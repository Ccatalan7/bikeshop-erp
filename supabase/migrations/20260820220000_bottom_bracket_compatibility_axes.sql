-- Bottom bracket compatibility axes.
--
-- The pedalier ficha collapsed three independent facts into one mandatory
-- single-select `bottom_bracket_family`, mixing shell standards (BSA,
-- Pressfit) with spindle/construction facts (Cuadrado cartucho, Hollowtech
-- externo). A real product is often both at once, so the only truthful answer
-- was «Otro» — which is why 0 of 34 live pedalier products carried the field
-- and 12 of 34 bike profiles sit on `other` while claiming `confirmed = true`.
--
-- This migration splits the three axes, gives every finite fact a bounded
-- vocabulary, and adds the narrowing mechanism the cascade needs.
--
-- Deliberately NOT done here:
--   * `bottom_bracket_family` keeps existing on the bike side and in the
--     service wizard. Its bike-profile backfill is a separate reviewed pass.
--   * spindle length keeps a generous list rather than the seven "standard"
--     values: the live catalog holds 110.5, 113.5, 118.5, 124, 124.5, 125,
--     125.5 and 127, none of which are textbook values. An invented closed
--     list is worse than the free text it replaces.
--
-- Existing data touched: none. The whole pedalier neighbourhood (48 products
-- across four templates) holds exactly one spec value today
-- (`spindle_length_mm = 124.5`), and no field it depends on is detached here.

begin;

-- ---------------------------------------------------------------------------
-- 1. Option narrowing, as the sibling of visibility_rules.
--
-- `visibility_rules` answers "does this field exist given the other answers".
-- It cannot answer "which of its options are still possible", which is the
-- other half of a guided cascade: a BSA shell admits 68/73/83/100 mm, a
-- Pressfit shell admits 86.5/89.5/92/121. Keeping that in `spec_definitions`
-- is wrong — the definition owns the complete vocabulary that search and the
-- AI inspector validate against; the template field owns what is offerable
-- here and now.
-- ---------------------------------------------------------------------------

alter table public.spec_template_fields
  add column if not exists option_rules jsonb not null default '[]'::jsonb;

comment on column public.spec_template_fields.option_rules is
  'Narrowing rules evaluated against sibling answers. Each entry is '
  '{"field","operator","value","allow"}; when the condition matches, the '
  'offerable options are restricted to "allow". Matching rules intersect. '
  'An empty array offers the definition''s full allowed_values. This never '
  'widens beyond allowed_values and is not a validity check: '
  'spec_definitions.allowed_values stays authoritative for search.';

-- ---------------------------------------------------------------------------
-- 2. The three axes, plus the cup/bearing facts the catalog already needs.
--
-- Labels stay compact on purpose: assistant_inspect_inventory_schema_v3
-- truncates allowed_values at 480 characters, and a truncated vocabulary
-- silently narrows what the AI assistant believes it can filter on.
-- ---------------------------------------------------------------------------

