begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_table(
  'public', 'workshop_inventory_commitments',
  'workshop assignments use a durable commitment ledger'
);
select has_table(
  'public', 'workshop_inventory_commitment_events',
  'workshop commitment transitions have append-only evidence'
);
select has_view(
  'public', 'active_inventory_commitments_v1',
  'online and workshop commitments share one active projection'
);
select has_view(
  'public', 'inventory_availability_v1',
  'staff can inspect on-hand, commitments and ATP separately'
);
select has_function(
  'public', 'assign_supply_need_from_stock_v1',
  array['uuid', 'bigint', 'text'],
  'stock assignment is an atomic command'
);
select has_function(
  'public', 'release_supply_need_stock_v1',
  array['uuid', 'bigint', 'text', 'text'],
  'stock release is an atomic command'
);
select has_function(
  'public', 'reject_supply_need_internal_stock_v1',
  array['uuid', 'bigint', 'text', 'text'],
  'rejecting assignable internal stock requires an audited command'
);
select has_function(
  'public', 'assistant_search_inventory_v7',
  array['text', 'text', 'text', 'jsonb', 'jsonb', 'text', 'text', 'integer', 'text'],
  'the AI inventory search reads the same common ATP authority'
);
select ok(
  position(
    'inventory_available_quantity_v1'
    in pg_get_functiondef(
      'public.online_product_available_quantity(uuid,uuid)'::regprocedure
    )
  ) > 0,
  'the established online availability signature delegates to common ATP'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.assign_supply_need_from_stock_v1(uuid,bigint,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.assign_supply_need_from_stock_v1(uuid,bigint,text)',
    'execute'
  ),
  'only authenticated staff can assign a need from stock'
);
select ok(
  has_table_privilege(
    'authenticated', 'public.workshop_inventory_commitments', 'select'
  ) and not has_table_privilege(
    'authenticated', 'public.workshop_inventory_commitments', 'insert'
  ) and not has_table_privilege(
    'authenticated', 'public.workshop_inventory_commitments', 'update'
  ),
  'clients inspect commitments but cannot forge lifecycle state'
);

insert into public.tenants(id, shop_name, currency, timezone) values (
  '99b20000-0000-4000-8000-000000000001',
  'Supply ATP Tenant', 'CLP', 'America/Santiago'
);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99b20000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'supply-atp@example.invalid', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99b20000-0000-4000-8000-000000000099',
  '99b20000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);
insert into public.customers(id, tenant_id, name) values (
  '99b20000-0000-4000-8000-000000000011',
  '99b20000-0000-4000-8000-000000000001',
  'Supply ATP Customer'
);
insert into public.bikes(id, tenant_id, customer_id, brand, model) values (
  '99b20000-0000-4000-8000-000000000012',
  '99b20000-0000-4000-8000-000000000001',
  '99b20000-0000-4000-8000-000000000011',
  'QA', 'ATP Bike'
);
insert into public.job_statuses(
  id, tenant_id, name, code, color, phase, sort_order
) values (
  '99b20000-0000-4000-8000-000000000021',
  '99b20000-0000-4000-8000-000000000001',
  'QA Repuestos', 'QA_ATP_PARTS', '#F97316', 'in_progress', 95
);
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, status_id
) values
  (
    '99b20000-0000-4000-8000-000000000031',
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000011',
    'SUPPLY-ATP-JOB', 'item_service', 'service', 'bike',
    'QA_ATP_PARTS', '99b20000-0000-4000-8000-000000000021'
  ),
  (
    '99b20000-0000-4000-8000-000000000032',
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000011',
    'SUPPLY-INVOICE-JOB', 'item_service', 'service', 'bike',
    'QA_ATP_PARTS', '99b20000-0000-4000-8000-000000000021'
  );
insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values
  (
    '99b20000-0000-4000-8000-000000000041',
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000031',
    '99b20000-0000-4000-8000-000000000012', 0
  ),
  (
    '99b20000-0000-4000-8000-000000000042',
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000032',
    '99b20000-0000-4000-8000-000000000012', 0
  );

