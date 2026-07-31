-- Server-owned payroll draft preparation from canonical Attendance data.
--
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).
--
-- Forward behavior:
--   * diagnoses pre-existing duplicate non-voided tenant/week vouchers;
--   * enforces one non-voided voucher per tenant and exact weekly period;
--   * prepares an immutable draft snapshot from completed/approved Attendance,
--     current employee rates, and server-owned payment/account configuration;
--   * records an idempotency receipt before returning to the client; and
--   * removes authenticated access to the legacy non-versioned generator.
--
-- Recovery:
--   * revoke the v2 command and drop the partial unique index only after
--     verifying no client depends on them;
--   * the command itself creates no external/non-transactional side effects;
--   * exact operation-key replay is safe after a lost acknowledgement.

begin;

do $$
declare
  conflict_group_count integer;
  conflict_voucher_count integer;
  conflict_sample jsonb;
begin
  select
    count(*)::integer,
    coalesce(sum(conflict_group.voucher_count), 0)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'tenant_id', conflict_group.tenant_id,
          'period_start', conflict_group.period_start,
          'period_end', conflict_group.period_end,
          'voucher_count', conflict_group.voucher_count
        )
        order by
          conflict_group.period_start,
          conflict_group.period_end,
          conflict_group.tenant_id
      ),
      '[]'::jsonb
    )
  into
    conflict_group_count,
    conflict_voucher_count,
    conflict_sample
  from (
    select
      voucher.tenant_id,
      voucher.period_start,
      voucher.period_end,
      count(*)::integer as voucher_count
    from public.payroll_vouchers voucher
    where voucher.status <> 'voided'
    group by
      voucher.tenant_id,
      voucher.period_start,
      voucher.period_end
    having count(*) > 1
    order by
      voucher.period_start,
      voucher.period_end,
      voucher.tenant_id
    limit 50
  ) conflict_group;

  if conflict_group_count > 0 then
    raise exception 'payroll_voucher_period_conflicts_exist'
      using
        errcode = '23505',
        detail = jsonb_build_object(
          'conflict_groups_in_sample', conflict_group_count,
          'vouchers_in_sample', conflict_voucher_count,
          'sample', conflict_sample
        )::text,
        hint = 'Consolidate or void duplicate payroll vouchers before retrying this migration';
  end if;
end
$$;

create unique index if not exists
  ux_payroll_vouchers_tenant_week_non_voided
  on public.payroll_vouchers(tenant_id, period_start, period_end)
  where status <> 'voided';

create or replace function
  public.get_payroll_attendance_summary_for_period_v2(
    p_start_date date,
    p_end_date date
  )
returns table (
  employee_id uuid,
  employee_name text,
  total_hours numeric,
  overtime_hours numeric,
  total_days integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  store_timezone_value text;
  period_start_at_value timestamp with time zone;
  period_end_at_value timestamp with time zone;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_start_date is null
     or p_end_date is null
     or p_start_date not between date '1900-01-01' and date '2100-12-25'
     or p_end_date <> p_start_date + 6
     or extract(isodow from p_start_date)::integer <> 1
     or extract(isodow from p_end_date)::integer <> 7 then
    raise exception 'payroll_prepare_draft_invalid_week'
      using
        errcode = '22023',
        detail = 'Payroll periods must be one Monday-through-Sunday civil week';
  end if;

  select tenant.timezone
  into store_timezone_value
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if store_timezone_value is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone_value
     ) then
    raise exception 'payroll_prepare_draft_invalid_timezone'
      using errcode = '22023';
  end if;

  period_start_at_value :=
    p_start_date::timestamp without time zone
      at time zone store_timezone_value;
  period_end_at_value :=
    (p_end_date + 1)::timestamp without time zone
      at time zone store_timezone_value;

  return query
  select
    employee.id,
    trim(employee.first_name || ' ' || employee.last_name),
    round(
      coalesce(sum(coalesce(attendance.worked_hours, 0)), 0),
      2
    )::numeric,
    round(
      coalesce(sum(coalesce(attendance.overtime_hours, 0)), 0),
      2
    )::numeric,
    count(
      distinct (
        attendance.check_in at time zone store_timezone_value
      )::date
    )::integer
  from public.employees employee
  left join public.attendances attendance
    on attendance.employee_id = employee.id
   and attendance.tenant_id = employee.tenant_id
   and attendance.status in ('completed', 'approved')
   and attendance.check_in >= period_start_at_value
   and attendance.check_in < period_end_at_value
  where employee.tenant_id = tenant_id_value
    and employee.status = 'active'
  group by employee.id, employee.first_name, employee.last_name
  order by trim(employee.first_name || ' ' || employee.last_name);
