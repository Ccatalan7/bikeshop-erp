begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(115);

-- Two tenants, three staff identities and three customer identities exercise
-- same-tenant shared support, participant-only internal chat, and strict
-- cross-tenant denial. Fixed UUIDs keep the quotation operation receipts
-- deterministic and replayable.
insert into public.tenants (id, shop_name) values
  ('9f190001-0000-4000-8000-000000000001', 'Messaging Guard Tenant A'),
  ('9f190001-0000-4000-8000-000000000002', 'Messaging Guard Tenant B');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9f190001-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'msg-staff-a@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f190001-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'msg-staff-b@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f190001-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000093',
    'authenticated', 'authenticated', 'msg-staff-other@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f190001-0000-4000-8000-000000000002'),
    now(), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000094',
    'authenticated', 'authenticated', 'msg-owner@example.invalid', '', now(),
    jsonb_build_object('account_type', 'erp_owner'),
    jsonb_build_object(
      'display_name', 'Viñabike',
      'full_name', 'Viñabike',
      'name', 'Viñabike'
    ),
    now(), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000191',
    'authenticated', 'authenticated', 'msg-customer-a@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f190001-0000-4000-8000-000000000001'
    ),
    now(), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000192',
    'authenticated', 'authenticated', 'msg-customer-b@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f190001-0000-4000-8000-000000000001'
    ),
    now(), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000193',
    'authenticated', 'authenticated', 'msg-customer-other@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f190001-0000-4000-8000-000000000002'
    ),
    now(), now()
  );

-- Local and production-derived Supabase shells may have auth bootstrap
-- triggers. Replace their generated rows with deterministic fixtures.
delete from public.user_profiles
where user_id in (
  '9f190001-0000-4000-8000-000000000091',
  '9f190001-0000-4000-8000-000000000092',
  '9f190001-0000-4000-8000-000000000093',
  '9f190001-0000-4000-8000-000000000094',
  '9f190001-0000-4000-8000-000000000191',
  '9f190001-0000-4000-8000-000000000192',
  '9f190001-0000-4000-8000-000000000193'
);
delete from public.customers
where auth_user_id in (
  '9f190001-0000-4000-8000-000000000191',
  '9f190001-0000-4000-8000-000000000192',
  '9f190001-0000-4000-8000-000000000193'
);
update auth.users
set raw_user_meta_data = case id
  when '9f190001-0000-4000-8000-000000000091'::uuid then
    jsonb_build_object(
      'tenant_id', '9f190001-0000-4000-8000-000000000001'
    )
  when '9f190001-0000-4000-8000-000000000092'::uuid then
    jsonb_build_object(
      'tenant_id', '9f190001-0000-4000-8000-000000000001'
    )
  when '9f190001-0000-4000-8000-000000000093'::uuid then
    jsonb_build_object(
      'tenant_id', '9f190001-0000-4000-8000-000000000002'
    )
  when '9f190001-0000-4000-8000-000000000094'::uuid then
    jsonb_build_object(
      'display_name', 'Viñabike',
      'full_name', 'Viñabike',
      'name', 'Viñabike'
    )
  when '9f190001-0000-4000-8000-000000000191'::uuid then
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f190001-0000-4000-8000-000000000001'
    )
  when '9f190001-0000-4000-8000-000000000192'::uuid then
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f190001-0000-4000-8000-000000000001'
    )
  when '9f190001-0000-4000-8000-000000000193'::uuid then
    jsonb_build_object(
      'account_type', 'public_store_customer',
      'customer_tenant_id', '9f190001-0000-4000-8000-000000000002'
    )
