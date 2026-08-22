select
  1 / (case when exists (
    select 1 from pg_tables where tablename = 'ai_agent_inventory_call_traces'
      and schemaname = 'public'
  ) then 1 else 0 end) as tabla_existe,
  1 / (case when (
    select relrowsecurity from pg_class where relname = 'ai_agent_inventory_call_traces'
  ) then 1 else 0 end) as rls_activo,
  1 / (case when not exists (
    select 1 from information_schema.role_table_grants
    where table_name = 'ai_agent_inventory_call_traces'
      and grantee in ('anon', 'authenticated')
  ) then 1 else 0 end) as sin_acceso_publico;
