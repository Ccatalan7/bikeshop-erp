# Auditoría de los 33 registros ambiguos y de revisión de negocio

Claude, revisor independiente · 2026-09-07

No asigno ninguna plantilla, no escribo ningún hecho y no toco base de datos, runtime, archivos de root, pruebas permanentes, asignaciones ni compuertas. Ningún nombre comercial se convierte en tipo o modelo, y ningún proveedor ni costo se convierte en producto técnico.

## De dónde salió cada cosa

| Artefacto | SHA-256 | Para qué lo usé |
|---|---|---|
| unmapped-product-ficha-codex-review-2026-09-06.json | `72661039d8b5ad9662a771734ba6dbe7e2958a1b3cba9979f1a7958449ee140d` | los 33 ids y su preimagen literal |
| all-product-review-register-2026-09-06.json | `88ef5edaf407d7883f791a858d651006eb8f6a0f64c676b9e56cfe5b85dd7965` | sku, actividad, hechos e imagen |
| product-identity-image-review-2026-09-06.json | `b46147aaa3200df701da0236104c21ce9fee5e395afde707a1125b59b2195b66` | observación de imagen con sha por pieza |
| all-family-cardinality-integrated-2026-09-07.json | `934ce172a6f3eaf8fa8dc616a912d161c965840b97b647fbee23870ccc154562` | existencia de la clave, su id y su familia |

La revisión visual que cito es la lectura de esos registros de imagen, con el sha256 de cada archivo. **No abrí los archivos de imagen**, y por eso ninguna decisión se apoya en algo que yo diga haber visto.

## Resultado

| Cuenta | Valor |
|---|---|
| registros revisados | 33 |
| ambiguous / business_record_review | 22 / 11 |
| decisión respaldada | 20 |
| decisión pendiente | 13 |
| no son producto técnico | 12 |
| con clave de plantilla propuesta | 10 |
| ya inactivos en el registro | 5 |
| siguiente paso a Codex / a Claude | 26 / 7 |

Ninguna investigación siguiente queda asignada al dueño.

## Lo que encontré

### A1 · Cinco alternativas de Codex no son claves de plantilla

De las alternativas propuestas, brake_cable_boot, brake_detangler, complete_brake, handlebar_cover, protective_cover no existen como clave. Cuatro tienen una clave real muy cercana —bmx_cable_detangler, handlebar_covering, bike_protection y, para la gomita, control_small_part— y una, complete_brake, no es una clave sino una familia técnica. Corregirlas es la mitad del trabajo de este lote.

### A2 · complete_brake es el único caso donde clave y familia se separan de verdad

En las 105 plantillas de la base hay 104 familias técnicas distintas, y la única compartida es complete_brake, entre hydraulic_disc_brake y mechanical_disc_brake. Es exactamente la familia que Codex nombró para el freno Tanke, así que el aviso de no confundir template_key, template_id y technical_family se paga justo en ese registro.

### A3 · La serie NNV es una señal, no una determinación

182 productos llevan sku NNV: 143 sin categoría y 173 sin hechos, lo que explica que 21 de estos 33 la lleven. Pero 17 registros NNV sí tienen plantilla asignada, así que el prefijo no decide nada por sí solo y no lo uso como criterio.

### A4 · Dos rótulos de proveedor están demostrados y tres no

«Bettabikes» aparece como sufijo en 29 nombres y «ALIEXPRESS» en otro, así que los registros que llevan sólo ese nombre son rótulos. «Andes», «Dr. Bike» y «MKR» no aparecen en ningún otro nombre: parecen lo mismo, pero no lo puedo demostrar y quedan pendientes. La diferencia entre los dos grupos es evidencia, no intuición.

### A5 · La revisión de imagen ya resolvía siete ambigüedades

Siete de los 22 ambiguos tienen imagen revisada con sha256 por pieza en product-identity-image-review-2026-09-06.json, y en cinco casos la observación resuelve exactamente la duda que el propio informe declaraba irresoluble sin imagen. Leí esos registros; no abrí los archivos de imagen, y lo digo en cada uno.

### A6 · Los campos de la plantilla sirven para elegir entre dos candidatas

La gomita de V-Brake se decide mirando qué representa cada plantilla: control_small_part lleva fits_cable_diameter_mm, fits_housing_diameter_mm y noodle_angle_deg, que son el recorrido del cable de un V-Brake; brake_small_part es genérica. Igual con el eje: hub_axle lleva cones_and_locknuts_included, que es lo que la imagen muestra. Elegir por los campos es verificable; elegir por el nombre no.

