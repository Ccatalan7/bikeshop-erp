begin;

select no_plan();

select has_function('public', 'assistant_query_workshop_jobs_v3',
  array['text','text','text','text','integer'],
  'relationship-aware workshop resolver exists');
select has_function('public', 'assistant_get_workshop_job_context_v1',
  array['uuid'], 'exact workshop context reader exists');
select has_function('public', 'assistant_inspect_diagnosis_schema_v1',
  array['text'], 'diagnosis field registry reader exists');
select has_function('public', 'assistant_prepare_diagnosis_update_v1', array[
  'uuid','uuid','text','numeric','text','text','text','uuid','integer','text','text'
], 'typed diagnosis preparation exists');
select has_function('public', 'assistant_prepare_workshop_item_v1', array[
  'uuid','uuid','uuid','numeric','text','text','uuid','integer','text','text'
], 'catalog-backed workshop item preparation exists');
select has_function('public', 'assistant_apply_approval_v2',
  array['uuid','text','uuid'], 'generic post-click approval command exists');
select ok(
  has_function_privilege('authenticated',
    'public.assistant_prepare_diagnosis_update_v1(uuid,uuid,text,numeric,text,text,text,uuid,integer,text,text)',
    'EXECUTE')
  and has_function_privilege('authenticated',
    'public.assistant_prepare_workshop_item_v1(uuid,uuid,uuid,numeric,text,text,uuid,integer,text,text)',
    'EXECUTE')
  and has_function_privilege('authenticated',
    'public.assistant_apply_approval_v2(uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.assistant_apply_approval_v2(uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.assistant_apply_approval_v2(uuid,text,uuid)', 'EXECUTE'),
  'only an authenticated caller can prepare or consume workshop approvals');
select is(public.assistant_capabilities_internal_v2(
    'mechanic', 'mechanic', '{}'::jsonb) ? 'ai.write.workshop', true,
  'persisted mechanic receives governed workshop write capability');
select is(public.assistant_capabilities_internal_v2(
    'cashier', 'owner', '{}'::jsonb) ? 'ai.write.workshop', false,
  'presentation owner cannot widen a persisted cashier into workshop writes');
select ok((select pg_get_functiondef(function.oid) like all(array[
      '%get_workshop_job_context%', '%inspect_diagnosis_schema%',
      '%analyze_sales_period%', '%prepare_diagnosis_update%',
      '%prepare_workshop_item%'
    ])
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'assistant_runtime'
      and function.proname = 'assistant_tool_receipt_contract_internal_v1'),
  'receipt contract contains every new read and preparation primitive');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"diagnosis_preview","title":"Cadena","destination":"workshop_jobs","chips":[],"approvalRef":{"id":"a1760000-0000-4000-8000-000000000001","action":"update_diagnosis","state":"pending","expiresAt":"2026-08-14T01:10:00.000000Z"}}]'::jsonb
), true, 'diagnosis approval preview is a closed durable card');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"diagnosis_preview","title":"Cadena","destination":"workshop_jobs","chips":[],"approvalRef":{"id":"a1760000-0000-4000-8000-000000000001","action":"add_workshop_item","state":"pending","expiresAt":"2026-08-14T01:10:00.000000Z"}}]'::jsonb
), false, 'preview kind cannot be paired with another action');

