begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

insert into public.tenants (id, shop_name) values
  ('9f192101-0000-4000-8000-000000000001', 'Atomic Messaging Tenant A'),
  ('9f192101-0000-4000-8000-000000000002', 'Atomic Messaging Tenant B');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9f192101-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'atomic-staff-a@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f192101-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f192101-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'atomic-staff-a2@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f192101-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f192101-0000-4000-8000-000000000093',
    'authenticated', 'authenticated', 'atomic-staff-b@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f192101-0000-4000-8000-000000000002'),
    now(), now()
  ),
  (
    '9f192101-0000-4000-8000-000000000094',
    'authenticated', 'authenticated', 'atomic-staff-a3@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f192101-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f192101-0000-4000-8000-000000000191',
    'authenticated', 'authenticated', 'atomic-customer-a@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f192101-0000-4000-8000-000000000001'
    ),
    now(), now()
  ),
  (
    '9f192101-0000-4000-8000-000000000192',
    'authenticated', 'authenticated', 'atomic-customer-b@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f192101-0000-4000-8000-000000000001'
    ),
    now(), now()
  );

delete from public.user_profiles
where user_id in (
  '9f192101-0000-4000-8000-000000000091',
  '9f192101-0000-4000-8000-000000000092',
  '9f192101-0000-4000-8000-000000000093',
  '9f192101-0000-4000-8000-000000000094',
  '9f192101-0000-4000-8000-000000000191',
  '9f192101-0000-4000-8000-000000000192'
);
delete from public.customers
where auth_user_id in (
  '9f192101-0000-4000-8000-000000000091',
  '9f192101-0000-4000-8000-000000000092',
  '9f192101-0000-4000-8000-000000000093',
  '9f192101-0000-4000-8000-000000000094',
  '9f192101-0000-4000-8000-000000000191',
  '9f192101-0000-4000-8000-000000000192'
);

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values
  (
    '9f192101-0000-4000-8000-000000000091',
    '9f192101-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f192101-0000-4000-8000-000000000092',
    '9f192101-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f192101-0000-4000-8000-000000000093',
    '9f192101-0000-4000-8000-000000000002',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f192101-0000-4000-8000-000000000094',
    '9f192101-0000-4000-8000-000000000001',
    'mechanic', '{}'::jsonb, true
  );

insert into public.customers (
  id, tenant_id, name, email, phone, auth_user_id, is_active
) values
  (
    '9f192101-0000-4000-8000-000000000111',
    '9f192101-0000-4000-8000-000000000001',
    'Atomic Customer A', 'atomic-customer-a@example.invalid', '+56911111111',
    '9f192101-0000-4000-8000-000000000191', true
  ),
  (
    '9f192101-0000-4000-8000-000000000112',
    '9f192101-0000-4000-8000-000000000001',
    'Atomic Customer B', 'atomic-customer-b@example.invalid', '+56922222222',
    '9f192101-0000-4000-8000-000000000192', true
  );

insert into public.suppliers (
  id, tenant_id, name, phone, default_tax_treatment
) values (
  '9f192101-0000-4000-8000-000000000121',
  '9f192101-0000-4000-8000-000000000001',
  'Atomic Supplier A', '+56933333333', 'no_tax'
);

insert into public.whatsapp_channels (
  id, tenant_id, phone_number_id, display_name, is_active
) values
  (
    '9f192101-0000-4000-8000-000000000131',
    '9f192101-0000-4000-8000-000000000001',
    'atomic-channel-a', 'Atomic Channel A', true
  ),
  (
    '9f192101-0000-4000-8000-000000000132',
    '9f192101-0000-4000-8000-000000000002',
    'atomic-channel-b', 'Atomic Channel B', true
  );

select has_column(
  'public', 'conversations', 'counterparty_type',
  'conversation stores a stable counterparty capability'
);
select col_not_null(
  'public', 'conversations', 'counterparty_type',
  'counterparty capability is mandatory'
);
select has_column(
  'public', 'conversations', 'is_group',
  'internal conversation shape is persisted explicitly'
);
select col_not_null(
  'public', 'conversations', 'is_group',
  'internal conversation shape cannot fall back to title inference'
);
select has_column(
  'public', 'messages', 'message_sequence',
  'messages expose a monotonic server read cursor'
);
select is(
  (select attribute.attidentity::text
   from pg_attribute attribute
   where attribute.attrelid = 'public.messages'::regclass
     and attribute.attname = 'message_sequence'),
  'a',
  'message cursor is generated always and cannot be forged by clients'
);
select has_column(
  'public', 'conversation_participants', 'last_read_message_sequence',
  'participant read state stores an exact message cursor'
);
select has_column(
  'public', 'conversations', 'staff_last_read_message_sequence',
  'support staff read state stores an exact shared cursor'
);
select has_table(
  'public', 'messaging_command_receipts',
  'messaging aggregate commands retain durable receipts'
);
select has_table(
  'public', 'messaging_participant_reconciliation_audit',
  'legacy participant cleanup retains append-only audit evidence'
);
select is(
  (
    select count(*)::integer
    from public.conversation_contexts context_link
    join public.conversations conversation
      on conversation.id = context_link.conversation_id
     and conversation.tenant_id = context_link.tenant_id
    where context_link.is_primary
      and (
        conversation.context_type is distinct from context_link.context_type
        or conversation.context_id is distinct from context_link.context_id
      )
  ),
  0,
  'every retained primary context matches the scalar conversation projection'
);
select is(
  (
    select count(*)::integer
    from public.conversations conversation
    where conversation.context_type is not null
      and not exists (
        select 1
        from public.conversation_contexts context_link
        where context_link.conversation_id = conversation.id
          and context_link.tenant_id = conversation.tenant_id
          and context_link.is_primary
          and context_link.context_type = conversation.context_type
          and context_link.context_id = conversation.context_id
      )
  ),
  0,
  'every scalar context has one exact retained primary ledger row'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.messaging_participant_reconciliation_audit',
    'SELECT'
  ),
  'authenticated clients cannot enumerate participant cleanup evidence'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.messaging_command_receipts', 'SELECT'
  ),
  'authenticated clients cannot enumerate command receipts'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.conversation_contexts', 'UPDATE'
  ),
  'authenticated clients cannot rewrite retained context evidence'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.conversation_contexts', 'INSERT'
  ),
  'authenticated clients cannot append unvalidated context identity'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.conversations', 'INSERT'
  ),
  'authenticated clients cannot create partial conversation graphs'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.messaging_context_customer_id(text,uuid,uuid)',
    'EXECUTE'
  ),
  'customer identity resolver is not exposed as an enumeration RPC'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.messaging_context_customer_user_id(text,uuid,uuid)',
    'EXECUTE'
  ),
  'customer account resolver is not exposed as an enumeration RPC'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.mark_conversation_read(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated users can submit exact read evidence'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.mark_conversation_read(uuid)',
    'EXECUTE'
  ),
  'legacy read RPC remains as a safe compatibility no-op'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_staff_support_conversation(uuid,text,uuid,text,uuid,text)',
    'EXECUTE'
  ),
  'staff client can create an atomic support aggregate'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_staff_internal_conversation(uuid,uuid[],text,boolean,text)',
    'EXECUTE'
  ),
  'staff client can create an atomic internal aggregate'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.ensure_whatsapp_conversation_binding(uuid,uuid,text,text,text,uuid,text,uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated clients cannot call the low-level provider binding primitive'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000091',
  true
);
set local role authenticated;

