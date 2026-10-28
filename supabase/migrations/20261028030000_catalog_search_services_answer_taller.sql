-- 20261028030000: «taller» finds the workshop's services.
--
-- After 20261028020000 a service search lists no product whose description
-- only mentions it, and «taller», «servicio» or «arreglo» alone found
-- nothing at all: no service is named that way. Every service now says those
-- words among its other names, so «taller» lists the services and «arreglo
-- frenos» the brake ones. Whether a product is a service is part of the
-- fingerprint, so a product turned into a service is rebuilt.

create or replace function public.catalog_search_source_md5_v1(p public.products)
returns text
language sql
stable
as $function$
  select pg_catalog.md5(pg_catalog.concat_ws(
    pg_catalog.chr(31),
    coalesce(p.website_name, ''),
    coalesce(p.name, ''),
    coalesce(p.sku, ''),
    coalesce(p.barcode, ''),
    coalesce(p.gtin, ''),
    coalesce(p.category_name, ''),
    coalesce(p.category, ''),
    coalesce(p.category_id::text, ''),
    coalesce(p.spec_template_id::text, ''),
    coalesce(p.brand, ''),
    coalesce(p.model, ''),
    coalesce(p.manufacturer, ''),
    coalesce(p.manufacturer_sku, ''),
    coalesce(p.website_description, ''),
    coalesce(p.description, ''),
    coalesce(p.product_type, ''),
    coalesce(p.is_service::text, '')
  ));
$function$;

