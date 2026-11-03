-- Cotizaciones, etapa 5: de la cotización aceptada al pedido, y del pago al
-- proveedor.
--
-- Plan aprobado por el dueño («implementalo nomás»): «Al aceptar, la oferta
-- se convierte en un pedido web en una sola operación de la base. Desde ahí
-- sigue el mismo camino que cualquier compra del sitio». Y el 2026-11-02:
-- «esta implementación debe ser completa, pero siempre tienes que tener ojo
-- de no ser muy abrumador al cliente y darle opciones».
--
-- * Aceptar (`accept_public_customer_quote_v1`) pide sólo lo que falta para
--   un pedido: retiro o despacho (con su costo de envío de siempre) y Mercado
--   Pago o transferencia. Crea el pedido web con los precios congelados de la
--   oferta; lo que está en el taller se aparta al tiro (también lo que la
--   oferta daba a pedido, si ya llegó) y lo demás queda «a pedido» con su
--   proveedor y su plazo. Lo prometido en stock que se acabó recién no se
--   vende a pedido sin decirlo: se pide otra oferta. `respond_…` ya no acepta.
-- * El pago es el de cualquier pedido (Mercado Pago o confirmar
--   transferencia). Si todo está en stock, la venta sale igual que siempre.
--   Si algo viene a pedido, **la venta espera**: vender al pagar descontaría
--   stock que no existe y, con unidades apartadas para otro cliente, el
--   disparador de reservas tumbaría el pago. El pago queda en el pedido (y en
--   su observación de Mercado Pago, `awaiting_on_order_stock`), lo apartado
--   espera 90 días y se arma un pedido a cada proveedor como **borrador en
--   Compras** (el documento de compra de siempre, 20260824490000), listo para
--   mandarlo.
-- * Llegar es tener stock libre para la línea, entre por donde entre (el
--   pedido recibido, otra factura o un ajuste): cada 10 minutos, y con «Revisar
--   si llegó» en el ERP, se aparta lo que llegó. Con todo apartado se emite la
--   venta: fechada ese día (la venta nace con la entrega) y con el pago en su
--   fecha. Después sigue como cualquier pedido: listo para retiro o despacho.
-- * Los avisos siguen lo que eligió el cliente: el pedido no le manda correos
--   de avance si no eligió correo (cancelación y reembolso sí: son su plata),
--   y a quien eligió WhatsApp le quedan «Por enviar» el pago, el listo para
--   retiro y el despacho. La aceptación ya no manda dos correos: el del pedido
--   es el aviso.
-- * Lo a pedido se cobra entero al aceptar (el valor del plan). Un abono
--   necesitaría un segundo pago que el pedido web no tiene: con un porcentaje
--   distinto de 100 la aceptación se niega en vez de cobrar mal.

begin;
-- ---------------------------------------------------------------------------
-- 1. Cada línea del pedido sabe si viene a pedido y cuándo llegó.
-- ---------------------------------------------------------------------------

alter table public.online_order_items
  add column if not exists fulfillment text not null default 'stock',
  add column if not exists customer_quote_offer_line_id uuid
    references public.customer_quote_offer_lines(id) on delete set null,
  add column if not exists on_order_supplier_id uuid
    references public.suppliers(id) on delete set null,
  add column if not exists lead_days_min smallint,
  add column if not exists lead_days_max smallint,
  add column if not exists arrived_at timestamptz;

alter table public.online_order_items
  drop constraint if exists online_order_items_fulfillment_check,
  drop constraint if exists online_order_items_arrival_shape,
  drop constraint if exists online_order_items_lead_days;
alter table public.online_order_items
  add constraint online_order_items_fulfillment_check
    check (fulfillment in ('stock', 'on_order')),
  add constraint online_order_items_arrival_shape
    check (fulfillment = 'on_order' or arrived_at is null),
  add constraint online_order_items_lead_days check (
    (lead_days_min is null and lead_days_max is null)
    or (lead_days_min between 0 and 120 and lead_days_max between lead_days_min and 180)
  );

create index if not exists online_order_items_waiting_idx
  on public.online_order_items (tenant_id, product_id)
  where fulfillment = 'on_order' and arrived_at is null;

comment on column public.online_order_items.fulfillment is
  'stock: se aparta al crear el pedido. on_order: viene del proveedor después del pago (pedido de una cotización); se aparta cuando llega (arrived_at).';

create unique index if not exists customer_quotes_online_order_key
  on public.customer_quotes (online_order_id) where online_order_id is not null;