select throws_ok(
  $$insert into public.conversations (
      tenant_id, type, channel, status
    ) values (
      '9f192101-0000-4000-8000-000000000001',
      'internal', 'internal', 'active'
    )$$,
  '42501',
  'permission denied for table conversations',
  'staff cannot create a partial conversation row directly'
);

select set_config(
  'test.atomic.internal_conversation_id',
  public.create_staff_internal_conversation(
    '9f192101-0000-4000-8000-000000000001',
    array['9f192101-0000-4000-8000-000000000094'::uuid],
    null,
    false,
    'atomic-internal-direct-1'
  )->>'conversation_id',
  true
);
select is(
  (select counterparty_type from public.conversations
   where id = current_setting('test.atomic.internal_conversation_id')::uuid),
  'internal',
  'internal aggregate persists the internal counterparty capability'
);
select is(
  (select is_group from public.conversations
   where id = current_setting('test.atomic.internal_conversation_id')::uuid),
  false,
  'direct internal aggregate persists non-group shape'
);
select is(
  (select count(*)::integer
   from public.conversation_participants
   where conversation_id =
     current_setting('test.atomic.internal_conversation_id')::uuid),
  2,
  'direct internal aggregate commits exactly both staff participants'
);
select is(
  public.create_staff_internal_conversation(
    '9f192101-0000-4000-8000-000000000001',
    array['9f192101-0000-4000-8000-000000000094'::uuid],
    null,
    false,
    'atomic-internal-direct-1'
  )->>'replayed',
  'true',
  'lost direct-chat acknowledgement replays its durable receipt'
);
select is(
  public.create_staff_internal_conversation(
    '9f192101-0000-4000-8000-000000000001',
    array['9f192101-0000-4000-8000-000000000094'::uuid],
    null,
    false,
    'atomic-internal-direct-reuse'
  )->>'conversation_id',
  current_setting('test.atomic.internal_conversation_id'),
  'a new command reuses the exact active direct staff pair'
);
select set_config(
  'test.atomic.group_conversation_id',
  public.create_staff_internal_conversation(
    '9f192101-0000-4000-8000-000000000001',
    array[
      '9f192101-0000-4000-8000-000000000091'::uuid,
      '9f192101-0000-4000-8000-000000000094'::uuid,
      '9f192101-0000-4000-8000-000000000094'::uuid
    ],
    'Equipo de prueba',
    true,
    'atomic-internal-group-1'
  )->>'conversation_id',
  true
);
select isnt(
  current_setting('test.atomic.group_conversation_id'),
  current_setting('test.atomic.internal_conversation_id'),
  'a one-invitee group is never confused with the direct staff pair'
);
select is(
  (select is_group from public.conversations
   where id = current_setting('test.atomic.group_conversation_id')::uuid),
  true,
  'group shape is retained independently of participant count'
);
select is(
  (select count(*)::integer
   from public.conversation_participants
   where conversation_id =
     current_setting('test.atomic.group_conversation_id')::uuid),
  2,
  'group command de-duplicates targets and excludes the actor'
);

