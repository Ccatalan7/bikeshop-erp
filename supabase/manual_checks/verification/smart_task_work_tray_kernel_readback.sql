-- Read-back del kernel de bandeja de tareas (20260826220000).
-- Cada aserción divide por cero si el invariante desplegado no está.

-- Las cuatro tablas nuevas existen.
select 1 / (case when to_regclass('public.smart_task_events') is not null
  then 1 else 0 end) as events_table_present;
select 1 / (case when to_regclass('public.smart_task_job_items') is not null
  then 1 else 0 end) as job_items_table_present;
select 1 / (case when to_regclass('public.smart_task_user_state') is not null
  then 1 else 0 end) as user_state_table_present;
select 1 / (case when to_regclass('public.smart_task_command_receipts') is not null
  then 1 else 0 end) as receipts_table_present;

-- El ledger impide el hard-delete de tareas con historia, y el DELETE de
-- cliente está revocado: la bandeja cancela, no borra.
select 1 / (case when exists (
  select 1 from pg_constraint
  where conrelid = 'public.smart_task_events'::regclass
    and contype = 'f'
    and confrelid = 'public.smart_tasks'::regclass
    and confdeltype = 'r'
) then 1 else 0 end) as ledger_blocks_hard_delete;
select 1 / (case when not has_table_privilege(
  'authenticated', 'public.smart_tasks', 'DELETE')
  then 1 else 0 end) as client_delete_revoked;

-- La evidencia del vínculo es invalidable, no borrable: sin FK CASCADE a la
-- línea, con marcas de invalidación y triggers en mechanic_job_items.
select 1 / (case when count(*) = 2 then 1 else 0 end) as link_evidence_columns
from information_schema.columns
where table_schema = 'public' and table_name = 'smart_task_job_items'
  and column_name in ('invalidated_at', 'context_changed_at');
select 1 / (case when count(*) = 0 then 1 else 0 end) as link_has_no_item_cascade
from pg_constraint
where conrelid = 'public.smart_task_job_items'::regclass
  and contype = 'f'
  and confrelid = 'public.mechanic_job_items'::regclass;
select 1 / (case when count(*) = 2 then 1 else 0 end) as link_marking_triggers
from pg_trigger
where tgrelid = 'public.mechanic_job_items'::regclass
  and tgname in ('trg_smart_task_link_invalidate',
                 'trg_smart_task_link_context_changed');

-- El claim idempotente serializa concurrentes.
select 1 / (case when position('pg_advisory_xact_lock' in pg_get_functiondef(
  'public.smart_task_claim_receipt(uuid,uuid,text,text,text)'::regprocedure
)) > 0 then 1 else 0 end) as idempotency_claim_serialized;

-- El hilo por tarea es único a nivel de base y server-owned.
select 1 / (case when exists (
  select 1 from pg_indexes
  where schemaname = 'public'
    and indexname = 'uq_conversation_contexts_task_thread'
) then 1 else 0 end) as task_thread_unique;
select 1 / (case when has_function_privilege(
  'authenticated', 'public.smart_task_thread_get_or_create_v1(uuid)', 'EXECUTE')
  then 1 else 0 end) as thread_get_or_create_present;

-- La ruta directa legada queda auditada.
select 1 / (case when count(*) = 1 then 1 else 0 end) as direct_write_audited
from pg_trigger
where tgrelid = 'public.smart_tasks'::regclass
  and tgname = 'trg_smart_tasks_audit_direct_write';

-- La bandeja tiene ciclo de vida, visibilidad y versión.
select 1 / (case when count(*) = 5 then 1 else 0 end) as tray_columns_present
from information_schema.columns
where table_schema = 'public' and table_name = 'smart_tasks'
  and column_name in ('task_kind', 'visibility', 'version',
                      'acknowledged_at', 'blocked_reason');

-- La RLS tenant-wide fue reemplazada por autoridad real.
select 1 / (case when count(*) = 0 then 1 else 0 end) as legacy_policies_gone
from pg_policies
where tablename = 'smart_tasks'
  and policyname like 'Users can%';
select 1 / (case when count(*) = 3 then 1 else 0 end) as authority_policies_present
from pg_policies
where tablename = 'smart_tasks'
  and policyname in ('smart_tasks_select', 'smart_tasks_insert',
                     'smart_tasks_update');
