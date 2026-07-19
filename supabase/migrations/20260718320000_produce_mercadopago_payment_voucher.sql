-- Production deployment is tracked by supabase_migrations.schema_migrations.
--
-- A validated approved Mercado Pago response may expose a credential-free
-- provider-hosted payment receipt through
-- transaction_details.external_resource_url. This migration records that
-- artifact as `mercadopago_payment_voucher`, explicitly NOT as a Chilean
-- boleta/DTE. The separately hardened `payment_voucher` path remains the only
-- voucher-as-boleta path and still requires the verified SII evidence model.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.mercadopago_payment_voucher_url_is_safe(
  p_url text
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  v_url text := btrim(coalesce(p_url, ''));
  v_host text;
begin
  if v_url = '' or length(v_url) > 2048
     or v_url !~* '^https://[^/?#:@[:space:]]+(/[^#[:space:]]*)?$'
     or v_url ~ '#'
     or v_url ~* '[?&](access[_-]?token|token|api[_-]?key|secret|signature|sig|authorization|auth|password|credential)=' then
    return false;
  end if;

  v_host := lower(substring(v_url from '^https://([^/:?#]+)'));
  return v_host ~ '(^|[.])(mercadopago|mercadolibre)[.](cl|com([.][a-z]{2})?)$';
end;
$$;

revoke all on function public.mercadopago_payment_voucher_url_is_safe(text)
  from public, anon, authenticated, service_role;

-- Keep explicit absence/unsafe/incomplete evidence in the immutable payment
-- event without retaining an unbounded provider response or any credential.
create or replace function public.sanitize_mercadopago_payment_evidence(
  p_payload jsonb
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'operation_number', nullif(left(btrim(coalesce(p_payload->>'operation_number', '')), 160), ''),
    'status_detail', nullif(left(btrim(coalesce(p_payload->>'status_detail', '')), 160), ''),
    'payment_type_id', nullif(left(btrim(coalesce(p_payload->>'payment_type_id', '')), 96), ''),
    'payment_method_id', nullif(left(btrim(coalesce(p_payload->>'payment_method_id', '')), 96), ''),
    'merchant_order_id', nullif(left(btrim(coalesce(p_payload->>'merchant_order_id', '')), 160), ''),
    'authorization_code', nullif(left(btrim(coalesce(p_payload->>'authorization_code', '')), 160), ''),
    'date_created', nullif(left(btrim(coalesce(p_payload->>'date_created', '')), 64), ''),
    'date_approved', nullif(left(btrim(coalesce(p_payload->>'date_approved', '')), 64), ''),
    'date_last_updated', nullif(left(btrim(coalesce(p_payload->>'date_last_updated', '')), 64), ''),
    'transaction_amount', case
      when coalesce(p_payload->>'transaction_amount', '') ~ '^-?[0-9]{1,14}([.][0-9]{1,4})?$'
        then (p_payload->>'transaction_amount')::numeric
    end,
    'currency_id', case
      when upper(btrim(coalesce(p_payload->>'currency_id', ''))) ~ '^[A-Z]{3}$'
        then upper(btrim(p_payload->>'currency_id'))
    end,
    'total_paid_amount', case
      when coalesce(p_payload->>'total_paid_amount', '') ~ '^-?[0-9]{1,14}([.][0-9]{1,4})?$'
        then (p_payload->>'total_paid_amount')::numeric
    end,
    'card_last_four_digits', case
      when coalesce(p_payload->>'card_last_four_digits', '') ~ '^[0-9]{4}$'
        then p_payload->>'card_last_four_digits'
    end,
    'processing_mode', nullif(left(btrim(coalesce(p_payload->>'processing_mode', '')), 96), ''),
    'point_of_interaction_type', nullif(left(btrim(coalesce(p_payload->>'point_of_interaction_type', '')), 96), ''),
    'point_of_interaction_sub_type', nullif(left(btrim(coalesce(p_payload->>'point_of_interaction_sub_type', '')), 96), ''),
    'point_of_interaction_unit', nullif(left(btrim(coalesce(p_payload->>'point_of_interaction_unit', '')), 96), ''),
    'point_of_interaction_sub_unit', nullif(left(btrim(coalesce(p_payload->>'point_of_interaction_sub_unit', '')), 96), ''),
    'mercadopago_payment_voucher', case
      when jsonb_typeof(p_payload->'mercadopago_payment_voucher') = 'object'
       and p_payload->'mercadopago_payment_voucher'->>'availability'
         in ('available', 'absent', 'rejected_unsafe', 'incomplete', 'not_applicable')
       and p_payload->'mercadopago_payment_voucher'->>'fiscal_validity'
         = 'not_a_tax_document'
       and (
         p_payload->'mercadopago_payment_voucher'->>'availability' <> 'available'
         or public.mercadopago_payment_voucher_url_is_safe(
           p_payload->'mercadopago_payment_voucher'->>'url'
         )
       )
      then jsonb_strip_nulls(jsonb_build_object(
        'source', 'transaction_details.external_resource_url',
        'availability', p_payload->'mercadopago_payment_voucher'->>'availability',
        'fiscal_validity', 'not_a_tax_document',
        'reason', case
          when p_payload->'mercadopago_payment_voucher'->>'availability' <> 'available'
            then nullif(left(btrim(coalesce(
              p_payload->'mercadopago_payment_voucher'->>'reason', ''
            )), 96), '')
        end,
        'url', case
          when p_payload->'mercadopago_payment_voucher'->>'availability' = 'available'
            then btrim(p_payload->'mercadopago_payment_voucher'->>'url')
        end
      ))
    end
  ));
