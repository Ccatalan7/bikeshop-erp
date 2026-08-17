-- Deployment status: applied to production and registered on 2026-08-16;
-- exact function, ACL and migration-history read-back passed.
-- Keep the two intelligent-purchasing reads inside the same durable runtime
-- contract as every other model-visible tool. The ranking envelope also uses
-- the exact catalog product as its server-owned entity identity; the opaque
-- supplier candidate hash is not a navigable entity and is not guaranteed to
-- carry RFC 4122 version/variant bits.
-- Recovery: the changes are additive contract synchronization. Rolling the
-- gateway back removes the advertised tools; retaining these entries and the
-- stricter projection is harmless.

begin;

create or replace function
  assistant_runtime.assistant_tool_receipt_contract_internal_v1(
    p_tool_name text
  )
returns table(risk text, policy_decision text, max_result_count integer)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select contract.risk, contract.policy_decision, contract.max_result_count
  from (values
    ('inspect_inventory_schema', 'read', 'allowed', 40),
    ('search_inventory', 'read', 'allowed', 10),
    ('rank_purchase_candidates', 'read', 'allowed', 10),
    ('build_purchase_scenarios', 'read', 'allowed', 3),
    ('list_attention_items', 'read', 'allowed', 10),
    ('get_business_snapshot', 'read', 'allowed', 10),
    ('search_workshop_jobs', 'read', 'allowed', 10),
    ('get_workshop_job_context', 'read', 'allowed', 10),
    ('inspect_diagnosis_schema', 'read', 'allowed', 40),
    ('search_tasks', 'read', 'allowed', 10),
    ('search_customers', 'read', 'allowed', 10),
    ('search_suppliers', 'read', 'allowed', 10),
    ('search_sales_invoices', 'read', 'allowed', 10),
    ('search_purchase_invoices', 'read', 'allowed', 10),
    ('find_inventory_risks', 'read', 'allowed', 10),
    ('list_recent_expenses', 'read', 'allowed', 10),
    ('analyze_cash_and_receivables', 'read', 'allowed', 10),
    ('analyze_sales_period', 'read', 'allowed', 1),
    ('search_conversations', 'read', 'allowed', 10),
    ('research_public_web', 'public_research', 'allowed', 10),
    ('prepare_task', 'draft', 'approval_required', 10),
    ('prepare_diagnosis_update', 'draft', 'approval_required', 1),
    ('prepare_workshop_item', 'draft', 'approval_required', 1),
    ('report_capability_gap', 'read', 'allowed', 10)
  ) contract(tool_name, risk, policy_decision, max_result_count)
  where contract.tool_name = p_tool_name;
$$;

revoke all on function
  assistant_runtime.assistant_tool_receipt_contract_internal_v1(text)
from public, anon, authenticated, service_role;

create or replace function public.assistant_rank_purchase_candidates_v1(
  p_query text,
  p_product_id uuid,
  p_profile text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_ranked jsonb;
  v_items jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  if p_profile not in ('balanced', 'profitability', 'urgent_local')
     or p_limit not between 1 and 10
     or octet_length(coalesce(p_query, '')) > 240
     or ((nullif(btrim(p_query), '') is null) = (p_product_id is null)) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  v_ranked := public.rank_purchase_candidates_v1(
    case when p_product_id is null then p_query else null end,
    p_product_id,
    null,
    p_profile,
    p_limit
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'entityId', item.value ->> 'productId',
    'rank', (item.value ->> 'rank')::integer,
    'rankingProfile', item.value ->> 'rankingProfile',
    'rankingVersion', item.value ->> 'rankingVersion',
    'rankingScore', (item.value ->> 'rankingScore')::numeric,
    'productName', item.value ->> 'productName',
    'productSku', item.value ->> 'productSku',
    'brand', item.value ->> 'brand',
    'category', item.value ->> 'category',
    'supplierName', item.value ->> 'supplierName',
    'supplierWebsite', item.value ->> 'supplierWebsite',
    'supplierLocation', item.value ->> 'supplierLocation',
    'isConfirmedLocal', (item.value ->> 'isConfirmedLocal')::boolean,
    'supplierAvailability', item.value ->> 'supplierAvailability',
    'currency', item.value ->> 'currency',
    'latestBaseUnitCostNet',
      (item.value ->> 'latestBaseUnitCostNet')::numeric,
    'latestAllocatedFreightNet',
      (item.value ->> 'latestAllocatedFreightNet')::numeric,
    'latestLandedUnitCostNet',
      (item.value ->> 'latestLandedUnitCostNet')::numeric,
    'catalogSalePriceGross',
      (item.value ->> 'catalogSalePriceGross')::numeric,
    'catalogSalePriceNet',
      (item.value ->> 'catalogSalePriceNet')::numeric,
    'projectedUnitGrossProfit',
      (item.value ->> 'projectedUnitGrossProfit')::numeric,
    'projectedGrossMarginRatio',
      (item.value ->> 'projectedGrossMarginRatio')::numeric,
    'purchaseCount', (item.value ->> 'purchaseCount')::integer,
    'purchasedUnits', (item.value ->> 'purchasedUnits')::numeric,
    'lastPurchaseAt', item.value ->> 'lastPurchaseAt',
    'evidenceAgeDays', (item.value ->> 'evidenceAgeDays')::integer,
    'evidenceQuality', item.value ->> 'evidenceQuality',
    'freightEvidence', item.value ->> 'freightEvidence',
    'economyScore', (item.value ->> 'economyScore')::numeric,
    'historyScore', (item.value ->> 'historyScore')::numeric,
    'recencyScore', (item.value ->> 'recencyScore')::numeric,
    'stabilityScore', (item.value ->> 'stabilityScore')::numeric,
    'evidenceScore', (item.value ->> 'evidenceScore')::numeric
  ) order by item.ordinality), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_ranked -> 'items')
    with ordinality item(value, ordinality);

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    coalesce((v_ranked ->> 'hasMore')::boolean, false)
  );
end;
$$;

revoke all on function public.assistant_rank_purchase_candidates_v1(
  text, uuid, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.assistant_rank_purchase_candidates_v1(
  text, uuid, text, integer
) to authenticated;

comment on function
  assistant_runtime.assistant_tool_receipt_contract_internal_v1(text) is
  'Closed risk, policy and result-count contract for every model-visible assistant tool, including intelligent-purchasing reads.';
comment on function public.assistant_rank_purchase_candidates_v1(
  text, uuid, text, integer
) is
  'Governed assistant projection of deterministic purchase candidates. Its hidden entity identity is the exact catalog product; supplier availability remains explicitly unverified.';

commit;
