-- Read-back de 20261010060000: un destacado nuevo pasa por la regla única de
-- venta y los que ya estaban se conservan.

select 1 / case
  when pg_get_functiondef(
         'public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure)
       ~ $re$requested\.id <> all \(v_previous\)$re$
   and pg_get_functiondef(
         'public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure)
       ~ $re$catalog_product_web_block_v1\(p, public\.catalog_web_policy_v1\(p_tenant_id\)\) is not null$re$
   and pg_get_functiondef(
         'public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure)
       ~ $re$hint = 'catalog_featured_not_on_sale'$re$
  then 1 else 0
end as assert_featured_adds_checked_by_sale_rule;

select 1 / case
  when not has_function_privilege('anon',
         'public.catalog_replace_featured_v1(uuid,uuid[])', 'execute')
   and has_function_privilege('authenticated',
         'public.catalog_replace_featured_v1(uuid,uuid[])', 'execute')
  then 1 else 0
end as assert_featured_replace_grants;
