-- C2: one integrated workshop recovery engine, 2026-09-30.
-- Prepared, not APPLIED. Requires 20260930170000 (capture) and
-- 20260930171000 (effect packets). Deploy the three together after review.
--
-- Rule: «vuelve lo que falta; lo que existe hoy manda».
-- * A row whose identity exists today is kept exactly as it is (live wins).
--   20260930092309 replaced present values of customers/brands/models; with
--   the only real backup (2025-12-09) that would have reverted 32 phones and
--   32 RUTs corrected since. No row is updated or deleted any more.
-- * The workshop graph comes back by aggregate. A job, a bike or a task that
--   is missing today comes back complete with its members (lines, bikes of
--   the job, tasks, timeline, ledgers, ficha, memory, history, links, notes).
--   A member of an aggregate that exists today does not come back: in the
--   real backup 39 of 40 missing lines belong to 17 jobs that exist today and
--   are invoiced; their invoice sync replaced them with new lines, and
--   re-adding the old ones would duplicate invoiced work.
-- * Catalogue rows (contacts, brands, models, statuses, subjects, packages)
--   come back when missing.
-- * Sales, purchases, accounting, stock, messaging, website, settings,
--   products and staff are never written. Their backed rows that no longer
--   exist are reported, not replayed.
-- * A link to a record that no longer exists (and does not come back) is
--   dropped when the column admits it; a row that cannot exist without it
--   stays out. Both are reported. Another tenant's identity, parent or
--   linked row, unknown columns or effects, unreviewed defaults and a row
--   the database would store differently refuse the whole recovery.
-- * Restored rows are history: the 30 hooked INSERT effects are suppressed
--   by private packets (20260930171000); the 11 structural validators run.
--   Four hooked task guards mix relations with rewrites; their relations are
--   verified here (workshop_restore_task_graph_internal), not their rewrites.
-- * Preflight runs the same engine inside a subtransaction that is always
--   rolled back, so the answer includes the database's real constraints and
--   validators. It writes and undoes: it is a mutating probe, run only by the
--   operator's review, never as an agent's production measurement. Apply
--   takes the table locks, decides the authority again, reruns it and
--   commits.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- Every captured table and what recovery may do with it, parents first.
-- Production has real FKs from bicycle history to jobs, job bikes and lines.
-- Recover that history after all workshop roots/lines, preserving those links.
-- Local lacks twelve of these FKs; the deployment contract checks the live DB.
create or replace function public.workshop_restore_tables_internal()
returns table(ord integer, table_name text, policy text, root_table text, root_column text)
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  values
    (1, 'customers', 'standalone', null, null),
    (2, 'bike_brands', 'standalone', null, null),
    (3, 'bike_models', 'standalone', null, null),
    (4, 'job_statuses', 'standalone', null, null),
    (5, 'job_subjects', 'standalone', null, null),
    (6, 'service_packages', 'standalone', null, null),
    (7, 'bikes', 'root', null, null),
    (8, 'bike_profiles', 'member', 'bikes', 'bike_id'),
    (45, 'bike_component_lifecycles', 'member', 'bikes', 'bike_id'),
    (46, 'bike_events', 'member', 'bikes', 'bike_id'),
    (47, 'bike_observations', 'member', 'bikes', 'bike_id'),
    (48, 'bike_interventions', 'member', 'bikes', 'bike_id'),
    (49, 'bike_system_states', 'member', 'bikes', 'bike_id'),
    (14, 'mechanic_jobs', 'root', null, null),
    (15, 'bike_technical_fact_patches', 'member', 'bikes', 'bike_id'),
    (16, 'bike_aggregate_save_operations', 'member', 'bikes', 'bike_id'),
    (17, 'mechanic_job_timeline', 'member', 'mechanic_jobs', 'job_id'),
    (18, 'mechanic_job_bikes', 'member', 'mechanic_jobs', 'job_id'),
    (19, 'mechanic_job_items', 'member', 'mechanic_jobs', 'job_id'),
    (20, 'mechanic_job_tasks', 'member', 'mechanic_jobs', 'job_id'),
    (21, 'mechanic_job_creations', 'member', 'mechanic_jobs', 'job_id'),
    (22, 'mechanic_job_line_saves', 'member', 'mechanic_jobs', 'job_id'),
    (23, 'mechanic_job_archive_events', 'member', 'mechanic_jobs', 'job_id'),
    (24, 'mechanic_job_delivery_events', 'member', 'mechanic_jobs', 'job_id'),
    (25, 'mechanic_job_mode_events', 'member', 'mechanic_jobs', 'job_id'),
    (26, 'mechanic_job_status_transition_events', 'member', 'mechanic_jobs', 'job_id'),
    (27, 'mechanic_job_status_transitions', 'member', 'mechanic_jobs', 'job_id'),
    (28, 'mechanic_job_task_preferences', 'member', 'mechanic_jobs', 'job_id'),
    (29, 'mechanic_job_warranty_claim_events', 'member', 'mechanic_jobs', 'warranty_job_id'),
    (30, 'supply_needs', 'member', 'mechanic_jobs', 'mechanic_job_id'),
    (31, 'smart_tasks', 'root', null, null),
    (32, 'smart_task_attachments', 'member', 'smart_tasks', 'task_id'),
    (33, 'smart_task_job_items', 'member', 'smart_tasks', 'task_id'),
    (34, 'smart_task_job_item_notes', 'member', 'smart_tasks', 'task_id'),
    (35, 'smart_task_events', 'member', 'smart_tasks', 'task_id'),
    (36, 'smart_task_user_state', 'member', 'smart_tasks', 'task_id'),
    (38, 'smart_task_command_receipts', 'member', 'smart_tasks', 'task_id'),
    (39, 'workshop_command_attempts', 'standalone', null, null),
    (40, 'mechanic_job_line_gate_deferrals', 'transient', null, null),
    (101, 'journal_lines', 'preserve', null, null),
    (102, 'online_order_items', 'preserve', null, null),
    (103, 'employee_contracts', 'preserve', null, null),
    (104, 'attendance_records', 'preserve', null, null),
    (105, 'messages', 'preserve', null, null),
    (106, 'conversation_contexts', 'preserve', null, null),
    (107, 'conversation_participants', 'preserve', null, null),
    (108, 'whatsapp_conversation_bindings', 'preserve', null, null),
    (109, 'whatsapp_webhook_events', 'preserve', null, null),
    (110, 'journal_entries', 'preserve', null, null),
    (111, 'sales_payments', 'preserve', null, null),
    (112, 'purchase_payments', 'preserve', null, null),
    (113, 'online_orders', 'preserve', null, null),
    (114, 'stock_movements', 'preserve', null, null),
    (115, 'conversations', 'preserve', null, null),
    (116, 'whatsapp_channels', 'preserve', null, null),
    (117, 'sales_invoices', 'preserve', null, null),
    (118, 'purchase_invoices', 'preserve', null, null),
    (119, 'featured_products', 'preserve', null, null),
    (120, 'website_blocks', 'preserve', null, null),
    (121, 'website_content', 'preserve', null, null),
    (122, 'website_banners', 'preserve', null, null),
    (123, 'website_settings', 'preserve', null, null),
    (124, 'company_settings', 'preserve', null, null),
    (125, 'payment_methods', 'preserve', null, null),
    (126, 'products', 'preserve', null, null),
    (127, 'employees', 'preserve', null, null),
    (128, 'accounts', 'preserve', null, null),
    (129, 'product_categories', 'preserve', null, null),
    (130, 'product_brands', 'preserve', null, null),
    (131, 'suppliers', 'preserve', null, null),
    -- The shared task chat channel is messaging configuration (it hangs from
    -- a conversation), not a member of a task.
    (132, 'smart_task_message_channels', 'preserve', null, null)
