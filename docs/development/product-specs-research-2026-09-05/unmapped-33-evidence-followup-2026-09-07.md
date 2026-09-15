# Seguimiento de evidencia de los 33

Claude, revisor independiente · 2026-09-07

Addendum a `unmapped-ambiguous-and-business-review-2026-09-07.json`, SHA `d966352e06415821860eafc0138e9fc7a9797ab4e9b43d6622989277c5f1ae2c`, que queda congelado. Aquí no lo reescribo: corrijo por id.

Leí producción en sólo lectura por `scripts/db/query.sh`, acotado a los 33 registros y a las contrapartes que nombran. Sin escrituras, sin sondas, sin mensajes externos y sin tocar productos ni archivos de root. No asigno ninguna plantilla. Los dos Garozzo y las propuestas de asignación son tuyos y no los toco.

## Las siete correcciones

Cinco son tuyas y dos las encontré al ejecutar la investigación.

### C1 — finding A4, cc9f7f88-0401-4eb2-bbd6-74b1b1b07336, 54aa6f11-e04d-446c-aa33-7e6580dbe7e1…

*Lo que yo afirmé:* «Bettabikes aparece como sufijo en 29 nombres y ALIEXPRESS en otro, así que los registros que llevan sólo ese nombre son rótulos» — y marqué esos dos como decisión respaldada.

*Por qué está mal:* La co-ocurrencia demuestra que la palabra se usa como sufijo de proveedor en otros productos. No demuestra nada sobre la identidad de este registro: que exista un proveedor con ese nombre no convierte a este renglón en su rótulo administrativo.

*Evidencia nueva:* La tabla suppliers registra AliExpress, Betta Bikes, Dr. Bike, MKR Imports, Andes Industrial y AndesLife. «Dr. Bike» coincide exacto y «MKR» es prefijo de «MKR Imports». Es una hipótesis de origen mucho mejor que la co-ocurrencia, y sigue sin ser identidad. «Andes» coincide con dos proveedores distintos y «Pack» con ninguno. Los seis tienen cero líneas de compra y cero de venta, así que el discriminante que yo mismo propuse no devuelve nada.

*Corrección:* Los seis pasan a pendiente. Ninguno queda como demostrado. La coincidencia con un proveedor registrado se anota como hipótesis de origen, separada de la identidad.

### C2 — finding A8

*Lo que yo afirmé:* «No cambia el análisis, pero sí la prioridad: ninguno de ellos bloquea el avance de fichas.»

*Por qué está mal:* Inactivo no es fuera de alcance. Los cinco siguen dentro del alcance del dueño y no tienen exención de saneamiento ni de llenado; que no bloqueen hoy no es una propiedad del registro sino de mi orden de trabajo.

*Evidencia nueva:* Producción confirma is_active = false en los cinco y, además, cero movimiento en todos: ni compras ni ventas. La inactividad no viene acompañada de ninguna marca que los excluya.

*Corrección:* Se retira la frase de prioridad. Los cinco quedan dentro del alcance, con su estado de actividad como dato y no como exención.

### C3 — f8089a2e-da2a-430c-8949-137fdd1930a7

*Lo que yo afirmé:* Decisión respaldada, no es producto técnico: «una ficha de cámara plana describiría sólo una parte del paquete».

*Por qué está mal:* Descarté el material físico sin mirar el uso real. Podría ser un servicio con material o un paquete compuesto, y en los dos casos hay una cámara de por medio.

*Evidencia nueva:* Producción declara purchase_treatment = workshop_consumable e is_service = false para M010. El tratamiento declarado apunta a material consumido en taller, no a un servicio puro. Y el uso no decide: cero líneas de compra, cero de venta y ningún perfil de servicio asociado.

*Corrección:* Pasa a pendiente. No se descarta la ficha ni el material físico. El siguiente discriminante es si el paquete se vende como una unidad con cámara incluida o como mano de obra que consume una cámara del inventario.

### C4 — ccdb85f9-8456-4da3-930a-e3d359ca6f47

*Lo que yo afirmé:* «dejar escrito en not_for que no está declarado como líquido de frenos».

*Por qué está mal:* not_for es para prohibiciones declaradas por el fabricante. La falta de evidencia no es incompatibilidad, y escribirla ahí la convertiría en una prohibición OEM que nadie declaró.

*Evidencia nueva:* Abrí la imagen: la etiqueta dice LUBETRAC y, debajo, «LUBRICANTE MULTI PROPÓSITO». Eso es un uso declarado y va en declared_applications. Sobre frenos la etiqueta no dice nada: ni lo permite ni lo prohíbe.

