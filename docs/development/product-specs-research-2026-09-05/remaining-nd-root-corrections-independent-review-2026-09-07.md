# Revisión independiente de la adjudicación de root al paquete ND restante (2026-09-07)

Revisión de representación sobre `all-family-remaining-nd-integrated-2026-09-07.json`. No se editó implementación, catálogos, producción ni runtime.

**Checkpoint.** El hash citado en el encargo es `cdd23c6b2a024db9…` y el del archivo es `f1826a9a782a2007…`. El artefacto de casos de root declara `f1826a9a782a2007…` como catálogo, que coincide con el archivo, así que base y casos son coherentes entre sí y lo desalineado es la referencia. Revisé contra el archivo real.

**La adjudicación es correcta en los ocho puntos, incluidos dos donde yo estaba equivocado: mis identidades confundían columnas requeridas con columnas suficientes, y mi guarda de presión excluía un número OEM legítimo. Quedan seis hallazgos, dos de ellos retirando afirmaciones mías de la ronda anterior, y el hash de base citado no corresponde al archivo.**

## 1. La adjudicación, punto por punto

| Punto | Qué hizo root | Mi veredicto | Residual |
|---|---|---|---|
| Las siete identidades que propuse | rechazadas: required no demuestra identidad | Root tiene razón y el error es mío de método. Comprobé que las columnas de la identidad fueran requeridas, que es una condición necesaria, y di por probado que fueran suficientes, que es otra cosa. Cada contraejemplo muestra un par de filas legítimas que mi clave habría fundido: un mismo emisor con dos programas, un compartimento medido cerrado y expandido, dos nutrientes escritos como «Otro», una base de porción sin su cantidad, y miembros, contrapartes y revisiones que mis claves dejaban fuera. | N4 |
| Programa de clasificación en el nivel de seguridad | agregado rating_scheme | Correcto. Con el programa como columna, el mismo emisor puede rotular dos niveles del mismo componente sin contradicción. Estado: ('rating_scheme', 'text', False). | — |
| Dimensión física de la botella distinta del diámetro de acople | bottle_diameter_mm rotulado como diámetro de acople y gateado; bottle_body_dimensions nuevo | Correcto y mejor que mi parche: yo sólo condicioné el campo, root además separó la medida física con su configuración y su referencia, que es lo que faltaba para una botella TWIST o de sección no circular. | N6 |
| Presiones por magnitud, unidad y configuración | pump_pressure_specifications con quantity_kind, value, unit y configuration | Correcto, y de paso corrige un error mío: mi parche excluía la presión máxima de un inflador de CO2, y eso era una restricción incorrecta. El fondo de escala del AirBooster G2 es un número publicado y legítimo; lo que faltaba no era prohibirlo sino decir de qué magnitud se trata. | N5 |
| El paso se expresa en mm o en TPI con independencia del diámetro | thread_pitch_system rotulado «Forma declarada de expresar el paso» | Correcto. Mi rótulo decía «Sistema de designación de la rosca», que confundía el diámetro con el paso y habría chocado con el 36 mm × 24 TPI que documenta Park Tool. Las opciones de root nombran sólo la expresión del paso. | — |
| El casco separa uso, construcción y público | helmet_kind pasa a uso declarado sin «Integral» ni «Niño»; construcción en su campo; público aparte | Correcto y más completo que mi parche, que sólo retiraba «Niño». «Integral» describe la carcasa y ahora vive en la construcción; ningún caso válido queda bloqueado porque la construcción es texto libre. | — |
| Otra variante del soporte no es una configuración de este SKU | acotado | Coincide con lo que yo mismo concluí para el neumático en la revisión semántica del paquete de ruedas: una variante distinta es otro producto, no otra fila. | — |
| Mis fixtures RF9, RF11 y RF13 | corregidos: tokens fuera del catálogo y números de fila sin transporte decimal | Aceptado sin reserva. Escribí cantidades de fila como enteros JSON y valores que no pertenecían a los vocabularios; eran fixtures de forma y no evidencia de inventario, y así deben quedar rotulados. | — |

## 2. Hallazgos

### N1 · P1 · El hash de base que citas no corresponde al archivo

**Evidencia.** `{"quoted_by_root": "cdd23c6b2a024db9668e442d8b24ffc4d74a68742a58fcf0f6dc817824730a29", "actual_file_sha256": "f1826a9a782a200754b21ba6c5420af0f9c39b89482503cab77f96779fc739b1", "catalogue_sha256_declared_by_root_cases_file": "f1826a9a782a200754b21ba6c5420af0f9c39b89482503cab77f96779fc739b1", "match": true, "searched": "ningún JSON de la carpeta tiene el hash citado"}`

