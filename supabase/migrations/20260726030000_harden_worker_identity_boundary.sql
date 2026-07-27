begin;

-- Worker portal credentials are an internal authentication primitive. Flutter
-- clients use the tenant-checked admin Edge function and the narrow worker RPCs;
-- no signed-in browser needs direct table access to usernames or login emails.
alter table public.employee_portal_accounts enable row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'employee_portal_accounts'
  loop
    execute format(
      'drop policy if exists %I on public.employee_portal_accounts',
      policy_row.policyname
    );
  end loop;
end
$$;

revoke all on table public.employee_portal_accounts
  from public, anon, authenticated;
grant all on table public.employee_portal_accounts
  to service_role;

-- Employee records contain the ERP-side user link. Reading remains available
-- to active tenant members, while lifecycle changes require the same
-- DB-backed authority as user administration.
alter table public.employees enable row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'employees'
  loop
    execute format(
      'drop policy if exists %I on public.employees',
      policy_row.policyname
    );
  end loop;
end
$$;

create policy employees_read_tenant
  on public.employees
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

create policy employees_insert_managers
  on public.employees
  for insert
  to authenticated
  with check (public.can_manage_tenant_users(tenant_id));

create policy employees_update_managers
  on public.employees
  for update
  to authenticated
  using (public.can_manage_tenant_users(tenant_id))
  with check (public.can_manage_tenant_users(tenant_id));

create policy employees_delete_managers
  on public.employees
  for delete
  to authenticated
  using (public.can_manage_tenant_users(tenant_id));

revoke all on table public.employees
  from public, anon, authenticated;
grant select, insert, update, delete on table public.employees
  to authenticated;
grant all on table public.employees
  to service_role;

