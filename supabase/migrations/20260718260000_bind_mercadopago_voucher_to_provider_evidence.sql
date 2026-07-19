-- Deployment status: NOT DEPLOYED. Validate on the production-derived clone
-- together with the pending 20260718120000..20260718250000 chain first.
--
-- A service-role caller must not be able to turn hand-entered fiscal fields
-- into a Mercado Pago voucher merely because some payment reached `approved`.
-- Bind the fiscal artifact to the exact sanitized Payments API observation:
-- operation id, supported card rail, authorization, last four digits, amount,
-- currency and provider approval timestamp must all agree. Redirect/ticket/3DS
-- URLs are deliberately outside this contract and can never satisfy it.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.mercadopago_payment_evidence_matches_voucher(
  p_provider_payload jsonb,
  p_payment_operation_id text,
  p_authorization_code text,
  p_amount numeric,
  p_currency text,
  p_issued_at timestamp with time zone
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_operation_id text := btrim(coalesce(p_payment_operation_id, ''));
  v_authorization_code text := btrim(coalesce(p_authorization_code, ''));
  v_currency text := upper(btrim(coalesce(p_currency, '')));
  v_payload_approved_at timestamp with time zone;
  v_payload_amount numeric;
  v_payload_total_paid numeric;
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
     or coalesce(p_provider_payload->>'date_approved', '')
       !~ '^\d{4}-\d{2}-\d{2}T.*(Z|[+-]\d{2}:?\d{2})$' then
    return false;
  end if;

  begin
    v_payload_amount := (p_provider_payload->>'transaction_amount')::numeric;
    v_payload_total_paid := (p_provider_payload->>'total_paid_amount')::numeric;
    v_payload_approved_at :=
      (p_provider_payload->>'date_approved')::timestamp with time zone;
  exception when others then
    return false;
  end;

  return round(v_payload_amount, 2) = round(p_amount, 2)
    and round(v_payload_total_paid, 2) = round(p_amount, 2)
    and v_payload_approved_at = p_issued_at;
end;
$$;

revoke all on function public.mercadopago_payment_evidence_matches_voucher(
  jsonb, text, text, numeric, text, timestamp with time zone
) from public, anon, authenticated, service_role;

-- Preserve the hardened 180000 recorder as the private fiscal base. A complete
-- core-schema replay recreates that public function before reaching this file,
-- so replace an older private copy only when the public body is not this
-- provider-binding wrapper. This keeps the migration idempotent.
do $$
declare
  v_public_body text;
begin
  select routine.prosrc into v_public_body
  from pg_proc routine
  where routine.oid = to_regprocedure(
    'public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)'
  );

  if v_public_body is null then
    raise exception 'Hardened official-document recorder is missing'
      using errcode = '42883';
  end if;

  if v_public_body not like '%mercadopago-provider-evidence-binding-v1%' then
    if to_regprocedure(
      'public.record_online_order_official_document_fiscal_base(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)'
    ) is not null then
      execute 'drop function public.record_online_order_official_document_fiscal_base(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)';
    end if;
    execute 'alter function public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb) rename to record_online_order_official_document_fiscal_base';
  end if;
end;
$$;

revoke all on function public.record_online_order_official_document_fiscal_base(
  uuid, uuid, text, text, text, text, numeric, text, timestamp with time zone,
  text, text, text, text, text, text, text, jsonb, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.record_online_order_official_document(
  p_tenant_id uuid,
  p_order_id uuid,
  p_document_kind text,
  p_provider text,
  p_provider_document_id text,
  p_fiscal_validity text,
  p_amount numeric,
  p_currency text,
  p_issued_at timestamp with time zone,
  p_artifact_url text,
  p_artifact_sha256 text,
  p_status text,
  p_source_event_key text,
  p_payment_operation_id text default null,
  p_document_type text default null,
  p_folio text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_voucher_fiscal_evidence jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
-- mercadopago-provider-evidence-binding-v1
declare
  v_document_kind text := lower(btrim(coalesce(p_document_kind, '')));
  v_provider text := lower(replace(btrim(coalesce(p_provider, '')), '_', ''));
  v_order_payment_method text;
  v_payment_event public.sales_channel_payment_events%rowtype;
  v_authorization_code text;
begin
  -- DTEs retain their independent provider contract. Non-Mercado Pago orders
  -- are delegated so the underlying recorder emits its canonical shape error.
  if v_document_kind <> 'payment_voucher' then
    return public.record_online_order_official_document_fiscal_base(
      p_tenant_id, p_order_id, p_document_kind, p_provider,
      p_provider_document_id, p_fiscal_validity, p_amount, p_currency,
      p_issued_at, p_artifact_url, p_artifact_sha256, p_status,
      p_source_event_key, p_payment_operation_id, p_document_type, p_folio,
      p_metadata, p_voucher_fiscal_evidence
    );
  end if;

  select lower(btrim(coalesce(orders.payment_method, '')))
  into v_order_payment_method
  from public.online_orders orders
  where orders.id = p_order_id
    and orders.tenant_id = p_tenant_id;

  if v_provider <> 'mercadopago'
     or v_order_payment_method not in ('mercadopago', 'mercado_pago') then
    return public.record_online_order_official_document_fiscal_base(
      p_tenant_id, p_order_id, p_document_kind, p_provider,
      p_provider_document_id, p_fiscal_validity, p_amount, p_currency,
      p_issued_at, p_artifact_url, p_artifact_sha256, p_status,
      p_source_event_key, p_payment_operation_id, p_document_type, p_folio,
      p_metadata, p_voucher_fiscal_evidence
    );
  end if;

  if p_voucher_fiscal_evidence is null
     or jsonb_typeof(p_voucher_fiscal_evidence) <> 'object'
     or jsonb_typeof(p_voucher_fiscal_evidence->'authorization_code')
       is distinct from 'string' then
    -- Preserve the stricter fiscal-base diagnostics for missing/invalid fiscal
    -- shape. That private layer cannot insert an incomplete voucher, so this
    -- delegation does not bypass the provider binding.
    return public.record_online_order_official_document_fiscal_base(
      p_tenant_id, p_order_id, p_document_kind, p_provider,
      p_provider_document_id, p_fiscal_validity, p_amount, p_currency,
      p_issued_at, p_artifact_url, p_artifact_sha256, p_status,
      p_source_event_key, p_payment_operation_id, p_document_type, p_folio,
      p_metadata, p_voucher_fiscal_evidence
    );
  end if;
  v_authorization_code :=
    btrim(p_voucher_fiscal_evidence->>'authorization_code');

  select payment_event.* into v_payment_event
  from public.sales_channel_payment_events payment_event
  where payment_event.tenant_id = p_tenant_id
    and payment_event.order_id = p_order_id
    and payment_event.provider = 'mercadopago'
    and payment_event.external_payment_id = btrim(coalesce(p_payment_operation_id, ''))
    and payment_event.provider_status = 'approved'
    and payment_event.outcome in ('payment_validated', 'applied')
    and round(payment_event.amount, 2) = round(p_amount, 2)
    and upper(payment_event.currency) = upper(btrim(coalesce(p_currency, '')))
  order by payment_event.id desc
  limit 1;

  if not found
     or v_payment_event.provider_paid_at is null
     or v_payment_event.provider_paid_at is distinct from p_issued_at
     or not public.mercadopago_payment_evidence_matches_voucher(
       v_payment_event.provider_payload,
       p_payment_operation_id,
       v_authorization_code,
       p_amount,
       p_currency,
       p_issued_at
     ) then
    raise exception 'Mercado Pago voucher is not bound to complete provider evidence'
      using errcode = '23514';
  end if;

  return public.record_online_order_official_document_fiscal_base(
    p_tenant_id, p_order_id, p_document_kind, p_provider,
    p_provider_document_id, p_fiscal_validity, p_amount, p_currency,
    p_issued_at, p_artifact_url, p_artifact_sha256, p_status,
    p_source_event_key, p_payment_operation_id, p_document_type, p_folio,
    p_metadata, p_voucher_fiscal_evidence
  );
end;
$$;

revoke all on function public.record_online_order_official_document(
  uuid, uuid, text, text, text, text, numeric, text, timestamp with time zone,
  text, text, text, text, text, text, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_official_document(
  uuid, uuid, text, text, text, text, numeric, text, timestamp with time zone,
  text, text, text, text, text, text, text, jsonb, jsonb
) to service_role;

comment on function public.mercadopago_payment_evidence_matches_voucher(
  jsonb, text, text, numeric, text, timestamp with time zone
) is
  'Fail-closed internal predicate binding a claimed card voucher to the exact sanitized Mercado Pago Payments API evidence. Payment-flow URLs never qualify as documents.';

comment on function public.record_online_order_official_document(
  uuid, uuid, text, text, text, text, numeric, text, timestamp with time zone,
  text, text, text, text, text, text, text, jsonb, jsonb
) is
  'Service-role append-only recorder. Mercado Pago vouchers additionally require a verified SII model, complete fiscal artifact fields and an exact eligible-card Payments API evidence binding; approved payment state alone is never a voucher or DTE.';

commit;
