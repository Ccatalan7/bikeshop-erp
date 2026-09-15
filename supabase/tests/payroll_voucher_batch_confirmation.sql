begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  to_regclass(
    'public.payroll_voucher_confirmation_batch_operations'
  ) is not null
  and to_regprocedure(
    'public.confirm_payroll_vouchers_v1(text,jsonb)'
  ) is not null
  and has_function_privilege(
    'authenticated',
    'public.confirm_payroll_vouchers_v1(text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.confirm_payroll_vouchers_v1(text,jsonb)',
    'EXECUTE'
  )
  and (
    select table_row.relrowsecurity
    from pg_class table_row
    where table_row.oid =
      'public.payroll_voucher_confirmation_batch_operations'::regclass
  ),
  'batch confirmation exposes one authenticated RPC and seals its ledger'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_confirmation_batch_operations',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_confirmation_batch_operations',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_confirmation_batch_operations',
    'DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_voucher_confirmation_batch_operations',
    'INSERT'
  ),
  'API and service roles cannot forge batch confirmation receipts'
);

insert into public.tenants (id, shop_name, timezone)
values
  (
    '9b111111-1111-4111-8111-111111111111',
    'Payroll Batch Tenant One',
    'America/Santiago'
  ),
  (
    '9b111111-1111-4111-8111-111111111112',
    'Payroll Batch Tenant Two',
    'America/Santiago'
  );

set local session_replication_role = replica;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '9b000000-0000-4000-8000-000000000001',
    'authenticated', 'authenticated',
    'batch-manager@example.invalid', '', now(),
    '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '9b000000-0000-4000-8000-000000000002',
    'authenticated', 'authenticated',
    'batch-worker@example.invalid', '', now(),
    '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
  );

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
)
values
  (
    '9b000000-0000-4000-8000-000000000011',
    '9b000000-0000-4000-8000-000000000001',
    '9b111111-1111-4111-8111-111111111111',
    'accountant', '{"access_accounting":true}'::jsonb, true
  ),
  (
    '9b000000-0000-4000-8000-000000000012',
    '9b000000-0000-4000-8000-000000000002',
    '9b111111-1111-4111-8111-111111111111',
    'cashier', '{}'::jsonb, true
  );

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title
)
values
  (
    '9b222222-2222-4222-8222-222222222221',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-01', 'Primera', 'Persona', 'Mecánico'
  ),
  (
    '9b222222-2222-4222-8222-222222222222',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-02', 'Segunda', 'Persona', 'Mecánico'
  ),
  (
    '9b222222-2222-4222-8222-222222222223',
    '9b111111-1111-4111-8111-111111111112',
    'BATCH-03', 'Otro', 'Tenant', 'Mecánico'
  );

insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end,
  total_hours, total_amount, employee_count, status
)
values
  (
    '9b333333-3333-4333-8333-333333333331',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-A', '2026-07-27', '2026-08-02', 10, 35000, 1, 'draft'
  ),
  (
    '9b333333-3333-4333-8333-333333333332',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-B', '2026-08-03', '2026-08-09', 10, 40000, 1, 'draft'
  ),
  (
    '9b333333-3333-4333-8333-333333333333',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-C', '2026-07-20', '2026-07-26', 10, 30000, 1, 'draft'
  ),
  (
    '9b333333-3333-4333-8333-333333333334',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-CONFIRMED', '2026-07-13', '2026-07-19',
    10, 25000, 1, 'confirmed'
  ),
  (
    '9b333333-3333-4333-8333-333333333335',
    '9b111111-1111-4111-8111-111111111111',
    'BATCH-ZERO', '2026-07-06', '2026-07-12', 0, 0, 0, 'draft'
  ),
  (
    '9b333333-3333-4333-8333-333333333336',
    '9b111111-1111-4111-8111-111111111112',
    'BATCH-OTHER', '2026-07-27', '2026-08-02', 10, 50000, 1, 'draft'
  );

insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name,
  worked_hours, hourly_rate, regular_amount, total_amount, is_included
)
values
  (
    '9b444444-4444-4444-8444-444444444441',
    '9b111111-1111-4111-8111-111111111111',
    '9b333333-3333-4333-8333-333333333331',
    '9b222222-2222-4222-8222-222222222221',
    'Primera Persona', 10, 3500, 35000, 35000, true
  ),
  (
    '9b444444-4444-4444-8444-444444444442',
    '9b111111-1111-4111-8111-111111111111',
    '9b333333-3333-4333-8333-333333333332',
    '9b222222-2222-4222-8222-222222222222',
    'Segunda Persona', 10, 4000, 40000, 40000, true
  ),
  (
    '9b444444-4444-4444-8444-444444444443',
    '9b111111-1111-4111-8111-111111111111',
    '9b333333-3333-4333-8333-333333333333',
    '9b222222-2222-4222-8222-222222222221',
    'Primera Persona', 10, 3000, 30000, 30000, true
  ),
  (
    '9b444444-4444-4444-8444-444444444444',
    '9b111111-1111-4111-8111-111111111111',
    '9b333333-3333-4333-8333-333333333334',
    '9b222222-2222-4222-8222-222222222221',
    'Primera Persona', 10, 2500, 25000, 25000, true
  ),
  (
    '9b444444-4444-4444-8444-444444444445',
    '9b111111-1111-4111-8111-111111111111',
    '9b333333-3333-4333-8333-333333333335',
    '9b222222-2222-4222-8222-222222222221',
    'Primera Persona', 0, 0, 0, 0, true
  ),
  (
    '9b444444-4444-4444-8444-444444444446',
    '9b111111-1111-4111-8111-111111111112',
    '9b333333-3333-4333-8333-333333333336',
    '9b222222-2222-4222-8222-222222222223',
    'Otro Tenant', 10, 5000, 50000, 50000, true
  );

