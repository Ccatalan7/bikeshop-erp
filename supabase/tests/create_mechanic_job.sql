-- El alta de un trabajo como comando con llave y recibo
-- (create_mechanic_job_v1, 20260929010000; BIKE_WORKSHOP_MASTER_SCHEMA.md,
-- cierre del 2026-09-29).
--
-- Prueba, como empleado autenticado:
-- - el alta con el id del formulario, y «Trabajo creado» una vez;
-- - la repetición con el mismo recibo, sin otro trabajo ni otro evento;
-- - la misma llave con otro contenido y otra llave con el mismo id;
-- - otro taller: no crea en el ajeno y no lee su recibo;
-- - lo que el alta no acepta;
-- - un corte después del alta y antes del recibo: no queda nada;
-- - lo que la bandeja manda detrás: las líneas y la factura en cada tipo de
--   trabajo, y en una garantía nueva las líneas antes de su registro, y la
--   decisión con su documento.
begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants(id, shop_name) values
  ('e2860000-0000-4000-8000-000000000001', 'Taller altas'),
  ('e2860000-0000-4000-8000-000000000002', 'Otro taller');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2860000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'altas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2860000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'otro-altas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles(user_id, tenant_id, role) values
  ('e2860000-0000-4000-8000-000000000091', 'e2860000-0000-4000-8000-000000000001', 'admin'),
  ('e2860000-0000-4000-8000-000000000092', 'e2860000-0000-4000-8000-000000000002', 'admin');

create or replace function pg_temp.as_user(p_user text)
returns void
language sql
as $$
  select set_config('request.jwt.claims', jsonb_build_object(
           'sub', 'e2860000-0000-4000-8000-0000000000' || p_user,
           'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub',
           'e2860000-0000-4000-8000-0000000000' || p_user, true);
$$;

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2860000-0000-4000-8000-0000000000' || p_n)::uuid $$;

select pg_temp.as_user('91');

insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente altas');
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  (pg_temp.id('20'), pg_temp.id('01'), pg_temp.id('10'), 'Trek', 'Marlin 5');
insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  is_service, product_type, track_stock
) values
  (pg_temp.id('30'), pg_temp.id('01'), 'Cable de cambio', 'ALTA-CABLE',
   5000, 1500, 10, 10, false, 'product', true);

-- El trabajo original de la garantía, entregado.
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, status
) values
  (pg_temp.id('40'), pg_temp.id('01'), pg_temp.id('10'), pg_temp.id('20'),
   'ALTA-ORIGEN', 'service', 'PENDIENTE');
update public.mechanic_jobs set status = 'ENTREGADO' where id = pg_temp.id('40');

-- Lo que el formulario manda en un alta (`MechanicJob.toJson`, sin la hora de
-- creación ni de cambio), con [p_extra] encima.
create or replace function pg_temp.new_job(p_n text, p_extra jsonb default '{}')
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'id', pg_temp.id(p_n),
    'tenant_id', pg_temp.id('01'),
    'customer_id', pg_temp.id('10'),
    'bike_id', pg_temp.id('20'),
    'service_package_id', null,
    'job_type', 'service',
    'workflow_kind', 'service',
    'intake_kind', 'bike',
    'mode_needs_review', false,
    'mode_review_reason', null,
    'subject_id', null,
    'subject_notes', null,
    'quotation_valid_until', null,
    'converted_from_id', null,
    'converted_at', null,
    'arrival_date', '2026-09-29T12:00:00Z',
    'diagnostic_deadline', null,
    'deadline', null,
    'diagnostic_sent_at', null,
    'started_at', null,
    'completed_at', null,
    'delivered_at', null,
    'status', 'PENDIENTE',
    'priority', 'NORMAL',
    'client_request', 'Revisar frenos',
    'diagnosis', null,
    'work_performed', null,
    'notes', null,
    'assigned_to', null,
    'assigned_technician_name', null,
    'estimated_cost', 0,
    'final_cost', 0,
    'discount_amount', 0,
    'estimated_duration_hours', null,
    'actual_labor_hours', null,
    'invoice_id', null,
    'is_invoiced', false,
    'is_paid', false,
    'is_warranty_job', false,
    'warranty_notes', null,
    'requires_approval', false,
    'approved_by_customer', false,
    'approved_at', null,
    'image_urls', '[]'::jsonb
  ) || p_extra
