begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_table(
  'public',
  'supplier_variant_resolution_revisions',
  'supplier variants have revisioned authority'
);
select has_table(
  'public',
  'supplier_variant_resolution_edges',
  'supplier variant revisions have ordered product edges'
);
select has_table(
  'public',
  'supplier_variant_resolution_corrections',
  'supplier resolution corrections have negative provenance'
);
select has_table(
  'public',
  'purchase_invoice_source_resolutions',
  'invoice source lines have durable parents'
);
select has_table(
  'public',
  'purchase_invoice_source_components',
  'invoice source parents retain their component expansion'
);
select has_trigger(
  'public',
  'purchase_invoices',
  'trg_validate_purchase_invoice_supplier_resolution',
  'provenance-bearing invoice JSON is validated before persistence'
);
select has_function(
  'public',
  'remember_supplier_variant_resolution',
  array[
    'uuid', 'uuid', 'text', 'text', 'text', 'text', 'integer', 'text',
    'boolean', 'text', 'text', 'jsonb', 'uuid', 'text', 'text', 'jsonb'
  ],
  'revisioned supplier resolution command exists'
);
select has_function(
  'public',
  'resolve_supplier_variant_resolution',
  array[
    'uuid', 'text', 'text', 'text', 'text', 'integer', 'text', 'boolean'
  ],
  'fail-closed supplier resolution read exists'
);
select has_function(
  'public',
  'prepare_purchase_invoice_source_resolution',
  array[
    'uuid', 'uuid', 'text', 'integer', 'numeric', 'bigint', 'text',
    'text[]', 'text', 'text', 'integer', 'text', 'boolean', 'jsonb'
  ],
  'invoice source resolution staging command exists'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.remember_supplier_variant_resolution(uuid,uuid,text,text,text,text,integer,text,boolean,text,text,jsonb,uuid,text,text,jsonb)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.remember_supplier_variant_resolution(uuid,uuid,text,text,text,text,integer,text,boolean,text,text,jsonb,uuid,text,text,jsonb)',
    'execute'
  ),
  'only authenticated callers can write revisioned supplier resolution'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.supplier_variant_resolution_revisions',
    'insert'
  ) and not has_table_privilege(
    'service_role',
    'public.purchase_invoice_source_components',
    'update'
  ),
  'client and service roles cannot forge resolution evidence directly'
);
select col_type_is(
  'public',
  'supplier_variant_resolution_edges',
  'catalog_units_per_purchase',
  'integer',
  'revision edge pack units are positive integers'
);
select col_type_is(
  'public',
  'purchase_invoice_source_components',
  'catalog_units_per_purchase',
  'integer',
  'invoice component pack units retain integer semantics'
);
select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.purchase_invoice_source_resolutions'::regclass
      and constraint_row.contype = 'c'
      and pg_get_constraintdef(constraint_row.oid)
        like '%currency_code = ''CLP''%'
  ),
  'the durable source parent enforces the CLP-only money boundary'
);
select col_type_is(
  'public',
  'purchase_invoice_source_resolutions',
  'source_document_date',
  'date',
  'the durable source parent retains the supplier civil document date'
);
select ok(
  exists (
    select 1
    from pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'uq_purchase_invoice_source_resolution_line'
      and index_row.indexdef like '%(tenant_id, source_line_key)%'
      and index_row.indexdef like '%WHERE (purchase_invoice_id IS NOT NULL)%'
  ),
  'one stable source line can be bound to only one invoice in a tenant'
);

