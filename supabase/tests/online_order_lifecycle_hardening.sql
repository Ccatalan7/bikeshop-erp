begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(57);

create temp table online_lifecycle_ids (
  name text primary key,
  id uuid not null
) on commit drop;

create temp table online_lifecycle_values (
  name text primary key,
  value text not null
) on commit drop;

create temp table online_lifecycle_results (
  name text primary key,
  passed boolean not null,
  message text
) on commit drop;

insert into public.tenants (id, shop_name)
values
  ('97000000-0000-4000-8000-000000000001', 'Online Lifecycle Tenant'),
  ('97000000-0000-4000-8000-000000000002', 'Online Lifecycle Other');

-- These lifecycle scenarios predate paid shipping and intentionally assert
-- item-only totals. Explicit zero-cost tiers preserve those totals while still
-- exercising the authoritative shipping-quote path for both tenants.
insert into public.online_shipping_rate_tiers (
  tenant_id,
  country_code,
  min_order_gross,
  max_order_gross,
  shipping_gross,
  tax_rate,
  estimated_min_business_days,
  estimated_max_business_days
) values
  (
    '97000000-0000-4000-8000-000000000001',
    'CL', 0, null, 0, 0, 0, 0
  ),
  (
    '97000000-0000-4000-8000-000000000002',
    'CL', 0, null, 0, 0, 0, 0
  );

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '97000000-0000-4000-8000-000000000099',
    'authenticated', 'authenticated', 'online-lifecycle@example.invalid', '',
    now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '97000000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '97000000-0000-4000-8000-000000000098',
    'authenticated', 'authenticated', 'online-lifecycle-other@example.invalid', '',
    now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '97000000-0000-4000-8000-000000000002'),
    now(), now()
  );

-- Production-derived clones do not guarantee an auth.users bootstrap trigger.
-- Make staff tenancy explicit so this test exercises lifecycle/RLS behavior,
-- not an environment-specific fixture side effect.
delete from public.user_profiles where user_id in (
  '97000000-0000-4000-8000-000000000099',
  '97000000-0000-4000-8000-000000000098'
);
insert into public.user_profiles(
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values
  (
    '97000000-0000-4000-8000-000000000099',
    '97000000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true
  ),
  (
    '97000000-0000-4000-8000-000000000098',
    '97000000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '97000000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000099',
  true
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values
  (
    '97000000-0000-4000-8000-000000000010',
    '97000000-0000-4000-8000-000000000001',
    'Canonical online product', 'ONLINE-CANONICAL-001', 1190, 990, 400, 19,
    'product', false, 'inventory', true, 10, 10, 0, 100,
    true, true, true
  ),
  (
    '97000000-0000-4000-8000-000000000011',
    '97000000-0000-4000-8000-000000000001',
    'Drifted stock product', 'ONLINE-DRIFT-001', 500, 500, 200, 19,
    'product', false, 'inventory', true, 5, 0, 0, 100,
    true, true, true
  ),
  (
    '97000000-0000-4000-8000-000000000012',
    '97000000-0000-4000-8000-000000000002',
    'Foreign tenant product', 'FOREIGN-TENANT-SKU', 750, 700, 300, 19,
    'product', false, 'inventory', true, 7, 7, 0, 100,
    true, true, true
  );

insert into online_lifecycle_ids
select 'mp_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '97000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-lifecycle-mp-001',
    'customer_email', 'mp@example.invalid',
    'customer_name', 'Mercado Pago Customer',
    'customer_address', 'Lifecycle 100',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Lifecycle 100',
    'payment_method', 'mercadopago',
    'total', 999999
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '97000000-0000-4000-8000-000000000010',
    'quantity', 1,
    'unit_price', 999999
  ))
);

select is(
  (select total from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'mp_order')),
  990::numeric,
  'checkout uses website_price before the base product price'
);

select is(
  (select unit_price from public.online_order_items
    where order_id = (select id from online_lifecycle_ids where name = 'mp_order')),
  990::numeric,
  'server-owned online line price ignores the client payload'
);

select is(
  (select unit_cost from public.online_order_items
    where order_id = (select id from online_lifecycle_ids where name = 'mp_order')),
  400::numeric,
  'checkout snapshots the prospective unit cost'
);

select is(
  (select tax_rate from public.online_order_items
    where order_id = (select id from online_lifecycle_ids where name = 'mp_order')),
  19::numeric,
  'checkout snapshots the product tax rate'
);

select is(
  (select concat_ws('|', is_service::text, purchase_treatment, product_type)
     from public.online_order_items
    where order_id = (select id from online_lifecycle_ids where name = 'mp_order')),
  'false|inventory|product',
  'checkout snapshots product/service and inventory classification'
);

