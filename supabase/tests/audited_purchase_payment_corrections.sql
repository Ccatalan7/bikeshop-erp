begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(54);

create temp table purchase_payment_correction_failures (
  name text primary key,
  passed boolean not null,
  message text
) on commit drop;

select ok(
  not exists (
    select 1
      from pg_trigger trigger_row
     where trigger_row.tgrelid = 'public.purchase_invoices'::regclass
       and trigger_row.tgname = 'trg_update_purchase_invoice_balance'
       and not trigger_row.tgisinternal
  ),
  'obsolete total-minus-gross purchase balance trigger is not active'
);

insert into public.tenants(id, shop_name) values
  (
    '9b240000-0000-4000-8000-000000000001',
    'Purchase Payment Correction Tenant A'
  ),
  (
    '9b240000-0000-4000-8000-000000000101',
    'Purchase Payment Correction Tenant B'
  );

-- Tenant bootstrap helpers may set a transaction-local subject. Fixture
-- accounting writes intentionally run without an employee JWT.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table purchase_correction_methods on commit drop as
select
  tenant_id,
  (array_agg(id order by id) filter (where code = 'cash'))[1] as cash_id,
  (array_agg(id order by id) filter (where code = 'transfer'))[1]
    as transfer_id
from public.payment_methods
where tenant_id in (
  '9b240000-0000-4000-8000-000000000001',
  '9b240000-0000-4000-8000-000000000101'
)
group by tenant_id;

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, net_amount, tax, iva_amount, total, paid_amount, balance,
  items, received_date
) values
  (
    '9b240000-0000-4000-8000-000000000020',
    '9b240000-0000-4000-8000-000000000001',
    'FC-PAY-CORR-MAIN', 'Main Correction Supplier', 'received',
    20000, 20000, 0, 0, 20000, 0, 20000, '[]'::jsonb,
    '2026-07-20 12:00:00+00'::timestamptz
  ),
  (
    '9b240000-0000-4000-8000-000000000030',
    '9b240000-0000-4000-8000-000000000001',
    'FC-PAY-CORR-LEGACY', 'Legacy Correction Supplier', 'confirmed',
    12000, 12000, 0, 0, 12000, 0, 12000, '[]'::jsonb, null
  ),
  (
    '9b240000-0000-4000-8000-000000000040',
    '9b240000-0000-4000-8000-000000000001',
    'FC-PAY-CORR-AMBIG', 'Ambiguous Correction Supplier', 'confirmed',
    10000, 10000, 0, 0, 10000, 0, 10000, '[]'::jsonb, null
  ),
  (
    '9b240000-0000-4000-8000-000000000050',
    '9b240000-0000-4000-8000-000000000001',
    'FC-PAY-CORR-MISSING', 'Missing Journal Supplier', 'confirmed',
    10000, 10000, 0, 0, 10000, 0, 10000, '[]'::jsonb, null
  ),
  (
    '9b240000-0000-4000-8000-000000000060',
    '9b240000-0000-4000-8000-000000000001',
    'FC-PAY-CORR-MIXED', 'Mixed Journal Supplier', 'confirmed',
    10000, 10000, 0, 0, 10000, 0, 10000, '[]'::jsonb, null
  ),
  (
    '9b240000-0000-4000-8000-000000000070',
    '9b240000-0000-4000-8000-000000000001',
    'FC-PAY-CORR-CREDIT', 'Credited Correction Supplier', 'received',
    10000, 10000, 0, 0, 10000, 0, 10000, '[]'::jsonb,
    '2026-07-20 12:00:00+00'::timestamptz
  );

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id,
  idempotency_key, amount, date, reference, notes
)
select
  fixture.id, fixture.tenant_id, fixture.invoice_id, method.cash_id,
  fixture.idempotency_key, fixture.amount,
  fixture.payment_date, fixture.reference, fixture.notes
