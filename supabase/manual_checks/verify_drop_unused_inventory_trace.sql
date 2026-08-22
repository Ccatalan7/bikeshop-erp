select
  1 / (case when not exists (
    select 1 from pg_tables where tablename = 'ai_agent_inventory_call_traces'
  ) then 1 else 0 end) as tabla_retirada,
  1 / (case when not exists (
    select 1 from pg_proc where proname = 'ai_agent_record_inventory_call_v1'
  ) then 1 else 0 end) as funcion_retirada;
