begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- A production-derived schema-only restore recreates public without restoring
-- Supabase object ACLs. Normalize the production grants inside this rolled-back
-- test before asserting them or switching roles.
grant usage on schema public to authenticated;
revoke all on function public.renew_online_order_inventory_reservations(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.renew_online_order_inventory_reservations(uuid)
  to service_role;
revoke all on public.online_order_inventory_reservations
  from public, anon, authenticated, service_role;
grant select on public.online_order_inventory_reservations to authenticated;

select has_table(
  'public',
  'online_order_inventory_reservations',
  'online inventory has a current reservation projection'
);
select has_table(
  'public',
  'online_order_inventory_reservation_events',
  'online inventory has an append-only lifecycle ledger'
);
select has_view(
  'public',
  'online_inventory_availability_view',
  'staff has an auditable physical/reserved/available projection'
);
select has_function(
  'public',
  'get_online_order_inventory_reservation_deadline',
  array['uuid'],
  'payment providers have a narrow reservation deadline RPC'
);
select has_function(
  'public',
  'get_product_available_quantities',
  array['uuid', 'uuid[]'],
  'modern clients have a stable reservation-aware availability projection'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_product_available_quantities(uuid,uuid[])',
    'EXECUTE'
  ),
  'authenticated ERP clients can read tenant availability'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.get_product_available_quantities(uuid,uuid[])',
    'EXECUTE'
  ),
  'service integrations can read tenant availability'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_product_available_quantities(uuid,uuid[])',
    'EXECUTE'
  ),
  'anonymous callers cannot use the internal availability projection'
);
select is(
  (select function_row.provolatile::text
   from pg_proc function_row
   where function_row.oid =
     'public.get_product_available_quantities(uuid,uuid[])'::regprocedure),
  's',
  'availability projection is declared stable'
);
select ok(
  (select function_row.prosecdef
   from pg_proc function_row
   where function_row.oid =
     'public.get_product_available_quantities(uuid,uuid[])'::regprocedure),
  'availability projection enforces tenant scope behind a security-definer boundary'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.renew_online_order_inventory_reservations(uuid)',
    'EXECUTE'
  ),
  'service role can atomically renew a payment reservation'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.renew_online_order_inventory_reservations(uuid)',
    'EXECUTE'
  ),
  'staff cannot silently extend payment reservation windows'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.online_order_inventory_reservations',
    'SELECT'
  ),
  'staff can inspect tenant reservation state'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.online_order_inventory_reservations',
    'INSERT'
  ),
  'staff cannot forge reservations directly'
);
select ok(
  not has_table_privilege(
    'service_role',
    'public.online_order_inventory_reservation_events',
    'UPDATE'
  ),
  'service role cannot rewrite reservation evidence'
);

insert into public.tenants (id, shop_name, currency, timezone)
values
  (
    '9d290000-0000-4000-8000-000000000001',
    'Online Inventory Reservation Test',
    'CLP',
    'America/Santiago'
  ),
  (
    '9d290000-0000-4000-8000-000000000002',
    'Online Inventory Reservation Other',
    'CLP',
    'America/Santiago'
  );

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '9d290000-0000-4000-8000-000000000099',
    'authenticated', 'authenticated', 'inventory-reservation@example.invalid',
    '', now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '9d290000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9d290000-0000-4000-8000-000000000098',
    'authenticated', 'authenticated', 'inventory-reservation-other@example.invalid',
    '', now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '9d290000-0000-4000-8000-000000000002'),
    now(), now()
  );

delete from public.user_profiles where user_id in (
  '9d290000-0000-4000-8000-000000000099',
  '9d290000-0000-4000-8000-000000000098'
);
insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values
  (
    '9d290000-0000-4000-8000-000000000099',
    '9d290000-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    '9d290000-0000-4000-8000-000000000098',
    '9d290000-0000-4000-8000-000000000002',
    'admin', '{}'::jsonb, true
  );

select is(
  public.online_order_inventory_reservation_ttl(
    '9d290000-0000-4000-8000-000000000001',
    'mercadopago'
  ),
  interval '30 minutes',
  'Mercado Pago reservations default to a short 30-minute window'
);
select is(
  public.online_order_inventory_reservation_ttl(
    '9d290000-0000-4000-8000-000000000001',
    'transfer'
  ),
  interval '24 hours',
  'transfer reservations default to one operational day'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9d290000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9d290000-0000-4000-8000-000000000099',
  true
);

