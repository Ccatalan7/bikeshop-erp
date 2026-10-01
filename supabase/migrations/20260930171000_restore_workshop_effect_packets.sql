-- C2: private effect packets for the integrated workshop recovery, 2026-09-30.
-- Prepared, not APPLIED. Deploy together with 20260930170000 (capture) and
-- 20260930172000 (engine) after their local gate and independent review.
--
-- A restored row is history, not a new business event. Every INSERT trigger
-- of the workshop write scope that treats an insert as new (timeline, ERP
-- notification, status/delivery ledger, warranty invoice, invoice sync, bike
-- facts, cost projection, creation-time normalizers and command guards) gets
-- a WHEN hook. The eleven structural validators it does not hook keep running
-- on restored rows (tenant graph, same-task tenant, sale anchor, quotation
-- invoice, explicit task, managed image files, line total).
--
-- Why WHEN instead of a line in each function body (Claude, 2026-09-30):
-- production and local bodies of five of these functions differ today
-- (handle_mechanic_job_items_change, sync_job_items_to_invoice_statement,
-- update_mechanic_job_costs, sync_adhoc_task_to_item,
-- capture_mechanic_job_status_transition). A body hook would have to copy
-- one version over the other. The WHEN hook leaves every function body and
-- its digest untouched and suppresses the trigger regardless of its body.
--
-- Authority: a packet row exists only inside the private writer, for its own
-- backend and transaction, for one relation, and only while that writer's one
-- INSERT statement runs at trigger depth 0. Clients have no privilege on the
-- tables; no GUC is read. Nested statements run at depth >= 1 and never match.
-- Exceptions roll back packets with the business write.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table public.workshop_restore_invocations (
  id uuid primary key,
  transaction_id bigint not null,
  backend_pid integer not null,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  unique (transaction_id, backend_pid)
);
create table public.workshop_restore_effect_packets (
  invocation_id uuid not null
    references public.workshop_restore_invocations(id) on delete cascade,
  relation_oid oid not null,
  trigger_name name not null,
  primary key (invocation_id, relation_oid, trigger_name)
);
alter table public.workshop_restore_invocations enable row level security;
alter table public.workshop_restore_effect_packets enable row level security;
revoke all on table public.workshop_restore_invocations,
  public.workshop_restore_effect_packets from public, anon, authenticated, service_role;

-- The reviewed trigger list. 'hook' triggers are suppressed for restored
-- rows; 'keep' triggers run and must keep their reviewed definition digest.
create function public.workshop_restore_trigger_review_internal()
returns table(table_name text, trigger_name name, review text, function_md5 text)
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  values
    ('bikes', 'trg_bike_image_urls_exist'::name, 'keep', '7b9f72b0bffc104257b4246633789812'),
    ('mechanic_jobs', 'trg_mechanic_job_image_urls_exist', 'keep', '1fa883f8ae930e0017b0a00bd3d54cc1'),
    ('mechanic_jobs', 'trg_mechanic_jobs_tenant_graph', 'keep', '597b9430999c7a4f3df973b97e990ac6'),
    ('mechanic_jobs', 'trg_mechanic_jobs_guard_quotation_invoice', 'keep', '39c6a91c9ee90facf9e323eda516f83a'),
    ('mechanic_jobs', 'trg_mechanic_jobs_guard_sale_anchor', 'keep', '43448a54662cc49273dedb6a98b02cc2'),
    ('mechanic_job_bikes', 'trg_mechanic_job_bikes_tenant_graph', 'keep', '597b9430999c7a4f3df973b97e990ac6'),
    ('mechanic_job_bikes', 'trg_mechanic_job_bikes_guard_sale_anchor', 'keep', '43448a54662cc49273dedb6a98b02cc2'),
    ('mechanic_job_items', 'trg_calculate_mechanic_job_item_total', 'keep', 'bff9deff20822e7821db9df30c418051'),
    ('mechanic_job_items', 'trg_mechanic_job_items_tenant_graph', 'keep', '597b9430999c7a4f3df973b97e990ac6'),
    ('mechanic_job_tasks', 'trg_mechanic_job_task_is_explicit', 'keep', 'be4c6cf39269c2dbebe6cd7d3baebf9d'),
    ('mechanic_job_tasks', 'trg_mechanic_job_task_same_tenant', 'keep', 'b0a4e703e625b20547d4507bcb938e18'),
    ('mechanic_jobs', 'trg_job_status_timestamp', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_job_erp_notification', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_before_insert', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_capture_delivery', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_change', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_covered_warranty_invoice_lifecycle', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_created_by', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_lifecycle_timestamp_guard', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_normalize_mode_axes', 'hook', null),
    ('mechanic_jobs', 'trg_mechanic_jobs_status_transition_ledger', 'hook', null),
    ('mechanic_jobs', 'zzzz_mechanic_jobs_guard_canonical_mode_insert', 'hook', null),
    ('mechanic_job_bikes', 'trg_mechanic_job_bikes_gate_job_lines', 'hook', null),
    ('mechanic_job_bikes', 'trg_mechanic_job_bikes_guard_final_service_budget', 'hook', null),
    ('mechanic_job_bikes', 'trg_mechanic_job_bikes_guard_paid_snapshot', 'hook', null),
    ('mechanic_job_items', 'trg_mechanic_job_items_bike_costs', 'hook', null),
    ('mechanic_job_items', 'trg_mechanic_job_items_change', 'hook', null),
    ('mechanic_job_items', 'trg_mechanic_job_items_guard_final_quotation', 'hook', null),
    ('mechanic_job_items', 'trg_mechanic_job_items_guard_paid_snapshot', 'hook', null),
    ('mechanic_job_items', 'trg_mechanic_job_items_installed_bike_facts_insert', 'hook', null),
    ('mechanic_job_items', 'trg_mechanic_job_items_sync_invoice_insert', 'hook', null),
    ('mechanic_job_items', 'trg_update_job_costs_on_item_insert', 'hook', null),
    ('mechanic_job_mode_events', 'trg_mechanic_job_mode_event_snapshot', 'hook', null),
    ('mechanic_job_tasks', 'trg_sync_adhoc_task_to_item', 'hook', null),
    ('smart_task_events', 'trg_smart_task_erp_notification', 'hook', null),
    ('smart_task_job_item_notes', 'trg_smart_task_job_item_notes_guard', 'hook', null),
    ('smart_task_job_items', 'trg_smart_task_job_items_guard', 'hook', null),
    ('smart_task_user_state', 'trg_smart_task_user_state_guard', 'hook', null),
    ('smart_tasks', 'trg_smart_tasks_audit_direct_insert', 'hook', null),
    ('smart_tasks', 'trg_smart_tasks_guard_primary_context', 'hook', null),
    ('smart_tasks', 'trg_smart_tasks_guard_work_tray', 'hook', null)