**Por qué.** El archivo en disco no tiene el hash del mensaje. El artefacto de casos del propio root declara como catálogo el hash real, así que el par base/casos es coherente entre sí y lo que quedó desalineado es la referencia del checkpoint. Revisé contra el archivo real y lo digo para que la cadena de hashes no arrastre una referencia muerta.

**Acción propuesta.** Corregir la referencia del checkpoint al hash real, o publicar el artefacto que sí tiene el hash citado si existe fuera de esta carpeta.

**¿Imposibilidad física?** No; se declara así a propósito.

Fuentes: S-BASE

### N2 · P1 · Mi regla carrera ≤ entrecentros no es universal: la retiro

**Evidencia.** `{"previous_finding": "R5 de wss-root-corrections-independent-review-2026-09-07", "template": "rear_shock", "keys": ["stroke_mm", "eye_to_eye_mm"], "missing_datum": ["referencia del entrecentros (extendido, comprimido o en reposo)", "sentido de accionamiento (compresión o tracción)"], "mount_kind_vocabulary_includes": "Trunnion"}`

**Por qué.** La regla se apoya en dos supuestos que la ficha no declara: que el entrecentros se mide con el amortiguador extendido y que comprimir lo acorta. Para un amortiguador convencional ambos se cumplen y la cota se sigue; para uno de tracción el conjunto trabaja estirándose y el sentido del recorrido respecto de la cota publicada ya no es el mismo, así que la desigualdad no se deduce de la geometría. No pude verificar en esta ronda un modelo concreto de tracción con fuente primaria, y precisamente por eso retiro la afirmación universal en vez de defenderla. Un montaje trunnion agrava el punto: su cota publicada tiene otra referencia y el campo no distingue cuál se usó.

**Acción propuesta.** No agregar el par escalar tal como lo propuse. Si el orden interesa, antes hace falta el dato que falta: una referencia declarada del entrecentros y un sentido de accionamiento; sólo con referencia extendida y accionamiento por compresión la cota se sostiene, y aun así es floja, porque el límite real es que la longitud comprimida supere el cuerpo y el herraje, no que sea mayor que cero. Y no debe generalizarse: recorrido de horquilla frente a eje-corona, o recorrido de tija frente a longitud total, son geometrías distintas y no heredan esta regla.

**¿Imposibilidad física?** No; se declara así a propósito.

Fuentes: S-BASE

### N3 · P1 · FOX dice «edge», no «shoulder», y no define dónde se miden pico y borde

**Evidencia.** `{"previous_finding": "R4 de wss-root-corrections-independent-review-2026-09-07", "oem_terms": ["Maximum Peak Tire Diameter 694 mm", "Maximum Edge Tire Diameter 670 mm", "Maximum Tire Width 71 mm", "Maximum Tire Size 26 x 2.80"], "my_column": "max_inflated_shoulder_diameter_mm", "same_tire_and_mode": true, "oem_defines_measurement_points": false, "oem_states_simultaneity": false}`

**Por qué.** La mitad de mi premisa se confirma: el manual dice que todos los valores suponen el neumático instalado y completamente inflado, así que hablan del mismo neumático en el mismo modo. La otra mitad no: el manual no define dónde se miden el pico y el borde, ni afirma que los máximos deban cumplirse a la vez. El orden pico ≥ borde se sigue del sentido corriente de las palabras y de los números publicados, no de una definición de la fuente. Además mi columna dice «shoulder» donde el fabricante dice «edge», y esa deriva de vocabulario es la que convierte una lectura en una ley.

**Acción propuesta.** Rebajar el par ordenado de imposibilidad física a comprobación de cordura con su supuesto escrito, y conservar el término del fabricante: renombrar la columna a borde o dejar que measurement_method guarde la palabra exacta del manual. Si otro fabricante midiera el borde en otro punto, el orden podría invertirse legítimamente y la comprobación debe poder desactivarse por fuente.

**¿Imposibilidad física?** No; se declara así a propósito.

Fuentes: S-FOX40

### N4 · P1 · Dos filas idénticas salvo el valor admitido siguen conviviendo

**Evidencia.** `{"fields_without_identity": ["tool_capabilities", "security_rating_configurations", "bar_clamp_configurations", "bag_member_configurations", "co2_cartridge_configurations", "eyewear_lens_configurations", "nutrition_facts"], "worked_example": {"field": "tool_capabilities", "row_a": {"operation": "Extraer", "target_standard": "Shimano HG", "supported": true}, "row_b": {"operation": "Extraer", "target_standard": "Shimano HG", "supported": false}, "discriminating_columns_empty": ["member", "brand_scope", "adapter_model", "source_url"]}}`

