begin;

-- The payment workspace is the canonical owner of payroll settlement intent.
-- OCR may hand over immutable statement observations, but it never posts money
-- and it never requires the operator to classify an entire statement.
-- Forward behavior: adds one atomic, tenant-scoped writer without backfilling
-- or changing existing payroll/statement rows.
-- Recovery: every apply is transactional and idempotent; a future audited
-- reversal must compensate posted results instead of mutating this evidence.
-- Lock risk: additive DDL takes brief catalog/table locks; the RPC itself uses
-- tenant/workspace/voucher advisory locks and bounded payload sizes.
-- Validation before deployment: production-derived pgTAP 19/19 on 2026-08-11.

create table if not exists public.payroll_payment_workspaces (
  id uuid primary key,
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  status text not null default 'draft'
    check (status in ('draft', 'applied', 'voided')),
  version bigint not null default 0 check (version >= 0),
  apply_operation_key text,
  apply_payload_hash text,
  apply_receipt jsonb,
  created_by uuid not null references auth.users(id),
  applied_by uuid references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  updated_at timestamp with time zone not null default statement_timestamp(),
  applied_at timestamp with time zone,
  unique (tenant_id, id),
  check (
    (
      status = 'draft'
      and apply_operation_key is null
      and apply_payload_hash is null
      and apply_receipt is null
      and applied_by is null
      and applied_at is null
    )
    or (
      status = 'applied'
      and apply_operation_key ~ '^[A-Za-z0-9:_-]{8,200}$'
      and apply_payload_hash ~ '^[0-9a-f]{64}$'
      and jsonb_typeof(apply_receipt) = 'object'
      and applied_by is not null
      and applied_at is not null
    )
    or status = 'voided'
  )
);

create unique index if not exists ux_payroll_payment_workspaces_operation
  on public.payroll_payment_workspaces(tenant_id, apply_operation_key)
  where apply_operation_key is not null;
create index if not exists idx_payroll_payment_workspaces_open
  on public.payroll_payment_workspaces(tenant_id, status, updated_at desc);

create table if not exists public.payroll_payment_workspace_legs (
  id uuid primary key,
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  workspace_id uuid not null,
  target_id uuid not null,
  concept_id uuid,
  target_ordinal integer not null check (target_ordinal between 1 and 500),
  leg_ordinal integer not null check (leg_ordinal between 1 and 500),
  leg_type text not null check (
    leg_type in ('salary_payment', 'salary_advance', 'additional_expense')
  ),
  funding_kind text check (
    funding_kind is null or funding_kind in ('bank', 'cash', 'other')
  ),
  voucher_id uuid references public.payroll_vouchers(id) on delete restrict,
  voucher_line_id uuid
    references public.payroll_voucher_lines(id) on delete restrict,
  advance_id uuid references public.employee_advances(id) on delete restrict,
  beneficiary_employee_id uuid
    references public.employees(id) on delete restrict,
  expense_account_id uuid references public.accounts(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  payment_method_id uuid
    references public.payment_methods(id) on delete restrict,
  payment_account_id uuid references public.accounts(id) on delete restrict,
  payment_date timestamp with time zone,
  reference text check (
    reference is null or char_length(reference) between 1 and 500
  ),
  description text check (
    description is null or char_length(description) between 1 and 500
  ),
  notes text check (notes is null or char_length(notes) between 1 and 2000),
  result_expense_id uuid references public.expenses(id) on delete restrict,
  result_expense_payment_id uuid unique
    references public.expense_payments(id) on delete restrict,
  result_advance_allocation_id uuid unique
    references public.employee_advance_allocations(id) on delete restrict,
  result_receipt jsonb not null check (jsonb_typeof(result_receipt) = 'object'),
  applied_by uuid not null references auth.users(id),
  applied_at timestamp with time zone not null default statement_timestamp(),
  created_at timestamp with time zone not null default statement_timestamp(),
  unique (tenant_id, id),
  unique (workspace_id, target_ordinal, leg_ordinal),
  unique (workspace_id, target_id, id),
  foreign key (tenant_id, workspace_id)
    references public.payroll_payment_workspaces(tenant_id, id)
    on delete restrict,
  check (
    (
      leg_type = 'salary_payment'
      and funding_kind is not null
      and voucher_id is not null
      and concept_id is null
      and voucher_line_id is not null
      and advance_id is null
      and expense_account_id is null
      and payment_method_id is not null
      and payment_account_id is not null
      and payment_date is not null
      and result_expense_id is not null
      and result_expense_payment_id is not null
      and result_advance_allocation_id is null
    )
    or (
      leg_type = 'salary_advance'
      and funding_kind is null
      and voucher_id is not null
      and concept_id is null
      and voucher_line_id is not null
      and advance_id is not null
      and expense_account_id is null
      and payment_method_id is null
      and payment_account_id is null
      and payment_date is null
      and result_expense_id is not null
      and result_expense_payment_id is null
      and result_advance_allocation_id is not null
    )
    or (
      leg_type = 'additional_expense'
      and funding_kind is not null
      and concept_id is not null
      and voucher_id is null
      and voucher_line_id is null
      and advance_id is null
      and expense_account_id is not null
      and payment_method_id is not null
      and payment_account_id is not null
      and payment_date is not null
      and description is not null
      and result_expense_id is not null
      and result_expense_payment_id is not null
      and result_advance_allocation_id is null
    )
  )
);

create index if not exists idx_payroll_payment_workspace_legs_workspace
  on public.payroll_payment_workspace_legs(workspace_id, target_ordinal, leg_ordinal);
create index if not exists idx_payroll_payment_workspace_legs_voucher
  on public.payroll_payment_workspace_legs(voucher_id, voucher_line_id)
  where voucher_id is not null;
create index if not exists idx_payroll_payment_workspace_legs_expense
  on public.payroll_payment_workspace_legs(result_expense_id);

create table if not exists public.payroll_payment_statement_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  workspace_id uuid not null,
  workspace_leg_id uuid not null,
  import_id uuid not null
    references public.payroll_statement_imports(id) on delete restrict,
  statement_row_id uuid not null
    references public.payroll_statement_rows(id) on delete restrict,
  row_fingerprint text not null check (row_fingerprint ~ '^[0-9a-f]{64}$'),
  observed_amount numeric(14,2) not null check (observed_amount > 0),
  allocated_amount numeric(14,2) not null check (allocated_amount > 0),
  result_expense_payment_id uuid not null
    references public.expense_payments(id) on delete restrict,
  applied_by uuid not null references auth.users(id),
  applied_at timestamp with time zone not null default statement_timestamp(),
  unique (workspace_leg_id, statement_row_id),
  foreign key (tenant_id, workspace_id)
    references public.payroll_payment_workspaces(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, workspace_leg_id)
    references public.payroll_payment_workspace_legs(tenant_id, id)
    on delete restrict
);

create index if not exists idx_payroll_payment_statement_allocations_row
  on public.payroll_payment_statement_allocations(
    tenant_id,
    statement_row_id
  );
create index if not exists idx_payroll_payment_statement_allocations_workspace
  on public.payroll_payment_statement_allocations(
    workspace_id,
    workspace_leg_id
  );

alter table public.payroll_payment_workspaces enable row level security;
alter table public.payroll_payment_workspace_legs enable row level security;
alter table public.payroll_payment_statement_allocations enable row level security;

drop policy if exists payroll_payment_workspaces_read_payroll
  on public.payroll_payment_workspaces;
create policy payroll_payment_workspaces_read_payroll
  on public.payroll_payment_workspaces
  for select to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));
drop policy if exists payroll_payment_workspace_legs_read_payroll
  on public.payroll_payment_workspace_legs;
