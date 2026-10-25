-- 20261025010000: a measure the visitor writes decides, and a search for a
-- part finds that part.
--
-- 2026-10-24, owner, on the header's box: «dude, the search engine it's still
-- garbage». «cassette 7v» listed two 7-speed freewheels and then 8- and
-- 9-speed cassettes and two cassette spacers. A battery of 45 searches the
-- workshop gets showed it was not one case:
--   * a measure only had to be written somewhere: the Shimano HG spline
--     option's identity label says «… ROAD 11v y 7v sólo según filas C-731»,
--     so every HG cassette and spacer «said» 7v; «cassette 11v» listed 8- and
--     9-speed ones;
--   * decimals were split: «1.50-2.20» was «1 50 2 20», so «camara 20» found
--     26 and 27.5 tubes (and a patch kit), and «180mm» did not find «180 mm»;
--   * a product that only mentions the part was listed as the part:
--     «manubrio 31.8» listed stems, «rayos 26» rims with 36 spokes,
--     «pastillas shimano» shift levers, «cassette 8v» a hub and a derailleur,
--     «cadena 12v» a chain tool and a derailleur;
--   * «desviador shimano 8v» put a Sensah first because its text says
--     «compatible con Shimano».
--
-- What changes, in the one search every public read shares
-- (get_public_products_without_inventory_reservations):
--   1. Measures decide (docs/architecture/product-identity-matching-contract.md,
--      «Medida excluyente»): speeds, wheel size (as the ISO bead seat), spoke
--      holes, clamp diameter and rotor diameter are read from the spec sheet
--      (sprocket_count, drivetrain_speeds, chain_speeds, bead_seat_diameter_mm…)
--      and from the name («7/8/9 velocidades», «aro 26», «29 x 2.25»,
--      «36 rayos»). A product that states a measure the visitor asked for with
--      another value is out; one that does not state it is not judged by it.
--      A speed is never found in free spec or description text.
--   2. The search's own text keeps decimals («2.20», «27.5», «31.8») and reads
--      «180mm» as «180 mm» (catalog_search_query_v2, catalog_search_text_v2).
--      catalog_search_normalize_v1 is unchanged: vocabulary words and the
--      misses' keys keep comparing as before.
--   3. A search that names a part (the first part word, as the vocabulary
--      says it) finds that part: a product that is another part is out unless
--      it belongs to the asked one (pads for «freno», a quick link for
--      «cadena») or is for it («Llave para motor sellado»).
--   4. The spec sheet is read as the store shows it (display_label), not the
--      option's identity label with its research codes.
--   5. The brand the visitor writes ranks its products first.
--   6. «disco» names the rotor, as the workshop says it («disco 180»).

-- A wheel size as its ISO bead seat (docs/wiki/compatibilidad: the number is
-- the rim's bead seat, never a model).
create or replace function public.catalog_search_bead_of_v1(p_size text)
returns numeric
language sql
immutable
parallel safe
set search_path to 'public'
as $function$
  select case p_size
    when '12' then 203
    when '14' then 254
    when '16' then 305
    when '18' then 355
    when '20' then 406
    when '22' then 457
    when '24' then 507
    when '26' then 559
    when '27.5' then 584
    when '275' then 584
    when '650b' then 584
    when '28' then 622
    when '29' then 622
    when '29er' then 622
    when '700' then 622
    when '700c' then 622
  end::numeric
$function$;

revoke all on function public.catalog_search_bead_of_v1(text) from public, anon, authenticated;

-- A product's text as the search compares it: lower case, no accents, letters,
-- digits and the decimal point between digits («2.20», «31.8»).
create or replace function public.catalog_search_text_v2(p_text text)
returns text
language sql
stable
parallel safe
set search_path to 'public'
as $function$
  select btrim(regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            unaccent(lower(coalesce(p_text, ''))),
            '([0-9]),([0-9])', '\1.\2', 'g'
          ),
          '([0-9])mm(?![a-z])', '\1 mm', 'g'
        ),
        '[^a-z0-9.]+', ' ', 'g'
      ),
      '(?<![0-9])\.|\.(?![0-9])', ' ', 'g'
    ),
    '\s+', ' ', 'g'
  ))
$function$;

comment on function public.catalog_search_text_v2(text) is
  'A product''s text as the catalog search compares it (20261025010000): lower case, no accents, «2,20» → «2.20», «180mm» → «180 mm»; decimals stay one word.';

revoke all on function public.catalog_search_text_v2(text) from public, anon, authenticated;

