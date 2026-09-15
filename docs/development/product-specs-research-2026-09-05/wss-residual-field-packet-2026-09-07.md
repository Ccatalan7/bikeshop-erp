# Campos residuales de ruedas, dirección y suspensión: paquete implementable

Claude, revisor independiente de representación · 2026-09-07

Propuesta local. No adjudica, no asigna, no llena y no publica. No toca compilador, catálogo, código, pruebas de root, base de datos ni runtime. Aprobar una representación no aprueba un montaje ni certifica una familia.

## Sobre qué se construyó

| Artefacto | SHA-256 | Verificado |
|---|---|---|
| all-family-row-values-integrated-2026-09-07.json | `58e68f0c4f0d7b8e824a84a3931cf9f7bd03767f8a65aaa55020bc6af7465f03` | sí, con `shasum -a 256` |
| all-family-row-values-cases-integrated-2026-09-07.json (259 casos) | `0eb5dfda6a7087cf115afd54e08a9908b00511acbae59d58217b783d371da810` | sí, con `shasum -a 256` |

Se implementan R1, R2, R3 y R6. **No** se implementan R4 ni R5, como pidió root: dos cotas independientes no ordenan los valores reales que admiten, y la relación entre carrera y entrecentros no es universal.

## Lo que probé antes de escribir un parche

Cada decisión de root la traté como una hipótesis y busqué el caso que la tumbaría. Ninguna falló. Dos cosas sí cambiaron, y las dos son mías.

**F1 · R2 — la decisión resiste.** Busqué el contraejemplo que la tumbaría: un rodamiento tapado por un solo lado. Existe —SKF distingue 6208-Z de 6208-2Z— pero el catálogo lo registra como cartucho sellado o blindado, no como cartucho abierto, así que conserva bearing_seal_kind. La compuerta sólo cierra el caso en que no hay nada que designar.

**F2 · R2 — la decisión resiste.** La página de Enduro que define LLB y LLU no usa la palabra «cartridge» ni una sola vez. La construcción y el sellado son dos hechos independientes y ninguno se lee del otro.

**F3 · R1 — la decisión resiste, con un límite.** NSK define α respecto del plano perpendicular al eje y lo acota entre 0° y 90°, pero no dice si una doble hilera de contacto angular tiene uno o dos ángulos nominales. Ese silencio es justo lo que sostiene la guarda de root: el campo sólo se llena cuando el fabricante declara un único valor nominal común. El Enduro 3802 LLU MAX es el caso: doble hilera, contacto angular, y ningún ángulo publicado.

**F4 · R1 — contraejemplo que confirma el alcance.** El BKC-0752 sí publica 15°, pero es un pedalier T47 completo con cazoletas mecanizadas, ajustador de precarga y separadores. Convertirlo en un SKU de rodamiento suelto sería inventar un producto. El motor no puede distinguirlo desde la ficha, así que queda como fixtura de tipo contradictory_undetectable y no como regla.

**F5 · R1 — precisión sobre el dominio.** Los dos biseles usan positive:true, que excluye el cero. Para α el cero es legítimo: NSK lo asigna al contacto radial. Por eso el campo nuevo usa min «0» y max «90» en vez de positive.

**F6 · R3 — la decisión resiste, y aparece un límite que conviene nombrar.** Schwalbe imprime las dos unidades para la misma cubierta: «max. Bar: 6 Bar» y «max. Psi: 85 PSI». No son conversiones exactas entre sí —6 bar son 87 psi—, así que ninguna se deriva de la otra. R3 guarda una sola, y la otra cifra impresa no queda representada. Es una pérdida consciente, no un error: representar las dos exigiría un par valor/unidad repetible, que es una fila, no un escalar.

**F7 · R3 — la fuente confirma la separación.** Continental declara en la página del GP 5000 S TR que el máximo hookless y el hooked «may differ» y que ambos están en el envase. El titular y el máximo de una configuración son dos hechos distintos con dueños distintos, tal como pide root.

**F8 · R6 — la decisión resiste.** La tabla hookless de Continental publica 5.0, 4.5, 4.0 y 3.8 bar y anchos de 21 a 25 mm según variante y modelo. No hay tope universal que inventar. La exigencia se implementa sobre pressure_unit y rim_internal_width_max_mm, nunca sobre el mínimo.

**F9 · R6 — trampa del motor evitada.** Exigir max_pressure directamente por perfil hookless habría dejado una celda requerida y no aplicable a la vez cuando falta la unidad: allowed_when es falso sin unidad, y una celda con valor no aplicable emite un bloqueo. Exigir la unidad, que ya arrastra su valor, produce el mismo resultado sin esa contradicción.

