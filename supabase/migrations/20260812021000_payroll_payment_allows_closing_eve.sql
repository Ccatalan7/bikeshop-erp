-- Payroll periods close on the civil period_end date, while the last real
-- operating/payment day is the last open business day on or before that date
-- (for example, Saturday for a Sunday payroll close). A payment on that
-- operational close is part of the payroll settlement, not an advance.
--
-- Earlier civil dates still fail closed as advances. Statement evidence does
-- not override that boundary: evidence can prefill a payment, but it cannot
-- change whether the money predates the payroll settlement window.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.payroll_period_operational_close_date(
  p_tenant_id uuid,
  p_period_start date,
  p_period_end date
)
returns date
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_apply_to_payroll text;
  v_manual_raw text;
  v_google_raw text;
  v_raw text;
  v_root jsonb;
  v_data jsonb;
  v_period jsonb;
  v_open_weekdays integer[] := array[]::integer[];
  v_weekday integer;
  v_candidate date;
begin
  if p_tenant_id is null
     or p_period_start is null
     or p_period_end is null
     or p_period_start > p_period_end then
    return p_period_end;
  end if;

  select
    max(setting.value) filter (
      where setting.key = 'business_hours_apply_payroll'
    ),
    max(setting.value) filter (
      where setting.key = 'business_hours_json'
    ),
    max(setting.value) filter (
      where setting.key = 'google_business_regular_hours'
    )
  into v_apply_to_payroll, v_manual_raw, v_google_raw
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and setting.key in (
      'business_hours_apply_payroll',
      'business_hours_json',
      'google_business_regular_hours'
    );

  if lower(coalesce(trim(v_apply_to_payroll), 'true')) = 'false' then
    return p_period_end;
  end if;

  v_raw := case
    when nullif(trim(v_manual_raw), '') is not null then v_manual_raw
    else nullif(trim(v_google_raw), '')
  end;
  if v_raw is null then
    return p_period_end;
  end if;

  begin
    v_root := v_raw::jsonb;
  exception when others then
    return p_period_end;
  end;

  v_data := case
    when jsonb_typeof(v_root->'opening_hours') = 'object'
      then v_root->'opening_hours'
    else v_root
  end;

  if jsonb_typeof(v_data->'periods') <> 'array' then
    return p_period_end;
  end if;

  for v_period in
    select value
    from jsonb_array_elements(v_data->'periods')
  loop
    v_weekday := case upper(coalesce(v_period->>'openDay', ''))
      when 'MONDAY' then 1
      when 'TUESDAY' then 2
      when 'WEDNESDAY' then 3
      when 'THURSDAY' then 4
      when 'FRIDAY' then 5
      when 'SATURDAY' then 6
      when 'SUNDAY' then 7
      else null
    end;

    if v_weekday is null
       and (v_period->'open'->>'day') ~ '^[0-6]$' then
      v_weekday := case (v_period->'open'->>'day')::integer
        when 0 then 7
        else (v_period->'open'->>'day')::integer
      end;
    end if;

    if v_weekday is not null
       and not (v_weekday = any(v_open_weekdays)) then
      v_open_weekdays := array_append(v_open_weekdays, v_weekday);
    end if;
  end loop;

  if coalesce(array_length(v_open_weekdays, 1), 0) = 0 then
    return p_period_end;
  end if;

  v_candidate := p_period_end;
  while v_candidate >= p_period_start loop
    if extract(isodow from v_candidate)::integer = any(v_open_weekdays) then
      return v_candidate;
    end if;
    v_candidate := v_candidate - 1;
  end loop;

  return p_period_end;
end;
$$;

comment on function public.payroll_period_operational_close_date(
  uuid,
  date,
  date
)
is 'Returns the last open business day in a payroll period using the tenant business-hours settings when they apply to payroll; malformed, missing, disabled, or empty settings fail back to period_end.';

revoke all on function public.payroll_period_operational_close_date(
  uuid,
  date,
  date
) from public, anon, authenticated, service_role;

create or replace function public.payroll_payment_civil_date_requires_advance(
  p_tenant_id uuid,
  p_period_start date,
  p_period_end date,
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
      < public.payroll_period_operational_close_date(
          p_tenant_id,
          p_period_start,
          p_period_end
        ),
    true
  )
$$;

comment on function public.payroll_payment_civil_date_requires_advance(
  uuid,
  date,
  date,
  timestamptz
)
is 'Returns true only when a payroll payment civil date is earlier than the tenant operational payroll close; money on or after that close is settlement and earlier money must be modeled as an advance.';

revoke all on function public.payroll_payment_civil_date_requires_advance(
  uuid,
  date,
  date,
  timestamptz
) from public, anon, authenticated, service_role;

do $migration$
declare
  v_signature regprocedure :=
    to_regprocedure('public.pay_payroll_voucher_internal(uuid,jsonb)');
  v_definition text;
  v_old_guard constant text := $old$
        if v_payment_date < v_voucher.period_end::timestamp with time zone
           and not (
             v_payment_date
               >= v_voucher.period_start::timestamp with time zone
             and v_statement_payment_backed
           ) then
$old$;
  v_new_guard constant text := $new$
        if public.payroll_payment_civil_date_requires_advance(
             v_line.tenant_id,
             v_voucher.period_start,
             v_voucher.period_end,
             v_payment_date
           ) then
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
      'Unexpected pay_payroll_voucher_internal pre-close guard; refusing partial patch'
      using errcode = '55000';
  end if;

  v_definition := replace(v_definition, v_old_guard, v_new_guard);
  execute v_definition;
end;
$migration$;

comment on function public.pay_payroll_voucher_internal(uuid, jsonb)
is 'Canonical payroll settlement writer. Payment dates use tenant civil dates: the configured operational payroll close and later are settlement payments, earlier money must be recorded as an advance, and genuinely future tenant dates remain rejected.';

commit;
