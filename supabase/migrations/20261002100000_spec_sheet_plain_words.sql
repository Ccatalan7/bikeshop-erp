-- Las opciones y los nombres de campo de la ficha se leen en español de
-- taller (dueño, 2026-10-01: «hay opciones en inglés», al ver «Derailleur» en
-- la ficha de una cadena; y «la cadena era la punta del iceberg»).
--
-- La auditoría de las 107 fichas activas encontró, entre 648 opciones con
-- palabras, unas pocas en inglés llano («Derailleur», «Single speed / BMX /
-- IGH», «Missing link», «Pin», «Half link», «Down swing», «U-lock»), dos con
-- códigos de un documento de investigación («… sólo según filas C-731;
-- LINKGLIDE según C-649») y diez nombres de campo con instrucciones internas
-- («Puertos (uno por fila)», «Documento OEM de cotas (id y revisión)»). Los
-- nombres de oficio que el taller dice así («Post Mount», «Tapered»,
-- «Lock-on», «Narrow-wide») se quedan.
--
-- **La etiqueta de una opción es su identidad; el operador lee otra cosa.**
-- Renombrar `spec_definition_values.label` no es inocuo aquí: las reglas de
-- cada ficha la citan, el código del taller la compara («Derailleur»,
-- «Single speed / BMX / IGH», «Braze-on» y «One-piece / americano» son
-- constantes de `drivetrain_canonical_data.dart` que también usan las 15
-- fichas de bicicleta), una app instalada sin actualizar seguiría comparando
-- el texto viejo, y el recibo de cada lectura del nombre está atado a ese
-- vocabulario (renombrarla deja muda la lectura). Por eso cada opción gana
-- `display_label`: lo que se muestra en la ficha y en la tienda. La etiqueta,
-- los códigos, las reglas, los hechos y las lecturas no cambian.
--
-- Los nombres de campo sí se corrigen en su lugar: son presentación, las
-- reglas citan la clave. Los diez son tablas o textos sin lecturas del nombre.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

alter table public.spec_definition_values
  add column if not exists display_label text;

comment on column public.spec_definition_values.display_label is
  'Lo que lee el operador o el cliente cuando la etiqueta, que es la identidad citada por reglas, código y lecturas del nombre, no está en español de taller. Nulo: se muestra la etiqueta.';

-- Una opción con dos filas globales iguales detiene todo: no se sabe a cuál
-- nombrar. Una que falta (una base local con el catálogo de antes) sólo avisa;
-- el read-back exige las 25 en producción.
do $guard$
declare r record; v_count integer;
begin
  for r in select * from (values
    ('drivetrain_mode','Derailleur','Con cambio trasero'),
    ('drivetrain_mode','Single speed / BMX / IGH','Una velocidad, BMX o cambios en la maza'),
    ('chain_connector_type','Missing link','Eslabón rápido (missing link)'),
    ('chain_connector_type','Pin','Pasador (pin)'),
    ('chain_connector_type','Half link','Medio eslabón (half link)'),
    ('front_derailleur_swing','Down swing','Hacia abajo (down swing)'),
    ('front_derailleur_swing','Side swing','Lateral (side swing)'),
    ('front_derailleur_pull_direction','Side swing','Lateral (side swing)'),
    ('front_derailleur_mount','Braze-on','Soldado al cuadro (braze-on)'),
    ('front_derailleur_mount_type','Braze-on','Soldado al cuadro (braze-on)'),
    ('spindle_interface','One-piece / americano','Una pieza (americano)'),
    ('spindle_interface_accepted','One-piece / americano','Una pieza (americano)'),
    ('control_part_kind','Noodle V-brake','Codo de V-brake (noodle)'),
    ('lock_kind','U-lock','Candado en U (U-lock)'),
    ('bar_fit_representation','Medidas discretas (filas)','Una lista de medidas'),
    ('bar_fit_representation','Rango continuo declarado por OEM','Un rango de medidas del fabricante'),
    ('cassette_spline_standard','Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)','Shimano HG spline L (ruta 11/12v)'),
    ('cassette_spline_standard','Shimano HG spline L2 (ROAD 12v dedicado)','Shimano HG spline L2 (ruta 12v)'),
    ('cassette_spline_standard','Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)','Shimano HG spline M (8/9/10v y MTB 11v)'),
    ('rear_drive_interface','Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)','Shimano HG spline L (ruta 11/12v)'),
    ('rear_drive_interface','Shimano HG spline L2 (ROAD 12v dedicado)','Shimano HG spline L2 (ruta 12v)'),
    ('rear_drive_interface','Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)','Shimano HG spline M (8/9/10v y MTB 11v)'),
    ('target_rear_drive_interface','Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)','Shimano HG spline L (ruta 11/12v)'),
    ('target_rear_drive_interface','Shimano HG spline L2 (ROAD 12v dedicado)','Shimano HG spline L2 (ruta 12v)'),
    ('target_rear_drive_interface','Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)','Shimano HG spline M (8/9/10v y MTB 11v)')
  ) as e(key,label,display_label) loop
    select count(*) into v_count
      from public.spec_definition_values v
      join public.spec_definitions d on d.id = v.spec_definition_id
     where d.tenant_id is null and d.key = r.key and v.tenant_id is null and v.label = r.label;
    if v_count > 1 then
      raise exception 'La opción % de % está % veces', r.label, r.key, v_count;
    elsif v_count = 0 then
      raise notice 'La opción % de % no existe aquí', r.label, r.key;
    end if;
  end loop;