insert into public.tenants (id, shop_name, owner_email, timezone)
values (
  'a1760000-0000-4000-8000-000000000001',
  'Workshop action tenant', 'workshop-action@example.invalid',
  'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1760000-0000-4000-8000-000000000011',
  'authenticated', 'authenticated', 'workshop-action@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role, permissions)
values (
  'a1760000-0000-4000-8000-000000000011',
  'a1760000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb
);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
insert into public.customers (id, tenant_id, name)
values (
  'a1760000-0000-4000-8000-000000000021',
  'a1760000-0000-4000-8000-000000000001', 'Álvaro González'
);
insert into public.bikes (id, tenant_id, customer_id, brand, model, year)
values (
  'a1760000-0000-4000-8000-000000000031',
  'a1760000-0000-4000-8000-000000000001',
  'a1760000-0000-4000-8000-000000000021', 'Trek', 'Marlin 7', 2023
);
insert into public.products (
  id, tenant_id, name, sku, price, cost, is_service, product_type,
  track_stock, is_active
) values (
  'a1760000-0000-4000-8000-000000000041',
  'a1760000-0000-4000-8000-000000000001',
  'Cambio de cadena', 'SRV-CHAIN', 15000, 0, true, 'service', false, true
);
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, status,
  subtotal, total, balance, items, source
) values (
  'a1760000-0000-4000-8000-000000000051',
  'a1760000-0000-4000-8000-000000000001', 'FV-AI-ACTION',
  'a1760000-0000-4000-8000-000000000021', 'Álvaro González', 'draft',
  0, 0, 0, '[]'::jsonb, 'mechanic_job'
);
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, bike_id, job_number, job_type, status,
  priority, invoice_id, is_invoiced
) values (
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000001',
  'a1760000-0000-4000-8000-000000000021',
  'a1760000-0000-4000-8000-000000000031', 'PG-AI-ACTION',
  'service', 'PENDIENTE', 'NORMAL',
  'a1760000-0000-4000-8000-000000000051', true
);
insert into public.mechanic_job_bikes (
  id, tenant_id, job_id, bike_id, order_index,
  diagnosis_sheet_key, diagnosis_sheet_data, diagnosis_sheet_updated_at
) values (
  'a1760000-0000-4000-8000-000000000071',
  'a1760000-0000-4000-8000-000000000001',
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000031', 0,
  'basic_workshop_v1', '{}'::jsonb, null
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);

create temp table action_authority(payload jsonb);
create temp table diagnosis_preview(payload jsonb);
create temp table diagnosis_stale_preview(payload jsonb);
create temp table diagnosis_commit(payload jsonb);
create temp table item_preview(payload jsonb);
create temp table item_discard_preview(payload jsonb);
create temp table item_commit(payload jsonb);
grant insert, select on action_authority, diagnosis_preview,
  diagnosis_stale_preview, diagnosis_commit, item_preview,
  item_discard_preview, item_commit to authenticated;

set local role authenticated;
insert into action_authority select public.assistant_get_authority_v1();
select is((select payload->'capabilities' ? 'ai.write.workshop'
  from action_authority), true,
  'live authority publishes workshop write capability');
