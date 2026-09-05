# Revisión de Claude: Compras del día y revisión OCR (2026-09-05)

Revisión independiente del refactor que Codex dejó sin commit el 2026-09-05
(14 archivos modificados, 8 nuevos, +2.808/−3.630). Cubre el código, una
prueba en vivo con una compra distinta de la que usó Codex, y las apreciaciones
del revisor separadas en cambiar, mejorar, agregar y quitar. Es una revisión
de lectura y prueba: no modifica la implementación.

## Alcance y método

- **Código.** Diff completo de los archivos tocados; nuevas piezas
  `ocr_purchase_review_flow.dart`, `ocr_catalog_unit_conversion.dart`,
  `ocr_product_review_steps.dart`, `ocr_review_evidence.dart`; host
  `ocr_upload_widget.dart`; picker; política y propuesta de proveedor.
  Analyzer limpio sobre esos archivos, `git diff --check` limpio, 110 pruebas
  focalizadas de 7 archivos en verde (corrida propia, 2026-09-05 15:00).
- **Prueba en vivo.** Sesión macOS `payroll` (pid 90499), tema claro y oscuro,
  escritorio 1821×944 y compacto 430×928. Compra elegida: **06/04/2026**
  (`AE060426`), 9 pedidos, 10 líneas, $99.204. Se eligió porque **no existe
  ningún día con pedidos y sin factura**: el calendario marca 12/08, 15/06,
  06/04, cuatro días de marzo y tres de febrero, todos «Compra ya facturada».
  Se recorrió desde el calendario hasta el paso 3 completo. **No se creó
  producto, no se guardó regla, no se guardó ni recibió factura.** Los dos
  productos «nuevos» del paso 3 quedaron sin crear a propósito.
- **Verdad de referencia.** Cada propuesta del matcher se comparó contra lo
  que el dueño vinculó en abril en la factura `AE060426` (leído en
  producción). Es la forma más honesta de medir la inteligencia: todos esos
  productos existen en el catálogo hoy.
- **Evidencia.** Frames reales en
  `/Users/Claudio/Dev/bikeshop-erp/.tmp/claude-ocr-review-2026-09-05/`
  (22 PNG, nombrados por paso). Las lecturas semánticas se citan en el texto.

## Qué hizo el flujo con esta compra

| Etapa | Observado |
|---|---|
| Calendario | Día 06/04 marcado «Compra ya facturada»; diálogo advierte y deja continuar. |
| Preparar factura | «Abriendo tus pedidos…» → «Leyendo pedido N de 9 (id)» → «Factura leída» en ~60 s. |
| Factura leída | `AE060426`, 6/4/2026, $99.204, 10 líneas «Por revisar», Suma = Total, Diferencia $0. |
| Paso 1 | Comparación de 10 líneas en 108 s (3–4 en paralelo). |
| Paso 2 | 8 filas existentes con cantidad, costo por compra, total y unidades por compra. |
| Paso 3 | 2 fichas nuevas con nombre, categoría, marca, unidades, costo y precio en columnas. |
| Vuelta a la factura | 8 «Vinculado»/«Descompuesto», 2 «Sin vínculo · Por revisar». Decisiones conservadas al reentrar. |

La factura real de abril tiene **13 líneas y $122.507**; la extracción de hoy
trae 10 líneas y $99.204. La diferencia son las dos manillas Shimano
(`AE0031`, `AE0034`, $23.303) que ya no aparecen en los pedidos de ese día en
AliExpress, más BUCKLOS que en abril quedó como dos líneas. No es defecto del
refactor, pero significa que «volver a revisar» un día ya facturado puede
producir una factura distinta de la registrada.

### Precisión del matcher, línea por línea

