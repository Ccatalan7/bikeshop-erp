begin;

-- Deployment status: local/off-production candidate; not deployed.
--
-- A reimbursement may be delivered in the same money movement as payroll
-- without being salary.  `included_in_payroll_total` preserves the original
-- voucher-line obligation as the settlement ceiling, settles part of that
-- obligation through the reimbursement, and posts an explicit reclassification
-- (debit salary payable / credit salary expense).  The reimbursement keeps its
-- own expense, liability and payment, so the ledger shows the real business
-- expense without posting the same cash twice.
--
-- Forward behavior: additive evidence/operation tables, a V2 workspace RPC,
-- and settlement projections that include the immutable linked amount.
-- Existing V1 payloads remain `additional` by definition and are untouched.
-- Recovery: stop calling V2.  Posted rows are immutable accounting evidence
-- and require a future compensating reversal; they must never be deleted.
-- Lock risk: brief additive DDL locks.  The command takes the existing
-- workspace lock, then the tenant payroll lock, then voucher/line locks in UUID
-- order.  There is no backfill or production data rewrite.

create table if not exists
  public.payroll_payment_workspace_concept_dispositions (
    id uuid primary key,
    tenant_id uuid not null
      references public.tenants(id) on delete restrict,
    workspace_id uuid not null,
    concept_id uuid not null,
    target_id uuid,
    disposition text not null
      check (disposition in ('additional', 'included_in_payroll_total')),
    voucher_id uuid references public.payroll_vouchers(id) on delete restrict,
    voucher_line_id uuid
      references public.payroll_voucher_lines(id) on delete restrict,
    expected_reconciliation_version bigint
      check (
        expected_reconciliation_version is null
        or expected_reconciliation_version >= 0
      ),
    amount numeric(14,2) not null check (amount > 0),
    result_expense_id uuid not null
      references public.expenses(id) on delete restrict,
    reclassification_journal_entry_id uuid unique
      references public.journal_entries(id) on delete restrict,
    effective_at timestamp with time zone not null,
    result_receipt jsonb not null
      check (jsonb_typeof(result_receipt) = 'object'),
    applied_by uuid not null references auth.users(id),
    applied_at timestamp with time zone not null default statement_timestamp(),
    created_at timestamp with time zone not null default statement_timestamp(),
    unique (tenant_id, id),
    unique (workspace_id, concept_id),
    unique (workspace_id, result_expense_id),
    foreign key (tenant_id, workspace_id)
      references public.payroll_payment_workspaces(tenant_id, id)
      on delete restrict,
    check (
      (
        disposition = 'additional'
        and target_id is null
        and voucher_id is null
        and voucher_line_id is null
        and expected_reconciliation_version is null
        and reclassification_journal_entry_id is null
      )
      or (
        disposition = 'included_in_payroll_total'
        and target_id is not null
        and voucher_id is not null
        and voucher_line_id is not null
        and expected_reconciliation_version is not null
        and reclassification_journal_entry_id is not null
      )
    )
  );

create index if not exists
  idx_payroll_workspace_concept_dispositions_line
  on public.payroll_payment_workspace_concept_dispositions(
    tenant_id,
    voucher_line_id
  )
  where disposition = 'included_in_payroll_total';

create table if not exists
  public.payroll_payment_workspace_v2_operations (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null
      references public.tenants(id) on delete restrict,
    workspace_id uuid not null,
    operation_key text not null
      check (operation_key ~ '^[A-Za-z0-9:_-]{8,200}$'),
    payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
    receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
    created_by uuid not null references auth.users(id),
    created_at timestamp with time zone not null default statement_timestamp(),
    unique (tenant_id, operation_key),
    unique (tenant_id, workspace_id),
    foreign key (tenant_id, workspace_id)
      references public.payroll_payment_workspaces(tenant_id, id)
      on delete restrict
  );

alter table public.payroll_payment_workspace_concept_dispositions
  enable row level security;
alter table public.payroll_payment_workspace_v2_operations
  enable row level security;

drop policy if exists payroll_workspace_concept_dispositions_read
  on public.payroll_payment_workspace_concept_dispositions;
create policy payroll_workspace_concept_dispositions_read
  on public.payroll_payment_workspace_concept_dispositions
  for select to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

revoke all on table
  public.payroll_payment_workspace_concept_dispositions
  from public, anon, authenticated, service_role;
revoke all on table public.payroll_payment_workspace_v2_operations
  from public, anon, authenticated, service_role;
grant select on table
  public.payroll_payment_workspace_concept_dispositions
  to authenticated, service_role;

create or replace function
  public.guard_payroll_workspace_concept_reclassification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  entry_id_value uuid;
begin
  if tg_table_name = 'payroll_payment_workspace_concept_dispositions' then
    raise exception 'payroll_workspace_concept_disposition_is_immutable'
      using errcode = '55000';
  end if;

  if tg_table_name = 'journal_entries' then
    if tg_op = 'DELETE' then
      entry_id_value := old.id;
    else
      entry_id_value := new.id;
    end if;
  elsif tg_op = 'DELETE' then
    entry_id_value := old.entry_id;
  else
    entry_id_value := new.entry_id;
  end if;

  if exists (
    select 1
    from public.payroll_payment_workspace_concept_dispositions disposition
    where disposition.reclassification_journal_entry_id = entry_id_value
  ) then
    raise exception 'payroll_workspace_reclassification_is_immutable'
      using errcode = '55000';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function
  public.guard_payroll_workspace_concept_reclassification()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_payroll_workspace_concept_disposition_immutable
  on public.payroll_payment_workspace_concept_dispositions;
create trigger trg_payroll_workspace_concept_disposition_immutable
  before update or delete
  on public.payroll_payment_workspace_concept_dispositions
  for each row execute function
    public.guard_payroll_workspace_concept_reclassification();

drop trigger if exists trg_payroll_workspace_reclassification_entry_immutable
  on public.journal_entries;
create trigger trg_payroll_workspace_reclassification_entry_immutable
  before update or delete on public.journal_entries
  for each row execute function
    public.guard_payroll_workspace_concept_reclassification();

drop trigger if exists trg_payroll_workspace_reclassification_line_immutable
  on public.journal_lines;
create trigger trg_payroll_workspace_reclassification_line_immutable
  before insert or update or delete on public.journal_lines
  for each row execute function
    public.guard_payroll_workspace_concept_reclassification();

-- A linked included concept is an allocation of the payroll-line obligation,
-- just like an employee advance, even though its cash movement belongs to the
-- separately classified reimbursement expense.
create or replace function
  public.get_payroll_voucher_line_settlements_internal(p_voucher_id uuid)
