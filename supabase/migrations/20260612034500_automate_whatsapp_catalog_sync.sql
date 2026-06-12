-- Automatically synchronize WhatsApp catalog products after relevant database changes.
-- The service-role key is stored separately in Supabase Vault as
-- whatsapp_catalog_sync_service_role_key.

alter table public.products
  add column if not exists whatsapp_catalog_sync_status text not null default 'not_synced',
  add column if not exists whatsapp_catalog_sync_error text,
  add column if not exists whatsapp_catalog_sync_requested_at timestamptz,
  add column if not exists whatsapp_catalog_synced_at timestamptz,
  add column if not exists whatsapp_catalog_meta_product_id text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_whatsapp_catalog_sync_status_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_whatsapp_catalog_sync_status_check
      check (
        whatsapp_catalog_sync_status in (
          'not_synced',
          'pending',
          'syncing',
          'synced',
          'removed',
          'failed'
        )
      );
  end if;
end $$;

create or replace function public.enqueue_whatsapp_catalog_product_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_service_role_key text;
begin
  if tg_op = 'INSERT' and not coalesce(new.is_whatsapp_catalog, false) then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and not coalesce(old.is_whatsapp_catalog, false)
     and not coalesce(new.is_whatsapp_catalog, false) then
    return new;
  end if;

  update public.products
  set whatsapp_catalog_sync_status = 'pending',
      whatsapp_catalog_sync_error = null,
      whatsapp_catalog_sync_requested_at = now()
  where id = new.id;

  select decrypted_secret
  into v_service_role_key
  from vault.decrypted_secrets
  where name = 'whatsapp_catalog_sync_service_role_key'
  order by created_at desc
  limit 1;

  if nullif(v_service_role_key, '') is null then
    update public.products
    set whatsapp_catalog_sync_status = 'failed',
        whatsapp_catalog_sync_error =
          'Missing Vault secret whatsapp_catalog_sync_service_role_key'
    where id = new.id;
    return new;
  end if;

  perform net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-catalog-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key,
      'apikey', v_service_role_key
    ),
    body := jsonb_build_object('productId', new.id::text),
    timeout_milliseconds := 15000
  );

  return new;
exception
  when others then
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
