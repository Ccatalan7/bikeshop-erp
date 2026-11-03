-- Anular y devolver un pedido de cotización pagado que todavía espera.
--
-- Desde 20261103010000 la venta de un pedido de cotización espera a que
-- llegue lo que viene a pedido. Si el proveedor no lo tiene, el pedido quedaba
-- sin salida: `cancel_online_order` se niega a anular un pedido pagado, y
-- Correcciones (devolución, nota de crédito y reembolso) pide una venta que
-- este pedido no tiene. No hay nada contable que revertir: el pago no se
-- registró como venta.
--
-- `customer_quote_order_cancel_v1` es ese camino. El equipo devuelve la plata
-- primero (en Mercado Pago o por transferencia) y anota su referencia; recién
-- entonces el comando anula el pedido, que libera lo apartado (el disparador
-- de siempre), anula los borradores de compra que nadie mandó, cierra la
-- observación de Mercado Pago que esperaba la llegada y deja el reembolso
-- registrado (`payment_status = 'refunded'`). El cliente recibe los correos de
-- siempre: pedido cancelado y reembolso con su monto. Sólo lo corre quien
-- puede mover plata en Correcciones (`online_order_correction_actor_allowed`).
--
-- Un pedido anulado ya no espera nada: `customer_quote_order_waiting_internal`
-- lo deja fuera, así la bandeja, la ficha y la página del cliente no lo
-- muestran «esperando».

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

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
      'order_paid', 'order_ready', 'order_shipped', 'order_delivered', 'order_cancelled',
      'order_refunded'
    )
  );

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
      join public.online_orders orders on orders.id = item.order_id
     where item.order_id = p_order_id
       and item.fulfillment = 'on_order'
       and item.arrived_at is null
       and orders.status <> 'cancelled'
  );
$$;

revoke all on function public.customer_quote_order_waiting_internal(uuid) from public, anon, authenticated;

