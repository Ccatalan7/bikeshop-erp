begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_employee_advance_ledger_page_v1(uuid,integer,timestamp with time zone,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_employee_advance_ledger_page_v1(uuid,integer,timestamp with time zone,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_employee_advance_ledger_page_v1(uuid,integer,timestamp with time zone,uuid)',
    'EXECUTE'
  ),
  'the advance ledger is exposed only to authenticated ERP callers'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_payroll_history_page_v1(integer,date,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_payroll_history_page_v1(integer,date,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_payroll_history_page_v1(integer,date,uuid)',
    'EXECUTE'
  ),
  'the paginated payroll history is exposed only to authenticated ERP callers'
);

select ok(
  to_regclass(
    'public.idx_employee_advances_tenant_employee_paid_cursor'
  ) is not null
  and to_regclass(
    'public.idx_payroll_vouchers_tenant_history_cursor'
  ) is not null,
  'both keyset projections have supporting compound indexes'
);

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      25,
      null,
      null
    )
  $$,
  '42501',
  'Payroll access denied',
  'an unauthenticated caller cannot read an employee advance ledger'
);

select throws_ok(
  $$
    select public.get_payroll_history_page_v1(25, null, null)
  $$,
  '42501',
  'Payroll access denied',
  'an unauthenticated caller cannot read payroll history'
);

set local session_replication_role = replica;

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  owner_email,
  timezone,
  is_active
)
values
  (
    '7f292200-0000-4000-8000-000000000001',
    'Payroll Audit Tenant A',
    'payroll-audit-a',
    'payroll-audit-a@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7f292200-0000-4000-8000-000000000002',
    'Payroll Audit Tenant B',
    'payroll-audit-b',
    'payroll-audit-b@example.invalid',
    'America/Santiago',
    true
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
    '7f292200-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'payroll-audit-manager@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f292200-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'payroll-audit-cashier@example.invalid',
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
  employee_id,
  role,
  permissions,
  is_active
)
values
  (
    '7f292200-0000-4000-8000-000000000111',
    '7f292200-0000-4000-8000-000000000101',
    '7f292200-0000-4000-8000-000000000001',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  ),
  (
    '7f292200-0000-4000-8000-000000000112',
    '7f292200-0000-4000-8000-000000000102',
    '7f292200-0000-4000-8000-000000000001',
    null,
    'cashier',
    '{}'::jsonb,
    true
  );

insert into public.employees (
  id,
  tenant_id,
  employee_number,
  first_name,
  last_name,
  job_title,
  status
)
values
  (
    '7f292200-0000-4000-8000-000000000201',
    '7f292200-0000-4000-8000-000000000001',
    'AUDIT-A-001',
    'Lucas',
    'Reyes',
    'Mecánico',
    'active'
  ),
  (
    '7f292200-0000-4000-8000-000000000202',
    '7f292200-0000-4000-8000-000000000002',
    'AUDIT-B-001',
    'Tenant',
    'Two',
    'Mecánico',
    'active'
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
  '7f292200-0000-4000-8000-000000000301',
  '7f292200-0000-4000-8000-000000000001',
  '1102',
  'Banco',
  'asset',
  'currentAsset'
);

insert into public.payment_methods (
  id,
  tenant_id,
  code,
  name,
  account_id,
  default_tax_treatment,
  is_active
)
values (
  '7f292200-0000-4000-8000-000000000401',
  '7f292200-0000-4000-8000-000000000001',
  'transfer',
  'Transferencia',
  '7f292200-0000-4000-8000-000000000301',
  'no_tax',
  true
);