select 1 / (case when count(*) = 0 then 1 else 0 end) as no_delete_policy
from pg_policies
where tablename = 'smart_tasks' and cmd = 'DELETE';
select 1 / (case when qual like '%visibility%' then 1 else 0 end)
  as private_visibility_enforced
from pg_policies
where tablename = 'smart_tasks' and policyname = 'smart_tasks_select';

-- El guard de transiciones y elegibilidad vive en la base.
select 1 / (case when count(*) = 1 then 1 else 0 end) as guard_trigger_present
from pg_trigger
where tgrelid = 'public.smart_tasks'::regclass
  and tgname = 'trg_smart_tasks_guard_work_tray';
select 1 / (case when count(*) = 1 then 1 else 0 end) as updated_at_deduplicated
from pg_trigger
where tgrelid = 'public.smart_tasks'::regclass
  and not tgisinternal
  and tgfoid = 'public.set_updated_at()'::regprocedure;

-- Los comandos idempotentes existen y solo para autenticados.
select 1 / (case when has_function_privilege(
  'authenticated', 'public.smart_task_create_v1(jsonb,text)', 'EXECUTE')
  and not has_function_privilege(
    'anon', 'public.smart_task_create_v1(jsonb,text)', 'EXECUTE')
  then 1 else 0 end) as create_rpc_acl;
select 1 / (case when has_function_privilege(
  'authenticated', 'public.smart_task_can_view_v1(uuid)', 'EXECUTE')
  and not has_function_privilege(
    'anon', 'public.smart_task_can_view_v1(uuid)', 'EXECUTE')
  and not has_function_privilege(
    'service_role', 'public.smart_task_can_view_v1(uuid)', 'EXECUTE')
  then 1 else 0 end) as visibility_helper_acl;
select 1 / (case when has_function_privilege(
  'authenticated', 'public.smart_task_command_v1(uuid,integer,text,jsonb,text)', 'EXECUTE')
  then 1 else 0 end) as command_rpc_present;
select 1 / (case when has_function_privilege(
  'authenticated', 'public.get_my_worker_tasks_v1()', 'EXECUTE')
  and has_function_privilege(
    'authenticated', 'public.worker_task_command_v1(uuid,integer,text,jsonb,text)', 'EXECUTE')
  then 1 else 0 end) as worker_portal_rpcs_present;
select 1 / (case when position('assigner_name' in pg_get_functiondef(
  'public.get_my_worker_tasks_v1()'::regprocedure)) > 0
  and position('erp_actor_display_name(task.assigned_by'
    in pg_get_functiondef('public.get_my_worker_tasks_v1()'::regprocedure)) > 0
  then 1 else 0 end) as worker_projection_names_assigner;
select 1 / (case when has_function_privilege(
  'authenticated', 'public.get_smart_task_assignment_directory_v1()', 'EXECUTE')
  then 1 else 0 end) as assignment_directory_present;

-- El ledger es append-only para clientes.
select 1 / (case when not has_table_privilege(
  'authenticated', 'public.smart_task_events', 'INSERT')
  and not has_table_privilege(
    'authenticated', 'public.smart_task_events', 'UPDATE')
  and not has_table_privilege(
    'authenticated', 'public.smart_task_events', 'DELETE')
  then 1 else 0 end) as events_append_only;
select 1 / (case when not has_table_privilege(
  'authenticated', 'public.smart_task_command_receipts', 'SELECT')
  then 1 else 0 end) as receipts_hidden;

-- Notificaciones dirigidas sin romper el broadcast legado.
select 1 / (case when count(*) = 1 then 1 else 0 end) as recipient_column_present
from information_schema.columns
where table_schema = 'public' and table_name = 'erp_notifications'
  and column_name = 'recipient_user_id';
select 1 / (case when qual like '%recipient_user_id%' then 1 else 0 end)
  as notification_select_targeted
from pg_policies
where tablename = 'erp_notifications' and policyname = 'erp_notifications_select';
select 1 / (case when
  not has_table_privilege(
    'authenticated', 'public.erp_notifications', 'UPDATE')
  and has_column_privilege(
    'authenticated', 'public.erp_notifications', 'read_at', 'UPDATE')
  and not has_column_privilege(
    'authenticated', 'public.erp_notifications', 'recipient_user_id', 'UPDATE')
  then 1 else 0 end) as notification_client_updates_read_only;
select 1 / (case when count(*) = 1 then 1 else 0 end) as task_notification_trigger
from pg_trigger
where tgrelid = 'public.smart_task_events'::regclass
  and tgname = 'trg_smart_task_erp_notification';

