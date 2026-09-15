-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; live two-line scenario read-back passed.
-- Bounded, deterministic basket scenarios for intelligent purchasing.
--
-- The solver receives already-resolved catalog products. It preserves the
-- stock-first boundary, explores a bounded supplier set, reports uncovered
-- lines honestly and never assumes a freight discount from consolidation.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.build_purchase_scenarios_v1(
  p_items jsonb,
  p_profile text default 'balanced',
  p_max_suppliers integer default 3,
  p_limit integer default 3
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_item_count integer;
  v_external_count integer;
  v_internal_count integer;
  v_candidate_count integer;
  v_supplier_count integer;
  v_scenario_count integer;
  v_scenarios jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 8
     or p_profile not in ('balanced', 'profitability', 'urgent_local')
     or p_max_suppliers not between 1 and 3
     or p_limit not between 1 and 3 then
    raise exception 'Invalid purchase scenario arguments' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) item(value)
    where jsonb_typeof(item.value) <> 'object'
       or item.value - array[
         'lineRef', 'productId', 'quantity', 'sourcingMode'
       ] <> '{}'::jsonb
       or jsonb_typeof(item.value -> 'lineRef') <> 'string'
       or btrim(item.value ->> 'lineRef') = ''
       or octet_length(item.value ->> 'lineRef') > 64
       or jsonb_typeof(item.value -> 'productId') <> 'string'
       or not ((item.value ->> 'productId') ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
       or jsonb_typeof(item.value -> 'quantity') <> 'number'
       or (item.value ->> 'quantity')::numeric <= 0
       or (item.value ->> 'quantity')::numeric > 999999
       or item.value ->> 'sourcingMode' not in (
         'stock_first', 'external_only'
       )
  ) then
    raise exception 'Invalid purchase scenario items' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) item(value)
    group by btrim(item.value ->> 'lineRef')
    having count(*) > 1
  ) then
    raise exception 'Purchase scenario line references must be unique'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) item(value)
    where not exists (
      select 1
      from public.products product
      where product.tenant_id = v_tenant_id
        and product.id = (item.value ->> 'productId')::uuid
        and product.is_active is true
    )
  ) then
    raise exception 'Product not found' using errcode = 'P0002';
  end if;

  with input_lines as materialized (
    select
      item.ordinality::integer as line_order,
      btrim(item.value ->> 'lineRef') as line_ref,
      (item.value ->> 'productId')::uuid as product_id,
      (item.value ->> 'quantity')::numeric(14,3) as requested_quantity,
      item.value ->> 'sourcingMode' as sourcing_mode
    from jsonb_array_elements(p_items) with ordinality item(value, ordinality)
  ), enriched_lines as materialized (
    select
      input.*,
      product.name as product_name,
      product.sku as product_sku,
      public.inventory_available_quantity_v1(
        v_tenant_id, input.product_id
      ) as available_to_promise,
      input.sourcing_mode = 'external_only'
        or public.inventory_available_quantity_v1(
          v_tenant_id, input.product_id
        ) < input.requested_quantity as requires_external
    from input_lines input
    join public.products product
      on product.tenant_id = v_tenant_id and product.id = input.product_id
  ), ranked_payloads as materialized (
    select line.line_ref,
      public.rank_purchase_candidates_v1(
        null, line.product_id, null, p_profile, 5
      ) as payload
    from enriched_lines line
    where line.requires_external
  ), candidates as materialized (
    select
      line.line_order,
      line.line_ref,
      line.product_id,
      line.product_name,
      line.product_sku,
      line.requested_quantity,
      line.available_to_promise,
      (candidate.value ->> 'candidateId')::uuid as candidate_id,
      coalesce(
        candidate.value ->> 'supplierId',
        'name:' || md5(lower(candidate.value ->> 'supplierName'))
      ) as supplier_key,
      nullif(candidate.value ->> 'supplierId', '')::uuid as supplier_id,
      candidate.value ->> 'supplierName' as supplier_name,
      coalesce((candidate.value ->> 'isConfirmedLocal')::boolean, false)
        as is_confirmed_local,
      candidate.value ->> 'currency' as currency_code,
      nullif(candidate.value ->> 'latestLandedUnitCostNet', '')::numeric
        as landed_unit_cost_net,
      nullif(candidate.value ->> 'projectedGrossMarginRatio', '')::numeric
        as projected_gross_margin_ratio,
      (candidate.value ->> 'rankingScore')::numeric as ranking_score,
      (candidate.value ->> 'rank')::integer as candidate_rank,
      (candidate.value ->> 'purchaseCount')::integer as purchase_count,
      (candidate.value ->> 'evidenceAgeDays')::integer as evidence_age_days,
      candidate.value ->> 'evidenceQuality' as evidence_quality,
      candidate.value ->> 'freightEvidence' as freight_evidence
    from ranked_payloads ranked
    join enriched_lines line on line.line_ref = ranked.line_ref
    cross join lateral jsonb_array_elements(ranked.payload -> 'items')
      candidate(value)
  ), supplier_coverage as materialized (
    select
      candidate.supplier_key,
      count(distinct candidate.line_ref)::integer as covered_lines,
      avg(candidate.ranking_score)::numeric as average_ranking_score,
      max(candidate.is_confirmed_local::integer)::integer as local_signal
    from candidates candidate
    group by candidate.supplier_key
  ), bounded_suppliers as materialized (
    select coverage.*,
      row_number() over (
        order by coverage.covered_lines desc,
          coverage.average_ranking_score desc,
          coverage.local_signal desc,
          coverage.supplier_key
      )::bigint as pool_index
    from supplier_coverage coverage
    order by coverage.covered_lines desc,
      coverage.average_ranking_score desc,
      coverage.local_signal desc,
      coverage.supplier_key
    limit 12
  )
  select
    count(*)::integer,
    count(*) filter (where requires_external)::integer,
    count(*) filter (where not requires_external)::integer,
    (select count(*)::integer from candidates),
    (select count(*)::integer from supplier_coverage)
  into v_item_count, v_external_count, v_internal_count,
    v_candidate_count, v_supplier_count
  from enriched_lines;

  if v_external_count = 0 then
    with input_lines as (
      select
        item.ordinality::integer as line_order,
        btrim(item.value ->> 'lineRef') as line_ref,
        (item.value ->> 'productId')::uuid as product_id,
        (item.value ->> 'quantity')::numeric(14,3) as requested_quantity
      from jsonb_array_elements(p_items) with ordinality item(value, ordinality)
    ), lines as (
      select input.*,
        product.name as product_name,
        product.sku as product_sku,
        public.inventory_available_quantity_v1(
          v_tenant_id, input.product_id
        ) as available_to_promise
      from input_lines input
      join public.products product
        on product.tenant_id = v_tenant_id and product.id = input.product_id
    )
    select jsonb_build_array(jsonb_build_object(
      'scenarioKey', 'internal-stock',
      'kind', 'internal_stock',
      'label', 'Resolver con stock interno',
      'coverageLineCount', v_item_count,
      'externalCoverageLineCount', 0,
      'totalLineCount', v_item_count,
      'externalLineCount', 0,
      'complete', true,
      'supplierCount', 0,
      'historicalSubtotals', '[]'::jsonb,
      'supplierAvailability', 'not_applicable',
      'freightAssumption', 'not_applicable',
      'lines', (
        select jsonb_agg(jsonb_build_object(
          'lineRef', line.line_ref,
          'productId', line.product_id,
          'productName', line.product_name,
          'productSku', line.product_sku,
          'requestedQuantity', line.requested_quantity,
          'availableToPromise', line.available_to_promise,
          'sourcing', 'internal',
          'covered', true
        ) order by line.line_order)
        from lines line
      ),
      'explanationCodes', jsonb_build_array('stock_first')
    )) into v_scenarios;

    return jsonb_build_object(
      'asOf', clock_timestamp(),
      'status', 'success',
      'profile', p_profile,
      'inputCount', v_item_count,
      'internalLineCount', v_internal_count,
      'externalLineCount', v_external_count,
      'boundedSupplierCount', 0,
      'scenarios', v_scenarios,
      'resultCount', 1,
      'hasMore', false,
      'supplierAvailabilitySemantics', 'historical_only_unverified'
    );
  end if;

  if v_candidate_count = 0 then
    return jsonb_build_object(
      'asOf', clock_timestamp(),
      'status', 'verifiedEmpty',
      'profile', p_profile,
      'inputCount', v_item_count,
      'internalLineCount', v_internal_count,
      'externalLineCount', v_external_count,
      'boundedSupplierCount', 0,
      'scenarios', '[]'::jsonb,
      'resultCount', 0,
      'hasMore', false,
      'supplierAvailabilitySemantics', 'historical_only_unverified'
    );
  end if;

  with recursive input_lines as materialized (
    select
      item.ordinality::integer as line_order,
      btrim(item.value ->> 'lineRef') as line_ref,
      (item.value ->> 'productId')::uuid as product_id,
      (item.value ->> 'quantity')::numeric(14,3) as requested_quantity,
      item.value ->> 'sourcingMode' as sourcing_mode
    from jsonb_array_elements(p_items) with ordinality item(value, ordinality)
  ), enriched_lines as materialized (
    select
      input.*,
      product.name as product_name,
      product.sku as product_sku,
      public.inventory_available_quantity_v1(
        v_tenant_id, input.product_id
      ) as available_to_promise,
      input.sourcing_mode = 'external_only'
        or public.inventory_available_quantity_v1(
          v_tenant_id, input.product_id
        ) < input.requested_quantity as requires_external
    from input_lines input
    join public.products product
      on product.tenant_id = v_tenant_id and product.id = input.product_id
  ), ranked_payloads as materialized (
    select line.line_ref,
      public.rank_purchase_candidates_v1(
        null, line.product_id, null, p_profile, 5
      ) as payload
    from enriched_lines line
    where line.requires_external
  ), candidates as materialized (
    select
      line.line_order,
      line.line_ref,
      line.product_id,
      line.product_name,
      line.product_sku,
      line.requested_quantity,
      line.available_to_promise,
      (candidate.value ->> 'candidateId')::uuid as candidate_id,
      coalesce(
        candidate.value ->> 'supplierId',
        'name:' || md5(lower(candidate.value ->> 'supplierName'))
      ) as supplier_key,
      nullif(candidate.value ->> 'supplierId', '')::uuid as supplier_id,
      candidate.value ->> 'supplierName' as supplier_name,
      coalesce((candidate.value ->> 'isConfirmedLocal')::boolean, false)
        as is_confirmed_local,
      candidate.value ->> 'currency' as currency_code,
      nullif(candidate.value ->> 'latestLandedUnitCostNet', '')::numeric
        as landed_unit_cost_net,
      nullif(candidate.value ->> 'projectedGrossMarginRatio', '')::numeric
        as projected_gross_margin_ratio,
      (candidate.value ->> 'rankingScore')::numeric as ranking_score,
      (candidate.value ->> 'rank')::integer as candidate_rank,
      (candidate.value ->> 'purchaseCount')::integer as purchase_count,
      (candidate.value ->> 'evidenceAgeDays')::integer as evidence_age_days,
      candidate.value ->> 'evidenceQuality' as evidence_quality,
      candidate.value ->> 'freightEvidence' as freight_evidence
    from ranked_payloads ranked
    join enriched_lines line on line.line_ref = ranked.line_ref
    cross join lateral jsonb_array_elements(ranked.payload -> 'items')
      candidate(value)
  ), supplier_coverage as materialized (
    select
      candidate.supplier_key,
      count(distinct candidate.line_ref)::integer as covered_lines,
      avg(candidate.ranking_score)::numeric as average_ranking_score,
      max(candidate.is_confirmed_local::integer)::integer as local_signal
    from candidates candidate
    group by candidate.supplier_key
  ), bounded_suppliers as materialized (
    select coverage.*,
      row_number() over (
        order by coverage.covered_lines desc,
          coverage.average_ranking_score desc,
          coverage.local_signal desc,
          coverage.supplier_key
      )::bigint as pool_index
    from supplier_coverage coverage
    order by coverage.covered_lines desc,
      coverage.average_ranking_score desc,
      coverage.local_signal desc,
      coverage.supplier_key
    limit 12
  ), supplier_sets(supplier_keys, last_pool_index) as (
    select array[supplier.supplier_key]::text[], supplier.pool_index
    from bounded_suppliers supplier
    union all
    select candidate_set.supplier_keys || supplier.supplier_key,
      supplier.pool_index
    from supplier_sets candidate_set
    join bounded_suppliers supplier
      on supplier.pool_index > candidate_set.last_pool_index
    where cardinality(candidate_set.supplier_keys) < p_max_suppliers
  ), choice_rows as materialized (
    select
      md5(array_to_string(candidate_set.supplier_keys, '|')) as set_key,
      candidate_set.supplier_keys,
      line.line_order,
      line.line_ref,
      line.requested_quantity,
      choice.candidate_id,
      choice.supplier_key,
      choice.currency_code,
      choice.landed_unit_cost_net,
      choice.ranking_score,
      choice.is_confirmed_local
    from supplier_sets candidate_set
    cross join enriched_lines line
    left join lateral (
      select candidate.*
      from candidates candidate
      where candidate.line_ref = line.line_ref
        and candidate.supplier_key = any(candidate_set.supplier_keys)
      order by candidate.ranking_score desc,
        candidate.candidate_rank,
        candidate.candidate_id
      limit 1
    ) choice on true
    where line.requires_external
  ), set_metrics as materialized (
    select
      choice.set_key,
      choice.supplier_keys,
      count(choice.candidate_id)::integer as covered_external_lines,
      count(distinct choice.supplier_key) filter (
        where choice.candidate_id is not null
      )::integer as actual_supplier_count,
      coalesce(sum(choice.ranking_score), 0)::numeric as ranking_score_total,
      count(distinct choice.currency_code) filter (
        where choice.candidate_id is not null
      )::integer as currency_count,
      count(choice.landed_unit_cost_net) filter (
        where choice.candidate_id is not null
      )::integer as known_cost_count,
      sum(choice.requested_quantity * choice.landed_unit_cost_net)
        filter (where choice.candidate_id is not null)
        ::numeric as historical_cost_total,
      count(*) filter (
        where choice.candidate_id is not null
          and choice.is_confirmed_local
      )::integer as local_line_count,
      string_agg(
        choice.line_ref || ':' || coalesce(choice.candidate_id::text, 'missing'),
        '|' order by choice.line_order
      ) as selection_signature
    from choice_rows choice
    group by choice.set_key, choice.supplier_keys
  ), unique_selections as materialized (
    select distinct on (metric.selection_signature) metric.*
    from set_metrics metric
    order by metric.selection_signature,
      metric.actual_supplier_count,
      cardinality(metric.supplier_keys),
      metric.ranking_score_total desc,
      metric.set_key
  ), recommended_pick as (
    select 1::integer as scenario_priority,
      'recommended'::text as scenario_kind,
      selection.*
    from unique_selections selection
    order by selection.covered_external_lines desc,
      selection.ranking_score_total desc,
      selection.actual_supplier_count,
      selection.local_line_count desc,
      selection.set_key
    limit 1
  ), consolidated_pick as (
    select 2::integer as scenario_priority,
      'consolidated'::text as scenario_kind,
      selection.*
    from unique_selections selection
    order by selection.covered_external_lines desc,
      selection.actual_supplier_count,
      selection.ranking_score_total desc,
      selection.set_key
    limit 1
  ), lowest_cost_pick as (
    select 3::integer as scenario_priority,
      'lowest_historical_cost'::text as scenario_kind,
      selection.*
    from unique_selections selection
    where selection.currency_count = 1
      and selection.known_cost_count = selection.covered_external_lines
      and selection.covered_external_lines > 0
    order by selection.covered_external_lines desc,
      selection.historical_cost_total,
      selection.actual_supplier_count,
      selection.ranking_score_total desc,
      selection.set_key
    limit 1
  ), candidate_scenarios as (
    select * from recommended_pick
    union all
    select * from consolidated_pick
    union all
    select * from lowest_cost_pick
  ), distinct_scenarios as materialized (
    select distinct on (scenario.selection_signature) scenario.*
    from candidate_scenarios scenario
    order by scenario.selection_signature,
      scenario.scenario_priority
  ), selected_scenarios as materialized (
    select scenario.*,
      row_number() over (
        order by scenario.scenario_priority,
          scenario.covered_external_lines desc,
          scenario.ranking_score_total desc,
          scenario.set_key
      )::integer as display_order
    from distinct_scenarios scenario
    order by display_order
    limit p_limit
  ), scenario_documents as (
    select
      selected.display_order,
      jsonb_build_object(
        'scenarioKey', selected.scenario_kind || ':' || selected.set_key,
        'kind', selected.scenario_kind,
        'label', case selected.scenario_kind
          when 'consolidated' then 'Menos proveedores'
          when 'lowest_historical_cost' then 'Menor costo histórico comparable'
          else case p_profile
            when 'profitability' then 'Mayor rentabilidad'
            when 'urgent_local' then 'Urgente/local'
            else 'Mejor equilibrio'
          end
        end,
        'coverageLineCount',
          v_internal_count + selected.covered_external_lines,
        'externalCoverageLineCount', selected.covered_external_lines,
        'totalLineCount', v_item_count,
        'externalLineCount', v_external_count,
        'complete',
          v_internal_count + selected.covered_external_lines = v_item_count,
        'supplierCount', selected.actual_supplier_count,
        'historicalSubtotals', coalesce((
          select jsonb_agg(jsonb_build_object(
            'currency', subtotal.currency_code,
            'historicalLandedSubtotalNet', subtotal.amount
          ) order by subtotal.currency_code)
          from (
            select choice.currency_code,
              sum(line.requested_quantity * choice.landed_unit_cost_net)
                ::numeric(18,4) as amount
            from enriched_lines line
            join lateral (
              select candidate.*
              from candidates candidate
              where candidate.line_ref = line.line_ref
                and candidate.supplier_key = any(selected.supplier_keys)
              order by candidate.ranking_score desc,
                candidate.candidate_rank,
                candidate.candidate_id
              limit 1
            ) choice on line.requires_external
            where choice.landed_unit_cost_net is not null
            group by choice.currency_code
          ) subtotal
        ), '[]'::jsonb),
        'supplierAvailability', 'historical_only_unverified',
        'freightAssumption',
          'sum_historical_landed_line_costs_no_consolidation_saving',
        'lines', (
          select jsonb_agg(
            case
              when not line.requires_external then jsonb_build_object(
                'lineRef', line.line_ref,
                'productId', line.product_id,
                'productName', line.product_name,
                'productSku', line.product_sku,
                'requestedQuantity', line.requested_quantity,
                'availableToPromise', line.available_to_promise,
                'sourcing', 'internal',
                'covered', true
              )
              when choice.candidate_id is null then jsonb_build_object(
                'lineRef', line.line_ref,
                'productId', line.product_id,
                'productName', line.product_name,
                'productSku', line.product_sku,
                'requestedQuantity', line.requested_quantity,
                'availableToPromise', line.available_to_promise,
                'sourcing', 'uncovered',
                'covered', false
              )
              else jsonb_build_object(
                'lineRef', line.line_ref,
                'productId', line.product_id,
                'productName', line.product_name,
                'productSku', line.product_sku,
                'requestedQuantity', line.requested_quantity,
                'availableToPromise', line.available_to_promise,
                'sourcing', 'external',
                'covered', true,
                'candidateId', choice.candidate_id,
                'supplierId', choice.supplier_id,
                'supplierName', choice.supplier_name,
                'isConfirmedLocal', choice.is_confirmed_local,
                'supplierAvailability', 'unverified',
                'currency', choice.currency_code,
                'latestLandedUnitCostNet', choice.landed_unit_cost_net,
                'projectedGrossMarginRatio',
                  choice.projected_gross_margin_ratio,
                'rankingScore', choice.ranking_score,
                'purchaseCount', choice.purchase_count,
                'evidenceAgeDays', choice.evidence_age_days,
                'evidenceQuality', choice.evidence_quality,
                'freightEvidence', choice.freight_evidence
              )
            end
            order by line.line_order
          )
          from enriched_lines line
          left join lateral (
            select candidate.*
            from candidates candidate
            where candidate.line_ref = line.line_ref
              and candidate.supplier_key = any(selected.supplier_keys)
            order by candidate.ranking_score desc,
              candidate.candidate_rank,
              candidate.candidate_id
            limit 1
          ) choice on line.requires_external
        ),
        'explanationCodes', jsonb_build_array(
          case when v_internal_count > 0
            then 'stock_first' else 'external_only' end,
          case when selected.covered_external_lines = v_external_count
            then 'complete_external_coverage'
            else 'partial_external_coverage' end,
          case selected.scenario_kind
            when 'consolidated' then 'supplier_consolidation'
            when 'lowest_historical_cost' then 'historical_cost_comparison'
            else 'profile_ranked' end,
          'historical_availability_unverified',
          'no_consolidation_freight_saving_assumed'
        )
      ) as document
    from selected_scenarios selected
  )
  select coalesce(jsonb_agg(document order by display_order), '[]'::jsonb),
    count(*)::integer
  into v_scenarios, v_scenario_count
  from scenario_documents;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'status', case
      when exists (
        select 1
        from jsonb_array_elements(v_scenarios) scenario(value)
        where (scenario.value ->> 'complete')::boolean
      ) then 'success'
      else 'partial'
    end,
    'profile', p_profile,
    'inputCount', v_item_count,
    'internalLineCount', v_internal_count,
    'externalLineCount', v_external_count,
    'boundedSupplierCount', least(v_supplier_count, 12),
    'scenarios', v_scenarios,
    'resultCount', v_scenario_count,
    'hasMore', v_supplier_count > 12 or v_scenario_count >= p_limit,
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  );
end;
$$;

