-- Fase 8, tercer lector: el que decide qué productos salen.
--
-- `assistant_inventory_technical_predicate_source_internal_v1` es el que
-- compara lo que pidió el operador contra la ficha de cada producto. Leía
-- `product_spec_values`, donde el valor de una lista es la etiqueta congelada
-- en la fila.
--
-- Ahora lee `spec_facts` y arma la etiqueta desde `spec_definition_values`. La
-- consecuencia práctica: renombrar un valor no rompe un filtro que ya
-- funcionaba, porque la comparación usa la etiqueta vigente y no la que estaba
-- guardada cuando se llenó la ficha.
--
-- Con esto los tres lectores de sólo lectura quedan movidos: tienda, inspector
-- y matcher. Lo que sigue escribe, y va aparte.

begin;

CREATE OR REPLACE FUNCTION public.assistant_inventory_technical_predicate_source_internal_v1(p_tenant_id uuid, p_product_id uuid, p_field_key text, p_operator text, p_values jsonb, p_identity_surface text, p_identity_raw text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_definition record;
  v_value record;
  v_match boolean := false;
  v_candidate text;
  v_candidate_normalized text;
  v_number numeric;
  v_first numeric;
  v_second numeric;
  v_boolean boolean;
begin
  select definition.data_type, definition.allowed_values
  into v_definition
  from public.spec_definitions definition
  where definition.key = p_field_key
    and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    and definition.is_filterable is true
  order by (definition.tenant_id is not null) desc
  limit 1;
  if not found then return 'unresolved'; end if;

  -- El hecho sale del registro unificado. Los valores de lista se arman desde
  -- `spec_fact_values`, así que la ETIQUETA con la que se compara es la actual
  -- del vocabulario y no una copia congelada: renombrar un valor no rompe un
  -- filtro que ya funcionaba.
  select f.value_text, f.value_number, f.value_boolean,
    (
      select string_agg(sv.label, ', ' order by fv.position)
      from public.spec_fact_values fv
      join public.spec_definition_values sv on sv.id = fv.value_id
      where fv.fact_id = f.id
    ) as value_option,
    (
      select jsonb_agg(sv.label order by fv.position)
      from public.spec_fact_values fv
      join public.spec_definition_values sv on sv.id = fv.value_id
      where fv.fact_id = f.id
    ) as value_json,
    null::text as display_value
  into v_value
  from public.spec_facts f
  join public.spec_definitions definition
    on definition.id = f.spec_definition_id
   and definition.key = p_field_key
   and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
  where f.tenant_id = p_tenant_id
    and f.subject_type = 'product'
    and f.subject_id = p_product_id
    and f.subject_scope is null
  order by (definition.tenant_id is not null) desc
  limit 1;

  if found then
    if v_definition.data_type = 'number' then
      if v_value.value_number is null then return 'conflict'; end if;
      v_number := v_value.value_number;
      v_first := (p_values ->> 0)::numeric;
      if p_operator = 'eq' then v_match := v_number = v_first;
      elsif p_operator = 'neq' then v_match := v_number <> v_first;
      elsif p_operator = 'lt' then v_match := v_number < v_first;
      elsif p_operator = 'lte' then v_match := v_number <= v_first;
      elsif p_operator = 'gt' then v_match := v_number > v_first;
      elsif p_operator = 'gte' then v_match := v_number >= v_first;
      elsif p_operator = 'between' then
        v_second := (p_values ->> 1)::numeric;
        v_match := v_number between least(v_first, v_second)
          and greatest(v_first, v_second);
      elsif p_operator = 'in' then
        v_match := exists (
          select 1 from jsonb_array_elements(p_values) requested(value)
          where v_number = (requested.value #>> '{}')::numeric
        );
      end if;
    elsif v_definition.data_type = 'boolean' then
      if v_value.value_boolean is null then return 'conflict'; end if;
      v_boolean := (p_values ->> 0)::boolean;
      if p_operator = 'eq' then v_match := v_value.value_boolean = v_boolean;
      elsif p_operator = 'neq' then v_match := v_value.value_boolean <> v_boolean;
      end if;
    elsif v_definition.data_type in ('single_select', 'multi_select', 'text') then
      if p_operator = 'contains' then
        v_candidate_normalized := public.assistant_normalize_query_internal_v1(
          p_values ->> 0
        );
        v_match := position(v_candidate_normalized in
          public.assistant_normalize_query_internal_v1(concat_ws(' ',
            v_value.value_text, v_value.value_option, v_value.display_value,
            v_value.value_json::text
          ))) > 0;
      else
        v_match := exists (
          select 1
          from jsonb_array_elements(p_values) requested(value)
          where public.assistant_normalize_query_internal_v1(
              requested.value #>> '{}'
            ) in (
              public.assistant_normalize_query_internal_v1(v_value.value_text),
              public.assistant_normalize_query_internal_v1(v_value.value_option),
              public.assistant_normalize_query_internal_v1(v_value.display_value)
            )
            or (
              jsonb_typeof(v_value.value_json) = 'array'
              and exists (
                select 1
                from jsonb_array_elements(v_value.value_json) member(value)
                where jsonb_typeof(member.value) in ('string', 'number', 'boolean')
                  and public.assistant_normalize_query_internal_v1(
                    member.value #>> '{}'
                  ) = public.assistant_normalize_query_internal_v1(
                    requested.value #>> '{}'
                  )
              )
            )
        );
        if p_operator = 'neq' then v_match := not v_match; end if;
      end if;
    end if;
    return case when v_match then 'product_spec' else 'conflict' end;
  end if;

  -- Curated identity may fill only exact equality/membership for an empty
  -- ficha. It is never a range engine: 68x122.5 cannot prove "eje < 125".
  if p_operator in ('eq', 'in') then
    for v_candidate in
      select requested.value #>> '{}'
      from jsonb_array_elements(p_values) requested(value)
    loop
      v_candidate_normalized := public.assistant_normalize_query_internal_v1(
        v_candidate
      );
      if position(
           ' ' || v_candidate_normalized || ' '
           in ' ' || coalesce(p_identity_surface, '') || ' '
         ) > 0
         or (
           v_candidate_normalized ~ '^[0-9]+(?:[.]?[0-9]+)?$'
           and coalesce(p_identity_raw, '') ~ (
             '(^|[^0-9.])' || replace(v_candidate_normalized, '.', '[.]') ||
             '([^0-9.]|$)'
           )
         ) then
        return 'identity_fallback';
      end if;
    end loop;
  end if;
  return 'unresolved';
end;
$function$
;

commit;
