-- Read-back de 20261116230000_mail_recipient_directory_faces.
-- Sólo `select` planos: la lectura remota corre el archivo en una sola
-- transacción de sólo lectura, y cada uno revienta si falta la definición o
-- si el invariante no se cumple. La libreta se lee como un administrador del
-- taller y sólo se imprimen unos: ninguna dirección ni logo sale en la salida.

-- 1. La definición nueva entrega el logo y sigue sólo leyendo, como su dueño
--    y con la ruta fija.
select 1 / (count(*) = 1)::int as funcion_con_logo
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.mail_recipient_directory_v1()')
   and p.prosecdef
   and p.provolatile = 's'
   and array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%'
   and pg_get_functiondef(p.oid) like '%''logo'', m.logo%';

-- 2. Sigue siendo sólo para una sesión del ERP.
select 1 / (
  has_function_privilege('authenticated', 'public.mail_recipient_directory_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_recipient_directory_v1()', 'EXECUTE')
)::int as solo_con_sesion;

-- 3. Como un administrador activo del taller: los proveedores con correo
--    traen su logo (23 de 23 al 2026-11-16) y la libreta no cambió de forma.
select 1 / (length(set_config('request.jwt.claim.sub', (
  select profile.user_id::text
    from public.user_profiles profile
    join public.tenants tenant on tenant.id = profile.tenant_id
   where tenant.subdomain = 'vinabike'
     and profile.role = 'admin'
     and profile.is_active
   order by profile.user_id
   limit 1
), true)) = 36)::int as sesion_del_taller;

select 1 / (length(set_config('request.jwt.claims',
  json_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated')::text,
  true)) > 0)::int as claims_del_taller;

with libreta as (
  select entry
    from jsonb_array_elements(public.mail_recipient_directory_v1()) as book(entry)
)
select 1 / (
  (select count(*) from libreta) = (select count(distinct entry->>'address') from libreta)
  and (select count(*) from libreta where entry->>'kind' = 'supplier' and entry ? 'logo') >= 20
  and (select count(*) from libreta where entry->>'kind' = 'customer') >= 70
)::int as libreta_con_logos;
