-- Immutable official-document evidence for online orders.
--
-- This migration intentionally does not derive legal documents from an order,
-- an internal sales invoice, or a payment status. Only the service-role
-- recorder may append evidence, and it requires a complete immutable HTTPS
-- artifact. Mercado Pago vouchers additionally require a matching approved,
-- applied provider-payment event; bank transfers can never produce vouchers.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- These composite keys let the ledger enforce the tenant graph with foreign
-- keys instead of trusting application-provided tenant identifiers.
create unique index if not exists uq_online_orders_tenant_id_id
  on public.online_orders(tenant_id, id);
create unique index if not exists uq_sales_invoices_tenant_id_id
  on public.sales_invoices(tenant_id, id);

create table if not exists public.online_order_official_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  order_id uuid not null,
  sales_invoice_id uuid not null,
  document_kind text not null check (
    document_kind in ('payment_voucher', 'tax_document')
  ),
  provider text not null check (
    provider = lower(btrim(provider))
    and provider ~ '^[a-z0-9][a-z0-9_-]{0,63}$'
  ),
  provider_document_id text not null check (
    nullif(btrim(provider_document_id), '') is not null
    and length(provider_document_id) <= 256
  ),
  payment_operation_id text check (
    payment_operation_id is null
    or (
      nullif(btrim(payment_operation_id), '') is not null
      and length(payment_operation_id) <= 256
    )
  ),
  fiscal_validity text not null check (
    fiscal_validity in (
      'voucher_valid_as_boleta',
      'official_chilean_dte'
    )
  ),
  document_type text check (
    document_type is null
    or (
      nullif(btrim(document_type), '') is not null
      and length(document_type) <= 128
    )
  ),
  folio text check (
    folio is null
    or (
      nullif(btrim(folio), '') is not null
      and length(folio) <= 128
    )
  ),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  issued_at timestamp with time zone not null,
  artifact_url text not null check (
    artifact_url ~* '^https://[^[:space:]/@]+(/[^[:space:]]*)?$'
  ),
  artifact_sha256 text not null check (
    artifact_sha256 ~ '^[0-9a-f]{64}$'
  ),
  status text not null check (status in ('approved', 'issued', 'accepted')),
  source_event_key text not null check (
    nullif(btrim(source_event_key), '') is not null
    and length(source_event_key) <= 256
  ),
  evidence_fingerprint text not null check (
    evidence_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  metadata jsonb not null default '{}'::jsonb check (
    jsonb_typeof(metadata) = 'object'
  ),
  recorded_by uuid references auth.users(id) on delete set null,
  recorded_at timestamp with time zone not null default clock_timestamp(),
  constraint online_order_official_documents_order_tenant_fkey
    foreign key (tenant_id, order_id)
    references public.online_orders(tenant_id, id) on delete restrict,
  constraint online_order_official_documents_invoice_tenant_fkey
    foreign key (tenant_id, sales_invoice_id)
    references public.sales_invoices(tenant_id, id) on delete restrict,
  constraint online_order_official_documents_kind_shape check (
    (
      document_kind = 'payment_voucher'
      and provider = 'mercadopago'
      and status = 'approved'
      and fiscal_validity = 'voucher_valid_as_boleta'
      and payment_operation_id is not null
      and document_type is null
      and folio is null
    )
    or (
      document_kind = 'tax_document'
      and status in ('issued', 'accepted')
      and fiscal_validity = 'official_chilean_dte'
      and document_type is not null
      and folio is not null
    )
  ),
  unique (tenant_id, source_event_key),
  unique (
    tenant_id,
    document_kind,
    provider,
    provider_document_id,
    status
  )
);

create index if not exists idx_online_order_official_documents_order
  on public.online_order_official_documents(
    tenant_id,
    order_id,
    issued_at desc,
    id desc
  );
create index if not exists idx_online_order_official_documents_invoice
  on public.online_order_official_documents(
    tenant_id,
    sales_invoice_id,
    issued_at desc,
    id desc
  );
create index if not exists idx_online_order_official_documents_operation
  on public.online_order_official_documents(
    tenant_id,
    provider,
    payment_operation_id
  )
  where payment_operation_id is not null;

alter table public.online_order_official_documents enable row level security;

create or replace function public.has_active_official_document_staff_access(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and coalesce(profile.is_active, true)
  );
