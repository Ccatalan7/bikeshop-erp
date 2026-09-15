# Los 742 sin plantilla y el vínculo explícito producto → ficha — revisión de Claude, 2026-09-06

Autor: Claude (Fable 5.1, modo Code, Ultracode). Encargo relevado por Codex:
revisar de forma independiente sus 742 registros
(`unmapped-product-ficha-codex-review-2026-09-06.json`, índice SHA-256
`69fb7af0…f812073`, snapshot congelado `legacy-baseline-20260906`), verificar
sus precisiones sobre mi revisión anterior, y proponer cómo corregir la raíz
demostrada por las categorías mixtas. Sólo lectura; este archivo es mi único
producto de esta ronda. El llenado sigue bloqueado hasta cerrar auditoría y
saneamiento, como ordenó el dueño.

## 0. Evidencia y límites

| Qué | Cómo |
|---|---|
| Los 742 registros de Codex, nombre por nombre, agrupados por clase | Python sobre el JSON; 709 `nominal_candidate`, 22 `ambiguous`, 11 `business_record_review`; 109 clases contando `None` |
| Imágenes de identidad | `.tmp/product-spec-catalog/identity-images/manifest.json`: 24 entradas, 2 con error de descarga, 20 vistas. Establecen la **clase de objeto**; no certifican compatibilidad OEM |
| Puntos de integración categoría → plantilla | migraciones `20260906070000` (líneas 283, 374, 416, 504, 697–699, 309–316), `20260821520000` (asistente v7), `20260813203000` (v4), `20260817160000` (compras), `20260503124500` (tienda), y seis archivos Dart citados en §3.1 |
| Fuentes públicas | Sheldon Brown *Tire Sizing* y glosario «Rotor»; Park Tool *Linear Pull Brake Service* (ya leídas hoy) |

Lo que no hice: no leí envases ni OEM por producto; no toqué mi JSON de los
863 (las correcciones que le corresponden quedan en §1 como fe de erratas, para
aplicarlas cuando se autorice); no escribí código ni SQL.

## 1. Precisiones de Codex sobre mi revisión de los 863

Todas correctas. Consecuencia para `assigned-product-ficha-claude-review-2026-09-06.json`:

| Precisión | Veredicto | Cambio pendiente en mi JSON |
|---|---|---|
| «Desconocido / sin confirmar» en HV408 no contradice 3/32 | Correcto: es un estado epistemológico, no un valor distinto | retirar el `fact_issue` de `chain_width_family` en HV408 (queda la nota sobre `drivetrain_primary_ecosystem=Otro`) |
| BSA no nombrado es falta de evidencia, no prueba de valor falso | Correcto; mi redacción lo trataba como conflicto | reescribir los 24 `fact_issues` de pedalier como «sin evidencia en el nombre; procedencia import»; no son contradicciones |
| «24"» nominal es insuficiente; no afirmar 507 sin un consumidor que lo interprete así | Correcto: el vocabulario `wheel_size` es nominal y ningún lector lo convierte a BSD | reescribir los 4 casos 24 × 1 3/8 y el 622/635 como **huecos del vocabulario** (no puede expresar 540/547/520 ni dos BSD), sin afirmar qué significa hoy «24"» |
| «NECO COMPATIBLE» no obliga a cambiar la marca Andes | Correcto; la imagen del producto lleva el logo Andes Industrial | retirar el `identity_issue` del rotor freestyle; revisar con el mismo criterio «Monsoon» (Andes) y «A-FORGE» (Andes) |
| 49b90689 es un fuelle de goma de cable V-brake, no una pastilla | Correcto (imagen: fuelle acordeón con terminal); el producto no estaba en mi conjunto | ninguno; en el JSON de Codex el 551 pasa de `ambiguous` a `brake_cable_boot` (§2.2) |
| b7fb996c muestra dos cálipers mecánicos, dos discos y dos adaptadores IS/PM, sin manetas | Correcto: **kit parcial**, no freno completo | retirar «→ complete_brake» del Logan; nuevo veredicto: composición (§3.3), ni `brake_caliper` de una unidad ni `complete_brake` |

