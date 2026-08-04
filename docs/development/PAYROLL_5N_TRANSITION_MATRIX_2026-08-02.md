# Nóminas · frame `5n` — matriz de transiciones auténtica (26 filas)

**Recuperada el 2026-08-02.** Este documento existe porque la matriz de cierre
de `5n` **no se puede leer del `spec.json`** ni del `.dc.html`, y cada ronda que
lo intentaba volvía con placeholders o con nada. Aquí queda la fuente que sí
funciona, la causa de las dos que no, y las 26 filas literales.

> **Alcance honesto de la ronda que la recuperó:** esta ronda **recuperó 26/26**.
> **No** las adjudicó contra el código, el backend, la navegación ni el
> responsive, y **no** cerró `5n`. Adjudicar es el trabajo siguiente.

## Proveniencia

| Campo | Valor |
|---|---|
| Proyecto Design | `ERP Bikeshop UI Mockups` · `a0fa3196-6315-4b96-bde7-7cc801e7a74e` |
| Página | `Nóminas - Rediseño.dc.html`, sección `t5` |
| Turno | **5** (frames `5a`–`5n`) |
| Frame | **`5n` · «Matriz de cierre y notas de implementación Flutter»** |
| Artefactos leídos con `DesignSync get_file` | `handoff-t5/spec.json` · `handoff-t5/CHANGELOG.md` · `handoff-t5/frames/5n-p1.png` · `5n-p2.png` · `5n-p3a.png` · `5n-p3b.png` |
| Espejo local | `.tmp/design-mirror/t5/` (no versionado; es cache, no fuente) |

Hashes registrados en `.tmp/design-mirror/t5/MANIFEST.sha256`:

```text
7ed210f0dfff6d8afe9ec52d1e154730a1fbd7f563e15db25d442100067dd540  spec.json
7b622dd393a7715b852c183421576e911caf34d917c067a36bf21061267a527a  5n.json
d93ff450ee194189bd7774c208b8897555d13ae56bf4c1570dbc824329aa971b  nominas-rediseno.dc.html
7a2390bbb8edf4cb1723cf88c3df9a6781e21d7404c6f08a22cd60eb67573b66  frames/5n-p1.png
a867cb80af5f642dc1ba2cf87157fe19eb9b618f97ee9b0a9d0f93079945d8f6  frames/5n-p2.png
d672f262e8089fa7463105f9f80add0784e569e786a837818e045a88d5b154de  frames/5n-p3a.png
```

`5n-p3b.png` se descargó después del manifiesto y **no está en él**; su lectura
sí está incorporada abajo. Al regenerar el manifiesto debe quedar incluido.

## Por qué las dos vías obvias no sirven — causa, no síntoma

**1 · `handoff-t5/spec.json` devuelve placeholders, y no está roto.** El campo
`copy` del frame `5n` transcribe el **DOM del template**, no el resultado
renderizado. Las 26 filas se generan por binding, así que lo que queda grabado
en el spec es literalmente:

```text
"{{ m.frame }}", "{{ m.action }}", "{{ m.next }}", "{{ m.data }}", "{{ m.widget }}"
```

Un cache que traiga eso está **correcto**; simplemente no contiene los datos.
Ningún reintento sobre `spec.json` los va a producir. Esto es coherente con la
corrección del 2026-07-30 del contrato de sync: los `{{ }}` aparecen sólo en el
cableado de la demo interactiva, y ahí no hay valores que leer.

**2 · `Nóminas - Rediseño.dc.html` llega truncado antes de `t5`.** La página
está ordenada **del turno más nuevo al más viejo**. `get_file` corta en el tope
de 256 KiB y devuelve `truncated: true` con 261.119 bytes, dentro de los cuales
sólo caben `t7` y `t6`. Comprobado: los únicos ids presentes son `6a`–`6f`,
`7a`–`7g`, `t6` y `t7`. **No hay ni un `id="5*"`.** Grepear ese archivo por `5n`
da falso vacío, no ausencia real.

**3 · La vía que sí sirve es la canónica.** El turno publica cada frame como PNG
propio bajo `handoff-t5/frames/`, que es exactamente lo que el contrato manda
publicar para no depender del `.dc.html`. Los cuatro PNG de `5n` bajan enteros
(`truncated: false`, ≤136 KB, bajo el tope) y traen las 26 filas renderizadas.
El propio encabezado del frame las cuenta:

> `MATRIZ DE TRANSICIONES · 26 FILAS · NINGUNA ACCIÓN SIN DESTINO`

Reparto por banda (cinco bandas con 20 px de solape): **11 filas en `p1`**,
**14 nuevas en `p2`** (la fila 11 se repite por el solape), **1 en `p3a`**.

Leer texto de comportamiento de un frame publicado **no es** leer un valor
visual de una captura. La prohibición del contrato es sobre color, radio,
sombra, borde, espaciado, tipografía y altura; esta matriz es contrato de
navegación y datos.

## Las 26 filas