create policy payroll_payment_workspace_legs_read_payroll
  on public.payroll_payment_workspace_legs
  for select to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));
drop policy if exists payroll_payment_statement_allocations_read_payroll
  on public.payroll_payment_statement_allocations;
create policy payroll_payment_statement_allocations_read_payroll
  on public.payroll_payment_statement_allocations
  for select to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

revoke all on table public.payroll_payment_workspaces
  from public, anon, authenticated, service_role;
revoke all on table public.payroll_payment_workspace_legs
  from public, anon, authenticated, service_role;
revoke all on table public.payroll_payment_statement_allocations
  from public, anon, authenticated, service_role;
grant select on table public.payroll_payment_workspaces to authenticated, service_role;
grant select on table public.payroll_payment_workspace_legs to authenticated, service_role;
grant select on table public.payroll_payment_statement_allocations
  to authenticated, service_role;

create or replace function public.guard_payroll_payment_workspace_result()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  result_is_owned boolean := false;
begin
  if tg_table_name = 'expense_payments' then
    select exists (
      select 1
      from public.payroll_payment_workspace_legs leg
      where leg.leg_type = 'additional_expense'
        and leg.result_expense_payment_id = old.id
    ) into result_is_owned;
  elsif tg_table_name = 'expense_lines' then
    select exists (
      select 1
      from public.payroll_payment_workspace_legs leg
      where leg.leg_type = 'additional_expense'
        and leg.result_expense_id = old.expense_id
    ) into result_is_owned;
  elsif tg_table_name = 'expenses' then
    select exists (
      select 1
      from public.payroll_payment_workspace_legs leg
      where leg.leg_type = 'additional_expense'
        and leg.result_expense_id = old.id
    ) into result_is_owned;
  end if;

  if result_is_owned then
    raise exception 'payroll_workspace_result_is_immutable'
      using
        errcode = '55000',
        detail = 'Use an audited reversal command instead of editing evidence';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_payroll_payment_workspace_result()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_payroll_workspace_expense_payment
  on public.expense_payments;
create trigger trg_guard_payroll_workspace_expense_payment
  before update or delete on public.expense_payments
  for each row execute function public.guard_payroll_payment_workspace_result();

drop trigger if exists trg_guard_payroll_workspace_expense_line
  on public.expense_lines;
create trigger trg_guard_payroll_workspace_expense_line
  before update or delete on public.expense_lines
  for each row execute function public.guard_payroll_payment_workspace_result();

drop trigger if exists trg_guard_payroll_workspace_expense
  on public.expenses;
create trigger trg_guard_payroll_workspace_expense
  before update or delete on public.expenses
  for each row execute function public.guard_payroll_payment_workspace_result();

