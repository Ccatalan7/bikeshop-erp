-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; governed-envelope read-back passed.
-- Governed AI read tools for intelligent purchasing.
-- Forward: expose the deterministic ranking kernel through the existing
-- assistant envelope and authority boundary.
-- Recovery: roll the gateway back to the previous registry; the additive RPC
-- can remain installed and no business rows require reversal.
-- Risk: read-only function creation. No purchase, stock or accounting write.
begin;

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
    'entityId', item.value ->> 'candidateId',
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

comment on function public.assistant_rank_purchase_candidates_v1(
  text, uuid, text, integer
) is
  'Governed assistant projection of deterministic purchase candidates. Accepts either an exact server-resolved catalog product or a bounded natural query; supplier availability remains explicitly unverified.';

commit;
