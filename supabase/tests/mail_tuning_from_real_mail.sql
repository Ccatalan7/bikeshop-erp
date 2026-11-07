begin;

select no_plan();

-- Correo que trabaja (20261106280000): afinar con el correo real. Nombres,
-- dominios y textos son inventados.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7b00000-0000-4000-8000-000000000001', 'Taller Afinar', 'afinar@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7b00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'caja-afinar@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7b00000-0000-4000-8000-000000000091', 'a7b00000-0000-4000-8000-000000000001', 'cashier', '{}', true);

set local session_replication_role = replica;
insert into public.suppliers (id, tenant_id, name, email, website, is_active) values
  ('a7b00000-0000-4000-8000-000000000021', 'a7b00000-0000-4000-8000-000000000001',
   'Rodados', 'ventas@rodados-ficha.example', 'https://rodados-ficha.example', true),
  ('a7b00000-0000-4000-8000-000000000022', 'a7b00000-0000-4000-8000-000000000001',
   'Ciclo', null, null, true);
insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  ('a7b00000-0000-4000-8000-000000000031', 'a7b00000-0000-4000-8000-000000000001',
   'Cliente Inventada', '+56 9 0000 0031', 'clienta@cliente-afinar.example', true);
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7b00000-0000-4000-8000-000000000001', 'a7b00000-0000-4000-8000-000000000091', 'gmail',
   'taller@afinar.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7b00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true where tenant_id = 'a7b00000-0000-4000-8000-000000000001';
select public.mail_prepare_tenant_v1('a7b00000-0000-4000-8000-000000000001');

-- El proveedor por el nombre en el dominio
select is((select party_type || '/' || label
             from public.mail_resolve_sender_internal('a7b00000-0000-4000-8000-000000000001', 'pedidos@rodadosalmayor.example')),
  'supplier/Rodados', 'a domain that starts with a supplier''s whole name is that supplier');
select is((select party_type
             from public.mail_resolve_sender_internal('a7b00000-0000-4000-8000-000000000001', 'hola@ciclomania.example')),
  'unknown', 'a name shorter than six letters does not claim a domain');
select is((select party_type || '/' || label
             from public.mail_resolve_sender_internal('a7b00000-0000-4000-8000-000000000001', 'avisos@email.meta.com')),
  'platform/Meta', 'Meta writes from meta.com too');
select is((select party_type || '/' || label
             from public.mail_resolve_sender_internal('a7b00000-0000-4000-8000-000000000001', 'support@veryfi.com')),
  'platform/Veryfi', 'Veryfi is a platform');

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7b00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'rodados-pedido', 'from_address', 'pedidos@rodadosalmayor.example',
      'subject', 'Pedido 45678 despachado', 'received_at', now() - interval '2 days'),
    -- Un cliente sin respuesta y un reclamo al que nos toca responder.
    jsonb_build_object('provider_message_id', 'clienta', 'from_address', 'clienta@cliente-afinar.example',
      'subject', 'Consulta por mi bici', 'received_at', now() - interval '3 days', 'provider_read', true),
    jsonb_build_object('provider_message_id', 'reclamo-respondido', 'provider_thread_id', 'th-r',
      'in_reply_to', '<nuestro@afinar.example>', 'from_address', 'pedidos@rodadosalmayor.example',
      'subject', 'Re: Problema con el despacho', 'received_at', now() - interval '6 days', 'provider_read', true,
      'body_text', 'El despacho no nos corresponde.')
  ))->>'new', '3', 'three messages enter');

select is((select kind from public.mail_messages where provider_message_id = 'rodados-pedido'
             and tenant_id = 'a7b00000-0000-4000-8000-000000000001'),
  'supplier_order', 'its mail is a supplier order');
select ok(exists (select 1 from public.mail_message_links l
                   join public.mail_messages m on m.id = l.message_id
                  where m.provider_message_id = 'rodados-pedido'
                    and l.record_type = 'supplier' and l.record_id = 'a7b00000-0000-4000-8000-000000000021'),
  'and it is in the supplier''s history');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7b00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7b00000-0000-4000-8000-000000000091', true);

select is((public.mail_morning_summary_v1()->>'customers')::int, 1, 'the claim to answer is not counted as a customer');
select is((public.mail_morning_summary_v1()->>'follow_ups')::int, 1, 'it is a follow-up');
select ok((public.mail_morning_summary_v1()->>'follow_ups_since')::timestamptz < now() - interval '5 days',
  'and the summary says since when');
select ok((public.mail_morning_summary_v1()->>'customers_since') is not null, 'the customer line too');
reset role;

select * from finish();
rollback;
