-- Add an auditable payroll bank-statement reconciliation boundary.
--
-- Importing parser/OCR output never pays payroll. The import command stores a
-- file digest plus immutable normalized rows in review. A separate apply
-- command requires an explicit decision for every imported row, current
-- voucher versions, and a human cash acknowledgement before it can create any
-- accounting movement.
--
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).
-- Backfill: none. Existing payroll vouchers start at reconciliation_version 0.
-- Lock risk: a brief catalog lock adds the voucher version column and trigger;
-- reconciliation indexes are over new empty tables. Tenant-composite reference
-- indexes also scan the existing payroll/accounting tables and briefly block
-- writes while this transactional migration runs. Runtime settlement commands
-- serialize per tenant, then lock one import and the explicitly selected
-- vouchers/lines/advances in deterministic order.
-- Recovery: stop new calls, preserve the audit tables, and restore the prior
-- voucher ACL/function definitions. Do not drop reconciliation evidence after
-- an apply operation has created accounting movements.
-- Prerequisite: 20260728020000_include_employee_advances_in_expense_trace.sql
-- must be applied first so advance allocations satisfy the current expense
-- trace invariant.

begin;

do $$
begin
  if to_regclass(
    'public.idx_payroll_voucher_lines_tenant_expense'
  ) is null then
    raise exception
      'Missing prerequisite 20260728020000_include_employee_advances_in_expense_trace'
      using errcode = '55000';
  end if;
end
$$;

alter table public.payroll_vouchers
  add column if not exists reconciliation_version bigint not null default 0;

create or replace function public.bump_payroll_voucher_reconciliation_version()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.reconciliation_version := old.reconciliation_version + 1;
  return new;
end;
$$;

revoke all on function
  public.bump_payroll_voucher_reconciliation_version()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_payroll_voucher_reconciliation_version
  on public.payroll_vouchers;
create trigger trg_payroll_voucher_reconciliation_version
  before update on public.payroll_vouchers
  for each row
  execute function public.bump_payroll_voucher_reconciliation_version();

create or replace function public.touch_payroll_voucher_from_line()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  voucher_id_value uuid := case
    when tg_op = 'DELETE' then old.voucher_id
    else new.voucher_id
  end;
  prior_voucher_id_value uuid := case
    when tg_op = 'UPDATE' then old.voucher_id
    else null
  end;
begin
  -- The voucher trigger owns the actual monotonic increment. A line mutation
  -- only touches the aggregate header, so direct REST edits cannot leave the
  -- optimistic-concurrency token stale.
  update public.payroll_vouchers voucher
  set updated_at = statement_timestamp()
  where voucher.id = voucher_id_value;

  if prior_voucher_id_value is not null
     and prior_voucher_id_value <> voucher_id_value then
    update public.payroll_vouchers voucher
    set updated_at = statement_timestamp()
    where voucher.id = prior_voucher_id_value;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.touch_payroll_voucher_from_line()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_touch_payroll_voucher_from_line
  on public.payroll_voucher_lines;
create trigger trg_touch_payroll_voucher_from_line
  after insert or update or delete on public.payroll_voucher_lines
  for each row
  execute function public.touch_payroll_voucher_from_line();

create or replace function public.normalize_payroll_statement_text(
  p_value text
)
returns text
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select nullif(
    trim(
      regexp_replace(
        lower(public.unaccent('unaccent', p_value)),
        '[^a-z0-9]+',
        ' ',
        'g'
      )
    ),
    ''
  )
$$;

revoke all on function public.normalize_payroll_statement_text(text)
  from public, anon, authenticated, service_role;
grant execute on function public.normalize_payroll_statement_text(text)
  to service_role;

create table if not exists public.payroll_statement_account_mappings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  erp_account_id uuid not null
    references public.accounts(id) on delete restrict,
  account_fingerprint text not null
    check (account_fingerprint ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  unique (tenant_id, erp_account_id),
  unique (tenant_id, account_fingerprint),
  unique (tenant_id, erp_account_id, account_fingerprint)
);

create table if not exists public.payroll_voucher_draft_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  operation_key text not null
    check (char_length(operation_key) between 8 and 200),
  payload_hash text not null
    check (payload_hash ~ '^[0-9a-f]{64}$'),
  voucher_id uuid
    references public.payroll_vouchers(id) on delete set null,
  expected_reconciliation_version bigint
    check (
      expected_reconciliation_version is null
      or expected_reconciliation_version >= 0
    ),
  receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
  created_by uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  unique (tenant_id, operation_key)
);

create index if not exists idx_payroll_voucher_draft_operations_voucher
  on public.payroll_voucher_draft_operations(tenant_id, voucher_id);

create table if not exists public.payroll_money_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  operation_type text not null
    check (
      operation_type in ('manual_payroll_payment', 'employee_advance')
    ),
  operation_key text not null
    check (char_length(operation_key) between 8 and 200),
  payload_hash text not null
    check (payload_hash ~ '^[0-9a-f]{64}$'),
  voucher_id uuid
    references public.payroll_vouchers(id) on delete restrict,
  employee_advance_id uuid
    references public.employee_advances(id) on delete restrict,
  receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
  created_by uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  unique (tenant_id, operation_key),
  check (
    (
      operation_type = 'manual_payroll_payment'
      and voucher_id is not null
      and employee_advance_id is null
    )
    or (
      operation_type = 'employee_advance'
      and voucher_id is null
      and employee_advance_id is not null
    )
  )
);

create index if not exists idx_payroll_money_operations_voucher
  on public.payroll_money_operations(tenant_id, voucher_id)
  where voucher_id is not null;
create index if not exists idx_payroll_money_operations_advance
  on public.payroll_money_operations(tenant_id, employee_advance_id)
  where employee_advance_id is not null;

create table if not exists public.payroll_money_operation_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  operation_id uuid not null
    references public.payroll_money_operations(id) on delete restrict,
  movement_type text not null
    check (movement_type in ('expense_payment', 'advance_allocation')),
  expense_payment_id uuid
    references public.expense_payments(id) on delete restrict,
  advance_allocation_id uuid
    references public.employee_advance_allocations(id) on delete restrict,
  created_at timestamp with time zone not null default statement_timestamp(),
  unique (expense_payment_id),
  unique (advance_allocation_id),
  check (
    (
      movement_type = 'expense_payment'
      and expense_payment_id is not null
      and advance_allocation_id is null
    )
    or (
      movement_type = 'advance_allocation'
      and expense_payment_id is null
      and advance_allocation_id is not null
    )
  )
);

create index if not exists idx_payroll_money_operation_movements_operation
  on public.payroll_money_operation_movements(tenant_id, operation_id);

create table if not exists public.payroll_statement_imports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  file_sha256 text not null
    check (file_sha256 ~ '^[0-9a-f]{64}$'),
  account_fingerprint text not null
    check (account_fingerprint ~ '^[0-9a-f]{64}$'),
  erp_account_id uuid not null
    references public.accounts(id) on delete restrict,
  source_metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_metadata) = 'object'),
  parser_name text not null
    check (char_length(parser_name) between 1 and 100),
  parser_version text not null
    check (char_length(parser_version) between 1 and 100),
  source_type text not null
    check (source_type in ('pdf_text', 'pdf_ocr', 'image_ocr')),
  row_count integer not null default 0
    check (row_count between 0 and 2000),
  revision integer not null default 1
    check (revision between 1 and 1000),
  status text not null default 'review'
    check (
      status in (
        'review',
        'applied',
        'applied_with_variances',
        'held'
      )
    ),
  create_operation_key text not null
    check (char_length(create_operation_key) between 8 and 200),
  create_payload_hash text not null
    check (create_payload_hash ~ '^[0-9a-f]{64}$'),
  import_receipt jsonb,
  apply_operation_key text,
  apply_payload_hash text,
  apply_receipt jsonb,
  created_by uuid not null references auth.users(id),
  applied_by uuid references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  applied_at timestamp with time zone,
  updated_at timestamp with time zone not null default statement_timestamp(),
  check (
    (
      apply_operation_key is null
      and apply_payload_hash is null
      and apply_receipt is null
      and applied_by is null
      and applied_at is null
      and status = 'review'
    )
    or (
      apply_operation_key is not null
      and char_length(apply_operation_key) between 8 and 200
      and apply_payload_hash ~ '^[0-9a-f]{64}$'
      and apply_receipt is not null
      and applied_by is not null
      and applied_at is not null
      and status in ('applied', 'applied_with_variances', 'held')
    )
  )
);

alter table public.payroll_statement_imports
  add column if not exists account_fingerprint text;
alter table public.payroll_statement_imports
  add column if not exists erp_account_id uuid;
alter table public.payroll_statement_imports
  add column if not exists revision integer not null default 1;
alter table public.payroll_statement_imports
  drop constraint if exists
    payroll_statement_imports_tenant_account_mapping_fkey;

do $$
begin
  if exists (
    select 1
    from public.payroll_statement_imports statement_import
    where statement_import.account_fingerprint is null
       or statement_import.erp_account_id is null
  ) then
    raise exception
      'Existing statement imports require an explicit account migration'
      using errcode = '55000';
  end if;

  alter table public.payroll_statement_imports
    alter column account_fingerprint set not null;
  alter table public.payroll_statement_imports
    alter column erp_account_id set not null;

  alter table public.payroll_statement_imports
    drop constraint if exists payroll_statement_imports_status_check;
  alter table public.payroll_statement_imports
    add constraint payroll_statement_imports_status_check
    check (
      status in (
        'review',
        'applied',
        'applied_with_variances',
        'held'
      )
    );
end
$$;

create unique index if not exists
  ux_payroll_statement_imports_tenant_file
  on public.payroll_statement_imports(tenant_id, file_sha256);
create unique index if not exists
  ux_payroll_statement_imports_create_operation
  on public.payroll_statement_imports(tenant_id, create_operation_key);
create unique index if not exists
  ux_payroll_statement_imports_apply_operation
  on public.payroll_statement_imports(tenant_id, apply_operation_key)
  where apply_operation_key is not null;
create index if not exists idx_payroll_statement_imports_review
  on public.payroll_statement_imports(tenant_id, status, created_at desc);

-- Each import operation is retained independently from the mutable current
-- review revision. A retry of a superseded operation can therefore fail
-- closed instead of silently restoring stale OCR rows.
create table if not exists public.payroll_statement_import_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  import_id uuid not null
    references public.payroll_statement_imports(id) on delete restrict,
  operation_key text not null
    check (char_length(operation_key) between 8 and 200),
  payload_hash text not null
    check (payload_hash ~ '^[0-9a-f]{64}$'),
  revision integer not null check (revision between 1 and 1000),
  receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
  created_by uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  unique (tenant_id, operation_key)
);

create index if not exists idx_payroll_statement_import_operations_import
  on public.payroll_statement_import_operations(import_id, revision);

-- This private table is a transaction-scoped capability. Unlike a custom GUC,
-- authenticated callers cannot forge it with set_config(). Failed commands
-- roll their context row back automatically.
create table if not exists public.payroll_statement_command_contexts (
  transaction_id bigint primary key,
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  import_id uuid not null
    references public.payroll_statement_imports(id) on delete restrict,
  command text not null check (
    command in ('import_revision', 'apply', 'manual_settlement')
  ),
  actor_id uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp()
);

create table if not exists public.payroll_money_command_contexts (
  transaction_id bigint primary key,
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  command text not null
    check (
      command in (
        'manual_payment',
        'advance_registration',
        'legacy_reversal'
      )
    ),
  operation_key text not null
    check (char_length(operation_key) between 8 and 200),
  actor_id uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp()
);

alter table public.payroll_money_command_contexts
  drop constraint if exists payroll_money_command_contexts_command_check;
alter table public.payroll_money_command_contexts
  add constraint payroll_money_command_contexts_command_check
  check (
    command in (
      'manual_payment',
      'advance_registration',
      'legacy_reversal'
    )
  );

alter table public.payroll_statement_command_contexts
  drop constraint if exists payroll_statement_command_contexts_command_check;
alter table public.payroll_statement_command_contexts
  add constraint payroll_statement_command_contexts_command_check
  check (command in ('import_revision', 'apply', 'manual_settlement'));

create table if not exists public.payroll_statement_rows (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  import_id uuid not null
    references public.payroll_statement_imports(id) on delete restrict,
  row_ordinal integer not null check (row_ordinal between 1 and 2000),
  page_number integer check (page_number between 1 and 10000),
  source_line_start integer,
  source_line_end integer,
  source_occurrence integer not null default 1
    check (source_occurrence between 1 and 2000),
  transaction_date date
    check (
      transaction_date is null
      or transaction_date between date '1900-01-01' and date '2100-12-31'
    ),
  direction text
    check (direction is null or direction in ('debit', 'credit', 'unknown')),
  amount numeric(14,2)
    check (
      amount is null
      or (amount > 0 and amount <= 999999999999.99)
    ),
  description_observed text,
  beneficiary_observed text,
  document_observed text,
  description_normalized text,
  beneficiary_normalized text,
  base_fingerprint text not null
    check (base_fingerprint ~ '^[0-9a-f]{64}$'),
  fingerprint text not null
    check (fingerprint ~ '^[0-9a-f]{64}$'),
  warnings jsonb not null default '[]'::jsonb
    check (
      jsonb_typeof(warnings) = 'array'
      and jsonb_array_length(warnings) <= 20
    ),
  created_at timestamp with time zone not null default statement_timestamp(),
  check (
    description_observed is not null
    or beneficiary_observed is not null
  ),
  check (
    description_observed is null
    or char_length(description_observed) between 1 and 500
  ),
  check (
    beneficiary_observed is null
    or char_length(beneficiary_observed) between 1 and 200
  ),
  unique (import_id, row_ordinal),
  unique (import_id, fingerprint)
);

alter table public.payroll_statement_rows
  add column if not exists source_line_start integer;
alter table public.payroll_statement_rows
  add column if not exists source_line_end integer;
alter table public.payroll_statement_rows
  add column if not exists document_observed text;
alter table public.payroll_statement_rows
  add column if not exists base_fingerprint text;
alter table public.payroll_statement_rows
  drop constraint if exists payroll_statement_rows_source_occurrence_check;
alter table public.payroll_statement_rows
  add constraint payroll_statement_rows_source_occurrence_check
  check (source_occurrence between 1 and 2000);
alter table public.payroll_statement_rows
  alter column transaction_date drop not null;
alter table public.payroll_statement_rows
  alter column direction drop not null;
alter table public.payroll_statement_rows
  alter column amount drop not null;
alter table public.payroll_statement_rows
  drop constraint if exists payroll_statement_rows_transaction_date_check;
alter table public.payroll_statement_rows
  add constraint payroll_statement_rows_transaction_date_check
  check (
    transaction_date is null
    or transaction_date between date '1900-01-01' and date '2100-12-31'
  );
alter table public.payroll_statement_rows
  drop constraint if exists payroll_statement_rows_direction_check;
alter table public.payroll_statement_rows
  add constraint payroll_statement_rows_direction_check
  check (
    direction is null
    or direction in ('debit', 'credit', 'unknown')
  );
alter table public.payroll_statement_rows
  drop constraint if exists payroll_statement_rows_amount_check;
alter table public.payroll_statement_rows
  add constraint payroll_statement_rows_amount_check
  check (
    amount is null
    or (amount > 0 and amount <= 999999999999.99)
  );

do $$
begin
  if exists (
    select 1
    from public.payroll_statement_rows statement_row
    where statement_row.base_fingerprint is null
  ) then
    raise exception
      'Existing statement rows require an explicit base fingerprint migration'
      using errcode = '55000';
  end if;

  alter table public.payroll_statement_rows
    alter column base_fingerprint set not null;
  alter table public.payroll_statement_rows
    drop constraint if exists
      payroll_statement_rows_base_fingerprint_check;
  alter table public.payroll_statement_rows
    add constraint payroll_statement_rows_base_fingerprint_check
    check (base_fingerprint ~ '^[0-9a-f]{64}$');
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
        'public.payroll_statement_rows'::regclass
      and constraint_row.conname =
        'payroll_statement_rows_source_line_range_check'
  ) then
    alter table public.payroll_statement_rows
      add constraint payroll_statement_rows_source_line_range_check
      check (
        (
          source_line_start is null
          and source_line_end is null
        )
        or (
          source_line_start between 1 and 1000000
          and source_line_end between source_line_start and 1000000
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
        'public.payroll_statement_rows'::regclass
      and constraint_row.conname =
        'payroll_statement_rows_document_observed_check'
  ) then
    alter table public.payroll_statement_rows
      add constraint payroll_statement_rows_document_observed_check
      check (
        document_observed is null
        or char_length(document_observed) between 1 and 100
      );
  end if;
end
$$;

create index if not exists idx_payroll_statement_rows_import_date
  on public.payroll_statement_rows(import_id, transaction_date, row_ordinal);
create index if not exists idx_payroll_statement_rows_tenant_fingerprint
  on public.payroll_statement_rows(tenant_id, fingerprint);
create index if not exists idx_payroll_statement_rows_tenant_base_fingerprint
  on public.payroll_statement_rows(tenant_id, base_fingerprint);

create table if not exists public.payroll_statement_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  import_id uuid not null
    references public.payroll_statement_imports(id) on delete restrict,
  operation_key text not null
    check (char_length(operation_key) between 8 and 200),
  decision_ordinal integer not null
    check (decision_ordinal between 1 and 4000),
  action text not null check (
    action in (
      'bank_payment',
      'cash_payment',
      'advance_allocation',
      'not_paid',
      'ignore',
      'hold',
      'already_resolved'
    )
  ),
  row_id uuid
    references public.payroll_statement_rows(id) on delete restrict,
  row_fingerprint text,
  prior_decision_id uuid,
  voucher_id uuid
    references public.payroll_vouchers(id) on delete restrict,
  voucher_line_id uuid
    references public.payroll_voucher_lines(id) on delete restrict,
  employee_id uuid references public.employees(id) on delete restrict,
  advance_id uuid
    references public.employee_advances(id) on delete restrict,
  payment_method_id uuid
    references public.payment_methods(id) on delete restrict,
  payment_account_id uuid
    references public.accounts(id) on delete restrict,
  bank_amount numeric(14,2),
  applied_amount numeric(14,2),
  variance numeric(14,2),
  variance_disposition text check (
    variance_disposition is null
    or variance_disposition in (
      'exact',
      'partial',
      'unresolved',
      'not_applicable'
    )
  ),
  payment_date date,
  manual_confirmation boolean not null default false,
  duplicate_override boolean not null default false,
  reason text check (reason is null or char_length(reason) between 1 and 1000),
  movement_reference text,
  result_expense_payment_id uuid
    references public.expense_payments(id) on delete restrict,
  result_advance_allocation_id uuid
    references public.employee_advance_allocations(id) on delete restrict,
  outcome text not null default 'pending'
    check (outcome in ('pending', 'applied', 'acknowledged', 'held')),
  decided_by uuid not null references auth.users(id),
  decided_at timestamp with time zone not null default statement_timestamp(),
  unique (import_id, decision_ordinal),
  unique (import_id, row_id)
);

alter table public.payroll_statement_decisions
  add column if not exists prior_decision_id uuid;
alter table public.payroll_statement_decisions
  add column if not exists duplicate_override boolean
    not null default false;
alter table public.payroll_statement_decisions
  drop constraint if exists
    payroll_statement_decisions_variance_disposition_check;
alter table public.payroll_statement_decisions
  add constraint payroll_statement_decisions_variance_disposition_check
  check (
    variance_disposition is null
    or variance_disposition in (
      'exact',
      'partial',
      'unresolved',
      'not_applicable'
    )
  );
alter table public.payroll_statement_decisions
  drop constraint if exists payroll_statement_decisions_action_check;
alter table public.payroll_statement_decisions
  add constraint payroll_statement_decisions_action_check
  check (
    action in (
      'bank_payment',
      'cash_payment',
      'advance_allocation',
      'not_paid',
      'ignore',
      'hold',
      'already_resolved'
    )
  );

create index if not exists idx_payroll_statement_decisions_import
  on public.payroll_statement_decisions(import_id, decision_ordinal);
create index if not exists idx_payroll_statement_decisions_voucher
  on public.payroll_statement_decisions(voucher_id, voucher_line_id);
drop index if exists
  public.ux_payroll_statement_decisions_resolved_fingerprint;
create unique index
  ux_payroll_statement_decisions_resolved_fingerprint
  on public.payroll_statement_decisions(tenant_id, row_fingerprint)
  where row_fingerprint is not null
    and action <> 'already_resolved'
    and outcome in ('applied', 'acknowledged', 'held');

create table if not exists public.payroll_statement_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  import_id uuid not null
    references public.payroll_statement_imports(id) on delete restrict,
  decision_id uuid not null unique
    references public.payroll_statement_decisions(id) on delete restrict,
  action text not null check (
    action in ('bank_payment', 'cash_payment', 'advance_allocation')
  ),
  row_id uuid
    references public.payroll_statement_rows(id) on delete restrict,
  row_fingerprint text,
  voucher_id uuid not null
    references public.payroll_vouchers(id) on delete restrict,
  voucher_line_id uuid not null
    references public.payroll_voucher_lines(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  expense_payment_id uuid unique
    references public.expense_payments(id) on delete restrict,
  employee_advance_allocation_id uuid unique
    references public.employee_advance_allocations(id) on delete restrict,
  bank_amount numeric(14,2),
  applied_amount numeric(14,2) not null check (applied_amount > 0),
  variance numeric(14,2),
  variance_disposition text not null check (
    variance_disposition in (
      'exact',
      'partial',
      'unresolved',
      'not_applicable'
    )
  ),
  payment_date date,
  movement_reference text not null,
  applied_by uuid not null references auth.users(id),
  applied_at timestamp with time zone not null default statement_timestamp(),
  check (
    (
      action = 'bank_payment'
      and row_id is not null
      and row_fingerprint ~ '^[0-9a-f]{64}$'
      and expense_payment_id is not null
      and employee_advance_allocation_id is null
      and bank_amount > 0
      and variance is not null
      and payment_date is not null
    )
    or (
      action = 'cash_payment'
      and row_id is null
      and row_fingerprint is null
      and expense_payment_id is not null
      and employee_advance_allocation_id is null
      and bank_amount is null
      and variance is null
      and variance_disposition = 'not_applicable'
      and payment_date is not null
    )
    or (
      action = 'advance_allocation'
      and row_id is null
      and row_fingerprint is null
      and expense_payment_id is null
      and employee_advance_allocation_id is not null
      and bank_amount is null
      and variance is null
      and variance_disposition = 'not_applicable'
    )
  )
);

