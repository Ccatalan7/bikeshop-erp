-- Intelligent bank reconciliation foundation.
--
-- Deployment status: reviewed production-bound forward migration; guarded
-- production apply, exact read-back, and history registration are part of
-- this task.
-- Verification status: 20/20 focused pgTAP assertions pass on a disposable
-- production-derived schema capture dated 2026-08-14.
--
-- The bank statement is evidence. This migration never creates, edits or
-- settles a sale, purchase, expense or journal entry. It stores a privacy-
-- bounded statement projection and explicit many-to-many links to operations
-- that already exist in the ERP.

create extension if not exists pgcrypto;

alter table public.payment_methods
  add column if not exists settlement_provider text not null default 'none'
    check (settlement_provider in ('none', 'transbank', 'mercadopago', 'other')),
  add column if not exists payment_instrument text not null default 'unknown'
    check (payment_instrument in ('unknown', 'debit', 'credit', 'prepaid'));

update public.payment_methods
   set settlement_provider = case
     when lower(code) = 'card' then 'transbank'
     when lower(code) = 'mercadopago' then 'mercadopago'
     else settlement_provider
   end
 where settlement_provider = 'none'
   and lower(code) in ('card', 'mercadopago');

comment on column public.payment_methods.settlement_provider is
  'Settlement provider for bank reconciliation. card defaults to Transbank; none means no aggregator.';
comment on column public.payment_methods.payment_instrument is
  'Card rail when known: debit, credit or prepaid. unknown preserves today''s combined method without blocking future separation.';

create table if not exists public.bank_statement_imports (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  erp_account_id uuid not null,
  file_sha256 text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  account_fingerprint text check (
    account_fingerprint is null or account_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  source_metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_metadata) = 'object'),
  status text not null default 'review'
    check (status in ('review', 'partially_reconciled', 'reconciled', 'held')),
  revision bigint not null default 1 check (revision > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, erp_account_id, file_sha256),
  unique (tenant_id, id),
  constraint bank_statement_imports_account_fk
    foreign key (tenant_id, erp_account_id)
    references public.accounts(tenant_id, id) on delete restrict
);

create table if not exists public.bank_statement_rows (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_id uuid not null,
  source_row_id text not null check (length(trim(source_row_id)) between 1 and 120),
  ordinal integer not null check (ordinal between 1 and 5000),
  booking_date date,
  operation_date date,
  direction text not null check (direction in ('debit', 'credit', 'unknown')),
  amount numeric(14,2) check (amount is null or amount > 0),
  description text not null check (length(trim(description)) between 1 and 1000),
  normalized_description text not null
    check (length(normalized_description) between 1 and 1000),
  counterparty_observed text,
  document_number text,
  balance numeric(14,2),
  warning_codes text[] not null default '{}',
  source_page integer not null check (source_page > 0),
  source_line_start integer not null check (source_line_start > 0),
  source_line_end integer not null check (source_line_end >= source_line_start),
  fingerprint text not null check (fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique (import_id, source_row_id),
  unique (import_id, ordinal),
  constraint bank_statement_rows_import_fk
    foreign key (tenant_id, import_id)
    references public.bank_statement_imports(tenant_id, id) on delete cascade
);

create unique index if not exists uq_bank_statement_rows_tenant_id
  on public.bank_statement_rows(tenant_id, id);

create table if not exists public.bank_reconciliation_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_id uuid,
  operation_key text not null check (length(trim(operation_key)) between 1 and 200),
  action text not null check (action in ('create_import', 'apply_review')),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (tenant_id, operation_key),
  constraint bank_reconciliation_operations_import_fk
    foreign key (tenant_id, import_id)
    references public.bank_statement_imports(tenant_id, id) on delete cascade
);

create table if not exists public.bank_reconciliation_row_decisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_id uuid not null,
  row_id uuid not null,
  disposition text not null
    check (disposition in ('pending', 'reconciled', 'ignored', 'held')),
  decided_by uuid not null references auth.users(id) on delete restrict,
  decided_at timestamptz not null default now(),
  unique (import_id, row_id),
  constraint bank_reconciliation_decisions_import_fk
    foreign key (tenant_id, import_id)
    references public.bank_statement_imports(tenant_id, id) on delete cascade,
  constraint bank_reconciliation_decisions_row_fk
    foreign key (tenant_id, row_id)
    references public.bank_statement_rows(tenant_id, id) on delete cascade
);

