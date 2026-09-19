-- The review's side of the race: it was built when the week owed $100.000
-- and pays $40.000 of it. Nómina committed $20.000 meanwhile, so this must
-- come back as a conflict and create nothing.
-- LOCAL stack only, driven by scripts/db/payroll_lock_probe.sh.
select set_config(
  'request.jwt.claims',
  '{"sub":"e9000000-0000-4000-8000-000000000002","role":"authenticated"}',
  false
);
select set_config(
  'request.jwt.claim.sub', 'e9000000-0000-4000-8000-000000000002', false
);
set statement_timeout = '60s';

select public.apply_bank_reconciliation_actions_v3(
  (select id from public.bank_statement_imports
    where tenant_id = 'e9000000-0000-4000-8000-000000000001'),
  (select revision from public.bank_statement_imports
    where tenant_id = 'e9000000-0000-4000-8000-000000000001'),
  'payroll-lock-probe:review-pays',
  jsonb_build_array(jsonb_build_object(
    'row_id', (select id from public.bank_statement_rows
                where tenant_id = 'e9000000-0000-4000-8000-000000000001'),
    'action', 'pay_payroll',
    'payroll', jsonb_build_object(
      'voucher_id', 'e9000000-0000-4000-8000-000000000040',
      'voucher_line_id', 'e9000000-0000-4000-8000-000000000041',
      'expected_amount', 100000, 'amount', 40000,
      'payment_method_id', 'e9000000-0000-4000-8000-000000000020',
      'confirm_draft', true
    )
  ))
);