Resoluciones por imagen de mis propios `ambiguous` y `wrong_template`:

| Producto | Imagen | Veredicto final |
|---|---|---|
| Freno Balata 90 mm | freno de banda (tambor con palanca y resorte) | `wrong_template`; clase «freno de banda», sin familia actual |
| PIÑON 15T FIJO | piñón fijo roscado | confirmado `fixed_cog` |
| ROTOR FREESTYLE COMPLETO | gyro: dos cables con divisores, anillo con rodamiento, dos placas | confirmado; clase «gyro BMX», sin familia actual |
| PIÑON 16 DTS EASTMAN | rueda libre de una velocidad (cuerpo con dos agujeros de extractor) | pasa de `ambiguous` a `freewheel` |
| Cubetas Motor Bmx Americana Sellada 19 mm | dos rodamientos de cartucho en copas, manguito, espaciadores | pasa a `bottom_bracket` (americano sellado completo) |
| Juego De Bielas + Cubetas Motor Mid | bielas de tres piezas, eje estriado, dos rodamientos, espaciadores | pasa a `crankset` con pedalier incluido; no `drivetrain_kit` |
| Pastillas de Freno Bicicleta Fantom | par de pastillas de disco con resorte | pasa a `brake_pad` (disco; forma sin identificar) |
| Obús Válvula Deemount | núcleos Presta de 26 mm | confirmado núcleo, no válvula |
| Canastillo Eje Thompson | canastillo de bolas | confirmado; decisión de familia en §2.3 |
| RESORTE (PAR) HERR/FRE | resorte de retorno de herradura | confirmado repuesto |
| Extension de postiza Risk | extensor de patilla con perno | confirmado extensor |
| CAMARA 26 (NO ES EXACTAMENTE…) | cámara Presta genérica | sigue `ambiguous`: la imagen no resuelve el rango |

## 2. Revisión independiente de los 742 registros de Codex

### 2.1 Lo que está bien

- Cada ID aparece una vez; los 197 sin categoría están incluidos; ninguna
  clase se asignó por analogía de categoría: los nombres se leyeron.
- 72 productos van a 24 familias que **ya existen**; 68 de ellos no tienen
  categoría. Es la corrección más barata del lote: categorizar, sin plantilla
  nueva.
- Los 11 registros administrativos (servicios, «Costo de bicicleta», «Nota de
  Crédito», «Test», «Gasto por transporte») están separados, no clasificados.
- Las 19 bebidas de la carta explican la anomalía «Nescafé» de mi plan: eran
  productos de cafetería, no un error de captura.

### 2.2 Errores u omisiones concretos

**a. `ambiguous` que la imagen o el nombre resuelven (11):**

| Registro | Resolución | Evidencia |
|---|---|---|
| 551 GOMITA PARA FRENO V-BRAKE | `brake_cable_boot` | imagen 49b90689; Codex ya usa esa clase para el 552 |
| 627 EJE BLOQUEO SOLO DELANTERO | `hub_axle` (eje hueco con conos y contratuercas) | imagen 5908b918: eje hueco, no aguja |
| 628 EJE BLOQUEO TRASERO 7/8 9V | `hub_axle` | imagen ce2e2810 |
| 180 Set Cubre Manubrio 125/220 mm | `grip` (puños de espuma en dos largos) | imagen 2ea1138a |
| 341 FUNDA PROTECTORA BEST GRIS | funda para bicicleta (accesorio suelto), no ropa | imagen 6be54ef6: envase Vision 200 × 58 × 100 cm; la marca impresa es Vision, no Best |
| 719 ACEITE NACIONAL | `workshop_chemical` | imagen ccdb85f9: Lubetrack lubricante multipropósito 100 ml |
| 722 LIMPIADOR TRIPLE PLATO PP-01 | `workshop_tool` (cepillo/herramienta de limpieza Rito) | imagen b887f8e9 |
| 537 Freno Hidráulico Delantero Tanke 4 Pistones | `complete_brake` (hidráulico, delantero) | nombre; el juego hermano ya está en `complete_brake` |
| 175 Rotor Freno Trasero BMX PadroBikes | gyro BMX, misma clase que el 64e9e200 | glosario Sheldon «Rotor» + el gemelo con imagen |
| 3, 10, 13, 105, 53, 129 (ALIEXPRESS, Andes, BETTABIKES, MKR, Dr. Bike, Pack) | `business_record_review`, no `ambiguous` | son rótulos de proveedor o comodines, no objetos |

