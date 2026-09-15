-- El costo unitario se puede mirar con flete o sin flete.
--
-- Hasta acá todo se publicaba **con flete prorrateado** y no había forma de ver
-- lo otro. Pero lo que se negocia con el proveedor es la mercadería: el flete
-- es un costo nuestro, y meterlo en el precio que se compara —y en el que se le
-- propone en un pedido— infla la cifra con algo que él no cobra.
--
-- Entonces se publican los dos y la pantalla elige. **Por defecto, sin flete**,
-- que es el que se cotiza. El de flete prorrateado sigue disponible con un
-- toque, porque para decidir a quién comprarle el costo real puesto en bodega
-- sí es el que manda.
--
-- Este archivo agrega `averageBaseUnitCostNet` al motor de concentración
-- —conservando el cuerpo vivo tal cual, con los tres puntos justos tocados— y
-- `baseUnitCostNet` a la evidencia y a la ficha del proveedor.

begin;

create or replace function public.purchase_supplier_concentration_internal_v1(
  -- **Los defaults se conservan exactamente como están vivos.** Cambiarlos en
  -- un `create or replace` no reemplaza: Postgres se niega («cannot remove
  -- parameter defaults from existing function») y obligaría a un `drop` que
  -- rompería a todo el que la llama.
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
set statement_timeout = '9000ms'
as $function$
declare
  v_brand text;
  v_items jsonb;
  v_total integer := 0;
begin
  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or octet_length(coalesce(p_brand, '')) > 80
     or p_limit not between 1 and 10 then
    raise exception 'Invalid supplier ranking arguments' using errcode = '22023';
  end if;

  v_brand := nullif(public.assistant_normalize_query_internal_v1(p_brand), '');

  if p_query is null and p_category is null and v_brand is null then
    raise exception 'Invalid supplier ranking arguments' using errcode = '22023';
  end if;

  with resolved as materialized (
    select * from public.purchase_query_products_internal_v1(
      p_tenant_id, coalesce(p_query, p_category), true
    )
  ), scope as (
    select max(dropped_words) dropped_words,
      max(dropped_filters) dropped_filters,
      (array_agg(requested_gamas) filter (where requested_gamas is not null))[1]
        requested_gamas
    from resolved
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
      -- Sólo la mercadería, sin flete. Es lo que se negocia con el proveedor:
      -- el flete es un costo nuestro y no una parte de su precio.
      greatest(coalesce(observation.quantity, 0), 0)
        * greatest(coalesce(observation.base_unit_cost_net, 0), 0) base_spend,
      band.band gama_band
    from public.purchase_line_landed_cost_observations_v1 observation
    join resolved on resolved.product_id = observation.product_id
    left join public.product_gama_v1 band
      on band.tenant_id = observation.tenant_id
     and band.category_id = observation.category_id
     and lower(btrim(band.brand)) = lower(btrim(observation.brand))
    where observation.tenant_id = p_tenant_id
      and observation.supplier_id is not null
      and observation.document_status in ('received', 'paid')
      -- La marca acota cuando el operador la nombró aparte de la frase.
      and (
        v_brand is null
        or position(
          v_brand in coalesce(
            public.assistant_normalize_query_internal_v1(observation.brand), ''
          )
        ) > 0
      )
  ), totals as (
    select nullif(sum(spend), 0) total_spend,
      nullif(sum(units), 0) total_units,
      count(*)::integer total_lines,
      count(distinct product_id)::integer total_products
    from lines
  ), by_supplier as (
    select supplier_id,
      max(supplier_name) supplier_name,
      count(*)::integer purchase_lines,
      count(distinct product_id)::integer distinct_products,
      count(distinct purchase_invoice_id)::integer purchase_invoices,
      sum(units) units,
      sum(spend) spend,
      sum(base_spend) base_spend,
      max(economic_date) last_at,
      count(*) filter (where gama_band = 'alta')::integer gama_alta,
      count(*) filter (where gama_band = 'media')::integer gama_media,
      count(*) filter (where gama_band = 'economica')::integer gama_economica,
      count(*) filter (where gama_band is null)::integer gama_desconocida,
      count(*) filter (
        where (select requested_gamas from scope) is not null
          and gama_band = any((select requested_gamas from scope))
      )::integer requested_gama_lines
    from lines
    group by supplier_id
  ), brands_by_supplier as (
    select supplier_id,
      nullif(string_agg(brand, ', ' order by brand_spend desc, brand), '') brands
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
      totals.total_products,
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
      -- El mismo promedio sin el flete prorrateado. La pantalla elige cuál
      -- muestra; por defecto el de mercadería, que es el que se cotiza.
      'averageBaseUnitCostNet', case
        when units > 0 then round(base_spend / units, 2) else null end,
      'lastPurchaseAt', last_at,
      'daysSinceLastPurchase', days_since,
      'brands', brands,
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
      'scopeRelaxed', (select dropped_words is not null or dropped_filters is not null from scope),
      'droppedWords', (select dropped_words from scope),
      'droppedFilters', (select dropped_filters from scope),
      'evidencePurchaseLines', total_lines,
      'evidenceSuppliers', matched_suppliers,
      'evidenceProductsMatched', total_products,
      'concentrationScore', round(concentration_score, 6),
      'supplierAvailability', 'unverified'
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched_suppliers), 0)
  into v_items, v_total
  from final;

  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$function$;

commit;
