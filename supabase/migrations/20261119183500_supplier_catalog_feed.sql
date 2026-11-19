-- A supplier's catalogue feed, read on a schedule.
--
-- Until now the only way to know what a supplier had was its distributor
-- portal, one product at a time and with the stock cut at «50+». On
-- 2026-11-17 MKR Imports gave Viñabike an endpoint for the 17 brands the owner
-- asked for: one file with every product, its exact stock, net prices,
-- description and photos, refreshed every 30 minutes. Selling on order with a
-- safety margin (owner, 2026-11-14: «publicar solamente los productos que
-- tengan más 3 o más 5 de stock») needs that reading kept fresh in the
-- database, with its history, before anything is published.
--
-- This migration only stores the reading. Nothing here publishes a product,
-- changes a price or shows on the storefront.
--
-- How a reading happens, like the Meta sweep (20261110080000): the schedule
-- mints a single-use, hashed ticket for each feed that is due and posts it to
-- the `supplier-feed-sync` function. The function redeems the ticket with the
-- service role, receives the endpoint and its token from Vault, reads the file
-- and sends the rows back. No shared secret exists, the token never leaves the
-- database except in that redeem, and nobody but the schedule can start a run.
--
-- The database decides what changed. A row that did not change is not written
-- again: 48 readings a day of 10.851 products would otherwise rewrite half a
-- million rows daily on a Micro instance.

-- Where a supplier's feed lives and how it is going.
create table if not exists public.supplier_catalog_feeds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  feed_key text not null default 'catalog'
    check (feed_key ~ '^[a-z][a-z0-9_]*$' and length(feed_key) <= 40),
  format text not null check (format in ('mkr_csv_v1')),
  -- The address with `{token}` where the supplier's token goes. The token
  -- itself is a supplier credential (`api_token`) in Vault.
  endpoint_template text not null
    check (
      endpoint_template ~ '^https://[a-z0-9.-]+/[^[:space:]]*\{token\}[^[:space:]]*$'
      and length(endpoint_template) <= 500
    ),
  credential_key text not null default 'catalog_feed'
    check (credential_key ~ '^[a-z][a-z0-9_.-]*$'),
  -- What the supplier takes off its wholesale price for this account. It is
  -- not in the file: MKR shows it in its portal («Descuento MKR 5%»).
  account_discount_percent numeric(5, 2) not null default 0
    check (account_discount_percent >= 0 and account_discount_percent < 100),
  enabled boolean not null default true,
  last_ok_at timestamptz,
  last_status text check (last_status in ('ok', 'failed', 'suspect')),
  last_run_id uuid,
  listed_count integer not null default 0,
  in_stock_count integer not null default 0,
  consecutive_failures integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, id, supplier_id),
  unique (tenant_id, supplier_id, feed_key),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade
);
alter table public.supplier_catalog_feeds enable row level security;
revoke all on public.supplier_catalog_feeds from public, anon, authenticated;
grant all on public.supplier_catalog_feeds to service_role;

comment on table public.supplier_catalog_feeds is
  'A supplier catalogue feed read on a schedule: where it lives, its format and how its last reading went. The token is a supplier credential in Vault, never a column here.';
comment on column public.supplier_catalog_feeds.last_ok_at is
  'When the last complete reading finished. Whatever is offered from this feed is only as fresh as this.';

