-- Contain tenant/auth privilege escalation and make invitation acceptance a
-- bearer-token capability without exposing invitation rows or clear tokens.
--
-- Rollout contract:
--   * Edge creates/rotates a random clear token, stores only its SHA-256 through
--     rotate_user_invitation_token(...), and sends the clear token by email.
--   * Flutter resolves the token through lookup_user_invitation(text).
--   * New Auth signup hashes the clear invitation once, retains only the
--     server-owned verifier, and consumes it atomically after confirmation.
--   * Existing confirmed identities present the URL token directly to
--     accept_user_invitation(text); shared customer/staff identity is supported.
--   * Owner tenants are created only after email_confirmed_at becomes non-null.
--   * Customer authorization is always the tenant-scoped customers row.
--
-- This migration intentionally disables the legacy SQL auth-user delete RPC.
-- Auth-user lifecycle remains in the tenant-checked admin-user-management Edge
-- function, where Auth Admin API failures and dependent records are handled.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

alter table public.user_invitations
  add column if not exists token_hash text,
  add column if not exists consumed_token_hash text,
  add column if not exists token_issued_at timestamp with time zone,
  add column if not exists accepted_at timestamp with time zone,
  add column if not exists accepted_user_id uuid;

-- Production historically linked employees.user_id to the deprecated
-- users_profiles mirror. Auth onboarding assigns the Auth user id directly, so
-- keep that relationship authoritative even when no legacy mirror row exists.
do $$
begin
  if exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.employees'::regclass
      and constraint_row.conname = 'employees_user_id_fkey'
      and constraint_row.confrelid <> 'auth.users'::regclass
  ) then
    alter table public.employees
      drop constraint employees_user_id_fkey;
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.employees'::regclass
      and constraint_row.conname = 'employees_user_id_fkey'
  ) then
    alter table public.employees
      add constraint employees_user_id_fkey
      foreign key (user_id)
      references auth.users(id)
      not valid;
  end if;
end
$$;

alter table public.employees
  validate constraint employees_user_id_fkey;

alter table public.employee_portal_accounts
  add column if not exists password_reset_required_at
    timestamp with time zone,
  add column if not exists password_credential_issued_at
    timestamp with time zone,
  add column if not exists password_reset_challenge_started_at
    timestamp with time zone;

update public.employee_portal_accounts
set password_reset_required_at = coalesce(
      password_reset_required_at,
      updated_at,
      created_at,
      now()
    )
where must_reset_password is true;

update public.employee_portal_accounts
set password_credential_issued_at = coalesce(
      password_credential_issued_at,
      password_reset_required_at,
      updated_at,
      created_at,
      now()
    )
where must_reset_password is true;

create or replace function public.sync_worker_password_reset_requirement()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.must_reset_password is true then
    if tg_op = 'INSERT' then
      new.password_reset_required_at := coalesce(
        new.password_reset_required_at,
        now()
      );
      new.password_reset_challenge_started_at := null;
    elsif old.must_reset_password is false
       or new.password_reset_required_at is null
       or new.password_reset_required_at is distinct from
         old.password_reset_required_at then
      new.password_reset_required_at := coalesce(
        new.password_reset_required_at,
        now()
      );
      new.password_credential_issued_at := null;
      new.password_reset_challenge_started_at := null;
    elsif new.password_credential_issued_at is distinct from
          old.password_credential_issued_at then
      new.password_reset_challenge_started_at := null;
    end if;
  else
    new.password_reset_challenge_started_at := null;
  end if;

  return new;
end;
$$;

revoke all on function public.sync_worker_password_reset_requirement()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sync_worker_password_reset_requirement
  on public.employee_portal_accounts;
create trigger trg_sync_worker_password_reset_requirement
  before insert or update of
    must_reset_password,
    password_reset_required_at,
    password_credential_issued_at,
    password_reset_challenge_started_at
  on public.employee_portal_accounts
  for each row
  execute function public.sync_worker_password_reset_requirement();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.employee_portal_accounts'::regclass
      and conname =
        'employee_portal_accounts_password_credential_order_check'
  ) then
    alter table public.employee_portal_accounts
      add constraint
        employee_portal_accounts_password_credential_order_check
      check (
        password_credential_issued_at is null
        or (
          password_reset_required_at is not null
          and password_credential_issued_at >= password_reset_required_at
        )
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.employee_portal_accounts'::regclass
      and conname =
        'employee_portal_accounts_password_challenge_order_check'
  ) then
    alter table public.employee_portal_accounts
      add constraint
        employee_portal_accounts_password_challenge_order_check
      check (
        password_reset_challenge_started_at is null
        or (
          password_credential_issued_at is not null
          and password_reset_challenge_started_at >
            password_credential_issued_at
        )
      ) not valid;
  end if;
end
$$;

alter table public.employee_portal_accounts
  validate constraint
    employee_portal_accounts_password_credential_order_check;
alter table public.employee_portal_accounts
  validate constraint
    employee_portal_accounts_password_challenge_order_check;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.user_invitations'::regclass
      and conname = 'user_invitations_token_hash_format_check'
  ) then
    alter table public.user_invitations
      add constraint user_invitations_token_hash_format_check
      check (
        token_hash is null
        or token_hash ~ '^[0-9a-f]{64}$'
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.user_invitations'::regclass
      and conname = 'user_invitations_consumed_token_hash_format_check'
  ) then
    alter table public.user_invitations
      add constraint user_invitations_consumed_token_hash_format_check
      check (
        consumed_token_hash is null
        or consumed_token_hash ~ '^[0-9a-f]{64}$'
      ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.user_invitations'::regclass
      and conname = 'user_invitations_accepted_user_id_fkey'
  ) then
    alter table public.user_invitations
      add constraint user_invitations_accepted_user_id_fkey
      foreign key (accepted_user_id)
      references auth.users(id)
      on delete set null
      not valid;
  end if;
end
$$;

-- One-time compatibility conversion for any invitation created by the legacy
-- Edge function. Clear tokens are removed from metadata in the same statement.
update public.user_invitations
set token_hash = encode(
      extensions.digest(
        convert_to(metadata->>'invitation_token', 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    token_issued_at = coalesce(token_issued_at, created_at, now()),
    metadata = coalesce(metadata, '{}'::jsonb) - 'invitation_token'
where token_hash is null
  and nullif(metadata->>'invitation_token', '') is not null;

update public.user_invitations
set metadata = coalesce(metadata, '{}'::jsonb) - 'invitation_token'
where metadata ? 'invitation_token';

alter table public.user_invitations
  validate constraint user_invitations_token_hash_format_check;

alter table public.user_invitations
  validate constraint user_invitations_consumed_token_hash_format_check;

alter table public.user_invitations
  validate constraint user_invitations_accepted_user_id_fkey;

-- The legacy whole-history uniqueness constraint prevents a second accepted or
-- expired invitation for the same address. Pending capability uniqueness is
-- enforced by the partial, case-insensitive index below instead.
alter table public.user_invitations
  drop constraint if exists user_invitations_tenant_id_email_status_key;

create unique index if not exists user_invitations_pending_token_hash_uidx
  on public.user_invitations(token_hash)
  where token_hash is not null
    and status = 'pending';

create unique index if not exists
  user_invitations_one_pending_email_per_tenant_uidx
  on public.user_invitations(tenant_id, lower(email))
  where status = 'pending';

-- The current client has no tenant selector and resolves profiles with
-- maybeSingle(). Preserve inactive history, but fail deployment before allowing
-- two simultaneous active ERP tenant authorities for one Auth identity.
do $$
begin
  if exists (
    select 1
    from public.user_profiles profile
    where profile.is_active is true
    group by profile.user_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot enforce one active ERP tenant: users with multiple active profiles exist';
  end if;
end
$$;

drop index if exists public.user_profiles_one_tenant_per_user_uidx;
drop index if exists public.user_profiles_one_active_tenant_per_user_uidx;

create unique index user_profiles_one_active_tenant_per_user_uidx
  on public.user_profiles(user_id)
  where is_active is true;

-- Preserve a tenant owner across an e-mail change only when the existing Auth
-- claim is already bound to the same DB-backed tenant. A raw metadata owner
-- claim for any other tenant is not authority.
create or replace function public.is_auth_user_db_backed_tenant_owner(
  p_user_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users auth_user
    join public.tenants tenant
      on tenant.id = p_tenant_id
    where auth_user.id = p_user_id
      and (
        lower(auth_user.email) = lower(tenant.owner_email)
        or (
          auth_user.raw_app_meta_data ->> 'account_type' = 'erp_owner'
          and auth_user.raw_app_meta_data ->> 'tenant_id' = p_tenant_id::text
        )
      )
  );
$$;

revoke all on function public.is_auth_user_db_backed_tenant_owner(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.is_auth_user_db_backed_tenant_owner(uuid, uuid)
  to service_role;

-- Strip stale or forged authority from every Auth identity, including orphans,
-- then reconstruct application metadata solely from active DB relationships.
-- A valid unconfirmed invitation verifier is the only pending intent retained.
-- Existing login sessions must be refreshed after rollout.
with rebuilt_authority as (
  select
    auth_user.id,
    coalesce(
      (
        select jsonb_build_object(
          'account_type',
            case
              when public.is_auth_user_db_backed_tenant_owner(
                auth_user.id,
                profile.tenant_id
              )
                then 'erp_owner'
              else 'erp_staff'
            end,
          'tenant_id', profile.tenant_id,
          'role', profile.role
        )
        from public.user_profiles profile
        join public.tenants tenant
          on tenant.id = profile.tenant_id
         and tenant.is_active is true
        where profile.user_id = auth_user.id
          and profile.is_active is true
        limit 1
      ),
      (
        select jsonb_build_object(
          'account_type', 'worker_portal',
          'tenant_id', portal.tenant_id,
          'employee_id', portal.employee_id,
          'role', 'worker'
        )
        from public.employee_portal_accounts portal
        join public.employees employee
          on employee.id = portal.employee_id
         and employee.tenant_id = portal.tenant_id
         and employee.status = 'active'
        join public.tenants tenant
          on tenant.id = portal.tenant_id
         and tenant.is_active is true
        where portal.auth_user_id = auth_user.id
          and portal.is_active is true
        limit 1
      ),
      case
        when customer_authority.memberships <> '{}'::jsonb
          then jsonb_build_object(
            'account_type',
            'public_store_customer'
          )
        else '{}'::jsonb
      end
    )
    || case
      when customer_authority.memberships <> '{}'::jsonb
        then jsonb_build_object(
          'customer_memberships',
          customer_authority.memberships
        )
      else '{}'::jsonb
    end
    || case
      when pending_invitation.token_hash is not null
        then jsonb_build_object(
          'pending_invitation_token_hash',
          pending_invitation.token_hash
        )
      else '{}'::jsonb
    end as metadata
  from auth.users auth_user
  left join lateral (
    select coalesce(
      jsonb_object_agg(customer.tenant_id::text, customer.id),
      '{}'::jsonb
    ) as memberships
    from public.customers customer
    join public.tenants tenant
      on tenant.id = customer.tenant_id
     and tenant.is_active is true
    where customer.auth_user_id = auth_user.id
      and customer.is_active is true
  ) customer_authority on true
  left join lateral (
    select invitation.token_hash
    from public.user_invitations invitation
    join public.tenants tenant
      on tenant.id = invitation.tenant_id
     and tenant.is_active is true
    where auth_user.email_confirmed_at is null
      and invitation.token_hash =
        auth_user.raw_app_meta_data->>'pending_invitation_token_hash'
      and lower(invitation.email) = lower(auth_user.email)
      and invitation.status = 'pending'
      and invitation.expires_at > now()
    limit 1
  ) pending_invitation on true
)
update auth.users auth_user
set raw_user_meta_data = coalesce(
      auth_user.raw_user_meta_data,
      '{}'::jsonb
    )
      - 'account_type'
      - 'tenant_id'
      - 'employee_id'
      - 'role'
      - 'permissions'
      - 'customer_id'
      - 'customer_tenant_id'
      - 'invitation_token',
    raw_app_meta_data = (
      coalesce(auth_user.raw_app_meta_data, '{}'::jsonb)
      - 'account_type'
      - 'tenant_id'
      - 'employee_id'
      - 'role'
      - 'permissions'
      - 'customer_id'
      - 'customer_tenant_id'
      - 'customer_memberships'
      - 'pending_invitation_token_hash'
    ) || rebuilt_authority.metadata
from rebuilt_authority
where rebuilt_authority.id = auth_user.id;

create or replace function public.user_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select case
    when count(*) = 1 then (array_agg(profile.tenant_id))[1]
    else null
  end
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = auth.uid()
    and profile.is_active is true
$$;

revoke all on function public.user_tenant_id()
  from public, anon, authenticated, service_role;
grant execute on function public.user_tenant_id()
  to anon, authenticated, service_role;

-- Public/customer policies need one non-sensitive fact about tenants without
-- granting SELECT on the tenant authority table or inheriting its staff RLS.
create or replace function public.is_tenant_active(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  )
$$;

revoke all on function public.is_tenant_active(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.is_tenant_active(uuid)
  to anon, authenticated, service_role;

create or replace function public.is_active_tenant_member(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
  )
$$;

revoke all on function public.is_active_tenant_member(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.is_active_tenant_member(uuid)
  to authenticated, service_role;

create or replace function public.can_manage_tenant_users(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role in ('admin', 'manager')
        or profile.permissions @> '{"manage_users": true}'::jsonb
      )
  )
$$;

revoke all on function public.can_manage_tenant_users(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_tenant_users(uuid)
  to authenticated, service_role;

create or replace function public.can_manage_tenant_accounting(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role in ('admin', 'manager', 'accountant')
        or profile.permissions @> '{"access_accounting": true}'::jsonb
      )
  )
$$;

revoke all on function public.can_manage_tenant_accounting(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_tenant_accounting(uuid)
  to authenticated, service_role;

create or replace function public.is_global_bike_catalog_manager()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.is_active is true
      and profile.role in ('admin', 'manager')
  )
$$;

revoke all on function public.is_global_bike_catalog_manager()
  from public, anon, authenticated, service_role;
grant execute on function public.is_global_bike_catalog_manager()
  to service_role;

-- Replace every policy on the four auth-boundary tables. This also removes
-- dashboard-created policy drift that is not represented in core_schema.sql.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'tenants',
        'reserved_subdomains',
        'user_profiles',
        'user_invitations'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end
$$;

-- Accounting rows and the shared bicycle encyclopedia had live policy drift.
-- Rebuild their policies from DB-backed profile authority, never JWT metadata.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('journal_entries', 'journal_lines', 'bike_catalog')
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end
$$;

alter table public.tenants enable row level security;
alter table public.reserved_subdomains enable row level security;
alter table public.user_profiles enable row level security;
alter table public.user_invitations enable row level security;

create policy tenants_member_read_own
  on public.tenants
  for select
  to authenticated
  using (id = public.user_tenant_id());

create policy tenants_manager_update_own
  on public.tenants
  for update
  to authenticated
  using (
    id = public.user_tenant_id()
    and public.can_manage_tenant_users(id)
  )
  with check (
    id = public.user_tenant_id()
    and public.can_manage_tenant_users(id)
  );

create policy user_profiles_read_own_or_managed_tenant
  on public.user_profiles
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.can_manage_tenant_users(tenant_id)
  );

alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.bike_catalog enable row level security;

create policy journal_entries_read_tenant
  on public.journal_entries
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

create policy journal_entries_write_accounting
  on public.journal_entries
  for all
  to authenticated
  using (public.can_manage_tenant_accounting(tenant_id))
  with check (public.can_manage_tenant_accounting(tenant_id));

create policy journal_lines_read_tenant
  on public.journal_lines
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

create policy journal_lines_write_accounting
  on public.journal_lines
  for all
  to authenticated
  using (public.can_manage_tenant_accounting(tenant_id))
  with check (
    public.can_manage_tenant_accounting(tenant_id)
    and exists (
      select 1
      from public.journal_entries entry
      where entry.id = entry_id
        and entry.tenant_id = journal_lines.tenant_id
    )
  );

create policy bike_catalog_read_authenticated
  on public.bike_catalog
  for select
  to authenticated
  using (true);

revoke all on table public.tenants
  from public, anon, authenticated;
grant select on table public.tenants
  to authenticated;
grant update (
  shop_name,
  logo_url,
  custom_domain,
  currency,
  timezone,
  updated_at
) on table public.tenants
  to authenticated;
grant all on table public.tenants
  to service_role;

-- Public routing uses a deliberately narrow directory instead of SELECT on the
-- tenants authority table. The view owner can read through base-table RLS, but
-- the security barrier and fixed projection expose only storefront-safe data.
create or replace view public.public_tenant_directory
with (security_barrier = true)
as
select
  tenant.id,
  tenant.shop_name,
  tenant.subdomain,
  tenant.is_active,
  tenant.logo_url,
  tenant.currency,
  tenant.timezone,
  tenant.custom_domain,
  tenant.created_at,
  tenant.updated_at
from public.tenants tenant
where tenant.is_active is true;

revoke all on table public.public_tenant_directory
  from public, anon, authenticated, service_role;
grant select on table public.public_tenant_directory
  to anon, authenticated, service_role;

-- Customer identity is tenant-scoped. The legacy global UNIQUE(email) blocked
-- one confirmed Auth identity from shopping at more than one storefront.
do $$
declare
  constraint_row record;
  email_attribute smallint;
begin
  select attribute.attnum
  into email_attribute
  from pg_attribute attribute
  where attribute.attrelid = 'public.customers'::regclass
    and attribute.attname = 'email'
    and not attribute.attisdropped;

  for constraint_row in
    select constraint_record.conname
    from pg_constraint constraint_record
    where constraint_record.conrelid = 'public.customers'::regclass
      and constraint_record.contype = 'u'
      and array_length(constraint_record.conkey, 1) = 1
      and constraint_record.conkey[1] = email_attribute
  loop
    execute format(
      'alter table public.customers drop constraint %I',
      constraint_row.conname
    );
  end loop;
end
$$;

do $$
begin
  if exists (
    select 1
    from public.customers customer
    where customer.email is not null
    group by customer.tenant_id, lower(customer.email)
    having count(*) > 1
  ) then
    raise exception
      'Cannot scope customer email uniqueness: duplicate tenant/email rows exist';
  end if;

  if exists (
    select 1
    from public.customers customer
    where customer.auth_user_id is not null
    group by customer.tenant_id, customer.auth_user_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot scope customer Auth uniqueness: duplicate tenant/user rows exist';
  end if;
end
$$;

create unique index if not exists customers_tenant_email_lower_uidx
  on public.customers(tenant_id, lower(email))
  where email is not null;

create unique index if not exists customers_tenant_auth_user_uidx
  on public.customers(tenant_id, auth_user_id)
  where auth_user_id is not null;

-- Rebuild customer policies so public identities can never self-provision rows
-- or move an existing identity between tenants. Active ERP members retain their
-- existing tenant-scoped CRUD contract.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
  loop
    execute format(
      'drop policy if exists %I on public.customers',
      policy_row.policyname
    );
  end loop;
end
$$;

create policy customers_read_staff_or_self
  on public.customers
  for select
  to authenticated
  using (
    public.is_active_tenant_member(tenant_id)
    or (
      auth_user_id = auth.uid()
      and is_active is true
      and public.is_tenant_active(customers.tenant_id)
    )
  );

create policy customers_insert_staff_tenant
  on public.customers
  for insert
  to authenticated
  with check (public.is_active_tenant_member(tenant_id));

create policy customers_update_staff_or_self
  on public.customers
  for update
  to authenticated
  using (
    public.is_active_tenant_member(tenant_id)
    or (
      auth_user_id = auth.uid()
      and is_active is true
      and public.is_tenant_active(customers.tenant_id)
    )
  )
  with check (
    public.is_active_tenant_member(tenant_id)
    or (
      auth_user_id = auth.uid()
      and is_active is true
      and public.is_tenant_active(customers.tenant_id)
    )
  );

create policy customers_delete_staff_tenant
  on public.customers
  for delete
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

-- A suspended customer membership must fail closed across every customer-owned
-- child surface. Match both the customer and child tenant IDs so a forged
-- foreign key cannot bridge storefront tenants.
alter table public.customer_addresses enable row level security;
alter table public.online_orders enable row level security;
alter table public.online_order_items enable row level security;
alter table public.mechanic_jobs enable row level security;
alter table public.bikes enable row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'customer_addresses',
        'online_orders',
        'online_order_items',
        'mechanic_jobs',
        'bikes'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end
$$;

create policy customer_addresses_select
  on public.customer_addresses
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));
create policy customer_addresses_insert
  on public.customer_addresses
  for insert
  to authenticated
  with check (public.is_active_tenant_member(tenant_id));
create policy customer_addresses_update
  on public.customer_addresses
  for update
  to authenticated
  using (public.is_active_tenant_member(tenant_id))
  with check (public.is_active_tenant_member(tenant_id));
create policy customer_addresses_delete
  on public.customer_addresses
  for delete
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

create policy online_orders_select
  on public.online_orders
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));
create policy online_order_items_select
  on public.online_order_items
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

create policy mechanic_jobs_select
  on public.mechanic_jobs
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));
create policy mechanic_jobs_insert
  on public.mechanic_jobs
  for insert
  to authenticated
  with check (public.is_active_tenant_member(tenant_id));
