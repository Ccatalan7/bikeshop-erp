-- Read-back de 20261014030000: cada tramo tiene zona, el checkout cotiza con
-- región, el editor guarda zonas por un comando, y lo que ya estaba cotiza
-- igual (una sola zona «Todo Chile» por taller con tramos).

select 1 / case
  when to_regclass('public.online_shipping_zones') is not null
   and not exists (select 1 from public.online_shipping_rate_tiers where zone_id is null)
   and has_function_privilege('anon', 'public.quote_public_online_shipping(uuid,text,numeric,text,text)', 'execute')
   and to_regprocedure('public.quote_public_online_shipping(uuid,text,numeric,text)') is null
   and not has_function_privilege('anon', 'public.quote_online_shipping_internal(uuid,text,numeric,text,text)', 'execute')
   and has_function_privilege('authenticated', 'public.save_online_shipping_zones(jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.save_online_shipping_zones(jsonb)', 'execute')
   and public.online_shipping_region_code('Región Metropolitana de Santiago') = 'CL-RM'
   and position('shipping_state' in pg_get_functiondef(
         'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure)) > 0
   and not exists (
     select tier.tenant_id
       from public.online_shipping_rate_tiers tier
      where tier.is_active
      group by tier.tenant_id
     having count(distinct tier.zone_id) <> 1
   )
  then 1 else 0 end as online_shipping_zones;
