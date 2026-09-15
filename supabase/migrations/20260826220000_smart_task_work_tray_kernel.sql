-- Smart Task work-tray kernel
--
-- smart_tasks pasa de lista plana tenant-wide a bandeja de trabajo:
-- tipo tarea/nota, visibilidad privada/equipo/empresa, ciclo de vida real
-- con recepción separada del estado, vínculo durable a servicios reales de
-- la pega (mechanic_job_items) con snapshot e invalidación explícita,
-- eventos append-only, comandos idempotentes y versionados, RLS por
-- autoridad real de creador/asignado/manager, estado por usuario
-- (visto/pin/snooze), hilo interno canónico por tarea, notificaciones
-- dirigidas por usuario y proyección mínima para el portal del trabajador.
--
-- FASE DE COMPATIBILIDAD (este kernel) vs CUTOVER (migración posterior):
-- los clientes ya instalados escriben smart_tasks por UPDATE directo. Este
-- kernel NO revoca esa ruta: la limita por actor (el asignado solo opera su
-- ciclo de vida; título/alcance/visibilidad son de creador/manager), la
-- audita en el mismo ledger de eventos, y deja a los escritores nuevos en
-- RPC. La revocación del UPDATE directo es una migración separada, cuando
-- ya no existan clientes legados instalados.
--
-- Compatibilidad medida antes de escribir (2026-08-26, producción):
--   * 72 smart_tasks: status solo 'pending'/'completed', priority solo
--     'normal', created_by nunca null → los CHECK son válidos sin backfill.
--   * assistant_apply_task_approval_v1 inserta solo columnas base → las
--     columnas nuevas con default no lo rompen.
--   * El cliente legado alterna pending↔completed por UPDATE directo y el
--     guard de transición lo admite para creador/asignado/manager.
-- No se fabrica evidencia: las 63 filas completadas quedan con
-- completed_at null (el estado es la verdad; el timestamp solo existe para
-- completaciones nuevas).

-- ============================================================================
-- 1. smart_tasks: columnas aditivas de bandeja
-- ============================================================================

alter table public.smart_tasks
  add column if not exists task_kind text not null default 'task',
  add column if not exists visibility text not null default 'team',
  add column if not exists assigned_at timestamptz,
  add column if not exists assigned_by uuid references auth.users(id) on delete set null,
  add column if not exists acknowledged_at timestamptz,
  add column if not exists acknowledged_by uuid references auth.users(id) on delete set null,
  add column if not exists started_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid references auth.users(id) on delete set null,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null,
  add column if not exists blocked_at timestamptz,
  add column if not exists blocked_by uuid references auth.users(id) on delete set null,
  add column if not exists blocked_reason text,
  add column if not exists version integer not null default 1;

-- Re-ejecutable: si un apply anterior quedó a medias, los drops devuelven al
-- punto de partida y los add recrean EXACTAMENTE la misma definición.
alter table public.smart_tasks
  drop constraint if exists smart_tasks_task_kind_check,
  drop constraint if exists smart_tasks_visibility_check,
  drop constraint if exists smart_tasks_status_domain_check,
  drop constraint if exists smart_tasks_priority_domain_check,
  drop constraint if exists smart_tasks_blocked_reason_check,
  drop constraint if exists smart_tasks_note_has_no_assignee_check,
  drop constraint if exists smart_tasks_private_is_personal_check;
alter table public.smart_tasks
  add constraint smart_tasks_task_kind_check
    check (task_kind in ('task', 'note')),
  add constraint smart_tasks_visibility_check
    check (visibility in ('private', 'team', 'company')),
  add constraint smart_tasks_status_domain_check
    check (status in ('pending', 'in_progress', 'blocked', 'completed', 'cancelled')),
  add constraint smart_tasks_priority_domain_check
    check (priority in ('low', 'normal', 'high', 'urgent')),
  add constraint smart_tasks_blocked_reason_check
    check (status <> 'blocked' or nullif(btrim(blocked_reason), '') is not null),
  add constraint smart_tasks_note_has_no_assignee_check
    check (task_kind <> 'note' or assigned_to is null),
  -- «Personal (solo yo)» es literal: sin responsable y sin pega. El
  -- compositor ya lo impide; la base lo garantiza para cualquier escritor.
  add constraint smart_tasks_private_is_personal_check
    check (
      visibility <> 'private'
      or (assigned_to is null and linked_job_id is null)
    );

create index if not exists idx_smart_tasks_tenant_assigned_status
  on public.smart_tasks (tenant_id, assigned_to, status);
create index if not exists idx_smart_tasks_tenant_private_creator
  on public.smart_tasks (tenant_id, created_by)
  where visibility = 'private';

-- La bandeja cancela o archiva; no borra físicamente. El botón Eliminar de
-- los clientes legados pasa a fallar con permiso denegado — honesto y
-- reversible — mientras la UI nueva ofrece Cancelar.
revoke delete on public.smart_tasks from anon, authenticated;

-- ============================================================================
-- 2. Autoridad y visibilidad
-- ============================================================================

create or replace function public.smart_task_can_view_v1(p_task_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.smart_tasks task
      where task.id = p_task_id
        and (
          (
            task.tenant_id = public.user_tenant_id()
            and (
              task.visibility in ('team', 'company')
              or task.created_by = auth.uid()
              or task.assigned_to = auth.uid()
            )
          )
          -- El asignado de portal no es miembro ERP pero sí ve lo suyo.
          or task.assigned_to = auth.uid()
        )
    );
$$;

grant execute on function public.smart_task_can_view_v1(uuid) to authenticated;
revoke execute on function public.smart_task_can_view_v1(uuid)
  from public, anon, service_role;

-- Un asignado elegible es un principal autenticado y activo del tenant:
-- miembro ERP (user_profiles activo) o cuenta de portal activa unida a un
-- empleado activo. Nada más recibe trabajo.
create or replace function public.smart_task_assignee_eligible_v1(
  p_tenant_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select p_tenant_id is not null and p_user_id is not null and (
    exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = p_user_id
        and profile.tenant_id = p_tenant_id
        and profile.is_active is true
    )
    or exists (
      select 1
      from public.employee_portal_accounts portal
      join public.employees employee
        on employee.id = portal.employee_id
       and employee.tenant_id = portal.tenant_id
       and employee.status = 'active'
      where portal.auth_user_id = p_user_id
        and portal.tenant_id = p_tenant_id
        and portal.is_active is true
    )
  );
$$;

