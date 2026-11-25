-- Lo caro se vende con lo que el distribuidor tiene (2026-11-24).
--
-- La regla de lo que se compra con plazo (20261120210000) le dejaba 5 al
-- proveedor en todo: se vendía si su lectura decía 6 o más. Sirve para cadenas,
-- cascos o pastillas, que MKR tiene por decenas. Las horquillas RockShox no:
-- MKR tiene de 1 a 8 de cada una, y de las 23 publicadas el 2026-11-24 sólo 2
-- llegaban a 6. Sobre $200.000 (el tramo que ya va de a 2 por compra) se le
-- deja 1: se vende si tiene 2 o más. Lo demás no cambia.
--
-- Mismo cuerpo que 20261122010000 salvo `reserve`.

create or replace function public.product_on_order_offer_internal_v1(
  p_tenant_id uuid,
  p_product_ids uuid[] default null
)
returns table (
  product_id uuid,
  supplier_id uuid,
  lead_days_min smallint,
  lead_days_max smallint,
  max_quantity integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with terms as (
    select t.product_id,
           t.supplier_id,
           t.lead_days_min,
           t.lead_days_max,
           coalesce(p.website_price, p.price, 0) as price,
           nullif(btrim(coalesce(p.supplier_code, '')), '') as supplier_code,
           array_remove(array[
             nullif(btrim(coalesce(p.barcode, '')), ''),
             nullif(btrim(coalesce(p.supplier_code, '')), ''),
             nullif(btrim(coalesce(p.sku, '')), '')
           ], null) as codes
      from public.product_on_order_terms t
      join public.products p
        on p.id = t.product_id
       and p.tenant_id = t.tenant_id
     where t.tenant_id = p_tenant_id
       and t.is_active
       and t.supplier_id is not null
       and (p_product_ids is null or t.product_id = any (p_product_ids))
  ), sized as (
    select terms.*,
           feed.id as feed_id,
           feed.last_ok_at,
           item.stock as supplier_stock,
           coalesce(pending.quantity, 0) as pending,
           case
             when terms.price <= 50000 then 5
             when terms.price <= 200000 then 3
             else 2
           end as per_order,
           -- Lo que se le deja al proveedor (20261124230000): 5 en lo de hasta
           -- $200.000, que otros talleres le compran todos los días; 1 en lo
           -- caro (horquillas, ruedas), que el distribuidor tiene de a 1 a 8
           -- y se vende de a una.
           case
             when terms.price <= 200000 then 5
             else 1
           end as reserve
      from terms
      left join lateral (
        select f.id, f.last_ok_at
          from public.supplier_catalog_feeds f
         where f.tenant_id = p_tenant_id
           and f.supplier_id = terms.supplier_id
           and f.enabled
         order by f.last_ok_at desc nulls last
         limit 1
      ) feed on true
      left join lateral (
        -- El producto en la lectura del proveedor: por su código del
        -- proveedor y, si no, por un código de barras (los del local llevan
        -- el código de barras en el SKU o en el código del proveedor).
        select fi.stock
          from public.supplier_catalog_feed_items fi
         where fi.tenant_id = p_tenant_id
           and fi.supplier_id = terms.supplier_id
           and fi.feed_id = feed.id
           and fi.is_listed
           and (
             fi.supplier_sku = terms.supplier_code
             or (fi.barcode = any (terms.codes) and fi.barcode not in ('', '0'))
           )
         order by (fi.supplier_sku = terms.supplier_code) desc nulls last,
                  fi.stock desc
         limit 1
      ) item on feed.id is not null
      left join lateral (
        -- Lo vendido que todavía no llega: la lectura del proveedor recién lo
        -- descuenta cuando se le compra. Mientras el pedido al proveedor no
        -- sale cuenta siempre; enviado, 2 días más; sin pedido todavía (un
        -- pago que no llega), 2 días desde la venta (20261122010000).
        select sum(i.quantity)::integer as quantity
          from public.online_order_items i
          join public.online_orders o
            on o.id = i.order_id
           and o.tenant_id = i.tenant_id
          left join public.customer_quote_purchase_orders po
            on po.online_order_id = o.id
           and po.tenant_id = o.tenant_id
           and po.supplier_id = i.on_order_supplier_id
          left join public.purchase_invoices pi
            on pi.id = po.purchase_invoice_id
           and pi.tenant_id = po.tenant_id
         where i.tenant_id = p_tenant_id
           and i.product_id = terms.product_id
           and i.fulfillment = 'on_order'
           and i.arrived_at is null
           and o.status <> 'cancelled'
           and case
                 when pi.id is null then o.created_at > clock_timestamp() - interval '2 days'
                 when pi.status = 'draft' then true
                 when pi.status = 'cancelled' then false
                 else coalesce(pi.sent_date, pi.updated_at) > clock_timestamp() - interval '2 days'
               end
      ) pending on true
  )
  select sized.product_id,
         sized.supplier_id,
         sized.lead_days_min,
         sized.lead_days_max,
         (case
            when sized.feed_id is null then sized.per_order
            else least(sized.per_order, sized.supplier_stock - sized.reserve - sized.pending)
          end)::integer as max_quantity
    from sized
   where sized.feed_id is null
      or (
        sized.last_ok_at > clock_timestamp() - interval '3 hours'
        and sized.supplier_stock is not null
        and sized.supplier_stock - sized.reserve - sized.pending >= 1
      );
$function$;

revoke all on function public.product_on_order_offer_internal_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;

comment on function public.product_on_order_offer_internal_v1(uuid, uuid[]) is
  'Lo que se vende hoy con plazo (20261120210000): «Se vende a pedido» activo con '
  'proveedor y, con lector de catálogo, su lectura de menos de 3 h. max_quantity: '
  'lo del proveedor menos lo que se le deja (5 hasta $200.000, 1 sobre eso, '
  '20261124230000) y menos lo vendido sin llegar (mientras el pedido no sale y 2 '
  'días después de enviado, 20261122010000), con tope por compra (5/3/2 según '
  'precio). Núcleo privado; sin grant.';
