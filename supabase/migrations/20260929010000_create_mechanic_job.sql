-- El alta de un trabajo nuevo, como comando con llave y recibo
-- (cierre del Master Schema, 2026-09-29).
--
-- Antes el formulario insertaba el trabajo con PostgREST antes de respaldar
-- sus líneas en la bandeja del equipo: si la app se cerraba entre el alta y
-- su respuesta, quedaba un trabajo sin líneas ni factura que había que
-- rescatar a mano, y la recuperación de un reintento (`23505` de la llave
-- primaria) volvía a anotar «Trabajo creado» en la historia de la bici,
-- porque ese evento lo escribía la app después del alta.
--
-- Ahora la app respalda el alta y lo que la sigue (las líneas, y en una
-- garantía nueva su registro) antes del primer envío, y los envía en orden.
-- Este comando crea el trabajo con el id que eligió el formulario y anota
-- «Trabajo creado» en la misma transacción, una sola vez. Su llave es la del
-- alta (la app usa el id del trabajo): el reintento devuelve el mismo
-- recibo; la misma llave con otro contenido se rechaza. El recibo se lee por
-- llave y taller (`get_mechanic_job_creation_v1`) cuando la respuesta se
-- perdió, con el contenido que se envió: el recibo dice si es el mismo que
-- escribió, así un recibo de la misma llave nunca confirma otro contenido
-- (revisión de Codex, 2026-09-29).
--
-- Mismas reglas que el alta directa que reemplaza: el taller es el del
-- perfil activo de quien llama (la política `mechanic_jobs_insert` pedía
-- `is_active_tenant_member`), los disparadores del trabajo corren igual (el
-- grafo de taller valida cliente, bici y componente) y sólo entran las
-- columnas que el formulario manda en un alta.
begin;

create table if not exists public.mechanic_job_creations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_key text not null,
  payload_hash text not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  result_snapshot jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key)
);

comment on table public.mechanic_job_creations is
  'Recibos del alta de un trabajo (create_mechanic_job_v1). Evidencia del comando y respuesta de un reintento, no una segunda verdad: el trabajo vive en mechanic_jobs.';

create unique index if not exists idx_mechanic_job_creations_job
  on public.mechanic_job_creations(tenant_id, job_id)
  where job_id is not null;

alter table public.mechanic_job_creations enable row level security;

drop policy if exists mechanic_job_creations_select
  on public.mechanic_job_creations;
create policy mechanic_job_creations_select
  on public.mechanic_job_creations
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Todo, también TRUNCATE, REFERENCES y TRIGGER, que los privilegios por
-- defecto dan a los roles de la API y el RLS no cubre (revisión de Codex).
revoke all
  on public.mechanic_job_creations
  from public, anon, authenticated;

