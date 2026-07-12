begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(10);

insert into public.tenants (id, shop_name)
values ('99300000-0000-4000-8000-000000000001', 'Receipt Compatibility Test');
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99300000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'receipt-compat@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99300000-0000-4000-8000-000000000001'
  ), now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role)
values (
  '99300000-0000-4000-8000-000000000099',
  '99300000-0000-4000-8000-000000000001', 'admin'
);
update auth.users
set raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
  'tenant_id', '99300000-0000-4000-8000-000000000001'
)
where id = '99300000-0000-4000-8000-000000000099';
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99300000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '99300000-0000-4000-8000-000000000099', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
) values
  ('99300000-0000-4000-8000-000000000002', '99300000-0000-4000-8000-000000000001', 'Legacy Receipt Product', 'COMPAT-OLD', 2000, 1000, 'product', false, true, 0, 0, 0, 100),
  ('99300000-0000-4000-8000-000000000005', '99300000-0000-4000-8000-000000000001', 'Guarded Receipt Product', 'COMPAT-NEW', 2000, 1000, 'product', false, true, 0, 0, 0, 100);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, net_amount, tax, total, balance, items
) values
  (
    '99300000-0000-4000-8000-000000000003',
    '99300000-0000-4000-8000-000000000001', 'FC-COMPAT-OLD',
    'Compatibility Supplier', 'draft', 3000, 3000, 0, 3000, 3000,
    '[{"line_id":"compat-old-line","product_id":"99300000-0000-4000-8000-000000000002","product_name":"Legacy Receipt Product","product_sku":"COMPAT-OLD","quantity":3,"unit_cost":1000,"purchase_treatment":"inventory","is_service":false}]'::jsonb
  ),
  (
    '99300000-0000-4000-8000-000000000004',
    '99300000-0000-4000-8000-000000000001', 'FC-COMPAT-NEW',
    'Compatibility Supplier', 'draft', 2000, 2000, 0, 2000, 2000,
    '[{"line_id":"compat-new-line","product_id":"99300000-0000-4000-8000-000000000005","product_name":"Guarded Receipt Product","product_sku":"COMPAT-NEW","quantity":2,"unit_cost":1000,"purchase_treatment":"inventory","is_service":false}]'::jsonb
  );
update public.purchase_invoices set status = 'confirmed', confirmed_date = now()
where id in (
  '99300000-0000-4000-8000-000000000003',
  '99300000-0000-4000-8000-000000000004'
);

select is(
  (select count(*)::integer from public.purchase_receipt_control_settings where tenant_id = '99300000-0000-4000-8000-000000000001'),
  0, 'schema installation activates no tenant'
);
select lives_ok(
  $$ update public.purchase_invoices
     set status = 'received', received_date = now()
     where id = '99300000-0000-4000-8000-000000000003' $$,
  'N-1 client legacy receipt remains available while control is disabled'
);
select is(
  (select status from public.purchase_invoices where id = '99300000-0000-4000-8000-000000000003'),
  'received', 'legacy client status transition completes while disabled'
);
select is(
  (select inventory_qty from public.products where id = '99300000-0000-4000-8000-000000000002'),
  3, 'legacy disabled-mode transition retains its existing stock behavior'
);
select is(
  (select count(*)::integer from public.purchase_receipts where purchase_invoice_id = '99300000-0000-4000-8000-000000000003'),
  0, 'legacy client does not fabricate a professional receipt document'
);

insert into public.purchase_receipt_control_settings (
  tenant_id, control_mode, activated_at, activated_by
) values (
  '99300000-0000-4000-8000-000000000001', 'enforce', now(),
  '99300000-0000-4000-8000-000000000099'
);
select throws_ok(
  $$ update public.purchase_invoices
     set status = 'received', received_date = now()
     where id = '99300000-0000-4000-8000-000000000004' $$,
  'P0001', 'Professional receiving is active; use the goods receipt command',
  'N-1 client is blocked before bypassing an enforced receipt command'
);
select is(
  (select status from public.purchase_invoices where id = '99300000-0000-4000-8000-000000000004'),
  'confirmed', 'blocked legacy write leaves invoice status unchanged'
);
select is(
  (select inventory_qty from public.products where id = '99300000-0000-4000-8000-000000000005'),
  0, 'blocked legacy write leaves inventory unchanged'
);
select is(
  (select count(*)::integer from public.stock_movements where product_id = '99300000-0000-4000-8000-000000000005'),
  0, 'blocked legacy write leaves no partial movement'
);
select is(
  (select count(*)::integer from public.purchase_receipts where purchase_invoice_id = '99300000-0000-4000-8000-000000000004'),
  0, 'blocked legacy write leaves no partial receipt document'
);

select * from finish();
rollback;
