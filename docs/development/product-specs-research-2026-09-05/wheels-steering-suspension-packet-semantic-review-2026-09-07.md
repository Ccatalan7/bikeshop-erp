# Revisión semántica del paquete WSS (2026-09-07)

Sobre el paquete congelado `c03ebe91fa7e56d3…` y la base `f3178bd3c860c421…`. No se editó el paquete, la base, el consumidor, sus pruebas ni el runtime. Llenado y publicación siguen en cero.

**Tres de las cuatro preguntas encuentran un defecto real en mi propio paquete: la exigencia de ángulos por destino, la columna de variante en las filas del neumático y el ancho máximo usado como identidad. La cuarta se resuelve al revés de lo esperado: no hay hechos que migrar y el rótulo que iba a cambiar era el correcto.**

## 1. Respuestas

### Q1 · ¿Exigir los ángulos por bearing_application = Dirección vale para bolas sueltas, canastillos, radiales y contacto angular?

**Veredicto.** No. El parche del paquete es incorrecto y además hereda una permisión incorrecta de la base.

La plantilla bearing vende cuatro cosas bajo el mismo destino: cartucho sellado, bolsa de bolas sueltas, canastillo y desconocido, y tiene ball_diameter_in y ball_count_per_pack precisamente para las bolas. Con mi parche, una bolsa de 5/32" declarada para dirección quedaba obligada a dos ángulos que no existen: el mismo error que root corrigió en luces al exigir una revisión que el fabricante no publica. Park Tool atribuye el par al apoyo con la pista y con el cuadro, y lo describe como marcado del cartucho; no se lo atribuye a bolas ni a canastillos. Un cartucho radial profundo tampoco declara par de biseles. La condición correcta es la construcción interna, no el destino.

Correcciones: `SR-Q1-bearing_inner_contact_angle_deg`, `SR-Q1-bearing_outer_contact_angle_deg`

### Q2 · ¿Cada fila de tire_rim_configurations, fork_tire_clearance, shock_ends y headset_bearings se queda dentro de un SKU?

**Veredicto.** Tres sí; tire_rim_configurations no.

shock_end_configurations lleva unique_by por extremo y headset_bearing_configurations por posición: en un SKU sólo caben el extremo superior y el inferior, y una talla o un head tube distinto es otro SKU, así que no hay forma de mezclar variantes. fork_tire_clearance_configurations lleva el BSD en la fila, lo que parece un surtido pero no lo es: un fabricante puede aprobar dos rodados para la MISMA horquilla, y en ese caso las dos filas son de ese SKU; lo que nunca debe entrar es otra columna del manual, como el diámetro de barra, porque eso sí es otra horquilla. tire_rim_configurations sí falla: la columna tire_variant invita a meter dos neumáticos distintos en una ficha.

Correcciones: `SR-Q2-tire-variant`

### Q3 · ¿Los unique_by identifican una configuración o sólo un nombre?

**Veredicto.** Uno usaba un nombre libre y otro usaba una medida declarada como identidad; el resto son tokens cerrados.

El nombre libre era tire_variant, que sale con SR-Q2 y deja la identidad en dos vocabularios cerrados: dos grafías del mismo texto ya no crean dos filas. La medida usada como identidad era max_tire_width_mm en la horquilla, que sale con SR-Q3. Los otros cuatro grupos son posiciones y extremos de vocabulario cerrado, más el caso de las mazas aceptadas, donde cada ancho admitido sí es una fila distinta y por eso el número pertenece a la identidad. Verifiqué además la trampa del motor: unique_by omite las filas a las que les falta una clave del grupo, así que toda columna de identidad tiene que ser required, y en los seis campos lo es.

Correcciones: `SR-Q3-fork-unique_by`

### Q4 · ¿Renombrar spoke_thread_diameter_mm cambia la semántica de hechos existentes?

**Veredicto.** No hay hechos que migrar, pero el cambio era igualmente incorrecto y se retira.

