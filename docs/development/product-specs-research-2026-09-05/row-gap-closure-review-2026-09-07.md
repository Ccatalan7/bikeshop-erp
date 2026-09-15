# Cierre de carencias de row_conditions

Claude, revisor independiente · 2026-09-07

Los 18 campos con `disposition = gap` de la propuesta, contrastados contra el catálogo vigente y las capacidades hasta 2500. No propongo arquitectura nueva. Sólo lecturas de código y artefactos y pruebas puras de validadores: sin base de datos, sin runtime, sin cambios de catálogo ni de productos. Los dos defectos abiertos de la propuesta de neumáticos quedan como estaban.

## Resultado

| Cuenta | Valor |
|---|---|
| campos revisados | 18 |
| instancias de carencia (campo × laguna) | 50 |
| resueltas con evidencia | 1 |
| cerrables ahora con corrección mínima | 2 |
| requisito de dato OEM, no defecto de motor | 31 |
| defecto de motor abierto | 16 |
| defectos de motor distintos | 2 |
| campos con algo cerrado o cerrable | 3 |
| esquemas que cambiaron desde la propuesta | 1 |

Las 16 instancias abiertas provienen de **dos** defectos: la falta de un predicado de presencia (12 campos) y la imposibilidad de leer una columna del miembro enlazado (4 campos). Las 31 restantes no son defectos del motor: son matrices OEM, identidad por producto, discriminadores estructurados que faltan y evidencia por afirmación.

## Qué cambió en el motor desde la propuesta

| Capacidad | Estado | Evidencia |
|---|---|---|
| row_conditions con allowed_when, required_when, allowed_options y value_when | vigente | product_spec_row_condition_metadata.py:151 |
| value_when, aserción tipada condicional | vigente y en uso | Dos entradas integradas: seatpost/seatpost_saddle_configurations.clamp_included y accessory_mount/bar_clamp_configurations.included, las dos con expected booleano true. Cierra la laguna G02 de la propuesta, que no afecta a ninguno de los 18. |
| cardinalidad de filas contra un total declarado | vigente, activada en una plantilla | row_coherence version 2 con cardinalities en crankset; row_cardinality_conflict bloquea y row_cardinality_pending no. |
| enlaces row_coherence | vigente | Resuelven el id del destino; no proyectan sus columnas. |
| predicado de presencia o al-menos-uno | ausente | OPERATORS = {eq, in, lt, lte, gt, gte}. |
| predicado sobre una columna del miembro enlazado | ausente | Las condiciones de fila sólo leen columnas de su propia fila. |

## Lo que sí cierra

### Resuelto — `security_rating_configurations` (lock), laguna G06

Es el único de los 18 cuyo esquema cambió: pasó de 8 a 9 columnas con `rating_scheme`, y la plantilla `lock` declara `required_when` sobre esa columna. El caso ejecutable actual `rnd_root_security_programme_missing` espera `row_required_missing` no bloqueante cuando la fila no la trae, y `rnd_root_two_security_programmes` fija que dos programas del mismo componente conviven. Sus otras dos lagunas, G03 y G07, siguen siendo requisito de dato.

### Cerrables ahora — `light_mode_configurations` y `power_port_configurations`, laguna G09

La capacidad de cardinalidad existe y está activada en `crankset`. Las dos plantillas ya declaran su total: `light.modes_count` y `consumer_electronics.ports_count`. Corriendo `validate_row_cardinalities` sobre el catálogo 934 aislé exactamente qué falta:

| Intento | Resultado |
|---|---|
| `light` tal como está hoy, version 1 | RECHAZA: «Invalid row coherence metadata» |
| `light` en version 2, reglas actuales del total | RECHAZA: «Row total requires a nonnegative integer domain» |
| `light` en version 2, total con `{min:"1", integer:true}` | ACEPTA |
| `consumer_electronics` en version 2, total con `{min:"1", integer:true}` | ACEPTA |
| `crankset` tal como está hoy (control) | ACEPTA |

La corrección mínima es de metadatos y no toca el motor: subir `row_coherence` a `version 2` y darle al total un dominio entero con mínimo no negativo. `{min: "1", integer: true}` conserva el significado; `min "0"` también pasaría pero abriría el dominio al cero. Los casos `PCB-C03` (conflicto bloqueante con más filas que el total) y `PCB-C04`, `PCB-C06`, `PCB-C07`, `PCB-C11`, `PCB-C14` (pendiente no bloqueante con menos) ya prueban que el mecanismo no deriva el total de las filas, que es justo lo que la integración de luces exige.

## Los dos defectos que siguen abiertos

### G01 — Presencia y alternativas de columnas (12 campos)

*Reproducción mínima.* validate_row_conditions sobre rack_basket/rack_mount_configurations con un predicado {operator: 'exists'} devuelve «Foreign or mistyped row prerequisite». El conjunto de operadores del contrato sigue siendo {eq, in, lt, lte, gt, gte} en scripts/inventory/product_spec_row_condition_metadata.py:10.

