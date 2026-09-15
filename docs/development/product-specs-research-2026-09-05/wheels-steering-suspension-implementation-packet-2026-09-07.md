# Ruedas, dirección, rodamientos y suspensión — paquete implementable W01–W11 (2026-09-07)

Sobre la base congelada `all-family-reviewed-fields-integrated-2026-09-07.json` (`f3178bd3c860c421…`, 105/681). Operaciones y preimágenes del compilador `scripts/inventory/product_spec_field_patches.py`; el generador toma cada preimagen de la base y verifica los mismos chequeos antes de escribir. No reescribe la base ni las propuestas anteriores. Llenado, asignación y publicación siguen en cero.

**Representación frente a aprobación mecánica.** Cada parche cambia qué se puede escribir, nunca qué se aprueba. Ningún campo de este paquete emite compatibilidad: los pares neumático↔llanta, horquilla↔cuadro, amortiguador↔cuadro y radio↔niple siguen necesitando una relación con fuente. Las fuentes OEM se citan por la FORMA del dato que exigen; su verificación mecánica pertenece a la revisión W del 2026-09-06 y no se repite aquí.

## 1. Veredicto por hallazgo

| Id | Sev | Estado | Qué muestra la base | Residual |
|---|---|---|---|---|
| W01 | P1 | no resuelto por A/B; corrección real | La base tiene tire_bead_type (construcción del talón: alambre/plegable/tubular), dos booleanos tubeless_ready y un tire_max_pressure_psi único; rim.tire_width_range_mm sólo lleva ancho mín/máx y fuente. Ningún campo distingue hooked de hookless ni ata presión a la configuración. | La intersección de límites (23 mm del neumático manda sobre 25 mm de la llanta) es una regla de compatibilidad entre dos productos: no la cierra este paquete. |
| W02 | P1 | no resuelto por A/B; corrección parcial (representación) | rear_shock conserva eye_to_eye_mm, stroke_mm y un único shock_mount_kind; mounting_hardware_included es un booleano de contenido; frame.rear_shock_size es texto libre. | Envolvente/depósito durante el recorrido, identidad y generación del par amortiguador↔cuadro y talla no son campos de un producto: son relaciones OEM con estado aprobado/excluido/pendiente. Este paquete no las crea. |
| W03 | P1 | no resuelto por A/B; corrección real | La base conserva bearing_size_code como texto único, bearing_construction con «Cartucho sellado» indiviso y bearing_application como declaración con evidencia. La envolvente (ID/OD/ancho) sigue disponible. | La equivalencia OEM entre referencias concretas es una relación, no un campo. |
| W04 | P1 | parcialmente resuelto por A/B; corrección real pendiente | A/B ya partió el escalar en bearing_inner_contact_angle_deg y bearing_outer_contact_angle_deg, condicionados a bearing_application = Dirección. Eso resuelve el par para un rodamiento suelto. | No se cierra por existir las dos columnas: la plantilla headset (el producto que el taller vende) no tiene ángulos ni representación por extremo, y el par no era exigible ni con destino «Dirección». |
| W05 | P2 | no resuelto por A/B; corrección real | frame.headset_upper_shis y headset_lower_shis siguen siendo texto obligatorio siempre, sin puertos separados. | El stack total y la longitud de espiga disponible siguen siendo del montaje, no del cuadro solo. |
| W06 | P2 | resuelto por A/B | headset_part_scope (Superior/Inferior/Completa) existe y condiciona ambos extremos: allowed_when y required_when de headset_upper_shis piden Superior o Completa, y los del inferior Inferior o Completa. Los dos SHIS son text libre, sin expresión regular cerrada: ZS62/40 y EC49/38.1 se guardan tal cual. | El registro ampliable de combinaciones documentadas sigue siendo un asunto de vocabulario, no de esquema: un texto que pasa no queda aprobado por eso. |
| W07 | P1 | no resuelto por A/B; corrección real | fork tiene bead_seat_diameter_mm, un max_tire_width_mm único, travel_mm y fork_offset_mm sin contraparte, y ninguna longitud eje-corona ni stack de corona. | Las restricciones del cuadro por modelo y talla (geometría, tipo de corona, recorrido admitido) son del cuadro y de la relación, no de la horquilla; este paquete no las crea. |
| W08 | P2 | parcialmente resuelto por A/B; corrección real pendiente | hub_old_mm, frame.rear_hub_old_mm y wheel.hub_old_mm son number con positive y sin integer: 132,5 se almacena exacto. hub_spacing_mm (lista cerrada 100–157) quedó como legacy. | No se cierra por el tipo decimal: las mazas nominales que una puntera acepta no tienen dónde escribirse, y esa lista es la mitad del caso Surly. |
| W09 | P2 | resuelto por A/B | thru_axle_thread incluye M12×1,75 y M20×1,0/1,5/1,75 además del par original; la plantilla wheel_retention separa thru_axle_diameter_mm, thru_axle_length_mm y target_hub_old_mm, y el requisito de rosca está condicionado a retention_kind = Eje pasante (en hub, fork y frame, al tipo de eje). El LIG601 12×174×1,75 se representa sin unknown artificial y un QR no queda pendiente por falta de rosca. | La denominación literal del fabricante no tiene campo propio y va en spec_evidence_source: no propongo un segundo dueño de la misma rosca, por la misma razón que en el saneamiento de luces. |
| W10 | P2 | no resuelto por A/B; corrección real | spoke_gauge y spoke_thread_diameter_mm coexisten, pero el segundo sigue rotulado como diámetro de rosca; nipple_thread es una lista de calibres (14G/15G/13G). | La referencia compatible OEM para sistemas propietarios sigue siendo una relación entre productos. |
| W11 | P2 | no resuelto; fuera del alcance de campos | spoke_length_mm existe; el conteo de agujeros existe en rim.spoke_hole_count y hub.spoke_hole_count. Nada de eso es una receta de armado. | Las dos reglas que el hallazgo rechaza (±1 mm y conteos iguales) son reglas de compatibilidad, no campos: no hay parche que las corrija. La receta de armado (lado, geometría, patrón, método de cálculo, compensación, niple) sería un campo de filas nuevo y no lo propongo sin que el dueño confirme que el taller registra armados; ver decisión D-W11. |

