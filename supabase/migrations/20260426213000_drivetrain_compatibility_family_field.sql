-- ==========================================================================
-- DRIVETRAIN COMPATIBILITY FAMILY FIELD
-- ==========================================================================
-- Adds a first-class persisted drivetrain compatibility family field to the
-- global product ficha templates. This field is broader than
-- drivetrain_platform / chain_profile_family / shift_actuation_family and is
-- intentionally not derived from raw commercial brand text.
--
-- Safe backfill below only promotes existing structured drivetrain signals.
-- ============================================================================

insert into spec_definitions (
  tenant_id,
  key,
  label,
  description,
  data_type,
  unit,
  allowed_values,
  validation_rules,
  is_filterable,
  is_required_by_default,
  is_compatibility_relevant,
  is_customer_visible,
  is_mechanic_visible,
  group_name,
  sort_order
)
values (
  null,
  'drivetrain_compatibility_family',
  'Familia compatibilidad transmision',
  'Familia amplia de compatibilidad o ecosistema tecnico declarado por el fabricante. No confundir con la marca comercial del producto.',
  'multi_select',
  null,
  '["Ecosistema Shimano","Ecosistema SRAM","Ecosistema Campagnolo","Ecosistema Microshift","KMC multicompatible","Universal / generico","Single speed / BMX","Otro","Desconocido / sin confirmar"]'::jsonb,
  '{}'::jsonb,
  true,
  false,
  true,
  true,
  true,
  'Compatibilidad',
  12
)
on conflict (key) where tenant_id is null do update
set label = excluded.label,
    description = excluded.description,
    data_type = excluded.data_type,
    unit = excluded.unit,
    allowed_values = excluded.allowed_values,
    validation_rules = excluded.validation_rules,
    is_filterable = excluded.is_filterable,
    is_required_by_default = excluded.is_required_by_default,
    is_compatibility_relevant = excluded.is_compatibility_relevant,
    is_customer_visible = excluded.is_customer_visible,
    is_mechanic_visible = excluded.is_mechanic_visible,
    group_name = excluded.group_name,
    sort_order = excluded.sort_order,
    updated_at = now();

with field_rows(template_key, helper_text, sort_order) as (
  values
    ('chain', 'Familia amplia de compatibilidad/ecosistema declarada por la caja; no usar la marca comercial como atajo.', 20),
    ('chain_link', 'Familia amplia declarada por la cadena/conector; perfil y plataforma refinan despues.', 20),
    ('cassette', 'Familia amplia declarada por el cassette; plataforma y driver refinan la decision.', 20),
    ('freewheel', 'Familia amplia declarada por la rueda libre; no duplicar solo desde marca.', 20),
    ('fixed_cog', null, 20),
    ('rear_derailleur', 'Familia amplia del ecosistema que el cambio trasero declara compatibilizar.', 20),
    ('front_derailleur', null, 30),
    ('shifter', null, 40),
    ('crankset', 'Familia amplia compatible con la transmision que este conjunto pretende servir.', 50),
    ('chainring', null, 30),
    ('chain_guide', null, 20),
    ('drivetrain_kit', 'Familia amplia del kit; plataforma, perfil e indexado refinan despues.', 40)
)
insert into spec_template_fields (
  tenant_id,
  template_id,
  spec_definition_id,
  is_required,
  section_key,
  sort_order,
  helper_text
)
select
  null,
  st.id,
  sd.id,
  false,
  'compatibility',
  fr.sort_order,
  fr.helper_text
from field_rows fr
join spec_templates st
  on st.tenant_id is null
 and st.key = fr.template_key
join spec_definitions sd
  on sd.tenant_id is null
 and sd.key = 'drivetrain_compatibility_family'
on conflict (template_id, spec_definition_id) do update
set is_required = excluded.is_required,
    section_key = excluded.section_key,
    sort_order = excluded.sort_order,
    helper_text = excluded.helper_text,
    updated_at = now();

