-- C2 review (Codex, 2026-09-30): the hook suppresses four task guards whole
-- (their rewrites of times, actors and snapshots would falsify history), so
-- the engine verifies their relations itself. Through the installed public
-- RPCs and a real create_backup, this decides:
--   A. concrete, atomic refusals: two primary contexts, a service of another
--      job (as the line's job and as the task's job), a note with services,
--      a note with an execution lifecycle, a private task with an assignee;
--      a bike restored earlier in the same run does not survive any of them;
--   B. an active service link whose line was deleted after the backup does
--      not come back, and neither does its note; both are reported;
--   C. an invalidated link is history: it comes back as stored without its
--      line, with its note, and no line is created or reassigned;
--   D. history is not re-judged: a job archived since and an assignee who
--      is no longer eligible stay as they were.
-- Local only, synthetic tenant, transaction rolled back.
begin;
select no_plan();
do $guard$
begin
  if exists (select 1 from vault.secrets) then
    raise exception 'restore_workshop_task_graph: local database only';
  end if;
end;
$guard$;

create temporary table tg_results(label text primary key, result jsonb);
grant all on tg_results to authenticated;
create function pg_temp.tg(p_suffix text) returns uuid language sql
as $$ select ('e2899300-0000-4000-8000-0000000000' || p_suffix)::uuid $$;
create function pg_temp.tg_claims(p_user text) returns void language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.tg(p_user), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.tg(p_user)::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;
create function pg_temp.tg_run(p_label text, p_backup uuid) returns void language plpgsql
as $$
begin
  insert into tg_results values (p_label || '-preflight',
    public.restore_backup_merge_preflight(p_backup, pg_temp.tg('01')));
  insert into tg_results values (p_label || '-apply',
    public.restore_backup_merge(p_backup, pg_temp.tg('01')));
end;
$$;
grant execute on function pg_temp.tg_run(text, uuid) to authenticated;