returns table (
  line_id uuid,
  cash_paid numeric(14,2),
  advances_applied numeric(14,2),
  settled_amount numeric(14,2),
  balance numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  select line.id,
    coalesce((
      select sum(payment.amount)
      from public.expense_payments payment
      where payment.expense_id = line.expense_id
    ), 0)::numeric(14,2),
    coalesce((
      select sum(allocation.amount)
      from public.employee_advance_allocations allocation
      where allocation.voucher_line_id = line.id
    ), 0)::numeric(14,2),
    least(
      line.total_amount,
      coalesce((
        select sum(payment.amount)
        from public.expense_payments payment
        where payment.expense_id = line.expense_id
      ), 0)
      + coalesce((
        select sum(allocation.amount)
        from public.employee_advance_allocations allocation
        where allocation.voucher_line_id = line.id
      ), 0)
      + coalesce((
        select sum(disposition.amount)
        from public.payroll_payment_workspace_concept_dispositions disposition
        where disposition.voucher_line_id = line.id
          and disposition.disposition = 'included_in_payroll_total'
      ), 0)
    )::numeric(14,2),
    greatest(
      line.total_amount
      - coalesce((
        select sum(payment.amount)
        from public.expense_payments payment
        where payment.expense_id = line.expense_id
      ), 0)
      - coalesce((
        select sum(allocation.amount)
        from public.employee_advance_allocations allocation
        where allocation.voucher_line_id = line.id
      ), 0)
      - coalesce((
        select sum(disposition.amount)
        from public.payroll_payment_workspace_concept_dispositions disposition
        where disposition.voucher_line_id = line.id
          and disposition.disposition = 'included_in_payroll_total'
      ), 0),
      0
    )::numeric(14,2)
  from public.payroll_voucher_lines line
  where line.voucher_id = p_voucher_id
    and line.tenant_id = public.user_tenant_id();
$$;

revoke all on function
  public.get_payroll_voucher_line_settlements_internal(uuid)
  from public, anon, authenticated, service_role;
grant execute on function
  public.get_payroll_voucher_line_settlements_internal(uuid)
  to service_role;

create or replace function public.refresh_payroll_voucher_status(
  p_voucher_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  due_value numeric(14,2);
  settled_value numeric(14,2);
  latest_value timestamp with time zone;
  status_value text;
begin
  select
    coalesce(sum(line.total_amount), 0),
    coalesce(sum(
      coalesce((
        select sum(payment.amount)
        from public.expense_payments payment
        where payment.expense_id = line.expense_id
      ), 0)
      + coalesce((
        select sum(allocation.amount)
        from public.employee_advance_allocations allocation
        where allocation.voucher_line_id = line.id
      ), 0)
      + coalesce((
        select sum(disposition.amount)
        from public.payroll_payment_workspace_concept_dispositions disposition
        where disposition.voucher_line_id = line.id
          and disposition.disposition = 'included_in_payroll_total'
      ), 0)
    ), 0),
    max(greatest(
      (select max(payment.payment_date)
       from public.expense_payments payment
       where payment.expense_id = line.expense_id),
      (select max(allocation.applied_at)
       from public.employee_advance_allocations allocation
       where allocation.voucher_line_id = line.id),
      (select max(disposition.effective_at)
       from public.payroll_payment_workspace_concept_dispositions disposition
       where disposition.voucher_line_id = line.id
         and disposition.disposition = 'included_in_payroll_total')
    ))
  into due_value, settled_value, latest_value
  from public.payroll_voucher_lines line
  where line.voucher_id = p_voucher_id
    and line.is_included is true;

  status_value := case
    when due_value > 0 and settled_value + 0.01 >= due_value then 'paid'
    when settled_value > 0 then 'partial'
    else 'confirmed'
  end;

  update public.payroll_vouchers voucher
  set status = status_value,
      paid_at = case
        when status_value = 'paid' then coalesce(latest_value, now())
        else null
      end,
      paid_by = case
        when settled_value > 0 then coalesce(auth.uid(), voucher.paid_by)
        else null
      end,
      updated_at = now()
  where voucher.id = p_voucher_id
    and voucher.tenant_id = public.user_tenant_id();

  return status_value;
end;
$$;

revoke all on function public.refresh_payroll_voucher_status(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.refresh_payroll_voucher_status(uuid)
  to service_role;

-- Expense trace completion must use the same effective-payment authority as
-- the salary projection. Otherwise a later totals-only update would reject a
-- valid included allocation even though the immutable disposition exists.
create or replace function public.complete_expense_accounting_operation(
  p_operation_id uuid,
  p_tenant_id uuid,
  p_expense_id uuid,
  p_payment_id uuid default null,
  p_expected_accrual_journals integer default null,
  p_expected_payment_journals integer default null,
  p_require_accrual_operation_link boolean default false,
  p_require_payment_operation_link boolean default false,
  p_expense_deleted boolean default false,
  p_expense_number text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
  v_expense_found boolean := false;
  v_expense_snapshot jsonb;
  v_line_subtotal numeric(14,2) := 0;
  v_line_tax numeric(14,2) := 0;
  v_line_total numeric(14,2) := 0;
  v_cash_payment_total numeric(14,2) := 0;
  v_advance_allocation_total numeric(14,2) := 0;
  v_included_concept_total numeric(14,2) := 0;
  v_payment_total numeric(14,2) := 0;
  v_effective_paid numeric(14,2) := 0;
  v_expected_balance numeric(14,2) := 0;
  v_header_mismatches integer := 0;
  v_accrual_journal_count integer := 0;
  v_payment_journal_count integer := 0;
  v_unbalanced_journal_count integer := 0;
  v_accrual_link_mismatches integer := 0;
  v_payment_link_mismatches integer := 0;
  v_stock_movement_count integer := 0;
  v_expected_accrual integer := 0;
  v_expected_payment integer := 0;
begin
  if not exists (
    select 1
    from public.inventory_accounting_operations operation
    where operation.id = p_operation_id
      and operation.tenant_id = p_tenant_id
  ) then
    raise exception 'Expense operation % does not belong to tenant %',
      p_operation_id,
      p_tenant_id
      using errcode = 'foreign_key_violation';
  end if;

  if p_expense_id is not null then
    select *
    into v_expense
    from public.expenses expense
    where expense.id = p_expense_id
      and expense.tenant_id = p_tenant_id;
    v_expense_found := found;
  end if;

  if v_expense_found then
    v_expense_snapshot :=
      public.expense_accounting_trace_snapshot(to_jsonb(v_expense));
    p_expense_number := coalesce(
      p_expense_number,
      v_expense.expense_number
    );

    select
      round(coalesce(sum(line.subtotal), 0), 2),
      round(coalesce(sum(line.tax_amount), 0), 2),
      round(coalesce(sum(line.total), 0), 2)
    into v_line_subtotal, v_line_tax, v_line_total
    from public.expense_lines line
    where line.expense_id = v_expense.id
      and line.tenant_id = v_expense.tenant_id;

    select round(coalesce(sum(payment.amount), 0), 2)
    into v_cash_payment_total
    from public.expense_payments payment
    where payment.expense_id = v_expense.id
      and payment.tenant_id = v_expense.tenant_id;

    select round(coalesce(sum(allocation.amount), 0), 2)
    into v_advance_allocation_total
    from public.employee_advance_allocations allocation
    join public.payroll_voucher_lines voucher_line
      on voucher_line.id = allocation.voucher_line_id
     and voucher_line.tenant_id = allocation.tenant_id
    where voucher_line.expense_id = v_expense.id
      and voucher_line.tenant_id = v_expense.tenant_id
      and allocation.tenant_id = v_expense.tenant_id;

    select round(coalesce(sum(disposition.amount), 0), 2)
    into v_included_concept_total
    from public.payroll_payment_workspace_concept_dispositions disposition
    join public.payroll_voucher_lines voucher_line
      on voucher_line.id = disposition.voucher_line_id
     and voucher_line.tenant_id = disposition.tenant_id
    where voucher_line.expense_id = v_expense.id
      and voucher_line.tenant_id = v_expense.tenant_id
      and disposition.tenant_id = v_expense.tenant_id
      and disposition.disposition = 'included_in_payroll_total';

    v_payment_total := round(
      v_cash_payment_total + v_advance_allocation_total
        + v_included_concept_total,
      2
    );

    v_effective_paid := case
      when v_payment_total = 0
       and lower(coalesce(v_expense.payment_status, 'pending')) = 'paid'
       and v_expense.payment_method_id is not null
       and round(coalesce(v_expense.total_amount, 0), 2) > 0
        then round(coalesce(v_expense.total_amount, 0), 2)
      else v_payment_total
    end;
    v_expected_balance := greatest(
      round(coalesce(v_expense.total_amount, 0), 2) - v_effective_paid,
      0
    );

    v_header_mismatches :=
      case
        when round(coalesce(v_expense.subtotal, 0), 2) <> v_line_subtotal
          then 1 else 0
      end
      + case
        when round(coalesce(v_expense.tax_amount, 0), 2) <> v_line_tax
          then 1 else 0
      end
      + case
        when round(coalesce(v_expense.total_amount, 0), 2) <> v_line_total
          then 1 else 0
      end
      + case
        when round(coalesce(v_expense.amount_paid, 0), 2) <> v_effective_paid
          then 1 else 0
      end
      + case
        when round(coalesce(v_expense.balance, 0), 2) <> v_expected_balance
          then 1 else 0
      end;

    v_expected_accrual := coalesce(
      p_expected_accrual_journals,
      case
        when lower(coalesce(v_expense.posting_status, 'draft')) = 'posted'
         and round(coalesce(v_expense.total_amount, 0), 2) <> 0 then 1
        else 0
      end
    );
  elsif p_expense_id is not null and not p_expense_deleted then
    raise exception 'Expense % disappeared before trace completion',
      p_expense_id
      using errcode = 'foreign_key_violation';
  else
    v_expected_accrual := coalesce(p_expected_accrual_journals, 0);
    if p_expense_number is null and p_expense_id is not null then
      select operation.before_snapshot->>'expense_number'
      into p_expense_number
      from public.inventory_accounting_operations operation
      where operation.id = p_operation_id;
    end if;
  end if;

  select count(*)::integer
  into v_accrual_journal_count
  from public.journal_entries entry
  where entry.tenant_id = p_tenant_id
    and entry.source_module = 'expenses'
    and (
      -- Expense journal UUID identity is authoritative; text references may
      -- belong to preserved journals for deleted legacy expenses.
      (p_expense_id is not null and entry.source_document_id = p_expense_id)
      or (
        p_expense_id is null
        and entry.source_reference = p_expense_number
      )
    );

  if p_payment_id is not null then
    if p_expected_payment_journals is null then
      select case
        when payment.id is not null
         and round(coalesce(payment.amount, 0), 2) <> 0
         and lower(coalesce(expense.posting_status, 'draft')) = 'posted' then 1
        else 0
      end
      into v_expected_payment
      from (select 1) seed
      left join public.expense_payments payment
        on payment.id = p_payment_id
       and payment.tenant_id = p_tenant_id
      left join public.expenses expense
        on expense.id = payment.expense_id
       and expense.tenant_id = payment.tenant_id;
      v_expected_payment := coalesce(v_expected_payment, 0);
    else
      v_expected_payment := p_expected_payment_journals;
    end if;

    select count(*)::integer
    into v_payment_journal_count
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'expense_payments'
      and (
        entry.source_reference = p_payment_id::text
        or entry.source_document_id = p_payment_id
      );
  end if;

  if p_require_accrual_operation_link and v_expected_accrual > 0 then
    select count(*)::integer
    into v_accrual_link_mismatches
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'expenses'
      and (
        -- Expense journal UUID identity is authoritative; text references may
        -- belong to preserved journals for deleted legacy expenses.
        (p_expense_id is not null and entry.source_document_id = p_expense_id)
        or (
          p_expense_id is null
          and entry.source_reference = p_expense_number
        )
      )
      and entry.operation_id is distinct from p_operation_id;
  end if;

  if p_require_payment_operation_link and v_expected_payment > 0 then
    select count(*)::integer
    into v_payment_link_mismatches
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'expense_payments'
      and (
        entry.source_reference = p_payment_id::text
        or entry.source_document_id = p_payment_id
      )
      and entry.operation_id is distinct from p_operation_id;
  end if;

  select count(*)::integer
  into v_unbalanced_journal_count
  from (
    select entry.id
    from public.journal_entries entry
    left join public.journal_lines line
      on line.entry_id = entry.id
     and line.tenant_id = entry.tenant_id
    where entry.tenant_id = p_tenant_id
      and (
        (
          entry.source_module = 'expenses'
          and (
            -- Expense journal UUID identity is authoritative; text references
            -- may belong to preserved journals for deleted legacy expenses.
            (
              p_expense_id is not null
              and entry.source_document_id = p_expense_id
            )
            or (
              p_expense_id is null
              and entry.source_reference = p_expense_number
            )
          )
        )
        or (
          p_payment_id is not null
          and entry.source_module = 'expense_payments'
          and (
            entry.source_reference = p_payment_id::text
            or entry.source_document_id = p_payment_id
          )
        )
      )
    group by entry.id
    having round(coalesce(sum(line.debit_amount), 0), 2)
        <> round(coalesce(sum(line.credit_amount), 0), 2)
       or round(coalesce(entry.total_debit, 0), 2)
        <> round(coalesce(sum(line.debit_amount), 0), 2)
       or round(coalesce(entry.total_credit, 0), 2)
        <> round(coalesce(sum(line.credit_amount), 0), 2)
  ) broken;

  select count(*)::integer
  into v_stock_movement_count
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id
    and movement.operation_id = p_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    p_operation_id,
    'source_snapshotted',
    'completed',
    case when p_payment_id is null then 'expense' else 'expense_payment' end,
    coalesce(p_payment_id, p_expense_id),
    jsonb_build_object(
      'expense_after', v_expense_snapshot,
      'line_subtotal', v_line_subtotal,
      'line_tax', v_line_tax,
      'line_total', v_line_total,
      'payment_total', v_payment_total,
      'cash_payment_total', v_cash_payment_total,
      'advance_allocation_total', v_advance_allocation_total,
      'included_concept_total', v_included_concept_total
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    p_operation_id,
    'accounting_planned',
    'completed',
    case when p_payment_id is null then 'expense' else 'expense_payment' end,
    coalesce(p_payment_id, p_expense_id),
    jsonb_build_object(
      'expected_accrual_journals', v_expected_accrual,
      'actual_accrual_journals', v_accrual_journal_count,
      'expected_payment_journals', v_expected_payment,
      'actual_payment_journals', v_payment_journal_count,
      'stock_effect', 'none'
    )
  );

  if v_header_mismatches <> 0
     or v_accrual_journal_count <> v_expected_accrual
     or v_payment_journal_count <> v_expected_payment
     or v_unbalanced_journal_count <> 0
     or v_accrual_link_mismatches <> 0
     or v_payment_link_mismatches <> 0
     or v_stock_movement_count <> 0 then
    raise exception
      'Expense trace invariant failed for operation % (header %, accrual %/%, payment %/%, unbalanced %, accrual link %, payment link %, stock %)',
      p_operation_id,
      v_header_mismatches,
      v_accrual_journal_count,
      v_expected_accrual,
      v_payment_journal_count,
      v_expected_payment,
      v_unbalanced_journal_count,
      v_accrual_link_mismatches,
      v_payment_link_mismatches,
      v_stock_movement_count
      using errcode = 'check_violation';
  end if;

  update public.inventory_accounting_operations operation
  set context = operation.context || jsonb_build_object(
        'expense_after', v_expense_snapshot,
        'accrual_journal_count', v_accrual_journal_count,
        'payment_journal_count', v_payment_journal_count,
        'stock_movement_count', v_stock_movement_count
      )
  where operation.id = p_operation_id
    and operation.tenant_id = p_tenant_id;

  perform public.complete_inventory_accounting_operation(
    p_operation_id,
    p_tenant_id,
    jsonb_build_object(
      'expense_id', p_expense_id,
      'payment_id', p_payment_id,
      'expense_deleted', p_expense_deleted,
      'accrual_journal_count', v_accrual_journal_count,
      'payment_journal_count', v_payment_journal_count,
      'stock_movement_count', v_stock_movement_count,
      'header_mismatches', v_header_mismatches
    )
  );

  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);
exception
  when others then
    perform set_config('app.inventory_operation_id', '', true);
    perform set_config('app.inventory_source_document_type', '', true);
    perform set_config('app.inventory_source_document_id', '', true);
    perform set_config('app.inventory_source_channel', '', true);
    raise;
end;
$$;

revoke all on function public.complete_expense_accounting_operation(
  uuid, uuid, uuid, uuid, integer, integer, boolean, boolean, boolean, text
) from public, anon, authenticated, service_role;

comment on function public.complete_expense_accounting_operation(
  uuid, uuid, uuid, uuid, integer, integer, boolean, boolean, boolean, text
) is
  'Validates expense totals against cash, advances and immutable included payroll concepts, then completes the accounting trace.';


-- Keep the salary expense projection consistent with the settlement ledger.
-- The expense retains the voucher's gross obligation; amount_paid/balance also
-- recognize the immutable included-concept allocation.
create or replace function
  public.recalculate_expense_totals_owner_only(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  expense_row record;
  subtotal_value numeric(14,2) := 0;
  tax_value numeric(14,2) := 0;
  total_value numeric(14,2) := 0;
  cash_paid_value numeric(14,2) := 0;
  allocated_value numeric(14,2) := 0;
  paid_value numeric(14,2) := 0;
  latest_payment_value timestamp with time zone;
  payment_method_count_value integer := 0;
  payment_account_count_value integer := 0;
  single_payment_method_id_value uuid;
  single_payment_account_id_value uuid;
  category_id_value uuid;
  line_account_id_value uuid;
  line_account_code_value text;
  line_account_name_value text;
  category_name_value text;
  category_description_value text;
  prior_payment_status_value text;
  new_payment_status_value text;
  is_payroll_value boolean := false;
begin
  if p_expense_id is null then
    return;
  end if;

  select expense.id, expense.tenant_id, expense.category_id,
    expense.issue_date,
    lower(coalesce(expense.payment_status, 'pending')) as payment_status,
    lower(coalesce(expense.posting_status, 'draft')) as posting_status,
    expense.paid_at, expense.payment_method_id, expense.payment_account_id,
    (
      expense.notes like 'Pago de salario%'
      or expense.notes like 'Salario:%'
      or expense.reference like 'Semana %'
    ) as is_payroll
  into expense_row
  from public.expenses expense
  where expense.id = p_expense_id
  for update;

  if not found then
    return;
  end if;
  is_payroll_value := coalesce(expense_row.is_payroll, false);

  select coalesce(sum(line.subtotal), 0),
    coalesce(sum(line.tax_amount), 0),
    coalesce(sum(line.total), 0)
  into subtotal_value, tax_value, total_value
  from public.expense_lines line
  where line.expense_id = p_expense_id;

  select coalesce(sum(payment.amount), 0), max(payment.payment_date)
  into cash_paid_value, latest_payment_value
  from public.expense_payments payment
  where payment.expense_id = p_expense_id;

  select coalesce(sum(allocation.amount), 0),
    greatest(latest_payment_value, max(allocation.applied_at))
  into allocated_value, latest_payment_value
  from public.employee_advance_allocations allocation
  join public.payroll_voucher_lines voucher_line
    on voucher_line.id = allocation.voucher_line_id
  where voucher_line.expense_id = p_expense_id;

  select allocated_value + coalesce(sum(disposition.amount), 0),
    greatest(latest_payment_value, max(disposition.effective_at))
  into allocated_value, latest_payment_value
  from public.payroll_payment_workspace_concept_dispositions disposition
  join public.payroll_voucher_lines voucher_line
    on voucher_line.id = disposition.voucher_line_id
  where voucher_line.expense_id = p_expense_id
    and disposition.disposition = 'included_in_payroll_total';

  paid_value := cash_paid_value + allocated_value;

  if cash_paid_value > 0 then
    select count(distinct payment.payment_method_id),
      (array_agg(distinct payment.payment_method_id))[1]
    into payment_method_count_value, single_payment_method_id_value
    from public.expense_payments payment
    where payment.expense_id = p_expense_id
      and payment.amount > 0
      and payment.payment_method_id is not null;

    select count(distinct payment.payment_account_id),
      (array_agg(distinct payment.payment_account_id))[1]
    into payment_account_count_value, single_payment_account_id_value
    from public.expense_payments payment
    where payment.expense_id = p_expense_id
      and payment.amount > 0
      and payment.payment_account_id is not null;
  end if;

  prior_payment_status_value := expense_row.payment_status;
  category_id_value := expense_row.category_id;
  if category_id_value is null then
    select line.account_id, line.account_code, line.account_name
    into line_account_id_value, line_account_code_value,
      line_account_name_value
    from public.expense_lines line
    where line.expense_id = p_expense_id
    order by line.line_index, line.created_at
    limit 1;

    if line_account_id_value is not null then
      category_name_value := public.get_expense_category_name_for_account(
        line_account_code_value,
        line_account_name_value
      );
      category_description_value := coalesce(
        line_account_name_value,
        category_name_value
      );
      category_id_value := public.ensure_expense_category(
        expense_row.tenant_id,
        category_name_value,
        category_description_value,
        line_account_id_value
      );
    end if;
  end if;

  if not is_payroll_value
     and prior_payment_status_value = 'paid'
     and expense_row.payment_method_id is not null
     and paid_value = 0
     and total_value > 0 then
    new_payment_status_value := 'paid';
    paid_value := total_value;
  elsif total_value = 0 then
    new_payment_status_value := prior_payment_status_value;
  elsif paid_value <= 0 then
    new_payment_status_value := case
      when prior_payment_status_value = 'scheduled' then 'scheduled'
      else 'pending'
    end;
  elsif paid_value + 0.01 < total_value then
    new_payment_status_value := 'partial';
  else
    new_payment_status_value := 'paid';
  end if;

  update public.expenses expense
  set subtotal = subtotal_value,
      tax_amount = tax_value,
      total_amount = total_value,
      amount_paid = paid_value,
      balance = greatest(total_value - paid_value, 0),
      category_id = coalesce(expense.category_id, category_id_value),
      payment_method_id = case
        when payment_method_count_value = 1
          and expense.payment_method_id is null
          then single_payment_method_id_value
        else expense.payment_method_id
      end,
      payment_account_id = case
        when payment_account_count_value = 1
          and expense.payment_account_id is null
          then single_payment_account_id_value
        else expense.payment_account_id
      end,
      payment_status = case
        when expense_row.posting_status = 'void' then expense.payment_status
        when prior_payment_status_value = 'void' then 'void'
        else new_payment_status_value
      end,
      paid_at = case
        when expense_row.posting_status <> 'void'
          and total_value > 0
          and paid_value + 0.01 >= total_value
          then coalesce(
            latest_payment_value,
            expense.paid_at,
            expense.issue_date,
            now()
          )
        when new_payment_status_value <> 'paid' then null
        else expense.paid_at
      end,
      updated_at = now()
  where expense.id = p_expense_id;
end;
$$;

revoke all on function
  public.recalculate_expense_totals_owner_only(uuid)
  from public, anon, authenticated, service_role;

-- Include immutable concept allocations in the hard line-balance guard.  This
-- preserves safety for later manual/API payments even if their own preflight
-- predates this disposition type.
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
  original_row public.expense_payments%rowtype;
  settled_value numeric(14,2);
  audited_reversal boolean := false;
begin
  select voucher_line.id, voucher_line.tenant_id,
    voucher_line.voucher_id, voucher_line.total_amount
  into line_row
  from public.payroll_voucher_lines voucher_line
  where voucher_line.expense_id = expense_id_value;

  if not found then
    if tg_op <> 'DELETE'
       and (
         new.reversal_of_id is not null
         or new.reversal_reason is not null
         or new.amount < 0
       ) then
      raise exception 'payroll_reversal_requires_payroll_expense'
        using errcode = '23514';
    end if;
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

  audited_reversal := exists (
    select 1
    from public.payroll_money_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.tenant_id = tenant_id_value
      and command_context.command = 'audited_reversal'
      and command_context.actor_id = auth.uid()
  );

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
         and command_context.command in ('manual_payment', 'audited_reversal')
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_money_operation_movements movement
       where movement.expense_payment_id = old.id
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using errcode = '55000',
        detail = 'Use the audited idempotent reversal command';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_statement_allocations allocation
       where allocation.expense_payment_id = old.id
     ) then
    raise exception 'payroll_reconciled_payment_is_immutable'
      using errcode = '55000',
        detail = 'Use the audited reconciliation reversal command';
  end if;

  if tg_op = 'UPDATE'
     and (
       old.reversal_of_id is distinct from new.reversal_of_id
       or old.reversal_reason is distinct from new.reversal_reason
     ) then
    raise exception 'payroll_payment_reversal_identity_is_immutable'
      using errcode = '55000';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'legacy_reversal'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(tenant_id_value::text || ':payroll-settlement', 0)
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

  if tg_op = 'INSERT' and new.reversal_of_id is not null then
    if not audited_reversal then
      raise exception 'payroll_money_command_required'
        using errcode = '42501';
    end if;

    select payment.*
    into original_row
    from public.expense_payments payment
    where payment.id = new.reversal_of_id
      and payment.tenant_id = tenant_id_value
    for update;

    if not found
       or original_row.expense_id <> new.expense_id
       or original_row.reversal_of_id is not null
       or original_row.amount <= 0
       or new.amount <> -original_row.amount
       or new.payment_method_id is distinct from
          original_row.payment_method_id
       or new.payment_account_id is distinct from
          original_row.payment_account_id
       or exists (
         select 1
         from public.expense_payments reversal
         where reversal.tenant_id = tenant_id_value
           and reversal.reversal_of_id = original_row.id
       ) then
      raise exception 'payroll_payment_reversal_invalid_original'
        using errcode = '23514';
    end if;
  elsif tg_op <> 'DELETE' then
    select
      coalesce((
        select sum(payment.amount)
        from public.expense_payments payment
        where payment.expense_id = expense_id_value
          and payment.id is distinct from payment_id_value
      ), 0)
      + coalesce((
        select sum(allocation.amount)
        from public.employee_advance_allocations allocation
        where allocation.voucher_line_id = line_row.id
      ), 0)
      + coalesce((
        select sum(disposition.amount)
        from public.payroll_payment_workspace_concept_dispositions disposition
        where disposition.voucher_line_id = line_row.id
          and disposition.disposition = 'included_in_payroll_total'
      ), 0)
    into settled_value;

    if new.amount <= 0
       or new.reversal_reason is not null
       or settled_value + new.amount > line_row.total_amount + 0.01 then
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

create or replace function public.apply_payroll_payment_workspace_v2(
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
  concepts_value jsonb := coalesce(
    p_payload->'additional_concepts',
    '[]'::jsonb
  );
  salary_targets_value jsonb := coalesce(
    p_payload->'salary_targets',
    '[]'::jsonb
  );
  payload_hash_value text;
  existing_operation public.payroll_payment_workspace_v2_operations%rowtype;
  concept_element record;
  target_element record;
  concept_value jsonb;
  target_value jsonb;
  concept_id_value uuid;
  target_id_value uuid;
  disposition_value text;
  beneficiary_employee_id_value uuid;
  voucher_id_value uuid;
  voucher_line_id_value uuid;
  expected_version_value bigint;
  amount_value numeric(14,2);
  legacy_concepts_value jsonb := '[]'::jsonb;
  legacy_targets_value jsonb := '[]'::jsonb;
  legacy_payload_value jsonb;
  legacy_receipt_value jsonb;
  result_expense_id_value uuid;
  effective_at_value timestamp with time zone;
  reclassification_id_value uuid;
  journal_entry_id_value uuid;
  salary_account_row public.accounts%rowtype;
  salary_liability_account_id_value uuid;
  salary_liability_account_row public.accounts%rowtype;
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
     or jsonb_typeof(concepts_value) <> 'array'
     or jsonb_typeof(salary_targets_value) <> 'array'
     or jsonb_array_length(salary_targets_value) > 200
     or jsonb_array_length(concepts_value) > 500
     or jsonb_array_length(salary_targets_value)
          + jsonb_array_length(concepts_value) > 500
     or pg_column_size(payload_value) > 1048576 then
    raise exception 'payroll_workspace_v2_invalid_payload'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(jsonb_build_object(
        'workspace_id', p_workspace_id,
        'expected_workspace_version', p_expected_workspace_version,
        'payload', payload_value
      )::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(
    tenant_id_value::text || ':payroll-payment-workspace:'
      || p_workspace_id::text,
    0
  ));

  perform pg_advisory_xact_lock(hashtextextended(
    tenant_id_value::text || ':payroll-settlement',
    0
  ));

  select operation.*
  into existing_operation
  from public.payroll_payment_workspace_v2_operations operation
  where operation.tenant_id = tenant_id_value
    and operation.operation_key = operation_key_value
  for update;

  if found then
    if existing_operation.workspace_id = p_workspace_id
       and existing_operation.payload_hash = payload_hash_value then
      return jsonb_set(
        existing_operation.receipt,
        '{replayed}',
        'true'::jsonb,
        true
      );
    end if;
    raise exception 'payroll_workspace_v2_idempotency_conflict'
      using errcode = 'P0001';
  end if;

  create temporary table if not exists pg_temp.payroll_workspace_v2_targets (
    target_ordinal integer primary key,
    target_id uuid not null unique,
    voucher_id uuid not null,
    expected_reconciliation_version bigint not null,
    has_legs boolean not null,
    legacy_target jsonb not null
  ) on commit drop;
  truncate table pg_temp.payroll_workspace_v2_targets;

  -- V1 requires at least one leg per salary target. V2 also accepts an empty
  -- target when an included concept for that exact worker target will settle
  -- the line. Empty targets are removed before delegating to V1 and restored
  -- verbatim (same UUIDv5 target identity) in the final V2 receipt.
  for target_element in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(salary_targets_value)
      with ordinality item(value, ordinality)
    order by item.ordinality
  loop
    target_value := target_element.value;
    if jsonb_typeof(target_value) <> 'object'
       or exists (
         select 1
         from jsonb_object_keys(target_value) target_key
         where target_key not in (
           'target_id', 'voucher_id', 'expected_reconciliation_version',
           'legs'
         )
       )
       or jsonb_typeof(target_value->'legs') <> 'array'
       or jsonb_array_length(target_value->'legs') > 100
       or coalesce(target_value->>'target_id', '') !~* (
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
         || '[0-9a-f]{4}-[0-9a-f]{12}$'
       )
       or coalesce(target_value->>'voucher_id', '') !~* (
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
         || '[0-9a-f]{4}-[0-9a-f]{12}$'
       )
       or jsonb_typeof(
         target_value->'expected_reconciliation_version'
       ) <> 'number'
       or (target_value->>'expected_reconciliation_version')
            !~ '^[0-9]{1,18}$' then
      raise exception 'payroll_workspace_v2_invalid_salary_target'
        using errcode = '22023';
    end if;

    insert into pg_temp.payroll_workspace_v2_targets (
      target_ordinal, target_id, voucher_id,
      expected_reconciliation_version, has_legs, legacy_target
    ) values (
      target_element.ordinality,
      (target_value->>'target_id')::uuid,
      (target_value->>'voucher_id')::uuid,
      (target_value->>'expected_reconciliation_version')::bigint,
      jsonb_array_length(target_value->'legs') > 0,
      target_value
    );
  end loop;

  create temporary table if not exists pg_temp.payroll_workspace_v2_concepts (
    concept_ordinal integer primary key,
    concept_id uuid not null unique,
    target_id uuid,
    disposition text not null,
    beneficiary_employee_id uuid,
    voucher_id uuid,
    voucher_line_id uuid,
    expected_reconciliation_version bigint,
    amount numeric(14,2) not null,
    legacy_concept jsonb not null,
    result_expense_id uuid,
    effective_at timestamp with time zone,
    disposition_id uuid,
    reclassification_journal_entry_id uuid
  ) on commit drop;
  truncate table pg_temp.payroll_workspace_v2_concepts;

  for concept_element in
    select item.value, item.ordinality::integer
    from jsonb_array_elements(concepts_value)
      with ordinality item(value, ordinality)
    order by item.ordinality
  loop
    concept_value := concept_element.value;
    if jsonb_typeof(concept_value) <> 'object'
       or not (concept_value ? 'disposition')
       or exists (
         select 1
         from jsonb_object_keys(concept_value) concept_key
         where concept_key not in (
           'concept_id', 'beneficiary_employee_id', 'expense_account_id',
           'amount', 'description', 'notes', 'payment_legs', 'disposition',
           'target_id', 'voucher_id', 'voucher_line_id',
           'expected_reconciliation_version'
         )
       ) then
      raise exception 'payroll_workspace_v2_invalid_concept'
        using errcode = '22023';
    end if;

    disposition_value := lower(trim(concept_value->>'disposition'));
    if disposition_value not in ('additional', 'included_in_payroll_total')
       or coalesce(concept_value->>'concept_id', '') !~* (
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
         || '[0-9a-f]{4}-[0-9a-f]{12}$'
       )
       or jsonb_typeof(concept_value->'amount') <> 'number'
       or (concept_value->>'amount') !~ '^[0-9]+([.][0-9]{1,2})?$' then
      raise exception 'payroll_workspace_v2_invalid_concept'
        using errcode = '22023';
    end if;

    concept_id_value := (concept_value->>'concept_id')::uuid;
    beneficiary_employee_id_value :=
      nullif(concept_value->>'beneficiary_employee_id', '')::uuid;
    amount_value := (concept_value->>'amount')::numeric;

    if amount_value <= 0
       or amount_value > 999999999999.99
       or round(amount_value, 2) <> amount_value then
      raise exception 'payroll_workspace_v2_invalid_concept'
        using errcode = '22023';
    end if;

    if disposition_value = 'included_in_payroll_total' then
      if beneficiary_employee_id_value is null
         or coalesce(concept_value->>'target_id', '') !~* (
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
           || '[0-9a-f]{4}-[0-9a-f]{12}$'
         )
         or coalesce(concept_value->>'voucher_id', '') !~* (
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
           || '[0-9a-f]{4}-[0-9a-f]{12}$'
         )
         or coalesce(concept_value->>'voucher_line_id', '') !~* (
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
           || '[0-9a-f]{4}-[0-9a-f]{12}$'
         )
         or jsonb_typeof(
           concept_value->'expected_reconciliation_version'
         ) <> 'number'
         or (concept_value->>'expected_reconciliation_version')
              !~ '^[0-9]{1,19}$' then
        raise exception 'payroll_workspace_v2_invalid_included_link'
          using errcode = '22023';
      end if;

      target_id_value := (concept_value->>'target_id')::uuid;
      voucher_id_value := (concept_value->>'voucher_id')::uuid;
      voucher_line_id_value := (concept_value->>'voucher_line_id')::uuid;
      expected_version_value :=
        (concept_value->>'expected_reconciliation_version')::bigint;
    else
      if concept_value ? 'target_id'
         or concept_value ? 'voucher_id'
         or concept_value ? 'voucher_line_id'
         or concept_value ? 'expected_reconciliation_version' then
        raise exception 'payroll_workspace_v2_additional_cannot_link_payroll'
          using errcode = '22023';
      end if;
      target_id_value := null;
      voucher_id_value := null;
      voucher_line_id_value := null;
      expected_version_value := null;
    end if;

    insert into pg_temp.payroll_workspace_v2_concepts (
      concept_ordinal, concept_id, target_id, disposition,
      beneficiary_employee_id,
      voucher_id, voucher_line_id, expected_reconciliation_version, amount,
      legacy_concept
    ) values (
      concept_element.ordinality, concept_id_value, target_id_value,
      disposition_value,
      beneficiary_employee_id_value, voucher_id_value, voucher_line_id_value,
      expected_version_value, amount_value,
      concept_value - array[
        'disposition', 'target_id', 'voucher_id', 'voucher_line_id',
        'expected_reconciliation_version'
      ]::text[]
    );
  end loop;

  if exists (
    select 1
    from pg_temp.payroll_workspace_v2_concepts concept
    left join pg_temp.payroll_workspace_v2_targets target
      on target.target_id = concept.target_id
     and target.voucher_id = concept.voucher_id
     and target.expected_reconciliation_version =
       concept.expected_reconciliation_version
    where concept.disposition = 'included_in_payroll_total'
      and (
        target.target_id is null
        or (
          target.has_legs
          and not exists (
            select 1
            from jsonb_array_elements(target.legacy_target->'legs') leg(value)
            where leg.value->>'voucher_line_id' =
              concept.voucher_line_id::text
          )
        )
      )
  ) or exists (
    select 1
    from pg_temp.payroll_workspace_v2_targets target
    where target.has_legs is false
      and not exists (
        select 1
        from pg_temp.payroll_workspace_v2_concepts concept
        where concept.disposition = 'included_in_payroll_total'
          and concept.target_id = target.target_id
          and concept.voucher_id = target.voucher_id
          and concept.expected_reconciliation_version =
            target.expected_reconciliation_version
      )
  ) then
    raise exception 'payroll_workspace_v2_included_target_conflict'
      using errcode = '22023';
  end if;

  perform voucher.id
  from public.payroll_vouchers voucher
  join pg_temp.payroll_workspace_v2_concepts concept
    on concept.voucher_id = voucher.id
  where concept.disposition = 'included_in_payroll_total'
    and voucher.tenant_id = tenant_id_value
  order by voucher.id
  for update of voucher;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  join pg_temp.payroll_workspace_v2_concepts concept
    on concept.voucher_line_id = voucher_line.id
   and concept.voucher_id = voucher_line.voucher_id
  where concept.disposition = 'included_in_payroll_total'
    and voucher_line.tenant_id = tenant_id_value
  order by voucher_line.voucher_id, voucher_line.id
  for update of voucher_line;

  if exists (
    select 1
    from pg_temp.payroll_workspace_v2_concepts concept
    left join public.payroll_vouchers voucher
      on voucher.id = concept.voucher_id
     and voucher.tenant_id = tenant_id_value
    left join public.payroll_voucher_lines voucher_line
      on voucher_line.id = concept.voucher_line_id
     and voucher_line.voucher_id = concept.voucher_id
     and voucher_line.tenant_id = tenant_id_value
    where concept.disposition = 'included_in_payroll_total'
      and (
        voucher.id is null
        or voucher.status not in ('confirmed', 'partial')
        or voucher.reconciliation_version
             <> concept.expected_reconciliation_version
        or voucher_line.id is null
        or voucher_line.employee_id <> concept.beneficiary_employee_id
        or voucher_line.is_included is distinct from true
        or voucher_line.total_amount <= 0
        or voucher_line.expense_id is null
        or voucher_line.salary_account_id is null
      )
  ) then
    raise exception 'payroll_workspace_v2_included_link_conflict'
      using errcode = '40001',
        detail = 'reload the complete payroll voucher before applying';
  end if;

  select coalesce(
    jsonb_agg(concept.legacy_concept order by concept.concept_ordinal),
    '[]'::jsonb
  )
  into legacy_concepts_value
  from pg_temp.payroll_workspace_v2_concepts concept;

  select coalesce(
    jsonb_agg(target.legacy_target order by target.target_ordinal),
    '[]'::jsonb
  )
  into legacy_targets_value
  from pg_temp.payroll_workspace_v2_targets target
  where target.has_legs;

  legacy_payload_value := jsonb_set(
    jsonb_set(
      payload_value,
      '{salary_targets}',
      legacy_targets_value,
      true
    ),
    '{additional_concepts}', legacy_concepts_value, true
  );

  legacy_receipt_value := public.apply_payroll_payment_workspace_v1(
    p_workspace_id,
    operation_key_value,
    p_expected_workspace_version,
    legacy_payload_value
  );

  if exists (
    select 1
    from pg_temp.payroll_workspace_v2_targets target
    where target.has_legs
      and not exists (
        select 1
        from jsonb_array_elements(legacy_receipt_value->'targets')
          receipt_target(value)
        where receipt_target.value->>'target_id' = target.target_id::text
          and receipt_target.value->>'voucher_id' = target.voucher_id::text
      )
  ) then
    raise exception 'payroll_workspace_v2_missing_v1_target_receipt'
      using errcode = '55000';
  end if;

  -- V1 has now persisted every actual cash movement.  Validate the included
  -- allocation against the post-payment remainder; any failure rolls the whole
  -- outer transaction, including those V1 movements, back.
  if exists (
    select 1
    from public.payroll_voucher_lines voucher_line
    join (
      select concept.voucher_line_id, sum(concept.amount) as requested_amount
      from pg_temp.payroll_workspace_v2_concepts concept
      where concept.disposition = 'included_in_payroll_total'
      group by concept.voucher_line_id
    ) requested on requested.voucher_line_id = voucher_line.id
    where coalesce((
      select sum(payment.amount)
      from public.expense_payments payment
      where payment.expense_id = voucher_line.expense_id
    ), 0)
    + coalesce((
      select sum(allocation.amount)
      from public.employee_advance_allocations allocation
      where allocation.voucher_line_id = voucher_line.id
    ), 0)
    + coalesce((
      select sum(disposition.amount)
      from public.payroll_payment_workspace_concept_dispositions disposition
      where disposition.voucher_line_id = voucher_line.id
        and disposition.disposition = 'included_in_payroll_total'
    ), 0)
    + requested.requested_amount > voucher_line.total_amount + 0.01
  ) then
    raise exception 'payroll_workspace_v2_salary_and_included_exceed_balance'
      using errcode = '23514';
  end if;

  update pg_temp.payroll_workspace_v2_concepts concept
  set result_expense_id = result.result_expense_id,
      effective_at = result.effective_at
  from (
    select leg.concept_id,
      min(leg.result_expense_id::text)::uuid as result_expense_id,
      max(leg.payment_date) as effective_at
    from public.payroll_payment_workspace_legs leg
    where leg.workspace_id = p_workspace_id
      and leg.tenant_id = tenant_id_value
      and leg.concept_id is not null
    group by leg.concept_id
  ) result
  where result.concept_id = concept.concept_id;

  if exists (
    select 1
    from pg_temp.payroll_workspace_v2_concepts concept
    where concept.result_expense_id is null
      or concept.effective_at is null
  ) then
    raise exception 'payroll_workspace_v2_missing_concept_result'
      using errcode = '55000';
  end if;

  for concept_element in
    select concept.*
    from pg_temp.payroll_workspace_v2_concepts concept
    order by concept.concept_ordinal
  loop
    reclassification_id_value := gen_random_uuid();
    journal_entry_id_value := null;

    if concept_element.disposition = 'included_in_payroll_total' then
      select account.*
      into salary_account_row
      from public.payroll_voucher_lines voucher_line
      join public.accounts account
        on account.id = voucher_line.salary_account_id
       and account.tenant_id = voucher_line.tenant_id
      where voucher_line.id = concept_element.voucher_line_id
        and voucher_line.voucher_id = concept_element.voucher_id
        and voucher_line.tenant_id = tenant_id_value;

      salary_liability_account_id_value := public.ensure_account(
        tenant_id_value,
        '2106',
        'Sueldos por Pagar',
        'liability',
        'currentLiability',
        'Obligaciones pendientes de pago por remuneraciones al personal',
        null
      );

      select account.*
      into salary_liability_account_row
      from public.accounts account
      where account.id = salary_liability_account_id_value
        and account.tenant_id = tenant_id_value;

      journal_entry_id_value := gen_random_uuid();
      insert into public.journal_entries (
        id, tenant_id, entry_number, entry_date, description, type,
        source_module, source_reference, status, total_debit, total_credit,
        source_document_type, source_document_id, created_by
      ) values (
        journal_entry_id_value,
        tenant_id_value,
        public.get_next_document_number(tenant_id_value, 'journal_entry'),
        concept_element.effective_at,
        'Reclasificación de nómina a gasto separado',
        'payroll_reclassification',
        'payroll_payment_workspaces',
        reclassification_id_value::text,
        'posted',
        concept_element.amount,
        concept_element.amount,
        'payroll_concept_reclassification',
        reclassification_id_value,
        actor_id_value
      );

      insert into public.journal_lines (
        tenant_id, entry_id, account_id, account_code, account_name,
        description, debit_amount, credit_amount
      ) values
      (
        tenant_id_value,
        journal_entry_id_value,
        salary_liability_account_row.id,
        salary_liability_account_row.code,
        salary_liability_account_row.name,
        'Reduce obligación salarial por concepto reclasificado',
        concept_element.amount,
        0
      ),
      (
        tenant_id_value,
        journal_entry_id_value,
        salary_account_row.id,
        salary_account_row.code,
        salary_account_row.name,
        'Reduce gasto salarial por concepto reclasificado',
        0,
        concept_element.amount
      );
    end if;

    insert into public.payroll_payment_workspace_concept_dispositions (
      id, tenant_id, workspace_id, concept_id, target_id, disposition,
      voucher_id, voucher_line_id, expected_reconciliation_version, amount,
      result_expense_id, reclassification_journal_entry_id, effective_at,
      result_receipt, applied_by
    ) values (
      reclassification_id_value,
      tenant_id_value,
      p_workspace_id,
      concept_element.concept_id,
      concept_element.target_id,
      concept_element.disposition,
      concept_element.voucher_id,
      concept_element.voucher_line_id,
      concept_element.expected_reconciliation_version,
      concept_element.amount,
      concept_element.result_expense_id,
      journal_entry_id_value,
      concept_element.effective_at,
      jsonb_strip_nulls(jsonb_build_object(
        'concept_id', concept_element.concept_id,
        'target_id', concept_element.target_id,
        'disposition', concept_element.disposition,
        'voucher_id', concept_element.voucher_id,
        'voucher_line_id', concept_element.voucher_line_id,
        'amount', concept_element.amount,
        'result_expense_id', concept_element.result_expense_id,
        'reclassification_id', reclassification_id_value,
        'reclassification_journal_entry_id', journal_entry_id_value
      )),
      actor_id_value
    );

    update pg_temp.payroll_workspace_v2_concepts concept
    set disposition_id = reclassification_id_value,
        reclassification_journal_entry_id = journal_entry_id_value
    where concept.concept_id = concept_element.concept_id;
  end loop;

  for voucher_line_id_value in
    select distinct concept.voucher_line_id
    from pg_temp.payroll_workspace_v2_concepts concept
    where concept.disposition = 'included_in_payroll_total'
    order by concept.voucher_line_id
  loop
    select voucher_line.expense_id
    into result_expense_id_value
    from public.payroll_voucher_lines voucher_line
    where voucher_line.id = voucher_line_id_value
      and voucher_line.tenant_id = tenant_id_value;

    perform public.recalculate_expense_totals_owner_only(
      result_expense_id_value
    );
  end loop;

  for voucher_id_value in
    select distinct concept.voucher_id
    from pg_temp.payroll_workspace_v2_concepts concept
    where concept.disposition = 'included_in_payroll_total'
    order by concept.voucher_id
  loop
    perform public.refresh_payroll_voucher_status(voucher_id_value);
  end loop;

  receipt_value := legacy_receipt_value || jsonb_build_object(
    'api_version', 2,
    'replayed', false,
    'targets', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'target_id', input_target.target_id,
          'voucher_id', input_target.voucher_id,
          'status', voucher.status,
          'reconciliation_version', voucher.reconciliation_version,
          'legs', coalesce(legacy_target.value->'legs', '[]'::jsonb)
        )
        order by input_target.target_ordinal
      )
      from pg_temp.payroll_workspace_v2_targets input_target
      join public.payroll_vouchers voucher
        on voucher.id = input_target.voucher_id
       and voucher.tenant_id = tenant_id_value
      left join lateral (
        select receipt_target.value
        from jsonb_array_elements(legacy_receipt_value->'targets')
          receipt_target(value)
        where receipt_target.value->>'target_id' =
          input_target.target_id::text
        limit 1
      ) legacy_target on true
    ), '[]'::jsonb),
    'additional_concepts', coalesce((
      select jsonb_agg(
        concept_receipt.value || jsonb_strip_nulls(jsonb_build_object(
          'disposition', disposition.disposition,
          'target_id', disposition.target_id,
          'voucher_id', disposition.voucher_id,
          'voucher_line_id', disposition.voucher_line_id,
          'reclassification_id', disposition.id,
          'reclassification_journal_entry_id',
            disposition.reclassification_journal_entry_id
        ))
        order by concept_receipt.ordinality
      )
      from jsonb_array_elements(
        legacy_receipt_value->'additional_concepts'
      ) with ordinality concept_receipt(value, ordinality)
      join public.payroll_payment_workspace_concept_dispositions disposition
        on disposition.workspace_id = p_workspace_id
       and disposition.tenant_id = tenant_id_value
       and disposition.concept_id =
          (concept_receipt.value->>'concept_id')::uuid
    ), '[]'::jsonb)
  );

  insert into public.payroll_payment_workspace_v2_operations (
    tenant_id, workspace_id, operation_key, payload_hash, receipt, created_by
  ) values (
    tenant_id_value, p_workspace_id, operation_key_value,
    payload_hash_value, receipt_value, actor_id_value
  );

  return receipt_value;
end;
$$;

revoke all on function public.apply_payroll_payment_workspace_v2(
  uuid, text, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.apply_payroll_payment_workspace_v2(
  uuid, text, bigint, jsonb
) to authenticated, service_role;

comment on function public.apply_payroll_payment_workspace_v2(
  uuid, text, bigint, jsonb
) is
  'Atomically posts payroll payments plus separate concepts. included_in_payroll_total links a concept to one voucher line, counts it toward settlement, and posts a non-cash accounting reclassification.';

commit;
