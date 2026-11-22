-- Marcas en el menú (2026-11-21, el dueño: «agrégale un buen mega menú de
-- marcas… elegante, que sea bien útil»).
--
-- Un ítem de «Navegación» puede llevar a una marca: `link_type = 'brand'` y
-- `link_value` = el id de la marca (`product_brands.id`). Lleva al catálogo
-- filtrado por esa marca, el mismo filtro que escribe la faceta «Marca», y un
-- menú ancho cuyos ítems son marcas muestra sus logos en una grilla.
--
-- La tienda los lee con el menú: `get_public_storefront_shell_v1` suma
-- `brands`, el id, el nombre y el logo de cada marca activa que nombra un
-- ítem visible de este taller (las suyas y las del catálogo compartido). El
-- logo es el que guarda «Inventario › Marcas». Nada más cambia: la misma
-- función security invoker con los mismos permisos; la visita ya lee
-- `product_brands` (política `public_product_brands_select`, sólo activas) y
-- `website_navigation`. `website_navigation.link_type` no tiene restricción:
-- el tipo nuevo no pide cambiar la tabla.

set local lock_timeout = '5s';

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
                 nav.show_on_desktop, nav.show_on_mobile, nav.css_class,
                 nav.icon
            from public.website_navigation nav
           where nav.tenant_id = p_tenant_id
             and nav.is_visible
        ) item
    ), '[]'::jsonb),
    'pages', coalesce((
      select jsonb_agg(to_jsonb(page) order by page.slug, page.id)
        from (
          select wp.id, wp.slug, wp.is_home, wp.title, wp.template
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
    ), '[]'::jsonb),
    -- The brands the menus name (20261121230000): a value that is not an id
    -- names none, and is never cast.
    'brands', coalesce((
      select jsonb_agg(to_jsonb(brand) order by brand.id)
        from (
          select pb.id, pb.name, pb.logo_url
            from public.product_brands pb
           where pb.is_active
             and (pb.tenant_id = p_tenant_id or pb.tenant_id is null)
             and pb.id::text in (
               select lower(btrim(nav.link_value))
                 from public.website_navigation nav
                where nav.tenant_id = p_tenant_id
                  and nav.is_visible
                  and nav.link_type = 'brand'
             )
        ) brand
    ), '[]'::jsonb)
  );
$$;

comment on function public.get_public_storefront_shell_v1(uuid) is
  'What every public page shares: public settings (get_public_store_data), visible menus (with each item''s CSS class and icon), published pages (with their template), active categories (with description, image and order), shipping tiers, and the brands the menus name with their logos (20261121230000). Security invoker over existing public reads.';

revoke all on function public.get_public_storefront_shell_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_storefront_shell_v1(uuid)
  to anon, authenticated, service_role;
