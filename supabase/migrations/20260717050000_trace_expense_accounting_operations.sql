-- Deployment status: DEPLOYED AND VERIFIED in production
-- xzdvtzdqjeyqxnkqprtf on 2026-07-17 (America/Los_Angeles).
-- Forward change:
--   Connect expense headers, lines, payments, accrual journals, and payment
--   journals to the shared inventory/accounting operation trace. Existing
--   expense and journal rows are not rewritten.
-- Recovery:
--   Roll back the client to the previous expense calls if needed. The trace
--   rows and nullable journal lineage remain compatible and must not be
--   deleted. The legacy journal implementations are retained as private
--   helpers so the public wrappers can be replaced without data loss.

begin;

create or replace function public.expense_accounting_trace_snapshot(p_row jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', p_row->'id',
    'expense_number', p_row->'expense_number',
    'posting_status', p_row->'posting_status',
    'payment_status', p_row->'payment_status',
    'issue_date', p_row->'issue_date',
    'currency', p_row->'currency',
    'subtotal', p_row->'subtotal',
    'tax_amount', p_row->'tax_amount',
    'total_amount', p_row->'total_amount',
    'amount_paid', p_row->'amount_paid',
    'balance', p_row->'balance',
    'payment_method_id', p_row->'payment_method_id',
    'payment_account_id', p_row->'payment_account_id',
    'posted_at', p_row->'posted_at',
    'paid_at', p_row->'paid_at',
    'created_at', p_row->'created_at',
    'updated_at', p_row->'updated_at'
  ));
$$;

