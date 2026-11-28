-- One cheap question tells the store server whether any public page changed.
--
-- vinabike.cl built every page from scratch on every visit: the database
-- reads take ~0.4 s of a ~0.45 s answer (2026-11-28), although between two
-- visits nothing the page shows had changed. The server now keeps each page
-- it built and asks this function, at most every couple of seconds, whether
-- what the pages show is still the same; a page is built again only when the
-- stamp moved. It answers in about a millisecond and reads no page data.
--
-- The stamp has two parts:
--   * what the site editor writes (blocks, pages, settings, menus), row by
--     row and in the caller's own snapshot (each row's id and its version:
--     xmin and ctid): an edit is seen by the very next question;
--   * for every table a public page read touches, how many rows were ever
--     written to it (the statistics counters). A counter moves after the
--     writing transaction commits (at once, or within ~10 s when its session
--     had just reported), never before it: a page built after reading the
--     stamp is at least as new as the stamp.
--
-- It says that something changed, never what: an md5. The counters are
-- shared by every tenant, so another shop's sale also moves the stamp; that
-- only builds a page once more.
--
-- The list is every table reached from the reads the kept pages make
-- (shell, home, catalog, product page, their completions). The read-back
-- supabase/manual_checks/verify_public_storefront_change_stamp.sql follows
-- the function bodies and fails when one of them reads a table the list does
-- not name: run it after adding a read to a public page. A table it misses
-- is not shown stale forever: the server builds every kept page again after
-- a quarter of an hour.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.public_storefront_watched_tables_v1()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    -- Catalog: products, their groups, prices and stock.
    'products',
    'product_brands',
    'product_categories',
    'categories',
    'product_models',
    'product_model_members',
    'product_set_components',
    'product_url_aliases',
    'featured_products',
    'public_image_thumbnails',
    -- Technical sheets and the filters built from them.
    'spec_facts',
    'spec_fact_values',
    'spec_definitions',
    'spec_definition_values',
    'spec_templates',
    'spec_template_fields',
    'product_spec_references',
    'category_tech_mappings',
    -- What goes with a product and how the catalog is searched.
    'catalog_part_affinity',
    'catalog_product_popularity',
    'catalog_search_documents',
    'catalog_search_terms',
    'catalog_search_words',
    -- Sold out: on order, with the supplier's own availability.
    'product_on_order_terms',
    'supplier_catalog_feeds',
    'supplier_catalog_feed_items',
    'customer_quote_sold_out_brands',
    'customer_quote_purchase_orders',
    'purchase_invoices',
    -- Stock an online order holds.
    'online_orders',
    'online_order_items',
    'online_order_inventory_reservations',
    'orders',
    'bikes',
    -- Shipping tiers named on every page.
    'online_shipping_zones',
    'online_shipping_rate_tiers',
    'online_shipping_bike_categories',
    -- The shop and its site.
    'tenants',
    'website_blocks',
    'website_pages',
    'website_settings',
    'website_navigation'
  ]::text[];
$$;

comment on function private.public_storefront_watched_tables_v1() is
  'Every public table a kept page of the HTML storefront reads. get_public_storefront_change_stamp_v1 counts their writes; verify_public_storefront_change_stamp.sql fails when a public page read reaches a table missing here.';

revoke all on function private.public_storefront_watched_tables_v1()
  from public, anon, authenticated, service_role;

create or replace function public.get_public_storefront_change_stamp_v1(
  p_tenant_id uuid
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.md5(
    coalesce((
      select pg_catalog.string_agg(b.id::text || ':' || b.xmin::text
                                   || ':' || b.ctid::text, ','
                                   order by b.id)
        from public.website_blocks b
       where b.tenant_id = p_tenant_id
    ), '')
    || '|' ||
    coalesce((
      select pg_catalog.string_agg(p.id::text || ':' || p.xmin::text
                                   || ':' || p.ctid::text, ','
                                   order by p.id)
        from public.website_pages p
       where p.tenant_id = p_tenant_id
    ), '')
    || '|' ||
    coalesce((
      select pg_catalog.string_agg(s.key || ':' || s.xmin::text
                                   || ':' || s.ctid::text, ','
                                   order by s.key)
        from public.website_settings s
       where s.tenant_id = p_tenant_id
    ), '')
    || '|' ||
    coalesce((
      select pg_catalog.string_agg(n.id::text || ':' || n.xmin::text
                                   || ':' || n.ctid::text, ','
                                   order by n.id)
        from public.website_navigation n
       where n.tenant_id = p_tenant_id
    ), '')
    || '|' ||
    coalesce((
      select pg_catalog.string_agg(
               watched.name || ':' || (
                 pg_catalog.pg_stat_get_tuples_inserted(c.oid)
                 + pg_catalog.pg_stat_get_tuples_updated(c.oid)
                 + pg_catalog.pg_stat_get_tuples_deleted(c.oid)
               )::text,
               ',' order by watched.name)
        from pg_catalog.unnest(
               private.public_storefront_watched_tables_v1()
             ) as watched(name)
        join pg_catalog.pg_class c
          on c.relname = watched.name
         and c.relnamespace = 'public'::pg_catalog.regnamespace
    ), '')
  );
$$;

comment on function public.get_public_storefront_change_stamp_v1(uuid) is
  'Whether anything a public page of the store shows changed: an md5 over the site editor''s rows (id and row version, in the caller''s snapshot) and the write counters of every table the public page reads touch. The store server keeps the pages it built while this stamp stands. It says that something changed, never what.';

revoke all on function public.get_public_storefront_change_stamp_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_storefront_change_stamp_v1(uuid)
  to anon, authenticated, service_role;
