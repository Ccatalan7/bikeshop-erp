-- Tareas del taller: notas por servicio, con historia (dueño, 2026-09-27).
--
-- Al encargar un trabajo con `/tarea` la nota era una sola para toda la
-- tarea, pero la indicación suele ser de un servicio puntual («la cadena ya
-- viene cambiada»). El dueño pidió además que esas notas tengan su línea de
-- tiempo: se muestra siempre la vigente, y se puede ver quién escribió qué y
-- cuándo. Y dos modos: corregir la propia nota («uno se puede equivocar») o
-- continuarla con una nueva.
--
-- Modelo:
--   * Cada nota es una fila (`smart_task_job_item_notes`) sobre la identidad
--     del servicio dentro de la tarea (task_id, job_item_id), no sobre el
--     vínculo: re-vincular borra y vuelve a crear los vínculos, y las notas no
--     se pierden por eso. La vigente es la última no retirada.
--   * No es `item_instructions`: ésa es la copia inmutable de las notas de la
--     línea del trabajo, y la tarea no reescribe el trabajo.
--   * Comandos, en `smart_task_command_v1` (ERP) y `worker_task_command_v1`
--     (portal):
--       - `add_job_item_note` {job_item_id, note}: la primera o «continuar».
--         La escriben el responsable, quien encargó o un manager.
--       - `edit_job_item_note` {note_id, note}: corregir. Sólo quien la
--         escribió, y lo que decía queda en el ledger.
--       - `withdraw_job_item_note` {note_id}: retirar la propia; queda en la
--         historia como retirada.
--     Todos sólo en una tarea abierta.
--   * `smart_task_create_v1` acepta `job_item_notes` {job_item_id: nota}: la
--     primera nota de cada servicio nace con el encargo.
--   * La línea de tiempo de un servicio (`get_smart_task_service_timeline_v1`)
--     sale del ledger: encargo, cada nota escrita, continuada, corregida (con
--     el texto anterior) o retirada, hecho / pendiente, y lo que el taller
--     cambió o sacó; con nombre, hora del servidor y si fue desde el portal.
--   * Una nota nueva avisa a quien no la escribió (las del encargo no: ya
--     llega el aviso de la asignación); corregirla actualiza el aviso sin
--     volver a encenderlo, y retirarla lo retira.
--   * Orden de bloqueo: agregar toma el servicio antes que la tarea, como
--     marcar; corregir y retirar toman la tarea y después la nota.
--   * Revisión de Codex (2026-09-27), antes de desplegar:
--       - Notas e historial exigen, además de ver la tarea, una cuenta viva
--         del taller (ERP o portal): `smart_task_can_view_v1` deja leer a un
--         `assigned_to` aunque su cuenta de portal se haya desactivado, y en
--         una tarea cerrada ese `assigned_to` no se limpia. El predicado
--         compartido queda aparte; aquí se cierra para lo nuevo.
--       - Cada nota tiene su propio aviso (entidad `smart_task_service_note`,
--         id de la nota): uno por tarea hacía que una nota nueva pisara el
--         aviso sin leer de otra.
--       - Desvincular o re-vincular deja en el ledger lo que el taller cambió o sacó
--         (`job_item_context_changed` / `job_item_invalidated`, con la hora de
--         la marca): el vínculo nuevo nace sin marcas y la historia las
--         perdía. Se registra al re-vincular, no cuando el taller edita la
--         línea: escribir en el ledger desde ese trigger tomaría la tarea
--         después del servicio en el orden contrario al de marcar.

create table if not exists public.smart_task_job_item_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  task_id uuid not null references public.smart_tasks(id) on delete cascade,
  -- Identidad del servicio en la tarea. Sin FK a la línea: si el taller la
  -- borra, la nota queda como evidencia, igual que el vínculo.
  job_item_id uuid not null,
  body text not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  edited_at timestamptz,
  edited_by uuid references auth.users(id) on delete set null,
  withdrawn_at timestamptz,
  withdrawn_by uuid references auth.users(id) on delete set null,
  constraint smart_task_job_item_notes_body_check
    check (length(btrim(body)) between 1 and 2000),
  constraint smart_task_job_item_notes_edited_by_needs_edited_at
    check (edited_by is null or edited_at is not null),
  constraint smart_task_job_item_notes_withdrawn_by_needs_withdrawn_at
    check (withdrawn_by is null or withdrawn_at is not null)
);

create index if not exists idx_smart_task_job_item_notes_thread
  on public.smart_task_job_item_notes (task_id, job_item_id, created_at);
create index if not exists idx_smart_task_job_item_notes_tenant_fk
  on public.smart_task_job_item_notes (tenant_id);
create index if not exists idx_smart_task_job_item_notes_created_by_fk
  on public.smart_task_job_item_notes (created_by);
create index if not exists idx_smart_task_job_item_notes_edited_by_fk
  on public.smart_task_job_item_notes (edited_by);
create index if not exists idx_smart_task_job_item_notes_withdrawn_by_fk
  on public.smart_task_job_item_notes (withdrawn_by);

alter table public.smart_task_job_item_notes enable row level security;