insert into public.spec_definitions (
  tenant_id, key, label, description, data_type, unit,
  allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, group_name, sort_order
) values
  (null, 'bb_shell_standard', 'Caja del cuadro',
   'Cómo se monta el pedalier al cuadro. Define rosca, diámetro y anchos posibles.',
   'single_select', null,
   '["BSA 1.37x24","Italiano 36x24","T47","Frances 35x1","Suizo 35x1",'
   '"Euro BMX roscado 68","BB86 / BB92 41mm","PF30 46mm","BB30 42mm",'
   '"BB386EVO 46mm","BB90 / BB95","BBRight / OSBB","Mid BMX 41.2mm",'
   '"Spanish BMX 37mm","Americano 51.5mm"]'::jsonb,
   '{}'::jsonb, true, true, true, true, true, 'Pedalier', 58),

  (null, 'bb_construction', 'Construccion',
   'Como esta hecho por dentro. No cambia si calza, pero decide si se ajusta, como se sirve y que servicio aplica.',
   'single_select', null,
   '["Cartucho sellado","Copas externas","Copa y cono","Rodamientos prensados",'
   '"Thread-together"]'::jsonb,
   '{}'::jsonb, true, true, true, true, true, 'Pedalier', 59),

  (null, 'includes_spindle', 'Incluye eje',
   'Si el producto trae el eje. Un cartucho sellado si; unas copas externas no, el eje viene con la biela.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Pedalier', 66),

  (null, 'spindle_interface_accepted', 'Interfaces de eje que acepta',
   'Que ejes admite un pedalier que no trae el suyo. Acepta mas de uno: hay copas que sirven para Hollowtech 24/24 y para GXP 22/24.',
   'multi_select', null,
   '["Cuadrado JIS","Cuadrado ISO","Hollowtech / 24mm","SRAM GXP 24/22",'
   '"SRAM DUB 28.99mm","BB30 30mm","ISIS","Octalink","Con chaveta",'
   '"BMX 19mm","BMX 22mm","BMX 24mm","One-piece / americano","Powerspline"]'::jsonb,
   '{}'::jsonb, true, false, true, true, true, 'Pedalier', 67),

  (null, 'bb_cup_thread_pair', 'Mano de la rosca',
   'Combinacion de rosca de las cubetas. El ingles BSA lleva la copa fija a la izquierda; el italiano y buena parte de lo generico van ambas a la derecha.',
   'single_select', null,
   '["Derecha / Izquierda (BSA ingles)","Derecha / Derecha (italiano o generico)",'
   '"Sin rosca (a presion)"]'::jsonb,
   '{}'::jsonb, true, false, true, true, true, 'Pedalier', 68),

  (null, 'bb_cup_outer_diameter_mm', 'Diametro de cubeta',
   'Diametro exterior de la cubeta, medido sobre la rosca o el asiento.',
   'number', 'mm',
   '[34.8,35,36,37,41.2,51.5]'::jsonb,
   '{"min":30,"max":60}'::jsonb,
   true, false, true, true, true, 'Pedalier', 69),

  (null, 'bb_ball_size_in', 'Tamano de bolita',
   'Diametro de las bolitas del canastillo, en pulgadas.',
   'single_select', null,
   '["1/8","5/32","3/16","1/4"]'::jsonb,
   '{}'::jsonb, true, false, true, true, true, 'Rodamientos', 70),

  (null, 'bb_ball_count_per_side', 'Bolitas por lado',
   'Cantidad de bolitas por canastillo. Un canastillo 1/4 x 9 lleva nueve.',
   'number', null,
   '[7,9,11,12,13]'::jsonb,
   '{"min":5,"max":20}'::jsonb,
   true, false, true, true, true, 'Rodamientos', 71)
on conflict (key) where tenant_id is null do update set
  label = excluded.label,
  description = excluded.description,
  data_type = excluded.data_type,
  unit = excluded.unit,
  allowed_values = excluded.allowed_values,
  validation_rules = excluded.validation_rules,
  is_filterable = excluded.is_filterable,
  is_compatibility_relevant = excluded.is_compatibility_relevant,
  group_name = excluded.group_name,
  sort_order = excluded.sort_order,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 3. Bounded vocabularies on the facts that were free text or incomplete.
