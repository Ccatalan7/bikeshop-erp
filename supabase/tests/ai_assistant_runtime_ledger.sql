begin;

select no_plan();

select has_schema('assistant_runtime', 'isolated runtime RPC schema exists');

select has_table('public', 'assistant_threads', 'thread ledger exists');
select has_table('public', 'assistant_messages', 'message ledger exists');
select has_table('public', 'assistant_runs', 'run ledger exists');
select has_table('public', 'assistant_provider_attempts', 'provider attempt ledger exists');
select has_table('public', 'assistant_tool_receipts', 'tool receipt ledger exists');
select has_table('public', 'assistant_quota_buckets', 'quota ledger exists');
select has_table('public', 'assistant_run_leases', 'fenced leases exist');
select has_table('assistant_runtime', 'attestation_keys',
  'runtime attestation key metadata exists');
select has_table('assistant_runtime', 'attestation_nonces',
  'single-use attestation receipt ledger exists');

select ok((select bool_and(class.relrowsecurity and class.relforcerowsecurity)
  from pg_class class join pg_namespace namespace on namespace.oid = class.relnamespace
  where namespace.nspname = 'public' and class.relname like 'assistant_%'
    and class.relkind = 'r'), 'all runtime ledger tables force RLS');

select ok((select bool_and(not has_table_privilege(role_name,
  format('public.%I', table_name), privilege))
  from unnest(array['authenticated','anon']) role_name
  cross join unnest(array[
    'assistant_threads','assistant_messages','assistant_runs',
    'assistant_provider_attempts','assistant_tool_receipts',
    'assistant_quota_buckets','assistant_run_leases'
  ]) table_name
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) privilege),
  'clients have no direct ledger privileges');

select has_function('public', 'assistant_begin_run_v1', array[
  'uuid','text','text','text','uuid','integer','integer','integer','text','integer'
], 'caller-bound begin/replay RPC exists');
select has_function('assistant_runtime', 'assistant_heartbeat_run_v2',
  array['text','text','text'], 'attested heartbeat RPC exists');
select has_function('assistant_runtime', 'assistant_record_provider_attempt_v2',
  array['text','text','text'], 'attested provider accounting RPC exists');
select has_function('assistant_runtime', 'assistant_record_tool_receipt_v2',
  array['text','text','text'], 'attested tool receipt RPC exists');
select has_function('assistant_runtime', 'assistant_complete_run_v2',
  array['text','text','text'], 'attested terminal RPC exists');
select has_function('assistant_runtime', 'assistant_purge_expired_runtime_v1',
  array['integer'], 'isolated bounded purge RPC exists');

select ok(has_schema_privilege('authenticated','assistant_runtime','USAGE'),
  'authenticated caller may resolve the attested RPC schema');
select is((select count(*)::text
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and has_function_privilege('authenticated', function.oid, 'EXECUTE')),
  '4', 'caller JWT receives exactly four attested mutator grants');
select ok(has_function_privilege('authenticated',
  'public.assistant_begin_run_v1(uuid,text,text,text,uuid,integer,integer,integer,text,integer)',
  'EXECUTE'), 'caller JWT alone admits or replays a run');
select ok(not has_function_privilege('authenticated',
  'assistant_runtime.assistant_purge_expired_runtime_v1(integer)','EXECUTE')
  and not has_function_privilege('service_role',
  'assistant_runtime.assistant_purge_expired_runtime_v1(integer)','EXECUTE'),
  'purge remains scheduler/owner-only rather than an API capability');
select ok((select bool_and(
    not has_function_privilege('authenticated', function.oid, 'EXECUTE'))
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where (namespace.nspname = 'public' and function.proname in (
      'assistant_current_authority_internal_v1',
      'assistant_server_authority_internal_v1',
      'assistant_run_snapshot_internal_v1',
      'assistant_assert_live_lease_internal_v1',
      'assistant_cards_valid_v1'
    )) or (namespace.nspname = 'assistant_runtime'
      and function.proname like '%_internal_v1')),
  'caller cannot execute assistant internals');
select ok(not has_table_privilege('authenticated',
  'assistant_runtime.attestation_keys','SELECT')
  and not has_table_privilege('authenticated',
  'assistant_runtime.attestation_nonces','SELECT')
  and not has_table_privilege('authenticated','vault.decrypted_secrets','SELECT'),
  'caller cannot read attestation metadata, receipts or Vault plaintext');
select ok((select bool_and(not has_function_privilege(
  'authenticated', function.oid, 'EXECUTE'))
  from pg_proc function join pg_namespace namespace on namespace.oid=function.pronamespace
  where namespace.nspname='assistant_runtime' and function.proname like '%_v1'),
  'typed v1 mutators and purge remain closed to caller JWTs');
select ok((select bool_and(function.prosecdef
  and coalesce(function.proconfig::text,'') like '%search_path=%')
  from pg_proc function join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and function.proname in (
      'assistant_heartbeat_run_v2','assistant_record_provider_attempt_v2',
      'assistant_record_tool_receipt_v2','assistant_complete_run_v2')),
  'every attested runtime RPC is security definer with fixed search_path');

