-- La tienda dice «Desde $X» o «A cotizar» donde el ERP lo decidió.
--
-- `products.website_price_mode` nació con la regla única de venta
-- (20261010010000): `exact`, `from` (precio de partida) o `quote` (un
-- servicio que se cotiza; el checkout sigue rechazando un precio de $0). La
-- tienda completa cada fila pública con su identidad web
-- (`publicProductIdentityColumns`, como anónimo) y la ficha la lee
-- `get_public_product_page_v2` (SECURITY INVOKER, columnas nombradas): a
-- ninguno le llegaba el modo, así que /servicios y la ficha del servicio
-- habrían seguido diciendo «Consultar» o el precio a secas.
--
-- 1. Anónimo puede leer esa columna (como `website_price`).
-- 2. La ficha la incluye entre los campos web del producto y los relacionados.

grant select (website_price_mode) on table public.products to anon;

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
  related as (
    select to_jsonb(other) - 'cost' - 'total_count' - 'ordinality' as row,
           other.id,
           other.brand_id,
           other.ordinality as position
      from base
      cross join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_category_ids := array[base.category_id],
             p_only_in_stock := true,
             p_limit := 9
           ) with ordinality other
     where base.category_id is not null
       and other.id <> base.id
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