create or replace function public.apply_payroll_payment_workspace_v1(
  p_workspace_id uuid,
  p_operation_key text,
  p_expected_workspace_version bigint,
  p_payload jsonb
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
  payload_value jsonb := coalesce(p_payload, '{}'::jsonb);
  payload_hash_value text;
  workspace_row public.payroll_payment_workspaces%rowtype;
  operation_workspace public.payroll_payment_workspaces%rowtype;
  statement_value jsonb := coalesce(p_payload->'statement', 'null'::jsonb);
  rows_value jsonb := coalesce(p_payload->'rows', 'null'::jsonb);
  salary_targets_value jsonb := coalesce(
    p_payload->'salary_targets',
    '[]'::jsonb
  );
  concepts_value jsonb := coalesce(
    p_payload->'additional_concepts',
    '[]'::jsonb
  );
  statement_file_digest_value text;
  statement_file_name_value text;
  statement_start_value date;
  statement_end_value date;
  statement_account_id_value uuid;
  statement_account_fingerprint_value text;
  statement_import_id_value uuid;
  statement_import_receipt_value jsonb;
  statement_is_new_value boolean := false;
  target_element record;
  leg_element record;
  concept_element record;
  evidence_element record;
  row_element record;
  target_value jsonb;
  leg_value jsonb;
  concept_value jsonb;
  evidence_value jsonb;
  row_value jsonb;
  target_id_value uuid;
  leg_id_value uuid;
  voucher_id_value uuid;
  voucher_line_id_value uuid;
  expected_voucher_version_value bigint;
  live_voucher_version_value bigint;
  leg_kind_value text;
  funding_kind_value text;
  amount_value numeric(14,2);
  concept_total_value numeric(14,2);
  concept_payment_legs_value jsonb;
  payment_method_id_value uuid;
  payment_account_id_value uuid;
  payment_date_value timestamp with time zone;
  reference_value text;
  description_value text;
  notes_value text;
  advance_id_value uuid;
  beneficiary_employee_id_value uuid;
  expense_account_id_value uuid;
  source_row_id_value text;
  evidence_import_id_value uuid;
  evidence_row_id_value uuid;
  evidence_amount_value numeric(14,2);
  salary_receipt_value jsonb;
  result_expense_id_value uuid;
  result_payment_id_value uuid;
  result_allocation_id_value uuid;
  expense_number_value text;
  expense_account_row public.accounts%rowtype;
  new_workspace_version_value bigint;
  receipt_value jsonb;
begin
  if tenant_id_value is null
     or actor_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll workspace access denied'
      using errcode = '42501';
  end if;

  if p_workspace_id is null
     or operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or p_expected_workspace_version is null
     or p_expected_workspace_version < 0
     or jsonb_typeof(payload_value) <> 'object'
     or pg_column_size(payload_value) > 1048576 then
    raise exception 'payroll_workspace_invalid_payload'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_object_keys(payload_value) payload_key
    where payload_key not in (
      'statement', 'rows', 'salary_targets', 'additional_concepts'
    )
  )
     or jsonb_typeof(salary_targets_value) <> 'array'
     or jsonb_typeof(concepts_value) <> 'array'
     or jsonb_array_length(salary_targets_value) > 200
     or jsonb_array_length(concepts_value) > 500
     or jsonb_array_length(salary_targets_value)
          + jsonb_array_length(concepts_value) > 500
     or (
       jsonb_array_length(salary_targets_value) = 0
       and jsonb_array_length(concepts_value) = 0
     ) then
    raise exception 'payroll_workspace_invalid_payload'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'workspace_id', p_workspace_id,
          'expected_workspace_version', p_expected_workspace_version,
          'payload', payload_value
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-payment-workspace:'
        || p_workspace_id::text,
      0
    )
  );

  select workspace.*
  into operation_workspace
  from public.payroll_payment_workspaces workspace
  where workspace.tenant_id = tenant_id_value
    and workspace.apply_operation_key = operation_key_value
  for update;

  if found then
    if operation_workspace.id = p_workspace_id
       and operation_workspace.apply_payload_hash = payload_hash_value
       and operation_workspace.status = 'applied' then
      return operation_workspace.apply_receipt
        || jsonb_build_object('replayed', true);
    end if;
    raise exception 'payroll_workspace_idempotency_conflict'
      using errcode = 'P0001';
  end if;

  select workspace.*
  into workspace_row
  from public.payroll_payment_workspaces workspace
  where workspace.id = p_workspace_id
    and workspace.tenant_id = tenant_id_value
  for update;

  if not found then
    if p_expected_workspace_version <> 0 then
      raise exception 'payroll_workspace_version_conflict'
        using errcode = '40001';
    end if;
    insert into public.payroll_payment_workspaces (
      id, tenant_id, status, version, created_by
    ) values (
      p_workspace_id, tenant_id_value, 'draft', 0, actor_id_value
    ) returning * into workspace_row;
  elsif workspace_row.status <> 'draft'
     or workspace_row.version <> p_expected_workspace_version then
    raise exception 'payroll_workspace_version_conflict'
      using errcode = '40001';
  end if;

  create temporary table if not exists pg_temp.payroll_workspace_inline_rows (
    source_row_id text primary key,
    row_ordinal integer not null,
    supplied_fingerprint text,
    transaction_date date,
    direction text,
    amount numeric(14,2),
    description_observed text,
    import_id uuid,
    row_id uuid
  ) on commit drop;
  truncate table pg_temp.payroll_workspace_inline_rows;

  create temporary table if not exists pg_temp.payroll_workspace_input_legs (
    leg_id uuid primary key,
    target_id uuid not null,
    concept_id uuid,
    target_ordinal integer not null,
    leg_ordinal integer not null,
    leg_type text not null,
    funding_kind text,
    voucher_id uuid,
    voucher_line_id uuid,
    expected_voucher_version bigint,
    advance_id uuid,
    beneficiary_employee_id uuid,
    expense_account_id uuid,
    amount numeric(14,2) not null,
    payment_method_id uuid,
    payment_account_id uuid,
    payment_date timestamp with time zone,
    reference text,
    description text,
    notes text,
    result_expense_id uuid,
    result_expense_payment_id uuid,
    result_advance_allocation_id uuid,
    result_receipt jsonb
  ) on commit drop;
  truncate table pg_temp.payroll_workspace_input_legs;

  create temporary table if not exists pg_temp.payroll_workspace_input_concepts (
    concept_id uuid primary key,
    target_ordinal integer not null,
    beneficiary_employee_id uuid,
    expense_account_id uuid not null,
    total_amount numeric(14,2) not null,
    description text not null,
    notes text,
    result_expense_id uuid,
    expense_number text
  ) on commit drop;
  truncate table pg_temp.payroll_workspace_input_concepts;

  create temporary table if not exists pg_temp.payroll_workspace_input_evidence (
    leg_id uuid not null,
    evidence_ordinal integer not null,
    source_row_id text,
    import_id uuid,
    row_id uuid,
    allocated_amount numeric(14,2) not null,
    primary key (leg_id, evidence_ordinal)
  ) on commit drop;
  truncate table pg_temp.payroll_workspace_input_evidence;

  if statement_value <> 'null'::jsonb or rows_value <> 'null'::jsonb then
    if jsonb_typeof(statement_value) <> 'object'
       or jsonb_typeof(rows_value) <> 'array'
       or jsonb_array_length(rows_value) not between 1 and 2000
       or exists (
         select 1 from jsonb_object_keys(statement_value) statement_key
         where statement_key not in (
           'filename', 'file_digest', 'statement_start', 'statement_end',
           'account_id', 'account_fingerprint', 'parser_name',
           'parser_version', 'source_type'
         )
       ) then
      raise exception 'payroll_workspace_invalid_statement_evidence'
        using errcode = '22023';
    end if;

    statement_file_name_value :=
      nullif(trim(statement_value->>'filename'), '');
    statement_file_digest_value :=
      lower(trim(coalesce(statement_value->>'file_digest', '')));
    statement_start_value :=
      nullif(statement_value->>'statement_start', '')::date;
    statement_end_value :=
      nullif(statement_value->>'statement_end', '')::date;
    statement_account_id_value :=
      nullif(statement_value->>'account_id', '')::uuid;
    statement_account_fingerprint_value := lower(
      nullif(trim(statement_value->>'account_fingerprint'), '')
    );
    if statement_account_fingerprint_value is null then
      statement_account_fingerprint_value := encode(
        extensions.digest(
          convert_to(
            tenant_id_value::text || ':'
              || statement_account_id_value::text,
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      );
    end if;

    if char_length(coalesce(statement_file_name_value, '')) > 255
       or statement_file_digest_value !~ '^[0-9a-f]{64}$'
       or statement_account_fingerprint_value !~ '^[0-9a-f]{64}$'
       or statement_start_value is null
       or statement_start_value not between date '1900-01-01'
            and date '2100-12-31'
       or statement_end_value not between statement_start_value
            and date '2100-12-31'
       or not exists (
         select 1 from public.accounts account
         where account.id = statement_account_id_value
           and account.tenant_id = tenant_id_value
           and account.type = 'asset'
           and account.is_active is true
       ) then
      raise exception 'payroll_workspace_invalid_statement_evidence'
        using errcode = '22023';
    end if;

    for row_element in
      select row_item.value, row_item.ordinality
      from jsonb_array_elements(rows_value)
        with ordinality row_item(value, ordinality)
      order by row_item.ordinality
    loop
      row_value := row_element.value;
      if jsonb_typeof(row_value) <> 'object'
         or exists (
           select 1 from jsonb_object_keys(row_value) row_key
           where row_key not in (
             'source_row_id', 'fingerprint', 'ordinal',
             'transaction_date', 'date', 'direction', 'amount',
             'description', 'description_observed',
             'beneficiary_observed', 'document_observed', 'warnings'
           )
         ) then
        raise exception 'payroll_workspace_invalid_inline_row'
          using errcode = '22023';
      end if;

      source_row_id_value := nullif(trim(row_value->>'source_row_id'), '');
      if source_row_id_value is null
         or char_length(source_row_id_value) > 100 then
        raise exception 'payroll_workspace_invalid_inline_row'
          using errcode = '22023';
      end if;

      insert into pg_temp.payroll_workspace_inline_rows (
        source_row_id,
        row_ordinal,
        supplied_fingerprint,
        transaction_date,
        direction,
        amount,
        description_observed
      ) values (
        source_row_id_value,
        coalesce(
          nullif(row_value->>'ordinal', '')::integer,
          row_element.ordinality::integer
        ),
        lower(nullif(trim(row_value->>'fingerprint'), '')),
        nullif(
          coalesce(row_value->>'transaction_date', row_value->>'date'),
          ''
        )::date,
        lower(nullif(trim(row_value->>'direction'), '')),
        nullif(row_value->>'amount', '')::numeric,
        nullif(trim(coalesce(
          row_value->>'description_observed',
          row_value->>'description'
        )), '')
      );
    end loop;

    if exists (
      select 1 from pg_temp.payroll_workspace_inline_rows inline_row
      where inline_row.row_ordinal not between 1 and 2000
         or inline_row.transaction_date is null
         or inline_row.direction not in ('debit', 'credit')
         or inline_row.amount is null
         or inline_row.amount <= 0
         or round(inline_row.amount, 2) <> inline_row.amount
         or inline_row.description_observed is null
         or char_length(inline_row.description_observed) > 500
         or (
           inline_row.supplied_fingerprint is not null
           and inline_row.supplied_fingerprint !~ '^[0-9a-f]{64}$'
         )
    ) or exists (
      select 1
      from pg_temp.payroll_workspace_inline_rows inline_row
      group by inline_row.row_ordinal
      having count(*) > 1
    ) then
      raise exception 'payroll_workspace_invalid_inline_row'
        using errcode = '22023';
    end if;

    select statement_import.id
    into statement_import_id_value
    from public.payroll_statement_imports statement_import
    where statement_import.tenant_id = tenant_id_value
      and statement_import.file_sha256 = statement_file_digest_value
    for update;

    if found then
      if not exists (
        select 1 from public.payroll_statement_imports statement_import
        where statement_import.id = statement_import_id_value
          and statement_import.tenant_id = tenant_id_value
          and statement_import.erp_account_id = statement_account_id_value
          and statement_import.account_fingerprint =
              statement_account_fingerprint_value
          and statement_import.status = 'review'
          and nullif(
            statement_import.source_metadata->>'statement_start', ''
          )::date = statement_start_value
          and nullif(
            statement_import.source_metadata->>'statement_end', ''
          )::date = statement_end_value
      ) then
        raise exception 'payroll_workspace_statement_import_conflict'
          using errcode = '40001';
      end if;
    else
      statement_import_receipt_value :=
        public.create_payroll_statement_import(
          'workspace:evidence:' || substr(payload_hash_value, 1, 40),
          statement_file_digest_value,
          jsonb_strip_nulls(jsonb_build_object(
            'parser_name', coalesce(
              nullif(trim(statement_value->>'parser_name'), ''),
              'payroll_payment_workspace'
            ),
            'parser_version', coalesce(
              nullif(trim(statement_value->>'parser_version'), ''),
              '1'
            ),
            'source_type', coalesce(
              nullif(lower(trim(statement_value->>'source_type')), ''),
              'pdf_ocr'
            ),
            'statement_start', statement_start_value,
            'statement_end', statement_end_value,
            'account_fingerprint', statement_account_fingerprint_value,
            'erp_account_id', statement_account_id_value
          )),
          (
            select jsonb_agg(
              jsonb_strip_nulls(
                row_item.value
                - 'source_row_id'
                - 'date'
                - 'description'
                || jsonb_build_object(
                  'ordinal', inline_row.row_ordinal,
                  'transaction_date', inline_row.transaction_date,
                  'direction', inline_row.direction,
                  'amount', inline_row.amount,
                  'description_observed',
                    inline_row.description_observed
                )
              )
              order by inline_row.row_ordinal
            )
            from jsonb_array_elements(rows_value)
              with ordinality row_item(value, ordinality)
            join pg_temp.payroll_workspace_inline_rows inline_row
              on inline_row.source_row_id =
                  trim(row_item.value->>'source_row_id')
          )
        );
      statement_import_id_value :=
        (statement_import_receipt_value->>'import_id')::uuid;
      statement_is_new_value := true;
    end if;

    update pg_temp.payroll_workspace_inline_rows inline_row
    set import_id = statement_import_id_value,
        row_id = statement_row.id
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = statement_import_id_value
      and statement_row.tenant_id = tenant_id_value
      and (
        (
          inline_row.supplied_fingerprint is not null
          and statement_row.fingerprint = inline_row.supplied_fingerprint
        )
        or (
          inline_row.supplied_fingerprint is null
          and statement_row.row_ordinal = inline_row.row_ordinal
        )
      )
      and statement_row.transaction_date = inline_row.transaction_date
      and statement_row.direction = inline_row.direction
      and statement_row.amount = inline_row.amount
      and statement_row.description_normalized =
          public.normalize_payroll_statement_text(
            inline_row.description_observed
          );

    if exists (
      select 1 from pg_temp.payroll_workspace_inline_rows inline_row
      where inline_row.row_id is null
    ) then
      raise exception 'payroll_workspace_inline_row_mismatch'
        using errcode = '22023';
    end if;
  end if;

  for target_element in
    select target_item.value, target_item.ordinality
    from jsonb_array_elements(salary_targets_value)
      with ordinality target_item(value, ordinality)
    order by target_item.ordinality
  loop
    target_value := target_element.value;
    if jsonb_typeof(target_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(target_value) target_key
         where target_key not in (
           'target_id', 'voucher_id', 'expected_reconciliation_version',
           'legs'
         )
       )
       or jsonb_typeof(target_value->'legs') <> 'array'
       or jsonb_array_length(target_value->'legs') not between 1 and 100 then
      raise exception 'payroll_workspace_invalid_salary_target'
        using errcode = '22023';
    end if;

    target_id_value := nullif(target_value->>'target_id', '')::uuid;
    voucher_id_value := nullif(target_value->>'voucher_id', '')::uuid;
    expected_voucher_version_value :=
      nullif(target_value->>'expected_reconciliation_version', '')::bigint;
    if target_id_value is null
       or voucher_id_value is null
       or expected_voucher_version_value is null
       or expected_voucher_version_value < 0 then
      raise exception 'payroll_workspace_invalid_salary_target'
        using errcode = '22023';
    end if;

    for leg_element in
      select leg_item.value, leg_item.ordinality
      from jsonb_array_elements(target_value->'legs')
        with ordinality leg_item(value, ordinality)
      order by leg_item.ordinality
    loop
      leg_value := leg_element.value;
      if jsonb_typeof(leg_value) <> 'object'
         or exists (
           select 1 from jsonb_object_keys(leg_value) leg_key
           where leg_key not in (
             'leg_id', 'voucher_line_id', 'kind', 'funding_kind',
             'amount', 'payment_method_id', 'payment_account_id',
             'payment_date', 'reference', 'notes', 'advance_id',
             'evidence'
           )
         ) then
        raise exception 'payroll_workspace_invalid_salary_leg'
          using errcode = '22023';
      end if;

      leg_id_value := nullif(leg_value->>'leg_id', '')::uuid;
      voucher_line_id_value :=
        nullif(leg_value->>'voucher_line_id', '')::uuid;
      leg_kind_value := lower(trim(coalesce(leg_value->>'kind', 'payment')));
      amount_value := nullif(leg_value->>'amount', '')::numeric;
      funding_kind_value :=
        lower(nullif(trim(leg_value->>'funding_kind'), ''));
      payment_method_id_value :=
        nullif(leg_value->>'payment_method_id', '')::uuid;
      payment_account_id_value :=
        nullif(leg_value->>'payment_account_id', '')::uuid;
      payment_date_value :=
        nullif(leg_value->>'payment_date', '')::timestamptz;
      reference_value := nullif(trim(leg_value->>'reference'), '');
      notes_value := nullif(trim(leg_value->>'notes'), '');
      advance_id_value := nullif(leg_value->>'advance_id', '')::uuid;

      if leg_id_value is null
         or voucher_line_id_value is null
         or leg_kind_value not in ('payment', 'advance')
         or amount_value is null
         or amount_value <= 0
         or round(amount_value, 2) <> amount_value
         or amount_value > 999999999999.99
         or char_length(coalesce(reference_value, '')) > 500
         or char_length(coalesce(notes_value, '')) > 2000
         or (
           leg_kind_value = 'payment'
           and (
             funding_kind_value not in ('bank', 'cash', 'other')
             or payment_method_id_value is null
             or payment_account_id_value is null
             or payment_date_value is null
             or trim(leg_value->>'payment_date')
                  !~* '(Z|[+-][0-9]{2}(:[0-9]{2})?)$'
             or advance_id_value is not null
           )
         )
         or (
           leg_kind_value = 'advance'
           and (
             funding_kind_value is not null
             or payment_method_id_value is not null
             or payment_account_id_value is not null
             or payment_date_value is not null
             or advance_id_value is null
           )
         ) then
        raise exception 'payroll_workspace_invalid_salary_leg'
          using errcode = '22023';
      end if;

      insert into pg_temp.payroll_workspace_input_legs (
        leg_id, target_id, target_ordinal, leg_ordinal, leg_type,
        funding_kind, voucher_id, voucher_line_id,
        expected_voucher_version, advance_id, amount,
        payment_method_id, payment_account_id, payment_date,
        reference, notes
      ) values (
        leg_id_value, target_id_value, target_element.ordinality,
        leg_element.ordinality,
        case when leg_kind_value = 'payment'
          then 'salary_payment' else 'salary_advance' end,
        funding_kind_value, voucher_id_value, voucher_line_id_value,
        expected_voucher_version_value, advance_id_value, amount_value,
        payment_method_id_value, payment_account_id_value,
        payment_date_value, reference_value, notes_value
      );

      if leg_value ? 'evidence' then
        if jsonb_typeof(leg_value->'evidence') <> 'array'
           or jsonb_array_length(leg_value->'evidence') > 100 then
          raise exception 'payroll_workspace_invalid_evidence_allocation'
            using errcode = '22023';
        end if;
        for evidence_element in
          select evidence_item.value, evidence_item.ordinality
          from jsonb_array_elements(leg_value->'evidence')
            with ordinality evidence_item(value, ordinality)
          order by evidence_item.ordinality
        loop
          evidence_value := evidence_element.value;
          source_row_id_value :=
            nullif(trim(evidence_value->>'source_row_id'), '');
          evidence_import_id_value :=
            nullif(evidence_value->>'import_id', '')::uuid;
          evidence_row_id_value :=
            nullif(evidence_value->>'row_id', '')::uuid;
          evidence_amount_value :=
            nullif(evidence_value->>'amount', '')::numeric;
          if jsonb_typeof(evidence_value) <> 'object'
             or exists (
               select 1 from jsonb_object_keys(evidence_value) evidence_key
               where evidence_key not in (
                 'source_row_id', 'import_id', 'row_id', 'amount'
               )
             )
             or ((source_row_id_value is null) = (evidence_row_id_value is null))
             or (evidence_row_id_value is not null and evidence_import_id_value is null)
             or evidence_amount_value is null
             or evidence_amount_value <= 0
             or round(evidence_amount_value, 2) <> evidence_amount_value then
            raise exception 'payroll_workspace_invalid_evidence_allocation'
              using errcode = '22023';
          end if;
          insert into pg_temp.payroll_workspace_input_evidence (
            leg_id, evidence_ordinal, source_row_id, import_id, row_id,
            allocated_amount
          ) values (
            leg_id_value, evidence_element.ordinality, source_row_id_value,
            evidence_import_id_value, evidence_row_id_value,
            evidence_amount_value
          );
        end loop;
      end if;
    end loop;
  end loop;

  for concept_element in
    select concept_item.value, concept_item.ordinality
    from jsonb_array_elements(concepts_value)
      with ordinality concept_item(value, ordinality)
    order by concept_item.ordinality
  loop
    concept_value := concept_element.value;
    if jsonb_typeof(concept_value) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(concept_value) concept_key
         where concept_key not in (
           'concept_id', 'beneficiary_employee_id', 'expense_account_id',
           'amount', 'description', 'notes', 'payment_legs'
         )
       )
       or jsonb_typeof(concept_value->'payment_legs') <> 'array'
       or jsonb_array_length(concept_value->'payment_legs')
            not between 1 and 100 then
      raise exception 'payroll_workspace_invalid_additional_concept'
        using errcode = '22023';
    end if;

    target_id_value := nullif(concept_value->>'concept_id', '')::uuid;
    beneficiary_employee_id_value :=
      nullif(concept_value->>'beneficiary_employee_id', '')::uuid;
    expense_account_id_value :=
      nullif(concept_value->>'expense_account_id', '')::uuid;
    concept_total_value := nullif(concept_value->>'amount', '')::numeric;
    description_value := nullif(trim(concept_value->>'description'), '');
    notes_value := nullif(trim(concept_value->>'notes'), '');
    concept_payment_legs_value := concept_value->'payment_legs';

    if target_id_value is null
       or expense_account_id_value is null
       or concept_total_value is null
       or concept_total_value <= 0
       or round(concept_total_value, 2) <> concept_total_value
       or concept_total_value > 999999999999.99
       or description_value is null
       or char_length(description_value) > 500
       or char_length(coalesce(notes_value, '')) > 2000 then
      raise exception 'payroll_workspace_invalid_additional_concept'
        using errcode = '22023';
    end if;

    insert into pg_temp.payroll_workspace_input_concepts (
      concept_id, target_ordinal, beneficiary_employee_id,
      expense_account_id, total_amount, description, notes
    ) values (
      target_id_value,
      jsonb_array_length(salary_targets_value) + concept_element.ordinality,
      beneficiary_employee_id_value, expense_account_id_value,
      concept_total_value, description_value, notes_value
    );

    for leg_element in
      select leg_item.value, leg_item.ordinality
      from jsonb_array_elements(concept_payment_legs_value)
        with ordinality leg_item(value, ordinality)
      order by leg_item.ordinality
    loop
      leg_value := leg_element.value;
      if jsonb_typeof(leg_value) <> 'object'
         or exists (
           select 1 from jsonb_object_keys(leg_value) leg_key
           where leg_key not in (
             'leg_id', 'amount', 'funding_kind', 'payment_method_id',
             'payment_account_id', 'payment_date', 'reference', 'notes',
             'evidence'
           )
         ) then
        raise exception 'payroll_workspace_invalid_additional_concept_leg'
          using errcode = '22023';
      end if;

      leg_id_value := nullif(leg_value->>'leg_id', '')::uuid;
      amount_value := nullif(leg_value->>'amount', '')::numeric;
      funding_kind_value :=
        lower(nullif(trim(leg_value->>'funding_kind'), ''));
      payment_method_id_value :=
        nullif(leg_value->>'payment_method_id', '')::uuid;
      payment_account_id_value :=
        nullif(leg_value->>'payment_account_id', '')::uuid;
      payment_date_value :=
        nullif(leg_value->>'payment_date', '')::timestamptz;
      reference_value := nullif(trim(leg_value->>'reference'), '');
      notes_value := nullif(trim(leg_value->>'notes'), '');

      if leg_id_value is null
         or amount_value is null
         or amount_value <= 0
         or round(amount_value, 2) <> amount_value
         or amount_value > 999999999999.99
         or funding_kind_value not in ('bank', 'cash', 'other')
         or payment_method_id_value is null
         or payment_account_id_value is null
         or payment_date_value is null
         or trim(leg_value->>'payment_date')
              !~* '(Z|[+-][0-9]{2}(:[0-9]{2})?)$'
         or char_length(coalesce(reference_value, '')) > 500
         or char_length(coalesce(notes_value, '')) > 2000 then
        raise exception 'payroll_workspace_invalid_additional_concept_leg'
          using errcode = '22023';
      end if;

      insert into pg_temp.payroll_workspace_input_legs (
        leg_id, target_id, concept_id, target_ordinal, leg_ordinal,
        leg_type, funding_kind, beneficiary_employee_id,
        expense_account_id, amount, payment_method_id, payment_account_id,
        payment_date, reference, description, notes
      ) values (
        leg_id_value, target_id_value, target_id_value,
        jsonb_array_length(salary_targets_value)
          + concept_element.ordinality,
        leg_element.ordinality, 'additional_expense', funding_kind_value,
        beneficiary_employee_id_value, expense_account_id_value,
        amount_value, payment_method_id_value, payment_account_id_value,
        payment_date_value, reference_value, description_value,
        coalesce(notes_value,
          (select concept.notes
           from pg_temp.payroll_workspace_input_concepts concept
           where concept.concept_id = target_id_value))
      );

      if leg_value ? 'evidence' then
        if jsonb_typeof(leg_value->'evidence') <> 'array'
           or jsonb_array_length(leg_value->'evidence') > 100 then
          raise exception 'payroll_workspace_invalid_evidence_allocation'
            using errcode = '22023';
        end if;
        for evidence_element in
          select evidence_item.value, evidence_item.ordinality
          from jsonb_array_elements(leg_value->'evidence')
            with ordinality evidence_item(value, ordinality)
          order by evidence_item.ordinality
        loop
          evidence_value := evidence_element.value;
          source_row_id_value :=
            nullif(trim(evidence_value->>'source_row_id'), '');
          evidence_import_id_value :=
            nullif(evidence_value->>'import_id', '')::uuid;
          evidence_row_id_value :=
            nullif(evidence_value->>'row_id', '')::uuid;
          evidence_amount_value :=
            nullif(evidence_value->>'amount', '')::numeric;
          if jsonb_typeof(evidence_value) <> 'object'
             or exists (
               select 1 from jsonb_object_keys(evidence_value) evidence_key
               where evidence_key not in (
                 'source_row_id', 'import_id', 'row_id', 'amount'
               )
             )
             or ((source_row_id_value is null) = (evidence_row_id_value is null))
             or (evidence_row_id_value is not null and evidence_import_id_value is null)
             or evidence_amount_value is null
             or evidence_amount_value <= 0
             or round(evidence_amount_value, 2) <> evidence_amount_value then
            raise exception 'payroll_workspace_invalid_evidence_allocation'
              using errcode = '22023';
          end if;
          insert into pg_temp.payroll_workspace_input_evidence (
            leg_id, evidence_ordinal, source_row_id, import_id, row_id,
            allocated_amount
          ) values (
            leg_id_value, evidence_element.ordinality,
            source_row_id_value, evidence_import_id_value,
            evidence_row_id_value, evidence_amount_value
          );
        end loop;
      end if;
    end loop;
  end loop;

  if exists (
    select 1
    from pg_temp.payroll_workspace_input_concepts concept
    left join pg_temp.payroll_workspace_input_legs leg
      on leg.concept_id = concept.concept_id
    group by concept.concept_id, concept.total_amount
    having coalesce(sum(leg.amount), 0) <> concept.total_amount
  ) then
    raise exception 'payroll_workspace_concept_payment_total_mismatch'
      using errcode = '23514';
  end if;

  if (select count(*) from pg_temp.payroll_workspace_input_legs) > 500
     or exists (
       select 1
       from pg_temp.payroll_workspace_input_legs leg
       group by leg.target_id
       having min(leg.target_ordinal) <> max(leg.target_ordinal)
     )
     or exists (
       select 1
       from pg_temp.payroll_workspace_input_legs salary_leg
       where salary_leg.voucher_id is not null
       group by salary_leg.voucher_id
       having count(distinct salary_leg.expected_voucher_version) > 1
     ) then
    raise exception 'payroll_workspace_duplicate_target_or_limit'
      using errcode = '22023';
  end if;

  -- Resolve inline evidence IDs only after every leg is structurally valid.
  update pg_temp.payroll_workspace_input_evidence evidence
  set import_id = inline_row.import_id,
      row_id = inline_row.row_id
  from pg_temp.payroll_workspace_inline_rows inline_row
  where evidence.source_row_id = inline_row.source_row_id;

  if exists (
    select 1 from pg_temp.payroll_workspace_input_evidence evidence
    where evidence.row_id is null or evidence.import_id is null
  ) then
    raise exception 'payroll_workspace_evidence_row_not_found'
      using errcode = '42501';
  end if;

  perform statement_row.id
  from public.payroll_statement_rows statement_row
  where statement_row.tenant_id = tenant_id_value
    and statement_row.id in (
      select evidence.row_id
      from pg_temp.payroll_workspace_input_evidence evidence
    )
  order by statement_row.id
  for update;

  if exists (
    select 1
    from pg_temp.payroll_workspace_input_evidence evidence
    join pg_temp.payroll_workspace_input_legs leg
      on leg.leg_id = evidence.leg_id
    left join public.payroll_statement_rows statement_row
      on statement_row.id = evidence.row_id
     and statement_row.import_id = evidence.import_id
     and statement_row.tenant_id = tenant_id_value
    left join public.payroll_statement_imports statement_import
      on statement_import.id = statement_row.import_id
     and statement_import.tenant_id = statement_row.tenant_id
    where statement_row.id is null
       or statement_import.status <> 'review'
       or statement_row.direction <> 'debit'
       or statement_row.amount is null
       or statement_row.transaction_date is null
       or statement_import.erp_account_id <> leg.payment_account_id
       or leg.leg_type = 'salary_advance'
       or leg.funding_kind <> 'bank'
  ) or exists (
    select 1
    from pg_temp.payroll_workspace_input_evidence evidence
    group by evidence.leg_id, evidence.row_id
    having count(*) > 1
  ) or exists (
    select 1
    from pg_temp.payroll_workspace_input_evidence evidence
    group by evidence.leg_id
    having sum(evidence.allocated_amount) <>
      (select leg.amount
       from pg_temp.payroll_workspace_input_legs leg
       where leg.leg_id = evidence.leg_id)
  ) then
    raise exception 'payroll_workspace_invalid_evidence_allocation'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.payroll_statement_rows statement_row
    join (
      select evidence.row_id, sum(evidence.allocated_amount) as new_amount
      from pg_temp.payroll_workspace_input_evidence evidence
      group by evidence.row_id
    ) selected on selected.row_id = statement_row.id
    where statement_row.tenant_id = tenant_id_value
      and selected.new_amount
        + coalesce((
            select sum(allocation.applied_amount)
            from public.payroll_statement_allocations allocation
            where allocation.tenant_id = tenant_id_value
              and allocation.row_id = statement_row.id
          ), 0)
        + coalesce((
            select sum(allocation.allocated_amount)
            from public.payroll_payment_statement_allocations allocation
            where allocation.tenant_id = tenant_id_value
              and allocation.statement_row_id = statement_row.id
          ), 0)
        > statement_row.amount
  ) then
    raise exception 'payroll_workspace_statement_row_overallocated'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from pg_temp.payroll_workspace_input_legs leg
    where leg.leg_type in ('salary_payment', 'salary_advance')
      and not exists (
        select 1
        from public.payroll_vouchers voucher
        join public.payroll_voucher_lines voucher_line
          on voucher_line.voucher_id = voucher.id
         and voucher_line.tenant_id = voucher.tenant_id
        where voucher.id = leg.voucher_id
          and voucher.tenant_id = tenant_id_value
          and voucher.status in ('confirmed', 'partial')
          and voucher.reconciliation_version =
              leg.expected_voucher_version
          and voucher_line.id = leg.voucher_line_id
          and voucher_line.is_included is true
          and voucher_line.total_amount > 0
      )
  ) or exists (
    select 1
    from pg_temp.payroll_workspace_input_legs leg
    join public.payroll_voucher_lines voucher_line
      on voucher_line.id = leg.voucher_line_id
     and voucher_line.voucher_id = leg.voucher_id
     and voucher_line.tenant_id = tenant_id_value
    where leg.leg_type in ('salary_payment', 'salary_advance')
    group by voucher_line.id, voucher_line.total_amount,
      voucher_line.expense_id
    having sum(leg.amount) > greatest(
      voucher_line.total_amount
      - coalesce((
          select sum(payment.amount)
          from public.expense_payments payment
          where payment.expense_id = voucher_line.expense_id
        ), 0)
      - coalesce((
          select sum(allocation.amount)
          from public.employee_advance_allocations allocation
          where allocation.voucher_line_id = voucher_line.id
        ), 0),
      0
    ) + 0.01
  ) then
    raise exception 'payroll_workspace_salary_exceeds_balance'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from pg_temp.payroll_workspace_input_legs leg
    where leg.leg_type = 'additional_expense'
      and (
        not exists (
          select 1 from public.accounts expense_account
          where expense_account.id = leg.expense_account_id
            and expense_account.tenant_id = tenant_id_value
            and expense_account.type = 'expense'
            and expense_account.is_active is true
        )
        or exists (
          select 1 from public.employees employee
          where employee.tenant_id = tenant_id_value
            and employee.salary_account_id = leg.expense_account_id
        )
        or exists (
          select 1 from public.payroll_voucher_lines voucher_line
          where voucher_line.tenant_id = tenant_id_value
            and voucher_line.salary_account_id = leg.expense_account_id
        )
      )
  ) or exists (
    select 1
    from pg_temp.payroll_workspace_input_legs leg
    where leg.leg_type in ('salary_payment', 'additional_expense')
      and not exists (
        select 1
        from public.payment_methods payment_method
        join public.accounts payment_account
          on payment_account.id = leg.payment_account_id
         and payment_account.tenant_id = payment_method.tenant_id
         and payment_account.type = 'asset'
         and payment_account.is_active is true
        where payment_method.id = leg.payment_method_id
          and payment_method.tenant_id = tenant_id_value
          and payment_method.is_active is true
          and (
            payment_method.account_id is null
            or payment_method.account_id = payment_account.id
          )
      )
  ) or exists (
    select 1
    from pg_temp.payroll_workspace_input_legs leg
    where leg.beneficiary_employee_id is not null
      and not exists (
        select 1 from public.employees employee
        where employee.id = leg.beneficiary_employee_id
          and employee.tenant_id = tenant_id_value
      )
  ) then
    raise exception 'payroll_workspace_account_or_employee_invalid'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from pg_temp.payroll_workspace_input_legs leg
    join public.payment_methods payment_method
      on payment_method.id = leg.payment_method_id
     and payment_method.tenant_id = tenant_id_value
    where leg.leg_type in ('salary_payment', 'additional_expense')
      and not (
        (
          lower(trim(payment_method.code)) = 'transfer'
          and leg.funding_kind = 'bank'
        )
        or (
          lower(trim(payment_method.code)) = 'cash'
          and leg.funding_kind = 'cash'
        )
        or (
          lower(trim(payment_method.code)) not in ('transfer', 'cash')
          and leg.funding_kind = 'other'
        )
      )
  ) then
    raise exception 'payroll_workspace_funding_method_mismatch'
      using errcode = '23514';
  end if;

  -- One V2 call per salary leg preserves an exact leg-to-movement mapping.
  -- The outer transaction remains atomic and threads each returned CAS version
  -- through every target in the same voucher. A payroll week may contain many
  -- workers; target_id groups the receipt, never the voucher CAS boundary.
  for target_element in
    select leg.voucher_id,
      min(leg.expected_voucher_version) as expected_voucher_version,
      min(leg.target_ordinal) as first_target_ordinal
    from pg_temp.payroll_workspace_input_legs leg
    where leg.voucher_id is not null
    group by leg.voucher_id
    order by min(leg.target_ordinal)
  loop
    live_voucher_version_value := target_element.expected_voucher_version;
    for leg_element in
      select *
      from pg_temp.payroll_workspace_input_legs leg
      where leg.voucher_id = target_element.voucher_id
      order by leg.target_ordinal, leg.leg_ordinal
    loop
      salary_receipt_value := public.pay_payroll_voucher_v2(
        target_element.voucher_id,
        'workspace:' || replace(p_workspace_id::text, '-', '')
          || ':leg:' || replace(leg_element.leg_id::text, '-', ''),
        live_voucher_version_value,
        jsonb_build_object(
          leg_element.voucher_line_id::text,
          jsonb_build_array(
            case
              when leg_element.leg_type = 'salary_payment' then
                jsonb_strip_nulls(jsonb_build_object(
                  'kind', 'payment',
                  'amount', leg_element.amount,
                  'payment_method_id', leg_element.payment_method_id,
                  'payment_account_id', leg_element.payment_account_id,
                  'payment_date', leg_element.payment_date,
                  'reference', leg_element.reference,
                  'notes', leg_element.notes
                ))
              else jsonb_strip_nulls(jsonb_build_object(
                'kind', 'advance',
                'amount', leg_element.amount,
                'advance_id', leg_element.advance_id,
                'notes', leg_element.notes
              ))
            end
          )
        )
      );
      live_voucher_version_value :=
        (salary_receipt_value->>'reconciliation_version')::bigint;
      result_expense_id_value := (
        select voucher_line.expense_id
        from public.payroll_voucher_lines voucher_line
        where voucher_line.id = leg_element.voucher_line_id
          and voucher_line.tenant_id = tenant_id_value
      );
      result_payment_id_value := case
        when leg_element.leg_type = 'salary_payment'
          then (salary_receipt_value->'expense_payments'->0->>'payment_id')::uuid
        else null
      end;
      result_allocation_id_value := case
        when leg_element.leg_type = 'salary_advance'
          then (salary_receipt_value->'advance_allocations'->0->>'allocation_id')::uuid
        else null
      end;
      if (leg_element.leg_type = 'salary_payment'
          and result_payment_id_value is null)
         or (leg_element.leg_type = 'salary_advance'
          and result_allocation_id_value is null) then
        raise exception 'payroll_workspace_kernel_missing_movement'
          using errcode = '55000';
      end if;
      update pg_temp.payroll_workspace_input_legs leg
      set result_expense_id = result_expense_id_value,
          result_expense_payment_id = result_payment_id_value,
          result_advance_allocation_id = result_allocation_id_value,
          result_receipt = salary_receipt_value
      where leg.leg_id = leg_element.leg_id;
    end loop;
  end loop;

  for concept_element in
    select * from pg_temp.payroll_workspace_input_concepts concept
    order by concept.target_ordinal
  loop
    select account.* into expense_account_row
    from public.accounts account
    where account.id = concept_element.expense_account_id
      and account.tenant_id = tenant_id_value;

    expense_number_value := public.generate_expense_number();
    perform set_config(
      'app.inventory_idempotency_key',
      operation_key_value || ':concept:' || concept_element.concept_id::text,
      true
    );
    insert into public.expenses (
      tenant_id, expense_number, document_type, issue_date, posting_status,
      payment_status, reference, notes, created_by
    ) values (
      tenant_id_value, expense_number_value, 'reimbursement',
      (
        select min(leg.payment_date)
        from pg_temp.payroll_workspace_input_legs leg
        where leg.concept_id = concept_element.concept_id
      ),
      'draft', 'pending',
      (
        select leg.reference
        from pg_temp.payroll_workspace_input_legs leg
        where leg.concept_id = concept_element.concept_id
          and leg.reference is not null
        order by leg.leg_ordinal
        limit 1
      ),
      coalesce(concept_element.notes, concept_element.description),
      actor_id_value
    ) returning id into result_expense_id_value;

    insert into public.expense_lines (
      tenant_id, expense_id, line_index, account_id, account_code,
      account_name, description, quantity, unit_price, tax_rate, tax_amount,
      total
    ) values (
      tenant_id_value, result_expense_id_value, 0,
      expense_account_row.id, expense_account_row.code,
      expense_account_row.name, concept_element.description,
      1, concept_element.total_amount, 0, 0, concept_element.total_amount
    );

    update public.expenses expense
    set posting_status = 'posted',
        approval_status = 'approved',
        approved_by = actor_id_value,
        approved_at = statement_timestamp()
    where expense.id = result_expense_id_value
      and expense.tenant_id = tenant_id_value;

    update pg_temp.payroll_workspace_input_concepts concept
    set result_expense_id = result_expense_id_value,
        expense_number = expense_number_value
    where concept.concept_id = concept_element.concept_id;

    for leg_element in
      select *
      from pg_temp.payroll_workspace_input_legs leg
      where leg.concept_id = concept_element.concept_id
      order by leg.leg_ordinal
    loop
      insert into public.expense_payments (
        tenant_id, expense_id, payment_method_id, payment_account_id,
        amount, payment_date, reference, notes
      ) values (
        tenant_id_value, result_expense_id_value,
        leg_element.payment_method_id,
        leg_element.payment_account_id,
        leg_element.amount, leg_element.payment_date,
        leg_element.reference, leg_element.notes
      ) returning id into result_payment_id_value;

      update pg_temp.payroll_workspace_input_legs leg
      set result_expense_id = result_expense_id_value,
          result_expense_payment_id = result_payment_id_value,
          result_receipt = jsonb_build_object(
            'concept_id', concept_element.concept_id,
            'expense_id', result_expense_id_value,
            'expense_payment_id', result_payment_id_value,
            'expense_number', expense_number_value,
            'amount', leg_element.amount,
            'expense_account_id', concept_element.expense_account_id
          )
      where leg.leg_id = leg_element.leg_id;
    end loop;
    perform set_config('app.inventory_idempotency_key', '', true);
  end loop;

  insert into public.payroll_payment_workspace_legs (
    id, tenant_id, workspace_id, target_id, concept_id,
    target_ordinal, leg_ordinal,
    leg_type, funding_kind, voucher_id, voucher_line_id, advance_id,
    beneficiary_employee_id, expense_account_id, amount, payment_method_id,
    payment_account_id, payment_date, reference, description, notes,
    result_expense_id, result_expense_payment_id,
    result_advance_allocation_id, result_receipt, applied_by
  )
  select
    leg.leg_id, tenant_id_value, p_workspace_id, leg.target_id,
    leg.concept_id, leg.target_ordinal, leg.leg_ordinal,
    leg.leg_type, leg.funding_kind,
    leg.voucher_id, leg.voucher_line_id, leg.advance_id,
    leg.beneficiary_employee_id, leg.expense_account_id, leg.amount,
    leg.payment_method_id, leg.payment_account_id, leg.payment_date,
    leg.reference, leg.description, leg.notes, leg.result_expense_id,
    leg.result_expense_payment_id, leg.result_advance_allocation_id,
    leg.result_receipt, actor_id_value
  from pg_temp.payroll_workspace_input_legs leg
  order by leg.target_ordinal, leg.leg_ordinal;

  insert into public.payroll_payment_statement_allocations (
    tenant_id, workspace_id, workspace_leg_id, import_id,
    statement_row_id, row_fingerprint, observed_amount, allocated_amount,
    result_expense_payment_id, applied_by
  )
  select
    tenant_id_value, p_workspace_id, evidence.leg_id,
    statement_row.import_id, statement_row.id, statement_row.fingerprint,
    statement_row.amount, evidence.allocated_amount,
    leg.result_expense_payment_id, actor_id_value
  from pg_temp.payroll_workspace_input_evidence evidence
  join pg_temp.payroll_workspace_input_legs leg
    on leg.leg_id = evidence.leg_id
  join public.payroll_statement_rows statement_row
    on statement_row.id = evidence.row_id
   and statement_row.import_id = evidence.import_id
   and statement_row.tenant_id = tenant_id_value
  order by evidence.leg_id, evidence.evidence_ordinal;

  new_workspace_version_value := workspace_row.version + 1;
  receipt_value := jsonb_build_object(
    'workspace_id', p_workspace_id,
    'operation_key', operation_key_value,
    'payload_hash', payload_hash_value,
    'status', 'applied',
    'version', new_workspace_version_value,
    'replayed', false,
    'statement', case
      when statement_import_id_value is null then null
      else jsonb_build_object(
        'import_id', statement_import_id_value,
        'file_digest', statement_file_digest_value,
        'account_id', statement_account_id_value,
        'created', statement_is_new_value,
        'rows', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'source_row_id', inline_row.source_row_id,
              'row_id', inline_row.row_id,
              'fingerprint', statement_row.fingerprint,
              'ordinal', inline_row.row_ordinal
            ) order by inline_row.row_ordinal
          )
          from pg_temp.payroll_workspace_inline_rows inline_row
          join public.payroll_statement_rows statement_row
            on statement_row.id = inline_row.row_id
           and statement_row.import_id = inline_row.import_id
           and statement_row.tenant_id = tenant_id_value
        ), '[]'::jsonb)
      )
    end,
    'targets', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'target_id', target_group.target_id,
          'voucher_id', target_group.voucher_id,
          'status', target_group.status,
          'reconciliation_version', target_group.reconciliation_version,
          'legs', target_group.legs
        ) order by target_group.target_ordinal
      )
      from (
        select leg.target_id, leg.target_ordinal, leg.voucher_id,
          (array_agg(
            leg.result_receipt->>'status'
            order by leg.leg_ordinal desc
          ))[1] as status,
          max((
            leg.result_receipt->>'reconciliation_version'
          )::bigint) as reconciliation_version,
          jsonb_agg(
            jsonb_build_object(
              'leg_id', leg.leg_id,
              'kind', leg.leg_type,
              'amount', leg.amount,
              'expense_id', leg.result_expense_id,
              'expense_payment_id', leg.result_expense_payment_id,
              'advance_allocation_id', leg.result_advance_allocation_id,
              'receipt', leg.result_receipt
            ) order by leg.leg_ordinal
          ) as legs
        from pg_temp.payroll_workspace_input_legs leg
        where leg.voucher_id is not null
        group by leg.target_id, leg.target_ordinal, leg.voucher_id
      ) target_group
    ), '[]'::jsonb),
    'additional_concepts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'concept_id', concept.concept_id,
          'amount', concept.total_amount,
          'expense_account_id', concept.expense_account_id,
          'expense_id', concept.result_expense_id,
          'expense_number', concept.expense_number,
          'payment_legs', (
            select jsonb_agg(
              jsonb_build_object(
                'leg_id', leg.leg_id,
                'amount', leg.amount,
                'funding_kind', leg.funding_kind,
                'expense_payment_id', leg.result_expense_payment_id,
                'receipt', leg.result_receipt
              ) order by leg.leg_ordinal
            )
            from pg_temp.payroll_workspace_input_legs leg
            where leg.concept_id = concept.concept_id
          )
        ) order by concept.target_ordinal
      )
      from pg_temp.payroll_workspace_input_concepts concept
    ), '[]'::jsonb),
    'statement_allocations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'allocation_id', allocation.id,
          'leg_id', allocation.workspace_leg_id,
          'import_id', allocation.import_id,
          'row_id', allocation.statement_row_id,
          'allocated_amount', allocation.allocated_amount,
          'expense_payment_id', allocation.result_expense_payment_id
        ) order by allocation.id
      )
      from public.payroll_payment_statement_allocations allocation
      where allocation.workspace_id = p_workspace_id
        and allocation.tenant_id = tenant_id_value
    ), '[]'::jsonb)
  );

  update public.payroll_payment_workspaces workspace
  set status = 'applied',
      version = new_workspace_version_value,
      apply_operation_key = operation_key_value,
      apply_payload_hash = payload_hash_value,
      apply_receipt = receipt_value,
      applied_by = actor_id_value,
      applied_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where workspace.id = p_workspace_id
    and workspace.tenant_id = tenant_id_value
    and workspace.status = 'draft'
    and workspace.version = p_expected_workspace_version;

  if not found then
    raise exception 'payroll_workspace_version_conflict'
      using errcode = '40001';
  end if;

  return receipt_value;
exception
  when others then
    perform set_config('app.inventory_idempotency_key', '', true);
    raise;
end;
$$;

revoke all on function public.apply_payroll_payment_workspace_v1(
  uuid, text, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.apply_payroll_payment_workspace_v1(
  uuid, text, bigint, jsonb
) to authenticated;

comment on function public.apply_payroll_payment_workspace_v1(
  uuid, text, bigint, jsonb
) is
  'Canonical atomic payment workspace for one or many payroll targets. OCR observations are optional evidence; salary, cash, advances, and separate non-salary expenses share this one idempotent CAS command.';

commit;