-- Identidad de trabajador para tareas operativas de taller.
create or replace function public.smart_task_assignee_worker_linked_v1(
  p_tenant_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select p_tenant_id is not null and p_user_id is not null and (
    exists (
      select 1
      from public.user_profiles profile
      join public.employees employee
        on employee.id = profile.employee_id
       and employee.tenant_id = profile.tenant_id
       and employee.status = 'active'
      where profile.user_id = p_user_id
        and profile.tenant_id = p_tenant_id
        and profile.is_active is true
    )
    or exists (
      select 1
      from public.employees employee
      where employee.user_id = p_user_id
        and employee.tenant_id = p_tenant_id
        and employee.status = 'active'
    )
    or exists (
      select 1
      from public.employee_portal_accounts portal
      join public.employees employee
        on employee.id = portal.employee_id
       and employee.tenant_id = portal.tenant_id
       and employee.status = 'active'
      where portal.auth_user_id = p_user_id
        and portal.tenant_id = p_tenant_id
        and portal.is_active is true
    )
  );
$$;

-- ============================================================================
-- 3. Eventos append-only
--    ON DELETE RESTRICT: mientras exista un ledger, la tarea no puede
--    borrarse físicamente ni siquiera por mantenimiento descuidado.
-- ============================================================================

create table if not exists public.smart_task_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  task_id uuid not null references public.smart_tasks(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in (
    'created', 'details_updated', 'assigned', 'unassigned', 'acknowledged',
    'returned', 'started', 'blocked', 'unblocked', 'completed', 'reopened',
    'cancelled', 'visibility_changed', 'job_items_linked',
    'job_items_unlinked', 'conversation_linked',
    -- Contrato preparado para el checkpoint D (sin productor todavía):
    'due_soon', 'mentioned'
  )),
  task_version integer not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_smart_task_events_task
  on public.smart_task_events (task_id, created_at desc);
create index if not exists idx_smart_task_events_tenant_created
  on public.smart_task_events (tenant_id, created_at desc);

alter table public.smart_task_events enable row level security;

drop policy if exists smart_task_events_select on public.smart_task_events;
create policy smart_task_events_select on public.smart_task_events
  for select to authenticated
  using (public.smart_task_can_view_v1(task_id));

revoke insert, update, delete on public.smart_task_events
  from anon, authenticated;
revoke all on public.smart_task_events from anon;

-- ============================================================================
-- 4. Vínculo tarea ↔ servicios reales de la pega, con evidencia durable
--    Identidad propia; job_item_id/job_id SIN foreign key a propósito: si el
--    taller borra o edita la línea, el vínculo NO desaparece — conserva el
--    UUID y el snapshot originales y se marca invalidated_at /
--    context_changed_at para que la tarea siga siendo resoluble.
-- ============================================================================

create table if not exists public.smart_task_job_items (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.smart_tasks(id) on delete cascade,
  job_item_id uuid not null,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid not null,
  job_bike_id uuid,
  -- Snapshot de contexto: lo que el operador vio al vincular.
  item_name text not null,
  item_type text,
  job_number text,
  bike_label text,
  linked_by uuid references auth.users(id) on delete set null,
  linked_at timestamptz not null default now(),
  invalidated_at timestamptz,
  context_changed_at timestamptz,
  unique (task_id, job_item_id)
);

create index if not exists idx_smart_task_job_items_job_item
  on public.smart_task_job_items (job_item_id);
create index if not exists idx_smart_task_job_items_tenant_job
  on public.smart_task_job_items (tenant_id, job_id);

alter table public.smart_task_job_items enable row level security;

drop policy if exists smart_task_job_items_select on public.smart_task_job_items;
create policy smart_task_job_items_select on public.smart_task_job_items
  for select to authenticated
  using (public.smart_task_can_view_v1(task_id));

revoke insert, update, delete on public.smart_task_job_items
  from anon, authenticated;
revoke all on public.smart_task_job_items from anon;

-- Integridad al VINCULAR (la línea debe existir viva y ser trabajo real);
-- después del vínculo la evidencia es del ledger, no de la línea.
create or replace function public.smart_task_job_items_guard()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_item public.mechanic_job_items%rowtype;
  v_task public.smart_tasks%rowtype;
begin
  if tg_op = 'UPDATE' then
    -- Solo mutan las marcas de evidencia; la identidad del vínculo es fija.
    if new.task_id is distinct from old.task_id
      or new.job_item_id is distinct from old.job_item_id
      or new.tenant_id is distinct from old.tenant_id
      or new.job_id is distinct from old.job_id then
      raise exception 'smart_task_job_items: link identity is immutable'
        using errcode = '23514';
    end if;
    return new;
  end if;

  select * into v_task from public.smart_tasks where id = new.task_id;
  if not found then
    raise exception 'smart_task_job_items: task not found'
      using errcode = '23503';
  end if;
  if v_task.task_kind = 'note' then
    raise exception 'smart_tasks: a note keeps the job, never its service lines'
      using errcode = '23514', hint = 'note_has_no_services';
  end if;

  select * into v_item from public.mechanic_job_items where id = new.job_item_id;
  if not found then
    raise exception 'smart_task_job_items: job item not found'
      using errcode = '23503';
  end if;

  if v_item.tenant_id is distinct from v_task.tenant_id then
    raise exception 'smart_task_job_items: job item belongs to another tenant'
      using errcode = '42501';
  end if;
  if v_item.job_id is distinct from new.job_id then
    raise exception 'smart_task_job_items: job item does not belong to the declared job'
      using errcode = '23514';
  end if;
  if v_task.linked_job_id is distinct from new.job_id then
    raise exception 'smart_task_job_items: task is not linked to the declared job'
      using errcode = '23514';
  end if;
  -- Solo líneas de trabajo: 'service' y 'adhoc' (el checklist del taller crea
  -- ítems 'adhoc' para trabajo con precio ad-hoc; los productos no son
  -- trabajo asignable).
  if coalesce(v_item.item_type, '') not in ('service', 'adhoc') then
    raise exception 'smart_task_job_items: only service lines can back a task'
      using errcode = '23514', hint = 'job_item_not_service';
  end if;

  new.tenant_id := v_task.tenant_id;
  new.job_bike_id := v_item.job_bike_id;
  return new;
end;
$$;

drop trigger if exists trg_smart_task_job_items_guard on public.smart_task_job_items;
create trigger trg_smart_task_job_items_guard
  before insert or update on public.smart_task_job_items
  for each row execute function public.smart_task_job_items_guard();

-- La edición o eliminación de la línea del taller marca la evidencia, nunca
-- la borra.
create or replace function public.smart_task_job_items_mark_invalidated()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  update public.smart_task_job_items link
     set invalidated_at = coalesce(link.invalidated_at, now())
   where link.job_item_id = old.id;
  return old;
end;
$$;

create or replace function public.smart_task_job_items_mark_context_changed()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  if new.product_name is distinct from old.product_name
    or new.description is distinct from old.description
    or new.item_type is distinct from old.item_type
    or new.job_bike_id is distinct from old.job_bike_id then
    update public.smart_task_job_items link
       set context_changed_at = now()
     where link.job_item_id = new.id
       and link.invalidated_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_smart_task_link_invalidate on public.mechanic_job_items;
create trigger trg_smart_task_link_invalidate
  after delete on public.mechanic_job_items
  for each row execute function public.smart_task_job_items_mark_invalidated();

drop trigger if exists trg_smart_task_link_context_changed on public.mechanic_job_items;
create trigger trg_smart_task_link_context_changed
  after update on public.mechanic_job_items
  for each row execute function public.smart_task_job_items_mark_context_changed();

-- ============================================================================
-- 5. Estado por usuario: visto, pin y snooze
--    La verdad del badge personal: una tarea cuenta como no vista para su
--    asignado mientras seen_version < version (o no exista fila).
-- ============================================================================

create table if not exists public.smart_task_user_state (
  task_id uuid not null references public.smart_tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  seen_at timestamptz,
  seen_version integer,
  pinned_at timestamptz,
  snoozed_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (task_id, user_id)
);

alter table public.smart_task_user_state enable row level security;

-- Estado propio, de tareas que el usuario realmente puede ver. Escritura
-- directa a propósito: es preferencia personal, no verdad de negocio.
drop policy if exists smart_task_user_state_select on public.smart_task_user_state;
create policy smart_task_user_state_select on public.smart_task_user_state
  for select to authenticated
  using (user_id = auth.uid());
drop policy if exists smart_task_user_state_insert on public.smart_task_user_state;
create policy smart_task_user_state_insert on public.smart_task_user_state
  for insert to authenticated
  with check (
    user_id = auth.uid() and public.smart_task_can_view_v1(task_id)
  );
drop policy if exists smart_task_user_state_update on public.smart_task_user_state;
create policy smart_task_user_state_update on public.smart_task_user_state
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
drop policy if exists smart_task_user_state_delete on public.smart_task_user_state;
create policy smart_task_user_state_delete on public.smart_task_user_state
  for delete to authenticated
  using (user_id = auth.uid());

revoke all on public.smart_task_user_state from anon;

create or replace function public.smart_task_user_state_guard()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  select task.tenant_id into new.tenant_id
  from public.smart_tasks task where task.id = new.task_id;
  if new.tenant_id is null then
    raise exception 'smart_task_user_state: task not found'
      using errcode = '23503';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_smart_task_user_state_guard on public.smart_task_user_state;
create trigger trg_smart_task_user_state_guard
  before insert or update on public.smart_task_user_state
  for each row execute function public.smart_task_user_state_guard();

-- ============================================================================
-- 6. Recibos de comandos idempotentes
-- ============================================================================

create table if not exists public.smart_task_command_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  command_type text not null,
  idempotency_key text not null,
  actor_id uuid not null,
  request_fingerprint text not null,
  task_id uuid,
  result jsonb not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, command_type, actor_id, idempotency_key)
);

alter table public.smart_task_command_receipts enable row level security;
revoke all on public.smart_task_command_receipts from anon, authenticated;

-- Claim ATÓMICO: el lock transaccional serializa dos solicitudes concurrentes
-- con la misma clave; la segunda espera y encuentra el recibo de la primera.
create or replace function public.smart_task_claim_receipt(
  p_tenant_id uuid,
  p_actor uuid,
  p_command_type text,
  p_idempotency_key text,
  p_fingerprint text,
  out o_replay jsonb
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_existing public.smart_task_command_receipts%rowtype;
begin
  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null
    or length(btrim(p_idempotency_key)) > 200 then
    raise exception 'smart_tasks: idempotency key is required'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws('|', p_tenant_id::text, p_command_type, p_actor::text,
      btrim(p_idempotency_key)),
    42
  ));

  select * into v_existing
  from public.smart_task_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.command_type = p_command_type
    and receipt.actor_id = p_actor
    and receipt.idempotency_key = btrim(p_idempotency_key);

  if found then
    if v_existing.request_fingerprint <> p_fingerprint then
      raise exception 'smart_tasks: idempotency key reused with different arguments'
        using errcode = '22023', hint = 'idempotency_conflict';
    end if;
    o_replay := v_existing.result;
  else
    o_replay := null;
  end if;
end;
$$;

create or replace function public.smart_task_store_receipt(
  p_tenant_id uuid,
  p_actor uuid,
  p_command_type text,
  p_idempotency_key text,
  p_fingerprint text,
  p_task_id uuid,
  p_result jsonb
)
returns void
language sql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  insert into public.smart_task_command_receipts (
    tenant_id, command_type, idempotency_key, actor_id,
    request_fingerprint, task_id, result
  ) values (
    p_tenant_id, p_command_type, btrim(p_idempotency_key), p_actor,
    p_fingerprint, p_task_id, p_result
  )
  on conflict (tenant_id, command_type, actor_id, idempotency_key) do nothing;
$$;

