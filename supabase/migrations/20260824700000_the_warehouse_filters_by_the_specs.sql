-- La bodega busca por las características, no por la frase.
--
-- El asistente traduce «camaras 27.5 con válvula de auto» a predicados tipados y
-- los guarda en `supply_need_interpretation_revisions.constraints`. Este paso los
-- ignoraba: volvía a resolver `original_description` como texto, y el texto no
-- sabe de válvulas. Resultado medido: **33 alternativas donde la ficha dice 12**.
--
-- Con esto, dar dos características basta para ver exactamente lo que las
-- cumple. Y sigue sin ser obligatorio: una necesidad sin predicados —o escrita
-- antes de que existieran— cae al resolvedor de frase como siempre.

begin;

create or replace function public.supply_need_stock_candidates_v1(
  p_need_id uuid,
  p_limit integer default 8
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_need record;
  v_items jsonb;
  v_total integer := 0;
  v_dropped_words text;
  v_dropped_filters text;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 20 then
    raise exception 'Invalid stock candidate arguments' using errcode = '22023';
  end if;

  select need.id, need.original_description, need.product_id
  into v_need
  from public.supply_needs need
  where need.id = p_need_id and need.tenant_id = v_tenant_id;

  if v_need.id is null then
    raise exception 'Supply need not found' using errcode = 'P0002';
  end if;

  -- Con producto confirmado esta lectura no aplica: la bodega exacta ya la
  -- publica `get_supply_need_inventory_snapshot_v1`, que es su dueña. Dos
  -- verdades sobre el mismo stock es peor que una sola incompleta.
  if v_need.product_id is not null then
    return jsonb_build_object(
      'asOf', clock_timestamp(),
      'items', '[]'::jsonb,
      'resultCount', 0,
      'totalMatches', 0,
      'reason', 'identity_confirmed'
    );
  end if;

  -- **Las características que el asistente ya tradujo mandan sobre la frase.**
  --
  -- La interpretación guarda predicados tipados —`wheel_size = 27.5"`,
  -- `valve_type = Schrader (americana / auto)`— y este paso los ignoraba: volvía
  -- a resolver `original_description` como texto. Con «camaras 27.5 con válvula
  -- de auto» eso devolvía 33 alternativas donde la ficha dice 12, porque el
  -- texto no sabe de válvulas.
  --
  -- Se leen los del revision más reciente. Si no hay ninguno —una necesidad sin
  -- características, o escrita antes de que existieran— el camino sigue siendo
  -- la frase, que es lo que hace que esto no sea obligatorio: se avanza igual.
  with criterios as (
    select predicado.value ->> 'field' campo,
      predicado.value -> 'values' valores
    from public.supply_need_interpretation_revisions revision
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(revision.constraints) = 'array'
      then revision.constraints else '[]'::jsonb end
    ) predicado(value)
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = v_need.id
      and revision.revision_no = (
        select max(newest.revision_no)
        from public.supply_need_interpretation_revisions newest
        where newest.tenant_id = v_tenant_id
          and newest.supply_need_id = v_need.id
      )
      and predicado.value ? 'field'
      and jsonb_typeof(predicado.value -> 'values') = 'array'
  ), por_ficha as (
    -- Un producto entra si cumple TODAS las características pedidas. El valor
    -- viaja como etiqueta —así lo guarda el asistente— y por eso se compara
    -- contra `spec_definition_values.label`.
    select fact.subject_id product_id
    from public.spec_facts fact
    join public.spec_definitions definition
      on definition.id = fact.spec_definition_id
    join public.spec_fact_values fact_value on fact_value.fact_id = fact.id
    join public.spec_definition_values value_row
      on value_row.id = fact_value.value_id
    join criterios on criterios.campo = definition.key
     and value_row.label in (
       select valor #>> '{}' from jsonb_array_elements(criterios.valores) valor
     )
    where fact.tenant_id = v_tenant_id
      and fact.subject_type = 'product'
    group by fact.subject_id
    having count(distinct definition.key) = (select count(*) from criterios)
  ), resolved as materialized (
    select * from public.purchase_query_products_internal_v1(
      v_tenant_id, v_need.original_description, false
    )
    where not exists (select 1 from criterios)
    union all
    select por_ficha.product_id, null::text, null::text, null::text[]
    from por_ficha
  ), stock as (
    select product.id,
      product.name,
      product.sku,
      product.brand,
      product.category_name,
      product.price,
      product.cost,
      coalesce(product.track_stock, false) tracks_inventory,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      max(resolved.dropped_words) over () dropped_words,
      max(resolved.dropped_filters) over () dropped_filters,
      count(*) over ()::integer matched
    from public.products product
    join resolved on resolved.product_id = product.id
    where product.tenant_id = v_tenant_id
      and product.is_active is true
  ), ranked as (
    select stock.*,
      row_number() over (
        -- Lo que hay primero: un producto que calza y está en cero no le
        -- resuelve el día a nadie, pero saber que existe sí evita crearlo
        -- de nuevo.
        order by (case when available > 0 then 0 else 1 end), available desc,
          name
      )::integer rank
    from stock
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', id,
      'name', name,
      'sku', sku,
      'brand', brand,
      'category', category_name,
      'available', available,
      'tracksInventory', tracks_inventory,
      'priceGross', price,
      'costNet', cost
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched), 0),
    max(dropped_words),
    max(dropped_filters)
  into v_items, v_total, v_dropped_words, v_dropped_filters
  from ranked;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'items', v_items,
    'resultCount', jsonb_array_length(v_items),
    'totalMatches', v_total,
    'hasMore', v_total > p_limit,
    'droppedWords', v_dropped_words,
    'droppedFilters', v_dropped_filters,
    'reason', case when v_total = 0 then 'no_match' else 'candidates' end
  );
end;
$function$;

commit;
