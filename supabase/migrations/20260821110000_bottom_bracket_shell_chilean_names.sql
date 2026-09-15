-- «Caja inglesa» y las descripciones con el vocabulario del taller chileno.
--
-- La corrección anterior sacó la traducción, pero se apoyó en los títulos de la
-- bodega, que son de proveedor y están sucios. Referencias chilenas reales:
--
--   * Ruedabuena vende «Motor Miche Primato BSA (Caja Inglesa)» — BSA se dice
--     caja inglesa, y ninguna de las dos formas sobra: la sigla la usa el
--     catálogo y el nombre lo usa el mecánico.
--   * Challa Cycling: «Motor eje cuadrado sellado, más conocido como
--     simplemente motor sellado», y del integrado: «se tuvieron que
--     externalizar los rodamientos del motor y que quedaran fuera del cuadro».
--   * Una Velocidad (Santiago): «el sistema común estandarizado se llama
--     Inglés con rosca derecha-izquierda»; el cuadrado viene en ISO de 12,5 mm
--     (europeo) y JIS de 12,63 mm (Shimano); en press fit «los rodamientos van
--     dentro de una cubeta o cartucho que se inserta a presión en el cuadro».
--   * ibikes, Belda, Oxford, Bikefactory, Daski y Faucon nombran la categoría
--     entera «Motores», nunca «pedalier».
--
-- El diámetro de 34,8 mm que traen las cubetas de la bodega no es un dato
-- extra: es la rosca inglesa misma (1.37" = 34,8 mm). La etiqueta lo dice ahora
-- en vez de dejarlo como una medida suelta que parece independiente.

begin;

update public.spec_definitions set
  allowed_values =
    '["BSA / Caja inglesa 1.37x24","Italiano 36x24","T47","Francés 35x1",'
    '"Suizo 35x1","Euro BMX roscado 68","BB86 / BB92 41mm","PF30 46mm",'
    '"BB30 42mm","BB386EVO 46mm","BB90 / BB95","BBRight / OSBB",'
    '"Mid BMX 41.2mm","Spanish BMX 37mm","Americano 51.5mm"]'::jsonb,
  description = 'La caja del cuadro donde entra el motor. La inglesa es la corriente en Chile: rosca derecha-izquierda de 1.37" x 24.',
  updated_at = now()
where key = 'bb_shell_standard' and tenant_id is null;

update public.spec_definitions set
  description = 'Cómo está armado por dentro. Un motor sellado no se ajusta ni se sirve; uno de cubetas y canastillo sí; en el integrado los rodamientos quedan fuera de la caja.',
  updated_at = now()
where key = 'bb_construction' and tenant_id is null;

update public.spec_definitions set
  description = 'Cómo entra el volante en el eje. El cuadrado viene en JIS (12,63 mm, Shimano) e ISO (12,5 mm, europeo); Octalink e ISIS son estriados.',
  updated_at = now()
where key = 'spindle_interface' and tenant_id is null;

update public.spec_definitions set
  label = 'Diámetro de rosca de cubeta',
  description = 'Diámetro sobre la rosca de la cubeta. En caja inglesa son 34,8 mm, que es la misma rosca de 1.37".',
  updated_at = now()
where key = 'bb_cup_outer_diameter_mm' and tenant_id is null;

-- Las reglas llevan el valor como texto literal, en las cuatro plantillas.
update public.spec_template_fields tf set
  visibility_rules =
    replace(tf.visibility_rules::text, 'BSA 1.37x24', 'BSA / Caja inglesa 1.37x24')::jsonb,
  option_rules =
    replace(tf.option_rules::text, 'BSA 1.37x24', 'BSA / Caja inglesa 1.37x24')::jsonb,
  updated_at = now()
from public.spec_templates t
where tf.template_id = t.id and t.key like 'bottom_bracket%';

update public.spec_template_fields tf set
  helper_text = replace(tf.helper_text, 'caja BSA', 'caja inglesa'),
  updated_at = now()
from public.spec_templates t
where tf.template_id = t.id and t.key like 'bottom_bracket%'
  and tf.helper_text is not null;

-- Y los 33 productos que ya la tenían guardada.
update public.product_spec_values v set
  value_option = 'BSA / Caja inglesa 1.37x24',
  display_value = 'BSA / Caja inglesa 1.37x24',
  updated_at = now()
from public.spec_definitions d
where v.spec_definition_id = d.id
  and d.key = 'bb_shell_standard' and v.value_option = 'BSA 1.37x24';

commit;