-- Lee notas e historial quien ve la tarea Y tiene una cuenta viva del taller
-- (ERP o portal).
create or replace function public.smart_task_service_notes_readable_v1(p_task_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select public.smart_task_can_view_v1(p_task_id)
    and exists (
      select 1
        from public.smart_tasks task
       where task.id = p_task_id
         and (
           task.tenant_id = public.user_tenant_id()
           or task.tenant_id = public.worker_portal_tenant_id()
         )
    );
$function$;

revoke all on function public.smart_task_service_notes_readable_v1(uuid) from public, anon;
grant execute on function public.smart_task_service_notes_readable_v1(uuid) to authenticated, service_role;

drop policy if exists smart_task_job_item_notes_select
  on public.smart_task_job_item_notes;
create policy smart_task_job_item_notes_select
  on public.smart_task_job_item_notes
  for select to authenticated
  using (public.smart_task_service_notes_readable_v1(task_id));

-- Se escribe sólo por comando.
revoke all on table public.smart_task_job_item_notes from public, anon, authenticated;
grant select on table public.smart_task_job_item_notes to authenticated;
grant all on table public.smart_task_job_item_notes to service_role;

alter table public.smart_task_events
  drop constraint if exists smart_task_events_event_type_check;
alter table public.smart_task_events
  add constraint smart_task_events_event_type_check
  check (event_type = any (array[
    'created', 'details_updated', 'assigned', 'unassigned', 'acknowledged',
    'returned', 'started', 'blocked', 'unblocked', 'completed', 'reopened',
    'cancelled', 'visibility_changed', 'job_items_linked', 'job_items_unlinked',
    'conversation_linked', 'due_soon', 'mentioned',
    'job_item_done', 'job_item_reopened', 'handoff_note_set', 'handoff_note_cleared',
    'job_item_note_added', 'job_item_note_edited', 'job_item_note_withdrawn',
    'job_item_context_changed', 'job_item_invalidated'
  ]));

-- ── Guard: una nota nace y cambia sólo por su comando ────────────────
create or replace function public.smart_task_job_item_notes_guard()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_task public.smart_tasks%rowtype;
  v_cmd text := coalesce(current_setting('vinabike.smart_task_cmd', true), '');
begin
  if tg_op = 'INSERT' then
    if v_cmd not in ('add_job_item_note', 'create') then
      raise exception 'smart_task_job_item_notes: notes are written through their command'
        using errcode = '42501';
    end if;
    select * into v_task from public.smart_tasks where id = new.task_id;
    if not found then
      raise exception 'smart_task_job_item_notes: task not found'
        using errcode = '23503';
    end if;
    if not exists (
      select 1 from public.smart_task_job_items link
       where link.task_id = new.task_id
         and link.job_item_id = new.job_item_id
         and link.tenant_id = v_task.tenant_id
    ) then
      raise exception 'smart_tasks: that service is not part of this task'
        using errcode = '23503', hint = 'job_item_not_linked';
    end if;
    new.tenant_id := v_task.tenant_id;
    new.body := btrim(new.body);
    -- La hora del reloj, no la de la transacción: dos notas del mismo hilo
    -- escritas en una transacción siguen teniendo un orden.
    new.created_at := clock_timestamp();
    new.edited_at := null;
    new.edited_by := null;
    new.withdrawn_at := null;
    new.withdrawn_by := null;
    return new;
  end if;

  if new.id is distinct from old.id
    or new.tenant_id is distinct from old.tenant_id
    or new.task_id is distinct from old.task_id
    or new.job_item_id is distinct from old.job_item_id
    or new.created_at is distinct from old.created_at then
    raise exception 'smart_task_job_item_notes: a note stays where it was written'
      using errcode = '23514';
  end if;

  -- Los autores sólo sueltan a una cuenta borrada (la FK `on delete set
  -- null`); reponerlos haría imposible borrar la cuenta.
  if new.created_by is distinct from old.created_by
    and not (new.created_by is null
      and not exists (select 1 from auth.users account where account.id = old.created_by)) then
    new.created_by := old.created_by;
  end if;

  if v_cmd not in ('edit_job_item_note', 'withdraw_job_item_note') then
    new.body := old.body;
    new.edited_at := old.edited_at;
    new.withdrawn_at := old.withdrawn_at;
    if not (new.edited_by is null
      and old.edited_by is not null
      and not exists (select 1 from auth.users account where account.id = old.edited_by)) then
      new.edited_by := old.edited_by;
    end if;
    if not (new.withdrawn_by is null
      and old.withdrawn_by is not null
      and not exists (select 1 from auth.users account where account.id = old.withdrawn_by)) then
      new.withdrawn_by := old.withdrawn_by;
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.smart_task_job_item_notes_guard() from public, anon, authenticated;

drop trigger if exists trg_smart_task_job_item_notes_guard
  on public.smart_task_job_item_notes;
create trigger trg_smart_task_job_item_notes_guard
  before insert or update on public.smart_task_job_item_notes
  for each row execute function public.smart_task_job_item_notes_guard();

-- ── Re-vincular deja en la historia lo que cambió el taller ─────────
CREATE OR REPLACE FUNCTION public.smart_task_set_job_items_internal(p_task smart_tasks, p_actor uuid, p_job_id uuid, p_job_item_ids uuid[])
 RETURNS smart_tasks
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_job public.mechanic_jobs%rowtype;
  v_requested int;
  v_eligible int;
  v_present int;
  v_task public.smart_tasks;
  v_done jsonb;
begin
  -- Lo que el taller cambió o sacó queda en la historia de cada servicio:
  -- desvincular o re-vincular borra los vínculos, y el nuevo nace sin esas
  -- marcas. Va antes de cualquier borrado, en los dos caminos.
  insert into public.smart_task_events (
    tenant_id, task_id, actor_user_id, event_type, task_version, payload
  )
  select p_task.tenant_id, p_task.id, null, marker.event_type, p_task.version,
         jsonb_build_object(
           'job_item_id', marker.job_item_id,
           'item_name', marker.item_name,
           'at', marker.at
         )
    from public.smart_task_job_items link
   cross join lateral (
     values
       ('job_item_context_changed', link.job_item_id, link.item_name,
        link.context_changed_at),
       ('job_item_invalidated', link.job_item_id, link.item_name,
        link.invalidated_at)
   ) as marker(event_type, job_item_id, item_name, at)
   where link.task_id = p_task.id
     and link.tenant_id = p_task.tenant_id
     and marker.at is not null;

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

  -- Lo ya hecho sobrevive a re-vincular: se guarda antes de borrar y se repone
  -- en los servicios que siguen. Uno que sale se lleva su marca.
  select coalesce(jsonb_object_agg(link.job_item_id::text, jsonb_build_object(
           'at', link.done_at, 'by', link.done_by)), '{}'::jsonb)
    into v_done
    from public.smart_task_job_items link
   where link.task_id = p_task.id
     and link.done_at is not null;

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

    update public.smart_task_job_items link
       set done_at = (v_done -> link.job_item_id::text ->> 'at')::timestamptz,
           done_by = (v_done -> link.job_item_id::text ->> 'by')::uuid
     where link.task_id = v_task.id
       and v_done ? link.job_item_id::text;
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
$function$;

-- ── Comandos: escribir, continuar, corregir y retirar ────────────────
CREATE OR REPLACE FUNCTION public.smart_task_apply_command(p_actor uuid, p_tenant_id uuid, p_is_manager boolean, p_allowed_commands text[], p_task_id uuid, p_expected_version integer, p_command text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_task public.smart_tasks%rowtype;
  v_is_creator boolean;
  v_is_assignee boolean;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_new_assignee uuid;
  v_new_employee uuid;
  v_previous_employee uuid;
  v_reason text;
  v_previous_assignee uuid;
  v_job_id uuid;
  v_item_ids uuid[];
  v_overlaps jsonb;
  v_item_id uuid;
  v_done boolean;
  v_link public.smart_task_job_items%rowtype;
  v_note text;
  v_note_id uuid;
  v_entry public.smart_task_job_item_notes%rowtype;
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

  -- Marcar un servicio (o escribirle una nota) toma su identidad antes que
  -- la tarea, igual que re-vincular: el traspaso borra vínculos y después
  -- toca la otra tarea, y en orden contrario las dos se esperarían.
  if p_command in ('set_job_item_done', 'add_job_item_note') then
    v_item_id := nullif(v_payload ->> 'job_item_id', '')::uuid;
    if v_item_id is null then
      raise exception 'smart_tasks: which service?'
        using errcode = '22023', hint = 'job_item_required';
    end if;
    perform public.smart_task_lock_job_items(p_tenant_id, array[v_item_id]);
  end if;

  -- Mismo orden global para asignar a un trabajador: su fila, después la de
  -- la tarea. La sincronización de cuentas toma el trabajador y luego sus
  -- tareas; al revés, las dos podían esperarse mutuamente.
  if p_command = 'assign'
    and nullif(v_payload ->> 'assigned_employee_id', '') is not null then
    perform 1 from public.employees employee
     where employee.id = (v_payload ->> 'assigned_employee_id')::uuid
       and employee.tenant_id = p_tenant_id
     for share;
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
    'assign', 'acknowledge', 'return', 'start', 'block', 'unblock', 'complete',
    'set_job_item_done', 'set_handoff_note',
    'add_job_item_note', 'edit_job_item_note', 'withdraw_job_item_note'
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
      -- Se asigna a un trabajador (tenga o no cuenta) o, para quien no es
      -- trabajador, a una cuenta. El guard deriva la otra mitad.
      v_new_employee := nullif(v_payload ->> 'assigned_employee_id', '')::uuid;
      v_new_assignee := nullif(v_payload ->> 'assigned_to', '')::uuid;
      v_previous_assignee := v_task.assigned_to;
      v_previous_employee := v_task.assigned_employee_id;
      if v_new_employee is not null then
        update public.smart_tasks
           set assigned_employee_id = v_new_employee, updated_at = now()
         where id = v_task.id
           and tenant_id = p_tenant_id
         returning * into v_task;
      else
        update public.smart_tasks
           set assigned_to = v_new_assignee,
               assigned_employee_id = case
                 when v_new_assignee is null then null
                 else assigned_employee_id
               end,
               updated_at = now()
         where id = v_task.id
           and tenant_id = p_tenant_id
         returning * into v_task;
      end if;
      perform public.smart_task_append_event(
        v_task, p_actor,
        case
          when v_task.assigned_to is null and v_task.assigned_employee_id is null
            then 'unassigned'
          else 'assigned'
        end,
        jsonb_strip_nulls(jsonb_build_object(
          'assigned_to', v_task.assigned_to,
          'assigned_employee_id', v_task.assigned_employee_id,
          'previous_assignee', v_previous_assignee,
          'previous_employee_id', v_previous_employee
        ))
      );
      perform public.smart_task_thread_sync_participants(
        v_task, v_task.assigned_to, v_previous_assignee);

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

    when 'set_job_item_done' then
      -- Quien hace el trabajo lo va marcando; quien lo encargó o un manager
      -- también, por si se lo cuentan en el mostrador.
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the assignee, the creator or a manager marks services'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      if v_task.status in ('completed', 'cancelled') then
        raise exception 'smart_tasks: a closed task keeps its services as they were'
          using errcode = '23514', hint = 'task_closed';
      end if;
      v_done := coalesce((v_payload ->> 'done')::boolean, true);
      select * into v_link
        from public.smart_task_job_items link
       where link.task_id = v_task.id
         and link.job_item_id = v_item_id
         and link.tenant_id = p_tenant_id
       for update;
      if not found then
        raise exception 'smart_tasks: that service is not part of this task'
          using errcode = '23503', hint = 'job_item_not_linked';
      end if;
      if v_done and v_link.invalidated_at is not null then
        raise exception 'smart_tasks: the workshop removed this service from the job'
          using errcode = '23514', hint = 'job_item_invalidated';
      end if;
      -- Ya está así (un doble toque, un reintento): nada que registrar.
      if v_done is distinct from (v_link.done_at is not null) then
        update public.smart_task_job_items
           set done_at = case when v_done then now() end,
               done_by = case when v_done then p_actor end
         where id = v_link.id;
        update public.smart_tasks
           set updated_at = now()
         where id = v_task.id
           and tenant_id = p_tenant_id
         returning * into v_task;
        perform public.smart_task_append_event(
          v_task, p_actor,
          case when v_done then 'job_item_done' else 'job_item_reopened' end,
          jsonb_build_object(
            'job_item_id', v_item_id,
            'item_name', v_link.item_name
          )
        );
      end if;

    when 'set_handoff_note' then
      -- «Dónde quedó»: una sola nota vigente para quien siga; las anteriores
      -- quedan en el ledger.
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the assignee, the creator or a manager leaves the shift note'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      if v_task.status in ('completed', 'cancelled') then
        raise exception 'smart_tasks: a closed task has no next shift'
          using errcode = '23514', hint = 'task_closed';
      end if;
      v_note := nullif(btrim(coalesce(v_payload ->> 'note', '')), '');
      if length(v_note) > 2000 then
        raise exception 'smart_tasks: the shift note is too long'
          using errcode = '22001', hint = 'note_too_long';
      end if;
      if v_note is distinct from v_task.handoff_note then
        update public.smart_tasks
           set handoff_note = v_note,
               handoff_note_at = case when v_note is not null then now() end,
               handoff_note_by = case when v_note is not null then p_actor end,
               updated_at = now()
         where id = v_task.id
           and tenant_id = p_tenant_id
         returning * into v_task;
        perform public.smart_task_append_event(
          v_task, p_actor,
          case when v_note is null then 'handoff_note_cleared' else 'handoff_note_set' end,
          jsonb_strip_nulls(jsonb_build_object('note', v_note))
        );
      end if;

    when 'add_job_item_note' then
      -- La primera nota de un servicio, o «continuar»: una entrada nueva en
      -- su hilo. La anterior queda en la historia y ésta pasa a ser la
      -- vigente.
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the assignee, the creator or a manager notes services'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      if v_task.status in ('completed', 'cancelled') then
        raise exception 'smart_tasks: a closed task keeps its services as they were'
          using errcode = '23514', hint = 'task_closed';
      end if;
      v_note := nullif(btrim(coalesce(v_payload ->> 'note', '')), '');
      if v_note is null then
        raise exception 'smart_tasks: the note is empty'
          using errcode = '22023', hint = 'note_required';
      end if;
      if length(v_note) > 2000 then
        raise exception 'smart_tasks: the service note is too long'
          using errcode = '22001', hint = 'note_too_long';
      end if;
      select * into v_link
        from public.smart_task_job_items link
       where link.task_id = v_task.id
         and link.job_item_id = v_item_id
         and link.tenant_id = p_tenant_id;
      if not found then
        raise exception 'smart_tasks: that service is not part of this task'
          using errcode = '23503', hint = 'job_item_not_linked';
      end if;
      if v_link.invalidated_at is not null then
        raise exception 'smart_tasks: the workshop removed this service from the job'
          using errcode = '23514', hint = 'job_item_invalidated';
      end if;
      insert into public.smart_task_job_item_notes (
        tenant_id, task_id, job_item_id, body, created_by
      ) values (
        p_tenant_id, v_task.id, v_item_id, v_note, p_actor
      )
      returning * into v_entry;
      update public.smart_tasks
         set updated_at = now()
       where id = v_task.id
         and tenant_id = p_tenant_id
       returning * into v_task;
      perform public.smart_task_append_event(
        v_task, p_actor, 'job_item_note_added',
        jsonb_build_object(
          'note_id', v_entry.id,
          'job_item_id', v_item_id,
          'item_name', v_link.item_name,
          'note', v_note
        )
      );

    when 'edit_job_item_note', 'withdraw_job_item_note' then
      -- Corregir o retirar: cada uno lo suyo, mientras pueda trabajar la
      -- tarea. Lo que decía queda en el ledger.
      if not (v_is_assignee or v_is_creator or p_is_manager) then
        raise exception 'smart_tasks: only the assignee, the creator or a manager notes services'
          using errcode = '42501', hint = 'not_authorized';
      end if;
      if v_task.status in ('completed', 'cancelled') then
        raise exception 'smart_tasks: a closed task keeps its services as they were'
          using errcode = '23514', hint = 'task_closed';
      end if;
      v_note_id := nullif(v_payload ->> 'note_id', '')::uuid;
      if v_note_id is null then
        raise exception 'smart_tasks: which note?'
          using errcode = '22023', hint = 'note_id_required';
      end if;
      select * into v_entry
        from public.smart_task_job_item_notes entry
       where entry.id = v_note_id
         and entry.task_id = v_task.id
         and entry.tenant_id = p_tenant_id
       for update;
      if not found then
        raise exception 'smart_tasks: that note is not part of this task'
          using errcode = '23503', hint = 'note_not_found';
      end if;
      if v_entry.created_by is distinct from p_actor then
        raise exception 'smart_tasks: only whoever wrote a note corrects or withdraws it'
          using errcode = '42501', hint = 'not_note_author';
      end if;
      select * into v_link
        from public.smart_task_job_items link
       where link.task_id = v_task.id
         and link.job_item_id = v_entry.job_item_id
         and link.tenant_id = p_tenant_id;

      if p_command = 'edit_job_item_note' then
        if v_entry.withdrawn_at is not null then
          raise exception 'smart_tasks: a withdrawn note is not corrected'
            using errcode = '23514', hint = 'note_withdrawn';
        end if;
        v_note := nullif(btrim(coalesce(v_payload ->> 'note', '')), '');
        if v_note is null then
          raise exception 'smart_tasks: the note is empty'
            using errcode = '22023', hint = 'note_required';
        end if;
        if length(v_note) > 2000 then
          raise exception 'smart_tasks: the service note is too long'
            using errcode = '22001', hint = 'note_too_long';
        end if;
        if v_note is distinct from v_entry.body then
          update public.smart_task_job_item_notes
             set body = v_note, edited_at = now(), edited_by = p_actor
           where id = v_entry.id;
          update public.smart_tasks
             set updated_at = now()
           where id = v_task.id
             and tenant_id = p_tenant_id
           returning * into v_task;
          perform public.smart_task_append_event(
            v_task, p_actor, 'job_item_note_edited',
            jsonb_strip_nulls(jsonb_build_object(
              'note_id', v_entry.id,
              'job_item_id', v_entry.job_item_id,
              'item_name', v_link.item_name,
              'note', v_note,
              'previous_note', v_entry.body
            ))
          );
        end if;
      elsif v_entry.withdrawn_at is null then
        update public.smart_task_job_item_notes
           set withdrawn_at = now(), withdrawn_by = p_actor
         where id = v_entry.id;
        update public.smart_tasks
           set updated_at = now()
         where id = v_task.id
           and tenant_id = p_tenant_id
         returning * into v_task;
        perform public.smart_task_append_event(
          v_task, p_actor, 'job_item_note_withdrawn',
          jsonb_strip_nulls(jsonb_build_object(
            'note_id', v_entry.id,
            'job_item_id', v_entry.job_item_id,
            'item_name', v_link.item_name,
            'previous_note', v_entry.body
          ))
        );
      end if;

    else
      raise exception 'smart_tasks: unknown command %', p_command
        using errcode = '22023', hint = 'unknown_command';
  end case;

  perform set_config('vinabike.smart_task_cmd', '', true);
  return public.smart_task_row_to_json(v_task);
end;
$function$;

-- ── ERP y portal escriben notas de servicio ──────────────────────────
CREATE OR REPLACE FUNCTION public.smart_task_command_v1(p_task_id uuid, p_expected_version integer, p_command text, p_payload jsonb, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
      'set_job_items', 'set_job_item_done', 'set_handoff_note',
      'add_job_item_note', 'edit_job_item_note', 'withdraw_job_item_note'
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
$function$;

CREATE OR REPLACE FUNCTION public.worker_task_command_v1(p_task_id uuid, p_expected_version integer, p_command text, p_payload jsonb, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
    array['acknowledge', 'return', 'start', 'block', 'unblock', 'complete',
      'set_job_item_done', 'set_handoff_note',
      'add_job_item_note', 'edit_job_item_note', 'withdraw_job_item_note'],
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
$function$;

-- ── Crear: la primera nota de cada servicio viene con el encargo ─────
CREATE OR REPLACE FUNCTION public.smart_task_create_v1(p_payload jsonb, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
  v_note_key text;
  v_note text;
  v_entry public.smart_task_job_item_notes%rowtype;
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
    due_date, assigned_to, assigned_employee_id, created_by,
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
    nullif(v_payload ->> 'assigned_employee_id', '')::uuid,
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
  if v_task.assigned_to is not null or v_task.assigned_employee_id is not null then
    perform public.smart_task_append_event(
      v_task, v_actor, 'assigned',
      jsonb_strip_nulls(jsonb_build_object(
        'assigned_to', v_task.assigned_to,
        'assigned_employee_id', v_task.assigned_employee_id
      ))
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

  -- La primera nota de cada servicio puede venir con el encargo.
  if jsonb_typeof(v_payload -> 'job_item_notes') = 'object' then
    for v_note_key, v_note in
      select note.key, nullif(btrim(note.value #>> '{}'), '')
      from jsonb_each(v_payload -> 'job_item_notes') as note
      order by note.key
    loop
      continue when v_note is null;
      if length(v_note) > 2000 then
        raise exception 'smart_tasks: the service note is too long'
          using errcode = '22001', hint = 'note_too_long';
      end if;
      if not exists (
        select 1 from public.smart_task_job_items link
         where link.task_id = v_task.id
           and link.tenant_id = v_tenant
           and link.job_item_id::text = v_note_key
      ) then
        raise exception 'smart_tasks: that service is not part of this task'
          using errcode = '23503', hint = 'job_item_not_linked';
      end if;
      insert into public.smart_task_job_item_notes (
        tenant_id, task_id, job_item_id, body, created_by
      ) values (
        v_tenant, v_task.id, v_note_key::uuid, v_note, v_actor
      )
      returning * into v_entry;
      perform public.smart_task_append_event(
        v_task, v_actor, 'job_item_note_added',
        jsonb_build_object(
          'note_id', v_entry.id,
          'job_item_id', v_entry.job_item_id,
          'item_name', (
            select link.item_name from public.smart_task_job_items link
             where link.task_id = v_task.id
               and link.job_item_id = v_entry.job_item_id
          ),
          'note', v_note,
          'at_create', true
        )
      );
    end loop;
  end if;

  perform set_config('vinabike.smart_task_cmd', '', true);

  v_result := jsonb_build_object('task', public.smart_task_row_to_json(v_task));
  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'task_create', p_idempotency_key, v_fingerprint,
    v_task.id, v_result
  );
  return v_result;
end;
$function$;

-- ── Aviso de las notas de servicio ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_smart_task_erp_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_task public.smart_tasks%rowtype;
  v_actor_name text;
  v_recipients jsonb := '[]'::jsonb;
  v_entry jsonb;
  v_recipient uuid;
begin
  -- Borrar la nota del turno retira su aviso: no queda un texto que ya no
  -- está en la tarea.
  if new.event_type = 'handoff_note_cleared' then
    delete from public.erp_notifications notification
     where notification.tenant_id = new.tenant_id
       and notification.type = 'smart_task_handoff_note'
       and notification.entity_type = 'smart_task'
       and notification.entity_id = new.task_id;
    return new;
  end if;

  -- Cada nota de servicio tiene su propio aviso (entidad: la nota), para que
  -- una nota nueva no pise el aviso sin leer de otra. Retirarla lo retira;
  -- corregirla lo actualiza sin volver a encenderlo.
  if new.event_type = 'job_item_note_withdrawn' then
    delete from public.erp_notifications notification
     where notification.tenant_id = new.tenant_id
       and notification.type = 'smart_task_service_note'
       and notification.entity_type = 'smart_task_service_note'
       and notification.entity_id = (new.payload ->> 'note_id')::uuid;
    return new;
  end if;
  if new.event_type = 'job_item_note_edited' then
    update public.erp_notifications notification
       set body = coalesce(
             public.erp_actor_display_name(new.actor_user_id, new.tenant_id), 'Alguien')
             || ' sobre «' || coalesce(new.payload ->> 'item_name', 'un servicio') || '»: '
             || left(new.payload ->> 'note', 140)
             || case when length(new.payload ->> 'note') > 140 then '…' else '' end,
           updated_at = now()
     where notification.tenant_id = new.tenant_id
       and notification.type = 'smart_task_service_note'
       and notification.entity_type = 'smart_task_service_note'
       and notification.entity_id = (new.payload ->> 'note_id')::uuid;
    return new;
  end if;

  if new.event_type not in (
    'assigned', 'unassigned', 'returned', 'blocked', 'completed', 'handoff_note_set',
    'job_item_note_added'
  ) then
    return new;
  end if;

  -- Las notas que trae el encargo llegan con el aviso de la asignación.
  if new.event_type = 'job_item_note_added'
    and coalesce((new.payload ->> 'at_create')::boolean, false) then
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
    when 'handoff_note_set' then
      -- La nota va a quien no la escribió: del que trabaja a quien encargó,
      -- o del que encargó al que trabaja.
      v_recipient := case
        when new.actor_user_id = v_task.assigned_to then v_task.created_by
        else coalesce(v_task.assigned_to, v_task.created_by)
      end;
      v_recipients := jsonb_build_array(jsonb_build_object(
        'recipient', v_recipient::text,
        'type', 'smart_task_handoff_note',
        'title', 'Nota para el siguiente turno',
        'body', coalesce(v_actor_name, 'Alguien') || ' sobre ' || v_task.title || ': '
          || left(new.payload ->> 'note', 140)
          || case when length(new.payload ->> 'note') > 140 then '…' else '' end,
        'severity', 'info'
      ));
    when 'job_item_note_added' then
      -- Igual que la nota del turno: a quien no la escribió.
      v_recipient := case
        when new.actor_user_id = v_task.assigned_to then v_task.created_by
        else coalesce(v_task.assigned_to, v_task.created_by)
      end;
      v_recipients := jsonb_build_array(jsonb_build_object(
        'recipient', v_recipient::text,
        'type', 'smart_task_service_note',
        'entity_type', 'smart_task_service_note',
        'entity_id', new.payload ->> 'note_id',
        'title', 'Nota en ' || v_task.title,
        'body', coalesce(v_actor_name, 'Alguien') || ' sobre «'
          || coalesce(new.payload ->> 'item_name', 'un servicio') || '»: '
          || left(new.payload ->> 'note', 140)
          || case when length(new.payload ->> 'note') > 140 then '…' else '' end,
        'severity', 'info'
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
      coalesce(v_entry ->> 'entity_type', 'smart_task'),
      coalesce((v_entry ->> 'entity_id')::uuid, v_task.id),
      v_entry ->> 'severity',
      jsonb_strip_nulls(jsonb_build_object(
        'task_id', v_task.id,
        'task_title', v_task.title,
        'event_type', new.event_type,
        'actor_name', v_actor_name,
        'job_id', v_task.linked_job_id,
        'job_item_id', new.payload ->> 'job_item_id',
        'note_id', new.payload ->> 'note_id'
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
$function$;

-- ── Proyección del portal: la nota vigente de cada servicio ──────────
-- Mismo tipo de retorno (`job_items` es jsonb): se reemplaza en su lugar.
CREATE OR REPLACE FUNCTION public.get_my_worker_tasks_v1()
 RETURNS TABLE(id uuid, title text, description text, status text, priority text, due_date timestamp with time zone, version integer, acknowledged_at timestamp with time zone, started_at timestamp with time zone, completed_at timestamp with time zone, blocked_reason text, created_at timestamp with time zone, creator_name text, assigner_name text, job_id uuid, job_number text, bike_labels jsonb, job_items jsonb, handoff_note text, handoff_note_at timestamp with time zone, handoff_note_by_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
    coalesce((
      select jsonb_agg(distinct link.bike_label)
      from public.smart_task_job_items link
      where link.task_id = task.id
        and link.bike_label is not null
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'job_item_id', link.job_item_id,
        'item_name', link.item_name,
        'item_instructions', link.item_instructions,
        'item_type', link.item_type,
        'bike_label', link.bike_label,
        'invalidated', case when link.invalidated_at is not null then true end,
        'context_changed', case when link.context_changed_at is not null then true end,
        'done_at', link.done_at,
        'done_by_name', case when link.done_at is not null
          then public.erp_actor_display_name(link.done_by, task.tenant_id) end,
        -- La nota vigente del servicio y cuántas tiene su hilo.
        'note', (
          select jsonb_build_object(
            'id', entry.id,
            'body', entry.body,
            'created_at', entry.created_at,
            'author_name', public.erp_actor_display_name(entry.created_by, task.tenant_id),
            'edited_at', entry.edited_at,
            'mine', entry.created_by = auth.uid()
          )
          from public.smart_task_job_item_notes entry
          where entry.task_id = task.id
            and entry.tenant_id = task.tenant_id
            and entry.job_item_id = link.job_item_id
            and entry.withdrawn_at is null
          order by entry.created_at desc, entry.id desc
          limit 1
        ),
        'note_count', (
          select nullif(count(*), 0)
          from public.smart_task_job_item_notes entry
          where entry.task_id = task.id
            and entry.tenant_id = task.tenant_id
            and entry.job_item_id = link.job_item_id
            and entry.withdrawn_at is null
        )
      )) order by link.linked_at)
      from public.smart_task_job_items link
      where link.task_id = task.id
    ), '[]'::jsonb),
    task.handoff_note,
    task.handoff_note_at,
    case when task.handoff_note is not null
      then public.erp_actor_display_name(task.handoff_note_by, task.tenant_id) end
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
$function$;

-- ── ERP: la nota vigente de cada servicio de una tarea ───────────────
create or replace function public.get_smart_task_service_notes_v1(p_task_id uuid)
 returns table (
   job_item_id uuid,
   note_id uuid,
   body text,
   created_at timestamptz,
   created_by uuid,
   author_name text,
   edited_at timestamptz,
   note_count integer
 )
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_task public.smart_tasks%rowtype;
begin
  if not public.smart_task_service_notes_readable_v1(p_task_id) then
    raise exception 'smart_tasks: task not found'
      using errcode = '42501', hint = 'not_authorized';
  end if;
  select * into v_task from public.smart_tasks where id = p_task_id;

  return query
  select distinct on (entry.job_item_id)
    entry.job_item_id,
    entry.id,
    entry.body,
    entry.created_at,
    entry.created_by,
    public.erp_actor_display_name(entry.created_by, v_task.tenant_id),
    entry.edited_at,
    (count(*) over (partition by entry.job_item_id))::integer
  from public.smart_task_job_item_notes entry
  where entry.task_id = v_task.id
    and entry.tenant_id = v_task.tenant_id
    and entry.withdrawn_at is null
  order by entry.job_item_id, entry.created_at desc, entry.id desc;
end;
$function$;

revoke all on function public.get_smart_task_service_notes_v1(uuid) from public, anon;
grant execute on function public.get_smart_task_service_notes_v1(uuid) to authenticated, service_role;

-- ── La línea de tiempo de un servicio ────────────────────────────────
-- Del ledger, lo más reciente primero. `kind`:
--   assigned          encargó el servicio (primer vínculo)
--   note_written      primera nota del hilo
--   note_continued    una nota que sigue a otra
--   note_edited       corrigió una nota (`previous_note`: lo que decía)
--   note_withdrawn    retiró una nota (`previous_note`: lo que decía)
--   done / reopened   hecho / pendiente otra vez
--   service_changed   el taller cambió la línea del trabajo (sin autor)
--   service_removed   el taller sacó la línea del trabajo (sin autor)
-- `is_current` marca la entrada que trae el texto de la nota vigente.
create or replace function public.get_smart_task_service_timeline_v1(
  p_task_id uuid,
  p_job_item_id uuid
)
 returns table (
   occurred_at timestamptz,
   kind text,
   actor_name text,
   from_portal boolean,
   note text,
   previous_note text,
   note_id uuid,
   at_create boolean,
   is_current boolean
 )
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_task public.smart_tasks%rowtype;
  v_current uuid;
begin
  if not public.smart_task_service_notes_readable_v1(p_task_id) then
    raise exception 'smart_tasks: task not found'
      using errcode = '42501', hint = 'not_authorized';
  end if;
  select * into v_task from public.smart_tasks where id = p_task_id;

  select entry.id into v_current
    from public.smart_task_job_item_notes entry
   where entry.task_id = v_task.id
     and entry.tenant_id = v_task.tenant_id
     and entry.job_item_id = p_job_item_id
     and entry.withdrawn_at is null
   order by entry.created_at desc, entry.id desc
   limit 1;

  return query
  with ledger as (
    select event.id, event.created_at, event.task_version, event.event_type,
           event.actor_user_id, event.payload
      from public.smart_task_events event
     where event.task_id = v_task.id
       and event.tenant_id = v_task.tenant_id
       and (
         (event.event_type in (
            'job_item_note_added', 'job_item_note_edited', 'job_item_note_withdrawn',
            'job_item_done', 'job_item_reopened',
            'job_item_context_changed', 'job_item_invalidated')
          and event.payload ->> 'job_item_id' = p_job_item_id::text)
         or (event.event_type = 'job_items_linked'
          and coalesce(event.payload -> 'job_item_ids', '[]'::jsonb) ? p_job_item_id::text)
       )
  ),
  entries as (
    (select linked.id as event_id, linked.created_at as occurred_at,
            linked.task_version as version, 0 as rank, 'assigned'::text as kind,
            linked.actor_user_id as actor, null::text as note,
            null::text as previous_note, null::uuid as note_id, false as at_create
       from ledger linked
      where linked.event_type = 'job_items_linked'
      order by linked.created_at, linked.task_version
      limit 1)
    union all
    select written.id, written.created_at, written.task_version, 1,
           case when row_number() over (
               order by written.created_at, written.task_version, written.id) = 1
             then 'note_written' else 'note_continued' end,
           written.actor_user_id, written.payload ->> 'note', null,
           (written.payload ->> 'note_id')::uuid,
           coalesce((written.payload ->> 'at_create')::boolean, false)
      from ledger written
     where written.event_type = 'job_item_note_added'
    union all
    select changed.id, changed.created_at, changed.task_version, 1,
           case when changed.event_type = 'job_item_note_edited'
             then 'note_edited' else 'note_withdrawn' end,
           changed.actor_user_id, changed.payload ->> 'note',
           changed.payload ->> 'previous_note',
           (changed.payload ->> 'note_id')::uuid, false
      from ledger changed
     where changed.event_type in ('job_item_note_edited', 'job_item_note_withdrawn')
    union all
    select marked.id, marked.created_at, marked.task_version, 2,
           case when marked.event_type = 'job_item_done' then 'done' else 'reopened' end,
           marked.actor_user_id, null, null, null, false
      from ledger marked
     where marked.event_type in ('job_item_done', 'job_item_reopened')
    union all
    -- Lo que el taller cambió o sacó antes de re-vincular, con la hora de la
    -- marca que se reemplazó.
    select carried.id, (carried.payload ->> 'at')::timestamptz, carried.task_version, 3,
           case when carried.event_type = 'job_item_context_changed'
             then 'service_changed' else 'service_removed' end,
           null, null, null, null, false
      from ledger carried
     where carried.event_type in ('job_item_context_changed', 'job_item_invalidated')
    union all
    select null::uuid, link.context_changed_at, null::integer, 3, 'service_changed',
           null, null, null, null, false
      from public.smart_task_job_items link
     where link.task_id = v_task.id
       and link.tenant_id = v_task.tenant_id
       and link.job_item_id = p_job_item_id
       and link.context_changed_at is not null
    union all
    select null::uuid, link.invalidated_at, null::integer, 3, 'service_removed',
           null, null, null, null, false
      from public.smart_task_job_items link
     where link.task_id = v_task.id
       and link.tenant_id = v_task.tenant_id
       and link.job_item_id = p_job_item_id
       and link.invalidated_at is not null
  ),
  -- La vigente se lee en su última escritura: la corrección si la hubo.
  -- Dentro de una transacción la hora es la misma; la versión de la tarea
  -- ordena lo que pasó antes.
  current_text as (
    select entry.event_id
      from entries entry
     where entry.note_id = v_current
       and entry.kind in ('note_written', 'note_continued', 'note_edited')
     order by entry.occurred_at desc, entry.version desc nulls last
     limit 1
  )
  select entry.occurred_at,
         entry.kind,
         public.erp_actor_display_name(entry.actor, v_task.tenant_id),
         case when entry.actor is null then null else exists (
           select 1 from public.employee_portal_accounts portal
            where portal.auth_user_id = entry.actor
              and portal.tenant_id = v_task.tenant_id
         ) end,
         entry.note,
         entry.previous_note,
         entry.note_id,
         entry.at_create,
         coalesce(entry.event_id = (select current_entry.event_id from current_text current_entry), false)
    from entries entry
   order by entry.occurred_at desc, entry.version desc nulls first, entry.rank desc;
end;
$function$;

revoke all on function public.get_smart_task_service_timeline_v1(uuid, uuid) from public, anon;
grant execute on function public.get_smart_task_service_timeline_v1(uuid, uuid) to authenticated, service_role;
