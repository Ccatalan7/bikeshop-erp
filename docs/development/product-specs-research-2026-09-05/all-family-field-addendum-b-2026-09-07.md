# Addendum B de campos 2026-09-07 — cockpit/contacto, portabultos, botellas, CO2, certificaciones, indumentaria, candados y conflictos entre fuentes

Cierra el delta pendiente de ND03, ND04, ND05, ND06, ND07, ND08, ND11, ND14, ND15, ND16, ND17, ND18, ND19, ND20 y ND24 tras C13–C18, como parches explícitos sobre la copia congelada `.tmp/product-spec-catalog/claude-fields-input-20260907.json` (SHA-256 `7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa`). El JSON `all-family-field-addendum-b-2026-09-07.json` es la fuente. No edita Dart, SQL, scripts, compilador, entregables anteriores, DB, runtime ni git. Codex decide e integra.

Resumen: 100 parches ({"replace_field_contract": 13, "add_field": 73, "replace_definition_label": 7, "append_row_columns": 2, "append_allowed_values": 4, "set_rows_ordered_pairs": 1}), 63 definiciones nuevas (7 de filas) más dos filas existentes extendidas, 26 casos de representación con 25 filas validadas, 11 sobre productos reales del inventario. Ninguna corrección activa una conclusión mecánica ni el fill; «compatible» sigue exigiendo extremos/interfaces del modelo y generación exactos.

## 1. Qué ya cubrían C13–C18 y qué se propone aquí

| Hallazgo | Cubierto | Delta de este addendum |
|---|---|---|
| ND03 | no integrado (status pending_integration) | estándar de rosca exacto + accionamiento; «Otro» restituido en pedal |
| ND04 | no integrado (status pending_integration) | largo por lado, diámetro nominal previsto, zona recta requerida, torque; interior medido pasa a opcional |
| ND05 | C14 separó ahead / quill / adaptador y quitó la abrazadera ficticia; aquí sólo se agrega inserción mínima de espiga y se rotula la abrazadera como zona superior | inserción mínima de espiga; abrazadera rotulada como zona superior |
| ND06 | C15 creó seatpost_saddle_configurations y saddle_rail_geometry; aquí se agregan pieza de abrazadera, incluida y fuente por fila | pieza de abrazadera, incluida y fuente por fila |
| ND07 | C15 aisló el shim; aquí van accionamiento/ruta/mando y las cotas de montaje OEM | accionamiento/ruta/mando y cotas OEM (inserción mín., mínimo expuesto, despeje inferior, documento) |
| ND08 | no integrado (status pending_integration) | construcción separada/integrada, referencia de ancho, hoods/drops/reach/drop, potencia integrada, guiado, conflictos |
| ND11 | C16 permitió medidas del U y del cable en el kit; aquí va la clasificación por componente/emisor y el diámetro del cable | clasificación por componente y emisor en filas; diámetro del cable |
| ND14 | no integrado (status pending_integration) | interfaz superior y anclajes de parrilla por fila; interfaz y generación del bolso; piezas auxiliares; miembros; conflictos |
| ND15 | no integrado (status pending_integration) | estándar KSA/placa, separación, pernos, rosca, altura instalada vs largo, peso máx., requisito de cuadro |
| ND16 | no integrado (status pending_integration) | sistema de retención botella/base, base incluida, ancho de tubo, insertos, lado de extracción |
| ND17 | no integrado (status pending_integration) | unión al cartucho, cartuchos por fila, presentación, alcance de presión; cabeza de válvula sólo en infladores |
| ND18 | C18 puso talla OEM y guía; aquí van certificaciones por fila, estado de etiqueta, construcción y público | certificaciones por fila, estado de etiqueta, construcción y público; protección también en rider_protection |
| ND19 | C17 creó eyewear_lens_configurations; aquí se agregan categoría, VLT y UV por lente | categoría, VLT y UV por lente |
| ND20 | C18 permitió manga en chaquetas; aquí van público, corte y composición | público, corte y composición en vestuario y guantes |
| ND24 | no integrado (status pending_integration) | filas conflicting_claims en manubrio y bolso; el escalar queda vacío |

## 2. Evidencia