$$;

revoke all on function public.sanitize_mercadopago_payment_evidence(jsonb)
  from public, anon, authenticated, service_role;

alter table public.online_order_official_documents
  add column if not exists artifact_hash_scope text not null default 'content';

alter table public.online_order_official_documents
  drop constraint if exists online_order_official_documents_document_kind_check,
  drop constraint if exists online_order_official_documents_fiscal_validity_check,
  drop constraint if exists online_order_official_documents_kind_shape,
  drop constraint if exists online_order_official_documents_artifact_hash_scope_check;

alter table public.online_order_official_documents
  add constraint online_order_official_documents_document_kind_check check (
    document_kind in (
      'payment_voucher',
      'mercadopago_payment_voucher',
      'tax_document'
    )
  ),
  add constraint online_order_official_documents_fiscal_validity_check check (
    fiscal_validity in (
      'voucher_valid_as_boleta',
      'not_a_tax_document',
      'official_chilean_dte'
    )
  ),
  add constraint online_order_official_documents_artifact_hash_scope_check check (
    artifact_hash_scope in ('content', 'reference_url')
  ),
  add constraint online_order_official_documents_kind_shape check (
    (
      document_kind = 'payment_voucher'
      and provider = 'mercadopago'
      and status = 'approved'
      and fiscal_validity = 'voucher_valid_as_boleta'
      and payment_operation_id is not null
      and document_type is null
      and folio is null
      and artifact_hash_scope = 'content'
    )
    or (
      document_kind = 'mercadopago_payment_voucher'
      and provider = 'mercadopago'
      and status = 'approved'
      and fiscal_validity = 'not_a_tax_document'
      and payment_operation_id is not null
      and document_type is null
      and folio is null
      and artifact_hash_scope = 'reference_url'
    )
    or (
      document_kind = 'tax_document'
      and status in ('issued', 'accepted')
      and fiscal_validity = 'official_chilean_dte'
      and document_type is not null
      and folio is not null
      and artifact_hash_scope = 'content'
    )
  );

alter table public.transactional_email_outbox
  drop constraint if exists transactional_email_outbox_message_kind_check;
alter table public.transactional_email_outbox
  add constraint transactional_email_outbox_message_kind_check check (
    message_kind in (
      'order_received',
      'payment_confirmed',
      'processing',
      'ready_for_pickup',
      'shipped',
      'delivered',
      'cancelled',
      'refund_completed',
      'mercadopago_payment_voucher_available',
      'payment_voucher_available',
      'tax_document_issued'
    )
  );

