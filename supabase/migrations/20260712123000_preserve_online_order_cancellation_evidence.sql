-- Preserve the complete online-order -> invoice -> stock/accounting chain.
-- Paid orders must use the explicit sales return / credit-note workflow; this
-- command never claims that cash was refunded and never deletes evidence.
begin;

alter table public.online_orders
  add column if not exists cancellation_operation_id uuid,
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'online_orders_cancellation_operation_fkey'
      and conrelid = 'public.online_orders'::regclass
  ) then
    alter table public.online_orders
      add constraint online_orders_cancellation_operation_fkey
      foreign key (tenant_id, cancellation_operation_id)
      references public.inventory_accounting_operations(tenant_id, id)
      on delete restrict;
  end if;
end $$;

create index if not exists idx_online_orders_cancellation_operation
  on public.online_orders(tenant_id, cancellation_operation_id)
  where cancellation_operation_id is not null;

create or replace function public.cancel_online_order(
  p_order_id uuid,
  p_reason text default 'Cancelado por el administrador',
  p_refund_amount numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.online_orders%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_tenant_id uuid := public.user_tenant_id();
  v_operation_id uuid;
  v_invoice_operation_id uuid;
  v_active_payment_total numeric := 0;
  v_invoice_status text;
  v_started_at timestamptz := clock_timestamp();
  v_before jsonb;
begin
  if v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = 'insufficient_privilege';
  end if;

  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'A cancellation reason is required'
      using errcode = 'check_violation';
  end if;

  if p_refund_amount is not null and (
    p_refund_amount < 0
    or p_refund_amount <> trunc(p_refund_amount)
  ) then
    raise exception 'Refund amount must be a non-negative whole CLP amount'
      using errcode = 'check_violation';
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

  if p_refund_amount is not null and p_refund_amount > v_order.total then
    raise exception 'Refund amount cannot exceed the order total'
      using errcode = 'check_violation';
  end if;

  -- Safe retry: return the original completed operation without producing a
  -- second invoice transition, stock movement, or journal action.
  if lower(v_order.status) = 'cancelled' then
    return jsonb_build_object(
      'success', true,
      'replay', true,
      'order_id', v_order.id,
      'order_number', v_order.order_number,
      'status', v_order.status,
      'refund_amount', coalesce(v_order.refund_amount, 0),
      'refund_recorded', v_order.refunded_at is not null,
      'invoice_preserved', v_order.sales_invoice_id is not null,
      'invoice_id', v_order.sales_invoice_id,
      'operation_id', v_order.cancellation_operation_id,
      'message', format('Pedido %s ya estaba cancelado; no se repitió ningún movimiento.', v_order.order_number)
    );
  end if;

  if v_order.sales_invoice_id is not null then
    select * into v_invoice
    from public.sales_invoices
    where id = v_order.sales_invoice_id
      and tenant_id = v_tenant_id
    for update;

    if not found then
      raise exception 'Linked sales invoice % is missing or belongs to another tenant',
        v_order.sales_invoice_id
        using errcode = 'foreign_key_violation';
    end if;

    select coalesce(sum(payment.amount), 0)
      into v_active_payment_total
      from public.sales_payments payment
     where payment.invoice_id = v_invoice.id
       and payment.tenant_id = v_tenant_id
       and payment.deleted_at is null;
  end if;

  v_invoice_status := lower(coalesce(v_invoice.status, ''));

  -- A cancellation is not a bank/card refund. Once money exists, the user
  -- must record the physical return (when applicable), credit note, and actual
  -- refund through the invoice corrections workflow.
  if lower(coalesce(v_order.payment_status, 'pending')) in ('paid', 'refunded')
     or v_order.paid_at is not null
     or v_active_payment_total > 0
     or v_invoice_status in ('paid', 'pagado', 'pagada') then
    raise exception 'Paid orders cannot be cancelled directly. Open the linked sales invoice and use Correcciones: devolución, nota de crédito y reembolso registrado.'
      using errcode = 'check_violation';
  end if;

  if coalesce(p_refund_amount, 0) <> 0 then
    raise exception 'This command does not execute money refunds. Use the linked invoice Correcciones workflow.'
      using errcode = 'check_violation';
  end if;

  v_before := jsonb_build_object(
    'order', to_jsonb(v_order),
    'invoice', case when v_order.sales_invoice_id is null then null else to_jsonb(v_invoice) end,
    'active_payment_total', v_active_payment_total
  );

  insert into public.inventory_accounting_operations(
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status,
    before_snapshot, context
  ) values (
    v_tenant_id,
    'online_order_cancel:' || p_order_id::text,
    'online_sale',
    'cancel',
    'online_order',
    p_order_id,
    auth.uid(),
    'database_rpc',
    v_order.status,
    'cancelled',
    v_before,
    jsonb_build_object(
      'reason', btrim(p_reason),
      'linked_sales_invoice_id', v_order.sales_invoice_id,
      'refund_requested', coalesce(p_refund_amount, 0),
      'refund_executed', false,
      'transaction_id', txid_current()::text
    )
  )
  returning id into v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'online_order', p_order_id,
    jsonb_build_object('action', 'cancel', 'reason', btrim(p_reason))
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'online_order', p_order_id,
    v_before
  );

  -- Preserve the linked invoice. Its existing invoice trigger owns the exact
  -- stock restoration and journal-evidence capture as a separately traceable
  -- child operation.
  if v_order.sales_invoice_id is not null
     and v_invoice_status not in ('cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada') then
    perform set_config('app.inventory_idempotency_key', 'online_order_cancel:' || p_order_id::text, true);
    update public.sales_invoices
       set status = 'cancelled',
           updated_at = clock_timestamp()
     where id = v_invoice.id
       and tenant_id = v_tenant_id;

    select operation.id into v_invoice_operation_id
      from public.inventory_accounting_operations operation
     where operation.tenant_id = v_tenant_id
       and operation.document_type = 'sales_invoice'
       and operation.document_id = v_invoice.id
       and operation.action = 'update'
       and operation.created_at >= v_started_at
     order by operation.created_at desc
     limit 1;
  end if;

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'online_order', true);
  perform set_config('app.inventory_source_document_id', p_order_id::text, true);
  perform set_config('app.inventory_source_channel', 'online_sale', true);

  update public.online_orders
     set status = 'cancelled',
         cancelled_at = clock_timestamp(),
         cancelled_reason = btrim(p_reason),
         refund_amount = 0,
         refunded_at = null,
         cancelled_by = auth.uid(),
         cancellation_operation_id = v_operation_id,
         updated_at = clock_timestamp()
   where id = p_order_id
     and tenant_id = v_tenant_id;

  update public.inventory_accounting_operations
     set after_snapshot = jsonb_build_object(
           'order', (select to_jsonb(current_order) from public.online_orders current_order where current_order.id = p_order_id),
           'invoice', case when v_order.sales_invoice_id is null then null else
             (select to_jsonb(current_invoice) from public.sales_invoices current_invoice where current_invoice.id = v_order.sales_invoice_id)
           end
         ),
         context = context || jsonb_build_object(
           'invoice_operation_id', v_invoice_operation_id,
           'invoice_preserved', v_order.sales_invoice_id is not null
         )
   where id = v_operation_id
     and tenant_id = v_tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'inventory_applied',
    'completed',
    coalesce(case when v_invoice_operation_id is null then 'online_order' else 'sales_invoice' end, 'online_order'),
    coalesce(v_order.sales_invoice_id, p_order_id),
    jsonb_build_object(
      'child_invoice_operation_id', v_invoice_operation_id,
      'stock_effect_owned_by_child_operation', v_invoice_operation_id is not null,
      'invoice_preserved', v_order.sales_invoice_id is not null
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accounting_planned', 'completed', 'online_order', p_order_id,
    jsonb_build_object(
      'child_invoice_operation_id', v_invoice_operation_id,
      'refund_executed', false,
      'payment_evidence_deleted', false
    )
  );

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    v_tenant_id,
    jsonb_build_object(
      'status', 'cancelled',
      'invoice_id', v_order.sales_invoice_id,
      'invoice_operation_id', v_invoice_operation_id,
      'refund_amount', 0,
      'invoice_preserved', v_order.sales_invoice_id is not null
    )
  );

  return jsonb_build_object(
    'success', true,
    'replay', false,
    'order_id', p_order_id,
    'order_number', v_order.order_number,
    'status', 'cancelled',
    'refund_amount', 0,
    'refund_recorded', false,
    'invoice_preserved', v_order.sales_invoice_id is not null,
    'invoice_id', v_order.sales_invoice_id,
    'invoice_number', v_invoice.invoice_number,
    'operation_id', v_operation_id,
    'invoice_operation_id', v_invoice_operation_id,
    'message', format('Pedido %s cancelado sin borrar su factura ni registrar un reembolso ficticio.', v_order.order_number)
  );
end;
$$;

revoke all on function public.cancel_online_order(uuid, text, numeric)
  from public, anon;
grant execute on function public.cancel_online_order(uuid, text, numeric)
  to authenticated;

comment on function public.cancel_online_order(uuid, text, numeric) is
  'Cancels only unpaid online orders, preserves linked invoice/payment evidence, and records a trace operation. Paid orders require invoice corrections.';

commit;