end
where id in (
  '9f190001-0000-4000-8000-000000000091',
  '9f190001-0000-4000-8000-000000000092',
  '9f190001-0000-4000-8000-000000000093',
  '9f190001-0000-4000-8000-000000000094',
  '9f190001-0000-4000-8000-000000000191',
  '9f190001-0000-4000-8000-000000000192',
  '9f190001-0000-4000-8000-000000000193'
);

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values
  (
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f190001-0000-4000-8000-000000000092',
    '9f190001-0000-4000-8000-000000000001',
    'manager', '{}'::jsonb, true
  ),
  (
    '9f190001-0000-4000-8000-000000000093',
    '9f190001-0000-4000-8000-000000000002',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f190001-0000-4000-8000-000000000094',
    '9f190001-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  );

insert into public.customers (
  id, tenant_id, name, email, auth_user_id
) values
  (
    '9f190001-0000-4000-8000-000000000111',
    '9f190001-0000-4000-8000-000000000001',
    'Messaging Customer A', 'msg-customer-a@example.invalid',
    '9f190001-0000-4000-8000-000000000191'
  ),
  (
    '9f190001-0000-4000-8000-000000000112',
    '9f190001-0000-4000-8000-000000000001',
    'Messaging Customer B', 'msg-customer-b@example.invalid',
    '9f190001-0000-4000-8000-000000000192'
  ),
  (
    '9f190001-0000-4000-8000-000000000113',
    '9f190001-0000-4000-8000-000000000002',
    'Messaging Customer Other', 'msg-customer-other@example.invalid',
    '9f190001-0000-4000-8000-000000000193'
  ),
  (
    '9f190001-0000-4000-8000-000000000114',
    '9f190001-0000-4000-8000-000000000001',
    'Usuario', 'msg-owner@example.invalid',
    '9f190001-0000-4000-8000-000000000094'
  );

-- Auth bootstrap triggers can leave transaction-local claims behind.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.mechanic_jobs (
  id, tenant_id, customer_id, job_number, job_type,
  quotation_status, quotation_valid_until, status
) values
  (
    '9f190001-0000-4000-8000-000000000211',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-QUOTE-A', 'quotation', 'pending', now() + interval '7 days',
    'PRESUPUESTO'
  ),
  (
    '9f190001-0000-4000-8000-000000000212',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000112',
    'MSG-QUOTE-B', 'quotation', 'pending', now() + interval '7 days',
    'PRESUPUESTO'
  ),
  (
    '9f190001-0000-4000-8000-000000000213',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-QUOTE-DECLINE', 'quotation', 'pending', now() + interval '7 days',
    'PRESUPUESTO'
  ),
  (
    '9f190001-0000-4000-8000-000000000215',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-QUOTE-WHATSAPP', 'quotation', 'pending', now() + interval '7 days',
    'PRESUPUESTO'
  ),
  (
    '9f190001-0000-4000-8000-000000000218',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-QUOTE-EXPIRED', 'quotation', 'pending', now() - interval '1 day',
    'PRESUPUESTO'
  ),
  (
    '9f190001-0000-4000-8000-000000000222',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-QUOTE-WA-EXPIRED', 'quotation', 'pending', now() - interval '1 day',
    'PRESUPUESTO'
  ),
  (
    '9f190001-0000-4000-8000-000000000221',
    '9f190001-0000-4000-8000-000000000002',
    '9f190001-0000-4000-8000-000000000113',
    'MSG-QUOTE-OTHER', 'quotation', 'pending', now() + interval '7 days',
    'PRESUPUESTO'
  );

insert into public.mechanic_jobs (
  id, tenant_id, customer_id, job_number, job_type, status, status_id
) values
  (
    '9f190001-0000-4000-8000-000000000214',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-NOT-A-QUOTE', 'service', 'PENDIENTE',
    (select id from public.job_statuses where tenant_id =
      '9f190001-0000-4000-8000-000000000001' and code = 'PENDIENTE')
  ),
  (
    '9f190001-0000-4000-8000-000000000216',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-DELIVERY-ACCEPT', 'service', 'FINALIZADO',
    (select id from public.job_statuses where tenant_id =
      '9f190001-0000-4000-8000-000000000001' and code = 'FINALIZADO')
  ),
  (
    '9f190001-0000-4000-8000-000000000217',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-DELIVERY-DECLINE', 'service', 'FINALIZADO',
    (select id from public.job_statuses where tenant_id =
      '9f190001-0000-4000-8000-000000000001' and code = 'FINALIZADO')
  ),
  (
    '9f190001-0000-4000-8000-000000000219',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000111',
    'MSG-DELIVERY-WHATSAPP', 'service', 'FINALIZADO',
    (select id from public.job_statuses where tenant_id =
      '9f190001-0000-4000-8000-000000000001' and code = 'FINALIZADO')
  );

insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values
  (
    '9f190001-0000-4000-8000-000000000291',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000211',
    'Servicio cotizado', 'service', 1, 25000
  ),
  (
    '9f190001-0000-4000-8000-000000000292',
    '9f190001-0000-4000-8000-000000000001',
    '9f190001-0000-4000-8000-000000000215',
    'Servicio cotizado por WhatsApp', 'service', 1, 15000
  );

insert into public.conversations (
  id, tenant_id, type, channel, title, context_type, context_id, status,
  created_by
) values
  (
    '9f190001-0000-4000-8000-000000000311',
    '9f190001-0000-4000-8000-000000000001',
    'internal', 'internal', 'Internal A', null, null, 'active',
    '9f190001-0000-4000-8000-000000000091'
  ),
  (
    '9f190001-0000-4000-8000-000000000314',
    '9f190001-0000-4000-8000-000000000001',
    'internal', 'internal', 'Internal A shared', null, null, 'active',
    '9f190001-0000-4000-8000-000000000091'
  ),
  (
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000001',
    'support', 'whatsapp', 'Support A', 'job',
    '9f190001-0000-4000-8000-000000000211', 'active',
    '9f190001-0000-4000-8000-000000000191'
  ),
  (
    '9f190001-0000-4000-8000-000000000313',
    '9f190001-0000-4000-8000-000000000001',
    'support', 'website_portal', 'Support B', 'job',
    '9f190001-0000-4000-8000-000000000212', 'active',
    '9f190001-0000-4000-8000-000000000192'
  ),
  (
    '9f190001-0000-4000-8000-000000000321',
    '9f190001-0000-4000-8000-000000000002',
    'support', 'website_portal', 'Support Other', 'job',
    '9f190001-0000-4000-8000-000000000221', 'active',
    '9f190001-0000-4000-8000-000000000193'
  );

insert into public.conversation_participants (
  conversation_id, user_id, tenant_id, role, last_read_at
) values
  (
    '9f190001-0000-4000-8000-000000000311',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001', 'admin', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000314',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001', 'admin', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000314',
    '9f190001-0000-4000-8000-000000000092',
    '9f190001-0000-4000-8000-000000000001', 'member', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000191',
    '9f190001-0000-4000-8000-000000000001', 'member', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001', 'admin', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000313',
    '9f190001-0000-4000-8000-000000000192',
    '9f190001-0000-4000-8000-000000000001', 'member', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000321',
    '9f190001-0000-4000-8000-000000000193',
    '9f190001-0000-4000-8000-000000000002', 'member', now() - interval '1 day'
  ),
  (
    '9f190001-0000-4000-8000-000000000321',
    '9f190001-0000-4000-8000-000000000093',
    '9f190001-0000-4000-8000-000000000002', 'admin', now() - interval '1 day'
  );

insert into public.conversation_contexts (
  id, conversation_id, context_type, context_id, is_primary, added_by,
  tenant_id
) values
  (
    '9f190001-0000-4000-8000-000000000511',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000213', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000512',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000214', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000513',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000215', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000514',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000216', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000515',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000217', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000516',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000218', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000517',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000219', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  ),
  (
    '9f190001-0000-4000-8000-000000000518',
    '9f190001-0000-4000-8000-000000000312', 'job',
    '9f190001-0000-4000-8000-000000000222', false,
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001'
  );

insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type, metadata,
  created_at
) values
  (
    '9f190001-0000-4000-8000-000000000411',
    '9f190001-0000-4000-8000-000000000311',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Internal only', 'text', '{}'::jsonb, now()
  ),
  (
    '9f190001-0000-4000-8000-000000000412',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Visible staff reply', 'text', '{}'::jsonb, now()
  ),
  (
    '9f190001-0000-4000-8000-000000000413',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000191',
    '9f190001-0000-4000-8000-000000000001',
    'Inbound customer message', 'text',
    '{"message_direction":"inbound"}'::jsonb,
    now() + interval '1 minute'
  ),
  (
    '9f190001-0000-4000-8000-000000000421',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Approve quote A', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000211',
      'target_id', '9f190001-0000-4000-8000-000000000211'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000422',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Decline quote A', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000213',
      'target_id', '9f190001-0000-4000-8000-000000000213'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000423',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Ordinary message', 'text', '{}'::jsonb, now()
  ),
  (
    '9f190001-0000-4000-8000-000000000424',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Wrong customer quote', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000212',
      'target_id', '9f190001-0000-4000-8000-000000000212'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000425',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Other tenant quote', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000221',
      'target_id', '9f190001-0000-4000-8000-000000000221'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000426',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Not a quote target', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000214',
      'target_id', '9f190001-0000-4000-8000-000000000214'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000427',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Expired quote', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000218',
      'target_id', '9f190001-0000-4000-8000-000000000218'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000428',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Confirm delivery', 'action_request',
    jsonb_build_object(
      'action_type', 'confirm_delivery', 'status', 'pending',
      'target_id', '9f190001-0000-4000-8000-000000000216'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000429',
    '9f190001-0000-4000-8000-000000000312',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Decline delivery', 'action_request',
    jsonb_build_object(
      'action_type', 'confirm_delivery', 'status', 'pending',
      'target_id', '9f190001-0000-4000-8000-000000000217'
    ), now()
  ),
  (
    '9f190001-0000-4000-8000-000000000430',
    '9f190001-0000-4000-8000-000000000313',
    '9f190001-0000-4000-8000-000000000091',
    '9f190001-0000-4000-8000-000000000001',
    'Archived quote request', 'action_request',
    jsonb_build_object(
      'action_type', 'approve_quote', 'status', 'pending',
      'jobId', '9f190001-0000-4000-8000-000000000212',
      'target_id', '9f190001-0000-4000-8000-000000000212'
    ), now()
  );

insert into public.whatsapp_channels (
  id, tenant_id, phone_number_id, display_name, is_active
) values (
  '9f190001-0000-4000-8000-000000000611',
  '9f190001-0000-4000-8000-000000000001',
  'msg-security-phone-number-id', 'Messaging pgTAP', true
);

insert into public.whatsapp_conversation_bindings (
  id, tenant_id, conversation_id, channel_id, customer_id,
  external_wa_id, external_phone_number, contact_name
) values (
  '9f190001-0000-4000-8000-000000000621',
  '9f190001-0000-4000-8000-000000000001',
  '9f190001-0000-4000-8000-000000000312',
  '9f190001-0000-4000-8000-000000000611',
  '9f190001-0000-4000-8000-000000000111',
  '56976431387', '56976431387', 'Messaging Customer A'
);

insert into public.whatsapp_webhook_events (
  id, tenant_id, channel_id, event_key, event_type, direction, payload
) values
(
  '9f190001-0000-4000-8000-000000000631',
  '9f190001-0000-4000-8000-000000000001',
  '9f190001-0000-4000-8000-000000000611',
  'message:wamid.messaging.secure.quote.1',
  'message', 'inbound',
  jsonb_build_object(
    'message', jsonb_build_object(
      'id', 'wamid.messaging.secure.quote.1',
      'from', '56976431387',
      'context', jsonb_build_object(
        'id', 'wamid.messaging.outbound.quote.1'
      ),
      'interactive', jsonb_build_object(
        'button_reply', jsonb_build_object(
          'id', 'job:9f190001-0000-4000-8000-000000000215:approve_quote:1760000000001'
        )
      )
    )
  )
),
(
  '9f190001-0000-4000-8000-000000000632',
  '9f190001-0000-4000-8000-000000000001',
  '9f190001-0000-4000-8000-000000000611',
  'message:wamid.messaging.secure.delivery.1',
  'message', 'inbound',
  jsonb_build_object(
    'message', jsonb_build_object(
      'id', 'wamid.messaging.secure.delivery.1',
      'from', '56976431387',
      'context', jsonb_build_object(
        'id', 'wamid.messaging.outbound.delivery.1'
      ),
      'interactive', jsonb_build_object(
        'button_reply', jsonb_build_object(
          'id', 'job:9f190001-0000-4000-8000-000000000219:confirm_delivery:1760000000002'
        )
      )
    )
  )
),
(
  '9f190001-0000-4000-8000-000000000633',
  '9f190001-0000-4000-8000-000000000001',
  '9f190001-0000-4000-8000-000000000611',
  'message:wamid.messaging.secure.expired.1',
  'message', 'inbound',
  jsonb_build_object(
    'message', jsonb_build_object(
      'id', 'wamid.messaging.secure.expired.1',
      'from', '56976431387',
      'context', jsonb_build_object(
        'id', 'wamid.messaging.outbound.expired.1'
      ),
      'interactive', jsonb_build_object(
        'button_reply', jsonb_build_object(
          'id', 'job:9f190001-0000-4000-8000-000000000222:approve_quote:1760000000003'
        )
      )
    )
  )
);

insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type, metadata,
  external_provider, external_message_id, message_direction
) values
(
  '9f190001-0000-4000-8000-000000000440',
  '9f190001-0000-4000-8000-000000000312',
  '9f190001-0000-4000-8000-000000000091',
  '9f190001-0000-4000-8000-000000000001',
  'Presupuesto WhatsApp', 'action_request',
  jsonb_build_object(
    'action_type', 'approve_quote',
    'action_kind', 'job',
    'target_id', '9f190001-0000-4000-8000-000000000215',
    'jobId', '9f190001-0000-4000-8000-000000000215',
    'action_revision_ms', 1760000000001,
    'action_token',
      'job:9f190001-0000-4000-8000-000000000215:approve_quote:1760000000001',
    'action_reject_token',
      'job:9f190001-0000-4000-8000-000000000215:reject_quote:1760000000001',
    'action_allowed_actions', jsonb_build_array('approve_quote', 'reject_quote'),
    'status', 'pending'
  ),
  'whatsapp', 'wamid.messaging.outbound.quote.1', 'outbound'
),
(
  '9f190001-0000-4000-8000-000000000441',
  '9f190001-0000-4000-8000-000000000312',
  null,
  '9f190001-0000-4000-8000-000000000001',
  'Aprobar presupuesto', 'text', '{}'::jsonb,
  'whatsapp', 'wamid.messaging.secure.quote.1', 'inbound'
),
(
  '9f190001-0000-4000-8000-000000000442',
  '9f190001-0000-4000-8000-000000000312',
  '9f190001-0000-4000-8000-000000000091',
  '9f190001-0000-4000-8000-000000000001',
  'Confirmar entrega WhatsApp', 'action_request',
  jsonb_build_object(
    'action_type', 'confirm_delivery', 'action_kind', 'job',
    'target_id', '9f190001-0000-4000-8000-000000000219',
    'jobId', '9f190001-0000-4000-8000-000000000219',
    'action_revision_ms', 1760000000002,
    'action_token',
      'job:9f190001-0000-4000-8000-000000000219:confirm_delivery:1760000000002',
    'action_reject_token',
      'job:9f190001-0000-4000-8000-000000000219:cancel_delivery:1760000000002',
    'action_allowed_actions', jsonb_build_array('confirm_delivery', 'cancel_delivery'),
    'status', 'pending'
  ),
  'whatsapp', 'wamid.messaging.outbound.delivery.1', 'outbound'
),
(
  '9f190001-0000-4000-8000-000000000443',
  '9f190001-0000-4000-8000-000000000312',
  null,
  '9f190001-0000-4000-8000-000000000001',
  'Confirmar entrega', 'text', '{}'::jsonb,
  'whatsapp', 'wamid.messaging.secure.delivery.1', 'inbound'
),
(
  '9f190001-0000-4000-8000-000000000444',
  '9f190001-0000-4000-8000-000000000312',
  '9f190001-0000-4000-8000-000000000091',
  '9f190001-0000-4000-8000-000000000001',
  'Presupuesto vencido WhatsApp', 'action_request',
  jsonb_build_object(
    'action_type', 'approve_quote', 'action_kind', 'job',
    'target_id', '9f190001-0000-4000-8000-000000000222',
    'jobId', '9f190001-0000-4000-8000-000000000222',
    'action_revision_ms', 1760000000003,
    'action_token',
      'job:9f190001-0000-4000-8000-000000000222:approve_quote:1760000000003',
    'action_reject_token',
      'job:9f190001-0000-4000-8000-000000000222:reject_quote:1760000000003',
    'action_allowed_actions', jsonb_build_array('approve_quote', 'reject_quote'),
    'status', 'pending'
  ),
  'whatsapp', 'wamid.messaging.outbound.expired.1', 'outbound'
),
(
  '9f190001-0000-4000-8000-000000000445',
  '9f190001-0000-4000-8000-000000000312',
  null,
  '9f190001-0000-4000-8000-000000000001',
  'Aprobar presupuesto vencido', 'text', '{}'::jsonb,
  'whatsapp', 'wamid.messaging.secure.expired.1', 'inbound'
);

-- API privileges and view execution model.
select ok(
  not has_table_privilege('anon', 'public.conversations', 'SELECT'),
  'anonymous clients have no conversations table grant'
);
select ok(
  not has_table_privilege('authenticated', 'public.messages', 'UPDATE'),
  'authenticated clients cannot rewrite message evidence'
);
select ok(
  not has_table_privilege('authenticated', 'public.messages', 'DELETE'),
  'authenticated clients cannot delete message evidence'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.delete_conversation(uuid)', 'EXECUTE'
  ),
  'legacy hard-delete RPC is unavailable to authenticated clients'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.archive_conversation(uuid)', 'EXECUTE'
  ),
  'authenticated clients can invoke the scoped archive RPC'
);
select ok(
  not has_function_privilege(
    'anon', 'public.archive_conversation(uuid)', 'EXECUTE'
  ),
  'anonymous clients cannot archive conversations'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.update_conversation_timestamp()', 'EXECUTE'
  ),
  'message timestamp trigger is not callable through the API'
);
select ok(
  position(
    'for share' in lower(pg_get_functiondef(
      'public.enforce_messaging_tenant_consistency()'::regprocedure
    ))
  ) > 0,
  'message insert serializes its open-state check with conversation archival'
);
select ok(
  position(
    'for share of conversation' in lower(pg_get_functiondef(
      'public.respond_to_action_request(uuid,text,text,jsonb)'::regprocedure
    ))
  ) > 0,
  'client action response serializes its open-state check with archival'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.get_public_user_info(uuid)', 'EXECUTE'
  ),
  'authenticated chat callers can resolve visible participant labels'
);
select ok(
  not has_function_privilege(
    'anon', 'public.get_public_user_info(uuid)', 'EXECUTE'
  ),
  'anonymous callers cannot enumerate user labels'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.set_config(text,text,boolean)', 'EXECUTE'
  ),
  'authenticated clients cannot mint arbitrary session capabilities'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.confirm_invoice_approval(uuid)', 'EXECUTE'
  ),
  'legacy invoice-as-quotation approval RPC is unavailable'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the WhatsApp automation command'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)',
    'EXECUTE'
  ),
  'only the webhook service role can invoke the WhatsApp automation command'
);
select is(
  (
    select coalesce(
      (select option_value = 'true'
       from pg_options_to_table(c.reloptions)
       where option_name = 'security_invoker'),
      false
    )
    from pg_class c
    where c.oid = 'public.conversation_unread_counts'::regclass
  ),
  true,
  'unread projection executes with invoker rights'
);

