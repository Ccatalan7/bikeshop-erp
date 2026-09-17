-- Read-back: la RPC existe, es security definer y la puede ejecutar la app.

select case
  when to_regprocedure('public.update_supplier_image_url(uuid,uuid,text)')::oid is not null
  then 'ok: la funcion existe con su firma'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as firma;

select case
  when (
    select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'update_supplier_image_url'
      and p.prosecdef
  ) = 1
  then 'ok: security definer'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as definer;

select case
  when has_function_privilege(
         'authenticated',
         'public.update_supplier_image_url(uuid,uuid,text)',
         'execute'
       )
   and not has_function_privilege(
         'public',
         'public.update_supplier_image_url(uuid,uuid,text)',
         'execute'
       )
  then 'ok: authenticated ejecuta, public no'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as permisos;

-- Y la tabla sigue cerrada al cliente: la RPC es el único camino.
select case
  when not has_table_privilege('authenticated', 'public.suppliers', 'update')
  then 'ok: authenticated no escribe la tabla directo'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as tabla_cerrada;