| # | FRAME | ACCIÓN | SIGUIENTE ESTADO | DATO REQUERIDO | WIDGET / OVERLAY |
|---|---|---|---|---|---|
| 1 | A · Cola | clic en tarjeta de semana | semana seleccionada · tabla recarga | `weekId` | inline · sin overlay |
| 2 | A · Fila | clic en caret ▸ | disclosure abierta (1 a la vez) | `personId` | inline expansion |
| 3 | A · Fila pagada | clic en chip Pagado | detalle de pago + evidencia | `paymentId` | Popover 380 (desktop) · Sheet (táctil) |
| 4 | A · Fila sin método | clic en Sin método ▾ | menú: Transferencia / Efectivo / Configurar | `personId` | PopupMenu 232 |
| 5 | A · Fila transferencia | clic en Registrar pago | composer abierto con monto sugerido | `personId, weekId, sugerido` | Panel derecho 540 · Sheet full en 390 |
| 6 | A · Fila efectivo | clic en Confirmar efectivo | sheet de efectivo | `personId, weekId, monto, anticipos` | Sheet 480 · Sheet full en 390 |
| 7 | A · Barra | clic en Confirmar Sxx | diálogo de confirmación de semana | `weekId, saldo=0` | Dialog 520 |
| 8 | A · Barra bloqueada | hover en CTA inerte | tooltip con la razón | — | Tooltip |
| 9 | B · Composer | elegir Completo / Diferencia / Parcial | monto y nota de tolerancia recalculan | `monto` | inline segmented |
| 10 | B · Composer | adjuntar comprobante | evidencia en cola de subida | `file (≤10 MB)` | FilePicker + thumb 56 |
| 11 | B · Composer | guardar | fila Pagado / Parcial · semana recalcula · toast | `monto, fecha, referencia` | Toast 4 s con Deshacer |
| 12 | C · Efectivo | aplicar anticipo | monto a entregar baja | `advanceIds` | inline checkbox 48 |
| 13 | C · Efectivo | confirmar entrega | fila Pagado (efectivo) · saldo recalcula | `monto, fecha, entregadoPor` | Toast + Deshacer |
| 14 | D · Método | elegir Transferencia | campos banco/cuenta requeridos | `banco, tipo, número, RUT` | Dialog 460 |
| 15 | D · Método | guardar | vuelve a la acción original (composer abierto) | `methodId` | retorno con foco restaurado |
| 16 | E · Anticipo | crear desde persona o semana | anticipo vigente · aplicable | `monto, fecha, motivo` | Dialog 460 |
| 17 | E · Semana corta | liquidar hasta miércoles | semana parcial cerrada para esa persona | `fechaCorte` | Dialog 460 + aviso |
| 18 | F · Historial | clic en semana | detalle a la derecha | `weekId` | master-detail |
| 19 | F · Historial | clic en Ver pago | detalle + evidencia + reversar | `paymentId` | Popover / Sheet |
| 20 | G · OCR 1 | subir PDF / imagen / cámara | extracción en curso | `file` | DropZone + progreso |
| 21 | G · OCR 2 | extracción termina | lista de movimientos con confianza | — | inline |
| 22 | G · OCR 3 | corregir persona / semana / monto | match reescrito · confianza a 100% manual | `personId, weekId, monto` | inline editable |
| 23 | G · OCR 3 | excluir movimiento | fuera del impacto (recuperable) | `txId` | inline · deshacer |
| 24 | G · OCR 4 | aplicar | N pagos escritos · idempotente por hash | `txHash[]` | Dialog resumen + Toast |
| 25 | H · Conflicto | otro usuario pagó la misma fila | banner: recargar fila o forzar | `version` | Banner inline + Dialog |
| 26 | H · Offline | guardar sin red | en cola local · se reintenta | `draft` | Banner persistente |

## Notas Flutter del mismo frame (`5n-p3a` / `5n-p3b`), literales

Estas sí estaban legibles en `spec.json` (`annotations` no usa binding) y se
confirmaron contra el PNG. Se transcriben porque **contienen números con dueño**
que la adjudicación va a necesitar.

**Estructura**

- *Una superficie, un archivo:* `payroll_queue_surface.dart` (5a/5b/5m/5l-1) ·
  `payroll_payment_composer.dart` (5e + landscape) · `payroll_cash_sheet.dart`
  (5f) · `payroll_method_dialog.dart` (5g) · `payroll_advances_surface.dart`
  (5h) · `payroll_history_surface.dart` (5i) ·
  `payroll_reconciliation_flow.dart` (5j).
- *El control de decisión es UN widget:*
  `PayrollDecisionCell({kind, label, meta, onTap, enabled, disabledReason})` con
  `enum DecisionKind {paid, transfer, cash, noMethod, locked}`.
  **Alto 28 desktop / 44 táctil, `maxWidth 186/168/200`,
  `TextOverflow.ellipsis`, `softWrap:false`.** Prohibido componer chip + botón
  en la misma celda.
- *Layout por ancho lógico*, con `LayoutBuilder` **en la superficie, no en la
  fila**: **≥1200 tabla de 8 columnas · 1000–1199 seis columnas · 900–999 cinco
  · <900 cuatro con fila de 60 · <600 tarjetas**. El breakpoint **recompone,
  nunca desmonta**: la fila abierta, el borrador y el paso del OCR sobreviven.
- *Números:* `NumberFormat.currency(locale:'es_CL', symbol:'$', decimalDigits:0)`
  y `fontFeatures:[FontFeature.tabularFigures()]` en toda cifra.
- *Teclado y foco:* `FocusTraversalGroup` por fila; `Shortcuts` ↑↓ mueve, →
  abre disclosure, ← cierra, ↵ ejecuta la decisión, Esc cierra panel/menú. El
  anillo de foco es **`FocusRing 3px` por fuera del borde, no un `Border` nuevo**
  (no debe mover layout).

**Datos y escritura**

- *El total lo calcula el servidor, no la vista:*
  `WeekLiquidation{total, advances, toPay, paid, balance, excludedPeople[]}`. La
  UI nunca suma horas × tarifa. Las personas sin horas cerradas llegan en
  `excludedPeople`, **fuera de `total`**.
