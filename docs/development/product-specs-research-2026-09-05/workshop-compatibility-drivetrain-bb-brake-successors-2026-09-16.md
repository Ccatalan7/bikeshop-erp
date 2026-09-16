# Compatibilidad de taller: transmisión, pedalier y freno leen los sucesores — 2026-09-16

Segundo bloque del consumidor
(`lib/modules/bikeshop/services/bike_product_compatibility_service.dart`) tras las familias de
rueda ([workshop-compatibility-wheel-successors-2026-09-16.md](workshop-compatibility-wheel-successors-2026-09-16.md)).
Las 44 claves `legacy` que el servicio seguía leyendo en cassette, rueda libre, cadena,
conector, plato, biela, pedalier, cambios, mandos, freno y dirección eran invisibles para el
mecánico: el lector `get_product_spec_contexts_v1` excluye los campos `legacy`. Hoy, por ejemplo,
31 cassettes y 21 ruedas libres tienen `sprocket_count` y ninguna `drivetrain_speeds` visible; el
servicio no comparaba velocidades en ninguna de ellas.

## Cómo llegan los sucesores

Muchos sucesores cambiaron de forma: ya no son un escalar sino **filas** (`json`): configuraciones
documentadas del cambio, cuerpos de maza admitidos, pedalier requerido por combinación, montajes
de caja declarados, receta de rotor por rueda. El lector los entrega como el **texto JSON
guardado** (`{"schema_version":1,"rows":[…]}`), porque `spec_payload_display_internal_v1` trata
todo lo que no es número, booleano ni opción como texto. El servicio los decodifica
(`_specRows`) y acepta también un mapa o una lista ya decodificados. Cada fila de declaración
trae su veredicto en una de tres columnas (`status`, `declaration_result`, `verdict`); una fila
«Incompatible declarado / No compatible declarado / Excluido por la fuente» es una **negación del
fabricante** y pesa más que una coincidencia nominal.

## Qué cambia por familia (sucesor primero, original de respaldo)

