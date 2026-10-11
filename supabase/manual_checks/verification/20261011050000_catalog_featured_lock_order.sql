-- Read-back de 20261011050000: destacados toma las filas antes del candado.

select 1 / case
  when position('for share of p' in pg_get_functiondef('public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure))
       < position('pg_advisory_xact_lock' in pg_get_functiondef('public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure))
   and position('for share of p' in pg_get_functiondef('public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure)) > 0
   and not has_function_privilege('anon', 'public.catalog_replace_featured_v1(uuid,uuid[])', 'execute')
  then 1 else 0
end as assert_rows_before_featured_lock;
