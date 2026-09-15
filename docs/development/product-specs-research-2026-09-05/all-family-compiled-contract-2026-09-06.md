# Contrato compilado de familias y campos — 2026-09-06

Autor: Claude (Fable 5.1), revisor independiente. Codex conserva la decisión final. Este documento es la lectura humana de `all-family-compiled-contract-2026-09-06.json`; el JSON es la fuente. No edita SQL, Dart, datos ni valores de productos. Nada de esto autoriza «catálogo listo».

## 0. Entradas, salida y hashes

| Archivo | SHA-256 |
|---|---|
| Blueprint JSON (congelado) | `250a32e47592aec332d39bb7672197510848f1c9ce78ba53580a4888aedac1a3` |
| Blueprint MD (congelado) | `dfa3092ff336ee061cc51978854f5978e633c293c3801798066c68b4f24f451f` |
| Snapshot legacy-baseline | `52d083195dd3d5d7ac25d6f3e1f361941e088d9678bc3dac629d8251681e0dd7` |
| Contrato JSON (esta entrega) | `785cd11a39011b643e4bcb1422ab805c242f8a7aae0108b399c6aff0c0d78175` |
| Definiciones de producción leídas | 2026-09-06 (post 20260906150000) |

| Métrica | Valor |
|---|---|
| definitions | 539 |
| existing_definitions_used | 127 |
| new_definitions | 412 |
| renamed_keys | 33 |
| union_keys | 21 |
| templates | 105 |
| interfaces | 140 |
| interfaces_evaluable | 119 |
| interfaces_not_applicable | 19 |
| interfaces_structural_only | 2 |
| typed_rules | 170 |
| verified_rules | 151 |
| rules_with_projection_pending | 19 |
| rules_with_unverified_values | 6 |
| fields_with_conditions | 137 |
| unresolved_conditions | 0 |
| existing_rules_reviewed | 120 |
| existing_rules_by_decision | {"keep": 28, "retire": 19, "reexpress_with_source": 34, "demote_to_hint": 30, "reexpress_on_new_keys": 9} |
| fixtures | 476 |
| sources_valid | 30 |

## 1. Cómo leerlo

- **Gramática de condición** (idéntica al borrador `20260906180000`, schema_version 2): `{field, operator, value_type, value}` con `operator ∈ {eq,in,lt,lte,gt,gte}`, `value_type ∈ {decimal,token,boolean}`; decimales como **string exacta**, tokens como texto exacto de la opción, `in` con array, comparaciones sólo sobre decimal. `rows` = AND dentro de la fila, OR entre filas. Un entero del catálogo viaja como `decimal` (string) en una condición.
- **Tipos del catálogo**: `decimal`, `integer` (sólo cuentas discretas), `boolean`, `token` (una opción), `token_set` (varias), `text`, `rows` (estructura tipada con `row_schema`).
- **Por campo y plantilla**: `role`, `required_when`, `allowed_when` (kind `always`/`never`/`when` + AST), `allowed_options` (subconjunto del vocabulario que admite esa plantilla), `known_values` (evidencia de lectura para numéricos: nunca restringe), `requires_identity`, `legacy_action`, `evidence_required`.
- **Prerrequisitos**: `prerequisites[key] = [keys]`; todo campo con rol `declaration` exige `spec_evidence_source`, más los prerrequisitos ya existentes en el `form_contract`.
- **Interfaces**: `required_field_alternatives` (OR de AND de claves reales), `counterpart` (`bike_profile`, `template:<keys>`, `delegate:kit_members`, `external:`, `profile_provider`), y `rules` tipadas: `product_field`, `counterpart_field`, `operator`, `value_type`, `outcome_on_mismatch` (`incompatible`/`caution`/`unknown`/`undetermined`), `outcome_on_unknown = unknown`, `assertion_kind` (`structural` vs `mechanical_claim`), `projection_pending`, `unverified_values` (→ unknown, nunca bloquea), `source_ids`, `verified`.
- **Política de conjunto**: Un veredicto de instalación completa nunca se deriva de una sola interfaz; el resultado por interfaz se reporta por separado y el conjunto queda undetermined mientras cualquier interfaz requerida sea unknown. structural = forma/presencia/formato; mechanical_claim = afirmación física que exige fuente y vocabulario verificado.
- **Requerido** sigue siendo aviso no bloqueante en el validador actual; el contrato no lo convierte en bloqueo.

## 2. Cambios concretos respecto del blueprint

### 2.1 Claves separadas (misma clave, noción distinta) y fusiones con definiciones existentes