set local role anon;
select throws_ok(
  $$select count(*) from public.conversations$$,
  '42501',
  'permission denied for table conversations',
  'anonymous callers cannot enumerate conversations'
);
select throws_ok(
  $$select public.get_public_user_info(
      '9f190001-0000-4000-8000-000000000091'
    )$$,
  '42501',
  'permission denied for function get_public_user_info',
  'anonymous callers cannot invoke participant profile lookup'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000094',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000094',
  true
);
set local role authenticated;
select is(
  public.get_public_user_info(
    '9f190001-0000-4000-8000-000000000094'
  )->>'name',
  'Viñabike',
  'an ERP owner label wins over a legacy customer membership'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role')::text,
  true
);
select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
select throws_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000215',
      'reject_quote',
      'wamid.messaging.secure.quote.1',
      '{"message":{"forged":true}}'::jsonb,
      'wamid.messaging.outbound.quote.1',
      1760000000001
    )$$,
  '42501',
  'WhatsApp action token does not match the requested job action',
  'caller payload cannot replace the durable WhatsApp action token'
);
select throws_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000212',
      'approve_quote',
      'wamid.messaging.secure.quote.1',
      '{}'::jsonb,
      'wamid.messaging.outbound.quote.1',
      1760000000001
    )$$,
  '42501',
  'WhatsApp action token does not match the requested job action',
  'WhatsApp action cannot substitute another job for the bound token'
);
select lives_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000215',
      'approve_quote',
      'wamid.messaging.secure.quote.1',
      '{}'::jsonb,
      'wamid.messaging.outbound.quote.1',
      1760000000001
    )$$,
  'validated WhatsApp approval executes the canonical quotation command'
);
reset role;

