-- Card photos at the size a card shows them, and the product page of a
-- product without a SKU, for the HTML storefront
-- (docs/architecture/storefront-html-migration-plan.md).
--
-- 1. Thumbnails. Catalog and category cards showed the 1.200 px photo
--    (75–120 KB each) in a 236 px column, and a slow phone fetched ~16 of them
--    at once: `/productos` painted its first card at ~4,4 s. The owner chose
--    the free option on 2026-10-05: keep a 400 px and an 800 px copy of each
--    card photo next to it, instead of paying for Supabase image
--    transformations. One job makes them for every photo a public card uses,
--    whatever path uploaded it and wherever it is hosted
--    (scripts/generate_public_image_thumbnails.dart, run by the store build);
--    this table is its record of which copies exist for which photo. A photo
--    the job has not reached yet has no row, and its card keeps the large
--    photo. The storefront reads the record through
--    get_public_image_thumbnails_v1; nothing else reads or writes the table.
--
-- 2. get_public_product_page_v2 reads a product by SKU or by id. The
--    canonical route of a product without a SKU is `/productos/<uuid>`
--    (product_url.dart), and the page read went only by SKU, so the server
--    could not draw it (Codex review of opening the routes, 2026-10-05; 0 of
--    1.682 products lacked a SKU that day). v1 stays as a call to v2 so the
--    running server keeps answering while the new one is published.

create table if not exists public.public_image_thumbnails (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  -- The photo as a public card links it.
  source_url text not null check (source_url ~ '^https?://'),
  -- ETag, or length and date when the host gives no ETag: a photo replaced
  -- at the same URL is made again.
  source_signature text not null check (length(source_signature) > 0),
  source_width integer not null check (source_width > 0),
  source_height integer not null check (source_height > 0),
  -- [{"width": 400, "height": 300, "url": "https://…"}, …], narrower than the
  -- photo only; empty when the photo is already that small.
  variants jsonb not null default '[]'::jsonb
    check (jsonb_typeof(variants) = 'array'),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, source_url)
);

comment on table public.public_image_thumbnails is
  'Smaller copies of the photos public product cards show, made by scripts/generate_public_image_thumbnails.dart. Read only through get_public_image_thumbnails_v1.';

alter table public.public_image_thumbnails enable row level security;
revoke all on table public.public_image_thumbnails
  from public, anon, authenticated;
grant select, insert, update, delete on table public.public_image_thumbnails
  to service_role;

create or replace function public.get_public_image_thumbnails_v1(
  p_tenant_id uuid,
  p_urls text[]
)
returns table (
  source_url text,
  source_width integer,
  source_height integer,
  variants jsonb
)
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  -- Only the photos asked about, at most a page of cards' worth: the copies
  -- are public files, but the record is not a list to walk.
  select t.source_url, t.source_width, t.source_height, t.variants
    from public.public_image_thumbnails t
   where t.tenant_id = p_tenant_id
     and t.source_url = any (p_urls[1:200]);
$$;

comment on function public.get_public_image_thumbnails_v1(uuid, text[]) is
  'The smaller copies that exist for the given card photos of a store (at most 200 per call). A photo without a row keeps its original size.';

revoke all on function public.get_public_image_thumbnails_v1(uuid, text[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_image_thumbnails_v1(uuid, text[])
  to anon, authenticated, service_role;

create or replace function public.get_public_product_page_v2(
  p_tenant_id uuid,
  p_sku text default null,
  p_product_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = public, pg_temp
stable
as $$
  with base as (
    select to_jsonb(product) - 'cost' - 'total_count' as row,
           product.id,
           product.category_id,
           product.brand_id
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := case
               when p_product_id is not null then array[p_product_id]
             end,
             p_sku := case when p_product_id is null then p_sku end,
             p_only_in_stock := false,
             p_limit := 1
           ) product
     -- Without a SKU or an id the listing would return any product.
     where p_product_id is not null or nullif(btrim(p_sku), '') is not null
     limit 1
  ),
  related as (
    select to_jsonb(other) - 'cost' - 'total_count' - 'ordinality' as row,
           other.id,
           other.brand_id,
           other.ordinality as position
      from base
      cross join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_category_ids := array[base.category_id],
             p_only_in_stock := true,
             p_limit := 9
           ) with ordinality other
     where base.category_id is not null
       and other.id <> base.id
  ),
  website as (
    select p.id, to_jsonb(fields) as fields
      from public.products p
      cross join lateral (
        select p.is_set, p.set_type, p.parent_set_id, p.component_label,
               p.component_position, p.website_name, p.website_price,
               p.website_description, p.website_seo_title,
               p.website_seo_description, p.website_search_terms,
               p.website_merchant_title, p.website_merchant_description,
               p.website_merchant_brand, p.website_merchant_gtin,
               p.website_merchant_mpn, p.website_google_product_category,
               p.website_image_url, p.website_image_url_optimized,
               p.website_image_urls, p.price_currency
      ) fields
     where p.tenant_id = p_tenant_id
       and p.id in (select id from base union all select id from related)
  )
  select jsonb_build_object(
    'product', base.row || coalesce(
      (select website.fields from website where website.id = base.id),
      '{}'::jsonb),
    -- Raw rows of this store's or global brands: the client decides with
    -- canonicalPublicProductBrandNames, the rule the Flutter store applies.
    'brand_rows', coalesce((
      select jsonb_agg(to_jsonb(brand))
        from (
          select b.id, b.name, b.tenant_id, b.is_active
            from public.product_brands b
           where b.is_active
             and (b.tenant_id = p_tenant_id or b.tenant_id is null)
             and b.id in (
               select base.brand_id
               union
               select related.brand_id from related
             )
        ) brand
    ), '[]'::jsonb),
    'specs', coalesce((
      select jsonb_agg(to_jsonb(spec))
        from public.get_public_product_technical_specs(p_tenant_id, base.id) spec
    ), '[]'::jsonb),
    'related', coalesce((
      select jsonb_agg(
               related.row || coalesce(website.fields, '{}'::jsonb)
               order by related.position)
        from related
        left join website on website.id = related.id
    ), '[]'::jsonb)
  )
    from base;
$$;

comment on function public.get_public_product_page_v2(uuid, text, uuid) is
  'A public product page in one read, by SKU or by id (the canonical route of a product without SKU): the product as get_public_products publishes it plus its website fields, this store''s or global brand rows, technical sheet and in-stock products of its category with the same website fields. No row when the product is not public or neither key is given. Security invoker over existing public reads.';

revoke all on function public.get_public_product_page_v2(uuid, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_page_v2(uuid, text, uuid)
  to anon, authenticated, service_role;

create or replace function public.get_public_product_page_v1(
  p_tenant_id uuid,
  p_sku text
)
returns jsonb
language sql
security invoker
set search_path = public, pg_temp
stable
as $$
  select public.get_public_product_page_v2(p_tenant_id, p_sku, null);
$$;

comment on function public.get_public_product_page_v1(uuid, text) is
  'Kept for a storefront server published before get_public_product_page_v2; the same read by SKU.';

notify pgrst, 'reload schema';
