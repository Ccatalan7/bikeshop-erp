-- Lo que va con el producto (2026-10-23).
--
-- Las tiendas grandes ofrecen junto a un neumático las cámaras de su medida.
-- La ficha técnica ya lo sabe: 121 neumáticos tienen su aro y su ancho en mm
-- (`bead_seat_diameter_mm`, `tire_width_mm`) y 124 cámaras su rango
-- (`tube_fit_rows`: aro, ancho mínimo y máximo). Una cámara calza con un
-- neumático cuando una de sus filas tiene el mismo aro y un rango que
-- incluye el ancho del neumático (wiki de compatibilidad, ruedas y
-- neumáticos). La válvula depende del agujero de la llanta, que el
-- neumático no dice: se ofrecen las dos y la tienda lo explica.
--
-- 1. `get_public_product_fits_v1`: para un neumático, las cámaras que
--    calzan; para una cámara, los neumáticos que calza. Sólo productos que
--    la tienda publica y tiene en stock, del más barato al más caro.
-- 2. `get_public_product_page_v2` los devuelve en `fits` ({kind, items}).
-- Rerunnable: create or replace.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create or replace function public.get_public_product_fits_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_limit integer default 6
)
returns table(kind text, product_id uuid, fit_position integer)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with facts as (
    -- The product facts the fit reads, customer-visible definitions only.
    select f.subject_id, d.key, f.value_number, f.value_json
      from public.spec_facts f
      join public.spec_definitions d on d.id = f.spec_definition_id
     where f.tenant_id = p_tenant_id
       and f.subject_type = 'product'
       and f.subject_scope is null
       and d.is_customer_visible
       and d.key in ('bead_seat_diameter_mm', 'tire_width_mm', 'tube_fit_rows')
  ),
  tube_rows as (
    select facts.subject_id,
           (row_value->'values'->>'bead_seat_diameter_mm')::numeric as bsd,
           (row_value->'values'->>'width_min_mm')::numeric as width_min,
           (row_value->'values'->>'width_max_mm')::numeric as width_max
      from facts
      cross join lateral jsonb_array_elements(
             case when jsonb_typeof(facts.value_json->'rows') = 'array'
               then facts.value_json->'rows' else '[]'::jsonb end) row_value
     where facts.key = 'tube_fit_rows'
       and row_value->'values'->>'bead_seat_diameter_mm' ~ '^[0-9]+(\.[0-9]+)?$'
       and row_value->'values'->>'width_min_mm' ~ '^[0-9]+(\.[0-9]+)?$'
       and row_value->'values'->>'width_max_mm' ~ '^[0-9]+(\.[0-9]+)?$'
  ),
  tyres as (
    select diameter.subject_id,
           diameter.value_number as bsd,
           width.value_number as width
      from facts diameter
      join facts width
        on width.subject_id = diameter.subject_id
       and width.key = 'tire_width_mm'
       and width.value_number is not null
     where diameter.key = 'bead_seat_diameter_mm'
       and diameter.value_number is not null
       and not exists (
         select 1 from tube_rows where tube_rows.subject_id = diameter.subject_id
       )
  ),
  matches as (
    -- A tyre: the tubes whose rows hold it.
    select 'tubes'::text as kind, tube_rows.subject_id as id
      from tyres
      join tube_rows
        on tube_rows.bsd = tyres.bsd
       and tyres.width between tube_rows.width_min and tube_rows.width_max
     where tyres.subject_id = p_product_id
    union
    -- A tube: the tyres its rows hold.
    select 'tyres'::text, tyres.subject_id
      from tube_rows
      join tyres
        on tyres.bsd = tube_rows.bsd
       and tyres.width between tube_rows.width_min and tube_rows.width_max
     where tube_rows.subject_id = p_product_id
  ),
  listed as (
    select listed.id, listed.price, listed.name
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             -- An empty or null list is the whole catalog to the listing:
             -- with no match it reads only the product itself, left out below.
             p_product_ids := coalesce(
               (select array_agg(distinct matches.id) from matches),
               array[p_product_id]),
             p_only_in_stock := true,
             p_limit := 200
           ) listed
     where listed.id <> p_product_id
  )
  select (select min(matches.kind) from matches),
         listed.id,
         row_number() over (order by listed.price, listed.name)::integer
    from listed
   where exists (select 1 from matches)
   order by 3
   limit greatest(1, least(coalesce(p_limit, 6), 24))
$$;

comment on function public.get_public_product_fits_v1(uuid, uuid, integer) is
  'What goes with a product, by its technical sheet: the tubes that fit a tyre (same bead seat diameter, tyre width inside the tube''s range) or the tyres a tube fits. Published and in stock only, cheapest first.';

revoke all on function public.get_public_product_fits_v1(uuid, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_fits_v1(uuid, uuid, integer)
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
  fits as (
    -- What goes with the product: the tubes that fit a tyre, the tyres a
    -- tube fits (20261024020000), cheapest first.
    select to_jsonb(item) - 'cost' - 'total_count' as row,
           item.id,
           item.brand_id,
           fit.kind,
           fit.fit_position as position
      from base
      cross join lateral public.get_public_product_fits_v1(
             p_tenant_id, base.id, 6) fit
      join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := array[fit.product_id],
             p_only_in_stock := true,
             p_limit := 1
           ) item on true
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
       and p.id in (
         select id from base
         union all select id from related
         union all select id from fits
       )
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
               union
               select fits.brand_id from fits
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
    ), '[]'::jsonb),
    'fits', coalesce((
      select jsonb_build_object(
               'kind', min(fits.kind),
               'items', jsonb_agg(
                 fits.row || coalesce(website.fields, '{}'::jsonb)
                 order by fits.position))
        from fits
        left join website on website.id = fits.id
    ), '{}'::jsonb)
  )
    from base;
$$;

commit;