-- Tenant, its administrator and an account that never belonged to it.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values (pg_temp.tg('01'), 'Tareas recuperadas');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  (pg_temp.tg('91'), 'authenticated', 'authenticated', 'tg-admin@example.invalid', '', now(), '{}', '{}', now(), now()),
  (pg_temp.tg('94'), 'authenticated', 'authenticated', 'tg-antes@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.tg('91'), pg_temp.tg('01'), 'admin');

select pg_temp.tg_claims('91');
insert into public.customers(id, tenant_id, name, phone) values
  (pg_temp.tg('10'), pg_temp.tg('01'), 'Cliente de las tareas', '111'),
  (pg_temp.tg('11'), pg_temp.tg('01'), 'Otro cliente', '222');
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  (pg_temp.tg('40'), pg_temp.tg('01'), pg_temp.tg('10'), 'Trek', 'Marlin 7');
-- Two jobs with service lines.
insert into public.mechanic_jobs(id, tenant_id, customer_id, status, client_request) values
  (pg_temp.tg('50'), pg_temp.tg('01'), pg_temp.tg('10'), 'EN_CURSO', 'Frenos y transmisión'),
  (pg_temp.tg('51'), pg_temp.tg('01'), pg_temp.tg('11'), 'PENDIENTE', 'Cambios');
insert into public.mechanic_job_items(id, tenant_id, job_id, product_name, item_type, quantity, unit_price) values
  (pg_temp.tg('60'), pg_temp.tg('01'), pg_temp.tg('50'), 'Purga de frenos', 'service', 1, 25000),
  (pg_temp.tg('61'), pg_temp.tg('01'), pg_temp.tg('50'), 'Cambio de cadena', 'service', 1, 8000),
  (pg_temp.tg('62'), pg_temp.tg('01'), pg_temp.tg('51'), 'Ajuste de cambios', 'service', 1, 6000),
  (pg_temp.tg('63'), pg_temp.tg('01'), pg_temp.tg('50'), 'Centrado de rueda', 'service', 1, 7000);

-- T1 with two active services and a note on each; T2 whose service line is
-- deleted before the backup (its link becomes history); T3 assigned to an
-- account that is not eligible in this workshop.
insert into public.smart_tasks(id, tenant_id, title, linked_job_id, visibility, task_kind, created_by) values
  (pg_temp.tg('80'), pg_temp.tg('01'), 'Frenos y cadena', pg_temp.tg('50'), 'team', 'task', pg_temp.tg('91')),
  (pg_temp.tg('83'), pg_temp.tg('01'), 'Rueda trasera', pg_temp.tg('50'), 'team', 'task', pg_temp.tg('91'));
insert into public.smart_tasks(id, tenant_id, title, visibility, task_kind, created_by) values
  (pg_temp.tg('88'), pg_temp.tg('01'), 'Llamar al proveedor', 'team', 'task', pg_temp.tg('91'));
insert into public.smart_task_job_items(id, tenant_id, task_id, job_item_id, job_id, item_name) values
  (pg_temp.tg('81'), pg_temp.tg('01'), pg_temp.tg('80'), pg_temp.tg('60'), pg_temp.tg('50'), 'x'),
  (pg_temp.tg('82'), pg_temp.tg('01'), pg_temp.tg('80'), pg_temp.tg('61'), pg_temp.tg('50'), 'x'),
  (pg_temp.tg('84'), pg_temp.tg('01'), pg_temp.tg('83'), pg_temp.tg('63'), pg_temp.tg('50'), 'x');
select set_config('vinabike.smart_task_cmd', 'create', true);
insert into public.smart_task_job_item_notes(id, tenant_id, task_id, job_item_id, body) values
  (pg_temp.tg('85'), pg_temp.tg('01'), pg_temp.tg('80'), pg_temp.tg('60'), 'Pistón delantero duro'),
  (pg_temp.tg('86'), pg_temp.tg('01'), pg_temp.tg('80'), pg_temp.tg('61'), 'Cadena al 0,75'),
  (pg_temp.tg('87'), pg_temp.tg('01'), pg_temp.tg('83'), pg_temp.tg('63'), 'Rayo cortado');
select set_config('vinabike.smart_task_cmd', '', true);
delete from public.mechanic_job_items where id = pg_temp.tg('63');
set local session_replication_role = replica;
update public.smart_tasks set assigned_to = pg_temp.tg('94'), assigned_at = now(),
  assigned_by = pg_temp.tg('91') where id = pg_temp.tg('88');
set local session_replication_role = origin;
select ok((select invalidated_at is not null and item_name = 'Centrado de rueda'
      from public.smart_task_job_items where id = pg_temp.tg('84'))
    and (select invalidated_at is null and item_name = 'Purga de frenos'
      from public.smart_task_job_items where id = pg_temp.tg('81')),
  'the seed is real: the guard wrote the snapshots and the line delete invalidated its link');

set local role authenticated;
insert into tg_results(label, result) select 'backup',
  public.create_backup(pg_temp.tg('01'), 'Tareas del taller', 'manual', null);
reset role;
create temporary table tg_snapshot as
  select backup_data as data from public.database_backups
   where id = (select (result ->> 'backup_id')::uuid from tg_results where label = 'backup');
select ok((select jsonb_array_length(data -> 'smart_task_job_items') = 3
      and jsonb_array_length(data -> 'smart_task_job_item_notes') = 3
      and jsonb_array_length(data -> 'smart_tasks') = 3 from tg_snapshot),
  'the backup holds the three tasks, their three links and their three notes');

-- Later: a line of T1 is deleted and its job is archived. Then the tasks and
-- the bike are lost without their delete effects.
select pg_temp.tg_claims('91');
delete from public.mechanic_job_items where id = pg_temp.tg('61');
set local session_replication_role = replica;
update public.mechanic_jobs set deleted_at = now() where id = pg_temp.tg('50');
do $lose$
declare v_table record;
begin
  for v_table in select t.table_name, t.root_column from public.workshop_restore_tables_internal() t
                  where t.policy = 'member' and t.root_table in ('bikes', 'smart_tasks')
                  order by t.ord desc loop
    execute format('delete from public.%I where %I = any($1)', v_table.table_name, v_table.root_column)
      using array[pg_temp.tg('40'), pg_temp.tg('80'), pg_temp.tg('83'), pg_temp.tg('88')];
  end loop;
  delete from public.smart_tasks where id in (pg_temp.tg('80'), pg_temp.tg('83'), pg_temp.tg('88'));
  delete from public.bikes where id = pg_temp.tg('40');
end;
$lose$;
set local session_replication_role = origin;
select ok(not exists (select 1 from public.smart_tasks where tenant_id = pg_temp.tg('01'))
    and not exists (select 1 from public.smart_task_job_items where tenant_id = pg_temp.tg('01'))
    and not exists (select 1 from public.bikes where id = pg_temp.tg('40')),
  'the tasks and the bike are lost');

-- A. One tampered backup per relation; each refuses whole.
create function pg_temp.tg_tamper(p_suffix text, p_table text, p_row text, p_patch jsonb)
returns uuid language sql
as $$
  insert into public.database_backups(id, tenant_id, backup_name, backup_type, status, backup_data)
  select pg_temp.tg(p_suffix), pg_temp.tg('01'), 'Manipulado ' || p_suffix, 'manual', 'completed',
    jsonb_set(s.data, array[p_table], (select jsonb_agg(case when x ->> 'id' = pg_temp.tg(p_row)::text
      then x || p_patch else x end) from jsonb_array_elements(s.data -> p_table) x))
  from tg_snapshot s
  returning id
$$;
create function pg_temp.tg_refused(p_label text, p_code text, p_table text) returns boolean
language sql
as $$
  select coalesce((select not (result ->> 'can_restore')::boolean
             and result -> 'refusal' ->> 'code' = p_code
             and result -> 'refusal' ->> 'table' = p_table
           from tg_results where label = p_label || '-preflight'), false)
     and coalesce((select not (result ->> 'success')::boolean
             and result ->> 'error_code' = 'restore_merge_not_safe'
             and result -> 'refusal' ->> 'code' = p_code
           from tg_results where label = p_label || '-apply'), false)
     and not exists (select 1 from public.bikes where id = pg_temp.tg('40'))
     and not exists (select 1 from public.smart_tasks where tenant_id = pg_temp.tg('01'))
$$;

select pg_temp.tg_tamper('70', 'smart_tasks', '80',
  jsonb_build_object('linked_customer_id', pg_temp.tg('10')));
select pg_temp.tg_tamper('71', 'smart_task_job_items', '81',
  jsonb_build_object('job_id', pg_temp.tg('51')));
select pg_temp.tg_tamper('72', 'smart_tasks', '80',
  jsonb_build_object('linked_job_id', pg_temp.tg('51')));
select pg_temp.tg_tamper('73', 'smart_tasks', '80', '{"task_kind": "note"}'::jsonb);
select pg_temp.tg_tamper('74', 'smart_tasks', '88',
  '{"task_kind": "note", "status": "completed", "assigned_to": null, "assigned_at": null, "assigned_by": null}'::jsonb);
select pg_temp.tg_tamper('75', 'smart_tasks', '88', '{"visibility": "private"}'::jsonb);
set local role authenticated;
select pg_temp.tg_run('two-contexts', pg_temp.tg('70'));
select pg_temp.tg_run('line-of-another-job', pg_temp.tg('71'));
select pg_temp.tg_run('task-of-another-job', pg_temp.tg('72'));
select pg_temp.tg_run('note-with-services', pg_temp.tg('73'));
select pg_temp.tg_run('note-lifecycle', pg_temp.tg('74'));
select pg_temp.tg_run('private-assigned', pg_temp.tg('75'));
reset role;
select ok(pg_temp.tg_refused('two-contexts', 'task_primary_context', 'smart_tasks'),
  'a task tied to a job and a customer at once refuses the whole recovery');
select ok(pg_temp.tg_refused('line-of-another-job', 'task_link_job_mismatch', 'smart_task_job_items'),
  'a service whose line belongs to another job than the link says refuses the whole recovery');
select ok(pg_temp.tg_refused('task-of-another-job', 'task_link_job_mismatch', 'smart_task_job_items'),
  'an active service of a job other than the task''s job refuses the whole recovery');
select ok(pg_temp.tg_refused('note-with-services', 'task_note_has_services', 'smart_task_job_items'),
  'a note with service lines refuses the whole recovery');
select ok(pg_temp.tg_refused('note-lifecycle', 'task_note_lifecycle', 'smart_tasks'),
  'a completed note refuses the whole recovery');
select ok(pg_temp.tg_refused('private-assigned', 'task_private_personal', 'smart_tasks'),
  'a private task with an assignee refuses the whole recovery');
select ok((select result ->> 'message' like '%«Frenos y cadena»%«Purga de frenos»%otro trabajo%'
    from tg_results where label = 'line-of-another-job-preflight'),
  'the refusal names the task and the service in workshop words');
select ok(not exists (select 1 from public.workshop_restore_invocations)
    and not exists (select 1 from public.workshop_restore_effect_packets)
    and (select count(*) = 0 from public.database_backups
          where tenant_id = pg_temp.tg('01') and restored_at is not null),
  'no refusal leaves an invocation, a packet or a restore report behind');

-- B–D. The real backup.
set local role authenticated;
select pg_temp.tg_run('history', (select (result ->> 'backup_id')::uuid from tg_results where label = 'backup'));
reset role;
select diag('history apply: ' || (result - 'preserved' - 'restored')::text)
  from tg_results where label = 'history-apply';
select ok((select (result ->> 'can_restore')::boolean from tg_results where label = 'history-preflight')
    and (select (result ->> 'success')::boolean from tg_results where label = 'history-apply'),
  'the real backup recovers');
select ok((select jsonb_path_exists(result,
      '$.not_restored[*] ? (@.table == "smart_task_job_items" && @.reason == "parent_missing" && @.rows == 1
         && exists(@.parents[*] ? (@.table == "mechanic_job_items")))')
    and jsonb_path_exists(result,
      '$.not_restored[*] ? (@.table == "smart_task_job_item_notes" && @.reason == "parent_missing" && @.rows == 1
         && exists(@.parents[*] ? (@.table == "smart_task_job_items")))')
    and jsonb_path_exists(result,
      '$.not_restored[*] ? (@.table == "smart_task_job_items" && @.examples[*] == "Cambio de cadena")')
    from tg_results where label = 'history-apply'),
  'B. the service whose line was deleted later and its note stay out, reported with what they need');
select ok(not exists (select 1 from public.smart_task_job_items where id = pg_temp.tg('82'))
    and not exists (select 1 from public.smart_task_job_item_notes where id = pg_temp.tg('86')),
  'B. the task does not get back a service it no longer has');
select is(
  (select jsonb_agg(x order by x ->> 'id') from tg_snapshot s, lateral (
     select x from jsonb_array_elements(s.data -> 'smart_tasks') x
     union all select x from jsonb_array_elements(s.data -> 'smart_task_job_items') x
       where x ->> 'id' in (pg_temp.tg('81')::text, pg_temp.tg('84')::text)
     union all select x from jsonb_array_elements(s.data -> 'smart_task_job_item_notes') x
       where x ->> 'id' in (pg_temp.tg('85')::text, pg_temp.tg('87')::text)) q),
  (select jsonb_agg(v order by v ->> 'id') from (
     select to_jsonb(r) v from public.smart_tasks r where tenant_id = pg_temp.tg('01')
     union all select to_jsonb(r) from public.smart_task_job_items r where tenant_id = pg_temp.tg('01')
     union all select to_jsonb(r) from public.smart_task_job_item_notes r where tenant_id = pg_temp.tg('01')) q),
  'C/D. tasks, links and notes are back exactly as stored: authorship, times, snapshots, assignee');
select ok((select invalidated_at is not null and item_name = 'Centrado de rueda'
      from public.smart_task_job_items where id = pg_temp.tg('84'))
    and exists (select 1 from public.smart_task_job_item_notes where id = pg_temp.tg('87'))
    and not exists (select 1 from public.mechanic_job_items where id = pg_temp.tg('63'))
    and (select count(*) from public.mechanic_job_items where job_id = pg_temp.tg('50')) = 1,
  'C. the invalidated link is history: back without its line, with its note; no line is created');
select ok((select linked_job_id = pg_temp.tg('50') from public.smart_tasks where id = pg_temp.tg('80'))
    and (select deleted_at is not null from public.mechanic_jobs where id = pg_temp.tg('50'))
    and (select assigned_to = pg_temp.tg('94') from public.smart_tasks where id = pg_temp.tg('88'))
    and not exists (select 1 from public.user_profiles
                     where user_id = pg_temp.tg('94') and tenant_id = pg_temp.tg('01')),
  'D. an archived job and a no-longer-eligible assignee are history, not refusals');
select ok(exists (select 1 from public.bikes where id = pg_temp.tg('40'))
    and not exists (select 1 from public.workshop_restore_invocations)
    and not exists (select 1 from public.workshop_restore_effect_packets),
  'the bike comes back too and no invocation or packet survives');
select * from finish();
rollback;