Dos hallazgos se cierran con evidencia: **W06** (existe `headset_part_scope` y los SHIS son texto libre, así que ZS62/40 y EC49/38.1 caben) y **W09** (vocabulario de rosca ampliado, retención separada de OLD y rosca condicionada al eje pasante). **W04 y W08 no se cierran por existir una columna**: el par de ángulos existe para un rodamiento suelto pero no para la dirección que se vende, y el decimal de OLD no representa las mazas que una puntera acepta. **W11 no tiene parche**: sus dos reglas son de compatibilidad, no de campos.

## 2. Parches

| Id | Hallazgo | Operación | Plantilla / clave | Alcance |
|---|---|---|---|---|
| WSS-W01-rim-rim_bead_profile | W01 | add_field | rim / rim_bead_profile | Sólo la plantilla rim. Hookless y hooked no son el mismo asiento y hoy no se distinguen; tubeless_ready es otro eje. |
| WSS-W01-wheel-rim_bead_profile | W01 | add_field | wheel / rim_bead_profile | Sólo la plantilla wheel. Hookless y hooked no son el mismo asiento y hoy no se distinguen; tubeless_ready es otro eje. |
| WSS-W01-tire-configurations | W01 | add_field | tire / tire_rim_configurations | El límite es por variante × perfil × método: 28c hookless 23 mm y 5,0 bar; 30c hookless 25 mm y 4,5 bar. Una presión única del producto no representa dos montajes. |
| WSS-W01-tire-max_pressure-label | W01 | replace_definition_label | — / tire_max_pressure_psi | El escalar sigue siendo el titular OEM y conserva su dueño; el detalle por configuración vive en las filas. Ni el escalar se deriva de las filas ni las filas lo niegan. |
| WSS-W02-shock-ends | W02 | add_field | rear_shock / shock_end_configurations | Cada extremo tiene su tipo, ancho y perno: hoy sólo hay un shock_mount_kind para todo el amortiguador. Una fila por extremo, identificada por posición. |
| WSS-W02-hardware-label | W02 | replace_definition_label | — / mounting_hardware_included | Sólo el rótulo: «incluido» dejaba leerse como «apropiado para este cuadro». |
| WSS-W03-size_code-label | W03 | replace_definition_label | — / bearing_size_code | Rótulo de la definición, compartida por bearing, bottom_bracket y bottom_bracket_bearing: en las tres el campo es la designación del fabricante, así que el cambio vale para todas. |
| WSS-W03-dimensional_code | W03 | add_field | bearing / bearing_dimensional_code | Segundo dueño legítimo: el literal del fabricante y el código dimensional normalizado son dos hechos, como en el saneamiento de luces. |
| WSS-W03-internal_construction | W03 | add_field | bearing / bearing_internal_construction | ID/OD/ancho es filtro de envolvente; la retención de bolas y el destino previsto son otro hecho. |
| WSS-W03-seal_kind | W03 | add_field | bearing / bearing_seal_kind | El sellado y la lubricación cambian el destino funcional y viajan en el sufijo de la designación. |
| WSS-W03-application-label | W03 | replace_definition_label | — / bearing_application | Sólo el rótulo: el campo es una declaración con evidencia, no una interfaz. |
| WSS-W04-headset-bearings | W04 | add_field | headset / headset_bearing_configurations | Una dirección completa lleva dos rodamientos con pares de ángulos propios; hoy la plantilla headset no tiene ningún ángulo. Una fila por extremo vendido. |
| WSS-W04-bearing-require-bearing_inner_contact_angle_deg | W04 | replace_field_contract | bearing / bearing_inner_contact_angle_deg | El propio hallazgo señala que la nota exige el par y el contrato no lo pedía. La exigencia es no bloqueante (required_missing) y sólo cuando el destino declarado es dirección. |
| WSS-W04-bearing-require-bearing_outer_contact_angle_deg | W04 | replace_field_contract | bearing / bearing_outer_contact_angle_deg | El propio hallazgo señala que la nota exige el par y el contrato no lo pedía. La exigencia es no bloqueante (required_missing) y sólo cuando el destino declarado es dirección. |
| WSS-W05-frame-ports | W05 | add_field | frame / headset_port_configurations | El alojamiento del cuadro es un puerto con tipo, diámetro nominal y profundidad; el código nominal, la dimensión medida y la tolerancia son significados distintos. |
| WSS-W05-frame-upper_shis-optional | W05 | replace_field_contract | frame / headset_upper_shis | El SHIS del cuadro pasa a evidencia de la configuración original y deja de ser obligatorio: exigirlo siempre obliga a inventar un código donde sólo hay un alojamiento medido. |
| WSS-W05-frame-lower_shis-optional | W05 | replace_field_contract | frame / headset_lower_shis | Igual que el superior. |
| WSS-W05-label-headset_upper_shis | W05 | replace_field_contract | frame / headset_upper_shis | Sólo en la plantilla frame. La definición la comparten headset, bicycle y frame: en una dirección el SHIS es su propio código y ese rótulo no debe cambiar, así que se anula por plantilla en vez de reescribir la definición. |
| WSS-W05-label-headset_lower_shis | W05 | replace_field_contract | frame / headset_lower_shis | Sólo en la plantilla frame. La definición la comparten headset, bicycle y frame: en una dirección el SHIS es su propio código y ese rótulo no debe cambiar, así que se anula por plantilla en vez de reescribir la definición. |
| WSS-W07-fork-clearance | W07 | add_field | fork / fork_tire_clearance_configurations | La envolvente es por rueda: la FOX 40 de 2013 en 26" limita pico 694 mm, borde 670 mm y ancho 71 mm. Ancho y nominal por separado no bastan. |
| WSS-W07-fork-axle_to_crown | W07 | add_field | fork / axle_to_crown_mm | Geometría que el cuadro exige y hoy no existe en la horquilla. |
| WSS-W07-fork-crown_stack_min_mm | W07 | add_field | fork / crown_stack_min_mm | El manual FOX exige comprobar el stack total 105–166,8 mm para la corona direct mount. |
| WSS-W07-fork-crown_stack_max_mm | W07 | add_field | fork / crown_stack_max_mm | El manual FOX exige comprobar el stack total 105–166,8 mm para la corona direct mount. |
| WSS-W07-fork-stack-pair | W07 | replace_template_coherence | fork / scalar_ordered_pairs | Ambos extremos son number en mm: el par es válido para el evaluador desplegado en 0200. Se aplica en la misma migración que los dos campos. |
| WSS-W07-fork-max_tire_width-label | W07 | replace_field_contract | fork / max_tire_width_mm | Sólo en fork. La definición la comparten fender, bicycle y frame, que no reciben filas de envolvente: se anula por plantilla y allí conserva su rótulo. |
| WSS-W08-frame-dropout | W08 | add_field | frame / dropout_hub_acceptance_configurations | El ancho físico entre punteras (rear_hub_old_mm, ya decimal) y las mazas nominales aceptadas son dos hechos. El Pack Rat mide 132,5 y acepta 130 y 135 por diseño. |
| WSS-W10-spoke-thread-label | W10 | replace_definition_label | — / spoke_thread_diameter_mm | El campo pasa a nombrar lo que sí es: una medición del alambre. No se copia 14G → 2,0 mm. |
| WSS-W10-spoke-thread_standard | W10 | add_field | spoke / spoke_thread_standard | La rosca laminada tiene su propia designación, distinta del calibre del alambre. |
| WSS-W10-nipple-thread_standard | W10 | add_field | spoke_nipple / nipple_thread_standard | La misma convención en los dos lados: sin ella, un radio FG 2.3 y su niple «14G» parecen incompatibles. |
| WSS-W10-nipple-thread-label | W10 | replace_definition_label | — / nipple_thread | El campo es una lista de calibres comerciales, no una rosca medida. |

