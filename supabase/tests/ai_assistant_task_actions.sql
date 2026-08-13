begin;

select no_plan();

select has_table('public', 'assistant_approvals',
  'durable assistant approval ledger exists');
select has_function('public', 'assistant_prepare_task_v1', array[
  'text','text','text','text','text','text','uuid','integer','text','text'
], 'caller-bound task preparation RPC exists');
select has_function('public', 'assistant_apply_task_approval_v1',
  array['uuid','text','uuid'], 'post-click approval RPC exists');
select hasnt_function('public', 'assistant_create_task_v1',
  'there is no model-callable task commit RPC');
select ok((select relrowsecurity and relforcerowsecurity
  from pg_class where oid = 'public.assistant_approvals'::regclass),
  'approval ledger forces RLS');
select ok((select bool_and(not has_table_privilege(role_name,
    'public.assistant_approvals', privilege))
  from unnest(array['authenticated','anon','service_role']) role_name
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) privilege),
  'client and runtime roles have no direct approval table access');
select ok(has_function_privilege('authenticated',
    'public.assistant_prepare_task_v1(text,text,text,text,text,text,uuid,integer,text,text)',
    'EXECUTE')
  and has_function_privilege('authenticated',
    'public.assistant_apply_task_approval_v1(uuid,text,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.assistant_apply_task_approval_v1(uuid,text,uuid)', 'EXECUTE'),
  'only authenticated caller JWT can prepare or click an approval');