create policy mechanic_jobs_update
  on public.mechanic_jobs
  for update
  to authenticated
  using (public.is_active_tenant_member(tenant_id))
  with check (public.is_active_tenant_member(tenant_id));
create policy mechanic_jobs_delete
  on public.mechanic_jobs
  for delete
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

create policy bikes_select
  on public.bikes
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));
create policy bikes_insert
  on public.bikes
  for insert
  to authenticated
  with check (public.is_active_tenant_member(tenant_id));
create policy bikes_update
  on public.bikes
  for update
  to authenticated
  using (public.is_active_tenant_member(tenant_id))
  with check (public.is_active_tenant_member(tenant_id));
create policy bikes_delete
  on public.bikes
  for delete
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

drop policy if exists public_customer_addresses_select_own
  on public.customer_addresses;
drop policy if exists public_customer_addresses_insert_own
  on public.customer_addresses;
drop policy if exists public_customer_addresses_update_own
  on public.customer_addresses;
drop policy if exists public_customer_addresses_delete_own
  on public.customer_addresses;

create policy public_customer_addresses_select_own
  on public.customer_addresses
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = customer_addresses.customer_id
        and customer.tenant_id = customer_addresses.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

create policy public_customer_addresses_insert_own
  on public.customer_addresses
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = customer_addresses.customer_id
        and customer.tenant_id = customer_addresses.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

create policy public_customer_addresses_update_own
  on public.customer_addresses
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = customer_addresses.customer_id
        and customer.tenant_id = customer_addresses.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  )
  with check (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = customer_addresses.customer_id
        and customer.tenant_id = customer_addresses.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

create policy public_customer_addresses_delete_own
  on public.customer_addresses
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = customer_addresses.customer_id
        and customer.tenant_id = customer_addresses.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

drop policy if exists public_online_orders_select_authenticated
  on public.online_orders;
create policy public_online_orders_select_authenticated
  on public.online_orders
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = online_orders.customer_id
        and customer.tenant_id = online_orders.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

drop policy if exists public_online_order_items_select_authenticated
  on public.online_order_items;
create policy public_online_order_items_select_authenticated
  on public.online_order_items
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.online_orders customer_order
      join public.customers customer
        on customer.id = customer_order.customer_id
       and customer.tenant_id = customer_order.tenant_id
      where customer_order.id = online_order_items.order_id
        and customer_order.tenant_id = online_order_items.tenant_id
        and public.is_tenant_active(customer.tenant_id)
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

drop policy if exists public_mechanic_jobs_select_own
  on public.mechanic_jobs;
create policy public_mechanic_jobs_select_own
  on public.mechanic_jobs
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = mechanic_jobs.customer_id
        and customer.tenant_id = mechanic_jobs.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

drop policy if exists public_bikes_select_own
  on public.bikes;
create policy public_bikes_select_own
  on public.bikes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.customers customer
      where public.is_tenant_active(customer.tenant_id)
        and customer.id = bikes.customer_id
        and customer.tenant_id = bikes.tenant_id
        and customer.auth_user_id = auth.uid()
        and customer.is_active is true
    )
  );

create or replace function public.guard_customer_identity_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if auth.uid() is null or auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.auth_user_id is distinct from old.auth_user_id then
    raise exception 'Customer tenant and Auth identity are immutable'
      using errcode = '42501';
  end if;

  if old.auth_user_id = auth.uid()
     and not public.is_active_tenant_member(old.tenant_id)
     and (
       to_jsonb(new) - array[
         'name',
         'phone',
         'rut',
         'image_url',
         'updated_at'
       ]::text[]
     ) is distinct from (
       to_jsonb(old) - array[
         'name',
         'phone',
         'rut',
         'image_url',
         'updated_at'
       ]::text[]
     ) then
    raise exception 'Customer self-service may update profile fields only'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_customer_identity_update()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_customer_identity_update
  on public.customers;
create trigger trg_guard_customer_identity_update
  before update on public.customers
  for each row
  execute function public.guard_customer_identity_update();

create or replace function public.guard_customer_address_identity_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if auth.uid() is null
     or auth.role() is distinct from 'authenticated'
     or public.is_active_tenant_member(old.tenant_id) then
    return new;
  end if;

  if exists (
       select 1
       from public.customers customer
       where customer.id = old.customer_id
         and customer.tenant_id = old.tenant_id
         and customer.auth_user_id = auth.uid()
     )
     and (
       new.customer_id is distinct from old.customer_id
       or new.tenant_id is distinct from old.tenant_id
     ) then
    raise exception 'Customer address identity is immutable'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_customer_address_identity_update()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_customer_address_identity_update
  on public.customer_addresses;
create trigger trg_guard_customer_address_identity_update
  before update on public.customer_addresses
  for each row
  execute function public.guard_customer_address_identity_update();

revoke all on table public.reserved_subdomains
  from public, anon, authenticated;
grant all on table public.reserved_subdomains
  to service_role;

create or replace view public.public_reserved_subdomains
with (security_barrier = true)
as
select reserved.subdomain
from public.reserved_subdomains reserved;

revoke all on table public.public_reserved_subdomains
  from public, anon, authenticated, service_role;
grant select on table public.public_reserved_subdomains
  to anon, authenticated, service_role;

revoke all on table public.user_profiles
  from public, anon, authenticated;
grant select on table public.user_profiles
  to authenticated;
grant all on table public.user_profiles
  to service_role;

revoke all on table public.user_invitations
  from public, anon, authenticated;
grant all on table public.user_invitations
  to service_role;

-- Internal payment repair evidence contains amounts, references, and reasons.
-- It has no client contract and must not inherit the schema-wide table grants.
alter table public.payment_integrity_backfill_audit
  enable row level security;
alter table public.payment_integrity_backfill_audit
  force row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'payment_integrity_backfill_audit'
  loop
    execute format(
      'drop policy if exists %I on public.payment_integrity_backfill_audit',
      policy_row.policyname
    );
  end loop;
end
$$;

revoke all on table public.payment_integrity_backfill_audit
  from public, anon, authenticated, service_role;
grant all on table public.payment_integrity_backfill_audit
  to service_role;

revoke all on table public.journal_entries
  from public, anon, authenticated;
grant select, insert, update, delete on table public.journal_entries
  to authenticated;
grant all on table public.journal_entries
  to service_role;

revoke all on table public.journal_lines
  from public, anon, authenticated;
grant select, insert, update, delete on table public.journal_lines
  to authenticated;
grant all on table public.journal_lines
  to service_role;

revoke all on table public.bike_catalog
  from public, anon, authenticated;
grant select on table public.bike_catalog
  to authenticated;
grant all on table public.bike_catalog
  to service_role;