-- El pedido al proveedor es el documento de compra en borrador de Compras
-- (20260824490000: «el pedido vive en el módulo de compras real»). Esta tabla
-- sólo dice cuál nació de qué pedido de cliente.
create table if not exists public.customer_quote_purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete cascade,
  online_order_id uuid not null references public.online_orders(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  purchase_invoice_id uuid references public.purchase_invoices(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  constraint customer_quote_purchase_orders_once unique (online_order_id, supplier_id)
);

comment on table public.customer_quote_purchase_orders is
  'El pedido a cada proveedor que nació de un pedido web de cotización: el documento de compra en borrador (PED-…) que el equipo manda y que después recibe la factura.';

alter table public.customer_quote_purchase_orders enable row level security;
revoke all on public.customer_quote_purchase_orders from public, anon, authenticated;
grant select on public.customer_quote_purchase_orders to authenticated;
drop policy if exists customer_quote_purchase_orders_tenant_read on public.customer_quote_purchase_orders;
create policy customer_quote_purchase_orders_tenant_read on public.customer_quote_purchase_orders
  for select to authenticated using (tenant_id = (select public.user_tenant_id()));

alter table public.customer_quote_messages
  drop constraint if exists customer_quote_messages_kind;
alter table public.customer_quote_messages
  add constraint customer_quote_messages_kind check (kind in (
    'received', 'offer', 'reminder', 'accepted',
    'order_paid', 'order_ready', 'order_shipped'
  ));

alter table public.customer_quote_events
  drop constraint if exists customer_quote_events_type;
alter table public.customer_quote_events
  add constraint customer_quote_events_type check (
    event_type in (
      'requested', 'offer_prepared', 'offer_revised', 'line_confirmed', 'line_added',
      'supplier_task_opened', 'supplier_task_done', 'offer_sent', 'viewed',
      'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled',
      'reminder_sent', 'message_queued', 'note', 'notify_changed', 'contact_updated',
      'order_waiting', 'order_line_arrived', 'order_sale_issued', 'order_attention',
      'order_paid', 'order_ready', 'order_shipped', 'order_delivered', 'order_cancelled'
    )
  );

-- ---------------------------------------------------------------------------
-- 2. Piezas internas del pedido a pedido.
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_order_waiting_internal(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.online_order_items item
     where item.order_id = p_order_id
       and item.fulfillment = 'on_order'
       and item.arrived_at is null
  );
$$;

revoke all on function public.customer_quote_order_waiting_internal(uuid) from public, anon, authenticated;

-- Lo apartado de un pedido que espera productos a pedido no vence a los
-- minutos del pago: espera hasta 90 días o hasta que se emita la venta.
create or replace function public.customer_quote_order_hold_internal(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant uuid;
  v_hold timestamptz := clock_timestamp() + interval '90 days';
  v_reservation public.online_order_inventory_reservations%rowtype;
  v_count integer := 0;
begin
  select tenant_id into v_tenant from public.online_orders where id = p_order_id;
  if v_tenant is null then
    return 0;
  end if;
  for v_reservation in
    update public.online_order_inventory_reservations reservation
       set expires_at = v_hold,
           version = reservation.version + 1,
           updated_at = clock_timestamp()
     where reservation.tenant_id = v_tenant
       and reservation.order_id = p_order_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
       and reservation.expires_at < v_hold - interval '1 day'
     returning reservation.*
  loop
    perform public.append_online_inventory_reservation_event(
      v_reservation, 're_reserved', 'active', 'active', 'customer_quote_hold',
      'reservation-hold:' || v_reservation.id::text || ':' || v_reservation.version::text,
      jsonb_build_object('expires_at', v_reservation.expires_at, 'reason', 'customer_quote_on_order')
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.customer_quote_order_hold_internal(uuid) from public, anon, authenticated;

-- Una línea a pedido «llega» cuando hay stock libre para apartarla: no
-- importa si entró por el documento de compra, por otra factura o por un
-- ajuste. Si no alcanza, no pasa nada y se vuelve a mirar más tarde.
create or replace function public.customer_quote_order_fill_line_internal(p_item_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item public.online_order_items%rowtype;
  v_physical integer;
begin
  select * into v_item from public.online_order_items where id = p_item_id for update;
  if not found or v_item.fulfillment <> 'on_order' or v_item.arrived_at is not null then
    return false;
  end if;
  select coalesce(p.stock_quantity, p.inventory_qty, 0)::integer into v_physical
    from public.products p
   where p.id = v_item.product_id and p.tenant_id = v_item.tenant_id;
  if coalesce(v_physical, 0) < v_item.quantity then
    return false;
  end if;
  begin
    update public.online_order_items set arrived_at = clock_timestamp() where id = p_item_id;
    perform public.reserve_online_order_item_inventory(p_item_id, 'customer_quote_arrival');
    perform public.customer_quote_order_hold_internal(v_item.order_id);
    return true;
  exception when check_violation then
    return false;
  end;
end;
$$;

revoke all on function public.customer_quote_order_fill_line_internal(uuid) from public, anon, authenticated;

-- Un pedido a cada proveedor con lo que falta, como borrador en Compras: el
-- mismo documento que arma el asistente de compras y que después lleva la
-- factura. Un borrador no toca stock ni contabilidad.
create or replace function public.customer_quote_order_prepare_purchases_internal(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_group record;
  v_supplier public.suppliers%rowtype;
  v_net numeric;
  v_iva numeric;
  v_number text;
  v_invoice_id uuid;
  v_count integer := 0;
begin
  select * into v_order from public.online_orders where id = p_order_id;
  if not found then
    return 0;
  end if;
  select * into v_quote from public.customer_quotes
   where online_order_id = p_order_id and tenant_id = v_order.tenant_id;
  if not found then
    return 0;
  end if;

  for v_group in
    select item.on_order_supplier_id as supplier_id,
           jsonb_agg(jsonb_build_object(
             'product_id', item.product_id,
             'product_name', item.product_name,
             'product_sku', item.product_sku,
             'quantity', item.quantity,
             'unit_cost', coalesce(line.unit_cost_net, product.cost, 0),
             'iva_rate', 0.19,
             'discount', 0,
             'description', null,
             'purchase_treatment', 'inventory',
             'created_at', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
           ) order by item.product_name) as items,
           sum(item.quantity * coalesce(line.unit_cost_net, product.cost, 0)) as net
      from public.online_order_items item
      left join public.customer_quote_offer_lines line on line.id = item.customer_quote_offer_line_id
      left join public.products product on product.id = item.product_id and product.tenant_id = item.tenant_id
     where item.order_id = p_order_id
       and item.tenant_id = v_order.tenant_id
       and item.fulfillment = 'on_order'
       and item.arrived_at is null
       and item.on_order_supplier_id is not null
       and not exists (
         select 1 from public.customer_quote_purchase_orders po
          where po.online_order_id = p_order_id and po.supplier_id = item.on_order_supplier_id
       )
     group by item.on_order_supplier_id
  loop
    select * into v_supplier from public.suppliers
     where id = v_group.supplier_id and tenant_id = v_order.tenant_id;
    if not found then
      continue;
    end if;
    v_net := public.clp_round(v_group.net);
    v_iva := public.clp_round(v_net * 0.19);
    -- El número provisorio del asistente de compras: cuando llegue la
    -- factura, el campo pasa a llevar el folio del proveedor.
    loop
      v_number := 'PED-' || to_char(clock_timestamp(), 'YYYYMM') || '-'
        || lpad((floor(random() * 100000))::integer::text, 5, '0');
      exit when not exists (
        select 1 from public.purchase_invoices pi
         where pi.tenant_id = v_order.tenant_id
           and pi.supplier_id = v_supplier.id
           and pi.invoice_number = v_number
      );
    end loop;
    insert into public.purchase_invoices (
      tenant_id, invoice_number, supplier_id, supplier_name, supplier_rut, date,
      status, subtotal, iva_amount, total, net_amount, tax_treatment,
      source_document_kind, notes, items
    ) values (
      v_order.tenant_id, v_number, v_supplier.id, v_supplier.name, v_supplier.rut, clock_timestamp(),
      'draft', v_net, v_iva, v_net + v_iva, v_net, 'tax_included',
      'tax_invoice',
      'Para el pedido ' || v_order.order_number || ' (cotización ' || v_quote.quote_number || ').',
      v_group.items
    ) returning id into v_invoice_id;
    insert into public.customer_quote_purchase_orders (
      tenant_id, quote_id, online_order_id, supplier_id, purchase_invoice_id
    ) values (
      v_order.tenant_id, v_quote.id, p_order_id, v_supplier.id, v_invoice_id
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.customer_quote_order_prepare_purchases_internal(uuid) from public, anon, authenticated;

-- Un pedido de cotización que espera productos a pedido quedó pagado: lo que
-- estaba en stock sigue apartado (si otro se lo llevó mientras pagaba, pasa a
-- pedirse), lo que ya llegó se aparta, todo espera y sale el pedido a cada
-- proveedor. Se puede llamar más de una vez.
create or replace function public.customer_quote_order_paid_internal(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_item public.online_order_items%rowtype;
  v_moved integer := 0;
  v_filled integer := 0;
  v_purchases integer := 0;
  v_without_supplier integer;
begin
  select * into v_order from public.online_orders where id = p_order_id for update;
  if not found or v_order.payment_status <> 'paid' or v_order.status = 'cancelled' then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where online_order_id = p_order_id and tenant_id = v_order.tenant_id;
  if not found then
    return null;
  end if;

  for v_item in
    select * from public.online_order_items
     where order_id = p_order_id and tenant_id = v_order.tenant_id and fulfillment = 'stock'
     order by id
  loop
    begin
      perform public.reserve_online_order_item_inventory(v_item.id, 'customer_quote_paid');
    exception when check_violation then
      update public.online_order_items
         set fulfillment = 'on_order',
             on_order_supplier_id = (
               select p.supplier_id from public.products p
                where p.id = v_item.product_id and p.tenant_id = v_item.tenant_id
             )
       where id = v_item.id;
      v_moved := v_moved + 1;
    end;
  end loop;

  for v_item in
    select * from public.online_order_items
     where order_id = p_order_id and tenant_id = v_order.tenant_id
       and fulfillment = 'on_order' and arrived_at is null
     order by id
  loop
    if public.customer_quote_order_fill_line_internal(v_item.id) then
      v_filled := v_filled + 1;
    end if;
  end loop;

  perform public.customer_quote_order_hold_internal(p_order_id);

  if v_order.status = 'pending' then
    update public.online_orders set status = 'confirmed'
     where id = p_order_id and tenant_id = v_order.tenant_id;
  end if;

  if not public.customer_quote_order_waiting_internal(p_order_id) then
    return jsonb_build_object('waiting', false, 'filled', v_filled, 'moved', v_moved);
  end if;

  -- El pedido al proveedor no puede tumbar el pago: si no sale, el equipo lo
  -- arma en Compras.
  begin
    v_purchases := public.customer_quote_order_prepare_purchases_internal(p_order_id);
  exception when others then
    v_purchases := 0;
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_order_attention', 'Arma en Compras el pedido al proveedor',
      'online_order', p_order_id, 'warning'
    );
  end;

  select count(*) into v_without_supplier
    from public.online_order_items
   where order_id = p_order_id and fulfillment = 'on_order' and arrived_at is null
     and on_order_supplier_id is null;

  if not exists (
    select 1 from public.customer_quote_events e
     where e.quote_id = v_quote.id and e.operation_key = 'order-waiting:' || p_order_id::text
  ) then
    perform public.customer_quote_log_internal(
      v_quote.id, 'order_waiting', 'system', null, 'system', v_quote.current_offer_id,
      'order-waiting:' || p_order_id::text,
      jsonb_build_object(
        'order_id', p_order_id, 'order_number', v_order.order_number,
        'purchases', v_purchases, 'moved_to_order', v_moved, 'filled', v_filled,
        'without_supplier', v_without_supplier
      )
    );
  end if;
  perform public.customer_quote_notify_internal(
    v_quote.id, 'customer_quote_order_to_purchase', 'Pagado: pedir lo que viene a pedido',
    'online_order', p_order_id, 'warning'
  );
  return jsonb_build_object(
    'waiting', true, 'filled', v_filled, 'moved', v_moved,
    'purchases', v_purchases, 'without_supplier', v_without_supplier
  );
end;
$$;

revoke all on function public.customer_quote_order_paid_internal(uuid) from public, anon, authenticated;

-- La transferencia de un pedido que espera productos a pedido: queda en el
-- pedido (referencia, fecha) y la venta la toma cuando llega todo. Mismas
-- exigencias que la confirmación normal.
create or replace function public.customer_quote_order_record_transfer_internal(
  p_order_id uuid,
  p_payment_reference text,
  p_payment_date timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reference text := nullif(btrim(coalesce(p_payment_reference, '')), '');
begin
  if v_reference is null then
    raise exception 'A bank/payment reference is required for manual confirmation'
      using errcode = 'check_violation';
  end if;
  if p_payment_date is null then
    raise exception 'Payment date is required' using errcode = 'check_violation';
  end if;
  if p_payment_date > clock_timestamp() + interval '5 minutes' then
    raise exception 'Payment date cannot be in the future' using errcode = 'check_violation';
  end if;
  -- El disparador del pago llama al proceso del pedido, que ve que espera y
  -- deja todo apartado y pedido.
  update public.online_orders
     set payment_status = 'paid',
         paid_at = p_payment_date,
         payment_reference = v_reference
   where id = p_order_id and payment_status <> 'paid';
  return null;
end;
$$;

revoke all on function public.customer_quote_order_record_transfer_internal(uuid, text, timestamptz) from public, anon, authenticated;

-- Mira si llegó lo que falta; con todo apartado emite la venta: con Mercado
-- Pago vuelve a procesar el pago que quedó esperando, con transferencia el
-- proceso normal del pedido.
create or replace function public.customer_quote_order_check_arrivals_internal(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_item public.online_order_items%rowtype;
  v_filled integer := 0;
  v_event_id bigint;
  v_result jsonb;
  v_invoice uuid;
  v_error text;
begin
  select * into v_order from public.online_orders where id = p_order_id for update;
  if not found then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where online_order_id = p_order_id and tenant_id = v_order.tenant_id;
  if not found then
    return null;
  end if;
  if v_order.status = 'cancelled' or v_order.payment_status <> 'paid'
     or v_order.sales_invoice_id is not null then
    return jsonb_build_object(
      'order_id', p_order_id,
      'waiting', public.customer_quote_order_waiting_internal(p_order_id),
      'invoice_id', v_order.sales_invoice_id
    );
  end if;

  for v_item in
    select * from public.online_order_items
     where order_id = p_order_id and tenant_id = v_order.tenant_id
       and fulfillment = 'on_order' and arrived_at is null
     order by id
  loop
    if public.customer_quote_order_fill_line_internal(v_item.id) then
      v_filled := v_filled + 1;
      perform public.customer_quote_log_internal(
        v_quote.id, 'order_line_arrived', 'system', null, 'system', v_quote.current_offer_id,
        'order-line-arrived:' || v_item.id::text,
        jsonb_build_object('order_id', p_order_id, 'product', v_item.product_name, 'quantity', v_item.quantity)
      );
    end if;
  end loop;

  if public.customer_quote_order_waiting_internal(p_order_id) then
    return jsonb_build_object('order_id', p_order_id, 'waiting', true, 'arrived', v_filled);
  end if;

  begin
    if v_order.payment_method = 'mercadopago' then
      select processing.payment_event_id into v_event_id
        from public.sales_channel_payment_processing processing
       where processing.order_id = p_order_id
         and processing.tenant_id = v_order.tenant_id
         and processing.processing_state = 'action_required'
         and processing.last_error_code = 'awaiting_on_order_stock'
       order by processing.updated_at desc
       limit 1;
    end if;
    if v_event_id is not null then
      v_result := public.process_mercadopago_payment_observation(v_event_id);
      v_invoice := nullif(v_result ->> 'invoice_id', '')::uuid;
      if v_invoice is null then
        v_error := coalesce(v_result ->> 'error_message', 'La venta no se pudo emitir.');
      end if;
    else
      v_invoice := public.process_online_order(p_order_id);
    end if;
  exception when others then
    v_invoice := null;
    v_error := left(sqlerrm, 300);
  end;

  if v_invoice is null then
    perform public.customer_quote_log_internal(
      v_quote.id, 'order_attention', 'system', null, 'system', v_quote.current_offer_id, null,
      jsonb_build_object('order_id', p_order_id, 'error', coalesce(v_error, 'La venta no se emitió.'))
    );
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_order_attention', 'Llegó todo, pero la venta no se emitió',
      'online_order', p_order_id, 'warning'
    );
    return jsonb_build_object('order_id', p_order_id, 'waiting', false, 'arrived', v_filled, 'error', v_error);
  end if;

  perform public.customer_quote_log_internal(
    v_quote.id, 'order_sale_issued', 'system', null, 'system', v_quote.current_offer_id,
    'order-sale:' || p_order_id::text,
    jsonb_build_object(
      'order_id', p_order_id, 'invoice_id', v_invoice,
      'invoice_number', (select invoice_number from public.sales_invoices where id = v_invoice)
    )
  );
  update public.erp_notifications n
     set read_at = coalesce(n.read_at, clock_timestamp())
   where n.tenant_id = v_order.tenant_id
     and n.type in ('customer_quote_order_to_purchase', 'customer_quote_order_attention')
     and n.entity_type = 'online_order'
     and n.entity_id = p_order_id;
  perform public.customer_quote_notify_internal(
    v_quote.id, 'customer_quote_order_ready', 'Llegó todo: preparar el pedido',
    'online_order', p_order_id, 'success'
  );
  return jsonb_build_object('order_id', p_order_id, 'waiting', false, 'arrived', v_filled, 'invoice_id', v_invoice);
end;
$$;

revoke all on function public.customer_quote_order_check_arrivals_internal(uuid) from public, anon, authenticated;

-- El botón «Revisar si llegó» del ERP.
create or replace function public.customer_quote_order_check_arrivals_v1(p_tenant_id uuid, p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order_id uuid;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  select q.online_order_id into v_order_id
    from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id;
  if v_order_id is null then
    raise exception 'Quote has no order' using errcode = 'P0002';
  end if;
  return public.customer_quote_order_check_arrivals_internal(v_order_id);
end;
$$;

revoke all on function public.customer_quote_order_check_arrivals_v1(uuid, uuid) from public, anon;
grant execute on function public.customer_quote_order_check_arrivals_v1(uuid, uuid) to authenticated;

-- Cada 10 minutos: los pedidos pagados que esperan algo que ya tiene stock.
create or replace function public.customer_quote_orders_check_arrivals_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order_id uuid;
  v_count integer := 0;
begin
  for v_order_id in
    select distinct o.id
      from public.online_orders o
      join public.customer_quotes q on q.online_order_id = o.id and q.tenant_id = o.tenant_id
      join public.online_order_items item on item.order_id = o.id and item.tenant_id = o.tenant_id
      join public.products p on p.id = item.product_id and p.tenant_id = item.tenant_id
     where o.payment_status = 'paid'
       and o.status <> 'cancelled'
       and o.sales_invoice_id is null
       and item.fulfillment = 'on_order'
       and item.arrived_at is null
       and coalesce(p.stock_quantity, p.inventory_qty, 0) >= item.quantity
     limit 50
  loop
    begin
      perform public.customer_quote_order_check_arrivals_internal(v_order_id);
      v_count := v_count + 1;
    exception when others then
      raise warning 'Quote order arrival check failed for %: %', v_order_id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.customer_quote_orders_check_arrivals_v1() from public, anon, authenticated;

-- Lo que el cliente necesita para seguir con su pedido: el acceso a su
-- página (con él paga) y sus números. Nunca datos de otro.
create or replace function public.customer_quote_order_receipt_internal(
  p_order_id uuid,
  p_access jsonb,
  p_replay boolean
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'order_id', o.id,
    'order_number', o.order_number,
    'access_token', p_access ->> 'token',
    'expires_at', p_access ->> 'expires_at',
    'total', o.total,
    'payment_method', o.payment_method,
    'payment_status', o.payment_status,
    'delivery_type', o.delivery_type,
    'waiting', public.customer_quote_order_waiting_internal(o.id),
    'replay', p_replay
  )
    from public.online_orders o
   where o.id = p_order_id;
$$;

revoke all on function public.customer_quote_order_receipt_internal(uuid, jsonb, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Aceptar: la oferta se convierte en el pedido web, en una sola operación.
-- ---------------------------------------------------------------------------

create or replace function public.accept_public_customer_quote_v1(p_token text, p_request jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_offer public.customer_quote_offers%rowtype;
  v_event public.customer_quote_events%rowtype;
  v_key text := lower(btrim(coalesce(p_request ->> 'operation_key', '')));
  v_delivery text := lower(btrim(coalesce(p_request ->> 'delivery_type', '')));
  v_method text := lower(btrim(coalesce(p_request ->> 'payment_method', '')));
  v_line1 text := nullif(left(btrim(coalesce(p_request ->> 'shipping_address_line1', '')), 200), '');
  v_line2 text := nullif(left(btrim(coalesce(p_request ->> 'shipping_address_line2', '')), 200), '');
  v_city text := nullif(left(btrim(coalesce(p_request ->> 'shipping_city', '')), 120), '');
  v_region text := nullif(left(btrim(coalesce(p_request ->> 'shipping_state', '')), 120), '');
  v_postal text := nullif(left(btrim(coalesce(p_request ->> 'shipping_postal_code', '')), 20), '');
  v_notes text := nullif(left(btrim(coalesce(p_request ->> 'customer_notes', '')), 1000), '');
  v_expected_shipping numeric;
  v_capabilities jsonb;
  v_capability jsonb;
  v_settings public.customer_quote_settings%rowtype;
  v_line record;
  v_product public.products%rowtype;
  v_order_id uuid;
  v_tax_rate numeric;
  v_on_order integer := 0;
  v_item_snapshot jsonb;
  v_shipping jsonb;
  v_shipping_gross numeric(12,2);
  v_created jsonb;
  v_access_token jsonb;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote acceptance' using errcode = '22023';
  end if;
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random operation key is required' using errcode = '22023';
  end if;

  v_access := public.customer_quote_token_internal(p_token, 'respond_quote');
  if v_access.id is null then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;
  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id
   for update;

  -- La misma aceptación repetida (una respuesta perdida) devuelve el mismo
  -- pedido con un acceso nuevo.
  select * into v_event from public.customer_quote_events e
   where e.quote_id = v_quote.id and e.operation_key = v_key;
  if found then
    if v_event.event_type <> 'accepted' or v_quote.online_order_id is null then
      raise exception 'Operation key already used' using errcode = '23505';
    end if;
    v_access_token := public.issue_online_order_access_token(
      v_quote.online_order_id, array['view_order']::text[], clock_timestamp() + interval '30 days'
    );
    return public.customer_quote_order_receipt_internal(v_quote.online_order_id, v_access_token, true);
  end if;

  if v_quote.status <> 'offered' then
    raise exception 'quote_not_open' using errcode = '55000', detail = v_quote.status;
  end if;
  select * into v_offer from public.customer_quote_offers where id = v_quote.current_offer_id for update;
  if (p_request ->> 'offer_id') is not null
     and (p_request ->> 'offer_id')::uuid is distinct from v_offer.id then
    raise exception 'quote_offer_outdated' using errcode = '40001';
  end if;
  if v_offer.valid_until <= clock_timestamp() then
    raise exception 'quote_offer_expired' using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.customer_quote_offer_lines l
     where l.offer_id = v_offer.id and l.quantity_offered > 0
       and l.availability in ('in_stock', 'on_order')
  ) then
    raise exception 'quote_offer_empty' using errcode = '55000';
  end if;
  if v_quote.customer_email is null then
    raise exception 'quote_contact_invalid' using errcode = '22023', detail = 'customer_email';
  end if;

  if v_delivery not in ('pickup', 'shipping') then
    raise exception 'quote_delivery_invalid' using errcode = '22023';
  end if;
  if v_delivery = 'shipping' and (v_line1 is null or v_city is null or v_region is null) then
    raise exception 'quote_address_required' using errcode = '22023';
  end if;
  if v_method = 'mercado_pago' then
    v_method := 'mercadopago';
  elsif v_method = 'bank_transfer' then
    v_method := 'transfer';
  end if;
  if v_method not in ('mercadopago', 'transfer') then
    raise exception 'quote_payment_invalid' using errcode = '22023';
  end if;
  v_capabilities := public.resolve_public_checkout_capabilities(v_quote.tenant_id);
  select method.value into v_capability
    from jsonb_array_elements(v_capabilities -> 'methods') method(value)
   where method.value ->> 'code' = v_method;
  if v_capability is null or coalesce((v_capability ->> 'available')::boolean, false) is not true then
    raise exception 'quote_payment_unavailable' using errcode = 'P0001';
  end if;
  if p_request ? 'shipping_quote_cost' then
    begin
      v_expected_shipping := (p_request ->> 'shipping_quote_cost')::numeric;
    exception when others then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end;
    if v_expected_shipping is null or v_expected_shipping < 0
       or v_expected_shipping <> public.clp_round(v_expected_shipping) then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end if;
  end if;

  -- Hoy lo a pedido se paga entero al aceptar (plan aprobado, «100 % al
  -- aceptar»). Un abono necesitaría un segundo pago que el pedido web no tiene.
  v_settings := public.customer_quote_settings_internal(v_quote.tenant_id);
  if v_settings.on_order_prepay_percent <> 100 and exists (
    select 1 from public.customer_quote_offer_lines l
     where l.offer_id = v_offer.id and l.quantity_offered > 0 and l.availability = 'on_order'
  ) then
    raise exception 'quote_deposit_unsupported' using errcode = '0A000';
  end if;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', 'true', true);

  insert into public.online_orders (
    tenant_id, order_number, customer_id, customer_email, customer_name, customer_phone,
    customer_address, delivery_type, shipping_address_line1, shipping_address_line2,
    shipping_city, shipping_state, shipping_postal_code, shipping_country,
    subtotal, tax_amount, shipping_cost, shipping_net_amount, shipping_tax_amount,
    shipping_tax_rate, shipping_rate_snapshot, discount_amount, total,
    status, payment_status, payment_method, customer_notes, checkout_idempotency_key
  ) values (
    v_quote.tenant_id,
    public.generate_online_order_number(v_quote.tenant_id, clock_timestamp()),
    v_quote.customer_id, v_quote.customer_email, v_quote.customer_name, v_quote.customer_phone,
    case when v_delivery = 'shipping' then concat_ws(', ', v_line1, v_line2, v_city) end,
    v_delivery,
    case when v_delivery = 'shipping' then v_line1 end,
    case when v_delivery = 'shipping' then v_line2 end,
    case when v_delivery = 'shipping' then v_city end,
    case when v_delivery = 'shipping' then v_region end,
    case when v_delivery = 'shipping' then v_postal end,
    case when v_delivery = 'pickup' then null else 'Chile' end,
    0, 0, 0, 0, 0, 0, '{}'::jsonb, 0, 0,
    'pending', 'pending', v_method, v_notes,
    'customer-quote:' || v_offer.id::text
  ) returning id into v_order_id;

  -- La cotización apunta a su pedido antes del primer evento del pedido: así
  -- el correo «recibimos tu pedido» ya sabe si el cliente eligió correo.
  update public.customer_quotes set online_order_id = v_order_id where id = v_quote.id;

  for v_line in
    select l.*
      from public.customer_quote_offer_lines l
     where l.offer_id = v_offer.id
       and l.quantity_offered > 0
       and l.availability in ('in_stock', 'on_order')
     order by l.line_no
  loop
    select * into v_product from public.products p
     where p.id = v_line.product_id and p.tenant_id = v_quote.tenant_id
     for update;
    if not found then
      raise exception 'quote_product_missing' using errcode = '55000', detail = v_line.product_name;
    end if;
    v_tax_rate := case
      when coalesce(v_line.tax_rate, v_product.tax_rate) in (0.19, 19) then 19
      when coalesce(v_line.tax_rate, v_product.tax_rate) = 0 then 0
    end;
    if v_tax_rate is null then
      raise exception 'Product % has missing or unsupported tax classification', v_line.product_name
        using errcode = '23514';
    end if;
    if v_line.unit_price is null or v_line.unit_price <= 0
       or v_line.unit_price <> public.clp_round(v_line.unit_price) then
      raise exception 'Offer line % requires a positive whole-CLP price', v_line.product_name
        using errcode = '23514';
    end if;

    -- Primero del stock: lo que está en el taller se aparta ya, aunque la
    -- oferta lo diera a pedido (llega antes). Lo prometido «en stock» que se
    -- acabó recién no se vende a pedido sin decirlo: se pide otra oferta.
    begin
      insert into public.online_order_items (
        tenant_id, order_id, product_id, product_name, product_sku, quantity,
        unit_price, subtotal, unit_cost, tax_rate, is_service, purchase_treatment,
        product_type, fulfillment, customer_quote_offer_line_id
      ) values (
        v_quote.tenant_id, v_order_id, v_product.id, v_line.product_name, v_line.product_sku,
        v_line.quantity_offered, v_line.unit_price,
        public.clp_round(v_line.unit_price * v_line.quantity_offered),
        v_product.cost, v_tax_rate,
        (coalesce(v_product.is_service, false) or v_product.product_type = 'service'),
        coalesce(v_product.purchase_treatment, 'inventory'),
        coalesce(v_product.product_type, 'product'),
        'stock', v_line.id
      );
    exception when check_violation then
      if v_line.availability = 'in_stock' then
        raise exception 'quote_stock_changed' using errcode = '40001', detail = v_line.product_name;
      end if;
      insert into public.online_order_items (
        tenant_id, order_id, product_id, product_name, product_sku, quantity,
        unit_price, subtotal, unit_cost, tax_rate, is_service, purchase_treatment,
        product_type, fulfillment, customer_quote_offer_line_id, on_order_supplier_id,
        lead_days_min, lead_days_max
      ) values (
        v_quote.tenant_id, v_order_id, v_product.id, v_line.product_name, v_line.product_sku,
        v_line.quantity_offered, v_line.unit_price,
        public.clp_round(v_line.unit_price * v_line.quantity_offered),
        coalesce(v_line.unit_cost_net, v_product.cost), v_tax_rate,
        false,
        coalesce(v_product.purchase_treatment, 'inventory'),
        coalesce(v_product.product_type, 'product'),
        'on_order', v_line.id, coalesce(v_line.supplier_id, v_product.supplier_id),
        v_line.lead_days_min, v_line.lead_days_max
      );
      v_on_order := v_on_order + 1;
    end;
  end loop;

  v_item_snapshot := public.calculate_online_order_tax_snapshot(v_order_id, v_quote.tenant_id);
  v_shipping := public.quote_online_shipping_internal(
    v_quote.tenant_id, v_delivery, (v_item_snapshot ->> 'gross_amount')::numeric, 'CL', v_region
  );
  v_shipping_gross := (v_shipping ->> 'shipping_gross')::numeric;
  if v_expected_shipping is null then
    if v_shipping_gross > 0 then
      raise exception 'A current shipping quote is required before checkout' using errcode = '23514';
    end if;
    v_expected_shipping := 0;
  end if;
  if v_expected_shipping <> v_shipping_gross then
    raise exception 'Shipping quote changed; refresh checkout before paying' using errcode = '40001';
  end if;

  perform pg_catalog.set_config('app.online_order_shipping_quote_in_progress', 'true', true);
  update public.online_orders
     set subtotal = (v_item_snapshot ->> 'net_amount')::numeric,
         tax_amount = (v_item_snapshot ->> 'tax_amount')::numeric,
         shipping_cost = v_shipping_gross,
         shipping_net_amount = (v_shipping ->> 'shipping_net')::numeric,
         shipping_tax_amount = (v_shipping ->> 'shipping_tax')::numeric,
         shipping_tax_rate = (v_shipping ->> 'tax_rate')::numeric,
         shipping_rate_tier_id = nullif(v_shipping ->> 'tier_id', '')::uuid,
         shipping_rate_snapshot = v_shipping,
         discount_amount = 0,
         total = (v_item_snapshot ->> 'gross_amount')::numeric + v_shipping_gross
   where id = v_order_id and tenant_id = v_quote.tenant_id;
  perform pg_catalog.set_config('app.online_order_shipping_quote_in_progress', '', true);

  select jsonb_build_object(
    'success', true, 'order_id', o.id, 'status', o.status, 'payment_status', o.payment_status,
    'version', o.version, 'invoice_id', o.sales_invoice_id, 'total', o.total,
    'shipping_cost', o.shipping_cost, 'changed', true
  ) into v_created
    from public.online_orders o where o.id = v_order_id;

  insert into public.online_order_events (
    tenant_id, order_id, event_type, from_status, to_status, from_payment_status,
    to_payment_status, changed, expected_version, result_version, actor_id,
    operation_key, request_snapshot, response_snapshot
  )
  select o.tenant_id, o.id, 'order_created', null, o.status, null, o.payment_status,
         true, null, o.version, auth.uid(),
         'customer-quote-created:' || o.id::text,
         jsonb_build_object(
           'source', 'customer_quote',
           'quote_id', v_quote.id,
           'quote_number', v_quote.quote_number,
           'offer_id', v_offer.id,
           'delivery_type', o.delivery_type,
           'payment_method', o.payment_method,
           'on_order_lines', v_on_order,
           'tax_source', 'customer_quote_offer',
           'shipping_quote', o.shipping_rate_snapshot,
           'accepted_shipping_cost', v_expected_shipping
         ),
         v_created
    from public.online_orders o where o.id = v_order_id;

  perform public.capture_online_order_storefront_snapshot(v_order_id, v_quote.tenant_id);

  update public.customer_quote_offers
     set status = 'accepted', responded_at = clock_timestamp()
   where id = v_offer.id;
  update public.customer_quotes
     set status = 'accepted', accepted_at = clock_timestamp(), online_order_id = v_order_id,
         updated_at = clock_timestamp(), version = version + 1
   where id = v_quote.id;
  perform public.customer_quote_log_internal(
    v_quote.id, 'accepted', 'customer', null, 'web', v_offer.id, v_key,
    jsonb_build_object(
      'total', v_offer.total, 'order_id', v_order_id,
      'order_number', (select order_number from public.online_orders where id = v_order_id),
      'delivery_type', v_delivery, 'payment_method', v_method, 'on_order_lines', v_on_order
    )
  );
  perform public.customer_quote_notify_internal(
    v_quote.id, 'customer_quote_accepted', 'Cotización aceptada', 'customer_quote_offer', v_offer.id, 'success'
  );

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  -- Una transferencia con todo en stock sigue el camino de cualquier pedido:
  -- su venta nace al tiro y se paga al confirmar. Con algo a pedido, la
  -- venta espera a que llegue.
  if v_method = 'transfer' and v_on_order = 0 then
    perform public.process_public_checkout_order(v_order_id, v_quote.tenant_id);
  end if;

  v_access_token := public.issue_online_order_access_token(
    v_order_id, array['view_order']::text[], clock_timestamp() + interval '30 days'
  );
  return public.customer_quote_order_receipt_internal(v_order_id, v_access_token, false);
exception
  when others then
    perform pg_catalog.set_config('app.online_order_shipping_quote_in_progress', '', true);
    perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);
    raise;
end;
$$;

revoke all on function public.accept_public_customer_quote_v1(text, jsonb) from public;
grant execute on function public.accept_public_customer_quote_v1(text, jsonb) to anon, authenticated, service_role;

-- Desde la página de la cotización, volver al pedido (para pagarlo o
-- seguirlo) con el mismo enlace que la aceptó.
create or replace function public.open_public_customer_quote_order_v1(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens;
  v_order_id uuid;
  v_access_token jsonb;
begin
  v_access := public.customer_quote_token_internal(p_token, 'respond_quote');
  if v_access.id is null then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;
  select q.online_order_id into v_order_id
    from public.customer_quotes q
   where q.id = v_access.quote_id and q.tenant_id = v_access.tenant_id;
  if v_order_id is null then
    raise exception 'quote_has_no_order' using errcode = 'P0002';
  end if;
  v_access_token := public.issue_online_order_access_token(
    v_order_id, array['view_order']::text[], clock_timestamp() + interval '30 days'
  );
  return public.customer_quote_order_receipt_internal(v_order_id, v_access_token, true);
end;
$$;

revoke all on function public.open_public_customer_quote_order_v1(text) from public;
grant execute on function public.open_public_customer_quote_order_v1(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Los hitos del pedido en la historia de la cotización y, si el cliente
--    eligió WhatsApp, su aviso «Por enviar».
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_order_event_mirror()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_event text;
begin
  select * into v_quote from public.customer_quotes q
   where q.online_order_id = new.order_id and q.tenant_id = new.tenant_id;
  if not found then
    return null;
  end if;
  v_event := case
    when new.event_type = 'payment_transition' and new.to_payment_status = 'paid' then 'order_paid'
    when new.event_type = 'status_transition' and new.to_status = 'ready_for_pickup' then 'order_ready'
    when new.event_type = 'status_transition' and new.to_status = 'shipped' then 'order_shipped'
    when new.event_type = 'status_transition' and new.to_status = 'delivered' then 'order_delivered'
    when new.event_type = 'status_transition' and new.to_status = 'cancelled' then 'order_cancelled'
  end;
  if v_event is null then
    return null;
  end if;
  begin
    if not exists (
      select 1 from public.customer_quote_events e
       where e.quote_id = v_quote.id and e.operation_key = 'order-event:' || new.id::text
    ) then
      perform public.customer_quote_log_internal(
        v_quote.id, v_event, 'system', null, 'system', v_quote.current_offer_id,
        'order-event:' || new.id::text,
        jsonb_build_object('order_id', new.order_id)
      );
    end if;
    if v_event in ('order_paid', 'order_ready', 'order_shipped') then
      perform public.customer_quote_enqueue_message_internal(v_quote.id, v_event, v_quote.current_offer_id);
    end if;
  exception when others then
    -- La historia de la cotización nunca frena un cambio del pedido.
    raise warning 'Customer quote order mirror failed for order %: %', new.order_id, sqlerrm;
  end;
  return null;
end;
$$;

revoke all on function public.customer_quote_order_event_mirror() from public, anon, authenticated;

drop trigger if exists trg_customer_quote_order_event_mirror on public.online_order_events;
create trigger trg_customer_quote_order_event_mirror
  after insert on public.online_order_events
  for each row when (new.changed)
  execute function public.customer_quote_order_event_mirror();

-- ---------------------------------------------------------------------------
-- 5. Lo que ya existía, con el pedido a pedido adentro. Cada función es la
--    definición de producción (leída el 2026-11-02) con su agregado marcado.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reserve_online_order_item_inventory(p_order_item_id uuid, p_executor text DEFAULT 'database_rpc'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item public.online_order_items%rowtype;
  v_order public.online_orders%rowtype;
  v_source public.products%rowtype;
  v_target record;
  v_target_product public.products%rowtype;
  v_reservation public.online_order_inventory_reservations%rowtype;
  v_existing public.online_order_inventory_reservations%rowtype;
  v_deadline timestamptz;
  v_reserved_other integer;
  v_physical integer;
  v_target_count integer := 0;
  v_was_existing boolean;
begin
  if p_order_item_id is null then
    raise exception 'Online order item is required' using errcode = '22023';
  end if;

  select item.* into v_item
    from public.online_order_items item
   where item.id = p_order_item_id;
  if not found then
    raise exception 'Online order item not found' using errcode = '23503';
  end if;

  -- Una línea a pedido de una cotización no tiene stock que apartar hasta
  -- que llega; al llegar se aparta (20261103010000).
  if v_item.fulfillment = 'on_order' and v_item.arrived_at is null then
    return 0;
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = v_item.order_id
     and orders.tenant_id = v_item.tenant_id
   for update;
  if not found then
    raise exception 'Online order item tenant mismatch' using errcode = '42501';
  end if;
  if v_order.status in ('cancelled', 'delivered') then
    raise exception 'Inventory cannot be reserved for terminal online order %',
      v_order.order_number using errcode = '23514';
  end if;

  select product.* into v_source
    from public.products product
   where product.id = v_item.product_id
     and product.tenant_id = v_item.tenant_id;
  if not found then
    raise exception 'Online order product is missing from its tenant'
      using errcode = '23503';
  end if;

  if coalesce(v_item.is_service, v_source.is_service, false)
     or coalesce(v_item.product_type, v_source.product_type) = 'service'
     or coalesce(v_item.purchase_treatment, v_source.purchase_treatment, 'inventory')
          = 'workshop_consumable'
     or not coalesce(v_source.track_stock, true) then
    return 0;
  end if;

  if v_item.quantity <= 0 or v_item.quantity <> trunc(v_item.quantity) then
    raise exception 'Tracked online order quantities must be whole units'
      using errcode = '23514';
  end if;

  -- A tenant-scoped advisory lock keeps differently ordered carts from
  -- deadlocking while product row locks serialize them with POS/adjustments.
  perform pg_advisory_xact_lock(hashtextextended(
    'online_inventory_reservation:' || v_item.tenant_id::text,
    0
  ));
  perform public.expire_online_order_inventory_reservations(
    v_item.tenant_id,
    5000
  );

  v_deadline := clock_timestamp()
    + public.online_order_inventory_reservation_ttl(
        v_item.tenant_id,
        v_order.payment_method
      );

  for v_target in
    select requirement.product_id, requirement.required_quantity
      from (
        select v_source.id as product_id,
               v_item.quantity::integer as required_quantity
         where not coalesce(v_source.is_set, false)
        union all
        select component.component_product_id,
               (v_item.quantity::integer * component.quantity_in_set)::integer
          from public.product_set_components component
         where component.tenant_id = v_item.tenant_id
           and component.set_product_id = v_source.id
           and coalesce(v_source.is_set, false)
      ) requirement
     order by requirement.product_id
  loop
    v_target_count := v_target_count + 1;

    select product.* into v_target_product
      from public.products product
     where product.id = v_target.product_id
       and product.tenant_id = v_item.tenant_id
     for update;
    if not found then
      raise exception 'Set component is missing from the online-order tenant'
        using errcode = '23503';
    end if;
    if coalesce(v_target_product.is_service, false)
       or v_target_product.product_type = 'service'
       or not coalesce(v_target_product.track_stock, true) then
      raise exception 'Tracked online set contains a non-stock component: %',
        v_target_product.name using errcode = '23514';
    end if;
    if coalesce(v_target_product.inventory_qty, 0)
       <> coalesce(v_target_product.stock_quantity, 0) then
      raise exception 'Product stock columns disagree; reservation blocked for %',
        v_target_product.name using errcode = '23514';
    end if;
    if v_target.required_quantity <= 0 then
      raise exception 'Online set contains an invalid component quantity'
        using errcode = '23514';
    end if;

    select reservation.* into v_existing
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = v_item.tenant_id
       and reservation.order_item_id = v_item.id
       and reservation.product_id = v_target.product_id
     for update;
    v_was_existing := found;

    if v_was_existing
       and v_existing.state in ('consuming', 'consumed') then
      if v_existing.quantity <> v_target.required_quantity then
        raise exception 'Consumed reservation no longer matches its order item'
          using errcode = '23514';
      end if;
      continue;
    end if;
    if v_was_existing
       and v_existing.state = 'active'
       and v_existing.expires_at > clock_timestamp() then
      if v_existing.quantity <> v_target.required_quantity then
        raise exception 'Active reservation no longer matches its order item'
          using errcode = '23514';
      end if;
      continue;
    end if;

    select coalesce(sum(reservation.quantity), 0)::integer
      into v_reserved_other
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = v_item.tenant_id
       and reservation.product_id = v_target.product_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
       and (not v_was_existing or reservation.id <> v_existing.id);

    v_physical := coalesce(
      v_target_product.stock_quantity,
      v_target_product.inventory_qty,
      0
    );
    if v_physical - v_reserved_other < v_target.required_quantity then
      raise exception 'Insufficient available stock for product %',
        v_target_product.name using errcode = '23514';
    end if;

    if v_was_existing then
      if v_existing.state not in ('released', 'expired') then
        raise exception 'Reservation is not eligible for reactivation: %',
          v_existing.state using errcode = '23514';
      end if;
      update public.online_order_inventory_reservations reservation
         set quantity = v_target.required_quantity,
             state = 'active',
             cycle = reservation.cycle + 1,
             version = reservation.version + 1,
             reserved_at = clock_timestamp(),
             expires_at = v_deadline,
             consumption_started_at = null,
             consumed_at = null,
             released_at = null,
             expired_at = null,
             release_reason = null,
             sales_invoice_id = null,
             stock_movement_ids = array[]::uuid[],
             created_by = auth.uid(),
             updated_at = clock_timestamp()
       where reservation.id = v_existing.id
         and reservation.tenant_id = v_existing.tenant_id
       returning reservation.* into v_reservation;
    else
      insert into public.online_order_inventory_reservations (
        tenant_id, order_id, order_item_id, product_id, quantity,
        state, reserved_at, expires_at, created_by
      ) values (
        v_item.tenant_id,
        v_item.order_id,
        v_item.id,
        v_target.product_id,
        v_target.required_quantity,
        'active',
        clock_timestamp(),
        v_deadline,
        auth.uid()
      ) returning * into v_reservation;
    end if;

    perform public.append_online_inventory_reservation_event(
      v_reservation,
      case when v_was_existing then 're_reserved' else 'reserved' end,
      case when v_was_existing then v_existing.state else null end,
      'active',
      coalesce(nullif(btrim(p_executor), ''), 'database_rpc'),
      'reservation-reserve:' || v_reservation.id::text || ':'
        || v_reservation.cycle::text,
      jsonb_build_object(
        'source_product_id', v_source.id,
        'is_set_component', coalesce(v_source.is_set, false),
        'physical_stock', v_physical,
        'other_reserved_quantity', v_reserved_other,
        'expires_at', v_reservation.expires_at
      )
    );
  end loop;

  if coalesce(v_source.is_set, false) and v_target_count = 0 then
    raise exception 'Tracked online set has no component definition: %',
      v_source.name using errcode = '23514';
  end if;

  return v_target_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.process_online_order_internal(p_order_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_items jsonb;
  v_next_number integer;
  v_year text;
  v_payment_method record;
  v_tenant_id uuid;
  v_net_amount numeric(12,2);
  v_iva_amount numeric(12,2);
  v_gross_amount numeric(12,2);
  v_item_net_amount numeric(12,2);
  v_item_tax_amount numeric(12,2);
  v_item_gross_amount numeric(12,2);
  v_tax_treatment text;
  v_tax_snapshot jsonb;
  v_invoice_status text;
  v_should_create_payment boolean;
  v_invoice_date timestamp with time zone;
begin
  select * into v_order
    from public.online_orders
   where id = p_order_id
   for update;

  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  v_tenant_id := v_order.tenant_id;
  if v_tenant_id is null then
    raise exception 'Order has no tenant_id: %', p_order_id;
  end if;

  -- A linked invoice is immutable. This branch only settles it once the
  -- provider payment becomes durable.
  if v_order.sales_invoice_id is not null then
    perform 1
      from public.sales_invoices invoice
     where invoice.id = v_order.sales_invoice_id
       and invoice.tenant_id = v_tenant_id;
    if not found then
      raise exception 'Linked sales invoice is missing or belongs to another tenant: %',
        v_order.sales_invoice_id
        using errcode = '23503';
    end if;

    if v_order.payment_status = 'paid' then
      select * into v_payment_method
        from public.payment_methods
       where tenant_id = v_tenant_id
         and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
         and is_active = true
       limit 1;

      if v_payment_method is null then
        select * into v_payment_method
          from public.payment_methods
         where tenant_id = v_tenant_id
           and is_active = true
         order by sort_order
         limit 1;
      end if;

      perform 1
        from public.sales_invoices
       where id = v_order.sales_invoice_id
         and tenant_id = v_tenant_id
         and status != 'paid';

      if found then
        update public.sales_invoices
           set status = 'paid',
               paid_amount = total,
               balance = 0,
               updated_at = now()
         where id = v_order.sales_invoice_id
           and tenant_id = v_tenant_id;

        if not exists (
          select 1
            from public.sales_payments
           where invoice_id = v_order.sales_invoice_id
             and tenant_id = v_tenant_id
        ) and v_payment_method.id is not null then
          insert into public.sales_payments (
            tenant_id,
            invoice_id,
            invoice_reference,
            payment_method_id,
            amount,
            date,
            reference,
            notes
          ) values (
            v_tenant_id,
            v_order.sales_invoice_id,
            (
              select invoice_number
                from public.sales_invoices
               where id = v_order.sales_invoice_id
                 and tenant_id = v_tenant_id
            ),
            v_payment_method.id,
            v_order.total,
            coalesce(v_order.paid_at, now()),
            v_order.payment_reference,
            'Pago automático - Pedido online #' || v_order.order_number
              || ' (' || coalesce(v_payment_method.name, v_order.payment_method)
              || ')'
          );
        end if;
      end if;
    end if;

    return v_order.sales_invoice_id;
  end if;

  -- Un pedido de cotización con productos a pedido espera a que lleguen: la
  -- venta (stock, asientos y el pago) se emite cuando está todo. El pago ya
  -- recibido queda en el pedido (20261103010000).
  if public.customer_quote_order_waiting_internal(p_order_id) then
    if v_order.payment_status = 'paid' then
      perform public.customer_quote_order_paid_internal(p_order_id);
    end if;
    if public.customer_quote_order_waiting_internal(p_order_id) then
      return null;
    end if;
    select * into v_order
      from public.online_orders
     where id = p_order_id
     for update;
  end if;

  if coalesce(v_order.discount_amount, 0) <> 0 then
    raise exception 'Online order discount lacks an immutable tax classification'
      using errcode = '23514';
  end if;

  v_tax_snapshot := public.calculate_online_order_tax_snapshot(
    p_order_id,
    v_tenant_id
  );
  v_item_gross_amount := (v_tax_snapshot->>'gross_amount')::numeric;
  v_item_net_amount := (v_tax_snapshot->>'net_amount')::numeric;
  v_item_tax_amount := (v_tax_snapshot->>'tax_amount')::numeric;
  v_items := v_tax_snapshot->'items';

  -- Item and shipping tax snapshots are independently immutable. Their sum
  -- must reconcile exactly to the gross amount accepted by the customer.
  if v_order.subtotal is distinct from v_item_net_amount
     or v_order.tax_amount is distinct from v_item_tax_amount then
    raise exception 'Online order item monetary snapshot does not reconcile'
      using errcode = '23514';
  end if;
  if v_order.shipping_cost is null
     or v_order.shipping_net_amount is null
     or v_order.shipping_tax_amount is null
     or v_order.shipping_tax_rate is null
     or v_order.shipping_cost
          <> v_order.shipping_net_amount + v_order.shipping_tax_amount then
    raise exception 'Online order shipping monetary snapshot does not reconcile'
      using errcode = '23514';
  end if;
  if v_order.shipping_cost > 0 and (
       v_order.delivery_type <> 'shipping'
       or v_order.shipping_tax_rate <> 19
       or v_order.shipping_rate_tier_id is null
       or coalesce(v_order.shipping_rate_snapshot, '{}'::jsonb) = '{}'::jsonb
     ) then
    raise exception 'Online order shipping evidence is incomplete'
      using errcode = '23514';
  end if;
  if v_order.shipping_cost = 0 and (
       v_order.shipping_net_amount <> 0
       or v_order.shipping_tax_amount <> 0
     ) then
    raise exception 'Zero-cost shipping has a non-zero tax breakdown'
      using errcode = '23514';
  end if;

  v_gross_amount := v_item_gross_amount + v_order.shipping_cost;
  v_net_amount := v_item_net_amount + v_order.shipping_net_amount;
  v_iva_amount := v_item_tax_amount + v_order.shipping_tax_amount;
  if v_order.total is distinct from v_gross_amount
     or v_gross_amount <> v_net_amount + v_iva_amount then
    raise exception 'Online order total does not reconcile to item and shipping snapshots'
      using errcode = '23514';
  end if;

  if v_order.shipping_cost > 0 then
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'line_kind', 'shipping',
      'product_id', null,
      'product_name', 'Despacho a domicilio',
      'product_sku', 'ENVIO',
      'quantity', 1,
      'unit_price', v_order.shipping_cost,
      'price', v_order.shipping_cost,
      'subtotal', v_order.shipping_cost,
      'line_total', v_order.shipping_cost,
      'gross_amount', v_order.shipping_cost,
      'net_amount', v_order.shipping_net_amount,
      'tax_amount', v_order.shipping_tax_amount,
      'tax_rate', v_order.shipping_tax_rate,
      'discount', 0,
      'cost', null,
      'is_service', true,
      'purchase_treatment', 'service',
      'product_type', 'service',
      'is_catalog_product', false,
      'shipping_rate_tier_id', v_order.shipping_rate_tier_id,
      'shipping_rate_snapshot', v_order.shipping_rate_snapshot
    ));
  end if;
  v_tax_treatment := case
    when v_iva_amount > 0 then 'tax_included'
    else 'no_tax'
  end;

  select * into v_payment_method
    from public.payment_methods
   where tenant_id = v_tenant_id
     and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
     and is_active = true
   limit 1;

  if v_payment_method is null then
    select * into v_payment_method
      from public.payment_methods
     where tenant_id = v_tenant_id
       and is_active = true
     order by sort_order
     limit 1;
  end if;

  if v_order.payment_status = 'paid' then
    v_invoice_status := 'paid';
    v_should_create_payment := true;
  elsif lower(v_order.payment_method) = 'mercadopago'
        and v_order.payment_status = 'pending' then
    v_invoice_status := 'confirmed';
    v_should_create_payment := false;
  else
    v_invoice_status := 'sent';
    v_should_create_payment := false;
  end if;

  -- Lo que vino a pedido se vende el día que llega todo: la venta nace con
  -- la entrega y el pago conserva su fecha (20261103010000).
  v_invoice_date := case
    when exists (
      select 1
        from public.online_order_items item
       where item.order_id = p_order_id
         and item.fulfillment = 'on_order'
    ) then now()
    when v_order.payment_status = 'paid' then
      coalesce(v_order.paid_at, v_order.created_at, now())
    else coalesce(v_order.created_at, now())
  end;
  v_year := to_char(v_invoice_date, 'YY');

  perform pg_advisory_xact_lock(hashtextextended(
    'online_order_invoice_number:' || v_tenant_id::text || ':' || v_year,
    0
  ));
  select coalesce(
    max(cast(substring(invoice_number from '\d+$') as integer)),
    0
  ) + 1
    into v_next_number
    from public.sales_invoices
   where tenant_id = v_tenant_id
     and invoice_number ~ ('^INV-' || v_year || '-\d+$');

  v_invoice_number := 'INV-' || v_year || '-'
    || lpad(
      v_next_number::text,
      greatest(5, length(v_next_number::text)),
      '0'
    );

  insert into public.sales_invoices (
    tenant_id,
    invoice_number,
    customer_id,
    customer_name,
    date,
    due_date,
    status,
    tax_treatment,
    net_amount,
    subtotal,
    iva_amount,
    total,
    paid_amount,
    balance,
    items,
    reference,
    source
  ) values (
    v_tenant_id,
    v_invoice_number,
    v_order.customer_id,
    v_order.customer_name,
    v_invoice_date,
    v_invoice_date + interval '30 days',
    v_invoice_status,
    v_tax_treatment,
    v_net_amount,
    v_gross_amount,
    v_iva_amount,
    v_order.total,
    case when v_should_create_payment then v_order.total else 0 end,
    case when v_should_create_payment then 0 else v_order.total end,
    v_items,
    'Pedido online #' || v_order.order_number || case
      when v_order.delivery_type = 'pickup' then ' (Retiro en tienda)'
      else ' (Envío)'
    end,
    'ecommerce'
  ) returning id into v_invoice_id;

  if v_invoice_status in ('paid', 'confirmed') then
    declare
      v_invoice_record public.sales_invoices%rowtype;
    begin
      select * into v_invoice_record
        from public.sales_invoices
       where id = v_invoice_id
         and tenant_id = v_tenant_id;
      perform public.consume_sales_invoice_inventory(v_invoice_record);
      perform public.create_sales_invoice_journal_entry(v_invoice_record);
    end;
  end if;

  update public.online_orders
     set sales_invoice_id = v_invoice_id,
         status = case
           when status = 'pending' then 'confirmed'
           else status
         end
   where id = p_order_id
     and tenant_id = v_tenant_id;

  if v_should_create_payment and v_payment_method.id is not null then
    insert into public.sales_payments (
      tenant_id,
      invoice_id,
      invoice_reference,
      payment_method_id,
      amount,
      date,
      reference,
      notes
    ) values (
      v_tenant_id,
      v_invoice_id,
      v_invoice_number,
      v_payment_method.id,
      v_order.total,
      coalesce(v_order.paid_at, v_invoice_date),
      v_order.payment_reference,
      'Pago automático - Pedido online #' || v_order.order_number
        || ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
    );
  end if;

  return v_invoice_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.process_online_order(p_order_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_invoice_id uuid;
  v_previous_context text := current_setting('app.online_order_id', true);
begin
  select tenant_id into v_tenant_id
    from public.online_orders
   where id = p_order_id;
  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  if auth.uid() is not null
     and v_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = '42501';
  end if;

  perform set_config('app.online_order_id', p_order_id::text, true);
  v_invoice_id := public.process_online_order_internal(p_order_id);
  -- Sin venta (un pedido de cotización que espera lo que viene a pedido) no
  -- hay reservas que cerrar todavía (20261103010000).
  if v_invoice_id is not null then
    perform public.finalize_online_inventory_reservations_for_invoice(
      p_order_id,
      v_invoice_id,
      v_tenant_id,
      false
    );
  end if;
  perform set_config('app.online_order_id', coalesce(v_previous_context, ''), true);
  return v_invoice_id;
exception when others then
  perform set_config('app.online_order_id', coalesce(v_previous_context, ''), true);
  raise;
end;
$function$;

CREATE OR REPLACE FUNCTION public.process_public_checkout_order(p_order_id uuid, p_tenant_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_invoice_id uuid;
  v_previous_context text := current_setting('app.online_order_id', true);
begin
  if not exists (
    select 1
    from public.online_orders customer_order
    where customer_order.id = p_order_id
      and customer_order.tenant_id = p_tenant_id
  ) then
    raise exception 'Order not found: %', p_order_id;
  end if;

  perform set_config('app.online_order_id', p_order_id::text, true);
  v_invoice_id := public.process_online_order_internal(p_order_id);
  if v_invoice_id is not null then
    perform public.finalize_online_inventory_reservations_for_invoice(
      p_order_id,
      v_invoice_id,
      p_tenant_id,
      false
    );
  end if;
  perform set_config('app.online_order_id', coalesce(v_previous_context, ''), true);
  return v_invoice_id;
exception when others then
  perform set_config('app.online_order_id', coalesce(v_previous_context, ''), true);
  raise;
end;
$function$;

CREATE OR REPLACE FUNCTION public.process_mercadopago_payment_observation(p_payment_event_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_event public.sales_channel_payment_events%rowtype;
  v_processing public.sales_channel_payment_processing%rowtype;
  v_order public.online_orders%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_invoice_id uuid;
  v_operation_id uuid;
  v_attempt_number integer;
  v_attempted_at timestamp with time zone := clock_timestamp();
  v_error_code text;
  v_error_message text;
  v_sqlstate text;
  v_payment_count integer;
  v_payment_total numeric(14,2);
  v_requires_refund_review boolean := false;
begin
  if p_payment_event_id is null then
    raise exception 'Payment event identifier is required'
      using errcode = '22023';
  end if;

  select payment_event.* into v_event
  from public.sales_channel_payment_events payment_event
  where payment_event.id = p_payment_event_id
    and payment_event.provider = 'mercadopago';

  if not found then
    raise exception 'Mercado Pago payment observation not found'
      using errcode = '23503';
  end if;

  select processing.* into v_processing
  from public.sales_channel_payment_processing processing
  where processing.payment_event_id = v_event.id
    and processing.tenant_id = v_event.tenant_id
    and processing.order_id = v_event.order_id
  for update;

  if not found then
    raise exception 'Mercado Pago payment processing projection is missing'
      using errcode = '23503';
  end if;

  if auth.uid() is null then
    -- service_role workers and direct database maintenance are trusted. An
    -- authenticated/anon API role without a subject must never inherit that
    -- internal bypass.
    if coalesce(auth.role(), '') in ('authenticated', 'anon') then
      raise exception 'Payment observation not found or access denied'
        using errcode = '42501';
    end if;
  elsif not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = auth.uid()
      and profile.tenant_id = v_event.tenant_id
      and profile.is_active is true
      and (
        profile.role in ('admin', 'manager', 'cashier')
        or coalesce(profile.permissions->'create_invoices', 'false'::jsonb)
             = 'true'::jsonb
      )
  ) then
    raise exception 'Payment observation not found or access denied'
      using errcode = '42501';
  end if;

  if v_processing.processing_state = 'processed' then
    return jsonb_build_object(
      'event_id', v_event.id,
      'order_id', v_event.order_id,
      'outcome', v_event.outcome,
      'processing_state', v_processing.processing_state,
      'attempt_count', v_processing.attempt_count,
      'invoice_id', v_processing.invoice_id,
      'operation_id', v_processing.operation_id,
      'replay', true
    );
  end if;

  select * into v_order
  from public.online_orders orders
  where orders.id = v_event.order_id
    and orders.tenant_id = v_event.tenant_id
  for update;

  if not found then
    raise exception 'Online order missing for durable payment observation'
      using errcode = '23503';
  end if;

  v_attempt_number := v_processing.attempt_count + 1;

  if v_event.outcome in ('rejected_amount', 'rejected_currency', 'rejected_conflicting_payment') then
    v_error_code := v_event.outcome;
    v_error_message := 'Pago aprobado requiere conciliacion manual antes de aplicar la venta.';
    v_requires_refund_review := v_event.provider_status = 'approved';
  elsif v_event.outcome = 'ignored_stale' then
    update public.sales_channel_payment_processing
       set processing_state = 'processed',
           attempt_count = v_attempt_number,
           first_attempted_at = coalesce(first_attempted_at, v_attempted_at),
           last_attempted_at = v_attempted_at,
           processed_at = clock_timestamp(),
           action_required_at = null,
           last_error_code = null,
           last_error_message = null,
           requires_refund_review = false,
           updated_at = clock_timestamp()
     where payment_event_id = v_event.id;

    insert into public.sales_channel_payment_processing_attempts (
      payment_event_id, tenant_id, order_id, attempt_number, result_state,
      attempted_at
    ) values (
      v_event.id, v_event.tenant_id, v_event.order_id, v_attempt_number,
      'processed', v_attempted_at
    );

    return jsonb_build_object(
      'event_id', v_event.id,
      'order_id', v_event.order_id,
      'outcome', v_event.outcome,
      'processing_state', 'processed',
      'attempt_count', v_attempt_number,
      'replay', false
    );
  elsif v_event.outcome in ('recorded_pending', 'recorded_failed') then
    if v_order.payment_status not in ('paid', 'refunded') then
      perform set_config('app.defer_online_order_payment_processing', 'true', true);
      update public.online_orders
         set payment_status = case
               when v_event.outcome = 'recorded_failed' then 'failed'
               else 'pending'
             end,
             payment_method = 'mercadopago',
             payment_reference = v_event.external_payment_id,
             paid_at = null
       where id = v_order.id
         and tenant_id = v_order.tenant_id;
      perform set_config('app.defer_online_order_payment_processing', '', true);
    end if;

    update public.sales_channel_payment_processing
       set processing_state = 'processed',
           attempt_count = v_attempt_number,
           first_attempted_at = coalesce(first_attempted_at, v_attempted_at),
           last_attempted_at = v_attempted_at,
           processed_at = clock_timestamp(),
           action_required_at = null,
           last_error_code = null,
           last_error_message = null,
           requires_refund_review = false,
           updated_at = clock_timestamp()
     where payment_event_id = v_event.id;

    insert into public.sales_channel_payment_processing_attempts (
      payment_event_id, tenant_id, order_id, attempt_number, result_state,
      attempted_at
    ) values (
      v_event.id, v_event.tenant_id, v_event.order_id, v_attempt_number,
      'processed', v_attempted_at
    );

    return jsonb_build_object(
      'event_id', v_event.id,
      'order_id', v_event.order_id,
      'outcome', v_event.outcome,
      'processing_state', 'processed',
      'attempt_count', v_attempt_number,
      'replay', false
    );
  elsif v_event.outcome not in ('payment_validated', 'applied') then
    raise exception 'Unsupported Mercado Pago observation outcome: %', v_event.outcome
      using errcode = '23514';
  end if;

  if v_error_code is null and v_order.payment_status = 'refunded' then
    v_error_code := 'approved_payment_after_refund';
    v_error_message := 'Pago aprobado observado despues de un reembolso; requiere conciliacion.';
    v_requires_refund_review := true;
  elsif v_error_code is null
     and v_order.payment_status = 'paid'
     and nullif(btrim(coalesce(v_order.payment_reference, '')), '')
       is distinct from v_event.external_payment_id then
    v_error_code := 'conflicting_approved_payment';
    v_error_message := 'Existe otro pago aprobado asociado al pedido; revisar posible cobro duplicado.';
    v_requires_refund_review := true;
  end if;

  if v_error_code is null and v_order.payment_status <> 'paid' then
    begin
      perform set_config('app.defer_online_order_payment_processing', 'true', true);
      update public.online_orders
         set payment_status = 'paid',
             payment_method = 'mercadopago',
             payment_reference = v_event.external_payment_id,
             paid_at = coalesce(v_event.provider_paid_at, clock_timestamp())
       where id = v_order.id
         and tenant_id = v_order.tenant_id;
      perform set_config('app.defer_online_order_payment_processing', '', true);
    exception when others then
      perform set_config('app.defer_online_order_payment_processing', '', true);
      get stacked diagnostics v_sqlstate = returned_sqlstate;
      v_error_code := 'payment_state_update_failed_' || lower(v_sqlstate);
      v_error_message := 'El pago fue validado, pero no se pudo actualizar el estado del pedido.';
    end;
  end if;

  if v_error_code is null and v_order.status = 'cancelled' then
    v_error_code := 'approved_payment_for_cancelled_order';
    v_error_message := 'El pedido cancelado recibio un pago aprobado; requiere conciliacion.';
    v_requires_refund_review := true;
  end if;

  -- Un pedido de cotización que espera productos a pedido: el pago queda
  -- validado en el pedido, lo que hay queda apartado y lo que falta se pide.
  -- La venta se emite cuando llega todo, volviendo a procesar este pago
  -- (20261103010000).
  if v_error_code is null
     and public.customer_quote_order_waiting_internal(v_order.id) then
    perform public.customer_quote_order_paid_internal(v_order.id);
    if public.customer_quote_order_waiting_internal(v_order.id) then
      v_error_code := 'awaiting_on_order_stock';
      v_error_message := 'Pago validado. La venta se emite cuando llegue lo que viene a pedido.';
    end if;
  end if;

  if v_error_code is null then
    begin
      -- Checkout does not reserve inventory. Lock and revalidate the exact
      -- product rows immediately before creating a posted invoice so two paid
      -- checkouts cannot drive the general staff-sale path below zero.
      perform product.id
      from public.products product
      join public.online_order_items item
        on item.product_id = product.id
       and item.tenant_id = product.tenant_id
      where item.order_id = v_order.id
        and item.tenant_id = v_event.tenant_id
      order by product.id
      for update of product;

      if exists (
        select 1
        from public.online_order_items item
        join public.products product
          on product.id = item.product_id
         and product.tenant_id = item.tenant_id
        where item.order_id = v_order.id
          and item.tenant_id = v_event.tenant_id
          and not (
            coalesce(item.is_service, product.is_service, false)
            or coalesce(item.product_type, product.product_type) = 'service'
          )
          and coalesce(product.track_stock, true)
          and (
            (
              product.stock_quantity is not null
              and product.inventory_qty is not null
              and product.stock_quantity <> product.inventory_qty
            )
            or coalesce(product.stock_quantity, product.inventory_qty, 0)
                 < item.quantity
          )
      ) then
        raise exception 'Canonical product stock is unavailable for paid online order'
          using errcode = '23514';
      end if;

      if v_order.sales_invoice_id is not null and exists (
        select 1
        from public.sales_payments payment
        where payment.tenant_id = v_event.tenant_id
          and payment.invoice_id = v_order.sales_invoice_id
          and payment.deleted_at is null
          and coalesce(payment.idempotency_key, '')
                <> 'mercadopago:' || v_event.external_payment_id
          and coalesce(payment.reference, '') <> v_event.external_payment_id
      ) then
        raise exception 'Existing invoice has unrelated payment evidence'
          using errcode = '23514';
      end if;

      v_invoice_id := public.process_online_order(v_order.id);

      update public.sales_payments payment
         set idempotency_key = 'mercadopago:' || v_event.external_payment_id,
             updated_at = clock_timestamp()
       where payment.tenant_id = v_event.tenant_id
         and payment.invoice_id = v_invoice_id
         and payment.deleted_at is null
         and (
           payment.reference = v_event.external_payment_id
           or payment.idempotency_key = 'mercadopago:' || v_event.external_payment_id
         );

      select count(*)::integer, coalesce(sum(payment.amount), 0)
        into v_payment_count, v_payment_total
      from public.sales_payments payment
      where payment.tenant_id = v_event.tenant_id
        and payment.invoice_id = v_invoice_id
        and payment.deleted_at is null
        and payment.idempotency_key = 'mercadopago:' || v_event.external_payment_id;

      if v_payment_count <> 1
         or round(v_payment_total, 2) <> round(v_event.amount, 2) then
        raise exception 'Provider payment ledger did not reconcile exactly once'
          using errcode = '23514';
      end if;

      select * into v_invoice
      from public.sales_invoices invoice
      where invoice.id = v_invoice_id
        and invoice.tenant_id = v_event.tenant_id;

      if not found
         or lower(coalesce(v_invoice.status, '')) <> 'paid'
         or round(coalesce(v_invoice.balance, v_invoice.total), 2) <> 0 then
        raise exception 'Processed invoice is not fully settled'
          using errcode = '23514';
      end if;

      select operation.id into v_operation_id
      from public.inventory_accounting_operations operation
      where operation.tenant_id = v_event.tenant_id
        and operation.document_type = 'sales_invoice'
        and operation.document_id = v_invoice_id
        and operation.outcome = 'completed'
      order by operation.created_at desc, operation.id desc
      limit 1;

      if v_operation_id is null then
        raise exception 'Completed invoice inventory/accounting trace is missing'
          using errcode = '23514';
      end if;
    exception when others then
      get stacked diagnostics v_sqlstate = returned_sqlstate;
      v_error_code := case
        when v_sqlstate = '23514' then 'sale_processing_business_rule'
        when v_sqlstate = '23505' then 'sale_processing_idempotency_conflict'
        when v_sqlstate = '55P03' then 'sale_processing_lock_timeout'
        else 'sale_processing_internal_' || lower(v_sqlstate)
      end;
      v_error_message := case
        when v_sqlstate = '55P03'
          then 'El pago esta validado; el procesamiento quedo pendiente por concurrencia.'
        else 'El pago esta validado, pero stock, factura o contabilidad requieren revision.'
      end;
      v_invoice_id := null;
      v_operation_id := null;
    end;
  end if;

  if v_error_code is not null then
    update public.sales_channel_payment_processing
       set processing_state = 'action_required',
           attempt_count = v_attempt_number,
           first_attempted_at = coalesce(first_attempted_at, v_attempted_at),
           last_attempted_at = v_attempted_at,
           processed_at = null,
           action_required_at = coalesce(action_required_at, clock_timestamp()),
           invoice_id = null,
           operation_id = null,
           last_error_code = left(v_error_code, 96),
           last_error_message = left(v_error_message, 320),
           requires_refund_review = v_requires_refund_review,
           updated_at = clock_timestamp()
     where payment_event_id = v_event.id;

    insert into public.sales_channel_payment_processing_attempts (
      payment_event_id, tenant_id, order_id, attempt_number, result_state,
      error_code, error_message, requires_refund_review, attempted_at
    ) values (
      v_event.id, v_event.tenant_id, v_event.order_id, v_attempt_number,
      'action_required', left(v_error_code, 96), left(v_error_message, 320),
      v_requires_refund_review, v_attempted_at
    );

    return jsonb_build_object(
      'event_id', v_event.id,
      'order_id', v_event.order_id,
      'outcome', v_event.outcome,
      'payment_status', (
        select orders.payment_status
        from public.online_orders orders
        where orders.id = v_event.order_id
      ),
      'processing_state', 'action_required',
      'attempt_count', v_attempt_number,
      'error_code', left(v_error_code, 96),
      'error_message', left(v_error_message, 320),
      'requires_refund_review', v_requires_refund_review,
      'replay', false
    );
  end if;

  update public.sales_channel_payment_processing
     set processing_state = 'processed',
         attempt_count = v_attempt_number,
         first_attempted_at = coalesce(first_attempted_at, v_attempted_at),
         last_attempted_at = v_attempted_at,
         processed_at = clock_timestamp(),
         action_required_at = null,
         invoice_id = v_invoice_id,
         operation_id = v_operation_id,
         last_error_code = null,
         last_error_message = null,
         requires_refund_review = false,
         updated_at = clock_timestamp()
   where payment_event_id = v_event.id;

  insert into public.sales_channel_payment_processing_attempts (
    payment_event_id, tenant_id, order_id, attempt_number, result_state,
    invoice_id, operation_id, attempted_at
  ) values (
    v_event.id, v_event.tenant_id, v_event.order_id, v_attempt_number,
    'processed', v_invoice_id, v_operation_id, v_attempted_at
  );

  return jsonb_build_object(
    'event_id', v_event.id,
    'order_id', v_event.order_id,
    'outcome', v_event.outcome,
    'payment_status', 'paid',
    'processing_state', 'processed',
    'attempt_count', v_attempt_number,
    'invoice_id', v_invoice_id,
    'operation_id', v_operation_id,
    'replay', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_online_order_payment(p_order_id uuid, p_payment_reference text DEFAULT NULL::text, p_payment_date timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_order public.online_orders%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_payment_method_id uuid;
  v_payment_id uuid;
  v_operation_id uuid;
  v_invoice_operation_id uuid;
  v_payment_operation_id uuid;
  v_active_payment_total numeric := 0;
  v_reference text;
  v_before jsonb;
begin
  if v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_order
    from public.online_orders
   where id = p_order_id
     and tenant_id = v_tenant_id
   for update;

  if not found then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = 'insufficient_privilege';
  end if;

  -- The row lock serializes concurrent confirmations. A committed retry returns
  -- the exact original payment instead of creating another one.
  if lower(v_order.payment_status) = 'paid' then
    if v_order.manual_payment_id is not null and exists(
      select 1 from public.sales_payments payment
       where payment.id = v_order.manual_payment_id
         and payment.tenant_id = v_tenant_id
         and payment.deleted_at is null
    ) then
      return v_order.manual_payment_id;
    end if;
    return null;
  end if;

  if lower(v_order.status) = 'cancelled' then
    raise exception 'Cancelled orders cannot receive payment confirmation'
      using errcode = 'check_violation';
  end if;

  if lower(coalesce(v_order.payment_method, '')) not in (
    'transfer','transferencia','bank_transfer'
  ) then
    raise exception 'Manual confirmation is only available for bank-transfer orders'
      using errcode = 'check_violation';
  end if;

  -- Un pedido de cotización que espera productos a pedido todavía no tiene
  -- venta: la transferencia queda en el pedido y la venta la toma cuando
  -- llega todo (20261103010000).
  if v_order.sales_invoice_id is null
     and public.customer_quote_order_waiting_internal(v_order.id) then
    return public.customer_quote_order_record_transfer_internal(
      v_order.id, p_payment_reference, p_payment_date
    );
  end if;

  if v_order.sales_invoice_id is null then
    raise exception 'Order has no invoice. Process the online order first.'
      using errcode = 'check_violation';
  end if;

  select * into v_invoice
    from public.sales_invoices
   where id = v_order.sales_invoice_id
     and tenant_id = v_tenant_id
   for update;

  if not found then
    raise exception 'Linked invoice is missing or belongs to another tenant: %',
      v_order.sales_invoice_id
      using errcode = 'foreign_key_violation';
  end if;

  if lower(v_invoice.status) in ('cancelled','cancelado','cancelada','anulado','anulada') then
    raise exception 'Cancelled invoices cannot receive payment confirmation'
      using errcode = 'check_violation';
  end if;

  v_reference := coalesce(
    nullif(btrim(coalesce(p_payment_reference, '')), ''),
    nullif(btrim(coalesce(v_order.payment_reference, '')), '')
  );
  if v_reference is null then
    raise exception 'A bank/payment reference is required for manual confirmation'
      using errcode = 'check_violation';
  end if;

  if p_payment_date is null then
    raise exception 'Payment date is required'
      using errcode = 'check_violation';
  end if;
  if p_payment_date > clock_timestamp() + interval '5 minutes' then
    raise exception 'Payment date cannot be in the future'
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(payment.amount), 0)
    into v_active_payment_total
    from public.sales_payments payment
   where payment.invoice_id = v_invoice.id
     and payment.tenant_id = v_tenant_id
     and payment.deleted_at is null;

  if v_active_payment_total <> 0 then
    raise exception 'This invoice already has payments. Use the invoice payment workspace for partial or corrective settlement.'
      using errcode = 'check_violation';
  end if;

  if round(coalesce(v_invoice.total, 0), 2) <> round(coalesce(v_order.total, 0), 2) then
    raise exception 'Order and invoice totals differ. Review the linked invoice before confirming payment.'
      using errcode = 'check_violation';
  end if;
  if v_invoice.total <= 0 or v_invoice.total <> trunc(v_invoice.total) then
    raise exception 'Manual online payment must be a positive whole CLP amount'
      using errcode = 'check_violation';
  end if;

  select method.id into v_payment_method_id
    from public.payment_methods method
   where method.tenant_id = v_tenant_id
     and lower(method.code) = lower(coalesce(v_order.payment_method, 'transfer'))
     and method.is_active = true
   order by method.sort_order, method.id
   limit 1;

  if v_payment_method_id is null then
    select method.id into v_payment_method_id
      from public.payment_methods method
     where method.tenant_id = v_tenant_id
       and lower(method.code) in ('transfer','transferencia','bank_transfer')
       and method.is_active = true
     order by method.sort_order, method.id
     limit 1;
  end if;
  if v_payment_method_id is null then
    raise exception 'No active transfer payment method is configured for this tenant'
      using errcode = 'check_violation';
  end if;

  v_before := jsonb_build_object(
    'order', to_jsonb(v_order),
    'invoice', public.inventory_trace_document_snapshot(to_jsonb(v_invoice)),
    'active_payment_total', v_active_payment_total
  );

  insert into public.inventory_accounting_operations(
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status,
    before_snapshot, context
  ) values (
    v_tenant_id,
    'online_order_manual_payment:' || p_order_id::text,
    'online_sale_manual_payment',
    'confirm_payment',
    'online_order',
    p_order_id,
    auth.uid(),
    'database_rpc',
    v_order.payment_status,
    'paid',
    v_before,
    jsonb_build_object(
      'invoice_id', v_invoice.id,
      'payment_reference', v_reference,
      'payment_date', p_payment_date,
      'amount', v_invoice.total,
      'transaction_id', txid_current()::text
    )
  ) returning id into v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'online_order', p_order_id,
    jsonb_build_object('action', 'confirm_payment', 'invoice_id', v_invoice.id)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'online_order', p_order_id,
    v_before
  );

  if lower(v_invoice.status) in (
    'draft','borrador','sent','enviado','enviada','issued','emitido','emitida'
  ) then
    perform set_config('app.inventory_idempotency_key', 'online_order_manual_payment:' || p_order_id::text, true);
    update public.sales_invoices
       set status = 'confirmed', updated_at = clock_timestamp()
     where id = v_invoice.id and tenant_id = v_tenant_id;

    select operation.id into v_invoice_operation_id
      from public.inventory_accounting_operations operation
     where operation.tenant_id = v_tenant_id
       and operation.operation_key =
             'sales_invoice:' || v_invoice.id::text
             || ':update:online_order_manual_payment:' || p_order_id::text
       and operation.document_type = 'sales_invoice'
       and operation.document_id = v_invoice.id
       and operation.action = 'update'
       and operation.outcome = 'completed';

    if v_invoice_operation_id is null then
      raise exception 'Completed invoice trace missing for online-order payment confirmation %',
        p_order_id
        using errcode = 'data_exception';
    end if;
  elsif lower(v_invoice.status) not in ('confirmed','confirmado','confirmada') then
    raise exception 'Invoice status % is not eligible for manual online payment confirmation', v_invoice.status
      using errcode = 'check_violation';
  end if;

  perform set_config('app.inventory_idempotency_key', 'online_order_manual_payment:' || p_order_id::text, true);
  insert into public.sales_payments(
    tenant_id, invoice_id, invoice_reference, payment_method_id,
    idempotency_key, amount, date, reference, notes
  ) values (
    v_tenant_id, v_invoice.id, v_invoice.invoice_number, v_payment_method_id,
    'online_order_manual_payment:' || p_order_id::text,
    v_invoice.total, p_payment_date, v_reference,
    'Confirmación manual de pago - Pedido online #' || v_order.order_number
  ) returning id into v_payment_id;

  select operation.id into v_payment_operation_id
    from public.inventory_accounting_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key =
           'sales_payment:' || v_payment_id::text
           || ':insert:online_order_manual_payment:' || p_order_id::text
     and operation.document_type = 'sales_payment'
     and operation.document_id = v_payment_id
     and operation.action = 'insert'
     and operation.outcome = 'completed';

  if v_payment_operation_id is null then
    raise exception 'Completed payment trace missing for online-order payment confirmation %',
      p_order_id
      using errcode = 'data_exception';
  end if;

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'online_order', true);
  perform set_config('app.inventory_source_document_id', p_order_id::text, true);
  perform set_config('app.inventory_source_channel', 'online_sale_manual_payment', true);

  update public.online_orders
     set payment_status = 'paid',
         paid_at = p_payment_date,
         payment_reference = v_reference,
         manual_payment_id = v_payment_id,
         payment_confirmation_operation_id = v_operation_id,
         updated_at = clock_timestamp()
   where id = p_order_id and tenant_id = v_tenant_id;

  update public.inventory_accounting_operations
     set after_snapshot = jsonb_build_object(
           'order', (select to_jsonb(current_order) from public.online_orders current_order where current_order.id = p_order_id),
           'invoice', (select public.inventory_trace_document_snapshot(to_jsonb(current_invoice)) from public.sales_invoices current_invoice where current_invoice.id = v_invoice.id),
           'payment', (select public.inventory_trace_payment_snapshot(to_jsonb(current_payment)) from public.sales_payments current_payment where current_payment.id = v_payment_id)
         ),
         context = context || jsonb_build_object(
           'invoice_operation_id', v_invoice_operation_id,
           'payment_operation_id', v_payment_operation_id,
           'payment_id', v_payment_id
         )
   where id = v_operation_id and tenant_id = v_tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'sales_invoice', v_invoice.id,
    jsonb_build_object(
      'child_invoice_operation_id', v_invoice_operation_id,
      'stock_owner', 'sales_invoice',
      'stock_applied_once', true
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'journal_posted', 'completed', 'sales_payment', v_payment_id,
    jsonb_build_object(
      'child_payment_operation_id', v_payment_operation_id,
      'payment_reference', v_reference,
      'amount', v_invoice.total
    )
  );

  perform public.complete_inventory_accounting_operation(
    v_operation_id, v_tenant_id,
    jsonb_build_object(
      'order_id', p_order_id,
      'invoice_id', v_invoice.id,
      'payment_id', v_payment_id,
      'invoice_operation_id', v_invoice_operation_id,
      'payment_operation_id', v_payment_operation_id,
      'amount', v_invoice.total
    )
  );

  return v_payment_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.renew_online_order_inventory_reservations(p_order_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_order public.online_orders%rowtype;
  v_reservation public.online_order_inventory_reservations%rowtype;
  v_deadline timestamptz;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Reservation renewal is service-role only'
      using errcode = '42501';
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
   for update;
  if not found then
    raise exception 'Online order not found' using errcode = '23503';
  end if;
  if v_order.status in ('cancelled', 'delivered')
     or v_order.payment_status in ('paid', 'refunded') then
    raise exception 'Order is not eligible for inventory reservation renewal'
      using errcode = '23514';
  end if;

  perform public.ensure_online_order_inventory_reservations(
    v_order.id,
    'payment_preference'
  );
  v_deadline := clock_timestamp()
    + public.online_order_inventory_reservation_ttl(
        v_order.tenant_id,
        v_order.payment_method
      );

  for v_reservation in
    update public.online_order_inventory_reservations reservation
       set expires_at = v_deadline,
           version = reservation.version + 1,
           updated_at = clock_timestamp()
     where reservation.tenant_id = v_order.tenant_id
       and reservation.order_id = v_order.id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
     returning reservation.*
  loop
    perform public.append_online_inventory_reservation_event(
      v_reservation,
      're_reserved',
      'active',
      'active',
      'payment_preference',
      'reservation-renew:' || v_reservation.id::text || ':'
        || v_reservation.version::text,
      jsonb_build_object('expires_at', v_reservation.expires_at)
    );
  end loop;

  if not exists (
    select 1
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = v_order.tenant_id
       and reservation.order_id = v_order.id
       and reservation.state = 'active'
       and reservation.expires_at = v_deadline
  ) and exists (
    select 1
      from public.online_order_items item
      join public.products product
        on product.id = item.product_id
       and product.tenant_id = item.tenant_id
     where item.tenant_id = v_order.tenant_id
       and item.order_id = v_order.id
       and not coalesce(item.is_service, product.is_service, false)
       and coalesce(item.product_type, product.product_type) <> 'service'
       and coalesce(item.purchase_treatment, product.purchase_treatment, 'inventory')
             <> 'workshop_consumable'
       and coalesce(product.track_stock, true)
       -- Lo que viene a pedido se aparta al llegar (20261103010000).
       and not (item.fulfillment = 'on_order' and item.arrived_at is null)
  ) then
    raise exception 'Tracked order has no active inventory reservation'
      using errcode = '23514';
  end if;

  return case
    when exists (
      select 1
        from public.online_order_inventory_reservations reservation
       where reservation.tenant_id = v_order.tenant_id
         and reservation.order_id = v_order.id
         and reservation.state = 'active'
    ) then v_deadline
    else null
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.enqueue_transactional_email_from_order_event_id(p_event_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_event public.online_order_events%rowtype;
  v_order public.online_orders%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_message_kind text;
  v_subject text;
  v_recipient text;
  v_source_event_key text;
  v_idempotency_key text;
  v_delivery_mode text := 'dry_run';
  v_state text := 'pending';
  v_suppression_reason text;
  v_shipment public.online_order_shipments%rowtype;
  v_payload jsonb;
  v_outbox_id uuid;
begin
  select * into v_event
  from public.online_order_events
  where id = p_event_id;

  if not found or not coalesce(v_event.changed, false) then
    return null;
  end if;

  select * into v_order
  from public.online_orders
  where id = v_event.order_id
    and tenant_id = v_event.tenant_id;

  if not found then
    raise exception 'Online order event % has no matching order', p_event_id;
  end if;

  v_message_kind := case
    when v_event.event_type = 'order_created' then 'order_received'
    when v_event.event_type = 'payment_transition'
      and v_event.to_payment_status = 'paid'
      and v_order.payment_status = 'paid' then 'payment_confirmed'
    when v_event.event_type = 'payment_transition'
      and v_event.to_payment_status = 'refunded'
      and v_order.payment_status = 'refunded'
      and v_order.refunded_at is not null
      and coalesce(v_order.refund_amount, 0) > 0 then 'refund_completed'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'processing'
      and v_order.status = 'processing' then 'processing'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'ready_for_pickup'
      and v_order.status = 'ready_for_pickup' then 'ready_for_pickup'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'shipped'
      and v_order.status = 'shipped' then 'shipped'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'delivered'
      and v_order.status = 'delivered' then 'delivered'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'cancelled'
      and v_order.status = 'cancelled' then 'cancelled'
    else null
  end;

  -- There are intentionally no automatic payment_voucher_available or
  -- tax_document_issued branches. A Mercado Pago status is payment evidence,
  -- not by itself an immutable official voucher artifact, and internal
  -- sales_invoices are not Chilean DTE evidence.
  if v_message_kind is null then
    return null;
  end if;

  -- El cliente de una cotización eligió por dónde le avisamos: si no eligió
  -- correo, su pedido no le manda los correos de avance. Cancelación y
  -- reembolso salen igual: son su plata (20261103010000).
  if v_message_kind not in ('cancelled', 'refund_completed') and exists (
    select 1
      from public.customer_quotes q
     where q.online_order_id = v_order.id
       and q.tenant_id = v_order.tenant_id
       and not q.notify_email
  ) then
    return null;
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  if v_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return null;
  end if;

  select * into v_tenant
  from public.tenants
  where id = v_order.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = v_order.tenant_id;

  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  if v_message_kind = 'shipped' then
    select shipment.* into v_shipment
      from public.online_order_shipments shipment
     where shipment.tenant_id = v_order.tenant_id
       and shipment.order_id = v_order.id
     order by shipment.created_at desc
     limit 1;
  end if;

  v_subject := public.transactional_email_subject(v_message_kind, v_order.order_number);
  v_payload := public.transactional_email_render_payload(v_order, v_message_kind, v_shipment);

  v_source_event_key := 'online_order_event:' || v_event.id::text;
  v_idempotency_key := 'txn-email:v1:' || encode(extensions.digest(
    convert_to(
      v_event.tenant_id::text || ':' || v_event.order_id::text || ':' ||
      v_source_event_key || ':' || v_message_kind || ':' || v_recipient,
      'UTF8'
    ),
    'sha256'
  ), 'hex');

  select suppression.reason into v_suppression_reason
  from public.transactional_email_suppressions suppression
  where suppression.tenant_id = v_event.tenant_id
    and suppression.email_sha256 = encode(
      extensions.digest(convert_to(v_recipient, 'UTF8'), 'sha256'),
      'hex'
    )
    and suppression.lifted_at is null
  order by suppression.suppressed_at desc
  limit 1;

  if v_suppression_reason is not null then
    v_state := 'suppressed';
  end if;

  insert into public.transactional_email_outbox (
    tenant_id,
    order_id,
    order_event_id,
    source_event_key,
    message_kind,
    template_key,
    template_version,
    recipient_email,
    recipient_name,
    sender_name,
    sender_email,
    reply_to_email,
    subject,
    render_payload,
    idempotency_key,
    delivery_mode,
    state,
    suppression_reason
  ) values (
    v_event.tenant_id,
    v_event.order_id,
    v_event.id,
    v_source_event_key,
    v_message_kind,
    v_message_kind,
    1,
    v_recipient,
    nullif(btrim(v_order.customer_name), ''),
    nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    nullif(lower(btrim(v_settings.from_email)), ''),
    nullif(lower(btrim(v_settings.reply_to_email)), ''),
    v_subject,
    v_payload,
    v_idempotency_key,
    v_delivery_mode,
    v_state,
    v_suppression_reason
  )
  on conflict (idempotency_key) do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select id into v_outbox_id
    from public.transactional_email_outbox
    where idempotency_key = v_idempotency_key;
  end if;

  return v_outbox_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_quote_events_enqueue_messages()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.event_type = 'requested' and new.actor_kind = 'customer' then
    perform public.customer_quote_enqueue_message_internal(new.quote_id, 'received', null);
  elsif new.event_type = 'offer_sent' then
    perform public.customer_quote_enqueue_message_internal(new.quote_id, 'offer', new.offer_id);
  elsif new.event_type = 'accepted' and not exists (
    -- Aceptada con su pedido: el correo del pedido es el aviso, no dos
    -- correos al mismo tiempo (20261103010000).
    select 1 from public.customer_quotes q
     where q.id = new.quote_id and q.online_order_id is not null
  ) then
    perform public.customer_quote_enqueue_message_internal(new.quote_id, 'accepted', new.offer_id);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_quote_enqueue_message_internal(p_quote_id uuid, p_kind text, p_offer_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_quote public.customer_quotes%rowtype;
  v_count integer := 0;
  v_id uuid;
  v_channels text[];
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if not found then
    return 0;
  end if;
  v_channels := case
    -- Los hitos del pedido van por WhatsApp sólo a quien lo eligió; por correo
    -- los manda el pedido mismo (20261103010000).
    when p_kind in ('order_paid', 'order_ready', 'order_shipped') then
      case when v_quote.notify_whatsapp and v_quote.customer_phone is not null
           then array['whatsapp'] else array[]::text[] end
    when p_kind in ('offer', 'reminder') then array_remove(array[
      case when v_quote.notify_whatsapp and v_quote.customer_phone is not null then 'whatsapp' end,
      case when v_quote.notify_email and v_quote.customer_email is not null then 'email' end
    ], null)
    -- «Recibimos» y «aceptada» sólo van por correo: a quien no ha escrito por
    -- WhatsApp no se le puede escribir primero sin plantilla de Meta.
    when v_quote.notify_email and v_quote.customer_email is not null then array['email']
    else array[]::text[]
  end;

  for i in 1 .. coalesce(array_length(v_channels, 1), 0) loop
    insert into public.customer_quote_messages (
      tenant_id, quote_id, offer_id, kind, channel, recipient, state
    ) values (
      v_quote.tenant_id, v_quote.id, p_offer_id, p_kind, v_channels[i],
      case v_channels[i] when 'email' then v_quote.customer_email else v_quote.customer_phone end,
      case v_channels[i] when 'email' then 'pending' else 'needs_staff' end
    )
    on conflict on constraint customer_quote_messages_once do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      perform public.customer_quote_log_internal(
        v_quote.id, 'message_queued', 'system', null, 'system', p_offer_id, null,
        jsonb_build_object('kind', p_kind, 'channel', v_channels[i], 'message_id', v_id)
      );
      if v_channels[i] = 'whatsapp' then
        perform public.customer_quote_notify_internal(
          v_quote.id,
          'customer_quote_whatsapp_pending',
          case p_kind
            when 'reminder' then 'Recordar la oferta por WhatsApp'
            when 'order_paid' then 'Avisar el pago por WhatsApp'
            when 'order_ready' then 'Avisar por WhatsApp que está listo'
            when 'order_shipped' then 'Avisar el despacho por WhatsApp'
            else 'Enviar la oferta por WhatsApp'
          end,
          'customer_quote_message',
          v_id,
          'warning'
        );
      end if;
    end if;
    v_id := null;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.respond_public_customer_quote_v1(p_token text, p_response jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_offer public.customer_quote_offers%rowtype;
  v_action text := p_response ->> 'action';
  v_key text := lower(btrim(coalesce(p_response ->> 'operation_key', '')));
  v_note text := nullif(btrim(coalesce(p_response ->> 'note', '')), '');
  v_quantities jsonb;
  v_event public.customer_quote_events%rowtype;
begin
  if p_response is null or jsonb_typeof(p_response) <> 'object'
     or v_action not in ('accept', 'request_changes', 'reject') then
    raise exception 'Invalid quote response' using errcode = '22023';
  end if;
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random operation key is required' using errcode = '22023';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'quote_note_too_long' using errcode = '22023';
  end if;
  -- Aceptar crea el pedido y pide entrega y pago: es su propio comando,
  -- accept_public_customer_quote_v1 (20261103010000).
  if v_action = 'accept' then
    raise exception 'quote_accept_requires_checkout' using errcode = '22023';
  end if;

  v_access := public.customer_quote_token_internal(p_token, 'respond_quote');
  if v_access.id is null then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;

  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id
   for update;

  -- La misma respuesta repetida devuelve lo mismo.
  select * into v_event from public.customer_quote_events e
   where e.quote_id = v_quote.id and e.operation_key = v_key;
  if found then
    return public.customer_quote_public_projection_internal(v_quote.id)
      || jsonb_build_object('replay', true);
  end if;

  if v_quote.status <> 'offered' then
    raise exception 'quote_not_open' using errcode = '55000', detail = v_quote.status;
  end if;
  select * into v_offer from public.customer_quote_offers where id = v_quote.current_offer_id for update;
  if (p_response ->> 'offer_id') is not null and (p_response ->> 'offer_id')::uuid is distinct from v_offer.id then
    raise exception 'quote_offer_outdated' using errcode = '40001';
  end if;
  if v_offer.valid_until <= clock_timestamp() then
    raise exception 'quote_offer_expired' using errcode = '55000';
  end if;

  if v_action = 'reject' then
    update public.customer_quote_offers set status = 'rejected', responded_at = clock_timestamp()
     where id = v_offer.id;
    update public.customer_quotes
       set status = 'rejected', rejected_at = clock_timestamp(), closed_reason = v_note,
           updated_at = clock_timestamp(), version = version + 1
     where id = v_quote.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'rejected', 'customer', null, 'web', v_offer.id, v_key,
      jsonb_build_object('note', v_note)
    );
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_rejected', 'Cotización rechazada', 'customer_quote_offer', v_offer.id, 'warning'
    );
  else
    -- Pedir cambios: cantidades nuevas por número de línea (0 = quitarla).
    select coalesce(jsonb_object_agg(x ->> 'line_no', greatest(0, least(99, (x ->> 'quantity')::integer))), '{}'::jsonb)
      into v_quantities
      from jsonb_array_elements(coalesce(p_response -> 'lines', '[]'::jsonb)) x
     where (x ->> 'line_no') ~ '^[0-9]{1,2}$' and (x ->> 'quantity') ~ '^[0-9]{1,2}$';
    if v_note is null and v_quantities = '{}'::jsonb then
      raise exception 'quote_changes_required' using errcode = '22023';
    end if;
    update public.customer_quote_offers set status = 'superseded', responded_at = clock_timestamp()
     where id = v_offer.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'changes_requested', 'customer', null, 'web', v_offer.id, v_key,
      jsonb_build_object('note', v_note, 'quantities', v_quantities)
    );
    perform public.customer_quote_prepare_offer_internal(v_quote.id, 'customer', null, v_offer.id, v_quantities);
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_changes_requested', 'Cliente pidió cambios', 'customer_quote_offer', v_offer.id, 'info'
    );
  end if;

  return public.customer_quote_public_projection_internal(v_quote.id) || jsonb_build_object('replay', false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_quote_public_projection_internal(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (
    select * from public.customer_quotes where id = p_quote_id
  ), offer as (
    select o.* from public.customer_quote_offers o, q
     where o.id = q.current_offer_id
  )
  select jsonb_build_object(
    'quote', (select jsonb_strip_nulls(jsonb_build_object(
      'number', q.quote_number,
      'status', q.status,
      'customerName', q.customer_name,
      'notifyEmail', q.notify_email,
      'notifyWhatsapp', q.notify_whatsapp,
      -- Sólo si la cuenta tiene cada dato, nunca el dato: el enlace se puede
      -- reenviar.
      'canEmail', q.customer_email is not null,
      'canWhatsapp', q.customer_phone is not null,
      'requestedAt', q.requested_at,
      'offeredAt', q.offered_at,
      'expiresAt', q.expires_at,
      'acceptedAt', q.accepted_at,
      'rejectedAt', q.rejected_at,
      'expiredAt', q.expired_at,
      'cancelledAt', q.cancelled_at
    )) from q),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineNo', l.line_no, 'name', l.product_name, 'sku', l.product_sku,
        'quantity', l.quantity, 'kind', l.kind_at_request
      ) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = p_quote_id
    ), '[]'::jsonb),
    'offer', (select jsonb_strip_nulls(jsonb_build_object(
      'id', offer.id,
      'number', offer.offer_no,
      'status', offer.status,
      'sentAt', offer.sent_at,
      'validUntil', offer.valid_until,
      'subtotal', offer.subtotal,
      'taxAmount', offer.tax_amount,
      'total', offer.total,
      'notes', offer.notes_to_customer,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', ol.id, 'lineNo', ol.line_no, 'name', ol.product_name, 'sku', ol.product_sku,
          'quantityRequested', ol.quantity_requested, 'quantity', ol.quantity_offered,
          'availability', ol.availability, 'unitPrice', ol.unit_price,
          'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
          'leadDaysMin', ol.lead_days_min, 'leadDaysMax', ol.lead_days_max,
          'note', ol.customer_note
        )) order by ol.line_no)
          from public.customer_quote_offer_lines ol where ol.offer_id = offer.id
      ), '[]'::jsonb)
    )) from offer where offer.status <> 'draft'),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.event_type, 'at', e.occurred_at) order by e.id)
        from public.customer_quote_events e
       where e.quote_id = p_quote_id
         and e.event_type in (
           'requested', 'offer_sent', 'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled',
           'order_paid', 'order_sale_issued', 'order_ready', 'order_shipped', 'order_delivered', 'order_cancelled'
         )
    ), '[]'::jsonb),
    -- El pedido que nació al aceptar: estado, entrega y qué viene a pedido.
    -- Sin su acceso: la página lo pide con el enlace (20261103010000).
    'order', (select jsonb_strip_nulls(jsonb_build_object(
      'number', o.order_number,
      'status', o.status,
      'paymentStatus', o.payment_status,
      'paymentMethod', o.payment_method,
      'deliveryType', o.delivery_type,
      'productsTotal', o.subtotal + o.tax_amount,
      'shippingCost', o.shipping_cost,
      'total', o.total,
      'waiting', public.customer_quote_order_waiting_internal(o.id),
      'readyForPickupAt', o.ready_for_pickup_at,
      'shippedAt', o.shipped_at,
      'deliveredAt', o.delivered_at,
      'cancelledAt', o.cancelled_at,
      'trackingCarrier', o.shipping_carrier,
      'trackingNumber', o.tracking_number,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'name', i.product_name,
          'quantity', i.quantity,
          'onOrder', i.fulfillment = 'on_order',
          'arrived', case when i.fulfillment = 'on_order' then i.arrived_at is not null end,
          'leadDaysMin', i.lead_days_min,
          'leadDaysMax', i.lead_days_max
        )) order by i.created_at, i.id)
          from public.online_order_items i
         where i.order_id = o.id
      ), '[]'::jsonb)
    ))
      from public.online_orders o, q
     where o.id = q.online_order_id and o.tenant_id = q.tenant_id)
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_public_customer_quote_v1(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_can_respond boolean;
  v_can_answer boolean;
begin
  v_access := public.customer_quote_token_internal(p_token, 'view_quote');
  if v_access.id is null then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id;
  if not found then
    return null;
  end if;

  -- La primera vista de una oferta enviada queda en la historia.
  if v_quote.status = 'offered' and not exists (
    select 1 from public.customer_quote_events e
     where e.quote_id = v_quote.id and e.event_type = 'viewed' and e.offer_id = v_quote.current_offer_id
  ) then
    perform public.customer_quote_log_internal(
      v_quote.id, 'viewed', 'customer', null, 'web', v_quote.current_offer_id
    );
  end if;

  v_can_answer := v_access.scopes @> array['respond_quote']::text[];
  v_can_respond := v_quote.status = 'offered'
    and v_can_answer
    and v_quote.expires_at > clock_timestamp();

  return public.customer_quote_public_projection_internal(v_quote.id)
    || jsonb_build_object('actions', jsonb_build_object(
      'accept', v_can_respond,
      'requestChanges', v_can_respond,
      'reject', v_can_respond,
      'changeNotify', v_can_answer and v_quote.status in ('confirming', 'offered', 'accepted'),
      'openOrder', v_can_answer and v_quote.online_order_id is not null,
      'onOrderPrepayPercent', (public.customer_quote_settings_internal(v_quote.tenant_id)).on_order_prepay_percent
    ));
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_online_order_by_access_token(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  access_row public.online_order_access_tokens%rowtype;
  order_row public.online_orders%rowtype;
  order_items jsonb;
  storefront_identity jsonb;
begin
  if length(coalesce(p_token, '')) < 40 or length(p_token) > 128 then
    return null;
  end if;

  select access.*
  into access_row
  from public.online_order_access_tokens access
  where access.token_sha256 = encode(
    extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'),
    'hex'
  )
    and access.revoked_at is null
    and access.expires_at > clock_timestamp()
    and access.scopes @> array['view_order']::text[]
  for update;

  if not found then
    return null;
  end if;

  select customer_order.*
  into order_row
  from public.online_orders customer_order
  where customer_order.id = access_row.order_id
    and customer_order.tenant_id = access_row.tenant_id;

  if not found then
    return null;
  end if;

  update public.online_order_access_tokens access
  set last_used_at = clock_timestamp(),
      use_count = access.use_count + 1
  where access.id = access_row.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'name', item.product_name,
    'sku', item.product_sku,
    'quantity', item.quantity,
    'unitPrice', item.unit_price,
    'subtotal', item.subtotal,
    'taxRate', case when item.tax_rate = 0.19 then 19 else item.tax_rate end,
    -- Lo que viene a pedido de una cotización (20261103010000).
    'onOrder', item.fulfillment = 'on_order',
    'arrived', item.fulfillment = 'on_order' and item.arrived_at is not null,
    'leadDaysMin', item.lead_days_min,
    'leadDaysMax', item.lead_days_max
  ) order by item.created_at, item.id), '[]'::jsonb)
  into order_items
  from public.online_order_items item
  where item.order_id = order_row.id
    and item.tenant_id = order_row.tenant_id;

  select snapshot.identity_snapshot
  into storefront_identity
  from public.online_order_storefront_snapshots snapshot
  where snapshot.order_id = order_row.id
    and snapshot.tenant_id = order_row.tenant_id;

  return jsonb_build_object(
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', order_row.id,
      'number', order_row.order_number,
      'status', order_row.status,
      'paymentStatus', order_row.payment_status,
      'paymentMethod', order_row.payment_method,
      'deliveryType', order_row.delivery_type,
      'createdAt', order_row.created_at,
      'updatedAt', order_row.updated_at,
      'readyForPickupAt', order_row.ready_for_pickup_at,
      'shippedAt', order_row.shipped_at,
      'deliveredAt', order_row.delivered_at,
      'cancelledAt', order_row.cancelled_at,
      'trackingCarrier', order_row.shipping_carrier,
      'trackingNumber', order_row.tracking_number,
      'trackingUrl', case
        when order_row.tracking_url ~* '^https://[^[:space:]]+$'
          then order_row.tracking_url
        else null
      end,
      'subtotal', order_row.subtotal,
      'taxAmount', order_row.tax_amount,
      'shippingCost', order_row.shipping_cost,
      'discountAmount', order_row.discount_amount,
      'total', order_row.total,
      'quoteNumber', (
        select q.quote_number
          from public.customer_quotes q
         where q.online_order_id = order_row.id
           and q.tenant_id = order_row.tenant_id
      ),
      'waitingOnOrder', case
        when public.customer_quote_order_waiting_internal(order_row.id) then true
      end
    )),
    'items', order_items,
    'storefront', coalesce(
      storefront_identity,
      jsonb_build_object(
        'schemaVersion', 1,
        'displayName', 'Tienda'
      )
    ),
    'access', jsonb_build_object(
      'scopes', access_row.scopes,
      'expiresAt', access_row.expires_at
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_quote_detail_v1(p_tenant_id uuid, p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_quote public.customer_quotes%rowtype;
  v_draft uuid;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  select o.id into v_draft from public.customer_quote_offers o
   where o.quote_id = p_quote_id and o.status = 'draft';

  return jsonb_build_object(
    'quote', to_jsonb(v_quote) - 'request_idempotency_key',
    'settings', to_jsonb(public.customer_quote_settings_internal(p_tenant_id)),
    'requested', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no)
                             from public.customer_quote_lines l where l.quote_id = p_quote_id), '[]'::jsonb),
    'offers', coalesce((
      select jsonb_agg(to_jsonb(o) || jsonb_build_object(
        'lines', coalesce((
          select jsonb_agg(to_jsonb(ol) || jsonb_build_object(
            'supplier_name', s.name,
            'stock_now', p.inventory_qty
          ) order by ol.line_no)
            from public.customer_quote_offer_lines ol
            left join public.suppliers s on s.id = ol.supplier_id
            left join public.products p on p.id = ol.product_id
           where ol.offer_id = o.id
        ), '[]'::jsonb)
      ) order by o.offer_no desc)
        from public.customer_quote_offers o
       where o.quote_id = p_quote_id and o.status <> 'cancelled'
    ), '[]'::jsonb),
    'draftOfferId', v_draft,
    'tasks', coalesce((
      select jsonb_agg(to_jsonb(t) || jsonb_build_object(
        'supplier_name', s.name,
        'sales_rep_name', s.sales_rep_name,
        'sales_rep_phone', s.sales_rep_phone
      ) order by t.created_at)
        from public.customer_quote_supplier_tasks t
        left join public.suppliers s on s.id = t.supplier_id
       where t.quote_id = p_quote_id and t.status <> 'cancelled'
    ), '[]'::jsonb),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'kind', m.kind, 'channel', m.channel, 'recipient', m.recipient,
        'state', m.state, 'sent_at', m.sent_at, 'created_at', m.created_at,
        'offer_id', m.offer_id, 'last_error', m.last_error
      ) order by m.created_at)
        from public.customer_quote_messages m where m.quote_id = p_quote_id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.id)
        from public.customer_quote_events e where e.quote_id = p_quote_id
    ), '[]'::jsonb),
    -- El pedido que nació al aceptar, con lo que viene a pedido y el pedido a
    -- cada proveedor (20261103010000).
    'order', (
      select jsonb_build_object(
        'id', o.id,
        'number', o.order_number,
        'status', o.status,
        'payment_status', o.payment_status,
        'payment_method', o.payment_method,
        'delivery_type', o.delivery_type,
        'total', o.total,
        'shipping_cost', o.shipping_cost,
        'paid_at', o.paid_at,
        'tracking_number', o.tracking_number,
        'shipping_carrier', o.shipping_carrier,
        'sales_invoice_id', o.sales_invoice_id,
        'invoice_number', (
          select si.invoice_number from public.sales_invoices si
           where si.id = o.sales_invoice_id and si.tenant_id = o.tenant_id
        ),
        'waiting', public.customer_quote_order_waiting_internal(o.id),
        'items', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', i.id,
            'product_id', i.product_id,
            'product_name', i.product_name,
            'product_sku', i.product_sku,
            'quantity', i.quantity,
            'fulfillment', i.fulfillment,
            'arrived_at', i.arrived_at,
            'supplier_id', i.on_order_supplier_id,
            'supplier_name', s.name,
            'lead_days_min', i.lead_days_min,
            'lead_days_max', i.lead_days_max,
            'stock_now', p.stock_quantity
          ) order by i.created_at, i.id)
            from public.online_order_items i
            left join public.suppliers s on s.id = i.on_order_supplier_id and s.tenant_id = i.tenant_id
            left join public.products p on p.id = i.product_id and p.tenant_id = i.tenant_id
           where i.order_id = o.id and i.tenant_id = o.tenant_id
        ), '[]'::jsonb),
        'purchases', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', po.id,
            'supplier_id', po.supplier_id,
            'supplier_name', s.name,
            'sales_rep_name', s.sales_rep_name,
            'sales_rep_phone', s.sales_rep_phone,
            'purchase_invoice_id', pi.id,
            'number', pi.invoice_number,
            'status', pi.status,
            'total', pi.total,
            'created_at', po.created_at
          ) order by po.created_at)
            from public.customer_quote_purchase_orders po
            left join public.suppliers s on s.id = po.supplier_id and s.tenant_id = po.tenant_id
            left join public.purchase_invoices pi on pi.id = po.purchase_invoice_id and pi.tenant_id = po.tenant_id
           where po.online_order_id = o.id and po.tenant_id = o.tenant_id
        ), '[]'::jsonb)
      )
        from public.online_orders o
       where o.id = v_quote.online_order_id and o.tenant_id = p_tenant_id
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_my_customer_quotes_v1(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(mine.item order by mine.requested_at desc), '[]'::jsonb)
    from (
      select q.requested_at, jsonb_strip_nulls(jsonb_build_object(
        'id', q.id,
        'number', q.quote_number,
        'status', q.status,
        'requestedAt', q.requested_at,
        'expiresAt', case when q.status = 'offered' then q.expires_at end,
        'lines', (select count(*) from public.customer_quote_lines l where l.quote_id = q.id),
        'total', (select o.total from public.customer_quote_offers o
                   where o.id = q.current_offer_id and o.status <> 'draft'),
        'notifyEmail', q.notify_email,
        'notifyWhatsapp', q.notify_whatsapp,
        'orderNumber', (select o.order_number from public.online_orders o
                         where o.id = q.online_order_id and o.tenant_id = q.tenant_id),
        'orderWaiting', case when q.online_order_id is not null
                              and public.customer_quote_order_waiting_internal(q.online_order_id)
                             then true end
      )) as item
        from public.customer_quotes q
        join public.customers c on c.id = q.customer_id and c.tenant_id = q.tenant_id
       where q.tenant_id = p_tenant_id
         and auth.uid() is not null
         and c.auth_user_id = auth.uid()
       order by q.requested_at desc
       limit 50
    ) mine;
