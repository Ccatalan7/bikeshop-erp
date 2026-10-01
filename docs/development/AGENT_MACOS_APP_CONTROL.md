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

**Un `final` global ya leído tampoco se recalcula (2026-09-27).** Un índice
top-level o `static final` armado desde una lista `const` —
`_contractsByFamilyAndKey` sobre `kServiceQuestionContracts`— se inicializa la
primera vez que se lee y el reload no lo vuelve a correr: la lista nueva
compila, las pruebas pasan, y la app sigue usando el índice viejo. En F.2
«Tipo de eje» siguió saliendo en «De este servicio» después de pasar a
destino ficha, y casi se reportó como defecto del código. Si el cambio toca
una lista de configuración que alimenta un índice así, el `restart` es el
camino corto; después del reinicio las coordenadas de antes ya no sirven
(`shot` nuevo antes de cualquier `click`): reutilizar una del frame anterior
abrió la ficha de un producto en vez del buscador del trabajo.
Reincidencia el 2026-09-28: `kIsoWheelBsdOptions` era un `final` derivado de
un mapa y el editor siguió mostrando la lista vieja de 15 BSD tras el reload
(una ronda de verificación). Si la lista la escribes tú, hazla `const`
explícita en vez de derivarla: el reload sí la actualiza y no hay que
reiniciar ni rehacer la navegación.

## The three surfaces, and when to use each

**2026-09-06 — model and draft transitions during hot reload.** The product ficha
introduced constructor fields and controller listeners while an older editor
was open. Reload does not rerun constructors or `initState`: old instances
returned null for new non-null fields, and model edits did not refresh reference
choices until listeners were rebound. Use a backward-compatible field read and
fresh metadata hydration; rebind the affected listeners idempotently in
`reassemble` when preserving that already-open editor. Do not restart merely to
make the problem disappear. Capture the old draft before refreshing a new
category/revision key. The first refresh here lost the user's unsaved test
selections (stored product data was unchanged); the corrected transition was
verified by refreshing HV408 with 6/7/8, 11/128 and 7.1 still selected, then
binding/unbinding a reference without discarding those manual values. See the
[result](product-specs-research-2026-09-05/implementation-result.md). This is a
specific preserved-session transition, not a reason to add reassembly hooks to
every widget.

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

**Y cuando `type` sí llega (2026-09-19), puede llegar a otro lado.** Un clic
por coordenada sobre un campo no garantiza el foco: las letras cayeron en el
buscador global de la app, que se abre con cualquier tecla, y quedaron
escritas ahí («Esunaportedecapitalmio…», sin espacios). Se cierra con
`key 53`. `enter-text --label` tampoco sirve para un campo cuyo rótulo es el
`labelText` del `InputDecoration`: ese `Text` no es editable ni tocable. Hace
falta la `ValueKey`; si la llave lleva un id interno
(`bank-reconciliation-ai-answer-<sha12>:<fila>`), se calcula con la misma
sonda que usa el servicio sobre el PDF, en vez de probar coordenadas.

**Una tecla con Mayúscula no abre el buscador; escríbela dentro de él
(2026-09-26).** Las acciones rápidas se abren con «/», que en el teclado
español es Mayúscula+7. `keystroke "/"` enviado sin un campo enfocado se
pierde a ratos —1 de cada 5 en una medición; cero veces con una letra—, y
se parece exactamente a «el atajo no captura»: costó tres rondas buscando
el defecto en `GlobalSearchShortcut`. Abre el buscador con una letra (`a`),
bórrala (`key 51`) y escribe `/tarea` ya dentro del campo enfocado. Antes de
cada tecla, pon la app al frente por su PID; y lee el resultado con `read`
(«ACCIONES RÁPIDAS»), no lo supongas.

**`read` ve más que `find`.** `read` recorre la semántica, que incluye las
filas que un `ListView` mantiene en caché fuera de pantalla; `find`, `tap` y
`enter-text` sólo aceptan lo que el hit test alcanza. Si `read` muestra la
fila y `find` dice «sin coincidencias», la fila está arriba o abajo del
viewport: desplaza **sobre la lista** (`scroll X Y N`, positivo sube, negativo
baja) y vuelve a buscar.

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

**2026-09-04 — Galería y Archivo no exponen el mismo panel nativo.**
`ImagePicker` puede abrir un `AXSheet` con descripción `open` dentro de la ventana,
mientras `FilePicker` abre una ventana `Open`. El wrapper reconoce ambas formas
antes de enviar teclas y al comprobar el cierre. Buscar sólo ventanas por nombre
rechazaba una Galería correctamente abierta; no era un fallo del adjunto.

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