| # | Línea leída | Primera propuesta | Lo que vinculó el dueño en abril | Veredicto |
|---|---|---|---|---|
| 1 | Luz delantera LED 1000LM | AE0322 Luz Delantera 1000LM | AE0322 | correcta |
| 2 | ROCKBROS botella (gris) | AE0325 Botella Rockbros Gris | AE0325 | correcta, distingue variante |
| 3 | ROCKBROS botella (negra) | AE0324 Botella Rockbros Negra | AE0324 | correcta |
| 4 | Luz USB faro nocturno | AE0056 Luz Delantera AE | AE0317 Luz Recargable Para Bicicleta | **errónea**, el exacto existe |
| 5 | Pegatinas Los Simpson | AE0271 Porta Termo Negro Deemount | AE0318 Stickers Los Simpson | **errónea**, el exacto existe |
| 6 | Luz portátil IPX6 | AE0056 Luz Delantera AE | AE0321 Luz Delantera IPX6 | **errónea**, el exacto existe |
| 7 | BUCKLOS pinza del./tras. | AE0145 + AE0144 (regla recordada) | AE0145 + AE0144 | correcta, por regla |
| 8 | ZTTO portabotellas | AE0323 Porta Caramagiola ZTTO | AE0323 | correcta |
| 9 | Sillín hueco MTB | 2000000305530 Asiento Radical Mountain | AE0320 Sillín Prostático Riderace | **errónea**, el exacto existe |
| 10 | AVID palanca de freno | AE0319 Manetas Avid FR-5 | AE0319 | correcta |

Seis de diez correctas; una de esas seis por regla recordada. **Cuatro de las
nueve líneas que resolvió la IA propusieron un producto equivocado teniendo el
producto exacto en el catálogo.** En las stickers la causa se ve en el picker:
`AE0318 Stickers Los Simpson` está en «Accesorios» y la línea se clasificó en
«Accesorios / Souvenirs», así que la compuerta de categoría lo mandó a «8
productos en otra categoría» y subió un portabotellas de la categoría
Souvenirs. En las dos luces la IA propuso el mismo producto genérico `AE0056`
para dos artículos distintos, sin avisar que otra fila ya lo tenía.

En producción hay **13 reglas de variante** y todas son del 12 al 26 de
agosto; ninguna de las 13 líneas de abril dejó regla al crear su producto.
Por eso sólo BUCKLOS llegó como «Coincidencia de compras anteriores».

## Hallazgos por prioridad

### P1 · Integridad: la regla recordada no gobierna el paso 2

BUCKLOS llegó al paso 1 con la regla recordada (3 compras → 3 delanteros + 3
traseros). En el paso 2 la fila prellena **«Unidades por compra = 1»** e
**«Ingreso a inventario: 3 unidades · AE0145»**, y deja la regla detrás de un
botón «Aplicar regla guardada». Pulsé «Confirmar y preparar productos nuevos»
sin tocar esa fila: la confirmó en lote con 3 × AE0145 y **los 3 calipers
traseros desaparecieron del borrador** (lectura semántica: «Cantidades y
costos confirmados» junto a «Ingreso a inventario: 3 unidades · AE0145»,
frame `rev_step2_bottom.png`). Sólo al pulsar «Aplicar regla guardada» volvió
la descomposición (`rev_step2_rule_applied.png`).

Antes del refactor la regla era autoridad; ahora es una sugerencia que el
lote ignora en silencio. El dueño pidió que los montos «puedan estar
supeditados a las reglas aplicadas», no que la regla se pierda por defecto.

**Cambiar:** prellenar el paso 2 desde la regla (unidades y composición) con
el rótulo «Regla de compras anteriores» y un «Cambiar»; y que la acción de
lote no confirme una fila cuya regla sigue sin aplicar ni rechazar. La prueba
de regresión es esta misma línea: lote sin tocar la fila debe dejar
3 + 3, nunca 3.

### P1 · Estado falso: «Sin coincidencias sugeridas» antes de comparar

