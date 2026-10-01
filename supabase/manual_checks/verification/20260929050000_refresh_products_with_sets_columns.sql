-- Production read-back for 20260929050000. SQL-level failure is intentional.
with shape as (
  select
    (select count(*) from pg_attribute
      where attrelid = 'public.products'::regclass
        and attnum > 0 and not attisdropped) as product_columns,
    (select count(*) from pg_attribute
      where attrelid = 'public.products_with_sets'::regclass
        and attnum > 0 and not attisdropped) as view_columns,
    (select count(*) from pg_attribute v
      where v.attrelid = 'public.products_with_sets'::regclass
        and v.attnum > 0 and not v.attisdropped
        and not exists (
          select 1 from pg_attribute p
          where p.attrelid = 'public.products'::regclass
            and p.attnum > 0 and not p.attisdropped
            and p.attname = v.attname)) as calculated_columns
)
select product_columns, view_columns, calculated_columns from shape;

select 1 / (case when
  (select count(*) from pg_attribute v
   where v.attrelid = 'public.products_with_sets'::regclass
     and v.attnum > 0 and not v.attisdropped)
    = (select count(*) + 4 from pg_attribute p
       where p.attrelid = 'public.products'::regclass
         and p.attnum > 0 and not p.attisdropped)
  and not exists (
    select 1 from pg_attribute p
    where p.attrelid = 'public.products'::regclass
      and p.attnum > 0 and not p.attisdropped
      and not exists (
        select 1 from pg_attribute v
        where v.attrelid = 'public.products_with_sets'::regclass
          and v.attnum > 0 and not v.attisdropped
          and v.attname = p.attname
          and v.atttypid = p.atttypid))
  then 1 else 0 end) as all_product_columns_keep_names_and_types;

select 1 / (case when
  (select array_agg(v.attname order by v.attname)
   from pg_attribute v
   where v.attrelid = 'public.products_with_sets'::regclass
     and v.attnum > 0 and not v.attisdropped
     and not exists (
       select 1 from pg_attribute p
       where p.attrelid = 'public.products'::regclass
         and p.attnum > 0 and not p.attisdropped
         and p.attname = v.attname))
  = array['full_sets_available', 'is_partial', 'parent_set_info',
          'set_components']::name[]
  then 1 else 0 end) as only_the_four_set_fields_are_extra;

select 1 / (case when
  (select coalesce(c.reloptions, array[]::text[])
   from pg_class c where c.oid = 'public.products_with_sets'::regclass)
      @> array['security_invoker=true']::text[]
  and not has_table_privilege('anon', 'public.products_with_sets', 'SELECT')
  and has_table_privilege('authenticated', 'public.products_with_sets', 'SELECT')
  and has_table_privilege('service_role', 'public.products_with_sets', 'SELECT')
  then 1 else 0 end) as invoker_and_role_boundary;

select id, set_components, full_sets_available, is_partial, parent_set_info
from public.products_with_sets
limit 0;