-- Mensajería conoce el contexto 'task'.
select 1 / (case when pg_get_constraintdef(oid) like '%task%' then 1 else 0 end)
  as conversation_context_accepts_task
from pg_constraint
where conname = 'conversation_contexts_context_type_check';
select 1 / (case when pg_get_functiondef(
  'public.messaging_context_belongs_to_tenant(text,uuid,uuid)'::regprocedure
) like '%''task''%' then 1 else 0 end) as context_membership_knows_task;

-- Realtime: el checklist técnico dejó de estar fuera de la publicación y los
-- eventos de la bandeja se publican.
select 1 / (case when count(*) = 2 then 1 else 0 end) as realtime_publication_fixed
from pg_publication_tables
where pubname = 'supabase_realtime'
  and tablename in ('mechanic_job_tasks', 'smart_task_events');

-- (4) Contratos nuevos, explícitos.
select 1 / (case when exists (
  select 1 from pg_constraint
  where conname = 'smart_tasks_private_is_personal_check'
    and conrelid = 'public.smart_tasks'::regclass
    and convalidated
) then 1 else 0 end) as private_is_personal_constraint;
select 1 / (case when position('note_has_no_lifecycle' in pg_get_functiondef(
  'public.smart_tasks_guard_work_tray()'::regprocedure
)) > 0 then 1 else 0 end) as note_lifecycle_guarded;
select 1 / (case when position('note_has_no_lifecycle' in pg_get_functiondef(
  to_regprocedure(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'
  )
)) > 0 then 1 else 0 end) as note_lifecycle_guarded_in_commands;
select 1 / (case when
  position('new.assigned_by := coalesce(v_actor, new.created_by)'
    in pg_get_functiondef(
      'public.smart_tasks_guard_work_tray()'::regprocedure)) > 0
  and position('new.acknowledged_at := old.acknowledged_at'
    in pg_get_functiondef(
      'public.smart_tasks_guard_work_tray()'::regprocedure)) > 0
  and position('job_not_linkable'
    in pg_get_functiondef(
      'public.smart_tasks_guard_work_tray()'::regprocedure)) > 0
  then 1 else 0 end) as direct_writes_cannot_forge_evidence;
select 1 / (case when
  to_regprocedure('public.smart_task_lock_job_items(uuid,uuid[])') is not null
  and position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.smart_task_lock_job_items(uuid,uuid[])'::regprocedure)) > 0
  and position('smart_task_job_items_tenant' in pg_get_functiondef(
    'public.smart_task_lock_job_items(uuid,uuid[])'::regprocedure)) > 0
  and position('smart_task_lock_job_items' in pg_get_functiondef(
    'public.smart_task_create_v1(jsonb,text)'::regprocedure)) > 0
  and position('smart_task_lock_job_items' in pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure))
      < position('select * into v_task' in pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure))
  and not has_function_privilege('authenticated',
    'public.smart_task_lock_job_items(uuid,uuid[])', 'EXECUTE')
  then 1 else 0 end) as service_overlap_decision_serialized_before_task_rows;
select 1 / (case when position(
  'select v_existing, v_actor, v_tenant'
  in pg_get_functiondef(
    'public.smart_task_thread_get_or_create_v1(uuid)'::regprocedure)) > 0
  then 1 else 0 end) as thread_race_loser_joins_winner;
select 1 / (case
  when to_regprocedure('public.smart_task_assignee_eligible_v1(uuid,uuid)')
      is not null
    and not has_function_privilege('authenticated',
      'public.smart_task_assignee_eligible_v1(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon',
      'public.smart_task_assignee_eligible_v1(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('service_role',
      'public.smart_task_assignee_eligible_v1(uuid,uuid)', 'EXECUTE')
    -- PUBLIC es el grantee 0 de la ACL real (con proacl null, el default
    -- concede EXECUTE a PUBLIC: eso también debe contar como violación).
    and not exists (
      select 1
      from pg_proc proc,
        aclexplode(coalesce(proc.proacl,
          acldefault('f', proc.proowner))) acl_entry
      where proc.oid =
          to_regprocedure('public.smart_task_assignee_eligible_v1(uuid,uuid)')
        and acl_entry.grantee = 0
        and acl_entry.privilege_type = 'EXECUTE'
    )
  then 1 else 0 end) as eligible_helper_internal_only;
