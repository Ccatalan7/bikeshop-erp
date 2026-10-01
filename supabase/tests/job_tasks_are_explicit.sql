-- Las tareas de un trabajo las crea una persona (20260929040000; cierre del
-- Master Schema, 2026-09-29).
--
-- Con descripciones como las del catálogo real (renglones sin marca que son
-- pasos, viñetas que son advertencias o sub-ítems de un encabezado, `1)` que
-- son títulos, `1.`, promociones con precio):
-- - una línea nueva, de servicio o de producto, no crea tareas;
-- - el cliente publicado, que las crea al guardar (cada renglón, marcadas
--   `parsed_from_description`), recibe un rechazo que nombra la regla;
-- - una persona crea su tarea, de la línea o suelta, como la app (RLS);
-- - una tarea heredada se sigue pudiendo marcar hecha, y una de persona no se
--   puede volver heredada.
begin;

select no_plan();

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2900000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Taller tareas');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'tareas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'service_role')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
select set_config('request.jwt.claim.role', 'service_role', true);

insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente tareas');

-- Las descripciones, como están en el catálogo (con los finales de línea de
-- Windows que traen algunas).
insert into public.products(id, tenant_id, name, product_type, description) values
  (pg_temp.id('70'), pg_temp.id('01'), 'Mantención Maza', 'service',
   E'-SIN CONTAR POSIBLE CAMBIO DE EJE\r\n-VIÑABIKE SE GUARDA EL DERECHO A DIAGNOSTICAR UN POSIBLE CAMBIO DE MAZA\r\nDesarme\r\nLimpieza\r\nEngrasado\r\nInstalación\r\nSi es necesario: Cambio de Rodamientos'),
  (pg_temp.id('71'), pg_temp.id('01'), 'Mantención Semi', 'service',
   E'1) MANTENCIÓN DE TRANSMISIÓN\nLimpieza profunda de:\n-Cadena\n-Piñon\n2) CABLES/PIOLAS NUEVAS\n3. Regulación de frenos y cambios'),
  (pg_temp.id('72'), pg_temp.id('01'), 'Freno hidráulico', 'product',
   E'Freno hidráulico delantero\n• Aceite mineral\n+ Instalación en $45.000');

insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number,
                                 job_type, status) values
  (pg_temp.id('50'), pg_temp.id('01'), pg_temp.id('10'), 'RT-50', 'service',
   'PENDIENTE');

create function pg_temp.tasks() returns integer language sql as $$
  select count(*)::integer from public.mechanic_job_tasks
   where tenant_id = pg_temp.id('01') and job_id = pg_temp.id('50')
$$;

-- ============================================================================
-- Una línea nueva no crea tareas
-- ============================================================================

insert into public.mechanic_job_items(id, tenant_id, job_id, service_product_id,
                                      product_name, quantity, unit_price,
                                      item_type) values
  (pg_temp.id('60'), pg_temp.id('01'), pg_temp.id('50'), pg_temp.id('70'),
   'Mantención Maza', 1, 15000, 'service'),
  (pg_temp.id('61'), pg_temp.id('01'), pg_temp.id('50'), pg_temp.id('71'),
   'Mantención Semi', 1, 35000, 'service');
insert into public.mechanic_job_items(id, tenant_id, job_id, product_id,
                                      product_name, quantity, unit_price,
                                      item_type) values
  (pg_temp.id('62'), pg_temp.id('01'), pg_temp.id('50'), pg_temp.id('72'),
   'Freno hidráulico', 1, 60000, 'product');

select is(pg_temp.tasks(), 0,
  'ni viñetas, ni 1., ni 1), ni la prosa de la descripción se vuelven tareas');
select ok(
  not exists (select 1 from pg_trigger
               where tgrelid = 'public.mechanic_job_items'::regclass
                 and tgname = 'trg_auto_parse_item_description'),
  'la línea ya no tiene el disparador que las creaba');

-- ============================================================================
-- El cliente publicado las intenta crear: la base lo rechaza con la regla
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select throws_ok(
  $$insert into public.mechanic_job_tasks(tenant_id, job_id, parent_item_id,
                                          task_name, parsed_from_description,
                                          display_order)
    values (pg_temp.id('01'), pg_temp.id('50'), pg_temp.id('60'),
            '-SIN CONTAR POSIBLE CAMBIO DE EJE', true, 0)$$,
  '23514',
  'Las tareas de un trabajo las crea una persona: la descripción del catálogo es instrucción, no tarea',
  'una tarea copiada de la descripción se rechaza, como la crea el cliente publicado');

