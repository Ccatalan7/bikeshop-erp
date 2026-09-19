-- A settlement applied before its marker is replayed, not refused.
--
-- Third pass of Codex's review (2026-09-19). 20260919160000 made the
-- adapter mark the allocations it converts with `settlement: true`, so the
-- payload the kernel hashes is no longer the one the caller sent. An
-- operation applied before that deploy — whose answer the client lost, the
-- case operation keys exist for — hashed the unmarked payload: repeating it
-- now reaches the kernel with the marked one and comes back as
-- `bank_reconciliation_idempotency_conflict`, with nothing the operator can
-- do about it.
--
--   * The adapter takes the kernel's own `:bank-reconciliation` lock before
--     reading the operation, so a retry never reads one mid-write.
--   * When the operation exists, its action is `apply_actions` and the
--     payload the caller sent hashes to the one stored, the adapter returns
--     the receipt it kept, marked `replayed`, without calling the kernel.
--     A receipt written before the adapter existed gains
--     `terminal_settlement_count` so the shape does not change.
--   * A different payload under the same key is still rejected, and so is
--     an operation that was not an apply.
--
-- Signature and privileges are unchanged.

create or replace function public.apply_bank_reconciliation_actions_v2(
  p_import_id uuid,
  p_expected_revision bigint,
  p_operation_key text,
  p_actions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_base_actions jsonb;
  v_receipt jsonb;
  v_action jsonb;
  v_allocation jsonb;
  v_row_id uuid;
  v_row_booking_date date;
  v_row_direction text;
  v_row_amount numeric(14,2);
  v_import_account_id uuid;
  v_profile_id uuid;
  v_profile_provider_name text;
  v_profile_terminal_name text;
  v_profile_clearing_account_id uuid;
  v_profile_commission_expense_account_id uuid;
  v_profile_settlement_account_id uuid;
  v_existing_id uuid;
  v_existing_terminal_profile_id uuid;
  v_existing_settlement_account_id uuid;
  v_existing_clearing_account_id uuid;
  v_existing_gross_sales_amount numeric(14,2);
  v_existing_bank_net_amount numeric(14,2);
  v_existing_journal_entry_id uuid;
  v_bank_account_id uuid;
  v_bank_account_code text;
  v_bank_account_name text;
  v_clearing_account_id uuid;
  v_clearing_account_code text;
  v_clearing_account_name text;
  v_profile_count integer;
  v_target_count integer;
  v_processor_count integer;
  v_gross numeric(14,2);
  v_journal_id uuid;
  v_settlement_id uuid;
  v_description text;
  v_settlement_count integer := 0;
  v_processor_total integer;
  v_source_payload_hash text;
  v_existing_source_payload_hash text;
  v_existing_action text;
  v_existing_receipt jsonb;
  v_operation_existed boolean := false;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_import_id is null or p_expected_revision is null
     or p_expected_revision <= 0 or p_operation_key is null
     or length(trim(p_operation_key)) not between 1 and 180
     or coalesce(jsonb_typeof(p_actions), 'null') <> 'array'
     or jsonb_array_length(p_actions) > 5000 then
    raise exception using errcode = '22023', message = 'bank_reconciliation_actions_invalid';
  end if;

  v_source_payload_hash := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'import_id', p_import_id,
      'expected_revision', p_expected_revision,
      'actions', p_actions
    )::text,
    'utf8'
  ), 'sha256'), 'hex');
  -- The same lock the kernel takes, so a retry never reads an operation
  -- another connection is still writing.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':bank-reconciliation', 0
  ));
  select operation.action, operation.source_payload_hash, operation.receipt
    into v_existing_action, v_existing_source_payload_hash, v_existing_receipt
    from public.bank_reconciliation_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  v_operation_existed := found;

  select count(*) into v_processor_total
    from jsonb_array_elements(p_actions) action(value)
    cross join lateral jsonb_array_elements(
           case
             when jsonb_typeof(action.value->'allocations') = 'array'
               then action.value->'allocations'
             else '[]'::jsonb
           end
         ) allocation(value)
   where allocation.value->>'match_kind' = 'processor_estimate';
  if v_operation_existed then
    if v_existing_action <> 'apply_actions'
       or (
         v_existing_source_payload_hash is not null
         and v_existing_source_payload_hash <> v_source_payload_hash
       )
       or (
         v_existing_source_payload_hash is null
         and v_processor_total > 0
       ) then
      raise exception using
        errcode = 'P0001',
        message = 'bank_reconciliation_idempotency_conflict';
    end if;
    -- Everything this operation did is already committed, and what the
    -- caller sent matches it. The kernel would hash the normalized actions
    -- and refuse a payload it stored before this adapter marked
    -- settlements, so the answer comes from the receipt it kept.
    update public.bank_reconciliation_operations operation
       set source_payload_hash = coalesce(
             operation.source_payload_hash, v_source_payload_hash
           )
     where operation.tenant_id = v_tenant_id
       and operation.operation_key = trim(p_operation_key);
    return (v_existing_receipt - 'replayed')
           || jsonb_build_object('replayed', true)
           || case
                when v_existing_receipt ? 'terminal_settlement_count'
                  then '{}'::jsonb
                else jsonb_build_object('terminal_settlement_count', 0)
              end;
  end if;

  select coalesce(jsonb_agg(
    case
      when action.value->>'action' = 'associate_existing' then
        jsonb_set(
          action.value,
          '{allocations}',
          coalesce((
            select jsonb_agg(
              case when allocation.value->>'match_kind' = 'processor_estimate'
                then jsonb_set(
                  allocation.value, '{match_kind}', '"manual"'::jsonb
                ) || jsonb_build_object('settlement', true)
                -- Only this adapter may call an allocation a settlement.
                else allocation.value - 'settlement'
              end
              order by allocation.ordinality
            )
              from jsonb_array_elements(
                coalesce(action.value->'allocations', '[]'::jsonb)
              ) with ordinality allocation(value, ordinality)
          ), '[]'::jsonb),
          true
        )
      else action.value
    end
    order by action.ordinality
  ), '[]'::jsonb)
    into v_base_actions
    from jsonb_array_elements(p_actions)
      with ordinality action(value, ordinality);

  v_receipt := public.apply_bank_reconciliation_actions_without_terminal_settlements(
    p_import_id, p_expected_revision, p_operation_key, v_base_actions
  );

  select imported.erp_account_id into v_import_account_id
    from public.bank_statement_imports imported
   where imported.tenant_id = v_tenant_id
     and imported.id = p_import_id;
  if not found then
    raise exception using errcode = '42501', message = 'bank_reconciliation_import_not_accessible';
  end if;
  select account.id, account.code, account.name
    into v_bank_account_id, v_bank_account_code, v_bank_account_name
    from public.accounts account
   where account.tenant_id = v_tenant_id
     and account.id = v_import_account_id
     and account.type = 'asset'
     and account.is_active;
  if not found then
    raise exception using errcode = '42501', message = 'bank_account_not_accessible';
  end if;

  for v_action in select value from jsonb_array_elements(p_actions)
  loop
    select count(*) into v_processor_count
      from jsonb_array_elements(
        coalesce(v_action->'allocations', '[]'::jsonb)
      ) allocation
     where allocation->>'match_kind' = 'processor_estimate';
    if v_processor_count = 0 then
      continue;
    end if;
    v_settlement_count := v_settlement_count + 1;
    if v_action->>'action' <> 'associate_existing'
       or v_processor_count <> jsonb_array_length(v_action->'allocations') then
      raise exception using
        errcode = '22023', message = 'processor_settlement_allocation_invalid';
    end if;

    select row.id, row.booking_date, row.direction, row.amount
      into v_row_id, v_row_booking_date, v_row_direction, v_row_amount
      from public.bank_statement_rows row
     where row.tenant_id = v_tenant_id
       and row.import_id = p_import_id
       and row.id = (v_action->>'row_id')::uuid;
    if not found or v_row_direction <> 'credit' or v_row_amount is null then
      raise exception using
        errcode = '22023', message = 'processor_settlement_row_invalid';
    end if;

    select count(distinct profile.id),
           count(*),
           (array_agg(distinct profile.id))[1],
           sum(payment.amount)
      into v_profile_count, v_target_count, v_profile_id, v_gross
      from jsonb_array_elements(v_action->'allocations') allocation
      join public.sales_payments payment
        on payment.tenant_id = v_tenant_id
       and payment.id = (allocation->>'target_id')::uuid
       and payment.deleted_at is null
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      join public.payment_terminal_profiles profile
        on profile.tenant_id = method.tenant_id
       and profile.id = method.terminal_profile_id
       and method.account_id = profile.clearing_account_id
     where allocation->>'target_kind' = 'sales_payment'
       and allocation->>'match_kind' = 'processor_estimate';
    if v_profile_count <> 1 or v_target_count <> v_processor_count then
      raise exception using
        errcode = '23514', message = 'processor_settlement_profile_mismatch';
    end if;
    select profile.provider_name, profile.terminal_name,
           profile.clearing_account_id,
           profile.commission_expense_account_id,
           profile.settlement_account_id
      into v_profile_provider_name, v_profile_terminal_name,
           v_profile_clearing_account_id,
           v_profile_commission_expense_account_id,
           v_profile_settlement_account_id
      from public.payment_terminal_profiles profile
     where profile.tenant_id = v_tenant_id
       and profile.id = v_profile_id;
    if not found
       or v_profile_settlement_account_id <> v_import_account_id
       or v_gross < v_row_amount then
      raise exception using
        errcode = '23514', message = 'processor_settlement_amount_invalid';
    end if;
    select account.id, account.code, account.name
      into v_clearing_account_id, v_clearing_account_code,
           v_clearing_account_name
      from public.accounts account
     where account.tenant_id = v_tenant_id
       and account.id = v_profile_clearing_account_id
       and account.type = 'asset'
       and account.is_active;
    if not found then
      raise exception using
        errcode = '23503', message = 'processor_clearing_account_invalid';
    end if;

    for v_allocation in
      select value from jsonb_array_elements(v_action->'allocations')
    loop
      update public.bank_reconciliation_allocations allocation
         set match_kind = 'processor_estimate'
       where allocation.tenant_id = v_tenant_id
         and allocation.import_id = p_import_id
         and allocation.row_id = v_row_id
         and allocation.target_kind = 'sales_payment'
         and allocation.target_id = (v_allocation->>'target_id')::uuid
         and allocation.match_kind in ('manual', 'processor_estimate');
      if not found then
        raise exception using
          errcode = '40001', message = 'processor_settlement_allocation_changed';
      end if;
    end loop;

    select settlement.id, settlement.terminal_profile_id,
           settlement.settlement_account_id, settlement.clearing_account_id,
           settlement.gross_sales_amount, settlement.bank_net_amount,
           settlement.journal_entry_id
      into v_existing_id, v_existing_terminal_profile_id,
           v_existing_settlement_account_id, v_existing_clearing_account_id,
           v_existing_gross_sales_amount, v_existing_bank_net_amount,
           v_existing_journal_entry_id
      from public.payment_terminal_settlements settlement
     where settlement.tenant_id = v_tenant_id
       and settlement.bank_statement_row_id = v_row_id;
    if found then
      if v_existing_terminal_profile_id <> v_profile_id
         or v_existing_settlement_account_id <> v_import_account_id
         or v_existing_clearing_account_id <> v_profile_clearing_account_id
         or v_existing_gross_sales_amount <> v_gross
         or v_existing_bank_net_amount <> v_row_amount then
        raise exception using
          errcode = '55000', message = 'processor_settlement_already_posted';
      end if;
      v_settlement_id := v_existing_id;
      v_journal_id := v_existing_journal_entry_id;
    else
      v_journal_id := gen_random_uuid();
      v_description := format(
        'Abono neto %s · %s', v_profile_provider_name,
        v_profile_terminal_name
      );
      insert into public.journal_entries (
        id, tenant_id, entry_number, entry_date, description, type,
        source_module, source_reference, status, total_debit, total_credit,
        created_by
      ) values (
        v_journal_id, v_tenant_id,
        public.get_next_document_number(v_tenant_id, 'journal_entry'),
        v_row_booking_date, v_description, 'payment',
        'payment_terminal_settlements', v_row_id::text, 'posted',
        v_row_amount, v_row_amount, v_user_id
      );
      insert into public.journal_lines (
        tenant_id, entry_id, account_id, account_code, account_name,
        description, debit_amount, credit_amount
      ) values
      (
        v_tenant_id, v_journal_id, v_bank_account_id,
        v_bank_account_code, v_bank_account_name, v_description,
        v_row_amount, 0
      ),
      (
        v_tenant_id, v_journal_id, v_clearing_account_id,
        v_clearing_account_code, v_clearing_account_name, v_description,
        0, v_row_amount
      );
      insert into public.payment_terminal_settlements (
        tenant_id, import_id, bank_statement_row_id, terminal_profile_id,
        settlement_account_id, clearing_account_id,
        commission_expense_account_id, gross_sales_amount, bank_net_amount,
        unresolved_deduction_amount, journal_entry_id, created_by
      ) values (
        v_tenant_id, p_import_id, v_row_id, v_profile_id,
        v_profile_settlement_account_id, v_profile_clearing_account_id,
        v_profile_commission_expense_account_id, v_gross, v_row_amount,
        v_gross - v_row_amount, v_journal_id, v_user_id
      ) returning id into v_settlement_id;
    end if;
    update public.bank_reconciliation_row_decisions decision
       set action_snapshot = decision.action_snapshot || jsonb_build_object(
         'terminal_settlement_id', v_settlement_id,
         'terminal_settlement_journal_id', v_journal_id,
         'terminal_profile_id', v_profile_id,
         'gross_sales_amount', v_gross,
         'bank_net_amount', v_row_amount,
         'unresolved_deduction_amount', v_gross - v_row_amount
       )
     where decision.tenant_id = v_tenant_id
       and decision.import_id = p_import_id
       and decision.row_id = v_row_id;
  end loop;

  v_receipt := v_receipt || jsonb_build_object(
    'terminal_settlement_count', v_settlement_count
  );
  update public.bank_reconciliation_operations operation
     set source_payload_hash = coalesce(
           operation.source_payload_hash, v_source_payload_hash
         ),
         receipt = case
           when not v_operation_existed
             then (v_receipt - 'replayed')
                  || jsonb_build_object('replayed', false)
           else operation.receipt
         end
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  if not found then
    raise exception using
      errcode = '40001', message = 'bank_reconciliation_operation_missing';
  end if;
  return v_receipt;
end;
$$;
