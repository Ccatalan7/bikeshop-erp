-- Read-only catalog of business tables/columns plausibly holding a budget PDF
-- reference. Returns schema names only, never business rows or object paths.
select
  c.relname as table_name,
  string_agg(
    a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod),
    ', ' order by a.attname
  ) as columns
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
join pg_catalog.pg_attribute a on a.attrelid = c.oid
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and a.attnum > 0
  and not a.attisdropped
  and c.relname ~* '(budget|quote|quotation|estimate|presupuest)'
group by c.relname
order by c.relname;
