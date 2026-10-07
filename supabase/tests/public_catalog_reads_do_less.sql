-- 20261007020000: the public catalog reads do less work and answer the same.
-- The bodies they replace (captured from production on 2026-10-07) live here
-- as temporary functions, and every case compares row by row.
begin;

select plan(22);

create function pg_temp.old_spec_values(p_tenant_id uuid)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $old$
  with bound as (
    -- Facts of the product's resolved active template, field not retired,
    -- customer-visible, whatever their origin.
    select f.id as fact_id, f.subject_id, f.value_number, f.value_boolean, f.value_json,
      d.key, d.label, d.store_label, d.data_type, d.unit, d.is_filterable, d.validation_rules,
      t.form_contract
    from public.spec_facts f
    join public.product_spec_bindings_internal_v1 b on b.product_id = f.subject_id and b.tenant_id = f.tenant_id
    join public.spec_templates t on t.id = b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id = p_tenant_id)
    join public.spec_template_fields tf on tf.template_id = t.id and tf.spec_definition_id = f.spec_definition_id
    join public.spec_definitions d on d.id = f.spec_definition_id and d.is_customer_visible
    where f.tenant_id = p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
      and coalesce(t.form_contract->'roles'->>d.key, 'primary') <> 'legacy'
  ), scalar as (
    -- Options by label, numbers without trailing zeros, booleans as «Sí»/«No».
    select b.subject_id, b.key,
      coalesce(nullif(btrim(b.store_label), ''), b.form_contract->'labels'->>b.key, b.label) as spec_label,
      b.data_type, b.unit,
      case b.data_type
        when 'number' then trim_scale(b.value_number)::text
        when 'boolean' then case when b.value_boolean then 'Sí' else 'No' end
        else v.label end as value_text
    from bound b
    left join public.spec_fact_values fv on fv.fact_id = b.fact_id
    left join public.spec_definition_values v on v.id = fv.value_id and v.is_active
    where b.is_filterable and b.data_type in ('single_select','number','boolean')
      and (b.data_type <> 'single_select' or v.label is not null)
      and (b.data_type <> 'number' or b.value_number is not null)
      and (b.data_type <> 'boolean' or b.value_boolean is not null)
  ), projected as (
    -- A numeric cell of a rows field named after a global filterable number
    -- field is that field for the visitor (a tube's ISO diameter is «Aro»).
    select b.subject_id, target.key,
      coalesce(nullif(btrim(target.store_label), ''), b.form_contract->'labels'->>target.key, target.label) as spec_label,
      target.data_type, target.unit,
      case when (fit.r->'values'->>(cols.col->>'key')) ~ '^[0-9]+(\.[0-9]+)?$'
        then trim_scale((fit.r->'values'->>(cols.col->>'key'))::numeric)::text end as value_text
    from bound b
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.validation_rules->'rows_schema'->'columns') = 'array'
        then b.validation_rules->'rows_schema'->'columns' else '[]'::jsonb end
    ) as cols(col)
    join public.spec_definitions target
      on target.tenant_id is null and target.key = cols.col->>'key'
     and target.data_type = 'number' and target.is_filterable and target.is_customer_visible
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.value_json->'rows') = 'array' then b.value_json->'rows' else '[]'::jsonb end
    ) as fit(r)
    where b.data_type = 'json' and cols.col->>'type' in ('integer','decimal','number')
  )
  select subject_id, key, spec_label, data_type, unit, value_text from scalar
  union
  select subject_id, key, spec_label, data_type, unit, value_text from projected where value_text is not null
$old$;

