-- Read-back for 20261029230000: the search box's category counts are the
-- facets' own, for searches a customer types.

-- The function exists, runs as its owner and the store (anon) may call it.
select p.proname, p.prosecdef, has_function_privilege('anon', p.oid, 'execute') as anon_can
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_public_search_category_counts_v1';

select 1 / (case when exists (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_public_search_category_counts_v1'
    and p.prosecdef
    and has_function_privilege('anon', p.oid, 'execute')
) then 1 else 0 end) as function_is_public;

-- Same rows as the category facet of get_public_product_facets_v2: in stock,
-- and with «Incluir agotados».
with terms(term, out_too) as (
  values
    ('camara', false), ('neumatico 29', false), ('cadena', false),
    ('pastillas', false), ('freno', false), ('casco', true)
), light as (
  select t.term, t.out_too, c.category_id::text as id, c.item_count
  from terms t
  cross join lateral public.get_public_search_category_counts_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, t.term, t.out_too
  ) c
), heavy as (
  select t.term, t.out_too, f.value_id as id, f.item_count
  from terms t
  cross join lateral public.get_public_product_facets_v2(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, t.term, 'product',
    false, null, null, null, null, t.out_too
  ) f
  where f.facet_key = 'category'
), diff as (
  (select * from light except select * from heavy)
  union all
  (select * from heavy except select * from light)
)
select
  (select count(*) from light) as light_rows,
  (select count(*) from heavy) as heavy_rows,
  (select count(*) from diff) as differences,
  1 / (case
    when (select count(*) from diff) = 0 and (select count(*) from light) > 0
      then 1 else 0
  end) as counts_match_facets;
