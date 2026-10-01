-- Candidate public columns that can hold references to legacy workshop files.
-- Catalog only: no business rows, object names, URLs, or file bytes are read.
select
  c.relname as table_name,
  string_agg(
    a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod),
    ', ' order by a.attname
  ) as candidate_columns
from pg_catalog.pg_attribute a
join pg_catalog.pg_class c on c.oid = a.attrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and a.attnum > 0
  and not a.attisdropped
  and a.attname ~* '(^|_)(url|urls|image|images|file|files|attachment|attachments|pdf|path|bucket)(_|$)'
group by c.relname
order by c.relname;
