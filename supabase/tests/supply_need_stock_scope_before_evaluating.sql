begin;
-- Synthetic tenant setup may emit notices from unrelated seed/broadcast
-- triggers. SQL errors and pgTAP assertions remain visible.
set local client_min_messages = error;
select no_plan();

-- Local-only planner regression. The context and detail dependencies are
-- replaced inside this rolled-back transaction, keeping their STABLE promise
-- and cost. A VOLATILE stub would prevent the old CTE folding by itself and
-- make the test pass for the wrong reason. Counters observe executions, never
-- determine their returned values. Real matching/tenant behavior is covered
-- by supply_need_family_resolution_b1 and the production JSON read-back.
insert into public.tenants(id, shop_name, currency, timezone) values
  ('99e10000-0000-4000-8000-000000000001', 'Stock scope test', 'CLP', 'UTC'),
  ('99e10000-0000-4000-8000-000000000002', 'Other scope test', 'CLP', 'UTC');

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values
  ('99e10000-0000-4000-8000-000000000011',
   '99e10000-0000-4000-8000-000000000001', 'Scope', 'Scope', 1, true),
  ('99e10000-0000-4000-8000-000000000012',
   '99e10000-0000-4000-8000-000000000001', 'Child', 'Scope / Child', 2, true),
  ('99e10000-0000-4000-8000-000000000013',
   '99e10000-0000-4000-8000-000000000001', 'Inactive', 'Scope / Inactive', 2, false),
  ('99e10000-0000-4000-8000-000000000014',
   '99e10000-0000-4000-8000-000000000001', 'Unrelated', 'Unrelated', 1, true),
  ('99e10000-0000-4000-8000-000000000015',
   '99e10000-0000-4000-8000-000000000001', 'Empty', 'Empty', 1, true);
update public.product_categories
set parent_id = '99e10000-0000-4000-8000-000000000011'
where id in (
  '99e10000-0000-4000-8000-000000000012',
  '99e10000-0000-4000-8000-000000000013'
);

insert into public.products(
  id, tenant_id, name, sku, category_id, is_active, price,
  is_service, product_type
) values
  ('99e10000-0000-4000-8000-000000000101',
   '99e10000-0000-4000-8000-000000000001', 'Strong', 'scope-101',
   '99e10000-0000-4000-8000-000000000011', true, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000102',
   '99e10000-0000-4000-8000-000000000001', 'Conflict', 'scope-102',
   '99e10000-0000-4000-8000-000000000012', true, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000103',
   '99e10000-0000-4000-8000-000000000001', 'Unverified', 'scope-103',
   '99e10000-0000-4000-8000-000000000011', true, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000104',
   '99e10000-0000-4000-8000-000000000001', 'Weak', 'scope-104',
   '99e10000-0000-4000-8000-000000000012', true, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000105',
   '99e10000-0000-4000-8000-000000000001', 'Disabled product', 'scope-105',
   '99e10000-0000-4000-8000-000000000011', false, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000106',
   '99e10000-0000-4000-8000-000000000001', 'Disabled category', 'scope-106',
   '99e10000-0000-4000-8000-000000000013', true, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000107',
   '99e10000-0000-4000-8000-000000000001', 'Service flag', 'scope-107',
   '99e10000-0000-4000-8000-000000000011', true, 100, true, 'service'),
  ('99e10000-0000-4000-8000-000000000108',
   '99e10000-0000-4000-8000-000000000002', 'Other tenant', 'scope-108',
   null, true, 100, false, 'product'),
  ('99e10000-0000-4000-8000-000000000110',
   '99e10000-0000-4000-8000-000000000001', 'Exact in other family', 'scope-110',
   '99e10000-0000-4000-8000-000000000014', true, 100, false, 'product');

insert into public.products(
  id, tenant_id, name, sku, category_id, is_active, price,
  is_service, product_type
)
select
  ('99e10000-0000-4000-8000-' || lpad(number::text, 12, '0'))::uuid,
  '99e10000-0000-4000-8000-000000000001'::uuid,
  'Unrelated product ' || number, 'scope-unrelated-' || number,
  '99e10000-0000-4000-8000-000000000014'::uuid,
  true, 100, false, 'product'
from generate_series(1000, 1499) number;
analyze public.products;

create temporary sequence stock_scope_detail_calls;
create temporary sequence stock_scope_outside_calls;

create or replace function public.supply_need_resolution_context_internal_v1(
  p_tenant_id uuid, p_need_id uuid
)
returns table (
  need_id uuid, need_version bigint, quantity numeric, unit text,
  product_id uuid, identity_state text, supply_state text,
  internal_stock_rejection_reason text, revision_no bigint,
  category_id uuid, constraints jsonb
)
language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  return query select p_need_id, 1::bigint, 1::numeric, 'unit'::text,
    case when p_need_id = '99e10000-0000-4000-8000-000000000203'::uuid
      then '99e10000-0000-4000-8000-000000000110'::uuid else null::uuid end,
    case when p_need_id = '99e10000-0000-4000-8000-000000000203'::uuid
      then 'confirmed'::text else 'unresolved'::text end,
    'open'::text, null::text, 1::bigint,
    case
      when p_need_id = '99e10000-0000-4000-8000-000000000202'::uuid
        then null::uuid
      when p_need_id = '99e10000-0000-4000-8000-000000000204'::uuid
        then '99e10000-0000-4000-8000-000000000015'::uuid
      else '99e10000-0000-4000-8000-000000000011'::uuid
    end,
    '[{"field":"scope_probe","operator":"eq","values":[1]},
      {"kind":"ranking_profile","value":"balanced"}]'::jsonb;
