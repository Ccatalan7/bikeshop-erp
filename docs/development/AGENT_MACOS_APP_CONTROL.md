# Driving the app and reading Design from an agent session

Everything an agent needs to verify UI work on this repository **without**
10-minute rebuilds, without asking the owner to click, and without
re-discovering the same five traps. Read this before touching UI.

Verified working on 2026-07-30 (macOS 25.5, Flutter 3.38.5 via FVM).

> **El procedimiento vive en
> [`AGENT_VISUAL_WORKFLOW.md`](AGENT_VISUAL_WORKFLOW.md).** Este archivo
> es la referencia de cada herramienta y de las trampas que encierra.
> Si vienes a probar la app o a compararla con un frame, empieza por allá.

## Analiza antes de recargar, y recarga antes de reiniciar

**2026-08-10, costo real: dos flujos completos de AliExpress rehechos.**

`dart analyze` sobre los archivos que uno toca no basta. Agregar un valor a un
`enum` compartido rompe todos los `switch` exhaustivos del repositorio —
`ProductDuplicateMatchTier.ruledOut` rompió
`lib/modules/inventory/widgets/product_duplicate_review_dialog.dart`, un archivo
que el cambio no tocaba—. La app arranca igual y falla al compilar el hot
reload, y desde afuera eso se ve idéntico a «el reload no confirmó». El orden es:

1. `dart analyze lib test` completo cuando el cambio toca un tipo compartido
   (enum, clase sellada, firma pública). Sobre los archivos propios sólo cuando
   el cambio es local.
2. `scripts/dev/native_session.sh reload`.
3. `restart` **sólo** si el reload no basta.

Un reinicio no es gratis: borra el estado de la sesión y obliga a rehacer el
flujo entero —en el OCR de compras, volver a juntar los pedidos del día, releer
la factura y volver a pagar el análisis de IA de cada línea—. El dueño lo dijo
en esas palabras; cada reinicio innecesario le cuesta minutos y cuota.

Lo que un reload **no** recalcula es el estado ya computado: los candidatos de
una fila se resolvieron una vez y siguen ahí. Para volver a medirlos sin
reiniciar, se vuelve a disparar el trabajo desde la propia pantalla —«Buscar
pendientes», el reintento de una fila, o abrir el overlay de parecidos, que
consulta de nuevo al matcher— en vez de rehacer el flujo desde el navegador.

## The three surfaces, and when to use each

| Surface | Loop | Use it for |
|---|---|---|
| **macOS debug session** (`scripts/dev/native_session.sh`) | hot reload 2–5 s | Default for every desktop/tablet UI round. Real data, real services. |
| **iOS Simulator** (`mcp__Claude_Code_iOS_Simulator__control`) | build once, then tap/screenshot | Phone layouts, touch targets, safe areas, keyboard insets. |
| **Web preview** (`scripts/dev/web_preview.sh`, see `WEB_PREVIEW.md`) | release build ~10 min | Only when the browser is the point. Not an iteration loop. |

## 1. macOS debug session — the main loop

```bash
scripts/dev/native_session.sh start      # ~1-2 min the first time
scripts/dev/native_session.sh reload     # after edits · ~2-5 s
scripts/dev/native_session.sh restart    # state reset · ~3-5 s
scripts/dev/native_session.sh errors     # compile errors / exceptions
scripts/dev/native_session.sh status
scripts/dev/native_session.sh stop
```

La sesión canónica usa por defecto el mismo gateway moderno del release. El
owner acepta sólo los defines cerrados; no acepta un fragmento arbitrario de
shell. La clave pública se resuelve en el proceso que lanza la sesión, primero
desde `NATIVE_SESSION_SUPABASE_PUBLISHABLE_KEY` y luego desde el Keychain
aprobado, y no se escribe en el repositorio ni en el log. Por eso el arranque
normal es simplemente:

```bash
scripts/dev/native_session.sh start
```

Si la entrada de Keychain no existe, el launcher falla antes de compilar en vez
de abrir una sesión cuyo primer mensaje inevitablemente fallará. Un valor de
entorno explícito sigue siendo válido para una sesión acotada.

El asistente legado queda disponible sólo como rollback explícito y visible:

```bash
NATIVE_SESSION_AI_AGENT_GATEWAY_ENABLED=false \
  scripts/dev/native_session.sh start
```

Un hot reload no puede cambiar un `dart-define`: para activar o revertir este
rollout se reemplaza deliberadamente la sesión completa.

The session lives in a detached `screen` named `payroll`. The owner can take
it over at any time with **`screen -x payroll`** (`Ctrl+A`, then `D` to
detach). Both sides share the same terminal, so nobody has to hand over.

Traps this encodes, each of which cost a full round when hit:

1. **Never pipe `flutter run` to `tee`.** Losing the TTY silently disables the
   single-key commands: `r` does nothing, forever. Logging goes through
   screen's own `logfile` directive (macOS ships screen 4.x, which has no
   `-Logfile` flag — it must come from a `screenrc`).
