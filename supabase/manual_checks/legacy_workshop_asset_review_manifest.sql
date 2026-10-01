-- Read-only, deliberately explicit per-object review input for C3.
-- Store the output privately under .tmp; never publish customer/job IDs or URLs.
-- Exact current references are checked again before an authorized future copy.
select o.id as object_id, o.bucket_id, o.name as source_path,
       o.metadata ->> 'mimetype' as content_type,
       nullif(o.metadata ->> 'size','')::bigint as declared_bytes,
       o.created_at, o.updated_at,
       coalesce((select jsonb_agg(jsonb_build_object(
         'job_id', j.id, 'tenant_id', j.tenant_id, 'customer_id', j.customer_id,
         'reference', u.url))
         from public.mechanic_jobs j
         cross join lateral unnest(coalesce(j.image_urls, array[]::text[])) u(url)
         where u.url = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/' || o.name
            or u.url = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/' || replace(o.name, ' ', '%20')),
         '[]'::jsonb) as exact_job_references,
       (select jsonb_build_object('customer_id',c.id,'tenant_id',c.tenant_id)
          from public.customers c
         where c.id::text = split_part(o.name,'/',2)) as path_customer
from storage.objects o
where o.bucket_id='vinabike-assets'
  and split_part(o.name,'/',1) in ('mechanic_jobs','presupuestos')
order by o.name;
