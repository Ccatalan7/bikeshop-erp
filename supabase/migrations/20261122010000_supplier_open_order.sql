-- Un solo pedido abierto por proveedor, que sale de verdad (2026-11-22).
--
-- El dueño, sobre las ventas a pedido: «supongamos que llega ya un cliente un
-- día compró una rodillera… pasa una hora y otro cliente compra una
-- horquilla… ¿Van a ser tres documentos distintos y con botones para enviar
-- tres cosas en un día a un proveedor? ¿O existe una ventana razonable para
-- acumular pedidos y se genera un solo documento?» (2026-11-21).
--
-- Hasta hoy cada venta pagada abría su propio borrador de compra (PED) por
-- proveedor, «Enviar al proveedor» fuera de las 24 h mandaba sólo el saludo y
-- lo dejaba «Enviada», y lo vendido se descontaba del stock del proveedor sólo
-- 2 días contados desde la venta. Desde esta migración:
--
-- * Cada venta pagada suma sus productos al pedido abierto del proveedor: el
--   borrador de compra que ya lleva ventas web y que nadie ha enviado. Una
--   línea por producto (las cantidades se suman), y la nota dice para qué
--   pedidos es. Dos pagos al mismo tiempo no abren dos pedidos (un candado por
--   proveedor). Lo que se pague después de enviarlo abre el siguiente.
-- * Una venta anulada saca sus productos del pedido abierto; si era la única,
--   el pedido se anula como antes. Lo ya enviado queda para que el equipo le
--   avise al proveedor.
-- * La base no deja sacar de un pedido abierto lo que pagó un cliente (un
--   guardado con el pedido abierto desde antes de una venta lo borraría sin
--   aviso), ni marcarlo «Enviada» sin el comando que compara lo que salió con
--   lo que dice el pedido.
-- * Lo vendido que no llega se descuenta del stock del proveedor mientras el
--   pedido no sale y hasta 2 días después de enviado.
-- * Lo que llega se reparte en el orden en que pagaron.

begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 1. Las líneas de un pedido: sumar o restar por producto.
-- ---------------------------------------------------------------------------

-- p_sign = 1 suma p_delta (una línea por producto, al final las nuevas);
-- p_sign = -1 resta y saca las líneas que quedan en cero. Cada línea guarda
-- su costo: lo que el equipo ya decidió no cambia al sumar otra venta.
create or replace function public.supplier_open_order_items_apply_internal(
  p_items jsonb,
  p_delta jsonb,
  p_sign integer
)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $function$
  with base as (
    select e.value as item, e.ordinality as ord
      from jsonb_array_elements(
        case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end
      ) with ordinality e
  ), ranked as (
    select b.item,
           b.ord,
           row_number() over (partition by b.item ->> 'product_id' order by b.ord) as nth
      from base b
  ), delta as (
    select d.value ->> 'product_id' as product_id,
           sum(coalesce((d.value ->> 'quantity')::numeric, 0)) as quantity,
           min(d.ordinality) as ord,
           (array_agg(d.value order by d.ordinality))[1] as item
      from jsonb_array_elements(
        case when jsonb_typeof(p_delta) = 'array' then p_delta else '[]'::jsonb end
      ) with ordinality d
     where d.value ->> 'product_id' is not null
     group by d.value ->> 'product_id'
  ), applied as (
    select case
             when r.nth = 1 and d.product_id is not null then
               jsonb_set(
                 r.item,
                 '{quantity}',
                 to_jsonb(coalesce((r.item ->> 'quantity')::numeric, 0) + p_sign * d.quantity)
               )
             else r.item
           end as item,
           r.ord
      from ranked r
      left join delta d on d.product_id = r.item ->> 'product_id'
    union all
    select jsonb_set(d.item, '{quantity}', to_jsonb(d.quantity)), 1000000 + d.ord
      from delta d
     where p_sign > 0
       and not exists (
         select 1 from base b where b.item ->> 'product_id' = d.product_id
       )
  )
  select coalesce(jsonb_agg(applied.item order by applied.ord), '[]'::jsonb)
    from applied
   where coalesce((applied.item ->> 'quantity')::numeric, 0) > 0;
