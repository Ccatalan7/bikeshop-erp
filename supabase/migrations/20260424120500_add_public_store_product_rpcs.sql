-- Public storefront product RPCs.
--
-- These functions return only storefront-safe product columns and require a
-- tenant id argument, so the Flutter public store no longer needs to query the
-- products table directly or download the full catalog for client-side paging.

begin;

drop function if exists public.search_public_products(text, uuid, integer);

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
      trim(coalesce(p_search_term, '')) as term,
      regexp_split_to_array(lower(trim(coalesce(p_search_term, ''))), '\s+')
        as tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type
  ),
  filtered as (
    select p.*
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
      and (
        a.term = ''
        or not exists (
          select 1
          from unnest(a.tokens) token
          where token <> ''
            and lower(
              concat_ws(
                ' ',
                p.name,
                p.sku,
                p.barcode,
                p.description,
                p.website_description,
                p.brand,
                p.model,
                p.manufacturer,
                p.manufacturer_sku,
                p.gtin
              )
            ) not like '%' || token || '%'
        )
      )
  ),
  counted as (
    select p.*, count(*) over() as row_total
    from filtered p
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
  cross join args a
  order by
    case when a.sort_by = 'price_asc' then p.price end asc nulls last,
    case when a.sort_by = 'price_desc' then p.price end desc nulls last,
    case when a.sort_by = 'newest' then p.created_at end desc nulls last,
    p.name asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$$;

grant execute on function public.get_public_products(
  uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer
) to anon, authenticated;

create or replace function public.search_public_products(
  p_search_term text,
  p_tenant_id uuid,
  p_limit integer default 10
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
  updated_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    gp.id,
    gp.tenant_id,
    gp.name,
    gp.sku,
    gp.barcode,
    gp.price,
    gp.cost,
    gp.inventory_qty,
    gp.stock_quantity,
    gp.image_url,
    gp.image_url_optimized,
    gp.image_urls,
    gp.description,
    gp.website_description,
    gp.category,
    gp.category_id,
    gp.category_name,
    gp.brand_id,
    gp.brand,
    gp.model,
    gp.manufacturer,
    gp.manufacturer_sku,
    gp.gtin,
    gp.product_type,
    gp.track_stock,
    gp.is_active,
    gp.is_published,
    gp.show_on_website,
    gp.created_at,
    gp.updated_at
  from public.get_public_products(
    p_tenant_id := p_tenant_id,
    p_search_term := p_search_term,
    p_only_in_stock := true,
    p_sort_by := 'name',
    p_limit := p_limit,
    p_offset := 0
  ) gp;
$$;

grant execute on function public.search_public_products(text, uuid, integer)
  to anon, authenticated;

create or replace function public.get_public_featured_products(
  p_tenant_id uuid,
  p_limit integer default 10
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
  updated_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
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
    p.updated_at
  from public.featured_products fp
  join public.products p on p.id = fp.product_id
  where fp.tenant_id = p_tenant_id
    and fp.active = true
    and p.tenant_id = p_tenant_id
    and p.is_active = true
    and coalesce(p.is_published, false) = true
    and coalesce(p.show_on_website, false) = true
  order by fp.order_index asc, p.name asc
  limit greatest(coalesce(p_limit, 10), 0);
$$;

grant execute on function public.get_public_featured_products(uuid, integer)
  to anon, authenticated;

create or replace function public.get_public_product_category_counts(
  p_tenant_id uuid,
  p_product_type text default null,
  p_only_in_stock boolean default true
)
returns table (
  category_id uuid,
  product_count bigint
)
language sql
security definer
set search_path = public
stable
as $$
  select p.category_id, count(*) as product_count
  from public.products p
  where p.tenant_id = p_tenant_id
    and p.is_active = true
    and coalesce(p.is_published, false) = true
    and coalesce(p.show_on_website, false) = true
    and (
      nullif(trim(coalesce(p_product_type, '')), '') is null
      or p.product_type = nullif(trim(coalesce(p_product_type, '')), '')
    )
    and (
      not p_only_in_stock
      or p.product_type = 'service'
      or coalesce(p.track_stock, true) = false
      or greatest(coalesce(p.inventory_qty, 0), coalesce(p.stock_quantity, 0)) > 0
    )
  group by p.category_id;
$$;

grant execute on function public.get_public_product_category_counts(
  uuid, text, boolean
) to anon, authenticated;

commit;
