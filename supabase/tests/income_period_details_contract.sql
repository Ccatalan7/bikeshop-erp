begin;

select plan(12);

select has_function(
  'public',
  'get_income_period_details',
  array['timestamp with time zone', 'timestamp with time zone', 'boolean'],
  'dashboard income period drill-down function exists'
);

select ok(
  (
    select procedure.prosecdef
      and procedure.proconfig @> array['search_path=pg_catalog, public, pg_temp']
      and pg_get_function_result(procedure.oid) like
        '%payment_method_code text, payment_instrument text, settlement_provider text, occurred_at timestamp with time zone%'
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_income_period_details'
  ),
  'income drill-down is security definer, pins its search path and returns the payment method identity'
);

select ok(
  not has_function_privilege(
    'public',
    'public.get_income_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.get_income_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and not has_function_privilege(
    'service_role',
    'public.get_income_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.get_income_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ),
  'income drill-down is executable only by authenticated application users'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'f1000000-0000-4000-8000-000000000001',
  'Income Detail Test',
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
values
  (
    'f1000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'income-detail-accountant@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    'f1000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'income-detail-mechanic@example.invalid',
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
values
  (
    'f1000000-0000-4000-8000-000000000004',
    'f1000000-0000-4000-8000-000000000002',
    'f1000000-0000-4000-8000-000000000001',
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  ),
  (
    'f1000000-0000-4000-8000-000000000005',
    'f1000000-0000-4000-8000-000000000003',
    'f1000000-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    true
  );

insert into public.customers (id, tenant_id, name)
values (
  'f1000000-0000-4000-8000-000000000006',
  'f1000000-0000-4000-8000-000000000001',
  'Cliente de prueba'
);

insert into public.sales_invoices (id, tenant_id, invoice_number, customer_id)
values (
  'f1000000-0000-4000-8000-000000000007',
  'f1000000-0000-4000-8000-000000000001',
  'F-INC-001',
  'f1000000-0000-4000-8000-000000000006'
);

insert into public.payment_methods (
  id,
  tenant_id,
  code,
  name,
  account_id,
  payment_instrument,
  settlement_provider
)
values
  (
    'f1000000-0000-4000-8000-000000000008',
    'f1000000-0000-4000-8000-000000000001',
    'card_debit',
    'Tarjeta de débito',
    'f1000000-0000-4000-8000-0000000000aa',
    'debit',
    'transbank'
  ),
  (
    'f1000000-0000-4000-8000-000000000009',
    'f1000000-0000-4000-8000-000000000001',
    'cash',
    'Efectivo',
    'f1000000-0000-4000-8000-0000000000ab',
    'unknown',
    'none'
  );

insert into public.sales_payments (
  id,
  tenant_id,
  invoice_id,
  payment_method_id,
  amount,
  date,
  deleted_at
)
values
  -- Débito, mediodía del 10.
  (
    'f1000000-0000-4000-8000-00000000000a',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000007',
    'f1000000-0000-4000-8000-000000000008',
    69000,
    '2026-10-10 15:00:00+00',
    null
  ),
  -- Efectivo a las 21:30 de Santiago del 10 (00:30 UTC del 11).
  (
    'f1000000-0000-4000-8000-00000000000b',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000007',
    'f1000000-0000-4000-8000-000000000009',
    5000,
    '2026-10-11 00:30:00+00',
    null
  ),
  -- Anulado: revertir la factura deja el cobro con deleted_at.
  (
    'f1000000-0000-4000-8000-00000000000c',
    'f1000000-0000-4000-8000-000000000001',
    'f1000000-0000-4000-8000-000000000007',
    'f1000000-0000-4000-8000-000000000009',
    30000,
    '2026-10-10 16:00:00+00',
    '2026-10-10 17:00:00+00'
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'f1000000-0000-4000-8000-000000000002',
  true
);
set local role authenticated;

select is(
  (
    select count(*)::bigint
    from public.get_income_period_details(
      '2026-10-10 03:00:00+00',
      '2026-10-11 03:00:00+00',
      true
    )
  ),
  2::bigint,
  'cash income detail returns the live payments of the shop day and leaves the voided one out'
);

select results_eq(
  $$
    select payment_method_code, payment_instrument, settlement_provider, amount
    from public.get_income_period_details(
      '2026-10-10 03:00:00+00',
      '2026-10-11 03:00:00+00',
      true
    )
    where payment_method_code = 'card_debit'
  $$,
  $$ values ('card_debit'::text, 'debit'::text, 'transbank'::text, 69000::numeric) $$,
  'a card payment carries its method code, instrument and provider'
);

select is(
  (
    select transaction_date
    from public.get_income_period_details(
      '2026-10-10 03:00:00+00',
      '2026-10-11 03:00:00+00',
      true
    )
    where payment_method_code = 'cash'
  ),
  date '2026-10-10',
  'a payment at 21:30 in Santiago belongs to that shop day, not the next UTC day'
);

select is(
  (
    select occurred_at
    from public.get_income_period_details(
      '2026-10-10 03:00:00+00',
      '2026-10-11 03:00:00+00',
      true
    )
    where payment_method_code = 'cash'
  ),
  '2026-10-11 00:30:00+00'::timestamptz,
  'the exact instant is returned for the time of day'
);

select is(
  (
    select count(*)::bigint
    from public.get_income_period_details(
      '2026-10-10 03:00:00+00',
      '2026-10-11 03:00:00+00',
      true
    )
    where id = 'f1000000-0000-4000-8000-00000000000c'
  ),
  0::bigint,
  'a voided payment never reaches the detail'
);

-- The app sends the calendar day as an offset-less midnight. Since
-- 20261030020000 the bar counts the 21:30 Santiago payment in its shop day,
-- like the detail above (69000 + 5000), and still leaves the voided one out.
select is(
  (
    select income
    from public.get_income_expense_daily_timeseries(
      '2026-10-10 00:00:00+00',
      '2026-10-10 23:59:59+00',
      true
    )
    where period_start = date '2026-10-10'
  ),
  74000::numeric,
  'the cash chart counts the shop day and leaves the voided payment out, so the bar and its detail agree'
);

select throws_ok(
  $$select * from public.get_income_period_details(
    '2026-10-11 00:00:00+00',
    '2026-10-10 00:00:00+00',
    true
  )$$,
  '22023',
  'Invalid accounting date range',
  'a reversed range is rejected'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"f1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'f1000000-0000-4000-8000-000000000003',
  true
);

select throws_ok(
  $$select * from public.get_income_period_details(
    '2026-10-10 03:00:00+00',
    '2026-10-11 03:00:00+00',
    true
  )$$,
  '42501',
  'Accounting access denied',
  'a mechanic without accounting authority cannot read the income detail'
);

select throws_ok(
  $$select * from public.get_income_period_details(
    '2026-10-10 03:00:00+00',
    '2026-10-11 03:00:00+00',
    false
  )$$,
  '42501',
  'Accounting access denied',
  'the accrual drill-down has the same gate'
);

select * from finish();
rollback;
