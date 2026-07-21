begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(40);

insert into public.tenants (id, shop_name) values
  ('99a10000-0000-4000-8000-000000000001', 'Product Set Tenant A'),
  ('99a10000-0000-4000-8000-000000000002', 'Product Set Tenant B');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '99a10000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
    'product-set-a@example.invalid', '', now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '99a10000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '99a10000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
    'product-set-b@example.invalid', '', now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '99a10000-0000-4000-8000-000000000002'),
    now(), now()
  );

-- The canonical auth hook provisions a starter tenant for new users. Replace
-- that bootstrap profile with the explicit tenant fixture so user_tenant_id()
-- is deterministic inside this transaction.
delete from public.user_profiles
where user_id in (
  '99a10000-0000-4000-8000-000000000091'::uuid,
  '99a10000-0000-4000-8000-000000000092'::uuid
);
insert into public.user_profiles (user_id, tenant_id, role) values
  ('99a10000-0000-4000-8000-000000000091', '99a10000-0000-4000-8000-000000000001', 'admin'),
  ('99a10000-0000-4000-8000-000000000092', '99a10000-0000-4000-8000-000000000002', 'admin');

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99a10000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '99a10000-0000-4000-8000-000000000091', true);

create temp table set_create_result on commit drop as
select public.save_product_set_aggregate(
  jsonb_build_object(
    'id', '99a10000-0000-4000-8000-000000000010',
    'name', 'Canonical Brake Set',
    'sku', 'PGTAP-SET-001',
    'price', 30000,
    'cost', 15000,
    'min_stock_level', 5,
    'max_stock_level', 10,
    'set_type', 'front_rear',
    'image_fingerprint', jsonb_build_object('sha256', 'set-image-hash'),
    'is_whatsapp_catalog', true,
    'whatsapp_catalog_title', 'Canonical Brake Set Catalog',
    'whatsapp_catalog_description', 'Front and rear brake set',
    'whatsapp_catalog_price', 31990
  ),
  jsonb_build_array(
    jsonb_build_object(
      'sku', 'PGTAP-SET-001-FRONT',
      'name', 'Canonical Brake Front',
      'label', 'Delantero',
      'position', 1,
      'quantity_in_set', 1,
      'price', 15000,
      'cost', 7500,
      'cost_ratio', 0.5,
      'price_ratio', 0.5
    ),
    jsonb_build_object(
      'sku', 'PGTAP-SET-001-REAR',
      'name', 'Canonical Brake Rear',
      'label', 'Trasero',
      'position', 2,
      'quantity_in_set', 2,
      'price', 15000,
      'cost', 7500,
      'cost_ratio', 0.5,
      'price_ratio', 0.5
    )
  ),
  'pgtap-set-create-001'
) as payload;

select is(
  (select payload->'parent'->>'id' from set_create_result),
  '99a10000-0000-4000-8000-000000000010',
  'aggregate RPC returns the full saved parent'
);
select is(
  (select inventory_qty from public.products where id = '99a10000-0000-4000-8000-000000000010'),
  0,
  'set parent stores no physical inventory'
);
select is(
  (select count(*)::integer from public.products where parent_set_id = '99a10000-0000-4000-8000-000000000010'),
  2,
  'aggregate RPC creates both component products atomically'
);
select is(
  (select count(*)::integer from public.product_set_components where set_product_id = '99a10000-0000-4000-8000-000000000010'),
  2,
  'aggregate RPC creates the canonical map'
);
select is(
  (select count(*)::integer
   from public.product_set_components component
   join public.products product on product.id = component.component_product_id
   where component.set_product_id = '99a10000-0000-4000-8000-000000000010'
     and product.parent_set_id = component.set_product_id),
  2,
  'legacy parent_set_id remains an exact compatibility mirror'
);
select is(
  (select quantity_in_set from public.product_set_components
   where set_product_id = '99a10000-0000-4000-8000-000000000010'
     and component_position = 2),
  2,
  'quantity_in_set is persisted as part of the canonical map'
);
select is(
  (select image_fingerprint->>'sha256' from public.products
   where id = '99a10000-0000-4000-8000-000000000010'),
  'set-image-hash',
  'aggregate RPC preserves image-match metadata'
);
select ok(
  (select is_whatsapp_catalog from public.products
   where id = '99a10000-0000-4000-8000-000000000010'),
  'aggregate RPC preserves the user-owned WhatsApp catalog toggle'
);
select is(
  (select whatsapp_catalog_title from public.products
   where id = '99a10000-0000-4000-8000-000000000010'),
  'Canonical Brake Set Catalog',
  'aggregate RPC preserves the user-owned WhatsApp catalog title'
);
select is(
  (select whatsapp_catalog_price from public.products
   where id = '99a10000-0000-4000-8000-000000000010'),
  31990::numeric,
  'aggregate RPC preserves the user-owned WhatsApp catalog price'
);

