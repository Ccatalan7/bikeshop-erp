# Coherencia de filas — diagnóstico y gramática mínima cerrada (2026-09-07)

Propuesta independiente, no implementada. El JSON `row-coherence-proposal-2026-09-07.json` es la fuente (incluye fixtures que el generador evaluó con la semántica propuesta). No toca addenda, Dart, SQL, compilador, productos, DB, runtime ni git. No declara fill listo.

## 1. Qué garantizan hoy las filas y por qué se cuelan los cuatro casos

- product_spec_rows.dart / spec_rows_validate_internal_v1: forma (id, values, sources), tipos de celda text|token|decimal|integer|boolean|url, números como string exacta, dominio positive/min/max, opción dentro de allowed_values, URL por fila, ordered_pairs dentro de la fila, unique_by entre filas del mismo campo.
- missingRequired / row_incomplete: celda requerida ausente = incompleto, no bloqueante (Dart y SQL coinciden).
- Cada campo de filas es UN hecho (spec_facts.value_json) por producto y definición; source/confirmed/readings viven por hecho, no por fila; cada fila lleva sus propias URLs.
- spec_rows_fact_guard valida un hecho aislado: no ve los demás campos del mismo producto. spec_write_payload_internal_v2 sí tiene el payload completo (referencia + valores explícitos) antes de escribir y es una sola función: la escritura ya es atómica.
- Condiciones rules_version 2 (product_spec_template_rules.dart / spec_template_condition_internal_v1): predicados sólo sobre escalares token|decimal|boolean; el guard de metadatos rechaza un predicado sobre un campo json. Una fila no puede mirar un escalar y un escalar no puede mirar una fila.
- ProductSpecRowsField: edita una fila a la vez; el selector muestra «Configuración N» con las tres primeras celdas; el id de fila es un UUID v4 opaco generado por el widget; una celda text es texto libre; no existe forma de elegir «una fila de otro campo».
- spec_validate_draft_internal_v1 y validateProductSpecDraft son el lugar donde ya se comparan campos entre sí (range_order entre dos escalares) y donde se distingue bloqueante de pendiente.
- spec_rows_definition_guard: cambiar rows_schema de una definición con hechos guardados exige migración explícita; hoy las definiciones de los addenda no tienen hechos.

| Caso observado | Por qué se cuela |
|---|---|
| budget_row_names_unknown_port | power_budget_configurations.port_id y power_port_configurations.port_id son dos columnas text independientes: coinciden sólo por disciplina del operador. Nada declara que la primera se resuelva en la segunda. |
| ant_plus_row_with_ant_plus_false | sensor_link_ant_plus (boolean) duplica lo que ya dice la fila transport=ANT+. Un resumen escalar almacenado de un campo de filas siempre puede contradecir a las filas; ninguna condición puede leer las filas para impedirlo. |
| t25_token_with_torx_size_30 | head_drive codifica un tamaño dentro de un token («Torx T25») y torx_size lo repite como número: dos campos escalares que dicen lo mismo con tipos distintos. constraint_rules sólo restringe campos de elección, no números, así que ni el esquema actual ni las condiciones pueden atarlos. |
| mode_row_names_unknown_light | light_mode_configurations.member_id y light_member_configurations.member_id son text sin relación declarada: mismo defecto que el presupuesto. |

### Tres cosas que no se confunden

| Clase | Definición |
|---|---|
| referential_integrity | Una fila menciona una fila de otro campo de la MISMA ficha que no existe. Es una contradicción interna de la ficha (bloquea) sólo cuando el conjunto destino existe; si el conjunto destino está vacío o ausente, es dato incompleto (pendiente). |
| incomplete_data | Celda requerida ausente, conjunto destino aún sin filas, escalar prerrequisito sin confirmar. Nunca bloquea el guardado; se muestra como pendiente. Una fila ausente jamás es prohibición. |
| physical_incompatibility | Afirmación sobre dos piezas/interfaces. No sale de la coherencia de filas: sale de relaciones con fuente (20260906180000) por interfaz, con modelo/generación, y su ausencia es desconocido. Este contrato no la produce ni la niega. |

## 2. Gramática mínima cerrada: un constructo nuevo

