-- Verify owner consistency for the legacy public job images that have a
-- literal reference. Output is aggregate only; no URL, job or customer ID.
with assets as (
  select o.name, split_part(o.name, '/', 2) as customer_segment
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) = 'mechanic_jobs'
), job_references as (
  select distinct a.name, j.id as job_id, j.customer_id, j.tenant_id
  from assets a
  join public.mechanic_jobs j on exists (
    select 1
    from unnest(coalesce(j.image_urls, array[]::text[])) u(url)
    where position(a.name in u.url) > 0
       or position(replace(a.name, ' ', '%20') in u.url) > 0
  )
), owned as (
  select r.name, r.job_id, r.customer_id, r.tenant_id,
    c.id as path_customer_id, c.tenant_id as customer_tenant_id
  from job_references r
  join assets a on a.name = r.name
  left join public.customers c on c.id::text = a.customer_segment
)
select
  count(distinct name) as referenced_objects,
  count(*) as reference_pairs,
  count(*) filter (where path_customer_id is null) as missing_path_customer,
  count(*) filter (where customer_id is distinct from path_customer_id)
    as job_customer_mismatches,
  count(*) filter (where tenant_id is distinct from customer_tenant_id)
    as job_tenant_mismatches,
  count(distinct tenant_id) as referenced_tenants
from owned;
