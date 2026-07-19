begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(24);

select has_table(
  'public',
  'product_tax_classification_batches',
  'curated tax batches have an immutable receipt table'
);
select has_table(
  'public',
  'product_tax_classification_events',
  'product tax changes have append-only before/after evidence'
);
select has_function(
  'public',
  'apply_curated_product_tax_classification_batch',
  array['uuid', 'text', 'integer', 'text', 'text', 'numeric', 'text', 'text'],
  'curated fail-closed batch command exists'
);
select has_trigger(
  'public',
  'products',
  'trg_capture_product_tax_classification_event',
  'every future product tax-rate change is captured'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_curated_product_tax_classification_batch(uuid,text,integer,text,text,numeric,text,text)',
    'EXECUTE'
  ),
  'staff clients cannot invoke the curated migration command directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.apply_curated_product_tax_classification_batch(uuid,text,integer,text,text,numeric,text,text)',
    'EXECUTE'
  ),
  'service role can invoke the reviewed batch command'
);

insert into public.tenants (id, shop_name, currency, timezone)
values
  (
    '9e220000-0000-4000-8000-000000000001',
    'Product Tax Rollout Test',
    'CLP',
    'America/Santiago'
  ),
  (
    '9e220000-0000-4000-8000-000000000002',
    'Product Tax Drift Test',
    'CLP',
    'America/Santiago'
  );

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
    '9e220000-0000-4000-8000-000000000010',
    '9e220000-0000-4000-8000-000000000001',
    'Public product', 'TAX-ROLLOUT-PRODUCT', 1190, 1190, 400, null,
    'product', false, 'inventory', false, 0, 0, 0, 0,
    true, true, true
  ),
  (
    '9e220000-0000-4000-8000-000000000011',
    '9e220000-0000-4000-8000-000000000001',
    'Public service', 'TAX-ROLLOUT-SERVICE', 2380, 2380, 900, null,
    'service', true, 'expense', false, 0, 0, 0, 0,
    true, true, true
  ),
  (
    '9e220000-0000-4000-8000-000000000012',
    '9e220000-0000-4000-8000-000000000001',
    'Zero price review', 'TAX-ROLLOUT-ZERO', 0, 0, 0, null,
    'product', false, 'inventory', false, 0, 0, 0, 0,
    true, true, true
  ),
  (
    '9e220000-0000-4000-8000-000000000013',
    '9e220000-0000-4000-8000-000000000001',
    'Private review', 'TAX-ROLLOUT-PRIVATE', 3000, 3000, 1000, null,
    'product', false, 'inventory', false, 0, 0, 0, 0,
    true, false, false
  ),
  (
    '9e220000-0000-4000-8000-000000000020',
    '9e220000-0000-4000-8000-000000000002',
    'Drift candidate', 'TAX-ROLLOUT-DRIFT', 1500, 1500, 500, null,
    'product', false, 'inventory', false, 0, 0, 0, 0,
    true, true, true
  );

create temp table product_tax_rollout_contract (
  tenant_id uuid primary key,
  expected_count integer not null,
  member_sha256 text not null,
  snapshot_sha256 text not null
) on commit drop;

insert into product_tax_rollout_contract
select
  product.tenant_id,
  count(*)::integer,
  encode(extensions.digest(
    string_agg(product.id::text, ',' order by product.id),
    'sha256'
  ), 'hex'),
  encode(extensions.digest(string_agg(
    concat_ws(
      '|',
      product.id::text,
      product.tenant_id::text,
      product.product_type,
      product.price::text,
      product.is_active::text,
      product.is_published::text,
      product.show_on_website::text,
      coalesce(product.tax_rate::text, 'null')
    ),
    E'\n' order by product.id
  ), 'sha256'), 'hex')
from public.products product
where product.tenant_id = '9e220000-0000-4000-8000-000000000001'
  and product.tax_rate is null
  and product.is_active is true
  and product.is_published is true
  and product.show_on_website is true
  and product.price > 0
  and product.product_type in ('product', 'service')
group by product.tenant_id;

select throws_ok(
  $$
    select public.apply_curated_product_tax_classification_batch(
      '9e220000-0000-4000-8000-000000000002',
      'drift-test-v1',
      1,
      repeat('0', 64),
      repeat('1', 64),
      19,
      'pg_tap',
      'Must fail closed'
    )
  $$,
  '23514',
  null,
  'wrong snapshot hashes fail before any product mutation'
);
select is(
  (
    select tax_rate
      from public.products
     where id = '9e220000-0000-4000-8000-000000000020'
  ),
  null::numeric,
  'failed preflight leaves the drift candidate unclassified'
);
select is(
  (
    select count(*)::integer
      from public.product_tax_classification_batches
     where tenant_id = '9e220000-0000-4000-8000-000000000002'
  ),
  0,
  'failed preflight leaves no false batch receipt'
);

create temp table product_tax_rollout_results (
  sequence integer primary key,
  payload jsonb not null
) on commit drop;

insert into product_tax_rollout_results
select 1, public.apply_curated_product_tax_classification_batch(
  contract.tenant_id,
  'pg-tap-public-catalog-v1',
  contract.expected_count,
  contract.member_sha256,
  contract.snapshot_sha256,
  19,
  'pg_tap',
  'Reviewed public product and service fixtures'
)
from product_tax_rollout_contract contract;

