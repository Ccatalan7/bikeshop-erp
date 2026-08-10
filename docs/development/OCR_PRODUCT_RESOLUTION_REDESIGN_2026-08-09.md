# Rediseño del flujo OCR factura → conciliación → producto ERP

**Fecha:** 2026-08-09 · **Estado:** dirección cerrada, pendiente de implementación por Codex
**Origen:** revisión independiente pedida por el dueño tras rechazar la implementación actual.
**Alcance:** `ocr_upload_widget.dart`, `ocr_product_review_workspace.dart`,
`product_duplicate_matcher_service.dart`, `product_catalog_semantic_resolver.dart`.

Este documento es **una sola dirección**, no un menú. Donde hay una decisión,
está tomada y justificada. Lo que no se puede leer (valores visuales de Design)
está marcado como *por leer con DesignSync*, nunca reemplazado por un número
plausible.

Evidencia usada: los dos frames rechazados (21:09 y 21:10 del 2026-08-09), el
código real en el árbol de trabajo, y **cuatro lecturas de sólo lectura sobre
producción** (`scripts/db/query.sh production`) sobre el catálogo de 1.614
productos activos.

---

## A. Diagnóstico jerarquizado

### A.0 El defecto raíz, del que cuelgan casi todos los demás

**El matcher decide qué es una pieza buscando palabras en cualquier parte de una
bolsa de texto, y después usa esa familia como compuerta dura.**

Un título de repuesto no es una bolsa de palabras. Tiene gramática:

```
[marca] [familia] [modelo] [medidas/estándar] [posición] para|compatible con [otra cosa] (variante)
```

Todo lo que va después de `para` / `for` / `compatible con` describe **otra
pieza**, no ésta. El código actual sólo neutraliza `compatible con` y sólo para
extraer modelos (`_withoutCompatibilityClaims`, línea 1224); no conoce `para`
ni `for`, y no lo aplica ni a la inferencia de familia ni a los tokens de
keyword. Las tres fallas que el dueño reportó son la misma falla.

### P0 — Matcher: la familia se infiere del sustantivo equivocado

`_inferProductFamilies` (línea 1346) marca una familia si la frase aparece **en
cualquier posición**. Consecuencia medida sobre los datos reales:

| Línea de factura | Familia que infiere hoy | Por qué | Efecto |
|---|---|---|---|
| `Novatec bujes … buje de Cassette 28/32/36 agujeros HG SX` | `cassette` | `buje` **no existe en el léxico** (sólo `maza`/`hub`, línea 1436); la única palabra reconocida es `Cassette`, que está en el segmento de compatibilidad | La compuerta exige `cassette` → sobreviven espaciadores |
| `IXF-platos y bielas … Compatible con SHIMANO/SRAM` | `{chainring, crankset, chain}` | `rueda de cadena` → `chain` | Compite contra cadenas y bielas izquierdas |

Y del lado del catálogo, `_buildProductSimilarityText` (línea 1171) concatena
**`product.categoryName`** en el texto del que se infiere la familia. Por eso
`AE0125 Espaciador de Cassette RISK 1.5mm`, cuya categoría es literalmente
`Espaciadores de Cassette`, hereda la familia `cassette` y **pasa la compuerta
del buje Novatec**. La categoría, que es el dato estructurado más confiable que
existe, se usa como si fuera prosa.

### P0 — Matcher: el modelo exacto no cuenta como identidad, así que la compuerta lo mata

Líneas 395-403:

```dart
final hasDeterministicIdentity = identityScore >= 1 || exactCanonicalImage;
if (familyConflict && !hasDeterministicIdentity) continue;
```

`hasExactModelMatch` **no está** en `hasDeterministicIdentity`. En producción
existe `AE0063 · Maza Delantera Novatec 32H 100x9mm HG D041SB` — el modelo
`D041SB` está impreso en el nombre y coincide exactamente con la línea de
factura. Se descarta antes de puntuar, porque su familia (`hub`) no intersecta
la familia mal inferida del probe (`cassette`).

### P0 — Matcher: el catálogo real habla chileno y el léxico no

Lecturas de producción:

- `AE0093 · Volante IXF Integrado Black 170Mm + Motor BSA + Corona 34T`,
  categoría `Volante`, marca `IXF`. **Es el producto que el dueño dice que ya
  existe.** El matcher no conoce `volante`; sí conoce `motor bsa`, que está en
  la lista de `bottom_bracket` (línea 1401). Familia inferida:
  `{bottom_bracket}`. Intersección con `{chainring, crankset, chain}` = ∅ →
  **descartado por compuerta dura**.
- La categoría `Coronas` (9 productos 104BCD) tampoco tiene entrada: `corona`
  no existe en ninguno de los dos léxicos.
- `buje` no existe. El catálogo usa `Maza` y hasta tiene una categoría `Maza`.

Además hay **dos léxicos que no se hablan**:
`ProductCatalogSemanticResolver._inferFamily` conoce 4 familias y sí tiene
`volante`; el matcher conoce ~40 y no lo tiene. Dos dueños de la misma verdad.

### P0 — Matcher: la imagen pesa 0.55 y no puede distinguir formas

`_combineDuplicateScores` (línea 2456) le da a la imagen **55% del peso** cuando
hay huella disponible. Esa huella es un aHash/dHash 8×8 más RGB medio. El
comentario del propio código (líneas 552-561) admite que *«no puede distinguir
formas distintas ni "cosa negra" vs "cosa plateada"»*. Un espaciador negro
redondo y un buje negro sobre fondo blanco producen la misma huella. Ésa es la
razón mecánica de «resultados absurdos»: la señal dominante del ranking es la
que menos información tiene. 1.312 de 1.614 productos activos tienen huella, así
que se aplica casi siempre.

### P0 — Matcher: «compatible con Shimano» entra al bag of words

`_extractSimilarityTokens` no segmenta compatibilidad. Los tokens `shimano`,
`sram`, `compatible`, `104bcd`, `mtb` del título IXF suben el keyword score de
cualquier producto Shimano. `104BCD` fue correctamente excluido de los
identificadores de modelo (líneas 1265-1270) pero **sigue siendo token**.

### P0 — Recuperación: se descarga el catálogo entero por cada revisión

`_checkSimilarProductsForNewEntries` llama `inventoryService.getProducts()`
(línea 3089), que ejecuta `select('products', fetchAll: true)` — 1.614 filas
completas al cliente. El matcher recorre esa lista una vez por línea. La
búsqueda semántica existe (`searchProductsSemantic`, 1.593/1.614 con embedding)
pero sus resultados se **intersectan** con esa misma lista descargada, así que no
ahorra nada. Esto es también el antecedente del incidente de memoria del
2026-08-05.

