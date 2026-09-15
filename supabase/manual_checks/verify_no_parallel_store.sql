-- No queda almacén paralelo: ni funciones, ni el pedido de prueba.
--
-- El arreglo del disparador `handle_purchase_item` **se conserva**: era un
-- defecto real de la tabla, independiente de dónde guardemos el pedido. Sumaba
-- al inventario al insertar una línea, dando por recibida mercadería que nadie
-- había despachado.
select
  (select count(*) from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname in ('save_purchase_order_draft_v1',
        'mark_purchase_order_sent_v1', 'purchase_orders_page_v1',
        'purchase_order_lines_v1', 'purchase_order_guard_probe_v1'))
    funciones_del_silo,
  (select count(*) from public.purchase_orders) pedidos_paralelos,
  (select count(*) from public.purchase_order_items) lineas_paralelas,
  (select position('is distinct from ''received''' in prosrc) > 0
     from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'handle_purchase_item') disparador_sigue_arreglado,
  (select count(*) from public.purchase_invoices
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and status = 'draft') borradores_reales;