-- The remaining ledger-domain regressions exercise the internal typed
-- mutators directly under a temporary transaction-only grant. The effective
-- ACL assertions above run first; separate attestation tests below cover the
-- only production-exposed v2 boundary.
grant execute on function assistant_runtime.assistant_heartbeat_run_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer
) to authenticated;
grant execute on function assistant_runtime.assistant_record_provider_attempt_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, text, text, text, text, text,
  bigint, bigint, bigint, text, text, text, timestamptz, timestamptz
) to authenticated;
grant execute on function assistant_runtime.assistant_record_tool_receipt_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, integer, text, text, text, text,
  text, text, text, text, integer, integer, boolean, boolean, text,
  timestamptz, timestamptz
) to authenticated;
grant execute on function assistant_runtime.assistant_complete_run_v1(
  uuid, uuid, text, uuid, uuid, bigint, text, text, jsonb, text
) to authenticated;

select is(public.assistant_cards_valid_v1(
  '[{"kind":"job","title":"Trabajo","destination":"workshop_jobs","chips":[]}]'),
  true, 'exact Flutter snake-case card is valid');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"job","title":"Trabajo","destination":"workshop_jobs","chips":[],"entityRef":{"kind":"workshopJob","id":"a1700000-0000-4000-8000-000000000101"}}]'),
  true, 'server-owned tenant-validated entity reference is valid');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"expense","title":"G-0001","destination":"expenses","chips":[],"entityRef":{"kind":"expense","id":"a1700000-0000-4000-8000-000000000102"}}]'),
  true, 'expense card and entity reference use the exact closed route pair');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"conversation","title":"WhatsApp","destination":"conversations","chips":[],"entityRef":{"kind":"conversation","id":"a1700000-0000-4000-8000-000000000103"}}]'),
  true, 'conversation card and entity reference use the exact closed route pair');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"expense","title":"G-0001","destination":"conversations","chips":[],"entityRef":{"kind":"conversation","id":"a1700000-0000-4000-8000-000000000102"}}]'),
  false, 'new card routes and entity kinds cannot be mixed');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"job","title":"Trabajo","destination":"workshop_jobs","chips":[],"entityRef":{"kind":"customer","id":"a1700000-0000-4000-8000-000000000101"}}]'),
  false, 'entity kind cannot be mixed with the card kind');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"job","title":"Trabajo","destination":"workshop_jobs","chips":[],"entityRef":{"kind":"workshopJob","id":"not-a-uuid"}}]'),
  false, 'entity reference requires a canonical UUID');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"task","title":"Trabajo","destination":"workshop_jobs","chips":[]}]'),
  false, 'kind and destination cannot be mixed');
select is(public.assistant_cards_valid_v1(
  '[{"kind":"job","title":"Trabajo","destination":"workshopJobs","chips":[]}]'),
  false, 'legacy camel-case destinations fail closed');
select is(public.assistant_cards_valid_v1(jsonb_build_array(jsonb_build_object(
  'kind','job','title',repeat('😀',41),'destination','workshop_jobs','chips','[]'::jsonb
))), false, 'card title bound uses exact UTF-8 bytes');

insert into public.tenants(id,shop_name,owner_email) values
('a1700000-0000-4000-8000-000000000001','AI runtime A','owner-a@example.invalid'),
('a1700000-0000-4000-8000-000000000002','AI runtime B','owner-b@example.invalid');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('a1700000-0000-4000-8000-000000000011','authenticated','authenticated',
 'staff-a@example.invalid','',now(),'{}','{}',now(),now()),
('a1700000-0000-4000-8000-000000000012','authenticated','authenticated',
 'staff-b@example.invalid','',now(),'{}','{}',now(),now());
insert into public.user_profiles(user_id,tenant_id,role,permissions) values
('a1700000-0000-4000-8000-000000000011',
 'a1700000-0000-4000-8000-000000000001','cashier','{}'),
('a1700000-0000-4000-8000-000000000012',
 'a1700000-0000-4000-8000-000000000002','admin','{}');

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
create temp table runtime_authority as select public.assistant_get_authority_v1() payload;
grant select on runtime_authority to authenticated;
select is((select payload->>'authorityTenantId' from runtime_authority),
  'a1700000-0000-4000-8000-000000000001','caller authority derives tenant');
select throws_ok($$select assistant_runtime.assistant_purge_expired_runtime_v1(1)$$,
  '42501','permission denied for function assistant_purge_expired_runtime_v1',
  'authenticated callers cannot mutate or purge the ledger');
create temp table runtime_begin as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000101',repeat('a',64),
  'Busca trabajos urgentes','fast',null,5,8,2048,'ai-agent-gateway-v1',110
) payload;
grant select on runtime_begin to authenticated;
select is((select payload->>'authorityTenantId' from runtime_begin),
  'a1700000-0000-4000-8000-000000000001',
  'caller begin derives its own tenant without authority parameters');
