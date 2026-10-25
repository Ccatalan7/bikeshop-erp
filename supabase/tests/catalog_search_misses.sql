begin;

select no_plan();

-- What visitors search and do not find, and the store's own words
-- (20261024070000).

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('a6090000-0000-4000-8000-000000000001', 'Tienda que aprende',
   'aprende@example.invalid', 'America/Santiago', true),
  ('a6090000-0000-4000-8000-000000000002', 'Otra tienda',
   'otra@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value)
values ('a6090000-0000-4000-8000-000000000001',
  'product_visibility_stock_policy', 'available_only');

insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website, website_price_mode, category_name
) values
  ('a6090000-0000-4000-8000-000000000101', 'a6090000-0000-4000-8000-000000000001',
   'Maza trasera Shimano 32 hoyos', 'A609-101', 25000, 1000, 19, 'product',
   false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Mazas'),
  ('a6090000-0000-4000-8000-000000000102', 'a6090000-0000-4000-8000-000000000001',
   'Pata de cambio Merida', 'A609-102', 9000, 1000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact', 'Patas de cambio');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a6090000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'staff-aprende@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', 'a6090000-0000-4000-8000-000000000001'),
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values ('a6090000-0000-4000-8000-000000000091',
  'a6090000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

set local session_replication_role = origin;

-- ---------------------------------------------------------------- recording
set local role anon;

select lives_ok(
  $$select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', '  Tablero   de herramientas ')$$,
  'the public key records a search that found nothing'
);
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'tablero de herramientas');
-- Found by the store: nothing stays.
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'maza');
-- Found only out of stock: it stays, with how many.
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'pata de cambio');
-- What could be someone's data never stays.
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'juan@correo.cl');
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', '+56 9 1234 5678');
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', '12.345.678-9');
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'www.algo.cl');
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'x');
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'una frase muy larga con muchas palabras que nadie busca nunca');

select throws_ok(
  $$select count(*) from public.catalog_search_misses$$,
  '42501',
  null,
  'the public key cannot read what was searched'
);

reset role;

select is(
  (select array_agg(m.term || ':' || m.searches || ':' || m.out_of_stock order by m.term)
     from public.catalog_search_misses m
    where m.tenant_id = 'a6090000-0000-4000-8000-000000000001'),
  array['pata de cambio:1:1', 'tablero de herramientas:2:0'],
  'only what the store lists nothing for stays, counted, with what is out of stock'
);
select is(
  (select m.typed from public.catalog_search_misses m
    where m.tenant_id = 'a6090000-0000-4000-8000-000000000001'
      and m.term = 'tablero de herramientas'),
  'tablero de herramientas',
  'the text is kept as written, trimmed and in lower case'
);

-- --------------------------------------------------------------- the ERP
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a6090000-0000-4000-8000-000000000091', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'a6090000-0000-4000-8000-000000000091', true);
set local role authenticated;

select throws_ok(
  $$select * from public.catalog_search_misses_v1('a6090000-0000-4000-8000-000000000002')$$,
  '42501',
  'catalog_tenant_forbidden',
  'another store''s searches are not read'
);

select is(
  (select array_agg(r.typed || ':' || r.state order by r.searches desc)
     from public.catalog_search_misses_v1('a6090000-0000-4000-8000-000000000001') r),
  array['tablero de herramientas:open', 'pata de cambio:open'],
  'the ERP reads the open searches, the most searched first'
);

select ok(
  (select r.shared and 'camara' = any (r.terms)
     from public.catalog_search_vocabulary_v1('a6090000-0000-4000-8000-000000000001') r
    where r.concept = 'camara'),
  'the ERP reads the shared vocabulary'
);

select set_config('vb.test.answer', (public.catalog_search_add_words_v1(
  'a6090000-0000-4000-8000-000000000001', 'Tablero', array['tablero de herramientas', 'Tabléro', 'pizarron'],
  'part', 'tablero de herramientas', 'Tablero de taller'))::text, true);
select is(
  current_setting('vb.test.answer')::jsonb - 'finds' - 'listed',
  jsonb_build_object(
    'concept', 'tablero',
    'added_terms', jsonb_build_array('tablero', 'pizarron'),
    'added_phrases', jsonb_build_array('tablero de herramientas'),
    'already', '[]'::jsonb,
    'created', true
  ),
  'a new concept of the store''s own: a phrase and its words, accents taken out'
);
select is(
  (select r.state || ':' || r.concept
     from public.catalog_search_misses_v1('a6090000-0000-4000-8000-000000000001') r
    where r.typed = 'tablero de herramientas'),
  'word:tablero',
  'the search it answers is closed with the concept'
);

