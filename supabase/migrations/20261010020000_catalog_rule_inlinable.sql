-- La regla única de venta online vuelve a ser incrustable.
--
-- 20261010010000 dejó `catalog_product_web_block_v1` con un `exists` sobre
-- la categoría. Postgres no incrusta (inline) una función SQL cuyo cuerpo
-- tiene subconsultas, así que la llamaba fila por fila: la lectura del
-- catálogo pasó de ~60 ms a ~130 ms (24 productos, medido en producción el
-- 2026-10-10) y el buscador de ~440 ms a ~515 ms. La subconsulta pasa a su
-- propia función; el `case` sólo la evalúa si el sitio exige categoría
-- visible (hoy no). Mismo resultado fila por fila.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.catalog_category_visible_v1(
  p_tenant_id uuid,
  p_category_id uuid
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
      from public.product_categories pc
     where pc.id = p_category_id
       and pc.tenant_id = p_tenant_id
       and pc.is_active = true
       and coalesce(pc.show_on_website, false) = true
  );
$$;

revoke all on function public.catalog_category_visible_v1(uuid, uuid) from public, anon;
grant execute on function public.catalog_category_visible_v1(uuid, uuid) to authenticated;

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
    when coalesce((p_policy ->> 'require_image')::boolean, false)
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

commit;
