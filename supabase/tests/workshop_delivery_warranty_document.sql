begin;

select no_plan();

-- Comprobante de entrega y garantía (20261104200000): la primera entrega deja
-- la garantía del servicio con la política de la tienda, la de los repuestos y
-- un comprobante con la foto del trabajo; el QR liga la cuenta del portal a la
-- ficha aunque el cliente sólo haya dejado su teléfono; el cliente lee lo suyo
-- y nada más.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('b2040000-0000-4000-8000-000000000001', 'Taller entrega A',
   'entrega-a@example.invalid', 'America/Santiago', true),
  ('b2040000-0000-4000-8000-000000000002', 'Taller entrega B',
   'entrega-b@example.invalid', 'America/Santiago', true);

-- Iniciar un taller deja la sesión con su id como usuario: sin esto, todo lo
-- sembrado después queda creado por un usuario que no existe.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  -- Del equipo de A y de B.
  ('b2040000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2040000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'equipo-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  -- Clientes que crean su cuenta en el portal.
  ('b2040000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'dora@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2040000-0000-4000-8000-000000000094', 'authenticated', 'authenticated',
   'intruso@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2040000-0000-4000-8000-000000000095', 'authenticated', 'authenticated',
   'sin-confirmar@example.invalid', '', null, '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2040000-0000-4000-8000-000000000096', 'authenticated', 'authenticated',
   'con-compras@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2040000-0000-4000-8000-000000000097', 'authenticated', 'authenticated',
   'elena@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('b2040000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'repetido@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  -- Creó la cuenta con correo desde el QR y la confirmó en otro navegador.
  ('b2040000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'pendiente@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions) values
  ('b2040000-0000-4000-8000-000000000091', 'b2040000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb),
  ('b2040000-0000-4000-8000-000000000092', 'b2040000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb);

insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  -- Sólo dejó su teléfono.
  ('b2040000-0000-4000-8000-000000000011', 'b2040000-0000-4000-8000-000000000001',
   'Dora Pérez', '+56 9 1234 5678', null, true),
  -- Sin teléfono ni correo.
  ('b2040000-0000-4000-8000-000000000012', 'b2040000-0000-4000-8000-000000000001',
   'Sin Datos', null, null, true),
  -- De otro taller.
  ('b2040000-0000-4000-8000-000000000013', 'b2040000-0000-4000-8000-000000000002',
   'Cliente B', '+56 9 8888 7777', null, true),
  -- Dejó un correo que ya no usa.
  ('b2040000-0000-4000-8000-000000000018', 'b2040000-0000-4000-8000-000000000001',
   'Elena Rojas', null, 'elena.antigua@example.invalid', true),
  -- Otra ficha con el correo de alguien que viene por un QR ajeno a ella.
  ('b2040000-0000-4000-8000-000000000019', 'b2040000-0000-4000-8000-000000000001',
   'Ficha repetida', null, 'repetido@example.invalid', true);

insert into public.website_settings (tenant_id, key, value) values
  ('b2040000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-a.example.invalid/');

insert into public.bikes (id, tenant_id, customer_id, brand, model, serial_number, color) values
  ('b2040000-0000-4000-8000-000000000021', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000011', 'Trek', 'Marlin 7', 'WTU123', 'Negra');

-- Trabajos sembrados sin pasar por sus comandos.
set local session_replication_role = replica;
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, bike_id, job_number, job_type, workflow_kind, status, work_performed
) values
  ('b2040000-0000-4000-8000-000000000031', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000011', 'b2040000-0000-4000-8000-000000000021',
   'PG-T1', 'service', 'service', 'PENDIENTE', 'Mantención completa'),
  ('b2040000-0000-4000-8000-000000000032', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000012', null,
   'PG-T2', 'service', 'service', 'PENDIENTE', null),
  ('b2040000-0000-4000-8000-000000000033', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000012', null,
   'PG-T3', 'service', 'service', 'PENDIENTE', null),
  ('b2040000-0000-4000-8000-000000000034', 'b2040000-0000-4000-8000-000000000002',
   'b2040000-0000-4000-8000-000000000013', null,
   'PG-B1', 'service', 'service', 'PENDIENTE', null),
  ('b2040000-0000-4000-8000-000000000035', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000018', null,
   'PG-T5', 'service', 'service', 'PENDIENTE', null);

-- Lo que pidió y lo que encontró el taller (20261104210000).
update public.mechanic_jobs
   set client_request = 'Revisar frenos', diagnosis = 'Pastillas gastadas'
 where id = 'b2040000-0000-4000-8000-000000000031';

insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id, order_index, work_requested, work_performed) values
  ('b2040000-0000-4000-8000-000000000041', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000031', 'b2040000-0000-4000-8000-000000000021', 0,
   'Revisar cambios', 'Ajuste de cambios y frenos');

insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, item_type, product_name, description, quantity, unit_price, total_price
) values
  ('b2040000-0000-4000-8000-000000000051', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000031', 'b2040000-0000-4000-8000-000000000041',
   'service', 'Mantención general', null, 1, 25000, 25000),
  ('b2040000-0000-4000-8000-000000000052', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000031', 'b2040000-0000-4000-8000-000000000041',
   'product', 'Cadena KMC X11', null, 1, 18000, 18000),
  ('b2040000-0000-4000-8000-000000000053', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000031', 'b2040000-0000-4000-8000-000000000041',
   'adhoc', 'Limpieza de transmisión', null, 1, 5000, 5000);

insert into public.sales_invoices (
  id, tenant_id, customer_id, invoice_number, customer_name, date, status, subtotal, iva_amount, total,
  paid_amount, balance, items, notes
) values
  ('b2040000-0000-4000-8000-000000000061', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000011', 'FV-T1', 'Dora Pérez', now(), 'paid', 48000, 0, 48000,
   48000, 0,
   '[{"product_name":"Cadena KMC X11","quantity":1,"unit_price":18000,"discount":0,"line_total":18000,"cost":9000,"is_service":false}]'::jsonb,
   'nota interna'),
  ('b2040000-0000-4000-8000-000000000062', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000011', 'FV-T2', 'Dora Pérez', now(), 'draft', 1000, 0, 1000,
   0, 1000, '[]'::jsonb, null),
  ('b2040000-0000-4000-8000-000000000063', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000011', 'FV-T3', 'Dora Pérez', now(), 'cancelado', 1000, 0, 1000,
   0, 1000, '[]'::jsonb, null);
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- La política de la tienda
-- ---------------------------------------------------------------------------

select results_eq(
  $$select service_days, parts_months from public.workshop_warranty_policy_v1('b2040000-0000-4000-8000-000000000001')$$,
  $$values (14, 2)$$,
  'sin ajustes, la garantía es de 14 días el servicio y 2 meses los repuestos'
);

insert into public.company_settings (tenant_id, key, value) values
  ('b2040000-0000-4000-8000-000000000002', 'workshop_service_warranty_days', '30'),
  ('b2040000-0000-4000-8000-000000000002', 'workshop_parts_warranty_months', 'seis');

select results_eq(
  $$select service_days, parts_months from public.workshop_warranty_policy_v1('b2040000-0000-4000-8000-000000000002')$$,
  $$values (30, 2)$$,
  'cada tienda pone sus días; un valor que no es número no rompe nada'
);

-- ---------------------------------------------------------------------------
-- La entrega deja la garantía y el comprobante
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000091', true);

update public.mechanic_jobs set status = 'ENTREGADO'
 where id = 'b2040000-0000-4000-8000-000000000031';

select results_eq(
  $$select warranty_days_snapshot, parts_warranty_months_snapshot,
           (warranty_expires_at - warranty_started_at) = interval '14 days',
           parts_warranty_expires_at = warranty_started_at + interval '2 months'
      from public.mechanic_job_delivery_events
     where job_id = 'b2040000-0000-4000-8000-000000000031'$$,
  $$values (14, 2, true, true)$$,
  'la primera entrega anota 14 días del servicio y 2 meses de los repuestos'
);

select is(
  (select count(*)::integer from public.mechanic_job_delivery_documents
    where job_id = 'b2040000-0000-4000-8000-000000000031'),
  1,
  'la primera entrega deja un comprobante'
);

select results_eq(
  $$select job_number, snapshot #>> '{customer,name}', jsonb_array_length(snapshot -> 'lines'),
           snapshot #>> '{bikes,0,brand}', snapshot #>> '{bikes,0,serial_number}',
           snapshot #>> '{bikes,0,work_performed}'
      from public.mechanic_job_delivery_documents
     where job_id = 'b2040000-0000-4000-8000-000000000031'$$,
  $$values ('PG-T1'::text, 'Dora Pérez'::text, 3, 'Trek'::text, 'WTU123'::text, 'Ajuste de cambios y frenos'::text)$$,
  'el comprobante guarda quién, qué bici y lo que se hizo'
);
select results_eq(
  $$select snapshot ->> 'client_request', snapshot ->> 'diagnosis'
      from public.mechanic_job_delivery_documents
     where job_id = 'b2040000-0000-4000-8000-000000000031'$$,
  $$values ('Revisar frenos'::text, 'Pastillas gastadas'::text)$$,
  'y lo que pidió el cliente y lo que encontró el taller, como en el portal'
);
select is(
  public.ensure_job_delivery_document_v1('b2040000-0000-4000-8000-000000000031') #>> '{storefront,schemaVersion}',
  '1',
  'el comprobante trae el membrete de la tienda (20261104220000)'
);

select results_eq(
  $$select line ->> 'kind', line ->> 'name'
      from public.mechanic_job_delivery_documents document,
           jsonb_array_elements(document.snapshot -> 'lines') line
     where document.job_id = 'b2040000-0000-4000-8000-000000000031'
     order by line ->> 'name'$$,
  $$values ('part'::text, 'Cadena KMC X11'::text),
           ('other'::text, 'Limpieza de transmisión'::text),
           ('service'::text, 'Mantención general'::text)$$,
  'cada línea dice si es servicio, repuesto u otra cosa'
);

select ok(
  not exists (
    select 1 from public.mechanic_job_delivery_documents document,
                  jsonb_array_elements(document.snapshot -> 'lines') line
     where document.job_id = 'b2040000-0000-4000-8000-000000000031'
       and (line ? 'unit_price' or line ? 'total_price')
  ),
  'el comprobante no lleva precios: están en la factura'
);

-- Volver a abrirlo y entregarlo otra vez no abre otra garantía ni otro comprobante.
update public.mechanic_jobs set status = 'EN_CURSO'
 where id = 'b2040000-0000-4000-8000-000000000031';
update public.mechanic_jobs set status = 'ENTREGADO'
 where id = 'b2040000-0000-4000-8000-000000000031';

select results_eq(
  $$select count(*)::integer, count(*) filter (where starts_warranty_window)::integer
      from public.mechanic_job_delivery_events
     where job_id = 'b2040000-0000-4000-8000-000000000031'$$,
  $$values (2, 1)$$,
  'una re-entrega queda anotada sin abrir otra garantía'
);
select is(
  (select count(*)::integer from public.mechanic_job_delivery_documents
    where job_id = 'b2040000-0000-4000-8000-000000000031'),
  1,
  'una re-entrega no deja otro comprobante'
);

-- Si armar el comprobante falla, la bici igual se entrega.
select set_config('test.snapshot_def',
  pg_get_functiondef('public.job_delivery_document_snapshot_internal(uuid,uuid)'::regprocedure), true);
create or replace function public.job_delivery_document_snapshot_internal(p_tenant_id uuid, p_job_id uuid)
returns jsonb language plpgsql as $$ begin raise exception 'falla de prueba'; end; $$;

select lives_ok(
  $$update public.mechanic_jobs set status = 'ENTREGADO'
     where id = 'b2040000-0000-4000-8000-000000000032'$$,
  'una falla del comprobante no impide entregar'
);
select results_eq(
  $$select (select count(*)::integer from public.mechanic_job_delivery_events
             where job_id = 'b2040000-0000-4000-8000-000000000032' and starts_warranty_window),
           (select count(*)::integer from public.mechanic_job_delivery_documents
             where job_id = 'b2040000-0000-4000-8000-000000000032')$$,
  $$values (1, 0)$$,
  'la garantía queda abierta aunque el comprobante no se armó'
);

-- ---------------------------------------------------------------------------
-- El equipo pide el comprobante
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.ensure_job_delivery_document_v1('b2040000-0000-4000-8000-000000000032')$$,
  'falla de prueba',
  'con la falla todavía puesta, pedirlo la muestra'
);

-- Se arregla: pedirlo lo arma con la entrega original.
do $$ begin execute current_setting('test.snapshot_def'); end $$;

select is(
  public.ensure_job_delivery_document_v1('b2040000-0000-4000-8000-000000000032') ->> 'job_number',
  'PG-T2',
  'el equipo lo pide y se arma con la entrega original'
);
select is(
  (select count(*)::integer from public.mechanic_job_delivery_documents
    where job_id = 'b2040000-0000-4000-8000-000000000032'),
  1,
  'queda guardado una sola vez'
);

select ok(
  (select (document ->> 'service_warranty_days_remaining')::integer between 13 and 14
          and (document ->> 'parts_warranty_days_remaining')::integer between 55 and 62
          and document ->> 'customer_has_account' = 'false'
     from (select public.ensure_job_delivery_document_v1('b2040000-0000-4000-8000-000000000031') as document) d),
  'el comprobante dice cuántos días quedan de cada garantía y si el cliente tiene cuenta'
);

select throws_ok(
  $$select public.ensure_job_delivery_document_v1('b2040000-0000-4000-8000-000000000033')$$,
  'job_not_delivered',
  'un trabajo sin entregar no tiene comprobante'
);

select throws_ok(
  $$select public.ensure_job_delivery_document_v1('b2040000-0000-4000-8000-000000000034')$$,
  'Job not found or not accessible',
  'el trabajo de otro taller no se ve'
);

-- ---------------------------------------------------------------------------
-- El QR liga la cuenta del portal
-- ---------------------------------------------------------------------------

select set_config('test.code', public.issue_customer_portal_claim_code_v1(
  'b2040000-0000-4000-8000-000000000031', 'delivery') ->> 'code', true);

select ok(length(current_setting('test.code')) >= 40, 'el equipo saca un código largo para el QR');
select results_eq(
  $$select r ->> 'store_url', r ->> 'customer_first_name'
      from (select public.issue_customer_portal_claim_code_v1(
              'b2040000-0000-4000-8000-000000000031', 'reception') as r) issued$$,
  $$values ('https://tienda-a.example.invalid/'::text, 'Dora'::text)$$,
  'el código trae adónde lleva el QR y a quién saluda (20261104230000)'
);

-- Quien abre el QR, todavía sin cuenta.
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select results_eq(
  format($$select r ->> 'status', r ->> 'first_name', r ->> 'bike', r ->> 'job_number',
                  r ->> 'purpose', r ? 'phone', r ? 'email'
             from (select public.peek_customer_portal_claim_code_v1(
                     'b2040000-0000-4000-8000-000000000001', %L) as r) peeked$$,
         current_setting('test.code')),
  $$values ('valid'::text, 'Dora'::text, 'Trek Marlin 7'::text, 'PG-T1'::text,
            'delivery'::text, false, false)$$,
  'el QR saluda por el nombre de pila y dice qué bici es, sin teléfono ni correo'
);
select is(
  public.peek_customer_portal_claim_code_v1('b2040000-0000-4000-8000-000000000002',
    current_setting('test.code')) ->> 'status',
  'invalid',
  'en otro taller el código no dice nada'
);
select is(
  public.peek_customer_portal_claim_code_v1('b2040000-0000-4000-8000-000000000001',
    'x' || repeat('y', 50)) ->> 'status',
  'invalid',
  'un código inventado no dice nada'
);
reset role;
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000091', true);
select ok(
  not exists (select 1 from public.customer_portal_claim_codes
               where code_sha256 = current_setting('test.code')
                  or code_sha256 !~ '^[0-9a-f]{64}$'),
  'sólo se guarda la huella del código'
);

select throws_ok(
  $$select public.issue_customer_portal_claim_code_v1('b2040000-0000-4000-8000-000000000034', 'reception')$$,
  'Job not found or not accessible',
  'no se saca un código para el cliente de otro taller'
);

-- Quien no tiene el correo confirmado no liga nada.
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000095","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000095', true);
select throws_ok(
  format($$select public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001', %L, '+56912345678')$$,
         current_setting('test.code')),
  'A confirmed Auth email is required',
  'hace falta el correo confirmado'
);

-- Dora crea su cuenta: el portal ya le dejó una ficha vacía con su correo y una dirección.
set local session_replication_role = replica;
insert into public.customers (id, tenant_id, name, email, auth_user_id, is_active) values
  ('b2040000-0000-4000-8000-000000000014', 'b2040000-0000-4000-8000-000000000001',
   'dora', 'dora@example.invalid', 'b2040000-0000-4000-8000-000000000093', true);
insert into public.customer_addresses (
  id, tenant_id, customer_id, label, recipient_name, phone, street_address, street_number,
  comuna, city, region, is_default
) values ('b2040000-0000-4000-8000-000000000015', 'b2040000-0000-4000-8000-000000000001',
        'b2040000-0000-4000-8000-000000000014', 'Casa', 'Dora Pérez', '+56912345678',
        'Calle Uno', '1', 'Viña del Mar', 'Viña del Mar', 'Valparaíso', true);
set local session_replication_role = origin;

select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000093', true);

select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code'), '+56 9 9999 0000') ->> 'status',
  'phone_mismatch',
  'si la ficha tiene teléfono, tiene que calzar'
);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000002',
    current_setting('test.code'), '+56912345678') ->> 'status',
  'invalid',
  'el código de un taller no sirve en otro'
);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    'no-es-un-codigo', '+56912345678') ->> 'status',
  'invalid',
  'un código que no es no liga nada'
);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code'), '912345678') ->> 'status',
  'linked',
  'con el código y su teléfono, la cuenta queda ligada a su ficha'
);

