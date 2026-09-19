-- Un bloqueo vencido no es un bloqueo: las dos puertas que faltaban.
--
-- `20260919210000` restauró en `is_authoritative_worker_portal_identity` la
-- forma que `20260728010000` tenía —«sin bloqueo **o** ya venció»— y que
-- `20260827210000` perdió al reescribir la identidad. Revisando las demás
-- puertas, cuatro ya la conservaban (`erp_member_tenant_id`,
-- `current_erp_employee_id` y los dos directorios: ahí `banned_until is null`
-- es sólo la primera mitad de la condición completa, y buscar esa frase las
-- señala en falso). Quedaban dos escritas al revés, en la misma migración de
-- agosto:
--
--   * `guard_worker_portal_identity`, el trigger que valida la cuenta de
--     portal: con un bloqueo vencido no se podía ni tocar la cuenta del
--     trabajador para arreglarla.
--   * `switch_erp_user_to_worker`, que convierte un usuario ERP en
--     trabajador: comprueba el bloqueo de la identidad Worker destino, y con
--     una vencida abortaba la transición.
--
-- Supabase Auth deja entrar cuando `banned_until` ya pasó, así que la forma
-- estricta dejaba a la persona autenticada y sin arreglo posible desde el
-- ERP. Un bloqueo **vigente** sigue cerrando ambas puertas.
--
-- Cuidado que esto no resuelve: un bloqueo temporal no es una suspensión.
-- Si a alguien se le quita el acceso de verdad, eso va en los estados
-- (`user_profiles.is_active`, `employees.status`, la cuenta de portal), no en
-- una fecha que vence sola.
--
-- Firmas y privilegios sin cambios.


CREATE OR REPLACE FUNCTION public.guard_worker_portal_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'pg_temp'
AS $function$
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
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    );

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
$function$;

CREATE OR REPLACE FUNCTION public.switch_erp_user_to_worker(p_user_id uuid, p_employee_id uuid, p_portal_account_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'pg_temp'
AS $function$
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
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    );

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
$function$;
