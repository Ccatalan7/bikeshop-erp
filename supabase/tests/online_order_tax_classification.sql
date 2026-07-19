begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(34);

select has_function(
  'public',
  'calculate_online_order_tax_snapshot',
  array['uuid', 'uuid'],
  'private line-snapshot tax calculator exists'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.calculate_online_order_tax_snapshot(uuid,uuid)',
    'EXECUTE'
  ),
  'anonymous clients cannot call the private tax calculator'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.calculate_online_order_tax_snapshot(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated clients cannot call the private tax calculator'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.calculate_online_order_tax_snapshot(uuid,uuid)',
    'EXECUTE'
  ),
  'service workers cannot bypass the canonical checkout/processing paths'
);

select has_function(
  'public',
  'get_public_product_tax_classifications',
  array['uuid', 'uuid[]'],
  'public storefront has a narrow product tax-classification projection'
);
select ok(
  has_function_privilege(
    'anon',
    'public.get_public_product_tax_classifications(uuid,uuid[])',
    'EXECUTE'
  ) and has_function_privilege(
    'authenticated',
    'public.get_public_product_tax_classifications(uuid,uuid[])',
    'EXECUTE'
  ),
  'public storefront roles can hydrate checkout tax classifications'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.get_public_product_tax_classifications(uuid,uuid[])',
    'EXECUTE'
  ),
  'service workers cannot use the public tax projection as a financial write path'
);

insert into public.tenants (id, shop_name, currency, timezone)
values (
  '9e200000-0000-4000-8000-000000000001',
  'Online Tax Classification Test',
  'CLP',
  'America/Santiago'
);

-- Tenant seed helpers touch transaction-local auth configuration. Product
-- fixture creation must remain an actorless synthetic setup.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values
  (
    '9e200000-0000-4000-8000-000000000010',
    '9e200000-0000-4000-8000-000000000001',
    'Producto afecto', 'ONLINE-TAXED-001', 1190, 1190, 500, 19,
    'product', false, 'inventory', true, 20, 20, 0, 100,
    true, true, true
  ),
  (
    '9e200000-0000-4000-8000-000000000011',
    '9e200000-0000-4000-8000-000000000001',
    'Producto exento', 'ONLINE-EXEMPT-001', 500, 500, 200, 0,
    'product', false, 'inventory', true, 20, 20, 0, 100,
    true, true, true
  ),
  (
    '9e200000-0000-4000-8000-000000000012',
    '9e200000-0000-4000-8000-000000000001',
    'Producto sin clasificar', 'ONLINE-NULL-TAX-001', 800, 800, 300, null,
    'product', false, 'inventory', true, 20, 20, 0, 100,
    true, true, true
  ),
  (
    '9e200000-0000-4000-8000-000000000013',
    '9e200000-0000-4000-8000-000000000001',
    'Producto tasa no soportada', 'ONLINE-BAD-TAX-001', 900, 900, 300, 10,
    'product', false, 'inventory', true, 20, 20, 0, 100,
    true, true, true
  ),
  (
    '9e200000-0000-4000-8000-000000000014',
    '9e200000-0000-4000-8000-000000000001',
    'Producto precio fraccionario', 'ONLINE-FRACTIONAL-001', 1000.50, 1000.50,
    300, 19, 'product', false, 'inventory', true, 20, 20, 0, 100,
    true, true, true
  ),
  (
    '9e200000-0000-4000-8000-000000000015',
    '9e200000-0000-4000-8000-000000000001',
    'Producto tasa fraccional conocida', 'ONLINE-FRACTION-TAX-001',
    1190, 1190, 300, 0.19, 'product', false, 'inventory', true,
    20, 20, 0, 100, true, true, true
  );

select is(
  (
    select string_agg(
      classified.id::text || ':' || coalesce(classified.tax_rate::text, 'null'),
      '|' order by classified.id
    )
      from public.get_public_product_tax_classifications(
        '9e200000-0000-4000-8000-000000000001',
        array[
          '9e200000-0000-4000-8000-000000000010'::uuid,
          '9e200000-0000-4000-8000-000000000012'::uuid,
          '9e200000-0000-4000-8000-000000000013'::uuid
        ]
      ) classified
  ),
  '9e200000-0000-4000-8000-000000000010:19.00|9e200000-0000-4000-8000-000000000012:null|9e200000-0000-4000-8000-000000000013:10.00',
  'public projection preserves valid, missing, and unsupported rates so the UI fails closed'
);

