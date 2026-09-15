-- Una medida que no se puede filtrar es una medida invisible.
--
-- El asistente no resolvía «48mm» en ninguna redacción, y la causa no era el
-- lenguaje: `valve_length_mm` tenía `is_filterable = false`, y la inferencia
-- sólo considera campos filtrables. El campo nunca fue candidato, con **94
-- hechos cargados** esperando.
--
-- Lo mismo pasaba con otras tres medidas. Se abren todas: un número con unidad
-- —milímetros de largo, de grosor, mililitros de sellante— existe justamente
-- para comparar y acotar.
--
-- `diagnosis_notes` se queda fuera a propósito: es texto libre de un
-- diagnóstico, y filtrar por él no acota nada, sólo devuelve ruido.

begin;

update public.spec_definitions
set is_filterable = true, updated_at = now()
where tenant_id is null
  and key in (
    'valve_length_mm', 'rotor_thickness_mm', 'spoke_length_mm',
    'sealant_volume_ml'
  );

commit;