2. **Keys need `-p 0`:** `screen -S payroll -p 0 -X stuff 'r'`. Without the
   window selector the keystroke is swallowed.
3. **One session at a time.** If VS Code is running its own debug session,
   stop it first (⏹). `start` refuses instead of creating a second one.
4. **A hot reload rebuilds the routed page**, so the module returns to its
   default scope. Re-navigate before judging what you see.
5. **A wedged incremental compiler looks like a dead session, and isn't**
   (2026-07-31). Symptom: `reload` times out, the log freezes mid
   `Performing hot reload... ⣷⣯`, and **the app keeps running and answering
   screenshots** — so every capture shows the OLD code and nothing you write
   ever appears. `flutter run` never reports it. More reloads do nothing.

   Run **`native_session.sh doctor`**, which names the cause instead of
   guessing: it checks whether the log is still growing, probes the VM service
   with a **read-only `getVM`**, and prints `COMPILADOR TRABADO — Error while
   starting Kernel isolate task` when the kernel task is stuck. The only fix
   is restarting the process: `native_session.sh stop && native_session.sh start`.

   > **`doctor` no pide un `reloadSources`, y no debe pedirlo.** Una versión
   > anterior lo hacía «para comprobar», y eso disparaba un segundo reload
   > encima del que ya corría: los dos morían y el doctor reportaba trabado un
   > compilador que él mismo acababa de trabar. Un diagnóstico es de sólo
   > lectura — si para medir algo hay que moverlo, no se está midiendo. El
   > script actual usa `getVM`; esta guía decía lo contrario hasta el
   > 2026-08-01.

6. **La app puede arrancar sin que el tool llegue a su loop interactivo**
   (2026-08-01). Síntoma engañoso: `status` dice `app: pid NNNNN` —está viva y
   cargando datos reales— pero `vm: sin URI en el log`, y **todo
   `app_control.sh` queda inservible** porque va por el VM service. No es que
   la app haya fallado: es que `flutter run` nunca imprimió la línea
   `A Dart VM Service … is available at:`.

   Cómo se confirma en dos comandos, sin tocar nada:

   ```bash
   lsof -nP -p <pid> -a -iTCP -sTCP:LISTEN     # sí escucha: 127.0.0.1:NNNNN
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:NNNNN/   # 403
   ```

   El `403` es la prueba: el puerto existe, pero el VM exige el **código de
   autenticación**, y ese código **sólo viaja en la línea de stdout que nunca
   salió**. No se puede reconstruir ni adivinar. Otra señal del mismo cuadro:
   `screen -S payroll -p 0 -X stuff 'h'` deja una `h` literal al final del log
   en vez de imprimir la ayuda — el proceso no está leyendo teclas.

   **La única salida es reemplazar la sesión deliberadamente**
   (`stop` y luego `start`, comprobando antes los PID y la `screen`), y **exigir
   la URI del VM antes de seguir**. Con el build caliente cuesta poco. Lo que no
   se puede es seguir trabajando «a ciegas» sobre una app que responde a la
   vista pero no al control: cada `read`/`shot` fallaría y se leería como un
   defecto de la pantalla.

7. **`stop` dejaba huérfano todo el árbol, y por eso el `start` siguiente se
   negaba** (2026-08-01). `stop` era una sola línea: `screen -S <s> -X quit`.
   Eso mata **screen**, no a sus descendientes: `login → flutter → frontend`
   pasan a colgar de `init` y siguen vivos. Se observó **dos veces en una
   jornada** —dos árboles completos quemando CPU— y el síntoma con el que
   aparece es engañoso: el `start` siguiente responde `hay una app debug viva
   sin sesión screen`, que se lee como «quedó una app abierta» cuando en
   realidad quedó un `flutter run` entero.

   Peor: una vez que screen murió, **ya no hay manera de saber qué
   descendientes eran suyos** sin adivinar por patrón — y matar por patrón es
   justo lo que este runbook prohíbe, porque acierta a la sesión del dueño con
   la misma facilidad.

   El owner corregido hace las cuatro cosas en orden: **captura el árbol antes
   de tocar screen**, pide salida grácil con `q` (que es como `flutter run`
   termina solo, cerrando la app y liberando el VM service), y sólo si no salió
   cierra screen y termina **ese** árbol, hoja primero; al final **verifica que
   no quede descendiente y lo dice si queda**. Un `stop` que informa éxito sin
   comprobarlo es exactamente lo que produjo los huérfanos.

   Do **not** blame `screen -ls` saying `(Attached)`. An attached owner does
   NOT block reloads — that misreading cost a full round on 2026-07-31, and
   `doctor` now prints the attach as informational precisely so nobody
   confuses it with the cause again.

