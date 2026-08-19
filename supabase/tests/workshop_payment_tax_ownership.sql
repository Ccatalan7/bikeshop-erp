begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(96);

insert into public.tenants(id, shop_name) values (
  '99942000-0000-4000-8000-000000000001',
  'Workshop Payment Ownership Tenant'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99942000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'workshop-payment@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99942000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99942000-0000-4000-8000-000000000099',
  '99942000-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values (
  '99942000-0000-4000-8000-000000000010',
  '99942000-0000-4000-8000-000000000001',
  'Workshop Payment Customer'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_type, subject_notes,
  estimated_duration_hours, status, priority
) values (
  '99942000-0000-4000-8000-000000000020',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000010',
  'item_service',
  'Servicio de prueba',
  1.5,
  'PENDIENTE',
  'NORMAL'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, quantity, unit_price,
  total_price, notes, description, item_type,
  service_configuration_data, system_key, component_slot_key,
  location_key, intervention_type, creates_lifecycle
) values (
  '99942000-0000-4000-8000-000000000030',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000020',
  'Servicio taller',
  1,
  119000,
  119000,
  'Diagnóstico original',
  'Diagnóstico original',
  'service',
  '{"_notes":"Torque final confirmado"}'::jsonb,
  'cockpit',
  'headset',
  'none',
  'adjusted',
  true
);

insert into public.mechanic_job_tasks(
  id, tenant_id, job_id, parent_item_id, task_name
) values (
  '99942000-0000-4000-8000-000000000040',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000020',
  '99942000-0000-4000-8000-000000000030',
  'Tarea que debe sobrevivir'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_invoice_from_mechanic_job(uuid)',
    'execute'
  ),
  'anonymous callers cannot create workshop invoices'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.sync_invoice_items_to_job(uuid)',
    'execute'
  ),
  'anonymous callers cannot run invoice to job sync'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.sync_job_to_invoice(uuid)',
    'execute'
  ),
  'anonymous callers cannot run job to invoice sync'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.create_invoice_from_mechanic_job(uuid)',
    'execute'
  ),
  'service role cannot bypass the employee workshop invoice command'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.sync_invoice_items_to_job(uuid)',
    'execute'
  ),
  'service role cannot invoke invoice to job sync directly'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.sync_invoice_status_to_job(uuid)',
    'execute'
  ),
  'service role cannot invoke invoice status sync directly'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.sync_job_to_invoice(uuid)',
    'execute'
  ),
  'service role cannot invoke job to invoice sync directly'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.register_sales_payment_with_invoice_tax(uuid,uuid,text,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'anonymous callers cannot run the payment tax command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.register_sales_payment_with_invoice_tax(uuid,uuid,text,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'authenticated employees can run the payment tax command'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.register_sales_payment_with_invoice_tax(uuid,uuid,text,numeric,timestamptz,text,text,text)',
    'execute'
  ),
  'service role cannot bypass the employee payment command'
);
select ok(
  to_regprocedure('public.apply_workshop_invoice_backfill(uuid,text)') is null,
  'unsafe broad historical backfill command is absent'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_workshop_financial_backfill(uuid,text)',
    'execute'
  ),
  'employees cannot invoke the historical financial backfill'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.apply_workshop_financial_backfill(uuid,text)',
    'execute'
  ),
  'service role cannot invoke the historical financial backfill'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_accounting_source_identity_backfill(uuid,text)',
    'execute'
  ),
  'employees cannot invoke the accounting source identity backfill'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.apply_accounting_source_identity_backfill(uuid,text)',
    'execute'
  ),
  'service role cannot invoke the accounting source identity backfill'
);

select is(
  public.create_invoice_from_mechanic_job(
    '99942000-0000-4000-8000-000000000020'
  ) is not null,
  true,
  'job creates one linked invoice'
);

