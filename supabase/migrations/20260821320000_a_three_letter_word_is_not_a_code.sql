-- «motores de caja BSA con ancho de caja 68 y largo de eje 118» traducía bien
-- los tres filtros y aun así devolvía cero: la palabra «con» sobrevivía como
-- texto libre, y el filtro de texto exige que cada palabra esté en el nombre
-- del producto. Ningún motor se llama «con».

create or replace function public.assistant_infer_technical_predicates_internal_v1(
  p_tenant_id uuid,
  p_query text
) returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  with params as (
    select p_tenant_id as tid, coalesce(p_query, '') as q
  ), scoped as (
    select distinct on (d.key) d.id, d.key, d.label, d.data_type
    from public.spec_definitions d
    cross join params p
    where d.is_filterable is true
      and (d.tenant_id is null or d.tenant_id = p.tid)
      and d.data_type in ('number', 'single_select', 'multi_select', 'text')
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
    select s.key, v.label, vt.token
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
  ), vocab_unique as (
    select token, min(key) key, min(label) label
    from vocab_tokens
    group by token
    having count(distinct key || '|' || label) = 1
  ), vocab_hits as (
    select distinct u.key, u.label, t.ordinality
    from vocab_unique u
    join tokens t on t.token = u.token
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
    select token::numeric value, ordinality
    from tokens
    where token ~ '^[0-9]+([.][0-9]+)?$'
  ), cue_bindings as (
    select distinct on (c.key) c.key, n.value, n.ordinality, t.ordinality cue_ord
    from numeric_cues c
    join tokens t on t.token = c.token
    join number_tokens n
      on n.ordinality > t.ordinality and n.ordinality <= t.ordinality + 4
    order by c.key, n.ordinality
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
    group by n.ordinality, n.value
    having count(distinct s.key) = 1
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
  ), bounded_predicates as (
    select * from predicates order by ordinality limit 8
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
    'predicates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'field', key, 'operator', operator, 'values', values
      ) order by ordinality)
      from bounded_predicates
    ), '[]'::jsonb),
    'residual', coalesce((
      select string_agg(token, ' ' order by ordinality) from residual_tokens
    ), '')
  );
$function$;

;
