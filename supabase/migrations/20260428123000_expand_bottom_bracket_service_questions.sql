-- Expand bottom-bracket service wizards so they can carry richer
-- upstream truth into bike_profiles.technical_profile.values.

insert into service_profile_questions (
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
from service_profiles sp
join (
  values
    ('00000000-0020-0001-0000-000000000001'::uuid, 'bottom_bracket_family', 'Familia pedalier / BB', 'single_select', true, 10,
     '[{"value":"bsa_threaded","label":"BSA roscado"},{"value":"pressfit","label":"Pressfit"},{"value":"bb30_pf30","label":"BB30 / PF30"},{"value":"mid","label":"Mid / BMX"},{"value":"one_piece","label":"One-piece"},{"value":"other","label":"Otro"},{"value":"unknown","label":"Desconocido"}]'::jsonb),
    ('00000000-0020-0001-0000-000000000010'::uuid, 'bb_shell_width_mm', 'Ancho caja pedalier', 'single_select', false, 20,
     '[{"value":"68","label":"68 mm"},{"value":"70","label":"70 mm"},{"value":"73","label":"73 mm"},{"value":"83","label":"83 mm"},{"value":"86.5","label":"86.5 mm"},{"value":"89.5","label":"89.5 mm"},{"value":"92","label":"92 mm"},{"value":"100","label":"100 mm"},{"value":"107","label":"107 mm"},{"value":"121","label":"121 mm"}]'::jsonb),
    ('00000000-0020-0001-0000-000000000011'::uuid, 'bb_shell_diameter_mm', 'Diametro shell / bore', 'single_select', false, 30,
     '[{"value":"41","label":"41 mm"},{"value":"41.2","label":"41.2 mm"},{"value":"42","label":"42 mm"},{"value":"46","label":"46 mm"},{"value":"51.5","label":"51.5 mm"}]'::jsonb),
    ('00000000-0020-0001-0000-000000000012'::uuid, 'spindle_interface', 'Interfaz del eje', 'single_select', false, 40,
     '[{"value":"square_jis","label":"Cuadrado JIS"},{"value":"square_iso","label":"Cuadrado ISO"},{"value":"square_taper","label":"Cuadrado (sin confirmar JIS/ISO)"},{"value":"hollowtech_24","label":"Hollowtech / 24 mm"},{"value":"sram_dub","label":"SRAM DUB"},{"value":"isis","label":"ISIS"},{"value":"octalink","label":"Octalink"},{"value":"bmx_19","label":"BMX 19 mm"},{"value":"bmx_22","label":"BMX 22 mm"},{"value":"bmx_24","label":"BMX 24 mm"},{"value":"one_piece","label":"One-piece / americano"}]'::jsonb),
    ('00000000-0020-0001-0000-000000000002'::uuid, 'symptom', 'Síntoma principal', 'single_select', true, 50,
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

insert into service_profile_questions (
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
from service_profiles sp
join (
  values
    ('00000000-0021-0001-0000-000000000001'::uuid, 'bottom_bracket_family', 'Familia pedalier / BB', 'single_select', true, 10,
     '[{"value":"bsa_threaded","label":"BSA roscado"},{"value":"pressfit","label":"Pressfit"},{"value":"bb30_pf30","label":"BB30 / PF30"},{"value":"mid","label":"Mid / BMX"},{"value":"one_piece","label":"One-piece"},{"value":"other","label":"Otro"},{"value":"unknown","label":"Desconocido"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000010'::uuid, 'bb_shell_width_mm', 'Ancho caja pedalier', 'single_select', false, 20,
     '[{"value":"68","label":"68 mm"},{"value":"70","label":"70 mm"},{"value":"73","label":"73 mm"},{"value":"83","label":"83 mm"},{"value":"86.5","label":"86.5 mm"},{"value":"89.5","label":"89.5 mm"},{"value":"92","label":"92 mm"},{"value":"100","label":"100 mm"},{"value":"107","label":"107 mm"},{"value":"121","label":"121 mm"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000011'::uuid, 'bb_shell_diameter_mm', 'Diametro shell / bore', 'single_select', false, 30,
     '[{"value":"41","label":"41 mm"},{"value":"41.2","label":"41.2 mm"},{"value":"42","label":"42 mm"},{"value":"46","label":"46 mm"},{"value":"51.5","label":"51.5 mm"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000012'::uuid, 'spindle_interface', 'Interfaz del eje', 'single_select', false, 40,
     '[{"value":"square_jis","label":"Cuadrado JIS"},{"value":"square_iso","label":"Cuadrado ISO"},{"value":"square_taper","label":"Cuadrado (sin confirmar JIS/ISO)"},{"value":"hollowtech_24","label":"Hollowtech / 24 mm"},{"value":"sram_dub","label":"SRAM DUB"},{"value":"isis","label":"ISIS"},{"value":"octalink","label":"Octalink"},{"value":"bmx_19","label":"BMX 19 mm"},{"value":"bmx_22","label":"BMX 22 mm"},{"value":"bmx_24","label":"BMX 24 mm"},{"value":"one_piece","label":"One-piece / americano"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000002'::uuid, 'symptom', 'Síntoma principal', 'single_select', false, 50,
     '[{"value":"play","label":"Juego"},{"value":"noise","label":"Ruido"},{"value":"roughness","label":"Aspereza / roce interno"},{"value":"tightness","label":"Apriete / dureza"},{"value":"preventive","label":"Mantención preventiva"}]'::jsonb),
    ('00000000-0021-0001-0000-000000000003'::uuid, 'replace_unit', '¿Reemplazar unidad / rodamientos?', 'boolean', false, 60,
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