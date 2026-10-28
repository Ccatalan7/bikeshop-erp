-- Read-back of 20261028030000_catalog_search_services_answer_taller.sql
-- (plain SQL, no transaction control: it runs through the read-only hosted
-- wrapper).

select count(*) as taller_services
from public.get_public_products_without_inventory_reservations(
  p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
  p_search_term := 'taller',
  p_only_in_stock := false,
  p_sort_by := 'relevance',
  p_limit := 200
) r;

-- «taller» lists the workshop's services and nothing else; the fingerprint
-- still inlines.
select 1 / (
  case when (
      select count(*) > 0 and bool_and(r.product_type = 'service')
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'taller',
        p_only_in_stock := false,
        p_sort_by := 'relevance',
        p_limit := 200
      ) r
    )
    and (
      select p.provolatile = 's' and p.proconfig is null
      from pg_proc p
      where p.oid = 'public.catalog_search_source_md5_v1(public.products)'::regprocedure
    )
  then 1 else 0 end
) as afirma_taller_trae_los_servicios;