**b. `ambiguous` que deben seguir así (7):** 44 Cubetas Motor Americano BMX
(cubeta vs pedalier completo), 56 Eje de Motor Set Up Bikes, 77 Juego de
Tuercas Laterales Motor + Rodamientos, 143/144 Piñón 1v (libre o fijo), 720
Aceite Mineral Chepark (fluido de freno o aceite general: hace falta la
etiqueta), 723 Limpiador Cadena y Piñón Chepark (químico o herramienta).

**c. Clases que chocan con el conjunto mapeado y exigen una sola política:**

| Codex (742) | Conjunto de 863 | Decisión que propongo |
|---|---|---|
| `combined_control` (1: ST-EF500) | 5 mandos combinados bajo `shifter` | una sola: `shifter` con subtipo «combinado» y rol de freno, o composición; no dos clases |
| `derailleur_mount_adapter` (1: Extensor De Cambio Betta) | mis 3 extensores marcados `wrong_template` sin familia | adoptar la clase de Codex para los cuatro |
| `complete_brake` (80: Kit Freno Disco Zoom Mecánico DB-280) | Logan (748) ya demostrado kit parcial | aplicar la misma regla a los dos: kit parcial, composición; no declarar freno completo sin verificar manetas |
| `solid_tire` (1: rueda sólida scooter) | `tire.tire_bead_type` tiene «Sólido / sin aire» | no es clase nueva; es `tire` con subtipo y además **no bicicleta** |
| `tubeless_tape` (10) | matriz §3: `rim_strip` con discriminador «protección de cámara / cinta sellante» | mantener una familia con subtipo y campos por visibilidad (ancho, largo de rollo); no dos plantillas |
| `headset_bearing` (2) | `bearing.bearing_application` admite «Dirección» | `bearing`, no clase nueva |
| `bottom_bracket_bearing` (2) y 389 Canastillo Thompson | `bearing_application` admite «Pedalier» y existe `bottom_bracket_bearing` | elegir **una** familia para todo canastillo/rodamiento de pedalier; la duplicidad ya existe en el conjunto mapeado |

**d. Presentación antes que ficha.** `control_cable` (rollos de 30/50 m, sets
de 100), `control_terminal` (500 piezas), `hub_cone` (20 unidades), `fastener`
(mínimo 20), `bearing` (gruesa): igual que en el conjunto mapeado, la
cantidad de venta no cabe en ninguna plantilla. Ninguna de estas familias puede
declararse lista sin un campo de presentación.

**e. Fuera de bicicleta (24 + 1 mapeado):** 19 bebidas, 4 de electrónica de
consumo, la rueda sólida Xiaomi, el adaptador de válvula de scooter, y las dos
pastillas de patín eléctrico del conjunto mapeado. No reciben ficha; la
política se fija en §3.7.

### 2.3 Composición: 84 clases nuevas → 32 familias con subtipo

Conteos del JSON de Codex. «Subtipo» es un campo dentro de la familia, no una
plantilla aparte, salvo donde se indica.

