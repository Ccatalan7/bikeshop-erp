begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(51);

select has_table(
  'public',
  'supplier_product_aliases',
  'supplier listing decisions have a durable alias table'
);
select has_table(
  'public',
  'aliexpress_sku_reservation_receipts',
  'AE allocations have a durable replay receipt table'
);
select has_trigger(
  'public',
  'aliexpress_sku_reservation_receipts',
  'trg_aliexpress_sku_reservation_receipts_immutable',
  'AE reservation receipts are append-only'
);
select has_trigger(
  'public',
  'aliexpress_sku_reservation_receipts',
  'trg_aliexpress_sku_receipts_validate_identity',
  'denormalized receipt identities are validated when recorded'
);
select has_function(
  'public',
  'resolve_supplier_product_alias',
  array['uuid', 'text', 'text', 'text'],
  'an exact supplier listing variant alias can be resolved'
);
select has_function(
  'public',
  'remember_supplier_product_alias',
  array[
    'uuid', 'uuid', 'text', 'text', 'text', 'text', 'text', 'text', 'text'
  ],
  'an explicit supplier listing variant decision can be remembered'
);
select has_function(
  'public',
  'resolve_product_by_supplier_code',
  array['uuid', 'text'],
  'supplier-code lookup requires an explicit supplier'
);
select has_function(
  'public',
  'reserve_aliexpress_skus',
  array['integer', 'text', 'uuid', 'text'],
  'AE SKUs use one atomic reservation command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.resolve_supplier_product_alias(uuid,text,text,text)',
    'execute'
  ),
  'authenticated workers can resolve aliases'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.resolve_product_by_supplier_code(uuid,text)',
    'execute'
  ),
  'authenticated workers can use supplier-scoped exact lookup'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.reserve_aliexpress_skus(integer,text,uuid,text)',
    'execute'
  ),
  'authenticated workers can reserve AE SKUs'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.reserve_aliexpress_skus(integer,text,uuid,text)',
    'execute'
  ),
  'anonymous callers cannot reserve AE SKUs'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.supplier_product_aliases',
    'insert'
  ),
  'aliases can only be written through the canonical command'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.aliexpress_sku_reservation_receipts',
    'insert'
  ),
  'reservation receipts can only be written through the allocator'
);
select is(
  (
    select class.relrowsecurity
    from pg_class class
    where class.oid = 'public.supplier_product_aliases'::regclass
  ),
  true,
  'supplier aliases have RLS enabled'
);
select is(
  (
    select class.relrowsecurity
    from pg_class class
    where class.oid = 'public.aliexpress_sku_reservation_receipts'::regclass
  ),
  true,
  'AE reservation receipts have RLS enabled'
);

insert into public.tenants(id, shop_name) values
  ('9a210000-0000-4000-8000-000000000001', 'Supplier Identity Tenant A'),
  ('9a210000-0000-4000-8000-000000000002', 'Supplier Identity Tenant B');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9a210000-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'supplier-a@example.invalid', '',
    now(), '{}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '9a210000-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'supplier-b@example.invalid', '',
    now(), '{}'::jsonb, '{}'::jsonb, now(), now()
  ),
  (
    '9a210000-0000-4000-8000-000000000093',
    'authenticated', 'authenticated', 'supplier-mechanic@example.invalid', '',
    now(), '{}'::jsonb, '{}'::jsonb, now(), now()
  );

insert into public.user_profiles(user_id, tenant_id, role) values
  (
    '9a210000-0000-4000-8000-000000000091',
    '9a210000-0000-4000-8000-000000000001',
    'admin'
  ),
  (
    '9a210000-0000-4000-8000-000000000092',
    '9a210000-0000-4000-8000-000000000002',
    'admin'
  ),
  (
    '9a210000-0000-4000-8000-000000000093',
    '9a210000-0000-4000-8000-000000000001',
    'mechanic'
  );