select set_config('app.product_set_composition_writer', 'migration', true);
insert into public.products(
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, is_set
) values
  (
    '99b20000-0000-4000-8000-000000000051',
    '99b20000-0000-4000-8000-000000000001',
    'ATP shared product', 'SUPPLY-ATP-SHARED',
    10000, 10000, 4000, 19, 'product', false, 'inventory', true,
    2, 2, 0, 100, true, true, true, false
  ),
  (
    '99b20000-0000-4000-8000-000000000052',
    '99b20000-0000-4000-8000-000000000001',
    'ATP rejectable product', 'SUPPLY-ATP-REJECT',
    12000, 12000, 5000, 19, 'product', false, 'inventory', true,
    2, 2, 0, 100, true, true, true, false
  ),
  (
    '99b20000-0000-4000-8000-000000000053',
    '99b20000-0000-4000-8000-000000000001',
    'ATP invoice product', 'SUPPLY-ATP-INVOICE',
    15000, 15000, 6000, 19, 'product', false, 'inventory', true,
    2, 2, 0, 100, true, true, true, false
  ),
  (
    '99b20000-0000-4000-8000-000000000054',
    '99b20000-0000-4000-8000-000000000001',
    'ATP canonical set', 'SUPPLY-ATP-SET',
    30000, 30000, 12000, 19, 'product', false, 'inventory', true,
    0, 0, 0, 100, true, true, true, true
  ),
  (
    '99b20000-0000-4000-8000-000000000055',
    '99b20000-0000-4000-8000-000000000001',
    'ATP set component A', 'SUPPLY-ATP-COMP-A',
    10000, 10000, 4000, 19, 'product', false, 'inventory', true,
    4, 4, 0, 100, true, true, true, false
  ),
  (
    '99b20000-0000-4000-8000-000000000056',
    '99b20000-0000-4000-8000-000000000001',
    'ATP set component B', 'SUPPLY-ATP-COMP-B',
    10000, 10000, 4000, 19, 'product', false, 'inventory', true,
    2, 2, 0, 100, true, true, true, false
  );
update public.products
set image_url_optimized = 'https://media.invalid/stock-optimized.webp',
    image_url = 'https://media.invalid/stock.jpg',
    image_urls = array['https://media.invalid/stock-alt.jpg']::text[]
where id = '99b20000-0000-4000-8000-000000000051';
update public.products
set parent_set_id = '99b20000-0000-4000-8000-000000000054',
    component_label = case id
      when '99b20000-0000-4000-8000-000000000055'::uuid then 'Component A'
      else 'Component B'
    end,
    component_position = case id
      when '99b20000-0000-4000-8000-000000000055'::uuid then 1
      else 2
    end
where id in (
  '99b20000-0000-4000-8000-000000000055'::uuid,
  '99b20000-0000-4000-8000-000000000056'::uuid
);
insert into public.product_set_components(
  tenant_id, set_product_id, component_product_id,
  component_label, component_position, quantity_in_set
) values
  (
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000054',
    '99b20000-0000-4000-8000-000000000055',
    'Component A', 1, 2
  ),
  (
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000054',
    '99b20000-0000-4000-8000-000000000056',
    'Component B', 2, 1
  );
select set_config('app.product_set_composition_writer', '', true);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99b20000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99b20000-0000-4000-8000-000000000099',
  true
);

create temporary table supply_atp_ids(
  name text primary key,
  id uuid not null
) on commit drop;

insert into supply_atp_ids
select 'online_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '99b20000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'supply-atp-online-first',
    'customer_email', 'supply-atp-online@example.invalid',
    'customer_name', 'Supply ATP Online',
    'customer_address', 'Test',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '99b20000-0000-4000-8000-000000000051',
    'quantity', 1
  ))
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000051'
  ),
  1,
  'common ATP reproduces the online-only result before workshop demand'
);
select is(
  public.online_product_available_quantity(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000051'
  ),
  1,
  'the compatibility signature returns that same ATP result'
);