revoke all on function public.smart_task_claim_receipt(uuid, uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_store_receipt(uuid, uuid, text, text, text, uuid, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- 7. Guard de mutación sobre smart_tasks
--    Disciplina de versión, grafo de transiciones, sellos de evidencia,
--    elegibilidad del asignado y LÍMITE POR ACTOR también para la ruta
--    directa del cliente legado: el asignado opera su ciclo de vida; el
--    título, el alcance, la visibilidad y la reasignación son de
--    creador/manager.
-- ============================================================================

create or replace function public.smart_tasks_guard_work_tray()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_cmd text := coalesce(current_setting('vinabike.smart_task_cmd', true), '');
  v_is_creator boolean;
  v_is_manager boolean;
  v_worker_required boolean;
  v_requested_blocked_reason text;
begin
  if tg_op = 'INSERT' then
    new.version := 1;
    if new.task_kind = 'note'
      and new.status not in ('pending', 'cancelled') then
      raise exception 'smart_tasks: notes have no execution lifecycle'
        using errcode = '23514', hint = 'note_has_no_lifecycle';
    end if;
    if new.visibility = 'private'
      and (new.assigned_to is not null or new.linked_job_id is not null) then
      raise exception 'smart_tasks: a private task is personal — no assignee, no job'
        using errcode = '23514', hint = 'private_is_personal';
    end if;
    if new.linked_job_id is not null and not exists (
      select 1
      from public.mechanic_jobs job
      where job.id = new.linked_job_id
        and job.tenant_id = new.tenant_id
        and job.deleted_at is null
    ) then
      raise exception 'smart_tasks: job not found in tenant or is archived'
        using errcode = '23503', hint = 'job_not_linkable';
    end if;

    -- Las columnas de evidencia son server-owned incluso durante la fase de
    -- compatibilidad con INSERT directo. Un cliente legado no las conoce; un
    -- cliente manipulado no puede atribuir la asignación o el ciclo a otro
    -- usuario ni sembrar timestamps falsos.
    new.acknowledged_at := null;
    new.acknowledged_by := null;
    if new.assigned_to is not null then
      if not public.smart_task_assignee_eligible_v1(new.tenant_id, new.assigned_to) then
        raise exception 'smart_tasks: assignee is not an active principal of this tenant'
          using errcode = '23514', hint = 'assignee_not_eligible';
      end if;
      if new.linked_job_id is not null
        and not public.smart_task_assignee_worker_linked_v1(new.tenant_id, new.assigned_to) then
        raise exception 'smart_tasks: workshop tasks require an assignee linked to a worker'
          using errcode = '23514', hint = 'assignee_not_worker_linked';
      end if;
      new.assigned_at := now();
      new.assigned_by := coalesce(v_actor, new.created_by);
    else
      new.assigned_at := null;
      new.assigned_by := null;
    end if;
    new.started_at := case when new.status = 'in_progress' then now() else null end;
    if new.status = 'completed' then
      new.completed_at := now();
      new.completed_by := coalesce(v_actor, new.created_by);
    else
      new.completed_at := null;
      new.completed_by := null;
    end if;
    if new.status = 'cancelled' then
      new.cancelled_at := now();
      new.cancelled_by := coalesce(v_actor, new.created_by);
    else
      new.cancelled_at := null;
      new.cancelled_by := null;
    end if;
    if new.status = 'blocked' then
      new.blocked_at := now();
      new.blocked_by := coalesce(v_actor, new.created_by);
      new.blocked_reason := nullif(btrim(new.blocked_reason), '');
    else
      new.blocked_at := null;
      new.blocked_by := null;
      new.blocked_reason := null;
    end if;
    return new;
  end if;

  -- La versión no la decide el cliente, y la autoría de origen es inmutable.
  new.version := old.version + 1;
  new.tenant_id := old.tenant_id;
  new.created_by := old.created_by;
  new.created_at := old.created_at;

  -- Salvo el acuse emitido por el comando canónico, toda evidencia se
  -- deriva abajo de la transición real y nunca de columnas enviadas por el
  -- cliente. Se captura el motivo antes de restaurar el valor persistido.
  v_requested_blocked_reason := new.blocked_reason;
  new.assigned_at := old.assigned_at;
  new.assigned_by := old.assigned_by;
  if v_cmd <> 'acknowledge' then
    new.acknowledged_at := old.acknowledged_at;
    new.acknowledged_by := old.acknowledged_by;
  end if;
  new.started_at := old.started_at;
  new.completed_at := old.completed_at;
  new.completed_by := old.completed_by;
  new.cancelled_at := old.cancelled_at;
  new.cancelled_by := old.cancelled_by;
  new.blocked_at := old.blocked_at;
  new.blocked_by := old.blocked_by;
  new.blocked_reason := old.blocked_reason;

  v_is_creator := v_actor is not null and old.created_by = v_actor;
  v_is_manager := v_actor is not null
    and public.can_manage_tenant_users(old.tenant_id);

  -- Alcance, identidad y visibilidad pertenecen a creador/manager, también
  -- por la ruta directa. (v_actor null = mantenimiento/servicio interno.)
  if v_actor is not null and not (v_is_creator or v_is_manager) then
    if new.title is distinct from old.title
      or new.description is distinct from old.description
      or new.priority is distinct from old.priority
      or new.due_date is distinct from old.due_date
      or new.visibility is distinct from old.visibility
      or new.task_kind is distinct from old.task_kind
      or new.linked_job_id is distinct from old.linked_job_id
      or new.linked_customer_id is distinct from old.linked_customer_id
      or new.linked_supplier_id is distinct from old.linked_supplier_id
      or new.linked_purchase_invoice_id is distinct from old.linked_purchase_invoice_id
      or new.linked_sales_invoice_id is distinct from old.linked_sales_invoice_id then
      raise exception 'smart_tasks: only the creator or a manager edits scope and details'
        using errcode = '42501', hint = 'not_authorized_scope';
    end if;
  end if;

  -- Cambio de responsable: creador/manager reasignan; el asignado solo puede
  -- devolver (a null). Re-valida elegibilidad y reinicia la recepción.
  if new.assigned_to is distinct from old.assigned_to then
    if v_actor is not null
      and not (v_is_creator or v_is_manager)
      and not (v_actor = old.assigned_to and new.assigned_to is null) then
      raise exception 'smart_tasks: only the creator or a manager reassigns'
        using errcode = '42501', hint = 'not_authorized_assign';
    end if;
    if new.assigned_to is not null then
      if not public.smart_task_assignee_eligible_v1(new.tenant_id, new.assigned_to) then
        raise exception 'smart_tasks: assignee is not an active principal of this tenant'
          using errcode = '23514', hint = 'assignee_not_eligible';
      end if;
      v_worker_required := new.linked_job_id is not null
        or exists (
          select 1 from public.smart_task_job_items link
          where link.task_id = new.id and link.invalidated_at is null
        );
      if v_worker_required
        and not public.smart_task_assignee_worker_linked_v1(new.tenant_id, new.assigned_to) then
        raise exception 'smart_tasks: workshop tasks require an assignee linked to a worker'
          using errcode = '23514', hint = 'assignee_not_worker_linked';
      end if;
      new.assigned_at := now();
      new.assigned_by := v_actor;
    else
      new.assigned_at := null;
      new.assigned_by := null;
    end if;
    new.acknowledged_at := null;
    new.acknowledged_by := null;
  end if;

  -- El vínculo a pega puede llegar después de la creación: la identidad de
  -- trabajador se re-exige aquí para todo camino.
  if new.linked_job_id is distinct from old.linked_job_id
  then
    if v_cmd = '' and exists (
      select 1 from public.smart_task_job_items link
      where link.task_id = old.id
    ) then
      raise exception 'smart_tasks: relink service-backed tasks through the canonical command'
        using errcode = '23514', hint = 'job_items_require_command';
    end if;
    if new.linked_job_id is not null and not exists (
      select 1
      from public.mechanic_jobs job
      where job.id = new.linked_job_id
        and job.tenant_id = new.tenant_id
        and job.deleted_at is null
    ) then
      raise exception 'smart_tasks: job not found in tenant or is archived'
        using errcode = '23503', hint = 'job_not_linkable';
    end if;
    if new.linked_job_id is not null
      and new.assigned_to is not null
      and not public.smart_task_assignee_worker_linked_v1(new.tenant_id, new.assigned_to) then
      raise exception 'smart_tasks: workshop tasks require an assignee linked to a worker'
        using errcode = '23514', hint = 'assignee_not_worker_linked';
    end if;
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'pending' and new.status in ('in_progress', 'blocked', 'completed', 'cancelled'))
      or (old.status = 'in_progress' and new.status in ('pending', 'blocked', 'completed', 'cancelled'))
      or (old.status = 'blocked' and new.status in ('pending', 'in_progress', 'completed', 'cancelled'))
      or (old.status = 'completed' and new.status = 'pending')
      or (old.status = 'cancelled' and new.status = 'pending')
    ) then
      raise exception 'smart_tasks: illegal status transition % -> %', old.status, new.status
        using errcode = '23514', hint = 'illegal_transition';
    end if;

    -- Una nota solo vive (pending) o se archiva (cancelled): Archivar y
    -- Restaurar. Nada del ciclo de tarea.
    if new.task_kind = 'note' and not (
      (old.status = 'pending' and new.status = 'cancelled')
      or (old.status = 'cancelled' and new.status = 'pending')
    ) then
      raise exception 'smart_tasks: notes have no execution lifecycle'
        using errcode = '23514', hint = 'note_has_no_lifecycle';
    end if;

    if new.status = 'in_progress' then
      new.started_at := coalesce(new.started_at, old.started_at, now());
    end if;
    if new.status = 'completed' then
      new.completed_at := now();
      new.completed_by := v_actor;
    elsif old.status = 'completed' then
      new.completed_at := null;
      new.completed_by := null;
    end if;
    if new.status = 'cancelled' then
      new.cancelled_at := now();
      new.cancelled_by := v_actor;
    elsif old.status = 'cancelled' then
      new.cancelled_at := null;
      new.cancelled_by := null;
    end if;
    if new.status = 'blocked' then
      new.blocked_at := now();
      new.blocked_by := v_actor;
      new.blocked_reason := nullif(btrim(v_requested_blocked_reason), '');
    elsif old.status = 'blocked' then
      new.blocked_at := null;
      new.blocked_by := null;
      new.blocked_reason := null;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_smart_tasks_guard_work_tray on public.smart_tasks;
create trigger trg_smart_tasks_guard_work_tray
  before insert or update on public.smart_tasks
  for each row execute function public.smart_tasks_guard_work_tray();

-- La ruta directa legada también queda en el ledger. Los RPC marcan su
-- comando en un GUC local; si no está marcado, el cambio vino directo y se
-- audita aquí con source='direct'.
create or replace function public.smart_tasks_audit_direct_write()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_cmd text := coalesce(current_setting('vinabike.smart_task_cmd', true), '');
  v_actor uuid := auth.uid();
  v_event text;
  v_fields text[] := array[]::text[];
