begin;

-- 20261030020000: the dashboard chart buckets cash instants by the shop's day
-- and month (`tenants.timezone`), not by the UTC day of the session.
select plan(6);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'f2000000-0000-4000-8000-000000000001',
  'Series Shop Day Test',
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
  'f2000000-0000-4000-8000-000000000002',
  'authenticated',
  'authenticated',
  'series-shop-day-accountant@example.invalid',
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
  'f2000000-0000-4000-8000-000000000003',
  'f2000000-0000-4000-8000-000000000002',
  'f2000000-0000-4000-8000-000000000001',
  'accountant',
  '{"access_accounting":true}'::jsonb,
  true
);

insert into public.customers (id, tenant_id, name)
values (
  'f2000000-0000-4000-8000-000000000004',
  'f2000000-0000-4000-8000-000000000001',
  'Cliente de prueba'
);

insert into public.sales_invoices (id, tenant_id, invoice_number, customer_id)
values (
  'f2000000-0000-4000-8000-000000000005',
  'f2000000-0000-4000-8000-000000000001',
  'F-SER-001',
  'f2000000-0000-4000-8000-000000000004'
);

insert into public.suppliers (id, tenant_id, name)
values (
  'f2000000-0000-4000-8000-000000000006',
  'f2000000-0000-4000-8000-000000000001',
  'Proveedor de prueba'
);

insert into public.purchase_invoices (id, tenant_id, invoice_number, supplier_id)
values (
  'f2000000-0000-4000-8000-000000000007',
  'f2000000-0000-4000-8000-000000000001',
  'C-SER-001',
  'f2000000-0000-4000-8000-000000000006'
);

insert into public.payment_methods (id, tenant_id, code, name, account_id)
values (
  'f2000000-0000-4000-8000-000000000008',
  'f2000000-0000-4000-8000-000000000001',
  'cash',
  'Efectivo',
  'f2000000-0000-4000-8000-0000000000aa'
);

insert into public.sales_payments (
  id,
  tenant_id,
  invoice_id,
  payment_method_id,
  amount,
  date
)
values
  -- 21:30 in Santiago on 2025-01-10 (00:30 UTC of the 11th). January is
  -- summer there too (UTC-3), and far from the months the monthly check reads.
  (
    'f2000000-0000-4000-8000-000000000009',
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000005',
    'f2000000-0000-4000-8000-000000000008',
    5000,
    '2025-01-11 00:30:00+00'
  ),
  -- The shop's midnight of the 11th belongs to the 11th.
  (
    'f2000000-0000-4000-8000-00000000000a',
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000005',
    'f2000000-0000-4000-8000-000000000008',
    7000,
    '2025-01-11 03:00:00+00'
  ),
  -- 22:00 in Santiago on the last day of the previous month: in UTC it is
  -- already the 1st of the current month.
  (
    'f2000000-0000-4000-8000-00000000000b',
    'f2000000-0000-4000-8000-000000000001',
    'f2000000-0000-4000-8000-000000000005',
    'f2000000-0000-4000-8000-000000000008',
    11000,
    (
      date_trunc('month', current_timestamp at time zone 'America/Santiago')
      - interval '2 hours'
    ) at time zone 'America/Santiago'
  );

-- 21:45 in Santiago on 2025-01-10 (00:45 UTC of the 11th).
insert into public.purchase_payments (
  id,
  tenant_id,
  invoice_id,
  payment_method_id,
  amount,
  date
)
values (
  'f2000000-0000-4000-8000-00000000000c',
  'f2000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000007',
  'f2000000-0000-4000-8000-000000000008',
  3000,
  '2025-01-11 00:45:00+00'
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"f2000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'f2000000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

-- The app sends the calendar day as an offset-less midnight.
select results_eq(
  $$
    select period_start, income, expense
    from public.get_income_expense_daily_timeseries(
      '2025-01-10 00:00:00+00',
      '2025-01-11 00:00:00+00',
      true
    )
    order by period_start
  $$,
  $$
    values
      (date '2025-01-10', 5000::numeric, 3000::numeric),
      (date '2025-01-11', 7000::numeric, 0::numeric)
  $$,
  'a cash payment at 21:30 or 21:45 in Santiago lands on its shop day, and the shop midnight starts the next one'
);

select is(
  (
    select count(*)::bigint
    from public.get_income_expense_daily_timeseries(
      '2025-01-10 00:00:00+00',
      '2025-01-11 00:00:00+00',
      true
    )
  ),
  2::bigint,
  'the daily windows still come from the calendar day the app sends'
);

select is(
  (
    select max(period_start)
    from public.get_income_expense_timeseries(2, true)
  ),
  date_trunc('month', current_timestamp at time zone 'America/Santiago')::date,
  'the current month is the shop month'
);

select is(
  (
    select income
    from public.get_income_expense_timeseries(2, true)
    where period_start = (
      date_trunc('month', current_timestamp at time zone 'America/Santiago')
      - interval '1 month'
    )::date
  ),
  11000::numeric,
  'a payment at 22:00 on the last evening of a month counts in that month'
);

select is(
  (
    select income
    from public.get_income_expense_timeseries(2, true)
    where period_start = date_trunc(
      'month',
      current_timestamp at time zone 'America/Santiago'
    )::date
  ),
  0::numeric,
  'the evening payment of the previous month stays out of the current month'
);

select is(
  (
    select period_end
    from public.get_income_expense_timeseries(2, true)
    where period_start = date_trunc(
      'month',
      current_timestamp at time zone 'America/Santiago'
    )::date
  ),
  (
    date_trunc('month', current_timestamp at time zone 'America/Santiago')
    + interval '1 month' - interval '1 day'
  )::date,
  'each month still ends on its last calendar day'
);

select * from finish();
rollback;