| Familia propuesta | Productos | Clases de Codex que absorbe | Subtipo / nota |
|---|---|---|---|
| familia existente (categorizar) | 76 | 24 familias + `headset_bearing`, `combined_control`, `solid_tire` | 68 sin categoría; 8 en categorías mixtas |
| `rider_equipment` | 59 | rider_glove 33, helmet 13, eyewear 3, rider_apparel 4, rider_bag 2, rider_bag_cover 2, rider_protection 1, workshop_ppe 1 | subtipo + talla; certificación sólo con fuente |
| `workshop_tool` | 43 | workshop_tool 41, tool_spare_part 1, applicator 1 | operación e interfaz de servicio (K30) |
| `mounted_accessory` | 40 | accessory_mount 8, bottle_cage 11, rack_basket 5, fender 4, kickstand 2, training_wheel 3, bike_storage_mount 1, reflective_tape 1, bike_bag 5 | anclaje y dimensiones; sin compatibilidad |
| `grip` | 35 | grip 28, bar_tape 7 | subtipo puño/cinta; largo y diámetro |
| `pedal` | 35 | pedal 34, pedal_peg 1 | plataforma/cala/peg; rosca 9/16 o 1/2 (K22) |
| `lock` | 31 | lock 31 | subtipo U/espiral; dimensiones |
| `workshop_chemical` | 28 | workshop_chemical 28 | uso y formulación; sin reglas por color |
| `light_electronics` | 28 | light 20, cycle_computer 1, audible_signal 7 | alimentación, anclaje |
| `saddle` | 26 | saddle 22, saddle_cover 4 | riel; la funda con dimensiones del destino |
| `fastener` | 22 | fastener 22 | rol (biela, plato, rotor, tee), rosca y largo |
| `loose_accessory` | 22 | bottle 7, souvenir 7, frame_protection 3, valve_cap 3, cargo_strap 1, tire_liner 1 | atributos propios; sin interfaz |
| `hub_axle` | 20 | hub_axle 20 | diámetro, largo, hueco/macizo, con conos |
| `control_cable` | 18 | control_cable 18 | uso freno/cambio, cabezal, largo, presentación (K27) |
| `control_small_part` | 18 | control_terminal 12, brake_noodle 3, cable_adjuster 1, control_cable_guide 1, brake_cable_boot 1 | subtipo |
| `stem` | 18 | stem 16, stem_adapter 2 | interfaces espiga/manubrio; adaptador como subtipo |
| `pump` | 17 | pump 15, inflation_adapter 2 | mano/pie/shock; válvula |
| `seatpost` | 16 | seatpost 14, seatpost_shim 2 | diámetro; camisa con dirección (K20) |
| `hydraulic` | 15 | hydraulic_fitting 10, hydraulic_hose 2, brake_fluid 3 | manguera/oliva/inserto/fluido por modelo (K26) |
| `wheel_retention` | 15 | wheel_retention 14, wheel_retention_small_part 1 | aguja QR / eje pasante / perno |
| `handlebar` | 14 | handlebar 14 | diámetro de fijación, ancho, rise |
| `control_housing` | 13 | control_housing 13 | freno/cambio, diámetro, presentación en rollo |
| `seat_clamp` | 12 | seat_clamp 11, seat_clamp_small_part 1 | diámetro; QR |
| `tube_repair` | 12 | tube_repair 10, tubeless_repair 1, tubeless_valve_small_part 1 | material y proceso |
| `hub_small_part` | 11 | hub_cone 6, hub_locknut 1, hub_axle_adapter 1, spoke_nipple 3 | subtipo; niple con rosca y asiento (K17) |
| `headset_small_part` | 11 | headset_spacer 7, headset_preload 3, bottom_bracket_spacer 1 | espaciador/araña; el de pedalier va a pedalier |
| `fork` | 11 | fork 11 | espiga, rueda/eje, freno, recorrido (K19, K24, K28) |
| `rim_strip` ampliada | 10 | tubeless_tape 10 | subtipo cinta sellante con ancho/largo |
| `brake_adapter` | 5 | brake_adapter 4, rotor_mount_adapter 1 | extremos tipados y diámetro (K24) |
| `drivetrain_small_part` | 3 | derailleur_mount_adapter 1, chainring_guard 1, cassette_lockring 1 | subtipo; recibe los 3 extensores del conjunto mapeado |
| `rear_shock` | 1 | rear_shock 1 | largo entre ojos, carrera (K29) |
| `brake_small_part` | 1 | brake_pad_retainer 1 | subtipo |
| sin ficha por política | 23 + 33 | food_beverage 19, consumer_electronics 4; `None` 33 | §3.7 |

