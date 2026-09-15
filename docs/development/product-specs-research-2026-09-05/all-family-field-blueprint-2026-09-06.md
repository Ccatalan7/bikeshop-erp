# Blueprint de saneamiento de familias y campos — Claude, 2026-09-06

Autor: Claude (Fable 5.1, modo Code, Ultracode), revisor independiente. Codex
mantiene SQL, Dart y producto. Este documento y su JSON son los únicos archivos
de esta ronda; no se editó código, SQL ni datos, y no se tocó producción ni el
runtime. Nada de lo que sigue aprueba llenar: define **qué campos e interfaces
debe tener cada familia y clase** para que el saneamiento pueda demostrarse con
casos válidos, inválidos y desconocidos.

- JSON implementable: `all-family-field-blueprint-2026-09-06.json`, SHA-256 `250a32e47592aec332d39bb7672197510848f1c9ce78ba53580a4888aedac1a3`.
- Generado y validado por script: cada plantilla del snapshot tiene una entrada,
  cada campo existente tiene decisión, cada clase candidata de la revisión de
  Codex tiene destino y cada clase del registro de 1 605 productos físicos está
  cubierta (`coverage_check` en el JSON).

## 0. Entradas, cifras y límites

| Entrada | Uso |
|---|---|
| Snapshot legacy `2026-09-06T22:27:50.089535+00:00` (SHA `52d083195dd3d5d7…`) | 37 plantillas, 280 campos, 136 definiciones, 542 opciones, 1 664 productos, 6 sets comerciales `frontRear` con 12 componentes |
| `all-fields-semantic-review-2026-09-06.json` | 136 disposiciones semánticas de Codex: los grupos `bb_axes_mixed`, `freehub_interface_mixed`, `headset_upper_lower`, `intrinsic_vs_compatible_cardinality`, `rotor_diameter_recipe_mixed`, `brake_types_incomplete`, `open_numeric_vocabulary`, `iso_size_tuple`, `composed_kit` se resuelven campo a campo aquí |
| `assigned-product-ficha-claude-review-2026-09-06.json` (863) y `unmapped-product-ficha-codex-review-2026-09-06.json` (742) | 108 clases candidatas + 33 sin clase; 20 fichas con observación entre los 863 |
| `product-identity-image-review-2026-09-06.json` (21 imágenes) | sólo clase de objeto; nunca variante, MPN ni compatibilidad |
| `all-product-review-register-2026-09-06.json` (1 664) | 134 clases observadas en productos físicos; todas cubiertas |
| Fuentes primarias leídas hoy (§6) | Sheldon Brown, Park Tool, Shimano C-731/C-649, SRAM XD/XDR, Cane Creek SHIS, RockShox |

| Cifra | Valor |
|---|---:|
| Plantillas existentes con decisión | 37 (retain 4 · extend 30 · split 3 · retire 0) |
| Claves de definición usadas por las 37 plantillas / con decisión | 128 / 128 |
| Campos nuevos propuestos sobre plantillas existentes | 156 |
| Plantillas nuevas | 68 (tres sin productos hoy: `bicycle`, `frame`, `wheel`) |
| Clases candidatas del inventario sin ficha | 108 = 82 create (634 productos) + 26 reuse (75 productos) |
| Reclasificaciones observadas entre los 863 con ficha | 16 |
| Registros sin clase (uno a uno) | 33 = identity_review 16 · business_review 11 · create 6 |

Límites: el snapshot es anterior a `20260906150000` (los rangos `min/max` que
muestra ya fueron reemplazados por «positivo/entero» en producción); las
imágenes prueban clase de objeto; ninguna lista OEM de modelos existe todavía
en el catálogo, así que toda interfaz `reference_model_list` nace vacía; las
plantillas `bicycle`, `frame` y `wheel` no tienen productos y se incluyen por
instrucción del dueño y porque el taller guarda 849 hechos de sujetos «bike»
sin contrato.

## 1. Cómo leer el JSON

- `conventions.separation`: identidad · hechos intrínsecos · medidas · contenido
  (`kit_members`, `pack_quantity`) · declaraciones OEM · compatibilidad por
  filas/relación · evidencia · legado. Cada campo lleva `role`, `required_when`,
  `allowed_when`, `unit`, `evidence_required` y `legacy_action`.
- `relation_shape` de cada interfaz: `exact_match`, `set_membership`,
  `range_contains`, `row_alternatives_all_conditions` (filas AND, alternativas
  OR: el borrador 180000 de Codex), `adapter_recipe`, `reference_model_list`,
  `kit_members`, `none`. `blocking_rules` dice cuándo se devuelve incompatible;
  `unknown_conditions`, cuándo desconocido. Nunca hay «compatible» con un lado
  desconocido.
- `legacy_action` se decide **por plantilla**: la misma definición puede ser
  `legacy` en una familia y `compatibility` en otra (p. ej. `valve_type` es
  legado en `rim`, donde manda `valve_hole`, y compatibilidad en `tube`).
- `kit_members` describe composición técnica (groupset, freno completo, bielas
  + cubetas, juego de frenos). **No** implica `is_set`, hijos de inventario ni
  ratios de precio: los 6 sets comerciales `frontRear` del snapshot siguen
  siendo sets y además declaran su composición.
- `shared_vocabularies` trae cada valor con su fuente; los marcados
  `unverified` no pueden alimentar una regla bloqueante.
- `not_approved` lista explícitamente lo que este blueprint **no** aprueba.

## 2. Cobertura por bloque

| Bloque | Plantillas existentes | Plantillas nuevas | Productos del snapshot |
|---|---:|---:|---:|
| Transmisión | 20 | 6 | 355 |
| Ruedas y neumáticos | 9 | 10 | 487 |
| Dirección y suspensión | 1 | 8 | 57 |
| Frenos | 7 | 10 | 197 |
| Contacto | 0 | 7 | 104 |
| Eléctricos y electrónica | 0 | 4 | 32 |
| Ropa y protección del ciclista | 0 | 5 | 54 |
| Accesorios | 0 | 14 | 109 |
| Consumibles y taller | 0 | 3 | 96 |
| Café | 0 | 1 | 19 |

Servicios (59) siguen en su flujo; los 11 registros contables o de servicio
que aparecían como productos van a `business_review` (§5.4).

## 3. Las 37 plantillas existentes

`campos` = total / nuevos / legacy. La disposición **split** conserva la
familia y reparte campos o plantillas hijas; ninguna plantilla se retira.

