-- Viñabike bottom bracket / pedalier workflow rollout
--
-- Purpose:
-- - seed the missing global bottom-bracket service profiles and target rows
-- - bridge the clearly bottom-bracket stock categories into
--   category_tech_mappings.technical_family = `bottom_bracket`
-- - map the live Viñabike service rows that already use “motor” vocabulary
--
-- Notes:
-- - this rollout intentionally keeps product compatibility at the coarse
--   technical-family layer for now; detailed bottom-bracket ficha templates can
--   follow later once richer product data is available.

-- ============================================================
-- Global service profiles
-- ============================================================

insert into public.service_profiles (
  id,
  tenant_id,
  key,
  name,
  service_family,
  description,
  customer_summary_template,
  mechanic_summary_template
)
select
  '00000000-0020-0000-0000-000000000001',
  null,
  'bottom_bracket_adjustment',
  'Ajuste de Motor',
  'bottom_bracket',
  'Ajuste de juego, carga y suavidad del pedalier / BB',
  'Ajuste pedalier · síntoma {{symptom}}',
  'Pedalier / BB {{bottom_bracket_family}} · Ajuste por {{symptom}}'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'bottom_bracket_adjustment'
);

update public.service_profiles
   set name = 'Ajuste de Motor',
       service_family = 'bottom_bracket',
       description = 'Ajuste de juego, carga y suavidad del pedalier / BB',
       customer_summary_template = 'Ajuste pedalier · síntoma {{symptom}}',
       mechanic_summary_template = 'Pedalier / BB {{bottom_bracket_family}} · Ajuste por {{symptom}}',
       updated_at = now()
 where tenant_id is null
   and key = 'bottom_bracket_adjustment';

insert into public.service_profile_questions (
  id,
  tenant_id,
  service_profile_id,
  key,
  label,
  question_type,
  is_required,
  sort_order,
  options_json
)
select
  seed.id,
  null,
  sp.id,
  seed.key,
  seed.label,
  seed.question_type,
  seed.is_required,
  seed.sort_order,
  seed.options_json
