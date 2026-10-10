-- Read-back de 20261010030000: anónimo lee el modo de precio y la ficha
-- pública lo trae.

select 1 / case
  when has_column_privilege('anon', 'public.products', 'website_price_mode', 'SELECT')
   and not has_column_privilege('anon', 'public.products', 'cost', 'SELECT')
  then 1 else 0
end as assert_anon_reads_price_mode_not_cost;

select 1 / case
  when position('p.website_price_mode' in pg_get_functiondef(
         'public.get_public_product_page_v2(uuid,text,uuid)'::regprocedure)) > 0
  then 1 else 0
end as assert_product_page_reads_price_mode;

select 1 / case
  when (
    select bool_and(
             public.get_public_product_page_v2(p.tenant_id, null, p.id)
               -> 'product' ->> 'website_price_mode' = p.website_price_mode)
      from public.products p
      join public.get_public_products(
             p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
             p_product_type := 'service',
             p_only_in_stock := false,
             p_limit := 3) listed on listed.id = p.id
     where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  )
  then 1 else 0
end as assert_service_page_carries_its_mode;