Suma: 742. Cuatro clases nuevas quedan además fuera de este cuadro y salen del
conjunto mapeado: «freno de banda», «gyro BMX» (2 productos entre ambos
conjuntos), y los kits parciales de freno (Logan, Zoom). Son composición o
familia pequeña, no plantilla por categoría.

## 3. Propuesta: vínculo explícito producto → ficha, con la categoría como respaldo

### 3.1 Dónde se resuelve hoy categoría → plantilla (puntos reales)

| Punto | Archivo y línea | Qué hace |
|---|---|---|
| Validación diferida del producto | `20260906070000` 374 | `select m.template_id … from category_tech_mappings m where m.category_id = v_product.category_id` |
| Guardado atómico | `20260906070000` 504–511 | resuelve la plantilla por `p_product->>'category_id'` y exige que sea igual a `p_template_id`; si no, «La plantilla cambió» |
| Contexto de taller | `20260906070000` 283 | `get_product_spec_contexts_v1` hace `left join category_tech_mappings` |
| Tienda pública | `20260906070000` 416 | `get_public_product_technical_specs` hace `join category_tech_mappings` (sin mapeo, sin ficha publicada) |
| Escritor legado de hechos | `20260906070000` 697–699 | «La respuesta no pertenece a esta plantilla» contra la plantilla de la categoría |
| Asistente IA (búsqueda v7) | `20260821520000` 367–447 | `product.technical_family` sale de `mapping.technical_family`; el alcance por categoría también |
| Compras (necesidades) | `20260817160000` y `supply_need_effective_criteria.dart` 36–45 | la familia «la deriva de `category_tech_mappings`»; la columna nace nula |
| Formulario de producto | `spec_engine_service.dart` 239–247 y `product_form_page.dart` 1259–1330 | `getTemplateForCategory(categoryId)`; el borrador se guarda por categoría (`_specDrafts[categoryId]`) |
| Compatibilidad de taller (cliente) | `bike_product_compatibility_service.dart` 283–374 | caché de mapeos por `categoryId` |
| Recomendación de trabajos | `smart_job_recommendation_service.dart` 310–325 | categorías cuya familia es `chain` |
| Contratos del asistente | `ai_assistant_turn_contracts.dart` 315–326 | `technicalFamily` «derivada; su dueño es `category_tech_mappings`» |

No hay ninguna columna de plantilla ni familia en `products` (verificado en
`information_schema`); el vínculo referencia → producto sí existe
(`spec_reference_id`), y su validador exige que la familia de la referencia sea
la de la plantilla resuelta por categoría (línea 169).

### 3.2 Diagnóstico

La única resolución es por categoría, y las categorías son comerciales: una
misma hoja contiene legítimamente dos clases de objeto («Pastillas» con
zapatas y pastillas de disco; «Piñones» con ruedas libres y un piñón fijo;
«Calipers» con un kit; «Postiza» con extensores; «Válvula Tubeless» con
núcleos; «Rodamientos» con cuatro aplicaciones), 197 productos no tienen
categoría y 742 no tienen mapeo. Partir categorías no lo arregla: multiplica
hojas de navegación de la tienda y de compras, no sirve para los sin
categoría, y no representa kits ni subtipos. La raíz es que el sistema no
guarda **qué es** cada producto; lo infiere de dónde lo puso el vendedor.

