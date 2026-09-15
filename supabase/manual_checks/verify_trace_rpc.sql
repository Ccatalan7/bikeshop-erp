select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'ai_agent_record_inventory_call_v1'
      and prosecdef
  ) then 1 else 0 end) as funcion_existe,
  -- Deriva el tenant de la autoridad: no lo recibe por parámetro.
  1 / (case when (
    select count(*) from information_schema.parameters
    where specific_name like 'ai_agent_record_inventory_call_v1%'
      and parameter_name = 'p_tenant_id'
  ) = 0 then 1 else 0 end) as sin_tenant_por_parametro;