select throws_ok($$select public.assistant_begin_run_v1(
  gen_random_uuid(),repeat('a',64),repeat('😀',2049),'fast',null,5,8,2048,
  'ai-agent-gateway-v1',110)$$, '22023','Invalid assistant run request',
  'caller begin enforces the exact 8192-byte content bound');
reset role;

create temp table runtime_attestation_secret(secret_id uuid primary key);
insert into runtime_attestation_secret
select vault.create_secret(
  repeat('11', 32),
  'assistant_attestation_test',
  'Transaction-local pgTAP attestation key'
);
insert into assistant_runtime.attestation_keys (
  key_id, vault_secret_id, audience, not_before, expires_at
) select
  'runtime-test', secret_id, 'supabase:projectref:assistant-runtime',
  now() - interval '1 minute', now() + interval '1 hour'
from runtime_attestation_secret;

select is(
  assistant_runtime.assistant_canonical_json_internal_v1(
    '{"z":"Mañana 🚲","a":[1,true,null]}'::jsonb
  ),
  '{"a":[1,true,null],"z":"Mañana 🚲"}',
  'database canonical JSON preserves Unicode and recursively sorts ASCII keys'
);

create temp table runtime_attestation_fixture (
  envelope text not null,
  body text not null,
  mac_hex text not null
);
with body as (
  select assistant_runtime.assistant_canonical_json_internal_v1(
    jsonb_build_object(
      'p_tenant_id', 'a1700000-0000-4000-8000-000000000001',
      'p_actor_user_id', 'a1700000-0000-4000-8000-000000000011',
      'p_authority_fingerprint', payload->>'authorityFingerprint',
      'p_run_id', payload->>'runId',
      'p_lease_token', payload->>'leaseToken',
      'p_fence_token', (payload->>'fenceToken')::bigint,
      'p_lease_ttl_seconds', 110
    )
  ) value,
  payload
  from runtime_begin
), envelope as (
  select concat_ws(E'\n',
    'VINABIKE-AI-ATTESTATION-V1',
    'kid=runtime-test',
    'aud=supabase:projectref:assistant-runtime',
    'iss=ai-agent-gateway',
    'op=assistant_heartbeat_run_v2',
    'nonce=a1700000-0000-4000-8000-000000000401',
    'iat=' || floor(extract(epoch from statement_timestamp()))::bigint,
    'exp=' || (floor(extract(epoch from statement_timestamp()))::bigint + 60),
    'sub=a1700000-0000-4000-8000-000000000011',
    'tenant=a1700000-0000-4000-8000-000000000001',
    'authority=' || (payload->>'authorityFingerprint'),
    'run=' || (payload->>'runId'),
    'lease=' || (payload->>'leaseToken'),
    'fence=' || (payload->>'fenceToken'),
    'body-bytes=' || octet_length(value)
  ) value, body.value body_value
  from body
)
insert into runtime_attestation_fixture
select value, body_value, encode(extensions.hmac(
  convert_to(value, 'UTF8') || decode('00', 'hex') || convert_to(body_value, 'UTF8'),
  decode(repeat('11', 32), 'hex'), 'sha256'
), 'hex')
from envelope;
grant select on runtime_attestation_fixture to authenticated;
create temp table runtime_attestation_wrong_tenant as
select changed.envelope, changed.body, encode(extensions.hmac(
  convert_to(changed.envelope, 'UTF8') || decode('00','hex') ||
    convert_to(changed.body, 'UTF8'),
  decode(repeat('11',32),'hex'), 'sha256'
), 'hex') mac_hex
from runtime_attestation_fixture fixture
cross join lateral (
  select
    replace(replace(fixture.envelope,
      'nonce=a1700000-0000-4000-8000-000000000401',
      'nonce=a1700000-0000-4000-8000-000000000402'),
      'tenant=a1700000-0000-4000-8000-000000000001',
      'tenant=a1700000-0000-4000-8000-000000000002') envelope,
    replace(fixture.body,
      'a1700000-0000-4000-8000-000000000001',
      'a1700000-0000-4000-8000-000000000002') body
) changed;
grant select on runtime_attestation_wrong_tenant to authenticated;
create temp table runtime_attested_response(response jsonb);
grant insert, select on runtime_attested_response to authenticated;
create temp table runtime_attestation_retention(within_bound boolean);
grant insert, select on runtime_attestation_retention to authenticated;

select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
insert into runtime_attested_response
select assistant_runtime.assistant_heartbeat_run_v2(envelope, body, mac_hex)
from runtime_attestation_fixture;
reset role;
insert into runtime_attestation_retention
select expires_at > created_at
  and expires_at <= created_at + interval '15 minutes'
from assistant_runtime.attestation_nonces
where nonce = 'a1700000-0000-4000-8000-000000000401';
set local role authenticated;
select is(
  (select assistant_runtime.assistant_heartbeat_run_v2(envelope, body, mac_hex)::text
   from runtime_attestation_fixture),
  (select response::text from runtime_attested_response),
  'byte-identical nonce replay returns the exact cached mutation response'
);
select ok((select within_bound from runtime_attestation_retention),
  'exact-replay receipt is retained for at most fifteen minutes');