### P1 — Tabla 2: la geometría no existe, hay una lista de píxeles

`_DesktopReviewTable` (línea 542):

- `static const double _minimumWidth = 1680` dentro de un
  `SingleChildScrollView(scrollDirection: Axis.horizontal)`. **La tabla siempre
  scrollea horizontalmente**, en cualquier viewport. Lo prohíben
  `GUI_DESIGN_PRINCIPLES` §7 y `universal-ui-component-system` §8.
- Anchos literales por celda: `88, 180, 150, 110, 72, 72, 238, 52, 32`. Sin
  `min`/`max`/`flex`, sin orden de compresión declarado. Eso es exactamente
  «columnas de tamaños arbitrarios».
- `dataRowMinHeight: 108` más una aritmética por fila
  `rowHeight = 108 + alternativas*44 + …` (líneas 663-666): **cada fila mide
  distinto según cuántos candidatos tenga expandidos**. Eso es «filas de tamaños
  arbitrarios».
- `DataTable` de Material es el primitivo equivocado: dimensiona por contenido y
  no admite prioridades de columna. No se arregla con píxeles; se cambia.
- La etapa 1 tiene la misma enfermedad: `ConstrainedBox(minWidth: 1280)` +
  scroll horizontal (`ocr_upload_widget.dart` línea 841).

### P1 — Categoría: la ruta completa dentro de 150 px

Línea 757: `labelFor: (category) => category.fullPath` dentro de un
`SizedBox(width: 150)`. `Componentes / Dirección / Tee` truncado a la mitad, que
es lo que se ve en el frame rechazado. El nombre corto (`Tee`) es la identidad;
la ruta sólo sirve para desambiguar **dentro de la búsqueda**.

Además `_SearchableDropdown` (línea 2045) es un **componente local nuevo** en un
archivo de feature. `S-06 VbSearchableSelect` está publicado en la guía y
declarado como *no implementado* en `universal-ui-component-system.md`. Escribir
una variante local es precisamente el defecto que ese documento existe para
impedir.

### P1 — Parecidos: se expanden dentro de la fila

`expandedAlternatives` + `_DesktopAlternativeDecision` (línea 1378) inyectan una
banda dentro de la celda de decisión y recalculan la altura de esa fila. La
tabla deja de ser comparable en el momento exacto en que el operador necesita
comparar.

### P2 — Defectos adicionales que encontré (no estaban en tu lista)

1. **El estado se pinta tres veces con tres vocabularios distintos**: la insignia
   de la celda origen, la celda de decisión y el contador del encabezado
   (`Por revisar` / `Buscando…` / `0 listas · 7 por decidir`).
2. **Dos nombres en la misma fila**: `Producto de factura` y `Nombre ERP`. El
   operador lee dos nombres y no sabe cuál es el producto.
3. **La columna `SKU ERP` está vacía en toda fila nueva** («Se asignará al
   crear»): 88 px por fila de nada.
4. **Dos costos con la misma palabra**: `Costo unit. factura` (etapa 1) y
   `Costo catálogo` (etapa 2), más un switch `Costo con IVA` en el pie de la
   etapa 2 que **reinterpreta retroactivamente** los números de la etapa 1.
5. `Precio sugerido = costo × 2` se declara como política en el pie, pero la
   celda es un número editable sin ninguna señal de que editarlo rompe la regla.
6. **El botón primario miente**: `Crear 7 productos` cuando parte de las líneas
   se van a vincular, no a crear.
7. `_buildDuplicateSignals` mezcla evidencia de identidad con `Stock: N`. El
   stock no es evidencia de que dos productos sean el mismo.
8. **`Tooltip` por celda editable** (`_DesktopTextCell`, línea 984) dentro de una
   tabla gobernada por `LayoutBuilder`: es el patrón registrado en memoria como
   causa de caída del módulo al redimensionar. Y el origen del dato
   («limpiado por IA») es información importante detrás de hover, que
   `GUI_DESIGN_PRINCIPLES` §12 prohíbe.
9. La razón de bloqueo junto al primario deshabilitado está truncada a dos
   líneas: *«Espera a que termine el análisis o la carga de imáge…»*. El
   operador no puede leer por qué no puede avanzar.
10. `_supplierScopedProducts` (línea 1138) cae al catálogo completo cuando el
    conjunto del proveedor tiene **menos de 5** productos. Un número mágico que
    cambia el universo de búsqueda sin que nadie lo vea.
11. El auto-vínculo por alias recordado (`_resolveRememberedProductAlias`) deja
    la fila en `Vinculado`, igual que un vínculo manual. Dos causas distintas,
    el mismo estado — lo que `GUI_DESIGN_PRINCIPLES` llama derivar el estado de
    un número en vez del porqué.
12. «7 de 7 necesitan una decisión» cuenta bien pero no nombra la decisión.

---

## B. Flujo end-to-end

Se mantienen dos etapas, pero con trabajos que hoy están mezclados y que a
partir de ahora no se cruzan.

### Etapa 1 — «Lo que dice la factura» (el documento)

**Lo primero que ve:** la cabecera del documento (proveedor, N°, fecha, total
leído, y el switch *el costo ya incluye IVA*) y debajo la **tabla 1**: una fila
por línea del documento con cantidad, costo unitario, descuento y total.

**La única decisión de esta etapa:** *¿los números cuadran?* La franja de cierre
compara la suma de las líneas contra el total leído y lo dice en palabras
(`cuadra` / `faltan $2.310`). Se corrigen cantidades, costos y descuentos en la
propia tabla.

**Por qué esa función pertenece aquí:** una factura es un documento contable
antes que un lote de productos. El costo determina el precio y el margen; si el
costo está mal leído, todo el trabajo de catálogo se hace sobre una base falsa.
Y el switch de IVA **cambia la aritmética que esta tabla muestra**, así que es
aquí donde su efecto es verificable — no en el pie de la etapa siguiente, donde
hoy reinterpreta en silencio números que el operador ya dio por buenos.

Aquí **no se toca la identidad del producto**. No hay columna «Producto ERP», ni
insignia `Por revisar` por fila: en esta etapa no hay nada que revisar por línea.

**Salida:** `Conciliar con inventario`.

### Etapa 2 — «Conciliar con inventario»

**Lo primero que ve:** la **tabla 2**, una fila por línea de factura, con la
columna **Decisión** ya poblada por el sistema, y arriba una sola frase de
estado: `3 listas · 4 esperan tu decisión`.

**La decisión por fila es una sola, con tres salidas:** *vincular a un producto
existente*, *crear uno nuevo*, *omitir esta línea*.

