begin;

select no_plan();

create role public_catalog_facets_untrusted nologin;

select ok(
  (
    select not attribute.attnotnull
    from pg_attribute attribute
    where attribute.attrelid = 'public.product_brands'::regclass
      and attribute.attname = 'tenant_id'
      and not attribute.attisdropped
  ),
  'canonical brand rows can be global because product_brands.tenant_id is nullable'
);
select ok(
  exists (
    select 1
    from pg_constraint constraint_record
    join pg_attribute attribute
      on attribute.attrelid = constraint_record.conrelid
     and attribute.attname = 'name'
     and not attribute.attisdropped
    where constraint_record.conrelid = 'public.product_brands'::regclass
      and constraint_record.contype = 'u'
      and constraint_record.conkey = array[attribute.attnum]::smallint[]
  ),
  'the global canonical brand registry keeps one unique row per name'
);
select ok(
  not exists (
    select 1
    from pg_constraint constraint_record
    where constraint_record.conrelid = 'public.product_brands'::regclass
      and constraint_record.conname = 'product_brands_tenant_id_name_key'
  ),
  'the stale tenant-scoped brand-name uniqueness contract is absent'
);

select has_function(
  'public',
  'get_public_products_faceted_v1',
  array[
    'uuid', 'uuid[]', 'text', 'text', 'boolean', 'uuid[]', 'numeric',
    'numeric', 'text', 'integer', 'integer'
  ],
  'public catalog exposes a versioned server-paged facet query'
);
select has_function(
  'public',
  'get_public_product_facets_v1',
  array[
    'uuid', 'uuid[]', 'text', 'text', 'boolean', 'uuid[]', 'numeric',
    'numeric'
  ],
  'public catalog exposes versioned facet metadata'
);
select ok(
  (
    select
      count(*) = 5
      and bool_and(owner_role.rolname = 'postgres')
      and bool_and(procedure_record.prosecdef)
      and bool_and(
        procedure_record.proconfig = array['search_path=public']::text[]
      )
    from pg_proc procedure_record
    join pg_roles owner_role on owner_role.oid = procedure_record.proowner
    where procedure_record.oid in (
      'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure,
      'public.online_product_available_quantity(uuid,uuid)'::regprocedure,
      'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure,
      'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)'::regprocedure,
      'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)'::regprocedure
    )
  ),
  'catalog RPCs are postgres-owned SECURITY DEFINER functions with an exact trusted search_path'
);
select ok(
  not has_schema_privilege(
    'public_catalog_facets_untrusted',
    'public',
    'CREATE'
  ),
  'an untrusted role cannot shadow SECURITY DEFINER dependencies in public'
);
select ok(
  not has_function_privilege(
    'public_catalog_facets_untrusted',
    'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'public_catalog_facets_untrusted',
    'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'public_catalog_facets_untrusted',
    'public.online_product_available_quantity(uuid,uuid)',
    'EXECUTE'
  ),
  'PUBLIC grants do not leak the facet facades or private availability kernel to an untrusted role'
);
select ok(
  has_function_privilege(
    'anon',
    'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)',
    'EXECUTE'
  ),
  'anonymous storefront visitors can query paged public facet results'
);
select ok(
  has_function_privilege(
    'anon',
    'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)',
    'EXECUTE'
  ),
  'anonymous storefront visitors can read public facet metadata'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)',
    'EXECUTE'
  ),
  'authenticated storefront visitors can query paged public facet results'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)',
    'EXECUTE'
  ),
  'authenticated storefront visitors can read public facet metadata'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)',
    'EXECUTE'
  ),
  'the public facet facade grants execution only to visitor roles'
);
select ok(
  position(
    'canonical_brand.tenant_id is null' in pg_get_functiondef(
      'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)'::regprocedure
    )
  ) > 0,
  'facet labels explicitly accept canonical global brand rows'
);
select ok(
  position(
    'canonical_category.tenant_id = p_tenant_id' in pg_get_functiondef(
      'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)'::regprocedure
    )
  ) > 0,
  'category facet labels are resolved through the same tenant canonical category'
);
select ok(
  position(
    'p_category_ids := null' in pg_get_functiondef(
      'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)'::regprocedure
    )
  ) > 0,
  'category option counts deliberately exclude their own active category selection'
);
select results_eq(
  $test$
    with raw_source as (
      select lower(procedure_record.prosrc) as body
      from pg_proc procedure_record
      where procedure_record.oid =
        'public.get_public_product_facets_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric)'::regprocedure
    ), without_comments as (
      select regexp_replace(
        regexp_replace(
          body,
          E'/\\*([^*]|\\*+[^*/])*\\*+/',
          ' ',
          'g'
        ),
        E'--[^\\r\\n]*',
        ' ',
        'g'
      ) as body
      from raw_source
    ), lexical_source as (
      select regexp_replace(
        body,
        $quoted$'(''|[^'])*'$quoted$,
        ' ',
        'g'
      ) as body
      from without_comments
    )
    select
      regexp_count(
        body,
        '(^|[^[:alnum:]_])"?get_public_products"?[[:space:]]*[(]'
      )::integer,
      regexp_count(
        body,
        '(^|[^[:alnum:]_])"?public"?[[:space:]]*[.][[:space:]]*"?get_public_products"?[[:space:]]*[(]'
      )::integer,
      regexp_count(
        body,
        '(^|[^[:alnum:]_])p_category_ids[[:space:]]*:=[[:space:]]*null([^[:alnum:]_]|$)'
      )::integer,
      regexp_count(
        body,
        '(^|[^[:alnum:]_])"?get_public_products_without_inventory_reservations"?[[:space:]]*[(]'
      )::integer
    from lexical_source
  $test$,
  $expected$ values (1, 1, 1, 0) $expected$,
  'facet metadata has one qualified canonical call, no category scope and no private-base bypass'
);
select ok(
  position(
    'public.get_public_products(' in pg_get_functiondef(
      'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)'::regprocedure
    )
  ) > 0,
  'faceted paging delegates public eligibility and availability to the canonical RPC'
);
select ok(
  position(
    'get_public_products_without_inventory_reservations' in pg_get_functiondef(
      'public.get_public_products_faceted_v1(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,text,integer,integer)'::regprocedure
    )
  ) = 0,
  'faceted paging cannot bypass the reservation-aware canonical RPC'
);
-- The behavioral reservation assertions below protect the public result. This
-- cheap structural guard separately prevents the N+1 scalar implementation
-- that the set-based migration was introduced to remove.
select ok(
  position('online_product_available_quantity(' in installed.body) = 0
  and position('online_order_inventory_reservations' in installed.body) > 0
  and position('product_set_components' in installed.body) > 0,
  'the installed canonical public RPC keeps reservation-aware availability set-based'
)
from (
  select pg_get_functiondef(
    'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
  ) as body
) installed;
select has_function(
  'public',
  'get_public_products_without_inventory_reservations',
  array[
    'uuid', 'uuid[]', 'uuid[]', 'text', 'text', 'text', 'boolean', 'text',
    'integer', 'integer'
  ],
  'the reservation-aware public RPC keeps its search and ranking base private'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.online_product_available_quantity(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.online_product_available_quantity(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.online_product_available_quantity(uuid,uuid)',
    'EXECUTE'
  ),
  'visitor and service roles cannot bypass reservation-aware availability or its private base'
);
select ok(
  has_function_privilege(
    'anon',
    'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE'
  ),
  'the canonical reservation-aware wrapper retains its deployed callers'
);

insert into public.tenants (id, shop_name, currency, timezone)
values
  (
    '7fac0000-0000-4000-8000-000000000001',
    'Public Catalog Facet Test',
    'CLP',
    'America/Santiago'
  ),
  (
    '7fac0000-0000-4000-8000-000000000002',
    'Public Catalog Facet Other Tenant',
    'CLP',
    'America/Santiago'
  ),
  (
    '7fac0000-0000-4000-8000-000000000003',
    'Public Catalog Global Brand Tenant',
    'CLP',
    'America/Santiago'
  );

-- Tenant bootstrap seeds dependent catalogs and temporarily impersonates each
-- new tenant. Product fixtures exercise public catalog selection, not the
-- unrelated manual-stock audit trigger.
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.skip_stock_adjustment_trigger', 'true', true);

insert into public.website_settings (tenant_id, key, value)
values (
  '7fac0000-0000-4000-8000-000000000001',
  'product_visibility_stock_policy',
  'all'
)
on conflict (tenant_id, key) do update
set value = excluded.value;

insert into public.product_categories (
  id, tenant_id, name, full_path, parent_id, level, is_active,
  show_on_website, sort_order
)
values
  (
    '7fac3000-0000-4000-8000-000000000001',
    '7fac0000-0000-4000-8000-000000000001',
    'Transmisión',
    'Componentes / Transmisión',
    null,
    0,
    true,
    true,
    10
  ),
  (
    '7fac3000-0000-4000-8000-000000000002',
    '7fac0000-0000-4000-8000-000000000001',
    'Cadenas',
    'Componentes / Transmisión / Cadenas',
    '7fac3000-0000-4000-8000-000000000001',
    1,
    true,
    false,
    20
  ),
  (
    '7fac3000-0000-4000-8000-000000000003',
    '7fac0000-0000-4000-8000-000000000001',
    'Ruedas',
    'Componentes / Ruedas',
    null,
    0,
    true,
    true,
    30
  ),
  (
    '7fac3000-0000-4000-8000-000000000004',
    '7fac0000-0000-4000-8000-000000000002',
    'Categoría de otro tenant',
    'Categoría de otro tenant',
    null,
    0,
    true,
    true,
    10
  );

insert into public.product_brands (id, tenant_id, name, is_active)
values
  (
    '7fac1000-0000-4000-8000-000000000001',
    '7fac0000-0000-4000-8000-000000000001',
    'Andes Components',
    true
  ),
  (
    '7fac1000-0000-4000-8000-000000000002',
    '7fac0000-0000-4000-8000-000000000001',
    'Pacífico Cycling',
    true
  ),
  (
    '7fac1000-0000-4000-8000-000000000003',
    '7fac0000-0000-4000-8000-000000000002',
    'Other Tenant Brand',
    true
  );

insert into public.product_brands (id, tenant_id, name, is_active)
values (
  '7fac1000-0000-4000-8000-000000000004',
  null,
  'Global Components',
  true
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  category_id, category_name, brand_id, brand,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  product_type, is_service, purchase_treatment, track_stock,
  is_active, is_published, show_on_website
)
values
  (
    '7fac2000-0000-4000-8000-000000000001',
    '7fac0000-0000-4000-8000-000000000001',
    'Andes entry product',
    'FACET-ANDES-ENTRY',
    900, 1000, 400, 19,
    '7fac3000-0000-4000-8000-000000000001',
    'Stale transmission label',
    '7fac1000-0000-4000-8000-000000000001',
    'Andes Components',
    3, 3, 0, 100,
    'product', false, 'inventory', true,
    true, true, true
  ),
  (
    '7fac2000-0000-4000-8000-000000000002',
    '7fac0000-0000-4000-8000-000000000001',
    'Andes premium product',
    'FACET-ANDES-PREMIUM',
    5000, 1500, 600, 19,
    '7fac3000-0000-4000-8000-000000000002',
    'Stale chain label',
    '7fac1000-0000-4000-8000-000000000001',
    'Andes Components',
    2, 2, 0, 100,
    'product', false, 'inventory', true,
    true, true, true
  ),
  (
    '7fac2000-0000-4000-8000-000000000003',
    '7fac0000-0000-4000-8000-000000000001',
    'Pacific product',
    'FACET-PACIFIC',
    3000, null, 1200, 19,
    '7fac3000-0000-4000-8000-000000000003',
    'Stale wheel label',
    '7fac1000-0000-4000-8000-000000000002',
    'Pacífico Cycling',
    5, 5, 0, 100,
    'product', false, 'inventory', true,
    true, true, true
  ),
  (
    '7fac2000-0000-4000-8000-000000000004',
    '7fac0000-0000-4000-8000-000000000002',
    'Private tenant product',
    'FACET-OTHER-TENANT',
    1200, 1200, 500, 19,
    '7fac3000-0000-4000-8000-000000000004',
    'Stale other tenant label',
    '7fac1000-0000-4000-8000-000000000003',
    'Other Tenant Brand',
    5, 5, 0, 100,
    'product', false, 'inventory', true,
    true, true, true
  ),
  (
    '7fac2000-0000-4000-8000-000000000005',
    '7fac0000-0000-4000-8000-000000000001',
    'Pacific unavailable product',
    'FACET-PACIFIC-OUT',
    4000, null, 1200, 19,
    '7fac3000-0000-4000-8000-000000000003',
    'Stale wheel label',
    '7fac1000-0000-4000-8000-000000000002',
    'Pacífico Cycling',
    0, 0, 0, 100,
    'product', false, 'inventory', true,
    true, true, true
  ),
  (
    '7fac2000-0000-4000-8000-000000000007',
    '7fac0000-0000-4000-8000-000000000001',
    'Uncategorized public product',
    'FACET-UNCATEGORIZED',
    2500, 2500, 1000, 19,
    null,
    null,
    null,
    null,
    1, 1, 0, 100,
    'product', false, 'inventory', true,
    true, true, true
  );

-- Deliberately drift one denormalized product label. Facet labels must still
-- come from the canonical same-tenant category row identified by UUID.
update public.products
set category_name = 'Stale chain label'
where id = '7fac2000-0000-4000-8000-000000000002';

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  brand_id, brand,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  product_type, is_service, purchase_treatment, track_stock,
  is_active, is_published, show_on_website
)
values (
  '7fac2000-0000-4000-8000-000000000006',
  '7fac0000-0000-4000-8000-000000000003',
  'Global branded product',
  'FACET-GLOBAL-BRAND',
  2500,
  2500,
  900,
  19,
  '7fac1000-0000-4000-8000-000000000004'::uuid,
  'Stale product brand label',
  2,
  2,
  0,
  100,
  'product',
  false,
  'inventory',
  true,
  true,
  true,
  true
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000003',
      p_only_in_stock := true
    ) facet
    where facet.facet_key = 'brand'
  $$,
  $$
    values (
      '7fac1000-0000-4000-8000-000000000004'::text,
      'Global Components'::text,
      1::bigint
    )
  $$,
  'global canonical brand rows resolve by stable ID and canonical label'
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := true
    ) facet
    where facet.facet_key = 'category'
    order by facet.value_label, facet.value_id
  $$,
  $$
    values
      (
        '7fac3000-0000-4000-8000-000000000002'::text,
        'Cadenas'::text,
        1::bigint
      ),
      (
        '7fac3000-0000-4000-8000-000000000003'::text,
        'Ruedas'::text,
        1::bigint
      ),
      (
        '7fac3000-0000-4000-8000-000000000001'::text,
        'Transmisión'::text,
        1::bigint
      )
  $$,
  'category counts use stable IDs, canonical labels and visitor availability'
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'category'
    order by facet.value_label, facet.value_id
  $$,
  $$
    values
      (
        '7fac3000-0000-4000-8000-000000000002'::text,
        'Cadenas'::text,
        1::bigint
      ),
      (
        '7fac3000-0000-4000-8000-000000000003'::text,
        'Ruedas'::text,
        2::bigint
      ),
      (
        '7fac3000-0000-4000-8000-000000000001'::text,
        'Transmisión'::text,
        1::bigint
      )
  $$,
  'category counts include rule-allowed unavailable products only when the visitor does not narrow availability'
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false,
      p_brand_ids := array[
        '7fac1000-0000-4000-8000-000000000001'::uuid
      ],
      p_min_price := 1000,
      p_max_price := 1600
    ) facet
    where facet.facet_key = 'category'
    order by facet.value_label, facet.value_id
  $$,
  $$
    values
      (
        '7fac3000-0000-4000-8000-000000000002'::text,
        'Cadenas'::text,
        1::bigint
      ),
      (
        '7fac3000-0000-4000-8000-000000000001'::text,
        'Transmisión'::text,
        1::bigint
      )
  $$,
  'category counts apply active brand and effective storefront price filters'
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_search_term := 'Pacific',
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'category'
  $$,
  $$
    values (
      '7fac3000-0000-4000-8000-000000000003'::text,
      'Ruedas'::text,
      2::bigint
    )
  $$,
  'category counts apply the same canonical search result as product paging'
);

