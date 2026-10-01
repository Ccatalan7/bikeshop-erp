-- La decisión de garantía como comando de la bandeja del equipo
-- (BIKE_WORKSHOP_MASTER_SCHEMA.md, punto 2 del cierre, 2026-09-29).
--
-- El RPC `decide_mechanic_job_warranty_claim` no cambia (su repetición, su
-- llave y su documento los prueba mechanic_job_service_warranty_ledger.sql).
-- Esto prueba la costura que usa la bandeja: el guardado de líneas de un
-- guardado con decisión no hace documento; la decisión que llega después lo
-- hace con esas líneas (y al revés no: por eso la cola); el comprobante y la
-- lectura exacta por taller, trabajo y llave con los que la bandeja la da por
-- escrita; la repetición sin otro evento ni otro documento; el rechazo sin
-- nada escrito; otro taller; y el estado después de la decisión.
begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants(id, shop_name) values
  ('e2850000-0000-4000-8000-000000000001', 'Taller garantías'),
  ('e2850000-0000-4000-8000-000000000002', 'Otro taller');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2850000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'garantias@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2850000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'otro-taller@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles(user_id, tenant_id, role) values
  ('e2850000-0000-4000-8000-000000000091', 'e2850000-0000-4000-8000-000000000001', 'admin'),
  ('e2850000-0000-4000-8000-000000000092', 'e2850000-0000-4000-8000-000000000002', 'admin');

create or replace function pg_temp.as_user(p_user text)
returns void
language sql
as $$
  select set_config('request.jwt.claims', jsonb_build_object(
           'sub', 'e2850000-0000-4000-8000-0000000000' || p_user,
           'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub',
           'e2850000-0000-4000-8000-0000000000' || p_user, true);
$$;

select pg_temp.as_user('91');

insert into public.customers(id, tenant_id, name) values
  ('e2850000-0000-4000-8000-000000000010', 'e2850000-0000-4000-8000-000000000001',
   'Cliente garantías');
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  ('e2850000-0000-4000-8000-000000000020', 'e2850000-0000-4000-8000-000000000001',
   'e2850000-0000-4000-8000-000000000010', 'Trek', 'Marlin 5');
insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  is_service, product_type, track_stock
) values
  ('e2850000-0000-4000-8000-000000000030', 'e2850000-0000-4000-8000-000000000001',
   'Cable de cambio', 'GAR-CABLE', 5000, 1500, 10, 10, false, 'product', true);

-- El trabajo original, entregado: abre la garantía.
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, status
) values
  ('e2850000-0000-4000-8000-000000000040', 'e2850000-0000-4000-8000-000000000001',
   'e2850000-0000-4000-8000-000000000010', 'e2850000-0000-4000-8000-000000000020',
   'GAR-ORIGEN', 'service', 'PENDIENTE');
update public.mechanic_jobs set status = 'ENTREGADO'
 where id = 'e2850000-0000-4000-8000-000000000040';

-- Tres garantías del mismo trabajo original, cada una vinculada.
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type,
  warranty_outcome, is_warranty_job, status
)
select ('e2850000-0000-4000-8000-0000000000' || g.n)::uuid,
       'e2850000-0000-4000-8000-000000000001',
       'e2850000-0000-4000-8000-000000000010',
       'e2850000-0000-4000-8000-000000000020',
       'GAR-' || g.n, 'warranty', 'pending', true, 'EN_CURSO'
  from (values ('51'), ('52'), ('53')) g(n);

select public.register_mechanic_job_warranty_claim(
  ('e2850000-0000-4000-8000-0000000000' || g.n)::uuid,
  'e2850000-0000-4000-8000-000000000040',
  'registro-' || g.n)
  from (values ('51'), ('52'), ('53')) g(n);

create temporary table results (label text primary key, result jsonb);

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2850000-0000-4000-8000-0000000000' || p_n)::uuid $$;

