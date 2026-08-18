-- Fase B2, corte 5: las opciones externas de una necesidad, después del stock.
--
-- **Qué agrega.** `get_supply_need_external_candidates_v1`: la primera lectura
-- pública que propone comprar. Rankea el conjunto elegible de la necesidad con
-- el kernel de scoring, mezcla el objetivo comercial tipado del corte 4 y
-- pagina accionables y no verificados por separado.
--
-- **La guarda stock-first es una excepción, no un estado.** Si el conjunto
-- elegible bloquea —hay una alternativa interna que cubre entera la
-- necesidad— y nadie registró un rechazo interno explícito, la lectura levanta
-- `P0001 stock_first_required` **antes de tocar el kernel**. Devolver una lista
-- vacía con un rótulo sería peor: una interfaz la mostraría como «no hay
-- proveedores» y el operador compraría lo que ya tiene en la bodega. El error
-- es la única forma de que el paso saltado se note.
--
-- **Una sola evaluación técnica.** `supply_need_stock_bundle_internal_v1` se
-- llama exactamente una vez por invocación, en todos los caminos que pasan la
-- validación de argumentos. Incluso cuando la necesidad ya está cerrada: el
-- envelope queda uniforme —carril, categoría, universo y cobertura viajan
-- siempre— y el invariante «una vez» es una propiedad dura que una prueba
-- puede afirmar, en vez de «a veces cero».
--
-- **El orden que la medición impone.** El conjunto completo de `candidate_id`
-- se resuelve **primero**, desde los `product_id` elegibles, y sólo después se
-- llama **una** vez a `purchase_candidate_scores_internal_v1`. Derivar los ids
-- desde `purchase_candidate_metrics_v1` dentro de la misma sentencia que llama
-- al kernel midió **6.494 ms** en producción: el planificador evalúa la vista
-- una vez por fila. Está prohibido y documentado en
-- `manual_checks/diagnostics/purchase_candidate_any_shape_probe.sql`.
--
-- **Se puntúa el conjunto entero antes de cortar.** Rerank, split por grupo y
-- paginación ocurren después. Cortar antes daría una primera página que no es
-- la mejor, y el objetivo comercial —que reordena— dejaría de poder rescatar a
-- un candidato que venía en la página tres.
--
-- **El puntaje sigue siendo relativo a todo el `eligible_set`**, porque el
-- kernel normaliza contra las filas que recibe. El envelope lo dice en
-- `scoreScope` en vez de dejar que alguien compare dos pantallas.
--
-- ───────────────────────────────────────────────────────────────────────────
-- LA AUDITORÍA DE MONEDA QUE CAMBIÓ ESTE CORTE
-- ───────────────────────────────────────────────────────────────────────────
--
-- `projected_gross_margin_ratio` de la vista resta
-- `latest_landed_unit_cost_net` —en `aggregate.currency_code`, la moneda de la
-- **factura de compra**— de `catalog_sale_price_net` —derivado de
-- `products.price`—. La vista nunca comparó las dos monedas, así que
-- **`economy_score` podía premiar una resta entre monedas distintas**: con un
-- costo histórico en USD y un precio de venta en CLP, el margen sale
-- absurdamente alto y el candidato gana. No hay tipo de cambio en este
-- sistema, así que ese número no es convertible: es desconocido.
--
-- La autoridad no había que inferirla. `products.price_currency` **existe**
-- (`not null default 'CLP'`) junto a `products.cost_currency`, y en producción
-- los 1.613 productos activos están en CLP, igual que los 268 candidatos
-- históricos. El defecto es real y hoy está **latente**, no activo: por eso se
-- corrige aquí sin cambiar un solo número de la salida vigente.
--
-- Tres decisiones, con su razón:
--
-- 1. **La vista publica `price_currency`** como columna aditiva al final
--    —después de `brand_id`, único sitio que `create or replace view` admite—.
--    `tenants.currency` **no** es un sustituto: es la moneda del taller *hoy*,
--    no la del precio de catálogo, y usarla habría sido la misma inferencia
--    que este corte vino a eliminar. `cost_currency` se queda afuera a
--    propósito: el candidato histórico se denomina en su propia
--    `currency_code`, la de la factura, no en la del costo del catálogo.
--
-- 2. **La vista y el kernel tratan una rentabilidad no comparable como
--    desconocida**, tanto por moneda distinta como por flete incompleto. La
--    vista no fabrica la resta; `economy_score` toma el mismo valor neutro 0.35
--    que ya usaba cuando el margen es nulo, y el item publica
--    `projectedUnitGrossProfit` y `projectedGrossMarginRatio` en **null**.
--    Nulo ya era un valor legal de esos campos —un producto sin precio de
--    venta los deja nulos—, así que ningún consumidor aprende una forma nueva.
--    No se agregó **ninguna clave** al item: el golden compara el JSON entero
--    y una clave nueva lo rompería aunque el número no cambiara.
--
-- 3. **El wrapper no se toca y su golden queda intacto.** El arnés es CLP puro
--    y producción también, así que la corrección es un no-op bit a bit ahí, y
--    una regresión cross-currency nueva demuestra que sí muerde donde importa.
--
-- **Y por eso las dos señales económicas del objetivo no comparten condición:**
--   · `maxLandedUnitCostNet` es un monto **denominado**: se compara contra
--     `target.currencyCode` —la moneda **de la revisión** que fijó el tope, no
--     la del taller de hoy—;
--   · `minGrossMarginRatio` es un **ratio adimensional**: lo que hay que
--     probar no es la moneda del tope sino que el ratio sea computable, o sea
--     que el costo del candidato y el precio de catálogo estén en la misma
--     moneda: `candidate.currency_code = catalogSalePriceCurrency`.
--   Confundirlas habría declarado `unknown` un margen perfectamente válido, o
--   peor, habría aceptado uno que mezcla monedas.
--
-- **El flete decide si el costo aterrizado es costo aterrizado.** Un número no
-- nulo no basta: con `freight_evidence_status` fuera de `complete`/`none` la
-- asignación de flete no es reproducible y comparar el base como si fuera
-- landed premia falsamente al candidato. Los dos valores reales de esa columna
-- que significan «incompleto» son `partial_currency` y
-- `unavailable_denominator` —no `partial`/`missing`/`unclassified`, que no
-- existen—, así que la regla se escribe por la lista positiva.
--
-- **Precedencia de razones, fija:** moneda primero, flete después, ausencia al
-- final. Nunca se convierte nada y un `unknown` jamás vale cero: se excluye
-- del promedio.
--
-- Forward-only. `rank_purchase_candidates_v1`, `get_supply_need_stock_resolution_v1`,
-- `set_supply_need_commercial_target_v1` y todas las `*_v1` anteriores quedan
-- con su firma, sus permisos y su salida.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. La vista publica la moneda del precio de catálogo.
--
-- Cuerpo carácter por carácter el de
-- `20260817180000_purchase_candidate_brand_identity.sql` —la definición
-- **vigente**— con **una** columna aditiva al final. La vista se redefine en
-- seis migraciones; partir de una anterior podría deshacer en silencio una
-- corrección que un revert restauró.
-- ───────────────────────────────────────────────────────────────────────────
create or replace view public.purchase_candidate_metrics_v1
with (security_invoker = true)
as
with exact_observations as (
  select observation.*
  from public.purchase_line_landed_cost_observations_v1 observation
  where observation.product_id is not null
), aggregates as (
  select
    tenant_id,
    product_id,
    supplier_id,
    supplier_name,
    currency_code,
    count(distinct purchase_invoice_id)::integer as purchase_count,
    count(*)::integer as observation_count,
    sum(quantity)::numeric(18,4) as purchased_units,
    min(economic_date) as first_purchase_at,
    max(economic_date) as last_purchase_at,
    avg(landed_unit_cost_net)::numeric(18,6) as average_landed_unit_cost_net,
    stddev_samp(landed_unit_cost_net)::numeric(18,6)
      as landed_cost_standard_deviation,
    count(*) filter (
      where freight_evidence_status in ('complete', 'none')
    )::integer as complete_cost_observation_count
  from exact_observations
  group by tenant_id, product_id, supplier_id, supplier_name, currency_code
), latest as (
  select distinct on (
    tenant_id, product_id, supplier_id, supplier_name, currency_code
  )
    tenant_id,
    product_id,
    supplier_id,
    supplier_name,
    currency_code,
    purchase_invoice_id as latest_purchase_invoice_id,
    purchase_invoice_line_id as latest_purchase_invoice_line_id,
    economic_date as latest_purchase_at,
    base_unit_cost_net as latest_base_unit_cost_net,
    allocated_freight_net as latest_allocated_freight_net,
    landed_unit_cost_net as latest_landed_unit_cost_net,
    freight_evidence_status as latest_freight_evidence_status,
    identity_quality as latest_identity_quality
  from exact_observations
  order by tenant_id, product_id, supplier_id, supplier_name, currency_code,
    economic_date desc, purchase_invoice_line_id desc
)
select
  aggregate.tenant_id,
  md5(
    aggregate.product_id::text || ':' ||
    coalesce(aggregate.supplier_id::text, aggregate.supplier_name, '') || ':' ||
    aggregate.currency_code
  )::uuid as candidate_id,
  aggregate.product_id,
  product.name as product_name,
  product.sku as product_sku,
  product.category_id,
  coalesce(category.full_path, category.name, product.category_name,
    product.category) as category_path,
  coalesce(product.brand, brand.name) as brand,
  aggregate.supplier_id,
  aggregate.supplier_name,
  supplier.website as supplier_website,
  nullif(concat_ws(', ', supplier.comuna, supplier.city), '')
    as supplier_location,
  exists (
    select 1
    from public.supplier_relationship_tags tag
    where tag.tenant_id = aggregate.tenant_id
      and tag.supplier_id = aggregate.supplier_id
      and tag.tag_code in ('local', 'local_workshop', 'emergency_local')
      and tag.valid_from <= public.tenant_business_date(aggregate.tenant_id)
      and (tag.valid_to is null
        or tag.valid_to >= public.tenant_business_date(aggregate.tenant_id))
  ) as is_confirmed_local,
  aggregate.currency_code,
  aggregate.purchase_count,
  aggregate.observation_count,
  aggregate.purchased_units,
  aggregate.first_purchase_at,
  aggregate.last_purchase_at,
  latest.latest_purchase_invoice_id,
  latest.latest_purchase_invoice_line_id,
  latest.latest_base_unit_cost_net,
  latest.latest_allocated_freight_net,
  latest.latest_landed_unit_cost_net,
  aggregate.average_landed_unit_cost_net,
  aggregate.landed_cost_standard_deviation,
  latest.latest_freight_evidence_status,
  latest.latest_identity_quality,
  aggregate.complete_cost_observation_count,
  product.price::numeric(18,4) as catalog_sale_price_gross,
  case
    when product.price is null or product.price <= 0 then null
    when coalesce(product.tax_rate, 19) > 1
      then (product.price / (1 + coalesce(product.tax_rate, 19) / 100))
    else (product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0)))
  end::numeric(18,6) as catalog_sale_price_net,
  case
    when product.price is null or product.price <= 0
      or product.price_currency is distinct from aggregate.currency_code
      or latest.latest_freight_evidence_status is null
      or latest.latest_freight_evidence_status not in ('complete', 'none')
      then null
    else (
      (case
        when coalesce(product.tax_rate, 19) > 1
          then product.price / (1 + coalesce(product.tax_rate, 19) / 100)
        else product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0))
      end) - latest.latest_landed_unit_cost_net
    )::numeric(18,6)
  end as projected_unit_gross_profit,
  case
    when product.price is null or product.price <= 0
      or product.price_currency is distinct from aggregate.currency_code
      or latest.latest_freight_evidence_status is null
      or latest.latest_freight_evidence_status not in ('complete', 'none')
      then null
    else (
      ((case
        when coalesce(product.tax_rate, 19) > 1
          then product.price / (1 + coalesce(product.tax_rate, 19) / 100)
        else product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0))
      end) - latest.latest_landed_unit_cost_net)
      / nullif((case
        when coalesce(product.tax_rate, 19) > 1
          then product.price / (1 + coalesce(product.tax_rate, 19) / 100)
        else product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0))
      end), 0)
    )::numeric(12,8)
  end as projected_gross_margin_ratio,
  greatest(
    public.tenant_business_date(aggregate.tenant_id)
      - latest.latest_purchase_at::date,
    0
  )::integer as evidence_age_days,
  product.updated_at as sale_price_updated_at,
  'unverified'::text as supplier_availability,
  latest.latest_purchase_at,
  -- CREATE OR REPLACE VIEW only permits additive columns at the end of the
  -- existing projection. Keeping the media triple here preserves every
  -- previously published ordinal/name and makes this migration forward-only.
  nullif(btrim(product.image_url_optimized), '') as image_url_optimized,
  nullif(btrim(product.image_url), '') as image_url,
  coalesce(product.image_urls, array[]::text[]) as image_urls,
  -- Identidad de marca, al final de la proyección porque
  -- `create or replace view` sólo admite columnas aditivas ahí. La glosa
  -- `brand` de más arriba se conserva intacta: hay productos cuya única
  -- marca es ese texto legado.
  product.brand_id,
  -- La moneda del precio de catálogo, autoritativa y ya existente en
  -- `products` (`not null default 'CLP'`). Sin ella, `projected_gross_margin_ratio`
  -- resta un costo en la moneda de la factura de un precio en otra moneda y
  -- nadie puede notarlo. `cost_currency` NO se publica: el candidato histórico
  -- se denomina en `currency_code`, la de la compra, no en la del catálogo.
  product.price_currency
