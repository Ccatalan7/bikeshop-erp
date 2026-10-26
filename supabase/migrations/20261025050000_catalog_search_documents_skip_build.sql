-- 20261025050000: a search with every document built does not call the
-- function that builds one.
--
-- 20261025040000 brought a search for «cadena» from 585 ms to 234 ms in
-- production. Profiled the same evening, 154 ms of what was left was the call
-- to catalog_search_documents_compute_internal_v1 with no product to build:
-- a SQL function is planned on every call, and that one is ~300 lines. The
-- search now asks it only for the products whose document is missing or
-- stale (`missing`). Finding those was itself an anti join of two CTEs that
-- ran as a nested loop (148 ms): each product now looks its document up by
-- key (`lookup`). The results are the same (catalog_search_documents.sql and
-- the equivalence blocks of catalog_search_vocabulary.sql and
-- catalog_search_measures.sql).

CREATE OR REPLACE FUNCTION public.get_public_products_without_inventory_reservations(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_sku text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      coalesce(t.required_tokens, array[]::text[]) as required_tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type,
      -- The outer reservation-aware wrapper is the sole stock-policy owner.
      'all'::text as stock_policy,
      -- La regla única de venta online (catalog_product_web_block_v1) lee
      -- los ajustes del sitio una vez por consulta.
      public.catalog_web_policy_v1(p_tenant_id) as policy
    from (
      select public.catalog_search_query_v2(p_search_term) as term
    ) s
    cross join lateral (
      -- A word that only joins others («de», «para») asks nothing; one that
      -- names the bicycle, the wheel or a unit («bicicleta», «aro», «mm»,
      -- «hoyos») counts when the product has it but is not required:
      -- «cámara para bicicleta aro 29» is a 29 tube, whose name says neither
      -- (2026-10-24).
      select
        coalesce(
          array_agg(w.token order by w.n) filter (where not w.stop),
          array_agg(w.token order by w.n)
        ) as tokens,
        coalesce(
          array_agg(w.token order by w.n) filter (where not w.stop and not w.soft),
          array_agg(w.token order by w.n) filter (where not w.stop),
          array_agg(w.token order by w.n)
        ) as required_tokens
      from (
        select
          token_parts.token,
          token_parts.n,
          token_parts.token = any (array[
            'de', 'del', 'la', 'las', 'el', 'los', 'lo', 'para', 'con', 'y',
            'e', 'o', 'u', 'en', 'un', 'una', 'unos', 'unas', 'por', 'al', 'a',
            'mi', 'su', 'que'
          ]) as stop,
          token_parts.token = any (array[
            'bici', 'bicis', 'bicicleta', 'bicicletas', 'bike', 'bikes', 'aro',
            'aros', 'rin', 'rines', 'rodado', 'medida', 'tipo', 'mm', 'cm',
            'pulgada', 'pulgadas', 'hoyos', 'agujeros', 'perforaciones',
            'dientes'
          ])
          -- A tyre's width next to its wheel («27.5 2.1»): the wheel decides,
          -- the width orders. A 27.5 x 2.25 is what the workshop offers when
          -- there is no 2.1.
          or (
            token_parts.token ~ '^[1-3]\.[0-9]{1,3}$'
            and exists (
              select 1
              from regexp_split_to_table(s.term, '\s+') as wheel(token)
              where public.catalog_search_bead_of_v1(wheel.token) is not null
            )
          ) as soft
        from regexp_split_to_table(s.term, '\s+') with ordinality as token_parts(token, n)
        where token_parts.token <> ''
      ) w
    ) t
  ),
  query_measures as materialized (
    -- The measures the visitor asks for: «7v» speeds, a wheel size («20»,
    -- «27.5», «700») as its bead seat, «32 hoyos» or «36h» spoke holes, a
    -- clamp («31.8», «27.2») and a rotor («180»). A number that is no
    -- measure of a product asks nothing of it (below).
    select distinct m.dim, m.value
    from args a
    cross join lateral (
      select w.token, lead(w.token) over (order by w.n) as next_token
      from unnest(a.tokens) with ordinality as w(token, n)
    ) t
    cross join lateral (
      select 'speeds'::text as dim, (regexp_match(t.token, '^([0-9]{1,2})v$'))[1]::numeric as value
      union all
      select 'bead', public.catalog_search_bead_of_v1(t.token)
      union all
      select 'holes',
        case when t.token ~ '^[0-9]{2}h$'
               or (t.token ~ '^[0-9]{2}$'
                   and t.next_token in ('hoyos', 'agujeros', 'perforaciones', 'rayos', 'h'))
          then (regexp_match(t.token, '^([0-9]{2})'))[1]::numeric end
      union all
      select 'clamp',
        case when t.token in ('22.2', '25.4', '26', '27.2', '28.6', '30.9', '31.6', '31.8', '34.9', '35')
          then t.token::numeric end
      union all
      select 'rotor',
        case when t.token in ('140', '160', '180', '200', '203', '220')
          then t.token::numeric end
      union all
      -- What a hub takes: a cassette (1) or a threaded freewheel (2). Only a
      -- hub or wheel states it (hub_drive_receiver_kind).
      select 'drive',
        case
          when t.token in ('cassette', 'cassettes', 'casete', 'cassete', 'casette', 'nucleo') then 1
          when t.token in ('rosca', 'hilo', 'freewheel') then 2
        end::numeric
    ) m
    where a.term <> ''
      and m.value is not null
      and m.value > 0
      and (m.dim <> 'speeds' or m.value between 1 and 13)
  ),
  eligible as (
    -- What may be listed. The texts a search compares are its document
    -- (catalog_search_documents, 20261025040000), checked against the
    -- fingerprint of the product as it is now.
    select
      p.*,
      a.term,
      a.tokens,
      a.required_tokens,
      a.page_limit,
      a.page_offset,
      a.sort_by,
      (
        a.term ~ '(^| )(servicio|servicios|mantencion|mantenciones|reparacion|reparaciones|ajuste|ajustes|instalacion|instalaciones|limpieza|lavado|engrase|sangrado|purga|centrado|enrayado|diagnostico|revision)( |$)'
      ) as service_intent,
      public.catalog_search_source_md5_v1(p) as search_source_md5
    from public.products p
    cross join args a
    where p.tenant_id = p_tenant_id
      and p.is_active = true
      and coalesce(p.is_published, false) = true
      and coalesce(p.show_on_website, false) = true
      and (
        p_product_ids is null
        or cardinality(p_product_ids) = 0
        or p.id = any(p_product_ids)
      )
      and (
        p_category_ids is null
        or cardinality(p_category_ids) = 0
        or p.category_id = any(p_category_ids)
      )
      and (
        a.wanted_sku is null
        or lower(p.sku) = lower(a.wanted_sku)
      )
      and (
        a.wanted_product_type is null
        or p.product_type = a.wanted_product_type
      )
      -- Consumible, precio, costo, foto, nombre, categoría: lo decide la
      -- regla única, la misma que usan la ficha, el checkout y el ERP.
      and public.catalog_product_web_block_v1(p, a.policy) is null
      and (
        a.stock_policy = 'all'
        or coalesce(p.is_service, false)
        or p.product_type = 'service'
        or (
          a.stock_policy = 'available_only'
          and (
            coalesce(p.track_stock, true) = false
            or coalesce(p.stock_quantity, p.inventory_qty, 0) > 0
          )
        )
        or (
          a.stock_policy = 'out_of_stock_only'
          and coalesce(p.track_stock, true) = true
          and coalesce(p.stock_quantity, p.inventory_qty, 0) <= 0
        )
      )
  ),
  lookup as materialized (
    -- Each product's document, by its key, when it was built from the
    -- product as it is now.
    select e.id, d.product_id as built,
      d.name_n, d.sku_n, d.barcode_n, d.gtin_n, d.category_n, d.brand_n,
      d.model_n, d.manufacturer_n, d.manufacturer_sku_n, d.description_n,
      d.spec_n, d.alias_head_n, d.alias_type_n, d.head_names, d.type_names,
      d.own_parts, d.alias_n, d.measures
    from eligible e
    left join public.catalog_search_documents d
      on d.tenant_id = p_tenant_id
     and d.product_id = e.id
     and d.version = 1
     and d.source_md5 = e.search_source_md5
    where e.term <> ''
  ),
  missing as materialized (
    -- The ones not built yet, or built before the product changed. (An anti
    -- join of two CTEs here ran as a nested loop: 700 thousand comparisons,
    -- 148 ms.)
    select coalesce(array_agg(l.id), '{}'::uuid[]) as ids
    from lookup l
    where l.built is null
  ),
  computed as materialized (
    -- Computed here, as before 20261025040000, the same way the refresh
    -- builds them. Only when one is missing: calling the function at all
    -- costs ~150 ms (a SQL function is planned on every call), which was
    -- most of a search with every document built.
    select c.*
    from missing m
    cross join lateral public.catalog_search_documents_compute_internal_v1(
      p_tenant_id, m.ids
    ) c
    where cardinality(m.ids) > 0
  ),
  docs as materialized (
    select id as product_id, name_n, sku_n, barcode_n, gtin_n, category_n,
      brand_n, model_n, manufacturer_n, manufacturer_sku_n, description_n,
      spec_n, alias_head_n, alias_type_n, head_names, type_names, own_parts,
      alias_n, measures
    from lookup
    where built is not null
    union all
    select product_id, name_n, sku_n, barcode_n, gtin_n, category_n, brand_n,
      model_n, manufacturer_n, manufacturer_sku_n, description_n, spec_n,
      alias_head_n, alias_type_n, head_names, type_names, own_parts, alias_n,
      measures
    from computed
  ),
  normalized as (
    -- Without a term every product passes with empty texts, and the order
    -- reads the raw name, price and date (nor are they scored, below).
    select
      e.*,
      coalesce(d.name_n, '') as name_n,
      coalesce(d.sku_n, '') as sku_n,
      coalesce(d.barcode_n, '') as barcode_n,
      coalesce(d.gtin_n, '') as gtin_n,
      coalesce(d.category_n, '') as category_n,
      coalesce(d.brand_n, '') as brand_n,
      coalesce(d.model_n, '') as model_n,
      coalesce(d.manufacturer_n, '') as manufacturer_n,
      coalesce(d.manufacturer_sku_n, '') as manufacturer_sku_n,
      coalesce(d.description_n, '') as description_n,
      coalesce(d.spec_n, '') as spec_n,
      coalesce(d.alias_head_n, '') as alias_head_n,
      coalesce(d.alias_type_n, '') as alias_type_n,
      coalesce(d.head_names, '') as head_names,
      coalesce(d.type_names, '') as type_names,
      d.own_parts,
      coalesce(d.alias_n, '') as alias_n,
      coalesce(d.measures, '{}'::text[]) as measures
    from eligible e
    left join docs d on d.product_id = e.id
  ),
  product_measures as materialized (
    -- What each product states of the measures asked, from its document.
    select n.id as product_id,
      split_part(m.measure, ':', 1) as dim,
      split_part(m.measure, ':', 2)::numeric as value
    from normalized n
    cross join lateral unnest(n.measures) as m(measure)
    where exists (select 1 from query_measures)
  ),
  measure_checks as materialized (
    -- Per product and measure asked: does it state the value asked?
    select pm.product_id,
      array_agg(distinct qm.dim) filter (where pm.value = qm.value) as confirms,
      array_agg(distinct qm.dim) as states
    from product_measures pm
    join query_measures qm on qm.dim = pm.dim
    where pm.value is not null
    group by pm.product_id
  ),
  vocabulary as materialized (
    -- The workshop's words (catalog_search_terms): the shared ones and the
    -- store's own, by concept. A concept brings its terms, its broader
    -- words and the words of its phrases.
    select v.concept, v.kind, v.terms, v.broader, v.phrases
    from public.catalog_search_terms v
    where (v.tenant_id is null or v.tenant_id = p_tenant_id)
      and (select a.term from args a) <> ''
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
  query_parts as materialized (
    -- The parts the visitor names, by the position of their first word:
    -- «maza trasera cassette» asks for a hub, «cable de freno» for a cable.
    select vt.concept, w.n as pos, false as is_phrase
    from args a
    cross join lateral regexp_split_to_table(a.term, ' ') with ordinality as w(token, n)
    join vocabulary_terms vt on vt.kind = 'part' and vt.term = w.token
    where a.term <> ''
    union all
    select vp.concept,
      case
        when btrim(split_part(' ' || a.term || ' ', ' ' || vp.phrase || ' ', 1)) = '' then 1
        else cardinality(string_to_array(
          btrim(split_part(' ' || a.term || ' ', ' ' || vp.phrase || ' ', 1)), ' '
        )) + 1
      end,
      true
    from args a
    join vocabulary_phrases vp
      on vp.kind = 'part'
     and strpos(' ' || a.term || ' ', ' ' || vp.phrase || ' ') > 0
    where a.term <> ''
  ),
  primary_part as materialized (
    -- The first part named; its terms are the shared ones and the store's.
    select qp.concept,
      array(
        select distinct term_parts.term
        from vocabulary v
        cross join lateral unnest(v.terms) as term_parts(term)
        where v.concept = qp.concept
      ) as terms
    from query_parts qp
    order by qp.pos, qp.is_phrase desc, qp.concept
    limit 1
  ),
  enriched as (
    select
      -- n carries the document: what the product is (the part its name
      -- starts with, and next the part its category names), its aliases
      -- and its spec text.
      n.*,
      coalesce(mc.confirms, '{}'::text[]) as measures_confirmed,
      coalesce(mc.states, '{}'::text[]) as measures_stated,
      prim.concept as asked_part,
      coalesce(prim.concept = any (n.own_parts), false) as is_asked_part,
      (
        prim.concept is not null
        and (
          -- It belongs to the part asked: pads to a brake, a quick link to
          -- a chain.
          exists (
            select 1 from vocabulary v
            where v.concept = any (n.own_parts)
              and v.broader && prim.terms
          )
          -- It is a tool, a consumable or a small part for the part asked:
          -- «Llave para motor sellado», «Lubricante de cadena», «Espaciador
          -- de cassette». A hub «para piñón con hilo» or a fork «para
          -- disco» is a hub and a fork.
          or (
            n.own_parts && array[
              'herramienta', 'llave', 'desmontador', 'lubricante', 'grasa',
              'desengrasante', 'liquido_freno', 'adaptador', 'espaciador',
              'parche', 'cubrecadena', 'rodamiento', 'eje', 'cono', 'niple',
              'abrazadera', 'funda', 'cinta_llanta'
            ]
            and n.name_n ~ (
              '(^| )(para|de|del) (la |el |los |las )?(' || array_to_string(prim.terms, '|') || ')( |$)'
            )
          )
        )
      ) as is_for_asked_part
    from normalized n
    left join measure_checks mc on mc.product_id = n.id
    left join primary_part prim on true
  ),
  matched as (
    select
      e.*,
      (
        case when e.term <> '' and e.sku_n = e.term then 1000 else 0 end +
        case when e.term <> '' and e.barcode_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.gtin_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.name_n = e.term then 850 else 0 end +
        case when e.term <> '' and e.name_n like e.term || '%' then 760 else 0 end +
        case when e.term <> '' and e.name_n like '%' || e.term || '%' then 650 else 0 end +
        case when e.term <> '' and e.head_names like '%|' || e.term || '|%' then 700 else 0 end +
        case when e.term <> '' and e.type_names like '%|' || e.term || '|%' then 600 else 0 end +
        case when e.term <> '' and e.category_n = e.term then 620 else 0 end +
        case when e.term <> '' and e.category_n like '%' || e.term || '%' then 560 else 0 end +
        case when e.term <> '' and e.alias_n like '%' || e.term || '%' then 500 else 0 end +
        case when e.term <> '' and e.sku_n like '%' || e.term || '%' then 460 else 0 end +
        case when e.term <> '' and e.manufacturer_sku_n like '%' || e.term || '%' then 420 else 0 end +
        case when e.term <> '' and e.brand_n like '%' || e.term || '%' then 360 else 0 end +
        case when e.term <> '' and e.model_n like '%' || e.term || '%' then 320 else 0 end +
        case when e.term <> '' and e.manufacturer_n like '%' || e.term || '%' then 300 else 0 end +
        case when e.term <> '' and e.spec_n like '%' || e.term || '%' then 280 else 0 end
      ) as phrase_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            -- A speed is the product's when its sheet or name says it; never
            -- from free text (an option note, a description).
            -- The name saying it first: a rear 7-speed shifter before a front
            -- one whose sheet says it is for 7-speed drivetrains.
            when tp.is_speed and (' ' || e.alias_n || ' ') like '% ' || tp.token || ' %' then 100
            when tp.is_speed and 'speeds' = any (e.measures_confirmed) then 60
            when tp.is_speed then 0
            when tp.is_number and e.sku_n = tp.token then 120
            when tp.is_number and e.barcode_n = tp.token then 120
            when tp.is_number and e.gtin_n = tp.token then 120
            when tp.is_number and e.name_n ~ tp.number then 70
            when tp.is_number and e.category_n ~ tp.number then 58
            when tp.is_number and e.alias_n ~ tp.number then 52
            when tp.is_number and e.spec_n ~ tp.number then 40
            when tp.is_number then 0
            when e.name_n like tp.token || '%' then 95
            when (' ' || e.alias_head_n) like tp.pat then 92
            when (' ' || e.alias_type_n) like tp.pat then 80
            when (' ' || e.name_n) like tp.pat then 76
            when (' ' || e.category_n) like tp.pat then 66
            when (' ' || e.alias_n) like tp.pat then 56
            when (' ' || e.sku_n) like tp.pat then 54
            when (' ' || e.manufacturer_sku_n) like tp.pat then 48
            when (' ' || e.spec_n) like tp.pat then 44
            when (' ' || e.brand_n) like tp.pat then 42
            when (' ' || e.model_n) like tp.pat then 38
            when (' ' || e.manufacturer_n) like tp.pat then 34
            when length(tp.token) >= 4 and greatest(
              word_similarity(tp.token, e.name_n),
              word_similarity(tp.token, e.category_n),
              word_similarity(tp.token, e.brand_n),
              word_similarity(tp.token, e.model_n),
              word_similarity(tp.token, e.manufacturer_n),
              word_similarity(tp.token, e.alias_n)
            ) >= case when length(tp.token) >= 5 then 0.56 else 0.72 end then 28
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        cross join lateral (
          select
            token_parts.token,
            token_parts.token ~ '^[0-9]{1,2}v$' as is_speed,
            token_parts.token ~ '^[0-9]+(\.[0-9]+)?$' as is_number,
            '(^|[^0-9.])' || replace(token_parts.token, '.', '\.') || '([^0-9.]|$)' as number,
            -- One or two letters start a word («fv», «av», «ca» while
            -- typing); a longer word may sit inside one («caramagiola» in
            -- «portacaramagiola»).
            case when length(token_parts.token) <= 2
              then '% ' || token_parts.token || '%'
              else '%' || token_parts.token || '%'
            end as pat
        ) tp
        where token_parts.token <> ''
      ), 0) end as token_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when tp.is_speed then 0
            when tp.is_number and e.description_n ~ tp.number then 8
            when not tp.is_number and (' ' || e.description_n) like tp.pat then 8
            when not tp.is_number and length(tp.token) >= 5 and word_similarity(tp.token, e.description_n) >= 0.86 then 5
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        cross join lateral (
          select
            token_parts.token,
            token_parts.token ~ '^[0-9]{1,2}v$' as is_speed,
            token_parts.token ~ '^[0-9]+(\.[0-9]+)?$' as is_number,
            '(^|[^0-9.])' || replace(token_parts.token, '.', '\.') || '([^0-9.]|$)' as number,
            case when length(token_parts.token) <= 2
              then '% ' || token_parts.token || '%'
              else '%' || token_parts.token || '%'
            end as pat
        ) tp
        where token_parts.token <> ''
      ), 0) end as weak_description_score
    from enriched e
    where e.term = ''
      or (
        -- A measure the product states with another value: out
        -- («cassette 7v» and an 8-speed cassette, «camara 20» and a 26
        -- tube).
        not (e.measures_stated && array(
          select unnest(e.measures_stated)
          except
          select unnest(e.measures_confirmed)
        ))
        -- A wheel size asked is said by the part itself, or confirmed: a
        -- patch kit «20 unidades» is not for a 20 tube, a truing stand is
        -- not a 29 wheel.
        and (
          not exists (select 1 from query_measures qm where qm.dim = 'bead')
          or 'bead' = any (e.measures_confirmed)
          or e.is_asked_part
        )
        -- A product that is another part than the one asked: out, unless
        -- it belongs to it or is for it. Services keep their own rule
        -- (below).
        and (
          e.asked_part is null
          or e.own_parts is null
          or e.is_asked_part
          or e.is_for_asked_part
          or e.product_type = 'service'
          or coalesce(e.is_service, false)
        )
        and not exists (
          select 1
          from unnest(e.required_tokens) as token_parts(token)
          cross join lateral (
            select
              token_parts.token,
              token_parts.token ~ '^[0-9]{1,2}v$' as is_speed,
              token_parts.token ~ '^[0-9]+(\.[0-9]+)?$' as is_number,
              '(^|[^0-9.])' || replace(token_parts.token, '.', '\.') || '([^0-9.]|$)' as number,
              case when length(token_parts.token) <= 2
                then '% ' || token_parts.token || '%'
                else '%' || token_parts.token || '%'
              end as pat
          ) tp
          where token_parts.token <> ''
            and not (
              (
                tp.is_speed
                and (
                  'speeds' = any (e.measures_confirmed)
                  or (' ' || e.alias_n || ' ') like '% ' || tp.token || ' %'
                  or (' ' || e.name_n || ' ') like '% ' || tp.token || ' %'
                  or (' ' || e.sku_n || ' ') like '% ' || tp.token || ' %'
                  or (' ' || e.model_n || ' ') like '% ' || tp.token || ' %'
                )
              )
              or (
                tp.is_number
                and (
                  e.sku_n = tp.token
                  or e.barcode_n = tp.token
                  or e.gtin_n = tp.token
                  or e.name_n ~ tp.number
                  or e.category_n ~ tp.number
                  or e.alias_n ~ tp.number
                  or e.spec_n ~ tp.number
                  or e.description_n ~ tp.number
                )
              )
              or (
                not tp.is_number
                and not tp.is_speed
                and (
                  (' ' || e.name_n) like tp.pat
                  or (' ' || e.category_n) like tp.pat
                  or (' ' || e.alias_n) like tp.pat
                  or (' ' || e.sku_n) like tp.pat
                  or (' ' || e.barcode_n) like tp.pat
                  or (' ' || e.gtin_n) like tp.pat
                  or (' ' || e.brand_n) like tp.pat
                  or (' ' || e.model_n) like tp.pat
                  or (' ' || e.manufacturer_n) like tp.pat
                  or (' ' || e.manufacturer_sku_n) like tp.pat
                  or (' ' || e.spec_n) like tp.pat
                  or (' ' || e.description_n) like tp.pat
                  or (
                    length(tp.token) >= 4
                    and greatest(
                      word_similarity(tp.token, e.name_n),
                      word_similarity(tp.token, e.category_n),
                      word_similarity(tp.token, e.brand_n),
                      word_similarity(tp.token, e.model_n),
                      word_similarity(tp.token, e.manufacturer_n),
                      word_similarity(tp.token, e.alias_n)
                    ) >= case when length(tp.token) >= 5 then 0.56 else 0.72 end
                  )
                  or (
                    length(tp.token) >= 5
                    and word_similarity(tp.token, e.description_n) >= 0.86
                  )
                )
              )
            )
        )
      )
  ),
  scored as (
    select
      m.*,
      (m.phrase_strong_score + m.token_strong_score) as strong_score,
      (
        m.phrase_strong_score +
        m.token_strong_score +
        m.weak_description_score +
        -- The part asked before what belongs to it or is for it.
        case when m.is_asked_part then 240 else 0 end +
        -- What states the measure asked before what does not say it.
        case when cardinality(m.measures_confirmed) > 0 then 120 else 0 end +
        -- The brand written: «desviador shimano» lists Shimano's first, then
        -- what only says it fits Shimano.
        case when m.brand_n <> ''
              and (' ' || m.term || ' ') like '% ' || m.brand_n || ' %'
          then 150 else 0 end +
        -- «shifter 7v», «desviador 8v» ask for the rear one: a front shifter
        -- or derailleur «3x7» comes after it, unless the visitor asks for
        -- the front.
        case when m.name_n ~ '(^| )(delanter[oa]s?|izquierd[oa]s?)( |$)'
              and m.term !~ '(delanter|izquierd)'
              and exists (
                select 1 from query_measures qm
                where qm.dim = 'speeds' and qm.value >= 4
              )
          then -150 else 0 end +
        case when m.product_type = 'service' and not m.service_intent
          then -260 else 0 end
      ) as search_score
    from matched m
  ),
  ranked as (
    select s.*
    from scored s
    where s.term = ''
      or s.product_type <> 'service'
      or s.service_intent
      or s.strong_score > 0
      or not exists (
        select 1
        from scored product_match
        where product_match.product_type <> 'service'
          and product_match.strong_score > 0
      )
  ),
  counted as (
    select p.*, count(*) over() as row_total
    from ranked p
  )
  select
    p.id,
    p.tenant_id,
    coalesce(nullif(btrim(p.website_name), ''), p.name) as name,
    p.sku,
    p.barcode,
    coalesce(p.website_price, p.price) as price,
    0::numeric as cost,
    p.inventory_qty,
    p.stock_quantity,
    coalesce(nullif(btrim(p.website_image_url), ''), p.image_url) as image_url,
    coalesce(nullif(btrim(p.website_image_url_optimized), ''), p.image_url_optimized) as image_url_optimized,
    case
      when cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        then p.website_image_urls
      else p.image_urls
    end as image_urls,
    p.description,
    p.website_description,
    p.category,
    p.category_id,
    p.category_name,
    p.brand_id,
    p.brand,
    p.model,
    p.manufacturer,
    p.manufacturer_sku,
    p.gtin,
    p.product_type,
    p.track_stock,
    p.is_active,
    p.is_published,
    p.show_on_website,
    p.created_at,
    p.updated_at,
    p.row_total as total_count
  from counted p
  order by
    case when p.term <> '' then p.search_score end desc nulls last,
    case when p.term = '' and p.sort_by = 'price_asc'
      then coalesce(p.website_price, p.price) end asc nulls last,
    case when p.term = '' and p.sort_by = 'price_desc'
      then coalesce(p.website_price, p.price) end desc nulls last,
    case when p.term = '' and p.sort_by = 'newest'
      then p.created_at end desc nulls last,
    coalesce(nullif(btrim(p.website_name), ''), p.name) asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$function$;
