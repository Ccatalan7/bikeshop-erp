-- Read-back of 20261103110000. Fails before the migration and passes after:
-- las dos lecturas cuentan compras como documentos.

select 1 / (case when
  pg_get_functiondef('public.supplier_brands_v1(uuid, uuid)'::regprocedure)
    like '%count(distinct pi.id)%'
  and pg_get_functiondef('public.supplier_brands_v1(uuid, uuid)'::regprocedure)
    like '%''purchases''%'
  and pg_get_functiondef('public.brand_suppliers_v1(uuid, uuid)'::regprocedure)
    like '%count(distinct pi.id)%'
  and has_function_privilege('authenticated', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.brand_suppliers_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.brand_suppliers_v1(uuid, uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_compras_son_documentos;
