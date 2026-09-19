-- Finish a statement later, and never settle a movement twice.
--
-- An apply used to replace a statement's whole review and refused one that
-- had created an expense, a journal or a payment, so whatever it left
-- pending could never be resolved; the review page said the opposite. And
-- nothing recognised a movement that an overlapping statement had already
-- settled: a September statement cut on the 17th, applied, and the full
-- month loaded later would have offered the 1st to the 17th again.
--
--   * apply_bank_reconciliation_actions_without_terminal_settlements (the
--     kernel behind v2 and v3) keeps every decided row as it is and applies
--     exactly the rows still open. A decided row in the payload is refused.
--   * A row whose date, direction, amount and running balance match a row
--     another statement of the same account already decided cannot be
--     associated, booked or classified again; it can be dismissed with
--     `settled_elsewhere`, which the kernel proves before recording.
--   * get_bank_reconciliation_candidates_v2 no longer offers operations a
--     row already explains, returns `reconciled_rows` for the statement's
--     dates, and does not learn from those settled-elsewhere dismissals.
--
-- Signatures and privileges are unchanged.

create index if not exists idx_bank_statement_rows_settlement_key
  on public.bank_statement_rows(tenant_id, booking_date, direction, amount, balance);

create or replace function public.apply_bank_reconciliation_actions_without_terminal_settlements(
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
  v_import record;
  v_existing record;
  v_payload_hash text;
  v_action jsonb;
  v_action_code text;
  v_allocation jsonb;
  v_row record;
  v_target jsonb;
  v_target_kind text;
  v_target_id uuid;
  v_account record;
  v_method record;
  v_bank_account record;
  v_expense_id uuid;
  v_expense_payment_id uuid;
  v_expense_number text;
  v_journal_id uuid;
  v_description text;
  v_reference text;
  v_disposition text;
  v_generated_kind text;
  v_generated_id uuid;
  v_action_snapshot jsonb;
  v_status text;
  v_revision bigint;
  v_allocation_count integer;
  v_created_expense_count integer := 0;
  v_created_journal_count integer := 0;
  v_receipt jsonb;
  v_settled_elsewhere boolean;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_import_id is null or p_expected_revision is null or p_expected_revision <= 0
     or p_operation_key is null
     or length(trim(p_operation_key)) not between 1 and 180
     or coalesce(jsonb_typeof(p_actions), 'null') <> 'array'
     or jsonb_array_length(p_actions) > 5000 then
    raise exception using errcode = '22023', message = 'bank_reconciliation_payload_invalid';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'import_id', p_import_id,
    'expected_revision', p_expected_revision,
    'actions', p_actions
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
    if v_existing.action <> 'apply_actions'
       or v_existing.payload_hash <> v_payload_hash then
      raise exception using errcode = 'P0001', message = 'bank_reconciliation_idempotency_conflict';
    end if;
    return v_existing.receipt || jsonb_build_object('replayed', true);
  end if;

  select imported.id, imported.revision, imported.erp_account_id
    into v_import
    from public.bank_statement_imports imported
   where imported.tenant_id = v_tenant_id
     and imported.id = p_import_id
   for update;
  if not found then
    raise exception using errcode = '42501', message = 'bank_statement_import_not_accessible';
  end if;
  if v_import.revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'bank_reconciliation_revision_conflict';
  end if;
  -- A decided row is final: what an earlier apply settled stays settled, and
  -- a later apply covers exactly the rows still open. Before 2026-09-19 an
  -- apply replaced the whole statement and refused one that had created
  -- anything, so a movement left pending could never be resolved.
  if exists (
    select 1
      from jsonb_array_elements(p_actions) action
      join public.bank_reconciliation_row_decisions decision
        on decision.tenant_id = v_tenant_id
       and decision.import_id = v_import.id
       and decision.row_id::text = action->>'row_id'
     where decision.disposition <> 'pending'
  ) then
    raise exception using errcode = '55000', message = 'bank_reconciliation_row_already_decided';
  end if;
  if jsonb_array_length(p_actions) <> (
    select count(*) from public.bank_statement_rows row
     where row.import_id = v_import.id
       and not exists (
         select 1
           from public.bank_reconciliation_row_decisions decision
          where decision.tenant_id = v_tenant_id
            and decision.import_id = v_import.id
            and decision.row_id = row.id
            and decision.disposition <> 'pending'
       )
  ) or exists (
    select 1
      from jsonb_array_elements(p_actions) action
     group by action->>'row_id'
    having count(*) <> 1
  ) then
    raise exception using errcode = '22023', message = 'bank_reconciliation_action_coverage_invalid';
  end if;

  select account.id, account.code, account.name
    into v_bank_account
    from public.accounts account
   where account.tenant_id = v_tenant_id
     and account.id = v_import.erp_account_id
     and account.type = 'asset'
     and account.is_active;
  if not found then
    raise exception using errcode = '42501', message = 'bank_account_not_accessible';
  end if;

  delete from public.bank_reconciliation_allocations allocation
   where allocation.tenant_id = v_tenant_id
     and allocation.import_id = v_import.id
     and not exists (
       select 1
         from public.bank_reconciliation_row_decisions decision
        where decision.tenant_id = v_tenant_id
          and decision.import_id = v_import.id
          and decision.row_id = allocation.row_id
          and decision.disposition <> 'pending'
     );
  delete from public.bank_reconciliation_row_decisions decision
   where decision.tenant_id = v_tenant_id
     and decision.import_id = v_import.id
     and decision.disposition = 'pending';

  for v_action in select value from jsonb_array_elements(p_actions)
  loop
    if jsonb_typeof(v_action) <> 'object'
       or coalesce(v_action->>'action', '') not in (
         'pending', 'associate_existing', 'create_expense', 'post_journal',
         'dismiss'
       ) then
      raise exception using errcode = '22023', message = 'bank_reconciliation_action_invalid';
    end if;
    select row.id, row.amount, row.direction, row.booking_date,
           row.description, row.counterparty_observed, row.document_number,
           row.balance
      into v_row
      from public.bank_statement_rows row
     where row.tenant_id = v_tenant_id
       and row.import_id = v_import.id
       and row.id = (v_action->>'row_id')::uuid;
    if not found then
      raise exception using errcode = '22023', message = 'bank_reconciliation_row_invalid';
    end if;

    v_action_code := v_action->>'action';

    -- Overlapping statements repeat a movement with the same date, amount
    -- and running balance. One that another statement of this account
    -- already settled is not settled again: only recorded as that.
    v_settled_elsewhere := v_row.balance is not null and exists (
      select 1
        from public.bank_statement_rows other_row
        join public.bank_statement_imports other_import
          on other_import.tenant_id = other_row.tenant_id
         and other_import.id = other_row.import_id
        join public.bank_reconciliation_row_decisions other_decision
          on other_decision.tenant_id = other_row.tenant_id
         and other_decision.row_id = other_row.id
       where other_row.tenant_id = v_tenant_id
         and other_row.import_id <> v_import.id
         and other_import.erp_account_id = v_import.erp_account_id
         and other_row.booking_date = v_row.booking_date
         and other_row.direction = v_row.direction
         and other_row.amount = v_row.amount
         and other_row.balance = v_row.balance
         and other_decision.disposition <> 'pending'
    );
    if v_settled_elsewhere
       and v_action_code in ('associate_existing', 'create_expense', 'post_journal') then
      raise exception using errcode = '55000', message = 'bank_reconciliation_row_settled_elsewhere';
    end if;
    v_disposition := 'pending';
    v_generated_kind := null;
    v_generated_id := null;
    v_action_snapshot := '{}'::jsonb;

    if v_action_code = 'associate_existing' then
      if coalesce(jsonb_typeof(v_action->'allocations'), 'null') <> 'array'
         or jsonb_array_length(v_action->'allocations') not between 1 and 100 then
        raise exception using errcode = '22023', message = 'bank_reconciliation_allocation_invalid';
      end if;
      for v_allocation in
        select value from jsonb_array_elements(v_action->'allocations')
      loop
        if jsonb_typeof(v_allocation) <> 'object'
           or (v_allocation->>'row_id')::uuid <> v_row.id
           or coalesce(v_allocation->>'target_kind', '') not in (
             'sales_payment', 'purchase_payment', 'expense_payment', 'expense',
             'journal_entry'
           )
           or coalesce(v_allocation->>'match_kind', '') not in (
             'direct', 'transbank_estimate', 'manual'
           )
           or coalesce(v_allocation->>'confidence', '') not in (
             'low', 'medium', 'high'
           )
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
        v_target_kind := v_allocation->>'target_kind';
        v_target_id := (v_allocation->>'target_id')::uuid;
        v_target := public.bank_reconciliation_target_snapshot(
          v_tenant_id, v_import.erp_account_id, v_target_kind, v_target_id
        );
        if v_target is null then
          raise exception using errcode = '42501', message = 'bank_reconciliation_target_not_accessible';
        end if;
        if v_target->>'direction' <> v_row.direction
           or (v_target->>'amount')::numeric
             <> (v_allocation->>'target_amount')::numeric
           or coalesce(v_target->>'provider', 'none')
             <> v_allocation->>'provider'
           or coalesce(v_target->>'instrument', 'unknown')
             <> v_allocation->>'instrument'
           or (
             v_allocation->>'match_kind' = 'transbank_estimate'
             and coalesce(v_target->>'provider', 'none') <> 'transbank'
           ) then
          raise exception using errcode = '40001', message = 'bank_reconciliation_target_changed';
        end if;
        if exists (
          select 1 from public.bank_reconciliation_allocations existing
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
          v_tenant_id, v_import.id, v_row.id, v_target_kind, v_target_id,
          (v_allocation->>'bank_amount')::numeric,
          (v_allocation->>'target_amount')::numeric,
          v_allocation->>'match_kind', v_allocation->>'confidence',
          v_allocation->>'provider', v_allocation->>'instrument',
          coalesce(v_allocation->'rationale', '{}'::jsonb), v_user_id
        );
      end loop;
      if coalesce((
        select sum(allocation.bank_amount)
          from public.bank_reconciliation_allocations allocation
         where allocation.row_id = v_row.id
      ), 0) <> v_row.amount then
        raise exception using errcode = '23514', message = 'bank_reconciliation_row_not_fully_allocated';
      end if;
      v_disposition := 'reconciled';
      v_action_snapshot := jsonb_build_object(
        'allocation_count', jsonb_array_length(v_action->'allocations')
      );

    elsif v_action_code = 'create_expense' then
      if v_row.direction <> 'debit' or v_row.amount is null
         or v_row.booking_date is null
         or coalesce(jsonb_typeof(v_action->'expense'), 'null') <> 'object'
         or length(trim(coalesce(v_action->'expense'->>'description', '')))
              not between 2 and 500 then
        raise exception using errcode = '22023', message = 'bank_reconciliation_expense_invalid';
      end if;
      select account.id, account.code, account.name, account.type
        into v_account
        from public.accounts account
       where account.tenant_id = v_tenant_id
         and account.id = (v_action->'expense'->>'account_id')::uuid
         and account.type = 'expense'
         and account.is_active;
      if not found then
        raise exception using errcode = '42501', message = 'bank_reconciliation_expense_account_invalid';
      end if;
      select method.id, method.code, method.name, method.account_id
        into v_method
        from public.payment_methods method
       where method.tenant_id = v_tenant_id
         and method.id = (v_action->'expense'->>'payment_method_id')::uuid
         and method.account_id = v_import.erp_account_id
         and method.is_active;
      if not found then
        raise exception using errcode = '42501', message = 'bank_reconciliation_payment_method_invalid';
      end if;

      v_expense_id := gen_random_uuid();
      v_description := trim(v_action->'expense'->>'description');
      v_reference := nullif(trim(coalesce(
        v_action->'expense'->>'reference', v_row.document_number, ''
      )), '');
      insert into public.expenses (
        id, tenant_id, expense_number, supplier_name, document_type,
        document_number, issue_date, due_date, currency, posting_status,
        payment_status, subtotal, tax_amount, total_amount, amount_paid,
        balance, notes, reference, approval_status, approved_by, approved_at,
        payment_account_id, payment_method_id, created_by
      ) values (
        v_expense_id, v_tenant_id, '',
        nullif(trim(coalesce(v_action->'expense'->>'supplier_name', '')), ''),
        'other', v_reference,
        ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
        ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
        'CLP', 'draft', 'pending', 0, 0, 0, 0, 0,
        v_description, v_reference, 'approved', v_user_id, now(),
        v_import.erp_account_id, v_method.id, v_user_id
      );
      insert into public.expense_lines (
        tenant_id, expense_id, line_index, account_id, account_code,
        account_name, description, quantity, unit_price, subtotal, tax_rate,
        tax_amount, total
      ) values (
        v_tenant_id, v_expense_id, 0, v_account.id, v_account.code,
        v_account.name, v_description, 1, v_row.amount, v_row.amount, 0, 0,
        v_row.amount
      );
      update public.expenses expense
         set posting_status = 'posted',
             approval_status = 'approved', approved_by = v_user_id,
             approved_at = coalesce(expense.approved_at, now()),
             posted_at = coalesce(
               expense.posted_at,
               ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC')
             ),
             updated_at = now()
       where expense.id = v_expense_id;
      insert into public.expense_payments (
        tenant_id, expense_id, payment_method_id, payment_account_id,
        amount, payment_date, reference, notes
      ) values (
        v_tenant_id, v_expense_id, v_method.id, v_import.erp_account_id,
        v_row.amount,
        ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
        v_reference, 'Creado desde conciliación bancaria'
      ) returning id into v_expense_payment_id;
      select expense.expense_number into v_expense_number
        from public.expenses expense where expense.id = v_expense_id;

      insert into public.bank_reconciliation_allocations (
        tenant_id, import_id, row_id, target_kind, target_id, bank_amount,
        target_amount, match_kind, confidence, provider, instrument,
        rationale, created_by
      ) values (
        v_tenant_id, v_import.id, v_row.id, 'expense_payment',
        v_expense_payment_id,
        v_row.amount, v_row.amount, 'manual', 'high', 'none', 'unknown',
        jsonb_build_object('action', 'create_expense'), v_user_id
      );
      v_disposition := 'reconciled';
      v_generated_kind := 'expense';
      v_generated_id := v_expense_id;
      v_created_expense_count := v_created_expense_count + 1;
      v_action_snapshot := jsonb_build_object(
        'account_id', v_account.id,
        'payment_method_id', v_method.id,
        'expense_number', v_expense_number,
        'expense_payment_id', v_expense_payment_id
      );

    elsif v_action_code = 'post_journal' then
      if v_row.direction not in ('debit', 'credit') or v_row.amount is null
         or v_row.booking_date is null
         or coalesce(jsonb_typeof(v_action->'journal'), 'null') <> 'object'
         or length(trim(coalesce(v_action->'journal'->>'description', '')))
              not between 2 and 500 then
        raise exception using errcode = '22023', message = 'bank_reconciliation_journal_invalid';
      end if;
      select account.id, account.code, account.name, account.type
        into v_account
        from public.accounts account
       where account.tenant_id = v_tenant_id
         and account.id = (v_action->'journal'->>'counterpart_account_id')::uuid
         and account.id <> v_import.erp_account_id
         and account.is_active;
      if not found then
        raise exception using errcode = '42501', message = 'bank_reconciliation_counterpart_account_invalid';
      end if;

      v_journal_id := gen_random_uuid();
      v_description := trim(v_action->'journal'->>'description');
      v_reference := nullif(trim(coalesce(
        v_action->'journal'->>'reference', v_row.document_number, ''
      )), '');
      insert into public.journal_entries (
        id, tenant_id, entry_number, entry_date, description, type,
        source_module, source_reference, status, total_debit, total_credit,
        created_by
      ) values (
        v_journal_id, v_tenant_id,
        public.get_next_document_number(v_tenant_id, 'journal_entry'),
        ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
        v_description, 'adjustment', 'bank_reconciliation',
        coalesce(v_reference, v_row.id::text), 'posted', v_row.amount,
        v_row.amount, v_user_id
      );
      insert into public.journal_lines (
        tenant_id, entry_id, account_id, account_code, account_name,
        description, debit_amount, credit_amount
      ) values
      (
        v_tenant_id, v_journal_id,
        case when v_row.direction = 'credit' then v_bank_account.id else v_account.id end,
        case when v_row.direction = 'credit' then v_bank_account.code else v_account.code end,
        case when v_row.direction = 'credit' then v_bank_account.name else v_account.name end,
        v_description,
        case when v_row.direction = 'credit' then v_row.amount else 0 end,
        case when v_row.direction = 'debit' then v_row.amount else 0 end
      ),
      (
        v_tenant_id, v_journal_id,
        case when v_row.direction = 'credit' then v_account.id else v_bank_account.id end,
        case when v_row.direction = 'credit' then v_account.code else v_bank_account.code end,
        case when v_row.direction = 'credit' then v_account.name else v_bank_account.name end,
        v_description,
        case when v_row.direction = 'debit' then v_row.amount else 0 end,
        case when v_row.direction = 'credit' then v_row.amount else 0 end
      );

      insert into public.bank_reconciliation_allocations (
        tenant_id, import_id, row_id, target_kind, target_id, bank_amount,
        target_amount, match_kind, confidence, provider, instrument,
        rationale, created_by
      ) values (
        v_tenant_id, v_import.id, v_row.id, 'journal_entry', v_journal_id,
        v_row.amount, v_row.amount, 'manual', 'high', 'none', 'unknown',
        jsonb_build_object('action', 'post_journal'), v_user_id
      );
      v_disposition := 'reconciled';
      v_generated_kind := 'journal_entry';
      v_generated_id := v_journal_id;
      v_created_journal_count := v_created_journal_count + 1;
      v_action_snapshot := jsonb_build_object(
        'counterpart_account_id', v_account.id,
        'reference', v_reference
      );

    elsif v_action_code = 'dismiss' then
      if length(trim(coalesce(v_action->>'reason', ''))) not between 3 and 500 then
        raise exception using errcode = '22023', message = 'bank_reconciliation_dismiss_reason_required';
      end if;
      if coalesce(v_action->>'settled_elsewhere', 'false') = 'true'
         and not v_settled_elsewhere then
        raise exception using errcode = '23514', message = 'bank_reconciliation_settled_elsewhere_unproven';
      end if;
      v_disposition := 'ignored';
      v_action_snapshot := jsonb_build_object('reason', trim(v_action->>'reason'))
        || case when coalesce(v_action->>'settled_elsewhere', 'false') = 'true'
             then jsonb_build_object('settled_elsewhere', true)
             else '{}'::jsonb
           end;
    end if;

    insert into public.bank_reconciliation_row_decisions (
      tenant_id, import_id, row_id, disposition, action_kind, note,
      generated_target_kind, generated_target_id, action_snapshot, decided_by
    ) values (
      v_tenant_id, v_import.id, v_row.id, v_disposition, v_action_code,
      case when v_action_code = 'dismiss' then trim(v_action->>'reason') else null end,
      v_generated_kind, v_generated_id, v_action_snapshot, v_user_id
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

  select case
    when bool_and(decision.disposition = 'reconciled')
      then 'reconciled'
    when bool_or(decision.disposition in ('reconciled', 'ignored', 'held'))
      then 'partially_reconciled'
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
    'operation', 'apply_actions',
    'operation_key', trim(p_operation_key),
    'payload_hash', v_payload_hash,
    'replayed', false,
    'import_id', v_import.id,
    'revision', v_revision,
    'status', coalesce(v_status, 'review'),
    'allocation_count', v_allocation_count,
    'created_expense_count', v_created_expense_count,
    'created_journal_count', v_created_journal_count
  );
  insert into public.bank_reconciliation_operations (
    tenant_id, import_id, operation_key, action, payload_hash, receipt,
    created_by
  ) values (
    v_tenant_id, v_import.id, trim(p_operation_key), 'apply_actions',
    v_payload_hash, v_receipt, v_user_id
  );
  return v_receipt;
end;
$$;

revoke all on function
  public.apply_bank_reconciliation_actions_without_terminal_settlements(
    uuid, bigint, text, jsonb
  ) from public, anon, authenticated, service_role;

comment on function
  public.apply_bank_reconciliation_actions_without_terminal_settlements(
    uuid, bigint, text, jsonb
  ) is
  'Applies the open rows of one bank-statement review atomically. Decided rows are final; a movement another statement of the account already settled can only be dismissed as such. Generated expenses and journals are posted before their immutable evidence allocation is persisted.';

create or replace function public.get_bank_reconciliation_candidates_v2(
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
  v_base jsonb;
  v_candidates jsonb;
  v_payroll_lines jsonb;
  v_open_sales jsonb;
  v_open_purchases jsonb;
  v_parties jsonb;
  v_decisions jsonb;
  v_open_advances jsonb;
  v_reconciled_rows jsonb;
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;

  -- v1 validates the range and the bank account and owns eligibility.
  v_base := public.get_bank_reconciliation_candidates_v1(
    p_erp_account_id, p_from_date, p_to_date
  );

  with base as (
    select item.value as candidate
      from jsonb_array_elements(coalesce(v_base->'candidates', '[]'::jsonb)) item
  ), payment_ids as (
    select base.candidate->>'target_id' as target_id
      from base
     where base.candidate->>'target_kind' <> 'journal_entry'
  ), kept as (
    select base.candidate
      from base
      left join public.journal_entries entry
        on base.candidate->>'target_kind' = 'journal_entry'
       and entry.tenant_id = v_tenant_id
       and entry.id = (base.candidate->>'target_id')::uuid
     where (
          entry.id is null
          or not (
            coalesce(entry.source_module, '') in (
              'sales_payments', 'purchase_payments', 'expense_payments',
              'payment_terminal_settlements'
            )
            or coalesce(entry.source_reference, '') in (
              select payment_ids.target_id from payment_ids
            )
          )
        )
       -- An operation a statement row already explains is not offered again.
       and not exists (
         select 1
           from public.bank_reconciliation_allocations allocation
          where allocation.tenant_id = v_tenant_id
            and allocation.target_kind = base.candidate->>'target_kind'
            and allocation.target_id::text = base.candidate->>'target_id'
       )
  )
  select coalesce(jsonb_agg(
    kept.candidate || public.bank_reconciliation_candidate_identity(
      v_tenant_id,
      kept.candidate->>'target_kind',
      (kept.candidate->>'target_id')::uuid
    )
    order by kept.candidate->>'occurred_on', kept.candidate->>'target_id'
  ), '[]'::jsonb)
    into v_candidates
    from kept;

  -- Payroll lines Nómina still owes. Confirming a week books each line's
  -- expense, so "owed" is the balance (total minus payments and applied
  -- advances, as pay_payroll_voucher_v2 computes it), not "a line without
  -- an expense": the first catalog lost every confirmed, unpaid week. Status
  -- and version let the review pay the line through Nómina's own command.
  with owed as (
    select voucher.id as voucher_id,
           voucher.voucher_number,
           voucher.period_label,
           voucher.period_start,
           voucher.period_end,
           voucher.status,
           voucher.reconciliation_version,
           line.id as line_id,
           line.employee_id,
           coalesce(
             nullif(btrim(coalesce(line.employee_name, '')), ''),
             concat_ws(' ', employee.first_name, employee.last_name)
           ) as employee_name,
           line.employee_name as line_employee_name,
           line.total_amount,
           line.payment_method,
           line.payment_method_id,
           line.payment_account_id,
           line.total_amount
             - coalesce((
                 select sum(payment.amount)
                   from public.expense_payments payment
                  where payment.tenant_id = line.tenant_id
                    and line.expense_id is not null
                    and payment.expense_id = line.expense_id
               ), 0)
             - coalesce((
                 select sum(allocation.amount)
                   from public.employee_advance_allocations allocation
                  where allocation.tenant_id = line.tenant_id
                    and allocation.voucher_line_id = line.id
               ), 0) as balance
      from public.payroll_vouchers voucher
      join public.payroll_voucher_lines line
        on line.tenant_id = voucher.tenant_id
       and line.voucher_id = voucher.id
      left join public.employees employee
        on employee.tenant_id = line.tenant_id
       and employee.id = line.employee_id
     where voucher.tenant_id = v_tenant_id
       and voucher.status in ('draft', 'confirmed', 'partial')
       and line.is_included
       and line.total_amount > 0
       and voucher.period_end between p_from_date - 45 and p_to_date
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'voucher_id', owed.voucher_id,
    'voucher_number', owed.voucher_number,
    'period_label', owed.period_label,
    'period_start', owed.period_start,
    'period_end', owed.period_end,
    'status', owed.status,
    'reconciliation_version', owed.reconciliation_version,
    -- The first day Nómina takes the money as this week's salary: its
    -- operational close (Saturday for a Sunday close). Earlier money is an
    -- advance, and pay_payroll_voucher_v2 refuses it as a salary.
    'payable_from', public.payroll_period_operational_close_date(
      v_tenant_id, owed.period_start, owed.period_end
    ),
    'line_id', owed.line_id,
    'employee_id', owed.employee_id,
    'employee_name', owed.employee_name,
    'counterparty_names', public.bank_reconciliation_employee_names(
      v_tenant_id, owed.employee_id, array[owed.line_employee_name]
    ),
    'amount', owed.balance,
    'total', owed.total_amount,
    'payment_method', owed.payment_method,
    'payment_method_id', owed.payment_method_id,
    'payment_account_id', owed.payment_account_id
  ) order by owed.period_end, owed.employee_name), '[]'::jsonb)
    into v_payroll_lines
    from owed
   where owed.balance > 0;

  select coalesce(jsonb_agg(jsonb_build_object(
    'invoice_id', invoice.id,
    'invoice_number', invoice.invoice_number,
    'date', invoice.date::date,
    'status', invoice.status,
    'total', invoice.total,
    'balance', invoice.balance,
    'counterparty_id', invoice.customer_id,
    'counterparty_names', public.bank_reconciliation_name_list(
      array[invoice.customer_name, customer.name]
    )
  ) order by invoice.date, invoice.invoice_number), '[]'::jsonb)
    into v_open_sales
    from public.sales_invoices invoice
    left join public.customers customer
      on customer.tenant_id = invoice.tenant_id
     and customer.id = invoice.customer_id
   where invoice.tenant_id = v_tenant_id
     and coalesce(invoice.balance, 0) > 0
     and invoice.status not in ('draft', 'cancelled', 'cancelado', 'voided', 'void')
     and invoice.date::date between p_from_date - 90 and p_to_date;

  select coalesce(jsonb_agg(jsonb_build_object(
    'invoice_id', invoice.id,
    'invoice_number', invoice.invoice_number,
    'supplier_invoice_number', invoice.supplier_invoice_number,
    'date', invoice.date::date,
    'status', invoice.status,
    'total', invoice.total,
    'balance', invoice.balance,
    'counterparty_id', invoice.supplier_id,
    'counterparty_names', public.bank_reconciliation_name_list(
      array[
        invoice.supplier_name, supplier.name, supplier.legal_name,
        supplier.trade_name, supplier.owner_name
      ] || coalesce(supplier.aliases, array[]::text[])
    )
  ) order by invoice.date, invoice.invoice_number), '[]'::jsonb)
    into v_open_purchases
    from public.purchase_invoices invoice
    left join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
   where invoice.tenant_id = v_tenant_id
     and (
       coalesce(invoice.balance, 0) > 0
       or invoice.status = 'draft'
     )
     and invoice.status not in ('cancelled', 'cancelado', 'voided', 'void')
     and invoice.date::date between p_from_date - 120 and p_to_date;

  -- Who the tenant usually pays, and which expense account each one used.
  with usage as (
    select
      case when expense.supplier_id is not null then 'supplier' else 'payee' end as kind,
      coalesce(expense.supplier_id::text, lower(btrim(expense.supplier_name))) as party_key,
      line.account_id,
      method.code as payment_method_code,
      count(*) as uses,
      max(expense.issue_date) as last_used_at,
      (array_agg(
        coalesce(nullif(btrim(expense.notes), ''), line.description)
        order by expense.issue_date desc
      ))[1] as last_description
      from public.expenses expense
      join public.expense_lines line
        on line.tenant_id = expense.tenant_id
       and line.expense_id = expense.id
      left join public.payment_methods method
        on method.tenant_id = expense.tenant_id
       and method.id = expense.payment_method_id
     where expense.tenant_id = v_tenant_id
       and expense.issue_date >= (p_to_date - 540)
       and (
         expense.supplier_id is not null
         or nullif(btrim(coalesce(expense.supplier_name, '')), '') is not null
       )
       and not exists (
         select 1 from public.payroll_voucher_lines payroll_line
          where payroll_line.tenant_id = expense.tenant_id
            and payroll_line.expense_id = expense.id
       )
     group by 1, 2, 3, 4
  ), usage_by_party as (
    select usage.kind, usage.party_key,
           jsonb_agg(jsonb_build_object(
             'account_id', usage.account_id,
             'payment_method_code', usage.payment_method_code,
             'uses', usage.uses,
             'last_used_at', usage.last_used_at,
             'last_description', usage.last_description
           ) order by usage.uses desc, usage.last_used_at desc) as usual
      from usage
     group by usage.kind, usage.party_key
  ), purchase_counts as (
    select invoice.supplier_id, count(*) as purchases
      from public.purchase_invoices invoice
     where invoice.tenant_id = v_tenant_id
       and invoice.supplier_id is not null
       and invoice.date::date >= (p_to_date - 540)
     group by invoice.supplier_id
  ), parties as (
    select jsonb_build_object(
      'kind', 'supplier',
      'id', supplier.id,
      'display_name', supplier.name,
      'counterparty_rut', nullif(btrim(coalesce(supplier.rut, '')), ''),
      'counterparty_names', public.bank_reconciliation_name_list(
        array[
          supplier.name, supplier.legal_name, supplier.trade_name,
          supplier.owner_name
        ] || coalesce(supplier.aliases, array[]::text[])
      ),
      'purchase_count', coalesce(purchase_counts.purchases, 0),
      'usual', coalesce(usage_by_party.usual, '[]'::jsonb)
    ) as party
      from public.suppliers supplier
      left join purchase_counts
        on purchase_counts.supplier_id = supplier.id
      left join usage_by_party
        on usage_by_party.kind = 'supplier'
       and usage_by_party.party_key = supplier.id::text
     where supplier.tenant_id = v_tenant_id
       and (supplier.is_active or usage_by_party.party_key is not null)
    union all
    select jsonb_build_object(
      'kind', 'payee',
      'id', null,
      'display_name', (
        select expense.supplier_name
          from public.expenses expense
         where expense.tenant_id = v_tenant_id
           and expense.supplier_id is null
           and lower(btrim(expense.supplier_name)) = usage_by_party.party_key
         order by expense.issue_date desc
         limit 1
      ),
      'counterparty_rut', null,
      'counterparty_names', jsonb_build_array(usage_by_party.party_key),
      'purchase_count', 0,
      'usual', usage_by_party.usual
    )
      from usage_by_party
     where usage_by_party.kind = 'payee'
    union all
    select jsonb_build_object(
      'kind', 'employee',
      'id', employee.id,
      'display_name', concat_ws(' ', employee.first_name, employee.last_name),
      'counterparty_rut', nullif(btrim(coalesce(employee.rut, '')), ''),
      'counterparty_names', public.bank_reconciliation_employee_names(
        v_tenant_id, employee.id, array[]::text[]
      ),
      'purchase_count', 0,
      'usual', case when employee.salary_account_id is null then '[]'::jsonb
        else jsonb_build_array(jsonb_build_object(
          'account_id', employee.salary_account_id,
          'payment_method_code', null,
          'uses', 0,
          'last_used_at', null,
          'last_description', null
        )) end
    )
      from public.employees employee
     where employee.tenant_id = v_tenant_id
       and coalesce(employee.status, 'active') <> 'terminated'
  )
  select coalesce(jsonb_agg(parties.party), '[]'::jsonb)
    into v_parties
    from parties;

  -- Earlier decisions on unregistered rows teach the next proposal.
  select coalesce(jsonb_agg(item order by item->>'decided_at' desc), '[]'::jsonb)
    into v_decisions
    from (
      select jsonb_build_object(
        'action', decision.action_kind,
        'decided_at', decision.decided_at,
        'direction', statement_row.direction,
        'amount', statement_row.amount,
        'description', statement_row.description,
        'counterparty', statement_row.counterparty_observed,
        'account_id', coalesce(
          decision.action_snapshot->>'account_id',
          decision.action_snapshot->>'counterpart_account_id'
        ),
        'payment_method_id', decision.action_snapshot->>'payment_method_id',
        'supplier_name', expense.supplier_name,
        'text', coalesce(expense.notes, journal.description, decision.note)
      ) as item
        from public.bank_reconciliation_row_decisions decision
        join public.bank_statement_rows statement_row
          on statement_row.tenant_id = decision.tenant_id
         and statement_row.id = decision.row_id
        left join public.expenses expense
          on decision.generated_target_kind = 'expense'
         and expense.tenant_id = decision.tenant_id
         and expense.id = decision.generated_target_id
        left join public.journal_entries journal
          on decision.generated_target_kind = 'journal_entry'
         and journal.tenant_id = decision.tenant_id
         and journal.id = decision.generated_target_id
       where decision.tenant_id = v_tenant_id
         and decision.action_kind in ('create_expense', 'post_journal', 'dismiss')
         and coalesce(decision.action_snapshot->>'settled_elsewhere', 'false') <> 'true'
       order by decision.decided_at desc
       limit 500
    ) recent;

  -- Advances Nómina still has to discount. A salary transfer is the week's
  -- balance minus the advances paid on or before the week's end, which is
  -- how Nómina applies them (pay_payroll_voucher_v2 refuses a later one).
  select coalesce(jsonb_agg(jsonb_build_object(
    'advance_id', advance.id,
    'employee_id', advance.employee_id,
    'available', advance.amount - advance.amount_applied,
    'paid_on', public.tenant_business_date(v_tenant_id, advance.paid_at),
    'payment_method_code', method.code
  ) order by advance.paid_at, advance.id), '[]'::jsonb)
    into v_open_advances
    from public.employee_advances advance
    left join public.payment_methods method
      on method.tenant_id = advance.tenant_id
     and method.id = advance.payment_method_id
   where advance.tenant_id = v_tenant_id
     and advance.status in ('open', 'partially_applied')
     and advance.amount - advance.amount_applied > 0;

  -- Rows a review of this account already settled. A statement reopened to
  -- finish what it left pending, or one that overlaps an applied statement,
  -- shows them as done instead of offering them again.
  select coalesce(jsonb_agg(jsonb_build_object(
    'import_id', imported.id,
    'file_sha256', imported.file_sha256,
    'source_row_id', statement_row.source_row_id,
    'booking_date', statement_row.booking_date,
    'direction', statement_row.direction,
    'amount', statement_row.amount,
    'balance', statement_row.balance,
    'disposition', decision.disposition,
    'action', decision.action_kind,
    'settled_elsewhere',
      coalesce(decision.action_snapshot->>'settled_elsewhere', 'false') = 'true',
    'note', decision.note,
    'decided_at', decision.decided_at,
    'labels', coalesce((
      select jsonb_agg(
        public.bank_reconciliation_target_snapshot(
          v_tenant_id, imported.erp_account_id,
          allocation.target_kind, allocation.target_id
        )->>'label'
        order by allocation.created_at, allocation.id
      )
        from public.bank_reconciliation_allocations allocation
       where allocation.tenant_id = v_tenant_id
         and allocation.row_id = decision.row_id
    ), '[]'::jsonb)
  ) order by statement_row.booking_date, imported.id, statement_row.ordinal),
  '[]'::jsonb)
    into v_reconciled_rows
    from public.bank_reconciliation_row_decisions decision
    join public.bank_statement_rows statement_row
      on statement_row.tenant_id = decision.tenant_id
     and statement_row.id = decision.row_id
    join public.bank_statement_imports imported
      on imported.tenant_id = decision.tenant_id
     and imported.id = decision.import_id
   where decision.tenant_id = v_tenant_id
     and imported.erp_account_id = p_erp_account_id
     and decision.disposition <> 'pending'
     and statement_row.booking_date between p_from_date and p_to_date;

  return jsonb_build_object(
    'candidates', v_candidates,
    'reconciled_rows', v_reconciled_rows,
    'payroll_lines', v_payroll_lines,
    'open_advances', v_open_advances,
    'open_sales', v_open_sales,
    'open_purchases', v_open_purchases,
    'parties', v_parties,
    'decisions', v_decisions
  );
end;
$$;

revoke all on function public.get_bank_reconciliation_candidates_v2(
  uuid, date, date
) from public, anon;
grant execute on function public.get_bank_reconciliation_candidates_v2(
  uuid, date, date
) to authenticated, service_role;