$function$;

-- The WHEN hook itself. SECURITY INVOKER and read-only: every role that may
-- write workshop rows (anon, authenticated, service_role, owners) evaluates
-- it. A client role has no privilege on the packet tables and gets false
-- without reading them; only the table owner, i.e. the private engine
-- running as its owner, reaches the query, and only for its own backend and
-- transaction. It never reads a setting and never writes.
create function public.workshop_restore_effect_suppressed(p_relation regclass, p_trigger name)
returns boolean
language plpgsql stable security invoker
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
begin
  if pg_catalog.pg_trigger_depth() <> 0
     or not pg_catalog.has_table_privilege(current_user,
       'public.workshop_restore_effect_packets', 'SELECT') then
    return false;
  end if;
  return exists (
    select 1
      from public.workshop_restore_effect_packets packet
      join public.workshop_restore_invocations invocation
        on invocation.id = packet.invocation_id
     where invocation.transaction_id = pg_catalog.txid_current_if_assigned()
       and invocation.backend_pid = pg_catalog.pg_backend_pid()
       and packet.relation_oid = p_relation
       and packet.trigger_name = p_trigger);
end;
$function$;
revoke all on function public.workshop_restore_effect_suppressed(regclass, name) from public;
grant execute on function public.workshop_restore_effect_suppressed(regclass, name)
  to public;

-- The exact WHEN text of a hooked trigger, as pg_get_triggerdef renders it
-- under this fixed search_path. The engine compares it before suppressing.
create function public.workshop_restore_hook_when_internal(p_table text, p_trigger name)
returns text
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select format(' WHEN ((NOT workshop_restore_effect_suppressed(%L::regclass, %L::name))) ',
    p_table, p_trigger)
$function$;

-- Install the hooks. A trigger that already has a WHEN, is not enabled for
-- origin writes, or is missing stops the deploy; nothing is guessed.
do $hook$
declare
  v_trigger record;
  v_definition text;
  v_hooked integer := 0;