create or replace function public.rotate_user_invitation_token(
  p_invitation_id uuid,
  p_tenant_id uuid,
  p_token_hash text,
  p_expires_at timestamp with time zone
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  current_token_hash text;
  current_token_issued_at timestamp with time zone;
begin
  if auth.role() is distinct from 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'Service role required'
      using errcode = '42501';
  end if;

  if p_invitation_id is null
     or p_tenant_id is null
     or p_token_hash is null
     or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid invitation token rotation input'
      using errcode = '22023';
  end if;

  if p_expires_at is null
     or p_expires_at <= now()
     or p_expires_at > now() + interval '30 days' then
    raise exception 'Invitation expiry must be within the next 30 days'
      using errcode = '22023';
  end if;

  select invitation.token_hash, invitation.token_issued_at
  into current_token_hash, current_token_issued_at
  from public.user_invitations invitation
  join public.tenants tenant
    on tenant.id = invitation.tenant_id
   and tenant.is_active is true
  where invitation.id = p_invitation_id
    and invitation.tenant_id = p_tenant_id
    and invitation.status = 'pending'
  for update of invitation;

  if not found then
    return false;
  end if;

  -- Network retries carrying the same token are idempotent. A different token
  -- inside the cooldown is rejected so the caller never emails an unstored
  -- token and rapid resend abuse cannot churn invitation capabilities.
  if current_token_hash = p_token_hash then
    return true;
  end if;

  if current_token_issued_at is not null
     and current_token_issued_at > now() - interval '60 seconds' then
    raise exception 'Invitation token rotation is rate limited'
      using errcode = '55000';
  end if;

  update public.user_invitations invitation
  set token_hash = p_token_hash,
      token_issued_at = now(),
      expires_at = p_expires_at,
      accepted_at = null,
      accepted_user_id = null,
      metadata = coalesce(invitation.metadata, '{}'::jsonb)
        - 'invitation_token'
  where invitation.id = p_invitation_id;

  return true;
end;
$$;

revoke all on function public.rotate_user_invitation_token(
  uuid,
  uuid,
  text,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.rotate_user_invitation_token(
  uuid,
  uuid,
  text,
  timestamp with time zone
) to service_role;

create or replace function public.lookup_user_invitation(p_token text)
returns table (
  invitation_id uuid,
  email text,
  role text,
  tenant_id uuid,
  shop_name text,
  expires_at timestamp with time zone
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
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
    invitation.expires_at
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

revoke all on function public.lookup_user_invitation(text)
  from public, anon, authenticated, service_role;
grant execute on function public.lookup_user_invitation(text)
  to anon, authenticated, service_role;

create or replace function public.accept_user_invitation(p_token text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  auth_user_id_value uuid := auth.uid();
  auth_email text;
  token_digest text;
  invitation_row public.user_invitations%rowtype;
  active_profile_tenant_id uuid;
begin
  if auth_user_id_value is null
     or p_token is null
     or length(p_token) < 32
     or length(p_token) > 512 then
    raise exception 'Invalid or unavailable invitation'
      using errcode = '42501';
  end if;

  select lower(nullif(trim(auth_user.email), ''))
  into auth_email
  from auth.users auth_user
  where auth_user.id = auth_user_id_value
    and auth_user.email_confirmed_at is not null;

  if not found or auth_email is null then
    raise exception 'Invalid or unavailable invitation'
      using errcode = '42501';
  end if;

  token_digest := encode(
    extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'),
    'hex'
  );

  -- A completed retry is safe and does not recreate profile/employee links.
  if exists (
    select 1
    from public.user_invitations invitation
    where invitation.consumed_token_hash = token_digest
      and invitation.status = 'accepted'
      and invitation.accepted_user_id = auth_user_id_value
  ) then
    return true;
  end if;

  select invitation.*
  into invitation_row
  from public.user_invitations invitation
  join public.tenants tenant
    on tenant.id = invitation.tenant_id
   and tenant.is_active is true
  where invitation.token_hash = token_digest
    and lower(invitation.email) = auth_email
    and invitation.status = 'pending'
    and invitation.expires_at > now()
  limit 1
  for update of invitation;

  if not found then
    raise exception 'Invalid or unavailable invitation'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = auth_user_id_value
  ) then
    raise exception 'Invitation cannot be accepted by this identity'
      using errcode = '42501';
  end if;

  select profile.tenant_id
  into active_profile_tenant_id
  from public.user_profiles profile
  where profile.user_id = auth_user_id_value
    and profile.is_active is true
  limit 1
  for update;

  if found then
    if active_profile_tenant_id <> invitation_row.tenant_id then
      raise exception 'Invalid or unavailable invitation'
        using errcode = '42501';
    end if;

    -- A same-tenant active membership is already authoritative. Consume the
    -- matching invitation as an idempotent receipt without changing role,
    -- permissions, or employee linkage.
    update public.user_invitations
    set status = 'accepted',
        accepted_at = now(),
        accepted_user_id = auth_user_id_value,
        consumed_token_hash = token_digest,
        token_hash = null,
        metadata = coalesce(metadata, '{}'::jsonb) - 'invitation_token'
    where id = invitation_row.id
      and status = 'pending';

    if not found then
      raise exception 'Invalid or unavailable invitation'
        using errcode = '42501';
    end if;

    return true;
  end if;

  if invitation_row.employee_id is not null then
    update public.employees employee
    set user_id = auth_user_id_value,
        updated_at = now()
    where employee.id = invitation_row.employee_id
      and employee.tenant_id = invitation_row.tenant_id
      and employee.status = 'active'
      and (
        employee.user_id is null
        or employee.user_id = auth_user_id_value
      );

    if not found then
      raise exception 'Invalid or unavailable invitation'
        using errcode = '42501';
    end if;
  end if;

  insert into public.user_profiles (
    user_id,
    tenant_id,
    role,
    is_active,
    permissions,
    employee_id
  )
  values (
    auth_user_id_value,
    invitation_row.tenant_id,
    invitation_row.role,
    true,
    invitation_row.permissions,
    invitation_row.employee_id
  );

  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
        - 'account_type'
        - 'tenant_id'
        - 'employee_id'
        - 'role'
        - 'permissions'
        - 'invitation_token',
      raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
        || jsonb_build_object(
          'account_type', 'erp_staff',
          'tenant_id', invitation_row.tenant_id,
          'role', invitation_row.role
        )
  where id = auth_user_id_value;

  update public.user_invitations
  set status = 'accepted',
      accepted_at = now(),
      accepted_user_id = auth_user_id_value,
      consumed_token_hash = token_digest,
      token_hash = null,
      metadata = coalesce(metadata, '{}'::jsonb) - 'invitation_token'
  where id = invitation_row.id
    and status = 'pending';

  if not found then
    raise exception 'Invalid or unavailable invitation'
      using errcode = '42501';
  end if;

  return true;
end;
$$;

revoke all on function public.accept_user_invitation(text)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_user_invitation(text)
  to authenticated;

create or replace function public.provision_current_public_store_customer(
  p_tenant_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  auth_user_id_value uuid := auth.uid();
  auth_email text;
  auth_metadata jsonb;
  auth_app_metadata jsonb;
  customer_id_value uuid;
  existing_customer_user_id uuid;
  existing_customer_is_active boolean;
  customer_name_value text;
  preserve_workforce_metadata boolean;
begin
  if auth_user_id_value is null or p_tenant_id is null then
    raise exception 'Authenticated customer and tenant are required'
      using errcode = '42501';
  end if;

  select
    lower(nullif(trim(auth_user.email), '')),
    coalesce(auth_user.raw_user_meta_data, '{}'::jsonb),
    coalesce(auth_user.raw_app_meta_data, '{}'::jsonb)
  into auth_email, auth_metadata, auth_app_metadata
  from auth.users auth_user
  where auth_user.id = auth_user_id_value
    and auth_user.email_confirmed_at is not null
  for update;

  if not found or auth_email is null then
    raise exception 'A confirmed Auth email is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Storefront tenant is invalid or inactive'
      using errcode = '42501';
  end if;

  preserve_workforce_metadata :=
    exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth_user_id_value
    )
    or exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.auth_user_id = auth_user_id_value
    )
    or coalesce(auth_app_metadata->>'account_type', '') in (
      'erp_owner',
      'erp_staff',
      'worker_portal'
    )
    or coalesce(auth_app_metadata->>'role', '') in (
      'admin',
      'manager',
      'cashier',
      'mechanic',
      'accountant',
      'worker'
    );

  -- Serialize email-based linking so OAuth callbacks and auth-state retries
  -- cannot create two rows for the same customer/store pair.
  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':' || auth_email, 0)
  );

  select customer.id, customer.auth_user_id, customer.is_active
  into
    customer_id_value,
    existing_customer_user_id,
    existing_customer_is_active
  from public.customers customer
  where customer.tenant_id = p_tenant_id
    and customer.auth_user_id = auth_user_id_value
  limit 1
  for update;

  if customer_id_value is null then
    select customer.id, customer.auth_user_id, customer.is_active
    into
      customer_id_value,
      existing_customer_user_id,
      existing_customer_is_active
    from public.customers customer
    where customer.tenant_id = p_tenant_id
      and lower(customer.email) = auth_email
    limit 1
    for update;
  end if;

  if customer_id_value is not null
     and existing_customer_user_id is not null
     and existing_customer_user_id <> auth_user_id_value then
    raise exception 'Store customer email is already linked to another Auth user'
      using errcode = '23505';
  end if;

  if customer_id_value is not null
     and existing_customer_is_active is not true then
    raise exception 'Customer membership is inactive'
      using errcode = '42501';
  end if;

  customer_name_value := coalesce(
    nullif(trim(auth_metadata->>'full_name'), ''),
    nullif(trim(auth_metadata->>'name'), ''),
    split_part(auth_email, '@', 1)
  );

  if customer_id_value is null then
    insert into public.customers (
      tenant_id,
      auth_user_id,
      name,
      email,
      is_active
    )
    values (
      p_tenant_id,
      auth_user_id_value,
      customer_name_value,
      auth_email,
      true
    )
    returning id into customer_id_value;
  else
    if exists (
      select 1
      from public.customers conflicting_customer
      where conflicting_customer.tenant_id = p_tenant_id
        and lower(conflicting_customer.email) = auth_email
        and conflicting_customer.id <> customer_id_value
    ) then
      raise exception 'Store customer email resolves to conflicting rows'
        using errcode = '23505';
    end if;

    update public.customers
    set auth_user_id = auth_user_id_value,
        email = auth_email,
        name = coalesce(nullif(name, ''), customer_name_value),
        updated_at = now()
    where id = customer_id_value
      and tenant_id = p_tenant_id;
  end if;

  update public.online_orders
  set customer_id = customer_id_value,
      updated_at = now()
  where tenant_id = p_tenant_id
    and customer_id is null
    and lower(customer_email) = auth_email;

  -- User metadata is user-editable and therefore display-only. Remove identity
  -- and authorization-shaped keys regardless of whether this is customer-only
  -- or a shared workforce/customer identity.
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
        - 'account_type'
        - 'tenant_id'
        - 'employee_id'
        - 'role'
        - 'permissions'
        - 'customer_id'
        - 'customer_tenant_id'
  where id = auth_user_id_value;

  -- A staff/worker may also shop as a customer. Customer authorization always
  -- comes from public.customers, so never replace the authoritative workforce
  -- account_type, tenant, or role claims for a shared identity.
  if preserve_workforce_metadata then
    update auth.users
    set raw_app_meta_data = coalesce(
          raw_app_meta_data,
          '{}'::jsonb
        ) || jsonb_build_object(
          'customer_memberships',
          coalesce(
            raw_app_meta_data->'customer_memberships',
            '{}'::jsonb
          ) || jsonb_build_object(
            p_tenant_id::text,
            customer_id_value
          )
        )
    where id = auth_user_id_value;
  else
    update auth.users
    set raw_app_meta_data = (
          coalesce(raw_app_meta_data, '{}'::jsonb)
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'permissions'
          - 'customer_id'
          - 'customer_tenant_id'
        )
          || jsonb_build_object(
            'account_type', 'public_store_customer',
            'customer_memberships',
              coalesce(
                raw_app_meta_data->'customer_memberships',
                '{}'::jsonb
              ) || jsonb_build_object(
                p_tenant_id::text,
                customer_id_value
              )
          )
    where id = auth_user_id_value;
  end if;

  return customer_id_value;
end;
$$;

