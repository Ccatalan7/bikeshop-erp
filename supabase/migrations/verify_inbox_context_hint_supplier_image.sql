-- Read-back: el payload de proveedores trae image_url.
--
-- Sin bloques `do $$` y sin constantes plegables: un read-back corre por la
-- ruta de lectura remota (ver AGENT_DATABASE_CONTRACT.md, 2026-08-19).

-- 1. La función sigue existiendo con la misma firma.
select case
  when to_regprocedure(
         'public.inbox_context_hint_rows_v1(uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])'
       )::oid is not null
  then 'ok: la funcion existe con su firma'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as firma;

-- 2. El CTE de proveedores proyecta image_url.
select case
  when (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'inbox_context_hint_rows_v1'
      and p.prosrc like '%s.sales_rep_name, s.is_active, s.image_url%'
  ) = 1
  then 'ok: el payload de proveedores incluye image_url'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as columna;

-- 3. Y sigue siendo la misma clase de función: estable y security definer.
select case
  when (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'inbox_context_hint_rows_v1'
      and p.provolatile = 's'
      and p.prosecdef
  ) = 1
  then 'ok: stable security definer, sin cambios'
  else (select (1 / count(*))::text from pg_class where relname = '__no_existe__')
end as clase;
