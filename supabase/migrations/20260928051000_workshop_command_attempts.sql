-- Deployment status: NOT DEPLOYED
-- Intentos de los comandos del taller (BIKE_WORKSHOP_MASTER_SCHEMA.md, ítem 3
-- de la cola).
--
-- Los recibos (`bike_aggregate_save_operations`, `bike_technical_fact_patches`)
-- prueban sólo lo que se escribió. Un guardado sin red, uno rechazado o uno
-- que llegó tarde a una ficha que ya había cambiado no deja rastro en el
-- servidor, y soporte no puede distinguirlos. La app anota cada intento en su
-- bandeja local (también sin red) y los entrega aquí cuando puede.
--
-- Resultados:
--   committed  — el servidor respondió con lo escrito.
--   reconciled — se perdió la respuesta, pero el recibo prueba que se
--                escribió (lo devuelve la consulta del recibo o el reenvío con
--                la misma llave, `replayed = true`).
--   rejected   — el servidor lo rechazó y no aplicó nada.
--   stale      — el servidor lo rechazó porque la ficha cambió desde que se
--                cargó (40001); no aplicó nada.
--   offline    — no hubo respuesta: el comando sigue pendiente con su llave.
--   discarded  — alguien lo descartó antes de que llegara.
--
-- Es evidencia de soporte, no una segunda verdad: el estado de la bici sigue
-- en `bikes` y `bike_profiles`, y lo escrito, en los recibos.
begin;

create table if not exists public.workshop_command_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  attempt_id uuid not null,
  operation_key text not null,
  command_kind text not null,
  attempt_number integer not null,
  trigger text not null,
  outcome text not null,
  error_code text,
  error_message text,
  bike_id uuid,
  job_id uuid,
  client_started_at timestamptz not null,
  duration_ms integer,
  client_platform text,
  app_version text,
  received_at timestamptz not null default clock_timestamp(),
  constraint workshop_command_attempts_attempt_unique
    unique (tenant_id, attempt_id),
  -- `job_line_save`: el guardado de líneas y ficha del trabajo
  -- (20260928080000), que pasa por la misma bandeja;
  -- `job_invoice_continuation`, su factura cuando quedó en `failed`; y
  -- `job_status_transition`, el cambio de estado, en la cola del trabajo; y
  -- `job_warranty_decision`, la decisión de garantía, entre el guardado de
  -- líneas y el estado (punto 2 del cierre, 2026-09-29); `job_create`, el
  -- alta de un trabajo nuevo, respaldada con sus líneas antes de enviarse, y
  -- `job_warranty_registration`, el registro de la garantía de un trabajo
  -- nuevo, detrás de sus líneas (20260929010000).
  constraint workshop_command_attempts_kind_check
    check (command_kind in (
      'bike_aggregate_save', 'bike_fact_patch', 'job_line_save',
      'job_invoice_continuation', 'job_status_transition',
      'job_warranty_decision', 'job_create', 'job_warranty_registration'
    )),
  constraint workshop_command_attempts_trigger_check
    check (trigger in ('save', 'retry', 'resume', 'discard')),
  constraint workshop_command_attempts_outcome_check
    check (outcome in (
      'committed', 'reconciled', 'rejected', 'stale', 'offline', 'discarded'
    )),
  constraint workshop_command_attempts_number_check
    check (attempt_number between 0 and 10000),
  constraint workshop_command_attempts_key_check
    check (char_length(operation_key) between 1 and 200)
);

-- Reejecutable: una base que ya tiene la tabla toma el `check` de hoy.
alter table public.workshop_command_attempts
  drop constraint if exists workshop_command_attempts_kind_check;
alter table public.workshop_command_attempts
  add constraint workshop_command_attempts_kind_check
  check (command_kind in (
    'bike_aggregate_save', 'bike_fact_patch', 'job_line_save',
    'job_invoice_continuation', 'job_status_transition',
    'job_warranty_decision', 'job_create', 'job_warranty_registration'
  ));