--
-- `spindle_interface` keeps its single-value meaning ("the spindle this
-- product has") and loses «Otro» / «Desconocido». Those two were never
-- standards: they are states of knowledge, and while they sit in the value
-- list the `confirmed` flag beside them cannot mean anything. Absence is how
-- this schema already says "not known".
-- ---------------------------------------------------------------------------

update public.spec_definitions set
  allowed_values =
    '["Cuadrado JIS","Cuadrado ISO","Hollowtech / 24mm","SRAM GXP 24/22",'
    '"SRAM DUB 28.99mm","BB30 30mm","ISIS","Octalink","Con chaveta",'
    '"BMX 19mm","BMX 22mm","BMX 24mm","One-piece / americano","Powerspline"]'::jsonb,
  is_compatibility_relevant = true,
  updated_at = now()
where key = 'spindle_interface' and tenant_id is null;

update public.spec_definitions set
  allowed_values = '[68,70,73,83,86.5,89.5,92,100,107,121]'::jsonb,
  validation_rules = '{"min":50,"max":125}'::jsonb,
  is_compatibility_relevant = true,
  updated_at = now()
where key = 'bb_shell_width_mm' and tenant_id is null;

update public.spec_definitions set
  allowed_values = '[37,41,41.2,42,46,51.5]'::jsonb,
  validation_rules = '{"min":30,"max":60}'::jsonb,
  is_compatibility_relevant = true,
  updated_at = now()
where key = 'bb_shell_diameter_mm' and tenant_id is null;

-- Observed in the live catalog: 103, 110.5, 113, 113.5, 118, 118.5, 122.5,
-- 124, 124.5, 125, 125.5, 127, 127.5. The rest are common market values.
update public.spec_definitions set
  allowed_values =
    '[103,107,110,110.5,113,113.5,116,118,118.5,119,121,122.5,124,124.5,'
    '125,125.5,126,127,127.5,128,131,135]'::jsonb,
  validation_rules = '{"min":100,"max":150}'::jsonb,
  is_compatibility_relevant = true,
  updated_at = now()
where key = 'spindle_length_mm' and tenant_id is null;

update public.spec_definitions set
  allowed_values = '[17,19,20,22,24,25.4,28.99,30]'::jsonb,
  validation_rules = '{"min":15,"max":32}'::jsonb,
  is_compatibility_relevant = true,
  updated_at = now()
where key = 'spindle_diameter_mm' and tenant_id is null;

-- ---------------------------------------------------------------------------
-- 4. Wire the axes into the four pedalier templates.
--
-- sort_order also decides section order: SpecTemplate.sections takes the
-- first-seen section over fields ordered by sort_order. Giving the
-- compatibility axes the lowest numbers is what stops the form asking for
-- measurements before it asks for the standard.
-- ---------------------------------------------------------------------------

insert into public.spec_template_fields (
  tenant_id, template_id, spec_definition_id, is_required, section_key,
  sort_order, visibility_rules, option_rules, helper_text
)
select null, t.id, d.id, f.is_required, f.section_key, f.sort_order,
       f.visibility_rules, f.option_rules, f.helper_text
from (values
  -- bottom_bracket: the complete unit.
  ('bottom_bracket', 'bb_shell_standard', true, 'compatibility', 10,
   '[]'::jsonb, '[]'::jsonb,
   'Empieza por aca: define la rosca, el diametro y que anchos existen.'),
  ('bottom_bracket', 'bb_construction', true, 'compatibility', 20,
   '[]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BB86 / BB92 41mm","PF30 46mm","BB30 42mm","BB386EVO 46mm",'
   '"BB90 / BB95","BBRight / OSBB"],'
   '"allow":["Rodamientos prensados","Copas externas"]},'
   '{"field":"bb_shell_standard","operator":"eq","value":"Americano 51.5mm",'
   '"allow":["Copa y cono"]}]'::jsonb,
   'Una misma caja BSA acepta cartucho sellado, copa y cono, o copas externas.'),
  ('bottom_bracket', 'spindle_interface', false, 'compatibility', 30,
   '[{"field":"includes_spindle","operator":"eq","value":true}]'::jsonb,
   '[{"field":"bb_construction","operator":"eq","value":"Copas externas",'
   '"allow":["Hollowtech / 24mm","SRAM GXP 24/22","SRAM DUB 28.99mm"]},'
   '{"field":"bb_construction","operator":"eq","value":"Copa y cono",'
   '"allow":["Cuadrado JIS","Cuadrado ISO","Con chaveta","One-piece / americano"]},'
   '{"field":"bb_shell_standard","operator":"eq","value":"Mid BMX 41.2mm",'
   '"allow":["BMX 19mm","BMX 22mm","BMX 24mm"]}]'::jsonb,
   'El eje que este pedalier trae.'),
  ('bottom_bracket', 'spindle_interface_accepted', false, 'compatibility', 35,
   '[{"field":"includes_spindle","operator":"eq","value":false}]'::jsonb,
   '[]'::jsonb,
   'Marca todas las que sirven. Hay copas que aceptan 24/24 y 22/24 a la vez.'),
  ('bottom_bracket', 'includes_spindle', true, 'contents', 40,
   '[]'::jsonb, '[]'::jsonb,
   'Un cartucho sellado trae el eje; unas copas externas no.'),
  ('bottom_bracket', 'bb_shell_width_mm', true, 'dimensions', 50,
   '[]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BSA 1.37x24","BB30 42mm","Euro BMX roscado 68"],'
   '"allow":[68,73,83,100]},'
   '{"field":"bb_shell_standard","operator":"eq","value":"Italiano 36x24",'
   '"allow":[70]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["BB86 / BB92 41mm","PF30 46mm","BB386EVO 46mm"],'
   '"allow":[86.5,89.5,92,107,121]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["Mid BMX 41.2mm","Spanish BMX 37mm","Americano 51.5mm"],'
   '"allow":[68,73]}]'::jsonb,
   null),
  ('bottom_bracket', 'bb_shell_diameter_mm', false, 'dimensions', 60,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BB86 / BB92 41mm","PF30 46mm","BB30 42mm","BB386EVO 46mm",'
   '"BB90 / BB95","BBRight / OSBB","Mid BMX 41.2mm","Spanish BMX 37mm",'
   '"Americano 51.5mm"]}]'::jsonb,
   '[]'::jsonb,
   'En las cajas roscadas manda la rosca, no el diametro del bore.'),
  ('bottom_bracket', 'spindle_length_mm', false, 'dimensions', 70,
   '[{"field":"includes_spindle","operator":"eq","value":true}]'::jsonb,
   '[]'::jsonb, null),
  ('bottom_bracket', 'spindle_diameter_mm', false, 'dimensions', 80,
   '[{"field":"includes_spindle","operator":"eq","value":true}]'::jsonb,
   '[]'::jsonb, null),

  -- bottom_bracket_cup: cups only, so it never carries a spindle.
  ('bottom_bracket_cup', 'bb_shell_standard', true, 'compatibility', 10,
   '[]'::jsonb, '[]'::jsonb, null),
  ('bottom_bracket_cup', 'bb_construction', true, 'compatibility', 20,
   '[]'::jsonb, '[]'::jsonb, null),
  ('bottom_bracket_cup', 'bb_cup_thread_pair', true, 'compatibility', 25,
   '[]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"eq","value":"BSA 1.37x24",'
   '"allow":["Derecha / Izquierda (BSA ingles)"]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["BB86 / BB92 41mm","PF30 46mm","BB30 42mm","Mid BMX 41.2mm"],'
   '"allow":["Sin rosca (a presion)"]}]'::jsonb,
   'DER/IZQ es el ingles; DER/DER aparece en italiano y en buena parte de lo generico.'),
  ('bottom_bracket_cup', 'spindle_interface_accepted', true, 'compatibility', 30,
   '[]'::jsonb, '[]'::jsonb,
   'Marca todas las que sirven.'),
  ('bottom_bracket_cup', 'bb_cup_outer_diameter_mm', false, 'dimensions', 50,
   '[]'::jsonb, '[]'::jsonb, null),

  -- bottom_bracket_axle: a loose spindle, so it is all spindle facts.
  -- A rule with no `field` is unconditional: a loose spindle only ever comes
  -- from a cup-and-cone or cartridge system, whatever else is answered.
  ('bottom_bracket_axle', 'bb_construction', false, 'compatibility', 5,
   '[]'::jsonb,
   '[{"allow":["Copa y cono","Cartucho sellado"]}]'::jsonb,
   'Un eje suelto vive en un sistema de copa y cono.'),
  ('bottom_bracket_axle', 'spindle_diameter_mm', false, 'dimensions', 30,
   '[]'::jsonb, '[]'::jsonb, null),

  -- bottom_bracket_bearing: the loose-ball retainer or the sealed cartridge.
  ('bottom_bracket_bearing', 'bb_ball_size_in', false, 'identification', 15,
   '[]'::jsonb, '[]'::jsonb,
   'Solo para canastillos de bolitas sueltas.'),
  ('bottom_bracket_bearing', 'bb_ball_count_per_side', false, 'identification', 16,
   '[]'::jsonb, '[]'::jsonb, null)
) as f(
  template_key, def_key, is_required, section_key, sort_order,
  visibility_rules, option_rules, helper_text
)
join public.spec_templates t
  on t.key = f.template_key and t.tenant_id is null
join public.spec_definitions d
  on d.key = f.def_key and d.tenant_id is null
on conflict (template_id, spec_definition_id) do update set
  is_required = excluded.is_required,
  section_key = excluded.section_key,
  sort_order = excluded.sort_order,
  visibility_rules = excluded.visibility_rules,
  option_rules = excluded.option_rules,
  helper_text = excluded.helper_text,
  updated_at = now();

-- ---------------------------------------------------------------------------
-- 5. Retire the two mis-axed fields from the pedalier templates.
--
-- `bottom_bracket_family` mixed shell with construction; `bb_thread_standard`
-- restated what the shell already fixes. Neither holds a live value on any
-- product in these templates. The definitions stay in place because the bike
-- profile and the service wizard still read `bottom_bracket_family`, and their
-- migration is a separate reviewed pass.
-- ---------------------------------------------------------------------------

delete from public.spec_template_fields tf
using public.spec_templates t, public.spec_definitions d
where tf.template_id = t.id
  and tf.spec_definition_id = d.id
  and t.tenant_id is null
  and d.tenant_id is null
  and t.key in (
    'bottom_bracket', 'bottom_bracket_cup',
    'bottom_bracket_axle', 'bottom_bracket_bearing'
  )
  and d.key in ('bottom_bracket_family', 'bb_thread_standard')
  and not exists (
    select 1 from public.product_spec_values psv
    where psv.spec_definition_id = d.id
  );

commit;
