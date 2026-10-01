-- C2: the installed public recovery RPCs bring back a lost workshop graph
-- (job, lines, bikes of the job, diagnosis, ficha, memory, history, tasks and
-- their links) from a real create_backup, parents before children, without
-- replaying stock, accounting, notifications, ledgers or messages, and keep
-- everything that exists today. Each block decides one C2 criterion:
--   1. graph recovery with exact content;   2. live data and identity win;
--   3. no effect replay;                    4. preflight writes nothing;
--   5. atomic refusal (another tenant's row after earlier tables were written);
--   6. authority;  7. unreviewed effect refused unexecuted;
--   8. normal writes still fire their effects;  9. cost bound with volume.
-- Local only, synthetic tenants, transaction rolled back.
begin;
select no_plan();
do $guard$
begin
  if exists (select 1 from vault.secrets) then
    raise exception 'restore_workshop_graph: local database only';
  end if;
end;
$guard$;

create temporary table wg_net_before as select count(*) as n from net.http_request_queue;
create temporary table wg_results(label text primary key, result jsonb, ms integer);
grant all on wg_results to authenticated;
create function pg_temp.wg(p_suffix text) returns uuid language sql
as $$ select ('e2899100-0000-4000-8000-0000000000' || p_suffix)::uuid $$;
create function pg_temp.wg_claims(p_user text) returns void language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.wg(p_user), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.wg(p_user)::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end;
$$;
create function pg_temp.wg_backup() returns uuid language sql
as $$ select (result ->> 'backup_id')::uuid from wg_results where label = 'backup' $$;

-- Tenants and people: an administrator and a mechanic of the workshop, and
-- the administrator of another workshop.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values
  (pg_temp.wg('01'), 'Recuperación del taller'),
  (pg_temp.wg('02'), 'Otro taller');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  (pg_temp.wg('91'), 'authenticated', 'authenticated', 'wg-admin@example.invalid', '', now(), '{}', '{}', now(), now()),
  (pg_temp.wg('92'), 'authenticated', 'authenticated', 'wg-otro@example.invalid', '', now(), '{}', '{}', now(), now()),
  (pg_temp.wg('93'), 'authenticated', 'authenticated', 'wg-mecanico@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.wg('91'), pg_temp.wg('01'), 'admin'),
  (pg_temp.wg('92'), pg_temp.wg('02'), 'admin'),
  (pg_temp.wg('93'), pg_temp.wg('01'), 'mechanic');

select pg_temp.wg_claims('91');
insert into public.customers(id, tenant_id, name, phone) values
  (pg_temp.wg('10'), pg_temp.wg('01'), 'Cliente del grafo', '111'),
  (pg_temp.wg('11'), pg_temp.wg('01'), 'Cliente que sigue', '222');
insert into public.customers(id, tenant_id, name, phone)
  select ('e2899100-0000-4000-8000-' || lpad((5000 + g)::text, 12, '0'))::uuid,
    pg_temp.wg('01'), 'Contacto ' || g, '900' || g
  from generate_series(1, 1000) g;
select pg_temp.wg_claims('92');
insert into public.customers(id, tenant_id, name, phone) values
  (pg_temp.wg('12'), pg_temp.wg('02'), 'Cliente de otro taller', '333');
select pg_temp.wg_claims('91');
insert into public.products(id, tenant_id, name, product_type, price) values
  (pg_temp.wg('30'), pg_temp.wg('01'), 'Rotor 160 mm', 'product', 32990),
  (pg_temp.wg('31'), pg_temp.wg('01'), 'Purga de frenos', 'service', 25000);
insert into public.sales_invoices(id, tenant_id, invoice_number, customer_id, customer_name, status,
  source, subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment) values
  (pg_temp.wg('35'), pg_temp.wg('01'), 'WG-35', pg_temp.wg('10'), 'Cliente del grafo', 'draft',
   'manual_sale', 57990, 57990, 0, 57990, 0, 57990, 'no_tax');
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  (pg_temp.wg('40'), pg_temp.wg('01'), pg_temp.wg('10'), 'Trek', 'Marlin 7'),
  (pg_temp.wg('41'), pg_temp.wg('01'), pg_temp.wg('11'), 'Scott', 'Scale 970');

-- The graph that will be lost: the mechanic opens the job (created_by and
-- status time are the mechanic's, not the restoring administrator's).
select pg_temp.wg_claims('93');
insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id, status, client_request,
  diagnosis, invoice_id) values
  (pg_temp.wg('50'), pg_temp.wg('01'), pg_temp.wg('10'), pg_temp.wg('40'), 'EN_CURSO',
   'Frena poco adelante', 'Pastillas cristalizadas y rotor bajo el mínimo', pg_temp.wg('35'));
insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id) values
  (pg_temp.wg('55'), pg_temp.wg('01'), pg_temp.wg('50'), pg_temp.wg('40'));