from (
  values
    (
      '9b240000-0000-4000-8000-000000000021'::uuid,
      '9b240000-0000-4000-8000-000000000001'::uuid,
      '9b240000-0000-4000-8000-000000000020'::uuid,
      'purchase-correction-main-original'::text,
      5000::numeric,
      '2026-07-20 15:00:00+00'::timestamptz,
      'MAIN-REF-1'::text,
      'Original main note'::text
    ),
    (
      '9b240000-0000-4000-8000-000000000031'::uuid,
      '9b240000-0000-4000-8000-000000000001'::uuid,
      '9b240000-0000-4000-8000-000000000030'::uuid,
      'purchase-correction-legacy-original'::text,
      4000::numeric,
      '2026-07-20 16:00:00+00'::timestamptz,
      'LEGACY-REF-1'::text,
      'Original legacy note'::text
    ),
    (
      '9b240000-0000-4000-8000-000000000041'::uuid,
      '9b240000-0000-4000-8000-000000000001'::uuid,
      '9b240000-0000-4000-8000-000000000040'::uuid,
      'purchase-correction-ambiguous-original'::text,
      4000::numeric,
      '2026-07-20 17:00:00+00'::timestamptz,
      'AMBIG-REF-1'::text,
      'Original ambiguous note'::text
    ),
    (
      '9b240000-0000-4000-8000-000000000051'::uuid,
      '9b240000-0000-4000-8000-000000000001'::uuid,
      '9b240000-0000-4000-8000-000000000050'::uuid,
      'purchase-correction-missing-original'::text,
      4000::numeric,
      '2026-07-20 18:00:00+00'::timestamptz,
      'MISSING-REF-1'::text,
      'Original missing note'::text
    ),
    (
      '9b240000-0000-4000-8000-000000000061'::uuid,
      '9b240000-0000-4000-8000-000000000001'::uuid,
      '9b240000-0000-4000-8000-000000000060'::uuid,
      'purchase-correction-mixed-original'::text,
      4000::numeric,
      '2026-07-20 19:00:00+00'::timestamptz,
      'MIXED-REF-1'::text,
      'Original mixed note'::text
    ),
    (
      '9b240000-0000-4000-8000-000000000071'::uuid,
      '9b240000-0000-4000-8000-000000000001'::uuid,
      '9b240000-0000-4000-8000-000000000070'::uuid,
      'purchase-correction-credit-original'::text,
      10000::numeric,
      '2026-07-20 20:00:00+00'::timestamptz,
      'CREDIT-REF-1'::text,
      'Original credited note'::text
    )
) as fixture(
  id, tenant_id, invoice_id, idempotency_key,
  amount, payment_date, reference, notes
)
join purchase_correction_methods method
  on method.tenant_id = fixture.tenant_id;

create temp table purchase_main_baseline on commit drop as
select
  payment.updated_at,
  payment.invoice_id,
  payment.idempotency_key,
  payment.created_at,
  payment.deleted_at,
  payment.deleted_by,
  entry.id as journal_entry_id
from public.purchase_payments payment
join public.journal_entries entry
  on entry.tenant_id = payment.tenant_id
 and entry.source_module = 'purchase_payments'
 and entry.source_reference = payment.id::text
where payment.id = '9b240000-0000-4000-8000-000000000021';

-- Convert one fixture to the uniquely attributable historical linkage.
update public.journal_entries
   set source_reference = 'FC-PAY-CORR-LEGACY',
       source_document_type = null,
       source_document_id = null
 where tenant_id = '9b240000-0000-4000-8000-000000000001'
   and source_module = 'purchase_payments'
   and source_reference = '9b240000-0000-4000-8000-000000000031';

-- Convert one fixture to legacy and add a duplicate legacy journal.
update public.journal_entries
   set source_reference = 'FC-PAY-CORR-AMBIG',
       source_document_type = null,
       source_document_id = null
 where tenant_id = '9b240000-0000-4000-8000-000000000001'
   and source_module = 'purchase_payments'
   and source_reference = '9b240000-0000-4000-8000-000000000041';

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit,
  created_at, updated_at
)
select
  '9b240000-0000-4000-8000-000000000042',
  entry.tenant_id,
  public.get_next_document_number(entry.tenant_id, 'journal_entry'),
  entry.entry_date, entry.description || ' duplicate', entry.type,
  entry.source_module, entry.source_reference, entry.status,
  entry.total_debit, entry.total_credit, now(), now()
from public.journal_entries entry
where entry.tenant_id = '9b240000-0000-4000-8000-000000000001'
  and entry.source_module = 'purchase_payments'
  and entry.source_reference = 'FC-PAY-CORR-AMBIG'
order by entry.created_at
limit 1;

insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount, created_at, updated_at
)
select
  gen_random_uuid(), line.tenant_id,
  '9b240000-0000-4000-8000-000000000042',
  line.account_id, line.account_code, line.account_name,
  line.description || ' duplicate', line.debit_amount, line.credit_amount,
  now(), now()
from public.journal_lines line
join public.journal_entries entry on entry.id = line.entry_id
where entry.tenant_id = '9b240000-0000-4000-8000-000000000001'
  and entry.source_module = 'purchase_payments'
  and entry.source_reference = 'FC-PAY-CORR-AMBIG'
  and entry.id <> '9b240000-0000-4000-8000-000000000042';

-- Keep the UUID journal and add a second invoice-number candidate.
insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit,
  created_at, updated_at
)
select
  '9b240000-0000-4000-8000-000000000062',
  entry.tenant_id,
  public.get_next_document_number(entry.tenant_id, 'journal_entry'),
  entry.entry_date, entry.description || ' mixed legacy', entry.type,
  entry.source_module, 'FC-PAY-CORR-MIXED', entry.status,
  entry.total_debit, entry.total_credit, now(), now()
from public.journal_entries entry
where entry.tenant_id = '9b240000-0000-4000-8000-000000000001'
  and entry.source_module = 'purchase_payments'
  and entry.source_reference = '9b240000-0000-4000-8000-000000000061';

insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount, created_at, updated_at
)
select
  gen_random_uuid(), line.tenant_id,
  '9b240000-0000-4000-8000-000000000062',
  line.account_id, line.account_code, line.account_name,
  line.description || ' mixed legacy', line.debit_amount, line.credit_amount,
  now(), now()
