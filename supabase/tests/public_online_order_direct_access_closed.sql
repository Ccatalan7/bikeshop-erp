begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(22);

select is(
  (
    select count(*)::integer
      from pg_policy
     where polrelid = 'public.online_orders'::regclass
       and polname = 'public_online_orders_anon_select'
  ),
  0,
  'legacy anonymous full-order SELECT policy is removed'
);
select is(
  (
    select count(*)::integer
      from pg_policy
     where polrelid = 'public.online_order_items'::regclass
       and polname = 'public_online_order_items_anon_select'
  ),
  0,
  'legacy anonymous order-line SELECT policy is removed'
);

select ok(
  not has_table_privilege('anon', 'public.online_orders', 'SELECT'),
  'anonymous clients have no direct order SELECT privilege'
);
select ok(
  not has_table_privilege('anon', 'public.online_order_items', 'SELECT'),
  'anonymous clients have no direct order-line SELECT privilege'
);
select ok(
  not has_table_privilege('anon', 'public.online_orders', 'INSERT')
    and not has_table_privilege('anon', 'public.online_orders', 'UPDATE')
    and not has_table_privilege('anon', 'public.online_orders', 'DELETE')
    and not has_table_privilege('anon', 'public.online_orders', 'TRUNCATE')
    and not has_table_privilege('anon', 'public.online_orders', 'REFERENCES')
    and not has_table_privilege('anon', 'public.online_orders', 'TRIGGER')
    and not has_table_privilege('anon', 'public.online_orders', 'MAINTAIN'),
  'anonymous clients retain no destructive or schema-adjacent order privilege'
);
select ok(
  not has_table_privilege('anon', 'public.online_order_items', 'INSERT')
    and not has_table_privilege('anon', 'public.online_order_items', 'UPDATE')
    and not has_table_privilege('anon', 'public.online_order_items', 'DELETE')
    and not has_table_privilege('anon', 'public.online_order_items', 'TRUNCATE')
    and not has_table_privilege('anon', 'public.online_order_items', 'REFERENCES')
    and not has_table_privilege('anon', 'public.online_order_items', 'TRIGGER')
    and not has_table_privilege('anon', 'public.online_order_items', 'MAINTAIN'),
  'anonymous clients retain no destructive or schema-adjacent line privilege'
);

select ok(
  has_table_privilege('authenticated', 'public.online_orders', 'SELECT'),
  'authenticated ERP/customer sessions retain RLS-governed order reads'
);
select ok(
  has_table_privilege('authenticated', 'public.online_order_items', 'SELECT'),
  'authenticated ERP/customer sessions retain RLS-governed order-line reads'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_orders', 'INSERT')
    and not has_table_privilege('authenticated', 'public.online_orders', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.online_orders', 'DELETE')
    and not has_table_privilege('authenticated', 'public.online_orders', 'TRUNCATE')
    and not has_table_privilege('authenticated', 'public.online_orders', 'REFERENCES')
    and not has_table_privilege('authenticated', 'public.online_orders', 'TRIGGER')
    and not has_table_privilege('authenticated', 'public.online_orders', 'MAINTAIN'),
  'authenticated order mutations cannot bypass audited RPCs'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_order_items', 'INSERT')
    and not has_table_privilege('authenticated', 'public.online_order_items', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.online_order_items', 'DELETE')
    and not has_table_privilege('authenticated', 'public.online_order_items', 'TRUNCATE')
    and not has_table_privilege('authenticated', 'public.online_order_items', 'REFERENCES')
    and not has_table_privilege('authenticated', 'public.online_order_items', 'TRIGGER')
    and not has_table_privilege('authenticated', 'public.online_order_items', 'MAINTAIN'),
  'authenticated order-line mutations cannot bypass audited RPCs'
);

select ok(
  has_table_privilege('service_role', 'public.online_orders', 'SELECT')
    and has_table_privilege('service_role', 'public.online_orders', 'INSERT')
    and has_table_privilege('service_role', 'public.online_orders', 'UPDATE')
    and has_table_privilege('service_role', 'public.online_orders', 'DELETE'),
  'service role retains the order DML needed by trusted Edge workflows'
);
select ok(
  has_table_privilege('service_role', 'public.online_order_items', 'SELECT')
    and has_table_privilege('service_role', 'public.online_order_items', 'INSERT')
    and has_table_privilege('service_role', 'public.online_order_items', 'UPDATE')
    and has_table_privilege('service_role', 'public.online_order_items', 'DELETE'),
  'service role retains the order-line DML needed by trusted Edge workflows'
);

select ok(
  has_function_privilege(
    'anon',
    'public.create_public_online_order_with_access(jsonb,jsonb)',
    'EXECUTE'
  ),
  'anonymous checkout remains available through its token-issuing RPC'
);
select ok(
  has_function_privilege(
    'anon',
    'public.get_public_online_order_by_access_token(text)',
    'EXECUTE'
  ),
  'anonymous confirmation remains available through the token reader'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_online_order(uuid,uuid)',
    'EXECUTE'
  ),
  'legacy UUID-only full-row reader remains inaccessible'
);

set local role anon;

select throws_ok(
  $$ select count(*) from public.online_orders $$,
  '42501',
  'permission denied for table online_orders',
  'PostgREST-equivalent anonymous direct order read is rejected'
);
select throws_ok(
  $$ select count(*) from public.online_order_items $$,
  '42501',
  'permission denied for table online_order_items',
  'PostgREST-equivalent anonymous direct order-line read is rejected'
);
select throws_ok(
  $$ truncate table public.online_orders $$,
  '42501',
  'permission denied for table online_orders',
  'anonymous clients cannot bypass RLS with order TRUNCATE'
);

reset role;
set local role authenticated;

select lives_ok(
  $$ select count(*) from public.online_orders $$,
  'authenticated order SELECT remains available under RLS'
);
select lives_ok(
  $$ select count(*) from public.online_order_items $$,
  'authenticated order-line SELECT remains available under RLS'
);
select throws_ok(
  $$ truncate table public.online_orders $$,
  '42501',
  'permission denied for table online_orders',
  'authenticated clients cannot bypass RLS with order TRUNCATE'
);
select throws_ok(
  $$ delete from public.online_order_items where false $$,
  '42501',
  'permission denied for table online_order_items',
  'authenticated clients cannot bypass lifecycle RPCs with line DELETE'
);

reset role;

select * from finish();

rollback;
