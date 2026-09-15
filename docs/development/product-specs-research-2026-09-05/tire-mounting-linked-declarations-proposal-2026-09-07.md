# Declaraciones de montaje y cifras de presión enlazadas

Claude, revisor independiente de representación · 2026-09-07

Propuesta local. No adjudica, no asigna, no llena y no publica. Conservar dos declaraciones en conflicto no aprueba ninguna, y ningún estado pendiente es un permiso mecánico. No se toca compilador, catálogo, código, pruebas de root, base de datos ni runtime; el contrato local de cardinalidad es de otro revisor.

## Sobre qué se construyó

| Artefacto | SHA-256 | Verificado |
|---|---|---|
| all-family-evidence-scopes-integrated-2026-09-07.json | `e709158d0ac49603ab01dfde19326d1f9f2fd0d0ce50723cb5d0076390226d9d` | sí |
| all-family-evidence-scopes-cases-integrated-2026-09-07.json (302 casos) | `456946a2bb7b2ca23bb9decc77a729a5f157eec7ce983f27d8f0aaaeab5b884e` | sí |

Confirmé en esta base que la tabla general de TPDU está integrada, que R6 sigue sobre `tire_rim_configurations`, que `tire` todavía no tiene bloque `row_coherence` y que las cuatro familias que ya usan enlaces son luz, electrónica y los dos frenos.

## Por qué tu rechazo era correcto

No discuto la decisión: la refuerzo con la razón que yo no había visto. Mi F4 admitía declaraciones legítimas adicionales por sub-rango o condición, así que estaba pidiendo una prohibición apoyada en que yo no las encontré en dos sitios. Eso ya bastaba. Pero lo más grave es lo segundo que dijiste: «dos veces en un documento es un error» no es una regla mecánica. Es una hipótesis editorial, y una clave que la impone convierte un juicio en un veto.

## La arquitectura

Dos tablas y un enlace, con el motor que ya existe.

```
tire_declared_pressures.declaration_row_id  ──►  tire_mounting_declarations (row.id)
    qué cifra es, unidad, valor              rótulos: perfil, método, condiciones, documento
```

La celda del enlace guarda el **id de la fila** de destino: lo comprobé en el validador, que resuelve con `target.rows.any((r) => r.id == value)`. Las columnas de rótulo son las que el formulario muestra para elegir la declaración, así que el dueño no escribe ids a mano.

**La identidad es la fila.** El parser ya exige ids únicos dentro del campo y el enlace resuelve por ese id. Ninguna de las dos tablas lleva `unique_by`, a propósito: no hay ninguna combinación de columnas que pueda identificar una declaración sin prohibir otra legítima. Es la misma corrección que me hiciste sobre `member_revision` hace varias rondas.

**El alcance vive una sola vez.** La declaración lleva sujeto, condiciones, límites de ancho y documento; la cifra lleva sólo qué cifra es, su unidad y su valor, y hereda el resto por el enlace. Dos unidades del mismo máximo son dos filas que apuntan a la misma declaración, así que el ancho no se duplica y el documento tampoco.

### Declaraciones de montaje

| Columna | Tipo | Requerida |
|---|---|---|
| rim_bead_profile | token | sí |
| mounting_method | token | sí |
| condition_scope | token | sí |
| declared_conditions | text | no |
| rim_internal_width_min_mm | decimal | no |
| rim_internal_width_max_mm | decimal | no |
| source_document | text | sí |
| source_url | url | no |

### Cifras de presión

| Columna | Tipo | Requerida |
|---|---|---|
| declaration_row_id | text | no |
| quantity_kind | token | sí |
| pressure_unit | token | sí |
| pressure_value | decimal | no |
| source_url | url | no |

## Lo que evalué

### F1 · Tenías razón en rechazar mi clave.

**Dos veces, y por dos razones distintas.**

La primera: mi propio F4 admitía declaraciones legítimas adicionales por sub-rango, carga u otra condición, y no haberlas encontrado en dos sitios no prueba que sean imposibles. Estaba pidiendo que aceptaras una prohibición apoyada en una búsqueda mía. La segunda es peor y es la que no había visto: «dos veces en un documento es un error» no es una regla mecánica, es una hipótesis editorial. Un documento puede declarar dos veces el mismo perfil y método bajo condiciones distintas y estar bien. Una clave que lo prohíbe convierte un juicio en un veto.

