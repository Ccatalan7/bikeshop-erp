-- Read-back de 20260924020000_gama_costs_and_pgtap_leave_the_api.
-- Antes de desplegar tiene que fallar contra producción: anónimo lee la gama
-- y pgTAP vive en `public`.

select c.relname as relacion,
       has_table_privilege('anon', c.oid, 'SELECT') as anon,
       has_table_privilege('authenticated', c.oid, 'SELECT') as con_sesion,
       has_table_privilege('service_role', c.oid, 'SELECT') as servicio
  from pg_class c
 where c.oid in ('public.product_gama_bands_mv'::regclass,
                 'public.product_gama_v1'::regclass)
 order by 1;

select 1 / (case when
  not has_table_privilege('anon', 'public.product_gama_bands_mv', 'SELECT')
  and not has_table_privilege('authenticated', 'public.product_gama_bands_mv', 'SELECT')
  and not has_table_privilege('anon', 'public.product_gama_v1', 'SELECT')
  and not has_table_privilege('authenticated', 'public.product_gama_v1', 'SELECT')
then 1 else 0 end) as gama_sin_clientes;

-- Los consumidores siguen siendo SECURITY DEFINER sin permiso de cliente.
select 1 / (count(*) = 3)::integer as consumidores_definer
  from pg_proc p
 where p.oid in (
         'public.purchase_candidate_scores_internal_v1'::regproc,
         'public.purchase_supplier_concentration_internal_v1'::regproc,
         'public.refresh_product_gama_bands_v1'::regproc)
   and p.prosecdef;

select e.extname, e.extversion, e.extnamespace::regnamespace::text as esquema
  from pg_extension e
 where e.extname = 'pgtap';

select 1 / (case when
  (select extnamespace from pg_extension where extname = 'pgtap')
    = 'extensions'::regnamespace
  and to_regprocedure('public.lives_ok(text)') is null
  and to_regclass('public.tap_funky') is null
  and to_regclass('public.pg_all_foreign_keys') is null
  and to_regprocedure('extensions.lives_ok(text)') is not null
then 1 else 0 end) as pgtap_fuera_de_la_api;
