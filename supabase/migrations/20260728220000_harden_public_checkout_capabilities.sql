-- NOT DEPLOYED.
--
-- Make public checkout payment availability a tenant-scoped server contract
-- and freeze the storefront identity used by customer order artifacts.
--
-- Forward behavior:
--   * public callers see only method availability and safe reason codes;
--   * a first checkout attempt fails before order insertion when its selected
--     method is not effectively configured;
--   * an exact idempotent replay remains recoverable if configuration changes;
--   * new orders receive one immutable server-derived storefront snapshot.
--
-- Recovery:
--   This migration is additive. The prior function definitions can be restored
--   without deleting snapshot rows. Snapshot rows deliberately reject mutation.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table if not exists public.online_order_storefront_snapshots (
  order_id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  identity_snapshot jsonb not null,
  captured_at timestamptz not null default clock_timestamp(),
  constraint online_order_storefront_snapshots_order_tenant_fkey
    foreign key (tenant_id, order_id)
    references public.online_orders(tenant_id, id)
    on delete restrict,
  constraint online_order_storefront_snapshots_identity_object_check
    check (jsonb_typeof(identity_snapshot) = 'object')
);

create index if not exists idx_online_order_storefront_snapshots_tenant
  on public.online_order_storefront_snapshots(tenant_id);

alter table public.online_order_storefront_snapshots enable row level security;

revoke all on table public.online_order_storefront_snapshots
  from public, anon, authenticated;
grant select on table public.online_order_storefront_snapshots to service_role;

create or replace function public.prevent_online_order_storefront_snapshot_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  raise exception 'Online order storefront snapshots are immutable'
    using errcode = '55000';
end;
$$;

revoke all on function
  public.prevent_online_order_storefront_snapshot_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_online_order_storefront_snapshots_immutable
  on public.online_order_storefront_snapshots;
create trigger trg_online_order_storefront_snapshots_immutable
  before update or delete on public.online_order_storefront_snapshots
  for each row
  execute function public.prevent_online_order_storefront_snapshot_mutation();