### F2 · ¿Cuál es entonces la identidad estable de una declaración?

**Su propia fila.**

El parser ya exige que los id de fila sean únicos dentro del campo, y el motor de enlaces resuelve por ese id: la celda del enlace guarda el id de la fila de destino y el validador comprueba que exista. La identidad ya está ahí y es estable. Ninguna combinación de columnas necesita fingir que identifica. Esto es lo mismo que me corregiste sobre member_revision hace varias rondas: row.id ya da identidad, y un unique_by no justifica inventar un dato.

### F3 · ¿Cómo queda el alcance completo?

**En la declaración, y las cifras lo heredan por el enlace.**

La declaración lleva sujeto, condiciones, límites de ancho y documento; la cifra lleva sólo qué cifra es, su unidad y su valor. El alcance no se repite en cada cifra, así que no hay dos dueños del ancho ni del documento, y las dos unidades de un mismo máximo son dos filas que apuntan a la misma declaración.

### F4 · ¿Cómo se representan varias declaraciones del mismo documento?

**Como varias filas, sin nada que las impida.**

Sin unique_by no hay tope. Lo que las distingue para el operador es la columna de condiciones declaradas, y el formulario las muestra por sus columnas de rótulo cuando hay que elegir una para enlazar. Hay un caso real en el mismo documento de Continental: declara el montaje sin gancho con cifras y, para el montaje con gancho, remite al envase. Son dos declaraciones legítimas del mismo documento.

### F5 · ¿Y la ausencia de unidad o de fuente?

**Pendiente, nunca permiso.**

Una cifra sin declaración enlazada no hereda documento ni condiciones: la condición «toda cifra pide su declaración» la deja pendiente por fila y por columna. Una cifra sin unidad queda con requisitos por confirmar. Una unidad declarada desconocida deja la fila incompleta. Ninguno de esos estados autoriza nada: son huecos visibles, no permisos. Mantengo el nivel correcto en la fixtura de token desconocido, sin rebajarla al comportamiento que el servidor corrige en 2500.

### F6 · ¿Qué se pierde al separar en dos tablas?

**La mitad de R6 y la detección de declaraciones sin cifras. Lo digo antes de que lo pruebes.**

R6 exigía dos cosas a un montaje sin gancho: su ancho interior máximo y su unidad de presión. Lo primero cruza intacto a la tabla de declaraciones. Lo segundo ya no se puede expresar: la unidad vive ahora en otro campo y ninguna condición de fila cruza de campo. Y el motor de enlaces recorre las filas de origen, así que una declaración sin ninguna cifra enlazada no emite nada; lo comprobé leyendo el validador y lo dejo como fixtura con esa expectativa. Es el precio de la arquitectura que pediste, y no propongo ningún mecanismo nuevo para taparlo.

### F7 · ¿Y la discrepancia entre documentos?

**Se conserva entera, y conservar no es aprobar.**

Dos documentos son dos declaraciones con sus propias cifras. El motor no elige entre ellas, no marca ninguna errónea y no deriva nada de que convivan. El desempate es humano y la ficha lo muestra como lo que es: evidencia en conflicto, no un dato aprobado.

### F8 · Sobre el documento y su edición.

**Se anota el documento como se leyó, no una edición certificada.**

Retiraste bien mi atribución: el «2014» del título de Schwalbe es parte del nombre comercial del artículo y no acredita una edición documental. Ninguna de las páginas que leí certifica edición. Por eso la columna se llama «documento que declara, como se leyó» y su ayuda dice que no se afirma una edición que el editor no certifique.

### F9 · ¿Por qué retirar el dueño anterior y no dejarlo convivir?

**Porque serían dos dueños del mismo hecho.**

Dejarlo activo permitiría declarar el mismo montaje en dos lugares sin ninguna regla que los compare. Pasa a legado, que en este motor significa que el validador descarta sus valores antes de validar: el contenido queda intacto, sin reinterpretarse y sin borrarse. Su entrada en row_conditions se retira porque el validador rechaza condiciones sobre un campo legacy, no porque la regla estorbe.

### F10 · ¿Sobre Sheldon y Park?

**Quedan como contexto, con su límite escrito.**

