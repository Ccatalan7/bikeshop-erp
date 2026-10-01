-- C1/C4 por la app (PLANS.md, 2026-09-30): el recorrido completo del taller
-- con la app real contra la base local. Lo usa
-- scripts/e2e/run_android_local_journey.sh --journey workshop.
--
--   preflight  sólo lectura: lo que el recorrido necesita existe en esta base
--              y no quedan restos de otra corrida
--   setup      taller, dos mecánicos con ficha de empleado, la clienta, un
--              modelo del catálogo y el servicio «Enrayado de rueda»
--   objects    los bytes privados del taller (para retirarlos por la API)
--   readback   lo que dejaron las decisiones del operador, con 1/0 al final
--   teardown   todo lo sintético, incluido el modelo del catálogo global
--
-- La historia que el readback exige, en el orden del operador:
--   1. La bici nace del modelo: `catalog_bike_id` y los datos del modelo con
--      fuente `catalog` y sin confirmar, también el aro y las mazas que el
--      formulario copia (criterio 1).
--   2. El Enrayado se pide para la rueda trasera con 28H; atrás va un
--      neumático 29 (BSD 622, calza) y, por error, adelante uno 27,5 (584).
--      Con el motor de fichas real, el 584 no calza con el aro 29 y el cierre
--      se rechaza entero (`incompatible`): ni estado, ni recibo, ni ficha.
--   3. «Revisar líneas» lleva a la línea; se cambia el 27,5 por otro 29 (con
--      su precio, no el del 27,5) y el trabajo termina: la ficha dice 28H
--      atrás, confirmado por el trabajo (`job_completion`), BSD 622 en las
--      dos ruedas declarado y sin confirmar (la ficha técnica del neumático no
--      está verificada), la delantera sigue en 32H del modelo, el recibo
--      nombra el trabajo y la memoria pone el Enrayado en la rueda trasera
--      (criterios 5, 6 y 7).
--   4. El encargo: una tarea ligada a la línea del Enrayado, asignada a la
--      compañera por su ficha de empleado, con una foto adjunta.
--   5. Una sola factura del trabajo: el presupuesto aprobado se factura antes
--      de corregir, porque un presupuesto aprobado es de sólo lectura.
--
-- La base local necesita, además del esquema de referencia, el motor de
-- fichas, el BSD del neumático y el cierre como en producción: el preflight
-- los exige por nombre y AGENT_MACOS_APP_CONTROL.md §4.c dice cómo se
-- instalan (2026-09-30).
--
-- Alcance fijo: taller e2898000-0000-4000-8000-000000000031, cuentas
-- taller-ui-e2e@ y taller-ui-e2e-otra@vinabike.invalid (las crea el lanzador
-- por la API de Auth) y el modelo e2898000-0000-4000-8000-000000000301.
-- No toca los talleres …0001/0002/0021 de los otros recorridos.
\set ON_ERROR_STOP on
\getenv fixture_mode WORKSHOP_E2E_FIXTURE_MODE
\if :{?fixture_mode}
\else
select 1 / 0 as falta_workshop_e2e_fixture_mode;
\endif

select :'fixture_mode' = 'preflight' as is_preflight,
       :'fixture_mode' = 'setup' as is_setup,
       :'fixture_mode' = 'objects' as is_objects,
       :'fixture_mode' = 'readback' as is_readback,
       :'fixture_mode' = 'teardown' as is_teardown,
       :'fixture_mode' in ('preflight', 'setup', 'objects', 'readback', 'teardown')
         as is_known
\gset

\if :is_known
\else
select 1 / 0 as modo_desconocido;
\endif

-- Una base con secretos en vault es la de producción: aquí no se sigue.
select 1 / (case when not exists (select 1 from vault.secrets) then 1 else 0 end)
  as solo_base_local
\gset