-- Every table that can grant ERP or worker membership takes the same
-- transaction-scoped advisory lock. This closes the cross-table race where two
-- concurrent transactions could each observe the other membership as absent.
create or replace function public.lock_auth_membership_identities(
  p_previous_user_id uuid,
  p_next_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  lock_key bigint;
begin
  for lock_key in
    select distinct hashtextextended(
      'vinabike-auth-membership:' || candidate.user_id::text,
      0
    )
    from unnest(
      array[p_previous_user_id, p_next_user_id]::uuid[]
    ) candidate(user_id)
    where candidate.user_id is not null
    order by 1
  loop
    perform pg_advisory_xact_lock(lock_key);
  end loop;
end;
$$;

revoke all on function public.lock_auth_membership_identities(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Reissuing an admin-set credential is the only supported reactivation path.
-- The DB gate becomes active and reset-required before the Auth Admin API
-- changes the password; a partial Auth failure therefore remains fail-closed.
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
  set is_active = true,
      must_reset_password = true,
      password_reset_required_at = reset_required_at,
      password_credential_issued_at = null,
      password_reset_challenge_started_at = null,
      updated_at = now()
  where portal.id = p_portal_account_id
    and portal.tenant_id = p_tenant_id
    and portal.auth_user_id is not null;

  if not found then
    raise exception 'Worker portal account not found'
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

create or replace function public.revoke_worker_portal_sessions(
  p_portal_account_id uuid,
  p_tenant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  auth_user_id_value uuid;
  deleted_count integer := 0;
begin
  if p_portal_account_id is null or p_tenant_id is null then
    raise exception 'Worker portal account and tenant are required'
      using errcode = '22004';
  end if;

  select portal.auth_user_id
  into auth_user_id_value
  from public.employee_portal_accounts portal
  where portal.id = p_portal_account_id
    and portal.tenant_id = p_tenant_id
  for update;

  if not found or auth_user_id_value is null then
    raise exception 'Worker portal Auth identity not found'
      using errcode = 'P0002';
  end if;

  delete from auth.sessions session
  where session.user_id = auth_user_id_value;

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.revoke_worker_portal_sessions(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.revoke_worker_portal_sessions(uuid, uuid)
  to service_role;

-- An Auth identity may have customer memberships in many storefronts, but a
-- worker login must never simultaneously be an active ERP staff identity.
-- Authority is accepted only when immutable Admin metadata, the active portal
-- link, the employee, and the tenant all agree.
create or replace function public.is_authoritative_worker_portal_identity(
  p_user_id uuid,
  p_tenant_id uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select exists (
    select 1
    from auth.users auth_user
    join public.employee_portal_accounts portal
      on portal.auth_user_id = auth_user.id
     and portal.tenant_id = p_tenant_id
     and portal.employee_id = p_employee_id
     and portal.is_active is true
    join public.employees employee
      on employee.id = portal.employee_id
     and employee.tenant_id = portal.tenant_id
     and employee.status = 'active'
    join public.tenants tenant
      on tenant.id = portal.tenant_id
     and tenant.is_active is true
    where auth_user.id = p_user_id
      and auth_user.banned_until is null
      and coalesce(
        auth_user.raw_app_meta_data->>'account_type',
        ''
      ) = 'worker_portal'
      and coalesce(
        auth_user.raw_app_meta_data->>'tenant_id',
        ''
      ) = p_tenant_id::text
      and coalesce(
        auth_user.raw_app_meta_data->>'employee_id',
        ''
      ) = p_employee_id::text
      and coalesce(
        auth_user.raw_app_meta_data->>'role',
        ''
      ) = 'worker'
      and not exists (
        select 1
        from public.user_profiles profile
        join public.tenants profile_tenant
          on profile_tenant.id = profile.tenant_id
         and profile_tenant.is_active is true
        where profile.user_id = p_user_id
          and profile.is_active is true
      )
      and not exists (
        select 1
        from public.employees staff_employee
        join public.tenants staff_tenant
          on staff_tenant.id = staff_employee.tenant_id
         and staff_tenant.is_active is true
        where staff_employee.user_id = p_user_id
          and staff_employee.status = 'active'
      )
  )
$$;

revoke all on function public.is_authoritative_worker_portal_identity(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated, service_role;

create or replace function public.guard_worker_portal_identity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  auth_metadata jsonb;
begin
  perform public.lock_auth_membership_identities(
    case
      when tg_op = 'INSERT' then null
      else old.auth_user_id
    end,
    new.auth_user_id
  );

  if new.is_active is not true or new.auth_user_id is null then
    return new;
  end if;

  select coalesce(auth_user.raw_app_meta_data, '{}'::jsonb)
  into auth_metadata
  from auth.users auth_user
  where auth_user.id = new.auth_user_id
    and auth_user.banned_until is null;

  if not found
     or coalesce(auth_metadata->>'account_type', '') <> 'worker_portal'
     or coalesce(auth_metadata->>'tenant_id', '') <> new.tenant_id::text
     or coalesce(auth_metadata->>'employee_id', '') <> new.employee_id::text
     or coalesce(auth_metadata->>'role', '') <> 'worker' then
    raise exception 'Authoritative worker portal identity is required'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = new.auth_user_id
      and profile.is_active is true
  ) then
    raise exception
      'Worker portal identity cannot be linked to an active ERP profile'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.employees employee
    join public.tenants tenant
      on tenant.id = employee.tenant_id
     and tenant.is_active is true
    where employee.user_id = new.auth_user_id
      and employee.status = 'active'
  ) then
    raise exception
      'Worker portal identity cannot be linked as ERP staff'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_worker_portal_identity()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_worker_portal_identity
  on public.employee_portal_accounts;
create trigger trg_guard_worker_portal_identity
  before insert or update of tenant_id, employee_id, auth_user_id, is_active
  on public.employee_portal_accounts
  for each row
  execute function public.guard_worker_portal_identity();

create or replace function public.guard_worker_profile_overlap()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.lock_auth_membership_identities(
    case
      when tg_op = 'INSERT' then null
      else old.user_id
    end,
    new.user_id
  );

  if new.is_active is true
     and exists (
       select 1
       from public.employee_portal_accounts portal
       where portal.auth_user_id = new.user_id
         and portal.is_active is true
     ) then
    raise exception
      'Worker portal identity cannot be linked to an active ERP profile'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_worker_profile_overlap()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_worker_profile_overlap
  on public.user_profiles;
create trigger trg_guard_worker_profile_overlap
  before insert or update of user_id, is_active
  on public.user_profiles
  for each row
  execute function public.guard_worker_profile_overlap();

create or replace function public.guard_worker_staff_employee_overlap()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.lock_auth_membership_identities(
    case
      when tg_op = 'INSERT' then null
      else old.user_id
    end,
    new.user_id
  );

  if new.user_id is not null
     and new.status = 'active'
     and exists (
       select 1
       from public.employee_portal_accounts portal
       where portal.auth_user_id = new.user_id
         and portal.is_active is true
     ) then
    raise exception 'Worker portal identity cannot be linked as ERP staff'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_worker_staff_employee_overlap()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_worker_staff_employee_overlap
  on public.employees;
create trigger trg_guard_worker_staff_employee_overlap
  before insert or update of user_id, status
  on public.employees
  for each row
  execute function public.guard_worker_staff_employee_overlap();

-- Ending an employment immediately closes the worker credential gate and
-- revokes every Auth session. Reactivation must then go through the
-- credential-issue workflow, which assigns a fresh temporary password and
-- restores the mandatory reset marker.
create or replace function public.deactivate_worker_portal_on_employee_exit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
begin
  if old.status = 'active' and new.status <> 'active' then
    update public.employee_portal_accounts portal
    set is_active = false,
        must_reset_password = true,
        password_reset_required_at = clock_timestamp(),
        password_credential_issued_at = null,
        password_reset_challenge_started_at = null,
        updated_at = now()
    where portal.employee_id = new.id
      and portal.tenant_id = new.tenant_id
      and portal.auth_user_id is not null;

    delete from auth.sessions session
    using public.employee_portal_accounts portal
    where portal.employee_id = new.id
      and portal.tenant_id = new.tenant_id
      and portal.auth_user_id = session.user_id;
  end if;

  return new;
end;
$$;

revoke all on function public.deactivate_worker_portal_on_employee_exit()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_deactivate_worker_portal_on_employee_exit
  on public.employees;
create trigger trg_deactivate_worker_portal_on_employee_exit
  after update of status
  on public.employees
  for each row
  when (old.status is distinct from new.status)
  execute function public.deactivate_worker_portal_on_employee_exit();

-- A physical employee delete previously cascaded the portal row while leaving
-- Auth and its sessions orphaned. Preserve the employee audit row until a
-- dedicated service-role unlink/delete workflow has disposed of the Auth
-- identity explicitly.
create or replace function public.guard_linked_worker_employee_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = old.id
      and portal.tenant_id = old.tenant_id
      and portal.auth_user_id is not null
  ) then
    raise exception
      'Linked worker access must be removed before deleting the employee'
      using errcode = '42501';
  end if;

  return old;
end;
$$;

revoke all on function public.guard_linked_worker_employee_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_linked_worker_employee_delete
  on public.employees;
create trigger trg_guard_linked_worker_employee_delete
  before delete
  on public.employees
  for each row
  execute function public.guard_linked_worker_employee_delete();

-- Preserve the established RPC signatures while placing the legacy bodies
-- behind wrappers that require the dedicated worker identity invariant.
do $$
begin
  if to_regprocedure(
    'public.resolve_worker_login_internal(text,text)'
  ) is null then
    if to_regprocedure(
      'public.resolve_worker_login(text,text)'
    ) is null then
      raise exception 'Missing worker login resolver';
    end if;
    alter function public.resolve_worker_login(text, text)
      rename to resolve_worker_login_internal;
  end if;

  if to_regprocedure(
    'public.get_my_worker_portal_context_internal()'
  ) is null then
    if to_regprocedure(
      'public.get_my_worker_portal_context()'
    ) is null then
      raise exception 'Missing worker portal context RPC';
    end if;
    alter function public.get_my_worker_portal_context()
      rename to get_my_worker_portal_context_internal;
  end if;

  if to_regprocedure(
    'public.begin_my_worker_password_reset_internal()'
  ) is null then
    if to_regprocedure(
      'public.begin_my_worker_password_reset()'
    ) is null then
      raise exception 'Missing worker password reset begin RPC';
    end if;
    alter function public.begin_my_worker_password_reset()
      rename to begin_my_worker_password_reset_internal;
  end if;

  if to_regprocedure(
    'public.complete_my_worker_password_reset_internal()'
  ) is null then
    if to_regprocedure(
      'public.complete_my_worker_password_reset()'
    ) is null then
      raise exception 'Missing worker password reset completion RPC';
    end if;
    alter function public.complete_my_worker_password_reset()
      rename to complete_my_worker_password_reset_internal;
  end if;
end
$$;

revoke all on function public.resolve_worker_login_internal(text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.get_my_worker_portal_context_internal()
  from public, anon, authenticated, service_role;
revoke all on function public.begin_my_worker_password_reset_internal()
  from public, anon, authenticated, service_role;
revoke all on function public.complete_my_worker_password_reset_internal()
  from public, anon, authenticated, service_role;

create or replace function public.resolve_worker_login(
  p_tenant text,
  p_username text
)
returns table (login_email text)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select candidate.login_email
  from public.resolve_worker_login_internal(
    p_tenant,
    p_username
  ) candidate
  join public.employee_portal_accounts portal
    on portal.login_email = candidate.login_email
   and portal.is_active is true
  where public.is_authoritative_worker_portal_identity(
    portal.auth_user_id,
    portal.tenant_id,
    portal.employee_id
  )
  limit 1
$$;

revoke all on function public.resolve_worker_login(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.resolve_worker_login(text, text)
  to service_role;

create or replace function public.get_my_worker_portal_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = auth.uid()
      and portal.is_active is true
      and public.is_authoritative_worker_portal_identity(
        portal.auth_user_id,
        portal.tenant_id,
        portal.employee_id
      )
  ) then
    return null;
  end if;

  return public.get_my_worker_portal_context_internal();
end;
$$;

revoke all on function public.get_my_worker_portal_context()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_worker_portal_context()
  to authenticated;

create or replace function public.worker_portal_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select portal.tenant_id
  from public.employee_portal_accounts portal
  where portal.auth_user_id = auth.uid()
    and portal.is_active is true
    and portal.must_reset_password is false
    and public.is_authoritative_worker_portal_identity(
      portal.auth_user_id,
      portal.tenant_id,
      portal.employee_id
    )
  limit 1
$$;

revoke all on function public.worker_portal_tenant_id()
  from public, anon, authenticated, service_role;
grant execute on function public.worker_portal_tenant_id()
  to authenticated;

create or replace function public.worker_portal_employee_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select portal.employee_id
  from public.employee_portal_accounts portal
  where portal.auth_user_id = auth.uid()
    and portal.is_active is true
    and portal.must_reset_password is false
    and public.is_authoritative_worker_portal_identity(
      portal.auth_user_id,
      portal.tenant_id,
      portal.employee_id
    )
  limit 1
$$;

revoke all on function public.worker_portal_employee_id()
  from public, anon, authenticated, service_role;
grant execute on function public.worker_portal_employee_id()
  to authenticated;

create or replace function public.begin_my_worker_password_reset()
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = auth.uid()
      and portal.is_active is true
      and public.is_authoritative_worker_portal_identity(
        portal.auth_user_id,
        portal.tenant_id,
        portal.employee_id
      )
  ) then
    raise exception 'Authoritative worker identity required'
      using errcode = '42501';
  end if;

  return public.begin_my_worker_password_reset_internal();
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
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = auth.uid()
      and portal.is_active is true
      and public.is_authoritative_worker_portal_identity(
        portal.auth_user_id,
        portal.tenant_id,
        portal.employee_id
      )
  ) then
    raise exception 'Authoritative worker identity required'
      using errcode = '42501';
  end if;

  return public.complete_my_worker_password_reset_internal();
end;
$$;

revoke all on function public.complete_my_worker_password_reset()
  from public, anon, authenticated, service_role;
grant execute on function public.complete_my_worker_password_reset()
  to authenticated;

commit;
