-- Deployment status: PENDING production-derived validation and production rollout.
--
-- Purpose:
--   1. Give every future product tax-rate change an immutable tenant-scoped
--      provenance event.
--   2. Apply the owner-reviewed 19% IVA classification only to the exact
--      Viñabike public-catalog snapshot audited on 2026-07-18.
--   3. Fail closed if membership or relevant commercial fields drift before
--      deployment. Existing online-order line snapshots are never rewritten.
--
-- Forward recovery:
--   Roll back clients while leaving the explicit product classifications and
--   immutable audit evidence in place. Do not clear tax_rate values after they
--   have been used by a checkout; a later correction must be a new audited
--   classification event.

begin;

create table if not exists public.product_tax_classification_batches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  batch_key text not null,
  source text not null,
  reason text not null,
  expected_product_count integer not null check (expected_product_count > 0),
  applied_product_count integer not null check (applied_product_count > 0),
  member_sha256 text not null check (member_sha256 ~ '^[0-9a-f]{64}$'),
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  target_tax_rate numeric(5,2) not null check (target_tax_rate in (0, 19)),
  actor_id uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, batch_key),
  check (applied_product_count = expected_product_count)
);

comment on table public.product_tax_classification_batches is
  'Immutable receipts for fail-closed curated product tax-classification batches.';

create table if not exists public.product_tax_classification_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  event_type text not null check (event_type in (
    'classification_initialized',
    'classification_set',
    'classification_changed',
    'classification_cleared'
  )),
  before_tax_rate numeric(5,2),
  after_tax_rate numeric(5,2),
  source text not null,
  reason text,
  batch_key text,
  product_snapshot jsonb not null default '{}'::jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint product_tax_classification_event_changed check (
    before_tax_rate is distinct from after_tax_rate
  ),
  constraint product_tax_classification_event_batch_fk
    foreign key (tenant_id, batch_key)
    references public.product_tax_classification_batches(tenant_id, batch_key)
    deferrable initially deferred
);

comment on table public.product_tax_classification_events is
  'Append-only before/after provenance for product tax classification; historical order-line snapshots remain independent.';

create index if not exists idx_product_tax_classification_batches_tenant_time
  on public.product_tax_classification_batches(tenant_id, applied_at desc);
create index if not exists idx_product_tax_classification_events_product_time
  on public.product_tax_classification_events(tenant_id, product_id, occurred_at desc);
create unique index if not exists uq_product_tax_classification_event_batch_product
  on public.product_tax_classification_events(tenant_id, batch_key, product_id)
  where batch_key is not null;

alter table public.product_tax_classification_batches enable row level security;
alter table public.product_tax_classification_events enable row level security;

drop policy if exists product_tax_classification_batches_select
  on public.product_tax_classification_batches;
create policy product_tax_classification_batches_select
  on public.product_tax_classification_batches
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists product_tax_classification_events_select
  on public.product_tax_classification_events;
create policy product_tax_classification_events_select
  on public.product_tax_classification_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.product_tax_classification_batches
  from public, anon, authenticated, service_role;
revoke all on public.product_tax_classification_events
  from public, anon, authenticated, service_role;
grant select on public.product_tax_classification_batches to authenticated;
grant select on public.product_tax_classification_events to authenticated;

create or replace function public.prevent_product_tax_classification_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Product tax-classification audit evidence is append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_product_tax_classification_audit_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_product_tax_classification_batches_immutable
  on public.product_tax_classification_batches;
create trigger trg_product_tax_classification_batches_immutable
  before update or delete on public.product_tax_classification_batches
  for each row execute function public.prevent_product_tax_classification_audit_mutation();

drop trigger if exists trg_product_tax_classification_events_immutable
  on public.product_tax_classification_events;
create trigger trg_product_tax_classification_events_immutable
  before update or delete on public.product_tax_classification_events
  for each row execute function public.prevent_product_tax_classification_audit_mutation();

create or replace function public.capture_product_tax_classification_event()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_before numeric(5,2);
  v_event_type text;
  v_source text;
  v_reason text;
  v_batch_key text;
begin
  if tg_op = 'INSERT' then
    if new.tax_rate is null then
      return new;
    end if;
    v_before := null;
    v_event_type := 'classification_initialized';
  else
    if old.tax_rate is not distinct from new.tax_rate then
      return new;
    end if;
    v_before := old.tax_rate;
    v_event_type := case
      when old.tax_rate is null and new.tax_rate is not null
        then 'classification_set'
      when old.tax_rate is not null and new.tax_rate is null
        then 'classification_cleared'
      else 'classification_changed'
    end;
  end if;

  v_source := coalesce(
    nullif(current_setting('app.product_tax_classification_source', true), ''),
    'direct_product_write'
  );
  v_reason := nullif(
    current_setting('app.product_tax_classification_reason', true),
    ''
  );
  v_batch_key := nullif(
    current_setting('app.product_tax_classification_batch_key', true),
    ''
  );

  insert into public.product_tax_classification_events (
    tenant_id,
    product_id,
    event_type,
    before_tax_rate,
    after_tax_rate,
    source,
    reason,
    batch_key,
    product_snapshot,
    actor_id
  ) values (
    new.tenant_id,
    new.id,
    v_event_type,
    v_before,
    new.tax_rate,
    v_source,
    v_reason,
    v_batch_key,
    jsonb_build_object(
      'product_type', new.product_type,
      'price', new.price,
      'is_active', new.is_active,
      'is_published', new.is_published,
      'show_on_website', new.show_on_website,
      'member_sha256', nullif(
        current_setting('app.product_tax_classification_member_sha256', true),
        ''
      ),
      'snapshot_sha256', nullif(
        current_setting('app.product_tax_classification_snapshot_sha256', true),
        ''
      )
    ),
    auth.uid()
  );

  return new;
