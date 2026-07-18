begin;

-- Durable command receipts make a lost RPC acknowledgement safely replayable.
create table if not exists public.expense_aggregate_save_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_key text not null,
  payload_hash text not null,
  expense_id uuid not null,
  expected_updated_at timestamptz not null,
  result_snapshot jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, operation_key)
);

create index if not exists idx_expense_aggregate_save_operations_expense
  on public.expense_aggregate_save_operations(
    tenant_id,
    expense_id,
    created_at desc
  );

alter table public.expense_aggregate_save_operations enable row level security;

drop policy if exists expense_aggregate_save_operations_select
  on public.expense_aggregate_save_operations;
create policy expense_aggregate_save_operations_select
  on public.expense_aggregate_save_operations
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.expense_aggregate_save_operations
  from public, anon, authenticated, service_role;
grant select on public.expense_aggregate_save_operations to authenticated;

-- A nested recalculate_expense_totals() updates the same expense row while the
-- outer expense trigger still owns the trace. Only the original trigger depth
-- may complete that root after process_expense_change() has replaced the
-- journal. Without this guard, posted header edits validate the old journal
-- too early and are rejected with an accrual-link mismatch.
do $$
declare
  v_definition text;
  v_old text := $needle$or v_operation_context->>'owner_table' is distinct from TG_TABLE_NAME then$needle$;
  v_new text := $replacement$or v_operation_context->>'owner_table' is distinct from TG_TABLE_NAME
     -- Only the owning trigger depth may finalize a same-table root.
     or coalesce(
       nullif(v_operation_context->>'trigger_depth', '')::integer,
       1
     ) <> pg_trigger_depth() then$replacement$;
  v_count integer;
begin
  select pg_get_functiondef(
    'public.complete_expense_row_trace()'::regprocedure
  ) into v_definition;

  if position('Only the owning trigger depth may finalize' in v_definition) > 0 then
    return;
  end if;

  v_count := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  if v_count <> 1 then
    raise exception
      'Expected one expense trace owner-table predicate, found %',
      v_count;
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$$;

