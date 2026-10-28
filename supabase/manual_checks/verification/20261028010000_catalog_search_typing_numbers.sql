-- Read-back of 20261028010000_catalog_search_typing_numbers.sql (plain SQL,
-- no transaction control: it runs through the read-only hosted wrapper).

select
  position(
    'e.tokens[cardinality(e.tokens)]' in pg_get_functiondef(
      'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
    )
  ) > 0 as last_word_is_a_beginning,
  position(
    '650b 275 27.5 27' in pg_get_functiondef(
      'public.catalog_search_documents_compute_internal_v1(uuid,uuid[])'::regprocedure
    )
  ) > 0 as documents_say_27,
  public.catalog_search_query_v2('neumatico 27 5') = 'neumatico 27.5' as point_not_typed;

-- «neumatico 27» finds 27.5 tyres and nothing of another wheel; «camara 20»
-- still never a tube whose only 20 is in «2.20».
select 1 / (
  case when (
      select count(*) > 0
        and bool_and(r.name ~ '27[.,]5')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'neumatico 27',
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
        p_search_term := 'camara 20',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
      where r.name !~ '(^|[^0-9.,])20([^0-9.,]|$)'
    )
    and (
      select count(*) from public.catalog_search_documents
      where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    ) > 1000
  then 1 else 0 end
) as afirma_los_numeros_se_leen_como_se_escriben;
