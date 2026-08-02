begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  to_regclass('public.payroll_statement_account_mappings') is not null
  and to_regclass('public.payroll_beneficiary_aliases') is not null
  and to_regclass('public.payroll_voucher_draft_operations') is not null
  and to_regclass('public.payroll_money_operations') is not null
  and to_regclass('public.payroll_money_operation_movements') is not null
  and to_regclass('public.payroll_money_command_contexts') is not null
  and to_regclass('public.payroll_statement_imports') is not null
  and to_regclass('public.payroll_statement_import_operations') is not null
  and to_regclass('public.payroll_statement_command_contexts') is not null
  and to_regclass('public.payroll_statement_rows') is not null
  and to_regclass('public.payroll_statement_decisions') is not null
  and to_regclass('public.payroll_statement_allocations') is not null,
  'payroll commands retain separate idempotency, capability, import, decision, and allocation evidence'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_payroll_voucher_settlement_evidence(uuid[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_payroll_voucher_settlement_evidence(uuid[])',
    'EXECUTE'
  ),
  'movement-level payroll evidence is available only through the authorized read model'
);

select ok(
  (
    select bool_and(table_row.relrowsecurity)
    from pg_class table_row
    where table_row.oid in (
      'public.payroll_statement_account_mappings'::regclass,
      'public.payroll_voucher_draft_operations'::regclass,
      'public.payroll_money_operations'::regclass,
      'public.payroll_money_operation_movements'::regclass,
      'public.payroll_statement_imports'::regclass,
      'public.payroll_statement_import_operations'::regclass,
      'public.payroll_statement_rows'::regclass,
      'public.payroll_statement_decisions'::regclass,
      'public.payroll_statement_allocations'::regclass
    )
  ),
  'every statement reconciliation table has RLS enabled'
);