create temporary table supply_shared_need as
select public.create_supply_need_v1(
  'mechanic_job',
  '99b20000-0000-4000-8000-000000000031',
  '99b20000-0000-4000-8000-000000000041',
  'Producto compartido para probar ATP',
  '99b20000-0000-4000-8000-000000000051',
  1, 'unit', null, 'supply-atp-create-shared'
) as receipt;
create temporary table supply_shared_snapshot as
select public.get_supply_need_inventory_snapshot_v1(
  (select (receipt->>'need_id')::uuid from supply_shared_need)
) as payload;
select is(
  (select payload #>> '{components,0,image_url_optimized}'
   from supply_shared_snapshot),
  'https://media.invalid/stock-optimized.webp',
  'the stock-first surface receives the optimized product photo'
);
select is(
  (select payload #>> '{components,0,image_url}'
   from supply_shared_snapshot),
  'https://media.invalid/stock.jpg',
  'the stock-first surface preserves the raw product photo fallback'
);
select is(
  (select payload #>> '{components,0,image_urls,0}'
   from supply_shared_snapshot),
  'https://media.invalid/stock-alt.jpg',
  'the stock-first surface preserves the additional photo fallback tier'
);
select is(
  (public.assign_supply_need_from_stock_v1(
    (select (receipt->>'need_id')::uuid from supply_shared_need),
    1,
    'supply-atp-assign-shared'
  )->>'version')::bigint,
  2::bigint,
  'workshop assignment commits the last ATP unit and versions the need'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000051'
  ),
  0,
  'online plus workshop commitments exhaust the two physical units'
);
select is(
  (
    select row(physical_quantity, online_committed_quantity,
               workshop_committed_quantity, available_to_promise)::text
    from public.inventory_availability_v1
    where product_id = '99b20000-0000-4000-8000-000000000051'
  ),
  '(2,1,1,0)',
  'the read model keeps on-hand, each commitment source and ATP distinct'
);
create temporary table supply_ai_atp_search as
select public.assistant_search_inventory_v7(
  'SUPPLY-ATP-SHARED', null, 'any', '[]'::jsonb, '[]'::jsonb,
  'relevance', 'desc', 10, 'all_matches'
) as payload;
select is(
  (select (payload #>> '{items,0,stock}')::integer
   from supply_ai_atp_search),
  0,
  'the AI reports available-to-promise rather than physical stock'
);
select is(
  (select payload #>> '{items,0,availability}' from supply_ai_atp_search),
  'out_of_stock',
  'the AI availability state includes active online and workshop commitments'
);
select is(
  (
    public.assistant_search_inventory_v7(
      'SUPPLY-ATP-SHARED', null, 'in_stock', '[]'::jsonb, '[]'::jsonb,
      'relevance', 'desc', 10, 'all_matches'
    ) ->> 'status'
  ),
  'verifiedEmpty',
  'an exhausted committed item cannot survive an in-stock AI filter'
);
select throws_ok(
  $$select public.create_public_online_order(
    jsonb_build_object(
      'tenant_id', '99b20000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', 'supply-atp-online-loser',
      'customer_email', 'supply-atp-loser@example.invalid',
      'customer_name', 'Supply ATP Loser',
      'customer_address', 'Test',
      'delivery_type', 'pickup',
      'payment_method', 'mercadopago'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '99b20000-0000-4000-8000-000000000051',
      'quantity', 1
    ))
  )$$,
  '23514',
  'Stock disponible insuficiente para ATP shared product: solicitado 1, ATP 0.',
  'an online competitor cannot take the unit already committed to the workshop'
);
select is(
  (public.assign_supply_need_from_stock_v1(
    (select (receipt->>'need_id')::uuid from supply_shared_need),
    1,
    'supply-atp-assign-shared'
  )->>'replay')::boolean,
  true,
  'lost assignment acknowledgement replays without a second commitment'
);
select is(
  (
    select count(*)::integer
    from public.workshop_inventory_commitments
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_shared_need
    )
  ),
  1,
  'assignment replay leaves one physical commitment row'
);
select is(
  (public.release_supply_need_stock_v1(
    (select (receipt->>'need_id')::uuid from supply_shared_need),
    2,
    'El operador eligió otra gama',
    'supply-atp-release-shared'
  )->>'released_count')::integer,
  1,
  'release terminalizes the exact workshop commitment'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000051'
  ),
  1,
  'release returns one ATP unit while the online order remains committed'
);
select is(
  (public.assign_supply_need_from_stock_v1(
    (select (receipt->>'need_id')::uuid from supply_shared_need),
    3,
    'supply-atp-reassign-shared'
  )->>'version')::bigint,
  4::bigint,
  'a released row can be safely reactivated in a new cycle'
);
select is(
  (public.cancel_supply_need_v1(
    (select (receipt->>'need_id')::uuid from supply_shared_need),
    4,
    'El cliente canceló',
    'supply-atp-cancel-shared'
  )->>'released_commitment_count')::integer,
  1,
  'cancelling a committed need releases stock in the same transaction'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000051'
  ),
  1,
  'atomic cancellation returns ATP exactly once'
);