| Id | Fuente | Grado | Qué afirma |
|---|---|---|---|
| E-SHELDON-PEDALS | [Sheldon Brown — Bicycle Pedals](https://www.sheldonbrown.com/pedals.html) | reference_general (Sheldon) | Roscas: 9/16" x 20 TPI (bielas de tres piezas), 1/2" x 20 TPI (biela de una pieza), 14 mm x 1,25 (francesas antiguas), 1" x 24 TPI (Shimano Dyna Drive). · El pedal izquierdo lleva rosca izquierda. · Un pedal francés empieza a roscar en 9/16 x 20 (y viceversa) pero se traba: no son intercambiables. |
| E-PT-PEDAL | [Park Tool — Pedal Installation and Removal](https://www.parktool.com/en-us/blog/repair-help/pedal-installation-and-removal) | reference_general (Park Tool) | Izquierdo rosca izquierda, derecho rosca derecha; muchos pedales marcan L/R. · Llave de pedal (15 mm) o hexágono 6/8 mm según modelo; machos TAP-6 (9/16 x 20) y TAP-3 (1/2 x 20). · Torque típico ≈ 360 in-lb. |
| E-ERGON-GP1 | [Ergon — GP1 Installation and User Instructions (PDF)](https://www.ergonbike.com/infocenter/downloads/manual_gp1.pdf) | oem_manual (texto extraído localmente del PDF) | Largo de zona recta necesaria: 128 mm Standard (largos); 128 / 93 mm Rohloff/Nexus (largo / corto); 93 mm Gripshift (cortos). · Tabla de largos: Standard 128 / 128 mm; Rohloff/Nexus 128 / 93 mm; Gripshift 93 / 93 mm. · «The handlebar must conform to the standard external diameter of 22.2 mm». · Torque de las abrazaderas 5 Nm; reapretar tras 50 km. |
| E-SHELDON-BARS | [Sheldon Brown — Handlebar and Stem Dimensions](https://www.sheldonbrown.com/cribsheet-handlebars.html) | reference_general (Sheldon) | Zona de abrazadera (25,4 / 26,0 / 31,8 / 35) y zona del puño (22,2 / 23,8) son diámetros distintos del mismo manubrio. |
| E-PT-STEM-AHEAD | [Park Tool — Threadless Stem Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/stem-removal-installation-threadless) | reference_general (Park Tool) | La potencia abraza el exterior del tubo de dirección; diámetros comunes 1", 1 1/8", 1 1/4", 1 1/2". · La potencia o los espaciadores quedan ≈3 mm sobre el tubo; con espiga de carbono va espaciador encima. Torque típico 4–6 Nm. · No trata espigas cónicas: el diámetro que importa es donde aprieta la potencia. |
| E-PT-STEM-QUILL | [Park Tool — Quill Stem Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/stem-removal-installation-quill-stems) | reference_general (Park Tool) | La espiga entra dentro del tubo y se fija con cuña o cono; diámetros de espiga comunes 22,2 / 25,4 / 28,6 mm. · Respetar la marca de inserción mínima / altura máxima grabada en la espiga. · Diámetros de manubrio comunes 22,2 / 25,4 / 26,0 / 31,8 / 35,0 mm. |
| E-RITCHEY-CLAMPSET | [Ritchey — WCS Carbon 1-Bolt Seatpost Saddle Rail Complete Clampset](https://ritcheylogic.com/bike/seatposts/wcs-carbon-1-bolt-seatpost-complete-clampset) | oem_page | Variantes 7x7 mm, 8x8.5 mm y 7x10 mm; «7x10 mm fits 7x9, 7x9.6, and 7x10 carbon rails». · Para tijas Superlogic y WCS Carbon 1-Bolt; aleación 2014 con perno inox. |
| E-REVERB-SPEC | [RockShox — Reverb AXS seatpost specifications GEN.0000000006250 Rev A (2020) (PDF)](https://www.sram.com/globalassets/document-hierarchy/frame-fit-specifications/rockshox/gen0000000006250-rev-a-reverb-axs-seatpost-specifications.pdf) | oem_manual (texto extraído localmente del PDF) | Travel 100 / 125 / 150 / 170 → largo total 340 / 390 / 440 / 480 mm; mínimo expuesto 165 / 190 / 215 / 235 mm. · Inserción mínima 80 mm; válvula de purga 23 mm que no debe tocar el cuadro: B (inserción máxima del cuadro) ≥ E (23) + 80. · Ajuste: A (altura de sillín desde tope del tubo) ≥ D (mínimo expuesto); A + 80 ≤ C (largo total) ≤ A + B − E. · Sólo esa edición y esos travels; no extrapolar a otra generación Reverb. |
| E-SHELDON-SEATPOST | [Sheldon Brown — Seatpost Size Database](https://www.sheldonbrown.com/seatpost-sizes.html) | reference_general (Sheldon) | Tamaños comunes 25,4 / 26,8 / 27,2 / 30,9 / 31,6; BMX 21,15–22,2; británico/italiano antiguo 28,6. · La base cita casos «con shim»; medir es más fiable que consultar la tabla. |
| E-ROVAL-RAPIDE | [Specialized — Roval Rapide Cockpit 218323](https://www.specialized.com/us/en/roval-rapide-cockpit/p/218323?color=352960-218323&searchText=21023-0647) | review_cited_not_read (403 en esta ronda) | Unidad integrada manubrio + potencia con anchos por posición; la página muestra −6/6 vs −10 grados y drop 127 vs 125 mm: contradicción no resuelta. |
| E-KRYPTONITE-002079 | [Kryptonite — Evolution Mini-7 with 4’ Flex Cable (002079)](https://www.kryptonitelock.com/en/products/product-information/current-key/002079.html?type=bicycle) | oem_page | U 3,25" x 7"; arco 13 mm; cable 4 ft; 3 llaves; soporte FlexFrame-U; 1,61 kg. · Nivel de seguridad 7 (escala Kryptonite); Sold Secure Gold; ART 4. · Cobertura antirrobo excluye el cable: la clasificación es del U. |
| E-TOPEAK-TRUNKBAG | [Topeak — MTX TrunkBag DXP (MTX 2.0) TT9635B2](https://www.topeak.com/global/en/product/1685-MTX-TRUNKBAG-DXP-%28MTX-2.0%29) | oem_page | 19,4 L; 36 x 25 x 21,5–29 cm; 1 185 g; poliéster 600D. · «Compatible with all MTX QuickTrack 2.0 racks with attachable side frames»; «MTX Dual Side Frames are required when using panniers on MTX BeamRacks». · Carga máxima limitada por la parrilla. |
| E-TOPEAK-TETRARACK | [Topeak — TetraRack M2 (TA2408M2)](https://www.topeak.com/global/en/product/1286-TETRARACK-M2-%28MTB%29) | oem_page | Montaje por correas hook-and-loop a los tirantes; sin ojales. Tirante > 15 mm de diámetro; ancho entre tirantes 95–125 mm; largo de montaje 200 mm. · Carga máx. 12 kg; 960 g; QuickTrack integrado; también KLICKfix / RackTime Snapit 1.0 o Vario. · No recomendado con tirantes/horquilla de carbono; incompatible con V-brake. |
| E-TOPEAK-2024 | [Topeak — 2024 new products preview (catálogo PDF)](https://www.topeak.com/storage/app/media/subsite/de/Download/2024_topeak_new_products_preview.pdf) | review_cited_not_read | TT9635B2 aparece con 22,6 L frente a 19,4 L de la página actual; causa no resuelta. |
| E-HEBIE-0669E | [Hebie — ABSTELLHELD 18 (0669 E)](https://www.hebie.de/ABSTELLHELD-18/0669-E) | oem_page | KSA 18 (separación de agujeros 18 mm), 2 pernos; ruedas 27,5"–29" (variante 24"–28"); peso máx. de bicicleta 25 kg. · Altura 340–390 mm (305–360 en la variante menor); ajuste sin herramientas 42 mm; «sólo para cuadros con el alojamiento correspondiente». |
| E-HEBIE-KSA40 | [Hebie — FIX 40 / ABSTELLHELD 40 (KSA 40)](https://www.hebie.de/ABSTELLHELD-40/0667-E) | oem_search_summary | KSA 40 = alojamiento en la vaina con separación de agujeros 40 mm; tornillos M6 x 16. KSA 18 y KSA 40 no son intercambiables. |
| E-FIDLOCK-UNIBASE | [Fidlock — TWIST uni base 09620-P00002(BLK)](https://www.fidlock.com/consumer/en/twist-uni-base/09620-p00002-blk) | oem_page | Para tubos de ancho 28–62 mm; se fija con dos bridas; «fits all TWIST modules»; 0,044 kg. |
| E-FIDLOCK-BOTTLE590 | [Fidlock — TWIST bottle 590 + uni base 09641-001032(TBL)](https://www.fidlock.com/consumer/en/twist-bottle-590-uni-base/09641-001032-tbl) | oem_search_summary (la página dio 404 en esta ronda) | 590 ml; incluye TWIST uni base; polietileno sin BPA, apto lavavajillas; 0,168 kg. |
| E-LEZYNE-CO2 | [Lezyne — 16G CO2 Cartridge 5 pack (1-C2-CRTDG-V116P5)](https://ride.lezyne.com/products/16g-co2-cartridge) | oem_page | Cartuchos roscados de 16 g de CO2; presentación de 5; también cajas de 30 y 250. · 87,9 x 21,8 x 21,8 mm; «para todos los infladores Lezyne CO2». La lectura dio «60 g» sin aclarar si es por cartucho o por pack: pendiente. |
| E-SMITH-MAINLINE | [Smith — Mainline Mips](https://www.smithoptics.com/en-gb/products/mainline-mips-r) | oem_page | Normas: U.S. CPSC (5+), CE EN 1078, NTA8776 E-Bike, ASTM F1952 Downhill. · Mips descrito como sistema de protección rotacional, aparte de las normas. · Tallas S 51–55, M 55–59, L 59–62 cm; in-mold, Koroyd, 21 ventilaciones; 770 g (M). |
| E-SMITH-EU-DOC | [Smith — EU Declaration of Conformity, bike helmets, 2024-09-09 (PDF)](https://www.smithoptics.com/on/demandware.static/-/Library-Sites-SmithSharedLibrary/default/pdfs/ProductConformityCerts/EU_Declaration_of_Conformity_-_Bike_Helmets_%2829-language%29_9-9-24.pdf) | review_cited_not_read (404 en esta ronda) | Cita EN 1078:2012+A1:2012 y enumera modelos; norma, edición, modelo y jurisdicción tienen alcance propio. |
| E-JULBO-REACTIV-24 | [Julbo — Photochromic 2-4 Polarized sunglasses (REACTIV 2-4 Polarized)](https://www.julbo.com/en_gb/sunglasses/photochromic-2-4-polarized-sunglasses) | oem_page | REACTIV 2-4 Polarized: fotocromática categoría 2 a 4 y polarizada (99 %) a la vez; 100 % UV; NTS. · La página no cita EN ISO 12312-1 ni VLT en %. |
| E-CASTELLI-PERFETTO | [Castelli — Perfetto RoS Long Sleeve 4519500-383](https://www.castelli-cycling.com/AU/en/Men/Cycling/Top/Jackets/Cold/PERFETTO-RoS-LONG-SLEEVE/p/4519500_383_52_S) | oem_page | Chaqueta de manga larga; tallas S, M, L, XL, XXL, 3XL; hombre; «tailored fit»; 374 g; 4–14 °C; GORE-TEX INFINIUM. · La página no publica composición ni tabla de medidas en la lectura. |
| E-ND-REVIEW | Dictamen independiente non-drivetrain-field-review-2026-09-06 | review | Hallazgos y escenarios ND03/04/05/06/07/08/11/14/15/16/17/18/19/20/24. |
| E-C13-C18 | Correcciones C13–C18 ya integradas en la copia congelada | frozen_input | C13 pedales (apoyos/calas); C14 potencia (ahead/quill/adaptador); C15 riel/kit y shim; C16 kit U + cable; C17 lentes por fila; C18 manga y talla OEM. |
| E-INVENTARIO | Registro de revisión all-product-review-register-2026-09-06 | inventory | 34 pedales, 28 puños, 14 manubrios, 16 potencias, 14 tijas, 22 sillines, 31 candados, 11 portabidones, 7 botellas, 5 canastos, 2 patas, 5 bolsos, 2 mochilas, 15 bombines, 13 cascos, 3 lentes, 4 prendas, 33 guantes, 1 protección; ninguno con ficha. |

## 3. Parches por hallazgo

### ND03 — estándar de rosca exacto + accionamiento; «Otro» restituido en pedal

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND03-pedal-pedal_thread | pedal | `pedal_thread` | replace_field_contract | allowed_options: ["9/16", "1/2", "Desconocido / sin confirmar"] → ["9/16", "1/2", "Otro", "Desconocido / sin confirmar"] | E-SHELDON-PEDALS, E-PT-PEDAL, E-ND-REVIEW | Pedal francés M14 x 1,25 confirmado no puede quedar como Desconocido ni como 9/16. |
| AD-ND03-pedal-pedal_thread_standard | pedal | `pedal_thread_standard` | add_field | rol measurement/compatibility; allowed: always; required: never · **definición nueva** | E-SHELDON-PEDALS, E-PT-PEDAL, E-ND-REVIEW | Un francés M14 x 1,25 empieza a roscar en 9/16 x 20 y se traba (Sheldon): no se aprueba por diámetro parecido. |
| AD-ND03-pedal-pedal_wrench_interface | pedal | `pedal_wrench_interface` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-SHELDON-PEDALS, E-PT-PEDAL, E-ND-REVIEW | Pedales sin planos de llave sólo admiten hexágono 8 mm (Park Tool). |

### ND04 — largo por lado, diámetro nominal previsto, zona recta requerida, torque; interior medido pasa a opcional

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND04-label-grip_inner_diameter_mm | (definición) | `grip_inner_diameter_mm` | replace_definition_label | «Diámetro interior del puño» → «Diámetro interior medido del puño» | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | sólo etiqueta; el código y los valores no cambian |
| AD-ND04-label-grip_length_mm | (definición) | `grip_length_mm` | replace_definition_label | «Largo del puño» → «Largo del puño (legado, un solo valor)» | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | sólo etiqueta; el código y los valores no cambian |
| AD-ND04-grip-grip_inner_diameter_mm | grip | `grip_inner_diameter_mm` | replace_field_contract | required_when: always → never; semantic_roles: "compatibility" → "measurement" | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | Ergon declara 22,2 mm de manubrio, no el interior del puño. |
| AD-ND04-grip-grip_length_mm | grip | `grip_length_mm` | replace_field_contract | roles: "measurement" → "legacy"; semantic_roles: "measurement" → "legacy" | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | GP1 Rohloff/Nexus 128 / 93 mm no cabe en un valor. |
| AD-ND04-grip-grip_bar_nominal_diameter_mm | grip | `grip_bar_nominal_diameter_mm` | add_field | rol measurement/compatibility; allowed: always; required: always · **definición nueva** | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | Comparar con la zona del puño del manubrio, no con la abrazadera central. |
| AD-ND04-grip-grip_length_left_mm | grip | `grip_length_left_mm` | add_field | rol measurement/measurement; allowed: (sold_as eq "Par"); required: never · **definición nueva** | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | GP1 Rohloff/Nexus: 128 (izq.) / 93 (der.). |
| AD-ND04-grip-grip_length_right_mm | grip | `grip_length_right_mm` | add_field | rol measurement/measurement; allowed: (sold_as eq "Par"); required: never · **definición nueva** | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | Idem. |
| AD-ND04-grip-grip_straight_length_required_mm | grip | `grip_straight_length_required_mm` | add_field | rol measurement/compatibility; allowed: always; required: never · **definición nueva** | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | GP1: 128 mm Standard, 128/93 Rohloff-Nexus, 93 Gripshift; con mando giratorio el lado corto aplica. |
| AD-ND04-grip-grip_clamp_torque_nm | grip | `grip_clamp_torque_nm` | add_field | rol declaration/declaration; allowed: (grip_attachment in ["Lock-on (una abrazadera)", "Lock-on (doble abrazadera)"]); required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-ERGON-GP1, E-SHELDON-BARS, E-ND-REVIEW | GP1: 5 Nm. |

### ND05 — inserción mínima de espiga; abrazadera rotulada como zona superior

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND05-label-stem_steerer_clamp_diameter_mm | (definición) | `stem_steerer_clamp_diameter_mm` | replace_definition_label | «Diámetro nominal de espiga admitido por la potencia ahead» → «Diámetro de abrazadera de dirección (zona superior de la espiga)» | E-PT-STEM-AHEAD, E-PT-STEM-QUILL, E-C13-C18 | sólo etiqueta; el código y los valores no cambian |
| AD-ND05-stem-quill_min_insertion_mm | stem | `quill_min_insertion_mm` | add_field | rol measurement/measurement; allowed: (stem_kind in ["Tee de espiga (quill)", "Adaptador quill → ahead"]); required: never · **definición nueva** | E-PT-STEM-AHEAD, E-PT-STEM-QUILL, E-C13-C18 | Park Tool: la marca debe quedar dentro del tubo; no existe un mínimo universal. |

### ND06 — pieza de abrazadera, incluida y fuente por fila

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND06-rows-seatpost_saddle_configurations | (definición) | `seatpost_saddle_configurations` | append_row_columns | columnas nuevas: clamp_part:text, clamp_included:boolean, source_url:url | E-RITCHEY-CLAMPSET, E-C13-C18, E-ND-REVIEW | Ritchey: el clampset 7x10 cubre 7x9, 7x9.6 y 7x10 sólo en Superlogic / WCS Carbon 1-Bolt; otra abrazadera sigue desconocida. |
| AD-ND06-label-saddle_mount_model | (definición) | `saddle_mount_model` | replace_definition_label | «Modelo exacto de anclaje de sillín» → «Sistema o modelo de anclaje del sillín (propietario)» | E-RITCHEY-CLAMPSET, E-C13-C18, E-ND-REVIEW | sólo etiqueta; el código y los valores no cambian |

### ND07 — accionamiento/ruta/mando y cotas OEM (inserción mín., mínimo expuesto, despeje inferior, documento)

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND07-seatpost-dropper_actuation | seatpost | `dropper_actuation` | replace_field_contract | roles: "primary" → "legacy"; semantic_roles: "intrinsic" → "legacy" | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Reverb AXS: electrónico inalámbrico, sin ruta de cable. |
| AD-ND07-seatpost-dropper_control_kind | seatpost | `dropper_control_kind` | add_field | rol primary/intrinsic; allowed: (seatpost_kind eq "Telescópica (dropper)"); required: (seatpost_kind eq "Telescópica (dropper)") · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Idem. |
| AD-ND07-seatpost-dropper_cable_routing | seatpost | `dropper_cable_routing` | add_field | rol primary/compatibility; allowed: (seatpost_kind eq "Telescópica (dropper)" ∧ dropper_control_kind in ["Mecánico por cable", "Hidráulico", "Otro"]); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Una tija stealth exige cuadro con guiado interno; eso es otra interfaz. |
| AD-ND07-seatpost-dropper_remote_included | seatpost | `dropper_remote_included` | add_field | rol contents/contents; allowed: (seatpost_kind eq "Telescópica (dropper)"); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Mando vendido aparte no se presume. |
| AD-ND07-seatpost-dropper_remote_model | seatpost | `dropper_remote_model` | add_field | rol contents/contents; allowed: (seatpost_kind eq "Telescópica (dropper)"); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Idem. |
| AD-ND07-seatpost-seatpost_min_insertion_mm | seatpost | `seatpost_min_insertion_mm` | add_field | rol measurement/compatibility; allowed: (seatpost_kind in ["Rígida", "Con suspensión", "Telescópica (dropper)", "Otro"]); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Reverb AXS Rev A: 80 mm; otra generación puede diferir. |
| AD-ND07-seatpost-seatpost_min_exposed_mm | seatpost | `seatpost_min_exposed_mm` | add_field | rol measurement/compatibility; allowed: (seatpost_kind eq "Telescópica (dropper)"); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Reverb AXS: 165 / 190 / 215 / 235 mm para 100 / 125 / 150 / 170. |
| AD-ND07-seatpost-seatpost_bottom_clearance_mm | seatpost | `seatpost_bottom_clearance_mm` | add_field | rol measurement/compatibility; allowed: (seatpost_kind in ["Rígida", "Con suspensión", "Telescópica (dropper)", "Otro"]); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | Reverb AXS: válvula de purga 23 mm que no debe tocar el cuadro. |
| AD-ND07-seatpost-seatpost_dimension_document | seatpost | `seatpost_dimension_document` | add_field | rol declaration/evidence; allowed: (seatpost_kind in ["Rígida", "Con suspensión", "Telescópica (dropper)", "Otro"]); required: never · **definición nueva** | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | GEN.0000000006250 Rev A (2020). |
| AD-ND07-label-seatpost_length_mm | (definición) | `seatpost_length_mm` | replace_definition_label | «Largo de la tija» → «Largo total de la tija» | E-REVERB-SPEC, E-SHELDON-SEATPOST, E-C13-C18 | sólo etiqueta; el código y los valores no cambian |

### ND08 — construcción separada/integrada, referencia de ancho, hoods/drops/reach/drop, potencia integrada, guiado, conflictos

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND08-handlebar-bar_construction | handlebar | `bar_construction` | add_field | rol primary/intrinsic; allowed: always; required: always · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Roval Rapide Cockpit es una unidad: no tiene abrazadera central. |
| AD-ND08-handlebar-bar_clamp_diameter_mm | handlebar | `bar_clamp_diameter_mm` | replace_field_contract | allowed_when: always → (bar_construction eq "Manubrio separado"); required_when: always → (bar_construction eq "Manubrio separado") | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Idem. |
| AD-ND08-handlebar-bar_width_mm | handlebar | `bar_width_mm` | replace_field_contract | prerequisites: null → ["bar_width_reference"] | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | 440 mm sin referencia no dice hoods ni drops ni extremos. |
| AD-ND08-handlebar-bar_width_reference | handlebar | `bar_width_reference` | add_field | rol measurement/measurement; allowed: always; required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Idem. |
| AD-ND08-handlebar-bar_width_hoods_mm | handlebar | `bar_width_hoods_mm` | add_field | rol measurement/measurement; allowed: (bar_style eq "Ruta (drop)"); required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Roval declara anchos por posición. |
| AD-ND08-handlebar-bar_width_drops_mm | handlebar | `bar_width_drops_mm` | add_field | rol measurement/measurement; allowed: (bar_style eq "Ruta (drop)"); required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Idem. |
| AD-ND08-handlebar-bar_reach_mm | handlebar | `bar_reach_mm` | add_field | rol measurement/measurement; allowed: (bar_style eq "Ruta (drop)"); required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Idem. |
| AD-ND08-handlebar-bar_drop_mm | handlebar | `bar_drop_mm` | add_field | rol measurement/measurement; allowed: (bar_style eq "Ruta (drop)"); required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Roval: 127 vs 125 mm en la misma página → conflicting_claims, no un valor. |
| AD-ND08-handlebar-integrated_stem_length_mm | handlebar | `integrated_stem_length_mm` | add_field | rol measurement/measurement; allowed: (bar_construction eq "Integrado manubrio + potencia"); required: (bar_construction eq "Integrado manubrio + potencia") · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Variantes largo x ancho son SKU distintos. |
| AD-ND08-handlebar-integrated_stem_angle_deg | handlebar | `integrated_stem_angle_deg` | add_field | rol measurement/measurement; allowed: (bar_construction eq "Integrado manubrio + potencia"); required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Roval: −6 vs −10 → conflicto registrado. |
| AD-ND08-handlebar-integrated_steerer_clamp_mm | handlebar | `integrated_steerer_clamp_mm` | add_field | rol measurement/compatibility; allowed: (bar_construction eq "Integrado manubrio + potencia"); required: (bar_construction eq "Integrado manubrio + potencia") · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Sin este dato la unidad no se compara con la horquilla. |
| AD-ND08-handlebar-cable_routing | handlebar | `cable_routing` | add_field | rol primary/compatibility; allowed: always; required: never · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Una unidad integrada con guiado interno exige dirección compatible: otra interfaz. |
| AD-ND08-handlebar-accessory_mount_ports_text | handlebar | `accessory_mount_ports_text` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | No inventar un montaje desde un dato web contradictorio. |
| AD-ND08-handlebar-conflicting_claims | handlebar | `conflicting_claims` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-ROVAL-RAPIDE, E-SHELDON-BARS, E-PT-STEM-QUILL | Roval −6/−10 y 127/125. |

### ND11 — clasificación por componente y emisor en filas; diámetro del cable

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND11-lock-security_rating_claim | lock | `security_rating_claim` | replace_field_contract | roles: "declaration" → "legacy"; semantic_roles: "declaration" → "legacy" | E-KRYPTONITE-002079, E-C13-C18, E-ND-REVIEW | Un «Sold Secure Gold» del U no cubre el cable (Kryptonite excluye el cable de su cobertura). |
| AD-ND11-lock-security_rating_configurations | lock | `security_rating_configurations` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-KRYPTONITE-002079, E-C13-C18, E-ND-REVIEW | Kryptonite 002079: U → nivel 7/10, Sold Secure Gold, ART 4; cable → sin clasificación. |
| AD-ND11-lock-cable_diameter_mm | lock | `cable_diameter_mm` | add_field | rol measurement/measurement; allowed: (lock_kind in ["Cable / espiral", "Kit U + cable"]); required: never | E-KRYPTONITE-002079, E-C13-C18, E-ND-REVIEW | OnGuard 180 cm x 12 mm del inventario: 12 es el cable, no el arco. |

### ND14 — interfaz superior y anclajes de parrilla por fila; interfaz y generación del bolso; piezas auxiliares; miembros; conflictos

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND14-def-carrier_mount_kind | (definición) | `carrier_mount_kind` | append_allowed_values | agrega: Correas a tirantes (sin ojales) | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND14-rack_basket-rack_top_interface | rack_basket | `rack_top_interface` | add_field | rol measurement/compatibility; allowed: (carrier_kind in ["Parrilla trasera", "Parrilla delantera"]); required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | TetraRack M2: QuickTrack + KLICKfix/RackTime Snapit; una parrilla sin interfaz no acepta un TrunkBag. |
| AD-ND14-rack_basket-rack_eyelets_required | rack_basket | `rack_eyelets_required` | add_field | rol measurement/compatibility; allowed: (carrier_kind in ["Parrilla trasera", "Parrilla delantera"]); required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | TetraRack M2 monta sin ojales: «sin ojales = incompatible» era falso. |
| AD-ND14-rack_basket-rack_mount_configurations | rack_basket | `rack_mount_configurations` | add_field | rol measurement/compatibility; allowed: (carrier_kind in ["Parrilla trasera", "Parrilla delantera"]); required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | TetraRack M2: tirantes > 15 mm, ancho 95–125 mm, no carbono, no V-brake. |
| AD-ND14-rack_basket-load_reference | rack_basket | `load_reference` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | 12 kg de TetraRack es parrilla completa; un TrunkBag limita por la parrilla. |
| AD-ND14-def-attachment | (definición) | `attachment` | append_allowed_values | agrega: Sistema de riel (QuickTrack / KLICKfix / RackTime) | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND14-bike_bag-bag_rack_interface | bike_bag | `bag_rack_interface` | add_field | rol measurement/compatibility; allowed: (attachment in ["Sistema de riel (QuickTrack / KLICKfix / RackTime)", "Riel"]); required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | TrunkBag DXP: MTX QuickTrack 2.0 con marcos laterales. |
| AD-ND14-bike_bag-bag_interface_generation | bike_bag | `bag_interface_generation` | add_field | rol measurement/compatibility; allowed: (attachment in ["Sistema de riel (QuickTrack / KLICKfix / RackTime)", "Riel"]); required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | QuickTrack 2.0 ≠ 1.0. |
| AD-ND14-bike_bag-auxiliary_part_requirements | bike_bag | `auxiliary_part_requirements` | add_field | rol contents/compatibility; allowed: always; required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | Alforjas desplegadas sobre BeamRack exigen MTX Dual Side Frames. |
| AD-ND14-bike_bag-bag_member_configurations | bike_bag | `bag_member_configurations` | add_field | rol contents/contents; allowed: always; required: never · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | Bolso con laterales desplegables. |
| AD-ND14-bike_bag-conflicting_claims | bike_bag | `conflicting_claims` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-TOPEAK-TRUNKBAG, E-TOPEAK-TETRARACK, E-ND-REVIEW | TT9635B2: 19,4 L (página) vs 22,6 L (catálogo 2024). |

### ND15 — estándar KSA/placa, separación, pernos, rosca, altura instalada vs largo, peso máx., requisito de cuadro

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND15-kickstand-kickstand_mount_standard | kickstand | `kickstand_mount_standard` | add_field | rol measurement/compatibility; allowed: always; required: always · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | Hebie 0669 E es KSA 18: un cuadro con separación 40 mm no lo acepta aunque la rueda esté en rango. |
| AD-ND15-kickstand-mount_hole_spacing_mm | kickstand | `mount_hole_spacing_mm` | add_field | rol measurement/compatibility; allowed: (kickstand_mount_standard in ["KSA 18 (separación 18 mm, 2 pernos)", "KSA 40 (separación 40 mm, 2 pernos)", "Otro"]); required: never · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | 18 vs 40 mm. |
| AD-ND15-kickstand-mount_bolt_count | kickstand | `mount_bolt_count` | add_field | rol measurement/compatibility; allowed: always; required: never · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | 2 pernos KSA; 1 perno placa central. |
| AD-ND15-kickstand-thread | kickstand | `thread` | add_field | rol measurement/compatibility; allowed: always; required: never | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | KSA 40: M6 x 16. |
| AD-ND15-kickstand-kickstand_length_reference | kickstand | `kickstand_length_reference` | add_field | rol measurement/measurement; allowed: always; required: never · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | «26–36 cm» del inventario no dice si es altura o largo. |
| AD-ND15-kickstand-installed_height_min_mm | kickstand | `installed_height_min_mm` | add_field | rol measurement/compatibility; allowed: always; required: never · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | Hebie: 340–390 mm. |
| AD-ND15-kickstand-installed_height_max_mm | kickstand | `installed_height_max_mm` | add_field | rol measurement/compatibility; allowed: always; required: never · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | Idem. |
| AD-ND15-kickstand-max_bike_weight_kg | kickstand | `max_bike_weight_kg` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | Hebie: 25 kg. |
| AD-ND15-kickstand-frame_requirement_text | kickstand | `frame_requirement_text` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | «Nur für Rahmen mit entsprechender Aufnahme am Hinterbau». |
| AD-ND15-kickstand-length_min_mm | kickstand | `length_min_mm` | replace_field_contract | prerequisites: null → ["kickstand_length_reference"] | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | Idem. |
| AD-ND15-kickstand-length_max_mm | kickstand | `length_max_mm` | replace_field_contract | prerequisites: null → ["kickstand_length_reference"] | E-HEBIE-0669E, E-HEBIE-KSA40, E-ND-REVIEW | Idem. |

### ND16 — sistema de retención botella/base, base incluida, ancho de tubo, insertos, lado de extracción

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND16-bottle-bottle_retention_system | bottle | `bottle_retention_system` | add_field | rol measurement/compatibility; allowed: always; required: always · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | TWIST 590 no se define por diámetro para un aro. |
| AD-ND16-bottle-bottle_diameter_mm | bottle | `bottle_diameter_mm` | replace_field_contract | allowed_when: always → (bottle_retention_system eq "Convencional (portabidón de aro)") | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Idem. |
| AD-ND16-bottle-base_included | bottle | `base_included` | add_field | rol contents/contents; allowed: (bottle_retention_system in ["FIDLOCK TWIST", "Otro propietario"]); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | TWIST bottle 590 + uni base incluye la base; la botella suelta (09642) no. |
| AD-ND16-bottle-included_base_model | bottle | `included_base_model` | add_field | rol contents/contents; allowed: (base_included eq true); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | TWIST uni base 09620. |
| AD-ND16-def-cage_mount | (definición) | `cage_mount` | append_allowed_values | agrega: Bridas (cable ties) al tubo | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND16-bottle_cage-cage_retention_system | bottle_cage | `cage_retention_system` | add_field | rol measurement/compatibility; allowed: always; required: always · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Uni base «fits all TWIST modules»: no acepta botella convencional. |
| AD-ND16-bottle_cage-bottle_diameter_mm | bottle_cage | `bottle_diameter_mm` | replace_field_contract | allowed_when: always → (cage_retention_system eq "Convencional (portabidón de aro)") | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Idem. |
| AD-ND16-bottle_cage-frame_tube_width_min_mm | bottle_cage | `frame_tube_width_min_mm` | add_field | rol measurement/compatibility; allowed: (cage_mount in ["Abrazadera al tubo", "Bridas (cable ties) al tubo"]); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Uni base: 28–62 mm de ancho. |
| AD-ND16-bottle_cage-frame_tube_width_max_mm | bottle_cage | `frame_tube_width_max_mm` | add_field | rol measurement/compatibility; allowed: (cage_mount in ["Abrazadera al tubo", "Bridas (cable ties) al tubo"]); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Idem. |
| AD-ND16-bottle_cage-boss_spacing_mm | bottle_cage | `boss_spacing_mm` | add_field | rol measurement/compatibility; allowed: (cage_mount eq "Dos tornillos del cuadro (estándar)"); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | El tipo de anclaje no equivale a la separación correcta. |
| AD-ND16-bottle_cage-boss_count | bottle_cage | `boss_count` | add_field | rol measurement/compatibility; allowed: (cage_mount eq "Dos tornillos del cuadro (estándar)"); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Idem. |
| AD-ND16-bottle_cage-side_entry_side | bottle_cage | `side_entry_side` | add_field | rol primary/intrinsic; allowed: (side_entry eq true); required: never · **definición nueva** | E-FIDLOCK-UNIBASE, E-FIDLOCK-BOTTLE590, E-ND-REVIEW | Izquierda vs derecha en cuadros pequeños. |

### ND17 — unión al cartucho, cartuchos por fila, presentación, alcance de presión; cabeza de válvula sólo en infladores

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND17-def-pump_kind | (definición) | `pump_kind` | append_allowed_values | agrega: Cartucho CO2 (recarga) | E-LEZYNE-CO2, E-ND-REVIEW, E-INVENTARIO | ninguna opción existente se renombra ni se borra; los códigos de opción vigentes no cambian |
| AD-ND17-pump-co2_cartridge_interface | pump | `co2_cartridge_interface` | add_field | rol measurement/compatibility; allowed: (pump_kind in ["Inflador CO2", "Cartucho CO2 (recarga)"]); required: (pump_kind in ["Inflador CO2", "Cartucho CO2 (recarga)"]) · **definición nueva** | E-LEZYNE-CO2, E-ND-REVIEW, E-INVENTARIO | Lezyne 16 g es roscado «para infladores Lezyne»; un cartucho no roscado no entra. |
| AD-ND17-pump-co2_cartridge_configurations | pump | `co2_cartridge_configurations` | add_field | rol measurement/compatibility; allowed: (pump_kind in ["Inflador CO2", "Cartucho CO2 (recarga)"]); required: never · **definición nueva** | E-LEZYNE-CO2, E-ND-REVIEW, E-INVENTARIO | 16 g de gas, peso físico y 5 unidades son datos distintos. |
| AD-ND17-pump-pack_quantity | pump | `pack_quantity` | add_field | rol contents/contents; allowed: (pump_kind eq "Cartucho CO2 (recarga)"); required: never | E-LEZYNE-CO2, E-ND-REVIEW, E-INVENTARIO | 5 pack / 30 / 250. |
| AD-ND17-pump-inflation_target_note | pump | `inflation_target_note` | add_field | rol declaration/declaration; allowed: (pump_kind in ["Inflador CO2", "Cartucho CO2 (recarga)", "De mano / mini", "De pie"]); required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-LEZYNE-CO2, E-ND-REVIEW, E-INVENTARIO | Lezyne: «road and low-volume gravel». |
| AD-ND17-pump-valve_heads_supported | pump | `valve_heads_supported` | replace_field_contract | allowed_when: always → (pump_kind in ["De pie", "De mano / mini", "Inflador CO2", "Bomba de suspensión", "Compresor / eléctrica", "Otro"]); required_when: always → (pump_kind in ["De pie", "De mano / mini", "Inflador CO2", "Bomba de suspensión", "Compresor / eléctrica", "Otro"]) | E-LEZYNE-CO2, E-ND-REVIEW, E-INVENTARIO | Cartucho de recarga sin cabeza de válvula. |

### ND18 — certificaciones por fila, estado de etiqueta, construcción y público; protección también en rider_protection

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND18-helmet-certification_claim | helmet | `certification_claim` | replace_field_contract | roles: "declaration" → "legacy"; semantic_roles: "declaration" → "legacy" | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | Smith Mainline: CPSC + EN 1078 + NTA 8776 + ASTM F1952 con mercado y edición propios. |
| AD-ND18-helmet-label_evidence_state | helmet | `label_evidence_state` | add_field | rol declaration/evidence; allowed: always; required: never · **definición nueva** | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | No seleccionar «Sin etiqueta visible» como norma ni dar por observada la etiqueta. |
| AD-ND18-helmet-certification_configurations | helmet | `certification_configurations` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | EN 1078:2012+A1:2012 (declaración UE 2024-09-09) ≠ «EN 1078» sin edición. |
| AD-ND18-helmet-helmet_construction | helmet | `helmet_construction` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | Integral no prueba ASTM F1952. |
| AD-ND18-helmet-intended_audience | helmet | `intended_audience` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | «Niño» en helmet_kind mezclaba usuario y construcción. |
| AD-ND18-rider_protection-certification_configurations | rider_protection | `certification_configurations` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | Un kit rodillera + codera puede certificar sólo una pieza. |
| AD-ND18-rider_protection-intended_audience | rider_protection | `intended_audience` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-SMITH-MAINLINE, E-SMITH-EU-DOC, E-C13-C18 | Idem. |

### ND19 — categoría, VLT y UV por lente

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND19-rows-eyewear_lens_configurations | (definición) | `eyewear_lens_configurations` | append_row_columns | columnas nuevas: category_min:integer, category_max:integer, vlt_min_pct:decimal, vlt_max_pct:decimal, uv_claim:text, source_url:url | E-JULBO-REACTIV-24, E-C13-C18, E-ND-REVIEW | REACTIV 2-4 Polarized: fotocromática 2→4 y polarizada, 100 % UV; sin VLT publicado → vacío, no inventado. |
| AD-ND19-rows-eyewear_lens_configurations-ordered | (definición) | `eyewear_lens_configurations` | set_rows_ordered_pairs | ordered_pairs: null → [["category_min", "category_max"], ["vlt_min_pct", "vlt_max_pct"]] | E-JULBO-REACTIV-24, E-C13-C18, E-ND-REVIEW | Categoría 4→2 invertida se bloquea. |

### ND20 — público, corte y composición en vestuario y guantes

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND20-rider_apparel-intended_audience | rider_apparel | `intended_audience` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | «Niño» en gender_fit mezclaba edad con corte. |
| AD-ND20-rider_apparel-fit_cut | rider_apparel | `fit_cut` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | Castelli Perfetto: «tailored fit». |
| AD-ND20-rider_apparel-fabric_composition_text | rider_apparel | `fabric_composition_text` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | La página Castelli no la publica: queda vacío. |
| AD-ND20-rider_glove-intended_audience | rider_glove | `intended_audience` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | «Niño» en gender_fit mezclaba edad con corte. |
| AD-ND20-rider_glove-fit_cut | rider_glove | `fit_cut` | add_field | rol primary/intrinsic; allowed: always; required: never · **definición nueva** | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | Castelli Perfetto: «tailored fit». |
| AD-ND20-rider_glove-fabric_composition_text | rider_glove | `fabric_composition_text` | add_field | rol declaration/declaration; allowed: always; required: never; prereq ['spec_evidence_source'] · **definición nueva** | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | La página Castelli no la publica: queda vacío. |
| AD-ND20-label-gender_fit | (definición) | `gender_fit` | replace_definition_label | «Corte declarado» → «Corte / género de la prenda» | E-CASTELLI-PERFETTO, E-C13-C18, E-ND-REVIEW | sólo etiqueta; el código y los valores no cambian |

### ND24 — filas conflicting_claims en manubrio y bolso; el escalar queda vacío

| Parche | Plantilla | Clave | Op | Cambio | Fuente | Caso contrario |
|---|---|---|---|---|---|---|
| AD-ND24-label-volume_l | (definición) | `volume_l` | replace_definition_label | «Capacidad» → «Capacidad declarada (vacía mientras exista un conflicto registrado)» | E-TOPEAK-TRUNKBAG, E-TOPEAK-2024, E-ROVAL-RAPIDE | sólo etiqueta; el código y los valores no cambian |

## 4. Definiciones nuevas

| Clave | Tipo | Unidad | Opciones / columnas |
|---|---|---|---|
| `pedal_thread_standard` | single_select | — | 9/16" x 20 TPI (bielas de tres piezas), 1/2" x 20 TPI (biela de una pieza), M14 x 1,25 (francés antiguo), 1" x 24 TPI (Shimano Dyna Drive), Otro, Desconocido / sin confirmar |
| `pedal_wrench_interface` | single_select | — | Llave de pedal 15 mm, Hexágono 6 mm, Hexágono 8 mm, Llave 15 mm y hexágono 8 mm, Otro, Desconocido / sin confirmar |
| `grip_length_left_mm` | number | mm | {"positive": true} |
| `grip_length_right_mm` | number | mm | {"positive": true} |
| `grip_bar_nominal_diameter_mm` | number | mm | {"positive": true} |
| `grip_straight_length_required_mm` | number | mm | {"positive": true} |
| `grip_clamp_torque_nm` | number | Nm | {"positive": true} |
| `quill_min_insertion_mm` | number | mm | {"positive": true} |
| `bar_construction` | single_select | — | Manubrio separado, Integrado manubrio + potencia, Desconocido / sin confirmar |
| `bar_width_reference` | single_select | — | Centro a centro en los extremos, Centro a centro en manetas (hoods), Centro a centro en drops, Exterior a exterior, Desconocido / sin confirmar |
| `bar_width_hoods_mm` | number | mm | {"positive": true} |
| `bar_width_drops_mm` | number | mm | {"positive": true} |
| `bar_reach_mm` | number | mm | {"positive": true} |
| `bar_drop_mm` | number | mm | {"positive": true} |
| `integrated_stem_length_mm` | number | mm | {"positive": true} |
| `integrated_stem_angle_deg` | number | ° | {} |
| `integrated_steerer_clamp_mm` | number | mm | {"positive": true} |
| `cable_routing` | single_select | — | Externa, Interna, Mixta, Desconocido / sin confirmar |
| `accessory_mount_ports_text` | text | — | {} |
| `dropper_control_kind` | single_select | — | Mecánico por cable, Hidráulico, Electrónico inalámbrico, Otro, Desconocido / sin confirmar |
| `dropper_cable_routing` | single_select | — | Interna (stealth), Externa, No aplica (inalámbrico), Desconocido / sin confirmar |
| `dropper_remote_included` | boolean | — | {} |
| `dropper_remote_model` | text | — | {} |
| `seatpost_min_insertion_mm` | number | mm | {"positive": true} |
| `seatpost_min_exposed_mm` | number | mm | {"positive": true} |
| `seatpost_bottom_clearance_mm` | number | mm | {"positive": true} |
| `seatpost_dimension_document` | text | — | {} |
| `security_rating_configurations` | json (filas) | — | component:token*, issuer:token*, level:text*, scope_note:text, source_url:url · unique [['component', 'issuer']] |
| `rack_top_interface` | single_select | — | MTX QuickTrack 2.0, MTX QuickTrack (1.0), KLICKfix / RackTime Snapit, Riel plano genérico, Sin interfaz superior, Otro, Desconocido / sin confirmar |
| `rack_eyelets_required` | boolean | — | {} |
| `rack_mount_configurations` | json (filas) | — | mount_point:token*, requirement:text, tube_diameter_min_mm:decimal, tube_diameter_max_mm:decimal, span_min_mm:decimal, span_max_mm:decimal, exclusions:text, source_url:url · ordered [['tube_diameter_min_mm', 'tube_diameter_max_mm'], ['span_min_mm', 'span_max_mm']] · unique [['mount_point']] |
| `load_reference` | single_select | — | Parrilla completa, Por alforja, Canasto, Plataforma superior, Desconocido / sin confirmar |
| `bag_rack_interface` | single_select | — | MTX QuickTrack 2.0, MTX QuickTrack (1.0), KLICKfix / RackTime Snapit, Riel plano genérico, Sin interfaz superior, Otro, Desconocido / sin confirmar |
| `bag_interface_generation` | text | — | {} |
| `auxiliary_part_requirements` | json (filas) | — | configuration:text*, part:text*, included:boolean, applies_to:text, source_url:url · unique [['configuration', 'part']] |
| `bag_member_configurations` | json (filas) | — | member:text*, position:token*, volume_l:decimal, width_mm:decimal, height_mm:decimal, depth_mm:decimal, source_url:url · unique [['member']] |
| `kickstand_mount_standard` | single_select | — | KSA 18 (separación 18 mm, 2 pernos), KSA 40 (separación 40 mm, 2 pernos), Placa central de un perno (M10), Abrazadera a vaina, Otro, Desconocido / sin confirmar |
| `mount_hole_spacing_mm` | number | mm | {"positive": true} |
| `mount_bolt_count` | number | — | {"positive": true, "integer": true} |
| `installed_height_min_mm` | number | mm | {"positive": true} |
| `installed_height_max_mm` | number | mm | {"positive": true} |
| `kickstand_length_reference` | single_select | — | Altura instalada (eje a suelo / según OEM), Largo de la pieza, Desconocido / sin confirmar |
| `max_bike_weight_kg` | number | kg | {"positive": true} |
| `frame_requirement_text` | text | — | {} |
| `bottle_retention_system` | single_select | — | Convencional (portabidón de aro), FIDLOCK TWIST, Otro propietario, Desconocido / sin confirmar |
| `base_included` | boolean | — | {} |
| `included_base_model` | text | — | {} |
| `cage_retention_system` | single_select | — | Convencional (portabidón de aro), FIDLOCK TWIST, Otro propietario, Desconocido / sin confirmar |
| `frame_tube_width_min_mm` | number | mm | {"positive": true} |
| `frame_tube_width_max_mm` | number | mm | {"positive": true} |
| `boss_spacing_mm` | number | mm | {"positive": true} |
| `boss_count` | number | — | {"positive": true, "integer": true} |
| `side_entry_side` | single_select | — | Izquierda, Derecha, Ambos, Desconocido / sin confirmar |
| `co2_cartridge_interface` | single_select | — | Roscado, No roscado, Ambos, Desconocido / sin confirmar |
| `co2_cartridge_configurations` | json (filas) | — | gas_mass_g:decimal*, threaded:boolean*, included_quantity:integer, gross_weight_g:decimal, source_url:url · unique [['gas_mass_g', 'threaded']] |
| `inflation_target_note` | text | — | {} |
| `certification_configurations` | json (filas) | — | standard:token*, standard_text:text, edition:text, market:text, scope_model:text, evidence_kind:token*, evidence_date:text, source_url:url · unique [['standard', 'market', 'evidence_kind']] |
| `label_evidence_state` | single_select | — | Etiqueta observada, Etiqueta no observada, Desconocido / sin confirmar |
| `helmet_construction` | single_select | — | In-mold, Hardshell (carcasa pegada), Integral (full face), Convertible (mentonera desmontable), Otro, Desconocido / sin confirmar |
| `intended_audience` | single_select | — | Adulto, Niño / juvenil, Desconocido / sin confirmar |
| `fit_cut` | single_select | — | Race / ajustado, Regular, Holgado, Desconocido / sin confirmar |
| `fabric_composition_text` | text | — | {} |
| `conflicting_claims` | json (filas) | — | field_key:text*, value:text*, unit:text, source_kind:token*, source_date:text, locator:text, measurement_context:text, source_url:url · unique [['field_key', 'value', 'source_kind']] |

## 5. Casos de representación

| Caso | Plantilla | Producto real | Filas | Faltantes esperados | Nota |
|---|---|---|---|---|---|
| pedal_french_m14_vs_9_16_not_equivalent | pedal | — | 0 | — | Escenario ND03: el francés se registra como estándar exacto (no Desconocido); frente a una biela 9/16 x 20 no es equivalente aunque empiece a roscar. Ejemplo sintético de forma, no SKU del inventario. |
| pedal_inventory_best_kp198_alias_unconfirmed | pedal | PEDAL BEST (PAR) KP-198 NEGRO EJE 9/16" CAJA | 0 | — | Producto real: el título dice 9/16; el paso x 20 TPI no se completa hasta que etiqueta u OEM lo confirme (alias legacy sin traducir). |
| grip_ergon_gp1_rohloff_nexus_asymmetric_pair | grip | — | 0 | — | Escenario ND04: 128/93 se conservan como el par vendido; la zona recta requerida se declara por el lado mayor y cada lado se evalúa con su mando. grip_inner_diameter_mm queda sin medir. |
| grip_inventory_ozono_132_22_ambiguous | grip | PUÑOS OZONO NEGROS 132mm 22mm | 0 | — | Producto real «132mm 22mm»: 132 va al legado (un solo largo); «22mm» no dice si es diámetro nominal del manubrio o interior del puño → grip_bar_nominal_diameter_mm queda pendiente. |
| stem_ahead_28_6_vs_tapered_fork_top | stem | Tee Alum Eclipse 31.8MM x 45MM Black AS-263 | 0 | — | Escenario ND05: la potencia declara sólo su abrazadera (28,6); contra una horquilla cónica 28,6→38,1 se compara el extremo superior. La horquilla necesita un campo de diámetro superior (fuera de este alcance): hasta entonces la interfaz es desconocida, no incompatible. Ejemplo con medidas del inventario (Eclipse 31,8 x |
| seatpost_ritchey_wcs_1bolt_clampset_7x10 | seatpost | — | 5 | — | Escenario ND06: la cobertura 7x9/7x9.6/7x10 pertenece al clampset 7x10 (kit opcional, no incluido) y sólo a Superlogic / WCS Carbon 1-Bolt; cuál kit trae de fábrica el SKU no se leyó → «De fábrica» no se declara. |
| seatpost_reverb_axs_150_rev_a_dimensions | seatpost | — | 0 | — | Escenario ND07: diámetro y carrera no bastan; con A (altura de sillín) y B (inserción máxima del cuadro) desconocidos, el ajuste queda desconocido. El diámetro 31,6 es un ejemplo: la ficha Rev A no fija el diámetro de cada SKU en la lectura. |
| seatpost_inventory_zoom_27_2_rigid | seatpost | TUBO SILLIN ZOOM SP-C255(ISO-M) 27.2X400 BED/BED/LABK | 0 | seatpost_saddle_configurations | Producto real: 27,2 x 400 del título; la geometría de riel que acepta la abrazadera no está en el título → filas requeridas faltantes (pendiente), no se presume 7 mm. |
| handlebar_roval_rapide_integrated_with_conflicts | handlebar | — | 4 | integrated_stem_length_mm, integrated_steerer_clamp_mm, bar_width_mm | Escenario ND08/ND24: unidad integrada sin abrazadera central; ángulo y drop quedan vacíos con el conflicto registrado (página citada por el dictamen; dio 403 en esta ronda). Largo, abrazadera de dirección y ancho requeridos faltan → pendiente. |
| handlebar_inventory_ruta_440_25_4 | handlebar | MANUBRIO RUTA AL. 440mm. 25.4 DR-AL-48B/E NEGRO | 0 | — | Producto real: 440 mm sin referencia de medición → bar_width_reference desconocido y así se declara. |
| lock_kryptonite_002079_kit_ratings_by_component | lock | — | 3 | — | Escenario ND11: el kit registra U (3,25" x 7" → 82,55 x 177,8 mm; 13 mm) y cable (4 ft → 1219 mm) en la misma presentación; la clasificación es del U y no se transfiere al cable (sin fila = desconocido para el cable). Conversiones de pulgadas propias, no del OEM. |
| lock_inventory_onguard_coil_180x12 | lock | Candado OnGuard Llave Espiral NS Coil 180cmX12mm Naranjo | 0 | — | Producto real: 180 cm x 12 mm son largo y diámetro del cable; sin clasificación de seguridad declarada. |
| rack_topeak_tetrarack_m2_no_eyelets | rack_basket | — | 1 | — | Escenario ND14: sin ojales no bloquea; la generación exacta del QuickTrack del TetraRack no se leyó («Integrated QuickTrack system»): se deja 1.0 como hipótesis a confirmar, y KLICKfix/Snapit se anota en requisito. |
| bike_bag_topeak_trunkbag_dxp_side_frames_and_conflict | bike_bag | — | 5 | — | Escenario ND14/ND24: volume_l queda vacío con dos afirmaciones registradas; las alforjas sobre BeamRack conservan el requisito de Dual Side Frames. La altura 21,5–29 cm (expandible) no cabe en un decimal y no se fuerza. |
| kickstand_hebie_0669e_ksa18_vs_40mm_frame | kickstand | — | 0 | — | Escenario ND15: un cuadro con separación 40 mm (KSA 40) no acepta el montaje directo aunque la rueda esté en rango; una adaptación requeriría evidencia propia. |
| kickstand_inventory_clamp_26_36cm_reference_unknown | kickstand | PATA DE APOYO DE ABRAZADERA AJUSTABLE 26cm-36cm | 0 | — | Producto real: 26–36 cm sin saber si es altura instalada o largo de pieza; se declara la referencia como desconocida. |
| bottle_fidlock_twist_590_with_uni_base | bottle | — | 0 | — | Escenario ND16: la botella no lleva diámetro (no aplica a TWIST) y registra la base incluida. Datos de la botella por resumen de búsqueda (la página dio 404). |
| bottle_cage_fidlock_uni_base_tube_width | bottle_cage | — | 0 | — | 28–62 mm es ancho de tubo, no diámetro; «fits all TWIST modules» no incluye botellas convencionales. |
| bottle_inventory_ztto_750_retention_unknown | bottle | Botella 750ml ZTTO Blanca/Transparente | 0 | — | Producto real: el título no identifica el sistema de retención; no se presume aro convencional. |
| pump_lezyne_16g_co2_5pack | pump | — | 1 | — | Escenario ND17: 16 g de gas, 5 unidades y peso físico separados; el peso físico («60 g») no se transcribe porque la lectura no aclara si es por cartucho o por pack. valve_heads_supported no aplica a un cartucho. |
| helmet_smith_mainline_certifications_by_row | helmet | — | 4 | — | Escenario ND18: normas con mercado y evidencia por fila; Mips es declaración aparte; etiqueta no observada; la edición EN 1078 viene del documento citado por el dictamen (404 en esta ronda), por eso se anota como tal. |
| helmet_inventory_best_enduro_certificado_sin_norma | helmet | CASCO BEST ENDURO NEGRO MATTE TALLA L CERTIFICADO EN CAJA | 0 | — | Producto real «Certificado en caja»: sin norma nombrada ni etiqueta observada → ninguna fila de certificación; no se infiere EN 1078 ni CPSC. |
| eyewear_julbo_reactiv_2_4_polarized | eyewear | — | 1 | — | Escenario ND19: fotocromía y polarización coexisten en la misma fila con categoría 2→4; VLT no publicado → vacío. |
| eyewear_inventory_scvcn_photochromic_unknown_category | eyewear | Lentes SCVCN Fotocromáticos DZ-S62-PH-08 | 1 | — | Producto real: sólo se sabe fotocromático por el título; categoría, polarización y UV quedan sin declarar. La URL de la fila es un marcador de forma (no existe página OEM leída): reemplazar antes de guardar. |
| apparel_castelli_perfetto_ros_ls_jacket | rider_apparel | — | 0 | — | Escenario ND20: chaqueta con manga larga (ya permitido por C18); «tailored fit» se registra como corte ajustado; composición no publicada → vacío. |
| apparel_inventory_polera_wtb_xl | rider_apparel | Polera Wtb Wilderness Negra Xl | 0 | — | Producto real: talla OEM exacta «XL» sin sistema ni guía; público desconocido. |

## 6. Lo que no se cambió

- No se retira ningún campo: pedal_thread, grip_length_mm, grip_inner_diameter_mm, dropper_actuation, security_rating_claim, certification_claim y gender_fit se conservan (algunos como legado).
- Los vocabularios compartidos (pedal_thread, carrier_mount_kind, attachment, cage_mount, pump_kind, thread) sólo reciben opciones o etiqueta; no se renombra ni borra ninguna opción.
- kit_members, saddle y rider_bag no cambian.
- No se propone ninguna regla de interfaz «compatible»: cada campo nuevo describe extremos/interfaces del propio producto; comparar sigue exigiendo modelo/generación y la contraparte real.

## 7. Pendientes sinceros

1. Horquilla: ND05 exige que la horquilla declare el diámetro superior de la espiga (no sólo el perfil cónico); ese template lo cubre el revisor de dirección; hasta entonces stem ↔ fork queda desconocido.
2. Ergon GP1 y Reverb AXS Rev A se leyeron extrayendo el texto del PDF con PDFKit local; Roval Rapide (403), declaración UE de Smith (404) y catálogo Topeak 2024 no se leyeron: se citan por el dictamen y así se graduaron.
3. Fidlock TWIST 590: la página de producto dio 404; volumen, base incluida, material y peso vienen de resúmenes de búsqueda sobre fidlock.com.
4. TetraRack M2: la generación exacta del QuickTrack integrado no se leyó; el caso la deja como hipótesis.
5. Lezyne 16 g: «60 g» de peso físico sin saber si es por cartucho o por pack: no se transcribe.
6. Inventario: pedales (34), puños (28), manubrios (14), potencias (16), tijas (14), candados (31), cascos (13), guantes (33) no tienen OEM leído; los casos con producto real sólo llevan lo que el título declara y marcan lo demás desconocido.
7. Las filas exigen URL por fila (isSpecRelationSourceUrl): el caso SCVCN usa un marcador de forma; fotos/etiquetas sin URL siguen siendo pendiente de arquitectura de Codex.
8. Certificaciones de casco: la vocabulario HELMET_STD es abierto con «Otra» + texto; no se afirma que las normas listadas cubran todos los mercados ni se deduce ASTM por construcción integral.
9. Ninguna corrección activa conclusiones mecánicas ni fill; las conversiones pulgada→mm del caso Kryptonite son propias, no del OEM.

## 8. Verificación y checkpoint

- SHA de la copia congelada = 7ebf2b5b…
- toda plantilla/clave de replace existe; ninguna clave nueva colisiona con las 558 definiciones ni con las 48 del addendum A
- condiciones validadas con la gramática Dart (claves, operadores, tipos, opciones dentro de allowed_values/allowed_options, campos presentes tras los parches)
- rows_schema nuevos y extendidos validados (tipos, allowed_values sólo token, validation numérica, ordered_pairs numéricos, unique_by existentes)
- filas de los casos validadas (id, tipos, requeridos, dominio, URL, rangos, unicidad)
- prerrequisitos apuntan a campos presentes

| Archivo | SHA-256 | Estado |
|---|---|---|
| claude-fields-input-20260907.json (copia congelada) | `7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa` | entrada congelada / referencia |
| non-drivetrain-field-review-2026-09-06.json | `298b46d4d91230d3884d0c40925262832d0d6342ae40ea39698fc807bbdbc1b9` | entrada congelada / referencia |
| non-drivetrain-integration-status-2026-09-06.json | `82573feb2477c5eb8914c702b66bbb9e7992792bd163907080e83bbc3f1ebf6b` | entrada congelada / referencia |
| all-product-review-register-2026-09-06.json | `88ef5edaf407d7883f791a858d651006eb8f6a0f64c676b9e56cfe5b85dd7965` | entrada congelada / referencia |
| all-family-field-addendum-2026-09-07.json (referencia, no duplicar) | `86c7f7d6b7360d01a771f1aaf63ddba0e63352999d65dc4ea78038da58d25440` | entrada congelada / referencia |
| all-family-field-addendum-b-2026-09-07.json | `b43aa4798dab2be7029660efb08dd3836ecfb350ccfb80b97549f53bf7b56b8d` | salida (esta entrega) |
| all-family-field-addendum-b-2026-09-07.md | ver checkpoint del chat | salida |