-- What the supplier lists, one row per supplier code. Written only when the
-- reading differs from what is stored.
create table if not exists public.supplier_catalog_feed_items (
  tenant_id uuid not null,
  feed_id uuid not null,
  supplier_id uuid not null,
  supplier_sku text not null
    check (supplier_sku <> '' and length(supplier_sku) <= 64),
  product_code text,
  barcode text,
  name text not null default '',
  brand text not null default '',
  description_html text,
  photo_urls text[] not null default '{}',
  -- The reader's fingerprint of name, brand, description and photos. Null
  -- until that content arrives.
  content_hash text,
  stock integer not null default 0,
  price_net numeric(14, 2),
  price_before_net numeric(14, 2),
  price_offer_net numeric(14, 2),
  suggested_retail_net numeric(14, 2),
  is_listed boolean not null default true,
  first_seen_at timestamptz not null default clock_timestamp(),
  stock_changed_at timestamptz,
  price_changed_at timestamptz,
  content_changed_at timestamptz,
  delisted_at timestamptz,
  primary key (feed_id, supplier_sku),
  foreign key (tenant_id, feed_id, supplier_id)
    references public.supplier_catalog_feeds(tenant_id, id, supplier_id)
    on delete cascade
);
create index if not exists supplier_catalog_feed_items_supplier_sku_idx
  on public.supplier_catalog_feed_items (tenant_id, supplier_id, supplier_sku);
create index if not exists supplier_catalog_feed_items_barcode_idx
  on public.supplier_catalog_feed_items (tenant_id, barcode)
  where barcode is not null;
alter table public.supplier_catalog_feed_items enable row level security;
revoke all on public.supplier_catalog_feed_items from public, anon, authenticated;
grant all on public.supplier_catalog_feed_items to service_role;

comment on table public.supplier_catalog_feed_items is
  'What a supplier lists in its feed, by supplier code: exact stock, net prices, description and photos as last read. A product missing from a complete reading stays here with is_listed = false.';
comment on column public.supplier_catalog_feed_items.price_net is
  'The supplier''s wholesale price as the file gives it, net of tax and before the account discount.';
comment on column public.supplier_catalog_feed_items.price_offer_net is
  'The supplier''s offer price, net. It is a real offer only when it is above zero and below price_before_net: the file flags almost every row as an offer.';
comment on column public.supplier_catalog_feed_items.suggested_retail_net is
  'The retail price the supplier suggests, net of tax.';

-- Each reading: its ticket, how it went and what it changed.
create table if not exists public.supplier_catalog_feed_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  feed_id uuid not null,
  -- Only the hash of the ticket, and only until it is redeemed.
  token_hash text,
  lease_until timestamptz not null,
  status text not null default 'dispatched'
    check (status in ('dispatched', 'running', 'ok', 'failed', 'suspect')),
  dispatched_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  finished_at timestamptz,
  row_count integer not null default 0,
  new_count integer not null default 0,
  stock_changes integer not null default 0,
  price_changes integer not null default 0,
  content_changes integer not null default 0,
  delisted_count integer not null default 0,
  http_status integer,
  bytes bigint,
  duration_ms integer,
  error_code text check (error_code ~ '^[a-z0-9_]+$' and length(error_code) <= 64),
  foreign key (tenant_id, feed_id)
    references public.supplier_catalog_feeds(tenant_id, id) on delete cascade
);
create index if not exists supplier_catalog_feed_runs_feed_idx
  on public.supplier_catalog_feed_runs (feed_id, dispatched_at desc);
alter table public.supplier_catalog_feed_runs enable row level security;
revoke all on public.supplier_catalog_feed_runs from public, anon, authenticated;
grant all on public.supplier_catalog_feed_runs to service_role;

comment on table public.supplier_catalog_feed_runs is
  'Each scheduled reading of a supplier feed: counts and codes only, never the address or the token. Kept 60 days.';

-- How a product's stock moved at the supplier between readings: what tells
-- how fast the supplier sells it, and so how much margin a promise needs.
create table if not exists public.supplier_catalog_feed_stock_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null,
  feed_id uuid not null,
  supplier_sku text not null,
  observed_at timestamptz not null default clock_timestamp(),
  stock_before integer not null,
  stock_after integer not null,
  foreign key (tenant_id, feed_id)
    references public.supplier_catalog_feeds(tenant_id, id) on delete cascade
);
create index if not exists supplier_catalog_feed_stock_events_sku_idx
  on public.supplier_catalog_feed_stock_events (feed_id, supplier_sku, observed_at desc);
alter table public.supplier_catalog_feed_stock_events enable row level security;
revoke all on public.supplier_catalog_feed_stock_events from public, anon, authenticated;
grant all on public.supplier_catalog_feed_stock_events to service_role;