8. **Nunca pongas `reload`/`restart` dentro de un loop o background task**
   (2026-08-01). Un loop dejado esperando sobrevivió al primer reemplazo y,
   como la sesión nueva reutiliza el nombre `payroll`, le inyectó una `r`
   durante el build. La sesión recién creada llegó al VM y quedó trabada de
   inmediato en `Performing hot reload...`; repetir `stop && start` sin matar
   primero el productor sólo recreó el mismo defecto.

   `native_session.sh reload` ya espera y confirma una sola ronda. Si queda
   colgado, **interrumpe primero el comando, loop o task que envió la tecla**;
   después usa `doctor` y reemplaza la sesión una vez. Nunca dejes un poller
   que ejecute acciones: observar `status` puede repetirse, enviar `r`/`R` no.

9. **Recicla la sesión (`stop && start`) en rondas pesadas de WebView**
   (2026-08-05). Un hot restart (`R`) reinicia el código Dart pero **no corre
   `dispose()`**: cada restart puede dejar huérfano el WKWebView nativo de
   cada workspace abierto, y esa memoria no vuelve nunca dentro del mismo
   proceso. Costo real: tras ~24 h de sesión con 5 recorridos completos de
   AliExpress y ~6 hot restarts, el proceso llegó a **41 GB de RSS**, macOS
   agotó la memoria del sistema y pausó todas las aplicaciones — los
   «cuelgues» que parecían bugs del flujo OCR eran el proceso congelado por el
   sistema. Regla: antes de una ronda que navegue mucho dentro de WebViews
   (importación AliExpress, pruebas largas del navegador), y después de 2-3
   hot restarts con workspaces de navegador abiertos, reemplaza el proceso
   completo. En producción no aplica (no hay hot restart) y desde el
   2026-08-05 la app además se defiende sola: `MemoryHygiene` (watchdog de RSS
   + `didHaveMemoryPressure`) libera las cachés transitorias registradas, el
   ImageCache del framework y la caché en memoria de los WebView.

10. **Una sesión lanzada por el agente no puede hacer hot reload en esta
    máquina** (2026-08-06). macOS protege los contenedores de las demás apps:
    un `flutter run` lanzado desde el shell del agente (hijo de Claude.app, con
    o sin sandbox propio) no puede escribir el DevFS en
    `~/Library/Containers/com.vinabike.vinabikeErp.debug/Data/tmp/` — «Operation not
    permitted». El arranque en frío funciona (instala por el bundle), pero el
    **primer** `r`/`R` imprime «Flutter failed to create file/directory at
    .../Data/tmp/...» y `flutter run` **muere**, llevándose el `screen`. El
    síntoma engaña doble: parece que «algo mata la sesión a los minutos», y el
    primer archivo que DevFS intenta crear (p. ej. un asset) parece el
    culpable. Costó cinco sesiones en una noche. Opciones reales: (a) el dueño
    lanza `scripts/dev/native_session.sh start` desde su Terminal y el agente
    se adhiere con `screen -x` — el modo histórico, con reload de 2-5 s; (b) el
    dueño concede a Claude acceso a datos de otras apps / Full Disk Access
    cuando macOS lo pregunte; (c) sin permiso, el agente trabaja sólo con
    arranques en frío (~1-2 min por iteración de código; navegar y probar no
    necesita reload).

11. **Nunca vacíes `.tmp/native-session/run.log`** (2026-08-06). `app_control.sh`
    saca la URL del VM service de ese archivo: truncarlo para «leer el log
    limpio» deja toda la herramienta ciega con «sin VM service en el log», y
    los `tap`/`read` fallan en silencio mientras la sesión sigue viva. Para
    leer sólo lo nuevo, usa `tail -c`/`tail -n` o marca la posición antes de
    empezar; para empezar de cero, reemplaza la sesión (`stop && start`), que
    reescribe la línea del VM service.

### Debug y la app instalada no comparten identidad (2026-08-27)

La copia instalada y el build Debug llegaron a ejecutarse simultáneamente con
el mismo bundle ID, `com.vinabike.vinabikeErp`. Para macOS eran la misma app:
ambas quedaron dentro de un solo sandbox y escribieron el mismo registro de
Supabase en SharedPreferences. El último inicio de sesión reemplazaba la sesión
persistida de las dos; la otra ventana podía conservar el usuario antiguo en
memoria hasta un reinicio o refresh y entonces cambiar de cuenta. El mismo
choque alcanzaba preferencias, SQLite y datos persistentes de WebKit.

La separación obligatoria es:

- Debug: `com.vinabike.vinabikeErp.debug`;
- Release y Profile: `com.vinabike.vinabikeErp`.

La identidad se resuelve por configuración en
`macos/Runner/Configs/{Debug,Release}.xcconfig`; no se arregla cambiando sólo la
clave local de Supabase, porque eso dejaría todas las demás cachés compartidas.
`native_session.sh start` lee los build settings efectivos de Xcode y falla
antes de lanzar Flutter si Debug y Release vuelven a coincidir o si cambia la
identidad estable de Release.