select set_config('app.product_set_composition_writer', 'migration', true);
insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, is_set
)
values
  (
    '9d290000-0000-4000-8000-000000000010',
    '9d290000-0000-4000-8000-000000000001',
    'Reserved tracked product', 'RESERVE-TRACKED-001',
    1000, 1000, 400, 19, 'product', false, 'inventory', true,
    2, 2, 0, 100, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000011',
    '9d290000-0000-4000-8000-000000000001',
    'Manual transfer product', 'RESERVE-TRANSFER-001',
    1000, 1000, 400, 19, 'product', false, 'inventory', true,
    3, 3, 0, 100, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000012',
    '9d290000-0000-4000-8000-000000000001',
    'Expiring reservation product', 'RESERVE-EXPIRY-001',
    1000, 1000, 400, 19, 'product', false, 'inventory', true,
    1, 1, 0, 100, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000013',
    '9d290000-0000-4000-8000-000000000001',
    'Service without physical stock', 'RESERVE-SERVICE-001',
    1000, 1000, 0, 19, 'service', true, 'expense', false,
    0, 0, 0, 0, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000014',
    '9d290000-0000-4000-8000-000000000001',
    'Non tracked product', 'RESERVE-NONTRACK-001',
    1000, 1000, 400, 19, 'product', false, 'expense', false,
    0, 0, 0, 0, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000015',
    '9d290000-0000-4000-8000-000000000001',
    'Reservation set', 'RESERVE-SET-001',
    5000, 5000, 1800, 19, 'product', false, 'inventory', true,
    0, 0, 0, 100, true, true, true, true
  ),
  (
    '9d290000-0000-4000-8000-000000000016',
    '9d290000-0000-4000-8000-000000000001',
    'Set component one', 'RESERVE-COMPONENT-001',
    1000, 1000, 400, 19, 'product', false, 'inventory', true,
    4, 4, 0, 100, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000017',
    '9d290000-0000-4000-8000-000000000001',
    'Set component two', 'RESERVE-COMPONENT-002',
    1000, 1000, 400, 19, 'product', false, 'inventory', true,
    2, 2, 0, 100, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000018',
    '9d290000-0000-4000-8000-000000000001',
    'Mercado Pago reserved product', 'RESERVE-MP-001',
    1190, 1190, 500, 19, 'product', false, 'inventory', true,
    1, 1, 0, 100, true, true, true, false
  ),
  (
    '9d290000-0000-4000-8000-000000000019',
    '9d290000-0000-4000-8000-000000000001',
    'Broken reservation set', 'RESERVE-BROKEN-SET',
    5000, 5000, 1800, 19, 'product', false, 'inventory', true,
    0, 0, 0, 100, true, true, true, true
  );

select set_config('app.product_set_composition_writer', 'migration', true);
update public.products
set parent_set_id = '9d290000-0000-4000-8000-000000000015',
    component_label = case id
      when '9d290000-0000-4000-8000-000000000016'::uuid then 'Component one'
      else 'Component two'
    end,
    component_position = case id
      when '9d290000-0000-4000-8000-000000000016'::uuid then 1
      else 2
    end
where id in (
  '9d290000-0000-4000-8000-000000000016'::uuid,
  '9d290000-0000-4000-8000-000000000017'::uuid
);
insert into public.product_set_components (
  tenant_id, set_product_id, component_product_id,
  component_label, component_position, quantity_in_set
)
values
  (
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000015',
    '9d290000-0000-4000-8000-000000000016',
    'Component one', 1, 2
  ),
  (
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000015',
    '9d290000-0000-4000-8000-000000000017',
    'Component two', 2, 1
  );
select set_config('app.product_set_composition_writer', '', true);

select throws_ok(
  $$select * from public.get_product_available_quantities(
    '9d290000-0000-4000-8000-000000000001',
    array['9d290000-0000-4000-8000-000000000019'::uuid]
  )$$,
  '23514',
  'Set product RESERVE-BROKEN-SET has no canonical components',
  'availability projection fails closed for a set without a canonical map'
);
select throws_ok(
  $$select * from public.get_product_available_quantities(
    '9d290000-0000-4000-8000-000000000002',
    array['9d290000-0000-4000-8000-000000000019'::uuid]
  )$$,
  '42501',
  'Tenant availability access denied',
  'availability projection cannot cross the authenticated tenant boundary'
);

