-- Cleanup helper for workshop consumable verification invoices.
--
-- This script is intentionally non-destructive by default:
-- 1) preview matching sales and purchase test invoices
-- 2) review the rows/counts
-- 3) uncomment the delete block when ready
--
-- Prefixes created by current manual checks:
-- - TEST-WC-  : workshop consumable sales verification
-- - TEST-WCP- : mixed purchase verification
--
-- NOTE:
-- Deleting purchase invoices that reached 'received' should restore inventory
-- through the existing trigger logic.

drop table if exists tmp_wc_cleanup_settings;

create temporary table tmp_wc_cleanup_settings as
select
  false::boolean as run_cleanup,
  '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
  'TEST-WC-%'::text as sales_prefix,
  'TEST-WCP-%'::text as purchase_prefix;

with settings as (
  select * from tmp_wc_cleanup_settings
),
target_invoices as (
  select
    'sales'::text as invoice_type,
    s.id,
    s.tenant_id,
    s.invoice_number,
    s.status,
    s.total,
    s.created_at
  from public.sales_invoices s
  cross join settings cfg
  where s.tenant_id = cfg.tenant_id
    and s.invoice_number like cfg.sales_prefix

  union all

  select
    'purchase'::text as invoice_type,
    p.id,
    p.tenant_id,
    p.invoice_number,
    p.status,
    p.total,
    p.created_at
  from public.purchase_invoices p
  cross join settings cfg
  where p.tenant_id = cfg.tenant_id
    and p.invoice_number like cfg.purchase_prefix
)
select *
from target_invoices
order by created_at desc, invoice_type, invoice_number;

with settings as (
  select * from tmp_wc_cleanup_settings
),
counts as (
  select
    count(*) filter (where invoice_type = 'sales') as sales_test_invoices,
    count(*) filter (where invoice_type = 'purchase') as purchase_test_invoices,
    count(*) as total_test_invoices
  from (
    select 'sales'::text as invoice_type
    from public.sales_invoices s
    cross join settings cfg
    where s.tenant_id = cfg.tenant_id
      and s.invoice_number like cfg.sales_prefix

    union all

    select 'purchase'::text as invoice_type
    from public.purchase_invoices p
    cross join settings cfg
    where p.tenant_id = cfg.tenant_id
      and p.invoice_number like cfg.purchase_prefix
  ) q
)
select * from counts;

-- To execute cleanup, change run_cleanup to true in tmp_wc_cleanup_settings above
-- and rerun the file.

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
  case
    when cfg.run_cleanup then 'Cleanup executed.'
    else 'Preview only. Set run_cleanup = true in tmp_wc_cleanup_settings to delete.'
  end as message,
  (select count(*) from public.sales_invoices s where s.tenant_id = cfg.tenant_id and s.invoice_number like cfg.sales_prefix) as remaining_sales,
  (select count(*) from public.purchase_invoices p where p.tenant_id = cfg.tenant_id and p.invoice_number like cfg.purchase_prefix) as remaining_purchases
from settings cfg;
