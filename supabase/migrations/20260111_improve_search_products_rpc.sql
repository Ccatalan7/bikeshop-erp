-- Improve public store fuzzy search:
-- - Tokenized AND search ("camara 26" matches "Camara ... 26x...")
-- - Accent/diacritic insensitive via unaccent
-- - Matches across more fields (name/sku/description/brand/model/etc)
-- - Keeps multi-tenant safety by filtering tenant_id and remaining SECURITY INVOKER

create extension if not exists pg_trgm;
create extension if not exists unaccent;

create or replace function public.search_products(
  p_search_term text,
  p_tenant_id uuid,
  p_limit int default 10
)
returns setof public.products
language sql
security invoker
set search_path = public
as $$
  with q as (
    select
      unaccent(lower(coalesce(p_search_term, ''))) as term,
      array_remove(
        regexp_split_to_array(
          regexp_replace(unaccent(lower(coalesce(p_search_term, ''))), '[^a-z0-9]+', ' ', 'g'),
          '\\s+'
        ),
        ''
      ) as tokens
  )
  select p.*
  from public.products p
  cross join q
  where
    q.term <> ''
    and p.tenant_id = p_tenant_id
    and p.is_active = true
    and (coalesce(p.inventory_qty, 0) > 0 or coalesce(p.stock_quantity, 0) > 0)

    -- AND semantics across tokens, OR semantics across fields
    and (
      select bool_and(
          case
            -- Numeric-only tokens (e.g. "26") often represent sizes.
            -- Avoid matching them inside long identifier fields like SKU/barcodes,
            -- which can create false positives.
            when t ~ '^[0-9]+$' then
              (
                unaccent(lower(coalesce(p.name, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.description, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.brand, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.model, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.manufacturer, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.category_name, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.sku, ''))) ~ ('(^|[^0-9])' || t || '([^0-9]|$)')
                or unaccent(lower(coalesce(p.manufacturer_sku, ''))) ~ ('(^|[^0-9])' || t || '([^0-9]|$)')
              )
            else
              (
                unaccent(lower(coalesce(p.name, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.sku, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.description, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.brand, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.model, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.manufacturer, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.manufacturer_sku, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.barcode, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.gtin, ''))) like '%' || t || '%'
                or unaccent(lower(coalesce(p.category_name, ''))) like '%' || t || '%'
              )
          end
      )
      from unnest(q.tokens) as t
    )

  order by
    -- Prefer direct substring hits in the most relevant fields
    case when unaccent(lower(coalesce(p.sku, ''))) = q.term then 5 else 0 end desc,
    case when unaccent(lower(coalesce(p.name, ''))) like '%' || q.term || '%' then 4 else 0 end desc,
    case when unaccent(lower(coalesce(p.sku, ''))) like '%' || q.term || '%' then 3 else 0 end desc,
    case when unaccent(lower(coalesce(p.brand, ''))) like '%' || q.term || '%' then 2 else 0 end desc,

    -- Then trigram similarity
    greatest(
      similarity(unaccent(lower(coalesce(p.name, ''))), q.term),
      similarity(unaccent(lower(coalesce(p.sku, ''))), q.term),
      similarity(unaccent(lower(coalesce(p.description, ''))), q.term)
    ) desc,

    -- Stable ordering
    p.name asc

  limit greatest(p_limit, 0);
$$;

grant execute on function public.search_products(text, uuid, int) to anon;
grant execute on function public.search_products(text, uuid, int) to authenticated;