create temp table online_inventory_test_ids (
  name text primary key,
  id uuid not null
) on commit drop;

insert into online_inventory_test_ids
select 'tracked_order_1', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-tracked-001',
    'customer_email', 'tracked-one@example.invalid',
    'customer_name', 'Tracked One',
    'customer_address', 'Test 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  (select stock_quantity from public.products
    where id = '9d290000-0000-4000-8000-000000000010'),
  2,
  'checkout commits availability without changing physical stock'
);
select is(
  (select quantity from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'tracked_order_1'
    ) and state = 'active'),
  1,
  'checkout creates an active whole-unit commitment'
);
select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000010'
  ),
  1,
  'availability subtracts the committed unit from physical stock'
);
select is(
  (
    select available_quantity
    from public.get_product_available_quantities(
      '9d290000-0000-4000-8000-000000000001',
      array['9d290000-0000-4000-8000-000000000010'::uuid]
    )
  ),
  1,
  'stable availability projection returns ordinary stock after reservations'
);
select is(
  (
    select stock_quantity
      from public.get_public_products(
        '9d290000-0000-4000-8000-000000000001',
        null,
        array['9d290000-0000-4000-8000-000000000010'::uuid],
        null, null, null, true, 'name', 20, 0
      )
  ),
  1,
  'public catalog exposes available, not merely physical, quantity'
);
select is(
  public.create_public_online_order(
    jsonb_build_object(
      'tenant_id', '9d290000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', 'reservation-tracked-001',
      'customer_email', 'tracked-one@example.invalid',
      'customer_name', 'Tracked One',
      'customer_address', 'Test 1',
      'delivery_type', 'pickup',
      'payment_method', 'mercadopago'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '9d290000-0000-4000-8000-000000000010',
      'quantity', 1
    ))
  ),
  (select id from online_inventory_test_ids where name = 'tracked_order_1'),
  'lost checkout acknowledgement replays the original order'
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'tracked_order_1'
    )),
  1,
  'checkout replay does not duplicate the reservation'
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservation_events
    where order_id = (
      select id from online_inventory_test_ids where name = 'tracked_order_1'
    ) and event_type = 'reserved'),
  1,
  'checkout replay does not duplicate reservation evidence'
);

insert into online_inventory_test_ids
select 'tracked_order_2', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-tracked-002',
    'customer_email', 'tracked-two@example.invalid',
    'customer_name', 'Tracked Two',
    'customer_address', 'Test 2',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000010'
  ),
  0,
  'two committed units exhaust online availability'
);
select is(
  (
    select count(*)::integer
      from public.get_public_products(
        '9d290000-0000-4000-8000-000000000001',
        null,
        array['9d290000-0000-4000-8000-000000000010'::uuid],
        null, null, null, true, 'name', 20, 0
      )
  ),
  0,
  'available-only catalog hides a fully committed product'
);
select throws_ok(
  $$
    select public.create_public_online_order(
      jsonb_build_object(
        'tenant_id', '9d290000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'reservation-tracked-003',
        'customer_email', 'tracked-three@example.invalid',
        'customer_name', 'Tracked Three',
        'customer_address', 'Test 3',
        'delivery_type', 'pickup',
        'payment_method', 'mercadopago'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9d290000-0000-4000-8000-000000000010',
        'quantity', 1
      ))
    )
  $$,
  '23514',
  'Insufficient available stock for product Reserved tracked product',
  'a third concurrent checkout cannot oversell the last units'
);
select is(
  (select count(*)::integer
     from public.online_orders
    where tenant_id = '9d290000-0000-4000-8000-000000000001'
      and checkout_idempotency_key = 'reservation-tracked-003'),
  0,
  'failed availability rolls back order, item and reservation together'
);
select throws_ok(
  $$
    update public.products
       set stock_quantity = 0, inventory_qty = 0
     where id = '9d290000-0000-4000-8000-000000000010'
  $$,
  '23514',
  'Stock update would consume 2 units reserved for online orders; available floor is 2',
  'POS/manual stock paths cannot consume units committed online'
);

