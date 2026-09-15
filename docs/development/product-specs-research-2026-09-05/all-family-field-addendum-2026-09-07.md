# Addendum de campos 2026-09-07 — herramientas, luces, soportes, ciclocomputadores, electrónica y alimentos

Resuelve la representabilidad pendiente de ND09, ND10, ND12, ND13, ND21, ND22 y ND23 como parches explícitos sobre `all-family-reviewed-fields-2026-09-06.json` (SHA-256 `7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa`, congelado). El JSON `all-family-field-addendum-2026-09-07.json` es la fuente: definiciones nuevas completas, parches con `before` copiado literal y `after`, condiciones en la gramática efectiva de `product_spec_template_rules.dart`, filas según `product_spec_rows.dart`, casos de representación validados y evidencia por corrección. No edita SQL, Dart, scripts, catálogos, producción, runtime ni git. Codex decide e integra.

Resumen: 82 parches ({"replace_definition_label": 3, "append_allowed_values": 5, "replace_field_contract": 24, "add_field": 50}), 48 definiciones nuevas (11 de filas), 20 casos de representación con 67 filas validadas, 9 de ellos sobre productos reales del inventario. Ninguna corrección activa una conclusión mecánica ni el fill.

## 1. Gramática respetada

- **field_condition**: product_spec_template_rules.dart: {kind: always|never|when, rows: [[{field, operator ∈ eq|in|lt|lte|gt|gte, value_type ∈ token|decimal|boolean, value}]]}; comparaciones sólo decimal; decimales como string exacta; no hay negación ni predicados sobre multi_select
- **rows**: product_spec_rows.dart: rows_schema {version:1, columns[{key,label,type ∈ text|token|decimal|integer|boolean|url, unit?, required?, allowed_values (sólo token), validation {positive,min,max}}], ordered_pairs (decimal/integer), unique_by}; fila {id, values, sources[url]}; fila ausente = desconocido; celda faltante = incompleto (aviso); rango invertido / tipo falso / posición repetida = bloqueo
- **definition**: formato del archivo congelado: {id, key, origin, label, data_type ∈ single_select|multi_select|number|boolean|text|json, unit, allowed_values, validation_rules, used_by}; los rows viven en validation_rules.rows_schema de una definición json

## 2. Evidencia