insert into public.tenants(id, shop_name)
values (
  '8b110000-0000-4000-8000-000000000001',
  'Supplier Resolution Tenant'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '8b110000-0000-4000-8000-000000000091',
  'authenticated', 'authenticated', 'resolution@example.invalid', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles(user_id, tenant_id, role, is_active)
values (
  '8b110000-0000-4000-8000-000000000091',
  '8b110000-0000-4000-8000-000000000001',
  'admin',
  true
);

insert into public.suppliers(
  id, tenant_id, name, default_tax_treatment, is_active
) values (
  '8b120000-0000-4000-8000-000000000001',
  '8b110000-0000-4000-8000-000000000001',
  'AliExpress Resolution Test',
  'no_tax',
  true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  min_stock_level, max_stock_level, is_active, product_type, is_set, set_type
) values
  (
    '8b130000-0000-4000-8000-000000000001',
    '8b110000-0000-4000-8000-000000000001',
    'Caliper delantero', 'RES-FRONT', 2000, 1000, 0, 0, 0, 100, true,
    'product', false, null
  ),
  (
    '8b130000-0000-4000-8000-000000000002',
    '8b110000-0000-4000-8000-000000000001',
    'Caliper trasero', 'RES-REAR', 2000, 1000, 0, 0, 0, 100, true,
    'product', false, null
  ),
  (
    '8b130000-0000-4000-8000-000000000003',
    '8b110000-0000-4000-8000-000000000001',
    'Producto inactivo', 'RES-INACTIVE', 2000, 1000, 0, 0, 0, 100, false,
    'product', false, null
  ),
  (
    '8b130000-0000-4000-8000-000000000004',
    '8b110000-0000-4000-8000-000000000001',
    'Servicio taller', 'RES-SERVICE', 2000, 0, 0, 0, 0, 0, true,
    'service', false, null
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '8b110000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '8b110000-0000-4000-8000-000000000091',
  true
);

do $$
begin
  perform public.save_product_set_aggregate(
    jsonb_build_object(
      'id', '8b130000-0000-4000-8000-000000000005',
      'name', 'Set delantero y trasero',
      'sku', 'RES-SET',
      'price', 4000,
      'cost', 2000,
      'is_set', true,
      'product_type', 'product',
      'track_stock', true,
      'set_type', 'front_rear'
    ),
    jsonb_build_array(
      jsonb_build_object(
        'sku', 'RES-SET-FRONT',
        'name', 'Componente set delantero',
        'label', 'Delantero',
        'position', 1,
        'quantity_in_set', 1,
        'cost_ratio', 0.6,
        'price_ratio', 0.5
      ),
      jsonb_build_object(
        'sku', 'RES-SET-REAR',
        'name', 'Componente set trasero',
        'label', 'Trasero',
        'position', 2,
        'quantity_in_set', 1,
        'cost_ratio', 0.4,
        'price_ratio', 0.5
      )
    ),
    'supplier-resolution-pgtap-set'
  );
end;
$$;

create temporary table operator_decision_fixture on commit drop as
select jsonb_build_object(
  'source_line_key', 'order:123#line:1',
  'source_document_date', '2026-01-15',
  'supplier_order_numbers', jsonb_build_array('ORDER-123'),
  'source_purchase_quantity', 2,
  'persisted_quantity', 2,
  'source_total_minor', 1001,
  'persisted_total_minor', 1001,
  'currency_code', 'CLP',
  'confirmation_surface', 'ocr_product_review',
  'model_version', 'supplier-resolution-v1'
) as evidence;

create temporary table correction_decision_fixture on commit drop as
select jsonb_build_object(
  'actor_note', 'Supplier corrected the pack definition'
) as evidence;

select is(
  public.normalize_immutable_supplier_variant_key(
    ' props:200:20|100:10 '
  ),
  'props:100:10|200:20',
  'immutable property tuples are canonicalized by property and value ID'
);
select throws_ok(
  $$select public.normalize_immutable_supplier_variant_key('black-2pcs')$$,
  '22023',
  'An immutable sku: or props: supplier variant key is required.',
  'translated option labels cannot become exact supplier identity'
);
select throws_ok(
  $$select public.normalize_immutable_supplier_variant_key('sku:default')$$,
  '22023',
  'An immutable sku: or props: supplier variant key is required.',
  'default fallback keys cannot become exact supplier identity'
);
select is(
  public.supplier_option_evidence_v1_hash(
    'sku:120000300000000001', 2, 'pcs', false
  ),
  '030f68dcc2bc248e5067b829af73f76007ed388121b6176e937a37d4a1cd11c6',
  'database and client share the exact compact UTF-8 option evidence v1 hash'
);

select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000090',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567090', null, 'sku:120000300000000090',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000090', 1, 'piece', false
    ),
    1, 'piece', false,
    'activate', 'single',
    jsonb_build_array(jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 1,
      'component_role', 'single'
    )),
    null, null, 'migration_confirmed', '{}'::jsonb
  )$$,
  '22023',
  'Migration confirmation requires version, source reference, and actor note.',
  'migration-confirmed authority cannot be seeded without durable why evidence'
);

create temporary table initial_resolution on commit drop as
select public.remember_supplier_variant_resolution(
  '8b140000-0000-4000-8000-000000000001',
  '8b120000-0000-4000-8000-000000000001',
  '1005001234567890',
  null,
  'sku:120000300000000001',
  public.supplier_option_evidence_v1_hash(
    'sku:120000300000000001', 2, 'piece', false
  ),
  2,
  'piece',
  false,
  'activate',
  'composite',
  jsonb_build_array(
    jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 0.6,
      'component_role', 'front'
    ),
    jsonb_build_object(
      'edge_ordinal', 2,
      'product_id', '8b130000-0000-4000-8000-000000000002',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 0.4,
      'component_role', 'rear'
    )
  ),
  null,
  null,
  'operator_confirmed',
  (select evidence from operator_decision_fixture)
) as payload;

