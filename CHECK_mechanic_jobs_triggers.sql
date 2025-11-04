-- Check for UPDATE triggers on mechanic_jobs that might set invoice_id = NULL
select 
  tgname as trigger_name,
  tgtype,
  tgenabled as enabled,
  pg_get_triggerdef(oid) as trigger_definition
from pg_trigger
where tgrelid = 'mechanic_jobs'::regclass
  and tgname like '%invoice%'
order by tgname;