-- Una persona: de la línea y suelta.
select lives_ok(
  $$insert into public.mechanic_job_tasks(id, tenant_id, job_id, parent_item_id,
                                          task_name)
    values (pg_temp.id('80'), pg_temp.id('01'), pg_temp.id('50'),
            pg_temp.id('60'), 'Revisar juego del eje')$$,
  'una persona agrega una tarea a la línea');
select lives_ok(
  $$insert into public.mechanic_job_tasks(id, tenant_id, job_id, task_name,
                                          is_standalone)
    values (pg_temp.id('81'), pg_temp.id('01'), pg_temp.id('50'),
            'Avisar al cliente del eje', true)$$,
  'y una suelta, del trabajo');
select is(pg_temp.tasks(), 2, 'sólo esas dos existen');

select throws_ok(
  $$update public.mechanic_job_tasks set parsed_from_description = true
     where id = pg_temp.id('80')$$,
  '23514', null,
  'una tarea de persona no se puede volver heredada');

reset role;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'service_role')::text, true);
select set_config('request.jwt.claim.role', 'service_role', true);

-- ============================================================================
-- Las heredadas se conservan y se pueden cerrar
-- ============================================================================

-- Como las 370 de producción: creadas antes de la regla.
set local session_replication_role = replica;
insert into public.mechanic_job_tasks(id, tenant_id, job_id, parent_item_id,
                                      task_name, parsed_from_description,
                                      display_order)
values (pg_temp.id('82'), pg_temp.id('01'), pg_temp.id('50'), pg_temp.id('61'),
        'Cadena', true, 0);
set local session_replication_role = origin;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select lives_ok(
  $$update public.mechanic_job_tasks set is_completed = true
     where id = pg_temp.id('82')$$,
  'una tarea heredada se puede marcar hecha');
select is(
  (select parsed_from_description and is_completed
     from public.mechanic_job_tasks where id = pg_temp.id('82')),
  true, 'y conserva su marca');

reset role;

-- ============================================================================
-- Otro taller no ve ni crea tareas en este trabajo
-- ============================================================================

insert into public.tenants(id, shop_name) values
  (pg_temp.id('02'), 'Otro taller');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('92'), 'authenticated', 'authenticated',
   'otro-tareas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('92'), pg_temp.id('02'), 'admin');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('92')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

select is(
  (select count(*)::integer from public.mechanic_job_tasks
    where job_id = pg_temp.id('50')),
  0, 'otro taller no ve las tareas de este trabajo');
select throws_ok(
  $$insert into public.mechanic_job_tasks(tenant_id, job_id, task_name)
    values (pg_temp.id('01'), pg_temp.id('50'), 'Ajena')$$,
  '42501', null,
  'ni crea una en este taller');
-- Ni una suya colgada de un trabajo o de una línea de este taller (revisión de
-- Codex; sin esta guardia, sólo el cobro lo frenaba la guardia de líneas).
select throws_ok(
  $$insert into public.mechanic_job_tasks(tenant_id, job_id, task_name,
                                          is_standalone, is_adhoc, adhoc_price)
    values (pg_temp.id('02'), pg_temp.id('50'), 'Cobro ajeno', true, true, 50000)$$,
  '42501',
  'La tarea y su trabajo, línea o bici tienen que ser del mismo taller y del mismo trabajo',
  'ni una suya que apunte a un trabajo de este taller');
select throws_ok(
  $$insert into public.mechanic_job_tasks(tenant_id, job_id, parent_item_id, task_name)
    values (pg_temp.id('02'), pg_temp.id('50'), pg_temp.id('60'), 'Línea ajena')$$,
  '42501', null,
  'ni una colgada de una línea de este taller');

reset role;
select is(
  (select count(*)::integer from public.mechanic_job_items
    where job_id = pg_temp.id('50')),
  3, 'el trabajo de este taller sigue con sus tres líneas');

-- Dentro del mismo taller, una tarea no se cuelga de la línea de otro trabajo.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'service_role')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number,
                                 job_type, status) values
  (pg_temp.id('51'), pg_temp.id('01'), pg_temp.id('10'), 'RT-51', 'service',
   'PENDIENTE');
select throws_ok(
  $$insert into public.mechanic_job_tasks(tenant_id, job_id, parent_item_id, task_name)
    values (pg_temp.id('01'), pg_temp.id('51'), pg_temp.id('60'), 'Línea de otro trabajo')$$,
  '42501', null,
  'ni una tarea de un trabajo colgada de la línea de otro');

reset role;

select * from finish();
rollback;