\if :is_preflight
-- Cada requisito por su nombre: lo que falte se ve antes de escribir nada.
select
  to_regclass('public.bike_catalog') is not null as catalogo,
  to_regclass('public.service_profile_questions_resolved_v1') is not null
    as preguntas_de_servicio,
  to_regclass('public.smart_task_job_items') is not null as encargo_por_linea,
  to_regclass('public.bike_technical_fact_patches') is not null as recibos_de_ficha,
  to_regprocedure('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)')
    is not null as lo_instalado,
  -- El motor de fichas, no sólo quien lo llama: sin él un repuesto no dice
  -- su medida y el cierre no revisa nada.
  to_regclass('public.spec_facts') is not null
    and to_regclass('public.product_spec_bindings_internal_v1') is not null
    and to_regprocedure('public.spec_active_product_values_internal_v1(uuid,uuid)') is not null
    and to_regprocedure('public.get_product_spec_contexts_v1(uuid[])') is not null
    as motor_de_fichas,
  exists (select 1 from public.spec_template_fields f
            join public.spec_templates t on t.id = f.template_id
            join public.spec_definitions d on d.id = f.spec_definition_id
           where t.tenant_id is null and t.key = 'tire' and t.is_active
             and d.key = 'bead_seat_diameter_mm') as neumatico_con_bsd,
  exists (select 1 from public.bike_fact_spec_links
           where spec_key = 'bead_seat_diameter_mm' and template_key = 'tire')
    as bsd_a_la_ficha,
  -- El cierre como en producción (2026-09-30): el de la base de referencia
  -- descuenta stock y asienta al terminar; el de producción no.
  md5(pg_get_functiondef('public.handle_mechanic_job_change()'::regprocedure))
    = 'fbf44c605a0925f4186f7ebe0a9369c2' as cierre_como_produccion,
  exists (select 1 from storage.buckets where id = 'task-attachments')
    as bucket_de_tareas,
  not exists (select 1 from public.tenants
               where id = 'e2898000-0000-4000-8000-000000000031')
    as sin_taller_previo,
  not exists (select 1 from public.bike_catalog
               where id = 'e2898000-0000-4000-8000-000000000301')
    as sin_modelo_previo,
  (select count(*) from public.bike_catalog
    where lower(brand) = 'trek' and lower(model_name) = 'marlin 7 gen 3'
      and model_year = 2024) as modelos_homonimos;

select 1 / (case when
    to_regclass('public.bike_catalog') is not null
    and to_regclass('public.service_profile_questions_resolved_v1') is not null
    and to_regclass('public.smart_task_job_items') is not null
    and to_regclass('public.bike_technical_fact_patches') is not null
    and to_regprocedure('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)')
        is not null
    and to_regclass('public.spec_facts') is not null
    and to_regclass('public.product_spec_bindings_internal_v1') is not null
    and to_regprocedure('public.spec_active_product_values_internal_v1(uuid,uuid)') is not null
    and to_regprocedure('public.get_product_spec_contexts_v1(uuid[])') is not null
    and exists (select 1 from public.spec_template_fields f
                  join public.spec_templates t on t.id = f.template_id
                  join public.spec_definitions d on d.id = f.spec_definition_id
                 where t.tenant_id is null and t.key = 'tire' and t.is_active
                   and d.key = 'bead_seat_diameter_mm')
    and exists (select 1 from public.bike_fact_spec_links
                 where spec_key = 'bead_seat_diameter_mm' and template_key = 'tire')
    and md5(pg_get_functiondef('public.handle_mechanic_job_change()'::regprocedure))
        = 'fbf44c605a0925f4186f7ebe0a9369c2'
    and exists (select 1 from storage.buckets where id = 'task-attachments')
  then 1 else 0 end) as preflight_ok;
\endif

\if :is_setup
begin;

do $setup$
begin
  if (select count(*) from auth.users
       where lower(email) in ('taller-ui-e2e@vinabike.invalid',
                              'taller-ui-e2e-otra@vinabike.invalid')) <> 2 then
    raise exception 'Faltan las dos cuentas sintéticas (las crea el lanzador por la API de Auth)';
  end if;
  if exists (select 1 from public.tenants
              where id = 'e2898000-0000-4000-8000-000000000031') then
    raise exception 'Queda el taller sintético de otra corrida: correr antes la retirada';
  end if;
