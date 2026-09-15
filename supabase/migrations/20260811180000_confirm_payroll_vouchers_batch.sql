begin;

-- Explicit batch approval for the final payroll payment desk.
-- Forward behavior: confirms one bounded set of draft vouchers atomically,
-- with tenant authorization, optimistic versions and an immutable receipt.
-- Recovery: additive only; an exact retry returns the stored receipt and any
-- failure rolls the complete batch back. No existing payroll rows are changed
-- by applying this migration.
-- Lock risk: brief additive DDL locks; calls serialize on the established
-- tenant payroll-settlement advisory lock and then lock vouchers in UUID order.
-- Validation: production-derived schema pgTAP 14/14 on 2026-08-11.
-- Deployment status: local candidate only; not applied to production.

create table if not exists
  public.payroll_voucher_confirmation_batch_operations (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null
      references public.tenants(id) on delete restrict,
    operation_key text not null
      check (char_length(operation_key) between 8 and 200),
    payload_hash text not null
      check (payload_hash ~ '^[0-9a-f]{64}$'),
    receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
    created_by uuid not null references auth.users(id),
    created_at timestamp with time zone not null default statement_timestamp(),
    unique (tenant_id, operation_key)
  );

alter table public.payroll_voucher_confirmation_batch_operations
  enable row level security;

revoke all on table
  public.payroll_voucher_confirmation_batch_operations
  from public, anon, authenticated, service_role;

