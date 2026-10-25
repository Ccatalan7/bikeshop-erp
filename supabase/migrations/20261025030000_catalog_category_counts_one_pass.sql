-- «Categorías» of the store catalog counted in one pass.
--
-- `catalog_category_counts_v1` answered every category with four correlated
-- subqueries over the catalog's items and the category tree: with 147
-- categories and 1.688 items it took 8,1 s in production on 2026-10-25,
-- over the 8 s statement timeout of a signed-in user, so «Catálogo de la
-- tienda» showed «No se pudo leer el catálogo» (57014). The items cost 2,3 s;
-- the rest was the per-category recounting. Same signature, same rows and
-- the same numbers, now from one join of the tree with the items, grouped
-- once.

create or replace function public.catalog_category_counts_v1(p_tenant_id uuid)
returns table (
  category_id uuid,
  name text,
  parent_id uuid,
  full_path text,
  level integer,
  sort_order integer,
  show_on_website boolean,
  subcategories integer,
  selling integer,
  out_of_stock integer,
  needs_attention integer,
  selling_direct integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);

  return query
  with recursive cat as (
    select c.id, c.name, c.parent_id, c.full_path, c.level, c.sort_order,
           c.show_on_website
      from public.product_categories c
     where c.tenant_id = p_tenant_id
       and c.is_active = true
  ), tree(root, id, depth) as (
    select cat.id, cat.id, 0 from cat
    union all
    select tree.root, child.id, tree.depth + 1
      from tree
      join cat child on child.parent_id = tree.id
     where tree.depth < 12
  ), items as materialized (
    select i.category_id, i.state
      from public.catalog_web_items_v1(p_tenant_id) i
     where i.kind in ('product', 'kit')
  ), per_category as (
    select i.category_id,
           count(*) filter (where i.state = 'venta')   as selling,
           count(*) filter (where i.state = 'agotado') as out_of_stock,
           count(*) filter (where i.state = 'falta')   as needs_attention
      from items i
     where i.category_id is not null
     group by i.category_id
  ), per_root as (
    select t.root,
           count(*) filter (where t.depth > 0)       as subcategories,
           coalesce(sum(p.selling), 0)               as selling,
           coalesce(sum(p.out_of_stock), 0)          as out_of_stock,
           coalesce(sum(p.needs_attention), 0)       as needs_attention
      from tree t
      left join per_category p on p.category_id = t.id
     group by t.root
  )
  select cat.id,
         cat.name,
         cat.parent_id,
         cat.full_path,
         cat.level,
         cat.sort_order,
         coalesce(cat.show_on_website, false),
         coalesce(r.subcategories, 0)::integer,
         coalesce(r.selling, 0)::integer,
         coalesce(r.out_of_stock, 0)::integer,
         coalesce(r.needs_attention, 0)::integer,
         coalesce(d.selling, 0)::integer
    from cat
    left join per_root r on r.root = cat.id
    left join per_category d on d.category_id = cat.id
   order by cat.full_path nulls last, cat.name;
end;
$$;

revoke all on function public.catalog_category_counts_v1(uuid) from public, anon;
grant execute on function public.catalog_category_counts_v1(uuid) to authenticated;
