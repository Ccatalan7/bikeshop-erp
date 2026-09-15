# Corrección de ruta de fuentes

Claude, revisor independiente · 2026-09-07

Tenías razón: el cero era mío, no de los productos. Corrijo aquí `unmapped-33-evidence-followup-2026-09-07.json` (SHA `68b2446fca850183d792411a312ef9fdd24a156920b4f944209f7033d65618b1`) y una etiqueta de `unmapped-ambiguous-and-business-review-2026-09-07.json` (SHA `d966352e06415821860eafc0138e9fc7a9797ab4e9b43d6622989277c5f1ae2c`). Los dos quedan congelados; corrijo por id. Lectura sólo lectura, sin escrituras ni mensajes externos.

## Qué medí

No vuelvo a afirmar una ausencia sin decir de qué ruta hablo y cuánto cubre.

| Ruta | Líneas | Productos distintos | Límite |
|---|---|---|---|
| sales_invoices.items (jsonb) | 1741 | 415 | Líneas de venta vigentes. Es la ruta real y la que yo no consulté. |
| sales_order_items (normalizada) | 0 | 0 | Vacía en todo el tenant. Yo concluí «cero ventas» consultando una tabla sin ninguna fila. |
| purchase_invoices.items (jsonb) | 363 | 278 | Líneas de compra vigentes. Tampoco la consulté. |
| purchase_receipt_lines (normalizada) | 28 | 24 | Sólo recepciones registradas: 24 productos frente a 278 con línea de compra, es decir menos del 9%. Yo la usé como si fuera el universo de compras. |
| stock_movements | 2685 | 892 | La señal más amplia del tenant y la que más me faltó: tiene product_id propio y nunca la consulté. |
| product_images | 0 | 0 | Vacía. Las 1 373 imágenes viven en products.image_url. |
| products.image_url | 1373 | 1373 | Una imagen por producto; no hay galería. |

**`sales_order_items` está vacía en todo el tenant.** Concluí «cero ventas» consultando una tabla sin una sola fila. Y `purchase_receipt_lines` cubre 24 productos de los 278 que tienen línea de compra vigente: menos del 9%. La señal más amplia, `stock_movements` con 892 productos, no la consulté nunca aunque tiene `product_id` propio.

## Las seis correcciones

### R1 — finding G1 de unmapped-33-evidence-followup-2026-09-07.json

*Lo que afirmé:* «Cero líneas en purchase_receipt_lines, cero en sales_order_items […] para los 33. El uso real no resuelve ninguno.»

*Por qué está mal:* Derivé una ausencia general de dos tablas parciales. Medido: sales_order_items está vacía en todo el tenant, y purchase_receipt_lines cubre 24 productos frente a 278 con línea de compra vigente. Las líneas actuales viven en sales_invoices.items y purchase_invoices.items, y además existe stock_movements con product_id propio, que nunca consulté.

*Evidencia:* Tu lectura encontró M010 en FV-00714 y FV-00986, NNV43 en cinco ventas pagadas, NNV155 en FV-00457 y Test en FV-00446. La mía, por las rutas reales, encuentra uso en cinco de mis siete.

*Corrección:* G1 queda anulado. La formulación correcta es «cero coincidencias en las rutas consultadas», nombrando cada ruta y su cobertura, y nunca «sin uso».

### R2 — C1, C2 y C3 de unmapped-33-evidence-followup-2026-09-07.json

*Lo que afirmé:* En C1 dije que los seis rótulos «tienen cero líneas de compra y cero de venta»; en C2, «cero movimiento en todos»; en C3, que para M010 «el uso no decide».

*Por qué está mal:* Las tres frases descansaban en el mismo cero falso.

*Evidencia:* M010 aparece en dos facturas de venta según tu lectura. Los seis rótulos y los cinco inactivos son de tus 26 y tu evidencia manda sobre ellos.

*Corrección:* Se anula la parte probatoria de las tres. Lo que sobrevive de C1 es la distinción entre coincidencia con un proveedor registrado e identidad del registro, que no dependía del cero. Lo que sobrevive de C2 es que inactivo no es fuera de alcance. C3 se mantiene en su conclusión —no descartar el material físico de M010— y ahora con evidencia a favor en vez de un cero.

### R3 — C6 de unmapped-33-evidence-followup-2026-09-07.json

*Lo que afirmé:* «El objeto queda resuelto; la plantilla dueña no», tras retirar mi argumento del noodle_angle_deg.