*Corrección:* El uso en frenos se registra como no declarado, fuera de not_for. La instrucción anterior queda anulada.

### C5 — 02472142-39a6-4037-9d87-d044786eea7e, 47cbf024-c586-4170-af0e-c0fea99e3146, e174953e-ff08-48b9-ad39-3737a3ab5518

*Lo que yo afirmé:* «si aparece eje, es bottom_bracket; si sólo copas y rodamientos, es bottom_bracket_cup con bottom_bracket_bearing aparte».

*Por qué está mal:* La presencia o ausencia del eje no define el objeto: hay sistemas donde el eje pertenece a las bielas y el pedalier son sólo copas y rodamientos, y aun así se vende y se instala como un pedalier. Y la segunda mitad era peor: proponía partir en dos fichas un kit que se vende como una unidad.

*Evidencia nueva:* Producción no aporta contenido: los tres tienen is_set = false, sin parent_set_id, sin descripción, sin marca y sin ningún documento asociado.

*Corrección:* El discriminante pasa a ser qué vende el proveedor como una unidad y qué interfaz presentan las copas, no si hay eje en la caja. Un kit vendido como unidad no se parte para que calce con una plantilla.

### C6 — finding A6, 49b90689-b504-4216-81e3-b311e29bfb90

*Lo que yo afirmé:* Elegí control_small_part porque lleva noodle_angle_deg, «que es el recorrido del cable de un V-Brake».

*Por qué está mal:* Al abrir la imagen se ve que el objeto es el fuelle, no el codo. El noodle_angle_deg describe el codo metálico y quedaría vacío para esta pieza, así que el campo que usé como argumento no aplica.

*Evidencia nueva:* La imagen abierta: manguito de goma corrugado, con collar ancho en un extremo y un extremo ranurado en el otro.

*Corrección:* El objeto queda resuelto; la plantilla dueña no. Entre control_small_part y brake_small_part hace falta la intención del dueño de esas dos plantillas, y lo registro como discriminante abierto en vez de sostener mi razón anterior.

### C7 — finding A7, grupo de servicios

*Lo que yo afirmé:* Llamé «servicio de taller» a Diagnóstico, Retiro de Óxido, Descontaminación y las demás intervenciones.

*Por qué está mal:* Era una lectura del nombre presentada junto a datos de producción, lo que la hace parecer un dato del ERP. No lo es.

*Evidencia nueva:* Producción declara is_service = false en los 33, incluidos Diagnóstico y Retiro de Óxido. Lo que sí distingue a varios es purchase_treatment = workshop_consumable, presente en Aceite Mineral Chepark, M010, Descontaminación, Retiro de Óxido, el eje delantero y la gomita.

*Corrección:* La lectura del nombre se mantiene como hipótesis, y se separa del campo del ERP, que dice lo contrario. La contradicción entre el nombre y is_service queda anotada como pregunta abierta para el dueño de esos registros.

## Cambios de estado

| Registro | Antes | Ahora | Por |
|---|---|---|---|
| ALIEXPRESS | respaldada | pendiente | C1 |
| BETTABIKES | respaldada | pendiente | C1 |
| Cámara nueva + servicio de cambio | respaldada | pendiente | C3 |

## La investigación que me asigné, ejecutada

Abrí de verdad las cuatro imágenes que existían entre mis siete registros. Las descargué del almacenamiento del ERP y **el sha256 de cada archivo coincide con el que registró la revisión de imagen congelada**, así que la evidencia original quedó verificada y no sólo citada.

| Registro | Imagen abierta | sha256 coincide | Estado |
|---|---|---|---|
| Set Cubre Manubrio 125mm/220mm Black | 24131.jpg · 600x450 | sí | respaldada |
| GOMITA PARA FRENO V-BRAKE COMPATIBLE / | 1541.jpg · JPEG 7 227 bytes | sí | pendiente |
| LIMPIADOR TRIPLE PLATO PP-01 | 1559.jpg · JPEG 11 052 bytes | sí | respaldada |
| ACEITE NACIONAL | 67.png · 175x216 | sí | respaldada |
| Aceite Mineral Chepark | no hay imagen | — | pendiente |
| Limpiador Cadena y Piñón Chepark | no hay imagen | — | pendiente |
| Rotor Freno Trasero BMX PadroBikes | no hay imagen | — | pendiente |

