-- Read-back of 20261025010000: a measure the visitor writes decides, and a
-- search for a part finds that part. Plain SQL: a missing invariant divides
-- by zero after printing what it found. Read on Viñabike's live catalog
-- (2026-10-25), counting everything, in stock or not.

with q(term) as (values ('cassette 7v'), ('camara 20'), ('manubrio 31.8'), ('cadena 12v'))
select q.term, count(r.*) as encontrados,
       left(string_agg(r.name, ' · ' order by r.name), 300) as nombres
  from q
  left join lateral public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890', null, null, null, q.term, null,
    false, 'name', 400, 0) r on true
 group by q.term
 order by q.term;

-- The helpers and the vocabulary.
select 1 / (case when public.catalog_search_query_v2('Cámara 29x2,25 180mm 11 velocidades') = 'camara 29 2.25 180 mm 11v'
  and public.catalog_search_text_v2('Cámara aro 20 x 1.50-2.20') = 'camara aro 20 x 1.50 2.20'
  and public.catalog_search_bead_of_v1('27.5') = 584
  and not has_function_privilege('anon', 'public.catalog_search_query_v2(text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_text_v2(text)', 'execute')
  and exists (select 1 from public.catalog_search_terms
               where tenant_id is null and concept = 'disco' and 'disco' = any (terms))
  and exists (select 1 from public.catalog_search_terms where tenant_id is null and concept = 'cortacadena' and label = 'Cortacadena')
  then 1 else 0 end) as afirma_ayudas_y_vocabulario;

-- No cassette, freewheel or spacer of another speed answers «cassette 7v»;
-- every product found says 7 speeds in its name.
select 1 / (case when not exists (
    select 1
      from public.get_public_products_without_inventory_reservations(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, 'cassette 7v', null,
        false, 'name', 400, 0) r
     where public.catalog_search_text_v2(r.name) !~ '(^| )7( |v|/)'
       and public.catalog_search_text_v2(r.name) !~ '[ /]7 (velocidades|v)'
  )
  then 1 else 0 end) as afirma_cassette_7v;

-- «camara 20» lists only 20 tubes: none of 26, 27.5 or 29.
select 1 / (case when not exists (
    select 1
      from public.get_public_products_without_inventory_reservations(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, 'camara 20', null,
        false, 'name', 400, 0) r
     where r.name ~* '(aro|rin) (26|27\.5|29)|700'
  )
  then 1 else 0 end) as afirma_camara_20;

-- «manubrio 31.8» lists handlebars, not stems.
select 1 / (case when not exists (
    select 1
      from public.get_public_products_without_inventory_reservations(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, 'manubrio 31.8', null,
        false, 'name', 400, 0) r
     where r.name ~* '^tee'
  )
  and exists (
    select 1
      from public.get_public_products_without_inventory_reservations(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, 'manubrio 31.8', null,
        false, 'name', 400, 0) r
     where r.name ~* '^manubrio'
  )
  then 1 else 0 end) as afirma_manubrio;

-- A plain search still answers: «kenda» finds Kenda products.
select 1 / (case when (
    select count(*)
      from public.get_public_products_without_inventory_reservations(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, 'kenda', null,
        false, 'name', 400, 0)
  ) > 0
  then 1 else 0 end) as afirma_busqueda_simple;