revoke all on function public.expense_accounting_trace_snapshot(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.begin_expense_accounting_operation(
  p_tenant_id uuid,
  p_document_type text,
  p_document_id uuid,
  p_expense_id uuid,
  p_source_channel text,
  p_action text,
  p_before_snapshot jsonb default null,
  p_after_snapshot jsonb default null,
  p_context jsonb default '{}'::jsonb,
  p_executor text default 'database_trigger'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_text text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  v_operation_id uuid;
  v_operation_key text;
begin
  if v_existing_text is not null then
    v_operation_id := v_existing_text::uuid;
    if not exists (
      select 1
      from public.inventory_accounting_operations operation
      where operation.id = v_operation_id
        and operation.tenant_id = p_tenant_id
    ) then
      raise exception 'Active accounting operation does not belong to expense tenant'
        using errcode = 'foreign_key_violation';
    end if;
    return v_operation_id;
  end if;

  if p_tenant_id is null
     or p_document_type is null
     or p_document_id is null
     or p_source_channel is null
     or p_action is null then
    raise exception 'Expense trace requires tenant, document, source channel, and action';
  end if;

  if auth.uid() is not null
     and public.user_tenant_id() is distinct from p_tenant_id then
    raise exception 'Expense trace tenant does not match authenticated tenant'
      using errcode = 'insufficient_privilege';
  end if;

  v_operation_key := format(
    '%s:%s:%s:%s',
    p_document_type,
    p_document_id,
    p_action,
    coalesce(
      nullif(current_setting('app.inventory_idempotency_key', true), ''),
      gen_random_uuid()::text
    )
  );

  insert into public.inventory_accounting_operations (
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    old_status,
    new_status,
    before_snapshot,
    after_snapshot,
    context
  ) values (
    p_tenant_id,
    v_operation_key,
    p_source_channel,
    p_action,
    p_document_type,
    p_document_id,
    auth.uid(),
    coalesce(nullif(p_executor, ''), 'database_trigger'),
    coalesce(
      p_before_snapshot->>'posting_status',
      p_before_snapshot->>'payment_status'
    ),
    coalesce(
      p_after_snapshot->>'posting_status',
      p_after_snapshot->>'payment_status'
    ),
    p_before_snapshot,
    p_after_snapshot,
    jsonb_strip_nulls(jsonb_build_object(
      'expense_id', p_expense_id,
      'transaction_id', txid_current()::text
    )) || coalesce(p_context, '{}'::jsonb)
  )
  returning id into v_operation_id;

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', p_document_type, true);
  perform set_config('app.inventory_source_document_id', p_document_id::text, true);
  perform set_config('app.inventory_source_channel', p_source_channel, true);

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    p_document_type,
    p_document_id,
    jsonb_build_object(
      'action', p_action,
      'source_channel', p_source_channel,
      'expense_id', p_expense_id
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    p_document_type,
    p_document_id,
    jsonb_build_object(
      'before', p_before_snapshot,
      'after', p_after_snapshot
    )
  );

  return v_operation_id;
end;
$$;

revoke all on function public.begin_expense_accounting_operation(
  uuid, text, uuid, uuid, text, text, jsonb, jsonb, jsonb, text
) from public, anon, authenticated, service_role;

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
    v_expense_snapshot := public.expense_accounting_trace_snapshot(to_jsonb(v_expense));
    p_expense_number := coalesce(p_expense_number, v_expense.expense_number);

    select
      round(coalesce(sum(line.subtotal), 0), 2),
      round(coalesce(sum(line.tax_amount), 0), 2),
      round(coalesce(sum(line.total), 0), 2)
    into v_line_subtotal, v_line_tax, v_line_total
    from public.expense_lines line
    where line.expense_id = v_expense.id
      and line.tenant_id = v_expense.tenant_id;

    select round(coalesce(sum(payment.amount), 0), 2)
    into v_payment_total
    from public.expense_payments payment
    where payment.expense_id = v_expense.id
      and payment.tenant_id = v_expense.tenant_id;

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
      case when round(coalesce(v_expense.subtotal, 0), 2) <> v_line_subtotal then 1 else 0 end
      + case when round(coalesce(v_expense.tax_amount, 0), 2) <> v_line_tax then 1 else 0 end
      + case when round(coalesce(v_expense.total_amount, 0), 2) <> v_line_total then 1 else 0 end
      + case when round(coalesce(v_expense.amount_paid, 0), 2) <> v_effective_paid then 1 else 0 end
      + case when round(coalesce(v_expense.balance, 0), 2) <> v_expected_balance then 1 else 0 end;

    v_expected_accrual := coalesce(
      p_expected_accrual_journals,
      case
        when lower(coalesce(v_expense.posting_status, 'draft')) = 'posted'
         and round(coalesce(v_expense.total_amount, 0), 2) <> 0 then 1
        else 0
      end
    );
  elsif p_expense_id is not null and not p_expense_deleted then
    raise exception 'Expense % disappeared before trace completion', p_expense_id
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
      entry.source_reference = p_expense_number
      or (p_expense_id is not null and entry.source_reference = p_expense_id::text)
      or (p_expense_id is not null and entry.source_document_id = p_expense_id)
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
        entry.source_reference = p_expense_number
        or (p_expense_id is not null and entry.source_reference = p_expense_id::text)
        or (p_expense_id is not null and entry.source_document_id = p_expense_id)
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
            entry.source_reference = p_expense_number
            or (p_expense_id is not null and entry.source_reference = p_expense_id::text)
            or (p_expense_id is not null and entry.source_document_id = p_expense_id)
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
      'payment_total', v_payment_total
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

create or replace function public.begin_expense_row_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_operation text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  v_old_row jsonb;
  v_new_row jsonb;
  v_effective_row jsonb;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_tenant_id uuid;
  v_expense_id uuid;
  v_document_id uuid;
  v_document_type text;
  v_source_channel text;
  v_action text;
  v_entity_id uuid;
begin
  -- Recalculation and journal wrappers deliberately keep one active root.
  if v_active_operation is not null then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  if TG_OP = 'INSERT' then
    v_new_row := to_jsonb(NEW);
    v_effective_row := v_new_row;
  elsif TG_OP = 'UPDATE' then
    v_old_row := to_jsonb(OLD);
    v_new_row := to_jsonb(NEW);
    v_effective_row := v_new_row;
  else
    v_old_row := to_jsonb(OLD);
    v_effective_row := v_old_row;
  end if;

  v_tenant_id := nullif(v_effective_row->>'tenant_id', '')::uuid;
  v_entity_id := nullif(v_effective_row->>'id', '')::uuid;
  v_action := lower(TG_OP);

  if TG_TABLE_NAME = 'expenses' then
    v_expense_id := v_entity_id;
    v_document_id := v_expense_id;
    v_document_type := 'expense';
    v_source_channel := 'expense';
    v_before_snapshot := case
      when v_old_row is null then null
      else public.expense_accounting_trace_snapshot(v_old_row)
    end;
    v_after_snapshot := case
      when v_new_row is null then null
      else public.expense_accounting_trace_snapshot(v_new_row)
    end;
  elsif TG_TABLE_NAME = 'expense_lines' then
    v_expense_id := nullif(v_effective_row->>'expense_id', '')::uuid;
    v_document_id := v_expense_id;
    v_document_type := 'expense';
    v_source_channel := 'expense_line';
    v_action := 'line_' || v_action;
    v_before_snapshot := case when v_old_row is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', v_old_row->'id',
      'expense_id', v_old_row->'expense_id',
      'line_index', v_old_row->'line_index',
      'account_id', v_old_row->'account_id',
      'quantity', v_old_row->'quantity',
      'unit_price', v_old_row->'unit_price',
      'subtotal', v_old_row->'subtotal',
      'tax_amount', v_old_row->'tax_amount',
      'total', v_old_row->'total'
    )) end;
    v_after_snapshot := case when v_new_row is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', v_new_row->'id',
      'expense_id', v_new_row->'expense_id',
      'line_index', v_new_row->'line_index',
      'account_id', v_new_row->'account_id',
      'quantity', v_new_row->'quantity',
      'unit_price', v_new_row->'unit_price',
      'subtotal', v_new_row->'subtotal',
      'tax_amount', v_new_row->'tax_amount',
      'total', v_new_row->'total'
    )) end;
  elsif TG_TABLE_NAME = 'expense_payments' then
    v_expense_id := nullif(v_effective_row->>'expense_id', '')::uuid;
    v_document_id := v_entity_id;
    v_document_type := 'expense_payment';
    v_source_channel := 'expense_payment';
    v_before_snapshot := case when v_old_row is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', v_old_row->'id',
      'expense_id', v_old_row->'expense_id',
      'payment_method_id', v_old_row->'payment_method_id',
      'payment_account_id', v_old_row->'payment_account_id',
      'amount', v_old_row->'amount',
      'payment_date', v_old_row->'payment_date',
      'reference', v_old_row->'reference',
      'created_at', v_old_row->'created_at',
      'updated_at', v_old_row->'updated_at'
    )) end;
    v_after_snapshot := case when v_new_row is null then null else jsonb_strip_nulls(jsonb_build_object(
      'id', v_new_row->'id',
      'expense_id', v_new_row->'expense_id',
      'payment_method_id', v_new_row->'payment_method_id',
      'payment_account_id', v_new_row->'payment_account_id',
      'amount', v_new_row->'amount',
      'payment_date', v_new_row->'payment_date',
      'reference', v_new_row->'reference',
      'created_at', v_new_row->'created_at',
      'updated_at', v_new_row->'updated_at'
    )) end;
  else
    raise exception 'Unsupported expense trace table: %', TG_TABLE_NAME;
  end if;

  if v_tenant_id is null or v_document_id is null then
    raise exception 'Expense row trace requires tenant and document id';
  end if;

  if TG_TABLE_NAME <> 'expenses'
     and v_expense_id is not null
     and not exists (
    select 1
    from public.expenses expense
    where expense.id = v_expense_id
      and expense.tenant_id = v_tenant_id
  ) then
    raise exception 'Expense trace parent % does not belong to tenant %',
      v_expense_id,
      v_tenant_id
      using errcode = 'foreign_key_violation';
  end if;

  perform public.begin_expense_accounting_operation(
    v_tenant_id,
    v_document_type,
    v_document_id,
    v_expense_id,
    v_source_channel,
    v_action,
    v_before_snapshot,
    v_after_snapshot,
    jsonb_build_object(
      'trace_owner', 'row_trigger',
      'owner_table', TG_TABLE_NAME,
      'owner_entity_id', v_entity_id,
      'table', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
      'trigger_depth', pg_trigger_depth()
    ),
    'database_trigger'
  );

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.begin_expense_row_trace()
  from public, anon, authenticated, service_role;

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
     or v_operation_context->>'owner_table' is distinct from TG_TABLE_NAME then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  v_tenant_id := case when TG_OP = 'DELETE' then OLD.tenant_id else NEW.tenant_id end;

  if TG_TABLE_NAME = 'expenses' then
    v_expense_id := case when TG_OP = 'DELETE' then OLD.id else NEW.id end;
    if TG_OP = 'DELETE' then
      v_expected_accrual := 0;
      v_expense_deleted := true;
      v_expense_number := OLD.expense_number;
    elsif TG_OP = 'UPDATE'
       and lower(coalesce(NEW.posting_status, 'draft')) = 'posted' then
      v_require_accrual_link := true;
    end if;
  elsif TG_TABLE_NAME = 'expense_lines' then
    v_expense_id := case when TG_OP = 'DELETE' then OLD.expense_id else NEW.expense_id end;
    v_require_accrual_link := true;
  elsif TG_TABLE_NAME = 'expense_payments' then
    v_expense_id := case when TG_OP = 'DELETE' then OLD.expense_id else NEW.expense_id end;
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