create temp table set_replay_result on commit drop as
select public.save_product_set_aggregate(
  jsonb_build_object(
    'id', '99a10000-0000-4000-8000-000000000010',
    'name', 'Canonical Brake Set',
    'sku', 'PGTAP-SET-001',
    'price', 30000,
    'cost', 15000,
    'min_stock_level', 5,
    'max_stock_level', 10,
    'set_type', 'front_rear',
    'image_fingerprint', jsonb_build_object('sha256', 'set-image-hash'),
    'is_whatsapp_catalog', true,
    'whatsapp_catalog_title', 'Canonical Brake Set Catalog',
    'whatsapp_catalog_description', 'Front and rear brake set',
    'whatsapp_catalog_price', 31990
  ),
  jsonb_build_array(
    jsonb_build_object('sku', 'PGTAP-SET-001-FRONT', 'name', 'Canonical Brake Front', 'label', 'Delantero', 'position', 1, 'quantity_in_set', 1, 'price', 15000, 'cost', 7500, 'cost_ratio', 0.5, 'price_ratio', 0.5),
    jsonb_build_object('sku', 'PGTAP-SET-001-REAR', 'name', 'Canonical Brake Rear', 'label', 'Trasero', 'position', 2, 'quantity_in_set', 2, 'price', 15000, 'cost', 7500, 'cost_ratio', 0.5, 'price_ratio', 0.5)
  ),
  'pgtap-set-create-001'
) as payload;

select ok((select (payload->>'replayed')::boolean from set_replay_result), 'exact operation replay is acknowledged');
select is(
  (select count(*)::integer from public.inventory_accounting_operations
   where operation_key = 'product_set:pgtap-set-create-001'),
  1,
  'operation replay creates no duplicate trace'
);

update public.products
set whatsapp_catalog_sync_status = 'synced',
    whatsapp_catalog_sync_error = null,
    whatsapp_catalog_sync_requested_at = null
where id = '99a10000-0000-4000-8000-000000000010';

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
select lives_ok(
  $$update public.products set inventory_qty = 3, stock_quantity = 3
    where sku = 'PGTAP-SET-001-FRONT'$$,
  'component stock remains authoritative when catalog transport is unavailable'
);
update public.products set inventory_qty = 6, stock_quantity = 6
where sku = 'PGTAP-SET-001-REAR';
select set_config('app.skip_stock_adjustment_trigger', '', true);

select ok(
  (select whatsapp_catalog_sync_requested_at is not null
          and whatsapp_catalog_sync_status in ('pending', 'failed')
   from public.products
   where id = '99a10000-0000-4000-8000-000000000010'),
  'component stock queues its WhatsApp-published parent without virtual stock'
);
select is(
  (select count(*)::integer from public.stock_movements
   where product_id = '99a10000-0000-4000-8000-000000000010'),
  0,
  'parent catalog refresh creates no virtual-header inventory movement'
);