select is(
  (select quotation_status from public.mechanic_jobs
   where id = '9f190001-0000-4000-8000-000000000215'),
  'approved',
  'WhatsApp approval updates canonical quotation state'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where tenant_id = '9f190001-0000-4000-8000-000000000001'
     and operation_key = md5(
       'whatsapp-job-quotation:wamid.messaging.secure.quote.1'
     )::uuid::text),
  1,
  'external message id produces one deterministic quotation receipt'
);

set local role service_role;
select lives_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000215',
      'approve_quote',
      'wamid.messaging.secure.quote.1',
      '{"retry":true}'::jsonb,
      'wamid.messaging.outbound.quote.1',
      1760000000001
    )$$,
  'duplicate webhook replay is idempotent after lost acknowledgement'
);
reset role;
select is(
  (select metadata #>> '{whatsapp_job_action,action}'
   from public.messages
   where id = '9f190001-0000-4000-8000-000000000441'),
  'approve_quote',
  'WhatsApp replay retains the atomic action receipt on the inbound message'
);

set local role service_role;
select throws_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000222',
      'approve_quote',
      'wamid.messaging.secure.expired.1',
      '{}'::jsonb,
      'wamid.messaging.outbound.expired.1',
      1760000000003
    )$$,
  '23514',
  'La cotización venció y requiere revisión del taller',
  'WhatsApp cannot approve an expired quotation card'
);
update public.conversations
set status = null
where id = '9f190001-0000-4000-8000-000000000312';
select throws_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000222',
      'approve_quote',
      'wamid.messaging.secure.expired.1',
      '{}'::jsonb,
      'wamid.messaging.outbound.expired.1',
      1760000000003
    )$$,
  '23514',
  'WhatsApp action request conversation is closed',
  'WhatsApp action treats nullable legacy conversation status as closed'
);
update public.conversations
set status = 'active'
where id = '9f190001-0000-4000-8000-000000000312';
select lives_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000219',
      'confirm_delivery',
      'wamid.messaging.secure.delivery.1',
      '{}'::jsonb,
      'wamid.messaging.outbound.delivery.1',
      1760000000002
    )$$,
  'WhatsApp delivery confirmation uses the canonical status command'
);
reset role;
select is(
  (select status from public.mechanic_jobs
   where id = '9f190001-0000-4000-8000-000000000219'),
  'ENTREGADO',
  'WhatsApp delivery confirmation updates the canonical job status'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_status_transition_events
   where operation_key =
     'whatsapp-job-status:wamid.messaging.secure.delivery.1'),
  1,
  'WhatsApp delivery confirmation appends one status transition receipt'
);
select is(
  (select metadata->>'status' from public.messages
   where id = '9f190001-0000-4000-8000-000000000442'),
  'accepted',
  'WhatsApp response closes the exact outbound action card'
);
set local role service_role;
select lives_ok(
  $$select public.apply_whatsapp_job_action(
      '9f190001-0000-4000-8000-000000000219',
      'confirm_delivery',
      'wamid.messaging.secure.delivery.1',
      '{"retry":true}'::jsonb,
      'wamid.messaging.outbound.delivery.1',
      1760000000002
    )$$,
  'WhatsApp delivery replay returns its durable inbound receipt'
);
reset role;
select is(
  (select count(*)::integer
   from public.mechanic_job_status_transition_events
   where operation_key =
     'whatsapp-job-status:wamid.messaging.secure.delivery.1'),
  1,
  'WhatsApp delivery replay does not append a second transition event'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Staff A participates in the internal thread and sees same-tenant support.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000091',
  true
);
set local role authenticated;
select is(
  (select count(*)::integer from public.conversations),
  4,
  'tenant A staff participant sees both internal and both support threads'
);
select is(
  (select count(*)::integer from public.messages
   where conversation_id = '9f190001-0000-4000-8000-000000000311'),
  1,
  'internal participant reads internal messages'
);
select is(
  public.get_public_user_info(
    '9f190001-0000-4000-8000-000000000191'
  )->>'name',
  'Messaging Customer A',
  'participant profile lookup resolves a customer in an accessible thread'
);
select throws_ok(
  $$select public.get_public_user_info(
      '9f190001-0000-4000-8000-000000000193'
    )$$,
  '42501',
  'User is not visible in an accessible conversation',
  'participant profile lookup cannot enumerate a foreign tenant'
);
select throws_ok(
  $$insert into public.conversation_participants (
      conversation_id, user_id, tenant_id, role
    ) values (
      '9f190001-0000-4000-8000-000000000312',
      '9f190001-0000-4000-8000-000000000192',
      '9f190001-0000-4000-8000-000000000001',
      'member'
    )$$,
  '42501',
  'new row violates row-level security policy for table "conversation_participants"',
  'staff cannot expose customer A history by enrolling customer B'
);
reset role;