begin
  perform set_config('search_path', 'pg_catalog, public, pg_temp', true);
  for v_trigger in
    select review.table_name, review.trigger_name, t.oid, t.tgqual, t.tgenabled
      from public.workshop_restore_trigger_review_internal() review
      left join pg_class c on c.relname = review.table_name
        and c.relnamespace = 'public'::regnamespace
      left join pg_trigger t on t.tgrelid = c.oid and t.tgname = review.trigger_name
        and not t.tgisinternal
     where review.review = 'hook'
     order by review.table_name, review.trigger_name
  loop
    if v_trigger.oid is null or v_trigger.tgqual is not null
       or v_trigger.tgenabled <> 'O' then
      raise exception 'Workshop restore hook precondition failed on %.%',
        v_trigger.table_name, v_trigger.trigger_name;
    end if;
    v_definition := pg_get_triggerdef(v_trigger.oid);
    if position(' EXECUTE FUNCTION ' in v_definition) = 0 then
      raise exception 'Unexpected trigger definition on %.%',
        v_trigger.table_name, v_trigger.trigger_name;
    end if;
    execute format('drop trigger %I on public.%I', v_trigger.trigger_name, v_trigger.table_name);
    execute regexp_replace(v_definition, ' EXECUTE FUNCTION ',
      format(' WHEN (NOT public.workshop_restore_effect_suppressed(%L::regclass, %L::name)) EXECUTE FUNCTION ',
        'public.' || v_trigger.table_name, v_trigger.trigger_name));
    if position(public.workshop_restore_hook_when_internal(v_trigger.table_name, v_trigger.trigger_name)
                in pg_get_triggerdef((select t.oid from pg_trigger t
                  where t.tgrelid = to_regclass('public.' || v_trigger.table_name)
                    and t.tgname = v_trigger.trigger_name))) = 0 then
      raise exception 'Workshop restore hook did not render as reviewed on %.%',
        v_trigger.table_name, v_trigger.trigger_name;
    end if;
    v_hooked := v_hooked + 1;
  end loop;
  if v_hooked <> 30 then
    raise exception 'Expected 30 hooked workshop triggers, got %', v_hooked;
  end if;
end;
$hook$;

create function public.workshop_restore_open_internal(p_tenant_id uuid)
returns uuid
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare v_id uuid := gen_random_uuid();
begin
  if p_tenant_id is null or pg_trigger_depth() <> 0 then
    raise exception 'Recovery cannot be nested in a business trigger' using errcode = '22023';
  end if;
  insert into public.workshop_restore_invocations(id, transaction_id, backend_pid, tenant_id)
    values (v_id, txid_current(), pg_backend_pid(), p_tenant_id);
  return v_id;
end;
$function$;

-- Open the packets of one relation for the writer's next single statement.
-- Every hooked trigger of that relation must carry the reviewed WHEN hook.
create function public.workshop_restore_suppress_internal(p_invocation_id uuid, p_relation regclass)
returns integer
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_table text;
  v_trigger record;
  v_count integer := 0;
begin
  select c.relname into v_table from pg_class c
   where c.oid = p_relation and c.relnamespace = 'public'::regnamespace;
  if v_table is null or pg_trigger_depth() <> 0
     or not exists (select 1 from public.workshop_restore_invocations i
                     where i.id = p_invocation_id and i.transaction_id = txid_current()
                       and i.backend_pid = pg_backend_pid())
     or exists (select 1 from public.workshop_restore_effect_packets p
                 where p.invocation_id = p_invocation_id) then
    raise exception 'Invalid or unclosed recovery packet' using errcode = '22023';
  end if;
  for v_trigger in
    select review.trigger_name, t.oid
      from public.workshop_restore_trigger_review_internal() review
      left join pg_trigger t on t.tgrelid = p_relation and t.tgname = review.trigger_name
        and not t.tgisinternal and t.tgenabled in ('O', 'A')
     where review.table_name = v_table and review.review = 'hook'
  loop
    if v_trigger.oid is null
       or position(public.workshop_restore_hook_when_internal(v_table, v_trigger.trigger_name)
                   in pg_get_triggerdef(v_trigger.oid)) = 0 then
      raise exception 'Recovery hook is missing on %.%', v_table, v_trigger.trigger_name
        using errcode = '22023';
    end if;
    insert into public.workshop_restore_effect_packets(invocation_id, relation_oid, trigger_name)
      values (p_invocation_id, p_relation, v_trigger.trigger_name);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

create function public.workshop_restore_release_internal(p_invocation_id uuid)
returns integer
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare v_count integer;
begin
  if pg_trigger_depth() <> 0 then
    raise exception 'Recovery packet cannot close inside a trigger' using errcode = '22023';
  end if;
  delete from public.workshop_restore_effect_packets packet
    using public.workshop_restore_invocations invocation
    where packet.invocation_id = invocation.id and invocation.id = p_invocation_id
      and invocation.transaction_id = txid_current()
      and invocation.backend_pid = pg_backend_pid();
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

create function public.workshop_restore_close_internal(p_invocation_id uuid)
returns boolean
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare v_count integer;
begin
  if pg_trigger_depth() <> 0 then
    raise exception 'Recovery cannot close inside a trigger' using errcode = '22023';
  end if;
  delete from public.workshop_restore_invocations i
    where i.id = p_invocation_id and i.transaction_id = txid_current()
      and i.backend_pid = pg_backend_pid();
  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$function$;

revoke all on function public.workshop_restore_trigger_review_internal(),
  public.workshop_restore_hook_when_internal(text, name),
  public.workshop_restore_open_internal(uuid),
  public.workshop_restore_suppress_internal(uuid, regclass),
  public.workshop_restore_release_internal(uuid),
  public.workshop_restore_close_internal(uuid)
  from public, anon, authenticated, service_role;

commit;