insert into public.payroll_vouchers (
  id,
  tenant_id,
  voucher_number,
  period_start,
  period_end,
  period_label,
  total_hours,
  total_amount,
  employee_count,
  status,
  paid_at,
  paid_by,
  notes,
  created_by,
  created_at,
  updated_at,
  reconciliation_version
)
values
  (
    '7f292200-0000-4000-8000-000000000601',
    '7f292200-0000-4000-8000-000000000001',
    'NOM-AUDIT-003',
    '2026-07-20',
    '2026-07-26',
    'Semana 30',
    61,
    267875,
    3,
    'paid',
    '2026-07-29 20:00:00+00',
    '7f292200-0000-4000-8000-000000000101',
    null,
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-27 12:00:00+00',
    '2026-07-29 20:00:00+00',
    8
  ),
  (
    '7f292200-0000-4000-8000-000000000602',
    '7f292200-0000-4000-8000-000000000001',
    'NOM-AUDIT-002',
    '2026-07-13',
    '2026-07-19',
    'Semana 29',
    55,
    240000,
    3,
    'voided',
    null,
    null,
    'Anulada',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-20 12:00:00+00',
    '2026-07-21 12:00:00+00',
    3
  ),
  (
    '7f292200-0000-4000-8000-000000000603',
    '7f292200-0000-4000-8000-000000000001',
    'NOM-AUDIT-001',
    '2026-07-06',
    '2026-07-12',
    'Semana 28',
    58,
    250000,
    3,
    'paid',
    '2026-07-14 20:00:00+00',
    '7f292200-0000-4000-8000-000000000101',
    null,
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-13 12:00:00+00',
    '2026-07-14 20:00:00+00',
    4
  ),
  (
    '7f292200-0000-4000-8000-000000000604',
    '7f292200-0000-4000-8000-000000000001',
    'NOM-AUDIT-DRAFT',
    '2026-06-29',
    '2026-07-05',
    'Semana 27',
    50,
    220000,
    3,
    'draft',
    null,
    null,
    null,
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-06 12:00:00+00',
    '2026-07-06 12:00:00+00',
    1
  ),
  (
    '7f292200-0000-4000-8000-000000000605',
    '7f292200-0000-4000-8000-000000000001',
    'NOM-AUDIT-PARTIAL',
    '2026-06-22',
    '2026-06-28',
    'Semana 26',
    49,
    210000,
    3,
    'partial',
    null,
    null,
    null,
    '7f292200-0000-4000-8000-000000000101',
    '2026-06-29 12:00:00+00',
    '2026-06-29 12:00:00+00',
    2
  );

insert into public.payroll_voucher_lines (
  id,
  tenant_id,
  voucher_id,
  employee_id,
  employee_name,
  worked_hours,
  overtime_hours,
  hourly_rate,
  overtime_rate,
  regular_amount,
  overtime_amount,
  total_amount,
  payment_method,
  payment_method_id,
  payment_account_id,
  is_included
)
values
  (
    '7f292200-0000-4000-8000-000000000611',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000601',
    '7f292200-0000-4000-8000-000000000201',
    'Lucas Reyes',
    40,
    0,
    3500,
    5250,
    140000,
    0,
    140000,
    'transfer',
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    true
  ),
  (
    '7f292200-0000-4000-8000-000000000613',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000603',
    '7f292200-0000-4000-8000-000000000201',
    'Lucas Reyes',
    40,
    0,
    3500,
    5250,
    140000,
    0,
    140000,
    'transfer',
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    true
  );

insert into public.employee_advances (
  id,
  tenant_id,
  employee_id,
  amount,
  amount_applied,
  payment_method_id,
  payment_account_id,
  paid_at,
  reference,
  notes,
  status,
  created_by,
  created_at,
  updated_at
)
values
  (
    '7f292200-0000-4000-8000-000000000701',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000201',
    100000,
    40000,
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    '2026-07-29 15:00:00+00',
    'ADV-001',
    'Anticipo parcialmente imputado',
    'partially_applied',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-29 15:00:01+00',
    '2026-07-30 12:00:00+00'
  ),
  (
    '7f292200-0000-4000-8000-000000000705',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000201',
    25000,
    0,
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    '2026-07-29 15:00:00+00',
    'ADV-005',
    null,
    'open',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-29 15:00:02+00',
    '2026-07-29 15:00:02+00'
  ),
  (
    '7f292200-0000-4000-8000-000000000702',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000201',
    50000,
    0,
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    '2026-07-20 15:00:00+00',
    'ADV-002',
    null,
    'open',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-20 15:00:00+00',
    '2026-07-20 15:00:00+00'
  ),
  (
    '7f292200-0000-4000-8000-000000000703',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000201',
    30000,
    30000,
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    '2026-07-10 15:00:00+00',
    'ADV-003',
    null,
    'applied',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-10 15:00:00+00',
    '2026-07-14 12:00:00+00'
  ),
  (
    '7f292200-0000-4000-8000-000000000704',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000201',
    20000,
    0,
    '7f292200-0000-4000-8000-000000000401',
    '7f292200-0000-4000-8000-000000000301',
    '2026-07-01 15:00:00+00',
    'ADV-004',
    'Anulado',
    'voided',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-01 15:00:00+00',
    '2026-07-02 15:00:00+00'
  );

