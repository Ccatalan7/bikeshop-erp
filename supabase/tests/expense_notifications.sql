begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(14);

select has_function(
  'public',
  'create_expense_erp_notification',
  array[]::text[],
  'expense notification trigger function exists'
);

select function_returns(
  'public',
  'create_expense_erp_notification',
  array[]::text[],
  'trigger',
  'expense notification source is a trigger function'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.create_expense_erp_notification()'::regprocedure
  ),
  'expense notification function is security definer'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_expense_erp_notification()',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the trigger function directly'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_expense_erp_notification()',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke the trigger function directly'
);

select ok(
  exists (
    select 1
    from pg_trigger trigger_row
    join pg_proc function_row on function_row.oid = trigger_row.tgfoid
    where trigger_row.tgrelid = 'public.expenses'::regclass
      and trigger_row.tgname = 'trg_expense_erp_notification'
      and not trigger_row.tgisinternal
      and function_row.oid =
        'public.create_expense_erp_notification()'::regprocedure
      and pg_get_triggerdef(trigger_row.oid) like '%AFTER INSERT%'
  ),
  'expenses owns one after-insert notification trigger'
);

insert into public.tenants (id, shop_name)
values (
  '98600000-0000-4000-8000-000000000001',
  'Expense Notification Test'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '98600000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'expense-notification@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '98600000-0000-4000-8000-000000000001',
    'name', 'Expense Notification Fixture'
  ),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '98600000-0000-4000-8000-000000000099';

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98600000-0000-4000-8000-000000000099',
  '98600000-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98600000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98600000-0000-4000-8000-000000000099',
  true
);

insert into public.expenses (
  id,
  tenant_id,
  expense_number,
  supplier_name,
  supplier_rut,
  document_type,
  document_number,
  issue_date,
  posting_status,
  payment_status,
  subtotal,
  tax_amount,
  total_amount,
  amount_paid,
  balance,
  created_by,
  created_at
) values (
  '98600000-0000-4000-8000-000000000010',
  '98600000-0000-4000-8000-000000000001',
  'GTO-NOTIFY-001',
  'Proveedor de prueba',
  '76.000.000-0',
  'invoice',
  'F-100',
  '2026-07-24 15:00:00+00',
  'draft',
  'pending',
  10000,
  1900,
  11900,
  0,
  11900,
  '98600000-0000-4000-8000-000000000099',
  '2026-07-24 15:05:00+00'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where tenant_id = '98600000-0000-4000-8000-000000000001'
      and entity_type = 'expense'
      and entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  1,
  'one expense insert creates exactly one durable notification'
);

select is(
  (
    select type
    from public.erp_notifications
    where entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  'expense_recorded',
  'expense notification uses its canonical event type'
);

select is(
  (
    select route
    from public.erp_notifications
    where entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  '/accounting/expenses/98600000-0000-4000-8000-000000000010',
  'expense notification deep-links to the exact expense'
);

select ok(
  (
    select body like 'GTO-NOTIFY-001%Proveedor de prueba%11%900'
    from public.erp_notifications
    where entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  'expense activity identifies the document, supplier, and amount'
);

select is(
  (
    select (data->>'total_amount')::numeric
    from public.erp_notifications
    where entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  11900::numeric,
  'expense notification keeps the canonical total in structured data'
);

select is(
  (
    select (data->>'tax_amount')::numeric
    from public.erp_notifications
    where entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  1900::numeric,
  'expense notification keeps tax evidence in structured data'
);

select is(
  (
    select created_at
    from public.erp_notifications
    where entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  now(),
  'live expense notifications receive their own durable event timestamp'
);

update public.expenses
set notes = 'updated after notification'
where id = '98600000-0000-4000-8000-000000000010';

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where tenant_id = '98600000-0000-4000-8000-000000000001'
      and entity_type = 'expense'
      and entity_id = '98600000-0000-4000-8000-000000000010'
  ),
  1,
  'editing an expense does not manufacture a second creation event'
);

select * from finish();
rollback;
