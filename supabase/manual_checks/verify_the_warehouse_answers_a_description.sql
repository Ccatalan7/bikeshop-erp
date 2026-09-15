-- Read-back: la bodega se puede consultar por descripción, con el MISMO
-- resolvedor del ranking, y no pisa a la lectura exacta cuando ya hay producto.
select
  1 / (case when has_function_privilege('authenticated',
    'public.supply_need_stock_candidates_v1(uuid,integer)', 'execute')
    then 1 else 0 end) as modulo_ejecuta,
  1 / (case when (
    select prosrc from pg_proc where proname = 'supply_need_stock_candidates_v1'
  ) like '%purchase_query_products_internal_v1%' then 1 else 0 end)
    as mismo_resolvedor,
  1 / (case when (
    select prosrc from pg_proc where proname = 'supply_need_stock_candidates_v1'
  ) like '%identity_confirmed%' then 1 else 0 end) as no_pisa_la_lectura_exacta,
  -- Mira el catálogo completo, no sólo lo que alguna vez se compró: la bodega
  -- tiene productos que nunca pasaron por una factura de compra.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supply_need_stock_candidates_v1'
  ) like '%v_need.original_description, false%' then 1 else 0 end)
    as catalogo_completo;
