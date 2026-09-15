-- Exact definition and least-privilege boundary, checked on the live server.
select 1/case when count(*)=1 and bool_and(
 md5(pg_get_functiondef(p.oid))='0a9ca5252a7013e674edd427da58dfa7'
 and p.proacl::text='{postgres=X/postgres,service_role=X/postgres}'
 and not p.prosecdef and p.provolatile='s'
 and pg_get_userbyid(p.proowner)='postgres'
 and p.proconfig=array['search_path=pg_catalog, public, pg_temp']::text[])
 then 1 else 0 end numeric_quote_function_assertion
 from pg_proc p where p.oid=to_regprocedure('public.spec_reading_rejection_internal_v1(uuid,jsonb,text)');
-- Existing global numeric definition only; no synthetic production writes.
with def as (select id from public.spec_definitions where key='chain_outer_width_mm' and data_type='number' and tenant_id is null),
 cases(value,quote,expected) as (values
 ('10'::jsonb,'10',null::text),('100'::jsonb,'100.00 mm',null::text),('0'::jsonb,'0',null::text),
 ('-10'::jsonb,'−10',null::text),('10'::jsonb,'1','la cita no trae ese número'),
 ('0'::jsonb,'sin cifras','la cita no trae ese número'),('10'::jsonb,'-10','la cita no trae ese número'),
 ('"NaN"'::jsonb,'NaN','el valor no es un número')),
 checked as (select public.spec_reading_rejection_internal_v1(def.id,c.value,c.quote) is not distinct from c.expected as ok from def cross join cases c)
 select 1/case when count(*)=8 and bool_and(ok) then 1 else 0 end numeric_quote_read_smoke from checked;