*Por qué está mal:* Retirar una razón inválida no vuelve irresoluble una decisión que el discriminante correcto sí respalda. Me quedé a medio camino y te devolví una pregunta que el catálogo ya contestaba.

*Evidencia:* Verificado en el catálogo 934: control_part_kind admite literalmente «Fuelle / goma protectora», y noodle_angle_deg tiene allowed_when igual a control_part_kind = «Noodle V-brake», así que con el fuelle el ángulo ni se pide ni se puede llenar. brake_part_kind, en cambio, sólo ofrece pasador, resorte, perno y «Otro»: el fuelle sólo cabría como «Otro».

*Corrección:* control_small_part es la dueña, respaldada. La razón que yo había dado era inválida; la correcta es que la plantilla tiene un token literal para este objeto y que el campo que me preocupaba está cerrado por condición.

### R4 — finding G3 de unmapped-33-evidence-followup-2026-09-07.json

*Lo que afirmé:* Presenté is_service = false en los 33 como el dato del ERP que contradice mi lectura de «servicio».

*Por qué está mal:* Estamos auditando errores de clasificación. Un campo mal puesto no es prueba mecánica de lo que el producto es; usarlo así convierte el error auditado en evidencia.

*Evidencia:* Las líneas de venta llevan su propio is_service, distinto del campo del producto, y los movimientos de 1541 y 2854 registran conversiones de inventario a consumible de taller: la clasificación de estos registros cambia con el tiempo y por decisión.

*Corrección:* is_service pasa a ser un dato observado más, no un veredicto. Ni el nombre ni el campo deciden solos.

### R5 — campo source_preimage de unmapped-ambiguous-and-business-review-2026-09-07.json

*Lo que afirmé:* Lo llamé preimagen y dije «preimagen literal».

*Por qué está mal:* Es una proyección de campos elegidos por mí, no una copia completa del registro original. Llamarla preimagen literal promete más de lo que entrega.

*Evidencia:* Tú conservaste los originales completos en unmapped-26-root-evidence-2026-09-07.json y verificaste que mis valores retenidos y los 33 tríos de plantilla coinciden.

*Corrección:* El campo se lee como «projection_of_source_record». La copia completa de los 26 está en tu artefacto; para mis siete, la copia viva queda en este archivo.

### R6 — redacción general sobre evidencia faltante

*Lo que afirmé:* En varios lugares escribí que algo «no está declarado» junto a la familia propuesta, de forma que se lee como una limitación del producto.

*Por qué está mal:* La falta de aprobación o de declaración no es incompatibilidad. Ya lo habías corregido para not_for y la regla es general.

*Evidencia:* Ninguna: es una regla de redacción.

*Corrección:* Lo no declarado se escribe como hueco de evidencia y nunca junto a un veredicto de aptitud. Aplica a los siete registros de este archivo.

## Mis siete, reconsultados por las rutas reales

| sku | Registro | Ventas | Compras | Movimientos | Qué cambia |
|---|---|---|---|---|---|
| 2854 | Aceite Mineral Chepark | 1 | 0 | 3 | uso encontrado |
| 67 | ACEITE NACIONAL | 1 | 0 | 0 | uso encontrado |
| 1541 | GOMITA PARA FRENO V-BRAKE COMPATIB | 0 | 0 | 2 | uso encontrado |
| 1197 | Limpiador Cadena y Piñón Chepark | 0 | 0 | 2 | uso encontrado |
| 1559 | LIMPIADOR TRIPLE PLATO PP-01 | 0 | 0 | 1 | uso encontrado |
| 24131 | Set Cubre Manubrio 125mm/220mm Bla | 0 | 0 | 0 | cero en las rutas consultadas |
| NNV162 | Rotor Freno Trasero BMX PadroBikes | 0 | 0 | 0 | cero en las rutas consultadas |

Cinco de siete tenían uso que yo había declarado inexistente.

### Aceite Mineral Chepark (2854)

**Documentos.**
- FV-00016 (draft, 2025-11-15), cantidad 1, is_catalog_product true

**Movimientos de stock.**
- 2025-11-13 initial IN 1000
- 2026-01-09 manual IN 1
- 2026-06-19 correction OUT 1000, «Conversión interna de inventario a consumible de taller»