Definiciones nuevas: 15 (axle_to_crown_mm, bearing_dimensional_code, bearing_internal_construction, bearing_seal_kind, crown_stack_max_mm, crown_stack_min_mm, dropout_hub_acceptance_configurations, fork_tire_clearance_configurations, headset_bearing_configurations, headset_port_configurations, nipple_thread_standard, rim_bead_profile, shock_end_configurations, spoke_thread_standard, tire_rim_configurations). Ninguna existe en la base.

## 3. Carencias del motor que quedan abiertas

| Id | Carencia | Casos | Estado |
|---|---|---|---|
| E1 | Condiciones por celda dentro de una fila (aplicabilidad y obligatoriedad). | max_pressure_bar exigible sólo cuando mounting_method = Tubeless; max_inflated_diameter_mm exigible cuando el manual publica envolvente; hardware_width_mm sólo con mount_kind = Ojal estándar | La migración 2200 (row_conditions) está local y en revisión: este paquete NO depende de ella y deja esas celdas opcionales. |
| E2 | Consistencia fila ↔ escalar. | tire_max_pressure_psi frente a las presiones por configuración; fork.max_tire_width_mm frente a las filas de envolvente; frame.rear_hub_old_mm frente a las mazas aceptadas; headset_part_scope frente a las filas de rodamiento por extremo | No expresable. Ninguna de estas parejas es duplicación: son titular declarado y detalle conocido, como en el saneamiento de luces. |
| E3 | Referencias entre filas de dos productos distintos (neumático ↔ llanta, horquilla ↔ cuadro, amortiguador ↔ cuadro). | intersectar 23 mm del neumático con 25 mm de la llanta; envolvente FOX frente a la rueda concreta | Fuera del contrato de coherencia por diseño: eso son relaciones con fuente, no coherencia interna de una ficha. |
| E4 | Comparación numérica entre filas y escalares (mínimos, máximos, intersecciones). | la presión menor de dos componentes manda | No se propone: convertir una intersección en regla automática produce aprobaciones que ninguna fuente respalda. |
| E5 | Los consumidores (filtro técnico del asistente y facetas) todavía no leen columnas de filas. | buscar neumáticos por presión admitida en hookless; buscar direcciones por ángulo de contacto | Compuerta técnica previa a mover detalle a filas, no trabajo manual del dueño. Es la misma G7 del bloque de luces. |

