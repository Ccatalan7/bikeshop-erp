-- Read-back of 20261006220000: the automatic version is open to whoever may
-- save the site (`can_edit_tenant_settings`) through `record_website_version`
-- (authenticated only, never anon), and restoring puts back each page's own
-- data and skips the blocks of pages deleted since; menus and the safety
-- version stay. Read-only; division by zero fails it.
select p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as autenticado,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anonimo
  from pg_proc p
 where p.oid in (to_regprocedure('public.record_website_version(text,text)'),
                 to_regprocedure('public.create_website_backup(text,text,boolean)'));

select 1/(case when
 (select p.prosecdef
     and p.prosrc like '%can_edit_tenant_settings(v_tenant_id)%'
     and p.prosrc like '%create_website_backup_internal(%'
    from pg_proc p
   where p.oid = to_regprocedure('public.record_website_version(text,text)'))
 and has_function_privilege('authenticated',
       'public.record_website_version(text,text)', 'EXECUTE')
 and not has_function_privilege('anon',
       'public.record_website_version(text,text)', 'EXECUTE')
 and (select p.prosrc like '%update website_pages page%'
     and p.prosrc like '%continue when%'
     and p.prosrc like '%set parent_id = r.parent_id%'
     and p.prosrc like '%Antes de volver a%'
    from pg_proc p
   where p.oid = to_regprocedure('public.restore_website_backup_internal(uuid,boolean)'))
 and (select p.prosrc like '%can_manage_tenant_backups%'
    from pg_proc p
   where p.oid = to_regprocedure('public.restore_website_backup(uuid,boolean)'))
then 1 else 0 end) as versiones_para_quien_edita;