update public.online_orders
   set status = 'cancelled',
       cancelled_reason = 'Synthetic cancellation two'
 where id = (select id from online_inventory_test_ids where name = 'tracked_order_2');
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'tracked_order_2'
    )),
  'released',
  'cancellation releases the exact second-order commitment'
);
select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000010'
  ),
  1,
  'released units immediately return to catalog availability'
);
update public.online_orders
   set status = 'cancelled',
       cancelled_reason = 'Synthetic cancellation one'
 where id = (select id from online_inventory_test_ids where name = 'tracked_order_1');
select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000010'
  ),
  2,
  'all released units restore the full physical quantity'
);

insert into online_inventory_test_ids
select 'service_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-service-001',
    'customer_email', 'service@example.invalid',
    'customer_name', 'Service Customer',
    'customer_address', 'Service 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000013',
    'quantity', 1
  ))
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'service_order'
    )),
  0,
  'services never invent physical stock reservations'
);

insert into online_inventory_test_ids
select 'nontracked_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-nontracked-001',
    'customer_email', 'nontracked@example.invalid',
    'customer_name', 'Nontracked Customer',
    'customer_address', 'Nontracked 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000014',
    'quantity', 1
  ))
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'nontracked_order'
    )),
  0,
  'track_stock false products never invent physical stock reservations'
);

select is(
  (
    select stock_quantity
    from public.get_public_products(
      '9d290000-0000-4000-8000-000000000001',
      null,
      array['9d290000-0000-4000-8000-000000000015'::uuid],
      null, null, null, true, 'name', 20, 0
    )
  ),
  2,
  'available-only catalog includes a virtual set using component availability'
);
select is(
  (
    select available_quantity
    from public.get_product_available_quantities(
      '9d290000-0000-4000-8000-000000000001',
      array['9d290000-0000-4000-8000-000000000015'::uuid]
    )
  ),
  2,
  'stable availability projection derives complete sets from components'
);

insert into online_inventory_test_ids
select 'set_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-set-001',
    'customer_email', 'set@example.invalid',
    'customer_name', 'Set Customer',
    'customer_address', 'Set 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000015',
    'quantity', 1
  ))
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'set_order'
    ) and state = 'active'),
  2,
  'a set reserves its two physical component rows'
);
select results_eq(
  $$
    select product_id, quantity
      from public.online_order_inventory_reservations
     where order_id = (
       select id from online_inventory_test_ids where name = 'set_order'
     )
     order by product_id
  $$,
  $$
    values
      ('9d290000-0000-4000-8000-000000000016'::uuid, 2),
      ('9d290000-0000-4000-8000-000000000017'::uuid, 1)
  $$,
  'set reservation quantities are expanded from the immutable recipe'
);
select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000015'
  ),
  1,
  'set availability is the minimum remaining component bundle'
);
select is(
  (
    select stock_quantity
    from public.get_public_products(
      '9d290000-0000-4000-8000-000000000001',
      null,
      array['9d290000-0000-4000-8000-000000000015'::uuid],
      null, null, null, true, 'name', 20, 0
    )
  ),
  1,
  'public set quantity follows remaining component bundles after reservation'
);
select is(
  (
    select available_quantity
    from public.get_product_available_quantities(
      '9d290000-0000-4000-8000-000000000001',
      array['9d290000-0000-4000-8000-000000000015'::uuid]
    )
  ),
  1,
  'stable set availability follows component reservations'
);
select throws_ok(
  $$
    update public.product_set_components
       set quantity_in_set = 3
     where set_product_id = '9d290000-0000-4000-8000-000000000015'
       and component_position = 1
  $$,
  '42501',
  'Product set composition must be changed through save_product_set_aggregate',
  'canonical set recipes cannot be edited directly while reservations exist'
);
select throws_ok(
  $$
    update public.products
       set stock_quantity = 1, inventory_qty = 1
     where id = '9d290000-0000-4000-8000-000000000016'
  $$,
  '23514',
  'Stock update would consume 2 units reserved for online orders; available floor is 2',
  'component stock cannot be reduced below a set commitment'
);
update public.online_orders
   set status = 'cancelled', cancelled_reason = 'Synthetic set cancellation'
 where id = (select id from online_inventory_test_ids where name = 'set_order');
select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000015'
  ),
  2,
  'set cancellation restores the component-derived bundle count'
);