end;
$$;

create or replace function public.supply_need_match_detail_internal_v1(
  p_tenant_id uuid, p_product_id uuid, p_predicates jsonb
)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform nextval('pg_temp.stock_scope_detail_calls');
  if p_product_id not in (
    '99e10000-0000-4000-8000-000000000101'::uuid,
    '99e10000-0000-4000-8000-000000000102'::uuid,
    '99e10000-0000-4000-8000-000000000103'::uuid,
    '99e10000-0000-4000-8000-000000000104'::uuid
  ) then
    perform nextval('pg_temp.stock_scope_outside_calls');
  end if;
  return jsonb_build_array(jsonb_build_object(
    'field', 'scope_probe',
    'source', case p_product_id
      when '99e10000-0000-4000-8000-000000000102'::uuid then 'conflict'
      when '99e10000-0000-4000-8000-000000000103'::uuid then 'unresolved'
      when '99e10000-0000-4000-8000-000000000104'::uuid then 'identity_fallback'
      else 'product_spec'
    end
  ));
end;
$$;

select is((select provolatile::text from pg_proc where oid =
  'public.supply_need_match_detail_internal_v1(uuid,uuid,jsonb)'::regprocedure),
  's', 'instrumentation preserves STABLE so the old folding remains possible');

create temporary table scope_result as
select public.supply_need_eligible_products_internal_v1(
  '99e10000-0000-4000-8000-000000000001',
  '99e10000-0000-4000-8000-000000000201'
) as body;

select is((select body ->> 'status' from scope_result), 'ok', 'family resolves');
select is((select (body ->> 'universeSize')::int from scope_result), 4,
  'universe is the active family, including its active child, before conflicts');
select is((select (body ->> 'predicateCount')::int from scope_result), 1,
  'commercial/ranking entries do not become technical predicates');
select is((select case when is_called then last_value else 0 end
  from stock_scope_detail_calls), 4::bigint,
  'detail is evaluated exactly once for each scoped product, including conflict');
select is((select case when is_called then last_value else 0 end
  from stock_scope_outside_calls), 0::bigint,
  'unrelated family, disabled products/categories, services and other tenant are not judged');
select is((select body -> 'items' from scope_result),
  '[
    {"productId":"99e10000-0000-4000-8000-000000000101","matchState":"strong",
     "matchDetail":[{"field":"scope_probe","source":"product_spec"}]},
    {"productId":"99e10000-0000-4000-8000-000000000103","matchState":"unverified",
     "matchDetail":[{"field":"scope_probe","source":"unresolved"}]},
    {"productId":"99e10000-0000-4000-8000-000000000104","matchState":"weak",
     "matchDetail":[{"field":"scope_probe","source":"identity_fallback"}]}
  ]'::jsonb,
  'ordered full detail is preserved; only conflict is removed');

alter sequence stock_scope_detail_calls restart;
create temporary table scope_over_limit as
select public.supply_need_eligible_products_internal_v1(
  '99e10000-0000-4000-8000-000000000001',
  '99e10000-0000-4000-8000-000000000201', 3
) as body;
select is((select body ->> 'status' from scope_over_limit), 'needs_refinement',
  'the safe ceiling still applies before judging conflicts');
select is((select body -> 'items' from scope_over_limit), '[]'::jsonb,
  'too broad does not leak a truncated candidate list');
select is((select case when is_called then last_value else 0 end
  from stock_scope_detail_calls), 0::bigint, 'too broad pays no detail calls');

create temporary table scope_unresolved as
select public.supply_need_eligible_products_internal_v1(
  '99e10000-0000-4000-8000-000000000001',
  '99e10000-0000-4000-8000-000000000202'
) as body;
select is((select body ->> 'status' from scope_unresolved), 'identity_unresolved',
  'missing category does not widen to the whole catalog');
select is((select case when is_called then last_value else 0 end
  from stock_scope_detail_calls), 0::bigint, 'missing category pays no detail calls');

create temporary table scope_empty as
select public.supply_need_eligible_products_internal_v1(
  '99e10000-0000-4000-8000-000000000001',
  '99e10000-0000-4000-8000-000000000204'
) as body;
select is((select body -> 'items' from scope_empty), '[]'::jsonb,
  'an empty recognized category still returns an honest empty universe');
select is((select case when is_called then last_value else 0 end
  from stock_scope_detail_calls), 0::bigint, 'empty category pays no detail calls');

alter sequence stock_scope_detail_calls restart;
create temporary table scope_exact as
select public.supply_need_eligible_products_internal_v1(
  '99e10000-0000-4000-8000-000000000001',
  '99e10000-0000-4000-8000-000000000203'
) as body;
select is((select body ->> 'lane' from scope_exact), 'exact',
  'a confirmed product keeps its independent exact lane');
select is((select body #>> '{items,0,productId}' from scope_exact),
  '99e10000-0000-4000-8000-000000000110', 'exact lane keeps its confirmed product');
select is((select jsonb_array_length(body -> 'items') from scope_exact), 1,
  'exact lane never widens to the family');
select is((select case when is_called then last_value else 0 end
  from stock_scope_detail_calls), 1::bigint, 'exact lane judges only that product');

select * from finish();
rollback;
