begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.payroll_money_command_contexts'::regclass
      and constraint_row.conname =
        'payroll_money_command_contexts_command_check'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid) like
        '%advance_audit_attach%'
      and pg_catalog.pg_get_constraintdef(constraint_row.oid) like
        '%audited_reversal%'
  ),
  'the shared payroll command domain preserves advance audit and reversal writers'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.register_employee_advance_v3(text,uuid,numeric,uuid,uuid,timestamp with time zone,text,text,text,text,date,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.register_employee_advance_v3(text,uuid,numeric,uuid,uuid,timestamp with time zone,text,text,text,text,date,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.register_employee_advance_v3(text,uuid,numeric,uuid,uuid,timestamp with time zone,text,text,text,text,date,uuid,text)',
    'EXECUTE'
  ),
  'only authenticated ERP callers can execute advance v3'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.register_employee_advance_v2(text,uuid,numeric,uuid,uuid,timestamp with time zone,text,text)',
    'EXECUTE'
  ),
  'the expand-first migration keeps the published v2 client callable'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_employee_advance_ledger_page_v2(uuid,integer,timestamp with time zone,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_employee_advance_ledger_page_v2(uuid,integer,timestamp with time zone,uuid)',
    'EXECUTE'
  ),
  'the enriched ledger is payroll-authorized only'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_employee_advance_receipt_policy_v1()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_employee_advance_receipt_policy_v1()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_employee_advance_receipt_policy_v1()',
    'EXECUTE'
  ),
  'only authenticated ERP callers can probe the receipt policy capability'
);

select ok(
  to_regclass('public.employee_advance_evidence') is not null
  and exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'employee_advances'
      and column_row.column_name = 'reason_code'
  )
  and exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'employee_advances'
      and column_row.column_name = 'reason_explanation'
  )
  and exists (
    select 1
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'employee_advances'
      and column_row.column_name = 'work_ended_on'
  ),
  'structured advance fields and their append-only evidence owner exist'
);

select ok(
  to_regprocedure(
    'public.is_locked_employee_advance_storage_object(text,text)'
  ) is null
  and to_regprocedure(
    'private.is_locked_employee_advance_storage_object(text,text)'
  ) is not null,
  'the Storage lock helper is not exposed as a public API RPC'
);

select ok(
  to_regprocedure(
    'public.employee_advance_receipt_policy_v1()'
  ) is null
  and to_regprocedure(
    'private.employee_advance_receipt_policy_v1()'
  ) is not null
  and not has_function_privilege(
    'authenticated',
    'private.employee_advance_receipt_policy_v1()',
    'EXECUTE'
  ),
  'the authoritative receipt policy remains private and unexposed'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname = 'vinabike_payroll_evidence_insert_scoped'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'INSERT'
  )
  and exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname =
        'vinabike_payroll_evidence_update_immutable'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'UPDATE'
  )
  and exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'storage'
      and policy.tablename = 'objects'
      and policy.policyname =
        'vinabike_payroll_evidence_delete_immutable'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'DELETE'
  ),
  'payroll evidence uploads are scoped and linked bytes are immutable'
);

select ok(
  (
    select count(*) = 4
    from information_schema.columns column_row
    where column_row.table_schema = 'public'
      and column_row.table_name = 'employee_advance_evidence'
      and column_row.column_name in (
        'storage_object_id',
        'storage_object_version',
        'storage_object_etag',
        'storage_object_owner_id'
      )
  )
  and exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'app_files'
      and policy.policyname = 'app_files_payroll_evidence_insert_guard'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'INSERT'
  )
  and exists (
    select 1
    from pg_catalog.pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'app_files'
      and policy.policyname = 'app_files_payroll_evidence_update_guard'
      and policy.permissive = 'RESTRICTIVE'
      and policy.cmd = 'UPDATE'
  ),
  'evidence records bind server Storage identity and guard metadata creation'
);

set local session_replication_role = replica;
select throws_ok(
  $$
    insert into public.employee_advances (
      tenant_id,
      employee_id,
      amount,
      payment_method_id,
      paid_at,
      reason_code,
      reason_explanation
    ) values (
      gen_random_uuid(),
      gen_random_uuid(),
      1000,
      gen_random_uuid(),
      statement_timestamp(),
      'requested_advance',
      null
    )
  $$,
  '23514',
  null,
  'the table constraint cannot be bypassed with a null explanation'
);

