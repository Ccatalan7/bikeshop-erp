-- Un bloqueo temporal vencido no deja al trabajador fuera para siempre.
--
-- `20260728010000` decía «banned_until is null **o** ya venció»; al reescribir
-- la identidad para las transiciones reversibles, `20260827210000` se quedó
-- sólo con la primera mitad, y cualquier bloqueo —aunque hubiera expirado—
-- cerraba el Portal del Trabajador para siempre. Supabase, en cambio, lo deja
-- volver a entrar: quedaba autenticado y sin acceso.
--
-- Lo encontró la prueba 67 de `hr_payroll_authorization_hardening.sql`, que
-- lleva fallando desde ese día.
--
-- Otras seis funciones comparten la comprobación estricta
-- (`erp_member_tenant_id`, `current_erp_employee_id`,
-- `guard_worker_portal_identity`, `switch_erp_user_to_worker` y los dos
-- directorios). Esa es una decisión de seguridad más ancha, con su propio
-- alcance: se deja anotada, no se cambia de paso.
--
-- Firma y privilegios sin cambios.

CREATE OR REPLACE FUNCTION public.is_authoritative_worker_portal_identity(p_user_id uuid, p_tenant_id uuid, p_employee_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'pg_temp'
AS $function$
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
      -- A ban that already expired is not a ban: Supabase lets the
      -- worker log in again, and 20260728010000 said so until
      -- 20260827210000 dropped the clause while rewriting identity.
      and (
        auth_user.banned_until is null
        or auth_user.banned_until <= statement_timestamp()
      )
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
$function$;