create or replace function public.record_mercadopago_payment_voucher_document(
  p_tenant_id uuid,
  p_order_id uuid,
  p_provider_document_id text,
  p_amount numeric,
  p_currency text,
  p_issued_at timestamp with time zone,
  p_artifact_url text,
  p_artifact_sha256 text,
  p_source_event_key text,
  p_payment_operation_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.online_orders%rowtype;
  v_invoice_id uuid;
  v_payment_event public.sales_channel_payment_events%rowtype;
  v_existing public.online_order_official_documents%rowtype;
  v_provider_document_id text := btrim(coalesce(p_provider_document_id, ''));
  v_payment_operation_id text := btrim(coalesce(p_payment_operation_id, ''));
  v_currency text := upper(btrim(coalesce(p_currency, '')));
  v_artifact_url text := btrim(coalesce(p_artifact_url, ''));
  v_artifact_sha256 text := lower(btrim(coalesce(p_artifact_sha256, '')));
  v_source_event_key text := btrim(coalesce(p_source_event_key, ''));
  v_metadata jsonb;
  v_reference_sha256 text;
  v_fingerprint text;
  v_source_lock bigint;
  v_document_lock bigint;
  v_document_id uuid;
begin
  if p_tenant_id is null or p_order_id is null
     or v_provider_document_id <> 'payment:' || v_payment_operation_id
     or v_payment_operation_id = '' or length(v_payment_operation_id) > 160
     or v_source_event_key <> 'mercadopago_payment_voucher:' || v_payment_operation_id
     or p_amount is null or p_amount <= 0
     or v_currency !~ '^[A-Z]{3}$'
     or p_issued_at is null
     or p_issued_at > clock_timestamp() + interval '5 minutes'
     or not public.mercadopago_payment_voucher_url_is_safe(v_artifact_url) then
    raise exception 'Mercado Pago payment voucher evidence is incomplete or unsafe'
      using errcode = '23514';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Mercado Pago payment voucher metadata must be an object'
      using errcode = '22023';
  end if;

  v_reference_sha256 := encode(extensions.digest(
    convert_to(v_artifact_url, 'UTF8'),
    'sha256'
  ), 'hex');
  if v_artifact_sha256 is distinct from v_reference_sha256 then
    raise exception 'Mercado Pago payment voucher reference hash is invalid'
      using errcode = '23514';
  end if;
  v_metadata := public.sanitize_online_order_document_metadata(p_metadata);

  select * into v_order
  from public.online_orders orders
  where orders.id = p_order_id
    and orders.tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Online order not found for Mercado Pago payment voucher'
      using errcode = '23503';
  end if;
  if v_order.payment_status <> 'paid'
     or lower(btrim(coalesce(v_order.payment_method, '')))
       not in ('mercadopago', 'mercado_pago')
     or nullif(btrim(coalesce(v_order.payment_reference, '')), '')
       is distinct from v_payment_operation_id
     or round(v_order.total, 2) <> round(p_amount, 2)
     or p_issued_at < v_order.created_at - interval '5 minutes' then
    raise exception 'Mercado Pago payment voucher does not match the paid order'
      using errcode = '23514';
  end if;
  if v_currency <> upper(coalesce(
    (select tenant.currency from public.tenants tenant where tenant.id = p_tenant_id),
    'CLP'
  )) then
    raise exception 'Mercado Pago payment voucher currency does not match tenant'
      using errcode = '23514';
  end if;

  if v_order.sales_invoice_id is not null then
    select invoice.id into v_invoice_id
    from public.sales_invoices invoice
    where invoice.id = v_order.sales_invoice_id
      and invoice.tenant_id = p_tenant_id
      and round(invoice.total, 2) = round(p_amount, 2);
    if not found then
      raise exception 'Mercado Pago payment voucher invoice binding is invalid'
        using errcode = '23503';
    end if;
  end if;

  select payment_event.* into v_payment_event
  from public.sales_channel_payment_events payment_event
  where payment_event.tenant_id = p_tenant_id
    and payment_event.order_id = p_order_id
    and payment_event.provider = 'mercadopago'
    and payment_event.external_payment_id = v_payment_operation_id
    and payment_event.provider_status = 'approved'
    and payment_event.outcome in ('payment_validated', 'applied')
    and payment_event.provider_paid_at = p_issued_at
    and round(payment_event.amount, 2) = round(p_amount, 2)
    and upper(payment_event.currency) = v_currency
    and payment_event.provider_payload->'mercadopago_payment_voucher'
      @> jsonb_build_object(
        'source', 'transaction_details.external_resource_url',
        'availability', 'available',
        'fiscal_validity', 'not_a_tax_document',
        'url', v_artifact_url
      )
  order by payment_event.id desc
  limit 1;

  if not found then
    raise exception 'Mercado Pago payment voucher lacks matching durable provider evidence'
      using errcode = '23514';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'tenant_id', p_tenant_id,
      'order_id', p_order_id,
      'sales_invoice_id', v_invoice_id,
      'document_kind', 'mercadopago_payment_voucher',
      'provider', 'mercadopago',
      'provider_document_id', v_provider_document_id,
      'payment_operation_id', v_payment_operation_id,
      'fiscal_validity', 'not_a_tax_document',
      'amount', round(p_amount, 2),
      'currency', v_currency,
      'issued_at', p_issued_at,
      'artifact_url', v_artifact_url,
      'artifact_sha256', v_reference_sha256,
      'artifact_hash_scope', 'reference_url',
      'status', 'approved'
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  v_source_lock := hashtextextended(
    p_tenant_id::text || ':' || v_source_event_key,
    0
  );
  v_document_lock := hashtextextended(
    p_tenant_id::text || ':mercadopago_payment_voucher:mercadopago:'
      || v_provider_document_id || ':approved',
    0
  );
  perform pg_advisory_xact_lock(least(v_source_lock, v_document_lock));
  if v_source_lock <> v_document_lock then
    perform pg_advisory_xact_lock(greatest(v_source_lock, v_document_lock));
  end if;

  select * into v_existing
  from public.online_order_official_documents document
  where document.tenant_id = p_tenant_id
    and (
      document.source_event_key = v_source_event_key
      or (
        document.document_kind = 'mercadopago_payment_voucher'
        and document.provider = 'mercadopago'
        and document.provider_document_id = v_provider_document_id
        and document.status = 'approved'
      )
    )
  order by (document.source_event_key = v_source_event_key) desc
  limit 1;

  if found then
    if v_existing.evidence_fingerprint <> v_fingerprint then
      raise exception 'Mercado Pago payment voucher idempotency conflict'
        using errcode = '23000';
    end if;
    perform public.enqueue_transactional_email_from_official_document_id(v_existing.id);
    return v_existing.id;
  end if;

  insert into public.online_order_official_documents (
    tenant_id,
    order_id,
    sales_invoice_id,
    document_kind,
    provider,
    provider_document_id,
    payment_operation_id,
    fiscal_validity,
    document_type,
    folio,
    amount,
    currency,
    issued_at,
    artifact_url,
    artifact_sha256,
    artifact_hash_scope,
    status,
    source_event_key,
    evidence_fingerprint,
    metadata,
    recorded_by
  ) values (
    p_tenant_id,
    p_order_id,
    v_invoice_id,
    'mercadopago_payment_voucher',
    'mercadopago',
    v_provider_document_id,
    v_payment_operation_id,
    'not_a_tax_document',
    null,
    null,
    round(p_amount, 2),
    v_currency,
    p_issued_at,
    v_artifact_url,
    v_reference_sha256,
    'reference_url',
    'approved',
    v_source_event_key,
    v_fingerprint,
    v_metadata,
    auth.uid()
  ) returning id into v_document_id;

  return v_document_id;
end;
$$;

revoke all on function public.record_mercadopago_payment_voucher_document(
  uuid, uuid, text, numeric, text, timestamp with time zone, text, text, text,
  text, jsonb
) from public, anon, authenticated, service_role;

-- Preserve the hardened fiscal recorder exactly as-is, then add a narrow
-- non-fiscal branch under the same canonical service-role API.
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
    raise exception 'Canonical official-document recorder is missing'
      using errcode = '42883';
  end if;

  if v_public_body not like '%mercadopago-non-fiscal-payment-voucher-v1%' then
    if to_regprocedure(
      'public.record_online_order_official_document_pre_non_fiscal_base(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)'
    ) is not null then
      execute 'drop function public.record_online_order_official_document_pre_non_fiscal_base(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)';
    end if;
    execute 'alter function public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb) rename to record_online_order_official_document_pre_non_fiscal_base';
  end if;
end;
$$;

revoke all on function public.record_online_order_official_document_pre_non_fiscal_base(
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
-- mercadopago-non-fiscal-payment-voucher-v1
begin
  if lower(btrim(coalesce(p_document_kind, '')))
       = 'mercadopago_payment_voucher' then
    if lower(replace(btrim(coalesce(p_provider, '')), '_', '')) <> 'mercadopago'
       or lower(btrim(coalesce(p_fiscal_validity, ''))) <> 'not_a_tax_document'
       or lower(btrim(coalesce(p_status, ''))) <> 'approved'
       or p_document_type is not null
       or p_folio is not null
       or p_voucher_fiscal_evidence is not null then
      raise exception 'Mercado Pago payment voucher cannot claim fiscal validity'
        using errcode = '23514';
    end if;

    return public.record_mercadopago_payment_voucher_document(
      p_tenant_id,
      p_order_id,
      p_provider_document_id,
      p_amount,
      p_currency,
      p_issued_at,
      p_artifact_url,
      p_artifact_sha256,
      p_source_event_key,
      p_payment_operation_id,
      p_metadata
    );
  end if;

  return public.record_online_order_official_document_pre_non_fiscal_base(
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

create or replace function public.enqueue_mercadopago_payment_voucher_email(
  p_document_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_document public.online_order_official_documents%rowtype;
  v_order public.online_orders%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_recipient text;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
  v_source_event_key text;
  v_idempotency_key text;
  v_delivery_mode text := 'dry_run';
  v_state text := 'pending';
  v_suppression_reason text;
  v_outbox_id uuid;
begin
  select * into v_document
  from public.online_order_official_documents document
  where document.id = p_document_id
    and document.document_kind = 'mercadopago_payment_voucher'
    and document.provider = 'mercadopago'
    and document.status = 'approved'
    and document.fiscal_validity = 'not_a_tax_document'
    and document.artifact_hash_scope = 'reference_url'
    and public.mercadopago_payment_voucher_url_is_safe(document.artifact_url)
    and document.artifact_sha256 = encode(extensions.digest(
      convert_to(document.artifact_url, 'UTF8'),
      'sha256'
    ), 'hex');

  if not found then
    return null;
  end if;

  select * into v_order
  from public.online_orders orders
  where orders.id = v_document.order_id
    and orders.tenant_id = v_document.tenant_id
    and orders.sales_invoice_id is not distinct from v_document.sales_invoice_id
    and orders.payment_status = 'paid'
    and lower(btrim(coalesce(orders.payment_method, '')))
      in ('mercadopago', 'mercado_pago')
    and nullif(btrim(coalesce(orders.payment_reference, '')), '')
      is not distinct from v_document.payment_operation_id;

  if not found then
    return null;
  end if;

  if not exists (
    select 1
    from public.sales_channel_payment_events payment_event
    where payment_event.tenant_id = v_document.tenant_id
      and payment_event.order_id = v_document.order_id
      and payment_event.provider = 'mercadopago'
      and payment_event.external_payment_id = v_document.payment_operation_id
      and payment_event.provider_status = 'approved'
      and payment_event.outcome in ('payment_validated', 'applied')
      and payment_event.provider_payload->'mercadopago_payment_voucher'
        @> jsonb_build_object(
          'availability', 'available',
          'fiscal_validity', 'not_a_tax_document',
          'url', v_document.artifact_url
        )
  ) then
    return null;
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  if v_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    return null;
  end if;

  select * into v_tenant
  from public.tenants tenant
  where tenant.id = v_document.tenant_id;
  if not found then
    return null;
  end if;

  select * into v_settings
  from public.transactional_email_settings settings
  where settings.tenant_id = v_document.tenant_id;
  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url,
    v_tenant.custom_domain
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'name', item.product_name,
    'sku', item.product_sku,
    'quantity', item.quantity,
    'unitPrice', item.unit_price,
    'subtotal', item.subtotal
  ) order by item.created_at, item.id), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = v_order.id
    and item.tenant_id = v_order.tenant_id;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', 'mercadopago_payment_voucher_available',
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
      end,
      'storeUrl', v_store_url,
      'currency', v_document.currency,
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago')
    )),
    'customer', jsonb_build_object('name', v_order.customer_name),
    'order', jsonb_build_object(
      'id', v_order.id,
      'number', v_order.order_number,
      'status', v_order.status,
      'paymentStatus', v_order.payment_status,
      'createdAt', v_order.created_at,
      'deliveryType', v_order.delivery_type,
      'subtotal', v_order.subtotal,
      'shippingCost', v_order.shipping_cost,
      'discountAmount', v_order.discount_amount,
      'total', v_order.total
    ),
    'items', v_items,
    'document', jsonb_build_object(
      'kind', 'mercadopago_payment_voucher',
      'taxStatus', 'not_a_tax_document',
      'label', 'Comprobante de pago de Mercado Pago · No constituye boleta ni factura'
    ),
    'mercadoPagoPaymentVoucher', jsonb_build_object(
      'provider', 'Mercado Pago',
      'providerDocumentId', v_document.provider_document_id,
      'operationId', v_document.payment_operation_id,
      'status', v_document.status,
      'fiscalValidity', 'not_a_tax_document',
      'amount', v_document.amount,
      'currency', v_document.currency,
      'issuedAt', v_document.issued_at,
      'downloadUrl', v_document.artifact_url,
      'referenceSha256', v_document.artifact_sha256
    )
  );

  v_source_event_key := 'online_order_official_document:' || v_document.id::text;
  v_idempotency_key := 'txn-email:v1:' || encode(extensions.digest(
    convert_to(
      v_document.tenant_id::text || ':' || v_document.order_id::text || ':'
        || v_source_event_key || ':mercadopago_payment_voucher_available:'
        || v_recipient,
      'UTF8'
    ),
    'sha256'
  ), 'hex');

  select suppression.reason into v_suppression_reason
  from public.transactional_email_suppressions suppression
  where suppression.tenant_id = v_document.tenant_id
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
    tenant_id, order_id, order_event_id, source_event_key, message_kind,
    template_key, template_version, recipient_email, recipient_name,
    sender_name, sender_email, reply_to_email, subject, render_payload,
    attachment_manifest, idempotency_key, delivery_mode, state,
    suppression_reason
  ) values (
    v_document.tenant_id,
    v_document.order_id,
    null,
    v_source_event_key,
    'mercadopago_payment_voucher_available',
    'mercadopago_payment_voucher_available',
    1,
    v_recipient,
    nullif(btrim(v_order.customer_name), ''),
    nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    nullif(lower(btrim(v_settings.from_email)), ''),
    nullif(lower(btrim(v_settings.reply_to_email)), ''),
    format('Comprobante de Mercado Pago · %s', v_order.order_number),
    v_payload,
    '[]'::jsonb,
    v_idempotency_key,
    v_delivery_mode,
    v_state,
    v_suppression_reason
  )
  on conflict (idempotency_key) do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select outbox.id into v_outbox_id
    from public.transactional_email_outbox outbox
    where outbox.idempotency_key = v_idempotency_key;
  end if;

  return v_outbox_id;