select ok(
  (
    select bool_and(attribute_row.attnotnull is false)
    from pg_catalog.pg_attribute attribute_row
    where attribute_row.attrelid =
        'public.payroll_statement_rows'::regclass
      and attribute_row.attname in (
        'transaction_date',
        'direction',
        'amount'
      )
      and attribute_row.attnum > 0
      and not attribute_row.attisdropped
  )
  and (
    select count(*) = 3
    from pg_catalog.pg_attribute attribute_row
    where attribute_row.attrelid =
        'public.payroll_statement_rows'::regclass
      and attribute_row.attname in (
        'transaction_date',
        'direction',
        'amount'
      )
      and attribute_row.attnum > 0
      and not attribute_row.attisdropped
  ),
  'incomplete OCR date, direction, and amount remain nullable audit evidence'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.payroll_statement_rows',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_statement_rows',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_statement_rows',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_statement_rows',
    'DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_statement_rows',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_statement_command_contexts',
    'INSERT'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_statement_command_contexts',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_draft_operations',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_draft_operations',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_draft_operations',
    'DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_voucher_draft_operations',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_money_operations',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_money_operation_movements',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_money_operation_movements',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_money_operation_movements',
    'DELETE'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_money_operation_movements',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_money_command_contexts',
    'INSERT'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_money_command_contexts',
    'INSERT'
  ),
  'API and service roles cannot forge parser, lifecycle, capability, or money-operation evidence'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_payroll_statement_import(text,text,jsonb,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.apply_payroll_statement_reconciliation(uuid,text,jsonb,jsonb,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_payroll_voucher_draft(uuid,text,bigint,jsonb,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.confirm_payroll_voucher_v2(uuid,text,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.pay_payroll_voucher_v2(uuid,text,bigint,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.register_employee_advance_v2(text,uuid,numeric,uuid,uuid,timestamp with time zone,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.delete_payroll_voucher_draft_v2(uuid,text,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.create_payroll_statement_import(text,text,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_payroll_statement_reconciliation(uuid,text,jsonb,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.pay_payroll_voucher(uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.register_employee_advance(uuid,numeric,uuid,uuid,timestamp with time zone,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.confirm_payroll_voucher(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.delete_payroll_voucher_draft(uuid)',
    'EXECUTE'
  ),
  'authenticated callers use only versioned and idempotent payroll commands'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.payroll_vouchers',
    'DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_lines',
    'DELETE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_voucher_lines',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_vouchers',
    'UPDATE'
  ),
  'voucher header and line mutations are server-owned full-snapshot commands'
);

insert into public.tenants (id, shop_name, timezone)
values
  (
    '7f281000-0000-4000-8000-000000000001',
    'Payroll Statement Tenant One',
    'America/Santiago'
  ),
  (
    '7f281000-0000-4000-8000-000000000002',
    'Payroll Statement Tenant Two',
    'America/Santiago'
  );

-- Tenant bootstrap creates defaults. Replace them with deterministic fixtures.
delete from public.payment_methods
where tenant_id in (
  '7f281000-0000-4000-8000-000000000001',
  '7f281000-0000-4000-8000-000000000002'
);
delete from public.accounts
where tenant_id in (
  '7f281000-0000-4000-8000-000000000001',
  '7f281000-0000-4000-8000-000000000002'
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
    '7f281000-0000-4000-8000-000000000301',
    '7f281000-0000-4000-8000-000000000001',
    '1102',
    'Banco',
    'asset',
    'currentAsset'
  ),
  (
    '7f281000-0000-4000-8000-000000000302',
    '7f281000-0000-4000-8000-000000000001',
    '1101',
    'Caja',
    'asset',
    'currentAsset'
  ),
  (
    '7f281000-0000-4000-8000-000000000303',
    '7f281000-0000-4000-8000-000000000001',
    '1135',
    'Anticipos al Personal',
    'asset',
    'currentAsset'
  ),
  (
    '7f281000-0000-4000-8000-000000000304',
    '7f281000-0000-4000-8000-000000000001',
    '2106',
    'Sueldos por Pagar',
    'liability',
    'currentLiability'
  ),
  (
    '7f281000-0000-4000-8000-000000000305',
    '7f281000-0000-4000-8000-000000000001',
    '610101',
    'Sueldo Vicente',
    'expense',
    'operatingExpense'
  ),
  (
    '7f281000-0000-4000-8000-000000000306',
    '7f281000-0000-4000-8000-000000000001',
    '610102',
    'Sueldo Guillermo',
    'expense',
    'operatingExpense'
  ),
  (
    '7f281000-0000-4000-8000-000000000307',
    '7f281000-0000-4000-8000-000000000002',
    '1102',
    'Banco Otro Tenant',
    'asset',
    'currentAsset'
  ),
  (
    '7f281000-0000-4000-8000-000000000308',
    '7f281000-0000-4000-8000-000000000002',
    '610101',
    'Sueldo Otro Tenant',
    'expense',
    'operatingExpense'
  );

insert into public.payment_methods (
  id,
  tenant_id,
  code,
  name,
  account_id,
  default_tax_treatment
)
values
  (
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000001',
    'transfer',
    'Transferencia',
    '7f281000-0000-4000-8000-000000000301',
    'no_tax'
  ),
  (
    '7f281000-0000-4000-8000-000000000402',
    '7f281000-0000-4000-8000-000000000001',
    'cash',
    'Efectivo',
    '7f281000-0000-4000-8000-000000000302',
    'no_tax'
  ),
  (
    '7f281000-0000-4000-8000-000000000403',
    '7f281000-0000-4000-8000-000000000002',
    'transfer',
    'Transferencia Otro Tenant',
    '7f281000-0000-4000-8000-000000000307',
    'no_tax'
  ),
  (
    '7f281000-0000-4000-8000-000000000404',
    '7f281000-0000-4000-8000-000000000001',
    'transfer_alt',
    'Transferencia Alternativa',
    '7f281000-0000-4000-8000-000000000301',
    'no_tax'
  );

set local session_replication_role = replica;

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
    '7f281000-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'statement-manager-one@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f281000-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'statement-worker@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f281000-0000-4000-8000-000000000103',
    'authenticated',
    'authenticated',
    'statement-manager-two@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

set local session_replication_role = origin;

insert into public.employees (
  id,
  tenant_id,
  employee_number,
  first_name,
  last_name,
  job_title,
  salary_account_id,
  preferred_payment_method,
  preferred_payment_method_id
)
values
  (
    '7f281000-0000-4000-8000-000000000201',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-001',
    'Vicente',
    'Díaz',
    'Manager',
    '7f281000-0000-4000-8000-000000000305',
    'transfer',
    '7f281000-0000-4000-8000-000000000401'
  ),
  (
    '7f281000-0000-4000-8000-000000000202',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-002',
    'Rodrigo Guillermo',
    'Nieto',
    'Mecánico',
    '7f281000-0000-4000-8000-000000000306',
    'cash',
    '7f281000-0000-4000-8000-000000000402'
  ),
  (
    '7f281000-0000-4000-8000-000000000203',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-003',
    'Trabajador',
    'Sin Permiso',
    'Mecánico',
    '7f281000-0000-4000-8000-000000000305',
    'transfer',
    '7f281000-0000-4000-8000-000000000401'
  ),
  (
    '7f281000-0000-4000-8000-000000000204',
    '7f281000-0000-4000-8000-000000000002',
    'STMT-004',
    'Otro',
    'Tenant',
    'Mecánico',
    '7f281000-0000-4000-8000-000000000308',
    'transfer',
    '7f281000-0000-4000-8000-000000000403'
  ),
  (
    '7f281000-0000-4000-8000-000000000205',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-005',
    'Sin',
    'Método',
    'Mecánico',
    '7f281000-0000-4000-8000-000000000305',
    null,
    null
  );

update public.employees
set user_id = '7f281000-0000-4000-8000-000000000102'
where id = '7f281000-0000-4000-8000-000000000203';

set local session_replication_role = replica;

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
    '7f281000-0000-4000-8000-000000000111',
    '7f281000-0000-4000-8000-000000000101',
    '7f281000-0000-4000-8000-000000000001',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  ),
  (
    '7f281000-0000-4000-8000-000000000112',
    '7f281000-0000-4000-8000-000000000102',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000203',
    'cashier',
    '{}'::jsonb,
    true
  ),
  (
    '7f281000-0000-4000-8000-000000000113',
    '7f281000-0000-4000-8000-000000000103',
    '7f281000-0000-4000-8000-000000000002',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  );

set local session_replication_role = origin;

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
  status
)
values
  (
    '7f281000-0000-4000-8000-000000000501',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-BANK',
    '2026-07-16',
    '2026-07-22',
    'Semana banco',
    36.5,
    127750,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000502',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-CASH',
    '2026-07-17',
    '2026-07-23',
    'Semana efectivo',
    9.5,
    38000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000503',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-ADVANCE',
    '2026-07-06',
    '2026-07-12',
    'Semana anticipo',
    9,
    36000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000504',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-NOT-PAID',
    '2026-07-18',
    '2026-07-24',
    'Semana pendiente',
    2.5,
    10000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000505',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-DELETE',
    '2026-01-12',
    '2026-01-18',
    'Borrador eliminable',
    1,
    3500,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000506',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-STALE',
    '2026-07-13',
    '2026-07-19',
    'Versión obsoleta',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000507',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-DUPLICATE',
    '2026-07-20',
    '2026-07-26',
    'Fila duplicada',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000508',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-NO-METHOD',
    '2026-07-21',
    '2026-07-27',
    'Método ausente',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000509',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-WARNING',
    '2026-07-22',
    '2026-07-28',
    'Advertencia OCR',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000510',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-MULTI',
    '2026-07-19',
    '2026-07-25',
    'Cobertura completa',
    2,
    2000,
    2,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000511',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-TOLERANCE',
    '2026-07-23',
    '2026-07-29',
    'Margen inválido',
    60,
    60000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000512',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-LOW-TOLERANCE',
    '2026-07-24',
    '2026-07-31',
    'Margen bajo',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000513',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-UNDERPAY',
    '2026-07-25',
    '2026-07-31',
    'Subpago revisado',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000514',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-W27-TRANSFER',
    '2026-06-30',
    '2026-07-06',
    'Semana 27 transferencia',
    37,
    129500,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000515',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-W27-CASH',
    '2026-06-28',
    '2026-07-04',
    'Semana 27 efectivo',
    6.5,
    26000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000516',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-CLOSE-PLUS-ONE',
    '2026-07-28',
    '2026-08-03',
    'Movimiento posterior al cierre',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000517',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-DYNAMIC-CLOSE-PLUS-ONE',
    (statement_timestamp() at time zone 'America/Santiago')::date - 6,
    (statement_timestamp() at time zone 'America/Santiago')::date,
    'Cierre dinámico más un día',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000518',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-DYNAMIC-FUTURE-TWO',
    (statement_timestamp() at time zone 'America/Santiago')::date - 9,
    (statement_timestamp() at time zone 'America/Santiago')::date - 1,
    'Futuro dinámico más dos días',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000519',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-REPEATED-PRIOR',
    -- Fixed overlapping weeks keep this duplicate-row scenario independent
    -- from the calendar-relative future-date fixtures above.
    '2026-03-01',
    '2026-03-07',
    'Cargo repetido anterior',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000520',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-REPEATED-NEW',
    '2026-03-02',
    '2026-03-08',
    'Cargo repetido nuevo',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000521',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-W27-END-PLUS-FIVE',
    '2026-06-29',
    '2026-07-05',
    'Límite de pago semana 27',
    1,
    1000,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000522',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-CONFIRM-V2',
    '2026-08-03',
    '2026-08-09',
    'Confirmación versionada',
    1,
    3500,
    1,
    'draft'
  ),
  (
    '7f281000-0000-4000-8000-000000000523',
    '7f281000-0000-4000-8000-000000000001',
    'STMT-DELETE-V2',
    '2026-08-10',
    '2026-08-16',
    'Eliminación versionada',
    1,
    3500,
    1,
    'draft'
  );

insert into public.payroll_voucher_lines (
  id,
  tenant_id,
  voucher_id,
  employee_id,
  employee_name,
  worked_hours,
  hourly_rate,
  regular_amount,
  total_amount,
  payment_method,
  payment_method_id,
  payment_account_id,
  is_included,
  salary_account_id
)
values
  (
    '7f281000-0000-4000-8000-000000000601',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000501',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    36.5,
    3500,
    127750,
    127750,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000602',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000502',
    '7f281000-0000-4000-8000-000000000202',
    'Rodrigo Guillermo Nieto',
    9.5,
    4000,
    38000,
    38000,
    'cash',
    '7f281000-0000-4000-8000-000000000402',
    '7f281000-0000-4000-8000-000000000302',
    true,
    '7f281000-0000-4000-8000-000000000306'
  ),
  (
    '7f281000-0000-4000-8000-000000000603',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000503',
    '7f281000-0000-4000-8000-000000000202',
    'Rodrigo Guillermo Nieto',
    9,
    4000,
    36000,
    36000,
    'cash',
    '7f281000-0000-4000-8000-000000000402',
    '7f281000-0000-4000-8000-000000000302',
    true,
    '7f281000-0000-4000-8000-000000000306'
  ),
  (
    '7f281000-0000-4000-8000-000000000604',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000504',
    '7f281000-0000-4000-8000-000000000202',
    'Rodrigo Guillermo Nieto',
    2.5,
    4000,
    10000,
    10000,
    'cash',
    '7f281000-0000-4000-8000-000000000402',
    '7f281000-0000-4000-8000-000000000302',
    true,
    '7f281000-0000-4000-8000-000000000306'
  ),
  (
    '7f281000-0000-4000-8000-000000000605',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000505',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    3500,
    3500,
    3500,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000606',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000506',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000607',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000507',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000608',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000508',
    '7f281000-0000-4000-8000-000000000205',
    'Sin Método',
    1,
    1000,
    1000,
    1000,
    null,
    null,
    null,
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000609',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000509',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000610',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000510',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000611',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000510',
    '7f281000-0000-4000-8000-000000000202',
    'Rodrigo Guillermo Nieto',
    0.25,
    4000,
    1000,
    1000,
    'cash',
    '7f281000-0000-4000-8000-000000000402',
    '7f281000-0000-4000-8000-000000000302',
    true,
    '7f281000-0000-4000-8000-000000000306'
  ),
  (
    '7f281000-0000-4000-8000-000000000612',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000511',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    60,
    1000,
    60000,
    60000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000613',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000512',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000614',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000513',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000615',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000514',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    37,
    3500,
    129500,
    129500,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000616',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000515',
    '7f281000-0000-4000-8000-000000000202',
    'Rodrigo Guillermo Nieto',
    6.5,
    4000,
    26000,
    26000,
    'cash',
    '7f281000-0000-4000-8000-000000000402',
    '7f281000-0000-4000-8000-000000000302',
    true,
    '7f281000-0000-4000-8000-000000000306'
  ),
  (
    '7f281000-0000-4000-8000-000000000617',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000516',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000618',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000517',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000619',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000518',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000620',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000519',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000621',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000520',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000622',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000521',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    1000,
    1000,
    1000,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000623',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000522',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    3500,
    3500,
    3500,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  ),
  (
    '7f281000-0000-4000-8000-000000000624',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000523',
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz',
    1,
    3500,
    3500,
    3500,
    'transfer',
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    true,
    '7f281000-0000-4000-8000-000000000305'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"7f281000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f281000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

reset role;
set local session_replication_role = replica;

insert into public.employee_advances (
  id,
  tenant_id,
  employee_id,
  amount,
  payment_method_id,
  paid_at,
  reference
)
values
  (
    '7f281000-0000-4000-8000-000000000701',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000202',
    36000,
    '7f281000-0000-4000-8000-000000000402',
    '2026-07-11 12:00:00+00',
    'STMT-ADVANCE-FIXTURE'
  ),
  (
    '7f281000-0000-4000-8000-000000000702',
    '7f281000-0000-4000-8000-000000000001',
    '7f281000-0000-4000-8000-000000000202',
    1000,
    '7f281000-0000-4000-8000-000000000402',
    '2026-07-27 12:00:00+00',
    'STMT-LATE-ADVANCE-FIXTURE'
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f281000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f281000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select set_config(
  'test.payroll.draft_create_receipt',
  public.save_payroll_voucher_draft(
    null,
    'draft-create-0001',
    null,
    jsonb_build_object(
      'period_start', '2026-02-02',
      'period_end', '2026-02-08',
      'period_label', 'Borrador atómico'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'employee_id', '7f281000-0000-4000-8000-000000000201',
        'worked_hours', 2,
        'overtime_hours', 1,
        'hourly_rate', 3500,
        'overtime_rate', 5250,
        'payment_method', 'transfer',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'salary_account_id',
          '7f281000-0000-4000-8000-000000000305',
        'is_included', true
      )
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.payroll.draft_create_receipt')::jsonb
      ->>'created'
  )::boolean
  and (
    current_setting('test.payroll.draft_create_receipt')::jsonb
      ->>'total_hours'
  )::numeric = 3
  and (
    current_setting('test.payroll.draft_create_receipt')::jsonb
      ->>'total_amount'
  )::numeric = 12250
  and jsonb_array_length(
    current_setting('test.payroll.draft_create_receipt')::jsonb->'lines'
  ) = 1,
  'draft create atomically derives totals and server-owned line IDs'
);

select is(
  public.save_payroll_voucher_draft(
    null,
    'draft-create-0001',
    null,
    jsonb_build_object(
      'period_start', '2026-02-02',
      'period_end', '2026-02-08',
      'period_label', 'Borrador atómico'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'employee_id', '7f281000-0000-4000-8000-000000000201',
        'worked_hours', 2,
        'overtime_hours', 1,
        'hourly_rate', 3500,
        'overtime_rate', 5250,
        'payment_method', 'transfer',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'salary_account_id',
          '7f281000-0000-4000-8000-000000000305',
        'is_included', true
      )
    )
  ),
  current_setting('test.payroll.draft_create_receipt')::jsonb,
  'lost acknowledgement retry returns the exact draft creation receipt'
);

select throws_ok(
  $$
    select public.save_payroll_voucher_draft(
      null,
      'draft-create-0001',
      null,
      jsonb_build_object(
        'period_start', '2026-02-02',
        'period_end', '2026-02-08',
        'period_label', 'Payload cambiado'
      ),
      '[]'::jsonb
    )
  $$,
  'P0001',
  'payroll_draft_idempotency_conflict',
  'a draft operation key cannot be reused with another snapshot'
);

select set_config(
  'test.payroll.draft_update_version',
  (
    select reconciliation_version::text
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000506'
  ),
  true
);

select set_config(
  'test.payroll.draft_update_receipt',
  public.save_payroll_voucher_draft(
    '7f281000-0000-4000-8000-000000000506',
    'draft-update-0001',
    current_setting('test.payroll.draft_update_version')::bigint,
    jsonb_build_object(
      'period_start', '2026-02-09',
      'period_end', '2026-02-15',
      'period_label', 'Versión reemplazada'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'line_id', '7f281000-0000-4000-8000-000000000606',
        'employee_id', '7f281000-0000-4000-8000-000000000201',
        'worked_hours', 1.25,
        'overtime_hours', 0,
        'hourly_rate', 1000,
        'overtime_rate', 1500,
        'payment_method', 'transfer',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'salary_account_id',
          '7f281000-0000-4000-8000-000000000305',
        'is_included', true
      )
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.payroll.draft_update_receipt')::jsonb
      ->>'created'
  )::boolean is false
  and (
    current_setting('test.payroll.draft_update_receipt')::jsonb
      ->>'reconciliation_version'
  )::bigint > current_setting(
    'test.payroll.draft_update_version'
  )::bigint
  and (
    select total_amount = 1250
      and payment_account_id =
        '7f281000-0000-4000-8000-000000000301'
    from public.payroll_voucher_lines
    where id = '7f281000-0000-4000-8000-000000000606'
  ),
  'draft replacement serializes one complete versioned header and line snapshot'
);

select throws_ok(
  $$
    select public.save_payroll_voucher_draft(
      '7f281000-0000-4000-8000-000000000506',
      'draft-update-stale-0002',
      current_setting('test.payroll.draft_update_version')::bigint,
      jsonb_build_object(
        'period_start', '2026-02-09',
        'period_end', '2026-02-15'
      ),
      '[]'::jsonb
    )
  $$,
  '40001',
  'payroll_draft_version_conflict',
  'a stale full-snapshot draft update fails before deleting any line'
);

select set_config(
  'test.payroll.advance_receipt',
  public.register_employee_advance_v2(
    'advance-create-0001',
    '7f281000-0000-4000-8000-000000000201',
    1234,
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    '2026-07-10 12:00:00+00',
    'ADVANCE-IDEMPOTENT',
    'Anticipo de prueba'
  )::text,
  true
);

select ok(
  (
    current_setting('test.payroll.advance_receipt')::jsonb
      ->>'advance_id'
  ) is not null
  and (
    current_setting('test.payroll.advance_receipt')::jsonb
      ->>'amount'
  )::numeric = 1234
  and (
    select count(*) = 1
    from public.employee_advances advance
    where advance.id = (
      current_setting('test.payroll.advance_receipt')::jsonb
        ->>'advance_id'
    )::uuid
  ),
  'advance v2 creates one reviewed money movement and exact receipt'
);

set local timezone = 'America/Santiago';

select is(
  public.register_employee_advance_v2(
    'advance-create-0001',
    '7f281000-0000-4000-8000-000000000201',
    1234,
    '7f281000-0000-4000-8000-000000000401',
    '7f281000-0000-4000-8000-000000000301',
    '2026-07-10 12:00:00+00',
    'ADVANCE-IDEMPOTENT',
    'Anticipo de prueba'
  ),
  current_setting('test.payroll.advance_receipt')::jsonb,
  'advance replay is stable across caller session timezones'
);

set local timezone = 'UTC';

reset role;

select throws_ok(
  $$
    update public.employee_advances
    set amount = amount + 1,
        payment_method_id =
          '7f281000-0000-4000-8000-000000000402',
        paid_at = paid_at + interval '1 day'
    where id = (
      current_setting('test.payroll.advance_receipt')::jsonb
        ->>'advance_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'a v2-created advance cannot change amount, method, or paid-at evidence'
);

select throws_ok(
  $$
    delete from public.employee_advances
    where id = (
      current_setting('test.payroll.advance_receipt')::jsonb
        ->>'advance_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'a v2-created advance cannot be deleted behind its stored receipt'
);

set local role authenticated;

select set_config(
  'test.statement.source_metadata',
  jsonb_build_object(
    'parser_name',
    'payroll_statement_parser',
    'parser_version',
    '1',
    'source_type',
    'pdf_text',
    'page_count',
    5,
    'extraction_kind',
    'embedded_text',
    'locale',
    'es-CL',
    'account_fingerprint',
    repeat('1', 64),
    'erp_account_id',
    '7f281000-0000-4000-8000-000000000301'
  )::text,
  true
);

select set_config(
  'test.statement.main_rows',
  jsonb_build_array(
    jsonb_build_object(
      'ordinal',
      1,
      'page',
      5,
      'source_line_start',
      44,
      'source_line_end',
      44,
      'transaction_date',
      '2026-07-27',
      'direction',
      'debit',
      'amount',
      128000,
      'description_observed',
      'App-traspaso A: Vicente Díaz',
      'beneficiary_observed',
      'Vicente Díaz',
      'document_number',
      'DOC-128000',
      'source_occurrence',
      1,
      'warnings',
      '[]'::jsonb
    ),
    jsonb_build_object(
      'ordinal',
      2,
      'page',
      4,
      'source_line_start',
      18,
      'source_line_end',
      18,
      'transaction_date',
      '2026-07-13',
      'direction',
      'debit',
      'amount',
      22000,
      'description_observed',
      'App-traspaso A: Vicente Díaz',
      'beneficiary_observed',
      'Vicente Díaz',
      'document_number',
      'DOC-22000',
      'source_occurrence',
      1,
      'warnings',
      '[]'::jsonb
    )
  )::text,
  true
);

select set_config(
  'test.statement.import_receipt',
  public.create_payroll_statement_import(
    'import-main-0001',
    repeat('a', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    current_setting('test.statement.main_rows')::jsonb
  )::text,
  true
);

select is(
  (
    current_setting('test.statement.import_receipt')::jsonb
      ->>'row_count'
  )::integer,
  2,
  'import stores every normalized statement row in review'
);

select ok(
  jsonb_array_length(
    current_setting('test.statement.import_receipt')::jsonb->'rows'
  ) = 2
  and (
    current_setting('test.statement.import_receipt')::jsonb
      ->'rows'->0->>'row_id'
  ) is not null
  and (
    current_setting('test.statement.import_receipt')::jsonb
      ->'rows'->0->>'fingerprint'
  ) ~ '^[0-9a-f]{64}$',
  'import receipt maps each parser ordinal and fingerprint to its server row UUID'
);

select is(
  (
    select status
    from public.payroll_statement_imports
    where id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
  ),
  'review',
  'OCR/parser import alone remains review-only'
);

select is(
  (
    select count(*)::integer
    from public.payroll_statement_account_mappings
    where tenant_id = '7f281000-0000-4000-8000-000000000001'
  ),
  0,
  'review-only OCR cannot confirm or poison the bank account fingerprint mapping'
);

select is(
  (
    public.create_payroll_statement_import(
      'import-main-0001',
      repeat('a', 64),
      current_setting('test.statement.source_metadata')::jsonb,
      current_setting('test.statement.main_rows')::jsonb
    )->>'import_id'
  ),
  (
    current_setting('test.statement.import_receipt')::jsonb
      ->>'import_id'
  ),
  'an identical import operation retry returns the original receipt'
);

select is(
  (
    public.create_payroll_statement_import(
      'import-main-retry-0002',
      repeat('a', 64),
      current_setting('test.statement.source_metadata')::jsonb,
      current_setting('test.statement.main_rows')::jsonb
    )->>'import_id'
  ),
  (
    current_setting('test.statement.import_receipt')::jsonb
      ->>'import_id'
  ),
  'the same tenant and PDF digest deduplicate even with a new operation key'
);

select set_config(
  'test.statement.reparse_v1',
  public.create_payroll_statement_import(
    'import-reparse-0001',
    repeat('e', 64),
    jsonb_set(
      current_setting('test.statement.source_metadata')::jsonb,
      '{account_fingerprint}',
      to_jsonb(repeat('2', 64))
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-25',
        'direction', 'debit',
        'amount', 7777,
        'description_observed', 'OCR inicial incorrecto'
      )
    )
  )::text,
  true
);

select set_config(
  'test.statement.reparse_v2',
  public.create_payroll_statement_import(
    'import-reparse-0002',
    repeat('e', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-25',
        'direction', 'debit',
        'amount', 7777,
        'description_observed', 'OCR corregido y revisado'
      )
    )
  )::text,
  true
);

select ok(
  current_setting('test.statement.reparse_v1')::jsonb
    ->>'import_id'
    = current_setting('test.statement.reparse_v2')::jsonb
      ->>'import_id'
  and (
    current_setting('test.statement.reparse_v2')::jsonb
      ->>'revision'
  )::integer = 2
  and (
    current_setting('test.statement.reparse_v2')::jsonb
      ->>'revised'
  )::boolean
  and not exists (
    select 1
    from public.payroll_statement_rows statement_row
    where statement_row.id = (
      current_setting('test.statement.reparse_v1')::jsonb
        ->'rows'->0->>'row_id'
    )::uuid
  ),
  'a corrected parser pass atomically replaces only a review revision'
);

select throws_ok(
  $$
    select public.create_payroll_statement_import(
      'import-reparse-0001',
      repeat('e', 64),
      jsonb_set(
        current_setting('test.statement.source_metadata')::jsonb,
        '{account_fingerprint}',
        to_jsonb(repeat('2', 64))
      ),
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'transaction_date', '2026-07-25',
          'direction', 'debit',
          'amount', 7777,
          'description_observed', 'OCR inicial incorrecto'
        )
      )
    )
  $$,
  '40001',
  'payroll_statement_import_revision_superseded',
  'a stale create retry cannot restore invalidated OCR row IDs'
);

select set_config(
  'test.statement.identical_rows_import',
  public.create_payroll_statement_import(
    'import-identical-rows-0001',
    repeat('f', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-24',
        'direction', 'debit',
        'amount', 5555,
        'description_observed', 'Dos cargos sin documento',
        'source_occurrence', 1
      ),
      jsonb_build_object(
        'ordinal', 2,
        'transaction_date', '2026-07-24',
        'direction', 'debit',
        'amount', 5555,
        'description_observed', 'Dos cargos sin documento',
        'source_occurrence', 2
      )
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.statement.identical_rows_import')::jsonb
      ->>'row_count'
  )::integer = 2
  and (
    select count(distinct statement_row.fingerprint) = 2
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.identical_rows_import')::jsonb
        ->>'import_id'
    )::uuid
  )
  and (
    select array_agg(
      statement_row.source_occurrence
      order by statement_row.row_ordinal
    ) = array[1, 2]
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.identical_rows_import')::jsonb
        ->>'import_id'
    )::uuid
  ),
  'stable source occurrence distinguishes two legitimate identical bank rows'
);

select set_config(
  'test.statement.identical_rows_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.identical_rows_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-identical-rows-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'ignore',
        'row_id', (
          current_setting('test.statement.identical_rows_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'manual_confirmation', true,
        'reason', 'Primer cargo idéntico revisado por separado'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'action', 'hold',
        'row_id', (
          current_setting('test.statement.identical_rows_import')::jsonb
            ->'rows'->1->>'row_id'
        ),
        'manual_confirmation', true,
        'reason', 'Segundo cargo idéntico retenido por separado'
      )
    ),
    '{}'::jsonb
  )::text,
  true
);

select ok(
  current_setting('test.statement.identical_rows_apply')::jsonb
    ->>'status' = 'held'
  and (
    current_setting('test.statement.identical_rows_apply')::jsonb
      ->>'decision_count'
  )::integer = 2
  and (
    select count(distinct decision.row_fingerprint) = 2
    from public.payroll_statement_decisions decision
    where decision.import_id = (
      current_setting('test.statement.identical_rows_import')::jsonb
        ->>'import_id'
    )::uuid
      and decision.outcome in ('acknowledged', 'held')
  ),
  'identical rows retain independent reviewed dispositions'
);

select throws_ok(
  $$
    select public.create_payroll_statement_import(
      'import-forged-occurrence-0001',
      '3b947fc1eac5fb11bb50a5444d12c0ac376e99c88018f53b039d745022d824f3',
      current_setting('test.statement.source_metadata')::jsonb,
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'transaction_date', '2026-07-24',
          'direction', 'debit',
          'amount', 5555,
          'description_observed', 'Ocurrencia manipulada',
          'source_occurrence', 2
        )
      )
    )
  $$,
  '22023',
  'payroll_statement_source_occurrence_mismatch_1',
  'a caller cannot forge source occurrence to bypass cross-statement dedupe'
);

select throws_ok(
  $$
    select public.create_payroll_statement_import(
      'import-main-0001',
      repeat('a', 64),
      current_setting('test.statement.source_metadata')::jsonb,
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'transaction_date', '2026-07-27',
          'direction', 'debit',
          'amount', 1,
          'description_observed', 'Changed payload'
        )
      )
    )
  $$,
  'P0001',
  'payroll_statement_import_idempotency_conflict',
  'reusing an import operation key with another payload fails closed'
);

