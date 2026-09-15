# Máximos generales de neumático en dos unidades: propuesta de tabla

Claude, revisor independiente de representación · 2026-09-07

Propuesta local. No adjudica, no asigna, no llena y no publica. No toca compilador, catálogo, código, pruebas de root, base de datos ni runtime. Aprobar una representación no aprueba un montaje ni certifica una familia.

## Sobre qué se construyó

| Artefacto | SHA-256 | Verificado |
|---|---|---|
| all-family-contents-integrated-2026-09-07.json | `20a9c1eabdf84dd5e3e9cb5a4a922a695c6e91deff53bebdb2e0c584b5e8edee` | sí |
| all-family-contents-cases-integrated-2026-09-07.json (272 casos) | `f87a94087f0a325d637f58833d61c5568e95cc52bb5e27fd126a1306aa5eb1ae` | sí |
| wss-residual-field-packet-2026-09-07.json (paquete anterior, congelado) | `239ab6607e25f4211f88d5c4998cec25af52d07278d75d983c98f0cfa8b05087` | sí |

Confirmé en esta base que `tire_max_pressure_unit` y `tire_max_pressure_value` no están integrados, que `tire_max_pressure_psi` sigue con rol `declaration` y que `row_conditions` está en su estado anterior a R6. Las preimágenes de abajo salen de aquí, no del paquete anterior.

## Tu corrección, aceptada

Tenías razón y mi F6 se quedó corta. Yo identifiqué la pérdida —Schwalbe imprime 6 Bar y 85 PSI para la misma cubierta y un par escalar guarda una sola— y la llamé consciente. Eliminarla es mejor que aceptarla, y la tabla es la forma correcta porque el segundo eje no es la unidad sino el documento.

## Lo que evalué antes de proponer

**G1 · ¿Existe de verdad un máximo general sin condiciones?** A veces sí y a veces no, y la tabla tiene que aguantar las dos.

Schwalbe imprime para el Marathon Plus 37-622 un mínimo y un máximo sin condicionarlos a ningún perfil de llanta: ahí el máximo general existe como hecho publicado. Continental, para el GP 5000 S TR, publica en la web sólo cifras condicionadas a montaje sin gancho y dice explícitamente que el máximo general está en el envase y que hooked y hookless pueden diferir: ahí el máximo general existe pero no es legible desde esa fuente. La conclusión operativa es que la tabla vacía es un estado legítimo y no un defecto de la ficha.

**G2 · ¿Cómo se impide promocionar un máximo hooked o hookless?** Por vocabulario, no por bloqueo.

La columna de alcance sólo ofrece «sin condición de llanta en el documento», «el documento lo declara para todo montaje» y desconocido. Un máximo que la fuente condiciona a un perfil no tiene token con qué declararse aquí, y su lugar sigue siendo tire_rim_configurations. Digo lo que esto no logra: un operador puede elegir «sin condición» para una cifra que sí la tenía, y el motor no puede verlo desde la ficha. Es un límite de revisión de fuente, igual que el ángulo copiado del BKC-0752.

**G3 · ¿Se puede exigir la unidad de forma que un número suelto no valga?** No con las condiciones. Queda pendiente, nunca bloqueado.

Lo intenté y falló, y lo digo antes de que lo pruebes: diseñé la columna de unidad con un token explícito «Desconocido / sin confirmar» apostando a que elegirlo volvería la condición definitivamente falsa y haría bloquear al número. La sonda devolvió pendiente. La causa es que hasKnownSpecValue trata ese texto como ausencia en todo el motor, así que el token explícito y la celda vacía son el mismo estado. No hay vocabulario que arregle esto: con las condiciones, «sin unidad no se vuelve un número autorizado» se expresa como fila incompleta más valor con requisitos por confirmar, y nada más. Si quieres que ese caso bloquee hace falta otro mecanismo, y no propongo ninguno que no haya podido medir. El token se conserva igual porque es la convención de todas las columnas token del catálogo y porque la columna es requerida, así que la fila sigue marcada incompleta.

**G7 · ¿Se conserva algo del escalar retirado?** El hecho guardado sí; el gobierno del formulario no.

tire_max_pressure_psi pasa a legado y validateProductSpecDraft descarta sus valores antes de validar, así que deja de emitir y deja de exigir. Ninguna condición del catálogo lo referencia como dependencia, de modo que retirarlo no rompe otra regla. Si prefieres integrar la tabla primero y retirarlo en otra ronda, el parche está aislado.

