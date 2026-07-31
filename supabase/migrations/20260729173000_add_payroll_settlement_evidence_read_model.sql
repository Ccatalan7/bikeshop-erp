-- Payroll settlement-evidence read model plus the beneficiary alias table.
--
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).
-- Recovery: drop the alias table and the evidence RPC; both are additive and
-- hold no source-document content. No data rewrite or backfill occurs.

begin;

-- Optional beneficiary aliases improve candidate generation but never authorize
-- or auto-apply a payroll movement. An alias is unique inside one tenant so a
-- bank description cannot silently identify two employees.
create table if not exists public.payroll_beneficiary_aliases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete cascade,
  employee_id uuid not null,
  alias text not null
    check (
      char_length(btrim(alias)) between 2 and 160
      and alias = btrim(alias)
    ),
  normalized_alias text not null,
  created_by uuid not null default auth.uid()
    references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  updated_at timestamp with time zone not null default statement_timestamp(),
  constraint payroll_beneficiary_aliases_tenant_employee_fkey
    foreign key (tenant_id, employee_id)
    references public.employees(tenant_id, id)
    on delete cascade
);

create unique index if not exists
  ux_payroll_beneficiary_aliases_tenant_alias
  on public.payroll_beneficiary_aliases(
    tenant_id,
    normalized_alias
  );
create index if not exists idx_payroll_beneficiary_aliases_employee
  on public.payroll_beneficiary_aliases(tenant_id, employee_id);

create or replace function public.normalize_payroll_beneficiary_alias()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.normalized_alias :=
    public.normalize_payroll_statement_text(new.alias);
  if new.normalized_alias is null then
    raise exception 'Payroll beneficiary alias has no searchable text'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.normalize_payroll_beneficiary_alias()
  from public, anon, authenticated, service_role;

drop trigger if exists normalize_payroll_beneficiary_alias
  on public.payroll_beneficiary_aliases;
create trigger normalize_payroll_beneficiary_alias
before insert or update on public.payroll_beneficiary_aliases
for each row execute function public.normalize_payroll_beneficiary_alias();

drop trigger if exists set_payroll_beneficiary_aliases_updated_at
  on public.payroll_beneficiary_aliases;
create trigger set_payroll_beneficiary_aliases_updated_at
before update on public.payroll_beneficiary_aliases
for each row execute function public.set_updated_at();

create or replace function public.guard_payroll_beneficiary_alias_update()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.tenant_id is distinct from old.tenant_id
     or new.employee_id is distinct from old.employee_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Payroll beneficiary alias ownership is immutable'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_payroll_beneficiary_alias_update()
  from public, anon, authenticated, service_role;

drop trigger if exists guard_payroll_beneficiary_alias_update
  on public.payroll_beneficiary_aliases;
create trigger guard_payroll_beneficiary_alias_update
before update on public.payroll_beneficiary_aliases
for each row execute function public.guard_payroll_beneficiary_alias_update();

alter table public.payroll_beneficiary_aliases enable row level security;

drop policy if exists payroll_beneficiary_aliases_read_payroll
  on public.payroll_beneficiary_aliases;
create policy payroll_beneficiary_aliases_read_payroll
  on public.payroll_beneficiary_aliases
  for select
  to authenticated
  using (
    tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_payroll(tenant_id)
  );

drop policy if exists payroll_beneficiary_aliases_insert_payroll
  on public.payroll_beneficiary_aliases;
create policy payroll_beneficiary_aliases_insert_payroll
  on public.payroll_beneficiary_aliases
  for insert
  to authenticated
  with check (
    tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_payroll(tenant_id)
    and created_by = auth.uid()
  );

drop policy if exists payroll_beneficiary_aliases_update_payroll
  on public.payroll_beneficiary_aliases;
create policy payroll_beneficiary_aliases_update_payroll
  on public.payroll_beneficiary_aliases
  for update
  to authenticated
  using (
    tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_payroll(tenant_id)
  )
  with check (
    tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_payroll(tenant_id)
  );