alter table public.payroll_statement_allocations
  drop constraint if exists
    payroll_statement_allocations_variance_disposition_check;
alter table public.payroll_statement_allocations
  add constraint payroll_statement_allocations_variance_disposition_check
  check (
    variance_disposition in (
      'exact',
      'partial',
      'unresolved',
      'not_applicable'
    )
  );

create unique index if not exists
  ux_payroll_statement_allocations_tenant_fingerprint
  on public.payroll_statement_allocations(tenant_id, row_fingerprint)
  where row_fingerprint is not null;
create index if not exists idx_payroll_statement_allocations_voucher
  on public.payroll_statement_allocations(voucher_id, voucher_line_id);

-- Composite uniqueness lets every reconciliation FK carry tenant ownership.
-- IDs are already globally unique; these indexes cannot expose duplicate
-- business keys, but they do scan the existing referenced tables.
create unique index if not exists ux_payroll_statement_imports_tenant_id
  on public.payroll_statement_imports(tenant_id, id);
create unique index if not exists ux_payroll_statement_rows_tenant_id
  on public.payroll_statement_rows(tenant_id, id);
create unique index if not exists ux_payroll_statement_decisions_tenant_id
  on public.payroll_statement_decisions(tenant_id, id);
create unique index if not exists ux_payroll_money_operations_tenant_id
  on public.payroll_money_operations(tenant_id, id);
create unique index if not exists ux_payroll_vouchers_tenant_id
  on public.payroll_vouchers(tenant_id, id);
create unique index if not exists ux_payroll_voucher_lines_tenant_id
  on public.payroll_voucher_lines(tenant_id, id);
create unique index if not exists ux_employees_tenant_id
  on public.employees(tenant_id, id);
create unique index if not exists ux_employee_advances_tenant_id
  on public.employee_advances(tenant_id, id);
create unique index if not exists ux_expense_payments_tenant_id
  on public.expense_payments(tenant_id, id);
create unique index if not exists ux_employee_advance_allocations_tenant_id
  on public.employee_advance_allocations(tenant_id, id);

do $$
declare
  constraint_spec record;
begin
  for constraint_spec in
    select *
    from (
      values
        (
          'payroll_statement_account_mappings',
          'payroll_statement_account_mappings_tenant_account_fkey',
          'foreign key (tenant_id, erp_account_id) references '
            || 'public.accounts(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_money_operations',
          'payroll_money_operations_tenant_voucher_fkey',
          'foreign key (tenant_id, voucher_id) references '
            || 'public.payroll_vouchers(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_money_operations',
          'payroll_money_operations_tenant_advance_fkey',
          'foreign key (tenant_id, employee_advance_id) references '
            || 'public.employee_advances(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_money_operation_movements',
          'payroll_money_operation_movements_tenant_operation_fkey',
          'foreign key (tenant_id, operation_id) references '
            || 'public.payroll_money_operations(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_money_operation_movements',
          'payroll_money_operation_movements_tenant_payment_fkey',
          'foreign key (tenant_id, expense_payment_id) references '
            || 'public.expense_payments(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_money_operation_movements',
          'payroll_money_operation_movements_tenant_allocation_fkey',
          'foreign key (tenant_id, advance_allocation_id) references '
            || 'public.employee_advance_allocations(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_imports',
          'payroll_statement_imports_tenant_erp_account_fkey',
          'foreign key (tenant_id, erp_account_id) '
            || 'references public.accounts(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_import_operations',
          'payroll_statement_import_operations_tenant_import_fkey',
          'foreign key (tenant_id, import_id) references '
            || 'public.payroll_statement_imports(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_command_contexts',
          'payroll_statement_command_contexts_tenant_import_fkey',
          'foreign key (tenant_id, import_id) references '
            || 'public.payroll_statement_imports(tenant_id, id) '
            || 'on delete cascade'
        ),
        (
          'payroll_statement_rows',
          'payroll_statement_rows_tenant_import_fkey',
          'foreign key (tenant_id, import_id) references '
            || 'public.payroll_statement_imports(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_import_fkey',
          'foreign key (tenant_id, import_id) references '
            || 'public.payroll_statement_imports(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_row_fkey',
          'foreign key (tenant_id, row_id) references '
            || 'public.payroll_statement_rows(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_prior_decision_fkey',
          'foreign key (tenant_id, prior_decision_id) references '
            || 'public.payroll_statement_decisions(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_voucher_fkey',
          'foreign key (tenant_id, voucher_id) references '
            || 'public.payroll_vouchers(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_voucher_line_fkey',
          'foreign key (tenant_id, voucher_line_id) references '
            || 'public.payroll_voucher_lines(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_employee_fkey',
          'foreign key (tenant_id, employee_id) references '
            || 'public.employees(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_advance_fkey',
          'foreign key (tenant_id, advance_id) references '
            || 'public.employee_advances(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_method_fkey',
          'foreign key (tenant_id, payment_method_id) references '
            || 'public.payment_methods(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_account_fkey',
          'foreign key (tenant_id, payment_account_id) references '
            || 'public.accounts(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_payment_result_fkey',
          'foreign key (tenant_id, result_expense_payment_id) references '
            || 'public.expense_payments(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_decisions',
          'payroll_statement_decisions_tenant_advance_result_fkey',
          'foreign key (tenant_id, result_advance_allocation_id) references '
            || 'public.employee_advance_allocations(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_import_fkey',
          'foreign key (tenant_id, import_id) references '
            || 'public.payroll_statement_imports(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_decision_fkey',
          'foreign key (tenant_id, decision_id) references '
            || 'public.payroll_statement_decisions(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_row_fkey',
          'foreign key (tenant_id, row_id) references '
            || 'public.payroll_statement_rows(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_voucher_fkey',
          'foreign key (tenant_id, voucher_id) references '
            || 'public.payroll_vouchers(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_voucher_line_fkey',
          'foreign key (tenant_id, voucher_line_id) references '
            || 'public.payroll_voucher_lines(tenant_id, id) '
            || 'on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_employee_fkey',
          'foreign key (tenant_id, employee_id) references '
            || 'public.employees(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_payment_result_fkey',
          'foreign key (tenant_id, expense_payment_id) references '
            || 'public.expense_payments(tenant_id, id) on delete restrict'
        ),
        (
          'payroll_statement_allocations',
          'payroll_statement_allocations_tenant_advance_result_fkey',
          'foreign key (tenant_id, employee_advance_allocation_id) '
            || 'references public.employee_advance_allocations(tenant_id, id) '
            || 'on delete restrict'
        )
    ) as constraints_to_add(table_name, constraint_name, definition)
  loop
    if not exists (
      select 1
      from pg_catalog.pg_constraint existing_constraint
      where existing_constraint.conrelid =
        format('public.%I', constraint_spec.table_name)::regclass
        and existing_constraint.conname = constraint_spec.constraint_name
    ) then
      execute format(
        'alter table public.%I add constraint %I %s',
        constraint_spec.table_name,
        constraint_spec.constraint_name,
        constraint_spec.definition
      );
    end if;
  end loop;
end
$$;

create or replace function public.guard_payroll_statement_row_immutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'DELETE'
     and exists (
       select 1
       from public.payroll_statement_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.command = 'import_revision'
         and command_context.tenant_id = old.tenant_id
         and command_context.import_id = old.import_id
     ) then
    return old;
  end if;

  raise exception 'payroll_statement_rows_are_immutable'
    using errcode = '55000';
end;
$$;

revoke all on function public.guard_payroll_statement_row_immutable()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_payroll_statement_rows_immutable
  on public.payroll_statement_rows;
create trigger trg_payroll_statement_rows_immutable
  before update or delete on public.payroll_statement_rows
  for each row
  execute function public.guard_payroll_statement_row_immutable();

create or replace function public.guard_payroll_statement_evidence_immutable()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  import_id_value uuid := case
    when tg_op = 'DELETE' then old.import_id
    else new.import_id
  end;
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then old.tenant_id
    else new.tenant_id
  end;
begin
  if tg_table_name = 'payroll_statement_decisions'
     and tg_op = 'UPDATE'
     and old.import_id = new.import_id
     and old.tenant_id = new.tenant_id
     and exists (
       select 1
       from public.payroll_statement_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.command = 'apply'
         and command_context.tenant_id = tenant_id_value
         and command_context.import_id = import_id_value
     ) then
    return new;
  end if;

  raise exception 'payroll_statement_evidence_is_immutable'
    using errcode = '55000';
end;
$$;

revoke all on function public.guard_payroll_statement_evidence_immutable()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_payroll_statement_decisions_immutable
  on public.payroll_statement_decisions;
create trigger trg_payroll_statement_decisions_immutable
  before update or delete on public.payroll_statement_decisions
  for each row
  execute function public.guard_payroll_statement_evidence_immutable();

drop trigger if exists trg_payroll_statement_allocations_immutable
  on public.payroll_statement_allocations;
create trigger trg_payroll_statement_allocations_immutable
  before update or delete on public.payroll_statement_allocations
  for each row
  execute function public.guard_payroll_statement_evidence_immutable();

create or replace function public.guard_reconciled_payroll_voucher_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  voucher_id_value uuid := case
    when tg_table_name = 'payroll_vouchers' then
      case
        when tg_op = 'DELETE' then (to_jsonb(old)->>'id')::uuid
        else (to_jsonb(new)->>'id')::uuid
      end
    when tg_op = 'DELETE'
      then (to_jsonb(old)->>'voucher_id')::uuid
    else (to_jsonb(new)->>'voucher_id')::uuid
  end;
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then (to_jsonb(old)->>'tenant_id')::uuid
    else (to_jsonb(new)->>'tenant_id')::uuid
  end;
  prior_voucher_id_value uuid := case
    when tg_table_name = 'payroll_voucher_lines' and tg_op = 'UPDATE'
      then (to_jsonb(old)->>'voucher_id')::uuid
    else null
  end;
begin
  if (
    exists (
      select 1
      from public.payroll_statement_decisions decision
      where decision.voucher_id in (
        voucher_id_value,
        prior_voucher_id_value
      )
    )
    or exists (
      select 1
      from public.payroll_statement_allocations allocation
      where allocation.voucher_id in (
        voucher_id_value,
        prior_voucher_id_value
      )
    )
  )
  and not exists (
    select 1
    from public.payroll_statement_command_contexts command_context
    join public.payroll_statement_decisions decision
      on decision.import_id = command_context.import_id
     and decision.tenant_id = command_context.tenant_id
     and decision.voucher_id in (
       voucher_id_value,
       prior_voucher_id_value
     )
    where command_context.transaction_id = txid_current()
      and command_context.command = 'apply'
      and command_context.tenant_id = tenant_id_value
  )
  and not (
    tg_table_name = 'payroll_vouchers'
    and tg_op = 'UPDATE'
    and (
      to_jsonb(new) - array[
        'status',
        'paid_at',
        'paid_by',
        'updated_at',
        'reconciliation_version'
      ]::text[]
    ) = (
      to_jsonb(old) - array[
        'status',
        'paid_at',
        'paid_by',
        'updated_at',
        'reconciliation_version'
      ]::text[]
    )
    and exists (
      select 1
      from public.payroll_statement_command_contexts command_context
      join public.payroll_statement_decisions decision
        on decision.import_id = command_context.import_id
       and decision.tenant_id = command_context.tenant_id
       and decision.voucher_id = voucher_id_value
      where command_context.transaction_id = txid_current()
        and command_context.command = 'manual_settlement'
        and command_context.tenant_id = tenant_id_value
    )
  ) then
    raise exception 'payroll_reconciled_voucher_is_immutable'
      using
        errcode = '55000',
        detail = 'Use a future audited reconciliation reversal command';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function
  public.guard_reconciled_payroll_voucher_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_reconciled_payroll_voucher
  on public.payroll_vouchers;
create trigger trg_guard_reconciled_payroll_voucher
  before update or delete on public.payroll_vouchers
  for each row
  execute function public.guard_reconciled_payroll_voucher_mutation();

drop trigger if exists trg_guard_reconciled_payroll_voucher_line
  on public.payroll_voucher_lines;
create trigger trg_guard_reconciled_payroll_voucher_line
  before insert or update or delete on public.payroll_voucher_lines
  for each row
  execute function public.guard_reconciled_payroll_voucher_mutation();

create or replace function public.guard_payroll_expense_payment_balance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  expense_id_value uuid := case
    when tg_op = 'DELETE' then old.expense_id
    else new.expense_id
  end;
  payment_id_value uuid := case
    when tg_op = 'INSERT' then null
    else old.id
  end;
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then old.tenant_id
    else new.tenant_id
  end;
  line_row record;
  settled_value numeric(14,2);
begin
  select
    voucher_line.id,
    voucher_line.tenant_id,
    voucher_line.voucher_id,
    voucher_line.total_amount
  into line_row
  from public.payroll_voucher_lines voucher_line
  where voucher_line.expense_id = expense_id_value;

  if not found then
    if tg_op = 'UPDATE'
       and old.expense_id is distinct from new.expense_id
       and exists (
         select 1
         from public.payroll_voucher_lines voucher_line
         where voucher_line.expense_id = old.expense_id
       ) then
      raise exception 'payroll_payment_expense_link_is_immutable'
        using errcode = '55000';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if line_row.tenant_id <> tenant_id_value then
    raise exception 'payroll_payment_tenant_mismatch'
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.payroll_statement_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'apply'
     )
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'manual_payment'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if (
    tg_op in ('UPDATE', 'DELETE')
    and exists (
      select 1
      from public.payroll_money_operation_movements movement
      where movement.expense_payment_id = old.id
    )
  ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Use a future audited idempotent reversal command';
  end if;

  if (
    tg_op in ('UPDATE', 'DELETE')
    and exists (
      select 1
      from public.payroll_statement_allocations allocation
      where allocation.expense_payment_id = old.id
    )
  ) then
    raise exception 'payroll_reconciled_payment_is_immutable'
      using
        errcode = '55000',
        detail = 'Use a future audited reconciliation reversal command';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'legacy_reversal'
     ) then
    -- PostgreSQL obtains the target payment row lock before this BEFORE
    -- trigger. Reject untrusted edits before taking the tenant advisory lock,
    -- so direct DML cannot invert the command lock order.
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  perform voucher.id
  from public.payroll_vouchers voucher
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.id = line_row.id
    and voucher_line.tenant_id = tenant_id_value
  for update;

  if tg_op = 'UPDATE'
     and old.expense_id is distinct from new.expense_id then
    raise exception 'payroll_payment_expense_link_is_immutable'
      using errcode = '55000';
  end if;

  if tg_op <> 'DELETE' then
    select
      coalesce(
        (
          select sum(payment.amount)
          from public.expense_payments payment
          where payment.expense_id = expense_id_value
            and payment.id is distinct from payment_id_value
        ),
        0
      )
      + coalesce(
        (
          select sum(allocation.amount)
          from public.employee_advance_allocations allocation
          where allocation.voucher_line_id = line_row.id
        ),
        0
      )
    into settled_value;

    if new.amount <= 0
       or settled_value + new.amount
            > line_row.total_amount + 0.01 then
      raise exception 'payroll_expense_payment_exceeds_line_balance'
        using errcode = '23514';
    end if;
  end if;

  update public.payroll_vouchers voucher
  set updated_at = statement_timestamp()
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_payroll_expense_payment_balance()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aaa_payroll_expense_payment_balance
  on public.expense_payments;
create trigger trg_aaa_payroll_expense_payment_balance
  before insert or update or delete on public.expense_payments
  for each row
  execute function public.guard_payroll_expense_payment_balance();

create or replace function public.guard_payroll_advance_allocation_evidence()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then old.tenant_id
    else new.tenant_id
  end;
  voucher_line_id_value uuid := case
    when tg_op = 'DELETE' then old.voucher_line_id
    else new.voucher_line_id
  end;
  advance_id_value uuid := case
    when tg_op = 'DELETE' then old.advance_id
    else new.advance_id
  end;
  line_row record;
begin
  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_money_operation_movements movement
       where movement.advance_allocation_id = old.id
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Use a future audited idempotent reversal command';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_statement_allocations allocation
       where allocation.employee_advance_allocation_id = old.id
     ) then
    raise exception 'payroll_reconciled_advance_allocation_is_immutable'
      using
        errcode = '55000',
        detail = 'Use a future audited reconciliation reversal command';
  end if;

  select
    voucher_line.id,
    voucher_line.tenant_id,
    voucher_line.voucher_id
  into line_row
  from public.payroll_voucher_lines voucher_line
  where voucher_line.id = voucher_line_id_value;

  if not found then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if line_row.tenant_id <> tenant_id_value then
    raise exception 'payroll_advance_allocation_tenant_mismatch'
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.payroll_statement_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'apply'
     )
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'manual_payment'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'legacy_reversal'
     ) then
    -- Reject before acquiring the advisory lock: the target allocation row is
    -- already locked by PostgreSQL when this BEFORE trigger runs.
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  perform voucher.id
  from public.payroll_vouchers voucher
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  perform advance.id
  from public.employee_advances advance
  where advance.id = advance_id_value
    and advance.tenant_id = tenant_id_value
  for update;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.id = voucher_line_id_value
    and voucher_line.tenant_id = tenant_id_value
  for update;

  update public.payroll_vouchers voucher
  set updated_at = statement_timestamp()
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function
  public.guard_payroll_advance_allocation_evidence()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aaa_payroll_advance_allocation_evidence
  on public.employee_advance_allocations;
create trigger trg_aaa_payroll_advance_allocation_evidence
  before insert or update or delete on public.employee_advance_allocations
  for each row
  execute function public.guard_payroll_advance_allocation_evidence();

