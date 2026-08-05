-- 20260805180000_self_heal_erp_account_stamp.sql
--
-- Por qué existe: el 2026-08-05 un administrador recién invitado quedó fuera
-- del ERP con su perfil perfecto. La transacción de verificación de correo
-- selló `account_type='erp_staff'` en `auth.users.raw_app_meta_data` a las
-- 17:03:07.992 (trigger de aceptación); ~1 s después una escritura del propio
-- GoTrue reescribió la fila con la copia leída ANTES de esa transacción y el
-- sello desapareció, resucitando `pending_invitation_token_hash`. Con el sello
-- ausente, `get_my_erp_profile_internal()` rechaza con
-- `erp_profile_context_invalid` y toda la app queda en «No pudimos validar tu
-- acceso».
--
-- Principio (ya declarado en canonical-ui-surfaces): los metadatos mutables de
-- Auth nunca son autoridad. La autoridad es la fila activa de
-- `user_profiles` en un tenant activo; el sello es estado DERIVADO. Por lo
-- tanto un sello AUSENTE con exactamente un perfil activo se repara aquí
-- mismo, en el punto de entrada que el cliente ya llama. Un sello EN
-- CONFLICTO (customer, worker_portal, …) sigue siendo deriva de identidad y
-- sigue fallando cerrado — esta migración no convierte identidades.
--
-- La función pierde STABLE porque la reparación escribe; el cliente la invoca
-- por RPC (POST), donde la volatilidad es válida. Los grants existentes se
-- conservan (CREATE OR REPLACE no toca ACLs).
--
-- Estado de despliegue: aplicada a producción el 2026-08-05 vía
-- `scripts/db/query.sh production --write --file` y verificada con read-back
-- de `pg_get_functiondef` + pgTAP local `erp_account_stamp_self_heal.sql`.

create or replace function public.get_my_erp_profile()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  caller_user_id uuid := auth.uid();
  claimed_account_type text;
  auth_email text;
  owner_email_value text;
  active_profile_count integer;
  profile_row public.user_profiles%rowtype;
begin
  if exists (
    select 1
    from auth.users auth_user
    where auth_user.id = caller_user_id
      and auth_user.banned_until > statement_timestamp()
  ) then
    raise exception 'ERP profile access denied'
      using errcode = '42501';
  end if;

  -- Auto-reparación del sello derivado. Sólo cuando el sello está VACÍO y la
  -- base prueba una única identidad ERP activa; nunca sobre un sello ajeno.
  if caller_user_id is not null then
    select coalesce(auth_user.raw_app_meta_data->>'account_type', ''),
           lower(nullif(trim(auth_user.email), ''))
    into claimed_account_type, auth_email
    from auth.users auth_user
    where auth_user.id = caller_user_id;

    if found and claimed_account_type = '' then
      select count(*)::integer
      into active_profile_count
      from public.user_profiles profile
      join public.tenants tenant
        on tenant.id = profile.tenant_id
       and tenant.is_active is true
      where profile.user_id = caller_user_id
        and profile.is_active is true;

      if active_profile_count = 1 then
        select profile.*
        into profile_row
        from public.user_profiles profile
        join public.tenants tenant
          on tenant.id = profile.tenant_id
         and tenant.is_active is true
        where profile.user_id = caller_user_id
          and profile.is_active is true;

        select lower(nullif(trim(tenant.owner_email), ''))
        into owner_email_value
        from public.tenants tenant
        where tenant.id = profile_row.tenant_id;

        -- El hash pendiente que sobrevive a una invitación ya consumida es
        -- basura del mismo choque; se retira junto con la reparación.
        update auth.users
        set raw_app_meta_data = (
              coalesce(raw_app_meta_data, '{}'::jsonb)
              - 'pending_invitation_token_hash'
            ) || jsonb_build_object(
              'account_type',
              case
                when auth_email is not null
                     and auth_email = owner_email_value
                  then 'erp_owner'
                else 'erp_staff'
              end,
              'tenant_id', profile_row.tenant_id,
              'role', profile_row.role
            )
        where id = caller_user_id;
      end if;
    end if;
  end if;

  return public.get_my_erp_profile_internal();
end;
$$;
