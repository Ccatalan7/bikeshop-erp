-- Tareas del taller, fase 2: el trabajador marca cada servicio y deja una nota
-- para el siguiente turno (dueño, 2026-09-26).
--
-- Hasta hoy una tarea sobre un trabajo traía la lista de sus servicios, pero
-- nadie podía marcar cuál estaba hecho: la única marca era completar la tarea
-- entera. Y quien dejaba un trabajo a medias no tenía dónde decir dónde quedó.
--
-- Modelo:
--   * Hecho / pendiente vive en el VÍNCULO tarea↔servicio
--     (`smart_task_job_items.done_at/done_by`): es lo que el responsable
--     reporta del servicio que se le encargó. No toca el checklist técnico del
--     trabajo (`mechanic_job_tasks`, pasos generados desde la descripción del
--     servicio, 351 filas y ninguna marcada al 2026-09-26) ni la línea
--     facturable (`mechanic_job_items`): el registro de superficies prohíbe
--     duplicar ese checklist y que una tarea cambie en silencio el registro
--     vinculado.
--   * La nota del turno es UNA por tarea (`smart_tasks.handoff_note`), con
--     autor y hora del servidor; cada versión anterior queda en el ledger.
--   * Todo pasa por `smart_task_command_v1` (ERP) y `worker_task_command_v1`
--     (portal): `set_job_item_done` {job_item_id, done} y `set_handoff_note`
--     {note}. Marcan el responsable, quien encargó o un manager, y sólo en una
--     tarea abierta. Ninguno completa la tarea solo: completar sigue siendo
--     una decisión explícita.
--   * Orden de bloqueo: marcar toma la identidad del servicio antes que la
--     tarea, como re-vincular; el traspaso borra vínculos y después toca la
--     otra tarea.
--   * Re-vincular (`set_job_items` borra y vuelve a crear los vínculos) repone
--     la marca de los servicios que siguen.
--   * La nota avisa a quien no la escribió (erp_notifications); las marcas de
--     servicio no avisan a nadie: serían ruido.
--   * `erp_actor_display_name` resuelve también a quien actúa desde su portal
--     (su ficha), para que «hecho por Braulio» tenga nombre.
--   * Revisión de Codex (2026-09-26): los autores nuevos (`done_by`,
--     `handoff_note_by`) sueltan a una cuenta borrada en vez de reponerla —la
--     FK es `on delete set null` y reponerla bloqueaba el borrado—;
--     `smart_task_lock_job_items`, que crear, re-vincular y marcar llaman
--     antes que nada, toma también las filas de servicio (un borrado paralelo
--     dejaba vivo un vínculo a una línea inexistente, y con «traspasar» las
--     dos transacciones se esperaban); y borrar la nota retira su aviso. Los autores del kernel (`created_by` y compañía) ya reponían
--     la cuenta y hoy impiden borrar a quien creó una tarea: queda aparte.

alter table public.smart_task_job_items
  add column if not exists done_at timestamptz,
  add column if not exists done_by uuid references auth.users(id) on delete set null;

alter table public.smart_task_job_items
  drop constraint if exists smart_task_job_items_done_by_needs_done_at;
alter table public.smart_task_job_items
  add constraint smart_task_job_items_done_by_needs_done_at
  check (done_by is null or done_at is not null);

create index if not exists idx_smart_task_job_items_done_by_fk
  on public.smart_task_job_items (done_by);

alter table public.smart_tasks
  add column if not exists handoff_note text,
  add column if not exists handoff_note_at timestamptz,
  add column if not exists handoff_note_by uuid references auth.users(id) on delete set null;

-- `handoff_note_by` puede quedar null si se borra la cuenta: la nota sigue.
alter table public.smart_tasks
  drop constraint if exists smart_tasks_handoff_note_shape_check;
alter table public.smart_tasks
  add constraint smart_tasks_handoff_note_shape_check
  check (
    (handoff_note is null and handoff_note_at is null and handoff_note_by is null)
    or (handoff_note is not null
      and length(btrim(handoff_note)) between 1 and 2000
      and handoff_note_at is not null)
  );

create index if not exists idx_smart_tasks_handoff_note_by_fk
  on public.smart_tasks (handoff_note_by);