select throws_ok(
  $$
    insert into public.employee_advances (
      tenant_id,
      employee_id,
      amount,
      payment_method_id,
      paid_at,
      reason_code,
      reason_explanation
    ) values (
      gen_random_uuid(),
      gen_random_uuid(),
      1000,
      gen_random_uuid(),
      statement_timestamp(),
      null,
      'Estado parcial que no debe existir'
    )
  $$,
  '23514',
  null,
  'the table constraint rejects explanation without a canonical reason code'
);
set local session_replication_role = origin;

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-unauth-0001',
      gen_random_uuid(),
      1000,
      gen_random_uuid(),
      gen_random_uuid(),
      statement_timestamp(),
      null,
      null,
      'requested_advance',
      'Solicitud del trabajador',
      null,
      null,
      null
    )
  $$,
  '42501',
  'Payroll access denied',
  'an unauthenticated caller cannot create audited advances'
);

select throws_ok(
  $$
    select public.get_employee_advance_receipt_policy_v1()
  $$,
  '42501',
  'Payroll access denied',
  'an unauthenticated caller cannot probe payroll receipt capability'
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
    '7f2a1830-0000-4000-8000-000000000001',
    'Advance Audit Tenant A',
    'advance-audit-a',
    'advance-audit-a@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7f2a1830-0000-4000-8000-000000000002',
    'Advance Audit Tenant B',
    'advance-audit-b',
    'advance-audit-b@example.invalid',
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
    '7f2a1830-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'advance-audit-manager@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f2a1830-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'advance-audit-cashier@example.invalid',
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
    '7f2a1830-0000-4000-8000-000000000111',
    '7f2a1830-0000-4000-8000-000000000101',
    '7f2a1830-0000-4000-8000-000000000001',
    null,
    'manager',
    '{"manage_users":true}'::jsonb,
    true
  ),
  (
    '7f2a1830-0000-4000-8000-000000000112',
    '7f2a1830-0000-4000-8000-000000000102',
    '7f2a1830-0000-4000-8000-000000000001',
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
values (
  '7f2a1830-0000-4000-8000-000000000201',
  '7f2a1830-0000-4000-8000-000000000001',
  'ADV-AUDIT-201',
  'Rocío',
  'Maldonado',
  'Mecánica',
  'active'
);

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category,
  is_active
)
values (
  '7f2a1830-0000-4000-8000-000000000301',
  '7f2a1830-0000-4000-8000-000000000001',
  '1110',
  'Banco auditado',
  'asset',
  'currentAsset',
  true
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
  '7f2a1830-0000-4000-8000-000000000401',
  '7f2a1830-0000-4000-8000-000000000001',
  'transfer',
  'Transferencia',
  '7f2a1830-0000-4000-8000-000000000301',
  'no_tax',
  true
);

insert into public.app_files (
  id,
  tenant_id,
  uploaded_by,
  file_name,
  storage_bucket,
  storage_path,
  mime_type,
  size_bytes,
  source_type,
  source_id,
  context_type,
  context_id,
  metadata
)
values
  (
    '7f2a1830-0000-4000-8000-000000000501',
    '7f2a1830-0000-4000-8000-000000000001',
    '7f2a1830-0000-4000-8000-000000000101',
    'comprobante-anticipo.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/receipt.pdf',
    'application/pdf',
    128,
    'payroll_advance',
    'advance-audit-create-0001',
    'payroll_advance_operation',
    'advance-audit-create-0001',
    '{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operation_key":"advance-audit-create-0001"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000502',
    '7f2a1830-0000-4000-8000-000000000002',
    null,
    'otro-tenant.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000002/evidence/payroll_advance/receipt.pdf',
    'application/pdf',
    64,
    'payroll_advance',
    'advance-audit-cross-file-0001',
    'payroll_advance_operation',
    'advance-audit-cross-file-0001',
    '{"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","operation_key":"advance-audit-cross-file-0001"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000503',
    '7f2a1830-0000-4000-8000-000000000001',
    '7f2a1830-0000-4000-8000-000000000101',
    'archivo-ajeno.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/misc/foreign.pdf',
    'application/pdf',
    64,
    'manual',
    'supplier-1',
    'supplier',
    'supplier-1',
    '{"sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000504',
    '7f2a1830-0000-4000-8000-000000000001',
    '7f2a1830-0000-4000-8000-000000000101',
    'comprobante-conflicto.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/conflict.pdf',
    'application/pdf',
    96,
    'payroll_advance',
    'advance-audit-late-0001',
    'payroll_advance_operation',
    'advance-audit-late-0001',
    '{"sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","operation_key":"advance-audit-late-0001"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000505',
    '7f2a1830-0000-4000-8000-000000000001',
    '7f2a1830-0000-4000-8000-000000000101',
    'comprobante-sin-contexto.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/null-context.pdf',
    'application/pdf',
    80,
    'payroll_advance',
    'advance-audit-null-context-0001',
    null,
    null,
    '{"sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000507',
    '7f2a1830-0000-4000-8000-000000000001',
    '7f2a1830-0000-4000-8000-000000000101',
    'comprobante-namespace-falso.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payrollXadvance/receipt.pdf',
    'application/pdf',
    72,
    'payroll_advance',
    'advance-audit-bad-namespace-0001',
    'payroll_advance_operation',
    'advance-audit-bad-namespace-0001',
    '{"sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","operation_key":"advance-audit-bad-namespace-0001"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000508',
    '7f2a1830-0000-4000-8000-000000000001',
    '7f2a1830-0000-4000-8000-000000000101',
    'comprobante-owner-ajeno.pdf',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/owner-mismatch.pdf',
    'application/pdf',
    88,
    'payroll_advance',
    'advance-audit-owner-mismatch-0001',
    'payroll_advance_operation',
    'advance-audit-owner-mismatch-0001',
    '{"sha256":"abababababababababababababababababababababababababababababababab","operation_key":"advance-audit-owner-mismatch-0001"}'::jsonb
  );

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values ('vinabike-files', 'vinabike-files', false, 52428800, null)
on conflict (id) do nothing;

