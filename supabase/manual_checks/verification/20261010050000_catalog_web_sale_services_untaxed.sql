-- Read-back de 20261010050000: encender la venta exime a los servicios del
-- IVA, como la regla de la tienda.

select 1 / case
  when pg_get_functiondef(
         'public.catalog_set_web_sale_v1(uuid,uuid[],boolean)'::regprocedure)
       ~ $re$= 'service'\s+or p\.tax_rate in \(0, 0\.19, 19\)$re$
   and pg_get_functiondef(
         'public.catalog_set_web_sale_v1(uuid,uuid[],boolean)'::regprocedure)
       ~ $re$<> 'service'\s+and \(p\.tax_rate is null$re$
  then 1 else 0
end as assert_services_skip_tax_on_web_sale;
