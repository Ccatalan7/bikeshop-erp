-- The review knows from which day Nómina takes a transfer as the week's
-- salary.
--
-- Nómina pays a week from its operational close on — the last open business
-- day on or before period_end, Saturday for this shop's Sunday close — and
-- refuses earlier money as a salary (it is an advance). The review proposed
-- «Pagar sueldo» from three days before period_end, so a Thursday transfer
-- would have made the whole apply fail. The catalog now carries that close
-- as `payable_from`, computed by payroll_period_operational_close_date, the
-- same function the payment kernel checks. Same signature, one more field.

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
