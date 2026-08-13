begin;

select no_plan();

select has_column('public', 'assistant_tool_receipts', 'external_provider',
  'tool receipts store an external research provider');
select has_column('public', 'assistant_tool_receipts', 'external_model',
  'tool receipts store the exact external model');
select has_column('public', 'assistant_tool_receipts', 'external_usage_state',
  'tool receipts distinguish reported, estimated and unavailable usage');
select has_column('public', 'assistant_tool_receipts', 'external_input_tokens',
  'tool receipts store external input tokens');
select has_column('public', 'assistant_tool_receipts', 'external_output_tokens',
  'tool receipts store external output tokens');
select has_column('public', 'assistant_tool_receipts', 'external_meter',
  'tool receipts store the non-token meter');
select has_column('public', 'assistant_tool_receipts', 'external_meter_units',
  'tool receipts store non-token meter units');
select has_column('public', 'assistant_tool_receipts', 'external_cost_microusd',
  'tool receipts store bounded external cost');

select has_function('assistant_runtime', 'assistant_record_tool_receipt_usage_v1', array[
  'uuid','uuid','text','uuid','uuid','bigint','integer','integer','text','text',
  'text','text','text','text','text','text','integer','integer','boolean','boolean',
  'text','text','text','text','bigint','bigint','text','integer','bigint',
  'timestamp with time zone','timestamp with time zone'
], 'internal external-usage receipt owner exists');
select ok(not has_function_privilege('authenticated',
  'assistant_runtime.assistant_record_tool_receipt_usage_v1(uuid,uuid,text,uuid,uuid,bigint,integer,integer,text,text,text,text,text,text,text,text,integer,integer,boolean,boolean,text,text,text,text,bigint,bigint,text,integer,bigint,timestamptz,timestamptz)',
  'EXECUTE'), 'caller cannot bypass the attested v2 receipt boundary');
select ok(has_function_privilege('authenticated',
  'assistant_runtime.assistant_record_tool_receipt_v2(text,text,text)',
  'EXECUTE'), 'caller retains the single attested receipt RPC');
select is((select count(*)::text
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and has_function_privilege('authenticated', function.oid, 'EXECUTE')),
  '4', 'forward migration does not broaden caller runtime authority');

-- Exercise the table invariant directly without retaining fixture rows. A
-- partial external tuple must not exploit SQL three-valued CHECK semantics.
select throws_ok($$
  insert into public.assistant_tool_receipts (
    tenant_id, actor_user_id, run_id, ordinal, provider_call_hash,
    tool_name, tool_version, risk, policy_decision, status, arguments_hash,
    result_count, output_bytes, approval_used, read_back_verified,
    failure_code, started_at, completed_at, external_provider,
    external_model, external_usage_state, external_meter
  ) values (
    gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 1, repeat('a',64),
    'research_public_web', 'v1', 'public_research', 'allowed', 'failed',
    repeat('b',64), 0, 0, false, false, 'tool_source_unavailable', now(), now(),
    'gemini', null, 'configured_estimate', 'google_search_query'
  )
$$, '23514', null,
  'partial external usage tuple is rejected before any foreign-key lookup');

select ok((select pg_get_functiondef(function.oid) like
    '%v_has_external_usage := assistant_runtime.assistant_json_has_exact_keys_internal_v1%'
    and pg_get_functiondef(function.oid) like
    '%if not v_has_external_usage and not%'
    and pg_get_functiondef(function.oid) like
    '%else 0 end%'
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and function.proname = 'assistant_record_tool_receipt_v2'),
  'v2 accepts only exact old or exact external-usage bodies during DB-first rollout');

select ok((select pg_get_functiondef(function.oid) like
    '%assistant_record_tool_receipt_v1(%'
    and pg_get_functiondef(function.oid) like
    '%input_tokens = run.input_tokens + p_external_input_tokens%'
    and pg_get_functiondef(function.oid) not like '%provider_attempt_count =%'
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and function.proname = 'assistant_record_tool_receipt_usage_v1'),
  'one transaction owns receipt plus run/quota usage without synthetic attempts');

select ok((select pg_get_functiondef(function.oid) like
    '%if (v_attestation ->> ''replayed'')::boolean then%'
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and function.proname = 'assistant_record_tool_receipt_v2'),
  'exact nonce replay returns before any usage or quota increment');

