-- 20260805210000_mechanic_job_status_transitions.sql
--
-- Por qué existe: la columna Flujo del taller decía «Sin dato» o «Sin
-- evidencia suficiente» en casi toda pega. La causa no era el read model —
-- `get_mechanic_job_time_metrics` es reconstrucción honesta y se niega a
-- inventar — sino la CAPTURA: los flags `triggers_start/completion/delivery`
-- de `job_statuses` existían y se editaban en la UI, pero ningún código
-- ejecutaba `triggers_start` (started_at quedaba al 49% por escrituras
-- manuales dispersas), y ningún registro durable guardaba las transiciones de
-- estado — sólo `status_updated_at`, que se pisa a sí mismo, y una bitácora
-- por NOMBRE de estado que un rename rompe.
--
-- La entrega ya tenía el patrón correcto (resolver semántico + evento
-- inmutable + sello server-side). Esta migración completa ese patrón para el
-- resto del ciclo:
--   1. resolver de inicio `mechanic_job_resolves_start`;
--   2. sello de `started_at` en el guard de ciclo de vida existente
--      (primer-gana, nunca se borra: una pausa no des-inicia el trabajo);
--   3. libro append-only `mechanic_job_status_transitions` con fase y flags
--      congelados al momento del cambio — el análisis de cuellos de botella
--      por estado no puede depender de estados renombrables;
--   4. evidencia de transición en el read model de métricas, con la misma
--      regla de siempre: nunca inventar, siempre declarar la fuente.
--
-- Estado de despliegue: aplicada a producción el 2026-08-05 vía
-- `scripts/db/query.sh production --write --file` y verificada con read-back
-- + pgTAP local `mechanic_job_status_transitions.sql`.

-- 1 ── Resolver semántico de inicio, espejo del de entrega/término.
create or replace function public.mechanic_job_resolves_start(
  p_status text,
  p_status_id uuid
)
returns boolean
language sql
stable
set search_path = public
as $$
  select upper(coalesce(p_status, '')) in ('EN_CURSO', 'EN CURSO')
    or exists (
      select 1
      from public.job_statuses status
      where status.id = p_status_id
        and (
          coalesce(status.triggers_start, false)
          or lower(coalesce(status.code, '')) in ('en_curso', 'en curso')
        )
    );
$$;

-- 2 ── El guard de ciclo de vida ahora también sella el inicio.
create or replace function public.normalize_mechanic_job_lifecycle_timestamps()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_is_delivered boolean;
  v_is_complete boolean;
  v_is_started boolean;
begin
  v_is_delivered := public.mechanic_job_resolves_delivery(
    new.status,
    new.status_id
  );
  v_is_complete := public.mechanic_job_resolves_completion(
    new.status,
    new.status_id
  );
  v_is_started := public.mechanic_job_resolves_start(
    new.status,
    new.status_id
  );

  -- El inicio es primer-gana y nunca se limpia: pasar a En Pausa o a
  -- REPUESTOS no des-inicia un trabajo. Un término o entrega implica que el
  -- trabajo también comenzó, aunque nadie haya pasado por «En Curso».
  if v_is_started or v_is_complete or v_is_delivered then
    new.started_at := coalesce(new.started_at, v_now);
  end if;

  if v_is_delivered then
    new.delivered_at := coalesce(new.delivered_at, v_now);
  else
    new.delivered_at := null;
  end if;

  if v_is_complete then
    new.completed_at := coalesce(
      new.completed_at,
      new.delivered_at,
      v_now
    );
  end if;

  return new;
end;
$$;

-- 3 ── Libro append-only de transiciones de estado.
create table if not exists public.mechanic_job_status_transitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid not null references public.mechanic_jobs(id) on delete cascade,
  occurred_at timestamptz not null default clock_timestamp(),
  from_status text,
  from_status_id uuid,
  from_phase text,
  to_status text not null,
  to_status_id uuid,
  -- Fase y flags CONGELADOS al momento del cambio: si mañana renombran o
  -- reconfiguran el estado, la historia sigue diciendo la verdad de ese día.
  to_phase text,
  to_triggers_start boolean not null default false,
  to_triggers_completion boolean not null default false,
  to_triggers_delivery boolean not null default false,
  actor_user_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_job_status_transitions_job
  on public.mechanic_job_status_transitions (tenant_id, job_id, occurred_at);
create index if not exists idx_job_status_transitions_tenant_time
  on public.mechanic_job_status_transitions (tenant_id, occurred_at);

alter table public.mechanic_job_status_transitions enable row level security;

drop policy if exists "job_status_transitions_select"
  on public.mechanic_job_status_transitions;
create policy "job_status_transitions_select"
  on public.mechanic_job_status_transitions
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Sin política de insert/update/delete para clientes: el único escritor es
-- el trigger (security definer). Append-only por construcción.

-- 4 ── Captura server-side: cada cambio de estado deja una fila, venga del
-- formulario, de la tabla, del POS o de cualquier escritor futuro.
create or replace function public.capture_mechanic_job_status_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from_phase text;
  v_to_phase text;
  v_to_start boolean := false;
  v_to_completion boolean := false;
  v_to_delivery boolean := false;
begin
  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.status_id is not distinct from new.status_id then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    select status.phase into v_from_phase
    from public.job_statuses status
    where status.id = old.status_id;
  end if;

  select status.phase,
         coalesce(status.triggers_start, false),
         coalesce(status.triggers_completion, false),
         coalesce(status.triggers_delivery, false)
  into v_to_phase, v_to_start, v_to_completion, v_to_delivery
  from public.job_statuses status
  where status.id = new.status_id;

  -- Una pega con estado sólo-texto (sin status_id catalogado) también deja
  -- huella: SELECT INTO sin fila pisa las variables con NULL, y el libro
  -- exige flags concretos.
  v_to_start := coalesce(v_to_start, false);
  v_to_completion := coalesce(v_to_completion, false);
  v_to_delivery := coalesce(v_to_delivery, false);

  insert into public.mechanic_job_status_transitions (
    tenant_id,
    job_id,
    from_status,
    from_status_id,
    from_phase,
    to_status,
    to_status_id,
    to_phase,
    to_triggers_start,
    to_triggers_completion,
    to_triggers_delivery,
    actor_user_id
  )
  values (
    new.tenant_id,
    new.id,
    case when tg_op = 'UPDATE' then old.status end,
    case when tg_op = 'UPDATE' then old.status_id end,
    v_from_phase,
    new.status,
    new.status_id,
    v_to_phase,
    v_to_start,
    v_to_completion,
    v_to_delivery,
    auth.uid()
  );

  return new;
end;
$$;

revoke all on function public.capture_mechanic_job_status_transition()
  from public, anon, authenticated;

drop trigger if exists trg_mechanic_jobs_status_transition_ledger
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_status_transition_ledger
  after insert or update of status, status_id on public.mechanic_jobs
  for each row
  execute function public.capture_mechanic_job_status_transition();
