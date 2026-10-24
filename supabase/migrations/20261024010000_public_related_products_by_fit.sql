-- Relacionados que calzan (2026-10-23).
--
-- La ficha mostraba como relacionados los 9 primeros en stock de la misma
-- categoría por nombre: a un neumático de ruta 700 x 23C le sugería
-- neumáticos de 20″, 24″ y 26″. Las tiendas grandes muestran primero lo que
-- comparte la medida.
--
-- 1. `get_public_related_fit_v1`: cuántos valores filtrables de la ficha
--    técnica (aro, ancho, uso, velocidades, tipo de freno…, los mismos que la
--    tienda ofrece como filtro) comparte cada candidato con el producto.
--    Sólo cuenta candidatos que la tienda publica (`get_public_products`).
-- 2. `get_public_product_page_v2` toma hasta 48 candidatos de la categoría y
--    devuelve los 9 que más comparten; a igual puntaje, el orden del catálogo.
-- La vista previa del editor (Flutter) ordena sus candidatos con la misma
-- función.
-- Rerunnable: create or replace.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create or replace function public.get_public_related_fit_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_candidate_ids uuid[]
)
returns table(product_id uuid, shared integer)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with published as (
    -- Only what the store lists, and at most 60 candidates.
    select listed.id
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := (
               select array_agg(candidate)
                 from (
                   select distinct candidate
                     from unnest(p_candidate_ids) candidate
                    where candidate is not null
                    limit 60
                 ) bounded
             ) || array[p_product_id],
             p_only_in_stock := false,
             p_limit := 61
           ) listed
  ),
  facts as (
    select value.product_id, value.spec_key, value.value_text
      from public.spec_public_facet_values_compute_internal_v1(
             p_tenant_id,
             (select array_agg(published.id) from published)
           ) value
  ),
  own as (
    select facts.spec_key, facts.value_text
      from facts
     where facts.product_id = p_product_id
  )
  select published.id,
         count(own.spec_key)::integer
    from published
    left join facts on facts.product_id = published.id
    left join own
      on own.spec_key = facts.spec_key
     and own.value_text = facts.value_text
   where published.id <> p_product_id
     and exists (select 1 from published p where p.id = p_product_id)
   group by published.id
$$;

comment on function public.get_public_related_fit_v1(uuid, uuid, uuid[]) is
  'How many filterable spec values each published candidate shares with the product (aro, ancho, uso…): the related products of a product page are ranked by it. Security definer over the public listing and the public facet values.';

revoke all on function public.get_public_related_fit_v1(uuid, uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_related_fit_v1(uuid, uuid, uuid[])
  to anon, authenticated, service_role;

create or replace function public.get_public_product_page_v2(
  p_tenant_id uuid,
  p_sku text default null,
  p_product_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = public, pg_temp
stable
as $$
  with base as (
    select to_jsonb(product) - 'cost' - 'total_count' as row,
           product.id,
           product.category_id,
           product.brand_id
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := case
               when p_product_id is not null then array[p_product_id]
             end,
             p_sku := case when p_product_id is null then p_sku end,
             p_only_in_stock := false,
             p_limit := 1
           ) product
     -- Without a SKU or an id the listing would return any product.
     where p_product_id is not null or nullif(btrim(p_sku), '') is not null
     limit 1
  ),
  candidates as (
    -- Up to 48 of the category in stock, in the catalog's order; the fit
    -- ranks them below.
    select to_jsonb(other) - 'cost' - 'total_count' - 'ordinality' as row,
           other.id,
           other.brand_id,
           other.ordinality as position
      from base
      cross join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_category_ids := array[base.category_id],
             p_only_in_stock := true,
             p_limit := 49
           ) with ordinality other
     where base.category_id is not null
       and other.id <> base.id
  ),
  fit as (
    select score.product_id, score.shared
      from base
      cross join lateral public.get_public_related_fit_v1(
             p_tenant_id,
             base.id,
             (select array_agg(candidates.id) from candidates)
           ) score
  ),
  scored as (
    select candidates.row, candidates.id, candidates.brand_id,
           candidates.position as catalog_position,
           coalesce(fit.shared, 0) as shared,
           max(coalesce(fit.shared, 0)) over () as best
      from candidates
      left join fit on fit.product_id = candidates.id
  ),
  related as (
    -- The ones that share more of the product's filterable spec values
    -- first (a 700 x 23C road tyre: other 700c road tyres), then the
    -- catalog's order. When some share a value, the ones that share none
    -- are left out (no 20-inch tyre under a road tyre); when none do, the
    -- category in the catalog's order, as before.
    select scored.row, scored.id, scored.brand_id,
           row_number() over (
             order by scored.shared desc, scored.catalog_position
           ) as position
      from scored
     where scored.best = 0 or scored.shared > 0
     order by 4
     limit 9
  ),
  website as (
    select p.id, to_jsonb(fields) as fields
      from public.products p
      cross join lateral (
        select p.is_set, p.set_type, p.parent_set_id, p.component_label,
               p.component_position, p.website_name, p.website_price,
               p.website_price_mode, p.website_description, p.website_seo_title,
               p.website_seo_description, p.website_search_terms,
               p.website_merchant_title, p.website_merchant_description,
               p.website_merchant_brand, p.website_merchant_gtin,
               p.website_merchant_mpn, p.website_google_product_category,
               p.website_image_url, p.website_image_url_optimized,
               p.website_image_urls, p.price_currency
      ) fields
     where p.tenant_id = p_tenant_id
       and p.id in (select id from base union all select id from related)
  )
  select jsonb_build_object(
    'product', base.row || coalesce(
      (select website.fields from website where website.id = base.id),
      '{}'::jsonb),
    -- Raw rows of this store's or global brands: the client decides with
    -- canonicalPublicProductBrandNames, the rule the Flutter store applies.
    'brand_rows', coalesce((
      select jsonb_agg(to_jsonb(brand))
        from (
          select b.id, b.name, b.tenant_id, b.is_active
            from public.product_brands b
           where b.is_active
             and (b.tenant_id = p_tenant_id or b.tenant_id is null)
             and b.id in (
               select base.brand_id
               union
               select related.brand_id from related
             )
        ) brand
    ), '[]'::jsonb),
    'specs', coalesce((
      select jsonb_agg(to_jsonb(spec))
        from public.get_public_product_technical_specs(p_tenant_id, base.id) spec
    ), '[]'::jsonb),
    'related', coalesce((
      select jsonb_agg(
               related.row || coalesce(website.fields, '{}'::jsonb)
               order by related.position)
        from related
        left join website on website.id = related.id
    ), '[]'::jsonb)
  )
    from base;
$$;

commit;
