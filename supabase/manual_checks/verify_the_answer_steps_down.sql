-- Read-back: la escalera tiene tres escalones, la rama nunca se suelta, y el
-- plural dejó de decidir.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%for v_attempt in 1..3 loop%' then 1 else 0 end) as tres_escalones,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%droppedFilters%' then 1 else 0 end) as declara_lo_soltado,
  -- La rama se conserva: si alguna vez se vaciaran las categorías deducidas,
  -- la respuesta pasaría a ser «a quién le compramos todo».
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) not like '%v_inferred_categories := null%' then 1 else 0 end)
    as la_rama_no_se_suelta,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'purchase_supplier_concentration_internal_v1'
  ) like '%left(token, length(token) - 1)%' then 1 else 0 end) as plural_no_decide;