-- 20261024080000: the groups have their names, and a shared group is
-- found by its key, underscores and all.
select is(
  (select r.label from public.catalog_search_vocabulary_v1('a6090000-0000-4000-8000-000000000001') r
    where r.concept = 'camara'),
  'Cámara',
  'a shared group has its name with its accents'
);
select is(
  (select r.label from public.catalog_search_vocabulary_v1('a6090000-0000-4000-8000-000000000001') r
    where r.concept = 'tablero'),
  'Tablero de taller',
  'a group of the store''s own keeps the name it was given'
);
select is(
  public.catalog_search_add_words_v1(
    'a6090000-0000-4000-8000-000000000001', 'pata_de_cambio', array['colgador'])->>'concept',
  'pata_de_cambio',
  'a word joins the shared group by its key'
);
select is(
  (select r.own_terms from public.catalog_search_vocabulary_v1('a6090000-0000-4000-8000-000000000001') r
    where r.concept = 'pata_de_cambio'),
  array['colgador'],
  'and is the store''s own there, under the shared name'
);
select is(
  public.catalog_search_remove_word_v1('a6090000-0000-4000-8000-000000000001', 'pata_de_cambio', 'colgador')->>'removed',
  'true',
  'and comes out the same way'
);

select is(
  (public.catalog_search_add_words_v1(
    'a6090000-0000-4000-8000-000000000001', 'maza', array['cubo', 'cubos', 'buje'])->'already'),
  '["buje"]'::jsonb,
  'a shared concept takes the store''s words; a word it has is said, not doubled'
);
select is(
  (select r.own_terms from public.catalog_search_vocabulary_v1('a6090000-0000-4000-8000-000000000001') r
    where r.concept = 'maza'),
  array['cubo', 'cubos'],
  'the store''s words of a shared concept are its own'
);

select is(
  public.catalog_search_remove_word_v1('a6090000-0000-4000-8000-000000000001', 'maza', 'cubo')->>'removed',
  'true',
  'a word of the store''s own is taken out'
);
select is(
  public.catalog_search_remove_word_v1('a6090000-0000-4000-8000-000000000001', 'maza', 'maza')->>'removed',
  'false',
  'a shared word stays'
);
select public.catalog_search_remove_word_v1('a6090000-0000-4000-8000-000000000001', 'maza', 'cubos');
select is(
  (select cardinality(r.own_terms) from public.catalog_search_vocabulary_v1('a6090000-0000-4000-8000-000000000001') r
    where r.concept = 'maza'),
  0,
  'the last word takes the store''s words with it'
);

select is(
  public.catalog_search_miss_close_v1('a6090000-0000-4000-8000-000000000001', 'pata de cambio')->>'changed',
  'true',
  '«Ignorar» closes a search'
);
select is(
  (select r.state from public.catalog_search_misses_v1('a6090000-0000-4000-8000-000000000001') r
    where r.typed = 'pata de cambio'),
  'ignored',
  'an ignored search says so'
);
select public.catalog_search_miss_close_v1('a6090000-0000-4000-8000-000000000001', 'pata de cambio', false);
select is(
  (select r.state from public.catalog_search_misses_v1('a6090000-0000-4000-8000-000000000001') r
    where r.typed = 'pata de cambio'),
  'open',
  'and its undo opens it again'
);

select throws_ok(
  $$select public.catalog_search_add_words_v1('a6090000-0000-4000-8000-000000000002', 'maza', array['buje'])$$,
  '42501',
  'catalog_tenant_forbidden',
  'another store''s words are not written'
);

reset role;

select is(
  (select count(*)::integer from public.catalog_search_terms v
    where v.tenant_id = 'a6090000-0000-4000-8000-000000000001' and v.concept = 'maza'),
  0,
  'no empty row is left'
);
select ok(
  (select v.kind = 'part' and 'tablero' = any (v.terms)
     from public.catalog_search_terms v
    where v.tenant_id = 'a6090000-0000-4000-8000-000000000001' and v.concept = 'tablero'),
  'the store''s own concept is a part, its name one of its words'
);

-- A word added that still finds nothing comes back when it is searched.
update public.catalog_search_misses
   set closed_at = now() - interval '1 hour'
 where tenant_id = 'a6090000-0000-4000-8000-000000000001' and term = 'tablero de herramientas';
set local role anon;
select public.catalog_search_miss_record_v1('a6090000-0000-4000-8000-000000000001', 'tablero de herramientas');
reset role;
select is(
  (select m.searches from public.catalog_search_misses m
    where m.tenant_id = 'a6090000-0000-4000-8000-000000000001' and m.term = 'tablero de herramientas'),
  3,
  'it keeps counting'
);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a6090000-0000-4000-8000-000000000091', 'role', 'authenticated')::text, true);
set local role authenticated;
select is(
  (select r.state from public.catalog_search_misses_v1('a6090000-0000-4000-8000-000000000001') r
    where r.typed = 'tablero de herramientas'),
  'open',
  'a word that did not help opens the search again'
);
reset role;

select * from finish();
rollback;