end;
$$;

revoke all on function public.enqueue_mercadopago_payment_voucher_email(uuid)
  from public, anon, authenticated, service_role;

do $$
declare
  v_public_body text;
begin
  select routine.prosrc into v_public_body
  from pg_proc routine
  where routine.oid = to_regprocedure(
    'public.enqueue_transactional_email_from_official_document_id(uuid)'
  );

  if v_public_body is null then
    raise exception 'Canonical official-document email gate is missing'
      using errcode = '42883';
  end if;

  if v_public_body not like '%mercadopago-non-fiscal-payment-voucher-email-v1%' then
    if to_regprocedure(
      'public.enqueue_txn_email_official_doc_pre_mp_base(uuid)'
    ) is not null then
      execute 'drop function public.enqueue_txn_email_official_doc_pre_mp_base(uuid)';
    end if;
    execute 'alter function public.enqueue_transactional_email_from_official_document_id(uuid) rename to enqueue_txn_email_official_doc_pre_mp_base';
  end if;
end;
$$;

revoke all on function public.enqueue_txn_email_official_doc_pre_mp_base(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.enqueue_transactional_email_from_official_document_id(
  p_document_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
-- mercadopago-non-fiscal-payment-voucher-email-v1
declare
  v_document_kind text;
begin
  select document.document_kind into v_document_kind
  from public.online_order_official_documents document
  where document.id = p_document_id;

  if v_document_kind = 'mercadopago_payment_voucher' then
    return public.enqueue_mercadopago_payment_voucher_email(p_document_id);
  end if;

  return public.enqueue_txn_email_official_doc_pre_mp_base(
    p_document_id
  );
end;
$$;

revoke all on function public.enqueue_transactional_email_from_official_document_id(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.enqueue_transactional_email_from_official_document_id(uuid)
  to service_role;

comment on column public.online_order_official_documents.artifact_hash_scope is
  'content for immutable fiscal files; reference_url for a provider-hosted non-fiscal receipt whose stored SHA-256 covers the credential-free HTTPS reference, not remote bytes.';
comment on function public.record_online_order_official_document(
  uuid, uuid, text, text, text, text, numeric, text, timestamp with time zone,
  text, text, text, text, text, text, text, jsonb, jsonb
) is
  'Service-role append-only recorder. mercadopago_payment_voucher is a non-fiscal provider payment receipt bound to an approved durable payment observation; payment_voucher remains the separately verified SII voucher-as-boleta path.';
comment on function public.sanitize_mercadopago_payment_evidence(jsonb) is
  'Bounded Mercado Pago evidence allow-list including explicit non-fiscal payment-voucher availability or absence. Credentialed/unsafe URLs are never retained.';

commit;