create table if not exists public.bank_reconciliation_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  import_id uuid not null,
  row_id uuid not null,
  target_kind text not null check (target_kind in (
    'sales_payment', 'purchase_payment', 'expense_payment', 'journal_entry'
  )),
  target_id uuid not null,
  bank_amount numeric(14,2) not null check (bank_amount > 0),
  target_amount numeric(14,2) not null check (target_amount > 0),
  match_kind text not null check (match_kind in (
    'direct', 'transbank_estimate', 'manual'
  )),
  confidence text not null check (confidence in ('low', 'medium', 'high')),
  provider text not null default 'none'
    check (provider in ('none', 'transbank', 'mercadopago', 'other')),
  instrument text not null default 'unknown'
    check (instrument in ('unknown', 'debit', 'credit', 'prepaid')),
  rationale jsonb not null default '{}'::jsonb
    check (jsonb_typeof(rationale) = 'object'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (row_id, target_kind, target_id),
  constraint bank_reconciliation_allocations_import_fk
    foreign key (tenant_id, import_id)
    references public.bank_statement_imports(tenant_id, id) on delete cascade,
  constraint bank_reconciliation_allocations_row_fk
    foreign key (tenant_id, row_id)
    references public.bank_statement_rows(tenant_id, id) on delete cascade
);

create index if not exists idx_bank_statement_imports_tenant_status
  on public.bank_statement_imports(tenant_id, status, updated_at desc);
create index if not exists idx_bank_statement_rows_import_date
  on public.bank_statement_rows(import_id, booking_date, ordinal);
create index if not exists idx_bank_statement_rows_fingerprint
  on public.bank_statement_rows(tenant_id, fingerprint);
create unique index if not exists uq_bank_reconciliation_allocations_target
  on public.bank_reconciliation_allocations(tenant_id, target_kind, target_id);

alter table public.bank_statement_imports enable row level security;
alter table public.bank_statement_rows enable row level security;
alter table public.bank_reconciliation_operations enable row level security;
alter table public.bank_reconciliation_row_decisions enable row level security;
alter table public.bank_reconciliation_allocations enable row level security;

drop policy if exists bank_statement_imports_accounting_read
  on public.bank_statement_imports;
create policy bank_statement_imports_accounting_read
  on public.bank_statement_imports for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

drop policy if exists bank_statement_rows_accounting_read
  on public.bank_statement_rows;
create policy bank_statement_rows_accounting_read
  on public.bank_statement_rows for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

drop policy if exists bank_reconciliation_operations_accounting_read
  on public.bank_reconciliation_operations;
create policy bank_reconciliation_operations_accounting_read
  on public.bank_reconciliation_operations for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

drop policy if exists bank_reconciliation_decisions_accounting_read
  on public.bank_reconciliation_row_decisions;
create policy bank_reconciliation_decisions_accounting_read
  on public.bank_reconciliation_row_decisions for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

drop policy if exists bank_reconciliation_allocations_accounting_read
  on public.bank_reconciliation_allocations;
create policy bank_reconciliation_allocations_accounting_read
  on public.bank_reconciliation_allocations for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

revoke all on public.bank_statement_imports,
  public.bank_statement_rows,
  public.bank_reconciliation_operations,
  public.bank_reconciliation_row_decisions,
  public.bank_reconciliation_allocations
  from public, anon, authenticated;
grant select on public.bank_statement_imports,
  public.bank_statement_rows,
  public.bank_reconciliation_operations,
  public.bank_reconciliation_row_decisions,
  public.bank_reconciliation_allocations
  to authenticated;

