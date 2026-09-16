# fill-002: lecturas de nombre en lote — 2026-09-16

Segundo llenado técnico persistido, y el primero masivo: **842 hechos `name_reading` en 575
productos de 33 familias**, escritos por el RPC sancionado `record_product_spec_reading_v1`
como el actor real (`7bb76d88…`, administrador de Viñabike) sobre `scripts/db/query.sh`.
Ningún hecho se escribió por fuera del motor: cada uno pasó la cita literal, el vocabulario del
campo, la regla del hecho existente y la guardia de coherencia del producto, y dejó su recibo
en `spec_fact_readings`.

| Lectura posterior (producción) | Antes | Después |
|---|---:|---:|
| Hechos `name_reading` | 14 | 847 |
| Productos con al menos una lectura | 13 | 578 |
| Recibos `spec_fact_readings` | 14 | 847 |
| Hechos de otras procedencias (`supplier_text`, `import`, `inferred`, `mechanic`, `research`) | 1.645 | 1.645 |

843 llamadas: 842 `recorded` (833 hechos nuevos y 9 lecturas previas de pastillas reescritas
con su recibo), 1 `rejected` por la guardia de coherencia (`bearing_system` en un juego de
mazas: el campo no aplica a un envase de varias piezas). Recibo completo con veredicto por
llamada: [fill-002-name-readings-verdicts-2026-09-16.json](fill-002-name-readings-verdicts-2026-09-16.json)
(sha256 `9ab65d9d9112b11b6b41afe49af3d6ddf4f16a72e7f154675f4f8b37a4f535e5`).

## Qué se leyó y de dónde

Reglas por familia en `scripts/inventory/spec_name_reading_rules.py`: expresiones sobre la
notación comercial de los nombres chilenos (`36H`, `135x10mm`, `SGS`, `V/FRANCESA`, `9/16`,
`160mm`, `14-28T`, `104BCD`, `U-Lock`, `Bombín de pie`) que producen (campo, valor, cita). Sólo
campos filtrables no `legacy` de la plantilla viva; sólo `single_select`, `number` y `boolean`
(el servidor rechaza listas por diseño); nada inferido entre campos ni convertido de unidad.

| Familia | Campos leídos (hechos) |
|---|---|
| tube | `valve_length_mm_value` 89, `valve_standard` 72 |
| hub | `hub_package_position` 42, `spoke_hole_count` 35, `hub_old_mm` 18, `hub_axle_diameter_mm` 12, `bearing_system` 5, `hub_drive_receiver_kind` 4 |
| rim | `spoke_hole_count` 44, `rim_material` 14, `rim_wall_type` 14, `bead_seat_diameter_mm` 1 |
| brake_pad | `braking_surface` 23, `compound_type` 19, `rim_pad_length_mm` 5 |
| cassette | `sprocket_count` 32, `largest_cog_teeth` 3, `smallest_cog_teeth` 3 |
| shifter | `shifter_position` 20, `shifter_indexed_positions` 10, `shifter_actuation_mode` 1 |
| lock | `lock_kind` 27, `locking_mechanism` 10 |
| stem | `material` 13, `bar_clamp_diameter_mm` 10, `stem_length_mm` 10, `stem_kind` 2 |
| pedal | `body_material` 19, `pedal_thread_standard` 11, `pedal_type` 1, `sold_as` 1 |
| hub_axle | `wheel_position` 20, `axle_length_mm` 9 |
| chainring | `teeth_count` 14, `chainring_bcd_mm` 12, `chainring_package_kind` 2, `narrow_wide` 1 |
| crankset | `crank_arm_length_mm` 20, `crankset_construction` 3 |
| tire | `tire_use` 17, `tire_tpi` 12 |
| handlebar | `bar_clamp_diameter_mm` 10, `bar_width_mm` 6, `material` 4, `bar_style` 2 |
| rotor | `rotor_diameter_mm_value` 16, `rotor_nominal_thickness_mm` 3, `rotor_material` 2 |
| freewheel | `sprocket_count` 21 |
| seatpost | `seatpost_length_mm` 9, `material` 7, `seatpost_diameter_mm` 5 |
| light | `light_position` 13 |
| spoke | `spoke_length_mm` 5, `spoke_head_interface` 4, `pack_quantity` 3 |
| rear_derailleur | `derailleur_cage_length` 10 |
| helmet | `helmet_kind` 6, `intended_audience` 4 |
| saddle | `saddle_intended_use` 10 |
| pump | `pump_kind` 9 |
| front_derailleur | `front_derailleur_cable_pull` 3, `front_derailleur_mount_type` 1 |
| brake_lever | `lever_side` 3 |
| bottom_bracket | `spindle_length_mm` 2 |
| chain | `chain_width_family` 1, `link_count` 1 |
| grip | `sold_as` 2 |

