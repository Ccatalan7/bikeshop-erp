begin;

select no_plan();

-- Correo que trabaja (20261106260000): lo que espera respuesta, el banco falso
-- y el resumen de la mañana. Nombres, direcciones y textos son inventados.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7d00000-0000-4000-8000-000000000001', 'Taller Seguir', 'seguir@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7d00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'caja-seguir@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7d00000-0000-4000-8000-000000000091', 'a7d00000-0000-4000-8000-000000000001', 'cashier', '{}', true);

set local session_replication_role = replica;
insert into public.suppliers (id, tenant_id, name, email, is_active) values
  ('a7d00000-0000-4000-8000-000000000021', 'a7d00000-0000-4000-8000-000000000001',
   'Repuestos Inventados', 'ventas@repuestos-inventados.example', true);
insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  ('a7d00000-0000-4000-8000-000000000031', 'a7d00000-0000-4000-8000-000000000001',
   'Cliente Inventado', '+56 9 0000 0031', 'cliente@cliente-inventado.example', true);
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7d00000-0000-4000-8000-000000000001', 'a7d00000-0000-4000-8000-000000000091', 'gmail',
   'taller@seguir.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7d00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true where tenant_id = 'a7d00000-0000-4000-8000-000000000001';
-- Con la casilla encendida, su dirección es «de la casa».
select public.mail_prepare_tenant_v1('a7d00000-0000-4000-8000-000000000001');

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7d00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    -- Mandado ayer, pregunta: espera, todavía no vence.
    jsonb_build_object('provider_message_id', 'out-pregunta', 'direction', 'out', 'provider_thread_id', 'th-1',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('ventas@repuestos-inventados.example'),
      'subject', 'Pastillas de freno', 'received_at', now() - interval '1 day',
      'body_text', E'Hola, ¿tienen pastillas B01S?\n\nEl mar, 4 nov, Repuestos escribió:\n> Hola'),
    -- Mandado hace 4 días, no pide nada: no espera.
    jsonb_build_object('provider_message_id', 'out-aviso', 'direction', 'out', 'provider_thread_id', 'th-2',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('ventas@repuestos-inventados.example'),
      'subject', 'Comprobante', 'received_at', now() - interval '4 days',
      'body_text', E'Les mando el comprobante del pago.\n\nEl lun, 3 nov, Repuestos escribió:\n> ¿Nos confirmas el pago?'),
    -- A la propia casilla: no espera a nadie.
    jsonb_build_object('provider_message_id', 'out-interno', 'direction', 'out', 'provider_thread_id', 'th-6',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('taller@seguir.example'),
      'subject', 'Nota', 'received_at', now() - interval '6 days', 'body_text', '¿Revisamos esto mañana?'),
    -- Al cliente, hace 4 días, pregunta: venció.
    jsonb_build_object('provider_message_id', 'out-vencido', 'direction', 'out', 'provider_thread_id', 'th-3',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('cliente@cliente-inventado.example'),
      'subject', 'Tu bici', 'received_at', now() - interval '4 days', 'body_text', 'Hola, ¿te acomoda retirarla el martes?'),
    -- Preguntado y respondido en el hilo.
    jsonb_build_object('provider_message_id', 'out-respondido', 'direction', 'out', 'provider_thread_id', 'th-4',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('ventas@repuestos-inventados.example'),
      'subject', 'Despacho', 'received_at', now() - interval '5 days', 'body_text', 'Quedo atento a la fecha de despacho.'),
    jsonb_build_object('provider_message_id', 'in-respuesta', 'provider_thread_id', 'th-4',
      'from_address', 'ventas@repuestos-inventados.example', 'subject', 'Re: Despacho',
      'received_at', now() - interval '3 days', 'provider_read', true, 'body_text', 'Sale el jueves.'),
    -- Dos seguidos en el mismo hilo: espera el último.
    jsonb_build_object('provider_message_id', 'out-superado', 'direction', 'out', 'provider_thread_id', 'th-5',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('ventas@repuestos-inventados.example'),
      'subject', 'Cotización', 'received_at', now() - interval '6 days', 'body_text', '¿Nos cotizan 10 cadenas?'),
    jsonb_build_object('provider_message_id', 'out-segundo', 'direction', 'out', 'provider_thread_id', 'th-5',
      'from_address', 'taller@seguir.example', 'to_addresses', jsonb_build_array('ventas@repuestos-inventados.example'),
      'subject', 'Re: Cotización', 'received_at', now() - interval '2 days', 'body_text', '¿Pudieron verlo?'),
    -- Un reclamo con el courier: dos correos del caso, el último hace 8 días.
    jsonb_build_object('provider_message_id', 'reclamo-1', 'provider_thread_id', 'th-claim',
      'from_address', 'clientes@starken.cl', 'subject', 'Caso registrado: XQ-123456 reclamo por cobro indebido',
      'received_at', now() - interval '10 days', 'provider_read', true, 'body_text', 'Registramos su caso.'),
    jsonb_build_object('provider_message_id', 'reclamo-2', 'provider_thread_id', 'th-claim',
      'from_address', 'clientes@starken.cl', 'subject', 'Re: Caso registrado: XQ-123456 reclamo por cobro indebido',
      'received_at', now() - interval '8 days', 'provider_read', true, 'body_text', 'Estamos revisando su caso.'),
    -- Bancos: el falso por el nombre, el falso por el asunto, el de verdad y
    -- un cliente que manda su comprobante.
    jsonb_build_object('provider_message_id', 'banco-falso', 'from_address', 'alertas@seguridad-cuenta.example',
      'from_name', 'Banco de Chile', 'subject', 'Su cuenta fue bloqueada', 'received_at', now() - interval '2 hours'),
    jsonb_build_object('provider_message_id', 'asunto-falso', 'from_address', 'avisos@otro-dominio.example',
      'from_name', 'Notificaciones', 'subject', 'BancoEstado: valida tus datos', 'received_at', now() - interval '3 hours'),
    jsonb_build_object('provider_message_id', 'banco-real', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos', 'received_at', now() - interval '1 hour',
      'body_text', 'Le informamos que Cliente Inventado le ha transferido $45.990 , el día de hoy.'),
    jsonb_build_object('provider_message_id', 'comprobante', 'from_address', 'persona@gmail.com',
      'from_name', 'Persona Inventada', 'subject', 'Comprobante transferencia BancoEstado',
      'received_at', now() - interval '4 hours')
  ))->>'new', '14', 'fourteen messages enter');