from public.journal_lines line
join public.journal_entries entry on entry.id = line.entry_id
where entry.tenant_id = '9b240000-0000-4000-8000-000000000001'
  and entry.source_module = 'purchase_payments'
  and entry.source_reference = '9b240000-0000-4000-8000-000000000061';

-- The missing-journal fixture remains explicit review-only evidence.
delete from public.journal_entries
 where tenant_id = '9b240000-0000-4000-8000-000000000001'
   and source_module = 'purchase_payments'
   and source_reference = '9b240000-0000-4000-8000-000000000051';

-- Minimal posted credit/refund evidence exercises the current settlement
-- formula without calling an external provider or moving stock.
insert into public.inventory_accounting_operations (
  id, tenant_id, operation_key, source_channel, action,
  document_type, document_id, executor, outcome, completed_at
) values
  (
    '9b240000-0000-4000-8000-000000000073',
    '9b240000-0000-4000-8000-000000000001',
    'purchase-correction-credit-fixture',
    'purchase_credit_note', 'create', 'purchase_credit_note',
    '9b240000-0000-4000-8000-000000000072',
    'test_fixture', 'completed', clock_timestamp()
  ),
  (
    '9b240000-0000-4000-8000-000000000076',
    '9b240000-0000-4000-8000-000000000001',
    'purchase-correction-refund-fixture',
    'purchase_supplier_refund', 'create', 'purchase_supplier_refund',
    '9b240000-0000-4000-8000-000000000075',
    'test_fixture', 'completed', clock_timestamp()
  );

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit,
  operation_id, source_document_type, source_document_id,
  created_at, updated_at
) values
  (
    '9b240000-0000-4000-8000-000000000074',
    '9b240000-0000-4000-8000-000000000001',
    public.get_next_document_number(
      '9b240000-0000-4000-8000-000000000001',
      'journal_entry'
    ),
    now(), 'Credit fixture evidence', 'credit_note',
    'purchase_credit_notes', '9b240000-0000-4000-8000-000000000072',
    'posted', 0, 0,
    '9b240000-0000-4000-8000-000000000073',
    'purchase_credit_note', '9b240000-0000-4000-8000-000000000072',
    now(), now()
  ),
  (
    '9b240000-0000-4000-8000-000000000077',
    '9b240000-0000-4000-8000-000000000001',
    public.get_next_document_number(
      '9b240000-0000-4000-8000-000000000001',
      'journal_entry'
    ),
    now(), 'Refund fixture evidence', 'refund',
    'purchase_supplier_refunds', '9b240000-0000-4000-8000-000000000075',
    'posted', 0, 0,
    '9b240000-0000-4000-8000-000000000076',
    'purchase_supplier_refund', '9b240000-0000-4000-8000-000000000075',
    now(), now()
  );

insert into public.purchase_credit_notes (
  id, tenant_id, purchase_invoice_id, credit_note_number,
  status, official_dte_status, issue_date, reason_code, reason,
  net_amount, tax_amount, total_amount, idempotency_key,
  operation_id, journal_entry_id
) values (
  '9b240000-0000-4000-8000-000000000072',
  '9b240000-0000-4000-8000-000000000001',
  '9b240000-0000-4000-8000-000000000070',
  'NCC-PAY-CORR-001', 'posted', 'internal', now(),
  'price_correction', 'Credit fixture for payment settlement trace',
  3000, 0, 3000, 'purchase-correction-credit-note-fixture',
  '9b240000-0000-4000-8000-000000000073',
  '9b240000-0000-4000-8000-000000000074'
);

insert into public.purchase_supplier_refunds (
  id, tenant_id, purchase_invoice_id, purchase_credit_note_id,
  refund_number, status, refunded_at, payment_method_id, amount,
  reference, reason, idempotency_key, operation_id, journal_entry_id
)
select
  '9b240000-0000-4000-8000-000000000075',
  '9b240000-0000-4000-8000-000000000001',
  '9b240000-0000-4000-8000-000000000070',
  '9b240000-0000-4000-8000-000000000072',
  'RP-PAY-CORR-001', 'posted', now(), method.cash_id, 1000,
  'REFUND-FIXTURE-1', 'Refund fixture for payment settlement trace',
  'purchase-correction-refund-fixture',
  '9b240000-0000-4000-8000-000000000076',
  '9b240000-0000-4000-8000-000000000077'
from purchase_correction_methods method
where method.tenant_id = '9b240000-0000-4000-8000-000000000001';

select public.recalculate_purchase_invoice_settlement(
  '9b240000-0000-4000-8000-000000000070'
);

insert into auth.users (
  id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9b240000-0000-4000-8000-000000000099',
    'authenticated', 'authenticated',
    'purchase-pay-correction-admin-a@example.invalid',
    '', '{}'::jsonb,
    '{"account_type":"public_store_customer","customer_tenant_id":"9b240000-0000-4000-8000-000000000001"}'::jsonb,
    now(), now()
  ),
  (
    '9b240000-0000-4000-8000-000000000098',
    'authenticated', 'authenticated',
    'purchase-pay-correction-cashier-a@example.invalid',
    '', '{}'::jsonb,
    '{"account_type":"public_store_customer","customer_tenant_id":"9b240000-0000-4000-8000-000000000001"}'::jsonb,
    now(), now()
  ),
  (
    '9b240000-0000-4000-8000-000000000199',
    'authenticated', 'authenticated',
    'purchase-pay-correction-admin-b@example.invalid',
    '', '{}'::jsonb,
    '{"account_type":"public_store_customer","customer_tenant_id":"9b240000-0000-4000-8000-000000000101"}'::jsonb,
    now(), now()
  );

