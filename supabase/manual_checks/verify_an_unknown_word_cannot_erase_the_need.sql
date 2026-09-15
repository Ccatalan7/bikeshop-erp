-- Read-back: hay segunda pasada, y la respuesta declara que se ensanchó.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%for v_attempt in 1..2 loop%' then 1 else 0 end) as segunda_pasada,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%scopeRelaxed%' then 1 else 0 end) as se_declara,
  -- Sin nada resuelto NO se relaja: soltar el texto sería «a quién le
  -- compramos todo».
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%and v_category is null)%' then 1 else 0 end) as sin_relajar_a_ciegas;
