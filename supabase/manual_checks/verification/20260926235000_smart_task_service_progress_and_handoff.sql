-- Read-back de 20260926235000_smart_task_service_progress_and_handoff.
-- Antes de desplegar tiene que fallar contra producción: las columnas no existen.

-- El vínculo tarea↔servicio guarda hecho, cuándo y quién.
select 1 / (case when count(*) = 2 then 1 else 0 end) as servicio_hecho_y_quien
from information_schema.columns
where table_schema = 'public'
  and table_name = 'smart_task_job_items'
  and column_name in ('done_at', 'done_by');

-- La tarea guarda la nota del turno con autor y hora.
select 1 / (case when count(*) = 3 then 1 else 0 end) as nota_de_turno
from information_schema.columns
where table_schema = 'public'
  and table_name = 'smart_tasks'
  and column_name in ('handoff_note', 'handoff_note_at', 'handoff_note_by');

select 1 / (case when count(*) = 2 then 1 else 0 end) as formas_validadas
from pg_constraint
where conname in (
  'smart_task_job_items_done_by_needs_done_at',
  'smart_tasks_handoff_note_shape_check'
);

-- El ledger acepta los cuatro eventos nuevos.
select 1 / (case when
  pg_get_constraintdef(oid) like '%job_item_done%'
  and pg_get_constraintdef(oid) like '%job_item_reopened%'
  and pg_get_constraintdef(oid) like '%handoff_note_set%'
  and pg_get_constraintdef(oid) like '%handoff_note_cleared%'
then 1 else 0 end) as eventos_nuevos
from pg_constraint
where conname = 'smart_task_events_event_type_check';

-- Los comandos existen en el núcleo y en las dos superficies.
select 1 / (case when
  pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure)
    like '%when ''set_job_item_done'' then%'
  and pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure)
    like '%when ''set_handoff_note'' then%'
  and pg_get_functiondef(
    'public.smart_task_command_v1(uuid,integer,text,jsonb,text)'::regprocedure)
    like '%''set_job_item_done'', ''set_handoff_note''%'
  and pg_get_functiondef(
    'public.worker_task_command_v1(uuid,integer,text,jsonb,text)'::regprocedure)
    like '%''set_job_item_done'', ''set_handoff_note''%'
then 1 else 0 end) as comandos_en_erp_y_portal;

-- Sólo los comandos escriben: los guards protegen hecho y nota, y re-vincular
-- conserva lo hecho.
select 1 / (case when
  pg_get_functiondef('public.smart_task_job_items_guard()'::regprocedure)
    like '%new.done_at := old.done_at%'
  and pg_get_functiondef('public.smart_tasks_guard_work_tray()'::regprocedure)
    like '%new.handoff_note := old.handoff_note%'
  and pg_get_functiondef(
    'public.smart_task_set_job_items_internal(smart_tasks,uuid,uuid,uuid[])'::regprocedure)
    like '%v_done ? link.job_item_id::text%'
then 1 else 0 end) as guards_y_revincular;

-- La nota avisa, y el nombre de quien actúa desde el portal se resuelve.
select 1 / (case when
  pg_get_functiondef('public.create_smart_task_erp_notification()'::regprocedure)
    like '%smart_task_handoff_note%'
  and pg_get_functiondef('public.erp_actor_display_name(uuid,uuid)'::regprocedure)
    like '%employee_portal_accounts portal%join public.employees employee%'
then 1 else 0 end) as aviso_y_nombre_del_portal;

-- El portal recibe servicios marcables y la nota, con los permisos de antes.
select 1 / (case when
  pg_get_function_result('public.get_my_worker_tasks_v1()'::regprocedure)
    like '%handoff_note_by_name text%'
  and pg_get_functiondef('public.get_my_worker_tasks_v1()'::regprocedure)
    like '%''job_item_id'', link.job_item_id%'
  and has_function_privilege('authenticated', 'public.get_my_worker_tasks_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_my_worker_tasks_v1()', 'EXECUTE')
then 1 else 0 end) as proyeccion_del_portal;

-- Revisión de Codex: los servicios se toman antes que vínculos y tareas,
-- borrar la nota retira su aviso, y los autores nuevos sueltan una cuenta
-- borrada en vez de reponerla.
select 1 / (case when
  pg_get_functiondef('public.smart_task_lock_job_items(uuid,uuid[])'::regprocedure)
    like '%for key share%'
  and pg_get_functiondef('public.create_smart_task_erp_notification()'::regprocedure)
    like '%handoff_note_cleared%'
  and pg_get_functiondef('public.smart_task_job_items_guard()'::regprocedure)
    like '%account.id = old.done_by%'
  and pg_get_functiondef('public.smart_tasks_guard_work_tray()'::regprocedure)
    like '%account.id = old.handoff_note_by%'
then 1 else 0 end) as arreglos_de_la_revision;