create or replace function public.get_expense_aggregate_save_operation(
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_active_profile_count integer;
  v_operation public.expense_aggregate_save_operations%rowtype;
begin
  select count(*)::integer
  into v_active_profile_count
  from public.user_profiles profile
  where profile.user_id = v_actor_id
    and profile.is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select profile.tenant_id
  into v_tenant_id
  from public.user_profiles profile
  where profile.user_id = v_actor_id
    and profile.is_active is true;

  select *
  into v_operation
  from public.expense_aggregate_save_operations operation
  where operation.tenant_id = v_tenant_id
    and operation.operation_key = nullif(btrim(p_operation_key), '');

  if not found then
    return null;
  end if;

  return v_operation.result_snapshot || jsonb_build_object('replayed', true);
end;
$$;

create or replace function public.save_expense_aggregate(
  p_operation_key text,
  p_expense_id uuid,
  p_expected_updated_at timestamptz,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid;
  v_active_profile_count integer;
  v_operation_key text := nullif(btrim(p_operation_key), '');
  v_payload_hash text;
  v_receipt public.expense_aggregate_save_operations%rowtype;
  v_before public.expenses%rowtype;
  v_saved public.expenses%rowtype;
  v_saved_line public.expense_lines%rowtype;
  v_line_id uuid;
  v_line_count integer;
  v_operation_id uuid;
  v_document_type text;
  v_document_number text;
  v_issue_date timestamptz;
  v_supplier_id uuid;
  v_supplier_name text;
  v_supplier_rut text;
  v_category_id uuid;
  v_account_id uuid;
  v_account public.accounts%rowtype;
  v_payment_method_id uuid;
  v_payment_account_id uuid;
  v_method_account_id uuid;
  v_total numeric(14,2);
  v_net numeric(14,2);
  v_tax numeric(14,2);
  v_tax_rate numeric(7,3);
  v_description text;
  v_notes text;
  v_reference text;
  v_result jsonb;
begin
  select count(*)::integer
  into v_active_profile_count
  from public.user_profiles profile
  where profile.user_id = v_actor_id
    and profile.is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select profile.tenant_id
  into v_tenant_id
  from public.user_profiles profile
  where profile.user_id = v_actor_id
    and profile.is_active is true;

  if v_operation_key is null or length(v_operation_key) > 128 then
    raise exception 'A valid expense save operation key is required';
  end if;

  if p_expense_id is null or p_expected_updated_at is null then
    raise exception 'Expense id and expected updated_at are required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Expense payload must be an object';
  end if;

  if octet_length(p_payload::text) > 32768 then
    raise exception 'Expense payload exceeds the 32 KiB command limit';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_payload) key_name
    where key_name <> all (array[
      'category_id', 'supplier_id', 'supplier_name', 'supplier_rut',
      'document_type', 'document_number', 'issue_date',
      'payment_method_id', 'payment_account_id', 'notes', 'reference',
      'account_id', 'description', 'total_amount'
    ]::text[])
  ) then
    raise exception 'Expense payload contains unsupported or server-owned fields';
  end if;

  v_payload_hash := encode(extensions.digest(jsonb_build_object(
    'expense_id', p_expense_id,
    'expected_updated_at', p_expected_updated_at,
    'payload', p_payload
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_tenant_id::text || ':expense_aggregate:' || v_operation_key,
      0
    )
  );

  select *
  into v_receipt
  from public.expense_aggregate_save_operations operation
  where operation.tenant_id = v_tenant_id
    and operation.operation_key = v_operation_key;

  if found then
    if v_receipt.payload_hash is distinct from v_payload_hash then
      raise exception 'Expense save key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;
    return v_receipt.result_snapshot || jsonb_build_object('replayed', true);
  end if;

  select *
  into v_before
  from public.expenses expense
  where expense.id = p_expense_id
    and expense.tenant_id = v_tenant_id
  for update;

  if not found then
    raise exception 'Expense not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.updated_at is distinct from p_expected_updated_at then
    raise exception 'Expense was modified after this form was loaded'
      using errcode = 'serialization_failure';
  end if;

  if lower(coalesce(v_before.posting_status, 'draft')) not in ('draft', 'posted') then
    raise exception 'Voided expenses cannot be edited through this form'
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.expense_payments payment
    where payment.expense_id = v_before.id
      and payment.tenant_id = v_before.tenant_id
  ) then
    raise exception 'Expenses with explicit payments require the advanced payment workflow'
      using errcode = 'check_violation';
  end if;

  select
    count(*)::integer,
    (array_agg(line.id order by line.id))[1]
  into v_line_count, v_line_id
  from public.expense_lines line
  where line.expense_id = v_before.id
    and line.tenant_id = v_before.tenant_id;

  if v_line_count > 1 then
    raise exception 'Multi-line expenses cannot be flattened by the simple edit form'
      using errcode = 'check_violation';
  end if;

  v_document_type := lower(nullif(btrim(p_payload->>'document_type'), ''));
  if v_document_type not in ('invoice', 'receipt', 'ticket', 'reimbursement', 'other') then
    raise exception 'Unsupported expense document type';
  end if;

  v_total := nullif(p_payload->>'total_amount', '')::numeric;
  if v_total is null or v_total <= 0 then
    raise exception 'Expense total must be positive';
  end if;

  -- This form is CLP-only. Persist the same integer amounts shown to the user
  -- and printed on Chilean tax documents; never create hidden CLP centavos.
  v_total := round(v_total, 0);
  if v_document_type = 'invoice' then
    v_net := round(v_total / 1.19, 0);
    v_tax := v_total - v_net;
    v_tax_rate := 19;
  else
    v_net := v_total;
    v_tax := 0;
    v_tax_rate := 0;
  end if;

  v_account_id := nullif(p_payload->>'account_id', '')::uuid;
  select *
  into v_account
  from public.accounts account
  where account.id = v_account_id
    and account.tenant_id = v_tenant_id
    and account.type = 'expense'
    and account.is_active is true;
  if not found then
    raise exception 'Expense account not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  v_category_id := coalesce(
    nullif(p_payload->>'category_id', '')::uuid,
    v_before.category_id
  );
  if v_category_id is not null and not exists (
    select 1
    from public.expense_categories category
    where category.id = v_category_id
      and category.tenant_id = v_tenant_id
  ) then
    raise exception 'Expense category not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  v_supplier_id := nullif(p_payload->>'supplier_id', '')::uuid;
  if v_supplier_id is not null and not exists (
    select 1
    from public.suppliers supplier
    where supplier.id = v_supplier_id
      and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Expense supplier not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  v_payment_method_id := coalesce(
    nullif(p_payload->>'payment_method_id', '')::uuid,
    v_before.payment_method_id
  );
  select method.account_id
  into v_method_account_id
  from public.payment_methods method
  where method.id = v_payment_method_id
    and method.tenant_id = v_tenant_id
    and method.is_active is true;
  if not found then
    raise exception 'Payment method not found for current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  v_payment_account_id := coalesce(
    nullif(p_payload->>'payment_account_id', '')::uuid,
    v_method_account_id
  );
  if v_payment_account_id is distinct from v_method_account_id then
    raise exception 'Payment account does not match the selected payment method'
      using errcode = 'integrity_constraint_violation';
  end if;

  v_document_number := nullif(btrim(p_payload->>'document_number'), '');
  v_issue_date := coalesce(
    nullif(p_payload->>'issue_date', '')::timestamptz,
    v_before.issue_date
  );
  v_supplier_name := nullif(btrim(p_payload->>'supplier_name'), '');
  v_supplier_rut := nullif(btrim(p_payload->>'supplier_rut'), '');
  v_description := nullif(btrim(p_payload->>'description'), '');
  v_notes := nullif(btrim(p_payload->>'notes'), '');
  v_reference := nullif(btrim(p_payload->>'reference'), '');

  v_operation_id := public.begin_expense_accounting_operation(
    v_tenant_id,
    'expense',
    v_before.id,
    v_before.id,
    'expense_form',
    'aggregate_update',
    public.expense_accounting_trace_snapshot(to_jsonb(v_before)),
    null,
    jsonb_build_object(
      'trace_owner', 'rpc',
      'rpc', 'save_expense_aggregate',
      'command_operation_key', v_operation_key,
      'expected_updated_at', p_expected_updated_at
    ),
    'database_rpc'
  );
  perform set_config('app.journal_supersession_reason', 'expense_atomic_edit', true);

  -- Moving to draft removes and archives the single posted journal under the
  -- root operation. All subsequent writes share this transaction and trace.
  update public.expenses expense
  set category_id = v_category_id,
      supplier_id = v_supplier_id,
      supplier_name = v_supplier_name,
      supplier_rut = v_supplier_rut,
      document_type = v_document_type,
      document_number = v_document_number,
      issue_date = v_issue_date,
      posting_status = 'draft',
      payment_status = 'paid',
      subtotal = v_net,
      tax_amount = v_tax,
      total_amount = v_total,
      amount_paid = v_total,
      balance = 0,
      notes = v_notes,
      reference = v_reference,
      payment_method_id = v_payment_method_id,
      payment_account_id = v_payment_account_id,
      paid_at = coalesce(v_before.paid_at, v_issue_date),
      posted_at = coalesce(v_before.posted_at, v_issue_date),
      updated_at = clock_timestamp()
  where expense.id = v_before.id
    and expense.tenant_id = v_before.tenant_id;

  if v_line_id is null then
    v_line_id := gen_random_uuid();
    insert into public.expense_lines (
      id, tenant_id, expense_id, line_index, account_id, account_code,
      account_name, description, quantity, unit_price, subtotal, tax_rate,
      tax_amount, total
    ) values (
      v_line_id, v_tenant_id, v_before.id, 0, v_account.id, v_account.code,
      v_account.name, v_description, 1, v_net, v_net, v_tax_rate,
      v_tax, v_total
    );
  else
    update public.expense_lines line
    set line_index = 0,
        account_id = v_account.id,
        account_code = v_account.code,
        account_name = v_account.name,
        description = v_description,
        quantity = 1,
        unit_price = v_net,
        subtotal = v_net,
        tax_rate = v_tax_rate,
        tax_amount = v_tax,
        total = v_total,
        updated_at = now()
    where line.id = v_line_id
      and line.expense_id = v_before.id
      and line.tenant_id = v_tenant_id;
  end if;

  -- The draft-to-posted transition recalculates from the saved line and emits
  -- exactly one replacement journal linked to this root operation.
  update public.expenses expense
  set posting_status = 'posted',
      updated_at = clock_timestamp()
  where expense.id = v_before.id
    and expense.tenant_id = v_before.tenant_id;

  select * into v_saved
  from public.expenses expense
  where expense.id = v_before.id;

  select * into v_saved_line
  from public.expense_lines line
  where line.id = v_line_id;

  update public.inventory_accounting_operations operation
  set after_snapshot = public.expense_accounting_trace_snapshot(to_jsonb(v_saved)),
      context = operation.context || jsonb_build_object(
        'line_after', jsonb_strip_nulls(to_jsonb(v_saved_line)),
        'clp_rounding', 'integer_document_amounts'
      )
  where operation.id = v_operation_id
    and operation.tenant_id = v_tenant_id;

  perform public.complete_expense_accounting_operation(
    v_operation_id,
    v_tenant_id,
    v_saved.id,
    null,
    1,
    0,
    true,
    false,
    false,
    v_saved.expense_number
  );

  v_result := jsonb_build_object(
    'expense', to_jsonb(v_saved),
    'line', to_jsonb(v_saved_line),
    'operation_id', v_operation_id,
    'replayed', false
  );

  insert into public.expense_aggregate_save_operations (
    tenant_id,
    operation_key,
    payload_hash,
    expense_id,
    expected_updated_at,
    result_snapshot,
    created_by
  ) values (
    v_tenant_id,
    v_operation_key,
    v_payload_hash,
    v_saved.id,
    p_expected_updated_at,
    v_result,
    v_actor_id
  );

  return v_result;
exception
  when others then
    perform set_config('app.inventory_operation_id', '', true);
    perform set_config('app.inventory_source_document_type', '', true);
    perform set_config('app.inventory_source_document_id', '', true);
    perform set_config('app.inventory_source_channel', '', true);
    perform set_config('app.journal_supersession_reason', '', true);
    raise;
end;
$$;

revoke all on function public.get_expense_aggregate_save_operation(text)
  from public, anon, service_role;
revoke all on function public.save_expense_aggregate(
  text, uuid, timestamptz, jsonb
) from public, anon, service_role;

grant execute on function public.get_expense_aggregate_save_operation(text)
  to authenticated;
grant execute on function public.save_expense_aggregate(
  text, uuid, timestamptz, jsonb
) to authenticated;

comment on function public.save_expense_aggregate(text, uuid, timestamptz, jsonb) is
  'Atomically edits one simple expense, archives its previous posted journal, persists integer CLP tax amounts, and returns an idempotent command receipt.';

commit;