create temporary table supply_reject_need as
select public.create_supply_need_v1(
  'mechanic_job',
  '99b20000-0000-4000-8000-000000000031', null,
  'Necesito una gama distinta aunque hay stock',
  '99b20000-0000-4000-8000-000000000052',
  1, 'unit', null, 'supply-atp-create-reject'
) as receipt;
select is(
  (public.reject_supply_need_internal_stock_v1(
    (select (receipt->>'need_id')::uuid from supply_reject_need),
    1,
    'La gama disponible no cumple la solicitud del cliente',
    'supply-atp-reject-internal'
  )->>'version')::bigint,
  2::bigint,
  'rejecting assignable stock records a versioned human decision'
);
select is(
  (
    select internal_stock_rejection_reason
    from public.supply_needs
    where id = (select (receipt->>'need_id')::uuid from supply_reject_need)
  ),
  'La gama disponible no cumple la solicitud del cliente',
  'the reason remains available to the external-search engine'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000052'
  ),
  2,
  'rejecting an alternative does not invent a stock commitment'
);
select is(
  (public.assign_supply_need_from_stock_v1(
    (select (receipt->>'need_id')::uuid from supply_reject_need),
    2,
    'supply-atp-assign-after-reject'
  )->'need'->>'internal_stock_rejection_reason'),
  null,
  'a later explicit assignment clears the obsolete rejection reason'
);
select lives_ok(
  format(
    'select public.release_supply_need_stock_v1(%L::uuid, 3, %L, %L)',
    (select receipt->>'need_id' from supply_reject_need),
    'Liberación de fixture', 'supply-atp-release-after-reject'
  ),
  'the explicitly assigned alternative can be released normally'
);

create temporary table supply_set_need as
select public.create_supply_need_v1(
  'mechanic_job',
  '99b20000-0000-4000-8000-000000000031', null,
  'Un set canónico',
  '99b20000-0000-4000-8000-000000000054',
  1, 'unit', null, 'supply-atp-create-set'
) as receipt;
select lives_ok(
  format(
    'select public.assign_supply_need_from_stock_v1(%L::uuid, 1, %L)',
    (select receipt->>'need_id' from supply_set_need),
    'supply-atp-assign-set'
  ),
  'a set assignment resolves to its canonical physical components'
);
select results_eq(
  $$select product_id, quantity
    from public.workshop_inventory_commitments
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_set_need
    ) and state = 'active'
    order by product_id$$,
  $$values
    ('99b20000-0000-4000-8000-000000000055'::uuid, 2),
    ('99b20000-0000-4000-8000-000000000056'::uuid, 1)$$,
  'the set recipe expands to exact component quantities'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000054'
  ),
  1,
  'set ATP is the minimum remaining component bundle'
);
select throws_ok(
  $$update public.products
    set inventory_qty = 1, stock_quantity = 1
    where id = '99b20000-0000-4000-8000-000000000055'$$,
  '23514',
  'La actualización consumiría unidades comprometidas; el piso protegido es 2.',
  'manual and POS stock paths cannot invade a workshop component floor'
);
select set_config('app.product_set_composition_writer', 'aggregate_rpc', true);
select throws_ok(
  $$update public.product_set_components
    set quantity_in_set = 3
    where set_product_id = '99b20000-0000-4000-8000-000000000054'
      and component_product_id = '99b20000-0000-4000-8000-000000000055'$$,
  '23514',
  'Los componentes del set están bloqueados por un compromiso de inventario.',
  'a committed set recipe cannot change underneath its need'
);
select set_config('app.product_set_composition_writer', '', true);
select lives_ok(
  format(
    'select public.release_supply_need_stock_v1(%L::uuid, 2, %L, %L)',
    (select receipt->>'need_id' from supply_set_need),
    'Liberación de set', 'supply-atp-release-set'
  ),
  'set release terminalizes every physical component'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000054'
  ),
  2,
  'releasing the set restores component-derived ATP'
);

create temporary table supply_invoice_need as
select public.create_supply_need_v1(
  'mechanic_job',
  '99b20000-0000-4000-8000-000000000032',
  '99b20000-0000-4000-8000-000000000042',
  'Producto que será consumido por la factura del trabajo',
  '99b20000-0000-4000-8000-000000000053',
  1, 'unit', null, 'supply-atp-create-invoice'
) as receipt;
select lives_ok(
  format(
    'select public.assign_supply_need_from_stock_v1(%L::uuid, 1, %L)',
    (select receipt->>'need_id' from supply_invoice_need),
    'supply-atp-assign-invoice'
  ),
  'invoice fixture starts from one active workshop commitment'
);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, status,
  subtotal, net_amount, total, paid_amount, balance, items
) values (
  '99b20000-0000-4000-8000-000000000071',
  '99b20000-0000-4000-8000-000000000001',
  'SUPPLY-ATP-INVOICE',
  '99b20000-0000-4000-8000-000000000011',
  'draft', 15000, 15000, 15000, 0, 15000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '99b20000-0000-4000-8000-000000000053',
    'product_sku', 'SUPPLY-ATP-INVOICE',
    'product_name', 'ATP invoice product',
    'quantity', 1,
    'unit_price', 15000,
    'total', 15000,
    'purchase_treatment', 'inventory',
    'is_service', false
  ))
);
update public.mechanic_jobs
set invoice_id = '99b20000-0000-4000-8000-000000000071',
    is_invoiced = true
