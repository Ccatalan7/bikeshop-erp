-- Read-back of 20261103100000. Fails before the migration and passes after:
-- reponer una marca quitada ya no la vuelve «manual» ni borra su evidencia.

select 1 / (case when
  has_function_privilege('authenticated',
    'public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)', 'EXECUTE')
  and pg_get_functiondef('public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)'::regprocedure)
    not like '%else ''manual'' end%'
  and pg_get_functiondef('public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)'::regprocedure)
    not like '%else ''{}''::jsonb end%'
then 1 else 0 end) as afirma_reponer_conserva_origen;
