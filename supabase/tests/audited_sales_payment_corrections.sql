begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(40);

create temp table payment_correction_failures (
  name text primary key,
  passed boolean not null,
  message text
) on commit drop;

insert into public.tenants(id, shop_name) values
  ('9a230000-0000-4000-8000-000000000001', 'Payment Correction Tenant A'),
  ('9a230000-0000-4000-8000-000000000101', 'Payment Correction Tenant B');

-- Tenant bootstrap helpers may set a transaction-local subject to the tenant
-- UUID. Fixture accounting writes deliberately run without an employee JWT.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table correction_methods on commit drop as
select
  tenant_id,
  (array_agg(id order by id) filter (where code = 'cash'))[1] as cash_id,
  (array_agg(id order by id) filter (where code = 'transfer'))[1]
    as transfer_id,
  (array_agg(id order by id) filter (where code = 'mercadopago'))[1]
    as mercadopago_id
from public.payment_methods
where tenant_id in (
  '9a230000-0000-4000-8000-000000000001',
  '9a230000-0000-4000-8000-000000000101'
)
group by tenant_id;

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment
) values
  (
    '9a230000-0000-4000-8000-000000000020',
    '9a230000-0000-4000-8000-000000000001',
    'FV-PAY-CORR-MANUAL', 'Manual Correction Customer', 'confirmed',
    'manual_sale', 20000, 20000, 0, 20000, 0, 20000, 'no_tax'
  ),
  (
    '9a230000-0000-4000-8000-000000000030',
    '9a230000-0000-4000-8000-000000000001',
    'FV-PAY-CORR-WEB', 'Online Correction Customer', 'confirmed',
    'ecommerce', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
  ),
  (
    '9a230000-0000-4000-8000-000000000040',
    '9a230000-0000-4000-8000-000000000001',
    'FV-PAY-CORR-PROVIDER', 'Provider Correction Customer', 'confirmed',
    'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
  );

insert into public.sales_payments (
  id, tenant_id, invoice_id, invoice_reference, payment_method_id,
  idempotency_key, amount, date, reference, notes
)
select
  '9a230000-0000-4000-8000-000000000021',
  '9a230000-0000-4000-8000-000000000001',
  '9a230000-0000-4000-8000-000000000020',
  'FV-PAY-CORR-MANUAL', method.cash_id,
  'manual-correction-original', 5000,
  '2026-07-20 15:00:00+00'::timestamptz,
  'MANUAL-REF-1', 'Original manual note'
from correction_methods method
where method.tenant_id = '9a230000-0000-4000-8000-000000000001';

insert into public.sales_payments (
  id, tenant_id, invoice_id, invoice_reference, payment_method_id,
  idempotency_key, amount, date, reference, notes
)
select
  '9a230000-0000-4000-8000-000000000031',
  '9a230000-0000-4000-8000-000000000001',
  '9a230000-0000-4000-8000-000000000030',
  'FV-PAY-CORR-WEB', method.mercadopago_id,
  'online_order:test-payment', 10000,
  '2026-07-20 16:00:00+00'::timestamptz,
  'WEB-REF-1', 'Original online note'
from correction_methods method
where method.tenant_id = '9a230000-0000-4000-8000-000000000001';

insert into public.sales_payments (
  id, tenant_id, invoice_id, invoice_reference, payment_method_id,
  idempotency_key, amount, date, reference, notes
)
select
  '9a230000-0000-4000-8000-000000000041',
  '9a230000-0000-4000-8000-000000000001',
  '9a230000-0000-4000-8000-000000000040',
  'FV-PAY-CORR-PROVIDER', method.mercadopago_id,
  'mercadopago:provider-payment-001', 10000,
  '2026-07-20 17:00:00+00'::timestamptz,
  'PROVIDER-REF-1', 'Original provider note'
from correction_methods method
where method.tenant_id = '9a230000-0000-4000-8000-000000000001';

create temp table manual_payment_baseline on commit drop as
select
  payment.updated_at,
  payment.invoice_id,
  payment.invoice_reference,
  payment.idempotency_key,
  payment.created_at,
  payment.tax_treatment,
  payment.deleted_at,
  payment.deleted_by,
  entry.id as journal_entry_id
