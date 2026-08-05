-- Deployment status: deployed and read back on production 2026-08-04;
-- migration version 20260804150000 is registered in production history.
-- Forward: add read-only identity lookups plus one service-only, exact-target
-- repair that archives a legacy tenant and removes only its corrupt profile.
-- Recovery: every repair is atomic and receipt-backed; any reversal is a
-- separate explicitly reviewed operation using that immutable snapshot.
-- Lock risk: 10 s lock timeout, 120 s statement timeout, one Auth advisory
-- identity lock, and row locks only on the exact source/target records.
--
-- Quarantine the legacy March 2026 customer-signup tenants without replacing
-- the Auth identity or deleting storefront history. This command is service
-- maintenance only: it archives the accidental tenant, removes the one corrupt
-- ERP profile, rebuilds Auth authority from active customer memberships, and
-- records an immutable receipt. Any business data or identity drift aborts the
-- complete transaction.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

create or replace function public.resolve_auth_user_id_by_email(
  p_email text
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, auth, pg_temp
as $$
  select auth_user.id
  from auth.users auth_user
  where lower(auth_user.email) = lower(btrim(p_email))
  limit 1
$$;

revoke all on function public.resolve_auth_user_id_by_email(text)
  from public, anon, authenticated, service_role;
grant execute on function public.resolve_auth_user_id_by_email(text)
  to service_role;

-- A valid invitation token already discloses its destination email and tenant.
-- Return one additional, current Auth fact so the acceptance UI never asks an
-- existing customer to create a second account. This remains read-only and
-- does not expose an email-directory lookup without the invitation capability.
create or replace function public.lookup_user_invitation_identity(
  p_token text
)
returns table (
  invitation_id uuid,
  email text,
  role text,
  tenant_id uuid,
  shop_name text,
  expires_at timestamp with time zone,
  account_exists boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
declare
  token_digest text;
begin
  if p_token is null
     or length(p_token) < 32
     or length(p_token) > 512 then
    return;
  end if;

  token_digest := encode(
    extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'),
    'hex'
  );

  return query
  select
    invitation.id,
    invitation.email,
    invitation.role,
    invitation.tenant_id,
    tenant.shop_name,
    invitation.expires_at,
    exists (
      select 1
      from auth.users auth_user
      where lower(auth_user.email) = lower(invitation.email)
    )
  from public.user_invitations invitation
  join public.tenants tenant
    on tenant.id = invitation.tenant_id
   and tenant.is_active is true
  where invitation.token_hash = token_digest
    and invitation.status = 'pending'
    and invitation.expires_at > now()
  limit 1;
end;
$$;

revoke all on function public.lookup_user_invitation_identity(text)
  from public, anon, authenticated, service_role;
grant execute on function public.lookup_user_invitation_identity(text)
  to anon, authenticated, service_role;

create table if not exists public.legacy_auth_identity_repair_receipts (
  id uuid primary key default gen_random_uuid(),
  repair_key text not null unique,
  source_tenant_id uuid not null,
  target_tenant_id uuid not null,
  auth_user_id uuid not null,
  source_profile_id uuid not null,
  target_customer_id uuid not null,
  source_tenant_snapshot jsonb not null,
  source_profile_snapshot jsonb not null,
  authority_metadata_before jsonb not null,
  authority_metadata_after jsonb not null,
  seed_row_counts jsonb not null default '{}'::jsonb,
  sessions_revoked integer not null default 0 check (sessions_revoked >= 0),
  reason text not null check (length(btrim(reason)) between 12 and 500),
  repaired_at timestamp with time zone not null default clock_timestamp(),
  constraint legacy_auth_identity_repair_distinct_tenants_check
    check (source_tenant_id <> target_tenant_id),
  constraint legacy_auth_identity_repair_key_check
    check (repair_key ~ '^[a-z0-9][a-z0-9._:-]{7,127}$')
);

alter table public.legacy_auth_identity_repair_receipts
  enable row level security;
alter table public.legacy_auth_identity_repair_receipts
  force row level security;

revoke all on table public.legacy_auth_identity_repair_receipts
  from public, anon, authenticated, service_role;
grant select on table public.legacy_auth_identity_repair_receipts
  to service_role;

create or replace function public.guard_legacy_auth_identity_repair_receipt()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  raise exception 'legacy_auth_identity_repair_receipt_immutable'
    using errcode = '42501';
end;
$$;

revoke all on function public.guard_legacy_auth_identity_repair_receipt()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_legacy_auth_identity_repair_receipt
  on public.legacy_auth_identity_repair_receipts;
create trigger trg_guard_legacy_auth_identity_repair_receipt
  before update or delete on public.legacy_auth_identity_repair_receipts
  for each row
  execute function public.guard_legacy_auth_identity_repair_receipt();

create or replace function public.repair_legacy_accidental_customer_tenant_identity(
  p_repair_key text,
  p_source_tenant_id uuid,
  p_source_profile_id uuid,
  p_auth_user_id uuid,
  p_target_tenant_id uuid,
  p_target_customer_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  normalized_repair_key text := lower(btrim(coalesce(p_repair_key, '')));
  normalized_reason text := btrim(coalesce(p_reason, ''));
  existing_receipt public.legacy_auth_identity_repair_receipts%rowtype;
  source_tenant public.tenants%rowtype;
  source_profile public.user_profiles%rowtype;
  auth_user auth.users%rowtype;
  tenant_table record;
  tenant_row_count bigint;
  seed_row_counts jsonb := '{}'::jsonb;
  customer_memberships jsonb := '{}'::jsonb;
  metadata_before jsonb := '{}'::jsonb;
  metadata_after jsonb := '{}'::jsonb;
  deleted_profiles integer := 0;
  sessions_revoked integer := 0;
  receipt_id uuid;
begin
  if normalized_repair_key !~ '^[a-z0-9][a-z0-9._:-]{7,127}$'
     or length(normalized_reason) not between 12 and 500
     or p_source_tenant_id is null
     or p_source_profile_id is null
     or p_auth_user_id is null
     or p_target_tenant_id is null
     or p_target_customer_id is null
     or p_source_tenant_id = p_target_tenant_id then
    raise exception 'legacy_identity_repair_invalid_request'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('legacy-auth-identity-repair:' || normalized_repair_key, 0)
  );
  perform public.lock_auth_membership_identities(null, p_auth_user_id);

  select receipt.*
  into existing_receipt
  from public.legacy_auth_identity_repair_receipts receipt
  where receipt.repair_key = normalized_repair_key;

  if found then
    if existing_receipt.source_tenant_id is distinct from p_source_tenant_id
       or existing_receipt.target_tenant_id is distinct from p_target_tenant_id
       or existing_receipt.auth_user_id is distinct from p_auth_user_id
       or existing_receipt.source_profile_id is distinct from p_source_profile_id
       or existing_receipt.target_customer_id is distinct from p_target_customer_id then
      raise exception 'legacy_identity_repair_idempotency_conflict'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'success', true,
      'replayed', true,
      'receiptId', existing_receipt.id,
      'sourceTenantArchived', true,
      'profileRemoved', true,
      'sessionsRevoked', existing_receipt.sessions_revoked
    );
  end if;

  select tenant.*
  into source_tenant
  from public.tenants tenant
  where tenant.id = p_source_tenant_id
  for update;
  if not found or source_tenant.is_active is distinct from true then
    raise exception 'legacy_identity_repair_source_tenant_unavailable'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_target_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'legacy_identity_repair_target_tenant_unavailable'
      using errcode = 'P0001';
  end if;

  select profile.*
  into source_profile
  from public.user_profiles profile
  where profile.id = p_source_profile_id
    and profile.user_id = p_auth_user_id
    and profile.tenant_id = p_source_tenant_id
  for update;
  if not found
     or source_profile.role <> 'admin'
     or source_profile.is_active is distinct from true
     or source_profile.employee_id is not null then
    raise exception 'legacy_identity_repair_profile_mismatch'
      using errcode = 'P0001';
  end if;

  select candidate.*
  into auth_user
  from auth.users candidate
  where candidate.id = p_auth_user_id
  for update;
  if not found
     or auth_user.email is null
     or lower(auth_user.email) is distinct from lower(source_tenant.owner_email)
     or auth_user.raw_app_meta_data->>'account_type' <> 'erp_owner'
     or auth_user.raw_app_meta_data->>'tenant_id' <>
       p_source_tenant_id::text then
    raise exception 'legacy_identity_repair_auth_authority_mismatch'
      using errcode = 'P0001';
  end if;

  perform 1
  from public.customers customer
  where customer.id = p_target_customer_id
    and customer.tenant_id = p_target_tenant_id
    and customer.auth_user_id = p_auth_user_id
    and customer.is_active is true
  for update;
  if not found then
    raise exception 'legacy_identity_repair_customer_membership_missing'
      using errcode = 'P0001';
  end if;

  if (select count(*) from public.user_profiles profile
      where profile.user_id = p_auth_user_id) <> 1
     or (select count(*) from public.user_profiles profile
         where profile.tenant_id = p_source_tenant_id) <> 1
     or exists (
       select 1 from public.employees employee
       where employee.user_id = p_auth_user_id
     )
     or exists (
       select 1 from public.employee_portal_accounts portal
       where portal.auth_user_id = p_auth_user_id
     )
     or exists (
       select 1 from public.user_invitations invitation
       where lower(invitation.email) = lower(auth_user.email)
         and invitation.status = 'pending'
     ) then
    raise exception 'legacy_identity_repair_membership_graph_changed'
      using errcode = 'P0001';
  end if;

  for tenant_table in
    select column_row.table_name
    from information_schema.columns column_row
    join information_schema.tables table_row
      on table_row.table_schema = column_row.table_schema
     and table_row.table_name = column_row.table_name
    where column_row.table_schema = 'public'
      and column_row.column_name = 'tenant_id'
      and table_row.table_type = 'BASE TABLE'
      and column_row.table_name not in (
        'accounts',
        'company_settings',
        'expense_categories',
        'job_roles',
        'job_statuses',
        'payment_methods',
        'planning_roles',
        'user_profiles',
        'website_settings'
      )
    order by column_row.table_name
  loop
    execute format(
      'select count(*) from public.%I where tenant_id = $1',
      tenant_table.table_name
    )
    into tenant_row_count
    using p_source_tenant_id;
    if tenant_row_count <> 0 then
      raise exception 'legacy_tenant_contains_business_data:%',
        tenant_table.table_name
        using errcode = 'P0001';
    end if;
  end loop;

  for tenant_table in
    select unnest(array[
      'accounts',
      'company_settings',
      'expense_categories',
      'job_roles',
      'job_statuses',
      'payment_methods',
      'planning_roles',
      'website_settings'
    ]) as table_name
  loop
    execute format(
      'select count(*) from public.%I where tenant_id = $1',
      tenant_table.table_name
    )
    into tenant_row_count
    using p_source_tenant_id;
    seed_row_counts := seed_row_counts ||
      jsonb_build_object(tenant_table.table_name, tenant_row_count);
  end loop;

  select coalesce(
    jsonb_object_agg(customer.tenant_id::text, customer.id),
    '{}'::jsonb
  )
  into customer_memberships
  from public.customers customer
  join public.tenants tenant
    on tenant.id = customer.tenant_id
   and tenant.is_active is true
  where customer.auth_user_id = p_auth_user_id
    and customer.is_active is true;

  if not customer_memberships ? p_target_tenant_id::text then
    raise exception 'legacy_identity_repair_customer_membership_missing'
      using errcode = 'P0001';
  end if;

  metadata_before := coalesce(auth_user.raw_app_meta_data, '{}'::jsonb);
  metadata_after := (
    metadata_before
      - 'account_type'
      - 'tenant_id'
      - 'employee_id'
      - 'role'
      - 'permissions'
      - 'customer_id'
      - 'customer_tenant_id'
      - 'customer_memberships'
      - 'pending_invitation_token_hash'
  ) || jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_memberships', customer_memberships
  );

  update public.tenants tenant
  set is_active = false,
      updated_at = clock_timestamp()
  where tenant.id = p_source_tenant_id
    and tenant.is_active is true;
  if not found then
    raise exception 'legacy_identity_repair_source_tenant_changed'
      using errcode = 'P0001';
  end if;

  delete from public.user_profiles profile
  where profile.id = p_source_profile_id
    and profile.user_id = p_auth_user_id
    and profile.tenant_id = p_source_tenant_id;
  get diagnostics deleted_profiles = row_count;
  if deleted_profiles <> 1 then
    raise exception 'legacy_identity_repair_profile_changed'
      using errcode = 'P0001';
  end if;

  update auth.users candidate
  set raw_user_meta_data = coalesce(candidate.raw_user_meta_data, '{}'::jsonb)
        - 'account_type'
        - 'shop_name'
        - 'subdomain'
        - 'tenant_id'
        - 'employee_id'
        - 'role'
        - 'permissions'
        - 'customer_id'
        - 'customer_tenant_id'
        - 'invitation_token',
      raw_app_meta_data = metadata_after,
      updated_at = clock_timestamp()
  where candidate.id = p_auth_user_id;
  if not found then
    raise exception 'legacy_identity_repair_auth_identity_changed'
      using errcode = 'P0001';
  end if;

  delete from auth.sessions session
  where session.user_id = p_auth_user_id;
  get diagnostics sessions_revoked = row_count;

  insert into public.legacy_auth_identity_repair_receipts (
    repair_key,
    source_tenant_id,
    target_tenant_id,
    auth_user_id,
    source_profile_id,
    target_customer_id,
    source_tenant_snapshot,
    source_profile_snapshot,
    authority_metadata_before,
    authority_metadata_after,
    seed_row_counts,
    sessions_revoked,
    reason
  )
  values (
    normalized_repair_key,
    p_source_tenant_id,
    p_target_tenant_id,
    p_auth_user_id,
    p_source_profile_id,
    p_target_customer_id,
    to_jsonb(source_tenant) - 'owner_email',
    to_jsonb(source_profile),
    metadata_before,
    metadata_after,
    seed_row_counts,
    sessions_revoked,
    normalized_reason
  )
  returning id into receipt_id;

  return jsonb_build_object(
    'success', true,
    'replayed', false,
    'receiptId', receipt_id,
    'sourceTenantArchived', true,
    'profileRemoved', true,
    'sessionsRevoked', sessions_revoked
  );
end;
$$;

revoke all on function public.repair_legacy_accidental_customer_tenant_identity(
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  uuid,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.repair_legacy_accidental_customer_tenant_identity(
  text,
  uuid,
  uuid,
  uuid,
  uuid,
  uuid,
  text
) to service_role;

commit;
