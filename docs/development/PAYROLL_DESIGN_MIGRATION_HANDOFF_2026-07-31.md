# Nóminas → migración a los diseños de Claude Design · handoff 2026-07-31

Continúa la migración visual del módulo de Nóminas. Este documento existe
porque el chat anterior murió por límite de contexto y porque el día se perdió
en gran parte por **no leer los diseños como corresponde**. Lee la sección 1
antes de tocar nada: ahí está el error que costó el día.

---

## 0. Lo que NO puedes hacer sin que el dueño lo autorice

Léelo antes que nada. El plan vivo es
**`docs/development/PAYROLL_COMPLETION_PLAN.md`** — su §13 tiene las
autorizaciones y su §15 es el ledger con toda la historia del módulo. Este
documento no lo reemplaza: lo continúa.

| Acción | Estado |
|---|---|
| **CHECKPOINT B** — smoke test con cartola real (writes de conciliación reales) | **PROHIBIDO.** Sigue sin autorizar |
| Commit / push / PR | Sólo si el dueño lo pide explícitamente |
| Desplegar migraciones a producción | Requiere autorización en el momento |
| Migración fuera de la lista cerrada de 7 | Requiere autorización |

CHECKPOINT A (las 7 migraciones) **ya fue autorizado y ejecutado**; el backend
versionado está activo en producción. No lo repitas.

### Escrituras reales: el accidente del 2026-07-30

Un clic de navegación cayó sobre `Quitar de la semana` y ejecutó
`save_payroll_voucher_draft` contra producción sin intención. Salió bien —el
dato era correcto y el dueño lo confirmó— pero la decisión no era del agente.

**Antes de cada clic, verifica dónde cae.** La app corre contra producción: no
hay entorno de juguete. Captura, ubica el objetivo, después haz clic.

### Restricción de runtime vigente

Mientras el plan de Nóminas siga abierto: sin Browser/Chrome/computer-use, sin
Workflow ni subagentes, y **una sola sesión Flutter** contra el checkout
compartido. La validación es formato + analyzer + tests headless + lecturas
guardadas de SQL. Es temporal y del alcance de esta tarea, no política
permanente.

### Otros contratos que aplican

- **`docs/architecture/canonical-ui-surfaces.md`**: si cambias una superficie
  de negocio, actualizas su fila del registro en la misma tarea.
- **`docs/development/CODEX_CLAUDE_COLLABORATION.md`**: antes de declarar
  terminado un trabajo compartido, corre el skill `cross-review`.
- **`docs/architecture/appearance-palette-contract.md`**: paletas, claro/oscuro
  y roles semánticos resuelven por esa cascada. Nada de literales locales.

## 0.b Trabaja sin parar a preguntar

El chat anterior murió por límite de contexto a mitad del trabajo. **Cada
pregunta evitable te acerca a esa muerte y no deja nada construido.** El dueño
lo dijo explícito: prefiere que decidas y avances.

**Decide tú, sin preguntar:** palabras, layout, qué del mock se descarta,
nombres de estados, orden de las columnas, si un control aporta o sobra, cómo
resolver un test rojo, cómo componer una pantalla. Ése es tu trabajo, no el
suyo. Si te equivocas, él lo dirá y lo corriges — eso cuesta menos que
preguntar.

**Pregunta sólo esto** (sección 0): CHECKPOINT B, commit/push, desplegar
migraciones. Nada más.

**Nunca cierres un turno con una pregunta que podías responder tú.** Si dudas
entre dos caminos, elige el que puedas revertir, dilo en una línea y sigue.

### Sobrevive a tu propio límite de contexto

Este chat también se va a acabar, sin aviso. Para que tu avance no muera con él:

- **Escribe en el ledger de `PAYROLL_COMPLETION_PLAN.md` §15 al cerrar cada
  frame**, no al final. Una línea con qué cerraste, qué decidiste y qué quedó.
- **Deja los tests en verde antes de empezar el siguiente frame.** Un módulo
  rojo a medias es más difícil de retomar que uno verde incompleto.
- Si notas que el contexto va largo, actualiza este documento con el estado
  real **antes** de seguir.

