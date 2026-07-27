-- Deployment status: candidate; production-derived clone + live read-back required.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- A worker login and an ERP identity are two mutually exclusive access modes
-- for one employee. A suspended/historical ERP profile may remain linked for
-- audit and later reactivation, but switching modes requires the explicit
-- unlink command below. Granting a link requires active records; removing an
-- exact link is deliberately allowed after either side is suspended so the
-- employee can never become permanently trapped between access modes.
--
-- This migration is intentionally fail-closed and contains no production data
-- repair. Existing conflicts must be investigated rather than guessed.
do $$
begin
  if exists (
    select 1
    from public.employees employee
    where employee.tenant_id is null
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: employees without tenant exist';
  end if;

  if exists (
    select 1
    from public.user_profiles profile
    join public.employees employee
      on employee.id = profile.employee_id
    where profile.employee_id is not null
      and employee.tenant_id is distinct from profile.tenant_id
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: cross-tenant ERP profile links exist';
  end if;

  if exists (
    select 1
    from public.user_invitations invitation
    join public.employees employee
      on employee.id = invitation.employee_id
    where invitation.employee_id is not null
      and employee.tenant_id is distinct from invitation.tenant_id
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: cross-tenant invitation links exist';
  end if;

  if exists (
    select 1
    from public.employees employee
    where employee.user_id is not null
    group by employee.user_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: ERP users linked to multiple employees exist';
  end if;

  if exists (
    select 1
    from public.user_profiles profile
    where profile.employee_id is not null
    group by profile.employee_id
    having count(*) > 1
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: employees with multiple ERP profile links exist';
  end if;

  if exists (
    select 1
    from public.employees employee
    where employee.user_id is not null
      and not exists (
        select 1
        from public.user_profiles profile
        where profile.user_id = employee.user_id
          and profile.tenant_id = employee.tenant_id
          and profile.employee_id = employee.id
      )
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: unilateral employee ERP links exist';
  end if;

  if exists (
    select 1
    from public.user_profiles profile
    join public.employees employee
      on employee.id = profile.employee_id
     and employee.tenant_id = profile.tenant_id
    where profile.employee_id is not null
      and (
        employee.user_id is distinct from profile.user_id
        or (
          profile.is_active is true
          and employee.status <> 'active'
        )
      )
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: active ERP profile links are inconsistent';
  end if;

  if exists (
    select 1
    from public.employee_portal_accounts portal
    join public.employees employee
      on employee.id = portal.employee_id
     and employee.tenant_id = portal.tenant_id
    where portal.is_active is true
      and (
        employee.user_id is not null
        or exists (
          select 1
          from public.user_profiles profile
          where profile.employee_id = employee.id
            and profile.tenant_id = employee.tenant_id
        )
      )
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: worker and ERP employee access overlap';
  end if;

  if exists (
    select 1
    from public.user_invitations invitation
    join public.employees employee
      on employee.id = invitation.employee_id
     and employee.tenant_id = invitation.tenant_id
    where invitation.status = 'pending'
      and invitation.employee_id is not null
      and (
        employee.status <> 'active'
        or employee.user_id is not null
        or exists (
          select 1
          from public.user_profiles profile
          where profile.employee_id = employee.id
            and profile.tenant_id = employee.tenant_id
        )
        or exists (
          select 1
          from public.employee_portal_accounts portal
          where portal.employee_id = employee.id
            and portal.tenant_id = employee.tenant_id
            and portal.is_active is true
        )
      )
  ) then
    raise exception
      'Cannot enforce employee access identity boundary: pending employee invitations conflict with existing access';
  end if;
end
$$;

alter table public.employees
  alter column tenant_id set not null;

create unique index if not exists employees_one_erp_user_uidx
  on public.employees(user_id)
  where user_id is not null;

drop index if exists public.user_profiles_one_active_employee_uidx;

create unique index if not exists user_profiles_one_erp_employee_uidx
  on public.user_profiles(employee_id)
  where employee_id is not null;

create unique index if not exists
  user_invitations_one_pending_employee_uidx
  on public.user_invitations(employee_id)
  where employee_id is not null
    and status = 'pending';

-- The employee UUID alone is globally unique, but the composite foreign keys
-- make tenant agreement a database invariant rather than an Edge convention.
alter table public.user_profiles
  drop constraint if exists user_profiles_employee_id_fkey;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.user_profiles'::regclass
      and conname = 'user_profiles_employee_tenant_fkey'
  ) then
    alter table public.user_profiles
      add constraint user_profiles_employee_tenant_fkey
      foreign key (employee_id, tenant_id)
      references public.employees(id, tenant_id)
      on delete set null (employee_id)
      not valid;
  end if;
end
$$;

alter table public.user_profiles
  validate constraint user_profiles_employee_tenant_fkey;

alter table public.user_invitations
  drop constraint if exists user_invitations_employee_id_fkey;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.user_invitations'::regclass
      and conname = 'user_invitations_employee_tenant_fkey'
  ) then
    alter table public.user_invitations
      add constraint user_invitations_employee_tenant_fkey
      foreign key (employee_id, tenant_id)
      references public.employees(id, tenant_id)
      on delete cascade
      not valid;
  end if;
end
$$;

alter table public.user_invitations
  validate constraint user_invitations_employee_tenant_fkey;

-- All competing employee-access writers take the same transaction-scoped lock.
create or replace function public.lock_employee_access_identity(
  p_employee_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if p_employee_id is not null then
    perform pg_advisory_xact_lock(
      hashtextextended(
        'vinabike-employee-access:' || p_employee_id::text,
        0
      )
    );
  end if;
end;
$$;

revoke all on function public.lock_employee_access_identity(uuid)
  from public, anon, authenticated, service_role;

-- Direct REST/service-role changes to the two link columns are forbidden.
-- SECURITY DEFINER onboarding and canonical link RPCs execute as their owner
-- and remain the only application writers.
create or replace function public.guard_employee_erp_user_id_write()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if (
    (tg_op = 'INSERT' and new.user_id is not null)
    or (
      tg_op = 'UPDATE'
      and new.user_id is distinct from old.user_id
    )
  )
     and current_user = any (
       array['anon', 'authenticated', 'service_role']::name[]
     ) then
    raise exception 'employee_erp_link_requires_canonical_command'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_employee_erp_user_id_write()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_employee_erp_user_id_write
  on public.employees;
create trigger trg_guard_employee_erp_user_id_write
  before insert or update of user_id
  on public.employees
  for each row
  execute function public.guard_employee_erp_user_id_write();

create or replace function public.guard_profile_employee_id_write()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if (
    (tg_op = 'INSERT' and new.employee_id is not null)
    or (
      tg_op = 'UPDATE'
      and new.employee_id is distinct from old.employee_id
    )
  )
     and current_user = any (
       array['anon', 'authenticated', 'service_role']::name[]
     ) then
    raise exception 'employee_erp_link_requires_canonical_command'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_profile_employee_id_write()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_profile_employee_id_write
  on public.user_profiles;
create trigger trg_guard_profile_employee_id_write
  before insert or update of employee_id
  on public.user_profiles
  for each row
  execute function public.guard_profile_employee_id_write();

-- A pending invitation reserves the employee's access mode until it is
-- accepted, cancelled, or expires. This trigger is the race-safe backstop for
-- every service-role invitation writer.
create or replace function public.guard_erp_invitation_employee_access()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  employee_row public.employees%rowtype;
begin
  if new.status <> 'pending' or new.employee_id is null then
    return new;
  end if;

  perform public.lock_employee_access_identity(new.employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = new.employee_id
    and employee.tenant_id = new.tenant_id
  for update;

  if not found or employee_row.status <> 'active' then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = new.employee_id
      and portal.tenant_id = new.tenant_id
      and portal.is_active is true
  ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  if employee_row.user_id is not null
     or exists (
       select 1
       from public.user_profiles profile
       where profile.employee_id = new.employee_id
         and profile.tenant_id = new.tenant_id
     ) then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_erp_invitation_employee_access()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_erp_invitation_employee_access
  on public.user_invitations;
create trigger trg_guard_erp_invitation_employee_access
  before insert or update of tenant_id, employee_id, status
  on public.user_invitations
  for each row
  execute function public.guard_erp_invitation_employee_access();

-- Invitation acceptance is an owner-defined canonical writer. API roles and
-- service-role REST writes remain blocked by the column guards above, while
-- this SECURITY DEFINER function updates both sides in one transaction and
-- participates in the same employee advisory lock as Worker provisioning.
--
-- An already-active ERP member must be linked with the explicit admin command;
-- accepting another invitation never silently consumes it as a no-op.
create or replace function public.accept_user_invitation(p_token text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
declare
  auth_user_id_value uuid := auth.uid();
  auth_email text;
  token_digest text;
  invitation_row public.user_invitations%rowtype;
  employee_row public.employees%rowtype;
  external_profile_count integer;
  same_tenant_profile_active boolean;
  same_tenant_profile_exists boolean;
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

  perform public.lock_auth_membership_identities(
    invitation_row.tenant_id,
    auth_user_id_value
  );

  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = auth_user_id_value
  ) then
    raise exception 'identity_unavailable'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employees employee
    where employee.user_id = auth_user_id_value
  ) then
    raise exception 'identity_unavailable'
      using errcode = 'P0001';
  end if;

  select count(*)::integer
  into external_profile_count
  from public.user_profiles profile
  where profile.user_id = auth_user_id_value
    and profile.tenant_id <> invitation_row.tenant_id;

  if external_profile_count <> 0 then
    raise exception 'identity_unavailable'
      using errcode = 'P0001';
  end if;

  select
    coalesce(bool_or(profile.is_active is true), false),
    count(*) > 0
  into same_tenant_profile_active, same_tenant_profile_exists
  from public.user_profiles profile
  where profile.user_id = auth_user_id_value
    and profile.tenant_id = invitation_row.tenant_id;

  if same_tenant_profile_active then
    raise exception 'active_staff_email_requires_direct_link'
      using errcode = 'P0001';
  end if;

  if same_tenant_profile_exists then
    raise exception 'staff_membership_inactive'
      using errcode = 'P0001';
  end if;

  if invitation_row.employee_id is not null then
    perform public.lock_employee_access_identity(invitation_row.employee_id);

    select employee.*
    into employee_row
    from public.employees employee
    where employee.id = invitation_row.employee_id
      and employee.tenant_id = invitation_row.tenant_id
    for update;

    if not found or employee_row.status <> 'active' then
      raise exception 'employee_not_found'
        using errcode = 'P0001';
    end if;

    if exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.employee_id = invitation_row.employee_id
        and portal.tenant_id = invitation_row.tenant_id
        and portal.is_active is true
    ) then
      raise exception 'worker_access_conflict'
        using errcode = 'P0001';
    end if;

    if employee_row.user_id is not null
       or exists (
         select 1
         from public.user_profiles profile
         where profile.employee_id = invitation_row.employee_id
           and profile.tenant_id = invitation_row.tenant_id
       ) then
      raise exception 'employee_erp_link_conflict'
        using errcode = 'P0001';
    end if;

    update public.employees employee
    set user_id = auth_user_id_value,
        updated_at = now()
    where employee.id = invitation_row.employee_id
      and employee.tenant_id = invitation_row.tenant_id
      and employee.status = 'active'
      and employee.user_id is null;

    if not found then
      raise exception 'employee_erp_link_state_changed'
        using errcode = 'P0001';
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

  if not found then
    raise exception 'Invalid or unavailable invitation'
      using errcode = '42501';
  end if;

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
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  return true;
exception
  when unique_violation or foreign_key_violation or check_violation then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
end;
$$;

revoke all on function public.accept_user_invitation(text)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_user_invitation(text)
  to authenticated;

-- Worker authority now also proves that the employee itself has no ERP link or
-- pending ERP invitation. Identity-level separation alone is insufficient.
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
     and employee.user_id is null
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
        where profile.employee_id = p_employee_id
          and profile.tenant_id = p_tenant_id
      )
      and not exists (
        select 1
        from public.user_invitations invitation
        where invitation.employee_id = p_employee_id
          and invitation.tenant_id = p_tenant_id
          and invitation.status = 'pending'
      )
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
  employee_row public.employees%rowtype;
begin
  perform public.lock_auth_membership_identities(
    case
      when tg_op = 'INSERT' then null
      else old.auth_user_id
    end,
    new.auth_user_id
  );
  perform public.lock_employee_access_identity(new.employee_id);

  if new.is_active is not true or new.auth_user_id is null then
    return new;
  end if;

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = new.employee_id
    and employee.tenant_id = new.tenant_id
  for update;

  if not found or employee_row.status <> 'active' then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  if employee_row.user_id is not null
     or exists (
       select 1
       from public.user_profiles profile
       where profile.employee_id = new.employee_id
         and profile.tenant_id = new.tenant_id
     )
     or exists (
       select 1
       from public.user_invitations invitation
       where invitation.employee_id = new.employee_id
         and invitation.tenant_id = new.tenant_id
         and invitation.status = 'pending'
     ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
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
  perform public.lock_employee_access_identity(new.employee_id);

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

  if new.is_active is true
     and new.employee_id is not null
     and exists (
       select 1
       from public.employee_portal_accounts portal
       where portal.employee_id = new.employee_id
         and portal.tenant_id = new.tenant_id
         and portal.is_active is true
     ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_worker_profile_overlap()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_worker_profile_overlap
  on public.user_profiles;
create trigger trg_guard_worker_profile_overlap
  before insert or update of user_id, tenant_id, employee_id, is_active
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
  perform public.lock_employee_access_identity(new.id);

  if new.user_id is not null
     and exists (
       select 1
       from public.employee_portal_accounts portal
       where portal.employee_id = new.id
         and portal.tenant_id = new.tenant_id
         and portal.is_active is true
     ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

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
  before insert or update of tenant_id, user_id, status
  on public.employees
  for each row
  execute function public.guard_worker_staff_employee_overlap();

create or replace function public.guard_linked_erp_employee_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if old.user_id is not null
     or exists (
       select 1
       from public.user_profiles profile
       where profile.employee_id = old.id
         and profile.tenant_id = old.tenant_id
     ) then
    raise exception 'employee_erp_unlink_required'
      using errcode = '42501';
  end if;

  return old;
end;
$$;

revoke all on function public.guard_linked_erp_employee_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_linked_erp_employee_delete
  on public.employees;
create trigger trg_guard_linked_erp_employee_delete
  before delete
  on public.employees
  for each row
  execute function public.guard_linked_erp_employee_delete();

-- Deferred assertions permit the canonical command to update both sides in
-- either order, while rejecting one-sided commits.
create or replace function public.assert_employee_erp_link_consistency()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.user_id is not null
     and not exists (
       select 1
       from public.user_profiles profile
       where profile.user_id = new.user_id
         and profile.tenant_id = new.tenant_id
         and profile.employee_id = new.id
     ) then
    raise exception 'employee_erp_link_inconsistent'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.assert_employee_erp_link_consistency()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_assert_employee_erp_link_consistency
  on public.employees;
create constraint trigger trg_assert_employee_erp_link_consistency
  after insert or update
  on public.employees
  deferrable initially deferred
  for each row
  execute function public.assert_employee_erp_link_consistency();

create or replace function public.assert_profile_employee_link_consistency()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    if old.employee_id is not null
       and exists (
         select 1
         from public.employees employee
         where employee.id = old.employee_id
           and employee.tenant_id = old.tenant_id
           and employee.user_id = old.user_id
       ) then
      raise exception 'employee_erp_link_inconsistent'
        using errcode = 'P0001';
    end if;
    return old;
  end if;

  if new.employee_id is not null
     and (
       not exists (
         select 1
         from public.employees employee
         where employee.id = new.employee_id
           and employee.tenant_id = new.tenant_id
           and employee.user_id = new.user_id
       )
       or (
         new.is_active is true
         and not exists (
           select 1
           from public.employees employee
           where employee.id = new.employee_id
             and employee.tenant_id = new.tenant_id
             and employee.user_id = new.user_id
             and employee.status = 'active'
         )
       )
     ) then
    raise exception 'employee_erp_link_inconsistent'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.assert_profile_employee_link_consistency()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_assert_profile_employee_link_consistency
  on public.user_profiles;
create constraint trigger trg_assert_profile_employee_link_consistency
  after insert or update or delete
  on public.user_profiles
  deferrable initially deferred
  for each row
  execute function public.assert_profile_employee_link_consistency();

-- Database-side equivalent of the Edge hierarchy check. The RPC is directly
-- callable by authenticated clients, so Edge validation is defense in depth,
-- never the final authorization boundary.
create or replace function public.assert_erp_employee_link_actor(
  p_tenant_id uuid,
  p_target_user_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  caller_profile public.user_profiles%rowtype;
  target_profile public.user_profiles%rowtype;
  caller_is_principal boolean;
  target_is_principal boolean;
  caller_rank integer;
  target_rank integer;
begin
  if caller_user_id is null
     or not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'employee_access_management_denied'
      using errcode = '42501';
  end if;

  select profile.*
  into caller_profile
  from public.user_profiles profile
  where profile.user_id = caller_user_id
    and profile.tenant_id = p_tenant_id
    and profile.is_active is true;

  select profile.*
  into target_profile
  from public.user_profiles profile
  where profile.user_id = p_target_user_id
    and profile.tenant_id = p_tenant_id;

  if caller_profile.id is null or target_profile.id is null then
    raise exception 'staff_user_not_found'
      using errcode = 'P0001';
  end if;

  caller_is_principal :=
    public.is_auth_user_db_backed_tenant_owner(
      caller_user_id,
      p_tenant_id
    );
  target_is_principal :=
    public.is_auth_user_db_backed_tenant_owner(
      p_target_user_id,
      p_tenant_id
    );

  if target_is_principal
     and not (
       caller_is_principal
       and caller_user_id = p_target_user_id
     ) then
    raise exception 'principal_owner_protected'
      using errcode = '42501';
  end if;

  if caller_user_id = p_target_user_id then
    return;
  end if;

  caller_rank := case
    when caller_is_principal then 400
    when caller_profile.role = 'admin' then 300
    when caller_profile.role = 'manager'
      or caller_profile.permissions @> '{"manage_users": true}'::jsonb
      then 200
    else 100
  end;
  target_rank := case
    when target_is_principal then 400
    when target_profile.role = 'admin' then 300
    when target_profile.role = 'manager'
      or target_profile.permissions @> '{"manage_users": true}'::jsonb
      then 200
    else 100
  end;

  if target_rank > caller_rank
     or (
       target_rank = caller_rank
       and caller_is_principal is false
     ) then
    raise exception 'staff_hierarchy_forbidden'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_erp_employee_link_actor(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Explicit administrator command: link one existing, active ERP identity to
-- one active employee. It never selects a candidate automatically.
create or replace function public.link_erp_user_to_employee(
  p_user_id uuid,
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  caller_tenant_id uuid;
  employee_row public.employees%rowtype;
  profile_row public.user_profiles%rowtype;
  account_type_value text;
begin
  if caller_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if p_user_id is null or p_employee_id is null then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  select profile.tenant_id
  into caller_tenant_id
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true
    and public.can_manage_tenant_users(profile.tenant_id);

  if not found then
    raise exception 'employee_access_management_denied'
      using errcode = '42501';
  end if;

  perform public.lock_auth_membership_identities(null, p_user_id);
  perform public.lock_employee_access_identity(p_employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  join public.tenants tenant
    on tenant.id = employee.tenant_id
   and tenant.is_active is true
  where employee.id = p_employee_id
    and employee.tenant_id = caller_tenant_id
  for update of employee;

  if not found or employee_row.status <> 'active' then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  select profile.*
  into profile_row
  from public.user_profiles profile
  where profile.user_id = p_user_id
    and profile.tenant_id = employee_row.tenant_id
    and profile.is_active is true
  for update;

  if not found then
    raise exception 'staff_user_not_found'
      using errcode = 'P0001';
  end if;

  perform public.assert_erp_employee_link_actor(
    employee_row.tenant_id,
    p_user_id
  );

  select coalesce(auth_user.raw_app_meta_data->>'account_type', '')
  into account_type_value
  from auth.users auth_user
  where auth_user.id = p_user_id;

  if not found or account_type_value not in ('erp_owner', 'erp_staff') then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = employee_row.id
      and portal.tenant_id = employee_row.tenant_id
      and portal.is_active is true
  ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.user_invitations invitation
    where invitation.employee_id = employee_row.id
      and invitation.tenant_id = employee_row.tenant_id
      and invitation.status = 'pending'
  ) then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  if employee_row.user_id is not null
     and employee_row.user_id <> p_user_id then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  if profile_row.employee_id is not null
     and profile_row.employee_id <> p_employee_id then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employees other_employee
    where other_employee.user_id = p_user_id
      and other_employee.id <> p_employee_id
  )
     or exists (
       select 1
       from public.user_profiles other_profile
       where other_profile.employee_id = p_employee_id
         and other_profile.id <> profile_row.id
     ) then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  update public.employees employee
  set user_id = p_user_id,
      updated_at = now()
  where employee.id = p_employee_id
    and employee.tenant_id = employee_row.tenant_id;

  update public.user_profiles profile
  set employee_id = p_employee_id,
      updated_at = now()
  where profile.id = profile_row.id
    and profile.user_id = p_user_id
    and profile.tenant_id = employee_row.tenant_id
    and profile.is_active is true;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by
  )
  values (
    employee_row.tenant_id,
    p_user_id,
    'employee_erp_identity_linked',
    jsonb_build_object(
      'employee_id', p_employee_id,
      'profile_id', profile_row.id
    ),
    caller_user_id
  );

  return jsonb_build_object(
    'success', true,
    'linked', true,
    'userId', p_user_id,
    'employeeId', p_employee_id
  );
end;
$$;

revoke all on function public.link_erp_user_to_employee(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.link_erp_user_to_employee(uuid, uuid)
  to authenticated;

-- Explicit administrator command: detach the current exact link. Unlike the
-- grant command, revocation remains available when the employee or profile is
-- inactive. Profile, employee, and Auth history remain; the immutable activity
-- row records who detached the access identity.
create or replace function public.unlink_erp_user_from_employee(
  p_user_id uuid,
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  caller_tenant_id uuid;
  employee_row public.employees%rowtype;
  profile_row public.user_profiles%rowtype;
begin
  if caller_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  select profile.tenant_id
  into caller_tenant_id
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true
    and public.can_manage_tenant_users(profile.tenant_id);

  if not found then
    raise exception 'employee_access_management_denied'
      using errcode = '42501';
  end if;

  perform public.lock_auth_membership_identities(null, p_user_id);
  perform public.lock_employee_access_identity(p_employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  join public.tenants tenant
    on tenant.id = employee.tenant_id
   and tenant.is_active is true
  where employee.id = p_employee_id
    and employee.tenant_id = caller_tenant_id
  for update of employee;

  if not found then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  select profile.*
  into profile_row
  from public.user_profiles profile
  where profile.user_id = p_user_id
    and profile.tenant_id = employee_row.tenant_id
  for update;

  if not found then
    raise exception 'staff_user_not_found'
      using errcode = 'P0001';
  end if;

  perform public.assert_erp_employee_link_actor(
    employee_row.tenant_id,
    p_user_id
  );

  if employee_row.user_id is distinct from p_user_id
     or profile_row.employee_id is distinct from p_employee_id then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = p_employee_id
      and portal.tenant_id = employee_row.tenant_id
      and portal.is_active is true
  ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  update public.user_profiles profile
  set employee_id = null,
      updated_at = now()
  where profile.id = profile_row.id
    and profile.user_id = p_user_id
    and profile.tenant_id = employee_row.tenant_id
    and profile.employee_id = p_employee_id;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  update public.employees employee
  set user_id = null,
      updated_at = now()
  where employee.id = p_employee_id
    and employee.tenant_id = employee_row.tenant_id
    and employee.user_id = p_user_id;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by
  )
  values (
    employee_row.tenant_id,
    p_user_id,
    'employee_erp_identity_unlinked',
    jsonb_build_object(
      'employee_id', p_employee_id,
      'profile_id', profile_row.id
    ),
    caller_user_id
  );

  return jsonb_build_object(
    'success', true,
    'linked', false,
    'userId', p_user_id,
    'employeeId', p_employee_id
  );
end;
$$;

revoke all on function public.unlink_erp_user_from_employee(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.unlink_erp_user_from_employee(uuid, uuid)
  to authenticated;

-- Tenant access removal is one atomic command. If the profile is linked, the
-- canonical unlink runs in the same transaction before the profile is
-- deactivated; any later failure rolls the whole detach back.
create or replace function public.deactivate_and_unlink_erp_user(
  p_user_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  profile_row public.user_profiles%rowtype;
  employee_id_value uuid;
  unlink_receipt jsonb;
begin
  if caller_user_id is null
     or p_user_id is null
     or p_tenant_id is null then
    raise exception 'employee_access_management_denied'
      using errcode = '42501';
  end if;

  if caller_user_id = p_user_id then
    raise exception 'self_detach_forbidden'
      using errcode = '42501';
  end if;

  if not public.can_manage_tenant_users(p_tenant_id) then
    raise exception 'employee_access_management_denied'
      using errcode = '42501';
  end if;

  perform public.lock_auth_membership_identities(null, p_user_id);

  select profile.*
  into profile_row
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = p_user_id
    and profile.tenant_id = p_tenant_id
    and profile.is_active is true
  for update of profile;

  if not found then
    raise exception 'staff_user_not_found'
      using errcode = 'P0001';
  end if;

  perform public.assert_erp_employee_link_actor(
    p_tenant_id,
    p_user_id
  );

  employee_id_value := profile_row.employee_id;
  if employee_id_value is not null then
    unlink_receipt := public.unlink_erp_user_from_employee(
      p_user_id,
      employee_id_value
    );

    if unlink_receipt is null
       or unlink_receipt->>'success' <> 'true'
       or unlink_receipt->>'linked' <> 'false'
       or unlink_receipt->>'userId' <> p_user_id::text
       or unlink_receipt->>'employeeId' <> employee_id_value::text then
      raise exception 'employee_erp_link_state_changed'
        using errcode = 'P0001';
    end if;
  end if;

  update public.user_profiles profile
  set is_active = false,
      updated_at = now()
  where profile.id = profile_row.id
    and profile.user_id = p_user_id
    and profile.tenant_id = p_tenant_id
    and profile.is_active is true;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by
  )
  values (
    p_tenant_id,
    p_user_id,
    'erp_tenant_access_deactivated',
    jsonb_build_object(
      'employee_id', employee_id_value,
      'profile_id', profile_row.id,
      'employee_unlinked', employee_id_value is not null
    ),
    caller_user_id
  );

  return jsonb_build_object(
    'success', true,
    'deactivated', true,
    'unlinked', employee_id_value is not null,
    'userId', p_user_id,
    'employeeId', employee_id_value
  );
end;
$$;

revoke all on function public.deactivate_and_unlink_erp_user(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.deactivate_and_unlink_erp_user(uuid, uuid)
  to authenticated;

-- `inactive` and `terminated` end ERP authority. `on_leave` deliberately keeps
-- access because leave is not separation from employment. Reactivation remains
-- an explicit user-management action.
create or replace function public.deactivate_linked_erp_access_on_employee_exit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  deactivated_profile record;
begin
  if new.status not in ('inactive', 'terminated')
     or new.status is not distinct from old.status then
    return new;
  end if;

  if new.user_id is not null and auth.uid() is not null then
    if new.user_id = auth.uid() then
      raise exception 'self_detach_forbidden'
        using errcode = '42501';
    end if;

    perform public.assert_erp_employee_link_actor(
      new.tenant_id,
      new.user_id
    );
  end if;

  perform public.lock_employee_access_identity(new.id);

  for deactivated_profile in
    update public.user_profiles profile
    set is_active = false,
        updated_at = now()
    where profile.employee_id = new.id
      and profile.tenant_id = new.tenant_id
      and profile.user_id = new.user_id
      and profile.is_active is true
    returning profile.id, profile.user_id
  loop
    insert into public.user_activity_log (
      tenant_id,
      user_id,
      action,
      details,
      performed_by
    )
    values (
      new.tenant_id,
      deactivated_profile.user_id,
      'employee_erp_access_deactivated',
      jsonb_build_object(
        'employee_id', new.id,
        'profile_id', deactivated_profile.id,
        'employee_status', new.status
      ),
      auth.uid()
    );
  end loop;

  return new;
end;
$$;

revoke all on function public.deactivate_linked_erp_access_on_employee_exit()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_deactivate_linked_erp_access_on_employee_exit
  on public.employees;
create trigger trg_deactivate_linked_erp_access_on_employee_exit
  after update of status
  on public.employees
  for each row
  when (old.status is distinct from new.status)
  execute function public.deactivate_linked_erp_access_on_employee_exit();

-- `terminated` is not an ordinary editable status: it is the outcome of the
-- canonical retirement command below. The command marker alone is not trusted
-- because API roles can set custom GUCs; the effective writer must also be the
-- SECURITY DEFINER owner rather than an API role.
create or replace function public.guard_employee_retirement_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.status = 'terminated'
     and new.status is distinct from old.status
     and (
       coalesce(
         current_setting(
           'app.employee_retirement_command',
           true
         ),
         ''
       ) <> 'true'
       or current_user = any (
         array['anon', 'authenticated', 'service_role']::name[]
       )
     ) then
    raise exception 'employee_retirement_requires_canonical_command'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_employee_retirement_transition()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_employee_retirement_transition
  on public.employees;
create trigger trg_guard_employee_retirement_transition
  before update of status
  on public.employees
  for each row
  execute function public.guard_employee_retirement_transition();

-- Employee history is soft-delete-only for application callers. Service-role
-- maintenance retains table privileges, but linked Worker history is guarded
-- even from privileged physical deletion.
drop policy if exists employees_delete_managers
  on public.employees;
revoke delete on table public.employees
  from authenticated;

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
  ) then
    raise exception 'employee_retirement_required'
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

-- Canonical employee retirement preserves HR and Auth history while closing
-- every application authority in one transaction. It is safe to retry: a
-- fully retired row returns alreadyRetired=true without duplicating audit.
create or replace function public.retire_employee(p_employee_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  employee_row public.employees%rowtype;
  audit_user_id uuid;
  prior_status text;
  status_changed boolean;
  portal_accounts integer := 0;
  portal_accounts_restricted integer := 0;
  pending_invitations_expired integer := 0;
  profiles_deactivated integer := 0;
  sessions_revoked integer := 0;
begin
  if caller_user_id is null or p_employee_id is null then
    raise exception 'employee_retirement_denied'
      using errcode = '42501';
  end if;

  perform public.lock_employee_access_identity(p_employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  join public.tenants tenant
    on tenant.id = employee.tenant_id
   and tenant.is_active is true
  where employee.id = p_employee_id
    and public.can_manage_tenant_users(employee.tenant_id)
  for update of employee;

  if not found then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  if employee_row.user_id = caller_user_id then
    raise exception 'self_detach_forbidden'
      using errcode = '42501';
  end if;

  if employee_row.user_id is not null then
    perform public.lock_auth_membership_identities(
      null,
      employee_row.user_id
    );
    perform public.assert_erp_employee_link_actor(
      employee_row.tenant_id,
      employee_row.user_id
    );
  end if;

  prior_status := employee_row.status;
  status_changed := employee_row.status <> 'terminated'
    or employee_row.termination_date is null;

  select count(*)::integer
  into portal_accounts
  from public.employee_portal_accounts portal
  where portal.employee_id = employee_row.id
    and portal.tenant_id = employee_row.tenant_id;

  audit_user_id := employee_row.user_id;
  if audit_user_id is null then
    select portal.auth_user_id
    into audit_user_id
    from public.employee_portal_accounts portal
    where portal.employee_id = employee_row.id
      and portal.tenant_id = employee_row.tenant_id
      and portal.auth_user_id is not null
    order by portal.created_at, portal.id
    limit 1;
  end if;
  audit_user_id := coalesce(audit_user_id, caller_user_id);

  select count(*)::integer
  into portal_accounts_restricted
  from public.employee_portal_accounts portal
  where portal.employee_id = employee_row.id
    and portal.tenant_id = employee_row.tenant_id
    and (
      portal.is_active is distinct from false
      or portal.must_reset_password is distinct from true
      or portal.password_reset_required_at is null
      or portal.password_credential_issued_at is not null
      or portal.password_reset_challenge_started_at is not null
    );

  select count(*)::integer
  into profiles_deactivated
  from public.user_profiles profile
  where profile.employee_id = employee_row.id
    and profile.tenant_id = employee_row.tenant_id
    and profile.is_active is true;

  update public.user_invitations invitation
  set status = 'expired',
      expires_at = least(invitation.expires_at, now()),
      token_hash = null,
      metadata = coalesce(invitation.metadata, '{}'::jsonb)
        - 'invitation_token'
  where invitation.employee_id = employee_row.id
    and invitation.tenant_id = employee_row.tenant_id
    and invitation.status = 'pending';
  get diagnostics pending_invitations_expired = row_count;

  delete from auth.sessions auth_session
  using public.employee_portal_accounts portal
  where portal.employee_id = employee_row.id
    and portal.tenant_id = employee_row.tenant_id
    and portal.auth_user_id = auth_session.user_id;
  get diagnostics sessions_revoked = row_count;

  perform set_config(
    'app.employee_retirement_command',
    'true',
    true
  );
  update public.employees employee
  set status = 'terminated',
      termination_date = coalesce(
        employee.termination_date,
        current_date
      ),
      updated_at = now()
  where employee.id = employee_row.id
    and employee.tenant_id = employee_row.tenant_id
    and (
      employee.status <> 'terminated'
      or employee.termination_date is null
    );
  perform set_config(
    'app.employee_retirement_command',
    '',
    true
  );

  -- Reassert fail-closed state for an already-retired or drifted row. The
  -- ordinary employee-exit triggers may already have applied these changes.
  update public.employee_portal_accounts portal
  set is_active = false,
      must_reset_password = true,
      password_reset_required_at = coalesce(
        portal.password_reset_required_at,
        clock_timestamp()
      ),
      password_credential_issued_at = null,
      password_reset_challenge_started_at = null,
      updated_at = now()
  where portal.employee_id = employee_row.id
    and portal.tenant_id = employee_row.tenant_id
    and (
      portal.is_active is distinct from false
      or portal.must_reset_password is distinct from true
      or portal.password_reset_required_at is null
      or portal.password_credential_issued_at is not null
      or portal.password_reset_challenge_started_at is not null
    );

  update public.user_profiles profile
  set is_active = false,
      updated_at = now()
  where profile.employee_id = employee_row.id
    and profile.tenant_id = employee_row.tenant_id
    and profile.is_active is true;

  if status_changed
     or portal_accounts_restricted > 0
     or pending_invitations_expired > 0
     or profiles_deactivated > 0
     or sessions_revoked > 0 then
    insert into public.user_activity_log (
      tenant_id,
      user_id,
      action,
      details,
      performed_by
    )
    values (
      employee_row.tenant_id,
      audit_user_id,
      'employee_retired',
      jsonb_build_object(
        'employee_id', employee_row.id,
        'previous_status', prior_status,
        'worker_portal_accounts', portal_accounts,
        'worker_portal_accounts_restricted',
          portal_accounts_restricted,
        'pending_invitations_expired',
          pending_invitations_expired,
        'erp_profiles_deactivated', profiles_deactivated,
        'worker_sessions_revoked', sessions_revoked
      ),
      caller_user_id
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'retired', true,
    'alreadyRetired', not (
      status_changed
      or portal_accounts_restricted > 0
      or pending_invitations_expired > 0
      or profiles_deactivated > 0
      or sessions_revoked > 0
    ),
    'employeeId', employee_row.id,
    'previousStatus', prior_status,
    'workerPortalAccounts', portal_accounts,
    'pendingInvitationsExpired', pending_invitations_expired,
    'erpProfilesDeactivated', profiles_deactivated,
    'workerSessionsRevoked', sessions_revoked
  );
end;
$$;

revoke all on function public.retire_employee(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.retire_employee(uuid)
  to authenticated;

-- Internal formatter shared by the two self-service RPCs. It is deliberately
-- not executable by API roles.
create or replace function public.erp_employee_self_json(
  p_user_id uuid,
  p_tenant_id uuid,
  p_employee_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'id', employee.id,
    'employeeNumber', employee.employee_number,
    'firstName', employee.first_name,
    'lastName', employee.last_name,
    'email', employee.email,
    'phone', employee.phone,
    'rut', employee.rut,
    'address', employee.address,
    'city', employee.city,
    'emergencyContactName', employee.emergency_contact_name,
    'emergencyContactPhone', employee.emergency_contact_phone,
    'jobTitle', employee.job_title,
    'departmentId', employee.department_id,
    'departmentName', department.name,
    'status', employee.status,
    'photoUrl', employee.photo_url,
    'updatedAt', employee.updated_at
  )
  from public.employees employee
  left join public.departments department
    on department.id = employee.department_id
   and department.tenant_id = employee.tenant_id
  where employee.id = p_employee_id
    and employee.tenant_id = p_tenant_id
    and employee.user_id = p_user_id
$$;

revoke all on function public.erp_employee_self_json(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.get_my_erp_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  profile_count integer;
  profile_row public.user_profiles%rowtype;
  account_type_value text;
  employee_json jsonb;
  employee_side_count integer;
begin
  if caller_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into profile_count
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true;

  if profile_count <> 1 then
    raise exception 'erp_profile_context_invalid'
      using errcode = 'P0001';
  end if;

  select profile.*
  into profile_row
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true;

  select coalesce(auth_user.raw_app_meta_data->>'account_type', '')
  into account_type_value
  from auth.users auth_user
  where auth_user.id = caller_user_id;

  if not found or account_type_value not in ('erp_owner', 'erp_staff') then
    raise exception 'erp_profile_context_invalid'
      using errcode = 'P0001';
  end if;

  select count(*)::integer
  into employee_side_count
  from public.employees employee
  where employee.user_id = caller_user_id
    and employee.tenant_id = profile_row.tenant_id;

  if profile_row.employee_id is null then
    if employee_side_count <> 0 then
      raise exception 'erp_employee_link_inconsistent'
        using errcode = 'P0001';
    end if;
    employee_json := null;
  else
    employee_json := public.erp_employee_self_json(
      caller_user_id,
      profile_row.tenant_id,
      profile_row.employee_id
    );

    if employee_side_count <> 1
       or employee_json is null
       or exists (
         select 1
         from public.employee_portal_accounts portal
         where portal.employee_id = profile_row.employee_id
           and portal.tenant_id = profile_row.tenant_id
           and portal.is_active is true
       ) then
      raise exception 'erp_employee_link_inconsistent'
        using errcode = 'P0001';
    end if;
  end if;

  return jsonb_build_object(
    'userId', caller_user_id,
    'tenantId', profile_row.tenant_id,
    'profileId', profile_row.id,
    'role', profile_row.role,
    'permissions', coalesce(profile_row.permissions, '{}'::jsonb),
    'employee', employee_json
  );
end;
$$;

revoke all on function public.get_my_erp_profile()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_erp_profile()
  to authenticated;

create or replace function public.update_my_employee_contact(
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  profile_count integer;
  profile_row public.user_profiles%rowtype;
  employee_row public.employees%rowtype;
  account_type_value text;
  patch_key text;
  next_phone text;
  next_address text;
  next_city text;
  next_emergency_name text;
  next_emergency_phone text;
  changed_fields jsonb;
begin
  if caller_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if p_patch is null
     or jsonb_typeof(p_patch) <> 'object'
     or p_patch = '{}'::jsonb then
    raise exception 'invalid_employee_contact_patch'
      using errcode = 'P0001';
  end if;

  for patch_key in
    select key
    from jsonb_object_keys(p_patch) key
  loop
    if patch_key not in (
      'phone',
      'address',
      'city',
      'emergency_contact_name',
      'emergency_contact_phone'
    )
       or jsonb_typeof(p_patch->patch_key) not in ('string', 'null') then
      raise exception 'invalid_employee_contact_patch'
        using errcode = 'P0001';
    end if;
  end loop;

  select count(*)::integer
  into profile_count
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true;

  if profile_count <> 1 then
    raise exception 'erp_profile_context_invalid'
      using errcode = 'P0001';
  end if;

  select coalesce(auth_user.raw_app_meta_data->>'account_type', '')
  into account_type_value
  from auth.users auth_user
  where auth_user.id = caller_user_id;

  if not found or account_type_value not in ('erp_owner', 'erp_staff') then
    raise exception 'erp_profile_context_invalid'
      using errcode = 'P0001';
  end if;

  select profile.*
  into profile_row
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true
  for update of profile;

  if profile_row.employee_id is null then
    raise exception 'erp_employee_link_required'
      using errcode = 'P0001';
  end if;

  perform public.lock_employee_access_identity(profile_row.employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = profile_row.employee_id
    and employee.tenant_id = profile_row.tenant_id
    and employee.user_id = caller_user_id
    and employee.status = 'active'
  for update;

  if not found
     or exists (
       select 1
       from public.employee_portal_accounts portal
       where portal.employee_id = profile_row.employee_id
         and portal.tenant_id = profile_row.tenant_id
         and portal.is_active is true
     ) then
    raise exception 'erp_employee_link_inconsistent'
      using errcode = 'P0001';
  end if;

  next_phone := case
    when p_patch ? 'phone' then nullif(btrim(p_patch->>'phone'), '')
    else employee_row.phone
  end;
  next_address := case
    when p_patch ? 'address' then nullif(btrim(p_patch->>'address'), '')
    else employee_row.address
  end;
  next_city := case
    when p_patch ? 'city' then nullif(btrim(p_patch->>'city'), '')
    else employee_row.city
  end;
  next_emergency_name := case
    when p_patch ? 'emergency_contact_name'
      then nullif(btrim(p_patch->>'emergency_contact_name'), '')
    else employee_row.emergency_contact_name
  end;
  next_emergency_phone := case
    when p_patch ? 'emergency_contact_phone'
      then nullif(btrim(p_patch->>'emergency_contact_phone'), '')
    else employee_row.emergency_contact_phone
  end;

  if length(coalesce(next_phone, '')) > 32
     or length(coalesce(next_address, '')) > 240
     or length(coalesce(next_city, '')) > 120
     or length(coalesce(next_emergency_name, '')) > 160
     or length(coalesce(next_emergency_phone, '')) > 32
     or coalesce(next_phone, '') ~ '[[:cntrl:]]'
     or coalesce(next_address, '') ~ '[[:cntrl:]]'
     or coalesce(next_city, '') ~ '[[:cntrl:]]'
     or coalesce(next_emergency_name, '') ~ '[[:cntrl:]]'
     or coalesce(next_emergency_phone, '') ~ '[[:cntrl:]]' then
    raise exception 'invalid_employee_contact_patch'
      using errcode = 'P0001';
  end if;

  update public.employees employee
  set phone = next_phone,
      address = next_address,
      city = next_city,
      emergency_contact_name = next_emergency_name,
      emergency_contact_phone = next_emergency_phone,
      updated_at = now()
  where employee.id = employee_row.id
    and employee.tenant_id = employee_row.tenant_id
    and employee.user_id = caller_user_id;

  if not found then
    raise exception 'erp_employee_link_inconsistent'
      using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(key order by key), '[]'::jsonb)
  into changed_fields
  from jsonb_object_keys(p_patch) key;

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by
  )
  values (
    employee_row.tenant_id,
    caller_user_id,
    'employee_contact_self_updated',
    jsonb_build_object(
      'employee_id', employee_row.id,
      'changed_fields', changed_fields
    ),
    caller_user_id
  );

  return public.erp_employee_self_json(
    caller_user_id,
    employee_row.tenant_id,
    employee_row.id
  );
end;
$$;

revoke all on function public.update_my_employee_contact(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_my_employee_contact(jsonb)
  to authenticated;

commit;