select throws_ok(
  $$
    select public.create_payroll_statement_import(
      'import-invalid-0001',
      repeat('9', 64),
      current_setting('test.statement.source_metadata')::jsonb,
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'transaction_date', '2026-07-27',
          'direction', 'debit',
          'amount', -1,
          'description_observed', 'Invalid negative amount'
        )
      )
    )
  $$,
  '22023',
  'payroll_statement_invalid_row_1',
  'invalid parser rows fail before any import receipt can be retained'
);

select is(
  (
    select count(*)::integer
    from public.payroll_statement_imports
    where create_operation_key = 'import-invalid-0001'
  ),
  0,
  'an invalid parser row rolls back its provisional import atomically'
);

select is(
  (select count(*)::integer from public.expense_payments),
  0,
  'importing OCR/parser output never creates a payment'
);

select set_config(
  'test.statement.decisions',
  (
    select jsonb_build_array(
      jsonb_build_object(
        'ordinal',
        1,
        'action',
        'bank_payment',
        'row_id',
        (
          select statement_row.id
          from public.payroll_statement_rows statement_row
          where statement_row.import_id = statement_import.id
            and statement_row.row_ordinal = 1
        ),
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000601',
        'payment_method_id',
        '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
        '7f281000-0000-4000-8000-000000000301',
        'applied_amount',
        127750,
        'variance_disposition',
        'unresolved',
        'manual_confirmation',
        true,
        'reason',
        'Diferencia de CLP 250 revisada contra la obligación'
      ),
      jsonb_build_object(
        'ordinal',
        2,
        'action',
        'ignore',
        'row_fingerprint',
        (
          current_setting('test.statement.import_receipt')::jsonb
            ->'rows'->1->>'fingerprint'
        ),
        'reason',
        'Transferencia para gestión, no corresponde a sueldo'
      ),
      jsonb_build_object(
        'ordinal',
        3,
        'action',
        'cash_payment',
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000602',
        'payment_method_id',
        '7f281000-0000-4000-8000-000000000402',
        'payment_account_id',
        '7f281000-0000-4000-8000-000000000302',
        'applied_amount',
        38000,
        'payment_date',
        '2026-07-27',
        'manual_confirmation',
        true
      ),
      jsonb_build_object(
        'ordinal',
        4,
        'action',
        'advance_allocation',
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000603',
        'advance_id',
        '7f281000-0000-4000-8000-000000000701',
        'applied_amount',
        36000
      ),
      jsonb_build_object(
        'ordinal',
        5,
        'action',
        'not_paid',
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000604',
        'manual_confirmation',
        true,
        'reason',
        'Efectivo aún no entregado'
      )
    )::text
    from public.payroll_statement_imports statement_import
    where statement_import.id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
  ),
  true
);

select set_config(
  'test.statement.expected_versions',
  jsonb_build_object(
    '7f281000-0000-4000-8000-000000000501',
    (
      select reconciliation_version
      from public.payroll_vouchers
      where id = '7f281000-0000-4000-8000-000000000501'
    ),
    '7f281000-0000-4000-8000-000000000502',
    (
      select reconciliation_version
      from public.payroll_vouchers
      where id = '7f281000-0000-4000-8000-000000000502'
    ),
    '7f281000-0000-4000-8000-000000000503',
    (
      select reconciliation_version
      from public.payroll_vouchers
      where id = '7f281000-0000-4000-8000-000000000503'
    ),
    '7f281000-0000-4000-8000-000000000504',
    (
      select reconciliation_version
      from public.payroll_vouchers
      where id = '7f281000-0000-4000-8000-000000000504'
    )
  )::text,
  true
);

select throws_ok(
  $$
    update public.payroll_voucher_lines
    set employee_name = employee_name
    where id = '7f281000-0000-4000-8000-000000000606'
  $$,
  '42501',
  'permission denied for table payroll_voucher_lines',
  'direct line mutation cannot race the versioned full-snapshot draft command'
);

reset role;
update public.employees
set status = 'inactive',
    preferred_payment_method = 'cash',
    preferred_payment_method_id =
      '7f281000-0000-4000-8000-000000000402'
where id = '7f281000-0000-4000-8000-000000000201';
set local role authenticated;

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.import_receipt')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-main-missing-draft-authorization-0001',
      current_setting('test.statement.decisions')::jsonb,
      current_setting('test.statement.expected_versions')::jsonb,
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000501',
        '7f281000-0000-4000-8000-000000000502',
        '7f281000-0000-4000-8000-000000000503'
      )
    )
  $$,
  '22023',
  'payroll_statement_draft_commitment_authorization_mismatch',
  'apply rejects a touched draft omitted from the explicit commitment allow-list'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.import_receipt')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-main-extra-draft-authorization-0001',
      current_setting('test.statement.decisions')::jsonb,
      current_setting('test.statement.expected_versions')::jsonb,
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000501',
        '7f281000-0000-4000-8000-000000000502',
        '7f281000-0000-4000-8000-000000000503',
        '7f281000-0000-4000-8000-000000000504',
        '7f281000-0000-4000-8000-000000000505'
      )
    )
  $$,
  '22023',
  'payroll_statement_draft_commitment_authorization_mismatch',
  'apply rejects an extra draft not touched by the reviewed decisions'
);

select set_config(
  'test.statement.apply_receipt',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-main-0001',
    current_setting('test.statement.decisions')::jsonb,
    current_setting('test.statement.expected_versions')::jsonb,
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000501',
      '7f281000-0000-4000-8000-000000000502',
      '7f281000-0000-4000-8000-000000000503',
      '7f281000-0000-4000-8000-000000000504'
    )
  )::text,
  true
);

select is(
  current_setting('test.statement.apply_receipt')::jsonb
    ->'committed_voucher_ids',
  jsonb_build_array(
    '7f281000-0000-4000-8000-000000000501',
    '7f281000-0000-4000-8000-000000000502',
    '7f281000-0000-4000-8000-000000000503',
    '7f281000-0000-4000-8000-000000000504'
  ),
  'the apply receipt returns the exact deterministic set of drafts committed'
);

select is(
  (
    current_setting('test.statement.apply_receipt')::jsonb
      ->>'allocation_count'
  )::integer,
  3,
  'one reviewed apply atomically creates bank, cash, and advance allocations'
);

select is(
  (
    select status
    from public.employees
    where id = '7f281000-0000-4000-8000-000000000201'
  ),
  'inactive',
  'historical liabilities remain payable after an employee is deactivated'
);

select ok(
  (
    select employee.preferred_payment_method_id =
      '7f281000-0000-4000-8000-000000000402'
    from public.employees employee
    where employee.id = '7f281000-0000-4000-8000-000000000201'
  )
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.expense_payments payment
      on payment.id = allocation.expense_payment_id
    where allocation.voucher_line_id =
        '7f281000-0000-4000-8000-000000000601'
      and payment.payment_method_id =
        '7f281000-0000-4000-8000-000000000401'
      and payment.payment_account_id =
        '7f281000-0000-4000-8000-000000000301'
  ),
  'historical settlement follows the locked line method and account, not a later employee preference'
);

select ok(
  current_setting('test.statement.apply_receipt')::jsonb
    ->>'status' = 'applied_with_variances'
  and (
    current_setting('test.statement.apply_receipt')::jsonb
      ->>'unresolved_variance_count'
  )::integer = 1
  and (
    current_setting('test.statement.apply_receipt')::jsonb
      ->>'unresolved_variance_total'
  )::numeric = 250
  and (
    select status
    from public.payroll_statement_imports
    where id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
  ) = 'applied_with_variances',
  'a reviewed approximate match is not reported as fully reconciled'
);

select ok(
  exists (
    select 1
    from public.payroll_statement_account_mappings account_mapping
    where account_mapping.tenant_id =
        '7f281000-0000-4000-8000-000000000001'
      and account_mapping.erp_account_id =
        '7f281000-0000-4000-8000-000000000301'
      and account_mapping.account_fingerprint = repeat('1', 64)
  )
  and (
    select count(*) = 1
    from public.payroll_statement_account_mappings account_mapping
    where account_mapping.tenant_id =
      '7f281000-0000-4000-8000-000000000001'
  ),
  'a successful apply atomically confirms one bank-account fingerprint mapping'
);

select set_config(
  'test.statement.account_replay_import',
  public.create_payroll_statement_import(
    'import-account-replay-0001',
    '28e08fde692befdcb7e6bf7236926c70435e391eed5f307e556aee9ebc6c4bd3',
    jsonb_set(
      current_setting('test.statement.source_metadata')::jsonb,
      '{account_fingerprint}',
      to_jsonb(repeat('2', 64))
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 3333,
        'description_observed', 'Hash anterior no confirmado',
        'document_number', 'ACCOUNT-REPLAY-1'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting(
          'test.statement.account_replay_import'
        )::jsonb->>'import_id'
      )::uuid,
      'apply-account-replay-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'ignore',
          'row_id', (
            current_setting(
              'test.statement.account_replay_import'
            )::jsonb->'rows'->0->>'row_id'
          ),
          'reason', 'No es sueldo'
        )
      ),
      '{}'::jsonb
    )
  $$,
  '23514',
  'payroll_statement_account_fingerprint_mismatch',
  'an old review-only account hash cannot replay after another hash is confirmed'
);

select ok(
  exists (
    select 1
    from public.payroll_statement_allocations allocation
    where allocation.import_id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.action = 'bank_payment'
      and allocation.bank_amount = 128000
      and allocation.applied_amount = 127750
      and allocation.variance = 250
      and allocation.variance_disposition = 'unresolved'
  ),
  'the CLP 250 excess stays explicit instead of disappearing'
);

select ok(
  exists (
    select 1
    from public.payroll_statement_decisions decision
    join public.payroll_statement_rows statement_row
      on statement_row.id = decision.row_id
    where decision.import_id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
      and statement_row.amount = 22000
      and decision.action = 'ignore'
      and decision.outcome = 'acknowledged'
  )
  and not exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.payroll_statement_rows statement_row
      on statement_row.id = allocation.row_id
    where statement_row.amount = 22000
  ),
  'the non-payroll CLP 22,000 transfer is acknowledged without paying salary'
);