begin
  if v_cmd <> '' then
    return new;
  end if;

  if new.status is distinct from old.status then
    v_event := case
      when new.status = 'in_progress' and old.status = 'blocked' then 'unblocked'
      when new.status = 'in_progress' then 'started'
      when new.status = 'blocked' then 'blocked'
      when new.status = 'completed' then 'completed'
      when new.status = 'cancelled' then 'cancelled'
      when new.status = 'pending' and old.status = 'blocked' then 'unblocked'
      when new.status = 'pending' then 'reopened'
    end;
    if v_event is not null then
      insert into public.smart_task_events (
        tenant_id, task_id, actor_user_id, event_type, task_version, payload
      ) values (
        new.tenant_id, new.id, v_actor, v_event, new.version,
        jsonb_strip_nulls(jsonb_build_object(
          'source', 'direct',
          'reason', case when v_event = 'blocked' then new.blocked_reason end
        ))
      );
    end if;
  end if;

  if new.assigned_to is distinct from old.assigned_to then
    insert into public.smart_task_events (
      tenant_id, task_id, actor_user_id, event_type, task_version, payload
    ) values (
      new.tenant_id, new.id, v_actor,
      case when new.assigned_to is null then 'unassigned' else 'assigned' end,
      new.version,
      jsonb_strip_nulls(jsonb_build_object(
        'source', 'direct',
        'assigned_to', new.assigned_to,
        'previous_assignee', old.assigned_to
      ))
    );
    -- El hilo sigue al trabajo también cuando la reasignación entró por la
    -- ruta directa legada.
    perform public.smart_task_thread_sync_participants(
      new, new.assigned_to, old.assigned_to);
  end if;

  if new.title is distinct from old.title then v_fields := v_fields || 'title'; end if;
  if new.description is distinct from old.description then v_fields := v_fields || 'description'; end if;
  if new.priority is distinct from old.priority then v_fields := v_fields || 'priority'; end if;
  if new.due_date is distinct from old.due_date then v_fields := v_fields || 'due_date'; end if;
  if new.visibility is distinct from old.visibility then v_fields := v_fields || 'visibility'; end if;
  if new.linked_job_id is distinct from old.linked_job_id then v_fields := v_fields || 'linked_job_id'; end if;
  if new.attachments is distinct from old.attachments then v_fields := v_fields || 'attachments'; end if;
  if array_length(v_fields, 1) > 0 then
    insert into public.smart_task_events (
      tenant_id, task_id, actor_user_id, event_type, task_version, payload
    ) values (
      new.tenant_id, new.id, v_actor, 'details_updated', new.version,
      jsonb_build_object('source', 'direct', 'fields', to_jsonb(v_fields))
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_smart_tasks_audit_direct_write on public.smart_tasks;
create trigger trg_smart_tasks_audit_direct_write
  after update on public.smart_tasks
  for each row execute function public.smart_tasks_audit_direct_write();

-- Los clientes ya instalados y las aprobaciones del asistente todavía
-- INSERTAN directo. Su nacimiento también queda en el ledger (y su
-- asignación notifica), sin duplicar lo que ya escribe la RPC (GUC).
create or replace function public.smart_tasks_audit_direct_insert()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_cmd text := coalesce(current_setting('vinabike.smart_task_cmd', true), '');
begin
  if v_cmd <> '' then
    return new;
  end if;

  insert into public.smart_task_events (
    tenant_id, task_id, actor_user_id, event_type, task_version, payload
  ) values (
    new.tenant_id, new.id, coalesce(auth.uid(), new.created_by), 'created',
    new.version,
    jsonb_strip_nulls(jsonb_build_object(
      'source', 'direct',
      'title', new.title,
      'visibility', new.visibility,
      'task_kind', new.task_kind
    ))
  );
  if new.assigned_to is not null then
    insert into public.smart_task_events (
      tenant_id, task_id, actor_user_id, event_type, task_version, payload
    ) values (
      new.tenant_id, new.id, coalesce(auth.uid(), new.created_by), 'assigned',
      new.version,
      jsonb_build_object('source', 'direct', 'assigned_to', new.assigned_to)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_smart_tasks_audit_direct_insert on public.smart_tasks;
create trigger trg_smart_tasks_audit_direct_insert
  after insert on public.smart_tasks
  for each row execute function public.smart_tasks_audit_direct_insert();

-- ============================================================================
-- 8. RLS de smart_tasks: autoridad real en vez de tenant-wide
-- ============================================================================

drop policy if exists "Users can view tasks in their tenant" on public.smart_tasks;
drop policy if exists "Users can insert tasks in their tenant" on public.smart_tasks;
drop policy if exists "Users can update tasks in their tenant" on public.smart_tasks;
drop policy if exists "Users can delete tasks in their tenant" on public.smart_tasks;
drop policy if exists smart_tasks_select on public.smart_tasks;
drop policy if exists smart_tasks_insert on public.smart_tasks;
drop policy if exists smart_tasks_update on public.smart_tasks;
drop policy if exists smart_tasks_delete on public.smart_tasks;

create policy smart_tasks_select on public.smart_tasks
  for select to authenticated
  using (
    (
      tenant_id = public.user_tenant_id()
      and (
        visibility in ('team', 'company')
        or created_by = auth.uid()
        or assigned_to = auth.uid()
      )
    )
    or assigned_to = auth.uid()
  );

create policy smart_tasks_insert on public.smart_tasks
  for insert to authenticated
  with check (
    tenant_id = public.user_tenant_id()
    and created_by = auth.uid()
  );

create policy smart_tasks_update on public.smart_tasks
  for update to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and (
      created_by = auth.uid()
      or assigned_to = auth.uid()
      or public.can_manage_tenant_users(tenant_id)
    )
  )
  with check (tenant_id = public.user_tenant_id());

-- Sin política DELETE: la bandeja cancela, no borra.

-- Un solo trigger de updated_at (producción tenía dos duplicados; el fixture
-- local solo el legado). Se normaliza al nombre canónico.
drop trigger if exists handle_updated_at_smart_tasks on public.smart_tasks;
drop trigger if exists trg_smart_tasks_updated_at on public.smart_tasks;
create trigger trg_smart_tasks_updated_at
  before update on public.smart_tasks
  for each row execute function public.set_updated_at();

-- ============================================================================
-- 9. Núcleo compartido de comandos (no expuesto a clientes)
-- ============================================================================

create or replace function public.smart_task_row_to_json(p_task public.smart_tasks)
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select to_jsonb(p_task);
$$;

create or replace function public.smart_task_append_event(
  p_task public.smart_tasks,
  p_actor uuid,
  p_event_type text,
  p_payload jsonb
)
returns void
language sql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  insert into public.smart_task_events (
    tenant_id, task_id, actor_user_id, event_type, task_version, payload
  ) values (
    p_task.tenant_id, p_task.id, p_actor, p_event_type, p_task.version,
    coalesce(p_payload, '{}'::jsonb)
  );
$$;

create or replace function public.smart_task_set_job_items_internal(
  p_task public.smart_tasks,
  p_actor uuid,
  p_job_id uuid,
  p_job_item_ids uuid[]
)
returns public.smart_tasks
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_requested int;
  v_eligible int;
  v_present int;
  v_task public.smart_tasks;
begin
  if p_job_id is null then
    delete from public.smart_task_job_items where task_id = p_task.id;
    update public.smart_tasks
       set linked_job_id = null, updated_at = now()
     where id = p_task.id
     returning * into v_task;
    perform public.smart_task_append_event(
      v_task, p_actor, 'job_items_unlinked',
      jsonb_build_object('previous_job_id', p_task.linked_job_id)
    );
    return v_task;
  end if;

  select * into v_job from public.mechanic_jobs
   where id = p_job_id and tenant_id = p_task.tenant_id;
  if not found then
    raise exception 'smart_tasks: job not found in tenant'
      using errcode = '23503', hint = 'job_not_found';
  end if;
  if v_job.deleted_at is not null then
    raise exception 'smart_tasks: cannot link an archived job'
      using errcode = '23514', hint = 'job_archived';
  end if;

  if p_task.task_kind = 'note'
    and p_job_item_ids is not null
    and array_length(p_job_item_ids, 1) > 0 then
    raise exception 'smart_tasks: a note keeps the job, never its service lines'
      using errcode = '23514', hint = 'note_has_no_services';
  end if;

  if p_job_item_ids is not null and array_length(p_job_item_ids, 1) > 0 then
    v_requested := (
      select count(distinct item_id) from unnest(p_job_item_ids) as item_id
    );
    select count(*) into v_present
    from public.mechanic_job_items item
    where item.id = any (p_job_item_ids)
      and item.job_id = p_job_id
      and item.tenant_id = p_task.tenant_id;
    if v_present <> v_requested then
      raise exception 'smart_tasks: % job item(s) do not belong to the linked job',
        v_requested - v_present
        using errcode = '23514', hint = 'job_items_outside_job';
    end if;
    select count(*) into v_eligible
    from public.mechanic_job_items item
    where item.id = any (p_job_item_ids)
      and item.job_id = p_job_id
      and item.tenant_id = p_task.tenant_id
      and coalesce(item.item_type, '') in ('service', 'adhoc');
    if v_eligible <> v_requested then
      raise exception 'smart_tasks: only service lines can back a task'
        using errcode = '23514', hint = 'job_item_not_service';
    end if;
  end if;

  update public.smart_tasks
     set linked_job_id = p_job_id, updated_at = now()
   where id = p_task.id
   returning * into v_task;

  delete from public.smart_task_job_items where task_id = p_task.id;

  if p_job_item_ids is not null and array_length(p_job_item_ids, 1) > 0 then
    insert into public.smart_task_job_items (
      task_id, job_item_id, tenant_id, job_id, job_bike_id,
      item_name, item_type, job_number, bike_label, linked_by
    )
    select
      v_task.id,
      item.id,
      v_task.tenant_id,
      v_job.id,
      item.job_bike_id,
      coalesce(
        nullif(btrim(item.description), ''),
        nullif(btrim(item.product_name), ''),
        'Ítem de pega'
      ),
      item.item_type,
      v_job.job_number,
      (
        select nullif(btrim(concat_ws(' ', bike.brand, bike.model)), '')
        from public.mechanic_job_bikes job_bike
        join public.bikes bike on bike.id = job_bike.bike_id
        where job_bike.id = item.job_bike_id
      ),
      p_actor
    from public.mechanic_job_items item
    where item.id = any (p_job_item_ids)
      and item.job_id = v_job.id
      and item.tenant_id = v_task.tenant_id;
  end if;

  perform public.smart_task_append_event(
    v_task, p_actor, 'job_items_linked',
    jsonb_build_object(
      'job_id', v_job.id,
      'job_number', v_job.job_number,
      'job_item_ids', coalesce(to_jsonb(p_job_item_ids), '[]'::jsonb)
    )
  );
  return v_task;
end;
$$;

-- Tareas activas de otro responsable sobre los mismos servicios vivos.
create or replace function public.smart_task_active_overlaps(
  p_tenant_id uuid,
  p_job_item_ids uuid[],
  p_exclude_task uuid default null
)
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select coalesce(jsonb_agg(overlap_row), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'task_id', task.id,
      'title', task.title,
      'status', task.status,
      'assigned_to', task.assigned_to,
      'job_item_ids', (
        select jsonb_agg(link_inner.job_item_id)
        from public.smart_task_job_items link_inner
        where link_inner.task_id = task.id
          and link_inner.job_item_id = any (p_job_item_ids)
          and link_inner.invalidated_at is null
      )
    ) as overlap_row
    from public.smart_tasks task
    where task.tenant_id = p_tenant_id
      and task.task_kind = 'task'
      and task.status in ('pending', 'in_progress', 'blocked')
      and (p_exclude_task is null or task.id <> p_exclude_task)
      and exists (
        select 1 from public.smart_task_job_items link
        where link.task_id = task.id
          and link.job_item_id = any (p_job_item_ids)
          and link.invalidated_at is null
      )
  ) overlap_rows;