$$;

create or replace function pg_temp.error_of(p_sql text)
returns text
language plpgsql
as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ': ' || sqlerrm;
end;
$$;

create or replace function pg_temp.events(p_n text)
returns integer
language sql
as $$
  select count(*)::integer from public.bike_events e
   where e.tenant_id = pg_temp.id('01') and e.job_id = pg_temp.id(p_n)
     and e.event_type = 'job_created'
$$;

create temporary table results (label text primary key, result jsonb);

-- ============================================================================
-- Antes del alta, la bandeja pregunta por la llave y no hay recibo
-- ============================================================================

select is(public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050'),
  null, 'sin alta, no hay recibo: toca enviarla');

-- ============================================================================
-- Un corte después del alta y de su evento, antes del recibo: nada queda
-- ============================================================================

create function public.test_cut_before_job_creation_receipt()
returns trigger language plpgsql as $$
begin
  raise exception 'corte simulado antes del recibo del alta (trabajo: %, evento: %)',
    (select count(*) from public.mechanic_jobs where id = new.job_id),
    (select count(*) from public.bike_events
      where job_id = new.job_id and event_type = 'job_created');
end;
$$;
create trigger zz_test_cut_before_job_creation_receipt
  before insert on public.mechanic_job_creations
  for each row execute function public.test_cut_before_job_creation_receipt();

select throws_like(
  $$select public.create_mechanic_job_v1(
      'e2860000-0000-4000-8000-000000000050', pg_temp.new_job('50'))$$,
  '%corte simulado antes del recibo del alta (trabajo: 1, evento: 1)%',
  'el corte llega con el trabajo y su evento ya escritos');
select is((select count(*)::integer from public.mechanic_jobs
            where id = pg_temp.id('50')), 0, 'el trabajo no quedó');
select is(pg_temp.events('50'), 0, 'ni su evento');
select is(public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050'),
  null, 'ni su recibo: la bandeja lo reenvía');

drop trigger zz_test_cut_before_job_creation_receipt
  on public.mechanic_job_creations;

-- ============================================================================
-- El alta con el id del formulario, y «Trabajo creado» una vez
-- ============================================================================

insert into results
select 'alta', public.create_mechanic_job_v1(
  'e2860000-0000-4000-8000-000000000050', pg_temp.new_job('50'));

select is((select result->'job'->>'id' from results where label = 'alta'),
  pg_temp.id('50')::text, 'el trabajo tiene el id que eligió el formulario');
select is((select result->>'replayed' from results where label = 'alta'),
  'false', 'es un alta nueva');
select ok((select (result->>'operation_id') is not null from results where label = 'alta'),
  'con su recibo');
select ok((select length(result->'job'->>'job_number') > 0 from results where label = 'alta'),
  'la base le dio su número');
select is((select result->'job'->>'tenant_id' from results where label = 'alta'),
  pg_temp.id('01')::text, 'del taller de quien lo crea');
select is(pg_temp.events('50'), 1, '«Trabajo creado» una vez');
select is(
  (select jsonb_build_object('title', title, 'summary', summary,
            'source', source, 'reference', reference_number = (
              select result->'job'->>'job_number' from results where label = 'alta'),
            'payload', payload, 'by', created_by)
     from public.bike_events
    where job_id = pg_temp.id('50') and event_type = 'job_created'),
  jsonb_build_object('title', 'Trabajo creado', 'summary', 'Revisar frenos',
    'source', 'job_lifecycle', 'reference', true,
    'payload', '{"status": "pendiente", "priority": "normal"}'::jsonb,
    'by', pg_temp.id('91')),
  'como lo anotaba la app, a nombre de quien lo creó');

