-- NOT DEPLOYED.
--
-- Add the first fail-closed storefront publication ledger for the Viñabike
-- storefront. PostgreSQL owns revision ordering, coalescing, successor
-- creation, fenced claims, workflow evidence, and editor authorization.
--
-- Initial scope:
--   * tenant 5443b130-cc28-45af-a420-cd500b288890 only;
--   * target vinabike-store only;
--   * https://vinabike.cl and https://vinabike-store.web.app only;
--   * dispatch remains disabled until a separately reviewed activation.
--
-- Forward behavior:
--   * tracked editorial owner changes advance a monotonic desired revision;
--   * queued changes coalesce and an in-flight request gets one successor;
--   * workers claim dispatch/reconciliation work with SKIP LOCKED and a fence;
--   * workflow begin, seal, and completion are exact-run/idempotency guarded;
--   * authenticated status/retry calls reuse can_edit_tenant_settings();
--   * cron can invoke only the fixed Edge endpoint with a dedicated Vault key.
--
-- Recovery:
--   Set dispatch_enabled=false first. The additive triggers, functions, cron
--   job, and tables can then be removed in reverse dependency order. Owner
--   data is never rewritten by this migration.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '90s';

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.storefront_publication_targets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  target_key text not null,
  expected_store_origin text not null,
  expected_firebase_origin text not null,
  dispatch_enabled boolean not null default false,
  desired_revision bigint not null default 0,
  last_published_revision bigint not null default 0,
  claim_fence bigint not null default 0,
  last_owner_change_at timestamptz,
  last_published_request_id uuid,
  last_published_attempt_id uuid,
  last_published_at timestamptz,
  last_dispatch_tick_at timestamptz,
  last_dispatch_request_id bigint,
  last_dispatch_error_class text,
  last_dispatch_error_message text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint storefront_publication_targets_owner_key
    unique (tenant_id, target_key),
  constraint storefront_publication_targets_tenant_identity_key
    unique (id, tenant_id),
  constraint storefront_publication_targets_initial_scope_check check (
    tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target_key = 'vinabike-store'
    and expected_store_origin = 'https://vinabike.cl'
    and expected_firebase_origin = 'https://vinabike-store.web.app'
  ),
  constraint storefront_publication_targets_revision_check check (
    desired_revision >= 0
    and last_published_revision >= 0
    and last_published_revision <= desired_revision
    and claim_fence >= 0
  ),
  constraint storefront_publication_targets_error_length_check check (
    char_length(last_dispatch_error_class) <= 120
    and char_length(last_dispatch_error_message) <= 2000
  )
);

create table if not exists public.storefront_publication_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  target_id uuid not null,
  requested_revision bigint not null,
  state text not null default 'queued',
  source text not null default 'owner_change',
  supersedes_request_id uuid,
  requested_by_user_id uuid references auth.users(id) on delete set null,
  coalesced_count integer not null default 0,
  first_change_at timestamptz not null default clock_timestamp(),
  last_change_at timestamptz not null default clock_timestamp(),
  available_at timestamptz not null default clock_timestamp(),
  attempt_count integer not null default 0,
  max_attempts integer not null default 3,
  active_attempt_id uuid,
  lease_owner text,
  lease_token uuid,
  lease_fence bigint,
  lease_expires_at timestamptz,
  failure_stage text,
  error_class text,
  error_message text,
  created_at timestamptz not null default clock_timestamp(),
  claimed_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  constraint storefront_publication_requests_target_fkey
    foreign key (target_id, tenant_id)
    references public.storefront_publication_targets(id, tenant_id)
    on delete cascade,
  constraint storefront_publication_requests_identity_key
    unique (id, tenant_id, target_id),
  constraint storefront_publication_requests_revision_check
    check (requested_revision > 0),
  constraint storefront_publication_requests_state_check check (
    state in (
      'queued',
      'dispatching',
      'dispatched',
      'dispatch_unknown',
      'running',
      'sealed',
      'succeeded',
      'failed',
      'dead_letter',
      'superseded'
    )
  ),
  constraint storefront_publication_requests_source_check check (
    source in ('owner_change', 'manual_retry', 'activation_baseline')
  ),
  constraint storefront_publication_requests_attempt_budget_check check (
    attempt_count >= 0
    and max_attempts between 1 and 5
    and attempt_count <= max_attempts
    and coalesced_count >= 0
  ),
  constraint storefront_publication_requests_lease_shape_check check (
    (
      state = 'dispatching'
      and lease_owner is not null
      and lease_token is not null
      and lease_fence is not null
      and lease_expires_at is not null
    )
    or (
      state = 'dispatch_unknown'
      and (
        (
          lease_owner is null
          and lease_token is null
          and lease_fence is null
          and lease_expires_at is null
        )
        or (
          lease_owner is not null
          and lease_token is not null
          and lease_fence is not null
          and lease_expires_at is not null
        )
      )
    )
    or (
      state not in ('dispatching', 'dispatch_unknown')
      and lease_owner is null
      and lease_token is null
      and lease_fence is null
      and lease_expires_at is null
    )
  ),
  constraint storefront_publication_requests_text_length_check check (
    char_length(lease_owner) <= 128
    and char_length(failure_stage) <= 80
    and char_length(error_class) <= 120
    and char_length(error_message) <= 2000
  )
);

create table if not exists public.storefront_publication_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  target_id uuid not null,
  request_id uuid not null,
  attempt_no integer not null,
  lease_owner text not null,
  lease_token uuid not null,
  lease_fence bigint not null,
  state text not null default 'dispatching',
  dispatch_http_status integer,
  dispatch_started_at timestamptz not null default clock_timestamp(),
  dispatch_completed_at timestamptz,
  github_run_id bigint,
  github_run_attempt integer,
  github_sha text,
  github_ref text,
  workflow_started_at timestamptz,
  heartbeat_at timestamptz,
  sealed_at timestamptz,
  requested_revision bigint not null,
  owner_source_sha256 text,
  build_input_sha256 text,
  release_manifest_sha256 text,
  release_commit text,
  release_run_id bigint,
  release_built_at timestamptz,
  release_request_id uuid,
  release_revision bigint,
  release_owner_source_sha256 text,
  primary_verified_at timestamptz,
  custom_verified_at timestamptz,
  failure_stage text,
  error_class text,
  error_message text,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint storefront_publication_attempts_request_fkey
    foreign key (request_id, tenant_id, target_id)
    references public.storefront_publication_requests(id, tenant_id, target_id)
    on delete cascade,
  constraint storefront_publication_attempts_identity_key
    unique (id, request_id, tenant_id, target_id),
  constraint storefront_publication_attempts_request_number_key
    unique (request_id, attempt_no),
  constraint storefront_publication_attempts_state_check check (
    state in (
      'dispatching',
      'dispatched',
      'dispatch_unknown',
      'running',
      'sealed',
      'succeeded',
      'failed',
      'dead_letter',
      'superseded'
    )
  ),
  constraint storefront_publication_attempts_values_check check (
    attempt_no > 0
    and lease_fence > 0
    and requested_revision > 0
    and (dispatch_http_status is null or dispatch_http_status between 100 and 599)
    and (github_run_id is null or github_run_id > 0)
    and (github_run_attempt is null or github_run_attempt > 0)
    and (release_run_id is null or release_run_id > 0)
    and (release_revision is null or release_revision > 0)
  ),
  constraint storefront_publication_attempts_hash_shape_check check (
    (github_sha is null or github_sha ~ '^[0-9a-f]{40}$')
    and (
      owner_source_sha256 is null
      or owner_source_sha256 ~ '^[0-9a-f]{64}$'
    )
    and (
      build_input_sha256 is null
      or build_input_sha256 ~ '^[0-9a-f]{64}$'
    )
    and (
      release_manifest_sha256 is null
      or release_manifest_sha256 ~ '^[0-9a-f]{64}$'
    )
    and (
      release_commit is null
      or release_commit ~ '^[0-9a-f]{40}$'
    )
    and (
      release_owner_source_sha256 is null
      or release_owner_source_sha256 ~ '^[0-9a-f]{64}$'
    )
  ),
  constraint storefront_publication_attempts_text_length_check check (
    char_length(lease_owner) <= 128
    and
    char_length(github_ref) <= 120
    and char_length(failure_stage) <= 80
    and char_length(error_class) <= 120
    and char_length(error_message) <= 2000
  )
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.storefront_publication_requests'::regclass
      and constraint_row.conname =
        'storefront_publication_requests_supersedes_fkey'
  ) then
    alter table public.storefront_publication_requests
      add constraint storefront_publication_requests_supersedes_fkey
      foreign key (supersedes_request_id)
      references public.storefront_publication_requests(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.storefront_publication_requests'::regclass
      and constraint_row.conname =
        'storefront_publication_requests_active_attempt_fkey'
  ) then
    alter table public.storefront_publication_requests
      add constraint storefront_publication_requests_active_attempt_fkey
      foreign key (active_attempt_id)
      references public.storefront_publication_attempts(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.storefront_publication_targets'::regclass
      and constraint_row.conname =
        'storefront_publication_targets_last_request_fkey'
  ) then
    alter table public.storefront_publication_targets
      add constraint storefront_publication_targets_last_request_fkey
      foreign key (last_published_request_id)
      references public.storefront_publication_requests(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.storefront_publication_targets'::regclass
      and constraint_row.conname =
        'storefront_publication_targets_last_attempt_fkey'
  ) then
    alter table public.storefront_publication_targets
      add constraint storefront_publication_targets_last_attempt_fkey
      foreign key (last_published_attempt_id)
      references public.storefront_publication_attempts(id)
      on delete set null;
  end if;
end
$$;

create index if not exists idx_storefront_publication_targets_tenant
  on public.storefront_publication_targets(tenant_id);

