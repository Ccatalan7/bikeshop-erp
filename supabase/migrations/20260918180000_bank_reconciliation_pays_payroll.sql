-- The bank reconciliation pays the salaries Nómina owes.
--
-- The owner reconciles a month and finds the week's salary transfers there;
-- until now the review could only say "pay it in Nómina, then come back".
-- v3 lets the same review pay the salary through Nómina's own commands and
-- associate the bank row with the payment in one atomic apply. Nómina keeps
-- its own path; both end in the same payroll payment.
--
-- The candidate catalog v2 is replaced in place (same signature, more
-- fields): its payroll lines now carry the week's status and version and the
-- line's balance. The first version listed only lines without an expense,
-- and confirming a week books every line's expense, so a confirmed, unpaid
-- week vanished from the review.

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
     where entry.id is null
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
       order by decision.decided_at desc
       limit 500
    ) recent;

  return jsonb_build_object(
    'candidates', v_candidates,
    'payroll_lines', v_payroll_lines,
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

-- Pay a salary Nómina owes from the bank line that paid it.
--
-- A `pay_payroll` action names the payroll line the bank transfer paid. In
-- one transaction the salary is paid through Nómina's own commands
-- (confirm_payroll_voucher_v2 for a draft week the operator agreed to
-- confirm, then pay_payroll_voucher_v2 dated on the bank booking date and
-- funded from this bank account) and the row is associated with the payment
-- that command created. Everything else is v2 unchanged. The salary is
-- therefore identical whether it was paid here or in Nómina.
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
            'payment_method_id', 'confirm_draft'
          )
       )
       or coalesce(v_action->>'row_id', '') !~* v_uuid_pattern
       or coalesce(v_payroll->>'voucher_id', '') !~* v_uuid_pattern
       or coalesce(v_payroll->>'voucher_line_id', '') !~* v_uuid_pattern
       or coalesce(v_payroll->>'payment_method_id', '') !~* v_uuid_pattern
       or coalesce(jsonb_typeof(v_payroll->'amount'), 'null') <> 'number'
       or coalesce(jsonb_typeof(v_payroll->'expected_amount'), 'null') <> 'number'
       or coalesce(jsonb_typeof(v_payroll->'confirm_draft'), 'null') <> 'boolean' then
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

    select voucher.id, voucher.status, voucher.voucher_number,
           voucher.reconciliation_version
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
    if v_voucher.status not in ('draft', 'confirmed', 'partial')
       or v_balance <> v_expected_amount
       or v_amount > v_balance then
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
        jsonb_build_array(jsonb_build_object(
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
       ) <> 1 then
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

revoke all on function public.apply_bank_reconciliation_actions_v3(
  uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_bank_reconciliation_actions_v3(
  uuid, bigint, text, jsonb
) to authenticated, service_role;

comment on function public.apply_bank_reconciliation_actions_v3(
  uuid, bigint, text, jsonb
) is 'v2 plus pay_payroll: pays an owed Nómina line through confirm_payroll_voucher_v2/pay_payroll_voucher_v2 on the bank date and associates the row with that payment, atomically.';
