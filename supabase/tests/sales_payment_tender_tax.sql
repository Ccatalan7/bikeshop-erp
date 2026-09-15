begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(11);

-- A sale settled with two tenders: cash, which this shop does not document,
-- and a debit card, which it does. Before 20260819180000 the first payment
-- fixed one tax treatment for the whole document and the second was rejected
-- with 55000, so a mixed-tender sale could not be classified at all.

insert into public.tenants(id, shop_name) values (
  '99943000-0000-4000-8000-000000000001',
  'Tender Tax Tenant'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99943000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'tender-tax@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99943000-0000-4000-8000-000000000099',
  '99943000-0000-4000-8000-000000000001',
  'admin'
);

select public.seed_payment_terminal_profiles_for_tenant(
  '99943000-0000-4000-8000-000000000001'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99943000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99943000-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values (
  '99943000-0000-4000-8000-000000000010',
  '99943000-0000-4000-8000-000000000001',
  'Tender Tax Customer'
);

insert into public.sales_invoices(
  id, tenant_id, customer_id, invoice_number, date, due_date,
  subtotal, total, status, source, tax_treatment
) values (
  '99943000-0000-4000-8000-000000000020',
  '99943000-0000-4000-8000-000000000001',
  '99943000-0000-4000-8000-000000000010',
  'FV-TENDER-1',
  '2026-08-18',
  '2026-09-17',
  167000,
  167000,
  'confirmed',
  'manual_sale',
  'no_tax'
);

-- 1. Cash first: undocumented, no IVA.
select lives_ok(
  $$
    select public.register_sales_payment_with_invoice_tax(
      '99943000-0000-4000-8000-000000000020',
      (select id from public.payment_methods
        where tenant_id = '99943000-0000-4000-8000-000000000001'
          and code = 'cash'),
      'tender-tax-cash',
      47000,
      '2026-08-18T12:00:00Z'::timestamptz,
      null,
      null,
      'no_tax'
    )
  $$,
  'a cash payment settles without tax'
);

-- 2. The balance on a debit card: documented, 19% IVA. This is the call that
--    used to raise 55000.
select lives_ok(
  $$
    select public.register_sales_payment_with_invoice_tax(
      '99943000-0000-4000-8000-000000000020',
      (select id from public.payment_methods
        where tenant_id = '99943000-0000-4000-8000-000000000001'
          and code = 'card_debit'),
      'tender-tax-debit',
      120000,
      '2026-08-19T12:00:00Z'::timestamptz,
      null,
      null,
      'tax_included'
    )
  $$,
  'a later card payment carries its own tax on the same invoice'
);

select is(
  (select tax_treatment from public.sales_payments
    where idempotency_key = 'tender-tax-cash'),
  'no_tax',
  'the cash payment keeps its own classification'
);
select is(
  (select iva_amount from public.sales_payments
    where idempotency_key = 'tender-tax-cash'),
  0.00::numeric,
  'the cash payment recognises no IVA'
);
select is(
  (select tax_treatment from public.sales_payments
    where idempotency_key = 'tender-tax-debit'),
  'tax_included',
  'the card payment keeps its own classification'
);
select is(
  (select net_amount from public.sales_payments
    where idempotency_key = 'tender-tax-debit'),
  100840.00::numeric,
  'the card payment separates its net from the 19%'
);
select is(
  (select iva_amount from public.sales_payments
    where idempotency_key = 'tender-tax-debit'),
  19160.00::numeric,
  'the card payment recognises IVA only over its own amount'
);

-- 3. The document keeps the classification its first payment gave it. It is
--    the default the next payment starts from, not the authority over IVA.
select is(
  (select tax_treatment from public.sales_invoices
    where id = '99943000-0000-4000-8000-000000000020'),
  'no_tax',
  'a later payment never reclassifies the document'
);
select is(
  (select paid_amount from public.sales_invoices
    where id = '99943000-0000-4000-8000-000000000020'),
  167000.00::numeric,
  'both tenders settle the same invoice'
);

-- 4. The accounting follows the tender: IVA débito is credited once, for the
--    card payment only.
select is(
  (select public.clp_round(coalesce(sum(payment.iva_amount), 0))
     from public.sales_payments payment
    where payment.tenant_id = '99943000-0000-4000-8000-000000000001'
      and payment.deleted_at is null),
  19160::numeric,
  'the invoice recognises IVA over the card amount only'
);

-- 5. The workshop backfill must not read a legitimate tender difference as
--    drift; that repair loop used to rewrite the payment to mirror its
--    invoice, which would erase the classification above.
select is(
  (select count(*)::integer
     from public.sales_payments payment
    where payment.tenant_id = '99943000-0000-4000-8000-000000000001'
      and payment.deleted_at is null
      and (
        public.clp_round(payment.net_amount) is distinct from case
          when payment.tax_treatment = 'tax_included'
            then public.clp_round(payment.amount / 1.19)
          else public.clp_round(payment.amount)
        end
        or public.clp_round(payment.iva_amount) is distinct from case
          when payment.tax_treatment = 'tax_included'
            then public.clp_round(payment.amount)
                   - public.clp_round(payment.amount / 1.19)
          else 0
        end
      )),
  0,
  'neither tender is drift under the backfill repair condition'
);

select * from finish();
rollback;