set local session_replication_role = origin;

-- Isolate the new atomic orchestration contract from the already-covered
-- legacy expense projection performed by a single confirmation.
create or replace function public.confirm_payroll_voucher_internal(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.payroll_vouchers voucher
  set status = 'confirmed',
      updated_at = statement_timestamp()
  where voucher.id = p_voucher_id
    and voucher.tenant_id = public.user_tenant_id()
    and voucher.status = 'draft';
  return found;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"9b000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b000000-0000-4000-8000-000000000002',
  true
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:denied:0001',
    '[{"voucher_id":"9b333333-3333-4333-8333-333333333331","expected_reconciliation_version":0}]'::jsonb
  )$$,
  '42501',
  'Payroll access denied',
  'a tenant member without payroll authority cannot approve a batch'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9b000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b000000-0000-4000-8000-000000000001',
  true
);

create temporary table batch_first_receipt on commit drop as
select public.confirm_payroll_vouchers_v1(
  'batch:success:0001',
  '[
    {"voucher_id":"9b333333-3333-4333-8333-333333333332","expected_reconciliation_version":0},
    {"voucher_id":"9b333333-3333-4333-8333-333333333331","expected_reconciliation_version":0}
  ]'::jsonb
) as receipt;

select is(
  (
    select count(*)::integer
    from public.payroll_vouchers voucher
    where voucher.id in (
      '9b333333-3333-4333-8333-333333333331',
      '9b333333-3333-4333-8333-333333333332'
    )
      and voucher.status = 'confirmed'
  ),
  2,
  'one call confirms every explicitly selected draft'
);

select ok(
  (
    select jsonb_array_length(receipt->'confirmed_vouchers') = 2
      and receipt->>'operation' = 'confirm_drafts_batch'
      and (receipt->>'replayed')::boolean is false
    from batch_first_receipt
  ),
  'the first receipt returns every confirmed voucher and its lifecycle result'
);

select ok(
  (
    select (public.confirm_payroll_vouchers_v1(
      'batch:success:0001',
      '[
        {"voucher_id":"9b333333-3333-4333-8333-333333333331","expected_reconciliation_version":0},
        {"voucher_id":"9b333333-3333-4333-8333-333333333332","expected_reconciliation_version":0}
      ]'::jsonb
    )->>'replayed')::boolean
  )
  and (
    select count(*) = 1
    from public.payroll_voucher_confirmation_batch_operations batch_operation
    where batch_operation.operation_key = 'batch:success:0001'
  ),
  'an exact semantic retry replays one immutable operation despite input order'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:success:0001',
    '[{"voucher_id":"9b333333-3333-4333-8333-333333333333","expected_reconciliation_version":0}]'::jsonb
  )$$,
  'P0001',
  'payroll_voucher_batch_idempotency_conflict',
  'an operation key cannot be reused with another batch'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:nondraft:001',
    '[
      {"voucher_id":"9b333333-3333-4333-8333-333333333333","expected_reconciliation_version":0},
      {"voucher_id":"9b333333-3333-4333-8333-333333333334","expected_reconciliation_version":0}
    ]'::jsonb
  )$$,
  '55000',
  'payroll_voucher_batch_contains_non_draft',
  'a non-draft voucher rejects the complete batch'
);

select is(
  (
    select voucher.status
    from public.payroll_vouchers voucher
    where voucher.id = '9b333333-3333-4333-8333-333333333333'
  ),
  'draft',
  'prevalidation leaves earlier drafts untouched when another item is invalid'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:stale:00001',
    '[{"voucher_id":"9b333333-3333-4333-8333-333333333333","expected_reconciliation_version":1}]'::jsonb
  )$$,
  '40001',
  'payroll_voucher_batch_version_conflict',
  'one stale version rejects the batch before confirmation'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:zero:000001',
    '[{"voucher_id":"9b333333-3333-4333-8333-333333333335","expected_reconciliation_version":0}]'::jsonb
  )$$,
  '22023',
  'payroll_voucher_batch_has_no_positive_obligations',
  'each draft must contain a positive included obligation'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:tenant:0001',
    '[{"voucher_id":"9b333333-3333-4333-8333-333333333336","expected_reconciliation_version":0}]'::jsonb
  )$$,
  '42501',
  'Payroll voucher not found',
  'another tenant voucher is indistinguishable from a missing voucher'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:duplicate:1',
    '[
      {"voucher_id":"9b333333-3333-4333-8333-333333333333","expected_reconciliation_version":0},
      {"voucher_id":"9b333333-3333-4333-8333-333333333333","expected_reconciliation_version":0}
    ]'::jsonb
  )$$,
  '23505',
  'payroll_voucher_batch_duplicate_voucher',
  'the explicit batch rejects duplicate voucher identifiers'
);

select throws_ok(
  $$select public.confirm_payroll_vouchers_v1(
    'batch:empty:000001',
    '[]'::jsonb
  )$$,
  '22023',
  'payroll_voucher_batch_invalid_payload',
  'an empty approval selection is rejected'
);

select * from finish();
rollback;