-- ============================================================================
-- La repetición: el mismo recibo, sin otro trabajo ni otro evento
-- ============================================================================

insert into results
select 'repetida', public.create_mechanic_job_v1(
  'e2860000-0000-4000-8000-000000000050', pg_temp.new_job('50'));

select is((select result->>'operation_id' from results where label = 'repetida'),
  (select result->>'operation_id' from results where label = 'alta'),
  'la repetición devuelve el mismo recibo');
select is((select result->>'replayed' from results where label = 'repetida'),
  'true', 'y dice que es repetida');
select is((select result->'job' from results where label = 'repetida'),
  (select result->'job' from results where label = 'alta'),
  'con la misma cabecera');
select is(pg_temp.events('50'), 1, 'sin otro «Trabajo creado»');

-- La lectura del recibo con que la bandeja resuelve una respuesta perdida,
-- como empleado autenticado.
select set_config('test.alta_operation',
  (select result->>'operation_id' from results where label = 'alta'), true);
set local role authenticated;
select is(
  (public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050')
    ->> 'operation_id'),
  current_setting('test.alta_operation'),
  'el recibo se lee por la llave, como empleado');
reset role;

-- La consulta con el contenido que se envió dice si es el que escribió la
-- llave: un recibo de la misma llave no confirma otro contenido (revisión de
-- Codex, 2026-09-29).
select is(
  public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050',
    pg_temp.new_job('50')) ->> 'payload_matches',
  'true', 'con el contenido que escribió, el recibo lo confirma');
select is(
  public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050',
    pg_temp.new_job('50', '{"priority": "URGENTE"}')) ->> 'payload_matches',
  'false', 'con otro contenido, el recibo dice que no es el suyo');
select is(
  public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050')
    ->> 'payload_matches',
  null, 'sin contenido, no lo afirma ni lo niega');

-- ============================================================================
-- La misma llave con otro contenido, y otra llave con el mismo id
-- ============================================================================

select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    'e2860000-0000-4000-8000-000000000050',
    pg_temp.new_job('50', '{"priority": "URGENTE"}'))$$), 5),
  '23505', 'la misma llave con otro contenido se rechaza');
select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    'otra-llave', pg_temp.new_job('50'))$$), 5),
  '23505', 'otra llave con el mismo id no crea otro trabajo');
select is((select count(*)::integer from public.mechanic_jobs
            where id = pg_temp.id('50')), 1, 'sigue habiendo uno');
select is(pg_temp.events('50'), 1, 'y un «Trabajo creado»');

-- ============================================================================
-- Lo que el alta no acepta
-- ============================================================================

select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    'sin-id', pg_temp.new_job('51') - 'id')$$), 5),
  '22023', 'sin el id del formulario no hay alta');
select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    'campo-ajeno', pg_temp.new_job('51', '{"total_cost": 99}'))$$), 5),
  '22023', 'un campo que el alta no manda se rechaza');
select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    '  ', pg_temp.new_job('51'))$$), 5),
  '22023', 'sin llave no hay alta');
select is((select count(*)::integer from public.mechanic_jobs
            where id = pg_temp.id('51')), 0, 'y nada quedó');

-- ============================================================================
-- Otro taller
-- ============================================================================

select pg_temp.as_user('92');
select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    'ajeno', pg_temp.new_job('52'))$$), 5),
  '42501', 'no crea un trabajo en otro taller');
select is(public.get_mechanic_job_creation_v1('e2860000-0000-4000-8000-000000000050'),
  null, 'ni lee el recibo de otro taller');
select is(
  left(pg_temp.error_of($$select public.create_mechanic_job_v1(
    'ajeno-mismo-id', pg_temp.new_job('50') - 'tenant_id'
      || jsonb_build_object('customer_id', null, 'bike_id', null,
                            'intake_kind', 'unspecified'))$$), 5),
  '23505', 'ni pisa el id de un trabajo ajeno');
