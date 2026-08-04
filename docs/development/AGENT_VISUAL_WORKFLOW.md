# Cómo un agente prueba la app y la compara con Claude Design

Este documento es **el procedimiento**, no una lista de herramientas. Si algo
acá contradice a otro documento, gana éste para el ciclo de trabajo, y
`DESIGN_HANDOFF_SYNC_CONTRACT.md` gana para *de dónde sale un valor visual*.

Existe porque el mismo trabajo se improvisó cinco veces con cinco resultados
distintos, y porque cada improvisación costó una ronda: clics que caían donde
no debían, un frame que nadie bajó, un compilador trabado leído como otra cosa.

---

## 0. Las cuatro reglas que no se negocian

1. **Un valor visual se lee del archivo de Design con `DesignSync`.** Color,
   radio, sombra, borde, espaciado, tipografía, altura. Nunca de una captura,
   nunca estimado. Un valor que no se puede leer **se reporta como ilegible**,
   no se reemplaza por uno plausible.
2. **Medir sobre el pixel sólo vale en un frame publicado por Design.** Esos
   PNG son recortes sin reescalar. Sobre una captura de la ventana de Design, o
   sobre un compuesto, medir está prohibido.
3. **Se toca por identidad.** La app corre contra **producción**: un clic que
   cae donde no debe escribe de verdad. Una coordenada se admite sólo para un
   objetivo sin identidad, tomada del `shot` actual y usada de inmediato;
   **nunca se reutiliza** después de navegar, redimensionar o reiniciar.
4. **Estructura de `read`, apariencia de `shot`.** Si un botón está
   deshabilitado o una fila seleccionada, eso se lee de la semántica. Deducirlo
   del color es inventar.

---

## 1. La sesión de debug

```bash
scripts/dev/native_session.sh start      # ~1-2 min la primera vez
scripts/dev/native_session.sh status     # screen + pid + VM service
scripts/dev/native_session.sh reload     # tras editar · 2-5 s
scripts/dev/native_session.sh doctor     # POR QUÉ no responde
scripts/dev/native_session.sh stop
```

### Cuando el reload no vuelve

**Corre `doctor`. No lo diagnostiques a ojo.** Nombra la causa real:

| Lo que dice | Qué significa | Qué hacer |
|---|---|---|
| `hay un reload EN CURSO o colgado` | el log terminó en el spinner | **NO mandes otro**: dos reloads simultáneos se matan entre sí. Espera ~2 min |
| `el VM service no responde` | la app murió | `stop && start` |
| `hay un 'screen -x' abierto` | el dueño está mirando | **informativo, no bloquea nada** |

Ese último es el que engañó el 31/07: un attach del dueño se leyó como la causa
y se perdió una ronda. Un attach nunca impide recargar.

### Cuando `start` se niega

`hay una app debug viva sin sesión screen` significa que quedó un proceso
huérfano de un ciclo anterior. Se cierra por su ventana, nunca con un kill por
patrón:

```bash
P=$(pgrep -f "Debug/vinabike_erp.app/Contents/MacOS/vinabike_erp" | head -1)
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $P) to click button 1 of window 1"
```

**Si eso responde `Can't get window 1 … Invalid index (-1719)`, el huérfano no
tiene ventana** (2026-08-01). Pasa cuando el proceso sobrevive a su propia
interfaz: `status` lo ve vivo, el VM contesta, y no hay nada que cerrar. Un
`quit` de aplicación sí funciona, y no es una señal de proceso:

```bash
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $P) to quit"
```

**No lo resuelvas con `kill`.** El guard lo deniega —«generic process signaling
is blocked»— y tiene razón: apunta a un proceso que puede no ser el que crees.

Dos formas de esa trampa, que juntas cuestan una ronda:

1. **El guard escanea el comando completo.** Un `kill` al final de un bloque
   compuesto hace que se deniegue **todo lo que iba antes**, incluido el `quit`
   que sí habría funcionado. Manda el `quit` solo.
2. **`kill -0` no señala nada** —es la forma canónica de preguntar «¿sigue
   vivo?»— y el guard igual lo deniega, porque lee el verbo, no el flag. Para
   comprobar liveness usa **`ps -p <pid>`**, que dice lo mismo sin la palabra
   prohibida.

Y cuando lo que necesitas es apagar la sesión, la respuesta no es rodear el
guard: es **`native_session.sh stop`**, que es el owner canónico y desde el
2026-08-01 captura y limpia su árbol entero.

### Si la ventana queda tapada, `shot` MIENTE — y no avisa

La trampa más cara del 31/07, y la que hay que revisar **antes** de creerle a
una captura.

Cuando otra ventana tapa por completo la de `vinabike_erp`, macOS la marca
oculta, `framesEnabled` pasa a `false` y el engine **deja de rasterizar**. La
app sigue perfectamente viva: responde el VM service, acepta toques, cambia de
ruta. Lo único que no hace es dibujar.

Y `shot` no falla: devuelve **el último frame que el engine alcanzó a
rasterizar**. Navegué tres pantallas seguidas y las tres capturas salieron
idénticas y viejas, sin una sola señal de que lo fueran. Así es exactamente como
un agente termina afirmando algo falso sobre una pantalla que nunca vio.

Cómo se detecta en un comando —`read` sale en ~0,2 s cuando no hay frames,
porque ni siquiera intenta esperarlos:

```bash
start=$(python3 -c "import time;print(time.time())")
scripts/dev/app_control.sh read --filter zzz >/dev/null 2>&1
python3 -c "import time;t=time.time()-$start;print('engine', 'dibujando' if t>1 else 'DETENIDO: ventana tapada')"
```

`read` avisa por sí solo con `# el engine no entregó frame …` y sigue siendo
fiable —desde el 31/07 dibuja el frame a mano si no llega—, así que **la
estructura se puede verificar con la ventana tapada; los píxeles no**.

> **Esa sonda da FALSOS POSITIVOS y ya costó una afirmación equivocada
> (2026-08-01).** `read --filter zzz` **también** vuelve en 0,2 s cuando el
> filtro simplemente no encuentra nada, que es exactamente lo que hace `zzz`.
> Con esa lectura escribí en un handoff que la confirmación visual quedaba
> pendiente por ventana tapada; un `shot` de control mostró la app
> perfectamente rasterizada. **Para saber si el engine dibuja, mira el frame o
> el aviso que el propio `read` imprime (`# el engine no entregó frame …`), no
> un cronómetro sobre un filtro que no matchea.** Un filtro que sí matchea algo
> presente en pantalla sirve; `zzz` no.

**Cuando la ventana sí está tapada, la única solución es que asome un pedazo.** Moverla o traerla al
frente por AppleScript no basta si igual queda cubierta, y no es algo que el
agente pueda resolver solo: se le pide al dueño y, si no se puede, se declara
que la confirmación visual quedó pendiente. Deducirla de un `shot` viejo es
inventar.

### `window` captura POR REGIÓN DE PANTALLA: puede traerte otra aplicación

**Trampa nueva, 2026-08-01, y es de privacidad.** Con `shot` devolviendo un
frame viejo, el reflejo es probar `app_control.sh window`, que hace una captura
del sistema operativo. Pero recorta **el rectángulo donde está la ventana**, no
la ventana: si `vinabike_erp` no está al frente, ahí encima hay otra cosa. En
esa ronda devolvió, a pantalla completa, **una página web ajena abierta en otro
navegador** — contenido privado del dueño que nada tenía que ver con la tarea.

Se borró en el acto y no se usó. La regla:

- **`window` sólo después de comprobar que la app está al frente**, y aun así
  mirando lo que devolvió antes de razonar sobre ello.
- Si lo que devuelve no es la app, **bórralo de inmediato** y no lo describas:
  es contenido privado que se coló en el contexto.