| Familia | Antes leía (`legacy`) | Ahora lee | Veredicto nuevo |
|---|---|---|---|
| Cassette, rueda libre, piñón fijo | `drivetrain_speeds`, `freehub_type`, `drivetrain_platform` | `sprocket_count`, `cog_sequence` (filas: cuenta y rango), `cassette_spline_standard`, `freehub_bodies_accepted` (filas), `freewheel_thread_standard`, `cog_thread_standard`, `shift_technology`, `smallest/largest_cog_teeth` | Spline S y M son el cuerpo HG; L y L2 el cuerpo ruta 11/12 (el paréntesis de ayuda con «ROAD 11v» no se lee). `HYPERGLIDE` a secas es HG/SIS, `HYPERGLIDE+` es HG+. Un cuerpo «Incompatible declarado» refuta. El rango (`11-42T`) se nombra en la cautela. |
| Cambio trasero | `drivetrain_speeds`, `rear_derailleur_max_teeth`, `total_capacity`, `shift_actuation_family` | `rear_derailleur_application_configurations` (filas: platos × coronas, piñón mayor mín/máx, capacidad), `rear_derailleur_actuation_ratio_declaration`, `rear_derailleur_compatibility_claims`, `derailleur_cage_length`, `rear_derailleur_mount_type` | Velocidad y piñón mayor siguen refutando; una declaración «No compatible declarado» hacia el mando refuta; si hay configuraciones y **ninguna** calza con la bici (p. ej. 2x en un cambio documentado sólo 1x, o piñón mayor bajo el mínimo), cautela que las enumera. |
| Desviador delantero | `front_chainring_count`, `front_derailleur_clamp_mm`, `pull_direction` | `front_derailleur_application_configurations`, `front_derailleur_clamp_options`, `front_derailleur_cable_pull`, `front_derailleur_mount_type` | Coincidencia de platos como antes; documentado para otra cantidad de velocidades → cautela que lo dice; la cautela nombra tiro, montaje, abrazadera y plato grande máximo. |
| Mando | `drivetrain_speeds`, `front_chainring_count`, `shift_actuation_family` | `shifter_indexed_positions`, `shifter_units` (filas por lado), `shifter_actuation_mode`, `shifter_compatibility_claims`, `shifter_control_style` | «Velocidades» del mando vale para los dos lados: 2–3 son platos, 5–13 son coronas; los rangos no se cruzan. Dos filas de lados distintos hacen un par aunque falte `shifter_position`. Fricción o conmutable acepta cualquier familia de indexado. |
| Biela / volante | `spindle_interface`, `bottom_bracket_family`, `front_chainring_count` | `crank_axle_interface_declarations` (designación, norma de cono, geometría), `bottom_bracket_required` (filas caja + ancho), `crankset_bottom_bracket_supplied`, `included_chainring_count`, `chainring_teeth_rows`, `crank_arm_length_mm`, `crankset_construction` | Eje distinto sigue en cautela; pedalier requerido que **no** calza con la caja de la bici → cautela que nombra ambos; la ficha suma biela, platos y pedalier incluido. |
| Plato | `drivetrain_speeds`, `drivetrain_platform` | `teeth_count`, `chainring_bcd_mm`, `chainring_mount_type`, `chainring_package_kind`, `chainring_set_members`, `narrow_wide`, `chainring_compatibility_claims` | «No intercambiable declarado» con la plataforma de la bici refuta; un juego se rotula «Juego de N platos» con sus dientes. |
| Pedalier, cubeta, eje | `bb_shell_standard`, `bottom_bracket_family`, `bb_shell_width_mm`, `bb_shell_diameter_mm`, `spindle_interface_accepted` | `bb_installation_claims` (filas: caja + ancho exacto o intervalo + estado), `bb_shell_ports` (rosca o asiento medidos: 1.37" × 24 tpi = BSA, 36 × 24 = italiano, 47 = T47, 41 a presión = BB86/92, 42 = BB30, 46 = PF30/BB386, 51,5 = americano), `bb_accepted_spindles`, `spindle_interface` (vivo), `spindle_length_mm` | Conflicto de caja sólo si **todas** las configuraciones conflictúan; «Incompatible declarado» con la caja o el eje de la bici refuta; el ancho calza si alguna configuración lo cubre (intervalo incluido). |
| Cadena, conector | `drivetrain_platform`, `chain_connector_target` | `chain_application_declarations` (filas con coronas y veredicto), `connector_target_declarations`, `connector_reuse_limit` | Un sistema «Excluido por la fuente» que la bici declara refuta la cadena; el conector nombra cadenas admitidas y excluidas y sus usos. |
| Cáliper, pastilla, maneta, rotor, presentaciones | `fluid_type`, `brake_type`, `caliper_hydraulic`, `piston_count`, `mount_standard`, `rotor_diameter_mm` | `rotor_size_recipe` (filas por rueda: diámetro, montaje, adaptador), `brake_model_fluid_approvals`, `brake_circuits`, `brake_actuation`, `braking_surface`, `caliper_mount_interface`, `piston_count_value`, `cable_pull_required`, `compound_type`, `pad_retention`, `compatible_caliper_models`, `lever_*`, `brake_presentation`, `rotor_mount_type` | El diseño de freno no cambia: el tipo agregado de la bici no refuta una pieza. Lo nuevo: la receta de rotor del cáliper frente al rotor de esa rueda (coincide / documenta otro diámetro / falta el de la bici), y la cautela describe la pieza con sus propios campos («Pieza declarada: freno de disco, hidráulico, Post Mount, 2 pistones»). |
| Dirección | `headset_standard`, `steerer_type` | — | Sin cambio: la bici no registra dirección ni tubo (`bike_form_dialog.dart` no ofrece esas claves), así que un SHIS no tiene contra qué compararse. Queda en la regla de familia. |

Las claves sucesoras entraron en `_drivetrainRelevantSpecKeys` y `_brakeRelevantSpecKeys`, la
compuerta de «este producto trae algo que la regla sabe leer». `sprocket_count` entró en
`_drivetrainSpeedSpecKeys`.

## Evidencia

- `test/unit/bike_product_compatibility_service_test.dart`: 124 pruebas verdes (100 previas sin
  tocar + 24 nuevas en «drivetrain, bottom bracket and brake successor keys (2026-09)»):
  velocidad por `sprocket_count`, spline M vs HG y vs Micro Spline, filas de cuerpos admitidos
  como texto JSON con una negación, HYPERGLIDE vs HYPERGLIDE+, `cog_sequence` de 12 filas,
  rueda libre por rosca, configuraciones de cambio (calza, piñón mayor 52 > 51, 11v, 2x sin
  configuración), relación de accionamiento y negación hacia el mando, desviador con tiro y
  abrazadera 34,9, mando por lado y por filas, fricción, biela con eje Hollowtech y pedalier BSA
  68 (y DUB / Pressfit), plato con dientes y BCD y juego 36-22T, pedalier por `bb_installation_claims`
  (BSA 68/73 calza, BB92 vs BSA refuta, negación refuta), rosca medida 1.37" × 24 tpi, ejes
  admitidos, receta de rotor 160 vs 160 y vs 180, fluidos aprobados, pastilla con compuesto y
  cálipers documentados, rotor Centerlock, cadena excluida por T-Type, conector con usos.
- Analizador sin incidencias en el servicio y en la prueba.
- Trampa encontrada: `canonicalBrakeWheelValue` compara `'delantero'` en minúsculas y las
  opciones de fila vienen capitalizadas («Delantero»); el servicio pasa por
  `_canonicalWheelPosition` antes.

## Qué queda

- Los hechos `legacy` no migran solos: 34 pedalieres tienen `bb_shell_standard` y 0 tienen
  `bb_installation_claims`; 29 cassettes tienen `drivetrain_speeds` y 31 `sprocket_count`. Donde
  el sucesor es escalar, las lecturas de nombre ya lo llenan; donde es de filas (pedalier, cambio,
  cáliper) hace falta un llenado por investigación o una migración de datos revisada por familia.
- El asistente de compras y el matcher de identidad leen sus propias claves; este bloque no los
  toca.
