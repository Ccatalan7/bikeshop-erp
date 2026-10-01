-- Read-only check for 20260930020000. Fails (division by zero) until the
-- posted-invoice purge exit is a private per-row authorization: the guard no
-- longer reads a session variable, claims or current_user; the authorization
-- table is private; only service_role (and the owner) may authorize; nobody
-- in the API may consume. Local pgTAP proves the behavior:
-- supabase/tests/posted_invoice_purge_authorization.sql.
with fn as (
  select
    to_regprocedure('public.guard_posted_invoice_delete()') as guard,
    to_regprocedure('public.authorize_posted_document_purge(uuid,text,uuid[],text)') as authorize,
    to_regprocedure('public.consume_posted_document_purge_internal(uuid,text,uuid)') as consume,
    to_regclass('public.posted_document_purge_authorizations') as authorizations
), checks as (
  select
    coalesce((
      select p.prosecdef
         and md5(p.prosrc) = '1370040447ca73d47d14661907410ede'
         and p.proconfig = array['search_path=public']
         and position('consume_posted_document_purge_internal' in pg_get_functiondef(p.oid)) > 0
         and pg_get_functiondef(p.oid) !~* '(allow_posted_document_purge|current_user|session_user|current_setting|request\.jwt|auth\.)'
        from pg_proc p where p.oid = fn.guard), false) as guard_uses_private_authorization,
    coalesce((
      select count(*) = 2
        from pg_trigger t
       where t.tgfoid = fn.guard
         and t.tgenabled = 'O'
         and t.tgrelid in ('public.sales_invoices'::regclass, 'public.purchase_invoices'::regclass)), false)
      as guard_on_sales_and_purchases,
    coalesce((
      select c.relrowsecurity
         and c.relowner = (select proowner from pg_proc where oid = fn.guard)
         and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid)
         and not exists (
           select 1
             from unnest(array['anon', 'authenticated', 'service_role']) as r(role),
                  unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
            where has_table_privilege(r.role, c.oid, p.priv))
        from pg_class c where c.oid = fn.authorizations), false) as authorizations_private,
    coalesce((
      select p.prosecdef
         and md5(p.prosrc) = 'cf0f508c91eac15b2c55b704ed268dbf'
         and p.proconfig = array['search_path=pg_catalog, public, pg_temp']
         and p.proowner = (select proowner from pg_proc where oid = fn.guard)
         and has_function_privilege('service_role', p.oid, 'EXECUTE')
         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and not has_function_privilege('anon', p.oid, 'EXECUTE')
         and not exists (select 1 from aclexplode(p.proacl) acl where acl.grantee = 0)
         and pg_get_functiondef(p.oid) !~* '(current_user|session_user|current_setting|request\.jwt|auth\.)'
        from pg_proc p where p.oid = fn.authorize), false) as authorize_backend_only,
    coalesce((
      select p.prosecdef
         and md5(p.prosrc) = 'ebb27d958f5a0f9576d2c1fafdfc3204'
         and p.proconfig = array['search_path=pg_catalog, public, pg_temp']
         and p.proowner = (select proowner from pg_proc where oid = fn.guard)
         and not has_function_privilege('service_role', p.oid, 'EXECUTE')
         and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
         and not has_function_privilege('anon', p.oid, 'EXECUTE')
         and not exists (select 1 from aclexplode(p.proacl) acl where acl.grantee = 0)
         and pg_get_functiondef(p.oid) !~* '(current_user|session_user|current_setting|request\.jwt|auth\.)'
        from pg_proc p where p.oid = fn.consume), false) as consume_internal_only
    from fn
)
select guard_uses_private_authorization,
       guard_on_sales_and_purchases,
       authorizations_private,
       authorize_backend_only,
       consume_internal_only,
       1 / (case when guard_uses_private_authorization
                  and guard_on_sales_and_purchases
                  and authorizations_private
                  and authorize_backend_only
                  and consume_internal_only
                 then 1 else 0 end) as posted_invoice_purge_authorization_contract
  from checks;