create or replace function public.guard_employee_advance_money_command()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = new.tenant_id
         and command_context.command = 'advance_registration'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE'
     and exists (
       select 1
       from public.payroll_money_operations money_operation
       where money_operation.employee_advance_id = old.id
         and money_operation.tenant_id = old.tenant_id
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Use a future audited idempotent reversal command';
  end if;

  if tg_op = 'UPDATE'
     and exists (
       select 1
       from public.payroll_money_operations money_operation
       where money_operation.employee_advance_id = old.id
         and money_operation.tenant_id = old.tenant_id
     )
     and (
       to_jsonb(new) - array[
         'amount_applied',
         'status',
         'updated_at'
       ]::text[]
     ) <> (
       to_jsonb(old) - array[
         'amount_applied',
         'status',
         'updated_at'
       ]::text[]
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Only allocation-derived advance fields may change';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_employee_advance_money_command()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aaa_employee_advance_money_command
  on public.employee_advances;
create trigger trg_aaa_employee_advance_money_command
  before insert or update or delete on public.employee_advances
  for each row
  execute function public.guard_employee_advance_money_command();

alter table public.payroll_statement_account_mappings enable row level security;
alter table public.payroll_voucher_draft_operations enable row level security;
alter table public.payroll_money_operations enable row level security;
alter table public.payroll_money_operation_movements enable row level security;
alter table public.payroll_statement_imports enable row level security;
alter table public.payroll_statement_import_operations enable row level security;
alter table public.payroll_statement_rows enable row level security;
alter table public.payroll_statement_decisions enable row level security;
alter table public.payroll_statement_allocations enable row level security;

drop policy if exists payroll_statement_imports_read_payroll
  on public.payroll_statement_imports;
create policy payroll_statement_imports_read_payroll
  on public.payroll_statement_imports
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_statement_account_mappings_read_payroll
  on public.payroll_statement_account_mappings;
create policy payroll_statement_account_mappings_read_payroll
  on public.payroll_statement_account_mappings
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_voucher_draft_operations_read_payroll
  on public.payroll_voucher_draft_operations;
create policy payroll_voucher_draft_operations_read_payroll
  on public.payroll_voucher_draft_operations
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_money_operations_read_payroll
  on public.payroll_money_operations;
create policy payroll_money_operations_read_payroll
  on public.payroll_money_operations
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_money_operation_movements_read_payroll
  on public.payroll_money_operation_movements;
create policy payroll_money_operation_movements_read_payroll
  on public.payroll_money_operation_movements
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_statement_import_operations_read_payroll
  on public.payroll_statement_import_operations;
create policy payroll_statement_import_operations_read_payroll
  on public.payroll_statement_import_operations
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_statement_rows_read_payroll
  on public.payroll_statement_rows;
create policy payroll_statement_rows_read_payroll
  on public.payroll_statement_rows
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_statement_decisions_read_payroll
  on public.payroll_statement_decisions;
create policy payroll_statement_decisions_read_payroll
  on public.payroll_statement_decisions
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

drop policy if exists payroll_statement_allocations_read_payroll
  on public.payroll_statement_allocations;
create policy payroll_statement_allocations_read_payroll
  on public.payroll_statement_allocations
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

do $$
declare
  table_name_value text;
begin
  foreach table_name_value in array array[
    'payroll_statement_account_mappings',
    'payroll_voucher_draft_operations',
    'payroll_money_operations',
    'payroll_money_operation_movements',
    'payroll_statement_imports',
    'payroll_statement_import_operations',
    'payroll_statement_rows',
    'payroll_statement_decisions',
    'payroll_statement_allocations'
  ]
  loop
    execute format(
      'revoke all on table public.%I '
      || 'from public, anon, authenticated, service_role',
      table_name_value
    );
    execute format(
      'grant select on table public.%I to authenticated',
      table_name_value
    );
    execute format(
      'grant select on table public.%I to service_role',
      table_name_value
    );
  end loop;
end
$$;

revoke all on table public.payroll_statement_command_contexts
  from public, anon, authenticated, service_role;
revoke all on table public.payroll_money_command_contexts
  from public, anon, authenticated, service_role;

create or replace function public.create_payroll_statement_import(
  p_operation_key text,
  p_file_sha256 text,
  p_source_metadata jsonb,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  file_sha256_value text := lower(trim(coalesce(p_file_sha256, '')));
  source_metadata_value jsonb := coalesce(p_source_metadata, '{}'::jsonb);
  payload_hash_value text;
  existing_import public.payroll_statement_imports%rowtype;
  existing_operation public.payroll_statement_import_operations%rowtype;
  import_id_value uuid;
  import_receipt_value jsonb;
  account_fingerprint_value text;
  erp_account_id_value uuid;
  revision_value integer := 1;
  is_revision_value boolean := false;
  row_value jsonb;
  row_ordinal_value integer;
  page_number_value integer;
  source_line_start_value integer;
  source_line_end_value integer;
  supplied_source_occurrence_value integer;
  source_occurrence_value integer;
  expected_source_occurrence_value integer;
  transaction_date_value date;
  direction_value text;
  amount_value numeric(14,2);
  description_observed_value text;
  beneficiary_observed_value text;
  document_observed_value text;
  document_normalized_value text;
  description_normalized_value text;
  beneficiary_normalized_value text;
  base_fingerprint_value text;
  fingerprint_value text;
  supplied_fingerprint_value text;
  warnings_value jsonb;
  parser_name_value text;
  parser_version_value text;
  source_type_value text;
  statement_start_value date;
  statement_end_value date;
  document_date_value date;
  row_count_value integer;
  violated_constraint_name text;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll statement access denied'
      using errcode = '42501';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$' then
    raise exception 'payroll_statement_invalid_operation_key'
      using errcode = '22023';
  end if;

  if file_sha256_value !~ '^[0-9a-f]{64}$' then
    raise exception 'payroll_statement_invalid_file_sha256'
      using errcode = '22023';
  end if;

  if jsonb_typeof(source_metadata_value) <> 'object'
     or octet_length(source_metadata_value::text) > 8192 then
    raise exception 'payroll_statement_invalid_source_metadata'
      using errcode = '22023';
  end if;

  -- Metadata is deliberately allowlisted. Account numbers, RUTs, statement
  -- holders, balances, and raw filenames are not accepted by this boundary.
  if exists (
    select 1
    from jsonb_object_keys(source_metadata_value) metadata_key
    where metadata_key not in (
      'parser_name',
      'parser_version',
      'source_type',
      'page_count',
      'extraction_kind',
      'locale',
      'statement_start',
      'statement_end',
      'document_date',
      'bank_name',
      'account_fingerprint',
      'erp_account_id'
    )
  ) then
    raise exception 'payroll_statement_source_metadata_key_not_allowed'
      using errcode = '22023';
  end if;

  parser_name_value :=
    trim(coalesce(source_metadata_value->>'parser_name', ''));
  parser_version_value :=
    trim(coalesce(source_metadata_value->>'parser_version', ''));
  source_type_value :=
    lower(trim(coalesce(source_metadata_value->>'source_type', '')));
  account_fingerprint_value := lower(
    trim(coalesce(source_metadata_value->>'account_fingerprint', ''))
  );
  erp_account_id_value :=
    nullif(source_metadata_value->>'erp_account_id', '')::uuid;
  statement_start_value :=
    nullif(source_metadata_value->>'statement_start', '')::date;
  statement_end_value :=
    nullif(source_metadata_value->>'statement_end', '')::date;
  document_date_value :=
    nullif(source_metadata_value->>'document_date', '')::date;

  if char_length(parser_name_value) not between 1 and 100
     or char_length(parser_version_value) not between 1 and 100
     or source_type_value not in ('pdf_text', 'pdf_ocr', 'image_ocr')
     or account_fingerprint_value !~ '^[0-9a-f]{64}$'
     or erp_account_id_value is null
     or (
       (statement_start_value is null)
         <> (statement_end_value is null)
     )
     or (
       statement_start_value is not null
       and (
         statement_start_value not between
           date '1900-01-01' and date '2100-12-31'
         or statement_end_value not between
           statement_start_value and date '2100-12-31'
       )
     )
     or (
       document_date_value is not null
       and document_date_value not between
         date '1900-01-01' and date '2100-12-31'
     ) then
    raise exception 'payroll_statement_invalid_parser_metadata'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.accounts account_row
    where account_row.id = erp_account_id_value
      and account_row.tenant_id = tenant_id_value
      and account_row.is_active is true
      and account_row.type = 'asset'
  ) then
    raise exception 'payroll_statement_erp_account_not_available'
      using errcode = '42501';
  end if;

  if p_rows is null
     or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) not between 1 and 2000 then
    raise exception 'payroll_statement_invalid_rows'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'file_sha256',
          file_sha256_value,
          'source_metadata',
          source_metadata_value,
          'rows',
          p_rows
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text
      || ':payroll-statement-file:'
      || file_sha256_value,
      0
    )
  );
  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text
      || ':payroll-statement-import:'
      || operation_key_value,
      0
    )
  );

  select import_operation.*
  into existing_operation
  from public.payroll_statement_import_operations import_operation
  where import_operation.tenant_id = tenant_id_value
    and import_operation.operation_key = operation_key_value;

  if found then
    if existing_operation.payload_hash <> payload_hash_value then
      raise exception 'payroll_statement_import_idempotency_conflict'
        using
          errcode = 'P0001',
          detail = 'operation_key already has a different payload';
    end if;

    select import_row.*
    into existing_import
    from public.payroll_statement_imports import_row
    where import_row.id = existing_operation.import_id
      and import_row.tenant_id = tenant_id_value
    for update;

    if not found
       or existing_import.revision <> existing_operation.revision then
      raise exception 'payroll_statement_import_revision_superseded'
        using
          errcode = '40001',
          detail = 'reload the current OCR review revision';
    end if;

    return existing_operation.receipt;
  end if;

  select import_row.*
  into existing_import
  from public.payroll_statement_imports import_row
  where import_row.tenant_id = tenant_id_value
    and import_row.file_sha256 = file_sha256_value
  for update;

  if found then
    import_id_value := existing_import.id;
    revision_value := existing_import.revision;

    if existing_import.create_payload_hash = payload_hash_value then
      insert into public.payroll_statement_import_operations (
        tenant_id,
        import_id,
        operation_key,
        payload_hash,
        revision,
        receipt,
        created_by
      )
      values (
        tenant_id_value,
        import_id_value,
        operation_key_value,
        payload_hash_value,
        revision_value,
        existing_import.import_receipt,
        auth.uid()
      );
      return existing_import.import_receipt;
    end if;

    if existing_import.status <> 'review' then
      raise exception 'payroll_statement_applied_import_cannot_be_revised'
        using
          errcode = '55000',
          detail = 'applied and held evidence is immutable';
    end if;

    if existing_import.revision >= 1000 then
      raise exception 'payroll_statement_revision_limit_reached'
        using errcode = '54000';
    end if;

    revision_value := existing_import.revision + 1;
    is_revision_value := true;

    insert into public.payroll_statement_command_contexts (
      transaction_id,
      tenant_id,
      import_id,
      command,
      actor_id
    )
    values (
      txid_current(),
      tenant_id_value,
      import_id_value,
      'import_revision',
      auth.uid()
    );

    delete from public.payroll_statement_rows statement_row
    where statement_row.import_id = import_id_value
      and statement_row.tenant_id = tenant_id_value;

    update public.payroll_statement_imports import_row
    set account_fingerprint = account_fingerprint_value,
        erp_account_id = erp_account_id_value,
        source_metadata = source_metadata_value,
        parser_name = parser_name_value,
        parser_version = parser_version_value,
        source_type = source_type_value,
        row_count = 0,
        revision = revision_value,
        create_payload_hash = payload_hash_value,
        import_receipt = null,
        updated_at = statement_timestamp()
    where import_row.id = import_id_value
      and import_row.tenant_id = tenant_id_value;
  else
    insert into public.payroll_statement_imports (
      tenant_id,
      file_sha256,
      account_fingerprint,
      erp_account_id,
      source_metadata,
      parser_name,
      parser_version,
      source_type,
      revision,
      create_operation_key,
      create_payload_hash,
      created_by
    )
    values (
      tenant_id_value,
      file_sha256_value,
      account_fingerprint_value,
      erp_account_id_value,
      source_metadata_value,
      parser_name_value,
      parser_version_value,
      source_type_value,
      revision_value,
      operation_key_value,
      payload_hash_value,
      auth.uid()
    )
    returning id into import_id_value;
  end if;

  for row_value in
    select row_element.value
    from jsonb_array_elements(p_rows) with ordinality row_element(value, n)
    order by row_element.n
  loop
    if jsonb_typeof(row_value) <> 'object' then
      raise exception 'payroll_statement_row_must_be_object'
        using errcode = '22023';
    end if;

    row_ordinal_value := nullif(
      coalesce(
        row_value->>'ordinal',
        row_value->>'source_ordinal'
      ),
      ''
    )::integer;
    page_number_value := nullif(
      coalesce(
        row_value->>'page',
        row_value->>'page_number'
      ),
      ''
    )::integer;
    source_line_start_value :=
      nullif(row_value->>'source_line_start', '')::integer;
    source_line_end_value :=
      nullif(row_value->>'source_line_end', '')::integer;
    supplied_source_occurrence_value :=
      nullif(row_value->>'source_occurrence', '')::integer;
    source_occurrence_value :=
      coalesce(supplied_source_occurrence_value, 1);
    transaction_date_value := nullif(
      coalesce(
        row_value->>'transaction_date',
        row_value->>'booking_date'
      ),
      ''
    )::date;
    direction_value :=
      nullif(lower(trim(coalesce(row_value->>'direction', ''))), '');
    amount_value := nullif(
      coalesce(
        row_value->>'amount',
        case
          when direction_value = 'debit'
            then row_value->>'debit_amount_clp'
          when direction_value = 'credit'
            then row_value->>'credit_amount_clp'
          else null
        end
      ),
      ''
    )::numeric;
    description_observed_value :=
      nullif(trim(row_value->>'description_observed'), '');
    beneficiary_observed_value :=
      nullif(trim(row_value->>'beneficiary_observed'), '');
    document_observed_value := nullif(
      trim(
        coalesce(
          row_value->>'document_observed',
          row_value->>'document_number'
        )
      ),
      ''
    );
    warnings_value := coalesce(
      row_value->'warnings',
      row_value->'warning_codes',
      '[]'::jsonb
    );

    if jsonb_typeof(warnings_value) <> 'array' then
      raise exception 'payroll_statement_invalid_row_%', row_ordinal_value
        using errcode = '22023';
    end if;

    if row_ordinal_value not between 1 and 2000
       or (
         page_number_value is not null
         and page_number_value not between 1 and 10000
       )
       or (
         (source_line_start_value is null)
           <> (source_line_end_value is null)
       )
       or (
         source_line_start_value is not null
         and (
           source_line_start_value not between 1 and 1000000
           or source_line_end_value not between
                source_line_start_value and 1000000
         )
       )
       or source_occurrence_value not between 1 and 2000
       or (
         transaction_date_value is not null
         and transaction_date_value not between
           date '1900-01-01' and date '2100-12-31'
       )
       or (
         direction_value is not null
         and direction_value not in ('debit', 'credit', 'unknown')
       )
       or (
         amount_value is not null
         and (
           amount_value::text = 'NaN'
           or amount_value <= 0
           or amount_value > 999999999999.99
           or round(amount_value, 2) <> amount_value
         )
       )
       or (
         description_observed_value is null
         and beneficiary_observed_value is null
       )
       or char_length(coalesce(description_observed_value, '')) > 500
       or char_length(coalesce(beneficiary_observed_value, '')) > 200
       or char_length(coalesce(document_observed_value, '')) > 100
       or octet_length(warnings_value::text) > 8192
       or exists (
         select 1
         from jsonb_array_elements(warnings_value) warning_element
         where jsonb_typeof(warning_element) <> 'string'
            or char_length(warning_element #>> '{}') not between 1 and 100
            or (warning_element #>> '{}') !~ '^[a-z0-9_:-]+$'
       ) then
      raise exception 'payroll_statement_invalid_row_%', row_ordinal_value
        using errcode = '22023';
    end if;

    if transaction_date_value is null
       and not (
         warnings_value @> '["missing_transaction_date"]'::jsonb
       ) then
      warnings_value :=
        warnings_value || '["missing_transaction_date"]'::jsonb;
    end if;

    if direction_value is null
       and not (warnings_value @> '["missing_direction"]'::jsonb) then
      warnings_value := warnings_value || '["missing_direction"]'::jsonb;
    elsif direction_value = 'unknown'
       and not (warnings_value @> '["unknown_direction"]'::jsonb) then
      warnings_value := warnings_value || '["unknown_direction"]'::jsonb;
    end if;

    if amount_value is null
       and not (warnings_value @> '["missing_amount"]'::jsonb) then
      warnings_value := warnings_value || '["missing_amount"]'::jsonb;
    end if;

    if (
      transaction_date_value is null
      or direction_value is null
      or direction_value = 'unknown'
      or amount_value is null
    ) and not (warnings_value @> '["incomplete_evidence"]'::jsonb) then
      warnings_value := warnings_value || '["incomplete_evidence"]'::jsonb;
    end if;

    if statement_start_value is not null
       and transaction_date_value is not null
       and transaction_date_value not between
         statement_start_value and statement_end_value
       and not (
         warnings_value @> '["out_of_statement_range"]'::jsonb
       ) then
      warnings_value :=
        warnings_value || '["out_of_statement_range"]'::jsonb;
    end if;

    if jsonb_array_length(warnings_value) > 20
       or octet_length(warnings_value::text) > 8192 then
      raise exception 'payroll_statement_invalid_row_%', row_ordinal_value
        using errcode = '22023';
    end if;

    description_normalized_value :=
      public.normalize_payroll_statement_text(
        description_observed_value
      );
    beneficiary_normalized_value :=
      public.normalize_payroll_statement_text(
        beneficiary_observed_value
      );
    document_normalized_value :=
      public.normalize_payroll_statement_text(
        document_observed_value
      );

    if row_value ? 'description_normalized'
       and nullif(row_value->>'description_normalized', '')
            is distinct from description_normalized_value then
      raise exception
        'payroll_statement_description_normalization_mismatch_%',
        row_ordinal_value
        using errcode = '22023';
    end if;

    if row_value ? 'beneficiary_normalized'
       and nullif(row_value->>'beneficiary_normalized', '')
            is distinct from beneficiary_normalized_value then
      raise exception
        'payroll_statement_beneficiary_normalization_mismatch_%',
        row_ordinal_value
        using errcode = '22023';
    end if;

    base_fingerprint_value := encode(
      extensions.digest(
        convert_to(
          concat_ws(
            '|',
            account_fingerprint_value,
            coalesce(transaction_date_value::text, ''),
            case
              when direction_value = 'unknown' then ''
              else coalesce(direction_value, '')
            end,
            coalesce(
              to_char(amount_value, 'FM999999999999990.00'),
              ''
            ),
            coalesce(description_normalized_value, ''),
            coalesce(beneficiary_normalized_value, ''),
            coalesce(document_normalized_value, '')
          ),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    select count(*)::integer + 1
    into expected_source_occurrence_value
    from public.payroll_statement_rows prior_row
    where prior_row.import_id = import_id_value
      and prior_row.base_fingerprint = base_fingerprint_value;

    if supplied_source_occurrence_value is not null
       and supplied_source_occurrence_value
            <> expected_source_occurrence_value then
      raise exception
        'payroll_statement_source_occurrence_mismatch_%',
        row_ordinal_value
        using
          errcode = '22023',
          detail =
            'source_occurrence must be the deterministic occurrence '
            || 'of the normalized row within this import';
    end if;
    source_occurrence_value := expected_source_occurrence_value;

    fingerprint_value := encode(
      extensions.digest(
        convert_to(
          concat_ws(
            '|',
            account_fingerprint_value,
            coalesce(transaction_date_value::text, ''),
            case
              when direction_value = 'unknown' then ''
              else coalesce(direction_value, '')
            end,
            coalesce(
              to_char(amount_value, 'FM999999999999990.00'),
              ''
            ),
            coalesce(description_normalized_value, ''),
            coalesce(beneficiary_normalized_value, ''),
            coalesce(document_normalized_value, ''),
            source_occurrence_value::text
          ),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );
    supplied_fingerprint_value := lower(
      nullif(
        trim(
          coalesce(
            row_value->>'fingerprint',
            row_value->>'source_fingerprint'
          )
        ),
        ''
      )
    );

    if supplied_fingerprint_value is not null
       and supplied_fingerprint_value <> fingerprint_value then
      raise exception 'payroll_statement_fingerprint_mismatch_%',
        row_ordinal_value
        using errcode = '22023';
    end if;

    insert into public.payroll_statement_rows (
      tenant_id,
      import_id,
      row_ordinal,
      page_number,
      source_line_start,
      source_line_end,
      source_occurrence,
      transaction_date,
      direction,
      amount,
      description_observed,
      beneficiary_observed,
      document_observed,
      description_normalized,
      beneficiary_normalized,
      base_fingerprint,
      fingerprint,
      warnings
    )
    values (
      tenant_id_value,
      import_id_value,
      row_ordinal_value,
      page_number_value,
      source_line_start_value,
      source_line_end_value,
      source_occurrence_value,
      transaction_date_value,
      direction_value,
      amount_value,
      description_observed_value,
      beneficiary_observed_value,
      document_observed_value,
      description_normalized_value,
      beneficiary_normalized_value,
      base_fingerprint_value,
      fingerprint_value,
      warnings_value
    );
  end loop;

  select count(*)::integer
  into row_count_value
  from public.payroll_statement_rows statement_row
  where statement_row.import_id = import_id_value;

  import_receipt_value := jsonb_build_object(
    'import_id',
    import_id_value,
    'status',
    'review',
    'revision',
    revision_value,
    'revised',
    is_revision_value,
    'row_count',
    row_count_value,
    'rows',
    (
      select jsonb_agg(
        jsonb_build_object(
          'row_id',
          statement_row.id,
          'fingerprint',
          statement_row.fingerprint,
          'base_fingerprint',
          statement_row.base_fingerprint,
          'ordinal',
          statement_row.row_ordinal
        )
        order by statement_row.row_ordinal
      )
      from public.payroll_statement_rows statement_row
      where statement_row.import_id = import_id_value
    ),
    'file_sha256',
    file_sha256_value,
    'account_fingerprint',
    account_fingerprint_value,
    'erp_account_id',
    erp_account_id_value,
    'payload_hash',
    payload_hash_value
  );

  update public.payroll_statement_imports import_row
  set row_count = row_count_value,
      import_receipt = import_receipt_value,
      updated_at = statement_timestamp()
  where import_row.id = import_id_value;

  insert into public.payroll_statement_import_operations (
    tenant_id,
    import_id,
    operation_key,
    payload_hash,
    revision,
    receipt,
    created_by
  )
  values (
    tenant_id_value,
    import_id_value,
    operation_key_value,
    payload_hash_value,
    revision_value,
    import_receipt_value,
    auth.uid()
  );

  if is_revision_value then
    delete from public.payroll_statement_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.import_id = import_id_value
      and command_context.command = 'import_revision';
  end if;

  return import_receipt_value;
exception
  when unique_violation then
    get stacked diagnostics
      violated_constraint_name = constraint_name;
    if violated_constraint_name in (
      'payroll_statement_rows_import_id_row_ordinal_key',
      'payroll_statement_rows_import_id_fingerprint_key'
    ) then
      raise exception 'payroll_statement_indistinguishable_duplicate_row'
        using
          errcode = '23505',
          detail = 'Exact statement rows require a stable bank document id';
    elsif violated_constraint_name in (
      'payroll_statement_import_operations_tenant_id_operation_key_key',
      'ux_payroll_statement_imports_tenant_file',
      'ux_payroll_statement_imports_create_operation'
    ) then
      raise exception 'payroll_statement_duplicate_row_or_operation'
        using errcode = '23505';
    else
      raise;
    end if;
end;
$$;

create or replace function public.save_payroll_voucher_draft(
  p_voucher_id uuid,
  p_operation_key text,
  p_expected_reconciliation_version bigint,
  p_header jsonb,
  p_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  header_value jsonb := coalesce(p_header, '{}'::jsonb);
  lines_value jsonb := coalesce(p_lines, '[]'::jsonb);
  payload_hash_value text;
  existing_operation public.payroll_voucher_draft_operations%rowtype;
  voucher_row public.payroll_vouchers%rowtype;
  voucher_id_value uuid := p_voucher_id;
  voucher_number_value text;
  next_voucher_number_value integer;
  period_start_value date;
  period_end_value date;
  period_label_value text;
  notes_value text;
  line_value jsonb;
  line_ordinal_value integer;
  line_id_value uuid;
  employee_id_value uuid;
  employee_name_value text;
  worked_hours_value numeric;
  overtime_hours_value numeric;
  hourly_rate_value numeric;
  overtime_rate_value numeric;
  regular_amount_value numeric(12,2);
  overtime_amount_value numeric(12,2);
  total_amount_value numeric(12,2);
  payment_method_value text;
  payment_method_id_value uuid;
  payment_account_id_value uuid;
  method_account_id_value uuid;
  salary_account_id_value uuid;
  is_included_value boolean;
  total_hours_value numeric(10,2);
  voucher_total_value numeric(12,2);
  employee_count_value integer;
  reconciliation_version_value bigint;
  receipt_value jsonb;
  created_value boolean := p_voucher_id is null;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$' then
    raise exception 'payroll_draft_invalid_operation_key'
      using errcode = '22023';
  end if;

  if jsonb_typeof(header_value) <> 'object'
     or jsonb_typeof(lines_value) <> 'array'
     or jsonb_array_length(lines_value) > 2000
     or not (header_value ? 'period_start')
     or not (header_value ? 'period_end')
     or exists (
       select 1
       from jsonb_object_keys(header_value) header_key
       where header_key not in (
         'period_start',
         'period_end',
         'period_label',
         'notes'
       )
     ) then
    raise exception 'payroll_draft_invalid_payload'
      using errcode = '22023';
  end if;

  period_start_value :=
    nullif(trim(header_value->>'period_start'), '')::date;
  period_end_value :=
    nullif(trim(header_value->>'period_end'), '')::date;
  period_label_value :=
    nullif(trim(header_value->>'period_label'), '');
  notes_value := nullif(trim(header_value->>'notes'), '');

  if period_start_value is null
     or period_end_value is null
     or period_start_value not between
       date '1900-01-01' and date '2100-12-31'
     or period_end_value not between
       period_start_value and date '2100-12-31'
     or char_length(coalesce(period_label_value, '')) > 200
     or char_length(coalesce(notes_value, '')) > 2000
     or (
       p_voucher_id is null
       and p_expected_reconciliation_version is not null
     )
     or (
       p_voucher_id is not null
       and (
         p_expected_reconciliation_version is null
         or p_expected_reconciliation_version < 0
       )
     ) then
    raise exception 'payroll_draft_invalid_header'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'voucher_id',
          p_voucher_id,
          'expected_reconciliation_version',
          p_expected_reconciliation_version,
          'header',
          header_value,
          'lines',
          lines_value
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  -- This is the same tenant lock used by reconciliation and manual settlement.
  -- It is acquired before any voucher or line lock.
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
    raise exception 'payroll_draft_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different payload';
  end if;

  if p_voucher_id is not null then
    select voucher.*
    into voucher_row
    from public.payroll_vouchers voucher
    where voucher.id = p_voucher_id
      and voucher.tenant_id = tenant_id_value
    for update;

    if not found then
      raise exception 'Payroll voucher not found'
        using errcode = '42501';
    end if;

    if voucher_row.status <> 'draft' then
      raise exception 'payroll_draft_not_editable'
        using errcode = '55000';
    end if;

    if voucher_row.reconciliation_version
         <> p_expected_reconciliation_version then
      raise exception 'payroll_draft_version_conflict'
        using
          errcode = '40001',
          detail = 'reload the complete payroll draft before saving';
    end if;

    perform voucher_line.id
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = p_voucher_id
      and voucher_line.tenant_id = tenant_id_value
    order by voucher_line.id
    for update;

    if exists (
      select 1
      from public.payroll_statement_decisions decision
      where decision.voucher_id = p_voucher_id
    ) or exists (
      select 1
      from public.payroll_statement_allocations allocation
      where allocation.voucher_id = p_voucher_id
    ) or exists (
      select 1
      from public.payroll_voucher_lines voucher_line
      where voucher_line.voucher_id = p_voucher_id
        and (
          voucher_line.expense_id is not null
          or exists (
            select 1
            from public.employee_advance_allocations allocation
            where allocation.voucher_line_id = voucher_line.id
          )
        )
    ) then
      raise exception 'payroll_draft_has_settlement_evidence'
        using errcode = '55000';
    end if;
  end if;

  create temporary table if not exists
    pg_temp.payroll_voucher_draft_lines_input (
      line_ordinal integer primary key,
      line_id uuid not null unique,
      employee_id uuid not null unique,
      employee_name text not null,
      worked_hours numeric(10,2) not null,
      overtime_hours numeric(10,2) not null,
      hourly_rate numeric(10,2) not null,
      overtime_rate numeric(10,2) not null,
      regular_amount numeric(12,2) not null,
      overtime_amount numeric(12,2) not null,
      total_amount numeric(12,2) not null,
      payment_method text,
      payment_method_id uuid,
      payment_account_id uuid,
      salary_account_id uuid,
      is_included boolean not null
    )
    on commit drop;
  truncate table pg_temp.payroll_voucher_draft_lines_input;

  for line_value, line_ordinal_value in
    select line_element.value, line_element.n::integer
    from jsonb_array_elements(lines_value)
      with ordinality line_element(value, n)
    order by line_element.n
  loop
    if jsonb_typeof(line_value) <> 'object'
       or exists (
         select 1
         from jsonb_object_keys(line_value) line_key
         where line_key not in (
           'line_id',
           'employee_id',
           'worked_hours',
           'overtime_hours',
           'hourly_rate',
           'overtime_rate',
           'payment_method',
           'payment_method_id',
           'payment_account_id',
           'salary_account_id',
           'is_included'
         )
       ) then
      raise exception 'payroll_draft_invalid_line_%', line_ordinal_value
        using errcode = '22023';
    end if;

    line_id_value := coalesce(
      nullif(line_value->>'line_id', '')::uuid,
      gen_random_uuid()
    );
    employee_id_value :=
      nullif(line_value->>'employee_id', '')::uuid;
    worked_hours_value := coalesce(
      nullif(line_value->>'worked_hours', '')::numeric,
      0
    );
    overtime_hours_value := coalesce(
      nullif(line_value->>'overtime_hours', '')::numeric,
      0
    );
    hourly_rate_value := coalesce(
      nullif(line_value->>'hourly_rate', '')::numeric,
      0
    );
    overtime_rate_value := coalesce(
      nullif(line_value->>'overtime_rate', '')::numeric,
      round(hourly_rate_value * 1.5, 2)
    );
    payment_method_value :=
      lower(nullif(trim(line_value->>'payment_method'), ''));
    payment_method_id_value :=
      nullif(line_value->>'payment_method_id', '')::uuid;
    payment_account_id_value :=
      nullif(line_value->>'payment_account_id', '')::uuid;
    salary_account_id_value :=
      nullif(line_value->>'salary_account_id', '')::uuid;
    is_included_value := coalesce(
      nullif(line_value->>'is_included', '')::boolean,
      true
    );

    if employee_id_value is null
       or worked_hours_value::text in ('NaN', 'Infinity', '-Infinity')
       or overtime_hours_value::text in ('NaN', 'Infinity', '-Infinity')
       or hourly_rate_value::text in ('NaN', 'Infinity', '-Infinity')
       or overtime_rate_value::text in ('NaN', 'Infinity', '-Infinity')
       or worked_hours_value not between 0 and 99999999.99
       or overtime_hours_value not between 0 and 99999999.99
       or hourly_rate_value not between 0 and 99999999.99
       or overtime_rate_value not between 0 and 99999999.99
       or round(worked_hours_value, 2) <> worked_hours_value
       or round(overtime_hours_value, 2) <> overtime_hours_value
       or round(hourly_rate_value, 2) <> hourly_rate_value
       or round(overtime_rate_value, 2) <> overtime_rate_value
       or (
         payment_method_value is not null
         and payment_method_value !~ '^[a-z0-9_-]{1,50}$'
       ) then
      raise exception 'payroll_draft_invalid_line_%', line_ordinal_value
        using errcode = '22023';
    end if;

    select trim(employee.first_name || ' ' || employee.last_name)
    into employee_name_value
    from public.employees employee
    where employee.id = employee_id_value
      and employee.tenant_id = tenant_id_value;

    if not found then
      raise exception 'Payroll employee not found'
        using errcode = '42501';
    end if;

    method_account_id_value := null;
    if payment_method_id_value is not null then
      select lower(payment_method.code), payment_method.account_id
      into payment_method_value, method_account_id_value
      from public.payment_methods payment_method
      where payment_method.id = payment_method_id_value
        and payment_method.tenant_id = tenant_id_value;

      if not found then
        raise exception 'Payroll payment method not found'
          using errcode = '42501';
      end if;
    end if;

    payment_account_id_value := coalesce(
      payment_account_id_value,
      method_account_id_value
    );

    if payment_account_id_value is not null
       and not exists (
         select 1
         from public.accounts payment_account
         where payment_account.id = payment_account_id_value
           and payment_account.tenant_id = tenant_id_value
           and payment_account.type = 'asset'
       ) then
      raise exception 'Payroll payment account not found'
        using errcode = '42501';
    end if;

    if method_account_id_value is not null
       and payment_account_id_value <> method_account_id_value then
      raise exception 'payroll_draft_payment_account_mismatch_%',
        line_ordinal_value
        using errcode = '22023';
    end if;

    if salary_account_id_value is not null
       and not exists (
         select 1
         from public.accounts salary_account
         where salary_account.id = salary_account_id_value
           and salary_account.tenant_id = tenant_id_value
           and salary_account.type = 'expense'
       ) then
      raise exception 'Payroll salary account not found'
        using errcode = '42501';
    end if;

    if p_voucher_id is null
       and line_value ? 'line_id'
       and nullif(line_value->>'line_id', '') is not null then
      raise exception 'payroll_draft_new_line_id_must_be_server_owned'
        using errcode = '22023';
    end if;

    if p_voucher_id is not null
       and line_value ? 'line_id'
       and nullif(line_value->>'line_id', '') is not null
       and not exists (
         select 1
         from public.payroll_voucher_lines voucher_line
         where voucher_line.id = line_id_value
           and voucher_line.voucher_id = p_voucher_id
           and voucher_line.tenant_id = tenant_id_value
       ) then
      raise exception 'payroll_draft_line_not_owned'
        using errcode = '42501';
    end if;

    regular_amount_value :=
      round(worked_hours_value * hourly_rate_value, 2);
    overtime_amount_value :=
      round(overtime_hours_value * overtime_rate_value, 2);
    total_amount_value :=
      regular_amount_value + overtime_amount_value;

    if total_amount_value > 9999999999.99 then
      raise exception 'payroll_draft_invalid_line_%', line_ordinal_value
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from pg_temp.payroll_voucher_draft_lines_input draft_line
      where draft_line.line_id = line_id_value
         or draft_line.employee_id = employee_id_value
    ) then
      raise exception 'payroll_draft_duplicate_line_%', line_ordinal_value
        using errcode = '23505';
    end if;

    insert into pg_temp.payroll_voucher_draft_lines_input (
      line_ordinal,
      line_id,
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
    values (
      line_ordinal_value,
      line_id_value,
      employee_id_value,
      employee_name_value,
      worked_hours_value,
      overtime_hours_value,
      hourly_rate_value,
      overtime_rate_value,
      regular_amount_value,
      overtime_amount_value,
      total_amount_value,
      payment_method_value,
      payment_method_id_value,
      payment_account_id_value,
      salary_account_id_value,
      is_included_value
    );
  end loop;

  select
    coalesce(
      sum(draft_line.worked_hours + draft_line.overtime_hours)
        filter (where draft_line.is_included),
      0
    )::numeric(10,2),
    coalesce(
      sum(draft_line.total_amount)
        filter (where draft_line.is_included),
      0
    )::numeric(12,2),
    count(*) filter (where draft_line.is_included)::integer
  into total_hours_value, voucher_total_value, employee_count_value
  from pg_temp.payroll_voucher_draft_lines_input draft_line;

  if p_voucher_id is null then
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
    voucher_id_value := gen_random_uuid();

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
      notes,
      created_by
    )
    values (
      voucher_id_value,
      tenant_id_value,
      voucher_number_value,
      period_start_value,
      period_end_value,
      period_label_value,
      0,
      0,
      0,
      'draft',
      notes_value,
      auth.uid()
    );
  else
    voucher_number_value := voucher_row.voucher_number;

    delete from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = voucher_id_value
      and voucher_line.tenant_id = tenant_id_value;
  end if;

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
    draft_line.line_id,
    tenant_id_value,
    voucher_id_value,
    draft_line.employee_id,
    draft_line.employee_name,
    draft_line.worked_hours,
    draft_line.overtime_hours,
    draft_line.hourly_rate,
    draft_line.overtime_rate,
    draft_line.regular_amount,
    draft_line.overtime_amount,
    draft_line.total_amount,
    draft_line.payment_method,
    draft_line.payment_method_id,
    draft_line.payment_account_id,
    draft_line.salary_account_id,
    draft_line.is_included
  from pg_temp.payroll_voucher_draft_lines_input draft_line
  order by draft_line.line_ordinal;

  update public.payroll_vouchers voucher
  set period_start = period_start_value,
      period_end = period_end_value,
      period_label = period_label_value,
      total_hours = total_hours_value,
      total_amount = voucher_total_value,
      employee_count = employee_count_value,
      notes = notes_value,
      updated_at = statement_timestamp()
  where voucher.id = voucher_id_value
    and voucher.tenant_id = tenant_id_value
  returning voucher.reconciliation_version
  into reconciliation_version_value;

  receipt_value := jsonb_build_object(
    'operation_key',
    operation_key_value,
    'payload_hash',
    payload_hash_value,
    'voucher_id',
    voucher_id_value,
    'voucher_number',
    voucher_number_value,
    'created',
    created_value,
    'status',
    'draft',
    'reconciliation_version',
    reconciliation_version_value,
    'total_hours',
    total_hours_value,
    'total_amount',
    voucher_total_value,
    'employee_count',
    employee_count_value,
    'lines',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'ordinal',
            draft_line.line_ordinal,
            'line_id',
            draft_line.line_id,
            'employee_id',
            draft_line.employee_id
          )
          order by draft_line.line_ordinal
        )
        from pg_temp.payroll_voucher_draft_lines_input draft_line
      ),
      '[]'::jsonb
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
    p_expected_reconciliation_version,
    receipt_value,
    auth.uid()
  );

  return receipt_value;
end;
$$;

-- Draft confirmation is a versioned aggregate command. The immutable
-- operation receipt is checked before the live row so an exact retry after a
-- lost acknowledgement returns the original result even if the voucher later
-- advances to another state.
create or replace function public.confirm_payroll_voucher_v2(
  p_voucher_id uuid,
  p_operation_key text,
  p_expected_reconciliation_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  payload_hash_value text;
  existing_operation public.payroll_voucher_draft_operations%rowtype;
  voucher_row public.payroll_vouchers%rowtype;
  confirmation_result_value boolean;
  confirmed_status_value text;
  reconciliation_version_value bigint;
  receipt_value jsonb;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_voucher_id is null
     or operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or p_expected_reconciliation_version is null
     or p_expected_reconciliation_version < 0 then
    raise exception 'payroll_voucher_lifecycle_invalid_payload'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'command',
          'confirm_draft',
          'voucher_id',
          p_voucher_id,
          'expected_reconciliation_version',
          p_expected_reconciliation_version
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

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
    if existing_operation.payload_hash = payload_hash_value
       and existing_operation.receipt->>'operation' = 'confirm_draft' then
      return existing_operation.receipt;
    end if;
    raise exception 'payroll_voucher_lifecycle_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different payload';
  end if;

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  if not found then
    raise exception 'Payroll voucher not found'
      using errcode = '42501';
  end if;

  if voucher_row.reconciliation_version
       <> p_expected_reconciliation_version then
    raise exception 'payroll_voucher_lifecycle_version_conflict'
      using
        errcode = '40001',
        detail = 'reload the complete payroll voucher before continuing';
  end if;

  if voucher_row.status <> 'draft' then
    raise exception 'payroll_voucher_is_not_a_draft'
      using errcode = '55000';
  end if;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
  order by voucher_line.id
  for update;

  if not exists (
    select 1
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = p_voucher_id
      and voucher_line.tenant_id = tenant_id_value
      and voucher_line.is_included is true
      and voucher_line.total_amount > 0
  ) then
    raise exception 'payroll_voucher_has_no_positive_obligations'
      using errcode = '22023';
  end if;

  confirmation_result_value :=
    public.confirm_payroll_voucher_internal(p_voucher_id);

  select voucher.status, voucher.reconciliation_version
  into confirmed_status_value, reconciliation_version_value
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value;

  if confirmation_result_value is distinct from true
     or confirmed_status_value <> 'confirmed' then
    raise exception 'payroll_voucher_confirmation_not_committed'
      using errcode = '55000';
  end if;

  receipt_value := jsonb_build_object(
    'operation',
    'confirm_draft',
    'operation_key',
    operation_key_value,
    'payload_hash',
    payload_hash_value,
    'voucher_id',
    p_voucher_id,
    'confirmed',
    true,
    'status',
    confirmed_status_value,
    'expected_reconciliation_version',
    p_expected_reconciliation_version,
    'reconciliation_version',
    reconciliation_version_value
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
    p_voucher_id,
    p_expected_reconciliation_version,
    receipt_value,
    auth.uid()
  );

  return receipt_value;
end;
$$;

create or replace function public.register_employee_advance_v2(
  p_operation_key text,
  p_employee_id uuid,
  p_amount numeric,
  p_payment_method_id uuid,
  p_payment_account_id uuid,
  p_paid_at timestamp with time zone,
  p_reference text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  payload_hash_value text;
  existing_operation public.payroll_money_operations%rowtype;
  employee_advance_id_value uuid;
  method_account_id_value uuid;
  tenant_timezone text;
  prior_timezone text := current_setting('TimeZone');
  receipt_value jsonb;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or p_employee_id is null
     or p_amount is null
     or p_amount::text in ('NaN', 'Infinity', '-Infinity')
     or p_amount <= 0
     or p_amount > 999999999999.99
     or round(p_amount, 2) <> p_amount
     or p_payment_method_id is null
     or p_payment_account_id is null
     or p_paid_at is null
     or p_paid_at > statement_timestamp() + interval '5 minutes'
     or p_paid_at < timestamp with time zone '1900-01-01 00:00:00+00'
     or char_length(coalesce(p_reference, '')) > 500
     or char_length(coalesce(p_notes, '')) > 2000 then
    raise exception 'payroll_advance_invalid_payload'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'operation_type',
          'employee_advance',
          'employee_id',
          p_employee_id,
          'amount',
          p_amount,
          'payment_method_id',
          p_payment_method_id,
          'payment_account_id',
          p_payment_account_id,
          'paid_at_epoch_microseconds',
          round(extract(epoch from p_paid_at) * 1000000)::bigint,
          'reference',
          p_reference,
          'notes',
          p_notes
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select money_operation.*
  into existing_operation
  from public.payroll_money_operations money_operation
  where money_operation.tenant_id = tenant_id_value
    and money_operation.operation_key = operation_key_value
  for update;

  if found then
    if existing_operation.operation_type = 'employee_advance'
       and existing_operation.payload_hash = payload_hash_value then
      return existing_operation.receipt;
    end if;
    raise exception 'payroll_money_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different money payload';
  end if;

  perform employee.id
  from public.employees employee
  where employee.id = p_employee_id
    and employee.tenant_id = tenant_id_value
    and employee.status = 'active'
  for update;

  if not found then
    raise exception 'Payroll employee not found'
      using errcode = '42501';
  end if;

  select payment_method.account_id
  into method_account_id_value
  from public.payment_methods payment_method
  where payment_method.id = p_payment_method_id
    and payment_method.tenant_id = tenant_id_value
    and payment_method.is_active is true
  for update;

  if not found then
    raise exception 'Payroll payment method not found'
      using errcode = '42501';
  end if;

  perform payment_account.id
  from public.accounts payment_account
  where payment_account.id = p_payment_account_id
    and payment_account.tenant_id = tenant_id_value
    and payment_account.is_active is true
    and payment_account.type = 'asset'
  for update;

  if not found
     or (
       method_account_id_value is not null
       and method_account_id_value <> p_payment_account_id
     ) then
    raise exception 'Payroll payment account not found'
      using errcode = '42501';
  end if;

  select coalesce(nullif(trim(tenant.timezone), ''), 'America/Santiago')
  into tenant_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value;

  perform set_config('TimeZone', tenant_timezone, true);

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'advance_registration',
    operation_key_value,
    auth.uid()
  );

  employee_advance_id_value :=
    public.register_employee_advance_internal(
      p_employee_id,
      p_amount,
      p_payment_method_id,
      p_payment_account_id,
      p_paid_at,
      p_reference,
      p_notes
    );

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'advance_registration';

  select jsonb_build_object(
    'operation_key',
    operation_key_value,
    'payload_hash',
    payload_hash_value,
    'advance_id',
    advance.id,
    'employee_id',
    advance.employee_id,
    'amount',
    advance.amount,
    'payment_method_id',
    advance.payment_method_id,
    'payment_account_id',
    advance.payment_account_id,
    'paid_at',
    advance.paid_at,
    'status',
    advance.status,
    'reference',
    advance.reference
  )
  into receipt_value
  from public.employee_advances advance
  where advance.id = employee_advance_id_value
    and advance.tenant_id = tenant_id_value;

  insert into public.payroll_money_operations (
    tenant_id,
    operation_type,
    operation_key,
    payload_hash,
    employee_advance_id,
    receipt,
    created_by
  )
  values (
    tenant_id_value,
    'employee_advance',
    operation_key_value,
    payload_hash_value,
    employee_advance_id_value,
    receipt_value,
    auth.uid()
  );

  perform set_config('TimeZone', prior_timezone, true);
  return receipt_value;
end;
$$;

create or replace function public.pay_payroll_voucher_v2(
  p_voucher_id uuid,
  p_operation_key text,
  p_expected_reconciliation_version bigint,
  p_payment_splits jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  payload_hash_value text;
  existing_operation public.payroll_money_operations%rowtype;
  operation_id_value uuid := gen_random_uuid();
  voucher_row public.payroll_vouchers%rowtype;
  tenant_timezone text;
  prior_timezone text := current_setting('TimeZone');
  context_import_id_value uuid;
  receipt_value jsonb;
  payment_count_value integer;
  payment_total_value numeric(14,2);
  allocation_count_value integer;
  allocation_total_value numeric(14,2);
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_voucher_id is null
     or operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or p_expected_reconciliation_version is null
     or p_expected_reconciliation_version < 0
     or p_payment_splits is null
     or jsonb_typeof(p_payment_splits) <> 'object'
     or p_payment_splits = '{}'::jsonb then
    raise exception 'payroll_payment_invalid_payload'
      using errcode = '22023';
  end if;

  if pg_column_size(p_payment_splits) > 1048576
     or exists (
       select 1
       from jsonb_each(p_payment_splits) line_split
       where jsonb_typeof(line_split.value) = 'array'
         and jsonb_array_length(line_split.value) > 50
     )
     or (
       select coalesce(
         sum(
           case
             when jsonb_typeof(line_split.value) = 'array'
               then jsonb_array_length(line_split.value)
             else 1
           end
         ),
         0
       )
       from jsonb_each(p_payment_splits) line_split
     ) > 500 then
    raise exception 'payroll_payment_payload_limit'
      using
        errcode = '22023',
        detail = 'At most 1 MiB, 50 splits per line, and 500 total splits';
  end if;

  if exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    where case
      when jsonb_typeof(line_split.value) <> 'array' then true
      else jsonb_array_length(line_split.value) = 0
    end
  ) then
    raise exception 'payroll_payment_invalid_splits'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    where jsonb_typeof(split.value) <> 'object'
  ) then
    raise exception 'payroll_payment_invalid_splits'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    where (
      coalesce(
        lower(nullif(trim(split.value->>'kind'), '')),
        'payment'
      ) = 'payment'
      and (
        coalesce(trim(split.value->>'payment_method_id'), '') !~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        or coalesce(trim(split.value->>'payment_account_id'), '') !~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      )
    )
    or (
      lower(nullif(trim(split.value->>'kind'), '')) = 'advance'
      and coalesce(trim(split.value->>'advance_id'), '') !~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
    )
  ) then
    raise exception 'payroll_payment_invalid_splits'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'operation_type',
          'manual_payroll_payment',
          'voucher_id',
          p_voucher_id,
          'expected_reconciliation_version',
          p_expected_reconciliation_version,
          'payment_splits',
          p_payment_splits
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select money_operation.*
  into existing_operation
  from public.payroll_money_operations money_operation
  where money_operation.tenant_id = tenant_id_value
    and money_operation.operation_key = operation_key_value
  for update;

  if found then
    if existing_operation.operation_type = 'manual_payroll_payment'
       and existing_operation.payload_hash = payload_hash_value then
      return existing_operation.receipt;
    end if;
    raise exception 'payroll_money_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different money payload';
  end if;

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  if not found then
    raise exception 'Payroll voucher not found'
      using errcode = '42501';
  end if;

  select coalesce(nullif(trim(tenant.timezone), ''), 'America/Santiago')
  into tenant_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value;

  if voucher_row.status not in ('confirmed', 'partial')
     or voucher_row.reconciliation_version
          <> p_expected_reconciliation_version then
    raise exception 'payroll_payment_version_conflict'
      using
        errcode = '40001',
        detail = 'reload payroll balances before paying';
  end if;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
  order by voucher_line.id
  for update;

  -- Keep method/account activity and pairing stable through the legacy insert.
  perform payment_method.id
  from public.payment_methods payment_method
  where payment_method.tenant_id = tenant_id_value
    and payment_method.id in (
      select distinct trim(split.value->>'payment_method_id')::uuid
      from jsonb_each(p_payment_splits) line_split
      cross join lateral jsonb_array_elements(line_split.value)
        split(value)
      where coalesce(
        lower(nullif(trim(split.value->>'kind'), '')),
        'payment'
      ) = 'payment'
    )
  order by payment_method.id
  for update;

  perform payment_account.id
  from public.accounts payment_account
  where payment_account.tenant_id = tenant_id_value
    and payment_account.id in (
      select distinct trim(split.value->>'payment_account_id')::uuid
      from jsonb_each(p_payment_splits) line_split
      cross join lateral jsonb_array_elements(line_split.value)
        split(value)
      where coalesce(
        lower(nullif(trim(split.value->>'kind'), '')),
        'payment'
      ) = 'payment'
    )
  order by payment_account.id
  for update;

  if exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    where line_split.key !~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
       or jsonb_typeof(line_split.value) <> 'array'
       or jsonb_array_length(line_split.value) = 0
       or not exists (
         select 1
         from public.payroll_voucher_lines voucher_line
         where voucher_line.id = line_split.key::uuid
           and voucher_line.voucher_id = p_voucher_id
           and voucher_line.tenant_id = tenant_id_value
           and voucher_line.is_included is true
           and voucher_line.total_amount > 0
       )
  ) or exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    where jsonb_typeof(split.value) <> 'object'
       or exists (
         select 1
         from jsonb_object_keys(split.value) split_key
         where split_key not in (
           'kind',
           'amount',
           'payment_method_id',
           'payment_account_id',
           'payment_date',
           'reference',
           'notes',
           'advance_id'
         )
       )
       or coalesce(
         nullif(split.value->>'amount', '')::numeric,
         0
       )::text in ('NaN', 'Infinity', '-Infinity')
       or coalesce(nullif(split.value->>'amount', '')::numeric, 0) <= 0
       or nullif(split.value->>'amount', '')::numeric > 999999999999.99
       or round(
         nullif(split.value->>'amount', '')::numeric,
         2
       ) <> nullif(split.value->>'amount', '')::numeric
       or coalesce(
         lower(nullif(trim(split.value->>'kind'), '')),
         'payment'
       ) not in ('payment', 'advance')
       or (
         coalesce(
           lower(nullif(trim(split.value->>'kind'), '')),
           'payment'
         ) = 'payment'
         and (
           nullif(split.value->>'payment_method_id', '')::uuid is null
           or nullif(split.value->>'payment_account_id', '')::uuid is null
           or nullif(split.value->>'payment_date', '')::timestamptz is null
           or trim(split.value->>'payment_date')
                !~* '(Z|[+-][0-9]{2}(:[0-9]{2})?)$'
           or nullif(split.value->>'advance_id', '') is not null
         )
       )
       or (
         coalesce(
           lower(nullif(trim(split.value->>'kind'), '')),
           'payment'
         ) = 'advance'
         and (
           nullif(split.value->>'advance_id', '')::uuid is null
           or nullif(split.value->>'payment_method_id', '') is not null
           or nullif(split.value->>'payment_account_id', '') is not null
           or nullif(split.value->>'payment_date', '') is not null
           or nullif(split.value->>'reference', '') is not null
         )
       )
       or char_length(coalesce(split.value->>'reference', '')) > 500
       or char_length(coalesce(split.value->>'notes', '')) > 2000
  ) or exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    where coalesce(
      lower(nullif(trim(split.value->>'kind'), '')),
      'payment'
    ) = 'payment'
      and not exists (
        select 1
        from public.payment_methods payment_method
        join public.accounts payment_account
          on payment_account.id =
              nullif(split.value->>'payment_account_id', '')::uuid
         and payment_account.tenant_id = payment_method.tenant_id
         and payment_account.is_active is true
         and payment_account.type = 'asset'
        where payment_method.id =
            nullif(split.value->>'payment_method_id', '')::uuid
          and payment_method.tenant_id = tenant_id_value
          and payment_method.is_active is true
          and (
            payment_method.account_id is null
            or payment_method.account_id = payment_account.id
          )
      )
  ) or exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    where coalesce(
      lower(nullif(trim(split.value->>'kind'), '')),
      'payment'
    ) = 'advance'
      and not exists (
        select 1
        from public.payroll_voucher_lines voucher_line
        join public.employee_advances advance
          on advance.id = nullif(split.value->>'advance_id', '')::uuid
         and advance.tenant_id = voucher_line.tenant_id
         and advance.employee_id = voucher_line.employee_id
         and advance.status in ('open', 'partially_applied')
         and (
           advance.paid_at at time zone tenant_timezone
         )::date <= voucher_row.period_end
        where voucher_line.id = line_split.key::uuid
          and voucher_line.voucher_id = p_voucher_id
          and voucher_line.tenant_id = tenant_id_value
      )
  ) then
    raise exception 'payroll_payment_invalid_splits'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    join public.payroll_voucher_lines voucher_line
      on voucher_line.id = line_split.key::uuid
     and voucher_line.voucher_id = p_voucher_id
     and voucher_line.tenant_id = tenant_id_value
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    group by
      voucher_line.id,
      voucher_line.total_amount,
      voucher_line.expense_id
    having sum((split.value->>'amount')::numeric)
      > greatest(
          voucher_line.total_amount
          - coalesce(
              (
                select sum(payment.amount)
                from public.expense_payments payment
                where payment.expense_id = voucher_line.expense_id
              ),
              0
            )
          - coalesce(
              (
                select sum(allocation.amount)
                from public.employee_advance_allocations allocation
                where allocation.voucher_line_id = voucher_line.id
              ),
              0
            ),
          0
        ) + 0.01
  ) then
    raise exception 'payroll_expense_payment_exceeds_line_balance'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from jsonb_each(p_payment_splits) line_split
    cross join lateral jsonb_array_elements(line_split.value)
      split(value)
    join public.employee_advances advance
      on advance.id = (split.value->>'advance_id')::uuid
     and advance.tenant_id = tenant_id_value
    where lower(trim(split.value->>'kind')) = 'advance'
    group by advance.id, advance.amount, advance.amount_applied
    having sum((split.value->>'amount')::numeric)
      > advance.amount - advance.amount_applied + 0.01
  ) then
    raise exception 'payroll_advance_allocation_exceeds_balance'
      using errcode = '23514';
  end if;

  perform set_config('TimeZone', tenant_timezone, true);

  create temporary table if not exists
    pg_temp.payroll_money_before_expense_payments (
      id uuid primary key
    )
    on commit drop;
  create temporary table if not exists
    pg_temp.payroll_money_before_advance_allocations (
      id uuid primary key
    )
    on commit drop;
  truncate table pg_temp.payroll_money_before_expense_payments;
  truncate table pg_temp.payroll_money_before_advance_allocations;

  insert into pg_temp.payroll_money_before_expense_payments (id)
  select payment.id
  from public.payroll_voucher_lines voucher_line
  join public.expense_payments payment
    on payment.expense_id = voucher_line.expense_id
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value;

  insert into pg_temp.payroll_money_before_advance_allocations (id)
  select allocation.id
  from public.payroll_voucher_lines voucher_line
  join public.employee_advance_allocations allocation
    on allocation.voucher_line_id = voucher_line.id
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value;

  select min(decision.import_id::text)::uuid
  into context_import_id_value
  from public.payroll_statement_decisions decision
  where decision.tenant_id = tenant_id_value
    and decision.voucher_id = p_voucher_id;

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'manual_payment',
    operation_key_value,
    auth.uid()
  );

  if context_import_id_value is not null then
    insert into public.payroll_statement_command_contexts (
      transaction_id,
      tenant_id,
      import_id,
      command,
      actor_id
    )
    values (
      txid_current(),
      tenant_id_value,
      context_import_id_value,
      'manual_settlement',
      auth.uid()
    );
  end if;

  perform public.pay_payroll_voucher_internal(
    p_voucher_id,
    p_payment_splits
  );

  if context_import_id_value is not null then
    delete from public.payroll_statement_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.import_id = context_import_id_value
      and command_context.command = 'manual_settlement';
  end if;

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'manual_payment';

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value;

  select
    count(*)::integer,
    coalesce(sum(payment.amount), 0)::numeric(14,2)
  into payment_count_value, payment_total_value
  from public.payroll_voucher_lines voucher_line
  join public.expense_payments payment
    on payment.expense_id = voucher_line.expense_id
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
    and not exists (
      select 1
      from pg_temp.payroll_money_before_expense_payments prior_payment
      where prior_payment.id = payment.id
    );

  select
    count(*)::integer,
    coalesce(sum(allocation.amount), 0)::numeric(14,2)
  into allocation_count_value, allocation_total_value
  from public.payroll_voucher_lines voucher_line
  join public.employee_advance_allocations allocation
    on allocation.voucher_line_id = voucher_line.id
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
    and not exists (
      select 1
      from pg_temp.payroll_money_before_advance_allocations prior_allocation
      where prior_allocation.id = allocation.id
    );

  if payment_count_value + allocation_count_value = 0 then
    raise exception 'payroll_payment_created_no_movement'
      using errcode = '22023';
  end if;

  receipt_value := jsonb_build_object(
    'operation_key',
    operation_key_value,
    'payload_hash',
    payload_hash_value,
    'voucher_id',
    p_voucher_id,
    'status',
    voucher_row.status,
    'reconciliation_version',
    voucher_row.reconciliation_version,
    'payment_count',
    payment_count_value,
    'payment_total',
    payment_total_value,
    'advance_allocation_count',
    allocation_count_value,
    'advance_allocation_total',
    allocation_total_value,
    'expense_payments',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'payment_id',
            payment.id,
            'voucher_line_id',
            voucher_line.id,
            'amount',
            payment.amount,
            'payment_method_id',
            payment.payment_method_id,
            'payment_account_id',
            payment.payment_account_id,
            'payment_date',
            payment.payment_date,
            'reference',
            payment.reference
          )
          order by payment.id
        )
        from public.payroll_voucher_lines voucher_line
        join public.expense_payments payment
          on payment.expense_id = voucher_line.expense_id
        where voucher_line.voucher_id = p_voucher_id
          and voucher_line.tenant_id = tenant_id_value
          and not exists (
            select 1
            from pg_temp.payroll_money_before_expense_payments prior_payment
            where prior_payment.id = payment.id
          )
      ),
      '[]'::jsonb
    ),
    'advance_allocations',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'allocation_id',
            allocation.id,
            'voucher_line_id',
            allocation.voucher_line_id,
            'advance_id',
            allocation.advance_id,
            'amount',
            allocation.amount,
            'applied_at',
            allocation.applied_at
          )
          order by allocation.id
        )
        from public.payroll_voucher_lines voucher_line
        join public.employee_advance_allocations allocation
          on allocation.voucher_line_id = voucher_line.id
        where voucher_line.voucher_id = p_voucher_id
          and voucher_line.tenant_id = tenant_id_value
          and not exists (
            select 1
            from pg_temp.payroll_money_before_advance_allocations
              prior_allocation
            where prior_allocation.id = allocation.id
          )
      ),
      '[]'::jsonb
    )
  );

  insert into public.payroll_money_operations (
    id,
    tenant_id,
    operation_type,
    operation_key,
    payload_hash,
    voucher_id,
    receipt,
    created_by
  )
  values (
    operation_id_value,
    tenant_id_value,
    'manual_payroll_payment',
    operation_key_value,
    payload_hash_value,
    p_voucher_id,
    receipt_value,
    auth.uid()
  );

  insert into public.payroll_money_operation_movements (
    tenant_id,
    operation_id,
    movement_type,
    expense_payment_id
  )
  select
    tenant_id_value,
    operation_id_value,
    'expense_payment',
    payment.id
  from public.payroll_voucher_lines voucher_line
  join public.expense_payments payment
    on payment.expense_id = voucher_line.expense_id
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
    and not exists (
      select 1
      from pg_temp.payroll_money_before_expense_payments prior_payment
      where prior_payment.id = payment.id
    );

  insert into public.payroll_money_operation_movements (
    tenant_id,
    operation_id,
    movement_type,
    advance_allocation_id
  )
  select
    tenant_id_value,
    operation_id_value,
    'advance_allocation',
    allocation.id
  from public.payroll_voucher_lines voucher_line
  join public.employee_advance_allocations allocation
    on allocation.voucher_line_id = voucher_line.id
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
    and not exists (
      select 1
      from pg_temp.payroll_money_before_advance_allocations prior_allocation
      where prior_allocation.id = allocation.id
    );

  perform set_config('TimeZone', prior_timezone, true);
  return receipt_value;