insert into public.user_profiles(user_id, tenant_id, role) values
  (
    '9b240000-0000-4000-8000-000000000099',
    '9b240000-0000-4000-8000-000000000001',
    'admin'
  ),
  (
    '9b240000-0000-4000-8000-000000000098',
    '9b240000-0000-4000-8000-000000000001',
    'cashier'
  ),
  (
    '9b240000-0000-4000-8000-000000000199',
    '9b240000-0000-4000-8000-000000000101',
    'admin'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"9b240000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b240000-0000-4000-8000-000000000099',
  true
);

select ok(
  not has_function_privilege(
    'anon',
    'public.correct_purchase_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'anonymous callers cannot run supplier-payment corrections'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.correct_purchase_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'authenticated employees can run the purchase correction command'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.correct_purchase_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'service role cannot bypass the employee purchase correction command'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.create_purchase_payment_journal_entry(uuid)',
    'execute'
  ),
  'anonymous callers cannot create supplier-payment journals directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_purchase_payment_journal_entry(uuid)',
    'execute'
  ),
  'employees cannot create supplier-payment journals outside the audited trigger path'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.create_purchase_payment_journal_entry(uuid)',
    'execute'
  ),
  'service role cannot create supplier-payment journals outside the audited trigger path'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.delete_purchase_payment_journal_entry(uuid)',
    'execute'
  ),
  'anonymous callers cannot delete supplier-payment journals directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.delete_purchase_payment_journal_entry(uuid)',
    'execute'
  ),
  'employees cannot delete supplier-payment journals outside the audited trigger path'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.delete_purchase_payment_journal_entry(uuid)',
    'execute'
  ),
  'service role cannot delete supplier-payment journals outside the audited trigger path'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_purchase_payment_edit_operation(text)',
    'execute'
  ),
  'authenticated employees can read back a committed correction receipt'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.purchase_payment_edit_events', 'select'
  ),
  'employees can read tenant-scoped supplier-payment correction history'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.purchase_payment_edit_events', 'update'
  ),
  'employees cannot update immutable supplier-payment correction history'
);

do $$
begin
  update public.purchase_payments
     set reference = 'DIRECT-BYPASS'
   where id = '9b240000-0000-4000-8000-000000000021';
  insert into purchase_payment_correction_failures
  values ('direct_update', false, 'direct update unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'direct_update',
      sqlerrm like '%audited purchase-payment correction command%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'direct_update'),
  'authenticated editable fields cannot bypass the audited command'
);

do $$
begin
  update public.purchase_payments
     set deleted_at = clock_timestamp(),
         deleted_by = auth.uid()
   where id = '9b240000-0000-4000-8000-000000000021';
  insert into purchase_payment_correction_failures
  values ('direct_identity', false, 'identity update unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'direct_identity',
      sqlerrm like '%identity is immutable%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'direct_identity'),
  'authenticated callers cannot mutate supplier-payment identity'
);

create temp table first_purchase_correction_result(result jsonb) on commit drop;
insert into first_purchase_correction_result(result)
select public.correct_purchase_payment(
  '9b240000-0000-4000-8000-000000000021',
  (select updated_at from purchase_main_baseline),
  'purchase-payment-correction-financial-001',
  (
    select transfer_id from purchase_correction_methods
    where tenant_id = '9b240000-0000-4000-8000-000000000001'
  ),
  6000,
  '2026-07-22 15:00:00+00'::timestamptz,
  'MAIN-REF-UPDATED',
  'Audited financial correction',
  'The supplier settlement amount and account were entered incorrectly'
);