end;
$setup$;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into public.tenants(id, shop_name) values
  ('e2898000-0000-4000-8000-000000000031', 'TALLER UI E2E - SYNTHETIC ONLY');
-- El alta del taller deja su id como `sub` (SUPABASE_WORKFLOW.md).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Los dos mecánicos tienen ficha de empleado: un encargo sobre un trabajo
-- sólo se asigna a quien la tiene (`assignee_not_worker_linked`).
insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
)
select v.id::uuid, 'e2898000-0000-4000-8000-000000000031', account.id,
       v.number, v.first_name, v.last_name, 'Mecánico', 'full_time', 'active', 0
  from (values
    ('e2898000-0000-4000-8000-000000000321', 'taller-ui-e2e@vinabike.invalid',
     'T-001', 'Tomás', 'Rivas'),
    ('e2898000-0000-4000-8000-000000000322', 'taller-ui-e2e-otra@vinabike.invalid',
     'T-002', 'Javiera', 'Soto')
  ) as v(id, email, number, first_name, last_name)
  join auth.users account on lower(account.email) = v.email;

insert into public.user_profiles (user_id, tenant_id, role, permissions, employee_id)
select account.id, 'e2898000-0000-4000-8000-000000000031', 'mechanic',
       '{}'::jsonb, employee.id
  from public.employees employee
  join auth.users account on account.id = employee.user_id
 where employee.tenant_id = 'e2898000-0000-4000-8000-000000000031';

insert into public.customers (id, tenant_id, name, phone) values
  ('e2898000-0000-4000-8000-000000000310',
   'e2898000-0000-4000-8000-000000000031', 'Camila Rojas', '+56 9 5550 0310');

-- La marca y el modelo como los tiene el taller: el formulario los elige de
-- sus listas, y con ellos busca el modelo en el catálogo.
insert into public.bike_brands (id, tenant_id, name, is_active)
select 'e2898000-0000-4000-8000-000000000305', 'e2898000-0000-4000-8000-000000000031',
       'Trek', true
 where not exists (select 1 from public.bike_brands
                    where tenant_id = 'e2898000-0000-4000-8000-000000000031'
                      and lower(name) = 'trek');
insert into public.bike_models (id, tenant_id, brand_id, name, year, is_active)
select 'e2898000-0000-4000-8000-000000000306', brand.tenant_id, brand.id,
       'Marlin 7 Gen 3', 2024, true
  from public.bike_brands brand
 where brand.tenant_id = 'e2898000-0000-4000-8000-000000000031'
   and lower(brand.name) = 'trek';

-- El modelo conocido: lo que su ficha técnica dice de fábrica.
insert into public.bike_catalog (
  id, brand, model_name, model_year, bike_type, wheel_size,
  drivetrain_speeds, drivetrain_config, brake_type,
  brake_rotor_size_front_mm, brake_rotor_size_rear_mm, freehub_type,
  spoke_count, front_hub_spacing_mm, rear_hub_spacing_mm, data_source
) values (
  'e2898000-0000-4000-8000-000000000301', 'Trek', 'Marlin 7 Gen 3', 2024,
  'mountain_hardtail', '29"', 10, '1x10', 'hydraulic_disc', 160, 160,
  'shimano_hg', 32, 100, 141, 'e2e_sintetico'
);

