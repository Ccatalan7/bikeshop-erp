-- Read-only, aggregate first pass for the 16 legacy private-purpose objects in
-- the public bucket. No object name, URL, business row or file byte is returned.
-- A non-match means only that these candidate fields had no literal match;
-- URL encoding and other tables can still hold a reference.
with assets as materialized (
  select
    o.name,
    split_part(o.name, '/', 1) as folder,
    coalesce(lower(substring(o.name from '\.([^.]+)$')), 'none')
      as file_extension
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) in ('presupuestos', 'mechanic_jobs')
), candidate_references as materialized (
  select 'mechanic_jobs.image_urls' as source, u.url as reference
  from public.mechanic_jobs j
  cross join lateral unnest(coalesce(j.image_urls, array[]::text[])) u(url)
  union all
  select 'mechanic_job_bikes.image_urls', u.url
  from public.mechanic_job_bikes jb
  cross join lateral unnest(coalesce(jb.image_urls, array[]::text[])) u(url)
  union all
  select 'bikes.image_urls', u.url
  from public.bikes b
  cross join lateral unnest(coalesce(b.image_urls, array[]::text[])) u(url)
  union all
  select 'bikes.image_url', b.image_url from public.bikes b
  union all
  select 'app_files.storage_path', f.storage_path
  from public.app_files f where f.storage_bucket = 'vinabike-assets'
  union all
  select 'messaging_attachments.storage_path', m.storage_path
  from public.messaging_attachments m
  where m.storage_bucket = 'vinabike-assets'
  union all
  select 'expense_attachments.file_url', e.file_url
  from public.expense_attachments e
  union all
  select 'smart_tasks.attachments', t.attachments::text
  from public.smart_tasks t
  union all
  select 'transactional_email_outbox.attachment_manifest',
    t.attachment_manifest::text
  from public.transactional_email_outbox t
), matches as (
  select distinct a.folder, a.file_extension, a.name, r.source
  from assets a
  join candidate_references r
    on r.reference is not null
   and (position(a.name in r.reference) > 0
     or position(replace(a.name, ' ', '%20') in r.reference) > 0)
)
select folder, file_extension, 'objects' as source,
  count(*)::bigint as object_count
from assets
group by folder, file_extension
union all
select folder, file_extension, source, count(*)::bigint
from matches
group by folder, file_extension, source
union all
select a.folder, a.file_extension, 'no_literal_match_in_scanned_fields',
  count(*)::bigint
from assets a
where not exists (select 1 from matches m where m.name = a.name)
group by a.folder, a.file_extension
order by folder, file_extension, source;