from aggregates aggregate
join latest
  on latest.tenant_id = aggregate.tenant_id
 and latest.product_id = aggregate.product_id
 and latest.supplier_id is not distinct from aggregate.supplier_id
 and latest.supplier_name is not distinct from aggregate.supplier_name
 and latest.currency_code = aggregate.currency_code
join public.products product
  on product.tenant_id = aggregate.tenant_id
 and product.id = aggregate.product_id
left join public.product_categories category
  on category.tenant_id = product.tenant_id
 and category.id = product.category_id
left join public.product_brands brand
  on brand.tenant_id = product.tenant_id
 and brand.id = product.brand_id
left join public.suppliers supplier
  on supplier.tenant_id = aggregate.tenant_id
 and supplier.id = aggregate.supplier_id
where product.is_active is true;

comment on view public.purchase_candidate_metrics_v1 is
  'Historical purchase candidates per product, supplier and currency, with landed cost, freight evidence, catalog margin base, product media, brand identity and the catalog sale price currency. brand_id is the durable identity a commercial preference matches on. Projected profit and margin are null unless catalog price and purchase cost share a currency and freight evidence is complete or none; this system has no FX and an unreconciled freight amount is not a landed cost.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. El kernel deja de tratar una resta entre monedas como margen.
--
-- Un solo cambio semántico, en dos sitios que dicen lo mismo: cuando
-- `price_currency` y `currency_code` difieren, el margen es **desconocido**.
--   · `economy_score` toma 0.35, el mismo neutro que ya usaba para un margen
--     nulo — no un valor nuevo, y por eso no hay una tercera semántica que
--     aprender;
--   · el item publica `projectedUnitGrossProfit` y `projectedGrossMarginRatio`
--     en null, que es lo que ya publicaba para un producto sin precio de venta.
--
-- **Ninguna clave nueva.** El arnés golden compara el item entero; agregar
-- `catalogSalePriceCurrency` aquí lo rompería aunque no cambiara un número. La
-- moneda del precio de catálogo la publica la RPC nueva, en sus propios
-- campos, junto a la razón `currency_mismatch_no_fx`.
--
-- **La salida vigente no se mueve.** El arnés es CLP puro y producción tiene
-- 268 candidatos, todos CLP contra 1.613 productos activos también en CLP: el
-- diff del golden es vacío por construcción, no por suerte.
--
-- El resto del cuerpo es el de `20260817190000` sin tocar.
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
      gama.band_is_confident as gama_is_confident,
      -- La rentabilidad sólo es comparable si ambos importes comparten moneda
      -- y el costo aterrizado incluye evidencia de flete reproducible.
      (metric.price_currency is not distinct from metric.currency_code
        and metric.latest_freight_evidence_status in ('complete', 'none'))
        as margin_is_comparable
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
        when projected_gross_margin_ratio is null
          or not margin_is_comparable then 0.35
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
        + case when catalog_sale_price_net is not null
            and margin_is_comparable then 0.20 else 0 end
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
          and margin_is_comparable
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
      -- Moneda incompatible o flete incompleto: desconocido, no una resta.
      -- `null` ya era el valor de estos campos sin precio de venta.
      'projectedUnitGrossProfit',
        case when margin_is_comparable then projected_unit_gross_profit end,
      'projectedGrossMarginRatio',
        case when margin_is_comparable then projected_gross_margin_ratio end,
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
  'Single owner of purchase candidate scoring. Consumes candidate identities (product+supplier+currency), not products, because a text query may match on supplier_name and collapsing to products would re-expand into suppliers the query never selected. Scores are relative to the supplied set. Profitability is unknown when cost and sale currencies differ or freight evidence is incomplete: economy_score stays neutral, profitability earns no catalog-price evidence reward, and projected profit/margin are null.';