end;
$$;

-- A reviewed statement can prove that earned wages were actually paid before
-- the nominal weekly period_end (for example, a short week ending Wednesday).
-- Keep the mature manual-settlement rule intact and permit the earlier date
-- only while the private apply capability is active and the exact immutable
-- decision backs every movement attribute.
create or replace function public.pay_payroll_voucher_internal(
  p_voucher_id uuid,
  p_payment_splits jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_voucher record;
  v_line record;
  v_splits jsonb;
  v_split jsonb;
  v_kind text;
  v_amount numeric(14,2);
  v_remaining numeric(14,2);
  v_batch_total numeric(14,2);
  v_method_id uuid;
  v_account_id uuid;
  v_advance record;
  v_payment_date timestamp with time zone;
  v_reference text;
  v_notes text;
  v_statement_payment_backed boolean;
  v_statement_future_exception_backed boolean;
begin
  select *
  into v_voucher
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = public.user_tenant_id()
  for update;

  if not found then
    raise exception 'Nómina no encontrada';
  end if;
  if v_voucher.status not in ('confirmed', 'partial') then
    raise exception
      'La nómina debe estar confirmada o parcialmente pagada';
  end if;

  for v_line in
    select voucher_line.*
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = p_voucher_id
      and voucher_line.is_included is true
      and voucher_line.total_amount > 0
  loop
    perform public.ensure_payroll_line_expense(v_line.id);

    select voucher_line.*
    into v_line
    from public.payroll_voucher_lines voucher_line
    where voucher_line.id = v_line.id;

    select greatest(
      v_line.total_amount
      - coalesce(
          (
            select sum(payment.amount)
            from public.expense_payments payment
            where payment.expense_id = v_line.expense_id
          ),
          0
        )
      - coalesce(
          (
            select sum(allocation.amount)
            from public.employee_advance_allocations allocation
            where allocation.voucher_line_id = v_line.id
          ),
          0
        ),
      0
    )
    into v_remaining;

    if p_payment_splits is null then
      v_splits := jsonb_build_array(
        jsonb_build_object(
          'kind',
          'payment',
          'payment_method_id',
          v_line.payment_method_id,
          'payment_account_id',
          v_line.payment_account_id,
          'amount',
          v_remaining,
          'payment_date',
          now()
        )
      );
    else
      v_splits := p_payment_splits -> v_line.id::text;
    end if;

    if v_splits is null then
      continue;
    end if;
    if jsonb_typeof(v_splits) <> 'array' then
      raise exception 'Movimientos inválidos para %', v_line.employee_name;
    end if;

    v_batch_total := 0;
    for v_split in
      select split.value
      from jsonb_array_elements(v_splits) split(value)
    loop
      v_amount := coalesce(nullif(v_split->>'amount', '')::numeric, 0);
      if v_amount <= 0 then
        continue;
      end if;

      v_batch_total := v_batch_total + v_amount;
      if v_batch_total > v_remaining + 0.01 then
        raise exception
          'Los movimientos exceden el saldo de %',
          v_line.employee_name;
      end if;

      v_kind := coalesce(nullif(v_split->>'kind', ''), 'payment');
      v_reference := nullif(v_split->>'reference', '');
      v_notes := nullif(v_split->>'notes', '');

      if v_kind = 'advance' then
        select advance.*
        into v_advance
        from public.employee_advances advance
        where advance.id = nullif(v_split->>'advance_id', '')::uuid
          and advance.tenant_id = v_line.tenant_id
          and advance.employee_id = v_line.employee_id
          and advance.status in ('open', 'partially_applied')
        for update;

        if not found then
          raise exception
            'Anticipo no válido para %',
            v_line.employee_name;
        end if;
        if v_amount > v_advance.amount - v_advance.amount_applied + 0.01 then
          raise exception
            'La imputación excede el saldo disponible del anticipo';
        end if;

        insert into public.employee_advance_allocations (
          tenant_id,
          advance_id,
          voucher_line_id,
          amount,
          applied_at,
          notes,
          created_by
        )
        values (
          v_line.tenant_id,
          v_advance.id,
          v_line.id,
          v_amount,
          v_voucher.period_end::timestamp with time zone,
          v_notes,
          auth.uid()
        );
      elsif v_kind = 'payment' then
        v_method_id := coalesce(
          nullif(v_split->>'payment_method_id', '')::uuid,
          v_line.payment_method_id
        );
        v_account_id := coalesce(
          nullif(v_split->>'payment_account_id', '')::uuid,
          v_line.payment_account_id
        );
        if v_method_id is null then
          raise exception
            'Falta método de pago para %',
            v_line.employee_name;
        end if;

        v_payment_date := coalesce(
          nullif(v_split->>'payment_date', '')::timestamp with time zone,
          now()
        );

        select
          exists (
            select 1
            from public.payroll_statement_command_contexts command_context
            join public.payroll_statement_decisions decision
              on decision.import_id = command_context.import_id
             and decision.tenant_id = command_context.tenant_id
            where command_context.transaction_id = txid_current()
              and command_context.command = 'apply'
              and command_context.tenant_id = v_line.tenant_id
              and decision.voucher_id = v_voucher.id
              and decision.voucher_line_id = v_line.id
              and decision.action in ('bank_payment', 'cash_payment')
              and decision.applied_amount = v_amount
              and decision.payment_method_id = v_method_id
              and decision.payment_account_id = v_account_id
              and decision.payment_date = v_payment_date::date
              and decision.movement_reference = v_reference
          ),
          exists (
            select 1
            from public.payroll_statement_command_contexts command_context
            join public.payroll_statement_imports statement_import
              on statement_import.id = command_context.import_id
             and statement_import.tenant_id = command_context.tenant_id
            join public.payroll_statement_decisions decision
              on decision.import_id = command_context.import_id
             and decision.tenant_id = command_context.tenant_id
            join public.payroll_statement_rows statement_row
              on statement_row.id = decision.row_id
             and statement_row.import_id = decision.import_id
             and statement_row.tenant_id = decision.tenant_id
            where command_context.transaction_id = txid_current()
              and command_context.command = 'apply'
              and command_context.tenant_id = v_line.tenant_id
              and decision.voucher_id = v_voucher.id
              and decision.voucher_line_id = v_line.id
              and decision.action = 'bank_payment'
              and decision.applied_amount = v_amount
              and decision.payment_method_id = v_method_id
              and decision.payment_account_id = v_account_id
              and decision.payment_date = v_payment_date::date
              and decision.movement_reference = v_reference
              and statement_row.warnings ? 'out_of_statement_range'
              and v_payment_date::date =
                (statement_import.source_metadata->>'statement_end')::date + 1
              and v_payment_date::date <= current_date + 1
              and v_payment_date::date <=
                (statement_import.created_at at time zone current_setting(
                  'TimeZone'
                ))::date + 1
          )
        into
          v_statement_payment_backed,
          v_statement_future_exception_backed;

        if v_payment_date > now() + interval '5 minutes'
           and not v_statement_future_exception_backed then
          raise exception 'La fecha de pago no puede estar en el futuro';
        end if;
        if v_payment_date < v_voucher.period_end::timestamp with time zone
           and not (
             v_payment_date
               >= v_voucher.period_start::timestamp with time zone
             and v_statement_payment_backed
           ) then
          raise exception
            'Un movimiento anterior al cierre del período debe registrarse como anticipo';
        end if;

        insert into public.expense_payments (
          tenant_id,
          expense_id,
          payment_method_id,
          payment_account_id,
          amount,
          payment_date,
          reference,
          notes
        )
        values (
          v_line.tenant_id,
          v_line.expense_id,
          v_method_id,
          v_account_id,
          v_amount,
          v_payment_date,
          coalesce(
            v_reference,
            format('Nómina %s', v_voucher.voucher_number)
          ),
          coalesce(
            v_notes,
            format('Pago de salario: %s', v_line.employee_name)
          )
        );
      else
        raise exception
          'Tipo de movimiento de nómina no válido: %',
          v_kind;
      end if;
    end loop;

    perform public.recalculate_expense_totals(v_line.expense_id);
  end loop;

  perform public.refresh_payroll_voucher_status(p_voucher_id);
  return true;
end;
$$;

drop function if exists public.apply_payroll_statement_reconciliation(
  uuid,
  text,
  jsonb,
  jsonb
);

create or replace function public.apply_payroll_statement_reconciliation(
  p_import_id uuid,
  p_operation_key text,
  p_decisions jsonb,
  p_expected_voucher_versions jsonb,
  p_authorized_draft_voucher_ids jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  expected_versions_value jsonb :=
    coalesce(p_expected_voucher_versions, '{}'::jsonb);
  authorized_draft_voucher_ids_value jsonb :=
    coalesce(p_authorized_draft_voucher_ids, '[]'::jsonb);
  canonical_authorized_draft_voucher_ids_value jsonb := '[]'::jsonb;
  payload_hash_value text;
  import_row public.payroll_statement_imports%rowtype;
  prior_import public.payroll_statement_imports%rowtype;
  decision_value jsonb;
  decision_ordinal_value integer;
  action_value text;
  row_id_value uuid;
  row_fingerprint_value text;
  prior_decision_id_value uuid;
  voucher_line_id_value uuid;
  advance_id_value uuid;
  payment_method_id_value uuid;
  payment_account_id_value uuid;
  applied_amount_value numeric(14,2);
  payment_date_value date;
  variance_disposition_value text;
  manual_confirmation_value boolean;
  duplicate_override_value boolean;
  reason_value text;
  decision_row record;
  voucher_row record;
  line_row record;
  advance_row record;
  method_row record;
  account_row record;
  employee_row record;
  row_record record;
  tenant_timezone text;
  prior_timezone text := current_setting('TimeZone');
  payment_at_value timestamp with time zone;
  current_settled_value numeric(14,2);
  live_line_balance_value numeric(14,2);
  expected_bank_applied_value numeric(14,2);
  bank_variance_value numeric(14,2);
  match_tolerance_value numeric(14,2);
  requested_line_total_value numeric(14,2);
  requested_advance_total_value numeric(14,2);
  touched_voucher_count integer;
  touched_draft_voucher_count integer;
  expected_voucher_count integer;
  authorized_draft_voucher_count integer;
  split_map_value jsonb;
  line_splits_value jsonb;
  receipt_value jsonb;
  final_status_value text;
  unresolved_variance_count_value integer;
  unresolved_variance_total_value numeric(14,2);
  already_resolved_count_value integer;
  violated_constraint_name text;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll statement access denied'
      using errcode = '42501';
  end if;

  if p_import_id is null then
    raise exception 'payroll_statement_import_required'
      using errcode = '22023';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$' then
    raise exception 'payroll_statement_invalid_operation_key'
      using errcode = '22023';
  end if;

  if p_decisions is null
     or jsonb_typeof(p_decisions) <> 'array'
     or jsonb_array_length(p_decisions) not between 1 and 4000 then
    raise exception 'payroll_statement_invalid_decisions'
      using errcode = '22023';
  end if;

  if jsonb_typeof(expected_versions_value) <> 'object' then
    raise exception 'payroll_statement_invalid_expected_versions'
      using errcode = '22023';
  end if;

  if jsonb_typeof(authorized_draft_voucher_ids_value) <> 'array'
     or jsonb_array_length(authorized_draft_voucher_ids_value) > 1000
     or exists (
       select 1
       from jsonb_array_elements(
         authorized_draft_voucher_ids_value
       ) authorized(element)
       where jsonb_typeof(authorized.element) <> 'string'
          or trim(authorized.element #>> '{}') !~
            '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
     ) then
    raise exception 'payroll_statement_invalid_draft_commitment_authorization'
      using errcode = '22023';
  end if;

  select coalesce(
    jsonb_agg(
      authorized.voucher_id::text
      order by authorized.voucher_id::text
    ),
    '[]'::jsonb
  )
  into canonical_authorized_draft_voucher_ids_value
  from (
    select distinct value::uuid as voucher_id
    from jsonb_array_elements_text(
      authorized_draft_voucher_ids_value
    ) element(value)
  ) authorized;

  if jsonb_array_length(authorized_draft_voucher_ids_value)
       <> jsonb_array_length(
         canonical_authorized_draft_voucher_ids_value
       ) then
    raise exception 'payroll_statement_duplicate_draft_commitment_authorization'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'import_id',
          p_import_id,
          'decisions',
          p_decisions,
          'expected_voucher_versions',
          expected_versions_value,
          'authorized_draft_voucher_ids',
          canonical_authorized_draft_voucher_ids_value
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select statement_import.*
  into import_row
  from public.payroll_statement_imports statement_import
  where statement_import.id = p_import_id
  for update;

  if not found
     or import_row.tenant_id <> tenant_id_value then
    raise exception 'Payroll statement import not found'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text
      || ':payroll-statement-apply:'
      || operation_key_value,
      0
    )
  );

  select statement_import.*
  into prior_import
  from public.payroll_statement_imports statement_import
  where statement_import.tenant_id = tenant_id_value
    and statement_import.apply_operation_key = operation_key_value
    and statement_import.id <> p_import_id
  for update;

  if found then
    raise exception 'payroll_statement_apply_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key belongs to another import';
  end if;

  if import_row.apply_operation_key is not null then
    if import_row.apply_operation_key = operation_key_value then
      if import_row.apply_payload_hash = payload_hash_value then
        return import_row.apply_receipt;
      end if;
      raise exception 'payroll_statement_apply_idempotency_conflict'
        using
          errcode = 'P0001',
          detail = 'operation_key already has a different payload';
    end if;
    raise exception 'payroll_statement_import_already_applied'
      using
        errcode = 'P0001',
        detail = 'an import has one final reviewed apply operation';
  end if;

  if import_row.status <> 'review' then
    raise exception 'payroll_statement_import_not_in_review'
      using errcode = '55000';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  -- A parser pass remains review-only and may correct a misread account hash
  -- or reviewed ERP account. The stable one-to-one mapping becomes
  -- authoritative only in the same transaction as a successful apply.
  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text
      || ':payroll-statement-account:'
      || import_row.erp_account_id::text,
      0
    )
  );
  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text
      || ':payroll-statement-account-fingerprint:'
      || import_row.account_fingerprint,
      0
    )
  );

  insert into public.payroll_statement_account_mappings (
    tenant_id,
    erp_account_id,
    account_fingerprint,
    created_by
  )
  values (
    tenant_id_value,
    import_row.erp_account_id,
    import_row.account_fingerprint,
    auth.uid()
  )
  on conflict do nothing;

  if not exists (
    select 1
    from public.payroll_statement_account_mappings account_mapping
    where account_mapping.tenant_id = tenant_id_value
      and account_mapping.erp_account_id = import_row.erp_account_id
      and account_mapping.account_fingerprint =
        import_row.account_fingerprint
  ) then
    raise exception 'payroll_statement_account_fingerprint_mismatch'
      using
        errcode = '23514',
        detail =
          'A successful prior reconciliation confirmed another account hash';
  end if;

  insert into public.payroll_statement_command_contexts (
    transaction_id,
    tenant_id,
    import_id,
    command,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    p_import_id,
    'apply',
    auth.uid()
  );

  for decision_value in
    select decision_element.value
    from jsonb_array_elements(p_decisions)
      with ordinality decision_element(value, n)
    order by decision_element.n
  loop
    if jsonb_typeof(decision_value) <> 'object' then
      raise exception 'payroll_statement_decision_must_be_object'
        using errcode = '22023';
    end if;

    decision_ordinal_value :=
      nullif(decision_value->>'ordinal', '')::integer;
    action_value :=
      lower(trim(coalesce(decision_value->>'action', '')));
    row_id_value := nullif(decision_value->>'row_id', '')::uuid;
    row_fingerprint_value := lower(
      nullif(
        trim(
          coalesce(
            decision_value->>'row_fingerprint',
            decision_value->>'source_fingerprint'
          )
        ),
        ''
      )
    );
    if row_id_value is null and row_fingerprint_value is not null then
      select statement_row.id
      into row_id_value
      from public.payroll_statement_rows statement_row
      where statement_row.import_id = p_import_id
        and statement_row.tenant_id = tenant_id_value
        and statement_row.fingerprint = row_fingerprint_value;

      if not found then
        raise exception 'Payroll statement row fingerprint not found'
          using errcode = '22023';
      end if;
    end if;
    prior_decision_id_value :=
      nullif(decision_value->>'prior_decision_id', '')::uuid;
    voucher_line_id_value :=
      nullif(decision_value->>'voucher_line_id', '')::uuid;
    advance_id_value :=
      nullif(decision_value->>'advance_id', '')::uuid;
    payment_method_id_value :=
      nullif(decision_value->>'payment_method_id', '')::uuid;
    payment_account_id_value :=
      nullif(decision_value->>'payment_account_id', '')::uuid;
    applied_amount_value :=
      nullif(
        coalesce(
          decision_value->>'applied_amount',
          decision_value->>'amount'
        ),
        ''
      )::numeric;
    payment_date_value :=
      nullif(decision_value->>'payment_date', '')::date;
    variance_disposition_value :=
      lower(nullif(trim(decision_value->>'variance_disposition'), ''));
    manual_confirmation_value := coalesce(
      nullif(decision_value->>'manual_confirmation', '')::boolean,
      false
    );
    duplicate_override_value := coalesce(
      nullif(decision_value->>'duplicate_override', '')::boolean,
      false
    );
    reason_value := nullif(
      trim(
        coalesce(
          decision_value->>'reason',
          decision_value->>'note'
        )
      ),
      ''
    );

    if decision_ordinal_value not between 1 and 4000
       or action_value not in (
         'bank_payment',
         'cash_payment',
         'advance_allocation',
         'not_paid',
         'ignore',
         'hold',
         'already_resolved'
       )
       or char_length(coalesce(reason_value, '')) > 1000
       or (
         applied_amount_value is not null
         and (
           applied_amount_value::text = 'NaN'
           or applied_amount_value <= 0
           or applied_amount_value > 999999999999.99
           or round(applied_amount_value, 2) <> applied_amount_value
         )
       ) then
      raise exception 'payroll_statement_invalid_decision_%',
        decision_ordinal_value
        using errcode = '22023';
    end if;

    insert into public.payroll_statement_decisions (
      tenant_id,
      import_id,
      operation_key,
      decision_ordinal,
      action,
      row_id,
      row_fingerprint,
      prior_decision_id,
      voucher_line_id,
      advance_id,
      payment_method_id,
      payment_account_id,
      applied_amount,
      payment_date,
      variance_disposition,
      manual_confirmation,
      duplicate_override,
      reason,
      decided_by
    )
    values (
      tenant_id_value,
      p_import_id,
      operation_key_value,
      decision_ordinal_value,
      action_value,
      row_id_value,
      row_fingerprint_value,
      prior_decision_id_value,
      voucher_line_id_value,
      advance_id_value,
      payment_method_id_value,
      payment_account_id_value,
      applied_amount_value,
      payment_date_value,
      variance_disposition_value,
      manual_confirmation_value,
      duplicate_override_value,
      reason_value,
      auth.uid()
    );
  end loop;

  -- Every imported row must receive one explicit reviewed disposition.
  if exists (
    select 1
    from public.payroll_statement_rows statement_row
    left join public.payroll_statement_decisions decision
      on decision.row_id = statement_row.id
     and decision.import_id = statement_row.import_id
    where statement_row.import_id = p_import_id
      and decision.id is null
  ) or exists (
    select 1
    from public.payroll_statement_decisions decision
    left join public.payroll_statement_rows statement_row
      on statement_row.id = decision.row_id
     and statement_row.import_id = decision.import_id
    where decision.import_id = p_import_id
      and decision.row_id is not null
      and statement_row.id is null
  ) then
    raise exception 'payroll_statement_every_row_requires_a_decision'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and (
        (
          decision.action in (
            'bank_payment',
            'ignore',
            'hold',
            'already_resolved'
          )
          and decision.row_id is null
        )
        or (
          decision.action in (
            'cash_payment',
            'advance_allocation',
            'not_paid'
          )
          and decision.row_id is not null
        )
        or (
          decision.action in (
            'bank_payment',
            'cash_payment',
            'advance_allocation',
            'not_paid'
          )
          and decision.voucher_line_id is null
        )
        or (
          decision.action in ('ignore', 'hold', 'already_resolved')
          and decision.voucher_line_id is not null
        )
        or (
          decision.action in ('ignore', 'hold', 'already_resolved')
          and decision.reason is null
        )
        or (
          decision.action = 'already_resolved'
          and decision.prior_decision_id is null
        )
        or (
          decision.action <> 'already_resolved'
          and decision.prior_decision_id is not null
        )
        or (
          decision.duplicate_override is true
          and decision.action <> 'bank_payment'
        )
      )
  ) then
    raise exception 'payroll_statement_decision_shape_invalid'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.payroll_statement_decisions not_paid_decision
    join public.payroll_statement_decisions settlement_decision
      on settlement_decision.import_id = not_paid_decision.import_id
     and settlement_decision.voucher_line_id =
          not_paid_decision.voucher_line_id
     and settlement_decision.action in (
       'bank_payment',
       'cash_payment',
       'advance_allocation'
     )
    where not_paid_decision.import_id = p_import_id
      and not_paid_decision.action = 'not_paid'
  ) then
    raise exception 'payroll_statement_not_paid_conflicts_with_settlement'
      using errcode = '22023';
  end if;

  -- Row locks are deterministic even for two overlapping statement imports.
  perform statement_row.id
  from public.payroll_statement_rows statement_row
  join public.payroll_statement_decisions decision
    on decision.row_id = statement_row.id
  where decision.import_id = p_import_id
  order by statement_row.id
  for update of statement_row;

  if exists (
    select 1
    from public.payroll_statement_decisions decision
    join public.payroll_statement_rows statement_row
      on statement_row.id = decision.row_id
    where decision.import_id = p_import_id
      and decision.row_fingerprint is not null
      and decision.row_fingerprint <> statement_row.fingerprint
  ) then
    raise exception 'payroll_statement_decision_fingerprint_mismatch'
      using errcode = '22023';
  end if;

  update public.payroll_statement_decisions decision
  set row_fingerprint = statement_row.fingerprint,
      bank_amount = statement_row.amount
  from public.payroll_statement_rows statement_row
  where decision.import_id = p_import_id
    and statement_row.id = decision.row_id;

  if exists (
    select 1
    from public.payroll_statement_decisions current_decision
    left join public.payroll_statement_decisions prior_decision
      on prior_decision.id = current_decision.prior_decision_id
     and prior_decision.tenant_id = current_decision.tenant_id
     and prior_decision.import_id <> current_decision.import_id
     and prior_decision.row_fingerprint =
          current_decision.row_fingerprint
     and prior_decision.action <> 'already_resolved'
     and prior_decision.outcome in ('applied', 'acknowledged', 'held')
    where current_decision.import_id = p_import_id
      and current_decision.action = 'already_resolved'
      and prior_decision.id is null
  ) then
    raise exception 'payroll_statement_prior_resolution_invalid'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.payroll_statement_decisions current_decision
    join public.payroll_statement_decisions prior_decision
      on prior_decision.tenant_id = current_decision.tenant_id
     and prior_decision.row_fingerprint =
          current_decision.row_fingerprint
     and prior_decision.import_id <> current_decision.import_id
     and prior_decision.outcome in ('applied', 'acknowledged', 'held')
    where current_decision.import_id = p_import_id
      and current_decision.row_fingerprint is not null
      and current_decision.action <> 'already_resolved'
  ) then
    raise exception 'payroll_statement_row_already_resolved'
      using errcode = 'P0001';
  end if;

  -- Occurrence disambiguates identical rows only inside one source document.
  -- If that normalized base already produced a bank allocation in an earlier
  -- import, another occurrence is never an automatic match. The reviewer must
  -- preserve a separate duplicate override flag plus the universal bank reason.
  if exists (
    select 1
    from public.payroll_statement_decisions current_decision
    join public.payroll_statement_rows current_row
      on current_row.id = current_decision.row_id
     and current_row.import_id = current_decision.import_id
    join public.payroll_statement_rows prior_row
      on prior_row.tenant_id = current_row.tenant_id
     and prior_row.base_fingerprint = current_row.base_fingerprint
     and prior_row.import_id <> current_row.import_id
    join public.payroll_statement_decisions prior_decision
      on prior_decision.row_id = prior_row.id
     and prior_decision.import_id = prior_row.import_id
     and prior_decision.tenant_id = prior_row.tenant_id
     and prior_decision.action = 'bank_payment'
     and prior_decision.outcome = 'applied'
    join public.payroll_statement_allocations prior_allocation
      on prior_allocation.decision_id = prior_decision.id
     and prior_allocation.row_id = prior_row.id
     and prior_allocation.tenant_id = prior_row.tenant_id
     and prior_allocation.action = 'bank_payment'
    where current_decision.import_id = p_import_id
      and current_decision.action = 'bank_payment'
      and current_decision.duplicate_override is not true
  ) then
    raise exception
      'payroll_statement_ambiguous_repeated_row_requires_override'
      using
        errcode = '22023',
        detail =
          'A prior bank allocation used the same normalized row base';
  end if;

  if exists (
    select 1
    from public.payroll_statement_decisions current_decision
    join public.payroll_statement_rows current_row
      on current_row.id = current_decision.row_id
     and current_row.import_id = current_decision.import_id
    where current_decision.import_id = p_import_id
      and current_decision.action = 'bank_payment'
      and current_decision.duplicate_override is true
      and not exists (
        select 1
        from public.payroll_statement_rows prior_row
        join public.payroll_statement_decisions prior_decision
          on prior_decision.row_id = prior_row.id
         and prior_decision.import_id = prior_row.import_id
         and prior_decision.tenant_id = prior_row.tenant_id
         and prior_decision.action = 'bank_payment'
         and prior_decision.outcome = 'applied'
        join public.payroll_statement_allocations prior_allocation
          on prior_allocation.decision_id = prior_decision.id
         and prior_allocation.row_id = prior_row.id
         and prior_allocation.tenant_id = prior_row.tenant_id
         and prior_allocation.action = 'bank_payment'
        where prior_row.tenant_id = current_row.tenant_id
          and prior_row.base_fingerprint = current_row.base_fingerprint
          and prior_row.import_id <> current_row.import_id
      )
  ) then
    raise exception
      'payroll_statement_duplicate_override_without_prior_allocation'
      using errcode = '22023';
  end if;

  update public.payroll_statement_decisions decision
  set voucher_id = voucher_line.voucher_id,
      employee_id = voucher_line.employee_id
  from public.payroll_voucher_lines voucher_line
  where decision.import_id = p_import_id
    and voucher_line.id = decision.voucher_line_id
    and voucher_line.tenant_id = tenant_id_value;

  if exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and decision.voucher_line_id is not null
      and (
        decision.voucher_id is null
        or decision.employee_id is null
      )
  ) then
    raise exception 'Payroll voucher line not found'
      using errcode = '42501';
  end if;

  perform voucher.id
  from public.payroll_vouchers voucher
  join (
    select distinct decision.voucher_id
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and decision.voucher_id is not null
  ) selected on selected.voucher_id = voucher.id
  where voucher.tenant_id = tenant_id_value
  order by voucher.id
  for update of voucher;

  perform advance.id
  from public.employee_advances advance
  join public.payroll_statement_decisions decision
    on decision.advance_id = advance.id
  where decision.import_id = p_import_id
    and advance.tenant_id = tenant_id_value
  order by advance.id
  for update of advance;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  join public.payroll_statement_decisions decision
    on decision.voucher_line_id = voucher_line.id
  where decision.import_id = p_import_id
    and voucher_line.tenant_id = tenant_id_value
  order by voucher_line.id
  for update of voucher_line;

  perform employee.id
  from public.employees employee
  join (
    select distinct decision.employee_id
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and decision.employee_id is not null
  ) selected on selected.employee_id = employee.id
  where employee.tenant_id = tenant_id_value
  order by employee.id
  for update of employee;

  perform payment_method.id
  from public.payment_methods payment_method
  join (
    select distinct decision.payment_method_id
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and decision.payment_method_id is not null
  ) selected on selected.payment_method_id = payment_method.id
  where payment_method.tenant_id = tenant_id_value
  order by payment_method.id
  for update of payment_method;

  perform locked_account.id
  from public.accounts locked_account
  where locked_account.tenant_id = tenant_id_value
    and (
      locked_account.id = import_row.erp_account_id
      or locked_account.id in (
        select decision.payment_account_id
        from public.payroll_statement_decisions decision
        where decision.import_id = p_import_id
          and decision.payment_account_id is not null
      )
    )
  order by locked_account.id
  for update of locked_account;

  -- A draft confirmation recognizes every included positive liability. Require
  -- an explicit settlement or not-paid decision for every such line before the
  -- aggregate can leave draft.
  if exists (
    select 1
    from public.payroll_vouchers voucher
    join public.payroll_statement_decisions selected_decision
      on selected_decision.voucher_id = voucher.id
     and selected_decision.import_id = p_import_id
    join public.payroll_voucher_lines voucher_line
      on voucher_line.voucher_id = voucher.id
     and voucher_line.tenant_id = voucher.tenant_id
    where voucher.tenant_id = tenant_id_value
      and voucher.status = 'draft'
      and voucher_line.is_included is true
      and voucher_line.total_amount > 0
      and not exists (
        select 1
        from public.payroll_statement_decisions coverage_decision
        where coverage_decision.import_id = p_import_id
          and coverage_decision.voucher_line_id = voucher_line.id
          and coverage_decision.action in (
            'bank_payment',
            'cash_payment',
            'advance_allocation',
            'not_paid'
          )
      )
  ) then
    raise exception 'payroll_statement_draft_requires_every_line_decision'
      using errcode = '22023';
  end if;

  select count(distinct decision.voucher_id)::integer
  into touched_voucher_count
  from public.payroll_statement_decisions decision
  where decision.import_id = p_import_id
    and decision.voucher_id is not null;

  select count(*)::integer
  into expected_voucher_count
  from jsonb_object_keys(expected_versions_value);

  select count(distinct decision.voucher_id)::integer
  into touched_draft_voucher_count
  from public.payroll_statement_decisions decision
  join public.payroll_vouchers voucher
    on voucher.id = decision.voucher_id
   and voucher.tenant_id = tenant_id_value
  where decision.import_id = p_import_id
    and voucher.status = 'draft';

  authorized_draft_voucher_count := jsonb_array_length(
    canonical_authorized_draft_voucher_ids_value
  );

  if authorized_draft_voucher_count <> touched_draft_voucher_count
     or exists (
       select 1
       from public.payroll_statement_decisions decision
       join public.payroll_vouchers voucher
         on voucher.id = decision.voucher_id
        and voucher.tenant_id = tenant_id_value
       where decision.import_id = p_import_id
         and voucher.status = 'draft'
         and not (
           canonical_authorized_draft_voucher_ids_value
             ? voucher.id::text
         )
     )
     or exists (
       select 1
       from jsonb_array_elements_text(
         canonical_authorized_draft_voucher_ids_value
       ) authorized(voucher_id)
       where not exists (
         select 1
         from public.payroll_statement_decisions decision
         join public.payroll_vouchers voucher
           on voucher.id = decision.voucher_id
          and voucher.tenant_id = tenant_id_value
         where decision.import_id = p_import_id
           and voucher.status = 'draft'
           and voucher.id::text = authorized.voucher_id
       )
     ) then
    raise exception 'payroll_statement_draft_commitment_authorization_mismatch'
      using
        errcode = '22023',
        detail =
          'authorized draft voucher ids must exactly match touched drafts';
  end if;

  if exists (
    select 1
    from jsonb_array_elements_text(
      canonical_authorized_draft_voucher_ids_value
    ) authorized(voucher_id)
    join public.payroll_vouchers voucher
      on voucher.id::text = authorized.voucher_id
     and voucher.tenant_id = tenant_id_value
    where not exists (
      select 1
      from public.payroll_voucher_lines voucher_line
      where voucher_line.voucher_id = voucher.id
        and voucher_line.tenant_id = voucher.tenant_id
        and voucher_line.is_included is true
        and voucher_line.total_amount > 0
    )
  ) then
    raise exception 'payroll_statement_draft_has_no_positive_obligations'
      using errcode = '22023';
  end if;

  if expected_voucher_count <> touched_voucher_count
     or exists (
       select 1
       from public.payroll_statement_decisions decision
       join public.payroll_vouchers voucher
         on voucher.id = decision.voucher_id
       where decision.import_id = p_import_id
         and decision.voucher_id is not null
         and (
           not expected_versions_value ? decision.voucher_id::text
           or (
             expected_versions_value->>decision.voucher_id::text
           )::bigint <> voucher.reconciliation_version
         )
     )
     or exists (
       select 1
       from jsonb_object_keys(expected_versions_value) expected(voucher_id)
       where not exists (
         select 1
         from public.payroll_statement_decisions decision
         where decision.import_id = p_import_id
           and decision.voucher_id::text = expected.voucher_id
       )
     ) then
    raise exception 'payroll_statement_voucher_version_conflict'
      using
        errcode = '40001',
        detail = 'reload payroll liabilities before applying';
  end if;

  select tenant.timezone
  into tenant_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if tenant_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = tenant_timezone
     ) then
    raise exception 'Payroll timezone invalid'
      using errcode = '22023';
  end if;

  for decision_row in
    select decision.*
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
    order by decision.decision_ordinal
  loop
    if decision_row.row_id is not null then
      select statement_row.*
      into row_record
      from public.payroll_statement_rows statement_row
      where statement_row.id = decision_row.row_id
        and statement_row.import_id = p_import_id
        and statement_row.tenant_id = tenant_id_value;

      if (
        row_record.transaction_date is null
        or row_record.direction is null
        or row_record.direction = 'unknown'
        or row_record.amount is null
      ) and (
        decision_row.action not in (
          'ignore',
          'hold',
          'already_resolved'
        )
        or decision_row.manual_confirmation is not true
        or decision_row.reason is null
      ) then
        raise exception
          'payroll_statement_incomplete_evidence_requires_review_%',
          decision_row.decision_ordinal
          using
            errcode = '22023',
            detail =
              'Incomplete OCR evidence can only be ignored or held '
              || 'after explicit human confirmation';
      end if;
    end if;

    if decision_row.voucher_line_id is not null then
      select
        voucher_line.*,
        voucher.status as voucher_status,
        voucher.period_start,
        voucher.period_end,
        voucher.voucher_number
      into line_row
      from public.payroll_voucher_lines voucher_line
      join public.payroll_vouchers voucher
        on voucher.id = voucher_line.voucher_id
       and voucher.tenant_id = voucher_line.tenant_id
      where voucher_line.id = decision_row.voucher_line_id
        and voucher_line.tenant_id = tenant_id_value;

      if not found
         or line_row.is_included is not true
         or line_row.total_amount <= 0 then
        raise exception 'Payroll voucher line is not payable'
          using errcode = '22023';
      end if;

      select employee.*
      into employee_row
      from public.employees employee
      where employee.id = line_row.employee_id
        and employee.tenant_id = tenant_id_value;

      if not found then
        raise exception 'Payroll employee not found'
          using errcode = '42501';
      end if;
    end if;

    if decision_row.payment_method_id is not null then
      select payment_method.*
      into method_row
      from public.payment_methods payment_method
      where payment_method.id = decision_row.payment_method_id
        and payment_method.tenant_id = tenant_id_value
        and payment_method.is_active is true;

      if not found then
        raise exception 'Payroll payment method not found'
          using errcode = '42501';
      end if;
    end if;

    if decision_row.payment_account_id is not null then
      select selected_account.*
      into account_row
      from public.accounts selected_account
      where selected_account.id = decision_row.payment_account_id
        and selected_account.tenant_id = tenant_id_value
        and selected_account.is_active is true
        and selected_account.type = 'asset';

      if not found then
        raise exception 'Payroll payment account not found'
          using errcode = '42501';
      end if;
    end if;

    if decision_row.action = 'bank_payment' then
      select
        coalesce(
          (
            select sum(payment.amount)
            from public.expense_payments payment
            where payment.expense_id = line_row.expense_id
          ),
          0
        )
        + coalesce(
          (
            select sum(allocation.amount)
            from public.employee_advance_allocations allocation
            where allocation.voucher_line_id = line_row.id
          ),
          0
        )
      into current_settled_value;

      live_line_balance_value := greatest(
        line_row.total_amount - current_settled_value,
        0
      );
      expected_bank_applied_value := least(
        row_record.amount,
        live_line_balance_value
      );
      bank_variance_value :=
        row_record.amount - live_line_balance_value;
      match_tolerance_value := greatest(
        1::numeric,
        least(
          500::numeric,
          ceil(live_line_balance_value * 0.01)
        )
      );

      if row_record.direction <> 'debit'
         or decision_row.applied_amount is null
         or live_line_balance_value <= 0
         or decision_row.applied_amount
              <> expected_bank_applied_value
         or decision_row.payment_method_id is null
         or decision_row.payment_account_id is null
         or coalesce(lower(method_row.code), '') <> 'transfer'
         or method_row.account_id <> decision_row.payment_account_id
         or decision_row.payment_account_id <> import_row.erp_account_id
         or decision_row.advance_id is not null
         or (
           line_row.payment_method_id is not null
           and line_row.payment_method_id
                <> decision_row.payment_method_id
           and (
             employee_row.preferred_payment_method_id
               is distinct from decision_row.payment_method_id
             or exists (
               select 1
               from public.payment_methods snapshot_method
               join public.accounts snapshot_account
                 on snapshot_account.id = snapshot_method.account_id
                and snapshot_account.tenant_id =
                    snapshot_method.tenant_id
                and snapshot_account.is_active is true
                and snapshot_account.type = 'asset'
               where snapshot_method.id =
                   line_row.payment_method_id
                 and snapshot_method.tenant_id = tenant_id_value
                 and snapshot_method.is_active is true
                 and lower(snapshot_method.code) in ('transfer', 'cash')
             )
           )
         )
         or (
           line_row.payment_method_id is null
           and nullif(
             lower(trim(coalesce(line_row.payment_method::text, ''))),
             ''
           ) is not null
           and lower(
             coalesce(line_row.payment_method::text, '')
           ) <> 'transfer'
         )
         or (
           line_row.payment_method_id is null
           and nullif(
             lower(trim(coalesce(line_row.payment_method::text, ''))),
             ''
           ) is null
           and (
             (
               employee_row.preferred_payment_method_id is not null
               and employee_row.preferred_payment_method_id
                    <> decision_row.payment_method_id
             )
             or (
               employee_row.preferred_payment_method_id is null
               and lower(
                 coalesce(
                   employee_row.preferred_payment_method::text,
                   ''
                 )
               ) <> 'transfer'
             )
           )
         )
         or (
           line_row.payment_account_id is not null
           and line_row.payment_account_id
                <> decision_row.payment_account_id
           and (
             line_row.payment_method_id is null
             or (
               line_row.payment_method_id
                 <> decision_row.payment_method_id
               and (
                 employee_row.preferred_payment_method_id
                   is distinct from decision_row.payment_method_id
                 or exists (
                   select 1
                   from public.payment_methods snapshot_method
                   join public.accounts snapshot_account
                     on snapshot_account.id = snapshot_method.account_id
                    and snapshot_account.tenant_id =
                        snapshot_method.tenant_id
                    and snapshot_account.is_active is true
                    and snapshot_account.type = 'asset'
                   where snapshot_method.id =
                       line_row.payment_method_id
                     and snapshot_method.tenant_id = tenant_id_value
                     and snapshot_method.is_active is true
                     and lower(snapshot_method.code)
                       in ('transfer', 'cash')
                 )
               )
             )
           )
         )
         or row_record.transaction_date < line_row.period_start
         or row_record.transaction_date > line_row.period_end + 5
         or (
           decision_row.payment_date is not null
           and decision_row.payment_date <> row_record.transaction_date
         ) then
        raise exception 'payroll_statement_invalid_bank_payment_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;

      payment_at_value :=
        row_record.transaction_date::timestamp without time zone
          at time zone tenant_timezone;
      if payment_at_value > statement_timestamp() + interval '5 minutes'
         and not coalesce(
           (
             row_record.transaction_date =
               nullif(
                 import_row.source_metadata->>'statement_end',
                 ''
               )::date + 1
             and row_record.transaction_date <=
               (
                 import_row.created_at at time zone tenant_timezone
               )::date + 1
             and row_record.warnings
                   @> '["out_of_statement_range"]'::jsonb
             and decision_row.manual_confirmation is true
             and decision_row.reason is not null
           ),
           false
         ) then
        raise exception 'payroll_statement_bank_payment_is_future_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;

      if bank_variance_value = 0 then
        if decision_row.variance_disposition is distinct from 'exact' then
          raise exception 'payroll_statement_exact_disposition_required_%',
            decision_row.decision_ordinal
            using errcode = '22023';
        end if;
      elsif bank_variance_value < 0 then
        -- A debit below the live liability is an intentional partial payment,
        -- never a fuzzy match. Applying exactly the statement debit preserves
        -- the residual voucher/expense balance for a later settlement.
        if decision_row.variance_disposition is distinct from 'partial'
           or decision_row.applied_amount <> row_record.amount
           or row_record.amount >= live_line_balance_value
           or decision_row.manual_confirmation is not true
           or decision_row.reason is null then
          raise exception 'payroll_statement_partial_requires_review_%',
            decision_row.decision_ordinal
            using errcode = '22023';
        end if;
      else
        -- A debit above the liability may only use the existing bounded
        -- tolerance. The excess remains an explicitly reviewed variance and
        -- is never posted to the payroll obligation.
        if bank_variance_value > match_tolerance_value then
          raise exception 'payroll_statement_variance_outside_tolerance_%',
            decision_row.decision_ordinal
            using errcode = '22023';
        end if;

        if decision_row.variance_disposition
             is distinct from 'unresolved'
           or decision_row.manual_confirmation is not true
           or decision_row.reason is null then
          raise exception 'payroll_statement_variance_requires_review_%',
            decision_row.decision_ordinal
            using errcode = '22023';
        end if;
      end if;

      if jsonb_array_length(row_record.warnings) > 0
         and (
           decision_row.manual_confirmation is not true
           or decision_row.reason is null
         ) then
        raise exception 'payroll_statement_warning_requires_review_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;

      if decision_row.manual_confirmation is not true
         or decision_row.reason is null then
        raise exception 'payroll_statement_bank_payment_requires_review_%',
          decision_row.decision_ordinal
          using
            errcode = '22023',
            detail =
              'Every bank allocation requires a human confirmation '
              || 'and an audit reason';
      end if;

      if exists (
        select 1
        from public.payroll_statement_allocations allocation
        where allocation.tenant_id = tenant_id_value
          and allocation.row_fingerprint = row_record.fingerprint
      ) then
        raise exception 'payroll_statement_row_already_applied'
          using errcode = 'P0001';
      end if;

      update public.payroll_statement_decisions decision
      set payment_date = row_record.transaction_date,
          bank_amount = row_record.amount,
          variance = bank_variance_value,
          movement_reference = 'payroll-statement:' || decision.id::text
      where decision.id = decision_row.id;
    elsif decision_row.action = 'cash_payment' then
      if decision_row.manual_confirmation is not true
         or decision_row.applied_amount is null
         or decision_row.payment_date is null
         or decision_row.payment_method_id is null
         or decision_row.payment_account_id is null
         or coalesce(lower(method_row.code), '') <> 'cash'
         or method_row.account_id <> decision_row.payment_account_id
         or decision_row.advance_id is not null
         or (
           line_row.payment_method_id is not null
           and line_row.payment_method_id
                <> decision_row.payment_method_id
           and (
             employee_row.preferred_payment_method_id
               is distinct from decision_row.payment_method_id
             or exists (
               select 1
               from public.payment_methods snapshot_method
               join public.accounts snapshot_account
                 on snapshot_account.id = snapshot_method.account_id
                and snapshot_account.tenant_id =
                    snapshot_method.tenant_id
                and snapshot_account.is_active is true
                and snapshot_account.type = 'asset'
               where snapshot_method.id =
                   line_row.payment_method_id
                 and snapshot_method.tenant_id = tenant_id_value
                 and snapshot_method.is_active is true
                 and lower(snapshot_method.code) in ('transfer', 'cash')
             )
           )
         )
         or (
           line_row.payment_method_id is null
           and nullif(
             lower(trim(coalesce(line_row.payment_method::text, ''))),
             ''
           ) is not null
           and lower(
             coalesce(line_row.payment_method::text, '')
           ) <> 'cash'
         )
         or (
           line_row.payment_method_id is null
           and nullif(
             lower(trim(coalesce(line_row.payment_method::text, ''))),
             ''
           ) is null
           and (
             (
               employee_row.preferred_payment_method_id is not null
               and employee_row.preferred_payment_method_id
                    <> decision_row.payment_method_id
             )
             or (
               employee_row.preferred_payment_method_id is null
               and lower(
                 coalesce(
                   employee_row.preferred_payment_method::text,
                   ''
                 )
               ) <> 'cash'
             )
           )
         )
         or (
           line_row.payment_account_id is not null
           and line_row.payment_account_id
                <> decision_row.payment_account_id
           and (
             line_row.payment_method_id is null
             or (
               line_row.payment_method_id
                 <> decision_row.payment_method_id
               and (
                 employee_row.preferred_payment_method_id
                   is distinct from decision_row.payment_method_id
                 or exists (
                   select 1
                   from public.payment_methods snapshot_method
                   join public.accounts snapshot_account
                     on snapshot_account.id = snapshot_method.account_id
                    and snapshot_account.tenant_id =
                        snapshot_method.tenant_id
                    and snapshot_account.is_active is true
                    and snapshot_account.type = 'asset'
                   where snapshot_method.id =
                       line_row.payment_method_id
                     and snapshot_method.tenant_id = tenant_id_value
                     and snapshot_method.is_active is true
                     and lower(snapshot_method.code)
                       in ('transfer', 'cash')
                 )
               )
             )
           )
         )
         or decision_row.payment_date < line_row.period_start
         or decision_row.payment_date > line_row.period_end + 5 then
        raise exception 'payroll_statement_invalid_cash_confirmation_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;

      payment_at_value :=
        decision_row.payment_date::timestamp without time zone
          at time zone tenant_timezone;
      if payment_at_value > statement_timestamp() + interval '5 minutes' then
        raise exception 'payroll_statement_cash_payment_is_future_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;

      update public.payroll_statement_decisions decision
      set variance_disposition = 'not_applicable',
          movement_reference = 'payroll-statement:' || decision.id::text
      where decision.id = decision_row.id;
    elsif decision_row.action = 'advance_allocation' then
      if decision_row.advance_id is null
         or decision_row.applied_amount is null
         or decision_row.payment_method_id is not null
         or decision_row.payment_account_id is not null
         or decision_row.payment_date is not null
         or decision_row.variance_disposition is not null then
        raise exception 'payroll_statement_invalid_advance_allocation_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;

      select advance.*
      into advance_row
      from public.employee_advances advance
      where advance.id = decision_row.advance_id
        and advance.tenant_id = tenant_id_value
        and advance.employee_id = line_row.employee_id
        and advance.status in ('open', 'partially_applied')
        and (
          advance.paid_at at time zone tenant_timezone
        )::date <= line_row.period_end;

      if not found then
        raise exception 'Payroll advance not found'
          using errcode = '42501';
      end if;

      update public.payroll_statement_decisions decision
      set variance_disposition = 'not_applicable',
          movement_reference = 'payroll-statement:' || decision.id::text
      where decision.id = decision_row.id;
    elsif decision_row.action = 'not_paid' then
      if decision_row.manual_confirmation is not true
         or decision_row.reason is null
         or decision_row.applied_amount is not null
         or decision_row.payment_method_id is not null
         or decision_row.payment_account_id is not null
         or decision_row.payment_date is not null
         or decision_row.variance_disposition is not null
         or decision_row.advance_id is not null then
        raise exception 'payroll_statement_invalid_not_paid_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;
    elsif decision_row.action in (
      'ignore',
      'hold',
      'already_resolved'
    ) then
      if decision_row.applied_amount is not null
         or decision_row.payment_method_id is not null
         or decision_row.payment_account_id is not null
         or decision_row.payment_date is not null
         or decision_row.variance_disposition is not null
         or decision_row.advance_id is not null
         or decision_row.reason is null then
        raise exception 'payroll_statement_invalid_row_disposition_%',
          decision_row.decision_ordinal
          using errcode = '22023';
      end if;
    end if;
  end loop;

  -- Validate all selected movements against the live, locked liability. The
  -- internal payment command revalidates the same invariant while inserting.
  for line_row in
    select voucher_line.*
    from public.payroll_voucher_lines voucher_line
    join (
      select distinct decision.voucher_line_id
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.voucher_line_id is not null
    ) selected on selected.voucher_line_id = voucher_line.id
    order by voucher_line.id
  loop
    select coalesce(sum(decision.applied_amount), 0)
    into requested_line_total_value
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and decision.voucher_line_id = line_row.id
      and decision.action in (
        'bank_payment',
        'cash_payment',
        'advance_allocation'
      );

    select
      coalesce(
        (
          select sum(payment.amount)
          from public.expense_payments payment
          where payment.expense_id = line_row.expense_id
        ),
        0
      )
      + coalesce(
        (
          select sum(allocation.amount)
          from public.employee_advance_allocations allocation
          where allocation.voucher_line_id = line_row.id
        ),
        0
      )
    into current_settled_value;

    if requested_line_total_value
         > line_row.total_amount - current_settled_value + 0.01 then
      raise exception 'payroll_statement_movements_exceed_live_balance'
        using errcode = '22023';
    end if;
  end loop;

  for advance_row in
    select advance.*
    from public.employee_advances advance
    join (
      select distinct decision.advance_id
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.advance_id is not null
    ) selected on selected.advance_id = advance.id
    order by advance.id
  loop
    select coalesce(sum(decision.applied_amount), 0)
    into requested_advance_total_value
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and decision.advance_id = advance_row.id;

    if requested_advance_total_value
         > advance_row.amount - advance_row.amount_applied + 0.01 then
      raise exception 'payroll_statement_advance_balance_exceeded'
        using errcode = '22023';
    end if;
  end loop;

  -- The mature payroll internals cast period_end to timestamptz. Pin the
  -- transaction-local timezone to the tenant so civil dates do not depend on
  -- the device/session timezone.
  perform set_config('TimeZone', tenant_timezone, true);

  for voucher_row in
    select voucher.*
    from public.payroll_vouchers voucher
    join (
      select distinct decision.voucher_id
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.voucher_id is not null
    ) selected on selected.voucher_id = voucher.id
    order by voucher.id
  loop
    if voucher_row.status = 'draft' then
      if not (
        canonical_authorized_draft_voucher_ids_value
          ? voucher_row.id::text
      ) then
        raise exception
          'payroll_statement_draft_commitment_authorization_mismatch'
          using errcode = '22023';
      end if;
      perform public.confirm_payroll_voucher_internal(voucher_row.id);
    elsif voucher_row.status not in ('confirmed', 'partial') then
      raise exception 'Payroll voucher is not open for reconciliation'
        using errcode = '22023';
    end if;
  end loop;

  for voucher_row in
    select voucher.*
    from public.payroll_vouchers voucher
    join (
      select distinct decision.voucher_id
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.action in (
          'bank_payment',
          'cash_payment',
          'advance_allocation'
        )
    ) selected on selected.voucher_id = voucher.id
    order by voucher.id
  loop
    split_map_value := '{}'::jsonb;

    for voucher_line_id_value in
      select distinct decision.voucher_line_id
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.voucher_id = voucher_row.id
        and decision.action in (
          'bank_payment',
          'cash_payment',
          'advance_allocation'
        )
      order by decision.voucher_line_id
    loop
      select jsonb_agg(
        case
          when decision.action = 'advance_allocation' then
            jsonb_build_object(
              'kind',
              'advance',
              'advance_id',
              decision.advance_id,
              'amount',
              decision.applied_amount,
              'notes',
              decision.movement_reference
            )
          else
            jsonb_build_object(
              'kind',
              'payment',
              'payment_method_id',
              decision.payment_method_id,
              'payment_account_id',
              decision.payment_account_id,
              'amount',
              decision.applied_amount,
              'payment_date',
              decision.payment_date::timestamp without time zone
                at time zone tenant_timezone,
              'reference',
              decision.movement_reference,
              'notes',
              'Payroll statement reconciliation '
                || p_import_id::text
            )
        end
        order by decision.decision_ordinal
      )
      into line_splits_value
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.voucher_line_id = voucher_line_id_value
        and decision.action in (
          'bank_payment',
          'cash_payment',
          'advance_allocation'
        );

      split_map_value := jsonb_set(
        split_map_value,
        array[voucher_line_id_value::text],
        line_splits_value,
        true
      );
    end loop;

    perform public.pay_payroll_voucher_internal(
      voucher_row.id,
      split_map_value
    );
  end loop;

  update public.payroll_statement_decisions decision
  set result_expense_payment_id = payment.id
  from public.payroll_voucher_lines voucher_line
  join public.expense_payments payment
    on payment.expense_id = voucher_line.expense_id
  where decision.import_id = p_import_id
    and decision.action in ('bank_payment', 'cash_payment')
    and voucher_line.id = decision.voucher_line_id
    and payment.tenant_id = tenant_id_value
    and payment.reference = decision.movement_reference;

  update public.payroll_statement_decisions decision
  set result_advance_allocation_id = allocation.id
  from public.employee_advance_allocations allocation
  where decision.import_id = p_import_id
    and decision.action = 'advance_allocation'
    and allocation.tenant_id = tenant_id_value
    and allocation.voucher_line_id = decision.voucher_line_id
    and allocation.advance_id = decision.advance_id
    and allocation.notes = decision.movement_reference;

  if exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.import_id = p_import_id
      and (
        (
          decision.action in ('bank_payment', 'cash_payment')
          and decision.result_expense_payment_id is null
        )
        or (
          decision.action = 'advance_allocation'
          and decision.result_advance_allocation_id is null
        )
      )
  ) then
    raise exception 'payroll_statement_result_link_missing'
      using errcode = '55000';
  end if;

  insert into public.payroll_statement_allocations (
    tenant_id,
    import_id,
    decision_id,
    action,
    row_id,
    row_fingerprint,
    voucher_id,
    voucher_line_id,
    employee_id,
    expense_payment_id,
    employee_advance_allocation_id,
    bank_amount,
    applied_amount,
    variance,
    variance_disposition,
    payment_date,
    movement_reference,
    applied_by
  )
  select
    decision.tenant_id,
    decision.import_id,
    decision.id,
    decision.action,
    decision.row_id,
    decision.row_fingerprint,
    decision.voucher_id,
    decision.voucher_line_id,
    decision.employee_id,
    decision.result_expense_payment_id,
    decision.result_advance_allocation_id,
    case
      when decision.action = 'bank_payment' then decision.bank_amount
      else null
    end,
    decision.applied_amount,
    case
      when decision.action = 'bank_payment' then decision.variance
      else null
    end,
    coalesce(decision.variance_disposition, 'not_applicable'),
    decision.payment_date,
    decision.movement_reference,
    auth.uid()
  from public.payroll_statement_decisions decision
  where decision.import_id = p_import_id
    and decision.action in (
      'bank_payment',
      'cash_payment',
      'advance_allocation'
    );

  update public.payroll_statement_decisions decision
  set outcome = case
    when decision.action in (
      'bank_payment',
      'cash_payment',
      'advance_allocation'
    ) then 'applied'
    when decision.action = 'hold' then 'held'
    else 'acknowledged'
  end
  where decision.import_id = p_import_id;

  select
    count(*)::integer,
    coalesce(sum(decision.variance), 0)::numeric(14,2)
  into
    unresolved_variance_count_value,
    unresolved_variance_total_value
  from public.payroll_statement_decisions decision
  where decision.import_id = p_import_id
    and decision.action = 'bank_payment'
    and decision.variance_disposition = 'unresolved'
    and decision.variance <> 0;

  select count(*)::integer
  into already_resolved_count_value
  from public.payroll_statement_decisions decision
  where decision.import_id = p_import_id
    and decision.action = 'already_resolved';

  final_status_value := case
    when exists (
      select 1
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
        and decision.action = 'hold'
    ) then 'held'
    when unresolved_variance_count_value > 0
      then 'applied_with_variances'
    else 'applied'
  end;

  receipt_value := jsonb_build_object(
    'import_id',
    p_import_id,
    'status',
    final_status_value,
    'revision',
    import_row.revision,
    'hold_is_terminal',
    final_status_value = 'held',
    'operation_key',
    operation_key_value,
    'payload_hash',
    payload_hash_value,
    'decision_count',
    (
      select count(*)
      from public.payroll_statement_decisions decision
      where decision.import_id = p_import_id
    ),
    'allocation_count',
    (
      select count(*)
      from public.payroll_statement_allocations allocation
      where allocation.import_id = p_import_id
    ),
    'already_resolved_count',
    already_resolved_count_value,
    'unresolved_variance_count',
    unresolved_variance_count_value,
    'unresolved_variance_total',
    unresolved_variance_total_value,
    'committed_voucher_ids',
    canonical_authorized_draft_voucher_ids_value,
    'voucher_versions',
    coalesce(
      (
        select jsonb_object_agg(
          voucher.id::text,
          voucher.reconciliation_version
          order by voucher.id::text
        )
        from public.payroll_vouchers voucher
        where voucher.id in (
          select decision.voucher_id
          from public.payroll_statement_decisions decision
          where decision.import_id = p_import_id
            and decision.voucher_id is not null
        )
      ),
      '{}'::jsonb
    )
  );

  update public.payroll_statement_imports statement_import
  set status = final_status_value,
      apply_operation_key = operation_key_value,
      apply_payload_hash = payload_hash_value,
      apply_receipt = receipt_value,
      applied_by = auth.uid(),
      applied_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where statement_import.id = p_import_id
    and statement_import.tenant_id = tenant_id_value;

  delete from public.payroll_statement_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.import_id = p_import_id
    and command_context.command = 'apply';

  perform set_config('TimeZone', prior_timezone, true);
  return receipt_value;
