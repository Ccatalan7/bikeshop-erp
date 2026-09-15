-- La respuesta baja un escalón; no se cae de golpe.
--
-- Segunda medición con frases reales del taller. Tres causas distintas para el
-- mismo cero, y ninguna es falta de datos:
--
--   «aros 26»    → el catálogo los llama «Llantas»; la palabra del operador
--                  no está en ningún nombre de producto.
--   «llanta 26»  → la rama SÍ resuelve y el 26 también, pero las llantas no
--                  traen `wheel_size` en su ficha: el predicado deja cero.
--   «platos»     → «plato» devolvía historial y «platos» cero; «bielas»
--                  devolvía historial y «biela» cero. El plural decidía.
--
-- El operador no tiene por qué saber cómo bautizamos las categorías, qué
-- campos poblamos, ni en qué número quedó escrito un producto.
--
-- Se sueltan filtros de a uno, del más frágil al más firme, y cada fila declara
-- lo que se soltó. La RAMA nunca se suelta: es lo que separa «te muestro
-- Ruedas» de «te muestro todo lo que compramos».

begin;

create or replace function public.purchase_supplier_concentration_internal_v1(
  p_tenant_id uuid,
  p_query text default null,
  p_category text default null,
  p_brand text default null,
  p_limit integer default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_query text;
  v_brand text;
  v_category text;
  v_inferred jsonb;
  v_inferred_categories uuid[];
  v_predicates jsonb := '[]'::jsonb;
  v_requested_gamas text[];
  v_items jsonb;
  v_total integer := 0;
  v_dropped_words text;
  v_dropped_filters text;
  v_scope_relaxed boolean := false;
  v_attempt integer;
begin
  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or octet_length(coalesce(p_brand, '')) > 80
     or p_limit not between 1 and 10 then
    raise exception 'Invalid supplier ranking arguments' using errcode = '22023';
  end if;

  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_brand := nullif(public.assistant_normalize_query_internal_v1(p_brand), '');
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );

  -- Sin nada que acotar, la respuesta sería «a quién le compramos todo», que
  -- no es una pregunta del taller y devolvería el ranking de proveedores
  -- completo disfrazado de análisis.
  if v_query is null and v_category is null and v_brand is null then
    raise exception 'Invalid supplier ranking arguments' using errcode = '22023';
  end if;

  if v_category is not null and not exists (
    select 1
    from public.product_categories category
    where category.tenant_id = p_tenant_id
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path)
           = v_category
      )
  ) then
    raise exception 'Category not found' using errcode = 'P0002';
  end if;

  -- La frase se traduce igual que en `search_inventory`: la rama nombrada
  -- vuelve como filtro de categoría y las medidas como predicados de ficha.
  -- El residuo es lo único que sigue buscándose como texto libre.
  if v_query is not null then
    v_inferred := public.assistant_infer_technical_predicates_internal_v1(
      p_tenant_id, p_query
    );
    v_predicates := coalesce(v_inferred -> 'predicates', '[]'::jsonb);
    select array_agg((category.value #>> '{}')::uuid)
    into v_inferred_categories
    from jsonb_array_elements(
      coalesce(v_inferred -> 'categories', '[]'::jsonb)
    ) category(value);
    if jsonb_array_length(v_predicates) > 0
       or v_inferred_categories is not null then
      v_query := nullif(
        public.assistant_normalize_query_internal_v1(
          v_inferred ->> 'residual'
        ), ''
      );
    end if;
  end if;

  -- La gama se dice con palabras, y esas palabras no están en el nombre de
  -- ningún producto. Dejarlas en el texto libre mataba la consulta entera:
  -- «neumáticos 29 de gama media y alta» devolvía CERO proveedores teniendo
  -- seis, porque el filtro exigía «media» y «alta» dentro del nombre. Se
  -- consumen como señal de banda —que informa y ordena— y salen del texto.
  if v_query is not null then
    select array_agg(distinct banda order by banda)
    into v_requested_gamas
    from regexp_split_to_table(v_query, ' +') token
    cross join lateral (
      select case
        when token in ('alta', 'altas', 'premium', 'tope') then 'alta'
        when token in ('media', 'medias', 'intermedia') then 'media'
        when token in ('economica', 'economicas', 'baja', 'bajas',
          'basica', 'basicas', 'barata', 'baratas', 'entrada') then 'economica'
      end banda
    ) mapped
    where banda is not null;

    if v_requested_gamas is not null then
      select nullif(btrim(string_agg(token, ' ')), '')
      into v_query
      from regexp_split_to_table(v_query, ' +') token
      where token not in ('alta', 'altas', 'premium', 'tope', 'media',
        'medias', 'intermedia', 'economica', 'economicas', 'baja', 'bajas',
        'basica', 'basicas', 'barata', 'baratas', 'entrada', 'gama', 'gamas');
    end if;
  end if;

  -- **La respuesta baja un escalón; no se cae de golpe.**
  --
  -- Medido con frases reales del taller, sobre datos de producción:
  --
  --   «aros 26»          → 0    «platos y bielas» → 0    «llanta 26» → 0
  --   «rayos 27.5»       → 4 proveedores ✓
  --
  -- Tres causas distintas, un mismo síntoma. El filtro de texto exige que CADA
  -- palabra esté en el nombre del producto, así que «aros» —que en el catálogo
  -- se llama «Llantas»— mataba la consulta. Y una medida sin cobertura en esa
  -- rama la mataba igual: «llanta 26» resuelve la rama Y el 26, pero las
  -- llantas no traen `wheel_size` en su ficha, así que el predicado dejaba
  -- cero.
  --
  -- El operador no tiene por qué saber cómo bautizamos las categorías ni qué
  -- campos poblamos. Así que se sueltan filtros de a uno, del más frágil al más
  -- firme, y cada fila declara lo que se soltó:
  --
  --   1. todo tal cual
  --   2. sin el texto libre que no calzó   (`droppedWords`)
  --   3. sin la medida técnica sin cobertura (`droppedFilters`)
  --
  -- La rama NUNCA se suelta: es lo que separa «te muestro Ruedas» de «te
  -- muestro todo lo que compramos». Y ningún escalón corre si nada se resolvió.
  for v_attempt in 1..3 loop
    if v_attempt > 1 and v_total > 0 then
      exit;
    end if;

    if v_attempt = 2 then
      -- Sin residuo, o sin nada más que sostenga la pregunta, este escalón no
      -- aplica: se pasa al siguiente en vez de abandonar la escalera.
      continue when v_query is null
        or (v_inferred_categories is null
            and jsonb_array_length(v_predicates) = 0
            and v_category is null);
      v_dropped_words := v_query;
      v_query := null;
      v_scope_relaxed := true;
    elsif v_attempt = 3 then
      continue when jsonb_array_length(v_predicates) = 0
        or (v_inferred_categories is null and v_category is null);
      v_dropped_filters := 'la medida técnica';
      v_predicates := '[]'::jsonb;
      v_scope_relaxed := true;
    end if;

    with recursive category_scope as (
      select category.id
      from public.product_categories category
      where category.tenant_id = p_tenant_id
        and v_category is not null
        and (
          public.assistant_normalize_query_internal_v1(category.name) = v_category
          or public.assistant_normalize_query_internal_v1(category.full_path)
             = v_category
        )
      union all
      select child.id
      from public.product_categories child
      join category_scope parent on child.parent_id = parent.id
      where child.tenant_id = p_tenant_id and child.is_active is true
    ), requested_predicates as (
      select predicate.value ->> 'field' as field_key,
        predicate.value ->> 'operator' as operator,
        coalesce(predicate.value -> 'values', '[]'::jsonb) as values
      from jsonb_array_elements(v_predicates) predicate(value)
    ), purchased as materialized (
      -- El universo son los productos que ALGUNA vez se compraron: ~267, no el
      -- catálogo entero. Evaluar la ficha ahí adentro es barato.
      select distinct observation.product_id,
        product.category_id,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )) identity_surface,
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category))) identity_raw,
        public.assistant_normalize_query_internal_v1(product.brand) brand_key
      from public.purchase_line_landed_cost_observations_v1 observation
      join public.products product
        on product.id = observation.product_id
       and product.tenant_id = observation.tenant_id
      where observation.tenant_id = p_tenant_id
        and observation.product_id is not null
        and observation.document_status in ('received', 'paid')
    ), matching as materialized (
      select purchased.product_id
      from purchased
      cross join lateral (
        select coalesce(bool_and(source.value in (
            'product_spec', 'identity_fallback'
          )), true) predicates_match
        from requested_predicates predicate
        cross join lateral (
          select public.assistant_inventory_technical_predicate_source_internal_v1(
            p_tenant_id, purchased.product_id, predicate.field_key,
            predicate.operator, predicate.values, purchased.identity_surface,
            purchased.identity_raw
          ) value
        ) source
      ) predicate_state
      where predicate_state.predicates_match
        and (
          v_inferred_categories is null
          or purchased.category_id = any(v_inferred_categories)
        )
        and (
          v_category is null
          or purchased.category_id in (select id from category_scope)
        )
        and (
          v_brand is null
          or position(v_brand in coalesce(purchased.brand_key, '')) > 0
        )
        and (
          v_query is null
          or not exists (
            -- **El plural no puede decidir si encontramos algo.** Medido:
            -- «plato» devolvía historial y «platos» cero; «bielas» devolvía
            -- historial y «biela» cero. Depende de cómo quedó escrito ese
            -- producto en particular, que es exactamente lo que el operador no
            -- puede saber. Se prueba la palabra y su raíz.
            select 1 from regexp_split_to_table(v_query, ' +') token
            where position(token in purchased.identity_surface) = 0
              and position(
                case
                  when length(token) > 4 and token like '%es'
                    then left(token, length(token) - 2)
                  when length(token) > 3 and token like '%s'
                    then left(token, length(token) - 1)
                  else token
                end in purchased.identity_surface
              ) = 0
          )
        )
    ), lines as (
      select observation.supplier_id,
        observation.supplier_name,
        observation.product_id,
        observation.purchase_invoice_id,
        observation.brand,
        observation.economic_date,
        greatest(coalesce(observation.quantity, 0), 0) units,
        greatest(coalesce(observation.quantity, 0), 0)
          * greatest(coalesce(observation.landed_unit_cost_net, 0), 0) spend,
        band.band gama_band
      from public.purchase_line_landed_cost_observations_v1 observation
      join matching on matching.product_id = observation.product_id
      left join public.product_gama_v1 band
        on band.tenant_id = observation.tenant_id
       and band.category_id = observation.category_id
       and lower(btrim(band.brand)) = lower(btrim(observation.brand))
      where observation.tenant_id = p_tenant_id
        and observation.supplier_id is not null
        and observation.document_status in ('received', 'paid')
    ), totals as (
      select nullif(sum(spend), 0) total_spend,
        nullif(sum(units), 0) total_units,
        count(*)::integer total_lines,
        count(distinct product_id)::integer total_products,
        min(economic_date) first_at,
        max(economic_date) last_at
      from lines
    ), by_supplier as (
      select supplier_id,
        max(supplier_name) supplier_name,
        count(*)::integer purchase_lines,
        count(distinct product_id)::integer distinct_products,
        count(distinct purchase_invoice_id)::integer purchase_invoices,
        sum(units) units,
        sum(spend) spend,
        min(economic_date) first_at,
        max(economic_date) last_at,
        count(*) filter (where gama_band = 'alta')::integer gama_alta,
        count(*) filter (where gama_band = 'media')::integer gama_media,
        count(*) filter (where gama_band = 'economica')::integer gama_economica,
        count(*) filter (where gama_band is null)::integer gama_desconocida,
        count(*) filter (
          where v_requested_gamas is not null and gama_band = any(v_requested_gamas)
        )::integer requested_gama_lines
      from lines
      group by supplier_id
    ), brands_by_supplier as (
      select supplier_id,
        nullif(string_agg(brand, ', ' order by brand_spend desc, brand), '')
          brands
      from (
        select supplier_id, brand, sum(spend) brand_spend,
          row_number() over (
            partition by supplier_id order by sum(spend) desc, brand
          ) position
        from lines
        where brand is not null and btrim(brand) <> ''
        group by supplier_id, brand
      ) ranked
      where position <= 5
      group by supplier_id
    ), scored as (
      select by_supplier.*,
        supplier.website supplier_website,
        supplier.city supplier_city,
        supplier.sales_rep_name,
        supplier.sales_rep_phone,
        supplier.sales_rep_email,
        supplier.phone supplier_phone,
        supplier.email supplier_email,
        nullif(btrim(coalesce(supplier.portal_username, '')), '') is not null
          has_portal_account,
        brands_by_supplier.brands,
        totals.total_spend, totals.total_units, totals.total_lines,
        totals.total_products, totals.first_at global_first, totals.last_at
          global_last,
        (extract(epoch from (statement_timestamp() - by_supplier.last_at))
          / 86400)::integer days_since,
        max(by_supplier.distinct_products) over () max_products
      from by_supplier
      cross join totals
      left join public.suppliers supplier
        on supplier.id = by_supplier.supplier_id
       and supplier.tenant_id = p_tenant_id
      left join brands_by_supplier
        on brands_by_supplier.supplier_id = by_supplier.supplier_id
    ), ranked as (
      select scored.*,
        coalesce(spend / nullif(total_spend, 0), 0) spend_share,
        coalesce(units / nullif(total_units, 0), 0) units_share,
        exp(-greatest(days_since, 0)::numeric / 180) recency_score,
        coalesce(
          distinct_products::numeric / nullif(max_products, 0), 0
        ) breadth_score
      from scored
    ), final as (
      select ranked.*,
        (0.55 * spend_share + 0.20 * units_share
          + 0.15 * recency_score + 0.10 * breadth_score)::numeric
          concentration_score,
        row_number() over (
          order by (0.55 * spend_share + 0.20 * units_share
            + 0.15 * recency_score + 0.10 * breadth_score) desc,
            spend desc, last_at desc, supplier_id
        )::integer rank,
        count(*) over ()::integer matched_suppliers
      from ranked
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'entityId', supplier_id,
        'rank', rank,
        'supplierName', supplier_name,
        'spendSharePercent', round(100 * spend_share, 1),
        'landedSpendNet', round(spend, 2),
        'purchaseLines', purchase_lines,
        'purchaseInvoices', purchase_invoices,
        'distinctProducts', distinct_products,
        'purchasedUnits', round(units, 2),
        'averageLandedUnitCostNet', case
          when units > 0 then round(spend / units, 2) else null end,
        'lastPurchaseAt', last_at,
        'daysSinceLastPurchase', days_since,
        'brands', brands,
        -- La mezcla viaja como frase legible: el modelo la repite, no la
        -- calcula, y un objeto anidado el validador de resultados lo rechaza.
        -- «sin banda 7» no le dice nada a nadie: es la ausencia del dato, no un
        -- hallazgo. Si NINGUNA línea tiene banda derivada, la mezcla se calla.
        'gamaMix', case
          when gama_alta + gama_media + gama_economica = 0 then null
          else nullif(concat_ws(' · ',
            nullif('alta ' || nullif(gama_alta, 0)::text, 'alta '),
            nullif('media ' || nullif(gama_media, 0)::text, 'media '),
            nullif('económica ' || nullif(gama_economica, 0)::text, 'económica '),
            nullif('sin banda ' || nullif(gama_desconocida, 0)::text, 'sin banda ')
          ), '')
        end,
        'requestedGamaLines', requested_gama_lines,
        'supplierWebsite', supplier_website,
        'hasPortalAccount', has_portal_account,
        'supplierCity', supplier_city,
        'salesRepName', sales_rep_name,
        'salesRepPhone', coalesce(sales_rep_phone, supplier_phone),
        'salesRepEmail', coalesce(sales_rep_email, supplier_email),
        -- La evidencia viaja en cada fila porque el sobre sólo admite sus
        -- claves base. Sin ella el modelo presenta «56%» de tres líneas con la
        -- misma seguridad que un 56% de trescientas.
        -- Cuando el texto se soltó, la respuesta ya no es de lo que el
        -- operador escribió literalmente: es de su rama. Se dice.
        'scopeRelaxed', v_scope_relaxed,
        'droppedWords', v_dropped_words,
        'droppedFilters', v_dropped_filters,
        'evidencePurchaseLines', total_lines,
        'evidenceSuppliers', matched_suppliers,
        'evidenceProductsMatched', total_products,
        'concentrationScore', round(concentration_score, 6),
        'supplierAvailability', 'unverified'
      ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
      coalesce(max(matched_suppliers), 0)
    into v_items, v_total
    from final;
  end loop;



  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$$;



commit;