from public.sales_payments payment
join public.journal_entries entry
  on entry.tenant_id = payment.tenant_id
 and entry.source_module = 'sales_payments'
 and entry.source_reference = payment.id::text
where payment.id = '9a230000-0000-4000-8000-000000000021';

create temp table managed_payment_baseline on commit drop as
select payment.updated_at, payment.date, payment.payment_method_id,
       entry.id as journal_entry_id
from public.sales_payments payment
join public.journal_entries entry
  on entry.tenant_id = payment.tenant_id
 and entry.source_module = 'sales_payments'
 and entry.source_reference = payment.id::text
where payment.id = '9a230000-0000-4000-8000-000000000031';

update public.payment_methods method
   set is_active = false
 where method.id = (
   select payment_method_id from managed_payment_baseline
 );

insert into auth.users (
  id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9a230000-0000-4000-8000-000000000099',
    'authenticated', 'authenticated', 'pay-correction-admin-a@example.invalid',
    '', '{}'::jsonb,
    '{"account_type":"public_store_customer","customer_tenant_id":"9a230000-0000-4000-8000-000000000001"}'::jsonb,
    now(), now()
  ),
  (
    '9a230000-0000-4000-8000-000000000098',
    'authenticated', 'authenticated', 'pay-correction-cashier-a@example.invalid',
    '', '{}'::jsonb,
    '{"account_type":"public_store_customer","customer_tenant_id":"9a230000-0000-4000-8000-000000000001"}'::jsonb,
    now(), now()
  ),
  (
    '9a230000-0000-4000-8000-000000000199',
    'authenticated', 'authenticated', 'pay-correction-admin-b@example.invalid',
    '', '{}'::jsonb,
    '{"account_type":"public_store_customer","customer_tenant_id":"9a230000-0000-4000-8000-000000000101"}'::jsonb,
    now(), now()
  );

insert into public.user_profiles(user_id, tenant_id, role) values
  (
    '9a230000-0000-4000-8000-000000000099',
    '9a230000-0000-4000-8000-000000000001', 'admin'
  ),
  (
    '9a230000-0000-4000-8000-000000000098',
    '9a230000-0000-4000-8000-000000000001', 'cashier'
  ),
  (
    '9a230000-0000-4000-8000-000000000199',
    '9a230000-0000-4000-8000-000000000101', 'admin'
  );

select set_config(
  'request.jwt.claims',
  '{"sub":"9a230000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a230000-0000-4000-8000-000000000099',
  true
);

select ok(
  not has_function_privilege(
    'anon',
    'public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'anonymous callers cannot run payment corrections'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'authenticated employees can run the correction command'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'service role cannot bypass the employee correction command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_sales_payment_edit_operation(text)',
    'execute'
  ),
  'authenticated employees can read back a committed correction receipt'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.sales_payment_edit_events', 'select'
  ),
  'employees can read tenant-scoped correction history'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.sales_payment_edit_events', 'update'
  ),
  'employees cannot update immutable correction history'
);

do $$
begin
  update public.sales_payments
     set reference = 'DIRECT-BYPASS'
   where id = '9a230000-0000-4000-8000-000000000021';
  insert into payment_correction_failures
  values ('direct_update', false, 'direct update unexpectedly succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'direct_update',
      sqlerrm like '%audited sales-payment correction command%',
      sqlerrm
    );
end;
$$;

select ok(
  (select passed from payment_correction_failures
    where name = 'direct_update'),
  'authenticated editable fields cannot bypass the audited command'
);

do $$
begin
  update public.sales_payments
     set deleted_at = clock_timestamp(),
         deleted_by = auth.uid()
   where id = '9a230000-0000-4000-8000-000000000021';
  insert into payment_correction_failures
  values (
    'direct_soft_delete',
    false,
    'direct soft-delete unexpectedly succeeded'
  );
exception
  when others then
    insert into payment_correction_failures values (
      'direct_soft_delete',
      sqlerrm like '%identity and server-owned tax fields are immutable%',
      sqlerrm
    );
end;
$$;