-- Los neumáticos: su BSD sale de su ficha técnica (plantilla global `tire`),
-- escrita como la de producción, de texto de proveedor y sin verificar.
insert into public.products (
  id, tenant_id, name, category_name, product_type, spec_template_id, price,
  inventory_qty, stock_quantity
)
select v.id::uuid, 'e2898000-0000-4000-8000-000000000031', v.name, 'Neumáticos',
       'product', template.id, v.price, 4, 4
  from (values
    ('e2898000-0000-4000-8000-000000000332', 'Neumático Maxxis Ardent 29 x 2.25', 32990),
    ('e2898000-0000-4000-8000-000000000333', 'Neumático Kenda 27.5 x 2.10', 14990)
  ) as v(id, name, price)
  cross join public.spec_templates template
 where template.tenant_id is null and template.key = 'tire' and template.is_active;
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id, value_number, source
)
select 'e2898000-0000-4000-8000-000000000031', 'product', v.id::uuid, definition.id,
       v.bsd, 'supplier_text'
  from (values
    ('e2898000-0000-4000-8000-000000000332', 622),
    ('e2898000-0000-4000-8000-000000000333', 584)
  ) as v(id, bsd)
  cross join public.spec_definitions definition
 where definition.tenant_id is null and definition.key = 'bead_seat_diameter_mm';
select 1 / (case when (select count(*) from public.spec_facts
                        where tenant_id = 'e2898000-0000-4000-8000-000000000031') = 2
                 then 1 else 0 end) as neumaticos_con_bsd;

-- El servicio que arma una rueda: qué rueda y cuántas perforaciones. Las
-- perforaciones se aplican a la ficha al terminar el trabajo.
insert into public.products (id, tenant_id, name, category_name, product_type, price) values
  ('e2898000-0000-4000-8000-000000000331',
   'e2898000-0000-4000-8000-000000000031', 'Enrayado de rueda', 'Servicios', 'service',
   25000);

insert into public.service_profiles (
  id, tenant_id, key, name, service_family, description,
  customer_summary_template, mechanic_summary_template
) values (
  'e2898000-0000-4000-8000-000000000341',
  'e2898000-0000-4000-8000-000000000031', 'e2e_wheel_build',
  'Enrayado de rueda', 'wheels', 'Armar la rueda con rayos nuevos',
  'Enrayado {{which_wheel}}, {{hole_count}} rayos',
  'Enrayado {{which_wheel}} · {{hole_count}}H'
);
insert into public.service_profile_questions (
  tenant_id, service_profile_id, key, label, question_type, is_required,
  sort_order, options_json
) values
  ('e2898000-0000-4000-8000-000000000031',
   'e2898000-0000-4000-8000-000000000341', 'which_wheel', '¿Qué rueda?',
   'single_select', true, 10,
   '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'),
  ('e2898000-0000-4000-8000-000000000031',
   'e2898000-0000-4000-8000-000000000341', 'hole_count', 'Cantidad de rayos / hoyos',
   'single_select', true, 20,
   '[{"value":"24","label":"24"},{"value":"28","label":"28"},{"value":"32","label":"32"},{"value":"36","label":"36"}]'),
  ('e2898000-0000-4000-8000-000000000031',
   'e2898000-0000-4000-8000-000000000341', 'brake_type', 'Tipo de freno',
   'single_select', false, 30,
   '[{"value":"rim","label":"Llanta"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"hydraulic_disc","label":"Disco hidráulico"}]');
insert into public.service_profile_targets (
  tenant_id, service_profile_id, target_family, target_position_mode
) values (
  'e2898000-0000-4000-8000-000000000031',
  'e2898000-0000-4000-8000-000000000341', 'wheel', 'front_rear'
);
insert into public.service_product_profile_mappings (
  tenant_id, product_id, service_profile_id, status
) values (
  'e2898000-0000-4000-8000-000000000031',
  'e2898000-0000-4000-8000-000000000331',
  'e2898000-0000-4000-8000-000000000341', 'active'
);

-- Los estados del trabajo nacen con el taller; sin ellos no hay cierre.
select 1 / (case when (select count(*) from public.job_statuses
                        where tenant_id = 'e2898000-0000-4000-8000-000000000031'
                          and code in ('EN_CURSO', 'FINALIZADO')) = 2
                 then 1 else 0 end) as estados_del_taller;

commit;

select profile.role, account.email, employee.first_name as empleado,
       account.raw_app_meta_data->>'account_type' as account_type
  from public.user_profiles profile
  join auth.users account on account.id = profile.user_id
  left join public.employees employee on employee.id = profile.employee_id
 where profile.tenant_id = 'e2898000-0000-4000-8000-000000000031'
 order by account.email;