select results_eq(
  $$select auth_user_id, email, is_active
      from public.customers where id = 'b2040000-0000-4000-8000-000000000011'$$,
  $$values ('b2040000-0000-4000-8000-000000000093'::uuid, 'dora@example.invalid'::text, true)$$,
  'la ficha del taller queda con la cuenta y el correo de la cuenta'
);
select results_eq(
  $$select auth_user_id, email, is_active
      from public.customers where id = 'b2040000-0000-4000-8000-000000000014'$$,
  $$values (null::uuid, null::text, false)$$,
  'la ficha vacía que dejó el portal se suelta y se archiva'
);
select results_eq(
  $$select count(*)::integer, bool_and(is_default)
      from public.customer_addresses
     where customer_id = 'b2040000-0000-4000-8000-000000000011'
       and street_address = 'Calle Uno'$$,
  $$values (1, true)$$,
  'la dirección que alcanzó a guardar queda en su ficha, como principal si no tenía otra'
);
select results_eq(
  $$select raw_app_meta_data ->> 'account_type',
           raw_app_meta_data -> 'customer_memberships' ->> 'b2040000-0000-4000-8000-000000000001'
      from auth.users where id = 'b2040000-0000-4000-8000-000000000093'$$,
  $$values ('public_store_customer'::text, 'b2040000-0000-4000-8000-000000000011'::text)$$,
  'la cuenta queda como cliente de la tienda con su ficha del taller'
);
select is(
  public.provision_current_public_store_customer('b2040000-0000-4000-8000-000000000001'),
  'b2040000-0000-4000-8000-000000000011'::uuid,
  'la próxima vez que entra al portal, el portal la reconoce sin chocar con la guardia'
);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code'), '912345678') ->> 'status',
  'already_yours',
  'usar el código otra vez dice que ya es suyo'
);