**Por qué.** Los contraejemplos de root derriban mis claves, no el problema que las motivaba. Cuando las columnas que distinguen dos filas legítimas están vacías en las dos, lo que queda es una afirmación y su negación sobre el mismo objeto, y hoy no la detecta nada. No propongo volver a una identidad más ancha: con columnas opcionales el motor omite las filas a las que les falta una clave, así que una identidad que incluyera el miembro o el programa no se dispararía justo en el caso que importa.

**Acción propuesta.** Dejarlo escrito como carencia del motor y no como campo faltante: haría falta una comprobación de que dos filas no sean idénticas en todas sus celdas presentes, que hoy no existe y que no se puede expresar con unique_by ni con condiciones por fila. Mientras tanto, la contradicción es visible sólo para quien lee la ficha.

**¿Imposibilidad física?** No; se declara así a propósito.

Fuentes: S-BASE, S-ROOT

### N5 · P2 · La presión escalar de la bomba quedó sin magnitud declarada

**Evidencia.** `{"template": "pump", "scalar": "max_pressure_psi", "label": "Presión máxima declarada", "allowed_when": {"kind": "always"}, "rows_field": "pump_pressure_specifications", "rows_columns": [["quantity_kind", "token", true], ["value", "decimal", true], ["unit", "token", true], ["configuration", "text", true], ["target_tire", "text", false], ["cartridge_gas_g", "decimal", false], ["tires_inflated", "integer", false], ["conditions", "text", false], ["source_url", "url", false]]}`

**Por qué.** La fila nueva resuelve bien el problema: distingue fondo de escala, límite de trabajo y estimación con neumático y cartucho. El escalar quedó permitido siempre, rotulado «Presión máxima declarada» y sin decir de qué magnitud es, de modo que en él caben las tres cosas y ninguna se distingue después. Es la misma ambigüedad que la fila vino a cerrar, conservada en el titular.

**Acción propuesta.** Decidir explícitamente qué guarda el titular: la cifra de portada tal como aparece, con su magnitud implícita documentada, o restringirlo a las clases donde «presión máxima» tiene un solo significado. No propongo retirarlo: mi intento anterior de excluir el CO2 ya resultó ser una restricción incorrecta.

**¿Imposibilidad física?** No; se declara así a propósito.

Fuentes: S-ROOT, S-BASE

### N6 · P3 · Referencias de medida exigidas como texto libre, que es la forma que root rechazó en mi propuesta

**Evidencia.** `{"bottle_body_dimensions": [["dimension", "token", true], ["value_mm", "decimal", true], ["configuration", "token", true], ["datum", "text", true], ["source_url", "url", false]], "pump_pressure_specifications_configuration": [["configuration", "text", true]], "root_principle": "required no debe obligar a inventar un dato que el fabricante no publica (rechazo de mi member_revision requerida)"}`

**Por qué.** En las dos filas nuevas hay un texto libre requerido: la referencia de la medida en la botella y la configuración en las presiones. Cuando la fuente publica un número sin decir dónde lo mide ni en qué configuración, el operador tiene que escribir algo igualmente. Es la misma forma que motivó rechazar mi revisión requerida del miembro; lo señalo por simetría, no porque tenga una preferencia entre las dos posturas.

**Acción propuesta.** Si la exigencia se mantiene, un vocabulario cerrado con un valor explícito de «no declarado» deja constancia de que la fuente calla, en vez de invitar a rellenar. Si no, basta con volverlas opcionales. Cualquiera de las dos es coherente; lo que no lo es son las dos reglas a la vez.

**¿Imposibilidad física?** No; se declara así a propósito.

Fuentes: S-ROOT, S-BASE

## 3. Las dos preguntas técnicas

### ¿La regla carrera ≤ entrecentros es universal, incluidos los amortiguadores de tracción?

No, y la retiro. Depende de dos datos que la ficha no guarda: con qué referencia se publicó el entrecentros y en qué sentido trabaja el amortiguador. Con referencia extendida y accionamiento por compresión la cota se sostiene; fuera de ese caso no se deduce. No verifiqué un modelo de tracción con fuente primaria en esta ronda, así que tampoco afirmo que falle: afirmo que no está demostrada. El datum que hace falta es una referencia declarada del entrecentros y un sentido de accionamiento, y aun con ellos la cota es floja frente al límite real, que es que la longitud comprimida supere el cuerpo y el herraje.

**No generalizar.** Ninguna otra familia hereda esto. El recorrido de una horquilla frente a su eje-corona, el de una tija frente a su longitud y la carrera de una bomba de suspensión son geometrías distintas.

### ¿El borde y el pico de FOX se refieren al mismo neumático y al mismo modo?

