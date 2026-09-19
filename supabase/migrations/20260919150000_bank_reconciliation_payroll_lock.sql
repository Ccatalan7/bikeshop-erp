-- Paying a salary from the conciliation reads the week under Nómina's lock.
--
-- The wrapper checked what a line owed, then confirmed the week if needed,
-- re-read the week's version and paid against it. A payment Nómina recorded
-- between the check and the re-read was absorbed by the new version: the
-- optimistic check the review promised could not see it (Codex's review,
-- 2026-09-19). Nómina's command still refuses to pay more than the balance,
-- so no overpayment was possible, only a lost conflict.
--
--   * The pay_payroll branch takes `:payroll-settlement`, the advisory lock
--     every Nómina settlement command takes, before reading the voucher, the
--     line, its balance and its advances. The lock is held until commit and
--     is reentrant for the Nómina commands it calls. Nómina never takes the
--     reconciliation lock, so the order bank-reconciliation → payroll-
--     settlement cannot deadlock against it.
--
-- Signatures and privileges are unchanged.

create or replace function public.apply_bank_reconciliation_actions_v3(
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
  v_uuid_pattern constant text :=
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_payload_hash text;
  v_existing_receipt jsonb;
  v_import_account_id uuid;
  v_import_revision bigint;
  v_item record;
  v_action jsonb;
  v_payroll jsonb;
  v_row record;
  v_voucher record;
  v_line record;
  v_amount numeric(14,2);
  v_expected_amount numeric(14,2);
  v_balance numeric(14,2);
  v_method_id uuid;
  v_version bigint;
  v_was_draft boolean;
  v_pay_receipt jsonb;
  v_payment jsonb;
  v_target jsonb;
  v_rewrites jsonb := '{}'::jsonb;
  v_rewritten jsonb;
  v_paid jsonb := '[]'::jsonb;
  v_confirmed_count integer := 0;
  v_receipt jsonb;
  v_advance jsonb;
  v_advance_total numeric(14,2);
  v_splits jsonb;
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

  -- A review with no salary to pay is exactly v2.
  if not exists (
    select 1
      from jsonb_array_elements(p_actions) action(value)
     where action.value->>'action' = 'pay_payroll'
  ) then
    return public.apply_bank_reconciliation_actions_v2(
      p_import_id, p_expected_revision, p_operation_key, p_actions
    );
  end if;

  if not public.can_manage_tenant_payroll(v_tenant_id) then
    raise exception using
      errcode = '42501', message = 'bank_reconciliation_payroll_access_required';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'import_id', p_import_id,
    'expected_revision', p_expected_revision,
    'actions', p_actions
  )::text, 'utf8'), 'sha256'), 'hex');

  -- Every reconciliation write takes this lock first; Nómina's locks come
  -- after it, inside its own commands.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':bank-reconciliation', 0
  ));

  -- A retry returns the first result: the salaries were paid once.
  select operation.receipt
    into v_existing_receipt
    from public.bank_reconciliation_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  if found then
    if v_existing_receipt->>'payroll_payload_hash'
         is distinct from v_payload_hash then
      raise exception using
        errcode = 'P0001', message = 'bank_reconciliation_idempotency_conflict';
    end if;
    return v_existing_receipt || jsonb_build_object('replayed', true);
  end if;

  select imported.erp_account_id, imported.revision
    into v_import_account_id, v_import_revision
    from public.bank_statement_imports imported
   where imported.tenant_id = v_tenant_id
     and imported.id = p_import_id;
  if not found then
    raise exception using
      errcode = '42501', message = 'bank_statement_import_not_accessible';
  end if;
  if v_import_revision <> p_expected_revision then
    raise exception using
      errcode = '40001', message = 'bank_reconciliation_revision_conflict';
  end if;

  -- Week by week, so a week's version threads through all its lines.
  for v_item in
    select action.value as action, action.ordinality
      from jsonb_array_elements(p_actions) with ordinality action(value, ordinality)
     where action.value->>'action' = 'pay_payroll'
     order by action.value->'payroll'->>'voucher_id', action.ordinality
  loop
    v_action := v_item.action;
    v_payroll := v_action->'payroll';
    if coalesce(jsonb_typeof(v_payroll), 'null') <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_payroll) payroll_key
          where payroll_key not in (
            'voucher_id', 'voucher_line_id', 'expected_amount', 'amount',
            'payment_method_id', 'confirm_draft', 'advances'
          )
       )
       or coalesce(v_action->>'row_id', '') !~* v_uuid_pattern
       or coalesce(v_payroll->>'voucher_id', '') !~* v_uuid_pattern
       or coalesce(v_payroll->>'voucher_line_id', '') !~* v_uuid_pattern
       or coalesce(v_payroll->>'payment_method_id', '') !~* v_uuid_pattern
       or coalesce(jsonb_typeof(v_payroll->'amount'), 'null') <> 'number'
       or coalesce(jsonb_typeof(v_payroll->'expected_amount'), 'null') <> 'number'
       or coalesce(jsonb_typeof(v_payroll->'confirm_draft'), 'null') <> 'boolean'
       or coalesce(jsonb_typeof(coalesce(v_payroll->'advances', '[]'::jsonb)), 'null')
            <> 'array'
       or jsonb_array_length(coalesce(v_payroll->'advances', '[]'::jsonb)) > 20 then
      raise exception using
        errcode = '22023', message = 'bank_reconciliation_payroll_payload_invalid';
    end if;

    select row.id, row.amount, row.direction, row.booking_date, row.description
      into v_row
      from public.bank_statement_rows row
     where row.tenant_id = v_tenant_id
       and row.import_id = p_import_id
       and row.id = (v_action->>'row_id')::uuid;
    if not found or v_row.direction <> 'debit' or v_row.amount is null
       or v_row.booking_date is null then
      raise exception using errcode = '22023', message = 'bank_reconciliation_row_invalid';
    end if;

    v_amount := (v_payroll->>'amount')::numeric;
    v_expected_amount := (v_payroll->>'expected_amount')::numeric;
    v_method_id := (v_payroll->>'payment_method_id')::uuid;
    -- The salary paid is what left the bank, within the rounding a direct
    -- association already tolerates.
    if v_amount <= 0 or v_amount <> round(v_amount, 2)
       or v_amount > v_row.amount or v_row.amount - v_amount > 1000 then
      raise exception using
        errcode = '22023', message = 'bank_reconciliation_payroll_amount_invalid';
    end if;

    -- Nómina's own settlement lock, taken before reading what the week
    -- owes and held until the payment is made: a payment Nómina records
    -- meanwhile waits, instead of slipping in between the balance this
    -- review checked and the version it pays against.
    perform pg_advisory_xact_lock(hashtextextended(
      v_tenant_id::text || ':payroll-settlement', 0
    ));
    select voucher.id, voucher.status, voucher.voucher_number,
           voucher.reconciliation_version, voucher.period_end
      into v_voucher
      from public.payroll_vouchers voucher
     where voucher.tenant_id = v_tenant_id
       and voucher.id = (v_payroll->>'voucher_id')::uuid;
    if not found then
      raise exception using
        errcode = '42501', message = 'bank_reconciliation_payroll_not_accessible';
    end if;
    select line.id, line.employee_id, line.employee_name, line.total_amount,
           line.is_included, line.expense_id
      into v_line
      from public.payroll_voucher_lines line
     where line.tenant_id = v_tenant_id
       and line.voucher_id = v_voucher.id
       and line.id = (v_payroll->>'voucher_line_id')::uuid;
    if not found or not v_line.is_included then
      raise exception using
        errcode = '42501', message = 'bank_reconciliation_payroll_not_accessible';
    end if;

    -- The review was built against this balance; a line paid or edited
    -- since then needs a fresh review, not a guess.
    v_balance := v_line.total_amount
      - coalesce((
          select sum(payment.amount)
            from public.expense_payments payment
           where payment.tenant_id = v_tenant_id
             and v_line.expense_id is not null
             and payment.expense_id = v_line.expense_id
        ), 0)
      - coalesce((
          select sum(allocation.amount)
            from public.employee_advance_allocations allocation
           where allocation.tenant_id = v_tenant_id
             and allocation.voucher_line_id = v_line.id
        ), 0);
    -- Advances Nómina already paid for this week are discounted here, as
    -- Nómina applies them: the worker's own, still open, paid on or before
    -- the week's end.
    v_advance_total := 0;
    v_splits := '[]'::jsonb;
    for v_advance in
      select value from jsonb_array_elements(coalesce(v_payroll->'advances', '[]'::jsonb))
    loop
      if jsonb_typeof(v_advance) <> 'object'
         or exists (
           select 1 from jsonb_object_keys(v_advance) advance_key
            where advance_key not in ('advance_id', 'amount')
         )
         or coalesce(v_advance->>'advance_id', '') !~* v_uuid_pattern
         or coalesce(jsonb_typeof(v_advance->'amount'), 'null') <> 'number'
         or (v_advance->>'amount')::numeric <= 0
         or not exists (
           select 1
             from public.employee_advances advance
            where advance.tenant_id = v_tenant_id
              and advance.id = (v_advance->>'advance_id')::uuid
              and advance.employee_id = v_line.employee_id
              and advance.status in ('open', 'partially_applied')
              and advance.amount - advance.amount_applied
                    >= (v_advance->>'amount')::numeric
              and public.tenant_business_date(v_tenant_id, advance.paid_at)
                    <= v_voucher.period_end
         ) then
        raise exception using
          errcode = '40001', message = 'bank_reconciliation_payroll_advance_invalid';
      end if;
      v_advance_total := v_advance_total + (v_advance->>'amount')::numeric;
      v_splits := v_splits || jsonb_build_array(jsonb_build_object(
        'kind', 'advance',
        'amount', (v_advance->>'amount')::numeric,
        'advance_id', (v_advance->>'advance_id')::uuid,
        'notes', 'Anticipo aplicado desde la conciliación bancaria'
      ));
    end loop;

    if v_voucher.status not in ('draft', 'confirmed', 'partial')
       or v_balance <> v_expected_amount
       or v_amount + v_advance_total > v_balance then
      raise exception using
        errcode = '40001', message = 'bank_reconciliation_payroll_line_changed';
    end if;

    if not exists (
      select 1
        from public.payment_methods method
       where method.tenant_id = v_tenant_id
         and method.id = v_method_id
         and method.is_active
         and lower(btrim(method.code)) = 'transfer'
         and method.account_id = v_import_account_id
    ) then
      raise exception using
        errcode = '23503', message = 'bank_reconciliation_payroll_method_invalid';
    end if;

    v_was_draft := v_voucher.status = 'draft';
    if v_was_draft then
      -- Paying a draft week recognizes it first, as Nómina does. The
      -- operator agreed to it on the row.
      if not (v_payroll->>'confirm_draft')::boolean then
        raise exception using
          errcode = '55000', message = 'bank_reconciliation_payroll_week_is_draft';
      end if;
      perform public.confirm_payroll_voucher_v2(
        v_voucher.id,
        'bankrec:' || left(encode(extensions.digest(
          trim(p_operation_key) || ':confirm:' || v_voucher.id::text, 'sha256'
        ), 'hex'), 48),
        v_voucher.reconciliation_version
      );
      v_confirmed_count := v_confirmed_count + 1;
    end if;
    select voucher.reconciliation_version
      into v_version
      from public.payroll_vouchers voucher
     where voucher.tenant_id = v_tenant_id
       and voucher.id = v_voucher.id;

    v_pay_receipt := public.pay_payroll_voucher_v2(
      v_voucher.id,
      'bankrec:' || left(encode(extensions.digest(
        trim(p_operation_key) || ':pay:' || v_row.id::text, 'sha256'
      ), 'hex'), 48),
      v_version,
      jsonb_build_object(
        v_line.id::text,
        v_splits || jsonb_build_array(jsonb_build_object(
          'kind', 'payment',
          'amount', v_amount,
          'payment_method_id', v_method_id,
          'payment_account_id', v_import_account_id,
          -- Noon UTC is morning in Chile: the civil date is the bank's.
          'payment_date', to_char(v_row.booking_date, 'YYYY-MM-DD') || 'T12:00:00Z',
          'reference', left(
            'Cartola ' || to_char(v_row.booking_date, 'DD-MM-YYYY') || ' · '
              || coalesce(v_row.description, ''),
            500
          ),
          'notes', 'Pagado desde la conciliación bancaria'
        ))
      )
    );
    if jsonb_array_length(
         coalesce(v_pay_receipt->'expense_payments', '[]'::jsonb)
       ) <> 1
       or jsonb_array_length(
         coalesce(v_pay_receipt->'advance_allocations', '[]'::jsonb)
       ) <> jsonb_array_length(v_splits) then
      raise exception using
        errcode = '55000', message = 'bank_reconciliation_payroll_payment_missing';
    end if;
    v_payment := v_pay_receipt->'expense_payments'->0;
    if (v_payment->>'voucher_line_id')::uuid <> v_line.id
       or (v_payment->>'amount')::numeric <> v_amount then
      raise exception using
        errcode = '55000', message = 'bank_reconciliation_payroll_payment_missing';
    end if;

    v_target := public.bank_reconciliation_target_snapshot(
      v_tenant_id, v_import_account_id, 'expense_payment',
      (v_payment->>'payment_id')::uuid
    );
    if v_target is null
       or v_target->>'direction' <> 'debit'
       or (v_target->>'amount')::numeric <> v_amount then
      raise exception using
        errcode = '55000', message = 'bank_reconciliation_payroll_payment_not_linkable';
    end if;

    v_paid := v_paid || jsonb_build_array(jsonb_build_object(
      'row_id', v_row.id,
      'voucher_id', v_voucher.id,
      'voucher_number', v_voucher.voucher_number,
      'voucher_line_id', v_line.id,
      'employee_id', v_line.employee_id,
      'employee_name', v_line.employee_name,
      'expense_payment_id', v_payment->>'payment_id',
      'amount', v_amount,
      'advances', coalesce(v_payroll->'advances', '[]'::jsonb),
      'confirmed_week', v_was_draft
    ));
    v_rewrites := v_rewrites || jsonb_build_object(
      v_row.id::text,
      jsonb_build_object(
        'row_id', v_row.id,
        'action', 'associate_existing',
        'allocations', jsonb_build_array(jsonb_build_object(
          'row_id', v_row.id,
          'target_kind', 'expense_payment',
          'target_id', v_payment->>'payment_id',
          'bank_amount', v_row.amount,
          'target_amount', v_amount,
          'match_kind', 'direct',
          'confidence', 'high',
          'provider', coalesce(v_target->>'provider', 'none'),
          'instrument', coalesce(v_target->>'instrument', 'unknown'),
          'rationale', jsonb_build_object(
            'reasons', jsonb_build_array(
              'Sueldo pagado desde la conciliación bancaria'
            ),
            'payroll_voucher_number', v_voucher.voucher_number,
            'employee_name', v_line.employee_name
          )
        ))
      )
    );
  end loop;

  select coalesce(jsonb_agg(
    coalesce(v_rewrites->(action.value->>'row_id'), action.value)
    order by action.ordinality
  ), '[]'::jsonb)
    into v_rewritten
    from jsonb_array_elements(p_actions) with ordinality action(value, ordinality);

  v_receipt := public.apply_bank_reconciliation_actions_v2(
    p_import_id, p_expected_revision, p_operation_key, v_rewritten
  );

  for v_item in select value from jsonb_array_elements(v_paid)
  loop
    update public.bank_reconciliation_row_decisions decision
       set action_snapshot = decision.action_snapshot
         || jsonb_build_object('payroll_payment', v_item.value - 'row_id')
     where decision.tenant_id = v_tenant_id
       and decision.import_id = p_import_id
       and decision.row_id = (v_item.value->>'row_id')::uuid;
    if not found then
      raise exception using
        errcode = '40001', message = 'bank_reconciliation_operation_missing';
    end if;
  end loop;

  v_receipt := (v_receipt - 'replayed') || jsonb_build_object(
    'payroll_payment_count', jsonb_array_length(v_paid),
    'payroll_confirmed_week_count', v_confirmed_count,
    'payroll_payments', v_paid,
    'payroll_payload_hash', v_payload_hash
  );
  update public.bank_reconciliation_operations operation
     set receipt = v_receipt || jsonb_build_object('replayed', false)
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = trim(p_operation_key);
  if not found then
    raise exception using
      errcode = '40001', message = 'bank_reconciliation_operation_missing';
  end if;
  return v_receipt || jsonb_build_object('replayed', false);
end;
$$;