-- Same-tenant staff B shares support but is not implicitly an internal member.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000092',
  true
);
set local role authenticated;
select is(
  (select count(*)::integer from public.conversations),
  3,
  'same-tenant staff sees shared support plus their explicit internal thread'
);
select is(
  (select count(*)::integer from public.messages
   where conversation_id = '9f190001-0000-4000-8000-000000000311'),
  0,
  'same-tenant staff cannot read internal messages without participation'
);
select lives_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type
    ) values (
      '9f190001-0000-4000-8000-000000000414',
      '9f190001-0000-4000-8000-000000000314',
      '9f190001-0000-4000-8000-000000000092',
      null,
      'Internal member reply',
      'text'
    )$$,
  'non-admin internal participant can send without timestamp-trigger rollback'
);
select is(
  (select tenant_id from public.messages
   where id = '9f190001-0000-4000-8000-000000000414'),
  '9f190001-0000-4000-8000-000000000001'::uuid,
  'internal member message keeps the canonical conversation tenant'
);
select cmp_ok(
  (select unread_count
   from public.conversation_unread_counts
   where conversation_id = '9f190001-0000-4000-8000-000000000312'),
  '>',
  0,
  'shared-support staff receives unread counts without participant enrollment'
);
reset role;

-- Cross-tenant staff sees only their own tenant support graph.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000093',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000093',
  true
);
set local role authenticated;
select is(
  (select array_agg(id order by id) from public.conversations),
  array['9f190001-0000-4000-8000-000000000321'::uuid],
  'foreign-tenant staff sees no tenant A conversation'
);
reset role;