-- Exercise the accounting owner against a real run. The attested wrapper is
-- covered by the runtime ledger's golden HMAC tests; this test owns the new
-- receipt fields and their atomic aggregates.
insert into public.tenants(id, shop_name, owner_email) values
('a1201000-0000-4000-8000-000000000001', 'AI research ledger',
 'owner-research@example.invalid');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1201000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
  'researcher@example.invalid', '', now(), '{}', '{}', now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role, permissions) values
('a1201000-0000-4000-8000-000000000011',
 'a1201000-0000-4000-8000-000000000001', 'admin', '{}');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1201000-0000-4000-8000-000000000011',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a1201000-0000-4000-8000-000000000011', true);
set local role authenticated;
create temp table research_authority as
select public.assistant_get_authority_v1() payload;
create temp table research_begin as
select public.assistant_begin_run_v1(
  'a1201000-0000-4000-8000-000000000101', repeat('a', 64),
  'segun reddit, cual es la mejor forma de evitar pinchazos de rueda?',
  'deep', null, 5, 8, 2048, 'ai-agent-gateway-v1', 110
) payload;
reset role;

select assistant_runtime.assistant_record_provider_attempt_v1(
  'a1201000-0000-4000-8000-000000000001',
  'a1201000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from research_authority),
  (select (payload->>'runId')::uuid from research_begin),
  (select (payload->>'leaseToken')::uuid from research_begin),
  (select (payload->>'fenceToken')::bigint from research_begin),
  1, 'gemini', 'gemini-3.1-pro-preview', 'deep', 'succeeded', 'tool_calls',
  20, 5, 100, repeat('b', 64), repeat('c', 64), null, now(), now()
);

create temp table research_before as
select
  run.input_tokens run_input_tokens,
  run.output_tokens run_output_tokens,
  run.estimated_cost_microusd run_cost,
  coalesce(sum(bucket.input_tokens), 0)::bigint bucket_input_tokens,
  coalesce(sum(bucket.output_tokens), 0)::bigint bucket_output_tokens,
  coalesce(sum(bucket.estimated_cost_microusd), 0)::bigint bucket_cost,
  coalesce(sum(bucket.provider_attempt_count), 0)::bigint provider_attempt_count,
  coalesce(sum(bucket.tool_call_count), 0)::bigint tool_call_count
from public.assistant_runs run
left join public.assistant_quota_buckets bucket
  on bucket.tenant_id = run.tenant_id
 and bucket.scope_id in (run.tenant_id, run.actor_user_id)
where run.id = (select (payload->>'runId')::uuid from research_begin)
group by run.input_tokens, run.output_tokens, run.estimated_cost_microusd;

select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_usage_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,1,%L,%L,%L,%L,%L,%L,%L,%L,2,512,false,true,null,%L,%L,%L,120,40,%L,3,12345,now(),now())',
  'a1201000-0000-4000-8000-000000000001',
  'a1201000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from research_authority),
  (select payload->>'runId' from research_begin),
  (select payload->>'leaseToken' from research_begin),
  (select payload->>'fenceToken' from research_begin), repeat('d', 64),
  'research_public_web', 'v1', 'public_research', 'allowed', 'succeeded',
  repeat('e', 64), repeat('f', 64), 'gemini', 'gemini-3.6-flash',
  'configured_estimate', 'google_search_query'),
  'real public research receipt records external usage atomically');

select is((select external_provider from public.assistant_tool_receipts
  where run_id = (select (payload->>'runId')::uuid from research_begin)),
  'gemini', 'receipt stores the external provider');
select is((select external_model from public.assistant_tool_receipts
  where run_id = (select (payload->>'runId')::uuid from research_begin)),
  'gemini-3.6-flash', 'receipt stores the external model');
select is((select external_input_tokens::text from public.assistant_tool_receipts
  where run_id = (select (payload->>'runId')::uuid from research_begin)),
  '120', 'receipt stores external input tokens');
select is((select external_cost_microusd::text from public.assistant_tool_receipts
  where run_id = (select (payload->>'runId')::uuid from research_begin)),
  '12345', 'receipt stores exact external cost');
