-- 20261128083000: the stamp the store server asks before trusting a page it
-- kept. Fails when the function is missing or closed to the public key, when
-- its answer is not a steady md5, when the list names a table that does not
-- exist, or when a read of a kept page reaches a table the list does not
-- name. Run it again after adding a read to a public page:
--   scripts/db/query.sh production --file supabase/manual_checks/verify_public_storefront_change_stamp.sql
-- Plain SQL, no transaction control: it runs through the read-only wrapper.

select
  to_regprocedure('public.get_public_storefront_change_stamp_v1(uuid)') is not null
    as existe,
  public.get_public_storefront_change_stamp_v1(
    '5443b130-cc28-45af-a420-cd500b288890') as huella,
  coalesce(cardinality(private.public_storefront_watched_tables_v1()), 0)
    as tablas_vigiladas;

select 1 / case
  when has_function_privilege('anon',
         'public.get_public_storefront_change_stamp_v1(uuid)', 'EXECUTE')
   and has_function_privilege('service_role',
         'public.get_public_storefront_change_stamp_v1(uuid)', 'EXECUTE')
   and not has_function_privilege('anon',
         'private.public_storefront_watched_tables_v1()', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'private.public_storefront_watched_tables_v1()', 'EXECUTE')
   and (select p.prosecdef and p.provolatile = 's'
               and p.proconfig = array['search_path=""']
          from pg_proc p
         where p.oid =
           'public.get_public_storefront_change_stamp_v1(uuid)'::regprocedure)
  then 1 else 0 end as afirma_publica_y_cerrada;

-- An md5, and the same one when nothing was written in between.
select 1 / case
  when public.get_public_storefront_change_stamp_v1(
         '5443b130-cc28-45af-a420-cd500b288890') ~ '^[0-9a-f]{32}$'
   and public.get_public_storefront_change_stamp_v1(
         '5443b130-cc28-45af-a420-cd500b288890')
     = public.get_public_storefront_change_stamp_v1(
         '5443b130-cc28-45af-a420-cd500b288890')
  then 1 else 0 end as afirma_huella_estable;

-- Another shop's site does not share this one's editor rows.
select 1 / case
  when public.get_public_storefront_change_stamp_v1(
         '5443b130-cc28-45af-a420-cd500b288890')
    <> public.get_public_storefront_change_stamp_v1(
         '00000000-0000-4000-8000-000000000000')
  then 1 else 0 end as afirma_huella_por_tienda;

-- Every name in the list is a table of `public`, once.
select name as tabla_que_no_existe
  from unnest(private.public_storefront_watched_tables_v1()) as watched(name)
 where to_regclass('public.' || quote_ident(name)) is null;

select 1 / case
  when (select count(*) = count(distinct name)
               and count(*) filter (
                     where to_regclass('public.' || quote_ident(name)) is null
                   ) = 0
          from unnest(private.public_storefront_watched_tables_v1())
               as watched(name))
  then 1 else 0 end as afirma_tablas_reales;

-- Every table the reads of a kept page reach, following function bodies from
-- the functions the server calls, is in the list.
with recursive
roots(name) as (values
  ('get_public_storefront_shell_if_changed_v1'),
  ('get_public_checkout_capabilities'),
  ('get_public_product_page_v2'),
  ('get_public_sold_out_offers_v1'),
  ('get_public_products'),
  ('get_public_products_faceted_v2'),
  ('get_public_product_facets_v2'),
  ('get_public_spec_option_labels_v1'),
  ('get_public_image_thumbnails_v1'),
  ('get_public_featured_products'),
  ('resolve_public_product_url_alias')
),
fn as (
  select p.proname::text collate "C" as proname, p.prosrc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private')
     and p.prokind = 'f'
),
names as (select distinct proname from fn),
walk(proname, depth) as (
  select name::text collate "C", 0 from roots
  union
  select callee.proname, w.depth + 1
    from walk w
    join fn caller on caller.proname = w.proname
    join names callee
      on callee.proname <> caller.proname
     and length(callee.proname) > 5
     and caller.prosrc ~ ('(^|[^a-z_0-9])' || callee.proname || '\s*\(')
   where w.depth < 8
),
reached as (select distinct proname from walk),
tables as (
  select c.relname::text collate "C" as relname
    from pg_class c
   where c.relnamespace = 'public'::regnamespace
     and c.relkind in ('r', 'p')
     and length(c.relname) > 4
),
read as (
  select distinct t.relname
    from reached x
    join fn f on f.proname = x.proname
    join tables t
      on f.prosrc ~ ('(^|[^a-z_0-9])' || t.relname || '($|[^a-z_0-9(])')
),
missing as (
  select relname from read
  except
  select name from unnest(private.public_storefront_watched_tables_v1())
              as watched(name)
)
-- The failure names what is missing: a cast that cannot be made, so the
-- error carries the list instead of a bare «division by zero».
select (select count(*) from reached) as funciones_seguidas,
       (select count(*) from read) as tablas_leidas,
       case
         when (select count(*) from reached) < 11
           or (select count(*) from read) < 20
           then ('el recorrido no alcanzó las lecturas públicas: '
                 || (select count(*) from reached) || ' funciones, '
                 || (select count(*) from read) || ' tablas')::integer
         when exists (select 1 from missing)
           then ('tablas que una página lee y la huella no vigila: '
                 || (select string_agg(relname, ', ' order by relname)
                       from missing))::integer
         else 1
       end as afirma_todo_vigilado;
