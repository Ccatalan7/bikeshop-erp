# Revisión independiente de las correcciones de root — ruedas, dirección y suspensión (2026-09-07)

Sobre la base final local `all-family-wss-integrated-2026-09-07.json` (`6ed9cdf73ae5d9fc…`). Revisión de representación: no se editó implementación, catálogo, pruebas, producción ni runtime.

**Los nueve puntos que root pidió verificar están correctos en la base final, incluido el que yo tenía factualmente al revés. Quedan siete hallazgos: dos contradicciones físicas todavía escribibles, una tercera en una fila, una divergencia entre clave y rótulo que contradice una decisión del mismo día, y tres asuntos de fidelidad o alcance que no son imposibilidades.**

**Corrección de un error mío, con fuente. En el paquete congelado propuse el token «MAX / sin canal de llenado». Enduro describe lo contrario: el MAX consigue el complemento completo de bolas por una ranura mecanizada en las pistas y por quitar la jaula. El token era falso al revés, y además excluyente frente a contacto angular cuando el propio fabricante vende 7902 2RS MAX y 3901 LLU MAX como angular contact. La corrección de root a texto literal más un eje aparte de retención es la respuesta correcta.**

## 1. Los nueve puntos, verificados contra la base

| Punto | Estado en la base | Ruta | Veredicto |
|---|---|---|---|
| El máximo de ancho interior de Continental no es un mínimo | La fila conserva dos columnas rotuladas «Ancho interior mínimo» y «Ancho interior máximo», con par ordenado entre ellas, así que el techo de 23 mm se escribe en la columna correcta y una inversión se marca. | `definitions.tire_rim_configurations.validation_rules.rows_schema` | correcto, con un residual en R6 |
| Una variante de neumático por ficha | La columna de variante desapareció y la identidad quedó en perfil del talón y método de montaje, dos vocabularios cerrados y requeridos. | `definitions.tire_rim_configurations…unique_by = [["rim_bead_profile","mounting_method"]]` | correcto |
| Una presión con su unidad | La fila tiene presión y unidad separadas, y la condición por fila sólo permite y exige la presión cuando la unidad está declarada en bar o psi. | `templates.tire.form_contract.row_conditions.fields.tire_rim_configurations` | correcto en la fila; ver R3 para el titular |
| Un Enduro MAX puede ser de contacto angular y tener canal de llenado | El diseño interno pasó de lista cerrada a texto literal del fabricante, así que «Angular-Contact, MAX-Design» se escribe entero; la retención de elementos quedó como eje aparte con «Complemento completo / sin jaula». | `definitions.bearing_internal_construction (text) + definitions.bearing_element_retention` | correcto; mi opción original era además falsa al revés (ver nota) |
| Los biseles de asiento de un cartucho no son el ángulo interno entre bolas y pistas | Los dos campos se rotularon como ángulo del bisel de apoyo y se condicionaron a construcción de cartucho y a la geometría de apoyo declarada; en la dirección, la condición por fila los permite sólo con cartucho y con el bisel correspondiente, y verifiqué que el exterior se condiciona al bisel exterior y no al interior. | `templates.bearing.form_contract.allowed_when + templates.headset.form_contract.row_conditions` | correcto en la condición; ver R1 por la clave |
| Construcción de cartucho no implica sellado | El vocabulario incorporó cartucho abierto, blindado y sellado sin confirmar, conservando los identificadores previos. | `definitions.bearing_construction.allowed_values` | correcto; ver R2 por una combinación que quedó abierta |
| Extremos del amortiguador por cuerpo y vástago | El extremo pasó a «Cuerpo» y «Vástago», que es lo que identifican las fichas OEM, con identidad por extremo; el selector sin extremo quedó legacy y el vocabulario de fijación sumó ojal con rodamiento y yoke. | `definitions.shock_end_configurations…end_position` | correcto |
| Alojamiento del cuadro frente a cazoleta EC/ZS | El asiento del cuadro dejó de nombrar cazoletas: su vocabulario es «Alojamiento para cazoleta prensada» y «Asiento mecanizado para cartucho». El código EC/ZS se quedó en las filas de la dirección, que es el producto que lo tiene. | `definitions.headset_port_configurations…seat_type frente a definitions.headset_bearing_configurations…seat_type` | correcto, y resuelve W05 mejor que mi propuesta |
| La altura entre coronas depende de la doble corona | Se agregó la construcción de coronas y los dos límites se condicionaron a «Doble corona», no al tipo de resorte como yo había propuesto. | `templates.fork.form_contract.allowed_when.crown_stack_min_mm / max_mm` | correcto; mi condición por aire o muelle era arbitraria |