**`references`** en `rows_schema.columns[i].references (clave opcional de la columna)`: `{"field": "<clave de otro campo de filas de la misma ficha>", "column": "<columna del campo destino>"}`; tipos de columna admitidos: text, token sin allowed_values.

Restricciones de metadatos:
- field ≠ el propio campo; el campo destino existe en TODA plantilla que incluya al campo que referencia (guard de plantilla), su definición es json con rows_schema y su rol no es legacy.
- column existe en el rows_schema destino, es text o token, y aparece como grupo de UN solo elemento en unique_by del destino (así una igualdad identifica exactamente una fila).
- La columna destino no declara references (sin cadenas ni ciclos).
- La columna que referencia puede ser required o no; si no está, aplica row_incomplete como hoy.

Evaluación (idéntica en Dart y SQL):
- Para cada fila r del campo F con columna c que declara references R: si r.values[c] no existe → nada (row_incomplete cubre lo requerido).
- Sea T = values[R.field] en el mismo borrador (payload completo: referencia + explícitos, sin legacy). Si T no existe o no tiene filas → issue row_reference_pending (no bloqueante).
- Si T tiene filas y ninguna t cumple t.values[R.column] == r.values[c] (igualdad exacta de texto) → issue row_reference_unresolved (bloqueante).
- Si existe → sin issue. La referencia sólo prueba que la ficha nombra algo que ella misma define; no prueba montaje ni capacidad.

| Código | Bloquea | Significado |
|---|---|---|
| `row_reference_pending` | no | el conjunto destino aún no tiene filas |
| `row_reference_unresolved` | sí | la ficha nombra una configuración que no define |

### Políticas que se resuelven sólo con el esquema actual (sin capacidad nueva)

| Id | Política | Aplica a |
|---|---|---|
| P1 | Un campo de filas no tiene resumen escalar almacenado. Si una condición necesitara «existe fila con…», eso es una capacidad nueva (predicado exists_row) que hoy NO se propone; se elimina el escalar duplicado y las filas quedan allowed always. | sensor_link_ant_plus / sensor_link_bluetooth / sensor_link_wired (addendum A); cualquier boolean que resuma filas. |
| P2 | Un token no codifica una magnitud que otro campo guarda como número. Se parte en forma (token) + medida (decimal/integer) y el token pierde el tamaño. | head_drive: «Torx T25»/«Torx T30» → «Torx» + torx_size; no están en producción, así que es corrección del esquema propuesto, no migración de datos. |
| P3 | Un conjunto de filas está acotado a modelo/generación/revisión. La ausencia de una fila es desconocido; una exclusión OEM se escribe como fila explícita (supported=false) con su generación. Nunca «no hay fila de 35 mm» ⇒ «no admite 35 mm». | bar_clamp_configurations (Quad Lock Out Front PRO V1/V2), tool_capabilities, freehub rows, light_mode_configurations (Cateye Spec change). |
| P4 | Una columna describe una interfaz de UN objeto: el puerto del dispositivo es del dispositivo; el extremo del cable es del cable. Un vocabulario no mezcla ambos. | light.charge_connector: quitar «USB-A (cable propio)»; el cable incluido va a contenido (kit_members) o a consumer_electronics.connector_a/b. |
| P5 | No existe regla universal suma(max_por_puerto) ≤ total ni max_solo ≥ reparto. Máximo individual, presupuesto compartido dinámico y asignación simultánea exacta son tres significados; se guardan como columnas/filas distintas y NO se comparan automáticamente. | power_port_configurations.max_power_w, power_budget_configurations.power_w, rated_power_w. |

### Qué NO cubre este contrato (a propósito)

- Predicados de condición que lean filas (exists_row / count) — no se propone; si aparece una necesidad real se diseña aparte.
- Comparaciones numéricas entre filas de campos distintos (sumas, presupuestos, tope por puerto) — fuera; ver P5.
- Referencias a filas de OTRO producto (bicicleta ↔ pieza, cable ↔ luz) — eso es una relación de compatibilidad, no coherencia de ficha.
- Aplicabilidad de una celda según otra celda de la misma fila (p. ej. lumens_secondary sólo en modo doble) — las celdas opcionales quedan opcionales.
- Procedencia y confirmación por fila — hoy son por hecho (source/confirmed/readings) y se mantienen; una fila individual no puede quedar «confirmada».
- Completitud de un conjunto compuesto (p. ej. que la combinación «C1 + C2» tenga las dos filas) — se muestra como pendiente por convención del editor, no se valida.
- Cualquier veredicto de compatibilidad física.

