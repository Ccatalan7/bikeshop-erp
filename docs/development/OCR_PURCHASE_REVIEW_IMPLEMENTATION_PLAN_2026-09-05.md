# Plan de implementación: revisión OCR de Compras del día (2026-09-05)

Sale de `OCR_PURCHASE_REVIEW_CLAUDE_REVIEW_2026-09-05.md` y de dos decisiones
del dueño del mismo día: el paso 2 es una tabla, y la identidad «exacta» es el
listado de AliExpress, no el nombre. Lo ejecuta Claude sobre el árbol que Codex
dejó sin commit; Codex no edita estos archivos mientras dure el plan.

## Reglas del plan

- Un bloque a la vez, en este orden. Cada bloque cierra con analyzer,
  pruebas focalizadas, mutación de su guardia nueva y hot reload en la sesión
  `payroll` sobre el borrador del 06/04/2026 que sigue abierto.
- Escrituras en producción sólo las que el flujo ya hace por diseño (guardar
  reglas de variante al confirmar). No se guarda ni recibe la factura de
  prueba; no se crean sus dos productos nuevos.
- Valores visuales desde la guía canónica por `DesignSync`
  (`projectId a0fa3196-6315-4b96-bde7-7cc801e7a74e`); si la sesión no tiene
  DesignSync, desde la copia en caché que Codex citó
  (`c430e08f-36b4-4cf0-b14b-322c1787f4cd/tool-results/bkyc7j0gj.txt`).
  Componentes: T-01/T-03 tabla, I-01 campo en celda, S-06 badge, F-04/F-06
  espaciado y densidad táctil.
- Al cerrar cada bloque se actualiza `canonical-ui-surfaces.md` si cambió la
  superficie, y el reporte de revisión marca el hallazgo como resuelto.

## Bloque 0 · Punto de partida

1. Verificar que Codex está inactivo y que `HEAD == origin` (hoy: `c83fe9a3`).
2. Commit de checkpoint con el árbol de Codex tal cual («wip(ocr): refactor de
   revisión en tres pasos, checkpoint previo a correcciones»). Así cada bloque
   queda diffable y reversible por separado.
3. Línea base: 110 pruebas de los 7 archivos, analyzer limpio.

## Bloque 1 · La regla manda y el vínculo deja regla

**Qué.** (a) Al entrar al paso 2, toda fila existente que traiga regla
recordada la aplica sola al borrador y muestra «Regla de compras anteriores»
con «Cambiar». (b) El botón de lote no avanza mientras haya una fila con regla
sin aplicar ni rechazar; el pie dice cuántas. (c) Al confirmar el paso 2, cada
fila vinculada a un existente sin regla guarda una: listado + variante → SKU,
con las unidades por compra confirmadas (`single` si 1, `homogeneous` si más).
Así la recompra del mismo listado entra resuelta sin IA.

**Dónde.** `ocr_upload_widget.dart`: `_advanceProductReviewStep` (aplicar al
pasar de identidad a importes, con `_useSupplierVariantResolutionForEntry`
sin `suggestOnly`), `_canAdvanceProductReview` y `_productReviewBlockingReason`
(guardia y texto), `_confirmPurchaseAmounts` (deja los datos listos) y un
nuevo `_rememberLinkedProductRules` que corre al salir del paso 2 usando
`SupplierVariantResolutionService.remember` con huella idempotente
(`supplierOperationFor`) y `decisionSource: operatorConfirmed`. `_NewProductEntry`
gana `ruleRejected`. `ocr_purchase_review_flow.dart` gana la regla de
avance como función pura.

**Pruebas.** `ocr_purchase_review_flow_test.dart`: lote con regla pendiente no
avanza; rechazar la regla sí. `ocr_product_review_integration_contract_test.dart`:
al confirmar importes con un existente sin regla se llama `remember` una vez
por fila y con la huella correcta; una segunda confirmación no repite la
llamada; un fallo del RPC no bloquea el borrador y deja aviso en la fila.
Mutación: desactivar la guardia debe poner rojo el test del lote.