create temporary table ids on commit drop as
  select provider_message_id as k, id from public.mail_messages
   where tenant_id = 'a7d00000-0000-4000-8000-000000000001';
grant select on ids to authenticated;

-- Lo que mandamos queda en la ficha de quien lo recibe.
select ok(exists (select 1 from public.mail_message_links l
                   where l.message_id = (select id from ids where k = 'out-pregunta')
                     and l.record_type = 'supplier' and l.record_id = 'a7d00000-0000-4000-8000-000000000021'),
  'a mail we sent is in the supplier''s history');
select ok(exists (select 1 from public.mail_message_links l
                   where l.message_id = (select id from ids where k = 'out-vencido')
                     and l.record_type = 'customer' and l.record_id = 'a7d00000-0000-4000-8000-000000000031'),
  'and in the customer''s');
select is((select facts->'to_party'->>'address' from public.mail_messages where id = (select id from ids where k = 'out-pregunta')),
  'ventas@repuestos-inventados.example', 'it knows who it was sent to');

-- Sólo cuenta lo que escribimos, no lo citado.
select ok(public.mail_expects_reply_internal(E'Hola, ¿tienen stock?'), 'a question asks for a reply');
select ok(public.mail_expects_reply_internal('Quedamos atentos a su confirmación.'), 'so does «quedamos atentos»');
select ok(not public.mail_expects_reply_internal(E'Gracias, recibido.\n\nEl jue, 6 nov, Ana escribió:\n> ¿Me confirmas?'),
  'a question in the quoted mail does not count');
select ok(not public.mail_expects_reply_internal(E'Listo.\n\n-----Mensaje original-----\nDe: Ana\n¿Algo más?'),
  'nor one below «Mensaje original»');

-- El banco falso
select is((select kind || '/' || coalesce(facts->>'bank_name', '') from public.mail_messages
            where id = (select id from ids where k = 'banco-falso')),
  'security/Banco de Chile', 'a stranger named «Banco de Chile» is a security warning');
select is((select kind || '/' || coalesce(facts->>'bank_name', '') from public.mail_messages
            where id = (select id from ids where k = 'asunto-falso')),
  'security/BancoEstado', 'so is a subject that names a bank and asks for data');
select is((select kind from public.mail_messages where id = (select id from ids where k = 'banco-real')),
  'transfer', 'the bank from its own domain is still a transfer');
select ok((select kind <> 'security' and not facts ? 'fake_bank' from public.mail_messages
            where id = (select id from ids where k = 'comprobante')),
  'a customer naming her bank is not a fake bank');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7d00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7d00000-0000-4000-8000-000000000091', true);

-- Esperando: lo que pide algo y nadie respondió, y el reclamo por su último correo.
select is((select string_agg(k, ',' order by k)
             from jsonb_array_elements(public.mail_inbox_v2('waiting')) e
             join ids on ids.id = (e->>'id')::uuid),
  'out-pregunta,out-segundo,out-vencido,reclamo-2', 'waiting holds what still waits for an answer');