create index if not exists idx_storefront_publication_requests_tenant_state
  on public.storefront_publication_requests(tenant_id, state, available_at);

create unique index if not exists uq_storefront_publication_requests_queued
  on public.storefront_publication_requests(target_id)
  where state = 'queued';

create unique index if not exists uq_storefront_publication_requests_active
  on public.storefront_publication_requests(target_id)
  where state in (
    'dispatching',
    'dispatched',
    'dispatch_unknown',
    'running',
    'sealed'
  );

create index if not exists idx_storefront_publication_attempts_request
  on public.storefront_publication_attempts(
    tenant_id,
    request_id,
    attempt_no desc
  );

create unique index if not exists uq_storefront_publication_attempts_github_run
  on public.storefront_publication_attempts(
    github_run_id,
    github_run_attempt
  )
  where github_run_id is not null
    and github_run_attempt is not null;

alter table public.storefront_publication_targets enable row level security;
alter table public.storefront_publication_targets force row level security;
alter table public.storefront_publication_requests enable row level security;
alter table public.storefront_publication_requests force row level security;
alter table public.storefront_publication_attempts enable row level security;
alter table public.storefront_publication_attempts force row level security;

revoke all on table public.storefront_publication_targets
  from public, anon, authenticated, service_role;
revoke all on table public.storefront_publication_requests
  from public, anon, authenticated, service_role;
revoke all on table public.storefront_publication_attempts
  from public, anon, authenticated, service_role;

grant select on table public.storefront_publication_targets to service_role;
grant select on table public.storefront_publication_requests to service_role;
grant select on table public.storefront_publication_attempts to service_role;

insert into public.storefront_publication_targets (
  tenant_id,
  target_key,
  expected_store_origin,
  expected_firebase_origin
)
select
  tenant.id,
  'vinabike-store',
  'https://vinabike.cl',
  'https://vinabike-store.web.app'
from public.tenants tenant
where tenant.id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
on conflict (tenant_id, target_key) do nothing;

create or replace function private.require_storefront_publication_service()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'storefront_publication_service_forbidden'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function private.storefront_publication_retryable_error(
  p_error_class text
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(p_error_class, '') = any (
    array[
      'dispatch_network',
      'dispatch_timeout',
      'github_rate_limit',
      'github_transient',
      'github_runner_capacity',
      'firebase_transient',
      'callback_network'
    ]::text[]
  );
$$;

create or replace function private.storefront_publication_owner_projection(
  p_owner_kind text,
  p_row jsonb
)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(entry.key, entry.value),
    '{}'::jsonb
  )
  from jsonb_each(coalesce(p_row, '{}'::jsonb)) entry
  where entry.key = any (
    case p_owner_kind
      when 'website_settings' then array[
        'tenant_id', 'key', 'value'
      ]::text[]
      when 'website_pages' then array[
        'id', 'tenant_id', 'slug', 'title', 'meta_title',
        'meta_description', 'meta_keywords', 'og_image_url',
        'is_published', 'is_home'
      ]::text[]
      when 'website_blocks' then array[
        'id', 'tenant_id', 'page_id', 'block_type', 'block_data',
        'order_index', 'is_visible'
      ]::text[]
      when 'products' then array[
        'id', 'tenant_id', 'name', 'description', 'website_description',
        'website_name', 'website_price', 'website_image_url',
        'website_image_url_optimized', 'website_image_urls',
        'website_seo_title', 'website_seo_description',
        'website_search_terms', 'website_merchant_title',
        'website_merchant_description', 'website_merchant_gtin',
        'website_merchant_mpn', 'website_merchant_brand',
        'website_google_product_category', 'is_google_merchant', 'price',
        'price_currency', 'sku', 'gtin', 'barcode', 'image_url',
        'image_url_optimized', 'image_urls', 'brand_id', 'brand',
        'category_id', 'category_name', 'track_stock', 'is_set',
        'product_type', 'is_active', 'is_published', 'show_on_website'
      ]::text[]
      when 'product_categories' then array[
        'id', 'tenant_id', 'name', 'full_path', 'parent_id', 'level',
        'description', 'image_url', 'sort_order', 'is_active',
        'show_on_website'
      ]::text[]
      when 'product_brands' then array[
        'id', 'tenant_id', 'name', 'is_active'
      ]::text[]
      when 'product_url_aliases' then array[
        'id', 'tenant_id', 'product_id', 'alias_path', 'source'
      ]::text[]
      else array[]::text[]
    end
  );
$$;

