-- Read-back de 20260926230000_smart_task_employee_assignee.
-- Antes de desplegar tiene que fallar contra producción: la columna no existe.

-- La tarea guarda al trabajador, atado a su tenant.
select 1 / count(*)::integer as columna_trabajador
from information_schema.columns
where table_schema = 'public'
  and table_name = 'smart_tasks'
  and column_name = 'assigned_employee_id';

select 1 / count(*)::integer as fk_trabajador_mismo_tenant
from pg_constraint
where conrelid = 'public.smart_tasks'::regclass
  and conname = 'smart_tasks_assigned_employee_tenant_fk'
  and pg_get_constraintdef(oid) like '%(assigned_employee_id, tenant_id)%';

-- Nota y tarea personal no tienen responsable, tampoco por trabajador.
select 1 / (case when count(*) = 2 then 1 else 0 end) as notas_y_personales_sin_trabajador
from pg_constraint
where conrelid = 'public.smart_tasks'::regclass
  and conname in (
    'smart_tasks_note_has_no_assignee_check',
    'smart_tasks_private_is_personal_check'
  )
  and pg_get_constraintdef(oid) like '%assigned_employee_id IS NULL%';

-- Los comandos y el guard conocen al trabajador.
select 1 / (case when
  pg_get_functiondef('public.smart_task_create_v1(jsonb,text)'::regprocedure)
    like '%assigned_employee_id%'
  and pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure)
    like '%v_new_employee%'
  and pg_get_functiondef('public.smart_tasks_guard_work_tray()'::regprocedure)
    like '%employee_access_sync%'
  and pg_get_functiondef('public.smart_tasks_audit_direct_insert()'::regprocedure)
    like '%assigned_employee_id%'
  and pg_get_functiondef('public.smart_tasks_audit_direct_write()'::regprocedure)
    like '%previous_employee_id%'
then 1 else 0 end) as comandos_guard_y_auditoria;

-- La sincronización cuelga de las tres puertas por donde llega o se va una
-- cuenta: en su tabla, habilitada, diferida y con su función.
select 1 / (case when count(*) = 3 then 1 else 0 end) as disparadores_de_sincronizacion
from pg_trigger trigger_row
join pg_proc function_row on function_row.oid = trigger_row.tgfoid
where not trigger_row.tgisinternal
  -- 'O' y 'A' corren en sesiones normales; 'R' (sólo réplica) y 'D' no.
  and trigger_row.tgenabled in ('O', 'A')
  and trigger_row.tgdeferrable
  and trigger_row.tginitdeferred
  and function_row.proname = 'smart_task_sync_on_employee_access'
  and (trigger_row.tgname, trigger_row.tgrelid) in (
    ('trg_employees_smart_task_account_sync', 'public.employees'::regclass),
    ('trg_portal_accounts_smart_task_account_sync', 'public.employee_portal_accounts'::regclass),
    ('trg_user_profiles_smart_task_account_sync', 'public.user_profiles'::regclass)
  );

-- Nadie la llama desde el cliente.
select 1 / (case when
  not has_function_privilege('authenticated',
    'public.smart_task_sync_employee_account_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_sync_employee_account_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.smart_task_employee_principal_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.smart_task_user_employee_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.smart_task_lock_user_employee_v1(uuid,uuid)', 'EXECUTE')
then 1 else 0 end) as funciones_internas;

-- Invariante: toda tarea abierta de un trabajador con cuenta le llega a una
-- cuenta suya (la herencia no dejó ninguna colgando).
select 1 / (case when not exists (
  select 1
  from public.smart_tasks task
  where task.assigned_employee_id is not null
    and task.status in ('pending', 'in_progress', 'blocked')
    and public.smart_task_employee_principal_v1(task.tenant_id, task.assigned_employee_id) is not null
    and (
      task.assigned_to is null
      or public.smart_task_user_employee_v1(task.tenant_id, task.assigned_to)
        is distinct from task.assigned_employee_id
    )
) then 1 else 0 end) as tareas_abiertas_llegan_a_su_cuenta;

-- El relleno escribió al trabajador detrás de cada cuenta que lo tiene.
select 1 / (case when not exists (
  select 1
  from public.smart_tasks task
  where task.assigned_to is not null
    and task.assigned_employee_id is null
    and public.smart_task_user_employee_v1(task.tenant_id, task.assigned_to) is not null
) then 1 else 0 end) as relleno_completo;

-- Toda asignación a un trabajador sin cuenta nace con esta migración, así
-- que tiene su fecha. (Hay 3 asignaciones antiguas por cuenta sin fecha,
-- anteriores al kernel de agosto: el relleno las conserva como están.)
select 1 / (case when not exists (
  select 1
  from public.smart_tasks task
  where task.assigned_employee_id is not null
    and task.assigned_to is null
    and task.assigned_at is null
) then 1 else 0 end) as asignacion_sin_cuenta_con_fecha;

-- Ninguna tarea abierta llega a una cuenta que ya no es de su trabajador.
select 1 / (case when not exists (
  select 1
  from public.smart_tasks task
  where task.assigned_employee_id is not null
    and task.assigned_to is not null
    and task.status in ('pending', 'in_progress', 'blocked')
    and public.smart_task_user_employee_v1(task.tenant_id, task.assigned_to)
      is distinct from task.assigned_employee_id
) then 1 else 0 end) as ninguna_cuenta_ajena;