## 2. Hallazgos accionables

### R1 · P1 · La clave dice ángulo de contacto y el rótulo dice bisel de apoyo; el ángulo de contacto interno se queda sin dueño numérico

**Evidencia.** `{"keys": ["bearing_inner_contact_angle_deg", "bearing_outer_contact_angle_deg"], "labels": ["Ángulo del bisel de apoyo interior", "Ángulo del bisel de apoyo exterior"], "origin": "new", "used_by": ["bearing"], "path": "definitions.bearing_inner_contact_angle_deg.label"}`

**Por qué importa.** El significado nuevo es el correcto: Park Tool describe el par marcado como el contacto con la pista o cono y con el cuadro, es decir superficies de apoyo. Pero root rechazó mi renombre de spoke_thread_diameter_mm con el argumento de que el rótulo original sí describía rosca, y aquí aplicó el movimiento contrario sobre una clave que sigue diciendo contact_angle. Queda la misma divergencia clave/rótulo que ese rechazo evitaba. Además, el ángulo de contacto interno de un cartucho de contacto angular es un dato real del fabricante —Enduro rotula 7902 y 3901 como angular contact— y tras el cambio no tiene ningún campo numérico: sólo cabe enterrado en el texto literal del diseño interno.

**Acción propuesta.** Las dos definiciones son origin new, sólo las usa bearing y no tienen hechos: renombrar la clave a bearing_inner_seat_bevel_deg y bearing_outer_seat_bevel_deg (alta nueva más retiro de la anterior, porque el compilador no renombra) deja clave y rótulo de acuerdo. Y decidir si el ángulo de contacto interno merece su propio campo numérico o se acepta como texto, dejándolo escrito.

**¿Imposibilidad física?** No. Simplifica o da fidelidad, pero no representa una imposibilidad; se declara así a propósito.

**Caso positivo.** Un cartucho de dirección con biseles 36 y 45 se escribe en los dos campos y la condición lo permite.

**Caso negativo.** Un 7902 2RS MAX de contacto angular no tiene dónde poner su ángulo de contacto como número; hoy se pierde o se escribe en prosa.

Fuentes: S-PARK-HEADSET, S-ENDURO-MAX, S-BASE

### R2 · P1 · Un cartucho abierto puede declarar sellado

**Evidencia.** `{"key": "bearing_seal_kind", "path": "templates.bearing.form_contract.allowed_when.bearing_seal_kind", "current": {"kind": "when", "rows": [[{"field": "bearing_construction", "operator": "in", "value_type": "token", "value": ["Cartucho sellado", "Cartucho abierto", "Cartucho blindado", "Cartucho (sellado sin confirmar)"]}]]}, "construction_options": ["Cartucho sellado", "Bolas sueltas (bolsa)", "Canastillo con bolas", "Desconocido / sin confirmar", "Cartucho abierto", "Cartucho blindado", "Cartucho (sellado sin confirmar)"]}`

**Por qué importa.** La designación de sellado quedó permitida para los cuatro tokens de cartucho, incluido «Cartucho abierto». Un rodamiento abierto no tiene designación de sello ni de blindaje: la combinación es una contradicción que hoy se guarda sin ruido, y es la simétrica del acierto de separar cartucho de sellado.

**Acción propuesta.** Condicionar bearing_seal_kind a bearing_construction en {Cartucho sellado, Cartucho blindado, Cartucho (sellado sin confirmar)}, dejando fuera el abierto. Un solo replace_field_contract sobre el bucket allowed_when.

**¿Imposibilidad física?** Sí: impide escribir algo que no puede existir.

**Caso positivo.** Un 7902 2RS declara construcción sellada y designación 2RS.

**Caso negativo.** Un cartucho declarado abierto con designación LLU se sigue guardando; con la condición deja de ser escribible.

Fuentes: S-ENDURO-MAX, S-BASE

### R3 · P2 · La presión de portada del neumático sigue amarrada a psi mientras la fila ya lleva su unidad

**Evidencia.** `{"key": "tire_max_pressure_psi", "unit": "psi", "origin": "new", "path": "definitions.tire_max_pressure_psi", "row_solution": "definitions.tire_rim_configurations…max_pressure + pressure_unit"}`