**Qué ocurre antes de que él llegue:** por cada línea, en este orden —
1. alias recordado del proveedor (`item id` + variante) → si existe, se vincula
   solo y la celda dice **por qué** («ya lo vinculaste el 12/2»);
2. identidad exacta (SKU interno, misma publicación **y** misma variante, o
   imagen idéntica) → se vincula solo, con su razón;
3. si no, se buscan candidatos y la fila queda en `Revisar` o en
   `Sin coincidencia fiable`.

**Qué ocurre cuando decide:** `Revisar` abre el **overlay centrado de parecidos**
(sección E). Elegir uno vincula y cierra. `Ninguno` deja la fila en *crear
nuevo* con la ficha ya editable en la tabla.

**Por qué el trabajo de catálogo pertenece aquí y no antes:** vincular o crear
un producto es una decisión sobre el inventario, no sobre el documento; y sólo
tiene sentido cuando el costo ya es correcto, porque el costo viaja al producto.

**Salida:** `Confirmar 7 líneas` — el rótulo nombra el acto, no el objeto, porque
el lote mezcla vínculos y creaciones. El pie desglosa: `4 vincular · 2 crear ·
1 omitir`.

**Vuelta:** las dos etapas se abren con `push` y se cierran con
`ReturnNavigation.close`, conservando el borrador de la factura, el scroll y la
fila seleccionada.

---

## C. Especificación de las dos tablas

> **Sobre los números de esta sección.** Los anchos, proporciones, prioridades y
> el orden de compresión son decisiones de layout y son mías/de Codex. Los
> valores *visuales* — color, radio, sombra, borde, tipografía y el ritmo
> vertical que fija la altura final de fila — se leen de
> `GUÍA GENERAL Viñabike - Componentes` con `DesignSync` antes de escribir el
> widget. El único alto de control que está publicado y citado en el repositorio
> es **34 pointer / 48 touch** (`F-06`, citado en
> `universal-ui-component-system.md`), y de ahí cuelga la altura de fila.

### Principios que gobiernan ambas tablas

1. **Cero scroll horizontal.** Nunca. Cada columna declara `min`, `max` o `flex`
   y hay un **orden de compresión** explícito. Si el ancho no alcanza, se aplica
   el siguiente paso de compresión; jamás aparece una barra horizontal.
2. **Altura de fila uniforme** dentro de una misma tabla y densidad. Ninguna
   fila crece por su contenido ni por su estado. Los títulos largos se recortan a
   2 líneas; lo que no cabe se abre, no se estira.
3. **Un solo alto de control.** Todos los inputs, selectores y switches de una
   fila comparten el alto del control (34 pointer / 48 touch). Nada de campos de
   alturas distintas en la misma fila.
4. **Alineación por tipo de dato:** texto a la izquierda; dinero y cantidades a
   la derecha con cifras tabulares (`VbMoneyText`, `F-03`); códigos en mono;
   controles centrados sólo si son la única cosa en la celda.
5. **Truncamiento con regla:** títulos a 2 líneas con elipsis; nombres de una
   línea; códigos nunca se truncan (si no caben, se comprime otra columna
   antes); rutas de categoría **no se muestran**.
6. **La separación entre filas es carga estructural**, no decoración: se usa el
   rol `outlineVariant` directo, sin alpha (regla explícita de la guía).

### Tabla 1 — Factura leída

| # | Columna | Tamaño | Alineación | Contenido y edición |
|---|---|---|---|---|
| 1 | `#` | fijo 40 | derecha, tabular | número de línea del documento |
| 2 | Producto leído | **flex 1**, min 300 | izquierda | miniatura 32 (sólo si hay imagen) + título del proveedor, **2 líneas máx**. No editable: es lo que dice el documento |
| 3 | Código proveedor | min 120 / max 160 | izquierda, mono | tal cual |
| 4 | Cant. | fijo 72 | derecha, tabular | **editable** |
| 5 | Costo unit. | fijo 116 | derecha, tabular | **editable** |
| 6 | Dscto. | fijo 96 | derecha, tabular | **editable**; vacío cuando es 0, nunca `0` |
| 7 | Total línea | fijo 128 | derecha, tabular, semibold | derivado, no editable |

Fijo = 452 px + medianiles. A 1.100 px de contenido la columna flexible recibe
~570 px, que es donde un título de AliExpress se lee cómodo en dos líneas.

**Orden de compresión:** (1) `Dscto.` se pliega como segunda línea dentro de
`Total línea`; (2) `Código proveedor` baja a min 120; (3) `Producto leído` baja
hasta min 300; (4) bajo 900 px se recompone (sección G).

**Estados:** cargando = 5 filas esqueleto con la misma geometría (`X-01`); error
de lectura = se conserva la cabecera y la tabla se reemplaza por un `VbNotice`
con reintento; línea sin costo = celda vacía con marca de «no consta», nunca 0.

**Pie de la tabla 1 (franja de cuadratura, fija):**
`7 líneas · Suma $147.595 · Total leído $147.595` + veredicto en palabras
(`cuadra` en tono success, o `faltan $2.310` en warning con acción
`Revisar diferencias`). A la derecha: `Volver a cargar` (secundario) y
`Conciliar con inventario` (primario).

`Guardar plantilla` sale del bloque de identidad de la factura y pasa a un menú
`⋯` de la cabecera: es una acción de administración rara, no una decisión del
flujo.

### Tabla 2 — Conciliación

| # | Columna | Tamaño | Alineación | Contenido y edición |
|---|---|---|---|---|
| 1 | Incluir | fijo 44 | centro | casilla; **toda la fila es hit target** |
| 2 | Línea de factura | **flex 3**, min 260 | izquierda | miniatura 40 + título proveedor (2 líneas) + código proveedor en mono. No editable |
| 3 | **Decisión** | fijo 248 | izquierda | ver abajo. Es la columna que manda |
| 4 | Nombre en el ERP | **flex 2**, min 200 | izquierda | input de una línea |
| 5 | Categoría | fijo 200 | izquierda | `S-06` buscable, **nombre corto** |
| 6 | Marca | fijo 156 | izquierda | `S-06` buscable + crear inline |
| 7 | Costo neto | fijo 104 | derecha, tabular | derivado de la etapa 1, **no editable** |
| 8 | Precio | fijo 104 | derecha, tabular | editable |
| 9 | Se vende | fijo 72 | centro | switch |

**La columna `SKU ERP` se elimina.** En una línea nueva siempre está vacía («se
asignará al crear») y en una vinculada el SKU ya se muestra dentro de la celda
de decisión. Era ruido en el 100% de las filas.