Al abrir el paso 1, las **diez** filas decían «Sin coincidencias sugeridas»
con «Marcar como nuevo» disponible, antes de que empezara ninguna
comparación (`rev_step1_loading.png`). Durante la corrida, las filas en cola
seguían diciéndolo: a los 12 s había 4 «Buscando coincidencias…» y **6 «Sin
coincidencias sugeridas»** que aún no se habían comparado. El estado
`needsSearch` se pinta igual que «no hay». Un operador puede marcar como nuevo
un producto que sí existe, sólo porque la fila todavía no entraba a la cola.

**Cambiar:** una fila sin comparar dice «Pendiente de comparar» y no ofrece
«Marcar como nuevo» hasta que la comparación termine o falle.

### P1 · La fila no muestra la calidad de la coincidencia

En el paso 1 el botón «Seleccionar producto» pesa lo mismo para una
«Coincidencia directa» que para un «Podría ser»; el nivel de evidencia sólo
se ve dentro del picker. Me pasó en la prueba: un toque vinculó «Porta Termo
Negro Deemount» a las stickers, sin ninguna advertencia, y quedó como
«Producto seleccionado». Es exactamente el riesgo que el dueño describió.

**Cambiar:** mostrar el badge de evidencia en la fila (ya existe
`OcrCandidateEvidence`), y para «Podría ser» hacer que el botón primario sea
«Comparar» en lugar de «Seleccionar producto».

### P1 · Inteligencia: el ERP olvida de qué listado nació cada producto

Detallado arriba. El matcher relegó el producto correcto en 4 de 9 líneas por
categoría o por genericidad. Y como al crear un producto desde AliExpress no
siempre se guarda la regla de variante, la siguiente compra del mismo listado
vuelve a pagar IA y vuelve a fallar.

**Corrección del dueño, 2026-09-05:** por nombre no se puede; nuestros
nombres nunca coinciden con los títulos de AliExpress. El «exacto» es el
listado: cada línea trae `listing_id` y `sku` de variante, y la tabla de reglas
ya resuelve listado + variante → SKU sin IA (BUCKLOS llegó así). Los once
productos de abril no guardaron código de proveedor, referencia ni regla; de
unos 370 productos AE sólo 13 tienen regla, todas de agosto.

**Mejorar:** que crear un producto desde una línea, o vincular uno en la
revisión, **siempre** deje la regla listado + variante → SKU; la segunda
compra del mismo listado entra resuelta sin IA. Con esta compra, 9 de las 10
líneas habrían llegado como «Coincidencia de compras anteriores». Para un
producto nunca comprado la IA sigue siendo el único camino; ahí la categoría
adivinada debería ser señal y no muro cuando lo que queda arriba es sólo
«Podría ser», decisión que choca con el contrato de identidad y es de Codex.

**Agregar:** aviso en la fila cuando otra línea del mismo lote ya eligió ese
producto (las dos luces con `AE0056`).

### P2 · UX del paso 2: largo, redundante y con decimales

- Ocho filas de ~300 px lógicos cada una, cuatro campos, un botón de
  descomposición y un «Confirmar línea» por fila, para lo que en 7 de 8 casos
  es «aceptar lo prellenado». El botón del lote confirma todas igual, así que
  «Confirmar línea» es redundante (código: `_advanceProductReviewStep` llama
  `_confirmPurchaseAmounts` por cada fila sin confirmar).
- Importes en CLP con decimales: «4028.5000», «8048.4000», «11912.3333»,
  «2528.00» (`_reviewNumber` usa cuatro decimales). En pesos no existen.
- «Costo por compra» recalcula el total y viceversa; correcto, pero el
  operador no ve cuál de los dos manda.

**Cambiar:** formato por moneda (CLP sin decimales). **Quitar:** «Confirmar
línea» por fila, o hacerlo la única confirmación. **Mejorar:** fila compacta
con campos en línea y desglose expandido sólo cuando hay regla o composición.

**Decisión del dueño, 2026-09-05:** el paso 2 es **una tabla ordenada**, no
fichas apiladas. Aprovecha mal el espacio, confunde y da más trabajo del que
ahorra. Propuesta de columnas, una fila por línea, alto fijo (T-01):