\endif

\if :is_objects
select object.name
  from storage.objects object
 where object.bucket_id = 'task-attachments'
   and object.name like 'e2898000-0000-4000-8000-000000000031/%'
 order by object.name;
\endif

\if :is_readback
with tenant as (
  select 'e2898000-0000-4000-8000-000000000031'::uuid as id
), coworker as (
  select employee.id from public.employees employee
   where employee.id = 'e2898000-0000-4000-8000-000000000322'
), bike as (
  select b.* from public.bikes b, tenant
   where b.tenant_id = tenant.id
     and b.customer_id = 'e2898000-0000-4000-8000-000000000310'
), profile as (
  select p.technical_profile as tp, p.catalog_bike_id
    from public.bike_profiles p join bike on bike.id = p.bike_id
), job as (
  select j.* from public.mechanic_jobs j, tenant
   where j.tenant_id = tenant.id and j.deleted_at is null
), build_lines as (
  select i.* from public.mechanic_job_items i join job on job.id = i.job_id
   where i.service_configuration_data ? 'hole_count'
), tire_lines as (
  select i.* from public.mechanic_job_items i join job on job.id = i.job_id
   where i.product_id in ('e2898000-0000-4000-8000-000000000332',
                          'e2898000-0000-4000-8000-000000000333')
), task as (
  select t.* from public.smart_tasks t, tenant where t.tenant_id = tenant.id
), facts as (
  select
    (select count(*) from bike) as bicis,
    (select count(*) from profile
      where catalog_bike_id = 'e2898000-0000-4000-8000-000000000301') as del_modelo,
    (select count(*) from profile
      where tp->'sources'->>'frontSpokeHoles' = 'catalog'
        and (tp->'values'->>'frontSpokeHoles')::integer = 32) as delantera_del_modelo,
    -- Lo que el formulario copia del modelo a los campos de la bici queda
    -- dicho como del modelo y sin confirmar; el mero vínculo no lo marca.
    (select count(*) from profile, bike
      where bike.wheel_size = '29"'
        and tp->'sources'->>'wheelSize' = 'catalog'
        and coalesce((tp->'confirmed'->>'wheelSize')::boolean, false) = false
        and tp->'sources'->>'rearHubSpacingMm' = 'catalog'
        and coalesce((tp->'confirmed'->>'rearHubSpacingMm')::boolean, false) = false)
      as base_del_modelo,
    (select count(*) from profile
      where (tp->'values'->>'rearSpokeHoles')::integer = 28
        and tp->'sources'->>'rearSpokeHoles' = 'job_completion'
        and (tp->'confirmed'->>'rearSpokeHoles')::boolean) as trasera_instalada,
    -- El neumático 29 atrás, declarado: su ficha técnica no está verificada.
    (select count(*) from profile
      where (tp->'values'->>'rearWheelBsdMm')::integer = 622
        and tp->'sources'->>'rearWheelBsdMm' = 'job_completion'
        and coalesce((tp->'confirmed'->>'rearWheelBsdMm')::boolean, false) = false)
      as bsd_trasero_declarado,
    -- El 29 que reemplazó al 27,5 adelante, igual de declarado.
    (select count(*) from profile
      where (tp->'values'->>'frontWheelBsdMm')::integer = 622
        and tp->'sources'->>'frontWheelBsdMm' = 'job_completion'
        and coalesce((tp->'confirmed'->>'frontWheelBsdMm')::boolean, false) = false)
      as bsd_delantero_declarado,
    (select count(*) from tire_lines) as neumaticos,
    (select count(*) from tire_lines
      where product_id = 'e2898000-0000-4000-8000-000000000333') as neumaticos_27_5,
    (select count(*) from tire_lines
      where product_id = 'e2898000-0000-4000-8000-000000000332'
        and location_key = 'rear'
        and service_configuration_data->'part_change'->>'key' = 'rearWheelBsdMm') as neumatico_29_atras,
    -- La línea cambiada lleva el precio del artículo nuevo.
    (select count(*) from tire_lines
      where product_id = 'e2898000-0000-4000-8000-000000000332'
        and location_key = 'front'
        and service_configuration_data->'part_change'->>'key' = 'frontWheelBsdMm'
        and unit_price = 32990) as neumatico_29_adelante,
    (select count(*) from job where invoice_id is not null) as trabajos_facturados,
    (select count(*) from job) as trabajos,
    (select count(*) from job where status = 'FINALIZADO') as terminados,
    (select count(*) from build_lines) as enrayados,
    (select count(*) from build_lines
      where coalesce(nullif(location_key, 'none'),
                     service_configuration_data->>'which_wheel') = 'rear'
        and service_configuration_data->>'hole_count' = '28') as enrayado_trasero_28,
    -- El cierre rechazado no deja recibo: sólo el que terminó el trabajo.
    (select count(*) from public.mechanic_job_status_transition_events event
       join job on job.id = event.job_id
       join public.job_statuses status on status.id = event.to_status_id
      where status.code = 'FINALIZADO') as cierres_con_recibo,
    (select count(*) from public.bike_technical_fact_patches patch
       join job on job.id = patch.job_id) as recibos_de_ficha,
    (select count(*) from public.bike_interventions intervention
       join bike on bike.id = intervention.bike_id) as intervenciones,
    -- Las respuestas del asistente («Tipo de freno: Disco hidráulico») no
    -- llevan el Enrayado al freno: su nombre dice la rueda.
    (select count(*) from public.bike_interventions intervention
       join bike on bike.id = intervention.bike_id
      where coalesce(intervention.service_product_id, intervention.product_id)
              = 'e2898000-0000-4000-8000-000000000331'
        and intervention.system_key = 'rear_wheel') as enrayado_en_la_rueda,
    (select count(*) from task) as encargos,
    (select count(*) from task join job on job.id = task.linked_job_id
      where task.assigned_employee_id = (select id from coworker)) as encargo_a_la_companera,
    (select count(*) from public.smart_task_job_items link
       join task on task.id = link.task_id) as lineas_encargadas,
    (select count(*) from public.smart_task_attachments attachment
       join task on task.id = attachment.task_id
      where attachment.deleted_at is null) as fotos_del_encargo
)
select facts.*,
       1 / (case when bicis = 1 and del_modelo = 1 and delantera_del_modelo = 1
                  and base_del_modelo = 1
                  and trasera_instalada = 1 and bsd_trasero_declarado = 1
                  and bsd_delantero_declarado = 1 and neumaticos = 2
                  and neumaticos_27_5 = 0 and neumatico_29_atras = 1
                  and neumatico_29_adelante = 1 and trabajos_facturados = 1
                  and trabajos = 1 and terminados = 1
                  and enrayados = 1 and enrayado_trasero_28 = 1
                  and cierres_con_recibo = 1 and recibos_de_ficha >= 1
                  and intervenciones >= 1 and enrayado_en_la_rueda = 1
                  and encargos = 1
                  and encargo_a_la_companera = 1 and lineas_encargadas = 1
                  and fotos_del_encargo = 1
                 then 1 else 0 end) as c1_c4_readback
  from facts;
