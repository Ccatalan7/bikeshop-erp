-- El ejecutor sólo tiene `rpc` sobre un cliente estrecho: la traza se escribe
-- por función, no por insert directo. Deriva el tenant de la misma autoridad
-- que el resto de las herramientas, así que no acepta un tenant ajeno.

create or replace function public.ai_agent_record_inventory_call_v1(
  p_arguments jsonb,
  p_run_id text,
  p_status text,
  p_count integer
) returns void
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_authority record;
begin
  select authority.tenant_id
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  insert into public.ai_agent_inventory_call_traces (
    tenant_id, run_id, arguments, result_status, result_count
  ) values (
    v_authority.tenant_id,
    left(coalesce(p_run_id, ''), 128),
    coalesce(p_arguments, '{}'::jsonb),
    left(coalesce(p_status, ''), 40),
    p_count
  );

  -- Se poda sola: es diagnóstico, no historia.
  delete from public.ai_agent_inventory_call_traces old
  where old.tenant_id = v_authority.tenant_id
    and old.created_at < now() - interval '7 days';
end;
$function$;

revoke all on function public.ai_agent_record_inventory_call_v1(
  jsonb, text, text, integer
) from public;
grant execute on function public.ai_agent_record_inventory_call_v1(
  jsonb, text, text, integer
) to authenticated;