create or replace function public.resolve_public_checkout_capabilities(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  mercadopago_access_token_value text;
  store_url_value text;
  custom_domain_value text;
  transfer_bank_name_value text;
  transfer_account_type_value text;
  transfer_account_number_value text;
  transfer_account_holder_value text;
  transfer_rut_value text;
  store_origin_ready boolean := false;
  mercadopago_available boolean := false;
  transfer_available boolean := false;
begin
  select
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'mercadopago_access_token'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_url'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'payment_transfer_bank_name'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'payment_transfer_account_type'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'payment_transfer_account_number'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'payment_transfer_account_holder'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'payment_transfer_rut')
  into
    mercadopago_access_token_value,
    store_url_value,
    transfer_bank_name_value,
    transfer_account_type_value,
    transfer_account_number_value,
    transfer_account_holder_value,
    transfer_rut_value
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and setting.key in (
      'mercadopago_access_token',
      'store_url',
      'payment_transfer_bank_name',
      'payment_transfer_account_type',
      'payment_transfer_account_number',
      'payment_transfer_account_holder',
      'payment_transfer_rut'
    );

  select nullif(btrim(tenant.custom_domain), '')
  into custom_domain_value
  from public.tenants tenant
  where tenant.id = p_tenant_id
    and tenant.is_active is true;

  if not found then
    return jsonb_build_object(
      'schemaVersion', 1,
      'methods', jsonb_build_array(
        jsonb_build_object(
          'code', 'mercadopago',
          'available', false,
          'reasonCode', 'storefront_unavailable'
        ),
        jsonb_build_object(
          'code', 'transfer',
          'available', false,
          'reasonCode', 'storefront_unavailable'
        )
      )
    );
  end if;

  store_origin_ready :=
    lower(coalesce(store_url_value, '')) ~
      '^https://([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}(:[0-9]{1,5})?/?$'
    or lower(coalesce(custom_domain_value, '')) ~
      '^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$';

  mercadopago_available :=
    mercadopago_access_token_value is not null and store_origin_ready;
  transfer_available :=
    transfer_bank_name_value is not null
    and transfer_account_type_value is not null
    and transfer_account_number_value is not null
    and transfer_account_holder_value is not null
    and transfer_rut_value is not null;

  return jsonb_build_object(
    'schemaVersion', 1,
    'methods', jsonb_build_array(
      jsonb_build_object(
        'code', 'mercadopago',
        'available', mercadopago_available,
        'reasonCode', case
          when mercadopago_available then 'available'
          when mercadopago_access_token_value is null
            then 'configuration_incomplete'
          else 'store_origin_invalid'
        end
      ),
      jsonb_build_object(
        'code', 'transfer',
        'available', transfer_available,
        'reasonCode', case
          when transfer_available then 'available'
          else 'configuration_incomplete'
        end
      )
    )
  );
end;
$$;

revoke all on function public.resolve_public_checkout_capabilities(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.get_public_checkout_capabilities(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if p_tenant_id is null or not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Storefront tenant is invalid or inactive'
      using errcode = '42501';
  end if;

  return public.resolve_public_checkout_capabilities(p_tenant_id);
end;
$$;

revoke all on function public.get_public_checkout_capabilities(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_checkout_capabilities(uuid)
  to anon, authenticated, service_role;

comment on function public.get_public_checkout_capabilities(uuid) is
  'Tenant-scoped public checkout method availability. Returns safe method and reason codes only; credentials and transfer details never leave the server.';

create or replace function public.capture_online_order_storefront_snapshot(
  p_order_id uuid,
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_row record;
  company_name_value text;
  company_legal_name_value text;
  company_fantasy_name_value text;
  company_public_email_value text;
  company_email_value text;
  company_support_phone_value text;
  company_phone_value text;
  store_name_value text;
  business_name_value text;
  store_tagline_value text;
  store_description_value text;
  logo_url_value text;
  contact_email_value text;
  contact_phone_value text;
  display_name_value text;
  legal_name_value text;
  tagline_value text;
  effective_logo_url_value text;
  support_email_value text;
  support_phone_value text;
begin
  if not exists (
    select 1
    from public.online_orders customer_order
    where customer_order.id = p_order_id
      and customer_order.tenant_id = p_tenant_id
  ) then
    raise exception 'Checkout order tenant mismatch'
      using errcode = '42501';
  end if;

  select
    tenant.id,
    nullif(btrim(tenant.shop_name), '') as shop_name,
    nullif(btrim(tenant.logo_url), '') as logo_url,
    nullif(btrim(tenant.owner_email), '') as owner_email
  into strict tenant_row
  from public.tenants tenant
  where tenant.id = p_tenant_id
    and tenant.is_active is true;

  select
    selected_company.name,
    selected_company.legal_name,
    selected_company.fantasy_name,
    selected_company.public_email,
    selected_company.email,
    selected_company.support_phone,
    selected_company.phone
  into
    company_name_value,
    company_legal_name_value,
    company_fantasy_name_value,
    company_public_email_value,
    company_email_value,
    company_support_phone_value,
    company_phone_value
  from (
    select
      nullif(btrim(company.name), '') as name,
      nullif(btrim(company.legal_name), '') as legal_name,
      nullif(btrim(company.fantasy_name), '') as fantasy_name,
      nullif(btrim(company.public_email), '') as public_email,
      nullif(btrim(company.email), '') as email,
      nullif(btrim(company.support_phone), '') as support_phone,
      nullif(btrim(company.phone), '') as phone
    from public.companies company
    where company.tenant_id = p_tenant_id
    order by company.is_default desc nulls last, company.created_at, company.id
    limit 1
  ) selected_company
  right join (select true as singleton) singleton on true;

  select
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_name'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'business_name'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_tagline'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_description'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'logo_url'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'contact_email'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'contact_phone')
  into
    store_name_value,
    business_name_value,
    store_tagline_value,
    store_description_value,
    logo_url_value,
    contact_email_value,
    contact_phone_value
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and setting.key in (
      'store_name',
      'business_name',
      'store_tagline',
      'store_description',
      'logo_url',
      'contact_email',
      'contact_phone'
    );

  display_name_value := left(coalesce(
    store_name_value,
    business_name_value,
    company_fantasy_name_value,
    tenant_row.shop_name,
    company_name_value,
    'Tienda'
  ), 200);
  legal_name_value := left(coalesce(
    company_legal_name_value,
    company_name_value,
    business_name_value,
    display_name_value
  ), 240);
  tagline_value := left(coalesce(
    store_tagline_value,
    store_description_value,
    ''
  ), 500);
  effective_logo_url_value := coalesce(logo_url_value, tenant_row.logo_url);
  if effective_logo_url_value !~* '^https://[^[:space:]]+$' then
    effective_logo_url_value := null;
  end if;
  support_email_value := left(coalesce(
    contact_email_value,
    company_public_email_value,
    company_email_value,
    tenant_row.owner_email,
    ''
  ), 254);
  support_phone_value := left(coalesce(
    contact_phone_value,
    company_support_phone_value,
    company_phone_value,
    ''
  ), 60);

  insert into public.online_order_storefront_snapshots (
    order_id,
    tenant_id,
    identity_snapshot
  )
  values (
    p_order_id,
    p_tenant_id,
    jsonb_strip_nulls(jsonb_build_object(
      'schemaVersion', 1,
      'displayName', display_name_value,
      'legalName', nullif(legal_name_value, ''),
      'tagline', nullif(tagline_value, ''),
      'logoUrl', effective_logo_url_value,
      'supportEmail', nullif(support_email_value, ''),
      'supportPhone', nullif(support_phone_value, '')
    ))
  )
  on conflict (order_id) do nothing;
end;
$$;

revoke all on function
  public.capture_online_order_storefront_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_public_online_order_with_access(
  p_order_data jsonb,
  p_order_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid;
  customer_id_value uuid;
  checkout_key text;
  payment_method_value text;
  existing_order_id uuid;
  order_id_value uuid;
  order_tenant_id uuid;
  access_receipt jsonb;
  capabilities jsonb;
  selected_capability jsonb;
  is_replay boolean := false;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload'
      using errcode = '22023';
  end if;

  begin
    tenant_id_value := nullif(p_order_data->>'tenant_id', '')::uuid;
    customer_id_value := nullif(p_order_data->>'customer_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'Invalid tenant_id or customer_id'
        using errcode = '22023';
  end;

  if tenant_id_value is null then
    raise exception 'Invalid tenant_id'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = tenant_id_value
      and tenant.is_active is true
  ) then
    raise exception 'Storefront tenant is invalid or inactive'
      using errcode = '42501';
  end if;

  if customer_id_value is not null
     and (
       auth.uid() is null
       or not exists (
         select 1
         from public.customers customer
         where customer.id = customer_id_value
           and customer.tenant_id = tenant_id_value
           and customer.auth_user_id = auth.uid()
           and customer.is_active is true
       )
     ) then
    raise exception 'Checkout customer membership is invalid or inactive'
      using errcode = '42501';
  end if;

  checkout_key := lower(trim(coalesce(
    p_order_data->>'checkout_idempotency_key',
    ''
  )));

  if checkout_key !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  then
    raise exception 'A random checkout idempotency key is required'
      using errcode = '22023';
  end if;

  payment_method_value := lower(btrim(coalesce(
    nullif(p_order_data->>'payment_method', ''),
    'transfer'
  )));
  if payment_method_value = 'mercado_pago' then
    payment_method_value := 'mercadopago';
  elsif payment_method_value = 'bank_transfer' then
    payment_method_value := 'transfer';
  end if;
  if payment_method_value not in ('mercadopago', 'transfer') then
    raise exception 'Invalid payment method: %', payment_method_value
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(tenant_id_value::text || ':' || checkout_key, 0)
  );

  select customer_order.id
  into existing_order_id
  from public.online_orders customer_order
  where customer_order.tenant_id = tenant_id_value
    and customer_order.checkout_idempotency_key = checkout_key;
  is_replay := found;

  if not is_replay then
    capabilities :=
      public.resolve_public_checkout_capabilities(tenant_id_value);
    select method.value
    into selected_capability
    from jsonb_array_elements(capabilities->'methods') method(value)
    where method.value->>'code' = payment_method_value;

    if selected_capability is null
       or coalesce((selected_capability->>'available')::boolean, false)
         is not true then
      raise exception 'Checkout payment method unavailable: %',
        coalesce(
          selected_capability->>'reasonCode',
          'configuration_incomplete'
        )
        using errcode = 'P0001';
    end if;
  end if;

  order_id_value := public.create_public_online_order(
    p_order_data || jsonb_build_object(
      'checkout_idempotency_key', checkout_key
    ),
    p_order_items
  );

  select customer_order.tenant_id
  into order_tenant_id
  from public.online_orders customer_order
  where customer_order.id = order_id_value;

  if not found or order_tenant_id is distinct from tenant_id_value then
    raise exception 'Checkout order tenant mismatch'
      using errcode = '42501';
  end if;

  if is_replay and existing_order_id is distinct from order_id_value then
    raise exception 'Checkout replay returned a different order'
      using errcode = '23505';
  end if;

  if not is_replay then
    perform public.capture_online_order_storefront_snapshot(
      order_id_value,
      tenant_id_value
    );
  end if;

  access_receipt := public.issue_online_order_access_token(
    order_id_value,
    array['view_order']::text[],
    clock_timestamp() + interval '30 days'
  );

  return jsonb_build_object(
    'order_id', order_id_value,
    'access_token', access_receipt->>'token',
    'expires_at', access_receipt->>'expires_at',
    'replay', is_replay
  );
end;
$$;

revoke all on function
  public.create_public_online_order_with_access(jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function
  public.create_public_online_order_with_access(jsonb, jsonb)
  to anon, authenticated, service_role;

create or replace function public.get_public_online_order_by_access_token(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  access_row public.online_order_access_tokens%rowtype;
  order_row public.online_orders%rowtype;
  order_items jsonb;
  storefront_identity jsonb;
begin
  if length(coalesce(p_token, '')) < 40 or length(p_token) > 128 then
    return null;
  end if;

  select access.*
  into access_row
  from public.online_order_access_tokens access
  where access.token_sha256 = encode(
    extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'),
    'hex'
  )
    and access.revoked_at is null
    and access.expires_at > clock_timestamp()
    and access.scopes @> array['view_order']::text[]
  for update;

  if not found then
    return null;
  end if;

  select customer_order.*
  into order_row
  from public.online_orders customer_order
  where customer_order.id = access_row.order_id
    and customer_order.tenant_id = access_row.tenant_id;

  if not found then
    return null;
  end if;

  update public.online_order_access_tokens access
  set last_used_at = clock_timestamp(),
      use_count = access.use_count + 1
  where access.id = access_row.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'name', item.product_name,
    'sku', item.product_sku,
    'quantity', item.quantity,
    'unitPrice', item.unit_price,
    'subtotal', item.subtotal,
    'taxRate', case when item.tax_rate = 0.19 then 19 else item.tax_rate end
  ) order by item.created_at, item.id), '[]'::jsonb)
  into order_items
  from public.online_order_items item
  where item.order_id = order_row.id
    and item.tenant_id = order_row.tenant_id;

  select snapshot.identity_snapshot
  into storefront_identity
  from public.online_order_storefront_snapshots snapshot
  where snapshot.order_id = order_row.id
    and snapshot.tenant_id = order_row.tenant_id;

  return jsonb_build_object(
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', order_row.id,
      'number', order_row.order_number,
      'status', order_row.status,
      'paymentStatus', order_row.payment_status,
      'paymentMethod', order_row.payment_method,
      'deliveryType', order_row.delivery_type,
      'createdAt', order_row.created_at,
      'updatedAt', order_row.updated_at,
      'readyForPickupAt', order_row.ready_for_pickup_at,
      'shippedAt', order_row.shipped_at,
      'deliveredAt', order_row.delivered_at,
      'cancelledAt', order_row.cancelled_at,
      'trackingCarrier', order_row.shipping_carrier,
      'trackingNumber', order_row.tracking_number,
      'trackingUrl', case
        when order_row.tracking_url ~* '^https://[^[:space:]]+$'
          then order_row.tracking_url
        else null
      end,
      'subtotal', order_row.subtotal,
      'taxAmount', order_row.tax_amount,
      'shippingCost', order_row.shipping_cost,
      'discountAmount', order_row.discount_amount,
      'total', order_row.total
    )),
    'items', order_items,
    'storefront', coalesce(
      storefront_identity,
      jsonb_build_object(
        'schemaVersion', 1,
        'displayName', 'Tienda'
      )
    ),
    'access', jsonb_build_object(
      'scopes', access_row.scopes,
      'expiresAt', access_row.expires_at
    )
  );
end;
$$;

revoke all on function public.get_public_online_order_by_access_token(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_online_order_by_access_token(text)
  to anon, authenticated, service_role;

comment on function public.get_public_online_order_by_access_token(text) is
  'Token-authorized redacted online-order projection with immutable public line tax and server-derived storefront identity snapshots.';

commit;