insert into public.mechanic_job_items(id, tenant_id, job_id, job_bike_id, product_id, product_name,
  item_type, quantity, unit_price) values
  (pg_temp.wg('60'), pg_temp.wg('01'), pg_temp.wg('50'), pg_temp.wg('55'), pg_temp.wg('30'),
   'Rotor 160 mm', 'product', 1, 32990),
  (pg_temp.wg('61'), pg_temp.wg('01'), pg_temp.wg('50'), pg_temp.wg('55'), null,
   'Purga de frenos', 'service', 1, 25000);
update public.mechanic_job_items set service_product_id = pg_temp.wg('31') where id = pg_temp.wg('61');
insert into public.mechanic_job_tasks(id, tenant_id, job_id, task_name, is_standalone) values
  (pg_temp.wg('65'), pg_temp.wg('01'), pg_temp.wg('50'), 'Medir el rotor trasero', true);
-- A job that exists before and after the backup, with many lines.
select pg_temp.wg_claims('91');
insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id, status, client_request) values
  (pg_temp.wg('51'), pg_temp.wg('01'), pg_temp.wg('11'), pg_temp.wg('41'), 'PENDIENTE', 'Mantención');
insert into public.mechanic_job_items(id, tenant_id, job_id, product_name, item_type, quantity, unit_price)
  select case g when 1 then pg_temp.wg('62') when 2 then pg_temp.wg('63')
           else ('e2899100-0000-4000-8000-' || lpad((7000 + g)::text, 12, '0'))::uuid end,
    pg_temp.wg('01'), pg_temp.wg('51'), 'Línea ' || g, 'product', 1, 1000
  from generate_series(1, 300) g;

-- Ficha, memory and history of the bike.
insert into public.bike_profiles(id, tenant_id, bike_id) values
  (pg_temp.wg('70'), pg_temp.wg('01'), pg_temp.wg('40'));
insert into public.bike_component_lifecycles(id, tenant_id, bike_id, system_key, component_slot_key,
  component_label, location_key, job_id) values
  (pg_temp.wg('71'), pg_temp.wg('01'), pg_temp.wg('40'), 'brakes', 'rotor', 'Rotor 160 mm', 'front',
   pg_temp.wg('50'));
insert into public.bike_interventions(id, tenant_id, bike_id, system_key, intervention_type, title,
  to_lifecycle_id, job_id, mechanic_job_item_id, location_key) values
  (pg_temp.wg('72'), pg_temp.wg('01'), pg_temp.wg('40'), 'brakes', 'replacement', 'Cambio de rotor',
   pg_temp.wg('71'), pg_temp.wg('50'), pg_temp.wg('60'), 'front');
insert into public.bike_observations(id, tenant_id, bike_id, system_key, observation_kind,
  observation_key, title, lifecycle_id, location_key) values
  (pg_temp.wg('73'), pg_temp.wg('01'), pg_temp.wg('40'), 'brakes', 'measurement', 'rotor_thickness',
   'Grosor del rotor 1,6 mm', pg_temp.wg('71'), 'front');