- *Concurrencia optimista:* todo `POST` lleva `weekVersion`; un 409 devuelve el
  estado nuevo y pinta el banner de `5d` en vez de reventar. `Confirmar semana`
  exige versión fresca y está deshabilitado offline.
- *Idempotencia del OCR:* clave por movimiento
  `sha1(personId|weekId|date|amount|normalizedGloss)` + huella del archivo. El
  paso 4 manda la lista completa; el servidor responde
  `{created, alreadyApplied}`. **Una sola transacción.**
- *Borradores locales:* el composer persiste `PaymentDraft` por
  `(personId, weekId)` con monto, fecha, referencia y ruta del adjunto.
  **Sobrevive al cierre del panel, al cruce de breakpoint y a la caída de red;**
  se descarta al registrar o al deshacer.
- *Permisos declarados en un punto:*
  `PayrollAbility{canView, canPay, canConfirm, canReverse, canEditMethod, canCreateAdvance}`.
  La celda de decisión recibe `enabled` y `disabledReason`: **se inhabilita con
  motivo, jamás se oculta.**

## Lo que la matriz cambia respecto de la auditoría vigente

Dos de las seis «decisiones» que la auditoría independiente marcó vienen del
bloque **«DECISIONES DE LÓGICA QUE DEBES APROBAR O CORREGIR»** del mismo frame,
que es **la propuesta del diseñador**, no la matriz de cierre. La matriz dice
otra cosa en dos puntos y hay que releerlos contra ella antes de fallar:

- Fila 22 dice literalmente **«match reescrito · confianza a 100% manual»** —
  no menciona los umbrales 90/70.
- Fila 4 nombra el menú **«Transferencia / Efectivo / Configurar»** — sin la
  frase «sólo por esta semana».

Esto **no resuelve** las seis adjudicaciones; sólo advierte que dos de ellas se
estaban evaluando contra el texto equivocado del frame.

## Defecto de documentación detectado al recuperarla

`DESIGN_HANDOFF_SYNC_CONTRACT.md` §«What Code does» manda correr
`scripts/dev/design_mirror.sh manifest t<N>` y `diff t<N>`. **Ese script no
existe** en `scripts/dev/`. El contrato prescribe una herramienta ausente, así
que el manifiesto de esta ronda se escribió a mano con `shasum -a 256`.
Corregir el contrato (o crear el script) queda pendiente para la ronda
siguiente; se registra aquí para que no se vuelva a descubrir desde cero.

---

# Adjudicación de las 26 filas (2026-08-02, tercera ronda)

**Cómo leer esta tabla.** `CUMPLE` = existe y se comprobó en esta ronda.
`PARCIAL` = existe pero le falta una parte declarada por `5n`. `FALLA` = existe
y contradice a `5n`. `NO SOPORTADO` = el dominio o el backend de hoy no lo
permiten, y **no se fabrica**.

**Fuente de esta actualización.** Se releyeron los owners concretos de cada
overlay, el canvas posterior `7d`, el contrato de evidencia/reversa y sus
regresiones. `7d` reemplaza la medida antigua de `5n` cuando ambos difieren;
el resto se adjudica contra dominio y backend, no por semejanza visual.