### A7 · Once registros no son productos técnicos y no necesitan ficha

Servicios, gastos y un documento de crédito. El caso que más fácil se equivoca es la nota de crédito por una cámara Chaoyang: cita una pieza con medida y válvula, y aun así su identidad es el documento. Asignarle la plantilla tube convertiría un ajuste contable en inventario técnico.

### A8 · Cinco registros ya están inactivos

Centrado de Rueda, Cubetas Motor Americano, los dos Piñón 1v y Restauración de Freno están inactivos en el registro global: cinco de los 33. No cambia el análisis, pero sí la prioridad: ninguno de ellos bloquea el avance de fichas.

## Los 33, uno por uno

| Nombre | sku | Decisión | Familia propuesta | Confianza | Siguiente |
|---|---|---|---|---|---|
| ALIEXPRESS | NNV7 | respaldada | — | alta | Codex |
| Andes | NNV8 | pendiente | — | baja | Codex |
| BETTABIKES | NNV15 | respaldada | — | alta | Codex |
| Centrado de Rueda BettaBikes | NNV36 | respaldada | — | alta | Codex |
| Costo de bicicleta | NNV41 | respaldada | — | alta | Codex |
| Cubetas Motor Americano BMX Bettabikes | NNV42 | pendiente | — | baja | Codex |
| Diagnóstico | 00000000 | respaldada | — | alta | Codex |
| Dr. Bike | NNV47 | pendiente | — | baja | Codex |
| Eje de Motor Set Up Bikes | NNV48 | pendiente | — | baja | Codex |
| Gasto por transporte | NNV60 | respaldada | — | alta | Codex |
| Instalación rayo trasero disco + centrado zo | NNV68 | respaldada | — | alta | Codex |
| Juego de Tuercas Laterales Motor + Rodamient | NNV71 | pendiente | — | baja | Codex |
| MKR | NNV102 | pendiente | — | baja | Codex |
| Nota de Crédito Por Cámara Chaoyang 700x25/3 | NNV111 | respaldada | — | alta | Codex |
| Pack | NNV112 | pendiente | — | baja | Codex |
| Piñon 1v Bettabikes | NNV125 | pendiente | — | baja | Codex |
| Piñon 1v Monsoon Bettabikes | NNV126 | pendiente | — | baja | Codex |
| Restauración de Freno Hidráulico | NNV154 | respaldada | — | alta | Codex |
| Rotor Freno Trasero BMX PadroBikes | NNV162 | respaldada | `bmx_cable_detangler` · familia `bmx_cable_detangler` | media-alta | Claude |
| Set Cubre Manubrio 125mm/220mm Black | 24131 | respaldada | `handlebar_covering` · familia `handlebar_covering` | media-alta | Claude |
| Test | ACC-TES-59147 | pendiente | — | baja | Codex |
| FUNDA PROTECTORA BEST COLOR GRIS | 17367 | respaldada | `bike_protection` · familia `bike_protection` | media | Codex |
| Freno Hidráulico Delantero Tanke 4 Pistones  | NNV56 | pendiente | `hydraulic_disc_brake` · familia `complete_brake` | media | Codex |
| GOMITA PARA FRENO V-BRAKE COMPATIBLE / GENER | 1541 | respaldada | `control_small_part` · familia `control_small_part` | media-alta | Claude |
| EJE BLOQUEO SOLO DELANTERO (min.10pcs) ALTER | PO02770019255 | respaldada | `hub_axle` · familia `hub_axle` | alta | Codex |
| EJE BLOQUEO TRASERO 7/8 9V. COMPATIBLE / GEN | PO02633001073 | respaldada | `hub_axle` · familia `hub_axle` | alta | Codex |
| Cámara nueva + servicio de cambio | M010 | respaldada | — | alta | Codex |
| Descontaminación Disco de Freno | NNV43 | respaldada | — | alta | Codex |
| Retiro de Óxido | NNV155 | respaldada | — | alta | Codex |
| ACEITE NACIONAL | 67 | respaldada | `workshop_chemical` · familia `workshop_chemical` | alta | Claude |
| Aceite Mineral Chepark | 2854 | pendiente | `brake_fluid` · familia `brake_fluid` | media | Claude |
| LIMPIADOR TRIPLE PLATO PP-01 | 1559 | respaldada | `workshop_tool` · familia `workshop_tool` | media-alta | Claude |
| Limpiador Cadena y Piñón Chepark | 1197 | pendiente | — | baja | Claude |