## 3. Dónde vive cada responsabilidad

| Capa | Cambio |
|---|---|
| Metadatos (spec_definitions.validation_rules.rows_schema) | Columna con `references {field, column}`. rows_schema.version sigue en 1 (la forma de los datos guardados no cambia). Sólo se agrega a definiciones sin hechos; una definición ya poblada exige la migración explícita que el guard ya impone. |
| Guard SQL de esquema (spec_rows_schema_validate_internal_v1) | Acepta la clave `references` con forma {field:text, column:text}; rechaza references en decimal/integer/boolean/url y en token con allowed_values. |
| Guard SQL de plantilla (spec_template_rules_validate_internal_v1) | Para cada campo de filas de la plantilla con references: destino presente en la plantilla, json con rows_schema, rol ≠ legacy, columna destino existente, en unique_by como grupo unitario, sin references propias. Se ejecuta en los mismos triggers diferidos ya existentes (plantilla, campos, definiciones). |
| Función SQL nueva: spec_rows_references_validate_internal_v1(p_template_id, p_values) → jsonb issues | Única implementación de la evaluación. La usan el validador de borrador (anexa issues), la escritura (bloquea) y el futuro aplicador de llenado (que inserta hechos directamente y por eso NO puede confiar en el trigger por hecho). |
| Validador de borrador SQL (spec_validate_draft_internal_v1) | Anexa row_reference_pending (blocking false) y row_reference_unresolved (blocking true) al arreglo de issues, con `field` = clave del campo que referencia y `row_id` de la fila afectada. |
| Escritura atómica (spec_write_payload_internal_v2) | Tras construir v_payload (referencia + explícitos, sin legacy) y antes del primer delete/insert: si la función devuelve algún issue bloqueante → raise 23514 (toda la escritura se revierte; ya es una transacción). Pendientes no bloquean, igual que hoy row_incomplete. |
| Trigger por hecho (spec_rows_fact_guard) | Sin cambio: no ve hermanos. Se documenta que la integridad referencial se garantiza a nivel payload/plantilla y que cualquier escritor directo de spec_facts debe llamar la función común. |
| Dart: ProductSpecRowColumn.fromJson | Acepta `references` (hoy cualquier clave desconocida lanza «Definición de columna inválida» y la ficha queda ilegible). Debe desplegarse ANTES de que cualquier metadato lleve la clave; si no, los editores viejos muestran el aviso fail-closed y conservan los datos. |
| Dart: validateProductSpecDraft | Misma evaluación que la función SQL, sobre `values` del borrador (ya tiene todos los campos activos). Códigos idénticos; tests de paridad con las fixtures de este documento. |
| UI: ProductSpecRowsField | Una celda con references se renderiza como selector (S-06 VbSearchableSelect) cuyas opciones son los valores de la columna destino en el borrador actual, pasadas por el formulario (nuevo parámetro `referenceOptions: Map<String fieldKey, List<String>>`). Sin texto libre. Un valor que ya no resuelve se muestra como estado de error y se conserva (no se borra solo). El selector de filas muestra primero la columna unique_by para que «USB-C 1» sea el rótulo, no «Configuración 2». |
| UI: orden de edición | El formulario ordena los campos de filas para que el destino aparezca antes que quien lo referencia (sort_order en la plantilla), y avisa «define primero los puertos/las luces» cuando el destino está vacío (row_reference_pending). |
| Procedencia y versiones | Sin capacidad nueva. Cada fila conserva sus URLs; el hecho conserva source/confirmed/readings; spec_revision del producto sube en cada guardado y contract_version/definition_revision invalidan editores abiertos cuando cambia el esquema (triggers existentes). Se declara el límite: no hay confirmación por fila. |
| Orden de despliegue | 1) Dart tolerante + validador + editor con tests; 2) migración SQL (guards + función común + validador + escritura + pgTAP); 3) metadatos: references en las definiciones aún no pobladas (presupuesto→puertos, modos→luces) y correcciones P1–P4 en los addenda adjudicados; 4) recién después, sembrado. Ninguna de estas etapas autoriza fill. |