create or replace function private.ensure_storefront_publication_successor(
  p_target_id uuid,
  p_supersedes_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.storefront_publication_targets%rowtype;
  v_request_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.id = p_target_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found
     or not v_target.dispatch_enabled
     or v_target.desired_revision <= 0 then
    return null;
  end if;

  select request.id
  into v_request_id
  from public.storefront_publication_requests request
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state = 'queued'
  for update;

  if found then
    update public.storefront_publication_requests request
    set requested_revision = v_target.desired_revision,
        supersedes_request_id = coalesce(
          request.supersedes_request_id,
          p_supersedes_request_id
        ),
        coalesced_count = request.coalesced_count + 1,
        last_change_at = v_now,
        available_at = least(
          request.created_at + interval '5 minutes',
          v_now + interval '45 seconds'
        ),
        updated_at = v_now
    where request.id = v_request_id;
    return v_request_id;
  end if;

  insert into public.storefront_publication_requests (
    tenant_id,
    target_id,
    requested_revision,
    source,
    supersedes_request_id,
    first_change_at,
    last_change_at,
    available_at
  ) values (
    v_target.tenant_id,
    v_target.id,
    v_target.desired_revision,
    'owner_change',
    p_supersedes_request_id,
    v_now,
    v_now,
    v_now + interval '45 seconds'
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

create or replace function private.mark_storefront_publication_change(
  p_tenant_id uuid,
  p_owner_kind text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target public.storefront_publication_targets%rowtype;
  v_queued_request_id uuid;
  v_active_request_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  if p_tenant_id is distinct from
    '5443b130-cc28-45af-a420-cd500b288890'::uuid then
    return null;
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.tenant_id = p_tenant_id
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found then
    return null;
  end if;

  update public.storefront_publication_targets target
  set desired_revision = target.desired_revision + 1,
      last_owner_change_at = v_now,
      updated_at = v_now
  where target.id = v_target.id
  returning target.desired_revision into v_target.desired_revision;

  if not v_target.dispatch_enabled then
    return v_target.desired_revision;
  end if;

  select request.id
  into v_queued_request_id
  from public.storefront_publication_requests request
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state = 'queued'
  for update;

  if found then
    update public.storefront_publication_requests request
    set requested_revision = v_target.desired_revision,
        coalesced_count = request.coalesced_count + 1,
        last_change_at = v_now,
        available_at = least(
          request.created_at + interval '5 minutes',
          v_now + interval '45 seconds'
        ),
        updated_at = v_now
    where request.id = v_queued_request_id;
    return v_target.desired_revision;
  end if;

  select request.id
  into v_active_request_id
  from public.storefront_publication_requests request
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state in (
      'dispatching',
      'dispatched',
      'dispatch_unknown',
      'running',
      'sealed'
    )
  for update;

  perform private.ensure_storefront_publication_successor(
    v_target.id,
    v_active_request_id
  );

  return v_target.desired_revision;
end;
$$;

create or replace function private.storefront_publication_owner_row_relevant(
  p_owner_kind text,
  p_row jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := nullif(p_row->>'tenant_id', '')::uuid;
begin
  if p_row is null
     or v_tenant_id is distinct from
       '5443b130-cc28-45af-a420-cd500b288890'::uuid then
    return false;
  end if;

  case p_owner_kind
    when 'website_settings' then
      return true;
    when 'website_pages' then
      return coalesce((p_row->>'is_published')::boolean, false);
    when 'website_blocks' then
      return coalesce((p_row->>'is_visible')::boolean, false)
        and exists (
          select 1
          from public.website_pages page
          where page.id = nullif(p_row->>'page_id', '')::uuid
            and page.tenant_id = v_tenant_id
            and page.is_published is true
        );
    when 'products' then
      return coalesce((p_row->>'is_active')::boolean, false)
        and coalesce((p_row->>'is_published')::boolean, false)
        and coalesce((p_row->>'show_on_website')::boolean, false)
        and coalesce(p_row->>'product_type', '') = 'product';
    when 'product_categories' then
      return coalesce((p_row->>'is_active')::boolean, false);
    when 'product_url_aliases' then
      return true;
    when 'product_brands' then
      return exists (
        select 1
        from public.products product
        where product.tenant_id = v_tenant_id
          and product.brand_id = nullif(p_row->>'id', '')::uuid
          and product.is_active is true
          and product.is_published is true
          and product.show_on_website is true
          and product.product_type = 'product'
      );
    else
      return false;
  end case;
end;
$$;

create or replace function private.storefront_publication_owner_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_kind text := tg_table_name;
  v_old_rows jsonb := '{}'::jsonb;
  v_new_rows jsonb := '{}'::jsonb;
  v_row_id text;
  v_old jsonb;
  v_new jsonb;
begin
  -- Transition tables make a bulk editorial statement one publication
  -- revision and one target lock, regardless of its row count.
  if nullif(tg_argv[0], '') is not null then
    execute format(
      'select coalesce('
      || 'jsonb_object_agg(owner_row.id::text, to_jsonb(owner_row)), '
      || '''{}''::jsonb) from %I owner_row',
      tg_argv[0]
    ) into v_old_rows;
  end if;

  if nullif(tg_argv[1], '') is not null then
    execute format(
      'select coalesce('
      || 'jsonb_object_agg(owner_row.id::text, to_jsonb(owner_row)), '
      || '''{}''::jsonb) from %I owner_row',
      tg_argv[1]
    ) into v_new_rows;
  end if;

  for v_row_id in
    select row_id
    from jsonb_object_keys(v_old_rows || v_new_rows) row_id
  loop
    v_old := v_old_rows->v_row_id;
    v_new := v_new_rows->v_row_id;

    if private.storefront_publication_owner_projection(
         v_owner_kind,
         v_old
       ) is not distinct from
       private.storefront_publication_owner_projection(
         v_owner_kind,
         v_new
       ) then
      continue;
    end if;

    if private.storefront_publication_owner_row_relevant(
         v_owner_kind,
         v_old
       )
       or private.storefront_publication_owner_row_relevant(
         v_owner_kind,
         v_new
       ) then
      perform private.mark_storefront_publication_change(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        v_owner_kind
      );
      exit;
    end if;
  end loop;

  return null;
end;
$$;

-- Transition relations require one trigger per event. Each trigger is
-- statement-level, so editor imports and bulk edits cannot amplify revisions.
drop trigger if exists trg_storefront_publication_website_settings
  on public.website_settings;
drop trigger if exists trg_storefront_publication_website_settings_insert
  on public.website_settings;
create trigger trg_storefront_publication_website_settings_insert
  after insert on public.website_settings
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_website_settings_update
  on public.website_settings;
create trigger trg_storefront_publication_website_settings_update
  after update on public.website_settings
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_website_settings_delete
  on public.website_settings;
create trigger trg_storefront_publication_website_settings_delete
  after delete on public.website_settings
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

drop trigger if exists trg_storefront_publication_website_pages
  on public.website_pages;
drop trigger if exists trg_storefront_publication_website_pages_insert
  on public.website_pages;
create trigger trg_storefront_publication_website_pages_insert
  after insert on public.website_pages
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_website_pages_update
  on public.website_pages;
create trigger trg_storefront_publication_website_pages_update
  after update on public.website_pages
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_website_pages_delete
  on public.website_pages;
create trigger trg_storefront_publication_website_pages_delete
  after delete on public.website_pages
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

drop trigger if exists trg_storefront_publication_website_blocks
  on public.website_blocks;
drop trigger if exists trg_storefront_publication_website_blocks_insert
  on public.website_blocks;
create trigger trg_storefront_publication_website_blocks_insert
  after insert on public.website_blocks
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_website_blocks_update
  on public.website_blocks;
create trigger trg_storefront_publication_website_blocks_update
  after update on public.website_blocks
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_website_blocks_delete
  on public.website_blocks;
create trigger trg_storefront_publication_website_blocks_delete
  after delete on public.website_blocks
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

drop trigger if exists trg_storefront_publication_products
  on public.products;
drop trigger if exists trg_storefront_publication_products_insert
  on public.products;
create trigger trg_storefront_publication_products_insert
  after insert on public.products
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_products_update
  on public.products;
create trigger trg_storefront_publication_products_update
  after update on public.products
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_products_delete
  on public.products;
create trigger trg_storefront_publication_products_delete
  after delete on public.products
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

drop trigger if exists trg_storefront_publication_product_categories
  on public.product_categories;
drop trigger if exists trg_storefront_publication_product_categories_insert
  on public.product_categories;
create trigger trg_storefront_publication_product_categories_insert
  after insert on public.product_categories
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_product_categories_update
  on public.product_categories;
create trigger trg_storefront_publication_product_categories_update
  after update on public.product_categories
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_product_categories_delete
  on public.product_categories;
create trigger trg_storefront_publication_product_categories_delete
  after delete on public.product_categories
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

drop trigger if exists trg_storefront_publication_product_brands
  on public.product_brands;
drop trigger if exists trg_storefront_publication_product_brands_insert
  on public.product_brands;
create trigger trg_storefront_publication_product_brands_insert
  after insert on public.product_brands
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_product_brands_update
  on public.product_brands;
create trigger trg_storefront_publication_product_brands_update
  after update on public.product_brands
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_product_brands_delete
  on public.product_brands;
create trigger trg_storefront_publication_product_brands_delete
  after delete on public.product_brands
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

drop trigger if exists trg_storefront_publication_product_url_aliases
  on public.product_url_aliases;
drop trigger if exists trg_storefront_publication_product_url_aliases_insert
  on public.product_url_aliases;
create trigger trg_storefront_publication_product_url_aliases_insert
  after insert on public.product_url_aliases
  referencing new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('', 'storefront_new_rows');
drop trigger if exists trg_storefront_publication_product_url_aliases_update
  on public.product_url_aliases;
create trigger trg_storefront_publication_product_url_aliases_update
  after update on public.product_url_aliases
  referencing old table as storefront_old_rows
              new table as storefront_new_rows
  for each statement execute function
    private.storefront_publication_owner_trigger(
      'storefront_old_rows',
      'storefront_new_rows'
    );
drop trigger if exists trg_storefront_publication_product_url_aliases_delete
  on public.product_url_aliases;
create trigger trg_storefront_publication_product_url_aliases_delete
  after delete on public.product_url_aliases
  referencing old table as storefront_old_rows
  for each statement execute function
    private.storefront_publication_owner_trigger('storefront_old_rows', '');

create or replace function public.claim_storefront_publication_requests(
  p_worker_id text,
  p_batch_size integer default 1,
  p_lease_seconds integer default 90
)
returns table (
  claim_action text,
  request_id uuid,
  attempt_id uuid,
  lease_token uuid,
  lease_fence bigint,
  requested_revision bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_request public.storefront_publication_requests%rowtype;
  v_target public.storefront_publication_targets%rowtype;
  v_attempt public.storefront_publication_attempts%rowtype;
  v_attempt_id uuid;
  v_attempt_no integer;
  v_token uuid;
  v_fence bigint;
  v_claimed integer := 0;
begin
  perform private.require_storefront_publication_service();

  if nullif(btrim(p_worker_id), '') is null
     or char_length(p_worker_id) > 128
     or p_batch_size not between 1 and 10
     or p_lease_seconds not between 30 and 300 then
    raise exception 'storefront_publication_invalid_claim'
      using errcode = '22023';
  end if;

  -- A dispatch lease can expire after GitHub accepted the request but before
  -- the Edge worker persisted the 204. Preserve ambiguity and reconcile it;
  -- never turn that timeout directly into a duplicate dispatch.
  for v_request in
    select request.*
    from public.storefront_publication_requests request
    join public.storefront_publication_targets target
      on target.id = request.target_id
     and target.tenant_id = request.tenant_id
    where request.state = 'dispatching'
      and request.lease_expires_at <= v_now
      and target.tenant_id =
        '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and target.target_key = 'vinabike-store'
    order by request.lease_expires_at, request.id
    for update of request skip locked
  loop
    update public.storefront_publication_attempts attempt
    set state = 'dispatch_unknown',
        error_class = 'dispatch_lease_expired',
        error_message = 'Dispatch lease expired before acknowledgement',
        updated_at = v_now
    where attempt.id = v_request.active_attempt_id
      and attempt.request_id = v_request.id
      and attempt.state = 'dispatching';

    update public.storefront_publication_requests request
    set state = 'dispatch_unknown',
        lease_owner = null,
        lease_token = null,
        lease_fence = null,
        lease_expires_at = null,
        available_at = v_now + interval '5 minutes',
        failure_stage = 'dispatch',
        error_class = 'dispatch_lease_expired',
        error_message = 'Dispatch acknowledgement is unknown',
        updated_at = v_now
    where request.id = v_request.id;
  end loop;

  -- Reconciliation leases are also recoverable. Expiration releases only the
  -- reconciliation claim; it does not authorize a new workflow dispatch.
  update public.storefront_publication_requests request
  set lease_owner = null,
      lease_token = null,
      lease_fence = null,
      lease_expires_at = null,
      available_at = greatest(
        request.available_at,
        v_now + interval '1 minute'
      ),
      updated_at = v_now
  from public.storefront_publication_targets target
  where target.id = request.target_id
    and target.tenant_id = request.tenant_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and request.state = 'dispatch_unknown'
    and request.lease_expires_at <= v_now;

  -- Ambiguous dispatches are returned as reconciliation work before new
  -- dispatches. The attempt fence remains immutable; the claim token rotates.
  for v_request in
    select request.*
    from public.storefront_publication_requests request
    join public.storefront_publication_targets target
      on target.id = request.target_id
     and target.tenant_id = request.tenant_id
    where request.state = 'dispatch_unknown'
      and request.lease_token is null
      and request.available_at <= v_now
      and target.dispatch_enabled is true
      and target.tenant_id =
        '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and target.target_key = 'vinabike-store'
      and target.expected_store_origin = 'https://vinabike.cl'
      and target.expected_firebase_origin =
        'https://vinabike-store.web.app'
    order by request.available_at, request.created_at, request.id
    for update of request skip locked
    limit p_batch_size
  loop
    select attempt.*
    into v_attempt
    from public.storefront_publication_attempts attempt
    where attempt.id = v_request.active_attempt_id
      and attempt.request_id = v_request.id
      and attempt.tenant_id = v_request.tenant_id
      and attempt.target_id = v_request.target_id
      and attempt.state = 'dispatch_unknown'
    for update;

    if not found then
      update public.storefront_publication_requests request
      set state = 'failed',
          failure_stage = 'dispatch',
          error_class = 'missing_active_attempt',
          error_message = 'Ambiguous request has no active attempt',
          finished_at = v_now,
          updated_at = v_now
      where request.id = v_request.id;
      continue;
    end if;

    v_token := gen_random_uuid();

    update public.storefront_publication_attempts attempt
    set lease_owner = btrim(p_worker_id),
        lease_token = v_token,
        updated_at = v_now
    where attempt.id = v_attempt.id;

    update public.storefront_publication_requests request
    set lease_owner = btrim(p_worker_id),
        lease_token = v_token,
        lease_fence = v_attempt.lease_fence,
        lease_expires_at =
          v_now + make_interval(secs => p_lease_seconds),
        updated_at = v_now
    where request.id = v_request.id;

    claim_action := 'reconcile';
    request_id := v_request.id;
    attempt_id := v_attempt.id;
    lease_token := v_token;
    lease_fence := v_attempt.lease_fence;
    requested_revision := v_request.requested_revision;
    v_claimed := v_claimed + 1;
    return next;
  end loop;

  if v_claimed >= p_batch_size then
    return;
  end if;

  -- A queued successor is claimable only after the previous request becomes
  -- terminal. The target row serializes the target-wide fence.
  for v_request in
    select request.*
    from public.storefront_publication_requests request
    join public.storefront_publication_targets target
      on target.id = request.target_id
     and target.tenant_id = request.tenant_id
    where request.state = 'queued'
      and request.available_at <= v_now
      and request.attempt_count < request.max_attempts
      and target.dispatch_enabled is true
      and target.tenant_id =
        '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and target.target_key = 'vinabike-store'
      and target.expected_store_origin = 'https://vinabike.cl'
      and target.expected_firebase_origin =
        'https://vinabike-store.web.app'
      and not exists (
        select 1
        from public.storefront_publication_requests active_request
        where active_request.target_id = request.target_id
          and active_request.tenant_id = request.tenant_id
          and active_request.state in (
            'dispatching',
            'dispatched',
            'dispatch_unknown',
            'running',
            'sealed'
          )
      )
    order by request.available_at, request.created_at, request.id
    for update of request skip locked
    limit (p_batch_size - v_claimed)
  loop
    select target.*
    into v_target
    from public.storefront_publication_targets target
    where target.id = v_request.target_id
      and target.tenant_id = v_request.tenant_id
      and target.dispatch_enabled is true
      and target.tenant_id =
        '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and target.target_key = 'vinabike-store'
      and target.expected_store_origin = 'https://vinabike.cl'
      and target.expected_firebase_origin =
        'https://vinabike-store.web.app'
    for update;

    if not found then
      continue;
    end if;

    if exists (
      select 1
      from public.storefront_publication_requests active_request
      where active_request.target_id = v_target.id
        and active_request.tenant_id = v_target.tenant_id
        and active_request.state in (
          'dispatching',
          'dispatched',
          'dispatch_unknown',
          'running',
          'sealed'
        )
    ) then
      continue;
    end if;

    update public.storefront_publication_targets target
    set claim_fence = target.claim_fence + 1,
        updated_at = v_now
    where target.id = v_target.id
    returning target.claim_fence into v_fence;

    v_attempt_no := v_request.attempt_count + 1;
    v_token := gen_random_uuid();

    insert into public.storefront_publication_attempts (
      tenant_id,
      target_id,
      request_id,
      attempt_no,
      lease_owner,
      lease_token,
      lease_fence,
      state,
      dispatch_started_at,
      requested_revision
    ) values (
      v_request.tenant_id,
      v_request.target_id,
      v_request.id,
      v_attempt_no,
      btrim(p_worker_id),
      v_token,
      v_fence,
      'dispatching',
      v_now,
      v_target.desired_revision
    )
    returning id into v_attempt_id;

    update public.storefront_publication_requests request
    set requested_revision = v_target.desired_revision,
        state = 'dispatching',
        attempt_count = v_attempt_no,
        active_attempt_id = v_attempt_id,
        lease_owner = btrim(p_worker_id),
        lease_token = v_token,
        lease_fence = v_fence,
        lease_expires_at =
          v_now + make_interval(secs => p_lease_seconds),
        claimed_at = coalesce(request.claimed_at, v_now),
        failure_stage = null,
        error_class = null,
        error_message = null,
        updated_at = v_now
    where request.id = v_request.id;

    claim_action := 'dispatch';
    request_id := v_request.id;
    attempt_id := v_attempt_id;
    lease_token := v_token;
    lease_fence := v_fence;
    requested_revision := v_target.desired_revision;
    return next;
  end loop;
end;
$$;

create or replace function public.complete_storefront_publication_dispatch(
  p_request_id uuid,
  p_attempt_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_lease_fence bigint,
  p_outcome text,
  p_http_status integer default null,
  p_error_class text default null,
  p_error_message text default null,
  p_retry_after_seconds integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.storefront_publication_requests%rowtype;
  v_attempt public.storefront_publication_attempts%rowtype;
  v_target public.storefront_publication_targets%rowtype;
  v_now timestamptz := clock_timestamp();
  v_retry_seconds integer;
  v_successor_exists boolean;
  v_next_state text;
begin
  perform private.require_storefront_publication_service();

  if p_request_id is null
     or p_attempt_id is null
     or nullif(btrim(p_worker_id), '') is null
     or char_length(p_worker_id) > 128
     or p_lease_token is null
     or p_lease_fence is null
     or p_lease_fence <= 0
     or p_outcome not in (
       'dispatched',
       'retry',
       'dispatch_unknown',
       'permanent_failure'
     )
     or (
       p_http_status is not null
       and p_http_status not between 100 and 599
     ) then
    raise exception 'storefront_publication_invalid_dispatch_completion'
      using errcode = '22023';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id;

  if not found then
    raise exception 'storefront_publication_request_not_found'
      using errcode = '22023';
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.id = v_request.target_id
    and target.tenant_id = v_request.tenant_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found then
    raise exception 'storefront_publication_target_forbidden'
      using errcode = '42501';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id
    and request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
  for update;

  select attempt.*
  into v_attempt
  from public.storefront_publication_attempts attempt
  where attempt.id = p_attempt_id
    and attempt.request_id = v_request.id
    and attempt.target_id = v_target.id
    and attempt.tenant_id = v_target.tenant_id
  for update;

  if not found
     or v_attempt.lease_owner is distinct from btrim(p_worker_id)
     or v_attempt.lease_token is distinct from p_lease_token
     or v_attempt.lease_fence is distinct from p_lease_fence then
    raise exception 'storefront_publication_stale_lease'
      using errcode = 'PT409';
  end if;

  -- Exact replay after the first completion lost its response.
  if (
    p_outcome = 'dispatched'
    and v_attempt.state in (
      'dispatched', 'running', 'sealed', 'succeeded'
    )
  ) or (
    p_outcome = 'dispatch_unknown'
    and v_attempt.state = 'dispatch_unknown'
    and v_request.state = 'dispatch_unknown'
    and v_request.lease_token is null
  ) or (
    p_outcome in ('retry', 'permanent_failure')
    and v_attempt.state in ('failed', 'dead_letter', 'superseded')
  ) then
    return jsonb_build_object(
      'ok', true,
      'replay', true,
      'request_id', v_request.id,
      'attempt_id', v_attempt.id,
      'state', v_request.state
    );
  end if;

  if v_request.state not in ('dispatching', 'dispatch_unknown')
     or v_request.active_attempt_id is distinct from v_attempt.id
     or v_request.lease_owner is distinct from btrim(p_worker_id)
     or v_request.lease_token is distinct from p_lease_token
     or v_request.lease_fence is distinct from p_lease_fence
     or v_request.lease_expires_at <= v_now then
    raise exception 'storefront_publication_stale_lease'
      using errcode = 'PT409';
  end if;

  if p_outcome = 'dispatched' then
    update public.storefront_publication_attempts attempt
    set state = 'dispatched',
        dispatch_http_status = coalesce(p_http_status, 204),
        dispatch_completed_at = v_now,
        failure_stage = null,
        error_class = null,
        error_message = null,
        updated_at = v_now
    where attempt.id = v_attempt.id;

    update public.storefront_publication_requests request
    set state = 'dispatched',
        lease_owner = null,
        lease_token = null,
        lease_fence = null,
        lease_expires_at = null,
        failure_stage = null,
        error_class = null,
        error_message = null,
        updated_at = v_now
    where request.id = v_request.id;

  elsif p_outcome = 'dispatch_unknown' then
    v_retry_seconds := greatest(
      300,
      least(coalesce(p_retry_after_seconds, 300), 3600)
    );

    update public.storefront_publication_attempts attempt
    set state = 'dispatch_unknown',
        dispatch_http_status = p_http_status,
        failure_stage = 'dispatch',
        error_class = left(
          coalesce(p_error_class, 'dispatch_timeout'),
          120
        ),
        error_message = left(
          coalesce(p_error_message, 'Dispatch acknowledgement is unknown'),
          2000
        ),
        updated_at = v_now
    where attempt.id = v_attempt.id;

    update public.storefront_publication_requests request
    set state = 'dispatch_unknown',
        lease_owner = null,
        lease_token = null,
        lease_fence = null,
        lease_expires_at = null,
        available_at =
          v_now + make_interval(secs => v_retry_seconds),
        failure_stage = 'dispatch',
        error_class = left(
          coalesce(p_error_class, 'dispatch_timeout'),
          120
        ),
        error_message = left(
          coalesce(p_error_message, 'Dispatch acknowledgement is unknown'),
          2000
        ),
        updated_at = v_now
    where request.id = v_request.id;

  else
    select exists (
      select 1
      from public.storefront_publication_requests successor
      where successor.target_id = v_target.id
        and successor.tenant_id = v_target.tenant_id
        and successor.state = 'queued'
        and successor.id <> v_request.id
    ) into v_successor_exists;

    if v_successor_exists
       or v_target.desired_revision > v_request.requested_revision then
      v_next_state := 'superseded';
    elsif p_outcome = 'retry'
          and v_request.attempt_count < v_request.max_attempts then
      v_next_state := 'queued';
    elsif v_request.attempt_count >= v_request.max_attempts then
      v_next_state := 'dead_letter';
    else
      v_next_state := 'failed';
    end if;

    update public.storefront_publication_attempts attempt
    set state = case
          when v_next_state = 'superseded' then 'superseded'
          when v_next_state = 'dead_letter' then 'dead_letter'
          else 'failed'
        end,
        dispatch_http_status = p_http_status,
        failure_stage = 'dispatch',
        error_class = left(
          coalesce(
            p_error_class,
            case
              when p_outcome = 'retry' then 'dispatch_network'
              else 'dispatch_permanent'
            end
          ),
          120
        ),
        error_message = left(
          coalesce(p_error_message, 'Storefront dispatch failed'),
          2000
        ),
        completed_at = v_now,
        updated_at = v_now
    where attempt.id = v_attempt.id;

    v_retry_seconds := greatest(
      30,
      least(
        coalesce(
          p_retry_after_seconds,
          least(
            1800,
            60 * power(
              2::numeric,
              greatest(v_request.attempt_count - 1, 0)
            )::integer
          )
        ),
        3600
      )
    );

    update public.storefront_publication_requests request
    set state = v_next_state,
        lease_owner = null,
        lease_token = null,
        lease_fence = null,
        lease_expires_at = null,
        available_at = case
          when v_next_state = 'queued'
            then v_now + make_interval(secs => v_retry_seconds)
          else request.available_at
        end,
        failure_stage = 'dispatch',
        error_class = left(
          coalesce(
            p_error_class,
            case
              when p_outcome = 'retry' then 'dispatch_network'
              else 'dispatch_permanent'
            end
          ),
          120
        ),
        error_message = left(
          coalesce(p_error_message, 'Storefront dispatch failed'),
          2000
        ),
        finished_at = case
          when v_next_state = 'queued' then null
          else v_now
        end,
        updated_at = v_now
    where request.id = v_request.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'replay', false,
    'request_id', v_request.id,
    'attempt_id', v_attempt.id,
    'state', (
      select request.state
      from public.storefront_publication_requests request
      where request.id = v_request.id
    )
  );
end;
$$;

create or replace function public.begin_storefront_publication_workflow(
  p_request_id uuid,
  p_github_run_id bigint,
  p_github_run_attempt integer,
  p_github_sha text,
  p_github_ref text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.storefront_publication_requests%rowtype;
  v_attempt public.storefront_publication_attempts%rowtype;
  v_target public.storefront_publication_targets%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  perform private.require_storefront_publication_service();

  if p_request_id is null
     or p_github_run_id is null
     or p_github_run_id <= 0
     or p_github_run_attempt is null
     or p_github_run_attempt <= 0
     or coalesce(p_github_sha, '') !~ '^[0-9a-f]{40}$'
     or p_github_ref <> 'refs/heads/main' then
    raise exception 'storefront_publication_invalid_workflow_identity'
      using errcode = '22023';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id;

  if not found then
    return jsonb_build_object(
      'should_run', false,
      'reason', 'request_not_found'
    );
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.id = v_request.target_id
    and target.tenant_id = v_request.tenant_id
    and target.dispatch_enabled is true
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found then
    return jsonb_build_object(
      'should_run', false,
      'reason', 'target_disabled_or_invalid'
    );
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id
    and request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
  for update;

  select attempt.*
  into v_attempt
  from public.storefront_publication_attempts attempt
  where attempt.id = v_request.active_attempt_id
    and attempt.request_id = v_request.id
    and attempt.target_id = v_target.id
    and attempt.tenant_id = v_target.tenant_id
  for update;

  if not found then
    return jsonb_build_object(
      'should_run', false,
      'reason', 'active_attempt_missing'
    );
  end if;

  if v_attempt.github_run_id is not null then
    if v_attempt.github_run_id = p_github_run_id
       and v_attempt.github_run_attempt = p_github_run_attempt
       and v_attempt.github_sha = p_github_sha
       and v_attempt.github_ref = p_github_ref then
      return jsonb_build_object(
        'should_run',
        v_attempt.state in ('running', 'sealed'),
        'replay', true,
        'reason', case
          when v_attempt.state in ('running', 'sealed') then 'bound'
          else 'already_terminal'
        end,
        'request_id', v_request.id,
        'attempt_id', v_attempt.id,
        'lease_fence', v_attempt.lease_fence,
        'requested_revision', v_request.requested_revision,
        'tenant_id', v_target.tenant_id,
        'expected_store_origin', v_target.expected_store_origin,
        'expected_firebase_origin', v_target.expected_firebase_origin
      );
    end if;

    return jsonb_build_object(
      'should_run', false,
      'reason', 'request_already_bound',
      'request_id', v_request.id
    );
  end if;

  if exists (
    select 1
    from public.storefront_publication_attempts other_attempt
    where other_attempt.id <> v_attempt.id
      and other_attempt.github_run_id = p_github_run_id
      and other_attempt.github_run_attempt = p_github_run_attempt
  ) then
    return jsonb_build_object(
      'should_run', false,
      'reason', 'github_run_already_bound'
    );
  end if;

  if v_request.state not in (
    'dispatching',
    'dispatched',
    'dispatch_unknown'
  ) or v_attempt.state not in (
    'dispatching',
    'dispatched',
    'dispatch_unknown'
  ) then
    return jsonb_build_object(
      'should_run', false,
      'reason', 'request_not_dispatchable',
      'state', v_request.state
    );
  end if;

  if v_target.desired_revision > v_request.requested_revision then
    update public.storefront_publication_attempts attempt
    set state = 'superseded',
        github_run_id = p_github_run_id,
        github_run_attempt = p_github_run_attempt,
        github_sha = p_github_sha,
        github_ref = p_github_ref,
        failure_stage = 'begin',
        error_class = 'owner_revision_superseded',
        error_message = 'A newer editorial revision exists',
        completed_at = v_now,
        updated_at = v_now
    where attempt.id = v_attempt.id;

    update public.storefront_publication_requests request
    set state = 'superseded',
        lease_owner = null,
        lease_token = null,
        lease_fence = null,
        lease_expires_at = null,
        failure_stage = 'begin',
        error_class = 'owner_revision_superseded',
        error_message = 'A newer editorial revision exists',
        finished_at = v_now,
        updated_at = v_now
    where request.id = v_request.id;

    perform private.ensure_storefront_publication_successor(
      v_target.id,
      v_request.id
    );

    return jsonb_build_object(
      'should_run', false,
      'reason', 'owner_revision_superseded',
      'request_id', v_request.id,
      'requested_revision', v_request.requested_revision,
      'desired_revision', v_target.desired_revision
    );
  end if;

  update public.storefront_publication_attempts attempt
  set state = 'running',
      github_run_id = p_github_run_id,
      github_run_attempt = p_github_run_attempt,
      github_sha = p_github_sha,
      github_ref = p_github_ref,
      workflow_started_at = v_now,
      heartbeat_at = v_now,
      failure_stage = null,
      error_class = null,
      error_message = null,
      updated_at = v_now
  where attempt.id = v_attempt.id;

  update public.storefront_publication_requests request
  set state = 'running',
      lease_owner = null,
      lease_token = null,
      lease_fence = null,
      lease_expires_at = null,
      started_at = coalesce(request.started_at, v_now),
      failure_stage = null,
      error_class = null,
      error_message = null,
      updated_at = v_now
  where request.id = v_request.id;

  return jsonb_build_object(
    'should_run', true,
    'replay', false,
    'reason', 'bound',
    'request_id', v_request.id,
    'attempt_id', v_attempt.id,
    'lease_fence', v_attempt.lease_fence,
    'requested_revision', v_request.requested_revision,
    'tenant_id', v_target.tenant_id,
    'expected_store_origin', v_target.expected_store_origin,
    'expected_firebase_origin', v_target.expected_firebase_origin
  );
end;
$$;

create or replace function public.seal_storefront_publication_workflow(
  p_request_id uuid,
  p_attempt_id uuid,
  p_lease_fence bigint,
  p_github_run_id bigint,
  p_owner_source_sha256 text,
  p_build_input_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.storefront_publication_requests%rowtype;
  v_attempt public.storefront_publication_attempts%rowtype;
  v_target public.storefront_publication_targets%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  perform private.require_storefront_publication_service();

  if p_request_id is null
     or p_attempt_id is null
     or p_lease_fence is null
     or p_lease_fence <= 0
     or p_github_run_id is null
     or p_github_run_id <= 0
     or coalesce(p_owner_source_sha256, '') !~ '^[0-9a-f]{64}$'
     or (
       p_build_input_sha256 is not null
       and p_build_input_sha256 !~ '^[0-9a-f]{64}$'
     ) then
    raise exception 'storefront_publication_invalid_seal'
      using errcode = '22023';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id;

  if not found then
    raise exception 'storefront_publication_request_not_found'
      using errcode = '22023';
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.id = v_request.target_id
    and target.tenant_id = v_request.tenant_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found then
    raise exception 'storefront_publication_target_forbidden'
      using errcode = '42501';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id
    and request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
  for update;

  select attempt.*
  into v_attempt
  from public.storefront_publication_attempts attempt
  where attempt.id = p_attempt_id
    and attempt.request_id = v_request.id
    and attempt.target_id = v_target.id
    and attempt.tenant_id = v_target.tenant_id
  for update;

  if not found
     or v_request.active_attempt_id is distinct from v_attempt.id
     or v_attempt.lease_fence is distinct from p_lease_fence
     or v_attempt.github_run_id is distinct from p_github_run_id then
    raise exception 'storefront_publication_stale_fence'
      using errcode = 'PT409';
  end if;

  if v_attempt.state in ('sealed', 'succeeded') then
    if v_attempt.owner_source_sha256 = p_owner_source_sha256
       and v_attempt.build_input_sha256 is not distinct from
         p_build_input_sha256 then
      return jsonb_build_object(
        'deploy', true,
        'replay', true,
        'request_id', v_request.id,
        'attempt_id', v_attempt.id,
        'requested_revision', v_request.requested_revision
      );
    end if;

    raise exception 'storefront_publication_seal_evidence_conflict'
      using errcode = 'PT409';
  end if;

  if v_request.state <> 'running'
     or v_attempt.state <> 'running' then
    raise exception 'storefront_publication_not_running'
      using errcode = 'PT409';
  end if;

  if v_target.desired_revision <> v_request.requested_revision
     or v_attempt.requested_revision <> v_request.requested_revision then
    update public.storefront_publication_attempts attempt
    set state = 'superseded',
        failure_stage = 'seal',
        error_class = 'owner_revision_changed',
        error_message = 'Editorial owners changed before release seal',
        completed_at = v_now,
        updated_at = v_now
    where attempt.id = v_attempt.id;

    update public.storefront_publication_requests request
    set state = 'superseded',
        failure_stage = 'seal',
        error_class = 'owner_revision_changed',
        error_message = 'Editorial owners changed before release seal',
        finished_at = v_now,
        updated_at = v_now
    where request.id = v_request.id;

    perform private.ensure_storefront_publication_successor(
      v_target.id,
      v_request.id
    );

    return jsonb_build_object(
      'deploy', false,
      'replay', false,
      'reason', 'owner_revision_changed',
      'requested_revision', v_request.requested_revision,
      'desired_revision', v_target.desired_revision
    );
  end if;

  update public.storefront_publication_attempts attempt
  set state = 'sealed',
      owner_source_sha256 = p_owner_source_sha256,
      build_input_sha256 = p_build_input_sha256,
      sealed_at = v_now,
      heartbeat_at = v_now,
      updated_at = v_now
  where attempt.id = v_attempt.id;

  update public.storefront_publication_requests request
  set state = 'sealed',
      updated_at = v_now
  where request.id = v_request.id;

  return jsonb_build_object(
    'deploy', true,
    'replay', false,
    'request_id', v_request.id,
    'attempt_id', v_attempt.id,
    'requested_revision', v_request.requested_revision
  );
end;
$$;

create or replace function public.complete_storefront_publication_workflow(
  p_request_id uuid,
  p_attempt_id uuid,
  p_lease_fence bigint,
  p_github_run_id bigint,
  p_github_run_attempt integer,
  p_outcome text,
  p_failure_stage text default null,
  p_error_class text default null,
  p_error_message text default null,
  p_release_commit text default null,
  p_release_run_id bigint default null,
  p_release_built_at timestamptz default null,
  p_release_request_id uuid default null,
  p_release_revision bigint default null,
  p_release_owner_source_sha256 text default null,
  p_release_manifest_sha256 text default null,
  p_primary_verified boolean default false,
  p_custom_verified boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.storefront_publication_requests%rowtype;
  v_attempt public.storefront_publication_attempts%rowtype;
  v_target public.storefront_publication_targets%rowtype;
  v_now timestamptz := clock_timestamp();
  v_successor_exists boolean;
  v_next_state text;
  v_retry_seconds integer;
begin
  perform private.require_storefront_publication_service();

  if p_request_id is null
     or p_attempt_id is null
     or p_lease_fence is null
     or p_lease_fence <= 0
     or p_github_run_id is null
     or p_github_run_id <= 0
     or p_github_run_attempt is null
     or p_github_run_attempt <= 0
     or p_outcome not in ('succeeded', 'failed') then
    raise exception 'storefront_publication_invalid_workflow_completion'
      using errcode = '22023';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id;

  if not found then
    raise exception 'storefront_publication_request_not_found'
      using errcode = '22023';
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.id = v_request.target_id
    and target.tenant_id = v_request.tenant_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found then
    raise exception 'storefront_publication_target_forbidden'
      using errcode = '42501';
  end if;

  select request.*
  into v_request
  from public.storefront_publication_requests request
  where request.id = p_request_id
    and request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
  for update;

  select attempt.*
  into v_attempt
  from public.storefront_publication_attempts attempt
  where attempt.id = p_attempt_id
    and attempt.request_id = v_request.id
    and attempt.target_id = v_target.id
    and attempt.tenant_id = v_target.tenant_id
  for update;

  if not found
     or v_request.active_attempt_id is distinct from v_attempt.id
     or v_attempt.lease_fence is distinct from p_lease_fence
     or v_attempt.github_run_id is distinct from p_github_run_id
     or v_attempt.github_run_attempt is distinct from p_github_run_attempt then
    raise exception 'storefront_publication_stale_fence'
      using errcode = 'PT409';
  end if;

  if v_attempt.state = 'succeeded' then
    if p_outcome = 'succeeded'
       and v_attempt.release_commit = p_release_commit
       and v_attempt.release_run_id = p_release_run_id
       and v_attempt.release_built_at = p_release_built_at
       and v_attempt.release_request_id = p_release_request_id
       and v_attempt.release_revision = p_release_revision
       and v_attempt.release_owner_source_sha256 =
         p_release_owner_source_sha256
       and v_attempt.release_manifest_sha256 =
         p_release_manifest_sha256
       and p_primary_verified
       and p_custom_verified then
      return jsonb_build_object(
        'ok', true,
        'replay', true,
        'state', 'succeeded',
        'request_id', v_request.id,
        'attempt_id', v_attempt.id
      );
    end if;

    raise exception 'storefront_publication_terminal_evidence_conflict'
      using errcode = 'PT409';
  end if;

  if v_attempt.state in ('failed', 'dead_letter', 'superseded') then
    if p_outcome = 'failed' then
      return jsonb_build_object(
        'ok', true,
        'replay', true,
        'state', v_request.state,
        'request_id', v_request.id,
        'attempt_id', v_attempt.id
      );
    end if;

    raise exception 'storefront_publication_terminal_evidence_conflict'
      using errcode = 'PT409';
  end if;

  if p_outcome = 'succeeded' then
    if v_request.state <> 'sealed'
       or v_attempt.state <> 'sealed'
       or coalesce(p_release_commit, '') !~ '^[0-9a-f]{40}$'
       or p_release_commit <> v_attempt.github_sha
       or p_release_run_id is distinct from v_attempt.github_run_id
       or p_release_request_id is distinct from v_request.id
       or p_release_revision is distinct from v_request.requested_revision
       or coalesce(p_release_owner_source_sha256, '') !~
         '^[0-9a-f]{64}$'
       or p_release_owner_source_sha256 <>
         v_attempt.owner_source_sha256
       or coalesce(p_release_manifest_sha256, '') !~
         '^[0-9a-f]{64}$'
       or p_release_built_at is null
       or p_release_built_at >
         v_now + interval '5 minutes'
       or p_release_built_at <
         coalesce(v_attempt.workflow_started_at, v_now) - interval '5 minutes'
       or not p_primary_verified
       or not p_custom_verified then
      raise exception 'storefront_publication_success_evidence_mismatch'
        using errcode = 'PT409';
    end if;

    update public.storefront_publication_attempts attempt
    set state = 'succeeded',
        release_manifest_sha256 = p_release_manifest_sha256,
        release_commit = p_release_commit,
        release_run_id = p_release_run_id,
        release_built_at = p_release_built_at,
        release_request_id = p_release_request_id,
        release_revision = p_release_revision,
        release_owner_source_sha256 = p_release_owner_source_sha256,
        primary_verified_at = v_now,
        custom_verified_at = v_now,
        failure_stage = null,
        error_class = null,
        error_message = null,
        completed_at = v_now,
        heartbeat_at = v_now,
        updated_at = v_now
    where attempt.id = v_attempt.id;

    update public.storefront_publication_requests request
    set state = 'succeeded',
        failure_stage = null,
        error_class = null,
        error_message = null,
        finished_at = v_now,
        updated_at = v_now
    where request.id = v_request.id;

    update public.storefront_publication_targets target
    set last_published_revision = greatest(
          target.last_published_revision,
          v_request.requested_revision
        ),
        last_published_request_id = case
          when v_request.requested_revision >=
            target.last_published_revision then v_request.id
          else target.last_published_request_id
        end,
        last_published_attempt_id = case
          when v_request.requested_revision >=
            target.last_published_revision then v_attempt.id
          else target.last_published_attempt_id
        end,
        last_published_at = case
          when v_request.requested_revision >=
            target.last_published_revision then v_now
          else target.last_published_at
        end,
        updated_at = v_now
    where target.id = v_target.id;

    return jsonb_build_object(
      'ok', true,
      'replay', false,
      'state', 'succeeded',
      'request_id', v_request.id,
      'attempt_id', v_attempt.id,
      'published_revision', v_request.requested_revision,
      'desired_revision', v_target.desired_revision
    );
  end if;

  if v_request.state not in ('running', 'sealed')
     or v_attempt.state not in ('running', 'sealed') then
    raise exception 'storefront_publication_workflow_not_active'
      using errcode = 'PT409';
  end if;

  select exists (
    select 1
    from public.storefront_publication_requests successor
    where successor.target_id = v_target.id
      and successor.tenant_id = v_target.tenant_id
      and successor.state = 'queued'
      and successor.id <> v_request.id
  ) into v_successor_exists;

  if v_successor_exists
     or v_target.desired_revision > v_request.requested_revision then
    v_next_state := 'superseded';
  elsif private.storefront_publication_retryable_error(p_error_class)
        and v_request.attempt_count < v_request.max_attempts then
    v_next_state := 'queued';
  elsif v_request.attempt_count >= v_request.max_attempts then
    v_next_state := 'dead_letter';
  else
    v_next_state := 'failed';
  end if;

  v_retry_seconds := least(
    1800,
    60 * power(
      2::numeric,
      greatest(v_request.attempt_count - 1, 0)
    )::integer
  );

  update public.storefront_publication_attempts attempt
  set state = case
        when v_next_state = 'superseded' then 'superseded'
        when v_next_state = 'dead_letter' then 'dead_letter'
        else 'failed'
      end,
      failure_stage = left(coalesce(p_failure_stage, 'workflow'), 80),
      error_class = left(coalesce(p_error_class, 'workflow_failed'), 120),
      error_message = left(
        coalesce(p_error_message, 'Storefront workflow failed'),
        2000
      ),
      completed_at = v_now,
      heartbeat_at = v_now,
      updated_at = v_now
  where attempt.id = v_attempt.id;

  update public.storefront_publication_requests request
  set state = v_next_state,
      available_at = case
        when v_next_state = 'queued'
          then v_now + make_interval(secs => v_retry_seconds)
        else request.available_at
      end,
      failure_stage = left(coalesce(p_failure_stage, 'workflow'), 80),
      error_class = left(coalesce(p_error_class, 'workflow_failed'), 120),
      error_message = left(
        coalesce(p_error_message, 'Storefront workflow failed'),
        2000
      ),
      finished_at = case
        when v_next_state = 'queued' then null
        else v_now
      end,
      updated_at = v_now
  where request.id = v_request.id;

  if v_next_state = 'superseded' then
    perform private.ensure_storefront_publication_successor(
      v_target.id,
      v_request.id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'replay', false,
    'state', v_next_state,
    'request_id', v_request.id,
    'attempt_id', v_attempt.id
  );
end;
$$;

create or replace function public.get_storefront_publication_status(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_target public.storefront_publication_targets%rowtype;
  v_queue jsonb;
  v_active jsonb;
  v_last_success jsonb;
  v_latest_failure jsonb;
  v_request_state text;
  v_request_id uuid;
  v_can_retry boolean;
  v_status_message text;
begin
  if v_actor_id is null
     or p_tenant_id is null
     or public.user_tenant_id() is distinct from p_tenant_id
     or not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'storefront_publication_status_forbidden'
      using errcode = '42501';
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.tenant_id = p_tenant_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app';

  if not found then
    return jsonb_build_object(
      'supported', true,
      'configured', false,
      'dispatch_enabled', false,
      'desired_revision', 0,
      'last_published_revision', 0,
      'request_state', null,
      'request_id', null,
      'last_published_request_id', null,
      'can_retry', false,
      'status_message', 'Storefront publication is not configured',
      'queue', null,
      'active', null,
      'last_success', null,
      'latest_failure', null
    );
  end if;

  select jsonb_build_object(
    'request_id', request.id,
    'state', request.state,
    'source', request.source,
    'requested_revision', request.requested_revision,
    'coalesced_count', request.coalesced_count,
    'available_at', request.available_at,
    'created_at', request.created_at
  )
  into v_queue
  from public.storefront_publication_requests request
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state = 'queued'
  order by request.created_at desc
  limit 1;

  select jsonb_build_object(
    'request_id', request.id,
    'attempt_id', attempt.id,
    'state', request.state,
    'requested_revision', request.requested_revision,
    'attempt_no', attempt.attempt_no,
    'github_run_id', attempt.github_run_id,
    'github_run_attempt', attempt.github_run_attempt,
    'github_sha', attempt.github_sha,
    'github_run_url', case
      when attempt.github_run_id is null then null
      else
        'https://github.com/Ccatalan7/bikeshop-erp/actions/runs/'
        || attempt.github_run_id::text
    end,
    'started_at', request.started_at,
    'sealed_at', attempt.sealed_at,
    'failure_stage', request.failure_stage,
    'error_class', request.error_class,
    'error_message', request.error_message
  )
  into v_active
  from public.storefront_publication_requests request
  left join public.storefront_publication_attempts attempt
    on attempt.id = request.active_attempt_id
   and attempt.request_id = request.id
   and attempt.tenant_id = request.tenant_id
   and attempt.target_id = request.target_id
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state in (
      'dispatching',
      'dispatched',
      'dispatch_unknown',
      'running',
      'sealed'
    )
  order by request.created_at desc
  limit 1;

  select jsonb_build_object(
    'request_id', request.id,
    'attempt_id', attempt.id,
    'published_revision', request.requested_revision,
    'github_run_id', attempt.github_run_id,
    'github_run_attempt', attempt.github_run_attempt,
    'github_sha', attempt.github_sha,
    'github_run_url',
      'https://github.com/Ccatalan7/bikeshop-erp/actions/runs/'
      || attempt.github_run_id::text,
    'owner_source_sha256', attempt.owner_source_sha256,
    'build_input_sha256', attempt.build_input_sha256,
    'release_manifest_sha256', attempt.release_manifest_sha256,
    'release_built_at', attempt.release_built_at,
    'primary_verified_at', attempt.primary_verified_at,
    'custom_verified_at', attempt.custom_verified_at,
    'completed_at', attempt.completed_at
  )
  into v_last_success
  from public.storefront_publication_requests request
  join public.storefront_publication_attempts attempt
    on attempt.id = request.active_attempt_id
   and attempt.request_id = request.id
   and attempt.tenant_id = request.tenant_id
   and attempt.target_id = request.target_id
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state = 'succeeded'
    and attempt.state = 'succeeded'
  order by request.requested_revision desc, attempt.completed_at desc
  limit 1;

  select jsonb_build_object(
    'request_id', request.id,
    'attempt_id', attempt.id,
    'state', request.state,
    'requested_revision', request.requested_revision,
    'attempt_no', attempt.attempt_no,
    'failure_stage', request.failure_stage,
    'error_class', request.error_class,
    'error_message', request.error_message,
    'finished_at', request.finished_at
  )
  into v_latest_failure
  from public.storefront_publication_requests request
  left join public.storefront_publication_attempts attempt
    on attempt.id = request.active_attempt_id
   and attempt.request_id = request.id
   and attempt.tenant_id = request.tenant_id
   and attempt.target_id = request.target_id
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state in ('failed', 'dead_letter')
  order by request.finished_at desc nulls last, request.created_at desc
  limit 1;

  if v_active is not null then
    v_request_state := v_active->>'state';
    v_request_id := nullif(v_active->>'request_id', '')::uuid;
  elsif v_queue is not null then
    v_request_state := v_queue->>'state';
    v_request_id := nullif(v_queue->>'request_id', '')::uuid;
  elsif v_latest_failure is not null
        and (
          v_last_success is null
          or (v_latest_failure->>'requested_revision')::bigint >
            (v_last_success->>'published_revision')::bigint
          or (v_latest_failure->>'requested_revision')::bigint >=
            v_target.desired_revision
        ) then
    v_request_state := v_latest_failure->>'state';
    v_request_id := nullif(v_latest_failure->>'request_id', '')::uuid;
  elsif v_last_success is not null then
    v_request_state := 'succeeded';
    v_request_id := nullif(v_last_success->>'request_id', '')::uuid;
  elsif v_latest_failure is not null then
    v_request_state := v_latest_failure->>'state';
    v_request_id := nullif(v_latest_failure->>'request_id', '')::uuid;
  end if;

  v_can_retry :=
    v_target.dispatch_enabled
    and v_queue is null
    and v_active is null
    and v_latest_failure is not null
    and v_request_state in ('failed', 'dead_letter')
    and v_target.desired_revision > v_target.last_published_revision;

  v_status_message := case
    when not v_target.dispatch_enabled
      then 'Storefront publication is disabled'
    when v_request_state = 'queued'
      then 'Storefront publication is queued'
    when v_request_state in (
      'dispatching',
      'dispatched',
      'dispatch_unknown',
      'running',
      'sealed'
    ) then 'Storefront publication is in progress'
    when v_request_state = 'succeeded'
      and v_target.desired_revision = v_target.last_published_revision
      then 'Storefront publication is current'
    when v_request_state in ('failed', 'dead_letter')
      then 'Storefront publication needs attention'
    when v_target.desired_revision > v_target.last_published_revision
      then 'Storefront has unpublished changes'
    else 'No storefront publication has been recorded'
  end;

  return jsonb_build_object(
    'supported', true,
    'configured', true,
    'target_key', v_target.target_key,
    'expected_store_origin', v_target.expected_store_origin,
    'expected_firebase_origin', v_target.expected_firebase_origin,
    'dispatch_enabled', v_target.dispatch_enabled,
    'desired_revision', v_target.desired_revision,
    'last_published_revision', v_target.last_published_revision,
    'request_state', v_request_state,
    'request_id', v_request_id,
    'last_published_request_id', v_target.last_published_request_id,
    'can_retry', v_can_retry,
    'status_message', v_status_message,
    'last_owner_change_at', v_target.last_owner_change_at,
    'last_published_at', v_target.last_published_at,
    'last_dispatch_tick_at', v_target.last_dispatch_tick_at,
    'last_dispatch_error_class', v_target.last_dispatch_error_class,
    'last_dispatch_error_message', v_target.last_dispatch_error_message,
    'queue', v_queue,
    'active', v_active,
    'last_success', v_last_success,
    'latest_failure', v_latest_failure
  );
end;
$$;

create or replace function public.retry_storefront_publication(
  p_tenant_id uuid,
  p_failed_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_target public.storefront_publication_targets%rowtype;
  v_existing_request public.storefront_publication_requests%rowtype;
  v_failed_request public.storefront_publication_requests%rowtype;
  v_request_id uuid;
  v_now timestamptz := clock_timestamp();
begin
  if v_actor_id is null
     or p_tenant_id is null
     or public.user_tenant_id() is distinct from p_tenant_id
     or not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'storefront_publication_retry_forbidden'
      using errcode = '42501';
  end if;

  select target.*
  into v_target
  from public.storefront_publication_targets target
  where target.tenant_id = p_tenant_id
    and target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
  for update;

  if not found or not v_target.dispatch_enabled then
    return jsonb_build_object(
      'accepted', false,
      'enqueued', false,
      'reason', 'dispatch_disabled',
      'message', 'Storefront publication is disabled',
      'status', public.get_storefront_publication_status(p_tenant_id)
    );
  end if;

  select request.*
  into v_existing_request
  from public.storefront_publication_requests request
  where request.target_id = v_target.id
    and request.tenant_id = v_target.tenant_id
    and request.state in (
      'queued',
      'dispatching',
      'dispatched',
      'dispatch_unknown',
      'running',
      'sealed'
    )
  order by
    case when request.state = 'queued' then 1 else 0 end,
    request.created_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'accepted', false,
      'enqueued', false,
      'reason', 'request_already_active',
      'message', 'A storefront publication request is already active',
      'request_id', v_existing_request.id,
      'state', v_existing_request.state,
      'requested_revision', v_existing_request.requested_revision,
      'status', public.get_storefront_publication_status(p_tenant_id)
    );
  end if;

  if p_failed_request_id is not null then
    select request.*
    into v_failed_request
    from public.storefront_publication_requests request
    where request.id = p_failed_request_id
      and request.target_id = v_target.id
      and request.tenant_id = v_target.tenant_id
      and request.state in ('failed', 'dead_letter');

    if not found then
      raise exception 'storefront_publication_retry_request_invalid'
        using errcode = '22023';
    end if;
  else
    select request.*
    into v_failed_request
    from public.storefront_publication_requests request
    where request.target_id = v_target.id
      and request.tenant_id = v_target.tenant_id
      and request.state in ('failed', 'dead_letter')
    order by request.finished_at desc nulls last, request.created_at desc
    limit 1;
  end if;

  if v_target.desired_revision <= v_target.last_published_revision
     and v_failed_request.id is null then
    return jsonb_build_object(
      'accepted', false,
      'enqueued', false,
      'reason', 'already_published',
      'message', 'The current editorial revision is already published',
      'published_revision', v_target.last_published_revision,
      'status', public.get_storefront_publication_status(p_tenant_id)
    );
  end if;

  if v_target.desired_revision <= 0 then
    return jsonb_build_object(
      'accepted', false,
      'enqueued', false,
      'reason', 'no_editorial_revision',
      'message', 'No editorial revision is available to publish',
      'status', public.get_storefront_publication_status(p_tenant_id)
    );
  end if;

  if exists (
    select 1
    from public.storefront_publication_requests request
    where request.target_id = v_target.id
      and request.tenant_id = v_target.tenant_id
      and request.source = 'manual_retry'
      and request.requested_by_user_id = v_actor_id
      and request.created_at > v_now - interval '5 minutes'
  ) then
    raise exception 'storefront_publication_retry_rate_limited'
      using errcode = 'PT429';
  end if;

  insert into public.storefront_publication_requests (
    tenant_id,
    target_id,
    requested_revision,
    state,
    source,
    supersedes_request_id,
    requested_by_user_id,
    first_change_at,
    last_change_at,
    available_at
  ) values (
    v_target.tenant_id,
    v_target.id,
    v_target.desired_revision,
    'queued',
    'manual_retry',
    v_failed_request.id,
    v_actor_id,
    v_now,
    v_now,
    v_now
  )
  returning id into v_request_id;

  return jsonb_build_object(
    'accepted', true,
    'enqueued', true,
    'reason', 'manual_retry',
    'message', 'The storefront publication retry is queued',
    'request_id', v_request_id,
    'requested_revision', v_target.desired_revision,
    'status', public.get_storefront_publication_status(p_tenant_id)
  );
end;
$$;

create or replace function private.invoke_storefront_publication_dispatcher()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target_id uuid;
  v_worker_secret text;
  v_request_id bigint;
  v_now timestamptz := clock_timestamp();
begin
  select target.id
  into v_target_id
  from public.storefront_publication_targets target
  where target.tenant_id =
      '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and target.target_key = 'vinabike-store'
    and target.expected_store_origin = 'https://vinabike.cl'
    and target.expected_firebase_origin =
      'https://vinabike-store.web.app'
    and target.dispatch_enabled is true
  for update;

  if not found then
    return null;
  end if;

  select secret.decrypted_secret
  into v_worker_secret
  from vault.decrypted_secrets secret
  where secret.name = 'storefront_publication_dispatch_secret'
    and nullif(secret.decrypted_secret, '') is not null
  order by secret.created_at desc
  limit 1;

  if nullif(v_worker_secret, '') is null then
    update public.storefront_publication_targets target
    set last_dispatch_tick_at = v_now,
        last_dispatch_request_id = null,
        last_dispatch_error_class = 'missing_vault_secret',
        last_dispatch_error_message =
          'Missing Vault secret storefront_publication_dispatch_secret',
        updated_at = v_now
    where target.id = v_target_id;
    return null;
  end if;

  select net.http_post(
    url :=
      'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/'
      || 'dispatch-storefront-publication',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-storefront-publication-secret', v_worker_secret
    ),
    body := jsonb_build_object('action', 'tick'),
    timeout_milliseconds := 15000
  )
  into v_request_id;

  update public.storefront_publication_targets target
  set last_dispatch_tick_at = v_now,
      last_dispatch_request_id = v_request_id,
      last_dispatch_error_class = null,
      last_dispatch_error_message = null,
      updated_at = v_now
  where target.id = v_target_id;

  return v_request_id;
exception
  when others then
    update public.storefront_publication_targets target
    set last_dispatch_tick_at = clock_timestamp(),
        last_dispatch_request_id = null,
        last_dispatch_error_class = 'dispatcher_invocation_failed',
        last_dispatch_error_message = left(sqlerrm, 2000),
        updated_at = clock_timestamp()
    where target.id = v_target_id;
    return null;
end;
$$;

revoke all on function private.require_storefront_publication_service()
  from public, anon, authenticated, service_role;
revoke all on function private.storefront_publication_retryable_error(text)
  from public, anon, authenticated, service_role;
revoke all on function private.storefront_publication_owner_projection(
  text,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.ensure_storefront_publication_successor(
  uuid,
  uuid
) from public, anon, authenticated, service_role;
revoke all on function private.mark_storefront_publication_change(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function private.storefront_publication_owner_row_relevant(
  text,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.storefront_publication_owner_trigger()
  from public, anon, authenticated, service_role;
revoke all on function private.invoke_storefront_publication_dispatcher()
  from public, anon, authenticated, service_role;

revoke all on function public.claim_storefront_publication_requests(
  text,
  integer,
  integer
) from public, anon, authenticated, service_role;
grant execute on function public.claim_storefront_publication_requests(
  text,
  integer,
  integer
) to service_role;

revoke all on function public.complete_storefront_publication_dispatch(
  uuid,
  uuid,
  text,
  uuid,
  bigint,
  text,
  integer,
  text,
  text,
  integer
) from public, anon, authenticated, service_role;
grant execute on function public.complete_storefront_publication_dispatch(
  uuid,
  uuid,
  text,
  uuid,
  bigint,
  text,
  integer,
  text,
  text,
  integer
) to service_role;

revoke all on function public.begin_storefront_publication_workflow(
  uuid,
  bigint,
  integer,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.begin_storefront_publication_workflow(
  uuid,
  bigint,
  integer,
  text,
  text
) to service_role;

revoke all on function public.seal_storefront_publication_workflow(
  uuid,
  uuid,
  bigint,
  bigint,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.seal_storefront_publication_workflow(
  uuid,
  uuid,
  bigint,
  bigint,
  text,
  text
) to service_role;

revoke all on function public.complete_storefront_publication_workflow(
  uuid,
  uuid,
  bigint,
  bigint,
  integer,
  text,
  text,
  text,
  text,
  text,
  bigint,
  timestamptz,
  uuid,
  bigint,
  text,
  text,
  boolean,
  boolean
) from public, anon, authenticated, service_role;
grant execute on function public.complete_storefront_publication_workflow(
  uuid,
  uuid,
  bigint,
  bigint,
  integer,
  text,
  text,
  text,
  text,
  text,
  bigint,
  timestamptz,
  uuid,
  bigint,
  text,
  text,
  boolean,
  boolean
) to service_role;

revoke all on function public.get_storefront_publication_status(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_storefront_publication_status(uuid)
  to authenticated;

revoke all on function public.retry_storefront_publication(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.retry_storefront_publication(uuid, uuid)
  to authenticated;

do $$
begin
  if to_regnamespace('cron') is null then
    return;
  end if;

  perform cron.unschedule(job.jobid)
  from cron.job job
  where job.jobname = 'vinabike_storefront_publication_dispatcher';

  perform cron.schedule(
    'vinabike_storefront_publication_dispatcher',
    '* * * * *',
    'select private.invoke_storefront_publication_dispatcher();'
  );
exception
  when others then
    raise notice 'Could not install storefront publication cron job: %',
      sqlerrm;
end
$$;

comment on table public.storefront_publication_targets is
  'Fail-closed Viñabike storefront publication target and monotonic editorial revision head.';
comment on table public.storefront_publication_requests is
  'Coalesced publication intent. One active request and at most one queued successor exist per target.';
comment on table public.storefront_publication_attempts is
  'Fenced dispatch/workflow attempt ledger with exact GitHub and live release evidence.';
comment on function public.claim_storefront_publication_requests(
  text,
  integer,
  integer
) is
  'Claims dispatch or reconciliation work with SKIP LOCKED, a bounded lease token, and a target-wide fence.';
comment on function public.retry_storefront_publication(uuid, uuid) is
  'Queues only the current server-owned revision after exact tenant/settings authorization; it accepts no target, URL, ref, or caller revision.';
comment on function private.invoke_storefront_publication_dispatcher() is
  'Cron-only fixed Edge invocation using the dedicated Vault secret. Disabled or misconfigured targets fail closed.';

commit;
