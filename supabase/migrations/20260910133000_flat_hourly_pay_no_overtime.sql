-- Every worked hour is paid at the worker's hourly rate. There is no overtime.
--
-- Owner rule, 2026-09-10: «horas trabajadas, horas pagadas; ellos eligen qué
-- horas quieren trabajar». The 2025-12 attendance trigger assumed a Chilean
-- overtime tier instead: after a shift closed it compared the shift against a
-- scheduled day (contract weekly_hours / 5, else 9 h) and wrote the excess to
-- attendances.overtime_hours — while worked_hours already held the WHOLE
-- shift. Payroll then summed both and priced the excess again at 1.5×, so the
-- excess was paid twice. Real case: Vicente Díaz, 2026-09-04, 14:06–23:43 =
-- 9,63 h → worked 9,63 + overtime 0,63; the week showed «34,9 h × $3.500» next
-- to a total of $123.358 (34,30 × 3.500 + 0,63 × 5.250), an overpayment of
-- $3.307,50 on a draft that had not been paid.
--
-- Forward:
--   1. calculate_attendance_hours() keeps worked_hours = shift − break and
--      always writes overtime_hours = 0. The contract/work-schedule lookup is
--      gone (production has no active contract with weekly_hours anyway).
--   2. Backfill attendances.overtime_hours to 0 (9 rows, 9,73 h, 2025-12-19 →
--      2026-09-04). worked_hours already contains those hours.
--   3. Draft vouchers only: lines with overtime get overtime_hours =
--      overtime_amount = 0 and total_amount = regular_amount; their headers are
--      re-summed. One line today (NOM-00038, draft, no statement decisions or
--      allocations, so the reconciliation guard lets it through). Confirmed
--      and paid vouchers are never touched: none carried overtime.
--
-- Deliberately untouched: prepare_payroll_voucher_draft_v2,
-- generate_payroll_voucher_draft_internal and save_payroll_voucher_draft still
-- carry an overtime × 1.5 branch. With overtime_hours pinned to 0 at the
-- source that branch is dormant; rewriting three thousand-line commands and
-- their pgTAP for a branch that can no longer receive hours is a separate
-- decision. The draft editor never exposed an overtime field.
--
-- Idempotent. Lock: create or replace of a trigger function and three scoped
-- updates; lock_timeout 5s, rerun if busy. Recovery: none needed for the
-- rule; the prior split can be recomputed from check_in/check_out if a tier
-- is ever wanted again.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.calculate_attendance_hours()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_hours numeric(10,2);
begin
  -- Only calculate if check_out is set and check_in exists
  if NEW.check_out is not null and NEW.check_in is not null then
    v_hours := extract(epoch from (NEW.check_out - NEW.check_in)) / 3600.0;
    v_hours := round(v_hours - (coalesce(NEW.break_minutes, 0) / 60.0), 2);

    NEW.worked_hours := v_hours;

    -- Viñabike pays every hour at the worker's rate: there is no overtime
    -- tier. worked_hours already holds the whole shift, so anything written
    -- here was paid twice (inside worked_hours and again at 1.5×).
    NEW.overtime_hours := 0;

    -- Auto-complete status
    if NEW.status = 'ongoing' then
      NEW.status := 'completed';
    end if;
  end if;

  return NEW;
end;
$$;

revoke all on function public.calculate_attendance_hours()
  from public, anon, authenticated, service_role;

comment on function public.calculate_attendance_hours() is
  'Derives worked_hours from check_in/check_out minus break. Overtime is always 0: every hour is paid at the hourly rate (owner rule 2026-09-10).';

-- 2. Attendance history: the excess already lives inside worked_hours.
update public.attendances
   set overtime_hours = 0
 where overtime_hours <> 0;

-- 3. Draft vouchers only. The reconciliation guard raises on vouchers with
--    statement decisions or allocations; those are excluded explicitly so a
--    rerun can never trip it.
update public.payroll_voucher_lines line
   set overtime_hours = 0,
       overtime_amount = 0,
       total_amount = line.regular_amount
  from public.payroll_vouchers voucher
 where voucher.id = line.voucher_id
   and voucher.tenant_id = line.tenant_id
   and voucher.status = 'draft'
   and (line.overtime_hours <> 0 or line.overtime_amount <> 0)
   and not exists (
     select 1 from public.payroll_statement_decisions decision
      where decision.voucher_id = voucher.id
   )
   and not exists (
     select 1 from public.payroll_statement_allocations allocation
      where allocation.voucher_id = voucher.id
   );

update public.payroll_vouchers voucher
   set total_hours = totals.total_hours,
       total_amount = totals.total_amount
  from (
    select line.voucher_id,
           line.tenant_id,
           coalesce(sum(line.worked_hours + line.overtime_hours)
                      filter (where line.is_included), 0)::numeric(10,2)
             as total_hours,
           coalesce(sum(line.total_amount)
                      filter (where line.is_included), 0)::numeric(12,2)
             as total_amount
      from public.payroll_voucher_lines line
     group by line.voucher_id, line.tenant_id
  ) totals
 where totals.voucher_id = voucher.id
   and totals.tenant_id = voucher.tenant_id
   and voucher.status = 'draft'
   and (voucher.total_hours is distinct from totals.total_hours
        or voucher.total_amount is distinct from totals.total_amount)
   and not exists (
     select 1 from public.payroll_statement_decisions decision
      where decision.voucher_id = voucher.id
   )
   and not exists (
     select 1 from public.payroll_statement_allocations allocation
      where allocation.voucher_id = voucher.id
   );

commit;
