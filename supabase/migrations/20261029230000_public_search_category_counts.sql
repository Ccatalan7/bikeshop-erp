-- 20261029230000: the search box counts its categories without the catalog's
-- filters.
--
-- 2026-10-29, owner: «la búsqueda a veces sigue bastante bumpy… es súper
-- importante este feature». With the production database busy, one search in
-- six answered 503 and others came without their categories. Each keystroke
-- read get_public_product_facets_v2 only for counts like «Cámaras 21», and
-- that read computes every filter of a catalog page: brands, prices and the
-- technical values of every product found. For «camara» it read ~14.4k
-- buffers against ~5.6k for the counts alone, and it is the read that spills
-- to temporary files.
--
-- What changes: get_public_search_category_counts_v1 counts, per active
-- category, the products a search lists. It counts the same universe as
-- get_public_product_facets_v2 (get_public_products with the search's stock
-- rule and no other filter), so the box shows the same numbers.
--
-- Nothing else changes; get_public_product_facets_v2 stays as it is.

create or replace function public.get_public_search_category_counts_v1(
  p_tenant_id uuid,
  p_search_term text,
  p_include_out_of_stock boolean default false
)
returns table(category_id uuid, item_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select found.category_id, count(*)::bigint as item_count
  from public.get_public_products(
    p_tenant_id := p_tenant_id,
    p_category_ids := null,
    p_search_term := p_search_term,
    p_product_type := 'product',
    p_only_in_stock := not coalesce(p_include_out_of_stock, false),
    p_sort_by := 'name',
    p_limit := 2147483647,
    p_offset := 0
  ) found
  join public.product_categories category
    on category.id = found.category_id
   and category.tenant_id = p_tenant_id
   and category.is_active = true
  group by found.category_id
$$;

comment on function public.get_public_search_category_counts_v1(uuid, text, boolean) is
  'The header search box''s categories: per active category, how many products the search lists (2026-10-29).';

revoke all on function public.get_public_search_category_counts_v1(uuid, text, boolean) from public;
grant execute on function public.get_public_search_category_counts_v1(uuid, text, boolean) to anon, authenticated;