select ok(
  exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.expense_payments payment
      on payment.id = allocation.expense_payment_id
    where allocation.action = 'cash_payment'
      and allocation.voucher_line_id =
        '7f281000-0000-4000-8000-000000000602'
      and payment.payment_method_id =
        '7f281000-0000-4000-8000-000000000402'
      and payment.amount = 38000
      and (
        payment.payment_date at time zone 'America/Santiago'
      )::date = date '2026-07-27'
  ),
  'cash payment exists only after an explicit manual confirmation and civil date'
);

select ok(
  exists (
    select 1
    from public.employee_advances advance
    join public.employee_advance_allocations allocation
      on allocation.advance_id = advance.id
    where advance.id = '7f281000-0000-4000-8000-000000000701'
      and advance.status = 'applied'
      and advance.amount_applied = 36000
      and allocation.voucher_line_id =
        '7f281000-0000-4000-8000-000000000603'
  ),
  'a selected existing advance allocates to the same worker liability'
);

select ok(
  exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.journal_entries journal_entry
      on journal_entry.source_module = 'expense_payments'
     and journal_entry.source_reference =
          allocation.expense_payment_id::text
    where allocation.action = 'bank_payment'
      and exists (
        select 1
        from public.journal_lines journal_line
        where journal_line.entry_id = journal_entry.id
          and journal_line.account_id =
            '7f281000-0000-4000-8000-000000000304'
          and journal_line.debit_amount = 127750
      )
      and exists (
        select 1
        from public.journal_lines journal_line
        where journal_line.entry_id = journal_entry.id
          and journal_line.account_id =
            '7f281000-0000-4000-8000-000000000301'
          and journal_line.credit_amount = 127750
      )
  )
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.journal_entries journal_entry
      on journal_entry.source_module = 'expense_payments'
     and journal_entry.source_reference =
          allocation.expense_payment_id::text
    where allocation.action = 'cash_payment'
      and exists (
        select 1
        from public.journal_lines journal_line
        where journal_line.entry_id = journal_entry.id
          and journal_line.account_id =
            '7f281000-0000-4000-8000-000000000304'
          and journal_line.debit_amount = 38000
      )
      and exists (
        select 1
        from public.journal_lines journal_line
        where journal_line.entry_id = journal_entry.id
          and journal_line.account_id =
            '7f281000-0000-4000-8000-000000000302'
          and journal_line.credit_amount = 38000
      )
  )
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.journal_entries journal_entry
      on journal_entry.source_module = 'employee_advance_allocations'
     and journal_entry.source_reference =
          allocation.employee_advance_allocation_id::text
    where allocation.action = 'advance_allocation'
      and exists (
        select 1
        from public.journal_lines journal_line
        where journal_line.entry_id = journal_entry.id
          and journal_line.account_code = '2106'
          and journal_line.debit_amount = 36000
      )
      and exists (
        select 1
        from public.journal_lines journal_line
        where journal_line.entry_id = journal_entry.id
          and journal_line.account_code = '1135'
          and journal_line.credit_amount = 36000
      )
  ),
  'bank, cash, and advance settlements post to reviewed accounting accounts'
);

select ok(
  (
    select status = 'confirmed'
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000504'
  )
  and not exists (
    select 1
    from public.expense_payments payment
    join public.payroll_voucher_lines voucher_line
      on voucher_line.expense_id = payment.expense_id
    where voucher_line.id =
      '7f281000-0000-4000-8000-000000000604'
  ),
  'not_paid recognizes the liability but creates no cash movement'
);

select is(
  (
    select count(*)::integer
    from public.payroll_vouchers
    where id in (
      '7f281000-0000-4000-8000-000000000501',
      '7f281000-0000-4000-8000-000000000502',
      '7f281000-0000-4000-8000-000000000503'
    )
      and status = 'paid'
  ),
  3,
  'fully settled bank, cash, and advance vouchers become paid'
);

select is(
  (
    select count(*)::integer
    from public.expense_payments
    where reference like 'payroll-statement:%'
  ),
  2,
  'each bank or cash decision has one uniquely linked expense payment'
);

select is(
  (
    current_setting('test.statement.apply_receipt')::jsonb
      ->>'replayed'
  )::boolean,
  false,
  'the first apply receipt is explicitly distinguished from a replay'
);

select set_config(
  'test.statement.apply_replay_receipt',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-main-0001',
    current_setting('test.statement.decisions')::jsonb,
    current_setting('test.statement.expected_versions')::jsonb,
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000501',
      '7f281000-0000-4000-8000-000000000502',
      '7f281000-0000-4000-8000-000000000503',
      '7f281000-0000-4000-8000-000000000504'
    )
  )::text,
  true
);

select is(
  (
    current_setting('test.statement.apply_replay_receipt')::jsonb
      ->>'replayed'
  )::boolean,
  true,
  'an identical apply acknowledgement retry declares the replay'
);

select is(
  current_setting('test.statement.apply_replay_receipt')::jsonb
    - 'replayed',
  current_setting('test.statement.apply_receipt')::jsonb
    - 'replayed',
  'an identical apply acknowledgement retry preserves the stored financial receipt'
);

select is(
  (
    select count(*)::integer
    from public.payroll_statement_allocations
    where import_id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
  ),
  3,
  'an apply acknowledgement retry never duplicates accounting movements'
);

select throws_ok(
  $$
    insert into public.expense_payments (
      tenant_id,
      expense_id,
      payment_method_id,
      payment_account_id,
      amount,
      payment_date,
      reference
    )
    select
      voucher_line.tenant_id,
      voucher_line.expense_id,
      '7f281000-0000-4000-8000-000000000402',
      '7f281000-0000-4000-8000-000000000302',
      1,
      '2026-07-27 12:00:00+00',
      'DIRECT-BYPASS'
    from public.payroll_voucher_lines voucher_line
    where voucher_line.id =
      '7f281000-0000-4000-8000-000000000604'
  $$,
  '42501',
  'payroll_money_command_required',
  'a direct payroll expense payment cannot bypass the idempotent money command'
);

select throws_ok(
  $$
    select public.pay_payroll_voucher_v2(
      '7f281000-0000-4000-8000-000000000504',
      'manual-pay-split-limit-0001',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000504'
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000604',
        (
          select jsonb_agg(
            jsonb_build_object(
              'kind', 'payment',
              'amount', 0.01,
              'payment_method_id',
                '7f281000-0000-4000-8000-000000000402',
              'payment_account_id',
                '7f281000-0000-4000-8000-000000000302',
              'payment_date', '2026-07-27 12:00:00+00',
              'reference', 'V2-SPLIT-LIMIT'
            )
            order by split_ordinal
          )
          from generate_series(1, 51) split_ordinal
        )
      )
    )
  $$,
  '22023',
  'payroll_payment_payload_limit',
  'one money command cannot fan out into an unbounded number of movements'
);

select is(
  (
    select count(*)::integer
    from public.expense_payments payment
    join public.payroll_voucher_lines voucher_line
      on voucher_line.expense_id = payment.expense_id
    where voucher_line.id =
      '7f281000-0000-4000-8000-000000000604'
  ),
  0,
  'an over-limit split payload creates no payroll movement'
);

select throws_ok(
  $$
    select public.pay_payroll_voucher_v2(
      '7f281000-0000-4000-8000-000000000504',
      'manual-pay-no-zone-0001',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000504'
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000604',
        jsonb_build_array(
          jsonb_build_object(
            'kind', 'payment',
            'amount', 1,
            'payment_method_id',
              '7f281000-0000-4000-8000-000000000402',
            'payment_account_id',
              '7f281000-0000-4000-8000-000000000302',
            'payment_date', '2026-07-27 12:00:00',
            'reference', 'V2-NO-TIMEZONE'
          )
        )
      )
    )
  $$,
  '22023',
  'payroll_payment_invalid_splits',
  'manual payment instants require an explicit UTC or numeric offset'
);

select throws_ok(
  $$
    select public.pay_payroll_voucher_v2(
      '7f281000-0000-4000-8000-000000000504',
      'manual-pay-over-0001',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000504'
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000604',
        jsonb_build_array(
          jsonb_build_object(
            'kind', 'payment',
            'amount', 10001,
            'payment_method_id',
              '7f281000-0000-4000-8000-000000000402',
            'payment_account_id',
              '7f281000-0000-4000-8000-000000000302',
            'payment_date', '2026-07-27 12:00:00+00',
            'reference', 'V2-OVERPAY'
          )
        )
      )
    )
  $$,
  '23514',
  'payroll_expense_payment_exceeds_line_balance',
  'the idempotent money command still cannot exceed the live payroll balance'
);

select set_config(
  'test.payroll.manual_payment_version',
  (
    select reconciliation_version::text
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000504'
  ),
  true
);

select set_config(
  'test.payroll.manual_payment_receipt',
  public.pay_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000504',
    'manual-pay-create-0001',
    current_setting('test.payroll.manual_payment_version')::bigint,
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000604',
      jsonb_build_array(
        jsonb_build_object(
          'kind', 'payment',
          'amount', 10000,
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000402',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000302',
          'payment_date', '2026-07-27 12:00:00+00',
          'reference', 'V2-MANUAL-PAY'
        )
      )
    )
  )::text,
  true
);

select ok(
  current_setting('test.payroll.manual_payment_receipt')::jsonb
    ->>'status' = 'paid'
  and (
    current_setting('test.payroll.manual_payment_receipt')::jsonb
      ->>'payment_count'
  )::integer = 1
  and (
    current_setting('test.payroll.manual_payment_receipt')::jsonb
      ->>'payment_total'
  )::numeric = 10000
  and exists (
    select 1
    from public.expense_payments payment
    where payment.id = (
      current_setting('test.payroll.manual_payment_receipt')::jsonb
        ->'expense_payments'->0->>'payment_id'
    )::uuid
      and payment.amount = 10000
  ),
  'not_paid can later settle through one idempotent manual payment receipt'
);

select is(
  public.pay_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000504',
    'manual-pay-create-0001',
    current_setting('test.payroll.manual_payment_version')::bigint,
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000604',
      jsonb_build_array(
        jsonb_build_object(
          'kind', 'payment',
          'amount', 10000,
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000402',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000302',
          'payment_date', '2026-07-27 12:00:00+00',
          'reference', 'V2-MANUAL-PAY'
        )
      )
    )
  ),
  current_setting('test.payroll.manual_payment_receipt')::jsonb,
  'lost acknowledgement retry returns the exact manual money receipt'
);

select is(
  (
    select count(*)::integer
    from public.payroll_money_operations money_operation
    join public.payroll_money_operation_movements movement
      on movement.operation_id = money_operation.id
     and movement.tenant_id = money_operation.tenant_id
    where money_operation.operation_key = 'manual-pay-create-0001'
      and money_operation.tenant_id =
        '7f281000-0000-4000-8000-000000000001'
  ),
  (
    (
      current_setting('test.payroll.manual_payment_receipt')::jsonb
        ->>'payment_count'
    )::integer
    + (
      current_setting('test.payroll.manual_payment_receipt')::jsonb
        ->>'advance_allocation_count'
    )::integer
  ),
  'every movement in the manual money receipt has one tenant-safe relational link'
);

reset role;

select throws_ok(
  $$
    update public.expense_payments
    set amount = amount
    where id = (
      current_setting('test.payroll.manual_payment_receipt')::jsonb
        ->'expense_payments'->0->>'payment_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'a v2-created expense payment cannot be changed behind its stored receipt'
);

select throws_ok(
  $$
    delete from public.expense_payments
    where id = (
      current_setting('test.payroll.manual_payment_receipt')::jsonb
        ->'expense_payments'->0->>'payment_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'a v2-created expense payment cannot be deleted behind its stored receipt'
);

set local role authenticated;

select is(
  public.pay_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000504',
    'manual-pay-create-0001',
    current_setting('test.payroll.manual_payment_version')::bigint,
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000604',
      jsonb_build_array(
        jsonb_build_object(
          'kind', 'payment',
          'amount', 10000,
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000402',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000302',
          'payment_date', '2026-07-27 12:00:00+00',
          'reference', 'V2-MANUAL-PAY'
        )
      )
    )
  ),
  current_setting('test.payroll.manual_payment_receipt')::jsonb,
  'a replay after rejected mutations still returns a receipt whose movement is live'
);

select throws_ok(
  $$
    select public.revert_payroll_payment(
      '7f281000-0000-4000-8000-000000000504'
    )
  $$,
  '55000',
  'payroll_reconciliation_requires_audited_reversal',
  'legacy reversal cannot invalidate a v2 money-operation receipt'
);

select ok(
  exists (
    select 1
    from public.expense_payments payment
    where payment.id = (
      current_setting('test.payroll.manual_payment_receipt')::jsonb
        ->'expense_payments'->0->>'payment_id'
    )::uuid
  ),
  'the stored manual payment receipt still points to a live movement after rejected reversal'
);

reset role;

select throws_ok(
  $$
    update public.payroll_voucher_lines
    set total_amount = total_amount + 1
    where id = '7f281000-0000-4000-8000-000000000601'
  $$,
  '55000',
  'payroll_reconciled_voucher_is_immutable',
  'a reconciled voucher line cannot diverge from its receipt'
);

select throws_ok(
  $$
    update public.employee_advance_allocations
    set amount = amount
    where id = (
      select allocation.employee_advance_allocation_id
      from public.payroll_statement_allocations allocation
      where allocation.action = 'advance_allocation'
      limit 1
    )
  $$,
  '55000',
  'payroll_reconciled_advance_allocation_is_immutable',
  'a linked advance allocation remains immutable after apply'
);

select throws_ok(
  $$
    update public.expense_payments
    set amount = amount
    where id = (
      select allocation.expense_payment_id
      from public.payroll_statement_allocations allocation
      where allocation.action = 'bank_payment'
      limit 1
    )
  $$,
  '55000',
  'payroll_reconciled_payment_is_immutable',
  'a linked expense payment remains immutable after apply'
);

set local role authenticated;

select throws_ok(
  $$
    select public.revert_payroll_payment(
      '7f281000-0000-4000-8000-000000000501'
    )
  $$,
  '55000',
  'payroll_reconciliation_requires_audited_reversal',
  'legacy payment reversal cannot erase reconciliation evidence'
);

