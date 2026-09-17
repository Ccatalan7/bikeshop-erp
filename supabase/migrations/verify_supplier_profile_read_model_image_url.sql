-- Read-back: la vista del directorio expone image_url y sigue siendo invoker.

select case
  when (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_profile_read_model'
      and column_name = 'image_url'
  ) = 1
  then 'ok: la vista expone image_url'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as columna;

select case
  when (
    select count(*) from pg_class
    where relname = 'supplier_profile_read_model'
      and 'security_invoker=true' = any(reloptions)
  ) = 1
  then 'ok: sigue siendo security_invoker'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as invoker;

select case
  when has_table_privilege('authenticated', 'public.supplier_profile_read_model', 'select')
  then 'ok: la app la sigue leyendo'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as permisos;