select ok(
  (select passed from payment_correction_failures
    where name = 'direct_soft_delete'),
  'authenticated callers cannot soft-delete or stamp deleted_by directly'
);

create temp table first_correction_result(result jsonb) on commit drop;
insert into first_correction_result(result)
select public.correct_sales_payment(
  '9a230000-0000-4000-8000-000000000021',
  (select updated_at from manual_payment_baseline),
  'payment-correction-financial-001',
  (select transfer_id from correction_methods
    where tenant_id = '9a230000-0000-4000-8000-000000000001'),
  6000,
  '2026-07-22 15:00:00+00'::timestamptz,
  'MANUAL-REF-UPDATED',
  'Audited financial correction',
  'The original amount and settlement account were entered incorrectly'
);

select is(
  (select (result->>'replayed')::boolean from first_correction_result),
  false,
  'first correction is committed as a new command'
);
select results_eq(
  $$
    select amount, payment_method_id, date, reference, notes
    from public.sales_payments
    where id = '9a230000-0000-4000-8000-000000000021'
  $$,
  $$
    select 6000::numeric,
           (select transfer_id from correction_methods
             where tenant_id = '9a230000-0000-4000-8000-000000000001'),
           '2026-07-22 15:00:00+00'::timestamptz,
           'MANUAL-REF-UPDATED'::text,
           'Audited financial correction'::text
  $$,
  'manual payment persists the authorized corrected fields'
);
select ok(
  exists (
    select 1
    from public.sales_payments payment
    cross join manual_payment_baseline baseline
    where payment.id = '9a230000-0000-4000-8000-000000000021'
      and payment.invoice_id = baseline.invoice_id
      and payment.invoice_reference = baseline.invoice_reference
      and payment.idempotency_key = baseline.idempotency_key
      and payment.created_at = baseline.created_at
      and payment.tax_treatment = baseline.tax_treatment
      and payment.deleted_at is not distinct from baseline.deleted_at
      and payment.deleted_by is not distinct from baseline.deleted_by
  ),
  'invoice, idempotency, tax, creation, and deletion identity stay immutable'
);
select results_eq(
  $$
    select paid_amount, balance, status
    from public.sales_invoices
    where id = '9a230000-0000-4000-8000-000000000020'
  $$,
  $$values (6000::numeric, 14000::numeric, 'confirmed'::text)$$,
  'invoice settlement projection is recalculated from the corrected payment'
);
select ok(
  exists (
    select 1
    from public.sales_payment_edit_events event
    where event.operation_key = 'payment-correction-financial-001'
      and event.payment_id = '9a230000-0000-4000-8000-000000000021'
      and event.invoice_id = '9a230000-0000-4000-8000-000000000020'
      and event.source = 'manual_sale'
      and event.source_managed is false
      and event.financial_fields_changed is true
      and (event.before_snapshot->>'amount')::numeric = 5000
      and (event.after_snapshot->>'amount')::numeric = 6000
  ),
  'immutable event stores source classification plus full before and after evidence'
);
select ok(
  exists (
    select 1
    from public.sales_payment_edit_events event
    where event.operation_key = 'payment-correction-financial-001'
      and event.request_hash ~ '^[0-9a-f]{64}$'
      and event.request_snapshot->>'reason'
            = 'The original amount and settlement account were entered incorrectly'
      and event.response_snapshot->'payment'->>'id'
            = '9a230000-0000-4000-8000-000000000021'
  ),
  'event is also a full-request durable command receipt'
);
select ok(
  exists (
    select 1
    from public.sales_payment_edit_events event
    join public.inventory_accounting_operations operation
      on operation.id = event.trace_operation_id
     and operation.tenant_id = event.tenant_id
    where event.operation_key = 'payment-correction-financial-001'
      and operation.outcome = 'completed'
      and operation.document_type = 'sales_payment'
      and not exists (
        select 1 from public.stock_movements movement
        where movement.operation_id = operation.id
          and movement.tenant_id = operation.tenant_id
      )
  ),
  'correction has a completed payment trace with zero inventory movements'
);
select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.source_module = 'sales_payments'
      and entry.source_reference = '9a230000-0000-4000-8000-000000000021'
      and entry.total_debit = 6000
      and entry.total_credit = 6000
      and entry.status = 'posted'
  ),
  1,
  'financial correction leaves exactly one balanced posted journal'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines debit_line on debit_line.entry_id = entry.id
    join public.payment_methods method
      on method.id = (
        select payment_method_id from public.sales_payments
        where id = '9a230000-0000-4000-8000-000000000021'
      )
     and debit_line.account_id = method.account_id
    join public.journal_lines credit_line on credit_line.entry_id = entry.id
    where entry.source_module = 'sales_payments'
      and entry.source_reference = '9a230000-0000-4000-8000-000000000021'
      and debit_line.debit_amount = 6000
      and debit_line.credit_amount = 0
      and credit_line.account_code = '1130'
      and credit_line.debit_amount = 0
      and credit_line.credit_amount = 6000
  ),
  'journal debits the selected settlement account and credits receivables'
);
select ok(
  exists (
    select 1
    from public.sales_payment_edit_events event
    join manual_payment_baseline baseline on true
    join public.journal_supersession_evidence evidence
      on evidence.tenant_id = event.tenant_id
     and evidence.journal_entry_id = baseline.journal_entry_id
     and evidence.operation_id = event.trace_operation_id
    where event.operation_key = 'payment-correction-financial-001'
      and evidence.captured_reason = 'sales_payment_audited_correction'
      and evidence.header_snapshot->>'id' = baseline.journal_entry_id::text
      and jsonb_array_length(evidence.lines_snapshot) = 2
  ),
  'superseded posted journal header and lines remain immutable evidence'
);

