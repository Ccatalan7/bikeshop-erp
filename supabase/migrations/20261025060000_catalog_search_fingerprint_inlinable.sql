-- 20261025060000: the search documents' fingerprint is inlined again.
--
-- 20261025040000 declared catalog_search_source_md5_v1 IMMUTABLE with
-- `set search_path`. Postgres does not inline a SQL function that has a SET
-- clause, nor an IMMUTABLE one whose body calls a STABLE function
-- (concat_ws is STABLE), so every public catalog read called it once per
-- listed product with the whole row: 44 ms for the 1,183 products against
-- 6.7 ms written inline (measured in production on 2026-10-25), with or
-- without a search term, because the eligible products are materialized
-- with it. The catalog without a term went from ~78 ms to ~110 ms that day.
--
-- Same expression, so every document built so far keeps matching: STABLE,
-- no SET, the built-ins named by schema.

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
    coalesce(p.description, '')
  ));
$function$;

alter function public.catalog_search_source_md5_v1(public.products) reset all;

revoke all on function public.catalog_search_source_md5_v1(public.products) from public, anon, authenticated;
