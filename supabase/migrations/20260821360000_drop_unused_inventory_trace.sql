-- La traza de llamadas nunca llegó a escribirse: el ejecutor de herramientas
-- sólo puede llamar un conjunto fijo de RPCs —así lo exige su propio contrato
-- y lo prueba `tool executor maps all ERP reads to fixed caller-scoped RPCs`—,
-- y el sistema ya graba recibos por `assistant_record_tool_receipt_v2`.
-- Se retira en vez de dejar dos objetos sin escritor.

drop function if exists public.ai_agent_record_inventory_call_v1(
  jsonb, text, text, integer
);
drop table if exists public.ai_agent_inventory_call_traces;