**F10 · R4 y R5 — sin parche, como pidió root.** No se propone la desigualdad entre máximos de FOX ni entre carrera y entrecentros. La razón de root es más fuerte que la mía: dos cotas independientes no ordenan los valores reales que admiten.

**F11 · R3 — límite del motor, medido.** «El valor exige la unidad» no llega a ser un bloqueo. Una dependencia ausente evalúa a SpecTruth.unknown, no a «no», así que un número escrito sin elegir la unidad queda como pendiente no bloqueante. Lo comprobé corriendo la fixtura contra validateProductSpecDraft, no leyendo el código. Es el mismo comportamiento que cualquier otro prerequisito del catálogo, así que es consistente; pero si root quiere que ese caso bloquee, no alcanza con allowed_when y hace falta otro mecanismo.

**F12 · R3 — corrección a mi propio parche.** Mi primera versión ponía tire_max_pressure_unit en allowed_when y además en prerequisites. La sonda devolvió dos avisos «prerequisite» para el mismo campo, con dos mensajes distintos: dos dueños para el mismo pendiente. Dejé allowed_when como único dueño de esa dependencia y prerequisites sólo con la fuente.

## Fuentes contrastadas hoy

| Id | Fuente | Qué demuestra |
|---|---|---|
| S-PARK-HEADSET | Park Tool, Headset Standards and Sizing | Un rodamiento de cartucho de dirección se marca con dos ángulos (36×45): el primero es el bisel que apoya en la pista de dirección o cono centrador, el segundo el que apoya en el alojamiento del cuadro. Enumera bolas sueltas, canastillo y cartucho como tres cosas distintas. |
| S-NSK-ANGLE | NSK, Differentiating rolling bearings | El ángulo de contacto α es «el ángulo entre una línea perpendicular al eje del rodamiento y otra que pasa por los puntos donde un elemento rodante contacta las pistas del anillo interior y exterior bajo carga», y su dominio va de 0° a 90° (radial 0–45, axial 45–90). No dice si un rodamiento de doble hilera de contacto angular tiene uno o dos ángulos nominales. |
| S-ENDURO-BASICS | Enduro Bearings, Bearing Basics 1 | LLB y LLU son designaciones de sellado: «These designations indicate a mating groove on the inner race where two sealing lips make light contact (LLB) or medium contact (LLU)». No publica ningún ángulo de contacto numérico y la palabra «cartridge» no aparece en la página. |
| S-ENDURO-3802 | Enduro Bearings, 3802 LLU MAX | 15×24×7 mm, doble hilera, contacto angular, sellos LLU de doble labio. No publica ningún ángulo de contacto. |
| S-ENDURO-BKC0752 | Enduro Bearings, BKC-0752 | «T47-Asymmetrical, Thread-In, XD15 Ceramic-Hybrid, Angular-Contact Bearing Bottom Bracket for BB386 type (30mm) spindles». Publica 15° de contacto angular, pero el SKU es un pedalier completo: cazoletas mecanizadas con rodamientos prensados, ajustador de precarga de aluminio y juego de separadores. |
| S-SKF-CAPPED | SKF, deep groove ball bearings (texto indexado) | Los rodamientos «capped on both sides are lubricated for the life of the bearing and are virtually maintenance-free». El folleto S-Type 41 distingue por designación pantallas removibles (SLLC) de pantallas metálicas no removibles (SFFC). |
| S-CONTI-HOOKLESS | Continental, Hookless vs. Hooked Rims | Los límites son por variante y no hay un máximo universal. GP 5000 S TR: 650b×30c 4.5\|65\|25, 650b×32c 4.5\|65\|25, 700×25c 5.0\|72\|21, 700×28c 5.0\|72\|23, 700×30c 4.5\|65\|25, 700×32c 4.5\|65\|25. GP 5000 AS TR: 700×25c 5.0\|72\|21, 700×28c 5.0\|72\|23, 700×32c 4.5\|65\|25, 700×35c 4.0\|58\|25. GP 5000 TT TR: 700×25c 5.0\|72\|21, 700×28c 5.0\|72\|23. AERO 111: 700×26c 5.0\|72\|22, 700×29c 5.0\|72\|25. Grand Prix TR: 700×25c 5.0\|72\|21, 700×28c 5.0\|72\|23, 700×30c 4.5\|65\|25, 700×32c 4.5\|65\|25. Notas al pie: «Hookless rim = *TSS rim (tubeless straight side)» y «Hooked rim = **C/TC rim (crotchet/tubeless crotchet)». |
| S-CONTI-GP5000STR | Continental, Grand Prix 5000 S TR | «The maximum inflation pressure for hookless and hooked applications as well as the maximum inner rim width can be found on the tire packaging and may differ between hooked and hookless applications». El máximo general por medida no se publica en la página. |
| S-SCHWALBE-MPLUS | Schwalbe, Marathon Plus 37-622 (11100769) | ETRTO 37-622, 700x35C: «min. Bar: 4 Bar min. Psi: 55 PSI max. Bar: 6 Bar max. Psi: 85 PSI». El máximo general se imprime en las dos unidades y no son conversiones exactas entre sí: 6 bar son 87 psi, y el fabricante imprime 85 PSI. |
| S-FOX-2013 | FOX 2013 (cotas de borde y pico) | Los dos máximos son cotas independientes. Un borde máximo de 700 y un pico máximo de 690 siguen admitiendo un borde real de 680 con un pico de 685; el orden entre ambos no es una imposibilidad física. |

