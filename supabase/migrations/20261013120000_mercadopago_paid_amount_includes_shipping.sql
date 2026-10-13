-- Un pago de Mercado Pago vale productos + despacho (2026-10-13).
--
-- La primera venta web oficial (WEB-26-00021, 2026-10-12) se pagó completa:
-- $11.000 de productos más $6.990 de despacho, $17.990 en total (Mercado
-- Pago: `transaction_amount` 11000, `shipping_amount` 6990,
-- `total_paid_amount` 17990; a la tienda le llegaron $17.306 después de la
-- comisión de $684). Pero el webhook y `mercadopago-get-payment` anotaban como
-- monto del pago sólo `transaction_amount`: Mercado Pago deja el despacho de
-- `shipments.cost` fuera de ese campo. El pago quedó «rechazado por monto»
-- ($11.000 contra un pedido de $17.990), sin venta ERP y marcado para revisar
-- un reembolso que no correspondía. Ningún pago web con despacho había llegado
-- a aprobarse antes (WEB-26-00015, mayo, fue con despacho $0).
--
-- Desde esta versión las funciones anotan productos + despacho y guardan
-- `shipping_amount` en la evidencia (supabase/functions/_shared/
-- mercadopago_payment_evidence.ts). Esta migración:
--
-- 1. Hace que `mercadopago_payment_evidence_matches_voucher` sume el mismo
--    despacho, para que un comprobante de un pago con despacho pueda calzar.
-- 2. Repara la única observación anotada mal (WEB-26-00021): monto 17990,
--    resultado `payment_validated`, la evidencia completa con el
--    `shipping_amount` que Mercado Pago devuelve para ese pago (leído de su
--    API el 2026-10-13), y su procesamiento vuelve a pendiente para que la
--    venta se cree por el camino normal («Reintentar procesamiento»). Los
--    intentos rechazados quedan en `sales_channel_payment_processing_attempts`.
--    Se exige el estado exacto de hoy; si ya está reparada no hace nada, y si
--    algo difiere se detiene.
--
-- La función reemplazada parte del texto vivo de producción del 2026-10-13.

