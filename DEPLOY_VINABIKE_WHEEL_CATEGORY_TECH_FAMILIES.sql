-- Viñabike wheel / steering category technical-family bridge
--
-- Purpose:
-- - seed the coarse `category_tech_mappings.technical_family` bridge for the
--   clearly unambiguous stocked wheel/headset categories
-- - unblock product-family coverage audit without pretending the whole wheel
--   catalog already has detailed ficha templates
--
-- Intentionally deferred here:
-- - `Tubeless` and `Tripas Tubeless`: live products still look mixed enough
--   that they should be split or templated deliberately instead of flattened
--   into one coarse family by guesswork.
-- - `Cinta Manillar`: cockpit accessory, not part of the current bearing/wheel slice.
-- - `Rodamientos Motor`: e-bike / motor family, not wheel/headset.

with desired(category_id, category_name, technical_family) as (
  values
    ('6f8d526a-11cb-46af-9860-96ab9d8839c6'::uuid, 'Maza', 'hub'),
    ('164a2269-4d0b-419b-af48-0098f0aae9d3'::uuid, 'Mazas', 'hub'),
    ('072f9bc7-d5c7-4c31-8ec9-965099aefbab'::uuid, 'Llantas', 'rim'),
    ('0e365f76-54a5-4224-8551-cb5d1d8dc539'::uuid, 'Rayos', 'spoke'),
    ('f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4'::uuid, 'Cámaras', 'tube'),
    ('e2660380-1cb6-4a13-9c20-452039dfa0b8'::uuid, 'Cámaras Anti-Pinchazo', 'tube'),
    ('aa02fb21-d0f0-4bdd-a334-d18dbcff82f6'::uuid, 'Cubre Cámara', 'rim_strip'),
    ('14d2d632-1f5f-406c-9a7c-16f55a5fc1ae'::uuid, 'Válvula Tubeless', 'tubeless_valve'),
    ('e2014395-26a3-4fa0-8b1b-e2d049c6a0df'::uuid, 'Líquido Tubeless', 'tubeless_consumable'),
    ('eea4e61b-4038-407f-a715-9f11ba477c13'::uuid, 'Juego de dirección', 'headset'),
    ('407c429d-4e24-4744-8189-441cf865dc05'::uuid, 'Rodamientos', 'bearing'),
    ('67d3ea45-aa2a-4137-8178-e73a853f76da'::uuid, 'Rodamientos', 'bearing')
),
resolved as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    d.category_id,
    d.category_name,
    d.technical_family
  from desired d
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.category_id = d.category_id
  group by d.category_id, d.category_name, d.technical_family
)
update public.category_tech_mappings ctm
   set technical_family = r.technical_family,
       status = 'active',
       updated_at = now()
  from resolved r
 where ctm.tenant_id = r.tenant_id
   and ctm.category_id = r.category_id;

with desired(category_id, category_name, technical_family) as (
  values
    ('6f8d526a-11cb-46af-9860-96ab9d8839c6'::uuid, 'Maza', 'hub'),
    ('164a2269-4d0b-419b-af48-0098f0aae9d3'::uuid, 'Mazas', 'hub'),
    ('072f9bc7-d5c7-4c31-8ec9-965099aefbab'::uuid, 'Llantas', 'rim'),
    ('0e365f76-54a5-4224-8551-cb5d1d8dc539'::uuid, 'Rayos', 'spoke'),
    ('f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4'::uuid, 'Cámaras', 'tube'),
    ('e2660380-1cb6-4a13-9c20-452039dfa0b8'::uuid, 'Cámaras Anti-Pinchazo', 'tube'),
    ('aa02fb21-d0f0-4bdd-a334-d18dbcff82f6'::uuid, 'Cubre Cámara', 'rim_strip'),
    ('14d2d632-1f5f-406c-9a7c-16f55a5fc1ae'::uuid, 'Válvula Tubeless', 'tubeless_valve'),
    ('e2014395-26a3-4fa0-8b1b-e2d049c6a0df'::uuid, 'Líquido Tubeless', 'tubeless_consumable'),
    ('eea4e61b-4038-407f-a715-9f11ba477c13'::uuid, 'Juego de dirección', 'headset'),
    ('407c429d-4e24-4744-8189-441cf865dc05'::uuid, 'Rodamientos', 'bearing'),
    ('67d3ea45-aa2a-4137-8178-e73a853f76da'::uuid, 'Rodamientos', 'bearing')
),
resolved as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    d.category_id,
    d.technical_family
  from desired d
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.category_id = d.category_id
  group by d.category_id, d.technical_family
)
insert into public.category_tech_mappings (
  tenant_id,
  category_id,
  technical_family,
  template_id,
  default_tags,
  status
)
select
  r.tenant_id,
  r.category_id,
  r.technical_family,
  null,
  '[]'::jsonb,
  'active'
from resolved r
where not exists (
  select 1
    from public.category_tech_mappings ctm
   where ctm.tenant_id = r.tenant_id
     and ctm.category_id = r.category_id
);