begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select has_table(
  'public',
  'storefront_publication_targets',
  'storefront publication has a fixed target head'
);
select has_table(
  'public',
  'storefront_publication_requests',
  'storefront publication has a durable request ledger'
);
select has_table(
  'public',
  'storefront_publication_attempts',
  'storefront publication has a fenced attempt ledger'
);
select has_function(
  'public',
  'claim_storefront_publication_requests',
  array['text', 'integer', 'integer'],
  'dispatcher claims have one narrow service RPC'
);
select has_function(
  'public',
  'begin_storefront_publication_workflow',
  array['uuid', 'bigint', 'integer', 'text', 'text'],
  'workflow begin resolves the attempt from request identity'
);
select has_function(
  'public',
  'seal_storefront_publication_workflow',
  array['uuid', 'uuid', 'bigint', 'bigint', 'text', 'text'],
  'workflow seal has an exact fenced CAS RPC'
);
select has_function(
  'public',
  'complete_storefront_publication_workflow',
  array[
    'uuid',
    'uuid',
    'bigint',
    'bigint',
    'integer',
    'text',
    'text',
    'text',
    'text',
    'text',
    'bigint',
    'timestamp with time zone',
    'uuid',
    'bigint',
    'text',
    'text',
    'boolean',
    'boolean'
  ],
  'workflow completion owns success evidence and failure retry policy'
);

select ok(
  (
    select bool_and(class_row.relrowsecurity and class_row.relforcerowsecurity)
    from pg_class class_row
    join pg_namespace namespace_row
      on namespace_row.oid = class_row.relnamespace
    where namespace_row.nspname = 'public'
      and class_row.relname in (
        'storefront_publication_targets',
        'storefront_publication_requests',
        'storefront_publication_attempts'
      )
  ),
  'all storefront publication ledgers force RLS'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.claim_storefront_publication_requests(text,integer,integer)',
    'EXECUTE'
  ),
  'only the service integration can claim publication work'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.claim_storefront_publication_requests(text,integer,integer)',
    'EXECUTE'
  ),
  'authenticated editors cannot claim publication work'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_storefront_publication_status(uuid)',
    'EXECUTE'
  ),
  'authenticated editors can call the protected status RPC'
);
select ok(
  not has_table_privilege(
    'service_role',
    'public.storefront_publication_requests',
    'UPDATE'
  ),
  'service integrations cannot mutate the request table directly'
);
select is(
  (
    select count(*)::integer
    from pg_trigger trigger_row
    join pg_class table_row
      on table_row.oid = trigger_row.tgrelid
    join pg_namespace namespace_row
      on namespace_row.oid = table_row.relnamespace
    where namespace_row.nspname = 'public'
      and table_row.relname in (
        'website_settings',
        'website_pages',
        'website_blocks',
        'products',
        'product_categories',
        'product_brands',
        'product_url_aliases'
      )
      and trigger_row.tgname like 'trg_storefront_publication_%'
      and not trigger_row.tgisinternal
  ),
  21,
  'seven editorial owners have insert update and delete statement triggers'
);
select ok(
  (
    select bool_and((trigger_row.tgtype::integer & 1) = 0)
    from pg_trigger trigger_row
    where trigger_row.tgname like 'trg_storefront_publication_%'
      and not trigger_row.tgisinternal
  ),
  'editorial owner triggers are statement-level'
);
select ok(
  not exists (
    select 1
    from pg_trigger trigger_row
    join pg_class table_row
      on table_row.oid = trigger_row.tgrelid
    join pg_namespace namespace_row
      on namespace_row.oid = table_row.relnamespace
    where namespace_row.nspname = 'public'
      and table_row.relname = 'website_navigation'
      and trigger_row.tgname like 'trg_storefront_publication_%'
      and not trigger_row.tgisinternal
  ),
  'navigation is not a publication owner'
);
select ok(
  pg_get_functiondef(
    'public.claim_storefront_publication_requests(text,integer,integer)'
      ::regprocedure
  ) ilike '%for update of request skip locked%',
  'claims use SKIP LOCKED'
);

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  is_active
) values (
  '5443b130-cc28-45af-a420-cd500b288890',
  'Viñabike publication contract',
  'vinabike-publication-contract',
  true
)
on conflict (id) do update
set is_active = true;

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  is_active
) values (
  '70000000-0000-4000-8000-000000000002',
  'Other publication tenant',
  'other-publication-contract',
  true
)
on conflict (id) do update
set is_active = true;