comment on table public.workshop_command_attempts is
  'Cada intento de un comando del taller, anotado por la app aunque no haya red, para que soporte distinga sin red, rechazado, ficha cambiada, escrito y reconciliado. No es la verdad de la bici: eso vive en bikes/bike_profiles y los recibos.';

create index if not exists idx_workshop_command_attempts_operation
  on public.workshop_command_attempts(tenant_id, operation_key, client_started_at);
create index if not exists idx_workshop_command_attempts_bike
  on public.workshop_command_attempts(tenant_id, bike_id, client_started_at desc);

alter table public.workshop_command_attempts enable row level security;

drop policy if exists workshop_command_attempts_select
  on public.workshop_command_attempts;
create policy workshop_command_attempts_select
  on public.workshop_command_attempts
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.workshop_command_attempts
  from public, anon, authenticated;
grant select on public.workshop_command_attempts to authenticated;

-- Recibe una tanda de intentos. Un intento mal formado (una versión vieja de
-- la app, un campo de más) se cuenta y se salta: rechazar la tanda entera
-- dejaría la bandeja local reenviándola para siempre. Un intento repetido
-- (la respuesta se perdió y la app lo reenvía) no se duplica.
create or replace function public.record_workshop_command_attempts_v1(
  p_attempts jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_tenant_id uuid := public.user_tenant_id();
  v_attempt jsonb;
  v_inserted integer := 0;
  v_duplicates integer := 0;
  v_invalid integer := 0;
  v_row_count integer;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_attempts is null or jsonb_typeof(p_attempts) <> 'array' then
    raise exception 'Attempts must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_attempts) > 100 then
    raise exception 'At most 100 attempts per call'
      using errcode = 'invalid_parameter_value';
  end if;

  for v_attempt in select value from jsonb_array_elements(p_attempts)
  loop
    begin
      if jsonb_typeof(v_attempt) <> 'object'
        or coalesce(v_attempt->>'attempt_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or (v_attempt ? 'bike_id' and v_attempt->>'bike_id' is not null
            and v_attempt->>'bike_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        or (v_attempt ? 'job_id' and v_attempt->>'job_id' is not null
            and v_attempt->>'job_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      then
        v_invalid := v_invalid + 1;
        continue;
      end if;

      insert into public.workshop_command_attempts (
        tenant_id,
        user_id,
        attempt_id,
        operation_key,
        command_kind,
        attempt_number,
        trigger,
        outcome,
        error_code,
        error_message,
        bike_id,
        job_id,
        client_started_at,
        duration_ms,
        client_platform,
        app_version
      )
      values (
        v_tenant_id,
        v_actor_id,
        (v_attempt->>'attempt_id')::uuid,
        v_attempt->>'operation_key',
        v_attempt->>'command_kind',
        (v_attempt->>'attempt_number')::integer,
        v_attempt->>'trigger',
        v_attempt->>'outcome',
        left(v_attempt->>'error_code', 40),
        left(v_attempt->>'error_message', 500),
        (v_attempt->>'bike_id')::uuid,
        (v_attempt->>'job_id')::uuid,
        (v_attempt->>'client_started_at')::timestamptz,
        least(greatest((v_attempt->>'duration_ms')::integer, 0), 3600000),
        left(v_attempt->>'client_platform', 40),
        left(v_attempt->>'app_version', 40)
      )
      on conflict (tenant_id, attempt_id) do nothing;

      get diagnostics v_row_count = row_count;
      if v_row_count = 1 then
        v_inserted := v_inserted + 1;
      else
        v_duplicates := v_duplicates + 1;
      end if;
    exception
      when check_violation
        or not_null_violation
        or invalid_text_representation
        or invalid_datetime_format
        or datetime_field_overflow
        or numeric_value_out_of_range then
        v_invalid := v_invalid + 1;
    end;
  end loop;

  return jsonb_build_object(
    'inserted', v_inserted,
    'duplicates', v_duplicates,
    'invalid', v_invalid
  );
end;
$$;

revoke all on function public.record_workshop_command_attempts_v1(jsonb)
  from public, anon, service_role;
grant execute on function public.record_workshop_command_attempts_v1(jsonb)
  to authenticated;

commit;