alter table public.smart_task_events
  drop constraint if exists smart_task_events_event_type_check;
alter table public.smart_task_events
  add constraint smart_task_events_event_type_check
  check (event_type = any (array[
    'created', 'details_updated', 'assigned', 'unassigned', 'acknowledged',
    'returned', 'started', 'blocked', 'unblocked', 'completed', 'reopened',
    'cancelled', 'visibility_changed', 'job_items_linked', 'job_items_unlinked',
    'conversation_linked', 'due_soon', 'mentioned',
    'job_item_done', 'job_item_reopened', 'handoff_note_set', 'handoff_note_cleared'
  ]));

-- ── Guard de vínculos: hecho/pendiente sólo por comando ───────────────
CREATE OR REPLACE FUNCTION public.smart_task_job_items_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_item public.mechanic_job_items%rowtype;
  v_task public.smart_tasks%rowtype;
begin
  if tg_op = 'UPDATE' then
    -- Only evidence markers may change after the link is created. The
    -- assignment snapshot itself is immutable.
    if new.task_id is distinct from old.task_id
      or new.job_item_id is distinct from old.job_item_id
      or new.tenant_id is distinct from old.tenant_id
      or new.job_id is distinct from old.job_id
      or new.job_bike_id is distinct from old.job_bike_id
      or new.item_name is distinct from old.item_name
      or new.item_type is distinct from old.item_type
      or new.job_number is distinct from old.job_number
      or new.bike_label is distinct from old.bike_label
      or new.item_instructions is distinct from old.item_instructions
      or new.linked_by is distinct from old.linked_by
      or new.linked_at is distinct from old.linked_at then
      raise exception 'smart_task_job_items: link snapshot is immutable'
        using errcode = '23514';
    end if;
    -- Hecho / pendiente es del comando: lo marca `set_job_item_done`, y
    -- `set_job_items` lo repone al re-vincular los servicios que siguen.
    -- Ninguna otra escritura atribuye trabajo a nadie.
    if coalesce(current_setting('vinabike.smart_task_cmd', true), '')
      not in ('set_job_item_done', 'set_job_items') then
      new.done_at := old.done_at;
      -- Salvo la FK `on delete set null` cuando se borra la cuenta: lo hecho
      -- sigue hecho, sin nombre. Reponerlo haría imposible borrar la cuenta.
      if not (new.done_by is null
        and old.done_by is not null
        and not exists (select 1 from auth.users account where account.id = old.done_by)) then
        new.done_by := old.done_by;
      end if;
    end if;
    return new;
  end if;

  select * into v_task
  from public.smart_tasks
  where id = new.task_id;
  if not found then
    raise exception 'smart_task_job_items: task not found'
      using errcode = '23503';
  end if;
  if v_task.task_kind = 'note' then
    raise exception 'smart_tasks: a note keeps the job, never its service lines'
      using errcode = '23514', hint = 'note_has_no_services';
  end if;

  select * into v_item
  from public.mechanic_job_items
  where id = new.job_item_id;
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
  if coalesce(v_item.item_type, '') not in ('service', 'adhoc') then
    raise exception 'smart_task_job_items: only service lines can back a task'
      using errcode = '23514', hint = 'job_item_not_service';
  end if;

  new.tenant_id := v_task.tenant_id;
  new.job_bike_id := v_item.job_bike_id;
  new.item_name := coalesce(
    nullif(btrim(v_item.description), ''),
    nullif(btrim(v_item.product_name), ''),
    'Servicio del trabajo'
  );
  new.item_type := v_item.item_type;
  new.item_instructions := nullif(btrim(v_item.notes), '');
  -- Un vínculo nace pendiente.
  new.done_at := null;
  new.done_by := null;
  return new;
end;
$function$;

-- ── Guard de tareas: la nota del turno sólo por su comando ────────────
CREATE OR REPLACE FUNCTION public.smart_tasks_guard_work_tray()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_cmd text := coalesce(current_setting('vinabike.smart_task_cmd', true), '');
  v_is_creator boolean;
  v_is_manager boolean;
  v_worker_required boolean;
  v_requested_blocked_reason text;
  v_assignment_changed boolean;
  v_employee uuid;