delete from public.storefront_publication_targets
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

insert into public.storefront_publication_targets (
  id,
  tenant_id,
  target_key,
  expected_store_origin,
  expected_firebase_origin
) values (
  '70000000-0000-4000-8000-000000000001',
  '5443b130-cc28-45af-a420-cd500b288890',
  'vinabike-store',
  'https://vinabike.cl',
  'https://vinabike-store.web.app'
);

select ok(
  (
    select not target.dispatch_enabled
    from public.storefront_publication_targets target
    where target.id = '70000000-0000-4000-8000-000000000001'
  ),
  'the exact Viñabike target is disabled by default'
);
select ok(
  (
    select pg_get_constraintdef(constraint_row.oid)
      like '%5443b130-cc28-45af-a420-cd500b288890%'
      and pg_get_constraintdef(constraint_row.oid)
        like '%https://vinabike.cl%'
      and pg_get_constraintdef(constraint_row.oid)
        like '%https://vinabike-store.web.app%'
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.storefront_publication_targets'::regclass
      and constraint_row.conname =
        'storefront_publication_targets_initial_scope_check'
  ),
  'the target table constrains tenant and both exact origins'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
(
  '70000000-0000-4000-8000-000000000010',
  'authenticated',
  'authenticated',
  'publication-admin@example.invalid',
  '',
  clock_timestamp(),
  '{}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
),
(
  '70000000-0000-4000-8000-000000000011',
  'authenticated',
  'authenticated',
  'publication-cashier@example.invalid',
  '',
  clock_timestamp(),
  '{}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
),
(
  '70000000-0000-4000-8000-000000000012',
  'authenticated',
  'authenticated',
  'publication-cross-tenant@example.invalid',
  '',
  clock_timestamp(),
  '{}'::jsonb,
  '{}'::jsonb,
  clock_timestamp(),
  clock_timestamp()
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values
(
  '70000000-0000-4000-8000-000000000010',
  '5443b130-cc28-45af-a420-cd500b288890',
  'admin',
  '{}'::jsonb,
  true
),
(
  '70000000-0000-4000-8000-000000000011',
  '5443b130-cc28-45af-a420-cd500b288890',
  'cashier',
  '{}'::jsonb,
  true
),
(
  '70000000-0000-4000-8000-000000000012',
  '70000000-0000-4000-8000-000000000002',
  'admin',
  '{}'::jsonb,
  true
);

-- One two-row INSERT is one owner revision while dispatch is disabled.
insert into public.website_settings (
  id,
  tenant_id,
  key,
  value
) values
(
  '70000000-0000-4000-8000-000000000100',
  '5443b130-cc28-45af-a420-cd500b288890',
  'pgtap_storefront_publication_a',
  'a0'
),
(
  '70000000-0000-4000-8000-000000000101',
  '5443b130-cc28-45af-a420-cd500b288890',
  'pgtap_storefront_publication_b',
  'b0'
);

select is(
  (
    select target.desired_revision
    from public.storefront_publication_targets target
    where target.id = '70000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'a bulk owner insert advances one revision'
);
select is(
  (
    select count(*)::integer
    from public.storefront_publication_requests request
    where request.target_id = '70000000-0000-4000-8000-000000000001'
  ),
  0,
  'disabled publication tracks revisions without queueing'
);

update public.storefront_publication_targets
set dispatch_enabled = true
where id = '70000000-0000-4000-8000-000000000001';

-- One two-row UPDATE is also one revision and one queued request.
update public.website_settings
set value = value || '-enabled'
where id in (
  '70000000-0000-4000-8000-000000000100',
  '70000000-0000-4000-8000-000000000101'
);

select is(
  (
    select target.desired_revision
    from public.storefront_publication_targets target
    where target.id = '70000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'a bulk update advances one revision after activation'
);
select is(
  (
    select count(*)::integer
    from public.storefront_publication_requests request
    where request.target_id = '70000000-0000-4000-8000-000000000001'
      and request.state = 'queued'
  ),
  1,
  'the first enabled owner change creates one queued request'
);
select is(
  private.storefront_publication_owner_projection(
    'products',
    ('{"id":"70000000-0000-4000-8000-000000000200",'
      || '"tenant_id":"5443b130-cc28-45af-a420-cd500b288890",'
      || '"name":"Bike","stock_quantity":1,"updated_at":"2026-07-28"}')
      ::jsonb
  ),
  private.storefront_publication_owner_projection(
    'products',
    ('{"id":"70000000-0000-4000-8000-000000000200",'
      || '"tenant_id":"5443b130-cc28-45af-a420-cd500b288890",'
      || '"name":"Bike","stock_quantity":999,"updated_at":"2027-01-01"}')
      ::jsonb
  ),
  'stock and operational timestamps are excluded from product ownership'
);
select isnt(
  private.storefront_publication_owner_projection(
    'products',
    ('{"id":"70000000-0000-4000-8000-000000000200",'
      || '"tenant_id":"5443b130-cc28-45af-a420-cd500b288890",'
      || '"name":"Bike"}')::jsonb
  ),
  private.storefront_publication_owner_projection(
    'products',
    ('{"id":"70000000-0000-4000-8000-000000000200",'
      || '"tenant_id":"5443b130-cc28-45af-a420-cd500b288890",'
      || '"name":"Bike changed"}')::jsonb
  ),
  'editorial product values remain publication owners'
);

select set_config(
  'request.jwt.claims',
  '{"role":"anon"}',
  true
);
select throws_ok(
  $$
    select *
    from public.claim_storefront_publication_requests('forbidden-worker', 1, 90)
  $$,
  '42501',
  'storefront_publication_service_forbidden',
  'non-service callers cannot claim work'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second'
where target_id = '70000000-0000-4000-8000-000000000001'
  and state = 'queued';

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

create temporary table storefront_claim_one
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-a', 1, 90);

select is(
  (select count(*)::integer from storefront_claim_one),
  1,
  'one due request is claimed'
);
select is(
  (select claim_action from storefront_claim_one),
  'dispatch',
  'a fresh request has an explicit dispatch action'
);
select ok(
  (
    select lease_token is not null and lease_fence > 0
    from storefront_claim_one
  ),
  'a claim returns an opaque token and positive target fence'
);
select is(
  (
    select count(*)::integer
    from public.claim_storefront_publication_requests(
      'edge-worker-b',
      1,
      90
    )
  ),
  0,
  'an active request cannot be claimed twice'
);
select throws_ok(
  (
    select format(
      'select public.complete_storefront_publication_dispatch('
      || '%L::uuid,%L::uuid,%L,%L::uuid,%s,%L)',
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-a',
      '70000000-0000-4000-8000-000000000999',
      claim_row.lease_fence,
      'dispatched'
    )
    from storefront_claim_one claim_row
  ),
  'PT409',
  'storefront_publication_stale_lease',
  'a stale lease token cannot complete dispatch'
);

select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-a',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatch_unknown',
      null,
      'dispatch_timeout',
      'GitHub acknowledgement was not observed',
      300
    )->>'state'
    from storefront_claim_one claim_row
  ),
  'dispatch_unknown',
  'an ambiguous acknowledgement is preserved without redispatch'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second'
where id = (select request_id from storefront_claim_one);

create temporary table storefront_reconcile_one
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-r1', 1, 90);

select is(
  (select claim_action from storefront_reconcile_one),
  'reconcile',
  'an ambiguous request is claimed only for reconciliation'
);
select ok(
  (
    select reconcile_row.attempt_id = claim_row.attempt_id
      and reconcile_row.lease_fence = claim_row.lease_fence
      and reconcile_row.lease_token <> claim_row.lease_token
    from storefront_reconcile_one reconcile_row
    cross join storefront_claim_one claim_row
  ),
  'reconciliation rotates only the token and preserves attempt fence'
);
select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-r1',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatch_unknown',
      null,
      'dispatch_reconciliation_inconclusive',
      'No authoritative GitHub result yet',
      300
    )->>'state'
    from storefront_reconcile_one claim_row
  ),
  'dispatch_unknown',
  'inconclusive reconciliation stays unknown'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second'
where id = (select request_id from storefront_claim_one);

create temporary table storefront_reconcile_two
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-r2', 1, 90);

select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-r2',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatched',
      204
    )->>'state'
    from storefront_reconcile_two claim_row
  ),
  'dispatched',
  'an exact GitHub run reconciles as dispatched without a new attempt'
);