insert into storage.objects (
  bucket_id,
  name,
  owner_id,
  version,
  metadata
)
values
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/receipt.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-create-0001',
    '{"size":128,"mimetype":"application/pdf","eTag":"etag-create-0001"}'::jsonb
  ),
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000002/evidence/payroll_advance/receipt.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-cross-0001',
    '{"size":64,"mimetype":"application/pdf","eTag":"etag-cross-0001"}'::jsonb
  ),
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/conflict.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-conflict-0001',
    '{"size":96,"mimetype":"application/pdf","eTag":"etag-conflict-0001"}'::jsonb
  ),
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/null-context.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-null-context-0001',
    '{"size":80,"mimetype":"application/pdf","eTag":"etag-null-context-0001"}'::jsonb
  ),
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payrollXadvance/receipt.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-lookalike-0001',
    '{"size":72,"mimetype":"application/pdf","eTag":"etag-lookalike-0001"}'::jsonb
  ),
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/owner-mismatch.pdf',
    '7f2a1830-0000-4000-8000-000000000102',
    'version-owner-mismatch-0001',
    '{"size":88,"mimetype":"application/pdf","eTag":"etag-owner-mismatch-0001"}'::jsonb
  ),
  (
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/owner-insert-mismatch.pdf',
    '7f2a1830-0000-4000-8000-000000000102',
    'version-owner-insert-mismatch-0001',
    '{"size":89,"mimetype":"application/pdf","eTag":"etag-owner-insert-mismatch-0001"}'::jsonb
  );