select pg_temp.as_user('91');
select is((select count(*)::integer from public.mechanic_jobs
            where id in (pg_temp.id('52'))), 0, 'nada quedó');

select ok(not has_function_privilege('anon',
  'public.create_mechanic_job_v1(text,jsonb)', 'EXECUTE'),
  'sin sesión no se llama');
select ok(not exists (
    select 1
      from unnest(array['anon', 'authenticated']) as role_name,
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                        'REFERENCES', 'TRIGGER']) as privilege
     where has_table_privilege(role_name, 'public.mechanic_job_creations',
                               privilege)),
  'los recibos no se tocan por la API, tampoco con TRUNCATE');

-- ============================================================================
-- Lo que la bandeja manda detrás del alta: las líneas y la factura
-- ============================================================================

-- El guardado de líneas de un trabajo nuevo, como lo arma el formulario: la
-- bici nueva por su llave, la línea en ella, el descuento contra el cero del
-- alta, y la factura en el mismo comando.
create or replace function pg_temp.first_lines(
  p_job text, p_key text, p_with_bike boolean default true,
  p_discount numeric default 0
)
returns jsonb
language sql
as $$
  select public.save_mechanic_job_lines_v1(
    p_key,
    pg_temp.id(p_job),
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'client_key', 'cable',
      'product_id', pg_temp.id('30'),
      'product_name', 'Cable de cambio',
      'quantity', 1,
      'unit_price', 5000,
      'item_type', 'product')
      -- Sólo nombra una bici cuando la hay, como el formulario.
      || case when p_with_bike
           then jsonb_build_object('job_bike_key', pg_temp.id('20')::text)
           else '{}'::jsonb end),
    '[]'::jsonb,
    case when p_discount = 0 then null else jsonb_build_object(
      'discount_amount', jsonb_build_object('value', p_discount, 'expected', 0))
    end,
    case when p_with_bike then jsonb_build_array(jsonb_build_object(
      'client_key', pg_temp.id('20'),
      'bike_id', pg_temp.id('20'),
      'order_index', 0,
      'work_requested', 'Revisar frenos',
      'is_warranty_work', false,
      'requires_approval', false,
      'approved_by_customer', false)) end,
    true);
$$;

insert into results select 'lineas-servicio', pg_temp.first_lines('50', 'lineas-50', true, 1000);
select is((select result->'invoice'->>'action' from results where label = 'lineas-servicio'),
  'created', 'un servicio nuevo: sus líneas hacen su factura');
select is((select count(*)::integer from public.mechanic_job_items where job_id = pg_temp.id('50')),
  1, 'con su línea');
select is((select count(*)::integer from public.mechanic_job_bikes where job_id = pg_temp.id('50')),
  1, 'y su bici');
select is((select discount_amount from public.mechanic_jobs where id = pg_temp.id('50')),
  1000::numeric, 'el descuento, contra el cero del alta');
insert into results select 'lineas-servicio-repetidas', pg_temp.first_lines('50', 'lineas-50', true, 1000);
select is((select result->'invoice'->>'invoice_id' from results where label = 'lineas-servicio-repetidas'),
  (select result->'invoice'->>'invoice_id' from results where label = 'lineas-servicio'),
  'la repetición trae la misma factura');
select is((select count(*)::integer from public.sales_invoices
            where tenant_id = pg_temp.id('01') and id in (
              select invoice_id from public.mechanic_jobs where id = pg_temp.id('50'))),
  1, 'una sola');