select is(
  (select payload->>'state' from initial_resolution),
  'active',
  'an initial composite resolution becomes active'
);
select is(
  (select jsonb_array_length(payload->'edges') from initial_resolution),
  2,
  'the active composite retains both ordered catalog edges'
);
select ok(
  (
    select payload->'decision_evidence' = evidence
      and payload->>'decision_evidence_hash'
        = public.supplier_resolution_sha256(evidence)
    from initial_resolution, operator_decision_fixture
  ),
  'decision evidence is stored, hashed, and returned for read-back'
);
select is(
  (
    public.remember_supplier_variant_resolution(
      '8b140000-0000-4000-8000-000000000001',
      '8b120000-0000-4000-8000-000000000001',
      '1005001234567890',
      null,
      'sku:120000300000000001',
      public.supplier_option_evidence_v1_hash(
        'sku:120000300000000001', 2, 'piece', false
      ),
      2,
      'piece',
      false,
      'activate',
      'composite',
      jsonb_build_array(
        jsonb_build_object(
          'edge_ordinal', 1,
          'product_id', '8b130000-0000-4000-8000-000000000001',
          'catalog_units_per_purchase', 1,
          'allocation_ratio', 0.6,
          'component_role', 'front'
        ),
        jsonb_build_object(
          'edge_ordinal', 2,
          'product_id', '8b130000-0000-4000-8000-000000000002',
          'catalog_units_per_purchase', 1,
          'allocation_ratio', 0.4,
          'component_role', 'rear'
        )
      ),
      null,
      null,
      'operator_confirmed',
      (select evidence from operator_decision_fixture)
    )->>'replayed'
  )::boolean,
  true,
  'an exact operation replay returns its original revision'
);
select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000001',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 2, 'piece', false
    ),
    2, 'piece', false,
    'activate', 'single',
    jsonb_build_array(jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 1,
      'component_role', 'single'
    )),
    null, null, 'operator_confirmed',
    (select evidence from operator_decision_fixture)
  )$$,
  '23505',
  'Resolution operation ID belongs to another request.',
  'an operation ID cannot replay a different request'
);
select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000091',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567091', null, 'sku:120000300000000091',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000091', 1, 'piece', false
    ),
    1, 'piece', false,
    'activate', 'single',
    jsonb_build_array(jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1.5,
      'allocation_ratio', 1,
      'component_role', 'single'
    )),
    null, null, 'operator_confirmed',
    (select evidence from operator_decision_fixture)
  )$$,
  '22023',
  'Resolution edge shape is invalid.',
  'fractional catalog units cannot enter a supplier resolution'
);
select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000092',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567092', null, 'sku:120000300000000092',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000092', 1, 'piece', false
    ),
    1, 'piece', false,
    'activate', 'single',
    jsonb_build_array(jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000004',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 1,
      'component_role', 'service'
    )),
    null, null, 'operator_confirmed',
    (select evidence from operator_decision_fixture)
  )$$,
  '23514',
  'Every resolution edge must reference an active non-service valid catalog target; composite edges cannot target sets.',
  'service products cannot become supplier resolution targets'
);

create temporary table set_resolution on commit drop as
select public.remember_supplier_variant_resolution(
  '8b140000-0000-4000-8000-000000000093',
  '8b120000-0000-4000-8000-000000000001',
  '1005001234567093', null, 'sku:120000300000000093',
  public.supplier_option_evidence_v1_hash(
    'sku:120000300000000093', 2, 'piece', false
  ),
  2, 'piece', false,
  'activate', 'single',
  jsonb_build_array(jsonb_build_object(
    'edge_ordinal', 1,
    'product_id', '8b130000-0000-4000-8000-000000000005',
    'catalog_units_per_purchase', 1,
    'allocation_ratio', 1,
    'component_role', 'catalog_set'
  )),
  null, null, 'operator_confirmed',
  (select evidence from operator_decision_fixture)
) as payload;

select is(
  (select payload->>'state' from set_resolution),
  'active',
  'single resolution may target an active non-service set parent'
);
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567093', null, 'sku:120000300000000093',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000093', 2, 'piece', false
    ),
    2, 'piece', false
  )->>'status',
  'resolved',
  'set parent remains authoritative for the receipt kernel to expand once'
);
select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000094',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567094', null, 'sku:120000300000000094',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000094', 2, 'piece', false
    ),
    2, 'piece', false,
    'activate', 'composite',
    jsonb_build_array(
      jsonb_build_object(
        'edge_ordinal', 1,
        'product_id', '8b130000-0000-4000-8000-000000000005',
        'catalog_units_per_purchase', 1,
        'allocation_ratio', 0.5,
        'component_role', 'nested_set'
      ),
      jsonb_build_object(
        'edge_ordinal', 2,
        'product_id', '8b130000-0000-4000-8000-000000000001',
        'catalog_units_per_purchase', 1,
        'allocation_ratio', 0.5,
        'component_role', 'ordinary'
      )
    ),
    null, null, 'operator_confirmed',
    (select evidence from operator_decision_fixture)
  )$$,
  '23514',
  'Every resolution edge must reference an active non-service valid catalog target; composite edges cannot target sets.',
  'composite resolutions reject set parents to prevent double expansion'
);

create temporary table repeated_product_resolution on commit drop as
select public.remember_supplier_variant_resolution(
  '8b140000-0000-4000-8000-000000000096',
  '8b120000-0000-4000-8000-000000000001',
  '1005001234567096', null, 'sku:120000300000000096',
  public.supplier_option_evidence_v1_hash(
    'sku:120000300000000096', 2, 'piece', false
  ),
  2, 'piece', false,
  'activate', 'composite',
  jsonb_build_array(
    jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 0.5,
      'component_role', 'left'
    ),
    jsonb_build_object(
      'edge_ordinal', 2,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 0.5,
      'component_role', 'right'
    )
  ),
  null, null, 'operator_confirmed',
  (select evidence from operator_decision_fixture)
) as payload;

select ok(
  (
    select jsonb_array_length(payload->'edges') = 2
      and (
        select count(distinct edge->>'product_id')
        from jsonb_array_elements(payload->'edges') edge
      ) = 1
      and (
        select array_agg(edge->>'component_role' order by edge->>'edge_ordinal')
        from jsonb_array_elements(payload->'edges') edge
      ) = array['left', 'right']
    from repeated_product_resolution
  ),
  'one product may repeat at ordered physical roles without losing allocation provenance'
);

