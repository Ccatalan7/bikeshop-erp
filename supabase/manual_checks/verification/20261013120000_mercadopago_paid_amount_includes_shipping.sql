-- Read-back de 20261013120000: el comprobante suma el despacho y el pago de
-- WEB-26-00021 quedó anotado por $17.990 (productos + despacho), validado y
-- pendiente de procesar, sin tocar el pedido.

select 1 / case
  when pg_get_functiondef('public.mercadopago_payment_evidence_matches_voucher(jsonb,text,text,numeric,text,timestamp with time zone)'::regprocedure)
         like '%v_payload_amount + v_payload_shipping%'
   and not has_function_privilege('anon', 'public.mercadopago_payment_evidence_matches_voucher(jsonb,text,text,numeric,text,timestamp with time zone)', 'execute')
   and exists (
     select 1
     from public.sales_channel_payment_events payment_event
     join public.sales_channel_payment_processing processing
       on processing.payment_event_id = payment_event.id
      and processing.tenant_id = payment_event.tenant_id
     join public.online_orders orders
       on orders.id = payment_event.order_id
      and orders.tenant_id = payment_event.tenant_id
     where payment_event.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and payment_event.external_payment_id = '182785051395'
       and payment_event.provider_status = 'approved'
       and payment_event.outcome = 'payment_validated'
       and payment_event.amount = 17990
       and payment_event.validation_error is null
       and (payment_event.provider_payload->>'shipping_amount')::numeric = 6990
       and (payment_event.provider_payload->>'transaction_amount')::numeric = 11000
       and orders.order_number = 'WEB-26-00021'
       and orders.total = 17990
       and orders.shipping_cost = 6990
       and (processing.processing_state = 'processed'
            or (processing.processing_state = 'pending'
                and processing.requires_refund_review is false
                and processing.last_error_code is null))
   )
   and exists (
     select 1
     from pg_trigger trigger_row
     where trigger_row.tgrelid = 'public.sales_channel_payment_events'::regclass
       and trigger_row.tgname = 'trg_sales_channel_payment_events_immutable'
       and trigger_row.tgenabled = 'O'
   )
  then 1 else 0
end as assert_mercadopago_paid_amount_includes_shipping;