select throws_ok(
  $$insert into public.aliexpress_sku_reservation_receipts(
      tenant_id, supplier_id, supplier_name, operation_key,
      requested_count, first_sequence, last_sequence, skus,
      request_snapshot, response_snapshot, actor_id
    ) values (
      '9a210000-0000-4000-8000-000000000099',
      '9a210000-0000-4000-8000-000000000099',
      'AliExpress Orphan', 'orphan-receipt',
      1, 1, 1, array['AE0001'],
      '{}'::jsonb, '{}'::jsonb,
      '9a210000-0000-4000-8000-000000000091'
    )$$,
  '23503',
  'Receipt tenant/supplier/actor identity was not valid at allocation time.',
  'a denormalized receipt cannot be born with orphan identity'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a210000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a210000-0000-4000-8000-000000000091',
  true
);

insert into public.suppliers(id, tenant_id, name, aliases) values
  (
    '9a210000-0000-4000-8000-000000000011',
    '9a210000-0000-4000-8000-000000000001',
    'AliExpress Marketplace',
    array['Ali Express']
  ),
  (
    '9a210000-0000-4000-8000-000000000012',
    '9a210000-0000-4000-8000-000000000001',
    'Proveedor Local',
    '{}'::text[]
  ),
  (
    '9a210000-0000-4000-8000-000000000021',
    '9a210000-0000-4000-8000-000000000002',
    'AliExpress B',
    '{}'::text[]
  );

insert into public.products(
  id, tenant_id, name, sku, price, cost,
  supplier_id, supplier_code, inventory_qty, stock_quantity
) values
  (
    '9a210000-0000-4000-8000-000000000031',
    '9a210000-0000-4000-8000-000000000001',
    'Ali exact product', 'SUP-ID-A-1', 1000, 500,
    '9a210000-0000-4000-8000-000000000011', 'SAME-CODE', 0, 0
  ),
  (
    '9a210000-0000-4000-8000-000000000032',
    '9a210000-0000-4000-8000-000000000001',
    'Local exact product', 'SUP-ID-A-2', 1000, 500,
    '9a210000-0000-4000-8000-000000000012', 'SAME-CODE', 0, 0
  ),
  (
    '9a210000-0000-4000-8000-000000000033',
    '9a210000-0000-4000-8000-000000000001',
    'Ambiguous Ali product one', 'SUP-ID-A-3', 1000, 500,
    '9a210000-0000-4000-8000-000000000011', 'DUPLICATE', 0, 0
  ),
  (
    '9a210000-0000-4000-8000-000000000034',
    '9a210000-0000-4000-8000-000000000001',
    'Ambiguous Ali product two', 'SUP-ID-A-4', 1000, 500,
    '9a210000-0000-4000-8000-000000000011', 'DUPLICATE', 0, 0
  ),
  (
    '9a210000-0000-4000-8000-000000000041',
    '9a210000-0000-4000-8000-000000000002',
    'Foreign tenant product', 'SUP-ID-B-1', 1000, 500,
    '9a210000-0000-4000-8000-000000000021', 'SAME-CODE', 0, 0
  ),
  (
    '9a210000-0000-4000-8000-000000000035',
    '9a210000-0000-4000-8000-000000000001',
    'Existing high AE product', 'AE900000000', 1000, 500,
    '9a210000-0000-4000-8000-000000000011', null, 0, 0
  );

select is(
  public.resolve_product_by_supplier_code(
    '9a210000-0000-4000-8000-000000000011',
    ' same-code '
  )->>'product_id',
  '9a210000-0000-4000-8000-000000000031',
  'an exact code resolves only inside the selected AliExpress supplier'
);
select is(
  public.resolve_product_by_supplier_code(
    '9a210000-0000-4000-8000-000000000012',
    'SAME-CODE'
  )->>'product_id',
  '9a210000-0000-4000-8000-000000000032',
  'the same code can independently resolve inside another supplier'
);
select is(
  public.resolve_product_by_supplier_code(
    '9a210000-0000-4000-8000-000000000011',
    'missing'
  ),
  null::jsonb,
  'an unknown supplier code returns no product'
);
select throws_ok(
  $$select public.resolve_product_by_supplier_code(
    '9a210000-0000-4000-8000-000000000011',
    'duplicate'
  )$$,
  '21000',
  'Supplier code is ambiguous for the selected supplier.',
  'duplicates inside one supplier fail closed instead of picking a row'
);
select throws_ok(
  $$select public.resolve_product_by_supplier_code(
    '9a210000-0000-4000-8000-000000000021',
    'same-code'
  )$$,
  'P0002',
  'Supplier was not found in the authenticated tenant.',
  'supplier-code lookup cannot use another tenant supplier'
);

