begin;

select plan(9);

-- La bandeja de cotizaciones trae las del taller (20261102100000): una
-- «Cotización» sin bicicleta recibida se lista con su estado leído como el de
-- la bandeja; un presupuesto, un trabajo eliminado o archivado y lo de otro
-- taller no.

insert into public.tenants (id, shop_name) values
  ('c0a90000-0000-4000-8000-000000000001', 'Taller bandeja A'),
  ('c0a90000-0000-4000-8000-000000000002', 'Taller bandeja B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0a90000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'bandeja-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0a90000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'web@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions) values
  ('c0a90000-0000-4000-8000-000000000091', 'c0a90000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb);

insert into public.customers (id, tenant_id, name) values
  ('c0a90000-0000-4000-8000-000000000011', 'c0a90000-0000-4000-8000-000000000001', 'Cliente Taller'),
  ('c0a90000-0000-4000-8000-000000000012', 'c0a90000-0000-4000-8000-000000000002', 'Cliente Otro');
insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0a90000-0000-4000-8000-000000000013', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000092', 'Web', 'web@example.invalid', '+56955556666', true);

insert into public.products (
  id, tenant_id, name, sku, price, tax_rate, product_type, is_service, is_active,
  is_published, show_on_website
) values (
  'c0a90000-0000-4000-8000-000000000021', 'c0a90000-0000-4000-8000-000000000001',
  'Neumático 29 x 2.25', 'INBOX-1', 30000, 19, 'product', false, true, true, true
);
update public.products set inventory_qty = 5, stock_quantity = 5
 where id = 'c0a90000-0000-4000-8000-000000000021';

-- Una cotización del sitio, para ver las dos fuentes juntas.
select set_config('request.jwt.claims', '{"sub":"c0a90000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a90000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('inbox.web', public.request_public_customer_quote_v1(
  'c0a90000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5d1c2a3b-4d5e-4f60-8a71-0000000000a1","notify_whatsapp":true,
    "items":[{"product_id":"c0a90000-0000-4000-8000-000000000021","quantity":1}]}')::text, true);
reset role;

-- Trabajos del taller, sembrados sin pasar por los comandos.
set local session_replication_role = replica;
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, job_number, job_type, workflow_kind, intake_kind,
  quotation_status, quotation_valid_until, total_cost, status, deleted_at, archive_reason
) values
  ('c0a90000-0000-4000-8000-000000000031', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-OFFER', 'quotation', 'quotation', 'unspecified',
   'pending', now() + interval '7 days', 45000, 'PENDIENTE', null, null),
  ('c0a90000-0000-4000-8000-000000000032', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-EMPTY', 'quotation', 'quotation', 'unspecified',
   'pending', now() + interval '7 days', 0, 'PENDIENTE', null, null),
  ('c0a90000-0000-4000-8000-000000000033', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-LATE', 'quotation', 'quotation', 'unspecified',
   'pending', now() - interval '1 day', 12000, 'PENDIENTE', null, null),
  ('c0a90000-0000-4000-8000-000000000034', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-NO', 'quotation', 'quotation', 'unspecified',
   'rejected', null, 9000, 'PENDIENTE', null, null),
  ('c0a90000-0000-4000-8000-000000000035', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-YES', 'quotation', 'quotation', 'unspecified',
   'approved', null, 20000, 'PENDIENTE', null, null),
  ('c0a90000-0000-4000-8000-000000000036', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-OLD', 'quotation', 'quotation', 'unspecified',
   'expired', null, 7000, 'PENDIENTE', null, null),
  ('c0a90000-0000-4000-8000-000000000037', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-CONV', 'service', 'service', 'component',
   null, null, 31000, 'EN_CURSO', null, null),
  ('c0a90000-0000-4000-8000-000000000038', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-BIKE', 'quotation', 'quotation', 'bike',
   'pending', now() + interval '7 days', 50000, 'PRESUPUESTO', null, null),
  ('c0a90000-0000-4000-8000-000000000039', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-GONE', 'quotation', 'quotation', 'unspecified',
   'pending', now() + interval '7 days', 1000, 'PENDIENTE', now(), null),
  ('c0a90000-0000-4000-8000-000000000040', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-ARCH', 'quotation', 'quotation', 'unspecified',
   'pending', now() + interval '7 days', 1000, 'PENDIENTE', null, 'test'),
  ('c0a90000-0000-4000-8000-000000000041', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000011', 'QA-BIKE-CONV', 'service', 'service', 'bike',
   null, null, 80000, 'EN_CURSO', null, null),
  ('c0a90000-0000-4000-8000-000000000042', 'c0a90000-0000-4000-8000-000000000002',
   'c0a90000-0000-4000-8000-000000000012', 'QB-OFFER', 'quotation', 'quotation', 'unspecified',
   'pending', now() + interval '7 days', 5000, 'PENDIENTE', null, null);