### 3.3 Cuatro conceptos que hoy se confunden

| Concepto | Qué es | Dónde debe vivir |
|---|---|---|
| **Identidad de pieza** | la clase de objeto (familia) más marca, modelo, MPN, GTIN y, si existe, la referencia OEM | vínculo explícito del producto a una plantilla de esa familia; identidad ya existente en `products` y `product_spec_references` |
| **Subtipo** | variante dentro de la familia que cambia qué campos aplican (disco/zapata, V-brake/tiro lateral, puño/cinta, QR/eje pasante) | un campo de la plantilla con rol `subtype` y reglas de visibilidad; sólo cuando los conjuntos de campos divergen mucho, dos plantillas de la misma familia, como ya hace `complete_brake` |
| **Kit** | varios objetos vendidos juntos (2 cálipers + 2 rotores; biela + pedalier; juego de mazas) | composición: `save_product_set_aggregate`, `is_set`, `parent_set_id`, `set_type` ya existen; cuando los componentes no son SKU propios, un contenido estructurado del kit, no un texto |
| **Declaración de compatibilidad** | lo que una fuente afirma que la pieza admite | referencias, claims y consumidor de taller, ya implementados; independientes del vínculo salvo la comprobación de familia |

Cadena y conector ya cumplen esto por dentro; el problema es que ninguna otra
familia puede llegar ahí mientras la familia la decida la categoría.

### 3.4 Alternativas evaluadas

| Opción | Qué resuelve | Qué no resuelve | Veredicto |
|---|---|---|---|
| A. Partir las categorías mixtas | Pastillas, Piñones, Postiza | sin categoría (197), sin mapeo (742), kits, subtipos; toca navegación de tienda y compras | insuficiente sola |
| B. `products.spec_template_id` explícito, con `category_tech_mappings` como respaldo cuando es nulo | todo lo anterior por producto; conserva el respaldo histórico para los 863 sin tocarlos | subtipo y kit los resuelven las plantillas y los sets, no el vínculo | **recomendada** |
| C. `products.technical_family` explícito y plantilla por familia | igual que B en identidad | una familia puede tener dos plantillas (`complete_brake`), así que la familia no basta para elegir el contrato; duplica la verdad con la plantilla | no; la familia se **deriva** de la plantilla resuelta |

Sí hace falta una arquitectura nueva, pero pequeña: una columna, un resolvedor
único y un comando versionado. Lo demás ya existe.

### 3.5 Diseño propuesto

1. **Columna** `products.spec_template_id uuid null references spec_templates(id)`,
   con la restricción de que la plantilla esté activa y sea global o del
   tenant del producto (mismo criterio que hoy usa el guardado).
2. **Resolvedor único** `spec_product_template_internal_v1(p_product_id)` →
   `coalesce(products.spec_template_id, plantilla activa del mapeo de la
   categoría)`, más una vista `product_spec_bindings_v1(product_id,
   template_id, technical_family, source)` con `source ∈ {explicit, category,
   none}` para los lectores por conjunto (búsqueda del asistente, compras,
   bodega). La familia técnica se lee siempre de esa vista; nadie vuelve a
   hacer join con `category_tech_mappings` para un producto concreto.
3. **Comando**: `save_product_with_specs_v1` recibe además
   `p_template_binding` (`{"template_id": …}` o `{"inherit": true}`). La regla
   actual «plantilla resuelta = `p_template_id`» se mantiene, pero la
   resolución se hace **después** de aplicar el vínculo pedido. El cambio de
   vínculo exige `p_expected_revision` y `p_expected_updated_at`, sube
   `spec_revision` por el trigger existente y deja recibo con el antes y el
   después. La referencia (`spec_reference_id`) debe pertenecer a la familia
   de la plantilla resuelta, como ya exige la línea 169.
