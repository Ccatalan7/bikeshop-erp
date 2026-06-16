-- Preserve every previously published product URL so renamed products and SKU
-- changes continue resolving to the current canonical product.

create or replace function public.product_url_slug(p_value text)
returns text
language sql
immutable
set search_path = public
as $$
  with normalized as (
    select regexp_replace(
      translate(
        lower(trim(coalesce(p_value, ''))),
        'áàäâãåéèëêíìïîóòöôõúùüûñç',
        'aaaaaaeeeeiiiiooooouuuunc'
      ),
      '[^a-z0-9]+',
      '-',
      'g'
    ) as value
  )
  select coalesce(
    nullif(
      regexp_replace(left(trim(both '-' from value), 80), '-+$', ''),
      ''
    ),
    'producto'
  )
  from normalized;
$$;

create or replace function public.product_public_url_path(
  p_name text,
  p_website_name text,
  p_sku text,
  p_id uuid
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when nullif(trim(coalesce(p_sku, '')), '') is null
      then '/productos/' || p_id::text
    else '/productos/'
      || public.product_url_slug(coalesce(nullif(trim(p_website_name), ''), p_name))
      || '/'
      || trim(p_sku)
  end;
$$;

create table if not exists public.product_url_aliases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  alias_path text not null,
  source text not null default 'historical',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint product_url_aliases_path_check
    check (alias_path like '/%'),
  unique (tenant_id, alias_path)
);

create index if not exists idx_product_url_aliases_product
  on public.product_url_aliases(product_id, created_at desc);

alter table public.product_url_aliases enable row level security;

create or replace function public.remember_product_url_aliases()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_path text;
  v_new_path text;
begin
  v_new_path := public.product_public_url_path(
    new.name,
    new.website_name,
    new.sku,
    new.id
  );

  if tg_op = 'INSERT' then
    insert into public.product_url_aliases (
      tenant_id,
      product_id,
      alias_path,
      source
    )
    values
      (new.tenant_id, new.id, '/productos/' || new.id::text, 'legacy_uuid'),
      (new.tenant_id, new.id, '/producto/' || new.id::text, 'legacy_singular'),
      (new.tenant_id, new.id, '/tienda/producto/' || new.id::text, 'legacy_erp')
    on conflict (tenant_id, alias_path) do update
      set last_seen_at = now();

    return new;
  end if;

  v_old_path := public.product_public_url_path(
    old.name,
    old.website_name,
    old.sku,
    old.id
  );

  if v_old_path is distinct from v_new_path then
    insert into public.product_url_aliases (
      tenant_id,
      product_id,
      alias_path,
      source
    )
    values (
      old.tenant_id,
      old.id,
      v_old_path,
      case
        when old.sku is distinct from new.sku then 'sku_change'
        else 'slug_change'
      end
    )
    on conflict (tenant_id, alias_path) do update
      set last_seen_at = now();
  end if;

  return new;
end;
$$;

revoke all on function public.remember_product_url_aliases() from public;

drop trigger if exists trg_products_remember_url_aliases_insert
  on public.products;
create trigger trg_products_remember_url_aliases_insert
  after insert on public.products
  for each row execute function public.remember_product_url_aliases();

drop trigger if exists trg_products_remember_url_aliases_update
  on public.products;
create trigger trg_products_remember_url_aliases_update
  after update of name, website_name, sku on public.products
  for each row execute function public.remember_product_url_aliases();

insert into public.product_url_aliases (
  tenant_id,
  product_id,
  alias_path,
  source
)
select aliases.tenant_id, aliases.product_id, aliases.alias_path, aliases.source
from (
  select tenant_id, id as product_id, '/productos/' || id::text as alias_path,
         'legacy_uuid'::text as source
  from public.products
  union all
  select tenant_id, id, '/producto/' || id::text, 'legacy_singular'
  from public.products
  union all
  select tenant_id, id, '/tienda/producto/' || id::text, 'legacy_erp'
  from public.products
) aliases
on conflict (tenant_id, alias_path) do nothing;

create or replace function public.resolve_public_product_url_alias(
  p_tenant_id uuid,
  p_alias_path text
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select a.product_id
  from public.product_url_aliases a
  join public.products p
    on p.id = a.product_id
   and p.tenant_id = a.tenant_id
  where a.tenant_id = p_tenant_id
    and a.alias_path = p_alias_path
    and p.is_active = true
    and p.is_published = true
    and p.show_on_website = true
    and p.product_type = 'product'
  limit 1;
$$;

grant execute on function public.resolve_public_product_url_alias(uuid, text)
  to anon, authenticated;

alter table public.products
  add column if not exists whatsapp_catalog_synced_url text,
  add column if not exists whatsapp_catalog_url_matches boolean,
  add column if not exists whatsapp_catalog_verified_at timestamptz;