select results_eq(
  $$
    select facet.value_id, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_category_ids := array[
        '7fac3000-0000-4000-8000-000000000003'::uuid
      ],
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'category'
    order by facet.value_id
  $$,
  $$
    values
      ('7fac3000-0000-4000-8000-000000000001'::text, 1::bigint),
      ('7fac3000-0000-4000-8000-000000000002'::text, 1::bigint),
      ('7fac3000-0000-4000-8000-000000000003'::text, 2::bigint)
  $$,
  'category options exclude the active category while preserving all other filters'
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_category_ids := array[
        '7fac3000-0000-4000-8000-000000000003'::uuid
      ],
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'brand'
  $$,
  $$
    values (
      '7fac1000-0000-4000-8000-000000000002'::text,
      'Pacífico Cycling'::text,
      2::bigint
    )
  $$,
  'brand options still respect the active category after the one-scan projection'
);

select results_eq(
  $$
    select facet.range_min, facet.range_max, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_category_ids := array[
        '7fac3000-0000-4000-8000-000000000003'::uuid
      ],
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'price'
  $$,
  $$ values (3000::numeric, 4000::numeric, 2::bigint) $$,
  'price metadata still respects the active category after the one-scan projection'
);

select results_eq(
  $$
    select
      facet.facet_key,
      facet.value_label,
      facet.item_count,
      facet.range_min,
      facet.range_max
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_category_ids := array[
        '7fac3000-0000-4000-8000-000000000003'::uuid
      ],
      p_only_in_stock := false,
      p_brand_ids := array[
        '7fac1000-0000-4000-8000-000000000002'::uuid
      ],
      p_min_price := 3500,
      p_max_price := 4500
    ) facet
    order by facet.facet_key, facet.value_label nulls first
  $$,
  $$
    values
      ('brand'::text, 'Pacífico Cycling'::text, 1::bigint, null::numeric, null::numeric),
      ('category'::text, 'Ruedas'::text, 1::bigint, null::numeric, null::numeric),
      ('price'::text, null::text, 2::bigint, 3000::numeric, 4000::numeric),
      ('summary'::text, null::text, 1::bigint, null::numeric, null::numeric)
  $$,
  'combined filters preserve every self-excluding facet mask from one canonical universe'
);

