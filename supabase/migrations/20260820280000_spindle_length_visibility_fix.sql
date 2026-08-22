-- El largo de eje se escondia mientras la interfaz siguiera sin contestar.
--
-- 20260820270000 dejo `spindle_length_mm` visible solo cuando
-- `spindle_interface` ya era una interfaz de eje propio. Verificado en la app
-- real: los 29 pedaliers del catalogo tienen su largo guardado y ninguno tiene
-- la interfaz confirmada — el nombre dice `P/CUADRADA`, que prueba que el cono
-- es cuadrado pero no si es JIS o ISO, asi que se dejo en blanco a proposito.
--
-- Con esa regla el campo desaparecia con 118 mm adentro. Y
-- `SpecEngineService.saveProductSpecValues` borra toda definicion de la
-- plantilla que no venga en el payload, o sea que abrir y guardar cualquiera de
-- esos 29 productos perdia el dato.
--
-- El criterio correcto es esconder cuando SE SABE que no aplica, no mientras no
-- se sabe: un Hollowtech, GXP, DUB, BB30 o one-piece no tiene largo propio que
-- declarar; una interfaz en blanco todavia puede tenerlo.
-- Lo fija `spec_cascade_bottom_bracket_test.dart`.

begin;

update public.spec_template_fields tf set
  visibility_rules =
    '[{"field": "includes_spindle", "operator": "eq", "value": true},'
    ' {"field": "spindle_interface", "operator": "not_in",'
    '  "value": ["Hollowtech / 24mm", "SRAM GXP 24/22", "SRAM DUB 28.99mm",'
    '            "BB30 30mm", "One-piece / americano"]}]'::jsonb,
  updated_at = now()
from public.spec_templates t, public.spec_definitions d
where tf.template_id = t.id and tf.spec_definition_id = d.id
  and t.key = 'bottom_bracket' and d.key = 'spindle_length_mm';

commit;