select is(
  public.peek_customer_portal_claim_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code')) ->> 'status',
  'linked',
  'con la cuenta ya ligada, el QR sólo invita a entrar'
);

-- La excepción de la guardia de identidad es sólo para ligar con el QR.
set local role authenticated;
select throws_ok(
  $$update public.customers set auth_user_id = 'b2040000-0000-4000-8000-000000000094'
     where id = 'b2040000-0000-4000-8000-000000000011'$$,
  '42501',
  'Customer tenant and Auth identity are immutable',
  'el cliente sigue sin poder pasarle su ficha a otra cuenta'
);
select set_config('vinabike.portal_claim_relink',
  txid_current()::text || ':b2040000-0000-4000-8000-000000000014', true);
select throws_ok(
  $$update public.customers set auth_user_id = 'b2040000-0000-4000-8000-000000000094'
     where id = 'b2040000-0000-4000-8000-000000000011'$$,
  '42501',
  'Customer tenant and Auth identity are immutable',
  'la marca de una ficha no abre otra'
);
select set_config('vinabike.portal_claim_relink', '', true);
reset role;

-- Con la cuenta ligada, ya no se saca código.
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000091', true);
select is(
  public.issue_customer_portal_claim_code_v1('b2040000-0000-4000-8000-000000000031', 'delivery') ->> 'status',
  'already_linked',
  'si el cliente ya tiene cuenta, no hace falta el QR'
);