select is(
  (select payload->>'replayed' from product_tax_rollout_results where sequence = 1),
  'false',
  'first curated command reports a real application'
);
select is(
  (select (payload->>'applied_product_count')::integer
     from product_tax_rollout_results where sequence = 1),
  2,
  'only the two exact eligible fixtures are classified'
);
select is(
  (
    select string_agg(id::text || ':' || tax_rate::text, '|' order by id)
      from public.products
     where id in (
       '9e220000-0000-4000-8000-000000000010',
       '9e220000-0000-4000-8000-000000000011'
     )
  ),
  '9e220000-0000-4000-8000-000000000010:19.00|9e220000-0000-4000-8000-000000000011:19.00',
  'eligible public product and service now carry explicit 19% IVA'
);
select is(
  (
    select count(*)::integer
      from public.products
     where id in (
       '9e220000-0000-4000-8000-000000000012',
       '9e220000-0000-4000-8000-000000000013'
     )
       and tax_rate is null
  ),
  2,
  'zero-price and non-public fixtures remain explicitly deferred'
);
select is(
  (
    select applied_product_count
      from public.product_tax_classification_batches
     where tenant_id = '9e220000-0000-4000-8000-000000000001'
       and batch_key = 'pg-tap-public-catalog-v1'
  ),
  2,
  'batch receipt records the exact applied count'
);
select is(
  (
    select count(*)::integer
      from public.product_tax_classification_events
     where tenant_id = '9e220000-0000-4000-8000-000000000001'
       and batch_key = 'pg-tap-public-catalog-v1'
       and before_tax_rate is null
       and after_tax_rate = 19
  ),
  2,
  'each classified product has immutable before/after evidence'
);
select ok(
  (
    select bool_and(
      product_snapshot->>'member_sha256' = contract.member_sha256
      and product_snapshot->>'snapshot_sha256' = contract.snapshot_sha256
    )
      from public.product_tax_classification_events event
      cross join product_tax_rollout_contract contract
     where event.tenant_id = contract.tenant_id
       and event.batch_key = 'pg-tap-public-catalog-v1'
  ),
  'each event carries the frozen aggregate catalog fingerprint'
);

insert into product_tax_rollout_results
select 2, public.apply_curated_product_tax_classification_batch(
  contract.tenant_id,
  'pg-tap-public-catalog-v1',
  contract.expected_count,
  contract.member_sha256,
  contract.snapshot_sha256,
  19,
  'pg_tap',
  'Reviewed public product and service fixtures'
)
from product_tax_rollout_contract contract;

select is(
  (select payload->>'replayed' from product_tax_rollout_results where sequence = 2),
  'true',
  'exact command replay returns the immutable receipt'
);
select is(
  (
    select count(*)::integer
      from public.product_tax_classification_events
     where tenant_id = '9e220000-0000-4000-8000-000000000001'
       and batch_key = 'pg-tap-public-catalog-v1'
  ),
  2,
  'exact replay creates no duplicate tax evidence'
);
select throws_ok(
  $$
    update public.product_tax_classification_batches
       set reason = 'rewritten'
     where batch_key = 'pg-tap-public-catalog-v1'
  $$,
  '55000',
  'Product tax-classification audit evidence is append-only',
  'batch receipts cannot be rewritten'
);
select throws_ok(
  $$
    delete from public.product_tax_classification_events
     where batch_key = 'pg-tap-public-catalog-v1'
  $$,
  '55000',
  'Product tax-classification audit evidence is append-only',
  'per-product tax evidence cannot be deleted'
);

insert into product_tax_rollout_results
select 3, jsonb_build_object(
  'order_id',
  public.create_public_online_order(
    jsonb_build_object(
      'tenant_id', '9e220000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', 'tax-rollout-history-v1',
      'customer_email', 'tax-rollout@example.invalid',
      'customer_name', 'Tax Rollout Customer',
      'delivery_type', 'pickup',
      'payment_method', 'transfer'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '9e220000-0000-4000-8000-000000000010',
      'quantity', 1
    ))
  )
);

update public.products
   set tax_rate = 0
 where id = '9e220000-0000-4000-8000-000000000010';

select is(
  (
    select tax_rate
      from public.products
     where id = '9e220000-0000-4000-8000-000000000010'
  ),
  0::numeric,
  'a later explicit classification can change the current product'
);
select is(
  (
    select source
      from public.product_tax_classification_events
     where product_id = '9e220000-0000-4000-8000-000000000010'
     order by occurred_at desc, id desc
     limit 1
  ),
  'direct_product_write',
  'future direct changes retain explicit provenance instead of disappearing'
);
select is(
  (
    select item.tax_rate
      from public.online_order_items item
      join product_tax_rollout_results result on result.sequence = 3
     where item.order_id = (result.payload->>'order_id')::uuid
  ),
  19::numeric,
  'later product changes never rewrite the immutable historical order-line tax snapshot'
);
select is(
  (
    select count(*)::integer
      from public.product_tax_classification_events
     where product_id = '9e220000-0000-4000-8000-000000000010'
  ),
  2,
  'the product has one batch event and one later classification-change event'
);

select * from finish();

rollback;
