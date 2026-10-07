-- Read-back of 20261007020000: the public catalog reads do less work and
-- answer the same. Read-only; division by zero fails it, and it fails before
-- the migration because the new function does not exist yet.
--
-- 1. The four functions are the ones tested (source hash), stay security
--    definer with their search path; the values and the inner listing stay
--    internal and the filters stay public.
-- 2. Every store's technical values equal the previous body's.
-- 3. The listing and the filters equal the previous bodies' for real requests
--    of the shop, row by row and in order. The previous bodies, captured from
--    production on 2026-10-07, run inline here.
-- 4. As anon, within anon's 3 s, the reads a catalog page makes.

select p.oid::regprocedure as funcion, md5(p.prosrc) as fuente, p.prosecdef, p.proconfig
  from pg_proc p
 where p.oid in (to_regprocedure('public.spec_public_facet_values_compute_internal_v1(uuid,uuid[])'),
                 to_regprocedure('public.spec_public_facet_values_internal_v1(uuid)'),
                 to_regprocedure('public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb)'),
                 to_regprocedure('public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'))
 order by 1::text;

select 1/(case when
  (select count(*) from pg_proc p
    where p.prosecdef
      and (p.oid, md5(p.prosrc)) in (
        (to_regprocedure('public.spec_public_facet_values_compute_internal_v1(uuid,uuid[])'), 'c95566ec271e574a756a9c5cbabd25a7'),
        (to_regprocedure('public.spec_public_facet_values_internal_v1(uuid)'), 'bced042d71e418a2b099c0a92ba934f5'),
        (to_regprocedure('public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb)'), '0f8cf1e418ceb17ea72d376b6e6cfa6d'),
        (to_regprocedure('public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'), 'e278170d09a1f42185471917c1732b1e'))) = 4
  and (select count(*) from pg_proc p
        where (p.oid, p.proconfig) in (
          (to_regprocedure('public.spec_public_facet_values_compute_internal_v1(uuid,uuid[])'), array['search_path=pg_catalog, public, pg_temp']),
          (to_regprocedure('public.spec_public_facet_values_internal_v1(uuid)'), array['search_path=pg_catalog, public, pg_temp']),
          (to_regprocedure('public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb)'), array['search_path=public']),
          (to_regprocedure('public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'), array['search_path=public']))) = 4
  and not exists (
    select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid in (to_regprocedure('public.spec_public_facet_values_compute_internal_v1(uuid,uuid[])'),
                     to_regprocedure('public.spec_public_facet_values_internal_v1(uuid)'))
       and a.privilege_type = 'EXECUTE' and a.grantee = 0)
  and not exists (
    select 1 from unnest(array['anon', 'authenticated', 'service_role']) r(role)
     where has_function_privilege(r.role, 'public.spec_public_facet_values_compute_internal_v1(uuid,uuid[])', 'EXECUTE')
        or has_function_privilege(r.role, 'public.spec_public_facet_values_internal_v1(uuid)', 'EXECUTE'))
  and has_function_privilege('anon', 'public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)', 'EXECUTE')
then 1 else 0 end) as funciones_probadas_y_privadas;