-- Changes while the first request is active create and coalesce one successor.
update public.website_settings
set value = value || '-successor-one'
where id in (
  '70000000-0000-4000-8000-000000000100',
  '70000000-0000-4000-8000-000000000101'
);
update public.website_settings
set value = value || '-successor-two'
where id in (
  '70000000-0000-4000-8000-000000000100',
  '70000000-0000-4000-8000-000000000101'
);

select is(
  (
    select target.desired_revision
    from public.storefront_publication_targets target
    where target.id = '70000000-0000-4000-8000-000000000001'
  ),
  4::bigint,
  'two bulk statements advance exactly two revisions'
);
select is(
  (
    select count(*)::integer
    from public.storefront_publication_requests request
    where request.target_id = '70000000-0000-4000-8000-000000000001'
      and request.state = 'queued'
  ),
  1,
  'an in-flight request has at most one queued successor'
);
select is(
  (
    select request.coalesced_count
    from public.storefront_publication_requests request
    where request.target_id = '70000000-0000-4000-8000-000000000001'
      and request.state = 'queued'
  ),
  1,
  'later changes coalesce into the existing successor'
);

select is(
  (
    select public.begin_storefront_publication_workflow(
      claim_row.request_id,
      100,
      1,
      repeat('a', 40),
      'refs/heads/main'
    )->>'reason'
    from storefront_claim_one claim_row
  ),
  'owner_revision_superseded',
  'begin refuses a dispatch whose editorial revision is stale'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second'
where target_id = '70000000-0000-4000-8000-000000000001'
  and state = 'queued';

create temporary table storefront_claim_two
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-c', 1, 90);

select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-c',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatched',
      204
    )->>'state'
    from storefront_claim_two claim_row
  ),
  'dispatched',
  'the successor dispatch is acknowledged'
);

