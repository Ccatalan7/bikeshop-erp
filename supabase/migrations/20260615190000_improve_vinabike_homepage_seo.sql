-- Keep Viñabike homepage metadata focused, factual, and consistent across the
-- public storefront, generated crawler snapshots, and the SEO settings editor.

update public.website_pages
set
  meta_title = 'Tienda y Taller de Bicicletas en Viña del Mar | Viñabike',
  meta_description = 'Compra bicicletas, repuestos y accesorios en Viñabike. Taller especializado, mantenciones y reparaciones en Viña del Mar, con retiro en tienda y despacho.',
  updated_at = now()
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and (is_home = true or slug in ('home', 'inicio'));

insert into public.website_settings (tenant_id, key, value, description)
values
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'seo_meta_title',
    'Tienda y Taller de Bicicletas en Viña del Mar | Viñabike',
    'Título SEO principal de la tienda'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'seo_meta_description',
    'Compra bicicletas, repuestos y accesorios en Viñabike. Taller especializado, mantenciones y reparaciones en Viña del Mar, con retiro en tienda y despacho.',
    'Descripción SEO principal de la tienda'
  )
on conflict (tenant_id, key) do update
set
  value = excluded.value,
  description = excluded.description,
  updated_at = now();
