-- Read-back of 20261120230000. Fails before the migration and passes after:
-- the tables, the store's reads with p_group_models (one version each, same
-- grants) and the ERP commands do not exist before; without the parameter
-- the store's reads answer as before.

select
  (select count(*) from public.product_models
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890') as modelos,
  (select count(*) from public.product_model_members
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890') as variantes;

-- Las tablas son privadas: sin acceso directo para nadie de afuera.
select 1 / (case when
  to_regclass('public.product_models') is not null
  and to_regclass('public.product_model_members') is not null
  and (select relrowsecurity from pg_class where oid = 'public.product_models'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.product_model_members'::regclass)
  and not has_table_privilege('anon', 'public.product_models', 'SELECT')
  and not has_table_privilege('authenticated', 'public.product_model_members', 'SELECT')
  and not has_table_privilege('service_role', 'public.product_model_members', 'INSERT')
then 1 else 0 end) as afirma_tablas_privadas;

-- Una sola versión de cada lectura de la tienda, con el parámetro nuevo y
-- los mismos permisos de antes.
select 1 / (case when
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('get_public_products_faceted_v2', 'get_public_product_facets_v2',
                        'get_public_search_category_counts_v1', 'get_public_product_page_v2')) = 4
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean, boolean)')::oid, 'EXECUTE')
  and not has_function_privilege('service_role', to_regprocedure(
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean, boolean)')::oid, 'EXECUTE')
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean, boolean)')::oid, 'EXECUTE')
  and has_function_privilege('service_role', to_regprocedure(
    'public.get_public_search_category_counts_v1(uuid, text, boolean, boolean)')::oid, 'EXECUTE')
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_product_page_v2(uuid, text, uuid, boolean)')::oid, 'EXECUTE')
  and not (select prosecdef from pg_proc where oid = to_regprocedure(
    'public.get_public_product_page_v2(uuid, text, uuid, boolean)')::oid)
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_product_model_v1(uuid, uuid)')::oid, 'EXECUTE')
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_product_models_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and not has_function_privilege('anon', to_regprocedure(
    'public.product_model_summaries_internal_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and has_function_privilege('service_role', to_regprocedure(
    'public.get_merchant_product_models_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and not has_function_privilege('anon', to_regprocedure(
    'public.get_merchant_product_models_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and has_function_privilege('authenticated', to_regprocedure(
    'public.product_model_save_v1(uuid, jsonb)')::oid, 'EXECUTE')
  and not has_function_privilege('anon', to_regprocedure(
    'public.product_model_save_v1(uuid, jsonb)')::oid, 'EXECUTE')
  and has_function_privilege('authenticated', to_regprocedure(
    'public.product_model_candidates_v1(uuid, uuid, text, integer)')::oid, 'EXECUTE')
then 1 else 0 end) as afirma_lecturas_y_comandos;

-- Sin el parámetro, la tienda publicada lee lo mismo: el listado sin
-- columnas de modelo y la ficha sin la llave «model».
select 1 / (case when
  not exists (
    select 1 from public.get_public_products_faceted_v2(
      p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_limit := 100) r
     where r.model_id is not null or r.model_summary is not null)
  and not (public.get_public_product_page_v2(
    '5443b130-cc28-45af-a420-cd500b288890',
    (select p.sku from public.products p
      where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and p.is_published and p.show_on_website and p.is_active
      order by p.updated_at desc limit 1)) ? 'model')
then 1 else 0 end) as afirma_sin_cambio_para_la_tienda_publicada;