select throws_ok(
  $$
    insert into public.app_files (
      id,
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000506',
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'comprobante-duplicado.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/payroll/duplicate.pdf',
      'application/pdf',
      128,
      'payroll_advance',
      'advance-audit-create-0001',
      'payroll_advance_operation',
      'advance-audit-create-0001',
      '{"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operation_key":"advance-audit-create-0001"}'::jsonb
    )
  $$,
  '23505',
  null,
  'one operation cannot own two active original receipt rows'
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f2a1830-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f2a1830-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select is(
  public.get_employee_advance_receipt_policy_v1(),
  jsonb_build_object(
    'contract_version', 1,
    'max_size_bytes', 12582912,
    'allowed_mime_types', jsonb_build_array(
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    )
  ),
  'the capability returns the exact versioned size and MIME contract'
);

select lives_ok(
  $$
    insert into public.app_files (
      id,
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000509',
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'archivo-ordinario.txt',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/misc/ordinary-null-context.txt',
      'text/plain',
      12,
      'manual',
      null,
      null,
      '{}'::jsonb
    )
  $$,
  'an ordinary app_file with null context remains valid'
);

-- The production-derived scratch deliberately does not grant direct SQL usage
-- on the managed storage schema. Seed Storage rows as fixtures; the real API
-- path is covered by the companion Storage + PostgREST smoke.
reset role;
set local session_replication_role = replica;
insert into storage.objects (
  id,
  bucket_id,
  name,
  owner_id,
  version,
  metadata
)
values
  (
    '7f2a1830-0000-4000-8000-000000000911',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/orphan.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-orphan-0001',
    '{"size":20,"mimetype":"application/pdf","eTag":"etag-orphan-0001"}'::jsonb
  ),
  (
    '7f2a1830-0000-4000-8000-000000000912',
    'vinabike-files',
    '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/positive.pdf',
    '7f2a1830-0000-4000-8000-000000000101',
    'version-positive-0001',
    '{"size":22,"mimetype":"application/pdf","eTag":"etag-positive-0001"}'::jsonb
  );
set local session_replication_role = origin;

select ok(
  (
    select count(*) = 2
    from storage.objects object
    where object.id in (
      '7f2a1830-0000-4000-8000-000000000911',
      '7f2a1830-0000-4000-8000-000000000912'
    )
  ),
  'Storage fixtures preserve server owner, version and ETag identity'
);

select lives_ok(
  $$
    update storage.objects
    set metadata = jsonb_set(metadata, '{size}', '21'::jsonb)
    where id = '7f2a1830-0000-4000-8000-000000000911'
  $$,
  'an unclaimed evidence upload remains mutable for deliberate cleanup'
);

set local role authenticated;

select lives_ok(
  $$
    insert into public.app_files (
      id,
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000510',
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'comprobante-positivo.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/positive.pdf',
      'application/pdf',
      22,
      'payroll_advance',
      'advance-audit-positive-policy-0001',
      'payroll_advance_operation',
      'advance-audit-positive-policy-0001',
      '{"sha256":"adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad","operation_key":"advance-audit-positive-policy-0001"}'::jsonb
    )
  $$,
  'Storage then validated app_files succeeds through origin triggers and RLS'
);

select throws_ok(
  $$
    insert into public.app_files (
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'etiqueta-falsa.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/misc/freeze-target.pdf',
      'application/pdf',
      10,
      'payroll_advance',
      'advance-audit-spoof-0001',
      'payroll_advance_operation',
      'advance-audit-spoof-0001',
      '{"sha256":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","operation_key":"advance-audit-spoof-0001"}'::jsonb
    )
  $$,
  '42501',
  null,
  'a caller cannot freeze an arbitrary object with payroll metadata'
);

select throws_ok(
  $$
    insert into public.app_files (
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'owner-ajeno.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/owner-insert-mismatch.pdf',
      'application/pdf',
      89,
      'payroll_advance',
      'advance-audit-owner-insert-0001',
      'payroll_advance_operation',
      'advance-audit-owner-insert-0001',
      '{"sha256":"acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac","operation_key":"advance-audit-owner-insert-0001"}'::jsonb
    )
  $$,
  '42501',
  'payroll_advance_app_file_identity_invalid',
  'app_files metadata cannot claim an object owned by another actor'
);

select throws_ok(
  $$
    update public.app_files
    set source_type = 'payroll_advance',
        source_id = 'advance-audit-spoof-update-0001',
        context_type = 'payroll_advance_operation',
        context_id = 'advance-audit-spoof-update-0001',
        metadata = jsonb_build_object(
          'sha256',
          'efefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef',
          'operation_key',
          'advance-audit-spoof-update-0001'
        )
    where id = '7f2a1830-0000-4000-8000-000000000503'
  $$,
  '42501',
  null,
  'an ordinary file cannot be relabelled as payroll evidence on update'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-invalid-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      'Prueba',
      'free_text_is_not_a_reason',
      'Prueba',
      null,
      null,
      null
    )
  $$,
  '22023',
  'payroll_advance_invalid_reason',
  'a free-text reason code is rejected before money moves'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-short-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      'Prueba',
      'short_workweek',
      'Terminó la semana antes',
      null,
      null,
      null
    )
  $$,
  '22023',
  'payroll_advance_invalid_reason',
  'a short workweek cannot omit work_ended_on'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-cross-file-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      'Prueba',
      'requested_advance',
      'Solicitud del trabajador',
      null,
      '7f2a1830-0000-4000-8000-000000000502',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    )
  $$,
  '42501',
  'payroll_advance_evidence_not_found',
  'an original receipt from another tenant is indistinguishable from missing'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-foreign-flow-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      'Prueba',
      'requested_advance',
      'Solicitud del trabajador',
      null,
      '7f2a1830-0000-4000-8000-000000000503',
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    )
  $$,
  '42501',
  'payroll_advance_evidence_not_found',
  'a tenant file from another workflow cannot become payroll evidence'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-bad-namespace-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      'Prueba',
      'requested_advance',
      'Solicitud del trabajador',
      null,
      '7f2a1830-0000-4000-8000-000000000507',
      'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    )
  $$,
  '42501',
  'payroll_advance_evidence_not_found',
  'a lookalike Storage namespace is not accepted as immutable evidence'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-owner-mismatch-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      'Prueba',
      'requested_advance',
      'Solicitud del trabajador',
      null,
      '7f2a1830-0000-4000-8000-000000000508',
      'abababababababababababababababababababababababababababababababab'
    )
  $$,
  '42501',
  'payroll_advance_evidence_not_found',
  'an object owned by another actor cannot be certified as payroll evidence'
);

select set_config(
  'test.advance_audit.receipt',
  public.register_employee_advance_v3(
    'advance-audit-create-0001',
    '7f2a1830-0000-4000-8000-000000000201',
    25000,
    '7f2a1830-0000-4000-8000-000000000401',
    '7f2a1830-0000-4000-8000-000000000301',
    '2026-07-30 15:00:00+00',
    'ADV-AUDIT-001',
    'Solicitud del trabajador',
    'requested_advance',
    'Solicitud expresa para locomoción',
    null,
    '7f2a1830-0000-4000-8000-000000000501',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )::text,
  true
);

