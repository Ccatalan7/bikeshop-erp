-- Bank reconciliation candidates v2: one clean catalog with identities.
--
-- v1 returned every payment twice: once as the payment and once as the
-- journal entry that payment posted. Its exclusion list names the modules
-- 'sales', 'purchases' and 'expenses', while the ledger writes
-- 'sales_payments', 'purchase_payments' and 'expense_payments'. With two
-- identical options the matcher never preselected anything (2 of 229 real
-- statement rows, June–September 2026). v1 also carried a single display
-- name, so every salary payment read 'Proveedor' and a bank line naming the
-- employee or the supplier's legal name could not be tied to it.
--
-- v2 keeps v1 as the owner of eligibility (access, range, bank account,
-- already-allocated targets) and adds what the client needs to decide:
--   * candidates without the duplicated payment journals;
--   * every name a bank line may show for the counterparty (customer,
--     supplier name/legal/trade/owner/aliases, employee and payroll
--     beneficiary aliases) plus the bank rows Nómina already tied to a
--     salary payment;
--   * unpaid payroll lines, open sales and purchase invoices, a directory of
--     counterparties with their usual expense account, and earlier
--     reconciliation decisions, so an unregistered row can be proposed.
-- v1 stays unchanged for app builds that still call it.

create or replace function public.bank_reconciliation_name_list(p_names text[])
returns jsonb
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  -- Byte order keeps the list identical on every server collation.
  select coalesce(jsonb_agg(name order by name collate "C"), '[]'::jsonb)
    from (
      select distinct btrim(raw_name) as name
        from unnest(coalesce(p_names, array[]::text[])) raw_name
       where length(btrim(coalesce(raw_name, ''))) >= 2
    ) names;
$$;

revoke all on function public.bank_reconciliation_name_list(text[])
  from public, anon, authenticated, service_role;

