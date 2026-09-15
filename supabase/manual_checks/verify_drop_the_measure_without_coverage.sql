-- Read-back: el escalón suelta por cobertura, no en bloque.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) not like '%v_predicates := ''[]''::jsonb;%' then 1 else 0 end)
    as no_vacia_en_bloque,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) like '%la medida sin cobertura%' then 1 else 0 end) as nombra_lo_soltado,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_query_products_internal_v1'
  ) like '%in (''product_spec'', ''identity_fallback'')%'
    then 1 else 0 end) as mide_cobertura_real;