insert into public.mechanic_job_items (id, tenant_id, job_id, product_name, quantity, unit_price) values
  ('c0a90000-0000-4000-8000-000000000051', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000031', 'Mantención completa', 1, 35000),
  ('c0a90000-0000-4000-8000-000000000052', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000031', 'Cadena 12v', 1, 10000),
  ('c0a90000-0000-4000-8000-000000000053', 'c0a90000-0000-4000-8000-000000000001',
   'c0a90000-0000-4000-8000-000000000033', 'Ajuste de frenos', 1, 12000);

insert into public.mechanic_job_mode_events (
  tenant_id, job_id, event_type, from_workflow_kind, to_workflow_kind,
  from_intake_kind, to_intake_kind, operation_key
) values
  ('c0a90000-0000-4000-8000-000000000001', 'c0a90000-0000-4000-8000-000000000037',
   'converted_to_billable', 'quotation', 'service', 'unspecified', 'component', 'inbox-conv-1'),
  ('c0a90000-0000-4000-8000-000000000001', 'c0a90000-0000-4000-8000-000000000041',
   'converted_to_billable', 'quotation', 'service', 'bike', 'bike', 'inbox-conv-2');
set local session_replication_role = origin;

select set_config('request.jwt.claims', '{"sub":"c0a90000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a90000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('inbox.a', public.customer_quote_inbox_v1('c0a90000-0000-4000-8000-000000000001')::text, true);
select set_config('inbox.offered', public.customer_quote_inbox_v1(
  'c0a90000-0000-4000-8000-000000000001', 'offered')::text, true);
reset role;

select is(
  (select string_agg((e ->> 'number') || ':' || (e ->> 'status'), ',' order by e ->> 'number' collate "C")
     from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
    where e ->> 'source' = 'workshop'),
  'QA-CONV:accepted,QA-EMPTY:confirming,QA-LATE:expired,QA-NO:rejected,QA-OFFER:offered,QA-OLD:expired,QA-YES:accepted',
  'every shop quotation is listed with its state read as the inbox state');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
               where e ->> 'number' in ('QA-BIKE', 'QA-BIKE-CONV')),
  'a bike service budget stays in Trabajos, before and after its conversion');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
               where e ->> 'number' in ('QA-GONE', 'QA-ARCH')),
  'a deleted or archived job is not listed');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
               where e ->> 'number' = 'QB-OFFER'),
  'another shop''s quotation is never listed');
select is(
  (select (e ->> 'lines') || '|' || (e ->> 'total')::numeric::integer || '|' || (e ->> 'customerName')
          || '|' || (e ->> 'converted') || '|' || ((e ->> 'expiresAt') is not null)::text
          || '|' || coalesce(e ->> 'notifyWhatsapp', 'none')
     from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
    where e ->> 'number' = 'QA-OFFER'),
  '2|45000|Cliente Taller|false|true|none',
  'a pending shop quotation carries its lines, total, customer and validity');
select is(
  (select (e ->> 'converted') || '|' || coalesce(e ->> 'expiresAt', 'none')
     from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
    where e ->> 'number' = 'QA-CONV'),
  'true|none', 'a converted quotation is accepted and says so');
select is(
  (select string_agg((e ->> 'notifyEmail') || '|' || (e ->> 'notifyWhatsapp'), ',')
     from jsonb_array_elements(current_setting('inbox.a')::jsonb -> 'quotes') e
    where e ->> 'source' <> 'workshop'),
  'false|true', 'the web quote is still listed beside them, with the notices its customer chose');
select is(
  current_setting('inbox.a')::jsonb -> 'counts',
  '{"accepted": 2, "confirming": 2, "expired": 2, "offered": 1, "rejected": 1}'::jsonb,
  'the counts add the shop and the site');
select is(
  (select string_agg(e ->> 'number', ',')
     from jsonb_array_elements(current_setting('inbox.offered')::jsonb -> 'quotes') e),
  'QA-OFFER', 'the status filter applies to shop quotations too');

select * from finish();
rollback;