### Set Cubre Manubrio 125mm/220mm Black

**Fuente observada.**
- Imagen abierta por Claude, 600x450: cuatro piezas tubulares de espuma negra. Dos largas, lisas y abiertas en los dos extremos. Dos más cortas con un extremo cerrado y un anillo de terminación visible.
- El sha256 del archivo que descargué coincide con el que registró la revisión de imagen congelada, así que es la misma evidencia.
- Producción: proveedor Comercial Ciclo, is_set = false, sin descripción, sin marca.

**Hipótesis.**
- Las dos largas serían los manguitos de 220 mm y las dos cortas los puños de 125 mm, que son las dos medidas del nombre. Es una lectura de la foto y de la longitud, no una declaración del fabricante.

**No declarado.**
- Material, diámetro interior y composición del set. El ERP no marca el registro como set y no trae descripción.

*Siguiente discriminante, Claude:* Medir el diámetro interior de las cuatro piezas, o pedir a Comercial Ciclo la ficha del artículo 24131; con eso se llena kit_members y las medidas.

### GOMITA PARA FRENO V-BRAKE COMPATIBLE / GENERICO

**Fuente observada.**
- Imagen abierta por Claude: manguito de goma negro corrugado, en acordeón, con un collar más ancho en un extremo y un extremo ranurado en el otro. No es zapata ni pastilla.
- sha256 coincide con el de la revisión congelada.
- Producción: marca Andes Industrial, purchase_treatment workshop_consumable.

**Hipótesis.**
- Fuelle protector del tramo de cable expuesto de un V-Brake.

**No declarado.**
- Diámetro interior, y si el fabricante lo declara para cable o para el puente de unión. Ninguna medida aparece en el ERP.

*Siguiente discriminante, Codex:* Definir con el dueño de las plantillas si un fuelle pertenece a control_small_part o a brake_small_part, y medir el diámetro interior. Ver corrección C6.

### LIMPIADOR TRIPLE PLATO PP-01

**Fuente observada.**
- Imagen abierta por Claude, 11 052 bytes: herramienta metálica sólida, anodizada celeste, dos placas unidas por un perno pivote, una con canto ganchudo y dentado. Lleva la marca «Rito CYCLE PARTS» grabada. No es envase ni botella.
- sha256 coincide con el de la revisión congelada.
- Producción: marca Rito, proveedor RBX, inventory_qty 1. Es el único de los 33 con existencia.

**Hipótesis.**
- Rascador para limpiar entre dientes de platos o piñones. La forma del canto lo sugiere; la resolución no permite ver el mecanismo.

**No declarado.**
- El tipo exacto de herramienta y para qué diente está dimensionada.

**Búsqueda ejecutada.**
- Búsqueda pública «Rito Cycle Parts PP-01»: la marca Rito Cycle Parts existe y se comercializa en marketplaces latinoamericanos, pero ninguna fuente identifica el modelo PP-01. Búsqueda ejecutada y sin resultado, que no es lo mismo que producto inexistente.

*Siguiente discriminante, Claude:* Pedir a RBX la ficha del artículo 1559 o una foto de mayor resolución; el discriminante es si el canto dentado entra entre platos o entre piñones.

### ACEITE NACIONAL

**Fuente observada.**
- Imagen abierta por Claude, 175x216: botella blanca de apriete con tapa cónica roja de goteo. La etiqueta dice «LUBETRAC» y, debajo, «LUBRICANTE MULTI PROPÓSITO». Se lee «CONT. APROX.» pero la cifra del volumen no es legible con seguridad a esa resolución.
- sha256 coincide con el de la revisión congelada.
- Producción: proveedor Trip, y el campo description contiene el valor basura «test 2».

**Hipótesis.**
- Lubricante multipropósito de taller. El nombre del registro dice «ACEITE NACIONAL» y la etiqueta dice LUBETRAC: el nombre del ERP no es el del envase.

**No declarado.**
- El uso en frenos no está declarado ni prohibido en la etiqueta: queda como no declarado y no se escribe en not_for. Tampoco están declarados la composición ni el volumen exacto.

*Siguiente discriminante, Claude:* Leer el volumen del envase físico o de una foto de mayor resolución, y decidir qué hacer con la discrepancia entre el nombre del registro y la marca de la etiqueta.

### Aceite Mineral Chepark

**Fuente observada.**
- Producción: no tiene imagen. image_url nulo y cero filas en product_images. Proveedor Vittal, purchase_treatment workshop_consumable. Cero compras y cero ventas.

