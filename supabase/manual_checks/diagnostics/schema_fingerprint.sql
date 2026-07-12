with catalog_components as (
  select
    'columns'::text as component,
    format('%I.%I.%s:%I:%s:%s:%s', table_schema, table_name, ordinal_position, column_name, udt_name, is_nullable, coalesce(column_default, '')) as definition
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
    'constraints',
    format('%I.%I:%I:%s', namespace.nspname, relation.relname, constraint_row.conname, pg_get_constraintdef(constraint_row.oid, true))
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
    'indexes',
    format('%I.%I:%s', namespace.nspname, relation.relname, pg_get_indexdef(index_row.indexrelid))
  from pg_index index_row
  join pg_class relation on relation.oid = index_row.indrelid
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
    'functions',
    pg_get_functiondef(procedure_row.oid)
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
    'views',
    format('%I.%I:%s', schemaname, viewname, definition)
  from pg_views view_row
  join pg_class relation on relation.relname = view_row.viewname
  join pg_namespace namespace on namespace.oid = relation.relnamespace
    and namespace.nspname = view_row.schemaname
  where schemaname = 'public'
    and not exists (
      select 1 from pg_depend dependency
      where dependency.classid = 'pg_class'::regclass
        and dependency.objid = relation.oid
        and dependency.deptype = 'e'
    )

  union all

  select
    'triggers',
    format('%I.%I:%I:%s', namespace.nspname, relation.relname, trigger_row.tgname, pg_get_triggerdef(trigger_row.oid, true))
  from pg_trigger trigger_row
  join pg_class relation on relation.oid = trigger_row.tgrelid
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and not trigger_row.tgisinternal
    and not exists (
      select 1 from pg_depend dependency
      where dependency.classid = 'pg_trigger'::regclass
        and dependency.objid = trigger_row.oid
        and dependency.deptype = 'e'
    )
)
select
  component,
  count(*) as object_count,
  md5(string_agg(definition, E'\n' order by definition)) as fingerprint
from catalog_components
group by component
order by component;