## 1. La regla que se incumplió y no se puede volver a incumplir

**Todo valor visual se lee de un archivo de Design con `DesignSync`. Nunca de
una captura de pantalla, nunca estimado.**

Lo que pasó el 30/07: un agente recorrió la ventana de Design con
`shot`/`scroll` para "ver" un popover, y escribió la superficie de su cabeza —
sombra, radio y borde inventados, y encima la sombra iba dentro de un `Material`
con `clipBehavior`, así que no se dibujaba nunca. Un `get_file` sobre la guía
devolvió los valores exactos en segundos.

El mismo error, más grande: se leyó `handoff-t5/spec.json` y se discutieron
reglas durante horas **sin bajar un solo PNG de los frames**. Los renders
estaban publicados desde el principio.

### Cómo se lee sin gastar contexto

Un `get_file` grande **se guarda en disco** y sólo entra un preview de 2 KB.
Ése es todo el truco: **buscar en el archivo, no cargarlo.**

```bash
# El resultado de la herramienta dice la ruta donde quedó. Se parsea y se grepea:
python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['content'])" \
  "<tool-result>.txt" > /tmp/spec.json
```

Para un PNG, el `content` viene en base64 → `base64.b64decode` → archivo → mirarlo.
Una guía de 260 KB cuesta 2 KB de contexto. **No existe el argumento de que
mirar sale caro.**

Contrato completo: `DESIGN_HANDOFF_SYNC_CONTRACT.md`.

---

## 1.b Oscuro y móvil también vienen de Design

Una superficie no está terminada en claro-escritorio. Cada una se cierra en
**tres vistas**: claro, oscuro y compacto (390). Y **la base visual de las tres
la entrega Design** — no cambia la división por cambiar de brightness o de
ancho.

- **El oscuro NO se deriva invirtiendo el claro.** Necesita capas propias, y
  los tonos semánticos no se recolorean por preset.
- **El móvil NO es la tabla comprimida.** Es composición propia: un objetivo
  por pantalla, targets táctiles.
- Si falta el frame oscuro o el compacto de una superficie, **pídelo**. No lo
  deduzcas: deducirlo es inventar con otro nombre.
- Tu aporte sigue siendo el mismo en las tres: criterio, lógica, UX y palabras
  **al implementar**. El look es de Design en las tres.

Móvil y tablet se cierran **junto con su superficie**, no como una fase final.
Diferirlos es lo que dejó abierto el pase de dark/compacto que este módulo
todavía arrastra (§15 del plan, entrada F8.2).

## 2. Qué manda Design y qué mandas tú

Design es experto **en diseño**, no en este negocio. El dueño lo dijo así:

> "el looking es lo más importante, pero si dentro de esos diseños Design puso
> algo que realmente no aporta, no existe en nuestro caso, tiene palabras
> raras, no usa bien el ajuste de layouts, o le faltan cosas que nosotros sí
> usamos, HAY QUE SABER RECONOCER ESO."

- **De Design**: paleta, tipografía, superficies, bordes, radios, sombras,
  chips, botones, tablas, inputs, jerarquía y estados.
- **Tuyo**: layout adaptativo, arquitectura de información, **palabras**, UX y
  lógica. Y la obligación de detectar lo que en el mock no aplica.

### Ejemplos ya resueltos (no los deshagas)

| Del mock | Decisión | Por qué |
|---|---|---|
| Rail vertical con iniciales (TA, IN, VE…) | **descartado** | La app ya tiene su menú y funciona |
| `Ordenar: pendientes primero` | **descartado** | Un control de orden para 5 filas es adorno; ése debe ser el orden por defecto |
| `GANADO` | → `TOTAL` | Un sueldo no se "gana" como premio |
| `DINERO NUEVO` | → `A PAGAR` | Dice lo que la columna contiene |
| `Comprometer semana` | → `Confirmar semana` | "Comprometer" en chileno suena a poner algo en riesgo. El RPC ya se llama `confirm_*` |
| `Imputar` (11 usos) | → `Aplicar` | "Imputar" es acusar de un delito |
| "crear obligaciones" | → "crear los sueldos por pagar" | Jerga contable |
| Píldora de confianza `61%` | → `CALZA` / `REVISA` / `NO SÉ QUIÉN ES` | Precisión falsa: no es una probabilidad medida, y un número invita a aprobar por umbral |
| `Confirmar efectivo` vs `Pagar` | **un solo verbo: `Pagar`** | La intención del dueño es la misma; lo que cambia es la evidencia, y eso va dentro del pago |
| Design **no** puso la salida a Asistencias | **agregada** | Design no sabe que Nóminas no puede editar horas |