-- What a visitor types, as the catalog writes it: catalog_search_normalize_v1's
-- readings («29x2.25» → «29 2.25», «11 velocidades»/«11s»/«1x11» → «11v»,
-- «29er» → «29», «700c» → «700») with the decimals kept.
create or replace function public.catalog_search_query_v2(p_text text)
returns text
language sql
stable
parallel safe
set search_path to 'public'
as $function$
  select public.catalog_search_text_v2(
    -- «700c» is the 700 the names say («700 x 25C»).
    regexp_replace(
      -- «29er» is a 29.
      regexp_replace(
        -- «29x2.25», «700 x 25c»: the measures, without the «x».
        regexp_replace(
          -- «11 velocidades», «11 vel», «11s», «11-speed»: «11v».
          regexp_replace(
            -- «1x11», «2x10»: the speeds of the cassette, «11v».
            regexp_replace(
              regexp_replace(
                unaccent(lower(btrim(coalesce(p_text, '')))),
                '([0-9]),([0-9])', '\1.\2', 'g'
              ),
              '(^|\s)[1-3]x([0-9]{1,2})(?=\s|$|v)',
              '\1\2v',
              'g'
            ),
            '(^|[^0-9.,])([0-9]{1,2})[\s-]?(v|vel|vels|velocidad|velocidades|s|sp|spd|speed|speeds)(?![a-z])',
            '\1\2v',
            'g'
          ),
          '([0-9])\s*[x×*]\s*([0-9])',
          '\1 \2',
          'g'
        ),
        '(^|[^0-9])([0-9]{2})er(?![a-z])',
        '\1\2',
        'g'
      ),
      '(^|[^0-9])([0-9]{3})c(?![a-z0-9])',
      '\1\2',
      'g'
    )
  )
$function$;

comment on function public.catalog_search_query_v2(text) is
  'A visitor''s search as the catalog writes it, decimals kept (20261025010000): «29x2.25» → «29 2.25», «11 velocidades»/«11s»/«1x11» → «11v», «29er» → «29», «700c» → «700», «180mm» → «180 mm».';

revoke all on function public.catalog_search_query_v2(text) from public, anon, authenticated;

-- «disco» is the rotor in the workshop («disco de 180», «cambiar los
-- discos»); it was only a broader word, so «disco 180mm» listed adapters.
update public.catalog_search_terms
   set terms = array['rotor', 'rotores', 'disco', 'discos'],
       broader = array['freno', 'frenos'],
       updated_at = now()
 where tenant_id is null
   and concept = 'disco';

-- A chain tool is a tool: «Cortacadena» sits in the category «Corta Cadena»
-- and «cadena 12v» listed it as a chain. Its own group (not a word of
-- «herramienta», or every tool would answer to «cortacadena»), and the
-- pullers' too.
insert into public.catalog_search_terms (tenant_id, concept, kind, terms, broader, phrases, label)
values
  (null, 'cortacadena', 'part', array['cortacadena', 'cortacadenas', 'tronchacadena', 'tronchacadenas'],
   array['herramienta', 'herramientas'], array['corta cadena', 'corta cadenas'], 'Cortacadena'),
  (null, 'extractor', 'part', array['extractor', 'extractores'],
   array['herramienta', 'herramientas'], array['saca volante', 'saca bielas'], 'Extractor')