select ok(
  (current_setting('test.advance_audit.receipt')::jsonb->>'replayed')::boolean
    is false
  and current_setting('test.advance_audit.receipt')::jsonb->>'reason_code' =
    'requested_advance'
  and current_setting('test.advance_audit.receipt')::jsonb
    ->>'evidence_storage_object_version' = 'version-create-0001'
  and current_setting('test.advance_audit.receipt')::jsonb
    ->>'evidence_storage_object_etag' = 'etag-create-0001'
  and (
    select advance.reason_explanation = 'Solicitud expresa para locomoción'
      and advance.work_ended_on is null
    from public.employee_advances advance
    where advance.id = (
      current_setting('test.advance_audit.receipt')::jsonb->>'advance_id'
    )::uuid
  )
  and (
    select count(*) = 1
    from public.employee_advance_evidence evidence
    where evidence.advance_id = (
      current_setting('test.advance_audit.receipt')::jsonb->>'advance_id'
    )::uuid
      and evidence.file_sha256 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      and evidence.storage_object_version = 'version-create-0001'
      and evidence.storage_object_etag = 'etag-create-0001'
      and evidence.storage_object_owner_id =
        '7f2a1830-0000-4000-8000-000000000101'
  ),
  'v3 atomically binds money and audit to the server-owned Storage identity'
);

select ok(
  (
    public.register_employee_advance_v3(
      'advance-audit-create-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      'ADV-AUDIT-001',
      'Solicitud del trabajador',
      'requested_advance',
      'Solicitud expresa para locomoción',
      null,
      '7f2a1830-0000-4000-8000-000000000501',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    )->>'replayed'
  )::boolean
  and (
    select count(*) = 1
    from public.employee_advance_evidence evidence
    where evidence.advance_id = (
      current_setting('test.advance_audit.receipt')::jsonb->>'advance_id'
    )::uuid
  ),
  'an exact retry is reported as replay and cannot duplicate evidence'
);

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-create-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      25000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      'ADV-AUDIT-001',
      'Solicitud del trabajador',
      'other',
      'Una explicación distinta',
      null,
      '7f2a1830-0000-4000-8000-000000000501',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    )
  $$,
  'P0001',
  'payroll_advance_audit_idempotency_conflict',
  'one operation key cannot be replayed with different audit meaning'
);

select set_config(
  'test.advance_audit.holder_receipt',
  public.register_employee_advance_v2(
    'advance-audit-holder-0001',
    '7f2a1830-0000-4000-8000-000000000201',
    6000,
    '7f2a1830-0000-4000-8000-000000000401',
    '7f2a1830-0000-4000-8000-000000000301',
    '2026-07-29 16:00:00+00',
    'ADV-HOLDER-001',
    'Fila para conflicto tardío'
  )::text,
  true
);

reset role;
set local session_replication_role = replica;
insert into public.employee_advance_evidence (
  id,
  tenant_id,
  advance_id,
  app_file_id,
  storage_object_id,
  storage_object_version,
  storage_object_etag,
  storage_object_owner_id,
  file_sha256,
  created_by
)
values (
  '7f2a1830-0000-4000-8000-000000000604',
  '7f2a1830-0000-4000-8000-000000000001',
  (
    current_setting('test.advance_audit.holder_receipt')::jsonb
      ->>'advance_id'
  )::uuid,
  '7f2a1830-0000-4000-8000-000000000504',
  (
    select object.id
    from storage.objects object
    where object.bucket_id = 'vinabike-files'
      and object.name =
        '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/conflict.pdf'
  ),
  'version-conflict-0001',
  'etag-conflict-0001',
  '7f2a1830-0000-4000-8000-000000000101',
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  '7f2a1830-0000-4000-8000-000000000101'
);
set local session_replication_role = origin;
set local role authenticated;

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-late-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      7000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-29 17:00:00+00',
      'ADV-LATE-001',
      'Debe revertirse completo',
      'requested_advance',
      'Solicitud con conflicto tardío simulado',
      null,
      '7f2a1830-0000-4000-8000-000000000504',
      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
    )
  $$,
  '23505',
  null,
  'a late evidence conflict aborts the outer money transaction'
);

select ok(
  not exists (
    select 1
    from public.payroll_money_operations money_operation
    where money_operation.tenant_id =
      '7f2a1830-0000-4000-8000-000000000001'
      and money_operation.operation_key = 'advance-audit-late-0001'
  )
  and not exists (
    select 1
    from public.employee_advances advance
    where advance.tenant_id = '7f2a1830-0000-4000-8000-000000000001'
      and advance.reference = 'ADV-LATE-001'
  ),
  'late evidence failure leaves no money operation or employee advance'
);

