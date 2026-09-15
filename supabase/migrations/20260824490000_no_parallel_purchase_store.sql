-- El pedido vive en el módulo de compras real. Se retira el almacén paralelo.
--
-- La primera versión guardaba el pedido en `purchase_orders`, con sus propias
-- funciones, su propia lista y su propio ciclo de vida. **Era un módulo de
-- compras al lado del módulo de compras**: dos lugares donde buscar un
-- documento del mismo proveedor, dos numeraciones y una conversión manual el
-- día que llegara la factura.
--
-- El pedido es el **mismo documento** que después va a llevar la factura del
-- proveedor: nace en `purchase_invoices` con estado `draft`, aparece en
-- «Documentos de compra» junto a todo lo demás, y cuando llega la factura se le
-- pone el folio real y se marca recibida. Sin conversión y sin retipear
-- líneas.
--
-- Un borrador no toca la contabilidad —los asientos los crean los disparadores
-- al pasar a `received`—, verificado contra producción: el borrador que ya
-- existía tiene cero asientos.
--
-- Se borra también el pedido de prueba que quedó de esa versión. `purchase_orders`
-- vuelve a quedar en cero, como estaba.

begin;

delete from public.purchase_order_items item
where item.purchase_order_id in (
  select orders.id from public.purchase_orders orders
  where orders.order_number like 'PED-%'
);
delete from public.purchase_orders orders
where orders.order_number like 'PED-%';

drop function if exists public.save_purchase_order_draft_v1(uuid, jsonb, uuid, text, date);
drop function if exists public.mark_purchase_order_sent_v1(uuid, text);
drop function if exists public.purchase_orders_page_v1(uuid, text[], integer, integer);
drop function if exists public.purchase_order_lines_v1(uuid);
drop function if exists public.purchase_order_guard_probe_v1();

commit;
