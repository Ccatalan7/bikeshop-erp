-- Read-back of 20261006200000: the snapshot keeps its body and prunes the
-- automatic versions past the last 30; the restore names its safety version
-- in Spanish; both stay security definer with a fixed search_path and the
-- public wrappers still check can_manage_tenant_backups. Viñabike's versions
-- are listed. Read-only; division by zero fails it.
select count(*) as versiones,
       count(*) filter (where is_auto_backup) as automaticas
  from public.website_backups
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

select 1/(case when
 (select p.prosecdef
     and p.prosrc like '%offset 30%'
     and p.prosrc like '%jsonb_object_agg(key, value)%'
     and array_to_string(p.proconfig, ',') like 'search_path=%'
    from pg_proc p
   where p.oid = to_regprocedure('public.create_website_backup_internal(text,text,boolean)'))
 and (select p.prosecdef
     and p.prosrc like '%Antes de volver a%'
     and p.prosrc like '%on conflict (tenant_id, key) do update%'
    from pg_proc p
   where p.oid = to_regprocedure('public.restore_website_backup_internal(uuid,boolean)'))
 and (select p.prosrc like '%can_manage_tenant_backups%'
    from pg_proc p
   where p.oid = to_regprocedure('public.create_website_backup(text,text,boolean)'))
then 1 else 0 end) as versiones_ok;