$$;

-- Serializa decisiones sobre los mismos servicios. Sin este lock, dos
-- sesiones podían observar simultáneamente «sin solape» y ambas crear una
-- reserva activa antes de que la otra hiciera visible su vínculo. El orden
-- determinista evita deadlocks cuando una tarea contiene varios servicios.
create or replace function public.smart_task_lock_job_items(
  p_tenant_id uuid,
  p_job_item_ids uuid[]
)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_item_id uuid;
begin
  if p_tenant_id is null or array_length(p_job_item_ids, 1) is null then
    return;
  end if;
  -- Todas las operaciones que pueden transferir vínculos toman primero este
  -- lock por tenant. Así ninguna conserva su propia fila de tarea mientras
  -- otra conserva los servicios y trata de actualizarla en orden inverso.
  -- Los locks por item permanecen como identidad explícita del conflicto.
  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws('|', 'smart_task_job_items_tenant', p_tenant_id::text),
    73
  ));
  for v_item_id in
    select distinct requested.item_id
    from unnest(p_job_item_ids) as requested(item_id)
    order by requested.item_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      concat_ws('|', 'smart_task_job_item', p_tenant_id::text,
        v_item_id::text),
      73
    ));
  end loop;
end;
$$;

create or replace function public.smart_task_transfer_overlaps(
  p_actor uuid,
  p_tenant_id uuid,
  p_target_task uuid,
  p_job_item_ids uuid[]
)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_other record;
  v_task public.smart_tasks%rowtype;
begin
  for v_other in
    select link.task_id, array_agg(link.job_item_id) as item_ids
    from public.smart_task_job_items link
    join public.smart_tasks task on task.id = link.task_id
    where link.tenant_id = p_tenant_id
      and link.job_item_id = any (p_job_item_ids)
      and link.task_id <> p_target_task
      and link.invalidated_at is null
      and task.task_kind = 'task'
      and task.status in ('pending', 'in_progress', 'blocked')
    group by link.task_id
  loop
    delete from public.smart_task_job_items
    where task_id = v_other.task_id
      and job_item_id = any (v_other.item_ids);
    update public.smart_tasks
       set updated_at = now()
     where id = v_other.task_id
     returning * into v_task;
    perform public.smart_task_append_event(
      v_task, p_actor, 'job_items_unlinked',
      jsonb_build_object(
        'transferred_to_task', p_target_task,
        'job_item_ids', to_jsonb(v_other.item_ids)
      )
    );
  end loop;
end;
$$;

-- ¿Este usuario tiene autoridad de manager en el tenant? (Por usuario, no
-- por caller: se usa para decidir la permanencia en el hilo.)
create or replace function public.smart_task_user_is_manager(
  p_tenant_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = p_user_id
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role in ('admin', 'manager')
        or profile.permissions @> '{"manage_users": true}'::jsonb
      )
  );
$$;

-- El hilo sigue al trabajo: al reasignar o devolver, entra el nuevo
-- responsable (si es principal ERP; el portal no es principal de mensajería
-- y no se le finge hilo) y SALE el anterior, salvo que sea el creador o un
-- manager. El historial de sus mensajes permanece en la conversación.
create or replace function public.smart_task_thread_sync_participants(
  p_task public.smart_tasks,
  p_new_assignee uuid,
  p_previous_assignee uuid
)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_conversation uuid;
begin
  select context.conversation_id into v_conversation
  from public.conversation_contexts context
  where context.context_type = 'task' and context.context_id = p_task.id
  limit 1;
  if v_conversation is null then
    return;
  end if;

  if p_new_assignee is not null and exists (
    select 1 from public.user_profiles profile
    where profile.user_id = p_new_assignee
      and profile.tenant_id = p_task.tenant_id
      and profile.is_active is true
  ) then
    insert into public.conversation_participants (conversation_id, user_id, tenant_id)
    select v_conversation, p_new_assignee, p_task.tenant_id
    where not exists (
      select 1 from public.conversation_participants participant
      where participant.conversation_id = v_conversation
        and participant.user_id = p_new_assignee
    );
  end if;

  if p_previous_assignee is not null
    and p_previous_assignee is distinct from p_new_assignee
    and p_previous_assignee is distinct from p_task.created_by
    and not public.smart_task_user_is_manager(p_task.tenant_id, p_previous_assignee) then
    delete from public.conversation_participants participant
    where participant.conversation_id = v_conversation
      and participant.user_id = p_previous_assignee;
  end if;
end;
$$;

