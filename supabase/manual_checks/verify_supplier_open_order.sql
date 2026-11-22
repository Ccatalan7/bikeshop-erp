-- 20261122010000: un solo pedido abierto por proveedor. Falla si el paso de
-- pagar no suma al pedido abierto, si falta la guarda o el disparador de
-- anulación, si el comando de enviar o la lectura del chat no existen o perdieron
-- su permiso, o si la regla de lo vendido sigue contando sólo 2 días desde la
-- venta. SQL plano, sin control de transacción: corre por el envoltorio de
-- lectura.

-- Pagar suma al pedido abierto del proveedor y la nota sale de sus ventas.
select 1 / case
  when position('supplier_open_order_items_apply_internal' in pg_get_functiondef(
         'public.customer_quote_order_prepare_purchases_internal(uuid)'::regprocedure)) > 0
   and position('supplier_open_order_note_internal' in pg_get_functiondef(
         'public.customer_quote_order_prepare_purchases_internal(uuid)'::regprocedure)) > 0
  then 1 else 0 end as paying_joins_the_open_order;

-- La guarda del pedido abierto y la salida de una venta anulada.
select 1 / case
  when exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.purchase_invoices'::regclass
       and t.tgname = 'trg_supplier_open_order_guard'
       and t.tgenabled <> 'D')
   and exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.online_orders'::regclass
       and t.tgname = 'trg_release_supplier_open_order_on_order_cancel'
       and t.tgenabled <> 'D')
  then 1 else 0 end as guard_and_release_triggers;

-- Enviar y leer el chat: el equipo sí, una visita no.
select 1 / case
  when has_function_privilege('authenticated',
         'public.purchase_order_mark_sent_v1(uuid,uuid,jsonb)', 'EXECUTE')
   and has_function_privilege('authenticated',
         'public.purchase_order_supplier_chat_v1(uuid,uuid)', 'EXECUTE')
   and not has_function_privilege('anon',
         'public.purchase_order_mark_sent_v1(uuid,uuid,jsonb)', 'EXECUTE')
   and not has_function_privilege('anon',
         'public.purchase_order_supplier_chat_v1(uuid,uuid)', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'public.supplier_open_order_release_order_internal(uuid)', 'EXECUTE')
  then 1 else 0 end as send_and_chat_permissions;

-- Lo vendido cuenta mientras el pedido no sale y 2 días después de enviado.
select 1 / case
  when position('sent_date' in pg_get_functiondef(
         'public.product_on_order_offer_internal_v1(uuid,uuid[])'::regprocedure)) > 0
  then 1 else 0 end as pending_until_sent;

-- La proyección del pedido web dice con cuántas ventas va y cuándo salió.
select 1 / case
  when position('''orders''' in pg_get_functiondef(
         'public.online_order_on_order_projection_internal(uuid)'::regprocedure)) > 0
   and position('''sent_at''' in pg_get_functiondef(
         'public.online_order_on_order_projection_internal(uuid)'::regprocedure)) > 0
  then 1 else 0 end as projection_counts_orders;

-- La regla vive: corre para Viñabike sin error y no ofrece cantidades negativas.
select 1 / case
  when not exists (
    select 1
      from public.product_on_order_offer_internal_v1(
             '5443b130-cc28-45af-a420-cd500b288890'::uuid, null) offer
     where offer.max_quantity < 1)
  then 1 else 0 end as offer_rule_runs;

-- Ningún borrador de compra de una venta web quedó repetido para un proveedor
-- (hoy no hay ventas a pedido; desde aquí, uno abierto por proveedor).
select 1 / case
  when not exists (
    select pi.supplier_id
      from public.purchase_invoices pi
     where pi.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and pi.status = 'draft'
       and exists (
         select 1
           from public.customer_quote_purchase_orders po
           join public.online_orders o on o.id = po.online_order_id and o.tenant_id = po.tenant_id
          where po.purchase_invoice_id = pi.id
            and po.tenant_id = pi.tenant_id
            and o.status <> 'cancelled')
     group by pi.supplier_id
    having count(*) > 1)
  then 1 else 0 end as one_open_order_per_supplier;