end;
$$;

revoke all on function public.capture_product_tax_classification_event()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_capture_product_tax_classification_event
  on public.products;
create trigger trg_capture_product_tax_classification_event
  after insert or update of tax_rate on public.products
  for each row execute function public.capture_product_tax_classification_event();

create or replace function public.apply_curated_product_tax_classification_batch(
  p_tenant_id uuid,
  p_batch_key text,
  p_expected_product_count integer,
  p_expected_member_sha256 text,
  p_expected_snapshot_sha256 text,
  p_target_tax_rate numeric,
  p_source text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing public.product_tax_classification_batches%rowtype;
  v_candidate_count integer;
  v_member_sha256 text;
  v_snapshot_sha256 text;
  v_updated_count integer;
  v_event_count integer;
begin
  if p_tenant_id is null
     or nullif(btrim(coalesce(p_batch_key, '')), '') is null
     or p_expected_product_count is null
     or p_expected_product_count < 1
     or p_expected_member_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_snapshot_sha256 !~ '^[0-9a-f]{64}$'
     or p_target_tax_rate not in (0, 19)
     or nullif(btrim(coalesce(p_source, '')), '') is null
     or nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'Invalid curated product tax-classification batch contract'
      using errcode = '22023';
  end if;

  perform 1
    from public.tenants
   where id = p_tenant_id
   for update;
  if not found then
    raise exception 'Unknown tax-classification tenant'
      using errcode = '23503';
  end if;

  -- The aggregate and update must observe one catalog snapshot. This lock is
  -- deliberately short-lived inside the migration transaction.
  lock table public.products in share row exclusive mode;

  select *
    into v_existing
    from public.product_tax_classification_batches
   where tenant_id = p_tenant_id
     and batch_key = p_batch_key;

  if found then
    if v_existing.expected_product_count <> p_expected_product_count
       or v_existing.applied_product_count <> p_expected_product_count
       or v_existing.member_sha256 <> p_expected_member_sha256
       or v_existing.snapshot_sha256 <> p_expected_snapshot_sha256
       or v_existing.target_tax_rate <> p_target_tax_rate
       or v_existing.source <> p_source
       or v_existing.reason <> p_reason then
      raise exception 'Curated product tax batch replay contract does not match immutable receipt'
        using errcode = '23514';
    end if;

    select
      count(*)::integer,
      encode(digest(string_agg(event.product_id::text, ',' order by event.product_id), 'sha256'), 'hex')
      into v_event_count, v_member_sha256
      from public.product_tax_classification_events event
     where event.tenant_id = p_tenant_id
       and event.batch_key = p_batch_key
       and event.after_tax_rate = p_target_tax_rate;

    if v_event_count <> p_expected_product_count
       or v_member_sha256 <> p_expected_member_sha256
       or exists (
         select 1
           from public.product_tax_classification_events event
           left join public.products product
             on product.id = event.product_id
            and product.tenant_id = event.tenant_id
          where event.tenant_id = p_tenant_id
            and event.batch_key = p_batch_key
            and (
              product.id is null
              or product.tax_rate is distinct from p_target_tax_rate
            )
       ) then
      raise exception 'Curated product tax batch replay evidence is incomplete or has drifted'
        using errcode = '23514';
    end if;

    return jsonb_build_object(
      'batch_key', p_batch_key,
      'tenant_id', p_tenant_id,
      'applied_product_count', p_expected_product_count,
      'target_tax_rate', p_target_tax_rate,
      'replayed', true
    );
  end if;

  select
    count(*)::integer,
    encode(digest(string_agg(product.id::text, ',' order by product.id), 'sha256'), 'hex'),
    encode(digest(string_agg(
      concat_ws(
        '|',
        product.id::text,
        product.tenant_id::text,
        product.product_type,
        product.price::text,
        product.is_active::text,
        product.is_published::text,
        product.show_on_website::text,
        coalesce(product.tax_rate::text, 'null')
      ),
      E'\n' order by product.id
    ), 'sha256'), 'hex')
    into v_candidate_count, v_member_sha256, v_snapshot_sha256
    from public.products product
   where product.tenant_id = p_tenant_id
     and product.tax_rate is null
     and product.is_active is true
     and product.is_published is true
     and product.show_on_website is true
     and product.price > 0
     and product.product_type in ('product', 'service');

  if v_candidate_count <> p_expected_product_count
     or v_member_sha256 is distinct from p_expected_member_sha256
     or v_snapshot_sha256 is distinct from p_expected_snapshot_sha256 then
    raise exception 'Curated product tax batch preflight drift: expected % rows / % / %, observed % / % / %',
      p_expected_product_count,
      p_expected_member_sha256,
      p_expected_snapshot_sha256,
      v_candidate_count,
      coalesce(v_member_sha256, 'null'),
      coalesce(v_snapshot_sha256, 'null')
      using errcode = '23514';
  end if;

  insert into public.product_tax_classification_batches (
    tenant_id,
    batch_key,
    source,
    reason,
    expected_product_count,
    applied_product_count,
    member_sha256,
    snapshot_sha256,
    target_tax_rate,
    actor_id
  ) values (
    p_tenant_id,
    p_batch_key,
    p_source,
    p_reason,
    p_expected_product_count,
    p_expected_product_count,
    p_expected_member_sha256,
    p_expected_snapshot_sha256,
    p_target_tax_rate,
    auth.uid()
  );

  perform set_config('app.product_tax_classification_batch_key', p_batch_key, true);
  perform set_config('app.product_tax_classification_source', p_source, true);
  perform set_config('app.product_tax_classification_reason', p_reason, true);
  perform set_config(
    'app.product_tax_classification_member_sha256',
    p_expected_member_sha256,
    true
  );
  perform set_config(
    'app.product_tax_classification_snapshot_sha256',
    p_expected_snapshot_sha256,
    true
  );

  update public.products product
     set tax_rate = p_target_tax_rate
   where product.tenant_id = p_tenant_id
     and product.tax_rate is null
     and product.is_active is true
     and product.is_published is true
     and product.show_on_website is true
     and product.price > 0
     and product.product_type in ('product', 'service');
  get diagnostics v_updated_count = row_count;

  perform set_config('app.product_tax_classification_batch_key', '', true);
  perform set_config('app.product_tax_classification_source', '', true);
  perform set_config('app.product_tax_classification_reason', '', true);
  perform set_config('app.product_tax_classification_member_sha256', '', true);
  perform set_config('app.product_tax_classification_snapshot_sha256', '', true);

  select count(*)::integer
    into v_event_count
    from public.product_tax_classification_events event
   where event.tenant_id = p_tenant_id
     and event.batch_key = p_batch_key
     and event.before_tax_rate is null
     and event.after_tax_rate = p_target_tax_rate;

  if v_updated_count <> p_expected_product_count
     or v_event_count <> p_expected_product_count
     or exists (
       select 1
         from public.product_tax_classification_events event
         join public.products product
           on product.id = event.product_id
          and product.tenant_id = event.tenant_id
        where event.tenant_id = p_tenant_id
          and event.batch_key = p_batch_key
          and product.tax_rate is distinct from p_target_tax_rate
     ) then
    raise exception 'Curated product tax batch postcondition failed'
      using errcode = '23514';
  end if;

  return jsonb_build_object(
    'batch_key', p_batch_key,
    'tenant_id', p_tenant_id,
    'applied_product_count', v_updated_count,
    'target_tax_rate', p_target_tax_rate,
    'replayed', false
  );
end;
$$;

comment on function public.apply_curated_product_tax_classification_batch(
  uuid, text, integer, text, text, numeric, text, text
) is
  'Service-only, replay-safe and fail-closed product tax batch command. It updates current products and preserves immutable provenance without rewriting historical order-line snapshots.';

revoke all on function public.apply_curated_product_tax_classification_batch(
  uuid, text, integer, text, text, numeric, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.apply_curated_product_tax_classification_batch(
  uuid, text, integer, text, text, numeric, text, text
) to service_role;

-- Exact no-PII production fingerprint captured read-only on 2026-07-18.
-- 1,525 public products + 57 public services; all positive-price and currently
-- unclassified. Eleven zero-price public records, one foreign-tenant pseudo
-- product and 61 non-public records are deliberately excluded for review.
do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
begin
  -- Empty schema bootstraps contain no operational tenant data. If this tenant
  -- has any catalog rows, however, the exact audited snapshot is mandatory.
  if exists (select 1 from public.tenants where id = v_tenant_id)
     and exists (select 1 from public.products where tenant_id = v_tenant_id) then
    perform public.apply_curated_product_tax_classification_batch(
      v_tenant_id,
      'vinabike-public-catalog-iva19-20260718-v1',
      1582,
      '46a611d0589ed137caf4da2f07a418cd5515ce0da4ff30f15fb1a5da828552f7',
      '050fae26054c3d365561e971b60c6d7175218e9cb3ca7eedc5456b5303246d53',
      19,
      'owner_approved_catalog_audit',
      'Ordinary positive-price products and services sold through the public Viñabike catalog are classified as 19% IVA; ambiguous and non-public records remain untouched.'
    );
  end if;
end;
$$;

commit;
