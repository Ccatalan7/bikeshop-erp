-- Read-back of 20261025050000_catalog_search_documents_skip_build.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  position(
    'lookup as materialized' in pg_get_functiondef(
      'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
    )
  ) > 0 as documents_by_key,
  position(
    'where cardinality(m.ids) > 0' in pg_get_functiondef(
      'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
    )
  ) > 0 as builds_only_what_is_missing;

select 1 / (
  case when position(
      'where cardinality(m.ids) > 0' in pg_get_functiondef(
        'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
      )
    ) > 0
    and (
      select count(*) from public.get_public_products(
        p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
        p_search_term := 'cadena',
        p_product_type := 'product',
        p_only_in_stock := false,
        p_limit := 5
      )
    ) > 0
  then 1 else 0 end
) as afirma_la_busqueda_lee_por_clave_y_responde;
