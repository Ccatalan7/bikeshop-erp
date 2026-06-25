-- Harden Meta Commerce catalog synchronization for WhatsApp and Instagram Shop.
--
-- Meta Catalog is the single external product sync target. Instagram Shopping
-- consumes the same catalog once enabled in Commerce Manager, so product
-- lifecycle changes stay platform-neutral at this layer.

create table if not exists public.product_catalog_sync_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  product_id uuid,
  catalog_id text,
  retailer_id text,
  meta_product_id text,
  operation text not null check (
    operation in ('upsert', 'remove', 'delete', 'refresh', 'legacy_cleanup')
  ),
  status text not null check (
    status in ('started', 'success', 'failed', 'skipped', 'partial')
  ),
  attempt_count integer,
  http_status integer,
  error text,
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_product_catalog_sync_events_tenant_created
  on public.product_catalog_sync_events(tenant_id, created_at desc);

create index if not exists idx_product_catalog_sync_events_product_created
  on public.product_catalog_sync_events(product_id, created_at desc);

create index if not exists idx_product_catalog_sync_events_catalog_retailer
  on public.product_catalog_sync_events(catalog_id, retailer_id, created_at desc);

alter table public.product_catalog_sync_events enable row level security;

drop policy if exists "product_catalog_sync_events_select" on public.product_catalog_sync_events;
create policy "product_catalog_sync_events_select"
  on public.product_catalog_sync_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

-- Automatically synchronize Meta catalog products after relevant database
-- changes. Hard deletes send a row snapshot so the Edge Function can remove the
-- corresponding Meta item even after public.products no longer has the row.
create or replace function public.enqueue_whatsapp_catalog_product_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_service_role_key text;
  v_request_body jsonb;
begin
  if tg_op = 'DELETE' then
    if not coalesce(old.is_whatsapp_catalog, false)
       and nullif(old.whatsapp_catalog_meta_product_id, '') is null
       and coalesce(old.whatsapp_catalog_sync_status, 'not_synced') in ('not_synced', 'removed') then
      return old;
    end if;
  elsif tg_op = 'INSERT' and not coalesce(new.is_whatsapp_catalog, false) then
    return new;
  elsif tg_op = 'UPDATE'
     and not coalesce(old.is_whatsapp_catalog, false)
     and not coalesce(new.is_whatsapp_catalog, false) then
    return new;
  end if;

  select decrypted_secret
  into v_service_role_key
  from vault.decrypted_secrets
  where name = 'whatsapp_catalog_sync_service_role_key'
  order by created_at desc
  limit 1;

  if nullif(v_service_role_key, '') is null then
    if tg_op = 'DELETE' then
      insert into public.product_catalog_sync_events (
        tenant_id,
        product_id,
        operation,
        status,
        error,
        request_payload
      )
      values (
        old.tenant_id,
        old.id,
        'delete',
        'failed',
        'Missing Vault secret whatsapp_catalog_sync_service_role_key',
        jsonb_build_object('productId', old.id::text)
      );
      return old;
    end if;

    update public.products
    set whatsapp_catalog_sync_status = 'failed',
        whatsapp_catalog_sync_error =
          'Missing Vault secret whatsapp_catalog_sync_service_role_key'
    where id = new.id;
    return new;
  end if;

  if tg_op = 'DELETE' then
    v_request_body := jsonb_build_object(
      'productId', old.id::text,
      'operation', 'delete',
      'product', jsonb_build_object(
        'id', old.id::text,
        'tenant_id', old.tenant_id::text,
        'sku', old.sku,
        'name', old.name,
        'whatsapp_catalog_meta_product_id', old.whatsapp_catalog_meta_product_id
      )
    );
  else
    update public.products
    set whatsapp_catalog_sync_status = 'pending',
        whatsapp_catalog_sync_error = null,
        whatsapp_catalog_sync_requested_at = now()
    where id = new.id;

    v_request_body := jsonb_build_object('productId', new.id::text);
  end if;

  perform net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-catalog-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key,
      'apikey', v_service_role_key
    ),
    body := v_request_body,
    timeout_milliseconds := 15000
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
exception
  when others then
    if tg_op = 'DELETE' then
      insert into public.product_catalog_sync_events (
        tenant_id,
        product_id,
        operation,
        status,
        error,
        request_payload
      )
      values (
        old.tenant_id,
        old.id,
        'delete',
        'failed',
        sqlerrm,
        jsonb_build_object('productId', old.id::text)
      );
      return old;
    end if;

    update public.products
    set whatsapp_catalog_sync_status = 'failed',
        whatsapp_catalog_sync_error = sqlerrm
    where id = new.id;
    return new;
end;
$$;

revoke all on function public.enqueue_whatsapp_catalog_product_sync() from public;

drop trigger if exists trg_products_whatsapp_catalog_sync_insert on public.products;
create trigger trg_products_whatsapp_catalog_sync_insert
  after insert on public.products
  for each row
  execute function public.enqueue_whatsapp_catalog_product_sync();

drop trigger if exists trg_products_whatsapp_catalog_sync_update on public.products;
create trigger trg_products_whatsapp_catalog_sync_update
  after update of
    is_whatsapp_catalog,
    whatsapp_catalog_title,
    whatsapp_catalog_description,
    whatsapp_catalog_price,
    name,
    sku,
    description,
    brand,
    category_name,
    price,
    stock_quantity,
    inventory_qty,
    is_active,
    is_published,
    website_name,
    website_description,
    website_price,
    website_image_url,
    website_image_url_optimized,
    image_url,
    image_url_optimized
  on public.products
  for each row
  execute function public.enqueue_whatsapp_catalog_product_sync();

drop trigger if exists trg_products_whatsapp_catalog_sync_delete on public.products;
create trigger trg_products_whatsapp_catalog_sync_delete
  after delete on public.products
  for each row
  execute function public.enqueue_whatsapp_catalog_product_sync();