select is(
  (select tax_treatment from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'no_tax',
  'new workshop invoice starts without tax until payment terminal decides'
);
select is(
  (select (items->0->>'id')::uuid from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  '99942000-0000-4000-8000-000000000030'::uuid,
  'invoice line carries the stable mechanic job item UUID'
);
select is(
  (select estimated_duration_hours from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  1.50::numeric,
  'estimated duration persists on the job'
);
select is(
  (select items->0->'service_configuration_data'->>'_notes'
     from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'Torque final confirmado',
  'invoice line carries durable service configuration data'
);
select is(
  (select items->0->>'system_key' from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'cockpit',
  'invoice line carries technical target metadata'
);

update public.sales_invoices
   set items = jsonb_set(items, '{0,description}', '"Diagnóstico actualizado"'::jsonb)
 where id = (select invoice_id from public.mechanic_jobs
              where id = '99942000-0000-4000-8000-000000000020');

select is(
  (select id from public.mechanic_job_items
    where job_id = '99942000-0000-4000-8000-000000000020'),
  '99942000-0000-4000-8000-000000000030'::uuid,
  'invoice to job sync preserves the item UUID'
);
select is(
  (select notes from public.mechanic_job_items
    where id = '99942000-0000-4000-8000-000000000030'),
  'Diagnóstico actualizado',
  'invoice to job sync updates the matching item in place'
);
select ok(
  exists(select 1 from public.mechanic_job_tasks
    where id = '99942000-0000-4000-8000-000000000040'
      and parent_item_id = '99942000-0000-4000-8000-000000000030'),
  'item task survives invoice round-trip'
);
select is(
  (select service_configuration_data->>'_notes'
     from public.mechanic_job_items
    where id = '99942000-0000-4000-8000-000000000030'),
  'Torque final confirmado',
  'invoice edit preserves service configuration on the job item'
);
select is(
  (select system_key from public.mechanic_job_items
    where id = '99942000-0000-4000-8000-000000000030'),
  'cockpit',
  'invoice edit preserves technical target metadata on the job item'
);

update public.sales_invoices
   set items = jsonb_set(
     jsonb_set(items, '{0,cost}', '1750'::jsonb),
     '{0,purchase_treatment}',
     '"workshop_consumable"'::jsonb
   )
 where id = (select invoice_id from public.mechanic_jobs
              where id = '99942000-0000-4000-8000-000000000020');
select public.sync_job_to_invoice('99942000-0000-4000-8000-000000000020');
select is(
  (select (items->0->>'cost')::numeric from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  1750::numeric,
  'job to invoice sync preserves accounting cost metadata'
);
select is(
  (select items->0->>'purchase_treatment' from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'workshop_consumable',
  'job to invoice sync preserves purchase treatment metadata'
);

select throws_ok(
  $$
    update public.sales_invoices
       set tax_treatment = 'tax_included'
     where id = (select invoice_id from public.mechanic_jobs
                  where id = '99942000-0000-4000-8000-000000000020')
  $$,
  '42501',
  'El IVA de la factura se controla únicamente desde el panel de pago.',
  'direct interactive invoice tax edits are rejected'
);

update public.user_profiles
   set role = 'mechanic', permissions = '{}'::jsonb
 where user_id = '99942000-0000-4000-8000-000000000099';
select throws_ok(
  $$
    select public.register_sales_payment_with_invoice_tax(
      (select invoice_id from public.mechanic_jobs
       where id = '99942000-0000-4000-8000-000000000020'),
      (select id from public.payment_methods
       where tenant_id = '99942000-0000-4000-8000-000000000001'
         and code = 'cash'),
      'workshop-payment-command-denied',
      119000,
      '2026-07-15T12:00:00Z'::timestamptz,
      null,
      null,
      'tax_included'
    )
  $$,
  '42501',
  'The active employee is not authorized to register payments',
  'mechanics without explicit payment permission are rejected'
);
update public.user_profiles
   set role = 'admin'
 where user_id = '99942000-0000-4000-8000-000000000099';

create temp table payment_result on commit drop as
select public.register_sales_payment_with_invoice_tax(
  (select invoice_id from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  (select id from public.payment_methods
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and code = 'cash'),
  'workshop-payment-command-1',
  119000,
  '2026-07-15T12:00:00Z'::timestamptz,
  'QA-REF',
  'Pago de prueba',
  'tax_included'
) as payload;

select is(
  (select tax_treatment from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'tax_included',
  'payment command sets invoice tax treatment'
);
select is(
  (select iva_amount from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  19000.00::numeric,
  'invoice extracts exact whole-CLP IVA from tax-included total'
);
select is(
  (select status from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'paid',
  'full payment posts and pays a draft workshop invoice'
);
select is(
  (select tax_treatment from public.sales_payments
    where idempotency_key = 'workshop-payment-command-1'),
  'tax_included',
  'payment row mirrors invoice tax treatment'
);
select is(
  (select tax_amount from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  19000.00::numeric,
  'job mirrors invoice tax amount without adding it to total'
);
select is(
  (select total_cost from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  119000.00::numeric,
  'job total equals invoice total instead of invoice plus IVA'
);
select is(
  (select count(*) from public.stock_movements
    where reference = 'sales_invoice:' || (
      select invoice_id::text from public.mechanic_jobs
      where id = '99942000-0000-4000-8000-000000000020'
    )),
  0::bigint,
  'service-only workshop payment creates zero stock movements'
);
select ok(
  not exists(
    select 1
    from public.journal_entries entry
    where entry.tenant_id = '99942000-0000-4000-8000-000000000001'
      and entry.total_debit is distinct from entry.total_credit
  ),
  'invoice and payment journals remain balanced'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_type, subject_notes,
  status, priority
) values (
  '99942000-0000-4000-8000-000000000023',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000010',
  'item_service',
  'Servicio sin IVA con dos pagos',
  'PENDIENTE',
  'NORMAL'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, quantity, unit_price,
  total_price, item_type
) values (
  '99942000-0000-4000-8000-000000000036',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000023',
  'Servicio no afecto', 1, 10000, 10000, 'service'
);

select ok(
  public.create_invoice_from_mechanic_job(
    '99942000-0000-4000-8000-000000000023'
  ) is not null,
  'a second workshop job creates its no-tax invoice'
);

select public.register_sales_payment_with_invoice_tax(
  (select invoice_id from public.mechanic_jobs
   where id = '99942000-0000-4000-8000-000000000023'),
  (select id from public.payment_methods
   where tenant_id = '99942000-0000-4000-8000-000000000001'
     and code = 'cash'),
  'workshop-no-tax-partial-1',
  4000,
  '2026-07-15T13:00:00Z'::timestamptz,
  null,
  'Primer abono sin IVA',
  'no_tax'
);

select results_eq(
  $$select status, paid_amount, balance, tax_treatment
    from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
      where id = '99942000-0000-4000-8000-000000000023')$$,
  $$values ('confirmed'::text, 4000::numeric, 6000::numeric, 'no_tax'::text)$$,
  'the atomic no-tax command posts a partial invoice with exact balance'
);
select is(
  (select tax_treatment from public.sales_payments
   where idempotency_key = 'workshop-no-tax-partial-1'),
  'no_tax',
  'the first partial payment mirrors the selected no-tax treatment'
);
select results_eq(
  $$select tax_treatment, tax_amount, total_cost
    from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000023'$$,
  $$values ('no_tax'::text, 0::numeric, 10000::numeric)$$,
  'the linked job mirrors no tax without changing the customer total'
);

select public.register_sales_payment_with_invoice_tax(
  (select invoice_id from public.mechanic_jobs
   where id = '99942000-0000-4000-8000-000000000023'),
  (select id from public.payment_methods
   where tenant_id = '99942000-0000-4000-8000-000000000001'
     and code = 'cash'),
  'workshop-no-tax-partial-2',
  6000,
  '2026-07-15T13:05:00Z'::timestamptz,
  null,
  'Saldo sin IVA',
  'no_tax'
);

select results_eq(
  $$select status, paid_amount, balance
    from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
      where id = '99942000-0000-4000-8000-000000000023')$$,
  $$values ('paid'::text, 10000::numeric, 0::numeric)$$,
  'the second no-tax payment closes the same invoice exactly'
);
select is(
  (select count(*) from public.sales_payments
   where idempotency_key in (
     'workshop-no-tax-partial-1', 'workshop-no-tax-partial-2'
   )),
  2::bigint,
  'the two atomic no-tax commands create exactly two payments'
);
select is(
  (select is_paid from public.mechanic_jobs
   where id = '99942000-0000-4000-8000-000000000023'),
  true,
  'the fully settled no-tax invoice marks the linked job paid'
);
select is(
  (select count(*) from public.stock_movements
   where reference = 'sales_invoice:' || (
     select invoice_id::text from public.mechanic_jobs
     where id = '99942000-0000-4000-8000-000000000023'
   )),
  0::bigint,
  'two payments for a service-only invoice create no stock movements'
);
select ok(
  not exists(
    select 1
    from public.journal_entries entry
    where entry.tenant_id = '99942000-0000-4000-8000-000000000001'
      and entry.total_debit is distinct from entry.total_credit
  ),
  'partial and final no-tax payment journals remain balanced'
);

select lives_ok(
  $$
    select public.register_sales_payment_with_invoice_tax(
      (select invoice_id from public.mechanic_jobs
       where id = '99942000-0000-4000-8000-000000000020'),
      (select id from public.payment_methods
       where tenant_id = '99942000-0000-4000-8000-000000000001'
         and code = 'cash'),
      'workshop-payment-command-1',
      119000,
      '2026-07-15T12:00:00Z'::timestamptz,
      'QA-REF',
      'Pago de prueba',
      'tax_included'
    )
  $$,
  'payment command replays safely'
);
select is(
  (select count(*) from public.sales_payments
    where idempotency_key = 'workshop-payment-command-1'),
  1::bigint,
  'payment replay does not duplicate cash settlement'
);
select is(
  (select count(*) from public.sales_payment_command_receipts
    where idempotency_key = 'workshop-payment-command-1'),
  1::bigint,
  'payment command stores one immutable retry receipt'
);
select is(
  (select length(payload_hash) from public.sales_payment_command_receipts
    where idempotency_key = 'workshop-payment-command-1'),
  64,
  'payment receipt fingerprints the complete normalized payload with SHA-256'
);
select throws_ok(
  $$
    update public.sales_payment_command_receipts
       set payload_snapshot = '{}'::jsonb
     where idempotency_key = 'workshop-payment-command-1'
  $$,
  '55000',
  'Payment command receipts are immutable',
  'payment receipts cannot be rewritten'
);
select throws_ok(
  $$
    delete from public.sales_payment_command_receipts
     where idempotency_key = 'workshop-payment-command-1'
  $$,
  '55000',
  'Payment command receipts are immutable',
  'payment receipts cannot be deleted'
);
select throws_ok(
  $$
    select public.register_sales_payment_with_invoice_tax(
      (select invoice_id from public.mechanic_jobs
       where id = '99942000-0000-4000-8000-000000000020'),
      (select id from public.payment_methods
       where tenant_id = '99942000-0000-4000-8000-000000000001'
         and code = 'cash'),
      'workshop-payment-command-1',
      119000,
      '2026-07-15T12:00:00Z'::timestamptz,
      'QA-REF',
      'Contenido diferente',
      'tax_included'
    )
  $$,
  '23000',
  'La clave idempotente ya fue usada con otro contenido de pago.',
  'one payment key cannot be reused with changed notes'
);
select throws_ok(
  $$
    select public.register_sales_payment_with_invoice_tax(
      (select invoice_id from public.mechanic_jobs
       where id = '99942000-0000-4000-8000-000000000020'),
      (select id from public.payment_methods
       where tenant_id = '99942000-0000-4000-8000-000000000001'
         and code = 'cash'),
      'workshop-payment-command-2',
      1,
      '2026-07-15T12:01:00Z'::timestamptz,
      null,
      null,
      'no_tax'
    )
  $$,
  'P0001',
  'El pago excede el saldo pendiente de la factura de venta.',
  'a later payment is bounded by the balance, not by the document tax'
);

update public.mechanic_jobs
   set tax_treatment = 'no_tax', tax_amount = 999, total_cost = 138000
 where id = '99942000-0000-4000-8000-000000000020';

create temp table financial_backfill_before on commit drop as
select
  (select id
     from public.journal_entries
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and source_module = 'sales_payments'
      and source_reference = (
        select id::text from public.sales_payments
        where idempotency_key = 'workshop-payment-command-1'
      )) as payment_journal_id,
  (select count(*) from public.stock_movements
    where tenant_id = '99942000-0000-4000-8000-000000000001') as stock_count;

-- Reproduce a legacy payment mirror without exercising the current integrity
-- trigger. The metadata-only after-trigger guard must preserve its payment JE.
-- Server-owned tax fields are immutable for an authenticated caller, so the
-- legacy row is forged the only way the platform itself could have written it.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
alter table public.sales_payments
  disable trigger trg_sales_payments_validate_integrity;
update public.sales_payments
   set tax_treatment = 'no_tax', net_amount = 1, iva_amount = 999
 where idempotency_key = 'workshop-payment-command-1';
alter table public.sales_payments
  enable trigger trg_sales_payments_validate_integrity;
select set_config(
  'request.jwt.claims',
  '{"sub":"99942000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

delete from public.journal_entries
 where tenant_id = '99942000-0000-4000-8000-000000000001'
   and source_module = 'sales_invoices'
   and source_reference = (
     select invoice_number from public.sales_invoices
      where id = (
        select invoice_id from public.mechanic_jobs
         where id = '99942000-0000-4000-8000-000000000020'
      )
   );

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
create temp table financial_backfill_result on commit drop as
select public.apply_workshop_financial_backfill(
  '99942000-0000-4000-8000-000000000001',
  'workshop-financial-test-1'
) as payload;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

select is(
  (select (payload->>'changed_jobs')::integer from financial_backfill_result),
  1,
  'financial backfill repairs the deterministic job mirror'
);
select is(
  (select (payload->>'changed_payments')::integer from financial_backfill_result),
  1,
  'financial backfill repairs the deterministic payment tax mirror'
);
select is(
  (select (payload->>'repaired_invoice_journals')::integer
     from financial_backfill_result),
  1,
  'financial backfill recreates the proven missing invoice journal'
);
select is(
  (select (payload->>'legacy_unresolved')::integer
     from financial_backfill_result),
  0,
  'deterministic fixture produces no unresolved accounting case'
);
select is(
  (select tax_treatment from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  'tax_included',
  'financial backfill restores job tax treatment from invoice truth'
);
select is(
  (select tax_amount from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  19000.00::numeric,
  'financial backfill restores the job IVA mirror'
);
select is(
  (select total_cost from public.mechanic_jobs
    where id = '99942000-0000-4000-8000-000000000020'),
  119000.00::numeric,
  'financial backfill restores the invoice-owned job total'
);
select is(
  (select tax_treatment from public.sales_payments
    where idempotency_key = 'workshop-payment-command-1'),
  'no_tax',
  'financial backfill never reclassifies a payment it did not classify'
);
select is(
  (select net_amount from public.sales_payments
    where idempotency_key = 'workshop-payment-command-1'),
  119000.00::numeric,
  'financial backfill restores payment net metadata from its own treatment'
);
select is(
  (select iva_amount from public.sales_payments
    where idempotency_key = 'workshop-payment-command-1'),
  0.00::numeric,
  'financial backfill restores payment IVA metadata from its own treatment'
);
select is(
  (select id from public.journal_entries
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and source_module = 'sales_payments'
      and source_reference = (
        select id::text from public.sales_payments
        where idempotency_key = 'workshop-payment-command-1'
      )),
  (select payment_journal_id from financial_backfill_before),
  'payment metadata repair preserves the original payment journal identity'
);
select is(
  (select count(*) from public.journal_entries
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and source_module = 'sales_invoices'
      and source_reference = (
        select invoice_number from public.sales_invoices
         where id = (
           select invoice_id from public.mechanic_jobs
            where id = '99942000-0000-4000-8000-000000000020'
         )
      )),
  1::bigint,
  'financial backfill leaves exactly one invoice journal'
);
select is(
  (select sum(line.debit_amount)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '99942000-0000-4000-8000-000000000001'
      and entry.source_module = 'sales_invoices'
      and line.account_code = '1130'
      and entry.source_reference = (
        select invoice_number from public.sales_invoices
         where id = (
           select invoice_id from public.mechanic_jobs
            where id = '99942000-0000-4000-8000-000000000020'
         )
      )),
  119000.00::numeric,
  'repaired invoice journal recognizes the exact receivable total'
);
select is(
  (select sum(line.credit_amount)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '99942000-0000-4000-8000-000000000001'
      and entry.source_module = 'sales_invoices'
      and line.account_code in ('4100', '4101', '2150', '2110')
      and entry.source_reference = (
        select invoice_number from public.sales_invoices
         where id = (
           select invoice_id from public.mechanic_jobs
            where id = '99942000-0000-4000-8000-000000000020'
         )
      )),
  119000.00::numeric,
  'repaired invoice journal recognizes exact revenue plus IVA'
);
select is(
  (select count(*) from public.stock_movements
    where tenant_id = '99942000-0000-4000-8000-000000000001'),
  (select stock_count from financial_backfill_before),
  'financial backfill creates zero stock movements'
);
select ok(
  (select count(*) >= 3
     from public.workshop_financial_backfill_rows
    where run_id = (
      select id from public.workshop_financial_backfill_runs
       where batch_key = 'workshop-financial-test-1'
    )),
  'financial backfill records job, payment and journal before/after evidence'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
create temp table financial_backfill_replay on commit drop as
select public.apply_workshop_financial_backfill(
  '99942000-0000-4000-8000-000000000001',
  'workshop-financial-test-1'
) as payload;
select ok(
  (select (payload->>'replayed')::boolean from financial_backfill_replay),
  'financial backfill batch key replays idempotently'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

create temp table source_identity_before on commit drop as
select count(*) as stock_count
from public.stock_movements
where tenant_id = '99942000-0000-4000-8000-000000000001';

select set_config('app.allow_legacy_duplicate_invoice_number', 'true', true);
alter table public.sales_invoices
  drop constraint if exists sales_invoices_tenant_id_invoice_number_key;
insert into public.sales_invoices(
  id, tenant_id, invoice_number, status, date,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  items, tax_treatment, source
)
select
  '99942000-0000-4000-8000-000000000070',
  tenant_id,
  invoice_number,
  'confirmed',
  '2026-07-15T13:00:00Z'::timestamptz,
  5000,
  5000,
  0,
  5000,
  0,
  5000,
  '[]'::jsonb,
  'no_tax',
  'mechanic_job'
from public.sales_invoices
where id = (
  select invoice_id from public.mechanic_jobs
  where id = '99942000-0000-4000-8000-000000000020'
);
select set_config('app.allow_legacy_duplicate_invoice_number', '', true);

select is(
  (select count(*) from public.journal_entries
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and source_module = 'sales_invoices'
      and source_document_id = '99942000-0000-4000-8000-000000000070'),
  0::bigint,
  'legacy duplicate number initially demonstrates the missing-journal collision'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
create temp table source_identity_result on commit drop as
select public.apply_accounting_source_identity_backfill(
  '99942000-0000-4000-8000-000000000001',
  'accounting-source-test-1'
) as payload;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

select is(
  (select (payload->>'duplicate_references_normalized')::integer
     from source_identity_result),
  1,
  'identity backfill normalizes the original duplicate-number journal reference'
);
select is(
  (select (payload->>'missing_duplicate_journals_created')::integer
     from source_identity_result),
  1,
  'identity backfill creates the one proven missing duplicate-number journal'
);
select is(
  (select (payload->>'legacy_unresolved')::integer
     from source_identity_result),
  0,
  'identity fixture has no unresolved orphan journal'
);
select is(
  (select count(*) from public.journal_entries entry
    join public.sales_invoices invoice
      on invoice.id = entry.source_document_id
     and invoice.tenant_id = entry.tenant_id
    where entry.tenant_id = '99942000-0000-4000-8000-000000000001'
      and entry.source_module = 'sales_invoices'
      and invoice.invoice_number = (
        select invoice_number from public.sales_invoices
        where id = '99942000-0000-4000-8000-000000000070'
      )),
  2::bigint,
  'duplicate visible number now has two independently owned journals'
);
select is(
  (select sum(line.debit_amount)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.source_document_id = (
      select invoice_id from public.mechanic_jobs
      where id = '99942000-0000-4000-8000-000000000020'
    ) and line.account_code = '1130'),
  119000.00::numeric,
  'original invoice keeps its exact receivable after identity split'
);
select is(
  (select sum(line.debit_amount)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.source_document_id = '99942000-0000-4000-8000-000000000070'
      and line.account_code = '1130'),
  5000.00::numeric,
  'duplicate invoice receives its own exact receivable'
);
select is(
  (select count(*) from public.journal_entries
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and source_module = 'sales_invoices'
      and source_reference = source_document_id::text
      and source_document_id in (
        '99942000-0000-4000-8000-000000000070',
        (select invoice_id from public.mechanic_jobs
         where id = '99942000-0000-4000-8000-000000000020')
      )),
  2::bigint,
  'duplicate-number journals use UUID source references'
);
select ok(
  (select count(*) >= 2
     from public.accounting_source_identity_backfill_rows
    where run_id = (
      select id from public.accounting_source_identity_backfill_runs
      where batch_key = 'accounting-source-test-1'
    )),
  'identity backfill records normalization and creation evidence'
);
select throws_ok(
  $$
    insert into public.sales_invoices(
      id, tenant_id, invoice_number, status, total, subtotal,
      net_amount, paid_amount, balance, items
    )
    select
      '99942000-0000-4000-8000-000000000071',
      tenant_id, invoice_number, 'draft', 1, 1, 1, 0, 1, '[]'::jsonb
    from public.sales_invoices
    where id = '99942000-0000-4000-8000-000000000070'
  $$,
  '23505',
  'El número de factura de venta ya existe para este tenant.',
  'new duplicate sales invoice numbers are rejected'
);

update public.sales_invoices
   set subtotal = 6000, net_amount = 6000, total = 6000, balance = 6000
 where id = '99942000-0000-4000-8000-000000000070';
select is(
  (select sum(line.debit_amount)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.source_document_id = (
      select invoice_id from public.mechanic_jobs
      where id = '99942000-0000-4000-8000-000000000020'
    ) and line.account_code = '1130'),
  119000.00::numeric,
  'editing one duplicate invoice does not rewrite its sibling journal'
);
select is(
  (select sum(line.debit_amount)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.source_document_id = '99942000-0000-4000-8000-000000000070'
      and line.account_code = '1130'),
  6000.00::numeric,
  'edited duplicate invoice recreates only its own journal'
);
select is(
  (select count(*) from public.journal_entries
    where tenant_id = '99942000-0000-4000-8000-000000000001'
      and source_module = 'sales_invoices'
      and source_document_id in (
        '99942000-0000-4000-8000-000000000070',
        (select invoice_id from public.mechanic_jobs
         where id = '99942000-0000-4000-8000-000000000020')
      )),
  2::bigint,
  'one journal remains for each duplicate-number invoice UUID'
);
select is(
  (select count(*) from public.stock_movements
    where tenant_id = '99942000-0000-4000-8000-000000000001'),
  (select stock_count from source_identity_before),
  'identity repair and duplicate journal edit create zero stock movements'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
create temp table source_identity_replay on commit drop as
select public.apply_accounting_source_identity_backfill(
  '99942000-0000-4000-8000-000000000001',
  'accounting-source-test-1'
) as payload;
select ok(
  (select (payload->>'replayed')::boolean from source_identity_replay),
  'accounting source identity batch replays idempotently'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

select set_config('app.syncing_job_to_invoice', 'true', true);
update public.sales_invoices
   set items = jsonb_set(items, '{0,id}', to_jsonb(gen_random_uuid()::text))
 where id = (select invoice_id from public.mechanic_jobs
              where id = '99942000-0000-4000-8000-000000000020');
select set_config('app.syncing_job_to_invoice', '', true);

insert into public.bikes(
  id, tenant_id, customer_id, brand, model, serial_number
) values (
  '99942000-0000-4000-8000-000000000011',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000010',
  'Test',
  'Ambiguous',
  'AMB-1'
);
insert into public.products(
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level,
  max_stock_level
) values (
  '99942000-0000-4000-8000-000000000033',
  '99942000-0000-4000-8000-000000000001',
  'Servicio catálogo dual',
  'SERVICE-DUAL',
  2000,
  0,
  'service',
  true,
  false,
  0,
  0,
  0,
  0
);
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, status, priority
) values (
  '99942000-0000-4000-8000-000000000021',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000010',
  '99942000-0000-4000-8000-000000000011',
  'PENDIENTE',
  'NORMAL'
);
insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, diagnosis_sheet_data
) values (
  '99942000-0000-4000-8000-000000000022',
  '99942000-0000-4000-8000-000000000001',
  '99942000-0000-4000-8000-000000000021',
  '99942000-0000-4000-8000-000000000011',
  '{"drivetrain":{"chain_wear_percent":0.8}}'::jsonb
);
insert into public.mechanic_job_items(
  id, tenant_id, job_id, job_bike_id, product_name, quantity,
  unit_price, total_price, item_type, product_id, service_product_id,
  notes, description, created_at, updated_at
) values
  (
    '99942000-0000-4000-8000-000000000031',
    '99942000-0000-4000-8000-000000000001',
    '99942000-0000-4000-8000-000000000021',
    '99942000-0000-4000-8000-000000000022',
    'Línea repetida', 1, 1000, 1000, 'adhoc', null, null,
    'Delantera', 'Delantera', now(), now()
  ),
  (
    '99942000-0000-4000-8000-000000000032',
    '99942000-0000-4000-8000-000000000001',
    '99942000-0000-4000-8000-000000000021',
    '99942000-0000-4000-8000-000000000022',
    'Línea repetida', 1, 1000, 1000, 'adhoc', null, null,
    'Trasera', 'Trasera', now() + interval '1 second', now()
  ),
  (
    '99942000-0000-4000-8000-000000000033',
    '99942000-0000-4000-8000-000000000001',
    '99942000-0000-4000-8000-000000000021',
    '99942000-0000-4000-8000-000000000022',
    'Servicio catálogo dual', 1, 2000, 2000, 'service',
    '99942000-0000-4000-8000-000000000033',
    '99942000-0000-4000-8000-000000000033',
    'Servicio dual', 'Servicio dual', now() + interval '2 seconds', now()
  ),
  (
    '99942000-0000-4000-8000-000000000034',
    '99942000-0000-4000-8000-000000000001',
    '99942000-0000-4000-8000-000000000021',
    '99942000-0000-4000-8000-000000000022',
    'Línea repetida', 1, 1000, 1000, 'adhoc', null, null,
    'Duplicada', 'Duplicada', now() + interval '3 seconds', now()
  ),
  (
    '99942000-0000-4000-8000-000000000035',
    '99942000-0000-4000-8000-000000000001',
    '99942000-0000-4000-8000-000000000021',
    '99942000-0000-4000-8000-000000000022',
    'Línea repetida', 1, 1000, 1000, 'adhoc', null, null,
    'Duplicada', 'Duplicada', now() + interval '4 seconds', now()
  );
select public.create_invoice_from_mechanic_job(
  '99942000-0000-4000-8000-000000000021'
);
select set_config('app.syncing_job_to_invoice', 'true', true);
update public.sales_invoices
   set items = jsonb_set(
     jsonb_set(
       jsonb_set(
         jsonb_set(
           jsonb_set(
             jsonb_set(
               items,
               '{0,id}',
               '"99942000-0000-4000-8000-000000000081"'::jsonb
             ),
             '{1,id}',
             '"99942000-0000-4000-8000-000000000082"'::jsonb
           ),
           '{2,id}',
           '"99942000-0000-4000-8000-000000000083"'::jsonb
         ),
         '{3,id}',
         '"99942000-0000-4000-8000-000000000084"'::jsonb
       ),
       '{4,id}',
       '"99942000-0000-4000-8000-000000000085"'::jsonb
     ),
     '{4,description}',
     '"Duplicada"'::jsonb
   )
 where id = (
   select invoice_id from public.mechanic_jobs
   where id = '99942000-0000-4000-8000-000000000021'
 );
select set_config('app.syncing_job_to_invoice', '', true);

select set_config('app.syncing_job_to_invoice', 'true', true);
update public.sales_invoices
   set reference = 'Pega PG-TEST'
 where id = (select invoice_id from public.mechanic_jobs
              where id = '99942000-0000-4000-8000-000000000020');
select set_config('app.syncing_job_to_invoice', '', true);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
create temp table line_identity_backfill_result on commit drop as
select public.apply_workshop_line_identity_backfill(
  '99942000-0000-4000-8000-000000000001',
  'workshop-line-identity-test-1'
) as payload;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);

select is(
  (select (payload->>'changed_invoice_lines')::int
     from line_identity_backfill_result),
  4,
  'line identity backfill changes unique, description-disambiguated and legacy dual-service matches'
);
select is(
  (select reference from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  'Trabajo PG-TEST',
  'line identity backfill normalizes the legacy user-facing reference'
);
select is(
  (select items->0->>'id' from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000020')),
  '99942000-0000-4000-8000-000000000030',
  'line identity backfill stamps the unique mechanic item UUID'
);
select is(
  (select items->3->>'id' from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000021')),
  '99942000-0000-4000-8000-000000000084',
  'line identity backfill leaves ambiguous duplicate lines untouched'
);
select is(
  (select items->1->>'id' from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000021')),
  '99942000-0000-4000-8000-000000000032',
  'exact preserved description disambiguates repeated workshop lines'
);
select is(
  (select items->2->>'id' from public.sales_invoices
    where id = (select invoice_id from public.mechanic_jobs
                 where id = '99942000-0000-4000-8000-000000000021')),
  '99942000-0000-4000-8000-000000000033',
  'legacy service rows match when product and service product UUIDs are both populated'
);
select is(
  (select (payload->>'manual_review_lines')::int
     from line_identity_backfill_result),
  2,
  'line identity backfill reports ambiguous lines for manual review'
);
select ok(
  (select count(*) >= 2
     from public.workshop_line_identity_backfill_rows
    where run_id = (
      select id from public.workshop_line_identity_backfill_runs
      where batch_key = 'workshop-line-identity-test-1'
    )),
  'line identity backfill records line and reference before/after evidence'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
create temp table line_identity_backfill_replay on commit drop as
select public.apply_workshop_line_identity_backfill(
    '99942000-0000-4000-8000-000000000001',
    'workshop-line-identity-test-1'
  ) as payload;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99942000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99942000-0000-4000-8000-000000000099',
  true
);
select ok(
  (select (payload->>'replayed')::boolean
     from line_identity_backfill_replay),
  'line identity backfill batch key replays idempotently'
);

select * from finish();
rollback;