El primer arranque con la identidad separada crea un contenedor Debug limpio;
no copies preferencias desde el contenedor Release, porque eso reintroduciría
la sesión y datos locales que justamente se aislaron. Las dos apps pueden quedar
abiertas con usuarios distintos. Sus ejecutables aún se llaman
`vinabike_erp`, así que todo control sigue resolviendo la ruta Debug y el PID
exactos, nunca el nombre del proceso.

### Verifying dark and compact without leaving a trace

Both are required before a surface is declared done, and both are reachable
from the same session:

- **Dark**: Configuración → Apariencia → `Oscuro`. It writes the owner's
  persisted preference, so **put it back on `Claro` when you finish** — the
  app is theirs, not a test rig.
- **Compact (390)**: resize the window instead of booting the Simulator when
  you only need the composition:

  ```bash
  scripts/dev/app_control.sh resize 430 928
  ```

  `app_control.sh geometry` prints the pid and confirms the new size, and the
  compact shell (drawer + pills) engages exactly as on a phone. Restore
  with `scripts/dev/app_control.sh resize 1672 928` afterwards. Use the
  Simulator when what you need is touch behaviour or the real safe areas, not
  just the breakpoint.

  Do not address `front window` yourself. On 2026-08-01 the exact debug process
  retained a residual 66×20 window while its real Flutter frame was 1360×768;
  `window 1`, process-frontmost, and name-based resizing all selected the
  residue and made working controls look broken. The wrapper resolves the
  exact debug PID and chooses its largest accessible window for `geometry`,
  `resize`, OS screenshots and OS-input fallback.

## 2. Eyes and hands on the running app

```bash
scripts/dev/app_control.sh shot out.png      # the app's own rendered frame
scripts/dev/app_control.sh geometry          # pid · window · frame size
scripts/dev/app_control.sh click X Y         # current `shot` only; never reuse
scripts/dev/app_control.sh scroll X Y -5
scripts/dev/app_control.sh drag X Y X2 Y2
scripts/dev/app_control.sh type "texto"
scripts/dev/app_control.sh key 36            # 36 return · 53 esc · 48 tab
scripts/dev/app_control.sh choose-file /ruta/absoluta/cartola.png
```

### `type` y `key` se caen solos; `enter-text` no (2026-08-21)

`type` y `key` son los **únicos** subcomandos que salen por AppleScript
(`System Events`). Esa autorización es del proceso que corre el shell, así que
puede estar concedida a una sesión y **denegada a la siguiente sin que cambie
nada en el repo**: `osascript` devuelve `-1743 Not authorized to send Apple
events`, `app_control.sh type` lo traga con `>/dev/null 2>&1` y sale 1 **en
silencio**. El campo se ve enfocado, con cursor y borde activo, y el texto
simplemente no llega — se parece exactísimo a un `TextField` deshabilitado.

`click`, `tap`, `scroll`, `drag`, `find`, `read` y `enter-text` van por el
canal de depuración de Flutter y siguen funcionando con la autorización
denegada. Por eso el síntoma es «los clics andan pero no puedo escribir», que
manda a buscar el defecto en la app.

Escribe siempre con `enter-text --key`, no con `type`:

```bash
scripts/dev/app_control.sh enter-text --key ai-assistant-message-input \
  --text "contacta al cliente Test"
scripts/dev/app_control.sh tap --label "Enviar mensaje al asistente"
```

Confirma con el eco que imprime (`texto ingresado (N caracteres) en <key>`).
`type` queda para el caso en que **no haya** `ValueKey` y haga falta el camino
real del sistema operativo; comprueba entonces su salida en vez de descartarla.

Costó cinco rondas el 2026-08-21 dando por rota la app.

### El selector de archivos es una ventana del sistema (2026-08-01)

`Elegir archivo` abre un panel de macOS que no pertenece al árbol semántico de
Flutter. No intentes manejarlo con coordenadas guardadas ni mandes
`Cmd+Shift+G` a ciegas: con el panel abierto detrás de Claude, el atajo terminó
seis veces en el buscador interno de Claude y luego otro intento perdió varios
minutos bajando carpeta por carpeta.

Abre el panel tocando el botón Flutter por identidad y entrega el archivo con
el owner versionado:

```bash
scripts/dev/app_control.sh tap --label "Elegir archivo"
scripts/dev/app_control.sh choose-file \
  /Users/Claudio/Dev/bikeshop-erp/tmp/pdfs/cartola_analysis/page-01.png
```

