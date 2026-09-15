begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- Forward behavior:
--   * every task/service link keeps the operative instructions that the
--     manager saw when assigning the task;
--   * existing live links are backfilled from mechanic_job_items.notes;
--   * later edits to those notes mark the snapshot as changed instead of
--     silently rewriting the assignment;
--   * the Worker projection receives the same safe, price-free instructions.
--
-- Recovery behavior:
--   the column is additive and nullable. Older clients ignore it. Replacing
--   the three functions with their previous definitions disables new writes
--   without deleting any captured evidence.
--
-- Lock/backfill scope:
--   ALTER TABLE takes a brief metadata lock. The bounded UPDATE touches only
--   existing smart_task_job_items rows and is replay-safe.

alter table public.smart_task_job_items
  add column if not exists item_instructions text;

-- The table remains protected by the transaction's DDL lock while the old
-- trigger is absent. Dropping it here makes a retry able to finish a partial
-- backfill even when the stricter immutable-snapshot guard is already live.
drop trigger if exists trg_smart_task_job_items_guard
  on public.smart_task_job_items;

update public.smart_task_job_items link
   set item_instructions = nullif(btrim(item.notes), '')
  from public.mechanic_job_items item
 where item.id = link.job_item_id
   and item.job_id = link.job_id
   and item.tenant_id = link.tenant_id
   and link.item_instructions is null
   and nullif(btrim(item.notes), '') is not null;

-- This historical fallback could reach the UI when a malformed service had
-- no usable label. Keep the internal identifiers, but never publish that old
-- terminology to an operator.
update public.smart_task_job_items
   set item_name = 'Servicio del trabajo'
 where item_name = convert_from(decode('w43DrXRlbSBkZSBwZWdh', 'base64'), 'UTF8');

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
  return new;
end;
$$;

create trigger trg_smart_task_job_items_guard
  before insert or update on public.smart_task_job_items
  for each row execute function public.smart_task_job_items_guard();

create or replace function public.smart_task_job_items_mark_context_changed()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  if new.product_name is distinct from old.product_name
    or new.description is distinct from old.description
    or new.notes is distinct from old.notes
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
    coalesce((
      select jsonb_agg(distinct link.bike_label)
      from public.smart_task_job_items link
      where link.task_id = task.id
        and link.bike_label is not null
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'item_name', link.item_name,
        'item_instructions', link.item_instructions,
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

grant execute on function public.get_my_worker_tasks_v1() to authenticated;
revoke execute on function public.get_my_worker_tasks_v1() from anon, public;

commit;
