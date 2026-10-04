-- Read-back of 20261004120000: the store reads the active shipping tiers of
-- one tenant through a narrow public function. It is security definer with a
-- fixed search_path, anon and the service role can call it while the table
-- itself stays closed to them, and for Viñabike it returns exactly the active
-- tiers the checkout quotes from, in order. Read-only; division by zero fails
-- it.
select count(*) as tiers_publicos,
       min(min_order_gross) as desde,
       count(*) filter (where max_order_gross is null) as sin_tope
  from public.get_public_online_shipping_tiers('5443b130-cc28-45af-a420-cd500b288890');

select 1/(case when
 (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_online_shipping_tiers(uuid)'))
 and has_function_privilege('anon', 'public.get_public_online_shipping_tiers(uuid)', 'EXECUTE')
 and has_function_privilege('service_role', 'public.get_public_online_shipping_tiers(uuid)', 'EXECUTE')
 and not has_table_privilege('anon', 'public.online_shipping_rate_tiers', 'SELECT')
 and not has_table_privilege('service_role', 'public.online_shipping_rate_tiers', 'SELECT')
 and (select count(*) from public.get_public_online_shipping_tiers('5443b130-cc28-45af-a420-cd500b288890'))
     = (select count(*) from public.online_shipping_rate_tiers
         where tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and is_active)
 and (select count(*) from public.online_shipping_rate_tiers
       where tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and is_active) > 0
 and not exists (select 1 from public.get_public_online_shipping_tiers('00000000-0000-0000-0000-000000000000'))
then 1 else 0 end) as tramos_de_envio_publicos;
