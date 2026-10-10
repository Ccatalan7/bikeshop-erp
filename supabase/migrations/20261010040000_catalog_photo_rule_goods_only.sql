-- «Exigir foto» vale para productos, no para servicios.
--
-- La regla única de venta (20261010010000) frenaba un servicio sin foto
-- cuando la tienda exige foto: «Mantención Full (bici rígida, frenos
-- hidráulicos)», encendida para la web, no salía en /servicios. Esa página
-- es una lista de precios sin fotos, Merchant no recibe servicios y la hoja
-- de reglas del ERP dice «un producto necesita foto». La marca ya se exigía
-- sólo a productos; la foto queda igual. La función sigue sin subconsultas
-- (el planificador la incrusta, 20261010020000).

create or replace function public.catalog_product_web_block_v1(
  p public.products,
  p_policy jsonb
)
returns text
language sql
stable
as $$
  select case
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce(p.purchase_treatment, 'inventory') = 'workshop_consumable'
      then 'workshop_consumable'
    when not coalesce(p.is_active, false)
      then 'inactive'
    when not (coalesce(p.is_published, false) and coalesce(p.show_on_website, false))
      then 'web_off'
    -- Sin clasificación de IVA el checkout lo rechaza y Merchant no lo
    -- recibe: no se ofrece. Un servicio no pasa por el carrito.
    when coalesce(p.product_type, 'product') <> 'service'
         and (p.tax_rate is null or p.tax_rate not in (0, 0.19, 19))
      then 'missing_tax'
    when coalesce(p.website_price, p.price, 0) <= 0
         and not (
           coalesce(p.product_type, 'product') = 'service'
           and p.website_price_mode = 'quote'
         )
      then 'missing_price'
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce(p.cost, 0) > 0
         and coalesce(p.website_price, p.price)
             < p.cost * public.catalog_tax_factor_v1(p.tax_rate)
         and coalesce(p.web_clearance_until, date '1900-01-01') < current_date
      then 'below_cost'
    -- La foto se exige a lo que se vende como producto: /servicios es una
    -- lista de precios sin fotos (20261010040000).
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce((p_policy ->> 'require_image')::boolean, false)
         and nullif(btrim(coalesce(p.website_image_url, '')), '') is null
         and nullif(btrim(coalesce(p.website_image_url_optimized, '')), '') is null
         and cardinality(coalesce(p.website_image_urls, array[]::text[])) = 0
         and nullif(btrim(coalesce(p.image_url, '')), '') is null
         and nullif(btrim(coalesce(p.image_url_optimized, '')), '') is null
         and cardinality(coalesce(p.image_urls, array[]::text[])) = 0
      then 'missing_image'
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce((p_policy ->> 'require_web_name')::boolean, false)
         and nullif(btrim(coalesce(p.website_name, '')), '') is null
      then 'missing_web_name'
    when coalesce((p_policy ->> 'require_description')::boolean, false)
         and nullif(btrim(coalesce(p.website_description, '')), '') is null
      then 'missing_description'
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce((p_policy ->> 'require_brand')::boolean, false)
         and p.brand_id is null
      then 'missing_brand'
    when coalesce((p_policy ->> 'require_visible_category')::boolean, false)
         and not (
           (p.category_id is null
             and coalesce((p_policy ->> 'include_uncategorized')::boolean, true))
           or public.catalog_category_visible_v1(p.tenant_id, p.category_id)
         )
      then 'category_hidden'
  end;
$$;