$function$;

CREATE OR REPLACE FUNCTION public.customer_quote_inbox_v1(p_tenant_id uuid, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  return (
    with web as (
      select q.id, q.quote_number as number, q.status, q.source,
             q.customer_name as "customerName",
             q.notify_email as "notifyEmail", q.notify_whatsapp as "notifyWhatsapp",
             q.requested_at as "requestedAt", q.updated_at as "updatedAt",
             q.expires_at as "expiresAt",
             (select count(*) from public.customer_quote_lines l where l.quote_id = q.id) as lines,
             (select o.total from public.customer_quote_offers o where o.id = q.current_offer_id) as total,
             (select count(*) from public.customer_quote_supplier_tasks t
               where t.quote_id = q.id and t.status = 'open') as "openTasks",
             (select min(t.due_at) from public.customer_quote_supplier_tasks t
               where t.quote_id = q.id and t.status = 'open') as "nextDueAt",
             false as converted,
             (select o.order_number from public.online_orders o
               where o.id = q.online_order_id and o.tenant_id = q.tenant_id) as "orderNumber",
             case when q.online_order_id is not null
                  then public.customer_quote_order_waiting_internal(q.online_order_id) end as "orderWaiting"
        from public.customer_quotes q
       where q.tenant_id = p_tenant_id
    ),
    workshop_jobs as (
      select j.id, j.tenant_id, j.customer_id, j.job_number, j.workflow_kind,
             j.quotation_status, j.quotation_valid_until, j.total_cost,
             j.created_at, j.updated_at,
             (select count(*) from public.mechanic_job_items i
               where i.job_id = j.id and i.tenant_id = j.tenant_id) as item_count
        from public.mechanic_jobs j
       where j.tenant_id = p_tenant_id
         and j.deleted_at is null
         and j.archive_reason is null
         and (
           (j.workflow_kind = 'quotation' and j.intake_kind is distinct from 'bike')
           or exists (
             select 1 from public.mechanic_job_mode_events e
              where e.tenant_id = j.tenant_id and e.job_id = j.id
                and e.event_type = 'converted_to_billable'
                and e.from_workflow_kind = 'quotation'
                and e.from_intake_kind is distinct from 'bike'
           )
         )
    ),
    workshop as (
      select w.id, w.job_number as number,
             case
               when w.workflow_kind is distinct from 'quotation' then 'accepted'
               when w.quotation_status = 'approved' then 'accepted'
               when w.quotation_status = 'rejected' then 'rejected'
               when w.quotation_status = 'expired' then 'expired'
               when w.quotation_valid_until < now() then 'expired'
               when w.item_count = 0 then 'confirming'
               else 'offered'
             end as status,
             'workshop'::text as source,
             coalesce(nullif(btrim(c.name), ''), 'Sin cliente') as "customerName",
             null::boolean as "notifyEmail", null::boolean as "notifyWhatsapp",
             w.created_at as "requestedAt", w.updated_at as "updatedAt",
             case when w.workflow_kind = 'quotation' and w.quotation_status = 'pending'
                  then w.quotation_valid_until end as "expiresAt",
             w.item_count as lines,
             w.total_cost as total,
             0::bigint as "openTasks",
             null::timestamptz as "nextDueAt",
             (w.workflow_kind is distinct from 'quotation') as converted,
             null::text as "orderNumber",
             null::boolean as "orderWaiting"
        from workshop_jobs w
        left join public.customers c on c.id = w.customer_id and c.tenant_id = w.tenant_id
    ),
    all_quotes as (
      select * from web
      union all
      select * from workshop
    )
    select jsonb_build_object(
      'counts', (
        select coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb)
          from (select a.status, count(*) as n from all_quotes a group by a.status) s
      ),
      'quotes', coalesce((
        select jsonb_agg(to_jsonb(r) order by r."updatedAt" desc)
          from (
            select a.* from all_quotes a
             where p_status is null or a.status = p_status
             order by a."updatedAt" desc
             limit greatest(1, least(coalesce(p_limit, 50), 200))
            offset greatest(0, coalesce(p_offset, 0))
          ) r
      ), '[]'::jsonb)
    )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. La revisión de llegadas, cada 10 minutos.
-- ---------------------------------------------------------------------------

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; quote order arrivals were not scheduled';
    return;
  end if;
  for v_job in select jobid from cron.job where jobname = 'vinabike_customer_quote_order_arrivals' loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'vinabike_customer_quote_order_arrivals',
    '3,13,23,33,43,53 * * * *',
    $job$select public.customer_quote_orders_check_arrivals_v1()$job$
  );
end;
$$;

commit;