select throws_ok(
  $$
    select public.revert_payroll_to_draft(
      '7f281000-0000-4000-8000-000000000504'
    )
  $$,
  '55000',
  'payroll_reconciliation_requires_audited_reversal',
  'a final not-paid decision cannot be reverted to a mutable draft'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.import_receipt')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-main-0001',
      jsonb_set(
        current_setting('test.statement.decisions')::jsonb,
        '{1,reason}',
        '"Changed acknowledgement"'::jsonb,
        true
      ),
      current_setting('test.statement.expected_versions')::jsonb,
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000501',
        '7f281000-0000-4000-8000-000000000502',
        '7f281000-0000-4000-8000-000000000503',
        '7f281000-0000-4000-8000-000000000504'
      )
    )
  $$,
  'P0001',
  'payroll_statement_apply_idempotency_conflict',
  'an apply operation key cannot acknowledge another decision payload'
);

-- A second import simulates a stale browser after another payroll edit.
select set_config(
  'test.statement.stale_import',
  public.create_payroll_statement_import(
    'import-stale-0001',
    repeat('b', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal',
        1,
        'transaction_date',
        '2026-07-27',
        'direction',
        'debit',
        'amount',
        1000,
        'description_observed',
        'Unique stale payment',
        'beneficiary_observed',
        'Vicente Díaz'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.stale_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-stale-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal',
          1,
          'action',
          'bank_payment',
          'row_id',
          (
            select statement_row.id
            from public.payroll_statement_rows statement_row
            where statement_row.import_id = (
              current_setting('test.statement.stale_import')::jsonb
                ->>'import_id'
            )::uuid
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000606',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount',
          1000,
          'variance_disposition',
          'exact'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000506',
        (
          select reconciliation_version + 1
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000506'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000506'
      )
    )
  $$,
  '40001',
  'payroll_statement_voucher_version_conflict',
  'a stale expected voucher version fails before any payment'
);

select is(
  (
    select count(*)::integer
    from public.payroll_statement_decisions
    where import_id = (
      current_setting('test.statement.stale_import')::jsonb
        ->>'import_id'
    )::uuid
  ),
  0,
  'version conflict rolls back its provisional decisions'
);

-- A different file containing the same canonical bank transaction gets the
-- same server fingerprint. The unique applied-fingerprint boundary handles a
-- race even if two overlapping imports pass an earlier read check.
select set_config(
  'test.statement.duplicate_import',
  public.create_payroll_statement_import(
    'import-duplicate-0001',
    repeat('c', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal',
        1,
        'page',
        5,
        'source_line_start',
        99,
        'source_line_end',
        99,
        'transaction_date',
        '2026-07-27',
        'direction',
        'debit',
        'amount',
        128000,
        'description_observed',
        'App-traspaso A: Vicente Díaz',
        'beneficiary_observed',
        'Vicente Díaz',
        'document_number',
        'DOC-128000',
        'source_occurrence',
        1,
        'warnings',
        '[]'::jsonb
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.duplicate_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-duplicate-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal',
          1,
          'action',
          'bank_payment',
          'row_id',
          (
            select statement_row.id
            from public.payroll_statement_rows statement_row
            where statement_row.import_id = (
              current_setting('test.statement.duplicate_import')::jsonb
                ->>'import_id'
            )::uuid
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000607',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount',
          127750,
          'variance_disposition',
          'unresolved',
          'manual_confirmation',
          true,
          'reason',
          'Intento duplicado revisado'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000507',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000507'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000507'
      )
    )
  $$,
  'P0001',
  'payroll_statement_row_already_resolved',
  'an overlapping statement fingerprint can never pay payroll twice'
);

select is(
  (
    select count(*)::integer
    from public.expense_payments payment
    join public.payroll_voucher_lines voucher_line
      on voucher_line.expense_id = payment.expense_id
    where voucher_line.id =
      '7f281000-0000-4000-8000-000000000607'
  ),
  0,
  'duplicate-fingerprint rejection rolls back before payment'
);

select set_config(
  'test.statement.duplicate_resolution_receipt',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.duplicate_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-duplicate-resolve-0002',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'already_resolved',
        'row_id', (
          current_setting('test.statement.duplicate_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'prior_decision_id', (
          select decision.id
          from public.payroll_statement_decisions decision
          where decision.import_id = (
            current_setting('test.statement.import_receipt')::jsonb
              ->>'import_id'
          )::uuid
            and decision.action = 'bank_payment'
        ),
        'reason', 'Movimiento ya resuelto en la cartola principal'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'action', 'not_paid',
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000607',
        'manual_confirmation', true,
        'reason', 'Saldo reservado para imputar un anticipo'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000507',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000507'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000507'
    )
  )::text,
  true
);

select set_config(
  'test.payroll.manual_advance_version',
  (
    select reconciliation_version::text
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000507'
  ),
  true
);

select set_config(
  'test.payroll.manual_advance_receipt',
  public.pay_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000507',
    'manual-advance-apply-0001',
    current_setting('test.payroll.manual_advance_version')::bigint,
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000607',
      jsonb_build_array(
        jsonb_build_object(
          'kind', 'advance',
          'amount', 1000,
          'advance_id', (
            current_setting('test.payroll.advance_receipt')::jsonb
              ->>'advance_id'
          ),
          'notes', 'Imputación v2 protegida por comprobante'
        )
      )
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.payroll.manual_advance_receipt')::jsonb
      ->>'advance_allocation_count'
  )::integer = 1
  and (
    current_setting('test.payroll.manual_advance_receipt')::jsonb
      ->>'advance_allocation_total'
  )::numeric = 1000
  and (
    select count(*) = 1
    from public.payroll_money_operations money_operation
    join public.payroll_money_operation_movements movement
      on movement.operation_id = money_operation.id
     and movement.tenant_id = money_operation.tenant_id
    where money_operation.operation_key = 'manual-advance-apply-0001'
      and movement.movement_type = 'advance_allocation'
      and movement.advance_allocation_id = (
        current_setting('test.payroll.manual_advance_receipt')::jsonb
          ->'advance_allocations'->0->>'allocation_id'
      )::uuid
  )
  and (
    select (
      allocation.applied_at at time zone 'America/Santiago'
    ) = timestamp '2026-07-26 00:00:00'
    from public.employee_advance_allocations allocation
    where allocation.id = (
      current_setting('test.payroll.manual_advance_receipt')::jsonb
        ->'advance_allocations'->0->>'allocation_id'
    )::uuid
  ),
  'v2 links the advance allocation and stamps period-end midnight in the tenant timezone'
);

reset role;

select throws_ok(
  $$
    update public.employee_advance_allocations
    set amount = amount
    where id = (
      current_setting('test.payroll.manual_advance_receipt')::jsonb
        ->'advance_allocations'->0->>'allocation_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'a v2-created advance allocation cannot change behind its stored receipt'
);

select throws_ok(
  $$
    delete from public.employee_advance_allocations
    where id = (
      current_setting('test.payroll.manual_advance_receipt')::jsonb
        ->'advance_allocations'->0->>'allocation_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'a v2-created advance allocation cannot be deleted behind its stored receipt'
);

set local role authenticated;

select is(
  public.pay_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000507',
    'manual-advance-apply-0001',
    current_setting('test.payroll.manual_advance_version')::bigint,
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000607',
      jsonb_build_array(
        jsonb_build_object(
          'kind', 'advance',
          'amount', 1000,
          'advance_id', (
            current_setting('test.payroll.advance_receipt')::jsonb
              ->>'advance_id'
          ),
          'notes', 'Imputación v2 protegida por comprobante'
        )
      )
    )
  ),
  current_setting('test.payroll.manual_advance_receipt')::jsonb,
  'a replay keeps the v2 advance-allocation receipt linked to a live movement'
);

select throws_ok(
  $$
    select public.create_payroll_statement_import(
      'import-main-reparse-0003',
      repeat('a', 64),
      current_setting('test.statement.source_metadata')::jsonb,
      jsonb_set(
        current_setting('test.statement.main_rows')::jsonb,
        '{0,description_observed}',
        '"Corrección tardía prohibida"'::jsonb
      )
    )
  $$,
  '55000',
  'payroll_statement_applied_import_cannot_be_revised',
  'an applied statement can never have its source rows replaced'
);

select set_config(
  'test.statement.no_method_import',
  public.create_payroll_statement_import(
    'import-no-method-0001',
    repeat('6', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Trabajador sin método configurado'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.no_method_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-no-method-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.no_method_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000608',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000508',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000508'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000508'
      )
    )
  $$,
  '22023',
  'payroll_statement_invalid_bank_payment_1',
  'a missing worker payment preference never defaults to transfer'
);

reset role;
update public.employees
set preferred_payment_method = 'transfer',
    preferred_payment_method_id =
      '7f281000-0000-4000-8000-000000000401'
where id = '7f281000-0000-4000-8000-000000000205';
set local role authenticated;

select is(
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.no_method_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-no-method-recovered-0002',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.no_method_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000608',
        'payment_method_id',
        '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
        '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason', 'Método configurado desde la revisión y fila verificada'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000508',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000508'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000508'
    )
  )->>'status',
  'applied',
  'a newly configured canonical worker method recovers a missing line snapshot'
);

select set_config(
  'test.statement.valid_snapshot_import',
  public.create_payroll_statement_import(
    'import-valid-snapshot-0001',
    repeat('ab', 32),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Snapshot válido no reemplazable'
      )
    )
  )::text,
  true
);

reset role;
update public.employees
set preferred_payment_method = 'transfer',
    preferred_payment_method_id =
      '7f281000-0000-4000-8000-000000000404'
where id = '7f281000-0000-4000-8000-000000000201';
set local role authenticated;

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.valid_snapshot_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-valid-snapshot-override-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.valid_snapshot_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000620',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000404',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact',
          'manual_confirmation', true,
          'reason', 'Intento explícito de reemplazar un snapshot aún válido'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000519',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000519'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000519'
      )
    )
  $$,
  '22023',
  'payroll_statement_invalid_bank_payment_1',
  'a still-valid line snapshot cannot be silently replaced by a new preference'
);

reset role;
update public.employees
set preferred_payment_method = 'transfer',
    preferred_payment_method_id =
      '7f281000-0000-4000-8000-000000000401'
where id = '7f281000-0000-4000-8000-000000000201';
set local role authenticated;

select set_config(
  'test.statement.warning_import',
  public.create_payroll_statement_import(
    'import-warning-0001',
    repeat('7', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'OCR con baja confianza',
        'warnings', jsonb_build_array('low_confidence')
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.warning_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-warning-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.warning_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000609',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000509',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000509'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000509'
      )
    )
  $$,
  '22023',
  'payroll_statement_warning_requires_review_1',
  'a warned OCR row cannot pay without explicit human review'
);

select is(
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.warning_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-warning-0002',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.warning_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000609',
        'payment_method_id',
        '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
        '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason', 'Fila y respaldo bancario revisados manualmente'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000509',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000509'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000509'
    )
  )->>'status',
  'applied',
  'a warned exact row can proceed only with explicit confirmation and reason'
);

select set_config(
  'test.statement.multi_import',
  public.create_payroll_statement_import(
    'import-multi-0001',
    repeat('8', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Sólo una línea de dos'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.multi_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-multi-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.multi_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000610',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000510',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000510'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000510'
      )
    )
  $$,
  '22023',
  'payroll_statement_draft_requires_every_line_decision',
  'a draft voucher cannot be confirmed while one worker is omitted'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.multi_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-wrong-account-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.multi_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000610',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000302',
          'applied_amount', 1000,
          'variance_disposition', 'exact'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'not_paid',
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000611',
          'manual_confirmation', true,
          'reason', 'Efectivo no entregado'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000510',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000510'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000510'
      )
    )
  $$,
  '22023',
  'payroll_statement_invalid_bank_payment_1',
  'a bank row cannot post to cash or a non-statement ERP account'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.multi_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-late-advance-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.multi_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'reason', 'Fila ajena al anticipo'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'not_paid',
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000610',
          'manual_confirmation', true,
          'reason', 'Transferencia no pagada'
        ),
        jsonb_build_object(
          'ordinal', 3,
          'action', 'advance_allocation',
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000611',
          'advance_id',
          '7f281000-0000-4000-8000-000000000702',
          'applied_amount', 1000
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000510',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000510'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000510'
      )
    )
  $$,
  '42501',
  'Payroll advance not found',
  'an advance paid after the period closes cannot settle that older liability'
);

select set_config(
  'test.statement.overlap_import',
  public.create_payroll_statement_import(
    'import-overlap-0001',
    '3eb9aae971fe03e5ad6992c41e18c6cbd2b49d5c1d786237a942b6255fd33ab3',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 128000,
        'description_observed', 'App-traspaso A: Vicente Díaz',
        'beneficiary_observed', 'Vicente Díaz',
        'document_number', 'DOC-128000'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Transferencia nueva de nómina',
        'beneficiary_observed', 'Vicente Díaz',
        'document_number', 'OVERLAP-NEW-1000'
      )
    )
  )::text,
  true
);

select set_config(
  'test.statement.overlap_receipt',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.overlap_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-overlap-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'already_resolved',
        'row_id', (
          current_setting('test.statement.overlap_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'prior_decision_id', (
          select decision.id
          from public.payroll_statement_decisions decision
          where decision.import_id = (
            current_setting('test.statement.import_receipt')::jsonb
              ->>'import_id'
          )::uuid
            and decision.action = 'bank_payment'
        ),
        'reason', 'Movimiento ya conciliado en la cartola anterior'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.overlap_import')::jsonb
            ->'rows'->1->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000610',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason', 'Coincidencia exacta revisada en cartola superpuesta'
      ),
      jsonb_build_object(
        'ordinal', 3,
        'action', 'not_paid',
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000611',
        'manual_confirmation', true,
        'reason', 'Efectivo aún no entregado'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000510',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000510'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000510'
    )
  )::text,
  true
);

select ok(
  current_setting('test.statement.overlap_receipt')::jsonb
    ->>'status' = 'applied'
  and (
    current_setting('test.statement.overlap_receipt')::jsonb
      ->>'already_resolved_count'
  )::integer = 1
  and (
    current_setting('test.statement.overlap_receipt')::jsonb
      ->>'allocation_count'
  )::integer = 1
  and exists (
    select 1
    from public.payroll_statement_decisions current_decision
    join public.payroll_statement_decisions prior_decision
      on prior_decision.id = current_decision.prior_decision_id
    where current_decision.import_id = (
      current_setting('test.statement.overlap_import')::jsonb
        ->>'import_id'
    )::uuid
      and current_decision.action = 'already_resolved'
      and current_decision.outcome = 'acknowledged'
      and current_decision.row_fingerprint =
          prior_decision.row_fingerprint
  )
  and not exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.payroll_statement_decisions decision
      on decision.id = allocation.decision_id
    where decision.import_id = (
      current_setting('test.statement.overlap_import')::jsonb
        ->>'import_id'
    )::uuid
      and decision.action = 'already_resolved'
  ),
  'an overlapping statement acknowledges the prior row and still applies every new row'
);