Sí en cuanto al neumático y al modo: el manual dice expresamente que todos los valores suponen el neumático instalado y completamente inflado. No en cuanto a la definición: no dice dónde se miden el pico ni el borde, ni que los máximos deban cumplirse a la vez. Con eso, el orden pico ≥ borde es una lectura razonable del vocabulario y de los números, no una regla enunciada por la fuente, y mi columna además cambió «edge» por «shoulder». Queda como comprobación de cordura con su supuesto escrito, no como imposibilidad física.

## 4. Límites

- Las 240 pruebas Dart y el ensayo SQL pendiente prueban que la representación se guarda, se lee y se valida; no prueban que un dato sea cierto ni que una pieza calce ni que un casco esté homologado.
- Las afirmaciones concretas sobre ABUS, Topeak TT9635B y AirBooster G2 las aporta root; no las releí y las trato como la forma del dato que hay que representar.
- No certifico ninguna familia como completa ni autorizo llenado, asignación ni siembra.
- N2 y N3 corrigen dos hallazgos míos de la ronda anterior; el resto de esa entrega no se toca aquí.

## 5. Fuentes

**S-FOX40 — FOX 2013 — Installing the 40 (manual del propietario)** · https://tech.ridefox.com/fox_tech_center/owners_manuals/013/Content/Forks/40/40withDMS_Installation.html · oem_manual

  - La tabla del 40 de 26" publica «Maximum Tire Size 26 x 2.80», «Maximum Peak Tire Diameter 694 mm», «Maximum Edge Tire Diameter 670 mm» y «Maximum Tire Width 71 mm».
  - Dice expresamente que todos los valores suponen el neumático instalado y completamente inflado: es el mismo neumático y el mismo modo.
  - NO define dónde se miden el pico ni el borde, y NO dice que los máximos deban cumplirse a la vez.
  - La corona direct mount exige un rango de stack total de 105 a 166,8 mm, y describe 6 mm de holgura con un 2,80" al final del recorrido.

**S-PARK-THREAD — Park Tool — conceptos de rosca y estándares de pedalier** · https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts · reference_general

  - La forma de expresar el paso es independiente del diámetro nominal: el pedalier italiano se documenta como 36 mm × 24 TPI, un diámetro métrico con paso en hilos por pulgada.

**S-SOLDSECURE — Sold Secure — estructura de categorías de certificación** · https://www.soldsecure.com/ · reference_general (estructura de programas; el caso concreto ABUS lo aporta root y no lo releí)

  - Sold Secure clasifica por programa de vehículo y por nivel, de modo que un mismo producto puede tener grados distintos en programas distintos del mismo emisor.

**S-ROOT — Adjudicación de root: wss/nd decisions y casos integrados** · adjudication

  - ABUS GRANIT XPlus 540 con Sold Secure Pedal Cycle Diamond y Powered Cycle Gold; Topeak TT9635B mide el mismo compartimento cerrado y expandido; Topeak AirBooster G2 publica 160 psi como fondo de escala.
  - Estas afirmaciones concretas las aporta root; no las releí en esta ronda y las trato como la forma del dato que hay que representar, no como evidencia verificada por mí.

**S-BASE — Base local integrada (f1826a9a782a2007…)** · structural

  - Estado real de campos, dominios y condiciones tras la adjudicación.

## 6. Lo revisado, con su hash

| Artefacto | SHA-256 |
|---|---|
| all-family-remaining-nd-integrated-2026-09-07.json (hash real) | `f1826a9a782a200754b21ba6c5420af0f9c39b89482503cab77f96779fc739b1` |
| all-family-remaining-nd-cases-integrated-2026-09-07.json | `14b6905563349eda7581cf651819f3b07e9c8de72de313c7250c1424de46f4ac` |
| scripts/inventory/normalize_remaining_nd_review.py | `d6c2a7c92175277fcf1d90b6e0a6e2d89f027c0bafa30034e7e6fd74521519f8` |
| scripts/inventory/compile_product_spec_remaining_nd_addendum.py | `c538db08a36058e4de90783718fc6e618a2b78ef970888d38ec4ad960c4e5aff` |
| remaining-non-drivetrain-addendum-review-2026-09-07.json (mi paquete, congelado) | `fd78724798b4c83773e599d33e6705d51fb5298526743470f5a223f5f586d0e1` |
| wss-root-corrections-independent-review-2026-09-07.json (mi revisión previa, contiene R4 y R5) | `ba67b55bf392f2fecf51f526ecfc63c1f69f8e6b299d65adad7afd8849e3dd4d` |

## 7. Lo que esta revisión no hace

- Ninguna familia queda certificada como completa.
- No se autoriza llenado, asignación ni siembra.

| remaining-nd-root-corrections-independent-review-2026-09-07.json | `91ae01602c8781a02dbe4fb5a55f5bdad7e363e58745e5aa4524e119550a0b57` |
