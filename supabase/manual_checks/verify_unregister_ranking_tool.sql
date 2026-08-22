select
  1 / (case when (select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1('rank_sales_customers')) = 0 then 1 else 0 end) as retirada,
  1 / (case when (select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1('analyze_sales_period')) = 1 then 1 else 0 end) as ventas_intacta,
  1 / (case when (select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1('search_inventory')) = 1 then 1 else 0 end) as inventario_intacto;