select throws_ok(
  $$update public.conversations
    set counterparty_type = 'customer'
    where id = current_setting('test.atomic.internal_conversation_id')::uuid$$,
  '23514',
  'Conversation counterparty_type is immutable',
  'counterparty capability cannot be rewritten by a client'
);
select throws_ok(
  $$update public.conversations
    set is_group = true
    where id = current_setting('test.atomic.internal_conversation_id')::uuid$$,
  '23514',
  'Conversation is_group is immutable',
  'direct/group identity cannot be rewritten by a client'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000094',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000094',
  true
);
set local role authenticated;
select is(
  public.create_staff_internal_conversation(
    '9f192101-0000-4000-8000-000000000001',
    array['9f192101-0000-4000-8000-000000000091'::uuid],
    null,
    false,
    'atomic-internal-direct-reverse'
  )->>'conversation_id',
  current_setting('test.atomic.internal_conversation_id'),
  'direct staff chat reuse is canonical in either participant direction'
);
select throws_ok(
  $$select public.create_staff_internal_conversation(
      '9f192101-0000-4000-8000-000000000001',
      array['9f192101-0000-4000-8000-000000000093'::uuid],
      null,
      false,
      'atomic-internal-foreign-target'
    )$$,
  '42501',
  'Every internal participant must be active staff in tenant',
  'internal aggregate rejects cross-tenant participants before graph creation'
);
reset role;
select is(
  (select count(*)::integer
   from public.messaging_command_receipts
   where tenant_id = '9f192101-0000-4000-8000-000000000001'
     and command_type = 'staff_internal_conversation'
     and idempotency_key = 'atomic-internal-foreign-target'),
  0,
  'rejected internal aggregate leaves no partial durable receipt'
);

-- Customer support creation is one atomic, replay-safe command.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000191',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000191',
  true
);
set local role authenticated;

select is(
  public.create_customer_support_request(
    '9f192101-0000-4000-8000-000000000001',
    'Necesito ayuda con mi cuenta',
    'customer',
    '9f192101-0000-4000-8000-000000000111',
    'atomic-support-request-1'
  )->>'status',
  'pending',
  'customer request command creates a pending case'
);

select is(
  (select count(*)::integer
   from public.conversations
   where created_by = '9f192101-0000-4000-8000-000000000191'
     and title is null
     and channel = 'website_portal'),
  1,
  'customer request creates exactly one conversation'
);
select is(
  (select counterparty_type
   from public.conversations
   where created_by = '9f192101-0000-4000-8000-000000000191'
     and channel = 'website_portal'),
  'customer',
  'customer request retains customer-only capabilities'
);
select is(
  (select count(*)::integer
   from public.conversation_participants participant
   join public.conversations conversation
     on conversation.id = participant.conversation_id
   where conversation.created_by = '9f192101-0000-4000-8000-000000000191'
     and conversation.channel = 'website_portal'),
  1,
  'customer participant is committed in the same aggregate'
);
select is(
  (select count(*)::integer
   from public.conversation_contexts context_link
   join public.conversations conversation
     on conversation.id = context_link.conversation_id
   where conversation.created_by = '9f192101-0000-4000-8000-000000000191'
     and conversation.channel = 'website_portal'),
  1,
  'authorized customer context is committed in the same aggregate'
);
select is(
  (select count(*)::integer
   from public.messages message
   join public.conversations conversation
     on conversation.id = message.conversation_id
   where conversation.created_by = '9f192101-0000-4000-8000-000000000191'
     and conversation.channel = 'website_portal'
     and message.content = 'Necesito ayuda con mi cuenta'
     and message.message_direction = 'inbound'),
  1,
  'initial inbound message is committed in the same aggregate'
);
select throws_ok(
  $$select count(*) from public.messaging_command_receipts$$,
  '42501',
  'permission denied for table messaging_command_receipts',
  'command receipts remain hidden from the customer'
);
select is(
  public.create_customer_support_request(
    '9f192101-0000-4000-8000-000000000001',
    'Necesito ayuda con mi cuenta',
    'customer',
    '9f192101-0000-4000-8000-000000000111',
    'atomic-support-request-1'
  )->>'replayed',
  'true',
  'lost acknowledgement retry returns the durable request receipt'
);
select is(
  (select count(*)::integer
   from public.conversations
   where created_by = '9f192101-0000-4000-8000-000000000191'
     and channel = 'website_portal'),
  1,
  'request replay does not duplicate the conversation graph'
);
select throws_ok(
  $$select public.create_customer_support_request(
      '9f192101-0000-4000-8000-000000000001',
      'Un mensaje diferente',
      'customer',
      '9f192101-0000-4000-8000-000000000111',
      'atomic-support-request-1'
    )$$,
  '23514',
  'Messaging idempotency key belongs to another request',
  'idempotency key cannot be reused for a different request'
);
select throws_ok(
  $$select public.create_customer_support_request(
      '9f192101-0000-4000-8000-000000000001',
      'Intento contexto ajeno',
      'customer',
      '9f192101-0000-4000-8000-000000000112',
      'atomic-support-request-foreign-context'
    )$$,
  '42501',
  'Customer cannot reference this messaging context',
  'customer cannot attach a sibling customer context'
);
select throws_ok(
  $$select public.create_customer_support_request(
      '9f192101-0000-4000-8000-000000000002',
      'Intento tenant ajeno', null, null,
      'atomic-support-request-foreign-tenant'
    )$$,
  '42501',
  'Customer messaging access is required',
  'customer cannot create a request in another tenant'
);
reset role;

-- Staff access to support threads is not authority to expose one customer's
-- retained history to another same-tenant customer.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select throws_ok(
  $$insert into public.conversation_participants (
      conversation_id, user_id, tenant_id, role
    ) values (
      (
        select conversation.id
        from public.conversations conversation
        where conversation.created_by =
          '9f192101-0000-4000-8000-000000000191'
          and conversation.channel = 'website_portal'
      ),
      '9f192101-0000-4000-8000-000000000192',
      '9f192101-0000-4000-8000-000000000001',
      'member'
    )$$,
  '42501',
  'new row violates row-level security policy for table "conversation_participants"',
  'staff cannot add a sibling customer to another customer support history'
);

