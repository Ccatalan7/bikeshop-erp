-- =============================================================================
-- DIAGNOSE + FIX: Invoices with status='paid' but missing payment journal entries
-- Run in Supabase SQL Editor
-- =============================================================================

-- ─── 1. Diagnose: paid invoices → do the sales_payments records exist? ────────
--   paid_with_payment_record  = payment JE can be backfilled
--   paid_NO_payment_record    = payment data is gone, nothing to backfill
--   missing_payment_je        = payment record exists but JE was never created
select
  si.invoice_number,
  si.status,
  to_char(si.date, 'DD/MM/YYYY')        as date,
  si.customer_name,
  si.total,
  count(sp.id)                           as payment_records,
  count(je.id)                           as payment_je_count,
  coalesce(sum(sp.amount), 0)            as total_payments_recorded
from public.sales_invoices si
left join public.sales_payments sp
       on sp.invoice_id = si.id
left join public.journal_entries je
       on je.source_module    = 'sales_payments'
      and je.source_reference = sp.id::text
      and je.tenant_id        = si.tenant_id
where lower(si.status) in ('paid','pagado','pagada')
  -- Only those missing at least one payment JE
  and not exists (
    select 1
      from public.journal_entries pje
     where pje.source_module = 'sales_payments'
       and pje.tenant_id     = si.tenant_id
       and lower(pje.description) like '%' || lower(si.invoice_number) || '%'
  )
group by si.id, si.invoice_number, si.status, si.date, si.customer_name, si.total
order by si.created_at desc;

-- ─── 2. BACKFILL: create payment JEs for payments that exist but have no JE ──
--   Safe to run: create_sales_payment_journal_entry checks for duplicates
do $$
declare
  v_payment public.sales_payments%rowtype;
  v_count   integer := 0;
  v_skipped integer := 0;
begin
  for v_payment in
    select sp.*
      from public.sales_payments sp
     where sp.amount > 0
       -- Payment JE doesn't exist for this payment record
       and not exists (
             select 1
               from public.journal_entries je
              where je.source_module    = 'sales_payments'
                and je.source_reference = sp.id::text
           )
       -- Invoice is paid/confirmed (not draft)
       and exists (
             select 1
               from public.sales_invoices si
              where si.id = sp.invoice_id
                and lower(si.status) in ('paid','confirmed','pagado','pagada','confirmado','confirmada')
           )
  loop
    begin
      perform public.create_sales_payment_journal_entry(v_payment);
      v_count := v_count + 1;
      raise notice 'Backfill payment JE: payment % (amount: %)', v_payment.id, v_payment.amount;
    exception when others then
      v_skipped := v_skipped + 1;
      raise warning 'Backfill payment JE: FAILED for payment % — %', v_payment.id, sqlerrm;
    end;
  end loop;

  raise notice '====================================================';
  raise notice 'Payment JE backfill: % created, % skipped/failed', v_count, v_skipped;
  raise notice '====================================================';
end $$;

-- ─── 3. Final check: should show 0 for missing payment JEs ──────────────────
select
  count(*) filter (
    where lower(si.status) in ('paid','pagado','pagada')
      and sp.id is not null
      and je.id is null
  ) as payments_still_missing_je,
  count(*) filter (
    where lower(si.status) in ('paid','pagado','pagada')
      and sp.id is null
  ) as paid_invoices_with_no_payment_record
from public.sales_invoices si
left join public.sales_payments sp
       on sp.invoice_id = si.id
left join public.journal_entries je
       on je.source_module    = 'sales_payments'
      and je.source_reference = sp.id::text
      and je.tenant_id        = si.tenant_id;
