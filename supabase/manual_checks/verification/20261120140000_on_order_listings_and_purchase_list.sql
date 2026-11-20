-- Read-back of 20261120140000. Fails before the migration and passes after:
-- the helpers do not exist before, the three public reads only name the
-- listing helper once it is applied, and the purchase list only skips what is
-- sold on order once both triggers carry the rule.

select
  (select count(*) from public.product_on_order_terms where is_active) as productos_a_pedido;

select 1 / (case when
  to_regprocedure('public.catalog_on_order_product_ids_internal_v1(uuid)') is not null
  and not has_function_privilege('anon',
    to_regprocedure('public.catalog_on_order_product_ids_internal_v1(uuid)')::oid, 'EXECUTE')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.catalog_on_order_product_ids_internal_v1(uuid)')::oid, 'EXECUTE')
  and not has_function_privilege('service_role',
    to_regprocedure('public.catalog_on_order_product_ids_internal_v1(uuid)')::oid, 'EXECUTE')
  and pg_get_functiondef(to_regprocedure(
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean)')::oid)
    like '%catalog_on_order_product_ids_internal_v1%'
  and pg_get_functiondef(to_regprocedure(
    'public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean)')::oid)
    like '%catalog_on_order_product_ids_internal_v1%'
  and pg_get_functiondef(to_regprocedure(
    'public.get_public_search_category_counts_v1(uuid, text, boolean)')::oid)
    like '%catalog_on_order_product_ids_internal_v1%'
  -- Lo que no cambia: el carrito, los destacados y Merchant.
  and pg_get_functiondef(to_regprocedure(
    'public.get_public_products(uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer)')::oid)
    not like '%catalog_on_order_product_ids_internal_v1%'
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean)')::oid,
    'EXECUTE')
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean)')::oid,
    'EXECUTE')
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_search_category_counts_v1(uuid, text, boolean)')::oid, 'EXECUTE')
  and not has_function_privilege('service_role', to_regprocedure(
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean)')::oid,
    'EXECUTE')
then 1 else 0 end) as afirma_a_pedido_en_los_listados;

-- El listado de Neumáticos de Viñabike responde y cuenta lo mismo que sus
-- filtros (con o sin productos a pedido).
select 1 / (case when (
  select coalesce(max(r.total_count), 0)
    from public.get_public_products_faceted_v2(
      p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
      p_only_in_stock := false,
      p_limit := 1
    ) r
) = (
  select coalesce(max(r.item_count), 0)
    from public.get_public_product_facets_v2(
      p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
      p_only_in_stock := false
    ) r
   where r.facet_key = 'summary'
) then 1 else 0 end) as el_listado_y_sus_filtros_cuentan_igual;

-- Lista de compras: la regla vive en los dos disparadores y su núcleo no se
-- ejecuta desde afuera.
select 1 / (case when
  to_regprocedure('public.purchase_list_on_order_only_internal_v1(uuid, uuid)') is not null
  and not has_function_privilege('anon',
    to_regprocedure('public.purchase_list_on_order_only_internal_v1(uuid, uuid)')::oid, 'EXECUTE')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.purchase_list_on_order_only_internal_v1(uuid, uuid)')::oid, 'EXECUTE')
  and not has_function_privilege('service_role',
    to_regprocedure('public.purchase_list_on_order_only_internal_v1(uuid, uuid)')::oid, 'EXECUTE')
  and pg_get_functiondef(to_regprocedure('public.auto_add_low_stock_to_purchase_list()')::oid)
    like '%purchase_list_on_order_only_internal_v1%'
  and exists (
    select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'products'
       and t.tgname = 'trg_auto_add_low_stock' and not t.tgisinternal
  )
  and exists (
    select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'product_on_order_terms'
       and t.tgname = 'trg_product_on_order_terms_purchase_list' and not t.tgisinternal
       and t.tgfoid = to_regprocedure('public.purchase_list_drop_on_order_only_internal_v1()')::oid
  )
then 1 else 0 end) as afirma_lo_a_pedido_fuera_de_la_lista_de_compras;
