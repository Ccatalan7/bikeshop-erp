-- El vocabulario del motor, como se le dice en el taller.
--
-- Traduje en vez de mirar el catálogo. La bodega ya tenía las palabras y no
-- las usé: «Motor Sellado» y «Rodamiento Sellado Para Motor 163110-2RS» para
-- lo que puse como «Cartucho sellado»; «MOTOR INTEGRADO GIZABOSS» y
-- «Espaciador de Aluminio 2mm para Motor Integrado» para lo que puse como
-- «Copas externas»; «Cubeta», «Canastillo» y «Cono» como piezas separadas
-- para lo que puse como «Copa y cono»; «caja de motor» y «Pta Cuadrada» para
-- lo que puse como «caja del cuadro» e «interfaz eje».
--
-- Ninguno de esos productos dice «pedalier» tampoco: las cuatro categorías son
-- `Motor`, `Ejes de motor`, `Rodamientos Motor` y `Cubetas`, y los tres
-- servicios del taller son «Ajuste de motor», «Limpieza y engrase de caja de
-- motor» y «Mantención De Motor».
--
-- Un renombre de valor toca cuatro lugares a la vez y si se olvida uno las
-- reglas dejan de calzar en silencio: `allowed_values`, las condiciones y los
-- `allow` de las reglas, y los valores ya guardados en los 48 productos. Van
-- en la misma transacción, y el read-back afirma que ninguno quedó suelto.

begin;

-- ── 1. Los valores de construcción ─────────────────────────────────────────
update public.spec_definitions set
  allowed_values =
    '["Rodamiento sellado","Integrado","Cubetas y canastillo","A presión",'
    '"Roscado entre sí"]'::jsonb,
  label = 'Construcción',
  description = 'Cómo está armado por dentro. No cambia si calza, pero decide si se ajusta, cómo se sirve y qué servicio del taller aplica.',
  updated_at = now()
where key = 'bb_construction' and tenant_id is null;

-- ── 2. Las etiquetas que usan la palabra equivocada ────────────────────────
update public.spec_definitions set
  label = 'Caja de motor',
  description = 'La caja del cuadro donde entra el motor. Define rosca, diámetro y qué anchos existen.',
  updated_at = now()
where key = 'bb_shell_standard' and tenant_id is null;

update public.spec_definitions set
  label = 'Punta del eje',
  description = 'Cómo entra la biela en el eje. En el catálogo aparece como «Pta Cuadrada» cuando es cono cuadrado.',
  updated_at = now()
where key = 'spindle_interface' and tenant_id is null;

update public.spec_definitions set
  label = 'Puntas de eje que acepta',
  description = 'Qué ejes admite un motor que no trae el suyo. Acepta más de uno: hay cubetas que sirven para Hollowtech 24/24 y para GXP 22/24.',
  updated_at = now()
where key = 'spindle_interface_accepted' and tenant_id is null;

update public.spec_definitions set
  description = 'Milímetros de espaciador que trae el juego. Un motor integrado de 68 mm necesita 2,5 mm por lado; en una caja de 73 mm van sin ellos.',
  updated_at = now()
where key = 'bb_spacer_stack_mm' and tenant_id is null;

update public.spec_definitions set
  description = 'Si el producto trae el eje. Un motor sellado sí; un integrado no, el eje viene con la biela.',
  updated_at = now()
where key = 'includes_spindle' and tenant_id is null;

update public.spec_definitions set
  description = 'Diámetro exterior de la cubeta, medido sobre la rosca. 34,8 mm es el inglés corriente.',
  updated_at = now()
where key = 'bb_cup_outer_diameter_mm' and tenant_id is null;

update public.spec_definitions set
  description = 'Cantidad de bolitas por canastillo. Un canastillo 1/4 x 9 lleva nueve.',
  updated_at = now()
where key = 'bb_ball_count_per_side' and tenant_id is null;

-- ── 3. Las reglas, que llevan los valores como texto literal ───────────────
update public.spec_template_fields tf set
  visibility_rules = replace(replace(replace(replace(
    tf.visibility_rules::text,
    'Cartucho sellado', 'Rodamiento sellado'),
    'Copas externas', 'Integrado'),
    'Copa y cono', 'Cubetas y canastillo'),
    'Rodamientos prensados', 'A presión')::jsonb,
  option_rules = replace(replace(replace(replace(replace(
    tf.option_rules::text,
    'Cartucho sellado', 'Rodamiento sellado'),
    'Copas externas', 'Integrado'),
    'Copa y cono', 'Cubetas y canastillo'),
    'Rodamientos prensados', 'A presión'),
    'Thread-together', 'Roscado entre sí')::jsonb,
  updated_at = now()
from public.spec_templates t
where tf.template_id = t.id and t.key like 'bottom_bracket%';

-- ── 4. Los textos de ayuda ─────────────────────────────────────────────────
update public.spec_template_fields tf set
  helper_text = replace(replace(replace(replace(replace(replace(
    tf.helper_text,
    'cartucho sellado', 'rodamiento sellado'),
    'copas externas', 'motores integrados'),
    'copa y cono', 'cubetas y canastillo'),
    'este pedalier', 'este motor'),
    'un pedalier', 'un motor'),
    'pedalier', 'motor'),
  updated_at = now()
from public.spec_templates t
where tf.template_id = t.id and t.key like 'bottom_bracket%'
  and tf.helper_text is not null;

update public.spec_template_fields tf set
  helper_text = 'Una misma caja BSA acepta motor sellado, cubetas y canastillo, o integrado.',
  updated_at = now()
from public.spec_templates t, public.spec_definitions d
where tf.template_id = t.id and tf.spec_definition_id = d.id
  and t.key = 'bottom_bracket' and d.key = 'bb_construction';

-- ── 5. Los valores ya guardados en los 48 productos ────────────────────────
update public.product_spec_values v set
  value_option = case v.value_option
    when 'Cartucho sellado' then 'Rodamiento sellado'
    when 'Copas externas' then 'Integrado'
    when 'Copa y cono' then 'Cubetas y canastillo'
    when 'Rodamientos prensados' then 'A presión'
    when 'Thread-together' then 'Roscado entre sí'
    else v.value_option end,
  display_value = case v.value_option
    when 'Cartucho sellado' then 'Rodamiento sellado'
    when 'Copas externas' then 'Integrado'
    when 'Copa y cono' then 'Cubetas y canastillo'
    when 'Rodamientos prensados' then 'A presión'
    when 'Thread-together' then 'Roscado entre sí'
    else v.display_value end,
  updated_at = now()
from public.spec_definitions d
where v.spec_definition_id = d.id and d.key = 'bb_construction';

commit;