select is((select (run.input_tokens - before.run_input_tokens)::text
  from public.assistant_runs run cross join research_before before
  where run.id = (select (payload->>'runId')::uuid from research_begin)),
  '120', 'run input usage increases exactly once');
select is((select (run.output_tokens - before.run_output_tokens)::text
  from public.assistant_runs run cross join research_before before
  where run.id = (select (payload->>'runId')::uuid from research_begin)),
  '40', 'run output usage increases exactly once');
select is((select (run.estimated_cost_microusd - before.run_cost)::text
  from public.assistant_runs run cross join research_before before
  where run.id = (select (payload->>'runId')::uuid from research_begin)),
  '12345', 'run external cost increases exactly once');
select is((select (sum(bucket.input_tokens) - before.bucket_input_tokens)::text
  from public.assistant_quota_buckets bucket cross join research_before before
  where bucket.tenant_id = 'a1201000-0000-4000-8000-000000000001'
    and bucket.scope_id in (
      'a1201000-0000-4000-8000-000000000001'::uuid,
      'a1201000-0000-4000-8000-000000000011'::uuid)
  group by before.bucket_input_tokens), '480',
  'four current quota buckets each receive external input usage');
select is((select (sum(bucket.estimated_cost_microusd) - before.bucket_cost)::text
  from public.assistant_quota_buckets bucket cross join research_before before
  where bucket.tenant_id = 'a1201000-0000-4000-8000-000000000001'
    and bucket.scope_id in (
      'a1201000-0000-4000-8000-000000000001'::uuid,
      'a1201000-0000-4000-8000-000000000011'::uuid)
  group by before.bucket_cost), '49380',
  'four current quota buckets each receive external cost');
select is((select (sum(bucket.provider_attempt_count)
    - before.provider_attempt_count)::text
  from public.assistant_quota_buckets bucket cross join research_before before
  where bucket.tenant_id = 'a1201000-0000-4000-8000-000000000001'
    and bucket.scope_id in (
      'a1201000-0000-4000-8000-000000000001'::uuid,
      'a1201000-0000-4000-8000-000000000011'::uuid)
  group by before.provider_attempt_count), '0',
  'external research does not create a synthetic provider attempt');
select is((select (sum(bucket.tool_call_count) - before.tool_call_count)::text
  from public.assistant_quota_buckets bucket cross join research_before before
  where bucket.tenant_id = 'a1201000-0000-4000-8000-000000000001'
    and bucket.scope_id in (
      'a1201000-0000-4000-8000-000000000001'::uuid,
      'a1201000-0000-4000-8000-000000000011'::uuid)
  group by before.tool_call_count), '4',
  'the originating tool call is counted once in each quota bucket');

select throws_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_usage_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,2,1,%L,%L,%L,%L,%L,%L,%L,%L,0,0,false,false,%L,%L,null,%L,0,0,%L,0,1,now(),now())',
  'a1201000-0000-4000-8000-000000000001',
  'a1201000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from research_authority),
  (select payload->>'runId' from research_begin),
  (select payload->>'leaseToken' from research_begin),
  (select payload->>'fenceToken' from research_begin), repeat('1', 64),
  'search_tasks', 'v1', 'read', 'allowed', 'failed', repeat('2', 64),
  repeat('3', 64), 'tool_source_unavailable', 'gemini',
  'configured_estimate', 'google_search_query'),
  '22023', 'Invalid external tool usage',
  'non-research tools cannot claim external provider usage');

-- Golden attested calls prove the production-exposed v2 accepts both rollout
-- shapes, caches exact replay and rejects hybrids before any mutation.
create temp table research_attestation_secret(secret_id uuid primary key);
insert into research_attestation_secret
select vault.create_secret(
  repeat('22', 32),
  'assistant_research_usage_test',
  'Transaction-local public research usage attestation key'
);
insert into assistant_runtime.attestation_keys(
  key_id, vault_secret_id, audience, not_before, expires_at
) select
  'research-usage-test', secret_id, 'supabase:projectref:assistant-runtime',
  now() - interval '1 minute', now() + interval '1 hour'
from research_attestation_secret;