select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 2, 'piece', false
    ),
    2, 'piece', false
  )->>'status',
  'resolved',
  'exact active option evidence resolves authoritatively'
);
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 1, 'piece', false
    ),
    1, 'piece', false
  )->>'status',
  'option_evidence_changed',
  'changed option evidence fails closed'
);
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 2, 'piece', true
    ),
    2, 'piece', true
  )->>'status',
  'pack_evidence_conflict',
  'conflicting raw pack evidence makes resolution non-authoritative'
);
select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000095',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567095', null, 'sku:120000300000000095',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000095', 2, 'piece', true
    ),
    2, 'piece', true,
    'activate', 'single',
    jsonb_build_array(jsonb_build_object(
      'edge_ordinal', 1,
      'product_id', '8b130000-0000-4000-8000-000000000001',
      'catalog_units_per_purchase', 1,
      'allocation_ratio', 1,
      'component_role', 'single'
    )),
    null, null, 'operator_confirmed',
    (select evidence from operator_decision_fixture)
  )$$,
  '23514',
  'Conflicting pack evidence cannot activate a supplier resolution.',
  'conflicting pack evidence cannot be remembered as authority'
);

create temporary table staged_source on commit drop as
select public.prepare_purchase_invoice_source_resolution(
  '8b150000-0000-4000-8000-000000000001',
  (select (payload->>'id')::uuid from initial_resolution),
  'order:123#line:1',
  0,
  2,
  1001,
  'CLP',
  array['ORDER-123'],
  'BUCKLOS front and rear caliper set',
  'Front+Rear 2PCS',
  2,
  'pcs',
  false,
  jsonb_build_object(
    'listing_id', '1005001234567890',
    'variant_key', 'sku:120000300000000001',
    'option_evidence_hash', public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 2, 'piece', false
    ),
    'source_row_index', 0,
    'source_document_date', '2026-01-15',
    'source_line_key', 'order:123#line:1',
    'source_order_numbers', jsonb_build_array('ORDER-123'),
    'source_title', 'BUCKLOS front and rear caliper set',
    'selected_option', 'Front+Rear 2PCS',
    'raw_pack_count', 2,
    'raw_unit_code', 'pcs',
    'option_unit_class', 'piece',
    'pack_evidence_conflict', false,
    'source_purchase_quantity', 2,
    'source_line_total_minor', 1001,
    'currency_code', 'CLP',
    'line_title', 'BUCKLOS front and rear caliper set'
  )
) as payload;

select is(
  (select jsonb_array_length(payload->'components') from staged_source),
  2,
  'one source line stages the entire component expansion'
);
select is(
  (
    select sum((component->>'resolved_quantity')::numeric)
    from staged_source,
      lateral jsonb_array_elements(payload->'components') component
  ),
  4::numeric,
  'component quantities equal source purchases times integer pack units'
);
select is(
  (
    select sum((component->>'allocated_line_total_minor')::bigint)::bigint
    from staged_source,
      lateral jsonb_array_elements(payload->'components') component
  ),
  1001::bigint,
  'largest-remainder allocation preserves the exact source total'
);
select ok(
  (
    select payload->>'source_snapshot_hash' ~ '^[a-f0-9]{64}$'
       and payload->>'source_row_index' = '0'
       and payload->>'source_document_date' = '2026-01-15'
       and payload->'source_order_numbers' = '["ORDER-123"]'::jsonb
       and payload->>'currency_code' = 'CLP'
       and payload->'source_snapshot'->>'source_title'
         = 'BUCKLOS front and rear caliper set'
    from staged_source
  ),
  'the source parent durably hashes its row, order, currency and source title'
);
select is(
  (
    public.prepare_purchase_invoice_source_resolution(
      '8b150000-0000-4000-8000-000000000001',
      (select (payload->>'id')::uuid from initial_resolution),
      'order:123#line:1', 0, 2, 1001, 'CLP', array['ORDER-123'],
      'BUCKLOS front and rear caliper set', 'Front+Rear 2PCS',
      2, 'pcs', false,
      (select payload->'source_snapshot' from staged_source)
    )->>'replayed'
  )::boolean,
  true,
  'source preparation is replay-safe for the exact request fingerprint'
);
select throws_ok(
  $$select public.prepare_purchase_invoice_source_resolution(
    '8b150000-0000-4000-8000-000000000002',
    (select (payload->>'id')::uuid from initial_resolution),
    'order:123#line:bad', 1, 1, 100, 'CLP', array['ORDER-123'],
    'Wrong variant snapshot', 'Rear only', 2, 'pcs', false,
    jsonb_build_object(
      'listing_id', '1005001234567890',
      'variant_key', 'sku:wrong',
      'option_evidence_hash', public.supplier_option_evidence_v1_hash(
        'sku:120000300000000001', 2, 'piece', false
      ),
      'source_row_index', 1,
      'source_document_date', '2026-01-15',
      'source_line_key', 'order:123#line:bad',
      'source_order_numbers', jsonb_build_array('ORDER-123'),
      'source_title', 'Wrong variant snapshot',
      'selected_option', 'Rear only',
      'raw_pack_count', 2,
      'raw_unit_code', 'pcs',
      'option_unit_class', 'piece',
      'pack_evidence_conflict', false,
      'source_purchase_quantity', 1,
      'source_line_total_minor', 100,
      'currency_code', 'CLP'
    )
  )$$,
  '23514',
  'Source snapshot listing/variant does not match the resolution revision.',
  'a source snapshot cannot drift from its revision immutable identity'
);
select throws_ok(
  $$select public.prepare_purchase_invoice_source_resolution(
    '8b150000-0000-4000-8000-000000000003',
    (select (payload->>'id')::uuid from initial_resolution),
    'order:123#line:currency', 2, 1, 100, 'USD', array['ORDER-123'],
    'Currency mismatch', null, 2, 'pcs', false,
    jsonb_build_object(
      'listing_id', '1005001234567890',
      'variant_key', 'sku:120000300000000001',
      'option_evidence_hash', public.supplier_option_evidence_v1_hash(
        'sku:120000300000000001', 2, 'piece', false
      ),
      'source_row_index', 2,
      'source_document_date', '2026-01-15',
      'source_line_key', 'order:123#line:currency',
      'source_order_numbers', jsonb_build_array('ORDER-123'),
      'source_title', 'Currency mismatch',
      'selected_option', null,
      'raw_pack_count', 2,
      'raw_unit_code', 'pcs',
      'option_unit_class', 'piece',
      'pack_evidence_conflict', false,
      'source_purchase_quantity', 1,
      'source_line_total_minor', 100,
      'currency_code', 'USD'
    )
  )$$,
  '22023',
  'Supplier-resolution invoice provenance supports CLP only.',
  'non-CLP money fails closed because this boundary has no exponent or FX contract'
);
select throws_ok(
  $$select public.prepare_purchase_invoice_source_resolution(
    '8b150000-0000-4000-8000-000000000004',
    (select (payload->>'id')::uuid from initial_resolution),
    'order:123#line:orders', 3, 1, 100, 'CLP', array['ORDER-123'],
    'Order mismatch', null, 2, 'pcs', false,
    jsonb_build_object(
      'listing_id', '1005001234567890',
      'variant_key', 'sku:120000300000000001',
      'option_evidence_hash', public.supplier_option_evidence_v1_hash(
        'sku:120000300000000001', 2, 'piece', false
      ),
      'source_row_index', 3,
      'source_document_date', '2026-01-15',
      'source_line_key', 'order:123#line:orders',
      'source_order_numbers', jsonb_build_array('ORDER-OTHER'),
      'source_title', 'Order mismatch',
      'selected_option', null,
      'raw_pack_count', 2,
      'raw_unit_code', 'pcs',
      'option_unit_class', 'piece',
      'pack_evidence_conflict', false,
      'source_purchase_quantity', 1,
      'source_line_total_minor', 100,
      'currency_code', 'CLP'
    )
  )$$,
  '23514',
  'Source snapshot does not exactly reproduce its staged source fields.',
  'snapshot order IDs cannot disagree with the staged source parent'
);
select throws_ok(
  $$select public.prepare_purchase_invoice_source_resolution(
    '8b150000-0000-4000-8000-000000000005',
    (select (payload->>'id')::uuid from initial_resolution),
    'order:123#line:conflict', 4, 1, 100, 'CLP', array['ORDER-123'],
    'Pack conflict', null, 2, 'pcs', true, '{}'::jsonb
  )$$,
  '23514',
  'Conflicting pack evidence cannot be staged on an invoice.',
  'pack evidence conflicts also fail closed at invoice preparation'
);
select throws_ok(
  $$select public.prepare_purchase_invoice_source_resolution(
    '8b150000-0000-4000-8000-000000000006',
    (select (payload->>'id')::uuid from initial_resolution),
    'order:123#line:1', 0, 2, 1001, 'CLP', array['ORDER-123'],
    'BUCKLOS front and rear caliper set', 'Front+Rear 2PCS',
    2, 'pcs', false,
    jsonb_set(
      (select payload->'source_snapshot' from staged_source),
      '{source_document_date}',
      '"2026-02-30"'::jsonb
    )
  )$$,
  '23514',
  'Source snapshot document date is invalid.',
  'an impossible source civil date fails closed before staging'
);

