-- Seed missing global drivetrain service targets and activate the first
-- conservative Viñabike drivetrain service mappings.

insert into public.service_profile_targets (
  tenant_id,
  service_profile_id,
  target_family,
  target_position_mode,
  target_rules
)
select null, sp.id, 'drivetrain', 'none', '{}'::jsonb
from public.service_profiles sp
where sp.tenant_id is null
  and sp.key in ('chain_lube', 'derailleur_adjustment')
  and not exists (
    select 1
    from public.service_profile_targets spt
    where spt.tenant_id is null
      and spt.service_profile_id = sp.id
      and spt.target_family = 'drivetrain'
      and spt.target_position_mode = 'none'
  );

insert into public.service_product_profile_mappings (
  tenant_id,
  product_id,
  service_profile_id,
  status
)
values
  ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '74a9cddd-c3f1-4789-a352-4667cde652ba'::uuid, '00000000-0003-0000-0000-000000000001'::uuid, 'active'),
  ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '506c4b31-deea-4085-b56a-215f91f87214'::uuid, '00000000-0003-0000-0000-000000000001'::uuid, 'active'),
  ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cc08406b-ed3b-48b8-96ec-0de4ce7b5fbb'::uuid, '00000000-0003-0000-0000-000000000001'::uuid, 'active'),
  ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '03af32b8-5d71-4b52-a793-4e9ad8215373'::uuid, '00000000-0002-0000-0000-000000000001'::uuid, 'active'),
  ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'a561b652-e993-4f86-8e3b-d7a5b2d4592d'::uuid, '00000000-0002-0000-0000-000000000001'::uuid, 'active')
on conflict (tenant_id, product_id) do update set
  service_profile_id = excluded.service_profile_id,
  status = excluded.status,
  updated_at = now();
