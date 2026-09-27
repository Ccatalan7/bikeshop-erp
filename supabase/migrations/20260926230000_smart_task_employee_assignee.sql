-- Una tarea se asigna al TRABAJADOR, no a su cuenta (dueño, 2026-09-26).
--
-- Hasta hoy `smart_tasks.assigned_to` era la única forma de asignar y apunta a
-- `auth.users`: a un trabajador sin usuario del ERP ni cuenta del portal
-- (Braulio, Lucas y Rodrigo el 2026-09-26) no se le podía dar una tarea. El
-- dueño lo quiere al revés: la tarea es de la persona, y «si un trabajador se
-- crea un usuario luego de que le fueron asignadas tareas, esas tareas son
-- heredadas y llegan a su bandeja de entrada».
--
-- Modelo:
--   * `assigned_employee_id` es el responsable. `assigned_to` pasa a ser la
--     cuenta por la que la tarea le llega, derivada del trabajador por el
--     guard: su usuario ERP activo, si no su cuenta activa del portal, si no
--     ninguna. Asignar sólo por cuenta (quien no es trabajador, el asistente,
--     clientes legados) sigue igual y el guard busca el trabajador detrás.
--   * Sincronización: la cuenta de las tareas abiertas de un trabajador sigue
--     a su cuenta vigente. Gana su primera cuenta (vínculo ERP, perfil activo
--     o portal): le llegan. La pierde: dejan de llegarle a la vieja y siguen
--     a su nombre. La cambia: pasan a la nueva. Corre al final de la
--     transacción que cambió el acceso (trigger diferido), cuando ya se ve el
--     estado final: los flujos de cambio ERP↔portal pasan por estados
--     intermedios y ya traspasan con `transfer_open_employee_tasks_v1`.
--   * Orden de bloqueo trabajador → tareas: crear o asignar (por trabajador o
--     por cuenta) toma la fila del trabajador, sólo si sigue activo, antes de
--     leer su cuenta, y la sincronización la toma antes de tocar sus tareas.
--     Una tarea creada en el mismo instante en que nace o se va la cuenta no
--     se queda con la equivocada. Residuo aceptado: la escritura directa
--     legada toma la fila de la tarea antes que la del trabajador; si una
--     transacción así se cruza con una sincronización, Postgres aborta una de
--     las dos (40P01) y se reintenta. Los comandos canónicos no tienen ese
--     cruce.
--   * Avisos: la sincronización registra `assigned` a nombre de quien asignó
--     la tarea (no de quien aceptó la invitación: el productor de avisos calla
--     al propio actor). En el portal, la tarea llega por
--     `get_my_worker_tasks_v1`; los avisos del ERP no se leen desde el portal.

-- Nada de RLS cambia: la visibilidad sigue decidiéndose por `assigned_to`, que
-- la herencia rellena, y una tarea de equipo la ve todo el tenant.

alter table public.smart_tasks
  add column if not exists assigned_employee_id uuid;

do $do$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'smart_tasks_assigned_employee_tenant_fk'
      and conrelid = 'public.smart_tasks'::regclass
  ) then
    alter table public.smart_tasks
      add constraint smart_tasks_assigned_employee_tenant_fk
      foreign key (assigned_employee_id, tenant_id)
      references public.employees (id, tenant_id)
      on delete set null (assigned_employee_id);
  end if;
end;
$do$;

create index if not exists idx_smart_tasks_assigned_employee
  on public.smart_tasks (tenant_id, assigned_employee_id, status)
  where assigned_employee_id is not null;

alter table public.smart_tasks
  drop constraint if exists smart_tasks_note_has_no_assignee_check;
alter table public.smart_tasks
  add constraint smart_tasks_note_has_no_assignee_check
  check (task_kind <> 'note' or (assigned_to is null and assigned_employee_id is null));

alter table public.smart_tasks
  drop constraint if exists smart_tasks_private_is_personal_check;
alter table public.smart_tasks
  add constraint smart_tasks_private_is_personal_check
  check (
    visibility <> 'private'
    or (assigned_to is null and assigned_employee_id is null and linked_job_id is null)
  );