select is(
  (select (result->>'replayed')::boolean
    from first_purchase_correction_result),
  false,
  'first supplier-payment correction commits as a new command'
);
select results_eq(
  $$
    select amount, payment_method_id, date, reference, notes
    from public.purchase_payments
    where id = '9b240000-0000-4000-8000-000000000021'
  $$,
  $$
    select 6000::numeric,
           (
             select transfer_id from purchase_correction_methods
             where tenant_id =
               '9b240000-0000-4000-8000-000000000001'
           ),
           '2026-07-22 15:00:00+00'::timestamptz,
           'MAIN-REF-UPDATED'::text,
           'Audited financial correction'::text
  $$,
  'authorized financial fields persist exactly'
);
select ok(
  exists (
    select 1
      from public.purchase_payments payment
      cross join purchase_main_baseline baseline
     where payment.id = '9b240000-0000-4000-8000-000000000021'
       and payment.invoice_id = baseline.invoice_id
       and payment.idempotency_key = baseline.idempotency_key
       and payment.created_at = baseline.created_at
       and payment.deleted_at is not distinct from baseline.deleted_at
       and payment.deleted_by is not distinct from baseline.deleted_by
  ),
  'invoice, idempotency, creation and deletion identity remain immutable'
);
select results_eq(
  $$
    select paid_amount, balance, status
    from public.purchase_invoices
    where id = '9b240000-0000-4000-8000-000000000020'
  $$,
  $$values (6000::numeric, 14000::numeric, 'received'::text)$$,
  'supplier-payment correction recalculates settlement and preserves receipt'
);
select ok(
  exists (
    select 1
      from public.purchase_payment_edit_events event
     where event.operation_key =
             'purchase-payment-correction-financial-001'
       and event.payment_id =
             '9b240000-0000-4000-8000-000000000021'
       and event.financial_fields_changed is true
       and event.legacy_journal_relinked is false
       and (event.before_snapshot->>'amount')::numeric = 5000
       and (event.after_snapshot->>'amount')::numeric = 6000
  ),
  'immutable event stores complete before/after financial evidence'
);
select ok(
  exists (
    select 1
      from public.purchase_payment_edit_events event
     where event.operation_key =
             'purchase-payment-correction-financial-001'
       and event.request_hash ~ '^[0-9a-f]{64}$'
       and event.request_snapshot->>'reason' =
         'The supplier settlement amount and account were entered incorrectly'
       and event.response_snapshot->'event'
             ->>'legacy_journal_relinked' = 'false'
  ),
  'event is a normalized full-request durable command receipt'
);
select ok(
  exists (
    select 1
      from public.purchase_payment_edit_events event
      join public.inventory_accounting_operations operation
        on operation.id = event.trace_operation_id
       and operation.tenant_id = event.tenant_id
     where event.operation_key =
             'purchase-payment-correction-financial-001'
       and operation.outcome = 'completed'
       and operation.document_type = 'purchase_payment'
       and not exists (
         select 1
           from public.stock_movements movement
          where movement.operation_id = operation.id
            and movement.tenant_id = operation.tenant_id
       )
  ),
  'correction has one completed zero-inventory payment trace'
);
select is(
  (
    select count(*)::integer
      from public.journal_entries entry
     where entry.source_module = 'purchase_payments'
       and entry.source_reference =
             '9b240000-0000-4000-8000-000000000021'
       and entry.total_debit = 6000
       and entry.total_credit = 6000
       and entry.status = 'posted'
  ),
  1,
  'financial correction leaves exactly one balanced posted UUID journal'
);
select ok(
  exists (
    select 1
      from public.journal_entries entry
      join public.journal_lines debit_line
        on debit_line.entry_id = entry.id
      join public.journal_lines credit_line
        on credit_line.entry_id = entry.id
      join public.payment_methods method
        on method.id = (
          select payment_method_id
            from public.purchase_payments
           where id = '9b240000-0000-4000-8000-000000000021'
        )
       and credit_line.account_id = method.account_id
     where entry.source_module = 'purchase_payments'
       and entry.source_reference =
             '9b240000-0000-4000-8000-000000000021'
       and debit_line.account_code = '2101'
       and debit_line.debit_amount = 6000
       and debit_line.credit_amount = 0
       and credit_line.debit_amount = 0
       and credit_line.credit_amount = 6000
  ),
  'journal debits accounts payable and credits the selected settlement account'
);
select ok(
  exists (
    select 1
      from public.purchase_payment_edit_events event
      cross join purchase_main_baseline baseline
      join public.journal_supersession_evidence evidence
        on evidence.tenant_id = event.tenant_id
       and evidence.journal_entry_id = baseline.journal_entry_id
       and evidence.operation_id = event.trace_operation_id
     where event.operation_key =
             'purchase-payment-correction-financial-001'
       and evidence.captured_reason =
             'purchase_payment_audited_correction'
       and jsonb_array_length(evidence.lines_snapshot) = 2
  ),
  'superseded posted supplier-payment journal remains immutable evidence'
);