create or replace function public.confirm_payroll_vouchers_v1(
  p_operation_key text,
  p_vouchers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  actor_id_value uuid := auth.uid();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  vouchers_value jsonb := coalesce(p_vouchers, 'null'::jsonb);
  voucher_value jsonb;
  voucher_ordinal_value integer;
  voucher_id_text_value text;
  voucher_id_value uuid;
  expected_version_numeric_value numeric;
  expected_version_value bigint;
  canonical_vouchers_value jsonb;
  payload_hash_value text;
  existing_operation
    public.payroll_voucher_confirmation_batch_operations%rowtype;
  confirmation_result_value boolean;
  receipt_value jsonb;
begin
  if tenant_id_value is null
     or actor_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or jsonb_typeof(vouchers_value) <> 'array' then
    raise exception 'payroll_voucher_batch_invalid_payload'
      using errcode = '22023';
  end if;

  if jsonb_array_length(vouchers_value) not between 1 and 100 then
    raise exception 'payroll_voucher_batch_invalid_payload'
      using errcode = '22023';
  end if;

  create temporary table if not exists
    pg_temp.payroll_voucher_confirmation_batch_input (
      voucher_ordinal integer primary key,
      voucher_id uuid not null unique,
      expected_reconciliation_version bigint not null
        check (expected_reconciliation_version >= 0)
    )
    on commit drop;
  truncate table pg_temp.payroll_voucher_confirmation_batch_input;

  for voucher_value, voucher_ordinal_value in
    select voucher_element.value, voucher_element.ordinality::integer
    from jsonb_array_elements(vouchers_value)
      with ordinality voucher_element(value, ordinality)
    order by voucher_element.ordinality
  loop
    if jsonb_typeof(voucher_value) <> 'object'
       or not (voucher_value ? 'voucher_id')
       or not (voucher_value ? 'expected_reconciliation_version')
       or exists (
         select 1
         from jsonb_object_keys(voucher_value) voucher_key
         where voucher_key not in (
           'voucher_id',
           'expected_reconciliation_version'
         )
       )
       or jsonb_typeof(
         voucher_value->'expected_reconciliation_version'
       ) <> 'number' then
      raise exception 'payroll_voucher_batch_invalid_item_%',
        voucher_ordinal_value
        using errcode = '22023';
    end if;

    voucher_id_text_value := voucher_value->>'voucher_id';
    if voucher_id_text_value is null
       or voucher_id_text_value !~* (
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
      || '[0-9a-f]{4}-[0-9a-f]{12}$'
    ) then
      raise exception 'payroll_voucher_batch_invalid_item_%',
        voucher_ordinal_value
        using errcode = '22023';
    end if;

    if (voucher_value->>'expected_reconciliation_version')
         !~ '^[0-9]{1,19}$' then
      raise exception 'payroll_voucher_batch_invalid_item_%',
        voucher_ordinal_value
        using errcode = '22023';
    end if;

    expected_version_numeric_value :=
      (voucher_value->>'expected_reconciliation_version')::numeric;
    if expected_version_numeric_value < 0
       or expected_version_numeric_value > 9223372036854775807::numeric
       or trunc(expected_version_numeric_value)
            <> expected_version_numeric_value then
      raise exception 'payroll_voucher_batch_invalid_item_%',
        voucher_ordinal_value
        using errcode = '22023';
    end if;

    voucher_id_value := voucher_id_text_value::uuid;
    expected_version_value := expected_version_numeric_value::bigint;

    begin
      insert into pg_temp.payroll_voucher_confirmation_batch_input (
        voucher_ordinal,
        voucher_id,
        expected_reconciliation_version
      )
      values (
        voucher_ordinal_value,
        voucher_id_value,
        expected_version_value
      );
    exception
      when unique_violation then
        raise exception 'payroll_voucher_batch_duplicate_voucher'
          using errcode = '23505';
    end;
  end loop;

  select jsonb_agg(
    jsonb_build_object(
      'voucher_id', batch_input.voucher_id,
      'expected_reconciliation_version',
        batch_input.expected_reconciliation_version
    )
    order by batch_input.voucher_id
  )
  into canonical_vouchers_value
  from pg_temp.payroll_voucher_confirmation_batch_input batch_input;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'command', 'confirm_drafts_batch',
          'vouchers', canonical_vouchers_value
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  -- Same tenant lock and lock order used by payroll settlement commands.
  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select batch_operation.*
  into existing_operation
  from public.payroll_voucher_confirmation_batch_operations batch_operation
  where batch_operation.tenant_id = tenant_id_value
    and batch_operation.operation_key = operation_key_value
  for update;

  if found then
    if existing_operation.payload_hash = payload_hash_value then
      return jsonb_set(
        existing_operation.receipt,
        '{replayed}',
        'true'::jsonb,
        true
      );
    end if;
    raise exception 'payroll_voucher_batch_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different payload';
  end if;

  perform voucher.id
  from public.payroll_vouchers voucher
  join pg_temp.payroll_voucher_confirmation_batch_input batch_input
    on batch_input.voucher_id = voucher.id
   and voucher.tenant_id = tenant_id_value
  order by voucher.id
  for update of voucher;

  if (
    select count(*)
    from public.payroll_vouchers voucher
    join pg_temp.payroll_voucher_confirmation_batch_input batch_input
      on batch_input.voucher_id = voucher.id
     and voucher.tenant_id = tenant_id_value
  ) <> jsonb_array_length(vouchers_value) then
    raise exception 'Payroll voucher not found'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.payroll_vouchers voucher
    join pg_temp.payroll_voucher_confirmation_batch_input batch_input
      on batch_input.voucher_id = voucher.id
    where voucher.tenant_id = tenant_id_value
      and voucher.status <> 'draft'
  ) then
    raise exception 'payroll_voucher_batch_contains_non_draft'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.payroll_vouchers voucher
    join pg_temp.payroll_voucher_confirmation_batch_input batch_input
      on batch_input.voucher_id = voucher.id
    where voucher.tenant_id = tenant_id_value
      and voucher.reconciliation_version
            <> batch_input.expected_reconciliation_version
  ) then
    raise exception 'payroll_voucher_batch_version_conflict'
      using
        errcode = '40001',
        detail = 'reload all payroll vouchers before confirming the batch';
  end if;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  join pg_temp.payroll_voucher_confirmation_batch_input batch_input
    on batch_input.voucher_id = voucher_line.voucher_id
  where voucher_line.tenant_id = tenant_id_value
  order by voucher_line.voucher_id, voucher_line.id
  for update of voucher_line;

  if exists (
    select 1
    from pg_temp.payroll_voucher_confirmation_batch_input batch_input
    where not exists (
      select 1
      from public.payroll_voucher_lines voucher_line
      where voucher_line.voucher_id = batch_input.voucher_id
        and voucher_line.tenant_id = tenant_id_value
        and voucher_line.is_included is true
        and voucher_line.total_amount > 0
    )
  ) then
    raise exception 'payroll_voucher_batch_has_no_positive_obligations'
      using errcode = '22023';
  end if;

  for voucher_id_value in
    select batch_input.voucher_id
    from pg_temp.payroll_voucher_confirmation_batch_input batch_input
    order by batch_input.voucher_id
  loop
    confirmation_result_value :=
      public.confirm_payroll_voucher_internal(voucher_id_value);
    if confirmation_result_value is distinct from true then
      raise exception 'payroll_voucher_batch_confirmation_not_committed'
        using errcode = '55000';
    end if;
  end loop;

  if exists (
    select 1
    from public.payroll_vouchers voucher
    join pg_temp.payroll_voucher_confirmation_batch_input batch_input
      on batch_input.voucher_id = voucher.id
    where voucher.tenant_id = tenant_id_value
      and voucher.status <> 'confirmed'
  ) then
    raise exception 'payroll_voucher_batch_confirmation_not_committed'
      using errcode = '55000';
  end if;

  receipt_value := jsonb_build_object(
    'operation', 'confirm_drafts_batch',
    'operation_key', operation_key_value,
    'payload_hash', payload_hash_value,
    'replayed', false,
    'confirmed_vouchers', (
      select jsonb_agg(
        jsonb_build_object(
          'voucher_id', voucher.id,
          'reconciliation_version', voucher.reconciliation_version,
          'status', voucher.status
        )
        order by voucher.id
      )
      from public.payroll_vouchers voucher
      join pg_temp.payroll_voucher_confirmation_batch_input batch_input
        on batch_input.voucher_id = voucher.id
      where voucher.tenant_id = tenant_id_value
    )
  );

  insert into public.payroll_voucher_confirmation_batch_operations (
    tenant_id,
    operation_key,
    payload_hash,
    receipt,
    created_by
  )
  values (
    tenant_id_value,
    operation_key_value,
    payload_hash_value,
    receipt_value,
    actor_id_value
  );

  return receipt_value;
end;
$$;

revoke all on function public.confirm_payroll_vouchers_v1(text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.confirm_payroll_vouchers_v1(text, jsonb)
  to authenticated;

comment on function public.confirm_payroll_vouchers_v1(text, jsonb) is
  'Atomically confirms a bounded explicit set of tenant-owned draft payroll vouchers using per-voucher optimistic versions and one idempotent receipt.';

commit;