create temp table online_tax_ids (
  name text primary key,
  id uuid not null
) on commit drop;

insert into online_tax_ids
select 'mixed_mp', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e200000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-tax-mixed-mp-001',
    'customer_email', 'mixed@example.invalid',
    'customer_name', 'Cliente Mixto',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago',
    'tax_amount', 999999,
    'total', 999999
  ),
  jsonb_build_array(
    jsonb_build_object(
      'product_id', '9e200000-0000-4000-8000-000000000010',
      'quantity', 1
    ),
    jsonb_build_object(
      'product_id', '9e200000-0000-4000-8000-000000000011',
      'quantity', 2
    )
  )
);

select is(
  (select total from public.online_orders
    where id = (select id from online_tax_ids where name = 'mixed_mp')),
  2190::numeric,
  'checkout total is the sum of server-owned gross line prices'
);
select is(
  (select subtotal from public.online_orders
    where id = (select id from online_tax_ids where name = 'mixed_mp')),
  2000::numeric,
  'checkout net subtotal is the sum of per-line net amounts'
);
select is(
  (select tax_amount from public.online_orders
    where id = (select id from online_tax_ids where name = 'mixed_mp')),
  190::numeric,
  'checkout IVA is the sum of per-line tax amounts'
);
select is(
  (
    select string_agg(tax_rate::text, '|' order by product_sku)
      from public.online_order_items
     where order_id = (select id from online_tax_ids where name = 'mixed_mp')
  ),
  '0.00|19.00',
  'checkout preserves both exempt and affected tax-rate snapshots'
);
select is(
  (
    select sum(
      case when tax_rate = 19
        then subtotal - public.clp_round(subtotal / 1.19)
        else 0
      end
    )
      from public.online_order_items
     where order_id = (select id from online_tax_ids where name = 'mixed_mp')
  ),
  190::numeric,
  'stored order tax equals the deterministic line-by-line calculation'
);
select is(
  (
    select request_snapshot->>'tax_source'
      from public.online_order_events
     where order_id = (select id from online_tax_ids where name = 'mixed_mp')
       and event_type = 'order_created'
  ),
  'product_line_snapshot',
  'creation receipt records the tax provenance'
);
select is(
  (select sales_invoice_id from public.online_orders
    where id = (select id from online_tax_ids where name = 'mixed_mp')),
  null::uuid,
  'pending Mercado Pago checkout does not create an invoice before payment'
);

select is(
  (
    with issued as (
      select public.issue_online_order_access_token(
        (select id from online_tax_ids where name = 'mixed_mp'),
        array['view_order']::text[],
        clock_timestamp() + interval '30 days'
      ) as access
    ), projected as (
      select public.get_public_online_order_by_access_token(
        issued.access->>'token'
      ) as payload
      from issued
    )
    select string_agg(item->>'taxRate', '|' order by item->>'sku')
      from projected,
           lateral jsonb_array_elements(projected.payload->'items') item
  ),
  '0.00|19.00',
  'token-authorized confirmation receives each immutable line tax classification'
);

