-- Pure SELECT read-back for 20260910133000_flat_hourly_pay_no_overtime.
-- Each statement divides by zero when the expected live state is absent.

-- 1. The trigger function pins overtime to 0 and no longer looks at contracts;
--    the trigger is still attached BEFORE INSERT OR UPDATE.
select 1/(case when
     pg_get_functiondef('public.calculate_attendance_hours()'::regprocedure)
       like '%NEW.overtime_hours := 0;%'
 and pg_get_functiondef('public.calculate_attendance_hours()'::regprocedure)
       not like '%weekly_hours%'
 and pg_get_functiondef('public.calculate_attendance_hours()'::regprocedure)
       like '%NEW.worked_hours := v_hours;%'
 and exists (
       select 1 from pg_trigger t
        where t.tgrelid = 'public.attendances'::regclass
          and t.tgname = 'trg_calculate_attendance_hours'
          and t.tgfoid = 'public.calculate_attendance_hours()'::regprocedure
          and t.tgenabled <> 'D'
          and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER trg_calculate_attendance_hours BEFORE INSERT OR UPDATE ON public.attendances FOR EACH ROW %')
 and (select p.prosecdef from pg_proc p where p.oid = 'public.calculate_attendance_hours()'::regprocedure)
 and not has_function_privilege('authenticated', 'public.calculate_attendance_hours()', 'execute')
 then 1 else 0 end) as attendance_trigger_pins_overtime_to_zero;

-- 2. No attendance carries overtime any more.
select 1/(case when count(*) = 0 then 1 else 0 end)
  as attendances_without_overtime
from public.attendances
where overtime_hours <> 0;

-- 3. Draft voucher lines: no overtime, and every line total equals its
--    regular amount.
select 1/(case when count(*) = 0 then 1 else 0 end)
  as draft_lines_flat
from public.payroll_voucher_lines line
join public.payroll_vouchers voucher on voucher.id = line.voucher_id
where voucher.status = 'draft'
  and (line.overtime_hours <> 0
       or line.overtime_amount <> 0
       or line.total_amount <> line.regular_amount);

-- 4. Draft voucher headers re-summed from their included lines.
select 1/(case when count(*) = 0 then 1 else 0 end)
  as draft_headers_match_lines
from public.payroll_vouchers voucher
join (
  select line.voucher_id,
         coalesce(sum(line.worked_hours + line.overtime_hours)
                    filter (where line.is_included), 0)::numeric(10,2) as hours,
         coalesce(sum(line.total_amount)
                    filter (where line.is_included), 0)::numeric(12,2) as amount
    from public.payroll_voucher_lines line
   group by line.voucher_id
) totals on totals.voucher_id = voucher.id
where voucher.status = 'draft'
  and (voucher.total_hours <> totals.hours
       or voucher.total_amount <> totals.amount);

-- 5. Confirmed and paid vouchers were never carrying overtime and still are not
--    (nothing outside drafts was touched).
select 1/(case when count(*) = 0 then 1 else 0 end)
  as non_draft_lines_untouched
from public.payroll_voucher_lines line
join public.payroll_vouchers voucher on voucher.id = line.voucher_id
where voucher.status <> 'draft'
  and (line.overtime_hours <> 0 or line.overtime_amount <> 0);