select is(
  (
    public.correct_sales_payment(
      '9a230000-0000-4000-8000-000000000021',
      (select updated_at from manual_payment_baseline),
      'payment-correction-financial-001',
      (select transfer_id from correction_methods
        where tenant_id = '9a230000-0000-4000-8000-000000000001'),
      6000,
      '2026-07-22 15:00:00+00'::timestamptz,
      'MANUAL-REF-UPDATED',
      'Audited financial correction',
      'The original amount and settlement account were entered incorrectly'
    )->>'replayed'
  )::boolean,
  true,
  'same operation key and full payload replay the committed response'
);
select is(
  (
    select count(*)::integer
    from public.sales_payment_edit_events
    where operation_key = 'payment-correction-financial-001'
  ),
  1,
  'replay does not append a duplicate event'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at from manual_payment_baseline),
    'payment-correction-financial-001',
    (select transfer_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MANUAL-REF-UPDATED', 'Different replay payload',
    'The original amount and settlement account were entered incorrectly'
  );
  insert into payment_correction_failures
  values ('key_reuse', false, 'key reuse unexpectedly succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'key_reuse',
      sqlerrm like '%already used with different content%',
      sqlerrm
    );
end;
$$;
select ok(
  (select passed from payment_correction_failures where name = 'key_reuse'),
  'operation key reuse with a different request is rejected'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at - interval '1 second' from manual_payment_baseline),
    'payment-correction-stale-001',
    (select transfer_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'STALE-REF', 'Audited financial correction',
    'Attempt based on a stale form'
  );
  insert into payment_correction_failures
  values ('stale', false, 'stale update unexpectedly succeeded');
exception
  when serialization_failure then
    insert into payment_correction_failures values ('stale', true, sqlerrm);
  when others then
    insert into payment_correction_failures values ('stale', false, sqlerrm);
end;
$$;
select ok(
  (select passed from payment_correction_failures where name = 'stale'),
  'optimistic updated_at rejects a stale form'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000021'),
    'payment-correction-no-reason-001',
    (select transfer_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'NO-REASON-REF', 'Audited financial correction', '  '
  );
  insert into payment_correction_failures
  values ('reason', false, 'reasonless correction unexpectedly succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'reason', sqlerrm like '%correction reason%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from payment_correction_failures where name = 'reason'),
  'every correction requires an explicit reason'
);

