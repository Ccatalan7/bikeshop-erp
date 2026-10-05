-- The shared shell also carries each category's description, image and
-- order.
--
-- The HTML storefront serves the category pages from phase 1 of
-- docs/architecture/storefront-html-migration-plan.md. Their introduction and
-- their meta description fall back to the category's own description, and
-- the page to its image, exactly as the SEO generator's snapshots did
-- (`buildCanonicalCategorySeoProjections`); `sort_order` orders a category's
-- children. Nothing else changes: same security invoker, same grants, the
-- columns the public key already reads (`product_categories` grants anon
-- SELECT on all three).

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
          select pc.id, pc.name, pc.parent_id, pc.full_path, pc.show_on_website,
                 pc.description, pc.image_url, pc.sort_order
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
  'What every public page shares: public settings (get_public_store_data), visible menus, published pages, active categories (with description, image and order) and shipping tiers. Security invoker over existing public reads.';

revoke all on function public.get_public_storefront_shell_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_storefront_shell_v1(uuid)
  to anon, authenticated, service_role;