*Corrección mínima.* Un predicado de presencia evaluado por hasKnownSpecValue, más un grupo «al menos una de estas columnas». Dos avisos que ya sé y que la corrección tiene que respetar: hasKnownSpecValue trata «Desconocido / sin confirmar» como ausencia, así que presencia significaría «hay un valor conocido»; y un al-menos-uno no puede escribirse como dos required_when mutuos, porque el validador de contrato rechaza el ciclo. No diseño aquí la regla.

*Representación frente a certificación.* Es un límite de expresión, no una certificación: hoy la ficha no puede decir «falta al menos uno de estos datos» y por eso el hueco queda invisible, no autorizado.

*Campos afectados:* `pedal_bearing_configurations`, `eyewear_lens_configurations`, `fastener_kit_members`, `light_mode_configurations`, `rack_top_interface`, `rack_mount_configurations`, `bag_rack_interface`, `bag_member_configurations`, `brake_hydraulic_connections`, `brake_bleed_ports`, `rim_brake_mount_fitments`, `brake_assembly_configurations`.

### G04 — Predicados sobre un miembro enlazado (4 campos)

*Reproducción mínima.* validate_row_conditions sobre light/light_mode_configurations con un predicado sobre battery_kind —columna de light_member_configurations, el destino del enlace light_member_link— devuelve «Foreign or mistyped row prerequisite». El enlace existe en el catálogo 934 y resuelve el id, pero ninguna condición proyecta columnas del miembro.

*Corrección mínima.* Permitir que un predicado nombre una columna del destino a través del enlace ya declarado, evaluada contra la fila que ese enlace resuelve. No copiar hechos a filas hermanas ni usar nombres como join, que es lo que la laguna original ya prohibía.

*Representación frente a certificación.* El enlace certifica que el miembro existe; no proyecta sus datos. Sin esa proyección, una exigencia que dependa del miembro no se puede escribir y tampoco se puede dar por cumplida.

*Campos afectados:* `light_mode_configurations`, `sensor_support_configurations`, `power_port_configurations`, `brake_hydraulic_connections`.

## Los 18, uno por uno

| Campo | Plantillas | Lagunas | Estado |
|---|---|---|---|
| `bottom_bracket_required` | 1 | G03, G06 | requisito_de_dato_oem |
| `wheel_configurations` | 1 | G03, G06 | requisito_de_dato_oem |
| `pedal_bearing_configurations` | 1 | G01, G06 | defecto_abierto, requisito_de_dato_oem |
| `eyewear_lens_configurations` | 1 | G01, G03 | defecto_abierto, requisito_de_dato_oem |
| `fastener_kit_members` | 1 | G01, G06 | defecto_abierto, requisito_de_dato_oem |
| `light_mode_configurations` | 1 | G01, G04, G05, G09 | cerrable_ahora, defecto_abierto, requisito_de_dato_oem |
| `sensor_support_configurations` | 1 | G03, G04, G05, G06 | defecto_abierto, requisito_de_dato_oem |
| `power_port_configurations` | 1 | G04, G06, G09 | cerrable_ahora, defecto_abierto, requisito_de_dato_oem |
| `security_rating_configurations` | 1 | G03, G06, G07 | requisito_de_dato_oem, resuelto |
| `rack_top_interface` | 1 | G01, G03, G06 | defecto_abierto, requisito_de_dato_oem |
| `rack_mount_configurations` | 1 | G01, G03, G06 | defecto_abierto, requisito_de_dato_oem |
| `bag_rack_interface` | 1 | G01, G03, G06 | defecto_abierto, requisito_de_dato_oem |
| `bag_member_configurations` | 1 | G01, G05, G09 | defecto_abierto, requisito_de_dato_oem |
| `certification_configurations` | 2 | G03, G06, G07 | requisito_de_dato_oem |
| `brake_hydraulic_connections` | 7 | G01, G03, G04 | defecto_abierto, requisito_de_dato_oem |
| `brake_bleed_ports` | 2 | G01, G03 | defecto_abierto, requisito_de_dato_oem |
| `rim_brake_mount_fitments` | 2 | G01, G03 | defecto_abierto, requisito_de_dato_oem |
| `brake_assembly_configurations` | 3 | G01, G03, G06, G09 | defecto_abierto, requisito_de_dato_oem |

El JSON lleva, por campo y por laguna, el id de definición, la reproducción cuando está abierta, la evidencia de metadatos y el caso ejecutable cuando cierra, y la corrección mínima.

## Lo que no hice

- No inventé ninguna regla mecánica: los dos defectos abiertos quedan descritos por su forma mínima, no diseñados.
- No usé ninguna prueba como fuente OEM. Los casos ejecutables se citan como prueba de comportamiento del motor, nunca como evidencia de un producto.
- No toqué diseños de neumático ni reabrí lo que las integraciones posteriores ya corrigieron.
- No propuse cardinalidad donde no hay un total declarado que enlazar: `bag_member_configurations` y `brake_assembly_configurations` siguen siendo carencia de dato.

## Compuertas

Publicación, llenado, asignación y aprobación mecánica siguen en `false`.
