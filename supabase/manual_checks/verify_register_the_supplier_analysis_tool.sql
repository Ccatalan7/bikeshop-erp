-- Read-back: la herramienta está anunciada, con su tope, y ninguna de las
-- anteriores se cayó del contrato al reescribirlo.
select
  1 / (case when (
    select max_result_count
    from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_purchase_suppliers'
    )
  ) = 5 then 1 else 0 end) as anunciada_con_tope,
  1 / (case when (
    select policy_decision
    from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_purchase_suppliers'
    )
  ) = 'allowed' then 1 else 0 end) as permitida,
  1 / (case when (
    select count(*) from (values
      ('inspect_inventory_schema'),('search_inventory'),
      ('rank_purchase_candidates'),('build_purchase_scenarios'),
      ('prepare_supply_request'),('list_attention_items'),
      ('get_business_snapshot'),('search_workshop_jobs'),
      ('get_workshop_job_context'),('inspect_diagnosis_schema'),
      ('search_tasks'),('search_customers'),('search_suppliers'),
      ('search_sales_invoices'),('search_purchase_invoices'),
      ('find_inventory_risks'),('list_recent_expenses'),
      ('analyze_cash_and_receivables'),('analyze_sales_period'),
      ('search_conversations'),('prepare_customer_contact'),
      ('research_public_web'),('prepare_task'),
      ('prepare_diagnosis_update'),('prepare_workshop_item'),
      ('report_capability_gap')
    ) previa(tool_name)
    where not exists (
      select 1
      from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
        previa.tool_name
      )
    )
  ) = 0 then 1 else 0 end) as ninguna_se_cayo;
