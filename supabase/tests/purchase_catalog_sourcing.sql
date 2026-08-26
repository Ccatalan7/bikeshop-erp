begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_function(
  'public', 'get_product_sourcing_evidence_v1', array['uuid[]'],
  'catalog sourcing evidence has one bounded authenticated read'
);
select has_function(
  'public', 'get_supply_need_stock_resolution_v2',
  array['uuid', 'integer', 'integer'],
  'stock resolution transports sourcing evidence in the same round trip'
);
select has_function(
  'public', 'get_supply_need_stock_resolution_v3',
  array['uuid', 'integer', 'integer'],
  'stock resolution transports labelled catalog cost without rewriting history'
);
select has_function(
  'public', 'prepare_purchase_plan_product_v1',
  array['uuid', 'bigint', 'uuid', 'uuid', 'numeric', 'text', 'text'],
  'a no-history exact product has an idempotent quote-line command'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.get_product_sourcing_evidence_v1(uuid[])',
    'execute'
  ) and not has_function_privilege(
    'anon', 'public.get_product_sourcing_evidence_v1(uuid[])', 'execute'
  ),
  'sourcing evidence is staff-only'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)',
    'execute'
  ),
  'catalog cost enrichment remains staff-only'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.prepare_purchase_plan_product_v1(uuid,bigint,uuid,uuid,numeric,text,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.prepare_purchase_plan_product_v1(uuid,bigint,uuid,uuid,numeric,text,text)',
    'execute'
  ),
  'only authenticated staff can prepare a quote-required line'
);
select col_is_null(
  'public', 'purchase_plan_lines', 'candidate_id',
  'a quote-required line does not invent a historical candidate'
);
select col_is_null(
  'public', 'purchase_plan_lines', 'supplier_name',
  'a quote-required line may honestly have no supplier yet'
);
select has_column(
  'public', 'purchase_plan_lines', 'evidence_state',
  'plan lines preserve the class of sourcing evidence'
);

select throws_ok(
  $$select public.get_product_sourcing_evidence_v1(
    array['99c25000-0000-4000-8000-000000000041'::uuid]
  )$$,
  '42501', 'No tenant context',
  'without a tenant no catalog sourcing evidence is disclosed'
);