select is(
  (select count(*)::integer from public.online_order_events
    where order_id = (select id from online_lifecycle_ids where name = 'mp_order')
      and event_type = 'order_created'),
  1,
  'checkout appends one durable creation receipt'
);

select is(
  (select (response_snapshot->>'total')::numeric
     from public.online_order_events
    where order_id = (select id from online_lifecycle_ids where name = 'mp_order')
      and event_type = 'order_created'),
  990::numeric,
  'creation receipt stores the trusted server total'
);

select ok(
  (select order_number ~ ('^WEB-' || to_char(current_date, 'YY') || '-[0-9]{5}$')
     from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'mp_order')),
  'checkout assigns the canonical tenant/year WEB number'
);

select is(
  (
    select count(*)::integer
      from public.get_public_products(
        '97000000-0000-4000-8000-000000000001',
        null, array['97000000-0000-4000-8000-000000000011'::uuid],
        null, null, null, true, 'name', 20, 0
      )
  ),
  0,
  'public availability trusts stock_quantity and does not take the larger legacy balance'
);

select throws_ok(
  $$
    select public.create_public_online_order(
      jsonb_build_object(
        'tenant_id', '97000000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'online-lifecycle-drift-001',
        'customer_email', 'drift@example.invalid',
        'customer_name', 'Drift Customer',
        'customer_address', 'Lifecycle 101',
        'delivery_type', 'shipping',
        'shipping_address_line1', 'Lifecycle 101',
        'payment_method', 'mercadopago'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '97000000-0000-4000-8000-000000000011',
        'quantity', 1
      ))
    )
  $$,
  'P0001',
  'Product stock columns disagree; checkout blocked for Drifted stock product',
  'checkout fails closed when canonical and legacy stock columns disagree'
);

insert into online_lifecycle_ids
select 'mp_order_2', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '97000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-lifecycle-mp-002',
    'customer_email', 'mp2@example.invalid',
    'customer_name', 'Second Customer',
    'customer_address', 'Lifecycle 102',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Lifecycle 102',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '97000000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  (
    select substring(second_order.order_number from '[0-9]+$')::integer
         - substring(first_order.order_number from '[0-9]+$')::integer
      from public.online_orders first_order
      join public.online_orders second_order
        on second_order.id = (select id from online_lifecycle_ids where name = 'mp_order_2')
     where first_order.id = (select id from online_lifecycle_ids where name = 'mp_order')
  ),
  1,
  'same-tenant order numbers advance exactly once'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into online_lifecycle_ids
select 'other_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '97000000-0000-4000-8000-000000000002',
    'checkout_idempotency_key', 'online-lifecycle-other-001',
    'customer_email', 'other@example.invalid',
    'customer_name', 'Other Tenant Customer',
    'customer_address', 'Other 1',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Other 1',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '97000000-0000-4000-8000-000000000012',
    'quantity', 1
  ))
);

select is(
  (select substring(order_number from '[0-9]+$')::integer
     from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'other_order')),
  1,
  'order numbering is independent per tenant and year'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '97000000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000099',
  true
);

insert into online_lifecycle_ids
select 'transfer_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '97000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'online-lifecycle-transfer-001',
    'customer_email', 'transfer@example.invalid',
    'customer_name', 'Transfer Customer',
    'customer_address', 'Lifecycle 103',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Lifecycle 103',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '97000000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  (select status || '|' || payment_status
     from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'confirmed|pending',
  'transfer checkout creates an operational order awaiting verified payment'
);

select is(
  (
    select concat_ws(
      '|',
      invoice.items->0->>'price',
      invoice.items->0->>'cost',
      invoice.items->0->>'tax_rate',
      invoice.items->0->>'is_service',
      invoice.items->0->>'purchase_treatment'
    )
      from public.online_orders orders
      join public.sales_invoices invoice
        on invoice.id = orders.sales_invoice_id
       and invoice.tenant_id = orders.tenant_id
     where orders.id = (select id from online_lifecycle_ids where name = 'transfer_order')
  ),
  '990.00|400.00|19.00|false|inventory',
  'generated invoice carries price/cost/tax/service snapshots prospectively'
);

select ok(
  (
    select created.occurred_at <= transitioned.occurred_at
      from public.online_order_events created
      join public.online_order_events transitioned
        on transitioned.order_id = created.order_id
       and transitioned.tenant_id = created.tenant_id
     where created.order_id = (select id from online_lifecycle_ids where name = 'transfer_order')
       and created.event_type = 'order_created'
       and transitioned.event_type = 'status_transition'
  ),
  'creation receipt precedes automatic checkout status processing'
);

