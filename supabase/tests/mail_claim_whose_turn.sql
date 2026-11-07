begin;

select no_plan();

-- Correo que trabaja (20261106270000): en un reclamo, de quién es el turno.
-- Nombres, direcciones y textos son inventados.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7c00000-0000-4000-8000-000000000001', 'Taller Turno', 'turno@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7c00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'caja-turno@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7c00000-0000-4000-8000-000000000091', 'a7c00000-0000-4000-8000-000000000001', 'cashier', '{}', true);

set local session_replication_role = replica;
insert into public.suppliers (id, tenant_id, name, email, is_active) values
  ('a7c00000-0000-4000-8000-000000000021', 'a7c00000-0000-4000-8000-000000000001',
   'Ciclo Inventado', 'contacto@ciclo-inventado.example', true);
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7c00000-0000-4000-8000-000000000001', 'a7c00000-0000-4000-8000-000000000091', 'gmail',
   'taller@turno.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7c00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true where tenant_id = 'a7c00000-0000-4000-8000-000000000001';
select public.mail_prepare_tenant_v1('a7c00000-0000-4000-8000-000000000001');

-- El acuse se lee del comienzo del texto, o del asunto si no es respuesta.
select ok(public.mail_is_acknowledgment_internal('Caso registrado: AB-1', null), 'a registered case is an acknowledgment');
select ok(public.mail_is_acknowledgment_internal('Re: tu consulta', 'Hemos recibido su solicitud.'),
  'so is «hemos recibido» in the text');
select ok(not public.mail_is_acknowledgment_internal('Re: Caso registrado: AB-1', 'Le confirmamos la devolución.'),
  'an answer under the old subject is not');

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7c00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    -- El proveedor respondió el reclamo hace 17 días: nos toca.
    jsonb_build_object('provider_message_id', 'cc-respuesta', 'provider_thread_id', 'th-cc',
      'in_reply_to', '<nuestro-1@turno.example>',
      'from_address', 'contacto@ciclo-inventado.example', 'subject', 'Re: Fallo en logística del despacho',
      'received_at', now() - interval '17 days', 'provider_read', true,
      'body_text', 'Le informamos que el despacho no nos corresponde.'),
    -- El courier registró el caso hace 9 días: esperamos novedades.
    jsonb_build_object('provider_message_id', 'st-acuse', 'provider_thread_id', 'th-st',
      'from_address', 'clientes@starken.cl', 'subject', 'Caso registrado: AB-765432 cobro indebido',
      'received_at', now() - interval '9 days', 'provider_read', true,
      'body_text', 'Registramos su caso y lo estamos revisando.')
  ))->>'new', '2', 'two claims enter');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7c00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7c00000-0000-4000-8000-000000000091', true);

select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'cc-respuesta'))->'state'->>'action'),
  'reply', 'the supplier answered: it is our turn');
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'st-acuse'))->'state'->>'action'),
  'remind', 'the courier only acknowledged: we wait');
select is((select string_agg(e->>'subject', ' | ' order by e->>'subject')
             from jsonb_array_elements(public.mail_inbox_v2('waiting')) e),
  'Caso registrado: AB-765432 cobro indebido', 'only the acknowledged claim waits on them');
select is((select count(*)::int from jsonb_array_elements(public.mail_inbox_v2('today')) e
            where e->>'subject' in ('Re: Fallo en logística del despacho', 'Caso registrado: AB-765432 cobro indebido')),
  2, 'both are for today: one to answer, one overdue');
reset role;

-- Les respondemos al proveedor: ahora esperamos nosotros, desde nuestro correo.
select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7c00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'cc-nuestra', 'direction', 'out', 'provider_thread_id', 'th-cc',
      'from_address', 'taller@turno.example', 'to_addresses', jsonb_build_array('contacto@ciclo-inventado.example'),
      'subject', 'Re: Fallo en logística del despacho', 'received_at', now() - interval '2 days',
      'body_text', '¿Pueden revisarlo con el transportista?'),
    -- Y el courier resolvió: su respuesta es nuestro turno.
    jsonb_build_object('provider_message_id', 'st-resuelto', 'provider_thread_id', 'th-st',
      'from_address', 'clientes@starken.cl', 'subject', 'Re: Caso registrado: AB-765432 cobro indebido',
      'received_at', now() - interval '1 hour', 'body_text', 'Le confirmamos la devolución del cobro.')
  ))->>'new', '2', 'our answer and the courier''s resolution');

set local role authenticated;
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'cc-respuesta'))->'state'->>'action'),
  'remind', 'after our answer the supplier claim waits on them');
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'cc-respuesta'))->'state'->>'overdue')::boolean,
  false, 'counted from our answer, two days ago');
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'cc-nuestra'))->'state'->>'actionable')::boolean,
  false, 'our own mail in the claim thread is not a second follow-up');
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'st-resuelto'))->'state'->>'action'),
  'reply', 'the courier''s resolution is our turn');
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'st-acuse'))->'state'->>'actionable')::boolean,
  false, 'and the acknowledgment is history');
select is((select string_agg(e->>'subject', ' | ')
             from jsonb_array_elements(public.mail_inbox_v2('waiting')) e),
  'Re: Fallo en logística del despacho', 'waiting holds the supplier claim, once');
select is((public.mail_counts_v2()->>'waiting')::int, 1, 'and its count');
reset role;

select * from finish();
rollback;