exception
  when unique_violation then
    get stacked diagnostics
      violated_constraint_name = constraint_name;
    if violated_constraint_name in (
      'ux_payroll_statement_decisions_resolved_fingerprint',
      'ux_payroll_statement_allocations_tenant_fingerprint'
    ) then
      raise exception 'payroll_statement_row_or_operation_already_applied'
        using errcode = '23505';
    elsif violated_constraint_name in (
      'ux_payroll_statement_imports_apply_operation',
      'payroll_statement_decisions_import_id_decision_ordinal_key',
      'payroll_statement_decisions_import_id_row_id_key'
    ) then
      raise exception 'payroll_statement_apply_idempotency_conflict'
        using errcode = '23505';
    else
      raise;
    end if;
end;
$$;

-- Legacy money wrappers are owner-side compatibility shims only. They still
-- serialize on the same tenant lock and mint an unforgeable transient
-- capability so their internal implementation cannot bypass the DML guards.
create or replace function public.register_employee_advance(
  p_employee_id uuid,
  p_amount numeric,
  p_payment_method_id uuid,
  p_payment_account_id uuid default null,
  p_paid_at timestamp with time zone default statement_timestamp(),
  p_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  tenant_timezone text;
  prior_timezone text := current_setting('TimeZone');
  result_value uuid;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select coalesce(nullif(trim(tenant.timezone), ''), 'America/Santiago')
  into tenant_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value;
  perform set_config('TimeZone', tenant_timezone, true);

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'advance_registration',
    'legacy-advance:' || gen_random_uuid()::text,
    auth.uid()
  );

  result_value := public.register_employee_advance_internal(
    p_employee_id,
    p_amount,
    p_payment_method_id,
    p_payment_account_id,
    p_paid_at,
    p_reference,
    p_notes
  );

  perform set_config('TimeZone', prior_timezone, true);

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'advance_registration';

  return result_value;