**Hipótesis.**
- Podría ser el aceite mineral de freno de la marca, pero eso viene del catálogo de Chepark y no de este registro.

**No declarado.**
- Código, volumen y sistema al que va destinado. Nada de eso está en el ERP.

**Búsqueda ejecutada.**
- Búsqueda pública anterior: Chepark comercializa BIC-860, aceite mineral para freno hidráulico. No identifica a este sku.

*Siguiente discriminante, Claude:* Pedir a Vittal el documento del artículo 2854 o una foto de la botella; el discriminante es el código impreso y si la etiqueta nombra un sistema de frenos.

### Limpiador Cadena y Piñón Chepark

**Fuente observada.**
- Producción: no tiene imagen, proveedor Vittal, cero compras y cero ventas.

**Hipótesis.**
- El nombre nombra igual a una máquina de limpieza de cadena que a un líquido.

**No declarado.**
- Todo lo que distingue una cosa de la otra: envase y volumen frente a mecanismo.

*Siguiente discriminante, Claude:* Pedir a Vittal el documento del artículo 1197 junto con el 2854, que es el mismo proveedor; el discriminante es envase con volumen frente a objeto con mecanismo.

### Rotor Freno Trasero BMX PadroBikes

**Fuente observada.**
- Producción: no tiene imagen, cero compras y cero ventas. El proveedor registrado es Padro Bikes, que es la palabra que aparece al final del nombre.

**Hipótesis.**
- Sigue siendo el desacoplador de cables de BMX, por la definición documentada de «rotor» en una bicicleta de estilo libre y porque el nombre dice rotor, freno trasero y BMX.

**No declarado.**
- Nada en la evidencia propia de este registro muestra el objeto. La lectura descansa en el vocabulario, no en una foto ni en un documento.

*Siguiente discriminante, Codex:* Pedir a Padro Bikes el documento o una foto del artículo; si aparece un disco, la familia cambia a rotor.

## Lo que encontré al leer producción

### G1 · Ninguno de los 33 tiene uso documentado

Cero líneas en purchase_receipt_lines, cero en sales_order_items, cero perfiles en service_product_profile_mappings y cero filas en product_images para los 33. El «uso real» no resuelve ninguno, y el discriminante que yo había propuesto para los rótulos —buscarlos como contraparte o como línea— no devuelve nada. Todo lo que queda por resolver depende de imágenes, del documento del proveedor o del fabricante.

### G2 · Las imágenes no viven donde las buscaba

product_images está vacía para los 33; las fotos están en products.image_url. Ocho de los 33 la tienen. Abrí las cuatro que me correspondían y las cuatro coinciden en sha256 con las que registró la revisión de imagen congelada, así que la evidencia original quedó verificada, no sólo citada.

### G3 · is_service dice lo contrario que el nombre

Los 33 tienen is_service = false, incluidos Diagnóstico y Retiro de Óxido. Lo que sí separa a varios es purchase_treatment = workshop_consumable. Mi lectura de «servicio» venía del nombre y la presenté junto a datos del ERP; queda como hipótesis y la contradicción con el campo queda anotada.

### G4 · Dos registros nombran algo distinto de lo que muestra su envase

«ACEITE NACIONAL» tiene una etiqueta LUBETRAC, y «FUNDA PROTECTORA BEST» tenía un envase VISION según la revisión congelada. Son dos casos del mismo patrón: el nombre del ERP no es el del producto fotografiado. Ninguno se resuelve renombrando por la foto.

### G5 · Un campo de datos con valor de prueba

La descripción de ACEITE NACIONAL contiene «test 2». No cambia la familia candidata, pero es un valor basura en un campo que una ficha podría llegar a leer.

## Lo que sigo sin poder afirmar

- Que ALIEXPRESS, BETTABIKES, Andes, Dr. Bike, MKR o Pack sean rótulos administrativos. Coinciden con proveedores registrados, y eso es origen probable, no identidad.
- Qué contiene cualquiera de las tres cajas de pedalier: producción no aporta contenido y el eje no es el discriminante.
- Si M010 es servicio con material o paquete compuesto. El tratamiento declarado dice que hay material; ningún documento dice cómo se vende.
- El tipo exacto de la herramienta Rito PP-01: la marca existe, el modelo no aparece en ninguna fuente y la foto no tiene resolución para el mecanismo.

## Compuertas

Asignación, llenado, publicación y aprobación mecánica siguen en `false`. Este addendum no aplica nada.
