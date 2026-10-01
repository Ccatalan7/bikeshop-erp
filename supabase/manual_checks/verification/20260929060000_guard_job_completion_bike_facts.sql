-- Read-only production readback. The behavioral rollback and same-key retry
-- are proved by local pgTAP with a real trigger failure; production is not
-- mutated to exercise this gate.
with definition as (
  select pg_get_functiondef(
    'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
  ) as body
)
select
  position('job_completion_blocked' in body) > 0 as semantic_guard,
  position('job_completion_retry' in body) > 0 as transient_retry,
  position('jsonb_agg(problem order by ord)' in body) > 0 as every_problem,
  position('errcode = ''40001''' in body) = 0 as no_postgrest_retry_loop
from definition;

select 1 / (case when
  exists (
    select 1
      from pg_proc p
     where p.oid = 'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
       and p.prosecdef
       and p.proconfig @> array['search_path=public', 'lock_timeout=750ms']::text[]
  )
  and has_function_privilege('authenticated',
    'public.transition_mechanic_job_status(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.transition_mechanic_job_status(uuid,uuid,text)', 'EXECUTE')
  and (
    select position('job_completion_blocked' in body) > 0
      and position('job_completion_retry' in body) > 0
      and position('jsonb_agg(problem order by ord)' in body) > 0
      and position('errcode = ''40001''' in body) = 0
      and position('insert into public.mechanic_job_status_transition_events' in body)
          > position('job_completion_blocked' in body)
    from (select pg_get_functiondef(
      'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
    ) as body) definition
  )
then 1 else 0 end) as guarded_atomic_completion;