-- Customer A sees the complete own support history, including staff replies,
-- but no internal, sibling-customer, or foreign-tenant conversation.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000191',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000191',
  true
);
set local role authenticated;
select is(
  (select array_agg(id order by id) from public.conversations),
  array['9f190001-0000-4000-8000-000000000312'::uuid],
  'customer sees only their explicit support conversation'
);
select is(
  (select count(*)::integer from public.messages
   where id = '9f190001-0000-4000-8000-000000000412'),
  1,
  'customer can read staff replies in their support thread'
);
select is(
  (select count(*)::integer from public.conversation_unread_counts),
  1,
  'unread projection exposes only the current customer participant row'
);
select cmp_ok(
  (select unread_count from public.conversation_unread_counts),
  '>',
  0,
  'customer unread projection counts later staff messages'
);
select lives_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type
    ) values (
      '9f190001-0000-4000-8000-000000000431',
      '9f190001-0000-4000-8000-000000000312',
      '9f190001-0000-4000-8000-000000000191',
      null,
      'Customer reply with canonical tenant',
      'text'
    )$$,
  'customer can send a normal message to their own support thread'
);
select is(
  (select tenant_id from public.messages
   where id = '9f190001-0000-4000-8000-000000000431'),
  '9f190001-0000-4000-8000-000000000001'::uuid,
  'message tenant is canonicalized from its parent conversation'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type, metadata
    ) values (
      '9f190001-0000-4000-8000-000000000435',
      '9f190001-0000-4000-8000-000000000312',
      '9f190001-0000-4000-8000-000000000191',
      '9f190001-0000-4000-8000-000000000001',
      'https://attacker.invalid/pixel.png',
      'image',
      '{"url":"https://attacker.invalid/pixel.png"}'::jsonb
    )$$,
  '42501',
  'new row violates row-level security policy for table "messages"',
  'customer cannot insert an image that makes another client load an arbitrary URL'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type, metadata
    ) values (
      '9f190001-0000-4000-8000-000000000436',
      '9f190001-0000-4000-8000-000000000312',
      '9f190001-0000-4000-8000-000000000191',
      '9f190001-0000-4000-8000-000000000001',
      'Forged quotation card hidden in text metadata',
      'text',
      '{"type":"quote_request","jobId":"9f190001-0000-4000-8000-000000000211","status":"pending"}'::jsonb
    )$$,
  '42501',
  'new row violates row-level security policy for table "messages"',
  'customer cannot smuggle a quotation/action card through text metadata'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type
    ) values (
      '9f190001-0000-4000-8000-000000000432',
      '9f190001-0000-4000-8000-000000000313',
      '9f190001-0000-4000-8000-000000000191',
      '9f190001-0000-4000-8000-000000000001',
      'Forbidden sibling reply',
      'text'
    )$$,
  '42501',
  'new row violates row-level security policy for table "messages"',
  'customer cannot send into another customer support thread'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type, metadata
    ) values (
      '9f190001-0000-4000-8000-000000000433',
      '9f190001-0000-4000-8000-000000000312',
      '9f190001-0000-4000-8000-000000000191',
      '9f190001-0000-4000-8000-000000000001',
      'Forged action card',
      'action_request',
      '{"action_type":"approve_quote"}'::jsonb
    )$$,
  '42501',
  'new row violates row-level security policy for table "messages"',
  'customer cannot forge a staff action-request card'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type,
      external_provider, external_message_id, external_status
    ) values (
      '9f190001-0000-4000-8000-000000000434',
      '9f190001-0000-4000-8000-000000000312',
      '9f190001-0000-4000-8000-000000000191',
      '9f190001-0000-4000-8000-000000000001',
      'Forged provider evidence',
      'text', 'whatsapp', 'wamid.forged', 'read'
    )$$,
  '42501',
  'new row violates row-level security policy for table "messages"',
  'customer cannot forge WhatsApp provider or delivery evidence'
);
select throws_ok(
  $$insert into public.conversation_participants (
      conversation_id, user_id, tenant_id, role
    ) values (
      '9f190001-0000-4000-8000-000000000313',
      '9f190001-0000-4000-8000-000000000191',
      '9f190001-0000-4000-8000-000000000001',
      'member'
    )$$,
  '42501',
  'new row violates row-level security policy for table "conversation_participants"',
  'customer cannot auto-enroll in another customer conversation'
);
select throws_ok(
  $$insert into public.conversations (
      id, tenant_id, type, channel, title, status
    ) values (
      '9f190001-0000-4000-8000-000000000331',
      '9f190001-0000-4000-8000-000000000002',
      'support', 'website_portal', 'Cross tenant forged support', 'pending'
    )$$,
  '42501',
  'permission denied for table conversations',
  'customer cannot create a partial support conversation directly'
);
select throws_ok(
  $$insert into public.conversations (
      id, tenant_id, type, channel, title, status
    ) values (
      '9f190001-0000-4000-8000-000000000332',
      '9f190001-0000-4000-8000-000000000001',
      'internal', 'internal', 'Forged internal chat', 'active'
    )$$,
  '42501',
  'permission denied for table conversations',
  'customer cannot create a partial internal conversation directly'
);

-- Action-request authorization and graph integrity.
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000421',
      'not_supported', 'accepted', '{}'::jsonb
    )$$,
  '22023',
  'Unsupported action request type',
  'action response rejects unknown action kinds'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000421',
      'approve_quote', 'maybe', '{}'::jsonb
    )$$,
  '22023',
  'Unsupported action request status',
  'action response rejects unknown terminal states'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000423',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '22023',
  'Message is not an action request',
  'ordinary messages cannot be converted into action responses'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000421',
      'pay_now', 'accepted', '{}'::jsonb
    )$$,
  '22023',
  'Action request type mismatch',
  'caller cannot swap the stored action identity'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000424',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '42501',
  'Customer, conversation, and quotation are not linked',
  'customer cannot approve another customer quotation'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000425',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '42501',
  'Customer, conversation, and quotation are not linked',
  'customer cannot approve a foreign-tenant quotation'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000426',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '23514',
  'El trabajo no es una cotización.',
  'canonical workshop command rejects a non-quotation target'
);
select is(
  (select metadata->>'status' from public.messages
   where id = '9f190001-0000-4000-8000-000000000426'),
  'pending',
  'failed canonical transition leaves message metadata pending atomically'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where operation_key = '9f190001-0000-4000-8000-000000000426'),
  0,
  'failed canonical transition creates no quotation audit receipt'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000427',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '23514',
  'La cotización venció y requiere revisión del taller',
  'customer cannot approve an expired quotation card'
);
select is(
  (select metadata->>'status' from public.messages
   where id = '9f190001-0000-4000-8000-000000000427'),
  'pending',
  'expired quotation rejection leaves the action request pending atomically'
);
select lives_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000428',
      'confirm_delivery', 'accepted', '{}'::jsonb
    )$$,
  'customer delivery acceptance uses the canonical job status command'
);
select lives_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000429',
      'confirm_delivery', 'declined',
      '{"response_note":"Aún no la recibo"}'::jsonb
    )$$,
  'customer delivery decline records the response without a job transition'
);
select lives_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000421',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  'linked customer can approve through the atomic messaging command'
);
reset role;

insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values (
  '9f190001-0000-4000-8000-000000000316',
  '9f190001-0000-4000-8000-000000000001',
  'support', 'website_portal', 'Legacy null action status', 'active',
  '9f190001-0000-4000-8000-000000000092'
);
insert into public.conversation_participants (
  conversation_id, user_id, tenant_id, role
) values (
  '9f190001-0000-4000-8000-000000000316',
  '9f190001-0000-4000-8000-000000000192',
  '9f190001-0000-4000-8000-000000000001',
  'member'
);
insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type, metadata
) values (
  '9f190001-0000-4000-8000-000000000458',
  '9f190001-0000-4000-8000-000000000316',
  '9f190001-0000-4000-8000-000000000092',
  '9f190001-0000-4000-8000-000000000001',
  'Legacy null-status approval request',
  'action_request',
  jsonb_build_object(
    'action_type', 'approve_quote',
    'target_id', '9f190001-0000-4000-8000-000000000212',
    'status', 'pending'
  )
);
update public.conversations
set status = null
where id = '9f190001-0000-4000-8000-000000000316';

select is(
  (select status from public.mechanic_jobs
   where id = '9f190001-0000-4000-8000-000000000216'),
  'ENTREGADO',
  'accepted delivery action updates the canonical job state'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_status_transition_events
   where operation_key =
     'messaging-delivery:9f190001-0000-4000-8000-000000000428'),
  1,
  'accepted delivery action appends one immutable transition receipt'
);
select is(
  (select status from public.mechanic_jobs
   where id = '9f190001-0000-4000-8000-000000000217'),
  'FINALIZADO',
  'declined delivery action does not move the job state'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_status_transition_events
   where operation_key =
     'messaging-delivery:9f190001-0000-4000-8000-000000000429'),
  0,
  'declined delivery action creates no job status transition event'
);

select is(
  (select quotation_status from public.mechanic_jobs
   where id = '9f190001-0000-4000-8000-000000000211'),
  'approved',
  'accepted action updates canonical quotation status'
);
select is(
  (select actor_id from public.mechanic_job_mode_events
   where operation_key = '9f190001-0000-4000-8000-000000000421'),
  '9f190001-0000-4000-8000-000000000191'::uuid,
  'quotation ledger records the customer actor'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where operation_key = '9f190001-0000-4000-8000-000000000421'),
  1,
  'message UUID is the unique quotation operation receipt'
);
select is(
  (select metadata->>'status' from public.messages
   where id = '9f190001-0000-4000-8000-000000000421'),
  'accepted',
  'message becomes accepted only after canonical transition commits'
);

create temporary table messaging_action_replay_snapshot as
select metadata->>'responded_at' as responded_at
from public.messages
where id = '9f190001-0000-4000-8000-000000000421';
grant select on messaging_action_replay_snapshot to authenticated;

set local role authenticated;
select lives_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000421',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  'same customer decision replays idempotently after a lost acknowledgement'
);
select is(
  (select metadata->>'responded_at' from public.messages
   where id = '9f190001-0000-4000-8000-000000000421'),
  (select responded_at from messaging_action_replay_snapshot),
  'terminal action replay preserves the original response timestamp'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000422',
      'approve_quote', 'declined',
      '{"customer_note":"arbitrary key"}'::jsonb
    )$$,
  '22023',
  'Unsupported action response metadata',
  'action response rejects every client metadata key except response_note'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000422',
      'approve_quote', 'declined',
      jsonb_build_object('response_note', repeat('x', 1001))
    )$$,
  '22023',
  'Action response note is too long',
  'decline response note is bounded to 1000 characters'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000422',
      'approve_quote', 'accepted',
      '{"response_note":"not valid on acceptance"}'::jsonb
    )$$,
  '22023',
  'Response note is only allowed for declined actions',
  'response note is accepted only for a declined decision'
);
select lives_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000422',
      'approve_quote', 'declined',
      '{"response_note":"  Necesito otro alcance  "}'::jsonb
    )$$,
  'linked customer can reject through the same canonical command'
);
reset role;

select is(
  (select quotation_status from public.mechanic_jobs
   where id = '9f190001-0000-4000-8000-000000000213'),
  'rejected',
  'declined action updates canonical quotation status'
);
select is(
  (select metadata->>'action_type' from public.messages
   where id = '9f190001-0000-4000-8000-000000000422'),
  'approve_quote',
  'caller metadata cannot replace protected action type'
);
select is(
  (select metadata->>'target_id' from public.messages
   where id = '9f190001-0000-4000-8000-000000000422'),
  '9f190001-0000-4000-8000-000000000213',
  'caller metadata cannot replace protected target id'
);
select is(
  (select metadata->>'response_note' from public.messages
   where id = '9f190001-0000-4000-8000-000000000422'),
  'Necesito otro alcance',
  'decline response note is trimmed and retained atomically'
);

-- A sibling customer cannot even answer a visible UUID guessed from another
-- conversation.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000192',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000192',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000421',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '42501',
  'Not authorized to respond to this action request',
  'sibling customer cannot answer another conversation action UUID'
);
reset role;

-- Same-tenant support staff may archive shared support without deleting any
-- evidence; customers and unrelated internal users may not.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000191',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000191',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.archive_conversation(
      '9f190001-0000-4000-8000-000000000312'
    )$$,
  '42501',
  'Not authorized to archive this conversation',
  'customer cannot archive or hide the support audit trail'
);
reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000092',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.archive_conversation(
      '9f190001-0000-4000-8000-000000000311'
    )$$,
  '42501',
  'Not authorized to archive this conversation',
  'same-tenant staff cannot archive unrelated internal chat'
);
select is(
  (public.archive_conversation(
    '9f190001-0000-4000-8000-000000000313'
  )->>'changed')::boolean,
  true,
  'same-tenant staff archives shared support through the scoped RPC'
);
select is(
  (public.archive_conversation(
    '9f190001-0000-4000-8000-000000000313'
  )->>'changed')::boolean,
  false,
  'archive replay is idempotent and creates no duplicate event'
);
select is(
  public.messaging_can_write_conversation(
    '9f190001-0000-4000-8000-000000000313'
  ),
  false,
  'archived conversation remains readable but is not writable'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type
    ) values (
      '9f190001-0000-4000-8000-000000000451',
      '9f190001-0000-4000-8000-000000000313',
      '9f190001-0000-4000-8000-000000000092',
      '9f190001-0000-4000-8000-000000000001',
      'Late staff message', 'text'
    )$$,
  '23514',
  'Conversation is closed to new messages',
  'staff cannot append a client message after archival'
);
select is(
  (public.archive_conversation(
    '9f190001-0000-4000-8000-000000000312'
  )->>'changed')::boolean,
  true,
  'staff can archive the WhatsApp thread for terminal-policy tests'
);
reset role;