| # | Fila | Veredicto | Evidencia / decisión de producto |
|---|---|---|---|
| 1 | Cola · clic semana | CUMPLE | `payroll_queue_surface.dart` · tarjeta de semana; test `week card is one semantic InkWell action`. |
| 2 | Fila · caret → disclosure 1 a la vez | CUMPLE | `payroll_redesign_page.dart:323` `String? _expandedLineId` es **un solo** id; `:2288` alterna a `null`. Regresión nueva: `5n · la fila abierta sobrevive al cruce de breakpoint`. |
| 3 | Fila pagada · chip → detalle+evidencia | **CUMPLE ADAPTADO** | El chip abre `PayrollPaymentEvidenceSurface` en el panel auditado canónico de **520** (`payroll_redesign_page.dart`, `desktopWidth: 520`) y como sheet táctil. Los 380 de `5n` ya no alcanzan para original, reversa, asiento, cartola, actor y motivo; volver a un popover anclado además reintroduciría la familia de `OverlayPortal` que ya falló al recomponer la tabla. Se conserva la intención —respaldo contextual— con el tamaño que exige la evidencia real. |
| 4 | Fila sin método · menú 3 opciones | **CUMPLE ADAPTADO** | El `MenuAnchor` conserva el caret y abre una sola acción, `Configurar método`, que lleva a la hoja canónica donde se elige **Transferencia o Efectivo** y se validan los campos reales. Duplicar esas opciones en un popup de 232 crearía un segundo owner de reglas de método. **Corrección vigente:** la matriz no dice «sólo por esta semana». |
| 5 | Fila transferencia · composer | **CUMPLE** | El Design posterior `7d` reemplaza los 540 antiguos: declara **sheet 560** y contenido 522. El owner usa `desktopWidth: 560`; en teléfono la superficie adaptativa es full sheet. |
| 6 | Fila efectivo · sheet 480 | **CUMPLE** | `7d` declara **sheet 480** y contenido 442; el owner usa `desktopWidth: 480` y full sheet táctil. |
| 7 | Barra · Confirmar Sxx → Dialog 520 | CUMPLE | `payroll_redesign_page.dart:2452` `desktopWidth: 520` y `:3536` `maxWidth: 520`; test `semana confirmada nunca ofrece un segundo cierre manual`. |
| 8 | Barra bloqueada · tooltip razón | **CUMPLE ADAPTADO** | El motivo se expone de forma visible y por semántica. **El Tooltip como mecanismo queda expresamente rechazado**: un tooltip por fila con `LayoutBuilder` ya tumbó el módulo al redimensionar. `disabledReason` y la franja canónica conservan la intención informativa sin reintroducir el fallo de runtime. |
| 9 | Composer · Completo/Diferencia/Parcial | **CUMPLE ADAPTADO** | No son tres modos elegibles: son indicadores derivados del único monto editable. `payroll_composer_amount_cases_test.dart` prueba Completo y Parcial, que ningún chip gane gesto, y que el sobrepago muestre una instrucción honesta en vez de prometer una escritura que el host bloquea. Crear un modo registrable de “Diferencia” requeriría un contrato financiero nuevo y se descarta. |
| 10 | Composer · adjuntar (≤10 MB) | **NO SOPORTADO / DESCARTADO** | El pago manual no tiene owner de archivo ni FK de evidencia; el composer conserva referencia y la conciliación conserva cartola, fila, fecha, monto y hash. Los anticipos sí tienen comprobante inmutable bajo su propio contrato de 12 MiB. No se agrega un picker que aparente persistencia ni se cuelga un archivo al owner equivocado; incorporar comprobante manual de pago exige primero un contrato backend propio. |
| 11 | Composer · guardar → toast 4 s con Deshacer | **CUMPLE ADAPTADO** | El pago actualiza fila y semana, pero el `Deshacer` efímero se reemplaza por **Corregir pago** persistente en su evidencia. Exige motivo, actor, versión y operación idempotente; agrega compensación exacta y asiento balanceado ligado al original, sin borrar evidencia. Es una corrección financiera formal, no una carrera de cuatro segundos. |
| 12 | Efectivo · aplicar anticipo (checkbox 48) | **CUMPLE** | El control mide `PayrollTokens.touchMobile` = 48, expone `Semantics.checked`, muestra marcado/desmarcado y el segundo toque restaura el monto. `payroll_cash_advance_toggle_test.dart` prueba además `min(anticipo disponible, saldo)`: la entrega nunca queda negativa y no pulsa Confirmar. |
| 13 | Efectivo · confirmar entrega + Deshacer | **CUMPLE ADAPTADO** | La entrega cumple y la misma acción persistente **Corregir pago** revierte formalmente el efectivo con motivo, linaje y asiento inverso. No se ofrece un undo temporal que pueda perderse al cerrar la vista. |
| 14 | Método · Transferencia → banco/tipo/número/RUT | **CUMPLE ADAPTADO** | El contrato real exige banco+número; el tipo permite legalmente “Sin especificar”. RUT/titular se descarta porque `employees` no tiene owner para guardarlo y los nombres alternativos ya pertenecen a `payroll_beneficiary_aliases`. Cinco casos en `payroll_method_required_fields_test.dart` prueban bloqueo, draft, efectivo y ausencia deliberada del campo inventado. |
| 15 | Método · guardar → vuelve con foco restaurado | **CUMPLE** | Tras guardar se recarga por ids y se abre el composer de la misma persona. Al cerrar el flujo, `_StatusActionMenu` restaura el foco al control estable de origen; regresión `5n: al cerrar configuración de método el foco vuelve al control de origen`. |
| 16 | Anticipo · crear desde persona o semana | **CUMPLE** | La entrada por persona ya estaba cubierta en `payroll_advances_ux_test.dart`; `payroll_advance_entry_points_test.dart` agrega la pata faltante y prueba que “Nuevo anticipo” vive en la fila abierta y conserva la identidad de esa persona, sin escribir. |
| 17 | Semana corta · liquidar hasta miércoles | **CUMPLE ADAPTADO** | El backend confirma la semana completa y no posee una liquidación parcial por persona; inventar `fechaCorte` en Nóminas produciría una obligación distinta de la fuente. El término anticipado se registra estructuradamente y la UI lleva a **Asistencias** para cerrar horas; luego Nóminas liquida la obligación real de esa semana. El panel operable de `5h` se descarta, pero el caso de negocio sí queda resuelto. |
| 18 | Historial · clic semana → detalle derecha | **CUMPLE** | `payroll_redesign_surface_test.dart` ya ejercitaba selección e hidratación; la regresión ahora se ancla al ledger derecho y exige que desaparezcan las cifras de la semana anterior y aparezcan las de la nueva. Esto evita un falso verde producido sólo por el chip de la lista. |
| 19 | Historial · Ver pago → detalle+evidencia+**reversar** | **CUMPLE** | El historial hidrata original, asiento, cartola y linaje; cuando la capability v2 y la autorización contable están activas expone **Corregir pago/anticipo**. La RPC agrega una única reversa exacta, recalcula proyecciones y devuelve recibo idempotente; originales y reversas quedan visibles newest-first. |
| 20 | OCR 1 · subir → extracción | CUMPLE | Ejercitado en la app real (producción, claro, 1360/834/430) sin escribir. |
| 21 | OCR 2 · lista con confianza | CUMPLE | Ejercitado en la app real; las 10 preguntas se resolvieron sin aplicar. |
| 22 | OCR 3 · corregir → **confianza a 100% manual** | **CUMPLE ADAPTADO** | **Corrige la auditoría:** la fila **no** pide los umbrales 90/70; pide que una corrección humana lleve la confianza a 100 %. **La traducción es deliberada y se registra:** la app modela `manualCertainty` y **no muestra un 100 % numérico**; muestra `TÚ LO DECIDISTE`. Es la regla «nunca un número que finge ser una medición» de la guía: un 100 % afirmaría una precisión que nadie midió, cuando el hecho es que lo decidió una persona. Misma semántica, palabra correcta. El fallo previo «90/70» queda **retirado**: se evaluaba contra el bloque de propuestas, no contra la matriz. |
| 23 | OCR 3 · excluir movimiento (recuperable) | CUMPLE | Excluir no escribe y es reversible antes del paso 4; ejercitado en la app real. |
| 24 | OCR 4 · aplicar idempotente por hash | **CUMPLE** | El código usa SHA-256 + operation key, versiones esperadas y una sola transacción, más fuerte que el `sha1(...)` propuesto. Las cuatro migraciones pendientes quedaron instaladas con write → read-back → historial, el gate derivado de producción pasó **161/161**, y `veryfi-ocr` quedó activo en producción como versión **107**. Un smoke autenticado con la cartola real devolvió **14 movimientos estructurados** desde el endpoint de cartolas —7 cargos, 7 abonos, saldo en 14— sin pulsar `Aplicar`. Los PDF digitales permanecen locales; imágenes y escaneos reutilizan el proxy Veryfi y la ERP no persiste archivo ni OCR completo. |
| 25 | Conflicto · banner recargar **o forzar** | **CUMPLE ADAPTADO** | Los comandos monetarios, la conciliación y la reversa llevan operation key y versión esperada; un conflicto levanta la valla stale y ofrece **Recargar**. **`Forzar` se rechaza expresamente:** sobrescribir el pago de otro usuario es pérdida de integridad financiera, no una opción válida de UI. La adaptación conserva la resolución segura y descarta la rama peligrosa del frame. |
| 26 | Offline · guardar sin red → cola local | NO SOPORTADO | No existe cola offline ni reintento. **Se rechaza fabricarla:** una cola local de escrituras financieras sin backend idempotente por operación produce pagos duplicados. Un banner que prometa reintento sería una mentira operativa. |

