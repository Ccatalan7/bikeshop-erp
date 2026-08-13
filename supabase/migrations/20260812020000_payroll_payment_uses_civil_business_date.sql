-- Deployment: pending production verification.
--
-- PayrollPaymentWorkspace transports an operator-selected civil date as UTC
-- noon. Comparing that transport timestamp with now() rejects an otherwise
-- valid "today" payment before 12:00 UTC. Payroll future-date policy therefore
-- compares the transported civil date with the tenant-owned business date.
--
-- This migration changes one function expression only. It has no backfill,
-- takes the ordinary brief catalog lock of CREATE OR REPLACE FUNCTION, and is
-- safe to replay. A future reversal must be another forward migration.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.payroll_payment_civil_date_is_future(
  p_tenant_id uuid,
  p_payment_date timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(
    public.tenant_business_date(p_tenant_id, p_payment_date)
      > public.tenant_business_date(p_tenant_id),
    true
  )
$$;

comment on function public.payroll_payment_civil_date_is_future(uuid, timestamptz)
is 'Validates the canonical UTC-noon PayrollCivilDate wire value against the tenant business date; same-day payroll payments are never future merely because their transport time is later than statement time.';

revoke all on function public.payroll_payment_civil_date_is_future(
  uuid,
  timestamptz
) from public, anon, authenticated, service_role;

do $migration$
declare
  v_signature regprocedure :=
    to_regprocedure('public.pay_payroll_voucher_internal(uuid,jsonb)');
  v_definition text;
  v_old_guard constant text := $old$
        if v_payment_date > now() + interval '5 minutes'
           and not v_statement_future_exception_backed then
$old$;
  v_new_guard constant text := $new$
        if public.payroll_payment_civil_date_is_future(
             v_line.tenant_id,
             v_payment_date
           )
           and not v_statement_future_exception_backed then
$new$;
begin
  if v_signature is null then
    raise exception 'pay_payroll_voucher_internal(uuid,jsonb) is missing'
      using errcode = '42883';
  end if;

  select pg_get_functiondef(v_signature)
  into v_definition;

  if position(v_new_guard in v_definition) > 0 then
    return;
  end if;

  if position(v_old_guard in v_definition) = 0 then
    raise exception
      'Unexpected pay_payroll_voucher_internal future-date guard; refusing partial patch'
      using errcode = '55000';
  end if;

  v_definition := replace(v_definition, v_old_guard, v_new_guard);
  execute v_definition;
end;
$migration$;

comment on function public.pay_payroll_voucher_internal(uuid, jsonb)
is 'Canonical payroll settlement writer. Payment dates are civil business dates: today is accepted regardless of the UTC-noon transport instant, while later tenant dates remain rejected.';

commit;