revoke all on function public.provision_current_public_store_customer(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.provision_current_public_store_customer(uuid)
  to authenticated;

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
  existing_order_id uuid;
  order_id_value uuid;
  order_tenant_id uuid;
  access_receipt jsonb;
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

  -- Guest checkouts must omit customer_id. A caller may attach an order to a
  -- customer only when the current Auth identity owns that active membership;
  -- tenant equality alone is not proof of ownership.
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

  perform pg_advisory_xact_lock(
    hashtextextended(tenant_id_value::text || ':' || checkout_key, 0)
  );

  select customer_order.id
  into existing_order_id
  from public.online_orders customer_order
  where customer_order.tenant_id = tenant_id_value
    and customer_order.checkout_idempotency_key = checkout_key;
  is_replay := found;

  order_id_value := public.create_public_online_order(
    p_order_data || jsonb_build_object(
      'checkout_idempotency_key',
      checkout_key
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

create or replace function public.quote_public_online_shipping(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Storefront tenant is invalid or inactive'
      using errcode = '42501';
  end if;

  return public.quote_online_shipping_internal(
    p_tenant_id,
    p_delivery_type,
    p_item_gross,
    p_country_code
  );
end;
$$;

create or replace function public.get_tenant_users(p_tenant_id uuid)
returns table (
  id uuid,
  email text,
  role text,
  permissions jsonb,
  is_active boolean,
  last_sign_in timestamp with time zone,
  created_at timestamp with time zone,
  employee_id uuid,
  employee_name text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if auth.uid() is null
     or p_tenant_id is null
     or not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'Not authorized for this tenant'
      using errcode = '42501';
  end if;

  return query
  select
    auth_user.id,
    auth_user.email::text,
    profile.role::text,
    profile.permissions,
    profile.is_active,
    auth_user.last_sign_in_at,
    auth_user.created_at,
    employee.id,
    nullif(
      trim(
        coalesce(employee.first_name, '')
        || ' '
        || coalesce(employee.last_name, '')
      ),
      ''
    )
  from public.user_profiles profile
  join auth.users auth_user
    on auth_user.id = profile.user_id
  left join public.employees employee
    on employee.user_id = profile.user_id
   and employee.tenant_id = profile.tenant_id
  where profile.tenant_id = p_tenant_id
  order by auth_user.created_at desc;
end;
$$;

revoke all on function public.get_tenant_users(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_tenant_users(uuid)
  to authenticated;

create or replace function public.delete_tenant_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  raise exception
    'delete_tenant_user is disabled; use admin-user-management'
    using errcode = '42501';
end;
$$;

revoke all on function public.delete_tenant_user(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.erp_actor_display_name(
  p_user_id uuid,
  p_tenant_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  actor_name text;
begin
  if p_user_id is null or p_tenant_id is null then
    return null;
  end if;

  select nullif(
    trim(
      coalesce(employee.first_name, '')
      || ' '
      || coalesce(employee.last_name, '')
    ),
    ''
  )
  into actor_name
  from public.user_profiles profile
  join public.employees employee
    on employee.id = profile.employee_id
   and employee.tenant_id = profile.tenant_id
  where profile.user_id = p_user_id
    and profile.tenant_id = p_tenant_id
  limit 1;

  if actor_name is not null then
    return actor_name;
  end if;

  -- Auth metadata is considered only after proving that the target identity is
  -- attached to this tenant. Email is deliberately not used as a fallback.
  if not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = p_user_id
      and profile.tenant_id = p_tenant_id
    union all
    select 1
    from public.customers customer
    where customer.auth_user_id = p_user_id
      and customer.tenant_id = p_tenant_id
    union all
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = p_user_id
      and portal.tenant_id = p_tenant_id
  ) then
    return null;
  end if;

  select nullif(
    trim(
      coalesce(
        auth_user.raw_user_meta_data->>'full_name',
        auth_user.raw_user_meta_data->>'name',
        auth_user.raw_user_meta_data->>'display_name',
        ''
      )
    ),
    ''
  )
  into actor_name
  from auth.users auth_user
  where auth_user.id = p_user_id;

  return actor_name;
end;
$$;

revoke all on function public.erp_actor_display_name(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  account_type text := coalesce(new.raw_user_meta_data->>'account_type', '');
  invitation_token text;
  invitation_digest text;
  invitation_row public.user_invitations%rowtype;
  tenant_id_value uuid;
  employee_id_value uuid;
  shop_name_value text;
  subdomain_base text;
  subdomain_value text;
  subdomain_counter integer := 0;
begin
  if tg_op = 'UPDATE' then
    if old.email_confirmed_at is not null
       or new.email_confirmed_at is null then
      return new;
    end if;
  end if;

  if account_type = 'worker_portal'
     or coalesce(new.raw_app_meta_data->>'account_type', '') =
       'worker_portal' then
    if coalesce(new.raw_app_meta_data->>'account_type', '') <>
         'worker_portal'
       or coalesce(new.raw_app_meta_data->>'role', '') <> 'worker'
       or nullif(new.raw_app_meta_data->>'tenant_id', '') is null
       or nullif(new.raw_app_meta_data->>'employee_id', '') is null then
      raise exception 'Authoritative worker portal metadata is required';
    end if;

    if new.email_confirmed_at is null then
      raise exception 'Worker Auth identity must be confirmed by the Admin API';
    end if;

    begin
      tenant_id_value :=
        nullif(new.raw_app_meta_data->>'tenant_id', '')::uuid;
      employee_id_value :=
        nullif(new.raw_app_meta_data->>'employee_id', '')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'Invalid worker portal tenant or employee identifier';
    end;

    if tenant_id_value is null
       or employee_id_value is null
       or not exists (
         select 1
         from public.employees employee
         join public.tenants tenant
           on tenant.id = employee.tenant_id
          and tenant.is_active is true
         where employee.id = employee_id_value
           and employee.tenant_id = tenant_id_value
           and employee.status = 'active'
       ) then
      raise exception 'Invalid worker portal tenant or employee';
    end if;

    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          - 'account_type'
          - 'shop_name'
          - 'subdomain'
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'invitation_token',
        raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
          || jsonb_build_object(
            'account_type', 'worker_portal',
            'tenant_id', tenant_id_value,
            'employee_id', employee_id_value,
            'role', 'worker'
          )
    where id = new.id;

    -- employee_portal_accounts is the sole authorization link for workers and
    -- is inserted by the tenant-checked Edge function after Auth creation.
    return new;
  end if;

  if account_type = 'public_store_customer' then
    if coalesce(new.raw_app_meta_data->>'account_type', '') not in (
      '',
      'public_store_customer'
    )
       or new.raw_app_meta_data ? 'tenant_id'
       or new.raw_app_meta_data ? 'employee_id'
       or coalesce(new.raw_app_meta_data->>'role', '') in (
         'admin',
         'manager',
         'cashier',
         'mechanic',
         'accountant',
         'worker'
       ) then
      raise exception 'Customer signup cannot carry ERP or worker authority';
    end if;

    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
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
        raw_app_meta_data = (
          coalesce(raw_app_meta_data, '{}'::jsonb)
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'permissions'
          - 'customer_id'
          - 'customer_tenant_id'
          - 'account_type'
          - 'shop_name'
          - 'subdomain'
        )
    where id = new.id;

    -- Confirmation/login then calls provision_current_public_store_customer()
    -- with the tenant resolved from the storefront URL. No tenant authority is
    -- accepted from signup metadata.
    return new;
  end if;

  if account_type = 'staff_invitation'
     or nullif(
       new.raw_app_meta_data->>'pending_invitation_token_hash',
       ''
     ) is not null then
    if account_type = 'staff_invitation' then
      invitation_token :=
        nullif(new.raw_user_meta_data->>'invitation_token', '');

      if new.email is null
         or invitation_token is null
         or length(invitation_token) < 32
         or length(invitation_token) > 512 then
        raise exception 'A valid invitation token is required';
      end if;

      invitation_digest := encode(
        extensions.digest(
          convert_to(invitation_token, 'UTF8'),
          'sha256'
        ),
        'hex'
      );

      if not exists (
        select 1
        from public.user_invitations invitation
        join public.tenants tenant
          on tenant.id = invitation.tenant_id
         and tenant.is_active is true
        where invitation.token_hash = invitation_digest
          and lower(invitation.email) = lower(new.email)
          and invitation.status = 'pending'
          and invitation.expires_at > now()
      ) then
        raise exception 'Invitation is invalid, expired, used, or belongs to another email';
      end if;

      update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
            - 'account_type'
            - 'tenant_id'
            - 'employee_id'
            - 'role'
            - 'permissions'
            - 'invitation_token',
          raw_app_meta_data = (
            coalesce(raw_app_meta_data, '{}'::jsonb)
            - 'tenant_id'
            - 'employee_id'
            - 'role'
            - 'permissions'
          ) || jsonb_build_object(
            'pending_invitation_token_hash',
            invitation_digest
          )
      where id = new.id;
    else
      invitation_digest :=
        new.raw_app_meta_data->>'pending_invitation_token_hash';
    end if;

    if invitation_digest !~ '^[0-9a-f]{64}$' then
      raise exception 'Invalid pending invitation verifier';
    end if;

    if new.email_confirmed_at is null then
      return new;
    end if;

    select invitation.*
    into invitation_row
    from public.user_invitations invitation
    join public.tenants tenant
      on tenant.id = invitation.tenant_id
     and tenant.is_active is true
    where invitation.token_hash = invitation_digest
      and lower(invitation.email) = lower(new.email)
      and invitation.status = 'pending'
      and invitation.expires_at > now()
    limit 1
    for update of invitation;

    if not found then
      -- Mailbox confirmation must not become permanently uncommittable merely
      -- because the invitation expired or was rotated after signup. Remove the
      -- stale server-owned intent and leave the confirmed identity unassigned;
      -- a fresh invitation remains consumable through the existing-user RPC.
      update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
            - 'account_type'
            - 'tenant_id'
            - 'employee_id'
            - 'role'
            - 'permissions'
            - 'invitation_token',
          raw_app_meta_data = coalesce(
            raw_app_meta_data,
            '{}'::jsonb
          ) - 'pending_invitation_token_hash'
      where id = new.id;

      return new;
    end if;

    if exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.auth_user_id = new.id
    )
       or exists (
         select 1
         from public.user_profiles profile
         where profile.user_id = new.id
           and profile.is_active is true
       ) then
      raise exception 'Invitation cannot be accepted by this identity';
    end if;

    if invitation_row.employee_id is not null then
      update public.employees employee
      set user_id = new.id,
          updated_at = now()
      where employee.id = invitation_row.employee_id
        and employee.tenant_id = invitation_row.tenant_id
        and employee.status = 'active'
        and (
          employee.user_id is null
          or employee.user_id = new.id
        );

      if not found then
        raise exception 'Invitation employee is invalid or already linked';
      end if;
    end if;

    insert into public.user_profiles (
      user_id,
      tenant_id,
      role,
      is_active,
      permissions,
      employee_id
    )
    values (
      new.id,
      invitation_row.tenant_id,
      invitation_row.role,
      true,
      invitation_row.permissions,
      invitation_row.employee_id
    );

    update public.user_invitations
    set status = 'accepted',
        accepted_at = now(),
        accepted_user_id = new.id,
        consumed_token_hash = invitation_digest,
        token_hash = null,
        metadata = coalesce(metadata, '{}'::jsonb) - 'invitation_token'
    where id = invitation_row.id
      and status = 'pending';

    if not found then
      raise exception 'Invitation was already consumed';
    end if;

    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          - 'account_type'
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'permissions'
          - 'invitation_token',
        raw_app_meta_data = (
          coalesce(raw_app_meta_data, '{}'::jsonb)
          - 'pending_invitation_token_hash'
        ) || jsonb_build_object(
          'account_type', 'erp_staff',
          'tenant_id', invitation_row.tenant_id,
          'role', invitation_row.role
        )
    where id = new.id;

    return new;
  end if;

  -- A pending staff invitation can never fall through to owner provisioning;
  -- it remains unassigned until the confirmed user presents the bearer token.
  if new.email is not null
     and exists (
       select 1
       from public.user_invitations invitation
       where lower(invitation.email) = lower(new.email)
         and invitation.status = 'pending'
         and invitation.expires_at > now()
     ) then
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          - 'account_type'
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'permissions'
          - 'invitation_token'
    where id = new.id;
    return new;
  end if;

  -- Owner tenant creation is deferred until Auth proves mailbox ownership.
  if new.email_confirmed_at is null then
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          - 'account_type'
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'permissions'
          - 'invitation_token'
    where id = new.id;
    return new;
  end if;

  -- OAuth identities without explicit shop intent remain unassigned. Owner
  -- provisioning is public by design, but only through the known empty/owner
  -- account types and a bounded explicit business name.
  if account_type not in ('', 'erp_owner') then
    raise exception 'Unsupported account type for ERP owner signup';
  end if;

  if nullif(trim(new.raw_user_meta_data->>'shop_name'), '') is null then
    if account_type = 'erp_owner' then
      raise exception 'A shop name is required to create an ERP tenant';
    end if;
    return new;
  end if;

  shop_name_value := trim(new.raw_user_meta_data->>'shop_name');

  if new.email is null
     or length(shop_name_value) < 3
     or length(shop_name_value) > 120
     or shop_name_value ~ '[[:cntrl:]<>]' then
    raise exception 'ERP shop name must contain 3 to 120 safe characters';
  end if;

  subdomain_base := lower(
    regexp_replace(
      coalesce(
        nullif(trim(new.raw_user_meta_data->>'subdomain'), ''),
        shop_name_value
      ),
      '[^a-z0-9]+',
      '-',
      'g'
    )
  );
  subdomain_base := trim(both '-' from subdomain_base);
  subdomain_base := left(subdomain_base, 48);

  if length(subdomain_base) < 2 then
    subdomain_base := 'shop-' || left(replace(new.id::text, '-', ''), 10);
  end if;

  loop
    subdomain_value := case
      when subdomain_counter = 0 then subdomain_base
      else left(subdomain_base, 48)
        || '-'
        || subdomain_counter::text
    end;

    if exists (
      select 1
      from public.reserved_subdomains reserved
      where reserved.subdomain = subdomain_value
    ) then
      subdomain_counter := subdomain_counter + 1;
      continue;
    end if;

    begin
      insert into public.tenants (
        shop_name,
        subdomain,
        owner_email,
        plan,
        is_active,
        currency,
        timezone
      )
      values (
        shop_name_value,
        subdomain_value,
        lower(new.email),
        'free',
        true,
        'CLP',
        'America/Santiago'
      )
      returning id into tenant_id_value;
      exit;
    exception
      when unique_violation then
        subdomain_counter := subdomain_counter + 1;
    end;

    if subdomain_counter > 100 then
      raise exception 'Could not generate a unique subdomain';
    end if;
  end loop;

  insert into public.user_profiles (
    user_id,
    tenant_id,
    role,
    is_active,
    permissions
  )
  values (
    new.id,
    tenant_id_value,
    'admin',
    true,
    '{
      "access_pos": true,
      "create_invoices": true,
      "edit_prices": true,
      "delete_invoices": true,
      "access_accounting": true,
      "manage_users": true,
      "edit_settings": true
    }'::jsonb
  );

  update auth.users
  set raw_user_meta_data = (
        coalesce(raw_user_meta_data, '{}'::jsonb)
        || jsonb_build_object(
          'shop_name', shop_name_value,
          'subdomain', subdomain_value
        )
      )
        - 'account_type'
        - 'tenant_id'
        - 'employee_id'
        - 'role'
        - 'permissions'
        - 'invitation_token',
      raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
        || jsonb_build_object(
          'account_type', 'erp_owner',
          'tenant_id', tenant_id_value,
          'role', 'admin'
        )
  where id = new.id;

  return new;
end;
$$;

revoke all on function public.handle_new_user()
  from public, anon, authenticated, service_role;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
  after update of email_confirmed_at on auth.users
  for each row
  when (
    old.email_confirmed_at is null
    and new.email_confirmed_at is not null
  )
  execute function public.handle_new_user();

-- Username-to-email resolution necessarily reveals account existence and is
-- therefore a server-side primitive only. The public login flow calls an Edge
-- proxy that performs this lookup with service_role and returns one constant
-- external response shape.
create or replace function public.resolve_worker_login(
  p_tenant text,
  p_username text
)
returns table (login_email text)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_key text := lower(trim(coalesce(p_tenant, '')));
  normalized_username text :=
    public.normalize_worker_username(left(coalesce(p_username, ''), 128));
  tenant_id_value uuid;
  tenant_uuid_candidate uuid;
  tenant_match_count integer := 0;
begin
  if length(tenant_key) < 1 or length(tenant_key) > 253 then
    return;
  end if;

  begin
    tenant_uuid_candidate := tenant_key::uuid;
  exception
    when invalid_text_representation then
      tenant_uuid_candidate := null;
  end;

  tenant_key := trim(
    trailing '/' from regexp_replace(
      tenant_key,
      '^https?://',
      '',
      'i'
    )
  );

  select count(*)::integer, (array_agg(matched_tenant.id))[1]
  into tenant_match_count, tenant_id_value
  from (
    select tenant.id
    from public.tenants tenant
    where tenant.is_active is true
      and (
        tenant.id = tenant_uuid_candidate
        or lower(trim(coalesce(tenant.subdomain, ''))) = tenant_key
        or trim(
          trailing '/' from regexp_replace(
            lower(trim(coalesce(tenant.custom_domain, ''))),
            '^https?://',
            '',
            'i'
          )
        ) = tenant_key
      )
    limit 2
  ) matched_tenant;

  if tenant_match_count <> 1 or tenant_id_value is null then
    return;
  end if;

  return query
  select portal.login_email
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  where portal.tenant_id = tenant_id_value
    and portal.username = normalized_username
    and portal.is_active is true
    and employee.status = 'active'
  limit 1;
end;
$$;

-- Before a required password reset is completed, expose only enough context
-- to render the reset gate. Payroll and employee PII remain unavailable until
-- the independently audited password update clears the reset requirement.
create or replace function public.get_my_worker_portal_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  context_value jsonb;
begin
  select jsonb_build_object(
    'account', jsonb_build_object(
      'id', portal.id,
      'username', portal.username,
      'mustResetPassword', portal.must_reset_password,
      'isActive', portal.is_active
    ),
    'tenant', jsonb_build_object(
      'id', tenant.id,
      'shopName', tenant.shop_name,
      'subdomain', tenant.subdomain
    )
  )
  into context_value
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  join public.tenants tenant
    on tenant.id = portal.tenant_id
  where portal.auth_user_id = auth.uid()
    and portal.is_active is true
    and portal.must_reset_password is true
    and employee.status = 'active'
    and tenant.is_active is true
  limit 1;

  if context_value is not null then
    return context_value;
  end if;

  select jsonb_build_object(
    'account', jsonb_build_object(
      'id', portal.id,
      'username', portal.username,
      'mustResetPassword', portal.must_reset_password,
      'isActive', portal.is_active,
      'createdAt', portal.created_at,
      'lastLoginAt', portal.last_login_at
    ),
    'tenant', jsonb_build_object(
      'id', tenant.id,
      'shopName', tenant.shop_name,
      'subdomain', tenant.subdomain,
      'timezone', tenant.timezone
    ),
    'storeSchedule', (
      select jsonb_build_object(
        'source',
          coalesce(
            max(setting.value)
              filter (where setting.key = 'business_hours_source'),
            'erp_settings'
          ),
        'businessHoursJson',
          coalesce(
            max(setting.value)
              filter (where setting.key = 'business_hours_json'),
            ''
          ),
        'googleBusinessHoursJson',
          coalesce(
            max(setting.value)
              filter (
                where setting.key = 'google_business_regular_hours'
              ),
            ''
          ),
        'updatedAt',
          max(setting.value)
            filter (where setting.key = 'business_hours_updated_at')
      )
      from public.website_settings setting
      where setting.tenant_id = portal.tenant_id
        and setting.key in (
          'business_hours_source',
          'business_hours_json',
          'google_business_regular_hours',
          'business_hours_updated_at'
        )
    ),
    'employee', jsonb_build_object(
      'id', employee.id,
      'employeeNumber', employee.employee_number,
      'firstName', employee.first_name,
      'lastName', employee.last_name,
      'fullName', trim(employee.first_name || ' ' || employee.last_name),
      'jobTitle', employee.job_title,
      'departmentName', department.name,
      'employmentType', employee.employment_type,
      'systemRole', employee.system_role,
      'photoUrl', employee.photo_url,
      'email', employee.email,
      'phone', employee.phone,
      'rut', employee.rut,
      'birthDate', employee.birth_date,
      'hireDate', employee.hire_date,
      'address', employee.address,
      'city', employee.city,
      'emergencyContactName', employee.emergency_contact_name,
      'emergencyContactPhone', employee.emergency_contact_phone,
      'status', employee.status
    ),
    'payroll', jsonb_build_object(
      'hourlyRate', coalesce(employee.hourly_rate, 0),
      'preferredPaymentMethod', employee.preferred_payment_method,
      'preferredPaymentMethodId', employee.preferred_payment_method_id,
      'preferredPaymentMethodName', payment_method.name
    ),
    'planningRoles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', planning_role.id,
        'code', planning_role.code,
        'name', planning_role.name,
        'color', planning_role.color,
        'isDefault', employee_role.is_default
      ) order by
        employee_role.is_default desc,
        planning_role.sort_order,
        planning_role.name
      )
      from public.employee_planning_roles employee_role
      join public.planning_roles planning_role
        on planning_role.id = employee_role.planning_role_id
      where employee_role.tenant_id = portal.tenant_id
        and employee_role.employee_id = portal.employee_id
        and planning_role.is_active is true
    ), '[]'::jsonb),
    'defaultShiftBlocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', shift_block.id,
        'dayOfWeek', shift_block.day_of_week,
        'startTime', shift_block.start_time,
        'endTime', shift_block.end_time,
        'timezone', shift_block.timezone,
        'planningRoleId', shift_block.planning_role_id,
        'planningRoleName', planning_role.name,
        'planningRoleColor', planning_role.color,
        'source', shift_block.source,
        'storeHoursValidated', shift_block.store_hours_validated,
        'outsideStoreHoursReason', shift_block.outside_store_hours_reason
      ) order by shift_block.day_of_week, shift_block.start_time)
      from public.employee_default_shift_blocks shift_block
      left join public.planning_roles planning_role
        on planning_role.id = shift_block.planning_role_id
      where shift_block.tenant_id = portal.tenant_id
        and shift_block.employee_id = portal.employee_id
        and shift_block.is_active is true
    ), '[]'::jsonb)
  )
  into context_value
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  join public.tenants tenant
    on tenant.id = portal.tenant_id
  left join public.departments department
    on department.id = employee.department_id
  left join public.payment_methods payment_method
    on payment_method.id = employee.preferred_payment_method_id
   and payment_method.tenant_id = employee.tenant_id
  where portal.auth_user_id = auth.uid()
    and portal.is_active is true
    and portal.must_reset_password is false
    and employee.status = 'active'
    and tenant.is_active is true
  limit 1;

  return context_value;