## Déficits: implementados y probados

El bloqueo de la ronda anterior —«el eje de la escalera no es el ancho lógico»—
**está resuelto**. La causa son **dos descuentos acumulados**, no uno: entre el
ancho exterior y la tabla se pierden el **padding lateral de la superficie
(32 px, 36 según el tier)** y además los **2 px del `Border`** de la tarjeta.
Decir «eran sólo 2 px» fue una simplificación equivocada de la ronda anterior y
queda corregida acá: con ambos descuentos, un viewport de 1200 nunca llegaba a
1200 en el punto donde se decidía el tramo.

1. **El owner del tramo subió al `LayoutBuilder` exterior de
   `PayrollQueueSurface`**, tal como `5n` lo pide («`LayoutBuilder` en la
   superficie, no en la fila»). `_QueueGridLayout.resolve` ahora recibe **dos**
   anchos y la distinción es el arreglo: `logicalWidth` decide el tramo,
   `width` (interior, ya sin padding ni borde) reparte columnas. Usar uno solo
   para las dos cosas producía, según cuál se eligiera, un tramo corrido
   decenas de píxeles o un overflow de dos.
2. **Un solo owner canónico del tier.** `payrollQueueEightColMin = 1200` y
   `payrollQueueSixColMin = 1000` viven en la superficie, y el host dejó de
   tener su propio `< 1240`: `payroll_redesign_page.dart` pregunta por
   `payrollQueueDenseHint(...)`. Dos dueños se contradecían justo en el borde.
3. **`maxWidth 186/168/200` alcanza las CUATRO formas** —directa, pagada, menú
   y pasiva—, porque el tope lo resuelve el layout una vez
   (`_QueueGridLayout.decisionMaxWidth`) y viaja; antes cada forma lo deducía
   de `tablet`, que es lo que dejó el compacto de escritorio en 186 y el táctil
   sin tope alguno (crecía hasta los 280 de la regla de columna).
4. **El cruce recompone y no desmonta**: la fila abierta conserva su detalle y
   su única decisión en 1400 → 1100 → 834 → 1400.

### Verificación viva en la app real (2026-08-02)

Las pruebas de widget fijan la geometría; esto fija que el módulo **real** se
comporta así. Ejecutado por el dueño sobre la sesión canónica `screen payroll`
/ app `89180`, en **producción y oscuro**, con reload de **38/5159 librerías en
2,811 s** y **sin abrir una segunda sesión**.

| Ancho | Qué se observó | Captura |
|---|---|---|
| 1250×768 | banda ancha, **8 columnas** | `08-5n-wide-live.png` |
| 1200×768 | tramo compacto, **6 columnas** | `09-5n-compact-live.png` |
| 834×768 | **4 columnas** y CTA apilado | `10-5n-tablet-live.png` |

Y el punto que ninguna prueba de widget puede dar por sí sola: en 834 se abrió
por semántica **«Mostrar detalle de Fernando José Tapia Carrillo»**, se
confirmaron *Horas cerradas*, *Tarifa* y *Abrir en Asistencias*, se redimensionó
a **1250** y el control seguía diciendo **«Ocultar detalle…»**. El estado vivo
sobrevivió al cambio de banda en la app real, no sólo en el harness.

Después se cerró el detalle y se restauró **1360×800, oscuro, pantalla Semanas,
sin borrador OCR**. No se pulsó *Confirmar semana* ni *Aplicar*.

Las capturas viven bajo `Screenshots vinabikeProject/payroll-closure-2026-08-02/`,
directorio **ignorado por `.gitignore:110`**: no cuentan como árbol sucio.

### Regresiones que muerden