- Para verificar la app, el camino es `shot` (va por el VM service y **no puede**
  capturar otra aplicación), con la app traída al frente primero.

### Traer la app al frente: `open -a`, no `set frontmost`

```bash
open -a "$PWD/build/macos/Build/Products/Debug/vinabike_erp.app"
```

`osascript … to set frontmost of (process whose unix id is …) to true` **falla
en silencio** con esta app: devuelve sin error y el frontmost sigue siendo otro
—comprobado el 2026-08-01, quedó al frente un navegador—. `open -a` sobre el
bundle **no relanza** la app si ya corre (el PID no cambia): sólo la activa.

Importa porque una app en segundo plano no rasteriza: `read` sigue diciendo la
verdad del árbol, pero `shot` devuelve el último frame viejo. **Síntoma exacto:
el árbol dice que el popover está abierto y el PNG muestra la pantalla sin él.**

### Después de cambiar el brillo, REABRE la ruta antes de capturar

Una ruta que ya estaba en la pila puede conservar píxeles del tema anterior. El
2026-08-01 el diálogo de 5g salió con su fondo oscuro y su texto claro **encima
de una app ya conmutada a claro**, y por un momento pareció un defecto de
contraste del componente. No lo era: era el frame rancio de la ruta.

Cierra la ruta, vuelve a una pantalla neutra, comprueba **ahí** que el brillo
cambió, y recién entonces reabre la ruta que vas a capturar.

### El ciclo completo es más confiable que el reload

El hot reload de este proyecto **se cuelga con frecuencia**, incluso en una
sesión recién levantada y sin nadie mirando. Cuando necesites ver un cambio con
certeza, `stop && start` cuesta ~1 min y nunca miente. Es una limitación real
del proyecto, no un error de operación: no la escondas en el reporte.

---

## 2. Interactuar con la app como un usuario

### Ubicar y tocar — por identidad

```bash
scripts/dev/app_control.sh find --label "Confirmar semana"
scripts/dev/app_control.sh find --key payroll-confirm-week
scripts/dev/app_control.sh tap  --key payroll-confirm-week
scripts/dev/app_control.sh tap  --label "Nóminas" --index 0
```

`find` resuelve el objetivo en el árbol vivo por `ValueKey<String>` o por
etiqueta de semántica/`Text`, y devuelve su rectángulo real. `tap` ubica y toca
en un paso, y **dice qué tocó**.

Un candidato sólo cuenta si su punto de toque está dentro del **viewport
lógico actual**, no está bajo `Offstage`, `IgnorePointer` o `AbsorbPointer`, no
declara semántica deshabilitada ni es un botón deshabilitado, y su propia rama
gana el **hit-test vivo** en ese punto. Por eso `find` no ofrece un control
fuera de pantalla, cubierto por otra capa, bloqueado o deshabilitado como si
fuera seguro tocarlo.

**Con más de un candidato, `tap` se niega y los lista.** `--index N` es un
índice entero base cero sobre esa lista: falta de índice ante ambigüedad,
texto no entero, valor negativo o fuera de rango son errores y producen
**cero eventos de puntero**. Esa negativa es una función, no un estorbo: tocar
«alguno» es exactamente cómo se dispara una acción que nadie pidió.

> **Dos espacios, una traducción explícita.** `shot` devuelve píxeles físicos;
> Flutter recibe eventos en coordenadas lógicas. En el backend normal (`app`),
> el script consulta el DPR vivo y divide las coordenadas del frame actual
> antes de crear el evento. En `APP_CONTROL_BACKEND=os`, transforma esos mismos
> píxeles físicos a la ventana actual y compensa su barra de título. Esto hace
> válido un punto tomado del **frame actual**; no vuelve válida una coordenada
> guardada. Después de navegar, cambiar layout/ventana/pantalla/DPR o reiniciar,
> toma otro `shot`. `click` queda sólo para lo que no tiene identidad —un punto
> dentro de un canvas, gráfico o imagen— y para probar la capa de eventos del
> sistema operativo. Nunca reutilices sus coordenadas.

### Leer la pantalla

```bash
scripts/dev/app_control.sh read
scripts/dev/app_control.sh read --filter "pagar"
```

Recorre el **árbol de semántica** —lo mismo que Flutter le entrega a VoiceOver—
y devuelve etiqueta, valor, **estado** y tamaño, indentado por jerarquía:

```
Nóminas · [botón seleccionado] · 250x26
62 pendientes en Correo · [DESHABILITADO] · 268x38
Semana 27, 29 jun – 05 jul, $225.000 por pagar, SIN CONFIRMAR · [botón seleccionado] · 292x71
```

Cuesta texto en vez de una imagen, así que se puede usar seguido. Y si `read` y
`shot` discrepan, **esa discrepancia es el defecto**: lo que anuncia un lector
de pantalla es la semántica.

### Ver el frame exacto

```bash
scripts/dev/app_control.sh shot salida.png
scripts/dev/app_control.sh geometry        # pid · ventana · tamaño del frame
```

`shot` va por el VM service, así que devuelve el frame **renderizado**, no una
foto de la pantalla: no lo ensucia otra ventana encima ni el cursor del dueño.

### Cambiar de breakpoint

```bash
P=$(scripts/dev/app_control.sh geometry | sed -n 's/^pid \([0-9]*\).*/\1/p')
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $P) to set size of window \"Viñabike ERP\" to {430, 928}"
```

Anchos útiles: **430** (compacto/teléfono) · **880** (tablet) · **1180**
(sidebar expandido) · **1672** (escritorio). Devuelve la ventana a como estaba
al terminar. Para gestos táctiles reales y safe areas de verdad, el Simulador
de iOS; para verificar sólo la composición del breakpoint, redimensionar basta.

---

## 3. Traer un frame de Design

`DesignSync` es una herramienta MCP: la llama el agente, no un script.

```
DesignSync list_files  projectId=<uuid>
DesignSync get_file    projectId=<uuid> path=handoff-t9/frames/7a-pacific-p2.png
```

Un `get_file` grande **no entra al contexto**: la herramienta lo deja en disco y
sólo muestra un preview de 2 KB. Ese archivo se convierte en el real con:

```bash
scripts/dev/visual_compare.py decode <ruta-del-resultado>.txt frames/
```

Sirve igual para PNG (base64) y para `spec.json` / `CHANGELOG.md` (texto). Un
canvas de 260 KB cuesta 2 KB de contexto: **no existe el argumento de que mirar
sale caro.**

**Antes de implementar un frame, lee el `CHANGELOG.md` de su turno.** Ahí está
qué reemplaza a qué, y las correcciones a turnos anteriores. El número de
carpeta y el número de turno **no coinciden** (`handoff-t9` es el turno 7 de la
página de Nóminas), así que la carpeta se descubre con `list_files`, no se
adivina.

La ventana de Design (`design_window.sh`) es para **dos cosas solamente**: ver
lo que el API entrega truncado, y confirmar un resultado construido. Nunca para
leer valores.

### El tope de 192 KiB: un frame puede llegar cortado sin decirlo

`get_file` corta la respuesta en 256 KiB, que después de decodificar el base64
son **exactamente 196.608 bytes = 192 KiB clavados**. No hay aviso: el archivo
se escribe, y simplemente no decodifica.

Se reconoce por los dos síntomas **juntos**:

```bash
ls -l frames/          # 196608 exacto  →  vino cortado
```

y el lector de imágenes lo rechaza. Los que sí bajan enteros están por debajo
(`5d.png` 150.868, `7a-*` ~119.400).

El `CHANGELOG` del turno 5 lo dice sin nombrarlo: los frames anchos van en
bandas `-p1`/`-p2` «porque un solo PNG superaba los 200 KB». `5c` y `5h` se
publicaron como archivo único y caían justo encima del tope — **hasta que
Design los republicó en bandas**, que es lo que el propio `CHANGELOG` registra
en su sección «Republicado después del turno 5» (comprobado el 2026-08-01:
`5c-p1.png` baja en 104.760 bytes y decodifica).