spoke_thread_diameter_mm es origin new en la base integrada: no tiene hechos guardados, así que la exigencia de migración no llega a aplicarse. El problema es otro y más grave: el rótulo que iba a reemplazar es el acertado. Reviso además los otros cuatro rótulos del paquete: dos tocan definiciones existing (bearing_size_code y bearing_application) y ninguno reinterpreta un valor guardado, sólo precisa qué admite el campo; nipple_thread y los rótulos por plantilla son de definiciones nuevas o anulaciones locales.

Correcciones: `SR-Q4-withdraw-relabel`

## 2. Correcciones, con preimagen

### SR-Q1-bearing_inner_contact_angle_deg — reemplaza un parche del paquete: `WSS-W04-bearing-require-bearing_inner_contact_angle_deg`

Preimagen:

```json
{"patch_before": {"required_when": {"kind": "never"}}, "patch_after": {"required_when": {"kind": "when", "rows": [[{"field": "bearing_application", "operator": "eq", "value_type": "token", "value": "Dirección"}]]}}, "base_allowed_when": {"kind": "when", "rows": [[{"field": "bearing_application", "operator": "eq", "value_type": "token", "value": "Dirección"}]]}}
```

Propuesta:

```json
{"op": "replace_field_contract", "template": "bearing", "key": "bearing_inner_contact_angle_deg", "before": {"allowed_when": {"kind": "when", "rows": [[{"field": "bearing_application", "operator": "eq", "value_type": "token", "value": "Dirección"}]]}, "required_when": {"kind": "never"}}, "after": {"allowed_when": {"kind": "when", "rows": [[{"field": "bearing_internal_construction", "operator": "eq", "value_type": "token", "value": "Contacto angular"}]]}, "required_when": {"kind": "when", "rows": [[{"field": "bearing_internal_construction", "operator": "eq", "value_type": "token", "value": "Contacto angular"}]]}}}
```

**Por qué.** El par de ángulos es del cartucho de contacto angular, no del destino declarado. Un envase de bolas sueltas o un canastillo con destino «Dirección» no tiene par que declarar, y un cartucho radial montado en una dirección tampoco: Park Tool enumera los tres tipos por separado y sólo describe el par marcado en el cartucho. Condicionar por construcción interna corrige la exigencia (mía) y de paso la permisión (que venía de A/B y hoy admite ángulos en una bolsa de bolas).

**Nota de integración.** Depende de que WSS-W03-internal_construction se aplique antes: la condición cita bearing_internal_construction y el guard de metadatos rechaza la plantilla si el campo no está. Sin ciclo: los ángulos dependen de la construcción interna, que depende de bearing_construction.

### SR-Q1-bearing_outer_contact_angle_deg — reemplaza un parche del paquete: `WSS-W04-bearing-require-bearing_outer_contact_angle_deg`

Preimagen:

```json
{"patch_before": {"required_when": {"kind": "never"}}, "patch_after": {"required_when": {"kind": "when", "rows": [[{"field": "bearing_application", "operator": "eq", "value_type": "token", "value": "Dirección"}]]}}, "base_allowed_when": {"kind": "when", "rows": [[{"field": "bearing_application", "operator": "eq", "value_type": "token", "value": "Dirección"}]]}}
```

Propuesta:

```json
{"op": "replace_field_contract", "template": "bearing", "key": "bearing_outer_contact_angle_deg", "before": {"allowed_when": {"kind": "when", "rows": [[{"field": "bearing_application", "operator": "eq", "value_type": "token", "value": "Dirección"}]]}, "required_when": {"kind": "never"}}, "after": {"allowed_when": {"kind": "when", "rows": [[{"field": "bearing_internal_construction", "operator": "eq", "value_type": "token", "value": "Contacto angular"}]]}, "required_when": {"kind": "when", "rows": [[{"field": "bearing_internal_construction", "operator": "eq", "value_type": "token", "value": "Contacto angular"}]]}}}
```

**Por qué.** El par de ángulos es del cartucho de contacto angular, no del destino declarado. Un envase de bolas sueltas o un canastillo con destino «Dirección» no tiene par que declarar, y un cartucho radial montado en una dirección tampoco: Park Tool enumera los tres tipos por separado y sólo describe el par marcado en el cartucho. Condicionar por construcción interna corrige la exigencia (mía) y de paso la permisión (que venía de A/B y hoy admite ángulos en una bolsa de bolas).

