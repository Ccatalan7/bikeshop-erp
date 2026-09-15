-- Exact read-back of the only function replaced by this forward.
select 1 / case when exists(select 1 from pg_proc where
 oid='public.spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)'::regprocedure and md5(pg_get_functiondef(oid))='cf4c62043ce36a3f62af020fade60417'
 and pg_get_userbyid(proowner)='postgres' and prosecdef and provolatile='v'
 and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]
 and proacl=array['postgres=X/postgres','service_role=X/postgres']::aclitem[])
 then 1 else 0 end as typed_legacy_writer_matches;
