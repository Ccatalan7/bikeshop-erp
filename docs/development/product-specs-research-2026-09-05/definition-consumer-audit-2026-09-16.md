# Auditoría de definiciones con consumidores — 2026-09-16

Segunda compuerta del llenado («cada definición que tiene consumidores»), hecha de forma
estructural y sólo de lectura por `scripts/inventory/audit_definition_consumers.py` sobre la
instantánea global de las 09:17Z (`global-audit-20260916/snapshot.json`, sha256 `adddd7c1…`) y
sobre las 80 funciones y 3 vistas de producción cuyo cuerpo lee tablas de fichas
(`definition-consumers-20260916/sql-consumers.json`). Un consumidor es cualquier fuente de
`lib/`, `supabase/functions/` o esas funciones que nombra una clave de definición como literal
entre comillas. Resultado completo en
[definition-consumer-audit-2026-09-16.json](definition-consumer-audit-2026-09-16.json).
Ningún dato cambió. Llenado técnico persistido: 0.

## Cifras

| Medida | Valor |
|---|---|
| Definiciones globales vivas | 901 |
| Leídas por algún consumidor por clave | 123 (66 activas en alguna plantilla, 53 `legacy` en todas sus plantillas, 4 en ninguna plantilla activa) |
| Sin ningún consumidor por clave | 778 (el editor, el validador, la ficha pública y el matcher las leen por plantilla, no por clave: no es un defecto) |
| Fuentes que leen claves | 209 (184 Dart, 13 edge, 12 funciones SQL) |
| Literales con forma de clave que no son definición | 284 (campos propios de bicicletas, ruedas y necesidades que comparten vocabulario; revisar sólo si un consumidor los pasa al motor) |

## Hallazgos

1. **La compatibilidad de taller sigue escrita para las plantillas originales.**
   `lib/modules/bikeshop/services/bike_product_compatibility_service.dart` nombra 99 claves: 54
   activas, **44 `legacy` en todas sus plantillas** y una que ya no está en ninguna plantilla
   activa (`bb_thread_standard`). Como el lector `get_product_spec_contexts_v1` excluye `legacy`,
   esas 44 reglas reciben vacío en los productos ya reemplazados y degradan a cautela o silencio;
   no emiten veredictos falsos (revisión de piezas de freno, ronda 226), pero la capacidad que
   prometían desapareció con los 37 reemplazos. Familias afectadas: pedalier (`bb_shell_*`,
   `bb_construction`, `bottom_bracket_family`, `spindle_interface_accepted`), transmisión
   (`drivetrain_*`, `chain_*`, `chainring_*`, `rear_derailleur_*`, `front_derailleur_*`,
   `freehub_type`, `cassette_cog_sequence`, `shift_actuation_family`), freno (`brake_type`,
   `brake_system`, `caliper_hydraulic`, `piston_count`, `fluid_type`, `bleed_port`,
   `hose_*`, `mount_standard`, `rotor_*`), rueda (`spoke_*`, `hub_spacing_mm`, `wheel_size`,
   `valve_*`) y dirección (`headset_standard`, `steerer_type`).
2. **La búsqueda en portales de proveedor pierde discriminadores.**
   `lib/shared/services/supplier_need_portal_search.dart` traduce 15 claves a tipos de pieza; 9
   son `legacy` (`bb_shell_standard`, `drivetrain_speeds`, `freehub_type`, `hub_spacing_mm`,
   `rotor_diameter_mm`, `spoke_holes`, `valve_length_mm`, `valve_type`, `wheel_size`). Además
   lee `seatpost_diameter_mm`, que está activa pero no es filtrable, así que el matcher la
   devuelve `unresolved`.
3. **La ficha pública de la tienda enumera claves retiradas.**
   `lib/public_store/pages/product_detail_page.dart` nombra 17 claves y 11 son `legacy`. La RPC
   pública ya las excluye; el efecto es que esas filas no aparecen y ningún sucesor las
   reemplaza en esa página.
4. **Restos en el cliente de fichas.** `product_spec_coherence.dart` conserva pares cableados
   sobre `tube_width_*` (hoy `legacy`; los pares vivos vienen de `scalar_ordered_pairs`) y
   `product_spec_contract.dart` nombra `rear_speeds`. `bikeshop_models.dart` usa
   `noise_status`, `overall_status` y `tubeless_status`, definiciones sin plantilla activa: son
   estados de la bicicleta, no fichas de producto.
5. **SQL y edge sin fuga.** Ninguna función de producción lee una clave `legacy` salvo
   `validate_product_spec_value_exact_drivetrain_fields` (`drivetrain_platform`,
   `shift_actuation_family`), que hoy no recibe escrituras porque el guardado rechaza cambiar
   un valor `legacy`. Las funciones edge (Merchant, asistente, WhatsApp) no leen claves de
   definición: reciben cargas ya proyectadas.

## Sucesores candidatos por radical (sin certificar)

`bb_shell_standard→bb_shell_ports`, `chainring_bolt_count→chainring_bolt_pattern_symmetric`,
`chainring_offset_mm→chainring_offset_declarations`, `chainring_teeth→chainring_teeth_rows/min/max`,
`freehub_type→freehub_bodies_accepted`, `front_derailleur_clamp_mm→front_derailleur_clamp_options`,
`piston_count→piston_count_value`, `rotor_diameter_mm→rotor_diameter_mm_value`,
`spoke_gauge→spoke_gauge_designation`, `valve_length_mm→valve_length_mm_value`,
`valve_type→valve_standard` (+ forma de base, obús). Las otras 40 claves `legacy` leídas no
tienen sucesor por radical: su reemplazo está en la adjudicación de cada familia
(`*-successors-adjudication-2026-09-16.md`, `brake-pieces-adjudication-2026-09-15.md`,
`drivetrain-kit-members-adjudication-2026-09-15.md`) y muchas cambiaron de forma (filas,
alternativas tipadas, perfiles de miembro), no sólo de nombre. Un consumidor no se migra
renombrando claves.

## Qué decide esto y qué no

- Cierra la parte estructural de la segunda compuerta: se sabe qué código lee qué clave y en qué
  estado está cada una. No juzga si el valor leído es correcto ni si dos consumidores resuelven
  la misma identidad y el mismo estado de compatibilidad: eso es la cuarta compuerta.
- El siguiente bloque de consumidores es la compatibilidad de taller, familia por familia, con
  el mapa de cada adjudicación y pruebas que demuestren que una regla vuelve a ver el dato en el
  sucesor (perfil de miembro incluido) sin inventar un veredicto donde antes había cautela.
- Antes del primer lote de llenado no hace falta migrar todos los consumidores: hace falta que
  la familia del lote tenga sus consumidores migrados o declarados en silencio, y que la ficha
  pública y el matcher muestren lo que se llene (flags `is_customer_visible`/`is_filterable`,
  hoy `false` en casi todos los sucesores).
