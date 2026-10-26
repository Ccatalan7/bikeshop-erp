-- Read-back of 20261025040000_catalog_search_documents.sql (plain SQL, no
-- transaction control: it runs through the read-only hosted wrapper).

select
  to_regclass('public.catalog_search_documents') is not null as documents_table,
  position(
    'catalog_search_documents_compute_internal_v1' in pg_get_functiondef(
      'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
    )
  ) > 0 as search_reads_documents,
  (
    select count(*) from public.catalog_search_documents
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  ) as vinabike_documents,
  exists (
    select 1 from cron.job
    where jobname = 'catalog_search_documents_refresh' and schedule = '* * * * *'
  ) as refresh_every_minute,
  not has_table_privilege('anon', 'public.catalog_search_documents', 'select') as closed_to_anon;

-- Every listed product of the store has its document as it is now.
select 1 / (
  case when not exists (
    select 1
    from public.products p
    left join public.catalog_search_documents d
      on d.tenant_id = p.tenant_id and d.product_id = p.id
     and d.version = 1 and d.source_md5 = public.catalog_search_source_md5_v1(p)
    where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and p.is_active
      and coalesce(p.is_published, false)
      and coalesce(p.show_on_website, false)
      and d.product_id is null
  ) then 1 else 0 end
) as afirma_cada_producto_tiene_su_documento;

-- The search still answers, and the cron job exists.
select 1 / (
  case when (
    select count(*) from public.get_public_products(
      p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
      p_search_term := 'cadena',
      p_product_type := 'product',
      p_only_in_stock := false,
      p_limit := 5
    )
  ) > 0
  and exists (select 1 from cron.job where jobname = 'catalog_search_documents_refresh')
  and not has_table_privilege('anon', 'public.catalog_search_documents', 'select')
  then 1 else 0 end
) as afirma_la_busqueda_responde;