`choose-file` exige un archivo real y una ruta absoluta, resuelve el panel
`Open` del PID debug exacto, lo trae al frente y abre `Go to Folder`. **La ruta
se pega desde el portapapeles en una sola operación; no se teclea carácter a
carácter.** Teclearla compite con la animación de la hoja y pierde caracteres,
mientras que `Cmd+Shift+G` + paste ya fue el mecanismo probado. El owner
preserva y restaura todos los formatos del portapapeles, confirma el archivo y
falla si el panel no se cerró. No lanza otra copia de la app ni toca una
ventana de Claude o Terminal. Después confirma el resultado por semántica
(`read`) —por ejemplo, nombre del archivo y cantidad de movimientos— antes de
seguir.

El PID debe permanecer en el *specifier* de AppleScript en cada acceso. No
guardes `first process whose unix id is …` en una variable para reutilizarla:
System Events serializa después esa referencia por **nombre**, y si la copia
instalada y la debug se llaman ambas `vinabike_erp`, `tell targetProcess`
resuelve la primera homónima. El síntoma engañoso fue `name of every window`
como lista anidada y `-1700`, aunque el PID inicial era correcto. Tampoco uses
`open -a` para enfocar: aunque Debug y Release ya tienen identificadores
distintos, ambos ejecutables conservan el nombre `vinabike_erp` y resolver por
nombre puede activar la copia instalada. `choose-file` mantiene ahora el
predicado de PID inline y enumera cada ventana por índice; esta trampa costó una
ronda completa el 2026-08-01.

### Tap by identity; pixels are a one-frame fallback (2026-07-31)

```bash
scripts/dev/app_control.sh find --label "Confirmar semana"
scripts/dev/app_control.sh find --key payroll-confirm-week
scripts/dev/app_control.sh tap  --key payroll-confirm-week
scripts/dev/app_control.sh enter-text --key ai-assistant-message-input \
  --text "Resume los trabajos activos"
```

**Why a reused `click X Y` keeps missing.** `shot` returns physical pixels —
1360×757 on one run, 3024×1632 on a Retina display, 2312×1410 after a resize —
while Flutter hit testing uses logical coordinates. The script bridges those
spaces for the **current** frame: the normal app backend queries the live DPR
and divides the physical frame coordinates before creating `PointerEvent`s;
the OS backend maps the same physical pixels into the current window and title
bar. That translation does not make a saved coordinate durable. Navigation,
layout, resize, display/DPR changes or an app restart can move the target, so a
coordinate read from an earlier capture is stale. On an app running against
**production**, reusing one caused the 2026-07-30 navigation tap to land on
`Quitar de la semana` and write for real.

`find` resolves the target from the live element tree by `ValueKey<String>` or
by semantic/`Text` label, and prints its real rectangle in logical coordinates.
`tap` locates and taps in one step, and **prints what it hit** — so you keep
awareness of where the event landed instead of inferring it.

Three properties that matter:

- **Ambiguity is an error, not a coin flip.** With more than one candidate
  `tap` refuses and lists them. `--index N` is a zero-based integer into that
  list; a missing index for multiple matches, non-integer, negative, or
  out-of-range value is rejected before any pointer event is sent.
- **The target must be live and usable now.** Its chosen point must be inside
  the current logical viewport and its branch must win the live hit test.
  Offstage, ignored, absorbed, semantics-disabled, disabled-button, covered,
  off-viewport, detached, and zero-size candidates are not returned.
- **Coordinates expire.** If an identity does not exist, take a fresh `shot`
  and use its point immediately. Never carry a coordinate across navigation,
  layout changes, resize, display/DPR changes, reload, or restart.

Keep `click X Y` for what has no identity — a canvas, a chart, a spot inside an
image — and for testing the OS event path itself. For anything with a key or a
label, use `tap`; never reuse a coordinate from an earlier frame.

### Text fields: update Flutter, not only the macOS AX proxy (2026-08-03)

Computer Use can focus a Flutter macOS `TextField` and report it as settable,
while `set_value` changes only the native accessibility proxy. The AX tree then
shows the requested value even though the rendered field and its
`TextEditingController` remain empty; `Return` consequently submits nothing.
`type_text`/key injection can fail through the same bridge. This was reproduced
both in the AI composer and the inventory search field, so a feature-local
`Semantics(onSetText:)` does not repair it.

For the debug app, enter text through the existing process-local input owner:

```bash
scripts/dev/app_control.sh enter-text \
  --key ai-assistant-message-input \
  --text "Dame un resumen de los trabajos activos"
scripts/dev/app_control.sh tap --key ai-assistant-send-message
```

`enter-text` resolves one live `ValueKey<String>`, rejects missing, ambiguous,
disabled, read-only and non-editable targets, and updates the real
`EditableTextState` through Flutter's user-edit pipeline. Formatters,
`onChanged`, selection, rendering and submit callbacks therefore receive the
same value. An empty `--text ""` deliberately clears the field. The extension
exists only in Debug and a newly added extension requires a hot restart before
the running isolate exposes it.

