-- An Instagram or Messenger contact is shown by the name Meta gives for it,
-- not by «Instagram • 1B5849» (2026-11-09). The webhook claims the contacts
-- that have no profile, asks Meta, and records the answer.
begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name) values
  ('c0a7ac70-0000-4000-8000-000000000001', 'Meta Contact Names Tenant A'),
  ('c0a7ac70-0000-4000-8000-000000000002', 'Meta Contact Names Tenant B');

insert into public.meta_channels (
  id, tenant_id, provider, external_account_id, display_name, is_active
) values
  (
    'c0a7ac70-0001-4000-8000-000000000001',
    'c0a7ac70-0000-4000-8000-000000000001',
    'instagram', 'ig-names-account-a', 'Instagram Names A', true
  ),
  (
    'c0a7ac70-0001-4000-8000-000000000002',
    'c0a7ac70-0000-4000-8000-000000000002',
    'instagram', 'ig-names-account-b', 'Instagram Names B', true
  );

create temporary table contact as
select
  'ig-names-user-1'::text as external_user_id,
  'Instagram • ' || upper(substr(md5('ig-names-user-1'), 1, 6)) as code_title;

-- 1. Without a profile the contact is a code, as before.
select public.ingest_meta_message(
  'instagram', 'ig-names-account-a',
  'meta:instagram:message:ig-names-account-a:mid-1', 'mid-1',
  'ig-names-user-1', null, null, 'text', 'Hola, ¿tienen cámaras?',
  now() - interval '3 minutes', '{}'::jsonb
);

select is(
  (
    select conversation.title
    from public.meta_conversation_bindings binding
    join public.conversations conversation
      on conversation.id = binding.conversation_id
    where binding.external_user_id = 'ig-names-user-1'
  ),
  (select code_title from contact),
  'a contact Meta has not named is titled with the provider and a code'
);
select is(
  (
    select message.metadata->>'contact_label'
    from public.messages message
    where message.external_message_id like '%mid-1'
      and message.tenant_id = 'c0a7ac70-0000-4000-8000-000000000001'
  ),
  (select code_title from contact),
  'and its message is labelled with the same code'
);

-- 2. The webhook claims it once.
create temporary table first_claim as
select public.claim_meta_contact_profiles_due(
  'instagram', 'ig-names-account-a', 3
) as claim;

select is(
  (select jsonb_array_length(claim->'contacts') from first_claim),
  1,
  'a contact without a profile is due'
);
select is(
  (select claim->'contacts'->0->>'external_user_id' from first_claim),
  'ig-names-user-1',
  'the claim names the scoped id to ask Meta about'
);
select is(
  (select claim->>'channel_id' from first_claim),
  'c0a7ac70-0001-4000-8000-000000000001',
  'and the channel whose token asks'
);
select is(
  jsonb_array_length(
    public.claim_meta_contact_profiles_due('instagram', 'ig-names-account-a', 3)
      ->'contacts'
  ),
  0,
  'a burst of events asks Meta once: the claim stamps the attempt'
);

-- 3. Meta refuses: the code stays, and the contact waits a day.
select is(
  public.record_meta_contact_profile(
    (select (claim->'contacts'->0->>'binding_id')::uuid from first_claim),
    null, null, 'graph_10', false
  )->>'resolved',
  'false',
  'a refusal resolves nothing'
);
select is(
  (
    select binding.profile_error
    from public.meta_conversation_bindings binding
    where binding.external_user_id = 'ig-names-user-1'
  ),
  'graph_10',
  'the reason is kept as a code'
);
select is(
  jsonb_array_length(
    public.claim_meta_contact_profiles_due('instagram', 'ig-names-account-a', 3)
      ->'contacts'
  ),
  0,
  'a refused contact is not asked again the same day'
);

update public.meta_conversation_bindings
set profile_checked_at = clock_timestamp() - interval '25 hours'
where external_user_id = 'ig-names-user-1';

select is(
  jsonb_array_length(
    public.claim_meta_contact_profiles_due('instagram', 'ig-names-account-a', 3)
      ->'contacts'
  ),
  1,
  'it is asked again a day later, which names it once Meta allows'
);

-- 4. A transient failure is asked again on the next webhook.
select public.record_meta_contact_profile(
  (select (claim->'contacts'->0->>'binding_id')::uuid from first_claim),
  null, null, 'network', true
);
select is(
  jsonb_array_length(
    public.claim_meta_contact_profiles_due('instagram', 'ig-names-account-a', 3)
      ->'contacts'
  ),
  1,
  'a transient failure does not cost a day'
);

-- 5. Meta answers: the name is everywhere the operator reads it.
select is(
  public.record_meta_contact_profile(
    (select (claim->'contacts'->0->>'binding_id')::uuid from first_claim),
    'Camila Rojas', 'camila.rojas'
  )->>'resolved',
  'true',
  'a profile resolves the contact'
);
select is(
  (
    select conversation.title
    from public.meta_conversation_bindings binding
    join public.conversations conversation
      on conversation.id = binding.conversation_id
    where binding.external_user_id = 'ig-names-user-1'
  ),
  'Camila Rojas',
  'the conversation is titled with the name'
);
select is(
  (
    select binding.contact_name || ' / ' || binding.username
      || ' / ' || coalesce(binding.profile_error, 'sin error')
    from public.meta_conversation_bindings binding
    where binding.external_user_id = 'ig-names-user-1'
  ),
  'Camila Rojas / camila.rojas / sin error',
  'the contact keeps name and username, and the old reason is cleared'
);
select is(
  jsonb_array_length(
    public.claim_meta_contact_profiles_due('instagram', 'ig-names-account-a', 3)
      ->'contacts'
  ),
  0,
  'a named contact is never due'
);