select throws_ok(
  (select format(
    'select assistant_runtime.assistant_heartbeat_run_v2(%L,%L,%L)',
    envelope, body, repeat('0', 64)
  ) from runtime_attestation_fixture),
  '42501', 'Runtime attestation nonce was already consumed',
  'same nonce with a different MAC cannot replay'
);
select throws_ok(
  (select format(
    'select assistant_runtime.assistant_heartbeat_run_v2(%L,%L,%L)',
    envelope, body, mac_hex
  ) from runtime_attestation_wrong_tenant),
  '42501', 'Runtime attestation caller mismatch',
  'valid HMAC with the wrong tenant binding is denied by caller authority'
);
reset role;

select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select throws_ok($$select count(*) from public.assistant_runs$$,
  '42501','permission denied for table assistant_runs',
  'caller JWT cannot query ledger tables');
select throws_ok($$select assistant_runtime.assistant_heartbeat_run_v1(
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select (payload->>'runId')::uuid from runtime_begin), gen_random_uuid(), 1, 110
)$$, '42501','Assistant run lease is stale or unavailable',
  'internal typed mutator rejects an unpredictable lease');
select throws_ok($$select assistant_runtime.assistant_heartbeat_run_v1(
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011', repeat('f',64),
  (select (payload->>'runId')::uuid from runtime_begin),
  (select (payload->>'leaseToken')::uuid from runtime_begin),
  (select (payload->>'fenceToken')::bigint from runtime_begin), 110
)$$, '42501','Runtime authority fingerprint is stale',
  'runtime authority is revalidated before lease or ledger mutation');
select throws_ok($$select assistant_runtime.assistant_heartbeat_run_v1(
  'a1700000-0000-4000-8000-000000000002',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select (payload->>'runId')::uuid from runtime_begin),
  (select (payload->>'leaseToken')::uuid from runtime_begin),
  (select (payload->>'fenceToken')::bigint from runtime_begin), 110
)$$, '42501','Runtime actor access is invalid',
  'cross-tenant runtime inputs fail authority validation before locks');
select is((select payload->>'runDisposition' from runtime_begin),'claimed',
  'server RPC atomically creates and claims a run');
select is((select payload->>'authorityFingerprint' from runtime_begin),
  (select payload->>'authorityFingerprint' from runtime_authority),
  'lease snapshot carries the revalidated authority fingerprint');
select is((select payload->>'nextProviderAttemptNo' from runtime_begin),'1',
  'provider ordinals start at one');
select is(jsonb_array_length((select payload->'canonicalMessages' from runtime_begin)),1,
  'begin returns canonical server-owned visible history');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select is(public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000101',repeat('a',64),
  'Busca trabajos urgentes','fast',null,5,8,2048,'ai-agent-gateway-v1',110
)->>'runDisposition','in_progress','live caller replay is explicitly in progress');
select throws_ok($$select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000101',repeat('b',64),
  'contenido distinto','fast',null,5,8,2048,'ai-agent-gateway-v1',110)$$,
  '22023','Client request id was already used with different content',
  'same id with a different request hash fails closed');
reset role;
select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
create temp table runtime_success_complete(payload jsonb);
grant insert, select on runtime_success_complete to authenticated;
set local role authenticated;
select lives_ok(format(
  'select assistant_runtime.assistant_heartbeat_run_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,110)',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_begin),(select payload->>'leaseToken' from runtime_begin),
  (select payload->>'fenceToken' from runtime_begin)), 'live fence heartbeats');
select lives_ok(format(
  'select assistant_runtime.assistant_record_provider_attempt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,%L,%L,%L,%L,%L,10,5,20,%L,%L,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_begin),(select payload->>'leaseToken' from runtime_begin),
  (select payload->>'fenceToken' from runtime_begin),'gemini','gemini-2.5-flash','fast',
  'succeeded','tool_calls',repeat('c',64),repeat('d',64)),
  'terminal provider usage is recorded without raw payload');
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,1,%L,%L,%L,%L,%L,%L,%L,%L,2,100,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_begin),(select payload->>'leaseToken' from runtime_begin),
  (select payload->>'fenceToken' from runtime_begin),repeat('e',64),'search_workshop_jobs',
  'v1','read','allowed','succeeded',repeat('f',64),repeat('1',64)),
  'hash-only tool evidence is recorded');
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,2,1,%L,%L,%L,%L,%L,%L,%L,%L,3,100,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_begin),(select payload->>'leaseToken' from runtime_begin),
  (select payload->>'fenceToken' from runtime_begin),repeat('2',64),'get_business_snapshot',
  'v1','read','allowed','succeeded',repeat('3',64),repeat('4',64)),
  'new fixed ERP snapshot is accepted only as a read receipt');
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,3,1,%L,%L,%L,%L,%L,%L,%L,%L,2,100,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_begin),(select payload->>'leaseToken' from runtime_begin),
  (select payload->>'fenceToken' from runtime_begin),repeat('5',64),'research_public_web',
  'v1','public_research','allowed','succeeded',repeat('6',64),repeat('7',64)),
  'isolated public research is accepted only with its exact risk class');