$function$;

-- References without a foreign key. Recovery keeps them as history but never
-- lets one point at another tenant's live row.
create or replace function public.workshop_restore_soft_links_internal()
returns table(table_name text, column_name text, parent_table text)
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  values
    ('bike_component_lifecycles', 'job_id', 'mechanic_jobs'),
    ('bike_component_lifecycles', 'job_bike_id', 'mechanic_job_bikes'),
    ('bike_component_lifecycles', 'mechanic_job_item_id', 'mechanic_job_items'),
    ('bike_events', 'job_id', 'mechanic_jobs'),
    ('bike_interventions', 'job_id', 'mechanic_jobs'),
    ('bike_interventions', 'job_bike_id', 'mechanic_job_bikes'),
    ('bike_interventions', 'mechanic_job_item_id', 'mechanic_job_items'),
    ('bike_observations', 'job_id', 'mechanic_jobs'),
    ('bike_observations', 'job_bike_id', 'mechanic_job_bikes'),
    ('bike_observations', 'mechanic_job_item_id', 'mechanic_job_items'),
    ('bike_system_states', 'job_id', 'mechanic_jobs'),
    ('bike_system_states', 'job_bike_id', 'mechanic_job_bikes'),
    ('mechanic_job_status_transition_events', 'from_status_id', 'job_statuses'),
    ('mechanic_job_status_transition_events', 'to_status_id', 'job_statuses'),
    ('mechanic_job_status_transitions', 'from_status_id', 'job_statuses'),
    ('mechanic_job_status_transitions', 'to_status_id', 'job_statuses'),
    ('smart_task_command_receipts', 'task_id', 'smart_tasks'),
    ('smart_task_job_item_notes', 'job_item_id', 'mechanic_job_items'),
    ('smart_task_job_items', 'job_item_id', 'mechanic_job_items'),
    ('smart_task_job_items', 'job_id', 'mechanic_jobs'),
    ('smart_task_job_items', 'job_bike_id', 'mechanic_job_bikes'),
    ('workshop_command_attempts', 'bike_id', 'bikes'),
    ('workshop_command_attempts', 'job_id', 'mechanic_jobs')
$function$;

-- Workshop words for every table the recovery reports.
create or replace function public.workshop_restore_table_label(p_table text)
returns text
language sql stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select coalesce(case p_table
      when 'bike_brands' then 'marcas de bicis'
      when 'bike_models' then 'modelos de bicis'
      when 'job_statuses' then 'estados de trabajo'
      when 'job_subjects' then 'componentes recibidos'
      when 'service_packages' then 'paquetes de servicio'
      when 'bike_component_lifecycles' then 'componentes instalados en las bicis'
      when 'bike_events' then 'historial de las bicis'
      when 'bike_observations' then 'observaciones de las bicis'
      when 'bike_interventions' then 'intervenciones en las bicis'
      when 'bike_system_states' then 'estado de los sistemas de las bicis'
      when 'bike_technical_fact_patches' then 'cambios de ficha'
      when 'bike_aggregate_save_operations' then 'guardados de ficha'
      when 'mechanic_job_timeline' then 'historial de los trabajos'
      when 'mechanic_job_bikes' then 'bicis de los trabajos'
      when 'mechanic_job_items' then 'líneas de los trabajos'
      when 'mechanic_job_tasks' then 'tareas de los trabajos'
      when 'mechanic_job_creations' then 'altas de trabajos'
      when 'mechanic_job_line_saves' then 'guardados de líneas'
      when 'mechanic_job_archive_events' then 'archivos de trabajos'
      when 'mechanic_job_delivery_events' then 'entregas'
      when 'mechanic_job_mode_events' then 'decisiones de presupuestos'
      when 'mechanic_job_status_transition_events' then 'registro de estados'
      when 'mechanic_job_status_transitions' then 'cambios de estado'
      when 'mechanic_job_task_preferences' then 'preferencias de tareas'
      when 'mechanic_job_warranty_claim_events' then 'garantías'
      when 'supply_needs' then 'repuestos por conseguir'
      when 'smart_task_attachments' then 'archivos de tareas'
      when 'smart_task_job_items' then 'servicios de las tareas'
      when 'smart_task_job_item_notes' then 'notas de servicios'
      when 'smart_task_events' then 'historial de las tareas'
      when 'smart_task_user_state' then 'lecturas de tareas'
      when 'smart_task_message_channels' then 'conversaciones de tareas'
      when 'smart_task_command_receipts' then 'recibos de tareas'
      when 'workshop_command_attempts' then 'intentos de guardado'
      when 'users' then 'cuentas de usuario'
    end, public.restore_backup_table_label(p_table), p_table)
$function$;

-- «Trabajo RB-50», «Bici Trek Marlin», «Tarea Revisar frenos», for examples.
create or replace function public.workshop_restore_record_label(p_table text, p_row jsonb)
returns text
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select case p_table
    when 'mechanic_jobs' then 'Trabajo ' || coalesce(nullif(p_row ->> 'job_number', ''), 'sin número')
    when 'bikes' then 'Bici ' || coalesce(nullif(btrim(concat_ws(' ', p_row ->> 'brand', p_row ->> 'model')), ''), 'sin marca')
    when 'smart_tasks' then 'Tarea ' || coalesce(nullif(p_row ->> 'title', ''), 'sin título')
    when 'customers' then coalesce(nullif(p_row ->> 'name', ''), 'Cliente')
    when 'mechanic_job_items' then coalesce(nullif(p_row ->> 'product_name', ''),
      nullif(p_row ->> 'description', ''), 'Línea')
    when 'smart_task_job_items' then coalesce(nullif(p_row ->> 'item_name', ''), 'Servicio')
    else null end
$function$;

-- A concrete, atomic refusal: the caller's exception handler rolls back.
create or replace function public.workshop_restore_reject_internal(
  p_code text, p_table text, p_message text
) returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
begin
  raise exception using errcode = 'VBRJ1', message = p_message,
    detail = jsonb_build_object('code', p_code, 'table', p_table)::text;
end;
$function$;

-- Null when every INSERT write path of the relation is reviewed: kept
-- validators with their reviewed digest and no WHEN, hooked effects with the
-- exact reviewed hook, and no INSERT rule. Otherwise the unreviewed path.
create or replace function public.workshop_restore_effects_review_internal(p_relation regclass)
returns text
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_table text;
  v_trigger record;
begin
  select c.relname into v_table from pg_class c
   where c.oid = p_relation and c.relnamespace = 'public'::regnamespace
     and c.relkind = 'r' and not c.relispartition;
  if v_table is null then return 'relation'; end if;
  if exists (select 1 from pg_rewrite r where r.ev_class = p_relation
              and r.ev_type = '3' and r.ev_enabled in ('O', 'A')) then
    return 'rule';
  end if;
  for v_trigger in
    select t.oid, t.tgname, t.tgqual, review.review, review.function_md5,
      md5(replace(pg_get_functiondef(t.tgfoid), E'\r\n', E'\n')) as actual_md5
      from pg_trigger t
      left join public.workshop_restore_trigger_review_internal() review
        on review.table_name = v_table and review.trigger_name = t.tgname
     where t.tgrelid = p_relation and not t.tgisinternal
       and t.tgenabled in ('O', 'A') and (t.tgtype::integer & 4) <> 0
  loop
    if v_trigger.review = 'keep' and v_trigger.tgqual is null
       and v_trigger.actual_md5 = v_trigger.function_md5 then
      continue;
    end if;
    if v_trigger.review = 'hook'
       and position(public.workshop_restore_hook_when_internal(v_table, v_trigger.tgname)
                    in pg_get_triggerdef(v_trigger.oid)) > 0 then
      continue;
    end if;
    return 'trigger ' || v_trigger.tgname;
  end loop;
  return null;
