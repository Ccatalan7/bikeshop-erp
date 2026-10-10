-- Read-back de 20261010040000: la foto se exige sólo a productos y la regla
-- sigue incrustable.

select 1 / case
  when pg_get_functiondef(
         'public.catalog_product_web_block_v1(public.products,jsonb)'::regprocedure)
       ~ $re$<> 'service'\s+and coalesce\(\(p_policy ->> 'require_image'\)$re$
   and position('exists' in lower(pg_get_functiondef(
         'public.catalog_product_web_block_v1(public.products,jsonb)'::regprocedure))) = 0
  then 1 else 0
end as assert_photo_rule_skips_services;

select 1 / case
  when not exists (
    select 1
      from public.products p
     where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and p.product_type = 'service'
       and public.catalog_product_web_block_v1(
             p, public.catalog_web_policy_v1(p.tenant_id)) = 'missing_image'
  )
  then 1 else 0
end as assert_no_service_blocked_for_photo;
