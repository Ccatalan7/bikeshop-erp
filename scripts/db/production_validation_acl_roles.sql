-- Roles referenced by production public/private-schema ACLs.
--
-- The validation manager creates only missing, local NOLOGIN compatibility
-- roles before restoring ACL statements. It never copies passwords, memberships
-- or privileged role attributes from production.
with acl_role_oids(role_oid) as (
  select exploded.grantee
  from pg_namespace namespace
  cross join lateral aclexplode(namespace.nspacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantor
  from pg_namespace namespace
  cross join lateral aclexplode(namespace.nspacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantee
  from pg_class relation
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(relation.relacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantor
  from pg_class relation
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(relation.relacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantee
  from pg_attribute attribute
  join pg_class relation on relation.oid = attribute.attrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(attribute.attacl) exploded
  where namespace.nspname in ('public', 'private')
    and attribute.attnum > 0
    and not attribute.attisdropped

  union

  select exploded.grantor
  from pg_attribute attribute
  join pg_class relation on relation.oid = attribute.attrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(attribute.attacl) exploded
  where namespace.nspname in ('public', 'private')
    and attribute.attnum > 0
    and not attribute.attisdropped

  union

  select exploded.grantee
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  cross join lateral aclexplode(procedure.proacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantor
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  cross join lateral aclexplode(procedure.proacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantee
  from pg_type type_row
  join pg_namespace namespace on namespace.oid = type_row.typnamespace
  cross join lateral aclexplode(type_row.typacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantor
  from pg_type type_row
  join pg_namespace namespace on namespace.oid = type_row.typnamespace
  cross join lateral aclexplode(type_row.typacl) exploded
  where namespace.nspname in ('public', 'private')

  union

  select exploded.grantee
  from pg_default_acl default_acl
  left join pg_namespace namespace on namespace.oid = default_acl.defaclnamespace
  cross join lateral aclexplode(default_acl.defaclacl) exploded
  where namespace.nspname in ('public', 'private')
     or default_acl.defaclnamespace = 0

  union

  select exploded.grantor
  from pg_default_acl default_acl
  left join pg_namespace namespace on namespace.oid = default_acl.defaclnamespace
  cross join lateral aclexplode(default_acl.defaclacl) exploded
  where namespace.nspname in ('public', 'private')
     or default_acl.defaclnamespace = 0

  union

  select default_acl.defaclrole
  from pg_default_acl default_acl
  left join pg_namespace namespace on namespace.oid = default_acl.defaclnamespace
  where namespace.nspname in ('public', 'private')
     or default_acl.defaclnamespace = 0

  union

  select unnest(policy.polroles)
  from pg_policy policy
  join pg_class relation on relation.oid = policy.polrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private')
)
select encode(convert_to(role_row.rolname, 'UTF8'), 'hex')
from pg_roles role_row
join acl_role_oids referenced on referenced.role_oid = role_row.oid
where referenced.role_oid <> 0
order by role_row.rolname;
