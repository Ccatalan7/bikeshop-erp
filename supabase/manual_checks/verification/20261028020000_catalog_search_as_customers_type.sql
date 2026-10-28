-- Read-back of 20261028020000_catalog_search_as_customers_type.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  (select count(*) from public.catalog_search_words
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890') as store_words,
  public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'kasco') as kasco,
  public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'pastiyas') as pastiyas,
  public.catalog_search_query_v2('pastillas b01s') as b01s;

-- The store's own: «kasco» is «casco», «pastiyas» is «pastillas»; «cambio
-- delantero» lists no rear derailleur; «mantencion» no product whose
-- description only mentions it; a known word is not corrected.
select 1 / (
  case when
    public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'kasco') = 'casco'
    and public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'pastiyas') = 'pastillas'
    and public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'cadena') is null
    and public.catalog_search_query_v2('pastillas b01s') = 'pastillas b01s'
    and (
      select count(*) > 0 and bool_and(r.name !~* 'trasero')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'cambio delantero',
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
        p_search_term := 'mantencion',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
      where r.name ~* 'bolitas'
    )
    and (
      select count(*) from public.catalog_search_words
      where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    ) > 500
  then 1 else 0 end
) as afirma_la_busqueda_entiende_al_cliente;