insert into online_tax_ids
select 'taxed_transfer', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e200000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-tax-transfer-001',
    'customer_email', 'transfer@example.invalid',
    'customer_name', 'Cliente Transferencia',
    'delivery_type', 'pickup',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e200000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  (
    select concat_ws('|', subtotal::text, tax_amount::text, total::text)
      from public.online_orders
     where id = (select id from online_tax_ids where name = 'taxed_transfer')
  ),
  '1000.00|190.00|1190.00',
  'bank transfer has the same product-derived tax split as any other rail'
);
select is(
  (
    select status || '|' || payment_status
      from public.online_orders
     where id = (select id from online_tax_ids where name = 'taxed_transfer')
  ),
  'confirmed|pending',
  'transfer checkout retains its existing operational state flow'
);
select is(
  (
    select invoice.tax_treatment
      from public.online_orders orders
      join public.sales_invoices invoice
        on invoice.id = orders.sales_invoice_id
       and invoice.tenant_id = orders.tenant_id
     where orders.id = (select id from online_tax_ids where name = 'taxed_transfer')
  ),
  'tax_included',
  'invoice classification comes from the item tax snapshot, not the transfer rail'
);
select is(
  (
    select concat_ws(
      '|', invoice.subtotal::text, invoice.net_amount::text,
      invoice.iva_amount::text, invoice.total::text
    )
      from public.online_orders orders
      join public.sales_invoices invoice
        on invoice.id = orders.sales_invoice_id
       and invoice.tenant_id = orders.tenant_id
     where orders.id = (select id from online_tax_ids where name = 'taxed_transfer')
  ),
  '1190.00|1000.00|190.00|1190.00',
  'invoice gross, net, IVA, and total reconcile in whole CLP'
);
select is(
  (
    select concat_ws(
      '|', invoice.items->0->>'gross_amount',
      invoice.items->0->>'net_amount', invoice.items->0->>'tax_amount',
      invoice.items->0->>'tax_rate'
    )
      from public.online_orders orders
      join public.sales_invoices invoice
        on invoice.id = orders.sales_invoice_id
       and invoice.tenant_id = orders.tenant_id
     where orders.id = (select id from online_tax_ids where name = 'taxed_transfer')
  ),
  '1190.00|1000.00|190.00|19.00',
  'invoice line retains its explicit gross/net/tax breakdown and tax rate'
);

insert into online_tax_ids
select 'exempt_mp', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e200000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-tax-exempt-mp-001',
    'customer_email', 'exempt@example.invalid',
    'customer_name', 'Cliente Exento',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e200000-0000-4000-8000-000000000011',
    'quantity', 1
  ))
);

select is(
  (
    select concat_ws('|', subtotal::text, tax_amount::text, total::text)
      from public.online_orders
     where id = (select id from online_tax_ids where name = 'exempt_mp')
  ),
  '500.00|0.00|500.00',
  'Mercado Pago does not invent IVA for an exempt item'
);

insert into online_tax_ids
select 'fraction_rate_mp', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e200000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-tax-fraction-rate-mp-001',
    'customer_email', 'fraction-rate@example.invalid',
    'customer_name', 'Cliente Tasa Fraccional',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e200000-0000-4000-8000-000000000015',
    'quantity', 1
  ))
);
select is(
  (select tax_rate from public.online_order_items
    where order_id = (select id from online_tax_ids where name = 'fraction_rate_mp')),
  19::numeric,
  'known legacy fraction 0.19 is normalized to canonical 19 at checkout'
);
select is(
  (
    select concat_ws('|', subtotal::text, tax_amount::text, total::text)
      from public.online_orders
     where id = (select id from online_tax_ids where name = 'fraction_rate_mp')
  ),
  '1000.00|190.00|1190.00',
  'normalized legacy rate produces the same per-line tax calculation'
);

select throws_ok(
  $$
    select public.create_public_online_order(
      jsonb_build_object(
        'tenant_id', '9e200000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'online-tax-null-001',
        'customer_email', 'null-tax@example.invalid',
        'customer_name', 'Cliente Sin Tasa',
        'delivery_type', 'pickup',
        'payment_method', 'mercadopago'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e200000-0000-4000-8000-000000000012',
        'quantity', 1
      ))
    )
  $$,
  '23514',
  'Product Producto sin clasificar has missing or unsupported tax classification',
  'checkout fails closed when product tax classification is missing'
);
select throws_ok(
  $$
    select public.create_public_online_order(
      jsonb_build_object(
        'tenant_id', '9e200000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'online-tax-invalid-001',
        'customer_email', 'bad-tax@example.invalid',
        'customer_name', 'Cliente Tasa Invalida',
        'delivery_type', 'pickup',
        'payment_method', 'transfer'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e200000-0000-4000-8000-000000000013',
        'quantity', 1
      ))
    )
  $$,
  '23514',
  'Product Producto tasa no soportada has missing or unsupported tax classification',
  'checkout fails closed on unsupported product tax rates'
);
select throws_ok(
  $$
    select public.create_public_online_order(
      jsonb_build_object(
        'tenant_id', '9e200000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'online-tax-fractional-001',
        'customer_email', 'fractional@example.invalid',
        'customer_name', 'Cliente Precio Fraccionario',
        'delivery_type', 'pickup',
        'payment_method', 'mercadopago'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e200000-0000-4000-8000-000000000014',
        'quantity', 1
      ))
    )
  $$,
  '23514',
  'Product Producto precio fraccionario requires a positive whole-CLP website price',
  'checkout fails closed on fractional CLP website prices'
);