end;
$function$;

-- A preserved domain: how many backed rows no longer exist. Never written.
create or replace function public.workshop_restore_preserved_internal(p_table text, p_rows jsonb)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_missing bigint;
begin
  if exists (select 1 from pg_constraint c join pg_attribute a
               on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
              where c.conrelid = to_regclass(format('public.%I', p_table))
                and c.contype = 'p' and cardinality(c.conkey) = 1
                and a.attname = 'id' and a.atttypid = 'uuid'::regtype) then
    execute format($sql$
      select count(*) from jsonb_array_elements($1) r(value)
       where r.value ->> 'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         and not exists (select 1 from public.%I l
                          where l.id = (r.value ->> 'id')::uuid)
    $sql$, p_table) into v_missing using p_rows;
  end if;
  return jsonb_build_object('table', p_table,
    'label', public.workshop_restore_table_label(p_table),
    'backed_rows', jsonb_array_length(p_rows), 'missing_rows', v_missing);
end;
$function$;

-- Tasks: the relations their hooked guards verified, without their rewrites.
-- The hook suppresses smart_tasks_guard_primary_context,
-- smart_tasks_guard_work_tray, smart_task_job_items_guard and
-- smart_task_job_item_notes_guard whole, because they also stamp now(), the
-- restoring account and fresh snapshots over the history. Their relations
-- still hold for every row that comes back, judged on the row as it would be
-- stored (after dropped links) and against what exists now, including what
-- this invocation restored earlier:
-- * a task has at most one primary context; a note has no execution
--   lifecycle and no service lines; a private task has no assignee and no job;
-- * a service link names a line of its own job, and while it is active that
--   job is the task's job; a line of another job refuses the recovery;
-- * an active link whose line no longer exists (deleted after the backup, or
--   held back) does not come back, and neither do its notes: the task does
--   not get a service it no longer has. An invalidated link is history: it
--   comes back as stored even when its line is gone, and no line is created
--   or reassigned for it;
-- * a note comes back only with its link.
-- History is never re-judged: authorship, times, snapshots, assignees that
-- are no longer active or eligible and jobs archived since then stay as they
-- were. Refusals roll the whole invocation back; held-back rows are reported.
-- Returns {items, missing_parents}.
create or replace function public.workshop_restore_task_graph_internal(
  p_table text, p_tenant_id uuid, p_items jsonb
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_items jsonb := p_items;
  v_missing jsonb := '{}'::jsonb;
  v_label text;
  v_service text;
  v_count bigint;
begin
  if p_table = 'smart_tasks' then
    select coalesce(t.title, 'sin título') into v_label
      from jsonb_array_elements(v_items) i(value)
      cross join lateral jsonb_populate_record(null::public.smart_tasks, i.value -> 'row') t
     where i.value ->> 's' = 'candidate'
       and num_nonnulls(t.linked_job_id, t.linked_customer_id, t.linked_supplier_id,
             t.linked_sales_invoice_id, t.linked_purchase_invoice_id) > 1
     order by (i.value ->> 'o')::bigint limit 1;
    if found then
      perform public.workshop_restore_reject_internal('task_primary_context', p_table,
        format('La tarea «%s» del respaldo está ligada a la vez a más de un trabajo, cliente, '
          'proveedor o factura. No se tocó nada.', v_label));
    end if;
    select coalesce(t.title, 'sin título') into v_label
      from jsonb_array_elements(v_items) i(value)
      cross join lateral jsonb_populate_record(null::public.smart_tasks, i.value -> 'row') t
     where i.value ->> 's' = 'candidate' and t.task_kind = 'note'
       and t.status not in ('pending', 'cancelled')
     order by (i.value ->> 'o')::bigint limit 1;
    if found then
      perform public.workshop_restore_reject_internal('task_note_lifecycle', p_table,
        format('La nota «%s» del respaldo figura en curso, bloqueada o terminada, y una nota no tiene '
          'ese ciclo. No se tocó nada.', v_label));
    end if;
    select coalesce(t.title, 'sin título') into v_label
      from jsonb_array_elements(v_items) i(value)
      cross join lateral jsonb_populate_record(null::public.smart_tasks, i.value -> 'row') t
     where i.value ->> 's' = 'candidate' and t.visibility = 'private'
       and num_nonnulls(t.assigned_to, t.assigned_employee_id, t.linked_job_id) > 0
     order by (i.value ->> 'o')::bigint limit 1;
    if found then
      perform public.workshop_restore_reject_internal('task_private_personal', p_table,
        format('La tarea privada «%s» del respaldo tiene responsable o trabajo, y una tarea '
          'privada es personal. No se tocó nada.', v_label));
    end if;

  elsif p_table = 'smart_task_job_items' then
    -- The task of each candidate was restored by this invocation (a member
    -- comes back only with its root), so it is live now; so is every line
    -- that exists today or came back with its job.
    select coalesce(task.title, 'sin título') into v_label
      from jsonb_array_elements(v_items) i(value)
      join public.smart_tasks task on task.id = (i.value -> 'row' ->> 'task_id')::uuid
                                  and task.tenant_id = p_tenant_id
     where i.value ->> 's' = 'candidate' and task.task_kind = 'note'
     order by (i.value ->> 'o')::bigint limit 1;
    if found then
      perform public.workshop_restore_reject_internal('task_note_has_services', p_table,
        format('La nota «%s» del respaldo trae servicios de un trabajo, y una nota guarda el '
          'trabajo, nunca sus líneas. No se tocó nada.', v_label));
    end if;
    select coalesce(task.title, 'sin título'), coalesce(link.item_name, 'un servicio')
      into v_label, v_service
      from jsonb_array_elements(v_items) i(value)
      cross join lateral jsonb_populate_record(null::public.smart_task_job_items, i.value -> 'row') link
      join public.smart_tasks task on task.id = link.task_id and task.tenant_id = p_tenant_id
      join public.mechanic_job_items item on item.id = link.job_item_id and item.tenant_id = p_tenant_id
     where i.value ->> 's' = 'candidate'
       and (item.job_id is distinct from link.job_id
         or (link.invalidated_at is null and task.linked_job_id is distinct from link.job_id))
     order by (i.value ->> 'o')::bigint limit 1;
    if found then
      perform public.workshop_restore_reject_internal('task_link_job_mismatch', p_table,
        format('En la tarea «%s» del respaldo, «%s» apunta a una línea de otro trabajo que el '
          'de la tarea. No se tocó nada.', v_label, v_service));
    end if;
    select coalesce(jsonb_agg(case when h.held then jsonb_set(h.value, '{s}', '"parent_missing"')
             else h.value end order by h.o), '[]'::jsonb),
           count(*) filter (where h.held)
      into v_items, v_count
      from (select i.value, (i.value ->> 'o')::bigint as o,
              i.value ->> 's' = 'candidate'
                and coalesce(i.value -> 'row' ->> 'invalidated_at', '') = ''
                and not exists (select 1 from public.mechanic_job_items item
                                 where item.id = (i.value -> 'row' ->> 'job_item_id')::uuid
                                   and item.tenant_id = p_tenant_id) as held
              from jsonb_array_elements(v_items) i(value)) h;
    if v_count > 0 then
      v_missing := jsonb_build_object('mechanic_job_items', v_count);
    end if;

  elsif p_table = 'smart_task_job_item_notes' then
    -- Links were written just before (ord 33 < 34): a note whose link is not
    -- live now stays out with it.
    select coalesce(jsonb_agg(case when h.held then jsonb_set(h.value, '{s}', '"parent_missing"')
             else h.value end order by h.o), '[]'::jsonb),
           count(*) filter (where h.held)
      into v_items, v_count
      from (select i.value, (i.value ->> 'o')::bigint as o,
              i.value ->> 's' = 'candidate'
                and not exists (select 1 from public.smart_task_job_items link
                                 where link.task_id = (i.value -> 'row' ->> 'task_id')::uuid
                                   and link.job_item_id = (i.value -> 'row' ->> 'job_item_id')::uuid
                                   and link.tenant_id = p_tenant_id) as held
              from jsonb_array_elements(v_items) i(value)) h;
    if v_count > 0 then
      v_missing := jsonb_build_object('smart_task_job_items', v_count);
    end if;
  end if;
  return jsonb_build_object('items', v_items, 'missing_parents', v_missing);
end;
$function$;

-- One table of the write scope: classify, resolve parents, insert what comes
-- back with its effects suppressed, and verify the stored rows. Items are
-- {o: backup position, s: status, row: typed present fields}.
create or replace function public.workshop_restore_table_internal(
  p_invocation_id uuid, p_tenant_id uuid, p_table text, p_policy text,
  p_root_table text, p_root_column text, p_rows jsonb, p_restored jsonb
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_rel regclass := to_regclass(format('public.%I', p_table));
  v_rel_text text := format('public.%I', p_table);
  v_label text := public.workshop_restore_table_label(p_table);
  v_pk text[];
  v_pk_key text;
  v_pk_match text;
  v_columns text[];
  v_generated text[];
  v_items jsonb;
  v_count bigint;
  v_text text;
  v_fk record;
  v_child_cols text[];
  v_parent_cols text[];
  v_null_cols text[];
  v_live_match text;
  v_foreign_match text;
  v_child_key text;
  v_parent_key text;
  v_parent_available jsonb;
  v_parent_write boolean;
  v_parent_tenant boolean;
  v_nullable boolean;
  v_self_changed boolean;
  v_pass integer;
  v_link record;
  v_keys text[];
  v_group jsonb;
  v_returned jsonb := '[]'::jsonb;
  v_batch jsonb;
  v_candidates jsonb;
  v_attachments jsonb;
  v_omitted jsonb := '[]'::jsonb;
  v_dropped jsonb := '[]'::jsonb;
  v_missing_parents jsonb := '{}'::jsonb;
  v_derived text[] := case when p_table = 'mechanic_job_items'
    then array['total_price'] else '{}'::text[] end;
  v_opened integer;
  v_released integer;
  v_reason text;
  v_not_restored jsonb;
  v_task jsonb;
  v_part record;
begin
  if v_rel is null then
    perform public.workshop_restore_reject_internal('unknown_table', p_table,
      format('El respaldo trae «%s», que ya no existe. No se tocó nada.', v_label));
  end if;
  select array_agg(a.attname::text order by k.ord) into v_pk
    from pg_constraint c cross join lateral unnest(c.conkey) with ordinality k(n, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n
   where c.conrelid = v_rel and c.contype = 'p';
  select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attgenerated = ''), '{}'),
         coalesce(array_agg(a.attname::text) filter (where a.attgenerated <> ''), '{}')
    into v_columns, v_generated
    from pg_attribute a where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped;
  if v_pk is null or not ('tenant_id' = any(v_columns)) then
    perform public.workshop_restore_reject_internal('unsupported_table', p_table,
      format('«%s» no tiene la identidad que la recuperación necesita. No se tocó nada.', v_label));
  end if;
  -- JSON key of a row by its primary key; typed values have one spelling.
  v_pk_key := (select string_agg(format('coalesce(%%1$s->>%L, '''')', k), ' || ''|'' || ') from unnest(v_pk) k);

  -- Shape: objects, known columns, identity and this tenant.
  if exists (select 1 from jsonb_array_elements(p_rows) r(value)
              where jsonb_typeof(r.value) is distinct from 'object') then
    perform public.workshop_restore_reject_internal('invalid_data', p_table,
      format('Una fila de «%s» del respaldo está dañada. No se tocó nada.', v_label));
  end if;
  select string_agg(distinct k, ', ') into v_text
    from jsonb_array_elements(p_rows) r(value) cross join lateral jsonb_object_keys(r.value) k
   where not (k = any(v_columns)) and not (k = any(v_generated));
  if v_text is not null then
    perform public.workshop_restore_reject_internal('unknown_column', p_table,
      format('«%s» del respaldo trae campos que ya no existen (%s). No se tocó nada.', v_label, v_text));
  end if;
  execute format($sql$
    select coalesce(jsonb_agg(jsonb_build_object('o', r.ord, 's', 'candidate', 'row',
        (select jsonb_object_agg(k, t.typed -> k) from jsonb_object_keys(r.value - $2) k))
      order by r.ord), '[]'::jsonb)
      from jsonb_array_elements($1) with ordinality r(value, ord)
      cross join lateral (select to_jsonb(jsonb_populate_record(null::%s, r.value - $2)) as typed) t
  $sql$, v_rel_text) into v_items using p_rows, v_generated;
  if exists (select 1 from jsonb_array_elements(v_items) i(value)
              cross join unnest(v_pk || array['tenant_id']) k
              where coalesce(i.value -> 'row' -> k, 'null'::jsonb) = 'null'::jsonb) then
    perform public.workshop_restore_reject_internal('invalid_data', p_table,
      format('Una fila de «%s» del respaldo no trae su identidad. No se tocó nada.', v_label));
  end if;
  if exists (select 1 from jsonb_array_elements(v_items) i(value)
              where (i.value -> 'row' ->> 'tenant_id')::uuid is distinct from p_tenant_id) then
    perform public.workshop_restore_reject_internal('other_tenant_row', p_table,
      format('«%s» del respaldo trae filas de otro taller. No se tocó nada.', v_label));
  end if;
  execute format('select count(*) from (select 1 from jsonb_array_elements($1) i(value)
      group by %s having count(*) > 1) d', format(v_pk_key, 'i.value->''row'''))
    into v_count using v_items;
  if v_count > 0 then
    perform public.workshop_restore_reject_internal('duplicate_identity', p_table,
      format('«%s» del respaldo repite registros. No se tocó nada.', v_label));
  end if;

  -- Identity: what exists today is kept; another tenant's identity refuses.
  select string_agg(format('l.%I = (i.value->''row''->>%L)::%s', a.attname, a.attname,
           format_type(a.atttypid, a.atttypmod)), ' and ')
    into v_pk_match
    from unnest(v_pk) k join pg_attribute a on a.attrelid = v_rel and a.attname = k;
  execute format($sql$
    select count(*) from jsonb_array_elements($1) i(value)
     where exists (select 1 from %s l where %s and l.tenant_id is distinct from $2)
  $sql$, v_rel_text, v_pk_match) into v_count using v_items, p_tenant_id;
  if v_count > 0 then
    perform public.workshop_restore_reject_internal('other_tenant_identity', p_table,
      format('«%s» del respaldo usa registros de otro taller. No se tocó nada.', v_label));
  end if;
  execute format($sql$
    select coalesce(jsonb_agg(case when exists (select 1 from %s l where %s)
        then jsonb_set(i.value, '{s}', '"existing"') else i.value end
      order by (i.value ->> 'o')::bigint), '[]'::jsonb)
      from jsonb_array_elements($1) i(value)
  $sql$, v_rel_text, v_pk_match) into v_items using v_items;

  -- Aggregates: a member comes back only with its root.
  if p_policy = 'member' then
    select coalesce(jsonb_object_agg(r.value ->> 'id', true), '{}'::jsonb) into v_parent_available
      from jsonb_array_elements(coalesce(p_restored -> p_root_table, '[]'::jsonb)) r(value);
    execute format($sql$
      select coalesce(jsonb_agg(case
          when i.value ->> 's' <> 'candidate'
            or coalesce(i.value -> 'row' ->> %1$L, '') = '' then i.value
          when $2 ? (i.value -> 'row' ->> %1$L) then i.value
          when exists (select 1 from public.%2$I root
                        where root.id = (i.value -> 'row' ->> %1$L)::uuid
                          and root.tenant_id = $3)
            then jsonb_set(i.value, '{s}', '"root_live"')
          else jsonb_set(i.value, '{s}', '"root_not_restored"') end
        order by (i.value ->> 'o')::bigint), '[]'::jsonb)
        from jsonb_array_elements($1) i(value)
    $sql$, p_root_column, p_root_table) into v_items using v_items, v_parent_available, p_tenant_id;
  end if;

  -- A portal account is current authorization, not history: a contact that
  -- comes back never gets its old portal link back (the live one, if any, is
  -- never touched because existing rows are never written).
  if p_table = 'customers' then
    select count(*) into v_count from jsonb_array_elements(v_items) i(value)
     where i.value ->> 's' = 'candidate' and coalesce(i.value -> 'row' ->> 'auth_user_id', '') <> '';
    if v_count > 0 then
      select coalesce(jsonb_agg(case when i.value ->> 's' = 'candidate'
          and coalesce(i.value -> 'row' ->> 'auth_user_id', '') <> ''
          then jsonb_set(i.value, '{row,auth_user_id}', 'null'::jsonb) else i.value end
        order by (i.value ->> 'o')::bigint), '[]'::jsonb)
        into v_items from jsonb_array_elements(v_items) i(value);
      v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('column', 'auth_user_id',
        'parent_table', 'portal_access', 'parent_label', 'acceso al portal', 'rows', v_count));
    end if;
  end if;

  -- Parents. Live (this tenant) or restored in this invocation are available.
  -- Otherwise a nullable link is dropped and a required one keeps the row out.
  -- Another tenant's live parent refuses the recovery. Self references repeat
  -- until stable.
  for v_pass in 1..5 loop
    v_self_changed := false;
    for v_fk in
      select c.oid, c.conname, c.conkey, c.confkey, c.confrelid, c.confmatchtype,
        p.relname as parent_table,
        n.nspname as parent_schema
        from pg_constraint c join pg_class p on p.oid = c.confrelid
        join pg_namespace n on n.oid = p.relnamespace
       where c.conrelid = v_rel and c.contype = 'f'
         and not (n.nspname = 'public' and p.relname = 'tenants')
       order by c.conname
    loop
      select array_agg(ca.attname::text order by k.ord), array_agg(pa.attname::text order by k.ord),
        array_agg(ca.attname::text order by k.ord) filter (where ca.attname <> 'tenant_id'),
        string_agg(format('p.%I = (i.value->''row''->>%L)::%s', pa.attname, ca.attname,
          format_type(ca.atttypid, ca.atttypmod)), ' and ' order by k.ord),
        bool_and(not ca.attnotnull) filter (where ca.attname <> 'tenant_id')
        into v_child_cols, v_parent_cols, v_null_cols, v_live_match, v_nullable
        from unnest(v_fk.conkey, v_fk.confkey) with ordinality k(child_num, parent_num, ord)
        join pg_attribute ca on ca.attrelid = v_rel and ca.attnum = k.child_num
        join pg_attribute pa on pa.attrelid = v_fk.confrelid and pa.attnum = k.parent_num;
      v_nullable := coalesce(v_nullable, false) and cardinality(v_null_cols) > 0;
      v_parent_tenant := exists (select 1 from pg_attribute a where a.attrelid = v_fk.confrelid
        and a.attname = 'tenant_id' and a.atttypid = 'uuid'::regtype and not a.attisdropped);
      v_parent_write := v_fk.parent_schema = 'public' and exists (
        select 1 from public.workshop_restore_tables_internal() t
         where t.table_name = v_fk.parent_table and t.policy in ('standalone', 'root', 'member'));
      v_child_key := (select string_agg(format('coalesce(i.value->''row''->>%L, '''')', c), ' || ''|'' || ')
                        from unnest(v_child_cols) c);
      v_parent_key := (select string_agg(format('coalesce(r.value->>%L, '''')', c), ' || ''|'' || ')
                         from unnest(v_parent_cols) c);
      -- Available parents restored earlier, or candidates of this same table.
      execute format($sql$
        select coalesce(jsonb_object_agg(%s, true), '{}'::jsonb) from (
          select r.value from jsonb_array_elements($1) r(value) where $3
          union all
          select i.value -> 'row' from jsonb_array_elements($2) i(value)
           where $4 and i.value ->> 's' = 'candidate') r(value)
      $sql$, v_parent_key) into v_parent_available
        using coalesce(p_restored -> v_fk.parent_table, '[]'::jsonb), v_items,
          v_parent_write, v_fk.confrelid = v_rel;
      v_foreign_match := case when v_parent_tenant
        then format('exists (select 1 from %I.%I p where %s and p.tenant_id is distinct from $2)',
          v_fk.parent_schema, v_fk.parent_table, v_live_match) else 'false' end;
      execute format($sql$
        select count(*) from jsonb_array_elements($1) i(value)
         where i.value ->> 's' = 'candidate'
           and not exists (select 1 from unnest($3::text[]) c
                            where coalesce(i.value -> 'row' -> c, 'null'::jsonb) = 'null'::jsonb)
           and %s
      $sql$, v_foreign_match) into v_count using v_items, p_tenant_id, v_child_cols;
      if v_count > 0 then
        perform public.workshop_restore_reject_internal('other_tenant_parent', p_table,
          format('«%s» del respaldo apunta a %s de otro taller. No se tocó nada.', v_label,
            public.workshop_restore_table_label(v_fk.parent_table)));
      end if;
      execute format($sql$
        with judged as (
          select i.value, (i.value ->> 'o')::bigint as o,
            i.value ->> 's' = 'candidate'
              and not exists (select 1 from unnest($3::text[]) c
                               where coalesce(i.value -> 'row' -> c, 'null'::jsonb) = 'null'::jsonb)
              and not ($4 ? (%s))
              and not exists (select 1 from %I.%I p where %s %s) as missing
            from jsonb_array_elements($1) i(value)
        )
        select coalesce(jsonb_agg(case
            when not missing then value
            when $5 then jsonb_set(value, '{row}', (value -> 'row') ||
              coalesce((select jsonb_object_agg(c, null) from unnest($6::text[]) c), '{}'::jsonb))
            else jsonb_set(value, '{s}', '"parent_missing"') end order by o), '[]'::jsonb),
          count(*) filter (where missing)
          from judged
      $sql$, v_child_key, v_fk.parent_schema, v_fk.parent_table, v_live_match,
        case when v_parent_tenant then 'and p.tenant_id = $2' else '' end)
        into v_items, v_count
        using v_items, p_tenant_id, v_child_cols, v_parent_available,
          v_nullable, v_null_cols;
      if v_count > 0 then
        if v_nullable then
          v_dropped := v_dropped || jsonb_build_array(jsonb_build_object(
            'column', array_to_string(v_null_cols, ', '), 'parent_table', v_fk.parent_table,
            'parent_label', public.workshop_restore_table_label(v_fk.parent_table), 'rows', v_count));
        else
          v_missing_parents := jsonb_set(v_missing_parents, array[v_fk.parent_table],
            to_jsonb(coalesce((v_missing_parents ->> v_fk.parent_table)::bigint, 0) + v_count));
        end if;
        if v_fk.confrelid = v_rel then
          v_self_changed := true;
        end if;
      end if;
    end loop;
    exit when not v_self_changed;
  end loop;

  -- Soft links: history may point anywhere in this tenant, never elsewhere.
  for v_link in select s.column_name, s.parent_table from public.workshop_restore_soft_links_internal() s
                 where s.table_name = p_table and s.column_name = any(v_columns) loop
    execute format($sql$
      select count(*) from jsonb_array_elements($1) i(value)
       where i.value ->> 's' = 'candidate'
         and coalesce(i.value -> 'row' ->> %1$L, '') <> ''
         and exists (select 1 from public.%2$I p
                      where p.id = (i.value -> 'row' ->> %1$L)::uuid
                        and p.tenant_id is distinct from $2)
    $sql$, v_link.column_name, v_link.parent_table) into v_count using v_items, p_tenant_id;
    if v_count > 0 then
      perform public.workshop_restore_reject_internal('other_tenant_link', p_table,
        format('«%s» del respaldo apunta a %s de otro taller. No se tocó nada.', v_label,
          public.workshop_restore_table_label(v_link.parent_table)));
    end if;
  end loop;

  -- Tasks keep the relations their suppressed guards verified.
  if p_table in ('smart_tasks', 'smart_task_job_items', 'smart_task_job_item_notes') then
    v_task := public.workshop_restore_task_graph_internal(p_table, p_tenant_id, v_items);
    v_items := v_task -> 'items';
    for v_part in select m.key, m.value from jsonb_each_text(v_task -> 'missing_parents') m loop
      v_missing_parents := jsonb_set(v_missing_parents, array[v_part.key],
        to_jsonb(coalesce((v_missing_parents ->> v_part.key)::bigint, 0) + v_part.value::bigint));
    end loop;
  end if;

  -- Photos and attachments whose file is gone come back without that URL.
  if p_table in ('bikes', 'mechanic_jobs') then
    select coalesce(jsonb_agg(i.value -> 'row' order by (i.value ->> 'o')::bigint), '[]'::jsonb)
      into v_candidates from jsonb_array_elements(v_items) i(value)
     where i.value ->> 's' = 'candidate';
    if jsonb_array_length(v_candidates) > 0 then
      v_attachments := public.backup_rows_without_missing_images(v_candidates, p_table,
        case p_table when 'bikes' then 'bike-images' else 'job-images' end, p_tenant_id);
      v_omitted := coalesce(v_attachments -> 'omitted', '[]'::jsonb);
      select coalesce(jsonb_agg(case when i.value ->> 's' = 'candidate'
          then jsonb_set(i.value, '{row}', coalesce((select a.value from jsonb_array_elements(v_attachments -> 'rows') a(value)
            where a.value ->> 'id' = i.value -> 'row' ->> 'id'), i.value -> 'row'))
          else i.value end order by (i.value ->> 'o')::bigint), '[]'::jsonb)
        into v_items from jsonb_array_elements(v_items) i(value);
    end if;
  end if;

  if exists (select 1 from jsonb_array_elements(v_items) i(value) where i.value ->> 's' = 'candidate') then
    -- Omitted columns take their real default only when it is reviewed safe.
    for v_keys in
      select distinct array(select k from jsonb_object_keys(i.value -> 'row') k order by k)
        from jsonb_array_elements(v_items) i(value) where i.value ->> 's' = 'candidate'
    loop
      select string_agg(a.attname, ', ') into v_text from pg_attribute a
       where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
         and not (a.attname::text = any(v_keys)) and a.attnotnull and not a.atthasdef;
      if v_text is not null then
        perform public.workshop_restore_reject_internal('missing_required_column', p_table,
          format('«%s» del respaldo no trae %s, que hoy es obligatorio. No se tocó nada.', v_label, v_text));
      end if;
      if exists (select 1 from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
                  where d.adrelid = v_rel and a.attgenerated = '' and not (a.attname::text = any(v_keys))
                    and not public.backup_merge_expression_safe_internal(d.adbin, true)) then
        perform public.workshop_restore_reject_internal('unreviewed_default', p_table,
          format('«%s» necesita un valor por defecto que la recuperación no revisó. No se tocó nada.', v_label));
      end if;
    end loop;
    v_reason := public.workshop_restore_effects_review_internal(v_rel);
    if v_reason is not null then
      perform public.workshop_restore_reject_internal('unreviewed_effect', p_table,
        format('«%s» tiene un efecto que la recuperación no revisó (%s). No se tocó nada.', v_label, v_reason));
    end if;

    -- One statement per column set, effects suppressed for exactly it.
    for v_keys in
      select distinct array(select k from jsonb_object_keys(i.value -> 'row') k order by k)
        from jsonb_array_elements(v_items) i(value) where i.value ->> 's' = 'candidate'
    loop
      select jsonb_agg(i.value -> 'row' order by (i.value ->> 'o')::bigint) into v_group
        from jsonb_array_elements(v_items) i(value)
       where i.value ->> 's' = 'candidate'
         and array(select k from jsonb_object_keys(i.value -> 'row') k order by k) = v_keys;
      v_opened := public.workshop_restore_suppress_internal(p_invocation_id, v_rel);
      execute format($sql$
        with inserted as (
          insert into %1$s as t (%2$s)
          select %2$s from jsonb_populate_recordset(null::%1$s, $1)
          on conflict do nothing
          returning to_jsonb(t) as value)
        select coalesce(jsonb_agg(value), '[]'::jsonb) from inserted
      $sql$, v_rel_text, (select string_agg(format('%I', k), ', ') from unnest(v_keys) k))
        into v_batch using v_group;
      v_released := public.workshop_restore_release_internal(p_invocation_id);
      if v_released <> v_opened then
        raise exception 'Recovery packets changed during the write' using errcode = '22023';
      end if;
      v_returned := v_returned || v_batch;
    end loop;

    -- A candidate the database skipped conflicts with a row of today.
    execute format($sql$
      select coalesce(jsonb_agg(case when i.value ->> 's' = 'candidate'
          and not exists (select 1 from jsonb_array_elements($2) r(value) where %s = %s)
          then jsonb_set(i.value, '{s}', '"conflict"') else i.value end
        order by (i.value ->> 'o')::bigint), '[]'::jsonb)
        from jsonb_array_elements($1) i(value)
    $sql$, format(v_pk_key, 'r.value'), format(v_pk_key, 'i.value->''row'''))
      into v_items using v_items, v_returned;

    -- The stored row must be the backed row, field by field.
    execute format($sql$
      select count(*) from jsonb_array_elements($1) i(value)
        join jsonb_array_elements($2) r(value) on %s = %s
       where i.value ->> 's' = 'candidate'
         and exists (select 1 from jsonb_object_keys(i.value -> 'row') k
                      where not (k = any($3))
                        and i.value -> 'row' -> k is distinct from r.value -> k)
    $sql$, format(v_pk_key, 'r.value'), format(v_pk_key, 'i.value->''row'''))
      into v_count using v_items, v_returned, v_derived;
    if v_count > 0 then
      perform public.workshop_restore_reject_internal('recovery_mismatch', p_table,
        format('«%s» se guardaría distinto a como está en el respaldo. No se tocó nada.', v_label));
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('reason', s.status, 'rows', s.n,
      'root_label', case p_root_table when 'mechanic_jobs' then 'trabajo'
        when 'bikes' then 'bici' when 'smart_tasks' then 'tarea' end,
      'parents', case when s.status = 'parent_missing' then (
        select jsonb_agg(jsonb_build_object('table', m.key,
          'label', public.workshop_restore_table_label(m.key), 'rows', m.value::bigint))
          from jsonb_each_text(v_missing_parents) m) end,
      'examples', s.examples) order by s.status), '[]'::jsonb)
    into v_not_restored
    from (select i.value ->> 's' as status, count(*) as n,
            (array_agg(public.workshop_restore_record_label(p_table, i.value -> 'row')
               order by (i.value ->> 'o')::bigint)
               filter (where public.workshop_restore_record_label(p_table, i.value -> 'row') is not null))[1:5]
              as examples
            from jsonb_array_elements(v_items) i(value)
           where i.value ->> 's' in ('root_live', 'root_not_restored', 'parent_missing', 'conflict')
           group by i.value ->> 's') s;

  return jsonb_build_object('restored_rows', v_returned, 'report', jsonb_build_object(
    'table', p_table, 'label', v_label,
    'restored', jsonb_array_length(v_returned),
    'existing', (select count(*) from jsonb_array_elements(v_items) i(value) where i.value ->> 's' = 'existing'),
    'examples', (select to_jsonb((array_agg(public.workshop_restore_record_label(p_table, r.value))
                   filter (where public.workshop_restore_record_label(p_table, r.value) is not null))[1:5])
                   from jsonb_array_elements(v_returned) r(value)),
    'not_restored', v_not_restored, 'links_dropped', v_dropped, 'omitted_attachments', v_omitted));