select results_eq(
  $$
    select
      facet.facet_key,
      facet.item_count,
      facet.range_min,
      facet.range_max
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false,
      p_min_price := 5000,
      p_max_price := 1000
    ) facet
    order by facet.facet_key
  $$,
  $$
    values
      ('price'::text, 0::bigint, null::numeric, null::numeric),
      ('summary'::text, 0::bigint, null::numeric, null::numeric)
  $$,
  'invalid metadata ranges fail closed while preserving zero price and summary rows'
);

select is(
  (
    select count(*)::integer
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'category'
      and facet.value_id = '7fac3000-0000-4000-8000-000000000004'
  ),
  0,
  'category facets never expose another tenant category identity'
);

select is(
  (
    select facet.item_count::integer
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'category'
      and facet.value_id = '7fac3000-0000-4000-8000-000000000002'
  ),
  1,
  'active hidden descendants retain direct counts for folding into a visible ancestor'
);

select results_eq(
  $$
    select facet.value_id, facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_category_ids := array[
        '7fac3000-0000-4000-8000-000000000003'::uuid
      ],
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'summary'
  $$,
  $$ values (null::text, null::text, 5::bigint) $$,
  'summary counts the complete secondary-filtered universe, including uncategorized products and excluding the active category facet'
);

select results_eq(
  $$
    select facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := true,
      p_brand_ids := array[
        '7fac1000-0000-4000-8000-000000000001'::uuid
      ],
      p_min_price := 1000,
      p_max_price := 1600
    ) facet
    where facet.facet_key = 'summary'
  $$,
  $$ values (2::bigint) $$,
  'summary applies search/type/brand/price/visitor-availability filters before counting'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_brand_ids := array[
        '7fac1000-0000-4000-8000-000000000001'::uuid
      ],
      p_only_in_stock := true,
      p_limit := 20
    )
  ),
  2,
  'a single stable brand ID filters the canonical public result'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_brand_ids := array[
        '7fac1000-0000-4000-8000-000000000001'::uuid,
        '7fac1000-0000-4000-8000-000000000002'::uuid
      ],
      p_only_in_stock := true,
      p_limit := 20
    )
  ),
  3,
  'multiple brand IDs use OR semantics inside the brand facet'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := true,
      p_limit := 20
    )
  ),
  4,
  'canonical public results never include another tenant product'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false,
      p_limit := 20
    )
  ),
  5,
  'the visitor can include every product allowed by the public stock rule'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := true,
      p_limit := 20
    )
  ),
  4,
  'the visitor availability facet narrows the allowed universe by canonical stock'
);