create temporary table staged_json on commit drop as
select jsonb_agg(
  jsonb_build_object(
    'supplier_resolution_application_id', source.payload->>'id',
    'supplier_resolution_revision_id', source.payload->>'supplier_resolution_revision_id',
    'source_line_key', source.payload->>'source_line_key',
    'supplier_resolution_edge_ordinal', (component->>'edge_ordinal')::integer,
    'supplier_resolution_component_role', component->>'component_role',
    'source_purchase_quantity', (source.payload->>'source_purchase_quantity')::numeric,
    'catalog_units_per_purchase', (component->>'catalog_units_per_purchase')::integer,
    'allocation_ratio', (component->>'allocation_ratio')::numeric,
    'source_line_total_minor', (source.payload->>'source_line_total_minor')::bigint,
    'allocated_line_total_minor', (component->>'allocated_line_total_minor')::bigint,
    'source_row_index', (source.payload->>'source_row_index')::integer,
    'source_order_numbers', source.payload->'source_order_numbers',
    'supplier_listing_id', source.payload->>'supplier_listing_id',
    'supplier_variant_key', source.payload->>'supplier_variant_key',
    'option_evidence_hash', source.payload->>'option_evidence_hash',
    'source_title', source.payload->>'source_title',
    'selected_option', source.payload->'selected_option',
    'raw_pack_count', source.payload->'raw_pack_count',
    'raw_unit_code', source.payload->'raw_unit_token',
    'pack_evidence_conflict', source.payload->'pack_evidence_conflict',
    'source_snapshot', source.payload->'source_snapshot',
    'product_id', component->>'product_id',
    'product_name', case when component->>'edge_ordinal' = '1'
      then 'Caliper delantero' else 'Caliper trasero' end,
    'product_sku', case when component->>'edge_ordinal' = '1'
      then 'RES-FRONT' else 'RES-REAR' end,
    'quantity', (component->>'resolved_quantity')::numeric,
    'unit_cost', case when component->>'edge_ordinal' = '1'
      then 301.5 else 200 end,
    'discount', case when component->>'edge_ordinal' = '1'
      then 2 else 0 end,
    'iva_rate', 0,
    'created_at', now()
  ) order by (component->>'edge_ordinal')::integer
) as items
from staged_source source,
  lateral jsonb_array_elements(source.payload->'components') component;