create temporary table storefront_begin_two
on commit drop
as
select public.begin_storefront_publication_workflow(
  claim_row.request_id,
  200,
  1,
  repeat('b', 40),
  'refs/heads/main'
) as result
from storefront_claim_two claim_row;

select ok(
  (select (result->>'should_run')::boolean from storefront_begin_two),
  'the exact current successor binds to its GitHub run'
);
select ok(
  (
    select (public.begin_storefront_publication_workflow(
      claim_row.request_id,
      200,
      1,
      repeat('b', 40),
      'refs/heads/main'
    )->>'replay')::boolean
    from storefront_claim_two claim_row
  ),
  'workflow begin replays idempotently for the same run'
);
select is(
  (
    select public.begin_storefront_publication_workflow(
      claim_row.request_id,
      201,
      1,
      repeat('b', 40),
      'refs/heads/main'
    )->>'reason'
    from storefront_claim_two claim_row
  ),
  'request_already_bound',
  'a request cannot bind to a different GitHub run'
);
select throws_ok(
  (
    select format(
      'select public.seal_storefront_publication_workflow('
      || '%L::uuid,%L::uuid,%s,%s,%L,%L)',
      claim_row.request_id,
      claim_row.attempt_id,
      claim_row.lease_fence + 1,
      200,
      repeat('c', 64),
      repeat('d', 64)
    )
    from storefront_claim_two claim_row
  ),
  'PT409',
  'storefront_publication_stale_fence',
  'seal rejects a stale fence'
);
select ok(
  (
    select (
      public.seal_storefront_publication_workflow(
        claim_row.request_id,
        claim_row.attempt_id,
        claim_row.lease_fence,
        200,
        repeat('c', 64),
        repeat('d', 64)
      )->>'deploy'
    )::boolean
    from storefront_claim_two claim_row
  ),
  'seal succeeds only for the unchanged owner revision'
);

-- A post-seal owner change creates a successor but does not invalidate the
-- exact release already sealed for revision 4.
update public.website_settings
set value = value || '-post-seal'
where id in (
  '70000000-0000-4000-8000-000000000100',
  '70000000-0000-4000-8000-000000000101'
);

