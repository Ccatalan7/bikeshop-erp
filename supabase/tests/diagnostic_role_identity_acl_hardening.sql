begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(27);

select has_role('codex_test_runner', 'diagnostic role remains available for controlled read-only inspection');

select ok(not rolcanlogin, 'diagnostic role cannot log in')
from pg_roles where rolname = 'codex_test_runner';
select ok(not rolsuper, 'diagnostic role is not superuser')
from pg_roles where rolname = 'codex_test_runner';
select ok(not rolinherit, 'diagnostic role cannot inherit privileges')
from pg_roles where rolname = 'codex_test_runner';
select ok(not rolcreatedb, 'diagnostic role cannot create databases')
from pg_roles where rolname = 'codex_test_runner';
select ok(not rolcreaterole, 'diagnostic role cannot create roles')
from pg_roles where rolname = 'codex_test_runner';
select ok(not rolreplication, 'diagnostic role cannot replicate')
from pg_roles where rolname = 'codex_test_runner';
select ok(not rolbypassrls, 'diagnostic role cannot bypass RLS')
from pg_roles where rolname = 'codex_test_runner';

select ok(
  (select rolpassword is null from pg_authid where rolname = 'codex_test_runner'),
  'diagnostic role has no password verifier'
);

select is(
  (
    select count(*)::integer
    from pg_auth_members membership
    join pg_roles role on role.oid = membership.member
    where role.rolname = 'codex_test_runner'
  ),
  0,
  'diagnostic role inherits no role membership'
);
select is(
  (
    select count(*)::integer
    from pg_auth_members membership
    join pg_roles role on role.oid = membership.roleid
    where role.rolname = 'codex_test_runner'
  ),
  0,
  'no other role can assume the diagnostic role'
);

select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    join pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    join pg_roles grantee_role on grantee_role.oid = expanded_acl.grantee
    where namespace_row.nspname = 'public'
      and grantee_role.rolname = 'codex_test_runner'
  ),
  0,
  'diagnostic role has no explicit public-routine ACL'
);

select is(
  (
    select count(*)::integer
    from pg_default_acl default_acl
    cross join lateral aclexplode(default_acl.defaclacl) expanded_acl
    join pg_roles grantee_role on grantee_role.oid = expanded_acl.grantee
    where default_acl.defaclobjtype = 'f'
      and grantee_role.rolname = 'codex_test_runner'
  ),
  0,
  'future functions do not inherit a diagnostic-role grant'
);

select is(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where grantee = 'codex_test_runner'
      and privilege_type <> 'SELECT'
  ),
  0,
  'diagnostic role has no non-SELECT table grant'
);

select is(
  (
    select count(*)::integer
    from information_schema.role_usage_grants
    where grantee = 'codex_test_runner'
  ),
  0,
  'diagnostic role has no sequence or other USAGE grant'
);

select is(
  (
    select count(*)::integer
    from pg_class relation_row
    join pg_namespace namespace_row
      on namespace_row.oid = relation_row.relnamespace
    cross join lateral aclexplode(
      coalesce(
        relation_row.relacl,
        acldefault('S', relation_row.relowner)
      )
    ) expanded_acl
    join pg_roles grantee_role on grantee_role.oid = expanded_acl.grantee
    where relation_row.relkind = 'S'
      and grantee_role.rolname = 'codex_test_runner'
      and expanded_acl.privilege_type <> 'SELECT'
  ),
  0,
  'diagnostic role has no sequence mutation grant'
);

select is(
  (
    select count(*)::integer
    from pg_namespace namespace_row
    cross join lateral aclexplode(
      coalesce(
        namespace_row.nspacl,
        acldefault('n', namespace_row.nspowner)
      )
    ) expanded_acl
    join pg_roles grantee_role on grantee_role.oid = expanded_acl.grantee
    where grantee_role.rolname = 'codex_test_runner'
      and expanded_acl.privilege_type <> 'USAGE'
  ),
  0,
  'diagnostic role has no schema CREATE grant'
);

select cmp_ok(
  (
    select count(*)::integer
    from information_schema.role_table_grants
    where grantee = 'codex_test_runner'
      and table_schema = 'public'
      and privilege_type = 'SELECT'
  ),
  '>',
  0,
  'existing diagnostic SELECT grants remain available'
);

select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    join pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    where namespace_row.nspname = 'public'
      and has_function_privilege(
        'codex_test_runner', procedure_row.oid, 'EXECUTE'
      )
  ),
  (
    select count(*)::integer
    from pg_proc procedure_row
    join pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where namespace_row.nspname = 'public'
      and expanded_acl.grantee = 0
      and expanded_acl.privilege_type = 'EXECUTE'
  ),
  'effective EXECUTE is exactly the inaccessible privilege inherited from PUBLIC'
);

select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    join pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    where namespace_row.nspname = 'public'
      and procedure_row.prosecdef
      and has_function_privilege(
        'codex_test_runner', procedure_row.oid, 'EXECUTE'
      )
  ),
  (
    select count(*)::integer
    from pg_proc procedure_row
    join pg_namespace namespace_row
      on namespace_row.oid = procedure_row.pronamespace
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where namespace_row.nspname = 'public'
      and procedure_row.prosecdef
      and expanded_acl.grantee = 0
      and expanded_acl.privilege_type = 'EXECUTE'
  ),
  'effective SECURITY DEFINER EXECUTE is only inaccessible PUBLIC inheritance'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ),
  'authenticated employees retain the canonical product import command'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ),
  'service role retains the canonical product import command'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ),
  'anonymous callers cannot use the canonical product import command'
);
select ok(
  not has_function_privilege(
    'codex_test_runner',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ),
  'diagnostic role cannot use the canonical product import command'
);

-- The production-derived clone intentionally keeps CREATE on public away from
-- postgres. Grant it only inside this rolled-back test so the probe exercises
-- postgres' real function default ACL without leaving a schema permission.
grant create on schema public to postgres;
set local role postgres;
create function public._diagnostic_acl_future_function_probe()
returns integer
language sql
immutable
as 'select 1';
reset role;

select ok(
  not exists (
    select 1
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    join pg_roles grantee_role on grantee_role.oid = expanded_acl.grantee
    where procedure_row.oid =
      'public._diagnostic_acl_future_function_probe()'::regprocedure
      and grantee_role.rolname = 'codex_test_runner'
  ),
  'a future postgres-owned public function has no diagnostic-role ACL'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public._diagnostic_acl_future_function_probe()',
    'EXECUTE'
  ) and has_function_privilege(
    'service_role',
    'public._diagnostic_acl_future_function_probe()',
    'EXECUTE'
  ),
  'future-function grants for legitimate API roles remain unchanged'
);

select ok(
  has_function_privilege(
    'anon',
    'public._diagnostic_acl_future_function_probe()',
    'EXECUTE'
  ),
  'future-function anonymous grant remains unchanged'
);

select * from finish();

rollback;
