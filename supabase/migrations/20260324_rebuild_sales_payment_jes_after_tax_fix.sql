-- Rebuild sales payment journal entries after reverting duplicate IVA recognition
-- Use this when invoice tax fields are already repaired, but payment JEs were created
-- by the temporary broken version of create_sales_payment_journal_entry().
--
-- Tenant: Viñabike
-- Tenant ID: 5443b130-cc28-45af-a420-cd500b288890
-- Date: 2026-03-24

begin;

-- 1) Target all payments for invoices that carry terminal-side IVA
create temp table tmp_sales_payments_to_rebuild as
select distinct
  sp.id as payment_id,
  sp.invoice_id,
  si.invoice_number
from public.sales_payments sp
join public.sales_invoices si
  on si.id = sp.invoice_id
where sp.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and coalesce(sp.iva_amount, 0) > 0;

-- 2) Drop existing payment JEs for that set
delete from public.journal_entries je
using tmp_sales_payments_to_rebuild t
where je.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and je.source_module = 'sales_payments'
  and je.source_reference = t.payment_id::text;

-- 3) Recreate payment JEs using the corrected function
 do $$
declare
  r record;
  v_payment public.sales_payments%rowtype;
begin
  for r in
    select payment_id
    from tmp_sales_payments_to_rebuild
  loop
    select *
      into v_payment
      from public.sales_payments
     where id = r.payment_id;

    perform public.create_sales_payment_journal_entry(v_payment);
  end loop;
end $$;

-- 4) Report
select
  count(*) as rebuilt_payment_je_count,
  min(invoice_number) as first_invoice,
  max(invoice_number) as last_invoice
from tmp_sales_payments_to_rebuild;

select invoice_number, payment_id
from tmp_sales_payments_to_rebuild
order by invoice_number, payment_id;

commit;
