-- Aggregate path shape and upload-owner availability for legacy internal
-- assets. No object name, owner ID, URL, business row or byte is returned.
with scoped as (
  select
    split_part(o.name, '/', 1) as folder,
    o.owner_id,
    o.created_at,
    array_length(string_to_array(o.name, '/'), 1) as path_segments,
    coalesce(lower(substring(o.name from '\.([^.]+)$')), 'none')
      as file_extension,
    split_part(o.name, '/', 2) ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      as second_segment_is_uuid,
    case
      when o.metadata->>'mimetype' like 'image/%' then 'image'
      when o.metadata->>'mimetype' = 'application/pdf' then 'pdf'
      else 'other_or_unknown'
    end as media_class
  from storage.objects o
  where o.bucket_id = 'vinabike-assets'
    and split_part(o.name, '/', 1) in ('presupuestos', 'mechanic_jobs')
)
select
  folder,
  media_class,
  file_extension,
  count(*) as objects,
  count(owner_id) as with_storage_owner,
  count(distinct owner_id) as distinct_storage_owners,
  min(path_segments) as min_path_segments,
  max(path_segments) as max_path_segments,
  count(*) filter (where second_segment_is_uuid) as second_segment_uuid,
  min(created_at::date) as first_created_date,
  max(created_at::date) as last_created_date
from scoped
group by folder, media_class, file_extension
order by folder, media_class, file_extension;