end;
$$;

create or replace function public.worker_portal_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select portal.tenant_id
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  join public.tenants tenant
    on tenant.id = portal.tenant_id
  where portal.auth_user_id = auth.uid()
    and portal.is_active is true
    and portal.must_reset_password is false
    and employee.status = 'active'
    and tenant.is_active is true
  limit 1
$$;

create or replace function public.worker_portal_employee_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select portal.employee_id
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  join public.tenants tenant
    on tenant.id = portal.tenant_id
  where portal.auth_user_id = auth.uid()
    and portal.is_active is true
    and portal.must_reset_password is false
    and employee.status = 'active'
    and tenant.is_active is true
  limit 1
$$;

create or replace function public.begin_worker_password_credential_issue(
  p_portal_account_id uuid,
  p_tenant_id uuid
)
returns timestamp with time zone
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  reset_required_at timestamp with time zone := clock_timestamp();
begin
  if p_portal_account_id is null or p_tenant_id is null then
    raise exception 'Worker portal account and tenant are required'
      using errcode = '22004';
  end if;

  update public.employee_portal_accounts portal
  set must_reset_password = true,
      password_reset_required_at = reset_required_at,
      password_credential_issued_at = null,
      password_reset_challenge_started_at = null,
      updated_at = now()
  where portal.id = p_portal_account_id
    and portal.tenant_id = p_tenant_id
    and portal.is_active is true;

  if not found then
    raise exception 'Active worker portal account not found'
      using errcode = 'P0002';
  end if;

  return reset_required_at;
end;
$$;

revoke all on function public.begin_worker_password_credential_issue(
  uuid,
  uuid
) from public, anon, authenticated, service_role;
grant execute on function public.begin_worker_password_credential_issue(
  uuid,
  uuid
) to service_role;

create or replace function public.finish_worker_password_credential_issue(
  p_portal_account_id uuid,
  p_tenant_id uuid,
  p_password_reset_required_at timestamp with time zone
)
returns timestamp with time zone
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  credential_issued_at timestamp with time zone;
begin
  if p_portal_account_id is null
     or p_tenant_id is null
     or p_password_reset_required_at is null then
    raise exception
      'Worker portal account, tenant, and reset version are required'
      using errcode = '22004';
  end if;

  credential_issued_at := greatest(
    clock_timestamp(),
    p_password_reset_required_at + interval '1 microsecond'
  );

  update public.employee_portal_accounts portal
  set password_credential_issued_at = credential_issued_at,
      password_reset_challenge_started_at = null,
      updated_at = now()
  where portal.id = p_portal_account_id
    and portal.tenant_id = p_tenant_id
    and portal.is_active is true
    and portal.must_reset_password is true
    and portal.password_reset_required_at =
      p_password_reset_required_at
    and portal.password_credential_issued_at is null
  returning portal.password_credential_issued_at
  into credential_issued_at;

  if not found then
    raise exception 'Worker credential issuance state changed'
      using errcode = '40001';
  end if;

  return credential_issued_at;
end;
$$;

