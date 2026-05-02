-- Fix online order cancellation after invoice_id was consolidated to sales_invoice_id.
-- Also keeps the canonical sales_payments soft-delete column present for fresh DBs.

alter table public.sales_payments
  add column if not exists deleted_at timestamp with time zone;

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
  v_order record;
  v_invoice record;
  v_actual_refund numeric;
  v_result jsonb;
begin
  select * into v_order
  from public.online_orders
  where id = p_order_id
    and tenant_id = public.user_tenant_id();

  if v_order is null then
    raise exception 'Order not found or access denied: %', p_order_id;
  end if;

  if v_order.status = 'cancelled' then
    raise exception 'Order is already cancelled';
  end if;

  if v_order.sales_invoice_id is not null then
    select * into v_invoice
    from public.sales_invoices
    where id = v_order.sales_invoice_id;
  end if;

  if p_refund_amount is null then
    v_actual_refund := v_order.total;
  else
    v_actual_refund := least(p_refund_amount, v_order.total);
  end if;

  if v_invoice is not null then
    if lower(coalesce(v_invoice.status, '')) in (
      'confirmed',
      'confirmado',
      'confirmada',
      'paid',
      'pagado',
      'pagada'
    ) then
      delete from public.sales_payments
      where invoice_id = v_invoice.id;

      update public.sales_invoices
      set status = 'draft',
          updated_at = now()
      where id = v_invoice.id;
    end if;

    delete from public.sales_invoices
    where id = v_invoice.id;

    raise notice 'Deleted invoice % and restored inventory', v_invoice.invoice_number;
  end if;

  update public.online_orders
  set status = 'cancelled',
      cancelled_at = now(),
      cancelled_reason = p_reason,
      refund_amount = v_actual_refund,
      refunded_at = case when v_actual_refund > 0 then now() else null end,
      sales_invoice_id = null,
      updated_at = now()
  where id = p_order_id;

  v_result := jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'order_number', v_order.order_number,
    'status', 'cancelled',
    'refund_amount', v_actual_refund,
    'invoice_deleted', v_invoice is not null,
    'invoice_number', coalesce(v_invoice.invoice_number, null),
    'message', format('Order %s cancelled. Refund: $%s', v_order.order_number, v_actual_refund)
  );

  return v_result;
end;
$$;

grant execute on function public.cancel_online_order(uuid, text, numeric) to authenticated;