end $guard$;

update public.spec_definition_values v set display_label='Con cambio trasero', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='drivetrain_mode' and v.tenant_id is null and v.label='Derailleur' and v.display_label is distinct from 'Con cambio trasero';
update public.spec_definition_values v set display_label='Una velocidad, BMX o cambios en la maza', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='drivetrain_mode' and v.tenant_id is null and v.label='Single speed / BMX / IGH' and v.display_label is distinct from 'Una velocidad, BMX o cambios en la maza';
update public.spec_definition_values v set display_label='Eslabón rápido (missing link)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='chain_connector_type' and v.tenant_id is null and v.label='Missing link' and v.display_label is distinct from 'Eslabón rápido (missing link)';
update public.spec_definition_values v set display_label='Pasador (pin)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='chain_connector_type' and v.tenant_id is null and v.label='Pin' and v.display_label is distinct from 'Pasador (pin)';
update public.spec_definition_values v set display_label='Medio eslabón (half link)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='chain_connector_type' and v.tenant_id is null and v.label='Half link' and v.display_label is distinct from 'Medio eslabón (half link)';
update public.spec_definition_values v set display_label='Hacia abajo (down swing)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='front_derailleur_swing' and v.tenant_id is null and v.label='Down swing' and v.display_label is distinct from 'Hacia abajo (down swing)';
update public.spec_definition_values v set display_label='Lateral (side swing)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='front_derailleur_swing' and v.tenant_id is null and v.label='Side swing' and v.display_label is distinct from 'Lateral (side swing)';
update public.spec_definition_values v set display_label='Lateral (side swing)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='front_derailleur_pull_direction' and v.tenant_id is null and v.label='Side swing' and v.display_label is distinct from 'Lateral (side swing)';
update public.spec_definition_values v set display_label='Soldado al cuadro (braze-on)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='front_derailleur_mount' and v.tenant_id is null and v.label='Braze-on' and v.display_label is distinct from 'Soldado al cuadro (braze-on)';
update public.spec_definition_values v set display_label='Soldado al cuadro (braze-on)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='front_derailleur_mount_type' and v.tenant_id is null and v.label='Braze-on' and v.display_label is distinct from 'Soldado al cuadro (braze-on)';
update public.spec_definition_values v set display_label='Una pieza (americano)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='spindle_interface' and v.tenant_id is null and v.label='One-piece / americano' and v.display_label is distinct from 'Una pieza (americano)';
update public.spec_definition_values v set display_label='Una pieza (americano)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='spindle_interface_accepted' and v.tenant_id is null and v.label='One-piece / americano' and v.display_label is distinct from 'Una pieza (americano)';
update public.spec_definition_values v set display_label='Codo de V-brake (noodle)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='control_part_kind' and v.tenant_id is null and v.label='Noodle V-brake' and v.display_label is distinct from 'Codo de V-brake (noodle)';
update public.spec_definition_values v set display_label='Candado en U (U-lock)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='lock_kind' and v.tenant_id is null and v.label='U-lock' and v.display_label is distinct from 'Candado en U (U-lock)';
update public.spec_definition_values v set display_label='Una lista de medidas', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='bar_fit_representation' and v.tenant_id is null and v.label='Medidas discretas (filas)' and v.display_label is distinct from 'Una lista de medidas';
update public.spec_definition_values v set display_label='Un rango de medidas del fabricante', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='bar_fit_representation' and v.tenant_id is null and v.label='Rango continuo declarado por OEM' and v.display_label is distinct from 'Un rango de medidas del fabricante';
update public.spec_definition_values v set display_label='Shimano HG spline L (ruta 11/12v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='cassette_spline_standard' and v.tenant_id is null and v.label='Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)' and v.display_label is distinct from 'Shimano HG spline L (ruta 11/12v)';
update public.spec_definition_values v set display_label='Shimano HG spline L2 (ruta 12v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='cassette_spline_standard' and v.tenant_id is null and v.label='Shimano HG spline L2 (ROAD 12v dedicado)' and v.display_label is distinct from 'Shimano HG spline L2 (ruta 12v)';
update public.spec_definition_values v set display_label='Shimano HG spline M (8/9/10v y MTB 11v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='cassette_spline_standard' and v.tenant_id is null and v.label='Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)' and v.display_label is distinct from 'Shimano HG spline M (8/9/10v y MTB 11v)';
update public.spec_definition_values v set display_label='Shimano HG spline L (ruta 11/12v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='rear_drive_interface' and v.tenant_id is null and v.label='Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)' and v.display_label is distinct from 'Shimano HG spline L (ruta 11/12v)';
update public.spec_definition_values v set display_label='Shimano HG spline L2 (ruta 12v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='rear_drive_interface' and v.tenant_id is null and v.label='Shimano HG spline L2 (ROAD 12v dedicado)' and v.display_label is distinct from 'Shimano HG spline L2 (ruta 12v)';
update public.spec_definition_values v set display_label='Shimano HG spline M (8/9/10v y MTB 11v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='rear_drive_interface' and v.tenant_id is null and v.label='Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)' and v.display_label is distinct from 'Shimano HG spline M (8/9/10v y MTB 11v)';
update public.spec_definition_values v set display_label='Shimano HG spline L (ruta 11/12v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='target_rear_drive_interface' and v.tenant_id is null and v.label='Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas C-731)' and v.display_label is distinct from 'Shimano HG spline L (ruta 11/12v)';
update public.spec_definition_values v set display_label='Shimano HG spline L2 (ruta 12v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='target_rear_drive_interface' and v.tenant_id is null and v.label='Shimano HG spline L2 (ROAD 12v dedicado)' and v.display_label is distinct from 'Shimano HG spline L2 (ruta 12v)';
update public.spec_definition_values v set display_label='Shimano HG spline M (8/9/10v y MTB 11v)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='target_rear_drive_interface' and v.tenant_id is null and v.label='Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)' and v.display_label is distinct from 'Shimano HG spline M (8/9/10v y MTB 11v)';

