-- Read-back de 20260927010000_smart_task_service_notes.
-- Antes de desplegar tiene que fallar contra producción: la tabla no existe.

-- Cada nota de servicio es una fila, con autor, corrección y retiro.
select 1 / (case when count(*) = 11 then 1 else 0 end) as tabla_de_notas
from information_schema.columns
where table_schema = 'public'
  and table_name = 'smart_task_job_item_notes'
  and column_name in (
    'id', 'tenant_id', 'task_id', 'job_item_id', 'body', 'created_at',
    'created_by', 'edited_at', 'edited_by', 'withdrawn_at', 'withdrawn_by'
  );

-- Se lee con RLS y se escribe sólo por comando.
select 1 / (case when
  (select relrowsecurity from pg_class
    where oid = 'public.smart_task_job_item_notes'::regclass)
  and exists (select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'smart_task_job_item_notes'
      and policyname = 'smart_task_job_item_notes_select')
  and has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'DELETE')
  and not has_table_privilege('anon', 'public.smart_task_job_item_notes', 'SELECT')
then 1 else 0 end) as lectura_con_rls_escritura_por_comando;

select 1 / (case when count(*) = 1 then 1 else 0 end) as guard_de_notas
from pg_trigger
where tgrelid = 'public.smart_task_job_item_notes'::regclass
  and tgname = 'trg_smart_task_job_item_notes_guard'
  and not tgisinternal;

select 1 / (case when count(*) = 3 then 1 else 0 end) as formas_validadas
from pg_constraint
where conname in (
  'smart_task_job_item_notes_body_check',
  'smart_task_job_item_notes_edited_by_needs_edited_at',
  'smart_task_job_item_notes_withdrawn_by_needs_withdrawn_at'
);

-- El ledger acepta los tres eventos nuevos.
select 1 / (case when
  pg_get_constraintdef(oid) like '%job_item_note_added%'
  and pg_get_constraintdef(oid) like '%job_item_note_edited%'
  and pg_get_constraintdef(oid) like '%job_item_note_withdrawn%'
then 1 else 0 end) as eventos_nuevos
from pg_constraint
where conname = 'smart_task_events_event_type_check';

-- Los comandos existen en el núcleo y en las dos superficies, y crear acepta
-- la primera nota de cada servicio.
select 1 / (case when
  pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure)
    like '%when ''add_job_item_note'' then%'
  and pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure)
    like '%when ''edit_job_item_note'', ''withdraw_job_item_note'' then%'
  and pg_get_functiondef(
    'public.smart_task_command_v1(uuid,integer,text,jsonb,text)'::regprocedure)
    like '%''add_job_item_note'', ''edit_job_item_note'', ''withdraw_job_item_note''%'
  and pg_get_functiondef(
    'public.worker_task_command_v1(uuid,integer,text,jsonb,text)'::regprocedure)
    like '%''add_job_item_note'', ''edit_job_item_note'', ''withdraw_job_item_note''%'
  and pg_get_functiondef('public.smart_task_create_v1(jsonb,text)'::regprocedure)
    like '%job_item_notes%'
then 1 else 0 end) as comandos_en_erp_y_portal;

-- El aviso de una nota nueva, su corrección y su retiro.
select 1 / (case when
  pg_get_functiondef('public.create_smart_task_erp_notification()'::regprocedure)
    like '%smart_task_service_note%'
  and pg_get_functiondef('public.create_smart_task_erp_notification()'::regprocedure)
    like '%job_item_note_withdrawn%'
then 1 else 0 end) as aviso_de_nota;

-- El portal recibe la vigente; ERP y portal leen la línea de tiempo.
select 1 / (case when
  pg_get_functiondef('public.get_my_worker_tasks_v1()'::regprocedure)
    like '%''note_count''%'
  and has_function_privilege('authenticated',
    'public.get_smart_task_service_timeline_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_smart_task_service_timeline_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.get_smart_task_service_notes_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_smart_task_service_notes_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_my_worker_tasks_v1()', 'EXECUTE')
then 1 else 0 end) as vigente_y_linea_de_tiempo;