create temporary table alias_result on commit drop as
select public.remember_supplier_product_alias(
  '9a210000-0000-4000-8000-000000000011',
  '9a210000-0000-4000-8000-000000000032',
  'https://www.aliexpress.com/item/1005001234567890.html?spm=test',
  null,
  ' SKU:MS-01B;COLOR:BLACK ',
  '  ZTTO   Brake PAD  ',
  ' MS-01B ',
  'https://ae01.alicdn.com/example.jpg',
  repeat('A', 64)
) as payload;

select is(
  (select payload->>'listing_id' from alias_result),
  '1005001234567890',
  'the canonical listing ID is extracted from the AliExpress URL'
);
select is(
  (select payload->>'variant_key' from alias_result),
  'sku:ms-01b;color:black',
  'the explicit listing variant key is normalized and retained'
);
select ok(
  (
    select product.supplier_id =
             '9a210000-0000-4000-8000-000000000012'::uuid
       and product.supplier_name = 'Proveedor Local'
    from public.products product
    where product.id = '9a210000-0000-4000-8000-000000000032'
  ),
  'learning an AliExpress alias preserves the existing primary supplier pair'
);
select ok(
  (
    select alias.normalized_title = 'ztto brake pad'
       and alias.normalized_model = 'ms-01b'
       and alias.image_content_hash = repeat('a', 64)
       and alias.image_url is null
    from public.supplier_product_aliases alias
    where alias.listing_id = '1005001234567890'
  ),
  'aliases retain only normalized title/model and one image identity proof'
);
select is(
  public.resolve_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    'https://www.aliexpress.com/item/1005001234567890.html',
    null,
    'sku:ms-01b;color:black'
  )->>'product_id',
  '9a210000-0000-4000-8000-000000000032',
  'the exact tenant+supplier+listing alias resolves its ERP product'
);
select is(
  (
    public.remember_supplier_product_alias(
      '9a210000-0000-4000-8000-000000000011',
      '9a210000-0000-4000-8000-000000000032',
      null,
      '1005001234567890',
      'sku:ms-01b;color:black',
      'ZTTO Brake PAD',
      'MS-01B',
      null,
      repeat('a', 64)
    )->>'replayed'
  )::boolean,
  true,
  'repeating the exact link is an idempotent no-op'
);
select is(
  (
    select count(*)::integer
    from public.supplier_product_aliases alias
    where alias.tenant_id = '9a210000-0000-4000-8000-000000000001'
      and alias.supplier_id = '9a210000-0000-4000-8000-000000000011'
      and alias.listing_id = '1005001234567890'
  ),
  1,
  'an exact alias replay creates no duplicate row'
);
select throws_ok(
  $$select public.remember_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    '9a210000-0000-4000-8000-000000000031',
    null,
    '1005001234567890',
    'sku:ms-01b;color:black',
    null,
    null,
    null,
    null
  )$$,
  '23505',
  'Supplier listing is already linked to another product.',
  'an existing listing variant cannot be silently rebound'
);
select is(
  public.remember_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    '9a210000-0000-4000-8000-000000000031',
    null,
    '1005001234567890',
    'sku:ms-01b;color:red',
    null,
    null,
    null,
    null
  )->>'product_id',
  '9a210000-0000-4000-8000-000000000031',
  'a different explicit variant of one listing can link independently'
);
select is(
  public.resolve_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    null,
    '1005001234567890',
    'sku:ms-01b;color:red'
  )->>'product_id',
  '9a210000-0000-4000-8000-000000000031',
  'resolution includes the variant key instead of using itemId alone'
);
select throws_ok(
  $$select public.resolve_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    null,
    '1005001234567890',
    '   '
  )$$,
  '22023',
  'A valid supplier listing variant key is required.',
  'blank variant identity fails closed before autonomous alias resolution'
);
select throws_ok(
  $$select public.remember_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    '9a210000-0000-4000-8000-000000000041',
    null,
    '1005009999999999',
    'sku:foreign',
    null,
    null,
    null,
    null
  )$$,
  'P0002',
  'Product was not found in the authenticated tenant.',
  'an alias cannot link to another tenant product'
);
select throws_ok(
  $$select public.resolve_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    'https://www.aliexpress.com/store/seller-only',
    null,
    'sku:missing-item'
  )$$,
  '22023',
  'AliExpress itemId or a URL containing the item ID is required.',
  'a URL without stable listing identity is rejected'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a210000-0000-4000-8000-000000000093',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a210000-0000-4000-8000-000000000093',
  true
);
select throws_ok(
  $$select public.remember_supplier_product_alias(
    '9a210000-0000-4000-8000-000000000011',
    '9a210000-0000-4000-8000-000000000031',
    null,
    '1005007777777777',
    'sku:mechanic',
    null,
    null,
    null,
    null
  )$$,
  '42501',
  'The active employee cannot manage supplier product identity.',
  'an unauthorized active role cannot write supplier aliases'
);
select throws_ok(
  $$select public.reserve_aliexpress_skus(
    1,
    'alias-sku-mechanic',
    '9a210000-0000-4000-8000-000000000011',
    'AliExpress Marketplace'
  )$$,
  '42501',
  'The active employee cannot manage supplier product identity.',
  'an unauthorized active role cannot reserve global AE numbers'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a210000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a210000-0000-4000-8000-000000000091',
  true
);

