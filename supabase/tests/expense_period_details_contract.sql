begin;

select plan(11);

select has_function(
  'public',
  'get_expense_period_details',
  array['timestamp with time zone', 'timestamp with time zone', 'boolean'],
  'dashboard expense period drill-down function exists'
);

select ok(
  (
    select procedure.prosecdef
      and procedure.proconfig @> array['search_path=public']
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_expense_period_details'
      and pg_get_function_identity_arguments(procedure.oid)
        = 'p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_is_cash_flow boolean'
  ),
  'dashboard expense drill-down is security definer with a pinned search path'
);

select lives_ok(
  $$select * from public.get_expense_period_details(
    now() - interval '30 days',
    now(),
    false
  )$$,
  'dashboard expense drill-down executes safely without tenant claims'
);

select lives_ok(
  $$select * from public.get_expense_period_details(
    now() - interval '30 days',
    now(),
    true
  )$$,
  'dashboard cash-flow expense drill-down executes safely without tenant claims'
);

select ok(
  not has_function_privilege(
    'public',
    'public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ),
  'dashboard expense drill-down is executable only by authenticated application users'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'e1000000-0000-4000-8000-000000000001',
  'Expense Cash Detail Test',
  'America/Santiago'
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
)
values (
  'e1000000-0000-4000-8000-000000000002',
  'authenticated',
  'authenticated',
  'expense-cash-detail@example.invalid',
  '',
  now(),
  '{"account_type":"erp_staff"}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

insert into public.user_profiles (
  id,
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  'e1000000-0000-4000-8000-000000000003',
  'e1000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000001',
  'accountant',
  '{"access_accounting":true}'::jsonb,
  true
);

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category
)
values
  (
    'e1000000-0000-4000-8000-000000000004',
    'e1000000-0000-4000-8000-000000000001',
    '619998',
    'Gasto de prueba',
    'expense',
    'operatingExpense'
  ),
  (
    'e1000000-0000-4000-8000-000000000005',
    'e1000000-0000-4000-8000-000000000001',
    '1135',
    'Anticipos al Personal',
    'asset',
    'currentAsset'
  );

insert into public.employees (
  id,
  tenant_id,
  employee_number,
  first_name,
  last_name,
  job_title
)
values (
  'e1000000-0000-4000-8000-000000000006',
  'e1000000-0000-4000-8000-000000000001',
  'CASH-DETAIL-001',
  'Persona',
  'Prueba',
  'Operaciones'
);

insert into public.expenses (
  id,
  tenant_id,
  expense_number,
  issue_date,
  posting_status,
  payment_status,
  subtotal,
  total_amount,
  amount_paid,
  balance,
  paid_at
)
values
  (
    'e1000000-0000-4000-8000-000000000007',
    'e1000000-0000-4000-8000-000000000001',
    'GTO-CASH-SPLIT',
    '2026-08-01 12:00:00+00',
    'posted',
    'paid',
    100,
    100,
    100,
    0,
    '2026-08-20 12:00:00+00'
  ),
  (
    'e1000000-0000-4000-8000-000000000008',
    'e1000000-0000-4000-8000-000000000001',
    'GTO-CASH-LEGACY',
    '2026-08-01 12:00:00+00',
    'posted',
    'paid',
    30,
    30,
    30,
    0,
    '2026-08-12 12:00:00+00'
  );

insert into public.expense_lines (
  id,
  tenant_id,
  expense_id,
  line_index,
  account_id,
  account_code,
  account_name,
  description,
  subtotal,
  total
)
values
  (
    'e1000000-0000-4000-8000-000000000009',
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000007',
    0,
    'e1000000-0000-4000-8000-000000000004',
    '619998',
    'Gasto de prueba',
    'Pago dividido',
    100,
    100
  ),
  (
    'e1000000-0000-4000-8000-00000000000a',
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000008',
    0,
    'e1000000-0000-4000-8000-000000000004',
    '619998',
    'Gasto de prueba',
    'Pago heredado',
    30,
    30
  );

insert into public.expense_payments (
  id,
  tenant_id,
  expense_id,
  amount,
  payment_date
)
values
  (
    'e1000000-0000-4000-8000-00000000000b',
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000007',
    40,
    '2026-08-10 12:00:00+00'
  ),
  (
    'e1000000-0000-4000-8000-00000000000c',
    'e1000000-0000-4000-8000-000000000001',
    'e1000000-0000-4000-8000-000000000007',
    60,
    '2026-08-15 12:00:00+00'
  );

insert into public.employee_advances (
  id,
  tenant_id,
  employee_id,
  amount,
  paid_at,
  reference,
  status
)
values (
  'e1000000-0000-4000-8000-00000000000d',
  'e1000000-0000-4000-8000-000000000001',
  'e1000000-0000-4000-8000-000000000006',
  20,
  '2026-08-13 12:00:00+00',
  'ANT-CASH-DATE',
  'open'
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'e1000000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select is(
  (
    select count(*)::bigint
    from public.get_expense_period_details(
      '2026-08-01 00:00:00+00',
      '2026-09-01 00:00:00+00',
      true
    )
  ),
  4::bigint,
  'cash detail returns one row per payment, advance, or legacy fallback'
);

select results_eq(
  $$
    select amount, transaction_date
    from public.get_expense_period_details(
      '2026-08-01 00:00:00+00',
      '2026-09-01 00:00:00+00',
      true
    )
    where document_number = 'GTO-CASH-SPLIT'
    order by amount
  $$,
  $$ values
    (40::numeric, date '2026-08-10'),
    (60::numeric, date '2026-08-15')
  $$,
  'split expense uses each payment amount and transaction date'
);

select is(
  (
    select count(*)::bigint
    from public.get_expense_period_details(
      '2026-08-01 00:00:00+00',
      '2026-09-01 00:00:00+00',
      true
    )
    where document_number = 'GTO-CASH-SPLIT'
      and transaction_date = date '2026-08-20'
  ),
  0::bigint,
  'expense header settlement date cannot replace payment dates'
);

select results_eq(
  $$
    select amount, transaction_date, source_type
    from public.get_expense_period_details(
      '2026-08-01 00:00:00+00',
      '2026-09-01 00:00:00+00',
      true
    )
    where id = 'e1000000-0000-4000-8000-00000000000d'
  $$,
  $$ values (20::numeric, date '2026-08-13', 'employee_advance'::text) $$,
  'employee advance uses the date when cash was delivered'
);

select results_eq(
  $$
    select amount, transaction_date
    from public.get_expense_period_details(
      '2026-08-01 00:00:00+00',
      '2026-09-01 00:00:00+00',
      true
    )
    where document_number = 'GTO-CASH-LEGACY'
  $$,
  $$ values (30::numeric, date '2026-08-12') $$,
  'legacy paid expense remains as an explicit fallback transaction'
);

select is(
  (
    select sum(amount)
    from public.get_expense_period_details(
      '2026-08-01 00:00:00+00',
      '2026-09-01 00:00:00+00',
      true
    )
  ),
  150::numeric,
  'cash detail total equals the authoritative money ledgers'
);

reset role;

select * from finish();

rollback;