| Columna | Contenido | Editable |
|---|---|---|
| Producto | foto 32 px, SKU, nombre; la ficha se abre por primary key | no |
| Comprado | cantidad de compra | sí |
| Costo por compra | prellenado desde la factura, en CLP sin decimales | sí |
| Total línea | recalcula con cantidad × costo, o manda si se edita | sí |
| Unid./compra | prellenado desde la regla; 1 si no hay | sí |
| Ingreso a inventario | «5 un. · AE0212» o «3 AE0145 + 3 AE0144» | calculado |
| Regla | badge «Compras anteriores» / «Sin regla» y acción «Descomponer» | acción |
| Estado | listo · revisar (importe inválido, regla sin aplicar) | calculado |

Una composición muestra sus componentes como subfilas indentadas debajo de la
línea, igual que ya lo hace la vista previa de la factura («3 × AE0145 ·
delantero»). El único diálogo es el de descomposición. Sin «Confirmar línea»:
el pie confirma todas las filas válidas y las inválidas quedan marcadas en la
columna Estado. En compacto la misma tabla se apila por fila con las mismas
ocho celdas, sin desplegables.

### P2 · Dos botones para la misma acción, y palabras que no dicen lo que hacen

- «Ver otras coincidencias (N)» y «Buscar en inventario» abren el mismo
  diálogo (`onOpenCandidates` en ambos). Uno sobra.
- «Primera coincidencia» no es la palabra: es «Mejor coincidencia» o
  «Coincidencia sugerida».
- Dentro del picker aparece «Sin contradicción probada; disponible para
  comparación AI-first»: jerga interna del motor, no lenguaje del operador.
- El editor de descomposición se abre con el título «Comparar productos» y la
  cabecera «COMPRADO · variante a identificar», cuando la identidad ya está
  decidida y lo que se define es el contenido de una compra.
- La regla se confirma dos veces con el mismo rótulo: «Aplicar y guardar
  regla» en el picker y otra vez en el diálogo «Confirmar contenido».
- El botón de la factura dice «Revisar 2 productos» después de decidir, pero
  abre las diez filas y siempre en el paso 1.

**Quitar:** el botón duplicado y la segunda confirmación. **Cambiar:** los
rótulos anteriores.

### P2 · Paso 3: correcto en escritorio, incompleto respecto al compacto

La edición en columnas (nombre/SKU, categoría, marca, unidades, costo, precio)
funciona y es lo que el dueño pidió (`rev_step3.png`). Pero en escritorio
faltan «Se vende», la imagen del producto y «Reutilizar categoría y marca de
la otra variante», que sí aparecen en compacto (`compact_step3.png`,
`_NewProductFields`). Los dos hosts deben ofrecer los mismos campos.

El nombre que propone la IA para las manetas es «Manillas de Freno Avid
Negras (Par)»: la unidad de venta sigue viviendo en el nombre y no en las
«Unidades por compra», que quedaron en 1. Es el caso del par que ya está
anotado como pendiente; el paso 3 tampoco lo resuelve.

### P2 · Calendario y progreso

- El marcador del día en el calendario es un punto de 3 px al lado del número
  (`ae_picker_aug.png`); la semántica sí anuncia «Compra ya facturada». El
  ojo no.
- El progreso «Leyendo pedido 7 de 9 (id)» es claro. No hay forma de cancelar
  y el aviso «Día ya facturado» sigue sin abrir la factura existente
  (hallazgos 5 y 6 del informe de Codex, aún vigentes).

### P3 · Código

- `_ReviewBatch` es un `StatefulWidget` sin estado; sobra.
- `_CompactField` decide su altura con `MediaQuery.sizeOf(context).width`
  mientras el workspace decide `touch` con los `constraints` del
  `LayoutBuilder`; con el zoom 0,8 de escritorio los dos criterios pueden
  discrepar.
