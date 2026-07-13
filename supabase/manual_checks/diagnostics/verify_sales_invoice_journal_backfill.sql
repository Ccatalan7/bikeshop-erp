-- =============================================================================
-- VERIFY: Confirm backfill worked — all sales invoices should now have JEs
-- Run in Supabase SQL Editor
-- =============================================================================

-- ─── 1. Summary: should show invoices_MISSING_je = 0 ────────────────────────
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
  )                                                         as invoices_MISSING_je
from public.sales_invoices si
left join public.journal_entries je
       on je.source_module    = 'sales_invoices'
      and je.source_reference = si.invoice_number
      and je.tenant_id        = si.tenant_id;

-- ─── 2. Spot-check: last 10 invoices — both columns should be non-null ───────
select
  si.invoice_number,
  si.status,
  to_char(si.date, 'DD/MM/YYYY') as date,
  si.customer_name,
  si.total,
  je.entry_number                 as invoice_je,
  pje.entry_number                as latest_payment_je
from public.sales_invoices si
left join public.journal_entries je
       on je.source_module    = 'sales_invoices'
      and je.source_reference = si.invoice_number
      and je.tenant_id        = si.tenant_id
left join lateral (
  select entry_number
    from public.journal_entries pje2
   where pje2.source_module = 'sales_payments'
     and pje2.tenant_id     = si.tenant_id
     and lower(pje2.description) like '%' || lower(si.invoice_number) || '%'
   order by pje2.created_at desc
   limit 1
) pje on true
where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
order by si.created_at desc
limit 10;
