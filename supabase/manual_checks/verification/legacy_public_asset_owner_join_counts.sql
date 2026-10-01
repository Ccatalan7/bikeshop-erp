-- Read-only aggregate test of whether a legacy object path carries a known
-- workshop/customer/tenant UUID. Never returns an object path or person ID.
with assets as (
  select
    o.name,
    split_part(o.name, '/', 1) as folder,
    split_part(o.name, '/', 2) as second_segment
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) in ('presupuestos', 'mechanic_jobs')
)
select
  a.folder,
  count(*) as objects,
  count(*) filter (where a.name ~*
    '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    as path_contains_uuid,
  count(*) filter (where exists (
    select 1 from public.mechanic_jobs j
    where a.second_segment = j.id::text
  )) as second_segment_is_job_id,
  count(*) filter (where exists (
    select 1 from public.customers c
    where a.second_segment = c.id::text
  )) as second_segment_is_customer_id,
  count(*) filter (where exists (
    select 1 from public.tenants t
    where a.second_segment = t.id::text
  )) as second_segment_is_tenant_id,
  count(*) filter (where exists (
    select 1 from public.mechanic_jobs j
    where position(j.id::text in a.name) > 0
  )) as path_contains_job_id
from assets a
group by a.folder
order by a.folder;