revoke all on function public.finish_worker_password_credential_issue(
  uuid,
  uuid,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.finish_worker_password_credential_issue(
  uuid,
  uuid,
  timestamp with time zone
) to service_role;

create or replace function public.begin_my_worker_password_reset()
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  auth_user_id_value uuid := auth.uid();
  portal_id_value uuid;
  credential_issued_at timestamp with time zone;
  challenge_started_at timestamp with time zone;
begin
  if auth_user_id_value is null then
    raise exception 'Authenticated worker required'
      using errcode = '42501';
  end if;

  select
    portal.id,
    portal.password_credential_issued_at,
    portal.password_reset_challenge_started_at
  into
    portal_id_value,
    credential_issued_at,
    challenge_started_at
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  join public.tenants tenant
    on tenant.id = portal.tenant_id
  where portal.auth_user_id = auth_user_id_value
    and portal.is_active is true
    and portal.must_reset_password is true
    and portal.password_reset_required_at is not null
    and portal.password_credential_issued_at is not null
    and employee.status = 'active'
    and tenant.is_active is true
  limit 1
  for update of portal;

  if not found then
    raise exception 'Active worker reset requirement not found'
      using errcode = '42501';
  end if;

  if challenge_started_at is null then
    update public.employee_portal_accounts
    set password_reset_challenge_started_at = greatest(
          clock_timestamp(),
          credential_issued_at + interval '1 microsecond'
        ),
        updated_at = now()
    where id = portal_id_value;
  end if;

  return true;
end;
$$;

revoke all on function public.begin_my_worker_password_reset()
  from public, anon, authenticated, service_role;
grant execute on function public.begin_my_worker_password_reset()
  to authenticated;

create or replace function public.complete_my_worker_password_reset()
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  auth_user_id_value uuid := auth.uid();
  portal_id_value uuid;
  reset_required boolean;
  required_at timestamp with time zone;
  challenge_started_at timestamp with time zone;
begin
  if auth_user_id_value is null then
    raise exception 'Authenticated worker required'
      using errcode = '42501';
  end if;

  select
    portal.id,
    portal.must_reset_password,
    portal.password_reset_required_at,
    portal.password_reset_challenge_started_at
  into
    portal_id_value,
    reset_required,
    required_at,
    challenge_started_at
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  join public.tenants tenant
    on tenant.id = portal.tenant_id
  where portal.auth_user_id = auth_user_id_value
    and portal.is_active is true
    and employee.status = 'active'
    and tenant.is_active is true
  limit 1
  for update of portal;

  if not found then
    raise exception 'Active worker account required'
      using errcode = '42501';
  end if;

  if reset_required is false then
    return true;
  end if;

  if required_at is null or challenge_started_at is null then
    raise exception 'Password reset challenge required'
      using errcode = '42501';
  end if;

  if not exists (
       select 1
       from auth.audit_log_entries audit
       where audit.created_at > required_at
         and audit.created_at > challenge_started_at
         -- Admin password assignment may name this worker as user_id, but only
         -- a self-service password change names the worker as the actor.
         and coalesce(
           audit.payload->>'actor_id',
           audit.payload->'traits'->>'actor_id'
         ) = auth_user_id_value::text
         and (
           audit.payload->>'action' = 'user_updated_password'
           or audit.payload->'traits'->>'action' =
             'user_updated_password'
         )
     ) then
    raise exception 'Verified password update required'
      using errcode = '42501';
  end if;

  update public.employee_portal_accounts
  set must_reset_password = false,
      password_reset_challenge_started_at = null,
      updated_at = now()
  where id = portal_id_value
    and must_reset_password is true;

  return true;
end;
$$;

revoke all on function public.complete_my_worker_password_reset()
  from public, anon, authenticated, service_role;
grant execute on function public.complete_my_worker_password_reset()
  to authenticated;

-- Worker helpers remain callable only by signed-in workers. The explicit
-- search_path prevents object-shadowing while preserving their current bodies.
alter function public.worker_portal_tenant_id()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.worker_portal_tenant_id()
  from public, anon, authenticated, service_role;
grant execute on function public.worker_portal_tenant_id()
  to authenticated;

alter function public.worker_portal_employee_id()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.worker_portal_employee_id()
  from public, anon, authenticated, service_role;
grant execute on function public.worker_portal_employee_id()
  to authenticated;

alter function public.get_my_worker_portal_context()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.get_my_worker_portal_context()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_worker_portal_context()
  to authenticated;

alter function public.resolve_worker_login(text, text)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.resolve_worker_login(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.resolve_worker_login(text, text)
  to service_role;

alter function public.get_my_worker_shifts(
  timestamp with time zone,
  timestamp with time zone
) set search_path = pg_catalog, public, pg_temp;
revoke all on function public.get_my_worker_shifts(
  timestamp with time zone,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.get_my_worker_shifts(
  timestamp with time zone,
  timestamp with time zone
) to authenticated;

alter function public.get_worker_portal_planning_calendar(
  timestamp with time zone,
  timestamp with time zone
) set search_path = pg_catalog, public, pg_temp;
revoke all on function public.get_worker_portal_planning_calendar(
  timestamp with time zone,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.get_worker_portal_planning_calendar(
  timestamp with time zone,
  timestamp with time zone
) to authenticated;

alter function public.update_my_worker_shift(
  uuid,
  timestamp with time zone,
  timestamp with time zone
) set search_path = pg_catalog, public, pg_temp;
revoke all on function public.update_my_worker_shift(
  uuid,
  timestamp with time zone,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.update_my_worker_shift(
  uuid,
  timestamp with time zone,
  timestamp with time zone
) to authenticated;

alter function public.get_my_worker_attendances(
  timestamp with time zone,
  timestamp with time zone
) set search_path = pg_catalog, public, pg_temp;
revoke all on function public.get_my_worker_attendances(
  timestamp with time zone,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.get_my_worker_attendances(
  timestamp with time zone,
  timestamp with time zone
) to authenticated;

alter function public.get_my_worker_payroll_for_period(date, date)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.get_my_worker_payroll_for_period(date, date)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_worker_payroll_for_period(date, date)
  to authenticated;

alter function public.validate_shift_planning_tenant_consistency()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.validate_shift_planning_tenant_consistency()
  from public, anon, authenticated, service_role;

-- Tenant bootstrap helpers execute behind the tenants INSERT trigger or from a
-- trusted service operation; none is a public mutation RPC.
alter function public.handle_new_tenant()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.handle_new_tenant()
  from public, anon, authenticated, service_role;
grant execute on function public.handle_new_tenant()
  to service_role;

alter function public.handle_new_tenant_digital_expense_classification()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.handle_new_tenant_digital_expense_classification()
  from public, anon, authenticated, service_role;
grant execute on function public.handle_new_tenant_digital_expense_classification()
  to service_role;

alter function public.seed_chart_of_accounts(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_chart_of_accounts(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_chart_of_accounts(uuid)
  to service_role;

alter function public.seed_payment_methods_for_tenant(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_payment_methods_for_tenant(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_payment_methods_for_tenant(uuid)
  to service_role;

alter function public.seed_job_statuses_for_tenant(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_job_statuses_for_tenant(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_job_statuses_for_tenant(uuid)
  to service_role;

alter function public.seed_company_settings(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_company_settings(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_company_settings(uuid)
  to service_role;

alter function public.seed_website_settings(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_website_settings(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_website_settings(uuid)
  to service_role;

alter function public.seed_website_pages(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_website_pages(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_website_pages(uuid)
  to service_role;

alter function public.seed_job_roles_for_tenant(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_job_roles_for_tenant(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_job_roles_for_tenant(uuid)
  to service_role;

alter function public.seed_job_subjects_for_tenant(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_job_subjects_for_tenant(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_job_subjects_for_tenant(uuid)
  to service_role;

alter function public.seed_digital_services_expense_classification(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.seed_digital_services_expense_classification(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_digital_services_expense_classification(uuid)
  to service_role;

-- Tenant authority is data, not a caller-supplied UUID. Backup/restore reads
-- or replaces nearly the entire tenant dataset, so generic settings-edit
-- authority is insufficient: only an active DB-backed admin may invoke it.
create or replace function public.can_manage_tenant_backups(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and profile.role = 'admin'
  )
$$;

revoke all on function public.can_manage_tenant_backups(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_tenant_backups(uuid)
  to authenticated, service_role;

-- Preserve the Flutter RPC signatures while moving the legacy broad bodies
-- behind service-only entry points. The wrappers prove tenant ownership before
-- invoking any SECURITY DEFINER data access.
do $$
begin
  if to_regprocedure(
    'public.create_backup_internal(uuid,text,text,text)'
  ) is null then
    if to_regprocedure(
      'public.create_backup(uuid,text,text,text)'
    ) is null then
      raise exception 'Missing create_backup RPC';
    end if;
    alter function public.create_backup(uuid, text, text, text)
      rename to create_backup_internal;
  end if;

  if to_regprocedure(
    'public.restore_backup_internal(uuid,uuid)'
  ) is null then
    if to_regprocedure('public.restore_backup(uuid,uuid)') is null then
      raise exception 'Missing restore_backup RPC';
    end if;
    alter function public.restore_backup(uuid, uuid)
      rename to restore_backup_internal;
  end if;

  if to_regprocedure(
    'public.get_backup_summary_internal(uuid)'
  ) is null then
    if to_regprocedure('public.get_backup_summary(uuid)') is null then
      raise exception 'Missing get_backup_summary RPC';
    end if;
    alter function public.get_backup_summary(uuid)
      rename to get_backup_summary_internal;
  end if;

  if to_regprocedure(
    'public.cleanup_old_backups_internal(uuid)'
  ) is null then
    if to_regprocedure('public.cleanup_old_backups(uuid)') is null then
      raise exception 'Missing cleanup_old_backups RPC';
    end if;
    alter function public.cleanup_old_backups(uuid)
      rename to cleanup_old_backups_internal;
  end if;
end
$$;

alter function public.create_backup_internal(uuid, text, text, text)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.restore_backup_internal(uuid, uuid)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.get_backup_summary_internal(uuid)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.cleanup_old_backups_internal(uuid)
  set search_path = pg_catalog, public, extensions, pg_temp;

revoke all on function public.create_backup_internal(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_internal(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_backup_summary_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.cleanup_old_backups_internal(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_backup_internal(uuid, text, text, text)
  to service_role;
grant execute on function public.restore_backup_internal(uuid, uuid)
  to service_role;
grant execute on function public.get_backup_summary_internal(uuid)
  to service_role;
grant execute on function public.cleanup_old_backups_internal(uuid)
  to service_role;

create or replace function public.create_backup(
  p_tenant_id uuid,
  p_backup_name text,
  p_backup_type text default 'manual',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  return public.create_backup_internal(
    p_tenant_id,
    p_backup_name,
    p_backup_type,
    p_notes
  );
end;
$$;

create or replace function public.restore_backup(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.database_backups backup
    where backup.id = p_backup_id
      and backup.tenant_id = p_tenant_id
      and backup.status = 'completed'
  ) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  return public.restore_backup_internal(p_backup_id, p_tenant_id);
end;
$$;

create or replace function public.get_backup_summary(p_backup_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid;
begin
  select backup.tenant_id
  into tenant_id_value
  from public.database_backups backup
  join public.tenants tenant
    on tenant.id = backup.tenant_id
   and tenant.is_active is true
  where backup.id = p_backup_id;

  if tenant_id_value is null
     or (
       auth.role() is distinct from 'service_role'
       and not public.can_manage_tenant_backups(tenant_id_value)
     ) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  return public.get_backup_summary_internal(p_backup_id);
end;
$$;

create or replace function public.cleanup_old_backups(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  return public.cleanup_old_backups_internal(p_tenant_id);
end;
$$;

revoke all on function public.create_backup(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_backup_summary(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.cleanup_old_backups(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_backup(uuid, text, text, text)
  to authenticated, service_role;
grant execute on function public.restore_backup(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.get_backup_summary(uuid)
  to authenticated, service_role;
grant execute on function public.cleanup_old_backups(uuid)
  to authenticated, service_role;

create or replace function public.run_due_backup_schedules(
  p_now timestamp with time zone default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  schedule_row record;
  backup_result jsonb;
  results_value jsonb := '[]'::jsonb;
  created_count integer := 0;
  failed_count integer := 0;
  next_run_value timestamp with time zone;
begin
  for schedule_row in
    select schedule.*
    from public.backup_schedules schedule
    where schedule.enabled is true
      and coalesce(schedule.next_run_at, p_now) <= p_now
    order by schedule.next_run_at nulls first
    limit 50
  loop
    begin
      backup_result := public.create_backup_internal(
        schedule_row.tenant_id,
        'Respaldo automático '
          || to_char(p_now at time zone 'UTC', 'YYYY-MM-DD HH24:MI')
          || ' UTC',
        'scheduled',
        'Respaldo automático completo creado por el programador del servidor.'
      );

      if coalesce((backup_result->>'success')::boolean, false) then
        created_count := created_count + 1;
      else
        failed_count := failed_count + 1;
      end if;

      if schedule_row.auto_delete_old then
        perform public.cleanup_old_backups_internal(schedule_row.tenant_id);
      end if;

      next_run_value := public.calculate_next_backup_run(
        schedule_row.frequency,
        schedule_row.time_of_day,
        schedule_row.day_of_week,
        schedule_row.day_of_month,
        p_now
      );

      update public.backup_schedules schedule
      set last_run_at = p_now,
          next_run_at = next_run_value,
          updated_at = now()
      where schedule.id = schedule_row.id;

      results_value := results_value || jsonb_build_array(
        jsonb_build_object(
          'tenant_id', schedule_row.tenant_id,
          'schedule_id', schedule_row.id,
          'next_run_at', next_run_value,
          'result', backup_result
        )
      );
    exception
      when others then
        failed_count := failed_count + 1;
        next_run_value := public.calculate_next_backup_run(
          schedule_row.frequency,
          schedule_row.time_of_day,
          schedule_row.day_of_week,
          schedule_row.day_of_month,
          p_now
        );

        update public.backup_schedules schedule
        set last_run_at = p_now,
            next_run_at = next_run_value,
            updated_at = now()
        where schedule.id = schedule_row.id;

        results_value := results_value || jsonb_build_array(
          jsonb_build_object(
            'tenant_id', schedule_row.tenant_id,
            'schedule_id', schedule_row.id,
            'next_run_at', next_run_value,
            'error', sqlerrm
          )
        );
    end;
  end loop;

  return jsonb_build_object(
    'success', true,
    'created_count', created_count,
    'failed_count', failed_count,
    'checked_at', p_now,
    'results', results_value
  );
end;
$$;

revoke all on function public.run_due_backup_schedules(timestamp with time zone)
  from public, anon, authenticated, service_role;
grant execute on function public.run_due_backup_schedules(timestamp with time zone)
  to service_role;

-- Website snapshots are also settings administration. Keep the established
-- Flutter RPCs while isolating the broad legacy bodies behind service-only
-- functions.
do $$
begin
  if to_regprocedure(
    'public.create_website_backup_internal(text,text,boolean)'
  ) is null then
    if to_regprocedure(
      'public.create_website_backup(text,text,boolean)'
    ) is null then
      raise exception 'Missing create_website_backup RPC';
    end if;
    alter function public.create_website_backup(text, text, boolean)
      rename to create_website_backup_internal;
  end if;

  if to_regprocedure(
    'public.restore_website_backup_internal(uuid,boolean)'
  ) is null then
    if to_regprocedure(
      'public.restore_website_backup(uuid,boolean)'
    ) is null then
      raise exception 'Missing restore_website_backup RPC';
    end if;
    alter function public.restore_website_backup(uuid, boolean)
      rename to restore_website_backup_internal;
  end if;
end
$$;

alter function public.create_website_backup_internal(text, text, boolean)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.restore_website_backup_internal(uuid, boolean)
  set search_path = pg_catalog, public, extensions, pg_temp;

revoke all on function
  public.create_website_backup_internal(text, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function
  public.restore_website_backup_internal(uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function
  public.create_website_backup_internal(text, text, boolean)
  to service_role;
grant execute on function
  public.restore_website_backup_internal(uuid, boolean)
  to service_role;

create or replace function public.create_website_backup(
  p_name text,
  p_description text default null,
  p_is_auto boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_backups(tenant_id_value) then
    raise exception 'Website backup access denied'
      using errcode = '42501';
  end if;

  return public.create_website_backup_internal(
    p_name,
    p_description,
    p_is_auto
  );
end;
$$;

create or replace function public.restore_website_backup(
  p_backup_id uuid,
  p_create_safety_backup boolean default true
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_backups(tenant_id_value)
     or not exists (
       select 1
       from public.website_backups backup
       where backup.id = p_backup_id
         and backup.tenant_id = tenant_id_value
     ) then
    raise exception 'Website backup access denied'
      using errcode = '42501';
  end if;

  return public.restore_website_backup_internal(
    p_backup_id,
    p_create_safety_backup
  );
end;
$$;

revoke all on function public.create_website_backup(text, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_website_backup(uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.create_website_backup(text, text, boolean)
  to authenticated;
grant execute on function public.restore_website_backup(uuid, boolean)
  to authenticated;

-- The client-facing account helper derives its tenant from the active DB
-- profile and requires accounting authority. The explicit-tenant overload is
-- reserved for trusted triggers and service maintenance.
do $$
begin
  if to_regprocedure(
    'public.ensure_account_internal(text,text,text,text,text,text)'
  ) is null then
    if to_regprocedure(
      'public.ensure_account(text,text,text,text,text,text)'
    ) is null then
      raise exception 'Missing ensure_account RPC';
    end if;
    alter function public.ensure_account(text, text, text, text, text, text)
      rename to ensure_account_internal;
  end if;
end
$$;

alter function
  public.ensure_account_internal(text, text, text, text, text, text)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function
  public.ensure_account(uuid, text, text, text, text, text, text)
  set search_path = pg_catalog, public, extensions, pg_temp;

revoke all on function
  public.ensure_account_internal(text, text, text, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function
  public.ensure_account(uuid, text, text, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function
  public.ensure_account_internal(text, text, text, text, text, text)
  to service_role;
grant execute on function
  public.ensure_account(uuid, text, text, text, text, text, text)
  to service_role;

create or replace function public.ensure_account(
  p_code text,
  p_name text,
  p_type text,
  p_category text,
  p_description text default null,
  p_parent_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or tenant_id_value is null
     or not public.can_manage_tenant_accounting(tenant_id_value) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  return public.ensure_account_internal(
    p_code,
    p_name,
    p_type,
    p_category,
    p_description,
    p_parent_code
  );
end;
$$;

revoke all on function
  public.ensure_account(text, text, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function
  public.ensure_account(text, text, text, text, text, text)
  to authenticated;

-- Keep the invoice safety-net RPC used by POS and invoice flows, but bind the
-- invoice UUID to the caller's active accounting tenant before invoking the
-- original journal body.
do $$
begin
  if to_regprocedure(
    'public.ensure_sales_invoice_journal_entry_internal(uuid)'
  ) is null then
    if to_regprocedure(
      'public.ensure_sales_invoice_journal_entry(uuid)'
    ) is null then
      raise exception 'Missing ensure_sales_invoice_journal_entry RPC';
    end if;
    alter function public.ensure_sales_invoice_journal_entry(uuid)
      rename to ensure_sales_invoice_journal_entry_internal;
  end if;
end
$$;

alter function public.ensure_sales_invoice_journal_entry_internal(uuid)
  set search_path = pg_catalog, public, extensions, pg_temp;
revoke all on function
  public.ensure_sales_invoice_journal_entry_internal(uuid)
  from public, anon, authenticated, service_role;
grant execute on function
  public.ensure_sales_invoice_journal_entry_internal(uuid)
  to service_role;

create or replace function public.ensure_sales_invoice_journal_entry(
  p_invoice_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid;
begin
  select invoice.tenant_id
  into tenant_id_value
  from public.sales_invoices invoice
  join public.tenants tenant
    on tenant.id = invoice.tenant_id
   and tenant.is_active is true
  where invoice.id = p_invoice_id;

  if auth.role() is distinct from 'service_role'
     and (
       tenant_id_value is null
       or tenant_id_value is distinct from public.user_tenant_id()
       or not public.can_manage_tenant_accounting(tenant_id_value)
     ) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  if tenant_id_value is null then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  perform public.ensure_sales_invoice_journal_entry_internal(p_invoice_id);
end;
$$;

revoke all on function public.ensure_sales_invoice_journal_entry(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_sales_invoice_journal_entry(uuid)
  to authenticated, service_role;

-- F29 generation is an accounting mutation. Preserve its client contract while
-- enforcing active, DB-backed tenant authority.
do $$
begin
  if to_regprocedure(
    'public.generate_f29_from_accounting_internal(uuid,integer,integer)'
  ) is null then
    if to_regprocedure(
      'public.generate_f29_from_accounting(uuid,integer,integer)'
    ) is null then
      raise exception 'Missing generate_f29_from_accounting RPC';
    end if;
    alter function
      public.generate_f29_from_accounting(uuid, integer, integer)
      rename to generate_f29_from_accounting_internal;
  end if;
end
$$;

alter function
  public.generate_f29_from_accounting_internal(uuid, integer, integer)
  set search_path = pg_catalog, public, extensions, pg_temp;
revoke all on function
  public.generate_f29_from_accounting_internal(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function
  public.generate_f29_from_accounting_internal(uuid, integer, integer)
  to service_role;

create or replace function public.generate_f29_from_accounting(
  p_tenant_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
begin
  if auth.role() is distinct from 'service_role'
     and (
       p_tenant_id is distinct from public.user_tenant_id()
       or not public.can_manage_tenant_accounting(p_tenant_id)
     ) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  return public.generate_f29_from_accounting_internal(
    p_tenant_id,
    p_year,
    p_month
  );
end;
$$;

revoke all on function
  public.generate_f29_from_accounting(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function
  public.generate_f29_from_accounting(uuid, integer, integer)
  to authenticated, service_role;

-- HR summary RPCs used by Flutter must never aggregate a different tenant.
create or replace function public.get_checked_in_employees()
returns table (
  attendance_id uuid,
  employee_id uuid,
  employee_name text,
  check_in timestamp with time zone,
  hours_worked numeric
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  return query
  select
    attendance.id,
    employee.id,
    trim(employee.first_name || ' ' || employee.last_name),
    attendance.check_in,
    round(
      extract(epoch from (now() - attendance.check_in)) / 3600.0,
      2
    )
  from public.attendances attendance
  join public.employees employee
    on employee.id = attendance.employee_id
   and employee.tenant_id = attendance.tenant_id
  where attendance.tenant_id = tenant_id_value
    and attendance.status = 'ongoing'
    and attendance.check_out is null
  order by attendance.check_in;
end;
$$;

create or replace function public.get_attendance_summary(
  p_employee_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (
  total_days integer,
  total_hours numeric,
  total_overtime numeric,
  average_hours numeric,
  late_arrivals integer,
  early_departures integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid attendance date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value)
     or not exists (
       select 1
       from public.employees employee
       where employee.id = p_employee_id
         and employee.tenant_id = tenant_id_value
     ) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  return query
  select
    count(distinct date(attendance.check_in))::integer,
    coalesce(sum(attendance.worked_hours), 0),
    coalesce(sum(attendance.overtime_hours), 0),
    coalesce(avg(attendance.worked_hours), 0),
    count(*) filter (
      where extract(hour from attendance.check_in) > 9
    )::integer,
    count(*) filter (
      where extract(hour from attendance.check_out) < 18
    )::integer
  from public.attendances attendance
  where attendance.tenant_id = tenant_id_value
    and attendance.employee_id = p_employee_id
    and attendance.status in ('completed', 'approved')
    and date(attendance.check_in) between p_start_date and p_end_date;
end;
$$;

create or replace function public.get_employee_hours_summary(
  p_employee_id uuid,
  p_start_date date,
  p_end_date date
)
returns json
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
  result_value json;
  expected_start constant time := '09:00:00';
  expected_end constant time := '18:00:00';
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid attendance date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value)
     or not exists (
       select 1
       from public.employees employee
       where employee.id = p_employee_id
         and employee.tenant_id = tenant_id_value
     ) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  select json_build_object(
    'total_days_worked', count(*),
    'total_hours', coalesce(sum(attendance.worked_hours), 0),
    'total_overtime', coalesce(sum(attendance.overtime_hours), 0),
    'total_break_minutes', coalesce(sum(attendance.break_minutes), 0),
    'average_hours_per_day',
      round(coalesce(avg(attendance.worked_hours), 0)::numeric, 2),
    'earliest_check_in', min(attendance.check_in::time),
    'latest_check_out', max(attendance.check_out::time),
    'days_with_overtime', count(*) filter (
      where coalesce(attendance.overtime_hours, 0) > 0
    ),
    'late_arrivals', count(*) filter (
      where attendance.check_in::time >
        expected_start + interval '30 minutes'
    ),
    'early_departures', count(*) filter (
      where attendance.check_out is not null
        and attendance.check_out::time <
          expected_end - interval '30 minutes'
    ),
    'perfect_attendance_days', count(*) filter (
      where coalesce(attendance.worked_hours, 0) >= 8
    ),
    'short_days', count(*) filter (
      where coalesce(attendance.worked_hours, 0) < 8
        and coalesce(attendance.worked_hours, 0) > 0
    )
  )
  into result_value
  from public.attendances attendance
  where attendance.tenant_id = tenant_id_value
    and attendance.employee_id = p_employee_id
    and attendance.check_in >= p_start_date
    and attendance.check_in < p_end_date + interval '1 day'
    and attendance.status in ('completed', 'approved');

  return coalesce(result_value, '{}'::json);
end;
$$;

create or replace function public.get_attendance_summary_for_period(
  p_start_date date,
  p_end_date date
)
returns table (
  employee_id uuid,
  employee_name text,
  total_hours numeric,
  total_days integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid attendance date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  return query
  select
    employee.id,
    trim(employee.first_name || ' ' || employee.last_name),
    coalesce(sum(attendance.worked_hours), 0)::numeric,
    count(distinct date(attendance.check_in))::integer
  from public.employees employee
  left join public.attendances attendance
    on attendance.employee_id = employee.id
   and attendance.tenant_id = employee.tenant_id
   and attendance.status in ('completed', 'approved')
   and date(attendance.check_in) between p_start_date and p_end_date
  where employee.tenant_id = tenant_id_value
    and employee.status = 'active'
  group by employee.id, employee.first_name, employee.last_name
  order by trim(employee.first_name || ' ' || employee.last_name);
end;
$$;

revoke all on function public.get_checked_in_employees()
  from public, anon, authenticated, service_role;
revoke all on function
  public.get_attendance_summary(uuid, date, date)
  from public, anon, authenticated, service_role;
revoke all on function
  public.get_employee_hours_summary(uuid, date, date)
  from public, anon, authenticated, service_role;
revoke all on function
  public.get_attendance_summary_for_period(date, date)
  from public, anon, authenticated, service_role;
grant execute on function public.get_checked_in_employees()
  to authenticated;
grant execute on function public.get_attendance_summary(uuid, date, date)
  to authenticated;
grant execute on function
  public.get_employee_hours_summary(uuid, date, date)
  to authenticated;
grant execute on function
  public.get_attendance_summary_for_period(date, date)
  to authenticated;

-- Keep the established aggregate RPC signatures and idempotency receipts, but
-- require an active DB-backed tenant before entering their legacy bodies. The
-- bodies remain service-only so a suspended profile cannot bypass the wrapper.
do $$
begin
  if to_regprocedure(
    'public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'
  ) is null then
    if to_regprocedure(
      'public.save_bike_aggregate(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'
    ) is null then
      raise exception 'Missing save_bike_aggregate RPC';
    end if;
    alter function public.save_bike_aggregate(
      text,
      uuid,
      uuid,
      timestamp with time zone,
      timestamp with time zone,
      jsonb,
      jsonb
    ) rename to save_bike_aggregate_internal;
  end if;

  if to_regprocedure(
    'public.get_bike_aggregate_internal(uuid)'
  ) is null then
    if to_regprocedure('public.get_bike_aggregate(uuid)') is null then
      raise exception 'Missing get_bike_aggregate RPC';
    end if;
    alter function public.get_bike_aggregate(uuid)
      rename to get_bike_aggregate_internal;
  end if;

  if to_regprocedure(
    'public.get_bike_aggregate_save_operation_internal(text)'
  ) is null then
    if to_regprocedure(
      'public.get_bike_aggregate_save_operation(text)'
    ) is null then
      raise exception 'Missing get_bike_aggregate_save_operation RPC';
    end if;
    alter function public.get_bike_aggregate_save_operation(text)
      rename to get_bike_aggregate_save_operation_internal;
  end if;

  if to_regprocedure(
    'public.save_expense_aggregate_internal(text,uuid,timestamptz,jsonb)'
  ) is null then
    if to_regprocedure(
      'public.save_expense_aggregate(text,uuid,timestamptz,jsonb)'
    ) is null then
      raise exception 'Missing save_expense_aggregate RPC';
    end if;
    alter function public.save_expense_aggregate(
      text,
      uuid,
      timestamp with time zone,
      jsonb
    ) rename to save_expense_aggregate_internal;
  end if;

  if to_regprocedure(
    'public.get_expense_aggregate_save_operation_internal(text)'
  ) is null then
    if to_regprocedure(
      'public.get_expense_aggregate_save_operation(text)'
    ) is null then
      raise exception 'Missing get_expense_aggregate_save_operation RPC';
    end if;
    alter function public.get_expense_aggregate_save_operation(text)
      rename to get_expense_aggregate_save_operation_internal;
  end if;
end
$$;

alter function public.save_bike_aggregate_internal(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  timestamp with time zone,
  jsonb,
  jsonb
) set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.get_bike_aggregate_internal(uuid)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.get_bike_aggregate_save_operation_internal(text)
  set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.save_expense_aggregate_internal(
  text,
  uuid,
  timestamp with time zone,
  jsonb
) set search_path = pg_catalog, public, extensions, pg_temp;
alter function public.get_expense_aggregate_save_operation_internal(text)
  set search_path = pg_catalog, public, extensions, pg_temp;

revoke all on function public.save_bike_aggregate_internal(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  timestamp with time zone,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.get_bike_aggregate_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.get_bike_aggregate_save_operation_internal(text)
  from public, anon, authenticated, service_role;
revoke all on function public.save_expense_aggregate_internal(
  text,
  uuid,
  timestamp with time zone,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function
  public.get_expense_aggregate_save_operation_internal(text)
  from public, anon, authenticated, service_role;

grant execute on function public.save_bike_aggregate_internal(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  timestamp with time zone,
  jsonb,
  jsonb
) to service_role;
grant execute on function public.get_bike_aggregate_internal(uuid)
  to service_role;
grant execute on function
  public.get_bike_aggregate_save_operation_internal(text)
  to service_role;
grant execute on function public.save_expense_aggregate_internal(
  text,
  uuid,
  timestamp with time zone,
  jsonb
) to service_role;
grant execute on function
  public.get_expense_aggregate_save_operation_internal(text)
  to service_role;

create or replace function public.save_bike_aggregate(
  p_operation_key text,
  p_bike_id uuid,
  p_customer_id uuid,
  p_expected_bike_updated_at timestamp with time zone,
  p_expected_profile_updated_at timestamp with time zone,
  p_bike_payload jsonb,
  p_profile_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Tenant aggregate access denied'
      using errcode = '42501';
  end if;

  return public.save_bike_aggregate_internal(
    p_operation_key,
    p_bike_id,
    p_customer_id,
    p_expected_bike_updated_at,
    p_expected_profile_updated_at,
    p_bike_payload,
    p_profile_payload
  );
end;
$$;

create or replace function public.get_bike_aggregate(p_bike_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Tenant aggregate access denied'
      using errcode = '42501';
  end if;

  return public.get_bike_aggregate_internal(p_bike_id);
end;
$$;

create or replace function public.get_bike_aggregate_save_operation(
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Tenant aggregate access denied'
      using errcode = '42501';
  end if;

  return public.get_bike_aggregate_save_operation_internal(p_operation_key);
end;
$$;

create or replace function public.save_expense_aggregate(
  p_operation_key text,
  p_expense_id uuid,
  p_expected_updated_at timestamp with time zone,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Tenant aggregate access denied'
      using errcode = '42501';
  end if;

  return public.save_expense_aggregate_internal(
    p_operation_key,
    p_expense_id,
    p_expected_updated_at,
    p_payload
  );
end;
$$;

create or replace function public.get_expense_aggregate_save_operation(
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or tenant_id_value is null
     or not public.is_active_tenant_member(tenant_id_value) then
    raise exception 'Tenant aggregate access denied'
      using errcode = '42501';
  end if;

  return public.get_expense_aggregate_save_operation_internal(
    p_operation_key
  );
end;
$$;

revoke all on function public.save_bike_aggregate(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  timestamp with time zone,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.get_bike_aggregate(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_bike_aggregate_save_operation(text)
  from public, anon, authenticated, service_role;
revoke all on function public.save_expense_aggregate(
  text,
  uuid,
  timestamp with time zone,
  jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.get_expense_aggregate_save_operation(text)
  from public, anon, authenticated, service_role;

grant execute on function public.save_bike_aggregate(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  timestamp with time zone,
  jsonb,
  jsonb
) to authenticated;
grant execute on function public.get_bike_aggregate(uuid)
  to authenticated;
grant execute on function public.get_bike_aggregate_save_operation(text)
  to authenticated;
grant execute on function public.save_expense_aggregate(
  text,
  uuid,
  timestamp with time zone,
  jsonb
) to authenticated;
grant execute on function public.get_expense_aggregate_save_operation(text)
  to authenticated;

-- Exact legacy maintenance helpers have no current client or policy contract.
-- Remove inherited authenticated execution and pin a safe lookup path.
do $$
declare
  signature text;
  routine_oid regprocedure;
begin
  foreach signature in array array[
    'public.backfill_stock_at_receipt_for_received_items()',
    'public.migrate_job_statuses()',
    'public.notify_new_email(uuid,text,text,jsonb)',
    'public.is_conversation_participant(uuid)',
    'public.ensure_expense_category(uuid,text,text,uuid)',
    'public.log_mechanic_job_timeline(uuid,text,text,text,text)',
    'public.generate_expense_number()',
    'public.get_account_balance(uuid,timestamptz,timestamptz)',
    'public.get_balances_by_type(text,timestamptz,timestamptz)',
    'public.get_balances_by_category(text,timestamptz,timestamptz)',
    'public.get_cumulative_balance(uuid,timestamptz)',
    'public.get_cumulative_balances_by_type(text,timestamptz)',
    'public.get_expense_category_name_for_account(text,text)'
  ]
  loop
    routine_oid := to_regprocedure(signature);
    if routine_oid is null then
      raise exception 'Missing service-only routine: %', signature;
    end if;

    execute format(
      'alter function %s set search_path = pg_catalog, public, extensions, pg_temp',
      routine_oid
    );
    execute format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      routine_oid
    );
    execute format(
      'grant execute on function %s to service_role',
      routine_oid
    );
  end loop;
end
$$;

-- mechanic_jobs.job_number invokes this as a column DEFAULT during direct
-- authenticated inserts. Keep that established contract, but remove anonymous
-- execution and pin the lookup path.
alter function public.generate_mechanic_job_number()
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.generate_mechanic_job_number()
  from public, anon, authenticated, service_role;
grant execute on function public.generate_mechanic_job_number()
  to authenticated, service_role;

-- Wheel compatibility is an ERP-only tenant workflow, not a storefront RPC.
-- Remove inherited PUBLIC execution and pin its lookup path.
alter function public.find_compatible_hubs(uuid, uuid, numeric, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.find_compatible_spokes(uuid, numeric, numeric)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function
  public.find_compatible_hubs(uuid, uuid, numeric, text)
  from public, anon, authenticated, service_role;
revoke all on function public.find_compatible_spokes(uuid, numeric, numeric)
  from public, anon, authenticated, service_role;
grant execute on function
  public.find_compatible_hubs(uuid, uuid, numeric, text)
  to authenticated, service_role;
grant execute on function public.find_compatible_spokes(uuid, numeric, numeric)
  to authenticated, service_role;

-- Production still exposes this legacy storefront bootstrap RPC. Recreate it
-- in the canonical snapshot with an active-tenant guard and an explicit safe
-- settings projection so provider credentials can never reach public clients.
create or replace function public.website_setting_is_sensitive(p_key text)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select lower(btrim(coalesce(p_key, ''))) ~
    '(access[_-]?token|refresh[_-]?token|secret|password|private|credential|api[_-]?key)'
$$;

revoke all on function public.website_setting_is_sensitive(text)
  from public, anon, authenticated, service_role;
grant execute on function public.website_setting_is_sensitive(text)
  to anon, authenticated, service_role;

create or replace function public.get_public_store_data(p_tenant_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  settings_value json;
  blocks_value json;
  home_page_id_value uuid;
begin
  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    return json_build_object(
      'settings', '{}'::json,
      'blocks', '[]'::json,
      'home_page_id', null
    );
  end if;

  select page.id
  into home_page_id_value
  from public.website_pages page
  where page.tenant_id = p_tenant_id
    and page.is_home is true
    and page.is_published is true
  order by page.created_at, page.id
  limit 1;

  if home_page_id_value is null then
    select page.id
    into home_page_id_value
    from public.website_pages page
    where page.tenant_id = p_tenant_id
      and page.is_published is true
    order by page.created_at, page.id
    limit 1;
  end if;

  select coalesce(
    json_object_agg(setting.key, setting.value),
    '{}'::json
  )
  into settings_value
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and not public.website_setting_is_sensitive(setting.key);

  select coalesce(
    json_agg(
      json_build_object(
        'id', block.id,
        'block_type', block.block_type,
        'block_data', block.block_data,
        'is_visible', block.is_visible,
        'order_index', block.order_index
      )
      order by block.order_index, block.id
    ),
    '[]'::json
  )
  into blocks_value
  from public.website_blocks block
  where block.tenant_id = p_tenant_id
    and block.page_id = home_page_id_value
    and block.is_visible is true;

  return json_build_object(
    'settings', settings_value,
    'blocks', blocks_value,
    'home_page_id', home_page_id_value
  );
end;
$$;

revoke all on function public.get_public_store_data(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_store_data(uuid)
  to anon, authenticated;

create or replace function public.can_edit_tenant_settings(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
  )
$$;

create or replace function public.can_manage_tenant_backups(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and profile.role = 'admin'
  )
$$;

revoke all on function public.can_edit_tenant_settings(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.can_manage_tenant_backups(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_edit_tenant_settings(uuid)
  to authenticated, service_role;
grant execute on function public.can_manage_tenant_backups(uuid)
  to authenticated, service_role;

-- Replace every website_settings policy, including dashboard or legacy PUBLIC
-- policies. Storefront reads expose only non-sensitive keys for active tenants;
-- authenticated mutations require explicit DB-backed settings authority.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_settings'
  loop
    execute format(
      'drop policy if exists %I on public.website_settings',
      policy_row.policyname
    );
  end loop;
end
$$;

alter table public.website_settings enable row level security;

create policy website_settings_public_safe_read
  on public.website_settings
  for select
  to anon
  using (
    not public.website_setting_is_sensitive(key)
    and public.is_tenant_active(website_settings.tenant_id)
  );

create policy website_settings_authenticated_safe_read
  on public.website_settings
  for select
  to authenticated
  using (
    not public.website_setting_is_sensitive(key)
    and public.is_tenant_active(website_settings.tenant_id)
  );

create policy website_settings_authorized_insert
  on public.website_settings
  for insert
  to authenticated
  with check (public.can_edit_tenant_settings(tenant_id));

create policy website_settings_authorized_update
  on public.website_settings
  for update
  to authenticated
  using (public.can_edit_tenant_settings(tenant_id))
  with check (public.can_edit_tenant_settings(tenant_id));

create policy website_settings_authorized_delete
  on public.website_settings
  for delete
  to authenticated
  using (public.can_edit_tenant_settings(tenant_id));

revoke all on table public.website_settings
  from public, anon, authenticated, service_role;
grant select on table public.website_settings to anon;
grant select, insert, update, delete on table public.website_settings
  to authenticated;
grant all on table public.website_settings to service_role;

-- Sensitive rows are intentionally invisible to authenticated SELECT. That
-- makes a direct INSERT ... ON CONFLICT DO UPDATE fail under RLS even for a
-- settings administrator. Keep secret reads server-owned and persist the three
-- MercadoPago settings atomically through a tenant-derived, bounded contract.
create or replace function public.save_mercadopago_settings(
  p_public_key text,
  p_access_token text,
  p_test_mode boolean
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
  public_key_value text := btrim(coalesce(p_public_key, ''));
  access_token_value text := btrim(coalesce(p_access_token, ''));
begin
  if tenant_id_value is null
     or not public.can_edit_tenant_settings(tenant_id_value) then
    raise exception 'Website settings access denied'
      using errcode = '42501';
  end if;

  if public_key_value = ''
     or access_token_value = ''
     or p_test_mode is null
     or length(public_key_value) > 512
     or length(access_token_value) > 4096 then
    raise exception 'Invalid MercadoPago settings'
      using errcode = '22023';
  end if;

  insert into public.website_settings (
    tenant_id,
    key,
    value,
    description,
    updated_at
  )
  values
    (
      tenant_id_value,
      'mercadopago_public_key',
      public_key_value,
      'MercadoPago public key',
      now()
    ),
    (
      tenant_id_value,
      'mercadopago_access_token',
      access_token_value,
      'MercadoPago server access token',
      now()
    ),
    (
      tenant_id_value,
      'mercadopago_test_mode',
      case when p_test_mode then 'true' else 'false' end,
      'MercadoPago test mode',
      now()
    )
  on conflict (tenant_id, key) do update
  set value = excluded.value,
      description = coalesce(
        excluded.description,
        public.website_settings.description
      ),
      updated_at = now();
end;
$$;

revoke all on function public.save_mercadopago_settings(text, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.save_mercadopago_settings(text, text, boolean)
  to authenticated;

-- Suspended tenants must fail closed in shared authorization helpers used by
-- messaging, official-document RLS, and payment command triggers.
create or replace function public.messaging_is_staff_in_tenant(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and p_tenant_id is not null
    and exists (
      select 1
      from public.user_profiles profile
      join public.tenants tenant
        on tenant.id = profile.tenant_id
       and tenant.is_active is true
      where profile.user_id = auth.uid()
        and profile.tenant_id = p_tenant_id
        and profile.is_active is true
    )
$$;

create or replace function public.messaging_is_customer_in_tenant(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and p_tenant_id is not null
    and exists (
      select 1
      from public.customers customer
      join public.tenants tenant
        on tenant.id = customer.tenant_id
       and tenant.is_active is true
      where customer.auth_user_id = auth.uid()
        and customer.tenant_id = p_tenant_id
        and customer.is_active is true
    )
$$;

create or replace function public.messaging_user_belongs_to_tenant(
  p_user_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select p_user_id is not null
    and p_tenant_id is not null
    and exists (
      select 1
      from public.tenants tenant
      where tenant.id = p_tenant_id
        and tenant.is_active is true
    )
    and (
      exists (
        select 1
        from public.user_profiles profile
        where profile.user_id = p_user_id
          and profile.tenant_id = p_tenant_id
          and profile.is_active is true
      )
      or exists (
        select 1
        from public.customers customer
        where customer.auth_user_id = p_user_id
          and customer.tenant_id = p_tenant_id
          and customer.is_active is true
      )
    )
$$;

create or replace function
  public.has_active_official_document_staff_access(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
  )
$$;

revoke all on function public.messaging_is_staff_in_tenant(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_is_customer_in_tenant(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_user_belongs_to_tenant(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.has_active_official_document_staff_access(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.messaging_is_staff_in_tenant(uuid)
  to authenticated, service_role;
grant execute on function public.messaging_is_customer_in_tenant(uuid)
  to authenticated, service_role;
grant execute on function
  public.messaging_user_belongs_to_tenant(uuid, uuid)
  to authenticated, service_role;
grant execute on function
  public.has_active_official_document_staff_access(uuid)
  to authenticated, service_role;

create or replace function public.messaging_is_conversation_participant(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversation_participants participant
      join public.conversations conversation
        on conversation.id = participant.conversation_id
       and conversation.tenant_id = participant.tenant_id
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where participant.conversation_id = p_conversation_id
        and participant.user_id = auth.uid()
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
    )
$$;

create or replace function public.messaging_can_access_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where conversation.id = p_conversation_id
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
        and (
          (
            conversation.type = 'internal'
            and (
              exists (
                select 1
                from public.conversation_participants participant
                where participant.conversation_id = conversation.id
                  and participant.user_id = auth.uid()
                  and participant.tenant_id = conversation.tenant_id
              )
              or (
                conversation.created_by = auth.uid()
                and public.messaging_is_staff_in_tenant(
                  conversation.tenant_id
                )
                and not exists (
                  select 1
                  from public.conversation_participants any_participant
                  where any_participant.conversation_id = conversation.id
                )
              )
            )
          )
          or (
            conversation.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(conversation.tenant_id)
              or exists (
                select 1
                from public.conversation_participants participant
                where participant.conversation_id = conversation.id
                  and participant.user_id = auth.uid()
                  and participant.tenant_id = conversation.tenant_id
              )
              or (
                conversation.created_by = auth.uid()
                and public.messaging_is_customer_in_tenant(
                  conversation.tenant_id
                )
              )
            )
          )
        )
    )
$$;

create or replace function public.messaging_can_read_conversation_messages(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where conversation.id = p_conversation_id
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
        and (
          exists (
            select 1
            from public.conversation_participants participant
            where participant.conversation_id = conversation.id
              and participant.user_id = auth.uid()
              and participant.tenant_id = conversation.tenant_id
          )
          or (
            conversation.type = 'support'
            and public.messaging_is_staff_in_tenant(
              conversation.tenant_id
            )
          )
        )
    )
$$;

create or replace function public.messaging_can_manage_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where conversation.id = p_conversation_id
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
        and (
          (
            conversation.type = 'support'
            and public.messaging_is_staff_in_tenant(conversation.tenant_id)
          )
          or (
            conversation.type = 'internal'
            and exists (
              select 1
              from public.conversation_participants participant
              where participant.conversation_id = conversation.id
                and participant.user_id = auth.uid()
                and participant.tenant_id = conversation.tenant_id
                and participant.role = 'admin'
            )
          )
        )
    )
$$;

-- Rebase the participant/read helpers on the capability-aware definitions from
-- the atomic messaging migration, adding only active-tenant/member checks.
create or replace function public.messaging_is_conversation_participant(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversation_participants participant
      join public.conversations conversation
        on conversation.id = participant.conversation_id
       and conversation.tenant_id = participant.tenant_id
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where participant.conversation_id = p_conversation_id
        and participant.user_id = auth.uid()
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
        and (
          conversation.counterparty_type <> 'supplier'
          or public.messaging_is_staff_in_tenant(conversation.tenant_id)
        )
    )
$$;

create or replace function public.messaging_can_access_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where conversation.id = p_conversation_id
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
        and (
          (
            conversation.type = 'internal'
            and (
              public.messaging_is_conversation_participant(conversation.id)
              or (
                conversation.created_by = auth.uid()
                and public.messaging_is_staff_in_tenant(
                  conversation.tenant_id
                )
                and not exists (
                  select 1
                  from public.conversation_participants any_participant
                  where any_participant.conversation_id = conversation.id
                )
              )
            )
          )
          or (
            conversation.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(conversation.tenant_id)
              or (
                conversation.counterparty_type = 'customer'
                and public.messaging_is_customer_in_tenant(
                  conversation.tenant_id
                )
                and (
                  public.messaging_is_conversation_participant(
                    conversation.id
                  )
                  or conversation.created_by = auth.uid()
                )
              )
            )
          )
        )
    )
$$;

create or replace function public.messaging_can_read_conversation_messages(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      join public.tenants tenant
        on tenant.id = conversation.tenant_id
       and tenant.is_active is true
      where conversation.id = p_conversation_id
        and public.messaging_user_belongs_to_tenant(
          auth.uid(),
          conversation.tenant_id
        )
        and (
          (
            conversation.type = 'internal'
            and public.messaging_is_conversation_participant(conversation.id)
          )
          or (
            conversation.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(conversation.tenant_id)
              or (
                conversation.counterparty_type = 'customer'
                and public.messaging_is_customer_in_tenant(
                  conversation.tenant_id
                )
                and public.messaging_is_conversation_participant(
                  conversation.id
                )
              )
            )
          )
        )
    )
$$;

revoke all on function
  public.messaging_is_conversation_participant(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_can_access_conversation(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.messaging_can_read_conversation_messages(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_can_manage_conversation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function
  public.messaging_is_conversation_participant(uuid)
  to authenticated, service_role;
grant execute on function public.messaging_can_access_conversation(uuid)
  to authenticated, service_role;
grant execute on function
  public.messaging_can_read_conversation_messages(uuid)
  to authenticated, service_role;
grant execute on function public.messaging_can_manage_conversation(uuid)
  to authenticated, service_role;

do $$
begin
  if to_regprocedure(
    'public.assert_sales_payment_access_internal(uuid)'
  ) is null then
    if to_regprocedure(
      'public.assert_sales_payment_access(uuid)'
    ) is null then
      raise exception 'Missing assert_sales_payment_access helper';
    end if;
    alter function public.assert_sales_payment_access(uuid)
      rename to assert_sales_payment_access_internal;
  end if;

  if to_regprocedure(
    'public.assert_purchase_payment_access_internal(uuid)'
  ) is null then
    if to_regprocedure(
      'public.assert_purchase_payment_access(uuid)'
    ) is null then
      raise exception 'Missing assert_purchase_payment_access helper';
    end if;
    alter function public.assert_purchase_payment_access(uuid)
      rename to assert_purchase_payment_access_internal;
  end if;
end
$$;

alter function public.assert_sales_payment_access_internal(uuid)
  set search_path = pg_catalog, public, pg_temp;
alter function public.assert_purchase_payment_access_internal(uuid)
  set search_path = pg_catalog, public, pg_temp;
revoke all on function public.assert_sales_payment_access_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.assert_purchase_payment_access_internal(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.assert_sales_payment_access_internal(uuid)
  to service_role;
grant execute on function public.assert_purchase_payment_access_internal(uuid)
  to service_role;

create or replace function public.assert_sales_payment_access(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Payment tenant is inactive or unavailable'
      using errcode = '42501';
  end if;

  perform public.assert_sales_payment_access_internal(p_tenant_id);
end;
$$;

create or replace function public.assert_purchase_payment_access(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Purchase payment tenant is inactive or unavailable'
      using errcode = '42501';
  end if;

  perform public.assert_purchase_payment_access_internal(p_tenant_id);
end;
$$;

revoke all on function public.assert_sales_payment_access(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.assert_purchase_payment_access(uuid)
  from public, anon, authenticated, service_role;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Remove that
-- inherited path and every explicit anon grant without synthesizing new grants
-- from has_function_privilege(), which would mistake PUBLIC inheritance for an
-- intentional authenticated contract.
do $$
declare
  routine_record record;
begin
  for routine_record in
    select routine.oid
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
  loop
    execute format(
      'revoke all on function %s from public, anon',
      routine_record.oid::regprocedure
    );
  end loop;
end
$$;

-- Trigger bodies, seeders, internal backup/restore routines, and journal
-- mutators are not direct client RPCs. Trigger execution does not require
-- callers to hold EXECUTE, while trusted maintenance retains an explicit
-- service grant. Client-facing wrappers are handled by exact signature above.
do $$
declare
  routine_record record;
begin
  for routine_record in
    select routine.oid
    from pg_proc routine
    join pg_namespace namespace
      on namespace.oid = routine.pronamespace
    where namespace.nspname = 'public'
      and routine.prosecdef is true
      and (
        routine.prorettype = 'trigger'::regtype
        or routine.proname like 'seed\_%' escape '\'
        or routine.proname = any (array[
          'create_backup_internal',
          'restore_backup_internal',
          'get_backup_summary_internal',
          'cleanup_old_backups_internal',
          'create_website_backup_internal',
          'restore_website_backup_internal',
          'ensure_account_internal',
          'create_sales_payment_journal_entry',
          'delete_sales_payment_journal_entry',
          'delete_sales_invoice_journal_entry',
          'ensure_sales_invoice_journal_entry_internal',
          'delete_purchase_invoice_journal_entry',
          'recalculate_journal_entry_totals',
          'sync_journal_entry_totals_from_lines',
          'create_employee_advance_journal_entry',
          'create_employee_advance_allocation_journal_entry',
          'ensure_payroll_line_expense',
          'capture_posted_journal_supersession_evidence',
          'checkpoint_journal_entry_trace',
          'begin_invoice_inventory_accounting_trace',
          'complete_invoice_inventory_accounting_trace'
        ])
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated, service_role',
      routine_record.oid::regprocedure
    );
    execute format(
      'grant execute on function %s to service_role',
      routine_record.oid::regprocedure
    );
  end loop;
end
$$;

alter default privileges in schema public
  revoke execute on functions from public;
alter default privileges in schema public
  revoke execute on functions from anon;
alter default privileges in schema public
  revoke execute on functions from authenticated;

revoke create on schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated, service_role;

do $$
declare
  signature text;
  routine_oid regprocedure;
begin
  foreach signature in array array[
    'public.user_tenant_id()',
    'public.is_tenant_active(uuid)',
    'public.resolve_public_product_url_alias(uuid,text)',
    'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'public.search_public_products(text,uuid,integer)',
    'public.get_public_featured_products(uuid,integer)',
    'public.get_public_product_category_counts(uuid,text,boolean)',
    'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)',
    'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)',
    'public.get_public_product_technical_specs(uuid,uuid)',
    'public.create_public_online_order_with_access(jsonb,jsonb)',
    'public.get_public_online_order_by_access_token(text)',
    'public.get_public_product_tax_classifications(uuid,uuid[])',
    'public.quote_public_online_shipping(uuid,text,numeric,text)',
    'public.get_public_store_data(uuid)',
    'public.lookup_user_invitation(text)'
  ]
  loop
    routine_oid := to_regprocedure(signature);
    if routine_oid is null then
      raise exception 'Missing anonymous RPC allowlist function: %', signature;
    end if;

    execute format(
      'grant execute on function %s to anon',
      routine_oid
    );
  end loop;
end
$$;

commit;