$$;

revoke all on function public.has_active_official_document_staff_access(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.has_active_official_document_staff_access(uuid)
  to authenticated;

drop policy if exists online_order_official_documents_staff_read
  on public.online_order_official_documents;
create policy online_order_official_documents_staff_read
  on public.online_order_official_documents
  for select to authenticated
  using (public.has_active_official_document_staff_access(tenant_id));

revoke all on public.online_order_official_documents
  from public, anon, authenticated, service_role;
grant select on public.online_order_official_documents to authenticated;

create or replace function public.prevent_online_order_official_document_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Online order official documents are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_online_order_official_document_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_online_order_official_documents_immutable
  on public.online_order_official_documents;
create trigger trg_online_order_official_documents_immutable
  before update or delete on public.online_order_official_documents
  for each row execute function public.prevent_online_order_official_document_mutation();

-- Strict allow-list projection: raw provider payloads, authorization headers,
-- tokens, signatures, cookies, API keys and customer/payment secrets are never
-- copied into the official-document ledger.
create or replace function public.sanitize_online_order_document_metadata(
  p_metadata jsonb
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'source', nullif(left(btrim(coalesce(p_metadata->>'source', '')), 80), ''),
    'provider_event_id', nullif(
      left(btrim(coalesce(p_metadata->>'provider_event_id', '')), 256),
      ''
    ),
    'provider_status_detail', nullif(
      left(btrim(coalesce(p_metadata->>'provider_status_detail', '')), 256),
      ''
    ),
    'document_series', nullif(
      left(btrim(coalesce(p_metadata->>'document_series', '')), 128),
      ''
    ),
    'mime_type', case
      when lower(btrim(coalesce(p_metadata->>'mime_type', '')))
        in ('application/pdf', 'application/xml', 'text/xml')
      then lower(btrim(p_metadata->>'mime_type'))
      else null
    end,
    'artifact_size_bytes', case
      when coalesce(p_metadata->>'artifact_size_bytes', '') ~ '^[0-9]{1,15}$'
      then (p_metadata->>'artifact_size_bytes')::bigint
      else null
    end,
    'provider_created_at', case
      when coalesce(p_metadata->>'provider_created_at', '')
        ~ '^\d{4}-\d{2}-\d{2}T'
      then left(p_metadata->>'provider_created_at', 64)
      else null
    end,
    'provider_updated_at', case
      when coalesce(p_metadata->>'provider_updated_at', '')
        ~ '^\d{4}-\d{2}-\d{2}T'
      then left(p_metadata->>'provider_updated_at', 64)
      else null
    end
  ));
$$;