select is(
  (
    select public.complete_storefront_publication_workflow(
      claim_row.request_id,
      claim_row.attempt_id,
      claim_row.lease_fence,
      200,
      1,
      'succeeded',
      null,
      null,
      null,
      repeat('b', 40),
      200,
      clock_timestamp(),
      claim_row.request_id,
      claim_row.requested_revision,
      repeat('c', 64),
      repeat('e', 64),
      true,
      true
    )->>'state'
    from storefront_claim_two claim_row
  ),
  'succeeded',
  'exact release evidence completes the sealed revision'
);
select ok(
  (
    select attempt.primary_verified_at is not null
      and attempt.custom_verified_at is not null
      and attempt.primary_verified_at = attempt.custom_verified_at
    from public.storefront_publication_attempts attempt
    where attempt.id = (select attempt_id from storefront_claim_two)
  ),
  'the database clocks both live-origin verification receipts'
);
select is(
  (
    select target.last_published_revision
    from public.storefront_publication_targets target
    where target.id = '70000000-0000-4000-8000-000000000001'
  ),
  4::bigint,
  'success advances only the sealed revision while revision 5 remains queued'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second'
where target_id = '70000000-0000-4000-8000-000000000001'
  and state = 'queued';

create temporary table storefront_claim_three
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-d', 1, 90);

select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-d',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatched',
      204
    )->>'state'
    from storefront_claim_three claim_row
  ),
  'dispatched',
  'the next successor dispatch is acknowledged'
);
select ok(
  (
    select (
      public.begin_storefront_publication_workflow(
        claim_row.request_id,
        300,
        1,
        repeat('f', 40),
        'refs/heads/main'
      )->>'should_run'
    )::boolean
    from storefront_claim_three claim_row
  ),
  'the next successor binds before its seal CAS'
);

update public.website_settings
set value = value || '-pre-seal-cas-loss'
where id in (
  '70000000-0000-4000-8000-000000000100',
  '70000000-0000-4000-8000-000000000101'
);

select ok(
  (
    select not (
      public.seal_storefront_publication_workflow(
        claim_row.request_id,
        claim_row.attempt_id,
        claim_row.lease_fence,
        300,
        repeat('1', 64),
        repeat('2', 64)
      )->>'deploy'
    )::boolean
    from storefront_claim_three claim_row
  ),
  'seal CAS supersedes a run when owners changed before the seal'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second'
where target_id = '70000000-0000-4000-8000-000000000001'
  and state = 'queued';

create temporary table storefront_claim_four
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-e', 1, 90);

select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-e',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatched',
      204
    )->>'state'
    from storefront_claim_four claim_row
  ),
  'dispatched',
  'the retry-policy request dispatch is acknowledged'
);
select ok(
  (
    select (
      public.begin_storefront_publication_workflow(
        claim_row.request_id,
        400,
        1,
        repeat('3', 40),
        'refs/heads/main'
      )->>'should_run'
    )::boolean
    from storefront_claim_four claim_row
  ),
  'the retry-policy request binds to its first workflow attempt'
);

select is(
  (
    select public.complete_storefront_publication_workflow(
      claim_row.request_id,
      claim_row.attempt_id,
      claim_row.lease_fence,
      400,
      1,
      'failed',
      'workflow',
      'github_transient',
      'Temporary GitHub failure'
    )->>'state'
    from storefront_claim_four claim_row
  ),
  'queued',
  'a whitelisted transient workflow failure retries within budget'
);

update public.storefront_publication_requests
set available_at = clock_timestamp() - interval '1 second',
    max_attempts = 2
where id = (select request_id from storefront_claim_four);

create temporary table storefront_claim_five
on commit drop
as
select *
from public.claim_storefront_publication_requests('edge-worker-f', 1, 90);

select ok(
  (
    select second_claim.attempt_id <> first_claim.attempt_id
      and second_claim.lease_fence > first_claim.lease_fence
    from storefront_claim_five second_claim
    cross join storefront_claim_four first_claim
  ),
  'a retry receives a new attempt and a strictly newer fence'
);

select is(
  (
    select public.complete_storefront_publication_dispatch(
      claim_row.request_id,
      claim_row.attempt_id,
      'edge-worker-f',
      claim_row.lease_token,
      claim_row.lease_fence,
      'dispatched',
      204
    )->>'state'
    from storefront_claim_five claim_row
  ),
  'dispatched',
  'the second workflow attempt dispatch is acknowledged'
);
select ok(
  (
    select (
      public.begin_storefront_publication_workflow(
        claim_row.request_id,
        401,
        1,
        repeat('4', 40),
        'refs/heads/main'
      )->>'should_run'
    )::boolean
    from storefront_claim_five claim_row
  ),
  'the second workflow attempt binds to its exact run'
);