select public.ingest_meta_message(
  'instagram', 'ig-names-account-a',
  'meta:instagram:message:ig-names-account-a:mid-2', 'mid-2',
  'ig-names-user-1', null, null, 'text', 'Gracias',
  now() - interval '1 minute', '{}'::jsonb
);
select is(
  (
    select string_agg(distinct message.metadata->>'contact_label', ', ')
      || ' / ' || bool_or(message.metadata ?| array[
        'external_account_id', 'external_user_id', 'contact_name', 'username'
      ])::text
    from public.messages message
    where message.tenant_id = 'c0a7ac70-0000-4000-8000-000000000001'
  ),
  (select code_title from contact) || ' / false',
  'message metadata keeps its pseudonymous label and carries no name'
);
select is(
  (
    select conversation.title
    from public.meta_conversation_bindings binding
    join public.conversations conversation
      on conversation.id = binding.conversation_id
    where binding.external_user_id = 'ig-names-user-1'
  ),
  'Camila Rojas',
  'and the title is not reset to the code'
);

-- 6. A conversation reopened for a known contact keeps the name.
-- Archiving is audited: it needs a real actor.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'c0a7ac70-0000-4000-8000-000000000091',
  'authenticated', 'authenticated', 'names-staff@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', 'c0a7ac70-0000-4000-8000-000000000001'),
  now(), now()
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config(
  'request.jwt.claim.sub', 'c0a7ac70-0000-4000-8000-000000000091', true
);
update public.conversations conversation
set status = 'resolved'
from public.meta_conversation_bindings binding
where conversation.id = binding.conversation_id
  and binding.external_user_id = 'ig-names-user-1';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

select public.ingest_meta_message(
  'instagram', 'ig-names-account-a',
  'meta:instagram:message:ig-names-account-a:mid-3', 'mid-3',
  'ig-names-user-1', null, null, 'text', 'Hola de nuevo',
  now(), '{}'::jsonb
);
select is(
  (
    select conversation.title || ' / ' || conversation.status
    from public.meta_conversation_bindings binding
    join public.conversations conversation
      on conversation.id = binding.conversation_id
    where binding.external_user_id = 'ig-names-user-1'
  ),
  'Camila Rojas / active',
  'the new conversation of a known contact is titled with the name'
);

-- 7. Many Instagram accounts have no display name: the username names them.
select public.ingest_meta_message(
  'instagram', 'ig-names-account-a',
  'meta:instagram:message:ig-names-account-a:mid-4', 'mid-4',
  'ig-names-user-2', null, null, 'text', 'Buenas',
  now(), '{}'::jsonb
);
select public.record_meta_contact_profile(
  (
    select binding.id from public.meta_conversation_bindings binding
    where binding.external_user_id = 'ig-names-user-2'
  ),
  null, '@solo.usuario'
);
select is(
  (
    select conversation.title || ' / ' || binding.username
    from public.meta_conversation_bindings binding
    join public.conversations conversation
      on conversation.id = binding.conversation_id
    where binding.external_user_id = 'ig-names-user-2'
  ),
  '@solo.usuario / solo.usuario',
  'a contact with only a username is shown as @username, stored without the @'
);

-- 8. A title an operator wrote is not replaced.
select public.ingest_meta_message(
  'instagram', 'ig-names-account-a',
  'meta:instagram:message:ig-names-account-a:mid-5', 'mid-5',
  'ig-names-user-3', null, null, 'text', 'Hola',
  now(), '{}'::jsonb
);
update public.conversations conversation
set title = 'Cliente de la Trek roja'
from public.meta_conversation_bindings binding
where conversation.id = binding.conversation_id
  and binding.external_user_id = 'ig-names-user-3';
select public.record_meta_contact_profile(
  (
    select binding.id from public.meta_conversation_bindings binding
    where binding.external_user_id = 'ig-names-user-3'
  ),
  'Otra Persona', 'otra.persona'
);
select is(
  (
    select conversation.title || ' / ' || binding.contact_name
    from public.meta_conversation_bindings binding
    join public.conversations conversation
      on conversation.id = binding.conversation_id
    where binding.external_user_id = 'ig-names-user-3'
  ),
  'Cliente de la Trek roja / Otra Persona',
  'the operator''s title stays, and the contact still learns its name'
);

-- 9. Tenants do not see each other's contacts.
select public.ingest_meta_message(
  'instagram', 'ig-names-account-b',
  'meta:instagram:message:ig-names-account-b:mid-6', 'mid-6',
  'ig-names-user-b', null, null, 'text', 'Hola',
  now(), '{}'::jsonb
);
select is(
  (
    select claim->'contacts'->0->>'external_user_id'
      || ' / ' || jsonb_array_length(claim->'contacts')
    from (
      select public.claim_meta_contact_profiles_due(
        'instagram', 'ig-names-account-b', 10
      ) as claim
    ) claimed
  ),
  'ig-names-user-b / 1',
  'a claim returns only the contacts of its own channel'
);
select is(
  public.claim_meta_contact_profiles_due('instagram', 'no-such-account', 3)
    ->'contacts',
  '[]'::jsonb,
  'an unknown account claims nothing'
);

-- 10. Only the server asks and records.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"c0a7ac70-0000-4000-8000-000000000091"}',
  true
);
select throws_ok(
  $$select public.claim_meta_contact_profiles_due(
      'instagram', 'ig-names-account-a', 3
    )$$,
  '42501',
  null,
  'a signed-in user cannot claim contact profiles'
);
select throws_ok(
  $$select public.record_meta_contact_profile(
      'c0a7ac70-0001-4000-8000-000000000001', 'Intruso', 'intruso'
    )$$,
  '42501',
  null,
  'nor record one'
);
reset role;

select * from finish();
rollback;