La tabla resume; el JSON lleva por registro la preimagen completa, la evidencia leída, la laguna y la acción concreta. `template_key`, `template_id` y `technical_family` van en campos separados en cada registro.

## Los que sí quedan resueltos

**Rotor Freno Trasero BMX PadroBikes** → `bmx_cable_detangler` · familia `bmx_cable_detangler` (`9e85c3f5-d7fb-5fa7-b93b-dee112f414ab`). Codex propuso «brake_detangler», que no es una clave de plantilla. La clave que existe es bmx_cable_detangler. Sheldon define el rotor de BMX como el mecanismo que enruta el cable del freno trasero alrededor de la potencia, y el nombre dice rotor, freno trasero y BMX.

*Laguna:* No hay imagen ni documento de este sku. La lectura descansa en que las tres palabras del nombre coinciden con la definición documentada, no en el nombre comercial por sí solo.

*Siguiente, Claude:* Buscar una foto o el documento de compra de PadroBikes que muestre si el objeto rodea la potencia; si aparece un disco, la familia cambia a rotor.

**Set Cubre Manubrio 125mm/220mm Black** → `handlebar_covering` · familia `handlebar_covering` (`30a5664f-8dbb-5a1c-9fdd-61b59c33eca2`). Codex propuso «handlebar_cover», que no es una clave; la que existe es handlebar_covering, y su campo kit_members es justamente el que permite no reducir el set a un par de puños.

*Laguna:* La imagen muestra cuatro piezas y el registro no declara la composición del set.

*Siguiente, Claude:* Abrir la imagen del ERP y describir las cuatro piezas para llenar kit_members; sin eso la ficha existiría vacía en lo que la distingue de un par de puños.

**FUNDA PROTECTORA BEST COLOR GRIS** → `bike_protection` · familia `bike_protection` (`479bdd38-e5e2-5123-9268-4bb60ef24467`). Codex propuso «protective_cover», que no es una clave; la que existe es bike_protection, con bike_protection_kind y fits_bike_size.

*Laguna:* La marca de la imagen es VISION y el nombre dice BEST: mientras eso no se resuelva, la identidad comercial del registro está en duda aunque el tipo de objeto no lo esté.

*Siguiente, Codex:* Confirmar en el documento de compra qué marca se compró; si el envase fotografiado no corresponde a este sku, la imagen deja de ser evidencia de este registro.

**GOMITA PARA FRENO V-BRAKE COMPATIBLE / GENERICO** → `control_small_part` · familia `control_small_part` (`37a61da4-67f9-5ab8-9a10-7868b3035f3c`). Codex propuso «brake_cable_boot», que no es una clave. Entre las dos que existen elijo control_small_part y no brake_small_part porque es la que modela el recorrido del cable de un V-Brake: lleva fits_cable_diameter_mm, fits_housing_diameter_mm y noodle_angle_deg. La imagen dice fuelle de cable, no zapata.

*Laguna:* La imagen fija el objeto pero no sus diámetros de cable y funda, que es lo que la plantilla pide.

*Siguiente, Claude:* Medir o leer del envase el diámetro de cable y de funda; sin eso la ficha queda con sus campos distintivos vacíos.

**EJE BLOQUEO SOLO DELANTERO (min.10pcs) ALTERNATIVO 2022 ECONOM.** → `hub_axle` · familia `hub_axle` (`7883bd2d-8ff0-583c-a4f2-606e23a6ce21`). La imagen dice eje de maza con conos y contratuercas, no aguja de cierre rápido, y la plantilla hub_axle lleva justamente cones_and_locknuts_included. Por eso descarto wheel_retention, que es la familia del cierre.

*Laguna:* Falta el diámetro y paso de rosca y el largo del eje, que son los campos que identifican la variante. «min.10pcs» es una condición de compra mínima, no contenido del producto.

*Siguiente, Codex:* Leer del documento de compra o del envase el diámetro, paso y largo; recién con eso la ficha distingue una variante de otra.