insert into public.purchase_invoices(
  id, tenant_id, invoice_number, supplier_id, supplier_name, date, status,
  subtotal, tax, iva_amount, total, net_amount, discount_value,
  discount_amount, additional_costs, paid_amount, balance, items
)
select
  '8b160000-0000-4000-8000-000000000001',
  '8b110000-0000-4000-8000-000000000001',
  'RESOLUTION-001',
  '8b120000-0000-4000-8000-000000000001',
  'AliExpress Resolution Test',
  '2026-01-15T12:00:00Z'::timestamptz,
  'draft',
  1001,
  0,
  0,
  1001,
  1001,
  0,
  0,
  '[]'::jsonb,
  0,
  1001,
  items
from staged_json;

select is(
  (
    select purchase_invoice_id
    from public.purchase_invoice_source_resolutions
    where operation_id = '8b150000-0000-4000-8000-000000000001'
  ),
  '8b160000-0000-4000-8000-000000000001'::uuid,
  'validated source evidence binds once to the persisted invoice'
);
select is(
  (
    select (items->0->>'discount')::numeric
    from public.purchase_invoices
    where id = '8b160000-0000-4000-8000-000000000001'
  ),
  2::numeric,
  'a nonzero discount is accepted as an absolute line amount, not a percent'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(items, '{0,source_row_index}', '9'::jsonb)
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'duplicated source row identity cannot drift from the durable parent'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      items, '{0,source_order_numbers}', '["FORGED"]'::jsonb
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'duplicated supplier order numbers cannot be forged in invoice JSON'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      jsonb_set(
        jsonb_set(
          items,
          '{0,supplier_listing_id}',
          '"forged-listing"'::jsonb
        ),
        '{0,supplier_variant_key}',
        '"sku:forged-variant"'::jsonb
      ),
      '{0,option_evidence_hash}',
      to_jsonb(repeat('a', 64))
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'duplicated listing, variant, and option hash cannot forge supplier identity'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      jsonb_set(
        jsonb_set(items, '{0,source_title}', '"Forged title"'::jsonb),
        '{0,selected_option}', '"Forged option"'::jsonb
      ),
      '{0,raw_pack_count}', '3'::jsonb
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'duplicated title, selected option, and raw pack count cannot drift'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      jsonb_set(
        items, '{0,raw_unit_code}', '"pair"'::jsonb
      ),
      '{0,pack_evidence_conflict}', 'true'::jsonb
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'duplicated raw unit and conflict evidence cannot drift'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      items,
      '{0,source_snapshot,source_title}',
      '"Forged snapshot"'::jsonb
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'the duplicated sanitized source snapshot must remain byte-semantically exact'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      items,
      '{0,supplier_resolution_component_role}',
      '"rear"'::jsonb
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'ordered component role cannot drift from its staged edge'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      jsonb_set(items, '{0,quantity}', '1'::jsonb),
      '{0,unit_cost}',
      '603'::jsonb
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice item drifted from its staged supplier-resolution snapshot.',
  'an invoice cannot drift from catalog units times source quantity'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = items - 1,
        subtotal = 601,
        net_amount = 601,
        total = 601,
        balance = 601
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Supplier-resolution components or source allocation are incomplete.',
  'an invoice cannot silently drop one source component'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = jsonb_set(
      items,
      '{0}',
      (items->0)
        - 'supplier_resolution_application_id'
        - 'supplier_resolution_revision_id'
    )
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Supplier-resolution invoice provenance is incomplete.',
  'any reserved provenance key activates fail-closed completeness validation'
);
select throws_ok(
  $$update public.purchase_invoices
    set items = '[]'::jsonb
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'A purchase invoice cannot discard bound supplier-resolution provenance.',
  'an invoice cannot discard a bound source parent'
);
select throws_ok(
  $$update public.purchase_invoices
    set date = '2026-01-16T12:00:00Z'::timestamptz
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice date does not match its staged supplier source date.',
  'the invoice civil date cannot drift from its source document date'
);
select throws_ok(
  $$update public.purchase_invoices
    set supplier_invoice_date = '2026-01-16T12:00:00Z'::timestamptz
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Invoice date does not match its staged supplier source date.',
  'an optional supplier invoice date must agree with the staged source date'
);
select throws_ok(
  $$update public.purchase_invoices
    set tax_treatment = 'tax_included'
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Supplier-resolution invoices must use no-tax semantics.',
  'graph-bearing invoices cannot reapply IVA'
);
select throws_ok(
  $$update public.purchase_invoices
    set discount_value = 10
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Supplier-resolution invoices cannot apply a global discount.',
  'graph-bearing invoices require a zero global discount input'
);
select throws_ok(
  $$update public.purchase_invoices
    set additional_costs = '[{"description":"duplicated","amount":1}]'::jsonb
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Supplier-resolution invoices cannot apply additional costs twice.',
  'graph-bearing invoices cannot duplicate landed source costs at header level'
);
select throws_ok(
  $$update public.purchase_invoices
    set total = 1000
    where id = '8b160000-0000-4000-8000-000000000001'$$,
  '23514',
  'Supplier-resolution invoice header does not reconcile to its lines.',
  'graph-bearing invoice header totals must reconcile to every persisted line'
);