**G4 · ¿Por qué sin unique_by?** Porque no sé demostrar una clave que sólo funda duplicados ilegítimos.

Los cuatro renglones de Schwalbe —dos unidades por dos documentos— son el contraejemplo: una clave sobre valor y unidad borra el segundo documento; una sobre documento y unidad borra una edición posterior que repite la cifra; una sobre las cuatro columnas no funde nada y sólo cuesta. 40 de los 57 esquemas de filas de la base tampoco llevan unique_by.

**G5 · ¿Se impone alguna equivalencia bar/psi?** Ninguna, y hay una razón medible.

6 bar son 87,02 psi y Schwalbe imprime 85 PSI. Continental imprime 4.5 bar y 65 psi, y la conversión da 65,27. Si el motor derivara una unidad de la otra imprimiría números que el fabricante nunca publicó. Las dos cifras son dos hechos y viajan como dos filas.

**G6 · ¿Qué gramática se usó?** La que root ya tiene en pump_pressure_specifications.

Esa tabla ya resuelve «una presión declarada con su unidad y su alcance»: magnitud, valor, unidad y a qué corresponde, las cuatro requeridas, más contexto y fuente opcionales, sin unique_by ni ordered_pairs. La tabla de neumáticos copia esa forma en vez de inventar otra al lado.

## Fuentes

| Id | Fuente | Qué demuestra |
|---|---|---|
| S-SCHWALBE-DE | Schwalbe, Marathon Plus 11100769 (schwalbe.com) | ETRTO 37-622, 700x35C: «min. Bar: 4 Bar min. Psi: 55 PSI max. Bar: 6 Bar max. Psi: 85 PSI». Peso 900 g. El máximo se imprime en las dos unidades y no se condiciona a ningún perfil de llanta. |
| S-SCHWALBE-US | Schwalbe, Marathon Plus 11100769 (schwalbetires.com) | El mismo artículo y la misma edición 2014: ETRTO «37-622», «Min Bar: 4 Bar, Min Psi: 55 PSI, Max Bar: 6 Bar, Max Psi: 85 PSI». El peso sale en otra unidad, «1.98416 lb». Son dos documentos distintos de la misma variante. |
| S-CONTI-HOOKLESS | Continental, Hookless vs. Hooked Rims | Cifras por variante y sólo para montaje sin gancho. GP 5000 S TR 700×28c: 5.0 bar, 72 psi, 23 mm de ancho interior máximo. No hay un máximo universal. |
| S-CONTI-GP | Continental, Grand Prix 5000 S TR | «The maximum inflation pressure for hookless and hooked applications as well as the maximum inner rim width can be found on the tire packaging and may differ between hooked and hookless applications». Para esta variante el máximo general no se publica en la web. |

## Los tres parches

| Id | Operación | Plantilla / campo | Reemplaza |
|---|---|---|---|
| TPDU-01-general-max-pressures-table | `add_field` | `tire` / `tire_general_max_pressures` | WRFP-R3-max-pressure-unit, WRFP-R3-max-pressure-value |
| TPDU-02-row-conditions-unit-gates-value | `replace_template_coherence` | `tire` / `row_conditions` | — |
| TPDU-03-retire-max-pressure-psi | `replace_field_contract` | `tire` / `tire_max_pressure_psi` | WRFP-R3-retire-max-pressure-psi |

### TPDU-01-general-max-pressures-table

Una tabla en vez de dos escalares. Cada fila es un máximo declarado con su valor decimal exacto, su unidad impresa, el alcance que le da el documento y la identidad del documento. Copia la gramática que root ya usa en pump_pressure_specifications: magnitud, valor, unidad y a qué corresponde, todo requerido, más contexto y fuente opcionales.

*No se afirma* ninguna equivalencia entre bar y psi. Dos filas del mismo documento con 6 bar y 85 psi son dos hechos impresos, no uno convertido. El orden de las columnas pone la unidad antes que el valor porque la unidad lo habilita.

*Sin `unique_by`.* Deliberado. 40 de los 57 esquemas de filas de la base tampoco lo llevan. Cualquier clave que junte valor y unidad borraría el segundo documento, y una que junte documento y unidad borraría una edición posterior que repite la cifra. No sé demostrar una clave que sólo funda duplicados ilegítimos, así que no la propongo.

### TPDU-02-row-conditions-unit-gates-value