create temporary table expected_first_sku_sequence on commit drop as
select coalesce(
  max((regexp_match(upper(product.sku), '^AE([0-9]+)$'))[1]::bigint),
  0
) + 1 as value
from public.products product
where upper(product.sku) ~ '^AE[0-9]+$';

create temporary table first_sku_reservation on commit drop as
select public.reserve_aliexpress_skus(
  2,
  'alias-sku-op-1',
  '9a210000-0000-4000-8000-000000000011',
  'AliExpress Marketplace'
) as payload;

select is(
  (
    select (payload->>'first_sequence')::bigint
    from first_sku_reservation
  ),
  (select value from expected_first_sku_sequence),
  'the allocator starts strictly after every existing global AE SKU'
);
select is(
  (select payload->'skus' from first_sku_reservation),
  (
    select to_jsonb(array[
      'AE' || lpad(
        expected.value::text,
        greatest(4, length(expected.value::text)),
        '0'
      ),
      'AE' || lpad(
        (expected.value + 1)::text,
        greatest(4, length((expected.value + 1)::text)),
        '0'
      )
    ])
    from expected_first_sku_sequence expected
  ),
  'one transaction returns the exact contiguous AE range'
);
select ok(
  (
    select replay.payload->'skus' = first.payload->'skus'
       and (replay.payload->>'replayed')::boolean
    from first_sku_reservation first
    cross join lateral (
      select public.reserve_aliexpress_skus(
        2,
        'alias-sku-op-1',
        '9a210000-0000-4000-8000-000000000011',
        'AliExpress Marketplace'
      ) as payload
    ) replay
  ),
  'the same operation key replays the committed SKU range'
);
select is(
  (
    select count(*)::integer
    from public.aliexpress_sku_reservation_receipts receipt
    where receipt.tenant_id = '9a210000-0000-4000-8000-000000000001'
      and receipt.operation_key = 'alias-sku-op-1'
  ),
  1,
  'an exact SKU replay creates no second receipt'
);
select throws_ok(
  $$select public.reserve_aliexpress_skus(
    3,
    'alias-sku-op-1',
    '9a210000-0000-4000-8000-000000000011',
    'AliExpress Marketplace'
  )$$,
  '23505',
  'SKU reservation operation key belongs to another request.',
  'an operation key cannot be reused for a different count'
);