select is(public.get_full_sets_count('99a10000-0000-4000-8000-000000000010'), 3, 'derived availability uses quantity_in_set');
select is(
  (select stock_quantity from public.products where id = '99a10000-0000-4000-8000-000000000010'),
  0,
  'component changes never materialize stock on the parent'
);
select is(
  (public.preview_product_stock_impact('99a10000-0000-4000-8000-000000000010', 1)->>'available_quantity')::integer,
  3,
  'stock impact preview exposes calculated set availability'
);
select ok(
  (public.preview_product_stock_impact('99a10000-0000-4000-8000-000000000010', 1)->>'tracks_inventory')::boolean,
  'stock impact preview explicitly identifies tracked inventory'
);
select is(
  (select (component->>'projected_stock')::integer
   from jsonb_array_elements(public.preview_product_stock_impact('99a10000-0000-4000-8000-000000000010', 1)->'components') component
   where component->>'sku' = 'PGTAP-SET-001-REAR'),
  4,
  'stock impact preview multiplies the component requirement'
);
select is(
  (select count(*)::integer from public.smart_purchase_list
   where product_id = '99a10000-0000-4000-8000-000000000010' and status = 'pending'),
  1,
  'smart purchasing tracks the set procurement unit using derived availability'
);
select is(
  (select count(*)::integer from public.smart_purchase_list list
   join public.products product on product.id = list.product_id
   where product.parent_set_id = '99a10000-0000-4000-8000-000000000010'
     and list.status = 'pending'),
  0,
  'smart purchasing does not duplicate private component recommendations'
);

select throws_ok(
  $$update public.products set inventory_qty = 1, stock_quantity = 1 where id = '99a10000-0000-4000-8000-000000000010'$$,
  '23514',
  'Set parent physical stock must remain zero; use calculated availability',
  'direct writes cannot put physical stock on a set parent'
);
select throws_ok(
  $$update public.products set parent_set_id = null where sku = 'PGTAP-SET-001-FRONT'$$,
  '42501',
  'Product set relationships must be changed through save_product_set_aggregate',
  'direct product writes cannot unlink a component'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '99a10000-0000-4000-8000-000000000092', 'role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', '99a10000-0000-4000-8000-000000000092', true);
select throws_ok(
  $$select public.get_product_set_composition('99a10000-0000-4000-8000-000000000010')$$,
  '42501',
  'Product set not found for current tenant',
  'composition reads are tenant isolated'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '99a10000-0000-4000-8000-000000000091', 'role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', '99a10000-0000-4000-8000-000000000091', true);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, balance, items
) values (
  '99a10000-0000-4000-8000-000000000020',
  '99a10000-0000-4000-8000-000000000001',
  'SET-HISTORY-001', 'Set history', 'draft',
  30000, 30000, 0, 30000, 30000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '99a10000-0000-4000-8000-000000000010',
    'product_sku', 'PGTAP-SET-001', 'quantity', 1,
    'unit_price', 30000, 'purchase_treatment', 'inventory'
  ))
);

select ok(
  public.product_set_has_document_history(
    '99a10000-0000-4000-8000-000000000001',
    '99a10000-0000-4000-8000-000000000010'
  ),
  'a saved invoice line freezes the set physical recipe'
);

create temp table set_edit_payload on commit drop as
select jsonb_build_object(
  'parent', jsonb_build_object(
    'id', parent.id, 'expected_updated_at', parent.updated_at,
    'name', parent.name, 'sku', parent.sku, 'price', parent.price,
    'cost', parent.cost, 'min_stock_level', parent.min_stock_level,
    'max_stock_level', parent.max_stock_level, 'set_type', parent.set_type
  ),
  'components', (
    select jsonb_agg(jsonb_build_object(
      'id', product.id, 'sku', product.sku, 'name', product.name,
      'label', case when component.component_position = 1 then 'Frontal' else component.component_label end,
      'position', component.component_position,
      'quantity_in_set', component.quantity_in_set,
      'price', product.price, 'cost', product.cost,
      'cost_ratio', component.cost_ratio, 'price_ratio', component.price_ratio
    ) order by component.component_position)
    from public.product_set_components component
    join public.products product on product.id = component.component_product_id
    where component.set_product_id = parent.id
  )
) as payload
from public.products parent
where parent.id = '99a10000-0000-4000-8000-000000000010';

select lives_ok(
  $$select public.save_product_set_aggregate(
    (select payload->'parent' from set_edit_payload),
    (select payload->'components' from set_edit_payload),
    'pgtap-set-edit-metadata-001'
  )$$,
  'metadata-only component edits remain possible after document history'
);
select is(
  (select component_label from public.product_set_components
   where set_product_id = '99a10000-0000-4000-8000-000000000010'
     and component_position = 1),
  'Frontal',
  'metadata edit updates canonical and compatibility labels'
);