insert into online_lifecycle_ids
select 'transfer_payment', public.confirm_online_order_payment(
  (select id from online_lifecycle_ids where name = 'transfer_order'),
  'BANK-LIFECYCLE-001',
  clock_timestamp()
);

select ok(
  (select id is not null from online_lifecycle_ids where name = 'transfer_payment'),
  'manual transfer confirmation returns the durable payment identity'
);

select is(
  (select count(*)::integer from public.online_order_events
    where order_id = (select id from online_lifecycle_ids where name = 'transfer_order')
      and event_type = 'payment_transition'
      and from_payment_status = 'pending'
      and to_payment_status = 'paid'),
  1,
  'payment confirmation appends one payment-transition receipt'
);

select is(
  (select actor_id from public.online_order_events
    where order_id = (select id from online_lifecycle_ids where name = 'transfer_order')
      and event_type = 'payment_transition'
      and to_payment_status = 'paid'),
  '97000000-0000-4000-8000-000000000099'::uuid,
  'payment receipt preserves the authenticated actor'
);

select is(
  (
    select invoice.status || '|' || invoice.balance::text
      from public.online_orders orders
      join public.sales_invoices invoice
        on invoice.id = orders.sales_invoice_id
       and invoice.tenant_id = orders.tenant_id
     where orders.id = (select id from online_lifecycle_ids where name = 'transfer_order')
  ),
  'paid|0.00',
  'manual confirmation fully settles the linked invoice'
);

select is(
  (select stock_quantity from public.products
    where id = '97000000-0000-4000-8000-000000000010'),
  9,
  'verified transfer payment consumes canonical stock exactly once'
);

insert into online_lifecycle_values
select 'processing_expected_version', version::text
  from public.online_orders
 where id = (select id from online_lifecycle_ids where name = 'transfer_order');

insert into online_lifecycle_values
select 'processing_response', public.transition_online_order_status(
  (select id from online_lifecycle_ids where name = 'transfer_order'),
  'processing',
  (select value::bigint from online_lifecycle_values where name = 'processing_expected_version'),
  'online-lifecycle-processing-001'
)::text;

select is(
  (select (value::jsonb)->>'status' from online_lifecycle_values
    where name = 'processing_response'),
  'processing',
  'canonical command advances confirmed orders to processing'
);

select ok(
  (
    select orders.status = 'processing'
       and orders.version > expected.value::bigint
      from public.online_orders orders
      cross join online_lifecycle_values expected
     where orders.id = (select id from online_lifecycle_ids where name = 'transfer_order')
       and expected.name = 'processing_expected_version'
  ),
  'successful transition updates status and optimistic version'
);

select is(
  (select actor_id from public.online_order_events
    where operation_key = 'online-lifecycle-processing-001'),
  '97000000-0000-4000-8000-000000000099'::uuid,
  'status receipt preserves the authenticated actor'
);

insert into online_lifecycle_values
select 'processing_replay', public.transition_online_order_status(
  (select id from online_lifecycle_ids where name = 'transfer_order'),
  'processing',
  (select value::bigint from online_lifecycle_values where name = 'processing_expected_version'),
  'online-lifecycle-processing-001'
)::text;

select is(
  (select (value::jsonb)->>'replay' from online_lifecycle_values
    where name = 'processing_replay'),
  'true',
  'same operation key and request replay the committed receipt'
);

select is(
  (select count(*)::integer from public.online_order_events
    where operation_key = 'online-lifecycle-processing-001'),
  1,
  'status replay never duplicates the event receipt'
);