**`cartola` y `conciliación` se quedan.** No son jerga: son las palabras
correctas en Chile y las que usa el dueño.

---

## 3. Estado del módulo

### El proyecto de Design tiene tres turnos, no uno

Esto no estaba escrito y se descubrió el 31/07 listando el proyecto:

| Carpeta | Qué es |
|---|---|
| `handoff-t5/` | Nóminas, 14 frames (5a–5n). **Todos en claro.** Incluye 5l phone y 5m tablet |
| `handoff-t7/` | Arquitectura de paletas: tinte, bordes, presets claro/oscuro a 1440, móvil claro/oscuro |
| `handoff-t8/` | Reemplaza el tinte oscuro de t7; 4 presets × 2 estados. Se declara `supersedes` de t7 |

t7/t8 son de la pantalla «Gestión de Trabajos», no de Nóminas: definen cómo se
construyen las capas oscuras a nivel de sistema. **Nóminas no tiene frames
oscuros propios.** Lo que hay que pedir está en `PAYROLL_COMPLETION_PLAN.md`
§14.c.

### Trampa del `spec.json` de t5

La geometría de 5a declara 7 tracks
(`24 / 1fr(min 220) / 118 / 112 / 108 / 146 / 172`) y **el frame dibuja 8
columnas**: el turno agregó `PAGADO` y dejó la línea de geometría del turno 4
(«sin cambios de geometría», dice su CHANGELOG). Se resuelve a favor del frame
—lo dice la regla del propio turno— y las columnas monetarias siguen siendo
`min/max/flex`, nunca anchos literales del mock.

Los PNG publicados son recortes sin reescalar, así que **medir sobre el pixel
del frame sí es método válido**; lo prohibido es medir sobre una captura de la
ventana de Design.

### Frames de Design (`handoff-t5/`, 14 frames)

| Frame | Qué es | Estado |
|---|---|---|
| 5a / 5b | Cola de semanas | **parcial** — ver abajo |
| 5c | Gramática de decisión (5 formas × 5 estados) | sin revisar |
| 5d | Confirmación de semana | sin revisar |
| 5e | Registro de pago por transferencia | sin revisar |
| 5f | Confirmación de efectivo | sin revisar |
| 5g | Método de pago del trabajador | sin revisar |
| 5h | Anticipos | sin revisar |
| 5i | Historial rediseñado | **cerrado** (claro-escritorio) |
| 5j | Conciliación OCR, 4 pasos | parcial — paso 3 avanzado |
| 5k | Estados reales del módulo | sin revisar |
| 5l | Phone 390 | sin revisar |
| 5m | Tablet 834 | sin revisar |
| 5n | Matriz de cierre | sin revisar |

**Ninguno se comparó mirando su PNG salvo 5a.** Ése es el trabajo: bajar cada
frame, ponerlo al lado de la app, y cerrar diferencias con criterio.

### 5a — CERRADO (2026-07-31)

Claro-escritorio y oscuro verificados en la app viva; compacto verificado por
test a 390 px (la sesión quedó tomada por el dueño antes de re-confirmarlo).

- Barra de progreso y línea de estado en las tarjetas de semana
- Horas junto al nombre
- Columnas `A PAGAR`, `PAGADO` y `DECISIÓN`
- Anticipos como `−$40.000` en verde
- Chip de decisión con método y fecha (`Pagado transf 14/07 ›`)
- Fila expandida con sus tres paneles (cómo se calculó / pagos / atajos)
- Resumen de la semana seleccionada en el header
- Franja «N personas quedan fuera del cálculo» con salida a Asistencias
- Tercer tier de columnas para 5m (834 suelta `ANTICIPOS` y `PAGADO`)

