-- Reproducción del ranking por texto libre que no cabe en su presupuesto.
--
-- Defecto abierto (2026-08-17): `rank_purchase_candidates_v1` con `p_query`
-- tarda ~32 s contra un `statement_timeout` de 4,5 s, con los 267 candidatos
-- del taller real. La app NO lo usa —siempre rankea por producto exacto, que
-- responde en ~2 s— pero bloquea cablear la rama de texto.
--
-- Este archivo es el cuerpo de la función con sus parámetros ya sustituidos:
-- reproduce los 32 s como consulta plana, así que se puede investigar con
-- EXPLAIN ANALYZE en una sesión con timeout largo, sin tocar la función.
--
-- Lo que el plan ya dice (explain sin ejecutar):
--   · costo estimado 588 contra 32 s reales;
--   · la subconsulta de métricas estima `rows=1` donde hay 267;
--   · con esa estimación el planificador elige bucles anidados aguas abajo.
--
-- Descartado con medición, no con corazonada:
--   · sólo el CTE `filtered`, sin las etapas siguientes: 3,0 s
--   · el mismo cuerpo con el tenant literal o desde subconsulta: igual de rápido
--   · escaneo de todos los tenants: 2,9 s → no es el filtro de tenant
--   · `assistant_normalize_query_internal_v1`: ~2 ms por llamada
--   · `tenant_business_date` por fila: sacarla no bajó el tiempo, y sacarla mal
--     rompió el camino rápido (revertido en 20260817129000)
--
-- CAUSA, ya explicada con números (bisección por etapas, 2026-08-17):
--
--   · `bounded` —la primera etapa después de `filtered`— ya cuesta 33 s, y lo
--     único que agrega son dos funciones de ventana sobre 29 filas. Lo que
--     cambia es que proyecta `filtered.*`, o sea TODAS las columnas de la vista.
--   · `tenant_business_date` cuesta ~60 ms por llamada: escanea
--     `pg_catalog.pg_timezone_names`, que tiene 1.194 filas.
--   · La vista la llama TRES veces por fila: dos dentro del EXISTS de
--     `is_confirmed_local` y una en `evidence_age_days`.
--   · Esas columnas se calculan para los 267 candidatos del tenant, no para los
--     29 que sobreviven al filtro de texto.
--
--   267 filas × 3 llamadas × 60 ms ≈ 48 s. El orden de magnitud calza.
--
-- Por qué despista: una sonda con `count(*)` da 3 s, porque el planificador
-- poda esas columnas cuando nadie las pide. Hay que medir proyectando.
--
-- POR QUÉ EL PRIMER ARREGLO NO SIRVIÓ: hoistear la fecha a un CTE sobre
-- `public.tenants` (20260817126000) la evaluaba para todos los tenants activos,
-- y `tenant_business_date` exige membresía: empezó a lanzar 42501 en lecturas
-- amplias. Acotarla al agregado (20260817128000) obligó a materializar todo
-- antes de filtrar y rompió el camino por producto exacto. Ambas revertidas en
-- 20260817129000.
--
-- DIRECCIÓN CORRECTA, sin validar todavía: la fecha del negocio de un tenant es
-- una sola por consulta. Hay que evaluarla una vez para el tenant que pregunta
-- —sin arrastrar el agregado completo ni tocar tenants ajenos— o abaratar
-- `tenant_business_date` para que no escanee el catálogo de zonas horarias en
-- cada llamada. Lo segundo beneficia a todo el ERP, no sólo a este ranking.
--
-- La base local con datos de fixture NO reproduce: 1,5 ms. Cualquier hipótesis
-- se valida acá, en lectura, antes de tocar la definición compartida.
  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid and category.id = null::uuid
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid and child.is_active is true
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
    where band.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
  ), filtered as materialized (
    select metric.*,
      gama.band as gama_band,
      gama.band_is_confident as gama_is_confident
    from public.purchase_candidate_metrics_v1 metric
    left join gama_scope gama
      on gama.category_id = metric.category_id
     and gama.brand_key = lower(btrim(metric.brand))
    where metric.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and (null::uuid is null or metric.product_id = null::uuid)
      and (null::uuid is null or metric.category_id in (
        select id from category_scope
      ))
      and (public.assistant_normalize_query_internal_v1('camara') is null or not exists (
        select 1 from regexp_split_to_table(public.assistant_normalize_query_internal_v1('camara'), ' +') token
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
        when null::text is null then 0
        when gama_band is null then 0.5
        when gama_band = null::text then 1
        when (null::text = 'media') or (gama_band = 'media') then 0.5
        else 0
      end::numeric as gama_score
    from bounded
  ), scored as (
    select dimensions.*,
      -- Sin gama pedida el puntaje queda identico al anterior; con gama
      -- pedida, un cuarto del peso pasa a la banda.
      (1 - case when null::text is null then 0 else 0.25 end) *
      case 'balanced'
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
      + case when null::text is null then 0 else 0.25 * gama_score end
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
      'rankingProfile', 'balanced',
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
    ) order by rank) filter (where rank <= 5), '[]'::jsonb),
    coalesce(max(matched_count), 0)
  from numbered;
