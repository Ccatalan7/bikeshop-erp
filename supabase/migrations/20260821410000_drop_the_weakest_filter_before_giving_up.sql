-- «Necesito un motor para una caja inglesa de 68 mm con eje cuadrado de 118 mm.
-- ¿Qué tengo en bodega?» —frase del dueño, 2026-08-21— deducía los cuatro
-- filtros correctos y devolvía cero. Uno de ellos,
-- `spindle_interface_accepted`, tiene ficha cargada en cinco productos y
-- ninguno es un motor; exigirlo borraba el resultado entero.
--
-- Ahora los predicados deducidos vienen ordenados por cuánta ficha respalda a
-- cada campo, y el buscador suelta el más débil y reintenta antes de contestar
-- que no hay nada. Es la regla que el dueño pidió desde el principio: si le
-- sobra un dato, que lo descarte y siga con el que sí sirve.

CREATE OR REPLACE FUNCTION public.assistant_infer_technical_predicates_internal_v1(p_tenant_id uuid, p_query text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  with params as (
    select p_tenant_id as tid, coalesce(p_query, '') as q
  ), scoped as (
    select distinct on (d.key) d.id, d.key, d.label, d.data_type
    from public.spec_definitions d
    cross join params p
    where d.is_filterable is true
      and (d.tenant_id is null or d.tenant_id = p.tid)
      -- `boolean` entra recién ahora: sin él, `includes_spindle` no existía
      -- para la inferencia y ninguna negación podía amarrarse.
      and d.data_type in (
        'number', 'single_select', 'multi_select', 'text', 'boolean'
      )
    order by d.key, (d.tenant_id is not null) desc
  ), tokens as (
    -- El normalizador de búsqueda borra el punto decimal: «122.5» se vuelve
    -- «122» y «5». Para leer una medida hay que tokenizar el texto crudo.
    select case
        when t.token ~ '^[0-9]+,[0-9]+$' then replace(t.token, ',', '.')
        else btrim(t.token, '.,')
      end token,
      t.ordinality
    from params p
    cross join lateral regexp_split_to_table(
      unaccent(lower(p.q)), '[^a-z0-9.,]+'
    ) with ordinality as t(token, ordinality)
    where btrim(t.token, '.,') <> ''
  ), stop_words as (
    -- Palabras del idioma, no del dominio. «Con uña / claw» convertía
    -- cualquier frase con «con una» en un filtro de patilla trasera; lo
    -- detectó el read-back antes de que llegara al asistente. La lista es de
    -- español, no de bicicletas: el vocabulario técnico sigue saliendo del
    -- catálogo, nunca de una lista escrita a mano.
    select unnest(array[
      'con', 'sin', 'por', 'para', 'que', 'del', 'las', 'los', 'una', 'uno',
      'unos', 'unas', 'como', 'mas', 'muy', 'este', 'esta', 'esto', 'esos',
      'esas', 'the', 'and', 'for', 'with'
    ]) token
  ), vocab_tokens as (
    select s.key, s.id def_id, v.label, vt.token
    from scoped s
    cross join params p
    join public.spec_definition_values v
      on v.spec_definition_id = s.id
     and v.is_active is true
     and (v.tenant_id is null or v.tenant_id = p.tid)
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(v.label), ' +'
    ) vt(token)
    where vt.token ~ '^[a-z]{3,}$'
      and vt.token not in (select token from stop_words)
  ), all_label_tokens as (
    -- Las palabras de los RÓTULOS, sin acotar por alcance. Una palabra que
    -- nombra un campo no puede ser evidencia de un valor: «caja» está en «Caja
    -- de motor» y en «Ancho caja motor», y por aparecer además dentro de un
    -- solo valor hacía que «motor caja 73» asumiera BSA en silencio.
    select distinct lt.token
    from scoped s
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(s.label), ' +'
    ) lt(token)
    where lt.token ~ '^[a-z]{3,}$'
  ), definition_coverage as (
    select f.spec_definition_id id, count(distinct f.subject_id) n
    from public.spec_facts f
    cross join params p
    where f.tenant_id = p.tid and f.subject_type = 'product'
    group by 1
  ), vocab_candidates as (
    select vt.token, vt.key, vt.label, coalesce(dc.n, 0) coverage
    from vocab_tokens vt
    left join definition_coverage dc on dc.id = vt.def_id
    where vt.token not in (select token from all_label_tokens)
  ), vocab_top as (
    select token, max(coverage) top from vocab_candidates group by token
  ), vocab_unique as (
    -- «bsa» vive en cuatro campos —caja, mano de la rosca y dos heredados—.
    -- Decide el catálogo: gana el campo que el taller realmente llena, y sólo
    -- si gana solo. Un campo sin un hecho cargado no compite.
    select c.token, min(c.key) key
    from vocab_candidates c
    join vocab_top t2 on t2.token = c.token and c.coverage = t2.top
    group by c.token
    having count(distinct c.key) = 1 and max(c.coverage) > 0
  ), vocab_hits as (
    select distinct u.key, c.label, tk.ordinality
    from vocab_unique u
    join vocab_candidates c on c.token = u.token and c.key = u.key
    join tokens tk on tk.token = u.token
  ), query_categories as (
    -- «motor» no es el nombre exacto de la categoría «Motores», pero sí una
    -- palabra de su ruta. Ese es el ancla que vuelve resoluble un rótulo
    -- genérico cuando la frase no trae ninguna palabra del vocabulario.
    select c.id, public.assistant_normalize_query_internal_v1(c.full_path) path
    from public.product_categories c
    cross join params p
    where c.tenant_id = p.tid
      and c.is_active is true
      and exists (
        select 1 from tokens t
        where t.token ~ '^[a-z]{4,}$'
          and position(
            t.token in public.assistant_normalize_query_internal_v1(c.full_path)
          ) > 0
      )
  ), vocab_scope as (
    select distinct other.spec_definition_id
    from vocab_hits hit
    join scoped s on s.key = hit.key
    join public.spec_template_fields own on own.spec_definition_id = s.id
    join public.spec_template_fields other on other.template_id = own.template_id
  ), category_scope_fields as (
    select distinct tf.spec_definition_id
    from query_categories qc
    cross join params p
    join public.category_tech_mappings m
      on m.category_id = qc.id and m.tenant_id = p.tid and m.status = 'active'
    join public.spec_templates tpl
      on tpl.is_active is true
     and (tpl.tenant_id is null or tpl.tenant_id = p.tid)
     and (tpl.id = m.template_id
       or (m.template_id is null and tpl.technical_family = m.technical_family))
    join public.spec_template_fields tf on tf.template_id = tpl.id
  ), family_scope as (
    select spec_definition_id from vocab_scope
    union all
    select spec_definition_id from category_scope_fields
    where not exists (select 1 from vocab_scope)
  ), label_tokens as (
    select s.key, s.data_type, lt.token
    from scoped s
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(s.label), ' +'
    ) lt(token)
    where lt.token ~ '^[a-z]{3,}$'
      and lt.token not in (select token from stop_words)
      and (
        not exists (select 1 from family_scope)
        or s.id in (select spec_definition_id from family_scope)
      )
  ), label_counts as (
    select token, count(distinct key) n, min(key) key, min(data_type) dt
    from label_tokens
    group by token
  ), numeric_cues as (
    select token, key from label_counts where n = 1 and dt = 'number'
  ), number_tokens as (
    select token::numeric value, token, ordinality
    from tokens
    where token ~ '^[0-9]+([.][0-9]+)?$'
  ), cue_bindings as (
    select distinct on (c.key) c.key, n.value, n.ordinality, t.ordinality cue_ord
    from numeric_cues c
    join tokens t on t.token = c.token
    join number_tokens n
      on n.ordinality > t.ordinality and n.ordinality <= t.ordinality + 4
    order by c.key, n.ordinality
  ), numeric_vocab as (
    -- «160» no es una medida libre: es una opción de `rotor_diameter_mm`, que
    -- es una lista cuyos valores son números. Lo mismo pasa con el rodado
    -- («29\"») y el número de rayos. Sin esta regla, «discos de freno de 160»
    -- devolvía cero teniendo siete en bodega.
    --
    -- Se compara contra el rótulo despojado de puntuación, no contra el
    -- normalizador de búsqueda: ése borra el punto decimal y «27.5» dejaría de
    -- calzar. Y se compara por igualdad, no por fragmento, para que «160» no
    -- se lleve «160/140».
    select n.ordinality, min(s.key) key, min(v.label) label
    from number_tokens n
    cross join params p
    join scoped s
      on s.data_type in ('single_select', 'multi_select')
     and s.id in (select spec_definition_id from family_scope)
    join public.spec_definition_values v
      on v.spec_definition_id = s.id
     and v.is_active is true
     and (v.tenant_id is null or v.tenant_id = p.tid)
     and regexp_replace(lower(unaccent(v.label)), '[^a-z0-9.]', '', 'g') = n.token
    where not exists (
      select 1 from cue_bindings b where b.ordinality = n.ordinality
    )
    group by n.ordinality
    having count(distinct s.key) = 1
  ), fact_bindings as (
    -- Un número sin pista —«manubrio 31.8»— se resuelve si dentro del alcance
    -- existe un solo campo cuyos hechos reales lo contengan. Decide el
    -- catálogo, no una lista escrita a mano.
    select n.ordinality, n.value, min(s.key) key
    from number_tokens n
    cross join params p
    join public.spec_facts f
      on f.tenant_id = p.tid and f.value_number = n.value
    join scoped s
      on s.id = f.spec_definition_id
     and s.data_type = 'number'
     and s.id in (select spec_definition_id from family_scope)
    where not exists (
      select 1 from cue_bindings b where b.ordinality = n.ordinality
    )
    and not exists (
      select 1 from numeric_vocab nv where nv.ordinality = n.ordinality
    )
    group by n.ordinality, n.value
    having count(distinct s.key) = 1
  ), boolean_cues as (
    -- «eje» no sirve como pista numérica —está en «Largo eje» y en «Punta del
    -- eje»—, pero entre los campos BOOLEANOS del alcance sólo lo tiene
    -- «Incluye eje». Esa distinción alcanza, y evita inventarle sinónimos al
    -- idioma: «traen», «incluye» y «con» no aparecen en ninguna lista.
    select s.key, lt.token
    from scoped s
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(s.label), ' +'
    ) lt(token)
    where s.data_type = 'boolean'
      and s.id in (select spec_definition_id from family_scope)
      and lt.token ~ '^[a-z]{3,}$'
      and lt.token not in (select token from stop_words)
  ), boolean_unique as (
    select token, min(key) key
    from boolean_cues group by token having count(distinct key) = 1
  ), negation_bindings as (
    -- Sólo se amarra la negación. Afirmar es ambiguo: «con largo de eje 118»
    -- habla de la medida, no de si el motor trae eje, y amarrar «true» ahí
    -- dejaría fuera productos correctos.
    select distinct on (u.key) u.key, t.ordinality, neg.ordinality neg_ord
    from boolean_unique u
    join tokens t on t.token = u.token
    join tokens neg
      on neg.token in ('no', 'sin', 'ningun', 'ninguna')
     and neg.ordinality < t.ordinality
     and neg.ordinality >= t.ordinality - 3
    order by u.key, t.ordinality
  ), predicates as (
    select key, 'in' operator,
      jsonb_agg(distinct to_jsonb(label)) values, min(ordinality) ordinality
    from vocab_hits group by key
    union all
    select key, 'eq', jsonb_build_array(to_jsonb(value)), ordinality
    from cue_bindings
    union all
    select key, 'eq', jsonb_build_array(to_jsonb(value)), ordinality
    from fact_bindings
    union all
    select key, 'in', jsonb_build_array(to_jsonb(label)), ordinality
    from numeric_vocab
    union all
    select key, 'eq', jsonb_build_array(to_jsonb(false)), ordinality
    from negation_bindings
  ), predicates_ranked as (
    -- Se ordenan por cuánta ficha tiene cargada cada campo. El buscador
    -- descarta desde el final si la combinación completa no calza nada: un
    -- campo casi vacío es el primero en sobrar.
    select p.key, p.operator, p.values, p.ordinality,
      coalesce(dc.n, 0) coverage
    from predicates p
    join scoped s on s.key = p.key
    left join definition_coverage dc on dc.id = s.id
  ), bounded_predicates as (
    select * from predicates_ranked order by coverage desc, ordinality limit 8
  ), category_words as (
    select distinct t.ordinality
    from tokens t
    join query_categories qc on position(t.token in qc.path) > 0
    where t.token ~ '^[a-z]{4,}$'
  ), consumed as (
    select ordinality from vocab_hits
    union select ordinality from cue_bindings
    union select cue_ord from cue_bindings
    union select ordinality from fact_bindings
    union select ordinality from numeric_vocab
    union select ordinality from negation_bindings
    union select neg_ord from negation_bindings
    union select ordinality from category_words
    union select t.ordinality from tokens t
      where exists (select 1 from vocab_tokens v where v.token = t.token)
         or exists (select 1 from label_tokens l where l.token = t.token)
  ), residual_candidates as (
    select t.token, t.ordinality
    from tokens t
    where t.ordinality not in (select ordinality from consumed)
      -- Un código de producto —«bc73»— es identidad, no palabra vacía: si se
      -- exige sólo letras, una frase mixta pierde la parte que identifica.
      -- Pero bajar el largo a tres dejó pasar «con», que existe como palabra
      -- suelta en nombres del catálogo («manilla con cable») y por lo tanto
      -- exigía «con» en cada resultado: cero. Tres caracteres sólo valen si
      -- traen un dígito; si son puras letras, hacen falta cuatro.
      and t.token ~ '^[a-z0-9]{3,}$'
      and (t.token ~ '[0-9]' or length(t.token) >= 4)
      and t.token not in (select token from stop_words)
  ), residual_tokens as (
    -- Lo que sobra sólo se conserva si nombra algo real del catálogo —una
    -- marca, un modelo—. «dame», «necesito» y «quiero» no sobreviven ese
    -- filtro, y por eso no hace falta una lista de palabras vacías.
    --
    -- El barrido de productos se paga por palabra candidata, no por consulta:
    -- medido el 2026-08-21, precomputarlo costaba 660 ms incluso cuando no
    -- quedaba ninguna palabra por revisar.
    select c.token, c.ordinality
    from residual_candidates c
    where exists (
      select 1
      from public.products pr
      cross join params p
      where pr.tenant_id = p.tid
        and pr.is_active is true
        and public.assistant_normalize_query_internal_v1(concat_ws(' ',
          pr.name, pr.sku, pr.barcode, pr.brand, pr.model, pr.manufacturer,
          pr.category_name, pr.category, pr.description
        )) ~ ('(^| )' || c.token || '( |$)')
    )
  )
  select jsonb_build_object(
    'categories', coalesce((
      select jsonb_agg(distinct qc.id) from query_categories qc
    ), '[]'::jsonb),
    'predicates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'field', key, 'operator', operator, 'values', values
      ) order by coverage desc, ordinality)
      from bounded_predicates
    ), '[]'::jsonb),
    'residual', coalesce((
      select string_agg(token, ' ' order by ordinality) from residual_tokens
    ), '')
  );
