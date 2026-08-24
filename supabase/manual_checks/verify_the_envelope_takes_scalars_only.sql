-- Read-back: el sobre queda con sus claves base y cada fila es escalar.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) not like '%''scope'', v_scope%' then 1 else 0 end) as sobre_sin_claves_extra,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) not like '%supplierAvailabilitySemantics%' then 1 else 0 end)
    as sobre_sin_semantica_suelta,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%evidencePurchaseLines%' then 1 else 0 end) as evidencia_por_fila,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%''entityId'', supplier_id%' then 1 else 0 end) as fila_con_entidad;
