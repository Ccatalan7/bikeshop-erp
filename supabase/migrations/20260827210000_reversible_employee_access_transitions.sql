begin;

-- A person may retain historical ERP and Worker identities, but only one of
-- them is authoritative at a time. A typed invitation is the sole exception:
-- it is a pending intent, not an active identity, so Worker Space remains
-- usable until acceptance performs the atomic cut-over.
create or replace function public.is_current_worker_to_erp_invitation(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_metadata jsonb
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(p_metadata #>> '{access_transition,kind}', '') =
           'worker_to_erp'
    and coalesce(p_metadata #>> '{access_transition,employee_id}', '') =
           p_employee_id::text
    and exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.tenant_id = p_tenant_id
        and portal.employee_id = p_employee_id
        and portal.is_active is true
        and portal.id::text = coalesce(
          p_metadata #>> '{access_transition,portal_account_id}',
          ''
        )
        and portal.auth_user_id::text = coalesce(
          p_metadata #>> '{access_transition,worker_auth_user_id}',
          ''
        )
    );
$$;

revoke all on function public.is_current_worker_to_erp_invitation(
  uuid,
  uuid,
  jsonb
) from public, anon, authenticated, service_role;

-- Pending transition invitations coexist only with the exact active Worker
-- identity named in their server-written metadata. Ordinary invitations keep
-- the original XOR guard unchanged.
create or replace function public.guard_erp_invitation_employee_access()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  employee_row public.employees%rowtype;
  active_worker_exists boolean;
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

  select exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = new.employee_id
      and portal.tenant_id = new.tenant_id
      and portal.is_active is true
  ) into active_worker_exists;

  if active_worker_exists
     and not public.is_current_worker_to_erp_invitation(
       new.tenant_id,
       new.employee_id,
       new.metadata
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

-- A typed transition invitation must not make the still-active Worker session
-- unauthoritative. Any other pending invitation remains a fail-closed conflict.
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
      and coalesce(auth_user.raw_app_meta_data->>'account_type', '') =
            'worker_portal'
      and coalesce(auth_user.raw_app_meta_data->>'tenant_id', '') =
            p_tenant_id::text
      and coalesce(auth_user.raw_app_meta_data->>'employee_id', '') =
            p_employee_id::text
      and coalesce(auth_user.raw_app_meta_data->>'role', '') = 'worker'
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
          and not public.is_current_worker_to_erp_invitation(
            invitation.tenant_id,
            invitation.employee_id,
            invitation.metadata
          )
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
  );
$$;

revoke all on function public.is_authoritative_worker_portal_identity(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated, service_role;

-- The row-level identity guard follows the same transition exception. This
-- keeps password rotation and other legitimate Worker maintenance available
-- while an ERP invitation is waiting for its recipient.
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
         and not public.is_current_worker_to_erp_invitation(
           invitation.tenant_id,
           invitation.employee_id,
           invitation.metadata
         )
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

-- Credential preparation for ERP -> Worker stays fail-closed: the Worker row
-- remains inactive while Auth Admin writes the temporary password. Only the
-- final transition command can activate it.
create or replace function public.prepare_worker_transition_credential(
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
    and portal.is_active is false
    and portal.auth_user_id is not null;

  if not found then
    raise exception 'Inactive worker portal account not found'
      using errcode = 'P0002';
  end if;

  return reset_required_at;
end;
$$;

revoke all on function public.prepare_worker_transition_credential(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.prepare_worker_transition_credential(uuid, uuid)
  to service_role;

create or replace function public.finish_worker_transition_credential(
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
    and portal.is_active is false
    and portal.must_reset_password is true
    and portal.password_reset_required_at = p_password_reset_required_at
    and portal.password_credential_issued_at is null
  returning portal.password_credential_issued_at
  into credential_issued_at;

  if not found then
    raise exception 'Worker transition credential state changed'
      using errcode = '40001';
  end if;

  return credential_issued_at;
end;
$$;

revoke all on function public.finish_worker_transition_credential(
  uuid,
  uuid,
  timestamp with time zone
) from public, anon, authenticated, service_role;
grant execute on function public.finish_worker_transition_credential(
  uuid,
  uuid,
  timestamp with time zone
) to service_role;

-- The company principal represents the company and is never a worker record.
create or replace function public.guard_company_principal_employee_link()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.user_id is not null
     and (
       tg_op = 'INSERT'
       or new.user_id is distinct from old.user_id
     )
     and public.is_auth_user_db_backed_tenant_owner(
       new.user_id,
       new.tenant_id
     ) then
    raise exception 'principal_owner_protected'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_company_principal_employee_link()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_company_principal_employee_link
  on public.employees;
create trigger trg_guard_company_principal_employee_link
  before insert or update
  on public.employees
  for each row
  execute function public.guard_company_principal_employee_link();

-- Transfer only open work. Completed/cancelled tasks, their immutable events,
-- messages and creator identity remain historical evidence. The helper runs
-- only from the canonical transition commands below.
create or replace function public.transfer_open_employee_tasks_v1(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_previous_user_id uuid,
  p_next_user_id uuid,
  p_requested_actor uuid,
  p_transition text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  effective_actor uuid;
  previous_sub text := current_setting('request.jwt.claim.sub', true);
  previous_claims text := current_setting('request.jwt.claims', true);
  previous_command text := current_setting('vinabike.smart_task_cmd', true);
  task_row public.smart_tasks%rowtype;
  transferred_count integer := 0;
begin
  if p_tenant_id is null
     or p_employee_id is null
     or p_previous_user_id is null
     or p_next_user_id is null
     or p_previous_user_id = p_next_user_id
     or nullif(btrim(p_transition), '') is null then
    raise exception 'employee_access_transition_invalid'
      using errcode = '22023';
  end if;

  select profile.user_id
  into effective_actor
  from public.user_profiles profile
  where profile.tenant_id = p_tenant_id
    and profile.is_active is true
    and (
      profile.role in ('admin', 'manager')
      or profile.permissions @> '{"manage_users": true}'::jsonb
    )
  order by
    (profile.user_id = p_requested_actor) desc,
    case when profile.role = 'admin' then 0 else 1 end,
    profile.created_at
  limit 1;

  if effective_actor is null then
    raise exception 'employee_access_management_denied'
      using errcode = '42501';
  end if;

  perform public.lock_auth_membership_identities(
    p_previous_user_id,
    p_next_user_id
  );

  perform set_config(
    'request.jwt.claim.sub',
    effective_actor::text,
    true
  );
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', effective_actor)::text,
    true
  );
  perform set_config(
    'vinabike.smart_task_cmd',
    'employee_access_transition',
    true
  );

  for task_row in
    update public.smart_tasks task
    set assigned_to = p_next_user_id,
        updated_at = now()
    where task.tenant_id = p_tenant_id
      and task.assigned_to = p_previous_user_id
      and task.status in ('pending', 'in_progress', 'blocked')
    returning task.*
  loop
    transferred_count := transferred_count + 1;

    insert into public.smart_task_events (
      tenant_id,
      task_id,
      actor_user_id,
      event_type,
      task_version,
      payload
    ) values (
      task_row.tenant_id,
      task_row.id,
      effective_actor,
      'assigned',
      task_row.version,
      jsonb_build_object(
        'source', 'identity_transition',
        'transition', p_transition,
        'employee_id', p_employee_id,
        'assigned_to', p_next_user_id,
        'previous_assignee', p_previous_user_id
      )
    );

    perform public.smart_task_thread_sync_participants(
      task_row,
      p_next_user_id,
      p_previous_user_id
    );
  end loop;

  perform set_config(
    'request.jwt.claim.sub',
    coalesce(previous_sub, ''),
    true
  );
  perform set_config(
    'request.jwt.claims',
    coalesce(previous_claims, ''),
    true
  );
  perform set_config(
    'vinabike.smart_task_cmd',
    coalesce(previous_command, ''),
    true
  );

  return transferred_count;
end;
$$;

revoke all on function public.transfer_open_employee_tasks_v1(
  uuid,
  uuid,
  uuid,
  uuid,
  uuid,
  text
) from public, anon, authenticated, service_role;

-- Immediate Worker -> existing ERP transition. The target ERP profile may be
-- suspended from a previous round-trip and is reactivated atomically.
create or replace function public.switch_worker_to_erp_user(
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
  portal_row public.employee_portal_accounts%rowtype;
  worker_auth_user_id uuid;
  worker_portal_account_id uuid;
  account_type_value text;
  sessions_revoked integer := 0;
  tasks_transferred integer := 0;
begin
  if caller_user_id is null
     or p_user_id is null
     or p_employee_id is null then
    raise exception 'employee_access_management_denied'
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

  select portal.id, portal.auth_user_id
  into worker_portal_account_id, worker_auth_user_id
  from public.employee_portal_accounts portal
  where portal.employee_id = p_employee_id
    and portal.tenant_id = caller_tenant_id
    and portal.is_active is true;

  if not found or worker_auth_user_id is null then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  perform public.assert_erp_employee_link_actor(
    caller_tenant_id,
    p_user_id
  );
  perform public.lock_auth_membership_identities(
    worker_auth_user_id,
    p_user_id
  );
  perform public.lock_employee_access_identity(p_employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = p_employee_id
    and employee.tenant_id = caller_tenant_id
  for update;

  if not found or employee_row.status <> 'active' then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  select profile.*
  into profile_row
  from public.user_profiles profile
  where profile.user_id = p_user_id
    and profile.tenant_id = caller_tenant_id
  for update;

  if not found then
    raise exception 'staff_user_not_found'
      using errcode = 'P0001';
  end if;

  select portal.*
  into portal_row
  from public.employee_portal_accounts portal
  where portal.id = worker_portal_account_id
    and portal.employee_id = p_employee_id
    and portal.tenant_id = caller_tenant_id
    and portal.is_active is true
  for update;

  if not found or portal_row.auth_user_id is null then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  select coalesce(auth_user.raw_app_meta_data->>'account_type', '')
  into account_type_value
  from auth.users auth_user
  where auth_user.id = p_user_id;

  if not found or account_type_value <> 'erp_staff' then
    raise exception 'principal_owner_protected'
      using errcode = '42501';
  end if;

  if employee_row.user_id is not null
     or profile_row.employee_id is not null
     or exists (
       select 1
       from public.user_invitations invitation
       where invitation.employee_id = p_employee_id
         and invitation.tenant_id = caller_tenant_id
         and invitation.status = 'pending'
     ) then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  update public.employee_portal_accounts portal
  set is_active = false,
      updated_at = now()
  where portal.id = portal_row.id
    and portal.is_active is true;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  sessions_revoked := public.revoke_worker_portal_sessions(
    portal_row.id,
    caller_tenant_id
  );

  update public.employees employee
  set user_id = p_user_id,
      updated_at = now()
  where employee.id = p_employee_id
    and employee.tenant_id = caller_tenant_id
    and employee.user_id is null;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  update public.user_profiles profile
  set employee_id = p_employee_id,
      is_active = true,
      updated_at = now()
  where profile.id = profile_row.id
    and profile.employee_id is null;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  tasks_transferred := public.transfer_open_employee_tasks_v1(
    caller_tenant_id,
    p_employee_id,
    portal_row.auth_user_id,
    p_user_id,
    caller_user_id,
    'worker_to_erp_direct'
  );

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by
  ) values (
    caller_tenant_id,
    p_user_id,
    'employee_access_switched_worker_to_erp',
    jsonb_build_object(
      'employee_id', p_employee_id,
      'worker_auth_user_id', portal_row.auth_user_id,
      'worker_portal_account_id', portal_row.id,
      'tasks_transferred', tasks_transferred,
      'worker_sessions_revoked', sessions_revoked
    ),
    caller_user_id
  );

  return jsonb_build_object(
    'success', true,
    'linked', true,
    'userId', p_user_id,
    'employeeId', p_employee_id,
    'accessMode', 'erp',
    'tasksTransferred', tasks_transferred,
    'sessionsRevoked', sessions_revoked
  );
end;
$$;

revoke all on function public.switch_worker_to_erp_user(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.switch_worker_to_erp_user(uuid, uuid)
  to authenticated;

-- ERP -> Worker mirror. Edge prepares an inactive Worker credential first;
-- this transaction unlinks and suspends ERP, activates the prepared portal,
-- revokes ERP sessions and moves open work with no dual-authority instant.
create or replace function public.switch_erp_user_to_worker(
  p_user_id uuid,
  p_employee_id uuid,
  p_portal_account_id uuid
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
  portal_row public.employee_portal_accounts%rowtype;
  worker_auth_user_id uuid;
  worker_metadata jsonb;
  sessions_revoked integer := 0;
  tasks_transferred integer := 0;
begin
  if caller_user_id is null
     or p_user_id is null
     or p_employee_id is null
     or p_portal_account_id is null
     or caller_user_id = p_user_id then
    raise exception 'employee_access_management_denied'
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

  select portal.auth_user_id
  into worker_auth_user_id
  from public.employee_portal_accounts portal
  where portal.id = p_portal_account_id
    and portal.employee_id = p_employee_id
    and portal.tenant_id = caller_tenant_id;

  if not found or worker_auth_user_id is null then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  perform public.assert_erp_employee_link_actor(
    caller_tenant_id,
    p_user_id
  );
  perform public.lock_auth_membership_identities(
    p_user_id,
    worker_auth_user_id
  );
  perform public.lock_employee_access_identity(p_employee_id);

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = p_employee_id
    and employee.tenant_id = caller_tenant_id
  for update;

  select profile.*
  into profile_row
  from public.user_profiles profile
  where profile.user_id = p_user_id
    and profile.tenant_id = caller_tenant_id
  for update;

  select portal.*
  into portal_row
  from public.employee_portal_accounts portal
  where portal.id = p_portal_account_id
    and portal.employee_id = p_employee_id
    and portal.tenant_id = caller_tenant_id
  for update;

  if employee_row.id is null
     or employee_row.status <> 'active'
     or profile_row.id is null
     or portal_row.id is null
     or portal_row.auth_user_id is null
     or portal_row.is_active is true
     or employee_row.user_id is distinct from p_user_id
     or profile_row.employee_id is distinct from p_employee_id
     or profile_row.is_active is not true
     or portal_row.must_reset_password is not true
     or portal_row.password_credential_issued_at is null then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  if public.is_auth_user_db_backed_tenant_owner(
    p_user_id,
    caller_tenant_id
  ) then
    raise exception 'principal_owner_protected'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.user_invitations invitation
    where invitation.employee_id = p_employee_id
      and invitation.tenant_id = caller_tenant_id
      and invitation.status = 'pending'
  ) then
    raise exception 'employee_erp_link_conflict'
      using errcode = 'P0001';
  end if;

  select coalesce(auth_user.raw_app_meta_data, '{}'::jsonb)
  into worker_metadata
  from auth.users auth_user
  where auth_user.id = portal_row.auth_user_id
    and auth_user.banned_until is null;

  if not found
     or coalesce(worker_metadata->>'account_type', '') <> 'worker_portal'
     or coalesce(worker_metadata->>'tenant_id', '') <>
          caller_tenant_id::text
     or coalesce(worker_metadata->>'employee_id', '') <>
          p_employee_id::text
     or coalesce(worker_metadata->>'role', '') <> 'worker' then
    raise exception 'worker_identity_conflict'
      using errcode = 'P0001';
  end if;

  update public.user_profiles profile
  set employee_id = null,
      is_active = false,
      updated_at = now()
  where profile.id = profile_row.id
    and profile.employee_id = p_employee_id
    and profile.is_active is true;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  update public.employees employee
  set user_id = null,
      updated_at = now()
  where employee.id = p_employee_id
    and employee.tenant_id = caller_tenant_id
    and employee.user_id = p_user_id;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  update public.employee_portal_accounts portal
  set is_active = true,
      updated_at = now()
  where portal.id = portal_row.id
    and portal.is_active is false;

  if not found then
    raise exception 'employee_erp_link_state_changed'
      using errcode = 'P0001';
  end if;

  delete from auth.sessions auth_session
  where auth_session.user_id = p_user_id;
  get diagnostics sessions_revoked = row_count;

  tasks_transferred := public.transfer_open_employee_tasks_v1(
    caller_tenant_id,
    p_employee_id,
    p_user_id,
    portal_row.auth_user_id,
    caller_user_id,
    'erp_to_worker'
  );

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by
  ) values (
    caller_tenant_id,
    p_user_id,
    'employee_access_switched_erp_to_worker',
    jsonb_build_object(
      'employee_id', p_employee_id,
      'worker_auth_user_id', portal_row.auth_user_id,
      'worker_portal_account_id', portal_row.id,
      'tasks_transferred', tasks_transferred,
      'erp_sessions_revoked', sessions_revoked
    ),
    caller_user_id
  );

  return jsonb_build_object(
    'success', true,
    'linked', false,
    'userId', p_user_id,
    'employeeId', p_employee_id,
    'accessMode', 'worker',
    'portalAccountId', portal_row.id,
    'workerAuthUserId', portal_row.auth_user_id,
    'tasksTransferred', tasks_transferred,
    'sessionsRevoked', sessions_revoked
  );
end;
$$;

revoke all on function public.switch_erp_user_to_worker(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.switch_erp_user_to_worker(uuid, uuid, uuid)
  to authenticated;

-- Invitation acceptance now recognizes the typed Worker -> ERP intent. The
-- ordinary path is unchanged; the transition path deactivates Worker only
-- after the new ERP identity has proved its email and invitation token.
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
  portal_row public.employee_portal_accounts%rowtype;
  external_profile_count integer;
  same_tenant_profile_active boolean;
  same_tenant_profile_exists boolean;
  transition_is_worker_to_erp boolean := false;
  worker_portal_account_id uuid;
  worker_auth_user_id uuid;
  worker_sessions_revoked integer := 0;
  tasks_transferred integer := 0;
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

  transition_is_worker_to_erp :=
    invitation_row.employee_id is not null
    and coalesce(
      invitation_row.metadata #>> '{access_transition,kind}',
      ''
    ) = 'worker_to_erp';

  if transition_is_worker_to_erp then
    select portal.*
    into portal_row
    from public.employee_portal_accounts portal
    where portal.tenant_id = invitation_row.tenant_id
      and portal.employee_id = invitation_row.employee_id
      and portal.id::text = coalesce(
        invitation_row.metadata #>>
          '{access_transition,portal_account_id}',
        ''
      )
      and portal.auth_user_id::text = coalesce(
        invitation_row.metadata #>>
          '{access_transition,worker_auth_user_id}',
        ''
      );

    if not found or portal_row.auth_user_id is null then
      raise exception 'employee_erp_link_state_changed'
        using errcode = 'P0001';
    end if;
    worker_portal_account_id := portal_row.id;
    worker_auth_user_id := portal_row.auth_user_id;
  end if;

  perform public.lock_auth_membership_identities(
    coalesce(worker_auth_user_id, invitation_row.tenant_id),
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

    if transition_is_worker_to_erp then
      select portal.*
      into portal_row
      from public.employee_portal_accounts portal
      where portal.id = worker_portal_account_id
        and portal.tenant_id = invitation_row.tenant_id
        and portal.employee_id = invitation_row.employee_id
        and portal.auth_user_id = worker_auth_user_id
        and portal.is_active is true
      for update;

      if not found
         or not public.is_current_worker_to_erp_invitation(
           invitation_row.tenant_id,
           invitation_row.employee_id,
           invitation_row.metadata
         ) then
        raise exception 'employee_erp_link_state_changed'
          using errcode = 'P0001';
      end if;

      update public.employee_portal_accounts portal
      set is_active = false,
          updated_at = now()
      where portal.id = portal_row.id
        and portal.is_active is true;

      if not found then
        raise exception 'employee_erp_link_state_changed'
          using errcode = 'P0001';
      end if;

      worker_sessions_revoked := public.revoke_worker_portal_sessions(
        portal_row.id,
        invitation_row.tenant_id
      );
    elsif exists (
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
  ) values (
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

  if transition_is_worker_to_erp then
    tasks_transferred := public.transfer_open_employee_tasks_v1(
      invitation_row.tenant_id,
      invitation_row.employee_id,
      worker_auth_user_id,
      auth_user_id_value,
      invitation_row.invited_by,
      'worker_to_erp_invitation'
    );
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

  if transition_is_worker_to_erp then
    insert into public.user_activity_log (
      tenant_id,
      user_id,
      action,
      details,
      performed_by
    ) values (
      invitation_row.tenant_id,
      auth_user_id_value,
      'employee_access_switched_worker_to_erp',
      jsonb_build_object(
        'employee_id', invitation_row.employee_id,
        'worker_auth_user_id', worker_auth_user_id,
        'worker_portal_account_id', portal_row.id,
        'invitation_id', invitation_row.id,
        'tasks_transferred', tasks_transferred,
        'worker_sessions_revoked', worker_sessions_revoked
      ),
      invitation_row.invited_by
    );
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

commit;