select set_config(
  'test.advance_audit.null_context_receipt',
  public.register_employee_advance_v2(
    'advance-audit-null-context-0001',
    '7f2a1830-0000-4000-8000-000000000201',
    8000,
    '7f2a1830-0000-4000-8000-000000000401',
    '7f2a1830-0000-4000-8000-000000000301',
    '2026-07-29 18:00:00+00',
    'ADV-NULL-CONTEXT-001',
    'Prueba de invariant independiente'
  )::text,
  true
);

reset role;
select throws_ok(
  $$
    insert into public.employee_advance_evidence (
      tenant_id,
      advance_id,
      app_file_id,
      file_sha256,
      created_by
    ) values (
      '7f2a1830-0000-4000-8000-000000000001',
      (
        current_setting('test.advance_audit.null_context_receipt')::jsonb
          ->>'advance_id'
      )::uuid,
      '7f2a1830-0000-4000-8000-000000000505',
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      '7f2a1830-0000-4000-8000-000000000101'
    )
  $$,
  '22023',
  'employee_advance_evidence_invalid',
  'the evidence trigger rejects a payroll file with null operation context'
);
set local role authenticated;

select ok(
  (
    public.get_employee_advance_ledger_page_v2(
      '7f2a1830-0000-4000-8000-000000000201',
      25,
      null,
      null
    )->>'contract_version'
  )::integer = 2
  and public.get_employee_advance_ledger_page_v2(
    '7f2a1830-0000-4000-8000-000000000201',
    25,
    null,
    null
  )#>>'{items,0,reason,code}' = 'requested_advance'
  and public.get_employee_advance_ledger_page_v2(
    '7f2a1830-0000-4000-8000-000000000201',
    25,
    null,
    null
  )#>>'{items,0,original_evidence,sha256}' =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  and public.get_employee_advance_ledger_page_v2(
    '7f2a1830-0000-4000-8000-000000000201',
    25,
    null,
    null
  )#>>'{items,0,original_evidence,storage_object_version}' =
    'version-create-0001'
  and public.get_employee_advance_ledger_page_v2(
    '7f2a1830-0000-4000-8000-000000000201',
    25,
    null,
    null
  )#>>'{items,0,original_evidence,storage_object_etag}' =
    'etag-create-0001',
  'ledger v2 exposes the structured reason and immutable evidence snapshot'
);

reset role;

-- Exercise the receipt namespace's restrictive Storage policy itself. The
-- production-derived scratch lacks direct managed-schema grants, so grant only
-- INSERT inside this rolled-back transaction. Replica mode disables Storage
-- triggers but leaves RLS active, isolating the policy under test.
grant usage on schema storage to authenticated;
grant insert on table storage.objects to authenticated;
grant insert on table public.app_files to authenticated;
set local session_replication_role = replica;
select set_config(
  'request.jwt.claims',
  '{"sub":"7f2a1830-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f2a1830-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select lives_ok(
  $$
    insert into storage.objects (
      id,
      bucket_id,
      name,
      owner_id,
      version,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000921',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-exact.pdf',
      '7f2a1830-0000-4000-8000-000000000101',
      'version-policy-exact-0001',
      '{"size":12582912,"contentType":" Application/PDF; charset=binary ","eTag":"etag-policy-exact-0001"}'::jsonb
    )
  $$,
  'the Storage policy accepts exactly 12 MiB and contentType fallback'
);

select throws_ok(
  $$
    insert into storage.objects (
      id,
      bucket_id,
      name,
      owner_id,
      version,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000922',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-too-large.pdf',
      '7f2a1830-0000-4000-8000-000000000101',
      'version-policy-too-large-0001',
      '{"size":12582913,"mimetype":"application/pdf","eTag":"etag-policy-too-large-0001"}'::jsonb
    )
  $$,
  '42501',
  null,
  'the Storage policy rejects one byte above the receipt limit'
);

select throws_ok(
  $$
    insert into storage.objects (
      id,
      bucket_id,
      name,
      owner_id,
      version,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000923',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-gif.gif',
      '7f2a1830-0000-4000-8000-000000000101',
      'version-policy-gif-0001',
      '{"size":64,"mimetype":"image/gif","eTag":"etag-policy-gif-0001"}'::jsonb
    )
  $$,
  '42501',
  null,
  'the Storage policy rejects MIME outside the four-format allowlist'
);

select lives_ok(
  $$
    insert into storage.objects (
      id,
      bucket_id,
      name,
      owner_id,
      version,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000924',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/misc/ordinary-large.gif',
      '7f2a1830-0000-4000-8000-000000000101',
      'version-policy-ordinary-0001',
      '{"size":12582913,"mimetype":"image/gif","eTag":"etag-policy-ordinary-0001"}'::jsonb
    )
  $$,
  'the payroll receipt policy does not narrow the shared bucket globally'
);