select set_config(
  'test.atomic.staff_support_conversation_id',
  public.create_staff_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    'Atención desde la ficha',
    null,
    'customer',
    '9f192101-0000-4000-8000-000000000111',
    'atomic-staff-support-1'
  )->>'conversation_id',
  true
);
select is(
  (select count(*)::integer
   from public.conversation_participants
   where conversation_id =
     current_setting('test.atomic.staff_support_conversation_id')::uuid),
  2,
  'staff support aggregate derives and commits the deliverable customer account'
);
select is(
  (select count(*)::integer
   from public.conversation_contexts
   where conversation_id =
       current_setting('test.atomic.staff_support_conversation_id')::uuid
     and context_type = 'customer'
     and context_id = '9f192101-0000-4000-8000-000000000111'
     and is_primary),
  1,
  'staff support aggregate retains the exact customer context atomically'
);
select is(
  (select accepted_by::text
   from public.conversations
   where id =
     current_setting('test.atomic.staff_support_conversation_id')::uuid),
  '9f192101-0000-4000-8000-000000000091',
  'staff-created support aggregate records its accepting actor'
);
select is(
  public.create_staff_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    'Atención desde la ficha',
    null,
    'customer',
    '9f192101-0000-4000-8000-000000000111',
    'atomic-staff-support-1'
  )->>'replayed',
  'true',
  'lost staff-support acknowledgement replays its durable receipt'
);
select throws_ok(
  $$select public.create_staff_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      'Identidad incompatible',
      '9f192101-0000-4000-8000-000000000192',
      'customer',
      '9f192101-0000-4000-8000-000000000111',
      'atomic-staff-support-mismatch'
    )$$,
  '42501',
  'Customer participant does not own support context',
  'staff support aggregate rejects a customer/context identity mismatch'
);
select set_config(
  'test.atomic.staff_outbound_conversation_id',
  public.create_staff_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    null,
    '9f192101-0000-4000-8000-000000000192',
    null,
    null,
    'atomic-staff-support-outbound'
  )->>'conversation_id',
  true
);
select is(
  (select count(*)::integer
   from public.conversation_contexts
   where conversation_id =
       current_setting('test.atomic.staff_outbound_conversation_id')::uuid
     and context_type = 'customer'
     and context_id = '9f192101-0000-4000-8000-000000000112'
     and is_primary),
  1,
  'outbound support without operational context retains customer identity evidence'
);
select is(
  public.create_staff_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    null,
    null,
    'supplier',
    '9f192101-0000-4000-8000-000000000121',
    'atomic-staff-support-supplier'
  )->>'counterparty_type',
  'supplier',
  'staff support aggregate also creates supplier-capability threads safely'
);
select throws_ok(
  $$update public.conversation_contexts context_link
    set context_id = '9f192101-0000-4000-8000-000000000112'
    from public.conversations conversation
    where conversation.id = context_link.conversation_id
      and conversation.created_by =
        '9f192101-0000-4000-8000-000000000191'
      and conversation.channel = 'website_portal'$$,
  '42501',
  'permission denied for table conversation_contexts',
  'authenticated staff cannot rewrite retained context identity'
);
reset role;
select is(
  (select count(*)::integer
   from public.messaging_command_receipts
   where tenant_id = '9f192101-0000-4000-8000-000000000001'
     and command_type = 'staff_support_conversation'
     and idempotency_key = 'atomic-staff-support-mismatch'),
  0,
  'rejected staff support aggregate leaves no partial receipt'
);
select throws_ok(
  $$update public.conversation_contexts context_link
    set context_id = '9f192101-0000-4000-8000-000000000112'
    from public.conversations conversation
    where conversation.id = context_link.conversation_id
      and conversation.created_by =
        '9f192101-0000-4000-8000-000000000191'
      and conversation.channel = 'website_portal'$$,
  '23514',
  'Conversation context identity and evidence are immutable',
  'privileged writes also cannot rewrite retained context evidence'
);
select is(
  (
    select context_link.context_id
    from public.conversation_contexts context_link
    join public.conversations conversation
      on conversation.id = context_link.conversation_id
    where conversation.created_by =
      '9f192101-0000-4000-8000-000000000191'
      and conversation.channel = 'website_portal'
  ),
  '9f192101-0000-4000-8000-000000000111'::uuid,
  'rejected rewrites preserve the original customer context'
);

-- Read receipts stop at the exact message rendered by the client.
insert into public.conversations (
  id, tenant_id, type, channel, counterparty_type, status, created_by
) values (
  '9f192101-0000-4000-8000-000000000311',
  '9f192101-0000-4000-8000-000000000001',
  'support', 'website_portal', 'customer', 'active',
  '9f192101-0000-4000-8000-000000000191'
);
insert into public.conversation_participants (
  conversation_id, user_id, tenant_id, role, last_read_at
) values (
  '9f192101-0000-4000-8000-000000000311',
  '9f192101-0000-4000-8000-000000000191',
  '9f192101-0000-4000-8000-000000000001',
  'member', '2026-01-01 09:00:00+00'
);
insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type, created_at
) values
  (
    '9f192101-0000-4000-8000-000000000411',
    '9f192101-0000-4000-8000-000000000311',
    '9f192101-0000-4000-8000-000000000091',
    '9f192101-0000-4000-8000-000000000001',
    'Primera respuesta visible', 'text', '2026-01-01 10:00:00+00'
  ),
  (
    '9f192101-0000-4000-8000-000000000412',
    '9f192101-0000-4000-8000-000000000311',
    '9f192101-0000-4000-8000-000000000091',
    '9f192101-0000-4000-8000-000000000001',
    'Respuesta que llegó después', 'text', '2026-01-01 10:00:00+00'
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000191',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000191',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.mark_conversation_read(
      '9f192101-0000-4000-8000-000000000311'
    )$$,
  'legacy read command remains callable during coordinated rollout'
);
select is(
  (select last_read_at
   from public.conversation_participants
   where conversation_id = '9f192101-0000-4000-8000-000000000311'
     and user_id = '9f192101-0000-4000-8000-000000000191'),
  '2026-01-01 09:00:00+00'::timestamptz,
  'legacy compatibility call cannot infer or advance read evidence'
);
select ok(
  (select first_message.message_sequence < second_message.message_sequence
   from public.messages first_message
   join public.messages second_message
     on second_message.id = '9f192101-0000-4000-8000-000000000412'
   where first_message.id = '9f192101-0000-4000-8000-000000000411'),
  'same-timestamp messages retain exact server insertion order'
);
select is(
  public.mark_conversation_read(
    '9f192101-0000-4000-8000-000000000311',
    '9f192101-0000-4000-8000-000000000411'
  )->>'read_through_message_id',
  '9f192101-0000-4000-8000-000000000411',
  'read command acknowledges the exact visible message id'
);
select is(
  (select unread_count
   from public.conversation_unread_counts
   where conversation_id = '9f192101-0000-4000-8000-000000000311'
     and user_id = '9f192101-0000-4000-8000-000000000191'),
  1,
  'same-timestamp message after the rendered target remains unread'
);
select throws_ok(
  $$select public.mark_conversation_read(
      '9f192101-0000-4000-8000-000000000311',
      '9f192101-0000-4000-8000-000000000301'
    )$$,
  '42501',
  'Read-through message is not visible unread evidence',
  'read command rejects a UUID that is not visible message evidence'
);
reset role;