| Plantilla | Familia | Productos | Disposición | Campos | Interfaces | Fuentes |
|---|---|---:|---|---|---|---|
| `bearing` | bearing | 9 | **extend** | 10 / 7 nuevos / 0 legacy | bearing_cartridge_fit | S17 |
| `bottom_bracket` | bottom_bracket | 34 | **extend** | 19 / 3 nuevos / 2 legacy | bb_to_frame_shell, bb_to_crank_spindle | S03, S09 |
| `bottom_bracket_axle` | bottom_bracket_axle | 3 | **extend** | 7 / 2 nuevos / 0 legacy | axle_to_cups_and_cranks | S03 |
| `bottom_bracket_bearing` | bottom_bracket_bearing | 3 | **extend** | 10 / 1 nuevos / 0 legacy | bb_bearing_fit | S17 |
| `bottom_bracket_cup` | bottom_bracket_cup | 8 | **extend** | 11 / 4 nuevos / 2 legacy | cup_to_frame_shell, cup_to_crank_spindle | S03, S09 |
| `brake_caliper` | brake_caliper | 11 | **split** | 18 / 5 nuevos / 4 legacy | caliper_to_frame_mount_and_rotor, caliper_to_pad, caliper_to_lever_actuation | S20, S27 |
| `brake_lever` | brake_lever | 15 | **extend** | 13 / 7 nuevos / 3 legacy | lever_to_brake, lever_to_handlebar | S06, S12, S27 |
| `brake_pad` | brake_pad | 53 | **split** | 17 / 8 nuevos / 2 legacy | disc_pad_to_caliper, rim_pad_to_brake | S12, S20 |
| `cassette` | cassette | 29 | **extend** | 12 / 6 nuevos / 3 legacy | cassette_to_hub_body, cassette_to_chain | S08, S11, S14, S15, S16 |
| `cassette_spacer` | cassette_spacer | 3 | **retain** | 4 / 1 nuevos / 1 legacy | spacer_to_body | S08, S14, S16 |
| `chain` | chain | 31 | **retain** | 13 / 0 nuevos / 2 legacy | chain_to_rear_speeds | S07, S11 |
| `chain_guide` | chain_guide | 3 | **extend** | 7 / 3 nuevos / 1 legacy | guide_to_frame_and_ring | S09 |
| `chain_link` | chain_link | 9 | **retain** | 13 / 0 nuevos / 3 legacy | connector_to_chain_model | S07 |
| `chainring` | chainring | 16 | **extend** | 15 / 4 nuevos / 4 legacy | ring_to_crank_spider, ring_to_chain | S02, S11 |
| `hydraulic_disc_brake` | complete_brake | 3 | **extend** | 16 / 4 nuevos / 2 legacy | complete_brake_to_frame | S20, S27 |
| `mechanical_disc_brake` | complete_brake | 0 | **extend** | 13 / 5 nuevos / 2 legacy | complete_brake_to_frame | S20 |
| `crank_arm` | crank_arm | 7 | **extend** | 7 / 2 nuevos / 0 legacy | arm_to_spindle, arm_to_pedal | S03, S13 |
| `crankset` | crankset | 27 | **extend** | 20 / 10 nuevos / 5 legacy | crank_to_bottom_bracket, crank_to_pedal, crank_to_chain | S03, S09, S11, S13 |
| `derailleur_hanger` | derailleur_hanger | 23 | **extend** | 7 / 3 nuevos / 2 legacy | hanger_to_frame | S17 |
| `derailleur_pulley` | derailleur_pulley | 7 | **extend** | 7 / 4 nuevos / 0 legacy | pulley_to_derailleur | S11 |
| `drivetrain_kit` | drivetrain_kit | 1 | **extend** | 15 / 3 nuevos / 6 legacy | kit_members_to_bike | S14, S15 |
| `fixed_cog` | fixed_cog | 0 | **retain** | 6 / 1 nuevos / 2 legacy | cog_to_hub_thread | S19 |
| `freewheel` | freewheel | 28 | **extend** | 11 / 5 nuevos / 3 legacy | freewheel_to_hub_thread | S08, S19 |
| `front_derailleur` | front_derailleur | 15 | **extend** | 15 / 5 nuevos / 4 legacy | fd_to_frame, fd_to_shifter | S11, S17 |
| `headset` | headset | 15 | **split** | 9 / 5 nuevos / 2 legacy | headset_to_frame_and_fork | S04, S10, S23 |
| `hub` | hub | 48 | **extend** | 17 / 11 nuevos / 3 legacy | hub_to_frame_dropout, hub_to_cassette_or_freewheel, hub_to_rotor, hub_to_rim_spokes | S05, S08, S14, S16, S20, S24, S28 |
| `rear_derailleur` | rear_derailleur | 35 | **extend** | 14 / 2 nuevos / 2 legacy | rd_to_drivetrain_range, rd_to_shifter, rd_to_hanger | S11, S17 |
| `rim` | rim | 41 | **extend** | 19 / 5 nuevos / 3 legacy | rim_to_tire, rim_to_spokes_hub, rim_to_rim_brake | S01, S12, S24 |
| `rim_brake` | rim_brake | 24 | **extend** | 12 / 7 nuevos / 1 legacy | rim_brake_to_frame, rim_brake_to_lever | S12 |
| `rim_strip` | rim_strip | 3 | **extend** | 6 / 3 nuevos / 2 legacy | strip_to_rim | S01 |
| `rotor` | rotor | 18 | **extend** | 12 / 3 nuevos / 2 legacy | rotor_to_hub, rotor_to_caliper | S20, S29 |
| `shifter` | shifter | 32 | **extend** | 13 / 5 nuevos / 3 legacy | shifter_to_derailleur, shifter_to_handlebar | S06, S11 |
| `spoke` | spoke | 48 | **extend** | 8 / 4 nuevos / 0 legacy | spoke_to_wheel_geometry | S24 |
| `tire` | tire | 113 | **extend** | 12 / 5 nuevos / 2 legacy | tire_to_rim, tire_to_tube | S01 |
| `tube` | tube | 137 | **extend** | 14 / 4 nuevos / 6 legacy | tube_to_tire_and_rim, tube_valve_to_rim_depth | S01, S22 |
| `tubeless_consumable` | tubeless_consumable | 3 | **extend** | 6 / 4 nuevos / 0 legacy | sealant_none | S22 |
| `tubeless_valve` | tubeless_valve | 8 | **extend** | 8 / 5 nuevos / 1 legacy | valve_to_rim | S22 |

### 3.1 Decisiones verificadas contra fuente (las que cambian el vocabulario)

