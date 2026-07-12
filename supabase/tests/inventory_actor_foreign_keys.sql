begin;

select plan(6);

select is(
  (
    select confrelid::regclass::text
    from pg_constraint
    where conrelid = 'public.stock_movements'::regclass
      and conname = 'stock_movements_created_by_fkey'
  ),
  'auth.users',
  'stock movement actor references auth.users'
);

select is(
  (
    select confrelid::regclass::text
    from pg_constraint
    where conrelid = 'public.journal_entries'::regclass
      and conname = 'journal_entries_created_by_fkey'
  ),
  'auth.users',
  'journal actor references auth.users'
);

insert into public.tenants (id, shop_name)
values ('97000000-0000-4000-8000-000000000001', 'Inventory Actor FK Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '97000000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'inventory-actor@example.invalid', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);

select set_config('request.jwt.claim.sub', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '97000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000001',
  'Inventory Actor Product', 'ACTOR-FK-001', 1000, 500,
  'product', false, true, 1, 1, 0, 10
);

select lives_ok(
  $$
    insert into public.stock_movements (
      tenant_id, product_id, type, quantity, created_by
    )
    select
      '97000000-0000-4000-8000-000000000001',
      product.id,
      'IN',
      1,
      '97000000-0000-4000-8000-000000000099'
    from public.products product
    where product.id = '97000000-0000-4000-8000-000000000002'
  $$,
  'authenticated actor can be stamped on a stock movement'
);

select lives_ok(
  $$
    insert into public.journal_entries (
      tenant_id, entry_number, description, type, created_by
    ) values (
      '97000000-0000-4000-8000-000000000001',
      'JE-ACTOR-FK-001',
      'Inventory actor FK test',
      'adjustment',
      '97000000-0000-4000-8000-000000000099'
    )
  $$,
  'authenticated actor can be stamped on a journal entry'
);

select throws_ok(
  $$
    insert into public.journal_entries (
      tenant_id, entry_number, description, type, created_by
    ) values (
      '97000000-0000-4000-8000-000000000001',
      'JE-ACTOR-FK-INVALID',
      'Invalid actor FK test',
      'adjustment',
      '97000000-0000-4000-8000-000000000098'
    )
  $$,
  '23503',
  null,
  'unknown actor remains rejected'
);

select is(
  (select count(*)::integer from public.users_profiles),
  0,
  'legacy profile table is not required by inventory trace writes'
);

select * from finish();
rollback;