from public.service_profiles sp
join (
  values
    ('00000000-0020-0001-0000-000000000001'::uuid, 'bottom_bracket_family', 'Familia pedalier / BB', 'single_select', true, 10,
     '[{"value":"bsa_threaded","label":"BSA roscado"},{"value":"pressfit","label":"Pressfit"},{"value":"bb30_pf30","label":"BB30 / PF30"},{"value":"mid","label":"Mid / BMX"},{"value":"one_piece","label":"One-piece"},{"value":"other","label":"Otro"},{"value":"unknown","label":"Desconocido"}]'::jsonb),
    ('00000000-0020-0001-0000-000000000002'::uuid, 'symptom', 'Síntoma principal', 'single_select', true, 20,
     '[{"value":"play","label":"Juego"},{"value":"noise","label":"Ruido"},{"value":"roughness","label":"Aspereza / roce interno"},{"value":"tightness","label":"Apriete / dureza"},{"value":"preventive","label":"Mantención preventiva"}]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'bottom_bracket_adjustment'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

insert into public.service_profiles (
  id,
  tenant_id,
  key,
  name,
  service_family,
  description,
  customer_summary_template,
  mechanic_summary_template
)
select
  '00000000-0021-0000-0000-000000000001',
  null,
  'bottom_bracket_service',
  'Mantención de Motor',
  'bottom_bracket',
  'Limpieza, engrase y mantención del pedalier / BB',
  'Mantención pedalier {{bottom_bracket_family}}',
  'Pedalier / BB {{bottom_bracket_family}} · Síntoma {{symptom}} · Reemplazo {{replace_unit}}'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'bottom_bracket_service'
);

update public.service_profiles
   set name = 'Mantención de Motor',
       service_family = 'bottom_bracket',
       description = 'Limpieza, engrase y mantención del pedalier / BB',
       customer_summary_template = 'Mantención pedalier {{bottom_bracket_family}}',
       mechanic_summary_template = 'Pedalier / BB {{bottom_bracket_family}} · Síntoma {{symptom}} · Reemplazo {{replace_unit}}',
       updated_at = now()
 where tenant_id is null
   and key = 'bottom_bracket_service';

insert into public.service_profile_questions (
  id,
  tenant_id,
  service_profile_id,
  key,
  label,
  question_type,
  is_required,
  sort_order,
  options_json
)
select
  seed.id,
  null,
  sp.id,
  seed.key,
  seed.label,
  seed.question_type,
  seed.is_required,
  seed.sort_order,
  seed.options_json
from public.service_profiles sp
join (
  values
    ('00000000-0021-0001-0000-000000000001'::uuid, 'bottom_bracket_family', 'Familia pedalier / BB', 'single_select', true, 10,
     '[{"value":"bsa_threaded","label":"BSA roscado"},{"value":"pressfit","label":"Pressfit"},{"value":"bb30_pf30","label":"BB30 / PF30"},{"value":"mid","label":"Mid / BMX"},{"value":"one_piece","label":"One-piece"},{"value":"other","label":"Otro"},{"value":"unknown","label":"Desconocido"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000002'::uuid, 'symptom', 'Síntoma principal', 'single_select', false, 20,
     '[{"value":"play","label":"Juego"},{"value":"noise","label":"Ruido"},{"value":"roughness","label":"Aspereza / roce interno"},{"value":"tightness","label":"Apriete / dureza"},{"value":"preventive","label":"Mantención preventiva"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000003'::uuid, 'replace_unit', '¿Reemplazar unidad / rodamientos?', 'boolean', false, 30,
     '[]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'bottom_bracket_service'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

insert into public.service_profile_targets (
  tenant_id,
  service_profile_id,
  target_family,
  target_position_mode,
  target_rules
)
select null, sp.id, 'bottom_bracket', 'none', '{}'::jsonb
from public.service_profiles sp
where sp.tenant_id is null
  and sp.key in ('bottom_bracket_adjustment', 'bottom_bracket_service')
  and not exists (
    select 1
      from public.service_profile_targets spt
     where spt.tenant_id is null
       and spt.service_profile_id = sp.id
       and spt.target_family = 'bottom_bracket'
       and spt.target_position_mode = 'none'
  );

-- ============================================================
-- Viñabike bottom-bracket category bridge
-- ============================================================

with desired(category_id, category_name, technical_family) as (
  values
    ('52bd08ee-7cbc-4193-b363-c11960e7efbe'::uuid, 'Motor', 'bottom_bracket'),
    ('73556edd-24ab-4403-8c50-6810fbf60cd9'::uuid, 'Ejes de motor', 'bottom_bracket'),
    ('08384ffb-ab73-4b0f-80dc-7840f0552450'::uuid, 'Rodamientos Motor', 'bottom_bracket')
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
    ('52bd08ee-7cbc-4193-b363-c11960e7efbe'::uuid, 'Motor', 'bottom_bracket'),
    ('73556edd-24ab-4403-8c50-6810fbf60cd9'::uuid, 'Ejes de motor', 'bottom_bracket'),
    ('08384ffb-ab73-4b0f-80dc-7840f0552450'::uuid, 'Rodamientos Motor', 'bottom_bracket')
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

-- ============================================================
-- Viñabike service mappings
-- ============================================================

with desired_mappings as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    p.id as product_id,
    sp.id as service_profile_id
  from (
    values
      ('Ajuste de motor', 'bottom_bracket_adjustment'),
      ('Limpieza y engrase de caja de motor', 'bottom_bracket_service'),
      ('Mantención De Motor', 'bottom_bracket_service')
  ) as desired(product_name, profile_key)
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.product_type = 'service'
   and p.name = desired.product_name
  join public.service_profiles sp
    on sp.tenant_id is null
   and sp.key = desired.profile_key
)
update public.service_product_profile_mappings spm
   set status = 'inactive'
  from desired_mappings dm
 where spm.tenant_id = dm.tenant_id
   and spm.product_id = dm.product_id
   and spm.status = 'active'
   and spm.service_profile_id <> dm.service_profile_id;

with desired_mappings as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    p.id as product_id,
    sp.id as service_profile_id
  from (
    values
      ('Ajuste de motor', 'bottom_bracket_adjustment'),
      ('Limpieza y engrase de caja de motor', 'bottom_bracket_service'),
      ('Mantención De Motor', 'bottom_bracket_service')
  ) as desired(product_name, profile_key)
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.product_type = 'service'
   and p.name = desired.product_name
  join public.service_profiles sp
    on sp.tenant_id is null
   and sp.key = desired.profile_key
)
update public.service_product_profile_mappings spm
   set status = 'active'
  from desired_mappings dm
 where spm.tenant_id = dm.tenant_id
   and spm.product_id = dm.product_id
   and spm.service_profile_id = dm.service_profile_id;

with desired_mappings as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    p.id as product_id,
    sp.id as service_profile_id
  from (
    values
      ('Ajuste de motor', 'bottom_bracket_adjustment'),
      ('Limpieza y engrase de caja de motor', 'bottom_bracket_service'),
      ('Mantención De Motor', 'bottom_bracket_service')
  ) as desired(product_name, profile_key)
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.product_type = 'service'
   and p.name = desired.product_name
  join public.service_profiles sp
    on sp.tenant_id is null
   and sp.key = desired.profile_key
)
insert into public.service_product_profile_mappings (
  tenant_id,
  product_id,
  service_profile_id,
  status
)
select
  dm.tenant_id,
  dm.product_id,
  dm.service_profile_id,
  'active'
from desired_mappings dm
where not exists (
  select 1
    from public.service_product_profile_mappings spm
   where spm.tenant_id = dm.tenant_id
     and spm.product_id = dm.product_id
     and spm.service_profile_id = dm.service_profile_id
);