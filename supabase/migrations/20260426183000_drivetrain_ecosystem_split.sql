begin;

with definition_rows(
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
) as (
  values
    (
      'drivetrain_mode',
      'Modo transmision',
      'Rama principal de compatibilidad: derailleur o single speed / BMX / IGH.',
      'single_select',
      null,
      '["Derailleur","Single speed / BMX / IGH","Desconocido / sin confirmar"]'::jsonb,
      '{}'::jsonb,
      true,
      false,
      true,
      true,
      true,
      'Compatibilidad',
      12
    ),
    (
      'drivetrain_primary_ecosystem',
      'Familia tecnica / ecosistema principal',
      'Ecosistema tecnico principal declarado por el fabricante. No confundir con la marca comercial del producto.',
      'single_select',
      null,
      '["Ecosistema Shimano","Ecosistema SRAM","Ecosistema Campagnolo","Ecosistema Microshift","Universal / generico","Single speed / BMX","Otro","Desconocido / sin confirmar"]'::jsonb,
      '{}'::jsonb,
      true,
      false,
      true,
      true,
      true,
      'Compatibilidad',
      13
    ),
    (
      'drivetrain_declared_compatible_ecosystems',
      'Ecosistemas compatibles declarados',
      'Claims explicitos de compatibilidad cruzada impresos en la caja, por ejemplo Compatible Shimano. No usar para duplicar el ecosistema principal.',
      'multi_select',
      null,
      '["Ecosistema Shimano","Ecosistema SRAM","Ecosistema Campagnolo","Ecosistema Microshift","Universal / generico","Single speed / BMX","Otro","Desconocido / sin confirmar"]'::jsonb,
      '{}'::jsonb,
      true,
      false,
      true,
      true,
      true,
      'Compatibilidad',
      14
    ),
    (
      'drivetrain_compatibility_family',
      'Familia compatibilidad transmision',
      'Campo legado/interino que mezclaba ecosistema principal y claims compatibles. Mantener solo como fallback mientras la ficha migra al modelo nuevo.',
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
      17
    ),
    (
      'drivetrain_platform',
      'Plataforma transmision',
      'Ecosistema de compatibilidad declarado por el fabricante cuando afecta cadena, cassette, cambio, shifter o plato.',
      'single_select',
      null,
      '["Shimano HG / SIS","Shimano Hyperglide+","Shimano Linkglide / CUES","SRAM Eagle","SRAM FlatTop / AXS road","SRAM T-Type Transmission","Campagnolo","Microshift Advent / Acolyte","Friccion / universal","Single speed / BMX","Generico compatible","Desconocido / sin confirmar"]'::jsonb,
      '{}'::jsonb,
      true,
      false,
      true,
      true,
      true,
      'Compatibilidad',
      15
    ),
    (
      'chain_profile_family',
      'Perfil cadena',
      'Perfil o familia de cadena compatible: universal, HG+, Linkglide, Eagle, FlatTop, BMX/single speed, etc.',
      'multi_select',
      null,
      '["Universal 5-8v","Universal 9-11v","Shimano HG+","Shimano Linkglide / CUES","SRAM Eagle","SRAM FlatTop","SRAM T-Type","Campagnolo","KMC compatible","Single speed / BMX","Otro","Desconocido / sin confirmar"]'::jsonb,
      '{}'::jsonb,
      true,
      false,
      true,
      true,
      true,
      'Compatibilidad',
      16
    )
)
insert into public.spec_definitions (
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
select
  null,
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
from definition_rows
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

delete from public.spec_template_fields tf
using public.spec_templates st,
      public.spec_definitions sd
where tf.template_id = st.id
  and tf.spec_definition_id = sd.id
  and st.tenant_id is null
  and sd.tenant_id is null
  and st.key in (
    'chain',
    'chain_link',
    'cassette',
    'freewheel',
    'fixed_cog',
    'rear_derailleur',
    'front_derailleur',
    'shifter',
    'crankset',
    'chainring',
    'chain_guide',
    'drivetrain_kit'
  )
  and sd.key = 'drivetrain_compatibility_family';

with field_rows(template_key, spec_key, is_required, section_key, sort_order, helper_text) as (
  values
    ('chain', 'drivetrain_mode', false, 'compatibility', 15, 'Rama principal: derailleur o single speed / BMX / IGH.'),
    ('chain', 'drivetrain_primary_ecosystem', false, 'compatibility', 30, 'Ecosistema principal declarado por la caja. No usar la marca comercial como atajo.'),
    ('chain', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 40, 'Solo para claims explícitos como Compatible Shimano.'),
    ('chain', 'drivetrain_platform', false, 'compatibility', 50, 'Solo llenar si el fabricante declara una plataforma especifica.'),
    ('chain', 'chain_profile_family', false, 'compatibility', 60, 'Perfil de compatibilidad declarado por fabricante.'),

    ('chain_link', 'drivetrain_mode', false, 'compatibility', 15, 'Rama principal: derailleur o single speed / BMX / IGH.'),
    ('chain_link', 'drivetrain_primary_ecosystem', false, 'compatibility', 30, 'Ecosistema principal declarado por la cadena/conector.'),
    ('chain_link', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 40, 'Solo para claims explícitos impresos en el conector.'),
    ('chain_link', 'chain_profile_family', false, 'compatibility', 50, 'Debe coincidir con cadena y plataforma cuando aplica.'),

    ('cassette', 'drivetrain_primary_ecosystem', false, 'compatibility', 20, 'Ecosistema principal declarado por el cassette.'),
    ('cassette', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 25, 'Solo para claims explícitos de compatibilidad cruzada.'),
    ('cassette', 'drivetrain_platform', false, 'compatibility', 30, 'Plataforma declarada si afecta cadena/cambio/shifter.'),

    ('freewheel', 'drivetrain_primary_ecosystem', false, 'compatibility', 20, 'Ecosistema principal declarado por la rueda libre.'),
    ('freewheel', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 25, 'Solo para claims explícitos de compatibilidad cruzada.'),
    ('freewheel', 'drivetrain_platform', false, 'compatibility', 30, null),

    ('fixed_cog', 'drivetrain_primary_ecosystem', false, 'compatibility', 20, 'Normalmente single speed / BMX cuando el producto lo declara.'),
    ('fixed_cog', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 25, null),
    ('fixed_cog', 'drivetrain_platform', false, 'compatibility', 30, null),

    ('rear_derailleur', 'drivetrain_primary_ecosystem', false, 'compatibility', 20, 'Ecosistema principal que el cambio trasero declara servir.'),
    ('rear_derailleur', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 25, 'Solo para claims explícitos de compatibilidad cruzada.'),
    ('rear_derailleur', 'drivetrain_platform', false, 'compatibility', 30, null),

    ('front_derailleur', 'drivetrain_primary_ecosystem', false, 'compatibility', 30, null),
    ('front_derailleur', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 35, null),
    ('front_derailleur', 'drivetrain_platform', false, 'compatibility', 40, null),

    ('shifter', 'drivetrain_primary_ecosystem', false, 'compatibility', 40, null),
    ('shifter', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 45, null),
    ('shifter', 'drivetrain_platform', false, 'compatibility', 50, null),

    ('crankset', 'drivetrain_primary_ecosystem', false, 'compatibility', 50, 'Ecosistema principal compatible con la transmision que este conjunto pretende servir.'),
    ('crankset', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 55, 'Solo para claims explícitos de compatibilidad cruzada.'),
    ('crankset', 'drivetrain_platform', false, 'compatibility', 60, null),
    ('crankset', 'chain_profile_family', false, 'compatibility', 70, 'Perfil de cadena/plato declarado si aplica.'),

    ('chainring', 'drivetrain_primary_ecosystem', false, 'compatibility', 30, null),
    ('chainring', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 35, null),
    ('chainring', 'chain_profile_family', false, 'compatibility', 40, null),
    ('chainring', 'drivetrain_platform', false, 'compatibility', 50, null),

    ('chain_guide', 'drivetrain_primary_ecosystem', false, 'compatibility', 20, null),
    ('chain_guide', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 25, null),
    ('chain_guide', 'drivetrain_platform', false, 'compatibility', 30, null),

    ('drivetrain_kit', 'drivetrain_primary_ecosystem', false, 'compatibility', 40, 'Ecosistema principal del kit; plataforma, perfil e indexado refinan despues.'),
    ('drivetrain_kit', 'drivetrain_declared_compatible_ecosystems', false, 'compatibility', 45, 'Solo para claims explícitos de compatibilidad cruzada.'),
    ('drivetrain_kit', 'drivetrain_platform', false, 'compatibility', 50, null),
    ('drivetrain_kit', 'chain_profile_family', false, 'compatibility', 60, null)
)
insert into public.spec_template_fields (
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
  fr.is_required,
  fr.section_key,
  fr.sort_order,
  fr.helper_text
from field_rows fr
join public.spec_templates st
  on st.key = fr.template_key
 and st.tenant_id is null
join public.spec_definitions sd
  on sd.key = fr.spec_key
 and sd.tenant_id is null
on conflict (template_id, spec_definition_id) do update
set is_required = excluded.is_required,
    section_key = excluded.section_key,
    sort_order = excluded.sort_order,
    helper_text = excluded.helper_text,
    updated_at = now();

with legacy_values as (
  select
    psv.tenant_id,
    psv.product_id,
    case
      when psv.value_json is not null and jsonb_typeof(psv.value_json) = 'array'
        then psv.value_json
      when psv.value_option is not null
        then jsonb_build_array(psv.value_option)
      when psv.display_value is not null
        then jsonb_build_array(psv.display_value)
      else '[]'::jsonb
    end as raw_values
  from public.product_spec_values psv
  join public.spec_definitions legacy
    on legacy.id = psv.spec_definition_id
   and legacy.key = 'drivetrain_compatibility_family'
),
normalized as (
  select
    lv.tenant_id,
    lv.product_id,
    array_agg(distinct value order by value)
      filter (
        where value <> ''
          and value <> 'KMC multicompatible'
          and value <> 'Desconocido / sin confirmar'
          and value <> 'Otro'
      ) as ecosystems
  from legacy_values lv
  cross join lateral jsonb_array_elements_text(lv.raw_values) as value_rows(value)
  group by lv.tenant_id, lv.product_id
),
primary_target as (
  select
    tenant_id,
    product_id,
    ecosystems[1] as value_option,
    ecosystems[1] as display_value
  from normalized
  where coalesce(array_length(ecosystems, 1), 0) = 1
)
insert into public.product_spec_values (
  tenant_id,
  product_id,
  spec_definition_id,
  value_option,
  display_value
)
select
  pt.tenant_id,
  pt.product_id,
  sd.id,
  pt.value_option,
  pt.display_value
from primary_target pt
join public.spec_definitions sd
  on sd.key = 'drivetrain_primary_ecosystem'
 and sd.tenant_id is null
on conflict (tenant_id, product_id, spec_definition_id) do update
set value_option = excluded.value_option,
    display_value = excluded.display_value,
    updated_at = now();

with legacy_values as (
  select
    psv.tenant_id,
    psv.product_id,
    case
      when psv.value_json is not null and jsonb_typeof(psv.value_json) = 'array'
        then psv.value_json
      when psv.value_option is not null
        then jsonb_build_array(psv.value_option)
      when psv.display_value is not null
        then jsonb_build_array(psv.display_value)
      else '[]'::jsonb
    end as raw_values
  from public.product_spec_values psv
  join public.spec_definitions legacy
    on legacy.id = psv.spec_definition_id
   and legacy.key = 'drivetrain_compatibility_family'
),
normalized as (
  select
    lv.tenant_id,
    lv.product_id,
    array_agg(distinct value order by value)
      filter (
        where value <> ''
          and value <> 'KMC multicompatible'
          and value <> 'Desconocido / sin confirmar'
          and value <> 'Otro'
      ) as ecosystems
  from legacy_values lv
  cross join lateral jsonb_array_elements_text(lv.raw_values) as value_rows(value)
  group by lv.tenant_id, lv.product_id
),
declared_target as (
  select
    tenant_id,
    product_id,
    to_jsonb(ecosystems) as value_json,
    array_to_string(ecosystems, ', ') as display_value
  from normalized
  where coalesce(array_length(ecosystems, 1), 0) > 1
)
insert into public.product_spec_values (
  tenant_id,
  product_id,
  spec_definition_id,
  value_json,
  display_value
)
select
  dt.tenant_id,
  dt.product_id,
  sd.id,
  dt.value_json,
  dt.display_value
from declared_target dt
join public.spec_definitions sd
  on sd.key = 'drivetrain_declared_compatible_ecosystems'
 and sd.tenant_id is null
on conflict (tenant_id, product_id, spec_definition_id) do update
set value_json = excluded.value_json,
    display_value = excluded.display_value,
    updated_at = now();

commit;