insert into online_inventory_test_ids
select 'expiry_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-expiry-001',
    'customer_email', 'expiry@example.invalid',
    'customer_name', 'Expiry Customer',
    'customer_address', 'Expiry 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000012',
    'quantity', 1
  ))
);
update public.online_order_inventory_reservations
   set reserved_at = clock_timestamp() - interval '2 hours',
       expires_at = clock_timestamp() - interval '1 hour'
 where order_id = (
   select id from online_inventory_test_ids where name = 'expiry_order'
 );
select is(
  public.expire_online_order_inventory_reservations(
    '9d290000-0000-4000-8000-000000000001',
    100
  ),
  1,
  'expiry worker atomically terminalizes one overdue commitment'
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'expiry_order'
    )),
  'expired',
  'overdue reservation remains as terminal evidence'
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservation_events
    where order_id = (
      select id from online_inventory_test_ids where name = 'expiry_order'
    ) and event_type = 'expired'),
  1,
  'expiry appends exactly one immutable event'
);
select is(
  public.online_product_available_quantity(
    '9d290000-0000-4000-8000-000000000001',
    '9d290000-0000-4000-8000-000000000012'
  ),
  1,
  'expired units return to online availability without stock movement'
);

insert into online_inventory_test_ids
select 'expiry_order_2', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-expiry-002',
    'customer_email', 'expiry-two@example.invalid',
    'customer_name', 'Expiry Customer Two',
    'customer_address', 'Expiry 2',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000012',
    'quantity', 1
  ))
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'expiry_order_2'
    )),
  'active',
  'a later checkout can safely commit the expired unit'
);

create temp table renewal_before on commit drop as
select expires_at
  from public.online_order_inventory_reservations
 where order_id = (
   select id from online_inventory_test_ids where name = 'expiry_order_2'
 );

select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role')::text,
  true
);
select set_config('request.jwt.claim.sub', '', true);
select ok(
  public.renew_online_order_inventory_reservations(
    (select id from online_inventory_test_ids where name = 'expiry_order_2')
  ) > (select expires_at from renewal_before),
  'payment preference renewal advances the authoritative deadline'
);
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservation_events
    where order_id = (
      select id from online_inventory_test_ids where name = 'expiry_order_2'
    ) and event_type = 're_reserved'),
  1,
  'deadline renewal is retained as explicit evidence'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9d290000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9d290000-0000-4000-8000-000000000099',
  true
);
select throws_ok(
  format(
    $$select public.renew_online_order_inventory_reservations(%L::uuid)$$,
    (select id from online_inventory_test_ids where name = 'expiry_order_2')
  ),
  '42501',
  'Reservation renewal is service-role only',
  'authenticated staff cannot bypass the payment-window policy'
);

insert into online_inventory_test_ids
select 'transfer_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-transfer-001',
    'customer_email', 'transfer@example.invalid',
    'customer_name', 'Transfer Customer',
    'customer_address', 'Transfer 1',
    'delivery_type', 'pickup',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000011',
    'quantity', 2
  ))
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'transfer_order'
    )),
  'active',
  'pending transfer retains an active commitment'
);
select is(
  (select invoice.status from public.sales_invoices invoice
    join public.online_orders orders on orders.sales_invoice_id = invoice.id
    where orders.id = (
      select id from online_inventory_test_ids where name = 'transfer_order'
    )),
  'sent',
  'pending transfer invoice remains non-posted'
);
select is(
  (select stock_quantity from public.products
    where id = '9d290000-0000-4000-8000-000000000011'),
  3,
  'pending transfer does not change physical stock'
);

insert into online_inventory_test_ids
select 'transfer_payment', public.confirm_online_order_payment(
  (select id from online_inventory_test_ids where name = 'transfer_order'),
  'RESERVATION-BANK-001',
  clock_timestamp()
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'transfer_order'
    )),
  'consumed',
  'payment atomically converts the commitment to consumed evidence'
);
select is(
  (select stock_quantity from public.products
    where id = '9d290000-0000-4000-8000-000000000011'),
  1,
  'transfer settlement consumes physical stock exactly once'
);
select ok(
  (select cardinality(stock_movement_ids) > 0
     from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'transfer_order'
    )),
  'consumed reservation retains its exact movement identities'
);
select results_eq(
  $$
    select event_type, count(*)::bigint
      from public.online_order_inventory_reservation_events
     where order_id = (
       select id from online_inventory_test_ids where name = 'transfer_order'
     ) and event_type in ('consumption_started', 'consumed')
     group by event_type
     order by event_type
  $$,
  $$
    values ('consumed'::text, 1::bigint),
           ('consumption_started'::text, 1::bigint)
  $$,
  'settlement leaves one start and one completion event'
);