**Nota de integración.** Depende de que WSS-W03-internal_construction se aplique antes: la condición cita bearing_internal_construction y el guard de metadatos rechaza la plantilla si el campo no está. Sin ciclo: los ángulos dependen de la construcción interna, que depende de bearing_construction.

### SR-Q2-tire-variant — corrige una definición nueva del paquete: `new_definitions.tire_rim_configurations`

Preimagen:

```json
{"columns": ["tire_variant", "rim_bead_profile", "mounting_method", "rim_internal_width_min_mm", "rim_internal_width_max_mm", "max_pressure_bar", "max_pressure_psi", "source_url"], "unique_by": [["tire_variant", "rim_bead_profile", "mounting_method"]], "tire_variant_column": {"key": "tire_variant", "label": "Variante del neumático", "type": "text", "required": true}}
```

Propuesta:

```json
{"columns": ["rim_bead_profile", "mounting_method", "rim_internal_width_min_mm", "rim_internal_width_max_mm", "max_pressure_bar", "max_pressure_psi", "source_url"], "unique_by": [["rim_bead_profile", "mounting_method"]], "removed_column": "tire_variant", "scope_rule": "Las filas describen configuraciones de ESTE SKU. La variante ya la identifican tire_width_mm, tire_etrto y el BSD del propio producto."}
```

**Por qué.** Es el defecto real de los cuatro campos de filas. Continental publica límites por variante y cada variante es un producto distinto: la 700×28c y la 700×30c son dos SKU. Con una columna de variante, la ficha de la 28c podía cargar los límites de la 30c y quedar convertida en hoja de modelo. Mi propia fixture del paquete lo hacía.

**Nota de integración.** La fixture tire_gp5000_two_variants_hookless del paquete debe partirse en dos fixtures de un SKU cada una; su versión corregida está en las regresiones de este documento.

### SR-Q3-fork-unique_by — corrige una definición nueva del paquete: `new_definitions.fork_tire_clearance_configurations`

Preimagen:

```json
{"unique_by": [["bead_seat_diameter_mm", "max_tire_width_mm"]]}
```

Propuesta:

```json
{"unique_by": [["bead_seat_diameter_mm"]]}
```

**Por qué.** El ancho máximo es el límite que la fila declara, no su identidad. Con [BSD, ancho] dos filas del mismo rodado con anchos distintos conviven y ambas parecen válidas; con [BSD] una horquilla declara una envolvente por rodado y un segundo ancho para el mismo rodado sale como contradicción, que es lo que es.

### SR-Q4-withdraw-relabel — retira un parche del paquete: `WSS-W10-spoke-thread-label`

Preimagen:

```json
{"op": "replace_definition_label", "key": "spoke_thread_diameter_mm", "before": "Diámetro nominal de rosca del rayo", "after": "Diámetro del alambre en la zona roscada, medido (mm)"}
```

Propuesta:

```json
{"action": "retirar el parche; el rótulo de spoke_thread_diameter_mm no se cambia"}
```

**Por qué.** Root tiene razón en la regla y el caso resulta ser peor que un problema de migración: el rótulo actual ya es el correcto. Sapim llama FG 2.3 a la rosca de un radio de 2 mm, es decir la rosca laminada es MÁS gruesa que el alambre; «diámetro nominal de rosca del rayo» nombra exactamente ese 2,3. Lo que W10 denunciaba no era el campo sino la nota del blueprint que lo rellenaba desde el calibre. Mi parche habría dejado la clave diciendo rosca y el rótulo diciendo alambre, y con eso un 2,3 correcto se leería como un alambre imposible.

**Nota de integración.** La definición es origin new y no tiene hechos, así que no habría exigido migración; el daño era semántico, no de datos. La regla de root se cumple igual: ningún parche del paquete reinterpreta un hecho guardado.

## 3. Auditoría de identidad en unique_by

