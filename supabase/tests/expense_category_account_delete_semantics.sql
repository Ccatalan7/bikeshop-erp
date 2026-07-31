begin;

select plan(3);

insert into public.tenants (id, shop_name)
values (
  '7d280130-0000-4000-8000-000000000001',
  'Expense FK Test'
);

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category
)
values (
  '7d280130-0000-4000-8000-000000000002',
  '7d280130-0000-4000-8000-000000000001',
  '6299-TEST',
  'Cuenta eliminable',
  'expense',
  'operatingExpense'
);

insert into public.expense_categories (
  id,
  tenant_id,
  name,
  default_account_id
)
values (
  '7d280130-0000-4000-8000-000000000003',
  '7d280130-0000-4000-8000-000000000001',
  'Categoría de prueba',
  '7d280130-0000-4000-8000-000000000002'
);

delete from public.accounts
where id = '7d280130-0000-4000-8000-000000000002'
  and tenant_id = '7d280130-0000-4000-8000-000000000001';

select is(
  (
    select tenant_id
    from public.expense_categories
    where id = '7d280130-0000-4000-8000-000000000003'
  ),
  '7d280130-0000-4000-8000-000000000001'::uuid,
  'deleting the optional account preserves category tenant ownership'
);

select is(
  (
    select default_account_id
    from public.expense_categories
    where id = '7d280130-0000-4000-8000-000000000003'
  ),
  null::uuid,
  'deleting the optional account clears only default_account_id'
);

select is(
  (
    select array_agg(attribute.attname order by attribute.attname)
    from pg_constraint constraint_row
    cross join lateral unnest(constraint_row.confdelsetcols) column_number
    join pg_attribute attribute
      on attribute.attrelid = constraint_row.conrelid
     and attribute.attnum = column_number
    where constraint_row.conrelid =
        'public.expense_categories'::regclass
      and constraint_row.conname =
        'expense_categories_default_account_id_fkey'
  ),
  array['default_account_id']::name[],
  'the FK SET NULL action is explicitly limited to the optional account column'
);

select * from finish();
rollback;
