-- Production read-back for the service-instruction task snapshot.
-- Diagnostics precede SQL-level assertions so a failure exposes its cause.

select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'smart_task_job_items'
  and column_name = 'item_instructions';

select
  proname,
  md5(pg_get_functiondef(function.oid)) as definition_md5
from pg_proc function
join pg_namespace namespace on namespace.oid = function.pronamespace
where namespace.nspname = 'public'
  and function.proname in (
    'smart_task_job_items_guard',
    'smart_task_job_items_mark_context_changed',
    'get_my_worker_tasks_v1'
  )
order by proname;

select
  trigger.tgname,
  trigger.tgenabled,
  pg_get_triggerdef(trigger.oid) as definition
from pg_trigger trigger
where trigger.tgrelid = 'public.smart_task_job_items'::regclass
  and trigger.tgname = 'trg_smart_task_job_items_guard'
  and not trigger.tgisinternal;

select
  count(*) as total_links,
  count(*) filter (where link.item_instructions is not null)
    as links_with_instructions,
  count(*) filter (where link.context_changed_at is not null)
    as links_with_changed_context
from public.smart_task_job_items link;

select 1 / (case when exists (
  select 1
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'smart_task_job_items'
    and column_name = 'item_instructions'
    and data_type = 'text'
) then 1 else 0 end) as instruction_snapshot_column_exists;

select 1 / (case when
  position('new.item_instructions := nullif(btrim(v_item.notes)' in
    pg_get_functiondef(
      'public.smart_task_job_items_guard()'::regprocedure
    )) > 0
  and position('new.notes is distinct from old.notes' in
    pg_get_functiondef(
      'public.smart_task_job_items_mark_context_changed()'::regprocedure
    )) > 0
  and position('item_instructions' in
    pg_get_functiondef(
      'public.get_my_worker_tasks_v1()'::regprocedure
    )) > 0
then 1 else 0 end) as instructions_flow_is_installed;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger
  where trigger.tgrelid = 'public.smart_task_job_items'::regclass
    and trigger.tgname = 'trg_smart_task_job_items_guard'
    and trigger.tgenabled <> 'D'
    and not trigger.tgisinternal
) then 1 else 0 end) as immutable_snapshot_guard_is_enabled;

select 1 / (case when not exists (
  select 1
  from public.smart_task_job_items link
  join public.mechanic_job_items item
    on item.id = link.job_item_id
   and item.job_id = link.job_id
   and item.tenant_id = link.tenant_id
  where link.context_changed_at is null
    and nullif(btrim(item.notes), '') is distinct from link.item_instructions
) then 1 else 0 end) as unchanged_live_links_match_their_instruction_snapshot;

select 1 / (case when not exists (
  select 1
  from public.smart_task_job_items link
  where link.item_name = convert_from(
    decode('w43DrXRlbSBkZSBwZWdh', 'base64'),
    'UTF8'
  )
) then 1 else 0 end) as old_operator_fallback_is_absent;

select 1 / (case when
  has_function_privilege(
    'authenticated',
    'public.get_my_worker_tasks_v1()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_my_worker_tasks_v1()',
    'EXECUTE'
  )
then 1 else 0 end) as worker_projection_remains_authenticated_only;