-- La cuenta por la que hoy le llega el trabajo a un trabajador activo: su
-- usuario ERP con perfil activo en el tenant; si no, su cuenta activa del
-- portal; si no, ninguna. Misma precedencia que el directorio de asignación.
create or replace function public.smart_task_employee_principal_v1(
  p_tenant_id uuid,
  p_employee_id uuid
)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $fn$
  select coalesce(
    (
      select profile.user_id
      from public.employees employee
      join public.user_profiles profile
        on profile.tenant_id = employee.tenant_id
       and profile.is_active is true
       and (
         profile.employee_id = employee.id
         or (employee.user_id is not null and profile.user_id = employee.user_id)
       )
      where employee.id = p_employee_id
        and employee.tenant_id = p_tenant_id
        and employee.status = 'active'
      order by (profile.employee_id = employee.id) desc, profile.created_at
      limit 1
    ),
    (
      select portal.auth_user_id
      from public.employee_portal_accounts portal
      join public.employees employee
        on employee.id = portal.employee_id
       and employee.tenant_id = portal.tenant_id
       and employee.status = 'active'
      where portal.employee_id = p_employee_id
        and portal.tenant_id = p_tenant_id
        and portal.is_active is true
        and portal.auth_user_id is not null
      limit 1
    )
  );
$fn$;

-- El trabajador activo detrás de una cuenta, o null si la cuenta no es de un
-- trabajador (un dueño sin ficha de empleado, por ejemplo).
create or replace function public.smart_task_user_employee_v1(
  p_tenant_id uuid,
  p_user_id uuid
)
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $fn$
  select coalesce(
    (
      select employee.id
      from public.employees employee
      where employee.tenant_id = p_tenant_id
        and employee.user_id = p_user_id
        and employee.status = 'active'
      limit 1
    ),
    (
      select profile.employee_id
      from public.user_profiles profile
      join public.employees employee
        on employee.id = profile.employee_id
       and employee.tenant_id = profile.tenant_id
       and employee.status = 'active'
      where profile.tenant_id = p_tenant_id
        and profile.user_id = p_user_id
        and profile.is_active is true
      limit 1
    ),
    (
      select portal.employee_id
      from public.employee_portal_accounts portal
      join public.employees employee
        on employee.id = portal.employee_id
       and employee.tenant_id = portal.tenant_id
       and employee.status = 'active'
      where portal.tenant_id = p_tenant_id
        and portal.auth_user_id = p_user_id
        and portal.is_active is true
      limit 1
    )
  );
$fn$;

-- El trabajador detrás de una cuenta, con su fila tomada. Asignar por cuenta
-- (el asistente, los clientes legados) sigue el mismo orden que asignar por
-- trabajador: primero el trabajador, después la tarea. Se relee después de
-- tomarlo, porque una desvinculación que terminó mientras se esperaba ya se
-- ve; si mientras tanto la cuenta pasó a otro trabajador, se toma ése.
create or replace function public.smart_task_lock_user_employee_v1(
  p_tenant_id uuid,
  p_user_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $fn$
declare
  v_locked uuid;
  v_current uuid := public.smart_task_user_employee_v1(p_tenant_id, p_user_id);
begin
  for attempt in 1..3 loop
    exit when v_current is null or v_current is not distinct from v_locked;
    perform 1 from public.employees employee
     where employee.id = v_current
       and employee.tenant_id = p_tenant_id
     for share;
    v_locked := v_current;
    v_current := public.smart_task_user_employee_v1(p_tenant_id, p_user_id);
  end loop;
  return v_current;
end;
$fn$;

revoke all on function public.smart_task_employee_principal_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.smart_task_lock_user_employee_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.smart_task_user_employee_v1(uuid, uuid)
  from public, anon, authenticated;

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

  perform set_config('vinabike.smart_task_cmd', '', true);

  v_result := jsonb_build_object('task', public.smart_task_row_to_json(v_task));
  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'task_create', p_idempotency_key, v_fingerprint,
    v_task.id, v_result
  );
  return v_result;
end;
$function$;

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

    else
      raise exception 'smart_tasks: unknown command %', p_command
        using errcode = '22023', hint = 'unknown_command';
  end case;

  perform set_config('vinabike.smart_task_cmd', '', true);
  return public.smart_task_row_to_json(v_task);
