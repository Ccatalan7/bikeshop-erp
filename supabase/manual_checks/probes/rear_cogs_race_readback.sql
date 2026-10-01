-- driver on the ficha, its source, receipts of the probe tenant that wrote
-- something, incompatible notices and retry notices on the bike, and job B's
-- status.
select p.technical_profile->'values'->>'freehubType' as driver,
       p.technical_profile->'sources'->>'freehubType' as source,
       (select count(*) from public.bike_technical_fact_patches r
         where r.tenant_id = p.tenant_id
           and jsonb_array_length(r.applied) > 0) as writing_receipts,
       (select count(*) from public.bike_events e
         where e.tenant_id = p.tenant_id
           and e.bike_id = p.bike_id
           and e.event_type = 'installed_fact_incompatible') as incompatible_notices,
       (select count(*) from public.bike_events e
         where e.tenant_id = p.tenant_id
           and e.bike_id = p.bike_id
           and e.event_type = 'installed_fact_pending') as retry_notices,
       (select j.status from public.mechanic_jobs j
         where j.id = 'e2830000-0000-4000-8000-000000000052'
           and j.tenant_id = p.tenant_id) as job_b
  from public.bike_profiles p
 where p.bike_id = 'e2830000-0000-4000-8000-000000000031'
   and p.tenant_id = 'e2830000-0000-4000-8000-000000000001';