end;
$$;

-- Serialize the established manual payment path with reconciliation and reject
-- unaudited reversals once statement evidence exists.
create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid,
  p_payment_splits jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  tenant_timezone text;
  prior_timezone text := current_setting('TimeZone');
  context_import_id_value uuid;
  result_value boolean;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select coalesce(nullif(trim(tenant.timezone), ''), 'America/Santiago')
  into tenant_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value;
  perform set_config('TimeZone', tenant_timezone, true);

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'manual_payment',
    'legacy-payment:' || p_voucher_id::text,
    auth.uid()
  );

  select min(decision.import_id::text)::uuid
  into context_import_id_value
  from public.payroll_statement_decisions decision
  where decision.tenant_id = tenant_id_value
    and decision.voucher_id = p_voucher_id;

  if context_import_id_value is not null then
    insert into public.payroll_statement_command_contexts (
      transaction_id,
      tenant_id,
      import_id,
      command,
      actor_id
    )
    values (
      txid_current(),
      tenant_id_value,
      context_import_id_value,
      'manual_settlement',
      auth.uid()
    );
  end if;

  result_value := public.pay_payroll_voucher_internal(
    p_voucher_id,
    p_payment_splits
  );

  perform set_config('TimeZone', prior_timezone, true);

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'manual_payment';

  if context_import_id_value is not null then
    delete from public.payroll_statement_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.import_id = context_import_id_value
      and command_context.command = 'manual_settlement';
  end if;

  return result_value;