select is(
  (
    public.correct_purchase_payment(
      '9b240000-0000-4000-8000-000000000021',
      (select updated_at from purchase_main_baseline),
      'purchase-payment-correction-financial-001',
      (
        select transfer_id from purchase_correction_methods
        where tenant_id = '9b240000-0000-4000-8000-000000000001'
      ),
      6000,
      '2026-07-22 15:00:00+00'::timestamptz,
      'MAIN-REF-UPDATED',
      'Audited financial correction',
      'The supplier settlement amount and account were entered incorrectly'
    )->>'replayed'
  )::boolean,
  true,
  'same operation key and normalized payload replay the committed response'
);
select is(
  (
    select count(*)::integer
      from public.purchase_payment_edit_events
     where operation_key = 'purchase-payment-correction-financial-001'
  ),
  1,
  'replay appends no duplicate correction event'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (select updated_at from purchase_main_baseline),
    'purchase-payment-correction-financial-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-UPDATED', 'Different replay payload',
    'The supplier settlement amount and account were entered incorrectly'
  );
  insert into purchase_payment_correction_failures
  values ('key_reuse', false, 'key reuse unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'key_reuse',
      sqlerrm like '%already used with different content%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'key_reuse'),
  'operation-key reuse with different content is rejected'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (select updated_at - interval '1 second'
       from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'),
    'purchase-payment-correction-stale-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-UPDATED', 'Audited financial correction',
    'Attempt based on a stale supplier-payment form'
  );
  insert into purchase_payment_correction_failures
  values ('stale', false, 'stale correction unexpectedly succeeded');
exception
  when serialization_failure then
    insert into purchase_payment_correction_failures
    values ('stale', true, sqlerrm);
  when others then
    insert into purchase_payment_correction_failures
    values ('stale', false, sqlerrm);
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'stale'),
  'optimistic updated_at rejects a stale supplier-payment form'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-reason-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-UPDATED', 'Audited financial correction', ' '
  );
  insert into purchase_payment_correction_failures
  values ('reason', false, 'reasonless correction unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'reason', sqlerrm like '%correction reason%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'reason'),
  'every supplier-payment correction requires an explicit reason'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-fraction-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000.5, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-UPDATED', 'Audited financial correction',
    'Attempt a fractional CLP correction'
  );
  insert into purchase_payment_correction_failures
  values ('fraction', false, 'fractional correction unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'fraction', sqlerrm like '%positive whole CLP%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'fraction'),
  'supplier-payment corrections reject fractional CLP'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-overpay-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    20001, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-UPDATED', 'Audited financial correction',
    'Attempt to exceed the purchase invoice'
  );
  insert into purchase_payment_correction_failures
  values ('overpay', false, 'overpayment unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'overpay', sqlerrm like '%gross remaining balance%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'overpay'),
  'supplier-payment correction rejects one peso beyond gross balance'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-reference-required-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    null, 'Audited financial correction',
    'Attempt to clear a required transfer reference'
  );
  insert into purchase_payment_correction_failures
  values (
    'reference_required',
    false,
    'required reference correction unexpectedly succeeded'
  );
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'reference_required',
      sqlerrm like '%requires a reference%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'reference_required'),
  'payment-method reference requirements are enforced by the command'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9b240000-0000-4000-8000-000000000098","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b240000-0000-4000-8000-000000000098',
  true
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-cashier-financial-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    7000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-UPDATED', 'Audited financial correction',
    'Cashier attempt to alter a supplier settlement'
  );
  insert into purchase_payment_correction_failures
  values (
    'cashier_financial',
    false,
    'cashier financial correction unexpectedly succeeded'
  );
exception
  when insufficient_privilege then
    insert into purchase_payment_correction_failures
    values ('cashier_financial', true, sqlerrm);
  when others then
    insert into purchase_payment_correction_failures
    values ('cashier_financial', false, sqlerrm);
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'cashier_financial'),
  'cashier purchase access does not imply financial correction authority'
);

create temp table cashier_metadata_journal_before on commit drop as
select id
  from public.journal_entries
 where source_module = 'purchase_payments'
   and source_reference = '9b240000-0000-4000-8000-000000000021';

select is(
  public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-cashier-reference-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-CASHIER', 'Audited financial correction',
    'Correct a manually entered supplier bank reference'
  )->'payment'->>'reference',
  'MAIN-REF-CASHIER',
  'cashier may correct supplier-payment reference metadata with a reason'
);
select is(
  (
    select id from public.journal_entries
    where source_module = 'purchase_payments'
      and source_reference = '9b240000-0000-4000-8000-000000000021'
  ),
  (select id from cashier_metadata_journal_before),
  'canonical metadata correction preserves the current journal identity'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9b240000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b240000-0000-4000-8000-000000000099',
  true
);

update public.payment_methods method
   set is_active = false
 where method.id = (
   select transfer_id from purchase_correction_methods
   where tenant_id = '9b240000-0000-4000-8000-000000000001'
 );

select is(
  public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-inactive-preserve-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-CASHIER', 'Historical inactive method retained',
    'Annotate the payment without changing its historical method'
  )->'payment'->>'notes',
  'Historical inactive method retained',
  'metadata correction preserves the same inactive historical method'
);
select is(
  (
    select id from public.journal_entries
    where source_module = 'purchase_payments'
      and source_reference = '9b240000-0000-4000-8000-000000000021'
  ),
  (select id from cashier_metadata_journal_before),
  'inactive-method metadata correction also avoids journal churn'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000031',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000031'
    ),
    'purchase-payment-correction-inactive-switch-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    4000, '2026-07-20 16:00:00+00'::timestamptz,
    'TRANSFER-REF', 'Original legacy note',
    'Attempt to select an inactive settlement method'
  );
  insert into purchase_payment_correction_failures
  values (
    'inactive_switch',
    false,
    'inactive method switch unexpectedly succeeded'
  );
exception
  when insufficient_privilege then
    insert into purchase_payment_correction_failures
    values ('inactive_switch', true, sqlerrm);
  when others then
    insert into purchase_payment_correction_failures
    values ('inactive_switch', false, sqlerrm);
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'inactive_switch'),
  'a correction cannot switch to a different inactive payment method'
);