select set_config(
  'test.statement.tolerance_import',
  public.create_payroll_statement_import(
    'import-tolerance-0001',
    repeat('9', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 60501,
        'description_observed', 'Exceso de CLP 501',
        'document_number', 'DOC-TOLERANCE'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.tolerance_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-tolerance-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.tolerance_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000612',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 60000,
          'variance_disposition', 'unresolved',
          'manual_confirmation', true,
          'reason', 'Intento explícito fuera de margen'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000511',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000511'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000511'
      )
    )
  $$,
  '22023',
  'payroll_statement_variance_outside_tolerance_1',
  'the absolute payroll match tolerance is capped at CLP 500'
);

select set_config(
  'test.statement.low_tolerance_import',
  public.create_payroll_statement_import(
    'import-low-tolerance-0001',
    repeat('3', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 1011,
        'description_observed', 'Exceso de CLP 11 sobre saldo bajo',
        'document_number', 'DOC-LOW-TOLERANCE'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.low_tolerance_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-low-tolerance-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.low_tolerance_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000613',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'unresolved',
          'manual_confirmation', true,
          'reason', 'Intento fuera del uno por ciento'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000512',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000512'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000512'
      )
    )
  $$,
  '22023',
  'payroll_statement_variance_outside_tolerance_1',
  'a low balance is limited to its one-percent tolerance, not the CLP 500 cap'
);

select set_config(
  'test.statement.underpay_import',
  public.create_payroll_statement_import(
    'import-underpay-0001',
    repeat('4', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 600,
        'description_observed', 'Pago parcial manual de CLP 600',
        'document_number', 'DOC-UNDERPAY'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.underpay_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-underpay-wrong-disposition-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.underpay_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
          '7f281000-0000-4000-8000-000000000614',
          'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 600,
          'variance_disposition', 'unresolved',
          'manual_confirmation', true,
          'reason', 'Disposición incorrecta para un pago parcial'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000513',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000513'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000513'
      )
    )
  $$,
  '22023',
  'payroll_statement_partial_requires_review_1',
  'an underpayment cannot be disguised as an unresolved fuzzy variance'
);

select set_config(
  'test.statement.underpay_receipt',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.underpay_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-underpay-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.underpay_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
        '7f281000-0000-4000-8000-000000000614',
        'payment_method_id',
        '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
        '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 600,
        'variance_disposition', 'partial',
        'manual_confirmation', true,
        'reason', 'Pago parcial vinculado manualmente'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000513',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000513'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000513'
    )
  )::text,
  true
);

select ok(
  current_setting('test.statement.underpay_receipt')::jsonb
    ->>'status' = 'applied'
  and (
    current_setting('test.statement.underpay_receipt')::jsonb
      ->>'unresolved_variance_count'
  )::integer = 0
  and (
    current_setting('test.statement.underpay_receipt')::jsonb
      ->>'unresolved_variance_total'
  )::numeric = 0
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    join public.expense_payments payment
      on payment.id = allocation.expense_payment_id
    where allocation.import_id = (
      current_setting('test.statement.underpay_import')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.bank_amount = 600
      and allocation.applied_amount = 600
      and allocation.variance = -400
      and allocation.variance_disposition = 'partial'
      and payment.amount = 600
  )
  and (
    select status = 'partial'
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000513'
  )
  and exists (
    select 1
    from public.payroll_voucher_lines voucher_line
    join public.expenses expense
      on expense.id = voucher_line.expense_id
     and expense.tenant_id = voucher_line.tenant_id
    where voucher_line.id =
        '7f281000-0000-4000-8000-000000000614'
      and expense.total_amount = 1000
      and expense.amount_paid = 600
      and expense.balance = 400
      and expense.payment_status = 'partial'
  ),
  'a manually linked partial debit applies only the bank amount and leaves the exact payroll balance open'
);

select set_config(
  'test.statement.incomplete_import',
  public.create_payroll_statement_import(
    'import-incomplete-0001',
    'ee634b02e94f51a5c119ba5a2bd0b19310a2b811f90d1f225bb3b4435cede940',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', null,
        'direction', 'debit',
        'amount', 129500,
        'description_observed', 'Fecha ilegible para Vicente',
        'document_number', 'INCOMPLETE-DATE'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'transaction_date', '2026-06-30',
        'direction', 'unknown',
        'amount', 22000,
        'description_observed', 'Dirección ilegible',
        'document_number', 'INCOMPLETE-DIRECTION'
      ),
      jsonb_build_object(
        'ordinal', 3,
        'transaction_date', '2026-06-30',
        'direction', 'debit',
        'amount', null,
        'description_observed', 'Monto ilegible',
        'document_number', 'INCOMPLETE-AMOUNT'
      )
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.statement.incomplete_import')::jsonb
      ->>'row_count'
  )::integer = 3
  and (
    select count(*) = 3
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.incomplete_import')::jsonb
        ->>'import_id'
    )::uuid
      and statement_row.fingerprint ~ '^[0-9a-f]{64}$'
      and statement_row.warnings @> '["incomplete_evidence"]'::jsonb
  )
  and exists (
    select 1
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.incomplete_import')::jsonb
        ->>'import_id'
    )::uuid
      and statement_row.row_ordinal = 1
      and statement_row.transaction_date is null
      and statement_row.warnings
            @> '["missing_transaction_date"]'::jsonb
  )
  and exists (
    select 1
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.incomplete_import')::jsonb
        ->>'import_id'
    )::uuid
      and statement_row.row_ordinal = 2
      and statement_row.direction = 'unknown'
      and statement_row.warnings @> '["unknown_direction"]'::jsonb
  )
  and exists (
    select 1
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.incomplete_import')::jsonb
        ->>'import_id'
    )::uuid
      and statement_row.row_ordinal = 3
      and statement_row.amount is null
      and statement_row.warnings @> '["missing_amount"]'::jsonb
  ),
  'import preserves every incomplete OCR row with warnings and a server fingerprint'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.incomplete_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-incomplete-missing-row-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Fecha ilegible revisada'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'hold',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->1->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Dirección pendiente de respaldo'
        )
      ),
      '{}'::jsonb
    )
  $$,
  '22023',
  'payroll_statement_every_row_requires_a_decision',
  'apply still requires an exact reviewed disposition for every incomplete row'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.incomplete_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-incomplete-as-bank-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
            '7f281000-0000-4000-8000-000000000615',
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 129500,
          'variance_disposition', 'exact',
          'manual_confirmation', true,
          'reason', 'Intento manual sin fecha bancaria'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->1->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Dirección ilegible'
        ),
        jsonb_build_object(
          'ordinal', 3,
          'action', 'hold',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->2->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Monto ilegible'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000514',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000514'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000514'
      )
    )
  $$,
  '22023',
  'payroll_statement_incomplete_evidence_requires_review_1',
  'an incomplete OCR row can never become a bank payment'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.incomplete_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-incomplete-unconfirmed-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'reason', 'Fecha ilegible'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->1->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Dirección ilegible'
        ),
        jsonb_build_object(
          'ordinal', 3,
          'action', 'hold',
          'row_id', (
            current_setting('test.statement.incomplete_import')::jsonb
              ->'rows'->2->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Monto ilegible'
        )
      ),
      '{}'::jsonb
    )
  $$,
  '22023',
  'payroll_statement_incomplete_evidence_requires_review_1',
  'ignore or hold of incomplete evidence requires explicit human confirmation'
);

select set_config(
  'test.statement.incomplete_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.incomplete_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-incomplete-reviewed-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'ignore',
        'row_id', (
          current_setting('test.statement.incomplete_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'manual_confirmation', true,
        'reason', 'Fecha ilegible; no se usa como pago'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'action', 'ignore',
        'row_id', (
          current_setting('test.statement.incomplete_import')::jsonb
            ->'rows'->1->>'row_id'
        ),
        'manual_confirmation', true,
        'reason', 'Dirección ilegible; no se usa como pago'
      ),
      jsonb_build_object(
        'ordinal', 3,
        'action', 'hold',
        'row_id', (
          current_setting('test.statement.incomplete_import')::jsonb
            ->'rows'->2->>'row_id'
        ),
        'manual_confirmation', true,
        'reason', 'Monto ilegible retenido para respaldo'
      )
    ),
    '{}'::jsonb
  )::text,
  true
);

select ok(
  current_setting('test.statement.incomplete_apply')::jsonb
    ->>'status' = 'held'
  and (
    current_setting('test.statement.incomplete_apply')::jsonb
      ->>'decision_count'
  )::integer = 3
  and (
    current_setting('test.statement.incomplete_apply')::jsonb
      ->>'allocation_count'
  )::integer = 0,
  'reviewed ignore and hold preserve complete disposition coverage without creating money'
);

select set_config(
  'test.statement.incomplete_overlap_import',
  public.create_payroll_statement_import(
    'import-incomplete-overlap-0001',
    'a1b598e4aba90917878b9c80e9db2f1513e892b009d1a674b33eef61d489cd45',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', null,
        'direction', 'debit',
        'amount', 129500,
        'description_observed', 'Fecha ilegible para Vicente',
        'document_number', 'INCOMPLETE-DATE'
      )
    )
  )::text,
  true
);

select set_config(
  'test.statement.incomplete_overlap_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.incomplete_overlap_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-incomplete-overlap-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'already_resolved',
        'row_id', (
          current_setting(
            'test.statement.incomplete_overlap_import'
          )::jsonb->'rows'->0->>'row_id'
        ),
        'prior_decision_id', (
          select decision.id
          from public.payroll_statement_decisions decision
          where decision.import_id = (
            current_setting('test.statement.incomplete_import')::jsonb
              ->>'import_id'
          )::uuid
            and decision.decision_ordinal = 1
        ),
        'manual_confirmation', true,
        'reason', 'Evidencia incompleta ya ignorada en revisión anterior'
      )
    ),
    '{}'::jsonb
  )::text,
  true
);

select ok(
  current_setting('test.statement.incomplete_overlap_apply')::jsonb
    ->>'status' = 'applied'
  and (
    current_setting('test.statement.incomplete_overlap_apply')::jsonb
      ->>'already_resolved_count'
  )::integer = 1
  and (
    current_setting('test.statement.incomplete_overlap_apply')::jsonb
      ->>'allocation_count'
  )::integer = 0,
  'repeated incomplete evidence can acknowledge its prior reviewed disposition'
);

select set_config(
  'test.statement.before_period_import',
  public.create_payroll_statement_import(
    'import-before-period-0001',
    'c9a2c4ef3fd564c951c015d25ec9a4407ccb4bb63c064732a8a73946c2a1fba9',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-06-28',
        'direction', 'debit',
        'amount', 129500,
        'description_observed', 'Transferencia anterior a semana 27',
        'document_number', 'BEFORE-W27'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.before_period_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-before-period-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.before_period_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
            '7f281000-0000-4000-8000-000000000615',
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 129500,
          'variance_disposition', 'exact'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000514',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000514'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000514'
      )
    )
  $$,
  '22023',
  'payroll_statement_invalid_bank_payment_1',
  'a transfer before period_start cannot settle that payroll week'
);

select set_config(
  'test.statement.after_window_import',
  public.create_payroll_statement_import(
    'import-after-window-0001',
    '7041269d77c8ac769753afef019045c841755ca5f50857a1091e9d6d4491f273',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-11',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Pago seis días después de semana 27',
        'document_number', 'W27-END-PLUS-SIX'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.after_window_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-after-window-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.after_window_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
            '7f281000-0000-4000-8000-000000000622',
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact',
          'manual_confirmation', true,
          'reason', 'Intento explícito fuera de ventana'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000521',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000521'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000521'
      )
    )
  $$,
  '22023',
  'payroll_statement_invalid_bank_payment_1',
  'period_end plus six days is outside the canonical payroll payment window'
);

select set_config(
  'test.statement.w27_import',
  public.create_payroll_statement_import(
    'import-w27-dates-0001',
    '1653b8d94ff5327a1f8f3aeef3340c03150d0cd41db5e70a6d5995ccdb65bc48',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-06-30',
        'direction', 'debit',
        'amount', 129500,
        'description_observed', 'Pago semana 27 Vicente',
        'document_number', 'W27-VICENTE-129500'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'transaction_date', '2026-07-10',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Pago en límite de semana 27',
        'document_number', 'W27-END-PLUS-FIVE'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.w27_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-w27-unconfirmed-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting('test.statement.w27_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
            '7f281000-0000-4000-8000-000000000615',
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 129500,
          'variance_disposition', 'exact'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.w27_import')::jsonb
              ->'rows'->1->>'row_id'
          ),
          'manual_confirmation', true,
          'reason', 'Cobertura de fila límite durante prueba de confirmación'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000514',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000514'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000514'
      )
    )
  $$,
  '22023',
  'payroll_statement_bank_payment_requires_review_1',
  'even an exact bank match requires human confirmation and an audit reason'
);

select set_config(
  'test.statement.w27_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.w27_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-w27-dates-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.w27_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000615',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 129500,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason', 'Coincidencia exacta de Vicente revisada'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.w27_import')::jsonb
            ->'rows'->1->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000622',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason', 'Límite de cinco días revisado'
      ),
      jsonb_build_object(
        'ordinal', 3,
        'action', 'cash_payment',
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000616',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000402',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000302',
        'applied_amount', 26000,
        'payment_date', '2026-07-01',
        'manual_confirmation', true
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000514',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000514'
      ),
      '7f281000-0000-4000-8000-000000000515',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000515'
      ),
      '7f281000-0000-4000-8000-000000000521',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000521'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000514',
      '7f281000-0000-4000-8000-000000000515',
      '7f281000-0000-4000-8000-000000000521'
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.statement.w27_apply')::jsonb
      ->>'allocation_count'
  )::integer = 3
  and (
    select count(*) = 3
    from public.payroll_vouchers voucher
    where voucher.id in (
      '7f281000-0000-4000-8000-000000000514',
      '7f281000-0000-4000-8000-000000000515',
      '7f281000-0000-4000-8000-000000000521'
    )
      and voucher.status = 'paid'
  )
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    where allocation.import_id = (
      current_setting('test.statement.w27_import')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.action = 'bank_payment'
      and allocation.payment_date = date '2026-06-30'
  )
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    where allocation.import_id = (
      current_setting('test.statement.w27_import')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.action = 'cash_payment'
      and allocation.payment_date = date '2026-07-01'
  )
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    where allocation.import_id = (
      current_setting('test.statement.w27_import')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.action = 'bank_payment'
      and allocation.payment_date = date '2026-07-10'
  ),
  'week-27 payments accept in-week dates and the inclusive end-plus-five boundary'
);