create temporary table second_sku_reservation on commit drop as
select public.reserve_aliexpress_skus(
  1,
  'alias-sku-op-2',
  '9a210000-0000-4000-8000-000000000011',
  'AliExpress Marketplace'
) as payload;
select is(
  (select (payload->>'first_sequence')::bigint from second_sku_reservation),
  (
    select (payload->>'last_sequence')::bigint + 1
    from first_sku_reservation
  ),
  'a new operation cannot overlap a previously reserved range'
);
select throws_ok(
  $$select public.reserve_aliexpress_skus(
    1,
    'alias-sku-name-mismatch',
    '9a210000-0000-4000-8000-000000000011',
    'AliExpress typo'
  )$$,
  '23514',
  'Supplier ID and supplier name do not identify the same supplier.',
  'supplier ID and name must remain consistent'
);
select throws_ok(
  $$select public.reserve_aliexpress_skus(
    1,
    'alias-sku-wrong-supplier',
    '9a210000-0000-4000-8000-000000000012',
    'Proveedor Local'
  )$$,
  '23514',
  'The selected supplier is not configured as AliExpress.',
  'the AE namespace cannot be reserved for another supplier'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a210000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a210000-0000-4000-8000-000000000092',
  true
);

create temporary table tenant_b_sku_reservation on commit drop as
select public.reserve_aliexpress_skus(
  1,
  'alias-sku-op-1',
  '9a210000-0000-4000-8000-000000000021',
  'AliExpress B'
) as payload;
select is(
  (select (payload->>'first_sequence')::bigint from tenant_b_sku_reservation),
  (
    select (payload->>'last_sequence')::bigint + 1
    from second_sku_reservation
  ),
  'another tenant still advances the globally unique products.sku namespace'
);
select is(
  (
    select count(*)::integer
    from public.aliexpress_sku_reservation_receipts receipt
    where receipt.operation_key = 'alias-sku-op-1'
  ),
  2,
  'the same operation key is independently scoped by tenant'
);
select throws_ok(
  $$update public.aliexpress_sku_reservation_receipts
    set requested_count = requested_count
    where id = (
      select (payload->>'id')::uuid
      from tenant_b_sku_reservation
    )$$,
  '55000',
  'AliExpress SKU reservation receipts are append-only',
  'a committed SKU receipt cannot be mutated'
);

delete from public.suppliers
where id = '9a210000-0000-4000-8000-000000000021';
select ok(
  (
    public.reserve_aliexpress_skus(
      1,
      'alias-sku-op-1',
      '9a210000-0000-4000-8000-000000000021',
      'AliExpress B'
    )->>'replayed'
  )::boolean,
  'an exact receipt remains replayable after its denormalized supplier is deleted'
);

-- A production-derived schema-only restore can omit schema ACLs. Re-establish
-- the standard Supabase grant inside this rolled-back test before exercising
-- the policies as the real API role.
grant usage on schema public to authenticated;
set local role authenticated;
select ok(
  (select count(*) from public.aliexpress_sku_reservation_receipts) = 1
    and (select count(*) from public.supplier_product_aliases) = 0,
  'active tenant B sees its own receipt but no tenant A aliases under RLS'
);
reset role;

update public.user_profiles
set is_active = false
where user_id = '9a210000-0000-4000-8000-000000000092'
  and tenant_id = '9a210000-0000-4000-8000-000000000002';
set local role authenticated;
select ok(
  (select count(*) from public.aliexpress_sku_reservation_receipts) = 0
    and (select count(*) from public.supplier_product_aliases) = 0,
  'an inactive employee token cannot read aliases or receipts directly'
);
reset role;

select * from finish();
rollback;
