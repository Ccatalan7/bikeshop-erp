-- Nómina's side of the race: it records a $20.000 payment on the week and
-- holds its settlement lock for a few seconds before committing.
-- LOCAL stack only, driven by scripts/db/payroll_lock_probe.sh.
begin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e9000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e9000000-0000-4000-8000-000000000002', true
);

select public.pay_payroll_voucher_v2(
  'e9000000-0000-4000-8000-000000000040',
  'payroll-lock-probe:nomina-pays',
  (select reconciliation_version from public.payroll_vouchers
    where id = 'e9000000-0000-4000-8000-000000000040'),
  jsonb_build_object(
    'e9000000-0000-4000-8000-000000000041',
    jsonb_build_array(jsonb_build_object(
      'kind', 'payment',
      'amount', 20000,
      'payment_method_id', 'e9000000-0000-4000-8000-000000000020',
      'payment_account_id', 'e9000000-0000-4000-8000-000000000010',
      'payment_date', '2026-08-31T12:00:00Z',
      'reference', 'Anticipo de caja registrado en Nómina'
    ))
  )
);

-- The window the review used to slip through.
select pg_sleep(5);

commit;
