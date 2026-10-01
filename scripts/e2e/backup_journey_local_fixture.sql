-- C2 por la app (PLANS.md, 2026-09-30): recuperar desde Configuración →
-- Respaldos un trabajo perdido, con su bici y su tarea, contra la base local.
-- Lo usa scripts/e2e/run_android_local_journey.sh --journey backup --surface web.
--
--   setup      taller, la operadora (admin) y la mecánica que abrió el
--              trabajo; el grafo del taller; un respaldo real (create_backup);
--              lo que cambió después; y la pérdida del grafo
--   objects    sin bytes (el recorrido no sube archivos)
--   readback   lo que dejó la recuperación, con 1/0 al final
--   teardown   todo lo sintético
--
-- La historia que el readback exige:
--   1. La mecánica abre el trabajo (diagnóstico, dos líneas, la bici en el
--      trabajo), la ficha y la memoria de la bici, y una tarea con su servicio
--      y una nota. Sus propios disparadores dejan historial y libro de estados.
--   2. La operadora respalda. Después se corrige el teléfono de la clienta,
--      otro trabajo que sigue vivo pierde una línea y nace un trabajo nuevo.
--   3. El trabajo, su bici y su tarea se pierden sin sus efectos de borrado.
--   4. En la app, la revisión dice qué vuelve y qué no; Restaurar lo trae.
--   5. Cada fila del grafo del respaldo está de vuelta idéntica (autoría,
--      tiempos, vínculos), el teléfono corregido y el trabajo nuevo siguen, la
--      línea del trabajo vivo no vuelve y la recuperación no produjo avisos.
--
-- Alcance fijo: taller e2898000-0000-4000-8000-000000000041, cuentas
-- respaldo-ui-e2e@ y respaldo-ui-e2e-otra@vinabike.invalid (las crea el
-- lanzador por la API de Auth). No toca los talleres de los otros recorridos.
\set ON_ERROR_STOP on
\getenv fixture_mode BACKUP_E2E_FIXTURE_MODE
\if :{?fixture_mode}
\else
select 1 / 0 as falta_backup_e2e_fixture_mode;
\endif

select :'fixture_mode' = 'setup' as is_setup,
       :'fixture_mode' = 'objects' as is_objects,
       :'fixture_mode' = 'readback' as is_readback,
       :'fixture_mode' = 'teardown' as is_teardown,
       :'fixture_mode' in ('setup', 'objects', 'readback', 'teardown') as is_known
\gset

\if :is_known
\else
select 1 / 0 as modo_desconocido;
\endif

\if :is_setup
begin;

do $setup$
begin
  if (select count(*) from auth.users
       where lower(email) in ('respaldo-ui-e2e@vinabike.invalid',
                              'respaldo-ui-e2e-otra@vinabike.invalid')) <> 2 then
    raise exception 'Faltan las dos cuentas sintéticas (las crea el lanzador por la API de Auth)';
  end if;
  if exists (select 1 from public.tenants
              where id = 'e2898000-0000-4000-8000-000000000041') then
    raise exception 'Queda el taller sintético de otra corrida: correr antes la retirada';
  end if;
end;
$setup$;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values
  ('e2898000-0000-4000-8000-000000000041', 'RESPALDO UI E2E - SYNTHETIC ONLY');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
)
select 'e2898000-0000-4000-8000-000000000422', 'e2898000-0000-4000-8000-000000000041',
       account.id, 'R-002', 'Javiera', 'Soto', 'Mecánica', 'full_time', 'active', 0
  from auth.users account where lower(account.email) = 'respaldo-ui-e2e-otra@vinabike.invalid';
insert into public.user_profiles (user_id, tenant_id, role, permissions, employee_id)
select account.id, 'e2898000-0000-4000-8000-000000000041',
       case when lower(account.email) = 'respaldo-ui-e2e@vinabike.invalid' then 'admin' else 'mechanic' end,
       '{}'::jsonb,
       case when lower(account.email) = 'respaldo-ui-e2e-otra@vinabike.invalid'
            then 'e2898000-0000-4000-8000-000000000422'::uuid end
  from auth.users account
 where lower(account.email) in ('respaldo-ui-e2e@vinabike.invalid',
                                'respaldo-ui-e2e-otra@vinabike.invalid');