-- Synthetic historical pending row: process must not rewrite the old monetary
-- heuristic or invent an invoice. It stops before financial/stock effects.
select set_config('app.public_order_rpc_in_progress', 'true', true);
insert into public.online_orders (
  id, tenant_id, order_number, customer_email, customer_name, delivery_type,
  subtotal, tax_amount, shipping_cost, discount_amount, total,
  status, payment_status, payment_method
) values (
  '9e200000-0000-4000-8000-000000000090',
  '9e200000-0000-4000-8000-000000000001',
  'WEB-20-HISTORICAL', 'historical@example.invalid', 'Pedido Historico',
  'pickup', 1190, 0, 0, 0, 1190, 'pending', 'pending', 'transfer'
);
insert into public.online_order_items (
  id, tenant_id, order_id, product_id, product_name, product_sku,
  quantity, unit_price, subtotal, unit_cost, tax_rate,
  is_service, purchase_treatment, product_type
) values (
  '9e200000-0000-4000-8000-000000000091',
  '9e200000-0000-4000-8000-000000000001',
  '9e200000-0000-4000-8000-000000000090',
  '9e200000-0000-4000-8000-000000000010',
  'Producto afecto', 'ONLINE-TAXED-001', 1, 1190, 1190, 500, 19,
  false, 'inventory', 'product'
);
select set_config('app.public_order_rpc_in_progress', '', true);

select throws_ok(
  $$ select public.process_online_order('9e200000-0000-4000-8000-000000000090') $$,
  '23514',
  'Online order item monetary snapshot does not reconcile',
  'historical mismatched tax rows stop for review instead of being reclassified'
);
select is(
  (select sales_invoice_id from public.online_orders
    where id = '9e200000-0000-4000-8000-000000000090'),
  null::uuid,
  'failed historical processing creates no invoice linkage'
);
select is(
  (
    select concat_ws('|', subtotal::text, tax_amount::text, total::text)
      from public.online_orders
     where id = '9e200000-0000-4000-8000-000000000090'
  ),
  '1190.00|0.00|1190.00',
  'failed historical processing leaves the original monetary row unchanged'
);

update public.online_order_items
   set tax_rate = null
 where id = '9e200000-0000-4000-8000-000000000091';
select throws_ok(
  $$
    select public.calculate_online_order_tax_snapshot(
      '9e200000-0000-4000-8000-000000000090',
      '9e200000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'Online order line 9e200000-0000-4000-8000-000000000091 has missing or unsupported tax classification',
  'processor also fails closed when a persisted line classification is missing'
);

select is(
  position(
    'v_order.tax_amount > 0'
    in pg_get_functiondef(
      'public.process_online_order_internal(uuid)'::regprocedure
    )
  ),
  0,
  'invoice processing no longer infers tax from the order/payment heuristic'
);
select is(
  position(
    'if v_payment_method = ''mercadopago'' then'
    in pg_get_functiondef(
      'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure
    )
  ),
  0,
  'checkout no longer branches tax calculation by payment rail'
);

select is(
  (
    select count(*)::integer
      from public.online_orders
     where tenant_id = '9e200000-0000-4000-8000-000000000001'
       and customer_email in (
         'null-tax@example.invalid',
         'bad-tax@example.invalid',
         'fractional@example.invalid'
       )
  ),
  0,
  'failed checkout classifications roll back their partial order rows'
);

select * from finish();
rollback;
