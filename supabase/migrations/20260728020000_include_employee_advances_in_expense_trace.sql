-- Payroll advances settle part of a salary expense without creating an
-- expense_payments row. Keep the expense trace on the same effective-payment
-- truth as recalculate_expense_totals_owner_only, and do not demand that a
-- nested totals-only expense update relink the unchanged accrual journal.
--
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).
-- Recovery: drop the trace index/constraint additions from the immediately
-- preceding schema snapshot; no data rewrite or backfill occurs.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create index if not exists idx_payroll_voucher_lines_tenant_expense
  on public.payroll_voucher_lines(tenant_id, expense_id)
  where expense_id is not null;

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

    v_payment_total := round(
      v_cash_payment_total + v_advance_allocation_total,
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
      'advance_allocation_total', v_advance_allocation_total
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
  'Validates expense totals against cash payments plus payroll advance allocations and completes the accounting trace.';

create or replace function public.complete_expense_row_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_text text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  v_operation_id uuid;
  v_operation_context jsonb;
  v_tenant_id uuid;
  v_expense_id uuid;
  v_payment_id uuid;
  v_expense_number text;
  v_require_accrual_link boolean := false;
  v_require_payment_link boolean := false;
  v_expected_accrual integer := null;
  v_expected_payment integer := null;
  v_expense_deleted boolean := false;
begin
  if v_operation_text is null then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  v_operation_id := v_operation_text::uuid;
  select operation.context
  into v_operation_context
  from public.inventory_accounting_operations operation
  where operation.id = v_operation_id;

  -- Nested expense recalculations and RPC-owned traces are finalized by the
  -- original line/payment trigger or wrapper, never by an intermediate UPDATE.
  if v_operation_context->>'trace_owner' is distinct from 'row_trigger'
     or v_operation_context->>'owner_table' is distinct from TG_TABLE_NAME
     -- Only the owning trigger depth may finalize a same-table root.
     or coalesce(
       nullif(v_operation_context->>'trigger_depth', '')::integer,
       1
     ) <> pg_trigger_depth() then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  v_tenant_id := case
    when TG_OP = 'DELETE' then OLD.tenant_id
    else NEW.tenant_id
  end;

  if TG_TABLE_NAME = 'expenses' then
    v_expense_id := case when TG_OP = 'DELETE' then OLD.id else NEW.id end;
    if TG_OP = 'DELETE' then
      v_expected_accrual := 0;
      v_expense_deleted := true;
      v_expense_number := OLD.expense_number;
    elsif TG_OP = 'UPDATE'
       and lower(coalesce(NEW.posting_status, 'draft')) = 'posted'
       and coalesce(
         (v_operation_context->>'trigger_depth')::integer,
         pg_trigger_depth()
       ) <= 1 then
      -- process_expense_change rebuilds and relinks the accrual journal only
      -- for a root expense update. Nested totals-only updates intentionally
      -- return early, so their trace validates journal count/balance but must
      -- retain the immutable operation link of the unchanged accrual.
      v_require_accrual_link := true;
    end if;
  elsif TG_TABLE_NAME = 'expense_lines' then
    v_expense_id := case
      when TG_OP = 'DELETE' then OLD.expense_id
      else NEW.expense_id
    end;
    v_require_accrual_link := true;
  elsif TG_TABLE_NAME = 'expense_payments' then
    v_expense_id := case
      when TG_OP = 'DELETE' then OLD.expense_id
      else NEW.expense_id
    end;
    v_payment_id := case when TG_OP = 'DELETE' then OLD.id else NEW.id end;
    v_require_payment_link := true;
    if TG_OP = 'DELETE' then
      v_expected_payment := 0;
    end if;
  end if;

  perform public.complete_expense_accounting_operation(
    v_operation_id,
    v_tenant_id,
    v_expense_id,
    v_payment_id,
    v_expected_accrual,
    v_expected_payment,
    v_require_accrual_link,
    v_require_payment_link,
    v_expense_deleted,
    v_expense_number
  );

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.complete_expense_row_trace()
  from public, anon, authenticated, service_role;

comment on function public.complete_expense_row_trace() is
  'Completes root and nested expense traces without relinking an unchanged accrual journal during nested totals-only updates.';

-- The canonical bootstrap predates the dynamic expense-RPC ACL convergence.
-- Reassert the trigger-only boundary explicitly so a snapshot build and a
-- migration build expose the same final privileges.
revoke all on function public.handle_expense_line_change()
  from public, anon, authenticated, service_role;
revoke all on function public.handle_expense_payment_change()
  from public, anon, authenticated, service_role;

commit;