select ok(position('prepare_task' in pg_get_functiondef(
  'assistant_runtime.assistant_record_tool_receipt_v1(uuid,uuid,text,uuid,uuid,bigint,integer,integer,text,text,text,text,text,text,text,text,integer,integer,boolean,boolean,text,timestamptz,timestamptz)'::regprocedure
)) > 0, 'runtime receipt allowlist includes the draft tool');
select ok(position('can_manage_tenant_users' in pg_get_functiondef(
  'public.assistant_prepare_task_v1(text,text,text,text,text,text,uuid,integer,text,text)'::regprocedure
)) > 0, 'named assignment delegates to the canonical tenant-user authority');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"task_preview","title":"Llamar","destination":"tasks","chips":["high"],"approvalRef":{"id":"a1750000-0000-4000-8000-000000000001","action":"create_task","state":"pending","expiresAt":"2026-08-11T12:10:00.000000Z"}}]'::jsonb
), true, 'closed task preview card is ledger-valid');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"task","title":"Llamar","destination":"tasks","chips":[],"approvalRef":{"id":"a1750000-0000-4000-8000-000000000001","action":"create_task","state":"pending","expiresAt":"2026-08-11T12:10:00.000000Z"}}]'::jsonb
), false, 'ordinary task cards cannot smuggle an approval');

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1750000-0000-4000-8000-000000000001', 'Action tenant A',
   'action-cashier@example.invalid', 'America/Santiago'),
  ('a1750000-0000-4000-8000-000000000002', 'Action tenant B',
   'action-neighbor@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1750000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'action-admin@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1750000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'action-cashier@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1750000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'action-lucas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1750000-0000-4000-8000-000000000014', 'authenticated', 'authenticated',
   'action-neighbor@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
) values (
  'a1750000-0000-4000-8000-000000000021',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000013',
  'AI-ACTION-001', 'Lucas', 'Mecánico', 'Mecánico', 'full_time', 'active', 0
);

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, employee_id
) values
  ('a1750000-0000-4000-8000-000000000011',
   'a1750000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, null),
  ('a1750000-0000-4000-8000-000000000012',
   'a1750000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, null),
  ('a1750000-0000-4000-8000-000000000013',
   'a1750000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'a1750000-0000-4000-8000-000000000021'),
  ('a1750000-0000-4000-8000-000000000014',
   'a1750000-0000-4000-8000-000000000002', 'manager', '{}'::jsonb, null);

create temp table action_admin_authority(payload jsonb);
create temp table action_cashier_authority(payload jsonb);
grant insert, select on action_admin_authority, action_cashier_authority
to authenticated;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1750000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1750000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into action_admin_authority select public.assistant_get_authority_v1();
reset role;

insert into public.assistant_threads (
  id, tenant_id, actor_user_id, authority_role, authority_fingerprint
) values (
  'a1750000-0000-4000-8000-000000000101',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011', 'admin',
  (select payload->>'authorityFingerprint' from action_admin_authority)
);
insert into public.assistant_runs (
  id, tenant_id, actor_user_id, thread_id, run_no, client_request_id,
  request_hash, model_role, status, authority_role, authority_fingerprint,
  turn_budget, provider_attempt_budget, tool_call_budget, max_output_tokens
) values (
  'a1750000-0000-4000-8000-000000000111',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000101', 1,
  'a1750000-0000-4000-8000-000000000121', repeat('1', 64), 'fast',
  'running', 'admin',
  (select payload->>'authorityFingerprint' from action_admin_authority),
  5, 12, 8, 2048
);
insert into public.assistant_provider_attempts (
  id, tenant_id, actor_user_id, run_id, attempt_no, provider, model,
  model_role, status, finish_reason, provider_request_hash, response_hash,
  input_tokens, output_tokens, estimated_cost_microusd, started_at, completed_at
) values (
  'a1750000-0000-4000-8000-000000000131',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000111', 1,
  'gemini', 'gemini-test', 'fast', 'succeeded', 'tool_calls',
  repeat('2', 64), repeat('3', 64), 1, 1, 0, now(), now()
);

create temp table action_admin_preview(payload jsonb);
grant insert, select on action_admin_preview to authenticated;
set local role authenticated;
insert into action_admin_preview select public.assistant_prepare_task_v1(
  '  Llamar al cliente  ', ' Confirmar retiro ', 'high',
  '2026-08-13T16:00:00Z', 'name', 'Lucas',
  'a1750000-0000-4000-8000-000000000111', 1,
  repeat('4', 64), repeat('5', 64)
);
reset role;

select is((select payload->>'resultCount' from action_admin_preview), '1',
  'model preparation returns one exact preview');
select is((select payload#>>'{items,0,title}' from action_admin_preview),
  'Llamar al cliente', 'task title is normalized before persistence');
select is((select payload#>>'{items,0,assigneeName}' from action_admin_preview),
  'Lucas Mecánico', 'a unique first name resolves to one active canonical profile');
select is((select count(*)::text from public.smart_tasks), '0',
  'preparation never creates a task');
select is((select count(*)::text from public.assistant_approvals), '1',
  'preparation is durable');
select is((select extract(epoch from (expires_at - created_at))::integer::text
  from public.assistant_approvals), '600',
  'approval TTL is exactly ten minutes');
select is((select state from public.assistant_approvals), 'pending',
  'prepared approval begins pending');
select is((select action_payload->>'assignedTo' from public.assistant_approvals),
  'a1750000-0000-4000-8000-000000000013',
  'server-owned payload stores the resolved active user, not a name lookup request');

set local role authenticated;
select is(public.assistant_prepare_task_v1(
  '  Llamar al cliente  ', ' Confirmar retiro ', 'high',
  '2026-08-13T16:00:00Z', 'name', 'Lucas',
  'a1750000-0000-4000-8000-000000000111', 1,
  repeat('4', 64), repeat('5', 64)
) #>> '{items,0,approvalId}',
  (select payload#>>'{items,0,approvalId}' from action_admin_preview),
  'ambiguous preparation retry returns the same approval');
select throws_ok($$select public.assistant_prepare_task_v1(
  'Otra tarea', null, 'high', null, 'name', 'Lucas',
  'a1750000-0000-4000-8000-000000000111', 1,
  repeat('4', 64), repeat('6', 64)
)$$, '22023', 'AI preparation idempotency conflict',
  'same provider call cannot change its task payload');
reset role;

insert into public.assistant_tool_receipts (
  tenant_id, actor_user_id, run_id, provider_attempt_id, ordinal,
  provider_call_hash, tool_name, tool_version, risk, policy_decision,
  status, arguments_hash, output_hash, result_count, output_bytes,
  approval_used, read_back_verified, started_at, completed_at
) values (
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000111',
  'a1750000-0000-4000-8000-000000000131', 1,
  repeat('4', 64), 'prepare_task', 'v1', 'draft', 'approval_required',
  'succeeded', repeat('5', 64), repeat('7', 64), 1, 100,
  false, true, now(), now()
);

update public.assistant_runs set status = 'succeeded', completed_at = now()
where id = 'a1750000-0000-4000-8000-000000000111';
insert into public.assistant_messages (
  id, tenant_id, actor_user_id, thread_id, sequence_no, role, content, cards, run_id
) values (
  'a1750000-0000-4000-8000-000000000141',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000101', 1, 'assistant',
  'Tarea preparada',
  jsonb_build_array(jsonb_build_object(
    'kind', 'task_preview', 'title', 'Llamar al cliente',
    'destination', 'tasks', 'chips', jsonb_build_array('high'),
    'approvalRef', jsonb_build_object(
      'id', (select payload#>>'{items,0,approvalId}' from action_admin_preview),
      'action', 'create_task', 'state', 'pending',
      'expiresAt', (select payload#>>'{items,0,expiresAt}' from action_admin_preview)
    )
  )),
  'a1750000-0000-4000-8000-000000000111'
);

create temp table action_admin_commit(payload jsonb);
grant insert, select on action_admin_commit to authenticated;
set local role authenticated;
insert into action_admin_commit select public.assistant_apply_task_approval_v1(
  (select (payload#>>'{items,0,approvalId}')::uuid from action_admin_preview),
  'approve', 'a1750000-0000-4000-8000-000000000151'
);
reset role;

select is((select payload->>'approvalState' from action_admin_commit),
  'approved', 'explicit click approves the task');
select is((select payload#>>'{task,title}' from action_admin_commit),
  'Llamar al cliente', 'commit returns exact authoritative task read-back');
select is((select count(*)::text from public.smart_tasks
  where title = 'Llamar al cliente'), '1', 'approval creates exactly one task');
select is((select assigned_to::text from public.smart_tasks
  where title = 'Llamar al cliente'),
  'a1750000-0000-4000-8000-000000000013',
  'commit uses the server-resolved assignee UUID');
select is((select state from public.assistant_approvals), 'approved',
  'approval is consumed once');
select is((select count(*)::text from public.assistant_tool_receipts
  where tool_name = 'create_task' and risk = 'reversible_write'
    and policy_decision = 'allowed' and approval_used is true
    and read_back_verified is true), '1',
  'commit atomically records an approval-used read-back receipt');
select is((select cards#>>'{0,approvalRef,state}' from public.assistant_messages
  where id = 'a1750000-0000-4000-8000-000000000141'),
  'approved', 'persisted preview reflects the terminal approval state');

set local role authenticated;
select is(public.assistant_apply_task_approval_v1(
  (select (payload#>>'{items,0,approvalId}')::uuid from action_admin_preview),
  'approve', 'a1750000-0000-4000-8000-000000000151'
)::text, (select payload::text from action_admin_commit),
  'same client action replay returns the exact durable response');
select throws_ok(format(
  'select public.assistant_apply_task_approval_v1(%L::uuid,%L,%L::uuid)',
  (select payload#>>'{items,0,approvalId}' from action_admin_preview),
  'discard', 'a1750000-0000-4000-8000-000000000152'
), '22023', 'Approval was already consumed',
  'a consumed approval cannot be changed');
reset role;
select is((select count(*)::text from public.smart_tasks
  where title = 'Llamar al cliente'), '1',
  'approval replay cannot duplicate the task');

-- An active, owner-labeled cashier profile proves self/unassigned scopes while
-- named assignment stays closed without canonical admin/manager/manage_users
-- authority. Tenant ownership does not widen can_manage_tenant_users.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1750000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1750000-0000-4000-8000-000000000012', true);
set local role authenticated;
insert into action_cashier_authority select public.assistant_get_authority_v1();
reset role;

insert into public.assistant_threads (
  id, tenant_id, actor_user_id, authority_role, authority_fingerprint
) values
  ('a1750000-0000-4000-8000-000000000201',
   'a1750000-0000-4000-8000-000000000001',
   'a1750000-0000-4000-8000-000000000012', 'owner',
   (select payload->>'authorityFingerprint' from action_cashier_authority)),
  ('a1750000-0000-4000-8000-000000000202',
   'a1750000-0000-4000-8000-000000000001',
   'a1750000-0000-4000-8000-000000000012', 'owner',
   (select payload->>'authorityFingerprint' from action_cashier_authority));
insert into public.assistant_runs (
  id, tenant_id, actor_user_id, thread_id, run_no, client_request_id,
  request_hash, model_role, status, authority_role, authority_fingerprint,
  turn_budget, provider_attempt_budget, tool_call_budget, max_output_tokens
) values
  ('a1750000-0000-4000-8000-000000000211',
   'a1750000-0000-4000-8000-000000000001',
   'a1750000-0000-4000-8000-000000000012',
   'a1750000-0000-4000-8000-000000000201', 1,
   'a1750000-0000-4000-8000-000000000221', repeat('8',64), 'fast',
   'running', 'owner',
   (select payload->>'authorityFingerprint' from action_cashier_authority),
   5, 12, 8, 2048),
  ('a1750000-0000-4000-8000-000000000212',
   'a1750000-0000-4000-8000-000000000001',
   'a1750000-0000-4000-8000-000000000012',
   'a1750000-0000-4000-8000-000000000202', 1,
   'a1750000-0000-4000-8000-000000000222', repeat('9',64), 'fast',
   'running', 'owner',
   (select payload->>'authorityFingerprint' from action_cashier_authority),
   5, 12, 8, 2048);
insert into public.assistant_provider_attempts (
  id, tenant_id, actor_user_id, run_id, attempt_no, provider, model,
  model_role, status, finish_reason, provider_request_hash, response_hash,
  started_at, completed_at
) values
  ('a1750000-0000-4000-8000-000000000231',
   'a1750000-0000-4000-8000-000000000001',
   'a1750000-0000-4000-8000-000000000012',
   'a1750000-0000-4000-8000-000000000211', 1,
   'gemini', 'gemini-test', 'fast', 'succeeded', 'tool_calls',
   repeat('a',64), repeat('b',64), now(), now()),
  ('a1750000-0000-4000-8000-000000000232',
   'a1750000-0000-4000-8000-000000000001',
   'a1750000-0000-4000-8000-000000000012',
   'a1750000-0000-4000-8000-000000000212', 1,
   'gemini', 'gemini-test', 'fast', 'succeeded', 'tool_calls',
   repeat('c',64), repeat('d',64), now(), now());

create temp table action_self_preview(payload jsonb);
create temp table action_unassigned_preview(payload jsonb);
grant insert, select on action_self_preview, action_unassigned_preview
to authenticated;
set local role authenticated;
insert into action_self_preview select public.assistant_prepare_task_v1(
  'Revisar caja', null, 'normal', null, 'me', null,
  'a1750000-0000-4000-8000-000000000211', 1, repeat('e',64), repeat('f',64)
);
select is((select payload#>>'{items,0,assigneeName}' from action_self_preview),
  'Tú', 'any active profile may prepare a task assigned to self');
select throws_ok($$select public.assistant_prepare_task_v1(
  'Asignar por nombre', null, 'normal', null, 'name', 'Lucas',
  'a1750000-0000-4000-8000-000000000211', 1, repeat('1',64), repeat('2',64)
)$$, '42501', 'Named task assignment is not allowed',
  'owner-labeled non-manager cannot address another person by name');
insert into action_unassigned_preview select public.assistant_prepare_task_v1(
  'Ordenar mostrador', null, 'low', null, 'unassigned', null,
  'a1750000-0000-4000-8000-000000000212', 1, repeat('3',64), repeat('4',64)
);
select is((select payload#>>'{items,0,assigneeName}' from action_unassigned_preview),
  'Sin asignar', 'active profile may prepare an unassigned task');
reset role;

update public.assistant_runs set status = 'succeeded', completed_at = now()
where id in (
  'a1750000-0000-4000-8000-000000000211',
  'a1750000-0000-4000-8000-000000000212'
);
update public.assistant_approvals set
  created_at = statement_timestamp() - interval '11 minutes',
  expires_at = statement_timestamp() - interval '1 minute',
  updated_at = statement_timestamp()
where id = (select (payload#>>'{items,0,approvalId}')::uuid
  from action_unassigned_preview);

set local role authenticated;
select is(public.assistant_apply_task_approval_v1(
  (select (payload#>>'{items,0,approvalId}')::uuid from action_self_preview),
  'discard', 'a1750000-0000-4000-8000-000000000251'
)->>'approvalState', 'discarded', 'discard consumes the preview without a task');
select is(public.assistant_apply_task_approval_v1(
  (select (payload#>>'{items,0,approvalId}')::uuid from action_unassigned_preview),
  'approve', 'a1750000-0000-4000-8000-000000000252'
)->>'approvalState', 'expired', 'expired approval cannot write even on approve');
reset role;
select is((select count(*)::text from public.smart_tasks
  where title in ('Revisar caja', 'Ordenar mostrador')), '0',
  'discard and expiry never create tasks');

-- A forced receipt collision proves the task insert, approval mutation and
-- action evidence are one transaction rather than best-effort steps.
insert into public.assistant_threads (
  id, tenant_id, actor_user_id, authority_role, authority_fingerprint
) values (
  'a1750000-0000-4000-8000-000000000301',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011', 'admin',
  (select payload->>'authorityFingerprint' from action_admin_authority)
);
insert into public.assistant_runs (
  id, tenant_id, actor_user_id, thread_id, run_no, client_request_id,
  request_hash, model_role, status, authority_role, authority_fingerprint,
  turn_budget, provider_attempt_budget, tool_call_budget, max_output_tokens
) values (
  'a1750000-0000-4000-8000-000000000311',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000301', 1,
  'a1750000-0000-4000-8000-000000000321', repeat('6',64), 'fast',
  'running', 'admin',
  (select payload->>'authorityFingerprint' from action_admin_authority),
  5, 12, 8, 2048
);
insert into public.assistant_provider_attempts (
  id, tenant_id, actor_user_id, run_id, attempt_no, provider, model,
  model_role, status, finish_reason, provider_request_hash, response_hash,
  started_at, completed_at
) values (
  'a1750000-0000-4000-8000-000000000331',
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000311', 1,
  'gemini', 'gemini-test', 'fast', 'succeeded', 'tool_calls',
  repeat('7',64), repeat('8',64), now(), now()
);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1750000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1750000-0000-4000-8000-000000000011', true);
create temp table action_collision_preview(payload jsonb);
grant insert, select on action_collision_preview to authenticated;
set local role authenticated;
insert into action_collision_preview select public.assistant_prepare_task_v1(
  'No debe sobrevivir', null, 'normal', null, 'me', null,
  'a1750000-0000-4000-8000-000000000311', 1, repeat('9',64), repeat('a',64)
);
reset role;
update public.assistant_runs set status = 'succeeded', completed_at = now()
where id = 'a1750000-0000-4000-8000-000000000311';
insert into public.assistant_tool_receipts (
  tenant_id, actor_user_id, run_id, provider_attempt_id, ordinal,
  provider_call_hash, tool_name, tool_version, risk, policy_decision,
  status, arguments_hash, output_hash, result_count, output_bytes,
  approval_used, read_back_verified, started_at, completed_at
) values (
  'a1750000-0000-4000-8000-000000000001',
  'a1750000-0000-4000-8000-000000000011',
  'a1750000-0000-4000-8000-000000000311',
  'a1750000-0000-4000-8000-000000000331', 1,
  encode(extensions.digest(convert_to(
    'assistant:task-action:a1750000-0000-4000-8000-000000000351', 'UTF8'
  ), 'sha256'), 'hex'),
  'search_tasks', 'v1', 'read', 'allowed', 'succeeded', repeat('b',64),
  repeat('c',64), 1, 10, false, true, now(), now()
);
set local role authenticated;
select throws_ok(format(
  'select public.assistant_apply_task_approval_v1(%L::uuid,%L,%L::uuid)',
  (select payload#>>'{items,0,approvalId}' from action_collision_preview),
  'approve', 'a1750000-0000-4000-8000-000000000351'
), '23505', null,
  'receipt collision aborts the entire approval transaction');
reset role;
select is((select count(*)::text from public.smart_tasks
  where title = 'No debe sobrevivir'), '0',
  'failed receipt leaves no partially committed task');
select is((select state from public.assistant_approvals
  where id = (select (payload#>>'{items,0,approvalId}')::uuid
    from action_collision_preview)), 'pending',
  'failed receipt leaves the approval retryable and unconsumed');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1750000-0000-4000-8000-000000000014', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1750000-0000-4000-8000-000000000014', true);
set local role authenticated;
select throws_ok(format(
  'select public.assistant_apply_task_approval_v1(%L::uuid,%L,%L::uuid)',
  (select payload#>>'{items,0,approvalId}' from action_admin_preview),
  'approve', 'a1750000-0000-4000-8000-000000000401'
), '42501', 'Approval is unavailable',
  'another tenant cannot observe or consume an approval');
reset role;

select * from finish();
rollback;