create temp table research_signed_new(
  envelope text not null,
  body text not null,
  mac_hex text not null
);
with body as (
  select assistant_runtime.assistant_canonical_json_internal_v1(
    jsonb_build_object(
      'p_tenant_id', 'a1201000-0000-4000-8000-000000000001',
      'p_actor_user_id', 'a1201000-0000-4000-8000-000000000011',
      'p_authority_fingerprint', authority.payload->>'authorityFingerprint',
      'p_run_id', begin_run.payload->>'runId',
      'p_lease_token', begin_run.payload->>'leaseToken',
      'p_fence_token', (begin_run.payload->>'fenceToken')::bigint,
      'p_ordinal', 2,
      'p_provider_attempt_no', 1,
      'p_provider_call_hash', repeat('4', 64),
      'p_tool_name', 'research_public_web',
      'p_tool_version', 'v1',
      'p_risk', 'public_research',
      'p_policy_decision', 'allowed',
      'p_status', 'succeeded',
      'p_arguments_hash', repeat('5', 64),
      'p_output_hash', repeat('6', 64),
      'p_result_count', 1,
      'p_output_bytes', 256,
      'p_approval_used', false,
      'p_read_back_verified', true,
      'p_failure_code', null,
      'p_external_provider', 'gemini',
      'p_external_model', 'gemini-3.6-flash',
      'p_external_usage_state', 'configured_estimate',
      'p_external_input_tokens', 10,
      'p_external_output_tokens', 5,
      'p_external_meter', 'google_search_query',
      'p_external_meter_units', 1,
      'p_external_cost_microusd', 1000,
      'p_started_at', statement_timestamp(),
      'p_completed_at', statement_timestamp()
    )
  ) value, authority.payload authority_payload, begin_run.payload begin_payload
  from research_authority authority cross join research_begin begin_run
), envelope as (
  select concat_ws(E'\n',
    'VINABIKE-AI-ATTESTATION-V1',
    'kid=research-usage-test',
    'aud=supabase:projectref:assistant-runtime',
    'iss=ai-agent-gateway',
    'op=assistant_record_tool_receipt_v2',
    'nonce=a1201000-0000-4000-8000-000000000401',
    'iat=' || floor(extract(epoch from statement_timestamp()))::bigint,
    'exp=' || (floor(extract(epoch from statement_timestamp()))::bigint + 60),
    'sub=a1201000-0000-4000-8000-000000000011',
    'tenant=a1201000-0000-4000-8000-000000000001',
    'authority=' || (authority_payload->>'authorityFingerprint'),
    'run=' || (begin_payload->>'runId'),
    'lease=' || (begin_payload->>'leaseToken'),
    'fence=' || (begin_payload->>'fenceToken'),
    'body-bytes=' || octet_length(value)
  ) value, body.value body_value
  from body
)
insert into research_signed_new
select value, body_value, encode(extensions.hmac(
  convert_to(value, 'UTF8') || decode('00', 'hex') ||
    convert_to(body_value, 'UTF8'),
  decode(repeat('22', 32), 'hex'), 'sha256'
), 'hex')
from envelope;

create temp table research_signed_response(response jsonb);
create temp table research_signed_before as
select run.input_tokens, run.output_tokens, run.estimated_cost_microusd,
  (select count(*) from public.assistant_tool_receipts receipt
    where receipt.run_id = run.id) receipt_count
from public.assistant_runs run
where run.id = (select (payload->>'runId')::uuid from research_begin);
grant select on research_signed_new, research_signed_before to authenticated;
grant insert, select on research_signed_response to authenticated;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1201000-0000-4000-8000-000000000011',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a1201000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into research_signed_response
select assistant_runtime.assistant_record_tool_receipt_v2(
  envelope, body, mac_hex
) from research_signed_new;
select is(
  (select assistant_runtime.assistant_record_tool_receipt_v2(
    envelope, body, mac_hex
  )::text from research_signed_new),
  (select response::text from research_signed_response),
  'exact signed new-shape replay returns the cached response'
);
reset role;
select is((select (run.input_tokens - before.input_tokens)::text
  from public.assistant_runs run cross join research_signed_before before
  where run.id = (select (payload->>'runId')::uuid from research_begin)),
  '10', 'signed new-shape replay does not double-count input usage');
