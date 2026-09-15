-- «Cubeta NAKASAWA 10561» devolvía cero y el asistente se iba a buscar el
-- producto a internet. La causa: «cubeta» es palabra del rótulo «Diámetro de
-- rosca de cubeta», así que la pista amarraba el número siguiente —el SKU—
-- como si fuera un diámetro de 10.561 mm.
--
-- Una pista sólo puede amarrar un número que el catálogo admita para ese
-- campo. Lo que queda fuera de rango vuelve al texto libre, donde un SKU
-- encuentra su producto.

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
  ), numeric_field_range as (
    -- Lo que el catálogo admite de verdad para cada campo numérico. Sirve de
    -- cordura: una pista no puede amarrar cualquier número que venga detrás.
    select s.key,
      min(f.value_number) lo, max(f.value_number) hi
    from scoped s
    cross join params p
    join public.spec_facts f
      on f.spec_definition_id = s.id and f.tenant_id = p.tid
     and f.subject_type = 'product' and f.value_number is not null
    where s.data_type = 'number'
    group by s.key
  ), cue_bindings as (
    -- La pista amarra el número siguiente SÓLO si cae dentro del rango real
    -- del campo. Sin esto, «cubeta NAKASAWA 10561» amarraba el SKU como
    -- «diámetro de rosca de cubeta = 10561» —los reales rondan los 34,8 mm— y
    -- la búsqueda devolvía cero; el asistente terminaba buscando el producto
    -- en internet en vez de leer su propia bodega (2026-08-21).
    select distinct on (c.key) c.key, n.value, n.ordinality, t.ordinality cue_ord
    from numeric_cues c
    join tokens t on t.token = c.token
    join number_tokens n
      on n.ordinality > t.ordinality and n.ordinality <= t.ordinality + 4
    join numeric_field_range r on r.key = c.key
     and n.value between r.lo and r.hi
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
    -- Sólo se consumen las palabras que NOMBRAN un campo. Antes se consumía
    -- también cualquier palabra que apareciera en algún valor del vocabulario,
    -- aunque no llegara a ser filtro: «shimano» existe dentro del valor
    -- «Shimano HG» de un piñón, así que en «qué motores shimano tengo» la
    -- marca desaparecía en silencio y la respuesta traía todos los motores.
    -- Una palabra de valor que sí amarra ya viene consumida por `vocab_hits`.
    union select t.ordinality from tokens t
      where exists (select 1 from label_tokens l where l.token = t.token)
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