insert into public.employee_advance_allocations (
  id,
  tenant_id,
  advance_id,
  voucher_line_id,
  amount,
  applied_at,
  notes,
  created_by,
  created_at,
  updated_at
)
values
  (
    '7f292200-0000-4000-8000-000000000711',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000701',
    '7f292200-0000-4000-8000-000000000611',
    40000,
    '2026-07-30 12:00:00+00',
    'Aplicado a semana 30',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-30 12:00:01+00',
    '2026-07-30 12:00:01+00'
  ),
  (
    '7f292200-0000-4000-8000-000000000713',
    '7f292200-0000-4000-8000-000000000001',
    '7f292200-0000-4000-8000-000000000703',
    '7f292200-0000-4000-8000-000000000613',
    30000,
    '2026-07-14 12:00:00+00',
    'Aplicado a semana 28',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-14 12:00:01+00',
    '2026-07-14 12:00:01+00'
  );

insert into public.payroll_money_operations (
  id,
  tenant_id,
  operation_type,
  operation_key,
  payload_hash,
  voucher_id,
  employee_advance_id,
  receipt,
  created_by,
  created_at
)
values
  (
    '7f292200-0000-4000-8000-000000000721',
    '7f292200-0000-4000-8000-000000000001',
    'employee_advance',
    'audit-advance-funding-001',
    repeat('a', 64),
    null,
    '7f292200-0000-4000-8000-000000000701',
    '{"advance_id":"7f292200-0000-4000-8000-000000000701"}',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-29 15:00:01+00'
  ),
  (
    '7f292200-0000-4000-8000-000000000722',
    '7f292200-0000-4000-8000-000000000001',
    'manual_payroll_payment',
    'audit-allocation-001',
    repeat('b', 64),
    '7f292200-0000-4000-8000-000000000601',
    null,
    '{"voucher_id":"7f292200-0000-4000-8000-000000000601"}',
    '7f292200-0000-4000-8000-000000000101',
    '2026-07-30 12:00:01+00'
  );

insert into public.payroll_money_operation_movements (
  id,
  tenant_id,
  operation_id,
  movement_type,
  expense_payment_id,
  advance_allocation_id,
  created_at
)
values (
  '7f292200-0000-4000-8000-000000000731',
  '7f292200-0000-4000-8000-000000000001',
  '7f292200-0000-4000-8000-000000000722',
  'advance_allocation',
  null,
  '7f292200-0000-4000-8000-000000000711',
  '2026-07-30 12:00:01+00'
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f292200-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f292200-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      25,
      null,
      null
    )
  $$,
  '42501',
  'Payroll access denied',
  'an ERP user without payroll authority cannot read advances'
);

select throws_ok(
  $$
    select public.get_payroll_history_page_v1(25, null, null)
  $$,
  '42501',
  'Payroll access denied',
  'an ERP user without payroll authority cannot read history'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f292200-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f292200-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000202',
      25,
      null,
      null
    )
  $$,
  '42501',
  'Payroll access denied',
  'an authorized manager cannot probe an employee in another tenant'
);

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      0,
      null,
      null
    )
  $$,
  '22023',
  'Payroll page size must be between 1 and 100',
  'the advance ledger rejects an unbounded page size'
);

select throws_ok(
  $$
    select public.get_payroll_history_page_v1(101, null, null)
  $$,
  '22023',
  'Payroll page size must be between 1 and 100',
  'history rejects an unbounded page size'
);

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      25,
      '2026-07-29 15:00:00+00',
      null
    )
  $$,
  '22023',
  'Employee advance cursor requires paid_at and id',
  'the advance ledger rejects a half cursor'
);

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      25,
      '2026-07-28 15:00:00+00',
      '7f292200-0000-4000-8000-000000000701'
    )
  $$,
  '22023',
  'Invalid employee advance cursor',
  'the advance ledger validates that both cursor values identify one row'
);

select throws_ok(
  $$
    select public.get_payroll_history_page_v1(
      25,
      null,
      '7f292200-0000-4000-8000-000000000601'
    )
  $$,
  '22023',
  'Payroll history cursor requires period_end and id',
  'history rejects a half cursor'
);

select throws_ok(
  $$
    select public.get_payroll_history_page_v1(
      25,
      '2026-07-25',
      '7f292200-0000-4000-8000-000000000601'
    )
  $$,
  '22023',
  'Invalid payroll history cursor',
  'history validates that both cursor values identify one retained header'
);

select is(
  (
    public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      2,
      null,
      null
    )->'totals'->>'delivered_amount'
  )::numeric,
  205000::numeric,
  'advance delivered total excludes the voided record'
);

select is(
  (
    public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      2,
      null,
      null
    )->'totals'->>'applied_amount'
  )::numeric,
  70000::numeric,
  'advance applied total is derived from allocation rows'
);

select is(
  (
    public.get_employee_advance_ledger_page_v1(
      '7f292200-0000-4000-8000-000000000201',
      2,
      null,
      null
    )->'totals'->>'balance_amount'
  )::numeric,
  135000::numeric,
  'advance open balance is server-derived and excludes voided money'
);