revoke all on function public.sanitize_online_order_document_metadata(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.enqueue_transactional_email_from_official_document_id(
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
  v_message_kind text;
  v_recipient text;
  v_subject text;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
  v_attachment_manifest jsonb;
  v_source_event_key text;
  v_idempotency_key text;
  v_delivery_mode text := 'dry_run';
  v_state text := 'pending';
  v_suppression_reason text;
  v_outbox_id uuid;
begin
  select * into v_document
  from public.online_order_official_documents
  where id = p_document_id;

  if not found then
    return null;
  end if;

  -- Independent defense in depth. A complete order/payment state is required
  -- in addition to the immutable document row.
  if v_document.document_kind = 'payment_voucher' then
    if v_document.provider <> 'mercadopago'
       or v_document.status <> 'approved'
       or v_document.fiscal_validity <> 'voucher_valid_as_boleta'
       or nullif(v_document.payment_operation_id, '') is null then
      return null;
    end if;
    v_message_kind := 'payment_voucher_available';
  elsif v_document.document_kind = 'tax_document' then
    if v_document.status not in ('issued', 'accepted')
       or v_document.fiscal_validity <> 'official_chilean_dte'
       or nullif(v_document.document_type, '') is null
       or nullif(v_document.folio, '') is null then
      return null;
    end if;
    v_message_kind := 'tax_document_issued';
  else
    return null;
  end if;

  select * into v_order
  from public.online_orders
  where id = v_document.order_id
    and tenant_id = v_document.tenant_id
    and sales_invoice_id = v_document.sales_invoice_id
    and payment_status = 'paid';

  if not found then
    return null;
  end if;

  if v_message_kind = 'payment_voucher_available'
     and (
       lower(btrim(coalesce(v_order.payment_method, '')))
         not in ('mercadopago', 'mercado_pago')
       or nullif(btrim(coalesce(v_order.payment_reference, '')), '')
         is distinct from v_document.payment_operation_id
     ) then
    return null;
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  if v_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return null;
  end if;

  select * into v_tenant
  from public.tenants
  where id = v_document.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = v_document.tenant_id;

  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url,
    v_tenant.custom_domain
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', item.product_name,
      'sku', item.product_sku,
      'quantity', item.quantity,
      'unitPrice', item.unit_price,
      'subtotal', item.subtotal
    ) order by item.created_at, item.id
  ), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = v_order.id
    and item.tenant_id = v_order.tenant_id;

  v_subject := case v_message_kind
    when 'payment_voucher_available'
      then format('Comprobante oficial de pago · %s', v_order.order_number)
    when 'tax_document_issued'
      then format('Documento tributario emitido · %s', v_order.order_number)
  end;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', v_message_kind,
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$'
          then v_tenant.logo_url
        else null
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
      'kind', v_document.document_kind,
      'taxStatus', v_document.fiscal_validity,
      'label', case v_message_kind
        when 'payment_voucher_available'
          then 'Comprobante oficial de pago válido como boleta'
        else 'Documento tributario electrónico oficial'
      end
    )
  );

  if v_message_kind = 'payment_voucher_available' then
    v_payload := v_payload || jsonb_build_object(
      'officialPaymentVoucher', jsonb_build_object(
        'provider', v_document.provider,
        'providerDocumentId', v_document.provider_document_id,
        'operationId', v_document.payment_operation_id,
        'status', v_document.status,
        'fiscalValidity', v_document.fiscal_validity,
        'amount', v_document.amount,
        'currency', v_document.currency,
        'issuedAt', v_document.issued_at,
        'downloadUrl', v_document.artifact_url,
        'artifactSha256', v_document.artifact_sha256
      )
    );
  else
    v_payload := v_payload || jsonb_build_object(
      'officialTaxDocument', jsonb_build_object(
        'provider', v_document.provider,
        'providerDocumentId', v_document.provider_document_id,
        'documentType', v_document.document_type,
        'folio', v_document.folio,
        'status', v_document.status,
        'fiscalValidity', v_document.fiscal_validity,
        'amount', v_document.amount,
        'currency', v_document.currency,
        'issuedAt', v_document.issued_at,
        'downloadUrl', v_document.artifact_url,
        'artifactSha256', v_document.artifact_sha256
      )
    );
  end if;

  v_attachment_manifest := jsonb_build_array(jsonb_strip_nulls(
    jsonb_build_object(
      'kind', v_document.document_kind,
      'url', v_document.artifact_url,
      'sha256', v_document.artifact_sha256,
      'mimeType', coalesce(
        v_document.metadata->>'mime_type',
        'application/pdf'
      ),
      'providerDocumentId', v_document.provider_document_id,
      'issuedAt', v_document.issued_at
    )
  ));

  v_source_event_key := 'online_order_official_document:' || v_document.id::text;
  v_idempotency_key := 'txn-email:v1:' || encode(extensions.digest(
    convert_to(
      v_document.tenant_id::text || ':' || v_document.order_id::text || ':'
        || v_source_event_key || ':' || v_message_kind || ':' || v_recipient,
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
    attachment_manifest,
    idempotency_key,
    delivery_mode,
    state,
    suppression_reason
  ) values (
    v_document.tenant_id,
    v_document.order_id,
    null,
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
    v_attachment_manifest,
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
$$;

revoke all on function public.enqueue_transactional_email_from_official_document_id(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.enqueue_transactional_email_from_official_document_id(uuid)
  to service_role;

create or replace function public.enqueue_transactional_email_from_official_document()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_transactional_email_from_official_document_id(new.id);
  return new;
end;
$$;

revoke all on function public.enqueue_transactional_email_from_official_document()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_enqueue_transactional_email_from_official_document
  on public.online_order_official_documents;
create trigger trg_enqueue_transactional_email_from_official_document
  after insert on public.online_order_official_documents
  for each row execute function public.enqueue_transactional_email_from_official_document();

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
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.online_orders%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_existing public.online_order_official_documents%rowtype;
  v_document_kind text := lower(btrim(coalesce(p_document_kind, '')));
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_provider_document_id text := btrim(coalesce(p_provider_document_id, ''));
  v_payment_operation_id text := nullif(
    btrim(coalesce(p_payment_operation_id, '')),
    ''
  );
  v_fiscal_validity text := lower(btrim(coalesce(p_fiscal_validity, '')));
  v_document_type text := nullif(btrim(coalesce(p_document_type, '')), '');
  v_folio text := nullif(btrim(coalesce(p_folio, '')), '');
  v_currency text := upper(btrim(coalesce(p_currency, '')));
  v_artifact_url text := btrim(coalesce(p_artifact_url, ''));
  v_artifact_sha256 text := lower(btrim(coalesce(p_artifact_sha256, '')));
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_source_event_key text := btrim(coalesce(p_source_event_key, ''));
  v_metadata jsonb;
  v_fingerprint text;
  v_document_id uuid;
  v_source_lock bigint;
  v_document_lock bigint;
begin
  if v_provider in ('mercado_pago', 'mercado-pago') then
    v_provider := 'mercadopago';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Official document metadata must be a JSON object'
      using errcode = '22023';
  end if;
  v_metadata := public.sanitize_online_order_document_metadata(p_metadata);

  if p_tenant_id is null or p_order_id is null then
    raise exception 'Official document requires tenant and order identifiers'
      using errcode = '22023';
  end if;
  if v_provider_document_id = '' or length(v_provider_document_id) > 256 then
    raise exception 'Official document provider identifier is invalid'
      using errcode = '22023';
  end if;
  if v_source_event_key = '' or length(v_source_event_key) > 256 then
    raise exception 'Official document source event key is invalid'
      using errcode = '22023';
  end if;
  if v_provider !~ '^[a-z0-9][a-z0-9_-]{0,63}$' then
    raise exception 'Official document provider is invalid'
      using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Official document amount must be positive'
      using errcode = '22023';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Official document currency is invalid'
      using errcode = '22023';
  end if;
  if p_issued_at is null
     or p_issued_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'Official document issue time is invalid'
      using errcode = '22023';
  end if;
  if v_artifact_url !~* '^https://[^[:space:]/@]+(/[^[:space:]]*)?$' then
    raise exception 'Official document requires a secure HTTPS artifact URL'
      using errcode = '22023';
  end if;
  if v_artifact_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Official document requires a SHA-256 artifact hash'
      using errcode = '22023';
  end if;

  select * into v_order
  from public.online_orders
  where id = p_order_id
    and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Online order not found for official document'
      using errcode = '23503';
  end if;
  if v_order.sales_invoice_id is null then
    raise exception 'Official document requires the linked sales invoice'
      using errcode = '23514';
  end if;
  if v_order.payment_status <> 'paid' then
    raise exception 'Official document requires a paid online order'
      using errcode = '23514';
  end if;
  if p_issued_at < v_order.created_at - interval '5 minutes' then
    raise exception 'Official document predates the online order'
      using errcode = '23514';
  end if;

  select * into v_invoice
  from public.sales_invoices
  where id = v_order.sales_invoice_id
    and tenant_id = v_order.tenant_id;

  if not found then
    raise exception 'Online order sales invoice is missing or cross-tenant'
      using errcode = '23503';
  end if;
  if round(p_amount, 2) <> round(v_order.total, 2)
     or round(p_amount, 2) <> round(v_invoice.total, 2) then
    raise exception 'Official document amount does not match order and invoice'
      using errcode = '23514';
  end if;
  if v_currency <> upper(coalesce(
    (select tenant.currency from public.tenants tenant where tenant.id = p_tenant_id),
    'CLP'
  )) then
    raise exception 'Official document currency does not match tenant currency'
      using errcode = '23514';
  end if;

  if v_document_kind = 'payment_voucher' then
    if v_provider <> 'mercadopago'
       or lower(btrim(coalesce(v_order.payment_method, '')))
         not in ('mercadopago', 'mercado_pago') then
      raise exception 'Only Mercado Pago orders can record payment vouchers'
        using errcode = '23514';
    end if;
    if v_status <> 'approved'
       or v_fiscal_validity <> 'voucher_valid_as_boleta'
       or v_payment_operation_id is null
       or v_document_type is not null
       or v_folio is not null then
      raise exception 'Mercado Pago voucher evidence is incomplete'
        using errcode = '23514';
    end if;
    if nullif(btrim(coalesce(v_order.payment_reference, '')), '')
         is distinct from v_payment_operation_id then
      raise exception 'Voucher operation does not match the online order payment'
        using errcode = '23514';
    end if;
    if not exists (
      select 1
      from public.sales_channel_payment_events payment_event
      where payment_event.tenant_id = v_order.tenant_id
        and payment_event.order_id = v_order.id
        and payment_event.invoice_id = v_invoice.id
        and payment_event.provider = 'mercadopago'
        and payment_event.external_payment_id = v_payment_operation_id
        and payment_event.provider_status = 'approved'
        and payment_event.outcome = 'applied'
        and round(payment_event.amount, 2) = round(p_amount, 2)
        and upper(payment_event.currency) = v_currency
    ) then
      raise exception 'Approved payment status alone is not official voucher evidence'
        using errcode = '23514';
    end if;
  elsif v_document_kind = 'tax_document' then
    if v_status not in ('issued', 'accepted')
       or v_fiscal_validity <> 'official_chilean_dte'
       or v_document_type is null
       or v_folio is null then
      raise exception 'Official DTE evidence is incomplete'
        using errcode = '23514';
    end if;
  else
    raise exception 'Unsupported official document kind: %', v_document_kind
      using errcode = '22023';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'tenant_id', p_tenant_id,
      'order_id', p_order_id,
      'sales_invoice_id', v_invoice.id,
      'document_kind', v_document_kind,
      'provider', v_provider,
      'provider_document_id', v_provider_document_id,
      'payment_operation_id', v_payment_operation_id,
      'fiscal_validity', v_fiscal_validity,
      'document_type', v_document_type,
      'folio', v_folio,
      'amount', round(p_amount, 2),
      'currency', v_currency,
      'issued_at', p_issued_at,
      'artifact_url', v_artifact_url,
      'artifact_sha256', v_artifact_sha256,
      'status', v_status
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  v_source_lock := hashtextextended(
    p_tenant_id::text || ':' || v_source_event_key,
    0
  );
  v_document_lock := hashtextextended(
    p_tenant_id::text || ':' || v_document_kind || ':' || v_provider || ':'
      || v_provider_document_id || ':' || v_status,
    0
  );

  -- Serialize both retry identities in a deterministic order. Concurrent
  -- provider callbacks may carry different event keys for the same official
  -- artifact; neither path can leak a unique-violation race to the caller.
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
        document.document_kind = v_document_kind
        and document.provider = v_provider
        and document.provider_document_id = v_provider_document_id
        and document.status = v_status
      )
    )
  order by (document.source_event_key = v_source_event_key) desc
  limit 1;

  if found then
    if v_existing.evidence_fingerprint <> v_fingerprint then
      raise exception 'Official document idempotency key conflicts with different evidence'
        using errcode = '23000';
    end if;
    perform public.enqueue_transactional_email_from_official_document_id(
      v_existing.id
    );
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
    status,
    source_event_key,
    evidence_fingerprint,
    metadata,
    recorded_by
  ) values (
    p_tenant_id,
    p_order_id,
    v_invoice.id,
    v_document_kind,
    v_provider,
    v_provider_document_id,
    v_payment_operation_id,
    v_fiscal_validity,
    v_document_type,
    v_folio,
    round(p_amount, 2),
    v_currency,
    p_issued_at,
    v_artifact_url,
    v_artifact_sha256,
    v_status,
    v_source_event_key,
    v_fingerprint,
    v_metadata,
    auth.uid()
  )
  returning id into v_document_id;

  return v_document_id;
end;
$$;

revoke all on function public.record_online_order_official_document(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_official_document(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) to service_role;

comment on table public.online_order_official_documents is
  'Append-only tenant-scoped official artifact evidence. Neither payment status nor an internal sales invoice is legal-document evidence.';
comment on column public.online_order_official_documents.metadata is
  'Strict allow-list metadata projection; raw provider payloads and secrets are forbidden.';
comment on function public.record_online_order_official_document(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) is
  'Service-role-only idempotent recorder for complete official online-order document evidence.';

commit;
