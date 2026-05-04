-- Improve public storefront product search relevance.
-- Deployed to production on 2026-05-03 and mirrored in core_schema.sql.

create extension if not exists unaccent;
create extension if not exists pg_trgm;

create or replace function public.get_public_products(
  p_tenant_id uuid,
  p_category_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_sku text default null,
  p_search_term text default null,
  p_product_type text default null,
  p_only_in_stock boolean default true,
  p_sort_by text default 'name',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  tenant_id uuid,
  name text,
  sku text,
  barcode text,
  price numeric,
  cost numeric,
  inventory_qty integer,
  stock_quantity integer,
  image_url text,
  image_url_optimized text,
  image_urls text[],
  description text,
  website_description text,
  category text,
  category_id uuid,
  category_name text,
  brand_id uuid,
  brand text,
  model text,
  manufacturer text,
  manufacturer_sku text,
  gtin text,
  product_type text,
  track_stock boolean,
  is_active boolean,
  is_published boolean,
  show_on_website boolean,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
security definer
set search_path = public
stable
as $$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type
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
      trim(regexp_replace(unaccent(lower(coalesce(p.name, ''))), '[^a-z0-9]+', ' ', 'g')) as name_n,
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
        not p_only_in_stock
        or p.product_type = 'service'
        or coalesce(p.track_stock, true) = false
        or greatest(coalesce(p.inventory_qty, 0), coalesce(p.stock_quantity, 0)) > 0
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
        case when m.product_type = 'service' and not m.service_intent then -260 else 0 end
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
    p.name,
    p.sku,
    p.barcode,
    p.price,
    0::numeric as cost,
    p.inventory_qty,
    p.stock_quantity,
    p.image_url,
    p.image_url_optimized,
    p.image_urls,
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
    case when p.term = '' and p.sort_by = 'price_asc' then p.price end asc nulls last,
    case when p.term = '' and p.sort_by = 'price_desc' then p.price end desc nulls last,
    case when p.term = '' and p.sort_by = 'newest' then p.created_at end desc nulls last,
    p.name asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$$;

grant execute on function public.get_public_products(
  uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer
) to anon, authenticated;