-- Staff read enrollment is also bounded by the exact inbound message instead
-- of the participant table default of now().
insert into public.conversations (
  id, tenant_id, type, channel, counterparty_type, status, created_by
) values (
  '9f192101-0000-4000-8000-000000000312',
  '9f192101-0000-4000-8000-000000000001',
  'support', 'website_portal', 'customer', 'active',
  '9f192101-0000-4000-8000-000000000191'
);
insert into public.conversation_participants (
  conversation_id, user_id, tenant_id, role, last_read_at
) values (
  '9f192101-0000-4000-8000-000000000312',
  '9f192101-0000-4000-8000-000000000191',
  '9f192101-0000-4000-8000-000000000001',
  'member', '2026-01-02 09:00:00+00'
);
insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type,
  message_direction, created_at
) values
  (
    '9f192101-0000-4000-8000-000000000421',
    '9f192101-0000-4000-8000-000000000312',
    '9f192101-0000-4000-8000-000000000191',
    '9f192101-0000-4000-8000-000000000001',
    'Primer mensaje cliente', 'text', 'inbound',
    '2026-01-02 10:00:00+00'
  ),
  (
    '9f192101-0000-4000-8000-000000000422',
    '9f192101-0000-4000-8000-000000000312',
    '9f192101-0000-4000-8000-000000000191',
    '9f192101-0000-4000-8000-000000000001',
    'Segundo mensaje cliente', 'text', 'inbound',
    '2026-01-02 10:00:00+00'
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select lives_ok(
  $$select public.mark_conversation_read(
      '9f192101-0000-4000-8000-000000000312',
      '9f192101-0000-4000-8000-000000000421'
    )$$,
  'staff can acknowledge a visible inbound message without prior enrollment'
);
select is(
  (select last_read_at
   from public.conversation_participants
   where conversation_id = '9f192101-0000-4000-8000-000000000312'
     and user_id = '9f192101-0000-4000-8000-000000000091'),
  '2026-01-02 10:00:00+00'::timestamptz,
  'staff participant marker equals visible evidence instead of now()'
);
select is(
  (select unread_count
   from public.conversation_unread_counts
   where conversation_id = '9f192101-0000-4000-8000-000000000312'
     and user_id = '9f192101-0000-4000-8000-000000000091'),
  1,
  'later customer message remains unread for staff'
);

-- Primary context selection is atomic and keeps prior links as non-primary
-- audit history. Capability boundaries are enforced inside the command.
select lives_ok(
  $$select public.set_conversation_primary_context(
      '9f192101-0000-4000-8000-000000000311',
      'customer',
      '9f192101-0000-4000-8000-000000000111'
    )$$,
  'staff can select an authorized customer context atomically'
);
select is(
  (select context_type
   from public.conversations
   where id = '9f192101-0000-4000-8000-000000000311'),
  'customer',
  'primary context projection changes with the context command'
);
select is(
  (select count(*)::integer
   from public.conversation_contexts
   where conversation_id = '9f192101-0000-4000-8000-000000000311'
     and context_type = 'customer'
     and context_id = '9f192101-0000-4000-8000-000000000111'
     and is_primary),
  1,
  'primary context history link is committed with the scalar projection'
);
select lives_ok(
  $$select public.set_conversation_primary_context(
      '9f192101-0000-4000-8000-000000000311', null, null
    )$$,
  'staff can clear the primary projection without deleting history'
);
select is(
  (select context_type
   from public.conversations
   where id = '9f192101-0000-4000-8000-000000000311'),
  null,
  'clearing the primary context clears the scalar projection'
);
select is(
  (select count(*)::integer
   from public.conversation_contexts
   where conversation_id = '9f192101-0000-4000-8000-000000000311'
     and context_type = 'customer'
     and context_id = '9f192101-0000-4000-8000-000000000111'
     and not is_primary),
  1,
  'cleared primary context remains as non-primary audit history'
);
select lives_ok(
  $$select public.set_conversation_primary_context(
      '9f192101-0000-4000-8000-000000000311',
      'customer',
      '9f192101-0000-4000-8000-000000000111'
    )$$,
  'staff can restore a retained context as primary'
);
select throws_ok(
  $$select public.set_conversation_primary_context(
      '9f192101-0000-4000-8000-000000000311',
      'customer',
      '9f192101-0000-4000-8000-000000000112'
    )$$,
  '23514',
  'Customer conversation context belongs to another customer',
  'staff cannot replace retained customer identity with a sibling customer'
);
select is(
  (select count(*)::integer
   from public.conversation_contexts
   where conversation_id = '9f192101-0000-4000-8000-000000000311'
     and is_primary),
  1,
  'rejected identity replacement leaves one primary context'
);
select is(
  (select context_id
   from public.conversations
   where id = '9f192101-0000-4000-8000-000000000311'),
  '9f192101-0000-4000-8000-000000000111'::uuid,
  'rejected identity replacement preserves the original scalar context'
);
select throws_ok(
  $$select public.set_conversation_primary_context(
      '9f192101-0000-4000-8000-000000000311',
      'supplier',
      '9f192101-0000-4000-8000-000000000121'
    )$$,
  '23514',
  'Customer conversations cannot accept supplier contexts',
  'customer context command rejects supplier capabilities'
);

-- A supplier WhatsApp thread cannot acquire customer/workshop actions, and a
-- terminal case rebinds to a fresh active conversation with an audit receipt.
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56933333334', '56933333334', 'Supplier with customer leak',
      '9f192101-0000-4000-8000-000000000111',
      'supplier', '9f192101-0000-4000-8000-000000000121',
      'atomic-open-supplier-customer-invalid'
    )$$,
  '23514',
  'Supplier conversations cannot bind a customer identity',
  'supplier capability rejects a customer binding before graph creation'
);
select is(
  (select count(*)::integer
   from public.whatsapp_conversation_bindings
   where channel_id = '9f192101-0000-4000-8000-000000000131'
     and external_wa_id = '56933333334'),
  0,
  'rejected supplier/customer combination leaves no partial binding'
);
select is(
  public.open_whatsapp_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    '9f192101-0000-4000-8000-000000000131',
    '56933333333', '56933333333', 'Atomic Supplier A', null,
    'supplier', '9f192101-0000-4000-8000-000000000121',
    'atomic-open-supplier-1'
  )->>'status',
  'active',
  'staff opens a supplier WhatsApp case atomically'
);
select is(
  (select conversation.counterparty_type
   from public.conversations conversation
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = conversation.id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'),
  'supplier',
  'supplier capability is durable on the conversation'
);
select throws_ok(
  $$update public.conversations conversation
    set context_type = 'customer',
        context_id = '9f192101-0000-4000-8000-000000000111'
    from public.whatsapp_conversation_bindings binding
    where binding.conversation_id = conversation.id
      and binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'$$,
  '23514',
  'Supplier conversations only accept supplier or purchase contexts',
  'supplier conversation rejects customer-only scalar context'
);
select throws_ok(
  $$insert into public.conversation_contexts (
      conversation_id, context_type, context_id, is_primary, tenant_id
    )
    select binding.conversation_id, 'customer',
      '9f192101-0000-4000-8000-000000000111', true,
      '9f192101-0000-4000-8000-000000000001'
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'$$,
  '42501',
  'permission denied for table conversation_contexts',
  'staff cannot bypass the context command with a direct history insert'
);
select throws_ok(
  $$select public.set_conversation_primary_context(
      binding.conversation_id,
      'customer',
      '9f192101-0000-4000-8000-000000000111'
    )
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'$$,
  '23514',
  'Supplier conversations only accept supplier or purchase contexts',
  'supplier context command rejects customer capabilities'
);

select is(
  public.messaging_can_add_participant(
    (
      select binding.conversation_id
      from public.whatsapp_conversation_bindings binding
      where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
        and binding.external_wa_id = '56933333333'
    ),
    '9f192101-0000-4000-8000-000000000191',
    '9f192101-0000-4000-8000-000000000001'
  ),
  false,
  'customer-only identities cannot become supplier chat participants'
);

select set_config(
  'test.atomic.supplier_accepted_by',
  (
    select conversation.accepted_by::text
    from public.conversations conversation
    join public.whatsapp_conversation_bindings binding
      on binding.conversation_id = conversation.id
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'
  ),
  true
);
select set_config(
  'test.atomic.supplier_accepted_at',
  (
    select conversation.accepted_at::text
    from public.conversations conversation
    join public.whatsapp_conversation_bindings binding
      on binding.conversation_id = conversation.id
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'
  ),
  true
);

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000092',
  true
);
set local role authenticated;
select is(
  public.messaging_can_read_conversation_messages(
    current_setting('test.atomic.internal_conversation_id')::uuid
  ),
  false,
  'same-tenant staff cannot bypass internal-chat participation through helper RPCs'
);
select lives_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56933333333', '56933333333', 'Atomic Supplier A', null,
      'supplier', '9f192101-0000-4000-8000-000000000121',
      'atomic-open-supplier-second-staff'
    )$$,
  'another staff member can open the already accepted supplier case'
);
select is(
  (select conversation.accepted_by::text
   from public.conversations conversation
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = conversation.id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'),
  current_setting('test.atomic.supplier_accepted_by'),
  'reopening an active case preserves the original accepting actor'
);
select is(
  (select conversation.accepted_at::text
   from public.conversations conversation
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = conversation.id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'),
  current_setting('test.atomic.supplier_accepted_at'),
  'reopening an active case preserves the matching acceptance timestamp'
);
select is(
  public.open_whatsapp_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    '9f192101-0000-4000-8000-000000000131',
    '56933333333', '56933333333', 'Atomic Supplier A', null,
    'supplier', '9f192101-0000-4000-8000-000000000121',
    'atomic-open-supplier-second-staff'
  )->>'accepted_by',
  current_setting('test.atomic.supplier_accepted_by'),
  'open receipt reports the preserved accepting actor instead of the current caller'
);
select is(
  (
    public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56933333333', '56933333333', 'Atomic Supplier A', null,
      'supplier', '9f192101-0000-4000-8000-000000000121',
      'atomic-open-supplier-second-staff'
    )->>'accepted_at'
  )::timestamptz::text,
  current_setting('test.atomic.supplier_accepted_at'),
  'open receipt reports the timestamp paired with the preserved accepting actor'
);