insert into public.tenants(id, shop_name) values
  ('99c25000-0000-4000-8000-000000000001', 'Catalog sourcing A'),
  ('99c25000-0000-4000-8000-000000000002', 'Catalog sourcing B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99c25000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'catalog-sourcing@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role) values (
  '99c25000-0000-4000-8000-000000000099',
  '99c25000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.suppliers(id, tenant_id, name, website) values
  (
    '99c25000-0000-4000-8000-000000000031',
    '99c25000-0000-4000-8000-000000000001',
    'Derman legado QA', 'https://derman.invalid/catalog'
  ),
  (
    '99c25000-0000-4000-8000-000000000032',
    '99c25000-0000-4000-8000-000000000001',
    'Portal fresco QA', 'https://portal.invalid'
  ),
  (
    '99c25000-0000-4000-8000-000000000033',
    '99c25000-0000-4000-8000-000000000002',
    'Proveedor ajeno QA', null
  );

insert into public.products(
  id, tenant_id, name, sku, price, cost, supplier_id,
  inventory_qty, stock_quantity, min_stock_level, track_stock,
  is_active, is_service, product_type, purchase_treatment
) values
  (
    '99c25000-0000-4000-8000-000000000041',
    '99c25000-0000-4000-8000-000000000001',
    'Cámara 29 Presta 60 mm QA', 'TUBE-60-QA', 7000, 3396,
    '99c25000-0000-4000-8000-000000000031',
    0, 0, 0, true, true, false, 'product', 'inventory'
  ),
  (
    '99c25000-0000-4000-8000-000000000042',
    '99c25000-0000-4000-8000-000000000001',
    'Producto de portal fresco QA', 'FRESH-QA', 8000, 3500, null,
    0, 0, 0, true, true, false, 'product', 'inventory'
  ),
  (
    '99c25000-0000-4000-8000-000000000043',
    '99c25000-0000-4000-8000-000000000001',
    'Producto sin proveedor QA', 'QUOTE-QA', 9000, 4000, null,
    0, 0, 0, true, true, false, 'product', 'inventory'
  ),
  (
    '99c25000-0000-4000-8000-000000000044',
    '99c25000-0000-4000-8000-000000000002',
    'Producto ajeno QA', 'FOREIGN-QA', 100, 50,
    '99c25000-0000-4000-8000-000000000033',
    0, 0, 0, true, true, false, 'product', 'inventory'
  );

insert into public.supplier_availability_checks(
  id, tenant_id, supplier_id, product_id, supplier_code, checked_at,
  status, price_net, stock_quantity, source_url, evidence
) values
  (
    '99c25000-0000-4000-8000-000000000051',
    '99c25000-0000-4000-8000-000000000001',
    '99c25000-0000-4000-8000-000000000032',
    '99c25000-0000-4000-8000-000000000042',
    'FRESH-QA', statement_timestamp() - interval '15 minutes',
    'available', 3700, 8, 'https://portal.invalid/FRESH-QA',
    '{"source":"fixture"}'::jsonb
  ),
  (
    '99c25000-0000-4000-8000-000000000052',
    '99c25000-0000-4000-8000-000000000001',
    '99c25000-0000-4000-8000-000000000032',
    '99c25000-0000-4000-8000-000000000042',
    'FRESH-QA', statement_timestamp() - interval '5 minutes',
    'session_expired', null, null, 'https://portal.invalid/login',
    '{"source":"fixture"}'::jsonb
  ),
  (
    '99c25000-0000-4000-8000-000000000053',
    '99c25000-0000-4000-8000-000000000001',
    '99c25000-0000-4000-8000-000000000031',
    '99c25000-0000-4000-8000-000000000042',
    'FRESH-QA-OTHER', statement_timestamp() - interval '2 minutes',
    'out_of_stock', 3650, 0, 'https://derman.invalid/FRESH-QA-OTHER',
    '{"source":"fixture"}'::jsonb
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99c25000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99c25000-0000-4000-8000-000000000099',
  true
);
set local role authenticated;

create temporary table catalog_sourcing_result as
select public.get_product_sourcing_evidence_v1(array[
  '99c25000-0000-4000-8000-000000000041'::uuid,
  '99c25000-0000-4000-8000-000000000042'::uuid,
  '99c25000-0000-4000-8000-000000000043'::uuid,
  '99c25000-0000-4000-8000-000000000044'::uuid
]) as payload;

select is(
  (
    select item.value ->> 'evidenceState'
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000041'
  ),
  'catalog_assignment',
  'a legacy catalog supplier keeps the exact product visible without history'
);
select is(
  (
    select item.value ->> 'supplierName'
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000041'
  ),
  'Derman legado QA',
  'the stock/catalog row names its catalog supplier without calling it a purchase'
);
select is(
  (
    select (item.value ->> 'purchaseCount')::integer
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000041'
  ),
  0,
  'catalog assignment never invents a purchase count'
);
select is(
  (
    select item.value ->> 'evidenceState'
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000042'
  ),
  'fresh_supplier_check',
  'a fresh available portal check may introduce a clearly sourced supplier'
);
select is(
  (
    select item.value ->> 'availabilitySourceUrl'
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000042'
  ),
  'https://portal.invalid/FRESH-QA',
  'fresh availability retains its source for the operator'
);
select is(
  (
    select item.value ->> 'availabilityStatus'
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000042'
  ),
  'available',
  'a newer failed probe or another supplier stockout cannot erase fresh availability'
);
select is(
  (
    select item.value ->> 'evidenceState'
    from catalog_sourcing_result result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000043'
  ),
  'no_erp_history',
  'a product without purchases or supplier remains an honest quote target'
);
select is(
  (select jsonb_array_length(payload -> 'items') from catalog_sourcing_result),
  3,
  'foreign-tenant product ids are not disclosed'
);

create temporary table quote_need as
select public.create_supply_need_v1(
  'ad_hoc', null, null, 'Producto de portal fresco QA',
  '99c25000-0000-4000-8000-000000000042', 2, 'unit', null,
  'catalog-quote-need-qa'
) as payload;
create temporary table quote_plan as
select public.prepare_purchase_plan_product_v1(
  null, null,
  (select (payload ->> 'need_id')::uuid from quote_need),
  '99c25000-0000-4000-8000-000000000042',
  2, 'balanced', 'catalog-quote-line-qa'
) as payload;

create temporary table exact_stock_v3 as
select public.get_supply_need_stock_resolution_v3(
  (select (payload ->> 'need_id')::uuid from quote_need), 12, 0
) as payload;

select is(
  (
    select (item.value ->> 'catalogCostNet')::numeric
    from exact_stock_v3 result
    cross join lateral jsonb_array_elements(result.payload -> 'items') item
    where item.value ->> 'productId' =
      '99c25000-0000-4000-8000-000000000042'
  ),
  3500::numeric,
  'the exact row exposes the current catalog cost as a labelled reference'
);

select is(
  (select payload #>> '{line,evidence_state}' from quote_plan),
  'fresh_supplier_check',
  'the plan freezes the real provenance class'
);
select ok(
  (select payload #> '{line,candidate_id}' from quote_plan) = 'null'::jsonb
  and (select payload #> '{line,landed_unit_cost_net}' from quote_plan)
    = 'null'::jsonb,
  'the quote line has neither invented candidate nor invented cost'
);
select is(
  (select payload #>> '{line,evidence_snapshot,availability_source_url}'
   from quote_plan),
  'https://portal.invalid/FRESH-QA',
  'the plan freezes the availability source and date instead of a vague flag'
);
select is(
  (select (payload #>> '{line,evidence_snapshot,catalog_cost_net}')::numeric
   from quote_plan),
  3500::numeric,
  'the plan freezes catalog cost in evidence without treating it as paid'
);
select is(
  (
    public.prepare_purchase_plan_product_v1(
      null, null,
      (select (payload ->> 'need_id')::uuid from quote_need),
      '99c25000-0000-4000-8000-000000000042',
      2, 'balanced', 'catalog-quote-line-qa'
    ) ->> 'replay'
  )::boolean,
  true,
  'an exact retry replays without duplicating a plan or line'
);

reset role;

-- La siguiente compra real debe promover la misma línea sin que NULL rompa
-- la comparación del writer histórico. Se inserta como draft para que el
-- normalizador canónico cree sus líneas y sólo se cambia el estado dentro del
-- fixture rollback-only, sin disparar inventario ni contabilidad.
insert into public.purchase_invoices(
  id, tenant_id, invoice_number, supplier_id, supplier_name, date,
  status, subtotal, tax, total, tax_treatment, net_amount, items
) values (
  '99c25000-0000-4000-8000-000000000061',
  '99c25000-0000-4000-8000-000000000001',
  'CATALOG-PROMOTION-QA',
  '99c25000-0000-4000-8000-000000000032',
  'Portal fresco QA', statement_timestamp(), 'draft',
  7400, 1406, 8806, 'tax_included', 7400,
  jsonb_build_array(jsonb_build_object(
    'product_id', '99c25000-0000-4000-8000-000000000042',
    'product_name', 'Producto de portal fresco QA',
    'product_sku', 'FRESH-QA',
    'purchase_treatment', 'inventory',
    'quantity', 2,
    'unit_cost', 3700,
    'iva_rate', 0.19
  ))
);
set local session_replication_role = replica;
update public.purchase_invoices
set status = 'received'
where id = '99c25000-0000-4000-8000-000000000061';
set local session_replication_role = origin;

set local role authenticated;
create temporary table promoted_quote_plan as
select public.prepare_purchase_plan_line_v1(
  (select (payload ->> 'plan_id')::uuid from quote_plan),
  (select (payload ->> 'plan_version')::bigint from quote_plan),
  (select (payload ->> 'need_id')::uuid from quote_need),
  (
    select candidate_id
    from public.purchase_candidate_metrics_v1
    where tenant_id = '99c25000-0000-4000-8000-000000000001'
      and product_id = '99c25000-0000-4000-8000-000000000042'
      and supplier_id = '99c25000-0000-4000-8000-000000000032'
    order by latest_purchase_at desc, candidate_id
    limit 1
  ),
  2, 'balanced', 'catalog-quote-promotion-qa'
) as payload;

select is(
  (select (payload ->> 'changed')::boolean from promoted_quote_plan),
  true,
  'the first ERP purchase actively promotes the existing quote line'
);
select ok(
  (select payload #> '{line,candidate_id}' from promoted_quote_plan)
    <> 'null'::jsonb
  and (select payload #>> '{line,evidence_state}' from promoted_quote_plan)
    = 'erp_purchase_history',
  'promotion replaces the null candidate and marks real purchase evidence'
);
select ok(
  (select (payload #>> '{line,landed_unit_cost_net}')::numeric
   from promoted_quote_plan) > 0,
  'promotion freezes the observed landed cost instead of a quote placeholder'
);
select is(
  (
    select event.changed
    from public.purchase_plan_events event
    where event.operation_key = 'catalog-quote-promotion-qa'
  ),
  true,
  'the promotion receipt records a non-null changed decision'
);

reset role;

-- Deterministic mutation test for the basket contract. This replacement lives
-- only inside this transaction and rollback restores the real resolver.
create or replace function public.purchase_supplier_concentration_internal_v1(
  p_tenant_id uuid,
  p_query text default null,
  p_category text default null,
  p_brand text default null,
  p_limit integer default 5
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
  select jsonb_build_object(
    'items', case btrim(coalesce(p_query, ''))
      when 'camara 29 presta 60' then jsonb_build_array(jsonb_build_object(
        'entityId', '99c25000-0000-4000-8000-000000000031',
        'supplierName', 'Derman legado QA',
        'scopeRelaxed', false,
        'landedSpendNet', 100,
        'spendSharePercent', 60,
        'lastPurchaseAt', '2026-08-20T12:00:00Z',
        'daysSinceLastPurchase', 5,
        'supplierWebsite', 'https://derman.invalid',
        'hasPortalAccount', false,
        'supplierCity', 'Santiago',
        'brands', 'QA'
      ))
      when 'disco 160 exacto' then jsonb_build_array(
        jsonb_build_object(
          'entityId', '99c25000-0000-4000-8000-000000000031',
          'supplierName', 'Derman legado QA',
          'scopeRelaxed', true,
          'landedSpendNet', 200,
          'spendSharePercent', 70,
          'lastPurchaseAt', '2026-08-21T12:00:00Z',
          'daysSinceLastPurchase', 4,
          'supplierWebsite', 'https://derman.invalid',
          'hasPortalAccount', false,
          'supplierCity', 'Santiago',
          'brands', 'QA'
        ),
        jsonb_build_object(
          'entityId', '99c25000-0000-4000-8000-000000000032',
          'supplierName', 'Portal fresco QA',
          'scopeRelaxed', false,
          'landedSpendNet', 50,
          'spendSharePercent', 30,
          'lastPurchaseAt', '2026-08-19T12:00:00Z',
          'daysSinceLastPurchase', 6,
          'supplierWebsite', 'https://portal.invalid',
          'hasPortalAccount', true,
          'supplierCity', 'Viña del Mar',
          'brands', 'QA'
        )
      )
      else '[]'::jsonb
    end
  );
$$;

create temporary table exact_basket as
select public.purchase_basket_supplier_coverage_internal_v1(
  '99c25000-0000-4000-8000-000000000001',
  '["camara 29 presta 60","disco 160 exacto"]'::jsonb,
  4
) as payload;

select is(
  (select (payload #>> '{items,0,coveredNeeds}')::integer from exact_basket),
  1,
  'a relaxed match does not increment exact basket coverage'
);
select is(
  (select (payload #>> '{items,0,approximateNeeds}')::integer
   from exact_basket),
  1,
  'the relaxed match remains visible as an approximate suggestion'
);
select is(
  (select payload #>> '{items,0,missingList}' from exact_basket),
  'disco 160 exacto',
  'the exact line remains missing instead of being falsely completed'
);
select is(
  (select payload #>> '{items,0,complementSupplierName}' from exact_basket),
  'Portal fresco QA',
  'the complement is calculated from exact coverage only'
);

select * from finish();
rollback;