4. **Consumidores** (tabla): 

| Consumidor | Cambio |
|---|---|
| `spec_validate_product_internal_v1` | usa el resolvedor en vez del join (línea 374) |
| `get_product_spec_contexts_v1`, `get_public_product_technical_specs` | usan el resolvedor (líneas 283 y 416); la tienda publica por vínculo, no por categoría |
| `save_product_spec_facts_v1` (legado) | guardia 697–699 por resolvedor, o retiro del RPC si ya no tiene llamadores |
| `assistant_search_inventory_v7`, `supply_need_*`, `supply_need_stock_candidates_v1`, búsquedas de inventario | leen `product_spec_bindings_v1`; el alcance por categoría sigue existiendo para consultas sin producto |
| Formulario (`product_form_page`, `SpecEngineService`) | carga la plantilla por producto (`get_product_spec_snapshot_v1` devuelve `template_id` y `source`); el borrador se indexa por plantilla, no por categoría; acción «Cambiar ficha» que muestra los hechos que quedarían fuera |
| `BikeProductCompatibilityService`, `SmartJobRecommendationService` | dejan de cachear mapeos por categoría; leen la familia del contexto o de la vista |
| Contratos del asistente y `supply_need_effective_criteria` | `technicalFamily` sale del vínculo cuando hay producto; sin producto, de la categoría, como hoy |
| Revisión de identidad y OCR | hoy no leen familia (verificado con grep en `product_duplicate_matcher_service.dart` y `ocr_purchase_review_flow.dart`); no cambian ahora; cuando la identidad use familia, la toma de la vista |

5. **Rol `subtype`** en `form_contract.roles` para el campo discriminador de
   cada familia; el evaluador de tres estados ya sabe ocultar y exigir por
   visibilidad. Familias del §2.3 que lo necesitan: brake_pad, rim_brake, grip,
   pump, wheel_retention, hub_small_part, control_small_part, seatpost, stem,
   rider_equipment, mounted_accessory, loose_accessory.
6. **Kits** por sets cuando los componentes son SKU; cuando no, un campo de
   contenido estructurado con roles (cantidad y familia por miembro) en vez
   del `kit_contents` texto. Un kit no hereda la ficha de un miembro ni la
   suma en una ficha plana (matriz, `drivetrain_kit`).

### 3.6 Conservar los hechos al corregir la ficha

Comportamiento actual, leído en el writer y el validador:

- El writer rechaza cualquier clave del payload que no esté en la plantilla
  (líneas 309–311) y **borra sólo** los hechos cuyas definiciones sí están en
  la plantilla y no vienen en el payload (313–316). Los hechos de definiciones
  fuera de la plantilla **sobreviven**.
- El validador recorre únicamente los campos de la plantilla (línea 181 en
  adelante); los lectores de taller y tienda filtran por campos de la
  plantilla. Un hecho fuera de plantilla es invisible y no bloquea.
- Codex encontró una cubeta con `spindle_diameter_mm` guardado y fuera de su
  plantilla: la prueba de que ya existen hechos huérfanos y de que el sistema
  los conserva en silencio.

Propuesta: mantener exactamente esa conservación y hacerla visible.

- Al cambiar el vínculo, ningún hecho se borra. Los que existen en la nueva
  plantilla se muestran; los demás pasan a una lista `__orphan_facts` del
  snapshot y del contexto, con valor, procedencia, `confirmed` y lecturas
  intactos.
- Un huérfano sólo se borra por comando explícito con recibo, nunca por el
  cambio de ficha; migrarlo a otra definición es otro comando.
- El validador reporta los huérfanos como incidencia no bloqueante
  (`orphan_fact`), para que el saneamiento los vea sin impedir guardar.
- Las referencias: si la nueva plantilla es de otra familia, el vínculo con
  la referencia se rechaza (regla 169) y el comando falla completo; primero se
  desvincula la referencia, que ya conserva las observaciones independientes.

