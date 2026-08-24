-- Read-back: el tope del recibo y el máximo del esquema dicen lo mismo.
-- El esquema de `rank_basket_suppliers` permite limit hasta 5; si el contrato
-- anuncia menos, una llamada legítima mata la corrida entera.
select
  1 / (case when (
    select max_result_count
    from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_basket_suppliers')
  ) = 5 then 1 else 0 end) as tope_de_canasta_es_cinco,
  1 / (case when (
    select max_result_count
    from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_purchase_suppliers')
  ) = 5 then 1 else 0 end) as tope_de_una_frase_es_cinco;