create or replace function public.bank_reconciliation_employee_names(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_extra text[] default array[]::text[]
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select public.bank_reconciliation_name_list(
    coalesce(p_extra, array[]::text[])
    || coalesce((
      select array[concat_ws(' ', employee.first_name, employee.last_name)]
        from public.employees employee
       where employee.tenant_id = p_tenant_id
         and employee.id = p_employee_id
    ), array[]::text[])
    || coalesce((
      select array_agg(alias.alias)
        from public.payroll_beneficiary_aliases alias
       where alias.tenant_id = p_tenant_id
         and alias.employee_id = p_employee_id
    ), array[]::text[])
  );
$$;

revoke all on function public.bank_reconciliation_employee_names(
  uuid, uuid, text[]
) from public, anon, authenticated, service_role;

create or replace function public.bank_reconciliation_candidate_identity(
  p_tenant_id uuid,
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
  v_expense_id uuid;
  v_payment_id uuid;
  v_employee_id uuid;
  v_employee_name text;
  v_evidence jsonb := '[]'::jsonb;
  v_source_module text;
  v_source_reference text;
begin
  if p_target_kind = 'sales_payment' then
    select jsonb_build_object(
      'occurred_at', payment.date,
      'counterparty_kind', 'customer',
      'counterparty_id', invoice.customer_id,
      'counterparty_rut', nullif(btrim(coalesce(customer.rut, invoice.customer_rut, '')), ''),
      'counterparty_names', public.bank_reconciliation_name_list(
        array[invoice.customer_name, customer.name]
      ),
      'document_number', invoice.invoice_number
    ) into v_result
      from public.sales_payments payment
      join public.sales_invoices invoice
        on invoice.tenant_id = payment.tenant_id
       and invoice.id = payment.invoice_id
      left join public.customers customer
        on customer.tenant_id = invoice.tenant_id
       and customer.id = invoice.customer_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id;
    return coalesce(v_result, '{}'::jsonb);
  end if;

  if p_target_kind = 'purchase_payment' then
    select jsonb_build_object(
      'occurred_at', payment.date,
      'counterparty_kind', 'supplier',
      'counterparty_id', invoice.supplier_id,
      'counterparty_rut', nullif(btrim(coalesce(supplier.rut, invoice.supplier_rut, '')), ''),
      'counterparty_names', public.bank_reconciliation_name_list(
        array[
          invoice.supplier_name, supplier.name, supplier.legal_name,
          supplier.trade_name, supplier.owner_name
        ] || coalesce(supplier.aliases, array[]::text[])
      ),
      'document_number', coalesce(
        nullif(btrim(coalesce(invoice.supplier_invoice_number, '')), ''),
        invoice.invoice_number
      )
    ) into v_result
      from public.purchase_payments payment
      join public.purchase_invoices invoice
        on invoice.tenant_id = payment.tenant_id
       and invoice.id = payment.invoice_id
      left join public.suppliers supplier
        on supplier.tenant_id = invoice.tenant_id
       and supplier.id = invoice.supplier_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id;
    return coalesce(v_result, '{}'::jsonb);
  end if;

  if p_target_kind in ('expense_payment', 'expense') then
    if p_target_kind = 'expense_payment' then
      select payment.expense_id, payment.id
        into v_expense_id, v_payment_id
        from public.expense_payments payment
       where payment.tenant_id = p_tenant_id
         and payment.id = p_target_id;
    else
      v_expense_id := p_target_id;
    end if;
    if v_expense_id is null then
      return '{}'::jsonb;
    end if;

    -- A salary is paid through a payroll line or a payment-workspace leg;
    -- the expense itself carries no supplier, only the voucher reference.
    select line.employee_id, line.employee_name
      into v_employee_id, v_employee_name
      from public.payroll_voucher_lines line
     where line.tenant_id = p_tenant_id
       and line.expense_id = v_expense_id
     limit 1;
    if v_employee_id is null then
      select leg.beneficiary_employee_id
        into v_employee_id
        from public.payroll_payment_workspace_legs leg
       where leg.tenant_id = p_tenant_id
         and leg.result_expense_id = v_expense_id
         and leg.beneficiary_employee_id is not null
       limit 1;
    end if;

    if v_payment_id is not null then
      select coalesce(jsonb_agg(distinct jsonb_build_object(
               'date', evidence.transaction_date,
               'amount', evidence.amount,
               'beneficiary', evidence.beneficiary_observed
             )), '[]'::jsonb)
        into v_evidence
        from (
          select statement_row.transaction_date, statement_row.amount,
                 statement_row.beneficiary_observed
            from public.payroll_payment_statement_allocations allocation
            join public.payroll_statement_rows statement_row
              on statement_row.tenant_id = allocation.tenant_id
             and statement_row.id = allocation.statement_row_id
           where allocation.tenant_id = p_tenant_id
             and allocation.result_expense_payment_id = v_payment_id
          union all
          select statement_row.transaction_date, statement_row.amount,
                 statement_row.beneficiary_observed
            from public.payroll_statement_allocations allocation
            join public.payroll_statement_rows statement_row
              on statement_row.tenant_id = allocation.tenant_id
             and statement_row.id = allocation.row_id
           where allocation.tenant_id = p_tenant_id
             and allocation.expense_payment_id = v_payment_id
        ) evidence;
    end if;

    select jsonb_build_object(
      'occurred_at', coalesce(payment.payment_date, expense.paid_at, expense.issue_date),
      'counterparty_kind', case
        when v_employee_id is not null then 'employee'
        when expense.supplier_id is not null then 'supplier'
        when nullif(btrim(coalesce(expense.supplier_name, '')), '') is not null then 'payee'
        else 'unknown'
      end,
      'counterparty_id', coalesce(v_employee_id, expense.supplier_id),
      'counterparty_rut', nullif(btrim(coalesce(supplier.rut, expense.supplier_rut, '')), ''),
      'counterparty_names', case
        when v_employee_id is not null then public.bank_reconciliation_employee_names(
          p_tenant_id, v_employee_id, array[v_employee_name]
        )
        else public.bank_reconciliation_name_list(
          array[
            expense.supplier_name, supplier.name, supplier.legal_name,
            supplier.trade_name, supplier.owner_name
          ] || coalesce(supplier.aliases, array[]::text[])
        )
      end,
      'document_number', coalesce(
        nullif(btrim(coalesce(expense.document_number, '')), ''),
        expense.expense_number
      ),
      'bank_evidence', v_evidence
    ) into v_result
      from public.expenses expense
      left join public.expense_payments payment
        on payment.tenant_id = expense.tenant_id
       and payment.id = v_payment_id
      left join public.suppliers supplier
        on supplier.tenant_id = expense.tenant_id
       and supplier.id = expense.supplier_id
     where expense.tenant_id = p_tenant_id
       and expense.id = v_expense_id;
    return coalesce(v_result, '{}'::jsonb);
  end if;

  if p_target_kind = 'journal_entry' then
    select entry.source_module, entry.source_reference
      into v_source_module, v_source_reference
      from public.journal_entries entry
     where entry.tenant_id = p_tenant_id
       and entry.id = p_target_id;
    if v_source_module = 'employee_advances'
       and v_source_reference ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select advance.employee_id into v_employee_id
        from public.employee_advances advance
       where advance.tenant_id = p_tenant_id
         and advance.id = v_source_reference::uuid;
      if v_employee_id is not null then
        return jsonb_build_object(
          'counterparty_kind', 'employee',
          'counterparty_id', v_employee_id,
          'counterparty_names', public.bank_reconciliation_employee_names(
            p_tenant_id, v_employee_id, array[]::text[]
          )
        );
      end if;
    end if;
    return '{}'::jsonb;
  end if;

  return '{}'::jsonb;
end;
$$;

revoke all on function public.bank_reconciliation_candidate_identity(
  uuid, text, uuid
) from public, anon, authenticated, service_role;

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

  -- Payroll lines that are owed but not paid yet: the bank transfer usually
  -- comes before the voucher is marked paid.
  select coalesce(jsonb_agg(jsonb_build_object(
    'voucher_id', voucher.id,
    'voucher_number', voucher.voucher_number,
    'period_label', voucher.period_label,
    'period_start', voucher.period_start,
    'period_end', voucher.period_end,
    'status', voucher.status,
    'line_id', line.id,
    'employee_id', line.employee_id,
    'employee_name', coalesce(
      nullif(btrim(coalesce(line.employee_name, '')), ''),
      concat_ws(' ', employee.first_name, employee.last_name)
    ),
    'counterparty_names', public.bank_reconciliation_employee_names(
      v_tenant_id, line.employee_id, array[line.employee_name]
    ),
    'amount', line.total_amount,
    'payment_method', line.payment_method
  ) order by voucher.period_end, line.employee_name), '[]'::jsonb)
    into v_payroll_lines
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
     and line.expense_id is null
     and voucher.period_end between p_from_date - 45 and p_to_date;

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
