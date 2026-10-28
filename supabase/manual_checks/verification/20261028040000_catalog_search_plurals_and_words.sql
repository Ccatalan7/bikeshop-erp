-- Read-back of 20261028040000_catalog_search_plurals_and_words.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  public.catalog_search_alt_v1('largos') as largos,
  public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'cono') as cono;

-- «guantes largos» finds the store's long gloves and only gloves, «porta celular» its phone
-- holders, and «cono» is no longer «con».
select 1 / (
  case when (
      select bool_or(r.name ~* 'largo') and bool_and(r.name ~* 'guante')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'guantes largos',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
    )
    and exists (
      select 1
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'porta celular',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
      where r.name ~* 'celular'
    )
    and coalesce(public.get_public_search_correction_v1('5443b130-cc28-45af-a420-cd500b288890', 'cono'), '') <> 'con'
  then 1 else 0 end
) as afirma_plurales_y_palabras;
