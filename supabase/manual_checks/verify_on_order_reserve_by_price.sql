-- 20261124230000: lo de más de $200.000 a pedido se vende si el proveedor tiene
-- 2 o más, dejándole 1. Falla si la regla no tiene el nuevo cuerpo, si quedó
-- al alcance de la API o si las horquillas RockShox de MKR que hoy tienen 2 o
-- más en su archivo no están todas a la venta (y ninguna con 1).
-- SQL plano, sin control de transacción: corre por el envoltorio de lectura.
select 1 / case
  when pg_get_functiondef('public.product_on_order_offer_internal_v1(uuid,uuid[])'::regprocedure)
         like '%when terms.price <= 200000 then 5%else 1%end as reserve%'
   and pg_get_functiondef('public.product_on_order_offer_internal_v1(uuid,uuid[])'::regprocedure)
         like '%sized.supplier_stock - sized.reserve - sized.pending >= 1%'
   and not has_function_privilege('anon',
         'public.product_on_order_offer_internal_v1(uuid,uuid[])', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'public.product_on_order_offer_internal_v1(uuid,uuid[])', 'EXECUTE')
  then 1 else 0 end as reserve_by_price_rule;

with horquillas as (
  select p.id, fi.stock
    from public.products p
    join public.product_on_order_terms t
      on t.product_id = p.id and t.tenant_id = p.tenant_id and t.is_active
    join public.supplier_catalog_feeds f
      on f.tenant_id = p.tenant_id and f.supplier_id = t.supplier_id and f.enabled
     and f.last_ok_at > clock_timestamp() - interval '3 hours'
    join public.supplier_catalog_feed_items fi
      on fi.tenant_id = p.tenant_id and fi.feed_id = f.id
     and fi.supplier_sku = p.supplier_code and fi.is_listed
   where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and p.supplier_id = '3f6f71dc-99b8-4f0c-9f44-cd37276fc5ee'
     and p.name like 'Horquilla RockShox %'
), a_la_venta as (
  select o.product_id
    from public.product_on_order_offer_internal_v1(
      '5443b130-cc28-45af-a420-cd500b288890',
      (select array_agg(id) from horquillas)) o
)
select 1 / case
  when (select count(*) from horquillas) = 23
   and (select count(*) from a_la_venta)
       = (select count(*) from horquillas where stock >= 2)
   and not exists (select 1 from a_la_venta v join horquillas h on h.id = v.product_id where h.stock < 2)
  then 1 else 0 end as rockshox_on_sale;