update public.spec_definitions set label='Diámetros de abrazadera admitidos', updated_at=now() where tenant_id is null and key='bar_clamp_configurations' and label='Diámetros de abrazadera admitidos (una fila por medida)';
update public.spec_definitions set label='Datos del fabricante que se contradicen', updated_at=now() where tenant_id is null and key='conflicting_claims' and label='Afirmaciones OEM en conflicto (una por fuente)';
update public.spec_definitions set label='Fluidos aprobados por el fabricante', updated_at=now() where tenant_id is null and key='brake_model_fluid_approvals' and label='Fluidos aprobados por modelo y edición';
update public.spec_definitions set label='Puertos', updated_at=now() where tenant_id is null and key='power_port_configurations' and label='Puertos (uno por fila)';
update public.spec_definitions set label='Certificaciones declaradas', updated_at=now() where tenant_id is null and key='certification_configurations' and label='Certificaciones declaradas (norma, edición, mercado, evidencia)';
update public.spec_definitions set label='Construcción declarada por el fabricante', updated_at=now() where tenant_id is null and key='helmet_construction' and label='Construcción declarada por el OEM';
update public.spec_definitions set label='Luces del producto', updated_at=now() where tenant_id is null and key='light_member_configurations' and label='Luces del producto (una fila por luz)';
update public.spec_definitions set label='Cartuchos admitidos o incluidos', updated_at=now() where tenant_id is null and key='co2_cartridge_configurations' and label='Cartuchos admitidos o incluidos (uno por fila)';
update public.spec_definitions set label='Puntos de anclaje de la parrilla', updated_at=now() where tenant_id is null and key='rack_mount_configurations' and label='Puntos de anclaje de la parrilla (uno por fila)';
update public.spec_definitions set label='Documento de medidas del fabricante', updated_at=now() where tenant_id is null and key='seatpost_dimension_document' and label='Documento OEM de cotas (id y revisión)';