**Varios archivos a la vez (2026-09-18).** Para un selector que acepta
varios (Conciliación bancaria → «Elegir archivos»), copia sólo los archivos
deseados a una carpeta propia y pasa **la carpeta**:
`app_control.sh choose-file /ruta/a/la/carpeta`. El owner entra a la carpeta,
selecciona todo y abre. Dos trampas, cada una costó un intento: sin la `/`
final, «Go to Folder» se queda en la carpeta padre con la carpeta resaltada y
`Cmd+A` elige los archivos del padre (una captura de pantalla terminó enviada
a Veryfi como si fuera una cartola); y en la vista de columnas el foco queda
fuera de la carpeta, así que `Open` sigue deshabilitado hasta mover el foco
con la flecha derecha. El owner ya hace las dos cosas.

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
  **Read that list before choosing the index (2026-09-02).** `tap --label
  Archivos --index 0` hit the sidebar module «Archivos» and replaced the
  owner's workspace tab; the chat-panel tab I wanted was not in the list at
  all, because its text carries a count badge. `--index 0` is not "the one I
  mean", it is "the first thing that matched". When the target is missing
  from the list, use `click X Y` from the current frame instead.
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

**2026-09-18 — `find` imprime lógicos; `click` y `scroll` piden píxeles del
`shot`.** Pasarle a `click` el rectángulo que dio `find` lo manda a la mitad de
la pantalla en Retina (DPR 2): tres clics perdidos sobre «Resolver» de una fila
de la conciliación. Si `find` lista el objetivo, se toca con
`tap --label … --index N`; `click` sólo con coordenadas leídas del `shot`
actual.

**2026-09-15 — una coincidencia única puede ser el control equivocado.** La
búsqueda por etiqueta admite subcadenas: `Productos` dentro del formulario
coincidió con el texto del interruptor «Los productos inactivos…», no con el
módulo de inventario, y cambió el estado activo del borrador. Se cerró sin
guardar y una lectura autenticada confirmó el estado original. Ante una
etiqueta corta o un cambio de contexto, ejecutar `find`, comprobar la etiqueta
completa y el tipo de control, y sólo entonces `tap`. La unicidad no sustituye
esa identificación. En esta misma sesión, los clics AX movían el foco sin
activar `Añadir configuración`; el backend `app` del wrapper sí produjo el
cambio comprobado en la semántica y en un frame actual.

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

If restoring the current route can trigger production writes, arm and verify
the repository's no-write seam **before** any hot restart. A restart rebuilds
the isolate and may restore the routed workspace immediately, before an agent
can navigate it somewhere harmless; parking the old frame is not protection
against that restoration. After the restart, prove the seam is active before
opening the write-capable surface and read the affected production invariant
back again when the visual round ends.

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

**2026-09-07 — empty OCR tree is not evidence of a blank app.** In the live
Flutter 3.38.5 session, closing the supplier picker over `DataTable` could
produce the SDK assertion `owner!._nodes.containsKey(id)` in
`RenderTable.assembleSemanticsNode`, followed by an empty `read`. Fresh frames
still showed the completed supplier selection and code edits. Check the
exception and verify the changed value in a new frame plus identity-based
input before calling the business operation stuck. Keeping a persistent
semantics handle passed an isolated test but did not recover this session;
that exploratory patch was removed. The SDK/reader failure remains open.
Do not restart the owner's session to investigate it while other workspaces
contain unsaved edits.

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

**Precisión 2026-08-30: recuperar un raster atrasado sin reiniciar.** En una
prueba del Asistente de compras, enfocar la ventana debug y ejecutar su acción
AX `Raise` no bastó: dos `shot` seguían mostrando el borrador anterior mientras
`read` ya anunciaba el nuevo. Con la identidad y geometría de la ventana
canónica comprobadas, cambiar temporalmente su ancho de 1455 a 1454 mediante
`app_control.sh resize` produjo un frame actual; después se restauró 1455. Es
un recurso acotado a ese síntoma, no un paso obligatorio de cada captura.
Verifica visualmente el frame resultante contra la semántica y restaura la
geometría; no aceptes las capturas atrasadas como evidencia ni recargues el
estado de trabajo para resolver sólo el repintado. El costo observado fueron
dos capturas inválidas, no una regresión del formulario.

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