create or replace function public.bank_reconciliation_target_snapshot(
  p_tenant_id uuid,
  p_erp_account_id uuid,
  p_target_kind text,
  p_target_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if p_target_kind = 'sales_payment' then
    select jsonb_build_object(
      'target_kind', 'sales_payment',
      'target_id', payment.id,
      'direction', 'credit',
      'amount', payment.amount,
      'occurred_on', payment.date::date,
      'label', 'Venta ' || invoice.invoice_number,
      'counterparty', coalesce(invoice.customer_name, customer.name, 'Cliente'),
      'reference', coalesce(payment.reference, payment.invoice_reference),
      'payment_method_code', method.code,
      'provider', method.settlement_provider,
      'instrument', method.payment_instrument
    ) into v_result
      from public.sales_payments payment
      join public.sales_invoices invoice
        on invoice.tenant_id = payment.tenant_id and invoice.id = payment.invoice_id
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      left join public.customers customer
        on customer.tenant_id = invoice.tenant_id and customer.id = invoice.customer_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id
       and payment.deleted_at is null
       and method.account_id = p_erp_account_id;
  elsif p_target_kind = 'purchase_payment' then
    select jsonb_build_object(
      'target_kind', 'purchase_payment',
      'target_id', payment.id,
      'direction', 'debit',
      'amount', payment.amount,
      'occurred_on', payment.date::date,
      'label', 'Compra ' || invoice.invoice_number,
      'counterparty', coalesce(invoice.supplier_name, supplier.name, 'Proveedor'),
      'reference', coalesce(payment.reference, payment.invoice_reference),
      'payment_method_code', method.code,
      'provider', method.settlement_provider,
      'instrument', method.payment_instrument
    ) into v_result
      from public.purchase_payments payment
      join public.purchase_invoices invoice
        on invoice.tenant_id = payment.tenant_id and invoice.id = payment.invoice_id
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      left join public.suppliers supplier
        on supplier.tenant_id = invoice.tenant_id and supplier.id = invoice.supplier_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id
       and payment.deleted_at is null
       and method.account_id = p_erp_account_id;
  elsif p_target_kind = 'expense_payment' then
    select jsonb_build_object(
      'target_kind', 'expense_payment',
      'target_id', payment.id,
      'direction', 'debit',
      'amount', payment.amount,
      'occurred_on', payment.payment_date::date,
      'label', 'Gasto ' || expense.expense_number,
      'counterparty', coalesce(expense.supplier_name, supplier.name, 'Proveedor'),
      'reference', coalesce(payment.reference, expense.reference),
      'payment_method_code', method.code,
      'provider', coalesce(method.settlement_provider, 'none'),
      'instrument', coalesce(method.payment_instrument, 'unknown')
    ) into v_result
      from public.expense_payments payment
      join public.expenses expense
        on expense.tenant_id = payment.tenant_id and expense.id = payment.expense_id
      left join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      left join public.suppliers supplier
        on supplier.tenant_id = expense.tenant_id and supplier.id = expense.supplier_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id
       and coalesce(payment.payment_account_id, method.account_id) = p_erp_account_id;
  elsif p_target_kind = 'journal_entry' then
    select jsonb_build_object(
      'target_kind', 'journal_entry',
      'target_id', entry.id,
      'direction', case
        when sum(line.debit_amount) > sum(line.credit_amount) then 'credit'
        else 'debit'
      end,
      'amount', abs(sum(line.debit_amount) - sum(line.credit_amount)),
      'occurred_on', entry.entry_date::date,
      'label', entry.entry_number || ' · ' || entry.description,
      'counterparty', null,
      'reference', entry.source_reference,
      'payment_method_code', null,
      'provider', 'none',
      'instrument', 'unknown'
    ) into v_result
      from public.journal_entries entry
      join public.journal_lines line
        on line.tenant_id = entry.tenant_id and line.entry_id = entry.id
     where entry.tenant_id = p_tenant_id
       and entry.id = p_target_id
       and entry.status = 'posted'
       and line.account_id = p_erp_account_id
     group by entry.id;
  else
    raise exception using
      errcode = '22023',
      message = 'bank_reconciliation_target_kind_invalid';
  end if;
  return v_result;
end;
$$;

revoke all on function public.bank_reconciliation_target_snapshot(
  uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;

create or replace function public.get_bank_reconciliation_candidates_v1(
  p_erp_account_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_candidates jsonb;
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_from_date is null or p_to_date is null or p_to_date < p_from_date
     or p_to_date - p_from_date > 370 then
    raise exception using errcode = '22023', message = 'bank_reconciliation_date_range_invalid';
  end if;
  if not exists (
    select 1 from public.accounts account
     where account.tenant_id = v_tenant_id
       and account.id = p_erp_account_id
       and account.type = 'asset'
       and account.is_active
  ) then
    raise exception using errcode = '42501', message = 'bank_account_not_accessible';
  end if;

  with candidates as (
    select public.bank_reconciliation_target_snapshot(
      v_tenant_id, p_erp_account_id, 'sales_payment', payment.id
    ) as candidate
      from public.sales_payments payment
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id and method.id = payment.payment_method_id
     where payment.tenant_id = v_tenant_id
       and payment.deleted_at is null
       and payment.date::date between p_from_date and p_to_date
       and method.account_id = p_erp_account_id
       and not exists (
         select 1
         from public.bank_reconciliation_allocations allocation
         where allocation.tenant_id = payment.tenant_id
           and allocation.target_kind = 'sales_payment'
           and allocation.target_id = payment.id
       )
    union all
    select public.bank_reconciliation_target_snapshot(
      v_tenant_id, p_erp_account_id, 'purchase_payment', payment.id
    )
      from public.purchase_payments payment
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id and method.id = payment.payment_method_id
     where payment.tenant_id = v_tenant_id
       and payment.deleted_at is null
       and payment.date::date between p_from_date and p_to_date
       and method.account_id = p_erp_account_id
       and not exists (
         select 1
         from public.bank_reconciliation_allocations allocation
         where allocation.tenant_id = payment.tenant_id
           and allocation.target_kind = 'purchase_payment'
           and allocation.target_id = payment.id
       )
    union all
    select public.bank_reconciliation_target_snapshot(
      v_tenant_id, p_erp_account_id, 'expense_payment', payment.id
    )
      from public.expense_payments payment
      left join public.payment_methods method
        on method.tenant_id = payment.tenant_id and method.id = payment.payment_method_id
     where payment.tenant_id = v_tenant_id
       and payment.payment_date::date between p_from_date and p_to_date
       and coalesce(payment.payment_account_id, method.account_id) = p_erp_account_id
       and not exists (
         select 1
         from public.bank_reconciliation_allocations allocation
         where allocation.tenant_id = payment.tenant_id
           and allocation.target_kind = 'expense_payment'
           and allocation.target_id = payment.id
       )
    union all
    select public.bank_reconciliation_target_snapshot(
      v_tenant_id, p_erp_account_id, 'journal_entry', entry.id
    )
      from public.journal_entries entry
     where entry.tenant_id = v_tenant_id
       and entry.status = 'posted'
       and entry.entry_date::date between p_from_date and p_to_date
       and coalesce(entry.source_module, '') not in (
         'sales', 'purchases', 'expenses', 'payroll'
       )
       and not exists (
         select 1
         from public.bank_reconciliation_allocations allocation
         where allocation.tenant_id = entry.tenant_id
           and allocation.target_kind = 'journal_entry'
           and allocation.target_id = entry.id
       )
       and exists (
         select 1 from public.journal_lines line
          where line.tenant_id = entry.tenant_id
            and line.entry_id = entry.id
            and line.account_id = p_erp_account_id
            and line.debit_amount <> line.credit_amount
       )
  )
  select coalesce(jsonb_agg(candidate order by candidate->>'occurred_on', candidate->>'target_id'), '[]'::jsonb)
    into v_candidates
    from candidates
   where candidate is not null;

  return jsonb_build_object('candidates', v_candidates);
end;
$$;

revoke all on function public.get_bank_reconciliation_candidates_v1(
  uuid, date, date
) from public, anon;
grant execute on function public.get_bank_reconciliation_candidates_v1(
  uuid, date, date
) to authenticated, service_role;

create or replace function public.save_bank_statement_import_v1(
  p_operation_key text,
  p_file_sha256 text,
  p_account_fingerprint text,
  p_erp_account_id uuid,
  p_source_metadata jsonb,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_payload_hash text;
  v_existing record;
  v_import record;
  v_row jsonb;
  v_row_id uuid;
  v_rows_receipt jsonb := '[]'::jsonb;
  v_receipt jsonb;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_operation_key is null or length(trim(p_operation_key)) not between 1 and 200
     or p_file_sha256 !~ '^[0-9a-f]{64}$'
     or (p_account_fingerprint is not null and p_account_fingerprint !~ '^[0-9a-f]{64}$')
     or jsonb_typeof(coalesce(p_source_metadata, '{}'::jsonb)) <> 'object'
     or coalesce(jsonb_typeof(p_rows), 'null') <> 'array'
     or jsonb_array_length(p_rows) not between 1 and 5000 then
    raise exception using errcode = '22023', message = 'bank_statement_import_payload_invalid';
  end if;
  if not exists (
    select 1 from public.accounts account
     where account.tenant_id = v_tenant_id
       and account.id = p_erp_account_id
       and account.type = 'asset'
       and account.is_active
  ) then
    raise exception using errcode = '42501', message = 'bank_account_not_accessible';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'file_sha256', p_file_sha256,
    'account_fingerprint', p_account_fingerprint,
    'erp_account_id', p_erp_account_id,
    'source_metadata', coalesce(p_source_metadata, '{}'::jsonb),
    'rows', p_rows
  )::text, 'utf8'), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':bank-reconciliation', 0
  ));
  select operation.action, operation.payload_hash, operation.receipt
    into v_existing
    from public.bank_reconciliation_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  if found then
    if v_existing.action <> 'create_import'
       or v_existing.payload_hash <> v_payload_hash then
      raise exception using errcode = 'P0001', message = 'bank_reconciliation_idempotency_conflict';
    end if;
    return v_existing.receipt || jsonb_build_object('replayed', true);
  end if;

  insert into public.bank_statement_imports (
    tenant_id, erp_account_id, file_sha256, account_fingerprint,
    source_metadata, created_by
  ) values (
    v_tenant_id, p_erp_account_id, p_file_sha256, p_account_fingerprint,
    coalesce(p_source_metadata, '{}'::jsonb), v_user_id
  )
  on conflict (tenant_id, erp_account_id, file_sha256) do update
    set source_metadata = public.bank_statement_imports.source_metadata
  returning id, revision, status into v_import;

  if not exists (
    select 1 from public.bank_statement_rows row
     where row.import_id = v_import.id
  ) then
    for v_row in select value from jsonb_array_elements(p_rows)
    loop
      if jsonb_typeof(v_row) <> 'object'
         or coalesce(v_row->>'source_row_id', '') = ''
         or coalesce(v_row->>'description', '') = ''
         or coalesce(v_row->>'normalized_description', '') = ''
         or coalesce(v_row->>'fingerprint', '') !~ '^[0-9a-f]{64}$'
         or coalesce(v_row->>'direction', '') not in ('debit', 'credit', 'unknown')
         or coalesce((v_row->>'ordinal')::integer, 0) not between 1 and 5000
         or coalesce((v_row->>'source_page')::integer, 0) <= 0
         or coalesce((v_row->>'source_line_start')::integer, 0) <= 0
         or coalesce((v_row->>'source_line_end')::integer, 0)
              < coalesce((v_row->>'source_line_start')::integer, 0) then
        raise exception using errcode = '22023', message = 'bank_statement_row_invalid';
      end if;
      insert into public.bank_statement_rows (
        tenant_id, import_id, source_row_id, ordinal, booking_date,
        operation_date, direction, amount, description,
        normalized_description, counterparty_observed, document_number,
        balance, warning_codes, source_page, source_line_start,
        source_line_end, fingerprint
      ) values (
        v_tenant_id,
        v_import.id,
        v_row->>'source_row_id',
        (v_row->>'ordinal')::integer,
        nullif(v_row->>'booking_date', '')::date,
        nullif(v_row->>'operation_date', '')::date,
        v_row->>'direction',
        nullif(v_row->>'amount', '')::numeric,
        v_row->>'description',
        v_row->>'normalized_description',
        nullif(v_row->>'counterparty_observed', ''),
        nullif(v_row->>'document_number', ''),
        nullif(v_row->>'balance', '')::numeric,
        coalesce(array(
          select jsonb_array_elements_text(coalesce(v_row->'warning_codes', '[]'::jsonb))
        ), '{}'::text[]),
        (v_row->>'source_page')::integer,
        (v_row->>'source_line_start')::integer,
        (v_row->>'source_line_end')::integer,
        v_row->>'fingerprint'
      ) returning id into v_row_id;
      v_rows_receipt := v_rows_receipt || jsonb_build_array(jsonb_build_object(
        'source_row_id', v_row->>'source_row_id', 'row_id', v_row_id
      ));
    end loop;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'source_row_id', row.source_row_id, 'row_id', row.id
    ) order by row.ordinal), '[]'::jsonb)
      into v_rows_receipt
      from public.bank_statement_rows row
     where row.import_id = v_import.id;
    if jsonb_array_length(v_rows_receipt) <> jsonb_array_length(p_rows)
       or exists (
         select 1
         from jsonb_array_elements(p_rows) payload(row_payload)
         where not exists (
           select 1
           from public.bank_statement_rows stored
           where stored.import_id = v_import.id
             and stored.source_row_id = payload.row_payload->>'source_row_id'
             and stored.ordinal = (payload.row_payload->>'ordinal')::integer
             and stored.fingerprint = payload.row_payload->>'fingerprint'
         )
       ) then
      raise exception using errcode = '55000', message = 'bank_statement_import_shape_conflict';
    end if;
  end if;

  v_receipt := jsonb_build_object(
    'operation', 'create_import',
    'operation_key', trim(p_operation_key),
    'payload_hash', v_payload_hash,
    'replayed', false,
    'import_id', v_import.id,
    'revision', v_import.revision,
    'status', v_import.status,
    'rows', v_rows_receipt
  );
  insert into public.bank_reconciliation_operations (
    tenant_id, import_id, operation_key, action, payload_hash, receipt, created_by
  ) values (
    v_tenant_id, v_import.id, trim(p_operation_key), 'create_import',
    v_payload_hash, v_receipt, v_user_id
  );
  return v_receipt;