-- Cada tabla de la ficha nombra sus filas: «Componente 1», «Circuito 2»,
-- «Puerto 3». 152 de 159 no lo hacían y el editor decía «Configuración» para
-- todo (los componentes de un freno, los puertos de una luz). Es
-- presentación: `row_label` no es parte del esquema guardado.
update public.spec_definitions d
   set validation_rules = d.validation_rules || jsonb_build_object('row_label', e.row_label),
       updated_at = now()
  from (values
    ('assembly_component_members','Componente'),
    ('assembly_configurations','Configuración'),
    ('assembly_frame_fitment_claims','Montaje'),
    ('assembly_frame_interfaces','Interfaz'),
    ('assembly_variant_identity','Variante'),
    ('assembly_wheel_members','Rueda'),
    ('auxiliary_part_requirements','Pieza'),
    ('bag_member_configurations','Bolso'),
    ('bag_rack_interface','Interfaz'),
    ('bar_clamp_configurations','Medida'),
    ('bb_accepted_spindles','Eje'),
    ('bb_declared_systems','Sistema'),
    ('bb_installation_claims','Montaje'),
    ('bb_shell_ports','Puerto'),
    ('bb_supplied_bearing_members','Rodamiento'),
    ('bead_seat_diameters_supported','Diámetro'),
    ('bicycle_drive_configurations','Montaje'),
    ('bicycle_size_configurations','Talla'),
    ('bicycle_wheel_positions','Rueda'),
    ('bottle_body_dimensions','Medida'),
    ('bottom_bracket_required','Motor'),
    ('brake_adapter_fitments','Aplicación'),
    ('brake_adapter_included_hardware','Pieza'),
    ('brake_bleed_ports','Puerto'),
    ('brake_circuits','Circuito'),
    ('brake_fluid_approvals','Fluido'),
    ('brake_fluid_declarations','Líquido'),
    ('brake_fluid_model_claims','Modelo'),
    ('brake_fluid_standard_claims','Norma'),
    ('brake_hydraulic_connections','Extremo'),
    ('brake_model_fluid_approvals','Fluido'),
    ('brake_piece_hydraulic_ports','Puerto'),
    ('brake_small_part_components','Pieza'),
    ('certification_configurations','Certificación'),
    ('chain_application_declarations','Aplicación'),
    ('chain_guide_assembled_weights','Peso'),
    ('chain_guide_frame_exclusions','Exclusión'),
    ('chain_guide_included_parts','Pieza'),
    ('chain_guide_mount_options','Montaje'),
    ('chain_mass_declarations','Peso'),
    ('chain_quick_links_supplied','Cierre rápido'),
    ('chainring_compatibility_claims','Declaración'),
    ('chainring_guard_configurations','Guarda'),
    ('chainring_guard_mounts','Montaje'),
    ('chainring_member_compatibility_claims','Declaración'),
    ('chainring_member_oem_pairings','Emparejado'),
    ('chainring_member_offsets','Desplazamiento'),
    ('chainring_oem_pairing_declarations','Emparejado'),
    ('chainring_offset_declarations','Desplazamiento'),
    ('chainring_set_members','Plato'),
    ('chainring_teeth_rows','Plato'),
    ('co2_cartridge_configurations','Cartucho'),
    ('cog_sequence','Corona'),
    ('combined_control_brake_configurations','Configuración de freno'),
    ('combined_control_shift_configurations','Configuración de cambio'),
    ('combined_control_units','Mando'),
    ('compatible_brake_models','Modelo'),
    ('compatible_caliper_models','Modelo'),
    ('compatible_derailleur_models','Cambio'),
    ('compatible_frames','Cuadro'),
    ('computer_contents','Pieza'),
    ('conflicting_claims','Dato'),
    ('connector_target_declarations','Cadena'),
    ('control_adjuster_threads','Rosca'),
    ('control_cable_end_options','Extremo'),
    ('control_cable_runs','Tramo'),
    ('control_housing_configurations','Funda'),
    ('crank_arm_compatibility_claims','Declaración'),
    ('crank_arm_unit_compatibility_claims','Declaración'),
    ('crank_arm_units','Brazo'),
    ('crank_axle_interface_by_member','Biela'),
    ('crank_axle_interface_declarations','Unión'),
    ('crankset_bottom_bracket_supplied','Motor'),
    ('crankset_compatibility_claims','Declaración'),
    ('derailleur_models_compatible','Cambio'),
    ('detangler_cable_configurations','Tramo'),
    ('detangler_cable_ends','Extremo'),
    ('dropper_control_configurations','Mando'),
    ('eyewear_lens_configurations','Lente'),
    ('fastener_component_configurations','Pieza'),
    ('fastener_kit_members','Pieza'),
    ('frame_geometry_measurements','Medida'),
    ('freehub_bodies_accepted','Núcleo'),
    ('front_derailleur_application_configurations','Configuración'),
    ('front_derailleur_clamp_options','Montaje'),
    ('front_derailleur_compatibility_claims','Declaración'),
    ('grip_clamp_torque_specifications','Abrazadera'),
    ('hanger_extender_claims','Modelo'),
    ('hanger_extender_limit_claims','Límite'),
    ('headset_component_fitments','Pieza'),
    ('headset_lower_bearing_configuration','Rodamiento'),
    ('headset_part_interfaces','Interfaz'),
    ('headset_torque_specifications','Apriete'),
    ('headset_upper_bearing_configuration','Rodamiento'),
    ('hub_brake_attachment_interfaces','Interfaz'),
    ('hub_brake_configurations','Configuración'),
    ('hub_package_pieces','Maza'),
    ('hydraulic_fitting_applications','Aplicación'),
    ('hydraulic_fitting_components','Pieza'),
    ('hydraulic_hose_end_configurations','Extremo'),
    ('hydraulic_hose_members','Tramo'),
    ('kit_members','Componente'),
    ('lever_cable_head_profiles','Cabeza'),
    ('lever_cable_pull_positions','Posición'),
    ('lever_inline_hydraulic_ports','Conexión'),
    ('light_member_configurations','Luz'),
    ('light_mode_configurations','Modo'),
    ('lockring_thread_interfaces','Interfaz'),
    ('nipple_tool_interfaces','Interfaz'),
    ('nutrition_facts','Nutriente'),
    ('pedal_bearing_configurations','Rodamiento'),
    ('power_budget_configurations','Combinación'),
    ('power_port_configurations','Puerto'),
    ('pulley_unit_fitment_declarations','Declaración'),
    ('pulley_units','Roldana'),
    ('pump_pressure_specifications','Presión'),
    ('rack_mount_configurations','Anclaje'),
    ('rack_top_interface','Interfaz'),
    ('rear_derailleur_application_configurations','Configuración'),
    ('rear_derailleur_compatibility_claims','Declaración'),
    ('repair_target_declarations','Superficie'),
    ('rim_brake_mount_fitments','Montaje'),
    ('rim_drilling_patterns','Patrón'),
    ('rim_spoke_tension_limits','Límite'),
    ('rotor_adapter_fitments','Extremo'),
    ('rotor_size_recipe','Configuración'),
    ('sealant_dose_recommendations','Dosis'),
    ('seatpost_saddle_configurations','Anclaje'),
    ('security_rating_configurations','Clasificación'),
    ('sensor_support_configurations','Sensor'),
    ('shifter_compatibility_claims','Declaración'),
    ('shifter_unit_compatibility_claims','Declaración'),
    ('shifter_units','Mando'),
    ('shock_size_declarations','Medida'),
    ('spacer_components','Separador'),
    ('spoke_supplied_nipples','Niple'),
    ('spoke_wire_sections','Sección'),
    ('tire_liner_fitments','Aplicación'),
    ('tire_width_range_mm','Rango'),
    ('tool_bits_included','Pieza'),
    ('tool_capabilities','Operación'),
    ('tool_pressure_specifications','Presión'),
    ('tube_fit_rows','Medida'),
    ('tubeless_kit_members','Componente'),
    ('tubeless_repair_plug_configurations','Mecha'),
    ('valve_part_configurations','Configuración'),
    ('wheel_compatible_claims','Declaración'),
    ('wheel_configurations','Rueda'),
    ('wheel_part_interfaces','Interfaz'),
    ('wheel_part_model_fitments','Modelo'),
    ('wheel_retention_configurations','Pieza'),
    ('wheel_size_declarations','Medida')
  ) as e(key, row_label)
 where d.tenant_id is null and d.key = e.key
   and d.validation_rules ? 'rows_schema'
   and not d.validation_rules ? 'row_label';