insert into public.bike_system_states(id, tenant_id, bike_id, system_key, overall_status, job_id) values
  (pg_temp.wg('74'), pg_temp.wg('01'), pg_temp.wg('40'), 'brakes', 'attention', pg_temp.wg('50'));
insert into public.bike_events(id, tenant_id, bike_id, event_type, event_category, title, job_id) values
  (pg_temp.wg('75'), pg_temp.wg('01'), pg_temp.wg('40'), 'job_opened', 'visit', 'Ingreso al taller',
   pg_temp.wg('50'));
insert into public.bike_technical_fact_patches(id, tenant_id, operation_key, payload_hash, source,
  bike_id, profile_id, job_id) values
  (pg_temp.wg('76'), pg_temp.wg('01'), 'wg-76', 'wg-hash', 'service_wizard', pg_temp.wg('40'),
   pg_temp.wg('70'), pg_temp.wg('50'));

-- The task of the job, its service link, its note and its reader state.
insert into public.smart_tasks(id, tenant_id, title, linked_job_id, visibility, task_kind, created_by) values
  (pg_temp.wg('80'), pg_temp.wg('01'), 'Purgar y medir', pg_temp.wg('50'), 'team', 'task', pg_temp.wg('91'));
insert into public.smart_task_job_items(id, tenant_id, task_id, job_item_id, job_id, item_name) values
  (pg_temp.wg('81'), pg_temp.wg('01'), pg_temp.wg('80'), pg_temp.wg('61'), pg_temp.wg('50'), 'x');
select set_config('vinabike.smart_task_cmd', 'create', true);
insert into public.smart_task_job_item_notes(id, tenant_id, task_id, job_item_id, body) values
  (pg_temp.wg('82'), pg_temp.wg('01'), pg_temp.wg('80'), pg_temp.wg('61'), 'Ojo con el pistón delantero');
select set_config('vinabike.smart_task_cmd', '', true);
insert into public.smart_task_user_state(task_id, user_id, tenant_id, pinned_at) values
  (pg_temp.wg('80'), pg_temp.wg('91'), pg_temp.wg('01'), now());

-- What the backup must bring back, as it is at capture time.
create temporary table wg_graph as
select 'mechanic_jobs' t, to_jsonb(r) v from public.mechanic_jobs r where id = pg_temp.wg('50')
union all select 'mechanic_job_bikes', to_jsonb(r) from public.mechanic_job_bikes r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_items', to_jsonb(r) from public.mechanic_job_items r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_tasks', to_jsonb(r) from public.mechanic_job_tasks r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_timeline', to_jsonb(r) from public.mechanic_job_timeline r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_status_transitions', to_jsonb(r) from public.mechanic_job_status_transitions r where job_id = pg_temp.wg('50')
union all select 'bikes', to_jsonb(r) from public.bikes r where id = pg_temp.wg('40')
union all select 'bike_profiles', to_jsonb(r) from public.bike_profiles r where bike_id = pg_temp.wg('40')
union all select 'bike_component_lifecycles', to_jsonb(r) from public.bike_component_lifecycles r where bike_id = pg_temp.wg('40')
union all select 'bike_interventions', to_jsonb(r) from public.bike_interventions r where bike_id = pg_temp.wg('40')
union all select 'bike_observations', to_jsonb(r) from public.bike_observations r where bike_id = pg_temp.wg('40')
union all select 'bike_system_states', to_jsonb(r) from public.bike_system_states r where bike_id = pg_temp.wg('40')
union all select 'bike_events', to_jsonb(r) from public.bike_events r where bike_id = pg_temp.wg('40')
union all select 'bike_technical_fact_patches', to_jsonb(r) from public.bike_technical_fact_patches r where bike_id = pg_temp.wg('40')
union all select 'smart_tasks', to_jsonb(r) from public.smart_tasks r where id = pg_temp.wg('80')
union all select 'smart_task_job_items', to_jsonb(r) from public.smart_task_job_items r where task_id = pg_temp.wg('80')
union all select 'smart_task_job_item_notes', to_jsonb(r) from public.smart_task_job_item_notes r where task_id = pg_temp.wg('80')
union all select 'smart_task_user_state', to_jsonb(r) from public.smart_task_user_state r where task_id = pg_temp.wg('80')
union all select 'smart_task_events', to_jsonb(r) from public.smart_task_events r where task_id = pg_temp.wg('80');
select ok((select count(distinct t) = 19 and count(*) filter (where t = 'mechanic_job_timeline') > 0
    and count(*) filter (where t = 'mechanic_job_status_transitions') > 0
    and count(*) filter (where t = 'smart_task_events') > 0 from wg_graph),
  'the seeded graph is real: its own triggers wrote timeline, status ledger and task history');