create temp table managed_correction_result(result jsonb) on commit drop;
insert into managed_correction_result(result)
select public.correct_sales_payment(
  '9a230000-0000-4000-8000-000000000031',
  (select updated_at from managed_payment_baseline),
  'payment-correction-managed-note-001',
  (select payment_method_id from managed_payment_baseline),
  10000,
  (select date from managed_payment_baseline),
  'WEB-REF-1',
  'Customer service annotation only',
  'Add a non-financial internal service annotation'
);
select is(
  (select result->'payment'->>'notes' from managed_correction_result),
  'Customer service annotation only',
  'source-managed payment accepts a notes-only correction'
);
select ok(
  exists (
    select 1
    from public.sales_payments payment
    join public.payment_methods method
      on method.id = payment.payment_method_id
     and method.tenant_id = payment.tenant_id
    cross join managed_payment_baseline baseline
    where payment.id = '9a230000-0000-4000-8000-000000000031'
      and payment.payment_method_id = baseline.payment_method_id
      and method.is_active is false
  ),
  'notes-only correction preserves an inactive historical payment method'
);
select ok(
  exists (
    select 1
    from public.sales_payment_edit_events event
    where event.operation_key = 'payment-correction-managed-note-001'
      and event.source = 'ecommerce'
      and event.source_managed is true
      and event.financial_fields_changed is false
  ),
  'managed notes event records its protected source classification'
);
select is(
  (
    select entry.id
    from public.journal_entries entry
    where entry.source_module = 'sales_payments'
      and entry.source_reference = '9a230000-0000-4000-8000-000000000031'
  ),
  (select journal_entry_id from managed_payment_baseline),
  'notes-only correction does not churn the payment journal'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000031',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000031'),
    'payment-correction-managed-financial-001',
    (select payment_method_id from managed_payment_baseline),
    9999, (select date from managed_payment_baseline),
    'WEB-REF-1', 'Customer service annotation only',
    'Attempt to alter a source-owned settlement'
  );
  insert into payment_correction_failures
  values ('managed_financial', false, 'managed financial update succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'managed_financial', sqlerrm like '%notes-only%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from payment_correction_failures
    where name = 'managed_financial'),
  'source-managed amount, date, and method require the source workflow'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000031',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000031'),
    'payment-correction-managed-reference-001',
    (select payment_method_id from managed_payment_baseline),
    10000, (select date from managed_payment_baseline),
    'WEB-REF-CHANGED', 'Customer service annotation only',
    'Attempt to alter source-owned provider evidence'
  );
  insert into payment_correction_failures
  values ('managed_reference', false, 'managed reference update succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'managed_reference', sqlerrm like '%notes-only%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from payment_correction_failures
    where name = 'managed_reference'),
  'source-managed provider reference is immutable in the payment form'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000041',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000041'),
    'payment-correction-provider-financial-001',
    (select mercadopago_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    9999, '2026-07-20 17:00:00+00'::timestamptz,
    'PROVIDER-REF-1', 'Original provider note',
    'Attempt to alter provider-owned evidence'
  );
  insert into payment_correction_failures
  values ('provider_financial', false, 'provider financial update succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'provider_financial', sqlerrm like '%notes-only%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from payment_correction_failures
    where name = 'provider_financial'),
  'provider idempotency identity is notes-only even on a legacy manual source'
);

select is(
  public.get_sales_payment_edit_operation(
    'payment-correction-financial-001'
  )->'event'->>'id',
  (select id::text from public.sales_payment_edit_events
    where operation_key = 'payment-correction-financial-001'),
  'readback returns the exact committed event after a lost acknowledgement'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9a230000-0000-4000-8000-000000000199","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a230000-0000-4000-8000-000000000199',
  true
);

select is(
  public.get_sales_payment_edit_operation(
    'payment-correction-financial-001'
  ),
  null::jsonb,
  'another tenant cannot read back the operation key'
);

set local role authenticated;
select is(
  (select count(*) from public.sales_payment_edit_events),
  0::bigint,
  'event RLS hides another tenant correction history'
);
reset role;

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000021'),
    'payment-correction-cross-tenant-001',
    (select cash_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000101'),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'CROSS-TENANT', 'Cross tenant attempt',
    'Attempt from another tenant'
  );
  insert into payment_correction_failures
  values ('cross_tenant', false, 'cross-tenant correction succeeded');