select throws_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,4,1,%L,%L,%L,%L,%L,%L,%L,%L,1,10,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_begin),(select payload->>'leaseToken' from runtime_begin),
  (select payload->>'fenceToken' from runtime_begin),repeat('8',64),'research_public_web',
  'v1','read','allowed','succeeded',repeat('9',64),repeat('a',64)),
  '22023','Invalid tool receipt counters',
  'public research cannot be mislabeled as an internal ERP read');
insert into runtime_success_complete
select assistant_runtime.assistant_complete_run_v1(
  'a1700000-0000-4000-8000-000000000001'::uuid,
  'a1700000-0000-4000-8000-000000000011'::uuid,
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select (payload->>'runId')::uuid from runtime_begin),
  (select (payload->>'leaseToken')::uuid from runtime_begin),
  (select (payload->>'fenceToken')::bigint from runtime_begin),
  'succeeded', 'Encontré dos trabajos.',
  '[{"kind":"job","title":"Trabajos urgentes","destination":"workshop_jobs","chips":[]}]'::jsonb,
  null
);
reset role;
select ok((select payload ? 'terminalErrorCode'
    and jsonb_typeof(payload->'terminalErrorCode') = 'null'
    from runtime_success_complete),
  'successful complete returns an explicit null terminalErrorCode');

-- The final already-incurred tool may cross 96 KiB. Its failed accounting
-- receipt is retained, but the ledger rejects every later effect.
select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
create temp table runtime_budget as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000107',repeat('b',64),
  'Prueba presupuesto de herramientas','fast',null,5,8,2048,
  'ai-agent-gateway-v1',110
) payload;
grant select on runtime_budget to authenticated;
reset role;
create temp table runtime_failed_complete(payload jsonb);
grant insert, select on runtime_failed_complete to authenticated;
select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select lives_ok(format(
  'select assistant_runtime.assistant_record_provider_attempt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,%L,%L,%L,%L,%L,0,0,0,%L,%L,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_budget),
  (select payload->>'leaseToken' from runtime_budget),
  (select payload->>'fenceToken' from runtime_budget),
  'gemini','gemini-2.5-flash','fast','succeeded','tool_calls',
  repeat('2',64),repeat('3',64)),
  'budget fixture has a successful tool-calling provider attempt');
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,1,%L,%L,%L,%L,%L,%L,%L,%L,1,40960,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_budget),
  (select payload->>'leaseToken' from runtime_budget),
  (select payload->>'fenceToken' from runtime_budget),repeat('4',64),
  'search_inventory','v1','read','allowed','succeeded',repeat('5',64),
  repeat('6',64)), 'first forty-KiB receipt fits the run budget');
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,2,1,%L,%L,%L,%L,%L,%L,%L,%L,1,40960,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_budget),
  (select payload->>'leaseToken' from runtime_budget),
  (select payload->>'fenceToken' from runtime_budget),repeat('7',64),
  'search_inventory','v1','read','allowed','succeeded',repeat('8',64),
  repeat('9',64)), 'second forty-KiB receipt fits the run budget');
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,3,1,%L,%L,%L,%L,%L,%L,%L,%L,1,40960,false,false,%L,now(),now())',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_budget),
  (select payload->>'leaseToken' from runtime_budget),
  (select payload->>'fenceToken' from runtime_budget),repeat('a',64),
  'search_inventory','v1','read','allowed','failed',repeat('b',64),
  repeat('c',64),'run_tool_output_budget_exhausted'),
  'the one receipt that crosses 96 KiB remains durable accounting');
select throws_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,4,1,%L,%L,%L,%L,%L,%L,%L,null,0,1,false,false,%L,now(),now())',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_budget),
  (select payload->>'leaseToken' from runtime_budget),
  (select payload->>'fenceToken' from runtime_budget),repeat('d',64),
  'search_inventory','v1','read','allowed','failed',repeat('e',64),
  'run_tool_output_budget_exhausted'),
  '22023','Invalid tool receipt counters',
  'no further tool receipt is accepted once the run exceeded 96 KiB');
insert into runtime_failed_complete
select assistant_runtime.assistant_complete_run_v1(
  'a1700000-0000-4000-8000-000000000001'::uuid,
  'a1700000-0000-4000-8000-000000000011'::uuid,
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select (payload->>'runId')::uuid from runtime_budget),
  (select (payload->>'leaseToken')::uuid from runtime_budget),
  (select (payload->>'fenceToken')::bigint from runtime_budget),
  'failed', null, '[]'::jsonb, 'agent_budget_exhausted'
);
reset role;
select is((select payload->>'terminalErrorCode' from runtime_failed_complete),
  'agent_budget_exhausted',
  'failed complete returns its stable terminalErrorCode');

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select is(public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000101',repeat('a',64),
  'Busca trabajos urgentes','fast',null,5,8,2048,'ai-agent-gateway-v1',110
)->>'runDisposition','terminal','completed request replays terminal state');
create temp table runtime_cancel as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000102',repeat('2',64),
  'Busca stock crítico','fast',null,5,8,2048,'ai-agent-gateway-v1',110
) payload;
grant select on runtime_cancel to authenticated;
reset role;