### 3.7 Política para lo que no lleva ficha

Un `product_kind` derivado y auditado, no adivinado por palabra:
`bicycle_part` (con plantilla), `rider_equipment` y `accessory` (con plantilla
de atributos propios, sin compatibilidad), `consumable` (químicos, parches),
`non_bicycle` (cafetería, electrónica, scooter) y `business_record` (servicios,
costos, notas de crédito, comodines). Sólo el primero puede llevar referencia y
claims; `non_bicycle` y `business_record` no reciben plantilla ni entran en la
cola de llenado. Los 19 cafés y los 4 electrónicos son la prueba de que hace
falta.

### 3.8 Decisiones implementables, con evidencia

1. Añadir `products.spec_template_id` y el resolvedor único; migrar los once
   puntos de §3.1 a él. Evidencia: cada punto hace hoy su propio join.
2. Extender `save_product_with_specs_v1` con `p_template_binding` y recibo del
   antes/después. Evidencia: líneas 504–511 exigen igualdad con la plantilla de
   la categoría, lo que impide corregir una ficha sin mover el producto de
   categoría.
3. Exponer `__orphan_facts` y la incidencia `orphan_fact`; prohibir el borrado
   implícito. Evidencia: writer 313–316 y la cubeta de Codex.
4. Corregir los ocho `wrong_template` y los resueltos por imagen (§1 y §2.2)
   **con ese comando**, no moviendo categorías: el piñón fijo a `fixed_cog`
   (mapeada a «Fixie»); el gyro, el freno de banda, los extensores y el
   resorte a sus clases nuevas cuando existan.
5. Categorizar los 68 sin categoría que pertenecen a familias existentes y
   vincularlos explícitamente; son 68 fichas sin plantilla nueva.
6. Fijar una sola política para mandos combinados, canastillos de pedalier,
   kits parciales de freno, cinta tubeless y rueda sólida (§2.2.c) antes de
   crear plantillas.
7. Crear las familias del §2.3 por bloques de la matriz, cada una con su campo
   de subtipo y su lista de campos críticos, sin compatibilidad hasta tener
   fuentes, con los conteos de §2.3: contacto y dirección (144), cables,
   hidráulica y adaptadores de freno (70), eje, retención y piezas de maza
   (46), equipamiento (59), herramientas y químicos (71), accesorios montados,
   luces y sueltos (40 + 28 + 22).
8. Añadir un campo de presentación (cantidad por unidad de venta, rollo,
   gruesa, par) transversal: aparece en cables, terminales, conos, pernos,
   rayos, mazas, herraduras y cassettes de ambos conjuntos.
9. Fijar `product_kind` y excluir de la cola 23 no bicicleta y 33 registros
   administrativos.
10. Cerrar el segundo motor de reglas del cliente al migrar: la compatibilidad
    de taller y la recomendación de trabajos dejan de decidir familia por
    categoría en Dart.
11. Rellenar `catalog-fill-critical-fields.json` por familia nueva antes de
    declararla lista para investigar (E3), como manda el orden del dueño:
    revisar, detectar, verificar campos, sanear, y sólo después llenar.

### 3.9 Verificación mínima antes de declarar el vínculo implementado

pgTAP local con tenant sintético, como en `product_spec_contract.sql`:
vínculo explícito gana sobre el mapeo; nulo cae al mapeo; producto sin ninguno
no publica ni bloquea; cambiar el vínculo conserva hechos huérfanos con su
procedencia y lecturas; referencia de otra familia rechaza el cambio completo;
la proyección pública y el contexto de taller siguen el vínculo; recibo
idempotente; cambio concurrente de categoría no revive un mapeo sobre un
vínculo explícito. Y un frame real del formulario mostrando la ficha correcta
en un producto de categoría mixta («Pastillas» con zapata de V-brake) en
escritorio, tablet y compacto, claro y oscuro.
