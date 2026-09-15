-- Una lista es una llamada, no una por línea.
--
-- Medido en producción con «necesito rayos 27.5, cámaras 29 y cadenas de 11
-- velocidades. ¿a quién le pido todo eso?»: el modelo llamó
-- `rank_purchase_suppliers` TRES veces —una por línea, y las tres
-- respondieron—, y aun así la corrida murió con `agent_budget_exhausted` a los
-- 38,7 s sin llegar a redactar la respuesta. Tres corridas seguidas igual.
--
-- El defecto no es del modelo: encadenar N llamadas para una pregunta que es
-- UNA gasta presupuesto de turno, presupuesto de herramientas y latencia, y la
-- decisión que el operador espera —«¿a uno solo, o lo reparto en dos?»— no la
-- puede tomar ninguna de las tres llamadas por separado.
--
-- Esta función resuelve la canasta entera de una vez y contesta la pregunta
-- real del taller: quién cubre más líneas, qué le falta, y quién completa lo
-- que falta. La decisión de repartir se calcula acá, con los datos a la vista,
-- no se le delega al modelo.

begin;

create or replace function public.purchase_basket_supplier_coverage_internal_v1(
  p_tenant_id uuid,
  p_queries jsonb,
  p_limit integer default 4
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '12000ms'
as $$
declare
  v_need text;
  v_analysis jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_need_count integer := 0;
  v_items jsonb;
  v_total integer := 0;
  v_leader_id text;
  v_missing text;
  v_complement_name text;
  v_complement_covers text;
begin
  if jsonb_typeof(p_queries) <> 'array'
     or jsonb_array_length(p_queries) < 2
     or jsonb_array_length(p_queries) > 6
     or p_limit not between 1 and 5 then
    raise exception 'Invalid basket arguments' using errcode = '22023';
  end if;

  for v_need in
    select btrim(value #>> '{}')
    from jsonb_array_elements(p_queries) item(value)
    where btrim(coalesce(value #>> '{}', '')) <> ''
  loop
    v_need_count := v_need_count + 1;
    v_analysis := public.purchase_supplier_concentration_internal_v1(
      p_tenant_id, v_need, null, null, 5
    );
    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'need', v_need,
      'items', coalesce(v_analysis -> 'items', '[]'::jsonb)
    ));
  end loop;

  if v_need_count < 2 then
    raise exception 'Invalid basket arguments' using errcode = '22023';
  end if;

  -- Quién cubre qué. Una línea «cubierta» significa que ese proveedor aparece
  -- en su historial de compras, nunca que tenga stock hoy.
  with per_need as (
    select row.value ->> 'need' as need, supplier.value as supplier
    from jsonb_array_elements(v_rows) row
    cross join lateral jsonb_array_elements(row.value -> 'items') supplier
  ), by_supplier as (
    select supplier ->> 'entityId' as supplier_id,
      max(supplier ->> 'supplierName') as supplier_name,
      count(distinct need)::integer as covered,
      string_agg(distinct need, ', ' order by need) as covered_list,
      sum((supplier ->> 'landedSpendNet')::numeric) as spend,
      round(avg((supplier ->> 'spendSharePercent')::numeric), 1) as avg_share,
      max((supplier ->> 'lastPurchaseAt')::timestamptz) as last_at,
      min((supplier ->> 'daysSinceLastPurchase')::integer) as days_since,
      max(supplier ->> 'supplierWebsite') as website,
      bool_or((supplier ->> 'hasPortalAccount')::boolean) as portal,
      max(supplier ->> 'supplierCity') as city,
      max(supplier ->> 'salesRepPhone') as rep_phone,
      max(supplier ->> 'salesRepEmail') as rep_email,
      string_agg(distinct nullif(supplier ->> 'brands', ''), ', '
        order by nullif(supplier ->> 'brands', '')) as brands
    from per_need
    where supplier ->> 'entityId' is not null
    group by 1
  ), ranked as (
    select by_supplier.*,
      row_number() over (
        order by covered desc, spend desc, last_at desc nulls last, supplier_id
      )::integer as rank,
      count(*) over ()::integer as supplier_count
    from by_supplier
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank,
      'entityId', supplier_id,
      'supplierName', supplier_name,
      'coveredNeeds', covered,
      'totalNeeds', v_need_count,
      'coveredList', covered_list,
      'averageSharePercent', avg_share,
      'landedSpendNet', round(spend, 2),
      'lastPurchaseAt', last_at,
      'daysSinceLastPurchase', days_since,
      'brands', brands,
      'supplierWebsite', website,
      'hasPortalAccount', portal,
      'supplierCity', city,
      'salesRepPhone', rep_phone,
      'salesRepEmail', rep_email,
      'supplierAvailability', 'unverified'
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(supplier_count), 0),
    (array_agg(supplier_id order by rank))[1]
  into v_items, v_total, v_leader_id
  from ranked;

  -- **La decisión de repartir se calcula acá.** Lo que el líder no cubre, y
  -- quién lo cubre mejor: eso es «uno solo o en dos», y es la pregunta que el
  -- operador hace de verdad.
  if v_leader_id is not null then
    with per_need as (
      select row.value ->> 'need' as need, supplier.value as supplier
      from jsonb_array_elements(v_rows) row
      cross join lateral jsonb_array_elements(row.value -> 'items') supplier
    ), leader_needs as (
      select distinct need from per_need
      where supplier ->> 'entityId' = v_leader_id
    ), uncovered as (
      select btrim(item.value #>> '{}') as need
      from jsonb_array_elements(p_queries) item(value)
      where btrim(coalesce(item.value #>> '{}', '')) <> ''
        and btrim(item.value #>> '{}') not in (select need from leader_needs)
    ), helpers as (
      select supplier ->> 'entityId' as supplier_id,
        max(supplier ->> 'supplierName') as supplier_name,
        count(distinct per_need.need)::integer as covered,
        string_agg(distinct per_need.need, ', ' order by per_need.need) as list,
        sum((supplier ->> 'landedSpendNet')::numeric) as spend
      from per_need
      join uncovered on uncovered.need = per_need.need
      where supplier ->> 'entityId' <> v_leader_id
      group by 1
    )
    select
      (select string_agg(need, ', ' order by need) from uncovered),
      (select supplier_name from helpers order by covered desc, spend desc limit 1),
      (select list from helpers order by covered desc, spend desc limit 1)
    into v_missing, v_complement_name, v_complement_covers;

    -- El complemento viaja en la fila del líder: es SU decisión de reparto, no
    -- un dato del proveedor complementario.
    if v_missing is not null and jsonb_array_length(v_items) > 0 then
      v_items := jsonb_set(v_items, '{0}',
        (v_items -> 0) || jsonb_build_object(
          'missingList', v_missing,
          'complementSupplierName', v_complement_name,
          'complementCoversList', v_complement_covers
        )
      );
    end if;
  end if;

  -- Todas las filas declaran las mismas claves: el validador del gateway exige
  -- claves EXACTAS por fila, así que las del líder no pueden ser distintas.
  select coalesce(jsonb_agg(
      jsonb_build_object(
        'missingList', null,
        'complementSupplierName', null,
        'complementCoversList', null
      ) || item.value
      order by (item.value ->> 'rank')::integer
    ), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_items) item(value);

  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$$;

revoke all on function public.purchase_basket_supplier_coverage_internal_v1(
  uuid, jsonb, integer
) from public, anon, authenticated, service_role;

-- La puerta del asistente.
create or replace function public.assistant_rank_basket_suppliers_v1(
  p_queries jsonb,
  p_limit integer default 4
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '12000ms'
as $$
declare
  v_authority record;
  v_analysis jsonb;
begin
  select authority.tenant_id, authority.actor_user_id
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  v_analysis := public.purchase_basket_supplier_coverage_internal_v1(
    v_authority.tenant_id, p_queries, p_limit
  );

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_analysis -> 'items',
    (v_analysis ->> 'total')::integer > p_limit,
    (v_analysis ->> 'total')::integer
  );
end;
$$;

revoke all on function public.assistant_rank_basket_suppliers_v1(jsonb, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.assistant_rank_basket_suppliers_v1(jsonb, integer)
  to authenticated;

-- La puerta del módulo, sin la capacidad de IA.
create or replace function public.rank_basket_suppliers_v1(
  p_queries jsonb,
  p_limit integer default 4
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '12000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_analysis jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;

  v_analysis := public.purchase_basket_supplier_coverage_internal_v1(
    v_tenant_id, p_queries, p_limit
  );

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'items', v_analysis -> 'items',
    'resultCount', jsonb_array_length(coalesce(v_analysis -> 'items', '[]'::jsonb)),
    'totalMatches', (v_analysis ->> 'total')::integer,
    'hasMore', (v_analysis ->> 'total')::integer > p_limit,
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  );
end;
$$;

revoke all on function public.rank_basket_suppliers_v1(jsonb, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.rank_basket_suppliers_v1(jsonb, integer)
  to authenticated;

commit;