select results_eq(
  $$
    select facet.range_min, facet.range_max, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := false
    ) facet
    where facet.facet_key = 'price'
  $$,
  $$ values (1000::numeric, 4000::numeric, 5::bigint) $$,
  'facet metadata uses the same visitor availability universe as product paging'
);

select results_eq(
  $$
    select product.price::numeric, product.total_count::bigint
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_min_price := 1000,
      p_max_price := 1500,
      p_only_in_stock := true,
      p_sort_by := 'price_asc',
      p_limit := 20
    ) product
    order by product.price
  $$,
  $$ values (1000::numeric, 2::bigint), (1500::numeric, 2::bigint) $$,
  'price filtering is inclusive and uses website_price before base price'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_min_price := 2000,
      p_max_price := 1000,
      p_only_in_stock := true
    )
  ),
  0,
  'invalid price ranges fail closed'
);

select results_eq(
  $$
    select facet.value_label, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_min_price := 1000,
      p_max_price := 1600,
      p_only_in_stock := true
    ) facet
    where facet.facet_key = 'brand'
    order by facet.value_label
  $$,
  $$ values ('Andes Components'::text, 2::bigint) $$,
  'brand option counts respect the active price facet'
);

select results_eq(
  $$
    select facet.range_min, facet.range_max, facet.item_count
    from public.get_public_product_facets_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_brand_ids := array[
        '7fac1000-0000-4000-8000-000000000001'::uuid
      ],
      p_only_in_stock := true
    ) facet
    where facet.facet_key = 'price'
  $$,
  $$ values (1000::numeric, 1500::numeric, 2::bigint) $$,
  'price bounds respect the active brand facet and effective website prices'
);