> **Antes de heredar un bloqueo, reverifícalo en su fuente.** Ese caso quedó
> declarado como «bloqueado esperando permiso del dueño» durante un día
> completo mientras el archivo ya estaba publicado. El CHANGELOG del turno se
> lee antes de implementar; lo que faltaba era volver a leerlo antes de
> **repetir un bloqueo**. Un impedimento que depende de un tercero caduca solo,
> y nadie le mira la fecha de vencimiento.

Qué hacer, en este orden:

1. `list_files` por si existe una variante en bandas (`-p1`, `-p2`).
2. Si no existe, **pedirle a Design que lo republique en bandas** — permiso del
   dueño por mensaje.
3. Mientras tanto se puede recuperar la parte que sí llegó, recortando en el
   último chunk PNG completo y cerrando con `IEND`: dio el 97% del alto de 5h y
   el 89% de 5c, que alcanzó para implementar. **Lo que no se alcanzó a ver se
   declara** — nunca se rellena con lo plausible.

---

## 3.b Recetas: las operaciones de todas las rondas, para copiar y pegar

Esta sección existe porque el 31/07 un agente perdió **media hora** atascado en
poner la app en oscuro. Tenía los frames bajados y el procedimiento leído; lo
que faltaba era la secuencia concreta. Un procedimiento sin recetas se paga en
minutos de tanteo, cada vez y por cada agente.

**Si te atascas en una operación que no está acá, agrégala al terminar.**

### Llegar a un módulo

```bash
scripts/dev/app_control.sh tap --label "RR.HH."
scripts/dev/app_control.sh tap --label "Nóminas" --index 0
```

Si `tap` se queja de varios candidatos, `find --label X` los lista y `--index N`
desempata. Nunca por coordenada.

### Llegar a un módulo EN COMPACTO (por el drawer)

Por debajo de 900 no hay barra lateral, y el drawer no se deja tocar por
identidad a la primera. Tres trampas seguidas, cada una cuesta un intento:

```bash
scripts/dev/app_control.sh click 28 28          # abre el drawer (el hamburger
                                                # no tiene identidad; coordenada
                                                # del frame actual, un solo uso)
scripts/dev/app_control.sh scroll 174 400 -6    # el módulo suele estar bajo el
                                                # pie: si no se ve, `find` dice
                                                # «nada que tocar», y tiene razón
scripts/dev/app_control.sh tap --label "RR.HH."
scripts/dev/app_control.sh read | grep -n "Nóminas"   # ← espera a que expanda
scripts/dev/app_control.sh tap --label "Nóminas" --index 0
```

1. **El hamburger no tiene etiqueta**: `find --label "Abrir menú"` no encuentra
   nada. Es el caso legítimo de coordenada.
2. **Lo que está bajo el pie del drawer no es tocable**, y `find` lo rechaza con
   «sin coincidencias: nada que tocar». No es un fallo del script: es su
   contrato. Se hace `scroll` primero.
3. **La fila padre tarda en expandir.** Un `find --label "Nóminas"` disparado
   justo después del `tap` sobre `RR.HH.` devuelve «sin coincidencias» aunque el
   `read` de un segundo después la muestre como `[botón]`. Comprueba con `read`
   antes de concluir que no está.

### Capturar un estado que sólo existe MIENTRAS carga

El esqueleto de carga (5k) se dibuja sólo en el **primer** montaje de la
página: una recarga conserva los datos y se queda en la vista real. Para verlo
no hace falta reiniciar la sesión —basta **salir del módulo y volver**, que
remonta la ruta— y la captura tiene que ir pegada al toque que entra:

```bash
scripts/dev/app_control.sh tap --label "Nóminas" --index 0
scripts/dev/app_control.sh shot frame.png     # sin nada en medio
```

Cualquier comando intercalado —incluso un `read`— pierde la carrera contra una
lectura de producción. Y **preparar la navegación antes**: expandir el menú, o
abrir y desplazar el drawer, en comandos aparte.

### Cambiar a oscuro, y volver

No hay comando: se hace por la UI del módulo de Configuración.

```bash
scripts/dev/app_control.sh tap --label "Configuración"
scripts/dev/app_control.sh tap --label "Apariencia"
scripts/dev/app_control.sh tap --label "Oscuro"      # o "Claro"
```

**Escribe la preferencia persistida del dueño**, así que no la dejes donde te
quedó por casualidad. **El valor al que se vuelve lo declara el handoff vigente
en su fila `Sesión canónica`**, no esta receta: durante la migración de Nóminas
ese valor es `Oscuro`, y una versión anterior de esta línea decía `Claro`, que
contradecía al handoff y hacía que cada ronda lo dejara distinto. Comprueba el
check en su sitio antes de cerrar.

**Si el toggle se resiste, no insistas a ciegas.** El pase oscuro también se
verifica sin la UI: `payroll_redesign_dark_host_test.dart` monta las superficies
en 6 presets × 2 modos y `payroll_visual_tokens_test.dart` verifica capas,
escalera de elevación y que un sheet no se confunda con el fondo. Para juzgar la
**composición** contra el frame igual necesitas la captura, pero no te bloquees:
sigue con un frame que no dependa del oscuro y vuelve después.

### Cambiar de breakpoint

```bash
P=$(scripts/dev/app_control.sh geometry | sed -n 's/^pid \([0-9]*\).*/\1/p')
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $P) to set size of window \"Viñabike ERP\" to {430, 928}"
```

**430** compacto · **880** tablet · **1180** sidebar expandido · **1672**
escritorio. Devuélvela como estaba al terminar.

> **La ventana se nombra, no se toma como «la de adelante».** El proceso expone
> **dos** ventanas —la real y una auxiliar de 66×20—, y `front window` resuelve
> a veces a la auxiliar: el `set size` **devuelve sin error y no pasa nada**.
> El 2026-08-02 costó tres intentos y un desvío diagnosticando permisos de
> Accesibilidad que estaban bien. Compruébalo con
> `... to get {name, size} of every window`, y redimensiona siempre
> `window "Viñabike ERP"`. Un `geometry` después del resize es la confirmación
> barata de que la ventana que cambió es la que estás mirando.

### Si un panel ignora `scroll`, usa `drag`

```bash
scripts/dev/app_control.sh drag 900 700 900 300     # arrastra hacia arriba
```

**2026-08-01.** El panel «Salario y Horas» de la ficha de trabajador **no se
movió** con `scroll` —cuatro intentos, dos posiciones distintas— y una ronda
anterior lo dio por bloqueado, dejando ese estado sin verificar. `drag` lo movió
a la primera: es un gesto de arrastre, que el `Scrollable` de Flutter atiende
aunque los eventos de rueda no le lleguen.

Antes de declarar una pantalla inalcanzable, prueba el otro gesto. Y comprueba
con `find` en vez de con `read`: `read` lista el nodo aunque esté fuera de la
vista, mientras que `find` sólo devuelve lo que de verdad se puede tocar — la
diferencia entre «existe» y «llego».

**2026-08-02: al DRAWER le pasa lo mismo.** Con `RR.HH.` ya expandido, `scroll`
sobre el drawer no movió nada y `find --label "Nóminas"` seguía diciendo «sin
coincidencias»; `drag 174 700 174 380` lo movió a la primera. O sea no es una
rareza de un panel: **es el patrón**. Si `find` no encuentra algo que `read` sí
lista, el gesto es `drag`, no más `scroll`.