| Plantilla | Clave del blueprint | Clave del contrato | Decisión |
|---|---|---|---|
| brake_caliper | `piston_count` | `piston_count_value` | cambio de tipo, no de noción: `piston_count` existente es lista de opciones (2/4/6) y se conserva como legacy; el entero nuevo lo reemplaza por mapa opción→entero |
| hydraulic_disc_brake | `piston_count` | `piston_count_value` | cambio de tipo, no de noción: `piston_count` existente es lista de opciones (2/4/6) y se conserva como legacy; el entero nuevo lo reemplaza por mapa opción→entero |
| hub | `rotor_mount` | `rotor_mount_type` | misma noción que la definición existente: `hub.rotor_mount` del blueprint se funde en `rotor_mount_type` (vocabulario existente + adiciones) |
| rim_brake | `frame_mount` | `rim_brake_frame_mount` | en adaptador `frame_mount` es montaje de disco (IS/PM/FM); en freno de llanta son postes/perno central: nociones distintas |
| pedal | `bearing_construction` | `pedal_bearing_kind` | clave separada: en `pedal` la noción era distinta de la de `bearing_construction` en otras plantillas |
| saddle | `intended_use` | `saddle_intended_use` | clave separada: en `saddle` la noción era distinta de la de `intended_use` en otras plantillas |
| fork | `steerer_type` | `steerer_fit` | vocabulario nuevo de espiga (1", 1-1/8", cónica 1-1/8→1.5…) compartido por horquilla, tee, piezas de dirección y gyro; `steerer_type` existente queda legacy en headset |
| rear_shock | `mount_kind` | `shock_mount_kind` | clave separada: en `rear_shock` la noción era distinta de la de `mount_kind` en otras plantillas |
| headset_small_part | `part_kind` | `headset_part_kind` | clave separada: en `headset_small_part` la noción era distinta de la de `part_kind` en otras plantillas |
| hub_small_part | `part_kind` | `hub_part_kind` | clave separada: en `hub_small_part` la noción era distinta de la de `part_kind` en otras plantillas |
| valve_small_part | `part_kind` | `valve_part_kind` | clave separada: en `valve_small_part` la noción era distinta de la de `part_kind` en otras plantillas |
| control_small_part | `part_kind` | `control_part_kind` | clave separada: en `control_small_part` la noción era distinta de la de `part_kind` en otras plantillas |
| brake_small_part | `part_kind` | `brake_part_kind` | clave separada: en `brake_small_part` la noción era distinta de la de `part_kind` en otras plantillas |
| light | `mount_kind` | `light_mount_kind` | clave separada: en `light` la noción era distinta de la de `mount_kind` en otras plantillas |
| accessory_mount | `mount_kind` | `accessory_mount_kind` | clave separada: en `accessory_mount` la noción era distinta de la de `mount_kind` en otras plantillas |
| rack_basket | `mount_kind` | `carrier_mount_kind` | clave separada: en `rack_basket` la noción era distinta de la de `mount_kind` en otras plantillas |
| rack_basket | `wheel_size_min` | `nominal_wheel_size_min` | `wheel_size_min` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| rack_basket | `wheel_size_max` | `nominal_wheel_size_max` | `wheel_size_max` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| fender | `wheel_size_min` | `nominal_wheel_size_min` | `wheel_size_min` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| fender | `wheel_size_max` | `nominal_wheel_size_max` | `wheel_size_max` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| fender | `mount_kind` | `fender_mount_kind` | clave separada: en `fender` la noción era distinta de la de `mount_kind` en otras plantillas |
| kickstand | `mount_kind` | `kickstand_mount_kind` | clave separada: en `kickstand` la noción era distinta de la de `mount_kind` en otras plantillas |
| kickstand | `wheel_size_min` | `nominal_wheel_size_min` | `wheel_size_min` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| kickstand | `wheel_size_max` | `nominal_wheel_size_max` | `wheel_size_max` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| training_wheel | `wheel_size_min` | `nominal_wheel_size_min` | `wheel_size_min` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| training_wheel | `wheel_size_max` | `nominal_wheel_size_max` | `wheel_size_max` era texto libre; pasa a token del vocabulario nominal compartido (12"…700c) para poder comparar |
| bike_protection | `protection_kind` | `bike_protection_kind` | clave separada: en `bike_protection` la noción era distinta de la de `protection_kind` en otras plantillas |
| souvenir | `item_kind` | `souvenir_kind` | clave separada: en `souvenir` la noción era distinta de la de `item_kind` en otras plantillas |
| rider_glove | `intended_use` | `glove_intended_use` | clave separada: en `rider_glove` la noción era distinta de la de `intended_use` en otras plantillas |
| rider_protection | `protection_kind` | `rider_protection_kind` | clave separada: en `rider_protection` la noción era distinta de la de `protection_kind` en otras plantillas |
| rider_protection | `certification_claim` | `certification_claim_text` | en casco `certification_claim` es multi_select de normas; en protección era texto libre: se separa como texto para no mezclar tipos |
| food_beverage | `item_kind` | `food_item_kind` | clave separada: en `food_beverage` la noción era distinta de la de `item_kind` en otras plantillas |
| wheel | `rotor_mount` | `rotor_mount_type` | misma noción que la definición existente: `hub.rotor_mount` del blueprint se funde en `rotor_mount_type` (vocabulario existente + adiciones) |

### 2.2 Vocabularios unidos (misma noción; cada plantilla conserva su subconjunto)

| Clave | Vocabulario unido | Plantillas |
|---|---|---|
| `axle_diameter_thread` | 3/8" x 26 tpi, 5/16" x 26 tpi, M10 x 1, M9 x 1, Hueco 9 mm (cierre rápido delantero), Hueco 10 mm (cierre rápido trasero), Desconocido / sin confirmar, M14 | hub_axle, hub_small_part |
| `axle_nut_thread` | 3/8" x 26 tpi, 5/16" x 26 tpi, M10 x 1, M14, Desconocido / sin confirmar | training_wheel, wheel_retention |
| `ball_diameter_in` | 1/8, 5/32, 3/16, 7/32, 1/4, Otro | bearing, hub_small_part |
| `bb_thread_hand` | Derecha / Izquierda, Derecha / Derecha, Desconocido / sin confirmar, Sin rosca (a presión) | bottom_bracket, bottom_bracket_cup |
| `bearing_construction` | Cartucho sellado, Bolas sueltas (bolsa), Canastillo con bolas, Desconocido / sin confirmar | bearing, bottom_bracket_bearing |
| `brake_actuation` | Mecánico (cable), Hidráulico, Híbrido (cable a hidráulico), Desconocido / sin confirmar, Contrapedal, Otro | brake_caliper, brake_lever, hub_brake |
| `braking_surface` | Disco, Llanta, Maza (banda / tambor / rodillo) | brake_caliper, brake_pad |
| `crank_bolt_thread` | M8, M12, M14, 3/8", Desconocido / sin confirmar | bottom_bracket_axle, crank_arm |
| `hanger_interface` | Patilla estándar (M10x1), UDH, Direct mount (Shimano), Con uña / claw, Desconocido / sin confirmar, Direct mount | derailleur_hanger, derailleur_hanger_extender |
| `lever_cable_pull` | Tiro largo (V-brake / disco mecánico tiro largo), Tiro corto (ruta / cantilever / caliper), Ajustable, Desconocido / sin confirmar | brake_lever, brake_shift_combined_control |
| `material` | Acero, Aluminio, Plástico, Otro, EVA, Corcho, Gel / PU, Silicona, Carbono, Magnesio / mixta, Policarbonato / plástico, Titanio, Latón, Poliéster / PET, Nylon, Acero galvanizado, Acero inoxidable, Recubierto (teflón / polímero), Plástico / nylon, Goma, PE / plástico, Tritan, Mimbre, PVC / vinilo, Neopreno, Poliéster, Polar, Algodón, Mezcla | accessory_mount, bike_protection, bottle, bottle_cage, brake_small_part, cassette_lockring, chainring_guard, control_cable, control_small_part, fastener, fender, fork, frame, handlebar, handlebar_covering, headset_small_part, kickstand, pedal_peg, rack_basket, rider_apparel, seat_clamp, seatpost, spacer, spoke_nipple, stem, tubeless_tape, wheel_retention |
| `padding` | Gel, Espuma, Sin relleno (impermeable), Otro, Sin acolchado | rider_glove, saddle_cover |
| `power_source` | Recargable USB, Pilas AA/AAA, Pila botón, Dinamo, Otra | audible_signal, cycle_computer, light |
| `rear_derailleur_hanger_interface` | Patilla estándar (M10x1), UDH, Direct mount (Shimano), Con uña / claw, Desconocido / sin confirmar, Sin patilla (single speed) | bicycle, frame |
| `size_label` | XS, S, M, L, XL, XXL, Única, Niño, Otra | helmet, rider_apparel, rider_glove, rider_protection, workshop_tool |
| `sold_as` | Par, Unidad izquierda, Unidad derecha, Unidad | grip, pedal |
| `thread` | M4, M5, M6, M8, M10, M12, M14, 3/8", Otra, Desconocido / sin confirmar | brake_small_part, fastener |

### 2.3 Etiquetas alineadas a las definiciones existentes (los datos no cambian)

El blueprint escribía algunas opciones con otra ortografía; el contrato usa la etiqueta que ya existe en producción y propone, aparte, mejoras sólo de etiqueta.

| Definición | Adiciones propuestas (sólo agregar) | Mejoras sólo-etiqueta propuestas |
|---|---|---|
| `fluid_type` | Desconocido / sin confirmar | {} |
| `mount_standard` | Desconocido / sin confirmar | {"Adaptor Requerido": "(no es un estándar de montaje: se conserva como legacy; la necesidad de adaptador vive en rotor_size_recipe.adapter_required)"} |
| `pedal_thread` |  | {"9/16": "9/16\" x 20 tpi", "1/2": "1/2\" x 20 tpi"} |
| `rotor_mount_type` | Desconocido / sin confirmar | {"6 pernos": "6 pernos (ISO 44 mm)", "Centerlock": "Center Lock"} |
| `spindle_interface` | Desconocido / sin confirmar | {} |
| `spoke_gauge` | 15G (1.8 mm), 1.8/1.6/1.8 (15/16G), Desconocido / sin confirmar | {"14G": "14G (2.0 mm)", "13G": "13G (2.3 mm)", "14/15G": "2.0/1.8/2.0 (14/15G)"} |
| `wheel_position` | Par | {} |

### 2.4 Revisión entero/decimal

| Clave(s) | Decisión | Por qué |
|---|---|---|
| bead_seat_diameter_mm | integer | Código de designación ISO 5775/ETRTO (622, 559, 584…): identificador entero, no medición continua; 134 del scooter es también designación (S26, no verificada). |
| hub_old_mm | decimal | OLD es una dimensión medida entre contratuercas; los valores de S05 son enteros por convención, no por definición. Corrige el `integer` del blueprint. |
| front_hub_old_mm / rear_hub_old_mm / target_hub_old_mm | decimal | Idem. |
| rotor_diameter_mm_value / rotor_included_diameter_mm / rotor_from_mm / rotor_to_mm / max_rotor_mm / max_rotor_rear_mm / rotor_front_mm / rotor_rear_mm | decimal | Diámetro medido (203 vs 203,2 existen en catálogos); se comparan como decimal exacto. |
| valve_length_mm_value | decimal | Largo de válvula es dimensión continua. |
| thru_axle_diameter_mm | decimal | Diámetro nominal de eje; dimensión. |
| volume_ml / serving_volume_ml / sealant_volume_ml / glue_volume_ml | decimal | Volumen continuo; el blueprint tenía `integer` en botella. |
| lumens_claimed / battery_capacity_mah / loudness_db_claim | decimal | Magnitudes declaradas, no cuentas. |
| teeth, coronas, agujeros, posiciones, unidades por envase, pistones, puertos, modos, funciones | integer | Cuentas discretas. |
| definiciones existentes numéricas | según validation_rules vigentes en producción (integer:true → integer; resto decimal) | La migración 20260906150000 ya fijó entero/positivo por definición; el contrato no la contradice. |

### 2.5 Vocabularios copiados literalmente de definiciones existentes

- `chain_speeds_supported`: vocabulario copiado literal de la definición existente `drivetrain_speeds` para que set_membership compare tokens idénticos.
- `chain_tool_speeds`: vocabulario copiado literal de la definición existente `drivetrain_speeds` para que set_membership compare tokens idénticos.
- `compatible_chainring_counts`: vocabulario copiado literal de la definición existente `front_chainring_count` para que set_membership compare tokens idénticos.
- `compatible_rear_speeds`: vocabulario copiado literal de la definición existente `drivetrain_speeds` para que set_membership compare tokens idénticos.

### 2.6 Frases del blueprint → AST (tabla de auditoría)

Cada frase distinta de `required_when`/`allowed_when` y su compilación. Un `≠` se compila como `in` sobre el complemento del subconjunto de la plantilla (la gramática v2 no tiene `not_in`).

| Frase | Compilación | Plantillas |
|---|---|---|
| adaptador | hub_part_kind eq "Adaptador de eje" | hub_small_part |
| aguja | clamp_kind eq "Aguja / palanca de repuesto" | seat_clamp |
| aguja | retention_kind eq "Aguja cierre rápido" | wheel_retention |
| automático | pedal_type in ["Automático (clipless)", "Mixto"] | pedal |
| axle_type eje pasante | axle_type in ["Eje pasante 12 mm", "Eje pasante 15 mm", "Eje pasante 20 mm"] | hub, fork |
| bag_kind = Cubre | bag_kind eq "Cubre-mochila" | rider_bag |
| bag_kind = hidratación | bag_kind eq "Mochila de hidratación" | rider_bag |
| bag_kind ≠ Cubre | bag_kind in ["Mochila", "Mochila de hidratación", "Otro"] | rider_bag |
| bb_construction = Cubetas y canastillo | bb_construction eq "Cubetas y canastillo" | bottom_bracket |
| bb_construction conocido | bb_construction in ["Rodamiento sellado", "Integrado", "Cubetas y canastillo", "A presión", "Roscado entre sí"] | bottom_bracket |
| bb_construction ∈ {cartucho, a presión, integrado} | bb_construction in ["Rodamiento sellado", "A presión", "Integrado", "Roscado entre sí"] | bottom_bracket |
| bb_construction ∈ {copas externas, integrado} | bb_construction in ["Integrado", "Roscado entre sí"] | bottom_bracket |
| bb_shell_interface a presión | bb_shell_interface in ["PF41 (BB86 / BB89.5 / BB92 / BB107 / BB132)", "PF42 (BB30 / BB30a / BB30ai)", "PF46 (PF30 / BB386EVO / OSBB)", "BB90 / BB95 (Trek)", "BMX Spanish 37 mm", "BMX Mid 41.2 mm", "BMX American / Ashtabula 51.5 mm"] | bottom_bracket |
| bb_shell_interface roscado | bb_shell_interface in ["BSA / ISO 1.37\" x 24 tpi (68 / 73 mm)", "Italiano 36 mm x 24 tpi (70 mm)", "T47 47 mm x 1.0", "Francés M35 x 1 (obsoleto)", "Suizo M35 x 1", "Raleigh 1 3/8\" x 26 tpi", "ISIS Overdrive M48 x 1.5"] | bottom_bracket |
| bb_shell_interface roscado o PF41/PF46 | bb_shell_interface in ["BSA / ISO 1.37\" x 24 tpi (68 / 73 mm)", "Italiano 36 mm x 24 tpi (70 mm)", "T47 47 mm x 1.0", "Francés M35 x 1 (obsoleto)", "Suizo M35 x 1", "Raleigh 1 3/8\" x 26 tpi", "ISIS Overdrive M48 x 1.5", "PF41 (BB86 / BB89.5 / BB92 / BB107 / BB132)", "PF46 (PF30 / BB386EVO / OSBB)"] | bottom_bracket |
| bearing_application = Dirección | bearing_application eq "Dirección" | bearing |
| bearing_construction = Bolas sueltas (bolsa) | bearing_construction eq "Bolas sueltas (bolsa)" | bearing |
| bearing_construction = Canastillo con bolas | bearing_construction eq "Canastillo con bolas" | bottom_bracket_bearing |
| bearing_construction = Cartucho sellado | bearing_construction eq "Cartucho sellado" | bearing, bottom_bracket_bearing |
| bearing_construction ∈ {Bolas sueltas, Canastillo} | bearing_construction in ["Bolas sueltas (bolsa)", "Canastillo con bolas"] | bearing |
| bearing_construction ≠ Cartucho sellado | bearing_construction in ["Bolas sueltas (bolsa)", "Canastillo con bolas", "Desconocido / sin confirmar"] | bearing, bottom_bracket_bearing |
| bike_kind = Eléctrica | bike_kind eq "Eléctrica" | bicycle |
| brake_actuation = Hidráulico | brake_actuation eq "Hidráulico" | brake_lever |
| brake_actuation = Mecánico (cable) | brake_actuation eq "Mecánico (cable)" | brake_caliper, brake_lever |
| brake_actuation ∈ {Hidráulico, Híbrido} | brake_actuation in ["Hidráulico", "Híbrido (cable a hidráulico)"] | brake_caliper |
| brake_mount disco | brake_mount in ["Post Mount", "International Standard", "Flat Mount"] | fork |
| braking_surface = Disco | braking_surface eq "Disco" | brake_caliper, brake_pad |
| braking_surface = Disco y hay modelo | braking_surface eq "Disco" + identidad ['model'] | brake_caliper |
| braking_surface = Llanta | braking_surface eq "Llanta" | brake_pad |
| cable_purpose = Freno | cable_purpose eq "Freno" | control_cable |
| caliper | rim_brake_style in ["Side-pull (single pivot)", "Dual pivot", "Center-pull"] | rim_brake |
| carrier_kind = Correa | carrier_kind eq "Correa / pulpo de carga" | rack_basket |
| chainring_mount_type BCD | chainring_mount_type in ["BCD 5 pernos", "BCD 4 pernos"] | chainring, crankset |
| chainring_mount_type BCD 4 pernos | chainring_mount_type eq "BCD 4 pernos" | chainring |
| clamp_kind = Aguja | clamp_kind eq "Aguja / palanca de repuesto" | seat_clamp |
| clamp_kind ≠ Aguja | clamp_kind in ["Collarín con perno", "Collarín con cierre rápido", "Otro"] | seat_clamp |
| cono | hub_part_kind eq "Cono" | hub_small_part |
| consumable_kind = Sellante | consumable_kind eq "Sellante" | tubeless_consumable |
| corta cadena | tool_kind eq "Corta cadena" | workshop_tool |
| covering_kind = Funda | covering_kind eq "Funda / espuma tubular" | handlebar_covering |
| cuando el producto es un miembro con posición | never | brake_caliper, brake_lever, brake_pad |
| device_kind = Audífonos | device_kind eq "Audífonos" | consumer_electronics |
| device_kind = Cable | device_kind eq "Cable de datos/carga" | consumer_electronics |
| device_kind = Cargador | device_kind eq "Cargador" | consumer_electronics |
| device_kind = Tarjeta | device_kind eq "Tarjeta de memoria" | consumer_electronics |
| device_kind ∈ {Cable, Cargador} | device_kind in ["Cable de datos/carga", "Cargador"] | consumer_electronics |
| fastener_kind = Golilla | fastener_kind eq "Golilla / espaciador" | fastener |
| fastener_kind ≠ Golilla | fastener_kind in ["Perno", "Tornillo", "Tuerca", "Kit", "Otro"] | fastener |
| fork_kind suspensión | fork_kind in ["Suspensión (muelle)", "Suspensión (aire)"] | fork |
| freno | cable_purpose eq "Freno" | control_cable |
| front_derailleur_mount = Abrazadera | front_derailleur_mount eq "Abrazadera" | frame |
| front_derailleur_mount_type = Abrazadera | front_derailleur_mount_type eq "Abrazadera" | front_derailleur |
| funda | control_part_kind in ["Tope / terminal de funda", "Guía de cable", "Regulador de tensión (barril)"] | control_small_part |
| garment_kind ∈ {Jersey, Polera} | garment_kind in ["Jersey", "Polera"] | rider_apparel |
| golilla | fastener_kind eq "Golilla / espaciador" | fastener |
| hidráulico | brake_actuation in ["Hidráulico", "Híbrido (cable a hidráulico)"] | brake_caliper |
| hidráulico | brake_actuation eq "Hidráulico" | brake_lever |
| includes_spindle = false | includes_spindle eq false | bottom_bracket |
| includes_spindle = true | includes_spindle eq true | bottom_bracket |
| kits técnicos (toda plantilla con composición) | never | bottom_bracket_cup, brake_lever, crankset, rim_brake, shifter, tubeless_consumable … |
| kits técnicos (toda plantilla con composición) | always | hydraulic_disc_brake, mechanical_disc_brake, drivetrain_kit, wheel |
| lock_kind = U-lock | lock_kind eq "U-lock" | lock |
| lock_kind ∈ {Cable, Cadena} | lock_kind in ["Cable / espiral", "Cadena"] | lock |
| mecánico | brake_actuation eq "Mecánico (cable)" | brake_caliper, brake_lever |
| mount_kind = Gancho | accessory_mount_kind eq "Gancho de pared / almacenamiento" | accessory_mount |
| mount_kind = teléfono | accessory_mount_kind eq "Soporte de teléfono" | accessory_mount |
| o-ring | valve_part_kind eq "O-ring / goma de base" | valve_small_part |
| obús | valve_part_kind eq "Obús (núcleo)" | valve_small_part |
| part_kind = Adaptador de eje | hub_part_kind eq "Adaptador de eje" | hub_small_part |
| part_kind = Cono | hub_part_kind eq "Cono" | hub_small_part |
| part_kind = Noodle | control_part_kind eq "Noodle V-brake" | control_small_part |
| part_kind = O-ring | valve_part_kind eq "O-ring / goma de base" | valve_small_part |
| part_kind = Obús | valve_part_kind eq "Obús (núcleo)" | valve_small_part |
| part_kind = Regulador | control_part_kind eq "Regulador de tensión (barril)" | control_small_part |
| part_kind ∈ {Terminal de piola, Capuchón} | control_part_kind in ["Terminal de piola (crimp)", "Capuchón"] | control_small_part |
| part_kind ∈ {Tope, Guía, Regulador} | control_part_kind in ["Tope / terminal de funda", "Guía de cable", "Regulador de tensión (barril)"] | control_small_part |
| pasante | retention_kind eq "Eje pasante" | wheel_retention |
| pedal_type = Plataforma | pedal_type eq "Plataforma" | pedal |
| pedal_type ∈ {Automático, Mixto} | pedal_type in ["Automático (clipless)", "Mixto"] | pedal |
| piola | control_part_kind in ["Terminal de piola (crimp)", "Capuchón"] | control_small_part |
| power_source = Recargable USB | power_source eq "Recargable USB" | light |
| protection_kind = Funda | bike_protection_kind eq "Funda de bicicleta (cubierta)" | bike_protection |
| quill | stem_kind in ["Tee de espiga (quill)", "Adaptador quill → ahead"] | stem |
| rear_axle_type eje pasante | rear_axle_type in ["Eje pasante 12 mm", "Eje pasante 15 mm", "Eje pasante 20 mm"] | frame |
| regulador | control_part_kind eq "Regulador de tensión (barril)" | control_small_part |
| retention_kind = Aguja | retention_kind eq "Aguja cierre rápido" | wheel_retention |
| retention_kind = Eje pasante | retention_kind eq "Eje pasante" | wheel_retention |
| retention_kind = Tuerca | retention_kind eq "Tuerca de eje" | wheel_retention |
| rim emite compatibilidad | always — requerido = aviso no bloqueante (validador existente) | rim |
| rim_brake_style caliper | rim_brake_style in ["Side-pull (single pivot)", "Dual pivot", "Center-pull"] | rim_brake |
| rim_strip emite compatibilidad | always — requerido = aviso no bloqueante (validador existente) | rim_strip |
| rim_symmetry = Asimétrica | rim_symmetry eq "Asimétrica" | rim |
| roscado | bb_shell_interface in ["BSA / ISO 1.37\" x 24 tpi (68 / 73 mm)", "Italiano 36 mm x 24 tpi (70 mm)", "T47 47 mm x 1.0", "Francés M35 x 1 (obsoleto)", "Suizo M35 x 1", "Raleigh 1 3/8\" x 26 tpi", "ISIS Overdrive M48 x 1.5"] | bottom_bracket_cup |
| seatpost_kind = Suplemento | seatpost_kind eq "Suplemento (shim)" | seatpost |
| seatpost_kind = Telescópica | seatpost_kind eq "Telescópica (dropper)" | seatpost |
| seatpost_kind ≠ Suplemento | seatpost_kind in ["Rígida", "Con suspensión", "Telescópica (dropper)", "Otro"] | seatpost |
| shifter_position ≠ Par | shifter_position in ["Izquierdo / delantero", "Derecho / trasero", "Universal"] | shifter |
| shim | seatpost_kind eq "Suplemento (shim)" | seatpost |
| siempre que se escriba un hecho con procedencia distinta de mechanic | never | bearing, bottom_bracket, bottom_bracket_axle, bottom_bracket_bearing, bottom_bracket_cup, brake_caliper … |
| signal_kind = Bocina | signal_kind eq "Bocina electrónica" | audible_signal |
| spindle_interface cuadrado | spindle_interface in ["Cuadrado JIS", "Cuadrado ISO"] | bottom_bracket, bottom_bracket_axle, crank_arm, crankset |
| spindle_interface ∈ {Cuadrado JIS, Cuadrado ISO} | spindle_interface in ["Cuadrado JIS", "Cuadrado ISO"] | bottom_bracket |
| stem_kind ∈ {quill, adaptador} | stem_kind in ["Tee de espiga (quill)", "Adaptador quill → ahead"] | stem |
| stem_kind ≠ Adaptador | stem_kind in ["Tee sin rosca (ahead)", "Tee de espiga (quill)", "Otro"] | stem |
| tire emite compatibilidad | always — requerido = aviso no bloqueante (validador existente) | tire |
| tire_bead_type ≠ Tubular/Sólido | tire_bead_type in ["Talón plegable", "Talón de alambre", "Desconocido / sin confirmar"] | tire |
| tool_kind = Botella aplicadora | tool_kind eq "Botella aplicadora" | workshop_tool |
| tool_kind = Corta cadena | tool_kind eq "Corta cadena" | workshop_tool |
| tool_kind = EPP | tool_kind eq "EPP (guantes de taller)" | workshop_tool |
| tool_kind = Manómetro | tool_kind eq "Manómetro / bomba de suspensión" | workshop_tool |
| trasera | wheel_position in ["Trasera", "Par"] | wheel |
| tube emite compatibilidad | always — requerido = aviso no bloqueante (validador existente) | tube |
| tuerca | retention_kind eq "Tuerca de eje" | wheel_retention |
| valve_type = Presta | valve_type eq "Presta (francesa)" | tube |
| wheel_position = Trasera | wheel_position eq "Trasera" | hub |
| wheel_position ≠ Delantera | wheel_position in ["Trasera", "Par"] | wheel |

## 3. Las 105 plantillas

| Plantilla | Familia | Estado | Disposición | Productos | Campos | Con condición | Interfaces (evaluables / estructurales / n-a) | Reglas (verificadas) | Kit |
|---|---|---|---|---|---|---|---|---|---|
| `bearing` | bearing | existing | extend | 9 | 10 | 7 | 1 / 0 / 0 | 1 (1) |  |
| `bottom_bracket` | bottom_bracket | existing | extend | 34 | 19 | 14 | 2 / 0 / 0 | 4 (4) |  |
| `bottom_bracket_axle` | bottom_bracket_axle | existing | extend | 3 | 7 | 1 | 1 / 0 / 0 | 1 (1) |  |
| `bottom_bracket_bearing` | bottom_bracket_bearing | existing | extend | 3 | 10 | 6 | 1 / 0 / 0 | 1 (1) |  |
| `bottom_bracket_cup` | bottom_bracket_cup | existing | extend | 8 | 11 | 1 | 2 / 0 / 0 | 3 (3) | kit_members |
| `brake_caliper` | brake_caliper | existing | split | 11 | 18 | 9 | 3 / 0 / 0 | 7 (7) |  |
| `brake_lever` | brake_lever | existing | extend | 15 | 13 | 3 | 2 / 0 / 0 | 5 (5) | kit_members |
| `brake_pad` | brake_pad | existing | split | 53 | 17 | 10 | 2 / 0 / 0 | 2 (2) |  |
| `cassette` | cassette | existing | extend | 29 | 12 | 0 | 2 / 0 / 0 | 3 (1) |  |
| `cassette_spacer` | cassette_spacer | existing | retain | 3 | 4 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `chain` | chain | existing | retain | 31 | 13 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `chain_guide` | chain_guide | existing | extend | 3 | 7 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `chain_link` | chain_link | existing | retain | 9 | 13 | 0 | 1 / 0 / 0 | 2 (1) |  |
| `chainring` | chainring | existing | extend | 16 | 15 | 2 | 2 / 0 / 0 | 3 (3) |  |
| `hydraulic_disc_brake` | complete_brake | existing | extend | 3 | 16 | 0 | 1 / 0 / 0 | 2 (2) | kit_members |
| `mechanical_disc_brake` | complete_brake | existing | extend | 0 | 13 | 0 | 1 / 0 / 0 | 2 (2) | kit_members |
| `crank_arm` | crank_arm | existing | extend | 7 | 7 | 1 | 2 / 0 / 0 | 2 (2) |  |
| `crankset` | crankset | existing | extend | 27 | 20 | 2 | 3 / 0 / 0 | 3 (3) | kit_members |
| `derailleur_hanger` | derailleur_hanger | existing | extend | 23 | 7 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `derailleur_pulley` | derailleur_pulley | existing | extend | 7 | 7 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `drivetrain_kit` | drivetrain_kit | existing | extend | 1 | 15 | 0 | 1 / 0 / 0 | 1 (0) | kit_members |
| `fixed_cog` | fixed_cog | existing | retain | 0 | 6 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `freewheel` | freewheel | existing | extend | 28 | 11 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `front_derailleur` | front_derailleur | existing | extend | 15 | 15 | 1 | 2 / 0 / 0 | 3 (3) |  |
| `headset` | headset | existing | split | 15 | 9 | 0 | 1 / 0 / 0 | 2 (2) |  |
| `hub` | hub | existing | extend | 48 | 17 | 2 | 4 / 0 / 0 | 6 (6) |  |
| `rear_derailleur` | rear_derailleur | existing | extend | 35 | 14 | 0 | 3 / 0 / 0 | 5 (4) |  |
| `rim` | rim | existing | extend | 41 | 19 | 1 | 3 / 0 / 0 | 4 (4) |  |
| `rim_brake` | rim_brake | existing | extend | 24 | 12 | 2 | 2 / 0 / 0 | 2 (2) | kit_members |
| `rim_strip` | rim_strip | existing | extend | 3 | 6 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `rotor` | rotor | existing | extend | 18 | 12 | 0 | 2 / 0 / 0 | 2 (2) |  |
| `shifter` | shifter | existing | extend | 32 | 13 | 1 | 2 / 0 / 0 | 2 (2) | kit_members |
| `spoke` | spoke | existing | extend | 48 | 8 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `tire` | tire | existing | extend | 113 | 12 | 1 | 2 / 0 / 0 | 4 (4) |  |
| `tube` | tube | existing | extend | 137 | 14 | 1 | 1 / 1 / 0 | 2 (2) |  |
| `tubeless_consumable` | tubeless_consumable | existing | extend | 3 | 6 | 1 | 0 / 0 / 1 | 0 (0) | kit_members |
| `tubeless_valve` | tubeless_valve | existing | extend | 8 | 8 | 0 | 1 / 0 / 0 | 1 (0) |  |
| `pedal` | pedal | new | create | 0 | 11 | 2 | 2 / 0 / 0 | 2 (2) |  |
| `pedal_peg` | pedal_peg | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `grip` | grip | new | create | 0 | 9 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `handlebar_covering` | handlebar_covering | new | create | 0 | 10 | 1 | 1 / 0 / 0 | 1 (1) | kit_members |
| `handlebar` | handlebar | new | create | 0 | 10 | 0 | 2 / 0 / 0 | 2 (2) |  |
| `stem` | stem | new | create | 0 | 10 | 2 | 2 / 0 / 0 | 2 (2) |  |
| `seatpost` | seatpost | new | create | 0 | 12 | 6 | 2 / 0 / 0 | 2 (2) |  |
| `seat_clamp` | seat_clamp | new | create | 0 | 6 | 2 | 1 / 0 / 0 | 1 (1) |  |
| `saddle` | saddle | new | create | 0 | 9 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `saddle_cover` | saddle_cover | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 3 (3) |  |
| `fork` | fork | new | create | 0 | 19 | 5 | 4 / 0 / 0 | 9 (9) |  |
| `rear_shock` | rear_shock | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 3 (3) |  |
| `spacer` | spacer | new | create | 0 | 8 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `headset_small_part` | headset_small_part | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 1 (1) | kit_members |
| `hub_axle` | hub_axle | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `hub_small_part` | hub_small_part | new | create | 0 | 8 | 3 | 1 / 0 / 0 | 1 (1) |  |
| `wheel_retention` | wheel_retention | new | create | 0 | 11 | 5 | 1 / 0 / 0 | 2 (2) |  |
| `spoke_nipple` | spoke_nipple | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `tubeless_tape` | tubeless_tape | new | create | 0 | 5 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `tubeless_repair` | tubeless_repair | new | create | 0 | 5 | 0 | 0 / 0 / 1 | 0 (0) | kit_members |
| `valve_small_part` | valve_small_part | new | create | 0 | 7 | 2 | 1 / 0 / 0 | 1 (1) |  |
| `tire_liner` | tire_liner | new | create | 0 | 5 | 0 | 1 / 0 / 0 | 3 (3) |  |
| `tube_repair` | tube_repair | new | create | 0 | 7 | 0 | 0 / 0 / 1 | 0 (0) | kit_members |
| `control_cable` | control_cable | new | create | 0 | 7 | 1 | 1 / 0 / 0 | 2 (2) |  |
| `control_housing` | control_housing | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (0) |  |
| `control_small_part` | control_small_part | new | create | 0 | 9 | 4 | 1 / 0 / 0 | 2 (2) |  |
| `hydraulic_fitting` | hydraulic_fitting | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (1) | kit_members |
| `hydraulic_hose` | hydraulic_hose | new | create | 0 | 8 | 0 | 1 / 0 / 0 | 1 (1) | kit_members |
| `brake_fluid` | brake_fluid | new | create | 0 | 4 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `brake_mount_adapter` | brake_mount_adapter | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 2 (2) |  |
| `rotor_mount_adapter` | rotor_mount_adapter | new | create | 0 | 3 | 0 | 1 / 0 / 0 | 2 (1) |  |
| `brake_small_part` | brake_small_part | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `hub_brake` | hub_brake | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (0) |  |
| `bmx_cable_detangler` | bmx_cable_detangler | new | create | 0 | 4 | 0 | 1 / 0 / 0 | 1 (1) | kit_members |
| `derailleur_hanger_extender` | derailleur_hanger_extender | new | create | 0 | 5 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `cassette_lockring` | cassette_lockring | new | create | 0 | 4 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `chainring_guard` | chainring_guard | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `fastener` | fastener | new | create | 0 | 10 | 3 | 0 / 1 / 0 | 0 (0) |  |
| `workshop_tool` | workshop_tool | new | create | 0 | 9 | 4 | 1 / 0 / 0 | 1 (1) |  |
| `workshop_chemical` | workshop_chemical | new | create | 0 | 8 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `lock` | lock | new | create | 0 | 12 | 3 | 0 / 0 / 1 | 0 (0) | kit_members |
| `light` | light | new | create | 0 | 14 | 1 | 1 / 0 / 0 | 2 (2) | kit_members |
| `audible_signal` | audible_signal | new | create | 0 | 7 | 1 | 1 / 0 / 0 | 2 (2) |  |
| `cycle_computer` | cycle_computer | new | create | 0 | 6 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `consumer_electronics` | consumer_electronics | new | create | 0 | 11 | 7 | 0 / 0 / 1 | 0 (0) |  |
| `accessory_mount` | accessory_mount | new | create | 0 | 10 | 5 | 1 / 0 / 0 | 2 (2) |  |
| `bottle_cage` | bottle_cage | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 1 (0) |  |
| `bottle` | bottle | new | create | 0 | 7 | 0 | 1 / 0 / 0 | 1 (0) |  |
| `rack_basket` | rack_basket | new | create | 0 | 9 | 1 | 1 / 0 / 0 | 3 (0) |  |
| `fender` | fender | new | create | 0 | 9 | 0 | 1 / 0 / 0 | 3 (1) | kit_members |
| `kickstand` | kickstand | new | create | 0 | 8 | 0 | 1 / 0 / 0 | 2 (0) |  |
| `bike_bag` | bike_bag | new | create | 0 | 6 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `rider_bag` | rider_bag | new | create | 0 | 8 | 4 | 1 / 0 / 0 | 2 (2) |  |
| `training_wheel` | training_wheel | new | create | 0 | 6 | 0 | 1 / 0 / 0 | 1 (0) | kit_members |
| `bike_protection` | bike_protection | new | create | 0 | 7 | 1 | 0 / 0 / 1 | 0 (0) |  |
| `reflector` | reflector | new | create | 0 | 4 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `souvenir` | souvenir | new | create | 0 | 4 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `rider_glove` | rider_glove | new | create | 0 | 8 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `helmet` | helmet | new | create | 0 | 11 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `eyewear` | eyewear | new | create | 0 | 5 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `rider_apparel` | rider_apparel | new | create | 0 | 7 | 1 | 0 / 0 / 1 | 0 (0) |  |
| `rider_protection` | rider_protection | new | create | 0 | 6 | 0 | 0 / 0 / 1 | 0 (0) | kit_members |
| `food_beverage` | food_beverage | new | create | 0 | 7 | 0 | 0 / 0 / 1 | 0 (0) |  |
| `pump` | pump | new | create | 0 | 9 | 0 | 1 / 0 / 0 | 1 (1) |  |
| `bicycle` | bicycle | new | create | 0 | 35 | 4 | 0 / 0 / 1 | 0 (0) | kit_members |
| `frame` | frame | new | create | 0 | 25 | 2 | 0 / 0 / 1 | 0 (0) |  |
| `wheel` | wheel | new | create | 0 | 14 | 1 | 4 / 0 / 0 | 5 (5) | kit_members |
| `brake_shift_combined_control` | brake_shift_combined_control | new | create | 0 | 7 | 0 | 2 / 0 / 0 | 2 (2) |  |

## 4. Reglas tipadas por interfaz

`incompatible` sólo con fuente registrada y sin proyección pendiente (lo comprueba `cc_validate`); una proyección pendiente baja la regla a `caution` hasta que exista.

| Plantilla | Regla | Campo | Contraparte | Op | Tipo | Si no calza | Proyección pendiente | Valores no verificados | Fuentes | Verificada |
|---|---|---|---|---|---|---|---|---|---|---|
| bearing | bearing_cartridge_fit.bearing_size_code | `bearing_size_code` | template:hub\|headset\|bottom_bracket → bearing_size_code | eq | token | incompatible |  |  | S17 | sí |
| bottom_bracket | bb_to_frame_shell.bb_shell_interface | `bb_shell_interface` | bike_profile → bb_shell_interface | eq | token | incompatible |  |  | S03, S09 | sí |
| bottom_bracket | bb_to_frame_shell.bb_shell_width_mm | `bb_shell_width_mm` | bike_profile → bb_shell_width_mm | eq | decimal | incompatible |  |  | S03, S09 | sí |
| bottom_bracket | bb_to_crank_spindle.spindle_interface | `spindle_interface` | template:crankset → spindle_interface | in | token | incompatible |  |  | S03, S09 | sí |
| bottom_bracket | bb_to_crank_spindle.spindle_interface_accepted | `spindle_interface_accepted` | template:crankset → spindle_interface | in | token | incompatible |  |  | S03, S09 | sí |
| bottom_bracket_axle | axle_to_cups_and_cranks.spindle_interface | `spindle_interface` | template:crankset → spindle_interface | eq | token | incompatible |  |  | S03 | sí |
| bottom_bracket_bearing | bb_bearing_fit.bearing_size_code | `bearing_size_code` | template:bottom_bracket → bearing_size_code | eq | token | incompatible |  |  | S17 | sí |
| bottom_bracket_cup | cup_to_frame_shell.bb_shell_interface | `bb_shell_interface` | bike_profile → bb_shell_interface | eq | token | incompatible |  |  | S03, S09 | sí |
| bottom_bracket_cup | cup_to_frame_shell.bb_shell_width_mm | `bb_shell_width_mm` | bike_profile → bb_shell_width_mm | eq | decimal | incompatible |  |  | S03, S09 | sí |
| bottom_bracket_cup | cup_to_crank_spindle.spindle_interface_accepted | `spindle_interface_accepted` | template:crankset → spindle_interface | in | token | incompatible |  |  | S03, S09 | sí |
| brake_caliper | caliper_to_frame_mount_and_rotor.mount_standard | `mount_standard` | bike_profile → brake_mount_front\|brake_mount_rear | row_lookup | token | unknown |  |  | S20 | sí |
| brake_caliper | caliper_to_frame_mount_and_rotor.rotor_size_recipe | `rotor_size_recipe` | bike_profile → rotor_front_mm\|rotor_rear_mm | row_lookup | rows | unknown |  |  | S20 | sí |
| brake_caliper | caliper_to_pad.pad_shape_code | `pad_shape_code` | template:brake_pad → pad_shape_code | eq | token | incompatible |  |  | S20 | sí |
| brake_caliper | caliper_to_lever_actuation.brake_actuation | `brake_actuation` | template:brake_lever → brake_actuation | eq | token | incompatible |  |  | S27 | sí |
| brake_caliper | caliper_to_lever_actuation.fluid_type | `fluid_type` | template:brake_lever → fluid_type | eq | token | incompatible |  |  | S27 | sí |
| brake_caliper | caliper_to_lever_actuation.cable_pull_required | `cable_pull_required` | template:brake_lever → lever_cable_pull | eq | token | incompatible |  |  | S27 | sí |
| brake_caliper | caliper_to_lever_actuation.hose_system_code | `hose_system_code` | template:brake_lever → hose_system_code | eq | token | incompatible |  |  | S27 | sí |
| brake_lever | lever_to_brake.brake_actuation | `brake_actuation` | template:rim_brake\|brake_caliper → brake_actuation | eq | token | incompatible |  |  | S12, S27 | sí |
| brake_lever | lever_to_brake.lever_cable_pull | `lever_cable_pull` | template:rim_brake\|brake_caliper → lever_pull_required\|cable_pull_required | eq | token | incompatible |  |  | S12, S27 | sí |
| brake_lever | lever_to_brake.fluid_type | `fluid_type` | template:rim_brake\|brake_caliper → fluid_type | eq | token | incompatible |  |  | S12, S27 | sí |
| brake_lever | lever_to_brake.hose_system_code | `hose_system_code` | template:rim_brake\|brake_caliper → hose_system_code | eq | token | incompatible |  |  | S12, S27 | sí |
| brake_lever | lever_to_handlebar.handlebar_clamp_mm | `handlebar_clamp_mm` | template:handlebar → grip_area_diameter_mm | eq | decimal | incompatible |  |  | S06 | sí |
| brake_pad | disc_pad_to_caliper.pad_shape_code | `pad_shape_code` | template:brake_caliper → pad_shape_code | row_match | token | incompatible |  |  | S20 | sí |
| brake_pad | rim_pad_to_brake.rim_pad_stud_type | `rim_pad_stud_type` | template:rim_brake → rim_pad_stud_type | eq | token | incompatible |  |  | S12 | sí |
| cassette | cassette_to_hub_body.freehub_bodies_accepted | `freehub_bodies_accepted` | template:hub\|wheel → rear_drive_interface | row_match | rows | incompatible |  | Rueda libre roscada M30 x 1 (BMX) | S14, S15, S16, S08 | sí |
| cassette | cassette_to_chain.sprocket_count | `sprocket_count` | template:chain → chain_speeds | in | decimal | caution | entero → token: el número como texto exacto («11») |  | S11 | no |
| cassette | cassette_to_chain.shift_technology | `shift_technology` | template:chain → chain_profile_family | eq | token | caution | LINKGLIDE ↔ familia de perfil de cadena: mapa de tokens pendiente |  | S11 | no |
| cassette_spacer | spacer_to_body.target_rear_drive_interface | `target_rear_drive_interface` | template:hub → rear_drive_interface | eq | token | incompatible |  | Rueda libre roscada M30 x 1 (BMX) | S08, S14, S16 | sí |
| chain | chain_to_rear_speeds.chain_speeds | `chain_speeds` | bike_profile → rear_speeds | in | token | caution |  |  | S11, S07 | sí |
| chain_guide | guide_to_frame_and_ring.chain_guide_mount_type | `chain_guide_mount_type` | bike_profile → iscg_tabs | eq | token | incompatible |  |  | S09 | sí |
| chain_link | connector_to_chain_model.chain_connector_target | `chain_connector_target` | template:chain → drivetrain_primary_ecosystem | eq | token | caution | el eslabón se declara por marca/ecosistema; el modelo exacto exige lista OEM |  | S07 | no |
| chain_link | connector_to_chain_model.chain_speeds | `chain_speeds` | template:chain → chain_speeds | in | token | incompatible |  |  | S07 | sí |
| chainring | ring_to_crank_spider.chainring_mount_type | `chainring_mount_type` | template:crankset → chainring_mount_type | eq | token | incompatible |  |  | S02 | sí |
| chainring | ring_to_crank_spider.chainring_bcd_mm | `chainring_bcd_mm` | template:crankset → chainring_bcd_mm | eq | decimal | incompatible |  |  | S02 | sí |
| chainring | ring_to_chain.compatible_rear_speeds | `compatible_rear_speeds` | template:chain → chain_speeds | in | token | caution |  |  | S11 | sí |
| hydraulic_disc_brake | complete_brake_to_frame.mount_standard | `mount_standard` | bike_profile → brake_mount_front\|brake_mount_rear | row_lookup | token | unknown |  |  | S20, S27 | sí |
| hydraulic_disc_brake | complete_brake_to_frame.rotor_size_recipe | `rotor_size_recipe` | bike_profile → rotor_front_mm\|rotor_rear_mm | row_lookup | rows | unknown |  |  | S20, S27 | sí |
| mechanical_disc_brake | complete_brake_to_frame.mount_standard | `mount_standard` | bike_profile → brake_mount_front\|brake_mount_rear | row_lookup | token | unknown |  |  | S20 | sí |
| mechanical_disc_brake | complete_brake_to_frame.rotor_size_recipe | `rotor_size_recipe` | bike_profile → rotor_front_mm\|rotor_rear_mm | row_lookup | rows | unknown |  |  | S20 | sí |
| crank_arm | arm_to_spindle.spindle_interface | `spindle_interface` | template:bottom_bracket\|bottom_bracket_axle → spindle_interface | eq | token | incompatible |  |  | S03 | sí |
| crank_arm | arm_to_pedal.pedal_thread | `pedal_thread` | template:pedal → pedal_thread | eq | token | incompatible |  |  | S13 | sí |
| crankset | crank_to_bottom_bracket.spindle_interface | `spindle_interface` | template:bottom_bracket → spindle_interface\|spindle_interface_accepted | in | token | incompatible |  |  | S03, S09 | sí |
| crankset | crank_to_pedal.pedal_thread | `pedal_thread` | template:pedal → pedal_thread | eq | token | incompatible |  |  | S13 | sí |
| crankset | crank_to_chain.compatible_rear_speeds | `compatible_rear_speeds` | template:chain → chain_speeds | in | token | caution |  |  | S11 | sí |
| derailleur_hanger | hanger_to_frame.compatible_frames | `compatible_frames` | bike_profile → identity.brand+identity.model | row_match | rows | incompatible |  |  | S17 | sí |
| derailleur_pulley | pulley_to_derailleur.compatible_derailleur_models | `compatible_derailleur_models` | template:rear_derailleur → identity.brand+identity.model | row_match | rows | incompatible |  |  | S11 | sí |
| drivetrain_kit | kit_members_to_bike.kit_members | `kit_members` | delegate:kit_members → members[*].family → interfaces de la plantilla miembro | delegate | rows | undetermined | cada miembro se evalúa con su propia plantilla; el kit nunca aprueba en bloque |  | S14, S15 | no |
| fixed_cog | cog_to_hub_thread.cog_thread_standard | `cog_thread_standard` | template:hub → rear_drive_interface | eq | token | incompatible |  |  | S19 | sí |
| freewheel | freewheel_to_hub_thread.freewheel_thread_standard | `freewheel_thread_standard` | template:hub → rear_drive_interface | eq | token | incompatible |  |  | S08, S19 | sí |
| front_derailleur | fd_to_frame.front_derailleur_mount_type | `front_derailleur_mount_type` | bike_profile → front_derailleur_mount | eq | token | incompatible |  |  | S17 | sí |
| front_derailleur | fd_to_frame.front_derailleur_clamp_mm | `front_derailleur_clamp_mm` | bike_profile → seat_tube_outer_for_fd_mm | eq | token | incompatible |  |  | S17 | sí |
| front_derailleur | fd_to_shifter.shift_actuation_family | `shift_actuation_family` | template:shifter → shift_actuation_family | eq | token | caution |  |  | S11 | sí |
| headset | headset_to_frame_and_fork.headset_upper_shis | `headset_upper_shis` | bike_profile → headset_upper_shis | eq | token | incompatible |  |  | S04, S10, S23 | sí |
| headset | headset_to_frame_and_fork.headset_lower_shis | `headset_lower_shis` | bike_profile → headset_lower_shis | eq | token | incompatible |  |  | S04, S10, S23 | sí |
| hub | hub_to_frame_dropout.hub_old_mm | `hub_old_mm` | bike_profile → rear_hub_old_mm\|front_hub_old_mm | eq | decimal | incompatible |  |  | S05, S28 | sí |
| hub | hub_to_frame_dropout.axle_type | `axle_type` | bike_profile → rear_axle_type\|front_axle_type | eq | token | incompatible |  |  | S05, S28 | sí |
| hub | hub_to_frame_dropout.thru_axle_thread | `thru_axle_thread` | bike_profile → thru_axle_thread | eq | token | incompatible |  |  | S05, S28 | sí |
| hub | hub_to_cassette_or_freewheel.rear_drive_interface | `rear_drive_interface` | template:cassette\|freewheel\|fixed_cog → freehub_bodies_accepted.rear_drive_interface\|freewheel_thread_standard\|cog_thread_standard | row_match | token | incompatible |  | Rueda libre roscada M30 x 1 (BMX) | S14, S16, S08 | sí |
| hub | hub_to_rotor.rotor_mount_type | `rotor_mount_type` | template:rotor → rotor_mount_type | eq | token | incompatible |  |  | S20 | sí |
| hub | hub_to_rim_spokes.spoke_hole_count | `spoke_hole_count` | template:rim → spoke_hole_count | eq | decimal | incompatible |  |  | S24 | sí |
| rear_derailleur | rd_to_drivetrain_range.rear_derailleur_max_teeth | `rear_derailleur_max_teeth` | template:cassette+crankset → cassette.largest_cog_teeth | gte | decimal | incompatible |  |  | S17 | sí |
| rear_derailleur | rd_to_drivetrain_range.rear_derailleur_min_teeth | `rear_derailleur_min_teeth` | template:cassette+crankset → cassette.smallest_cog_teeth | lte | decimal | incompatible |  |  | S17 | sí |
| rear_derailleur | rd_to_drivetrain_range.rear_derailleur_total_capacity_teeth | `rear_derailleur_total_capacity_teeth` | template:cassette+crankset → computed:(largest_cog−smallest_cog)+(largest_ring−smallest_ring) | gte | decimal | caution | S17: capacidad declarada vs diferencia calculada |  | S17 | no |
| rear_derailleur | rd_to_shifter.shifter_models_compatible | `shifter_models_compatible` | template:shifter → identity.brand+identity.model | row_match | rows | incompatible |  |  | S11 | sí |
| rear_derailleur | rd_to_hanger.rear_derailleur_mount_type | `rear_derailleur_mount_type` | bike_profile → rear_derailleur_hanger_interface | eq | token | incompatible |  |  | S17 | sí |
| rim | rim_to_tire.bead_seat_diameter_mm | `bead_seat_diameter_mm` | template:tire → bead_seat_diameter_mm | eq | decimal | incompatible |  |  | S01 | sí |
| rim | rim_to_tire.tire_width_range_mm | `tire_width_range_mm` | template:tire → tire_width_mm | eq | rows | incompatible |  |  | S01 | sí |
| rim | rim_to_spokes_hub.spoke_hole_count | `spoke_hole_count` | template:hub → spoke_hole_count | eq | decimal | incompatible |  |  | S24 | sí |
| rim | rim_to_rim_brake.brake_track | `brake_track` | template:rim_brake → const:true | eq | boolean | incompatible |  |  | S12 | sí |
| rim_brake | rim_brake_to_frame.rim_brake_frame_mount | `rim_brake_frame_mount` | bike_profile → brake_mount_front\|brake_mount_rear | eq | token | incompatible |  |  | S12 | sí |
| rim_brake | rim_brake_to_lever.lever_pull_required | `lever_pull_required` | template:brake_lever → lever_cable_pull | eq | token | incompatible |  |  | S12 | sí |
| rim_strip | strip_to_rim.bead_seat_diameter_mm | `bead_seat_diameter_mm` | template:rim → bead_seat_diameter_mm | eq | decimal | incompatible |  |  | S01 | sí |
| rotor | rotor_to_hub.rotor_mount_type | `rotor_mount_type` | template:hub → rotor_mount_type | eq | token | incompatible |  |  | S20 | sí |
| rotor | rotor_to_caliper.rotor_diameter_mm_value | `rotor_diameter_mm_value` | template:brake_caliper → rotor_size_recipe.rotor_diameter_mm | eq | decimal | incompatible |  |  | S20 | sí |
| shifter | shifter_to_derailleur.derailleur_models_compatible | `derailleur_models_compatible` | template:rear_derailleur\|front_derailleur → identity.brand+identity.model | row_match | rows | incompatible |  |  | S11 | sí |
| shifter | shifter_to_handlebar.handlebar_clamp_mm | `handlebar_clamp_mm` | template:handlebar → grip_area_diameter_mm | eq | decimal | incompatible |  |  | S06 | sí |
| spoke | spoke_to_wheel_geometry.spoke_thread_diameter_mm | `spoke_thread_diameter_mm` | template:rim\|hub\|spoke_nipple → nipple_thread | eq | decimal | incompatible |  |  | S24 | sí |
| tire | tire_to_rim.bead_seat_diameter_mm | `bead_seat_diameter_mm` | template:rim\|wheel → bead_seat_diameter_mm | eq | decimal | incompatible |  |  | S01 | sí |
| tire | tire_to_rim.tire_width_mm | `tire_width_mm` | template:rim\|wheel → tire_width_range_mm | eq | decimal | incompatible |  |  | S01 | sí |
| tire | tire_to_tube.bead_seat_diameter_mm | `bead_seat_diameter_mm` | template:tube → tube_fit_rows.bead_seat_diameter_mm | row_match | decimal | incompatible |  |  | S01 | sí |
| tire | tire_to_tube.tire_width_mm | `tire_width_mm` | template:tube → tube_fit_rows.width_min_mm..width_max_mm | row_match | decimal | incompatible |  |  | S01 | sí |
| tube | tube_to_tire_and_rim.tube_fit_rows | `tube_fit_rows` | template:tire\|rim → bead_seat_diameter_mm+tire_width_mm | row_match | rows | incompatible |  |  | S01 | sí |
| tube | tube_to_tire_and_rim.valve_type | `valve_type` | template:tire\|rim → valve_hole | row_match | token | incompatible |  |  | S01 | sí |
| tubeless_valve | valve_to_rim.valve_type | `valve_type` | template:rim → valve_hole | eq | token | caution | valve_type (Presta/Schrader) ↔ valve_hole (6,5/8,5 mm): mapa de tokens — pasa a incompatible cuando exista la proyección |  | S22 | no |
| pedal | pedal_to_crank.pedal_thread | `pedal_thread` | template:crankset\|crank_arm → pedal_thread | eq | token | incompatible |  |  | S13, S19 | sí |
| pedal | pedal_to_shoe_cleat.cleat_system | `cleat_system` | external:calzado (no está en el catálogo) → external.cleat_system | eq | token | incompatible |  |  | S13 | sí |
| pedal_peg | peg_to_hub_axle.peg_axle_fit | `peg_axle_fit` | template:hub_axle → axle_diameter_thread | eq | token | incompatible |  |  | S05 | sí |
| grip | grip_to_handlebar.grip_inner_diameter_mm | `grip_inner_diameter_mm` | template:handlebar → grip_area_diameter_mm | eq | decimal | incompatible |  |  | S06 | sí |
| handlebar_covering | covering_to_bar.inner_diameter_mm | `inner_diameter_mm` | template:handlebar → grip_area_diameter_mm | eq | decimal | incompatible |  |  | S06 | sí |
| handlebar | bar_to_stem.bar_clamp_diameter_mm | `bar_clamp_diameter_mm` | template:stem → bar_clamp_diameter_mm | eq | decimal | incompatible |  |  | S06 | sí |
| handlebar | bar_to_controls.grip_area_diameter_mm | `grip_area_diameter_mm` | template:grip\|brake_lever\|shifter → grip_inner_diameter_mm\|handlebar_clamp_mm | eq | decimal | incompatible |  |  | S06 | sí |
| stem | stem_to_steerer.steerer_fit | `steerer_fit` | template:fork → steerer_fit | eq | token | incompatible |  |  | S04, S06 | sí |
| stem | stem_to_handlebar.bar_clamp_diameter_mm | `bar_clamp_diameter_mm` | template:handlebar → bar_clamp_diameter_mm | eq | decimal | incompatible |  |  | S06 | sí |
| seatpost | post_to_seat_tube.seatpost_diameter_mm | `seatpost_diameter_mm` | bike_profile → seatpost_diameter_mm | eq | decimal | incompatible |  |  | S18 | sí |
| seatpost | post_to_saddle_rails.rail_clamp_fit | `rail_clamp_fit` | template:saddle → rail_type | eq | token | incompatible |  |  | S18 | sí |
| seat_clamp | clamp_to_seat_tube.seat_tube_outer_diameter_mm | `seat_tube_outer_diameter_mm` | bike_profile → seat_tube_outer_diameter_mm | eq | decimal | incompatible |  |  | S18 | sí |
| saddle | saddle_to_post.rail_type | `rail_type` | template:seatpost → rail_clamp_fit | eq | token | incompatible |  |  | S18 | sí |
| saddle_cover | cover_to_saddle.fits_saddle_length_min_mm | `fits_saddle_length_min_mm` | template:saddle → saddle_length_mm | lte | decimal | caution |  |  | S18 | sí |
| saddle_cover | cover_to_saddle.fits_saddle_length_max_mm | `fits_saddle_length_max_mm` | template:saddle → saddle_length_mm | gte | decimal | caution |  |  | S18 | sí |
| saddle_cover | cover_to_saddle.fits_saddle_width_max_mm | `fits_saddle_width_max_mm` | template:saddle → saddle_width_mm | gte | decimal | caution |  |  | S18 | sí |
| fork | fork_to_headset_and_frame.steerer_fit | `steerer_fit` | template:headset → headset_upper_shis | eq | token | incompatible |  |  | S04, S23 | sí |
| fork | fork_to_headset_and_frame.crown_race_diameter_mm | `crown_race_diameter_mm` | template:headset → headset_lower_shis | eq | decimal | incompatible |  |  | S04, S23 | sí |
| fork | fork_to_front_wheel.axle_type | `axle_type` | template:hub\|wheel → axle_type | eq | token | incompatible |  |  | S05, S28 | sí |
| fork | fork_to_front_wheel.hub_old_mm | `hub_old_mm` | template:hub\|wheel → hub_old_mm | eq | decimal | incompatible |  |  | S05, S28 | sí |
| fork | fork_to_front_wheel.thru_axle_thread | `thru_axle_thread` | template:hub\|wheel → thru_axle_thread | eq | token | incompatible |  |  | S05, S28 | sí |
| fork | fork_to_brake.brake_mount | `brake_mount` | template:brake_caliper → mount_standard | row_lookup | token | unknown |  |  | S20 | sí |
| fork | fork_to_brake.max_rotor_mm | `max_rotor_mm` | template:brake_caliper → rotor_size_recipe.rotor_diameter_mm | row_lookup | decimal | unknown |  |  | S20 | sí |
| fork | fork_to_tire.bead_seat_diameter_mm | `bead_seat_diameter_mm` | template:tire → bead_seat_diameter_mm | gte..lte | decimal | incompatible |  |  | S01 | sí |
| fork | fork_to_tire.max_tire_width_mm | `max_tire_width_mm` | template:tire → tire_width_mm | gte..lte | decimal | incompatible |  |  | S01 | sí |
| rear_shock | shock_to_frame.eye_to_eye_mm | `eye_to_eye_mm` | bike_profile → rear_shock_size | eq | decimal | incompatible |  |  | S25 | sí |
| rear_shock | shock_to_frame.stroke_mm | `stroke_mm` | bike_profile → rear_shock_size | eq | decimal | incompatible |  |  | S25 | sí |
| rear_shock | shock_to_frame.shock_mount_kind | `shock_mount_kind` | bike_profile → rear_shock_size | eq | token | incompatible |  |  | S25 | sí |
| spacer | spacer_to_shaft.inner_diameter_mm | `inner_diameter_mm` | template:fork → steerer_fit | eq | decimal | incompatible |  |  | S04 | sí |
| headset_small_part | preload_to_steerer.steerer_fit | `steerer_fit` | template:fork → steerer_fit | eq | token | incompatible |  |  | S04 | sí |
| hub_axle | axle_to_hub_shell.axle_diameter_thread | `axle_diameter_thread` | template:hub → axle_type | eq | token | incompatible |  |  | S05 | sí |
| hub_small_part | part_to_axle.axle_diameter_thread | `axle_diameter_thread` | template:hub_axle → axle_diameter_thread | eq | token | incompatible |  |  | S05 | sí |
| wheel_retention | retention_to_hub_and_frame.thru_axle_thread | `thru_axle_thread` | template:hub → thru_axle_thread | eq | token | incompatible |  |  | S05, S28 | sí |
| wheel_retention | retention_to_hub_and_frame.target_hub_old_mm | `target_hub_old_mm` | template:hub → hub_old_mm | eq | decimal | incompatible |  |  | S05, S28 | sí |
| spoke_nipple | nipple_to_spoke_and_rim.nipple_thread | `nipple_thread` | template:spoke → spoke_thread_diameter_mm | eq | token | incompatible |  |  | S24 | sí |
| tubeless_tape | tape_to_rim.tape_width_mm | `tape_width_mm` | template:rim → rim_internal_width_mm | gte..lte | decimal | incompatible |  |  | S22 | sí |
| valve_small_part | part_to_valve.valve_type | `valve_type` | template:tube\|tubeless_valve → valve_type | eq | token | incompatible |  |  | S22 | sí |
| tire_liner | liner_to_tire.bead_seat_diameters_supported | `bead_seat_diameters_supported` | template:tire → bead_seat_diameter_mm | row_match | rows | incompatible |  |  | S01 | sí |
| tire_liner | liner_to_tire.tire_width_min_mm | `tire_width_min_mm` | template:tire → tire_width_mm | lte | decimal | caution |  |  | S01 | sí |
| tire_liner | liner_to_tire.tire_width_max_mm | `tire_width_max_mm` | template:tire → tire_width_mm | gte | decimal | caution |  |  | S01 | sí |
| control_cable | cable_to_lever.cable_purpose | `cable_purpose` | template:brake_lever\|shifter → template | eq | token | incompatible |  |  | S21 | sí |
| control_cable | cable_to_lever.cable_head | `cable_head` | template:brake_lever\|shifter → cable_head_required | eq | token | incompatible |  |  | S21 | sí |
| control_housing | housing_to_system.housing_kind | `housing_kind` | template:control_cable → cable_purpose | eq | token | caution | mapa de tokens housing_kind → cable_purpose (freno ↔ Freno, cambio ↔ Cambio) — pasa a incompatible cuando exista la proyección |  | S21 | no |
| control_small_part | part_to_cable_or_housing.fits_cable_diameter_mm | `fits_cable_diameter_mm` | template:control_cable\|control_housing → cable_diameter_mm | eq | decimal | incompatible |  |  | S21 | sí |
| control_small_part | part_to_cable_or_housing.fits_housing_diameter_mm | `fits_housing_diameter_mm` | template:control_cable\|control_housing → housing_outer_diameter_mm | eq | decimal | incompatible |  |  | S21 | sí |
| hydraulic_fitting | fitting_to_hose_and_caliper.hose_system_code | `hose_system_code` | template:brake_caliper\|hydraulic_hose → hose_system_code | eq | token | incompatible |  |  | S27 | sí |
| hydraulic_hose | hose_to_system.hose_system_code | `hose_system_code` | template:brake_caliper\|brake_lever → hose_system_code | eq | token | incompatible |  |  | S27 | sí |
| brake_fluid | fluid_to_brake.fluid_type | `fluid_type` | template:brake_caliper\|brake_lever\|hydraulic_disc_brake → fluid_type | eq | token | incompatible |  |  | S27 | sí |
| brake_mount_adapter | adapter_recipe.caliper_mount | `caliper_mount` | template:brake_caliper+bike_profile → mount_standard | row_lookup | token | unknown |  |  | S20 | sí |
| brake_mount_adapter | adapter_recipe.frame_mount | `frame_mount` | template:brake_caliper+bike_profile → brake_mount_front\|brake_mount_rear | row_lookup | token | unknown |  |  | S20 | sí |
| rotor_mount_adapter | adapter_hub_to_rotor.hub_interface | `hub_interface` | template:hub+rotor → hub.rotor_mount_type\|hub.rear_drive_interface | eq | token | caution | hub_interface usa tokens compuestos («Centerlock → 6 pernos»): proyección pendiente — pasa a incompatible cuando exista la proyección |  | S20 | no |
| rotor_mount_adapter | adapter_hub_to_rotor.rotor_mount_out | `rotor_mount_out` | template:hub+rotor → rotor.rotor_mount_type | eq | token | incompatible |  | 6 pernos | S20 | sí |
| brake_small_part | part_to_brake_model.compatible_brake_models | `compatible_brake_models` | template:brake_caliper\|brake_lever\|hydraulic_disc_brake → identity.brand+identity.model | row_match | rows | incompatible |  |  | S12 | sí |
| hub_brake | hub_brake_to_hub.axle_fit | `axle_fit` | template:hub → axle_type | eq | token | caution | tokens de axle_fit vs axle_type: proyección pendiente |  | S12 | no |
| bmx_cable_detangler | detangler_to_headset.steerer_fit | `steerer_fit` | template:fork → steerer_fit | eq | token | incompatible |  |  | S29, S04 | sí |
| derailleur_hanger_extender | extender_to_hanger_and_rd.hanger_interface | `hanger_interface` | bike_profile → rear_derailleur_hanger_interface | eq | token | incompatible |  |  | S17 | sí |
| cassette_lockring | lockring_to_body.target_rear_drive_interface | `target_rear_drive_interface` | template:hub → rear_drive_interface | eq | token | incompatible |  | Rueda libre roscada M30 x 1 (BMX) | S14, S16 | sí |
| chainring_guard | guard_to_crank.chainring_bcd_mm | `chainring_bcd_mm` | template:crankset → chainring_bcd_mm | gte..lte | decimal | incompatible |  |  | S02 | sí |
| workshop_tool | tool_to_standard.chain_tool_speeds | `chain_tool_speeds` | template:chain → chain_speeds | in | token | caution |  |  | S30, S11 | sí |
| light | light_to_bar_or_post.mount_diameter_min_mm | `mount_diameter_min_mm` | template:handlebar\|seatpost → grip_area_diameter_mm\|seatpost_diameter_mm | lte | decimal | caution |  |  | S06 | sí |
| light | light_to_bar_or_post.mount_diameter_max_mm | `mount_diameter_max_mm` | template:handlebar\|seatpost → grip_area_diameter_mm\|seatpost_diameter_mm | gte | decimal | caution |  |  | S06 | sí |
| audible_signal | signal_to_bar.mount_diameter_min_mm | `mount_diameter_min_mm` | template:handlebar → grip_area_diameter_mm | lte | decimal | caution |  |  | S06 | sí |
| audible_signal | signal_to_bar.mount_diameter_max_mm | `mount_diameter_max_mm` | template:handlebar → grip_area_diameter_mm | gte | decimal | caution |  |  | S06 | sí |
| accessory_mount | mount_to_bar_and_device.bar_diameter_min_mm | `bar_diameter_min_mm` | template:handlebar → grip_area_diameter_mm | lte | decimal | caution |  |  | S06 | sí |
| accessory_mount | mount_to_bar_and_device.bar_diameter_max_mm | `bar_diameter_max_mm` | template:handlebar → grip_area_diameter_mm | gte | decimal | caution |  |  | S06 | sí |
| bottle_cage | cage_to_frame.cage_mount | `cage_mount` | bike_profile → frame.bottle_bosses_count | eq | token | caution | montaje con pernos exige bottle_bosses_count ≥ 1: proyección token → conteo |  | S06 | no |
| bottle | bottle_to_cage.bottle_diameter_mm | `bottle_diameter_mm` | template:bottle_cage → bottle_diameter_mm | eq | decimal | caution | tolerancia de la jaula no normada |  | S06 | no |
| rack_basket | carrier_to_bike.carrier_mount_kind | `carrier_mount_kind` | bike_profile → frame.rack_mounts | eq | token | caution | anclajes exigen rack_mounts = true: proyección token → boolean |  | S06 | no |
| rack_basket | carrier_to_bike.nominal_wheel_size_min | `nominal_wheel_size_min` | bike_profile → nominal derivado de bead_seat_diameter_mm | in | token | caution | rango ordinal min..max de nominales → conjunto de tokens; el nominal del perfil se deriva del BSD (nominal_wheel_size_to_bsd) |  | S06 | no |
| rack_basket | carrier_to_bike.nominal_wheel_size_max | `nominal_wheel_size_max` | bike_profile → nominal derivado de bead_seat_diameter_mm | in | token | caution | idem |  | S06 | no |
| fender | fender_to_bike.max_tire_width_mm | `max_tire_width_mm` | bike_profile+template:tire → tire.tire_width_mm | gte | decimal | caution |  |  | S01 | sí |
| fender | fender_to_bike.nominal_wheel_size_min | `nominal_wheel_size_min` | bike_profile+template:tire → nominal derivado de bead_seat_diameter_mm | in | token | caution | rango ordinal min..max de nominales → conjunto de tokens; el nominal del perfil se deriva del BSD (nominal_wheel_size_to_bsd) |  | S01 | no |
| fender | fender_to_bike.nominal_wheel_size_max | `nominal_wheel_size_max` | bike_profile+template:tire → nominal derivado de bead_seat_diameter_mm | in | token | caution | idem |  | S01 | no |
| kickstand | kickstand_to_frame.nominal_wheel_size_min | `nominal_wheel_size_min` | bike_profile → nominal derivado de bead_seat_diameter_mm | in | token | caution | rango ordinal min..max de nominales → conjunto de tokens; el nominal del perfil se deriva del BSD (nominal_wheel_size_to_bsd) |  | S06 | no |
| kickstand | kickstand_to_frame.nominal_wheel_size_max | `nominal_wheel_size_max` | bike_profile → nominal derivado de bead_seat_diameter_mm | in | token | caution | idem |  | S06 | no |
| rider_bag | cover_to_bag.fits_volume_min_l | `fits_volume_min_l` | template:rider_bag → volume_l | lte | decimal | caution |  |  | S06 | sí |
| rider_bag | cover_to_bag.fits_volume_max_l | `fits_volume_max_l` | template:rider_bag → volume_l | gte | decimal | caution |  |  | S06 | sí |
| training_wheel | training_wheel_to_bike.axle_nut_thread | `axle_nut_thread` | bike_profile → rear_axle_type | eq | token | caution | rosca de tuerca vs tipo de eje: proyección pendiente |  | S05 | no |
| pump | pump_to_valve.valve_heads_supported | `valve_heads_supported` | template:tube\|tubeless_valve → valve_type | in | token | caution |  |  | S22 | sí |
| wheel | wheel_to_frame_or_fork.hub_old_mm | `hub_old_mm` | bike_profile → rear_hub_old_mm\|front_hub_old_mm | eq | decimal | incompatible |  |  | S05, S28 | sí |
| wheel | wheel_to_frame_or_fork.axle_type | `axle_type` | bike_profile → rear_axle_type\|front_axle_type | eq | token | incompatible |  |  | S05, S28 | sí |
| wheel | wheel_to_tire.bead_seat_diameter_mm | `bead_seat_diameter_mm` | template:tire → bead_seat_diameter_mm | eq | decimal | incompatible |  |  | S01 | sí |
| wheel | wheel_to_cassette.rear_drive_interface | `rear_drive_interface` | template:cassette → freehub_bodies_accepted | row_match | token | incompatible |  | Rueda libre roscada M30 x 1 (BMX) | S14, S16 | sí |
| wheel | wheel_to_rotor.rotor_mount_type | `rotor_mount_type` | template:rotor → rotor_mount_type | eq | token | incompatible |  |  | S20 | sí |
| brake_shift_combined_control | combined_to_derailleur.derailleur_models_compatible | `derailleur_models_compatible` | template:rear_derailleur → identity.brand+identity.model | row_match | rows | incompatible |  |  | S11 | sí |
| brake_shift_combined_control | combined_to_brake.lever_cable_pull | `lever_cable_pull` | template:rim_brake → lever_pull_required | eq | token | incompatible |  |  | S12 | sí |

### 4.1 Interfaces sin regla tipada

- `tube.tube_valve_to_rim_depth` (range_contains): sólo forma. 
- `fastener.fastener_to_thread` (exact_match): sólo forma. 

Las 19 interfaces `n/a` son los 17 `no_compatibility`/`none` (ropa, casco, lentes, candado, electrónica, café, souvenir, reflector, protección, bolsos, químicos, reparación) y los dos proveedores de perfil (`bicycle`, `frame`).

## 5. Reglas existentes del snapshot (120)

| Decisión | Reglas | Significado |
|---|---|---|
| reexpress_with_source | 34 | hecho documentado en S03/S09: se reescribe como constraint con fuente sobre `bb_shell_interface` |
| demote_to_hint | 30 | lista `allow` sin fuente: pasa a sugerencia no bloqueante |
| keep | 28 | se conserva tal cual (visibilidad sin cambio de vocabulario o constraint con fuente) |
| retire | 19 | lista `allow` sin fuente sobre clave legacy: se retira (los datos no cambian) |
| reexpress_on_new_keys | 9 | misma condición sobre la clave nueva que reemplaza a la legacy |

| Plantilla | Campo | Tipo de regla | Decisión | Razón |
|---|---|---|---|---|
| bottom_bracket | `bb_ball_size_in` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `bb_ball_size_in` | option_rules ×2 | retire | lista allow sin fuente sobre clave legacy; los datos no cambian |
| bottom_bracket | `bb_ball_count_per_side` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `bb_ball_count_per_side` | option_rules ×2 | retire | lista allow sin fuente sobre clave legacy; los datos no cambian |
| bottom_bracket | `spindle_diameter_mm` | visibility_rules ×2 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `spindle_diameter_mm` | option_rules ×7 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket | `spindle_interface` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `spindle_interface` | option_rules ×4 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket | `spindle_interface` | option_rules ×4 | retire | lista allow sin fuente sobre clave legacy; los datos no cambian |
| bottom_bracket | `includes_spindle` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `bb_spacer_stack_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `bb_spacer_stack_mm` | option_rules ×3 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket | `bb_cup_thread_pair` | visibility_rules ×2 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket | `bb_cup_thread_pair` | option_rules ×3 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket | `bearing_size_code` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `bb_shell_width_mm` | visibility_rules ×1 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket | `bb_shell_width_mm` | option_rules ×5 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket | `spindle_length_mm` | visibility_rules ×2 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `spindle_length_mm` | option_rules ×6 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket | `bb_cup_outer_diameter_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `bb_cup_outer_diameter_mm` | option_rules ×2 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket | `bb_shell_diameter_mm` | visibility_rules ×1 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket | `bb_shell_diameter_mm` | option_rules ×6 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket | `spindle_interface_accepted` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket | `spindle_interface_accepted` | option_rules ×4 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket | `spindle_interface_accepted` | option_rules ×4 | retire | lista allow sin fuente sobre clave legacy; los datos no cambian |
| bottom_bracket | `bb_construction` | visibility_rules ×1 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket | `bb_construction` | option_rules ×4 | retire | lista allow sin fuente sobre clave legacy; los datos no cambian |
| bottom_bracket_axle | `bb_construction` | option_rules ×1 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket_axle | `spindle_length_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_axle | `spindle_length_mm` | option_rules ×6 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket_axle | `spindle_interface` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_axle | `spindle_interface` | option_rules ×2 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket_axle | `spindle_diameter_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_axle | `spindle_diameter_mm` | option_rules ×3 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket_bearing | `bearing_inner_diameter_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_bearing | `bb_ball_count_per_side` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_bearing | `bb_bearing_width_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_bearing | `bearing_outer_diameter_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_bearing | `bearing_size_code` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_bearing | `bb_construction` | option_rules ×1 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| bottom_bracket_bearing | `bb_ball_size_in` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_bearing | `spindle_diameter_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_cup | `bb_construction` | visibility_rules ×1 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket_cup | `bb_construction` | option_rules ×3 | retire | lista allow sin fuente sobre clave legacy; los datos no cambian |
| bottom_bracket_cup | `bb_shell_width_mm` | visibility_rules ×1 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket_cup | `bb_shell_width_mm` | option_rules ×4 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket_cup | `bb_cup_outer_diameter_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_cup | `bb_cup_outer_diameter_mm` | option_rules ×2 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket_cup | `bb_cup_thread_pair` | visibility_rules ×2 | reexpress_on_new_keys | toca clave legacy; misma condición sobre la clave nueva |
| bottom_bracket_cup | `bb_cup_thread_pair` | option_rules ×2 | reexpress_with_source | hecho documentado (anchos/diámetros/sentido de rosca de caja y eje): se reescribe como constraint con fuente sobre bb_shell_interface |
| bottom_bracket_cup | `spindle_interface_accepted` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| bottom_bracket_cup | `spindle_interface_accepted` | option_rules ×3 | demote_to_hint | lista allow sin fuente: pasa a sugerencia no bloqueante |
| chain | `chain_width_family` | constraint_rules ×1 | keep | cita fuente |
| chain_link | `chain_outer_width_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |
| chain_link | `chain_link_reusable` | constraint_rules ×1 | keep | cita fuente |
| rim | `rim_asymmetric_offset_mm` | visibility_rules ×1 | keep | visibilidad sin cambio de vocabulario |

## 6. Mapas de valores legado → clave nueva

Deterministas y sin adivinar: lo que no mapea queda `unknown` y el valor legacy se conserva.

| Mapa | Tipo | Nota |
|---|---|---|
| bb_shell_standard→bb_shell_interface | option_to_option | Las opciones que agrupan varios estándares (p. ej. «BBRight / OSBB») van al mismo PF46 sólo por diámetro; el ancho se lee aparte. |
| wheel_size→bead_seat_diameter_mm | option_to_value_or_unknown | Sólo nominales con un único BSD documentado; 24" y 26" quedan desconocidos hasta leer ETRTO. |
| valve_type→valve_hole (rim) | option_to_option | Diámetros 6,5 / 8,5 mm no verificados hoy: el mapa es evidencia pendiente. |
| hub_spacing_mm→hub_old_mm | option_to_decimal | Valor numérico exacto como string decimal. |
| spoke_holes→spoke_hole_count | option_to_integer |  |
| valve_length_mm→valve_length_mm_value | option_to_decimal |  |
| rotor_diameter_mm→rotor_diameter_mm_value | option_to_decimal_or_unknown | «203/180» y similares son recetas delantero/trasero: en rotor quedan desconocidas; en cáliper alimentan rotor_size_recipe sólo si el OEM confirma la posición. |
| piston_count→piston_count_value | option_to_integer |  |
| drivetrain_speeds→sprocket_count (cassette/freewheel) | set_to_integer_if_single | Sólo si el conjunto guardado tiene exactamente un valor; con varios queda desconocido y el conjunto se conserva en legacy. |
| drivetrain_speeds→compatible_rear_speeds (plato/biela/cambio/desviador) | set_to_set | Copia literal del conjunto declarado. |
| front_chainring_count→chainring_count (crankset) / compatible_chainring_counts (desviador/mando) | set_to_integer_if_single | set_to_set |  |
| brake_type→braking_surface+brake_actuation | option_to_pair |  |
| caliper_hydraulic→brake_actuation | boolean_to_option | false significaba «no hidráulico», que hoy sólo puede leerse como mecánico si brake_type lo confirma; si no, desconocido. |
| bb_cup_thread_pair→bb_thread_hand | option_to_option |  |
| freehub_type→rear_drive_interface (hub) / cassette_spline_standard (cassette) / freewheel_thread_standard (freewheel) | option_to_option_per_template | Las opciones históricas «Shimano HG» y «Shimano HG Road 11» no distinguen HG spline M/L/L2 ni 7v: se resuelven por modelo del producto, no por la opción. |
| headset_standard→headset_upper_shis+headset_lower_shis | unknown_always | Una opción plana no determina dos códigos SHIS. |
| rear_derailleur_mount_type «Extensor de pata»→reclasificación | reclassify_product |  |
| cassette_cog_sequence→cog_sequence | text_parse | Sólo secuencias numéricas separadas por - / ,; cualquier otro texto queda legacy. |
| chainring_teeth→teeth_count / chainring_teeth_rows | text_parse | Un número → teeth_count; varios → filas ordenadas. |
| tube_width_*_in/mm→tube_fit_rows | compose_rows | Fila sólo si existe BSD único y los mm vienen del envase; pulgadas no se convierten. |

Ejemplo `bb_shell_standard → bb_shell_interface`:

| Opción legacy | Interfaz nueva |
|---|---|
| BSA / Caja inglesa 34,8 mm (1.37") x 24 | BSA / ISO 1.37" x 24 tpi (68 / 73 mm) |
| Italiano 36 mm x 24 | Italiano 36 mm x 24 tpi (70 mm) |
| T47 47 mm | T47 47 mm x 1.0 |
| Francés 35 mm x 1 | Francés M35 x 1 (obsoleto) |
| Suizo 35 mm x 1 | Suizo M35 x 1 |
| Euro BMX roscado 68 mm | unknown |
| BB86 / BB92 41 mm | PF41 (BB86 / BB89.5 / BB92 / BB107 / BB132) |
| PF30 46 mm | PF46 (PF30 / BB386EVO / OSBB) |
| BB30 42 mm | PF42 (BB30 / BB30a / BB30ai) |
| BB386EVO 46 mm | PF46 (PF30 / BB386EVO / OSBB) |
| BB90 / BB95 | BB90 / BB95 (Trek) |
| BBRight / OSBB | PF46 (PF30 / BB386EVO / OSBB) |
| Mid BMX 41,2 mm | BMX Mid 41.2 mm |
| Spanish BMX 37 mm | BMX Spanish 37 mm |
| Americano 51,5 mm | BMX American / Ashtabula 51.5 mm |

## 7. Matriz de fixtures

Total 476: {'valid': 158, 'invalid': 158, 'unknown': 158, 'structural_only': 2}; por tipo de afirmación {'mechanical_claim': 471, 'structural': 5}. Cada regla tipada tiene tres casos (válido / inválido / desconocido) con valores verificados del vocabulario; el resultado esperado se da **por interfaz** (`expected_interface_outcome`) y **por conjunto** (`expected_assembly_outcome`), y el conjunto nunca es `compatible` por una sola interfaz.

| Plantilla | Regla | Caso | Producto | Contraparte | Interfaz | Conjunto |
|---|---|---|---|---|---|---|
| brake_caliper | caliper_to_frame_mount_and_rotor.mount_standard | valid | {"mount_standard": "Post Mount"} | {"brake_mount_front\|brake_mount_rear": "Post Mount"} | compatible_on_this_interface_only | undetermined |
| brake_caliper | caliper_to_frame_mount_and_rotor.mount_standard | invalid | {"mount_standard": "Post Mount"} | {"brake_mount_front\|brake_mount_rear": "Flat Mount"} | unknown | undetermined |
| brake_caliper | caliper_to_frame_mount_and_rotor.mount_standard | unknown | {"mount_standard": "Post Mount"} | {"brake_mount_front\|brake_mount_rear": null} | unknown | undetermined |
| brake_caliper | caliper_to_frame_mount_and_rotor.rotor_size_recipe | valid | {"rotor_size_recipe": "<fila válida según row_schema>"} | {"rotor_front_mm\|rotor_rear_mm": "<fila válida según row_schema>"} | compatible_on_this_interface_only | undetermined |
| brake_caliper | caliper_to_frame_mount_and_rotor.rotor_size_recipe | invalid | {"rotor_size_recipe": "<fila válida según row_schema>"} | {"rotor_front_mm\|rotor_rear_mm": "<fila con otro valor>"} | unknown | undetermined |
| brake_caliper | caliper_to_frame_mount_and_rotor.rotor_size_recipe | unknown | {"rotor_size_recipe": "<fila válida según row_schema>"} | {"rotor_front_mm\|rotor_rear_mm": null} | unknown | undetermined |
| brake_caliper | caliper_to_pad.pad_shape_code | valid | {"pad_shape_code": "<texto A>"} | {"pad_shape_code": "<texto A>"} | compatible_on_this_interface_only | undetermined |
| brake_caliper | caliper_to_pad.pad_shape_code | invalid | {"pad_shape_code": "<texto A>"} | {"pad_shape_code": "<texto B>"} | incompatible | incompatible |
| brake_caliper | caliper_to_pad.pad_shape_code | unknown | {"pad_shape_code": "<texto A>"} | {"pad_shape_code": null} | unknown | undetermined |
| brake_caliper | caliper_to_lever_actuation.brake_actuation | valid | {"brake_actuation": "Mecánico (cable)"} | {"brake_actuation": "Mecánico (cable)"} | compatible_on_this_interface_only | undetermined |
| brake_caliper | caliper_to_lever_actuation.brake_actuation | invalid | {"brake_actuation": "Mecánico (cable)"} | {"brake_actuation": "Hidráulico"} | incompatible | incompatible |
| brake_caliper | caliper_to_lever_actuation.brake_actuation | unknown | {"brake_actuation": "Mecánico (cable)"} | {"brake_actuation": null} | unknown | undetermined |
| brake_caliper | caliper_to_lever_actuation.fluid_type | valid | {"fluid_type": "Aceite Mineral"} | {"fluid_type": "Aceite Mineral"} | compatible_on_this_interface_only | undetermined |
| brake_caliper | caliper_to_lever_actuation.fluid_type | invalid | {"fluid_type": "Aceite Mineral"} | {"fluid_type": "DOT 4"} | incompatible | incompatible |
| brake_caliper | caliper_to_lever_actuation.fluid_type | unknown | {"fluid_type": "Aceite Mineral"} | {"fluid_type": null} | unknown | undetermined |
| cassette | cassette_to_hub_body.freehub_bodies_accepted | valid | {"freehub_bodies_accepted": "Shimano HG spline S (7v)"} | {"rear_drive_interface": "Shimano HG spline S (7v)"} | compatible_on_this_interface_only | undetermined |
| cassette | cassette_to_hub_body.freehub_bodies_accepted | invalid | {"freehub_bodies_accepted": "Shimano HG spline S (7v)"} | {"rear_drive_interface": "Shimano HG spline M (10/9/8/7v MTB; MTB 11v; LINKGLIDE 9/10/11v; 7v sólo CS-HG210-7 / CS-HG400-7)"} | incompatible | incompatible |
| cassette | cassette_to_hub_body.freehub_bodies_accepted | unknown | {"freehub_bodies_accepted": "Shimano HG spline S (7v)"} | {"rear_drive_interface": null} | unknown | undetermined |
| cassette | cassette_to_chain.sprocket_count | valid | {"sprocket_count": "1"} | {"chain_speeds": "1"} | compatible_on_this_interface_only | undetermined |
| cassette | cassette_to_chain.sprocket_count | invalid | {"sprocket_count": "1"} | {"chain_speeds": "2"} | caution | undetermined |
| cassette | cassette_to_chain.sprocket_count | unknown | {"sprocket_count": "1"} | {"chain_speeds": null} | unknown | undetermined |
| cassette | cassette_to_chain.shift_technology | valid | {"shift_technology": "HYPERGLIDE"} | {"chain_profile_family": "HYPERGLIDE"} | compatible_on_this_interface_only | undetermined |
| cassette | cassette_to_chain.shift_technology | invalid | {"shift_technology": "HYPERGLIDE"} | {"chain_profile_family": "HYPERGLIDE+"} | caution | undetermined |
| cassette | cassette_to_chain.shift_technology | unknown | {"shift_technology": "HYPERGLIDE"} | {"chain_profile_family": null} | unknown | undetermined |
| chain | chain_to_rear_speeds.chain_speeds | valid | {"chain_speeds": "1"} | {"rear_speeds": "1"} | compatible_on_this_interface_only | undetermined |
| chain | chain_to_rear_speeds.chain_speeds | invalid | {"chain_speeds": "1"} | {"rear_speeds": "5"} | caution | undetermined |
| chain | chain_to_rear_speeds.chain_speeds | unknown | {"chain_speeds": "1"} | {"rear_speeds": null} | unknown | undetermined |
| hub | hub_to_frame_dropout.hub_old_mm | valid | {"hub_old_mm": "135"} | {"rear_hub_old_mm\|front_hub_old_mm": "135"} | compatible_on_this_interface_only | undetermined |
| hub | hub_to_frame_dropout.hub_old_mm | invalid | {"hub_old_mm": "135"} | {"rear_hub_old_mm\|front_hub_old_mm": "142"} | incompatible | incompatible |
| hub | hub_to_frame_dropout.hub_old_mm | unknown | {"hub_old_mm": "135"} | {"rear_hub_old_mm\|front_hub_old_mm": null} | unknown | undetermined |

(Las 476 filas completas están en `fixtures` del JSON.)

## 8. Revisión de generalizaciones de las fuentes

| Fuentes | Regla | Alcance exacto | Lo que NO afirma |
|---|---|---|---|
| S01 | BSD igual | Requisito necesario para que el neumático monte en la llanta. | No aprueba llanta + neumático: faltan ancho dentro del rango OEM (o guía 1,45–2,0× como caution), talón compatible (hookless/tubeless según OEM) y presión máxima. Una sola interfaz nunca aprueba la instalación. |
| S01 | Relación 1,45–2,0× ancho interior | Guía general de Sheldon/Boeger; se emite caution fuera de rango sólo cuando no existe tabla OEM. | No es límite normativo actual; ETRTO y fabricantes publican tablas propias que mandan. |
| S02 | Lista de BCD documentados | Valores históricos y actuales conocidos; sirve para leer nombres y para saber que 58 y 145 existen. | No es lista cerrada ni define máximos: un BCD fuera de la lista no es inválido. |
| S05 | Lista de OLD | Valores documentados por Sheldon; OLD es medida continua (decimal). | No define máximos actuales (fat 197 existe; futuros anchos posibles); OLD igual no aprueba sin tipo de eje y rosca. |
| S06 | Diámetros de abrazadera | Lista histórica de Sheldon; 35 mm no aparece y se conserva como unverified. | No es lista cerrada. |
| S11 | Anchos nominales por velocidades | Sólo lectura de nombres; nunca deriva velocidades ni aprueba (decisión de producto 2026-09-06). | No convierte ancho medido en velocidades. |
| S14, S15, S16 | Filas de cuerpo de maza | Tabla OEM literal con notas; las filas del contrato se copian, no se deducen. | No cubre marcas fuera de Shimano/SRAM ni cuerpos de terceros «HG compatible» sin su propia declaración. |
| S17 | Capacidad del cambio | Fórmula de holgura; se compara con la capacidad declarada del modelo. | No sustituye piñón máximo/mínimo ni la lista OEM mando↔cambio. |
| S18 | Diámetros de tija | Décimas pares y rangos usuales; el diámetro exacto lo da el cuadro. | No es lista cerrada; un cuadro puede usar otra medida. |
| S20 | Montajes de cáliper | Nombres de montaje y necesidad de adaptador al cambiar diámetro. | No da la tabla de adaptadores: cada fila de receta necesita su fuente OEM. |
| S27 | DOT vs mineral | Nunca cruzar fluidos; kits separados. | No dice que dos aceites minerales de marcas distintas sean intercambiables. |
| S26 | 8.5×2 = 50-134 | Nombra el tamaño del neumático del scooter (fuente comunitaria). | No aprueba ninguna unidad ni maza concreta. |
| S04, S23 | Tablas de dirección | Diámetros de copa/corona/espiga y códigos SHIS por extremo. | No aprueban un juego sin los dos códigos del cuadro y la horquilla. |

## 9. Fuentes

| Id | Título | URL válida (regex 180000) | Grado |
|---|---|---|---|
| S01 | Sheldon Brown — Tire Sizing Systems | sí | primary |
| S02 | Sheldon Brown — Crank/Chainring BCD Crib Sheet | sí | primary |
| S03 | Sheldon Brown — Bottom Bracket Size Database (roscas y conos) | sí | primary |
| S04 | Sheldon Brown — Headset Size Crib Sheet | sí | primary |
| S05 | Sheldon Brown — Frame Spacing (Over-Locknut Dimension) | sí | primary |
| S06 | Sheldon Brown — Handlebar and Stem Size Crib Sheet | sí | primary |
| S07 | Sheldon Brown — Chains | sí | primary |
| S08 | Sheldon Brown — Shimano Cassettes & Freehubs | sí | primary |
| S09 | Park Tool — Bottom Bracket Standards and Terminology (rev. 2019-09-18) | sí | primary |
| S10 | Park Tool — Headset Standards (S.H.I.S.) | sí | primary |
| S11 | Park Tool — Chain Compatibility (2017-02-17) | sí | primary |
| S12 | Park Tool — Brake Pad Replacement: Rim Brakes (2017-01-24) | sí | primary |
| S13 | Park Tool — Pedal Installation and Removal (2015-08-21) | sí | primary |
| S14 | Shimano — FREEHUB and cassette spline compatibility C-731 | sí | primary |
| S15 | Shimano — LINKGLIDE cassette and FREEHUB compatibility C-649 | sí | primary |
| S16 | SRAM — XD and XDR Driver Body Explained | sí | primary |
| S17 | Sheldon Brown — Glossary Ca–Ce (Capacity, Cassette, Cantilever, Cartridge bearing) | sí | primary |
| S18 | Sheldon Brown — Seatpost Size Database | sí | primary |
| S19 | Sheldon Brown — Pedals; Thread-on Freewheels | sí | primary |
| S20 | Park Tool — Mechanical / Hydraulic Disc Brake Alignment; Rotor Removal & Installation | sí | primary |
| S21 | Park Tool — How to Size and Install Shift Cable Housing; Brake Housing & Cable Installation | sí | primary |
| S22 | Park Tool — Tubeless Tire Conversion; Tubeless Tire Compatibility | sí | primary |
| S23 | Cane Creek — The Ultimate Guide to Identifying and Choosing a Bicycle Headset (S.H.I.S., 2010) | sí | primary |
| S24 | Sheldon Brown — Measurements for Spoke-Length Calculations; Wheelbuilding | sí | primary |
| S25 | SRAM/RockShox — Rear Shock Fitment Guide | sí | primary |
| S26 | Open Consumables — Xiaomi M365 (fuente comunitaria, no OEM) | sí | community_not_oem |
| S27 | Park Tool — Hydraulic Brake Bleed Kits BKD-1.2 (DOT) / BKM-1.2 (Mineral) — instrucciones | sí | primary |
| S28 | Park Tool — Thru Axle Taps TAP-12.1/12.2/15.1/15.2 | sí | primary |
| S29 | Sheldon Brown — Glossary R (Rotor = detangler/gyro BMX) | sí | primary |
| S30 | Park Tool — Determining Cassette / Freewheel Type; Cassette Removal and Installation | sí | index_only |

## 10. Gates y dudas para Codex

1. Proyección numérica SQL→string (decimales exactos) del borrador 180000: sigue siendo gate; el contrato asume que todo decimal viaja como cadena exacta.
2. Contrapartes: 119 de 140 interfaces tienen regla tipada; 19 son n/a (sin interfaz mecánica o proveedor de perfil) y 2 quedan sólo de forma (`tube.tube_valve_to_rim_depth`, `fastener.fastener_to_thread`). Codex decide la contraparte de esas dos.
3. Etiquetas `label_es` de definiciones nuevas son generadas (label_origin = generated) y se revisan en la migración de vocabulario.
4. Adición de opciones sobre definiciones existentes (p. ej. «Par» en wheel_position): sólo adición; ninguna opción existente se renombra ni se borra.
5. `piston_count` existente (lista 2/4/6) se conserva; `piston_count_value` entero nuevo lo sustituye por migración de opción a entero.
6. La regla «requerido» sigue siendo aviso no bloqueante en el validador actual; el contrato no la convierte en bloqueo.
7. Las condiciones «≠» se compilan como `in` sobre el complemento del subconjunto de la plantilla (la gramática v2 no tiene not_in): si Codex añade opciones, hay que recompilar.
8. `freehub_type` → interfaces nuevas: no hay mapa por opción; se resuelve por modelo de producto (diccionario pendiente por producto).
9. Contrapartes ausentes en el catálogo: tube.valve_length_mm_value necesita rim.rim_depth_mm (no existe en rim); workshop_tool.tool_interface necesita que cassette_lockring / bottom_bracket declaren interfaz de herramienta; fender_mount_kind y kickstand_mount_kind necesitan anclajes en frame (sólo existe rack_mounts). Se dejan como interfaces estructurales.
10. Proyecciones pendientes (regla `projection_pending`): entero→token (sprocket_count vs chain_speeds), housing_kind→cable_purpose, hub_interface compuesto, cage_mount→conteo de pernos, carrier_mount_kind→rack_mounts, nominal↔BSD. Mientras no exista la proyección, la regla queda en caution y nunca en incompatible.
11. Etiquetas sólo-etiqueta (`label_only_improvements_proposed`): pedal_thread, rotor_mount_type, spoke_gauge; y mount_standard «Adaptor Requerido» no es un estándar de montaje.
12. Nada de esto autoriza «catálogo listo»: el contrato define forma y reglas; el saneamiento se demuestra con fixtures por interfaz y read-back.

## 11. Cómo se produjo y cómo se revalida

- Generado por un compilador de sesión (scratchpad de Claude, no versionado) a partir del blueprint JSON, el snapshot de definiciones y las `validation_rules` vigentes en producción. Todas sus decisiones quedan dentro del JSON: `conflict_resolution` por definición, `phrase_compilation_table`, `legacy_value_maps`, `rules` por interfaz y `type_review`; el JSON es autosuficiente para reproducir o discutir cada decisión.
- `cc_validate.py` recorre el JSON emitido y exige: claves de condición exactas, campo presente en la plantilla, tokens dentro del vocabulario o del subconjunto, decimales como string, comparaciones sólo sobre decimal, reglas `incompatible` con fuente y sin proyección pendiente, URLs válidas, fixtures sin regla huérfana. Resultado de esta entrega: 0 errores.
- Los dos blueprint no se tocaron (hashes en §0).