**`A PAGAR` cambió de significado**: era el saldo pendiente y ahora es
`total − anticipos`, que es lo que hace cuadrar la aritmética del pie
(`total − anticipos − pagado = falta pagar`). Con el saldo, una fila pagada
mostraba `$0` y la columna no sumaba nada.

**`Quitar de la semana` se retiró.** 5a resuelve el mismo caso mejor: la fila
dice `Horas sin cerrar`, sale de la aritmética de la semana, y la corrección
vive en Asistencias. Se conserva lo esencial de la corrección del 30/07 —$0 no
es «Pagado»— y desaparece de la tabla el botón que ese día disparó un write
real por accidente.

### Código muerto: revísalo antes de escribir uno nuevo

Dos veces ya ha pasado que un widget completo, correcto y con el diseño del
frame **nunca se instancia**, mientras la pantalla renderiza otra cosa:

| Widget | Estado |
|---|---|
| `PayrollPendingDecisionCard`, `PayrollReviewSection`, `PayrollNextQuestionAction` | 30/07: escritos y muertos → conectados |
| `PayrollReviewTableRow` (tabla de 5j paso 3) | 31/07: estaba muerto → **instalado**, reemplazando el ledger denso |

**La regla que zanja estos casos** (dueño, 2026-07-31): si un turno anterior se
confundió y montó otra composición, **se cambia a la de Design igual, aunque la
UX y la lógica de lo que hay funcionen bien**. Lo que funciona no es argumento
para conservar una composición que Design no propuso.

Antes de construir la superficie de un frame, **grepea si ya existe**:

```bash
grep -rn "NombreDelWidget" lib/ | grep -v "surfaces/.*\.dart:"
```

Si sólo aparece su propia declaración, está muerto. Decide: instanciarlo o
borrarlo — dejarlo es lo que hace creer que el frame ya está implementado.

### 5l — lo que falta (medido contra `5l-1-p1.png`)

La tarjeta de persona ya sigue 5l (cifra dominante, horas junto al método,
disclosure propio, razón del bloqueo bajo el CTA). Queda:

- **Tira de semanas en píldoras** `S28 S29 S30 +2`, no tarjetas anchas con monto
- **Fila pagada colapsada**: avatar con check verde, `pagado 14/07 · $179.375`
  y chevron; hoy usa la misma tarjeta pesada que una fila por resolver
- Badges de la cabecera (anticipos / pendientes) como en el frame

---

## 4. Correcciones de fondo hechas hoy (no son cosméticas)

1. **`$0` ya no dice "Pagado".** `balance == 0` se traducía a pagado sin
   preguntar por qué era 0. Alguien sin horas aparecía en verde afirmando un
   pago inexistente. Ahora hay `nothingToPay` con acción `Quitar de la semana`
   (usa `updateLine`, que ya existía y ya rechaza semanas confirmadas).
2. **Una semana en borrador no ofrece "Pagar".** El botón decía "Pagar" y
   abría el diálogo de confirmar la semana: mentía. Ahora `weekNotConfirmed`.
3. **Etiquetas de semana**: `ABIERTA`/`EN COLA` eran el mismo hecho con dos
   nombres. Ahora sólo aparece lo que no se deduce: `SIN CONFIRMAR`, `EN CURSO`,
   `PAGADA`.
4. **Iniciales legibles**: el color salía de una paleta por hash con texto de
   color fijo encima y nadie comprobó el par. Ahora fondo y tinta se derivan del
   mismo tono, así no puede quedar sin contraste.
5. **Asiento contable real en el respaldo de pago.** Ver sección 5.
6. **Composición 2c conectada**: `PayrollPendingDecisionCard`,
   `PayrollReviewSection` y `PayrollNextQuestionAction` estaban escritos y
   **nunca instanciados** — código muerto mientras la página renderizaba la
   tabla vieja.

---

## 5. Lección cara: verificar la fuente antes de afirmar

El respaldo de pago mostraba `Haber · no quedó registrada`. **Era falso.**

