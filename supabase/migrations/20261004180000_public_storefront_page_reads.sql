-- One round trip per public page for the HTML storefront.
--
-- The storefront moves from Flutter to HTML rendered on a server per visit
-- (docs/architecture/storefront-html-migration-plan.md). A product page needs
-- what Flutter reads in six or more calls today: the product, its website
-- fields, its brand, its technical sheet, products of its category, and the
-- shell every page shares (settings, menus, pages, categories, shipping). The
-- server makes these two calls at the same time, so a page costs one trip.
--
-- Both functions are SECURITY INVOKER and only compose reads that already
-- exist: `get_public_products` keeps owning publication and stock,
-- `get_public_store_data` which settings are public,
-- `get_public_product_technical_specs` the sheet, and
-- `get_public_online_shipping_tiers` the tiers. The few table reads run as the
-- caller, under the same RLS and column grants the Flutter store reads with,
-- so neither function can return anything the public key cannot read today.
-- `cost` is dropped from every product row anyway.

create or replace function public.get_public_storefront_shell_v1(
  p_tenant_id uuid
)
returns jsonb
language sql
security invoker
set search_path = public, pg_temp
stable
as $$
  select jsonb_build_object(
    'settings',
      coalesce(public.get_public_store_data(p_tenant_id)::jsonb -> 'settings',
               '{}'::jsonb),
    'navigation', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.order_index, item.id)
        from (
          select nav.id, nav.menu_location, nav.label, nav.link_type,
                 nav.link_value, nav.parent_id, nav.order_index,
                 nav.show_on_desktop, nav.show_on_mobile
            from public.website_navigation nav
           where nav.tenant_id = p_tenant_id
             and nav.is_visible
        ) item
    ), '[]'::jsonb),
    'pages', coalesce((
      select jsonb_agg(to_jsonb(page) order by page.slug, page.id)
        from (
          select wp.id, wp.slug, wp.is_home, wp.title
            from public.website_pages wp
           where wp.tenant_id = p_tenant_id
             and wp.is_published
        ) page
    ), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(to_jsonb(category) order by category.id)
        from (
          select pc.id, pc.name, pc.parent_id, pc.full_path, pc.show_on_website
            from public.product_categories pc
           where pc.tenant_id = p_tenant_id
             and pc.is_active
        ) category
    ), '[]'::jsonb),
    'shipping_tiers', coalesce((
      select jsonb_agg(to_jsonb(tier))
        from public.get_public_online_shipping_tiers(p_tenant_id) tier
    ), '[]'::jsonb)
  );
$$;

comment on function public.get_public_storefront_shell_v1(uuid) is
  'What every public page shares: public settings (get_public_store_data), visible menus, published pages, active categories and shipping tiers. Security invoker over existing public reads.';

create or replace function public.get_public_product_page_v1(
  p_tenant_id uuid,
  p_sku text
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
             p_sku := p_sku,
             p_only_in_stock := false,
             p_limit := 1
           ) product
     limit 1
  )
  select jsonb_build_object(
    'product', base.row || coalesce((
      select to_jsonb(website)
        from (
          select p.is_set, p.set_type, p.parent_set_id, p.component_label,
                 p.component_position, p.website_name, p.website_price,
                 p.website_description, p.website_seo_title,
                 p.website_seo_description, p.website_search_terms,
                 p.website_merchant_title, p.website_merchant_description,
                 p.website_merchant_brand, p.website_merchant_gtin,
                 p.website_merchant_mpn, p.website_google_product_category,
                 p.website_image_url, p.website_image_url_optimized,
                 p.website_image_urls, p.price_currency
            from public.products p
           where p.tenant_id = p_tenant_id
             and p.id = base.id
        ) website
    ), '{}'::jsonb),
    -- Raw rows: the client decides with canonicalPublicProductBrandNames,
    -- the same rule the Flutter store applies.
    'brand_rows', coalesce((
      select jsonb_agg(to_jsonb(brand))
        from (
          select b.id, b.name, b.tenant_id, b.is_active
            from public.product_brands b
           where b.id = base.brand_id
             and b.is_active
        ) brand
    ), '[]'::jsonb),
    'specs', coalesce((
      select jsonb_agg(to_jsonb(spec))
        from public.get_public_product_technical_specs(p_tenant_id, base.id) spec
    ), '[]'::jsonb),
    'related', case when base.category_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(to_jsonb(other) - 'cost' - 'total_count')
        from public.get_public_products(
               p_tenant_id := p_tenant_id,
               p_category_ids := array[base.category_id],
               p_only_in_stock := true,
               p_limit := 9
             ) other
       where other.id <> base.id
    ), '[]'::jsonb) end
  )
    from base;
$$;

comment on function public.get_public_product_page_v1(uuid, text) is
  'A public product page in one read: the product as get_public_products publishes it plus its website fields, brand rows, technical sheet and in-stock products of its category. No row when the SKU is not public. Security invoker over existing public reads.';

revoke all on function public.get_public_storefront_shell_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_storefront_shell_v1(uuid)
  to anon, authenticated, service_role;

revoke all on function public.get_public_product_page_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_page_v1(uuid, text)
  to anon, authenticated, service_role;