select lives_ok(
  $$
    insert into storage.objects (
      id,
      bucket_id,
      name,
      owner_id,
      version,
      metadata
    ) values
      (
        '7f2a1830-0000-4000-8000-000000000925',
        'vinabike-files',
        '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-mime-cross.png',
        '7f2a1830-0000-4000-8000-000000000101',
        'version-policy-mime-cross-0001',
        '{"size":64,"mimetype":"image/png","eTag":"etag-policy-mime-cross-0001"}'::jsonb
      ),
      (
        '7f2a1830-0000-4000-8000-000000000926',
        'vinabike-files',
        '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-size-cross.pdf',
        '7f2a1830-0000-4000-8000-000000000101',
        'version-policy-size-cross-0001',
        '{"size":64,"mimetype":"application/pdf","eTag":"etag-policy-size-cross-0001"}'::jsonb
      )
  $$,
  'allowed Storage fixtures exist for app_files cross-check tests'
);

reset role;
set local session_replication_role = origin;
set local role authenticated;

select lives_ok(
  $$
    insert into public.app_files (
      id,
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000521',
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'policy-exact.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-exact.pdf',
      'application/pdf',
      12582912,
      'payroll_advance',
      'advance-audit-policy-exact-0001',
      'payroll_advance_operation',
      'advance-audit-policy-exact-0001',
      '{"sha256":"1212121212121212121212121212121212121212121212121212121212121212","operation_key":"advance-audit-policy-exact-0001"}'::jsonb
    )
  $$,
  'app_files accepts the exact boundary when Storage size and MIME match'
);

select throws_ok(
  $$
    insert into public.app_files (
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'policy-mime-cross.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-mime-cross.png',
      'application/pdf',
      64,
      'payroll_advance',
      'advance-audit-policy-mime-cross-0001',
      'payroll_advance_operation',
      'advance-audit-policy-mime-cross-0001',
      '{"sha256":"3434343434343434343434343434343434343434343434343434343434343434","operation_key":"advance-audit-policy-mime-cross-0001"}'::jsonb
    )
  $$,
  '42501',
  'payroll_advance_app_file_identity_invalid',
  'app_files rejects a declared MIME crossed with Storage metadata'
);

select throws_ok(
  $$
    insert into public.app_files (
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000101',
      'policy-size-cross.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/policy-size-cross.pdf',
      'application/pdf',
      65,
      'payroll_advance',
      'advance-audit-policy-size-cross-0001',
      'payroll_advance_operation',
      'advance-audit-policy-size-cross-0001',
      '{"sha256":"5656565656565656565656565656565656565656565656565656565656565656","operation_key":"advance-audit-policy-size-cross-0001"}'::jsonb
    )
  $$,
  '42501',
  'payroll_advance_app_file_identity_invalid',
  'app_files rejects a size crossed with Storage metadata'
);

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f2a1830-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f2a1830-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.get_employee_advance_receipt_policy_v1()
  $$,
  '42501',
  'Payroll access denied',
  'a non-payroll user cannot probe the receipt policy capability'
);

-- Exercise the restrictive INSERT policies themselves. The production-derived
-- scratch intentionally lacks direct grants on Supabase's managed Storage
-- schema, so grant only the minimum inside this rolled-back pgTAP transaction.
-- Replica mode disables the identity trigger here; otherwise that trigger
-- would reject first and a regression in the RLS policy could stay hidden.
reset role;
set local session_replication_role = replica;
set local role authenticated;

select throws_ok(
  $$
    insert into storage.objects (
      id,
      bucket_id,
      name,
      owner_id,
      version,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000913',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/cashier-denied.pdf',
      '7f2a1830-0000-4000-8000-000000000102',
      'version-cashier-denied-0001',
      '{"size":24,"mimetype":"application/pdf","eTag":"etag-cashier-denied-0001"}'::jsonb
    )
  $$,
  '42501',
  null,
  'a non-payroll user cannot insert an employee-advance Storage object'
);

select throws_ok(
  $$
    insert into public.app_files (
      id,
      tenant_id,
      uploaded_by,
      file_name,
      storage_bucket,
      storage_path,
      mime_type,
      size_bytes,
      source_type,
      source_id,
      context_type,
      context_id,
      metadata
    ) values (
      '7f2a1830-0000-4000-8000-000000000511',
      '7f2a1830-0000-4000-8000-000000000001',
      '7f2a1830-0000-4000-8000-000000000102',
      'cashier-denied.pdf',
      'vinabike-files',
      '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/cashier-denied.pdf',
      'application/pdf',
      24,
      'payroll_advance',
      'advance-audit-cashier-policy-0001',
      'payroll_advance_operation',
      'advance-audit-cashier-policy-0001',
      '{"sha256":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","operation_key":"advance-audit-cashier-policy-0001"}'::jsonb
    )
  $$,
  '42501',
  null,
  'a non-payroll user cannot insert employee-advance app_file metadata'
);

reset role;
set local session_replication_role = origin;