La única fuente que no pude leer literalmente es SKF: el cuerpo de la página se sirve por JavaScript y el PDF de catálogo que devuelve el buscador es imagen sin capa de texto. Las dos frases que uso quedan marcadas como texto indexado, no como lectura de la página, y de esa fuente no tomo ninguna cifra.

## Los diez parches

| Id | Decisión | Operación | Plantilla / campo |
|---|---|---|---|
| WRFP-R2-bearing_seal_kind-open-cartridge | R2 | `replace_field_contract` | `bearing` / `bearing_seal_kind` |
| WRFP-R1-inner-bevel-helper | R1 | `replace_field_contract` | `bearing` / `bearing_inner_contact_angle_deg` |
| WRFP-R1-outer-bevel-helper | R1 | `replace_field_contract` | `bearing` / `bearing_outer_contact_angle_deg` |
| WRFP-R1-race-contact-angle | R1 | `add_field` | `bearing` / `bearing_race_contact_angle_deg` |
| WRFP-R1-row-count | R1 | `add_field` | `bearing` / `bearing_row_count` |
| WRFP-R1-regreasable | R1 | `add_field` | `bearing` / `bearing_regreasable` |
| WRFP-R3-retire-max-pressure-psi | R3 | `replace_field_contract` | `tire` / `tire_max_pressure_psi` |
| WRFP-R3-max-pressure-unit | R3 | `add_field` | `tire` / `tire_max_pressure_unit` |
| WRFP-R3-max-pressure-value | R3 | `add_field` | `tire` / `tire_max_pressure_value` |
| WRFP-R6-hookless-pending-completeness | R6 | `replace_template_coherence` | `tire` / `row_conditions` |

### WRFP-R2-bearing_seal_kind-open-cartridge

Un cartucho abierto no tiene sello ni pantalla, así que deja de admitir una designación de sellado. La designación OEM completa no se toca: sigue entera en bearing_size_code.

*No se afirma* que «cartucho» implique sellado, ni al revés. Un rodamiento tapado por un solo lado se sigue registrando como cartucho sellado o blindado y conserva este campo.

### WRFP-R1-inner-bevel-helper

Se conservan id, clave y rótulo. Sólo se agrega el datum que desambigua el bisel.

*No se afirma* que la convención 36×45 sea universal: se atribuye a Park Tool.

Este parche escribe un bucket que el campo hoy no tiene, así que la adjudicación necesita declararlo:

```json
{
  "patch_id": "WRFP-R1-inner-bevel-helper",
  "decision": "aceptar",
  "reason": "…",
  "before_extensions": {
    "helpers": {
      "present": false,
      "value": null
    }
  }
}
```

### WRFP-R1-outer-bevel-helper

Igual que el interior, en el otro anillo.

*No se afirma* No se propone renombrar las claves ni reasignar identidades.

Este parche escribe un bucket que el campo hoy no tiene, así que la adjudicación necesita declararlo:

```json
{
  "patch_id": "WRFP-R1-outer-bevel-helper",
  "decision": "aceptar",
  "reason": "…",
  "before_extensions": {
    "helpers": {
      "present": false,
      "value": null
    }
  }
}
```

### WRFP-R1-race-contact-angle

Campo nuevo y distinto de los dos biseles. Aplica sólo a construcciones de cartucho, que son las que tienen pistas propias; nunca es obligatorio.

*No se afirma* No se deriva de MAX, ni de bearing_application = Dirección, ni del par de biseles. Tampoco se afirma que un rodamiento de doble hilera tenga un solo ángulo nominal.

### WRFP-R1-row-count

Entero positivo. Se excluye sólo la bolsa de bolas sueltas, que no tiene hileras, y la construcción declarada como desconocida.