-- 2. Every store's technical values, the previous body inline.
with antes as materialized (
  select caso_args.p_tenant_id, x.*
    from (select t.id as p_tenant_id from public.tenants t) caso_args
    cross join lateral (
      with bound as (
          -- Facts of the product's resolved active template, field not retired,
          -- customer-visible, whatever their origin.
          select f.id as fact_id, f.subject_id, f.value_number, f.value_boolean, f.value_json,
            d.key, d.label, d.store_label, d.data_type, d.unit, d.is_filterable, d.validation_rules,
            t.form_contract
          from public.spec_facts f
          join public.product_spec_bindings_internal_v1 b on b.product_id = f.subject_id and b.tenant_id = f.tenant_id
          join public.spec_templates t on t.id = b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id = caso_args.p_tenant_id)
          join public.spec_template_fields tf on tf.template_id = t.id and tf.spec_definition_id = f.spec_definition_id
          join public.spec_definitions d on d.id = f.spec_definition_id and d.is_customer_visible
          where f.tenant_id = caso_args.p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
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
    ) x
), ahora as materialized (
  select k.id as p_tenant_id, x.*
    from public.tenants k
    cross join lateral public.spec_public_facet_values_internal_v1(k.id) x
), distintas as (
  (select * from ahora except all select * from antes)
  union all
  (select * from antes except all select * from ahora)
)
select (select count(distinct p_tenant_id) from ahora) as tiendas_con_valores,
       (select count(*) from ahora) as valores,
       (select count(*) from distintas) as filas_distintas,
       1/(case when (select count(*) from distintas) = 0 and (select count(*) from ahora) > 0
          then 1 else 0 end) as valores_iguales;

-- A product list gets exactly its products' values.
with lista as (
  select array(select p.id from public.products p
                where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid order by p.id limit 60) as ids
), por_lista as (
  select * from public.spec_public_facet_values_compute_internal_v1('5443b130-cc28-45af-a420-cd500b288890'::uuid, (select ids from lista))
), filtrados as (
  select * from public.spec_public_facet_values_internal_v1('5443b130-cc28-45af-a420-cd500b288890'::uuid) v
   where v.product_id in (select unnest(l.ids) from lista l)
)
select (select count(*) from por_lista) as valores_de_la_lista,
       1/(case when not exists (select * from por_lista except all select * from filtrados)
                and not exists (select * from filtrados except all select * from por_lista)
          then 1 else 0 end) as lista_de_productos;