| Prueba | Qué falla si se rompe |
|---|---|
| `5n · la escalera cambia en 1200 y en 1000 exactos` | Bordes 1199/1200 y 999/1000 desde la superficie real. Si el eje vuelve al interior de la tarjeta, los dos descuentos —padding lateral de la superficie (32/36 según el tier) **y** los 2 px del `Border`— corren el tramo y falla. |
| `5n · el tope 186/168/200 se alcanza en las cuatro formas` | Mide directa, pagada, menú **y pasiva** con rótulos deliberadamente largos y **aserto de igualdad**, con los topes escritos como **literales**. Verificado por mutación el 2026-08-02: con `decisionCellMaxWidthDense = 186` falla (`Expected: <168.0> Actual: <186.0>`) y al revertir vuelve a verde. Con rótulos cortos y `<=` —como estaba— la implementación vieja de 186 también pasaba, y comparar contra la constante era una tautología. |
| `5n · el ESTADO DE TRABAJO sobrevive al cambio de banda (la fila abierta sigue abierta)` — en `payroll_redesign_surface_test.dart:3376` | **Ésta es la prueba real de supervivencia**, y ya existía: abre la fila tocando el caret y luego redimensiona 1440→834 sobre el MISMO State padre. La que había escrito en la suite adaptativa precargaba `expanded: true` en cada pump, así que no probaba supervivencia de estado: fue **eliminada**. |
| `5m · a 834 la fila mide 60 y el control de decisión 44 × 200` | Ahora exige **200 exactos**. Decía `greaterThanOrEqualTo(200)` y por eso pasaba con 280. |
| `payroll_composer_amount_cases_test.dart` · 3 casos | Prueba que Completo/Parcial nacen del monto, que la tira es sólo lectura y que un sobrepago nunca promete una escritura imposible. |
| `payroll_cash_advance_toggle_test.dart` · 3 casos | Fija 48 px, estado accesible reversible y tope del anticipo al saldo pendiente. |
| `payroll_method_required_fields_test.dart` · 5 casos | Fija el contrato auténtico banco+número, tipo opcional y ausencia de RUT sin owner. |
| `payroll_advance_entry_points_test.dart` | Fija la entrada desde una fila semanal con la identidad correcta; la entrada por persona conserva su prueba preexistente. |
| `historial pagado/anulado hidrata lazy, ordena newest-first y es lectura` | Se ancla al ledger derecho para demostrar cambio real de detalle, no sólo selección en la lista. |

## Rechazado expresamente, con motivo

- **`Deshacer` financiero de cuatro segundos** (filas 11 y 13) — reemplazado
  por corrección/reversa transaccional, persistente y auditada.
- **Adjunto de pago manual sin owner backend** (fila 10) — no se aparenta una
  persistencia; la evidencia de anticipo y la cartola conservan sus owners.
- **Forzar sobre conflicto** (fila 25) — pérdida de integridad.
- **Cola offline** (fila 26) — duplicaría pagos.
- **`Tooltip` como portador del motivo** (fila 8) — regresión ya demostrada con
  `LayoutBuilder` en tabla.
- **`PayrollAbility`** — la autorización real es binaria
  (`canAccessAccounting`). No se fabrica una UI de permisos que no existen.

---

## FREEZE · auditoría final del módulo (2026-08-02, tras `61cbf978`)

**No se encontró ningún defecto reproducible.** Esta ronda no reimplementó
nada: verificó. Lo que sigue es la evidencia ejecutada, no el relato.

### Verificación automática

| Compuerta | Resultado |
|---|---|
| Batería completa de Nóminas (`test/unit/payroll_*` + `test/widgets/payroll_*` + `test/widgets/vb_*`) | **587 pasadas · 2 opt-in saltadas · 0 fallidas** (`All tests passed!`) |
| Analyzer de `lib/modules/hr/payroll/`, `lib/modules/hr/widgets/` y `payroll_reconciliation_page.dart` | **0 errores · 1 `info`** (ver residual) |

### Smoke real contra producción, sólo lectura

Sesión canónica **existente** `43256.payroll` / app `45814` (la anterior murió
con el apagado del Mac; **no se abrió una segunda**). Nada se escribió: no se
pulsó `Confirmar semana`, ni `Aplicar`, ni `Registrar corrección`.

| Superficie | Comprobado |
|---|---|
| Semanas | escritorio 1631, tablet 834, teléfono 430 · oscuro. Cuatro registros reales, barra de dinero y valla de borrador |
| Historial | maestro-detalle a 1631 (oscuro y **claro**) y lista-primero a 430; el detalle derecho cambia de verdad al elegir otra semana |
| Anticipos | ledger de la persona con `VIGENTE`/`APLICADO`, explicador de 4 reglas y salida `Nuevo para esta persona` |
| Evidencia de pago | 1631 y 430, **oscuro y claro**: banda de dinero, movimientos, `ASIENTO CONTABLE` con debe/haber y folio |
| Corregir pago | diálogo abierto y **cancelado**; dice que el original no se borra, que la reversa lleva asiento inverso y que el saldo se reabre |
| OCR / conciliación | paso 1 con los cuatro pasos, copy de Veryfi, tope de 12 MB y `Continuar` deshabilitado |

**Comprobado en vivo, no por contrato:** el CTA apilado de la barra de dinero
mide **802 × 48** a 834 — el `touchMobile` que `F-06` exigió sobre el 46 del
frame—, y el tramo de tarjetas/tabla cruza en `720` como manda `_isTabletBand`
(667 → tarjetas, 834 → tabla densa de cuatro columnas).

### Dos hallazgos que NO eran defectos, anotados para que no se re-abran

