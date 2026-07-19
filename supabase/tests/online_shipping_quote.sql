begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select has_table(
  'public',
  'online_shipping_rate_tiers',
  'server-owned online shipping tariff exists'
);
select has_function(
  'public',
  'quote_public_online_shipping',
  array['uuid', 'text', 'numeric', 'text'],
  'public checkout has a narrow shipping quote RPC'
);
select ok(
  has_function_privilege(
    'anon',
    'public.quote_public_online_shipping(uuid,text,numeric,text)',
    'EXECUTE'
  ),
  'anonymous storefront can request a server-derived quote'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.quote_online_shipping_internal(uuid,text,numeric,text)',
    'EXECUTE'
  ),
  'anonymous storefront cannot call the internal quote kernel'
);

insert into public.tenants (id, shop_name, currency, timezone)
values (
  '9e300000-0000-4000-8000-000000000001',
  'Online Shipping Quote Test',
  'CLP',
  'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '9e300000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'online-shipping@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id', '9e300000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '9e300000-0000-4000-8000-000000000099';
insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values (
  '9e300000-0000-4000-8000-000000000099',
  '9e300000-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

-- Tenant bootstrap helpers touch transaction-local auth context. Bind all
-- following audit events to the real synthetic staff actor explicitly.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e300000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9e300000-0000-4000-8000-000000000099',
  true
);

insert into public.online_shipping_rate_tiers (
  id, tenant_id, country_code,
  min_order_gross, max_order_gross, shipping_gross, tax_rate,
  estimated_min_business_days, estimated_max_business_days
)
values
  (
    '9e300000-0000-4000-8000-000000000101',
    '9e300000-0000-4000-8000-000000000001',
    'CL', 0, 30000, 6990, 19, 3, 12
  ),
  (
    '9e300000-0000-4000-8000-000000000102',
    '9e300000-0000-4000-8000-000000000001',
    'CL', 30000, 80000, 8990, 19, 3, 12
  ),
  (
    '9e300000-0000-4000-8000-000000000103',
    '9e300000-0000-4000-8000-000000000001',
    'CL', 80000, 150000, 11990, 19, 3, 12
  ),
  (
    '9e300000-0000-4000-8000-000000000104',
    '9e300000-0000-4000-8000-000000000001',
    'CL', 150000, null, 14990, 19, 3, 12
  );

select results_eq(
  $$
    select sample.item_gross,
           (
             public.quote_public_online_shipping(
               '9e300000-0000-4000-8000-000000000001',
               'shipping',
               sample.item_gross,
               'CL'
             )->>'shipping_gross'
           )::numeric as shipping_gross
      from (values
        (1::numeric),
        (29999::numeric),
        (30000::numeric),
        (79999::numeric),
        (80000::numeric),
        (149999::numeric),
        (150000::numeric),
        (500000::numeric)
      ) sample(item_gross)
     order by sample.item_gross
  $$,
  $$
    values
      (1::numeric, 6990::numeric),
      (29999::numeric, 6990::numeric),
      (30000::numeric, 8990::numeric),
      (79999::numeric, 8990::numeric),
      (80000::numeric, 11990::numeric),
      (149999::numeric, 11990::numeric),
      (150000::numeric, 14990::numeric),
      (500000::numeric, 14990::numeric)
  $$,
  'the four shipping bands use exact half-open CLP boundaries'
);

select is(
  (
    public.quote_public_online_shipping(
      '9e300000-0000-4000-8000-000000000001',
      'pickup',
      23800,
      'CL'
    )->>'shipping_gross'
  )::numeric,
  0::numeric,
  'store pickup is explicitly free'
);
select is(
  (
    public.quote_public_online_shipping(
      '9e300000-0000-4000-8000-000000000001',
      'pickup',
      23800,
      'CL'
    )->>'tax_rate'
  )::numeric,
  0::numeric,
  'free pickup invents neither shipping IVA nor a tariff tier'
);

select throws_ok(
  $$
    insert into public.online_shipping_rate_tiers (
      tenant_id, country_code, min_order_gross, max_order_gross,
      shipping_gross, tax_rate,
      estimated_min_business_days, estimated_max_business_days
    ) values (
      '9e300000-0000-4000-8000-000000000001',
      'CL', 25000, 40000, 7777, 19, 3, 12
    )
  $$,
  '23514',
  'Active online shipping rate tiers may not overlap',
  'active shipping ranges cannot overlap'
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values (
  '9e300000-0000-4000-8000-000000000010',
  '9e300000-0000-4000-8000-000000000001',
  'Shipping fixture product',
  'ONLINE-SHIPPING-001',
  23800,
  23800,
  10000,
  19,
  'product',
  false,
  'inventory',
  true,
  2,
  2,
  0,
  100,
  true,
  true,
  true
);

select throws_ok(
  $$
    select public.create_public_online_order(
      jsonb_build_object(
        'tenant_id', '9e300000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'shipping-stale-quote-001',
        'customer_email', 'stale@example.invalid',
        'customer_name', 'Stale Quote',
        'customer_address', 'Alvarez 32',
        'delivery_type', 'shipping',
        'shipping_address_line1', 'Alvarez 32',
        'shipping_country', 'Chile',
        'shipping_quote_cost', 8990,
        'payment_method', 'transfer'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e300000-0000-4000-8000-000000000010',
        'quantity', 1
      ))
    )
  $$,
  '40001',
  'Shipping quote changed; refresh checkout before paying',
  'checkout rejects a stale customer shipping quote'
);
select is(
  (select count(*)::integer
     from public.online_orders
    where tenant_id = '9e300000-0000-4000-8000-000000000001'
      and checkout_idempotency_key = 'shipping-stale-quote-001'),
  0,
  'stale quote rejection rolls back order, item and reservation'
);

create temp table online_shipping_ids (
  name text primary key,
  id uuid not null
) on commit drop;

insert into online_shipping_ids
select 'order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e300000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'shipping-current-quote-001',
    'customer_email', 'current@example.invalid',
    'customer_name', 'Current Quote',
    'customer_address', 'Alvarez 32',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Alvarez 32',
    'shipping_city', 'Vina del Mar',
    'shipping_country', 'Chile',
    'shipping_quote_cost', 6990,
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e300000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select results_eq(
  $$
    select
      shipping_cost,
      shipping_net_amount,
      shipping_tax_amount,
      shipping_tax_rate,
      subtotal,
      tax_amount,
      total
      from public.online_orders
     where id = (select id from online_shipping_ids where name = 'order')
  $$,
  $$ values (
    6990::numeric,
    5874::numeric,
    1116::numeric,
    19::numeric,
    20000::numeric,
    3800::numeric,
    30790::numeric
  ) $$,
  'order freezes exact item and shipping net/IVA/gross amounts'
);
select ok(
  (
    select shipping_rate_tier_id =
             '9e300000-0000-4000-8000-000000000101'::uuid
       and shipping_rate_snapshot->>'country_code' = 'CL'
       and (shipping_rate_snapshot->>'shipping_gross')::numeric = 6990
       and (shipping_rate_snapshot->>'estimated_min_business_days')::integer = 3
       and (shipping_rate_snapshot->>'estimated_max_business_days')::integer = 12
      from public.online_orders
     where id = (select id from online_shipping_ids where name = 'order')
  ),
  'order retains the exact tariff and delivery-promise evidence'
);
select throws_ok(
  format(
    $$update public.online_orders set shipping_cost = 0 where id = %L::uuid$$,
    (select id from online_shipping_ids where name = 'order')
  ),
  '55000',
  'Online order shipping quote is immutable',
  'persisted shipping money cannot be rewritten after checkout'
);

select is(
  (select invoice.status
     from public.online_orders orders
     join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
    where orders.id = (select id from online_shipping_ids where name = 'order')),
  'sent',
  'transfer checkout creates a non-posted invoice with its shipping line'
);
select is(
  (
    select count(*)::integer
      from public.online_orders orders
      join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
      cross join lateral jsonb_array_elements(invoice.items) line
     where orders.id = (select id from online_shipping_ids where name = 'order')
       and line->>'line_kind' = 'shipping'
       and line->>'product_name' = 'Despacho a domicilio'
       and line->>'product_sku' = 'ENVIO'
       and (line->>'gross_amount')::numeric = 6990
       and (line->>'net_amount')::numeric = 5874
       and (line->>'tax_amount')::numeric = 1116
       and (line->>'tax_rate')::numeric = 19
       and (line->>'is_service')::boolean
       and line->>'product_id' is null
  ),
  1,
  'invoice contains one IVA-classified non-catalog shipping service line'
);
select results_eq(
  $$
    select invoice.net_amount, invoice.iva_amount, invoice.total
      from public.online_orders orders
      join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
     where orders.id = (select id from online_shipping_ids where name = 'order')
  $$,
  $$ values (25874::numeric, 4916::numeric, 30790::numeric) $$,
  'invoice accounting totals include item and shipping IVA exactly once'
);
select is(
  (select stock_quantity from public.products
    where id = '9e300000-0000-4000-8000-000000000010'),
  2,
  'pending transfer changes no physical stock'
);
select is(
  (select count(*)::integer
     from public.stock_movements movement
     join public.online_orders orders
       on movement.reference = 'sales_invoice:' || orders.sales_invoice_id::text
    where orders.id = (select id from online_shipping_ids where name = 'order')),
  0,
  'non-posted product and shipping lines create no stock movement'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e300000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9e300000-0000-4000-8000-000000000099',
  true
);

insert into online_shipping_ids
select 'payment', public.confirm_online_order_payment(
  (select id from online_shipping_ids where name = 'order'),
  'SHIPPING-BANK-001',
  clock_timestamp()
);

select is(
  (select stock_quantity from public.products
    where id = '9e300000-0000-4000-8000-000000000010'),
  1,
  'payment consumes the tracked catalog product exactly once'
);
select is(
  (select coalesce(-sum(movement.quantity), 0)::integer
     from public.stock_movements movement
     join public.online_orders orders
       on movement.reference = 'sales_invoice:' || orders.sales_invoice_id::text
    where orders.id = (select id from online_shipping_ids where name = 'order')
      and movement.product_id = '9e300000-0000-4000-8000-000000000010'
      and movement.quantity < 0),
  1,
  'posted invoice owns one negative physical-product unit'
);
select is(
  (select count(*)::integer
     from public.stock_movements movement
     join public.online_orders orders
       on movement.reference = 'sales_invoice:' || orders.sales_invoice_id::text
    where orders.id = (select id from online_shipping_ids where name = 'order')
      and movement.product_id <>
            '9e300000-0000-4000-8000-000000000010'::uuid),
  0,
  'shipping service line creates no phantom product movement'
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (select id from online_shipping_ids where name = 'order')),
  'consumed',
  'shipping checkout still converts its physical reservation atomically'
);
select is(
  (select invoice.status
     from public.online_orders orders
     join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
    where orders.id = (select id from online_shipping_ids where name = 'order')),
  'paid',
  'payment settles the exact shipping-inclusive invoice'
);
select is(
  (select count(*)::integer from (
    select entry.id
      from public.journal_entries entry
      join public.journal_lines line on line.entry_id = entry.id
     where entry.tenant_id = '9e300000-0000-4000-8000-000000000001'
     group by entry.id
    having sum(line.debit_amount) <> sum(line.credit_amount)
  ) unbalanced),
  0,
  'shipping-inclusive invoice and payment journals remain balanced'
);

select * from finish();
rollback;