select ok(
  public.get_employee_advance_ledger_page_v1(
    '7f292200-0000-4000-8000-000000000201',
    2,
    null,
    null
  )->>'has_more' = 'true'
  and public.get_employee_advance_ledger_page_v1(
    '7f292200-0000-4000-8000-000000000201',
    2,
    null,
    null
  )->'next_cursor'->>'id'
    = '7f292200-0000-4000-8000-000000000701',
  'advance pagination uses paid_at and id to break equal-date ties'
);

select ok(
  not exists (
    with first_page as (
      select public.get_employee_advance_ledger_page_v1(
        '7f292200-0000-4000-8000-000000000201',
        2,
        null,
        null
      ) as body
    ),
    second_page as (
      select public.get_employee_advance_ledger_page_v1(
        '7f292200-0000-4000-8000-000000000201',
        2,
        '2026-07-29 15:00:00+00',
        '7f292200-0000-4000-8000-000000000701'
      ) as body
    )
    select 1
    from first_page
    cross join second_page
    cross join lateral
      jsonb_array_elements(first_page.body->'items') first_item
    cross join lateral
      jsonb_array_elements(second_page.body->'items') second_item
    where first_item->>'id' = second_item->>'id'
  ),
  'successive advance pages contain no duplicate rows'
);

select ok(
  (
    select
      (item->>'applied_amount')::numeric = 40000
      and (item->>'balance_amount')::numeric = 60000
      and item->'payment_method'->>'code' = 'transfer'
      and item->'payment_account'->>'code' = '1102'
      and item->'actor'->>'id'
        = '7f292200-0000-4000-8000-000000000101'
      and item->'funding_evidence'->>'operation_key'
        = 'audit-advance-funding-001'
      and jsonb_array_length(item->'allocations') = 1
      and item->'allocations'->0->'voucher'->>'period_end'
        = '2026-07-26'
      and item->'allocations'->0->'voucher_line'->>'id'
        = '7f292200-0000-4000-8000-000000000611'
      and item->'allocations'->0->'evidence'->>'operation_key'
        = 'audit-allocation-001'
    from jsonb_array_elements(
      public.get_employee_advance_ledger_page_v1(
        '7f292200-0000-4000-8000-000000000201',
        100,
        null,
        null
      )->'items'
    ) item
    where item->>'id' = '7f292200-0000-4000-8000-000000000701'
  ),
  'advance rows include method, account, actor and allocation week evidence'
);

select ok(
  (
    select
      item->>'status' = 'voided'
      and (item->>'amount')::numeric = 20000
      and (item->>'balance_amount')::numeric = 0
    from jsonb_array_elements(
      public.get_employee_advance_ledger_page_v1(
        '7f292200-0000-4000-8000-000000000201',
        100,
        null,
        null
      )->'items'
    ) item
    where item->>'id' = '7f292200-0000-4000-8000-000000000704'
  ),
  'voided advances remain auditable without contributing an open balance'
);

select ok(
  public.get_payroll_history_page_v1(2, null, null)->>'has_more' = 'true'
  and public.get_payroll_history_page_v1(
    2,
    null,
    null
  )->'next_cursor'->>'id'
    = '7f292200-0000-4000-8000-000000000602',
  'history returns a stable period_end and id cursor'
);

select ok(
  not exists (
    with first_page as (
      select public.get_payroll_history_page_v1(
        2,
        null,
        null
      ) as body
    ),
    second_page as (
      select public.get_payroll_history_page_v1(
        2,
        '2026-07-19',
        '7f292200-0000-4000-8000-000000000602'
      ) as body
    )
    select 1
    from first_page
    cross join second_page
    cross join lateral
      jsonb_array_elements(first_page.body->'items') first_item
    cross join lateral
      jsonb_array_elements(second_page.body->'items') second_item
    where first_item->>'id' = second_item->>'id'
  ),
  'successive payroll history pages contain no duplicate headers'
);

select ok(
  (
    select
      count(*) = 3
      and bool_and(item->>'status' in ('paid', 'voided'))
      and bool_and(not item ? 'lines')
    from jsonb_array_elements(
      public.get_payroll_history_page_v1(
        100,
        null,
        null
      )->'items'
    ) item
  ),
  'history contains only paid/voided headers and never hydrates line detail'
);

select is(
  public.get_payroll_history_page_v1(
    2,
    '2026-07-19',
    '7f292200-0000-4000-8000-000000000602'
  )->'items'->0->>'id',
  '7f292200-0000-4000-8000-000000000603',
  'history resumes strictly after the validated cursor'
);

reset role;
select * from finish();
rollback;