$function$
;

CREATE OR REPLACE FUNCTION public.assistant_search_inventory_v7(p_query text, p_category text, p_availability text, p_technical_predicates jsonb, p_operational_predicates jsonb, p_sort_field text, p_sort_direction text, p_limit integer, p_selection_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_predicate jsonb;
  v_translated_values jsonb;
  v_untranslated integer;
  v_applied_predicates jsonb := '[]'::jsonb;
  v_dropped_predicates integer := 0;
  v_field text;
  v_operator text;
  v_values jsonb;
  v_definition record;
  v_fields text[] := array[]::text[];
  v_operational_predicate jsonb;
  v_operational_field text;
  v_operational_operator text;
  v_operational_values jsonb;
  v_operational_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
  v_inferred jsonb;
  v_inferred_predicates jsonb;
  v_inferred_categories uuid[];
  v_model_predicates jsonb := '[]'::jsonb;
  v_relaxations integer := 0;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability is null
     or p_availability not in ('any', 'in_stock', 'low_stock', 'out_of_stock')
     or jsonb_typeof(p_technical_predicates) <> 'array'
     or jsonb_array_length(p_technical_predicates) > 8
     or jsonb_typeof(p_operational_predicates) <> 'array'
     or jsonb_array_length(p_operational_predicates) > 6
     or p_sort_field is null
     or p_sort_field not in ('relevance','name','stock','minimum_stock','price')
     or p_sort_direction is null
     or p_sort_direction not in ('asc','desc')
     or (p_sort_field = 'relevance' and p_sort_direction <> 'desc')
     or p_limit not between 1 and 10
     or p_selection_mode is null
     or p_selection_mode not in ('all_matches','top_n') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );
  if v_category is not null and not exists (
    select 1
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_predicate in
    select value
    from jsonb_array_elements(p_technical_predicates) item(value)
  loop
    if jsonb_typeof(v_predicate) <> 'object'
       or not (
         v_predicate ? 'field' and v_predicate ? 'operator'
         and v_predicate ? 'values'
       )
       or jsonb_typeof(v_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_predicate -> 'values') <> 'array'
       or exists (
         select 1 from jsonb_object_keys(v_predicate) key
         where key not in ('field', 'operator', 'values')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_field := btrim(v_predicate ->> 'field');
    v_operator := v_predicate ->> 'operator';
    v_values := v_predicate -> 'values';
    select definition.data_type, definition.allowed_values
    into v_definition
    from public.spec_definitions definition
    where definition.key = v_field
      and (
        definition.tenant_id is null
        or definition.tenant_id = v_authority.tenant_id
      )
      and definition.is_filterable is true
    order by (definition.tenant_id is not null) desc
    limit 1;
    if not found
       or v_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or v_field = any(v_fields)
       or v_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in','contains'
       )
       or jsonb_array_length(v_values) not between 1 and 10
       or (v_operator = 'between' and jsonb_array_length(v_values) <> 2)
       or (
         v_operator not in ('between','in')
         and jsonb_array_length(v_values) <> 1
       )
       or (v_definition.data_type = 'number' and (
         v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'number'
         )
       ))
       or (v_definition.data_type = 'boolean' and (
         v_operator not in ('eq','neq')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'boolean'
         )
       ))
       or (v_definition.data_type in ('single_select','multi_select') and (
         v_operator not in ('eq','neq','in','contains')
         or exists (
           select 1
           from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
         )
       ))
       or (v_definition.data_type = 'text' and (
         v_operator not in ('eq','neq','in','contains')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or octet_length(requested.value #>> '{}') not between 1 and 120
         )
       ))
       or v_definition.data_type not in (
         'number','boolean','single_select','multi_select','text'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_fields := array_append(v_fields, v_field);

    -- Interpretar antes de actuar. El operador habla como habla: «caja
    -- inglesa», «cuadrado», «hollowtech». El vocabulario guarda la entrada
    -- completa. Traducir eso es trabajo del buscador, no del operador: se
    -- resuelve contra `allowed_values` y recién ahí se filtra.
    if v_definition.data_type in ('single_select', 'multi_select')
       and v_operator in ('eq', 'neq', 'in')
       and jsonb_array_length(v_definition.allowed_values) > 0 then
      -- Un término que calza con varias entradas NO es un problema: es un
      -- filtro más ancho. «cuadrado» calza con JIS y con ISO, y los dos son
      -- cuadrados — se devuelven los dos. Rendirse ahí sería esconderle al
      -- operador stock que sí sirve.
      select jsonb_agg(distinct candidata), count(*) filter (where sin_traduccion)
      into v_translated_values, v_untranslated
      from (
        select
          jsonb_array_elements(
            public.assistant_resolve_select_value_internal_v1(
              v_definition.allowed_values, pedido.value #>> '{}'
            )
          ) as candidata,
          false as sin_traduccion
        from jsonb_array_elements(v_values) as pedido(value)
        union all
        select null::jsonb, true
        from jsonb_array_elements(v_values) as pedido(value)
        where jsonb_array_length(
          public.assistant_resolve_select_value_internal_v1(
            v_definition.allowed_values, pedido.value #>> '{}'
          )
        ) = 0
      ) resolucion
      where candidata is not null or sin_traduccion;

      -- Sólo se descarta el predicado cuando NINGÚN término se pudo traducir.
      -- Pedir tres cosas y equivocarse en una devuelve las otras dos.
      if v_translated_values is null
         or jsonb_array_length(v_translated_values) = 0 then
        v_dropped_predicates := v_dropped_predicates + 1;
        continue;
      end if;

      v_values := v_translated_values;
      -- Con más de una candidata la comparación pasa a ser de pertenencia.
      if v_operator = 'eq' and jsonb_array_length(v_values) > 1 then
        v_operator := 'in';
      end if;
    end if;

    v_applied_predicates := v_applied_predicates || jsonb_build_array(
      jsonb_build_object(
        'field', v_field, 'operator', v_operator, 'values', v_values
      )
    );
  end loop;

  -- El resto de la función filtra con los predicados ya traducidos.
  p_technical_predicates := v_applied_predicates;

  -- El operador escribe una frase, no predicados. Cuando el modelo no arma
  -- ninguno, el servidor traduce esa frase contra el registro de vocabulario y
  -- los hechos reales, y filtra con lo que reconoce. Las palabras que sobran se
  -- descartan: el filtro de texto exige que *cada* palabra esté en el nombre
  -- del producto, así que dejar «dame» o «caja» dentro devolvía cero.
  -- Los productos sin ficha no se pierden: el resolvedor de predicados admite
  -- `identity_fallback`, que reconoce la medida en el propio nombre.
  -- La traducción corre siempre que haya frase, no sólo cuando el modelo se
  -- abstuvo de armar predicados: lo que el modelo mande no puede decidir si el
  -- servidor entiende o no la frase del operador. Los predicados del modelo
  -- mandan sobre su propio campo; la frase sólo aporta los campos que él no
  -- tocó, y el texto libre se reduce a lo que no se pudo traducir.
  if v_query is not null then
    v_inferred := public.assistant_infer_technical_predicates_internal_v1(
      v_authority.tenant_id, p_query
    );
    v_inferred_predicates := coalesce(v_inferred -> 'predicates', '[]'::jsonb);
    -- La frase nombró una rama del catálogo —«discos de freno», «motores»—.
    -- Esas palabras se consumen para que no maten el filtro de texto, así que
    -- tienen que volver como lo que son: un filtro de categoría. Sin esto,
    -- «discos de freno de 160» calzaba 23 productos —siete rotores por ficha y
    -- dieciséis por traer «160» en el nombre, entre ellos bielas y cadenas—.
    select array_agg((category.value #>> '{}')::uuid)
    into v_inferred_categories
    from jsonb_array_elements(
      coalesce(v_inferred -> 'categories', '[]'::jsonb)
    ) category(value);

    if jsonb_array_length(v_inferred_predicates) > 0 then
      -- Sobre un mismo campo manda el valor deducido, no el del modelo: el
      -- deducido salió de `spec_definition_values`, así que existe con
      -- certeza, mientras que el del modelo es una abreviatura suya —«BSA»
      -- por «BSA / Caja inglesa 34,8 mm (1.37\") x 24»— que al no traducir
      -- filtra a cero. Los campos que la frase no menciona los conserva él.
      select coalesce(jsonb_agg(kept.value), '[]'::jsonb)
      into p_technical_predicates
      from jsonb_array_elements(p_technical_predicates) kept(value)
      where not exists (
        select 1
        from jsonb_array_elements(v_inferred_predicates) inferred(value)
        where inferred.value ->> 'field' = kept.value ->> 'field'
      );
      v_model_predicates := p_technical_predicates;
      p_technical_predicates := v_model_predicates || v_inferred_predicates;
      -- Sólo se toca el texto cuando algo se tradujo. Si no, «VP-BC73» sigue
      -- siendo una búsqueda por identidad y no se puede borrar.
      v_query := nullif(btrim(v_inferred ->> 'residual'), '');
    end if;
  end if;

  for v_operational_predicate in
    select value
    from jsonb_array_elements(p_operational_predicates) item(value)
  loop
    if jsonb_typeof(v_operational_predicate) <> 'object'
       or not (
         v_operational_predicate ? 'field'
         and v_operational_predicate ? 'operator'
         and v_operational_predicate ? 'values'
       )
       or jsonb_typeof(v_operational_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'values') <> 'array'
       or exists (
         select 1 from jsonb_object_keys(v_operational_predicate) key
         where key not in ('field', 'operator', 'values')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_field := btrim(v_operational_predicate ->> 'field');
    v_operational_operator := v_operational_predicate ->> 'operator';
    v_operational_values := v_operational_predicate -> 'values';
    if v_operational_field not in ('stock', 'minimum_stock', 'price')
       or v_operational_field = any(v_operational_fields)
       or v_operational_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in'
       )
       or jsonb_array_length(v_operational_values) not between 1 and 10
       or (
         v_operational_operator = 'between'
         and jsonb_array_length(v_operational_values) <> 2
       )
       or (
         v_operational_operator not in ('between','in')
         and jsonb_array_length(v_operational_values) <> 1
       )
       or exists (
         select 1
         from jsonb_array_elements(v_operational_values) requested(value)
         where jsonb_typeof(requested.value) <> 'number'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_fields := array_append(
      v_operational_fields, v_operational_field
    );
  end loop;

  -- Si la combinación completa no calza nada, el filtro más débil sobra: se
  -- suelta y se vuelve a preguntar. Los predicados deducidos vienen ordenados
  -- por cuánta ficha tiene cargada cada campo, así que el último es siempre el
  -- que menos respalda el catálogo.
  --
  -- Caso real del dueño, 2026-08-21: «caja inglesa de 68 mm con eje cuadrado de
  -- 118 mm» deducía los cuatro filtros correctos y devolvía cero, porque
  -- `spindle_interface_accepted` tiene ficha en cinco productos y ninguno era
  -- un motor. Rendirse ahí es lo contrario de lo que el operador pidió.
  loop
    with recursive selected_category as materialized (
      select category.id, category.name, category.full_path
      from public.product_categories category
      where v_category is not null
        and category.tenant_id = v_authority.tenant_id
        and category.is_active is true
        and (
          public.assistant_normalize_query_internal_v1(category.name) = v_category
          or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
        )
      order by (
        public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      ) desc, category.level desc
      limit 1
    ), category_scope as (
      select selected.id from selected_category selected
      union
      select child.id
      from public.product_categories child
      join category_scope parent on child.parent_id = parent.id
      where child.tenant_id = v_authority.tenant_id
        and child.is_active is true
    ), scoped_families as materialized (
      select distinct mapping.technical_family
      from category_scope scope
      join public.category_tech_mappings mapping
        on mapping.tenant_id = v_authority.tenant_id
       and mapping.category_id = scope.id
       and mapping.status = 'active'
      where mapping.technical_family is not null
    ), requested_predicates as materialized (
      select predicate.value ->> 'field' field_key,
        predicate.value ->> 'operator' operator,
        predicate.value -> 'values' values
      from jsonb_array_elements(p_technical_predicates) predicate(value)
    ), requested_operational_predicates as materialized (
      select predicate.value ->> 'field' field_key,
        predicate.value ->> 'operator' operator,
        predicate.value -> 'values' values
      from jsonb_array_elements(p_operational_predicates) predicate(value)
    ), product_surfaces as materialized (
      select product.id entity_id, product.category_id,
        mapping.technical_family, product.name, product.sku, product.brand,
        product.category_name, product.category, product.price,
        product.warehouse_location, product.updated_at,
        coalesce(product.track_stock, false) tracks_inventory,
        greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
        public.inventory_available_quantity_v1(
          product.tenant_id, product.id
        ) available_stock,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.sku, product.barcode, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category, product.description
        )) search_surface,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )) identity_surface,
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category))) identity_raw,
        public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
        public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
      from public.products_with_sets product
      left join public.category_tech_mappings mapping
        on mapping.tenant_id = product.tenant_id
       and mapping.category_id = product.category_id
       and mapping.status = 'active'
      where product.tenant_id = v_authority.tenant_id
        and product.is_active is true
    ), scoped as materialized (
      select product.*, predicate_state.technical_match
      from product_surfaces product
      cross join lateral (
        select coalesce(bool_and(source.value in (
            'product_spec','identity_fallback'
          )), true) predicates_match,
          case
            when count(*) = 0 then 'not_applicable'
            when bool_and(source.value = 'product_spec') then 'product_spec'
            else 'identity_fallback'
          end technical_match
        from requested_predicates predicate
        cross join lateral (
          select public.assistant_inventory_technical_predicate_source_internal_v1(
            v_authority.tenant_id, product.entity_id, predicate.field_key,
            predicate.operator, predicate.values, product.identity_surface,
            product.identity_raw
          ) value
        ) source
      ) predicate_state
      where predicate_state.predicates_match
        and (
          v_inferred_categories is null
          or product.category_id = any(v_inferred_categories)
        )
        and (
          v_category is null
          or product.category_id in (select id from category_scope)
          or (
            product.technical_family is not null
            and product.technical_family in (
              select technical_family from scoped_families
            )
          )
        )
        and (
          v_query is null
          or not exists (
            select 1 from regexp_split_to_table(v_query, ' +') token
            where case
              when token ~ '[0-9]' then not (
                position(
                  ' ' || token || ' ' in ' ' || product.identity_surface || ' '
                ) > 0
                or (
                  token ~ '^[0-9]+$'
                  and product.identity_raw ~ (
                    '(^|[^0-9])' || token || '([^0-9]|$)'
                  )
                )
                or product.sku_exact = token
                or product.barcode_exact = token
              )
              else position(token in product.search_surface) = 0
            end
          )
        )
    ), matched as materialized (
      select scoped.*,
        case
          when not tracks_inventory then 'not_tracked'
          when available_stock <= 0 then 'out_of_stock'
          when available_stock <= minimum_stock then 'low_stock'
          else 'in_stock'
        end availability
      from scoped
      where (
        p_availability = 'any'
        or (
          p_availability = 'in_stock'
          and tracks_inventory and available_stock > 0
        )
        or (
          p_availability = 'low_stock'
          and tracks_inventory and available_stock > 0
          and available_stock <= minimum_stock
        )
        or (
          p_availability = 'out_of_stock'
          and tracks_inventory and available_stock <= 0
        )
      )
        and not exists (
          select 1
          from requested_operational_predicates predicate
          cross join lateral (
            select case predicate.field_key
              when 'stock' then scoped.available_stock::numeric
              when 'minimum_stock' then scoped.minimum_stock::numeric
              when 'price' then scoped.price::numeric
              else null::numeric
            end actual_value
          ) actual
          where actual.actual_value is null
            or (
              predicate.field_key in ('stock', 'minimum_stock')
              and not scoped.tracks_inventory
            )
            or not case predicate.operator
              when 'eq' then
                actual.actual_value = (predicate.values ->> 0)::numeric
              when 'neq' then
                actual.actual_value <> (predicate.values ->> 0)::numeric
              when 'lt' then
                actual.actual_value < (predicate.values ->> 0)::numeric
              when 'lte' then
                actual.actual_value <= (predicate.values ->> 0)::numeric
              when 'gt' then
                actual.actual_value > (predicate.values ->> 0)::numeric
              when 'gte' then
                actual.actual_value >= (predicate.values ->> 0)::numeric
              when 'between' then actual.actual_value between
                least(
                  (predicate.values ->> 0)::numeric,
                  (predicate.values ->> 1)::numeric
                ) and greatest(
                  (predicate.values ->> 0)::numeric,
                  (predicate.values ->> 1)::numeric
                )
              when 'in' then exists (
                select 1
                from jsonb_array_elements_text(
                  predicate.values
                ) requested(value)
                where requested.value::numeric = actual.actual_value
              )
              else false
            end
        )
    ), numbered as (
      select *,
        count(*) over()::integer matched_count,
        count(*) filter (where tracks_inventory) over()::integer tracked_count,
        coalesce(sum(available_stock) filter (
          where tracks_inventory
        ) over(), 0)::integer total_stock,
        coalesce(sum(greatest(available_stock, 0) * price) filter (
          where tracks_inventory
        ) over(), 0)::numeric inventory_retail_value,
        avg(price) over()::numeric average_price,
        min(price) over()::numeric minimum_price,
        max(price) over()::numeric maximum_price,
        row_number() over (order by
          case
            when p_sort_field = 'stock' and p_sort_direction = 'asc'
              then available_stock
          end asc nulls last,
          case
            when p_sort_field = 'stock' and p_sort_direction = 'desc'
              then available_stock
          end desc nulls last,
          case
            when p_sort_field = 'minimum_stock' and p_sort_direction = 'asc'
              then minimum_stock
          end asc nulls last,
          case
            when p_sort_field = 'minimum_stock' and p_sort_direction = 'desc'
              then minimum_stock
          end desc nulls last,
          case
            when p_sort_field = 'price' and p_sort_direction = 'asc'
              then price
          end asc nulls last,
          case
            when p_sort_field = 'price' and p_sort_direction = 'desc'
              then price
          end desc nulls last,
          case
            when p_sort_field = 'name' and p_sort_direction = 'asc'
              then public.assistant_normalize_query_internal_v1(name)
          end asc nulls last,
          case
            when p_sort_field = 'name' and p_sort_direction = 'desc'
              then public.assistant_normalize_query_internal_v1(name)
          end desc nulls last,
          case
            when p_sort_field = 'relevance' then (
              v_query is not null
              and public.assistant_normalize_query_internal_v1(sku) = v_query
            )
          end desc nulls last,
          case
            when p_sort_field = 'relevance' then (
              v_query is not null
              and position(
                v_query in public.assistant_normalize_query_internal_v1(name)
              ) > 0
            )
          end desc nulls last,
          case when p_sort_field = 'relevance' then updated_at end desc nulls last,
          public.assistant_normalize_query_internal_v1(name), entity_id
        ) ordinal
      from matched
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'entityId', entity_id,
        'name', public.assistant_truncate_utf8_internal_v1(name, 160),
        'sku', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(sku, ''), 80
        ), ''),
        'brand', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(brand, ''), 100
        ), ''),
        'category', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(category_name, category, ''), 100
        ), ''),
        'price', price,
        'stock', available_stock,
        'minimumStock', minimum_stock,
        'availability', availability,
        'tracksInventory', tracks_inventory,
        'location', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(warehouse_location, ''), 120
        ), ''),
        'technicalMatch', technical_match,
        'matchedCount', matched_count,
        'trackedCount', tracked_count,
        'totalStock', total_stock,
        'inventoryRetailValue', inventory_retail_value,
        'averagePrice', average_price,
        'minimumPrice', minimum_price,
        'maximumPrice', maximum_price
      ) order by ordinal) filter (
        where ordinal <= p_limit
      ), '[]'::jsonb),
      coalesce(max(matched_count), 0)
    into v_items, v_total
    from numbered;
    exit when v_total > 0;
    exit when v_relaxations >= 3;
    exit when jsonb_array_length(v_inferred_predicates) <= 1;
    v_inferred_predicates := v_inferred_predicates
      - (jsonb_array_length(v_inferred_predicates) - 1);
    p_technical_predicates := v_model_predicates || v_inferred_predicates;
    v_relaxations := v_relaxations + 1;
  end loop;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    p_selection_mode = 'all_matches' and v_total > p_limit
  );
end;
$function$
;
