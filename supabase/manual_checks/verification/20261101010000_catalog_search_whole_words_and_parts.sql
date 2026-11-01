-- Read-back of 20261101010000_catalog_search_whole_words_and_parts.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  public.catalog_search_has_word_v1('collerin generico 2022 econom', 'cono') as cono_en_econom,
  public.catalog_search_has_word_v1('portacaramagiola negro', 'caramagiola') as caramagiola,
  (select count(*) from public.catalog_search_terms
    where tenant_id is null
      and concept in ('cepillo', 'roldana', 'protector', 'perno', 'aguja', 'cubeta',
        'oliva', 'valvula', 'tapa', 'arana', 'fitting')) as piezas_nuevas;

-- «grasa» lists grease and no brush, «cono» no seat clamp nor bearing cups,
-- «rueda» none of the parts its supplier names or descriptions mention,
-- «cubre mochila» the backpack covers, and the documents were rebuilt.
select 1 / (
  case when (
      select count(*) = 11 from public.catalog_search_terms
      where tenant_id is null
        and concept in ('cepillo', 'roldana', 'protector', 'perno', 'aguja', 'cubeta',
          'oliva', 'valvula', 'tapa', 'arana', 'fitting')
    )
    and not public.catalog_search_has_word_v1('collerin generico 2022 econom', 'cono')
    and public.catalog_search_has_word_v1('portacaramagiola negro', 'caramagiola')
    and (
      select bool_and(r.name ~* '^grasa') and count(*) > 0
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'grasa',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
    )
    and not exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'cono',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
      where r.name ~* '(collerín|cubetas|roldana)'
    )
    and not exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'rueda',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
      where r.name ~* '^(roldana|protector|aguja|gancho|sellante)'
    )
    and exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'cubre mochila',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
      where r.name ~* '^cubre mochila'
    )
    and (
      select count(*) > 1000 from public.catalog_search_documents
      where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    )
  then 1 else 0 end
) as afirma_palabras_y_piezas;