comment on table public.supplier_catalog_feed_stock_events is
  'Each change of a product''s stock at the supplier, as seen between two readings. Kept 180 days.';

-- Where the schedule posts, and its switch.
create table if not exists public.supplier_catalog_feed_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  endpoint text not null
    check (endpoint ~ '^https://[^/]+/functions/v1/supplier-feed-sync$')
);
insert into public.supplier_catalog_feed_runtime (singleton, endpoint)
values (
  true,
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/supplier-feed-sync'
)
on conflict (singleton) do nothing;
alter table public.supplier_catalog_feed_runtime enable row level security;
revoke all on public.supplier_catalog_feed_runtime from public, anon, authenticated;
grant all on public.supplier_catalog_feed_runtime to service_role;

comment on table public.supplier_catalog_feed_runtime is
  'Private switch and endpoint of the scheduled supplier feed readings.';

-- Closes a reading that did not finish, and counts it against its feed.
create or replace function public.fail_supplier_catalog_feed_run_v1(
  p_run_id uuid,
  p_error_code text,
  p_http_status integer default null
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_feed_id uuid;
  v_tenant_id uuid;
  v_code text := left(
    regexp_replace(
      lower(coalesce(nullif(btrim(p_error_code), ''), 'unknown')),
      '[^a-z0-9_]', '_', 'g'
    ),
    64
  );
begin
  if v_role <> 'service_role' then
    raise exception 'Supplier catalog feed runs require service role'
      using errcode = '42501';
  end if;

  update public.supplier_catalog_feed_runs run
  set status = 'failed',
      error_code = v_code,
      http_status = coalesce(p_http_status, run.http_status),
      token_hash = null,
      finished_at = clock_timestamp()
  where run.id = p_run_id
    and run.status in ('dispatched', 'running')
  returning run.feed_id, run.tenant_id into v_feed_id, v_tenant_id;
  if not found then
    return false;
  end if;

  update public.supplier_catalog_feeds feed
  set consecutive_failures = feed.consecutive_failures + 1,
      last_status = 'failed',
      last_run_id = p_run_id,
      updated_at = clock_timestamp()
  where feed.id = v_feed_id
    and feed.tenant_id = v_tenant_id;
  return true;
end;
$$;

comment on function public.fail_supplier_catalog_feed_run_v1(uuid, text, integer) is
  'Service only: closes an open supplier feed reading as failed, with a short code, and counts the failure on its feed.';

create or replace function public.dispatch_supplier_catalog_feed_syncs()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_endpoint text;
  v_feed record;
  v_expired record;
  v_token text;
  v_run_id uuid;
  v_count integer := 0;
begin
  -- A reading whose reader never came back is closed here, so its feed says
  -- it failed instead of looking as if nothing had been tried.
  for v_expired in
    update public.supplier_catalog_feed_runs run
    set status = 'failed',
        error_code = 'reader_timeout',
        token_hash = null,
        finished_at = clock_timestamp()
    where run.status in ('dispatched', 'running')
      and run.lease_until <= clock_timestamp()
    returning run.id, run.feed_id, run.tenant_id
  loop
    update public.supplier_catalog_feeds feed
    set consecutive_failures = feed.consecutive_failures + 1,
        last_status = 'failed',
        last_run_id = v_expired.id,
        updated_at = clock_timestamp()
    where feed.id = v_expired.feed_id
      and feed.tenant_id = v_expired.tenant_id;
  end loop;

  delete from public.supplier_catalog_feed_runs run
  where run.dispatched_at < clock_timestamp() - interval '60 days';
  delete from public.supplier_catalog_feed_stock_events event
  where event.observed_at < clock_timestamp() - interval '180 days';

  select runtime.endpoint into v_endpoint
  from public.supplier_catalog_feed_runtime runtime
  where runtime.singleton and runtime.enabled;
  if v_endpoint is null then
    return 0;
  end if;

  -- Nothing is posted for a feed without its token, or with a reading still
  -- out.
  for v_feed in
    select feed.id, feed.tenant_id
    from public.supplier_catalog_feeds feed
    where feed.enabled
      and exists (
        select 1
        from public.supplier_credentials credential
        where credential.tenant_id = feed.tenant_id
          and credential.supplier_id = feed.supplier_id
          and credential.credential_kind = 'api_token'
          and credential.credential_key = feed.credential_key
          and credential.vault_secret_id is not null
      )
      and not exists (
        select 1
        from public.supplier_catalog_feed_runs run
        where run.feed_id = feed.id
          and run.tenant_id = feed.tenant_id
          and run.status in ('dispatched', 'running')
          and run.lease_until > clock_timestamp()
      )
    order by feed.id
    limit 20
  loop
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.supplier_catalog_feed_runs (
      tenant_id, feed_id, token_hash, lease_until
    ) values (
      v_feed.tenant_id,
      v_feed.id,
      encode(extensions.digest(v_token, 'sha256'), 'hex'),
      clock_timestamp() + interval '3 minutes'
    )
    returning id into v_run_id;
    perform net.http_post(
      url := v_endpoint,
      headers := '{"Content-Type":"application/json","x-region":"sa-east-1"}'::jsonb,
      body := jsonb_build_object('run_id', v_run_id, 'token', v_token),
      timeout_milliseconds := 150000
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function public.dispatch_supplier_catalog_feed_syncs() is
  'Scheduled: closes readings that never finished and posts a single-use ticket to supplier-feed-sync for each enabled supplier feed that has its token and no reading out.';

create or replace function public.redeem_supplier_catalog_feed_sync(
  p_run_id uuid,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_feed_id uuid;
  v_tenant_id uuid;
  v_feed public.supplier_catalog_feeds%rowtype;
  v_secret text;
begin
  if v_role <> 'service_role' then
    raise exception 'Supplier catalog feed runs require service role'
      using errcode = '42501';
  end if;

  -- Single use: the ticket is gone once it opens a reading. The reader then
  -- has ten minutes to finish it.
  update public.supplier_catalog_feed_runs run
  set token_hash = null,
      status = 'running',
      started_at = clock_timestamp(),
      lease_until = clock_timestamp() + interval '10 minutes'
  where run.id = p_run_id
    and run.status = 'dispatched'
    and run.lease_until > clock_timestamp()
    and run.token_hash
      = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
  returning run.feed_id, run.tenant_id into v_feed_id, v_tenant_id;
  if not found then
    return null;
  end if;

  select feed.* into v_feed
  from public.supplier_catalog_feeds feed
  where feed.id = v_feed_id
    and feed.tenant_id = v_tenant_id
    and feed.enabled;
  if not found then
    perform public.fail_supplier_catalog_feed_run_v1(p_run_id, 'feed_disabled');
    return null;
  end if;

  select secret.decrypted_secret into v_secret
  from public.supplier_credentials credential
  join vault.decrypted_secrets secret
    on secret.id = credential.vault_secret_id
  where credential.tenant_id = v_feed.tenant_id
    and credential.supplier_id = v_feed.supplier_id
    and credential.credential_kind = 'api_token'
    and credential.credential_key = v_feed.credential_key;
  if nullif(btrim(coalesce(v_secret, '')), '') is null then
    perform public.fail_supplier_catalog_feed_run_v1(p_run_id, 'credential_missing');
    return null;
  end if;

  return jsonb_build_object(
    'run_id', p_run_id,
    'format', v_feed.format,
    'endpoint_template', v_feed.endpoint_template,
    'token', btrim(v_secret)
  );
end;
$$;

comment on function public.redeem_supplier_catalog_feed_sync(uuid, text) is
  'Service only: exchanges a dispatched ticket for the feed''s format, address and token. Null when the ticket is wrong, used or expired, or the feed cannot be read.';

-- The rows of a reading, without their content:
-- [code, product code, barcode, stock, price, price before, offer price,
--  suggested retail, content fingerprint]. Answers which codes need their
-- content sent.
create or replace function public.apply_supplier_catalog_feed_rows_v1(
  p_run_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_now timestamptz := clock_timestamp();
  v_feed_id uuid;
  v_tenant_id uuid;
  v_supplier_id uuid;
  v_rows integer;
  v_new integer;
  v_stock integer;
  v_price integer;
  v_need jsonb;
begin
  if v_role <> 'service_role' then
    raise exception 'Supplier catalog feed runs require service role'
      using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Supplier catalog feed rows must be an array'
      using errcode = '22023';
  end if;

  select run.feed_id, run.tenant_id, feed.supplier_id
  into v_feed_id, v_tenant_id, v_supplier_id
  from public.supplier_catalog_feed_runs run
  join public.supplier_catalog_feeds feed
    on feed.id = run.feed_id
   and feed.tenant_id = run.tenant_id
  where run.id = p_run_id
    and run.status = 'running'
    and run.lease_until > v_now
  for update of run;
  if not found then
    raise exception 'Supplier catalog feed run is not open'
      using errcode = '55000';
  end if;

  with incoming as (
    select distinct on (raw.sku)
      raw.sku,
      raw.product_code,
      raw.barcode,
      raw.stock,
      raw.price_net,
      raw.price_before_net,
      raw.price_offer_net,
      raw.suggested_retail_net,
      raw.content_hash
    from (
      select
        nullif(btrim(item.value->>0), '') as sku,
        nullif(btrim(item.value->>1), '') as product_code,
        nullif(btrim(item.value->>2), '') as barcode,
        coalesce((item.value->>3)::integer, 0) as stock,
        (item.value->>4)::numeric(14, 2) as price_net,
        (item.value->>5)::numeric(14, 2) as price_before_net,
        (item.value->>6)::numeric(14, 2) as price_offer_net,
        (item.value->>7)::numeric(14, 2) as suggested_retail_net,
        nullif(item.value->>8, '') as content_hash,
        item.ordinality as position
      from jsonb_array_elements(p_rows) with ordinality as item(value, ordinality)
      where jsonb_typeof(item.value) = 'array'
    ) raw
    where raw.sku is not null
      and length(raw.sku) <= 64
    order by raw.sku, raw.position desc
  ),
  before as (
    select
      item.supplier_sku,
      item.stock,
      item.price_net,
      item.price_before_net,
      item.price_offer_net,
      item.suggested_retail_net,
      item.content_hash
    from public.supplier_catalog_feed_items item
    join incoming on incoming.sku = item.supplier_sku
    where item.feed_id = v_feed_id
      and item.tenant_id = v_tenant_id
  ),
  inserted as (
    insert into public.supplier_catalog_feed_items (
      tenant_id, feed_id, supplier_id, supplier_sku, product_code, barcode,
      stock, price_net, price_before_net, price_offer_net,
      suggested_retail_net, first_seen_at
    )
    select
      v_tenant_id, v_feed_id, v_supplier_id, incoming.sku,
      incoming.product_code, incoming.barcode, incoming.stock,
      incoming.price_net, incoming.price_before_net, incoming.price_offer_net,
      incoming.suggested_retail_net, v_now
    from incoming
    where not exists (
      select 1 from before where before.supplier_sku = incoming.sku
    )
    on conflict (feed_id, supplier_sku) do nothing
    returning supplier_sku
  ),
  updated as (
    update public.supplier_catalog_feed_items item
    set product_code = incoming.product_code,
        barcode = incoming.barcode,
        stock = incoming.stock,
        price_net = incoming.price_net,
        price_before_net = incoming.price_before_net,
        price_offer_net = incoming.price_offer_net,
        suggested_retail_net = incoming.suggested_retail_net,
        is_listed = true,
        delisted_at = null,
        stock_changed_at = case
          when item.stock is distinct from incoming.stock then v_now
          else item.stock_changed_at
        end,
        price_changed_at = case
          when (item.price_net, item.price_before_net, item.price_offer_net,
                item.suggested_retail_net)
            is distinct from
               (incoming.price_net, incoming.price_before_net,
                incoming.price_offer_net, incoming.suggested_retail_net)
          then v_now
          else item.price_changed_at
        end
    from incoming
    where item.feed_id = v_feed_id
      and item.tenant_id = v_tenant_id
      and item.supplier_sku = incoming.sku
      and (item.product_code, item.barcode, item.stock, item.price_net,
           item.price_before_net, item.price_offer_net,
           item.suggested_retail_net, item.is_listed)
        is distinct from
          (incoming.product_code, incoming.barcode, incoming.stock,
           incoming.price_net, incoming.price_before_net,
           incoming.price_offer_net, incoming.suggested_retail_net, true)
    returning item.supplier_sku
  ),
  moved as (
    insert into public.supplier_catalog_feed_stock_events (
      tenant_id, feed_id, supplier_sku, observed_at, stock_before, stock_after
    )
    select
      v_tenant_id, v_feed_id, incoming.sku, v_now, before.stock, incoming.stock
    from incoming
    join before on before.supplier_sku = incoming.sku
    where before.stock is distinct from incoming.stock
    returning 1
  )
  select
    (select count(*) from incoming),
    (select count(*) from inserted),
    (select count(*) from moved),
    (
      select count(*)
      from incoming
      join before on before.supplier_sku = incoming.sku
      where (before.price_net, before.price_before_net, before.price_offer_net,
             before.suggested_retail_net)
        is distinct from
          (incoming.price_net, incoming.price_before_net,
           incoming.price_offer_net, incoming.suggested_retail_net)
    ),
    (
      select coalesce(jsonb_agg(incoming.sku order by incoming.sku), '[]'::jsonb)
      from incoming
      left join before on before.supplier_sku = incoming.sku
      where incoming.content_hash is not null
        and (
          before.supplier_sku is null
          or before.content_hash is distinct from incoming.content_hash
        )
    )
  into v_rows, v_new, v_stock, v_price, v_need;

  update public.supplier_catalog_feed_runs run
  set row_count = run.row_count + v_rows,
      new_count = run.new_count + v_new,
      stock_changes = run.stock_changes + v_stock,
      price_changes = run.price_changes + v_price
  where run.id = p_run_id;

  return jsonb_build_object(
    'rows', v_rows,
    'new', v_new,
    'stock_changes', v_stock,
    'price_changes', v_price,
    'need_content', v_need
  );
end;
$$;

comment on function public.apply_supplier_catalog_feed_rows_v1(uuid, jsonb) is
  'Service only: stores stock and prices of an open reading, writing only what changed and recording each stock movement. Answers the codes whose content must be sent.';

-- The content of the codes that asked for it:
-- [code, name, brand, description, [photos], content fingerprint].
create or replace function public.apply_supplier_catalog_feed_content_v1(
  p_run_id uuid,
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_now timestamptz := clock_timestamp();
  v_feed_id uuid;
  v_tenant_id uuid;
  v_count integer;
begin
  if v_role <> 'service_role' then
    raise exception 'Supplier catalog feed runs require service role'
      using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Supplier catalog feed content must be an array'
      using errcode = '22023';
  end if;

  select run.feed_id, run.tenant_id into v_feed_id, v_tenant_id
  from public.supplier_catalog_feed_runs run
  where run.id = p_run_id
    and run.status = 'running'
    and run.lease_until > v_now
  for update of run;
  if not found then
    raise exception 'Supplier catalog feed run is not open'
      using errcode = '55000';
  end if;

  with incoming as (
    select distinct on (raw.sku)
      raw.sku, raw.name, raw.brand, raw.description_html, raw.photo_urls,
      raw.content_hash
    from (
      select
        nullif(btrim(item.value->>0), '') as sku,
        left(coalesce(btrim(item.value->>1), ''), 400) as name,
        left(coalesce(btrim(item.value->>2), ''), 120) as brand,
        nullif(left(coalesce(item.value->>3, ''), 100000), '') as description_html,
        case
          when jsonb_typeof(item.value->4) = 'array' then array(
            select photo.url
            from jsonb_array_elements_text(item.value->4)
              with ordinality as photo(url, position)
            where photo.url ~ '^https://[^[:space:]]+$'
              and length(photo.url) <= 500
              and photo.position <= 12
            order by photo.position
          )
          else '{}'::text[]
        end as photo_urls,
        nullif(item.value->>5, '') as content_hash,
        item.ordinality as position
      from jsonb_array_elements(p_rows) with ordinality as item(value, ordinality)
      where jsonb_typeof(item.value) = 'array'
    ) raw
    where raw.sku is not null
      and raw.content_hash is not null
    order by raw.sku, raw.position desc
  )
  update public.supplier_catalog_feed_items item
  set name = incoming.name,
      brand = incoming.brand,
      description_html = incoming.description_html,
      photo_urls = incoming.photo_urls,
      content_hash = incoming.content_hash,
      content_changed_at = v_now
  from incoming
  where item.feed_id = v_feed_id
    and item.tenant_id = v_tenant_id
    and item.supplier_sku = incoming.sku
    and item.content_hash is distinct from incoming.content_hash;
  get diagnostics v_count = row_count;

  update public.supplier_catalog_feed_runs run
  set content_changes = run.content_changes + v_count
  where run.id = p_run_id;
  return v_count;
end;
$$;

comment on function public.apply_supplier_catalog_feed_content_v1(uuid, jsonb) is
  'Service only: stores name, brand, description and photos of the codes whose fingerprint changed in an open reading.';

-- Closes a complete reading: what the file no longer lists stops being
-- listed, and the feed is as fresh as now.
create or replace function public.finish_supplier_catalog_feed_run_v1(
  p_run_id uuid,
  p_skus text[],
  p_stats jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_now timestamptz := clock_timestamp();
  v_feed_id uuid;
  v_tenant_id uuid;
  v_row_count integer;
  v_seen integer;
  v_listed integer;
  v_delisted integer := 0;
  v_in_stock integer;
  v_http integer := nullif(p_stats->>'http_status', '')::integer;
  v_bytes bigint := nullif(p_stats->>'bytes', '')::bigint;
  v_duration integer := nullif(p_stats->>'duration_ms', '')::integer;
begin
  if v_role <> 'service_role' then
    raise exception 'Supplier catalog feed runs require service role'
      using errcode = '42501';
  end if;

  select run.feed_id, run.tenant_id, run.row_count
  into v_feed_id, v_tenant_id, v_row_count
  from public.supplier_catalog_feed_runs run
  where run.id = p_run_id
    and run.status = 'running'
    and run.lease_until > v_now
  for update of run;
  if not found then
    raise exception 'Supplier catalog feed run is not open'
      using errcode = '55000';
  end if;

  select count(distinct seen.sku) into v_seen
  from unnest(coalesce(p_skus, '{}'::text[])) as seen(sku)
  where nullif(btrim(seen.sku), '') is not null;
  if v_seen <> v_row_count then
    raise exception 'Supplier catalog feed run closed with % codes after storing %',
      v_seen, v_row_count
      using errcode = '22023';
  end if;

  select count(*) into v_listed
  from public.supplier_catalog_feed_items item
  where item.feed_id = v_feed_id
    and item.tenant_id = v_tenant_id
    and item.is_listed;

  -- A file with nothing, or with less than half of what was listed before
  -- this reading, is a broken answer and not the catalogue shrinking: it
  -- delists nothing and the feed does not get fresher.
  if v_seen = 0 or (v_listed >= 200 and v_seen * 2 < v_listed) then
    update public.supplier_catalog_feed_runs run
    set status = 'suspect',
        error_code = 'too_few_rows',
        http_status = v_http,
        bytes = v_bytes,
        duration_ms = v_duration,
        finished_at = v_now
    where run.id = p_run_id;
    update public.supplier_catalog_feeds feed
    set consecutive_failures = feed.consecutive_failures + 1,
        last_status = 'suspect',
        last_run_id = p_run_id,
        updated_at = v_now
    where feed.id = v_feed_id
      and feed.tenant_id = v_tenant_id;
    return jsonb_build_object('status', 'suspect', 'rows', v_seen, 'listed', v_listed);
  end if;

  update public.supplier_catalog_feed_items item
  set is_listed = false,
      delisted_at = v_now
  where item.feed_id = v_feed_id
    and item.tenant_id = v_tenant_id
    and item.is_listed
    and not exists (
      select 1
      from unnest(p_skus) as seen(sku)
      where btrim(seen.sku) = item.supplier_sku
    );
  get diagnostics v_delisted = row_count;

  select count(*), count(*) filter (where item.stock > 0)
  into v_listed, v_in_stock
  from public.supplier_catalog_feed_items item
  where item.feed_id = v_feed_id
    and item.tenant_id = v_tenant_id
    and item.is_listed;

  update public.supplier_catalog_feed_runs run
  set status = 'ok',
      delisted_count = v_delisted,
      http_status = v_http,
      bytes = v_bytes,
      duration_ms = v_duration,
      finished_at = v_now
  where run.id = p_run_id;
  update public.supplier_catalog_feeds feed
  set last_ok_at = v_now,
      last_status = 'ok',
      last_run_id = p_run_id,
      listed_count = v_listed,
      in_stock_count = v_in_stock,
      consecutive_failures = 0,
      updated_at = v_now
  where feed.id = v_feed_id
    and feed.tenant_id = v_tenant_id;

  return jsonb_build_object(
    'status', 'ok',
    'rows', v_seen,
    'listed', v_listed,
    'in_stock', v_in_stock,
    'delisted', v_delisted
  );
end;
$$;

comment on function public.finish_supplier_catalog_feed_run_v1(uuid, text[], jsonb) is
  'Service only: closes a complete reading. What the file no longer lists stops being listed and the feed becomes as fresh as now; a file with less than half of what was listed closes as suspect and changes nothing.';

revoke all on function public.fail_supplier_catalog_feed_run_v1(uuid, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.dispatch_supplier_catalog_feed_syncs()
  from public, anon, authenticated, service_role;
revoke all on function public.redeem_supplier_catalog_feed_sync(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.apply_supplier_catalog_feed_rows_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.apply_supplier_catalog_feed_content_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.finish_supplier_catalog_feed_run_v1(uuid, text[], jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.fail_supplier_catalog_feed_run_v1(uuid, text, integer)
  to service_role;
grant execute on function public.dispatch_supplier_catalog_feed_syncs()
  to service_role;
grant execute on function public.redeem_supplier_catalog_feed_sync(uuid, text)
  to service_role;
grant execute on function public.apply_supplier_catalog_feed_rows_v1(uuid, jsonb)
  to service_role;
grant execute on function public.apply_supplier_catalog_feed_content_v1(uuid, jsonb)
  to service_role;
grant execute on function public.finish_supplier_catalog_feed_run_v1(uuid, text[], jsonb)
  to service_role;

-- MKR Imports' feed. It stays silent until its token is stored as the
-- supplier's `api_token` credential with the key `catalog_feed`.
insert into public.supplier_catalog_feeds (
  tenant_id, supplier_id, feed_key, format, endpoint_template,
  credential_key, account_discount_percent
)
select
  supplier.tenant_id,
  supplier.id,
  'catalog',
  'mkr_csv_v1',
  'https://mkr.cl/api/endpoint?token={token}',
  'catalog_feed',
  5
from public.suppliers supplier
where supplier.id = '3f6f71dc-99b8-4f0c-9f44-cd37276fc5ee'
on conflict (tenant_id, supplier_id, feed_key) do nothing;

-- MKR refreshes its file every 30 minutes. Off the minutes other schedules
-- use.
do $schedule$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    perform cron.schedule(
      'vinabike_supplier_catalog_feeds',
      '19,49 * * * *',
      'select public.dispatch_supplier_catalog_feed_syncs();'
    );
  end if;
end;
$schedule$;