end;
$$;

create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  tenant_timezone text;
  prior_timezone text := current_setting('TimeZone');
  context_import_id_value uuid;
  result_value boolean;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select coalesce(nullif(trim(tenant.timezone), ''), 'America/Santiago')
  into tenant_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value;
  perform set_config('TimeZone', tenant_timezone, true);

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'manual_payment',
    'legacy-payment:' || p_voucher_id::text,
    auth.uid()
  );

  select min(decision.import_id::text)::uuid
  into context_import_id_value
  from public.payroll_statement_decisions decision
  where decision.tenant_id = tenant_id_value
    and decision.voucher_id = p_voucher_id;

  if context_import_id_value is not null then
    insert into public.payroll_statement_command_contexts (
      transaction_id,
      tenant_id,
      import_id,
      command,
      actor_id
    )
    values (
      txid_current(),
      tenant_id_value,
      context_import_id_value,
      'manual_settlement',
      auth.uid()
    );
  end if;

  result_value :=
    public.pay_payroll_voucher_internal(p_voucher_id, null);

  perform set_config('TimeZone', prior_timezone, true);

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'manual_payment';

  if context_import_id_value is not null then
    delete from public.payroll_statement_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.import_id = context_import_id_value
      and command_context.command = 'manual_settlement';
  end if;

  return result_value;
