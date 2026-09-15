-- Bank reconciliation action workspace.
--
-- Extends the evidence-only foundation with two missing capabilities:
--   * legacy embedded paid expenses remain valid existing-operation targets;
--   * one reviewed bank row can atomically associate an existing operation,
--     create and pay an expense, post a balanced classification journal, stay
--     pending, or be explicitly excluded with a reason.
--
-- Deployment status: reviewed production-bound forward migration; guarded
-- production apply, exact read-back, and history registration are part of
-- this task.

alter table public.bank_reconciliation_allocations
  drop constraint if exists bank_reconciliation_allocations_target_kind_check;
alter table public.bank_reconciliation_allocations
  add constraint bank_reconciliation_allocations_target_kind_check
  check (target_kind in (
    'sales_payment', 'purchase_payment', 'expense_payment', 'expense',
    'journal_entry'
  ));

alter table public.bank_reconciliation_operations
  drop constraint if exists bank_reconciliation_operations_action_check;
alter table public.bank_reconciliation_operations
  add constraint bank_reconciliation_operations_action_check
  check (action in ('create_import', 'apply_review', 'apply_actions'));

alter table public.bank_reconciliation_row_decisions
  add column if not exists action_kind text,
  add column if not exists note text,
  add column if not exists generated_target_kind text,
  add column if not exists generated_target_id uuid,
  add column if not exists action_snapshot jsonb not null default '{}'::jsonb;

update public.bank_reconciliation_row_decisions
   set action_kind = case disposition
     when 'reconciled' then 'associate_existing'
     when 'ignored' then 'dismiss'
     else 'pending'
   end
 where action_kind is null;

alter table public.bank_reconciliation_row_decisions
  alter column action_kind set default 'pending',
  alter column action_kind set not null,
  drop constraint if exists bank_reconciliation_row_decisions_action_kind_check,
  add constraint bank_reconciliation_row_decisions_action_kind_check
    check (action_kind in (
      'pending', 'associate_existing', 'create_expense', 'post_journal',
      'dismiss'
    )),
  drop constraint if exists bank_reconciliation_row_decisions_generated_kind_check,
  add constraint bank_reconciliation_row_decisions_generated_kind_check
    check (generated_target_kind is null or generated_target_kind in (
      'expense', 'journal_entry'
    )),
  drop constraint if exists bank_reconciliation_row_decisions_snapshot_check,
  add constraint bank_reconciliation_row_decisions_snapshot_check
    check (jsonb_typeof(action_snapshot) = 'object'),
  drop constraint if exists bank_reconciliation_row_decisions_generated_pair_check,
  add constraint bank_reconciliation_row_decisions_generated_pair_check
    check ((generated_target_kind is null) = (generated_target_id is null));

do $$
begin
  if to_regprocedure(
    'public.bank_reconciliation_target_snapshot_without_legacy_expense(uuid,uuid,text,uuid)'
  ) is null then
    alter function public.bank_reconciliation_target_snapshot(uuid, uuid, text, uuid)
      rename to bank_reconciliation_target_snapshot_without_legacy_expense;
  end if;
end;
$$;

revoke all on function
  public.bank_reconciliation_target_snapshot_without_legacy_expense(
    uuid, uuid, text, uuid
  ) from public, anon, authenticated, service_role;

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
  if p_target_kind <> 'expense' then
    return public.bank_reconciliation_target_snapshot_without_legacy_expense(
      p_tenant_id, p_erp_account_id, p_target_kind, p_target_id
    );
  end if;

  select jsonb_build_object(
    'target_kind', 'expense',
    'target_id', expense.id,
    'direction', 'debit',
    'amount', expense.total_amount,
    'occurred_on', coalesce(expense.paid_at, expense.issue_date)::date,
    'label', 'Gasto ' || expense.expense_number,
    'counterparty', coalesce(
      nullif(expense.supplier_name, ''), supplier.name, 'Proveedor'
    ),
    'reference', coalesce(
      nullif(expense.reference, ''), nullif(expense.document_number, '')
    ),
    'payment_method_code', method.code,
    'provider', coalesce(method.settlement_provider, 'none'),
    'instrument', coalesce(method.payment_instrument, 'unknown')
  ) into v_result
    from public.expenses expense
    left join public.payment_methods method
      on method.tenant_id = expense.tenant_id
     and method.id = expense.payment_method_id
    left join public.suppliers supplier
      on supplier.tenant_id = expense.tenant_id
     and supplier.id = expense.supplier_id
   where expense.tenant_id = p_tenant_id
     and expense.id = p_target_id
     and expense.posting_status = 'posted'
     and expense.payment_status = 'paid'
     and expense.total_amount > 0
     and coalesce(expense.payment_account_id, method.account_id)
       = p_erp_account_id
     and not exists (
       select 1
         from public.expense_payments payment
        where payment.tenant_id = expense.tenant_id
          and payment.expense_id = expense.id
          and payment.amount > 0
     );
  return v_result;
