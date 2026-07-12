with manifest as (
  select
    'column'::text as component,
    format('%I.%I.%I', table_schema, table_name, column_name) as identity,
    md5(format('%s:%s:%s', udt_name, is_nullable, coalesce(column_default, ''))) as definition_hash
  from information_schema.columns column_row
  where table_schema = 'public'
    and not exists (
      select 1
      from pg_class relation
      join pg_namespace namespace on namespace.oid = relation.relnamespace
      join pg_depend dependency on dependency.classid = 'pg_class'::regclass
        and dependency.objid = relation.oid
        and dependency.deptype = 'e'
      where namespace.nspname = column_row.table_schema
        and relation.relname = column_row.table_name
    )

  union all

  select
    'constraint',
    format('%I.%I.%I', namespace.nspname, relation.relname, constraint_row.conname),
    md5(pg_get_constraintdef(constraint_row.oid, true))
  from pg_constraint constraint_row
  join pg_class relation on relation.oid = constraint_row.conrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and not exists (
      select 1 from pg_depend dependency
      where dependency.classid = 'pg_class'::regclass
        and dependency.objid = relation.oid
        and dependency.deptype = 'e'
    )

  union all

  select
    'index',
    format('%I.%I.%I', namespace.nspname, relation.relname, index_relation.relname),
    md5(pg_get_indexdef(index_row.indexrelid))
  from pg_index index_row
  join pg_class relation on relation.oid = index_row.indrelid
  join pg_class index_relation on index_relation.oid = index_row.indexrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and not exists (
      select 1 from pg_depend dependency
      where dependency.classid = 'pg_class'::regclass
        and dependency.objid in (relation.oid, index_row.indexrelid)
        and dependency.deptype = 'e'
    )

  union all

  select
    'function',
    format('%I.%I(%s)', namespace.nspname, procedure_row.proname, replace(pg_get_function_identity_arguments(procedure_row.oid), ',', ';')),
    md5(pg_get_functiondef(procedure_row.oid))
  from pg_proc procedure_row
  join pg_namespace namespace on namespace.oid = procedure_row.pronamespace
  where namespace.nspname = 'public'
    and procedure_row.prokind in ('f', 'p')
    and not exists (
      select 1 from pg_depend dependency
      where dependency.classid = 'pg_proc'::regclass
        and dependency.objid = procedure_row.oid
        and dependency.deptype = 'e'
    )

  union all

  select
    'view',
    format('%I.%I', view_row.schemaname, view_row.viewname),
    md5(view_row.definition)
  from pg_views view_row
  join pg_class relation on relation.relname = view_row.viewname
  join pg_namespace namespace on namespace.oid = relation.relnamespace
    and namespace.nspname = view_row.schemaname
  where view_row.schemaname = 'public'
    and not exists (
      select 1 from pg_depend dependency
      where dependency.classid = 'pg_class'::regclass
        and dependency.objid = relation.oid
        and dependency.deptype = 'e'
    )

  union all

  select
    'trigger',
    format('%I.%I.%I', namespace.nspname, relation.relname, trigger_row.tgname),
    md5(pg_get_triggerdef(trigger_row.oid, true))
  from pg_trigger trigger_row
  join pg_class relation on relation.oid = trigger_row.tgrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and not trigger_row.tgisinternal
)
select component, identity, definition_hash
from manifest
order by component, identity;
