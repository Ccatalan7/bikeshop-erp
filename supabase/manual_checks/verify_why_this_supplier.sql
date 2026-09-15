-- Read-back: la evidencia usa el MISMO resolvedor que el ranking, distingue
-- compra de catálogo, y publica el peso de cada métrica.
select
  1 / (case when has_function_privilege('authenticated',
    'public.purchase_supplier_evidence_v1(uuid,jsonb,integer)', 'execute')
    then 1 else 0 end) as modulo_ejecuta,
  1 / (case when (
    select prosrc from pg_proc where proname = 'purchase_supplier_evidence_v1'
  ) like '%purchase_query_products_internal_v1%' then 1 else 0 end)
    as mismo_resolvedor,
  -- El catálogo NO es historial: va en su propia clave y sólo cuando no hay
  -- compras de esa línea.
  1 / (case when (
    select prosrc from pg_proc where proname = 'purchase_supplier_evidence_v1'
  ) like '%''catalog'', v_stock%' then 1 else 0 end) as catalogo_aparte,
  1 / (case when (
    select prosrc from pg_proc where proname = 'purchase_supplier_evidence_v1'
  ) like '%''weights'', jsonb_build_object%' then 1 else 0 end)
    as publica_los_pesos;