create or replace function public.customer_quote_order_cancel_v1(
  p_tenant_id uuid,
  p_quote_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_key text := lower(btrim(coalesce(p_request ->> 'operation_key', '')));
  v_reason text := btrim(coalesce(p_request ->> 'reason', ''));
  v_reference text := btrim(coalesce(p_request ->> 'refund_reference', ''));
  v_refunded_at timestamptz;
  v_quote public.customer_quotes%rowtype;
  v_order public.online_orders%rowtype;
  v_operation_id uuid;
  v_before jsonb;
  v_cancelled_purchases integer := 0;
  v_sent_purchases integer := 0;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  if not public.online_order_correction_actor_allowed(p_tenant_id) then
    raise exception 'quote_refund_not_allowed' using errcode = '42501';
  end if;
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote order cancellation' using errcode = '22023';
  end if;
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random operation key is required' using errcode = '22023';
  end if;
  if length(v_reason) not between 4 and 500 then
    raise exception 'quote_cancel_reason_required' using errcode = '22023';
  end if;
  if length(v_reference) not between 2 and 120 then
    raise exception 'quote_refund_reference_required' using errcode = '22023';
  end if;
  begin
    v_refunded_at := coalesce(nullif(p_request ->> 'refunded_at', '')::timestamptz, clock_timestamp());
  exception when others then
    raise exception 'Invalid refund date' using errcode = '22023';
  end;
  if v_refunded_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'quote_refund_date_in_future' using errcode = '22023';
  end if;

  select * into v_quote from public.customer_quotes
   where id = p_quote_id and tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = '42501';
  end if;

  -- Un reintento con la misma llave devuelve lo que ya quedó hecho.
  if exists (
    select 1 from public.customer_quote_events e
     where e.quote_id = v_quote.id and e.operation_key = v_key
  ) then
    return public.customer_quote_detail_v1(p_tenant_id, p_quote_id)
      || jsonb_build_object('replay', true);
  end if;

  if v_quote.online_order_id is null then
    raise exception 'Quote has no order' using errcode = 'P0002';
  end if;
  select * into v_order from public.online_orders
   where id = v_quote.online_order_id and tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Quote has no order' using errcode = 'P0002';
  end if;
  if v_order.status = 'cancelled' then
    raise exception 'quote_order_already_cancelled' using errcode = '55000';
  end if;
  if v_order.payment_status <> 'paid' then
    -- Sin pago no hay nada que devolver: se anula como cualquier pedido web.
    raise exception 'quote_order_not_paid' using errcode = '55000';
  end if;
  if v_order.sales_invoice_id is not null then
    -- Con venta, la devolución es de Correcciones, con su nota de crédito.
    raise exception 'quote_order_has_sale' using errcode = '55000';
  end if;
  if v_order.status not in ('pending', 'confirmed', 'processing', 'ready_for_pickup') then
    raise exception 'quote_order_already_delivered' using errcode = '55000';
  end if;
  if v_refunded_at < coalesce(v_order.paid_at, v_order.created_at) - interval '1 day' then
    raise exception 'quote_refund_date_before_payment' using errcode = '22023';
  end if;

  v_before := jsonb_build_object('order', to_jsonb(v_order));
  insert into public.inventory_accounting_operations (
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status,
    before_snapshot, context
  ) values (
    p_tenant_id,
    'online_order_cancel:' || v_order.id::text,
    'online_sale',
    'cancel',
    'online_order',
    v_order.id,
    auth.uid(),
    'database_rpc',
    v_order.status,
    'cancelled',
    v_before,
    jsonb_build_object(
      'reason', v_reason,
      'customer_quote_id', v_quote.id,
      'refund_requested', v_order.total,
      'refund_executed', true,
      'refund_reference', v_reference,
      'transaction_id', txid_current()::text
    )
  )
  returning id into v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'online_order', v_order.id,
    jsonb_build_object('action', 'cancel', 'reason', v_reason)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'online_order', v_order.id,
    v_before
  );

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'online_order', true);
  perform set_config('app.inventory_source_document_id', v_order.id::text, true);
  perform set_config('app.inventory_source_channel', 'online_sale', true);
  perform set_config('app.online_order_operation_key', 'quote-order-cancel:' || v_key, true);
  perform set_config(
    'app.online_order_request_snapshot',
    jsonb_build_object(
      'source', 'customer_quote_order_cancel_v1',
      'reason', v_reason,
      'refund_reference', v_reference
    )::text,
    true
  );

  -- Los disparadores de siempre: liberan lo apartado, anotan la transición y
  -- encolan los correos de pedido cancelado y de reembolso.
  update public.online_orders
     set status = 'cancelled',
         cancelled_at = clock_timestamp(),
         cancelled_reason = v_reason,
         cancelled_by = auth.uid(),
         cancellation_operation_id = v_operation_id,
         payment_status = 'refunded',
         refund_amount = v_order.total,
         refunded_at = v_refunded_at,
         updated_at = clock_timestamp()
   where id = v_order.id
     and tenant_id = p_tenant_id;

  perform set_config('app.online_order_operation_key', '', true);
  perform set_config('app.online_order_request_snapshot', '', true);

  -- Lo que nadie mandó al proveedor se anula; lo enviado queda para que el
  -- equipo le avise.
  update public.purchase_invoices pi
     set status = 'cancelled',
         updated_at = clock_timestamp()
    from public.customer_quote_purchase_orders po
   where po.online_order_id = v_order.id
     and po.tenant_id = p_tenant_id
     and pi.id = po.purchase_invoice_id
     and pi.tenant_id = p_tenant_id
     and pi.status = 'draft';
  get diagnostics v_cancelled_purchases = row_count;
  select count(*) into v_sent_purchases
    from public.customer_quote_purchase_orders po
    join public.purchase_invoices pi on pi.id = po.purchase_invoice_id and pi.tenant_id = po.tenant_id
   where po.online_order_id = v_order.id
     and po.tenant_id = p_tenant_id
     and pi.status not in ('draft', 'cancelled');

  -- El pago de Mercado Pago que esperaba la llegada ya no espera nada.
  update public.sales_channel_payment_processing processing
     set processing_state = 'processed',
         processed_at = clock_timestamp(),
         action_required_at = null,
         last_error_code = 'quote_order_refunded',
         last_error_message = 'Pedido anulado y pago devuelto (' || v_reference || ').',
         requires_refund_review = false,
         updated_at = clock_timestamp()
   where processing.order_id = v_order.id
     and processing.tenant_id = p_tenant_id
     and processing.processing_state <> 'processed';

  update public.erp_notifications n
     set read_at = coalesce(n.read_at, clock_timestamp())
   where n.tenant_id = p_tenant_id
     and n.type in ('customer_quote_order_to_purchase', 'customer_quote_order_attention',
                    'customer_quote_order_ready')
     and n.entity_type = 'online_order'
     and n.entity_id = v_order.id;

  perform public.customer_quote_log_internal(
    v_quote.id, 'order_refunded', 'staff', auth.uid(), 'erp', v_quote.current_offer_id,
    v_key,
    jsonb_build_object(
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'amount', v_order.total,
      'reference', v_reference,
      'refunded_at', v_refunded_at,
      'reason', v_reason,
      'purchases_cancelled', v_cancelled_purchases,
      'purchases_sent', v_sent_purchases
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'online_order', v_order.id,
    jsonb_build_object('reservations_released_by_trigger', true)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accounting_planned', 'completed', 'online_order', v_order.id,
    jsonb_build_object(
      'refund_executed', true,
      'refund_outside_erp', true,
      'sale_never_issued', true,
      'purchases_cancelled', v_cancelled_purchases
    )
  );
  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    p_tenant_id,
    jsonb_build_object(
      'status', 'cancelled',
      'refund_amount', v_order.total,
      'refund_reference', v_reference
    )
  );

  return public.customer_quote_detail_v1(p_tenant_id, p_quote_id)
    || jsonb_build_object('replay', false, 'purchases_sent', v_sent_purchases);
end;
$$;

revoke all on function public.customer_quote_order_cancel_v1(uuid, uuid, jsonb) from public, anon;
grant execute on function public.customer_quote_order_cancel_v1(uuid, uuid, jsonb) to authenticated;

comment on function public.customer_quote_order_cancel_v1(uuid, uuid, jsonb) is
  'Cancels a paid quote order that has no sale yet after the team returned the money: records the refund, releases reservations, cancels unsent supplier drafts and closes the waiting Mercado Pago observation.';

commit;
