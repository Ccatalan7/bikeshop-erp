-- codex_test_runner is a database-diagnostic reader, not an application/API
-- identity. Historical default privileges accidentally made it login-capable
-- and granted it EXECUTE on public routines. PostgreSQL has no deny ACL, so
-- PUBLIC EXECUTE remains effective where it already exists; this migration
-- instead makes that inherited privilege unreachable by sealing the role,
-- removes every explicit/default routine grant, and preserves every other
-- grantee byte-for-byte. Supabase PostgreSQL 17 retains one platform-owned
-- administrative edge from this role to postgres; it is accepted only when
-- both SET and INHERIT are false, so it cannot assume or inherit the identity.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $migration$
declare
  v_diagnostic_role oid;
  v_membership record;
  v_routine record;
  v_default_acl record;
  v_routine_acl_before text;
  v_routine_acl_after text;
  v_default_acl_before text;
  v_default_acl_after text;
begin
  select role.oid
  into v_diagnostic_role
  from pg_roles role
  where role.rolname = 'codex_test_runner';

  -- Bootstrap/local databases do not necessarily install the production-only
  -- diagnostic role. In that case there is no identity to harden.
  if v_diagnostic_role is null then
    return;
  end if;

  select md5(coalesce(string_agg(
    concat_ws('|',
      procedure_row.oid::text,
      expanded_acl.grantee::text,
      expanded_acl.grantor::text,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable::text
    ),
    '||' order by
      procedure_row.oid,
      expanded_acl.grantee,
      expanded_acl.grantor,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable
  ), ''))
  into v_routine_acl_before
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
    and expanded_acl.grantee <> v_diagnostic_role;

  select md5(coalesce(string_agg(
    concat_ws('|',
      default_acl.oid::text,
      default_acl.defaclrole::text,
      coalesce(default_acl.defaclnamespace::text, ''),
      default_acl.defaclobjtype,
      expanded_acl.grantee::text,
      expanded_acl.grantor::text,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable::text
    ),
    '||' order by
      default_acl.oid,
      expanded_acl.grantee,
      expanded_acl.grantor,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable
  ), ''))
  into v_default_acl_before
  from pg_default_acl default_acl
  cross join lateral aclexplode(default_acl.defaclacl) expanded_acl
  where expanded_acl.grantee <> v_diagnostic_role;

  -- Remove every role inherited by the diagnostic identity. PostgreSQL 17
  -- records the original grantor, so use that exact grantor explicitly.
  for v_membership in
    select granted_role.rolname as granted_role_name,
           member_role.rolname as member_role_name,
           grantor_role.rolname as grantor_role_name
    from pg_auth_members membership
    join pg_roles granted_role on granted_role.oid = membership.roleid
    join pg_roles member_role on member_role.oid = membership.member
    join pg_roles grantor_role on grantor_role.oid = membership.grantor
    where membership.member = v_diagnostic_role
  loop
    execute format(
      'revoke %I from %I granted by %I restrict',
      v_membership.granted_role_name,
      v_membership.member_role_name,
      v_membership.grantor_role_name
    );
  end loop;

  -- Hosted postgres is deliberately not SUPERUSER. Do not issue redundant
  -- NOSUPERUSER/NOREPLICATION/NOBYPASSRLS clauses, which PostgreSQL reserves
  -- for a real superuser; the invariant below still fails closed if any such
  -- attribute were ever enabled.
  execute 'alter role codex_test_runner noinherit nologin';
  execute 'alter role codex_test_runner password null';

  -- RESTRICT is intentional: codex_test_runner must not have delegated grants,
  -- and a surprise dependency must abort rather than revoke another grantee.
  for v_routine in
    select distinct procedure_row.oid::regprocedure::text as signature
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
      and expanded_acl.grantee = v_diagnostic_role
  loop
    execute format(
      'revoke all privileges on routine %s from codex_test_runner restrict',
      v_routine.signature
    );
  end loop;

  -- Remove the accidental grant from every function default-ACL owner/schema
  -- that currently contains it. Usually this is postgres/public; enumerating
  -- the catalog also converges any hosted-environment drift safely.
  for v_default_acl in
    select distinct
      owner_role.rolname as owner_name,
      namespace_row.nspname as schema_name
    from pg_default_acl default_acl
    join pg_roles owner_role on owner_role.oid = default_acl.defaclrole
    left join pg_namespace namespace_row
      on namespace_row.oid = default_acl.defaclnamespace
    cross join lateral aclexplode(default_acl.defaclacl) expanded_acl
    where default_acl.defaclobjtype = 'f'
      and expanded_acl.grantee = v_diagnostic_role
  loop
    if v_default_acl.schema_name is null then
      execute format(
        'alter default privileges for role %I '
        || 'revoke execute on functions from codex_test_runner',
        v_default_acl.owner_name
      );
    else
      execute format(
        'alter default privileges for role %I in schema %I '
        || 'revoke execute on functions from codex_test_runner',
        v_default_acl.owner_name,
        v_default_acl.schema_name
      );
    end if;
  end loop;

  if exists (
    select 1
    from pg_auth_members membership
    join pg_roles member_role on member_role.oid = membership.member
    join pg_roles grantor_role on grantor_role.oid = membership.grantor
    where membership.member = v_diagnostic_role
       or (
         membership.roleid = v_diagnostic_role
         and not (
           member_role.rolname = 'postgres'
           and member_role.rolcreaterole
           and grantor_role.rolname = 'supabase_admin'
           and membership.admin_option
           and not membership.inherit_option
           and not membership.set_option
         )
       )
  ) then
    raise exception 'Diagnostic role still has an inheritable or assumable membership'
      using errcode = '42501';
  end if;

  if exists (
    select 1
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
      and expanded_acl.grantee = v_diagnostic_role
  ) then
    raise exception 'Diagnostic role still has an explicit public-routine ACL'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from pg_default_acl default_acl
    cross join lateral aclexplode(default_acl.defaclacl) expanded_acl
    where default_acl.defaclobjtype = 'f'
      and expanded_acl.grantee = v_diagnostic_role
  ) then
    raise exception 'Diagnostic role still has a default function ACL'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from pg_roles role
    where role.oid = v_diagnostic_role
      and (
        role.rolcanlogin
        or role.rolsuper
        or role.rolinherit
        or role.rolcreatedb
        or role.rolcreaterole
        or role.rolreplication
        or role.rolbypassrls
      )
  ) then
    raise exception 'Diagnostic role retains an unsafe role attribute'
      using errcode = '42501';
  end if;

  select md5(coalesce(string_agg(
    concat_ws('|',
      procedure_row.oid::text,
      expanded_acl.grantee::text,
      expanded_acl.grantor::text,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable::text
    ),
    '||' order by
      procedure_row.oid,
      expanded_acl.grantee,
      expanded_acl.grantor,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable
  ), ''))
  into v_routine_acl_after
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
    and expanded_acl.grantee <> v_diagnostic_role;

  select md5(coalesce(string_agg(
    concat_ws('|',
      default_acl.oid::text,
      default_acl.defaclrole::text,
      coalesce(default_acl.defaclnamespace::text, ''),
      default_acl.defaclobjtype,
      expanded_acl.grantee::text,
      expanded_acl.grantor::text,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable::text
    ),
    '||' order by
      default_acl.oid,
      expanded_acl.grantee,
      expanded_acl.grantor,
      expanded_acl.privilege_type,
      expanded_acl.is_grantable
  ), ''))
  into v_default_acl_after
  from pg_default_acl default_acl
  cross join lateral aclexplode(default_acl.defaclacl) expanded_acl
  where expanded_acl.grantee <> v_diagnostic_role;

  if v_routine_acl_after is distinct from v_routine_acl_before then
    raise exception 'A non-diagnostic public-routine ACL changed'
      using errcode = '42501';
  end if;

  if v_default_acl_after is distinct from v_default_acl_before then
    raise exception 'A non-diagnostic default ACL changed'
      using errcode = '42501';
  end if;
end;
$migration$;

commit;
