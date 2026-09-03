-- Read-back de `20260902220000_supplier_sales_rep_is_editable_again`.
-- Cada bloque divide por cero si lo que afirma no está: corrido ANTES de la
-- migración tiene que fallar; después, pasar.

-- 1. El comando existe con su firma exacta, es security definer y volátil.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as el_comando_existe_con_su_firma
from pg_proc p
where p.oid = to_regprocedure(
  'public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)'
)
  and p.prosecdef
  and p.provolatile = 'v';

-- 2. Sólo authenticated y service_role lo ejecutan; ni anon ni PUBLIC.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as anon_y_public_no_lo_ejecutan
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'update_supplier_sales_rep'
  and grantee in ('anon', 'PUBLIC');

select 1 / (
  case when has_function_privilege(
    'authenticated',
    'public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  ) then 1 else 0 end
) as authenticated_lo_ejecuta;

-- 3. Los recibos son privados: RLS activa y ningún privilegio de tabla para
--    authenticated. Sólo el comando (security definer) los escribe y lee.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as recibos_con_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'supplier_sales_rep_command_receipts'
  and c.relrowsecurity;

select 1 / (
  case when has_table_privilege(
    'authenticated',
    'public.supplier_sales_rep_command_receipts',
    'SELECT'
  ) then 0 else 1 end
) as authenticated_no_lee_recibos;

-- 4. El cuerpo escribe las tres columnas del vendedor y nada más del
--    proveedor: se afirma sobre la definición real.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as escribe_solo_al_vendedor
from pg_proc p
where p.oid = to_regprocedure(
  'public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)'
)
  and pg_get_functiondef(p.oid) like '%set sales_rep_name = v_name%'
  and pg_get_functiondef(p.oid) like '%sales_rep_phone = v_phone%'
  and pg_get_functiondef(p.oid) like '%sales_rep_email = v_email%'
  and pg_get_functiondef(p.oid) not like '%set phone =%'
  and pg_get_functiondef(p.oid) not like '%contact_person =%';

-- 5. La ruta real resuelve: sin contexto de negocio muere en 42501 (guarda de
--    tenant), no en 42883 (no existiría) ni 42725 (firma ambigua).
explain (costs off)
select public.update_supplier_sales_rep(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  null::timestamptz,
  '00000000-0000-0000-0000-000000000000'::uuid,
  '{"name":null,"phone":null,"email":null}'::jsonb
);
