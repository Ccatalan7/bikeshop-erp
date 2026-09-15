-- Se deja de normalizar el texto de cada candidato para tirarlo a la basura.
--
-- `filtered` calculaba una columna `search_surface`
-- —`assistant_normalize_query_internal_v1` sobre el nombre, el SKU, la marca,
-- la categoría y el proveedor concatenados— que **ninguna** etapa posterior
-- usaba. El filtro de texto ya normaliza por su cuenta dentro del `not exists`,
-- así que el normalizador, que es PL/pgSQL y no se inlinea, corría dos veces
-- por fila sobre el escaneo completo de métricas.
--
-- Con los 267 candidatos del taller real el ranking por texto libre tardaba
-- 32 s contra un `statement_timeout` de 4,5 s: inutilizable. Quitar la columna
-- muerta no cambia ni una fila del resultado — sólo deja de pagar por ella.
--
-- Es un defecto anterior al trabajo de gama. Apareció probando el módulo en la
-- app real; ninguna prueba de definición podía verlo, porque la función era
-- correcta y sólo no cabía en su tiempo.

begin;

create or replace function public.rank_purchase_candidates_v1(
  p_query text default null,
  p_product_id uuid default null,
  p_category_id uuid default null,
  p_profile text default 'balanced',
  p_limit integer default 10,
  p_gama text default null
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
  v_query text := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_items jsonb;
  v_total integer;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if (p_gama is not null and p_gama not in ('economica', 'media', 'alta'))
     or p_profile not in ('balanced', 'profitability', 'urgent_local')
     or p_limit not between 1 and 20
     or octet_length(coalesce(p_query, '')) > 240
     or (v_query is null and p_product_id is null and p_category_id is null) then
    raise exception 'Invalid purchase ranking arguments' using errcode = '22023';
  end if;
  if p_product_id is not null and not exists (
    select 1 from public.products product
    where product.tenant_id = v_tenant_id and product.id = p_product_id
  ) then
    raise exception 'Product not found' using errcode = 'P0002';
  end if;
  if p_category_id is not null and not exists (
    select 1 from public.product_categories category
    where category.tenant_id = v_tenant_id and category.id = p_category_id
  ) then
    raise exception 'Category not found' using errcode = 'P0002';
  end if;

  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = v_tenant_id and category.id = p_category_id
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_tenant_id and child.is_active is true
  ), gama_scope as materialized (
    -- La banda del tenant se resuelve UNA vez y se materializa.
    --
    -- Antes esto era un `left join` directo contra `product_gama_v1` dentro de
    -- `filtered`: la vista deriva bandas con funciones de ventana sobre las
    -- métricas completas, así que el planificador la reevaluaba por fila y el
    -- ranking se pasaba del `statement_timeout` de 4,5 s. Son ~50 marcas: cabe
    -- de sobra en una CTE materializada.
    select
      band.category_id,
      lower(btrim(band.brand)) as brand_key,
      band.band,
      band.band_is_confident
    from public.product_gama_v1 band
    where band.tenant_id = v_tenant_id
  ), filtered as materialized (
    select metric.*,
      gama.band as gama_band,
      gama.band_is_confident as gama_is_confident
    from public.purchase_candidate_metrics_v1 metric
    left join gama_scope gama
      on gama.category_id = metric.category_id
     and gama.brand_key = lower(btrim(metric.brand))
    where metric.tenant_id = v_tenant_id
      and (p_product_id is null or metric.product_id = p_product_id)
      and (p_category_id is null or metric.category_id in (
        select id from category_scope
      ))
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', metric.product_name, metric.product_sku, metric.brand,
            metric.category_path, metric.supplier_name)
        )) = 0
      ))
  ), bounded as (
    select filtered.*,
      max(purchase_count) over()::numeric as max_purchase_count,
      max(purchased_units) over()::numeric as max_purchased_units
    from filtered
  ), dimensions as (
    select bounded.*,
      case
        when projected_gross_margin_ratio is null then 0.35
        else greatest(0, least(1,
          (projected_gross_margin_ratio + 0.10) / 0.70
        ))
      end::numeric as economy_score,
      (
        0.65 * case when max_purchase_count <= 1 then 1
          else ln(1 + purchase_count) / ln(1 + max_purchase_count) end
        + 0.35 * case when max_purchased_units <= 1 then 1
          else ln(1 + purchased_units) / ln(1 + max_purchased_units) end
      )::numeric as history_score,
      exp(-greatest(evidence_age_days, 0)::numeric / 180)::numeric
        as recency_score,
      case
        when observation_count < 2
          or average_landed_unit_cost_net <= 0
          or landed_cost_standard_deviation is null then 0.50
        else greatest(0, least(1,
          1 - landed_cost_standard_deviation / average_landed_unit_cost_net
        ))
      end::numeric as stability_score,
      (
        0.30
        + case when supplier_id is not null then 0.15 else 0 end
        + case when catalog_sale_price_net is not null then 0.20 else 0 end
        + case when latest_freight_evidence_status in ('complete', 'none')
            then 0.20 else 0 end
        + case when evidence_age_days <= 180 then 0.15 else 0 end
      )::numeric as evidence_score,
      case when is_confirmed_local then 1 else 0 end::numeric as local_score,
      -- La gama ORDENA, nunca elimina: el contrato de elegibilidad reserva la
      -- exclusion para la contradiccion tecnica demostrada. Una banda contigua
      -- conserva media puntuacion, y una marca sin banda no se castiga a cero
      -- porque no saber no es lo mismo que no calzar.
      case
        when p_gama is null then 0
        when gama_band is null then 0.5
        when gama_band = p_gama then 1
        when (p_gama = 'media') or (gama_band = 'media') then 0.5
        else 0
      end::numeric as gama_score
    from bounded
  ), scored as (
    select dimensions.*,
      -- Sin gama pedida el puntaje queda identico al anterior; con gama
      -- pedida, un cuarto del peso pasa a la banda.
      (1 - case when p_gama is null then 0 else 0.25 end) *
      case p_profile
        when 'profitability' then
          0.62 * economy_score + 0.15 * history_score
          + 0.08 * recency_score + 0.05 * stability_score
          + 0.10 * evidence_score
        when 'urgent_local' then
          0.28 * economy_score + 0.16 * history_score
          + 0.24 * recency_score + 0.22 * local_score
          + 0.10 * evidence_score
        else
          0.38 * economy_score + 0.24 * history_score
          + 0.16 * recency_score + 0.12 * stability_score
          + 0.10 * evidence_score
      end
      + case when p_gama is null then 0 else 0.25 * gama_score end
      ::numeric as ranking_score,
      case
        when latest_identity_quality = 'exact_product'
          and catalog_sale_price_net is not null
          and latest_freight_evidence_status in ('complete', 'none')
          and evidence_age_days <= 180 then 'complete'
        when latest_identity_quality like 'exact_product%'
          then 'partial'
        else 'weak'
      end as evidence_quality
    from dimensions
  ), numbered as (
    select scored.*,
      row_number() over (
        order by ranking_score desc, evidence_score desc,
          latest_purchase_at desc, candidate_id
      )::integer as rank,
      count(*) over()::integer as matched_count
    from scored
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'candidateId', candidate_id,
      'rank', rank,
      'rankingProfile', p_profile,
      'rankingVersion', 'purchase-ranking-v1',
      'rankingScore', round(ranking_score, 6),
      'productId', product_id,
      'productName', product_name,
      'productSku', product_sku,
      'brand', brand,
      'category', category_path,
      'imageUrlOptimized', image_url_optimized,
      'imageUrl', image_url,
      'imageUrls', to_jsonb(image_urls),
      'supplierId', supplier_id,
      'supplierName', supplier_name,
      'supplierWebsite', supplier_website,
      'supplierLocation', supplier_location,
      'isConfirmedLocal', is_confirmed_local,
      'supplierAvailability', supplier_availability,
      'currency', currency_code,
      'latestBaseUnitCostNet', latest_base_unit_cost_net,
      'latestAllocatedFreightNet', latest_allocated_freight_net,
      'latestLandedUnitCostNet', latest_landed_unit_cost_net,
      'catalogSalePriceGross', catalog_sale_price_gross,
      'catalogSalePriceNet', catalog_sale_price_net,
      'projectedUnitGrossProfit', projected_unit_gross_profit,
      'projectedGrossMarginRatio', projected_gross_margin_ratio,
      'purchaseCount', purchase_count,
      'purchasedUnits', purchased_units,
      'lastPurchaseAt', latest_purchase_at,
      'evidenceAgeDays', evidence_age_days,
      'evidenceQuality', evidence_quality,
      'freightEvidence', latest_freight_evidence_status,
      'economyScore', round(economy_score, 6),
      'historyScore', round(history_score, 6),
      'recencyScore', round(recency_score, 6),
      'stabilityScore', round(stability_score, 6),
      'evidenceScore', round(evidence_score, 6),
      'gama', gama_band,
      'gamaIsConfident', coalesce(gama_is_confident, false),
      'gamaScore', round(gama_score, 6),
      'latestPurchaseInvoiceId', latest_purchase_invoice_id,
      'latestPurchaseInvoiceLineId', latest_purchase_invoice_line_id
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched_count), 0)
  into v_items, v_total
  from numbered;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'status', case when v_total = 0 then 'verifiedEmpty' else 'success' end,
    'items', v_items,
    'resultCount', jsonb_array_length(v_items),
    'hasMore', v_total > p_limit,
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  );
end;
$$;

revoke all on function public.rank_purchase_candidates_v1(
  text, uuid, uuid, text, integer, text
) from public, anon, authenticated, service_role;
grant execute on function public.rank_purchase_candidates_v1(
  text, uuid, uuid, text, integer, text
) to authenticated;

commit;
