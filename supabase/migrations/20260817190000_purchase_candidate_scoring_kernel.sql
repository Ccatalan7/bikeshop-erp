-- Un solo dueño del scoring de candidatos de compra.
--
-- **Por qué se extrae.** La Fase B2 necesita rankear el conjunto elegible de
-- una necesidad —el que la Fase B1 resuelve por categoría y predicados— sin
-- volver a filtrar después del corte y sin escribir una segunda fórmula. Hoy
-- la fórmula vive dentro de `rank_purchase_candidates_v1`, mezclada con la
-- resolución de su universo.
--
-- **El universo se resuelve por `candidate_id`, no por producto.** Un
-- `candidate_id` es `md5(product_id : supplier : currency)`: un producto
-- comprado a dos proveedores son dos candidatos. Y `p_query` casa contra un
-- blob que **incluye `supplier_name`**, así que una consulta como «zafiro»
-- selecciona candidatos de ese proveedor y no todos los del producto.
-- Colapsar el universo a `product_ids` y volver a expandirlo agregaría
-- proveedores que la consulta original no trajo: la salida dejaría de ser la
-- misma. Por eso el kernel recibe candidatos.
--
-- **El puntaje es relativo al conjunto.** `max(purchase_count) over()` y
-- `max(purchased_units) over()` normalizan contra las filas presentes, y
-- `rank`/`matched_count` también. Dos llamadas con universos distintos dan
-- números distintos **por diseño**: quien compare dos pantallas tiene que
-- saber que un score sólo significa algo dentro de su propio conjunto.
--
-- **El kernel devuelve el item JSON canónico ya armado.** Si devolviera sólo
-- puntajes, cada llamador tendría que volver a leer
-- `purchase_candidate_metrics_v1` —la vista cara— para construir la respuesta.
-- La proyección queda en un único sitio y los llamadores sólo agregan.
--
-- **Equivalencia.** `rank_purchase_candidates_v1` conserva firma, permisos y
-- envelope, y ahora resuelve su universo y delega. El arnés
-- `supabase/manual_checks/verification/purchase_ranking_equivalence_golden.sql`
-- compara su salida —sin `asOf`— antes y después, en los seis caminos ×
-- 3 perfiles × 4 gamas: exacto, categoría raíz, categoría hija, texto por
-- producto, **texto que casa sólo por proveedor**, texto vacío y categoría sin
-- historial.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. El dueño del scoring.
--
-- El cuerpo es el de `rank_purchase_candidates_v1` a partir de `filtered`, con
-- una sola diferencia: el universo llega dado en `p_candidate_ids` en vez de
-- derivarse de producto/categoría/texto.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.purchase_candidate_scores_internal_v1(
  p_tenant_id uuid,
  p_candidate_ids uuid[],
  p_profile text,
  p_gama text default null
)
returns table (
  candidate_id uuid,
  product_id uuid,
  rank integer,
  matched_count integer,
  ranking_score numeric,
  item jsonb
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
begin
  if p_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local')
     or (p_gama is not null and p_gama not in ('economica', 'media', 'alta'))
  then
    raise exception 'Invalid purchase scoring arguments' using errcode = '22023';
  end if;

  return query
  with gama_scope as materialized (
    -- La banda del tenant se resuelve UNA vez y se materializa.
    --
    -- `product_gama_v1` deriva bandas con funciones de ventana sobre las
    -- métricas completas: sin materializar, el planificador la reevalúa por
    -- fila y el ranking se pasa de su presupuesto. Son ~50 marcas.
    select
      band.category_id,
      lower(btrim(band.brand)) as brand_key,
      band.band,
      band.band_is_confident
    from public.product_gama_v1 band
    where band.tenant_id = p_tenant_id
  ), filtered as materialized (
    select metric.*,
      gama.band as gama_band,
      gama.band_is_confident as gama_is_confident
    from public.purchase_candidate_metrics_v1 metric
    left join gama_scope gama
      on gama.category_id = metric.category_id
     and gama.brand_key = lower(btrim(metric.brand))
    where metric.tenant_id = p_tenant_id
      and metric.candidate_id = any(p_candidate_ids)
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
      ::numeric as computed_score,
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
        -- `candidate_id` sin calificar chocaría con el parámetro OUT del
        -- mismo nombre: en plpgsql los OUT de un `returns table` ensombrecen
        -- las columnas, y el desempate quedaría ambiguo.
        order by computed_score desc, evidence_score desc,
          latest_purchase_at desc, scored.candidate_id
      )::integer as computed_rank,
      count(*) over()::integer as computed_matched_count
    from scored
  )
  select numbered.candidate_id,
    numbered.product_id,
    numbered.computed_rank,
    numbered.computed_matched_count,
    round(numbered.computed_score, 6),
    -- Proyección copiada literal de `rank_purchase_candidates_v1`: los
    -- únicos cambios son los alias que el kernel renombró para no chocar
    -- con sus parámetros OUT. Reescribirla de memoria produjo una versión
    -- con nueve campos distintos, y por eso el arnés golden existe.
    jsonb_build_object(
      'candidateId', numbered.candidate_id,
      'rank', numbered.computed_rank,
      'rankingProfile', p_profile,
      'rankingVersion', 'purchase-ranking-v1',
      'rankingScore', round(numbered.computed_score, 6),
      'productId', numbered.product_id,
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
    )
  from numbered;
end;
$$;

revoke all on function public.purchase_candidate_scores_internal_v1(
  uuid, uuid[], text, text
) from public, anon, authenticated, service_role;

comment on function public.purchase_candidate_scores_internal_v1(
  uuid, uuid[], text, text
) is
  'Single owner of purchase candidate scoring. Consumes candidate identities (product+supplier+currency), not products, because a text query may match on supplier_name and collapsing to products would re-expand into suppliers the query never selected. Scores are relative to the supplied set.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. El wrapper conserva su firma y delega.
--
-- Resuelve exactamente el mismo universo que resolvía antes —los tres caminos
-- con sus mismos filtros— y lo entrega como identidades de candidato.
-- ───────────────────────────────────────────────────────────────────────────
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
  v_candidate_ids uuid[];
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

  -- El universo, con los mismos filtros de siempre. El token de texto se
  -- compara contra el blob que incluye `supplier_name`: por eso una consulta
  -- puede seleccionar candidatos sin que su producto la contenga.
  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = v_tenant_id and category.id = p_category_id
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_tenant_id and child.is_active is true
  )
  select array_agg(metric.candidate_id)
  into v_candidate_ids
  from public.purchase_candidate_metrics_v1 metric
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
    ));

  select coalesce(jsonb_agg(scored.item order by scored.rank)
      filter (where scored.rank <= p_limit), '[]'::jsonb),
    coalesce(max(scored.matched_count), 0)
  into v_items, v_total
  from public.purchase_candidate_scores_internal_v1(
    v_tenant_id, coalesce(v_candidate_ids, array[]::uuid[]), p_profile, p_gama
  ) scored;

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

comment on function public.rank_purchase_candidates_v1(
  text, uuid, uuid, text, integer, text
) is
  'Deterministic purchase candidate ranking. Resolves its universe (exact product, category subtree or bounded text that may match on supplier name) to candidate identities and delegates scoring to purchase_candidate_scores_internal_v1. Output is unchanged.';

commit;
