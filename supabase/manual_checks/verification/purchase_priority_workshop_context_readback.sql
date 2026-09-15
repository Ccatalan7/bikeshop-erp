-- Executable production read-back for 20260825161000.
-- A workshop row must expose the same durable provenance stored by Jobs.

select set_config(
  'request.jwt.claim.sub',
  (
    select profile.user_id::text
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.is_active is true
      and exists (
        select 1
        from public.supply_needs need
        where need.tenant_id = profile.tenant_id
          and need.origin_kind = 'mechanic_job'
          and need.supply_state = 'open'
      )
    group by profile.user_id
    having count(*) = 1
    order by profile.user_id
    limit 1
  ),
  true
) as workshop_tenant_context_ready;

with feed as (
  select public.purchase_priority_feed_v1(200, 120) as payload
), workshop_items as (
  select item.value
  from feed
  cross join lateral jsonb_array_elements(payload->'items') item
  where item.value->>'source' = 'workshop'
)
select
  value->>'title' as product,
  value->'jobContext'->>'jobNumber' as job_number,
  value->'jobContext'->>'scope' as scope,
  value->'jobContext'->>'bikeBrand' as bike_brand,
  value->'jobContext'->>'bikeModel' as bike_model
from workshop_items
order by job_number, product;

with feed as (
  select public.purchase_priority_feed_v1(200, 120) as payload
), workshop_items as (
  select item.value
  from feed
  cross join lateral jsonb_array_elements(payload->'items') item
  where item.value->>'source' = 'workshop'
)
select 1 / (case
  when exists (select 1 from workshop_items)
   and not exists (
     select 1
     from workshop_items
     where jsonb_typeof(value->'jobContext') <> 'object'
        or coalesce(btrim(value->'jobContext'->>'mechanicJobId'), '') = ''
        or coalesce(btrim(value->'jobContext'->>'jobNumber'), '') = ''
        or value->'jobContext'->>'scope' not in ('whole_job', 'bike')
        or (
          value->'jobContext'->>'scope' = 'whole_job'
          and value->'jobContext'->>'jobBikeId' is not null
        )
        or (
          value->'jobContext'->>'scope' = 'bike'
          and (
            coalesce(btrim(value->'jobContext'->>'jobBikeId'), '') = ''
            or coalesce(btrim(value->'jobContext'->>'bikeId'), '') = ''
          )
        )
   )
  then 1 else 0
end) as every_workshop_row_keeps_its_job_and_bike_scope;

select 1 / (case when pg_get_functiondef(
  'public.purchase_priority_feed_v1(integer,integer)'::regprocedure
) like '%''jobContext'', job_context%'
and pg_get_functiondef(
  'public.purchase_priority_feed_v1(integer,integer)'::regprocedure
) like '%job_bike.job_id = need.mechanic_job_id%'
then 1 else 0 end) as tenant_safe_workshop_context_is_installed;

select 1 / (case when has_function_privilege(
  'authenticated', 'public.purchase_priority_feed_v1(integer,integer)', 'execute'
) and not has_function_privilege(
  'anon', 'public.purchase_priority_feed_v1(integer,integer)', 'execute'
) then 1 else 0 end) as priority_feed_acl_is_unchanged;