begin
  if tg_op = 'INSERT' then
    new.version := 1;
    -- La tarea pertenece al TRABAJADOR; la cuenta es sólo por dónde le llega.
    -- Con trabajador, la cuenta se deriva de él (puede no tener ninguna); con
    -- sólo una cuenta, se busca el trabajador detrás de ella.
    if new.assigned_employee_id is not null then
      -- Elegibilidad y bloqueo en una sola lectura: se toma la fila del
      -- trabajador y sólo si sigue activo. Así una baja o un alta de cuenta en
      -- curso termina antes (y esta lectura la ve) o espera a que esta tarea
      -- exista (y su sincronización la ve).
      perform 1 from public.employees employee
       where employee.id = new.assigned_employee_id
         and employee.tenant_id = new.tenant_id
         and employee.status = 'active'
       for share;
      if not found then
        raise exception 'smart_tasks: assigned worker is not an active employee of this tenant'
          using errcode = '23514', hint = 'assignee_employee_not_eligible';
      end if;
      if new.assigned_to is not null then
        if public.smart_task_user_employee_v1(new.tenant_id, new.assigned_to)
          is distinct from new.assigned_employee_id then
          raise exception 'smart_tasks: the assignee account does not belong to the assigned worker'
            using errcode = '23514', hint = 'assignee_employee_mismatch';
        end if;
      else
        new.assigned_to := public.smart_task_employee_principal_v1(
          new.tenant_id, new.assigned_employee_id);
      end if;
    elsif new.assigned_to is not null then
      new.assigned_employee_id := public.smart_task_lock_user_employee_v1(
        new.tenant_id, new.assigned_to);
    end if;
    if new.task_kind = 'note'
      and new.status not in ('pending', 'cancelled') then
      raise exception 'smart_tasks: notes have no execution lifecycle'
        using errcode = '23514', hint = 'note_has_no_lifecycle';
    end if;
    if new.visibility = 'private'
      and (new.assigned_to is not null
        or new.assigned_employee_id is not null
        or new.linked_job_id is not null) then
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
    new.handoff_note := null;
    new.handoff_note_at := null;
    new.handoff_note_by := null;
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
    end if;
    if new.assigned_to is not null or new.assigned_employee_id is not null then
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
  -- El relleno sólo escribe quién es el responsable: no es un cambio que un
  -- cliente con la versión anterior deba perder por conflicto.
  new.version := case
    when v_cmd = 'employee_backfill' then old.version
    else old.version + 1
  end;
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
  -- La nota del turno la escribe sólo su comando, con autor y hora del
  -- servidor.
  if v_cmd <> 'set_handoff_note' then
    new.handoff_note := old.handoff_note;
    new.handoff_note_at := old.handoff_note_at;
    -- Salvo la FK `on delete set null` al borrar la cuenta de quien la
    -- escribió: la nota queda, sin nombre.
    if not (new.handoff_note_by is null
      and old.handoff_note_by is not null
      and not exists (select 1 from auth.users account where account.id = old.handoff_note_by)) then
      new.handoff_note_by := old.handoff_note_by;
    end if;
  end if;

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

  -- Trabajador y cuenta se mueven juntos. Cambiar de trabajador deriva su
  -- cuenta; cambiar sólo la cuenta (traspaso de acceso, herencia) conserva al
  -- trabajador que está detrás; quitar la cuenta a mano (devolver, desasignar)
  -- suelta también al trabajador.
  if new.assigned_employee_id is distinct from old.assigned_employee_id then
    if new.assigned_employee_id is not null then
      perform 1 from public.employees employee
       where employee.id = new.assigned_employee_id
         and employee.tenant_id = new.tenant_id
         and employee.status = 'active'
       for share;
      if not found then
        raise exception 'smart_tasks: assigned worker is not an active employee of this tenant'
          using errcode = '23514', hint = 'assignee_employee_not_eligible';
      end if;
      if new.assigned_to is not null
        and public.smart_task_user_employee_v1(new.tenant_id, new.assigned_to)
          is not distinct from new.assigned_employee_id then
        -- La cuenta (la que ya tenía o la que viene) es de este trabajador:
        -- se conserva y no se le mueve la bandeja a nadie.
        null;
      elsif new.assigned_to is distinct from old.assigned_to
        and new.assigned_to is not null then
        raise exception 'smart_tasks: the assignee account does not belong to the assigned worker'
          using errcode = '23514', hint = 'assignee_employee_mismatch';
      else
        new.assigned_to := public.smart_task_employee_principal_v1(
          new.tenant_id, new.assigned_employee_id);
      end if;
    elsif new.assigned_to is not distinct from old.assigned_to then
      new.assigned_to := null;
    elsif new.assigned_to is not null then
      new.assigned_employee_id := public.smart_task_lock_user_employee_v1(
        new.tenant_id, new.assigned_to);
    end if;
  elsif new.assigned_to is distinct from old.assigned_to then
    if new.assigned_to is null then
      -- Quitar la cuenta a mano (devolver, desasignar) suelta al trabajador;
      -- que el trabajador pierda su cuenta, no: la tarea sigue siendo suya.
      if v_cmd <> 'employee_access_sync' then
        new.assigned_employee_id := null;
      end if;
    else
      new.assigned_employee_id := public.smart_task_lock_user_employee_v1(
        new.tenant_id, new.assigned_to);
    end if;
  end if;
  v_assignment_changed := new.assigned_to is distinct from old.assigned_to
    or new.assigned_employee_id is distinct from old.assigned_employee_id;

  -- Cambio de responsable: creador/manager reasignan; el asignado solo puede
  -- devolver (a null). Re-valida elegibilidad y reinicia la recepción. La
  -- sincronización con la cuenta del trabajador y el relleno los hace el
  -- sistema: no son una reasignación de nadie y conservan cuándo y quién
  -- asignó; el relleno conserva además el acuse, porque la cuenta no cambia.
  if v_assignment_changed then
    if v_actor is not null
      and v_cmd not in ('employee_access_sync', 'employee_backfill')
      and not (v_is_creator or v_is_manager)
      and not (v_actor = old.assigned_to
        and new.assigned_to is null
        and new.assigned_employee_id is null) then
      raise exception 'smart_tasks: only the creator or a manager reassigns'
        using errcode = '42501', hint = 'not_authorized_assign';
    end if;
    -- El relleno no reasigna: no re-juzga una asignación vieja (una tarea
    -- cerrada puede apuntar a una cuenta que hoy ya no sería elegible).
    if new.assigned_to is not null and v_cmd <> 'employee_backfill' then
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
    end if;
    -- La sincronización, el traspaso entre cuentas de un mismo trabajador
    -- (`transfer_open_employee_tasks_v1`) y el relleno cambian por dónde le
    -- llega la tarea, no a quién ni quién se la dio.
    if v_cmd in ('employee_access_sync', 'employee_access_transition', 'employee_backfill')
      and new.assigned_employee_id is not distinct from old.assigned_employee_id
      or v_cmd = 'employee_backfill' then
      null;
    elsif new.assigned_to is not null or new.assigned_employee_id is not null then
      new.assigned_at := now();
      new.assigned_by := v_actor;
    else
      new.assigned_at := null;
      new.assigned_by := null;
    end if;
    if v_cmd <> 'employee_backfill' then
      new.acknowledged_at := null;
      new.acknowledged_by := null;
    end if;
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
$function$;