-- 3a. The listing.
with cases(caso, p_tenant_id, p_category_ids, p_product_ids, p_sku, p_search_term, p_product_type, p_only_in_stock, p_sort_by, p_limit, p_offset) as (
  values
    ('todo_nombre', '5443b130-cc28-45af-a420-cd500b288890'::uuid::uuid, null::uuid[], null::uuid[], null::text, null::text, 'product'::text, false::boolean, 'name'::text, 2147483647::integer, 0::integer),
    ('precio_asc_pagina_3', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, '', 'product', true, 'price_asc', 20, 40),
    ('precio_desc', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, null, null, true, 'price_desc', 60, 0),
    ('recientes_accesorios', '5443b130-cc28-45af-a420-cd500b288890'::uuid, array['164e46a9-3bfc-47d9-85ff-e911d96adacd']::uuid[], null, null, null, null, true, 'newest', 50, 0),
    ('busqueda_cadena', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'cadena 11 velocidades', 'product', true, 'name', 50, 0),
    ('busqueda_shimano', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'shimano', null, true, 'price_asc', 20, 20),
    ('busqueda_numero', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, '29', null, false, 'name', 40, 0),
    ('busqueda_simbolos', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, ' -- ', null, false, 'name', 30, 0),
    ('busqueda_con_tilde', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'cámara válvula', null, false, 'name', 30, 0),
    ('servicios_mantencion', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'mantencion', 'service', false, 'name', 50, 0),
    ('servicios_todos', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, null, 'service', false, 'name', 100, 0),
    ('ids', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, array(select p.id from public.products p where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid order by p.id limit 7), null, null, null, false, 'name', 2147483647, 0),
    ('un_sku', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, (select min(p.sku) from public.products p where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid and p.is_published and p.show_on_website and p.sku is not null), null, null, false, 'name', 5, 0)
)
select caso, filas, ahora = antes as igual,
       1/(case when ahora = antes then 1 else 0 end) as listado_igual
  from (
    select caso_args.caso,
           (select count(*) from public.get_public_products_without_inventory_reservations(caso_args.p_tenant_id, caso_args.p_category_ids, caso_args.p_product_ids, caso_args.p_sku, caso_args.p_search_term, caso_args.p_product_type, caso_args.p_only_in_stock, caso_args.p_sort_by, caso_args.p_limit, caso_args.p_offset)) as filas,
           (select md5(coalesce(string_agg(r::text, '|' order by r.rn), ''))
              from (select row_number() over () as rn, x.*
                      from public.get_public_products_without_inventory_reservations(caso_args.p_tenant_id, caso_args.p_category_ids, caso_args.p_product_ids, caso_args.p_sku, caso_args.p_search_term, caso_args.p_product_type, caso_args.p_only_in_stock, caso_args.p_sort_by, caso_args.p_limit, caso_args.p_offset) x) r) as ahora,
           (select md5(coalesce(string_agg(r::text, '|' order by r.rn), ''))
              from (select row_number() over () as rn, x.* from (
                with args as (
                    select
                      s.term,
                      coalesce(t.tokens, array[]::text[]) as tokens,
                      greatest(coalesce(caso_args.p_limit, 20), 0) as page_limit,
                      greatest(coalesce(caso_args.p_offset, 0), 0) as page_offset,
                      lower(coalesce(nullif(trim(caso_args.p_sort_by), ''), 'name')) as sort_by,
                      nullif(trim(coalesce(caso_args.p_sku, '')), '') as wanted_sku,
                      nullif(trim(coalesce(caso_args.p_product_type, '')), '') as wanted_product_type,
                      -- The outer reservation-aware wrapper is the sole stock-policy owner.
                      'all'::text as stock_policy,
                      lower(coalesce((
                          select ws.value
                          from public.website_settings ws
                          where ws.tenant_id = caso_args.p_tenant_id
                            and ws.key = 'product_visibility_require_image'
                          limit 1
                        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_image,
                      lower(coalesce((
                          select ws.value
                          from public.website_settings ws
                          where ws.tenant_id = caso_args.p_tenant_id
                            and ws.key = 'product_visibility_require_visible_category'
                          limit 1
                        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_visible_category,
                      lower(coalesce((
                          select ws.value
                          from public.website_settings ws
                          where ws.tenant_id = caso_args.p_tenant_id
                            and ws.key = 'product_visibility_include_uncategorized'
                          limit 1
                        ), 'true')) in ('true', '1', 'yes', 'si', 'sí') as include_uncategorized
                    from (
                      select trim(
                        regexp_replace(
                          unaccent(lower(trim(coalesce(caso_args.p_search_term, '')))),
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
                    where p.tenant_id = caso_args.p_tenant_id
                      and p.is_active = true
                      and coalesce(p.is_published, false) = true
                      and coalesce(p.show_on_website, false) = true
                      and (
                        caso_args.p_product_ids is null
                        or cardinality(caso_args.p_product_ids) = 0
                        or p.id = any(caso_args.p_product_ids)
                      )
                      and (
                        caso_args.p_category_ids is null
                        or cardinality(caso_args.p_category_ids) = 0
                        or p.category_id = any(caso_args.p_category_ids)
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
                            and pc.tenant_id = caso_args.p_tenant_id
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
                    ) x) r) as antes
      from cases caso_args) compared
 order by caso;

-- 3b. The filters. The previous body reads the listing and the values
-- through their functions, compared above.
with cases(caso, p_tenant_id, p_category_ids, p_search_term, p_product_type, p_only_in_stock, p_brand_ids, p_min_price, p_max_price, p_spec_filters) as (
  values
    ('raiz', '5443b130-cc28-45af-a420-cd500b288890'::uuid::uuid, null::uuid[], null::text, 'product'::text, true::boolean, null::uuid[], null::numeric, null::numeric, null::jsonb),
    ('accesorios', '5443b130-cc28-45af-a420-cd500b288890'::uuid, array['164e46a9-3bfc-47d9-85ff-e911d96adacd']::uuid[], null, 'product', true, null, null, null, null),
    ('marca_y_precio', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, 'product', false, array['d9a1d1d9-2d3e-4735-aee2-a88fbf8782a2']::uuid[], 1000, 50000, null),
    ('medida_butilo', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, 'product', true, null, null, null, '{"tube_material": ["Butilo"], "bead_seat_diameter_mm": ["622"]}'),
    ('busqueda_camara', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, 'camara', null, true, null, null, null, null),
    ('servicios', '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, 'service', false, null, null, null, null),
    ('categoria_vacia', '5443b130-cc28-45af-a420-cd500b288890'::uuid, '{}'::uuid[], null, 'product', true, null, null, null, null)
)
select caso, filas, ahora = antes as igual,
       1/(case when ahora = antes then 1 else 0 end) as filtros_iguales
  from (
    select caso_args.caso,
           (select count(*) from public.get_public_product_facets_v2(caso_args.p_tenant_id, caso_args.p_category_ids, caso_args.p_search_term, caso_args.p_product_type, caso_args.p_only_in_stock, caso_args.p_brand_ids, caso_args.p_min_price, caso_args.p_max_price, caso_args.p_spec_filters)) as filas,
           (select md5(coalesce(string_agg(r::text, '|' order by r.rn), ''))
              from (select row_number() over () as rn, x.*
                      from public.get_public_product_facets_v2(caso_args.p_tenant_id, caso_args.p_category_ids, caso_args.p_search_term, caso_args.p_product_type, caso_args.p_only_in_stock, caso_args.p_brand_ids, caso_args.p_min_price, caso_args.p_max_price, caso_args.p_spec_filters) x) r) as ahora,
           (select md5(coalesce(string_agg(r::text, '|' order by r.rn), ''))
              from (select row_number() over () as rn, x.* from (
                with args as (
                    select
                      case
                        when caso_args.p_min_price is null then null
                        when caso_args.p_min_price >= 0 then caso_args.p_min_price
                        else null
                      end as min_price,
                      case
                        when caso_args.p_max_price is null then null
                        when caso_args.p_max_price >= 0 then caso_args.p_max_price
                        else null
                      end as max_price,
                      (
                        (caso_args.p_min_price is null or caso_args.p_min_price >= 0)
                        and (caso_args.p_max_price is null or caso_args.p_max_price >= 0)
                        and (
                          caso_args.p_min_price is null
                          or caso_args.p_max_price is null
                          or caso_args.p_min_price <= caso_args.p_max_price
                        )
                      ) as is_valid
                  ), spec_filters as materialized (
                    select e.key
                    from jsonb_each(coalesce(caso_args.p_spec_filters, '{}'::jsonb)) e
                    where jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) > 0
                  ), spec_scope as materialized (
                    -- Products satisfying every spec filter; null when there is none.
                    select case when exists (select 1 from spec_filters)
                      then coalesce((select array_agg(m.product_id) from public.spec_public_facet_matches_internal_v1(caso_args.p_tenant_id, caso_args.p_spec_filters) m), '{}'::uuid[])
                      else null::uuid[] end as ids
                  ), spec_values as materialized (
                    select * from public.spec_public_facet_values_internal_v1(caso_args.p_tenant_id)
                  ), canonical_universe as materialized (
                    -- Load the canonical search/type/publication/site-stock universe exactly
                    -- once. Every facet projection below is derived from this same
                    -- reservation-aware snapshot, preventing duplicate full catalog scans.
                    select product.*
                    from public.get_public_products(
                      p_tenant_id := caso_args.p_tenant_id,
                      p_category_ids := null,
                      p_search_term := caso_args.p_search_term,
                      p_product_type := caso_args.p_product_type,
                      p_only_in_stock := true,
                      p_sort_by := 'name',
                      p_limit := 2147483647,
                      p_offset := 0
                    ) product
                  ), available_universe as materialized (
                    select base.*
                    from canonical_universe base
                    where not coalesce(caso_args.p_only_in_stock, true)
                      or base.product_type = 'service'
                      or not coalesce(base.track_stock, true)
                      or coalesce(base.stock_quantity, base.inventory_qty, 0) > 0
                  ), selected_category_rows as materialized (
                    -- Brand and price metadata respect the active category selection. This is
                    -- the exact direct-ID predicate owned by the canonical product RPC, now
                    -- applied after its single unselected-universe call.
                    select base.*
                    from available_universe base
                    where caso_args.p_category_ids is null
                      or cardinality(caso_args.p_category_ids) = 0
                      or base.category_id = any(caso_args.p_category_ids)
                  ), category_filtered_rows as materialized (
                    -- Category options and the summary deliberately exclude the current
                    -- category selection while respecting every other active facet.
                    select base.*
                    from available_universe base
                    cross join args
                    cross join spec_scope
                    where args.is_valid
                      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
                      and (
                        caso_args.p_brand_ids is null
                        or cardinality(caso_args.p_brand_ids) = 0
                        or base.brand_id = any(caso_args.p_brand_ids)
                      )
                      and (args.min_price is null or base.price >= args.min_price)
                      and (args.max_price is null or base.price <= args.max_price)
                  ), category_rows as (
                    -- Keep direct counts for every active canonical category. The category
                    -- publication owner decides which IDs become visible filter options, so a
                    -- hidden descendant can still roll up into its visible published ancestor.
                    select
                      'category'::text as facet_key,
                      base.category_id::text as value_id,
                      nullif(btrim(canonical_category.name), '') as value_label,
                      count(*)::bigint as item_count,
                      null::numeric as range_min,
                      null::numeric as range_max
                    from category_filtered_rows base
                    join public.product_categories canonical_category
                      on canonical_category.id = base.category_id
                     and canonical_category.tenant_id = caso_args.p_tenant_id
                     and canonical_category.is_active = true
                    group by base.category_id, canonical_category.name
                  ), summary_rows as (
                    -- This is the exact total for the category-option universe. It includes
                    -- uncategorized products, so consumers must not derive "Todas" by summing
                    -- only the category rows.
                    select
                      'summary'::text as facet_key,
                      null::text as value_id,
                      null::text as value_label,
                      count(*)::bigint as item_count,
                      null::numeric as range_min,
                      null::numeric as range_max
                    from category_filtered_rows
                  ), brand_rows as (
                    -- Brand counts exclude the current brand selection, but respect every
                    -- other active facet so alternatives remain useful and truthful.
                    select
                      'brand'::text as facet_key,
                      base.brand_id::text as value_id,
                      coalesce(nullif(btrim(canonical_brand.name), ''), nullif(btrim(base.brand), ''))
                        as value_label,
                      count(*)::bigint as item_count,
                      null::numeric as range_min,
                      null::numeric as range_max
                    from selected_category_rows base
                    cross join args
                    cross join spec_scope
                    left join public.product_brands canonical_brand
                      on canonical_brand.id = base.brand_id
                     and (
                       canonical_brand.tenant_id is null
                       or canonical_brand.tenant_id = caso_args.p_tenant_id
                     )
                    where args.is_valid
                      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
                      and base.brand_id is not null
                      and (args.min_price is null or base.price >= args.min_price)
                      and (args.max_price is null or base.price <= args.max_price)
                    group by
                      base.brand_id,
                      coalesce(nullif(btrim(canonical_brand.name), ''), nullif(btrim(base.brand), ''))
                  ), price_rows as (
                    -- Price bounds exclude the current price range, but respect the selected
                    -- brands and every route/publication/availability filter.
                    select
                      'price'::text as facet_key,
                      null::text as value_id,
                      null::text as value_label,
                      count(*)::bigint as item_count,
                      min(base.price)::numeric as range_min,
                      max(base.price)::numeric as range_max
                    from selected_category_rows base
                    cross join args
                    cross join spec_scope
                    where args.is_valid
                      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
                      and (
                        caso_args.p_brand_ids is null
                        or cardinality(caso_args.p_brand_ids) = 0
                        or base.brand_id = any(caso_args.p_brand_ids)
                      )
                  ), spec_matches_by_key as materialized (
                    -- For a key the visitor already filters on, its alternatives are counted
                    -- against the other keys only (as brands do with the brand selection).
                    select k.key as excluded_key, m.product_id
                    from spec_filters k
                    cross join lateral public.spec_public_facet_matches_internal_v1(caso_args.p_tenant_id, caso_args.p_spec_filters, k.key) m
                  ), spec_scope_rows as materialized (
                    -- The products the visitor is looking at once every non-spec facet and
                    -- the spec filters apply: the denominator that says whether a spec facet
                    -- describes this collection or only a corner of it.
                    select base.id
                    from selected_category_rows base
                    cross join args
                    cross join spec_scope
                    where args.is_valid
                      and (
                        caso_args.p_brand_ids is null
                        or cardinality(caso_args.p_brand_ids) = 0
                        or base.brand_id = any(caso_args.p_brand_ids)
                      )
                      and (args.min_price is null or base.price >= args.min_price)
                      and (args.max_price is null or base.price <= args.max_price)
                      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
                  ), spec_coverage as materialized (
                    select v.spec_key, count(distinct s.id)::numeric as covered
                    from spec_scope_rows s
                    join spec_values v on v.product_id = s.id
                    group by v.spec_key
                  ), spec_rows as (
                    -- One row per value. range_min carries how many products of the scope
                    -- have this key at all, range_max how many products the scope holds, so
                    -- the client can hide a facet that describes a small corner only.
                    select
                      ('spec:' || v.spec_key || ':' || v.data_type || ':' || coalesce(v.unit, ''))::text as facet_key,
                      v.value_text as value_id,
                      v.spec_label as value_label,
                      count(distinct base.id)::bigint as item_count,
                      (select c.covered from spec_coverage c where c.spec_key = v.spec_key) as range_min,
                      (select count(*)::numeric from spec_scope_rows) as range_max
                    from selected_category_rows base
                    cross join args
                    cross join spec_scope
                    join spec_values v on v.product_id = base.id
                    where args.is_valid
                      and (
                        caso_args.p_brand_ids is null
                        or cardinality(caso_args.p_brand_ids) = 0
                        or base.brand_id = any(caso_args.p_brand_ids)
                      )
                      and (args.min_price is null or base.price >= args.min_price)
                      and (args.max_price is null or base.price <= args.max_price)
                      and (
                        case when exists (select 1 from spec_filters k where k.key = v.spec_key)
                          then exists (select 1 from spec_matches_by_key m where m.excluded_key = v.spec_key and m.product_id = base.id)
                          else spec_scope.ids is null or base.id = any(spec_scope.ids)
                        end
                      )
                    group by v.spec_key, v.data_type, v.unit, v.value_text, v.spec_label
                  )
                  select * from category_rows
                  where value_label is not null
                  union all
                  select * from brand_rows
                  where value_label is not null
                  union all
                  select * from price_rows
                  union all
                  select * from summary_rows
                  union all
                  select * from spec_rows
                  order by facet_key, value_label nulls first, value_id nulls first
                    ) x) r) as antes
      from cases caso_args) compared
 order by caso;

-- 4. As anon, within anon's limit. Last: the role and the limit hold until
-- the end of the read.
set local role anon;
set local statement_timeout = '3s';
select count(*) as productos_raiz
  from public.get_public_products_faceted_v2(
    p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890'::uuid, p_product_type := 'product', p_only_in_stock := true,
    p_sort_by := 'name', p_limit := 24, p_offset := 0);
select count(*) as filtros_raiz
  from public.get_public_product_facets_v2(
    p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890'::uuid, p_product_type := 'product', p_only_in_stock := true);
select count(*) as filtros_accesorios
  from public.get_public_product_facets_v2(
    p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890'::uuid, p_category_ids := array['164e46a9-3bfc-47d9-85ff-e911d96adacd']::uuid[],
    p_product_type := 'product', p_only_in_stock := true);