-- ───────────────────────────────────────────────────────────────────────────
-- 3. El envelope, con un solo dueño y escrito clave por clave.
--
-- **Por qué es una función y no seis `jsonb_build_object` repartidos.** Este
-- corte tiene siete caminos que no rankean y uno que sí. Con el envelope
-- escrito en cada rama, la primera clave que alguien agregue en una sola de
-- ellas convierte el contrato público en algo que depende del estado — y la
-- Fase B1 ya pagó exactamente ese error: `bundle - 'orderedItems'` filtró tres
-- claves que la rama no-ok nunca había publicado.
--
-- **Nada se resta de nada.** Cada clave se nombra. El bundle puede crecer;
-- esto no crece con él.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_external_envelope_internal_v1(
  p_bundle jsonb,
  p_commercial jsonb,
  p_profile text,
  p_profile_source text,
  p_status text,
  p_counts jsonb,
  p_candidate_safe_limit integer,
  p_items jsonb,
  p_unverified_items jsonb,
  p_page jsonb,
  p_unverified_page jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    -- Identidad y concurrencia. `needVersion` y `revisionNo` son lo que el
    -- comando de rechazo y el de objetivo exigen: sin ellos la lectura no es
    -- autocontenida y la interfaz tendría que adivinar.
    'needId', p_bundle -> 'needId',
    'needVersion', p_bundle -> 'needVersion',
    'revisionNo', p_bundle -> 'revisionNo',
    'needSupplyState', p_commercial -> 'needSupplyState',
    'quantity', p_bundle -> 'quantity',
    'unit', p_bundle -> 'unit',

    -- Objetivo comercial. `targetCurrencyCode` es la moneda **de la revisión**
    -- que fijó el objetivo, no la del taller de hoy: releer un tope en la
    -- moneda actual lo reinterpretaría, y este sistema no tiene tipo de cambio.
    'targetRevisionNo', p_commercial -> 'targetRevisionNo',
    'target', p_commercial -> 'target',
    'targetCurrencyCode', p_commercial -> 'currencyCode',
    'tenantCurrencyCode', p_commercial -> 'tenantCurrencyCode',
    'preferredBrandAvailable', p_commercial -> 'preferredBrandAvailable',
    'legacyPreferenceNote', p_commercial -> 'legacyPreferenceNote',

    -- Perfil de ranking. El origen viaja para que `balanced` por omisión no se
    -- confunda con `balanced` elegido.
    'rankingProfile', to_jsonb(p_profile),
    'rankingProfileSource', to_jsonb(p_profile_source),
    'rankingVersion', to_jsonb('supply-need-external-candidates-v1'::text),

    -- Carril, categoría y universo: lo que la evaluación técnica resolvió.
    'lane', p_bundle -> 'lane',
    'categoryId', p_bundle -> 'categoryId',
    'universeSize', p_bundle -> 'universeSize',
    'safeLimit', p_bundle -> 'safeLimit',
    'availableFields', coalesce(p_bundle -> 'availableFields', '[]'::jsonb),
    'coverage', p_bundle -> 'coverage',
    'blocksExternal', p_bundle -> 'blocksExternal',
    'internalStockRejectionReason',
      p_bundle -> 'internalStockRejectionReason',

    'status', to_jsonb(p_status),

    -- **El fanout histórico tiene su propio techo y su propio nombre.**
    -- `universeSize`/`safeLimit` de arriba son de la Fase B1 y cuentan
    -- **productos del catálogo**; esto cuenta combinaciones
    -- producto×proveedor×moneda de lo ya comprado. Reusar aquellos nombres
    -- habría pisado un hecho distinto con otro, y `analysis_too_broad` es
    -- justamente el estado que necesita que los dos números convivan.
    'candidateUniverseSize', coalesce(p_counts -> 'candidates', to_jsonb(0)),
    'candidateSafeLimit', p_candidate_safe_limit,

    -- **El puntaje es relativo al conjunto entero**, no a la página ni al
    -- grupo. Dos pantallas con universos distintos dan números distintos por
    -- diseño; decirlo acá es lo que impide compararlos.
    'scoreScope', jsonb_build_object(
      'basis', 'eligible_set',
      'candidateCount', coalesce(p_counts -> 'candidates', to_jsonb(0)),
      'candidateSafeLimit', p_candidate_safe_limit,
      'comparableAcrossRequests', false
    ),

    -- Dos arreglos, dos páginas. `unverified` no es peor: es «no lo sé», y
    -- mezclarlo con lo accionable obligaría al operador a descartar a mano una
    -- carencia del ERP.
    'items', p_items,
    'unverifiedItems', p_unverified_items,
    'counts', p_counts,
    'page', p_page,
    'unverifiedPage', p_unverified_page,

    -- Historial de compra no es disponibilidad de proveedor. Nunca.
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  )
$$;