revoke all on function public.smart_task_row_to_json(public.smart_tasks)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_append_event(public.smart_tasks, uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_set_job_items_internal(public.smart_tasks, uuid, uuid, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_active_overlaps(uuid, uuid[], uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_lock_job_items(uuid, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_transfer_overlaps(uuid, uuid, uuid, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_user_is_manager(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_assignee_eligible_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_assignee_worker_linked_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_thread_sync_participants(public.smart_tasks, uuid, uuid)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- 10. Comando central (ERP y portal delegan aquí)
--     Autoridad por comando:
--       asignado ......... acknowledge, return, start, block, unblock, complete
--       creador/manager .. assign, cancel, reopen, update_details,
--                          set_visibility, set_job_items (+ block/unblock/
--                          complete como supervisión)
-- ============================================================================

create or replace function public.smart_task_apply_command(
  p_actor uuid,
  p_tenant_id uuid,
  p_is_manager boolean,
  p_allowed_commands text[],
  p_task_id uuid,
  p_expected_version integer,
  p_command text,
  p_payload jsonb
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_task public.smart_tasks%rowtype;
  v_is_creator boolean;
  v_is_assignee boolean;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_new_assignee uuid;
  v_reason text;
  v_previous_assignee uuid;
  v_job_id uuid;
  v_item_ids uuid[];
  v_overlaps jsonb;
begin
  perform set_config('vinabike.smart_task_cmd', p_command, true);

  if not coalesce(p_command = any (p_allowed_commands), false) then
    raise exception 'smart_tasks: command % is not allowed on this surface', p_command
      using errcode = '42501', hint = 'command_not_allowed';
  end if;

  -- El orden global de recursos es identidad de servicios -> filas de tarea.
  -- Debe ocurrir antes del FOR UPDATE propio: transferir vínculos también
  -- actualiza otras tareas y el orden contrario abre un ciclo de deadlock.
  if p_command = 'set_job_items' then
    v_item_ids := case
      when v_payload ? 'job_item_ids' then (
        select array_agg(value::uuid)
        from jsonb_array_elements_text(v_payload -> 'job_item_ids')
      )
      else null
    end;
    perform public.smart_task_lock_job_items(p_tenant_id, v_item_ids);
  end if;

  select * into v_task
  from public.smart_tasks
  where id = p_task_id and tenant_id = p_tenant_id
  for update;
  if not found then
    raise exception 'smart_tasks: task not found'
      using errcode = '23503', hint = 'task_not_found';
  end if;

  if p_expected_version is not null and p_expected_version <> v_task.version then
    raise exception 'smart_tasks: version conflict (expected %, current %)',
      p_expected_version, v_task.version
      using errcode = '40001', hint = 'version_conflict';
  end if;

  if v_task.task_kind = 'note' and p_command in (
    'assign', 'acknowledge', 'return', 'start', 'block', 'unblock', 'complete'
  ) then
    raise exception 'smart_tasks: notes have no execution lifecycle'
      using errcode = '23514', hint = 'note_has_no_lifecycle';
  end if;

  v_is_creator := v_task.created_by = p_actor;
  v_is_assignee := v_task.assigned_to = p_actor;

  case p_command
    when 'assign' then
      if not (v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the creator or a manager reassigns'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      v_new_assignee := nullif(v_payload ->> 'assigned_to', '')::uuid;
      v_previous_assignee := v_task.assigned_to;
      update public.smart_tasks
         set assigned_to = v_new_assignee, updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(
        v_task, p_actor,
        case when v_new_assignee is null then 'unassigned' else 'assigned' end,
        jsonb_strip_nulls(jsonb_build_object(
          'assigned_to', v_new_assignee,
          'previous_assignee', v_previous_assignee
        ))
      );
      perform public.smart_task_thread_sync_participants(
        v_task, v_new_assignee, v_previous_assignee);

    when 'acknowledge' then
      if not v_is_assignee then
        raise exception 'smart_tasks: only the assignee acknowledges'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set acknowledged_at = coalesce(acknowledged_at, now()),
             acknowledged_by = coalesce(acknowledged_by, p_actor),
             updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(v_task, p_actor, 'acknowledged', '{}'::jsonb);

    when 'return' then
      if not v_is_assignee then
        raise exception 'smart_tasks: only the assignee returns a task'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      v_reason := nullif(btrim(coalesce(v_payload ->> 'reason', '')), '');
      if v_reason is null then
        raise exception 'smart_tasks: returning a task requires a reason'
          using errcode = '22023', hint = 'reason_required';
      end if;
      v_previous_assignee := v_task.assigned_to;
      update public.smart_tasks
         set assigned_to = null,
             status = case when status = 'in_progress' then 'pending' else status end,
             updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(
        v_task, p_actor, 'returned',
        jsonb_build_object('reason', v_reason, 'previous_assignee', v_previous_assignee)
      );
      perform public.smart_task_thread_sync_participants(
        v_task, null, v_previous_assignee);

    when 'start' then
      if not (v_is_assignee or p_is_manager) then
        raise exception 'smart_tasks: only the assignee or a manager starts a task'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set status = 'in_progress', updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(v_task, p_actor, 'started', '{}'::jsonb);

    when 'block' then
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: not authorized to block'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      v_reason := nullif(btrim(coalesce(v_payload ->> 'reason', '')), '');
      if v_reason is null then
        raise exception 'smart_tasks: blocking requires a reason'
          using errcode = '22023', hint = 'reason_required';
      end if;
      update public.smart_tasks
         set status = 'blocked', blocked_reason = v_reason, updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(
        v_task, p_actor, 'blocked', jsonb_build_object('reason', v_reason)
      );

    when 'unblock' then
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: not authorized to unblock'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set status = case when started_at is not null then 'in_progress' else 'pending' end,
             updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(v_task, p_actor, 'unblocked', '{}'::jsonb);

    when 'complete' then
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: not authorized to complete'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set status = 'completed', updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(v_task, p_actor, 'completed', '{}'::jsonb);

    when 'reopen' then
      if not (v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the creator or a manager reopens'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set status = 'pending', updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(v_task, p_actor, 'reopened', '{}'::jsonb);

    when 'cancel' then
      if not (v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only creator or a manager cancels'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set status = 'cancelled', updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(v_task, p_actor, 'cancelled', '{}'::jsonb);

    when 'update_details' then
      if not (v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the creator or a manager edits details'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set title = coalesce(nullif(btrim(v_payload ->> 'title'), ''), title),
             description = case
               when v_payload ? 'description'
                 then nullif(btrim(coalesce(v_payload ->> 'description', '')), '')
               else description
             end,
             priority = coalesce(nullif(v_payload ->> 'priority', ''), priority),
             due_date = case
               when v_payload ? 'due_date'
                 then nullif(v_payload ->> 'due_date', '')::timestamptz
               else due_date
             end,
             linked_customer_id = case
               when v_payload ? 'linked_customer_id'
                 then nullif(v_payload ->> 'linked_customer_id', '')::uuid
               else linked_customer_id
             end,
             linked_supplier_id = case
               when v_payload ? 'linked_supplier_id'
                 then nullif(v_payload ->> 'linked_supplier_id', '')::uuid
               else linked_supplier_id
             end,
             linked_purchase_invoice_id = case
               when v_payload ? 'linked_purchase_invoice_id'
                 then nullif(v_payload ->> 'linked_purchase_invoice_id', '')::uuid
               else linked_purchase_invoice_id
             end,
             linked_sales_invoice_id = case
               when v_payload ? 'linked_sales_invoice_id'
                 then nullif(v_payload ->> 'linked_sales_invoice_id', '')::uuid
               else linked_sales_invoice_id
             end,
             updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(
        v_task, p_actor, 'details_updated',
        jsonb_build_object('fields', (
          select coalesce(jsonb_agg(key), '[]'::jsonb)
          from jsonb_object_keys(v_payload) as key
        ))
      );

    when 'set_visibility' then
      if not (v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only creator or a manager changes visibility'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      update public.smart_tasks
         set visibility = v_payload ->> 'visibility', updated_at = now()
       where id = v_task.id
       returning * into v_task;
      perform public.smart_task_append_event(
        v_task, p_actor, 'visibility_changed',
        jsonb_build_object('visibility', v_task.visibility)
      );

    when 'set_job_items' then
      if not (v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the creator or a manager relinks job items'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      v_job_id := nullif(v_payload ->> 'job_id', '')::uuid;
      if v_job_id is not null
        and v_item_ids is not null
        and array_length(v_item_ids, 1) > 0
        and coalesce(v_payload ->> 'overlap_decision', '') not in ('collaborate', 'transfer') then
        v_overlaps := public.smart_task_active_overlaps(p_tenant_id, v_item_ids, v_task.id);
        if v_overlaps <> '[]'::jsonb then
          raise exception 'smart_tasks: job items already covered by an active task'
            using errcode = '23505', hint = 'job_items_overlap',
              detail = v_overlaps::text;
        end if;
      end if;
      if coalesce(v_payload ->> 'overlap_decision', '') = 'transfer'
        and v_item_ids is not null then
        perform public.smart_task_transfer_overlaps(
          p_actor, p_tenant_id, v_task.id, v_item_ids
        );
      end if;
      v_task := public.smart_task_set_job_items_internal(
        v_task, p_actor, v_job_id, v_item_ids
      );
      if v_task.assigned_to is not null
        and v_task.linked_job_id is not null
        and not public.smart_task_assignee_worker_linked_v1(p_tenant_id, v_task.assigned_to) then
        raise exception 'smart_tasks: workshop tasks require an assignee linked to a worker'
          using errcode = '23514', hint = 'assignee_not_worker_linked';
      end if;

    else
      raise exception 'smart_tasks: unknown command %', p_command
        using errcode = '22023', hint = 'unknown_command';
  end case;

  perform set_config('vinabike.smart_task_cmd', '', true);
  return public.smart_task_row_to_json(v_task);
end;
$$;

revoke all on function public.smart_task_apply_command(uuid, uuid, boolean, text[], uuid, integer, text, jsonb)
  from public, anon, authenticated, service_role;

-- ============================================================================
-- 11. RPCs de cliente ERP
-- ============================================================================

create or replace function public.smart_task_create_v1(
  p_payload jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_fingerprint text;
  v_replay jsonb;
  v_title text;
  v_job_id uuid;
  v_item_ids uuid[];
  v_overlaps jsonb;
  v_task public.smart_tasks%rowtype;
  v_result jsonb;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'smart_tasks: active tenant membership required'
      using errcode = '42501';
  end if;

  v_fingerprint := md5(v_payload::text);
  select o_replay into v_replay from public.smart_task_claim_receipt(
    v_tenant, v_actor, 'task_create', p_idempotency_key, v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  perform set_config('vinabike.smart_task_cmd', 'create', true);

  v_title := nullif(btrim(coalesce(v_payload ->> 'title', '')), '');
  if v_title is null then
    raise exception 'smart_tasks: title is required'
      using errcode = '22023', hint = 'title_required';
  end if;

  v_job_id := nullif(v_payload ->> 'linked_job_id', '')::uuid;
  v_item_ids := case
    when v_payload ? 'job_item_ids' then (
      select array_agg(value::uuid)
      from jsonb_array_elements_text(v_payload -> 'job_item_ids')
    )
    else null
  end;
  perform public.smart_task_lock_job_items(v_tenant, v_item_ids);

  if v_job_id is not null
    and v_item_ids is not null
    and array_length(v_item_ids, 1) > 0
    and coalesce(v_payload ->> 'overlap_decision', '') not in ('collaborate', 'transfer') then
    v_overlaps := public.smart_task_active_overlaps(v_tenant, v_item_ids, null);
    if v_overlaps <> '[]'::jsonb then
      raise exception 'smart_tasks: job items already covered by an active task'
        using errcode = '23505', hint = 'job_items_overlap',
          detail = v_overlaps::text;
    end if;
  end if;

  insert into public.smart_tasks (
    tenant_id, title, description, task_kind, visibility, status, priority,
    due_date, assigned_to, created_by,
    linked_customer_id, linked_supplier_id,
    linked_purchase_invoice_id, linked_sales_invoice_id
  ) values (
    v_tenant,
    v_title,
    nullif(btrim(coalesce(v_payload ->> 'description', '')), ''),
    coalesce(nullif(v_payload ->> 'task_kind', ''), 'task'),
    coalesce(nullif(v_payload ->> 'visibility', ''), 'team'),
    'pending',
    coalesce(nullif(v_payload ->> 'priority', ''), 'normal'),
    nullif(v_payload ->> 'due_date', '')::timestamptz,
    nullif(v_payload ->> 'assigned_to', '')::uuid,
    v_actor,
    nullif(v_payload ->> 'linked_customer_id', '')::uuid,
    nullif(v_payload ->> 'linked_supplier_id', '')::uuid,
    nullif(v_payload ->> 'linked_purchase_invoice_id', '')::uuid,
    nullif(v_payload ->> 'linked_sales_invoice_id', '')::uuid
  )
  returning * into v_task;

  perform public.smart_task_append_event(
    v_task, v_actor, 'created',
    jsonb_strip_nulls(jsonb_build_object(
      'title', v_task.title,
      'visibility', v_task.visibility,
      'task_kind', v_task.task_kind
    ))
  );
  if v_task.assigned_to is not null then
    perform public.smart_task_append_event(
      v_task, v_actor, 'assigned',
      jsonb_build_object('assigned_to', v_task.assigned_to)
    );
  end if;

  if v_job_id is not null then
    if coalesce(v_payload ->> 'overlap_decision', '') = 'transfer'
      and v_item_ids is not null then
      perform public.smart_task_transfer_overlaps(
        v_actor, v_tenant, v_task.id, v_item_ids
      );
    end if;
    v_task := public.smart_task_set_job_items_internal(
      v_task, v_actor, v_job_id, v_item_ids
    );
  end if;

  perform set_config('vinabike.smart_task_cmd', '', true);

  v_result := jsonb_build_object('task', public.smart_task_row_to_json(v_task));
  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'task_create', p_idempotency_key, v_fingerprint,
    v_task.id, v_result
  );
  return v_result;
end;
$$;

create or replace function public.smart_task_command_v1(
  p_task_id uuid,
  p_expected_version integer,
  p_command text,
  p_payload jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'smart_tasks: active tenant membership required'
      using errcode = '42501';
  end if;

  v_fingerprint := md5(concat_ws('|',
    p_task_id::text, coalesce(p_expected_version::text, ''), p_command,
    coalesce(p_payload::text, '{}')
  ));
  select o_replay into v_replay from public.smart_task_claim_receipt(
    v_tenant, v_actor, 'task_command', p_idempotency_key, v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  v_result := jsonb_build_object('task', public.smart_task_apply_command(
    v_actor,
    v_tenant,
    public.can_manage_tenant_users(v_tenant),
    array[
      'assign', 'acknowledge', 'return', 'start', 'block', 'unblock',
      'complete', 'reopen', 'cancel', 'update_details', 'set_visibility',
      'set_job_items'
    ],
    p_task_id,
    p_expected_version,
    p_command,
    p_payload
  ));

  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'task_command', p_idempotency_key, v_fingerprint,
    p_task_id, v_result
  );
  return v_result;
end;
$$;

-- Directorio de asignación: reutiliza el directorio canónico de principals
-- ERP y lo extiende con los trabajadores de portal y con los empleados sin
-- cuenta (access = 'none') para el CTA «Invitar». UN principal canónico por
-- persona: precedencia explícita erp > portal > none, deduplicado por
-- empleado (o por usuario cuando no hay empleado).
create or replace function public.get_smart_task_assignment_directory_v1()
returns table (
  tenant_id uuid,
  user_id uuid,
  employee_id uuid,
  display_name text,
  role text,
  photo_url text,
  access text
)
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'pg_temp'
as $$
declare
  v_tenant uuid := public.user_tenant_id();
begin
  if v_tenant is null then
    raise exception 'smart_tasks: active tenant membership required'
      using errcode = '42501';
  end if;

  return query
  with raw as (
    select
      directory.tenant_id as r_tenant_id,
      directory.user_id as r_user_id,
      directory.employee_id as r_employee_id,
      directory.display_name as r_display_name,
      directory.role as r_role,
      directory.photo_url as r_photo_url,
      'erp'::text as r_access,
      1 as r_precedence
    from public.get_erp_chat_principal_directory() directory

    union all

    select
      portal.tenant_id,
      portal.auth_user_id,
      employee.id,
      coalesce(
        nullif(btrim(employee.first_name || ' ' || employee.last_name), ''),
        portal.username,
        'Trabajador'
      ),
      coalesce(nullif(btrim(employee.system_role), ''), 'worker'),
      employee.photo_url,
      'portal'::text,
      2
    from public.employee_portal_accounts portal
    join public.employees employee
      on employee.id = portal.employee_id
     and employee.tenant_id = portal.tenant_id
     and employee.status = 'active'
    where portal.tenant_id = v_tenant
      and portal.is_active is true

    union all

    -- Empleados activos sin principal utilizable: visibles para invitar.
    select
      employee.tenant_id,
      null::uuid,
      employee.id,
      coalesce(
        nullif(btrim(employee.first_name || ' ' || employee.last_name), ''),
        'Empleado'
      ),
      coalesce(nullif(btrim(employee.system_role), ''), 'worker'),
      employee.photo_url,
      'none'::text,
      3
    from public.employees employee
    where employee.tenant_id = v_tenant
      and employee.status = 'active'
      and not exists (
        select 1 from public.employee_portal_accounts portal
        where portal.employee_id = employee.id
          and portal.tenant_id = employee.tenant_id
          and portal.is_active is true
      )
      and not exists (
        select 1 from public.user_profiles profile
        where profile.tenant_id = employee.tenant_id
          and profile.is_active is true
          and (
            profile.employee_id = employee.id
            or (employee.user_id is not null and profile.user_id = employee.user_id)
          )
      )
  )
  select distinct on (coalesce(deduped.r_employee_id::text, deduped.r_user_id::text))
    deduped.r_tenant_id,
    deduped.r_user_id,
    deduped.r_employee_id,
    deduped.r_display_name,
    deduped.r_role,
    deduped.r_photo_url,
    deduped.r_access
  from raw deduped
  order by
    coalesce(deduped.r_employee_id::text, deduped.r_user_id::text),
    deduped.r_precedence;
end;
$$;

-- El hilo canónico de una tarea, si existe.
create or replace function public.smart_task_thread_v1(p_task_id uuid)
returns uuid
language sql
stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select context.conversation_id
  from public.conversation_contexts context
  where context.context_type = 'task'
    and context.context_id = p_task_id
    and public.smart_task_can_view_v1(p_task_id)
  limit 1;
$$;

-- Get-or-create server-owned del hilo. El servidor crea la conversación
-- interna con participantes EXACTOS (creador + asignado ERP + solicitante),
-- la vincula bajo el índice único parcial, y una carrera devuelve siempre
-- el hilo ganador. Un asignado de portal no es principal de mensajería:
-- no se le agrega ni se le finge hilo (el contrato del portal no expone
-- conversación).
create or replace function public.smart_task_thread_get_or_create_v1(
  p_task_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_task public.smart_tasks%rowtype;
  v_is_manager boolean;
  v_existing uuid;
  v_conversation uuid;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'smart_tasks: active tenant membership required'
      using errcode = '42501';
  end if;

  select * into v_task
  from public.smart_tasks
  where id = p_task_id and tenant_id = v_tenant
  for update;
  if not found then
    raise exception 'smart_tasks: task not found'
      using errcode = '23503', hint = 'task_not_found';
  end if;

  v_is_manager := public.can_manage_tenant_users(v_tenant);
  if not (v_task.created_by = v_actor
          or v_task.assigned_to = v_actor
          or v_is_manager) then
    raise exception 'smart_tasks: only creator, assignee or a manager opens the thread'
      using errcode = '42501', hint = 'not_authorized';
  end if;

  select context.conversation_id into v_existing
  from public.conversation_contexts context
  where context.context_type = 'task' and context.context_id = p_task_id
  limit 1;
  if v_existing is not null then
    -- Quien abre con autoridad (creador/asignado/manager) entra al hilo
    -- existente; sin esto, un supervisor autorizado quedaba mirando desde
    -- afuera.
    insert into public.conversation_participants (conversation_id, user_id, tenant_id)
    select v_existing, v_actor, v_tenant
    where exists (
        select 1 from public.user_profiles profile
        where profile.user_id = v_actor
          and profile.tenant_id = v_tenant
          and profile.is_active is true
      )
      and not exists (
        select 1 from public.conversation_participants participant
        where participant.conversation_id = v_existing
          and participant.user_id = v_actor
      );
    return jsonb_build_object('conversation_id', v_existing, 'created', false);
  end if;

  v_conversation := gen_random_uuid();
  insert into public.conversations (
    id, tenant_id, type, channel, counterparty_type, is_group, status,
    title, created_by, created_at, updated_at
  ) values (
    v_conversation, v_tenant, 'internal', 'internal', 'internal', true,
    'active', left(v_task.title, 120), v_actor, now(), now()
  );

  insert into public.conversation_participants (conversation_id, user_id, tenant_id)
  select v_conversation, member.user_id, v_tenant
  from (
    select distinct candidate.user_id
    from (values (v_task.created_by), (v_task.assigned_to), (v_actor))
      as candidate(user_id)
    where candidate.user_id is not null
  ) member
  where exists (
    select 1 from public.user_profiles profile
    where profile.user_id = member.user_id
      and profile.tenant_id = v_tenant
      and profile.is_active is true
  );

  begin
    insert into public.conversation_contexts (
      conversation_id, context_type, context_id, is_primary, added_by, tenant_id
    ) values (
      v_conversation, 'task', p_task_id, true, v_actor, v_tenant
    );
  exception when unique_violation then
    -- Otra sesión ganó la carrera: el hilo canónico es el suyo.
    select context.conversation_id into v_existing
    from public.conversation_contexts context
    where context.context_type = 'task' and context.context_id = p_task_id
    limit 1;
    delete from public.conversation_participants
      where conversation_id = v_conversation;
    delete from public.conversations where id = v_conversation;
    -- El perdedor autorizado también debe quedar dentro del hilo ganador.
    -- Sin esto, dos managers abriendo a la vez podían recibir el mismo UUID
    -- pero uno quedaba sin permiso para leer la conversación.
    insert into public.conversation_participants (
      conversation_id, user_id, tenant_id
    )
    select v_existing, v_actor, v_tenant
    where exists (
        select 1 from public.user_profiles profile
        where profile.user_id = v_actor
          and profile.tenant_id = v_tenant
          and profile.is_active is true
      )
      and not exists (
        select 1 from public.conversation_participants participant
        where participant.conversation_id = v_existing
          and participant.user_id = v_actor
      );
    return jsonb_build_object('conversation_id', v_existing, 'created', false);
  end;

  update public.smart_tasks set updated_at = now()
   where id = p_task_id
   returning * into v_task;
  perform public.smart_task_append_event(
    v_task, v_actor, 'conversation_linked',
    jsonb_build_object('conversation_id', v_conversation)
  );

  return jsonb_build_object('conversation_id', v_conversation, 'created', true);
end;
$$;

grant execute on function public.smart_task_create_v1(jsonb, text) to authenticated;
grant execute on function public.smart_task_command_v1(uuid, integer, text, jsonb, text) to authenticated;
grant execute on function public.get_smart_task_assignment_directory_v1() to authenticated;
grant execute on function public.smart_task_thread_v1(uuid) to authenticated;
grant execute on function public.smart_task_thread_get_or_create_v1(uuid) to authenticated;
revoke execute on function public.smart_task_create_v1(jsonb, text) from anon, public;
revoke execute on function public.smart_task_command_v1(uuid, integer, text, jsonb, text) from anon, public;
revoke execute on function public.get_smart_task_assignment_directory_v1() from anon, public;
revoke execute on function public.smart_task_thread_v1(uuid) from anon, public;
revoke execute on function public.smart_task_thread_get_or_create_v1(uuid) from anon, public;

-- ============================================================================
-- 12. Portal del trabajador: proyección mínima y comandos acotados
--     Sin hilo: el principal de portal no es principal de mensajería y no se
--     le muestra un hilo falso. Sin precios ni columnas comerciales.
-- ============================================================================

drop function if exists public.get_my_worker_tasks_v1();
create or replace function public.get_my_worker_tasks_v1()
returns table (
  id uuid,
  title text,
  description text,
  status text,
  priority text,
  due_date timestamptz,
  version integer,
  acknowledged_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  blocked_reason text,
  created_at timestamptz,
  creator_name text,
  -- Quién LE ASIGNÓ la tarea (assigned_by). Null en asignaciones legacy
  -- anteriores al kernel: el cliente usa creator_name solo como fallback
  -- explícito. Sin PII nueva: mismo resolutor de nombre que creator_name.
  assigner_name text,
  job_id uuid,
  job_number text,
  bike_labels jsonb,
  job_items jsonb
)
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_tenant uuid := public.worker_portal_tenant_id();
begin
  if auth.uid() is null or v_tenant is null then
    raise exception 'Worker portal account not found';
  end if;

  return query
  select
    task.id,
    task.title,
    task.description,
    task.status,
    task.priority,
    task.due_date,
    task.version,
    task.acknowledged_at,
    task.started_at,
    task.completed_at,
    task.blocked_reason,
    task.created_at,
    public.erp_actor_display_name(task.created_by, task.tenant_id),
    public.erp_actor_display_name(task.assigned_by, task.tenant_id),
    task.linked_job_id,
    job.job_number,
    -- La bicicleta viene de cada servicio vinculado; una pega multi-bici
    -- entrega todas sus etiquetas, sin inventar un único valor.
    coalesce((
      select jsonb_agg(distinct link.bike_label)
      from public.smart_task_job_items link
      where link.task_id = task.id and link.bike_label is not null
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'item_name', link.item_name,
        'item_type', link.item_type,
        'bike_label', link.bike_label,
        'invalidated', case when link.invalidated_at is not null then true end,
        'context_changed', case when link.context_changed_at is not null then true end
      )) order by link.linked_at)
      from public.smart_task_job_items link
      where link.task_id = task.id
    ), '[]'::jsonb)
  from public.smart_tasks task
  left join public.mechanic_jobs job on job.id = task.linked_job_id
  where task.tenant_id = v_tenant
    and task.assigned_to = auth.uid()
    and task.task_kind = 'task'
  order by
    case task.status
      when 'blocked' then 0
      when 'pending' then 1
      when 'in_progress' then 2
      else 3
    end,
    task.due_date nulls last,
    task.created_at desc;
end;
$$;

create or replace function public.worker_task_command_v1(
  p_task_id uuid,
  p_expected_version integer,
  p_command text,
  p_payload jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.worker_portal_tenant_id();
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'Worker portal account not found';
  end if;

  v_fingerprint := md5(concat_ws('|',
    p_task_id::text, coalesce(p_expected_version::text, ''), p_command,
    coalesce(p_payload::text, '{}')
  ));
  select o_replay into v_replay from public.smart_task_claim_receipt(
    v_tenant, v_actor, 'worker_task_command', p_idempotency_key, v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  v_result := jsonb_build_object('task', public.smart_task_apply_command(
    v_actor,
    v_tenant,
    false,
    array['acknowledge', 'return', 'start', 'block', 'unblock', 'complete'],
    p_task_id,
    p_expected_version,
    p_command,
    p_payload
  ));

  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'worker_task_command', p_idempotency_key, v_fingerprint,
    p_task_id, v_result
  );
  return v_result;
end;
$$;

grant execute on function public.get_my_worker_tasks_v1() to authenticated;
grant execute on function public.worker_task_command_v1(uuid, integer, text, jsonb, text) to authenticated;
revoke execute on function public.get_my_worker_tasks_v1() from anon, public;
revoke execute on function public.worker_task_command_v1(uuid, integer, text, jsonb, text) from anon, public;

-- ============================================================================
-- 13. El hilo de tarea existe para mensajería: contexto 'task'
-- ============================================================================

alter table public.conversation_contexts
  drop constraint if exists conversation_contexts_context_type_check;
alter table public.conversation_contexts
  add constraint conversation_contexts_context_type_check
  check (context_type = any (array[
    'job'::text, 'invoice'::text, 'bike'::text, 'product'::text,
    'order'::text, 'customer'::text, 'supplier'::text,
    'purchase_invoice'::text, 'task'::text
  ]));

-- Un hilo canónico por tarea, garantizado por la base, no por convención.
create unique index if not exists uq_conversation_contexts_task_thread
  on public.conversation_contexts (context_id)
  where context_type = 'task';

create index if not exists idx_conversation_contexts_task
  on public.conversation_contexts (context_type, context_id);

-- Extiende la validación de pertenencia con la rama 'task'; el resto del
-- cuerpo es copia literal de la definición de producción (leída 2026-08-26).
create or replace function public.messaging_context_belongs_to_tenant(
  p_context_type text, p_context_id uuid, p_tenant_id uuid
)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select case lower(coalesce(p_context_type, ''))
    when 'job' then exists (
      select 1 from public.mechanic_jobs row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'invoice' then exists (
      select 1 from public.sales_invoices row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'bike' then exists (
      select 1 from public.bikes row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'product' then exists (
      select 1 from public.products row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'order' then exists (
      select 1 from public.online_orders row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'customer' then exists (
      select 1 from public.customers row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'supplier' then exists (
      select 1 from public.suppliers row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'purchase_invoice' then exists (
      select 1 from public.purchase_invoices row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'task' then exists (
      select 1 from public.smart_tasks row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    else false
  end;
$$;

-- ============================================================================
-- 14. Notificaciones dirigidas
-- ============================================================================

alter table public.erp_notifications
  add column if not exists recipient_user_id uuid references auth.users(id) on delete cascade;

create index if not exists idx_erp_notifications_recipient_unread
  on public.erp_notifications (tenant_id, recipient_user_id)
  where read_at is null;

drop policy if exists erp_notifications_select on public.erp_notifications;
drop policy if exists erp_notifications_update on public.erp_notifications;

create policy erp_notifications_select on public.erp_notifications
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and (recipient_user_id is null or recipient_user_id = auth.uid())
  );

create policy erp_notifications_update on public.erp_notifications
  for update to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and (recipient_user_id is null or recipient_user_id = auth.uid())
  );

-- El cliente sólo marca como leída. La fila dirigida, su destinatario y su
-- contenido son verdad del productor server-side; una actualización directa
-- no puede secuestrar un broadcast ni redirigir el aviso de otra persona.
revoke update on public.erp_notifications from authenticated;
grant update (read_at) on public.erp_notifications to authenticated;

-- El destinatario es la CONTRAPARTE del actor, no siempre el creador:
--   assigned .... nuevo responsable (y aviso al anterior si lo había)
--   returned .... creador
--   blocked ..... si bloquea el asignado → creador; si bloquea
--                 creador/manager → asignado
--   completed ... la contraparte (creador o asignado, según quién actuó)
--   unassigned .. responsable anterior
create or replace function public.create_smart_task_erp_notification()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_task public.smart_tasks%rowtype;
  v_actor_name text;
  v_recipients jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_recipient uuid;
begin
  if new.event_type not in ('assigned', 'unassigned', 'returned', 'blocked', 'completed') then
    return new;
  end if;

  select * into v_task from public.smart_tasks where id = new.task_id;
  if not found or v_task.task_kind <> 'task' then
    return new;
  end if;

  v_actor_name := public.erp_actor_display_name(new.actor_user_id, new.tenant_id);

  case new.event_type
    when 'assigned' then
      v_recipients := jsonb_build_array(
        jsonb_build_object(
          'recipient', new.payload ->> 'assigned_to',
          'type', 'smart_task_assigned',
          'title', 'Tarea asignada',
          'body', coalesce(v_actor_name, 'Alguien') || ' te asignó: ' || v_task.title,
          'severity', 'info'
        ),
        jsonb_build_object(
          'recipient', new.payload ->> 'previous_assignee',
          'type', 'smart_task_reassigned',
          'title', 'Tarea reasignada',
          'body', v_task.title || ' ahora tiene otro responsable',
          'severity', 'info'
        )
      );
    when 'unassigned' then
      v_recipients := jsonb_build_array(jsonb_build_object(
        'recipient', new.payload ->> 'previous_assignee',
        'type', 'smart_task_unassigned',
        'title', 'Tarea sin responsable',
        'body', v_task.title || ' quedó sin responsable',
        'severity', 'info'
      ));
    when 'returned' then
      v_recipients := jsonb_build_array(jsonb_build_object(
        'recipient', v_task.created_by::text,
        'type', 'smart_task_returned',
        'title', 'Tarea devuelta',
        'body', coalesce(v_actor_name, 'El asignado') || ' devolvió: ' || v_task.title
          || coalesce(' — ' || (new.payload ->> 'reason'), ''),
        'severity', 'warning'
      ));
    when 'blocked' then
      v_recipient := case
        when new.actor_user_id = v_task.assigned_to then v_task.created_by
        else coalesce(v_task.assigned_to, v_task.created_by)
      end;
      v_recipients := jsonb_build_array(jsonb_build_object(
        'recipient', v_recipient::text,
        'type', 'smart_task_blocked',
        'title', 'Tarea bloqueada',
        'body', v_task.title || coalesce(' — ' || (new.payload ->> 'reason'), ''),
        'severity', 'warning'
      ));
    when 'completed' then
      v_recipient := case
        when new.actor_user_id = v_task.created_by
          then v_task.assigned_to
        else v_task.created_by
      end;
      v_recipients := jsonb_build_array(jsonb_build_object(
        'recipient', v_recipient::text,
        'type', 'smart_task_completed',
        'title', 'Tarea completada',
        'body', coalesce(v_actor_name, 'Alguien') || ' completó: ' || v_task.title,
        'severity', 'success'
      ));
  end case;

  for v_entry in select * from jsonb_array_elements(v_recipients) loop
    v_recipient := nullif(coalesce(v_entry ->> 'recipient', ''), '')::uuid;
    if v_recipient is null or v_recipient = new.actor_user_id then
      continue;
    end if;
    -- erp_notifications es único por (tenant, type, entity): la notificación
    -- viva de cada tipo se RE-DIRIGE al destinatario vigente y vuelve a
    -- no-leída, en vez de acumular una fila por ocurrencia.
    insert into public.erp_notifications (
      tenant_id, type, title, body, route, entity_type, entity_id,
      severity, data, recipient_user_id, occurred_at
    ) values (
      new.tenant_id,
      v_entry ->> 'type',
      v_entry ->> 'title',
      v_entry ->> 'body',
      null,
      'smart_task',
      v_task.id,
      v_entry ->> 'severity',
      jsonb_strip_nulls(jsonb_build_object(
        'task_id', v_task.id,
        'task_title', v_task.title,
        'event_type', new.event_type,
        'actor_name', v_actor_name,
        'job_id', v_task.linked_job_id
      )),
      v_recipient,
      new.created_at
    )
    on conflict (tenant_id, type, entity_type, entity_id) do update set
      title = excluded.title,
      body = excluded.body,
      severity = excluded.severity,
      data = excluded.data,
      recipient_user_id = excluded.recipient_user_id,
      occurred_at = excluded.occurred_at,
      read_at = null,
      updated_at = now();
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_smart_task_erp_notification on public.smart_task_events;
create trigger trg_smart_task_erp_notification
  after insert on public.smart_task_events
  for each row execute function public.create_smart_task_erp_notification();

revoke all on function public.create_smart_task_erp_notification()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_tasks_guard_work_tray()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_tasks_audit_direct_write()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_tasks_audit_direct_insert()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_job_items_guard()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_job_items_mark_invalidated()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_job_items_mark_context_changed()
  from public, anon, authenticated, service_role;
revoke all on function public.smart_task_user_state_guard()
  from public, anon, authenticated, service_role;

-- ============================================================================
-- 15. Realtime: la bandeja ya estaba publicada; se suman los eventos y el
-- estado por usuario, y se corrige el checklist técnico que estaba fuera de
-- la publicación (su suscripción en la app jamás disparó).
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'mechanic_job_tasks'
  ) then
    alter publication supabase_realtime add table public.mechanic_job_tasks;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'smart_task_events'
  ) then
    alter publication supabase_realtime add table public.smart_task_events;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'smart_task_user_state'
  ) then
    alter publication supabase_realtime add table public.smart_task_user_state;
  end if;
end
$$;