where id = '99b20000-0000-4000-8000-000000000032';

update public.sales_invoices
set status = 'confirmed'
where id = '99b20000-0000-4000-8000-000000000071';
select is(
  (
    select state from public.workshop_inventory_commitments
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_invoice_need
    )
  ),
  'consumed',
  'posting the linked invoice consumes the exact workshop commitment'
);
select is(
  (
    select stock_quantity from public.products
    where id = '99b20000-0000-4000-8000-000000000053'
  ),
  1,
  'the invoice remains the sole owner of the physical stock decrement'
);
select is(
  (
    select supply_state from public.supply_needs
    where id = (select (receipt->>'need_id')::uuid from supply_invoice_need)
  ),
  'covered',
  'a fully consumed commitment covers the supply dimension of the need'
);
select is(
  (
    select usage_state from public.supply_needs
    where id = (select (receipt->>'need_id')::uuid from supply_invoice_need)
  ),
  'pending',
  'supply coverage does not falsely claim that the mechanic installed the part'
);
select ok(
  (
    select cardinality(stock_movement_ids) > 0
    from public.workshop_inventory_commitments
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_invoice_need
    )
  ),
  'consumption retains the invoice movement identity'
);
select throws_ok(
  $$update public.sales_invoices
    set items = jsonb_set(items, '{0,quantity}', '2'::jsonb)
    where id = '99b20000-0000-4000-8000-000000000071'$$,
  '55000',
  'La factura consumió stock comprometido del taller. Vuelve a borrador antes de editar sus productos.',
  'a posted inventory edit cannot detach consumed commitment evidence'
);

update public.sales_invoices
set status = 'draft'
where id = '99b20000-0000-4000-8000-000000000071';
select is(
  (
    select state from public.workshop_inventory_commitments
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_invoice_need
    )
  ),
  'active',
  'reopening the invoice reactivates the exact commitment after stock restore'
);
select is(
  (
    select stock_quantity from public.products
    where id = '99b20000-0000-4000-8000-000000000053'
  ),
  2,
  'invoice reopening restores physical stock before recommitting the unit'
);
select is(
  public.inventory_available_quantity_v1(
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000053'
  ),
  1,
  'reactivated commitment protects the restored unit from other channels'
);
select is(
  (
    select supply_state from public.supply_needs
    where id = (select (receipt->>'need_id')::uuid from supply_invoice_need)
  ),
  'committed',
  'reopening the invoice returns the need to committed, not open'
);
update public.sales_invoices
set status = 'confirmed'
where id = '99b20000-0000-4000-8000-000000000071';
select is(
  (
    select state from public.workshop_inventory_commitments
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_invoice_need
    )
  ),
  'consumed',
  'reposting consumes the reactivated commitment exactly once in its new cycle'
);
select is(
  (
    select count(*)::integer
    from public.workshop_inventory_commitment_events
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_invoice_need
    ) and event_type = 'reactivated'
  ),
  1,
  'invoice reopening leaves one explicit reactivation event'
);

set local role authenticated;
select throws_ok(
  $$insert into public.workshop_inventory_commitments(
    tenant_id, supply_need_id, source_product_id, product_id, quantity
  ) values (
    '99b20000-0000-4000-8000-000000000001',
    '99b20000-0000-4000-8000-000000000000',
    '99b20000-0000-4000-8000-000000000052',
    '99b20000-0000-4000-8000-000000000052', 1
  )$$,
  '42501',
  'permission denied for table workshop_inventory_commitments',
  'authenticated clients cannot forge a commitment row'
);
reset role;
select throws_ok(
  $$delete from public.workshop_inventory_commitment_events
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_invoice_need
    )$$,
  '55000',
  'Supply kernel evidence is append-only',
  'commitment lifecycle evidence cannot be deleted'
);

select * from finish();
rollback;