update public.payment_methods method
   set is_active = true
 where method.id = (
   select transfer_id from purchase_correction_methods
   where tenant_id = '9b240000-0000-4000-8000-000000000001'
 );

create temp table legacy_purchase_correction_result(result jsonb)
on commit drop;
insert into legacy_purchase_correction_result(result)
select public.correct_purchase_payment(
  '9b240000-0000-4000-8000-000000000031',
  (
    select updated_at from public.purchase_payments
    where id = '9b240000-0000-4000-8000-000000000031'
  ),
  'purchase-payment-correction-legacy-001',
  (
    select cash_id from purchase_correction_methods
    where tenant_id = '9b240000-0000-4000-8000-000000000001'
  ),
  4000, '2026-07-20 16:00:00+00'::timestamptz,
  'LEGACY-REF-UPDATED', 'Original legacy note',
  'Correct a legacy payment reference and canonicalize its journal identity'
);
select is(
  (
    select (result->>'legacy_journal_relinked')::boolean
    from legacy_purchase_correction_result
  ),
  true,
  'unique legacy correction explicitly reports its one-time relink'
);
select ok(
  exists (
    select 1
      from public.purchase_payment_edit_events event
      join public.journal_supersession_evidence evidence
        on evidence.journal_entry_id = event.prior_journal_entry_id
       and evidence.operation_id = event.trace_operation_id
       and evidence.tenant_id = event.tenant_id
     where event.operation_key = 'purchase-payment-correction-legacy-001'
       and event.legacy_journal_relinked is true
       and evidence.source_reference = 'FC-PAY-CORR-LEGACY'
       and evidence.captured_reason =
             'purchase_payment_audited_correction'
       and exists (
         select 1 from public.journal_entries current_entry
          where current_entry.id = event.current_journal_entry_id
            and current_entry.source_reference = event.payment_id::text
       )
       and not exists (
         select 1 from public.journal_entries legacy_entry
          where legacy_entry.tenant_id = event.tenant_id
            and legacy_entry.source_module = 'purchase_payments'
            and legacy_entry.source_reference = 'FC-PAY-CORR-LEGACY'
       )
  ),
  'unique legacy journal is snapshotted and replaced by the UUID journal'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000041',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000041'
    ),
    'purchase-payment-correction-ambiguous-001',
    (
      select cash_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    4000, '2026-07-20 17:00:00+00'::timestamptz,
    'AMBIG-REF-UPDATED', 'Original ambiguous note',
    'Attempt to edit an ambiguous historical journal'
  );
  insert into purchase_payment_correction_failures
  values (
    'ambiguous',
    false,
    'ambiguous legacy correction unexpectedly succeeded'
  );
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'ambiguous',
      sqlerrm like '%ambiguous%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'ambiguous')
  and not exists (
    select 1 from public.purchase_payment_edit_events
    where operation_key = 'purchase-payment-correction-ambiguous-001'
  ),
  'ambiguous legacy journals fail atomically without an event'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000061',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000061'
    ),
    'purchase-payment-correction-mixed-001',
    (
      select cash_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    4000, '2026-07-20 19:00:00+00'::timestamptz,
    'MIXED-REF-UPDATED', 'Original mixed note',
    'Attempt to edit mixed journal identities'
  );
  insert into purchase_payment_correction_failures
  values ('mixed', false, 'mixed correction unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'mixed',
      sqlerrm like '%mixed or duplicate%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'mixed')
  and not exists (
    select 1 from public.purchase_payment_edit_events
    where operation_key = 'purchase-payment-correction-mixed-001'
  ),
  'mixed UUID and invoice-number journals fail without mutation'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000051',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000051'
    ),
    'purchase-payment-correction-missing-001',
    (
      select cash_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    4000, '2026-07-20 18:00:00+00'::timestamptz,
    'MISSING-REF-UPDATED', 'Original missing note',
    'Attempt to infer a missing historical journal'
  );
  insert into purchase_payment_correction_failures
  values ('missing', false, 'missing journal correction unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'missing',
      sqlerrm like '%no recognized settlement journal%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'missing')
  and not exists (
    select 1 from public.purchase_payment_edit_events
    where operation_key = 'purchase-payment-correction-missing-001'
  ),
  'missing settlement journal remains explicit review-only evidence'
);

