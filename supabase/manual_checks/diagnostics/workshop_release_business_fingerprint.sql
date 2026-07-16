-- Read-only, no-PII release fingerprint for workshop schema deployments.
--
-- Run immediately before and after each DDL-only workshop migration. The
-- server hashes complete rows but returns only table name, count and digest;
-- no customer or business payload leaves PostgreSQL. A changed digest means
-- business data changed during the window and must be investigated before the
-- next migration. This intentionally excludes the new status-event table so
-- the same query works before migration 080 creates it.

select 'bikes' as relation, count(*) as row_count,
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5('')) as digest
from public.bikes t
union all
select 'mechanic_jobs', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.mechanic_jobs t
union all
select 'mechanic_job_items', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.mechanic_job_items t
union all
select 'mechanic_job_bikes', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.mechanic_job_bikes t
union all
select 'mechanic_job_mode_events', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.mechanic_job_mode_events t
union all
select 'mechanic_job_delivery_events', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.mechanic_job_delivery_events t
union all
select 'mechanic_job_warranty_claim_events', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.mechanic_job_warranty_claim_events t
union all
select 'sales_invoices', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.sales_invoices t
union all
select 'sales_payments', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.sales_payments t
union all
select 'products', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.products t
union all
select 'stock_movements', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.stock_movements t
union all
select 'stock_adjustments', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.stock_adjustments t
union all
select 'inventory_accounting_operations', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.inventory_accounting_operations t
union all
select 'journal_entries', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.journal_entries t
union all
select 'journal_lines', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.journal_lines t
union all
select 'smart_tasks', count(*),
       coalesce(md5(string_agg(md5(to_jsonb(t)::text), '' order by id::text)), md5(''))
from public.smart_tasks t
order by relation;