**Prioridades:** `Decisión` y `Línea de factura` son las dos columnas que el
operador realmente lee; `Nombre`, `Categoría` y `Marca` sólo se tocan cuando la
decisión es *crear*; el dinero es verificación.

**Orden de compresión** (declarado, verificable):
1. `Se vende` → pasa al menú `⋯` de la fila.
2. `Costo neto` + `Precio` → una sola celda de 132 px, costo arriba (secundario)
   y precio abajo (editable).
3. `Marca` → segunda línea dentro de `Nombre en el ERP`.
4. `Categoría` → tercera línea dentro de `Nombre en el ERP`.
5. Bajo 900 px → composición táctil (sección G), **no** una tabla en miniatura.

**El origen de cada valor** (OCR / IA / tú) se marca de forma **persistente**:
una barra fina en el borde inicial del campo, con su significado en la semántica
del campo y en una leyenda `E-01` sobre la tabla. No un chip flotante encima del
input (frame rechazado), no un `Tooltip` por celda.

### La celda `Decisión`: cuatro estados, una acción cada uno

| Estado | Qué muestra | Acción |
|---|---|---|
| `Buscando` | línea esqueleto + `Buscando…` | ninguna |
| `Vinculado` | miniatura 24 + nombre ERP + SKU + **la razón** (`imagen idéntica` / `ya lo vinculaste antes` / `lo elegiste tú`) | `Cambiar` |
| `Revisar` | `3 parecidos · el mejor: Volante IXF Integrado…` | **`Revisar`** → overlay centrado |
| `Sin coincidencia fiable` | `No encontré ninguno que calce` en tono neutro, y la fila queda por defecto en **crear nuevo** | `Buscar a mano` → mismo overlay en modo búsqueda |

Tres decisiones deliberadas:

- **No hay botón `Vincular` en la fila.** Vincular sin ver la evidencia es
  exactamente como se producen los vínculos equivocados. El único camino a un
  vínculo no exacto pasa por el overlay.
- **El auto-vínculo es sólo para identidad exacta**, y siempre dice su razón. Un
  «candidato probable» nunca se vincula solo.
- **`Sin coincidencia fiable` no es un error.** Es la respuesta correcta cuando
  el catálogo no tiene la pieza, y el flujo ya está encaminado a crearla.

Con esto desaparecen la insignia de estado de la celda origen y la columna
`Estado`: el estado vive en un solo lugar.

**Pie de la tabla 2 (fijo):** izquierda `4 vincular · 2 crear · 1 omitir` y el
control de la regla de precio (`Precio sugerido = costo × 2`, con su efecto
aplicándose sólo a las filas incluidas y no editadas a mano); derecha
`Volver a la factura` (secundario) y `Confirmar 7 líneas` (primario). Si el
primario está deshabilitado, la razón se muestra **completa** junto a él, sin
truncar, y nombra la fila responsable.

---

## D. Contrato del selector buscable de categorías (`S-06`)

**Dueño canónico:** `VbSearchableSelect<T>` en
`lib/shared/widgets/vb_searchable_select.dart`. Hoy **no existe** y por eso el
módulo escribió el suyo. Se crea como componente compartido, con dos consumidores
reales desde el primer día (categoría y marca), y `_SearchableDropdown` local se
borra.

**Celda cerrada**
- Muestra **sólo el nombre corto**: `Tee`, `Maza`, `Rotores`, `Volante`.
- La ruta completa **nunca** aparece en la celda, ni truncada, ni como tooltip
  primario.
- Sólo si dos categorías del tenant comparten hoja, la celda añade una segunda
  línea silenciosa con el padre inmediato (`en Dirección`).
- Vacío: `Sin categoría` en tono secundario, más la sugerencia de IA marcada como
  sugerencia y no como valor.
- Semántica: `Categoría: Tee, dentro de Componentes / Dirección`.

**Popover de búsqueda** (`O-02`; en táctil `<900` es `O-05` bottom sheet)
- Ancho **independiente del disparador**: min 360, max 480, a 12 px de los bordes
  del viewport. La celda mide 200; el resultado necesita más y lo toma.
- Cada resultado: **nombre corto** con peso fuerte + breadcrumb de ancestros en
  una línea secundaria, con elipsis **al inicio** para que el padre quede visible
  (`… / Transmisión / Volantes`).
- La búsqueda calza contra hoja, ancestros **y sinónimos** — el mismo léxico del
  matcher (sección F.2). Escribir `buje` encuentra `Maza`. Ése es el punto donde
  el operador y el algoritmo comparten vocabulario.
- Consulta vacía: las 5 usadas en esta factura, y luego el árbol por frecuencia.
- Sin resultados: `No existe esa categoría` y, con permiso, `Crear "…"`. Nunca
  una lista vacía sin salida.

**Teclado**
`↑`/`↓` mueven, `Enter` elige, `Esc` cierra y devuelve el foco al disparador,
`Tab` confirma y avanza a la siguiente celda de la fila. El type-ahead resalta
pero **no** auto-selecciona. Al abrir, el foco entra al campo de búsqueda.

**Selección**
Un clic elige y cierra. La marca de origen del campo pasa a `tuyo` y esa fila
deja de aceptar sugerencias automáticas de IA para esa columna.

---

## E. Contrato del overlay centrado de parecidos

**Superficie:** overlay **centrado con scrim**, con la anatomía visual de
`O-02 VbPopoverSurface` (superficie, radio, sombra y borde leídos de la guía)
presentada centrada. No anclado: la tarea no es una elección local breve sino una
comparación contra evidencia, y anclarla a una celda de 248 px la estrangula —
que es el defecto del modal legacy que hay que evitar sin perder su contenido.

**Tamaño deliberado y fijo:** `min(920, ancho−64) × min(640, alto−96)`. Fijo a
propósito: no cambia entre filas, así el operador puede abrir siete seguidas sin
que la ventana salte.

**Tres bandas, sin anidamiento, un solo dueño de scroll (la banda central).**

**1. Cabecera (fija)**
Miniatura 56 · título completo del proveedor (2 líneas) · código proveedor en
mono · `Línea 4 de 7`. A la derecha, **`X`**. Debajo, una línea silenciosa:
`Tu decisión manda sobre lo que sugiere el sistema.`

**2. Cuerpo (scroll)** — lista de candidatos, **máximo 5**, misma geometría por
fila:
- miniatura 64;
- nombre ERP (1 línea, peso fuerte) · SKU en mono;
- categoría hoja · marca · stock actual;
- **evidencia en palabras, máximo 3 fragmentos**, en orden de fuerza:
  `Mismo modelo D041SB` · `Misma publicación del proveedor` ·
  `Medida 32H coincide` · `La foto es otra pieza`;