set local role authenticated;
insert into wg_results(label, result) select 'backup',
  public.create_backup(pg_temp.wg('01'), 'Grafo del taller', 'manual', null);
reset role;
select ok((select (result ->> 'success')::boolean from wg_results where label = 'backup')
    and (select summary ->> 'capture_contract' = 'workshop_graph_v1'
           from public.database_backups where id = pg_temp.wg_backup()),
  'create_backup captures the workshop graph contract');
create temporary table wg_snapshot as
  select backup_data as data from public.database_backups where id = pg_temp.wg_backup();

-- Later: a contact corrected, a line removed from a job that still exists,
-- a new job. All of it must survive the recovery.
select pg_temp.wg_claims('91');
update public.customers set phone = '555' where id = pg_temp.wg('10');
delete from public.mechanic_job_items where id = pg_temp.wg('63');
insert into public.mechanic_jobs(id, tenant_id, customer_id, status, client_request) values
  (pg_temp.wg('52'), pg_temp.wg('01'), pg_temp.wg('11'), 'PENDIENTE', 'Trabajo posterior');
insert into public.mechanic_job_items(id, tenant_id, job_id, product_name, item_type, quantity, unit_price) values
  (pg_temp.wg('64'), pg_temp.wg('01'), pg_temp.wg('52'), 'Cámara 29', 'product', 1, 6990);

-- Loss: the job, its bike, its task and the draft invoice vanish without
-- their delete effects (a purge gone wrong), with their notifications.
set local session_replication_role = replica;
do $lose$
declare v_table record;
begin
  for v_table in select t.table_name, t.root_column from public.workshop_restore_tables_internal() t
                  where t.policy = 'member' order by t.ord desc loop
    execute format('delete from public.%I where %I = any($1)', v_table.table_name, v_table.root_column)
      using array[pg_temp.wg('50'), pg_temp.wg('40'), pg_temp.wg('80')];
  end loop;
  delete from public.bike_technical_fact_patches where job_id = pg_temp.wg('50');
  delete from public.smart_tasks where id = pg_temp.wg('80');
  delete from public.mechanic_jobs where id = pg_temp.wg('50');
  delete from public.bikes where id = pg_temp.wg('40');
  delete from public.sales_invoices where id = pg_temp.wg('35');
  delete from public.erp_notifications where entity_id in (pg_temp.wg('50'), pg_temp.wg('80'));
end;
$lose$;
set local session_replication_role = origin;
select ok(not exists (select 1 from public.mechanic_jobs where id = pg_temp.wg('50'))
    and not exists (select 1 from public.mechanic_job_timeline where job_id = pg_temp.wg('50'))
    and not exists (select 1 from public.bike_profiles where bike_id = pg_temp.wg('40'))
    and not exists (select 1 from public.smart_task_events where task_id = pg_temp.wg('80')),
  'the graph is lost');