-- ── Los servicios se toman antes que vínculos y tareas ────────────────
CREATE OR REPLACE FUNCTION public.smart_task_lock_job_items(p_tenant_id uuid, p_job_item_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
  -- Y las filas de servicio, en este mismo punto: antes de traspasar vínculos
  -- de otras tareas, de tomar la tarea propia y de crear o marcar vínculos.
  -- Borrar un servicio toma su fila y después invalida sus vínculos; si
  -- alguien ya tenía un vínculo y esperaba la fila, las dos se esperaban
  -- (revisión de Codex, 2026-09-26). Tomarla antes de leerla, además, hace
  -- que un borrado en paralelo espere a que el vínculo nuevo exista y lo
  -- invalide, en vez de dejarlo vivo apuntando a una línea que ya no está.
  -- `for key share` no estorba a quien edita la línea; sólo a quien la borra.
  perform 1
    from public.mechanic_job_items item
   where item.id = any (p_job_item_ids)
     and item.tenant_id = p_tenant_id
   order by item.id
     for key share;
end;
$function$;

-- ── Re-vincular conserva lo hecho ─────────────────────────────────────
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

-- ── Comandos ──────────────────────────────────────────────────────────
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

  -- Marcar un servicio toma su identidad antes que la tarea, igual que
  -- re-vincular: el traspaso borra vínculos y después toca la otra tarea, y
  -- en orden contrario las dos se esperarían.
  if p_command = 'set_job_item_done' then
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
    'set_job_item_done', 'set_handoff_note'
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

    else
      raise exception 'smart_tasks: unknown command %', p_command
        using errcode = '22023', hint = 'unknown_command';
  end case;

  perform set_config('vinabike.smart_task_cmd', '', true);
  return public.smart_task_row_to_json(v_task);
end;
$function$;

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
      'set_job_items', 'set_job_item_done', 'set_handoff_note'
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
      'set_job_item_done', 'set_handoff_note'],
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