select is(
  (select status from public.conversations
   where id = '9f190001-0000-4000-8000-000000000313'),
  'resolved',
  'archived conversation remains as a resolved record'
);
select is(
  (select resolved_by from public.conversations
   where id = '9f190001-0000-4000-8000-000000000313'),
  '9f190001-0000-4000-8000-000000000092'::uuid,
  'archive records the staff actor'
);
select is(
  (select count(*)::integer from public.conversation_participants
   where conversation_id = '9f190001-0000-4000-8000-000000000313'),
  1,
  'archive preserves conversation participants'
);
select is(
  (select count(*)::integer from public.messages
   where conversation_id = '9f190001-0000-4000-8000-000000000313'
     and type = 'system'
     and metadata->>'event' = 'conversation_resolved'),
  1,
  'archive appends exactly one resolution event'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f190001-0000-4000-8000-000000000192',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f190001-0000-4000-8000-000000000192',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000430',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '23514',
  'Action request conversation is closed',
  'pending cards in archived conversations cannot mutate workshop state'
);
select throws_ok(
  $$select public.respond_to_action_request(
      '9f190001-0000-4000-8000-000000000458',
      'approve_quote', 'accepted', '{}'::jsonb
    )$$,
  '23514',
  'Action request conversation is closed',
  'client action treats nullable legacy conversation status as closed'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type
    ) values (
      '9f190001-0000-4000-8000-000000000452',
      '9f190001-0000-4000-8000-000000000313',
      '9f190001-0000-4000-8000-000000000192',
      '9f190001-0000-4000-8000-000000000001',
      'Late customer message', 'text'
    )$$,
  '23514',
  'Conversation is closed to new messages',
  'customer cannot append a client message after archival'
);
reset role;

-- Webhook evidence has a deliberate exception: trusted inbound WhatsApp rows
-- may be retained in the archived thread, but outbound sends are rejected and
-- the terminal conversation is never revived.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role')::text,
  true
);
select set_config('request.jwt.claim.sub', '', true);
set local role service_role;
insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values (
  '9f190001-0000-4000-8000-000000000315',
  '9f190001-0000-4000-8000-000000000001',
  'support', 'whatsapp', 'Legacy null status', null,
  '9f190001-0000-4000-8000-000000000091'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type,
      external_provider, external_message_id, message_direction
    ) values (
      '9f190001-0000-4000-8000-000000000457',
      '9f190001-0000-4000-8000-000000000315',
      null,
      '9f190001-0000-4000-8000-000000000001',
      'Outbound into legacy null status', 'text',
      'whatsapp', 'wamid.messaging.null-status.outbound.1', 'outbound'
    )$$,
  '23514',
  'Conversation is closed to new messages',
  'nullable legacy conversation status is treated as closed'
);
insert into public.whatsapp_webhook_events (
  id, tenant_id, channel_id, event_key, event_type, direction, payload
) values (
  '9f190001-0000-4000-8000-000000000634',
  '9f190001-0000-4000-8000-000000000001',
  '9f190001-0000-4000-8000-000000000611',
  'message:wamid.messaging.closed.inbound.1',
  'message', 'inbound',
  jsonb_build_object(
    'message', jsonb_build_object(
      'id', 'wamid.messaging.closed.inbound.1',
      'from', '56976431387'
    )
  )
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type,
      external_provider, external_message_id, message_direction
    ) values (
      '9f190001-0000-4000-8000-000000000453',
      '9f190001-0000-4000-8000-000000000312',
      null,
      '9f190001-0000-4000-8000-000000000001',
      'Late outbound send', 'text',
      'whatsapp', 'wamid.messaging.closed.outbound.1', 'outbound'
    )$$,
  '23514',
  'Conversation is closed to new messages',
  'service worker cannot send outbound into an archived conversation'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type,
      external_provider, external_message_id, message_direction
    ) values (
      '9f190001-0000-4000-8000-000000000455',
      '9f190001-0000-4000-8000-000000000312',
      null,
      '9f190001-0000-4000-8000-000000000001',
      'Forged late action card', 'action_request',
      'whatsapp', 'wamid.messaging.closed.inbound.1', 'inbound'
    )$$,
  '23514',
  'Conversation is closed to new messages',
  'late provider exception cannot inject a privileged action card'
);
select throws_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type,
      external_provider, external_message_id, message_direction
    ) values (
      '9f190001-0000-4000-8000-000000000456',
      '9f190001-0000-4000-8000-000000000312',
      null,
      '9f190001-0000-4000-8000-000000000001',
      'Provider identity omitted', 'text',
      null, 'wamid.messaging.closed.inbound.1', 'inbound'
    )$$,
  '23514',
  'Conversation is closed to new messages',
  'nullable provider fields fail closed in the late-evidence exception'
);
select lives_ok(
  $$insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type,
      external_provider, external_message_id, message_direction
    ) values (
      '9f190001-0000-4000-8000-000000000454',
      '9f190001-0000-4000-8000-000000000312',
      null,
      '9f190001-0000-4000-8000-000000000001',
      'Late inbound provider evidence', 'text',
      'whatsapp', 'wamid.messaging.closed.inbound.1', 'inbound'
    )$$,
  'trusted inbound provider evidence is retained after archival'
);
reset role;
select is(
  (select status from public.conversations
   where id = '9f190001-0000-4000-8000-000000000312'),
  'resolved',
  'late inbound provider evidence does not revive the conversation'
);
select is(
  (select count(*)::integer from public.messages
   where id = '9f190001-0000-4000-8000-000000000454'
     and external_provider = 'whatsapp'
     and message_direction = 'inbound'),
  1,
  'late inbound provider evidence remains traceable as a message'
);
select is(
  (select count(*)::integer from public.messages
   where conversation_id = '9f190001-0000-4000-8000-000000000312'
     and type = 'system'
     and metadata->>'event' = 'conversation_resolved'),
  1,
  'late provider evidence does not duplicate the resolution event'
);
select throws_ok(
  $$update public.conversations
    set status = 'active'
    where id = '9f190001-0000-4000-8000-000000000313'$$,
  '23514',
  'Resolved conversations are retained and cannot be reopened',
  'resolved conversation cannot be silently reopened'
);

select * from finish();

rollback;