## 4. Decisiones que quedan en root

- **D-W11 — ¿El taller registra recetas de armado de rueda?** Si las registra, el campo mínimo es una fila por lado con geometría, patrón, método de cálculo, compensación y niple; si no, W11 se cierra como asunto de relaciones y no se agrega campo. No lo decido yo: no hay evidencia en el catálogo de que se armen ruedas a medida.
- **D-W02 — ¿Dónde vive la aprobación amortiguador↔cuadro?** En relaciones con identidad, generación y talla, con estado aprobado / excluido / pendiente y su fuente. Los campos de este paquete describen el amortiguador; ninguno afirma que sirva para un cuadro.
- **D-W01 — ¿Se conserva tire_max_pressure_psi ahora que hay presión por configuración?** Sí. Es el titular del fabricante y tiene su propio significado; retirarlo repetiría el error que root corrigió en luces al confundir total declarado con detalle parcial.

## 5. Fixtures

| Id | Plantilla | Tipo | Issues esperados | Nota |
|---|---|---|---|---|
| tire_gp5000_two_variants_hookless | tire | valid | — | Dos variantes del mismo modelo con límites distintos. El titular de 102 psi convive con 5,0 bar de la configuración hookless: no es contradicción, es otro alcance (E2). |
| tire_pressure_of_another_variant | tire | contradictory_undetectable | — | La 28c con los límites de la 30c: el motor no puede saberlo. Es error de captura, y la regresión que el hallazgo pide vive en la revisión de la fuente, no en el esquema. |
| tire_hookless_without_configurations | tire | unknown | — | Sin filas, la respuesta para hookless es desconocida. Poner cámara no cambia la exigencia y el booleano de un lado no la resuelve. |
| tire_same_variant_profile_method_twice | tire | contradictory | row_shape@tire_rim_configurations | unique_by [variante, perfil, método] rechaza dos presiones para la misma configuración. |
| shock_trunnion_top_eyelet_bottom | rear_shock | valid | — | Campo dependiente de posición: cada extremo lleva su fijación. El hardware incluido no afirma nada sobre un cuadro; el contacto del depósito sigue siendo relación pendiente. |
| shock_two_rows_same_end | rear_shock | contradictory | row_shape@shock_end_configurations | unique_by [extremo]. |
| bearing_same_envelope_different_construction | bearing | valid | — | Misma envolvente que un rodamiento de maza y construcción distinta: ahora se distingue. «Cabe» sigue sin significar «aprobado». |
| headset_bearing_angles_per_end | headset | valid | — | Campo dependiente de posición: 36×45 arriba y 45×45 abajo dejan de colapsar en «45». |
| headset_lower_only_scope | headset | valid | — | W06 ya resuelto: una mitad inferior no exige inventar el extremo superior y EC49/38.1 se guarda porque el campo es texto. |
| bearing_headset_without_angles | bearing | unknown | required_missing@bearing_inner_contact_angle_deg, required_missing@bearing_outer_contact_angle_deg | Con destino «Dirección» el par pasa a exigible y su ausencia queda pendiente, no aprobada. Antes de este parche no se pedía. |
| frame_44_housing_two_alternatives | frame | valid | — | El alojamiento de 44 mm admite EC44/30 y ZS44/30; el SHIS registrado es la configuración original y no cierra la lista. |
| frame_housing_without_shis | frame | unknown | — | Diámetro medido de 41,8 sin código: el redondeo a IS42 es una convención declarada, no una medición, y no se escribe solo. Antes del parche el SHIS era obligatorio y obligaba a inventarlo. |
| fork_fox40_envelope | fork | valid | — | El caso construido de 70 mm de ancho y 695 mm de pico queda fuera aunque pase el ancho. Límites de esta generación, no de la familia. |
| fork_stack_inverted | fork | contradictory | range_order@crown_stack_min_mm, range_order@crown_stack_max_mm | El par escalar del contrato 0200 marca los dos extremos. |
| frame_surly_gnot_rite | frame | valid | — | 132,5 se guarda exacto (ya era decimal) y las mazas aceptadas son filas. 131 no queda aceptado y esto no autoriza forzar otro cuadro. |
| frame_dropout_open_interval | frame | contradictory_undetectable | — | Nada impide escribir 131: la fuente Surly no lo declara. El esquema no inventa el intervalo, pero tampoco detecta una fila sin respaldo (E2/E3). |
| spoke_sapim_2mm_fg23 | spoke | valid | — | Alambre de 2,0 mm medido y rosca FG 2.3 declarada: dos hechos. Con el rótulo anterior parecían el mismo y se contradecían. |
| spoke_nipple_pair_naming | spoke_nipple | valid | — | El niple declara la misma convención: un radio FG 2.3 y este niple dejan de parecer incompatibles. |
| spoke_thread_standard_unknown | spoke | unknown | — | Sin designación publicada, la rosca queda desconocida: no se deriva de 14G. |

