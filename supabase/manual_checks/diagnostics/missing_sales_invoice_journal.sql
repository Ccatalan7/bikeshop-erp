-- =============================================================================
-- DIAGNOSE: Sales invoices missing their invoice journal entry
-- Run in Supabase SQL Editor
-- =============================================================================

-- ─── 1. Count summary ────────────────────────────────────────────────────────
select
  count(*) filter (
    where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
  )                                                         as total_posted_invoices,
  count(*) filter (
    where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
      and je.id is not null
  )                                                         as invoices_with_je,
  count(*) filter (
    where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
      and je.id is null
  )                                                         as invoices_MISSING_je,
  round(
    100.0 * count(*) filter (
      where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
        and je.id is null
    ) / nullif(count(*) filter (
      where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
    ), 0)
  , 1)                                                      as pct_missing
from public.sales_invoices si
left join public.journal_entries je
       on je.source_module    = 'sales_invoices'
      and je.source_reference = si.invoice_number
      and je.tenant_id        = si.tenant_id;

-- ─── 2. Full list of invoices missing a JE ───────────────────────────────────
select
  si.invoice_number,
  si.status,
  to_char(si.date, 'DD/MM/YYYY')  as date,
  si.customer_name,
  si.total,
  si.net_amount,
  si.iva_amount,
  -- Show whether a payment JE exists (they usually do)
  (select count(*)
     from public.journal_entries pje
    where pje.source_module  = 'sales_payments'
      and pje.tenant_id      = si.tenant_id
      and lower(pje.description) like '%' || lower(si.invoice_number) || '%'
  )                               as payment_je_count,
  si.created_at
from public.sales_invoices si
left join public.journal_entries je
       on je.source_module    = 'sales_invoices'
      and je.source_reference = si.invoice_number
      and je.tenant_id        = si.tenant_id
where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
  and je.id is null
  and si.total > 0
order by si.created_at desc;