**Por qué importa.** La regla de una presión con su unidad se aplicó dentro de la fila y no al titular. Continental publica 5,0 bar; escribir ese dato en el campo de portada obliga a convertirlo a 72,5 psi, un número que ninguna fuente enuncia y que queda indistinguible de un dato declarado.

**Acción propuesta.** Reflejar en el titular lo que ya se hizo en la fila: un valor y su unidad, o dejar escrito que el campo es psi por convención y que una conversión se marca como derivada. La definición es origin new y no tiene hechos.

**¿Imposibilidad física?** No. Simplifica o da fidelidad, pero no representa una imposibilidad; se declara así a propósito.

**Caso positivo.** Una ficha que publica 102 psi escribe 102 sin ambigüedad.

**Caso negativo.** Una que publica 5,0 bar guarda 72,5 psi como si el fabricante lo hubiera dicho.

Fuentes: S-CONTI, S-BASE

### R4 · P2 · El diámetro de borde inflado puede superar al de pico

**Evidencia.** `{"field": "fork_tire_clearance_configurations", "columns": ["max_inflated_diameter_mm", "max_inflated_shoulder_diameter_mm"], "ordered_pairs": null, "path": "definitions.fork_tire_clearance_configurations.validation_rules.rows_schema.ordered_pairs"}`

**Por qué importa.** El manual FOX publica pico 694 mm y borde 670 mm: el borde se mide por dentro del pico, así que un borde mayor que el pico es imposible en un neumático inflado. La fila no tiene ningún par ordenado, de modo que la inversión se guarda.

**Acción propuesta.** Agregar ordered_pairs [["max_inflated_shoulder_diameter_mm","max_inflated_diameter_mm"]] al esquema de esa fila con replace_unpublished_rows_schema; las dos columnas son decimales de la misma unidad.

**¿Imposibilidad física?** Sí: impide escribir algo que no puede existir.

**Caso positivo.** Pico 694 y borde 670 pasan.

**Caso negativo.** Pico 670 y borde 694 se guardan hoy y con el par se marcan los dos extremos.

Fuentes: S-FOX40, S-BASE

### R5 · P2 · La carrera del amortiguador puede superar su entrecentros

**Evidencia.** `{"template": "rear_shock", "keys": ["stroke_mm", "eye_to_eye_mm"], "units": ["mm", "mm"], "current_pairs": null, "path": "templates.rear_shock.form_contract.scalar_ordered_pairs"}`

**Por qué importa.** Un amortiguador con carrera mayor o igual a su entrecentros no tiene longitud al final del recorrido: es imposible, no improbable. La plantilla no declara ningún par ordenado y el evaluador desplegado admite pares de la misma unidad, que aquí es milímetros en los dos.

**Acción propuesta.** Agregar scalar_ordered_pairs [["stroke_mm","eye_to_eye_mm"]] con replace_template_coherence. Conviene dejar escrito que el par admite la igualdad, así que atrapa la inversión grosera y no el margen real de compresión.

**¿Imposibilidad física?** Sí: impide escribir algo que no puede existir.

**Caso positivo.** 205 de entrecentros con 65 de carrera pasa.

**Caso negativo.** 65 de entrecentros con 205 de carrera se guarda hoy; con el par se marca en los dos campos.

Fuentes: S-BASE

### R6 · P3 · Nada distingue el techo hookless de un piso, aunque las columnas ya estén bien rotuladas

**Evidencia.** `{"field": "tire_rim_configurations", "columns": ["rim_internal_width_min_mm", "rim_internal_width_max_mm"], "both_optional": true, "path": "definitions.tire_rim_configurations.validation_rules.rows_schema"}`

**Por qué importa.** Los rótulos y el par ordenado ya impiden invertir el rango, y con eso el riesgo que root nombra se cubre en lo esencial. Lo que queda es una fila hookless con sólo el mínimo escrito, que se lee como «desde 23 mm» cuando la fuente dice «hasta 23 mm».

**Acción propuesta.** Una condición por fila que exija el ancho máximo cuando el perfil es hookless dejaría esa fila pendiente en vez de aparentemente completa.

**¿Imposibilidad física?** No. Simplifica o da fidelidad, pero no representa una imposibilidad; se declara así a propósito.

**Caso positivo.** Fila hookless con máximo 23 y presión 5,0 bar.

**Caso negativo.** Fila hookless con sólo mínimo 23: hoy pasa como completa. Advertencia explícita: esta regla no representa una imposibilidad física, sólo marca un dato faltante; el operador puede seguir escribiendo un techo equivocado y nada lo detectará.