end;
$$;

revoke all on function public.save_bank_statement_import_v1(
  text, text, text, uuid, jsonb, jsonb
) from public, anon;
grant execute on function public.save_bank_statement_import_v1(
  text, text, text, uuid, jsonb, jsonb
) to authenticated, service_role;

create or replace function public.apply_bank_reconciliation_v1(
  p_import_id uuid,
  p_expected_revision bigint,
  p_operation_key text,
  p_allocations jsonb,
  p_decisions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_import record;
  v_existing record;
  v_payload_hash text;
  v_allocation jsonb;
  v_decision jsonb;
  v_row record;
  v_target jsonb;
  v_target_kind text;
  v_target_id uuid;
  v_status text;
  v_revision bigint;
  v_allocation_count integer;
  v_receipt jsonb;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_import_id is null or p_expected_revision is null or p_expected_revision <= 0
     or p_operation_key is null or length(trim(p_operation_key)) not between 1 and 200
     or coalesce(jsonb_typeof(p_allocations), 'null') <> 'array'
     or coalesce(jsonb_typeof(p_decisions), 'null') <> 'array'
     or jsonb_array_length(p_allocations) > 5000
     or jsonb_array_length(p_decisions) > 5000 then
    raise exception using errcode = '22023', message = 'bank_reconciliation_payload_invalid';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'import_id', p_import_id,
    'expected_revision', p_expected_revision,
    'allocations', p_allocations,
    'decisions', p_decisions
  )::text, 'utf8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':bank-reconciliation', 0
  ));
  select operation.action, operation.payload_hash, operation.receipt
    into v_existing
    from public.bank_reconciliation_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  if found then
    if v_existing.action <> 'apply_review'
       or v_existing.payload_hash <> v_payload_hash then
      raise exception using errcode = 'P0001', message = 'bank_reconciliation_idempotency_conflict';
    end if;
    return v_existing.receipt || jsonb_build_object('replayed', true);
  end if;

  select imported.id, imported.revision, imported.erp_account_id
    into v_import
    from public.bank_statement_imports imported
   where imported.tenant_id = v_tenant_id and imported.id = p_import_id
   for update;
  if not found then
    raise exception using errcode = '42501', message = 'bank_statement_import_not_accessible';
  end if;
  if v_import.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'bank_reconciliation_revision_conflict';
  end if;
  if jsonb_array_length(p_decisions) <> (
    select count(*) from public.bank_statement_rows row where row.import_id = v_import.id
  ) then
    raise exception using errcode = '22023', message = 'bank_reconciliation_decision_coverage_invalid';
  end if;
  if exists (
    select 1
      from jsonb_array_elements(p_decisions) decision
     group by decision->>'row_id'
    having count(*) <> 1
  ) then
    raise exception using errcode = '22023', message = 'bank_reconciliation_decision_duplicate';
  end if;

  delete from public.bank_reconciliation_allocations
   where tenant_id = v_tenant_id and import_id = v_import.id;
  delete from public.bank_reconciliation_row_decisions
   where tenant_id = v_tenant_id and import_id = v_import.id;

  for v_allocation in select value from jsonb_array_elements(p_allocations)
  loop
    if jsonb_typeof(v_allocation) <> 'object'
       or coalesce(v_allocation->>'target_kind', '') not in (
         'sales_payment', 'purchase_payment', 'expense_payment', 'journal_entry'
       )
       or coalesce(v_allocation->>'match_kind', '') not in (
         'direct', 'transbank_estimate', 'manual'
       )
       or coalesce(v_allocation->>'confidence', '') not in ('low', 'medium', 'high')
       or coalesce(v_allocation->>'provider', '') not in (
         'none', 'transbank', 'mercadopago', 'other'
       )
       or coalesce(v_allocation->>'instrument', '') not in (
         'unknown', 'debit', 'credit', 'prepaid'
       )
       or coalesce((v_allocation->>'bank_amount')::numeric, 0) <= 0
       or coalesce((v_allocation->>'target_amount')::numeric, 0) <= 0
       or (
         v_allocation->>'match_kind' = 'direct'
         and abs(
           (v_allocation->>'bank_amount')::numeric
           - (v_allocation->>'target_amount')::numeric
         ) > 1000
       )
       or (
         v_allocation->>'match_kind' = 'transbank_estimate'
         and (v_allocation->>'bank_amount')::numeric
           > (v_allocation->>'target_amount')::numeric
       ) then
      raise exception using errcode = '22023', message = 'bank_reconciliation_allocation_invalid';
    end if;
    select row.id, row.amount, row.direction
      into v_row
      from public.bank_statement_rows row
     where row.tenant_id = v_tenant_id
       and row.import_id = v_import.id
       and row.id = (v_allocation->>'row_id')::uuid;
    if not found or v_row.amount is null then
      raise exception using errcode = '22023', message = 'bank_reconciliation_row_invalid';
    end if;
    v_target_kind := v_allocation->>'target_kind';
    v_target_id := (v_allocation->>'target_id')::uuid;
    v_target := public.bank_reconciliation_target_snapshot(
      v_tenant_id, v_import.erp_account_id, v_target_kind, v_target_id
    );
    if v_target is null then
      raise exception using errcode = '42501', message = 'bank_reconciliation_target_not_accessible';
    end if;
    if v_target->>'direction' <> v_row.direction
       or (v_target->>'amount')::numeric <> (v_allocation->>'target_amount')::numeric
       or coalesce(v_target->>'provider', 'none') <> v_allocation->>'provider'
       or coalesce(v_target->>'instrument', 'unknown') <> v_allocation->>'instrument'
       or (
         v_allocation->>'match_kind' = 'transbank_estimate'
         and coalesce(v_target->>'provider', 'none') <> 'transbank'
       ) then
      raise exception using errcode = '40001', message = 'bank_reconciliation_target_changed';
    end if;
    if exists (
      select 1
      from public.bank_reconciliation_allocations existing
      where existing.tenant_id = v_tenant_id
        and existing.target_kind = v_target_kind
        and existing.target_id = v_target_id
    ) then
      raise exception using errcode = '23505', message = 'bank_reconciliation_target_already_linked';
    end if;
    insert into public.bank_reconciliation_allocations (
      tenant_id, import_id, row_id, target_kind, target_id, bank_amount,
      target_amount, match_kind, confidence, provider, instrument,
      rationale, created_by
    ) values (
      v_tenant_id,
      v_import.id,
      v_row.id,
      v_target_kind,
      v_target_id,
      (v_allocation->>'bank_amount')::numeric,
      (v_allocation->>'target_amount')::numeric,
      v_allocation->>'match_kind',
      v_allocation->>'confidence',
      v_allocation->>'provider',
      v_allocation->>'instrument',
      coalesce(v_allocation->'rationale', '{}'::jsonb),
      v_user_id
    );
  end loop;

  if exists (
    select 1
      from public.bank_reconciliation_allocations allocation
      join public.bank_statement_rows row on row.id = allocation.row_id
     where allocation.import_id = v_import.id
     group by allocation.row_id, row.amount
    having sum(allocation.bank_amount) > row.amount
  ) then
    raise exception using errcode = '23514', message = 'bank_reconciliation_overallocated';
  end if;

  for v_decision in select value from jsonb_array_elements(p_decisions)
  loop
    if jsonb_typeof(v_decision) <> 'object'
       or coalesce(v_decision->>'disposition', '') not in (
         'pending', 'reconciled', 'ignored', 'held'
       ) then
      raise exception using errcode = '22023', message = 'bank_reconciliation_decision_invalid';
    end if;
    select row.id, row.amount, row.direction
      into v_row
      from public.bank_statement_rows row
     where row.tenant_id = v_tenant_id
       and row.import_id = v_import.id
       and row.id = (v_decision->>'row_id')::uuid;
    if not found then
      raise exception using errcode = '22023', message = 'bank_reconciliation_row_invalid';
    end if;
    if v_decision->>'disposition' = 'reconciled' and (
      v_row.amount is null or coalesce((
        select sum(allocation.bank_amount)
          from public.bank_reconciliation_allocations allocation
         where allocation.row_id = v_row.id
      ), 0) <> v_row.amount
    ) then
      raise exception using errcode = '23514', message = 'bank_reconciliation_row_not_fully_allocated';
    end if;
    if v_decision->>'disposition' <> 'reconciled' and exists (
      select 1 from public.bank_reconciliation_allocations allocation
       where allocation.row_id = v_row.id
    ) then
      raise exception using errcode = '23514', message = 'bank_reconciliation_disposition_conflict';
    end if;
    insert into public.bank_reconciliation_row_decisions (
      tenant_id, import_id, row_id, disposition, decided_by
    ) values (
      v_tenant_id, v_import.id, v_row.id,
      v_decision->>'disposition', v_user_id
    );
  end loop;

  select case
    when bool_and(decision.disposition in ('reconciled', 'ignored')) then 'reconciled'
    when bool_or(decision.disposition in ('reconciled', 'ignored', 'held')) then 'partially_reconciled'
    else 'review'
  end into v_status
    from public.bank_reconciliation_row_decisions decision
   where decision.import_id = v_import.id;
  update public.bank_statement_imports imported
     set status = coalesce(v_status, 'review'),
         revision = imported.revision + 1,
         updated_at = now()
   where imported.id = v_import.id
   returning imported.revision into v_revision;
  select count(*) into v_allocation_count
    from public.bank_reconciliation_allocations allocation
   where allocation.import_id = v_import.id;
  v_receipt := jsonb_build_object(
    'operation', 'apply_review',
    'operation_key', trim(p_operation_key),
    'payload_hash', v_payload_hash,
    'replayed', false,
    'import_id', v_import.id,
    'revision', v_revision,
    'status', coalesce(v_status, 'review'),
    'allocation_count', v_allocation_count
  );
  insert into public.bank_reconciliation_operations (
    tenant_id, import_id, operation_key, action, payload_hash, receipt, created_by
  ) values (
    v_tenant_id, v_import.id, trim(p_operation_key), 'apply_review',
    v_payload_hash, v_receipt, v_user_id
  );
  return v_receipt;
end;
$$;

revoke all on function public.apply_bank_reconciliation_v1(
  uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.apply_bank_reconciliation_v1(
  uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;

comment on function public.get_bank_reconciliation_candidates_v1(uuid, date, date) is
  'Read-only accounting candidate projection. Banco de Chile booking dates are evidence windows, never exact event timestamps.';
comment on function public.apply_bank_reconciliation_v1(uuid, bigint, text, jsonb, jsonb) is
  'Persists reviewed evidence links only. It never creates or mutates the linked business operations.';