1. **Tamaño de rueda.** `wheel_size` pasa a legado visible en `tire`, `tube`,
   `rim`, `rim_strip`; la compatibilidad se decide por
   `bead_seat_diameter_mm` (S01). Un nominal con varios BSD (24" → 507/520/540/547;
   26" → 559/571/584/590/597) **no** se convierte: queda desconocido hasta leer
   ETRTO. Ancho de neumático y BSD son dos comprobaciones separadas; sin rango
   OEM de la llanta, fuera de 1,45–2,0× es caution (S01).
2. **Cámaras por filas.** `tube_fit_rows` {BSD, ancho_min_mm, ancho_max_mm}
   sustituye los cuatro min/max en pulgadas y mm; una fila por BSD declarado,
   sin producto cartesiano. Las pulgadas quedan como legado visible.
3. **Cuerpo de maza.** `freehub_type` (mezclaba cuerpo, rosca, fijo y
   contrapedal) se reparte en `rear_drive_interface` (maza),
   `freehub_bodies_accepted` por filas {interfaz, espaciador} (cassette),
   `freewheel_thread_standard` (rueda libre) y `cog_thread_standard` (fijo).
   Vocabulario exacto de Shimano C-731 (S14): MICRO SPLINE sólo MTB 12v; HG
   spline L2 sólo ROAD 12v; HG spline L: ROAD 12v, ROAD 11v y MTB 11v con las
   notas de espaciador literales; HG spline M: 10/9/8/7v MTB y MTB 11v; HG
   spline S sólo tres cassettes de 7v. LINKGLIDE nunca en MICRO SPLINE (S15).
   XD entra en XDR con 1,85 mm; XDR sólo en XDR (S16).
4. **Velocidades.** `drivetrain_speeds` mezclaba número físico y capacidad. Se
   separa en `sprocket_count` (cassette/rueda libre), `shifter_indexed_positions`
   (mando), `chainring_count` (biela) y `compatible_rear_speeds` (declaración de
   cadena/plato/cambio/desviador). `chain_speeds` del piloto es la misma noción:
   se declara **alias** y no se renombra para no reabrir el contrato v6/v24.
   Fuera del conjunto declarado → caution; el ancho medido no deriva velocidades
   (S11; decisión de producto 2026-09-06).
5. **Pedalier.** `bb_shell_standard` se reparte en `bb_shell_interface` +
   `bb_shell_width_mm` + `bb_thread_hand` derivado (BSA/Suizo/Raleigh
   derecha-izquierda; Italiano/Francés derecha-derecha; S03, S09). JIS e ISO se
   declaran distintos (S03). De los 22 `option_rules` sobreviven sólo los que
   citan S03/S09 (anchos 68/73 BSA, 70 ITA, PF41 86,5–132, PF46 68–86, bolas 1/4
   en BSA, 9/11 bolas por lado); el resto se retira con la migración.
6. **Dirección.** `headset_standard` («Integrado/Semi-integrado/Tapered») se
   sustituye por `headset_upper_shis` y `headset_lower_shis` (S10, S23) más
   espiga y asiento de corona (S04). Horquilla, tee, espaciadores y araña
   consultan lo mismo.
7. **Maza y cuadro.** `hub_spacing_mm` (lista) → `hub_old_mm` entero (S05) +
   `axle_type` + `thru_axle_thread` (M12/M15 × 1,0/1,5; S28). 135 QR y 142×12 no
   son intercambiables por número.
8. **Frenos.** `brake_type` y `caliper_hydraulic` → `braking_surface` +
   `brake_actuation`; `brake_system` (marcas) pasa a legado; «Adaptor Requerido»
   deja de ser montaje y pasa a `rotor_size_recipe` (S20); `brake_pad` se divide
   en `disc_brake_pad` (forma/cálipers OEM, compuesto) y `rim_brake_pad`
   (espárrago roscado / poste liso / ruta; S12); manetas declaran tiro o fluido
   (S27). Coincidir diámetro de rotor es caution (corrección Dart del
   2026-09-06), no compatible.
9. **Plato.** BCD sin tope (58 y 145 mm existen, S02) y patrón
   simétrico/asimétrico como segundo campo; dientes pasan de texto a entero.
10. **Cambio trasero.** Capacidad = (plato mayor − menor) + (piñón mayor −
    menor) (S17); mando ↔ cambio sólo por lista OEM de modelos; velocidades
    iguales = caution.
11. **Pedales y pedalines.** Rosca 9/16"×20 vs 1/2"×20 (S13, S19); el pedalín
    va al eje de maza y tiene plantilla propia.
12. **Tija y sillín.** Diámetro exacto en décimas pares (S18); suplemento como
    par exterior/interior; sillín ↔ tija por riel.
13. **Cables.** Funda sin compresión sólo cambio; espiral sólo freno; trenzada
    ambas (S21). Fluidos DOT/mineral nunca se cruzan (S27).

### 3.2 Campos que quedan en rol legacy, por plantilla

| Plantilla | Campos legacy (visibles, sin uso en reglas) |
|---|---|
| `bottom_bracket` | `bb_shell_standard`, `bb_cup_thread_pair` |
| `bottom_bracket_cup` | `bb_shell_standard`, `bb_cup_thread_pair` |
| `brake_caliper` | `brake_type`, `caliper_hydraulic`, `rotor_diameter_mm`, `brake_system` |
| `brake_lever` | `brake_type`, `caliper_hydraulic`, `brake_system` |
| `brake_pad` | `brake_type`, `brake_system` |
| `cassette` | `drivetrain_speeds`, `cassette_cog_sequence`, `freehub_type` |
| `cassette_spacer` | `freehub_type` |
| `chain` | `drivetrain_primary_ecosystem`, `chain_profile_family` |
| `chain_guide` | `chainring_teeth` |
| `chain_link` | `drivetrain_primary_ecosystem`, `chain_profile_family`, `drivetrain_mode` |
| `chainring` | `chainring_teeth`, `chainring_bolt_count`, `drivetrain_speeds`, `chain_profile_family` |
| `hydraulic_disc_brake` | `rotor_diameter_mm`, `brake_system` |
| `mechanical_disc_brake` | `rotor_diameter_mm`, `brake_system` |
| `crankset` | `front_chainring_count`, `chainring_teeth`, `bottom_bracket_family`, `drivetrain_speeds`, `chain_profile_family` |
| `derailleur_hanger` | `compatible_frame_hint`, `rear_derailleur_mount_type` |
| `drivetrain_kit` | `kit_contents`, `front_chainring_count`, `chainring_teeth`, `bottom_bracket_family`, `drivetrain_primary_ecosystem`, `chain_profile_family` |
| `fixed_cog` | `freehub_type`, `drivetrain_speeds` |
| `freewheel` | `drivetrain_speeds`, `freehub_type`, `cassette_cog_sequence` |
| `front_derailleur` | `front_chainring_count`, `drivetrain_speeds`, `front_derailleur_pull_direction`, `drivetrain_primary_ecosystem` |
| `headset` | `headset_standard`, `steerer_type` |
| `hub` | `hub_spacing_mm`, `spoke_holes`, `freehub_type` |
| `rear_derailleur` | `drivetrain_speeds`, `drivetrain_primary_ecosystem` |
| `rim` | `wheel_size`, `spoke_holes`, `valve_type` |
| `rim_brake` | `brake_system` |
| `rim_strip` | `wheel_size`, `valve_type` |
| `rotor` | `rotor_diameter_mm`, `brake_system` |
| `shifter` | `drivetrain_speeds`, `front_chainring_count`, `drivetrain_primary_ecosystem` |
| `tire` | `wheel_size`, `tire_width_in` |
| `tube` | `wheel_size`, `tube_width_min_in`, `tube_width_max_in`, `tube_width_min_mm`, `tube_width_max_mm`, `valve_length_mm` |
| `tubeless_valve` | `valve_length_mm` |

Definiciones sin plantilla en la revisión semántica: `bb_thread_standard`
(sin uso: retirar en la migración de vocabulario) y las seis de taller
(`component_condition`, `contamination_status`, `diagnosis_notes`,
`noise_status`, `overall_status`, `tubeless_status`, `wear_percent`), que se
quedan en su dominio de taller y no entran en fichas de producto.

## 4. Plantillas nuevas (68)

Agrupación: una plantilla por objeto con interfaz propia; las piezas pequeñas
se agrupan sólo cuando comparten la misma interfaz (rosca de eje, diámetro de
piola/funda, tipo de válvula, diámetro de espiga). No se agrupa por parecido
comercial: el pedalín no es pedal, el extensor no es patilla, el fuelle no es
pastilla, el obús no es válvula, el gyro no es rotor.

| Plantilla | Clases que atiende | Productos | Campos | Interfaces | Fuentes |
|---|---|---:|---:|---|---|
| `pedal` | pedal | 34 | 11 | pedal_to_crank, pedal_to_shoe_cleat | S13, S19 |
| `pedal_peg` | pedal_peg | 1 | 6 | peg_to_hub_axle | S05 |
| `grip` | grip | 28 | 9 | grip_to_handlebar | S06 |
| `handlebar_covering` | bar_tape, handlebar_padding_set | 8 | 10 | covering_to_bar | S06 |
| `handlebar` | handlebar | 14 | 10 | bar_to_stem, bar_to_controls | S06 |
| `stem` | stem, stem_adapter | 18 | 10 | stem_to_steerer, stem_to_handlebar | S04, S06 |
| `seatpost` | seatpost, seatpost_shim | 16 | 12 | post_to_seat_tube, post_to_saddle_rails | S18 |
| `seat_clamp` | seat_clamp, seat_clamp_small_part | 12 | 6 | clamp_to_seat_tube | S18 |
| `saddle` | saddle | 22 | 9 | saddle_to_post | S18 |
| `saddle_cover` | saddle_cover | 4 | 6 | cover_to_saddle | S18 |
| `fork` | fork | 11 | 19 | fork_to_headset_and_frame, fork_to_front_wheel, fork_to_brake, fork_to_tire | S01, S04, S05, S20, S23, S28 |
| `rear_shock` | rear_shock | 1 | 7 | shock_to_frame | S25 |
| `spacer` | bottom_bracket_spacer, headset_spacer | 8 | 8 | spacer_to_shaft | S04 |
| `headset_small_part` | headset_preload | 3 | 7 | preload_to_steerer | S04 |
| `hub_axle` | hub_axle | 22 | 7 | axle_to_hub_shell | S05 |
| `hub_small_part` | hub_axle_adapter, hub_cone, hub_locknut | 8 | 8 | part_to_axle | S05 |
| `wheel_retention` | wheel_retention, wheel_retention_small_part | 15 | 11 | retention_to_hub_and_frame | S05, S28 |
| `spoke_nipple` | spoke_nipple | 3 | 7 | nipple_to_spoke_and_rim | S24 |
| `tubeless_tape` | tubeless_tape | 10 | 5 | tape_to_rim | S22 |
| `tubeless_repair` | tubeless_repair | 1 | 5 | no_compatibility | S22 |
| `valve_small_part` | inflation_adapter, tubeless_valve_small_part, valve_cap, valve_core | 7 | 7 | part_to_valve | S22 |
| `tire_liner` | tire_liner | 1 | 5 | liner_to_tire | S01 |
| `tube_repair` | tube_repair | 10 | 7 | no_compatibility | S22 |
| `control_cable` | control_cable | 18 | 7 | cable_to_lever | S21 |
| `control_housing` | control_housing | 13 | 6 | housing_to_system | S21 |
| `control_small_part` | brake_cable_boot, brake_noodle, cable_adjuster, control_cable_guide, control_terminal | 19 | 9 | part_to_cable_or_housing | S21 |
| `hydraulic_fitting` | hydraulic_fitting | 10 | 6 | fitting_to_hose_and_caliper | S27 |
| `hydraulic_hose` | hydraulic_hose | 2 | 8 | hose_to_system | S27 |
| `brake_fluid` | brake_fluid | 3 | 4 | fluid_to_brake | S27 |
| `brake_mount_adapter` | brake_adapter | 4 | 7 | adapter_recipe | S20 |
| `rotor_mount_adapter` | rotor_mount_adapter | 1 | 3 | adapter_hub_to_rotor | S20 |
| `brake_small_part` | brake_pad_retainer, brake_return_spring | 2 | 6 | part_to_brake_model | S12 |
| `hub_brake` | enclosed_hub_brake | 1 | 6 | hub_brake_to_hub | S12 |
| `bmx_cable_detangler` | bmx_cable_detangler | 1 | 4 | detangler_to_headset | S04, S29 |
| `derailleur_hanger_extender` | derailleur_hanger_extender, derailleur_mount_adapter | 3 | 5 | extender_to_hanger_and_rd | S17 |
| `cassette_lockring` | cassette_lockring | 1 | 4 | lockring_to_body | S14, S16 |
| `chainring_guard` | chainring_guard | 1 | 6 | guard_to_crank | S02 |
| `fastener` | fastener | 22 | 10 | fastener_to_thread | S13 |
| `workshop_tool` | applicator, tool_spare_part, workshop_cleaning_tool, workshop_ppe, workshop_tool | 45 | 9 | tool_to_standard | S11, S30 |
| `workshop_chemical` | workshop_chemical, workshop_lubricant | 29 | 8 | no_compatibility | S27 |
| `lock` | lock | 31 | 12 | no_compatibility | S06 |
| `light` | light | 20 | 14 | light_to_bar_or_post | S06 |
| `audible_signal` | audible_signal | 7 | 7 | signal_to_bar | S06 |
| `cycle_computer` | cycle_computer | 1 | 6 | no_compatibility | S06 |
| `consumer_electronics` | consumer_electronics | 4 | 11 | no_compatibility | S06 |
| `accessory_mount` | accessory_mount, bike_storage_mount | 9 | 10 | mount_to_bar_and_device | S06 |
| `bottle_cage` | bottle_cage | 11 | 7 | cage_to_frame | S06 |
| `bottle` | bottle | 7 | 7 | bottle_to_cage | S06 |
| `rack_basket` | cargo_strap, rack_basket | 6 | 9 | carrier_to_bike | S06 |
| `fender` | fender | 4 | 9 | fender_to_bike | S01 |
| `kickstand` | kickstand | 2 | 8 | kickstand_to_frame | S06 |
| `bike_bag` | bike_bag | 5 | 6 | no_compatibility | S06 |
| `rider_bag` | rider_bag, rider_bag_cover | 4 | 8 | cover_to_bag | S06 |
| `training_wheel` | training_wheel | 3 | 6 | training_wheel_to_bike | S05 |
| `bike_protection` | bicycle_cover, frame_protection | 4 | 7 | no_compatibility | S06 |
| `reflector` | reflective_tape | 1 | 4 | no_compatibility | S06 |
| `souvenir` | souvenir | 7 | 4 | no_compatibility | S06 |
| `rider_glove` | rider_glove | 33 | 8 | no_compatibility | S06 |
| `helmet` | helmet | 13 | 11 | no_compatibility | S06 |
| `eyewear` | eyewear | 3 | 5 | no_compatibility | S06 |
| `rider_apparel` | rider_apparel | 4 | 7 | no_compatibility | S06 |
| `rider_protection` | rider_protection | 1 | 6 | no_compatibility | S06 |
| `food_beverage` | food_beverage | 19 | 7 | no_compatibility | S06 |
| `pump` | pump | 15 | 9 | pump_to_valve | S22 |
| `bicycle` | — | 0 | 35 | bicycle_profile_as_bike_subject | S01, S03, S04, S05, S09, S18, S20, S23, S25 |
| `frame` | — | 0 | 25 | frame_profile | S03, S04, S05, S09, S18, S20, S23, S25 |
| `wheel` | — | 0 | 14 | wheel_to_frame_or_fork, wheel_to_tire, wheel_to_cassette, wheel_to_rotor | S01, S05, S14, S16, S20, S28 |
| `brake_shift_combined_control` | combined_control | 1 | 7 | combined_to_derailleur, combined_to_brake | S11, S12 |

## 5. Clases candidatas y registros especiales

### 5.1 Las 26 clases que reutilizan una plantilla existente (75 productos)

| Clase | Productos | Plantilla | Motivo |
|---|---:|---|---|
| spoke | 10 | `spoke` | Rayos sin categoría: la plantilla existente (extendida) los recibe. |
| bearing | 5 | `bearing` | Bolsas de bolas sueltas: `bearing` extendido con construcción «Bolas sueltas». |
| derailleur_hanger | 5 | `derailleur_hanger` | Postizas sin categoría (Giant, Norco…): plantilla existente; exige hanger_model_code o cuadro. |
| drivetrain_kit | 5 | `drivetrain_kit` | Groupsets Shimano CUES/SLX y set ProWheel: kit técnico con kit_members por miembro. |
| crankset | 4 | `crankset` | Bielas sin categoría → crankset extendido. |
| rear_derailleur | 4 | `rear_derailleur` | Cambios sin categoría → rear_derailleur extendido. |
| rim_brake | 4 | `rim_brake` | Frenos U-brake / tiro lateral / V-brake completos → rim_brake extendido (juegos = kit_members). |
| shifter | 4 | `shifter` | Mandos sin categoría → shifter extendido. |
| hub | 4 | `hub` | Mazas sin categoría → hub extendido. |
| tire | 4 | `tire` | Neumáticos sin categoría → tire extendido (BSD). |
| chain | 3 | `chain` | KMC X9/X10/X11 sin categoría → chain (piloto). |
| front_derailleur | 3 | `front_derailleur` | Desviadores sin categoría → front_derailleur extendido. |
| brake_lever | 3 | `brake_lever` | Manetas sin categoría → brake_lever extendido (tiro). |
| rim | 3 | `rim` | Llantas sin categoría → rim extendido (BSD, ERD). |
| headset_bearing | 2 | `bearing` | Rodamiento de dirección = `bearing` extendido con aplicación Dirección y ángulo/tamaño (1" / 1 1/8"). |
| bottom_bracket_bearing | 2 | `bottom_bracket_bearing` | Rodamientos enjaulados de motor → plantilla existente con construcción «Canastillo». |
| rim_strip | 1 | `rim_strip` | Cubre-cámara → rim_strip extendido (BSD). |
| crank_arm | 1 | `crank_arm` | Biela izquierda → crank_arm. |
| cassette | 1 | `cassette` | CS-HG200-7 → cassette extendido (HG spline M). |
| chainring | 1 | `chainring` | Catalina BMX 39T → chainring (montaje rosca BMX o BCD según envase). |
| tube | 1 | `tube` | Chaoyang 700x33/37c con 7 hechos → tube; los hechos se conservan. |
| headset | 1 | `headset` | Juego de dirección 10Ten semi-integrado → headset con SHIS superior/inferior. |
| complete_brake | 1 | `mechanical_disc_brake` | Kit Zoom DB-280 mecánico → mechanical_disc_brake con kit_members (miembros por confirmar en envase). |
| freewheel | 1 | `freewheel` | MF-TZ500-7 → freewheel extendido (rosca ISO, 7 coronas). |
| solid_tire | 1 | `tire` | Rueda sólida scooter 8.5×2 → tire con bead «Sólido», uso Scooter, BSD 134 (S26 comunitaria: no aprueba). |
| bottom_bracket | 1 | `bottom_bracket` | SM-BB94-41A press-fit → bottom_bracket extendido (PF41). |

Las 82 clases restantes (`action = create`, 634 productos) están en el JSON con su
destino y motivo; la tabla de §4 las agrupa por plantilla.

### 5.2 Reclasificaciones observadas entre los 863 con ficha

| Clase observada | Productos | Destino | Acción | Motivo |
|---|---:|---|---|---|
| derailleur_hanger_extender | 2 | `derailleur_hanger_extender` | create | eb82020b y ff0c6d4b (imágenes): extensores, no patillas; salen de derailleur_hanger. |
| enclosed_hub_brake | 1 | `hub_brake` | identity_review | 07e4b2d0 «Freno Balata 90 mm»: freno cerrado de maza (imagen); banda/tambor por confirmar; sale de brake_caliper. |
| brake_return_spring | 1 | `brake_small_part` | create | 1d3f2d8b resorte de herradura (imagen): sale de rim_brake. |
| crankset_with_bottom_bracket | 1 | `crankset` | reuse | 35e9adc9 bielas + cubetas Mid: crankset con kit_members; sale de drivetrain_kit. |
| bmx_cable_detangler | 1 | `bmx_cable_detangler` | create | 64e9e200 rotor freestyle = gyro (S29, imagen): sale de rotor. |
| valve_core | 1 | `valve_small_part` | create | 7da9c57b obús Presta (imagen): sale de tubeless_valve; no hereda largo. |
| disc_brake_pad | 1 | `brake_pad` | reuse | 8163d705 Fantom: pastilla de disco (imagen) → brake_pad con braking_surface = Disco (plantilla hija disc_brake_pad). |
| bottom_bracket_cup_kit | 1 | `bottom_bracket_cup` | identity_review | a514aeca cubetas americanas selladas eje 19 mm: kit de copas con rodamientos (imagen); roscado vs pressfit por confirmar. |
| disc_brake_component_kit | 1 | `mechanical_disc_brake` | reuse | b7fb996c Logan: 2 cálipers + 2 rotores sin manetas → kit parcial con levers_included = false; sale de brake_caliper. |
| fixed_cog | 1 | `fixed_cog` | reuse | 62a41771 PIÑON 15T FIJO (imagen): sale de freewheel. |
| handlebar_padding_set | 1 | `handlebar_covering` | create | 2ea1138a cuatro fundas tubulares (imagen): recubrimiento, no puños. |
| bicycle_cover | 1 | `bike_protection` | create | 6be54ef6 funda para bicicleta (imagen); marca VISION vs BEST pendiente. |
| brake_cable_boot | 1 | `control_small_part` | create | 49b90689 gomita V-brake = fuelle (imagen). |
| hub_axle | 2 | `hub_axle` | create | 5908b918 y ce2e2810 «EJE BLOQUEO»: ejes con conos (imágenes), no agujas. |
| workshop_cleaning_tool | 1 | `workshop_tool` | create | b887f8e9 limpiador triple plato: objeto sólido (imagen), no químico. |
| workshop_lubricant | 1 | `workshop_chemical` | identity_review | ccdb85f9 ACEITE NACIONAL: lubricante multipropósito (imagen); jamás fluido de frenos. |

### 5.3 Los 33 registros sin clase, uno a uno

| Registro | Acción | Destino | Nota |
|---|---|---|---|
| ALIEXPRESS | identity_review | — | Rótulo de proveedor, no producto: revisar documentos (compras/ventas) antes de decidir si es un producto real o un registro de conveniencia. |
| Andes | identity_review | — | Rótulo de marca. |
| BETTABIKES | identity_review | — | Rótulo de proveedor. |
| MKR | identity_review | — | Rótulo de marca. |
| Dr. Bike | identity_review | — | Rótulo. |
| Pack | identity_review | — | Rótulo genérico. |
| Test | business_review | — | Registro de prueba: decisión comercial (inactivar), no ficha. |
| Costo de bicicleta | business_review | — | Concepto contable. |
| Gasto por transporte | business_review | — | Concepto contable. |
| Nota de Crédito Por Cámara Chaoyang 700x25/32C F/V 60MM | business_review | — | Documento, no pieza; no reclasificar por la pieza que nombra. |
| Centrado de Rueda BettaBikes | business_review | service_flow | Intervención: flujo de servicios. |
| Diagnóstico | business_review | service_flow | Servicio. |
| Restauración de Freno Hidráulico | business_review | service_flow | Servicio. |
| Instalación rayo trasero disco + centrado zona afectada | business_review | service_flow | Servicio con material. |
| Descontaminación Disco de Freno | business_review | service_flow | Servicio. |
| Retiro de Óxido | business_review | service_flow | Servicio. |
| Cámara nueva + servicio de cambio | business_review | service_flow | Paquete servicio + cámara: separar en el flujo comercial antes de cualquier ficha. |
| Cubetas Motor Americano BMX Bettabikes | identity_review | bottom_bracket_cup | Copas o juego completo: inspeccionar contenido. |
| Eje de Motor Set Up Bikes | identity_review | bottom_bracket_axle | Eje suelto o conjunto: inspeccionar. |
| Juego de Tuercas Laterales Motor + Rodamientos | identity_review | bottom_bracket_cup | Kit de pedalier americano (tuercas + rodamientos): kit_members tras inspección. |
| Piñon 1v Bettabikes | identity_review | freewheel \| fixed_cog | Libre vs fijo: envase o foto. |
| Piñon 1v Monsoon Bettabikes | identity_review | freewheel \| fixed_cog | Idem. |
| Rotor Freno Trasero BMX PadroBikes | identity_review | bmx_cable_detangler \| rotor | Gyro vs disco: sin imagen no se decide. |
| Set Cubre Manubrio 125mm/220mm Black | create | handlebar_covering | Imagen 2ea1138a: fundas tubulares. |
| FUNDA PROTECTORA BEST COLOR GRIS | create | bike_protection | Imagen 6be54ef6: funda de bicicleta; marca pendiente. |
| Freno Hidráulico Delantero Tanke 4 Pistones Morado Metálico | identity_review | hydraulic_disc_brake | Confirmar si incluye maneta/manguera/cáliper: kit_members. |
| GOMITA PARA FRENO V-BRAKE COMPATIBLE / GENERICO | create | control_small_part | Imagen 49b90689: fuelle. |
| EJE BLOQUEO SOLO DELANTERO (min.10pcs) ALTERNATIVO 2022 ECON | create | hub_axle | Imagen 5908b918: eje con conos. |
| EJE BLOQUEO TRASERO 7/8 9V. COMPATIBLE / GENERICO | create | hub_axle | Imagen ce2e2810: eje con conos. |
| ACEITE NACIONAL | identity_review | workshop_chemical | Imagen ccdb85f9: lubricante multipropósito; nunca brake_fluid. |
| Aceite Mineral Chepark | identity_review | workshop_chemical | Sin etiqueta OEM de freno → workshop_chemical; si la etiqueta dice freno hidráulico → brake_fluid. |
| LIMPIADOR TRIPLE PLATO PP-01 | create | workshop_tool | Imagen b887f8e9: herramienta de limpieza. |
| Limpiador Cadena y Piñón Chepark | identity_review | workshop_chemical \| workshop_tool | Químico o herramienta: foto/envase. |

### 5.4 Qué significa cada acción

- `reuse`: la plantilla existente (con su extensión de §3) recibe el producto
  por asignación explícita (`assign_product_spec_template_v1`).
- `create`: requiere la plantilla nueva de §4 antes de asignar.
- `identity_review`: falta envase/foto para decidir el objeto; no se asigna.
- `business_review`: no es un producto físico (documento, concepto contable,
  servicio); se resuelve en el flujo comercial/servicios, no con ficha.

## 6. Reglas transversales y fuentes

### 6.1 Reglas que cruzan familias

| Id | Regla | Familias | Fuentes |
|---|---|---|---|
| R01_bsd_exact | Neumático, cámara, llanta, cinta y protector se cruzan por bead_seat_diameter_mm entero; el nominal comercial nunca decide. | tire, tube, rim, rim_strip, tubeless_tape, tire_liner, fork | S01 |
| R02_width_ratio_is_caution | Sin rango OEM de la llanta, un ancho fuera de 1,45–2,0× el interior es caution, no incompatible; con rango OEM, fuera de rango es incompatible. BSD y ancho son dos comprobaciones separadas, nunca una lista cruzada. | tire, rim | S01 |
| R03_freehub_rows | Cassette ↔ maza se resuelve por filas {interfaz, espaciador}; MICRO SPLINE sólo MTB 12v; LINKGLIDE nunca en MICRO SPLINE; XD en XDR sólo con 1,85 mm; XDR sólo en XDR. | cassette, hub, cassette_spacer, cassette_lockring | S14, S15, S16, S08 |
| R04_chain_speeds_declared | Las velocidades de cadena/plato/cambio/mando son declaraciones OEM (set_membership). Fuera del conjunto → caution. Ancho medido nunca deriva velocidades ni certifica (decisión de producto 2026-09-06). | chain, chain_link, chainring, crankset, rear_derailleur, front_derailleur, shifter, cassette, freewheel | S11 |
| R05_shifter_derailleur_by_model | Mando ↔ cambio sólo por lista OEM de modelos (reference_model_list). Marca, ecosistema o velocidades iguales no aprueban; coincidir velocidades es caution. | shifter, rear_derailleur, front_derailleur, brake_shift_combined_control | S11 |
| R06_rd_capacity | Capacidad = (plato mayor − menor) + (piñón mayor − menor); se compara con la capacidad declarada del cambio; piñón máximo y mínimo son límites aparte. | rear_derailleur | S17 |
| R07_bb_interface_plus_width | Pedalier ↔ cuadro: interfaz de caja + ancho, dos campos; sentido de rosca derivado del estándar. Biela ↔ pedalier: interfaz de eje por conjunto aceptado; JIS ≠ ISO. | bottom_bracket, bottom_bracket_cup, bottom_bracket_axle, crankset, crank_arm | S03, S09 |
| R08_bcd_no_caps | BCD sin mínimo ni máximo universal (58 y 145 mm existen); patrón simétrico/asimétrico es un segundo campo. | chainring, chainring_guard, crankset | S02 |
| R09_shis_per_end | Dirección: un código SHIS por extremo; horquilla aporta espiga y asiento de corona; nunca se colapsa a «integrado/tapered». | headset, fork, stem, spacer, headset_small_part, bmx_cable_detangler | S04, S10, S23 |
| R10_hub_old_plus_axle | Maza ↔ cuadro/horquilla: OLD numérico + tipo de eje + rosca de eje pasante (M12/M15 × 1,0/1,5). 135 QR y 142×12 no son intercambiables por número. | hub, fork, wheel_retention, hub_axle, training_wheel | S05, S28 |
| R11_disc_recipe | Freno de disco: montaje del cáliper + montaje del cuadro + diámetro de rotor + posición → receta de adaptador. «Adaptador requerido» no es un montaje. Diámetro igual de rotor es caution, no compatible. | brake_caliper, hydraulic_disc_brake, mechanical_disc_brake, brake_mount_adapter, rotor, fork, hub, rotor_mount_adapter | S20 |
| R12_pad_by_shape | Pastilla de disco ↔ cáliper por código de forma o lista OEM de modelos; zapata de llanta ↔ freno por tipo de espárrago (roscado / liso / ruta). Nunca por marca. | brake_pad, brake_caliper, rim_brake, brake_small_part | S12, S20 |
| R13_lever_pull | Maneta mecánica ↔ freno por tiro (largo V-brake / corto ruta-cantilever); hidráulica ↔ cáliper por fluido y sistema de manguera. Cabeza de piola (barril/pera) por maneta. | brake_lever, rim_brake, brake_caliper, brake_shift_combined_control, control_cable | S12, S21, S27 |
| R14_fluid_never_mixed | DOT y mineral nunca se cruzan; «mineral» de otra marca sin declaración OEM es caution. | brake_fluid, brake_caliper, brake_lever, hydraulic_disc_brake, hydraulic_fitting, hydraulic_hose | S27 |
| R15_housing_purpose | Funda sin compresión sólo para cambio; funda espiral sólo para freno; trenzada ambas. Piola de cambio jamás en freno. | control_housing, control_cable, control_small_part | S21 |
| R16_pedal_thread | Pedal ↔ biela por rosca 9/16"×20 o 1/2"×20; el izquierdo lleva rosca izquierda; pedalín no es pedal (eje de maza). | pedal, crank_arm, crankset, pedal_peg | S13, S19 |
| R17_seatpost_exact | Tija ↔ tubo de asiento por diámetro exacto (décimas pares); suplemento por par exterior/interior; collarín por exterior del tubo; sillín ↔ tija por riel. | seatpost, seat_clamp, saddle, saddle_cover | S18 |
| R18_bar_stem_grip | Manubrio ↔ tee por abrazadera (25,4 / 26,0 / 31,8 / 22,2; 25,8 admite dos); puños/manetas/mandos ↔ manubrio por zona de puño (22,2 / 23,8). | handlebar, stem, grip, brake_lever, shifter, light, audible_signal, accessory_mount | S06 |
| R19_spoke_geometry | Largo de rayo sólo por ERD + geometría de maza + cruces; rosca 14G/15G debe coincidir con el niple; nunca «rayo para aro 26». | spoke, spoke_nipple, rim, hub | S24 |
| R20_shock_e2e_stroke | Amortiguador ↔ cuadro por eye-to-eye × carrera × tipo de ojal; el hardware lo define el cuadro. | rear_shock | S25 |
| R21_kits_are_members | Un kit técnico (groupset, freno completo, bielas+cubetas, juego de frenos, kit de parches) se describe por kit_members; NO implica is_set, hijos de inventario ni ratios de precio. Los 6 sets comerciales frontRear del snapshot siguen siendo sets; su composición técnica se declara aparte. | drivetrain_kit, hydraulic_disc_brake, mechanical_disc_brake, crankset, rim_brake, shifter, brake_lever, hydraulic_fitting, hydraulic_hose, tube_repair, tubeless_repair, light, fender, training_wheel | S20 |
| R22_no_template_no_technical_claim | Un producto sin ficha no satisface criterios técnicos (decisión de producto 2026-09-06); el nombre sigue siendo evidencia para clasificar candidatos, no contrato técnico. | * | S11 |

### 6.2 Fuentes leídas (fecha de consulta)

| Id | Título | Editor | Consultada | URL |
|---|---|---|---|---|
| S01 | Sheldon Brown — Tire Sizing Systems | sheldonbrown.com (mantenido por John Allen) | 2026-09-06 | https://www.sheldonbrown.com/tire-sizing.html |
| S02 | Sheldon Brown — Crank/Chainring BCD Crib Sheet | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/cribsheet-bcd.html |
| S03 | Sheldon Brown — Bottom Bracket Size Database (roscas y conos) | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/bbsize.html |
| S04 | Sheldon Brown — Headset Size Crib Sheet | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/cribsheet-headsets.html |
| S05 | Sheldon Brown — Frame Spacing (Over-Locknut Dimension) | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/frame-spacing.html |
| S06 | Sheldon Brown — Handlebar and Stem Size Crib Sheet | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/cribsheet-handlebars.html |
| S07 | Sheldon Brown — Chains | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/chains.html |
| S08 | Sheldon Brown — Shimano Cassettes & Freehubs | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/k7.html |
| S09 | Park Tool — Bottom Bracket Standards and Terminology (rev. 2019-09-18) | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards-and-terminology |
| S10 | Park Tool — Headset Standards (S.H.I.S.) | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/headset-standards |
| S11 | Park Tool — Chain Compatibility (2017-02-17) | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/chain-compatibility |
| S12 | Park Tool — Brake Pad Replacement: Rim Brakes (2017-01-24) | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/brake-pad-replacement-rim-brakes |
| S13 | Park Tool — Pedal Installation and Removal (2015-08-21) | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/pedal-installation-and-removal |
| S14 | Shimano — FREEHUB and cassette spline compatibility C-731 | productinfo.shimano.com | 2026-09-06 | https://productinfo.shimano.com/en/compatibility/C-731 |
| S15 | Shimano — LINKGLIDE cassette and FREEHUB compatibility C-649 | productinfo.shimano.com | 2026-09-06 | https://productinfo.shimano.com/en/compatibility/C-649 |
| S16 | SRAM — XD and XDR Driver Body Explained | sram.com | 2026-09-06 | https://www.sram.com/en/service/articles/sram-xd-and-xdr-driver-body-explained |
| S17 | Sheldon Brown — Glossary Ca–Ce (Capacity, Cassette, Cantilever, Cartridge bearing) | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/gloss_ca-g.html |
| S18 | Sheldon Brown — Seatpost Size Database | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/seatpost-sizes.html |
| S19 | Sheldon Brown — Pedals; Thread-on Freewheels | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/pedals.html |
| S20 | Park Tool — Mechanical / Hydraulic Disc Brake Alignment; Rotor Removal & Installation | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/mechanical-disc-brake-alignment |
| S21 | Park Tool — How to Size and Install Shift Cable Housing; Brake Housing & Cable Installation | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/cutting-and-sizing-cable-housing |
| S22 | Park Tool — Tubeless Tire Conversion; Tubeless Tire Compatibility | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/tubeless-tire-conversion |
| S23 | Cane Creek — The Ultimate Guide to Identifying and Choosing a Bicycle Headset (S.H.I.S., 2010) | canecreek.com | 2026-09-06 | https://www.canecreek.com/pages/the-ultimate-guide-to-identifying-and-choosing-a-bicycle-headset |
| S24 | Sheldon Brown — Measurements for Spoke-Length Calculations; Wheelbuilding | sheldonbrown.com | 2026-09-06 | https://www.sheldonbrown.com/spoke-length.html |
| S25 | SRAM/RockShox — Rear Shock Fitment Guide | sram.com | 2026-09-06 | https://www.sram.com/en/service/articles/RockShox-fitment-article |
| S26 | Open Consumables — Xiaomi M365 (fuente comunitaria, no OEM) | openconsumables.org | 2026-09-06 | https://openconsumables.org/categories/openscoot/units/xiaomi-m365/ |
| S27 | Park Tool — Hydraulic Brake Bleed Kits BKD-1.2 (DOT) / BKM-1.2 (Mineral) — instrucciones | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-dot-bkd-1-2 |
| S28 | Park Tool — Thru Axle Taps TAP-12.1/12.2/15.1/15.2 | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/product/thru-axle-tap-set-tap-ta-set |
| S29 | Sheldon Brown — Glossary R (Rotor = detangler/gyro BMX) | sheldonbrown.com | 2026-09-06 (sesión anterior de esta misma fecha) | https://www.sheldonbrown.com/gloss_r.html |
| S30 | Park Tool — Determining Cassette / Freewheel Type; Cassette Removal and Installation | parktool.com | 2026-09-06 | https://www.parktool.com/en-us/blog/repair-help/cassette-and-freewheel-removal-and-installation |

Cada fuente lleva en el JSON los hechos concretos extraídos. Las páginas que
devolvieron 404 hoy (`sheldonbrown.com/cribsheet-threading.html`,
`cribsheet-seatposts.html`, `parktool.com/.../disc-brake-pad-removal-and-installation`,
`.../disc-brake-caliper-mounting-systems`) no se citan; se sustituyeron por las
páginas equivalentes listadas.

## 7. Contradicciones encontradas y cómo se resolvieron

1. **C-731 leída dos veces.** La primera lectura decía «HG spline L: ruta 11v
   con espaciador 1,85 mm y MTB 12v»; la segunda, con las filas literales, dice
   ROAD 12v / ROAD 11v / MTB 11v y notas *1–*3. Se corrigió el vocabulario
   `rear_drive_interface` y se registró la corrección en S14. Un espaciador mal
   atribuido habría aprobado cassettes que no entran.
2. **`chainring_bcd_mm` 64–144 vs S02.** El snapshot conserva el rango; la
   migración 150000 ya lo cambió a «positivo». El blueprint fija «sin tope» con
   la lista documentada (50,4–157).
3. **`brake_system` contiene marcas.** Se conserva como legado con rótulo
   «Marca del freno (legado)»; la identidad real es `brand`/`model`.
4. **`rotor_diameter_mm` con «203/180».** Era receta delantero/trasero
   disfrazada de medida: se separa en entero (rotor) y filas de receta (cáliper).
5. **`rear_derailleur_mount_type` contenía «Extensor de pata».** Un extensor es
   otro participante: plantilla `derailleur_hanger_extender`.
6. **Dos claves para velocidades** (`chain_speeds` y `drivetrain_speeds`). Se
   decide alias, no renombre, para no reabrir el piloto verificado.
7. **`valve_type` en llanta.** Una llanta no tiene válvula: tiene agujero. Se
   crea `valve_hole` y `valve_type` queda legado sólo en `rim`, no en `tube`.
8. **Sets comerciales vs kits técnicos.** Seis productos `is_set` (manillas en
   par, herraduras del/tras) y los kits OEM (groupset, freno completo, bielas +
   cubetas) son conceptos distintos; el blueprint no propone convertir unos en
   otros.
9. **Cadena con velocidades declaradas fuera de la bici.** La primera revisión
   sugería mantener `incompatible` cuando la cadena es más ancha que la
   transmisión; el dueño decidió que sin ancho/perfil/modelo y fuente exacta no
   se emite prueba física universal. El blueprint sigue esa decisión: caution.
10. **«Certificado» en el nombre de un casco** no es certificación: sólo lo
    impreso en la etiqueta entra en `certification_claim`.
11. **Aceite mineral ≠ fluido de frenos.** Dos productos «aceite mineral» sin
    etiqueta OEM de freno van a `workshop_chemical`; `brake_fluid` exige la
    etiqueta (S27).

## 8. Qué queda explícitamente sin aprobar

- Ninguna plantilla queda aprobada para llenar: este blueprint define campos e interfaces; la aprobación mecánica exige fixtures positivo/negativo/desconocido por interfaz y read-back.
- Valores marcados `unverified` en SHARED_VOCABULARIES (35 mm de abrazadera, 13G, M30×1 BMX, contratuerca 1.29"×24, agujero de válvula 6,5/8,5 mm, ISO 44 mm de rotor, BSD 134 scooter, roscas 26 tpi de eje) no alimentan reglas bloqueantes hasta leer su fuente.
- Los 22 option_rules de pedalier no citados por S03/S09 se retiran con la migración de vocabulario; no se conservan «porque tienen pruebas».
- Ningún cruce mando↔cambio, pastilla↔cáliper, patilla↔cuadro, conector↔cadena ni pedalier↔biela se aprueba sin lista OEM por modelo: hoy 0 de esas listas existe.
- Las 33 filas sin clase se resuelven una a una (NONE_RECORDS); ninguna se declara administrativa en bloque.
- Las clases con identity_review (enclosed_hub_brake, bottom_bracket_cup_kit, workshop_lubricant, y las 14 filas None ambiguas) no reciben plantilla hasta ver envase/foto.
- Fuentes: S26 (Xiaomi M365) es comunitaria; S30 (Park cassette/freewheel) sólo se leyó como índice; la página de pastillas de disco de Park devolvió 404 hoy y no se cita.

## 9. Orden de implementación sugerido para Codex (sin tocar datos hasta el read-back)

1. Migración de vocabulario y definiciones nuevas (§3.1, §3.2): crear las
   definiciones nuevas, marcar roles legacy por plantilla, retirar los
   `option_rules` sin fuente, añadir `bb_thread_standard` a la lista de retiro.
2. Plantillas nuevas de §4 en orden de productos: workshop_tool, pedal,
   rider_glove, lock, workshop_chemical, grip, hub_axle, saddle, fastener,
   light, food_beverage, control_cable, stem, pump, wheel_retention, handlebar,
   seatpost, control_housing, helmet, control_small_part…
3. Fixtures por interfaz (positivo, negativo, desconocido) con los valores de
   `shared_vocabularies` citados; ninguna interfaz `reference_model_list` se
   activa sin al menos una lista OEM sembrada.
4. Asignación explícita por producto (`assign_product_spec_template_v1`) para
   las 26 clases `reuse` y las reclasificaciones de §5.2, con recibo; las
   `identity_review` esperan envase/foto.
5. Migración de valores legado → nuevos por diccionario explícito (p. ej.
   `bb_shell_standard` → `bb_shell_interface` + ancho; `wheel_size` con un solo
   BSD posible → `bead_seat_diameter_mm`; con varios → desconocido), con
   read-back campo a campo y conservación del literal.
6. Recién entonces, campos críticos por familia y cola de investigación.