reset role;
-- Simulate a legacy/bypassed participant row. Capability-aware RLS must still
-- prevent the customer from learning that supplier conversation exists.
insert into public.conversation_participants (
  conversation_id, user_id, tenant_id, role, last_read_at
)
select
  binding.conversation_id,
  '9f192101-0000-4000-8000-000000000191',
  '9f192101-0000-4000-8000-000000000001',
  'member',
  '1970-01-01'::timestamptz
from public.whatsapp_conversation_bindings binding
where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
  and binding.external_wa_id = '56933333333';

insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type,
  message_direction, created_at
)
select
  '9f192101-0000-4000-8000-000000000431',
  binding.conversation_id,
  '9f192101-0000-4000-8000-000000000091',
  '9f192101-0000-4000-8000-000000000001',
  'Supplier evidence must stay private',
  'text', 'outbound', clock_timestamp()
from public.whatsapp_conversation_bindings binding
where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
  and binding.external_wa_id = '56933333333';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000191',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000191',
  true
);
set local role authenticated;
select is(
  public.messaging_can_read_conversation_messages(
    (
      select binding.conversation_id
      from public.whatsapp_conversation_bindings binding
      where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
        and binding.external_wa_id = '56933333333'
    )
  ),
  false,
  'legacy customer participant cannot read a supplier conversation'
);
select is(
  (select count(*)::integer
   from public.messages
   where id = '9f192101-0000-4000-8000-000000000431'),
  0,
  'supplier message remains hidden from a legacy customer participant'
);

