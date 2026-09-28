-- status, spoke holes on the ficha, receipts of the probe tenant.
select j.status,
       p.technical_profile->'values'->>'frontSpokeHoles' as holes,
       (select count(*) from public.bike_technical_fact_patches r
         where r.tenant_id = 'e2790000-0000-4000-8000-000000000001') as receipts
  from public.mechanic_jobs j
  join public.bike_profiles p on p.bike_id = j.bike_id and p.tenant_id = j.tenant_id
 where j.id = 'e2790000-0000-4000-8000-000000000051'
   and j.tenant_id = 'e2790000-0000-4000-8000-000000000001';