Fuentes: S-CONTI, S-BASE

### R7 · P3 · Doble hilera y versión engrasable no tienen eje propio

**Evidencia.** `{"evidence": "Enduro rotula 3901 LLU MAX como doble hilera y ofrece versiones engrasables; ningún campo de bearing distingue una hilera de dos.", "path": "templates.bearing.fields"}`

**Por qué importa.** No es una contradicción: el texto literal del diseño interno puede contenerlo. Es un dato estructural real que queda fuera de cualquier filtro.

**Acción propuesta.** Decidir si merece un eje propio o se acepta dentro del literal. Sin urgencia y sin bloquear nada.

**¿Imposibilidad física?** No. Simplifica o da fidelidad, pero no representa una imposibilidad; se declara así a propósito.

**Caso positivo.** El literal «MAX-Design, Double-Row, Angular-Contact» conserva el dato.

**Caso negativo.** No se puede buscar por doble hilera; ninguna ficha queda mal por eso.

Fuentes: S-ENDURO-MAX

## 3. Casos revisados

| Id | Punto | Plantilla | Tipo | Hoy | Después | Nota |
|---|---|---|---|---|---|---|
| RC1 | R2 | bearing | positivo | — | sin observación | MAX y contacto angular juntos en el literal, con la retención como eje aparte. Es el caso que el token cerrado impedía. |
| RC2 | R2 | bearing | negativo | se guarda sin observación | field_constraint@bearing_seal_kind | Un cartucho abierto con designación de sello. |
| RC3 | R1 | bearing | positivo | — | sin observación | Los dos biseles del par marcado 36-45, ahora con el significado que Park describe. |
| RC4 | R1 | bearing | desconocido | — | sin observación | Contacto angular declarado y su ángulo interno sin campo numérico: hoy queda fuera del dato estructurado. |
| RC5 | R4 | fork | negativo | se guarda sin observación | row_shape@fork_tire_clearance_configurations | Borde mayor que pico: imposible en un neumático inflado. |
| RC6 | verificación | fork | positivo | — | sin observación | La altura entre coronas queda atada a la doble corona, no al tipo de resorte. |
| RC7 | verificación | fork | negativo |  |  | Una horquilla de una corona no tiene altura entre coronas. La corrección de root ya lo impide. |
| RC8 | R5 | rear_shock | negativo | se guarda sin observación | range_order@stroke_mm, range_order@eye_to_eye_mm | Carrera mayor que entrecentros. |
| RC9 | verificación | rear_shock | positivo | — | sin observación | Cuerpo y vástago, que es como el fabricante identifica los extremos; la posición en el cuadro deja de decidirlo. |
| RC10 | verificación | tire | positivo | — | sin observación | Un solo SKU con dos configuraciones, cada presión con su unidad y el techo hookless en la columna de máximo. |
| RC11 | R6 | tire | desconocido | — | sin observación | El techo escrito como piso: pasa hoy y seguiría pasando salvo que se exija el máximo en hookless, que es una marca de completitud y no una imposibilidad. |
| RC12 | verificación | frame | positivo | — | sin observación | El cuadro declara su alojamiento sin comprometerse con EC o ZS; la alternativa EC44/30 frente a ZS44/30 deja de estar bloqueada por el SHIS registrado. |
| RC13 | verificación | headset | positivo | — | sin observación | Cartucho arriba con sus dos biseles y bolas sueltas abajo sin ángulos: la condición por fila lo permite y no exige lo que no existe. Verifiqué que el ángulo exterior se condiciona al bisel exterior y el interior al interior. |

## 4. Límites

- El ensayo SQL de 105 plantillas, 1205 usos y 167 casos con reversión prueba que la representación se guarda y se lee; no prueba que un dato sea cierto ni que una pieza calce.
- Ninguna de estas correcciones aprueba un montaje: neumático con llanta, horquilla con cuadro, amortiguador con cuadro y dirección con tubo siguen necesitando una relación con fuente.
- R1, R3, R6 y R7 no representan imposibilidades físicas. R1 y R3 son fidelidad a la fuente y coherencia entre clave y rótulo; R6 es una marca de dato faltante; R7 es alcance de búsqueda. Sólo R2, R4 y R5 impiden escribir algo que no puede existir.
- No certifico ninguna familia como completa ni autorizo sembrar este catálogo ampliado. El estado productivo verificado llega a la migración 2300 y este catálogo no está sembrado.
- Un tubo de dirección roscado antiguo sigue sin un campo propio en el cuadro más allá del texto del SHIS y del asiento «Otro»; no lo propongo en esta ronda porque no aparece en los casos revisados.