end;
$$;

revoke all on function public.bank_reconciliation_target_snapshot(
  uuid, uuid, text, uuid
) from public, anon, authenticated, service_role;

do $$
begin
  if to_regprocedure(
    'public.get_bank_reconciliation_candidates_without_legacy_expenses(uuid,date,date)'
  ) is null then
    alter function public.get_bank_reconciliation_candidates_v1(uuid, date, date)
      rename to get_bank_reconciliation_candidates_without_legacy_expenses;
  end if;
end;
$$;

revoke all on function
  public.get_bank_reconciliation_candidates_without_legacy_expenses(
    uuid, date, date
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
  v_base jsonb;
  v_candidates jsonb;
begin
  v_base := public.get_bank_reconciliation_candidates_without_legacy_expenses(
    p_erp_account_id, p_from_date, p_to_date
  );

  with candidates as (
    select item.value as candidate
      from jsonb_array_elements(coalesce(v_base->'candidates', '[]'::jsonb)) item
    union all
    select public.bank_reconciliation_target_snapshot(
      v_tenant_id, p_erp_account_id, 'expense', expense.id
    )
      from public.expenses expense
      left join public.payment_methods method
        on method.tenant_id = expense.tenant_id
       and method.id = expense.payment_method_id
     where expense.tenant_id = v_tenant_id
       and expense.posting_status = 'posted'
       and expense.payment_status = 'paid'
       and expense.total_amount > 0
       and coalesce(expense.paid_at, expense.issue_date)::date
         between p_from_date and p_to_date
       and coalesce(expense.payment_account_id, method.account_id)
         = p_erp_account_id
       and not exists (
         select 1
           from public.expense_payments payment
          where payment.tenant_id = expense.tenant_id
            and payment.expense_id = expense.id
            and payment.amount > 0
       )
       and not exists (
         select 1
           from public.bank_reconciliation_allocations allocation
          where allocation.tenant_id = expense.tenant_id
            and allocation.target_kind = 'expense'
            and allocation.target_id = expense.id
       )
  )
  select coalesce(jsonb_agg(
    candidate order by candidate->>'occurred_on', candidate->>'target_id'
  ), '[]'::jsonb)
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
  if jsonb_array_length(p_actions) <> (
    select count(*) from public.bank_statement_rows row
     where row.import_id = v_import.id
  ) or exists (
    select 1
      from jsonb_array_elements(p_actions) action
     group by action->>'row_id'
    having count(*) <> 1
  ) then
    raise exception using errcode = '22023', message = 'bank_reconciliation_action_coverage_invalid';
  end if;
  if exists (
    select 1
      from public.bank_reconciliation_row_decisions decision
     where decision.tenant_id = v_tenant_id
       and decision.import_id = v_import.id
       and decision.generated_target_id is not null
  ) then
    raise exception using errcode = '55000', message = 'bank_reconciliation_generated_review_immutable';
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

  delete from public.bank_reconciliation_allocations
   where tenant_id = v_tenant_id and import_id = v_import.id;
  delete from public.bank_reconciliation_row_decisions
   where tenant_id = v_tenant_id and import_id = v_import.id;

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
           row.description, row.counterparty_observed, row.document_number
      into v_row
      from public.bank_statement_rows row
     where row.tenant_id = v_tenant_id
       and row.import_id = v_import.id
       and row.id = (v_action->>'row_id')::uuid;
    if not found then
      raise exception using errcode = '22023', message = 'bank_reconciliation_row_invalid';
    end if;

    v_action_code := v_action->>'action';
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
      v_disposition := 'ignored';
      v_action_snapshot := jsonb_build_object('reason', trim(v_action->>'reason'));
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

revoke all on function public.apply_bank_reconciliation_actions_v2(
  uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_bank_reconciliation_actions_v2(
  uuid, bigint, text, jsonb
) to authenticated, service_role;

comment on function public.apply_bank_reconciliation_actions_v2(
  uuid, bigint, text, jsonb
) is 'Atomically applies one complete bank-statement review. Generated expenses and journals are posted before their immutable evidence allocation is persisted.';
