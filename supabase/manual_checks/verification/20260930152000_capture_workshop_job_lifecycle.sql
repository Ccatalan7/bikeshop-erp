-- SQL-failing readback for the production lifecycle captured by this forward.
with target as (
 select p.oid, md5(replace(pg_get_functiondef(p.oid), E'\r\n', E'\n')) as definition_md5,
        pg_get_userbyid(p.proowner) as owner, p.prosecdef, p.prorettype,
        p.proconfig, p.provolatile,
        p.proacl::text as acl,
        (select count(*) from pg_trigger t where t.tgfoid=p.oid
          and t.tgrelid='public.mechanic_jobs'::regclass
          and not t.tgisinternal and t.tgenabled='O') as active_bindings
 from pg_proc p where p.oid=to_regprocedure('public.handle_mechanic_job_change()')
)
select definition_md5, owner, prosecdef, proconfig, provolatile, acl, active_bindings,
       1 / (case when definition_md5='fbf44c605a0925f4186f7ebe0a9369c2' and owner='postgres'
         and prosecdef and prorettype='trigger'::regtype
         and proconfig=array['search_path=public']::text[]
         and provolatile='v' and active_bindings=2
         and acl='{postgres=X/postgres,service_role=X/postgres}'
         then 1 else 0 end) as workshop_lifecycle_capture
from target;
select 1 / (case when to_regprocedure('public.handle_mechanic_job_change()') is not null
                 then 1 else 0 end) as workshop_lifecycle_present;