select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select lives_ok(format(
  'select assistant_runtime.assistant_record_provider_attempt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,%L,%L,%L,%L,%L,4,2,10,%L,%L,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_cancel),(select payload->>'leaseToken' from runtime_cancel),
  (select payload->>'fenceToken' from runtime_cancel),'gemini','gemini-2.5-flash','fast',
  'succeeded','tool_calls',repeat('3',64),repeat('4',64)),
  'provider work preceding cancellation is durably accounted');
reset role;

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select is(public.assistant_request_run_cancel_v1(
  (select (payload->>'runId')::uuid from runtime_cancel)
)->>'cancelRequested','true','caller requests cancellation during tool execution');
reset role;

create temp table runtime_cancel_complete(payload jsonb);
grant insert, select on runtime_cancel_complete to authenticated;
select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select lives_ok(format(
  'select assistant_runtime.assistant_record_tool_receipt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,1,1,%L,%L,%L,%L,%L,%L,%L,%L,1,64,false,true,null,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_cancel),(select payload->>'leaseToken' from runtime_cancel),
  (select payload->>'fenceToken' from runtime_cancel),repeat('5',64),'search_inventory',
  'v1','read','allowed','succeeded',repeat('6',64),repeat('7',64)),
  'already-incurred tool receipt survives a concurrent cancel');
insert into runtime_cancel_complete
select assistant_runtime.assistant_complete_run_v1(
  'a1700000-0000-4000-8000-000000000001'::uuid,
  'a1700000-0000-4000-8000-000000000011'::uuid,
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select (payload->>'runId')::uuid from runtime_cancel),
  (select (payload->>'leaseToken')::uuid from runtime_cancel),
  (select (payload->>'fenceToken')::bigint from runtime_cancel),
  'failed', null, '[]'::jsonb, 'provider_unavailable'
);
reset role;

select is((select payload->>'terminalErrorCode' from runtime_cancel_complete),
  'run_cancelled',
  'cancel-coerced complete returns the cancellation terminalErrorCode');

select is((select status from public.assistant_runs
  where id = (select (payload->>'runId')::uuid from runtime_cancel)),
  'cancelled', 'cancel race terminalizes the run as cancelled');
select is((select error_code from public.assistant_runs
  where id = (select (payload->>'runId')::uuid from runtime_cancel)),
  'run_cancelled', 'cancel race replaces the worker error with stable cancellation');
select is((select response_message_id::text from public.assistant_runs
  where id = (select (payload->>'runId')::uuid from runtime_cancel)),
  null::text, 'cancel race persists no assistant response message');

select is((select count(*)::text
  from jsonb_array_elements(public.assistant_run_snapshot_internal_v1(
    (select (payload->>'runId')::uuid from runtime_cancel), true,
    null, null, null
  )->'canonicalMessages') visible
  where visible->>'content' = 'Busca stock crítico'), '0',
  'failed or cancelled request messages do not poison later canonical history');
select ok(not exists (
  select 1
  from jsonb_array_elements(public.assistant_run_snapshot_internal_v1(
    (select (payload->>'runId')::uuid from runtime_cancel), true,
    null, null, null
  )->'canonicalMessages') visible
  where visible->>'role' not in ('user','assistant')
), 'canonical provider history contains only user and assistant roles');

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select is(public.assistant_delete_thread_v1(
  (select (payload->>'threadId')::uuid from runtime_cancel)
)->>'state','deleted','caller can erase its own terminal thread without a lease');
reset role;

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
create temp table runtime_reclaim as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000103',repeat('8',64),
  'Prueba de recuperación','fast',null,5,8,2048,'ai-agent-gateway-v1',110
) payload;
grant select on runtime_reclaim to authenticated;
reset role;
update public.assistant_run_leases set lease_expires_at = now() - interval '1 second'
where run_id = (select (payload->>'runId')::uuid from runtime_reclaim);

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
create temp table runtime_reclaimed as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000103',repeat('8',64),
  'Prueba de recuperación','fast',null,5,8,2048,'ai-agent-gateway-v1',110
) payload;
grant select on runtime_reclaimed to authenticated;
select is((select payload->>'runDisposition' from runtime_reclaimed),'claimed',
  'an expired lease is reclaimed through caller replay');
select is((select payload->>'fenceToken' from runtime_reclaimed),'2',
  'lease reclaim advances the fencing token');
reset role;

select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select throws_ok(format(
  'select assistant_runtime.assistant_heartbeat_run_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,110)',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_reclaim),(select payload->>'leaseToken' from runtime_reclaim),
  (select payload->>'fenceToken' from runtime_reclaim)),
  '42501','Assistant run lease is stale or unavailable',
  'a stale worker cannot heartbeat after fenced takeover');
