-- Read-back of 20261006210000: versions keep the menus. The column exists,
-- the snapshot takes `website_navigation` under a per-tenant lock and still
-- prunes to 30, the restore puts the menus back (parents after the rows) and
-- both stay security definer behind the admin-only wrappers. Read-only;
-- division by zero fails it.
select count(*) as versiones,
       count(*) filter (where navigation_snapshot is not null) as con_menus
  from public.website_backups
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

select 1/(case when
 exists (select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'website_backups'
            and column_name = 'navigation_snapshot' and data_type = 'jsonb')
 and (select p.prosecdef
     and p.prosrc like '%pg_advisory_xact_lock%'
     and p.prosrc like '%from website_navigation nav%'
     and p.prosrc like '%offset 30%'
    from pg_proc p
   where p.oid = to_regprocedure('public.create_website_backup_internal(text,text,boolean)'))
 and (select p.prosecdef
     and p.prosrc like '%delete from website_navigation where tenant_id = v_tenant_id%'
     and p.prosrc like '%set parent_id = r.parent_id%'
     and p.prosrc like '%Antes de volver a%'
    from pg_proc p
   where p.oid = to_regprocedure('public.restore_website_backup_internal(uuid,boolean)'))
 and (select p.prosrc like '%can_manage_tenant_backups%'
    from pg_proc p
   where p.oid = to_regprocedure('public.restore_website_backup(uuid,boolean)'))
then 1 else 0 end) as versiones_con_menus;
