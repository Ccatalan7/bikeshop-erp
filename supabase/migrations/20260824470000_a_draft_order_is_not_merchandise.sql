-- Un pedido en borrador no es mercadería que llegó.
--
-- `trg_purchase_item` sumaba al inventario **al insertar la línea**:
--
--     update public.products set stock_quantity = stock_quantity + new.quantity
--     insert into public.stock_movements (... 'inbound' ...)
--
-- Es decir, guardar un borrador de pedido —algo que el proveedor todavía no ha
-- visto— habría dado por recibida la mercadería, inflado el stock de productos
-- que nadie compró y dejado movimientos de bodega fantasma. La única razón por
-- la que no ocurrió es que este tenant no tiene bodega configurada y el
-- disparador moría antes, en `No default warehouse configured`.
--
-- Se descubrió al guardar el primer pedido real desde el asistente de compras.
-- La tabla tenía cero filas, así que no hay stock que reparar: nunca llegó a
-- correr en producción.
--
-- **El stock se mueve cuando la mercadería llega, no cuando se pide.** El
-- disparador se conserva con su intención original, pero condicionado al estado
-- del pedido. En `draft` y en `ordered` no toca nada. Sin bodega configurada
-- tampoco falla: un pedido que no puede guardarse por una bodega que nadie
-- necesita todavía es un bloqueo sin causa.

begin;

create or replace function public.handle_purchase_item()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_company_id uuid;
  v_status public.purchase_status;
  v_warehouse_id uuid;
begin
  select orders.company_id, orders.status
    into v_company_id, v_status
    from public.purchase_orders orders
   where orders.id = new.purchase_order_id;

  -- Pedido pedido, no recibido: no hay nada que mover. Es el caso normal
  -- mientras se arma y mientras el proveedor no despacha.
  if v_status is distinct from 'received' then
    return new;
  end if;

  -- Una línea sin producto no mueve inventario: puede ser un flete, un
  -- servicio o algo que todavía no existe en el catálogo.
  if new.product_id is null then
    return new;
  end if;

  select w.id
    into v_warehouse_id
    from public.warehouses w
   where w.company_id = v_company_id
   order by w.created_at
   limit 1;

  if v_warehouse_id is null then
    raise exception 'No default warehouse configured for company %',
      v_company_id;
  end if;

  update public.products
     set inventory_qty = inventory_qty + new.quantity,
         stock_quantity = stock_quantity + new.quantity
   where id = new.product_id
     and is_service = false;

  insert into public.stock_movements (
    product_id, warehouse_id, movement_type, quantity, reference
  )
  values (
    new.product_id, v_warehouse_id, 'inbound', new.quantity,
    'purchase_order:' || new.purchase_order_id
  );

  return new;
end;
$$;

commit;