**En vivo.** Reabrir el borrador 06/04: BUCKLOS debe llegar con 3 + 3 sin tocar
nada; el lote debe negarse si se rechaza la regla y no se define contenido;
al confirmar, `supplier_variant_resolution_revisions` debe tener filas nuevas
para los listados de las luces, botellas, portabotellas y manetas.

## Bloque 2 · Paso 1 dice la verdad

**Qué.** (a) Fila sin comparar: «Pendiente de comparar», sin «Marcar como
nuevo» ni «Seleccionar producto» hasta que la comparación termine o falle.
(b) Badge de evidencia en la tarjeta del candidato; con «Podría ser» el botón
primario es «Comparar» y «Seleccionar» pasa a secundario. (c) Un solo botón
«Comparar (N)» en lugar de «Ver otras coincidencias» más «Buscar en
inventario». (d) Aviso «Otra línea ya eligió este producto» cuando dos líneas
del lote comparten candidato o selección. (e) «Mejor coincidencia» en vez de
«Primera coincidencia».

**Dónde.** `ocr_product_review_steps.dart` (`_IdentityReviewRow`,
`_InventoryProductReference`), `ocr_product_review_workspace.dart`
(`OcrProductReviewLine` gana `bestEvidence` y `sharedWithLineTitle`),
`ocr_upload_widget.dart` (`_buildProductReviewLine` calcula ambos;
`_productReviewStatus` distingue `needsSearch`).

**Pruebas.** `ocr_product_review_workspace_test.dart`: los tres estados de fila
(pendiente, buscando, lista) con sus botones; badge por tier; aviso de
repetido. Mutación: pintar `needsSearch` como lista debe fallar.

**En vivo.** Abrir «Revisar» sobre una factura recién leída y capturar los
primeros 3 s: ninguna fila debe decir «Sin coincidencias». Fila 4 y 6 del
06/04 deben mostrar el aviso de repetido mientras ambas propongan AE0056.

**Fuera de este bloque, para decisión con Codex.** Suavizar la compuerta de
categoría cuando lo viable es sólo «Podría ser» toca
`product-identity-matching-contract.md`; se propone en el reporte y no se
implementa sin ese acuerdo.

## Bloque 3 · Paso 2 es una tabla

**Qué.** Reemplazar las fichas apiladas por una tabla T-01 de una fila por
línea y ocho columnas: Producto (foto 32, SKU, nombre con ficha por primary
key) · Comprado · Costo por compra · Total línea · Unid./compra · Ingreso a
inventario · Regla · Estado. Tres celdas editables en línea (I-01);
recálculo cantidad × costo ↔ total como hoy. Composición como subfilas
indentadas bajo la línea, igual que la vista previa de la factura. La columna
Regla lleva el badge y la acción «Descomponer»; Estado dice «listo» o por qué
no. Sin «Confirmar línea»: el pie confirma las válidas. CLP sin decimales
(formateador común, también para el paso 3). En compacto, la misma fila se
apila con las mismas ocho celdas y sin desplegables.

**Dónde.** Nuevo `ocr_purchase_amounts_table.dart` como `part` del workspace,
que reemplaza `_PurchaseAmountsRow`; `ocr_review_evidence.dart` gana
`ocrReviewMoney` (CLP sin decimales) y `_NewProductEntry._reviewNumber` deja
de escribir cuatro decimales; `_ReviewBatchView` monta la tabla en el paso
`amounts`. Valores de T-01, I-01 y S-06 leídos de la guía y atados a roles.

**Pruebas.** Widget: tabla en 1672 y 430, claro y oscuro; edición en celda
recalcula; subfilas de composición; Estado bloquea al pie; ningún importe con
decimales. Se conserva la prueba de que el pie confirma todas las válidas.