-- Una cotización nueva: sus líneas, sin factura.
select lives_ok($$select public.create_mechanic_job_v1('alta-53',
  pg_temp.new_job('53', '{"job_type": "quotation", "workflow_kind": "quotation",
    "bike_id": null, "intake_kind": "unspecified", "subject_notes": "Horquilla"}'))$$,
  'una cotización nueva se crea');
insert into results select 'lineas-cotizacion', pg_temp.first_lines('53', 'lineas-53', false);
select is((select result->'invoice'->>'action' from results where label = 'lineas-cotizacion'),
  'none', 'y sus líneas no hacen factura');
select is(pg_temp.events('53'), 0, 'sin bici, sin evento en una bici');

-- Una venta nueva: sus líneas hacen su factura.
select lives_ok($$select public.create_mechanic_job_v1('alta-54',
  pg_temp.new_job('54', '{"job_type": "service", "workflow_kind": "sale",
    "bike_id": null, "intake_kind": "none", "client_request": null}'))$$,
  'una venta nueva se crea');
insert into results select 'lineas-venta', pg_temp.first_lines('54', 'lineas-54', false);
select is((select result->'invoice'->>'action' from results where label = 'lineas-venta'),
  'created', 'y sus líneas hacen su factura');

-- Un componente nuevo (sin bici, con lo que se recibió descrito): sus
-- líneas hacen su factura, como un servicio.
select lives_ok($$select public.create_mechanic_job_v1('alta-56',
  pg_temp.new_job('56', '{"job_type": "item_service", "workflow_kind": "service",
    "bike_id": null, "intake_kind": "component",
    "subject_notes": "Horquilla Fox 34"}'))$$,
  'un componente nuevo se crea');
select is((select intake_kind || '/' || job_type || '/' || mode_needs_review::text
             from public.mechanic_jobs where id = pg_temp.id('56')),
  'component/item_service/false', 'como componente, sin revisión pendiente');
insert into results select 'lineas-componente', pg_temp.first_lines('56', 'lineas-56', false);
select is((select result->'invoice'->>'action' from results where label = 'lineas-componente'),
  'created', 'y sus líneas hacen su factura');

-- ============================================================================
-- Una garantía nueva: el alta, sus líneas, su registro y su decisión
-- ============================================================================

select lives_ok($$select public.create_mechanic_job_v1('alta-55',
  pg_temp.new_job('55', '{"job_type": "warranty", "workflow_kind": "warranty",
    "warranty_outcome": "pending", "is_warranty_job": true}'))$$,
  'una garantía nueva se crea');
insert into results select 'lineas-garantia', pg_temp.first_lines('55', 'lineas-55', true);
select is((select result->'invoice'->>'action' from results where label = 'lineas-garantia'),
  'none', 'sus líneas no hacen factura: el documento es de la decisión');
select lives_ok($$select public.register_mechanic_job_warranty_claim(
    pg_temp.id('55'), pg_temp.id('40'), 'registro-55')$$,
  'el registro después de las líneas acepta la bici que ellas dejaron');
select is(
  (select jsonb_agg(jsonb_build_object('bike', bike_id, 'warranty', is_warranty_work))
     from public.mechanic_job_bikes where job_id = pg_temp.id('55')),
  jsonb_build_array(jsonb_build_object('bike', pg_temp.id('20'), 'warranty', true)),
  'una sola bici, marcada como trabajo de garantía');
select is((select count(*)::integer from public.mechanic_job_items where job_id = pg_temp.id('55')),
  1, 'con su línea');
insert into results select 'decision-55', public.decide_mechanic_job_warranty_claim(
  pg_temp.id('55'), 'covered', null, 'decision-55');
select ok((select invoice_id is not null from public.mechanic_jobs where id = pg_temp.id('55')),
  'la decisión hace el documento');
select is(
  (select coalesce(jsonb_agg(item->>'product_id'), '[]'::jsonb)
     from public.mechanic_jobs j
     join public.sales_invoices s on s.id = j.invoice_id and s.tenant_id = j.tenant_id
    cross join lateral jsonb_array_elements(coalesce(s.items, '[]'::jsonb)) item
    where j.id = pg_temp.id('55')),
  jsonb_build_array(pg_temp.id('30')::text),
  'con la línea que el alta llevaba');

select * from finish();
rollback;