select throws_ok(format(
  'select assistant_runtime.assistant_record_provider_attempt_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,2,%L,%L,%L,%L,null,0,0,0,null,null,%L,now(),now())',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_reclaimed),(select payload->>'leaseToken' from runtime_reclaimed),
  (select payload->>'fenceToken' from runtime_reclaimed),'gemini','gemini-2.5-flash','fast',
  'failed','invalid_attempt'),
  '22023','Invalid provider attempt counters','provider ordinals cannot skip');
select lives_ok(format(
  'select assistant_runtime.assistant_complete_run_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,%L,null,%L::jsonb,%L)',
  'a1700000-0000-4000-8000-000000000001','a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_reclaimed),(select payload->>'leaseToken' from runtime_reclaimed),
  (select payload->>'fenceToken' from runtime_reclaimed),'timed_out','[]','request_timeout'),
  'reclaimed run can terminalize only under its new fence');
reset role;

select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
create temp table runtime_live_one as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000104',repeat('9',64),
  'Concurrencia uno','fast',null,5,8,2048,'ai-agent-gateway-v1',110
) payload;
create temp table runtime_live_two as select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000105',repeat('a',64),
  'Concurrencia dos','fast',null,5,8,2048,'ai-agent-gateway-v1',110
) payload;
select throws_ok($$select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000106',repeat('b',64),
  'Concurrencia tres','fast',null,5,8,2048,'ai-agent-gateway-v1',110)$$,
  'P0001','Assistant user concurrency limit reached',
  'two live leases are the hard per-user concurrency cap');
reset role;
update public.user_profiles set permissions = '{"access_accounting":true}'::jsonb
where user_id = 'a1700000-0000-4000-8000-000000000011';
select set_config('request.jwt.claims','{"sub":"a1700000-0000-4000-8000-000000000011","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select throws_ok(format(
  'select assistant_runtime.assistant_heartbeat_run_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L::uuid,%s,110)',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011',
  (select payload->>'authorityFingerprint' from runtime_authority),
  (select payload->>'runId' from runtime_live_one),
  (select payload->>'leaseToken' from runtime_live_one),
  (select payload->>'fenceToken' from runtime_live_one)),
  '42501','Runtime authority fingerprint is stale',
  'permission changes invalidate an already-issued runtime authority snapshot');
reset role;
update public.user_profiles set permissions = '{}'::jsonb
where user_id = 'a1700000-0000-4000-8000-000000000011';
update public.assistant_run_leases set lease_expires_at = now() - interval '1 second'
where run_id = (select (payload->>'runId')::uuid from runtime_live_one);
delete from public.assistant_run_leases
where run_id = (select (payload->>'runId')::uuid from runtime_live_two);
select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select lives_ok(format('select public.assistant_delete_thread_v1(%L::uuid)',
  (select payload->>'threadId' from runtime_live_one)),
  'deleting a thread terminalizes its run even when the lease is expired');
select lives_ok(format('select public.assistant_delete_thread_v1(%L::uuid)',
  (select payload->>'threadId' from runtime_live_two)),
  'deleting a thread terminalizes its run even when the lease is missing');
reset role;