select set_config(
  'test.statement.repeated_prior_import',
  public.create_payroll_statement_import(
    'import-repeated-prior-0001',
    'f82ac918ea4b6972f2e1199f20a252dd7ba16136086293bba406f9903a993f78',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-03-02',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Cargo idéntico solapado',
        'document_number', 'REPEATED-ROW'
      )
    )
  )::text,
  true
);

select set_config(
  'test.statement.repeated_prior_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.repeated_prior_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-repeated-prior-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.repeated_prior_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000620',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason', 'Primer cargo idéntico revisado'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000519',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000519'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000519'
    )
  )::text,
  true
);

select set_config(
  'test.statement.repeated_overlap_import',
  public.create_payroll_statement_import(
    'import-repeated-overlap-0001',
    '8ad53536dc7d85279eb3805493a6e4aebb4842420d9190c9778c6a1487ae8be2',
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-03-02',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Cargo idéntico solapado',
        'document_number', 'REPEATED-ROW',
        'source_occurrence', 1
      ),
      jsonb_build_object(
        'ordinal', 2,
        'transaction_date', '2026-03-02',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Cargo idéntico solapado',
        'document_number', 'REPEATED-ROW',
        'source_occurrence', 2
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.repeated_overlap_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-repeated-no-override-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'already_resolved',
          'row_id', (
            current_setting(
              'test.statement.repeated_overlap_import'
            )::jsonb->'rows'->0->>'row_id'
          ),
          'prior_decision_id', (
            select decision.id
            from public.payroll_statement_decisions decision
            where decision.import_id = (
              current_setting(
                'test.statement.repeated_prior_import'
              )::jsonb->>'import_id'
            )::uuid
              and decision.action = 'bank_payment'
          ),
          'reason', 'Primera ocurrencia ya pagada'
        ),
        jsonb_build_object(
          'ordinal', 2,
          'action', 'bank_payment',
          'row_id', (
            current_setting(
              'test.statement.repeated_overlap_import'
            )::jsonb->'rows'->1->>'row_id'
          ),
          'voucher_line_id',
            '7f281000-0000-4000-8000-000000000621',
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact',
          'manual_confirmation', true,
          'reason', 'Segunda ocurrencia propuesta'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000520',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000520'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000520'
      )
    )
  $$,
  '22023',
  'payroll_statement_ambiguous_repeated_row_requires_override',
  'a repeated normalized base is never silently payable in an overlapping import'
);

select set_config(
  'test.statement.repeated_overlap_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.repeated_overlap_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-repeated-with-override-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'already_resolved',
        'row_id', (
          current_setting(
            'test.statement.repeated_overlap_import'
          )::jsonb->'rows'->0->>'row_id'
        ),
        'prior_decision_id', (
          select decision.id
          from public.payroll_statement_decisions decision
          where decision.import_id = (
            current_setting(
              'test.statement.repeated_prior_import'
            )::jsonb->>'import_id'
          )::uuid
            and decision.action = 'bank_payment'
        ),
        'reason', 'Primera ocurrencia ya pagada'
      ),
      jsonb_build_object(
        'ordinal', 2,
        'action', 'bank_payment',
        'row_id', (
          current_setting(
            'test.statement.repeated_overlap_import'
          )::jsonb->'rows'->1->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000621',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'duplicate_override', true,
        'reason',
          'Banco muestra una segunda ocurrencia distinta; respaldo revisado'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000520',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000520'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000520'
    )
  )::text,
  true
);

select ok(
  (
    current_setting('test.statement.repeated_overlap_apply')::jsonb
      ->>'already_resolved_count'
  )::integer = 1
  and (
    current_setting('test.statement.repeated_overlap_apply')::jsonb
      ->>'allocation_count'
  )::integer = 1
  and exists (
    select 1
    from public.payroll_statement_decisions decision
    join public.payroll_statement_rows statement_row
      on statement_row.id = decision.row_id
    where decision.import_id = (
      current_setting('test.statement.repeated_overlap_import')::jsonb
        ->>'import_id'
    )::uuid
      and decision.action = 'bank_payment'
      and decision.duplicate_override is true
      and decision.manual_confirmation is true
      and decision.reason is not null
      and statement_row.source_occurrence = 2
  ),
  'a distinct repeated charge remains payable only through an audited duplicate override'
);

select set_config(
  'test.statement.close_plus_one_import',
  public.create_payroll_statement_import(
    'import-close-plus-one-0001',
    'f75d2a36da43279119dc7a635f9ec95b5ae229280595d483fa437d880f0eccdb',
    jsonb_set(
      jsonb_set(
        jsonb_set(
          current_setting('test.statement.source_metadata')::jsonb,
          '{statement_start}',
          to_jsonb('2026-07-01'::text)
        ),
        '{statement_end}',
        to_jsonb('2026-07-28'::text)
      ),
      '{document_date}',
      to_jsonb('2026-07-28'::text)
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-29',
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Movimiento informado después del cierre',
        'document_number', 'CLOSE-PLUS-ONE'
      )
    )
  )::text,
  true
);

select ok(
  exists (
    select 1
    from public.payroll_statement_rows statement_row
    where statement_row.import_id = (
      current_setting('test.statement.close_plus_one_import')::jsonb
        ->>'import_id'
    )::uuid
      and statement_row.transaction_date = date '2026-07-29'
      and statement_row.warnings
            @> '["out_of_statement_range"]'::jsonb
  ),
  'a row one day after the declared statement close is retained with a warning'
);

select set_config(
  'test.statement.close_plus_one_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.close_plus_one_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-close-plus-one-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.close_plus_one_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000617',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason',
          'Cartola cierra el 28/07 pero el banco informó esta fila el 29/07'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000516',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000516'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000516'
    )
  )::text,
  true
);

select ok(
  current_setting('test.statement.close_plus_one_apply')::jsonb
    ->>'status' = 'applied'
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    where allocation.import_id = (
      current_setting('test.statement.close_plus_one_import')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.payment_date = date '2026-07-29'
      and allocation.bank_amount = 1000
      and allocation.applied_amount = 1000
  ),
  'a manually confirmed close-plus-one row can settle within the five-day payroll window'
);

select set_config(
  'test.statement.dynamic_close_import',
  public.create_payroll_statement_import(
    'import-dynamic-close-plus-one-0001',
    '626ee17d5a731e8559e0f2cc382bec38f5d60f93cfc77723ac115c4a5f7d10b2',
    jsonb_set(
      jsonb_set(
        jsonb_set(
          current_setting('test.statement.source_metadata')::jsonb,
          '{statement_start}',
          to_jsonb(
            (
              (statement_timestamp() at time zone 'America/Santiago')::date
                - 6
            )::text
          )
        ),
        '{statement_end}',
        to_jsonb(
          (
            statement_timestamp() at time zone 'America/Santiago'
          )::date::text
        )
      ),
      '{document_date}',
      to_jsonb(
        (
          statement_timestamp() at time zone 'America/Santiago'
        )::date::text
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date',
          (
            (
              statement_timestamp() at time zone 'America/Santiago'
            )::date + 1
          )::text,
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Cierre dinámico más un día',
        'document_number', 'DYNAMIC-CLOSE-PLUS-ONE'
      )
    )
  )::text,
  true
);

select set_config(
  'test.statement.dynamic_close_apply',
  public.apply_payroll_statement_reconciliation(
    (
      current_setting('test.statement.dynamic_close_import')::jsonb
        ->>'import_id'
    )::uuid,
    'apply-dynamic-close-plus-one-0001',
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'action', 'bank_payment',
        'row_id', (
          current_setting('test.statement.dynamic_close_import')::jsonb
            ->'rows'->0->>'row_id'
        ),
        'voucher_line_id',
          '7f281000-0000-4000-8000-000000000618',
        'payment_method_id',
          '7f281000-0000-4000-8000-000000000401',
        'payment_account_id',
          '7f281000-0000-4000-8000-000000000301',
        'applied_amount', 1000,
        'variance_disposition', 'exact',
        'manual_confirmation', true,
        'reason',
          'Fila de mañana informada por cartola que cierra hoy'
      )
    ),
    jsonb_build_object(
      '7f281000-0000-4000-8000-000000000517',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000517'
      )
    ),
    jsonb_build_array(
      '7f281000-0000-4000-8000-000000000517'
    )
  )::text,
  true
);

select ok(
  current_setting('test.statement.dynamic_close_apply')::jsonb
    ->>'status' = 'applied'
  and exists (
    select 1
    from public.payroll_statement_allocations allocation
    where allocation.import_id = (
      current_setting('test.statement.dynamic_close_import')::jsonb
        ->>'import_id'
    )::uuid
      and allocation.payment_date = (
        (statement_timestamp() at time zone 'America/Santiago')::date + 1
      )
  ),
  'tenant-relative close-plus-one evidence traverses the bounded future exception'
);

select set_config(
  'test.statement.dynamic_future_two_import',
  public.create_payroll_statement_import(
    'import-dynamic-future-two-0001',
    'fab8adbd78165fe15e8c21db54454f781b6eed7cc1eff85a783ca156ec14dabc',
    jsonb_set(
      jsonb_set(
        current_setting('test.statement.source_metadata')::jsonb,
        '{statement_start}',
        to_jsonb(
          (
            (statement_timestamp() at time zone 'America/Santiago')::date
              - 6
          )::text
        )
      ),
      '{statement_end}',
      to_jsonb(
        (
          statement_timestamp() at time zone 'America/Santiago'
        )::date::text
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date',
          (
            (
              statement_timestamp() at time zone 'America/Santiago'
            )::date + 2
          )::text,
        'direction', 'debit',
        'amount', 1000,
        'description_observed', 'Fecha futura fuera de excepción',
        'document_number', 'DYNAMIC-FUTURE-TWO'
      )
    )
  )::text,
  true
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting(
          'test.statement.dynamic_future_two_import'
        )::jsonb->>'import_id'
      )::uuid,
      'apply-dynamic-future-two-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'bank_payment',
          'row_id', (
            current_setting(
              'test.statement.dynamic_future_two_import'
            )::jsonb->'rows'->0->>'row_id'
          ),
          'voucher_line_id',
            '7f281000-0000-4000-8000-000000000619',
          'payment_method_id',
            '7f281000-0000-4000-8000-000000000401',
          'payment_account_id',
            '7f281000-0000-4000-8000-000000000301',
          'applied_amount', 1000,
          'variance_disposition', 'exact',
          'manual_confirmation', true,
          'reason', 'Intento explícito dos días en el futuro'
        )
      ),
      jsonb_build_object(
        '7f281000-0000-4000-8000-000000000518',
        (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '7f281000-0000-4000-8000-000000000518'
        )
      ),
      jsonb_build_array(
        '7f281000-0000-4000-8000-000000000518'
      )
    )
  $$,
  '22023',
  'payroll_statement_bank_payment_is_future_1',
  'a reviewed row two days beyond the imported close remains future fraud'
);

select set_config(
  'test.statement.hold_import',
  public.create_payroll_statement_import(
    'import-hold-0001',
    repeat('0', 64),
    current_setting('test.statement.source_metadata')::jsonb,
    jsonb_build_array(
      jsonb_build_object(
        'ordinal', 1,
        'transaction_date', '2026-07-27',
        'direction', 'debit',
        'amount', 4321,
        'description_observed', 'Fila retenida definitivamente'
      )
    )
  )::text,
  true
);

select set_config(
  'test.statement.hold_apply',
  public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.hold_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-hold-0001',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'hold',
          'row_id', (
            current_setting('test.statement.hold_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'reason', 'Retención final para investigación externa'
        )
      ),
      '{}'::jsonb
    )::text,
  true
);

select ok(
  current_setting('test.statement.hold_apply')::jsonb
    ->>'status' = 'held'
  and (
    select status
    from public.payroll_statement_imports
    where id = (
      current_setting('test.statement.hold_import')::jsonb
        ->>'import_id'
    )::uuid
  ) = 'held',
  'hold is stored as a terminal retained disposition, not a pause'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.hold_import')::jsonb
          ->>'import_id'
      )::uuid,
      'apply-hold-resume-0002',
      jsonb_build_array(
        jsonb_build_object(
          'ordinal', 1,
          'action', 'ignore',
          'row_id', (
            current_setting('test.statement.hold_import')::jsonb
              ->'rows'->0->>'row_id'
          ),
          'reason', 'Intento de reabrir'
        )
      ),
      '{}'::jsonb
    )
  $$,
  'P0001',
  'payroll_statement_import_already_applied',
  'a terminal hold cannot be resumed through a second apply'
);

select throws_ok(
  $$
    delete from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000505'
  $$,
  '42501',
  'permission denied for table payroll_vouchers',
  'authenticated managers cannot bypass aggregate draft deletion'
);

reset role;

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
  status
)
values (
  '7f281000-0000-4000-8000-000000000524',
  '7f281000-0000-4000-8000-000000000001',
  'STMT-CONFIRM-EMPTY',
  '2026-01-05',
  '2026-01-11',
  'Confirmación sin obligaciones',
  0,
  0,
  0,
  'draft'
);

set local role authenticated;

select throws_ok(
  $$
    select public.confirm_payroll_voucher_v2(
      '7f281000-0000-4000-8000-000000000524',
      'confirm-empty-v2-0001',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000524'
      )
    )
  $$,
  '22023',
  'payroll_voucher_has_no_positive_obligations',
  'confirm v2 rejects a draft with no included positive payroll obligation'
);

select is(
  (
    select count(*)::integer
    from public.payroll_voucher_draft_operations
    where voucher_id = '7f281000-0000-4000-8000-000000000524'
  ),
  0,
  'rejected empty confirmation leaves no lifecycle receipt'
);

select set_config(
  'test.lifecycle.confirm_expected_version',
  (
    select reconciliation_version::text
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000522'
  ),
  true
);

select set_config(
  'test.lifecycle.confirm_receipt',
  public.confirm_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000522',
    'confirm-draft-v2-0001',
    current_setting(
      'test.lifecycle.confirm_expected_version'
    )::bigint
  )::text,
  true
);