reset role;
select set_config(
  'test.atomic.supplier_message_count',
  (
    select count(*)::text
    from public.messages message
    join public.whatsapp_conversation_bindings binding
      on binding.conversation_id = message.conversation_id
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'
  ),
  true
);
select set_config(
  'test.atomic.supplier_context_count',
  (
    select count(*)::text
    from public.conversation_contexts context_link
    join public.whatsapp_conversation_bindings binding
      on binding.conversation_id = context_link.conversation_id
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'
  ),
  true
);
select set_config(
  'test.atomic.supplier_binding_count',
  (
    select count(*)::text
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'
  ),
  true
);
select is(
  public.reconcile_supplier_customer_participants(),
  1,
  'migration reconciliation removes the legacy customer-only supplier recipient'
);
select is(
  (select count(*)::integer
   from public.messaging_participant_reconciliation_audit audit
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = audit.conversation_id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'
     and audit.user_id = '9f192101-0000-4000-8000-000000000191'
     and audit.old_role = 'member'
     and audit.old_last_read_at = '1970-01-01'::timestamptz
     and audit.reason =
       'customer_only_identity_in_supplier_conversation'
     and audit.migration_version = '20260719210000'),
  1,
  'supplier reconciliation archives exactly the removed participant edge'
);
select is(
  public.reconcile_supplier_customer_participants(),
  0,
  'supplier reconciliation is a no-op after the unsafe edge is removed'
);
select is(
  (select count(*)::integer
   from public.messaging_participant_reconciliation_audit audit
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = audit.conversation_id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'
     and audit.user_id = '9f192101-0000-4000-8000-000000000191'),
  1,
  'reconciliation replay cannot duplicate append-only audit evidence'
);
select is(
  (select count(*)::integer
   from public.conversation_participants participant
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = participant.conversation_id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'
     and participant.user_id = '9f192101-0000-4000-8000-000000000191'),
  0,
  'supplier reconciliation removes the unsafe recipient edge'
);
select is(
  (select count(*)::text
   from public.messages message
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = message.conversation_id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'),
  current_setting('test.atomic.supplier_message_count'),
  'supplier reconciliation preserves message evidence'
);
select is(
  (select count(*)::text
   from public.conversation_contexts context_link
   join public.whatsapp_conversation_bindings binding
     on binding.conversation_id = context_link.conversation_id
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'),
  current_setting('test.atomic.supplier_context_count'),
  'supplier reconciliation preserves context evidence'
);
select is(
  (select count(*)::text
   from public.whatsapp_conversation_bindings binding
   where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
     and binding.external_wa_id = '56933333333'),
  current_setting('test.atomic.supplier_binding_count'),
  'supplier reconciliation preserves the provider binding'
);
select is(
  (select count(*)::integer
   from public.conversation_participants participant
   join public.conversations conversation
     on conversation.id = participant.conversation_id
    and conversation.tenant_id = participant.tenant_id
   where conversation.counterparty_type = 'supplier'
     and exists (
       select 1
       from public.customers customer
       where customer.auth_user_id = participant.user_id
         and customer.tenant_id = conversation.tenant_id
     )
     and not exists (
       select 1
       from public.user_profiles staff
       where staff.user_id = participant.user_id
         and staff.tenant_id = conversation.tenant_id
         and coalesce(staff.is_active, true)
     )),
  0,
  'read-back invariant has zero customer-only supplier recipients'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f192101-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f192101-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56933333333', '56933333333', 'Atomic Supplier A', null,
      'supplier', '9f192101-0000-4000-8000-000000000121',
      'atomic-open-supplier-second-staff'
    )$$,
  '23514',
  'Messaging idempotency key belongs to another request',
  'another actor cannot replay a staff command receipt'
);

select lives_ok(
  $$select public.archive_conversation(
      binding.conversation_id
    )
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'$$,
  'staff archives the first supplier case as retained evidence'
);
select set_config(
  'test.atomic.old_supplier_conversation_id',
  (
    select binding.conversation_id::text
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56933333333'
  ),
  true
);
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56933333333', '56933333333', 'Capability switch attempt',
      '9f192101-0000-4000-8000-000000000111',
      'customer', '9f192101-0000-4000-8000-000000000111',
      'atomic-open-supplier-as-customer'
    )$$,
  '23514',
  'WhatsApp contact is already bound to another counterparty capability',
  'terminal supplier binding cannot be reclassified as customer'
);
select isnt(
  public.open_whatsapp_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    '9f192101-0000-4000-8000-000000000131',
    '56933333333', '56933333333', 'Atomic Supplier A', null,
    'supplier', '9f192101-0000-4000-8000-000000000121',
    'atomic-open-supplier-2'
  )->>'conversation_id',
  current_setting('test.atomic.old_supplier_conversation_id'),
  'new activity after archival receives a fresh conversation id'
);
select is(
  (select count(*)::integer
   from public.conversations conversation
   where conversation.tenant_id = '9f192101-0000-4000-8000-000000000001'
     and conversation.channel = 'whatsapp'
     and conversation.counterparty_type = 'supplier'),
  2,
  'terminal supplier case and fresh active case are both retained'
);
select is(
  public.open_whatsapp_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    '9f192101-0000-4000-8000-000000000131',
    '56933333333', '56933333333', 'Atomic Supplier A', null,
    'supplier', '9f192101-0000-4000-8000-000000000121',
    'atomic-open-supplier-2'
  )->>'rebound_from_conversation_id',
  current_setting('test.atomic.old_supplier_conversation_id'),
  'rebind receipt links the new case to its terminal predecessor'
);
select is(
  public.open_whatsapp_support_conversation(
    '9f192101-0000-4000-8000-000000000001',
    '9f192101-0000-4000-8000-000000000131',
    '56933333333', '56933333333', 'Atomic Supplier A', null,
    'supplier', '9f192101-0000-4000-8000-000000000121',
    'atomic-open-supplier-2'
  )->>'replayed',
  'true',
  'WhatsApp open retry replays the durable command receipt'
);
select is(
  (select count(*)::integer
   from public.conversations conversation
   where conversation.tenant_id = '9f192101-0000-4000-8000-000000000001'
     and conversation.channel = 'whatsapp'
     and conversation.counterparty_type = 'supplier'),
  2,
  'WhatsApp open replay cannot create a third conversation'
);

