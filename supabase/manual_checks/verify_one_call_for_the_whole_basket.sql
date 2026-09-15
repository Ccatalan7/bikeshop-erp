-- Read-back: la canasta existe con sus dos puertas, el motor no está expuesto,
-- y la decisión de repartir se calcula en la base.
select
  1 / (case when has_function_privilege('authenticated',
    'public.assistant_rank_basket_suppliers_v1(jsonb,integer)', 'execute')
    then 1 else 0 end) as puerta_ia,
  1 / (case when has_function_privilege('authenticated',
    'public.rank_basket_suppliers_v1(jsonb,integer)', 'execute')
    then 1 else 0 end) as puerta_modulo,
  1 / (case when not has_function_privilege('authenticated',
    'public.purchase_basket_supplier_coverage_internal_v1(uuid,jsonb,integer)',
    'execute') then 1 else 0 end) as motor_no_expuesto,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_basket_supplier_coverage_internal_v1'
  ) like '%complementSupplierName%' then 1 else 0 end) as decide_el_reparto,
  -- Una canasta de una línea no es una canasta: para eso está la herramienta
  -- de una sola frase, que es más barata.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_basket_supplier_coverage_internal_v1'
  ) like '%< 2%' then 1 else 0 end) as exige_dos_lineas;