insert into auth.users (
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('a1700000-0000-4000-8000-000000000021','authenticated','authenticated',
   'runtime-tenant-1@example.invalid','',now(),'{}','{}',now(),now()),
  ('a1700000-0000-4000-8000-000000000022','authenticated','authenticated',
   'runtime-tenant-2@example.invalid','',now(),'{}','{}',now(),now()),
  ('a1700000-0000-4000-8000-000000000023','authenticated','authenticated',
   'runtime-tenant-3@example.invalid','',now(),'{}','{}',now(),now()),
  ('a1700000-0000-4000-8000-000000000024','authenticated','authenticated',
   'runtime-tenant-4@example.invalid','',now(),'{}','{}',now(),now()),
  ('a1700000-0000-4000-8000-000000000025','authenticated','authenticated',
   'runtime-tenant-5@example.invalid','',now(),'{}','{}',now(),now());
insert into public.user_profiles (user_id,tenant_id,role,permissions)
select actor_id,'a1700000-0000-4000-8000-000000000001','cashier','{}'::jsonb
from unnest(array[
  'a1700000-0000-4000-8000-000000000021'::uuid,
  'a1700000-0000-4000-8000-000000000022'::uuid,
  'a1700000-0000-4000-8000-000000000023'::uuid,
  'a1700000-0000-4000-8000-000000000024'::uuid,
  'a1700000-0000-4000-8000-000000000025'::uuid
]) as actor(actor_id);
create temp table runtime_tenant_live_threads(thread_id uuid primary key);
grant insert,select on runtime_tenant_live_threads to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"a1700000-0000-4000-8000-000000000021","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000021',true);
insert into runtime_tenant_live_threads select (
  public.assistant_begin_run_v1('a1700000-0000-4000-8000-000000000201',
    repeat('1',64),'Tenant uno','fast',null,5,8,2048,'ai-agent-gateway-v1',110)
  ->>'threadId')::uuid;
select set_config('request.jwt.claims',
  '{"sub":"a1700000-0000-4000-8000-000000000022","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000022',true);
insert into runtime_tenant_live_threads select (
  public.assistant_begin_run_v1('a1700000-0000-4000-8000-000000000202',
    repeat('2',64),'Tenant dos','fast',null,5,8,2048,'ai-agent-gateway-v1',110)
  ->>'threadId')::uuid;
select set_config('request.jwt.claims',
  '{"sub":"a1700000-0000-4000-8000-000000000023","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000023',true);
insert into runtime_tenant_live_threads select (
  public.assistant_begin_run_v1('a1700000-0000-4000-8000-000000000203',
    repeat('3',64),'Tenant tres','fast',null,5,8,2048,'ai-agent-gateway-v1',110)
  ->>'threadId')::uuid;
select set_config('request.jwt.claims',
  '{"sub":"a1700000-0000-4000-8000-000000000024","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000024',true);
insert into runtime_tenant_live_threads select (
  public.assistant_begin_run_v1('a1700000-0000-4000-8000-000000000204',
    repeat('4',64),'Tenant cuatro','fast',null,5,8,2048,'ai-agent-gateway-v1',110)
  ->>'threadId')::uuid;
select set_config('request.jwt.claims',
  '{"sub":"a1700000-0000-4000-8000-000000000025","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000025',true);
select throws_ok($$select public.assistant_begin_run_v1(
  'a1700000-0000-4000-8000-000000000205',repeat('5',64),
  'Tenant cinco','fast',null,5,8,2048,'ai-agent-gateway-v1',110)$$,
  'P0001','Assistant tenant concurrency limit reached',
  'four live leases are the hard per-tenant concurrency cap');
reset role;
delete from public.assistant_threads
where id in (select thread_id from runtime_tenant_live_threads);
delete from public.assistant_quota_buckets
where scope='user' and scope_id = any(array[
  'a1700000-0000-4000-8000-000000000021'::uuid,
  'a1700000-0000-4000-8000-000000000022'::uuid,
  'a1700000-0000-4000-8000-000000000023'::uuid,
  'a1700000-0000-4000-8000-000000000024'::uuid
]);

update public.assistant_quota_buckets set request_count = 10
where tenant_id = 'a1700000-0000-4000-8000-000000000001'
  and scope = 'user' and scope_id = 'a1700000-0000-4000-8000-000000000011'
  and period = 'five_minutes';
select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select throws_ok($$select public.assistant_begin_run_v1(
  gen_random_uuid(),repeat('c',64),'Cuota usuario','fast',null,5,8,2048,
  'ai-agent-gateway-v1',110)$$, 'P0001','Assistant request quota exceeded',
  'ten requests in five minutes are the hard per-user admission cap');
reset role;
update public.assistant_quota_buckets set request_count = case
  when scope = 'user' then 0 else 30 end
where tenant_id = 'a1700000-0000-4000-8000-000000000001'
  and period = 'five_minutes';
select set_config('request.jwt.claims',jsonb_build_object('sub',
  'a1700000-0000-4000-8000-000000000011','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','a1700000-0000-4000-8000-000000000011',true);
set local role authenticated;
select throws_ok($$select public.assistant_begin_run_v1(
  gen_random_uuid(),repeat('d',64),'Cuota tenant','fast',null,5,8,2048,
  'ai-agent-gateway-v1',110)$$, 'P0001','Assistant tenant quota exceeded',
  'thirty requests in five minutes are the hard tenant admission cap');
reset role;

insert into public.assistant_threads (
  id, tenant_id, actor_user_id, state, authority_role, authority_fingerprint,
  transcript_expires_at, ledger_expires_at
) values (
  'a1700000-0000-4000-8000-000000000901',
  'a1700000-0000-4000-8000-000000000001',
  'a1700000-0000-4000-8000-000000000011','deleted','cashier',
  (select payload->>'authorityFingerprint' from runtime_authority),
  now() - interval '2 days', now() - interval '1 day'
);
select lives_ok($$select assistant_runtime.assistant_purge_expired_runtime_v1(1000)$$,
  'bounded owner retention purge executes outside the runtime JWT');
select is((select count(*)::text from public.assistant_threads
  where id = 'a1700000-0000-4000-8000-000000000901'),'0',
  'ledger-expired empty thread is actually deleted');

select is((select count(*)::text from public.assistant_runs),'6',
  'replay, budget, cancel, reclaim and concurrency admissions create only intended runs');
select is((select count(*)::text from public.assistant_tool_receipts),'7',
  'normal, snapshot, research, budget-crossing and cancel-raced receipts persisted');
select is((select count(*)::text from public.assistant_messages message
  where message.thread_id = (select (payload->>'threadId')::uuid from runtime_cancel)),
  '0', 'thread deletion scrubs all visible messages even after lease removal');
select is((select count(*)::text from public.assistant_quota_buckets),'4',
  'one current five-minute and day bucket exists per user/tenant scope');
select ok((select bool_and(provider_attempt_budget = 12) from public.assistant_runs),
  'five tool rounds plus final/retry capacity receives twelve attempt slots');

select * from finish();
rollback;