create temporary table duplicate_staged_source on commit drop as
select public.prepare_purchase_invoice_source_resolution(
  '8b150000-0000-4000-8000-000000000099',
  (select (payload->>'id')::uuid from initial_resolution),
  'order:123#line:1', 0, 2, 1001, 'CLP', array['ORDER-123'],
  'BUCKLOS front and rear caliper set', 'Front+Rear 2PCS',
  2, 'pcs', false,
  (select payload->'source_snapshot' from staged_source)
) as payload;

create temporary table duplicate_staged_json on commit drop as
select jsonb_agg(
  jsonb_build_object(
    'supplier_resolution_application_id', source.payload->>'id',
    'supplier_resolution_revision_id', source.payload->>'supplier_resolution_revision_id',
    'source_line_key', source.payload->>'source_line_key',
    'supplier_resolution_edge_ordinal', (component->>'edge_ordinal')::integer,
    'supplier_resolution_component_role', component->>'component_role',
    'source_purchase_quantity', (source.payload->>'source_purchase_quantity')::numeric,
    'catalog_units_per_purchase', (component->>'catalog_units_per_purchase')::integer,
    'allocation_ratio', (component->>'allocation_ratio')::numeric,
    'source_line_total_minor', (source.payload->>'source_line_total_minor')::bigint,
    'allocated_line_total_minor', (component->>'allocated_line_total_minor')::bigint,
    'source_row_index', (source.payload->>'source_row_index')::integer,
    'source_order_numbers', source.payload->'source_order_numbers',
    'supplier_listing_id', source.payload->>'supplier_listing_id',
    'supplier_variant_key', source.payload->>'supplier_variant_key',
    'option_evidence_hash', source.payload->>'option_evidence_hash',
    'source_title', source.payload->>'source_title',
    'selected_option', source.payload->'selected_option',
    'raw_pack_count', source.payload->'raw_pack_count',
    'raw_unit_code', source.payload->'raw_unit_token',
    'pack_evidence_conflict', source.payload->'pack_evidence_conflict',
    'source_snapshot', source.payload->'source_snapshot',
    'product_id', component->>'product_id',
    'quantity', (component->>'resolved_quantity')::numeric,
    'unit_cost', case when component->>'edge_ordinal' = '1'
      then 301.5 else 200 end,
    'discount', case when component->>'edge_ordinal' = '1'
      then 2 else 0 end
  ) order by (component->>'edge_ordinal')::integer
) as items
from duplicate_staged_source source,
  lateral jsonb_array_elements(source.payload->'components') component;

select throws_ok(
  $$insert into public.purchase_invoices(
      id, tenant_id, invoice_number, supplier_id, supplier_name, date, status,
      subtotal, tax, iva_amount, total, net_amount, discount_value,
      discount_amount, additional_costs, paid_amount, balance, items
    )
    select
      '8b160000-0000-4000-8000-000000000099',
      '8b110000-0000-4000-8000-000000000001',
      'RESOLUTION-DUPLICATE-SOURCE',
      '8b120000-0000-4000-8000-000000000001',
      'AliExpress Resolution Test',
      '2026-01-15T12:00:00Z'::timestamptz,
      'draft', 1001, 0, 0, 1001, 1001, 0, 0, '[]'::jsonb, 0, 1001,
      items
    from duplicate_staged_json$$,
  '23505',
  'duplicate key value violates unique constraint "uq_purchase_invoice_source_resolution_line"',
  'one stable supplier source line cannot bind to a second invoice'
);

insert into public.purchase_invoices(
  id, tenant_id, invoice_number, supplier_id, supplier_name, status,
  subtotal, tax, total, paid_amount, balance, items
) values (
  '8b160000-0000-4000-8000-000000000002',
  '8b110000-0000-4000-8000-000000000001',
  'LEGACY-UNTOUCHED-001',
  '8b120000-0000-4000-8000-000000000001',
  'AliExpress Resolution Test',
  'draft',
  500,
  0,
  500,
  0,
  500,
  '[{"product_id":"8b130000-0000-4000-8000-000000000001","product_name":"Legacy","product_sku":"RES-FRONT","quantity":1,"unit_cost":500,"discount":0,"iva_rate":0}]'::jsonb
);
select ok(
  exists (
    select 1
    from public.purchase_invoices
    where id = '8b160000-0000-4000-8000-000000000002'
  ),
  'legacy invoice items without provenance remain operational'
);

create temporary table correction_resolution on commit drop as
select public.remember_supplier_variant_resolution(
  '8b140000-0000-4000-8000-000000000002',
  '8b120000-0000-4000-8000-000000000001',
  '1005001234567890', null, 'sku:120000300000000001',
  public.supplier_option_evidence_v1_hash(
    'sku:120000300000000001', 1, 'piece', false
  ),
  1, 'piece', false,
  'activate', 'single',
  jsonb_build_array(jsonb_build_object(
    'edge_ordinal', 1,
    'product_id', '8b130000-0000-4000-8000-000000000001',
    'catalog_units_per_purchase', 1,
    'allocation_ratio', 1,
    'component_role', 'single'
  )),
  (select (payload->>'id')::uuid from initial_resolution),
  'Supplier corrected the pack definition',
  'administrative_correction',
  (select evidence from correction_decision_fixture)
) as payload;

