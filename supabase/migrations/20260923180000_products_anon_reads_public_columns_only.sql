-- Anónimo deja de leer el costo y el proveedor de los productos.
--
-- Con la clave pública de la tienda se leían las 101 columnas de `products`:
-- 1.599 filas publicadas de dos empresas, con `cost` y `supplier_name`
-- (diagnóstico web del 2026-09-23, fase 1a). La tienda sólo pide dos listas
-- explícitas —`Product.storefrontPreviewSelect` y la identidad pública que lee
-- `PublicInventoryService`— y filtra por `tenant_id`; en los registros de la
-- API de las últimas 24 h no hay otra lectura anónima. El feed de Merchant y
-- el generador del sitemap usan la clave de servicio, y las RPC públicas son
-- SECURITY DEFINER: ninguno pasa por estos permisos.
--
-- `revoke all` sobre la tabla también retira los permisos por columna que
-- anónimo tenía (INSERT/UPDATE en 97 columnas, que el RLS ya frenaba). Los
-- clientes con sesión (`authenticated`) quedan igual: su puerta se cierra
-- aparte, con un cambio en la tienda, porque el staff usa el mismo rol y
-- necesita ver el costo.
revoke all on table public.products from anon;

grant select (
  id,
  tenant_id,
  name,
  sku,
  barcode,
  price,
  price_currency,
  inventory_qty,
  stock_quantity,
  image_url,
  image_url_optimized,
  image_urls,
  description,
  website_description,
  website_name,
  website_price,
  website_image_url,
  website_image_url_optimized,
  website_image_urls,
  website_seo_title,
  website_seo_description,
  website_search_terms,
  website_merchant_title,
  website_merchant_description,
  website_merchant_brand,
  website_merchant_gtin,
  website_merchant_mpn,
  website_google_product_category,
  category,
  category_id,
  category_name,
  brand_id,
  brand,
  model,
  manufacturer,
  manufacturer_sku,
  gtin,
  color,
  size,
  material,
  weight,
  specifications,
  product_type,
  track_stock,
  tax_rate,
  is_set,
  set_type,
  parent_set_id,
  component_label,
  component_position,
  is_active,
  is_published,
  show_on_website,
  created_at,
  updated_at
) on table public.products to anon;