with compatibility_def as (
  select id
  from spec_definitions
  where tenant_id is null
    and key = 'drivetrain_compatibility_family'
),
template_products as (
  select
    p.tenant_id,
    p.id as product_id,
    st.key as template_key
  from products p
  join category_tech_mappings ctm
    on ctm.tenant_id = p.tenant_id
   and ctm.category_id = p.category_id
  join spec_templates st
    on st.id = ctm.template_id
  where st.key in (
    'chain',
    'missing_link',
    'chain_link',
    'cassette',
    'freewheel',
    'fixed_cog',
    'rear_derailleur',
    'front_derailleur',
    'shifter',
    'chainring',
    'crankset',
    'drivetrain_kit',
    'chain_guide'
  )
),
definition_ids as (
  select key, id
  from spec_definitions
  where tenant_id is null
    and key in (
      'drivetrain_platform',
      'chain_profile_family',
      'shift_actuation_family',
      'chain_width_family',
      'chain_speeds',
      'chain_speed'
    )
),
signal_rows as (
  select
    tp.tenant_id,
    tp.product_id,
    lower(coalesce(platform.value_option, platform.value_text, platform.display_value, '')) as platform_text,
    lower(coalesce(profile.value_json::text, profile.value_option, profile.value_text, profile.display_value, '')) as profile_text,
    lower(coalesce(actuation.value_option, actuation.value_text, actuation.display_value, '')) as actuation_text,
    lower(coalesce(width.value_option, width.value_text, width.display_value, '')) as width_text,
    lower(coalesce(speed.value_json::text, speed.value_option, speed.value_text, speed.display_value, '')) as speed_text
  from template_products tp
  left join definition_ids platform_id on platform_id.key = 'drivetrain_platform'
  left join product_spec_values platform
    on platform.tenant_id = tp.tenant_id
   and platform.product_id = tp.product_id
   and platform.spec_definition_id = platform_id.id
  left join definition_ids profile_id on profile_id.key = 'chain_profile_family'
  left join product_spec_values profile
    on profile.tenant_id = tp.tenant_id
   and profile.product_id = tp.product_id
   and profile.spec_definition_id = profile_id.id
  left join definition_ids actuation_id on actuation_id.key = 'shift_actuation_family'
  left join product_spec_values actuation
    on actuation.tenant_id = tp.tenant_id
   and actuation.product_id = tp.product_id
   and actuation.spec_definition_id = actuation_id.id
  left join definition_ids width_id on width_id.key = 'chain_width_family'
  left join product_spec_values width
    on width.tenant_id = tp.tenant_id
   and width.product_id = tp.product_id
   and width.spec_definition_id = width_id.id
  left join definition_ids speed_json_id on speed_json_id.key = 'chain_speeds'
  left join product_spec_values speed_json
    on speed_json.tenant_id = tp.tenant_id
   and speed_json.product_id = tp.product_id
   and speed_json.spec_definition_id = speed_json_id.id
  left join definition_ids speed_text_id on speed_text_id.key = 'chain_speed'
  left join product_spec_values speed_text_row
    on speed_text_row.tenant_id = tp.tenant_id
   and speed_text_row.product_id = tp.product_id
   and speed_text_row.spec_definition_id = speed_text_id.id
  left join lateral (
    select
      coalesce(speed_json.value_json, to_jsonb(speed_text_row.value_text)) as value_json,
      speed_json.value_option,
      speed_text_row.value_text,
      coalesce(speed_json.display_value, speed_text_row.display_value) as display_value
  ) speed on true
),
family_rows as (
  select
    sr.tenant_id,
    sr.product_id,
    family
  from signal_rows sr
  cross join lateral unnest(array_remove(array[
    case
      when sr.platform_text like '%shimano%'
        or sr.platform_text like '%hg+%'
        or sr.platform_text like '%linkglide%'
        or sr.platform_text like '%cues%'
        or sr.profile_text like '%shimano hg+%'
        or sr.profile_text like '%shimano linkglide%'
        or sr.actuation_text like '%shimano%'
        or sr.actuation_text like '%dynasys%'
        or sr.actuation_text like '%sis%'
        or sr.actuation_text like '%linkglide%'
        or sr.actuation_text like '%cues%'
      then 'Ecosistema Shimano'
      else null
    end,
    case
      when sr.platform_text like '%sram%'
        or sr.platform_text like '%eagle%'
        or sr.platform_text like '%flat%top%'
        or sr.platform_text like '%t-type%'
        or sr.platform_text like '%transmission%'
        or sr.profile_text like '%sram eagle%'
        or sr.profile_text like '%sram flattop%'
        or sr.profile_text like '%sram t-type%'
        or sr.actuation_text like '%sram%'
        or sr.actuation_text like '%exact actuation%'
        or sr.actuation_text like '%x-actuation%'
        or sr.actuation_text like '%axs%'
        or sr.actuation_text like '%t-type%'
      then 'Ecosistema SRAM'
      else null
    end,
    case
      when sr.platform_text like '%campagnolo%'
        or sr.profile_text like '%campagnolo%'
        or sr.actuation_text like '%campagnolo%'
      then 'Ecosistema Campagnolo'
      else null
    end,
    case
      when sr.platform_text like '%microshift%'
        or sr.platform_text like '%advent%'
        or sr.platform_text like '%acolyte%'
        or sr.actuation_text like '%microshift%'
        or sr.actuation_text like '%advent%'
        or sr.actuation_text like '%acolyte%'
      then 'Ecosistema Microshift'
      else null
    end,
    case
      when sr.profile_text like '%kmc compatible%'
      then 'KMC multicompatible'
      else null
    end,
    case
      when sr.profile_text like '%universal 5-8v%'
        or sr.profile_text like '%universal 9-11v%'
        or sr.platform_text like '%friccion%'
        or sr.platform_text like '%universal%'
        or sr.actuation_text like '%friccion%'
        or sr.actuation_text like '%universal%'
      then 'Universal / generico'
      else null
    end,
    case
      when sr.platform_text like '%single%'
        or sr.platform_text like '%bmx%'
        or sr.profile_text like '%single speed / bmx%'
        or sr.width_text like '%1/8%'
        or sr.speed_text like '%"1"%'
      then 'Single speed / BMX'
      else null
    end
  ], null::text)) as family
),
aggregated_families as (
  select
    tenant_id,
    product_id,
    array_agg(distinct family order by family) as families
  from family_rows
  group by tenant_id, product_id
)
insert into product_spec_values (
  tenant_id,
  product_id,
  spec_definition_id,
  value_json,
  display_value,
  created_at,
  updated_at
)
select
  af.tenant_id,
  af.product_id,
  compatibility_def.id,
  to_jsonb(af.families),
  array_to_string(af.families, ', '),
  now(),
  now()
from aggregated_families af
cross join compatibility_def
where array_length(af.families, 1) is not null
on conflict (tenant_id, product_id, spec_definition_id) do nothing;