select throws_ok(
  $$select public.save_product_set_aggregate(
    jsonb_build_object(
      'id', parent.id, 'expected_updated_at', parent.updated_at,
      'name', parent.name, 'sku', parent.sku
    ),
    (
      select jsonb_agg(jsonb_build_object(
        'id', product.id, 'sku', product.sku, 'name', product.name,
        'label', component.component_label, 'position', component.component_position,
        'quantity_in_set', case when component.component_position = 1 then 2 else component.quantity_in_set end,
        'price', product.price, 'cost', product.cost,
        'cost_ratio', component.cost_ratio, 'price_ratio', component.price_ratio
      ) order by component.component_position)
      from public.product_set_components component
      join public.products product on product.id = component.component_product_id
      where component.set_product_id = parent.id
    ),
    'pgtap-set-edit-history-break-001'
  ) from public.products parent where parent.id = '99a10000-0000-4000-8000-000000000010'$$,
  '23514',
  'Set composition or quantities cannot change after document history exists',
  'document history freezes physical set composition'
);

select throws_ok(
  $$delete from public.product_set_components where set_product_id = '99a10000-0000-4000-8000-000000000010'$$,
  '42501',
  'Product set composition must be changed through save_product_set_aggregate',
  'direct canonical-map deletion is blocked'
);

select set_config('app.product_set_composition_writer', 'migration', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  product_type, purchase_treatment, is_service, track_stock, is_set
) values (
  '99a10000-0000-4000-8000-000000000030',
  '99a10000-0000-4000-8000-000000000001',
  'Broken Empty Set', 'PGTAP-EMPTY-SET', 1000, 500, 0, 0,
  'product', 'inventory', false, true, true
);
select set_config('app.product_set_composition_writer', '', true);

select throws_ok(
  $$select * from public.sales_invoice_stock_requirements(
    '99a10000-0000-4000-8000-000000000001',
    '[{"product_id":"99a10000-0000-4000-8000-000000000030","quantity":1}]'::jsonb
  )$$,
  '23514',
  'Set product PGTAP-EMPTY-SET has no canonical components',
  'sales requirements fail closed for an empty set'
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, net_amount, tax, total, balance, items
) values (
  '99a10000-0000-4000-8000-000000000031',
  '99a10000-0000-4000-8000-000000000001',
  'EMPTY-SET-PURCHASE', 'Broken supplier', 'draft',
  500, 500, 0, 500, 500,
  '[{"product_id":"99a10000-0000-4000-8000-000000000030","product_sku":"PGTAP-EMPTY-SET","quantity":1,"unit_cost":500,"purchase_treatment":"inventory"}]'::jsonb
);
select throws_ok(
  $$select public.consume_purchase_invoice_inventory(invoice)
    from public.purchase_invoices invoice
    where invoice.id = '99a10000-0000-4000-8000-000000000031'$$,
  '23514',
  'Set product PGTAP-EMPTY-SET has no canonical components',
  'legacy purchase consumption fails closed for an empty set'
);

select is(
  (select count(*)::integer from public.product_set_integrity_issues
   where product_id = '99a10000-0000-4000-8000-000000000010'),
  0,
  'valid aggregate has no integrity issue'
);
select is(
  (select count(*)::integer from public.product_set_integrity_issues
   where product_id = '99a10000-0000-4000-8000-000000000030'
     and issue_code = 'set_without_canonical_components'),
  1,
  'integrity projection exposes an empty set'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_set_components', 'INSERT'),
  'authenticated clients cannot insert canonical-map rows directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_set_components', 'TRUNCATE'),
  'authenticated clients cannot truncate canonical-map rows'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_set_components', 'REFERENCES'),
  'authenticated clients cannot add references to the canonical map'
);
select ok(
  not has_table_privilege('authenticated', 'public.product_set_components', 'TRIGGER'),
  'authenticated clients cannot attach triggers to the canonical map'
);
select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.products'::regclass
      and constraint_row.conname = 'products_tenant_parent_set_fkey'
      and constraint_row.contype = 'f'
  ),
  'legacy parent mirror has a tenant-composite foreign key'
);
select ok(
  exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.operation_key = 'product_set:pgtap-set-edit-metadata-001'
      and operation.outcome = 'completed'
  ),
  'aggregate edits complete an immutable operation trace'
);

select * from finish();
rollback;