Sirven para separar lo físico de lo declarado: el calce lo decide el diámetro de asiento y el lecho de la llanta es una realidad. Pero su guía de anchos es histórica y general, no sustituye el máximo que el fabricante publica por variante, y nombrar la norma ETRTO no vuelve no documental a esa norma. Lo dejé anotado en cada fuente.

## Los cinco parches

| Id | Operación | Objetivo |
|---|---|---|
| TMLD-01-mounting-declarations | `add_field` | `tire` / `tire_mounting_declarations` |
| TMLD-02-declared-pressures | `add_field` | `tire` / `tire_declared_pressures` |
| TMLD-03-retire-previous-owner | `replace_field_contract` | `tire` / `tire_rim_configurations` |
| TMLD-04-row-conditions | `replace_template_coherence` | `tire` / `row_conditions` |
| TMLD-05-link | `replace_template_coherence` | `tire` / `row_coherence` |

### TMLD-01-mounting-declarations

El destino del enlace. Una fila es una declaración completa: sujeto, condiciones, límites de ancho y documento. Sin unique_by: la identidad es la fila, que ya es única por construcción del parser, y ninguna combinación de sus columnas pretende identificarla.

*No se afirma* que el contexto identifique al SKU. Perfil, método, condiciones y documento describen el alcance de lo declarado; no dicen qué producto es.

### TMLD-02-declared-pressures

El origen del enlace. Una fila es una cifra impresa con su unidad y qué cifra es. Varias filas pueden apuntar a la misma declaración: dos unidades del mismo máximo, o un máximo y un mínimo. Sin unique_by, por lo mismo que la tabla de declaraciones.

*No se afirma* que la unidad se pueda convertir, ni que dos filas de la misma declaración con la misma unidad sean necesariamente un error.

### TMLD-03-retire-previous-owner

El dueño anterior pasa a legado para que no haya dos dueños del mismo hecho. validateProductSpecDraft descarta los valores de campos legacy antes de validar: el contenido se conserva intacto, no se reinterpreta y no se borra. Los metadatos aún son inéditos y no hay hechos reales que migrar en la base.

*No se afirma* que el contenido anterior se traduzca solo. La migración es explícita y sus fixturas la muestran fila por fila.

### TMLD-04-row-conditions

Retira la entrada del campo retirado, porque el validador rechaza condiciones sobre un campo legacy, y la vuelve a expresar sobre el nuevo dueño: una declaración sin gancho sigue pidiendo su ancho interior máximo. Añade que una cifra exige su unidad y que toda cifra pide su declaración. La entrada de la tabla de máximos generales se conserva palabra por palabra.

*No se afirma* que R6 sobreviva entero. Su otra mitad —que un montaje sin gancho traiga su unidad de presión— cruzaba de campo y ninguna condición cruza campos. Ver F6.

### TMLD-05-link

El enlace que ya usan luz, electrónica y frenos: la celda de la fila de presión guarda el id de la fila de declaración, y las columnas de rótulo son las que el formulario muestra para elegirla. El dueño no escribe ids a mano.

*No se afirma* que el enlace detecte una declaración sin cifras. El motor recorre las filas de origen, así que una declaración huérfana no emite nada. Ver F6.

## Huecos conocidos, medidos

| Id | Qué falta |
|---|---|
| G-R6-half | La mitad de R6 que exigía la unidad de presión a un montaje sin gancho no sobrevive: cruzaría de campo y ninguna condición cruza campos. |
| G-orphan-declaration | Una declaración sin ninguna cifra enlazada no produce incidencia alguna. |
| G-server-unknown-token | El servidor omite hoy el row_incomplete del token desconocido; se corrige en 2500. La fixtura conserva el nivel correcto y no el actual del servidor. |

El segundo lo comprobé corriendo, no leyendo: en la fixtura del documento que declara sin gancho con cifras y con gancho remitiendo al envase, la declaración sin cifras enlazadas no produce ninguna incidencia. No propongo ningún mecanismo nuevo para taparlo.

## Fundamento, con su límite