drop policy if exists payroll_beneficiary_aliases_delete_payroll
  on public.payroll_beneficiary_aliases;
create policy payroll_beneficiary_aliases_delete_payroll
  on public.payroll_beneficiary_aliases
  for delete
  to authenticated
  using (
    tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_payroll(tenant_id)
  );

revoke all on table public.payroll_beneficiary_aliases
  from public, anon, authenticated, service_role;
-- Write access is born RPC-only: the audited
-- learn_payroll_beneficiary_alias command (next migration) is the sole
-- writer. Granting direct DML here would open a one-migration window where
-- authenticated could mutate aliases without the audited path.
grant select
  on table public.payroll_beneficiary_aliases
  to authenticated;

-- One tenant-authorized snapshot for all visible vouchers. The client derives
-- its aggregate balance from these immutable movement rows, avoiding one
-- request per employee and preserving partial-payment history.
--
-- The observed statement fields below are deliberately bounded to the exact
-- row that funded an applied movement. The projection never returns source
-- files, hashes, account fingerprints, the full OCR payload, beneficiary text,
-- or unrelated statement rows.
drop function if exists
  public.get_payroll_voucher_settlement_evidence(uuid[]);

create or replace function public.get_payroll_voucher_settlement_evidence(
  p_voucher_ids uuid[]
)
returns table (
  voucher_id uuid,
  line_id uuid,
  evidence_id uuid,
  evidence_kind text,
  source text,
  origin_action text,
  amount numeric,
  effective_date timestamp with time zone,
  cash_movement_date timestamp with time zone,
  recorded_at timestamp with time zone,
  payment_method_id uuid,
  payment_method_label text,
  payment_account_id uuid,
  payment_account_label text,
  reference text,
  notes text,
  actor_id uuid,
  actor_name text,
  funding_actor_id uuid,
  funding_actor_name text,
  operation_id uuid,
  operation_key text,
  funding_operation_id uuid,
  funding_operation_key text,
  statement_import_id uuid,
  statement_decision_id uuid,
  statement_row_id uuid,
  advance_id uuid,
  bank_amount numeric,
  variance numeric,
  variance_disposition text,
  manual_confirmation boolean,
  review_reason text,
  statement_transaction_date date,
  statement_description_observed text,
  statement_document_observed text,
  statement_page_number integer,
  statement_source_line_start integer,
  statement_source_line_end integer,
  statement_row_ordinal integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  requested_ids uuid[];
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct requested.id), '{}'::uuid[])
  into requested_ids
  from unnest(coalesce(p_voucher_ids, '{}'::uuid[])) requested(id);

  if cardinality(requested_ids) > 100 then
    raise exception 'Too many payroll vouchers requested'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(requested_ids) requested(id)
    where not exists (
      select 1
      from public.payroll_vouchers voucher
      where voucher.id = requested.id
        and voucher.tenant_id = tenant_id_value
    )
  ) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return query
  with payment_evidence as (
    select
      voucher_line.voucher_id,
      voucher_line.id as line_id,
      payment.id as evidence_id,
      'payment'::text as evidence_kind,
      case
        when statement_allocation.action = 'bank_payment'
          then 'bank_statement'
        when statement_allocation.action = 'cash_payment'
          then 'cash_reconciliation'
        when money_operation.id is not null
          then 'manual'
        else 'legacy'
      end::text as source,
      coalesce(
        statement_allocation.action,
        money_operation.operation_type,
        'legacy_unattributed'
      )::text as origin_action,
      payment.amount::numeric as amount,
      payment.payment_date as effective_date,
      null::timestamp with time zone as cash_movement_date,
      payment.created_at as recorded_at,
      payment.payment_method_id,
      payment_method.name::text as payment_method_label,
      payment.payment_account_id,
      nullif(
        concat_ws(
          ' · ',
          nullif(payment_account.code, ''),
          nullif(payment_account.name, '')
        ),
        ''
      )::text as payment_account_label,
      payment.reference::text,
      payment.notes::text,
      coalesce(
        statement_allocation.applied_by,
        money_operation.created_by
      ) as actor_id,
      public.erp_actor_display_name(
        coalesce(
          statement_allocation.applied_by,
          money_operation.created_by
        ),
        tenant_id_value
      ) as actor_name,
      null::uuid as funding_actor_id,
      null::text as funding_actor_name,
      money_operation.id as operation_id,
      money_operation.operation_key::text,
      null::uuid as funding_operation_id,
      null::text as funding_operation_key,
      statement_allocation.import_id as statement_import_id,
      statement_allocation.decision_id as statement_decision_id,
      statement_allocation.row_id as statement_row_id,
      null::uuid as advance_id,
      statement_allocation.bank_amount::numeric,
      statement_allocation.variance::numeric,
      statement_allocation.variance_disposition::text,
      statement_decision.manual_confirmation,
      statement_decision.reason::text as review_reason,
      statement_row.transaction_date as statement_transaction_date,
      statement_row.description_observed::text
        as statement_description_observed,
      statement_row.document_observed::text
        as statement_document_observed,
      statement_row.page_number as statement_page_number,
      statement_row.source_line_start as statement_source_line_start,
      statement_row.source_line_end as statement_source_line_end,
      statement_row.row_ordinal as statement_row_ordinal
    from public.payroll_voucher_lines voucher_line
    join public.expense_payments payment
      on payment.expense_id = voucher_line.expense_id
     and payment.tenant_id = voucher_line.tenant_id
    left join public.payment_methods payment_method
      on payment_method.id = payment.payment_method_id
     and payment_method.tenant_id = payment.tenant_id
    left join public.accounts payment_account
      on payment_account.id = payment.payment_account_id
     and payment_account.tenant_id = payment.tenant_id
    left join public.payroll_money_operation_movements operation_movement
      on operation_movement.expense_payment_id = payment.id
     and operation_movement.tenant_id = payment.tenant_id
    left join public.payroll_money_operations money_operation
      on money_operation.id = operation_movement.operation_id
     and money_operation.tenant_id = operation_movement.tenant_id
    left join public.payroll_statement_allocations statement_allocation
      on statement_allocation.expense_payment_id = payment.id
     and statement_allocation.tenant_id = payment.tenant_id
    left join public.payroll_statement_decisions statement_decision
      on statement_decision.id = statement_allocation.decision_id
     and statement_decision.tenant_id = statement_allocation.tenant_id
    left join public.payroll_statement_rows statement_row
      on statement_row.id = statement_allocation.row_id
     and statement_row.tenant_id = statement_allocation.tenant_id
     and statement_row.import_id = statement_allocation.import_id
    where voucher_line.tenant_id = tenant_id_value
      and voucher_line.voucher_id = any(requested_ids)
  ),
  advance_evidence as (
    select
      voucher_line.voucher_id,
      voucher_line.id as line_id,
      allocation.id as evidence_id,
      'advance'::text as evidence_kind,
      case
        when statement_allocation.id is not null
          then 'statement_reconciliation'
        when money_operation.id is not null
          then 'manual'
        else 'legacy'
      end::text as source,
      coalesce(
        statement_allocation.action,
        money_operation.operation_type,
        'legacy_unattributed'
      )::text as origin_action,
      allocation.amount::numeric as amount,
      allocation.applied_at as effective_date,
      advance.paid_at as cash_movement_date,
      allocation.created_at as recorded_at,
      advance.payment_method_id,
      payment_method.name::text as payment_method_label,
      advance.payment_account_id,
      nullif(
        concat_ws(
          ' · ',
          nullif(payment_account.code, ''),
          nullif(payment_account.name, '')
        ),
        ''
      )::text as payment_account_label,
      advance.reference::text,
      allocation.notes::text,
      coalesce(
        statement_allocation.applied_by,
        money_operation.created_by,
        allocation.created_by
      ) as actor_id,
      public.erp_actor_display_name(
        coalesce(
          statement_allocation.applied_by,
          money_operation.created_by,
          allocation.created_by
        ),
        tenant_id_value
      ) as actor_name,
      advance.created_by as funding_actor_id,
      public.erp_actor_display_name(
        advance.created_by,
        tenant_id_value
      ) as funding_actor_name,
      money_operation.id as operation_id,
      money_operation.operation_key::text,
      funding_operation.id as funding_operation_id,
      funding_operation.operation_key::text as funding_operation_key,
      statement_allocation.import_id as statement_import_id,
      statement_allocation.decision_id as statement_decision_id,
      statement_allocation.row_id as statement_row_id,
      advance.id as advance_id,
      statement_allocation.bank_amount::numeric,
      statement_allocation.variance::numeric,
      statement_allocation.variance_disposition::text,
      statement_decision.manual_confirmation,
      statement_decision.reason::text as review_reason,
      null::date as statement_transaction_date,
      null::text as statement_description_observed,
      null::text as statement_document_observed,
      null::integer as statement_page_number,
      null::integer as statement_source_line_start,
      null::integer as statement_source_line_end,
      null::integer as statement_row_ordinal
    from public.payroll_voucher_lines voucher_line
    join public.employee_advance_allocations allocation
      on allocation.voucher_line_id = voucher_line.id
     and allocation.tenant_id = voucher_line.tenant_id
    join public.employee_advances advance
      on advance.id = allocation.advance_id
     and advance.tenant_id = allocation.tenant_id
    left join public.payment_methods payment_method
      on payment_method.id = advance.payment_method_id
     and payment_method.tenant_id = advance.tenant_id
    left join public.accounts payment_account
      on payment_account.id = advance.payment_account_id
     and payment_account.tenant_id = advance.tenant_id
    left join public.payroll_money_operation_movements operation_movement
      on operation_movement.advance_allocation_id = allocation.id
     and operation_movement.tenant_id = allocation.tenant_id
    left join public.payroll_money_operations money_operation
      on money_operation.id = operation_movement.operation_id
     and money_operation.tenant_id = operation_movement.tenant_id
    left join public.payroll_money_operations funding_operation
      on funding_operation.employee_advance_id = advance.id
     and funding_operation.tenant_id = advance.tenant_id
     and funding_operation.operation_type = 'employee_advance'
    left join public.payroll_statement_allocations statement_allocation
      on statement_allocation.employee_advance_allocation_id = allocation.id
     and statement_allocation.tenant_id = allocation.tenant_id
    left join public.payroll_statement_decisions statement_decision
      on statement_decision.id = statement_allocation.decision_id
     and statement_decision.tenant_id = statement_allocation.tenant_id
    where voucher_line.tenant_id = tenant_id_value
      and voucher_line.voucher_id = any(requested_ids)
  )
  select evidence.*
  from (
    select * from payment_evidence
    union all
    select * from advance_evidence
  ) evidence
  order by
    evidence.voucher_id,
    evidence.line_id,
    evidence.effective_date,
    evidence.evidence_id;
end;
$$;

revoke all on function public.get_payroll_voucher_settlement_evidence(uuid[])
  from public, anon, authenticated, service_role;
grant execute
  on function public.get_payroll_voucher_settlement_evidence(uuid[])
  to authenticated;

comment on table public.payroll_beneficiary_aliases is
  'Tenant-scoped alternate beneficiary names used only to generate payroll statement candidates. They never authorize or auto-apply money.';
comment on function public.get_payroll_voucher_settlement_evidence(uuid[]) is
  'Returns one tenant-authorized, line-level evidence snapshot for direct payments and advance allocations, including only the applied bank row observation and its page/line locator; source files, complete OCR payloads, beneficiary text, account fingerprints, unrelated rows, and auth metadata remain private.';

commit;
