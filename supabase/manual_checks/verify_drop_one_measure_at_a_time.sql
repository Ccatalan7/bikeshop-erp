select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) like '%for v_attempt in 1..8 loop%' then 1 else 0 end) as ocho_intentos,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) like '%order by cobertura asc, ord desc%' then 1 else 0 end)
    as la_menos_cubierta_primero,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) not like '%v_predicates := ''[]''::jsonb;%' then 1 else 0 end)
    as nunca_en_bloque;