| Id | Qué aporta | Qué no |
|---|---|---|
| S-CONTI-US | GP 5000 S TR «700 x 28c»: «5.0 \| 72» y 23 mm de ancho interior máximo, para montaje sin gancho. Y sobre el montaje con gancho remite al envase, advirtiendo que el máximo «may differ between hooked and hookless applications». Un mismo documento declarando dos montajes de distinta manera. | — |
| S-CONTI-B2C | El mismo fabricante en otro documento designa en ETRTO —«28-622»— y declara las mismas cifras, «5.0 \| 72» y 23 mm. Ninguno de los dos certifica una edición. | — |
| S-SHELDON-SIZING | Contextual. El calce lo decide el diámetro de asiento: «Generally, if this number matches, the tire will fit onto the rim». Su relación de anchos es «a general guideline» y su tabla «may err a bit on the side of caution». | Es guía histórica de anchos: no sustituye el máximo OEM de una variante y no prueba que una norma sea o deje de ser documental. |
| S-PARK-TUBELESS | Contextual. El lecho con gancho «helps catch and hold the bead», y el sistema descansa en «tolerances outlined in the ETRTO standards». | Nombrar una norma no la vuelve no documental: la norma también se lee en un documento y no reemplaza lo que el fabricante declara por variante. |

## Ensayo local

Los cinco parches pasan por `apply_reviewed_field_addendum` con `validate_contract` en verde y `publication_gates` sin cambios. Las doce fixturas corrieron contra `validateProductSpecDraft` con el catálogo parchado, con cero discrepancias; `observed_in_local_trial` es la salida literal del motor. La sonda vivió en un archivo temporal que ya borré.

## Fixturas

| Id | Tipo | Qué fija |
|---|---|---|
| tmld_migration_one_row_becomes_one_declaration_and_two_figures | migration_explicit | La migración explícita de la fila original de Continental: una declaración con su ancho máximo y su documento, y dos cifras enlazadas, 5.0 bar y 72 psi. El cont… |
| tmld_original_alone_is_preserved_and_silent | migration_explicit | Antes de migrar, el original se conserva y deja de gobernar el formulario. Ninguna incidencia lo nombra. |
| tmld_same_document_declares_hookless_and_defers_hooked | válido | Real y verificable: un mismo documento de Continental declara el montaje sin gancho con cifras y, para el montaje con gancho, remite al envase. Son dos declarac… |
| tmld_two_declarations_same_document_same_subject | synthetic_subrange_shape | La forma que mi clave rechazada habría bloqueado: un mismo documento declarando dos veces el mismo perfil y método, separados por un sub-rango de ancho. Aquí co… |
| tmld_figure_without_declaration_is_pending | desconocido | Ausencia de fuente y de alcance: una cifra sin declaración enlazada no hereda documento ni condiciones, y queda pendiente. No bloquea, y tampoco vale como dato … |
| tmld_figure_pointing_to_a_missing_declaration_blocks | contradictorio | Un enlace que apunta a una declaración inexistente sí es un error y bloquea. |
| tmld_figures_before_any_declaration_are_pending | desconocido | Sin ninguna declaración cargada todavía, el enlace queda pendiente y no bloquea: el motor distingue «aún no existe el destino» de «apunta a algo que no está». |
| tmld_unknown_unit_is_pending_not_permission | known_server_gap | Unidad declarada desconocida: la fila queda incompleta y la cifra pendiente. No es permiso mecánico para nada. El cliente Dart lo marca; el servidor hoy omite e… |
| tmld_value_without_unit_is_pending | desconocido | Una cifra sin unidad queda con requisitos por confirmar, igual que en las otras tablas. |
| tmld_hookless_declaration_still_requires_its_max_width | r6_regression | La mitad de R6 que sí cruza a la nueva tabla: sin gancho pide su ancho interior máximo. |
| tmld_documentary_discrepancy_is_preserved_not_approved | documentary_conflict_pending | Los dos documentos de Continental para el 28-622, cada uno con su declaración y sus dos cifras. Conservarlos no es aprobarlos: el motor no elige entre declaraci… |
| tmld_reversed_width_range_still_blocks | contradictorio | ordered_pairs viaja con la tabla nueva: un rango invertido sigue siendo imposible. |

Las dos primeras son la migración explícita: el contenido original viaja intacto en el campo retirado, el validador no lo interpreta ni lo emite, y al lado está su traducción a una declaración con dos cifras enlazadas. Las cifras reales son de los dos documentos de Continental que leí hoy; lo sintético está marcado como sintético y sin atribuir.

## Compuertas

Publicación, llenado, asignación y aprobación mecánica siguen en `false`. Ninguna familia queda certificada.
