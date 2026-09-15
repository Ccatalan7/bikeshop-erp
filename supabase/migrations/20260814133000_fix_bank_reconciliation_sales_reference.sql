-- Bank reconciliation sales-payment reference compatibility.
--
-- Production does not expose the historical denormalized
-- `sales_payments.invoice_reference` column.  The canonical payment reference
-- is `sales_payments.reference`; the invoice number already comes from the
-- joined invoice.  Replacing the sealed base projection keeps the public
-- action-workspace wrapper intact and prevents one legacy schema difference
-- from aborting the entire candidate catalog.

create or replace function
  public.bank_reconciliation_target_snapshot_without_legacy_expense(
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
  if p_target_kind = 'sales_payment' then
    select jsonb_build_object(
      'target_kind', 'sales_payment',
      'target_id', payment.id,
      'direction', 'credit',
      'amount', payment.amount,
      'occurred_on', payment.date::date,
      'label', 'Venta ' || invoice.invoice_number,
      'counterparty', coalesce(invoice.customer_name, customer.name, 'Cliente'),
      'reference', payment.reference,
      'payment_method_code', method.code,
      'provider', method.settlement_provider,
      'instrument', method.payment_instrument
    ) into v_result
      from public.sales_payments payment
      join public.sales_invoices invoice
        on invoice.tenant_id = payment.tenant_id and invoice.id = payment.invoice_id
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      left join public.customers customer
        on customer.tenant_id = invoice.tenant_id and customer.id = invoice.customer_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id
       and payment.deleted_at is null
       and method.account_id = p_erp_account_id;
  elsif p_target_kind = 'purchase_payment' then
    select jsonb_build_object(
      'target_kind', 'purchase_payment',
      'target_id', payment.id,
      'direction', 'debit',
      'amount', payment.amount,
      'occurred_on', payment.date::date,
      'label', 'Compra ' || invoice.invoice_number,
      'counterparty', coalesce(invoice.supplier_name, supplier.name, 'Proveedor'),
      'reference', payment.reference,
      'payment_method_code', method.code,
      'provider', method.settlement_provider,
      'instrument', method.payment_instrument
    ) into v_result
      from public.purchase_payments payment
      join public.purchase_invoices invoice
        on invoice.tenant_id = payment.tenant_id and invoice.id = payment.invoice_id
      join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      left join public.suppliers supplier
        on supplier.tenant_id = invoice.tenant_id and supplier.id = invoice.supplier_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id
       and payment.deleted_at is null
       and method.account_id = p_erp_account_id;
  elsif p_target_kind = 'expense_payment' then
    select jsonb_build_object(
      'target_kind', 'expense_payment',
      'target_id', payment.id,
      'direction', 'debit',
      'amount', payment.amount,
      'occurred_on', payment.payment_date::date,
      'label', 'Gasto ' || expense.expense_number,
      'counterparty', coalesce(expense.supplier_name, supplier.name, 'Proveedor'),
      'reference', coalesce(payment.reference, expense.reference),
      'payment_method_code', method.code,
      'provider', coalesce(method.settlement_provider, 'none'),
      'instrument', coalesce(method.payment_instrument, 'unknown')
    ) into v_result
      from public.expense_payments payment
      join public.expenses expense
        on expense.tenant_id = payment.tenant_id and expense.id = payment.expense_id
      left join public.payment_methods method
        on method.tenant_id = payment.tenant_id
       and method.id = payment.payment_method_id
      left join public.suppliers supplier
        on supplier.tenant_id = expense.tenant_id and supplier.id = expense.supplier_id
     where payment.tenant_id = p_tenant_id
       and payment.id = p_target_id
       and coalesce(payment.payment_account_id, method.account_id) = p_erp_account_id;
  elsif p_target_kind = 'journal_entry' then
    select jsonb_build_object(
      'target_kind', 'journal_entry',
      'target_id', entry.id,
      'direction', case
        when sum(line.debit_amount) > sum(line.credit_amount) then 'credit'
        else 'debit'
      end,
      'amount', abs(sum(line.debit_amount) - sum(line.credit_amount)),
      'occurred_on', entry.entry_date::date,
      'label', entry.entry_number || ' · ' || entry.description,
      'counterparty', null,
      'reference', entry.source_reference,
      'payment_method_code', null,
      'provider', 'none',
      'instrument', 'unknown'
    ) into v_result
      from public.journal_entries entry
      join public.journal_lines line
        on line.tenant_id = entry.tenant_id and line.entry_id = entry.id
     where entry.tenant_id = p_tenant_id
       and entry.id = p_target_id
       and entry.status = 'posted'
       and line.account_id = p_erp_account_id
     group by entry.id;
  else
    raise exception using
      errcode = '22023',
      message = 'bank_reconciliation_target_kind_invalid';
  end if;
  return v_result;
end;
$$;

revoke all on function
  public.bank_reconciliation_target_snapshot_without_legacy_expense(
    uuid, uuid, text, uuid
  ) from public, anon, authenticated, service_role;

comment on function
  public.bank_reconciliation_target_snapshot_without_legacy_expense(
    uuid, uuid, text, uuid
  ) is 'Sealed canonical-operation projection. Payment references come from each payment reference column; invoice labels come from the joined invoice.';