**Qué cambia.** Deja de ser «sin uso». Tiene una venta en borrador y tres movimientos, e incorpora un discriminante nuevo: la existencia inicial es 1000, que coincide con la presentación de 1000 ml del BIC-860 que encontré en la búsqueda pública. Sube la plausibilidad de brake_fluid sin confirmarla: el campo unit del producto dice «unit», así que 1000 podría ser mililitros anotados como unidades o mil unidades, y sólo el documento o el envase lo resuelve.

*Siguiente:* Leer la línea de la factura de compra si aparece en otra ruta, o el envase, para fijar código y volumen. El discriminante es si 1000 es mililitros.

### ACEITE NACIONAL (67)

**Documentos.**
- FV-00016 (draft, 2025-11-15), cantidad 1, is_catalog_product true

**Qué cambia.** Deja de ser «sin uso»: se vende como producto de catálogo, en la misma factura en borrador que el aceite Chepark. Eso refuerza que es una mercadería y no una intervención, sin tocar la lectura de la etiqueta.

*Siguiente:* Seguir FV-00016 completa: qué más lleva esa factura dice para qué se usaron los dos aceites juntos.

### GOMITA PARA FRENO V-BRAKE COMPATIBLE / GENERICO (1541)

**Movimientos de stock.**
- 2025-11-13 initial IN 38
- 2026-07-07 correction OUT 38, «Conversión interna de inventario a consumible de taller»

**Qué cambia.** Deja de ser «sin uso». Y los movimientos explican de dónde viene el purchase_treatment = workshop_consumable que yo había leído como un dato dado: es el resultado de una conversión registrada el 2026-07-07, es decir un evento de reclasificación, justo el tipo de cosa que esta auditoría busca.

*Siguiente:* Ninguno para la familia: la decisión queda cerrada por C6-bis. Queda medir el diámetro interior para llenar la ficha.

### Limpiador Cadena y Piñón Chepark (1197)

**Movimientos de stock.**
- 2025-11-13 initial IN 425
- 2025-12-17 manual OUT 425

**Qué cambia.** Deja de ser «sin uso» y aparece el mismo discriminante de cantidad: 425 es una existencia difícil de sostener para una máquina de limpieza y fácil para un volumen. Inclina hacia químico sobre herramienta, sin cerrarlo, porque el campo unit dice «unit».

*Siguiente:* Confrontar 425 con el envase o el documento de Vittal: si es mililitros, la familia es workshop_chemical.

### LIMPIADOR TRIPLE PLATO PP-01 (1559)

**Movimientos de stock.**
- 2025-11-13 initial IN 1

**Qué cambia.** Deja de ser «sin uso». La existencia inicial de 1 unidad es coherente con la herramienta que vi en la imagen y contrasta con los 425 y los 1000 de los dos limpiadores líquidos. Refuerza workshop_tool sin depender del nombre.

*Siguiente:* Sin cambio: falta la resolución de imagen o el catálogo Rito para el tipo exacto.

### Set Cubre Manubrio 125mm/220mm Black (24131)

**Qué cambia.** Sigue en cero, pero ahora es «cero en las cinco rutas consultadas» y no «sin uso». La lectura de la imagen no dependía de esto.

*Siguiente:* Buscar el artículo en rutas archivadas o no normalizadas antes de afirmar cualquier ausencia.

### Rotor Freno Trasero BMX PadroBikes (NNV162)

**Qué cambia.** Igual: cero en las cinco rutas consultadas, no ausencia. Es el único de mis siete sin imagen y sin ningún rastro, así que sigue apoyado sólo en el vocabulario.

*Siguiente:* Igual que el anterior, más el documento de Padro Bikes.

## Un discriminante nuevo que salió de la ruta correcta

Los movimientos iniciales separan los tres limpiadores mejor que sus nombres: 1 unidad para la herramienta PP-01, 38 para la gomita, 425 para el limpiador de cadena y 1000 para el aceite Chepark. Un 1000 encaja con la presentación de 1000 ml que devolvió la búsqueda pública y un 425 encaja con un volumen, no con una máquina. Es una señal, no una prueba: el campo unit de los cuatro dice «unit».

## La regla que rompí

La regla que rompí, escrita para no repetirla: una ausencia general no se deriva de una tabla parcial. Antes de afirmar «no hay», hay que medir la cobertura de la ruta y nombrarla en la afirmación. Dos de las tablas que usé tenían cero filas en todo el tenant, y yo leí ese cero como un hecho del producto.

## Compuertas

Asignación, llenado, publicación y aprobación mecánica siguen en `false`.