Campos que dependen de identidad o posición: extremos del amortiguador, rodamientos de dirección por extremo, alojamientos del cuadro por extremo, envolvente de horquilla por rueda, mazas aceptadas por puntera y configuraciones de neumático por variante. Todos usan `unique_by` sobre esa identidad.

## 6. Fuentes

| Id | Fuente | Grado | Forma del dato que exige |
|---|---|---|---|
| S-CONTI-HOOKLESS | Continental — Hookless vs. Hooked Rims | oem_page (citada en la revisión W del 2026-09-06; no releída en esta ronda) | El límite depende de la variante del neumático y del perfil de la llanta: GP 5000 S TR 700×28c en hookless queda en 23 mm internos y 5,0 bar; 700×30c en 25 mm y 4,5 bar. Manda el menor de los dos componentes. |
| S-ZIPP-TUBE | Zipp — cámara en llanta hookless con neumático tubeless | oem_page (citada en la revisión W; no releída) | El método de montaje (con cámara) no elimina el requisito de neumático tubeless en hookless: método y perfil son ejes distintos. |
| S-SHELDON-TIRE | Sheldon Brown — Tire Sizing | reference_general | BSD es el código de asiento; la guía histórica ancho/llanta es orientación, no homologación. |
| S-PARK-TUBELESS | Park Tool — Tubeless Tire Compatibility | reference_general | Compatibilidad tubeless se declara por par llanta/neumático, no por un booleano de un lado. |
| S-ROCKSHOX-FIT | RockShox — Rear Suspension Fitment | oem_page (citada en la revisión W; no releída) | Aviso de posible contacto del depósito RC2T con Specialized Demo 2020+ al comprimir; variantes por modelo/talla; carrera del amortiguador ≠ recorrido de rueda. |
| S-ENDURO-MAX | Enduro Bearings — Help Center, MAX de pivote en mazas | oem_page (citada en la revisión W; no releída) | Misma envolvente ID/OD/ancho con construcción y destino distintos: MAX de pivote desaconsejado en maza por retención de bolas, sellado y cargas. |
| S-CANECREEK-40 | Cane Creek — Forty, especificación y selectores | oem_page (citada en la revisión W; no releída) | Pares de ángulo 36×45 y 45×45; conjuntos superiores, inferiores y completos; códigos 62/40 y 49/38.1. |
| S-CANECREEK-HS | Cane Creek — Everything you need to know about Headsets | oem_page (citada en la revisión W; no releída) | Un tubo de 44 mm admite ZS44/28.6 + EC44/30 y ZS44/28.6 + ZS44/30: el alojamiento no queda descrito por el SHIS del conjunto original. |
| S-PARK-HEADSET | Park Tool — Headset Standards | reference_general | Diámetro de alojamiento, de cazoleta y de rodamiento se publican en columnas distintas. |
| S-FOX40-2013 | FOX 2013 — Installing the 40 (manual) | oem_manual (citado en la revisión W; no releído) | Columna 40 mm/26": neumático inflado ≤694 mm de pico, ≤670 mm de borde, ≤71 mm de ancho; corona direct mount con stack total 105–166,8 mm. Límites de esa generación. |
| S-SURLY-PACKRAT | Surly — Pack Rat, ficha y framesheet 85-000633_INST_A | oem_manual (citado en la revisión W; no releído) | Espaciado Gnot-rite de 132,5 mm entre punteras que admite mazas de 130 o 135 mm, por diseño de ese cuadro. |
| S-PARK-TAP | Park Tool — TAP-TA-SET (juego de machos de eje pasante) | reference_general | El juego enumera M12×1,0/1,5/1,75 y M20×1,0/1,5/1,75. |
| S-ROBERTAXLE-LIG601 | Robert Axle Project — LIG601 | oem_page (citada en la revisión W; no releída) | 12 mm × 174 mm × 1,75: la longitud del eje es un dato distinto del estándar de maza. |
| S-SAPIM | Sapim — folleto 2018, p. 8, párrafo «Thread» | oem_manual (citado en la revisión W; no releído) | La rosca se lamina, no se corta; la del radio estándar de 2 mm se denomina FG 2.3 mm. |
| S-SHELDON-SPOKE | Sheldon Brown / John Allen — Measurements for Spoke-Length Calculations | reference_general | El margen depende del método de cálculo, la compensación por tensado y el niple; no hay ±1 mm universal. |
| S-ENGINE | Motor real: product_spec_rows.dart, product_spec_template_rules.dart, product_spec_coherence.dart, migración 0200 desplegada | structural (lectura de código 2026-09-07) | Condiciones sólo sobre escalares; sin condiciones por celda (2200 local, no publicado); vínculos entre filas por row.id dentro de un producto; pares escalares con misma unidad. |
| S-BASE | Catálogo integrado all-family-reviewed-fields-integrated-2026-09-07.json (f3178bd3c860c421…) | structural | Estado real de campos, roles y contratos tras integrar A y B. |

## 7. Compuertas

- Ninguna definición nueva de este paquete existe en la base: todas son origin new y no exigen migración de hechos.
- WSS-W07-fork-stack-pair se aplica en la misma migración que los dos campos de stack, o el guard rechaza la plantilla.
- La migración 2200 (row_conditions) está local y en revisión: ningún parche de este paquete la requiere.
- Los consumidores deben leer columnas de filas antes de que el detalle migre a filas (E5): compuerta técnica, no tarea del dueño.
- Ningún parche autoriza llenado, asignación ni publicación.

Verificación de preimágenes: sin discrepancias.


| wheels-steering-suspension-implementation-packet-2026-09-07.json | `c03ebe91fa7e56d32ffb44a0a6ba3b00a4ff917b296068773e2a95027444b3bd` |