**EJE BLOQUEO TRASERO 7/8 9V. COMPATIBLE / GENERICO** → `hub_axle` · familia `hub_axle` (`7883bd2d-8ff0-583c-a4f2-606e23a6ce21`). La imagen dice eje de maza con conos y contratuercas, no aguja de cierre rápido, y la plantilla hub_axle lleva justamente cones_and_locknuts_included. Por eso descarto wheel_retention, que es la familia del cierre.

*Laguna:* Falta el diámetro y paso de rosca y el largo del eje, que son los campos que identifican la variante. «7/8 9V.» no identifica por sí solo la maza objetivo.

*Siguiente, Codex:* Leer del documento de compra o del envase el diámetro, paso y largo; recién con eso la ficha distingue una variante de otra.

**ACEITE NACIONAL** → `workshop_chemical` · familia `workshop_chemical` (`61bc1c93-8b73-55d0-9584-6087a8190dfe`). La imagen dice lubricante multipropósito. No se certifica uso en frenos y no se deduce composición. workshop_chemical tiene el campo not_for, que es donde eso se dice sin afirmar nada de más.

*Laguna:* Falta el volumen y el envase; la etiqueta de la imagen no da la composición.

*Siguiente, Claude:* Leer el volumen y el envase del documento de compra, y dejar escrito en not_for que no está declarado como líquido de frenos.

**LIMPIADOR TRIPLE PLATO PP-01** → `workshop_tool` · familia `workshop_tool` (`9fa846f3-8544-5fdf-9220-9f86e196ddb0`). Objeto sólido articulado, no botella: eso descarta el químico aunque el nombre diga limpiador.

*Laguna:* La foto es pequeña y no se lee el uso exacto; la búsqueda pública del código PP-01 no devolvió ninguna fuente.

*Siguiente, Claude:* Abrir la imagen del ERP a tamaño completo y describir el mecanismo; si es un limpiador de cadena, tool_kind y tool_capabilities ya lo representan.

## Los que no resuelvo, y por qué

**Andes.** No hay corroboración: a diferencia de Bettabikes y ALIEXPRESS, este nombre no aparece como sufijo en ningún otro producto del registro, así que no puedo demostrar que sea proveedor y tampoco que sea una pieza.

*Candidatas consideradas:* —. *Siguiente, Codex:* Buscar el registro en documentos de compra o venta: si aparece como contraparte es un rótulo; si aparece como línea con cantidad y precio unitario, hay que identificarlo.

**Cubetas Motor Americano BMX Bettabikes.** El nombre no dice si la caja trae eje. El registro además está inactivo, así que la urgencia es baja y no conviene decidirlo por analogía.

*Candidatas consideradas:* `bottom_bracket` · familia `bottom_bracket`, `bottom_bracket_cup` · familia `bottom_bracket_cup`. *Siguiente, Codex:* Revisar el documento de compra: si aparece eje, es bottom_bracket; si sólo copas y rodamientos, es bottom_bracket_cup con bottom_bracket_bearing aparte.

**Dr. Bike.** No hay corroboración: a diferencia de Bettabikes y ALIEXPRESS, este nombre no aparece como sufijo en ningún otro producto del registro, así que no puedo demostrar que sea proveedor y tampoco que sea una pieza.

*Candidatas consideradas:* —. *Siguiente, Codex:* Buscar el registro en documentos de compra o venta: si aparece como contraparte es un rótulo; si aparece como línea con cantidad y precio unitario, hay que identificarlo.

**Eje de Motor Set Up Bikes.** El nombre no distingue el eje suelto del conjunto completo.

*Candidatas consideradas:* `bottom_bracket_axle` · familia `bottom_bracket_axle`, `bottom_bracket` · familia `bottom_bracket`. *Siguiente, Codex:* Revisar el documento de compra de Set Up Bikes: si la línea trae copas, es un pedalier completo; si es sólo el eje, es bottom_bracket_axle.

**Juego de Tuercas Laterales Motor + Rodamientos.** Un kit de tuercas más rodamientos no tiene una plantilla que represente las dos cosas a la vez, y partirlo en dos fichas cambia lo que se vende.

*Candidatas consideradas:* `bottom_bracket_cup` · familia `bottom_bracket_cup`, `bottom_bracket_bearing` · familia `bottom_bracket_bearing`. *Siguiente, Codex:* Revisar el documento de compra para saber cuántas piezas trae y de qué tipo; recién ahí se decide si es un kit de copas o de rodamientos.