- botón `Usar este`.

Selección **explícita y en dos pasos**: el clic en la fila la selecciona
(semántica de radio, estado visible sin depender del color); el primario del pie
confirma. Un clic accidental no vincula nada.

**3. Pie (fijo)**
Izquierda: `Buscar otro producto` — convierte el cuerpo en una búsqueda sobre el
catálogo con el mismo formato de fila (aquí vive «buscar a mano», sin una
segunda pantalla). Derecha: `Ninguno: crear producto nuevo` (terciario),
`Cancelar` y **`Vincular con el elegido`** (primario, deshabilitado hasta que
haya selección).

**Qué NO se muestra, nunca**
- Ningún porcentaje, score ni «confianza 61%». La guía prohíbe un número que
  finge ser una medición, y `overallScore` es exactamente eso.
- La lista cruda de `_buildDuplicateSignals` (mezcla `Stock: N` con evidencia de
  identidad).
- Relleno para llegar a 5. Si hay dos candidatos válidos, se muestran dos.
- Cualquier candidato que haya fallado una compuerta dura. No aparece ni al
  final, ni en gris, ni «por si acaso».

**Estados**
- *Cargando*: 3 filas esqueleto con la geometría real + `Buscando en tu
  catálogo`. Nunca una lista vacía mientras carga.
- *Vacío*: `Ninguno de tus productos calza con esta línea`, tono **neutro**, con
  las dos salidas reales (buscar a mano / crear nuevo) y, si sirve, una sección
  `Parecidos que descarté y por qué` con máximo 2 ejemplos y su razón
  (`es delantera, ésta es trasera`). Eso convierte el fail-closed en una
  respuesta inteligente en vez de un fracaso.
- *Error*: se conserva la cabecera; el cuerpo muestra el `VbNotice` con
  reintento. Un fallo de red nunca se presenta como «no existe».

**Cierre y foco**
`X`, `Esc`, clic fuera y `Cancelar` cierran sin cambiar nada y devuelven el foco
al botón `Revisar` de esa fila. `↑`/`↓` mueven entre candidatos, `Enter` elige,
`⌘/Ctrl+Enter` vincula. Sólo puede haber una instancia abierta; abrirla no
detiene las búsquedas en segundo plano de las demás filas.

En táctil `<900` la misma superficie se presenta a pantalla completa con las tres
bandas intactas y objetivos de 48.

---

## F. Corrección raíz del matcher

### F.1 Un solo analizador de identidad, con gramática

Se reemplazan `_inferProductFamilies`, `_inferProductShapeProfile`,
`extractModelIdentifiers` y `ProductCatalogSemanticResolver._inferFamily` por un
**único dueño puro**, usado idénticamente para la línea de factura y para el
producto del catálogo:

```dart
class PartIdentity {
  final String headFamily;        // exactamente una, del sustantivo núcleo
  final double familyConfidence;
  final String? brandText;        // fabricante explícito, texto — no ProductBrand
  final Set<String> models;       // d041sb, rt56, mt001…
  final Map<String,num> measures; // rotor_mm, holes, old_mm, axle_mm, bcd, clamp_mm, length_mm
  final Map<String,String> standards; // freehub:HG|MicroSpline|XD, valve:presta|schrader,
                                      // brake:6-bolt|centerlock, bb:BSA|BB30|PF30
  final String? position;         // delantera|trasera|izquierda|derecha
  final String? material;
  final String? variant;          // color / medida de la variante del proveedor
  final String compatibilitySegment; // TODO lo demás — nunca identidad
}
```

Dos reglas que producen el resto:

**(a) Segmentar antes de leer.** El título se corta en el primer marcador de
compatibilidad — `para`, `for`, `compatible con`, `apto para`, `works with`, y
los paréntesis/comas que introducen la lista de compatibilidad. Todo lo que va
después alimenta `compatibilitySegment` y queda **excluido** de familia, marca,
modelo y tokens. Sólo con esto desaparecen «Shimano por el IXF» y «cassette por
el buje».

**(b) Gana el núcleo.** La familia sale del **primer** sustantivo de familia del
segmento de identidad, no de cualquier coincidencia. `buje … de Cassette` →
`hub`. `Maza Trasera … para Piñón` → `hub`.

### F.2 Un solo léxico, en chileno, sembrado desde el catálogo real

Hoy hay dos léxicos que se contradicen y a ambos les faltan las palabras que el
catálogo usa de verdad. El léxico nuevo:

- es **uno**, y lo consumen el matcher, el resolver semántico y la búsqueda de
  categorías (por eso escribir `buje` encuentra `Maza`);
- se **siembra desde el árbol de categorías del tenant**, no a mano: cada hoja
  (`Maza`, `Volante`, `Coronas`, `Rotores`, `Tee`, `Espaciadores de Cassette`…)
  declara su familia una vez;
- incluye como mínimo los sinónimos que faltan y que costaron esta revisión:
  `buje↔maza↔hub`, `volante↔bielas↔crankset↔pedivela`, `corona↔plato↔chainring`,
  `tee↔potencia↔stem↔vástago`, `motor↔caja pedalier↔bottom bracket`.

**Y el lado del catálogo deja de derivarse de una cadena.** Un producto tiene
`category_id`: ésa es su familia, con confianza alta. El nombre sólo se analiza
cuando la categoría falta o es genérica. Eso elimina de raíz que
`Espaciadores de Cassette` inyecte la familia `cassette` en un espaciador.

### F.3 Compuertas duras, antes de cualquier score

En este orden, cada una registrando el par de valores que la disparó:

1. **Familia.** `head(probe) == head(candidato)`, o un par explícitamente
   compatible del grafo de familias. Familia desconocida del candidato **no** es
   conflicto por sí sola; el candidato sobrevive sólo con evidencia de identidad
   (modelo, publicación o imagen idéntica). *Hoy desconocida ⇒ descartado, y eso
   es lo que mató al `Volante IXF`.*
2. **Posición/lado**, cuando **ambos** la declaran: delantera vs trasera,
   izquierda vs derecha. Conflicto duro.
3. **Estándar/interfaz**, cuando ambos lo declaran: `HG` vs `MicroSpline` vs
   `XD`, presta vs schrader, 6 pernos vs CenterLock, BSA vs BB30.
4. **Medida discreta**, cuando ambos la declaran: 160 vs 180 mm, 32H vs 36H,
   100×9 vs 135×10, 31.8 vs 35.
5. **Clase física de la imagen** (F.5), cuando existe en ambos.

Tres invariantes:

- Una compuerta **nunca** dispara con evidencia que sólo un lado declara. El
  silencio es «no consta», no «distinto».