| Campo de filas | unique_by | Tipo de identidad | Estado | Columnas de identidad requeridas |
|---|---|---|---|---|
| tire_rim_configurations | [["rim_bead_profile", "mounting_method"]] | dos tokens de vocabulario cerrado | tras SR-Q2 | sí |
| fork_tire_clearance_configurations | [["bead_seat_diameter_mm"]] | entero de medida | tras SR-Q3 | sí |
| shock_end_configurations | [["end_position"]] | token cerrado | sin cambio | sí |
| headset_bearing_configurations | [["position"]] | token cerrado | sin cambio | sí |
| headset_port_configurations | [["position"]] | token cerrado | sin cambio | sí |
| dropout_hub_acceptance_configurations | [["position", "accepted_hub_old_mm", "retention_kind"]] | token + medida + token | sin cambio | sí |

La última columna importa porque `unique_by` omite las filas a las que les falta una clave del grupo: una identidad opcional no deduplica nada.

## 4. Auditoría de rótulos

| Parche | Clave | Origen | Plantillas | Cambia el significado guardado | Veredicto |
|---|---|---|---|---|---|
| WSS-W01-tire-max_pressure-label | tire_max_pressure_psi | new | tire | no | conservar: precisa qué admite el campo sin reinterpretar ningún valor guardado |
| WSS-W02-hardware-label | mounting_hardware_included | new | rear_shock | no | conservar: precisa qué admite el campo sin reinterpretar ningún valor guardado |
| WSS-W03-size_code-label | bearing_size_code | existing | bearing, bottom_bracket, bottom_bracket_bearing | no | conservar: precisa qué admite el campo sin reinterpretar ningún valor guardado |
| WSS-W03-application-label | bearing_application | existing | bearing | no | conservar: precisa qué admite el campo sin reinterpretar ningún valor guardado |
| WSS-W10-spoke-thread-label | spoke_thread_diameter_mm | new | spoke | sí | retirar: cambia el significado del campo (rosca → alambre) |
| WSS-W10-nipple-thread-label | nipple_thread | new | spoke_nipple | no | conservar: precisa qué admite el campo sin reinterpretar ningún valor guardado |

## 5. Regresiones

| Id | Pregunta | Plantilla | Tipo | Issues esperados | Nota |
|---|---|---|---|---|---|
| SF1 | Q1 | bearing | válido | — | Cartucho de contacto angular con el par marcado: el único caso donde el par se exige. |
| SF2 | Q1 | bearing | desconocido | required_missing@bearing_inner_contact_angle_deg, required_missing@bearing_outer_contact_angle_deg | Contacto angular sin par publicado: pendiente, no aprobado. |
| SF3 | Q1 | bearing | válido | — | Una bolsa de bolas para dirección no debe pedir ni admitir ángulos. Con el parche del paquete quedaba con dos pendientes imposibles de resolver; con la base actual además puede escribirlos. |
| SF4 | Q1 | bearing | válido | — | Mismo caso con canastillo: Park Tool lo enumera aparte del cartucho. |
| SF5 | Q2 | tire | válido | — | La ficha de la 28c lleva sólo lo suyo. La 30c es otro producto con su propia ficha; ninguna de las dos hereda los límites de la otra. |
| SF6 | Q2/Q3 | tire | contradictorio | row_shape@tire_rim_configurations | Dos presiones para la misma configuración de este SKU. Antes de SR-Q2 esto se «resolvía» poniendo variantes distintas y quedaba válido. |
| SF7 | Q3 | fork | contradictorio | row_shape@fork_tire_clearance_configurations | Dos envolventes para el mismo rodado. Con el unique_by del paquete ambas pasaban. |
| SF8 | Q2/Q3 | fork | válido | — | Una horquilla aprobada por su fabricante para dos rodados: dos filas del mismo SKU, permitido y distinguible. |
| SF9 | Q4 | spoke | válido | — | Alambre 14G (2,0 mm), rosca laminada de 2,3 mm y su designación. Con el rótulo que el paquete proponía, este 2,3 se habría leído como un alambre de 2,3 mm. |

## 6. Fuentes

