-- El disparador ya no mueve inventario salvo que el pedido esté recibido.
--
-- Se comprueba en el cuerpo de la función, que es donde vive la regla, y se
-- confirma que no quedó stock que reparar: la tabla de pedidos está en cero,
-- así que la versión anterior nunca llegó a correr en producción.
select
  position('is distinct from ''received''' in prosrc) > 0
    as exige_recibido,
  position('new.product_id is null' in prosrc) > 0
    as ignora_linea_sin_producto,
  (select count(*) from public.purchase_orders) pedidos_existentes,
  (select count(*) from public.stock_movements
    where reference like 'purchase_order:%') movimientos_de_pedido
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'handle_purchase_item';
