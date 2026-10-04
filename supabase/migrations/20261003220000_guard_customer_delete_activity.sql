-- Borrar un cliente no se lleva su actividad (2026-10-03).
--
-- Las llaves foráneas de `customers` borran en cascada `bikes`,
-- `mechanic_jobs`, `vehicles`, `customer_addresses` y `loyalty`, y dejan en
-- NULL el cliente de `sales_invoices`, `orders` y `online_orders`
-- (`sales_orders` y `work_orders` no tienen acción: su llave ya impide el
-- borrado). La lista de clientes antigua ofrecía «Eliminar» en cada fila; la
-- nueva (c4ed2fde) sólo lo ofrece en la página de un cliente sin bicis,
-- trabajos ni facturas y lo revisaba con consultas sueltas antes del DELETE.
-- Entre la revisión y el borrado otro usuario podía agregarle una bici, y la
-- cascada se la llevaba (revisión de Codex, 2026-10-03; el dueño: «arregla
-- eso, parece algo grave»). La regla va en la base:
--
-- * Un disparador BEFORE DELETE rechaza borrar un cliente que tiene una
--   bici, un trabajo (también uno marcado con deleted_at: la cascada lo
--   borraría igual), un vehículo, una factura o un pedido.
-- * No hay ventana entre revisar y borrar: Postgres bloquea la fila del
--   cliente antes de disparar un BEFORE DELETE, y la llave foránea de una
--   fila hija nueva pide FOR KEY SHARE sobre esa misma fila. Si la hija ya
--   está confirmada, el disparador la ve (en READ COMMITTED, el de PostgREST
--   y `query.sh`, cada consulta de la función toma una foto nueva); si llega
--   después, espera y su llave falla porque el cliente ya no está.
-- * Se cuenta por customer_id, sin tenant_id, a propósito: la cascada
--   tampoco filtra por empresa, y lo que se protege es lo que ella tocaría.
--   SECURITY DEFINER para que RLS no esconda filas que la cascada sí ve.
-- * Un borrado que llega en cascada desde otra tabla (borrar una empresa)
--   trae pg_trigger_depth() > 1 y pasa: ahí todo se va junto a propósito. La
--   restauración heredada (`restore_backup_legacy_rows_internal`) borra
--   trabajos, bicis, pedidos en línea y facturas antes que los clientes, y
--   `vehicles` y `orders` tienen 0 filas en producción: sigue funcionando.
-- * El error es `customer_has_activity` con SQLSTATE 23503, el mismo de la
--   llave de `sales_orders` y `work_orders`; el detalle dice qué tiene. La
--   app lo muestra como «tiene bicis, trabajos, facturas o pedidos».

create or replace function public.guard_customer_delete_activity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_found text[];
begin
  -- Borrar una empresa borra sus clientes en cascada: eso no se detiene.
  if pg_trigger_depth() > 1 then
    return old;
  end if;

  v_found := array_remove(array[
    case when exists (select 1 from public.bikes where customer_id = old.id)
      then 'bicis' end,
    case when exists (select 1 from public.mechanic_jobs where customer_id = old.id)
      then 'trabajos' end,
    case when exists (select 1 from public.vehicles where customer_id = old.id)
      then 'vehículos' end,
    case when exists (select 1 from public.sales_invoices where customer_id = old.id)
      then 'facturas' end,
    case when exists (select 1 from public.orders where customer_id = old.id)
      then 'pedidos' end,
    case when exists (select 1 from public.online_orders where customer_id = old.id)
      then 'pedidos en línea' end
  ], null);

  if cardinality(v_found) > 0 then
    raise exception 'customer_has_activity'
      using errcode = '23503',
            detail = format('El cliente tiene %s.', array_to_string(v_found, ', ')),
            hint = 'Un cliente con bicis, trabajos, facturas o pedidos no se elimina: '
                   'borrarlo borraría sus bicis y trabajos.';
  end if;

  return old;
end;
$$;

comment on function public.guard_customer_delete_activity() is
  'Rechaza borrar un cliente con bicis, trabajos, vehículos, facturas o pedidos (customer_has_activity, 23503): las llaves de customers borran en cascada sus bicis y trabajos. Deja pasar el borrado en cascada desde otra tabla (pg_trigger_depth() > 1).';

revoke all on function public.guard_customer_delete_activity() from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_customer_delete_activity on public.customers;
create trigger trg_guard_customer_delete_activity
  before delete on public.customers
  for each row execute function public.guard_customer_delete_activity();