end;
$$;

comment on function
  public.get_payroll_attendance_summary_for_period_v2(date, date)
is
  'Returns server-owned regular and overtime hours for a payroll-authorized weekly preview.';

revoke all on function
  public.get_payroll_attendance_summary_for_period_v2(date, date)
  from public, anon, authenticated, service_role;
grant execute on function
  public.get_payroll_attendance_summary_for_period_v2(date, date)
  to authenticated;

create or replace function public.prepare_payroll_voucher_draft_v2(
  p_start_date date,
  p_end_date date,
  p_period_label text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  period_label_value text := nullif(trim(p_period_label), '');
  resolved_period_label_value text;
  payload_hash_value text;
  existing_operation public.payroll_voucher_draft_operations%rowtype;
  existing_voucher record;
  voucher_id_value uuid := gen_random_uuid();
  voucher_number_value text;
  next_voucher_number_value integer;
  total_hours_value numeric(10,2);
  total_amount_value numeric(12,2);
  employee_count_value integer;
  line_count_value integer;
  reconciliation_version_value bigint;
  store_timezone_value text;
  period_start_at_value timestamp with time zone;
  period_end_at_value timestamp with time zone;
  receipt_value jsonb;
  violated_constraint_name text;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$' then
    raise exception 'payroll_prepare_draft_invalid_operation_key'
      using errcode = '22023';
  end if;

  if p_start_date is null
     or p_end_date is null
     or p_start_date not between date '1900-01-01' and date '2100-12-25'
     or p_end_date <> p_start_date + 6
     or extract(isodow from p_start_date)::integer <> 1
     or extract(isodow from p_end_date)::integer <> 7
     or char_length(coalesce(period_label_value, '')) > 200 then
    raise exception 'payroll_prepare_draft_invalid_week'
      using
        errcode = '22023',
        detail = 'Payroll periods must be one Monday-through-Sunday civil week';
  end if;

  resolved_period_label_value := coalesce(
    period_label_value,
    'Periodo: ' || p_start_date || ' - ' || p_end_date
  );

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'command', 'prepare_payroll_voucher_draft_v2',
          'contract_version', 2,
          'period_start', p_start_date,
          'period_end', p_end_date,
          'period_label', period_label_value
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  -- Serialize every payroll aggregate writer for this tenant. The partial
  -- unique index below remains the hard invariant for non-cooperating legacy
  -- writers and cross-session races.
  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select draft_operation.*
  into existing_operation
  from public.payroll_voucher_draft_operations draft_operation
  where draft_operation.tenant_id = tenant_id_value
    and draft_operation.operation_key = operation_key_value
  for update;

  if found then
    if existing_operation.payload_hash = payload_hash_value then
      return existing_operation.receipt;
    end if;
    raise exception 'payroll_prepare_draft_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already belongs to a different payroll draft payload';
  end if;

  select
    voucher.id,
    voucher.status,
    voucher.voucher_number
  into existing_voucher
  from public.payroll_vouchers voucher
  where voucher.tenant_id = tenant_id_value
    and voucher.period_start = p_start_date
    and voucher.period_end = p_end_date
    and voucher.status <> 'voided'
  order by voucher.id
  limit 1
  for update;

  if found then
    raise exception 'payroll_voucher_period_already_exists'
      using
        errcode = '23505',
        detail = jsonb_build_object(
          'voucher_id', existing_voucher.id,
          'voucher_number', existing_voucher.voucher_number,
          'status', existing_voucher.status,
          'period_start', p_start_date,
          'period_end', p_end_date
        )::text;
  end if;

  select tenant.timezone
  into store_timezone_value
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if store_timezone_value is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone_value
     ) then
    raise exception 'payroll_prepare_draft_invalid_timezone'
      using errcode = '22023';
  end if;

  period_start_at_value :=
    p_start_date::timestamp without time zone
      at time zone store_timezone_value;
  period_end_at_value :=
    (p_end_date + 1)::timestamp without time zone
      at time zone store_timezone_value;

  if exists (
    select 1
    from public.employees employee
    where employee.tenant_id = tenant_id_value
      and employee.status = 'active'
      and (
        coalesce(employee.hourly_rate, 0)::text
          in ('NaN', 'Infinity', '-Infinity')
        or coalesce(employee.hourly_rate, 0) not between 0 and 99999999.99
        or round(coalesce(employee.hourly_rate, 0), 2)
             <> coalesce(employee.hourly_rate, 0)
      )
  ) then
    raise exception 'payroll_prepare_draft_invalid_employee_rate'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.employees employee
    left join public.payment_methods payment_method
      on payment_method.id = employee.preferred_payment_method_id
     and payment_method.tenant_id = employee.tenant_id
    left join public.accounts payment_account
      on payment_account.id = payment_method.account_id
     and payment_account.tenant_id = payment_method.tenant_id
    where employee.tenant_id = tenant_id_value
      and employee.status = 'active'
      and employee.preferred_payment_method_id is not null
      and (
        payment_method.id is null
        or payment_account.id is null
        or payment_account.type <> 'asset'
      )
  ) then
    raise exception 'payroll_prepare_draft_invalid_payment_account'
      using
        errcode = '22023',
        detail = 'An active worker payment method must resolve to a tenant-owned asset account';
  end if;

  if exists (
    select 1
    from public.employees employee
    left join public.accounts salary_account
      on salary_account.id = employee.salary_account_id
     and salary_account.tenant_id = employee.tenant_id
    where employee.tenant_id = tenant_id_value
      and employee.status = 'active'
      and employee.salary_account_id is not null
      and (
        salary_account.id is null
        or salary_account.type <> 'expense'
      )
  ) then
    raise exception 'payroll_prepare_draft_invalid_salary_account'
      using
        errcode = '22023',
        detail = 'An active worker salary account must be a tenant-owned expense account';
  end if;

  select coalesce(
    max(
      substring(voucher.voucher_number from 5)::integer
    ) filter (
      where voucher.voucher_number ~ '^NOM-[0-9]+$'
    ),
    0
  ) + 1
  into next_voucher_number_value
  from public.payroll_vouchers voucher
  where voucher.tenant_id = tenant_id_value;

  voucher_number_value :=
    'NOM-' || lpad(next_voucher_number_value::text, 5, '0');

  insert into public.payroll_vouchers (
    id,
    tenant_id,
    voucher_number,
    period_start,
    period_end,
    period_label,
    total_hours,
    total_amount,
    employee_count,
    status,
    created_by
  )
  values (
    voucher_id_value,
    tenant_id_value,
    voucher_number_value,
    p_start_date,
    p_end_date,
    resolved_period_label_value,
    0,
    0,
    0,
    'draft',
    auth.uid()
  );

  with attendance_totals as (
    select
      attendance.employee_id,
      round(
        coalesce(sum(coalesce(attendance.worked_hours, 0)), 0),
        2
      )::numeric(10,2) as worked_hours,
      round(
        coalesce(sum(coalesce(attendance.overtime_hours, 0)), 0),
        2
      )::numeric(10,2) as overtime_hours
    from public.attendances attendance
    where attendance.tenant_id = tenant_id_value
      and attendance.status in ('completed', 'approved')
      and attendance.check_in >= period_start_at_value
      and attendance.check_in < period_end_at_value
    group by attendance.employee_id
  ),
  canonical_lines as (
    select
      employee.id as employee_id,
      trim(employee.first_name || ' ' || employee.last_name)
        as employee_name,
      coalesce(attendance_total.worked_hours, 0)::numeric(10,2)
        as worked_hours,
      coalesce(attendance_total.overtime_hours, 0)::numeric(10,2)
        as overtime_hours,
      round(coalesce(employee.hourly_rate, 0), 2)::numeric(10,2)
        as hourly_rate,
      round(coalesce(employee.hourly_rate, 0) * 1.5, 2)::numeric(10,2)
        as overtime_rate,
      coalesce(
        lower(nullif(trim(payment_method.code), '')),
        lower(nullif(trim(employee.preferred_payment_method::text), '')),
        'transfer'
      ) as payment_method,
      payment_method.id as payment_method_id,
      payment_method.account_id as payment_account_id,
      employee.salary_account_id,
      (
        coalesce(attendance_total.worked_hours, 0)
        + coalesce(attendance_total.overtime_hours, 0)
      ) > 0 as is_included
    from public.employees employee
    left join attendance_totals attendance_total
      on attendance_total.employee_id = employee.id
    left join public.payment_methods payment_method
      on payment_method.id = employee.preferred_payment_method_id
     and payment_method.tenant_id = employee.tenant_id
    where employee.tenant_id = tenant_id_value
      and employee.status = 'active'
  )
  insert into public.payroll_voucher_lines (
    id,
    tenant_id,
    voucher_id,
    employee_id,
    employee_name,
    worked_hours,
    overtime_hours,
    hourly_rate,
    overtime_rate,
    regular_amount,
    overtime_amount,
    total_amount,
    payment_method,
    payment_method_id,
    payment_account_id,
    salary_account_id,
    is_included
  )
  select
    gen_random_uuid(),
    tenant_id_value,
    voucher_id_value,
    canonical_line.employee_id,
    canonical_line.employee_name,
    canonical_line.worked_hours,
    canonical_line.overtime_hours,
    canonical_line.hourly_rate,
    canonical_line.overtime_rate,
    round(
      canonical_line.worked_hours * canonical_line.hourly_rate,
      2
    ),
    round(
      canonical_line.overtime_hours * canonical_line.overtime_rate,
      2
    ),
    round(
      canonical_line.worked_hours * canonical_line.hourly_rate,
      2
    ) + round(
      canonical_line.overtime_hours * canonical_line.overtime_rate,
      2
    ),
    canonical_line.payment_method,
    canonical_line.payment_method_id,
    canonical_line.payment_account_id,
    canonical_line.salary_account_id,
    canonical_line.is_included
  from canonical_lines canonical_line
  order by canonical_line.employee_name, canonical_line.employee_id;

  select
    coalesce(
      sum(voucher_line.worked_hours + voucher_line.overtime_hours)
        filter (where voucher_line.is_included),
      0
    )::numeric(10,2),
    coalesce(
      sum(voucher_line.total_amount)
        filter (where voucher_line.is_included),
      0
    )::numeric(12,2),
    count(*) filter (where voucher_line.is_included)::integer,
    count(*)::integer
  into
    total_hours_value,
    total_amount_value,
    employee_count_value,
    line_count_value
  from public.payroll_voucher_lines voucher_line
  where voucher_line.tenant_id = tenant_id_value
    and voucher_line.voucher_id = voucher_id_value;

  update public.payroll_vouchers voucher
  set total_hours = total_hours_value,
      total_amount = total_amount_value,
      employee_count = employee_count_value,
      updated_at = statement_timestamp()
  where voucher.id = voucher_id_value
    and voucher.tenant_id = tenant_id_value
  returning voucher.reconciliation_version
  into reconciliation_version_value;

  receipt_value := jsonb_build_object(
    'command', 'prepare_payroll_voucher_draft_v2',
    'contract_version', 2,
    'operation_key', operation_key_value,
    'payload_hash', payload_hash_value,
    'voucher_id', voucher_id_value,
    'voucher_number', voucher_number_value,
    'status', 'draft',
    'reconciliation_version', reconciliation_version_value,
    'period_start', p_start_date,
    'period_end', p_end_date,
    'period_label', resolved_period_label_value,
    'total_hours', total_hours_value,
    'total_amount', total_amount_value,
    'employee_count', employee_count_value,
    'line_count', line_count_value,
    'origin', jsonb_build_object(
      'kind', 'attendance',
      'projection', 'server_derived',
      'included_statuses', jsonb_build_array('completed', 'approved'),
      'timezone', store_timezone_value
    )
  );

  insert into public.payroll_voucher_draft_operations (
    tenant_id,
    operation_key,
    payload_hash,
    voucher_id,
    expected_reconciliation_version,
    receipt,
    created_by
  )
  values (
    tenant_id_value,
    operation_key_value,
    payload_hash_value,
    voucher_id_value,
    null,
    receipt_value,
    auth.uid()
  );

  return receipt_value;
exception
  when unique_violation then
    get stacked diagnostics
      violated_constraint_name = constraint_name;
    if violated_constraint_name =
         'ux_payroll_vouchers_tenant_week_non_voided' then
      raise exception 'payroll_voucher_period_already_exists'
        using
          errcode = '23505',
          detail = jsonb_build_object(
            'period_start', p_start_date,
            'period_end', p_end_date
          )::text;
    end if;
    raise;
end;
$$;

comment on function public.prepare_payroll_voucher_draft_v2(
  date,
  date,
  text,
  text
) is
  'Idempotently prepares one weekly payroll draft from server-owned Attendance, rate, payment-method, and account data.';

revoke all on function public.prepare_payroll_voucher_draft_v2(
  date,
  date,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_payroll_voucher_draft_v2(
  date,
  date,
  text,
  text
) to authenticated;

-- The unversioned generator has no operation receipt and cannot enforce exact
-- retry semantics. Keep the function for controlled rollback compatibility,
-- but remove it from every API role.
revoke all on function public.generate_payroll_voucher_draft(
  date,
  date,
  text
) from public, anon, authenticated, service_role;

commit;
