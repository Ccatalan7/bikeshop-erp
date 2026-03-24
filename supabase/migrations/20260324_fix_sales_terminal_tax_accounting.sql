-- Bulk repair: sales invoices/journal entries/payment journal entries
-- for invoices where payment terminal stored IVA on sales_payments
-- but the invoice was saved as no_tax / iva_amount=0.
--
-- Tenant: Viñabike
-- Tenant ID: 5443b130-cc28-45af-a420-cd500b288890
-- Date: 2026-03-24

begin;

-- 1) Find affected invoices from payment-side tax data
create temp table tmp_broken_sales_tax as
select
  si.id as invoice_id,
  si.invoice_number,
  max(sp.created_at) as last_payment_at,
  round(sum(coalesce(sp.amount, 0))::numeric, 2) as total_paid,
  round(sum(coalesce(sp.net_amount, 0))::numeric, 2) as payment_net_total,
  round(sum(coalesce(sp.iva_amount, 0))::numeric, 2) as payment_iva_total
from public.sales_invoices si
join public.sales_payments sp
  on sp.invoice_id = si.id
where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and coalesce(sp.iva_amount, 0) > 0
  and (
    coalesce(si.iva_amount, 0) = 0
    or coalesce(si.tax_treatment, 'no_tax') = 'no_tax'
  )
group by si.id, si.invoice_number;

-- 2) Update invoices to reflect terminal-side tax treatment
update public.sales_invoices si
set
  tax_treatment = 'tax_included',
  net_amount = t.payment_net_total,
  iva_amount = t.payment_iva_total,
  subtotal = t.payment_net_total,
  total = t.payment_net_total + t.payment_iva_total,
  updated_at = now()
from tmp_broken_sales_tax t
where si.id = t.invoice_id;

-- 3) Rebuild invoice journal entries using corrected invoice tax fields
do $$
declare
  r record;
  v_invoice public.sales_invoices%rowtype;
begin
  for r in
    select invoice_id, invoice_number
    from tmp_broken_sales_tax
  loop
    delete from public.journal_entries
     where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and source_module = 'sales_invoices'
       and source_reference in (r.invoice_id::text, r.invoice_number);

    select *
      into v_invoice
      from public.sales_invoices
     where id = r.invoice_id;

    perform public.create_sales_invoice_journal_entry(v_invoice);
  end loop;
end $$;

-- 4) Rebuild ALL payment JEs for affected invoices so they clear AR
--    against the corrected invoice JE (revenue + IVA stay on invoice entry)
do $$
declare
  r record;
  v_payment public.sales_payments%rowtype;
begin
  for r in
    select sp.id as payment_id
      from public.sales_payments sp
      join tmp_broken_sales_tax t on t.invoice_id = sp.invoice_id
  loop
    perform public.delete_sales_payment_journal_entry(r.payment_id);

    select *
      into v_payment
      from public.sales_payments
     where id = r.payment_id;

    perform public.create_sales_payment_journal_entry(v_payment);
  end loop;
end $$;

-- 5) Report what was fixed
select
  count(*) as fixed_invoice_count,
  min(invoice_number) as first_invoice,
  max(invoice_number) as last_invoice
from tmp_broken_sales_tax;

select invoice_number, payment_net_total, payment_iva_total
from tmp_broken_sales_tax
order by invoice_number;

commit;