create or replace function public.create_mechanic_job_v1(
  p_operation_key text,
  p_job jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_active_profile_count integer;
  v_tenant_id uuid;
  v_operation_key text := nullif(btrim(p_operation_key), '');
  v_operation_id uuid := gen_random_uuid();
  v_job_id uuid;
  v_payload_hash text;
  v_receipt public.mechanic_job_creations%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_key text;
  v_columns text;
  v_result jsonb;
  -- Lo que el formulario manda en un alta (`MechanicJob.toJson`). La hora de
  -- creación y de cambio las pone el servidor; los costos calculados, sus
  -- disparadores.
  v_allowed constant text[] := array[
    'id', 'tenant_id', 'job_number', 'customer_id', 'bike_id',
    'service_package_id', 'job_type', 'workflow_kind', 'intake_kind',
    'mode_needs_review', 'mode_review_reason', 'subject_id', 'subject_notes',
    'warranty_outcome', 'quotation_status', 'quotation_valid_until',
    'converted_from_id', 'converted_at', 'arrival_date',
    'diagnostic_deadline', 'deadline', 'diagnostic_sent_at', 'started_at',
    'completed_at', 'delivered_at', 'status', 'status_id', 'priority',
    'client_request', 'diagnosis', 'work_performed', 'notes', 'assigned_to',
    'assigned_technician_name', 'estimated_cost', 'final_cost',
    'discount_amount', 'estimated_duration_hours', 'actual_labor_hours',
    'invoice_id', 'is_invoiced', 'is_paid', 'is_warranty_job',
    'warranty_notes', 'requires_approval', 'approved_by_customer',
    'approved_at', 'image_urls'
  ];
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select tenant_id
    into v_tenant_id
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  if v_operation_key is null or length(v_operation_key) > 80 then
    raise exception 'A valid job creation operation key is required'
      using errcode = '22023';
  end if;

  if p_job is null or jsonb_typeof(p_job) <> 'object' then
    raise exception 'The new job must be an object' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_job)
  loop
    if not (v_key = any (v_allowed)) then
      raise exception 'Job field % is not one the form sends on creation', v_key
        using errcode = '22023';
    end if;
  end loop;

  begin
    v_job_id := nullif(p_job ->> 'id', '')::uuid;
  exception when invalid_text_representation then
    v_job_id := null;
  end;
  if v_job_id is null then
    raise exception 'The new job carries the id the form chose'
      using errcode = '22023';
  end if;
  -- El trabajo es del taller de quien lo crea, nunca de otro.
  if p_job ? 'tenant_id'
     and (p_job ->> 'tenant_id') is distinct from v_tenant_id::text then
    raise exception 'The new job belongs to the active tenant'
      using errcode = '42501';
  end if;

  v_payload_hash := md5(p_job::text);

  -- Dos envíos de la misma alta (otra pestaña, la reanudación) no chocan: el
  -- segundo espera al primero y devuelve su recibo.
  perform pg_advisory_xact_lock(
    hashtextextended('create_mechanic_job_v1:' || v_job_id::text, 0));

  select *
    into v_receipt
    from public.mechanic_job_creations receipt
   where receipt.tenant_id = v_tenant_id
     and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.payload_hash <> v_payload_hash then
      raise exception 'La llave del alta ya respalda otro trabajo'
        using errcode = '23505';
    end if;
    return v_receipt.result_snapshot || jsonb_build_object('replayed', true);
  end if;

  if exists (select 1 from public.mechanic_jobs job where job.id = v_job_id) then
    raise exception 'Ya existe un trabajo con ese id'
      using errcode = '23505';
  end if;

  select string_agg(quote_ident(key), ', ' order by key)
    into v_columns
    from jsonb_object_keys(p_job) as key
   where key <> 'tenant_id';

  execute format(
    'insert into public.mechanic_jobs (tenant_id, %1$s)
     select $1, %1$s
       from jsonb_populate_record(null::public.mechanic_jobs, $2)
     returning *',
    v_columns
  )
  using v_tenant_id, p_job
  into v_job;

  -- La fila como quedó después de sus disparadores.
  select *
    into v_job
    from public.mechanic_jobs job
   where job.id = v_job.id
     and job.tenant_id = v_tenant_id;

  -- «Trabajo creado» en la historia de la bici, en la misma transacción que
  -- el alta: una sola vez aunque el alta se reintente. Igual que lo anotaba
  -- la app (estado y prioridad con sus nombres de la app).
  if v_job.bike_id is not null then
    insert into public.bike_events (
      tenant_id, bike_id, job_id, event_type, event_category, event_date,
      title, summary, source, reference_number, payload
    ) values (
      v_job.tenant_id,
      v_job.bike_id,
      v_job.id,
      'job_created',
      'visit',
      v_job.arrival_date,
      'Trabajo creado',
      coalesce(
        nullif(btrim(v_job.client_request), ''),
        'Se abrió la orden ' || v_job.job_number || '.'
      ),
      'job_lifecycle',
      v_job.job_number,
      jsonb_build_object(
        'status', case upper(v_job.status)
          when 'PENDIENTE' then 'pendiente'
          when 'DIAGNOSTICO' then 'diagnostico'
          when 'ESPERANDO_APROBACION' then 'esperandoAprobacion'
          when 'ESPERANDO_REPUESTOS' then 'esperandoRepuestos'
          when 'EN_CURSO' then 'enCurso'
          when 'FINALIZADO' then 'finalizado'
          when 'ENTREGADO' then 'entregado'
          when 'CANCELADO' then 'cancelado'
          else lower(v_job.status)
        end,
        'priority', lower(v_job.priority)
      )
    );
  end if;

  v_result := jsonb_build_object(
    'operation_id', v_operation_id,
    'operation_key', v_operation_key,
    'job', to_jsonb(v_job)
  );

  insert into public.mechanic_job_creations (
    tenant_id, operation_key, payload_hash, job_id, result_snapshot,
    created_by
  ) values (
    v_tenant_id, v_operation_key, v_payload_hash, v_job.id, v_result,
    v_actor_id
  );

  return v_result || jsonb_build_object('replayed', false);
end;
$function$;

comment on function public.create_mechanic_job_v1(text, jsonb) is
  'Alta de un trabajo con el id que eligió el formulario, con llave y recibo: el reintento devuelve el mismo recibo, la misma llave con otro contenido se rechaza (23505), y «Trabajo creado» se anota en la bici en la misma transacción, una vez.';

-- La primera versión local no recibía el contenido.
drop function if exists public.get_mechanic_job_creation_v1(text);

create or replace function public.get_mechanic_job_creation_v1(
  p_operation_key text,
  p_job jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_active_profile_count integer;
  v_tenant_id uuid;
  v_result jsonb;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if v_actor_id is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select tenant_id
    into v_tenant_id
    from public.user_profiles
   where user_id = v_actor_id
     and is_active is true;

  if not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  -- `payload_matches`: si el contenido enviado es el que escribió esta
  -- llave (la misma huella que compara el alta); null si no se envió.
  select receipt.result_snapshot || jsonb_build_object(
           'replayed', true,
           'payload_matches',
           case when p_job is null then null
                else receipt.payload_hash = md5(p_job::text) end)
    into v_result
    from public.mechanic_job_creations receipt
   where receipt.tenant_id = v_tenant_id
     and receipt.operation_key = nullif(btrim(p_operation_key), '');

  return v_result;
end;
$function$;

comment on function public.get_mechanic_job_creation_v1(text, jsonb) is
  'El recibo de un alta por su llave, del taller de quien pregunta; null si esa alta no se escribió. Con p_job dice si ese contenido es el que escribió la llave (payload_matches).';

revoke all on function public.create_mechanic_job_v1(text, jsonb)
  from public, anon, service_role;
grant execute on function public.create_mechanic_job_v1(text, jsonb)
  to authenticated;

revoke all on function public.get_mechanic_job_creation_v1(text, jsonb)
  from public, anon, service_role;
grant execute on function public.get_mechanic_job_creation_v1(text, jsonb)
  to authenticated;

commit;
