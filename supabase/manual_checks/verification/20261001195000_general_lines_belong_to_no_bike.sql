-- Read-back of 20261001195000: a job line's bike is the bike of its row, and
-- nothing else. A line in General belongs to no bike, also in a job with one
-- bike or with the bike only in the header. The body before the deploy was
-- b49a577fd850b81a420555fa48a112d0. On 2026-10-01 no General line carried a
-- ficha mark (`part_change`/`hole_count`), so no installed fact changed; the
-- last column reports that count and is informative, not part of the
-- contract (a later save may add one, and the close then reports it).
-- Read-only; division by zero fails it.
with actual as (
  select p.oid, p.prosrc, p.prosecdef, p.proconfig, p.proowner, p.proacl
    from pg_proc p
   where p.oid = to_regprocedure('public.job_line_bike_internal(uuid,uuid)')
), checks as (
  select
    count(oid) = 1 as function_exists,
    bool_and(md5(prosrc) = '749a166c7cbd69150d51d9e2337bb842') as exact_body,
    bool_and(prosecdef and proconfig @> array['search_path=public']) as definer_with_fixed_path,
    bool_and(proowner = 'postgres'::regrole) as owner,
    bool_and(not exists (select 1 from aclexplode(coalesce(actual.proacl, acldefault('f', actual.proowner))) a
      where a.privilege_type = 'EXECUTE'
        and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole))))
      as private_function,
    (select count(*) = 0 from public.mechanic_job_items i
      where i.job_bike_id is null
        and public.job_line_bike_internal(i.tenant_id, i.id) is not null)
      as general_is_no_bike,
    (select count(*) from public.mechanic_job_items i
      where i.job_bike_id is null
        and (i.service_configuration_data ? 'part_change'
             or i.service_configuration_data ? 'hole_count'))
      as general_lines_with_ficha_marks
  from actual
)
select checks.*,
  1 / case when function_exists and exact_body and definer_with_fixed_path
    and owner and private_function and general_is_no_bike
    then 1 else 0 end as contract_holds
from checks;