Hot reload also cannot retrofit every change to the shape of an already-live
object. If adding a non-null instance field produces an otherwise impossible
`Null` subtype error immediately after reload, capture that exact first error
and hot restart the **same canonical session** once before diagnosing app
logic. Do not launch a second Flutter session; verify the restarted isolate is
clean and continue from there.

Do not treat a changed AX value as evidence. Completion evidence is the same
text in a fresh rendered frame/semantics read and the expected result after the
real submit control is tapped.

### Two ways of seeing, and they answer different questions

```bash
scripts/dev/app_control.sh shot out.png          # cómo se VE
scripts/dev/app_control.sh read                  # qué ESTÁ
scripts/dev/app_control.sh read --filter pagar
```

`shot` returns the exact rendered frame through the VM service — real pixels,
not a photo of a screen. It is the only way to judge design fidelity, and it
stays mandatory for that: comparing a frame against the app is what this whole
contract is built on.

But a picture does not say what *is*. Whether a button is disabled, a row
selected, a field focused, a disclosure open — reading those off colour is
inference, and inference is how an agent ends up asserting something false.

`read` walks the **semantics tree**, the same structure Flutter hands to
VoiceOver, so it reflects the app as a person who is not looking at it receives
it. It prints label, value, state flags and size, indented by hierarchy, and
costs text instead of an image. `--filter` narrows it to one region.

Use both: **structure from `read`, appearance from `shot`.** When they
disagree, the semantics tree is what a screen reader will announce — that
disagreement is itself the bug.

**Precisión 2026-08-19: un `shot` puede estar viejo, y entonces no desmiente
nada.** Si la ventana de la app está detrás de otra —o su ciclo de vida quedó
en `hidden`/`paused`—, macOS deja de pedirle frames y `_flutter.screenshot`
devuelve el último raster que sí se dibujó: la captura muestra la pantalla
*anterior* a la interacción. `read` no se conforma con eso, bombea frames antes
de leer, así que sí ve el estado nuevo. Así que cuando `shot` y `read`
discrepan y `read` describe algo que `shot` no muestra, lo primero que se
descarta es que la app esté ociosa; el propio `read` lo avisa con «el engine no
entregó frame en 3 s». El costo real: un diálogo recién abierto se dio por no
abierto, y el paso siguiente habría sido «arreglar» código que ya funcionaba.
`window` no rescata ese caso: fotografía el rectángulo de la pantalla, de modo
que devuelve la ventana que esté delante —y de paso captura lo que el dueño
tenga abierto—, no la app.

### Two input backends — the default does not touch the owner's cursor

`click`, `scroll` and `drag` are delivered **inside the app** by default, through
the debug service extensions in `lib/dev/agent_input.dart`. They hand synthetic
`PointerEvent`s to `GestureBinding`, the same way widget tests do.

| | default (`app`) | `APP_CONTROL_BACKEND=os` |
|---|---|---|
| Owner's cursor | untouched | **moves — you fight over one mouse** |
| Window focus | not required | required, and stolen |
| Installed build stealing clicks | impossible | a real trap |
| Proves the OS event path | no | yes |

The default exists because the agent and the owner previously shared one
physical pointer: either could land a click in the middle of the other's
gesture. Now the owner keeps using the Mac while the agent drives the app, even
with the window in the background.

Use `APP_CONTROL_BACKEND=os` only to test the OS path itself — a window that
receives no events at all is invisible to synthetic pointers, by construction.

The channel is registered from `main.dart` behind `kDebugMode`, so no release
build exposes it. A build that predates it simply lacks the extension and the
script falls back to CGEvents on its own.

How the CGEvent backend works, and why it is not obvious:

- **`shot` goes through the Dart VM service** (`_flutter.screenshot`), so it
  returns exactly what the engine painted. No Screen Recording permission, no
  other window can cover it, and it works while the app is in the background.
  `window` uses `screencapture -R` instead when you need to see native chrome.
- **Clicks are CGEvents.** AppleScript's `click at` is accepted and then
  ignored by the Flutter window — it looks like nothing happened. The Swift
  driver in `scripts/dev/mouse_events.swift` posts real HID events; the script
  compiles it on demand into `.tmp/dev-tools/mouse`.
- **Coordinates begin as physical frame pixels** — the same numbers read from
  the current `shot`. The default app backend queries the live DPR and converts
  them to Flutter logical coordinates. The CGEvent backend independently maps
  them into current window points and offsets Y for the title bar. Neither
  mapping permits coordinate reuse after the rendered state or geometry moves.
- **Always target the debug app by executable path**, never by process name.
  An installed build (`~/Applications/Vinabike`) shares the name
  `vinabike_erp`; targeting by name silently drives the old app and every
  observation is wrong. If two windows appear, check
  `pgrep -f build/macos/Build/Products/Debug`.

### macOS permissions (one time, by the owner)

`System Settings → Privacy & Security → Accessibility` must list **both**
Claude entries:

