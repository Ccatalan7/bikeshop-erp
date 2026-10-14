-- Read-back de 20260728230000: el registro de publicación de la tienda existe,
-- cerrado al cliente, con el destino de Viñabike y el despacho apagado
-- (se enciende aparte, revisado), y el cron sin secreto en su texto.

select 1 / case
  when (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relrowsecurity and c.relforcerowsecurity
           and c.relname in ('storefront_publication_targets',
             'storefront_publication_requests', 'storefront_publication_attempts')) = 3
   and not has_table_privilege('authenticated', 'public.storefront_publication_targets', 'select')
   and not has_table_privilege('anon', 'public.storefront_publication_requests', 'select')
  then 1 else 0
end as assert_ledger_tables_closed;

select 1 / case
  when (select count(*) from public.storefront_publication_targets
         where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
           and target_key = 'vinabike-store'
           and expected_store_origin = 'https://vinabike.cl'
           and expected_firebase_origin = 'https://vinabike-store.web.app'
           and dispatch_enabled is false) = 1
  then 1 else 0
end as assert_target_seeded_with_dispatch_off;

select 1 / case
  when has_function_privilege('authenticated', 'public.get_storefront_publication_status(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.get_storefront_publication_status(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.retry_storefront_publication(uuid,uuid)', 'execute')
   and not has_function_privilege('authenticated', 'private.invoke_storefront_publication_dispatcher()', 'execute')
  then 1 else 0
end as assert_function_grants;

select 1 / case
  when (select count(*) from pg_trigger t
         where not t.tgisinternal
           and t.tgname like 'trg_storefront_publication_%'
           and t.tgrelid in ('public.products'::regclass, 'public.website_blocks'::regclass,
             'public.website_pages'::regclass, 'public.website_settings'::regclass,
             'public.product_categories'::regclass, 'public.product_brands'::regclass,
             'public.product_url_aliases'::regclass)) = 21
  then 1 else 0
end as assert_owner_triggers;

select 1 / case
  when (select count(*) from cron.job
         where jobname = 'vinabike_storefront_publication_dispatcher'
           and active
           and position('invoke_storefront_publication_dispatcher' in command) > 0
           and position('secret' in command) = 0) = 1
  then 1 else 0
end as assert_dispatcher_job_without_secret;

select jobname, schedule, active
  from cron.job
 where jobname = 'vinabike_storefront_publication_dispatcher';