**S-PARK-HEADSET — Park Tool — Headset Standards** · https://www.parktool.com/en-us/blog/repair-help/headset-standards · reference_general

  - Enumera tres cosas distintas para una dirección: bolas sueltas, bolas en canastillo (retainer) y rodamiento de cartucho.
  - El par marcado en un cartucho, por ejemplo «36-45», dice dónde apoya: el primer número es el contacto interior con la pista o cono de centrado y el segundo el contacto con el cuadro.
  - Atribuye el ángulo al apoyo con la pista y con el cuadro. NO le atribuye un par de ángulos a las bolas sueltas ni al canastillo.

**S-CANECREEK-40 — Cane Creek — Forty, especificación** · https://www.canecreek.com/products/40 · oem_page (citada en la revisión W del 2026-09-06; no releída)

  - Publica pares 36×45 y 45×45 para sus cartuchos.

**S-SAPIM — Sapim — folleto 2018, p. 8, párrafo «Thread»** · https://www.sapim.be/sites/default/files/Sapim%20brochure%202018%20def%20A5%202018-Taiwanese%20LR.pdf · oem_manual (citado en la revisión W; no releído)

  - La rosca se lamina y no se corta: la del radio estándar de 2 mm se denomina FG 2.3 mm, es decir la rosca es más gruesa que el alambre.

**S-CONTI-HOOKLESS — Continental — Hookless vs. Hooked Rims** · https://www.continental-tires.com/us/en/tire-knowledge/hookless-vs-hooked-rims/ · oem_page (citada en la revisión W; no releída)

  - Los límites se publican por variante del neumático: 700×28c hookless 23 mm y 5,0 bar; 700×30c hookless 25 mm y 4,5 bar. Cada variante es un producto distinto en el catálogo.

**S-FOX40-2013 — FOX 2013 — Installing the 40** · https://tech.ridefox.com/fox_tech_center/owners_manuals/013/Content/Forks/40/40withDMS_Installation.html · oem_manual (citado en la revisión W; no releído)

  - Publica la envolvente por columna de producto (40 mm / 26"): pico 694 mm, borde 670 mm, ancho 71 mm. Una columna es una variante, no un surtido.

**S-BASE — Catálogo integrado (f3178bd3c860c421…)** · structural

  - bearing_construction admite «Cartucho sellado», «Bolas sueltas (bolsa)», «Canastillo con bolas» y desconocido, y la plantilla bearing tiene ball_diameter_in y ball_count_per_pack para envases de bolas.
  - spoke_thread_diameter_mm es origin new, sin hechos, y su rótulo actual es «Diámetro nominal de rosca del rayo».
  - bearing_size_code y bearing_application son origin existing; spoke_gauge también.

**S-ENGINE — Motor: product_spec_rows.dart, spec_rows_validate_internal_v1, guard de metadatos 0200** · structural

  - unique_by omite las filas a las que les falta una clave del grupo, así que toda columna de identidad debe ser required.
  - Una condición sólo puede mirar un escalar de la misma plantilla que no sea legacy; el guard rechaza la plantilla si el campo citado no está.

## 7. Límites y compuertas

- Esta revisión no reescribe el paquete congelado: entrega las correcciones con su preimagen para que root las adjudique junto a él.
- SR-Q1 depende de que WSS-W03-internal_construction entre antes que los dos parches de ángulo; si root sólo aplica W04, la condición cita un campo ausente y el guard de metadatos rechaza la plantilla.
- SR-Q1 también corrige una permisión que venía de la base, no del paquete: hoy una bolsa de bolas con destino «Dirección» puede escribir ángulos. Aplicar sólo la parte de exigencia deja ese hueco abierto.
- Ninguna corrección aprueba nada: SR-Q1 acota dónde se pide un dato, SR-Q2 y SR-Q3 hacen detectable una contradicción que antes pasaba, y SR-Q4 retira un cambio.
- Sigue fuera de alcance la intersección de límites entre dos productos, que es materia de relaciones con fuente.
- Ninguna corrección autoriza llenado, asignación ni publicación.
- Orden obligatorio: WSS-W03-internal_construction antes de SR-Q1.
- Las fixtures SF5 y SF6 reemplazan a tire_gp5000_two_variants_hookless del paquete.

| wheels-steering-suspension-packet-semantic-review-2026-09-07.json | `d45728eefb34ce50598e1d89d272bcf9bd92ff3c0283e91573404cf290e14171` |