1. **Ancho del panel de respaldo.** Medía ~416 px en la captura contra
   `desktopWidth: 520`. **Conforme:** la sesión corre con `appliedScale 0.8`,
   así que 520 lógicos son 416 físicos. No se compensa localmente y el owner
   queda intacto. La causa del error de lectura está en el workflow §5.c.
2. **`Motivo obligatorio` con el botón habilitado.** No es una valla ausente:
   `submit()` exige ≥ 3 caracteres y pinta `errorText` sin cerrar el diálogo.
   Botón habilitado + error en línea dice **por qué** no se puede; un botón
   muerto no.

### Residual externo exacto

Nada de esto es de Nóminas y nada bloquea el módulo:

- `employee_advance_dialog.dart:37` — 1 `info` de analyzer: la clase
  `@deprecated` se referencia a sí misma. Es la ruta legacy v2 **sin
  consumidores** ya marcada para retiro junto a `payroll_list_page.dart` y
  `payroll_payment_dialog.dart`. Borrarla es una decisión de limpieza, no una
  corrección: se deja al dueño del retiro.
- **iOS · la barra de estado estaba OCULTA y ya está CORREGIDA (2026-08-03).**
  `ios/Runner/Info.plist` declaraba `UIStatusBarHidden = true`, así que en
  iPhone no existía la banda de **47** que `6a` compone dentro del header
  (`47 + 56 + 48 = 151`) y el operador no veía reloj, wifi ni batería. **No se
  aceptó «no existe el inset» como cierre:** se corrigió el dueño nativo.
  `UIStatusBarHidden` pasa a `false`, y `UIViewControllerBasedStatusBarAppearance`
  a `true` para que **el contraste lo pida cada pantalla** —esta app tiene
  pantallas claras y un header navy, y ningún estilo global sirve para las dos—.
  Sin compensaciones locales. Fijado por
  `test/unit/ios_status_bar_contract_test.dart` (**3 casos**, verificado por
  mutación: al volver a `true` la suite se pone roja).
- **iOS · contraste, corregido en el mismo owner canónico.** Al dejar de
  ocultarse, el login quedó con contenido **claro sobre fondo claro** —la hora
  casi ilegible—, porque esa pantalla vive fuera del `WorkspaceShellScope`, que
  es quien declara el estilo dentro de la app. Se le puso un `AnnotatedRegion`
  con **`vinabikeSystemOverlayStyleFor`**, el helper que ya existía y que deriva
  el brillo del color que la pantalla realmente pinta arriba. Evidencia real, en
  un iPhone 17 Pro del simulador con `simctl status_bar override --time 9:41`:
  `ios-07` (barra ausente) → `ios-09` (visible, claro sobre claro, ilegible) →
  `ios-10` (visible, **oscuro sobre claro, legible**). Inset superior consumido
  **una sola vez**: el contenido arranca bajo la isla, sin solape ni recorte.
- **Escrituras de producción** que ninguna sesión de agente puede ejercer:
  `Confirmar semana`, `Aplicar` del paso 4 y `Registrar corrección`. Sus
  contratos están probados en código y en pgTAP; su ejecución real es del dueño.

**Con eso el módulo queda CONGELADO.** Reabrirlo pide un defecto reproducible
citado con su comando y su salida, no una impresión.

---

## iOS desbloqueado: lo que costaba la ronda y no era de Nóminas (2026-08-03)

Con el permiso de Simulador otorgado, el residual iOS dejó de ser una incógnita.
Se compiló, instaló, lanzó y condujo la app en un **iPhone 17 Pro real del
simulador (402×874 puntos)**. Tres cosas salieron a la luz, y ninguna se sabía:

**1. El dispositivo que el proyecto designaba no puede mostrar nada en este
Mac.** `Vinabike iPhone 17 Pro x86` es un dispositivo **forzado a x86** y en un
M1 Pro arranca sin *display port*: `simctl io … screenshot` responde
`Device does not have a 'default' display port` y el panel falla con
`Could not find the Main Screen Surface`. **Ésa era la causa real** del
«toolchain bloqueado» de rondas anteriores — no faltaba la plataforma iOS.
Un dispositivo de stock captura sin problema, así que la verificación se hizo en
uno creado al efecto (`Claude iPhone 17 Pro`), que **se deja instalado** justo
para que nadie vuelva a diagnosticar esto desde cero. El binario, además, es
**x86_64 puro** (`lipo -archs` → `x86_64`), así que corre bajo Rosetta y el
primer arranque es lento de verdad.

**2. Defecto P1 encontrado y CORREGIDO: arranque en frío sin sesión se colgaba
en «Cargando…» para siempre.** Reproducido en un simulador limpio con red
comprobada (`curl` a Supabase, **200 en 0,66 s**): proceso vivo, spinner
girando, **6+ minutos**, y la pantalla de login **nunca** aparecía. La causa no
era lentitud: `gotrue` abre la suscripción con `AuthChangeEvent.initialSession`,
que **no** está en la lista de eventos «significativos» del listener; la bandera
`isInitializing` se apagaba **sin notificar**, el árbol no se reconstruía y
`main.dart` sigue pintando «Cargando…» mientras esa bandera esté arriba. En
escritorio no se veía porque ahí ya hay sesión y la bandera se apaga antes del
primer build. **Afecta también a release** (`kDebugMode` sólo controla el
auto-login, no el filtro).