-- Otro, con un código de una ficha que ya es de Dora.
select set_config('test.code2', public.issue_customer_portal_claim_code_v1(
  'b2040000-0000-4000-8000-000000000033', 'reception') ->> 'code', true);

select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000096","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000096', true);
set local session_replication_role = replica;
insert into public.customers (id, tenant_id, name, email, auth_user_id, is_active) values
  ('b2040000-0000-4000-8000-000000000016', 'b2040000-0000-4000-8000-000000000001',
   'con compras', 'con-compras@example.invalid', 'b2040000-0000-4000-8000-000000000096', true);
insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('b2040000-0000-4000-8000-000000000022', 'b2040000-0000-4000-8000-000000000001',
   'b2040000-0000-4000-8000-000000000016', 'Oxford', 'Merak');
set local session_replication_role = origin;
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code2'), null) ->> 'status',
  'account_has_history',
  'una cuenta que ya tiene su historia en otra ficha no se mueve sola'
);

-- Diez fallos en una hora y se detiene.
select count(public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
         'x' || n || repeat('y', 45), null))
  from generate_series(1, 10) n;
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code2'), null) ->> 'status',
  'too_many_attempts',
  'después de diez fallos en una hora no se prueba más, ni con un código bueno'
);

-- Un código vencido no sirve.
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000091', true);
select set_config('test.code3', public.issue_customer_portal_claim_code_v1(
  'b2040000-0000-4000-8000-000000000033', 'reception') ->> 'code', true);
