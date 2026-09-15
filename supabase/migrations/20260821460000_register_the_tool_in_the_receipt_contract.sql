-- Una herramienta nueva del asistente NO queda operativa con registrarla en el
-- código: `assistant_runtime.assistant_tool_receipt_contract_internal_v1` es un
-- allowlist del servidor —riesgo, decisión de política y tope de resultados por
-- herramienta— y si el nombre no está ahí, el recibo no existe y la corrida
-- muere con un 500 opaco, sin llegar nunca a la RPC.
--
-- Registrar una herramienta son cuatro lugares: la RPC, el contrato del
-- ejecutor, el esquema del registry y esta tabla de contratos.

CREATE OR REPLACE FUNCTION assistant_runtime.assistant_tool_receipt_contract_internal_v1(p_tool_name text)
 RETURNS TABLE(risk text, policy_decision text, max_result_count integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
  select contract.risk, contract.policy_decision, contract.max_result_count
  from (values
    ('inspect_inventory_schema', 'read', 'allowed', 40),
    ('search_inventory', 'read', 'allowed', 10),
    ('rank_purchase_candidates', 'read', 'allowed', 10),
    ('build_purchase_scenarios', 'read', 'allowed', 3),
    ('prepare_supply_request', 'read', 'allowed', 8),
    ('list_attention_items', 'read', 'allowed', 10),
    ('get_business_snapshot', 'read', 'allowed', 10),
    ('search_workshop_jobs', 'read', 'allowed', 10),
    ('get_workshop_job_context', 'read', 'allowed', 10),
    ('inspect_diagnosis_schema', 'read', 'allowed', 40),
    ('search_tasks', 'read', 'allowed', 10),
    ('search_customers', 'read', 'allowed', 10),
    ('search_suppliers', 'read', 'allowed', 10),
    ('search_sales_invoices', 'read', 'allowed', 10),
    ('search_purchase_invoices', 'read', 'allowed', 10),
    ('find_inventory_risks', 'read', 'allowed', 10),
    ('list_recent_expenses', 'read', 'allowed', 10),
    ('analyze_cash_and_receivables', 'read', 'allowed', 10),
    ('analyze_sales_period', 'read', 'allowed', 1),
    ('rank_sales_customers', 'read', 'allowed', 10),
    ('search_conversations', 'read', 'allowed', 10),
    ('research_public_web', 'public_research', 'allowed', 10),
    ('prepare_task', 'draft', 'approval_required', 10),
    ('prepare_diagnosis_update', 'draft', 'approval_required', 1),
    ('prepare_workshop_item', 'draft', 'approval_required', 1),
    ('report_capability_gap', 'read', 'allowed', 10)
  ) contract(tool_name, risk, policy_decision, max_result_count)
  where contract.tool_name = p_tool_name;
$function$
;
