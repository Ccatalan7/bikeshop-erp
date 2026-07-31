-- Public catalog availability: replace an N+1 with a set-based join.
--
-- `get_public_products` asked the inner catalog query for the ENTIRE result set
-- (`p_limit => 2147483647`), then called the plpgsql function
-- `online_product_available_quantity()` once per row before filtering by the
-- publication stock policy and paginating down to one page. That function
-- re-`SELECT`s the whole `products` row the outer query already had, so a
-- 553-product catalog cost 553 wide row fetches to return 20 items.
--
-- Measured on production before this change, warm cache, 20 rows returned:
--
--   inner catalog query alone   1 677 buffers    ~250 ms
--   get_public_products         9 311 buffers    ~725 ms  + 169 temp blocks
--
-- so roughly 7 600 buffers and 475 ms were per-row overhead that grows linearly
-- with catalog size. Cold or under concurrency it crossed the per-role
-- `statement_timeout` (anon 3 s, authenticated 8 s) and the storefront rendered
-- "No pudimos cargar el catálogo" from a `57014` cancellation. Note that the
-- reservations table held a single row at the time: the cost was never the
-- reservation maths, it was the per-row function call itself.
--
-- The availability contract is unchanged and is reproduced exactly:
--   * a service, an `is_service` row, or a row that does not track stock keeps
--     its raw stock and never consults reservations;
--   * a set product is limited by its scarcest component, floored at zero, and
--     a set with no components resolves to zero;
--   * any other tracked product is its stock minus active, unexpired
--     reservations, floored at zero.
--
-- `online_product_available_quantity()` is intentionally left in place: it is
-- the single-product answer used elsewhere, and it stays the canonical
-- definition of the rule this query now evaluates in bulk.

create or replace function public.get_public_products(
  p_tenant_id uuid,
  p_category_ids uuid[] default null::uuid[],
  p_product_ids uuid[] default null::uuid[],
  p_sku text default null::text,
  p_search_term text default null::text,
  p_product_type text default null::text,
  p_only_in_stock boolean default true,
  p_sort_by text default 'name'::text,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table(
  id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric,
  cost numeric, inventory_qty integer, stock_quantity integer, image_url text,
  image_url_optimized text, image_urls text[], description text,
  website_description text, category text, category_id uuid,
  category_name text, brand_id uuid, brand text, model text, manufacturer text,
  manufacturer_sku text, gtin text, product_type text, track_stock boolean,
  is_active boolean, is_published boolean, show_on_website boolean,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  total_count bigint
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with policy as (
    select case lower(coalesce(
      nullif(btrim(coalesce((
        select setting.value
          from public.website_settings setting
         where setting.tenant_id = p_tenant_id
           and setting.key = 'product_visibility_stock_policy'
         limit 1
      ), '')), ''),
      case when p_only_in_stock then 'available_only' else 'all' end
    ))
      when 'all' then 'all'
      when 'both' then 'all'
      when 'out_of_stock_only' then 'out_of_stock_only'
      when 'out_of_stock' then 'out_of_stock_only'
      when 'sin_stock' then 'out_of_stock_only'
      else 'available_only'
    end as stock_policy
  ), raw_rows as (
    select raw.*
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id,
        p_category_ids,
        p_product_ids,
        p_sku,
        p_search_term,
        p_product_type,
        false,
        p_sort_by,
        2147483647,
        0
      ) with ordinality as raw
  ), candidate as (
    -- One join instead of one function call per row. `is_set` and `is_service`
    -- are the only facts the inner catalog query does not already return.
    select r.id,
           r.tenant_id,
           r.stock_quantity,
           r.inventory_qty,
           coalesce(product.is_set, false) as is_set,
           coalesce(product.is_service, false) as is_service
      from raw_rows r
      join public.products product
        on product.id = r.id
       and product.tenant_id = r.tenant_id
     where r.product_type is distinct from 'service'
       and coalesce(r.track_stock, true)
  ), reserved as (
    -- Aggregated once for the whole tenant, then joined. Covers both the
    -- products themselves and the components of any set among them.
    select reservation.product_id,
           sum(reservation.quantity)::integer as quantity
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = p_tenant_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
     group by reservation.product_id
  ), simple_availability as (
    select candidate.id,
           greatest(
             coalesce(candidate.stock_quantity, candidate.inventory_qty, 0)
               - coalesce(reserved.quantity, 0),
             0
           ) as available_quantity
      from candidate
      left join reserved on reserved.product_id = candidate.id
     where not candidate.is_set
       and not candidate.is_service
  ), set_availability as (
    -- A set is limited by its scarcest component. An inner join means a set
    -- with no components produces no row here and resolves to zero below,
    -- which is what the per-row function returned for that case.
    select candidate.id,
           min(greatest(floor(
             (
               coalesce(component.stock_quantity, component.inventory_qty, 0)
               - coalesce(component_reserved.quantity, 0)
             )::numeric / set_component.quantity_in_set
           ), 0))::integer as available_quantity
      from candidate
      join public.product_set_components set_component
        on set_component.tenant_id = candidate.tenant_id
       and set_component.set_product_id = candidate.id
      join public.products component
        on component.id = set_component.component_product_id
       and component.tenant_id = set_component.tenant_id
      left join reserved component_reserved
        on component_reserved.product_id = component.id
     where candidate.is_set
       and not candidate.is_service
     group by candidate.id
  ), availability as (
    select id, available_quantity from simple_availability
    union all
    select id, available_quantity from set_availability
  ), base_rows as (
    select r.*,
           case
             when r.product_type = 'service'
               or not coalesce(r.track_stock, true)
               or coalesce(service_like.is_service, false)
               then greatest(coalesce(r.stock_quantity, r.inventory_qty, 0), 0)
             else coalesce(availability.available_quantity, 0)
           end as available_quantity
      from raw_rows r
      left join availability on availability.id = r.id
      left join candidate service_like on service_like.id = r.id
  ), filtered as (
    select base.*
      from base_rows base
      cross join policy
     where policy.stock_policy = 'all'
        or base.product_type = 'service'
        or not coalesce(base.track_stock, true)
        or (
          policy.stock_policy = 'available_only'
          and base.available_quantity > 0
        )
        or (
          policy.stock_policy = 'out_of_stock_only'
          and base.available_quantity <= 0
        )
  ), paged as (
    select filtered.*,
           count(*) over() as filtered_total
      from filtered
     order by filtered.ordinality
     limit greatest(coalesce(p_limit, 20), 0)
     offset greatest(coalesce(p_offset, 0), 0)
  )
  select
    paged.id,
    paged.tenant_id,
    paged.name,
    paged.sku,
    paged.barcode,
    paged.price,
    paged.cost,
    case
      when paged.product_type = 'service'
        or not coalesce(paged.track_stock, true)
        then paged.inventory_qty
      else paged.available_quantity
    end as inventory_qty,
    case
      when paged.product_type = 'service'
        or not coalesce(paged.track_stock, true)
        then paged.stock_quantity
      else paged.available_quantity
    end as stock_quantity,
    paged.image_url,
    paged.image_url_optimized,
    paged.image_urls,
    paged.description,
    paged.website_description,
    paged.category,
    paged.category_id,
    paged.category_name,
    paged.brand_id,
    paged.brand,
    paged.model,
    paged.manufacturer,
    paged.manufacturer_sku,
    paged.gtin,
    paged.product_type,
    paged.track_stock,
    paged.is_active,
    paged.is_published,
    paged.show_on_website,
    paged.created_at,
    paged.updated_at,
    paged.filtered_total as total_count
  from paged
  order by paged.ordinality;
$function$;