update public.customer_portal_claim_codes set expires_at = now() - interval '1 minute'
 where code_sha256 = encode(extensions.digest(convert_to(current_setting('test.code3'), 'UTF8'), 'sha256'), 'hex');
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000094","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000094', true);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code3'), null) ->> 'status',
  'expired',
  'un código vencido no liga nada'
);

-- Elena dejó un correo que ya no usa: su ficha queda con el de su cuenta y el
-- anterior en las notas.
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000091', true);
select set_config('test.code4', public.issue_customer_portal_claim_code_v1(
  'b2040000-0000-4000-8000-000000000035', 'reception') ->> 'code', true);
select set_config('test.code5', public.issue_customer_portal_claim_code_v1(
  'b2040000-0000-4000-8000-000000000032', 'reception') ->> 'code', true);

select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000097","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000097', true);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code4'), '+56 9 5555 4444') ->> 'status',
  'linked',
  'una ficha sin teléfono se liga con el código y deja el teléfono que escribió'
);
select results_eq(
  $$select email, phone, notes like '%elena.antigua@example.invalid%'
      from public.customers where id = 'b2040000-0000-4000-8000-000000000018'$$,
  $$values ('elena@example.invalid'::text, '+56 9 5555 4444'::text, true)$$,
  'queda con el correo confirmado de su cuenta y el anterior en las notas'
);
select is(
  public.provision_current_public_store_customer('b2040000-0000-4000-8000-000000000001'),
  'b2040000-0000-4000-8000-000000000018'::uuid,
  'y su próxima entrada al portal también la reconoce'
);