create temporary table wg_effects_before as select
  (select count(*) from public.erp_notifications where tenant_id = pg_temp.wg('01')) as notifications,
  (select count(*) from public.mechanic_job_delivery_events where tenant_id = pg_temp.wg('01')) as deliveries,
  (select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]') from public.journal_entries e where tenant_id = pg_temp.wg('01')) as journals,
  (select coalesce(jsonb_agg(to_jsonb(s) order by s.id), '[]') from public.stock_movements s where tenant_id = pg_temp.wg('01')) as stock,
  (select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]') from public.sales_invoices i where tenant_id = pg_temp.wg('01')) as invoices,
  (select coalesce(jsonb_agg(to_jsonb(p) order by p.id), '[]') from public.products p where tenant_id = pg_temp.wg('01')) as products,
  (select count(*) from public.messages) as messages;

-- 4. Preflight: the real engine, rolled back.
set local statement_timeout = '8s';
set local role authenticated;
insert into wg_results(label, result, ms)
  select 'preflight', r, round(extract(epoch from clock_timestamp() - t0) * 1000)
  from (select clock_timestamp() t0) s,
  lateral (select public.restore_backup_merge_preflight(pg_temp.wg_backup(), pg_temp.wg('01')) r) p;
reset role;
select diag('preflight ' || ms || ' ms: ' || (result - 'preserved')::text) from wg_results where label = 'preflight';
select ok((select (result ->> 'can_restore')::boolean from wg_results where label = 'preflight'),
  'preflight allows the recovery');
select ok((select jsonb_path_exists(result, '$.restored[*] ? (@.table == "mechanic_jobs" && @.rows == 1)')
    and jsonb_path_exists(result, '$.restored[*] ? (@.table == "mechanic_job_items" && @.rows == 2)')
    and jsonb_path_exists(result, '$.restored[*] ? (@.table == "smart_tasks" && @.rows == 1)')
    and jsonb_path_exists(result, '$.restored[*] ? (@.table == "bikes" && @.rows == 1)')
    and jsonb_path_exists(result, '$.links_dropped[*] ? (@.table == "mechanic_jobs" && @.parent_table == "sales_invoices" && @.rows == 1)')
    and jsonb_path_exists(result, '$.not_restored[*] ? (@.table == "mechanic_job_items" && @.reason == "root_live" && @.rows == 1)')
    from wg_results where label = 'preflight'),
  'preflight names what comes back, the dropped invoice link and the line of a job that exists today');
select ok(not exists (select 1 from public.mechanic_jobs where id = pg_temp.wg('50'))
    and not exists (select 1 from public.bikes where id = pg_temp.wg('40'))
    and (select count(*) from public.erp_notifications where tenant_id = pg_temp.wg('01'))
      = (select notifications from wg_effects_before)
    and not exists (select 1 from public.workshop_restore_invocations)
    and not exists (select 1 from public.workshop_restore_effect_packets),
  'preflight leaves no row, notification, invocation or packet behind');

-- 1–3. Apply through the public RPC.
set local role authenticated;
insert into wg_results(label, result, ms)
  select 'apply', r, round(extract(epoch from clock_timestamp() - t0) * 1000)
  from (select clock_timestamp() t0) s,
  lateral (select public.restore_backup_merge(pg_temp.wg_backup(), pg_temp.wg('01')) r) p;
reset role;
select diag('apply ' || ms || ' ms: ' || (result - 'preserved' - 'restored')::text) from wg_results where label = 'apply';
select ok((select (result ->> 'success')::boolean from wg_results where label = 'apply'),
  'the public RPC recovers the graph');