revoke all on function public.build_purchase_scenarios_v1(
  jsonb, text, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.build_purchase_scenarios_v1(
  jsonb, text, integer, integer
) to authenticated;

comment on function public.build_purchase_scenarios_v1(
  jsonb, text, integer, integer
) is
  'Builds up to three bounded stock-first basket scenarios from exact catalog products. It reports partial coverage and historical supplier uncertainty, and never invents a consolidation freight saving.';

create or replace function public.assistant_build_purchase_scenarios_v1(
  p_items jsonb,
  p_profile text,
  p_max_suppliers integer,
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
  v_inventory_authority record;
  v_result jsonb;
  v_items jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  select authority.tenant_id, authority.actor_user_id
  into strict v_inventory_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if v_inventory_authority.tenant_id <> v_authority.tenant_id
     or v_inventory_authority.actor_user_id <> v_authority.actor_user_id then
    raise exception 'Assistant authority changed during scenario analysis'
      using errcode = '42501';
  end if;

  v_result := public.build_purchase_scenarios_v1(
    p_items, p_profile, p_max_suppliers, p_limit
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'scenarioKey', scenario.value ->> 'scenarioKey',
    'kind', scenario.value ->> 'kind',
    'label', scenario.value ->> 'label',
    'coverageLineCount', (scenario.value ->> 'coverageLineCount')::integer,
    'externalCoverageLineCount',
      (scenario.value ->> 'externalCoverageLineCount')::integer,
    'totalLineCount', (scenario.value ->> 'totalLineCount')::integer,
    'externalLineCount', (scenario.value ->> 'externalLineCount')::integer,
    'complete', (scenario.value ->> 'complete')::boolean,
    'supplierCount', (scenario.value ->> 'supplierCount')::integer,
    'historicalSubtotals', scenario.value -> 'historicalSubtotals',
    'supplierAvailability', scenario.value ->> 'supplierAvailability',
    'freightAssumption', scenario.value ->> 'freightAssumption',
    'lines', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'lineRef', line.value ->> 'lineRef',
        'productName', line.value ->> 'productName',
        'productSku', line.value ->> 'productSku',
        'requestedQuantity',
          (line.value ->> 'requestedQuantity')::numeric,
        'availableToPromise',
          (line.value ->> 'availableToPromise')::integer,
        'sourcing', line.value ->> 'sourcing',
        'covered', (line.value ->> 'covered')::boolean,
        'supplierName', line.value ->> 'supplierName',
        'isConfirmedLocal',
          nullif(line.value ->> 'isConfirmedLocal', '')::boolean,
        'supplierAvailability', line.value ->> 'supplierAvailability',
        'currency', line.value ->> 'currency',
        'latestLandedUnitCostNet',
          nullif(line.value ->> 'latestLandedUnitCostNet', '')::numeric,
        'projectedGrossMarginRatio',
          nullif(line.value ->> 'projectedGrossMarginRatio', '')::numeric,
        'purchaseCount', nullif(line.value ->> 'purchaseCount', '')::integer,
        'evidenceAgeDays',
          nullif(line.value ->> 'evidenceAgeDays', '')::integer,
        'evidenceQuality', line.value ->> 'evidenceQuality',
        'freightEvidence', line.value ->> 'freightEvidence'
      )) order by line.ordinality), '[]'::jsonb)
      from jsonb_array_elements(scenario.value -> 'lines')
        with ordinality line(value, ordinality)
    ),
    'explanationCodes', scenario.value -> 'explanationCodes'
  ) order by scenario.ordinality), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_result -> 'scenarios')
    with ordinality scenario(value, ordinality);

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    coalesce((v_result ->> 'hasMore')::boolean, false)
  );
end;
$$;

revoke all on function public.assistant_build_purchase_scenarios_v1(
  jsonb, text, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.assistant_build_purchase_scenarios_v1(
  jsonb, text, integer, integer
) to authenticated;

comment on function public.assistant_build_purchase_scenarios_v1(
  jsonb, text, integer, integer
) is
  'Governed assistant projection of bounded basket scenarios. It requires ai.read.purchases plus the canonical ai.read.operational inventory authority and strips internal entity IDs.';

notify pgrst, 'reload schema';

commit;