create temp table credited_purchase_correction_result(result jsonb)
on commit drop;
insert into credited_purchase_correction_result(result)
select public.correct_purchase_payment(
  '9b240000-0000-4000-8000-000000000071',
  (
    select updated_at from public.purchase_payments
    where id = '9b240000-0000-4000-8000-000000000071'
  ),
  'purchase-payment-correction-credited-001',
  (
    select cash_id from purchase_correction_methods
    where tenant_id = '9b240000-0000-4000-8000-000000000001'
  ),
  9000, '2026-07-20 20:00:00+00'::timestamptz,
  'CREDIT-REF-UPDATED', 'Corrected credited payment',
  'Correct gross supplier payment while retaining credit and refund evidence'
);
select is(
  (
    select (result->>'financial_fields_changed')::boolean
    from credited_purchase_correction_result
  ),
  true,
  'credited-invoice supplier payment accepts an authorized financial correction'
);
select results_eq(
  $$
    select paid_amount, credited_amount, supplier_refunded_amount,
           balance, supplier_credit_balance, status
    from public.purchase_invoices
    where id = '9b240000-0000-4000-8000-000000000070'
  $$,
  $$
    values (
      9000::numeric, 3000::numeric, 1000::numeric,
      0::numeric, 1000::numeric, 'received'::text
    )
  $$,
  'credit/refund-aware settlement mirrors reconcile after correction'
);
select ok(
  exists (
    select 1
      from public.purchase_payment_edit_events event
      join public.inventory_accounting_operations operation
        on operation.id = event.trace_operation_id
       and operation.tenant_id = event.tenant_id
      join public.inventory_accounting_checkpoints checkpoint
        on checkpoint.operation_id = operation.id
       and checkpoint.tenant_id = operation.tenant_id
       and checkpoint.phase = 'completed'
       and checkpoint.outcome = 'completed'
     where event.operation_key = 'purchase-payment-correction-credited-001'
       and operation.outcome = 'completed'
       and (checkpoint.payload->>'ledger_credited')::numeric = 3000
       and (checkpoint.payload->>'ledger_refunded')::numeric = 1000
       and (checkpoint.payload->>'invoice_credit_balance')::numeric = 1000
       and not exists (
         select 1 from public.stock_movements movement
          where movement.operation_id = operation.id
       )
  ),
  'credited correction trace completes with exact settlement and zero stock'
);

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-no-change-001',
    (
      select transfer_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000001'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MAIN-REF-CASHIER', 'Historical inactive method retained',
    'No actual supplier-payment field change'
  );
  insert into purchase_payment_correction_failures
  values ('no_change', false, 'no-op correction unexpectedly succeeded');
exception
  when others then
    insert into purchase_payment_correction_failures values (
      'no_change',
      sqlerrm like '%contains no changes%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'no_change'),
  'no-op commands create no supplier-payment audit noise'
);

select is(
  public.get_purchase_payment_edit_operation(
    'purchase-payment-correction-financial-001'
  )->'event'->>'id',
  (
    select id::text from public.purchase_payment_edit_events
    where operation_key = 'purchase-payment-correction-financial-001'
  ),
  'readback returns the exact committed event after a lost acknowledgement'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9b240000-0000-4000-8000-000000000199","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b240000-0000-4000-8000-000000000199',
  true
);

select is(
  public.get_purchase_payment_edit_operation(
    'purchase-payment-correction-financial-001'
  ),
  null::jsonb,
  'another tenant cannot read back the operation key'
);

set local role authenticated;
select is(
  (select count(*) from public.purchase_payment_edit_events),
  0::bigint,
  'event RLS hides another tenant correction history'
);
reset role;

do $$
begin
  perform public.correct_purchase_payment(
    '9b240000-0000-4000-8000-000000000021',
    (
      select updated_at from public.purchase_payments
      where id = '9b240000-0000-4000-8000-000000000021'
    ),
    'purchase-payment-correction-cross-tenant-001',
    (
      select cash_id from purchase_correction_methods
      where tenant_id = '9b240000-0000-4000-8000-000000000101'
    ),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'CROSS-TENANT', 'Cross tenant attempt',
    'Attempt from another supplier-payment tenant'
  );
  insert into purchase_payment_correction_failures
  values ('cross_tenant', false, 'cross-tenant correction succeeded');
exception
  when insufficient_privilege then
    insert into purchase_payment_correction_failures
    values ('cross_tenant', true, sqlerrm);
  when others then
    insert into purchase_payment_correction_failures
    values ('cross_tenant', false, sqlerrm);
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'cross_tenant'),
  'correction command cannot resolve another tenant supplier payment'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9b240000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9b240000-0000-4000-8000-000000000099',
  true
);

do $$
begin
  update public.purchase_payment_edit_events
     set reason = 'Attempted evidence mutation'
   where operation_key = 'purchase-payment-correction-financial-001';
  insert into purchase_payment_correction_failures
  values ('immutable_event', false, 'event update unexpectedly succeeded');
exception
  when object_not_in_prerequisite_state then
    insert into purchase_payment_correction_failures
    values ('immutable_event', true, sqlerrm);
  when others then
    insert into purchase_payment_correction_failures
    values ('immutable_event', false, sqlerrm);
end;
$$;
select ok(
  (select passed from purchase_payment_correction_failures
    where name = 'immutable_event'),
  'database trigger rejects correction evidence mutation'
);

select ok(
  not exists (
    select 1
      from public.purchase_payment_edit_events event
      join public.inventory_accounting_operations operation
        on operation.id = event.trace_operation_id
       and operation.tenant_id = event.tenant_id
     where operation.outcome <> 'completed'
        or exists (
          select 1
            from public.stock_movements movement
           where movement.operation_id = event.trace_operation_id
             and movement.tenant_id = event.tenant_id
        )
  ),
  'all successful supplier-payment correction receipts retain completed zero-stock traces'
);

select * from finish();

rollback;