select lives_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56911111111', '56911111111', 'Atomic Customer A',
      '9f192101-0000-4000-8000-000000000111',
      'customer', '9f192101-0000-4000-8000-000000000111',
      'atomic-open-customer-1'
    )$$,
  'staff can create a customer WhatsApp capability'
);
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56911111111', '56911111111', 'Atomic Customer B',
      '9f192101-0000-4000-8000-000000000112',
      'customer', '9f192101-0000-4000-8000-000000000112',
      'atomic-open-customer-rebind-invalid'
    )$$,
  '23514',
  'WhatsApp customer binding is immutable',
  'active WhatsApp identity cannot be switched to a sibling customer'
);
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56911111111', '56911111111', 'Cross-customer context', null,
      'customer', '9f192101-0000-4000-8000-000000000112',
      'atomic-open-customer-context-invalid'
    )$$,
  '23514',
  'WhatsApp customer does not own messaging context',
  'active WhatsApp identity rejects another customer context'
);
select is(
  (
    select binding.customer_id
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56911111111'
  ),
  '9f192101-0000-4000-8000-000000000111'::uuid,
  'rejected rebinding preserves the canonical customer identity'
);
select is(
  (
    select count(*)::integer
    from public.conversation_participants participant
    join public.whatsapp_conversation_bindings binding
      on binding.conversation_id = participant.conversation_id
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56911111111'
      and participant.user_id = '9f192101-0000-4000-8000-000000000192'
  ),
  0,
  'rejected rebinding cannot enroll the sibling customer'
);
select lives_ok(
  $$select public.archive_conversation(binding.conversation_id)
    from public.whatsapp_conversation_bindings binding
    where binding.channel_id = '9f192101-0000-4000-8000-000000000131'
      and binding.external_wa_id = '56911111111'$$,
  'staff archives the customer capability case'
);
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000001',
      '9f192101-0000-4000-8000-000000000131',
      '56911111111', '56911111111', 'Customer as supplier attempt', null,
      'supplier', '9f192101-0000-4000-8000-000000000121',
      'atomic-open-customer-as-supplier'
    )$$,
  '23514',
  'Supplier conversations cannot bind a customer identity',
  'terminal customer binding cannot be reclassified as supplier'
);
select throws_ok(
  $$select public.open_whatsapp_support_conversation(
      '9f192101-0000-4000-8000-000000000002',
      '9f192101-0000-4000-8000-000000000132',
      '56944444444', '56944444444', 'Foreign contact', null,
      null, null, 'atomic-open-foreign-tenant'
    )$$,
  '42501',
  'Messaging staff access is required',
  'staff cannot open WhatsApp cases in another tenant'
);
reset role;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  $$select public.create_customer_support_request(
      '9f192101-0000-4000-8000-000000000001',
      'Anonymous request', null, null, 'atomic-anon-request'
    )$$,
  '42501',
  'permission denied for function create_customer_support_request',
  'anonymous callers cannot create support aggregates'
);
reset role;

select * from finish();
rollback;