## 4. Qué requiere capacidad nueva y qué no

| Caso | Resolución | Capacidad nueva |
|---|---|---|
| Presupuesto nombra un puerto inexistente | `references` presupuesto.port_id → puertos.port_id | sí (references + evaluación + selector) |
| Modo nombra una luz no definida | `references` modos.member_id → luces.member_id | sí (la misma) |
| ANT+ en fila con ant_plus=false | retirar los booleanos resumen (P1) | no |
| «Torx T25» con torx_size=30 | token sin tamaño + torx_size (P2) | no |
| Cateye Group Ride «Spec change» | dos filas por revisión, columna revision, sin rango ni modo doble (P3) | no |
| Quad Lock PRO y 35 mm | columna generation + supported; ausencia = desconocido (P3) | no |
| Micro-USB de la luz vs USB-A del cable | vocabulario del puerto sólo del dispositivo (P4) | no |
| Tope por puerto / suma de máximos | no se valida (P5); conflictos van a conflicting_claims | no (y no se propone) |

## 5. Fixtures (positivos, negativos, desconocidos)

| Id | Tipo | Issues esperados | Bloquea | Nota |
|---|---|---|---|---|
| budget_port_resolves | positive | — | no | Anker A2667: cada fila del reparto nombra un puerto definido. No se comprueba 45+20 contra 65 ni contra los máximos individuales (P5). |
| budget_port_unresolved | negative | row_reference_unresolved@power_budget_configurations/r1 | sí | Caso observado: la fila menciona USB-C 2 y la ficha sólo define USB-C 1 → contradicción interna, bloquea el guardado. No dice nada de electricidad. |
| budget_ports_pending | unknown | row_reference_pending@power_budget_configurations/r1 | no | Puertos aún no definidos: pendiente, no bloquea; el editor pide definir los puertos primero. |
| budget_exceeds_port_max_is_not_checked | positive | — | no | Deliberado: 30 W sobre un máximo declarado de 22,5 no es un error de coherencia de filas. Si el OEM lo publica así, se registra y se marca en conflicting_claims; una regla automática inventaría un significado (P5). |
| sensor_rows_without_summary_booleans | positive | — | no | Tras P1 no existe sensor_link_ant_plus: la fila es la única fuente de verdad y la contradicción «ANT+ con ant_plus=false» deja de ser representable. |
| torx_token_without_size | positive | — | no | Tras P2 el token no lleva tamaño; «Torx T25» + torx_size=30 no puede escribirse porque «Torx T25» ya no es opción. Corrección de esquema, sin capacidad nueva. |
| mode_member_resolves_cateye_group_ride_spec_change | positive | — | no | Corrección de fuente: Group Ride no es un rango ni un modo doble; son dos revisiones del mismo modo con nota «Spec change». Se guardan como dos filas (member, mode, revision) y el SKU en stock no se atribuye a ninguna hasta ver su envase. El conector de carga del ViZ300 queda desconocido: «USB-A» era el extremo del cable, no el puerto de la luz (P4). |
| mode_member_unresolved | negative | row_reference_unresolved@light_mode_configurations/r1 | sí | Caso observado: el modo nombra una luz que la ficha no define → bloquea. La ficha tampoco afirma que ViZ300 no exista: sólo que esta ficha no lo definió. |
| mode_members_pending | unknown | row_reference_pending@light_mode_configurations/r1 | no | Luces aún no definidas: pendiente. |
| quadlock_pro_35mm_unknown_without_generation | unknown | — | no | Corrección de fuente: el Out Front PRO depende de V1/V2. Sin fila de 35 mm la respuesta para 35 es DESCONOCIDO (P3), no «no admite». Una negación válida sería una fila 35 / generación exacta / supported=false con fuente. |
| explicit_exclusion_needs_generation_row | negative_shape | — | no | Forma correcta de una exclusión: fila explícita con generación y supported=false; sólo entonces «35 mm» es «no» para ESA generación. |