-- La tienda muestra el nombre visible de la opción; las reglas siguen
-- recibiendo la etiqueta.
create or replace function public.spec_option_display_internal_v1(
  p_definition_id uuid, p_label text, p_tenant_id uuid)
returns text
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce((
    select v.display_label
      from public.spec_definition_values v
     where v.spec_definition_id = p_definition_id
       and v.label = p_label
       and (v.tenant_id is null or v.tenant_id = p_tenant_id)
       and v.display_label is not null
     order by v.tenant_id nulls last
     limit 1), p_label)
$$;

revoke all on function public.spec_option_display_internal_v1(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.spec_option_display_internal_v1(uuid, text, uuid)
  to service_role;

-- El editor recibe la etiqueta (identidad que guarda) y el nombre visible.
CREATE OR REPLACE FUNCTION public.spec_template_editor_internal_v1(template_id uuid, tenant uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_variable
declare template jsonb; fields jsonb;
begin
   select jsonb_build_object('id',t.id,'tenant_id',t.tenant_id,'key',t.key,'name',t.name,
     'technical_family',t.technical_family,'contract_version',t.contract_version,
     'form_contract',public.spec_editor_rule_numbers_as_text_internal_v1(t.form_contract))
   into template from public.spec_templates t
   where t.id=template_id and t.is_active and (t.tenant_id is null or t.tenant_id=tenant);
   if template is null then raise exception 'Ficha no disponible' using errcode='42501'; end if;
   -- A malformed cross-tenant link fails closed instead of silently dropping a
   -- prerequisite and presenting a seemingly complete template.
   if exists(select 1 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
     where f.template_id=template_id and ((f.tenant_id is not null and f.tenant_id<>tenant)
       or (d.tenant_id is not null and d.tenant_id<>tenant))) then
     raise exception 'Campo no disponible para este tenant' using errcode='42501';
   end if;
   select coalesce(jsonb_agg(jsonb_build_object(
     'spec_definition_id',f.spec_definition_id,'section_key',f.section_key,'sort_order',f.sort_order,
     'is_required',f.is_required,'helper_text',f.helper_text,
     'default_value_json',case when d.data_type='number' then public.spec_json_numbers_as_text_internal_v1(f.default_value_json) else f.default_value_json end,
     'visibility_rules',public.spec_editor_rule_numbers_as_text_internal_v1(f.visibility_rules),
     'option_rules',public.spec_editor_rule_numbers_as_text_internal_v1(f.option_rules),
     'constraint_rules',public.spec_editor_rule_numbers_as_text_internal_v1(f.constraint_rules),
     'spec_definitions',jsonb_build_object('id',d.id,'key',d.key,'label',d.label,'data_type',d.data_type,
       'unit',d.unit,'description',d.description,'sort_order',d.sort_order,'allowed_values',d.allowed_values,
       'validation_rules',public.spec_editor_rule_numbers_as_text_internal_v1(d.validation_rules),
       'spec_definition_values',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'label',o.label,'display_label',o.display_label) order by o.sort_order,o.id),'[]'::jsonb)
         from public.spec_definition_values o where o.spec_definition_id=d.id and (o.tenant_id is null or o.tenant_id=tenant))))
     order by f.sort_order,f.id),'[]'::jsonb)
   into fields from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.template_id=template_id;
   template:=template||jsonb_build_object('fields',fields);
 return template;
end $function$;

CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
    join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as (
    select p.*,public.spec_active_product_values_internal_v1(p.id,p.template_id) vals from visible p
  ), assessed as (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.id definition_id,d.key,coalesce(p.form_contract->'labels'->>d.key,d.label) label,
      d.unit,d.data_type,d.validation_rules,p.form_contract,p.vals,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      -- Pending inference is retained in the editor, not asserted by the storefront.
      -- Confirmation and source are distinct: other origins keep their existing policy.
      and not exists (
        select 1 from public.spec_facts observed
        where observed.tenant_id=p_tenant_id and observed.subject_type='product'
          and observed.subject_id=p.id and observed.subject_scope is null
          and observed.spec_definition_id=d.id
          and observed.source='inferred' and not coalesce(observed.confirmed,false)
      )
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when jsonb_typeof(f.val)='array' then (select string_agg(public.spec_option_display_internal_v1(f.definition_id,e,p_tenant_id),', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      when f.data_type='single_select' then public.spec_option_display_internal_v1(f.definition_id,f.val#>>'{}',p_tenant_id)
      else f.val#>>'{}' end,f.unit,f.data_type
  from fields f order by f.section_order,f.sort_order,f.label
$function$;

commit;
