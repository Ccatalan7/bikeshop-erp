-- La hora a la que le sale solo el pedido a un proveedor se ve y se cambia en
-- su ficha (20261122030000 la creó en `suppliers.order_send_time`, 09:30 por
-- defecto). La app no escribe la tabla de proveedores (ningún grant desde el
-- 2026-09-17): lee y cambia por estos dos comandos, como sus hermanos.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Lo que muestra la ficha: la hora (null: lo manda una persona), si el
-- proveedor tiene productos que se venden a pedido, si el envío está
-- encendido en la tienda y, si hay un pedido abierto, cuándo sale.
create or replace function public.supplier_order_send_settings_v1(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', auth.role(), '');
  v_supplier public.suppliers%rowtype;
  v_open record;
begin
  if v_role <> 'service_role'
     and (p_tenant_id is null or not public.is_active_tenant_member(p_tenant_id)) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;
  select * into v_supplier from public.suppliers
   where id = p_supplier_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  select invoice.id, invoice.invoice_number,
         public.supplier_open_order_send_at_internal(invoice.id, invoice.tenant_id) as send_at
    into v_open
    from public.purchase_invoices invoice
   where invoice.tenant_id = p_tenant_id
     and invoice.supplier_id = p_supplier_id
     and invoice.status = 'draft'
     and exists (
       select 1
         from public.customer_quote_purchase_orders po
         join public.online_orders o
           on o.id = po.online_order_id
          and o.tenant_id = po.tenant_id
        where po.purchase_invoice_id = invoice.id
          and po.tenant_id = invoice.tenant_id
          and o.status <> 'cancelled'
     )
   order by invoice.created_at, invoice.id
   limit 1;

  return jsonb_build_object(
    'send_time', to_char(v_supplier.order_send_time, 'HH24:MI'),
    'sells_on_order', exists (
      select 1 from public.product_on_order_terms terms
       where terms.tenant_id = p_tenant_id
         and terms.supplier_id = p_supplier_id),
    'auto_send_enabled', public.supplier_order_auto_send_enabled_internal(p_tenant_id),
    'open_order', case when v_open.id is null then null else jsonb_build_object(
      'id', v_open.id,
      'number', v_open.invoice_number,
      'send_at', v_open.send_at) end
  );
end;
$function$;

revoke all on function public.supplier_order_send_settings_v1(uuid, uuid) from public, anon;
grant execute on function public.supplier_order_send_settings_v1(uuid, uuid) to authenticated, service_role;

-- Cambia la hora: 'HH:MI' entre 07:00 y 20:00, o null para que lo mande una
-- persona desde «Enviar al proveedor». Devuelve lo mismo que la lectura.
create or replace function public.set_supplier_order_send_time_v1(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_send_time text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', auth.role(), '');
  v_text text := nullif(btrim(coalesce(p_send_time, '')), '');
  v_time time;
begin
  if v_role <> 'service_role'
     and (p_tenant_id is null or not public.is_active_tenant_member(p_tenant_id)) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;
  if v_text is not null then
    if v_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception 'La hora va como 09:30.' using errcode = '22023';
    end if;
    v_time := v_text::time;
    if v_time < time '07:00' or v_time > time '20:00' then
      raise exception 'El pedido sale entre las 07:00 y las 20:00: nunca de noche.'
        using errcode = '22023';
    end if;
  end if;

  update public.suppliers
     set order_send_time = v_time,
         updated_at = now()
   where tenant_id = p_tenant_id
     and id = p_supplier_id;
  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  return public.supplier_order_send_settings_v1(p_tenant_id, p_supplier_id);
end;
$function$;

revoke all on function public.set_supplier_order_send_time_v1(uuid, uuid, text) from public, anon;
grant execute on function public.set_supplier_order_send_time_v1(uuid, uuid, text) to authenticated, service_role;

comment on function public.set_supplier_order_send_time_v1(uuid, uuid, text) is
  'A qué hora de un día hábil le sale solo su pedido abierto a un proveedor (HH:MI, 07:00–20:00), o null para mandarlo a mano (20261122040000).';

commit;