Y al revés, el `scroll` de la **página** de Configuración sí funciona — tan bien
que se pasa de largo. Si `find` falla después de desplazar, mira la captura
antes de insistir: el 02/08 «Apariencia» ya había quedado **arriba** de la vista,
no abajo, y dos scrolls más sólo alejaban el objetivo.

### `dart format` sobre un DIRECTORIO toca archivos de otros

```bash
.fvm/flutter_sdk/bin/dart format lib/shared/widgets/vb_short_select.dart   # sí
.fvm/flutter_sdk/bin/dart format test/                                     # NO
```

**2026-08-01, y costó una limpieza entera.** Un `dart format test/` reescribió
**32 archivos ajenos** —toda la familia de Website Builder y storefront— con
cambios de puro reformateo. En un checkout compartido eso aparece como
movimiento concurrente en la revisión de diff de otro agente, que es exactamente
lo que este repositorio prohíbe.

**Formatea por archivo, siempre los tuyos y sólo los tuyos.** Si ya pasó, la
reversión segura no es `git checkout --` a ciegas (además el guard lo deniega, y
con razón): por cada archivo, guarda una copia del árbol, escribe encima la
versión de `HEAD` con `git show HEAD:<ruta> > <ruta>`, formatéala y **compárala
con la copia**. Si son idénticas, el único cambio era tu formato y revertir es
correcto; si difieren, había trabajo ajeno y se restituye la copia intacta.

### Generar las capturas de HARNESS de una etapa inalcanzable en vivo

Cuando una superficie sólo existe tras una precondición prohibida —subir un
archivo real, confirmar una semana— las seis celdas se generan desde el arnés,
con fixture sintético, y **se declaran como de harness**:

```bash
SHOTS=$(mktemp -d)                       # directorio nuevo; nada que borrar
PAYROLL_SHOT_DIR="$SHOTS" .fvm/flutter_sdk/bin/flutter test <suite> \
  --plain-name "<nombre exacto y único del generador>"
ls -l "$SHOTS"                           # exactamente seis PNG
```

**El comando tiene que terminar en `exit 0`.** Un generador que sale distinto de
cero es un generador roto: mientras lo esté, no se puede distinguir «falló la
descarga de una fuente» de «la captura salió en blanco» o «la pantalla
desbordó», que es justo lo que estas imágenes existen para delatar.

**El obstáculo real y cómo se resuelve** (2026-08-01). `GoogleFonts.textStyle`
lanza la carga de la fuente como un future *fire-and-forget* y le hace `.then`
**sin `onError`**; en `flutter_test` toda petición HTTP vuelve 400, así que ese
future **rechaza** y el error llega a la zona como asíncrono no capturado. Y no
ocurre una sola vez: el `catch` de `loadFontIfNecessary` hace
`_loadedFonts.remove(...)` antes del `rethrow` (`google_fonts 6.3.2`,
`google_fonts_base.dart`), o sea **borra la marca de carga y reintenta en la
siguiente resolución de estilo** — por eso no hay drenaje ni precalentamiento
que sirva.

Sólo estalla al capturar porque el rechazo se materializa cuando el future
completa, y eso exige el event loop real: fuera de `runAsync` la zona falsa de
`flutter_test` nunca lo deja completar. La captura es el único punto que necesita `runAsync`
—el encoder de `toImage`/`toByteData` corre ahí—, así que ahí aterrizaban todos
los rechazos.

La solución es **que el error no nazca**, no taparlo: se sustituye el cliente
HTTP del paquete por uno cuyo `send` devuelve un `Completer` que nunca completa,
de modo que las cargas quedan **pendientes** en vez de rechazar. Un `Completer`
pelado no tiene timer ni I/O, así que no deja temporizadores al cerrar. Se
restaura el cliente original y se limpia la caché en `addTearDown`.

Lo que **no** se hace, y por qué:

- **No se drena con `takeException`.** Silencia también los errores ajenos —un
  overflow, por ejemplo—, que son exactamente los que la captura debe delatar.
- **No se apaga `allowRuntimeFetching`.** Sin la fuente entre los assets lanza
  al resolver **cada** estilo, o sea en cada frame: es peor.
- **No se captura fuera de `runAsync`.** `toByteData` se queda esperando el
  event loop y el test se cuelga (medido: bloqueado en `S`, 0 % CPU).

Y lo que sí queda declarado como límite, dicho por lo que se ve y no por lo que
se supone: en estas capturas **el texto sale como bloques** —los glifos de la
tipografía de prueba del arnés—, así que **no se puede leer ni una palabra en
ellas**. Demuestran **composición**: qué hay, dónde, de qué tamaño y con qué
color. **No son evidencia de tipografía** —ni de familia, ni de peso, ni de
kerning— y no se debe afirmar cuál se dibujó: eso no se midió. El texto se cubre
con aserciones de copy, nunca con la imagen.

El generador va **`opt-in`** por variable de entorno y **fuera de la batería**:
es herramienta de evidencia, no regresión — pero verde, como cualquier otra.

### Comparar una banda del frame contra la app

Los frames anchos vienen en bandas (`-p1`, `-p2`). La app hay que ponerla en el
mismo estado que la banda —fila abierta, scope correcto— **antes** de capturar,
si no comparas dos cosas distintas.

```bash
scripts/dev/app_control.sh tap --key payroll-row-action-tap-Lucas   # abrir la fila
scripts/dev/app_control.sh shot app.png
scripts/dev/visual_compare.py side frames/7a-pacific-p2.png app.png cmp.png
```

### Ciclo tras editar código

```bash
scripts/dev/native_session.sh reload || scripts/dev/native_session.sh doctor
```

Si `doctor` dice compilador trabado: `stop && start`, y si `start` se niega por
un proceso huérfano, ciérralo por su ventana (§1). **Tras un reinicio la app
vuelve al Inicio: hay que volver a navegar antes de juzgar lo que se ve.**

---

## 4. Comparar Design contra la app

### Visual

```bash
scripts/dev/app_control.sh shot app.png
scripts/dev/visual_compare.py side frames/5a-p1.png app.png comparacion.png
```

Deja las dos imágenes lado a lado, a la misma altura, en un solo PNG que se
abre de una mirada. Declara el factor de escala que aplicó y **acota el
compuesto para que el lector de imágenes pueda abrirlo**.

**El compuesto es para MIRAR, jamás para medir.** Escala una de las dos
imágenes: cualquier número sacado de ahí está mal.

### Métrica

```bash
scripts/dev/visual_compare.py columns frames/5a-p1.png --band 284 297
```

Da los bordes de columna de una banda horizontal, por corridas de píxel oscuro,
con la distancia entre columnas. Legítimo sobre un frame publicado; prohibido
sobre una captura de la ventana de Design o sobre un compuesto.

Sirve para lo que el `spec.json` no dice o dice mal: el 31/07 el spec de 5a
declaraba 7 columnas y su propio frame dibujaba 8. **Ante una diferencia entre
spec y frame, gana el frame** — lo dice la regla del propio turno.

**Para medir LA APP, no recortes la captura: pregúntale al árbol.** `find`
devuelve el rectángulo real (`centro x,y` + `ancho×alto`) del nodo vivo, y eso
es la medida buena. El 2026-08-02 se intentó recortar un PNG con `sips` para
mirar de cerca una banda del header y **`sips -c` recorta SIEMPRE desde el
centro; `--cropOffset` lo ignora en silencio** y devuelve un recorte de otra
parte de la pantalla, sin error y sin aviso. Dos intentos perdidos, y el riesgo
real no es perderlos: es **describir la zona equivocada creyendo que es el
header**. El cromo móvil se cerró midiendo con `find` —`nav 56 + borde 1 +
alcance 48`— en un solo comando.

### Código

Design publica los snippets `.dart` de cada turno junto a sus frames
(`handoff-t5/payroll_queue_surface.dart`, etc.). Se bajan igual que un PNG y se
comparan contra los nuestros:

```bash
scripts/dev/visual_compare.py decode <resultado>.txt /tmp/design/
diff -u lib/modules/hr/payroll/surfaces/payroll_queue_surface.dart /tmp/design/payroll_queue_surface.dart | head -80
```

**El snippet es referencia, no algo para copiar y pegar**: no conoce el dominio,
los servicios ni los estados reales. Sirve para ver qué estructura y qué nombres
propuso Design, no para reemplazar el archivo.

### Antes de escribir una superficie, revisa si ya existe

Dos veces se escribió un widget con el diseño correcto que **nunca se
instanció**, mientras la pantalla renderizaba otra cosa:

```bash
grep -rn "NombreDelWidget" lib/ test/ | grep -v "<archivo donde se declara>"
```

Si sólo aparece su propia declaración, está muerto. Decide: instalarlo o
borrarlo. Dejarlo es lo que hace creer que un frame ya está implementado.

---

## 5. El ciclo de un frame, de principio a fin

1. `list_files` → ubicar la carpeta del turno. Leer su `CHANGELOG.md`.
2. `get_file` del PNG → `visual_compare.py decode` → **mirarlo**.
3. Levantar/verificar la sesión (`status`, y `doctor` si no responde).
4. Navegar con `tap --label` / `tap --key`. Para un objetivo sin identidad,
   usar una coordenada del `shot` actual una sola vez; nunca reutilizarla.
5. `read` para el estado, `shot` para la apariencia.
6. `visual_compare.py side` → listar las diferencias, una por una.
7. **Pasar la compuerta de criterio (§5.b).** No es opcional y no es un
   trámite: un frame se implementa después de evaluarlo, nunca antes.
8. Implementar. Analyzer + formato + la batería del módulo en verde.
9. Verificar en las **tres vistas**: claro, oscuro y compacto. Una superficie
   sólo en claro-escritorio **no está entregada**.
10. Escribir en el ledger del plan **al cerrar el frame**, no al final.

Si falta el frame oscuro o el compacto de una superficie: **se pide a Design**
—pidiéndole que modifique el canvas que ya existe, no uno nuevo— y se dice que
falta. Deducirlo es inventar con otro nombre.

---

## 5.b La compuerta de criterio: un frame NO se acepta a ciegas

Design es experto **en diseño**, no en este negocio. No conoce el dominio, ni
los servicios, ni cómo navega el resto del ERP, ni cómo se habla en Chile. Un
frame es una **propuesta muy buena sobre el aspecto**, y una hipótesis sobre
todo lo demás.

> **De Design:** paleta, tipografía, superficies, bordes, radios, sombras,
> elevación, chips, botones, tablas, inputs, jerarquía visual y estados.
>
> **Del agente:** que funcione, que se entienda, que se pueda navegar, que las
> palabras sean las correctas, y que no rompa la armonía del ERP — en
> escritorio **y** en móvil.

Implementar sin evaluar produce dos daños que ya ocurrieron: una pantalla
preciosa que afirma algo falso, y un ERP donde cada módulo navega distinto.

### Las seis dimensiones. Se responden por escrito, por frame

| # | Pregunta | Se resuelve mirando |
|---|---|---|
| 1 | **¿Existe en este negocio?** ¿El control, el estado o el dato que dibuja es real acá? | los datos de producción (`scripts/db/query.sh production --sql …`) |
| 2 | **¿La palabra es la correcta?** ¿Es la que usa el dueño, en chileno, y dice lo que la cosa hace? | el vocabulario ya fijado del módulo |
| 3 | **¿La funcionalidad es posible?** ¿El backend expone esto, o es capacidad nueva? | los servicios y RPC reales |
| 4 | **¿La navegación calza con el ERP?** ¿Rutas, retorno, superficies canónicas? | `canonical-ui-surfaces.md` y el contrato de retorno |
| 5 | **¿El layout aguanta las SEIS CELDAS?** Son **dos ejes**, no una lista: brillo (claro · oscuro) **×** host (escritorio · tablet · móvil/compacto). Se responden las seis, deliberadamente, con los recursos que este ERP ya usa | la app corriendo en cada celda |
| 6 | **¿Rompe armonía con otros módulos?** ¿Reinventa un control que ya es canónico? | `universal-ui-component-system.md`, la guía de componentes |

> **Precisión del dueño, 2026-08-01.** La dimensión 5 decía «las tres vistas»
> —claro, oscuro, compacto—, y una corrección intermedia las listó como «cinco
> vistas» en fila. **Las dos formulaciones estaban mal por la misma razón: no
> es una lista, son dos ejes que se multiplican.**
>
> | | escritorio | tablet | móvil/compacto |
> |---|---|---|---|
> | **claro** | ? | ? | ? |
> | **oscuro** | ? | ? | ? |
>
> **Seis celdas, y ninguna se deduce de otra.** Enumerarlas en fila deja creer
> que «claro» y «escritorio» son dos casillas que se tachan por separado,
> cuando lo que hay que demostrar es *claro en escritorio*, *claro en tablet*,
> *oscuro en móvil*… Escritorio y tablet se responden **deliberadamente**, no se
> dan por supuestos porque este ERP haya nacido en escritorio.
>
> Y el criterio que gobierna las seis dimensiones, con todas sus letras: **un
> frame de Design es una propuesta sobre el ASPECTO, no una orden sobre el
> producto.** La app, el repositorio y los datos reales son la fuente de
> funcionalidad, UX, lenguaje y reglas; `DesignSync` sigue siendo la fuente
> literal de cada valor visual.

### Qué hacer con cada resultado

- **Calza** → se implementa tal cual. El *look* manda.
- **No aplica acá** → se descarta, y **se dice por qué**. Ejemplos ya
  resueltos: un rail vertical de iniciales cuando la app ya tiene su menú; un
  control de orden para cinco filas, que es adorno —ése debe ser el orden por
  defecto—; un `Ordenar: pendientes primero` que nadie va a tocar.
- **Falta algo que acá sí se usa** → se agrega, y se dice que se agregó.
  Design no sabía que Nóminas no puede editar horas, así que no dibujó la
  salida a Asistencias. Se agregó.
- **Dice algo falso** → se corrige, siempre. Un `$0` que se muestra como
  «Pagado» es una pantalla mintiendo sobre dinero. Que el frame lo dibuje así
  no lo hace correcto.
- **Necesita capacidad nueva** → **no se inventa a medias**: se implementa lo
  que el backend sí permite, y lo que falta se declara como pendiente con su
  nombre.

### Cómo se registra

En el ledger del plan, al cerrar el frame, **separado explícitamente**:

```
De 5f se copia:  el desglose rotulado, la nota de que esta confirmación ES el
                 comprobante, «Entregado por» como única traza.
De 5f se descarta: nada.
Se agrega:       qué pasa al desmarcar el anticipo — aplicarlo es lo esperado
                 pero es una decisión, y el saldo no se pierde.
```

Sin esa separación, nadie puede distinguir después una decisión de un descuido.
Y una decisión ya tomada **no se deshace sin decirlo**: si un frame posterior
contradice una decisión vigente, gana la decisión, salvo que el frame resuelva
el mismo problema *mejor* — y entonces se dice que se cambió y por qué.

### El caso que justifica toda esta sección

5a dibuja `Quitar de la semana` para alguien sin horas cerradas. La ronda
anterior lo implementó tal cual. Evaluado contra el dominio: Nóminas **no** es
dueña de las horas, así que el arreglo real vive en Asistencias, y ese botón
—en una app que corre contra producción— es justo el que el 30/07 se disparó
por accidente y escribió de verdad. Se descartó, la fila quedó diciendo `Horas
sin cerrar` y sale del cálculo. **Se conservó el hecho que el frame quería
comunicar; se cambió el mecanismo.** Eso es evaluar, no desobedecer.