Se leía `expense_payments.payment_account_id`, que efectivamente está nulo en
los 78 pagos de sueldo. Pero el asiento real vive en `journal_entries` +
`journal_lines` y **está completo y cuadrado en los 78**:

```
AC-01910 · 28/06/2026
  2106  Sueldos por Pagar           Debe   $24.000
  1110  Bancos - Cuenta Corriente   Haber  $24.000
```

El vínculo es `journal_entries.source_reference = expense_payments.id` con
`source_module = 'expense_payments'`, y `evidence.id` **es** el id del pago.

Esa afirmación falsa habría hecho al dueño desconfiar de una contabilidad sana.
**Antes de decir que un dato falta, comprobar que no sea la lectura la que
falla.** Las lecturas de producción son autónomas: `scripts/db/query.sh
production --sql "…"`.

---

## 6. Deuda abierta

### ~~22 tests rojos~~ → 292/292 VERDE (2026-07-31)

Eran 31, no 22, y sólo una parte era texto. Lo que había debajo:

- **7 suites sin compilar** (4 de Nóminas y 3 ajenas): `DatabaseService.select`
  ganó un parámetro `offset` con la paginación de Contabilidad y los fakes
  quedaron con la firma vieja.
- Un fake seguía en el contrato **pre-versionado** (`register_employee_advance`
  devolviendo string en vez de `register_employee_advance_v2` con recibo).
- **Defecto real**: al renombrar «Comprometer»→«Confirmar» se perdió
  `${draftVouchersToCommit.length}` y el CTA decía `Confirmar  semana`.
- **Defecto real**: `_setRowDisposition` medía `_suggestionIsBatchSafe`
  *después* de escribir la disposición —y esa función exige que la fila siga
  pendiente—, así que siempre daba `false` y **todo calce de un solo toque
  quedaba abierto como pregunta**. 19 tests colgaban de esto.
- **Defecto real**: el chip «Ver pago ›» del Historial se recortaba 19 px.

Lección: cuando una batería se pone roja tras un cambio de texto, **la mayoría
de los rojos suele no ser el texto**. Leer el error antes de tocar la aserción.

```bash
.fvm/flutter_sdk/bin/flutter test $(ls test/widgets/payroll_*.dart test/unit/payroll_*.dart | tr '\n' ' ')
```

### 23 rutas sin trackear en git

~14.500 líneas de Nóminas (`lib/modules/hr/payroll/`, la página de
conciliación, el parser de cartolas, el matcher, el OCR local) **nunca se
agregaron a git**. Existen sólo en el árbol de trabajo. Commitear es del dueño;
avisar es del agente.

---

## 7. Runtime

- Sesión macOS canónica: `scripts/dev/native_session.sh start|reload|restart`.
  El dueño la toma con `screen -x payroll` (`r` recarga, `R` reinicia).
- **El input NO mueve el cursor del dueño**: `app_control.sh click|scroll|drag`
  entra por las extensiones de depuración de `lib/dev/agent_input.dart`.
  `APP_CONTROL_BACKEND=os` fuerza los CGEvent reales, sólo para probar la capa
  del sistema operativo.
- Un `restart` devuelve la app al Inicio: hay que volver a navegar antes de
  juzgar lo que se ve.
- **Cuidado con los clics de navegación**: el 30/07 uno cayó sobre
  `Quitar de la semana` y ejecutó un write real en producción. Verificar dónde
  cae el clic antes de dispararlo.

Runbook: `AGENT_MACOS_APP_CONTROL.md`.

---

## 8. Por dónde empezar

1. Dejar los 22 tests en verde. Sin eso no se sabe qué rompe cada cambio.
2. Cerrar lo que falta de 5a.
3. Seguir frame por frame: 5i (Historial) y 5j (OCR) son los de mayor uso real,
   después 5e / 5f / 5h.
4. Para cada frame: bajar el PNG, ponerlo al lado de la app, listar diferencias,
   y separar explícitamente **lo que se copia** de **lo que se descarta con
   criterio propio**. Nombrar el frame en el handoff de la ronda.
