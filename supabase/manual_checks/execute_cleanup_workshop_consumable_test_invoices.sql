-- Execute-ready cleanup for workshop consumable verification invoices.
--
-- This file is intentionally destructive for the known verification prefixes:
-- - TEST-WC-  : workshop consumable sales verification
-- - TEST-WCP- : mixed purchase verification
--
-- Expected result:
-- - returns deleted sales/purchase test invoices
-- - final row reports cleanup_executed = true
-- - remaining_sales = 0
-- - remaining_purchases = 0

drop table if exists tmp_wc_cleanup_settings;

create temporary table tmp_wc_cleanup_settings as
select
  true::boolean as run_cleanup,
  '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
  'TEST-WC-%'::text as sales_prefix,
  'TEST-WCP-%'::text as purchase_prefix;

with settings as (
  select * from tmp_wc_cleanup_settings
),
deleted_sales as (
  delete from public.sales_invoices s
  using settings cfg
  where cfg.run_cleanup = true
    and s.tenant_id = cfg.tenant_id
    and s.invoice_number like cfg.sales_prefix
  returning 'sales'::text as invoice_type, s.id, s.invoice_number, s.status, s.total, s.created_at
),
deleted_purchases as (
  delete from public.purchase_invoices p
  using settings cfg
  where cfg.run_cleanup = true
    and p.tenant_id = cfg.tenant_id
    and p.invoice_number like cfg.purchase_prefix
  returning 'purchase'::text as invoice_type, p.id, p.invoice_number, p.status, p.total, p.created_at
)
select *
from deleted_sales
union all
select *
from deleted_purchases
order by created_at desc, invoice_type, invoice_number;

with settings as (
  select * from tmp_wc_cleanup_settings
)
select
  cfg.run_cleanup as cleanup_executed,
  'Cleanup executed.' as message,
  (select count(*) from public.sales_invoices s where s.tenant_id = cfg.tenant_id and s.invoice_number like cfg.sales_prefix) as remaining_sales,
  (select count(*) from public.purchase_invoices p where p.tenant_id = cfg.tenant_id and p.invoice_number like cfg.purchase_prefix) as remaining_purchases
from settings cfg;