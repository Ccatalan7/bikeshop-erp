-- Read-only compatibility identity for the production-derived validation cache.
--
-- The caller forces default_transaction_read_only=on. This query deliberately
-- returns definitions and ACL state for public, private and assistant_runtime,
-- never application rows.
with catalog_entries(kind, identity, definition) as (
  select
    'database',
    current_database(),
    jsonb_build_object(
      'encoding', pg_encoding_to_char(database.encoding),
      'collate', database.datcollate,
      'ctype', database.datctype,
      'connection_limit', database.datconnlimit
    )::text
  from pg_database database
  where database.datname = current_database()

  union all

  select
    'schema',
    namespace.nspname,
    jsonb_build_object(
      'owner', pg_get_userbyid(namespace.nspowner),
      'acl', coalesce(namespace.nspacl::text, '')
    )::text
  from pg_namespace namespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'extension',
    extension.extname,
    jsonb_build_object(
      'version', extension.extversion,
      'schema', namespace.nspname,
      'relocatable', extension.extrelocatable,
      'config', coalesce(extension.extconfig::text, ''),
      'condition', coalesce(extension.extcondition::text, '')
    )::text
  from pg_extension extension
  join pg_namespace namespace on namespace.oid = extension.extnamespace

  union all

  select
    'relation',
    format('%I.%I', namespace.nspname, relation.relname),
    jsonb_build_object(
      'kind', relation.relkind,
      'persistence', relation.relpersistence,
      'owner', pg_get_userbyid(relation.relowner),
      'row_security', relation.relrowsecurity,
      'force_row_security', relation.relforcerowsecurity,
      'replica_identity', relation.relreplident,
      'options', coalesce(relation.reloptions::text, ''),
      'acl', coalesce(relation.relacl::text, ''),
      'view_definition',
        case
          when relation.relkind in ('v', 'm')
            then pg_get_viewdef(relation.oid, false)
          else ''
        end
    )::text
  from pg_class relation
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')
    and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')

  union all

  select
    'column',
    format(
      '%I.%I.%s',
      namespace.nspname,
      relation.relname,
      attribute.attnum
    ),
    jsonb_build_object(
      'name', attribute.attname,
      'type', format_type(attribute.atttypid, attribute.atttypmod),
      'not_null', attribute.attnotnull,
      'identity', attribute.attidentity,
      'generated', attribute.attgenerated,
      'storage', attribute.attstorage,
      'compression', attribute.attcompression,
      'statistics', attribute.attstattarget,
      'collation',
        case
          when attribute.attcollation = 0 then ''
          else attribute.attcollation::regcollation::text
        end,
      'default',
        coalesce(pg_get_expr(default_value.adbin, default_value.adrelid), '')
    )::text
  from pg_attribute attribute
  join pg_class relation on relation.oid = attribute.attrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  left join pg_attrdef default_value
    on default_value.adrelid = attribute.attrelid
   and default_value.adnum = attribute.attnum
  where namespace.nspname in ('public', 'private', 'assistant_runtime')
    and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
    and attribute.attnum > 0
    and not attribute.attisdropped

  union all

  select
    'constraint',
    format(
      '%I.%I.%I',
      namespace.nspname,
      relation.relname,
      constraint_row.conname
    ),
    jsonb_build_object(
      'type', constraint_row.contype,
      'definition', pg_get_constraintdef(constraint_row.oid, false),
      'deferrable', constraint_row.condeferrable,
      'deferred', constraint_row.condeferred,
      'validated', constraint_row.convalidated,
      'parent', constraint_row.conparentid::text
    )::text
  from pg_constraint constraint_row
  join pg_class relation on relation.oid = constraint_row.conrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'index',
    format(
      '%I.%I.%I',
      namespace.nspname,
      relation.relname,
      index_relation.relname
    ),
    jsonb_build_object(
      'definition', pg_get_indexdef(index_row.indexrelid, 0, false),
      'valid', index_row.indisvalid,
      'ready', index_row.indisready,
      'live', index_row.indislive,
      'replica_identity', index_row.indisreplident
    )::text
  from pg_index index_row
  join pg_class relation on relation.oid = index_row.indrelid
  join pg_class index_relation on index_relation.oid = index_row.indexrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'routine',
    format(
      '%I.%I(%s)',
      namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid)
    ),
    jsonb_build_object(
      'kind', procedure.prokind,
      'owner', pg_get_userbyid(procedure.proowner),
      'security_definer', procedure.prosecdef,
      'leakproof', procedure.proleakproof,
      'strict', procedure.proisstrict,
      'volatility', procedure.provolatile,
      'parallel', procedure.proparallel,
      'config', coalesce(procedure.proconfig::text, ''),
      'acl', coalesce(procedure.proacl::text, ''),
      'definition',
        case
          when procedure.prokind in ('f', 'p')
            then pg_get_functiondef(procedure.oid)
          else concat_ws(
            '|',
            pg_get_function_arguments(procedure.oid),
            pg_get_function_result(procedure.oid),
            procedure.prosrc
          )
        end
    )::text
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'trigger',
    format(
      '%I.%I.%I',
      namespace.nspname,
      relation.relname,
      trigger_row.tgname
    ),
    jsonb_build_object(
      'definition', pg_get_triggerdef(trigger_row.oid, false),
      'enabled', trigger_row.tgenabled
    )::text
  from pg_trigger trigger_row
  join pg_class relation on relation.oid = trigger_row.tgrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')
    and not trigger_row.tgisinternal

  union all

  select
    'policy',
    format(
      '%I.%I.%I',
      namespace.nspname,
      relation.relname,
      policy.polname
    ),
    jsonb_build_object(
      'permissive', policy.polpermissive,
      'command', policy.polcmd,
      'roles', policy.polroles::text,
      'using', coalesce(pg_get_expr(policy.polqual, policy.polrelid), ''),
      'check', coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '')
    )::text
  from pg_policy policy
  join pg_class relation on relation.oid = policy.polrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'rule',
    format(
      '%I.%I.%I',
      namespace.nspname,
      relation.relname,
      rewrite_rule.rulename
    ),
    pg_get_ruledef(rewrite_rule.oid, false)
  from pg_rewrite rewrite_rule
  join pg_class relation on relation.oid = rewrite_rule.ev_class
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')
    and rewrite_rule.rulename <> '_RETURN'

  union all

  select
    'type',
    format('%I.%I', namespace.nspname, type_row.typname),
    jsonb_build_object(
      'kind', type_row.typtype,
      'category', type_row.typcategory,
      'owner', pg_get_userbyid(type_row.typowner),
      'not_null', type_row.typnotnull,
      'default', coalesce(type_row.typdefault, ''),
      'acl', coalesce(type_row.typacl::text, '')
    )::text
  from pg_type type_row
  join pg_namespace namespace on namespace.oid = type_row.typnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')
    and type_row.typtype in ('b', 'c', 'd', 'e', 'r', 'm')

  union all

  select
    'enum',
    format(
      '%I.%I.%s',
      namespace.nspname,
      type_row.typname,
      enum_row.enumsortorder
    ),
    enum_row.enumlabel
  from pg_enum enum_row
  join pg_type type_row on type_row.oid = enum_row.enumtypid
  join pg_namespace namespace on namespace.oid = type_row.typnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'sequence',
    format('%I.%I', namespace.nspname, relation.relname),
    jsonb_build_object(
      'type', format_type(sequence_row.seqtypid, null),
      'start', sequence_row.seqstart,
      'increment', sequence_row.seqincrement,
      'maximum', sequence_row.seqmax,
      'minimum', sequence_row.seqmin,
      'cache', sequence_row.seqcache,
      'cycle', sequence_row.seqcycle
    )::text
  from pg_sequence sequence_row
  join pg_class relation on relation.oid = sequence_row.seqrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'default_acl',
    concat_ws(
      '.',
      pg_get_userbyid(default_acl.defaclrole),
      coalesce(namespace.nspname, '*'),
      default_acl.defaclobjtype
    ),
    default_acl.defaclacl::text
  from pg_default_acl default_acl
  left join pg_namespace namespace on namespace.oid = default_acl.defaclnamespace
  where namespace.nspname in ('public', 'private', 'assistant_runtime')
     or default_acl.defaclnamespace = 0

  union all

  select
    'publication_table',
    concat_ws(
      '.',
      publication_tables.pubname,
      publication_tables.schemaname,
      publication_tables.tablename
    ),
    coalesce(publication_tables.attnames::text, '')
  from pg_publication_tables publication_tables
  where publication_tables.schemaname in ('public', 'private', 'assistant_runtime')

  union all

  select
    'event_trigger',
    event_trigger.evtname,
    jsonb_build_object(
      'event', event_trigger.evtevent,
      'owner', pg_get_userbyid(event_trigger.evtowner),
      'function', event_trigger.evtfoid::regprocedure::text,
      'enabled', event_trigger.evtenabled,
      'tags', coalesce(event_trigger.evttags::text, '')
    )::text
  from pg_event_trigger event_trigger
),
canonical_catalog as (
  select md5(
    coalesce(
      string_agg(
        jsonb_build_array(kind, identity, definition)::text,
        E'\n'
        order by kind, identity, definition
      ),
      ''
    )
  ) as fingerprint
  from catalog_entries
),
migration_state as (
  select
    coalesce(max(version), 'none') as migration_head,
    md5(
      coalesce(
        string_agg(
          jsonb_build_array(
            version,
            coalesce(name, ''),
            coalesce(statements::text, '')
          )::text,
          E'\n'
          order by version, name
        ),
        ''
      )
    ) as history_fingerprint
  from supabase_migrations.schema_migrations
)
select
  current_setting('server_version_num'),
  current_setting('server_version'),
  migration_state.migration_head,
  migration_state.history_fingerprint,
  canonical_catalog.fingerprint
from migration_state
cross join canonical_catalog;