create function pg_temp.old_listing(
  p_tenant_id uuid, p_category_ids uuid[], p_product_ids uuid[], p_sku text,
  p_search_term text, p_product_type text, p_only_in_stock boolean,
  p_sort_by text, p_limit integer, p_offset integer
)
returns TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
language sql stable
set search_path to 'public'
as $old$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type,
      -- The outer reservation-aware wrapper is the sole stock-policy owner.
      'all'::text as stock_policy,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_require_image'
          limit 1
        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_image,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_require_visible_category'
          limit 1
        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_visible_category,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_include_uncategorized'
          limit 1
        ), 'true')) in ('true', '1', 'yes', 'si', 'sí') as include_uncategorized
    from (
      select trim(
        regexp_replace(
          unaccent(lower(trim(coalesce(p_search_term, '')))),
          '[^a-z0-9]+',
          ' ',
          'g'
        )
      ) as term
    ) s
    cross join lateral (
      select array_agg(token) as tokens
      from regexp_split_to_table(s.term, '\s+') as token_parts(token)
      where token <> ''
    ) t
  ),
  normalized as (
    select
      p.*,
      a.term,
      a.tokens,
      a.page_limit,
      a.page_offset,
      a.sort_by,
      (
        a.term ~ '(^| )(servicio|servicios|mantencion|mantenciones|reparacion|reparaciones|ajuste|ajustes|instalacion|instalaciones|limpieza|lavado|engrase|sangrado|purga|centrado|enrayado|diagnostico|revision)( |$)'
      ) as service_intent,
      trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_name, p.name))), '[^a-z0-9]+', ' ', 'g')) as name_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.sku, ''))), '[^a-z0-9]+', ' ', 'g')) as sku_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.barcode, ''))), '[^a-z0-9]+', ' ', 'g')) as barcode_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.gtin, ''))), '[^a-z0-9]+', ' ', 'g')) as gtin_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.category_name, p.category, ''))), '[^a-z0-9]+', ' ', 'g')) as category_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.brand, ''))), '[^a-z0-9]+', ' ', 'g')) as brand_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.model, ''))), '[^a-z0-9]+', ' ', 'g')) as model_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer, ''))), '[^a-z0-9]+', ' ', 'g')) as manufacturer_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer_sku, ''))), '[^a-z0-9]+', ' ', 'g')) as manufacturer_sku_n,
      trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_description, p.description))), '[^a-z0-9]+', ' ', 'g')) as description_n
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
      and (
        not a.require_image
        or nullif(btrim(coalesce(p.website_image_url, '')), '') is not null
        or nullif(btrim(coalesce(p.website_image_url_optimized, '')), '') is not null
        or cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        or nullif(btrim(coalesce(p.image_url, '')), '') is not null
        or nullif(btrim(coalesce(p.image_url_optimized, '')), '') is not null
        or cardinality(coalesce(p.image_urls, array[]::text[])) > 0
      )
      and (
        not a.require_visible_category
        or (p.category_id is null and a.include_uncategorized)
        or exists (
          select 1
          from public.product_categories pc
          where pc.id = p.category_id
            and pc.tenant_id = p_tenant_id
            and pc.is_active = true
            and coalesce(pc.show_on_website, false) = true
        )
      )
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
  enriched as (
    select
      n.*,
      trim(concat_ws(
        ' ',
        case
          when n.name_n like '%pinon%'
            or n.category_n in ('pinones', 'cassette')
            then 'pinon pinones cassette freewheel rueda libre coronas'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cadena%'
            then 'cadena chain transmision'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%camara%'
            then 'camara tubo tube valvula neumatico'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cubierta%'
            or concat_ws(' ', n.name_n, n.category_n) like '%neumatico%'
            then 'cubierta neumatico tire goma'
          else null
        end
      )) as alias_n
    from normalized n
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
        case when e.term <> '' and e.category_n = e.term then 620 else 0 end +
        case when e.term <> '' and e.category_n like '%' || e.term || '%' then 560 else 0 end +
        case when e.term <> '' and e.alias_n like '%' || e.term || '%' then 500 else 0 end +
        case when e.term <> '' and e.sku_n like '%' || e.term || '%' then 460 else 0 end +
        case when e.term <> '' and e.manufacturer_sku_n like '%' || e.term || '%' then 420 else 0 end +
        case when e.term <> '' and e.brand_n like '%' || e.term || '%' then 360 else 0 end +
        case when e.term <> '' and e.model_n like '%' || e.term || '%' then 320 else 0 end +
        case when e.term <> '' and e.manufacturer_n like '%' || e.term || '%' then 300 else 0 end
      ) as phrase_strong_score,
      coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.sku_n = token then 120
            when token ~ '^[0-9]+$' and e.barcode_n = token then 120
            when token ~ '^[0-9]+$' and e.gtin_n = token then 120
            when token ~ '^[0-9]+$' and e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 70
            when token ~ '^[0-9]+$' and e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 58
            when token ~ '^[0-9]+$' then 0
            when e.name_n like token || '%' then 95
            when e.name_n like '%' || token || '%' then 76
            when e.category_n like '%' || token || '%' then 66
            when e.alias_n like '%' || token || '%' then 56
            when e.sku_n like '%' || token || '%' then 54
            when e.manufacturer_sku_n like '%' || token || '%' then 48
            when e.brand_n like '%' || token || '%' then 42
            when e.model_n like '%' || token || '%' then 38
            when e.manufacturer_n like '%' || token || '%' then 34
            when length(token) >= 4 and greatest(
              word_similarity(token, e.name_n),
              word_similarity(token, e.category_n),
              word_similarity(token, e.brand_n),
              word_similarity(token, e.model_n),
              word_similarity(token, e.manufacturer_n),
              word_similarity(token, e.alias_n)
            ) >= case when length(token) >= 5 then 0.56 else 0.72 end then 28
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) as token_strong_score,
      coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 8
            when token !~ '^[0-9]+$' and e.description_n like '%' || token || '%' then 8
            when token !~ '^[0-9]+$' and length(token) >= 5 and word_similarity(token, e.description_n) >= 0.86 then 5
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) as weak_description_score
    from enriched e
    where e.term = ''
      or not exists (
        select 1
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
          and not (
            (
              token ~ '^[0-9]+$'
              and (
                e.sku_n = token
                or e.barcode_n = token
                or e.gtin_n = token
                or e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
              )
            )
            or (
              token !~ '^[0-9]+$'
              and (
                e.name_n like '%' || token || '%'
                or e.category_n like '%' || token || '%'
                or e.alias_n like '%' || token || '%'
                or e.sku_n like '%' || token || '%'
                or e.barcode_n like '%' || token || '%'
                or e.gtin_n like '%' || token || '%'
                or e.brand_n like '%' || token || '%'
                or e.model_n like '%' || token || '%'
                or e.manufacturer_n like '%' || token || '%'
                or e.manufacturer_sku_n like '%' || token || '%'
                or e.description_n like '%' || token || '%'
                or (
                  length(token) >= 4
                  and greatest(
                    word_similarity(token, e.name_n),
                    word_similarity(token, e.category_n),
                    word_similarity(token, e.brand_n),
                    word_similarity(token, e.model_n),
                    word_similarity(token, e.manufacturer_n),
                    word_similarity(token, e.alias_n)
                  ) >= case when length(token) >= 5 then 0.56 else 0.72 end
                )
                or (
                  length(token) >= 5
                  and word_similarity(token, e.description_n) >= 0.86
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
  offset (select page_offset from args)
$old$;

select ok(
  not exists (
    select 1
      from unnest(array['anon', 'authenticated', 'service_role']) as r(role)
     where has_function_privilege(r.role,
             'public.spec_public_facet_values_compute_internal_v1(uuid,uuid[])', 'EXECUTE')
        or has_function_privilege(r.role,
             'public.spec_public_facet_values_internal_v1(uuid)', 'EXECUTE')),
  'the values stay internal'
);

-- Fixture: one store; five products that cover every way a product gets (or
-- does not get) a template, and facts of every kind the values read.
insert into public.tenants (id, shop_name, currency, timezone)
values ('7fae0000-0000-4000-8000-000000000001', 'Catalog Reads Test', 'CLP', 'America/Santiago');
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.skip_stock_adjustment_trigger', 'true', true);

insert into public.product_categories (id, tenant_id, name, full_path, parent_id, level, is_active, show_on_website, sort_order)
values
  ('7fae3000-0000-4000-8000-000000000001', '7fae0000-0000-4000-8000-000000000001', 'Cámaras', 'Cámaras', null, 0, true, true, 1),
  ('7fae3000-0000-4000-8000-000000000002', '7fae0000-0000-4000-8000-000000000001', 'Válvulas', 'Válvulas', null, 0, true, true, 2),
  ('7fae3000-0000-4000-8000-000000000003', '7fae0000-0000-4000-8000-000000000001', 'Servicios', 'Servicios', null, 0, true, true, 3);

insert into public.spec_definitions (id, tenant_id, key, label, store_label, data_type, unit, allowed_values, is_filterable, is_customer_visible)
values
  ('7fae5000-0000-4000-8000-000000000001', null, 'reads_test_valve', 'Válvula (lecturas)', 'Válvula', 'single_select', null, '["Presta", "Schrader"]'::jsonb, true, true),
  ('7fae5000-0000-4000-8000-000000000002', null, 'reads_test_len', 'Largo (lecturas)', null, 'number', 'mm', '[]'::jsonb, true, true),
  ('7fae5000-0000-4000-8000-000000000003', null, 'reads_test_sealant', 'Con líquido (lecturas)', null, 'boolean', null, '[]'::jsonb, true, true),
  ('7fae5000-0000-4000-8000-000000000004', null, 'reads_test_retired', 'Retirado (lecturas)', null, 'number', 'mm', '[]'::jsonb, true, true),
  ('7fae5000-0000-4000-8000-000000000005', null, 'reads_test_private', 'Privado (lecturas)', null, 'number', 'mm', '[]'::jsonb, true, false);

insert into public.spec_definition_values (id, spec_definition_id, code, label, sort_order, is_active)
values
  ('7fae5100-0000-4000-8000-000000000001', '7fae5000-0000-4000-8000-000000000001', 'presta', 'Presta', 1, true),
  ('7fae5100-0000-4000-8000-000000000002', '7fae5000-0000-4000-8000-000000000001', 'schrader', 'Schrader', 2, false);

insert into public.spec_templates (id, tenant_id, key, name, technical_family, form_contract, is_active)
values
  ('7fae6000-0000-4000-8000-000000000001', null, 'reads_test_tube', 'Cámara (lecturas)', 'tube',
   '{"roles": {"reads_test_retired": "legacy"}, "labels": {"reads_test_len": "Largo de válvula"}}'::jsonb, true),
  ('7fae6000-0000-4000-8000-000000000002', '7fae0000-0000-4000-8000-000000000001', 'reads_test_valve_tpl', 'Válvula (lecturas)', 'tube', '{}'::jsonb, true);

insert into public.spec_template_fields (template_id, spec_definition_id, section_key, sort_order)
select t.id, d.id, 'primary', row_number() over ()
  from (values ('7fae6000-0000-4000-8000-000000000001'::uuid), ('7fae6000-0000-4000-8000-000000000002'::uuid)) t(id)
 cross join (values ('7fae5000-0000-4000-8000-000000000001'::uuid), ('7fae5000-0000-4000-8000-000000000002'::uuid),
                    ('7fae5000-0000-4000-8000-000000000003'::uuid), ('7fae5000-0000-4000-8000-000000000004'::uuid),
                    ('7fae5000-0000-4000-8000-000000000005'::uuid)) d(id);

-- Category «Cámaras» maps to the shared tube template; «Válvulas» has a
-- pending mapping, which binds nothing.
insert into public.category_tech_mappings (tenant_id, category_id, technical_family, template_id, status)
values
  ('7fae0000-0000-4000-8000-000000000001', '7fae3000-0000-4000-8000-000000000001', 'tube', '7fae6000-0000-4000-8000-000000000001', 'active'),
  ('7fae0000-0000-4000-8000-000000000001', '7fae3000-0000-4000-8000-000000000002', 'tube', '7fae6000-0000-4000-8000-000000000001', 'pending');

insert into public.products (
  id, tenant_id, name, website_name, sku, price, website_price, cost, tax_rate,
  category_id, spec_template_id, brand, description,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  product_type, is_service, purchase_treatment, track_stock,
  is_active, is_published, show_on_website, created_at
)
values
  -- by its category's mapping
  ('7fae2000-0000-4000-8000-000000000001', '7fae0000-0000-4000-8000-000000000001',
   'Cámara Kenda 29', null, 'READS-1', 5000, 5000, 2000, null,
   '7fae3000-0000-4000-8000-000000000001', null, 'Kenda', 'Válvula Presta, 48 mm.',
   4, 4, 0, 100, 'product', false, 'inventory', true, true, true, true, now() - interval '3 days'),
  -- its own template wins over the category's
  ('7fae2000-0000-4000-8000-000000000002', '7fae0000-0000-4000-8000-000000000001',
   'Cámara Maxxis 27,5', 'Cámara Maxxis 27.5 «tubeless»', 'READS-2', 6000, 5500, 2500, null,
   '7fae3000-0000-4000-8000-000000000001', '7fae6000-0000-4000-8000-000000000002', 'Maxxis', null,
   4, 4, 0, 100, 'product', false, 'inventory', true, true, true, true, now() - interval '2 days'),
  -- pending mapping: no template
  ('7fae2000-0000-4000-8000-000000000003', '7fae0000-0000-4000-8000-000000000001',
   'Válvula Presta 60', null, 'READS-3', 1500, null, 500, null,
   '7fae3000-0000-4000-8000-000000000002', null, 'Genérico', 'Válvula de repuesto.',
   0, 0, 0, 100, 'product', false, 'inventory', true, true, true, true, now() - interval '1 day'),
  -- an explicit template that will be inactive does not fall back to the category
  ('7fae2000-0000-4000-8000-000000000004', '7fae0000-0000-4000-8000-000000000001',
   'Cámara de paso', null, 'READS-4', 4000, 4000, 1500, null,
   '7fae3000-0000-4000-8000-000000000001', '7fae6000-0000-4000-8000-000000000002', 'Kenda', null,
   1, 1, 0, 100, 'product', false, 'inventory', true, true, true, true, now()),
  -- a service
  ('7fae2000-0000-4000-8000-000000000005', '7fae0000-0000-4000-8000-000000000001',
   'Mantención de suspensión', null, 'READS-5', 30000, null, 0, null,
   '7fae3000-0000-4000-8000-000000000003', null, null, 'Cambio de aceite y retenes.',
   0, 0, 0, 0, 'service', true, 'service', false, true, true, true, now());

insert into public.spec_facts (id, tenant_id, subject_type, subject_id, spec_definition_id, value_number, value_boolean, source, confirmed)
select gen_random_uuid(), '7fae0000-0000-4000-8000-000000000001', 'product', p.id, d.id,
       case d.id when '7fae5000-0000-4000-8000-000000000002' then 48.50
                 when '7fae5000-0000-4000-8000-000000000004' then 33
                 when '7fae5000-0000-4000-8000-000000000005' then 21 end,
       case d.id when '7fae5000-0000-4000-8000-000000000003' then true end,
       'catalog', true
  from (values ('7fae2000-0000-4000-8000-000000000001'::uuid), ('7fae2000-0000-4000-8000-000000000002'::uuid),
               ('7fae2000-0000-4000-8000-000000000003'::uuid), ('7fae2000-0000-4000-8000-000000000004'::uuid)) p(id)
 cross join (values ('7fae5000-0000-4000-8000-000000000001'::uuid), ('7fae5000-0000-4000-8000-000000000002'::uuid),
                    ('7fae5000-0000-4000-8000-000000000003'::uuid), ('7fae5000-0000-4000-8000-000000000004'::uuid),
                    ('7fae5000-0000-4000-8000-000000000005'::uuid)) d(id);

insert into public.spec_fact_values (fact_id, value_id, position)
select f.id, case when f.subject_id = '7fae2000-0000-4000-8000-000000000002'
                  then '7fae5100-0000-4000-8000-000000000002'::uuid
                  else '7fae5100-0000-4000-8000-000000000001'::uuid end, 0
  from public.spec_facts f
 where f.spec_definition_id = '7fae5000-0000-4000-8000-000000000001'
   and f.tenant_id = '7fae0000-0000-4000-8000-000000000001';

create function pg_temp.differences(p_new text, p_old text)
returns bigint language plpgsql as $$
declare v bigint;
begin
  execute format('select count(*) from ((%s except all %s) union all (%s except all %s)) d',
                 p_new, p_old, p_old, p_new) into v;
  return v;
end $$;

-- Technical values ------------------------------------------------------------

select ok(
  (select count(*) from public.spec_public_facet_values_compute_internal_v1(
     '7fae0000-0000-4000-8000-000000000001', null)) > 0,
  'the fixture has technical values'
);
select is(
  pg_temp.differences(
    $$select * from public.spec_public_facet_values_compute_internal_v1('7fae0000-0000-4000-8000-000000000001', null)$$,
    $$select * from pg_temp.old_spec_values('7fae0000-0000-4000-8000-000000000001')$$),
  0::bigint,
  'the values of the store are the previous body''s, row by row'
);
select is(
  pg_temp.differences(
    $$select * from public.spec_public_facet_values_internal_v1('7fae0000-0000-4000-8000-000000000001')$$,
    $$select * from pg_temp.old_spec_values('7fae0000-0000-4000-8000-000000000001')$$),
  0::bigint,
  'and the old entry point answers the same'
);
select is(
  pg_temp.differences(
    $$select * from public.spec_public_facet_values_compute_internal_v1('7fae0000-0000-4000-8000-000000000001',
        array['7fae2000-0000-4000-8000-000000000002', '7fae2000-0000-4000-8000-000000000003']::uuid[])$$,
    $$select * from pg_temp.old_spec_values('7fae0000-0000-4000-8000-000000000001')
       where product_id in ('7fae2000-0000-4000-8000-000000000002', '7fae2000-0000-4000-8000-000000000003')$$),
  0::bigint,
  'a product list gets exactly its products'' values'
);
select is(
  (select count(*)::integer from public.spec_public_facet_values_compute_internal_v1(
     '7fae0000-0000-4000-8000-000000000001', '{}'::uuid[])),
  0,
  'an empty list gets none'
);
select is(
  (select string_agg(v.spec_label || '=' || v.value_text, ' ' order by v.spec_key collate "C")
     from public.spec_public_facet_values_compute_internal_v1('7fae0000-0000-4000-8000-000000000001', null) v
    where v.product_id = '7fae2000-0000-4000-8000-000000000001'),
  'Largo de válvula=48.5 Con líquido (lecturas)=Sí Válvula=Presta',
  'the contract''s label, trimmed numbers, «Sí», the store name; retired and private fields left out'
);

-- One product moves to its category's template, and the other one's own
-- template goes inactive. The retirement guard refuses that today, but rows
-- from before the guard can still be like this: such a product has no values
-- and does not fall back to its category's mapping.
update public.products set spec_template_id = null
 where id = '7fae2000-0000-4000-8000-000000000002';
set local session_replication_role = replica;
update public.spec_templates set is_active = false
 where id = '7fae6000-0000-4000-8000-000000000002';
set local session_replication_role = origin;
select is(
  (select count(*)::integer from public.spec_public_facet_values_compute_internal_v1(
     '7fae0000-0000-4000-8000-000000000001', array['7fae2000-0000-4000-8000-000000000004']::uuid[])),
  0,
  'a product whose own template is inactive has no values'
);
select is(
  pg_temp.differences(
    $$select * from public.spec_public_facet_values_compute_internal_v1('7fae0000-0000-4000-8000-000000000001', null)$$,
    $$select * from pg_temp.old_spec_values('7fae0000-0000-4000-8000-000000000001')$$),
  0::bigint,
  'after both changes, still the same'
);

-- Listing ---------------------------------------------------------------------

create function pg_temp.same_listing(p_args text)
returns boolean language plpgsql as $$
declare v_new text; v_old text;
begin
  execute format('select md5(coalesce(string_agg(q::text, %L order by q.rn), %L)) from (select row_number() over () as rn, x.* from public.get_public_products_without_inventory_reservations(%s) x) q', '|', '', p_args) into v_new;
  execute format('select md5(coalesce(string_agg(q::text, %L order by q.rn), %L)) from (select row_number() over () as rn, x.* from pg_temp.old_listing(%s) x) q', '|', '', p_args) into v_old;
  return v_new = v_old;
end $$;

select is(
  (select count(*)::integer from public.get_public_products_without_inventory_reservations(
     '7fae0000-0000-4000-8000-000000000001', null, null, null, null, null, false, 'name', 100, 0)),
  5,
  'the fixture lists all five'
);
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, null, null, false, 'name', 100, 0$$),
  'every product by name, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, '', 'product', true, 'price_asc', 2, 1$$),
  'by price, a page, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, null, null, false, 'price_desc', 100, 0$$),
  'by price, descending, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', array['7fae3000-0000-4000-8000-000000000001']::uuid[], null, null, null, null, false, 'newest', 100, 0$$),
  'a category, newest first, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, 'camara', null, false, 'name', 100, 0$$),
  'a search, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, 'Válvula 48', null, false, 'name', 100, 0$$),
  'a search with accents and a number, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, 'mantencion', null, false, 'name', 100, 0$$),
  'a service search, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, null, 'kenda', 'product', false, 'name', 100, 0$$),
  'a brand search, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, null, 'reads-2', null, null, false, 'name', 5, 0$$),
  'a SKU, as before');
select ok(pg_temp.same_listing($$'7fae0000-0000-4000-8000-000000000001', null, array['7fae2000-0000-4000-8000-000000000003']::uuid[], null, null, null, false, 'name', 5, 0$$),
  'a product list, as before');

-- Facets ----------------------------------------------------------------------

select ok(
  exists (
    select 1 from public.get_public_product_facets_v2(
      p_tenant_id := '7fae0000-0000-4000-8000-000000000001',
      p_category_ids := array['7fae3000-0000-4000-8000-000000000001']::uuid[],
      p_only_in_stock := false) f
     where f.facet_key like 'spec:reads_test_len:%' and f.value_id = '48.5'),
  'a category''s technical filters come from its own products'
);
select is(
  (select count(*)::integer from public.get_public_product_facets_v2(
     p_tenant_id := '7fae0000-0000-4000-8000-000000000001',
     p_category_ids := array['7fae3000-0000-4000-8000-000000000003']::uuid[],
     p_only_in_stock := false) f
    where f.facet_key like 'spec:%'),
  0,
  'a category without technical values offers none'
);

select * from finish();
rollback;