select is((public.mail_counts_v2()->>'waiting')::int, 4, 'and its count is the list');

select is((select string_agg(k, ',' order by k)
             from jsonb_array_elements(public.mail_inbox_v2('today')) e
             join ids on ids.id = (e->>'id')::uuid
            where k like 'out-%' or k like 'reclamo-%'),
  'out-vencido,reclamo-2', 'only the overdue ones come back to «Para hoy»');

select is((public.mail_message_v1((select id from ids where k = 'out-respondido'))->'state'->>'done_text'),
  'Ya respondieron', 'an answer in the thread closes it, with nothing stored');
select is((public.mail_message_v1((select id from ids where k = 'out-superado'))->'state'->>'actionable')::boolean,
  false, 'a later mail of ours in the thread is the one that waits');
select is((public.mail_message_v1((select id from ids where k = 'out-aviso'))->'state'->>'actionable')::boolean,
  false, 'a mail that asks nothing waits for nothing');
select is((public.mail_message_v1((select id from ids where k = 'reclamo-1'))->'state'->>'actionable')::boolean,
  false, 'an older mail of the claim is history');
select is((public.mail_message_v1((select id from ids where k = 'reclamo-2'))->'state'->>'remind_to'),
  'clientes@starken.cl', 'the reminder goes to whoever wrote the claim');
select is((public.mail_message_v1((select id from ids where k = 'out-vencido'))->'state'->>'overdue')::boolean,
  true, 'four days without an answer is overdue');
select is((public.mail_message_v1((select id from ids where k = 'out-pregunta'))->'state'->>'overdue')::boolean,
  false, 'one day is not');

-- Cerrar el reclamo lo saca; deshacer lo devuelve.
select is(public.mail_mark_v1(array[(select id from ids where k = 'reclamo-2')], 'done'), 1, 'closing the claim');
select ok(not exists (select 1 from jsonb_array_elements(public.mail_inbox_v2('waiting')) e
                       where (e->>'id')::uuid = (select id from ids where k = 'reclamo-2')),
  'a closed claim leaves waiting');
select is(public.mail_mark_v1(array[(select id from ids where k = 'reclamo-2')], 'undone'), 1, 'undoing it');
select ok(exists (select 1 from jsonb_array_elements(public.mail_inbox_v2('waiting')) e
                   where (e->>'id')::uuid = (select id from ids where k = 'reclamo-2')),
  'and it waits again');

-- El resumen de la mañana cuenta lo mismo que «Para hoy».
select is((public.mail_morning_summary_v1()->>'today')::int, (public.mail_counts_v2()->>'today')::int,
  'the morning summary counts the same as «Para hoy»');
select is((public.mail_morning_summary_v1()->>'follow_ups')::int, 2, 'two follow-ups are due');
select is((public.mail_morning_summary_v1()->>'security')::int, 2, 'and two fake banks to look at');
select is((public.mail_morning_summary_v1()->>'transfers_24h')::int, 1, 'one transfer came in');
reset role;

select ok(not has_function_privilege('anon', 'public.mail_morning_summary_v1()', 'EXECUTE'),
  'anonymous callers cannot read the summary');
select ok(not has_function_privilege('authenticated', 'public.mail_in_view_internal(text, public.mail_messages, jsonb)', 'EXECUTE'),
  'the view rule is internal');

-- Una respuesta del courier (no un acuse) es nuestro turno: responder.
select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7d00000-0000-4000-8000-000000000001'),
  jsonb_build_array(jsonb_build_object('provider_message_id', 'reclamo-3', 'provider_thread_id', 'th-claim',
      'from_address', 'clientes@starken.cl', 'subject', 'Re: Caso registrado: XQ-123456 reclamo por cobro indebido',
      'received_at', now() - interval '1 hour', 'body_text', 'Su caso fue resuelto.')))->>'new', '1', 'news on the claim');
set local role authenticated;
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'reclamo-3'
             and tenant_id = 'a7d00000-0000-4000-8000-000000000001'))->'state'->>'action'),
  'reply', 'when they answer the claim, it is our turn to reply');
select ok(exists (select 1 from jsonb_array_elements(public.mail_inbox_v2('today')) e
                   where e->>'subject' like 'Re: Caso%' and (e->>'read')::boolean = false),
  'their answer is for today');
select ok(not exists (select 1 from jsonb_array_elements(public.mail_inbox_v2('waiting')) e
                       where e->>'subject' like '%XQ-123456%'),
  'and the claim no longer waits on them');
reset role;

select * from finish();
rollback;