end;
$function$;

CREATE OR REPLACE FUNCTION public.smart_tasks_audit_direct_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
  if new.assigned_to is not null or new.assigned_employee_id is not null then
    insert into public.smart_task_events (
      tenant_id, task_id, actor_user_id, event_type, task_version, payload
    ) values (
      new.tenant_id, new.id, coalesce(auth.uid(), new.created_by), 'assigned',
      new.version,
      jsonb_strip_nulls(jsonb_build_object(
        'source', 'direct',
        'assigned_to', new.assigned_to,
        'assigned_employee_id', new.assigned_employee_id
      ))
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.smart_tasks_audit_direct_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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

  if new.assigned_to is distinct from old.assigned_to
    or new.assigned_employee_id is distinct from old.assigned_employee_id then
    insert into public.smart_task_events (
      tenant_id, task_id, actor_user_id, event_type, task_version, payload
    ) values (
      new.tenant_id, new.id, v_actor,
      case
        when new.assigned_to is null and new.assigned_employee_id is null
          then 'unassigned'
        else 'assigned'
      end,
      new.version,
      jsonb_strip_nulls(jsonb_build_object(
        'source', 'direct',
        'assigned_to', new.assigned_to,
        'assigned_employee_id', new.assigned_employee_id,
        'previous_assignee', old.assigned_to,
        'previous_employee_id', old.assigned_employee_id
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
$function$;

-- Sincronización: la cuenta de las tareas abiertas de un trabajador sigue a
-- su cuenta vigente (ver encabezado).
drop trigger if exists trg_employees_smart_task_inherit on public.employees;
drop trigger if exists trg_portal_accounts_smart_task_inherit
  on public.employee_portal_accounts;
drop trigger if exists trg_user_profiles_smart_task_inherit on public.user_profiles;
drop function if exists public.smart_task_inherit_on_employee_access();
drop function if exists public.smart_task_inherit_employee_tasks_v1(uuid, uuid);

create or replace function public.smart_task_sync_employee_account_v1(
  p_tenant_id uuid,
  p_employee_id uuid
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $fn$
declare
  v_principal uuid;
  v_previous uuid;
  v_previous_command text := current_setting('vinabike.smart_task_cmd', true);
  v_task public.smart_tasks%rowtype;
  v_count integer := 0;
begin
  if p_tenant_id is null or p_employee_id is null then
    return 0;
  end if;

  -- Trabajador primero, tareas después: el mismo orden que crear y asignar.
  perform 1 from public.employees employee
   where employee.id = p_employee_id
     and employee.tenant_id = p_tenant_id
   for update;
  if not found then
    return 0;
  end if;

  v_principal := public.smart_task_employee_principal_v1(p_tenant_id, p_employee_id);

  perform set_config('vinabike.smart_task_cmd', 'employee_access_sync', true);

  for v_task in
    select task.*
      from public.smart_tasks task
     where task.tenant_id = p_tenant_id
       and task.assigned_employee_id = p_employee_id
       and task.status in ('pending', 'in_progress', 'blocked')
       and task.assigned_to is distinct from v_principal
     order by task.id
     for update
  loop
    v_previous := v_task.assigned_to;
    -- Sin capturar errores: si una tarea no puede seguir a la cuenta del
    -- trabajador, el cambio de acceso completo se deshace en vez de dejar la
    -- tarea llegando a una cuenta que ya no es suya. La cuenta vigente es
    -- elegible por construcción, así que eso no debería pasar nunca.
    update public.smart_tasks task
       set assigned_to = v_principal,
           updated_at = now()
     where task.id = v_task.id
       and task.tenant_id = p_tenant_id
    returning task.* into v_task;
    v_count := v_count + 1;

    -- El aviso vivo de «Tarea asignada» de la cuenta que se fue ya no es
    -- verdad. Si hay cuenta nueva, el evento de abajo lo re-dirige a ella.
    if v_principal is null and v_previous is not null then
      delete from public.erp_notifications notification
       where notification.tenant_id = p_tenant_id
         and notification.entity_type = 'smart_task'
         and notification.entity_id = v_task.id
         and notification.type = 'smart_task_assigned'
         and notification.recipient_user_id = v_previous;
    end if;

    -- Le llega a una cuenta: se avisa a nombre de quien la asignó. Deja de
    -- llegarle (perdió la cuenta): no es «quedó sin responsable» —sigue a su
    -- nombre—, así que se registra sin aviso.
    perform public.smart_task_append_event(
      v_task,
      coalesce(v_task.assigned_by, v_task.created_by),
      case when v_principal is null then 'details_updated' else 'assigned' end,
      jsonb_strip_nulls(jsonb_build_object(
        'source', 'employee_access_sync',
        'fields', case when v_principal is null then jsonb_build_array('assigned_to') end,
        'assigned_to', v_principal,
        'assigned_employee_id', p_employee_id,
        'previous_assignee', v_previous
      ))
    );
    perform public.smart_task_thread_sync_participants(v_task, v_principal, v_previous);
  end loop;

  perform set_config('vinabike.smart_task_cmd', coalesce(v_previous_command, ''), true);
  return v_count;
end;
$fn$;

revoke all on function public.smart_task_sync_employee_account_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.smart_task_sync_on_employee_access()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $fn$
begin
  if tg_table_name = 'employees' then
    perform public.smart_task_sync_employee_account_v1(new.tenant_id, new.id);
  elsif tg_table_name = 'employee_portal_accounts' then
    perform public.smart_task_sync_employee_account_v1(new.tenant_id, new.employee_id);
    if tg_op = 'UPDATE' and old.employee_id is distinct from new.employee_id then
      perform public.smart_task_sync_employee_account_v1(old.tenant_id, old.employee_id);
    end if;
  elsif tg_table_name = 'user_profiles' then
    if new.employee_id is not null then
      perform public.smart_task_sync_employee_account_v1(new.tenant_id, new.employee_id);
    end if;
    if tg_op = 'UPDATE'
      and old.employee_id is not null
      and old.employee_id is distinct from new.employee_id then
      perform public.smart_task_sync_employee_account_v1(old.tenant_id, old.employee_id);
    end if;
  end if;
  return null;
end;
$fn$;

revoke all on function public.smart_task_sync_on_employee_access()
  from public, anon, authenticated;

-- Diferidos: corren al confirmar la transacción que cambió el acceso, con el
-- estado final a la vista.
drop trigger if exists trg_employees_smart_task_account_sync on public.employees;
create constraint trigger trg_employees_smart_task_account_sync
  after update of user_id, status on public.employees
  deferrable initially deferred
  for each row execute function public.smart_task_sync_on_employee_access();

drop trigger if exists trg_portal_accounts_smart_task_account_sync
  on public.employee_portal_accounts;
create constraint trigger trg_portal_accounts_smart_task_account_sync
  after insert or update of is_active, auth_user_id, employee_id
  on public.employee_portal_accounts
  deferrable initially deferred
  for each row execute function public.smart_task_sync_on_employee_access();

drop trigger if exists trg_user_profiles_smart_task_account_sync on public.user_profiles;
create constraint trigger trg_user_profiles_smart_task_account_sync
  after insert or update of is_active, employee_id on public.user_profiles
  deferrable initially deferred
  for each row execute function public.smart_task_sync_on_employee_access();

-- Las tareas ya asignadas a la cuenta de un trabajador quedan también a su
-- nombre. No cambia a quién le llega nada: el guard conserva la cuenta que ya
-- es del trabajador, la fecha, el autor y el acuse de la asignación, y la
-- versión que tiene el cliente. Sin evento, porque no pasó nada que avisar.
do $do$
begin
  perform set_config('vinabike.smart_task_cmd', 'employee_backfill', true);
  update public.smart_tasks task
     set assigned_employee_id = public.smart_task_user_employee_v1(
       task.tenant_id, task.assigned_to)
   where task.assigned_to is not null
     and task.assigned_employee_id is null
     and public.smart_task_user_employee_v1(task.tenant_id, task.assigned_to) is not null;
  perform set_config('vinabike.smart_task_cmd', '', true);
end;
$do$;