*No se afirma* No se infiere del sello, del ancho ni del código dimensional.

### WRFP-R1-regreasable

Booleano sin valor por defecto: la ausencia ya es «desconocido» para el motor, que sólo mira hasKnownSpecValue. Nunca es obligatorio.

*No se afirma* No se deduce del sello. La frase de SKF sobre lubricación de por vida está acotada a los tapados por ambos lados y no gobierna un sello LLU que el taller abre.

### WRFP-R3-retire-max-pressure-psi

El escalar en psi fija la unidad por adelantado y no distingue el máximo general del máximo de una configuración. Pasa a legado; validateProductSpecDraft descarta los valores de campos legacy antes de validar, así que deja de gobernar el editor sin perder el hecho guardado.

*No se afirma* No se borra ningún dato ni se convierte a otra unidad. Ninguna condición del catálogo lo referencia como dependencia, así que retirarlo no rompe otra regla.

### WRFP-R3-max-pressure-unit

La unidad precede al valor y lo habilita.

*No se afirma* No se convierte entre bar y psi en ningún sentido.

### WRFP-R3-max-pressure-value

allowed_when es el único dueño de la dependencia con la unidad; prerequisites sólo pide la fuente. Poner la unidad en las dos partes emitía dos avisos «prerequisite» para el mismo campo, medido en la sonda. Elegir la unidad y no traer el número deja la ficha pendiente: required_missing escalar es no bloqueante.

*No se afirma* No se ordena contra ningún máximo de fila ni contra el mínimo de otra configuración.

### WRFP-R6-hookless-pending-completeness

Una fila hookless sin ancho interno máximo o sin unidad de presión queda pendiente, no imposible. La unidad ya exigía su valor, así que la presión se completa por esa cadena y ningún otro miembro la aporta.

*No se afirma* No se inventa ningún tope universal: Continental publica 5.0, 4.5, 4.0 y 3.8 bar según la variante. El mínimo sigue siendo otro dato y nunca se iguala al máximo.

## Ensayo local contra el compilador real

Corrí `apply_reviewed_field_addendum` con una adjudicación de ensayo escrita por mí, sobre la base congelada. Los diez parches aplican, `validate_contract` pasa y `publication_gates` no cambia. Eso demuestra que las preimágenes son exactas y que el contrato resultante es válido. No es una adjudicación: la real la escribe root.

Después monté el catálogo ya parchado en una prueba Dart aislada y corrí las 19 fixturas contra `validateProductSpecDraft`. Las expectativas del JSON no están escritas a mano: cada fixtura lleva `observed_in_local_trial`, que es la salida literal del motor. La sonda vivió en un archivo temporal que ya borré; el árbol quedó como estaba, con los mismos 123 caminos modificados del inicio de sesión.

Dos expectativas mías no calzaron y las dos se corrigieron contra lo medido, no al revés:

1. El motor recorre los campos en el orden de la plantilla, así que el ángulo interno aparece antes que el conteo de hileras. Orden, no defecto.
2. Un valor de presión sin unidad **no** bloquea. Una dependencia ausente evalúa a `SpecTruth.unknown`, no a «no». Queda como pendiente. Ver F11.

## Fixturas