-- Exact content, table by table (the invoice link is the reported drop).
create temporary table wg_after as
select 'mechanic_jobs' t, to_jsonb(r) v from public.mechanic_jobs r where id = pg_temp.wg('50')
union all select 'mechanic_job_bikes', to_jsonb(r) from public.mechanic_job_bikes r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_items', to_jsonb(r) from public.mechanic_job_items r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_tasks', to_jsonb(r) from public.mechanic_job_tasks r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_timeline', to_jsonb(r) from public.mechanic_job_timeline r where job_id = pg_temp.wg('50')
union all select 'mechanic_job_status_transitions', to_jsonb(r) from public.mechanic_job_status_transitions r where job_id = pg_temp.wg('50')
union all select 'bikes', to_jsonb(r) from public.bikes r where id = pg_temp.wg('40')
union all select 'bike_profiles', to_jsonb(r) from public.bike_profiles r where bike_id = pg_temp.wg('40')
union all select 'bike_component_lifecycles', to_jsonb(r) from public.bike_component_lifecycles r where bike_id = pg_temp.wg('40')
union all select 'bike_interventions', to_jsonb(r) from public.bike_interventions r where bike_id = pg_temp.wg('40')
union all select 'bike_observations', to_jsonb(r) from public.bike_observations r where bike_id = pg_temp.wg('40')
union all select 'bike_system_states', to_jsonb(r) from public.bike_system_states r where bike_id = pg_temp.wg('40')
union all select 'bike_events', to_jsonb(r) from public.bike_events r where bike_id = pg_temp.wg('40')
union all select 'bike_technical_fact_patches', to_jsonb(r) from public.bike_technical_fact_patches r where bike_id = pg_temp.wg('40')
union all select 'smart_tasks', to_jsonb(r) from public.smart_tasks r where id = pg_temp.wg('80')
union all select 'smart_task_job_items', to_jsonb(r) from public.smart_task_job_items r where task_id = pg_temp.wg('80')
union all select 'smart_task_job_item_notes', to_jsonb(r) from public.smart_task_job_item_notes r where task_id = pg_temp.wg('80')
union all select 'smart_task_user_state', to_jsonb(r) from public.smart_task_user_state r where task_id = pg_temp.wg('80')
union all select 'smart_task_events', to_jsonb(r) from public.smart_task_events r where task_id = pg_temp.wg('80');
select is(
  (select jsonb_agg(v order by t, v::text) from (
     select t, case when t = 'mechanic_jobs' then v || '{"invoice_id": null}' else v end v from wg_graph) g),
  (select jsonb_agg(v order by t, v::text) from wg_after),
  'every row of the graph is back byte for byte: 19 tables, links, diagnosis, authorship and times');
select ok((select v ->> 'created_by' = pg_temp.wg('93')::text and v ->> 'diagnosis' like 'Pastillas%'
    from wg_after where t = 'mechanic_jobs'),
  'the job keeps its mechanic as author and its diagnosis');

-- 2. What exists today wins.
select is((select phone from public.customers where id = pg_temp.wg('10')), '555',
  'a contact corrected after the backup is not reverted');
select ok(not exists (select 1 from public.mechanic_job_items where id = pg_temp.wg('63'))
    and (select count(*) from public.mechanic_job_items where job_id = pg_temp.wg('51')) = 299,
  'a job that exists today keeps its own lines: the removed line does not come back');
select ok(exists (select 1 from public.mechanic_jobs where id = pg_temp.wg('52'))
    and exists (select 1 from public.mechanic_job_items where id = pg_temp.wg('64')),
  'the later job and its line are preserved');

-- 3. No replay.
select ok((select count(*) from public.erp_notifications where tenant_id = pg_temp.wg('01'))
      = (select notifications from wg_effects_before)
    and (select count(*) from public.mechanic_job_delivery_events where tenant_id = pg_temp.wg('01'))
      = (select deliveries from wg_effects_before)
    and (select coalesce(jsonb_agg(to_jsonb(e) order by e.id), '[]') from public.journal_entries e
          where tenant_id = pg_temp.wg('01')) = (select journals from wg_effects_before)
    and (select coalesce(jsonb_agg(to_jsonb(s) order by s.id), '[]') from public.stock_movements s
          where tenant_id = pg_temp.wg('01')) = (select stock from wg_effects_before)
    and (select coalesce(jsonb_agg(to_jsonb(i) order by i.id), '[]') from public.sales_invoices i
          where tenant_id = pg_temp.wg('01')) = (select invoices from wg_effects_before)
    and (select coalesce(jsonb_agg(to_jsonb(p) order by p.id), '[]') from public.products p
          where tenant_id = pg_temp.wg('01')) = (select products from wg_effects_before)
    and (select count(*) from public.messages) = (select messages from wg_effects_before),
  'no notification, delivery, journal, stock, invoice, product or message was produced');