- **Un token compartido jamás rescata a un candidato que falló una compuerta.**
  `104BCD`, `compatible con Shimano`, `cassette`, `MTB` son estándares y
  contexto, no identidad.
- **El modelo exacto se evalúa dentro de la etapa de compuertas**, como evidencia
  de identidad, no después. Ésa es la línea concreta (395-403) que hoy descarta
  `AE0063` teniendo `D041SB` impreso.

### F.4 Ranking después de las compuertas: niveles explicables, no un número

```
identidad_exacta   SKU interno igual · misma publicación Y misma variante · imagen idéntica
misma_publicacion  mismo item id del proveedor, variante distinta o desconocida
mismo_modelo       modelo auténtico igual + familia + medidas sin conflicto
candidato_probable familia + ≥2 de {medida, estándar, marca explícita, categoría, imagen parecida}
desconocido        todo lo demás → NO SE OFRECE
```

Sólo los tres primeros pueden presentarse como «es el mismo producto».
`candidato_probable` se presenta como «puede ser» y nunca auto-vincula.
`desconocido` no se muestra: **el top-k es la salida de un filtro, no una cuota**
— hoy `limit: 6` funciona como cuota y por eso se rellena con basura.

Dentro de un nivel, el orden de contribución es: modelo > estándar/medida >
marca explícita > categoría > imagen > texto libre. El texto libre va último, no
primero. Los pesos se normalizan sobre la evidencia que **existe en ambos
lados** (la idea correcta que ya tiene `_combineDuplicateScores` para la imagen,
aplicada a todas las señales).

**Marca faltante ≠ producto inexistente.** La marca tiene tres estados:
`explícita y registrada`, `explícita y no registrada`, `ausente`. Sólo la
primera suma. **La segunda no resta, no descarta, y viaja con el candidato**; la
fila levanta una tarea aparte y no bloqueante: `IXF no está en tu lista de
marcas — crear`. Una marca del segmento de compatibilidad no se convierte nunca
en `brand`.

### F.5 La imagen tiene que aportar semántica, no parecido

Estado actual: la imagen aporta **0.55 del peso** desde un hash 8×8 que el
propio código declara incapaz de distinguir formas. Rediseño:

- En el primer paso la imagen **no aporta un score**. Aporta una **etiqueta de
  clase física y atributos**, calculada una vez y persistida:
  `{clase: buje|espaciador|biela|tee|rotor|adaptador|corona…, forma, interfaces
  visibles (patrón de agujeros, 6 pernos, estrías del núcleo), color dominante,
  nº de piezas en la foto}`.
- **Dónde se calcula:** una llamada de visión **por línea de factura** (7 por
  factura, no por candidato) para la foto del proveedor; y **una vez en la vida**
  por producto del catálogo, persistida junto a `image_fingerprint` en un
  `image_semantics jsonb`. 1.614 productos son un backfill acotado, no un costo
  por factura. Después de eso, «Buscar parecidos» lee la etiqueta de la fila y no
  cuesta nada.
- **Cómo se usa:** la clase física es una **compuerta** (F.3.5). El color/variante
  es desempate **entre variantes de la misma publicación** (WAKE Rojo vs Morado),
  nunca señal primaria.
- La huella actual se conserva **degradada a lo que sí sabe hacer**: detectar que
  es *la misma foto*, que es evidencia de identidad. Se mantiene
  `hasExactImageMatch`; se elimina `imageScore` graduado del ranking.

### F.6 Recuperación: dejar de bajar el catálogo

`getProducts()` sale de este camino. Entra un RPC de recuperación de candidatos
en el servidor, `search_product_candidates(probe)`, que combina:

- similitud vectorial sobre el `embedding` existente (1.593/1.614 poblados);
- búsquedas exactas: SKU interno, `supplier_code`, item id del proveedor,
  identidad canónica de imagen, token de modelo;
- una pasada léxica (trigram / websearch) sobre nombre + modelo + código;

y devuelve **≤ 60 filas** con sólo las columnas que el matcher necesita, ya
filtradas por tenant, activo y no-servicio. Las compuertas y el ranking corren en
Dart sobre 60 filas, no sobre 1.614.

### F.7 Los tres casos, trazados

**Buje trasero Novatec D041SB/D042SB, 32H, HG**

*Hoy:* familia `cassette` (por `de Cassette`) → la compuerta exige `cassette` →
sobreviven `AE0125/AE0124/AE0119 Espaciador de Cassette RISK` (heredan la
familia de su **categoría**) y `1202 Maza Trasera … para Piñón` (por el
`piñón` del segmento de compatibilidad). `AE0063 Maza Delantera Novatec … HG
D041SB` se descarta pese al modelo exacto. Ranking final decidido por un hash de
8×8: negro redondo ≈ negro redondo.

*Con el rediseño:* identidad = `Novatec bujes … D041SB D042SB buje libre de acero
MTB`; compatibilidad = `de Cassette 28/32/36 agujeros HG SX 8-12 velocidades`;
`head=hub`, `models={d041sb,d042sb}`, `position=trasera` (variante `Black rear
32H`), `measures={holes:32}`, `standards={freehub:HG}`. Compuerta 1 deja sólo
`Maza`; compuerta 2 elimina `AE0063` (delantera); compuerta 3 elimina `AE0313
Maza Novatec 32H trasera MicroSpline`. **Resultado honesto: sin coincidencia
fiable → crear nuevo**, con `AE0063` mostrado en el overlay bajo
`Parecidos que descarté y por qué → es delantera`. Ningún espaciador aparece
jamás, en ninguna posición.

**Volante/bielas IXF**

*Hoy:* `AE0093 Volante IXF Integrado Black 170Mm + Motor BSA + Corona 34T` →
`volante` desconocido, `motor bsa` ⇒ familia `bottom_bracket` ⇒ intersección
vacía ⇒ **descartado antes de puntuar**. Sobreviven bielas izquierdas y productos
Shimano, porque `Compatible con SHIMANO/SRAM` entró al bag of words.

*Con el rediseño:* identidad = `IXF-platos y bielas … 104BCD, 170mm, manivela
ancha y estrecha`; compatibilidad = `Compatible con SHIMANO/SRAM`;
`head=crankset`, `brandText=IXF` (explícita, **no registrada**),
`measures={bcd:104, length_mm:170}`. `AE0093` toma su familia de la **categoría
`Volante`**, no del nombre; su columna `brand` dice `IXF`. Pasa las compuertas,
la marca explícita coincide → **`mismo_modelo`, top-1**. Shimano no entra: su
única evidencia estaba en el segmento de compatibilidad. La fila levanta, aparte,
`crear la marca IXF`.