-- El correo de la cuenta ya está en otra ficha de la tienda: lo une el equipo.
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000098","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000098', true);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001',
    current_setting('test.code5'), null) ->> 'status',
  'email_in_other_record',
  'si su correo ya está en otra ficha, no se liga sola: no quedan dos fichas con el mismo correo'
);
select is(
  (select auth_user_id from public.customers where id = 'b2040000-0000-4000-8000-000000000012'),
  null,
  'y la ficha del código sigue sin cuenta'
);

-- Sin código ni nada pendiente: no pasa nada y no cuenta como intento.
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000094","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000094', true);
select set_config('test.attempts94', (select count(*)::text from public.customer_portal_claim_attempts
  where auth_user_id = 'b2040000-0000-4000-8000-000000000094'), true);
select is(
  public.claim_customer_portal_code_v1('b2040000-0000-4000-8000-000000000001', null, null) ->> 'status',
  'nothing_pending',
  'al entrar sin código pendiente no pasa nada'
);
select is(
  (select count(*)::text from public.customer_portal_claim_attempts
    where auth_user_id = 'b2040000-0000-4000-8000-000000000094'),
  current_setting('test.attempts94'),
  'y no cuenta como intento'
);

-- Creó la cuenta con correo desde el QR: el código quedó en su cuenta y se
-- liga al entrar, aunque confirme en otro navegador.
update auth.users
   set raw_user_meta_data = jsonb_build_object(
     'name', 'Sin Datos',
     'vinabike_claim_code', current_setting('test.code5'),
     'vinabike_claim_phone', '+56 9 7777 6666')
 where id = 'b2040000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000099","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000099', true);
