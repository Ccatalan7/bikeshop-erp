-- Read-back: el motor delega la resolución de la frase y no la repite.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%purchase_query_products_internal_v1%' then 1 else 0 end)
    as motor_delega,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) not like '%for v_attempt in 1..4 loop%' then 1 else 0 end)
    as escalera_no_duplicada,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%scopeRelaxed%' then 1 else 0 end) as sigue_declarando;