| Id | Fuente | Grado | Qué afirma |
|---|---|---|---|
| E-PT-THREAD | [Park Tool — Basic Thread Concepts](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts) | reference_general (Park Tool) | Una rosca se designa por diámetro mayor y paso (o TPI) y sentido; ejemplos M5 x 0.8, 9/16" x 20 TPI. · Tabla: M5 x 0.8 pernos de rotor y portacaramagiola; M6 x 1.0 cálipers; M8 x 0.75 pernos de plato; M8 x 1.0 pernos de biela; M8 x 1.25 tornillería de potencia; M10 x 1.0 patilla; 9/16" x 20 y 1/2" x 20 pedales; M15 x 1.0 pernos Octalink/ISIS. · Un mismo diámetro existe con varios pasos (M8: 0.75 / 1.0 / 1.25; M4: 0.7 / 0.75). · No define referencia de longitud (bajo cabeza / total). |
| E-PT-CT33 | [Park Tool — CT-3.3 Chain Tool](https://www.parktool.com/en-us/product/chain-tool-ct-3-3) | oem_page | Compatible con cadenas de 1 velocidad 1/8", 3/16" y half-link, y con todas las de 5 a 12 velocidades incl. SRAM T-Type, Flattop y Shimano XTR 12v. · «Will install and remove, but not peen, Campagnolo 11, 12 and 13-speed chain rivets». · Pin reemplazable CTP. |
| E-PT-IB3 | [Park Tool — IB-3 I-Beam Multi-Tool](https://www.parktool.com/en-us/product/i-beam-mini-fold-up-with-chain-tool-ib-3) | oem_page | Hex 1.5, 2, 2.5, 3, 4, 5, 6, 8 mm; T25; destornillador plano; llave fija 8 mm; llaves de rayos 3.23 (SW-0) y 3.45 (SW-2); desmontador; corta cadena 5–12v. · Corta cadena compatible con SRAM 12v Flattop y T-Type; instala y extrae pero no peena Campagnolo 11/12/13v. · Peso 170 g. |
| E-PT-CASSETTE | [Park Tool — Cassette Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/cassette-removal-and-installation) | reference_general (Park Tool) | FR-5.2 / 5.2G / 5.2GT / 5.2H: contratuercas Shimano, SRAM, Chris King, Sun Race, Hugi…; 12 estrías, ≈23,4 mm. · BBT-5 / FR-11: Campagnolo, 12 estrías ≈22,8 mm. HCW-17: contratuerca externa 2–8 muescas. · Cassettes SRAM XD: mismas FR-5.2 que Shimano HG (la extracción no es el spline de instalación). · Torque de instalación ≥ 40 Nm o el del fabricante. |
| E-PT-BBT9 | [Park Tool — BBT-9 Bottom Bracket and Lockring Tool](https://www.parktool.com/en-us/product/bottom-bracket-tool-bbt-9) | oem_page | 16 muescas, diámetro mayor 44–45 mm, menor 42,7 mm: copas roscadas externas Shimano, SRAM/Truvativ GXP, Campagnolo, Chris King, FSA MegaExo, Race Face X-type… · Sirve además las tapas de biela Hollowtech II de 8 puntas (TL-FC16/18), contratuercas de rotor de 16 muescas y contratuercas Bafang BBSHD/BBS02. |
| E-SUPERB-6616 | [Super B — TB-6616 Cotterless Crank Tool (página oficial)](https://www.superbiketool.com/en/product/detail/Bottom_Crank_tool/TB_6616) | oem_page | Sólo bielas de cuadradillo estándar («standard square type only»). · Se acciona con llave hexagonal de 8 mm o llave fija de 15 mm. · No imprime rosca del extractor ni peso. |
| E-SHIMANO-TLPD40 | [Shimano TL-PD40 (Y42A09000) — descripciones de distribuidores](https://www.universalcycles.com/shopping/product_details.php?id=28030) | retailer_summary (sin página OEM leída) | Herramienta plástica de 15 mm para la contratuerca del eje de pedales Shimano SPD-SL (y Garmin Vector según distribuidores); ≈20 g. · No se leyó el manual Shimano: no se afirma la lista exacta de pedales. |
| E-CATEYE | [Cateye — AMPP800 (HL-EL088RC) + ViZ300 (TL-LD810) combo](https://www.cateye.com/intl/products/headlights/HL-EL088RC_TL-LD810/) | oem_page | AMPP800: High 800 lm 1,5 h; Middle 400 lm 2 h; Low 200 lm 4 h; Daytime HyperConstant 800/200 lm 5 h; Flashing 200 lm 30 h. Li-ion 3,7 V 2500 mAh, Micro-USB 3–7 h, manubrio φ22,0–35,0 mm, IPX4. · ViZ300: Constant 30 lm 5 h; Flashing 30 lm 45 h; Group Ride 100→15 lm 8→10 h; Daytime Hyperflash 300 lm 10 h. Li-ion, USB 3 h (0,5 A), φ21,5–32,0 mm, soporte SP-15 de tija hasta 130 mm de perímetro, IPX4. · Incluye cable Micro-USB (AMPP800). |
| E-QUADLOCK | [Quad Lock — Out Front Mount / Out Front Mount PRO (páginas y soporte oficiales)](https://www.quadlockcase.com/products/out-front-mount) | oem_search_summary (la página de producto sólo devolvió navegación; el artículo de soporte dio 403) | Out Front Mount: 35 mm, 31,8 mm, 25,4 mm y 22 mm con espaciadores incluidos. · Out Front Mount PRO: 31,8 mm, 25,4 mm y 22 mm (no 35 mm). · El dispositivo se une por carcasa o adaptador universal Quad Lock; «22 mm» vs 22,2 mm se resuelve por variante/manual, no por tolerancia inventada. |
| E-GARMIN-540 | [Garmin — Edge 540 Owner’s Manual (Wireless Sensors; Specifications) y página de producto](https://www8.garmin.com/manuals/webhelp/GUID-17DE938E-466A-4746-BDBF-7A6FC1B3A32C/EN-US/GUID-62D44DE6-9C4D-4834-8267-8B23F891A9F3.html) | oem_page | Sensores por ANT+ o Bluetooth: eBike, Edge Remote, Extended Display, Heart Rate, inReach Remote, Lights, Power, Radar, Shifting, Shimano Di2, Smart Trainer, Speed/Cadence, Tempe, VIRB. · Especificaciones: batería Li-ion integrada; hasta 26 h; -20…60 °C; radio 2,4 GHz @ 19,5 dBm máx; IEC 60529 IPX7. · Página de producto: GNSS multibanda; Wi-Fi. |
| E-ANKER-A2667 | [Anker — 735 Charger (Nano II 65W) A2667, ficha de soporte](https://service.anker.com/product-description/a085g000004x2BVAAY?recordId=a085g000004x2BVAAY) | oem_page | Puertos USB-C 1, USB-C 2, USB-A. Solo: C1 65 W; C2 65 W; A 22,5 W. · C1+C2: 45 + 20 W; C1+A: 40 + 22,5 W; C2+A: 12 + 12 W; C1+C2+A: 40 + 12 + 12 W. Total 65 W. · PPS, PowerIQ 3.0/2.0, GaN II; entrada 100–240 V 1,8 A 50–60 Hz. No documenta A2668. |
| E-MAURTEN | [Maurten — Gel 100 Caf 100 (caja US de 12)](https://www.maurten.com/products/us/gel-100-caf-100-box-us) | oem_page | Caja de 12 sobres, 480 g; 40 g por sobre. · Por sobre: ≈100 kcal, 25 g de carbohidratos, 100 mg de cafeína. Azúcares y sodio no especificados en la página. · Ingredientes: agua, glucosa, fructosa, alginato de sodio, ácido glucónico, carbonato de calcio, cafeína. «Sin colorantes, conservantes ni saborizantes artificiales». La página no da declaración de alérgenos: no se infiere ausencia. |
| E-SHELDON-BARS | [Sheldon Brown — Handlebar and Stem Dimensions](https://www.sheldonbrown.com/cribsheet-handlebars.html) | reference_general (Sheldon) | La zona de abrazadera (25,4 / 26,0 / 31,8 / 35) y la zona del puño (22,2 / 23,8) son diámetros distintos del mismo manubrio. |
| E-ND-REVIEW | Dictamen independiente non-drivetrain-field-review-2026-09-06 | review | Hallazgos ND09, ND10, ND12, ND13, ND21, ND22, ND23 y escenarios. |
| E-INVENTARIO | Registro de revisión all-product-review-register-2026-09-06 (productos reales de las siete familias) | inventory | 41 herramientas, 22 fijaciones, 20 luces, 8 soportes, 1 ciclocomputador, 4 electrónica, 19 alimentos; ninguno tiene ficha (facts=0). |

## 3. Decisiones por hallazgo

### ND09 — Fijaciones y aguja de collarín

La rosca se representa como diámetro nominal (token `thread`, ahora rotulado así) + `thread_pitch_mm` o `thread_tpi` + `thread_hand`; el largo exige `length_datum` antes de escribirse; el accionamiento separa forma (`head_drive`) de medida (`head_drive_size_mm` / `torx_size`); la clase es declaración con fuente; un kit lleva filas `fastener_kit_members`. El paso nunca se completa desde el uso declarado ni desde la llave. `seat_clamp` recibe paso y largo con referencia para la aguja de repuesto.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND09-label-thread | (definición) | `thread` | replace_definition_label | «Rosca» → «Diámetro nominal de la rosca» | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | sólo etiqueta; el código y los valores no cambian |
| AD-ND09-def-thread | (definición) | `thread` | append_allowed_values | agrega: M3, M7, M9, M15, M18, M19, M20, M22, 5/16", 1/2", 9/16" | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND09-def-head_drive | (definición) | `head_drive` | append_allowed_values | agrega: Torx, Phillips, Plana, Cuadrado interior | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND09-fastener-thread | fastener | `thread` | replace_field_contract | allowed_when: always → (fastener_kind in ["Perno", "Tornillo", "Tuerca", "Otro"]); required_when: (fastener_kind in ["Perno", "Tornillo", "Tuerca", "Kit", "Otro"]) → (fastener_kind in ["Perno", "Tornillo", "Tuerca", "Otro"]) | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Un kit con pernos M5 y M6 no cabe en un token único. |
| AD-ND09-fastener-length_mm | fastener | `length_mm` | replace_field_contract | allowed_when: always → (fastener_kind in ["Perno", "Tornillo", "Otro"]); prerequisites: null → ["length_datum"] | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Un «M5x12» de etiqueta no dice si 12 es bajo cabeza o total. |
| AD-ND09-fastener-thread_pitch_mm | fastener | `thread_pitch_mm` | add_field | rol measurement/compatibility; allowed: (fastener_kind in ["Perno", "Tornillo", "Tuerca", "Otro"] ∧ thread in ["M3", "M4", "M5", "M6", "M7", "M8", "M9", "M10", "M12", "M14", "M15", "M18", "M19", "M20", "M22"]); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | M8×0.75 (plato) y M8×1.25 (potencia) comparten el token M8: sin paso no hay comparación posible (Park Tool: mismo diámetro, varios pasos). |
| AD-ND09-fastener-thread_tpi | fastener | `thread_tpi` | add_field | rol measurement/compatibility; allowed: (fastener_kind in ["Perno", "Tornillo", "Tuerca", "Otro"] ∧ thread in ["5/16\"", "3/8\"", "1/2\"", "9/16\""]); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | 3/8" x 24 y 3/8" x 26 son ejes distintos (tabla Park Tool). |
| AD-ND09-fastener-thread_hand | fastener | `thread_hand` | add_field | rol measurement/compatibility; allowed: (fastener_kind in ["Perno", "Tornillo", "Tuerca", "Otro"]); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Pedal izquierdo 9/16" x 20 es rosca izquierda: el nominal no lo dice. |
| AD-ND09-fastener-length_datum | fastener | `length_datum` | add_field | rol measurement/measurement; allowed: (fastener_kind in ["Perno", "Tornillo", "Otro"]); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Idem length_mm. |
| AD-ND09-fastener-head_drive_size_mm | fastener | `head_drive_size_mm` | add_field | rol measurement/intrinsic; allowed: (head_drive in ["Hexagonal interior (Allen)", "Hexagonal exterior"]); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Allen 5 vs Allen 6 en pernos de patilla. |
| AD-ND09-fastener-torx_size | fastener | `torx_size` | add_field | rol measurement/intrinsic; allowed: (head_drive in ["Torx", "Torx T25", "Torx T30"]); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Perno de rotor T25 del inventario. |
| AD-ND09-fastener-strength_class_claim | fastener | `strength_class_claim` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | No se deduce del material. |
| AD-ND09-fastener-fastener_kit_members | fastener | `fastener_kit_members` | add_field | rol contents/contents; allowed: (fastener_kind eq "Kit"); required: (fastener_kind eq "Kit") · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Kit de pernos de rotor (12×M5×0.8×10) + golillas. |
| AD-ND09-seat_clamp-clamp_thread_pitch_mm | seat_clamp | `clamp_thread_pitch_mm` | add_field | rol measurement/compatibility; allowed: (clamp_kind eq "Aguja / palanca de repuesto"); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | M5 y M6 no prueban largo ni paso ni fijación al modelo. |
| AD-ND09-seat_clamp-clamp_bolt_length_mm | seat_clamp | `clamp_bolt_length_mm` | add_field | rol measurement/compatibility; allowed: (clamp_kind eq "Aguja / palanca de repuesto"); required: never; prereq ['length_datum'] · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND09-seat_clamp-length_datum | seat_clamp | `length_datum` | add_field | rol measurement/measurement; allowed: (clamp_kind eq "Aguja / palanca de repuesto"); required: never · **definición nueva** | E-PT-THREAD, E-ND-REVIEW, E-INVENTARIO | Idem. |

### ND10 — Herramientas

Filas `tool_capabilities` por operación y estándar objetivo con `supported` explícito (true/false); fila ausente = desconocido; `speeds_min/max` sólo cuando el OEM los declara para esa operación; `tool_bits_included` para contenido. `chain_tool_speeds` pasa a declaración y se permite en multiherramientas. Se elimina la idea «extractor HG no sirve en XD»: la contratuerca (12 estrías 23,4 mm) es la interfaz de extracción, no el spline de instalación.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND10-def-tool_kind | (definición) | `tool_kind` | append_allowed_values | agrega: Llave de contratuerca (cassette / rotor), Extractor de cono de dirección, Extractor de obús, Guía de cableado interno, Guía de corte, Alicate / prensa, Regla / medidor, Juego de llaves Allen, Punta / bit, Cincel / otro manual | E-PT-CT33, E-PT-IB3, E-PT-CASSETTE | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND10-workshop_tool-chain_tool_speeds | workshop_tool | `chain_tool_speeds` | replace_field_contract | allowed_when: (tool_kind eq "Corta cadena") → (tool_kind in ["Corta cadena", "Multiherramienta"]); required_when: (tool_kind eq "Corta cadena") → (tool_kind eq "Corta cadena"); roles: "measurement" → "declaration"; semantic_roles: "compatibility" → "declaration" | E-PT-CT33, E-PT-IB3, E-PT-CASSETTE | IB-3 es multiherramienta con corta cadena 5–12v: antes no podía declararlo. |
| AD-ND10-workshop_tool-tool_interface | workshop_tool | `tool_interface` | replace_field_contract | roles: "measurement" → "declaration"; semantic_roles: "compatibility" → "declaration" | E-PT-CT33, E-PT-IB3, E-PT-CASSETTE | Un texto «HG» no rechaza el uso de FR-5.2 sobre XD. |
| AD-ND10-workshop_tool-tool_capabilities | workshop_tool | `tool_capabilities` | add_field | rol measurement/compatibility; allowed: always; required: never · **definición nueva** | E-PT-CT33, E-PT-IB3, E-PT-CASSETTE | CT-3.3: instala y extrae remaches Campagnolo 11/12/13 (supported=true) y NO los peena (supported=false); FR-5.2 sirve contratuercas XD y HG (12 estrías 23,4 mm) aunque el spline de instalación difiera. |
| AD-ND10-workshop_tool-tool_bits_included | workshop_tool | `tool_bits_included` | add_field | rol contents/contents; allowed: (tool_kind in ["Multiherramienta", "Juego de llaves Allen", "Llave de rayos", "Punta / bit", "Repuesto de herramienta"]); required: never · **definición nueva** | E-PT-CT33, E-PT-IB3, E-PT-CASSETTE | IB-3: hex 1.5–8, T25, 8 mm fija, rayos 3.23/3.45. |

### ND12 — Luces

Filas `light_member_configurations` (una por luz: posición, batería, conector, fijación, diámetro y perímetro propios) y `light_mode_configurations` (una por luz y modo: lúmenes y autonomía juntos; modo doble y rango de autonomía representables). Los escalares de luz única sólo aplican a posiciones simples; en un juego son las filas las requeridas. `runtime_claim_h` queda legado.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND12-def-power_source | (definición) | `power_source` | append_allowed_values | agrega: Recargable USB (batería extraíble), Alimentación externa (USB) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND12-light-lumens_claimed | light | `lumens_claimed` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-battery_capacity_mah | light | `battery_capacity_mah` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-charge_connector | light | `charge_connector` | replace_field_contract | allowed_when: (power_source eq "Recargable USB") → (light_position in ["Delantera", "Trasera", "Casco / otra"] ∧ power_source eq "Recargable USB") | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-mount_diameter_min_mm | light | `mount_diameter_min_mm` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-mount_diameter_max_mm | light | `mount_diameter_max_mm` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-ip_rating | light | `ip_rating` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-modes_count | light | `modes_count` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]) | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | Juego AMPP800 + ViZ300: 800 lm y 45 h pertenecen a luces y modos distintos; un máximo global los mezclaría. |
| AD-ND12-light-runtime_claim_h | light | `runtime_claim_h` | replace_field_contract | allowed_when: always → (light_position in ["Delantera", "Trasera", "Casco / otra"]); roles: "declaration" → "legacy"; semantic_roles: "declaration" → "legacy" | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | No presentar 800 lm durante 30 h. |
| AD-ND12-light-light_member_configurations | light | `light_member_configurations` | add_field | rol contents/compatibility; allowed: always; required: (light_position eq "Juego delantera + trasera") · **definición nueva** | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | ViZ300: φ21,5–32 mm y SP-15 hasta 130 mm de perímetro; el diámetro no describe la tija aero. |
| AD-ND12-light-light_mode_configurations | light | `light_mode_configurations` | add_field | rol declaration/declaration; allowed: always; required: (light_position eq "Juego delantera + trasera"); prereq ['spec_evidence_source'] · **definición nueva** | E-CATEYE, E-ND-REVIEW, E-INVENTARIO | AMPP800 Daytime HyperConstant 800/200 lm 5 h; ViZ300 Group Ride 100→15 lm 8→10 h. |

### ND13 — Soportes

Se separan `bike_attachment_kind` y `device_attachment_kind`/`device_system`. `bar_fit_representation` decide entre filas discretas `bar_clamp_configurations` (diámetro + cómo se logra + incluido) y el rango continuo sólo si el OEM lo declara. El ancho del dispositivo sólo aplica a pinzas. Un candidato entre dos medidas listadas no queda aprobado.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND13-accessory_mount-bike_attachment_kind | accessory_mount | `bike_attachment_kind` | add_field | rol primary/compatibility; allowed: (accessory_mount_kind eq "Soporte de teléfono"); required: (accessory_mount_kind eq "Soporte de teléfono") · **definición nueva** | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Base de tapa de potencia vs abrazadera de manubrio: distinta zona de montaje. |
| AD-ND13-accessory_mount-bar_fit_representation | accessory_mount | `bar_fit_representation` | add_field | rol primary/compatibility; allowed: (accessory_mount_kind eq "Soporte de teléfono" ∧ bike_attachment_kind in ["Abrazadera de manubrio", "Abrazadera de potencia / tija"]); required: (accessory_mount_kind eq "Soporte de teléfono" ∧ bike_attachment_kind in ["Abrazadera de manubrio", "Abrazadera de potencia / tija"]) · **definición nueva** | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Quad Lock enumera 22 / 25,4 / 31,8 / 35: un candidato de 30 mm no queda aprobado por caer en el intervalo. |
| AD-ND13-accessory_mount-bar_diameter_min_mm | accessory_mount | `bar_diameter_min_mm` | replace_field_contract | allowed_when: (accessory_mount_kind eq "Soporte de teléfono") → (accessory_mount_kind eq "Soporte de teléfono" ∧ bar_fit_representation eq "Rango continuo declarado por OEM") | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Idem. |
| AD-ND13-accessory_mount-bar_diameter_max_mm | accessory_mount | `bar_diameter_max_mm` | replace_field_contract | allowed_when: (accessory_mount_kind eq "Soporte de teléfono") → (accessory_mount_kind eq "Soporte de teléfono" ∧ bar_fit_representation eq "Rango continuo declarado por OEM") | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Idem. |
| AD-ND13-accessory_mount-bar_clamp_configurations | accessory_mount | `bar_clamp_configurations` | add_field | rol measurement/compatibility; allowed: (accessory_mount_kind eq "Soporte de teléfono" ∧ bar_fit_representation eq "Medidas discretas (filas)"); required: (accessory_mount_kind eq "Soporte de teléfono" ∧ bar_fit_representation eq "Medidas discretas (filas)") · **definición nueva** | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | OFM: 35 directo, 31,8/25,4/22 con espaciadores incluidos; PRO no admite 35. |
| AD-ND13-accessory_mount-device_attachment_kind | accessory_mount | `device_attachment_kind` | add_field | rol primary/compatibility; allowed: (accessory_mount_kind eq "Soporte de teléfono"); required: (accessory_mount_kind eq "Soporte de teléfono") · **definición nueva** | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Un sistema con carcasa propietaria no se define por ancho de teléfono. |
| AD-ND13-accessory_mount-device_system | accessory_mount | `device_system` | add_field | rol primary/identity; allowed: (accessory_mount_kind eq "Soporte de teléfono" ∧ device_attachment_kind in ["Carcasa propietaria", "Adaptador universal adhesivo"]); required: never · **definición nueva** | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Idem. |
| AD-ND13-accessory_mount-device_width_min_mm | accessory_mount | `device_width_min_mm` | replace_field_contract | allowed_when: (accessory_mount_kind eq "Soporte de teléfono") → (accessory_mount_kind eq "Soporte de teléfono" ∧ device_attachment_kind eq "Pinza / brazos ajustables") | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | GUB 55–100 mm es una pinza; Quad Lock no tiene ancho. |
| AD-ND13-accessory_mount-device_width_max_mm | accessory_mount | `device_width_max_mm` | replace_field_contract | allowed_when: (accessory_mount_kind eq "Soporte de teléfono") → (accessory_mount_kind eq "Soporte de teléfono" ∧ device_attachment_kind eq "Pinza / brazos ajustables") | E-QUADLOCK, E-SHELDON-BARS, E-ND-REVIEW | Idem. |

### ND21 — Ciclocomputadores

`connection` queda legado; ejes separados: `positioning_source`, `speed_source` (gobierna `wheel_setting`), enlaces `sensor_link_ant_plus/bluetooth/wired`, `phone_link`, filas `sensor_support_configurations` (tipo + transporte + modelos) y `computer_contents`. Compartir Bluetooth no aprueba un sensor.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND21-cycle_computer-connection | cycle_computer | `connection` | replace_field_contract | required_when: always → never; roles: "primary" → "legacy"; semantic_roles: "intrinsic" → "legacy" | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Un Edge 540 es GNSS y además ANT+ y Bluetooth: «GPS» no lo representa. |
| AD-ND21-cycle_computer-positioning_source | cycle_computer | `positioning_source` | add_field | rol primary/intrinsic; allowed: always; required: always · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Edge 540: GNSS multibanda; velocímetro con cable del inventario: sin posicionamiento. |
| AD-ND21-cycle_computer-speed_source | cycle_computer | `speed_source` | add_field | rol primary/intrinsic; allowed: always; required: always · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Con GNSS puro no hay circunferencia que ajustar. |
| AD-ND21-cycle_computer-sensor_link_ant_plus | cycle_computer | `sensor_link_ant_plus` | add_field | rol primary/compatibility; allowed: always; required: never · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Compartir Bluetooth no aprueba cualquier sensor: el tipo va en filas. |
| AD-ND21-cycle_computer-sensor_link_bluetooth | cycle_computer | `sensor_link_bluetooth` | add_field | rol primary/compatibility; allowed: always; required: never · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND21-cycle_computer-sensor_link_wired | cycle_computer | `sensor_link_wired` | add_field | rol primary/compatibility; allowed: always; required: never · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Velocímetro 11 funciones con cable. |
| AD-ND21-cycle_computer-phone_link | cycle_computer | `phone_link` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Edge 540: Bluetooth + Wi-Fi. |
| AD-ND21-cycle_computer-sensor_support_configurations | cycle_computer | `sensor_support_configurations` | add_field | rol measurement/compatibility; allowed: (sensor_link_ant_plus eq true) ∨ (sensor_link_bluetooth eq true) ∨ (sensor_link_wired eq true); required: never · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Radar y luces sólo por ANT+ en Garmin: no se aprueba por «tiene Bluetooth». |
| AD-ND21-cycle_computer-wheel_setting | cycle_computer | `wheel_setting` | replace_field_contract | allowed_when: always → (speed_source in ["Sensor de rueda (imán / cable)", "Sensor de rueda inalámbrico", "GNSS o sensor"]) | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Con GNSS puro el ajuste no aplica. |
| AD-ND21-cycle_computer-computer_contents | cycle_computer | `computer_contents` | add_field | rol contents/contents; allowed: always; required: never · **definición nueva** | E-GARMIN-540, E-ND-REVIEW, E-INVENTARIO | Soporte de cuarto de vuelta incluido vs sensor vendido aparte. |

### ND22 — Electrónica

Cargadores: filas `power_port_configurations` (puerto, forma, dirección, máximo solo, protocolos) y `power_budget_configurations` (una fila por combinación y puerto; varias filas forman la combinación); `rated_power_w` se rotula «total». Cables: `cable_power_capacity_w` y `cable_data_capability`. Tarjetas: `storage_capacity_label`, `card_format`, `speed_class_claim`; nada se deriva de GB.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND22-label-rated_power_w | (definición) | `rated_power_w` | replace_definition_label | «Potencia nominal» → «Potencia nominal total» | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | sólo etiqueta; el código y los valores no cambian |
| AD-ND22-consumer_electronics-connector_a | consumer_electronics | `connector_a` | replace_field_contract | allowed_when: (device_kind in ["Cable de datos/carga", "Cargador"]) → (device_kind eq "Cable de datos/carga") | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | Un cargador con dos USB-C y un USB-A no cabe en un conector único. |
| AD-ND22-consumer_electronics-power_port_configurations | consumer_electronics | `power_port_configurations` | add_field | rol primary/compatibility; allowed: (device_kind eq "Cargador"); required: (device_kind eq "Cargador") · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | A2667: C1 65 W, C2 65 W, A 22,5 W. |
| AD-ND22-consumer_electronics-power_budget_configurations | consumer_electronics | `power_budget_configurations` | add_field | rol declaration/declaration; allowed: (device_kind eq "Cargador"); required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | C1+C2 = 45 + 20 W, no 65 + 65. |
| AD-ND22-consumer_electronics-cable_power_capacity_w | consumer_electronics | `cable_power_capacity_w` | add_field | rol declaration/declaration; allowed: (device_kind eq "Cable de datos/carga"); required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | Cable «100 W» del inventario: declaración de etiqueta, no medida. |
| AD-ND22-consumer_electronics-cable_data_capability | consumer_electronics | `cable_data_capability` | add_field | rol primary/intrinsic; allowed: (device_kind eq "Cable de datos/carga"); required: never · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | Un USB-C 100 W puede ser sólo carga o USB 2.0. |
| AD-ND22-consumer_electronics-storage_capacity_label | consumer_electronics | `storage_capacity_label` | add_field | rol primary/identity; allowed: (device_kind eq "Tarjeta de memoria"); required: never · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | Etiqueta y unidad se conservan. |
| AD-ND22-consumer_electronics-card_format | consumer_electronics | `card_format` | add_field | rol primary/compatibility; allowed: (device_kind eq "Tarjeta de memoria"); required: never · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | SanDisk 128GB del inventario: SD o microSD, SDXC por capacidad sólo si la etiqueta lo dice. |
| AD-ND22-consumer_electronics-speed_class_claim | consumer_electronics | `speed_class_claim` | add_field | rol declaration/declaration; allowed: (device_kind eq "Tarjeta de memoria"); required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-ANKER-A2667, E-ND-REVIEW, E-INVENTARIO | No se deriva de GB. |

### ND23 — Alimentos

`preparation_kind` separa preparado y envasado; preparados conservan tamaño de venta, volumen, temperatura, `milk_in_recipe`, `milk_substitution_offered` y `recipe_reference`; envasados llevan masa/volumen neto, unidades, masa por unidad y filas `nutrition_facts` con base obligatoria. Ingredientes y alérgenos exigen `allergen_statement_source`; `allergens_declared_none` sólo con etiqueta o receta que lo declare. Se añade `spec_evidence_source` a la plantilla.

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND23-def-food_item_kind | (definición) | `food_item_kind` | append_allowed_values | agrega: Latte, Mokaccino, Chocolate / Milo, Lungo, Espresso doble, Bebida saborizada, Gel / barra energética, Envasado (otro) | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND23-label-serving_size | (definición) | `serving_size` | replace_definition_label | «Tamaño de porción» → «Tamaño de venta (preparado)» | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | sólo etiqueta; el código y los valores no cambian |
| AD-ND23-food_beverage-preparation_kind | food_beverage | `preparation_kind` | add_field | rol primary/intrinsic; allowed: always; required: always · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Latte Chico (receta) vs gel Maurten (etiqueta). |
| AD-ND23-food_beverage-spec_evidence_source | food_beverage | `spec_evidence_source` | add_field | rol declaration/evidence; allowed: always; required: never | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | allergen_note sin fuente no prueba nada. |
| AD-ND23-food_beverage-serving_size | food_beverage | `serving_size` | replace_field_contract | allowed_when: always → (preparation_kind eq "Preparado en barra"); required_when: always → (preparation_kind eq "Preparado en barra") | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Un gel no es Chico/Mediano. |
| AD-ND23-food_beverage-serving_volume_ml | food_beverage | `serving_volume_ml` | replace_field_contract | allowed_when: always → (preparation_kind eq "Preparado en barra") | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND23-food_beverage-temperature | food_beverage | `temperature` | replace_field_contract | allowed_when: always → (preparation_kind eq "Preparado en barra") | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND23-food_beverage-milk | food_beverage | `milk` | replace_field_contract | allowed_when: always → (preparation_kind eq "Preparado en barra"); roles: "primary" → "legacy"; semantic_roles: "intrinsic" → "legacy" | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | «Opcional» mezclaba receta con modificador de venta. |
| AD-ND23-food_beverage-allergen_note | food_beverage | `allergen_note` | replace_field_contract | prerequisites: null → ["allergen_statement_source"] | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Leche vegetal en el nombre no prueba «sin lácteos». |
| AD-ND23-food_beverage-milk_in_recipe | food_beverage | `milk_in_recipe` | add_field | rol primary/intrinsic; allowed: (preparation_kind eq "Preparado en barra"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND23-food_beverage-milk_substitution_offered | food_beverage | `milk_substitution_offered` | add_field | rol primary/intrinsic; allowed: (preparation_kind eq "Preparado en barra"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND23-food_beverage-recipe_reference | food_beverage | `recipe_reference` | add_field | rol declaration/evidence; allowed: (preparation_kind eq "Preparado en barra"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Sin receta registrada, ingredientes y alérgenos quedan pendientes. |
| AD-ND23-food_beverage-net_mass_g | food_beverage | `net_mass_g` | add_field | rol measurement/measurement; allowed: (preparation_kind eq "Envasado"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Caja Maurten 480 g ≠ sobre 40 g ≠ 25 g de carbohidratos. |
| AD-ND23-food_beverage-net_volume_ml | food_beverage | `net_volume_ml` | add_field | rol measurement/measurement; allowed: (preparation_kind eq "Envasado"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND23-food_beverage-units_per_pack | food_beverage | `units_per_pack` | add_field | rol contents/contents; allowed: (preparation_kind eq "Envasado"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Caja de 12. |
| AD-ND23-food_beverage-unit_mass_g | food_beverage | `unit_mass_g` | add_field | rol measurement/measurement; allowed: (preparation_kind eq "Envasado"); required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | 40 g por sobre. |
| AD-ND23-food_beverage-nutrition_facts | food_beverage | `nutrition_facts` | add_field | rol declaration/declaration; allowed: (preparation_kind eq "Envasado"); required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | 25 g de carbohidratos por sobre no es por 100 g. |
| AD-ND23-food_beverage-ingredients_text | food_beverage | `ingredients_text` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['allergen_statement_source'] · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |
| AD-ND23-food_beverage-allergen_statement_source | food_beverage | `allergen_statement_source` | add_field | rol declaration/evidence; allowed: always; required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Sin fuente no hay declaración. |
| AD-ND23-food_beverage-allergens_declared_none | food_beverage | `allergens_declared_none` | add_field | rol declaration/declaration; allowed: (allergen_statement_source in ["Etiqueta del envase", "Receta verificada del negocio"]); required: never; prereq ['allergen_statement_source'] · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Maurten no da declaración de alérgenos: queda sin marcar, no en false. |
| AD-ND23-food_beverage-caffeine_mg | food_beverage | `caffeine_mg` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['caffeine_basis', 'spec_evidence_source'] · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | 100 mg por sobre. |
| AD-ND23-food_beverage-caffeine_basis | food_beverage | `caffeine_basis` | add_field | rol declaration/declaration; allowed: always; required: never · **definición nueva** | E-MAURTEN, E-ND-REVIEW, E-INVENTARIO | Idem. |

## 4. Definiciones nuevas

| Clave | Tipo | Unidad | Opciones / columnas |
|---|---|---|---|
| `thread_pitch_mm` | number | mm | {"positive": true} |
| `thread_tpi` | number | tpi | {"positive": true, "integer": true} |
| `thread_hand` | single_select | — | Derecha, Izquierda, Desconocido / sin confirmar |
| `length_datum` | single_select | — | Bajo cabeza, Total, Longitud roscada, Desconocido / sin confirmar |
| `head_drive_size_mm` | number | mm | {"positive": true} |
| `torx_size` | number | — | {"positive": true, "integer": true} |
| `strength_class_claim` | text | — | {} |
| `fastener_kit_members` | json (filas) | — | member_role:text*, thread_nominal:token*, thread_pitch_mm:decimal, thread_tpi:integer, thread_hand:token, length_mm:decimal, length_datum:token, head_drive:text, quantity:integer*, source_url:url · unique [['member_role', 'length_mm']] |
| `clamp_thread_pitch_mm` | number | mm | {"positive": true} |
| `clamp_bolt_length_mm` | number | mm | {"positive": true} |
| `tool_capabilities` | json (filas) | — | member:text, operation:token*, target_standard:text*, supported:boolean*, interface_measure_mm:decimal, drive_size:text, speeds_min:integer, speeds_max:integer, brand_scope:text, adapter_required:boolean, adapter_model:text, source_url:url · ordered [['speeds_min', 'speeds_max']] · unique [['member', 'operation', 'target_standard']] |
| `tool_bits_included` | json (filas) | — | bit_kind:token*, size:text*, quantity:integer*, source_url:url · unique [['bit_kind', 'size']] |
| `light_member_configurations` | json (filas) | — | member_id:text*, position:token*, battery_kind:token, battery_capacity_mah:decimal, battery_voltage_v:decimal, charge_connector:token, mount_kind:token, mount_diameter_min_mm:decimal, mount_diameter_max_mm:decimal, mount_circumference_max_mm:decimal, ip_rating:text, source_url:url · ordered [['mount_diameter_min_mm', 'mount_diameter_max_mm']] · unique [['member_id']] |
| `light_mode_configurations` | json (filas) | — | member_id:text*, mode:text*, pattern:token, lumens:decimal, lumens_secondary:decimal, runtime_h:decimal, runtime_max_h:decimal, source_url:url · ordered [['runtime_h', 'runtime_max_h']] · unique [['member_id', 'mode']] |
| `bike_attachment_kind` | single_select | — | Abrazadera de manubrio, Abrazadera de potencia / tija, Base de tapa de potencia, Correa elástica / silicona, Adhesivo, Otro |
| `bar_fit_representation` | single_select | — | Medidas discretas (filas), Rango continuo declarado por OEM, Desconocido / sin confirmar |
| `bar_clamp_configurations` | json (filas) | — | nominal_diameter_mm:decimal*, fit_method:token*, spacer_or_variant:text, included:boolean, source_url:url · unique [['nominal_diameter_mm']] |
| `device_attachment_kind` | single_select | — | Pinza / brazos ajustables, Carcasa propietaria, Adaptador universal adhesivo, Bolsa / funda transparente, Otro |
| `device_system` | text | — | {} |
| `positioning_source` | single_select | — | GNSS multibanda, GNSS, Sin posicionamiento (sensor de rueda), Desconocido / sin confirmar |
| `speed_source` | single_select | — | Sensor de rueda (imán / cable), Sensor de rueda inalámbrico, GNSS, GNSS o sensor, Desconocido / sin confirmar |
| `sensor_link_ant_plus` | boolean | — | {} |
| `sensor_link_bluetooth` | boolean | — | {} |
| `sensor_link_wired` | boolean | — | {} |
| `phone_link` | single_select | — | Ninguno, Bluetooth, Bluetooth + Wi-Fi, Otro |
| `sensor_support_configurations` | json (filas) | — | sensor_type:token*, transport:token*, models_note:text, source_url:url · unique [['sensor_type', 'transport']] |
| `computer_contents` | json (filas) | — | item:text*, quantity:integer*, mount_interface:text, source_url:url · unique [['item']] |
| `power_port_configurations` | json (filas) | — | port_id:text*, connector:token*, direction:token*, max_power_w:decimal, protocols:text, source_url:url · unique [['port_id']] |
| `power_budget_configurations` | json (filas) | — | configuration:text*, port_id:text*, power_w:decimal*, source_url:url · unique [['configuration', 'port_id']] |
| `cable_power_capacity_w` | number | W | {"positive": true} |
| `cable_data_capability` | single_select | — | Sólo carga, USB 2.0, USB 3.x, USB4 / Thunderbolt, Desconocido / sin confirmar |
| `storage_capacity_label` | text | — | {} |
| `card_format` | single_select | — | SD, SDHC, SDXC, microSD, microSDHC, microSDXC, CF, Otro |
| `speed_class_claim` | text | — | {} |
| `preparation_kind` | single_select | — | Preparado en barra, Envasado, Desconocido / sin confirmar |
| `recipe_reference` | text | — | {} |
| `milk_substitution_offered` | boolean | — | {} |
| `net_mass_g` | number | g | {"positive": true} |
| `net_volume_ml` | number | ml | {"positive": true} |
| `units_per_pack` | number | unidades | {"positive": true, "integer": true} |
| `unit_mass_g` | number | g | {"positive": true} |
| `nutrition_facts` | json (filas) | — | nutrient:token*, amount:decimal*, basis:token*, source_url:url · unique [['nutrient', 'basis']] |
| `ingredients_text` | text | — | {} |
| `allergen_statement_source` | single_select | — | Etiqueta del envase, Receta verificada del negocio, Sin fuente |
| `allergens_declared_none` | boolean | — | {} |
| `caffeine_mg` | number | mg | {"positive": true} |
| `caffeine_basis` | single_select | — | Por unidad / sobre, Por 100 g, Por 100 ml, Por porción declarada, Por porción servida |
| `milk_in_recipe` | single_select | — | Sin leche, Leche de vaca, Vegetal, Según receta, Desconocido / sin confirmar |

## 5. Casos de representación

Cada caso se validó contra los esquemas de filas y las opciones; `expected_blocking` enumera las filas requeridas que faltan (aviso de incompleto, no contradicción). Los casos con producto del inventario no inventan valores que el título no declara.

| Caso | Plantilla | Producto real | Filas | Faltantes esperados | Nota |
|---|---|---|---|---|---|
| fastener_hassns_m8_chainring_bolt_pitch_unknown | fastener | Perno Corona HASSNS M8 8.5mm  NEGRO | 0 | — | Producto real «Perno Corona HASSNS M8 8.5mm»: el paso 0.75 que Park Tool asocia a pernos de plato NO se escribe desde el uso; queda pendiente hasta etiqueta/OEM. La referencia del largo es desconocida y se declara así. |
| fastener_rotor_bolt_t25_park_standard_scope | fastener | PERNO FRENO DISCO (ROTOR) PARA TORQ T25 ( MINIMO 20 PCS ) | 0 | — | M5 x 0.8 es el estándar de aplicación que Park Tool documenta para pernos de rotor; como dato del SKU sólo vale si la etiqueta/OEM del perno lo confirma (aquí se muestra el alcance, no una medición). |
| fastener_kit_rows_shape | fastener | — | 2 | — | Forma de un kit: dos miembros con rosca/largo/cantidad propios. Valores ilustrativos del estándar Park Tool; no es un SKU del inventario. |
| workshop_tool_park_ct_3_3 | workshop_tool | — | 3 | — | Escenario ND10: la cobertura 5–12v no aprueba peenar; la exclusión OEM se representa con supported=false, no con ausencia de fila. |
| workshop_tool_park_fr_5_2_lockring | workshop_tool | — | 3 | — | La interfaz de extracción (contratuerca) es distinta del spline de instalación del cuerpo: un extractor «HG» no se rechaza sobre XD. |
| workshop_tool_park_bbt_9 | workshop_tool | — | 3 | — | Un estándar de copas no equivale a todas las cajas: PF/BB30 no aparecen y quedan desconocidos. |
| workshop_tool_super_b_tb_6616 | workshop_tool | EXTRACTOR DE VOLANTE SUPER B TB-6616 FOR STANDARD SQUARE TYPE | 2 | — | Producto real del inventario; la página oficial no imprime la rosca del extractor (M22 x 1 no se afirma). |
| workshop_tool_park_ib_3_multitool | workshop_tool | — | 9 | — | Multiherramienta que sí registra velocidades de cadena (antes prohibido por allowed_when) y separa contenido de capacidad. |
| light_cateye_ampp800_viz300_kit | light | — | 11 | — | Escenario ND12: 800 lm y 30 h nunca comparten fila; el trasero conserva su propio montaje y perímetro. Los escalares de luz única no aplican (allowed_when). |
| light_inventory_ae_kit_pending | light | Juego de luces delantera + trasera AE | 0 | light_member_configurations, light_mode_configurations | Producto real sin OEM: las filas requeridas faltan → pendiente (aviso), no contradicción; nada se inventa desde el título. |
| accessory_mount_quad_lock_out_front | accessory_mount | — | 4 | — | Escenario ND13: 30 mm no tiene fila → desconocido, no aprobado. El ancho del teléfono no aplica (carcasa propietaria). Cuál medida es «directa» y cuál con espaciador no lo confirma la lectura: la columna fit_method de la fila 35 es hipótesis a confirmar. |
| accessory_mount_quad_lock_out_front_pro_no_35 | accessory_mount | — | 3 | — | La variante PRO no lista 35 mm: sin fila, un manubrio de 35 queda desconocido; no se hereda de la variante estándar. |
| accessory_mount_gub_clamp_range_from_title | accessory_mount | Soporte Teléfono GUB Aluminio Bicicleta 55-100mm Negro | 0 | — | Producto real: el título declara 55–100 mm de dispositivo (pinza); el lado bicicleta queda desconocido hasta leer el envase/OEM. |
| cycle_computer_garmin_edge_540 | cycle_computer | — | 12 | — | Escenario ND21: GNSS y sensores son ejes distintos. El manual dice «ANT+ or Bluetooth» por tipo sin detallar cuál transporte admite cada tipo: las filas por transporte de Radar/Luces/Cambio/eBike/Remoto se dejan sólo en ANT+ como lectura conservadora y se marcan pendientes de confirmar por tipo. |
| cycle_computer_wired_11_functions_inventory | cycle_computer | CICLOCOMPUTADOR BICICLETA VELOCIMETRO CON CABLE 11 FUNCIONES | 0 | — | Producto real: velocímetro con cable; el ajuste de rueda aplica (sensor de rueda) pero su método es desconocido hasta leer el manual. |
| consumer_electronics_anker_a2667_ports_and_budget | consumer_electronics | — | 12 | — | Escenario ND22: 65 W nunca aparece en dos puertos a la vez; cada combinación son varias filas con el mismo `configuration`. A2668 no hereda nada. |
| consumer_electronics_baseus_65w_model_unknown | consumer_electronics | Cargador 65W Baseus | 0 | power_port_configurations | Producto real «Cargador 65W Baseus» sin modelo identificado: los puertos requeridos faltan → pendiente; no se copian los de Anker. |
| consumer_electronics_baseus_cable_100w_label_claim | consumer_electronics | Baseus Cable Usb-c a Usb-c Carga Rapida 100w | 0 | — | Producto real: 100 W es la declaración del título/etiqueta (requiere spec_evidence_source); la capacidad de datos no se deduce. |
| food_maurten_gel_100_caf_100_packaged | food_beverage | — | 3 | — | Escenario ND23: caja (480 g) ≠ sobre (40 g) ≠ carbohidratos (25 g); allergens_declared_none NO se marca porque nadie lo declara. Los valores por 100 g no se transcribieron (la lectura los daba aproximados). No es un producto del inventario. |
| food_latte_chico_prepared_inventory | food_beverage | Latte Chico | 0 | — | Producto real del café: la receta no está registrada, así que ingredientes/alérgenos quedan sin declarar (allergen_statement_source = Sin fuente); «Leche de vaca» y la sustitución son supuestos de venta a confirmar con el negocio, no hechos. |

## 6. Lo que no se cambió

- No se retira ningún campo: thread, connection, milk, runtime_claim_h, tool_interface pasan a legacy/declaración y conservan lo escrito.
- No se inventan predicados sobre multi_select ni tipos fuera de text/token/decimal/integer/boolean/url.
- Las definiciones compartidas (thread, head_drive, power_source, tool_kind, food_item_kind, rated_power_w, serving_size) sólo reciben opciones o etiqueta; sus códigos vigentes no cambian.
- audible_signal y pump conservan sus usos de mount_diameter_* / max_pressure_psi sin cambio.

## 7. Pendientes sinceros

1. Fastener del inventario (22 SKU): ninguno trae paso ni referencia de largo en el título; el paso no se completa desde el uso (Park Tool documenta M8 x 0.75 / 1.0 / 1.25). Cada SKU exige etiqueta u OEM.
2. Herramientas del inventario (41): sólo TB-6616 tiene página OEM leída; TL-PD40 sólo por distribuidores (no se afirma la lista de pedales); los genéricos (corta cadena AE/RiderAce/Toopre «hasta 12 vel», Deemount 15 en 1, HF-06) no tienen OEM: sus filas quedan vacías, no inventadas.
3. Luces del inventario (20): ninguna con OEM leído (AE, Radical Mountain, Machfally, OffBondage HYY900); títulos como «1000LM» o «4000mAh» son declaraciones sin modo ni autonomía: sólo lumens_claimed/battery con spec_evidence_source si hay etiqueta.
4. Quad Lock: la página de producto devolvió sólo navegación y el artículo de soporte dio 403; las medidas vienen de resúmenes de búsqueda sobre páginas oficiales. Confirmar qué medida es directa y cuáles usan espaciador antes de fijar fit_method.
5. Garmin: «ANT+ or Bluetooth» por tipo de sensor sin matriz por transporte en la página leída; las filas de Radar/Luces/Cambio/eBike/Remoto/Rodillo sólo se dejaron en ANT+ y deben confirmarse por tipo.
6. Electrónica del inventario: Baseus 65 W y SD SanDisk 128 GB sin modelo identificado; el audífono «Réplica Air Pro 4» no es un producto OEM (queda descriptivo).
7. Alimentos preparados (19 SKU de café): no existe URL OEM; la evidencia es la receta del negocio (recipe_reference + allergen_statement_source = Receta verificada). Las filas exigen URL (isSpecRelationSourceUrl): para etiquetas fotografiadas o recetas internas hace falta decidir un transporte de evidencia sin URL (duda para Codex).
8. Etiquetas `label` de definiciones nuevas son propuestas; los `id` los asigna el compilador de Codex (UUID v5 como el resto).
9. Ninguna corrección activa una conclusión mecánica ni el fill: son representabilidad y evidencia.

## 8. Verificación y checkpoint

- SHA del congelado igual a 7ebf2b5b…
- toda plantilla/clave de replace existe; ninguna clave nueva colisiona con las 558 definiciones
- condiciones validadas con la gramática Dart: claves exactas, operadores, tipos, opciones dentro de allowed_values/allowed_options, campos presentes en la plantilla tras los parches
- rows_schema validados (tipos de columna, allowed_values sólo token, validation sólo numérica, ordered_pairs numéricos, unique_by existentes)
- filas de los casos validadas: id, tipos, requeridos, positivo/min/max, URL, rangos, unicidad
- prerrequisitos apuntan a campos presentes

| Archivo | SHA-256 | Estado |
|---|---|---|
| all-family-reviewed-fields-2026-09-06.json | `7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa` | congelado / entrada |
| non-drivetrain-field-review-2026-09-06.json | `298b46d4d91230d3884d0c40925262832d0d6342ae40ea39698fc807bbdbc1b9` | congelado / entrada |
| non-drivetrain-integration-status-2026-09-06.json | `82573feb2477c5eb8914c702b66bbb9e7992792bd163907080e83bbc3f1ebf6b` | congelado / entrada |
| global-audit-and-sanitation-2026-09-06.md | `161b857bbeec4e1b093c87773c27898e411b71161f1ba9508ef1f1b1473b324f` | congelado / entrada |
| all-product-review-register-2026-09-06.json | `88ef5edaf407d7883f791a858d651006eb8f6a0f64c676b9e56cfe5b85dd7965` | congelado / entrada |
| all-family-field-addendum-2026-09-07.json | `86c7f7d6b7360d01a771f1aaf63ddba0e63352999d65dc4ea78038da58d25440` | salida (esta entrega) |
| all-family-field-addendum-2026-09-07.md | (se calcula al escribir; ver checkpoint del chat) | salida |