select is(
  (
    select state
    from public.supplier_variant_resolution_revisions
    where id = (select (payload->>'id')::uuid from initial_resolution)
  ),
  'superseded',
  'a correction supersedes rather than mutates prior authority'
);
select ok(
  exists (
    select 1
    from public.supplier_variant_resolution_corrections correction
    where correction.prior_revision_id =
      (select (payload->>'id')::uuid from initial_resolution)
      and correction.replacement_revision_id =
        (select (payload->>'id')::uuid from correction_resolution)
      and correction.correction_action = 'correction'
  ),
  'the correction records the rejected prior revision as a negative edge'
);
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 1, 'piece', false
    ),
    1, 'piece', false
  )->>'resolution_kind',
  'single',
  'the resolver returns only the latest active correction'
);

update public.products
set is_active = false
where id = '8b130000-0000-4000-8000-000000000001';
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 1, 'piece', false
    ),
    1, 'piece', false
  )->>'status',
  'inactive_or_contradictory_edges',
  'an inactive catalog product makes exact resolution fail closed'
);

update public.products
set is_active = true
where id = '8b130000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.remember_supplier_variant_resolution(
    '8b140000-0000-4000-8000-000000000003',
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 1, 'piece', false
    ),
    1, 'piece', false,
    'revoke', null, '[]'::jsonb,
    null, 'Attempted stale revocation', 'administrative_correction',
    (select evidence from correction_decision_fixture)
  )$$,
  '40001',
  'Revocation requires the exact active revision and a reason.',
  'a stale or missing expected revision cannot revoke authority'
);

update public.suppliers
set is_active = false
where id = '8b120000-0000-4000-8000-000000000001';
select is(
  (
    public.remember_supplier_variant_resolution(
      '8b140000-0000-4000-8000-000000000002',
      '8b120000-0000-4000-8000-000000000001',
      '1005001234567890', null, 'sku:120000300000000001',
      public.supplier_option_evidence_v1_hash(
        'sku:120000300000000001', 1, 'piece', false
      ),
      1, 'piece', false,
      'activate', 'single',
      jsonb_build_array(jsonb_build_object(
        'edge_ordinal', 1,
        'product_id', '8b130000-0000-4000-8000-000000000001',
        'catalog_units_per_purchase', 1,
        'allocation_ratio', 1,
        'component_role', 'single'
      )),
      (select (payload->>'id')::uuid from initial_resolution),
      'Supplier corrected the pack definition',
      'administrative_correction',
      (select evidence from correction_decision_fixture)
    )->>'replayed'
  )::boolean,
  true,
  'an exact remember replay survives later supplier inactivity'
);
select is(
  (
    public.prepare_purchase_invoice_source_resolution(
      '8b150000-0000-4000-8000-000000000001',
      (select (payload->>'id')::uuid from initial_resolution),
      'order:123#line:1', 0, 2, 1001, 'CLP', array['ORDER-123'],
      'BUCKLOS front and rear caliper set', 'Front+Rear 2PCS',
      2, 'pcs', false,
      (select payload->'source_snapshot' from staged_source)
    )->>'replayed'
  )::boolean,
  true,
  'an exact source replay survives later supplier inactivity'
);
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:120000300000000001',
    public.supplier_option_evidence_v1_hash(
      'sku:120000300000000001', 1, 'piece', false
    ),
    1, 'piece', false
  )->>'status',
  'supplier_inactive',
  'an inactive supplier makes new resolution reads fail closed'
);
select throws_ok(
  $$select public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005001234567890', null, 'sku:default', repeat('c', 64),
    null, 'unknown', false
  )$$,
  '22023',
  'An immutable sku: or props: supplier variant key is required.',
  'weak variant fallbacks are rejected at the resolver boundary even for an inactive supplier'
);
update public.suppliers
set is_active = true
where id = '8b120000-0000-4000-8000-000000000001';

insert into public.supplier_product_aliases(
  id, tenant_id, supplier_id, product_id, listing_id, variant_key,
  created_by, updated_by
) values (
  '8b170000-0000-4000-8000-000000000001',
  '8b110000-0000-4000-8000-000000000001',
  '8b120000-0000-4000-8000-000000000001',
  '8b130000-0000-4000-8000-000000000001',
  '1005009999999999',
  'sku:120000399999999999',
  '8b110000-0000-4000-8000-000000000091',
  '8b110000-0000-4000-8000-000000000091'
);
select is(
  public.resolve_supplier_variant_resolution(
    '8b120000-0000-4000-8000-000000000001',
    '1005009999999999', null, 'sku:120000399999999999',
    public.supplier_option_evidence_v1_hash(
      'sku:120000399999999999', null, 'unknown', false
    ),
    null, 'unknown', false
  )->>'status',
  'legacy_candidate',
  'an immutable legacy alias is surfaced only as a review candidate'
);
select is(
  public.resolve_supplier_product_alias(
    '8b120000-0000-4000-8000-000000000001',
    null,
    '1005009999999999',
    'sku:120000399999999999'
  ),
  null::jsonb,
  'the old one-target resolver cannot silently authorize a pack or composite'
);
select is(
  (
    public.resolve_supplier_variant_resolution(
      '8b120000-0000-4000-8000-000000000001',
      '1005009999999999', null, 'sku:120000399999999999',
      public.supplier_option_evidence_v1_hash(
        'sku:120000399999999999', null, 'unknown', false
      ),
      null, 'unknown', false
    )->>'authoritative'
  )::boolean,
  false,
  'legacy compatibility never grants new revision authority'
);

select * from finish();
rollback;