La unidad gobierna el valor dentro de su propia fila: con la unidad en bar o psi el valor es exigible y su falta queda pendiente, y sin unidad el número queda con requisitos por confirmar y la fila incompleta. Digo lo que no hace: no bloquea. Ver G3.

*No se afirma* que el bloque toque las configuraciones por aro: su entrada anterior se conserva palabra por palabra.

### TPDU-03-retire-max-pressure-psi

El escalar en psi fija la unidad por adelantado y sería un segundo dueño del mismo hecho que ahora vive en la tabla. Pasa a legado; validateProductSpecDraft descarta los valores de campos legacy antes de validar. Es la misma retirada del paquete anterior, con la preimagen de esta base.

*No se afirma* que se borre un dato. Ninguna condición del catálogo lo referencia como dependencia. Si prefieres integrar la tabla primero y retirarlo después, este parche se puede adjudicar por separado.

### El esquema

| Columna | Tipo | Requerida | Vocabulario |
|---|---|---|---|
| pressure_unit | token | sí | bar, psi, Desconocido / sin confirmar |
| max_pressure_value | decimal | no | — |
| declared_scope | token | sí | Sin condición de llanta en el documento, El documento lo declara para todo montaje, Desconocido / sin confirmar |
| source_document | text | sí | — |
| source_url | url | no | — |

La unidad va antes que el valor porque lo habilita. El valor es la única columna no requerida del grupo: una columna requerida estáticamente no admite `allowed_when` condicional, y sin esa condición la unidad no podría gobernarlo. Sin `ordered_pairs` y sin `unique_by`.

## Correcciones al paquete anterior

No reescribo el original. Cada corrección va por id y preimagen contra `wss-residual-field-packet-2026-09-07.json`, SHA `239ab6607e25f4211f88d5c4998cec25af52d07278d75d983c98f0cfa8b05087`.

| Id | Objetivo | Acción | Camino | Reemplazado por |
|---|---|---|---|---|
| C1 | patch `WRFP-R3-max-pressure-unit` | retirar | — | TPDU-01-general-max-pressures-table |
| C2 | patch `WRFP-R3-max-pressure-value` | retirar | — | TPDU-01-general-max-pressures-table |
| C3 | patch `WRFP-R1-race-contact-angle` | corregir | `after.helpers` | — |
| C4 | fixture `wrfp_bb_assembly_angle_copied_is_undetectable` | corregir | `note` | — |
| C5 | fixture `wrfp_schwalbe_general_maximum_in_bar` | retirar | — | tpdu_six_bar_and_85_psi_same_variant |
| C6 | fixture `wrfp_unit_without_value_is_pending` | retirar | — | tpdu_unit_without_value_is_pending |
| C7 | fixture `wrfp_value_without_unit_stays_pending` | retirar | — | tpdu_value_without_unit_is_not_authorized |
| C8 | fixture `wrfp_hookless_row_maximum_is_not_the_headline` | retirar | — | tpdu_hookless_only_source_is_not_promoted |
| C9 | finding `F6` | superado | — | TPDU-01-general-max-pressures-table |
| C10 | finding `F11` | sigue vigente, cambia de sujeto | — | — |

### C3 · `WRFP-R1-race-contact-angle` → `after.helpers`

Mi texto decía que el ángulo «pertenece al conjunto, no a un SKU de rodamiento». Es falso: el ángulo es de los rodamientos internos. Lo que el documento no hace es identificarlos como un SKU suelto, y lo que sigue siendo falso es copiar la cifra sin demostrar esa identidad.

*Preimagen exacta:*

> Magnitud del ángulo interno α medido respecto del plano perpendicular al eje, entre 0 y 90 grados (NSK). Se registra sólo si el fabricante declara un único valor nominal común. No se deduce del sufijo MAX, ni de que la aplicación sea Dirección, ni del par de biseles de asiento. Un conjunto de pedalier que declara 15° no es un rodamiento suelto: ese ángulo pertenece al conjunto, no a un SKU de rodamiento.

*Texto corregido:*

> Magnitud del ángulo interno α medido respecto del plano perpendicular al eje, entre 0 y 90 grados (NSK). Se registra sólo si el fabricante declara un único valor nominal común. No se deduce del sufijo MAX, ni de que la aplicación sea Dirección, ni del par de biseles de asiento. Un conjunto de pedalier que declara 15° está declarando el ángulo de sus rodamientos internos; lo que ese documento no hace es identificar qué rodamiento suelto son. Copiar la cifra a un SKU suelto exige demostrar antes que se trata del mismo rodamiento.

