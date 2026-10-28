begin;

select no_plan();

-- Los documentos de búsqueda (20261025040000). El 2026-10-25 cada sugerencia
-- del buscador tardaba 1,3–2,0 s: en cada tecla la base volvía a normalizar
-- los textos, leer las fichas y cruzar el vocabulario de los 1.183 productos.
-- Ahora cada producto tiene su documento; uno viejo o ausente se calcula al
-- buscar, como antes, y la búsqueda responde lo mismo.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('d0c50000-0000-4000-8000-000000000001', 'Tienda de los documentos',
  'documentos@example.invalid', 'America/Santiago', true);

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, website_price_mode, category_name,
  brand, description
) values
  ('d0c50000-0000-4000-8000-000000000101', 'd0c50000-0000-4000-8000-000000000001',
   'Cámara Kenda 29 x 2.10', null, 'DOC-101', 6000, 2000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Cámaras', 'Kenda', null),
  ('d0c50000-0000-4000-8000-000000000102', 'd0c50000-0000-4000-8000-000000000001',
   'Cámara Maxxis Welter', null, 'DOC-102', 7000, 2500, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cámaras', 'Maxxis', null),
  ('d0c50000-0000-4000-8000-000000000103', 'd0c50000-0000-4000-8000-000000000001',
   'Cámara CST aro 20', null, 'DOC-103', 4000, 1000, 19,
   'product', false, 'inventory', true, 4, 4, true, true, true, 'exact', 'Cámaras', 'CST', null),
  ('d0c50000-0000-4000-8000-000000000104', 'd0c50000-0000-4000-8000-000000000001',
   'Llanta doble pared Weinmann', null, 'DOC-104', 18000, 7000, 19,
   'product', false, 'inventory', true, 1, 1, true, true, true, 'exact', 'Llantas', 'Weinmann',
   'Para freno de disco, 32 hoyos.');

-- A tube's sheet: its valve (an option) and its wheel as the ISO bead seat.
insert into public.spec_definitions (
  id, tenant_id, key, label, data_type, unit, allowed_values,
  is_filterable, is_customer_visible
) values
  ('d0c55000-0000-4000-8000-000000000001', 'd0c50000-0000-4000-8000-000000000001',
   'docs_test_valve', 'Válvula (prueba)', 'single_select', null,
   '["Francesa (Presta)", "Auto (Schrader)"]'::jsonb, true, true),
  ('d0c55000-0000-4000-8000-000000000002', 'd0c50000-0000-4000-8000-000000000001',
   'bead_seat_diameter_mm', 'Aro (prueba)', 'number', 'mm', '[]'::jsonb, true, true);

insert into public.spec_definition_values (
  id, spec_definition_id, code, label, sort_order, is_active
) values
  ('d0c55100-0000-4000-8000-000000000001', 'd0c55000-0000-4000-8000-000000000001',
   'presta', 'Francesa (Presta)', 1, true),
  ('d0c55100-0000-4000-8000-000000000002', 'd0c55000-0000-4000-8000-000000000001',
   'schrader', 'Auto (Schrader)', 2, true);

insert into public.spec_templates (id, tenant_id, key, name, technical_family, form_contract)
values ('d0c56000-0000-4000-8000-000000000001', 'd0c50000-0000-4000-8000-000000000001',
  'docs_test_tube', 'Cámara (prueba)', 'tube', '{}'::jsonb);

insert into public.spec_template_fields (template_id, spec_definition_id, section_key, sort_order)
values
  ('d0c56000-0000-4000-8000-000000000001', 'd0c55000-0000-4000-8000-000000000001', 'primary', 1),
  ('d0c56000-0000-4000-8000-000000000001', 'd0c55000-0000-4000-8000-000000000002', 'measurement', 2);

update public.products
set spec_template_id = 'd0c56000-0000-4000-8000-000000000001'
where id in (
  'd0c50000-0000-4000-8000-000000000101',
  'd0c50000-0000-4000-8000-000000000102',
  'd0c50000-0000-4000-8000-000000000104'
);

insert into public.spec_facts (
  id, tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, source, confirmed
) values
  ('d0c57000-0000-4000-8000-000000000001', 'd0c50000-0000-4000-8000-000000000001', 'product',
   'd0c50000-0000-4000-8000-000000000101', 'd0c55000-0000-4000-8000-000000000001', null, 'catalog', true),
  ('d0c57000-0000-4000-8000-000000000002', 'd0c50000-0000-4000-8000-000000000001', 'product',
   'd0c50000-0000-4000-8000-000000000101', 'd0c55000-0000-4000-8000-000000000002', 622, 'catalog', true),
  ('d0c57000-0000-4000-8000-000000000003', 'd0c50000-0000-4000-8000-000000000001', 'product',
   'd0c50000-0000-4000-8000-000000000102', 'd0c55000-0000-4000-8000-000000000001', null, 'catalog', true),
  ('d0c57000-0000-4000-8000-000000000004', 'd0c50000-0000-4000-8000-000000000001', 'product',
   'd0c50000-0000-4000-8000-000000000102', 'd0c55000-0000-4000-8000-000000000002', 559, 'catalog', true),
  ('d0c57000-0000-4000-8000-000000000005', 'd0c50000-0000-4000-8000-000000000001', 'product',
   'd0c50000-0000-4000-8000-000000000104', 'd0c55000-0000-4000-8000-000000000002', 622, 'catalog', true);

insert into public.spec_fact_values (fact_id, value_id, position) values
  ('d0c57000-0000-4000-8000-000000000001', 'd0c55100-0000-4000-8000-000000000001', 0),
  ('d0c57000-0000-4000-8000-000000000003', 'd0c55100-0000-4000-8000-000000000002', 0);

set local session_replication_role = origin;

create function pg_temp.ranked(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    'd0c50000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

create function pg_temp.doc(p_sku text)
returns public.catalog_search_documents
language sql
as $$
  select d.*
  from public.catalog_search_documents d
  join public.products p on p.id = d.product_id
  where d.tenant_id = 'd0c50000-0000-4000-8000-000000000001' and p.sku = p_sku
$$;

-- The store's words, which a misspelt word («camra») is corrected against
-- (20261028020000), first: only the documents differ below.
select public.catalog_search_words_rebuild_v1('d0c50000-0000-4000-8000-000000000001');

-- Computed at search time (no document yet), then from the documents.
create temp table search_before as
select t.term, pg_temp.ranked(t.term) as skus
from unnest(array[
  'camara', 'camara presta', 'camara francesa', 'camara 29', 'camara aro 26',
  'presta', 'schrader', 'llanta 29', 'llanta disco', 'kenda', 'welter', 'camra'
]) as t(term);

select is(pg_temp.ranked('camara 29'), array['DOC-101'],
  'a tube''s sheet answers «29» (bead 622) before any document exists');
select is(pg_temp.ranked('camara presta'), array['DOC-101'],
  'and its valve, as the store shows it');

select ok(public.catalog_search_documents_refresh_v1() >= 4,
  'the refresh builds a document for every listed product');
select is(
  (select count(*)::integer from public.catalog_search_documents
    where tenant_id = 'd0c50000-0000-4000-8000-000000000001'),
  4, 'one document per product');
select ok((pg_temp.doc('DOC-101')).spec_n like '%presta%',
  'the document keeps the spec sheet''s text');
select ok('bead:622' = any ((pg_temp.doc('DOC-101')).measures),
  'and every measure it states');
select is(public.catalog_search_documents_refresh_v1(), 0,
  'a second refresh has nothing to build');

select results_eq(
  'select term, skus from search_before order by term',
  'select term, pg_temp.ranked(term) from search_before order by term',
  'from the documents, every search lists the same, in the same order'
);

-- A product renamed: its document no longer matches it, so the search
-- computes it until the refresh builds it again.
update public.products set name = 'Cámara CST aro 16'
where id = 'd0c50000-0000-4000-8000-000000000103';
select is(pg_temp.ranked('camara 16'), array['DOC-103'],
  'a renamed product is found by its new name at once');
select ok((pg_temp.doc('DOC-103')).name_n like '%20%',
  'its old document stays until the refresh');
select is(public.catalog_search_documents_refresh_v1(), 1,
  'the refresh rebuilds only that one');
select ok((pg_temp.doc('DOC-103')).name_n like '%16%', 'with the new name');

-- A spec sheet changed: the product's document is forgotten.
update public.spec_facts set value_number = 584
where id = 'd0c57000-0000-4000-8000-000000000004';
select ok(pg_temp.doc('DOC-102') is null,
  'a changed spec fact forgets its product''s document');
select ok(pg_temp.doc('DOC-101') is not null, 'and only that one');
select is(pg_temp.ranked('camara 27.5'), array['DOC-102'],
  'the search reads the new sheet at once');
delete from public.spec_fact_values
where fact_id = 'd0c57000-0000-4000-8000-000000000001';
select ok(pg_temp.doc('DOC-101') is null,
  'removing an option value forgets its product''s document too');

-- What every document reads changed: all are forgotten.
select public.catalog_search_documents_refresh_v1();
insert into public.catalog_search_terms (tenant_id, concept, kind, terms, broader, phrases)
values ('d0c50000-0000-4000-8000-000000000001', 'docs_test_concept', 'attribute',
  array['docstest'], array[]::text[], array[]::text[]);
select is(
  (select count(*)::integer from public.catalog_search_documents
    where tenant_id = 'd0c50000-0000-4000-8000-000000000001'),
  0, 'a change to the vocabulary forgets every document');

-- The fingerprint is inlined into the catalog reads (20261025060000): a SQL
-- function with a SET clause, or IMMUTABLE over STABLE concat_ws, was called
-- once per listed product on every read.
select ok(
  (select p.provolatile = 's' and p.proconfig is null and l.lanname = 'sql'
     from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = 'public.catalog_search_source_md5_v1(public.products)'::regprocedure),
  'the fingerprint can be inlined');

-- Closed to the public key, rebuilt every minute.
select ok(
  not has_table_privilege('anon', 'public.catalog_search_documents', 'select')
  and not has_table_privilege('authenticated', 'public.catalog_search_documents', 'select'),
  'the documents are not readable with the public key');
select ok(
  not has_function_privilege('anon', 'public.catalog_search_documents_refresh_v1(integer)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_documents_compute_internal_v1(uuid,uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'public.catalog_search_documents_refresh_v1(integer)', 'execute'),
  'nor built with it');
select ok(
  exists (select 1 from cron.job where jobname = 'catalog_search_documents_refresh' and schedule = '* * * * *'),
  'the refresh runs every minute');

select * from finish();

rollback;