$function$;

revoke all on function public.supplier_open_order_items_apply_internal(jsonb, jsonb, integer)
  from public, anon, authenticated;

-- «Para el pedido WEB-…» o «Para los pedidos WEB-…, WEB-… y WEB-…»: los
-- pedidos web vivos que lleva. Nombra pedidos, nunca clientes: el documento
-- también es el que ve el proveedor.
create or replace function public.supplier_open_order_note_internal(p_invoice_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with named as (
    select o.order_number
             || coalesce(' (cotización ' || q.quote_number || ')', '') as name,
           po.created_at,
           po.id
      from public.purchase_invoices pi
      join public.customer_quote_purchase_orders po
        on po.purchase_invoice_id = pi.id
       and po.tenant_id = pi.tenant_id
      join public.online_orders o
        on o.id = po.online_order_id
       and o.tenant_id = po.tenant_id
      left join public.customer_quotes q
        on q.id = po.quote_id
       and q.tenant_id = po.tenant_id
     where pi.id = p_invoice_id
       and o.status <> 'cancelled'
  ), listed as (
    select array_agg(named.name order by named.created_at, named.id) as names
      from named
  )
  select case
           when coalesce(cardinality(listed.names), 0) = 0 then null
           when cardinality(listed.names) = 1 then 'Para el pedido ' || listed.names[1] || '.'
           else 'Para los pedidos '
                  || array_to_string(listed.names[1:cardinality(listed.names) - 1], ', ')
                  || ' y ' || listed.names[cardinality(listed.names)] || '.'
         end
    from listed;
$function$;

revoke all on function public.supplier_open_order_note_internal(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Al pagar: sumar al pedido abierto del proveedor.
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_order_prepare_purchases_internal(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_has_quote boolean;
  v_group record;
  v_supplier public.suppliers%rowtype;
  v_open public.purchase_invoices%rowtype;
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
  v_has_quote := found;

  for v_group in
    select item.on_order_supplier_id as supplier_id,
           jsonb_agg(jsonb_build_object(
             'product_id', item.product_id,
             'product_name', item.product_name,
             'product_sku', item.product_sku,
             'quantity', item.quantity,
             'unit_cost', coalesce(line.unit_cost_net, item.unit_cost, product.cost, 0),
             'iva_rate', 0.19,
             'discount', 0,
             'description', null,
             'purchase_treatment', 'inventory',
             'created_at', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
           ) order by item.product_name) as items,
           sum(item.quantity * coalesce(line.unit_cost_net, item.unit_cost, product.cost, 0)) as net
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

    -- Un pedido a la vez por proveedor: dos pagos juntos no abren dos.
    perform pg_advisory_xact_lock(
      hashtextextended('supplier-open-order:' || v_order.tenant_id::text || ':' || v_supplier.id::text, 0)
    );

    -- El pedido abierto: el borrador que ya lleva una venta web viva y nadie
    -- envió.
    select pi.* into v_open
      from public.purchase_invoices pi
     where pi.tenant_id = v_order.tenant_id
       and pi.supplier_id = v_supplier.id
       and pi.status = 'draft'
       and exists (
         select 1
           from public.customer_quote_purchase_orders po
           join public.online_orders live
             on live.id = po.online_order_id
            and live.tenant_id = po.tenant_id
          where po.purchase_invoice_id = pi.id
            and po.tenant_id = pi.tenant_id
            and live.status <> 'cancelled'
       )
     order by pi.created_at, pi.id
     limit 1
     for update;

    if found then
      v_net := public.clp_round(coalesce(v_open.net_amount, v_open.subtotal, 0) + v_group.net);
      v_iva := public.clp_round(v_net * 0.19);
      update public.purchase_invoices
         set items = public.supplier_open_order_items_apply_internal(v_open.items, v_group.items, 1),
             subtotal = v_net,
             net_amount = v_net,
             iva_amount = v_iva,
             total = v_net + v_iva,
             updated_at = clock_timestamp()
       where id = v_open.id
         and tenant_id = v_order.tenant_id;
      v_invoice_id := v_open.id;
    else
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
        source_document_kind, items
      ) values (
        v_order.tenant_id, v_number, v_supplier.id, v_supplier.name, v_supplier.rut, clock_timestamp(),
        'draft', v_net, v_iva, v_net + v_iva, v_net, 'tax_included',
        'tax_invoice', v_group.items
      ) returning id into v_invoice_id;
    end if;

    insert into public.customer_quote_purchase_orders (
      tenant_id, quote_id, online_order_id, supplier_id, purchase_invoice_id
    ) values (
      v_order.tenant_id,
      case when v_has_quote then v_quote.id end,
      p_order_id,
      v_supplier.id,
      v_invoice_id
    );

    update public.purchase_invoices
       set notes = public.supplier_open_order_note_internal(v_invoice_id)
     where id = v_invoice_id
       and tenant_id = v_order.tenant_id;

    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.customer_quote_order_prepare_purchases_internal(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Una venta anulada sale del pedido abierto.
-- ---------------------------------------------------------------------------

-- Lo que la venta le pidió a cada proveedor y no llegó se resta del pedido
-- que nadie envió. Si era la única venta y no queda nada, el pedido se anula
-- (como antes); si quedan otras ventas, o líneas que el equipo sumó a mano, el
-- pedido sigue abierto sin ella. Lo enviado no se toca: el equipo le avisa al
-- proveedor (la anulación ya lo dice).
create or replace function public.supplier_open_order_release_order_internal(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order public.online_orders%rowtype;
  v_link record;
  v_invoice public.purchase_invoices%rowtype;
  v_delta jsonb;
  v_removed_net numeric;
  v_items jsonb;
  v_others integer;
  v_net numeric;
  v_iva numeric;
  v_released integer := 0;
  v_cancelled integer := 0;
begin
  select * into v_order from public.online_orders where id = p_order_id;
  if not found then
    return null;
  end if;

  for v_link in
    select po.id, po.supplier_id, po.purchase_invoice_id
      from public.customer_quote_purchase_orders po
     where po.online_order_id = p_order_id
       and po.tenant_id = v_order.tenant_id
       and po.purchase_invoice_id is not null
     order by po.created_at, po.id
  loop
    perform pg_advisory_xact_lock(
      hashtextextended('supplier-open-order:' || v_order.tenant_id::text || ':' || v_link.supplier_id::text, 0)
    );
    select * into v_invoice from public.purchase_invoices
     where id = v_link.purchase_invoice_id
       and tenant_id = v_order.tenant_id
     for update;
    if not found or v_invoice.status <> 'draft' then
      continue;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('product_id', i.product_id, 'quantity', i.quantity)), '[]'::jsonb)
      into v_delta
      from public.online_order_items i
     where i.order_id = p_order_id
       and i.tenant_id = v_order.tenant_id
       and i.fulfillment = 'on_order'
       and i.arrived_at is null
       and i.on_order_supplier_id = v_link.supplier_id;

    -- Lo que sale vale lo que dice el pedido, no la ficha de hoy.
    select coalesce(sum(
             least(d.quantity, coalesce((line.value ->> 'quantity')::numeric, 0))
             * coalesce((line.value ->> 'unit_cost')::numeric, 0)
           ), 0)
      into v_removed_net
      from (
        select x ->> 'product_id' as product_id, sum((x ->> 'quantity')::numeric) as quantity
          from jsonb_array_elements(v_delta) x
         group by x ->> 'product_id'
      ) d
      join lateral (
        select e.value
          from jsonb_array_elements(
            case when jsonb_typeof(v_invoice.items) = 'array' then v_invoice.items else '[]'::jsonb end
          ) with ordinality e
         where e.value ->> 'product_id' = d.product_id
         order by e.ordinality
         limit 1
      ) line on true;

    v_items := public.supplier_open_order_items_apply_internal(v_invoice.items, v_delta, -1);

    select count(*) into v_others
      from public.customer_quote_purchase_orders po
      join public.online_orders o on o.id = po.online_order_id and o.tenant_id = po.tenant_id
     where po.purchase_invoice_id = v_invoice.id
       and po.tenant_id = v_order.tenant_id
       and po.online_order_id <> p_order_id
       and o.status <> 'cancelled';

    if v_others = 0 and jsonb_array_length(v_items) = 0 then
      -- El pedido era sólo de esta venta: lo anula el comando de anulación,
      -- como siempre, y su historia lo cuenta. Ninguna venta nueva se suma a
      -- un pedido que sólo lleva ventas anuladas (la búsqueda del pedido
      -- abierto pide una viva).
      v_cancelled := v_cancelled + 1;
    else
      v_net := public.clp_round(greatest(coalesce(v_invoice.net_amount, v_invoice.subtotal, 0) - v_removed_net, 0));
      v_iva := public.clp_round(v_net * 0.19);
      delete from public.customer_quote_purchase_orders where id = v_link.id;
      update public.purchase_invoices
         set items = v_items,
             subtotal = v_net,
             net_amount = v_net,
             iva_amount = v_iva,
             total = v_net + v_iva,
             notes = public.supplier_open_order_note_internal(v_invoice.id),
             updated_at = clock_timestamp()
       where id = v_invoice.id
         and tenant_id = v_order.tenant_id;
      v_released := v_released + 1;
    end if;
  end loop;

  return jsonb_build_object('released', v_released, 'cancelled', v_cancelled);
end;
$function$;

revoke all on function public.supplier_open_order_release_order_internal(uuid)
  from public, anon, authenticated;

-- Cualquier anulación de una venta («Anular y devolver» del pedido web o de
-- la cotización) pasa por aquí, como la liberación de lo apartado.
create or replace function public.release_supplier_open_order_on_order_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    perform public.supplier_open_order_release_order_internal(new.id);
  end if;
  return null;
end;
$function$;

revoke all on function public.release_supplier_open_order_on_order_cancel()
  from public, anon, authenticated;

drop trigger if exists trg_release_supplier_open_order_on_order_cancel on public.online_orders;
create trigger trg_release_supplier_open_order_on_order_cancel
  after update of status on public.online_orders
  for each row
  execute function public.release_supplier_open_order_on_order_cancel();

-- ---------------------------------------------------------------------------
-- 4. La guarda del pedido abierto.
-- ---------------------------------------------------------------------------

-- Mientras un pedido con ventas web es borrador: no se le saca lo que pagó un
-- cliente (lo que todavía no llega), y no pasa a «Enviada» sin
-- purchase_order_mark_sent_v1, que compara lo que salió con lo que dice. Un
-- borrador sin ventas web no se toca.
create or replace function public.supplier_open_order_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_need record;
  v_have numeric;
begin
  if old.status is distinct from 'draft' then
    return new;
  end if;
  if not exists (
    select 1 from public.customer_quote_purchase_orders po
     where po.purchase_invoice_id = new.id
       and po.tenant_id = new.tenant_id
  ) then
    return new;
  end if;

  if new.status = 'sent'
     and coalesce(current_setting('app.supplier_order_send', true), '') <> new.id::text then
    raise exception 'Actualiza el ERP: este pedido se envía con su PDF desde «Enviar al proveedor».'
      using errcode = '55000', hint = 'supplier_order_send_required';
  end if;

  if new.status = 'draft' and new.items is distinct from old.items then
    for v_need in
      select i.product_id::text as product_id,
             min(i.product_name) as product_name,
             sum(i.quantity) as quantity,
             string_agg(distinct o.order_number, ', ') as orders
        from public.customer_quote_purchase_orders po
        join public.online_orders o
          on o.id = po.online_order_id
         and o.tenant_id = po.tenant_id
        join public.online_order_items i
          on i.order_id = o.id
         and i.tenant_id = o.tenant_id
       where po.purchase_invoice_id = new.id
         and po.tenant_id = new.tenant_id
         and o.status <> 'cancelled'
         and o.payment_status = 'paid'
         and i.fulfillment = 'on_order'
         and i.arrived_at is null
         and i.on_order_supplier_id = po.supplier_id
       group by i.product_id
    loop
      select coalesce(sum((e.value ->> 'quantity')::numeric), 0)
        into v_have
        from jsonb_array_elements(
          case when jsonb_typeof(new.items) = 'array' then new.items else '[]'::jsonb end
        ) e
       where e.value ->> 'product_id' = v_need.product_id;
      if v_have < v_need.quantity then
        raise exception 'No se puede sacar % de este pedido: lo pagó %. Vuelve a abrirlo para ver lo último.',
          v_need.product_name, v_need.orders
          using errcode = '23514', hint = 'supplier_order_line_needed';
      end if;
    end loop;
  end if;
  return new;
end;
$function$;

revoke all on function public.supplier_open_order_guard()
  from public, anon, authenticated;

drop trigger if exists trg_supplier_open_order_guard on public.purchase_invoices;
create trigger trg_supplier_open_order_guard
  before update of items, status on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.supplier_open_order_guard();

-- ---------------------------------------------------------------------------
-- 5. Enviar: lo que salió tiene que ser lo que dice el pedido.
-- ---------------------------------------------------------------------------

-- El asistente de compras manda el mensaje y el PDF y recién entonces llama
-- esto con las líneas que mandó. Si entretanto entró otra venta, el pedido no
-- se marca: lo nuevo no le llegó al proveedor. Repetir la llamada con el
-- pedido ya enviado devuelve lo mismo.
create or replace function public.purchase_order_mark_sent_v1(
  p_tenant_id uuid,
  p_purchase_invoice_id uuid,
  p_sent_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_invoice public.purchase_invoices%rowtype;
  v_changed text;
begin
  if auth.uid() is null or p_tenant_id is null or p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Purchase order not found or not accessible' using errcode = '42501';
  end if;
  if p_sent_lines is null or jsonb_typeof(p_sent_lines) <> 'array' then
    raise exception 'Invalid sent lines' using errcode = '22023';
  end if;

  select * into v_invoice from public.purchase_invoices
   where id = p_purchase_invoice_id
     and tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Purchase order not found or not accessible' using errcode = 'P0002';
  end if;
  if v_invoice.status = 'sent' then
    return to_jsonb(v_invoice) || jsonb_build_object('replay', true);
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'Este pedido ya no es un borrador.' using errcode = '55000';
  end if;

  -- Lo que dice el pedido menos lo que salió, producto por producto.
  with difference as (
    select both_sides.product_id,
           sum(both_sides.quantity) as quantity,
           min(both_sides.name) as name
      from (
        select e.value ->> 'product_id' as product_id,
               coalesce((e.value ->> 'quantity')::numeric, 0) as quantity,
               coalesce(e.value ->> 'product_name', e.value ->> 'description') as name
          from jsonb_array_elements(
            case when jsonb_typeof(v_invoice.items) = 'array' then v_invoice.items else '[]'::jsonb end
          ) e
        union all
        select x ->> 'product_id',
               -coalesce((x ->> 'quantity')::numeric, 0),
               null
          from jsonb_array_elements(p_sent_lines) x
      ) both_sides
     group by both_sides.product_id
  )
  select string_agg(coalesce(difference.name, 'un producto'), ', '
                    order by coalesce(difference.name, 'un producto'))
    into v_changed
    from difference
   where difference.quantity <> 0;
  if v_changed is not null then
    raise exception 'El pedido cambió mientras se enviaba (%): vuelve a abrirlo y mándale lo que falta.',
      v_changed
      using errcode = '55000', hint = 'supplier_order_changed';
  end if;

  perform set_config('app.supplier_order_send', v_invoice.id::text, true);
  update public.purchase_invoices
     set status = 'sent',
         sent_date = clock_timestamp(),
         updated_at = clock_timestamp()
   where id = v_invoice.id
     and tenant_id = p_tenant_id
  returning * into v_invoice;
  perform set_config('app.supplier_order_send', '', true);

  -- El aviso «Pagado: pedir lo que viene a pedido» de cada venta que lleva.
  update public.erp_notifications n
     set read_at = coalesce(n.read_at, clock_timestamp())
   where n.tenant_id = p_tenant_id
     and n.type = 'customer_quote_order_to_purchase'
     and n.entity_type = 'online_order'
     and n.entity_id in (
       select po.online_order_id
         from public.customer_quote_purchase_orders po
        where po.purchase_invoice_id = v_invoice.id
          and po.tenant_id = p_tenant_id
     );

  return to_jsonb(v_invoice) || jsonb_build_object('replay', false);
end;
$function$;

revoke all on function public.purchase_order_mark_sent_v1(uuid, uuid, jsonb) from public, anon;
grant execute on function public.purchase_order_mark_sent_v1(uuid, uuid, jsonb) to authenticated;

comment on function public.purchase_order_mark_sent_v1(uuid, uuid, jsonb) is
  'Marca enviado un pedido a proveedor (borrador de compra) sólo si las líneas que '
  'salieron por WhatsApp son las que dice el pedido (20261122010000).';

-- El chat de WhatsApp del proveedor donde va el PDF: el de su vendedor (el
-- teléfono de la ficha) y, si no, el más reciente. last_inbound_at dice si la
-- ventana de 24 h está abierta.
create or replace function public.purchase_order_supplier_chat_v1(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_supplier public.suppliers%rowtype;
  v_digits text;
  v_chat record;
begin
  if auth.uid() is null or p_tenant_id is null or p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Supplier not found or not accessible' using errcode = '42501';
  end if;
  select * into v_supplier from public.suppliers
   where id = p_supplier_id and tenant_id = p_tenant_id;
  if not found then
    raise exception 'Supplier not found or not accessible' using errcode = 'P0002';
  end if;
  v_digits := right(regexp_replace(coalesce(v_supplier.sales_rep_phone, ''), '\D', '', 'g'), 8);

  select c.id as conversation_id,
         b.last_inbound_at,
         b.external_phone_number
    into v_chat
    from public.conversations c
    left join public.whatsapp_conversation_bindings b
      on b.conversation_id = c.id
     and b.tenant_id = c.tenant_id
   where c.tenant_id = p_tenant_id
     and c.context_type = 'supplier'
     and c.context_id = p_supplier_id
     and c.channel = 'whatsapp'
   order by (length(v_digits) = 8
             and right(regexp_replace(coalesce(b.external_phone_number, ''), '\D', '', 'g'), 8) = v_digits) desc,
            b.last_inbound_at desc nulls last,
            c.updated_at desc nulls last
   limit 1;

  if v_chat.conversation_id is null then
    return jsonb_build_object('conversation_id', null, 'last_inbound_at', null, 'window_open', false);
  end if;
  return jsonb_build_object(
    'conversation_id', v_chat.conversation_id,
    'last_inbound_at', v_chat.last_inbound_at,
    'window_open', coalesce(v_chat.last_inbound_at > clock_timestamp() - interval '24 hours', false)
  );
end;
$function$;

revoke all on function public.purchase_order_supplier_chat_v1(uuid, uuid) from public, anon;
grant execute on function public.purchase_order_supplier_chat_v1(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Lo vendido se descuenta hasta 2 días después de enviar el pedido.
-- ---------------------------------------------------------------------------

create or replace function public.product_on_order_offer_internal_v1(
  p_tenant_id uuid,
  p_product_ids uuid[] default null
)
returns table (
  product_id uuid,
  supplier_id uuid,
  lead_days_min smallint,
  lead_days_max smallint,
  max_quantity integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with terms as (
    select t.product_id,
           t.supplier_id,
           t.lead_days_min,
           t.lead_days_max,
           coalesce(p.website_price, p.price, 0) as price,
           nullif(btrim(coalesce(p.supplier_code, '')), '') as supplier_code,
           array_remove(array[
             nullif(btrim(coalesce(p.barcode, '')), ''),
             nullif(btrim(coalesce(p.supplier_code, '')), ''),
             nullif(btrim(coalesce(p.sku, '')), '')
           ], null) as codes
      from public.product_on_order_terms t
      join public.products p
        on p.id = t.product_id
       and p.tenant_id = t.tenant_id
     where t.tenant_id = p_tenant_id
       and t.is_active
       and t.supplier_id is not null
       and (p_product_ids is null or t.product_id = any (p_product_ids))
  ), sized as (
    select terms.*,
           feed.id as feed_id,
           feed.last_ok_at,
           item.stock as supplier_stock,
           coalesce(pending.quantity, 0) as pending,
           case
             when terms.price <= 50000 then 5
             when terms.price <= 200000 then 3
             else 2
           end as per_order
      from terms
      left join lateral (
        select f.id, f.last_ok_at
          from public.supplier_catalog_feeds f
         where f.tenant_id = p_tenant_id
           and f.supplier_id = terms.supplier_id
           and f.enabled
         order by f.last_ok_at desc nulls last
         limit 1
      ) feed on true
      left join lateral (
        -- El producto en la lectura del proveedor: por su código del
        -- proveedor y, si no, por un código de barras (los del local llevan
        -- el código de barras en el SKU o en el código del proveedor).
        select fi.stock
          from public.supplier_catalog_feed_items fi
         where fi.tenant_id = p_tenant_id
           and fi.supplier_id = terms.supplier_id
           and fi.feed_id = feed.id
           and fi.is_listed
           and (
             fi.supplier_sku = terms.supplier_code
             or (fi.barcode = any (terms.codes) and fi.barcode not in ('', '0'))
           )
         order by (fi.supplier_sku = terms.supplier_code) desc nulls last,
                  fi.stock desc
         limit 1
      ) item on feed.id is not null
      left join lateral (
        -- Lo vendido que todavía no llega: la lectura del proveedor recién lo
        -- descuenta cuando se le compra. Mientras el pedido al proveedor no
        -- sale cuenta siempre; enviado, 2 días más; sin pedido todavía (un
        -- pago que no llega), 2 días desde la venta (20261122010000).
        select sum(i.quantity)::integer as quantity
          from public.online_order_items i
          join public.online_orders o
            on o.id = i.order_id
           and o.tenant_id = i.tenant_id
          left join public.customer_quote_purchase_orders po
            on po.online_order_id = o.id
           and po.tenant_id = o.tenant_id
           and po.supplier_id = i.on_order_supplier_id
          left join public.purchase_invoices pi
            on pi.id = po.purchase_invoice_id
           and pi.tenant_id = po.tenant_id
         where i.tenant_id = p_tenant_id
           and i.product_id = terms.product_id
           and i.fulfillment = 'on_order'
           and i.arrived_at is null
           and o.status <> 'cancelled'
           and case
                 when pi.id is null then o.created_at > clock_timestamp() - interval '2 days'
                 when pi.status = 'draft' then true
                 when pi.status = 'cancelled' then false
                 else coalesce(pi.sent_date, pi.updated_at) > clock_timestamp() - interval '2 days'
               end
      ) pending on true
  )
  select sized.product_id,
         sized.supplier_id,
         sized.lead_days_min,
         sized.lead_days_max,
         (case
            when sized.feed_id is null then sized.per_order
            else least(sized.per_order, sized.supplier_stock - 5 - sized.pending)
          end)::integer as max_quantity
    from sized
   where sized.feed_id is null
      or (
        sized.last_ok_at > clock_timestamp() - interval '3 hours'
        and sized.supplier_stock is not null
        and sized.supplier_stock - 5 - sized.pending >= 1
      );
$function$;

revoke all on function public.product_on_order_offer_internal_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;

comment on function public.product_on_order_offer_internal_v1(uuid, uuid[]) is
  'Lo que se vende hoy con plazo (20261120210000): «Se vende a pedido» activo con '
  'proveedor y, con lector de catálogo, su lectura de menos de 3 h con 6 o más. '
  'max_quantity: lo del proveedor menos 5 y menos lo vendido sin llegar (mientras '
  'el pedido no sale y 2 días después de enviado, 20261122010000), con tope por '
  'compra (5/3/2 según precio). Núcleo privado; sin grant.';

-- ---------------------------------------------------------------------------
-- 7. Lo que llega se reparte en el orden en que pagaron.
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_orders_check_arrivals_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order_id uuid;
  v_count integer := 0;
begin
  for v_order_id in
    select waiting.id
      from (
        select o.id, coalesce(o.paid_at, o.created_at) as paid_at
          from public.online_orders o
          join public.online_order_items item on item.order_id = o.id and item.tenant_id = o.tenant_id
          join public.products p on p.id = item.product_id and p.tenant_id = item.tenant_id
         where o.payment_status = 'paid'
           and o.status <> 'cancelled'
           and o.sales_invoice_id is null
           and item.fulfillment = 'on_order'
           and item.arrived_at is null
           and coalesce(p.stock_quantity, p.inventory_qty, 0) >= item.quantity
         group by o.id, coalesce(o.paid_at, o.created_at)
      ) waiting
     order by waiting.paid_at, waiting.id
     limit 50
  loop
    begin
      perform public.customer_quote_order_check_arrivals_internal(v_order_id);
      v_count := v_count + 1;
    exception when others then
      raise warning 'On-order arrival check failed for %: %', v_order_id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.customer_quote_orders_check_arrivals_v1() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. En el ERP: con cuántas ventas va el pedido y cuándo salió.
-- ---------------------------------------------------------------------------

create or replace function public.online_order_on_order_projection_internal(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
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
    'quote_id', (
      select q.id from public.customer_quotes q
       where q.online_order_id = o.id and q.tenant_id = o.tenant_id
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
        'sent_at', pi.sent_date,
        'orders', (
          select count(*)
            from public.customer_quote_purchase_orders other
            join public.online_orders other_order
              on other_order.id = other.online_order_id
             and other_order.tenant_id = other.tenant_id
           where other.purchase_invoice_id = pi.id
             and other.tenant_id = pi.tenant_id
             and other_order.status <> 'cancelled'
        ),
        'created_at', po.created_at
      ) order by po.created_at)
        from public.customer_quote_purchase_orders po
        left join public.suppliers s on s.id = po.supplier_id and s.tenant_id = po.tenant_id
        left join public.purchase_invoices pi on pi.id = po.purchase_invoice_id and pi.tenant_id = po.tenant_id
       where po.online_order_id = o.id and po.tenant_id = o.tenant_id
    ), '[]'::jsonb)
  )
    from public.online_orders o
   where o.id = p_order_id;
$function$;

revoke all on function public.online_order_on_order_projection_internal(uuid)
  from public, anon, authenticated;

comment on table public.customer_quote_purchase_orders is
  'Cada venta web con productos que llegan del proveedor y el pedido a ese proveedor que los lleva: '
  'el borrador de compra (PED-…) abierto del proveedor, que junta las ventas hasta que se envía '
  '(20261122010000). quote_id sólo cuando la venta nació de una cotización.';

commit;