revoke all on function public.supply_need_external_envelope_internal_v1(
  jsonb, jsonb, text, text, text, jsonb, integer, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

comment on function public.supply_need_external_envelope_internal_v1(
  jsonb, jsonb, text, text, text, jsonb, integer, jsonb, jsonb, jsonb, jsonb
) is
  'Single owner of the external-candidates envelope. Every key is named; nothing is subtracted from the bundle, so a future bundle key cannot leak into the public contract the way it did in phase B1.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Una página, con `hasMore` y `nextOffset` derivados del mismo lugar.
--
-- Los dos grupos paginan independientes; escribir la aritmética dos veces es
-- cómo se llega a que uno diga `hasMore` y el otro no para el mismo estado.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_external_page_internal_v1(
  p_limit integer,
  p_offset integer,
  p_total integer
)
returns jsonb
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'limit', p_limit,
    'offset', p_offset,
    'total', p_total,
    'returned', greatest(least(p_total - p_offset, p_limit), 0),
    'hasMore', p_total > p_offset + p_limit,
    'nextOffset', case
      when p_total > p_offset + p_limit then p_offset + p_limit
    end
  )
$$;

revoke all on function public.supply_need_external_page_internal_v1(
  integer, integer, integer
) from public, anon, authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Las opciones externas de una necesidad.
--
-- Internal para que las pruebas puedan bajar el techo de fanout a un número
-- pequeño sin sembrar cientos de facturas: probar `analysis_too_broad` con el
-- techo real exigiría una fixture que nadie mantendría, y una prueba que no se
-- corre no defiende nada.
--
-- **Los estados, y por qué cada uno existe:**
--   · `supply_closed`            la necesidad ya está cubierta o cancelada; no
--                                se propone comprar, aunque el conjunto
--                                elegible siga existiendo;
--   · `identity_unresolved` /
--     `needs_refinement`         estados **técnicos** del bundle, devueltos tal
--                                cual: quien los interpreta ya existe (Fase B1);
--   · `technical_conflict`       carril exacto cuyo producto contradice la
--                                ficha. No se rankea: proponer proveedores para
--                                algo que ya sabemos que no calza es ruido caro;
--   · `analysis_too_broad`       el fanout histórico supera el techo seguro. NO
--                                es `needs_refinement`: ahí sobra el catálogo,
--                                acá sobran las combinaciones producto×proveedor
--                                de lo ya comprado, y la acción es otra;
--   · `no_eligible_products`     la evaluación técnica no dejó ningún producto
--                                en pie —todo entró en conflicto—. La acción es
--                                revisar los criterios;
--   · `no_historical_candidates` hay productos elegibles y ninguno se compró
--                                nunca. La acción es buscar un proveedor nuevo.
--                                **No** es `verifiedEmpty`: esa palabra afirma
--                                que se verificó disponibilidad, y acá sólo se
--                                miró el historial;
--   · `success`                  hay candidatos puntuados.
--
-- **Las tres señales del objetivo, y su matemática.** Si existe al menos una
-- señal **conocida**, `finalScore = 0.75 * legacyScore + 0.25 *
-- promedio(conocidas)`. Si todas faltan, son `unknown` o no se pidieron,
-- `finalScore` es **exactamente** `legacyScore`: esa rama devuelve el número
-- sin tocarlo, en vez de multiplicarlo por 0.75 y sumarle un cero, que
-- reintroduciría error de redondeo y rompería la igualdad que la prueba afirma.
--
-- La gama **no** es una cuarta señal: ya entra al kernel como un cuarto del
-- peso. Viaja rotulada `delegated` para que nadie concluya que se ignoró, y
-- nunca entra al promedio.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_external_candidates_internal_v1(
  p_tenant_id uuid,
  p_need_id uuid,
  p_limit integer default 10,
  p_offset integer default 0,
  p_unverified_limit integer default 5,
  p_unverified_offset integer default 0,
  p_max_candidates integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_bundle jsonb;
  v_commercial jsonb;
  v_context record;
  v_target jsonb;
  v_profile_raw text;
  v_profile text;
  v_profile_source text;
  v_gama text;
  v_preferred_brand_id uuid;
  v_preferred_brand_key text;
  v_max_cost numeric;
  v_min_margin numeric;
  v_target_currency text;
  v_eligible_products uuid[];
  v_eligible_count integer := 0;
  v_states jsonb := '[]'::jsonb;
  v_candidate_ids uuid[];
  v_meta jsonb := '[]'::jsonb;
  v_candidate_count integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_unverified_items jsonb := '[]'::jsonb;
  v_actionable_total integer := 0;
  v_unverified_total integer := 0;
  v_strong integer := 0;
  v_weak integer := 0;
  v_no_criteria integer := 0;
  v_counts jsonb;
begin
  if p_tenant_id is null or p_need_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 50
     or p_offset is null or p_offset < 0 or p_offset > 5000
     or p_unverified_limit is null or p_unverified_limit not between 1 and 50
     or p_unverified_offset is null or p_unverified_offset < 0
     or p_unverified_offset > 5000
     or p_max_candidates is null or p_max_candidates not between 1 and 5000
  then
    raise exception 'Invalid external candidate bounds' using errcode = '22023';
  end if;

  -- El objetivo comercial trae además `needVersion` y `needSupplyState`, así
  -- que esta lectura hace de comprobación de existencia: una necesidad de otro
  -- taller levanta P0002 acá, antes de cualquier trabajo.
  v_commercial := public.supply_need_commercial_target_internal_v1(
    p_tenant_id, p_need_id
  );

  -- El perfil de ranking vive en los `constraints` de la revisión que gobierna.
  -- Se lee del dueño único de esa autoridad; una consulta local sería una
  -- segunda verdad sobre cuál revisión manda.
  select * into v_context
  from public.supply_need_resolution_context_internal_v1(p_tenant_id, p_need_id);

  select entry.value ->> 'value' into v_profile_raw
  from jsonb_array_elements(coalesce(v_context.constraints, '[]'::jsonb))
    entry(value)
  where entry.value ->> 'kind' = 'ranking_profile'
  limit 1;

  if v_profile_raw in ('balanced', 'profitability', 'urgent_local') then
    v_profile := v_profile_raw;
    v_profile_source := 'revision';
  else
    -- `update_supply_need_v1` escribe `constraints '[]'`: una necesidad
    -- reinterpretada a mano se queda sin perfil, y eso no puede ser un error.
    -- El origen se publica para que `balanced` por omisión no se confunda con
    -- `balanced` elegido.
    v_profile := 'balanced';
    v_profile_source := case
      when v_profile_raw is null then 'default'
      else 'default_unrecognized'
    end;
  end if;

  -- **La ÚNICA llamada al bundle, en todos los caminos.**
  v_bundle := public.supply_need_stock_bundle_internal_v1(
    p_tenant_id, p_need_id
  );

  v_target := coalesce(v_commercial -> 'target', '{}'::jsonb);
  v_target_currency := v_commercial ->> 'currencyCode';
  v_gama := v_target ->> 'gama';
  v_preferred_brand_id := nullif(v_target ->> 'preferredBrandId', '')::uuid;
  v_max_cost := (v_target ->> 'maxLandedUnitCostNet')::numeric;
  v_min_margin := (v_target ->> 'minGrossMarginRatio')::numeric;

  -- El **nombre vigente** de la marca preferida, normalizado una vez. Es lo
  -- único contra lo que un texto legado puede compararse: esos productos no
  -- tienen identidad, y el nombre de ayer no es evidencia de nada.
  if v_preferred_brand_id is not null then
    select public.assistant_normalize_query_internal_v1(brand.name)
    into v_preferred_brand_key
    from public.product_brands brand
    where brand.id = v_preferred_brand_id
      and (brand.tenant_id is null or brand.tenant_id = p_tenant_id);
  end if;

  v_counts := jsonb_build_object(
    'eligibleProducts', 0, 'candidates', 0,
    'actionable', 0, 'unverified', 0,
    'strong', 0, 'weak', 0, 'noCriteria', 0
  );

  -- ── Los caminos que no rankean ───────────────────────────────────────────
  --
  -- Cerrada primero: si la necesidad ya está cubierta o cancelada, ninguna
  -- otra cosa que sepamos del conjunto elegible cambia la respuesta.
  if (v_commercial ->> 'needSupplyState') in ('covered', 'cancelled') then
    return public.supply_need_external_envelope_internal_v1(
      v_bundle, v_commercial, v_profile, v_profile_source, 'supply_closed',
      v_counts, p_max_candidates, '[]'::jsonb, '[]'::jsonb,
      public.supply_need_external_page_internal_v1(p_limit, p_offset, 0),
      public.supply_need_external_page_internal_v1(
        p_unverified_limit, p_unverified_offset, 0)
    );
  end if;

  if v_bundle ->> 'status' <> 'ok' then
    return public.supply_need_external_envelope_internal_v1(
      v_bundle, v_commercial, v_profile, v_profile_source,
      v_bundle ->> 'status',
      v_counts, p_max_candidates, '[]'::jsonb, '[]'::jsonb,
      public.supply_need_external_page_internal_v1(p_limit, p_offset, 0),
      public.supply_need_external_page_internal_v1(
        p_unverified_limit, p_unverified_offset, 0)
    );
  end if;

  -- Carril exacto que contradice la ficha. El bundle no lo excluye —es el
  -- único producto que la necesidad tiene— y por eso hay que nombrarlo acá.
  if (v_bundle ->> 'lane') = 'exact' and exists (
    select 1
    from jsonb_array_elements(v_bundle -> 'orderedItems') entry(value)
    where entry.value ->> 'matchState' = 'conflict'
  ) then
    return public.supply_need_external_envelope_internal_v1(
      v_bundle, v_commercial, v_profile, v_profile_source, 'technical_conflict',
      v_counts, p_max_candidates, '[]'::jsonb, '[]'::jsonb,
      public.supply_need_external_page_internal_v1(p_limit, p_offset, 0),
      public.supply_need_external_page_internal_v1(
        p_unverified_limit, p_unverified_offset, 0)
    );
  end if;

  -- **La guarda stock-first, antes de tocar el kernel.**
  --
  -- Una excepción y no un estado: una lista vacía rotulada la muestra
  -- cualquier interfaz como «no hay proveedores», y el operador terminaría
  -- comprando lo que ya tiene en bodega. `internalStockRejectionReason` es el
  -- único registro de que alguien miró el stock y lo descartó a propósito.
  if (v_bundle ->> 'blocksExternal')::boolean is true
     and nullif(btrim(coalesce(
       v_bundle ->> 'internalStockRejectionReason', '')), '') is null then
    raise exception 'stock_first_required' using errcode = 'P0001',
      detail = 'Hay stock interno que cubre esta necesidad y nadie lo rechazó explícitamente.',
      hint = 'reject_supply_need_internal_stock_v2';
  end if;

  -- ── El conjunto elegible, sin conflictos ─────────────────────────────────
  select array_agg(distinct (entry.value ->> 'productId')::uuid),
    coalesce(jsonb_agg(jsonb_build_object(
      'productId', entry.value ->> 'productId',
      'matchState', entry.value ->> 'matchState',
      'matchDetail', coalesce(entry.value -> 'matchDetail', '[]'::jsonb)
    )), '[]'::jsonb)
  into v_eligible_products, v_states
  from jsonb_array_elements(v_bundle -> 'orderedItems') entry(value)
  where entry.value ->> 'matchState' <> 'conflict';

  v_eligible_count := coalesce(array_length(v_eligible_products, 1), 0);
  v_counts := v_counts || jsonb_build_object('eligibleProducts', v_eligible_count);

  if v_eligible_count = 0 then
    return public.supply_need_external_envelope_internal_v1(
      v_bundle, v_commercial, v_profile, v_profile_source,
      'no_eligible_products',
      v_counts, p_max_candidates, '[]'::jsonb, '[]'::jsonb,
      public.supply_need_external_page_internal_v1(p_limit, p_offset, 0),
      public.supply_need_external_page_internal_v1(
        p_unverified_limit, p_unverified_offset, 0)
    );
  end if;

  -- ── Resolución del universo de candidatos, en UNA sentencia y sin kernel ──
  --
  -- Acá se paga la única lectura de la vista de candidatos fuera del kernel, y
  -- se aprovecha para traer la metadata que las señales necesitan
  -- —marca, las dos monedas, costo aterrizado, margen y evidencia de flete—.
  -- Volver a consultar la vista después, para «enriquecer» los items, sería la
  -- tercera lectura cara que este diseño existe para evitar.
  --
  -- Y es una sentencia **propia**: derivar los ids desde la vista dentro de la
  -- misma sentencia que llama al kernel midió 6.494 ms en producción.
  select array_agg(metric.candidate_id),
    coalesce(jsonb_agg(jsonb_build_object(
      'candidateId', metric.candidate_id,
      'productId', metric.product_id,
      'brandId', metric.brand_id,
      'brandText', metric.brand,
      'currencyCode', metric.currency_code,
      'priceCurrency', metric.price_currency,
      'landedUnitCostNet', metric.latest_landed_unit_cost_net,
      'grossMarginRatio', metric.projected_gross_margin_ratio,
      'freightEvidence', metric.latest_freight_evidence_status
    )), '[]'::jsonb)
  into v_candidate_ids, v_meta
  from public.purchase_candidate_metrics_v1 metric
  where metric.tenant_id = p_tenant_id
    and metric.product_id = any(v_eligible_products);

  v_candidate_count := coalesce(array_length(v_candidate_ids, 1), 0);
  v_counts := v_counts || jsonb_build_object('candidates', v_candidate_count);

  if v_candidate_count = 0 then
    return public.supply_need_external_envelope_internal_v1(
      v_bundle, v_commercial, v_profile, v_profile_source,
      'no_historical_candidates',
      v_counts, p_max_candidates, '[]'::jsonb, '[]'::jsonb,
      public.supply_need_external_page_internal_v1(p_limit, p_offset, 0),
      public.supply_need_external_page_internal_v1(
        p_unverified_limit, p_unverified_offset, 0)
    );
  end if;

  -- **El techo acota el kernel, que es la parte cara.** La resolución de
  -- arriba hay que pagarla igual para saber cuánto fanout hay; lo que este
  -- corte evita es la pasada con funciones de ventana sobre miles de filas.
  if v_candidate_count > p_max_candidates then
    return public.supply_need_external_envelope_internal_v1(
      v_bundle, v_commercial, v_profile, v_profile_source, 'analysis_too_broad',
      v_counts, p_max_candidates, '[]'::jsonb, '[]'::jsonb,
      public.supply_need_external_page_internal_v1(p_limit, p_offset, 0),
      public.supply_need_external_page_internal_v1(
        p_unverified_limit, p_unverified_offset, 0)
    );
  end if;

  -- ── Puntuar el conjunto ENTERO, y recién después reordenar, agrupar y cortar
  with scored as (
    -- **La ÚNICA llamada al kernel**, con el conjunto completo. El puntaje que
    -- devuelve es relativo a ese conjunto, y así se publica en `scoreScope`.
    select kernel.candidate_id, kernel.product_id,
      kernel.rank as base_rank,
      kernel.ranking_score as base_score,
      kernel.item as base_item
    from public.purchase_candidate_scores_internal_v1(
      p_tenant_id, v_candidate_ids, v_profile, v_gama
    ) kernel
  ), meta as (
    select * from jsonb_to_recordset(v_meta) as entry(
      "candidateId" uuid, "productId" uuid, "brandId" uuid, "brandText" text,
      "currencyCode" text, "priceCurrency" text,
      "landedUnitCostNet" numeric, "grossMarginRatio" numeric,
      "freightEvidence" text
    )
  ), states as (
    select * from jsonb_to_recordset(v_states) as entry(
      "productId" uuid, "matchState" text, "matchDetail" jsonb
    )
  ), signalled as (
    select scored.candidate_id, scored.product_id, scored.base_rank,
      scored.base_score, scored.base_item,
      meta."priceCurrency" as price_currency,
      states."matchState" as match_state,
      states."matchDetail" as match_detail,

      -- ── Marca ────────────────────────────────────────────────────────────
      -- Identidad exacta = 1. Un texto legado que normaliza al nombre vigente
      -- es evidencia **débil** = 0.75, y sólo cuando el candidato no tiene
      -- identidad: con `brand_id` presente el texto no agrega nada. Una marca
      -- que difiere es un fallo **conocido** = 0. Y no tener marca es
      -- `unknown`: se excluye del promedio, no vale 0.5 — ese medio punto sería
      -- una afirmación que nadie hizo.
      case
        when v_preferred_brand_id is null then
          jsonb_build_object('status', 'not_requested',
            'reason', 'not_requested', 'score', null)
        when meta."brandId" = v_preferred_brand_id then
          jsonb_build_object('status', 'met',
            'reason', 'brand_identity_match', 'score', 1::numeric)
        when meta."brandId" is not null then
          jsonb_build_object('status', 'missed',
            'reason', 'brand_identity_differs', 'score', 0::numeric)
        when nullif(btrim(coalesce(meta."brandText", '')), '') is null then
          jsonb_build_object('status', 'unknown',
            'reason', 'brand_absent', 'score', null)
        when v_preferred_brand_key is null then
          jsonb_build_object('status', 'unknown',
            'reason', 'preferred_brand_name_unavailable', 'score', null)
        when public.assistant_normalize_query_internal_v1(meta."brandText")
          = v_preferred_brand_key then
          jsonb_build_object('status', 'met_weak',
            'reason', 'brand_legacy_text_match', 'score', 0.75::numeric)
        else
          jsonb_build_object('status', 'missed',
            'reason', 'brand_text_differs', 'score', 0::numeric)
      end as brand_signal,

      -- ── Tope de costo aterrizado ─────────────────────────────────────────
      -- Un monto **denominado**: se compara contra la moneda de la revisión
      -- que fijó el tope. Precedencia fija: moneda, flete, ausencia. Sin FX.
      case
        when v_max_cost is null then
          jsonb_build_object('status', 'not_requested',
            'reason', 'not_requested', 'score', null)
        when meta."currencyCode" is distinct from v_target_currency then
          jsonb_build_object('status', 'unknown',
            'reason', 'currency_mismatch_no_fx', 'score', null)
        when coalesce(meta."freightEvidence", '')
          not in ('complete', 'none') then
          jsonb_build_object('status', 'unknown',
            'reason', 'incomplete_landed_cost', 'score', null)
        when meta."landedUnitCostNet" is null then
          jsonb_build_object('status', 'unknown',
            'reason', 'landed_cost_missing', 'score', null)
        when meta."landedUnitCostNet" <= v_max_cost then
          jsonb_build_object('status', 'met',
            'reason', 'cost_within_ceiling', 'score', 1::numeric)
        else
          jsonb_build_object('status', 'missed',
            'reason', 'cost_above_ceiling', 'score', 0::numeric)
      end as cost_signal,

      -- ── Piso de margen bruto proyectado ──────────────────────────────────
      -- Un **ratio adimensional**: lo que hay que probar no es la moneda del
      -- piso sino que el ratio sea computable, o sea que el costo del
      -- candidato y el precio de catálogo compartan moneda. Por eso compara
      -- contra `price_currency` y no contra la moneda del objetivo ni contra
      -- la del taller.
      case
        when v_min_margin is null then
          jsonb_build_object('status', 'not_requested',
            'reason', 'not_requested', 'score', null)
        when meta."currencyCode" is distinct from meta."priceCurrency" then
          jsonb_build_object('status', 'unknown',
            'reason', 'currency_mismatch_no_fx', 'score', null)
        when coalesce(meta."freightEvidence", '')
          not in ('complete', 'none') then
          jsonb_build_object('status', 'unknown',
            'reason', 'incomplete_landed_cost', 'score', null)
        when meta."grossMarginRatio" is null then
          jsonb_build_object('status', 'unknown',
            'reason', 'margin_missing', 'score', null)
        when meta."grossMarginRatio" >= v_min_margin then
          jsonb_build_object('status', 'met',
            'reason', 'margin_meets_floor', 'score', 1::numeric)
        else
          jsonb_build_object('status', 'missed',
            'reason', 'margin_below_floor', 'score', 0::numeric)
      end as margin_signal,

      -- ── Gama ─────────────────────────────────────────────────────────────
      -- No se cuenta dos veces. Viaja para que su ausencia del promedio sea
      -- una decisión visible y no un olvido.
      case
        when v_gama is null then
          jsonb_build_object('status', 'not_requested',
            'reason', 'not_requested', 'score', null)
        else
          jsonb_build_object('status', 'delegated',
            'reason', 'scored_by_kernel', 'score', null)
      end as gama_signal
    from scored
    join meta on meta."candidateId" = scored.candidate_id
    join states on states."productId" = scored.product_id
  ), aggregated as (
    select signalled.*,
      (
        case when brand_signal ->> 'score' is not null then 1 else 0 end
        + case when cost_signal ->> 'score' is not null then 1 else 0 end
        + case when margin_signal ->> 'score' is not null then 1 else 0 end
      ) as known_count,
      (
        coalesce((brand_signal ->> 'score')::numeric, 0)
        + coalesce((cost_signal ->> 'score')::numeric, 0)
        + coalesce((margin_signal ->> 'score')::numeric, 0)
      ) as known_sum
    from signalled
  ), blended as (
    select aggregated.*,
      -- **Sin señal conocida, el puntaje es el legado, idéntico.** Devolverlo
      -- tal cual —y no `0.75 * legacy + 0.25 * 0`, ni `round(legacy, 6)`— es
      -- lo que hace que la igualdad sea exacta y no aproximada.
      case
        when known_count = 0 then base_score
        else 0.75 * base_score + 0.25 * (known_sum / known_count)
      end as final_score
    from aggregated
  ), ranked as (
    select blended.*,
      case when match_state = 'unverified' then 'unverified' else 'actionable'
      end as grp,
      -- Determinista de punta a punta: puntaje mezclado, luego el legado como
      -- desempate, luego el orden del kernel y por último la identidad. Dos
      -- corridas sobre los mismos datos dan la misma lista.
      row_number() over (
        order by final_score desc, base_score desc, base_rank asc,
          blended.candidate_id
      )::integer as overall_rank
    from blended
  ), grouped as (
    select ranked.*,
      row_number() over (
        partition by grp
        order by final_score desc, base_score desc, base_rank asc,
          ranked.candidate_id
      )::integer as group_rank
    from ranked
  ), projected as (
    select grouped.*,
      base_item || jsonb_build_object(
        -- El puntaje del kernel se conserva con nombre propio: sin él nadie
        -- podría ver cuánto movió el objetivo comercial.
        'baseRank', base_rank,
        'baseRankingScore', base_score,
        'rank', group_rank,
        'overallRank', overall_rank,
        -- El orden usa el valor numeric completo; sólo la salida se redondea.
        'rankingScore', round(final_score, 6),
        'rankingVersion', 'supply-need-external-candidates-v1',
        'group', grp,
        -- La moneda del precio de catálogo, para que el margen sea auditable
        -- en el cliente y no haya que confiar en la palabra del servidor.
        'catalogSalePriceCurrency', price_currency,
        'matchState', match_state,
        'matchDetail', coalesce(match_detail, '[]'::jsonb),
        'requestMatch', jsonb_build_object(
          'state', match_state,
          'group', grp,
          'knownSignalCount', known_count,
          'knownSignalAverage', case
            when known_count = 0 then null
            else round(known_sum / known_count, 6)
          end,
          'blendApplied', known_count > 0,
          'legacyWeight', 0.75::numeric,
          'signalWeight', 0.25::numeric,
          'signals', jsonb_build_object(
            'preferredBrandId', brand_signal,
            'maxLandedUnitCostNet', cost_signal,
            'minGrossMarginRatio', margin_signal,
            'gama', gama_signal
          )
        )
      ) as final_item
    from grouped
  )
  select
    coalesce(jsonb_agg(final_item order by group_rank) filter (
      where grp = 'actionable'
        and group_rank > p_offset and group_rank <= p_offset + p_limit
    ), '[]'::jsonb),
    coalesce(jsonb_agg(final_item order by group_rank) filter (
      where grp = 'unverified'
        and group_rank > p_unverified_offset
        and group_rank <= p_unverified_offset + p_unverified_limit
    ), '[]'::jsonb),
    count(*) filter (where grp = 'actionable')::integer,
    count(*) filter (where grp = 'unverified')::integer,
    count(*) filter (where match_state = 'strong')::integer,
    count(*) filter (where match_state = 'weak')::integer,
    count(*) filter (where match_state = 'no_criteria')::integer
  into v_items, v_unverified_items, v_actionable_total, v_unverified_total,
    v_strong, v_weak, v_no_criteria
  from projected;

  v_counts := v_counts || jsonb_build_object(
    'actionable', v_actionable_total,
    'unverified', v_unverified_total,
    'strong', v_strong,
    'weak', v_weak,
    'noCriteria', v_no_criteria
  );

  return public.supply_need_external_envelope_internal_v1(
    v_bundle, v_commercial, v_profile, v_profile_source, 'success',
    v_counts, p_max_candidates, v_items, v_unverified_items,
    public.supply_need_external_page_internal_v1(
      p_limit, p_offset, v_actionable_total),
    public.supply_need_external_page_internal_v1(
      p_unverified_limit, p_unverified_offset, v_unverified_total)
  );
end;
$$;

revoke all on function public.supply_need_external_candidates_internal_v1(
  uuid, uuid, integer, integer, integer, integer, integer
) from public, anon, authenticated, service_role;

comment on function public.supply_need_external_candidates_internal_v1(
  uuid, uuid, integer, integer, integer, integer, integer
) is
  'External purchase candidates for a supply need. Calls the stock bundle exactly once, raises P0001 stock_first_required before touching the kernel when a covering internal alternative was never explicitly rejected, resolves the whole candidate_id set from the eligible products in its own statement and then scores it with one kernel call. Scores the entire set before rerank, split and pagination; scores stay relative to the eligible set. p_max_candidates exists so a test can exercise analysis_too_broad without seeding hundreds of invoices.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. La RPC pública.
--
-- Sólo resuelve el tenant desde la sesión y fija el techo de fanout. Toda la
-- semántica vive en la internal, para que la prueba del techo no tenga que
-- pasar por un parámetro público que nadie debería poder mover desde el
-- cliente: un techo negociable no es un techo.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.get_supply_need_external_candidates_v1(
  p_need_id uuid,
  p_limit integer default 10,
  p_offset integer default 0,
  p_unverified_limit integer default 5,
  p_unverified_offset integer default 0
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
begin
  if v_tenant_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  return public.supply_need_external_candidates_internal_v1(
    v_tenant_id, p_need_id,
    p_limit, p_offset, p_unverified_limit, p_unverified_offset
  );
end;
$$;

revoke all on function public.get_supply_need_external_candidates_v1(
  uuid, integer, integer, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_external_candidates_v1(
  uuid, integer, integer, integer, integer
) to authenticated;

comment on function public.get_supply_need_external_candidates_v1(
  uuid, integer, integer, integer, integer
) is
  'External purchase candidates for a supply need, ranked by the shared scoring kernel and reranked by the typed commercial target. Stock-first is enforced: a covering internal alternative with no explicit rejection raises P0001 stock_first_required instead of returning an empty list a UI would read as "no suppliers". Actionable and unverified candidates paginate independently; supplierAvailability is historical evidence, never verified availability.';

commit;