drop trigger if exists zz_expense_trace_begin_expense on public.expenses;
create trigger zz_expense_trace_begin_expense
  before insert or update or delete on public.expenses
  for each row execute function public.begin_expense_row_trace();

drop trigger if exists zzz_expense_trace_complete_expense on public.expenses;
create trigger zzz_expense_trace_complete_expense
  after insert or update or delete on public.expenses
  for each row execute function public.complete_expense_row_trace();

drop trigger if exists zz_expense_trace_begin_line on public.expense_lines;
create trigger zz_expense_trace_begin_line
  before insert or update or delete on public.expense_lines
  for each row execute function public.begin_expense_row_trace();

drop trigger if exists zzz_expense_trace_complete_line on public.expense_lines;
create trigger zzz_expense_trace_complete_line
  after insert or update or delete on public.expense_lines
  for each row execute function public.complete_expense_row_trace();

drop trigger if exists zz_expense_trace_begin_payment on public.expense_payments;
create trigger zz_expense_trace_begin_payment
  before insert or update or delete on public.expense_payments
  for each row execute function public.begin_expense_row_trace();

drop trigger if exists zzz_expense_trace_complete_payment on public.expense_payments;
create trigger zzz_expense_trace_complete_payment
  after insert or update or delete on public.expense_payments
  for each row execute function public.complete_expense_row_trace();