select is(
  (select version::text from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  (select result_version::text from public.online_order_events
    where operation_key = 'online-lifecycle-processing-001'),
  'status replay does not advance the order version again'
);

do $$
begin
  perform public.transition_online_order_status(
    (select id from online_lifecycle_ids where name = 'transfer_order'),
    'shipped',
    (select value::bigint from online_lifecycle_values where name = 'processing_expected_version'),
    'online-lifecycle-stale-001',
    'TRACK-STALE'
  );
  insert into online_lifecycle_results values ('stale', false, 'unexpected success');
exception when sqlstate '40001' then
  insert into online_lifecycle_results values ('stale', true, sqlerrm);
when others then
  insert into online_lifecycle_results values ('stale', false, sqlstate || ': ' || sqlerrm);
end $$;

select ok(
  (select passed from online_lifecycle_results where name = 'stale'),
  'stale expected_version is rejected before applying a transition'
);

do $$
begin
  perform public.transition_online_order_status(
    (select id from online_lifecycle_ids where name = 'transfer_order'),
    'pending',
    (select version from public.online_orders
      where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
    'online-lifecycle-backwards-001'
  );
  insert into online_lifecycle_results values ('backwards', false, 'unexpected success');
exception when check_violation then
  insert into online_lifecycle_results values ('backwards', true, sqlerrm);
when others then
  insert into online_lifecycle_results values ('backwards', false, sqlstate || ': ' || sqlerrm);
end $$;

select ok(
  (select passed from online_lifecycle_results where name = 'backwards'),
  'backwards and skipped lifecycle states are rejected'
);

do $$
begin
  perform public.transition_online_order_status(
    (select id from online_lifecycle_ids where name = 'transfer_order'),
    'shipped',
    (select version from public.online_orders
      where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
    'online-lifecycle-no-tracking-001'
  );
  insert into online_lifecycle_results values ('tracking', false, 'unexpected success');
exception when check_violation then
  insert into online_lifecycle_results values ('tracking', true, sqlerrm);
when others then
  insert into online_lifecycle_results values ('tracking', false, sqlstate || ': ' || sqlerrm);
end $$;

select ok(
  (select passed from online_lifecycle_results where name = 'tracking'),
  'shipping requires tracking or carrier evidence'
);

insert into online_lifecycle_values
select 'shipped_response', public.transition_online_order_status(
  (select id from online_lifecycle_ids where name = 'transfer_order'),
  'shipped',
  (select version from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'online-lifecycle-shipped-001',
  'TRACK-LIFECYCLE-001',
  'https://carrier.example.invalid/TRACK-LIFECYCLE-001',
  'Test Carrier'
)::text;

select is(
  (select (value::jsonb)->>'status' from online_lifecycle_values
    where name = 'shipped_response'),
  'shipped',
  'valid shipping evidence advances a processing order'
);

select ok(
  (select shipped_at is not null
       and tracking_number = 'TRACK-LIFECYCLE-001'
       and shipping_carrier = 'Test Carrier'
     from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'shipping milestone stores server timestamp and supplied evidence'
);

insert into online_lifecycle_values
select 'delivered_response', public.transition_online_order_status(
  (select id from online_lifecycle_ids where name = 'transfer_order'),
  'delivered',
  (select version from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'online-lifecycle-delivered-001'
)::text;

select is(
  (select (value::jsonb)->>'status' from online_lifecycle_values
    where name = 'delivered_response'),
  'delivered',
  'shipped order can advance to delivered'
);

select ok(
  (select delivered_at is not null
     from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'delivery stores its server-owned milestone timestamp'
);

insert into online_lifecycle_values
select 'note_response', public.update_online_order_internal_notes(
  (select id from online_lifecycle_ids where name = 'transfer_order'),
  'Revisado por operaciones',
  (select version from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'online-lifecycle-note-001'
)::text;

select is(
  (select (value::jsonb)->>'changed' from online_lifecycle_values
    where name = 'note_response'),
  'true',
  'narrow note command reports a real change'
);

select ok(
  (select internal_notes = 'Revisado por operaciones'
       and updated_by = '97000000-0000-4000-8000-000000000099'::uuid
     from public.online_orders
    where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
  'note command stores the note and actor without opening general UPDATE'
);

select is(
  (select event_type from public.online_order_events
    where operation_key = 'online-lifecycle-note-001'),
  'internal_note_updated',
  'note command appends an explicit immutable receipt'
);

select is(
  (
    select (public.update_online_order_internal_notes(
      (select id from online_lifecycle_ids where name = 'transfer_order'),
      'Revisado por operaciones',
      (select expected_version from public.online_order_events
        where operation_key = 'online-lifecycle-note-001'),
      'online-lifecycle-note-001'
    )->>'replay')
  ),
  'true',
  'note command replays the original receipt safely'
);

select is(
  (select count(*)::integer from public.online_order_events
    where operation_key = 'online-lifecycle-note-001'),
  1,
  'note replay does not duplicate its event'
);

do $$
begin
  update public.online_order_events
     set response_snapshot = response_snapshot || '{"tampered":true}'::jsonb
   where operation_key = 'online-lifecycle-note-001';
  insert into online_lifecycle_results values ('immutable', false, 'unexpected success');
exception when object_not_in_prerequisite_state then
  insert into online_lifecycle_results values ('immutable', true, sqlerrm);
when others then
  insert into online_lifecycle_results values ('immutable', false, sqlstate || ': ' || sqlerrm);
end $$;

select ok(
  (select passed from online_lifecycle_results where name = 'immutable'),
  'online order event receipts are append-only even for privileged callers'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '97000000-0000-4000-8000-000000000098',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000098',
  true
);

do $$
begin
  perform public.transition_online_order_status(
    (select id from online_lifecycle_ids where name = 'transfer_order'),
    'delivered',
    (select version from public.online_orders
      where id = (select id from online_lifecycle_ids where name = 'transfer_order')),
    'online-lifecycle-cross-tenant-001'
  );
  insert into online_lifecycle_results values ('cross_tenant', false, 'unexpected success');
exception when insufficient_privilege then
  insert into online_lifecycle_results values ('cross_tenant', true, sqlerrm);
when others then
  insert into online_lifecycle_results values ('cross_tenant', false, sqlstate || ': ' || sqlerrm);
end $$;

select ok(
  (select passed from online_lifecycle_results where name = 'cross_tenant'),
  'canonical lifecycle command cannot cross tenant boundaries'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '97000000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '97000000-0000-4000-8000-000000000099',
  true
);

select ok(
  not has_table_privilege('authenticated', 'public.online_orders', 'INSERT'),
  'authenticated cannot insert online orders outside canonical checkout'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_orders', 'UPDATE'),
  'authenticated cannot directly update protected online-order fields'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_order_items', 'INSERT'),
  'authenticated cannot append order items outside a future correction command'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_order_items', 'UPDATE'),
  'authenticated cannot directly rewrite immutable order item snapshots'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_order_items', 'DELETE'),
  'authenticated cannot directly delete online-order item evidence'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_order_events', 'UPDATE'),
  'authenticated cannot update lifecycle receipts'
);
select ok(
  not has_table_privilege('authenticated', 'public.online_order_events', 'DELETE'),
  'authenticated cannot delete lifecycle receipts'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.transition_online_order_status(uuid,text,bigint,text,text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated can execute the canonical lifecycle command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.update_online_order_internal_notes(uuid,text,bigint,text)',
    'EXECUTE'
  ),
  'authenticated retains only the narrow internal-note mutation command'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.cancel_online_order(uuid,text,numeric)',
    'EXECUTE'
  ),
  'authenticated cannot bypass optimistic lifecycle through the cancellation kernel'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.cancel_online_order(uuid,text,numeric)',
    'EXECUTE'
  ),
  'service-role integrations retain the audited cancellation kernel'
);

select ok(
  pg_get_functiondef(
    'public.generate_online_order_number(uuid,timestamp with time zone)'::regprocedure
  ) like '%pg_advisory_xact_lock%tenant_id%',
  'order-number allocator serializes the tenant/year namespace'
);

select ok(
  pg_get_functiondef(
    'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure
  ) like '%coalesce(product.website_price, product.price)%'
  and pg_get_functiondef(
    'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure
  ) like '%stock columns disagree; checkout blocked%',
  'unkeyed checkout definition contains canonical price and fail-closed stock contracts'
);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  items, source
)
values (
  '97000000-0000-4000-8000-000000000050',
  '97000000-0000-4000-8000-000000000001',
  'FV-ONLINE-FOREIGN-SKU', 'Foreign SKU Probe', 'draft',
  700, 700, 0, 700, 0, 700,
  jsonb_build_array(jsonb_build_object(
    'product_sku', 'FOREIGN-TENANT-SKU',
    'product_name', 'Should not resolve across tenant',
    'quantity', 1,
    'price', 700,
    'cost', 300,
    'is_service', false,
    'purchase_treatment', 'inventory'
  )),
  'ecommerce'
);

do $$
begin
  update public.sales_invoices
     set status = 'confirmed'
   where id = '97000000-0000-4000-8000-000000000050';
  insert into online_lifecycle_results values ('foreign_sku', false, 'unexpected success');
exception when insufficient_privilege then
  insert into online_lifecycle_results values ('foreign_sku', true, sqlerrm);
when others then
  insert into online_lifecycle_results values ('foreign_sku', false, sqlstate || ': ' || sqlerrm);
end $$;

select ok(
  (select passed from online_lifecycle_results where name = 'foreign_sku'),
  'invoice inventory fallback refuses a SKU belonging to another tenant'
);

select is(
  (select stock_quantity from public.products
    where id = '97000000-0000-4000-8000-000000000012'),
  7,
  'failed cross-tenant SKU resolution cannot mutate foreign stock'
);

select is(
  (select data_type from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_channel_payment_events'
      and column_name = 'provider_payload'),
  'jsonb',
  'provider event evidence can retain richer sanitized Mercado Pago fields'
);

select ok(
  has_table_privilege('authenticated', 'public.online_order_events', 'SELECT'),
  'authenticated operators can read tenant-scoped lifecycle receipts'
);

select * from finish();

rollback;
