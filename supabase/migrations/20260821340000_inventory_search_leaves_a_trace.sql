-- Diagnóstico permanente. Hoy —2026-08-21— se perdieron varias rondas
-- adivinando qué argumentos manda el modelo a `search_inventory`: la RPC se
-- ejecutaba, devolvía vacío, y no había forma de ver con qué la llamó. La
-- función de borde no tiene lectura de logs desde el CLI, y ni la app ni la
-- base guardaban la llamada.
--
-- Guarda sólo la llamada de inventario y su recuento: ni prompts, ni respuesta
-- del modelo, ni identificadores de usuario.

create table if not exists public.ai_agent_inventory_call_traces (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  run_id text,
  arguments jsonb not null,
  result_status text,
  result_count integer,
  failure_code text,
  created_at timestamptz not null default now()
);

create index if not exists ai_agent_inventory_call_traces_recent_idx
  on public.ai_agent_inventory_call_traces (tenant_id, created_at desc);

alter table public.ai_agent_inventory_call_traces enable row level security;

revoke all on table public.ai_agent_inventory_call_traces from anon, authenticated;

comment on table public.ai_agent_inventory_call_traces is
  'Diagnóstico: argumentos con que el agente llamó a search_inventory y qué '
  'devolvió. Sin RLS de lectura a propósito: sólo el rol de servicio escribe y '
  'lee. Podarla es seguro.';