select results_eq(
  $$select r ->> 'status', r ->> 'job_id', r ->> 'first_name'
      from (select public.claim_customer_portal_code_v1(
              'b2040000-0000-4000-8000-000000000001', null, null) as r) claimed$$,
  $$values ('linked'::text, 'b2040000-0000-4000-8000-000000000032'::text, 'Sin'::text)$$,
  'el código pendiente de la cuenta la liga al entrar'
);
select results_eq(
  $$select auth_user_id, phone from public.customers where id = 'b2040000-0000-4000-8000-000000000012'$$,
  $$values ('b2040000-0000-4000-8000-000000000099'::uuid, '+56 9 7777 6666'::text)$$,
  'con el teléfono que escribió al crearla'
);
select is(
  (select raw_user_meta_data ?| array['vinabike_claim_code', 'vinabike_claim_phone']
     from auth.users where id = 'b2040000-0000-4000-8000-000000000099'),
  false,
  'y el código pendiente se borra apenas se usa'
);
select is(
  (select raw_user_meta_data ->> 'name' from auth.users where id = 'b2040000-0000-4000-8000-000000000099'),
  'Sin Datos',
  'sin tocar el resto de sus datos'
);

-- ---------------------------------------------------------------------------
-- El cliente lee lo suyo y nada más
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"b2040000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b2040000-0000-4000-8000-000000000093', true);
set local role authenticated;

select results_eq(
  $$select document ->> 'job_number', document ->> 'parts_warranty_months'
      from jsonb_array_elements(public.list_my_job_delivery_documents_v1('b2040000-0000-4000-8000-000000000001')) document$$,
  $$values ('PG-T1'::text, '2'::text)$$,
  'Dora ve su comprobante, no el de otros clientes'
);
select results_eq(
  $$select invoice ->> 'invoice_number', jsonb_array_length(invoice -> 'items'),
           (invoice -> 'items' -> 0) ? 'cost', invoice ? 'notes'
      from jsonb_array_elements(public.list_my_sales_invoices_v1('b2040000-0000-4000-8000-000000000001')) invoice$$,
  $$values ('FV-T1'::text, 1, false, false)$$,
  've sus facturas sin borradores, anuladas, costo ni notas internas'
);
select is(
  (select count(*)::integer from public.mechanic_job_delivery_documents),
  0,
  'la tabla de comprobantes no se le abre directo'
);
select throws_ok(
  $$select count(*) from public.customer_portal_claim_codes$$,
  '42501',
  null,
  'los códigos no se leen nunca directo'
);
select is(
  jsonb_array_length(public.list_my_job_delivery_documents_v1('b2040000-0000-4000-8000-000000000002')),
  0,
  'en otro taller no tiene nada'
);
reset role;

select * from finish();
rollback;