end;
$function$;

-- The engine. Writes: callers run it for real under locks, or inside a
-- subtransaction that they always roll back.
create or replace function public.workshop_restore_run_internal(p_data jsonb, p_tenant_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_invocation uuid;
  v_table record;
  v_rows jsonb;
  v_step jsonb;
  v_restored jsonb := '{}'::jsonb;
  v_tables jsonb := '[]'::jsonb;
  v_preserved jsonb := '[]'::jsonb;
  v_unknown text;
  v_state text;
  v_message text;
begin
  if pg_trigger_depth() <> 0 then
    raise exception 'Recovery cannot be nested in a business trigger' using errcode = '22023';
  end if;
  if p_tenant_id is null or jsonb_typeof(p_data) is distinct from 'object' then
    perform public.workshop_restore_reject_internal('invalid_data', null,
      'El respaldo está dañado. No se tocó nada.');
  end if;
  select string_agg(k, ', ' order by k) into v_unknown from jsonb_object_keys(p_data) k
   where not exists (select 1 from public.workshop_restore_tables_internal() t where t.table_name = k);
  if v_unknown is not null then
    perform public.workshop_restore_reject_internal('unknown_table', null,
      format('El respaldo trae datos que esta versión no sabe recuperar (%s). No se tocó nada.', v_unknown));
  end if;
  v_invocation := public.workshop_restore_open_internal(p_tenant_id);
  for v_table in select * from public.workshop_restore_tables_internal() order by ord loop
    v_rows := p_data -> v_table.table_name;
    if v_rows is null or v_rows = 'null'::jsonb or v_table.policy = 'transient' then
      continue;
    end if;
    if jsonb_typeof(v_rows) is distinct from 'array' then
      perform public.workshop_restore_reject_internal('invalid_data', v_table.table_name,
        format('«%s» del respaldo está dañado. No se tocó nada.',
          public.workshop_restore_table_label(v_table.table_name)));
    end if;
    if jsonb_array_length(v_rows) = 0 then continue; end if;
    if v_table.policy = 'preserve' then
      v_preserved := v_preserved || jsonb_build_array(
        public.workshop_restore_preserved_internal(v_table.table_name, v_rows));
      continue;
    end if;
    begin
      v_step := public.workshop_restore_table_internal(v_invocation, p_tenant_id,
        v_table.table_name, v_table.policy, v_table.root_table, v_table.root_column,
        v_rows, v_restored);
    exception
      when sqlstate 'VBRJ1' then raise;
      when lock_not_available or deadlock_detected or serialization_failure then raise;
      when others then
        get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
        raise exception using errcode = 'VBRJ1',
          message = format('La base no aceptó «%s» del respaldo: %s. No se tocó nada.',
            public.workshop_restore_table_label(v_table.table_name), v_message),
          detail = jsonb_build_object('code', 'write_refused', 'table', v_table.table_name,
            'sqlstate', v_state)::text;
    end;
    v_restored := jsonb_set(v_restored, array[v_table.table_name], v_step -> 'restored_rows');
    v_tables := v_tables || jsonb_build_array(v_step -> 'report');
  end loop;
  if not public.workshop_restore_close_internal(v_invocation) then
    raise exception 'Recovery invocation did not close' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'changed_rows', coalesce((select sum((t ->> 'restored')::bigint) from jsonb_array_elements(v_tables) t), 0),
    'existing_rows', coalesce((select sum((t ->> 'existing')::bigint) from jsonb_array_elements(v_tables) t), 0),
    'restored', coalesce((select jsonb_agg(jsonb_build_object('table', t ->> 'table', 'label', t ->> 'label',
        'rows', (t ->> 'restored')::bigint, 'examples', t -> 'examples'))
      from jsonb_array_elements(v_tables) t where (t ->> 'restored')::bigint > 0), '[]'::jsonb),
    'not_restored', coalesce((select jsonb_agg(n || jsonb_build_object('table', t ->> 'table', 'label', t ->> 'label'))
      from jsonb_array_elements(v_tables) t cross join lateral jsonb_array_elements(t -> 'not_restored') n), '[]'::jsonb),
    'links_dropped', coalesce((select jsonb_agg(d || jsonb_build_object('table', t ->> 'table', 'label', t ->> 'label'))
      from jsonb_array_elements(v_tables) t cross join lateral jsonb_array_elements(t -> 'links_dropped') d), '[]'::jsonb),
    'omitted_attachments', coalesce((select jsonb_agg(o)
      from jsonb_array_elements(v_tables) t cross join lateral jsonb_array_elements(t -> 'omitted_attachments') o), '[]'::jsonb),
    'preserved', v_preserved,
    'tables', v_tables);