**Los siete productos de esta factura** *(verificado contra producción hoy)*

| Línea | Esperado | Nivel esperado |
|---|---|---|
| WAKE vástago 31,8mm (Red) | `AE0137 Tee Aluminio Wake MTB 31.8MM x 45MM Rojo` | `misma_publicacion` + desempate de variante por color |
| WAKE vástago 31,8mm (Purple) | `AE0138 … Morado` | ídem |
| IXF platos y bielas 104BCD 170mm | `AE0093 Volante IXF Integrado Black 170Mm` | `mismo_modelo` |
| Rotor RT56 160mm | `AE0155 Disco freno Shimano Deore RT56 160MM` | `mismo_modelo` |
| Adaptador Presta→Schrader (10 pcs) | **ninguno** | `sin coincidencia fiable` |
| Novatec buje trasero 32H HG | **ninguno exacto** (`AE0063` es delantera, `AE0313` es MicroSpline) | `sin coincidencia fiable` |
| *(séptima línea, fuera de la captura)* | por confirmar con la factura completa | — |

**Corrección honesta al brief:** busqué el adaptador de válvula en producción
(`category_name ilike '%adaptador%'`, `name ilike '%valvula%|%presta%|%schrader%'`)
y en el catálogo sólo hay válvulas tubeless, tapas de válvula y cámaras. **Ese
producto no existe**, y el buje trasero Novatec HG 32H tampoco existe como
variante exacta. No son fallas del matcher: son los dos casos donde
`sin coincidencia fiable → crear` es la respuesta correcta, y así deben quedar
**afirmados en la prueba**, no tratados como pérdidas.

### F.8 La prueba derivada de producción

`test/unit/product_matcher_invoice_ae160326_test.dart`, hermética:

- **Fixture de entrada:** los 7 títulos reales del proveedor con su variante, su
  código de proveedor y su URL de imagen.
- **Fixture de catálogo:** ~120 filas reales congeladas, elegidas para ser
  adversarias: las 3 `Espaciador de Cassette RISK`, las 20+ `Maza` (incluidas
  `AE0063` delantera Novatec y `AE0313` trasera MicroSpline), las 9 `Corona
  104BCD`, el `60951 104BCD-cubierta protectora`, los 8 rotores Shimano/ZTTO
  (RT10 y RT56), los 5 `Tee Aluminio Wake` de todos los colores, las `Biela
  Izquierda`, y el `AE0093 Volante IXF`. Generadas por un script versionado que
  lee producción en sólo lectura y descarta identificadores de tenant.
- **Aserciones:**
  1. `top1 == sku esperado` en las líneas que tienen contraparte;
  2. `candidates.isEmpty` en el adaptador de válvula y en el buje trasero;
  3. **basura ofrecida = 0**: ningún candidato de una familia distinta a la
     esperada aparece en ningún top-k, en ninguna línea;
  4. las dos variantes WAKE resuelven a `AE0137` y `AE0138` **respectivamente** —
     el diseño actual no puede aprobar esto de forma estable;
  5. todo candidato devuelto trae una lista de evidencia no vacía, y ninguno
     trae una evidencia cuyo único elemento sea texto libre;
  6. ningún candidato descartado por compuerta aparece en la salida.

### F.9 Evaluación permanente

**Dataset:** *positivos* = los pares (línea, producto) que el operador confirmó
en facturas reales; *difíciles* = mismo modelo distinta variante, misma familia
distinta medida/posición/estándar, misma marca distinta familia; *negativos* =
piezas de otra familia que comparten un token (`104BCD`, `cassette`, `MTB`,
`Shimano compatible`) — el conjunto que hoy se cuela.

**Métricas:**
- top-1 y top-3 sobre positivos;
- **tasa de basura ofrecida** = candidatos mostrados que un humano marca como
  absurdos / candidatos mostrados. Es la métrica que importa aquí; el objetivo
  para las clases con compuerta es **0**, no «bajo»;
- latencia p50/p95 por factura y por línea;
- llamadas de IA por factura (objetivo en régimen: 1 de visión por línea, **0**
  por candidato) y costo por factura.

**Evidencia que hay que registrar por decisión** (`match_trace`, compacto, junto
a la línea): los segmentos de identidad y compatibilidad del probe; la evidencia
extraída; **cada compuerta que disparó, con el par de valores concreto**; el
nivel de cada candidato devuelto; y qué hizo finalmente el operador. Sin esto no
se puede depurar «por qué me ofreció esto», y ese último campo es además la señal
que alimenta la memoria de alias.

---

## G. Escritorio, tablet y teléfono

Umbral táctil **900** (`F-06`), no 600: la tablet de 834 es un host táctil.

| Ancho de contenido | Tabla 2 |
|---|---|
| ≥ 1280 | 9 columnas completas |
| 1100–1280 | pasos de compresión 1–2 |
| 900–1100 | pasos 3–4: `Incluir · Línea · Decisión · Ficha · Dinero`. **Sigue siendo tabla y sigue alineada** |
| < 900 (táctil) | composición dedicada, ver abajo |

**Bajo 900 no hay tarjetas arbitrarias ni una tabla en miniatura.** Es una lista
con una **rejilla fija de dos líneas por registro**, que conserva el orden, las
palabras y los comandos de la tabla:

- línea 1: miniatura + título del proveedor (2 líneas) + **estado de la
  decisión** a la derecha;
- línea 2: `Nombre ERP · Categoría · Precio`, cada uno un campo tocable que abre
  **el mismo control canónico** en `O-05` bottom sheet.

La decisión abre el mismo overlay, a pantalla completa. Todos los objetivos a
48 px con área invisible (la caja visual no crece). El pie se vuelve barra fija
con SafeArea; el teclado virtual no tapa el campo enfocado.

La tabla 1 bajo 900: el título mantiene sus 2 líneas y las columnas numéricas se
pliegan en un bloque alineado a la derecha (`cant × costo` arriba, `total`
abajo). La franja de cuadratura se vuelve barra pegajosa. **Nunca scroll
horizontal.**

Se verifica en `599/600`, `899/900` y `1440×900`, en claro y oscuro, con el
overlay abierto y un selector abierto, y con el borrador sucio cruzando el
umbral.

---

## H. Qué se borra, qué se conserva y en qué orden

### Se borra

- `_DesktopReviewTable` completa: `_minimumWidth = 1680`, el
  `SingleChildScrollView` horizontal, los anchos literales por celda y la
  aritmética `rowHeight = 108 + alternativas*44`.