select is((select (run.output_tokens - before.output_tokens)::text
  from public.assistant_runs run cross join research_signed_before before
  where run.id = (select (payload->>'runId')::uuid from research_begin)),
  '5', 'signed new-shape replay does not double-count output usage');
select is((select (run.estimated_cost_microusd
    - before.estimated_cost_microusd)::text
  from public.assistant_runs run cross join research_signed_before before
  where run.id = (select (payload->>'runId')::uuid from research_begin)),
  '1000', 'signed new-shape replay does not double-count cost');
select is((select (count(*) - before.receipt_count)::text
  from public.assistant_tool_receipts receipt
  cross join research_signed_before before
  where receipt.run_id = (select (payload->>'runId')::uuid from research_begin)
  group by before.receipt_count), '1',
  'signed new-shape replay creates exactly one receipt');

create temp table research_signed_legacy(
  envelope text not null,
  body text not null,
  mac_hex text not null
);
with body as (
  select assistant_runtime.assistant_canonical_json_internal_v1(
    jsonb_build_object(
      'p_tenant_id', 'a1201000-0000-4000-8000-000000000001',
      'p_actor_user_id', 'a1201000-0000-4000-8000-000000000011',
      'p_authority_fingerprint', authority.payload->>'authorityFingerprint',
      'p_run_id', begin_run.payload->>'runId',
      'p_lease_token', begin_run.payload->>'leaseToken',
      'p_fence_token', (begin_run.payload->>'fenceToken')::bigint,
      'p_ordinal', 3,
      'p_provider_attempt_no', 1,
      'p_provider_call_hash', repeat('7', 64),
      'p_tool_name', 'search_tasks',
      'p_tool_version', 'v1',
      'p_risk', 'read',
      'p_policy_decision', 'allowed',
      'p_status', 'succeeded',
      'p_arguments_hash', repeat('8', 64),
      'p_output_hash', repeat('9', 64),
      'p_result_count', 1,
      'p_output_bytes', 128,
      'p_approval_used', false,
      'p_read_back_verified', true,
      'p_failure_code', null,
      'p_started_at', statement_timestamp(),
      'p_completed_at', statement_timestamp()
    )
  ) value, authority.payload authority_payload, begin_run.payload begin_payload
  from research_authority authority cross join research_begin begin_run
), envelope as (
  select concat_ws(E'\n',
    'VINABIKE-AI-ATTESTATION-V1',
    'kid=research-usage-test',
    'aud=supabase:projectref:assistant-runtime',
    'iss=ai-agent-gateway',
    'op=assistant_record_tool_receipt_v2',
    'nonce=a1201000-0000-4000-8000-000000000402',
    'iat=' || floor(extract(epoch from statement_timestamp()))::bigint,
    'exp=' || (floor(extract(epoch from statement_timestamp()))::bigint + 60),
    'sub=a1201000-0000-4000-8000-000000000011',
    'tenant=a1201000-0000-4000-8000-000000000001',
    'authority=' || (authority_payload->>'authorityFingerprint'),
    'run=' || (begin_payload->>'runId'),
    'lease=' || (begin_payload->>'leaseToken'),
    'fence=' || (begin_payload->>'fenceToken'),
    'body-bytes=' || octet_length(value)
  ) value, body.value body_value
  from body
)
insert into research_signed_legacy
select value, body_value, encode(extensions.hmac(
  convert_to(value, 'UTF8') || decode('00', 'hex') ||
    convert_to(body_value, 'UTF8'),
  decode(repeat('22', 32), 'hex'), 'sha256'
), 'hex')
from envelope;
grant select on research_signed_legacy to authenticated;
set local role authenticated;
select lives_ok((select format(
  'select assistant_runtime.assistant_record_tool_receipt_v2(%L,%L,%L)',
  envelope, body, mac_hex
) from research_signed_legacy),
  'signed legacy exact body remains valid during DB-first rollout');
select throws_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v2(%L,%L,%L)',
  '', '{"p_external_provider":"gemini"}', repeat('0', 64)
), '22023', 'Invalid tool attestation body',
  'hybrid or partial body is rejected before attestation or mutation');
reset role;
select is((select external_provider from public.assistant_tool_receipts
  where provider_call_hash = repeat('7', 64)), null,
  'legacy receipt receives zero/null external usage defaults');

select * from finish();

rollback;