-- El guardado de líneas de un guardado con decisión: sin factura, porque la
-- decisión es la dueña del documento (como lo manda el formulario).
create or replace function pg_temp.save_line(p_job text, p_key text)
returns jsonb
language sql
as $$
  select public.save_mechanic_job_lines_v1(
    p_key,
    pg_temp.id(p_job),
    coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'updated_at', i.updated_at))
                from public.mechanic_job_items i
               where i.job_id = pg_temp.id(p_job)), '[]'::jsonb),
    jsonb_build_array(jsonb_build_object(
      'client_key', 'cable',
      'product_id', 'e2850000-0000-4000-8000-000000000030',
      'product_name', 'Cable de cambio',
      'quantity', 1,
      'unit_price', 5000,
      'item_type', 'product')),
    '[]'::jsonb,
    null,
    null,
    false);
$$;

-- La lectura con que la bandeja da por escrita una decisión cuya respuesta
-- se perdió: el evento de este taller, este trabajo y esta llave.
create or replace function pg_temp.readback(p_tenant text, p_job text, p_key text)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
    from public.mechanic_job_warranty_claim_events e
   where e.tenant_id = ('e2850000-0000-4000-8000-00000000000' || p_tenant)::uuid
     and e.warranty_job_id = pg_temp.id(p_job)
     and e.operation_key = p_key
     and e.event_type = 'decision';
$$;

create or replace function pg_temp.invoice_products(p_job text)
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(item->>'product_id' order by item->>'product_id'), '[]'::jsonb)
    from public.mechanic_jobs j
    join public.sales_invoices s on s.id = j.invoice_id and s.tenant_id = j.tenant_id
   cross join lateral jsonb_array_elements(coalesce(s.items, '[]'::jsonb)) item
   where j.id = pg_temp.id(p_job)
$$;

-- ============================================================================
-- Líneas, después la decisión: el orden de la cola
-- ============================================================================

insert into results select 'lineas_51', pg_temp.save_line('51', 'lineas-51');
select is(
  jsonb_build_array(
    (select count(*)::integer from public.mechanic_job_items where job_id = pg_temp.id('51')),
    (select invoice_id from public.mechanic_jobs where id = pg_temp.id('51')),
    (select result->'invoice' from results where label = 'lineas_51')),
  '[1, null, null]'::jsonb,
  'el guardado de líneas de un guardado con decisión deja la línea y no hace documento');

-- Un cierre aquí deja las líneas sin decisión ni documento: la bandeja tiene
-- la decisión respaldada, y la lectura dice que no se escribió.
select is(pg_temp.readback('1', '51', 'decision-51'), '[]'::jsonb,
  'antes de enviarla, la lectura de la bandeja no encuentra la decisión');

insert into results select 'decision_51',
  public.decide_mechanic_job_warranty_claim(pg_temp.id('51'), 'covered', null, 'decision-51');
select is(
  (select jsonb_build_object(
            'warranty_job_id', result->>'warranty_job_id',
            'operation_key', result->>'operation_key',
            'event_type', result->>'event_type',
            'outcome', result->>'outcome',
            'reason', result->'reason',
            'replay', result->'replay',
            'con_documento', result->>'invoice_id' is not null)
     from results where label = 'decision_51'),
  jsonb_build_object(
    'warranty_job_id', pg_temp.id('51'), 'operation_key', 'decision-51',
    'event_type', 'decision', 'outcome', 'covered', 'reason', null,
    'replay', false, 'con_documento', true),
  'la respuesta trae lo que la bandeja exige: trabajo, llave, decisión, motivo');
select is(
  jsonb_build_array(
    pg_temp.invoice_products('51'),
    (select s.total from public.sales_invoices s
       join public.mechanic_jobs j on j.invoice_id = s.id where j.id = pg_temp.id('51'))),
  '[["e2850000-0000-4000-8000-000000000030"], 0]'::jsonb,
  'la decisión que llega después de las líneas hace el documento con ellas (cubierta: sin cobro)');

-- Respuesta perdida: la lectura por taller, trabajo y llave la encuentra,
-- como empleado del taller (con RLS) y con los mismos campos.
select set_config('test.decision_51',
  (select result->>'id' from results where label = 'decision_51'), true);