El generador evaluó cada fixture con references con la semántica de la sección grammar.evaluation y comparó códigos/filas esperados: 0 discrepancias. Los fixtures usan esquemas reducidos (columnas mínimas) y una URL de forma; no son productos del inventario ni hechos guardados.

## 6. Correcciones concretas a los addenda A y B (para la adjudicación)

| Addendum | Objetivo | Cambio |
|---|---|---|
| A | `power_budget_configurations.port_id` | agregar references {field: power_port_configurations, column: port_id}; port_id ya es unique_by unitario en puertos. |
| A | `light_mode_configurations.member_id` | agregar references {field: light_member_configurations, column: member_id}; agregar columna revision (text) y unique_by [member_id, mode, revision]; quitar lumens_secondary/runtime_max_h como representación de «Spec change» (siguen válidas sólo para modos realmente dobles como HyperConstant 800/200). |
| A | `cycle_computer.sensor_link_ant_plus / sensor_link_bluetooth / sensor_link_wired` | retirar de la propuesta (P1); sensor_support_configurations allowed always; speed_source sigue gobernando wheel_setting. |
| A | `head_drive (definición) y torx_size` | quitar «Torx T25» y «Torx T30» de la propuesta (no están en producción); dejar «Torx» + torx_size (P2). |
| A | `light_member_configurations.charge_connector` | quitar «USB-A (cable propio)» del vocabulario (P4); el caso Cateye ViZ300 pasa a Desconocido / sin confirmar; el cable incluido va a kit_members. |
| A | `bar_clamp_configurations` | agregar columnas generation (text, required) y supported (boolean, required); unique_by [nominal_diameter_mm, generation]; el caso Quad Lock PRO deja de negar 35 mm (P3). |
| A/B | `tool_capabilities, certification_configurations, seatpost_saddle_configurations, rack_mount_configurations` | ya llevan modelo/generación o supported; sin cambio. Ninguna de sus filas referencia otro campo. |
| B | `auxiliary_part_requirements.applies_to / bag_member_configurations` | sin references: nombran parrillas de OTRO producto (relación, no coherencia interna). |

## 7. Entradas leídas

| Archivo | SHA-256 |
|---|---|
| lib/modules/inventory/models/product_spec_rows.dart | `68904dbe5a1de7060baf13447c39ed417450be916ce0ebb8efa8a3e206000d59` |
| lib/modules/inventory/models/product_spec_template_rules.dart | `7992bb91c822562cd9fe965ecb924f1c3aefcb537febf09c9a51215dba13e2fc` |
| lib/modules/inventory/models/product_spec_contract.dart | `9c62bb2f5841a2db8b07f9bff3571e7e379df49aa5d35c430000a4232454fb36` |
| lib/modules/inventory/widgets/product_spec_rows_field.dart | `1a744ed6d4ebf5b8926aa75360863d2a24f33be30a02571a1e0a090f6c73fbc6` |
| supabase/migrations/20260906190000_product_spec_structured_rows.sql | `53e0ac8b6313ae226ecba9d6b69aebf16f359223f78698434653836055866483` |
| supabase/migrations/20260906200000_product_spec_field_conditions.sql | `643f526a7dbb2a794373c3a90a169806906abf116a144efdd187832eabe1ecda` |
| supabase/migrations/20260907010000_product_spec_exact_editor_reads.sql | `8c5603bdf7064532b51515af03e1f1fc70b6183396fbb49c8271fd4ce5cc1e4b` |
| docs/.../all-family-field-addendum-2026-09-07.json | `86c7f7d6b7360d01a771f1aaf63ddba0e63352999d65dc4ea78038da58d25440` |
| docs/.../all-family-field-addendum-b-2026-09-07.json | `b43aa4798dab2be7029660efb08dd3836ecfb350ccfb80b97549f53bf7b56b8d` |

| row-coherence-proposal-2026-09-07.json | `ae929527c5957a3a76afdfc59e990219356ffc2c14c83c355bcd074db7561a63` |