select 1 / (case
  when to_regprocedure('public.smart_task_assignee_worker_linked_v1(uuid,uuid)')
      is not null
    and not has_function_privilege('authenticated',
      'public.smart_task_assignee_worker_linked_v1(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('anon',
      'public.smart_task_assignee_worker_linked_v1(uuid,uuid)', 'EXECUTE')
    and not has_function_privilege('service_role',
      'public.smart_task_assignee_worker_linked_v1(uuid,uuid)', 'EXECUTE')
    and not exists (
      select 1
      from pg_proc proc,
        aclexplode(coalesce(proc.proacl,
          acldefault('f', proc.proowner))) acl_entry
      where proc.oid = to_regprocedure(
          'public.smart_task_assignee_worker_linked_v1(uuid,uuid)')
        and acl_entry.grantee = 0
        and acl_entry.privilege_type = 'EXECUTE'
    )
  then 1 else 0 end) as worker_linked_helper_internal_only;

-- Los datos legados siguen ahí, y los invariantes de DATOS son DURABLES:
-- siguen siendo verdad con notas, privadas y completaciones legítimas
-- posteriores al release (los garantizan CHECK + guard, no la foto del día).
select 1 / (case when count(*) >= 72 then 1 else 0 end) as legacy_rows_preserved
from public.smart_tasks;
select 1 / (case when count(*) = 0 then 1 else 0 end) as version_discipline_holds
from public.smart_tasks
where version < 1;
select 1 / (case when count(*) = 0 then 1 else 0 end) as private_rows_are_personal
from public.smart_tasks
where visibility = 'private'
  and (assigned_to is not null or linked_job_id is not null);
select 1 / (case when count(*) = 0 then 1 else 0 end) as notes_outside_note_domain
from public.smart_tasks
where task_kind = 'note'
  and (status not in ('pending', 'cancelled') or assigned_to is not null);
select 1 / (case when count(*) = 0 then 1 else 0 end) as completion_stamp_coherent
from public.smart_tasks
where completed_at is not null and status <> 'completed';
select 1 / (case when count(*) = 0 then 1 else 0 end) as blocked_reason_coherent
from public.smart_tasks
where blocked_reason is not null and status <> 'blocked';

-- (2) Una función se prueba EJECUTÁNDOLA: identidad real de un miembro
-- activo del tenant (con UN solo perfil activo, elegido determinista), rol
-- authenticated, solo lectura. Si no existe tal miembro, el verify falla
-- aquí — eso también es señal.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', pick.user_id, 'role', 'authenticated')::text,
  true
)
from (
  select profile.user_id
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id and tenant.is_active is true
  where profile.is_active is true
    and not exists (
      select 1 from public.user_profiles other
      where other.user_id = profile.user_id
        and other.is_active is true
        and other.id <> profile.id
    )
  order by profile.user_id
  limit 1
) pick;
select set_config('request.jwt.claim.sub', pick.user_id::text, true)
from (
  select profile.user_id
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id and tenant.is_active is true
  where profile.is_active is true
    and not exists (
      select 1 from public.user_profiles other
      where other.user_id = profile.user_id
        and other.is_active is true
        and other.id <> profile.id
    )
  order by profile.user_id
  limit 1
) pick;
-- Mismo camino que PostgREST: el rol también viaja por set_config y las
-- llamadas autenticadas quedan al final del verify.
select set_config('role', 'authenticated', true);

select 1 / (case when (
  select count(*) from public.get_smart_task_assignment_directory_v1()
) >= 1 then 1 else 0 end) as directory_executes_for_real_member;
select 1 / (case when (
  select count(*) - count(distinct coalesce(entry.employee_id::text,
                                            entry.user_id::text))
  from public.get_smart_task_assignment_directory_v1() entry
) = 0 then 1 else 0 end) as directory_one_principal_per_person;
select 1 / (case when (
  select bool_and(entry.access in ('erp', 'portal', 'none'))
  from public.get_smart_task_assignment_directory_v1() entry
) then 1 else 0 end) as directory_access_domain_valid;
-- Ejecuta smart_task_thread_v1 con la misma identidad: una tarea inexistente
-- responde null (forma correcta) sin mutar nada.
select 1 / (case when public.smart_task_thread_v1(
  '00000000-0000-4000-8000-000000000000'::uuid
) is null then 1 else 0 end) as thread_executes_and_unknown_is_null;