select is(
  (
    select public.complete_storefront_publication_workflow(
      claim_row.request_id,
      claim_row.attempt_id,
      claim_row.lease_fence,
      401,
      1,
      'failed',
      'workflow',
      'workflow_permanent',
      repeat('x', 3000)
    )->>'state'
    from storefront_claim_five claim_row
  ),
  'dead_letter',
  'an exhausted attempt budget moves the request to dead letter'
);
select is(
  (
    select char_length(request.error_message)
    from public.storefront_publication_requests request
    where request.id = (select request_id from storefront_claim_five)
  ),
  2000,
  'persisted workflow errors are bounded'
);

select set_config(
  'request.jwt.claim.sub',
  '70000000-0000-4000-8000-000000000010',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000010",'
    || '"role":"authenticated"}',
  true
);

create temporary table storefront_authorized_status
on commit drop
as
select public.get_storefront_publication_status(
  '5443b130-cc28-45af-a420-cd500b288890'
) as result;

select ok(
  (
    select (result->>'supported')::boolean
      and (result->>'configured')::boolean
      and result->>'request_state' = 'dead_letter'
      and (result->>'can_retry')::boolean
    from storefront_authorized_status
  ),
  'authorized status exposes a flat stable state and retry decision'
);
select ok(
  (
    select result->'last_success'->>'build_input_sha256' = repeat('d', 64)
      and result->'last_success'->>'owner_source_sha256' = repeat('c', 64)
      and result->'last_success'->>'release_manifest_sha256' = repeat('e', 64)
      and result->'last_success'->>'primary_verified_at' is not null
      and result->'last_success'->>'custom_verified_at' is not null
    from storefront_authorized_status
  ),
  'status retains build release hashes and both verification receipts'
);
select ok(
  (
    select result ? 'queue'
      and result ? 'active'
      and result ? 'last_success'
      and result ? 'latest_failure'
    from storefront_authorized_status
  ),
  'status preserves the detailed nested ledger'
);

select set_config(
  'request.jwt.claim.sub',
  '70000000-0000-4000-8000-000000000011',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000011",'
    || '"role":"authenticated"}',
  true
);
select throws_ok(
  $$
    select public.get_storefront_publication_status(
      '5443b130-cc28-45af-a420-cd500b288890'
    )
  $$,
  '42501',
  'storefront_publication_status_forbidden',
  'same-tenant users without settings permission cannot read status'
);

select set_config(
  'request.jwt.claim.sub',
  '70000000-0000-4000-8000-000000000012',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000012",'
    || '"role":"authenticated"}',
  true
);
select throws_ok(
  $$
    select public.get_storefront_publication_status(
      '5443b130-cc28-45af-a420-cd500b288890'
    )
  $$,
  '42501',
  'storefront_publication_status_forbidden',
  'cross-tenant settings admins cannot read Viñabike publication status'
);

select set_config(
  'request.jwt.claim.sub',
  '70000000-0000-4000-8000-000000000010',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000010",'
    || '"role":"authenticated"}',
  true
);

create temporary table storefront_retry_result
on commit drop
as
select public.retry_storefront_publication(
  '5443b130-cc28-45af-a420-cd500b288890',
  (select request_id from storefront_claim_five)
) as result;

select ok(
  (
    select (result->>'accepted')::boolean
      and (result->>'enqueued')::boolean
      and result->'status'->>'request_state' = 'queued'
      and not (result->'status'->>'can_retry')::boolean
    from storefront_retry_result
  ),
  'an authorized retry queues only the current server-owned revision'
);
select is(
  (
    select request.requested_revision
    from public.storefront_publication_requests request
    where request.id = (
      select (result->>'request_id')::uuid
      from storefront_retry_result
    )
  ),
  (
    select target.desired_revision
    from public.storefront_publication_targets target
    where target.id = '70000000-0000-4000-8000-000000000001'
  ),
  'manual retry cannot choose an arbitrary revision'
);

update public.storefront_publication_targets
set dispatch_enabled = false
where id = '70000000-0000-4000-8000-000000000001';

select is(
  private.invoke_storefront_publication_dispatcher(),
  null::bigint,
  'private cron invocation fails closed while the target is disabled'
);

select * from finish();
rollback;