| Id | Decisión | Tipo | Qué fija |
|---|---|---|---|
| wrfp_open_cartridge_rejects_seal_designation | R2 | contradictorio | Un cartucho abierto no tiene sello que designar. |
| wrfp_open_cartridge_keeps_its_oem_code | R2 | válido | Retirar el sello no toca la designación del fabricante. |
| wrfp_sealed_cartridge_still_takes_llu | R2 | válido | La compuerta no se pasa de restrictiva: el sellado sigue admitiendo su designación. |
| wrfp_3802_double_row_without_declared_angle | R1 | desconocido | Doble hilera, contacto angular y MAX, sin ángulo publicado. El campo nuevo queda vacío y nunca se reclama. |
| wrfp_race_contact_angle_zero_is_in_domain | R1 | válido | NSK admite α = 0 para el contacto radial: el dominio parte en cero, no en «mayor que cero». |
| wrfp_race_contact_angle_outside_domain | R1 | contradictorio | El dominio de α termina en 90°. |
| wrfp_loose_balls_cannot_declare_rows_or_angle | R1 | contradictorio | Una bolsa de bolas no tiene hileras ni pistas propias. |
| wrfp_bb_assembly_angle_copied_is_undetectable | R1 | contradictory_undetectable | Los 15° del BKC-0752 pertenecen a un pedalier completo con cazoletas, precarga y separadores. Copiados a un rodamiento suelto el motor no puede detect… |
| wrfp_regreasable_is_unknown_by_default | R1 | desconocido | La ausencia ya es desconocido; el campo nunca se reclama. |
| wrfp_sealed_does_not_decide_regreasing | R1 | válido | Sellado y reengrasable conviven; el sello no decide la declaración. |
| wrfp_schwalbe_general_maximum_in_bar | R3 | válido | Cifra impresa: «max. Bar: 6 Bar». La misma ficha imprime «max. Psi: 85 PSI»; no se convierte. |
| wrfp_unit_without_value_is_pending | R3 | desconocido | Elegir la unidad y no traer el número deja la ficha pendiente, no rota. |
| wrfp_value_without_unit_stays_pending | R3 | desconocido | Medido, no supuesto: una dependencia ausente da SpecTruth.unknown, no «no». El número sin unidad queda con requisitos por confirmar y no bloquea. Es e… |
| wrfp_legacy_psi_no_longer_governs | R3 | legacy_boundary_regression | 999 es un número sintético, no atribuido a ningún fabricante. Tras el retiro, validateProductSpecDraft descarta el valor antes de validar y no emite n… |
| wrfp_hookless_row_maximum_is_not_the_headline | R3 | contradictory_undetectable | El 5.0 de la fila es el máximo hookless. Continental declara que el hookless y el hooked pueden diferir y que ambos están en el envase, así que copiar… |
| wrfp_hookless_row_pending_max_width | R6 | desconocido | Completitud pendiente, no imposibilidad. |
| wrfp_hookless_row_pending_unit_and_width | R6 | desconocido | Sin unidad, la presión de la fila queda con requisitos por confirmar; la unidad y el ancho máximo quedan pendientes. |
| wrfp_hooked_row_needs_no_hookless_completeness | R6 | válido | La compuerta es sólo para hookless; una fila con gancho no hereda la exigencia. |
| wrfp_hookless_minimum_is_not_invented | R6 | válido | Continental publica 21 mm como máximo del 700×25c y no publica mínimo. El mínimo queda vacío y nadie lo exige. |

Todas las celdas numéricas de fila viajan como texto decimal exacto. No es estilo: `ProductSpecRowColumn.validate` rechaza por tipo cualquier número JSON, y una columna entera rechaza el exponente negativo de `"2.0"`.

## Cambios que necesitan las fixturas anteriores

Releí la tabla hookless de Continental completa y verbatim y la contrasté contra los siete casos `tire` congelados. **Ningún valor está mal**: 28-622 con 23 mm y 5.0 bar, y 30-622 con 25 mm y 4.5 bar, son exactamente lo que publica el fabricante. No hay ningún máximo copiado como mínimo y ningún titular sin fuente. Tampoco hay un solo caso de los 259 que toque `tire_max_pressure_psi`, así que retirarlo no cambia ninguna expectativa.

Lo que sí cambia son tres expectativas, por R6. Ningún valor se toca; sólo se agrega un pendiente no bloqueante. No reescribo los archivos:

| Caso | Valores | Expectativa |
|---|---|---|
| wss_root_pressure_unit_requires_its_value | ninguno | gana un row_required_missing no bloqueante en rim_internal_width_max_mm de la fila «hookless», además del pendiente de presión que ya tenía. |
| wss_SF6 | ninguno | cada una de las dos filas hookless gana un row_required_missing no bloqueante en rim_internal_width_max_mm. El bloqueo por row_shape no cambia. |
| wss_tire_same_variant_profile_method_twice | ninguno | las dos filas hookless ganan un row_required_missing no bloqueante en rim_internal_width_max_mm. El bloqueo por row_shape no cambia. |

## Lo que este paquete no resuelve

- Un ángulo copiado desde un conjunto de pedalier a un rodamiento suelto es indetectable desde la ficha. Sólo la revisión de la fuente lo separa.
- Un máximo hookless copiado al titular también es indetectable. Continental declara que el hookless y el hooked pueden diferir, pero la ficha no sabe de dónde salió el número.
- Cuando el fabricante imprime el máximo en las dos unidades, R3 conserva una sola. Las dos cifras impresas no son conversiones entre sí, así que la otra no se deduce.
- «El valor exige la unidad» es un pendiente, no un bloqueo. Si root lo quiere bloqueante, `allowed_when` no alcanza.

## Compuertas

`all_family_domain_review_complete`, `all_product_assignment_review_complete`, `compatibility_rules_integrated` y `fill_allowed` siguen en `false`, en la base y en el ensayo. Ninguna familia queda certificada y no hay llenado autorizado.