set local role authenticated;
select is(
  (select jsonb_build_array(
            jsonb_array_length(pg_temp.readback('1', '51', 'decision-51')),
            pg_temp.readback('1', '51', 'decision-51')->0->>'id')),
  jsonb_build_array(1, current_setting('test.decision_51')),
  'tras una respuesta perdida, la lectura del taller encuentra ese mismo evento');
reset role;

-- La repetición con la misma llave (el reenvío de la bandeja) no hace otra
-- decisión ni otro documento.
insert into results select 'replay_51',
  public.decide_mechanic_job_warranty_claim(pg_temp.id('51'), 'covered', null, 'decision-51');
select is(
  jsonb_build_array(
    (select (result->>'replay')::boolean from results where label = 'replay_51'),
    (select result->>'id' from results where label = 'replay_51')
      = (select result->>'id' from results where label = 'decision_51'),
    (select count(*)::integer from public.mechanic_job_warranty_claim_events
      where tenant_id = 'e2850000-0000-4000-8000-000000000001'
        and warranty_job_id = pg_temp.id('51') and event_type = 'decision'),
    (select count(*)::integer from public.sales_invoices s
       join public.mechanic_jobs j on j.invoice_id = s.id
      where j.id = pg_temp.id('51'))),
  '[true, true, 1, 1]'::jsonb,
  'el reenvío con la misma llave devuelve el mismo evento: una decisión, un documento');

-- ============================================================================
-- Al revés: la decisión antes que las líneas deja el documento sin ellas
-- ============================================================================

insert into results select 'decision_52',
  public.decide_mechanic_job_warranty_claim(pg_temp.id('52'), 'covered', null, 'decision-52');
insert into results select 'lineas_52', pg_temp.save_line('52', 'lineas-52');
select is(
  jsonb_build_array(
    (select count(*)::integer from public.mechanic_job_items where job_id = pg_temp.id('52')),
    pg_temp.invoice_products('52')),
  '[1, []]'::jsonb,
  'si la decisión se adelanta a las líneas, su documento queda sin ellas: por eso va detrás en la cola');

-- ============================================================================
-- Rechazo, llave de otra decisión y otro taller
-- ============================================================================

select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
      pg_temp.id('53'), 'not_covered', null, 'decision-53')$$,
  'P0001',
  'Rechazar una garantía requiere una justificación',
  'una decisión que el servidor rechaza sale con P0001 (la bandeja no la reintenta)');
select is(
  jsonb_build_array(
    pg_temp.readback('1', '53', 'decision-53'),
    (select invoice_id from public.mechanic_jobs where id = pg_temp.id('53')),
    (select warranty_outcome from public.mechanic_jobs where id = pg_temp.id('53'))),
  '[[], null, "pending"]'::jsonb,
  'y no deja evento, documento ni cobertura');

select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
      pg_temp.id('51'), 'not_covered', 'Otra decisión', 'decision-51')$$,
  '23505',
  'La clave de operación ya pertenece a otra decisión de garantía',
  'una llave nunca cambia de decisión');

select pg_temp.as_user('92');
select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
      pg_temp.id('53'), 'covered', null, 'decision-53-otro')$$,
  '42501',
  'Workshop record does not belong to the active tenant',
  'otro taller no decide una garantía que no es suya');
set local role authenticated;
select is(pg_temp.readback('1', '51', 'decision-51'), '[]'::jsonb,
  'ni lee su evento, aunque tenga la llave');
reset role;
select pg_temp.as_user('91');

-- ============================================================================
-- El estado después de la decisión
-- ============================================================================

insert into results select 'estado_51', public.transition_mechanic_job_status(
  pg_temp.id('51'),
  (select s.id from public.job_statuses s
    where s.tenant_id = 'e2850000-0000-4000-8000-000000000001'
      and s.code = 'FINALIZADO' and s.is_active),
  'estado-51');
select is(
  jsonb_build_array(
    (select s.status from public.sales_invoices s
       join public.mechanic_jobs j on j.invoice_id = s.id where j.id = pg_temp.id('51')),
    (select inventory_qty from public.products
      where id = 'e2850000-0000-4000-8000-000000000030')),
  '["confirmed", 9]'::jsonb,
  'el estado que va detrás de la decisión confirma su documento y descuenta el repuesto');

select * from finish();
rollback;
