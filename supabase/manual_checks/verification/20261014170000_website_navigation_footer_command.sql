-- Read-back de 20261014170000: el pie por defecto es un comando de la base,
-- los menús del sitio los escribe sólo quien edita el sitio, y la tienda
-- pública sigue con su get_public_store_data de 20260924030000.

select 1 / case
  when has_function_privilege('authenticated', 'public.ensure_default_footer_navigation(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.ensure_default_footer_navigation(uuid)', 'execute')
  then 1 else 0
end as assert_footer_command_grants;

select 1 / case
  when (select count(*) from pg_policy
         where polrelid = 'public.website_navigation'::regclass
           and polname in ('website_navigation_insert', 'website_navigation_update',
             'website_navigation_delete')
           and coalesce(pg_get_expr(polqual, polrelid), pg_get_expr(polwithcheck, polrelid))
             like '%can_edit_tenant_settings(tenant_id)%') = 3
  then 1 else 0
end as assert_navigation_writes_need_editor;

-- Huella del cuerpo leída en producción antes de desplegar (2026-10-14).
select 1 / case
  when (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'get_public_store_data')
       = 'ea48a99eb839da65531675e38049b1f1'
   and has_function_privilege('anon', 'public.get_public_store_data(uuid)', 'execute')
  then 1 else 0
end as assert_store_payload_untouched;
