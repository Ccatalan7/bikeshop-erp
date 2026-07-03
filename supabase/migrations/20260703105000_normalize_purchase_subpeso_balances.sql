-- Normalize sub-peso purchase balances left by OCR/tax fractional totals.
-- The ERP pays and displays CLP pesos, so differences under one peso are not
-- actionable balances. Disable the purchase workflow trigger during this data
-- repair so received invoices do not create stock movement churn.

do $$
begin
  alter table public.purchase_invoices disable trigger trg_purchase_invoices_change;

  with active_payments as (
    select invoice_id, coalesce(sum(amount), 0) as active_paid
      from public.purchase_payments
     where deleted_at is null
     group by invoice_id
  )
  update public.purchase_invoices pi
     set balance = 0,
         updated_at = now()
    from active_payments ap
   where ap.invoice_id = pi.id
     and pi.status in ('received', 'paid')
     and pi.received_date is not null
     and abs(round(coalesce(pi.total, 0) - coalesce(ap.active_paid, 0), 2)) < 1
     and coalesce(pi.balance, 0) <> 0;

  alter table public.purchase_invoices enable trigger trg_purchase_invoices_change;
exception
  when others then
    alter table public.purchase_invoices enable trigger trg_purchase_invoices_change;
    raise;
end $$;