-- Preserve the proven accounting implementations behind traced wrappers.
do $$
begin
  if to_regprocedure('public.create_expense_journal_entry_untraced(uuid)') is null then
    alter function public.create_expense_journal_entry(uuid)
      rename to create_expense_journal_entry_untraced;
  end if;
  if to_regprocedure('public.delete_expense_journal_entry_untraced(uuid)') is null then
    alter function public.delete_expense_journal_entry(uuid)
      rename to delete_expense_journal_entry_untraced;
  end if;
  if to_regprocedure('public.create_expense_payment_journal_entry_untraced(uuid)') is null then
    alter function public.create_expense_payment_journal_entry(uuid)
      rename to create_expense_payment_journal_entry_untraced;
  end if;
  if to_regprocedure('public.delete_expense_payment_journal_entry_untraced(uuid)') is null then
    alter function public.delete_expense_payment_journal_entry(uuid)
      rename to delete_expense_payment_journal_entry_untraced;
  end if;
end $$;

revoke all on function public.create_expense_journal_entry_untraced(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_expense_journal_entry_untraced(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.create_expense_payment_journal_entry_untraced(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_expense_payment_journal_entry_untraced(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
  v_operation_text text := nullif(current_setting('app.inventory_operation_id', true), '');
  v_operation_id uuid;
  v_owns_trace boolean := false;
  v_expected integer := 0;
begin
  select * into v_expense
  from public.expenses expense
  where expense.id = p_expense_id;

  if not found then
    perform public.create_expense_journal_entry_untraced(p_expense_id);
    return;
  end if;

  if v_operation_text is null then
    v_operation_id := public.begin_expense_accounting_operation(
      v_expense.tenant_id,
      'expense',
      v_expense.id,
      v_expense.id,
      'expense',
      'journal_rebuild',
      public.expense_accounting_trace_snapshot(to_jsonb(v_expense)),
      public.expense_accounting_trace_snapshot(to_jsonb(v_expense)),
      jsonb_build_object('trace_owner', 'rpc', 'rpc', 'create_expense_journal_entry'),
      'database_rpc'
    );
    v_owns_trace := true;
  else
    v_operation_id := v_operation_text::uuid;
  end if;

  perform public.create_expense_journal_entry_untraced(p_expense_id);

  if v_owns_trace then
    select * into v_expense from public.expenses where id = p_expense_id;
    v_expected := case
      when lower(coalesce(v_expense.posting_status, 'draft')) = 'posted'
       and round(coalesce(v_expense.total_amount, 0), 2) <> 0 then 1
      else 0
    end;
    perform public.complete_expense_accounting_operation(
      v_operation_id,
      v_expense.tenant_id,
      v_expense.id,
      null,
      v_expected,
      null,
      v_expected = 1,
      false,
      false,
      v_expense.expense_number
    );
  end if;
exception
  when others then
    if v_owns_trace then
      perform set_config('app.inventory_operation_id', '', true);
      perform set_config('app.inventory_source_document_type', '', true);
      perform set_config('app.inventory_source_document_id', '', true);
      perform set_config('app.inventory_source_channel', '', true);
    end if;
    raise;
end;
$$;

create or replace function public.delete_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
  v_operation_text text := nullif(current_setting('app.inventory_operation_id', true), '');
  v_operation_id uuid;
  v_owns_trace boolean := false;
begin
  select * into v_expense
  from public.expenses expense
  where expense.id = p_expense_id;

  if not found then
    perform public.delete_expense_journal_entry_untraced(p_expense_id);
    delete from public.journal_entries entry
    where entry.source_module = 'expenses'
      and entry.source_document_id = p_expense_id;
    return;
  end if;

  if v_operation_text is null then
    v_operation_id := public.begin_expense_accounting_operation(
      v_expense.tenant_id,
      'expense',
      v_expense.id,
      v_expense.id,
      'expense',
      'journal_delete',
      public.expense_accounting_trace_snapshot(to_jsonb(v_expense)),
      public.expense_accounting_trace_snapshot(to_jsonb(v_expense)),
      jsonb_build_object('trace_owner', 'rpc', 'rpc', 'delete_expense_journal_entry'),
      'database_rpc'
    );
    v_owns_trace := true;
  else
    v_operation_id := v_operation_text::uuid;
  end if;

  perform public.delete_expense_journal_entry_untraced(p_expense_id);
  delete from public.journal_entries entry
  where entry.tenant_id = v_expense.tenant_id
    and entry.source_module = 'expenses'
    and entry.source_document_id = p_expense_id;

  if v_owns_trace then
    perform public.complete_expense_accounting_operation(
      v_operation_id,
      v_expense.tenant_id,
      v_expense.id,
      null,
      0,
      null,
      false,
      false,
      false,
      v_expense.expense_number
    );
  end if;
exception
  when others then
    if v_owns_trace then
      perform set_config('app.inventory_operation_id', '', true);
      perform set_config('app.inventory_source_document_type', '', true);
      perform set_config('app.inventory_source_document_id', '', true);
      perform set_config('app.inventory_source_channel', '', true);
    end if;
    raise;
end;
$$;

create or replace function public.create_expense_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.expense_payments%rowtype;
  v_expense public.expenses%rowtype;
  v_operation_text text := nullif(current_setting('app.inventory_operation_id', true), '');
  v_operation_id uuid;
  v_owns_trace boolean := false;
begin
  select * into v_payment
  from public.expense_payments payment
  where payment.id = p_payment_id;
  if not found then
    perform public.create_expense_payment_journal_entry_untraced(p_payment_id);
    return;
  end if;

  select * into v_expense
  from public.expenses expense
  where expense.id = v_payment.expense_id
    and expense.tenant_id = v_payment.tenant_id;
  if not found then
    raise exception 'Expense payment parent is missing'
      using errcode = 'foreign_key_violation';
  end if;

  if v_operation_text is null then
    v_operation_id := public.begin_expense_accounting_operation(
      v_payment.tenant_id,
      'expense_payment',
      v_payment.id,
      v_expense.id,
      'expense_payment',
      'journal_rebuild',
      to_jsonb(v_payment),
      to_jsonb(v_payment),
      jsonb_build_object('trace_owner', 'rpc', 'rpc', 'create_expense_payment_journal_entry'),
      'database_rpc'
    );
    v_owns_trace := true;
  else
    v_operation_id := v_operation_text::uuid;
  end if;

  perform public.create_expense_payment_journal_entry_untraced(p_payment_id);

  if v_owns_trace then
    perform public.complete_expense_accounting_operation(
      v_operation_id,
      v_payment.tenant_id,
      v_expense.id,
      v_payment.id,
      null,
      null,
      false,
      true,
      false,
      v_expense.expense_number
    );
  end if;
exception
  when others then
    if v_owns_trace then
      perform set_config('app.inventory_operation_id', '', true);
      perform set_config('app.inventory_source_document_type', '', true);
      perform set_config('app.inventory_source_document_id', '', true);
      perform set_config('app.inventory_source_channel', '', true);
    end if;
    raise;
end;
$$;

create or replace function public.delete_expense_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.expense_payments%rowtype;
  v_expense public.expenses%rowtype;
  v_entry public.journal_entries%rowtype;
  v_operation_text text := nullif(current_setting('app.inventory_operation_id', true), '');
  v_operation_id uuid;
  v_owns_trace boolean := false;
begin
  select * into v_payment
  from public.expense_payments payment
  where payment.id = p_payment_id;

  if found then
    select * into v_expense
    from public.expenses expense
    where expense.id = v_payment.expense_id
      and expense.tenant_id = v_payment.tenant_id;
  elsif v_operation_text is null then
    select * into v_entry
    from public.journal_entries entry
    where entry.source_module = 'expense_payments'
      and (
        entry.source_reference = p_payment_id::text
        or entry.source_document_id = p_payment_id
      )
    order by entry.created_at desc
    limit 1;
  end if;

  if v_operation_text is null and (v_payment.id is not null or v_entry.id is not null) then
    v_operation_id := public.begin_expense_accounting_operation(
      coalesce(v_payment.tenant_id, v_entry.tenant_id),
      'expense_payment',
      p_payment_id,
      v_payment.expense_id,
      'expense_payment',
      'journal_delete',
      case when v_payment.id is null then to_jsonb(v_entry) else to_jsonb(v_payment) end,
      null,
      jsonb_build_object('trace_owner', 'rpc', 'rpc', 'delete_expense_payment_journal_entry'),
      'database_rpc'
    );
    v_owns_trace := true;
  elsif v_operation_text is not null then
    v_operation_id := v_operation_text::uuid;
  end if;

  perform public.delete_expense_payment_journal_entry_untraced(p_payment_id);

  if v_owns_trace then
    perform public.complete_expense_accounting_operation(
      v_operation_id,
      coalesce(v_payment.tenant_id, v_entry.tenant_id),
      v_payment.expense_id,
      p_payment_id,
      null,
      0,
      false,
      false,
      v_payment.id is null,
      v_expense.expense_number
    );
  end if;
exception
  when others then
    if v_owns_trace then
      perform set_config('app.inventory_operation_id', '', true);
      perform set_config('app.inventory_source_document_type', '', true);
      perform set_config('app.inventory_source_document_id', '', true);
      perform set_config('app.inventory_source_channel', '', true);
    end if;
    raise;
end;
$$;

revoke all on function public.create_expense_journal_entry(uuid)
  from public, anon;
revoke all on function public.delete_expense_journal_entry(uuid)
  from public, anon;
revoke all on function public.create_expense_payment_journal_entry(uuid)
  from public, anon;
revoke all on function public.delete_expense_payment_journal_entry(uuid)
  from public, anon;
grant execute on function public.create_expense_journal_entry(uuid)
  to authenticated, service_role;
grant execute on function public.delete_expense_journal_entry(uuid)
  to authenticated, service_role;
grant execute on function public.create_expense_payment_journal_entry(uuid)
  to authenticated, service_role;
grant execute on function public.delete_expense_payment_journal_entry(uuid)
  to authenticated, service_role;

create or replace function public.rebuild_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense public.expenses%rowtype;
  v_operation_text text := nullif(current_setting('app.inventory_operation_id', true), '');
  v_operation_id uuid;
  v_owns_trace boolean := false;
  v_expected integer := 0;
begin
  select * into v_expense
  from public.expenses expense
  where expense.id = p_expense_id;
  if not found then
    raise exception 'Expense not found'
      using errcode = 'no_data_found';
  end if;

  if v_operation_text is null then
    v_operation_id := public.begin_expense_accounting_operation(
      v_expense.tenant_id,
      'expense',
      v_expense.id,
      v_expense.id,
      'expense',
      'rebuild_journal',
      public.expense_accounting_trace_snapshot(to_jsonb(v_expense)),
      null,
      jsonb_build_object('trace_owner', 'rpc', 'rpc', 'rebuild_expense_journal_entry'),
      'database_rpc'
    );
    v_owns_trace := true;
  else
    v_operation_id := v_operation_text::uuid;
  end if;

  perform public.recalculate_expense_totals(p_expense_id);

  if v_owns_trace then
    select * into v_expense from public.expenses where id = p_expense_id;
    v_expected := case
      when lower(coalesce(v_expense.posting_status, 'draft')) = 'posted'
       and round(coalesce(v_expense.total_amount, 0), 2) <> 0 then 1
      else 0
    end;
    perform public.complete_expense_accounting_operation(
      v_operation_id,
      v_expense.tenant_id,
      v_expense.id,
      null,
      v_expected,
      null,
      v_expected = 1,
      false,
      false,
      v_expense.expense_number
    );
  end if;
exception
  when others then
    if v_owns_trace then
      perform set_config('app.inventory_operation_id', '', true);
      perform set_config('app.inventory_source_document_type', '', true);
      perform set_config('app.inventory_source_document_id', '', true);
      perform set_config('app.inventory_source_channel', '', true);
    end if;
    raise;
end;
$$;

revoke all on function public.rebuild_expense_journal_entry(uuid)
  from public, anon;
grant execute on function public.rebuild_expense_journal_entry(uuid)
  to authenticated, service_role;

-- Recalculate before rebuilding so trigger-created journals never capture the
-- previous line totals. Current clients also call the atomic rebuild wrapper,
-- while old clients remain compatible with the traced public wrappers above.
create or replace function public.handle_expense_line_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense_id uuid;
  v_posting_status text;
begin
  v_expense_id := case when TG_OP = 'DELETE' then OLD.expense_id else NEW.expense_id end;

  perform public.recalculate_expense_totals(v_expense_id);

  select posting_status into v_posting_status
  from public.expenses
  where id = v_expense_id;

  if lower(coalesce(v_posting_status, 'draft')) = 'posted' then
    perform public.create_expense_journal_entry(v_expense_id);
  end if;

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

-- An AFTER DELETE can no longer resolve the removed expense number through
-- the one-argument compatibility helper. Delete by the immutable OLD snapshot
-- so no posted journal can be orphaned.
create or replace function public.process_expense_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_posted boolean := case
    when TG_OP = 'INSERT' then false
    else lower(coalesce(OLD.posting_status, 'draft')) = 'posted'
  end;
  v_new_posted boolean := case
    when TG_OP = 'DELETE' then false
    else lower(coalesce(NEW.posting_status, 'draft')) = 'posted'
  end;
begin
  if pg_trigger_depth() > 1 then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  if TG_OP = 'INSERT' then
    perform public.recalculate_expense_totals(NEW.id);
    return NEW;
  elsif TG_OP = 'UPDATE' then
    perform public.recalculate_expense_totals(NEW.id);

    if v_old_posted and not v_new_posted then
      perform public.delete_expense_journal_entry(OLD.id);
    elsif not v_old_posted and v_new_posted then
      perform public.create_expense_journal_entry(NEW.id);
    elsif v_old_posted and v_new_posted then
      perform public.create_expense_journal_entry(NEW.id);
    end if;
    return NEW;
  else
    if v_old_posted then
      delete from public.journal_entries entry
      where entry.tenant_id = OLD.tenant_id
        and entry.source_module = 'expenses'
        and (
          entry.source_reference in (OLD.expense_number, OLD.id::text)
          or entry.source_document_id = OLD.id
        );
    end if;
    return OLD;
  end if;
end;
$$;

comment on function public.rebuild_expense_journal_entry(uuid) is
  'Atomically recalculates one expense and replaces its accrual journal inside one traced operation.';
comment on function public.begin_expense_row_trace() is
  'Starts tenant-scoped append-only traces for expense headers, lines, and payments.';
comment on function public.complete_expense_row_trace() is
  'Verifies expense totals, journals, zero stock side effects, and closes the active trace.';

commit;