---

## 5.c Los errores que ya se cometieron. No los repitas

Cada uno costó tiempo real. Están acá con su **causa**, no con la anécdota,
porque la causa es lo que se repite. Si cometes uno nuevo, agrégalo.

### Un aserto acotado por un solo lado deja pasar el defecto entero

**2026-08-01.** El popover de `S-05` se estiraba a **1.672 px colgando de un
campo de 206** —cada opción es un `Row` con `Expanded`, así que la columna
adoptaba el ancho máximo admitido—. La prueba de contrato existía, decía
`ancho >= ancho del campo`, y estaba **verde**: un menú del ancho de la pantalla
cumple esa condición de sobra. Lo encontró la app viva, no el harness.

La causa no es «faltaba una prueba»: es que **la prueba traducía a `>=` una
regla que en el archivo de Design dice «mismo ancho o más»**, donde ese «más» es
el de la opción más larga. Una restricción con un solo extremo no es la regla.

Al escribir un aserto sobre una medida, pregúntate qué valor absurdo lo pasaría.
Si existe uno, acota por los dos lados. Y compruébalo con una mutación: si el
aserto no se pone rojo al romper el código, no está midiendo nada.

### Medir un ancho en la captura y denunciarlo como defecto

**2026-08-02, falso positivo mío.** El panel de respaldo de pago declara
`desktopWidth: 520` y en la captura medía ~416. Lo reporté como divergencia y me
puse a buscar la causa en el código del panel. **No había defecto:** la sesión
corre bajo `WindowZoomScope` con `appliedScale 0.8`, así que **520 lógicos son
416 físicos** — el valor observado era el correcto.

Dos causas, y las dos se repiten sin querer:

1. **Un píxel de la captura no es un píxel lógico.** Antes de restar anchos,
   averigua a qué escala corre la sesión; con zoom aplicado, toda medida de una
   PNG está multiplicada por ese factor.
2. **El ancho semántico de un `Text` no mide su contenedor.** `find` devuelve el
   tamaño del `RenderParagraph` —el texto pintado—, no el ancho disponible.
   Deducir el ancho del panel sumando padding a un rótulo da un número que
   parece riguroso y no lo es.

Si de verdad quieres el ancho de un contenedor, mídelo por su propio nodo o
compruébalo en el código del owner; y **antes de abrir un defecto de layout,
descarta la escala**.

### Auditar evidencia en la carpeta equivocada, y declararla falsa

**2026-08-02, y el error fue mío.** Declaré en el handoff que tres capturas de
`5n` «no existían en el disco» y que otras dos eran duplicados: **falso**.
Existen, con los hashes que el otro agente citaba, y sin un solo duplicado. Lo
que pasó es que hay **dos carpetas con el mismo nombre**:

```
/Users/Claudio/Dev/bikeshop-erp/Screenshots vinabikeProject/…   ← la real, y está en .gitignore
/Users/Claudio/Screenshots vinabikeProject/…                    ← otra, vieja, que no cita nadie
```

Audité la de `$HOME`, encontré duplicados **reales pero de una carpeta muerta**,
y los reporté como si fueran de la que el handoff cita. Acusar de falsa una
evidencia que sí existe cuesta más caro que no haberla mirado: manda a rehacer
trabajo hecho y quema la confianza en el resto del reporte.

**La regla, en dos partes.** Primero, **una carpeta de evidencia se cita con su
ruta absoluta**, nunca con `~` ni con el nombre suelto: el `~` es justo lo que
hizo que dos carpetas distintas se leyeran igual. Segundo, **antes de declarar
que algo falta, comprueba que estás mirando donde el documento apunta** —
`git check-ignore -v <ruta>` confirma de paso que es la carpeta versionada como
evidencia.

Con la ruta correcta, el chequeo que sí vale la pena:

```bash
cd "/Users/Claudio/Dev/bikeshop-erp/Screenshots vinabikeProject/<carpeta>"
shasum -a 256 *.png | awk '{print $1}' | sort | uniq -d
```

Y ojo con el falso positivo simétrico: **dos capturas del mismo estado canónico
salen byte a byte idénticas** —`07` y `14` de esa carpeta, tomadas con dos horas
de diferencia en sesiones distintas—. Ahí el hash repetido **prueba** que la
restauración fue exacta; no es un `cp` mal puesto. El hash dice «mismo píxel»,
no dice «mismo error»: la conclusión la pone el contexto, no el hash.

### Una batería recortada no dice que el módulo esté verde

**2026-08-02.** Las últimas rondas corrían **tres** suites y anotaban
`163 pasadas · 0 fallidas`. Cierto de esas tres. La batería completa que este
mismo repositorio manda correr tenía **tres pruebas rojas**, dos de ellas por un
`static` nuevo que rompe el candado de arquitectura de tema y una por un salto
de 1 px entre la silueta de carga y los datos. Llevaban ahí desde el cierre
anterior, declarado «CERRADO».

La causa es de encuadre: se recorta el alcance para que la corrida sea rápida
—razonable— y después **se cita el resultado como si el alcance fuera el
módulo**. Un conteo se dice con **su fecha, su árbol y su alcance**, y el
alcance es la parte que se olvida.

### «Ya sé por qué falla» — y no lo comprobé

- **La sesión no recargaba.** Vi `screen -ls` diciendo `(Attached)` y concluí
  que el dueño la tenía tomada. **Falso**: un attach no bloquea nada. Era el
  compilador incremental trabado, y la app seguía viva respondiendo capturas,
  así que cada captura mostraba código viejo. **Costó una ronda entera.**
- **22 tests rojos «por cambios de texto».** Eran 31, y la mayoría no era
  texto: 7 suites no compilaban por un parámetro nuevo en un servicio
  compartido, y **tres eran defectos reales** que llevaban días escondidos.

> **La regla:** antes de actuar sobre una causa, compruébala. Lo primero que
> parece explicarlo casi nunca es lo que pasa, y "arreglar" el síntoma
> equivocado cuesta más que investigar.

### El log compacto de `flutter test` no prueba qué corrió

El reporter por defecto reescribe **la misma línea** con `\r`. Grepear ese log
por rutas de archivo para saber si una suite corrió da un resultado que cambia
entre corridas idénticas: en dos ejecuciones con el mismo conteo `+330`,
faltaban tres archivos en una y **otros cuatro** en la otra. Ninguno faltaba —
lo que faltaba era su línea, pisada por la siguiente.

Lo que sí demuestra cobertura:

```bash
flutter test --reporter json <archivos> > out.json
# eventos {"type":"suite"} → una entrada por archivo, sin sobrescribir
# evento  {"type":"done","success":true}
```

> **La regla:** para afirmar «corrieron los N archivos», cuenta **eventos de
> suite**, no líneas de un log que se pisa a sí mismo. Y si dos corridas dan el
> mismo total pero distinta lista de «ausentes», el que está mal es tu método
> de medición, no la corrida.

### Concluir por ausencia en una lista truncada

Quise comprobar si un `reload` había entrado y busqué la fila que el código
nuevo elimina:

```bash
scripts/dev/app_control.sh read --filter "sueldos por pagar" | head -4   # ← la trampa
```

No apareció, y di el reload por bueno. **Estaba en la línea 5.** El `shot`
posterior mostró la fila intacta: el reload nunca había entrado y yo ya había
escrito que sí.

> **La regla:** `read` es una lista, y `head` la corta. **Una ausencia sólo
> prueba algo si miraste la lista entera** — filtra con `grep -n` sobre la
> salida completa, o mira el `shot`. Y para decidir si un cambio entró,
> pregúntale a lo que el código nuevo **agrega**, no a lo que quita: una
> presencia se ve en cualquier posición, una ausencia hay que demostrarla.

