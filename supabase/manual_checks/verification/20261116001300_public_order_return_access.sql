-- Read-back de 20261116001300_public_order_return_access.
-- Sólo `select` planos (corre en lectura remota): cada uno revienta si falta
-- la definición o si el invariante no se cumple. Ninguno emite un acceso: el
-- único llamado usa una preferencia que no es la del pedido.

-- 1. La función existe con su firma.
select 1 / (
  to_regprocedure('public.issue_public_online_order_return_access_v1(uuid,text)') is not null
)::int as funcion_existe;

-- 2. Corre como su dueño, con la ruta de búsqueda fija.
select 1 / (count(*) = 1)::int as definer_con_ruta_fija
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.issue_public_online_order_return_access_v1(uuid,text)')
   and p.prosecdef
   and array_to_string(p.proconfig, ',')
       like '%search_path=pg_catalog, public, extensions, pg_temp%';

-- 3. La llama la página del pedido sin sesión; emitir un acceso cualquiera
--    sigue siendo sólo del servidor.
select 1 / (
  has_function_privilege('anon',
    'public.issue_public_online_order_return_access_v1(uuid,text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.issue_public_online_order_return_access_v1(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.issue_online_order_access_token(uuid,text[],timestamp with time zone)', 'EXECUTE')
)::int as llamable_sin_sesion;

-- 4. Con el último pedido real de Mercado Pago y una preferencia que no es la
--    suya, no abre nada (y recorre las tablas reales sin error).
select 1 / (
  public.issue_public_online_order_return_access_v1(
    (
      select o.id
        from public.online_orders o
       where o.tenant_id = (select t.id from public.tenants t where t.subdomain = 'vinabike')
         and o.payment_method = 'mercadopago'
       order by o.created_at desc
       limit 1
    ),
    '1234567890-00000000-0000-4000-8000-000000000000'
  ) is null
)::int as preferencia_ajena_no_abre;
