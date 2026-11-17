-- Read-back of 20261116234500_catalog_search_phrases_and_total_speeds.sql
-- (plain SQL, no transaction control: it runs through the read-only hosted
-- wrapper). Each search is the store's, on the real catalog, out of stock
-- included.

-- What the searches answer, to read when an assertion below fails.
select q.term,
  (select count(*)
   from public.get_public_products_without_inventory_reservations(
     p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := q.term,
     p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r) as encontrados,
  (select r.name
   from public.get_public_products_without_inventory_reservations(
     p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := q.term,
     p_only_in_stock := false, p_sort_by := 'name', p_limit := 1) r) as primero
from unnest(array[
  'v brake', 'gomas de freno', 'extractor de cadena', 'cadena 21 velocidades',
  'forro bicicleta aro 26', 'neumatico sin camara', 'centrar rueda',
  'manilla de freno', 'cambio trasero'
]) as q(term);

-- The vocabulary as the migration leaves it.
select 1 / (
  case when (
      select not ('forro' = any (terms)) and 'forro de cambio' = any (phrases)
      from public.catalog_search_terms where tenant_id is null and concept = 'funda'
    )
    and (
      select 'forro' = any (terms)
      from public.catalog_search_terms where tenant_id is null and concept = 'neumatico'
    )
    and (
      select kind = 'attribute'
      from public.catalog_search_terms where tenant_id is null and concept = 'vbrake'
    )
    and (
      select 'extractor de cadena' = any (phrases)
      from public.catalog_search_terms where tenant_id is null and concept = 'cortacadena'
    )
    and (
      select count(*) = 5
      from public.catalog_search_terms
      where tenant_id is null and kind = 'attribute'
        and concept in ('centrado', 'enrayado', 'lavado', 'ajuste', 'instalacion')
    )
    and (
      select count(*) > 1000 from public.catalog_search_documents
      where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    )
  then 1 else 0 end
) as afirma_vocabulario;

-- «v brake» lists the V-brakes first (the disc calipers whose sheet says
-- «tiro largo, V-brake», for V-brake levers, come after them and their
-- pads); «gomas de freno» only pads; «extractor de cadena» only chain tools.
select 1 / (
  case when (
      select count(*) = 10 and bool_and(r.name ~* '^frenos? v-brake')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'v brake',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 10) r
    )
    and (
      select count(*) > 0 and bool_and(r.name ~* '^pat[ií]n')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'gomas de freno',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
    )
    and (
      select count(*) > 0 and bool_and(r.name ~* '^cortacadena')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'extractor de cadena',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
    )
  then 1 else 0 end
) as afirma_frases;

-- «cadena 21 velocidades» lists 7-speed chains and links, no 9 to 12;
-- «forro bicicleta aro 26» only tyres; «neumatico sin camara» tubeless
-- tyres; «centrar rueda» the truing service.
select 1 / (
  case when (
      select count(*) > 0
        and bool_and(r.name ~* '^(cadena|eslab)')
        and not bool_or(r.name ~* '(^| )(9|10|11|12) velocidades')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'cadena 21 velocidades',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
    )
    and (
      select count(*) > 0 and bool_and(r.name ~* '^neum[aá]tico')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'forro bicicleta aro 26',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
    )
    and exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'neumatico sin camara',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
      where r.name ~* '^neum[aá]tico'
    )
    and exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'centrar rueda',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
      where r.name ~* '^centrado de rueda'
    )
  then 1 else 0 end
) as afirma_palabras_del_cliente;

-- What answered well before still does: «manilla de freno» lists no shift
-- lever (the combined «Manilla de cambio y freno» is a brake lever too), and
-- «cambio trasero» no front derailleur.
select 1 / (
  case when not exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'manilla de freno',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
      where r.name ~* '^manillas? de cambio' and r.name !~* 'freno'
    )
    and not exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'cambio trasero',
        p_only_in_stock := false, p_sort_by := 'name', p_limit := 200) r
      where r.name ~* 'cambio delantero'
    )
  then 1 else 0 end
) as afirma_lo_que_ya_andaba;
