begin;

select plan(8);

select has_column(
  'public',
  'products_with_sets',
  'set_components',
  'products_with_sets preserves the legacy set-components projection'
);

select has_column(
  'public',
  'products_with_sets',
  'full_sets_available',
  'products_with_sets preserves calculated full-set availability'
);

select has_column(
  'public',
  'products_with_sets',
  'is_partial',
  'products_with_sets preserves partial-set state'
);

select has_column(
  'public',
  'products_with_sets',
  'parent_set_info',
  'products_with_sets preserves parent-set metadata'
);

select lives_ok(
  $$select * from public.products_with_sets limit 0$$,
  'products_with_sets remains queryable after in-place security hardening'
);

select ok(
  exists (
    select 1
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'products_with_sets'
      and coalesce(relation.reloptions, array[]::text[])
          @> array['security_invoker=true']::text[]
  ),
  'products_with_sets evaluates base-table RLS with caller privileges'
);

select ok(
  not has_table_privilege('anon', 'public.products_with_sets', 'SELECT'),
  'anonymous callers cannot read the internal set projection'
);

select ok(
  has_table_privilege('authenticated', 'public.products_with_sets', 'SELECT'),
  'authenticated ERP callers retain read access to the set projection'
);

select * from finish();
rollback;