-- 1. Lo que la mecánica hace, con su sesión.
select set_config('request.jwt.claims', jsonb_build_object('sub', account.id, 'role', 'authenticated')::text, true),
       set_config('request.jwt.claim.sub', account.id::text, true),
       set_config('request.jwt.claim.role', 'authenticated', true)
  from auth.users account where lower(account.email) = 'respaldo-ui-e2e-otra@vinabike.invalid';

insert into public.customers (id, tenant_id, name, phone) values
  ('e2898000-0000-4000-8000-000000000410', 'e2898000-0000-4000-8000-000000000041',
   'Camila Rojas', '+56 9 5550 0410');
insert into public.bikes (id, tenant_id, customer_id, brand, model, color) values
  ('e2898000-0000-4000-8000-000000000420', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000410', 'Trek', 'Marlin 7', 'Azul');
insert into public.products (id, tenant_id, name, product_type, price) values
  ('e2898000-0000-4000-8000-000000000430', 'e2898000-0000-4000-8000-000000000041',
   'Rotor 160 mm', 'product', 32990),
  ('e2898000-0000-4000-8000-000000000431', 'e2898000-0000-4000-8000-000000000041',
   'Purga de frenos', 'service', 25000);
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, status, client_request, diagnosis) values
  ('e2898000-0000-4000-8000-000000000450', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000410', 'e2898000-0000-4000-8000-000000000420',
   'EN_CURSO', 'Frena poco adelante',
   'Pastillas cristalizadas y rotor delantero bajo el mínimo (1,6 mm)'),
  ('e2898000-0000-4000-8000-000000000451', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000410', null, 'PENDIENTE', 'Mantención de la rueda', null);
-- La ficha del trabajo lee solicitud y diagnóstico de la bici del trabajo,
-- como los guarda la app; el trabajo conserva también su copia.
insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id, work_requested, diagnosis) values
  ('e2898000-0000-4000-8000-000000000455', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000450', 'e2898000-0000-4000-8000-000000000420',
   'Frena poco adelante', 'Pastillas cristalizadas y rotor delantero bajo el mínimo (1,6 mm)');