**En vivo.** Las ocho líneas del 06/04 caben en una pantalla de escritorio;
BUCKLOS muestra sus dos subfilas; captura en las seis celdas.

## Bloque 4 · Picker y descomposición con una sola voz

**Qué.** (a) En modo contenido, título «Definir contenido de la compra» y
cabecera «COMPRADO · contenido por definir». (b) Una sola confirmación de
regla: el picker cierra con «Continuar» y el diálogo «Confirmar contenido» es
el único «Aplicar y guardar regla». (c) La frase «Sin contradicción probada;
disponible para comparación AI-first» se traduce a lenguaje de operador en la
capa de presentación («Coincide en tipo y función; falta confirmar el modelo»)
sin tocar el ranking. (d) El botón de la factura dice «Revisar productos · N
por decidir» y reabrir vuelve al paso donde se salió.

**Dónde.** `ocr_candidate_picker.dart` (título, footer, `_CandidateRow`),
`ocr_review_evidence.dart` (`ocrReadableEvidence` cubre esa frase),
`ocr_upload_widget.dart` (`_confirmSupplierResolutionProposal`, rótulo del
botón en `_buildParsedPreview`, conservar `_purchaseReviewStep` al cerrar y
reabrir).

**Pruebas.** `ocr_candidate_picker_test.dart`: título y footer por modo; la
frase interna no aparece en el overlay. Contrato: reabrir conserva el paso.

## Bloque 5 · Paso 3 completo y bordes del flujo

**Qué.** (a) Escritorio del paso 3 con «Se vende», imagen y «Reutilizar
categoría y marca» en una segunda línea de la fila, como ya los tiene el
compacto. (b) Marcador del calendario visible (S-06 en vez del punto de 3 px),
valor leído de la guía. (c) El aviso «Día ya facturado» ofrece «Abrir factura
AE…» usando el resultado de `checkInvoiceNumberExists`. (d) Cancelar en el
diálogo de progreso sólo si la extracción admite un token de cancelación sin
dejar el navegador a medias; si no, se declara pendiente.

**Dónde.** `ocr_product_review_steps.dart` (`_NewCatalogRow`),
`vb_marked_date_picker.dart`, `webview_module_page.dart`
(`_buildAliExpressDayHint`, `_startAliExpressDailyImport`).

**Pruebas.** Widget del paso 3 en escritorio con los tres controles; diálogo
del día con la acción de abrir factura.

## Bloque 6 · Cierre

1. Batería focalizada completa de los archivos tocados más las suites que
   compilan contra tipos compartidos (`dart analyze lib test` si cambió un
   tipo público).
2. Seis celdas capturadas de los pasos 1, 2 y 3 con el borrador real.
3. Registro en `canonical-ui-surfaces.md`, nota en la guía GUI de escritorio
   sobre el paso 2 como tabla, y el reporte de revisión con cada hallazgo
   marcado como resuelto o pendiente.
4. Cross-review con Codex en esta frontera de bloque, según
   `CODEX_CLAUDE_COLLABORATION.md`. Un commit por bloque; `origin` sólo
   después de esa revisión.

## Estado (2026-09-05, cierre de la tarde)

Bloques 0–5 implementados y verificados en vivo sobre la reimportación del
06/04/2026; el matcher sí se tocó, contra lo que decía el plan: la traza
mostró que la IA acertaba y el código descartaba, así que la corrección fue
de post-proceso y recorrido (`product-identity-matching-contract.md`,
secciones del 2026-09-05). Pendiente del bloque 6: cross-review con Codex y
`origin`. Quedó fuera: el marcador del calendario (sin valor en la guía) y la
acción de lote «Aceptar N coincidencias directas».

## Lo que este plan no hace

- No cambia el matcher ni la compuerta de categoría (queda para acuerdo con
  Codex sobre el contrato de identidad).
- No guarda ni recibe la factura del 06/04 ni crea sus productos.
- No prueba Android real; la paridad compacta se verifica a 430 px en macOS.
