-- Deployment status: PENDING.
--
-- Manual online-payment confirmation already creates deterministic, unique
-- child operation keys. Resolve those exact identities instead of comparing
-- wall-clock timestamps: clock_timestamp() can move backwards when the host or
-- database VM corrects its clock, which previously left a completed invoice
-- and payment trace disconnected from their parent confirmation operation.
--
-- Recovery: this is a backwards-compatible function replacement. Rolling the
-- client back needs no schema rollback; a future replacement may supersede the
-- function while preserving the deterministic child-operation contract.

begin;

create or replace function public.confirm_online_order_payment(
  p_order_id uuid,
  p_payment_reference text default null,
  p_payment_date timestamp with time zone default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.confirm_online_order_payment(uuid, text, timestamp with time zone)
  from public, anon;
grant execute on function public.confirm_online_order_payment(uuid, text, timestamp with time zone)
  to authenticated;

comment on function public.confirm_online_order_payment(uuid, text, timestamp with time zone) is
  'Atomically confirms one full manual online-order payment and links exact deterministic invoice/payment child traces without wall-clock discovery.';

commit;
