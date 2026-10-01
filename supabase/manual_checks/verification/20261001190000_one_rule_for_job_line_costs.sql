-- Read-back of 20261001190000: one rule splits job lines into parts and labor
-- (a service is labor; anything else, a hand-written item included, is parts),
-- and the three cost writers use it. Bodies before the deploy:
-- recalculate_job_bike_costs c501ad41fc4d312c94ea8ce143e2323e,
-- recalculate_mechanic_job_costs db234ae905513374c0a0462bfb0988f5,
-- update_mechanic_job_costs 1795150c3a01f246394fdc7f9155ef37 (it overwrote
-- total_cost with the net of the lines). The pending-quotation guard already
-- had the rule and is not rewritten. Read-only; division by zero fails it.
with fns as (
  select p.oid, p.proname, p.prosrc, p.prosecdef, p.proconfig, p.proowner,
         p.proacl, p.provolatile
    from pg_proc p
   where p.oid in (
     to_regprocedure('public.job_line_cost_bucket(text)'),
     to_regprocedure('public.recalculate_job_bike_costs()'),
     to_regprocedure('public.recalculate_mechanic_job_costs(uuid)'),
     to_regprocedure('public.update_mechanic_job_costs()'))
), checks as (
  select
    count(*) = 4 as functions_exist,
    bool_and(md5(prosrc) = case proname
      when 'job_line_cost_bucket' then '6385482c005060694e25d3770e3694e2'
      when 'recalculate_job_bike_costs' then 'a9383b4a39555853e7035158da9d3ed6'
      when 'recalculate_mechanic_job_costs' then 'dce7b6f114a39562377734fe8341f2d4'
      when 'update_mechanic_job_costs' then '04e6af7c4985f3cbe9d39f8e44c44f4f'
    end) as exact_bodies,
    bool_and(proowner = 'postgres'::regrole) as owner,
    bool_and(case when proname = 'job_line_cost_bucket'
      then not prosecdef and provolatile = 'i'
           and proconfig @> array['search_path=pg_catalog, public, pg_temp']
      else prosecdef and proconfig @> array['search_path=public'] end) as fixed_paths,
    bool_and(proname <> 'job_line_cost_bucket' or not exists (
      select 1 from aclexplode(coalesce(fns.proacl, acldefault('f', fns.proowner))) a
       where a.privilege_type = 'EXECUTE'
         and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole,
                                             'service_role'::regrole))))
      as rule_is_private,
    (select public.job_line_cost_bucket('service') = 'labor'
        and public.job_line_cost_bucket('product') = 'parts'
        and public.job_line_cost_bucket('adhoc') = 'parts'
        and public.job_line_cost_bucket(null) = 'parts') as rule_holds,
    strpos(pg_get_functiondef(
             'public.guard_canonical_mechanic_job_mode_transition()'::regprocedure),
           'coalesce(item.item_type, ''product''::text) <> ''service''::text') > 0
      or strpos(pg_get_functiondef(
             'public.guard_canonical_mechanic_job_mode_transition()'::regprocedure),
           'coalesce(item.item_type, ''product'') <> ''service''') > 0
      as quotation_guard_same_rule
  from fns
)
select checks.*,
  1 / case when functions_exist and exact_bodies and owner and fixed_paths
    and rule_is_private and rule_holds and quotation_guard_same_rule
    then 1 else 0 end as contract_holds
from checks;