on conflict ((coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)), concept)
do update set kind = excluded.kind, terms = excluded.terms, broader = excluded.broader,
  phrases = excluded.phrases, label = excluded.label, updated_at = now();

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
  normalized as (
    -- The normalized texts only matter to a search: without a term every
    -- product passes and the order reads the raw name, price and date, so
    -- they are not computed (nor scored, below).
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
      case when a.term = '' then '' else public.catalog_search_text_v2(concat_ws(' ', p.website_name, p.name)) end as name_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.sku) end as sku_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.barcode) end as barcode_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.gtin) end as gtin_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(coalesce(p.category_name, p.category)) end as category_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.brand) end as brand_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.model) end as model_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.manufacturer) end as manufacturer_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(p.manufacturer_sku) end as manufacturer_sku_n,
      case when a.term = '' then '' else public.catalog_search_text_v2(concat_ws(' ', p.website_description, p.description)) end as description_n
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
  facet_values as materialized (
    -- The spec sheet as the store's filters show it, read once for a search.
    select v.*
    from public.spec_public_facet_values_compute_internal_v1(p_tenant_id, null) v
    where (select a.term from args a) <> ''
  ),
  display_labels as materialized (
    -- An option's identity label may carry research codes («… 7v sólo según
    -- filas C-731»); the store shows its display_label (20261002100000), and
    -- so the search reads it.
    select distinct on (dv.label) dv.label, btrim(dv.display_label) as display_label
    from public.spec_definition_values dv
    where dv.display_label is not null
      and btrim(dv.display_label) <> ''
      and (select a.term from args a) <> ''
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
    -- What each product states of the measures asked: its spec sheet, and
    -- its name («7/8/9 velocidades», «3x5/6/7», «aro 26», «29 x 2.25»,
    -- «36 rayos»). Read only when the search asks for a measure.
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
      and exists (select 1 from query_measures)
    union all
    select fv.product_id, 'drive',
      case
        when fv.value_text ilike '%cassette%' then 1
        when fv.value_text ilike '%rosca%' or fv.value_text ilike '%rueda libre%' then 2
        else 3
      end::numeric
    from facet_values fv
    where fv.spec_key = 'hub_drive_receiver_kind'
      and exists (select 1 from query_measures qm where qm.dim = 'drive')
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
      and exists (select 1 from query_measures qm where qm.dim = 'speeds')
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
      and exists (select 1 from query_measures qm where qm.dim = 'speeds')
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
      and exists (select 1 from query_measures qm where qm.dim = 'speeds')
    union all
    select n.id, 'bead', public.catalog_search_bead_of_v1(coalesce(m[1], m[2], m[3]))
    from normalized n
    cross join lateral regexp_matches(
      n.name_n,
      '(?:^| )(?:(?:aro|rin|rodado) ([0-9]{2}(?:\.5)?|700|650b)(?![0-9.])|([0-9]{2}(?:\.5)?|700|650b) ?x ?[0-9]|(700c|650b|29er)(?![0-9a-z.]))',
      'g'
    ) as m
    where public.catalog_search_bead_of_v1(coalesce(m[1], m[2], m[3])) is not null
      and exists (select 1 from query_measures qm where qm.dim = 'bead')
    union all
    select n.id, 'holes', m[1]::numeric
    from normalized n
    cross join lateral regexp_matches(
      n.name_n,
      '(?:^| )([0-9]{2}) ?(?:h|hoyos|agujeros|rayos|perforaciones)(?= |$)',
      'g'
    ) as m
    where exists (select 1 from query_measures qm where qm.dim = 'holes')
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
    where word_parts.word <> all (array['de', 'del', 'la', 'el', 'los', 'las', 'para', 'sin', 'con', 'y'])
      and not exists (
        select 1 from vocabulary_terms vt
        where vt.term = word_parts.word and vt.concept <> v.concept
      )
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
  product_words as materialized (
    -- Each product's words once, by where they are: the first word of its
    -- name (what it is), the rest of the name, its category and its spec
    -- sheet.
    select n.id as product_id, word_parts.word, case when word_parts.pos = 1 then 'head' else 'name' end as source
    from normalized n
    cross join lateral unnest(string_to_array(nullif(n.name_n, ''), ' ')) with ordinality as word_parts(word, pos)
    where n.term <> ''
    union all
    select n.id, word_parts.word, 'category'
    from normalized n
    cross join lateral unnest(string_to_array(nullif(n.category_n, ''), ' ')) as word_parts(word)
    where n.term <> ''
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
      where n.term <> ''
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
    -- its category names. Read only when the search names a part.
    select ch.product_id,
      coalesce(
        array_agg(ch.concept) filter (where ch.rank = 3),
        array_agg(ch.concept) filter (where ch.rank = 2)
      ) as own
    from concept_hits ch
    where ch.rank >= 2
      and exists (select 1 from primary_part)
    group by ch.product_id
  ),
  enriched as (
    select
      n.*,
      coalesce(st.spec_n, '') as spec_n,
      -- What the product is: the part its name starts with, and next the
      -- part its category names. «pedalier» puts the bottom brackets before
      -- the wrench «Llave para motor sellado», which sits in «Motores».
      coalesce(pa.head_n, '') as alias_head_n,
      coalesce(pa.type_n, '') as alias_type_n,
      coalesce(pn.head_names, '') as head_names,
      coalesce(pn.type_names, '') as type_names,
      coalesce(mc.confirms, '{}'::text[]) as measures_confirmed,
      coalesce(mc.states, '{}'::text[]) as measures_stated,
      pp.own as own_parts,
      prim.concept as asked_part,
      coalesce(prim.concept = any (pp.own), false) as is_asked_part,
      (
        prim.concept is not null
        and (
          -- It belongs to the part asked: pads to a brake, a quick link to
          -- a chain.
          exists (
            select 1 from vocabulary v
            where v.concept = any (pp.own)
              and v.broader && prim.terms
          )
          -- It is a tool, a consumable or a small part for the part asked:
          -- «Llave para motor sellado», «Lubricante de cadena», «Espaciador
          -- de cassette». A hub «para piñón con hilo» or a fork «para
          -- disco» is a hub and a fork.
          or (
            pp.own && array[
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
      ) as is_for_asked_part,
      case when n.term = '' then '' else trim(concat_ws(
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
        -- 27.5 is 650b; the 700 is the 28 some write.
        case
          when concat_ws(' ', n.name_n, st.spec_n) ~ '(^| )(27\.5|27 5|650 ?b|275|584)( |$)'
            then '650b 275 27.5'
        end,
        case when n.name_n ~ '(^| )700( |$)' then '28 700c' end
      )) end as alias_n
    from normalized n
    left join spec_text st on st.product_id = n.id
    left join product_aliases pa on pa.product_id = n.id
    left join product_names pn on pn.product_id = n.id
    left join measure_checks mc on mc.product_id = n.id
    left join product_parts pp on pp.product_id = n.id
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
