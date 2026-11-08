-- A card sent through the WhatsApp outbox keeps its answer state.
-- Regression of 2026-11-08 (PG-00672): completing the send wrote the
-- transport outcome «accepted» into the card's `status`, so the customer's
-- «Aprobar presupuesto» was refused as «already has a terminal response».
begin;
select plan(8);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- All data is synthetic, rolled back, and dispatch is disabled in this tx.
update public.whatsapp_outbox_runtime set enabled = false;
insert into public.tenants(id, shop_name) values
  ('9f032300-0000-4000-8000-000000000001', 'Outbox Card Test');
insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('9f032300-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'outbox-card-test@example.invalid', '', now(), '{}',
  '{"tenant_id":"9f032300-0000-4000-8000-000000000001"}', now(), now());
delete from public.user_profiles where user_id = '9f032300-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('9f032300-0000-4000-8000-000000000091', '9f032300-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.whatsapp_channels(id, tenant_id, phone_number_id, display_name, is_active)
values ('9f032300-0000-4000-8000-000000000131', '9f032300-0000-4000-8000-000000000001',
  'outbox-card-test', 'Synthetic', true);
insert into public.conversations(id, tenant_id, type, channel, counterparty_type, title, status, created_by)
values ('9f032300-0000-4000-8000-000000000141', '9f032300-0000-4000-8000-000000000001',
  'support', 'whatsapp', 'customer', 'Synthetic', 'active', '9f032300-0000-4000-8000-000000000091');

create temporary table card_test_messages(kind text primary key, message_id uuid);
grant all on card_test_messages to authenticated, service_role;
create function pg_temp.card_request(p_kind text) returns jsonb
language sql immutable as $$
  select jsonb_build_object('conversationId', '9f032300-0000-4000-8000-000000000141',
    'phoneNumber', '+56911113333', 'phoneNumberId', 'outbox-card-test', 'type', 'text',
    'text', 'Synthetic ' || p_kind,
    'metadata', jsonb_build_object('client_message_id', 'card-test-' || p_kind));
$$;
create function pg_temp.card_message(p_kind text) returns uuid
language sql stable as $$
  select message_id from card_test_messages where kind = p_kind;
$$;

-- Four sends from staff, as the workshop notices are queued.
select set_config('request.jwt.claims',
  '{"sub":"9f032300-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f032300-0000-4000-8000-000000000091', true);
set local role authenticated;
insert into card_test_messages
select kind, (public.enqueue_whatsapp_message_v1(pg_temp.card_request(kind))->>'message_id')::uuid
  from (values ('card'), ('plain'), ('answered'), ('refused')) as sends(kind);
reset role;

-- The worker's capability, one per send (c, p, a, r).
update public.whatsapp_outbox o set state = 'dispatched', attempts = 1,
  token_hash = encode(extensions.digest(repeat(left(t.kind, 1), 64), 'sha256'), 'hex'),
  lease_until = now() + interval '2 minutes'
from card_test_messages t
where o.message_id = t.message_id;

-- A card that already carries an answer (recorded before the late
-- completion) must keep it. Written by the server, as the guard requires.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
update public.messages
set metadata = metadata || jsonb_build_object('status', 'declined', 'responded_at', now())
where id = pg_temp.card_message('answered');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
do $$
declare
  v_send record;
begin
  for v_send in select kind, message_id from card_test_messages loop
    if public.claim_whatsapp_outbox_v1(v_send.message_id, repeat(left(v_send.kind, 1), 64)) is null then
      raise exception 'could not claim %', v_send.kind;
    end if;
    if v_send.kind <> 'refused'
       and not public.start_whatsapp_outbox_send_v1(v_send.message_id, repeat(left(v_send.kind, 1), 64)) then
      raise exception 'could not fence %', v_send.kind;
    end if;
  end loop;
end $$;

-- What whatsapp-deliver sends back for each one.
select ok(public.finish_whatsapp_outbox_v1(pg_temp.card_message('card'), repeat('c', 64), 'accepted',
  '{"external_message_id":"wamid.card-test","type":"action_request",
    "metadata":{"status":"pending","action_type":"approve_quote",
                "action_allowed_actions":["approve_quote","reject_quote"]}}'),
  'Meta accepts the quote card');
select ok(public.finish_whatsapp_outbox_v1(pg_temp.card_message('plain'), repeat('p', 64), 'accepted',
  '{"external_message_id":"wamid.plain-test"}'), 'Meta accepts a plain message');
select ok(public.finish_whatsapp_outbox_v1(pg_temp.card_message('answered'), repeat('a', 64), 'accepted',
  '{"external_message_id":"wamid.answered-test","type":"action_request","metadata":{"status":"pending"}}'),
  'Meta accepts a card that already has an answer');
select ok(public.finish_whatsapp_outbox_v1(pg_temp.card_message('refused'), repeat('r', 64), 'failed',
  '{"type":"action_request","error":"synthetic_refusal","metadata":{"status":"failed"}}'),
  'Meta refuses a card');
reset role;

select is(
  (select array[metadata->>'status', metadata->>'whatsapp_status', external_status, type]
     from public.messages where id = pg_temp.card_message('card')),
  array['pending', 'accepted', 'accepted', 'action_request'],
  'a sent card still waits for the customer; the send state lives in whatsapp_status');
select is((select metadata->>'status' from public.messages where id = pg_temp.card_message('plain')),
  'accepted', 'other messages complete as before');
select is((select metadata->>'status' from public.messages where id = pg_temp.card_message('answered')),
  'declined', 'a recorded answer is never overwritten by the send');
select is((select metadata->>'status' from public.messages where id = pg_temp.card_message('refused')),
  'failed', 'a refused card is not left waiting');

select * from finish();
rollback;
