select
  1 / (case when (
    select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_sales_customers'
    )
  ) = 1 then 1 else 0 end) as herramienta_registrada,
  1 / (case when (
    select max_result_count from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_sales_customers'
    )
  ) = 10 then 1 else 0 end) as tope_correcto,
  -- Y no se rompió ninguna de las que ya estaban.
  1 / (case when (
    select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'analyze_sales_period'
    )
  ) = 1 then 1 else 0 end) as ventas_intacta;