end;
$function$;

-- The words the dialog shows for a refusal raised by the engine.
create or replace function public.workshop_restore_refusal_internal(p_message text, p_detail text)
returns jsonb
language plpgsql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare v_detail jsonb;
begin
  begin
    v_detail := p_detail::jsonb;
  exception when others then
    v_detail := '{}'::jsonb;
  end;
  return jsonb_build_object('code', coalesce(v_detail ->> 'code', 'refused'),
    'table', v_detail ->> 'table', 'sqlstate', v_detail ->> 'sqlstate', 'message', p_message);
end;
$function$;

create or replace function public.restore_backup_merge_preflight(p_backup_id uuid, p_tenant_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_data jsonb;
  v_report jsonb;
  v_refusal jsonb;
  v_message text;
  v_detail text;
begin
  if not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;
  select b.backup_data into v_data from public.database_backups b
   where b.id = p_backup_id and b.tenant_id = p_tenant_id and b.status = 'completed';
  if v_data is null then raise exception 'Backup access denied' using errcode = '42501'; end if;
  -- The real engine, then an unconditional rollback of its subtransaction.
  begin
    v_report := public.workshop_restore_run_internal(v_data, p_tenant_id);
    raise exception using errcode = 'VBDRY', message = 'preflight rollback';
  exception
    when sqlstate 'VBDRY' then null;
    when sqlstate 'VBRJ1' then
      get stacked diagnostics v_message = message_text, v_detail = pg_exception_detail;
      v_refusal := public.workshop_restore_refusal_internal(v_message, v_detail);
    when lock_not_available or deadlock_detected or serialization_failure then
      v_refusal := jsonb_build_object('code', 'busy', 'message',
        'Hay registros en uso. No se tocó nada; vuelve a revisar en un momento.');
  end;
  if v_refusal is not null then
    return jsonb_build_object('can_restore', false, 'recovery_mode', 'restore_missing_keep_live',
      'contract', 'workshop_graph_v1', 'refusal', v_refusal, 'message', v_refusal ->> 'message');
  end if;
  return v_report - 'tables' || jsonb_build_object('can_restore', true,
    'recovery_mode', 'restore_missing_keep_live', 'contract', 'workshop_graph_v1',
    'message', case when (v_report ->> 'changed_rows')::bigint = 0
      then 'No falta nada de lo que guarda el respaldo: todo existe hoy y se conserva como está.'
      else 'Vuelve lo que falta; lo que existe hoy se conserva como está.' end);
end;
$function$;

create or replace function public.restore_backup_merge(p_backup_id uuid, p_tenant_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
set lock_timeout to '3s'
as $function$
declare
  v_data jsonb;
  v_report jsonb;
  v_lock_tables text;
  v_message text;
  v_detail text;
  v_refusal jsonb;
begin
  if not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;
  select b.backup_data into v_data from public.database_backups b
   where b.id = p_backup_id and b.tenant_id = p_tenant_id and b.status = 'completed' for update;
  if v_data is null then raise exception 'Backup access denied' using errcode = '42501'; end if;
  -- Writers of the workshop scope wait (or this refuses as busy) until the
  -- recovery commits. OID order; readers are not blocked.
  select string_agg(format('public.%I', t.table_name), ', ' order by to_regclass(format('public.%I', t.table_name))::oid)
    into v_lock_tables from public.workshop_restore_tables_internal() t
   where t.policy in ('standalone', 'root', 'member');
  execute 'lock table ' || v_lock_tables || ' in share row exclusive mode';
  -- The authority is decided again once the locks are held: a role removed
  -- while this waited must not reach the writer.
  if not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;
  v_report := public.workshop_restore_run_internal(v_data, p_tenant_id);
  update public.database_backups set restored_at = clock_timestamp(), restored_by = auth.uid(),
    restore_report = jsonb_build_object('restored_at', clock_timestamp(),
      'recovery_mode', 'restore_missing_keep_live', 'contract', 'workshop_graph_v1',
      'changed_rows', jsonb_build_object('inserted', (v_report ->> 'changed_rows')::bigint, 'updated', 0),
      'restored', v_report -> 'restored', 'not_restored', v_report -> 'not_restored',
      'links_dropped', v_report -> 'links_dropped', 'preserved', v_report -> 'preserved',
      'omitted_attachments', v_report -> 'omitted_attachments')
   where id = p_backup_id and tenant_id = p_tenant_id;
  return v_report - 'tables' || jsonb_build_object('success', true, 'backup_id', p_backup_id,
    'recovery_mode', 'restore_missing_keep_live', 'contract', 'workshop_graph_v1',
    'message', case when (v_report ->> 'changed_rows')::bigint = 0
      then 'No faltaba nada: el taller ya tenía todo lo que guarda el respaldo. No se cambió ningún registro.'
      else 'Volvió lo que faltaba. Lo que existía hoy quedó como estaba.' end);
exception
  when sqlstate 'VBRJ1' then
    get stacked diagnostics v_message = message_text, v_detail = pg_exception_detail;
    v_refusal := public.workshop_restore_refusal_internal(v_message, v_detail);
    return jsonb_build_object('success', false, 'backup_id', p_backup_id,
      'error_code', 'restore_merge_not_safe', 'recovery_mode', 'restore_missing_keep_live',
      'refusal', v_refusal, 'message', v_message);
  when check_violation or unique_violation or foreign_key_violation or not_null_violation
       or data_exception then
    return jsonb_build_object('success', false, 'backup_id', p_backup_id,
      'error_code', 'restore_merge_constraint_conflict', 'recovery_mode', 'restore_missing_keep_live',
      'message', 'La recuperación se revirtió completa porque hay datos incompatibles. No se cambió ningún registro.');
  when lock_not_available or deadlock_detected or serialization_failure then
    return jsonb_build_object('success', false, 'backup_id', p_backup_id,
      'error_code', 'restore_merge_busy', 'recovery_mode', 'restore_missing_keep_live',
      'message', 'Hay registros en uso. No se cambió nada; vuelve a intentar cuando termine la operación en curso.');
  when query_canceled then
    return jsonb_build_object('success', false, 'backup_id', p_backup_id,
      'error_code', 'restore_merge_timeout', 'recovery_mode', 'restore_missing_keep_live',
      'message', 'La recuperación tardó demasiado y se revirtió completa. No se cambió ningún registro.');
end;
$function$;

revoke all on function public.workshop_restore_tables_internal(),
  public.workshop_restore_soft_links_internal(),
  public.workshop_restore_table_label(text),
  public.workshop_restore_record_label(text, jsonb),
  public.workshop_restore_reject_internal(text, text, text),
  public.workshop_restore_effects_review_internal(regclass),
  public.workshop_restore_preserved_internal(text, jsonb),
  public.workshop_restore_task_graph_internal(text, uuid, jsonb),
  public.workshop_restore_table_internal(uuid, uuid, text, text, text, text, jsonb, jsonb),
  public.workshop_restore_run_internal(jsonb, uuid),
  public.workshop_restore_refusal_internal(text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_merge_preflight(uuid, uuid),
  public.restore_backup_merge(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.restore_backup_merge_preflight(uuid, uuid),
  public.restore_backup_merge(uuid, uuid) to authenticated;

-- Every captured table has exactly one recovery policy, and every foreign key
-- between written tables points to an earlier table (or itself).
do $contract$
begin
  if exists (select 1 from public.workshop_restore_tables_internal() t
              where t.policy = 'member' and not exists (
                select 1 from pg_attribute a
                 where a.attrelid = to_regclass(format('public.%I', t.table_name))
                   and a.attname = t.root_column and a.atttypid = 'uuid'::regtype
                   and not a.attisdropped)) then
    raise exception 'A member table lacks its root column';
  end if;
  if exists (select 1 from public.workshop_backup_scope_internal() s
              where not exists (select 1 from public.workshop_restore_tables_internal() t
                                 where t.table_name = s.table_name)) then
    raise exception 'A captured table has no recovery policy';
  end if;
  if exists (
    select 1 from pg_constraint c
      join pg_class child on child.oid = c.conrelid
      join pg_class parent on parent.oid = c.confrelid
      join public.workshop_restore_tables_internal() ct on ct.table_name = child.relname
      join public.workshop_restore_tables_internal() pt on pt.table_name = parent.relname
     where c.contype = 'f' and child.relnamespace = 'public'::regnamespace
       and parent.relnamespace = 'public'::regnamespace
       and ct.policy in ('standalone', 'root', 'member')
       and pt.policy in ('standalone', 'root', 'member')
       and pt.ord > ct.ord) then
    raise exception 'Recovery order puts a child before its parent';
  end if;
end;
$contract$;

commit;