begin;
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.mercadopago_payment_evidence_matches_voucher(p_provider_payload jsonb, p_payment_operation_id text, p_authorization_code text, p_amount numeric, p_currency text, p_issued_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_operation_id text := btrim(coalesce(p_payment_operation_id, ''));
  v_authorization_code text := btrim(coalesce(p_authorization_code, ''));
  v_currency text := upper(btrim(coalesce(p_currency, '')));
  v_payload_approved_at timestamp with time zone;
  v_payload_amount numeric;
  v_payload_total_paid numeric;
  v_payload_shipping numeric := 0;
begin
  if p_provider_payload is null
     or jsonb_typeof(p_provider_payload) <> 'object'
     or v_operation_id = ''
     or v_authorization_code = ''
     or p_amount is null
     or p_issued_at is null then
    return false;
  end if;

  -- Mercado Pago defines a voucher as the receipt generated for credit,
  -- debit or prepaid card transactions. Bank-transfer/Fintoc redirects,
  -- offline tickets, account-money status and 3DS challenge URLs are payment
  -- flow resources, not an official voucher artifact.
  if lower(btrim(coalesce(p_provider_payload->>'payment_type_id', '')))
       not in ('credit_card', 'debit_card', 'prepaid_card')
     or btrim(coalesce(p_provider_payload->>'operation_number', ''))
       <> v_operation_id
     or btrim(coalesce(p_provider_payload->>'authorization_code', ''))
       <> v_authorization_code
     or coalesce(p_provider_payload->>'card_last_four_digits', '')
       !~ '^[0-9]{4}$'
     or upper(btrim(coalesce(p_provider_payload->>'currency_id', '')))
       <> v_currency
     or coalesce(p_provider_payload->>'transaction_amount', '')
       !~ '^[0-9]{1,14}([.][0-9]{1,4})?$'
     or coalesce(p_provider_payload->>'total_paid_amount', '')
       !~ '^[0-9]{1,14}([.][0-9]{1,4})?$'
     or coalesce(p_provider_payload->>'shipping_amount', '0')
       !~ '^[0-9]{1,14}([.][0-9]{1,4})?$'
     or coalesce(p_provider_payload->>'date_approved', '')
       !~ '^\d{4}-\d{2}-\d{2}T.*(Z|[+-]\d{2}:?\d{2})$' then
    return false;
  end if;

  begin
    v_payload_amount := (p_provider_payload->>'transaction_amount')::numeric;
    v_payload_total_paid := (p_provider_payload->>'total_paid_amount')::numeric;
    v_payload_shipping :=
      coalesce((p_provider_payload->>'shipping_amount')::numeric, 0);
    v_payload_approved_at :=
      (p_provider_payload->>'date_approved')::timestamp with time zone;
  exception when others then
    return false;
  end;

  -- What the buyer paid for the order is the products plus the delivery
  -- Mercado Pago charged (`shipping_amount`), as the payment is recorded.
  return round(v_payload_amount + v_payload_shipping, 2) = round(p_amount, 2)
    and round(v_payload_total_paid, 2) = round(p_amount, 2)
    and v_payload_approved_at = p_issued_at;
end;
$function$;

do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_event public.sales_channel_payment_events%rowtype;
  v_order public.online_orders%rowtype;
  v_processing public.sales_channel_payment_processing%rowtype;
begin
  select payment_event.* into v_event
  from public.sales_channel_payment_events payment_event
  where payment_event.tenant_id = v_tenant_id
    and payment_event.provider = 'mercadopago'
    and payment_event.external_payment_id = '182785051395'
    and payment_event.provider_status = 'approved';

  if not found then
    -- Any database other than production (local, CI) has nothing to repair;
    -- the production read-back asserts the repaired row exists.
    raise notice 'WEB-26-00021 payment observation is not in this database';
    return;
  end if;

  select orders.* into v_order
  from public.online_orders orders
  where orders.id = v_event.order_id
    and orders.tenant_id = v_tenant_id
  for update;

  select processing.* into v_processing
  from public.sales_channel_payment_processing processing
  where processing.payment_event_id = v_event.id
    and processing.tenant_id = v_tenant_id
  for update;

  if v_event.outcome = 'payment_validated'
     and v_event.amount = 17990
     and (v_event.provider_payload->>'shipping_amount')::numeric = 6990 then
    raise notice 'WEB-26-00021 payment observation already repaired';
    return;
  end if;

  if v_order.order_number is distinct from 'WEB-26-00021'
     or v_order.total <> 17990
     or v_order.shipping_cost <> 6990
     or v_order.payment_status <> 'pending'
     or v_order.sales_invoice_id is not null
     or v_event.outcome <> 'rejected_amount'
     or v_event.amount <> 11000
     or upper(v_event.currency) <> 'CLP'
     or (v_event.provider_payload->>'transaction_amount')::numeric <> 11000
     or (v_event.provider_payload->>'total_paid_amount')::numeric <> 17990
     or v_event.provider_payload ? 'shipping_amount'
     or v_processing.processing_state is distinct from 'action_required'
     or v_processing.last_error_code is distinct from 'rejected_amount' then
    raise exception 'WEB-26-00021 is no longer in the state this repair was written for';
  end if;

  alter table public.sales_channel_payment_events
    disable trigger trg_sales_channel_payment_events_immutable;

  update public.sales_channel_payment_events
     set amount = 17990,
         outcome = 'payment_validated',
         validation_error = null,
         provider_payload = provider_payload
           || jsonb_build_object('shipping_amount', 6990)
   where id = v_event.id
     and tenant_id = v_tenant_id;

  alter table public.sales_channel_payment_events
    enable trigger trg_sales_channel_payment_events_immutable;

  update public.sales_channel_payment_processing
     set processing_state = 'pending',
         action_required_at = null,
         last_error_code = null,
         last_error_message = null,
         requires_refund_review = false,
         updated_at = clock_timestamp()
   where payment_event_id = v_event.id
     and tenant_id = v_tenant_id;
end;
$$;

commit;