- `Claude` — the desktop app.
- `claude` (lowercase) — the Claude Code helper at
  `~/Library/Application Support/Claude/claude-code/<version>/claude.app`.
  **This is the one that actually runs the agent's shell**; with only the
  uppercase entry enabled every call fails with
  `osascript is not allowed assistive access (-1719)`.

Screen Recording is only needed for `app_control.sh window` and for reading
the Design window.

## 3. Looking at Claude Design — never for values

> **Values come from `DesignSync`, not from this window.** Colour, radius,
> shadow, border, spacing, font and height are read out of the Design file with
> `DesignSync get_file`, which returns them literally. Reading them off a
> capture, or estimating them, is prohibited — see
> [`DESIGN_HANDOFF_SYNC_CONTRACT.md`](DESIGN_HANDOFF_SYNC_CONTRACT.md), which is
> the norm this section is subordinate to.

This window is for exactly two jobs:

1. **Seeing what the file API truncates.** A canvas page is capped at 256 KiB;
   sections past the cut exist only here. Anything taken this way is marked
   unsourced in the code until it can be read from a file.
2. **Confirming a built result** against the design, the same way app
   screenshots confirm a change.

```bash
scripts/dev/design_window.sh shot
scripts/dev/design_window.sh scroll -8
scripts/dev/design_window.sh pages       # page selector, then Esc to close
```

Design is a **window of the Claude app**, so it is raised by window name and
captured by frame. Two absolutes:

- **Never capture the full screen.** The desktop holds unrelated private
  windows (mail, chats). Capture the Design window's frame only.
- **Read-only.** Typing into Design's composer or sending a message is acting
  on the owner's behalf and needs explicit permission each time.

**The trap this section exists to prevent** (2026-07-30): an agent walked this
window with `shot`/`scroll` to "see" a popover, then wrote a surface out of its
own head — wrong shadow, wrong radius, and a shadow nested inside a clipping
`Material` so it never painted at all. One `get_file` on the component guide
returned the real ladder in seconds:
`popover 0 6px 22px rgba(12,37,55,.13)`. Scrolling to look is slower *and*
wrong.

### Sending a prompt to Design (only with per-message permission)

When the owner explicitly asks for a prompt to be typed and sent, paste it —
never `osascript … keystroke` the body, which mangles anything non-ASCII.

```bash
printf '%s' "$(cat prompt.txt)" | \
  __CF_USER_TEXT_ENCODING=0x1F6:0x8000100:0x8000100 pbcopy
osascript -e 'tell application "System Events" to keystroke "v" using command down'
```

**The accent trap, with its real cause.** This account's
`__CF_USER_TEXT_ENCODING` is `0x1F6:0x0:0x0` — the trailing `0x0` is
**MacRoman**. `pbcopy` puts the correct UTF-8 bytes on the pasteboard but
*declares* them MacRoman, so Design renders `CORRECCIÓN` as `CORRECCI√ìN` and
`además` as `adem√°s`. `pbpaste` round-trips fine and hides the bug — the
bytes were never wrong, only the declared flavour. Override the variable on
the `pbcopy` call itself (`0x8000100` = UTF-8); exporting it later is too
late. This cost a full round on 2026-07-30 and again on the T8 prompt.

Two more things worth knowing: a long paste lands as a **"Pasted text"
attachment chip**, not inline text — that is normal and Design reads it; and
if a bad paste is already attached, remove it with the chip's `✕` before
pasting again or the message goes out twice.

## 4. iOS Simulator — phone verification

Use the `mcp__Claude_Code_iOS_Simulator__control` tool. Order matters:

1. `attach` **first** — it opens the live panel instantly on a booted device
   and surfaces the one-time device-access prompt while the owner is present.
   On a cold machine it returns a clear error; boot or build, then retry.
2. `build` (`mcp__Claude_Code_iOS_Simulator__build`) or the repo's own build
   command produces the `.app`.
3. `launch` with the built `.app` path.
4. `screenshot`, `tap`, `swipe`, `text`, `touch_path` to drive and verify —
   these are headless and do not need the panel.

Notes that save time: coordinates are **device points**, origin top-left, and
`launch` reports the device's point size. A `swipe` starting within 4 pt of an
edge performs the OS gesture (back, notification shade, Control Center), not a
drag — start further in when scrolling content near a bezel. The Simulator
cannot be replaced by resizing the macOS window when what you are checking is
touch targets, safe areas or the software keyboard.

This tool drives **simulators only**. "On my iPhone" means building for the
device with the normal toolchain; say so instead of silently using a simulator.

### Website Builder phone keyboard smoke

The editor has an auth-free integration harness for the exact compact host,
CTA contextual sheet and iOS software-keyboard inset. Reuse it instead of
copying a Supabase session into a simulator:

```bash
fvm flutter test \
  integration_test/website_phone_authoring_ios_smoke_test.dart \
  -d <simulator-udid> --reporter expanded
```

