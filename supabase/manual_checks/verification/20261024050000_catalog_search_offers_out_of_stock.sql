-- Read-back of 20261024050000: a search can include what is out of stock when
-- the store offers it. Plain SQL: a missing invariant divides by zero after
-- printing what it found.

select 1 / (case when to_regprocedure('public.get_public_products_faceted_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,text,integer,integer,boolean)') is not null
  and to_regprocedure('public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,boolean)') is not null
  and to_regprocedure('public.get_public_products_faceted_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,text,integer,integer)') is null
  and to_regprocedure('public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb)') is null
  then 1 else 0 end) as afirma_firmas_nuevas;

select 1 / (case when has_function_privilege('anon', 'public.get_public_products_faceted_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,text,integer,integer,boolean)', 'execute')
  and has_function_privilege('anon', 'public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,boolean)', 'execute')
  and not has_function_privilege('service_role', 'public.get_public_products_faceted_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,text,integer,integer,boolean)', 'execute')
  and not has_function_privilege('service_role', 'public.get_public_product_facets_v2(uuid,uuid[],text,text,boolean,uuid[],numeric,numeric,jsonb,boolean)', 'execute')
  then 1 else 0 end) as afirma_permisos_de_visitante;

-- With Viñabike's catalog: «camara fv» lists more with «Incluir agotados».
select
  (select count(*) from public.get_public_products_faceted_v2(
     p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'camara fv',
     p_only_in_stock := false, p_limit := 100)) as sin_agotados,
  (select count(*) from public.get_public_products_faceted_v2(
     p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'camara fv',
     p_only_in_stock := false, p_limit := 100, p_include_out_of_stock := true)) as con_agotados;
select 1 / (case when
  (select count(*) from public.get_public_products_faceted_v2(
     p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'camara fv',
     p_only_in_stock := false, p_limit := 100, p_include_out_of_stock := true))
  > (select count(*) from public.get_public_products_faceted_v2(
     p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'camara fv',
     p_only_in_stock := false, p_limit := 100))
  then 1 else 0 end) as afirma_incluir_agotados_amplia;
