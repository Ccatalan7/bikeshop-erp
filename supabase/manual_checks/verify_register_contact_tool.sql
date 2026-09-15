select
  1 / (case when (select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1('prepare_customer_contact')) = 1 then 1 else 0 end) as registrada,
  1 / (case when (select max_result_count from assistant_runtime.assistant_tool_receipt_contract_internal_v1('prepare_customer_contact')) = 5 then 1 else 0 end) as tope_correcto,
  1 / (case when (select count(*) from assistant_runtime.assistant_tool_receipt_contract_internal_v1('search_inventory')) = 1 then 1 else 0 end) as inventario_intacto;
