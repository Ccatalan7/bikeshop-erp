-- Viñabike wheel-truing rollout
-- 1. Backfill the missing global target row for the existing wheel_truing profile.
-- 2. Map only the clearly matching service product `Centrado de rueda (C/U)`.
--
-- Intentionally deferred:
-- - `Centrado Express` -> future `wheel_truing_quick`
-- - `Enrayado + Centrado` -> future `wheel_build_and_true`

insert into public.service_profile_targets (
  tenant_id,
  service_profile_id,
  target_family,
  target_position_mode,
  target_rules
)
select null, sp.id, 'wheels', 'front_rear', '{}'::jsonb
from public.service_profiles sp
where sp.tenant_id is null
  and sp.key = 'wheel_truing'
  and not exists (
    select 1
      from public.service_profile_targets spt
     where spt.tenant_id is null
       and spt.service_profile_id = sp.id
       and spt.target_family = 'wheels'
       and spt.target_position_mode = 'front_rear'
  );

update public.service_product_profile_mappings
   set status = 'inactive'
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and product_id = 'a83329e3-9ca5-443b-84a7-4383a1fc4a99'
   and status = 'active'
   and service_profile_id <> '00000000-0004-0000-0000-000000000001';

update public.service_product_profile_mappings
   set status = 'active'
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and product_id = 'a83329e3-9ca5-443b-84a7-4383a1fc4a99'
   and service_profile_id = '00000000-0004-0000-0000-000000000001';

insert into public.service_product_profile_mappings (
  tenant_id,
  product_id,
  service_profile_id,
  status
)
select
  '5443b130-cc28-45af-a420-cd500b288890',
  'a83329e3-9ca5-443b-84a7-4383a1fc4a99',
  '00000000-0004-0000-0000-000000000001',
  'active'
where not exists (
  select 1
    from public.service_product_profile_mappings spm
   where spm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and spm.product_id = 'a83329e3-9ca5-443b-84a7-4383a1fc4a99'
     and spm.service_profile_id = '00000000-0004-0000-0000-000000000001'
);