select ok(
  current_setting('test.lifecycle.confirm_receipt')::jsonb @>
    jsonb_build_object(
      'operation', 'confirm_draft',
      'operation_key', 'confirm-draft-v2-0001',
      'voucher_id', '7f281000-0000-4000-8000-000000000522',
      'confirmed', true,
      'status', 'confirmed',
      'expected_reconciliation_version',
        current_setting(
          'test.lifecycle.confirm_expected_version'
        )::bigint
    )
  and (
    current_setting('test.lifecycle.confirm_receipt')::jsonb
      ->>'payload_hash'
  ) ~ '^[0-9a-f]{64}$'
  and (
    current_setting('test.lifecycle.confirm_receipt')::jsonb
      ->>'reconciliation_version'
  )::bigint = (
    select reconciliation_version
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000522'
  )
  and (
    select status
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000522'
  ) = 'confirmed'
  and (
    select expense_id is not null
    from public.payroll_voucher_lines
    where id = '7f281000-0000-4000-8000-000000000623'
  ),
  'confirm v2 commits one exact draft version and returns its durable receipt'
);

select is(
  public.confirm_payroll_voucher_v2(
    '7f281000-0000-4000-8000-000000000522',
    'confirm-draft-v2-0001',
    current_setting(
      'test.lifecycle.confirm_expected_version'
    )::bigint
  ),
  current_setting('test.lifecycle.confirm_receipt')::jsonb,
  'an exact confirmation replay returns the byte-stable receipt after commit'
);

select throws_ok(
  $$
    select public.confirm_payroll_voucher_v2(
      '7f281000-0000-4000-8000-000000000522',
      'confirm-draft-v2-0001',
      current_setting(
        'test.lifecycle.confirm_expected_version'
      )::bigint + 1
    )
  $$,
  'P0001',
  'payroll_voucher_lifecycle_idempotency_conflict',
  'a confirmation operation key cannot be reused with a changed payload'
);

select throws_ok(
  $$
    select public.confirm_payroll_voucher_v2(
      '7f281000-0000-4000-8000-000000000522',
      'confirm-draft-v2-stale-0002',
      current_setting(
        'test.lifecycle.confirm_expected_version'
      )::bigint
    )
  $$,
  '40001',
  'payroll_voucher_lifecycle_version_conflict',
  'a second confirmer holding the stale draft version loses deterministically'
);

select set_config(
  'test.lifecycle.delete_expected_version',
  (
    select reconciliation_version::text
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000523'
  ),
  true
);

select set_config(
  'test.lifecycle.delete_receipt',
  public.delete_payroll_voucher_draft_v2(
    '7f281000-0000-4000-8000-000000000523',
    'delete-draft-v2-0001',
    current_setting(
      'test.lifecycle.delete_expected_version'
    )::bigint
  )::text,
  true
);

select is(
  public.delete_payroll_voucher_draft_v2(
    '7f281000-0000-4000-8000-000000000523',
    'delete-draft-v2-0001',
    current_setting(
      'test.lifecycle.delete_expected_version'
    )::bigint
  ),
  current_setting('test.lifecycle.delete_receipt')::jsonb,
  'an exact deletion replay returns its receipt after the voucher is gone'
);

select ok(
  current_setting('test.lifecycle.delete_receipt')::jsonb @>
    jsonb_build_object(
      'operation', 'delete_draft',
      'operation_key', 'delete-draft-v2-0001',
      'voucher_id', '7f281000-0000-4000-8000-000000000523',
      'deleted', true,
      'expected_reconciliation_version',
        current_setting(
          'test.lifecycle.delete_expected_version'
        )::bigint,
      'deleted_reconciliation_version',
        current_setting(
          'test.lifecycle.delete_expected_version'
        )::bigint
    )
  and (
    current_setting('test.lifecycle.delete_receipt')::jsonb
      ->>'payload_hash'
  ) ~ '^[0-9a-f]{64}$'
  and not exists (
    select 1
    from public.payroll_vouchers
    where id = '7f281000-0000-4000-8000-000000000523'
  )
  and not exists (
    select 1
    from public.payroll_voucher_lines
    where id = '7f281000-0000-4000-8000-000000000624'
  )
  and exists (
    select 1
    from public.payroll_voucher_draft_operations draft_operation
    where draft_operation.operation_key = 'delete-draft-v2-0001'
      and draft_operation.voucher_id is null
      and draft_operation.expected_reconciliation_version =
        current_setting(
          'test.lifecycle.delete_expected_version'
        )::bigint
  ),
  'delete v2 removes the aggregate but retains immutable versioned evidence'
);

select throws_ok(
  $$
    select public.delete_payroll_voucher_draft_v2(
      '7f281000-0000-4000-8000-000000000523',
      'delete-draft-v2-0001',
      current_setting(
        'test.lifecycle.delete_expected_version'
      )::bigint + 1
    )
  $$,
  'P0001',
  'payroll_voucher_lifecycle_idempotency_conflict',
  'a deletion operation key cannot be reused with a changed payload'
);

select throws_ok(
  $$
    select public.delete_payroll_voucher_draft_v2(
      '7f281000-0000-4000-8000-000000000523',
      'delete-draft-v2-missing-0002',
      current_setting(
        'test.lifecycle.delete_expected_version'
      )::bigint
    )
  $$,
  '42501',
  'Payroll voucher not found',
  'a new operation key cannot disguise a second deletion'
);

select throws_ok(
  $$
    select public.delete_payroll_voucher_draft_v2(
      '7f281000-0000-4000-8000-000000000501',
      'delete-paid-v2-0001',
      (
        select reconciliation_version + 1
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000501'
      )
    )
  $$,
  '40001',
  'payroll_voucher_lifecycle_version_conflict',
  'delete compares the expected version before exposing later voucher state'
);

select throws_ok(
  $$
    select public.delete_payroll_voucher_draft_v2(
      '7f281000-0000-4000-8000-000000000501',
      'delete-paid-v2-0002',
      (
        select reconciliation_version
        from public.payroll_vouchers
        where id = '7f281000-0000-4000-8000-000000000501'
      )
    )
  $$,
  '55000',
  'payroll_voucher_is_not_a_draft',
  'a current but paid voucher remains unavailable to draft deletion'
);

reset role;

select throws_ok(
  $$
    update public.payroll_statement_rows
    set amount = amount
    where import_id = (
      current_setting('test.statement.import_receipt')::jsonb
        ->>'import_id'
    )::uuid
  $$,
  '55000',
  'payroll_statement_rows_are_immutable',
  'even a privileged SQL path cannot mutate normalized parser rows'
);

-- The payroll manager reads all movements for a voucher in one coherent
-- snapshot and can maintain only unambiguous tenant aliases.
select set_config(
  'request.jwt.claims',
  '{"sub":"7f281000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f281000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select is(
  public.learn_payroll_beneficiary_alias(
    '7f281000-0000-4000-8000-000000000201',
    'Vicente Díaz Manager'
  )->>'status',
  'created',
  'a payroll manager can explicitly learn a tenant beneficiary alias'
);

select is(
  (
    select count(*)::integer
    from public.payroll_beneficiary_aliases
  ),
  1,
  'the alias command creates exactly one tenant-scoped identity'
);

select is(
  public.learn_payroll_beneficiary_alias(
    '7f281000-0000-4000-8000-000000000202',
    'VICENTE DIAZ MANAGER'
  )->>'status',
  'conflict',
  'normalized aliases cannot be reassigned to another employee'
);

select ok(
  (
    select count(*) > 0
    from public.get_payroll_voucher_settlement_evidence(
      array['7f281000-0000-4000-8000-000000000501'::uuid]
    )
  ),
  'the evidence projection retains individual settlement movements'
);

select ok(
  exists (
    select 1
    from public.get_payroll_voucher_settlement_evidence(
      array['7f281000-0000-4000-8000-000000000501'::uuid]
    ) evidence
    where evidence.source = 'bank_statement'
      and evidence.statement_transaction_date = date '2026-07-27'
      and evidence.statement_description_observed =
        'App-traspaso A: Vicente Díaz'
      and evidence.statement_document_observed = 'DOC-128000'
      and evidence.statement_page_number = 5
      and evidence.statement_source_line_start = 44
      and evidence.statement_source_line_end = 44
      and evidence.statement_row_ordinal = 1
  ),
  'bank evidence exposes the exact applied observation and page-line locator'
);

select ok(
  not exists (
    select 1
    from public.get_payroll_voucher_settlement_evidence(
      array['7f281000-0000-4000-8000-000000000501'::uuid]
    ) evidence
    where evidence.statement_document_observed = 'DOC-22000'
  )
  and not exists (
    select 1
    from public.get_payroll_voucher_settlement_evidence(
      array[
        '7f281000-0000-4000-8000-000000000502'::uuid,
        '7f281000-0000-4000-8000-000000000503'::uuid,
        '7f281000-0000-4000-8000-000000000504'::uuid,
        '7f281000-0000-4000-8000-000000000507'::uuid
      ]
    ) evidence
    where evidence.statement_row_id is not null
       or evidence.statement_transaction_date is not null
       or evidence.statement_description_observed is not null
       or evidence.statement_document_observed is not null
       or evidence.statement_page_number is not null
       or evidence.statement_source_line_start is not null
       or evidence.statement_source_line_end is not null
       or evidence.statement_row_ordinal is not null
  ),
  'ignored rows and rowless cash or advance settlements leak no bank observation'
);

select is(
  (
    select coalesce(sum(evidence.amount), 0)::numeric
    from public.get_payroll_voucher_settlement_evidence(
      array['7f281000-0000-4000-8000-000000000501'::uuid]
    ) evidence
  ),
  (
    select
      coalesce(sum(payment.amount), 0)
      + coalesce(
          (
            select sum(allocation.amount)
            from public.payroll_voucher_lines voucher_line
            join public.employee_advance_allocations allocation
              on allocation.voucher_line_id = voucher_line.id
             and allocation.tenant_id = voucher_line.tenant_id
            where voucher_line.voucher_id =
              '7f281000-0000-4000-8000-000000000501'
          ),
          0
        )
    from public.payroll_voucher_lines voucher_line
    join public.expense_payments payment
      on payment.expense_id = voucher_line.expense_id
     and payment.tenant_id = voucher_line.tenant_id
    where voucher_line.voucher_id =
      '7f281000-0000-4000-8000-000000000501'
  )::numeric,
  'movement evidence sums to the direct-payment and advance ledger'
);

reset role;

-- Ordinary linked ERP worker: no full statement evidence and no commands.
select set_config(
  'request.jwt.claims',
  '{"sub":"7f281000-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f281000-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.payroll_statement_imports),
  0,
  'an ordinary worker cannot read statement import metadata'
);
select is(
  (
    select count(*)::integer
    from public.payroll_statement_import_operations
  ),
  0,
  'an ordinary worker cannot read superseded import revisions'
);
select is(
  (select count(*)::integer from public.payroll_statement_rows),
  0,
  'an ordinary worker cannot read bank transaction observations'
);
select is(
  (select count(*)::integer from public.payroll_statement_decisions),
  0,
  'an ordinary worker cannot read reconciliation decisions'
);
select is(
  (select count(*)::integer from public.payroll_statement_allocations),
  0,
  'an ordinary worker cannot read reconciliation allocations'
);
select is(
  (select count(*)::integer from public.payroll_statement_account_mappings),
  0,
  'an ordinary worker cannot read confirmed bank-account mappings'
);
select is(
  (select count(*)::integer from public.payroll_voucher_draft_operations),
  0,
  'an ordinary worker cannot read payroll draft command receipts'
);
select is(
  (select count(*)::integer from public.payroll_money_operations),
  0,
  'an ordinary worker cannot read payroll money command receipts'
);
select is(
  (
    select count(*)::integer
    from public.payroll_money_operation_movements
  ),
  0,
  'an ordinary worker cannot read receipt-to-movement links'
);
select is(
  (select count(*)::integer from public.payroll_beneficiary_aliases),
  0,
  'ordinary worker cannot read payroll beneficiary aliases'
);
select throws_ok(
  $$
    select *
    from public.get_payroll_voucher_settlement_evidence(
      array['7f281000-0000-4000-8000-000000000501'::uuid]
    )
  $$,
  '42501',
  'Payroll access denied',
  'ordinary worker cannot read payroll settlement evidence'
);

select throws_ok(
  $$
    select public.create_payroll_statement_import(
      'worker-denied-0001',
      repeat('d', 64),
      current_setting('test.statement.source_metadata')::jsonb,
      current_setting('test.statement.main_rows')::jsonb
    )
  $$,
  '42501',
  'Payroll statement access denied',
  'ordinary worker cannot import a bank statement'
);

reset role;

-- A payroll manager in another tenant sees no first-tenant evidence and cannot
-- address its import UUID through the definer-rights apply command.
select set_config(
  'request.jwt.claims',
  '{"sub":"7f281000-0000-4000-8000-000000000103","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f281000-0000-4000-8000-000000000103',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.payroll_statement_imports),
  0,
  'another tenant payroll manager reads no statement imports'
);
select is(
  (select count(*)::integer from public.payroll_statement_rows),
  0,
  'another tenant payroll manager reads no statement rows'
);

select throws_ok(
  $$
    select public.apply_payroll_statement_reconciliation(
      (
        current_setting('test.statement.import_receipt')::jsonb
          ->>'import_id'
      )::uuid,
      'other-tenant-0001',
      current_setting('test.statement.decisions')::jsonb,
      current_setting('test.statement.expected_versions')::jsonb
    )
  $$,
  '42501',
  'Payroll statement import not found',
  'definer-rights apply does not reveal or mutate another tenant import'
);
select throws_ok(
  $$
    select *
    from public.get_payroll_voucher_settlement_evidence(
      array['7f281000-0000-4000-8000-000000000501'::uuid]
    )
  $$,
  '42501',
  'Payroll access denied',
  'another tenant cannot address a voucher through the evidence read model'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select ok(
  to_regclass(
    'public.ux_payroll_statement_allocations_tenant_fingerprint'
  ) is not null
  and to_regclass(
    'public.ux_payroll_statement_decisions_resolved_fingerprint'
  ) is not null
  and to_regclass(
    'public.ux_payroll_statement_imports_apply_operation'
  ) is not null
  and to_regclass(
    'public.ux_payroll_money_operations_tenant_id'
  ) is not null,
  'unique fingerprint, operation, and tenant-link indexes close duplicate races'
);

select ok(
  (
    select count(*) >= 11
    from pg_catalog.pg_constraint constraint_row
    where (
      constraint_row.conname like
        'payroll_statement_%_tenant_%_fkey'
      or constraint_row.conname like
        'payroll_money_%_tenant_%_fkey'
    )
  ),
  'tenant-composite foreign keys protect reconciliation and money-operation relationships'
);

select * from finish();
rollback;