exception
  when insufficient_privilege then
    insert into payment_correction_failures
    values ('cross_tenant', true, sqlerrm);
  when others then
    insert into payment_correction_failures
    values ('cross_tenant', false, sqlerrm);
end;
$$;
select ok(
  (select passed from payment_correction_failures
    where name = 'cross_tenant'),
  'correction command cannot resolve another tenant payment'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9a230000-0000-4000-8000-000000000098","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a230000-0000-4000-8000-000000000098',
  true
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000021'),
    'payment-correction-cashier-financial-001',
    (select transfer_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    7000, '2026-07-22 15:00:00+00'::timestamptz,
    'MANUAL-REF-UPDATED', 'Audited financial correction',
    'Cashier financial change attempt'
  );
  insert into payment_correction_failures
  values ('cashier_financial', false, 'cashier financial correction succeeded');
exception
  when insufficient_privilege then
    insert into payment_correction_failures
    values ('cashier_financial', true, sqlerrm);
  when others then
    insert into payment_correction_failures
    values ('cashier_financial', false, sqlerrm);
end;
$$;
select ok(
  (select passed from payment_correction_failures
    where name = 'cashier_financial'),
  'cashier payment access does not imply financial correction authority'
);

create temp table manual_metadata_journal_before on commit drop as
select id from public.journal_entries
where source_module = 'sales_payments'
  and source_reference = '9a230000-0000-4000-8000-000000000021';

select is(
  public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000021'),
    'payment-correction-cashier-reference-001',
    (select transfer_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MANUAL-REF-CASHIER', 'Audited financial correction',
    'Correct a manually entered bank reference'
  )->'payment'->>'reference',
  'MANUAL-REF-CASHIER',
  'cashier may correct manual reference metadata with a reason'
);
select is(
  (
    select id from public.journal_entries
    where source_module = 'sales_payments'
      and source_reference = '9a230000-0000-4000-8000-000000000021'
  ),
  (select id from manual_metadata_journal_before),
  'manual reference correction preserves the current journal identity'
);

do $$
begin
  perform public.correct_sales_payment(
    '9a230000-0000-4000-8000-000000000021',
    (select updated_at from public.sales_payments
      where id = '9a230000-0000-4000-8000-000000000021'),
    'payment-correction-no-change-001',
    (select transfer_id from correction_methods
      where tenant_id = '9a230000-0000-4000-8000-000000000001'),
    6000, '2026-07-22 15:00:00+00'::timestamptz,
    'MANUAL-REF-CASHIER', 'Audited financial correction',
    'No actual payment field change'
  );
  insert into payment_correction_failures
  values ('no_change', false, 'no-op correction succeeded');
exception
  when others then
    insert into payment_correction_failures values (
      'no_change', sqlerrm like '%contains no changes%', sqlerrm
    );
end;
$$;
select ok(
  (select passed from payment_correction_failures where name = 'no_change'),
  'no-op commands do not create audit noise'
);

do $$
begin
  update public.sales_payment_edit_events
     set reason = 'Attempted evidence mutation'
   where operation_key = 'payment-correction-financial-001';
  insert into payment_correction_failures
  values ('immutable_event', false, 'event update unexpectedly succeeded');
exception
  when object_not_in_prerequisite_state then
    insert into payment_correction_failures
    values ('immutable_event', true, sqlerrm);
  when others then
    insert into payment_correction_failures
    values ('immutable_event', false, sqlerrm);
end;
$$;
select ok(
  (select passed from payment_correction_failures
    where name = 'immutable_event'),
  'database trigger rejects correction evidence mutation even by an owner role'
);

select ok(
  not exists (
    select 1
    from public.sales_payment_edit_events event
    join public.inventory_accounting_operations operation
      on operation.id = event.trace_operation_id
     and operation.tenant_id = event.tenant_id
    where operation.outcome <> 'completed'
       or exists (
         select 1 from public.stock_movements movement
         where movement.operation_id = event.trace_operation_id
           and movement.tenant_id = event.tenant_id
       )
  ),
  'all successful correction receipts retain completed zero-stock traces'
);

select * from finish();

rollback;