end;
$$;

create or replace function public.revert_payroll_payment(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  result_value boolean;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  if exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.tenant_id = tenant_id_value
      and decision.voucher_id = p_voucher_id
  ) or exists (
    select 1
    from public.payroll_money_operations money_operation
    where money_operation.tenant_id = tenant_id_value
      and money_operation.voucher_id = p_voucher_id
  ) then
    raise exception 'payroll_reconciliation_requires_audited_reversal'
      using errcode = '55000';
  end if;

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'legacy_reversal',
    'legacy-reversal:' || p_voucher_id::text,
    auth.uid()
  );

  result_value := public.revert_payroll_payment_internal(p_voucher_id);

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'legacy_reversal';

  return result_value;
end;
$$;

create or replace function public.revert_payroll_to_draft(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  result_value boolean;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  if exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.tenant_id = tenant_id_value
      and decision.voucher_id = p_voucher_id
  ) or exists (
    select 1
    from public.payroll_money_operations money_operation
    where money_operation.tenant_id = tenant_id_value
      and money_operation.voucher_id = p_voucher_id
  ) then
    raise exception 'payroll_reconciliation_requires_audited_reversal'
      using errcode = '55000';
  end if;

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  )
  values (
    txid_current(),
    tenant_id_value,
    'legacy_reversal',
    'legacy-reversal:' || p_voucher_id::text,
    auth.uid()
  );

  result_value := public.revert_payroll_to_draft_internal(p_voucher_id);

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'legacy_reversal';

  return result_value;
end;
$$;

-- Draft deletion is a server-owned aggregate command. It rejects any evidence
-- of settlement and removes orphanable draft expenses after voucher-line
-- cascade. Confirmed/partial/paid vouchers remain immutable through this path.
create or replace function public.delete_payroll_voucher_draft(
  p_voucher_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  voucher_row public.payroll_vouchers%rowtype;
  expense_ids_value uuid[];
  deleted_expense_count integer := 0;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  if not found then
    raise exception 'Payroll voucher not found'
      using errcode = 'P0002';
  end if;

  if voucher_row.status <> 'draft' then
    raise exception 'Only a draft payroll voucher can be deleted'
      using errcode = '22023';
  end if;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.tenant_id = tenant_id_value
  order by voucher_line.id
  for update;

  if exists (
    select 1
    from public.payroll_voucher_lines voucher_line
    join public.expense_payments payment
      on payment.expense_id = voucher_line.expense_id
    where voucher_line.voucher_id = p_voucher_id
  ) or exists (
    select 1
    from public.payroll_voucher_lines voucher_line
    join public.employee_advance_allocations allocation
      on allocation.voucher_line_id = voucher_line.id
    where voucher_line.voucher_id = p_voucher_id
  ) or exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.voucher_id = p_voucher_id
  ) then
    raise exception 'A payroll voucher with settlement evidence cannot be deleted'
      using errcode = '55000';
  end if;

  select array_agg(voucher_line.expense_id order by voucher_line.expense_id)
  into expense_ids_value
  from public.payroll_voucher_lines voucher_line
  where voucher_line.voucher_id = p_voucher_id
    and voucher_line.expense_id is not null;

  delete from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value;

  if expense_ids_value is not null then
    delete from public.expenses expense
    where expense.tenant_id = tenant_id_value
      and expense.id = any(expense_ids_value);
    get diagnostics deleted_expense_count = row_count;
  end if;

  return jsonb_build_object(
    'voucher_id',
    p_voucher_id,
    'deleted',
    true,
    'deleted_expense_count',
    deleted_expense_count
  );
end;
$$;

-- Deletion keeps its operation receipt after the aggregate disappears. Exact
-- replay is therefore resolved before attempting to load the deleted voucher.
create or replace function public.delete_payroll_voucher_draft_v2(
  p_voucher_id uuid,
  p_operation_key text,
  p_expected_reconciliation_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := trim(coalesce(p_operation_key, ''));
  payload_hash_value text;
  existing_operation public.payroll_voucher_draft_operations%rowtype;
  voucher_row public.payroll_vouchers%rowtype;
  deletion_result_value jsonb;
  receipt_value jsonb;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_voucher_id is null
     or operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or p_expected_reconciliation_version is null
     or p_expected_reconciliation_version < 0 then
    raise exception 'payroll_voucher_lifecycle_invalid_payload'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'command',
          'delete_draft',
          'voucher_id',
          p_voucher_id,
          'expected_reconciliation_version',
          p_expected_reconciliation_version
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

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
    if existing_operation.payload_hash = payload_hash_value
       and existing_operation.receipt->>'operation' = 'delete_draft' then
      return existing_operation.receipt;
    end if;
    raise exception 'payroll_voucher_lifecycle_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different payload';
  end if;

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  if not found then
    raise exception 'Payroll voucher not found'
      using errcode = '42501';
  end if;

  if voucher_row.reconciliation_version
       <> p_expected_reconciliation_version then
    raise exception 'payroll_voucher_lifecycle_version_conflict'
      using
        errcode = '40001',
        detail = 'reload the complete payroll voucher before continuing';
  end if;

  if voucher_row.status <> 'draft' then
    raise exception 'payroll_voucher_is_not_a_draft'
      using errcode = '55000';
  end if;

  deletion_result_value :=
    public.delete_payroll_voucher_draft(p_voucher_id);

  receipt_value := deletion_result_value || jsonb_build_object(
    'operation',
    'delete_draft',
    'operation_key',
    operation_key_value,
    'payload_hash',
    payload_hash_value,
    'voucher_id',
    p_voucher_id,
    'expected_reconciliation_version',
    p_expected_reconciliation_version,
    'deleted_reconciliation_version',
    voucher_row.reconciliation_version
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
    null,
    p_expected_reconciliation_version,
    receipt_value,
    auth.uid()
  );

  return receipt_value;
end;
$$;

revoke all on function public.create_payroll_statement_import(
  text,
  text,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.save_payroll_voucher_draft(
  uuid,
  text,
  bigint,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.confirm_payroll_voucher_v2(
  uuid,
  text,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.pay_payroll_voucher_v2(
  uuid,
  text,
  bigint,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.register_employee_advance_v2(
  text,
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.apply_payroll_statement_reconciliation(
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.delete_payroll_voucher_draft(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_payroll_voucher_draft_v2(
  uuid,
  text,
  bigint
) from public, anon, authenticated, service_role;
revoke all on function public.confirm_payroll_voucher(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.create_payroll_statement_import(
  text,
  text,
  jsonb,
  jsonb
) to authenticated;
grant execute on function public.save_payroll_voucher_draft(
  uuid,
  text,
  bigint,
  jsonb,
  jsonb
) to authenticated;
grant execute on function public.confirm_payroll_voucher_v2(
  uuid,
  text,
  bigint
) to authenticated;
grant execute on function public.pay_payroll_voucher_v2(
  uuid,
  text,
  bigint,
  jsonb
) to authenticated;
grant execute on function public.register_employee_advance_v2(
  text,
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) to authenticated;
grant execute on function public.apply_payroll_statement_reconciliation(
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb
) to authenticated;
grant execute on function public.delete_payroll_voucher_draft_v2(
  uuid,
  text,
  bigint
) to authenticated;
grant execute on function public.delete_payroll_voucher_draft(uuid)
  to service_role;
grant execute on function public.confirm_payroll_voucher(uuid)
  to service_role;

-- Header plus complete-line draft writes are a single server-owned command.
-- This closes the insert-after-apply race that exists when a REST line write
-- can pass its BEFORE guard and wait on the line-to-header AFTER trigger.
revoke insert, update, delete on table public.payroll_vouchers
  from public, anon, authenticated, service_role;
revoke insert, update, delete on table public.payroll_voucher_lines
  from public, anon, authenticated, service_role;
revoke insert, update, delete on table public.employee_advances
  from public, anon, authenticated, service_role;
revoke insert, update, delete on table public.employee_advance_allocations
  from public, anon, authenticated, service_role;

-- Money-moving client entrypoints require an idempotency key. The legacy
-- wrappers remain callable by owner-side routines only.
revoke all on function public.pay_payroll_voucher(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.pay_payroll_voucher(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.register_employee_advance(
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) from public, anon, authenticated, service_role;

comment on table public.payroll_statement_imports is
  'Payroll-only review receipt for a statement digest. Raw file bytes, account number, holder, RUT, and balances are rejected from metadata; only a stable local account hash and reviewed ERP account UUID are retained.';
comment on table public.payroll_statement_import_operations is
  'Immutable idempotency history for current and superseded OCR review revisions.';
comment on table public.payroll_statement_rows is
  'Sensitive payroll-only parser/OCR observations. Bank descriptions can themselves contain identifiers; warning payloads are restricted to short codes. Importing a row has no payment side effect.';
comment on table public.payroll_statement_decisions is
  'Explicit reviewed row and cash decisions for one atomic final operation. hold is a terminal retained disposition, not a resumable pause.';
comment on table public.payroll_statement_allocations is
  'Immutable evidence linking an applied reconciliation decision to the resulting payroll settlement.';
comment on table public.payroll_voucher_draft_operations is
  'Immutable idempotency receipts for atomic payroll draft creation, replacement, confirmation, and deletion.';
comment on table public.payroll_money_operations is
  'Immutable idempotency receipts for manual payroll settlements and employee advances. A tenant operation key identifies exactly one money payload.';
comment on table public.payroll_money_operation_movements is
  'Tenant-safe immutable links from a manual payroll money receipt to every expense payment or advance allocation it created.';
comment on function public.save_payroll_voucher_draft(
  uuid,
  text,
  bigint,
  jsonb,
  jsonb
) is
  'Creates or replaces one draft header plus its complete line snapshot under the payroll settlement lock. Totals and line IDs are server-owned, and retries return the original receipt.';
comment on function public.confirm_payroll_voucher_v2(
  uuid,
  text,
  bigint
) is
  'Confirms one exact draft version and returns an immutable receipt on every exact operation-key replay.';
comment on function public.pay_payroll_voucher_v2(
  uuid,
  text,
  bigint,
  jsonb
) is
  'Idempotent manual payroll settlement command with exact voucher version, stored payload hash, and movement receipt.';
comment on function public.register_employee_advance_v2(
  text,
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) is
  'Idempotent employee advance command with a reviewed payment account and stored money receipt.';
comment on function public.create_payroll_statement_import(
  text,
  text,
  jsonb,
  jsonb
) is
  'Idempotently stores or revises review-only rows for one statement digest. A revision atomically invalidates prior row IDs while still in review and never pays payroll.';
comment on function public.apply_payroll_statement_reconciliation(
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb
) is
  'Atomically applies explicit reviewed payroll decisions with stable account-scoped row dedupe, live balances, tenant locks, voucher-version checks, and an exact allow-list for draft vouchers the operator authorized to commit. The receipt returns committed_voucher_ids. A manually confirmed partial debit posts exactly the bank amount and leaves the residual obligation open; bounded overpayment variance remains unresolved and is not a full bank-ledger reconciliation.';
comment on function public.delete_payroll_voucher_draft(uuid) is
  'Service-only legacy aggregate deletion used behind the versioned public command.';
comment on function public.delete_payroll_voucher_draft_v2(
  uuid,
  text,
  bigint
) is
  'Deletes one exact locked draft version only without settlement evidence; its immutable receipt survives the aggregate deletion.';

commit;