-- ── Aviso de la nota del turno ────────────────────────────────────────
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

  if new.event_type not in (
    'assigned', 'unassigned', 'returned', 'blocked', 'completed', 'handoff_note_set'
  ) then
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
$function$;

-- ── Nombre de quien actúa desde el portal ─────────────────────────────
CREATE OR REPLACE FUNCTION public.erp_actor_display_name(p_user_id uuid, p_tenant_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  actor_name text;
begin
  if p_user_id is null or p_tenant_id is null then
    return null;
  end if;

  select nullif(
    trim(
      coalesce(employee.first_name, '')
      || ' '
      || coalesce(employee.last_name, '')
    ),
    ''
  )
  into actor_name
  from public.user_profiles profile
  join public.employees employee
    on employee.id = profile.employee_id
   and employee.tenant_id = profile.tenant_id
  where profile.user_id = p_user_id
    and profile.tenant_id = p_tenant_id
  limit 1;

  if actor_name is not null then
    return actor_name;
  end if;

  -- Un trabajador que actúa desde su portal no tiene perfil ERP: su nombre
  -- es el de su ficha.
  select nullif(
    trim(
      coalesce(employee.first_name, '')
      || ' '
      || coalesce(employee.last_name, '')
    ),
    ''
  )
  into actor_name
  from public.employee_portal_accounts portal
  join public.employees employee
    on employee.id = portal.employee_id
   and employee.tenant_id = portal.tenant_id
  where portal.auth_user_id = p_user_id
    and portal.tenant_id = p_tenant_id
  limit 1;

  if actor_name is not null then
    return actor_name;
  end if;

  -- Auth metadata is considered only after proving that the target identity is
  -- attached to this tenant. Email is deliberately not used as a fallback.
  if not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = p_user_id
      and profile.tenant_id = p_tenant_id
    union all
    select 1
    from public.customers customer
    where customer.auth_user_id = p_user_id
      and customer.tenant_id = p_tenant_id
    union all
    select 1
    from public.employee_portal_accounts portal
    where portal.auth_user_id = p_user_id
      and portal.tenant_id = p_tenant_id
  ) then
    return null;
  end if;

  select nullif(
    trim(
      coalesce(
        auth_user.raw_user_meta_data->>'full_name',
        auth_user.raw_user_meta_data->>'name',
        auth_user.raw_user_meta_data->>'display_name',
        ''
      )
    ),
    ''
  )
  into actor_name
  from auth.users auth_user
  where auth_user.id = p_user_id;

  return actor_name;
end;
$function$;

-- ── Proyección del portal: servicios marcables y la nota ─────────────
-- Cambia el tipo de retorno: se reemplaza y se devuelven los mismos permisos
-- que tenía (authenticated y service_role).
drop function if exists public.get_my_worker_tasks_v1();

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
          then public.erp_actor_display_name(link.done_by, task.tenant_id) end
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

revoke all on function public.get_my_worker_tasks_v1() from public, anon;
grant execute on function public.get_my_worker_tasks_v1() to authenticated, service_role;