select ok((select backup_data from public.database_backups where id = pg_temp.wg_backup())
      = (select data from wg_snapshot)
    and (select restore_report ->> 'recovery_mode' from public.database_backups where id = pg_temp.wg_backup())
      = 'restore_missing_keep_live',
  'the backup is untouched and the report is stored');
select ok(not exists (select 1 from public.workshop_restore_invocations)
    and not exists (select 1 from public.workshop_restore_effect_packets),
  'no invocation or packet survives a committed recovery');

-- 5. Atomic refusal: the task (written last) points at another tenant's
-- customer; bikes and jobs written earlier in that run must not survive.
set local session_replication_role = replica;
delete from public.smart_task_user_state where task_id = pg_temp.wg('80');
delete from public.smart_task_job_item_notes where task_id = pg_temp.wg('80');
delete from public.smart_task_job_items where task_id = pg_temp.wg('80');
delete from public.smart_task_events where task_id = pg_temp.wg('80');
delete from public.smart_tasks where id = pg_temp.wg('80');
delete from public.bike_technical_fact_patches where bike_id = pg_temp.wg('40');
delete from public.bike_events where bike_id = pg_temp.wg('40');
delete from public.bike_system_states where bike_id = pg_temp.wg('40');
delete from public.bike_observations where bike_id = pg_temp.wg('40');
delete from public.bike_interventions where bike_id = pg_temp.wg('40');
delete from public.bike_component_lifecycles where bike_id = pg_temp.wg('40');
delete from public.bike_profiles where bike_id = pg_temp.wg('40');
delete from public.mechanic_job_tasks where job_id = pg_temp.wg('50');
delete from public.mechanic_job_items where job_id = pg_temp.wg('50');
delete from public.mechanic_job_bikes where job_id = pg_temp.wg('50');
delete from public.mechanic_job_status_transitions where job_id = pg_temp.wg('50');
delete from public.mechanic_job_timeline where job_id = pg_temp.wg('50');
delete from public.mechanic_jobs where id = pg_temp.wg('50');
delete from public.bikes where id = pg_temp.wg('40');
set local session_replication_role = origin;
insert into public.database_backups(id, tenant_id, backup_name, backup_type, status, backup_data)
  select pg_temp.wg('96'), pg_temp.wg('01'), 'Manipulado', 'manual', 'completed',
    jsonb_set(data, '{smart_tasks}', (select jsonb_agg(case when x ->> 'id' = pg_temp.wg('80')::text
      then x || jsonb_build_object('linked_job_id', null, 'linked_customer_id', pg_temp.wg('12'))
      else x end) from jsonb_array_elements(data -> 'smart_tasks') x))
  from wg_snapshot;
set local role authenticated;
insert into wg_results(label, result) select 'tampered-preflight',
  public.restore_backup_merge_preflight(pg_temp.wg('96'), pg_temp.wg('01'));
insert into wg_results(label, result) select 'tampered-apply',
  public.restore_backup_merge(pg_temp.wg('96'), pg_temp.wg('01'));
reset role;
select ok((select not (result ->> 'can_restore')::boolean
      and result -> 'refusal' ->> 'code' = 'other_tenant_parent'
      and result -> 'refusal' ->> 'table' = 'smart_tasks'
    from wg_results where label = 'tampered-preflight')
    and (select not (result ->> 'success')::boolean and result ->> 'error_code' = 'restore_merge_not_safe'
    from wg_results where label = 'tampered-apply'),
  'another tenant''s parent is refused concretely by preflight and apply');
