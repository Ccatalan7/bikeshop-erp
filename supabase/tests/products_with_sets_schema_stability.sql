begin;

select plan(4);

select has_column(
  'public',
  'products_with_sets',
  'website_featured',
  'products_with_sets exposes final website columns on the first schema application'
);

select has_column(
  'public',
  'products_with_sets',
  'whatsapp_catalog_sync_status',
  'products_with_sets exposes final WhatsApp columns on the first schema application'
);

select is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products_with_sets'
  ),
  (
    select count(*)::integer + 4
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
  ),
  'products_with_sets contains every product column plus four computed set columns'
);

select lives_ok(
  $$select * from public.products_with_sets limit 0$$,
  'products_with_sets remains queryable after its final canonical recreation'
);

select * from finish();
rollback;
