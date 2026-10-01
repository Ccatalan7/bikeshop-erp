-- Lectura de código activo: rutas directas de efectos que dispararía el
-- INSERT de filas históricas del restore legado. No ejecuta esas funciones.
-- Una coincidencia textual confirma la llamada directa; no clasifica las
-- funciones anidadas ni autoriza apagar guardias de integridad.
with expected(signature, effect_path, source_fragment) as (
  values
    ('handle_sales_invoice_change()', 'stock de venta',
     'consume_sales_invoice_inventory('),
    ('handle_sales_invoice_change()', 'asiento de venta',
     'create_sales_invoice_journal_entry('),
    ('handle_purchase_invoice_change()', 'stock de compra',
     'consume_purchase_invoice_inventory('),
    ('handle_purchase_invoice_change()', 'asiento de compra',
     'create_purchase_invoice_journal_entry('),
    ('handle_new_online_order()', 'procesar pedido',
     'process_online_order('),
    ('invoke_push_notification_for_message()', 'solicitud de push',
     'net.http_post('),
    ('enqueue_whatsapp_catalog_product_sync()', 'sincronización de catálogo',
     'net.http_post('),
    ('broadcast_financial_projection_change()', 'aviso realtime',
     'realtime.send(')
)
select expected.signature,
       expected.effect_path,
       procedure_row.oid is not null as function_exists,
       coalesce(position(
         lower(expected.source_fragment)
         in lower(pg_get_functiondef(procedure_row.oid))
       ) > 0, false) as direct_path_in_live_definition
  from expected
  left join pg_proc procedure_row
    on procedure_row.oid = to_regprocedure('public.' || expected.signature)
 order by expected.signature, expected.effect_path;