- `OcrPurchaseAmounts.apply` escribe `discount: 0` en la línea: el descuento
  del proveedor deja de verse en la factura aunque el total lo conserve.
- `ocr_upload_widget.dart` tiene 8.892 líneas y creció 1.436 en este diff; el
  paso a `ocr_purchase_review_flow.dart` es la dirección correcta, pero el
  host sigue concentrando el estado.
- Pruebas: 110 verdes, con mutación comprobada por Codex en la barrera de
  identidad. La prueba de dispositivo Android usa una fixture aislada.

### P3 · Excepciones en el log de la sesión durante el recorrido

- **Producto abierto desde la revisión.** Doce veces
  `There should be exactly one item with [DropdownButton]'s value: 0df3cbca-…`
  en `product_form_page.dart:8442`, al abrir la ficha de un producto por
  primary key (el proveedor cargado no coincide con los ítems del
  desplegable). Es del editor de producto, no del refactor, pero la revisión
  ahora lo abre desde cada fila.
- **Tabla de la factura.** Tres veces
  `'owner!._nodes.containsKey(id)': is not true` en
  `RenderTable.assembleSemanticsNode`, al pulsar «Revisar 10 productos». Puede
  estar provocado por la lectura semántica del agente durante la transición;
  hay que reproducirlo sin la herramienta antes de atribuirlo al widget.
- `TaskService` imprime «Loaded 74 tasks» ocho veces por cada ciclo de
  polling del correo y cayó con `Connection reset by peer` varias veces. Es
  ajeno al OCR y el título del chat de Codex era justamente el parpadeo del
  inbox.

## Resumen accionable

**Cambiar**

- La regla recordada prellena el paso 2 y el lote no confirma filas con regla
  pendiente.
- Fila sin comparar: «Pendiente de comparar», sin «Marcar como nuevo».
- Badge de evidencia en la fila; «Comparar» como primario para «Podría ser».
- Formato CLP sin decimales en el paso 2 y el paso 3.
- Rótulos: «Mejor coincidencia», título y cabecera del editor de contenido,
  botón «Revisar N productos» coherente con lo que abre.

**Mejorar**

- Guardar la regla listado + variante → SKU al crear o vincular un producto
  desde AliExpress; es lo que hace innecesaria la IA en la recompra.
- Categoría adivinada como señal, no muro, cuando arriba sólo hay «Podría ser».
- Paso 2 más denso; desglose sólo cuando hay regla o composición.
- Paso 3 con los mismos campos en escritorio y compacto.
- Reentrar a la revisión en el paso donde se salió.

**Agregar**

- Aviso de producto repetido entre líneas del mismo lote.
- «Aceptar N coincidencias directas» como acción de lote para las filas con
  «Coincidencia directa» o regla recordada, conservando la decisión por fila
  para las demás.
- Cancelar en el diálogo de progreso; abrir la factura existente desde el
  aviso del calendario.
- Marcador visible en el calendario, no un punto.

**Quitar**

- «Confirmar línea» por fila (o la confirmación de lote, pero no ambas).
- «Buscar en inventario» duplicado de «Ver otras coincidencias».
- La segunda confirmación «Aplicar y guardar regla».
- La jerga «Sin contradicción probada; disponible para comparación AI-first».

## Lo que no se probó

- Crear productos, guardar reglas, guardar y recibir la factura: son
  escrituras en producción y esta ronda era de revisión.
- Android real con importación completa.
- Una compra sin factura: no existe ninguna en la cuenta hoy.

## Estado en que queda la sesión

- Pestaña «Factura AliExpress · 2026-04-06» abierta con el borrador en el paso
  1, diez identidades decididas, dos marcadas como nuevas y sin crear. Se
  puede cerrar sin efecto en producción.
- La pestaña de Codex «Factura AliExpress · 2026-08-12» sigue abierta.
- Tema devuelto a Claro; ventana devuelta a 1821×944.