*Corrección:* terminar de inicializar ahora **avisa**, sin reabrir lo que el
filtro protegía —`tokenRefreshed` sigue sin reconstruir, que es lo que salvaba
los formularios a medio llenar—. La regla vive en
`AuthService.shouldNotifyAuthListeners` para que se pueda probar sin Supabase, y
la fija `test/unit/auth_initialization_notify_contract_test.dart` (**6 casos**,
las dos mitades). **Demostrado en vivo**, no sólo en prueba: misma build, mismo
simulador, antes «Cargando…» y después la pantalla de login.

**3. El `47` de `5l` diverge por configuración de iOS**, con archivo y línea —
ver el residual de arriba. Entregado a Codex, no corregido acá.

**Estado del simulador al cerrar:** override de barra de estado limpiado, app
terminada, todos los dispositivos apagados.

---

## FREEZE · iOS corregido en el dueño nativo (2026-08-03)

**El residual iOS dejó de ser un residual: era un defecto y está arreglado.**

| Corrección | Evidencia |
|---|---|
| `UIStatusBarHidden` `true` → `false` (`ios/Runner/Info.plist`) | Barra visible en iPhone 17 Pro real del simulador: `9:41`, wifi y batería, con `simctl status_bar override` |
| `UIViewControllerBasedStatusBarAppearance` `false` → `true` | El contraste lo pide cada pantalla; ningún estilo global sirve para claras y navy a la vez |
| `AnnotatedRegion` en `login_screen.dart` con `vinabikeSystemOverlayStyleFor` | Antes claro-sobre-claro (ilegible); ahora **oscuro sobre claro**, legible |
| `AuthService.shouldNotifyAuthListeners` | Arranque en frío llega al login en vez de colgarse en «Cargando…» |

Pruebas: `ios_status_bar_contract_test.dart` (3, **verificada por mutación**) ·
`auth_initialization_notify_contract_test.dart` (6). Batería de Nóminas + estas
dos + suites de auth: **618 pasadas · 2 opt-in · 0 fallidas**. Analyzer de todo
lo tocado: **0 issues**. `git diff --check`: limpio.

**El residual de autenticación queda ELIMINADO (2026-08-03).** El dueño importó
la sesión Supabase local al contenedor del Simulator, y el smoke se completó con
datos reales de producción en el iPhone 17 Pro nativo, sólo lectura. Ver el
bloque «Smoke iOS completo» al final.

**Estado del simulador al cerrar:** apariencia devuelta a claro, override de
barra de estado limpiado, app terminada, todos los dispositivos apagados. El
dispositivo `Claude iPhone 17 Pro` **se deja creado** a propósito: el
`Vinabike iPhone 17 Pro x86` del proyecto no puede mostrar pantalla en este M1.

---

## FREEZE FINAL · smoke iOS completo con datos reales (2026-08-03)

**iPhone 17 Pro nativo** (`Claude iPhone 17 Pro`, 402×874 puntos), app
autenticada contra producción, **sólo lectura**: no se pulsó `Confirmar semana`,
ni `Aplicar`, ni `Registrar corrección`, ni ninguna escritura financiera o de
base de datos.

| Recorrido | Resultado |
|---|---|
| Dashboard → drawer → RR.HH. → Nóminas | entra limpio |
| **Semanas** | claro y **oscuro**: cuatro registros reales (S27, $225.000), tira de semanas S27–S30, barra de dinero y CTA |
| **Historial list-first** | claro y oscuro: la lista **es** el control, agrupada por mes, `25+ semanas cerradas · solo lectura` |
| **Detalle de semana** | ledger completo (TOTAL / ANTICIPOS / A PAGAR / PAGADO / SALDO) y `PERSONAS` con su método y fecha |
| **Evidencia full sheet** | claro y oscuro: banda de dinero, movimiento, `ASIENTO CONTABLE AC-01910` con debe/haber y `Corregir pago` |
| **Navegación atrás** | `✕` del sheet devuelve al detalle **con su estado**, y `← Todas las semanas` vuelve a la lista |

**El `151` de `5l`, verificado en hardware simulado real.** La barra de estado
**existe, es visible y es parte del header**: se pinta navy como el resto del
cromo y su contenido va en claro —hora, wifi y batería legibles— sobre ese
navy, en los dos temas. Debajo van la banda de navegación (☰ + `Nóminas` +
contexto `S27 · 4 por resolver · $225.000` + campana) y la banda de alcance
(`Semanas 4 · Historial • · Anticipos •` + `•••`). **Inset superior consumido
una sola vez**: ningún contenido queda bajo la barra, no hay recorte ni doble
margen. Esto es lo que la fila `5l` pedía y no se había podido fotografiar.

### Hallazgos reproducibles FUERA de Nóminas (no corregidos acá)

Los dos se reproducen en el iPhone y ninguno es del módulo; se entregan con su
evidencia en vez de arreglarlos por el camino:

1. **La búsqueda del drawer no ignora acentos.** Escribir `Nomina` —como se
   teclea en un teléfono— devuelve «No encontramos módulos o páginas para
   "Nomina"», aunque el módulo se llame `Nóminas`. Owner: la navegación global,
   no Payroll.
2. **Botones que parten la palabra en `Configuración → Apariencia`.**
   `Cambiar Logo` se dibuja «Cam/biar/Logo» y `Eliminar` como «Elimi/nar», en
   claro y en oscuro. Ya se había visto en macOS a 430; **se confirma que no era
   del ancho de ventana**: es de esa pantalla. En la misma pantalla, en oscuro,
   los chevrons y el chip `4 accesos` quedan con fondo claro sobre tarjeta
   oscura.

**Con esto el módulo Nóminas queda CONGELADO, sin residual propio.**