select ok(not exists (select 1 from public.bikes where id = pg_temp.wg('40'))
    and not exists (select 1 from public.mechanic_jobs where id = pg_temp.wg('50'))
    and not exists (select 1 from public.mechanic_job_items where job_id = pg_temp.wg('50'))
    and not exists (select 1 from public.smart_tasks where id = pg_temp.wg('80')),
  'the refusal is atomic: the bike and job written earlier in the same run are gone');

-- 7. An unreviewed INSERT effect is refused and never executed.
create temporary table wg_unreviewed(value boolean);
grant all on wg_unreviewed to authenticated;
create function pg_temp.wg_unreviewed_effect() returns trigger language plpgsql
as $$ begin insert into wg_unreviewed values (true); return new; end $$;
create trigger wg_unreviewed_effect before insert on public.bike_events
  for each row execute function pg_temp.wg_unreviewed_effect();
set local role authenticated;
insert into wg_results(label, result) select 'unreviewed-preflight',
  public.restore_backup_merge_preflight(pg_temp.wg_backup(), pg_temp.wg('01'));
insert into wg_results(label, result) select 'unreviewed-apply',
  public.restore_backup_merge(pg_temp.wg_backup(), pg_temp.wg('01'));
reset role;
select ok((select not (result ->> 'can_restore')::boolean
      and result -> 'refusal' ->> 'code' = 'unreviewed_effect'
    from wg_results where label = 'unreviewed-preflight')
    and (select not (result ->> 'success')::boolean from wg_results where label = 'unreviewed-apply')
    and (select count(*) = 0 from wg_unreviewed)
    and not exists (select 1 from public.bikes where id = pg_temp.wg('40')),
  'an unreviewed trigger refuses the recovery without running it or writing anything');
drop trigger wg_unreviewed_effect on public.bike_events;

-- 6. Authority.
select pg_temp.wg_claims('92');
set local role authenticated;
select throws_ok(format('select public.restore_backup_merge_preflight(%L, %L)', pg_temp.wg_backup(), pg_temp.wg('01')),
  '42501', null, 'another workshop''s administrator cannot read the plan');
select throws_ok(format('select public.restore_backup_merge(%L, %L)', pg_temp.wg_backup(), pg_temp.wg('01')),
  '42501', null, 'another workshop''s administrator cannot recover');
select ok(not has_function_privilege('public.workshop_restore_run_internal(jsonb,uuid)', 'EXECUTE')
    and not has_function_privilege('public.workshop_restore_suppress_internal(uuid,regclass)', 'EXECUTE')
    and not has_table_privilege('public.workshop_restore_effect_packets', 'INSERT')
    and not public.workshop_restore_effect_suppressed('public.mechanic_jobs'::regclass, 'trg_mechanic_jobs_change'),
  'a client can neither run the engine nor open a packet; the hook answers false to it');
reset role;

-- 8. Outside a recovery every hooked effect still fires.
select pg_temp.wg_claims('91');
set local role authenticated;
insert into public.mechanic_jobs(id, tenant_id, customer_id, status, client_request) values
  (pg_temp.wg('53'), pg_temp.wg('01'), pg_temp.wg('11'), 'PENDIENTE', 'Trabajo normal');
reset role;
select ok(exists (select 1 from public.mechanic_job_timeline where job_id = pg_temp.wg('53') and event_type = 'created')
    and exists (select 1 from public.mechanic_job_status_transitions where job_id = pg_temp.wg('53'))
    and exists (select 1 from public.erp_notifications where entity_id = pg_temp.wg('53'))
    and (select created_by = pg_temp.wg('91') from public.mechanic_jobs where id = pg_temp.wg('53')),
  'a normal job insert still writes its timeline, ledger, notification and author');

-- 9. Cost: 1,002 contacts and 300 lines of a live job in the backup.
select ok((select ms < 3000 from wg_results where label = 'preflight')
    and (select ms < 3000 from wg_results where label = 'apply'),
  'preflight and recovery with volume each finish well inside the 8 s client timeout');

select is((select count(*) from net.http_request_queue), (select n from wg_net_before),
  'no outbound request was queued');
select * from finish();
rollback;
