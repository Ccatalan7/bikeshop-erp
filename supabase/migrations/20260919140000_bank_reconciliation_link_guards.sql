-- Two guards on what an association may link, from Codex's review
-- (2026-09-19).
--
--   * The $1.000 bound 20260919110000 put on manual allocations also caught
--     card settlements: the terminal adapter sends `processor_estimate` to
--     the kernel as `manual`, and a $50.000 sale deposited as $48.750 was
--     refused (payment_terminal_settlement_accounting.sql). A manual
--     allocation without a provider keeps the $1.000 bound; one with a
--     provider is a settlement and may be below the sale, never above it.
--     None of the 11 card settlements in production is above its sale.
--   * The journal a payment posted (sales, purchase, expense payments and
--     terminal settlements) could be linked as a target of its own, apart
--     from the payment, so the same money could explain two movements. The
--     catalog never offered them; the kernel now refuses them. Production
--     links only journals the reconciliation generated.
--
-- Signatures and privileges are unchanged.

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
  v_part jsonb;
  v_part_amount numeric(14,2);
  v_part_total numeric(14,2);
  v_journal_total numeric(14,2);
  v_journal_parts jsonb;
  v_parts_snapshot jsonb;
  v_first_expense_id uuid;
  v_supplier record;
  v_supplier_id uuid;
  v_supplier_name text;
  v_split_method_id uuid;
  v_remainder_snapshot jsonb;
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
         'dismiss', 'split'
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
       and v_action_code in (
         'associate_existing', 'create_expense', 'post_journal', 'split'
       ) then
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
             (
               v_allocation->>'match_kind' = 'direct'
               or (
                 v_allocation->>'match_kind' = 'manual'
                 and v_allocation->>'provider' = 'none'
               )
             )
             and abs(
               (v_allocation->>'bank_amount')::numeric
               - (v_allocation->>'target_amount')::numeric
             ) > 1000
           )
           -- A card settlement (the terminal adapter sends its estimates
           -- as manual) nets the acquirer's commission: never more than
           -- the sale.
           or (
             (
               v_allocation->>'match_kind' = 'transbank_estimate'
               or (
                 v_allocation->>'match_kind' = 'manual'
                 and v_allocation->>'provider' <> 'none'
               )
             )
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
        -- The journal a payment posted is that payment's money, linked
        -- through the payment: as its own target the same money could
        -- explain two movements.
        if v_target_kind = 'journal_entry' and exists (
          select 1 from public.journal_entries entry
           where entry.tenant_id = v_tenant_id
             and entry.id = v_target_id
             and coalesce(entry.source_module, '') in (
               'sales_payments', 'purchase_payments', 'expense_payments',
               'payment_terminal_settlements'
             )
        ) then
          raise exception using errcode = '22023', message = 'bank_reconciliation_target_is_payment_journal';
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
      -- What the chosen operations leave of the movement, booked as one
      -- journal to the account the operator named: Carlos Sánchez paid his
      -- $7.000 sale and $11.000 never registered in one $18.000 transfer.
      v_journal_id := null;
      v_remainder_snapshot := '{}'::jsonb;
      if v_action ? 'remainder' then
        if coalesce(jsonb_typeof(v_action->'remainder'), 'null') <> 'object'
           or v_row.direction not in ('debit', 'credit')
           or v_row.booking_date is null
           or length(trim(coalesce(v_action->'remainder'->>'description', '')))
                not between 2 and 500 then
          raise exception using errcode = '22023', message = 'bank_reconciliation_remainder_invalid';
        end if;
        select coalesce(sum(allocation.bank_amount), 0)
          into v_part_total
          from public.bank_reconciliation_allocations allocation
         where allocation.row_id = v_row.id;
        v_part_amount := v_row.amount - v_part_total;
        if v_part_amount <= 0 then
          raise exception using errcode = '22023', message = 'bank_reconciliation_remainder_invalid';
        end if;
        select account.id, account.code, account.name, account.type
          into v_account
          from public.accounts account
         where account.tenant_id = v_tenant_id
           and account.id = (v_action->'remainder'->>'account_id')::uuid
           and account.id <> v_import.erp_account_id
           and account.is_active;
        if not found then
          raise exception using errcode = '42501', message = 'bank_reconciliation_counterpart_account_invalid';
        end if;

        v_journal_id := gen_random_uuid();
        v_description := trim(v_action->'remainder'->>'description');
        v_reference := nullif(trim(coalesce(
          v_action->'remainder'->>'reference', v_row.document_number, ''
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
          coalesce(v_reference, v_row.id::text), 'posted', v_part_amount,
          v_part_amount, v_user_id
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
          v_description, v_part_amount, 0
        ),
        (
          v_tenant_id, v_journal_id,
          case when v_row.direction = 'credit' then v_account.id else v_bank_account.id end,
          case when v_row.direction = 'credit' then v_account.code else v_bank_account.code end,
          case when v_row.direction = 'credit' then v_account.name else v_bank_account.name end,
          v_description, 0, v_part_amount
        );
        insert into public.bank_reconciliation_allocations (
          tenant_id, import_id, row_id, target_kind, target_id, bank_amount,
          target_amount, match_kind, confidence, provider, instrument,
          rationale, created_by
        ) values (
          v_tenant_id, v_import.id, v_row.id, 'journal_entry', v_journal_id,
          v_part_amount, v_part_amount, 'manual', 'high', 'none', 'unknown',
          jsonb_build_object('action', 'associate_remainder'), v_user_id
        );
        v_generated_kind := 'journal_entry';
        v_generated_id := v_journal_id;
        v_created_journal_count := v_created_journal_count + 1;
        v_remainder_snapshot := jsonb_build_object('remainder', jsonb_build_object(
          'account_id', v_account.id,
          'amount', v_part_amount,
          'description', v_description,
          'reference', v_reference,
          'journal_entry_id', v_journal_id
        ));
      end if;
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
      ) || v_remainder_snapshot;

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
        v_description, v_row.amount, 0
      ),
      (
        v_tenant_id, v_journal_id,
        case when v_row.direction = 'credit' then v_account.id else v_bank_account.id end,
        case when v_row.direction = 'credit' then v_account.code else v_bank_account.code end,
        case when v_row.direction = 'credit' then v_account.name else v_bank_account.name end,
        v_description, 0, v_row.amount
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

    elsif v_action_code = 'split' then
      -- One movement that paid or collected several things at once: the
      -- owner's mother pays the F29, the accountant and the municipal licence
      -- and is repaid in one transfer. A part on an expense account becomes
      -- an expense paid from the bank, with its supplier; any other account
      -- is a line of one balanced journal. The parts add up to the movement.
      if v_row.direction not in ('debit', 'credit') or v_row.amount is null
         or v_row.booking_date is null
         or coalesce(jsonb_typeof(v_action->'split'), 'null') <> 'object'
         or coalesce(jsonb_typeof(v_action->'split'->'parts'), 'null') <> 'array'
         or jsonb_array_length(v_action->'split'->'parts') not between 2 and 10
         or exists (
           select 1
             from jsonb_array_elements(v_action->'split'->'parts') part(value)
            where jsonb_typeof(part.value) <> 'object'
               or coalesce(jsonb_typeof(part.value->'amount'), 'null') <> 'number'
               or (part.value->>'amount')::numeric <= 0
               or length(trim(coalesce(part.value->>'description', '')))
                    not between 2 and 500
         ) then
        raise exception using errcode = '22023', message = 'bank_reconciliation_split_invalid';
      end if;
      select sum((part.value->>'amount')::numeric)
        into v_part_total
        from jsonb_array_elements(v_action->'split'->'parts') part(value);
      if v_part_total <> v_row.amount then
        raise exception using errcode = '23514', message = 'bank_reconciliation_split_total_mismatch';
      end if;

      v_reference := nullif(trim(coalesce(
        v_action->'split'->>'reference', v_row.document_number, ''
      )), '');
      v_journal_total := 0;
      v_journal_parts := '[]'::jsonb;
      v_parts_snapshot := '[]'::jsonb;
      v_first_expense_id := null;
      v_split_method_id := null;
      for v_part in
        select value from jsonb_array_elements(v_action->'split'->'parts')
      loop
        v_part_amount := (v_part->>'amount')::numeric;
        v_description := trim(v_part->>'description');
        select account.id, account.code, account.name, account.type
          into v_account
          from public.accounts account
         where account.tenant_id = v_tenant_id
           and account.id = (v_part->>'account_id')::uuid
           and account.id <> v_import.erp_account_id
           and account.is_active;
        if not found then
          raise exception using errcode = '42501', message = 'bank_reconciliation_counterpart_account_invalid';
        end if;

        if v_account.type <> 'expense' then
          v_journal_total := v_journal_total + v_part_amount;
          v_journal_parts := v_journal_parts || jsonb_build_array(jsonb_build_object(
            'account_id', v_account.id, 'code', v_account.code,
            'name', v_account.name, 'amount', v_part_amount,
            'description', v_description
          ));
          v_parts_snapshot := v_parts_snapshot || jsonb_build_array(jsonb_build_object(
            'kind', 'journal', 'account_id', v_account.id,
            'amount', v_part_amount, 'description', v_description
          ));
          continue;
        end if;

        if v_row.direction <> 'debit' then
          raise exception using errcode = '22023', message = 'bank_reconciliation_split_expense_needs_debit';
        end if;
        if v_split_method_id is null then
          select method.id, method.code, method.name, method.account_id
            into v_method
            from public.payment_methods method
           where method.tenant_id = v_tenant_id
             and method.id = (v_action->'split'->>'payment_method_id')::uuid
             and method.account_id = v_import.erp_account_id
             and method.is_active;
          if not found then
            raise exception using errcode = '42501', message = 'bank_reconciliation_payment_method_invalid';
          end if;
          v_split_method_id := v_method.id;
        end if;
        v_supplier_id := null;
        v_supplier_name := nullif(trim(coalesce(v_part->>'supplier_name', '')), '');
        if nullif(v_part->>'supplier_id', '') is not null then
          select supplier.id, supplier.name
            into v_supplier
            from public.suppliers supplier
           where supplier.tenant_id = v_tenant_id
             and supplier.id = (v_part->>'supplier_id')::uuid;
          if not found then
            raise exception using errcode = '42501', message = 'bank_reconciliation_split_supplier_invalid';
          end if;
          v_supplier_id := v_supplier.id;
          v_supplier_name := v_supplier.name;
        end if;

        v_expense_id := gen_random_uuid();
        insert into public.expenses (
          id, tenant_id, expense_number, supplier_id, supplier_name,
          document_type, document_number, issue_date, due_date, currency,
          posting_status, payment_status, subtotal, tax_amount, total_amount,
          amount_paid, balance, notes, reference, approval_status,
          approved_by, approved_at, payment_account_id, payment_method_id,
          created_by
        ) values (
          v_expense_id, v_tenant_id, '', v_supplier_id, v_supplier_name,
          'other', v_reference,
          ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
          ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
          'CLP', 'draft', 'pending', 0, 0, 0, 0, 0,
          v_description, v_reference, 'approved', v_user_id, now(),
          v_import.erp_account_id, v_split_method_id, v_user_id
        );
        insert into public.expense_lines (
          tenant_id, expense_id, line_index, account_id, account_code,
          account_name, description, quantity, unit_price, subtotal, tax_rate,
          tax_amount, total
        ) values (
          v_tenant_id, v_expense_id, 0, v_account.id, v_account.code,
          v_account.name, v_description, 1, v_part_amount, v_part_amount, 0, 0,
          v_part_amount
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
          v_tenant_id, v_expense_id, v_split_method_id, v_import.erp_account_id,
          v_part_amount,
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
          v_expense_payment_id, v_part_amount, v_part_amount, 'manual', 'high',
          'none', 'unknown', jsonb_build_object('action', 'split'), v_user_id
        );
        v_first_expense_id := coalesce(v_first_expense_id, v_expense_id);
        v_created_expense_count := v_created_expense_count + 1;
        v_parts_snapshot := v_parts_snapshot || jsonb_build_array(jsonb_build_object(
          'kind', 'expense', 'account_id', v_account.id,
          'amount', v_part_amount, 'description', v_description,
          'supplier_id', v_supplier_id, 'supplier_name', v_supplier_name,
          'expense_number', v_expense_number,
          'expense_payment_id', v_expense_payment_id
        ));
      end loop;

      v_journal_id := null;
      if v_journal_total > 0 then
        v_journal_id := gen_random_uuid();
        v_description := coalesce(
          nullif(trim(coalesce(v_action->'split'->>'description', '')), ''),
          v_journal_parts->0->>'description'
        );
        insert into public.journal_entries (
          id, tenant_id, entry_number, entry_date, description, type,
          source_module, source_reference, status, total_debit, total_credit,
          created_by
        ) values (
          v_journal_id, v_tenant_id,
          public.get_next_document_number(v_tenant_id, 'journal_entry'),
          ((v_row.booking_date::timestamp + interval '12 hours') at time zone 'UTC'),
          v_description, 'adjustment', 'bank_reconciliation',
          coalesce(v_reference, v_row.id::text), 'posted', v_journal_total,
          v_journal_total, v_user_id
        );
        insert into public.journal_lines (
          tenant_id, entry_id, account_id, account_code, account_name,
          description, debit_amount, credit_amount
        ) values (
          v_tenant_id, v_journal_id, v_bank_account.id, v_bank_account.code,
          v_bank_account.name, v_description,
          case when v_row.direction = 'credit' then v_journal_total else 0 end,
          case when v_row.direction = 'debit' then v_journal_total else 0 end
        );
        insert into public.journal_lines (
          tenant_id, entry_id, account_id, account_code, account_name,
          description, debit_amount, credit_amount
        )
        select v_tenant_id, v_journal_id, (line.value->>'account_id')::uuid,
               line.value->>'code', line.value->>'name',
               line.value->>'description',
               case when v_row.direction = 'debit'
                 then (line.value->>'amount')::numeric else 0 end,
               case when v_row.direction = 'credit'
                 then (line.value->>'amount')::numeric else 0 end
          from jsonb_array_elements(v_journal_parts) line(value);
        insert into public.bank_reconciliation_allocations (
          tenant_id, import_id, row_id, target_kind, target_id, bank_amount,
          target_amount, match_kind, confidence, provider, instrument,
          rationale, created_by
        ) values (
          v_tenant_id, v_import.id, v_row.id, 'journal_entry', v_journal_id,
          v_journal_total, v_journal_total, 'manual', 'high', 'none', 'unknown',
          jsonb_build_object('action', 'split'), v_user_id
        );
        v_created_journal_count := v_created_journal_count + 1;
      end if;
      if coalesce((
        select sum(allocation.bank_amount)
          from public.bank_reconciliation_allocations allocation
         where allocation.row_id = v_row.id
      ), 0) <> v_row.amount then
        raise exception using errcode = '23514', message = 'bank_reconciliation_row_not_fully_allocated';
      end if;
      v_disposition := 'reconciled';
      v_generated_kind := case when v_journal_id is not null
        then 'journal_entry' else 'expense' end;
      v_generated_id := coalesce(v_journal_id, v_first_expense_id);
      v_action_snapshot := jsonb_build_object(
        'payment_method_id', v_split_method_id,
        'journal_entry_id', v_journal_id,
        'reference', v_reference,
        'parts', v_parts_snapshot
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