- `_DesktopAlternativeDecision`, `expandedAlternatives`, `onToggleAlternatives`.
- `_SearchableDropdown` local (lo sustituye `S-06`).
- La columna `SKU ERP` y la insignia de estado de la celda origen.
- `_DesktopTextCell`'s `Tooltip` por celda (riesgo de caída registrado; el origen
  pasa a marca persistente).
- En el matcher: `imageScore` como señal graduada, `_combineDuplicateScores`, la
  escalera de once umbrales de `_shouldKeepDuplicateCandidate`, `overallScore`
  en la UI, `_inferProductFamilies`/`_inferProductShapeProfile` y el
  `_inferFamily` del resolver como dueños separados, y el uso de
  `product.categoryName` dentro de `_buildProductSimilarityText` para inferir
  familia.
- `getProducts()` como entrada del matcher, y el umbral mágico `>= 5` de
  `_supplierScopedProducts`.
- El `ConstrainedBox(minWidth: 1280)` de la tabla de la etapa 1.

### Se conserva (APIs e invariantes que sí están bien)

- La frontera `findCandidates(probe, …) → List<ProductDuplicateCandidate>` y la
  forma de `ProductDuplicateProbe`.
- `canonicalImageIdentity` — la normalización de URLs de AliExpress es correcta
  y es evidencia de identidad de primer nivel.
- **La memoria de alias del proveedor** (`resolveSupplierProductAlias`) y el
  hecho de que corra **antes** del matcher. Es lo mejor del flujo actual.
- `_AsyncPermitPool`, el LRU de bytes, la deduplicación de descargas en vuelo y
  `persistComputedImageFingerprints: false` en el camino de lectura.
- Los guardas de concurrencia `_ownsNewProductResolution` / `_ownsBulkReview` y
  el `resolutionRevision`: son corrección real, no ceremonia.
- La postura del `ProductCatalogSemanticResolver`: los valores de IA son pistas y
  nunca prueba; `rejectedBrandHint`; IXF reconocida sin fila de marca. Se
  conserva la postura y se amplía la cobertura de 4 familias al léxico real.
- `ReturnNavigation.close` + `push` para las dos etapas.
- `VbNotice`, `VbStatusBadge`, `VbMoneyText`, `VbSurfaceState`,
  `showVbAnchoredPopover`, `VbShortSelect` como dueños visuales.

### Orden de implementación (cada paso verificable solo)

1. **`PartIdentity` + léxico único**, puro, sin tocar UI.
   *Compuerta:* la prueba de las 7 líneas pasa contra la UI vieja.
2. **`search_product_candidates`** en el servidor; sale `getProducts()`.
   *Compuerta:* mismo top-k que el paso 1 trayendo ≤ 60 filas; p95 registrado.
3. **Compuertas + niveles** reemplazan los scores; `imageScore` degradado.
   *Compuerta:* basura ofrecida = 0 en el fixture; ningún candidato sin
   evidencia que haya pasado compuertas.
4. **`image_semantics`**: backfill del catálogo + compuerta de clase física.
   *Compuerta:* espaciador y buje quedan separados con imágenes reales.
5. **`S-06 VbSearchableSelect`** como dueño canónico, con su regresión
   (geometría, teclado, bottom sheet <900, host con zoom). Consumidores:
   categoría y marca.
6. **Overlay centrado de parecidos** + su regresión. La expansión en línea se
   borra en el mismo commit.
7. **Tabla 2** reconstruida sobre especificación adaptativa de columnas con el
   orden de compresión declarado.
   *Compuerta:* sin scroll horizontal a 1100/1280/1440; altura de fila uniforme;
   goldens en `599/600`, `899/900`, `1440×900`, claro y oscuro.
8. **Tabla 1** reconstruida + franja de cuadratura + switch de IVA reubicado.
9. Registro en `docs/architecture/canonical-ui-surfaces.md` y el aprendizaje
   escrito en la guía que corresponda.

Ningún paso deja la UI a medio migrar: del 1 al 4 la interfaz no cambia; del 5 al
8 el matcher ya está corregido.

---

## I. Criterios de aceptación

Mecánicos, para que no se pueda «arreglar la tabla actual por encima».

1. No existe `SingleChildScrollView(scrollDirection: Axis.horizontal)` ni una
   constante de ancho fijo de tabla en ninguna de las dos etapas. Prueba
   estática sobre los dos archivos.
2. Las filas de la tabla 2 miden **lo mismo** a una densidad dada: una prueba de
   widget mide tres filas en tres estados distintos (`buscando`, `vinculado`,
   `sin coincidencia`) y afirma igualdad.
3. La celda de categoría **nunca** renderiza una cadena que contenga `/`:
   probado con una categoría de 4 niveles.
4. `Revisar` abre una superficie centrada; `expandedAlternatives` ya no existe en
   el archivo; **la altura de la fila no cambia** al abrirla.
5. Sobre el fixture de producción de la factura AE160326: top-1 correcto en toda
   línea con contraparte, resultado vacío en las dos que no la tienen, y **cero**
   candidatos de una familia descartada por compuerta en cualquier línea.
6. Ningún porcentaje, score ni «confianza N%» llega a la UI. Prueba estática.
7. `findCandidates` trae ≤ 60 filas de catálogo por línea: afirmado con un
   repositorio falso que cuenta filas.
8. Llamadas de visión ≤ 1 por línea de factura y **0 por candidato** en régimen:
   afirmado con un doble que cuenta llamadas.
9. Las dos etapas cierran por `ReturnNavigation.close`; cubre el guarda existente
   `test/unit/navigation_return_contract_test.dart`.
10. Claro y oscuro a `1440×900`, `899/900` y `599/600`, con el overlay abierto y
    un selector abierto; sin hex literal en el código nuevo.
11. **Cada valor visual del código nuevo está citado desde `GUÍA GENERAL` con su
    id de componente, o listado como ilegible en el handoff.** Ningún valor
    estimado se despacha.
12. Los rótulos prohibidos no reaparecen y los nuevos son del taller: `Conciliar
    con inventario`, `No encontré ninguno que calce`, `Usar este`,
    `Confirmar 7 líneas`. Nada de «imputar», «matching», «score», «confianza».

---

## Lo que este documento **no** decide

- Los valores visuales concretos (color, radio, sombra, tipografía, ritmo
  vertical). Se leen con `DesignSync` de `GUÍA GENERAL Viñabike - Componentes`
  antes de escribir cada widget. **No usé DesignSync en esta revisión**, así que
  aquí no hay ni un solo valor visual afirmado.
- El modelo de visión concreto y su costo unitario: se decide al implementar el
  paso 4, con la métrica de costo por factura sobre la mesa.
- La séptima línea de la factura AE160326, que queda fuera de la captura y hay
  que confirmar contra el documento completo antes de congelar el fixture.