insert into public.mechanic_job_items (id, tenant_id, job_id, job_bike_id, product_id,
  service_product_id, product_name, item_type, quantity, unit_price) values
  ('e2898000-0000-4000-8000-000000000460', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000450', 'e2898000-0000-4000-8000-000000000455',
   'e2898000-0000-4000-8000-000000000430', null, 'Rotor 160 mm', 'product', 1, 32990),
  ('e2898000-0000-4000-8000-000000000461', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000450', 'e2898000-0000-4000-8000-000000000455',
   null, 'e2898000-0000-4000-8000-000000000431', 'Purga de frenos', 'service', 1, 25000),
  ('e2898000-0000-4000-8000-000000000462', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000451', null, null, null, 'Cámara 29', 'product', 1, 6990),
  ('e2898000-0000-4000-8000-000000000463', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000451', null, null, null, 'Parche', 'product', 2, 990);
insert into public.bike_profiles (id, tenant_id, bike_id) values
  ('e2898000-0000-4000-8000-000000000470', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000420');
insert into public.bike_component_lifecycles (id, tenant_id, bike_id, system_key,
  component_slot_key, component_label, location_key, job_id) values
  ('e2898000-0000-4000-8000-000000000471', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000420', 'brakes', 'rotor', 'Rotor 160 mm', 'front',
   'e2898000-0000-4000-8000-000000000450');
insert into public.bike_observations (id, tenant_id, bike_id, system_key, observation_kind,
  observation_key, title, lifecycle_id, location_key) values
  ('e2898000-0000-4000-8000-000000000473', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000420', 'brakes', 'measurement', 'rotor_thickness',
   'Rotor delantero 1,6 mm', 'e2898000-0000-4000-8000-000000000471', 'front');
insert into public.bike_system_states (id, tenant_id, bike_id, system_key, overall_status, job_id) values
  ('e2898000-0000-4000-8000-000000000474', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000420', 'brakes', 'attention',
   'e2898000-0000-4000-8000-000000000450');
insert into public.bike_events (id, tenant_id, bike_id, event_type, event_category, title, job_id) values
  ('e2898000-0000-4000-8000-000000000475', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000420', 'job_opened', 'visit', 'Ingreso al taller',
   'e2898000-0000-4000-8000-000000000450');
insert into public.smart_tasks (id, tenant_id, title, linked_job_id, visibility, task_kind, created_by)
select 'e2898000-0000-4000-8000-000000000480', 'e2898000-0000-4000-8000-000000000041',
       'Purgar y medir el rotor', 'e2898000-0000-4000-8000-000000000450', 'team', 'task', account.id
  from auth.users account where lower(account.email) = 'respaldo-ui-e2e-otra@vinabike.invalid';
insert into public.smart_task_job_items (id, tenant_id, task_id, job_item_id, job_id, item_name) values
  ('e2898000-0000-4000-8000-000000000481', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000480', 'e2898000-0000-4000-8000-000000000461',
   'e2898000-0000-4000-8000-000000000450', 'x');
select set_config('vinabike.smart_task_cmd', 'create', true);
insert into public.smart_task_job_item_notes (id, tenant_id, task_id, job_item_id, body) values
  ('e2898000-0000-4000-8000-000000000482', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000480', 'e2898000-0000-4000-8000-000000000461',
   'Ojo con el pistón delantero');
select set_config('vinabike.smart_task_cmd', '', true);

-- 2. La operadora respalda; después, lo que cambió.
select set_config('request.jwt.claims', jsonb_build_object('sub', account.id, 'role', 'authenticated')::text, true),
       set_config('request.jwt.claim.sub', account.id::text, true)
  from auth.users account where lower(account.email) = 'respaldo-ui-e2e@vinabike.invalid';
select 1 / (public.create_backup('e2898000-0000-4000-8000-000000000041',
  'Antes de perder el trabajo', 'manual', 'Respaldo sintético del recorrido C2') ->> 'success')::boolean::integer
  as respaldo_creado;
update public.customers set phone = '+56 9 5550 0999'
 where id = 'e2898000-0000-4000-8000-000000000410';
delete from public.mechanic_job_items where id = 'e2898000-0000-4000-8000-000000000463';
insert into public.mechanic_jobs (id, tenant_id, customer_id, status, client_request) values
  ('e2898000-0000-4000-8000-000000000452', 'e2898000-0000-4000-8000-000000000041',
   'e2898000-0000-4000-8000-000000000410', 'PENDIENTE', 'Trabajo posterior al respaldo');

-- 3. La pérdida: el trabajo, su bici y su tarea, sin sus efectos de borrado,
-- y sus avisos (para ver que la recuperación no los vuelve a producir).
set local session_replication_role = replica;
do $lose$
declare v_table record;
begin
  for v_table in select t.table_name, t.root_column from public.workshop_restore_tables_internal() t
                  where t.policy = 'member' order by t.ord desc loop
    execute format('delete from public.%I where %I = any($1)', v_table.table_name, v_table.root_column)
      using array['e2898000-0000-4000-8000-000000000450'::uuid,
                  'e2898000-0000-4000-8000-000000000420'::uuid,
                  'e2898000-0000-4000-8000-000000000480'::uuid];
  end loop;
  delete from public.smart_tasks where id = 'e2898000-0000-4000-8000-000000000480';
  delete from public.mechanic_jobs where id = 'e2898000-0000-4000-8000-000000000450';
  delete from public.bikes where id = 'e2898000-0000-4000-8000-000000000420';
  delete from public.erp_notifications
   where entity_id in ('e2898000-0000-4000-8000-000000000450', 'e2898000-0000-4000-8000-000000000480');
end;
$lose$;
set local session_replication_role = origin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select (select count(*) from public.mechanic_jobs where tenant_id = 'e2898000-0000-4000-8000-000000000041') as trabajos_hoy,
       (select count(*) from public.database_backups where tenant_id = 'e2898000-0000-4000-8000-000000000041'
          and status = 'completed') as respaldos;
commit;
\endif

\if :is_objects
select object.name
  from storage.objects object
 where object.bucket_id = 'task-attachments'
   and object.name like 'e2898000-0000-4000-8000-000000000041/%'
 order by object.name;
\endif

\if :is_readback
-- Cada fila del grafo del respaldo debe existir hoy idéntica (to_jsonb).
create temporary table backup_e2e_graph (tabla text, fila jsonb, igual boolean);
do $graph$
declare
  v_data jsonb;
  v_table record;
  v_row jsonb;
  v_equal boolean;
begin
  select backup_data into v_data from public.database_backups
   where tenant_id = 'e2898000-0000-4000-8000-000000000041'
     and backup_name = 'Antes de perder el trabajo';
  for v_table in
    select t.table_name, coalesce(t.root_column, 'id') as key_column
      from public.workshop_restore_tables_internal() t
     where t.policy in ('root', 'member')
       and jsonb_typeof(v_data -> t.table_name) = 'array'
  loop
    for v_row in select x from jsonb_array_elements(v_data -> v_table.table_name) x
                  where x ->> v_table.key_column in ('e2898000-0000-4000-8000-000000000450',
                    'e2898000-0000-4000-8000-000000000420', 'e2898000-0000-4000-8000-000000000480')
    loop
      if v_table.table_name = 'smart_task_user_state' then
        continue;
      end if;
      execute format('select to_jsonb(l) = $1 from public.%I l where l.id = ($1 ->> ''id'')::uuid',
                     v_table.table_name) into v_equal using v_row;
      insert into backup_e2e_graph values (v_table.table_name, v_row, coalesce(v_equal, false));
    end loop;
  end loop;
end;
$graph$;
select tabla, count(*) as filas, count(*) filter (where igual) as identicas
  from backup_e2e_graph group by tabla order by tabla;

with facts as (
  select
    (select count(*) from backup_e2e_graph) as filas_del_grafo,
    (select count(*) from backup_e2e_graph where igual) as filas_identicas,
    (select count(distinct tabla) from backup_e2e_graph) as tablas_del_grafo,
    (select job.created_by = employee.user_id from public.mechanic_jobs job
       join public.employees employee on employee.id = 'e2898000-0000-4000-8000-000000000422'
      where job.id = 'e2898000-0000-4000-8000-000000000450') as autora_la_mecanica,
    (select phone = '+56 9 5550 0999' from public.customers
      where id = 'e2898000-0000-4000-8000-000000000410') as telefono_de_hoy,
    (select count(*) from public.mechanic_job_items
      where id = 'e2898000-0000-4000-8000-000000000463') as linea_del_trabajo_vivo,
    (select count(*) from public.mechanic_jobs
      where id = 'e2898000-0000-4000-8000-000000000452') as trabajo_posterior,
    (select count(*) from public.erp_notifications
      where entity_id in ('e2898000-0000-4000-8000-000000000450',
                          'e2898000-0000-4000-8000-000000000480')) as avisos_nuevos,
    (select restore_report ->> 'recovery_mode' from public.database_backups
      where tenant_id = 'e2898000-0000-4000-8000-000000000041'
        and backup_name = 'Antes de perder el trabajo') as modo,
    (select (restore_report -> 'changed_rows' ->> 'inserted')::integer from public.database_backups
      where tenant_id = 'e2898000-0000-4000-8000-000000000041'
        and backup_name = 'Antes de perder el trabajo') as filas_repuestas,
    (select count(*) from public.workshop_restore_invocations)
      + (select count(*) from public.workshop_restore_effect_packets) as paquetes_abiertos
)
select *,
  (case when filas_del_grafo >= 15 and filas_identicas = filas_del_grafo
             and tablas_del_grafo >= 12 and autora_la_mecanica
             and telefono_de_hoy and linea_del_trabajo_vivo = 0 and trabajo_posterior = 1
             and avisos_nuevos = 0 and modo = 'restore_missing_keep_live'
             and filas_repuestas = filas_del_grafo and paquetes_abiertos = 0
        then 1 else 0 end) as c2_readback
  from facts;
select 1 / (select case when count(*) = count(*) filter (where igual) and count(*) >= 15
                        then 1 else 0 end from backup_e2e_graph) as grafo_identico;
\endif

\if :is_teardown
begin;

-- Igual que la retirada del taller (workshop_journey_local_fixture.sql):
-- tabla por tabla, suspendiendo sólo para ese borrado la guardia de
-- inmutabilidad, reintentando el orden que la base exige.
create temporary table backup_e2e_suspended (tabla text, disparador text, filas bigint);
do $immutable$
declare
  v_table record;
  v_trigger text;
  v_triggers text[];
  v_rows bigint;
  v_pass integer;
  v_pending integer;
  v_progress boolean;
  v_last_error text;
begin
  for v_pass in 1..20 loop
    v_pending := 0;
    v_progress := false;
    for v_table in
      select c.oid::regclass as relation
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind in ('r', 'p')
         and not c.relispartition
         and c.relname not in ('tenants', 'user_profiles', 'employees')
         and exists (select 1 from pg_attribute a
                      where a.attrelid = c.oid and a.attname = 'tenant_id'
                        and not a.attisdropped)
       order by c.relname
    loop
      execute format('select count(*) from %s where tenant_id = %L',
                     v_table.relation, 'e2898000-0000-4000-8000-000000000041')
        into v_rows;
      continue when v_rows = 0;
      select coalesce(array_agg(t.tgname order by t.tgname), '{}')
        into v_triggers
        from pg_trigger t
        join pg_proc p on p.oid = t.tgfoid
       where t.tgrelid = v_table.relation
         and not t.tgisinternal
         and t.tgenabled = 'O'
         and (p.proname ~ '(prevent|immutable|append_only|mutation)'
              or t.tgname ~ '(immutable|append_only)');
      begin
        foreach v_trigger in array v_triggers loop
          execute format('alter table %s disable trigger %I', v_table.relation, v_trigger);
        end loop;
        execute format('delete from %s where tenant_id = %L',
                       v_table.relation, 'e2898000-0000-4000-8000-000000000041');
        foreach v_trigger in array v_triggers loop
          execute format('alter table %s enable trigger %I', v_table.relation, v_trigger);
          insert into backup_e2e_suspended values (v_table.relation::text, v_trigger, v_rows);
        end loop;
        v_progress := true;
      exception when others then
        v_pending := v_pending + 1;
        v_last_error := v_table.relation::text || ': ' || sqlerrm;
      end;
    end loop;
    exit when v_pending = 0;
    if not v_progress then
      raise exception 'La retirada del taller sintético no avanza: %', v_last_error;
    end if;
  end loop;
  if v_pending > 0 then
    raise exception 'La retirada del taller sintético no terminó: %', v_last_error;
  end if;
end;
$immutable$;
delete from public.user_profiles
 where tenant_id = 'e2898000-0000-4000-8000-000000000041';
update public.employees set user_id = null
 where tenant_id = 'e2898000-0000-4000-8000-000000000041';
delete from public.tenants
 where id = 'e2898000-0000-4000-8000-000000000041';
delete from auth.users
 where lower(email) in ('respaldo-ui-e2e@vinabike.invalid',
                        'respaldo-ui-e2e-otra@vinabike.invalid');

commit;

create temporary table backup_e2e_leftovers (tabla text, filas bigint);
do $leftovers$
declare
  v_table record;
  v_rows bigint;
begin
  for v_table in
    select c.table_schema, c.table_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema = c.table_schema and t.table_name = c.table_name
     where c.table_schema = 'public' and c.column_name = 'tenant_id'
       and t.table_type = 'BASE TABLE'
  loop
    execute format('select count(*) from %I.%I where tenant_id = %L',
                   v_table.table_schema, v_table.table_name,
                   'e2898000-0000-4000-8000-000000000041')
      into v_rows;
    if v_rows > 0 then
      insert into backup_e2e_leftovers values (v_table.table_name, v_rows);
    end if;
  end loop;
end;
$leftovers$;
select * from backup_e2e_suspended order by tabla;
select * from backup_e2e_leftovers order by tabla;

select 1 / (case when not exists (select 1 from backup_e2e_leftovers)
                  and not exists (select 1 from public.tenants
                                   where id = 'e2898000-0000-4000-8000-000000000041')
                  and not exists (select 1 from backup_e2e_suspended s
                                    join pg_trigger t
                                      on t.tgrelid = s.tabla::regclass
                                     and t.tgname = s.disparador
                                   where t.tgenabled <> 'O')
                  and not exists (select 1 from auth.users
                                   where lower(email) in ('respaldo-ui-e2e@vinabike.invalid',
                                                          'respaldo-ui-e2e-otra@vinabike.invalid'))
                 then 1 else 0 end) as retirada_completa;
\endif
