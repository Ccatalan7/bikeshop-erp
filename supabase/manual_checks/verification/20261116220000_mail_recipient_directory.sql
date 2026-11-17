-- Read-back de 20261116220000_mail_recipient_directory.
-- Sólo `select` planos: la lectura remota corre el archivo en una sola
-- transacción de sólo lectura, y cada uno revienta si falta la definición o
-- si el invariante no se cumple. La libreta se lee como un administrador del
-- taller y sólo se imprimen unos: ninguna dirección sale en la salida.

-- 1. La función existe, sólo lee y corre como su dueño con la ruta fija.
select 1 / (count(*) = 1)::int as funcion_definer_estable
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.mail_recipient_directory_v1()')
   and p.prosecdef
   and p.provolatile = 's'
   and array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public%';

-- 2. La llama una sesión del ERP (la función exige personal del taller);
--    nadie sin sesión.
select 1 / (
  has_function_privilege('authenticated', 'public.mail_recipient_directory_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_recipient_directory_v1()', 'EXECUTE')
)::int as solo_con_sesion;

-- 3. Como un administrador activo del taller: una fila por dirección, todas
--    válidas, con los proveedores (24 direcciones al 2026-11-16) y los
--    clientes (83).
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
  and not exists (
    select 1 from libreta
     where entry->>'address' !~ '^[^[:space:]@,;<>"]+@[^[:space:]@,;<>"]+\.[^[:space:]@,;<>"]+$')
  and not exists (
    select 1 from libreta where entry->>'kind' not in ('supplier', 'customer', 'sent'))
  and (select count(*) from libreta where entry->>'kind' = 'supplier') >= 20
  and (select count(*) from libreta where entry->>'kind' = 'customer') >= 70
)::int as libreta_del_taller;