### Un arnés de prueba sin tema no prueba la app

`payroll_redesign_surface_test.dart` montaba `MaterialApp(home: …)` **sin
`theme:`**, así que sus 40+ pruebas ejercitaban Nóminas contra el default de
Flutter. Pasaban todas, y aun así no estaban mirando la aplicación: sin el tema
del resolver no existe `VinabikeThemeRoles`, y por lo tanto **ningún componente
compartido puede montarse ahí**. Se descubrió al intentar usar el primero: el
widget se negó a pintar con `VinabikeThemeRoles is missing`.

```dart
MaterialApp(
  theme: AppTheme.resolve(preset: AppearancePresets.all.first,
                          brightness: Brightness.light),
  home: …,
)
```

Montarlo no rompió una sola prueba, que es la parte incómoda: el hueco llevaba
tiempo abierto y era gratis de cerrar.

> **La regla:** un guard que se niega a funcionar en el arnés casi nunca está
> mal configurado — está diciendo que el arnés no representa a la app. Antes de
> degradar el componente para que quepa en la prueba, comprueba si la prueba es
> la que está mintiendo. Degradarlo habría dejado un widget pintando colores
> sin procedencia, que es justo lo que el contrato prohíbe.

**Ampliación del 2026-08-01, y es la parte incómoda:** ese hueco no se cerró
con el arreglo anterior, sólo dejó de verse. `VbNotice` y `VbMoneyText` vivían
dentro de un diálogo que casi ningún arnés abre, así que **tres arneses más
seguían sin tema y nadie se enteró**. Bastó montar el esqueleto `X-01` en el
gate de carga —el primer frame de **todo** montaje de la página— para que 22
pruebas se pusieran rojas de golpe con el mismo `VinabikeThemeRoles is missing`.
Los tres mentían distinto: uno sin `theme:`, otro con el `pump` bueno pero
cuatro `MaterialApp.router` sueltos sin tema, y el tercero con
`ThemeData.light()/dark()` mientras decía cruzar «todas las paletas» —lo que
cruzaba era el tema **anidado** del chrome, no el del resolver—. Se arreglaron
los tres montando lo que monta `lib/main.dart`
(`AppTheme.resolve(preset: appearance.appearancePreset, …)`) y **no cambió una
sola aserción**.

> **La regla que faltaba:** un arnés sin tema no se detecta arreglando el que
> falló, sino **metiendo el componente compartido en el camino que toda prueba
> recorre**. Mientras el componente viva en una rama que casi nadie visita, el
> resto de los arneses siguen mintiendo en silencio.

### Sobrescribir `MediaQuery` con una `MediaQueryData` nueva borra el tamaño

Para que `pumpAndSettle` no se quedara colgado contra el barrido infinito del
esqueleto, envolví la página en `MediaQuery(data: MediaQueryData(disableAnimations: true))`.
Eso **reemplaza la data entera**: el tamaño se fue a `Size.zero`, la página se
creyó compacta a 1440 y la prueba estuvo midiendo la composición móvil mientras
afirmaba medir la de escritorio. No falló por eso —falló tres aserciones más
abajo, con números que no cuadraban.

```dart
Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: …,
  ),
)
```

> **La regla:** a `MediaQuery` se le **copia** la data ambiente y se le cambia
> el campo; construir una `MediaQueryData` desde cero apaga todo lo demás. Y si
> una prueba responsiva empieza a dar números de otro breakpoint, sospecha del
> `MediaQuery` del arnés antes que del widget.

### Un pipe se come el código de salida de la batería

Corrí `flutter test … | tail -25` en segundo plano. El runner reportó **«exit
code 0»** y di la batería por verde. **No lo estaba**: `306 +1 fallo`. El código
de salida que se propaga es el del **último** comando de la tubería —`tail`—,
que siempre sale 0.

```bash
flutter test <archivos> > bat.log 2>&1; echo "EXIT=$?"   # así no miente
set -o pipefail                                          # o así, si hay pipe
```

> **La regla:** un resultado de pruebas se lee del **texto** (`All tests
> passed!` / `Some tests failed`), no del código de salida de una tubería. Y si
> lo que informa el verde es un runner en segundo plano, comprueba qué comando
> le dio ese código.

### Diagnosticar con algo que muta

Escribí un `doctor` que, para "comprobar" si el compilador respondía, **pedía un
reload**. Eso disparaba un segundo reload encima del que ya corría, los dos
morían, y el doctor reportaba trabado un compilador que él mismo acababa de
trabar.

> **La regla:** un diagnóstico es de **sólo lectura**. Si para medir algo tienes
> que moverlo, no estás midiendo.

### Afirmar que un dato falta sin comprobar la fuente

La app decía «el asiento contable no quedó registrada». Se leía
`expense_payments.payment_account_id`, nulo en los 78 pagos. **El asiento estaba
completo y cuadrado** en `journal_entries`/`journal_lines`. Esa frase habría
hecho al dueño desconfiar de una contabilidad sana.

> **La regla:** antes de decir que un dato falta, comprueba que no sea tu
> lectura la que falla. Las lecturas de producción son autónomas:
> `scripts/db/query.sh production --sql "…"`.

### Parchar un defecto compartido dentro del módulo

Los avatares en oscuro chocan con el acento de Pacific. Lo arreglé dentro de
Payroll y el guard de inventario congelado lo rechazó — **con razón**: el choque
lo tiene cualquier módulo con avatares en ese preset. Parcharlo acá era esconder
un defecto compartido.

> **La regla:** arregla donde **nace**, no donde duele. Si un guard te frena,
> probablemente está diciendo algo cierto: piénsalo antes de rodearlo.

### Escribir mientras otro publica

Escribí un `.md` mientras Codex corría su gate local, y apareció como movimiento
concurrente en su revisión del diff. No costó la publicación, pero pudo.

> **La regla:** comprueba el estado de publicación **antes** de la primera
> escritura (§ el bloque del handoff). Y la advertencia sin matiz es igual de
> mala: dejó a otro agente esperando algo que ya no lo afectaba.

### Hacer algo a mano y no escribirlo

Puse la app en oscuro con clics por coordenada, me falló, insistí, y **nunca lo
documenté**. El agente siguiente perdió media hora exactamente ahí, con los
frames ya bajados.

> **La regla:** si tuviste que tantear una operación, es candidata a receta
> (§3.b). Lo que a ti te costó diez minutos, al siguiente le cuesta treinta.

### Dar por implementado lo que sólo está escrito

Tres veces apareció un widget con el diseño correcto de Design que **nadie
monta**, mientras la pantalla renderiza otra cosa. Verlo en el archivo hace
creer que el frame está hecho.

> **La regla:** grepea antes (§4). Si sólo aparece su declaración, está muerto:
> instálalo o bórralo, pero no lo dejes.

### Entregar un comando antes de comprobar si ya estaba corriendo

Vi un run de publicación en curso, no comprobé quién lo había disparado, y le
pasé al dueño el comando para lanzarlo «por si acaso». Resultó que el que veía
era el de **Android** —los dos targets comparten workflow y `gh run list` los
muestra igual— así que el comando lanzó un macOS que faltaba, no un duplicado.
Peor: al «arreglar el duplicado» cancelé la publicación de macOS de verdad.

> **La regla:** un comando que dispara algo externo se entrega **después** de
> mirar qué hay corriendo, no antes con un «si ya lo hiciste, ignórame». Y el
> estado se lee por el campo que identifica la cosa (`displayTitle`), no por el
> que se parece (`workflowName`).

### Una prueba nueva que pasa a la primera es sospechosa: múta el código

El 2026-08-01, en el paso 4, escribí cuatro regresiones y **las cuatro pasaron
en la primera corrida**. Dos no probaban nada:

- «un descarte automático no se cuenta como *Excluidos por ti*» seguía verde con
  el contador **roto a propósito**: su fixture usaba un abono entrante, que ni
  siquiera entra en la lista sobre la que el contador itera.
- «el total es lo que las semanas dejan de deber» seguía verde **quitando los
  anticipos del total**: el fixture no creaba ninguno.

Las dos veces **el fixture estaba mal, no la aserción** — la misma causa que ya
había costado tres pruebas decorativas en el paso 2, sólo que ahí el síntoma era
un `if` y acá era un escenario que no se construía.

```bash
# el único chequeo que no se puede engañar a sí mismo
<rompe la línea que la prueba dice vigilar>
flutter test <suite> --plain-name "<la prueba>"   # tiene que salir ROJO
<restaura desde la copia>
```

> **La regla:** una regresión no vale por estar verde, vale por **ponerse roja
> cuando corresponde**. Mutar la línea que dice vigilar cuesta un minuto y es lo
> único que distingue una prueba de un adorno. Y si la mutación no la enrojece,
> arregla el **fixture** —que el escenario ocurra— antes de tocar la aserción.

### Un frame puede traer una palabra que un turno posterior ya derogó

`5j-paso4` (turno 5) rotula **`Total a imputar`**. El `CHANGELOG` del **turno 7**
lista, bajo «Decisiones de producto respetadas (ya en la app)», «"Imputar" →
"Aplicar"». El frame no está mal: está **desactualizado**, y nadie lo va a
reetiquetar.

> **La regla:** antes de copiar una palabra de un frame, busca esa palabra en los
> `CHANGELOG` de los turnos **posteriores**. Una decisión de producto ya tomada
> gana sobre el frame que la precede, y el contrato de sincronía nombra
> «imputar» y «ganado» justamente como los casos que Code debe corregir.

### Prometer y detenerse

Cerré un turno diciendo «sigo ahora mismo, no me detengo» y terminé el turno.

> **La regla:** si dices que sigues, sigue. Y si el trabajo es largo, el ledger
> se escribe **al cerrar cada frame**, no al final: es lo único que sobrevive si
> el chat se acaba.

---

## 5.d Lo que sólo se ve en el teléfono

Hay defectos que **no existen** en macOS ni en el navegador y que la batería no
puede ver. Se descubren mirando la pantalla del dueño, y su causa suele estar
en la plataforma, no en el widget.

### La barra de estado en Android 15+

`targetSdk` es **36**. Desde **Android 15 (API 35) `Window.setStatusBarColor`
está ignorado** —el modo edge-to-edge es obligatorio— y eso es exactamente lo
que hay debajo de `SystemUiOverlayStyle.statusBarColor`. Pedirle un color al
sistema no hace nada; sobre la franja transparente se ve el `windowBackground`
del tema Android, que en claro es **blanco**.

**La franja la pinta la app.** Se pide `SystemUiMode.edgeToEdge` al arrancar
(`lib/main.dart`) y el `AppBar` del shell extiende su fondo hasta arriba. El
color sigue viajando en el overlay style para versiones donde aún se respeta;
el brillo de los iconos nunca dejó de funcionar en ninguna.

El 31/07 se «arregló» sólo con el color y **la actualización salió sin cambio
alguno**. Un contrato lo fija ahora: `system_status_bar_contract_test.dart`
exige la llamada de edge-to-edge, con la causa escrita al lado.

> **La regla:** cuando algo de chrome del sistema no cambia pese a que el
> código lo declara, **comprueba primero si la API sigue vigente en el
> `targetSdk` real**, antes de tocar el widget. `flutter.targetSdkVersion`
> avanza solo con cada actualización del SDK, así que una API que funcionaba
> puede quedar ignorada sin que nadie cambie una línea.

### Publicar: dos plataformas, dos anclas distintas

Las novedades se atan a un rango, y **cada plataforma tiene su propio ancla**:
la última release de macOS y la última de Android no son el mismo commit. Un
candidato atado a la de Android hace fallar a macOS con
`The shared release-note base does not match the authoritative macOS range` —
y no falla el build, falla el paso de novedades, así que se lee como otra cosa.

El ancla real la resuelve el propio `prepare_erp_update.sh` y **la imprime**:

```
Notes base: fa698597cc50aac657f7eae5eb1387906a70413b
```

Se construye el candidato contra **esa** base, no contra la que uno supone.

---

## 6. Qué necesita al dueño

**Todo efecto que salga de este checkout se pide, y se pide por acción:**
commit, push, publicar la actualización, desplegar migraciones o funciones,
`scripts/deploy.sh` y CHECKPOINT B (writes reales de conciliación).

El contrato que manda es `CODEX_CLAUDE_COLLABORATION.md` §Safety boundary:
«Production writes, deployment, publication, messages, commits, and pushes
require the owner's explicit authorization.» Una autorización puntual **no** se
convierte en permiso permanente — se vuelve a pedir la próxima vez.

### El guard mecánico mide capacidad, no permiso

Son dos cosas distintas y confundirlas es lo que esta sección existe para
impedir: hasta el 2026-08-01 este mismo documento decía «commit y push ya no
[se piden]», y con eso un agente quedaba autorizándose solo.

| | Hoy el hook `.claude/hooks/guard-dangerous-bash.sh` |
|---|---|
| **Deja pasar** | `git add` · `commit` · `push` · `restore -- <rutas nombradas>` · `scripts/publish_*` · `scripts/releases/*` |
| **Sigue denegando** | `git rebase` · `restore` de alcance abierto · `supabase db\|migration` · `firebase deploy` · `supabase functions deploy` · `scripts/deploy.sh` · `production_validation.sh refresh` |

Que el hook **deje de impedir** algo no concede permiso: sólo deja de
bloquearlo. El contrato no se movió cuando se movió el hook. Lo que la fila de
la izquierda describe es qué comandos no van a fallar, no cuáles se pueden
ejecutar.

Ya con la autorización en la mano, antes de mover `origin` se comprueba que
Codex no esté publicando desde este checkout (§ el bloque de arranque del
handoff de Nóminas). El guard deniega lo de la fila derecha y **no se rodea**:
se le entrega al dueño el comando exacto y la evidencia.

### Publicar: dos targets, un solo workflow

`gh run list` **no distingue la plataforma**. macOS y Android comparten
`macos-release.yml`, así que los dos aparecen con el mismo `workflowName`
(«Build macOS Desktop Release») y una lista de runs se lee como si hubiera
duplicados donde hay uno de cada. Lo que distingue es el **`displayTitle`**:

```bash
gh run list --limit 8 --json displayTitle,status,conclusion,databaseId,headSha \
  --jq '.[] | select(.headSha | startswith("<sha>")) |
        "\(.status)/\(if .conclusion == "" then "pendiente" else .conclusion end)  \(.databaseId)  \(.displayTitle)"'
```

`Android publish · <sha> · notes <hash> · from <base>` vs `macOS publish · …`.
El 01/08 confundir uno con otro costó cancelar la publicación de macOS a mitad
de camino. **Antes de cancelar o relanzar un run, léele el título.**

Dos detalles de `gh` que muerden en el mismo comando: `conclusion` viene como
cadena **vacía** mientras el run corre, no `null`, así que `// "corriendo"` de
`jq` no sustituye y un bucle de espera cree que ya terminó; y el workflow tiene
`cancel-in-progress` para macOS, así que **relanzarlo cancela el anterior** —
eso es lo correcto, no un fallo.

Enviarle un prompt a Design es actuar en nombre del dueño: **requiere permiso
por mensaje**. Al pegarlo, la codificación va en la llamada a `pbcopy`, si no
los acentos salen rotos:

```bash
printf '%s' "$(cat prompt.txt)" | \
  __CF_USER_TEXT_ENCODING=0x1F6:0x8000100:0x8000100 pbcopy
```
