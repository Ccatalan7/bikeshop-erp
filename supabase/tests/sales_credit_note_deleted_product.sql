-- A financial credit note on a sale whose product was later deleted from the
-- catalogue (2026-10-13: the store's test sales INV-25-00001/00002 sold a
-- «test» product that no longer exists, and the credit failed on the foreign
-- key to products).
begin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(6);

insert into public.tenants(id, shop_name)
values ('99610000-0000-4000-8000-000000000001', 'Deleted Product Credit Test');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99610000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'deleted-product-credit@example.invalid', '', now(), '{}',
  jsonb_build_object('tenant_id', '99610000-0000-4000-8000-000000000001'),
  now(), now()
);
delete from public.user_profiles
 where user_id = '99610000-0000-4000-8000-000000000099';
insert into public.user_profiles(user_id, tenant_id, role)
values (
  '99610000-0000-4000-8000-000000000099',
  '99610000-0000-4000-8000-000000000001',
  'admin'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99610000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', '99610000-0000-4000-8000-000000000099', true
);

insert into public.sales_credit_note_control_settings(
  tenant_id, control_mode, activated_at, activated_by
) values (
  '99610000-0000-4000-8000-000000000001', 'enforce', now(),
  '99610000-0000-4000-8000-000000000099'
);

-- An untracked product, so the sale leaves no stock movement that would keep
-- the product from being deleted — the shape of the store's «test» item.
-- A row saved before 20261030190000, when a product without tax carried no
-- tax evidence and could still be deleted; the base now gives a new one 19.
alter table public.products disable trigger trg_products_default_tax_rate;

insert into public.products(
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
) values (
  '99610000-0000-4000-8000-000000000002',
  '99610000-0000-4000-8000-000000000001',
  'Producto que se borra', 'BORRADO-1', 100, 0, 'product', false,
  false, 0, 0, 0, 0
);

alter table public.products enable trigger trg_products_default_tax_rate;
insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status, subtotal, net_amount,
  iva_amount, total, balance, tax_treatment, items
) values (
  '99610000-0000-4000-8000-000000000003',
  '99610000-0000-4000-8000-000000000001',
  'FV-BORRADO-001', 'Cliente de prueba', 'draft', 84, 84, 16, 100, 100,
  'tax_included',
  '[{"line_id":"deleted-product-line","product_id":"99610000-0000-4000-8000-000000000002","product_name":"Producto que se borra","product_sku":"BORRADO-1","quantity":1,"unit_price":100,"price":100,"discount":0,"cost":0,"is_service":false}]'
);
update public.sales_invoices
   set status = 'confirmed'
 where id = '99610000-0000-4000-8000-000000000003';
insert into public.sales_payments(
  tenant_id, invoice_id, payment_method_id, idempotency_key, amount,
  tax_treatment, net_amount, iva_amount, date
)
select '99610000-0000-4000-8000-000000000001',
       '99610000-0000-4000-8000-000000000003',
       id, 'deleted-product-payment', 100, 'tax_included', 84, 16, now()
  from public.payment_methods
 where tenant_id = '99610000-0000-4000-8000-000000000001'
 order by created_at
 limit 1;

-- A product deleted before 20261030210000: the base now archives a product
-- with sales instead of deleting it.
alter table public.products disable trigger trg_guard_product_delete_history;
delete from public.products
 where id = '99610000-0000-4000-8000-000000000002';
alter table public.products enable trigger trg_guard_product_delete_history;

select is(
  (select status from public.sales_invoices
    where id = '99610000-0000-4000-8000-000000000003'),
  'paid',
  'the sale is paid and its product no longer exists'
);

select lives_ok(
  $$create temp table deleted_product_credit on commit drop as
    select public.create_sales_credit_note(
      '99610000-0000-4000-8000-000000000003',
      '[{"line_index":0,"credited_quantity":1}]',
      now(), 'invoice_correction', 'Venta de prueba',
      'deleted-product-credit'
    ) payload$$,
  'a financial credit note is issued without the deleted product'
);

select ok(
  (select product_id is null
          and product_name = 'Producto que se borra'
          and product_sku = 'BORRADO-1'
     from public.sales_credit_note_lines
    where sales_invoice_id = '99610000-0000-4000-8000-000000000003'),
  'the credit line keeps the name and SKU without the catalogue link'
);

select is(
  (select total_amount from public.sales_credit_notes
    where sales_invoice_id = '99610000-0000-4000-8000-000000000003'),
  100::numeric,
  'the whole sale is credited'
);

select is(
  (select customer_credit_balance from public.sales_invoices
    where id = '99610000-0000-4000-8000-000000000003'),
  100::numeric,
  'the payment received becomes the customer''s credit'
);

select ok(
  exists (
    select 1
      from public.journal_entries entry
     where entry.id = (
       select journal_entry_id from public.sales_credit_notes
        where sales_invoice_id = '99610000-0000-4000-8000-000000000003'
     )
       and entry.total_debit = 100
       and entry.total_credit = 100
  ),
  'the credit journal balances'
);

select * from finish();
rollback;