select is((public.assistant_query_workshop_jobs_v3(
  'Marlin 7', 'any', 'open', 'any', 10
) #>> '{items,0,entityId}'),
  'a1760000-0000-4000-8000-000000000061',
  'job resolver matches a bike identity instead of only the job label');
select is((public.assistant_get_workshop_job_context_v1(
  'a1760000-0000-4000-8000-000000000061'
) #>> '{items,0,jobBikeId}'),
  'a1760000-0000-4000-8000-000000000071',
  'exact job context returns the internal bike target');
select ok((public.assistant_inspect_diagnosis_schema_v1('drivetrain')
  -> 'items') @> '[{"field":"drivetrain.chain_wear_percent"}]'::jsonb,
  'diagnosis registry publishes the canonical chain-wear field');
reset role;

insert into public.assistant_threads (
  id, tenant_id, actor_user_id, authority_role, authority_fingerprint
) values
  ('a1760000-0000-4000-8000-000000000101',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000011', 'admin',
   (select payload->>'authorityFingerprint' from action_authority)),
  ('a1760000-0000-4000-8000-000000000102',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000011', 'admin',
   (select payload->>'authorityFingerprint' from action_authority));
insert into public.assistant_runs (
  id, tenant_id, actor_user_id, thread_id, run_no, client_request_id,
  request_hash, model_role, status, authority_role, authority_fingerprint,
  turn_budget, provider_attempt_budget, tool_call_budget, max_output_tokens
) values
  ('a1760000-0000-4000-8000-000000000111',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000011',
   'a1760000-0000-4000-8000-000000000101', 1,
   'a1760000-0000-4000-8000-000000000121', repeat('1',64), 'fast',
   'running', 'admin',
   (select payload->>'authorityFingerprint' from action_authority),
   5, 12, 8, 2048),
  ('a1760000-0000-4000-8000-000000000112',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000011',
   'a1760000-0000-4000-8000-000000000102', 1,
   'a1760000-0000-4000-8000-000000000122', repeat('2',64), 'fast',
   'running', 'admin',
   (select payload->>'authorityFingerprint' from action_authority),
   5, 12, 8, 2048);
insert into public.assistant_provider_attempts (
  id, tenant_id, actor_user_id, run_id, attempt_no, provider, model,
  model_role, status, finish_reason, provider_request_hash, response_hash,
  started_at, completed_at
) values
  ('a1760000-0000-4000-8000-000000000131',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000011',
   'a1760000-0000-4000-8000-000000000111', 1,
   'gemini', 'gemini-test', 'fast', 'succeeded', 'tool_calls',
   repeat('3',64), repeat('4',64), now(), now()),
  ('a1760000-0000-4000-8000-000000000132',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000011',
   'a1760000-0000-4000-8000-000000000112', 1,
   'gemini', 'gemini-test', 'fast', 'succeeded', 'tool_calls',
   repeat('5',64), repeat('6',64), now(), now());

set local role authenticated;
insert into diagnosis_preview select public.assistant_prepare_diagnosis_update_v1(
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000071',
  'drivetrain.chain_wear_percent', 0.6, null, 'display_fraction', null,
  'a1760000-0000-4000-8000-000000000111', 1,
  repeat('7',64), repeat('8',64)
);
insert into diagnosis_stale_preview
select public.assistant_prepare_diagnosis_update_v1(
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000071',
  'drivetrain.chain_wear_percent', 0.7, null, 'display_fraction', null,
  'a1760000-0000-4000-8000-000000000111', 1,
  repeat('b',64), repeat('c',64)
);
reset role;
select is((select payload#>>'{items,0,newValue}' from diagnosis_preview),
  '0.60', 'display fraction remains visible in the approval preview');
select is((select count(*)::text from public.mechanic_job_bikes
  where id = 'a1760000-0000-4000-8000-000000000071'
    and diagnosis_sheet_data = '{}'::jsonb), '1',
  'preparing a diagnosis never changes the sheet');

update public.assistant_runs set status='succeeded', completed_at=now()
where id='a1760000-0000-4000-8000-000000000111';
set local role authenticated;
insert into diagnosis_commit select public.assistant_apply_approval_v2(
  (select (payload#>>'{items,0,approvalId}')::uuid from diagnosis_preview),
  'approve', 'a1760000-0000-4000-8000-000000000151'
);
reset role;
select is((select payload->>'action' from diagnosis_commit),
  'update_diagnosis', 'generic approval identifies the committed action');
select is((select diagnosis_sheet_data #>> '{drivetrain,chain_wear_percent}'
  from public.mechanic_job_bikes
  where id='a1760000-0000-4000-8000-000000000071'),
  '60.0', '0.6 gauge input is stored canonically as 60 percent');
select is((select payload#>>'{result,newValue}' from diagnosis_commit),
  '0.60', 'diagnosis commit returns exact authoritative read-back');
select is((select count(*)::text from public.assistant_tool_receipts
  where tool_name='update_diagnosis' and approval_used is true
    and read_back_verified is true), '1',
  'diagnosis commit records an approval-used read-back receipt');
set local role authenticated;
select throws_ok(format(
  'select public.assistant_apply_approval_v2(%L::uuid,%L,%L::uuid)',
  (select payload#>>'{items,0,approvalId}' from diagnosis_stale_preview),
  'approve', 'a1760000-0000-4000-8000-000000000153'
), '22023', 'Workshop diagnosis revision changed',
  'a concurrent diagnosis change blocks a stale prepared approval');
reset role;
select is((select diagnosis_sheet_data #>> '{drivetrain,chain_wear_percent}'
  from public.mechanic_job_bikes
  where id='a1760000-0000-4000-8000-000000000071'),
  '60.0', 'stale approval cannot overwrite the committed diagnosis');

set local role authenticated;
insert into item_preview select public.assistant_prepare_workshop_item_v1(
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000071',
  'a1760000-0000-4000-8000-000000000041', 1, null,
  (select to_char(updated_at at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
   from public.mechanic_jobs
   where id='a1760000-0000-4000-8000-000000000061'),
  'a1760000-0000-4000-8000-000000000112', 1,
  repeat('9',64), repeat('a',64)
);
insert into item_discard_preview select public.assistant_prepare_workshop_item_v1(
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000071',
  'a1760000-0000-4000-8000-000000000041', 2, 'Propuesta descartable',
  (select to_char(updated_at at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
   from public.mechanic_jobs
   where id='a1760000-0000-4000-8000-000000000061'),
  'a1760000-0000-4000-8000-000000000112', 1,
  repeat('d',64), repeat('e',64)
);
reset role;
select is((select payload#>>'{items,0,lineTotal}' from item_preview),
  '15000.00', 'workshop preview prices the exact catalog service on the server');
select is((select count(*)::text from public.mechanic_job_items), '0',
  'preparing a workshop line performs no mutation');

update public.assistant_runs set status='succeeded', completed_at=now()
where id='a1760000-0000-4000-8000-000000000112';
set local role authenticated;
insert into item_commit select public.assistant_apply_approval_v2(
  (select (payload#>>'{items,0,approvalId}')::uuid from item_preview),
  'approve', 'a1760000-0000-4000-8000-000000000152'
);
reset role;
select is((select count(*)::text from public.mechanic_job_items
  where job_id='a1760000-0000-4000-8000-000000000061'
    and service_product_id='a1760000-0000-4000-8000-000000000041'
    and job_bike_id='a1760000-0000-4000-8000-000000000071'
    and total_price=15000), '1',
  'confirmed service is added once to the exact bike and job');
select is((select payload#>>'{result,invoiceNumber}' from item_commit),
  'FV-AI-ACTION', 'workshop commit read-back preserves linked invoice identity');
select ok((select items @> '[{"product_name":"Cambio de cadena"}]'::jsonb
  from public.sales_invoices
  where id='a1760000-0000-4000-8000-000000000051'),
  'linked draft invoice is synchronized from the canonical job item');
select is((select count(*)::text from public.assistant_tool_receipts
  where tool_name='add_workshop_item' and approval_used is true
    and read_back_verified is true), '1',
  'workshop item commit records one verified approval receipt');

set local role authenticated;
select is(public.assistant_apply_approval_v2(
  (select (payload#>>'{items,0,approvalId}')::uuid from item_preview),
  'approve', 'a1760000-0000-4000-8000-000000000152'
)::text, (select payload::text from item_commit),
  'lost acknowledgement replay returns the exact durable item result');
reset role;
select is((select count(*)::text from public.mechanic_job_items
  where service_product_id='a1760000-0000-4000-8000-000000000041'), '1',
  'approval replay cannot duplicate a workshop line');

set local role authenticated;
select is(public.assistant_apply_approval_v2(
  (select (payload#>>'{items,0,approvalId}')::uuid from item_discard_preview),
  'discard', 'a1760000-0000-4000-8000-000000000154'
)->>'approvalState', 'discarded',
  'discard consumes a prepared workshop line without executing it');
reset role;
select is((select count(*)::text from public.mechanic_job_items
  where service_product_id='a1760000-0000-4000-8000-000000000041'), '1',
  'discarded workshop proposal adds no second line');

alter table public.sales_invoices disable trigger user;
update public.sales_invoices set status='paid', paid_amount=100
where id='a1760000-0000-4000-8000-000000000051';
alter table public.sales_invoices enable trigger user;
set local role authenticated;
select throws_ok(format(
  'select public.assistant_prepare_workshop_item_v1(%L::uuid,%L::uuid,%L::uuid,1,null,%L,%L::uuid,1,%L,%L)',
  'a1760000-0000-4000-8000-000000000061',
  'a1760000-0000-4000-8000-000000000071',
  'a1760000-0000-4000-8000-000000000041',
  (select to_char(updated_at at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') from public.mechanic_jobs
    where id='a1760000-0000-4000-8000-000000000061'),
  'a1760000-0000-4000-8000-000000000112', repeat('f',64), repeat('0',64)
), '42501', 'Workshop invoice has financial history',
  'paid workshop invoice cannot receive a newly prepared line');
reset role;

select * from finish();
rollback;
