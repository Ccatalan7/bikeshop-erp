-- Las medidas se sueltan de a una, la menos cubierta primero.
--
-- El intento anterior soltaba sólo las medidas sin cobertura, y eso dejó un
-- hueco: cuando DOS medidas tienen cobertura por separado pero su combinación
-- no calza con ningún producto, no había nada que soltar y la respuesta
-- quedaba en cero. Medido: «Cámaras 29 Schrader» pasó de devolver 29 productos
-- equivocados a no devolver ninguno.
--
-- Ahora se suelta una por intento, empezando por la que menos productos toca en
-- esa rama —la que menos distingue—, y se prueba de nuevo. Así el «29»
-- sobrevive al «Schrader», que es el orden que el taller espera.

begin;

create or replace function public.purchase_query_products_internal_v1(
  p_tenant_id uuid,
  p_query text,
  p_only_purchased boolean default true
)
returns table(
  product_id uuid,
  dropped_words text,
  dropped_filters text,
  requested_gamas text[]
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_query text;
  v_inferred jsonb;
  v_inferred_categories uuid[];
  v_predicates jsonb := '[]'::jsonb;
  v_requested_gamas text[];
  v_query_full text;
  v_match_any boolean := false;
  v_dropped_words text;
  v_dropped_filters text;
  v_attempt integer;
  v_found integer := 0;
begin
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  if v_query is null then
    return;
  end if;

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

  -- La gama se dice con palabras, y esas palabras no están en el nombre de
  -- ningún producto. Se consumen como señal de banda y salen del texto.
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

  v_query_full := v_query;

  -- **La respuesta baja un escalón; no se cae de golpe.** Se sueltan filtros de
  -- a uno, del más frágil al más firme. La RAMA nunca se suelta.
  for v_attempt in 1..8 loop
    if v_attempt > 1 and v_found > 0 then
      exit;
    end if;

    if v_attempt = 2 then
      continue when v_query is null
        or (v_inferred_categories is null
            and jsonb_array_length(v_predicates) = 0);
      v_dropped_words := v_query;
      v_query := null;
    elsif v_attempt between 3 and 7 then
      -- **Las medidas se sueltan de a una, la menos cubierta primero.**
      --
      -- Soltarlas en bloque perdía la que importaba: «Cámaras 29 Schrader»
      -- pasaba de 6 productos a 29 —cámaras de 26 y de 700c presentadas como
      -- evidencia de una compra de 29—. Y soltar sólo las que no tienen
      -- cobertura tampoco basta: cuando las dos la tienen por separado y su
      -- COMBINACIÓN no calza, no había nada que soltar y la respuesta quedaba
      -- en cero.
      --
      -- Se suelta una por intento, empezando por la que menos productos toca
      -- en esta rama: la que menos distingue. Así «29» sobrevive a «Schrader».
      continue when jsonb_array_length(v_predicates) = 0
        or v_inferred_categories is null;
      select coalesce(jsonb_agg(medida.value order by medida.ord), '[]'::jsonb)
      into v_predicates
      from (
        select item.value, item.ordinality ord,
          (
            select count(*)
            from public.products product
            where product.tenant_id = p_tenant_id
              and product.is_active is true
              and product.category_id = any(v_inferred_categories)
              and public.assistant_inventory_technical_predicate_source_internal_v1(
                p_tenant_id, product.id,
                item.value ->> 'field',
                item.value ->> 'operator',
                coalesce(item.value -> 'values', '[]'::jsonb),
                public.assistant_normalize_query_internal_v1(concat_ws(' ',
                  product.name, product.brand, product.model,
                  product.manufacturer, product.category_name, product.category
                )),
                unaccent(lower(concat_ws(' ', product.name, product.brand,
                  product.model, product.manufacturer, product.category_name,
                  product.category)))
              ) in ('product_spec', 'identity_fallback')
          ) cobertura
        from jsonb_array_elements(v_predicates)
          with ordinality as item(value, ordinality)
      ) medida
      where medida.ord <> (
        select ord from (
          select item.ordinality ord,
            (
              select count(*)
              from public.products product
              where product.tenant_id = p_tenant_id
                and product.is_active is true
                and product.category_id = any(v_inferred_categories)
                and public.assistant_inventory_technical_predicate_source_internal_v1(
                  p_tenant_id, product.id,
                  item.value ->> 'field',
                  item.value ->> 'operator',
                  coalesce(item.value -> 'values', '[]'::jsonb),
                  public.assistant_normalize_query_internal_v1(concat_ws(' ',
                    product.name, product.brand, product.model,
                    product.manufacturer, product.category_name,
                    product.category
                  )),
                  unaccent(lower(concat_ws(' ', product.name, product.brand,
                    product.model, product.manufacturer,
                    product.category_name, product.category)))
                ) in ('product_spec', 'identity_fallback')
            ) cobertura
          from jsonb_array_elements(v_predicates)
            with ordinality as item(value, ordinality)
        ) ranking
        order by cobertura asc, ord desc
        limit 1
      );
      v_dropped_filters := 'la medida menos determinante';
    elsif v_attempt = 8 then
      continue when v_query_full is null
        or not exists (
          select 1 from regexp_split_to_table(v_query_full, ' +') token
          where length(token) >= 3
        );
      v_query := v_query_full;
      v_match_any := true;
      v_dropped_words := null;
      v_dropped_filters := 'la coincidencia de todas las palabras';
    end if;

    return query
    with requested_predicates as (
      select predicate.value ->> 'field' as field_key,
        predicate.value ->> 'operator' as operator,
        coalesce(predicate.value -> 'values', '[]'::jsonb) as values
      from jsonb_array_elements(v_predicates) predicate(value)
    ), universe as materialized (
      select distinct product.id as pid,
        product.category_id,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )) identity_surface,
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category))) identity_raw
      from public.products product
      where product.tenant_id = p_tenant_id
        and product.is_active is true
        and (
          not p_only_purchased
          or exists (
            select 1
            from public.purchase_line_landed_cost_observations_v1 observation
            where observation.tenant_id = p_tenant_id
              and observation.product_id = product.id
              and observation.document_status in ('received', 'paid')
          )
        )
    )
    select universe.pid, v_dropped_words, v_dropped_filters, v_requested_gamas
    from universe
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec', 'identity_fallback'
        )), true) predicates_match
      from requested_predicates predicate
      cross join lateral (
        select public.assistant_inventory_technical_predicate_source_internal_v1(
          p_tenant_id, universe.pid, predicate.field_key,
          predicate.operator, predicate.values, universe.identity_surface,
          universe.identity_raw
        ) value
      ) source
    ) predicate_state
    where predicate_state.predicates_match
      and (
        v_inferred_categories is null
        or universe.category_id = any(v_inferred_categories)
      )
      and (
        v_query is null
        or (
          case when v_match_any then
            exists (
              select 1 from regexp_split_to_table(v_query, ' +') token
              where length(token) >= 3
                and (
                  ' ' || universe.identity_surface || ' '
                    like '% ' || token || ' %'
                  or ' ' || universe.identity_surface || ' '
                    like '% ' || public.purchase_word_stem_internal_v1(token)
                      || ' %'
                )
            )
          else
            not exists (
              select 1 from regexp_split_to_table(v_query, ' +') token
              where position(token in universe.identity_surface) = 0
                and position(
                  public.purchase_word_stem_internal_v1(token)
                  in universe.identity_surface
                ) = 0
            )
          end
        )
      );

    get diagnostics v_found = row_count;
  end loop;
end;
$$;

revoke all on function public.purchase_query_products_internal_v1(
  uuid, text, boolean
) from public, anon, authenticated, service_role;

commit;