Los 68 campos leídos son visibles al cliente y filtrables tras la publicación de flags del
09-16; la tienda los muestra sólo en productos con `is_published` y `show_on_website`
(compuerta de la tienda, no de la ficha: la llanta Alexrims MD30 tiene `spoke_hole_count = 28`
y no está publicada). Ejemplo público leído como anónimo tras el commit: cámara 10Ten
700x19/25 → «Largo de la válvula: 60 mm»; juego de mazas Qi&Su → «Posición de las mazas de este
envase: Juego delantera + trasera».

## Cómo se decidió qué no leer

- 220 lecturas posibles se descartaron antes de llamar porque el campo ya tenía un hecho de
  otra procedencia (el RPC las habría dejado como `kept_existing`).
- Booleanos cuyo vocabulario de etiqueta convierte el sustantivo del producto en término
  (`Cambio con clutch` → `cambio`; `Cadena direccional` → `cadena`) no se leen por nombre:
  darían «sí» a todos. Sólo `narrow_wide` («Narrow») y `rotor_floating` («Flotante»).
- Notaciones sin palabra de la etiqueta quedan sin leer aunque sean claras para un mecánico:
  válvulas `V/A`, `VF`, `A/V`, `F/V` (unas 45 cámaras), cadenas `1/8` (la etiqueta no tiene
  palabra de dos letras), pastillas «Resina» (la etiqueta dice `Orgánico`), patines de
  llanta sin la palabra «llanta», `Direct attachment` de Shimano (no es `Direct mount`).
- Velocidades de cambios, manillas y cadenas son listas (`multi_select`): el servidor las
  rechaza por diseño y siguen para investigación.
- Un juego de mazas no recibe `spoke_hole_count` ni `bearing_system` (van por piezas) y un
  pedalier integrado no recibe `spindle_interface`: lo dijo la guardia en el ensayo con
  rollback y las reglas se recortaron antes del commit.

## Cómo se hizo, para repetirlo

1. Catálogo vivo de campos filtrables (rol no legacy, etiquetas activas) y vínculos efectivos
   producto→plantilla con los hechos existentes, leídos de producción.
2. `spec_name_reading_rules.py --catalog … --bindings … --output candidates.json`: candidatos
   más una réplica offline de `spec_reading_rejection_internal_v1` (normalización, stems,
   token numérico, vocabulario booleano) que predijo 851 de 852 veredictos.
3. `fill_name_readings.py --mode dry`: las 852 llamadas reales en transacciones con rollback;
   5 rechazos de la guardia de coherencia → dos reglas recortadas.
4. `fill_name_readings.py --mode commit`: 23 transacciones, 843 llamadas, 842 `recorded`.
5. Lectura posterior por fuente y por campo, y lectura pública anónima de muestra.

Carpeta de ensayo con cada SQL, log y veredicto: `.tmp/product-spec-catalog/fill-002-name-readings/`.

## Segunda pasada (fill-002b): frenos de disco, horquillas y cierres

Con las mismas herramientas, 36 lecturas más en 25 productos, todas `recorded`: cáliper
(`brake_position` 9, `brake_actuation` 7), horquilla (`material` 5, `travel_mm` 4, `hub_old_mm` 2
desde `9x100mm`/`15X110mm`, `lockout` 2 desde «Bloqueo») y cierres de maza (`material` 7).
Lectura posterior: hechos `name_reading` 883, productos con lectura 603, recibos 883. Veredictos en
el bloque `second_pass` del mismo JSON.

**Total del día en lecturas de nombre: 878 hechos en 600 productos.** Con la aplicación de
investigación de fill-001, el llenado técnico persistido queda en 601 productos y 884 hechos,
todos sin confirmar.