### C4 · `wrfp_bb_assembly_angle_copied_is_undetectable` → `note`

La misma afirmación equivocada que C3, en la nota de la fixtura. Los valores no cambian.

*Preimagen exacta:*

> Los 15° del BKC-0752 pertenecen a un pedalier completo con cazoletas, precarga y separadores. Copiados a un rodamiento suelto el motor no puede detectarlo: sólo la revisión de la fuente lo separa. Se registra como límite, no como regla.

*Texto corregido:*

> Los 15° del BKC-0752 son el ángulo de los rodamientos internos de ese pedalier. El documento no identifica qué rodamiento suelto son, así que copiar la cifra a un SKU suelto sin demostrar esa identidad es falso, y el motor no puede detectarlo desde la ficha: sólo la revisión de la fuente lo separa. Se registra como límite, no como regla.

Las demás correcciones retiran o marcan como superado, sin texto de reemplazo: el detalle y las preimágenes completas están en `corrections` del JSON.

## Ensayo local

Corrí los tres parches por `apply_reviewed_field_addendum` con una adjudicación de ensayo mía: aplican, `validate_contract` pasa y `publication_gates` no cambia. Después monté el catálogo ya parchado en una prueba Dart aislada y corrí las nueve fixturas contra `validateProductSpecDraft`. Cada fixtura lleva en `observed_in_local_trial` la salida literal del motor. La sonda vivió en un archivo temporal que ya borré.

Una expectativa mía falló y la corregí contra lo medido, no al revés: ver G3.

## Fixturas

| Id | Tipo | Qué fija |
|---|---|---|
| tpdu_six_bar_and_85_psi_same_variant | válido | Las dos cifras impresas del mismo documento, cada una con su unidad. Ninguna se deriva de la otra: 6 bar convertidos dan 87 psi y el fabricante imprime 85. |
| tpdu_two_documents_same_figures_do_not_merge | válido | Dos documentos reales de la misma variante con las mismas cifras. Leí los dos hoy. Con un unique_by sobre valor y unidad estas cuatro filas colapsarían a dos y la procede… |
| tpdu_two_editions_disagree_neither_is_wrong | synthetic_documentary_conflict | Cifras sintéticas y sin atribuir a ningún fabricante: no encontré dos ediciones reales de una misma variante que se contradigan, y no voy a inventar la atribución. Lo que… |
| tpdu_value_without_unit_is_not_authorized | desconocido | Sin unidad el número queda con requisitos por confirmar y la fila incompleta. Medido, no supuesto: una dependencia ausente evalúa a SpecTruth.unknown, no a «no», así que … |
| tpdu_unit_declared_unknown_is_still_only_pending | known_gap_regression | Yo esperaba un bloqueo aquí y me equivoqué. hasKnownSpecValue trata «Desconocido / sin confirmar» como ausencia en todo el motor, así que elegir ese token es idéntico a d… |
| tpdu_unit_without_value_is_pending | desconocido | Elegida la unidad, el valor es exigible y su falta queda pendiente. |
| tpdu_row_without_scope_or_document_is_pending | desconocido | Alcance y documento son columnas requeridas del esquema: su falta sale como row_incomplete no bloqueante, nombrando la fila y la columna que falta. |
| tpdu_hookless_only_source_is_not_promoted | válido | Continental publica para el 700×28c 5.0 bar y 23 mm sólo para montaje sin gancho, y dice que el máximo general está en el envase y puede diferir. La tabla de máximos gene… |
| tpdu_legacy_psi_no_longer_governs | legacy_boundary_regression | 999 es sintético y no se atribuye a nadie. Tras la retirada el validador descarta el valor antes de validar. |

Las cifras de Schwalbe y Continental son lecturas de hoy. Las dos ediciones que se contradicen son sintéticas y sin atribuir: no encontré dos ediciones reales de una misma variante que declaren distinto, y no invento la atribución. Ningún producto queda lleno.

## Lo que esto no resuelve

- Un máximo condicionado a un perfil de llanta declarado como si fuera general es indetectable desde la ficha. Sólo la revisión de la fuente lo separa.
- Un número sin unidad nunca bloquea, sólo queda pendiente. Ver G3.
- Dos ediciones que se contradicen conviven sin que ninguna quede marcada errónea, que es lo que pediste; el motor no elige entre ellas y nada en la ficha dice cuál rige.

## Compuertas

Publicación, llenado, asignación y aprobación mecánica siguen en `false`, en la base y en el ensayo. Ninguna familia queda certificada.