## 5. Fuentes

**S-ENDURO-MAX — Enduro Bearings — páginas de producto de suspensión y «Enduro Innovations»** · https://cycling.endurobearings.com/products/7902-2rs-max · oem_page

  - Los MAX consiguen el complemento completo de bolas por una ranura mecanizada en las pistas y por eliminar la jaula; el fabricante lo describe como 35–40 % más capacidad de carga.
  - MAX y contacto angular NO son excluyentes: el 7902 2RS MAX se rotula «Angular-Contact, MAX-Design, Radial»; el 7900 1ZS MAX igual; el 3901 LLU MAX es «MAX-Design, Double-Row, Angular-Contact».
  - Hay versiones MAX selladas y engrasables, y variantes de doble hilera.

**S-PARK-HEADSET — Park Tool — Headset Standards** · https://www.parktool.com/en-us/blog/repair-help/headset-standards · reference_general

  - Un cartucho marcado «36-45»: el primer número es el contacto interior con la pista o cono de centrado y el segundo el contacto con el cuadro.
  - Enumera bolas sueltas, bolas en canastillo y cartucho como tres cosas distintas; no atribuye ese par a las dos primeras.

**S-CONTI — Continental — Hookless vs. Hooked Rims** · https://www.continental-tires.com/us/en/tire-knowledge/hookless-vs-hooked-rims/ · oem_page (citada en la revisión W del 2026-09-06; no releída aquí)

  - Publica un límite superior de ancho interior y una presión máxima por variante y perfil: 700×28c hookless 23 mm y 5,0 bar. La cifra es un techo, y la presión viene en bar.

**S-FOX40 — FOX 2013 — Installing the 40** · https://tech.ridefox.com/fox_tech_center/owners_manuals/013/Content/Forks/40/40withDMS_Installation.html · oem_manual (citado en la revisión W; no releído aquí)

  - Columna 40 mm/26": diámetro de pico ≤694 mm y diámetro de borde ≤670 mm del neumático inflado; el borde se mide por dentro del pico.
  - La comprobación de stack total 105–166,8 mm es de la corona direct mount de doble corona.

**S-SHELDON — Sheldon Brown — glosario de dirección y de rodamientos** · https://www.sheldonbrown.com/gloss_he-i.html · reference_general

  - Distingue el rodamiento de cartucho de las bolas y pistas de una dirección convencional; el ángulo de las pistas es una propiedad del asiento, no del envase de bolas.

**S-BASE — Base final local (6ed9cdf73ae5d9fc…)** · structural

  - Estado real de campos, dominios, condiciones y condiciones por fila tras las correcciones de root.

## 6. Lo revisado, con su hash

| Artefacto | SHA-256 |
|---|---|
| all-family-wss-integrated-2026-09-07.json | `6ed9cdf73ae5d9fc0aa2284bb4691f4f1eca958c2762c5ea1e7076c5f9358b18` |
| wss-root-decisions-2026-09-07.json | `9afde6ed983b76e0eea953461d71a10c5a8125e2f5b4a5bcc7957b0d3c297799` |
| wss-representation-cases-2026-09-07.json | `322a9279a71b8eb51f19456ae5041b153707af9d0991741be61a0dc70f8560ee` |
| scripts/inventory/normalize_wss_review.py | `f30311cd48dd522c4b757db4466550b9cc246c691587df917c33a357af4c240d` |
| wheels-steering-suspension-implementation-packet-2026-09-07.json (mi paquete, congelado) | `c03ebe91fa7e56d32ffb44a0a6ba3b00a4ff917b296068773e2a95027444b3bd` |
| wheels-steering-suspension-packet-semantic-review-2026-09-07.json (mi revisión previa) | `d45728eefb34ce50598e1d89d272bcf9bd92ff3c0283e91573404cf290e14171` |

## 7. Lo que esta revisión no hace

- Ninguna familia queda certificada como completa.
- No se autoriza llenado, asignación ni siembra de este catálogo ampliado.
- El ensayo SQL prueba representación, no verdad del dato ni ajuste mecánico.

| wss-root-corrections-independent-review-2026-09-07.json | `ba67b55bf392f2fecf51f526ecfc63c1f69f8e6b299d65adad7afd8849e3dd4d` |