**MKR.** No hay corroboración: a diferencia de Bettabikes y ALIEXPRESS, este nombre no aparece como sufijo en ningún otro producto del registro, así que no puedo demostrar que sea proveedor y tampoco que sea una pieza.

*Candidatas consideradas:* —. *Siguiente, Codex:* Buscar el registro en documentos de compra o venta: si aparece como contraparte es un rótulo; si aparece como línea con cantidad y precio unitario, hay que identificarlo.

**Pack.** «Pack» es un sustantivo de presentación, no una pieza. Aparece como palabra dentro de 10 nombres de producto, pero eso no dice qué es este registro suelto.

*Candidatas consideradas:* —. *Siguiente, Codex:* Revisar los documentos donde se usó: un pack sin contenido declarado no puede recibir ficha, y si tiene contenido hay que registrarlo como el producto que realmente entrega.

**Piñon 1v Bettabikes.** Un piñón de una velocidad puede ser rueda libre o piñón fijo, y el nombre no lo dice. Los dos registros están inactivos.

*Candidatas consideradas:* `freewheel` · familia `freewheel`, `fixed_cog` · familia `fixed_cog`. *Siguiente, Codex:* Revisar el documento de compra o una foto del roscado: la rueda libre tiene mecanismo de trinquete y el piñón fijo no.

**Piñon 1v Monsoon Bettabikes.** Un piñón de una velocidad puede ser rueda libre o piñón fijo, y el nombre no lo dice. Los dos registros están inactivos.

*Candidatas consideradas:* `freewheel` · familia `freewheel`, `fixed_cog` · familia `fixed_cog`. *Siguiente, Codex:* Revisar el documento de compra o una foto del roscado: la rueda libre tiene mecanismo de trinquete y el piñón fijo no.

**Test.** El nombre dice Test pero el sku ACC-TES-59147 sigue el patrón de la categoría Accesorios, así que no se puede afirmar que sea un registro de prueba desechable.

*Candidatas consideradas:* —. *Siguiente, Codex:* Revisar si el registro tiene movimiento de stock o ventas; sólo entonces decidir si se retira o se identifica.

**Freno Hidráulico Delantero Tanke 4 Pistones Morado Metálico.** El registro no lista componentes. La convención de la marca inclina a conjunto, pero la misma marca vende cálipers sueltos, y la ruta de categoría «Frenos Hidráulicos» también contiene cálipers, así que la categoría no decide.

*Candidatas consideradas:* `brake_caliper` · familia `brake_caliper`. *Siguiente, Codex:* Leer el documento de compra o la foto del envase para ver si incluye manilla y manguera; eso decide entre las dos familias.

**Aceite Mineral Chepark.** El registro no tiene imagen ni modelo ni volumen. Que Chepark venda un aceite mineral de freno no demuestra que este sku sea ése: la marca también vende otros lubricantes y limpiadores, y en este mismo catálogo hay cinco registros Chepark distintos.

*Candidatas consideradas:* `workshop_chemical` · familia `workshop_chemical`. *Siguiente, Claude:* Leer el documento de compra para capturar el código y el volumen; si aparece BIC-860 o equivalente, la familia queda respaldada y si no, se queda en workshop_chemical.

**Limpiador Cadena y Piñón Chepark.** Sin imagen y sin código. «Limpiador de cadena y piñón» nombra igual a una máquina de limpieza que a un líquido, y Chepark fabrica de los dos.

*Candidatas consideradas:* `workshop_tool` · familia `workshop_tool`, `workshop_chemical` · familia `workshop_chemical`. *Siguiente, Claude:* Buscar imagen o documento de compra de este sku; el discriminante es si el envase es botella con volumen o un objeto con mecanismo.

## Lo que deliberadamente no hice

- No convertí ningún rótulo de proveedor en producto, ni siquiera donde el patrón era claro: donde no pude demostrarlo lo dejé pendiente.
- No le di la plantilla `tube` a la nota de crédito, aunque el nombre trae medida y válvula.
- No le di `spoke` a la instalación de rayo: el rayo es material de la intervención.
- No deduje uso en frenos de la palabra «mineral», ni composición de la palabra «nacional».
- No decidí ninguna de las cuatro cajas de pedalier por analogía entre ellas.
- No usé el prefijo NNV como criterio, porque 17 registros NNV sí tienen plantilla.

## Compuertas

Asignación, llenado, publicación y aprobación mecánica siguen en `false`. Este documento no aplica nada.