alter function public.catalog_search_source_md5_v1(public.products) reset all;
revoke all on function public.catalog_search_source_md5_v1(public.products) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.catalog_search_documents_compute_internal_v1(p_tenant_id uuid, p_product_ids uuid[])
 RETURNS TABLE(product_id uuid, source_md5 text, name_n text, sku_n text, barcode_n text, gtin_n text, category_n text, brand_n text, model_n text, manufacturer_n text, manufacturer_sku_n text, description_n text, spec_n text, alias_head_n text, alias_type_n text, head_names text, type_names text, own_parts text[], alias_n text, measures text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with normalized as materialized (
    -- The product's texts as the search compares them.
    select
      p.id,
      public.catalog_search_source_md5_v1(p) as source_md5,
      public.catalog_search_text_v2(concat_ws(' ', p.website_name, p.name)) as name_n,
      public.catalog_search_text_v2(p.sku) as sku_n,
      public.catalog_search_text_v2(p.barcode) as barcode_n,
      public.catalog_search_text_v2(p.gtin) as gtin_n,
      public.catalog_search_text_v2(coalesce(p.category_name, p.category)) as category_n,
      public.catalog_search_text_v2(p.brand) as brand_n,
      public.catalog_search_text_v2(p.model) as model_n,
      public.catalog_search_text_v2(p.manufacturer) as manufacturer_n,
      public.catalog_search_text_v2(p.manufacturer_sku) as manufacturer_sku_n,
      public.catalog_search_text_v2(concat_ws(' ', p.website_description, p.description)) as description_n,
      (coalesce(p.product_type, 'product') = 'service' or coalesce(p.is_service, false)) as is_service_n
    from public.products p
    where p.tenant_id = p_tenant_id
      and p.id = any (p_product_ids)
  ),
  facet_values as materialized (
    -- The spec sheet as the store's filters show it, read once per document.
    select v.*
    from public.spec_public_facet_values_compute_internal_v1(p_tenant_id, p_product_ids) v
    where exists (select 1 from normalized)
  ),
  display_labels as materialized (
    -- An option's identity label may carry research codes («… 7v sólo según
    -- filas C-731»); the store shows its display_label (20261002100000), and
    -- so the search reads it.
    select distinct on (dv.label) dv.label, btrim(dv.display_label) as display_label
    from public.spec_definition_values dv
    where dv.display_label is not null
      and btrim(dv.display_label) <> ''
      and exists (select 1 from normalized)
    order by dv.label, dv.updated_at desc
  ),
  spec_text as (
    -- The spec sheet as the store shows it («Francesa (Presta)», «622»,
    -- «MTB»; a yes/no field by its name when it is «Sí», as «Tubeless
    -- Ready»), searchable as the name is. A cassette's count of sprockets is
    -- also its speeds («11v»).
    select
      v.product_id,
      public.catalog_search_text_v2(string_agg(
        case
          when v.data_type = 'boolean' and v.value_text = 'Sí' then v.spec_label
          when v.data_type = 'boolean' then null
          when v.spec_key = 'sprocket_count' then v.value_text || ' ' || v.value_text || 'v'
          else coalesce(dl.display_label, v.value_text)
        end,
        ' '
      )) as spec_n
    from facet_values v
    left join display_labels dl
      on v.data_type = 'single_select' and dl.label = v.value_text
    group by v.product_id
  ),
  product_measures as materialized (
    -- Every measure the product states: its spec sheet, and its name
    -- («7/8/9 velocidades», «3x5/6/7», «aro 26», «29 x 2.25», «36 rayos»).
    -- A search compares only the ones it asks for (measure_checks).
    select fv.product_id,
      case
        when fv.spec_key = 'bead_seat_diameter_mm' then 'bead'
        when fv.spec_key in ('sprocket_count', 'shifter_indexed_positions') then 'speeds'
        when fv.spec_key = 'spoke_hole_count' then 'holes'
        when fv.spec_key = 'rotor_diameter_mm_value' then 'rotor'
        else 'clamp'
      end as dim,
      case when fv.value_text ~ '^[0-9]+(\.[0-9]+)?$' then fv.value_text::numeric end as value
    from facet_values fv
    where fv.data_type = 'number'
      and fv.value_text ~ '^[0-9]+(\.[0-9]+)?$'
      and fv.spec_key in (
        'bead_seat_diameter_mm', 'sprocket_count', 'shifter_indexed_positions',
        'spoke_hole_count', 'rotor_diameter_mm_value', 'bar_clamp_diameter_mm',
        'handlebar_clamp_mm', 'seatpost_diameter_mm', 'seat_tube_outer_diameter_mm',
        'stem_steerer_clamp_diameter_mm', 'grip_bar_nominal_diameter_mm',
        'quill_diameter_mm'
      )
    union all
    select fv.product_id, 'drive',
      case
        when fv.value_text ilike '%cassette%' then 1
        when fv.value_text ilike '%rosca%' or fv.value_text ilike '%rueda libre%' then 2
        else 3
      end::numeric
    from facet_values fv
    where fv.spec_key = 'hub_drive_receiver_kind'
    union all
    -- The speeds a chain, a derailleur or a shifter is for (multi-select
    -- fields, not shown as filters).
    select f.subject_id, 'speeds',
      nullif(regexp_replace(dv.label, '[^0-9]', '', 'g'), '')::numeric
    from public.spec_facts f
    join public.spec_definitions d
      on d.id = f.spec_definition_id
     and d.key in ('drivetrain_speeds', 'chain_speeds')
    join public.spec_fact_values fv on fv.fact_id = f.id
    join public.spec_definition_values dv on dv.id = fv.value_id and dv.is_active
    where f.tenant_id = p_tenant_id
      and f.subject_type = 'product'
      and f.subject_scope is null
      and dv.label ~ '^[0-9]{1,2}$'
      and f.subject_id = any (p_product_ids)
    union all
    select n.id, 'speeds', nullif(x.v, '')::numeric
    from normalized n
    cross join lateral regexp_matches(
      n.name_n,
      '(?:^| )(?:[1-3]x)?((?:[0-9]{1,2} (?:y |o )?)*[0-9]{1,2}) ?(?:v|vel|vels|velocidad|velocidades|s|sp|speed|speeds)(?= |$)',
      'g'
    ) as m
    cross join lateral regexp_split_to_table(m[1], '[^0-9]+') as x(v)
    where nullif(x.v, '')::integer between 1 and 13
    union all
    -- «3x8», «1x12» without the word: the cassette's speeds (not a chain's
    -- width, «1/2x11/128»).
    select n.id, 'speeds', m[1]::numeric
    from normalized n
    cross join lateral regexp_matches(
      n.name_n,
      '(?:^| )(?<![0-9] )[1-3]x([0-9]{1,2})(?! 128)(?= |$)',
      'g'
    ) as m
    where m[1]::integer between 1 and 13
    union all
    select n.id, 'bead', public.catalog_search_bead_of_v1(coalesce(m[1], m[2], m[3]))
    from normalized n
    cross join lateral regexp_matches(
      n.name_n,
      '(?:^| )(?:(?:aro|rin|rodado) ([0-9]{2}(?:\.5)?|700|650b)(?![0-9.])|([0-9]{2}(?:\.5)?|700|650b) ?x ?[0-9]|(700c|650b|29er)(?![0-9a-z.]))',
      'g'
    ) as m
    where public.catalog_search_bead_of_v1(coalesce(m[1], m[2], m[3])) is not null
    union all
    select n.id, 'holes', m[1]::numeric
    from normalized n
    cross join lateral regexp_matches(
      n.name_n,
      '(?:^| )([0-9]{2}) ?(?:h|hoyos|agujeros|rayos|perforaciones)(?= |$)',
      'g'
    ) as m
  ),
  vocabulary as materialized (
    -- The workshop's words (catalog_search_terms): the shared ones and the
    -- store's own, by concept. A concept brings its terms, its broader
    -- words and the words of its phrases.
    select v.concept, v.kind, v.terms, v.broader, v.phrases
    from public.catalog_search_terms v
    where (v.tenant_id is null or v.tenant_id = p_tenant_id)
      and exists (select 1 from normalized)
  ),
  vocabulary_terms as materialized (
    select distinct v.concept, v.kind, term_parts.term
    from vocabulary v
    cross join lateral unnest(v.terms) as term_parts(term)
  ),
  vocabulary_phrases as materialized (
    select distinct v.concept, v.kind, phrase_parts.phrase
    from vocabulary v
    cross join lateral unnest(v.phrases) as phrase_parts(phrase)
  ),
  vocabulary_words as materialized (
    select distinct v.concept, word_parts.word
    from vocabulary v
    cross join lateral unnest(v.terms || v.broader) as word_parts(word)
    union
    -- A phrase brings its own words, but not one that names another part on
    -- its own, nor a joining word: «sin cámara» makes a rim tubeless, not a
    -- tube (2026-10-24, «camara fv» listed a tubeless rim and valve).
    select distinct v.concept, word_parts.word
    from vocabulary v
    cross join lateral unnest(
      string_to_array(nullif(array_to_string(v.phrases, ' '), ''), ' ')
    ) as word_parts(word)
    -- A side is the product's, never its group's: every derailleur said
    -- «delantero», and «cambio delantero» listed rear ones (2026-10-28).
    where word_parts.word <> all (array['de', 'del', 'la', 'el', 'los', 'las', 'para', 'sin', 'con', 'y',
      'trasero', 'trasera', 'traseros', 'traseras', 'delantero', 'delantera', 'delanteros',
      'delanteras', 'izquierdo', 'izquierda', 'derecho', 'derecha'])
      and not exists (
        select 1 from vocabulary_terms vt
        where vt.term = word_parts.word and vt.concept <> v.concept
      )
  ),
  product_words as materialized (
    -- Each product's words once, by where they are: the first word of its
    -- name (what it is), the rest of the name, its category and its spec
    -- sheet.
    select n.id as product_id, word_parts.word, case when word_parts.pos = 1 then 'head' else 'name' end as source
    from normalized n
    cross join lateral unnest(string_to_array(nullif(n.name_n, ''), ' ')) with ordinality as word_parts(word, pos)
    union all
    select n.id, word_parts.word, 'category'
    from normalized n
    cross join lateral unnest(string_to_array(nullif(n.category_n, ''), ' ')) as word_parts(word)
    union all
    select st.product_id, word_parts.word, 'spec'
    from spec_text st
    cross join lateral unnest(string_to_array(nullif(st.spec_n, ''), ' ')) as word_parts(word)
  ),
  concept_hits as materialized (
    -- The concepts each product says, ranked by where: 3 its name starts
    -- with the part («Motor sellado», «Disco de freno…»), 2 its category
    -- names it, 1 its name says it elsewhere or, for an attribute, its spec
    -- sheet does. A part is what the name and category say, never the spec
    -- sheet: a chain whose sheet says «derailleur» is not a derailleur.
    select h.product_id, h.concept, max(h.rank) as rank
    from (
      select pw.product_id, vt.concept,
        case
          when vt.kind = 'part' and pw.source = 'head' then 3
          when vt.kind = 'part' and pw.source = 'category' then 2
          else 1
        end as rank
      from product_words pw
      join vocabulary_terms vt on vt.term = pw.word
      where vt.kind = 'attribute' or pw.source <> 'spec'
      union all
      select n.id, vp.concept,
        case
          when vp.kind = 'part' and n.name_n like vp.phrase || '%' then 3
          when vp.kind = 'part' and (' ' || n.category_n || ' ') like '% ' || vp.phrase || ' %' then 2
          else 1
        end
      from normalized n
      left join spec_text st on st.product_id = n.id
      join vocabulary_phrases vp
        on (' ' || concat_ws(' ', n.name_n, n.category_n,
              case when vp.kind = 'attribute' then st.spec_n end) || ' ')
           like '% ' || vp.phrase || ' %'
    ) h
    group by h.product_id, h.concept
  ),
  vocabulary_names as materialized (
    -- What names a concept on its own: each term and each phrase.
    select vt.concept, vt.term as name from vocabulary_terms vt
    union
    select vp.concept, vp.phrase from vocabulary_phrases vp
  ),
  product_names as materialized (
    -- The names of what each product is, so a search that is exactly one
    -- of them («pata de cambio», «motor») puts those products first.
    select ch.product_id,
      '|' || string_agg(distinct vn.name, '|') filter (where ch.rank = 3) || '|' as head_names,
      '|' || string_agg(distinct vn.name, '|') filter (where ch.rank = 2) || '|' as type_names
    from concept_hits ch
    join vocabulary_names vn on vn.concept = ch.concept
    where ch.rank >= 2
    group by ch.product_id
  ),
  product_aliases as materialized (
    select ch.product_id,
      string_agg(distinct vw.word, ' ') filter (where ch.rank = 3) as head_n,
      string_agg(distinct vw.word, ' ') filter (where ch.rank = 2) as type_n,
      string_agg(distinct vw.word, ' ') as words_n
    from concept_hits ch
    join vocabulary_words vw on vw.concept = ch.concept
    group by ch.product_id
  ),
  product_parts as materialized (
    -- What each product is: the parts its name starts with, else the ones
    -- its category names. A search that names a part reads it.
    select ch.product_id,
      coalesce(
        array_agg(ch.concept) filter (where ch.rank = 3),
        array_agg(ch.concept) filter (where ch.rank = 2)
      ) as own
    from concept_hits ch
    where ch.rank >= 2
    group by ch.product_id
  )
  select
    n.id,
    n.source_md5,
    n.name_n,
    n.sku_n,
    n.barcode_n,
    n.gtin_n,
    n.category_n,
    n.brand_n,
    n.model_n,
    n.manufacturer_n,
    n.manufacturer_sku_n,
    n.description_n,
    coalesce(st.spec_n, '') as spec_n,
    coalesce(pa.head_n, '') as alias_head_n,
    coalesce(pa.type_n, '') as alias_type_n,
    coalesce(pn.head_names, '') as head_names,
    coalesce(pn.type_names, '') as type_names,
    pp.own as own_parts,
      trim(concat_ws(
        ' ',
        -- Every concept the product says: «francesa» brings «presta» and
        -- «fv»; «Postiza» brings «pata de cambio».
        pa.words_n,
        -- Speeds as a visitor writes them: «11 velocidades», «11s», «1x11»
        -- (not a chain's width, «1/2x11/128»).
        (
          select string_agg(distinct coalesce(m[1], m[2]) || 'v', ' ')
          from regexp_matches(
            n.name_n,
            '(?:^| )(?:([0-9]{1,2}) ?(?:v|vel|vels|velocidad|velocidades|s|sp|spd|speed|speeds)|(?<![0-9] )[1-3]x([0-9]{1,2})(?! 128))(?= |$)',
            'g'
          ) as m
        ),
        -- 27.5 is 650b, and the «27» a visitor types on the way to it
        -- (20261028010000); the 700 is the 28 some write.
        case
          when concat_ws(' ', n.name_n, st.spec_n) ~ '(^| )(27\.5|27 5|650 ?b|275|584)( |$)'
            then '650b 275 27.5 27'
        end,
        case when n.name_n ~ '(^| )700( |$)' then '28 700c' end,
        -- Every service is the workshop's: «taller», «servicio», «arreglo»
        -- find them (20261028030000).
        case when n.is_service_n
          then 'servicio servicios taller arreglo arreglos reparacion reparaciones' end
      )) as alias_n,
    array(
      select distinct pm.dim || ':' || pm.value::text
      from product_measures pm
      where pm.product_id = n.id
        and pm.value is not null
      order by 1
    ) as measures
  from normalized n
  left join spec_text st on st.product_id = n.id
  left join product_aliases pa on pa.product_id = n.id
  left join product_names pn on pn.product_id = n.id
  left join product_parts pp on pp.product_id = n.id;
$function$;

-- Every document, rebuilt with the new fingerprint and aliases.
delete from public.catalog_search_documents;
select public.catalog_search_documents_refresh_v1();