\endif

\if :is_teardown
begin;

do $teardown$
begin
  if exists (select 1 from storage.objects object
              where object.bucket_id = 'task-attachments'
                and object.name like 'e2898000-0000-4000-8000-000000000031/%') then
    raise exception 'Quedan bytes del taller sintético: retirarlos antes por la API de Storage';
  end if;
end;
$teardown$;

-- La evidencia sólo de inserción (eventos del trabajo, su libro de estados,
-- operaciones de inventario, asientos y cualquier otra tabla con disparador
-- de inmutabilidad) apunta al taller con `restrict` o no se deja borrar.
-- Para retirar este taller sintético, y sólo dentro de esta transacción, se
-- borran las filas del taller tabla por tabla: la que tiene disparador de
-- inmutabilidad lo suspende sólo para ese borrado y lo reactiva enseguida.
-- El orden lo decide la base, no una lista: un borrado que choca con una
-- llave o una guardia porque otra tabla todavía apunta a sus filas se
-- deshace entero (disparador incluido) y se reintenta en la pasada
-- siguiente. Facturar el trabajo deja operaciones de inventario que sus
-- `checkpoints` y asientos todavía nombran (C1/C4 nativo, 2026-09-30).
-- Lo suspendido queda anotado y se comprueba después.
create temporary table workshop_e2e_suspended (tabla text, disparador text, filas bigint);
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
                     v_table.relation, 'e2898000-0000-4000-8000-000000000031')
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
          execute format('alter table %s disable trigger %I',
                         v_table.relation, v_trigger);
        end loop;
        execute format('delete from %s where tenant_id = %L',
                       v_table.relation, 'e2898000-0000-4000-8000-000000000031');
        foreach v_trigger in array v_triggers loop
          execute format('alter table %s enable trigger %I',
                         v_table.relation, v_trigger);
          insert into workshop_e2e_suspended
          values (v_table.relation::text, v_trigger, v_rows);
        end loop;
        v_progress := true;
      -- Cualquier error se reintenta: las guardias de dominio avisan con
      -- códigos distintos (borrar la bici suelta sus tareas y la bandeja
      -- exige relinkear por comando, 23514; borrar el cliente anula la
      -- factura y su traza de inventario exige un marco, P0001) y todas
      -- desaparecen al borrar antes la tabla que las dispara. Un error que
      -- no depende del orden no deja avanzar la pasada y se informa abajo.
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
delete from public.smart_task_attachments
 where tenant_id = 'e2898000-0000-4000-8000-000000000031';