select is(
  (
    select count(*)
    from storage.objects object
    where object.id = '7f2a1830-0000-4000-8000-000000000913'
  ) + (
    select count(*)
    from public.app_files app_file
    where app_file.id = '7f2a1830-0000-4000-8000-000000000511'
  ),
  0::bigint,
  'denied cashier inserts leave no Storage or app_files residue'
);

set local role authenticated;

select throws_ok(
  $$
    select public.register_employee_advance_v3(
      'advance-audit-cashier-0001',
      '7f2a1830-0000-4000-8000-000000000201',
      1000,
      '7f2a1830-0000-4000-8000-000000000401',
      '7f2a1830-0000-4000-8000-000000000301',
      '2026-07-30 15:00:00+00',
      null,
      null,
      'requested_advance',
      'Solicitud sin permiso de nóminas',
      null,
      null,
      null
    )
  $$,
  '42501',
  'Payroll access denied',
  'an authenticated non-payroll user cannot execute advance v3'
);

select throws_ok(
  $$
    select public.get_employee_advance_ledger_page_v2(
      '7f2a1830-0000-4000-8000-000000000201',
      25,
      null,
      null
    )
  $$,
  '42501',
  'Payroll access denied',
  'an authenticated non-payroll user cannot execute ledger v2'
);

select is(
  (select count(*) from public.employee_advance_evidence),
  0::bigint,
  'evidence RLS hides rows from an authenticated non-payroll user'
);

reset role;

select throws_ok(
  $$
    update public.employee_advance_evidence
    set file_sha256 =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    where advance_id = (
      current_setting('test.advance_audit.receipt')::jsonb->>'advance_id'
    )::uuid
  $$,
  '55000',
  'employee_advance_evidence_is_immutable',
  'the original-receipt link cannot be rewritten'
);

select throws_ok(
  $$
    delete from public.employee_advance_evidence
    where advance_id = (
      current_setting('test.advance_audit.receipt')::jsonb->>'advance_id'
    )::uuid
  $$,
  '55000',
  'employee_advance_evidence_is_immutable',
  'the original-receipt link cannot be deleted'
);

select throws_ok(
  $$
    update public.employee_advances
    set reason_explanation = 'Intento de reescritura'
    where id = (
      current_setting('test.advance_audit.receipt')::jsonb->>'advance_id'
    )::uuid
  $$,
  '55000',
  'payroll_money_receipt_movement_is_immutable',
  'structured audit fields cannot be rewritten outside the command context'
);

select throws_ok(
  $$
    update public.app_files
    set deleted_at = statement_timestamp()
    where id = '7f2a1830-0000-4000-8000-000000000501'
  $$,
  '55000',
  'employee_advance_evidence_file_is_immutable',
  'a linked financial receipt cannot be soft-deleted or replaced'
);

select throws_ok(
  $$
    delete from public.app_files
    where id = '7f2a1830-0000-4000-8000-000000000501'
  $$,
  '55000',
  'employee_advance_evidence_file_is_immutable',
  'a linked financial receipt cannot be deleted'
);

select throws_ok(
  $$
    update storage.objects
    set metadata = jsonb_set(metadata, '{size}', '999'::jsonb)
    where bucket_id = 'vinabike-files'
      and name =
        '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/receipt.pdf'
  $$,
  '55000',
  'employee_advance_evidence_object_is_immutable',
  'the linked receipt object cannot be overwritten'
);

select throws_ok(
  $$
    delete from storage.objects
    where bucket_id = 'vinabike-files'
      and name =
        '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/receipt.pdf'
  $$,
  '42501',
  'Direct deletion from storage tables is not allowed. Use the Storage API instead.',
  'direct SQL cannot delete the linked receipt object'
);

select ok(
  exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'vinabike-files'
      and object.name =
        '7f2a1830-0000-4000-8000-000000000001/evidence/payroll_advance/receipt.pdf'
      and object.metadata->>'size' = '128'
  ),
  'failed overwrite and delete attempts preserve the original object'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"7f2a1830-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f2a1830-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select set_config(
  'test.advance_audit.legacy_receipt',
  public.register_employee_advance_v2(
    'advance-audit-legacy-0001',
    '7f2a1830-0000-4000-8000-000000000201',
    5000,
    '7f2a1830-0000-4000-8000-000000000401',
    '7f2a1830-0000-4000-8000-000000000301',
    '2026-07-29 15:00:00+00',
    null,
    'Cliente publicado'
  )::text,
  true
);

select ok(
  (
    select advance.reason_code is null
      and advance.reason_explanation is null
      and advance.work_ended_on is null
    from public.employee_advances advance
    where advance.id = (
      current_setting('test.advance_audit.legacy_receipt')::jsonb
        ->>'advance_id'
    )::uuid
  ),
  'the still-supported v2 path remains explicit legacy data, not invented audit'
);

reset role;
select * from finish();
rollback;