select results_eq(
  $$
    select product.sku, product.total_count
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := true,
      p_limit := 0,
      p_offset := 0
    ) product
  $$,
  $$ values ('FACET-ANDES-ENTRY'::text, 4::bigint) $$,
  'zero page size clamps to one row so a non-empty result still carries total_count'
);

select results_eq(
  $$
    select product.sku, product.total_count
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_only_in_stock := true,
      p_limit := 2,
      p_offset := 999
    ) product
    order by product.sku
  $$,
  $$
    values
      ('FACET-PACIFIC'::text, 4::bigint),
      ('FACET-UNCATEGORIZED'::text, 4::bigint)
  $$,
  'a stale offset clamps to the final valid page and preserves total_count'
);

create temp table public_catalog_reservation_order (
  id uuid primary key
) on commit drop;

insert into public_catalog_reservation_order (id)
select public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '7fac0000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'facet-reservation-to-zero-001',
    'customer_email', 'facet-reservation@example.invalid',
    'customer_name', 'Facet Reservation',
    'customer_address', 'Test pickup',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '7fac2000-0000-4000-8000-000000000001',
    'quantity', 3
  ))
);

select is(
  public.online_product_available_quantity(
    '7fac0000-0000-4000-8000-000000000001',
    '7fac2000-0000-4000-8000-000000000001'
  ),
  0,
  'an active checkout reservation can reduce a real published product to zero availability'
);

select is(
  (
    select count(*)::integer
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_search_term := 'FACET-ANDES-ENTRY',
      p_only_in_stock := true
    )
  ),
  0,
  'the availability facet excludes a product whose physical stock is fully reserved'
);

select results_eq(
  $$
    select product.stock_quantity, product.total_count
    from public.get_public_products_faceted_v1(
      p_tenant_id := '7fac0000-0000-4000-8000-000000000001',
      p_search_term := 'FACET-ANDES-ENTRY',
      p_only_in_stock := false
    ) product
  $$,
  $$ values (0::integer, 1::bigint) $$,
  'the wider visitor view exposes reservation-aware zero rather than physical stock'
);

select finish();

rollback;