**Bloqueo medido 2026-09-30, Xcode 27 + runtime iOS 26.5 en este Mac:** el
proyecto Runner todavía declaraba iOS 14 aunque el Podfile exigía 16. Se
alinearon `Runner.xcodeproj` y `AppFrameworkInfo.plist` a 16 y el build
genérico del simulador terminó. Aun así, los Pods de MLKit excluyen arm64 del
simulador, por lo que el ejecutable resultó sólo x86_64. Instalarlo en el
iPhone 17e estándar arrancado como arm64 funcionó, pero `launchd_sim` negó
el arranque con `EBADARCH` (Bad CPU type). Arrancar ese dispositivo con
`simctl boot --arch=x86_64` tampoco dio una sesión utilizable en esta ronda;
se apagó. El viejo dispositivo `Vinabike iPhone 17 Pro x86` no es un atajo:
su falta de display está documentada en
`PAYROLL_5N_TRANSITION_MATRIX_2026-08-02.md`. **No calificar una pantalla de
teléfono por un build o instalación exitosos.** Antes de repetir este smoke,
verificar soporte real de un conjunto de dependencias para arm64-simulator o
un runtime x86 con display. La [lista oficial de problemas conocidos de
ML Kit](https://developers.google.com/ml-kit/known-issues) todavía indica
(actualizada el 2026-09-24) que sus simuladores en Mac M1 no son compatibles;
no asumir que un cambio de `EXCLUDED_ARCHS` o una subida de versión de Pods
lo resuelve. Un arnés iOS sin ML Kit puede verificar el widget y los insets,
pero no califica el binario completo ni su ruta autenticada. La prueba sin
Auth/Storage para ese arnés ya está en
`integration_test/workshop_completion_ios_smoke_test.dart`.

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

## 4.c Emulador Android: lo nativo sin sesión, la pantalla con una vista previa (2026-09-29)

El Mac tiene el AVD `Medium_Phone_API_36.1`; se arranca sin ventana
(`emulator -avd Medium_Phone_API_36.1 -no-window -no-audio -no-boot-anim`
en segundo plano) y se maneja con `adb`. La app corre contra producción y un
agente no escribe contraseñas reales, así que contra producción el emulador
**no tiene sesión** (desde el 2026-09-30 sí la tiene contra el stack local: ver
«Con sesión, contra el stack local» abajo). Sin sesión se prueba en dos capas:

- **Lo nativo, de verdad.** Intents, copias, permisos y el ciclo de las
  actividades no necesitan sesión: `run-as com.vinabike.erp ls -lR <carpeta>`
  (build debug) muestra lo que quedó, y
  `dumpsys activity activities | grep "Hist.*vinabike"` cuenta las
  `MainActivity` (tiene que haber una).
- **La pantalla, con una entrada desechable.** Un `main` de vista previa en
  `build/preview/*.dart` (ignorado por git) monta el widget real con datos de
  ejemplo: `flutter build apk --debug --target-platform android-arm64 -t
  build/preview/x.dart`. Es un render real en Android, con fuentes reales;
  se borra al cerrar la ronda.

Trampas que costaron una vuelta cada una:

- **`adb shell am start --grant-read-uri-permission` no sirve para fotos de la
  galería:** el shell no tiene permiso sobre MediaStore y la concesión se
  rechaza en silencio (el receptor recibe el intent y no puede leer nada). Un
  envío real se hace desde la app Archivos (`com.google.android.documentsui`):
  mantener pulsado, tocar los demás, Compartir. Manejarla por identidad con
  `uiautomator dump` (texto/`content-desc` → centro del `bounds`), nunca por
  píxeles.
- **El shell remoto expande `*/*`.** `adb shell cmd package query-activities -t
  '*/*'` pregunta por otra cosa; hay que citar dentro de la línea remota:
  `adb shell "cmd … -t '*/*'"`.
- **El emulador se llena**: con ~450 MB libres `installd` purga la caché de las
  apps al minuto y `adb install -r` falla con `INSTALL_FAILED_INSUFFICIENT_STORAGE`
  (necesita espacio para dos APK de ~190 MB). `pm trim-caches 2G` y, si no
  alcanza, `adb uninstall com.vinabike.erp` antes de instalar.
- **Recién instalada, la app no sale en la primera fila del menú Compartir**:
  Android la ordena por uso. Está en la lista completa (deslizar la hoja hacia
  arriba); después del primer uso sube sola.
- **Dos entradas de la misma app se agrupan** bajo el nombre de la app
  («vb-ERP ▾»); `uiautomator` no ve «WhatsApp ERP» hasta tocar el grupo, que
  abre un diálogo con las dos. Con una sola entrada se ve su propio `label`.
- **Un video de prueba grabado con `screenrecord` pesa nada** si la pantalla
  está quieta (12 s a 20 Mbps dieron 168 KB). Para probar compresión se arma
  uno de verdad en el Mac con `avconvert --preset Preset1920x1080 --source
  "/System/Library/Wallpapers/.default/Golden Gate.mov" --output x.mov` (hay
  uno vertical en `/System/Library/Desktop Pictures/.wallpapers/Sonoma/`), y
  se mide la salida con AVFoundation (`naturalSize` + `preferredTransform`) en
  un `swift` de una página. El codificador del emulador queda bajo la tasa
  pedida (1,3–1,5 Mbps por 4); un teléfono real la respeta mejor.
- **El gate corre en Linux**: `Platform.isMacOS` en una prueba pasa en el Mac y
  falla en CI. Lo que dependa del sistema anfitrión se fija en la prueba
  (`debugCanShareFilesOverride`).

### Con sesión, contra el stack local (2026-09-30)

`scripts/e2e/run_android_local_journey.sh --journey task-form|workshop` es el
lanzador común (`run_task_form_android_local.sh` quedó como atajo): un APK debug de
`lib/main.dart` con los defines **públicos** del stack local (JSON privado que
se borra al compilar), sellado con la URL y la huella de la llave; nunca se
instala uno sin sello. `adb reverse tcp:54321 tcp:54321` deja al emulador usar
`http://127.0.0.1:54321` igual que el Mac: no hace falta tocar el bootstrap por
`10.0.2.2`, porque `network_security_config` ya admite HTTP local. Las cuentas
sintéticas las crea la API de administración y cada recorrido es un driver
Python sin dependencias sobre `scripts/e2e/android_ui.py` (árbol, gestos,
frames, selector del sistema, login y tema), que toca por nombre leyendo
`uiautomator dump`. Un recorrido nuevo agrega su driver, su fixture y un
caso en el lanzador; no copia el lanzador. La primera compilación bajó ~7 GB a
`~/.gradle/caches` en 519 s; las siguientes, 27 s. `--reuse-apk` reusa un APK
sellado para el mismo stack. Si el emulador ya está arriba, el lanzador lo
reusa y no lo apaga: arrancarlo a mano ahorra ~1,5 min por corrida al iterar.

**`--hold` y `--release` (2026-09-30).** Con `--hold`, si el driver falla, la
app queda con su sesión y el taller sintético como quedaron: se sigue desde ahí
con las funciones de `android_ui.py` (un `python3 -` que importa el módulo con
`ANDROID_E2E_SERIAL`/`_ADB`/`_PACKAGE`/`_FRAMES_DIR` en el entorno) en vez de
rehacer login, cliente, bici y líneas en cada vuelta. `--release` retira lo
retenido (app, archivos, reverse y fixture). El recorrido del taller se
descubrió así, paso a paso, en una sola sesión retenida; después se escribió el
driver con los nombres reales. `--surface web` corre el mismo recorrido, con
las mismas cuentas, fixture, readback y retirada, en Chrome de escritorio
(`e2e/workshop_local.spec.ts`; trampas en `WEB_PREVIEW.md`): el escritorio
nativo de macOS no se usa mientras su sesión debug sea del dueño.

Lo que costó una corrida cada uno:

- **Cómo nombra Flutter los nodos en Android 9+.** Un `IconButton` con sólo
  `tooltip` recibe el tooltip como `content-desc` (el embedding lo copia cuando
  no hay etiqueta); con etiqueta y tooltip, sólo la etiqueta. Un campo con valor
  se llama «valor + pista» (la pista va en `hint`): se busca la pista al final.
  Un botón suma el texto de sus hijos: «Ver detalles de X X Detalles».
- **Nunca «el nodo más chico que contiene el título».** En la lista de tareas
  es el `CheckBox` «Marcar X como completada», y tocarlo completó la tarea. Se
  toca la acción propia de la fila («Ver detalles de X»).
- **El fondo modal también se llama «Cerrar»** y cubre toda la pantalla: tocar
  su centro cae sobre el diálogo. Se filtra por `class=Button`.
- **Lo que está fuera de la vista no está en el árbol.** En teléfono el
  formulario de tarea mide 700 px lógicos: «Guardar» y los adjuntos quedan bajo
  el borde, y al reabrir con `focusAttachments` el título «Editar Tarea» queda
  arriba; se reconoce por «Actualizar». Contar «Pendiente» sin desplazar da 0, y
  «Pendiente» a secas debe ser exacto (existe «Estado Pendiente»).
- **Diálogos del sistema.** Con 2 GB el AVD avisa «System UI isn't responding»
  al arrancar («Wait»); la primera apertura pide notificaciones («Don’t
  allow»). Con la pantalla apagada `uiautomator` devuelve `null root node`:
  `input keyevent 224` y `wm dismiss-keyguard` tras el arranque.
- **Atrás cierra la app en el panel.** El tema en teléfono está en menú
  principal → «Apariencia» (una hoja); atrás sólo mientras la hoja está abierta
  y el menú con «Cerrar menú». Atrás sin teclado cierra el diálogo o sale de la
  página, así que «hay teclado» se lee bien: `mImeWindowVis` (bit 2) o
  `mInputShown=true` en `dumpsys input_method`. **`mIsInputViewShown` miente**:
  en Android 16 queda en `true` con el teclado ya oculto (2026-09-30), y con él
  «bajar el teclado» mandó atrás y salió de la ficha de la bici.
- **Un teclado que se está cerrando sigue «arriba» un instante.** Al elegir un
  resultado del buscador de ítems el teclado baja solo; el atrás mandado en ese
  medio segundo cae en la página y abre «¿Descartar cambios?» (dos veces el
  2026-09-30). `hide_keyboard()` vuelve a mirar tras 0,7 s antes de mandarlo.
- **Un gesto sobre el teclado escribe.** Gboard desliza letras: un `input
  swipe` para desplazar con el teclado arriba metió una «o» en el título de la
  tarea. `scroll_into_view()` baja el teclado antes de cada gesto.
- **Los buscadores con panel pierden lo tecleado antes del panel.** El campo
  «Agregar repuesto o parte» abre su panel («Motor de compatibilidad») después
  del primer toque; lo que `input text` mandó antes no llega. Se toca, se
  espera el panel y recién se teclea.
- **Un menú emergente entra al árbol al terminar de abrirse**: un `dump`
  inmediato no lo ve. Se espera por su opción, no por el tiempo.
- **El «Cerrar» de una hoja inferior es su asa de arrastre**: cierra con la
  acción semántica (TalkBack), no con un toque; `input tap` no hace nada. La
  hoja se cierra tocando el «Sombreado» o eligiendo una opción.
- **Un panel a pantalla completa no saca del árbol lo que tapa.** Con «Ver la
  tarea» abierto (panel de herramientas) la lista del taller sigue en el
  `dump` con sus coordenadas: esperar «Vista:» dio por cerrado el panel y el
  toque cayó sobre él. Se espera a que desaparezca el panel mismo
  («Tareas, herramienta…»).
- **Un gesto para apartar un aviso empieza sobre el aviso**: desde más arriba
  desplaza la lista y el aviso queda.
- **Un aviso con acción queda fijo en Flutter 3.38** (`SnackBar.persist` vale
  `true` cuando hay `action`) y en teléfono tapa la hoja «Cambiar vista» y la
  lista hasta tocarlo. No es una trampa del driver: se corrige en el aviso con
  `persist: false` (el de «Presupuesto aprobado», 2026-09-30), y el recorrido
  anota si se fue solo.
- **El primer `cmd uimode night yes` tarda más de 2 s en pintarse**: la captura
  «oscura» salió clara. Se espera a que el `screencap` difiera del claro y quede
  quieto.
- **DocumentsUI multiselección**: los archivos copiados con `adb push` y
  `content call --uri content://media --method scan_file --arg <ruta>` salen en
  «Recent»; mantener el primero, tocar el segundo, esperar «2 selected» y
  «Select».

El gate focal C3/C4 (2026-09-30, `.tmp/e2e/android-workshop-20260930-143342`)
agregó:

- **Una tarjeta sin semántica por fila es un solo nodo.** La memoria técnica de
  la bici publica todo su texto en un nodo: `scroll_into_view` lo da por visto
  en cuanto asoma su borde superior y la fila buscada (el servicio, última de
  la tarjeta) queda bajo la pantalla; así salió el frame 16 del 095345.
  `reveal_end()` desplaza hasta que el borde inferior del nodo quede dentro
  de su área. **Recortado, el nodo informa el borde del área, no el suyo**, y
  si es más alto que el área conserva los mismos bordes aunque el contenido
  se mueva: el avance se mide comparando `screencap`, no bordes.
- **El historial de la bici desplaza su propia área, bajo las pestañas** (en
  1080×2400 empieza en y≈1234). Un `swipe_down()` genérico empieza en y≈912,
  sobre las pestañas, y no mueve nada; los gestos van dentro del área.
- **El mapa con pines animados no deja asentar el oscuro** («la app no cambió
  a oscuro»): la captura se toma con el mapa fuera de la pantalla.
- **`input text /tarea` de una vez perdió dos teclas** («/taa»): la primera
  tecla abre el buscador global y lo que llega mientras se abre se pierde en
  ocasiones. `open_action()` manda «/», espera el campo con foco, escribe el
  resto y comprueba su valor.
- **La ficha del trabajo en teléfono** dice «Ficha del trabajo» en su
  cabecera (en escritorio, «Editar Trabajo»), y su sección «Adjuntos» muestra
  las miniaturas como `ImageView` sin botón «Adjuntar archivo».

**El recorrido del taller necesita más que el esquema de referencia
(2026-09-30).** `workshop_journey_local_fixture.sql` en modo `preflight` lo
exige por nombre y el lanzador no sigue sin eso:

- **El motor de fichas.** La base local nace sin `spec_facts` ni los lectores
  (`spec_active_product_values_internal_v1`, `product_spec_bindings_internal_v1`,
  `get_product_spec_contexts_v1`), aunque sí trae las funciones de cambio de
  partes que los llaman: sus pgTAP reemplazan el lector dentro de la
  transacción, así que pasan igual. Sin el motor, un repuesto no dice su medida
  y el cierre no revisa nada. Se instala con el replay de
  `docs/development/product-specs-research-2026-09-05/local-engine-restore-2026-09-16.md`
  (sección del 2026-09-30).
- **El BSD del neumático.** Las publicaciones de familias no pueden aplicarse en
  local (exigen los ids de producción); `supabase/tests/fixtures/part_change_tire_bsd_local_seed.sql`
  agrega la definición de producción y su campo en la plantilla `tire`.
- **El cierre como en producción.** El `handle_mechanic_job_change` de la base
  de referencia descuenta stock y asienta al terminar un trabajo; el de
  producción no. `supabase/tests/fixtures/job_lifecycle_production_local_seed.sql`
  pone los tres cuerpos de producción (el preflight compara el del cierre por
  md5).

Antes de compilar, el lado del servidor se ensaya sin la app: la misma historia
con el rol de mecánico, en una transacción que se revierte (cierre rechazado
por el neumático que no calza, corregido, encargo a la compañera). Costó
minutos y encontró lo que una corrida nativa habría encontrado en horas.

La retirada no nombra tablas ni decide su orden: borra las filas del taller
sintético tabla por tabla (toda tabla con `tenant_id`), suspendiendo sólo
para ese borrado el disparador de inmutabilidad de la tabla (anota cuál y
cuántas filas) y reactivándolo enseguida. Un borrado que choca con una llave o
una guardia porque otra tabla todavía apunta a sus filas se deshace entero,
disparador incluido, y se reintenta en la pasada siguiente; si una pasada no
avanza, falla con el último error. Después recorre todas las tablas con
`tenant_id` y exige cero filas. Una ficha de empleado con acceso al ERP no se
borra mientras siga ligada (`employee_erp_unlink_required`): primero
`user_profiles` y `user_id`. Historia: la primera versión nombraba cuatro
tablas de eventos y el libro de estados la detuvo; la segunda suspendía
disparadores en un orden cualquiera y, cuando el recorrido empezó a facturar
(2026-09-30), la detuvieron tres veces seguidas `inventory_accounting_checkpoints`
(que nombra la operación de inventario), la guardia de la bandeja al soltar la
bici de una tarea (23514) y la traza de inventario al anular el cliente de la
factura (P0001). Ninguna era un defecto: era el orden.

**El recorrido del taller en teléfono, como es (2026-09-30).** Lo que un driver
escrito desde el código suponía y la app no hace:

- La bici nueva no se guarda sin familia de pedalier: «Guardar» devuelve a la
  sección 3 (`Sistema técnico` → `Pedalier / BB` → «Familia pedalier / BB»).
- Un trabajo nuevo nace «Presupuestar primero»; el presupuesto aprobado es de
  sólo lectura hasta facturarlo («Más» → «Facturar presupuesto» → «Crear
  factura»). Un cierre rechazado sobre un presupuesto sin facturar lleva a
  líneas que no se pueden corregir: se factura antes.
- El estado se cambia desde el chip de la fila («Cambiar o abrir estado»).
- «Solo compatibles» esconde el neumático que no calza; «Mostrar todo» lo
  muestra como «No compatible». Elegir la rueda de la línea («Sin fijar lado» →
  «Delantero»/«Trasero», `CheckBox`) es lo que deja la marca que la ficha
  aplica al terminar.
- «Cambiar por otro artículo» deja la línea sin lado: se vuelve a elegir.
- /tarea en la lista: los cuatro pasos (persona, trabajo, qué hacer, revisar) y
  «Ver la tarea» abre el panel de herramientas con dos «Volver».
- La ficha de la bici se lee desde la clienta («Abrir cliente …» → «Abrir
  bicicleta …»); «Abrir Bicicleta: …» en la fila abre el editor.

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

## Probar un atajo de teclado: tres trampas, una detrás de otra (2026-09-17)

Verificar `⌘K` y «escribir abre el buscador» costó cuatro rondas, todas gastadas
en el arnés y ninguna en la app. En orden:

**1. La app instalada contesta por el mismo nombre.** Hay dos procesos vivos:
la Release instalada (`com.vinabike.vinabikeErp`,
`~/Applications/Vinabike ERP.app`) y la sesión de debug
(`com.vinabike.vinabikeErp.debug`, `build/macos/.../Debug/vinabike_erp.app`).
Pedir acceso por el nombre visible **«Vinabike ERP» resuelve a la Release**, y
su `window_id` acepta clics y capturas sin que nada falle: se está manejando la
app equivocada, con datos reales, creyendo que es la sesión. Se pide el bundle
`…​.debug` explícito y se confirma cruzando el tamaño de ventana con el de
`app_control.sh shot`. `lsappinfo list | grep -A3 vinabike` muestra los dos con
su ruta y su pid.

**2. Una tecla sintética por accesibilidad no llega al motor de Flutter.**
`app_batch`/`app_key` entregan «raw input on AXGroup» y el propio resultado
avisa que no hay acción de accesibilidad para esa tecla. Flutter no la ve:
`HardwareKeyboard.instance.addHandler` no se dispara y la pantalla no cambia.
Eso **no prueba que el atajo esté roto**. Lo que sí llega es
`osascript -e 'tell application "System Events" to keystroke "k" using command down'`,
y sólo con el proceso de debug al frente:

```bash
osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is <PID_DEBUG>) to true'
osascript -e 'tell application "System Events" to keystroke "felipe"'
```

Sin el `frontmost`, las teclas se las lleva la app que esté adelante —
típicamente la Release del punto 1 — y el log de la sesión queda mudo. Un
`debugPrint` temporal en el handler más `native_session.sh log` distingue en una
ronda «no llega la tecla» de «llega y la lógica la descarta»; es más barato que
mirar capturas.

**3. `app_control.sh type` se come los espacios.** `type "nueva factura"` llega
como `nuevafactura` y la pantalla contesta que no encuentra nada, que parece un
defecto del buscador. Para texto con espacios se usa
`enter-text --key <clave> --text "…"`, que escribe la cadena completa en el
campo por identidad. (Complementa la nota anterior de que `type` no escribe en
un campo enfocado por identidad.)

**3.b Un campo sin `ValueKey` (2026-09-27): se pega, con UTF-8.** El prompt de
`showVbReasonPrompt` (notas, motivos) no tiene llave, así que ni `enter-text`
ni `type` sirven para texto con espacios. Se pega: guardar el portapapeles del
dueño, `printf '%s' "texto" | LC_ALL=en_US.UTF-8 pbcopy`, `type ""` para traer
la app al frente, `keystroke "v" using command down`, y devolver el
portapapeles (`LC_ALL=en_US.UTF-8 pbpaste` antes y `pbcopy` después, también
con UTF-8). **Sin `LC_ALL`** la shell de agente no trae locale y `pbcopy`
guarda los bytes UTF-8 como MacRoman: «está» llegó a la app como «est√°». Costó
dos notas de prueba con el texto roto en producción (retiradas, pero el ledger
las conserva).

### 4. Cuando las teclas «dejan de funcionar»: mirar el respondedor nativo (2026-09-30)

El dueño reportó que el buscador «funciona con 2 búsquedas, después ya no».
No era el buscador: después de cerrar su panel **ninguna** tecla llegaba a
Flutter —ni a `HardwareKeyboard`, ni a un campo—, sin un solo error en el log.
La pregunta que lo resuelve en una ronda es quién es el primer respondedor de
macOS:

```bash
osascript -e 'tell application "System Events" to tell (first process whose unix id is <PID_DEBUG>) to get role of (value of attribute "AXFocusedUIElement")'
```

`AXGroup` es la vista de Flutter (sano); `AXWindow` es la ventana, y con eso
las teclas se pierden antes del framework. Con un campo enfocado la consulta
falla, y es normal. La causa fue que el campo del panel usaba como controlador
el buffer del atajo, que se vaciaba al cerrar con el campo todavía montado: ver
el comentario de `_GlobalSearchPanelState._text`. Regla: **un `TextField` no
usa un controlador que otro vacía o reemplaza después de cerrarlo**; si hay
que traspasar texto, se copia.

**Trampa de la medición:** entre una llamada y la siguiente, la app de Claude
vuelve al frente, y un ciclo de teclas sin `set frontmost` antes de **cada**
`keystroke` mide teclas que nunca llegaron a la app. Costó dos rondas creer
que el arreglo no servía. El A/B que discriminó: seis ciclos abrir-cerrar con
el buffer compartido → `AXWindow` desde el primer cierre; sin él → `AXGroup`
los seis.

## Un cambio de entitlements no entra por reload ni por restart (2026-09-17)

**Costo real: una ronda entera creyendo que el código nuevo no se había
aplicado.**

`reload` y `restart` reutilizan el bundle ya firmado. Los entitlements se
graban al **construir y firmar** `vinabike_erp.app`, así que agregar
`com.apple.security.files.downloads.read-write` y recargar deja al sandbox
exactamente igual de estricto, con el mismo síntoma de antes: la escritura
falla, la cadena de respaldo la esconde, y desde afuera se ve como «el cambio
no se aplicó». El ciclo correcto es `stop` + `start`, y se comprueba leyendo lo
que quedó firmado, no lo que dice el archivo fuente:

```bash
codesign -d --entitlements - build/macos/Build/Products/Debug/vinabike_erp.app
```

Dos trampas más de esa misma ronda, ambas al verificar un panel **nativo**:

- **`app_control.sh shot` no ve los paneles del sistema.** Devuelve el frame que
  pinta Flutter; un `NSSavePanel` es una ventana de AppKit y no está ahí.
  Para verlo hay que usar `window`, o `screencapture -x` cuando el panel queda
  fuera del marco de la ventana.
- **El panel se abre detrás si la app no está al frente,** y entonces parece que
  nunca se abrió mientras bloquea la app. Antes de clicar algo que abra un panel
  nativo, traer el PID exacto al frente:
  `osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is <pid>) to true'`.
  Su contenido **no** se puede recorrer por accesibilidad —vive en un servicio
  XPC aparte, y `entire contents` viene vacío—, así que se maneja por teclado:
  `cmd+a`, el nombre, `return`. El nombre de la ventana (`Guardar archivo`) sí
  se ve, y sirve para confirmar que está abierto; recuerda apuntar al PID de
  debug, porque el Release instalado comparte el nombre del proceso.

## Probar la bandeja del taller sin cortar la red ni escribir bicis reales (2026-09-28)

Lo que costó una ronda al dar evidencia del ítem 3 contra producción:

- **`evaluate` de la VM no funciona en esta sesión.** Devuelve «No compilation
  service available; cannot evaluate from source»: el servicio que compila
  expresiones es del `flutter run` y no se alcanza por la URL del log. Lo que
  haya que accionar desde afuera va como extensión de depuración registrada en
  `registerAgentInputExtensions()` (`lib/dev/agent_input.dart`), que sí se
  llama por la misma URL (`GET <vm>/ext.nombre?isolateId=…&param=…`). La de la
  bandeja: `ext.vinabike.outbox.armFault?fault=offlineBeforeSend&times=2`
  (o `loseResponseAfterCommit`: escribe y pierde la respuesta y el recibo).
  Una extensión nueva entra con `restart`, no con `reload`.
- **Las preferencias de la app de debug viven en su contenedor.** Se leen con
  `defaults export ~/Library/Containers/com.vinabike.vinabikeErp.debug/Data/Library/Preferences/com.vinabike.vinabikeErp.debug -`;
  el `.plist` en disco va atrasado (cfprefsd lo baja cuando quiere) y leerlo
  directo mostró una bandeja vieja. Un `defaults write` a esa ruta lo ve la
  bandeja **en su próxima lectura, sin reiniciar** (relee las preferencias
  cada vez); así se siembra un estado —por ejemplo el que deja un guardado
  sin red— para probar la reanudación contra el RPC real.
- **Corrección 2026-09-28: un `restart` envía lo sembrado antes de que
  alcances a armar la falla.** El reinicio borra la falla armada (vive en
  memoria) y la reanudación del inicio de sesión corre en seguida, sin espera:
  lo sembrado sale a producción. Para probar lo pendiente sin enviarlo: arma
  la falla, después siembra, y no reinicies; si hace falta cargar código
  nuevo con `restart`, borra antes la siembra (`defaults delete`) y vuelve a
  sembrarla después de armar. Como red de seguridad, un alta sembrada lleva un
  campo que `save_bike_aggregate` rechaza antes de escribir
  («unsupported or server-owned fields»). Costó una vuelta de siembra al
  probar el aviso de alta pendiente.
- **Para reanudar lo sembrado sin `restart`, saca la app del frente y
  vuélvela a traer** (2026-09-28): `osascript -e 'tell application "Finder"
  to activate'` y después `set frontmost` del PID de debug. El
  `AppLifecycleState.resumed` llama `resumeNow()` y la bandeja relee lo
  sembrado; el log muestra `🧰 Bandeja del taller: <tipo>:<resultado>`. El
  aviso de la reanudación dura 8 s: captura con `shot` a los 2–3 s, no
  después de revisar el log (la primera captura del descarte llegó tarde).
  Borra después los intentos `…:a:` de tus llaves de prueba: sin
  `20260928051000` en producción no se vacían solos y subirían al desplegarla.
- **Un comando que el servidor de producción todavía no tiene no se prueba en
  esta sesión** (2026-09-28): la app de debug corre contra producción, así
  que `save_mechanic_job_lines_v1` sin desplegar hace fallar cualquier
  guardado de trabajo. Su prueba es el pgTAP local más el contrato: el pedido
  que arma Dart, pasado por la función local dentro de una transacción que
  se deshace. Abrir un trabajo sí se prueba: reanuda antes lo que la bandeja
  tenga de ese trabajo (con la bandeja vacía no envía nada) y el log muestra
  `Loading job` después; no guardes. Si un guardado de prueba llegó a
  respaldarse, producción lo rechaza al tiro (`PGRST202`, la función no
  existe) y sale de la bandeja; queda sólo su intento `…:a:`.
- **Un cambio de forma en la bandeja pide `restart`, no `reload`.** Un campo
  `final` nuevo que se asigna en el constructor de `WorkshopCommandOutbox`
  queda sin valor en la instancia viva después de un `reload`: el singleton se
  creó antes.
- **Sólo la bici fixture.** La de «Test Taller»
  (`DBG-DRIVETRAIN-NO-PROFILE-…`, del arnés «Prueba rápida») acepta escrituras
  de prueba; su marca y modelo son texto libre, así que el formulario no la
  deja guardar sin elegirlos del catálogo, y crear una marca para eso sería
  ensuciar el catálogo real: se siembra el comando en vez de guardarlo desde
  el formulario.
- **Un conflicto no se prueba contra producción** mientras la función lance
  `40001`: abre un bucle en PostgREST (ver
  `docs/development/AGENT_DATABASE_CONTRACT.md`). Se prueba con pgTAP local.
- **Una decisión de garantía pendiente sí se ve en la app real (2026-09-29).**
  Casi la di por imposible («se enviaría a producción») sin haber leído esta
  sección; el orden que funcionó, sin reiniciar:
  1. Arma `offlineBeforeSend` con `times=20`, el tope.
  2. Siembra el `c:` con `defaults write`, bajo cada `<taller>:<persona>` que
     muestre `vinabike_appearance_v2`; la persona que no está en sesión no se
     lee ni se envía.
  3. Pon `p_operation_key` vacío en `params`. Si la falla se agotara, el RPC lo
     rechaza antes de escribir («requiere una clave de operación»). La llave
     del comando va aparte, en `operation_key`.
  4. Pulsa **Actualizar** en la tabla y la tabla relee lo pendiente. Abrir el
     trabajo gasta una falla y deja un `a:` `offline`.
  5. Al terminar, borra los `c:` y `a:` de tu llave y desarma con
     `fault=none` (queda `×0`).
  6. Confirma en producción que `operation_key like 'dbg-…'` da 0.

  `scroll` sube con positivo y **baja con negativo**; con positivo la ficha no
  se mueve y parece que el scroll no llega.