Disconnect **I/O > Keyboard > Connect Hardware Keyboard** for this smoke, then
restore it afterward. The test unregisters Flutter's synthetic text input,
focuses the real field and requires a non-zero iOS `viewInsets.bottom`; it also
proves that the sheet and `Listo` end above the keyboard.

For a host-side PNG, use the checked-in extended driver:

```bash
fvm flutter drive \
  --driver=test_driver/website_phone_authoring_ios_smoke_test.dart \
  --target=integration_test/website_phone_authoring_ios_smoke_test.dart \
  -d <simulator-udid>
```

It writes `/private/tmp/website-phone-authoring-ios-keyboard.png`. A plain
`simctl io screenshot` taken while `flutter test` runs is misleading: XCTest
can present its own `Test finished` surface even while the Flutter test is
still reporting. Use the integration screenshot and the measured inset, not
that external frame.

## 4.b El escritorio dibuja a **0,8**: la captura no está en el espacio del spec

**2026-08-18, costo real: casi «arreglo» una columna que ya era correcta.**

`WindowZoomService._defaultScale` es **0,8** —el dueño lo pidió así, «equivalent
to pressing Cmd- twice»— y `window_zoom_scope.dart` lo aplica con un
`Transform.scale` sobre **todo** el contenido de escritorio. La consecuencia no
es cosmética: la captura y el spec hablan **dos idiomas distintos**.

- `shot` y `find` devuelven **píxeles pintados**: ya multiplicados por 0,8.
- `read` (árbol de semántica) devuelve **tamaños lógicos**: sin multiplicar.
- El contenido compone contra `ancho de ventana / 0,8`. Con la ventana en 1681
  el módulo no ve 1681, ve ~2101, y por eso elige composición de escritorio
  donde la captura «parece» de tablet.
- Bajo 900 px de ancho de ventana el scope aplica escala **1,0**
  (`appliedScale = constraints.maxWidth < desktopMin ? 1.0 : scale`), así que
  las capturas de teléfono y tablet **sí** son 1:1.

Síntoma exacto: el paso Necesidad medía **621 px** en la captura y el handoff
declara `column_max: 780`. No había defecto — 780 × 0,8 = 624, que es lo que
`find` devuelve para el `SingleChildScrollView` de la columna, y el árbol de
semántica confirma 780 lógicos para la misma fila. Sin esta corrección, cada
medida de escritorio parece un 20 % chica y se «corrige» geometría que ya
cumplía el contrato.

Regla: **para contrastar con un spec, divide la captura por 0,8, o mide con
`read`, que ya viene en lógicos.** Y nunca elijas el breakpoint mirando el
ancho de la captura.

## 5. Cost discipline

The mechanism is cheap; **looking** is what costs. A screenshot is ~2 k
tokens of context, a hot reload is a few hundred bytes of log.

- Verify by text first: `flutter analyze`, the focused suites, and
  `native_session.sh errors`. Hundreds of these fit in one screenshot's budget.
- Capture only when the judgement is visual: layout, hierarchy, colour,
  density, overflow.
- Navigate blind, capture at the end. Do not screenshot after every click "to
  see if it worked" — the next capture already proves it.

## 6. What still needs the owner

- Granting the two Accessibility entries (once).
- Stopping their own VS Code debug session before the agent starts one.
- Destructive financial/data repair, credential rotation, an ambiguous target,
  or a materially broader publication. Normal reviewed deployment and database
  rollout that complete an implementation/fix/ship are agent-owned and are
  routed from Claude to Codex when the Claude guard denies them.
- Anything typed into Design, or any message sent on their behalf.

## `shot` no ve el navegador integrado, ni ninguna vista nativa (2026-08-23)

`app_control.sh shot` pide `_flutter.screenshot` al VM service, así que devuelve
**el frame que dibuja Flutter**. El navegador integrado es un `WKWebView`: una
vista nativa que macOS compone *encima* de la superficie de Flutter. En ese
frame no existe, y sale **en blanco siempre** — haya cargado la página o no.

**El costo real:** reporté dos veces al dueño que el CTA «Entrar al portal»
abría el sitio y la página quedaba en blanco, como posible defecto del producto.
No lo era: teknobike.cl cargaba perfecto y él lo vio en su propia pantalla. Dos
rondas perdidas y un defecto inventado.

Para cualquier superficie compuesta por el sistema —navegador integrado, visor
de PDF, video, mapas— la captura es `app_control.sh window`, que hace
`screencapture` del marco real de la ventana. Cuesta permiso de Grabación de
pantalla y la ventana no puede estar tapada, pero es lo único que muestra lo que
el operador ve.

Regla corta: **si lo que quieres verificar no lo dibuja Flutter, `shot` no
sirve como evidencia de que falta; sólo prueba que Flutter no lo dibujó.**