create temp table transfer_counts_before_replay on commit drop as
select
  (select count(*) from public.stock_movements
    where tenant_id = '9d290000-0000-4000-8000-000000000001'
      and reference = 'sales_invoice:' || (
        select sales_invoice_id::text from public.online_orders
         where id = (
           select id from online_inventory_test_ids where name = 'transfer_order'
         )
      )) as movement_count,
  (select count(*) from public.online_order_inventory_reservation_events
    where order_id = (
      select id from online_inventory_test_ids where name = 'transfer_order'
    )) as event_count;
select is(
  public.confirm_online_order_payment(
    (select id from online_inventory_test_ids where name = 'transfer_order'),
    'RESERVATION-BANK-REPLAY',
    clock_timestamp()
  ),
  (select id from online_inventory_test_ids where name = 'transfer_payment'),
  'lost settlement acknowledgement returns the original payment'
);
select is(
  (select count(*) from public.stock_movements
    where tenant_id = '9d290000-0000-4000-8000-000000000001'
      and reference = 'sales_invoice:' || (
        select sales_invoice_id::text from public.online_orders
         where id = (
           select id from online_inventory_test_ids where name = 'transfer_order'
         )
      )),
  (select movement_count from transfer_counts_before_replay),
  'settlement replay creates no duplicate physical movement'
);
select is(
  (select count(*) from public.online_order_inventory_reservation_events
    where order_id = (
      select id from online_inventory_test_ids where name = 'transfer_order'
    )),
  (select event_count from transfer_counts_before_replay),
  'settlement replay creates no duplicate reservation event'
);

insert into online_inventory_test_ids
select 'mp_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9d290000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'reservation-mp-001',
    'customer_email', 'mp@example.invalid',
    'customer_name', 'MP Customer',
    'customer_address', 'MP 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9d290000-0000-4000-8000-000000000018',
    'quantity', 1
  ))
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'mp_order'
    )),
  'active',
  'Mercado Pago checkout commits the unit before provider settlement'
);
insert into online_inventory_test_ids
select 'mp_invoice', public.process_online_order(
  (select id from online_inventory_test_ids where name = 'mp_order')
);
select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select id from online_inventory_test_ids where name = 'mp_order'
    )),
  'consumed',
  'provider processing converts the exact reservation to consumption'
);
select is(
  (select stock_quantity from public.products
    where id = '9d290000-0000-4000-8000-000000000018'),
  0,
  'provider processing consumes the committed unit exactly once'
);
select is(
  (select coalesce(-sum(quantity), 0)::integer
     from public.stock_movements
    where tenant_id = '9d290000-0000-4000-8000-000000000001'
      and product_id = '9d290000-0000-4000-8000-000000000018'
      and reference = 'sales_invoice:' || (
        select id::text from online_inventory_test_ids where name = 'mp_invoice'
      )
      and quantity < 0),
  1,
  'provider invoice has one reconciled negative stock unit'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9d290000-0000-4000-8000-000000000098',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9d290000-0000-4000-8000-000000000098',
  true
);
-- The production ACL normalized at the start lets this exercise table RLS,
-- rather than failing first at schema/table privilege resolution.
set local role authenticated;
select is(
  (select count(*)::integer
     from public.online_order_inventory_reservations),
  0,
  'reservation projection is tenant-isolated under RLS'
);
reset role;
select throws_ok(
  format(
    $$select public.get_online_order_inventory_reservation_deadline(%L::uuid)$$,
    (select id from online_inventory_test_ids where name = 'expiry_order_2')
  ),
  '42501',
  'Order not found or access denied',
  'deadline RPC cannot cross tenant boundaries'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$
    update public.online_order_inventory_reservation_events
       set payload = payload || '{"forged":true}'::jsonb
     where tenant_id = '9d290000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'Online inventory reservation events are append-only',
  'even privileged maintenance cannot rewrite reservation evidence'
);

select * from finish();
rollback;
