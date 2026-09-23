-- Read-back de 20260923180000_products_anon_reads_public_columns_only.
-- SQL plano: cada afirmación divide por cero si el estado esperado falta.
-- Antes de desplegar tiene que fallar contra producción (anónimo lee `cost`).

with publicas(columna) as (
  select unnest(array[
    'id', 'tenant_id', 'name', 'sku', 'barcode', 'price', 'price_currency',
    'inventory_qty', 'stock_quantity', 'image_url', 'image_url_optimized',
    'image_urls', 'description', 'website_description', 'website_name',
    'website_price', 'website_image_url', 'website_image_url_optimized',
    'website_image_urls', 'website_seo_title', 'website_seo_description',
    'website_search_terms', 'website_merchant_title',
    'website_merchant_description', 'website_merchant_brand',
    'website_merchant_gtin', 'website_merchant_mpn',
    'website_google_product_category', 'category', 'category_id',
    'category_name', 'brand_id', 'brand', 'model', 'manufacturer',
    'manufacturer_sku', 'gtin', 'color', 'size', 'material', 'weight',
    'specifications', 'product_type', 'track_stock', 'tax_rate', 'is_set',
    'set_type', 'parent_set_id', 'component_label', 'component_position',
    'is_active', 'is_published', 'show_on_website', 'created_at', 'updated_at'
  ]::text[])
),
columnas as (
  select a.attname::text as columna,
         has_column_privilege('anon', 'public.products', a.attname, 'SELECT') as anon_lee,
         has_column_privilege('anon', 'public.products', a.attname, 'INSERT')
           or has_column_privilege('anon', 'public.products', a.attname, 'UPDATE')
           or has_column_privilege('anon', 'public.products', a.attname, 'REFERENCES') as anon_escribe,
         exists (select 1 from publicas p where p.columna = a.attname) as publica
    from pg_attribute a
   where a.attrelid = 'public.products'::regclass
     and a.attnum > 0
     and not a.attisdropped
)
select count(*) filter (where anon_lee) as anon_lee_columnas,
       count(*) filter (where anon_lee and publica) as anon_lee_publicas,
       string_agg(columna, ',' order by columna) filter (where anon_lee and not publica) as anon_lee_privadas,
       count(*) filter (where anon_escribe) as anon_escribe_columnas,
       has_column_privilege('anon', 'public.products', 'cost', 'SELECT') as anon_lee_costo,
       has_column_privilege('anon', 'public.products', 'supplier_name', 'SELECT') as anon_lee_proveedor,
       has_table_privilege('anon', 'public.products', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') as anon_tabla,
       has_column_privilege('authenticated', 'public.products', 'cost', 'SELECT') as staff_lee_costo
  from columnas;

-- Anónimo lee exactamente las 55 columnas públicas y ninguna otra.
select 1 / (case when (
  select count(*) = 55
     and count(*) filter (where p.columna is null) = 0
    from pg_attribute a
    left join (select unnest(array[
      'id', 'tenant_id', 'name', 'sku', 'barcode', 'price', 'price_currency',
      'inventory_qty', 'stock_quantity', 'image_url', 'image_url_optimized',
      'image_urls', 'description', 'website_description', 'website_name',
      'website_price', 'website_image_url', 'website_image_url_optimized',
      'website_image_urls', 'website_seo_title', 'website_seo_description',
      'website_search_terms', 'website_merchant_title',
      'website_merchant_description', 'website_merchant_brand',
      'website_merchant_gtin', 'website_merchant_mpn',
      'website_google_product_category', 'category', 'category_id',
      'category_name', 'brand_id', 'brand', 'model', 'manufacturer',
      'manufacturer_sku', 'gtin', 'color', 'size', 'material', 'weight',
      'specifications', 'product_type', 'track_stock', 'tax_rate', 'is_set',
      'set_type', 'parent_set_id', 'component_label', 'component_position',
      'is_active', 'is_published', 'show_on_website', 'created_at', 'updated_at'
    ]::text[]) as columna) p on p.columna = a.attname
   where a.attrelid = 'public.products'::regclass
     and a.attnum > 0
     and not a.attisdropped
     and has_column_privilege('anon', 'public.products', a.attname, 'SELECT')
) then 1 else 0 end) as anon_lee_solo_lo_publico;

-- Ni costo ni proveedor, ni ningún permiso de tabla ni de escritura.
select 1 / (case when
  not has_column_privilege('anon', 'public.products', 'cost', 'SELECT')
  and not has_column_privilege('anon', 'public.products', 'supplier_name', 'SELECT')
  and not has_column_privilege('anon', 'public.products', 'supplier_id', 'SELECT')
  and not has_table_privilege('anon', 'public.products', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  and not exists (
    select 1
      from pg_attribute a
     where a.attrelid = 'public.products'::regclass
       and a.attnum > 0
       and not a.attisdropped
       and (has_column_privilege('anon', 'public.products', a.attname, 'INSERT')
         or has_column_privilege('anon', 'public.products', a.attname, 'UPDATE')
         or has_column_privilege('anon', 'public.products', a.attname, 'REFERENCES'))
  )
then 1 else 0 end) as anon_sin_costo_ni_escritura;

-- El staff sigue leyendo el costo y las RPC públicas siguen abiertas a anónimo.
select 1 / (case when
  has_column_privilege('authenticated', 'public.products', 'cost', 'SELECT')
  and has_table_privilege('service_role', 'public.products', 'SELECT,INSERT,UPDATE,DELETE')
  and (
    select count(*) = 5
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('get_public_products', 'get_public_products_faceted_v1',
                         'get_public_products_faceted_v2',
                         'get_public_featured_products', 'search_public_products')
       and p.prosecdef
       and has_function_privilege('anon', p.oid, 'EXECUTE')
  )
then 1 else 0 end) as staff_y_rpc_intactos;