-- Una ficha de empleado con acceso al ERP no se borra mientras siga ligada
-- (`employee_erp_unlink_required`): primero se suelta el acceso.
delete from public.user_profiles
 where tenant_id = 'e2898000-0000-4000-8000-000000000031';
update public.employees set user_id = null
 where tenant_id = 'e2898000-0000-4000-8000-000000000031';
delete from public.tenants
 where id = 'e2898000-0000-4000-8000-000000000031';
delete from public.bike_catalog
 where id = 'e2898000-0000-4000-8000-000000000301';
delete from auth.users
 where lower(email) in ('taller-ui-e2e@vinabike.invalid',
                        'taller-ui-e2e-otra@vinabike.invalid');

commit;

-- Nada del taller sintético queda en ninguna tabla con `tenant_id`, tenga o
-- no llave hacia `tenants`: una tabla sin cascada dejaría huérfanos que
-- ninguna consulta de arriba nombra.
create temporary table workshop_e2e_leftovers (tabla text, filas bigint);
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
                   'e2898000-0000-4000-8000-000000000031')
      into v_rows;
    if v_rows > 0 then
      insert into workshop_e2e_leftovers values (v_table.table_name, v_rows);
    end if;
  end loop;
end;
$leftovers$;
select * from workshop_e2e_suspended order by tabla;
select * from workshop_e2e_leftovers order by tabla;

select 1 / (case when not exists (select 1 from workshop_e2e_leftovers)
                  and not exists (select 1 from public.tenants
                                   where id = 'e2898000-0000-4000-8000-000000000031')
                  -- Cada disparador suspendido quedó activo como estaba.
                  and not exists (select 1 from workshop_e2e_suspended s
                                    join pg_trigger t
                                      on t.tgrelid = s.tabla::regclass
                                     and t.tgname = s.disparador
                                   where t.tgenabled <> 'O')
                  and not exists (select 1 from public.bike_catalog
                                   where id = 'e2898000-0000-4000-8000-000000000301')
                  and not exists (select 1 from auth.users
                                   where lower(email) in ('taller-ui-e2e@vinabike.invalid',
                                                          'taller-ui-e2e-otra@vinabike.invalid'))
                 then 1 else 0 end) as retirada_completa;
\endif
