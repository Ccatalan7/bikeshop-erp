# Nóminas → migración a los diseños de Claude Design · handoff vivo

**Actualizado 2026-08-01, undécima sesión (`5c` gramática de decisión cerrada
contra el turno 7, con las seis casillas vivas, y el claro de `5j-p3`
completado con la cartola real).**

> **Sesión canónica al cerrar:** app `44281`, VM `:65235`, brillo **`Oscuro`**,
> ventana **1360×800**. Una sola, y no se arranca otra. Convive con una copia
> **instalada** (`~/Applications/Vinabike ERP.app`, `81847`): comprueba
> `pgrep -fl vinabike_erp` y toca siempre por identidad, nunca por coordenada.
> **La sesión anterior (`73994`) se cerró con `stop && start`, deliberadamente
> y no por capricho:** un `Tooltip` por fila la dejó en cascada de errores de
> overlay y un `reload` colgado la volvió inservible (§4.24).
>
> **CERRADOS, no pendientes:** el **OCR paso 4**, el **Historial 5i**, la cola
> **5a**, el sidebar **5b**, la tablet **5m**, **Anticipos 5h** y ahora la
> **gramática de decisión `5c`**, todos con evidencia viva contra producción.
> **`5j-p3` quedó con las seis casillas**: el oscuro se capturó el 01/08 y el
> claro en esta sesión, recargando la cartola con el brillo ya en claro.
> **Lo siguiente es `5n` matriz de cierre**, y 5e/5f siguen bloqueados por
> escritura, ver §7.
>
> Límites vigentes: no hay writes de producción, no hay commit, push, deploy ni
> publicación, y **no se lanzan subagentes, agent teams ni Workflows** — se
> trabaja secuencialmente en una sola sesión.
>
> **El criterio que gobierna todo esto:** Design manda el **aspecto**; la app,
> el repositorio, el backend y el dominio mandan el **producto** —función,
> palabras, navegación, UX y reglas—, y cada frame pasa la compuerta de seis
> dimensiones antes de escribir código.
>
> **La trampa que más costó en esta ronda, para que el siguiente no la repita:**
> tres veces una prueba quedó verde **sin probar nada** — un `if` alrededor de
> la aserción, un fixture que no construía el escenario que su nombre prometía,
> y un finder que hacía match con otro texto de la misma pantalla. Si el caso
> puede no producirse, **el fixture está mal, no la aserción**. Y una promesa de
> UI se comprueba **leyendo el servicio que la cumple**, nunca el frame que la
> dibuja: así aparecieron «extracción exacta», «confianza por línea», «NÍTIDA»,
> «ILEGIBLE», «LECTURA DUDOSA», «semanas que cubre» y «Otros movimientos», que
> eran siete afirmaciones falsas.

### VIGENTE al cerrar esta sesión — reconsultado, no recordado

| Qué | Valor |
|---|---|
| Rama · HEAD | `smartpegas1.0` · `74df6776` |
| Sin pushear | `git rev-list --count origin/smartpegas1.0..HEAD` = **0** |
| Árbol | **48 rutas sucias** — compartido, **no limpio**. Reconsultado al cerrar el bloque OCR. `.agents/` y `AGENTS.md` **no son míos**: aparecieron durante la sesión, es Codex trabajando en paralelo |
| Publicación local | sin procesos vivos al cerrar |
| Batería Nóminas + compartidos | **513 pasadas · 2 saltadas · 0 fallidas · 41 suites**, `{"type":"done","success":true}` leído del reporter JSON (2026-08-01, tras la **revisión Ultracode de `5c`**). **No se compara restando contra rondas anteriores:** Codex agregó suites al árbol compartido durante la ronda (`payroll_beneficiary_alias_*`, `payroll_advance_evidence_service_test`) y modificó las suyas — se vuelve a medir con el mismo comando o no se compara. Lo mío: `payroll_queue_surface_adaptive_test` **15 → 26** y `payroll_redesign_surface_test` **+2**, cada contrato con su mutación **verificada como aplicada** antes de creerle. Las **2 saltadas son las de siempre**: los generadores de capturas `opt-in` de los pasos 2 y 4 |
| Próximo comando | **§7: `5n` matriz de cierre** (sin empezar). Cerrados con evidencia viva: **5i**, **5a**, **5b**, **5c**, **5h**, **5m** y **`5j-p3` en sus seis casillas**. **5e/5f siguen con RT bloqueado por escritura** (§2), y **5l** sigue sin el marco del turno 6. Para llegar a Nóminas: `native_session.sh status` → `pgrep -fl vinabike_erp` (**una sola instancia de debug**, ver §4.d) → `app_control.sh tap --label "RR.HH."` · `--label "Nóminas" --index 0` |
| Cuadratura del conteo | **454 = 449 − 2 + 7, y las dos partes están verificadas.** El cierre del bloque OCR dejó **449 / 2 / 38 suites**; ese 38 incluía `main_layout_breakpoint_state_test.dart`, que tiene **2 casos** y **NO está en el glob** de la fila anterior (no empieza por `payroll_` ni por `vb_`). Descontarlo da **447 en 37 suites**, y esta ronda sumó **+7** al reescribir `payroll_history_surface_adaptive_test` de **5 a 12** pruebas → **454 en 37 suites**. Esta ronda **no agregó ni quitó suites**; también migró un caso de `payroll_redesign_surface_test` al disclosure compacto, que no mueve el conteo. Las **2 saltadas son las mismas de siempre**: los generadores de capturas `opt-in` de los pasos 2 y 4. **La lección, que es lo que vale:** dos glob distintos dan dos números distintos sobre el mismo árbol. Un conteo se compara **volviendo a medir con el mismo comando**, no restando contra el número de otra ronda; si el comando cambió, dilo o el siguiente leerá una regresión donde no la hay |
| Focales finales | **30/30** `vb_short_select_contract_test` (S-05) · **33/33** `payroll_employee_payment_method_command_test` (5g) · `deferred_route_state_contract_test` (router) · en `payroll_reconciliation_responsive_test`: navegación de preguntas, elisión a 834/430 y CTA largo del paso 4 |
| Sesión canónica | app **`89180`**, VM **`:56556`**. Las anteriores (`44281`, `65685`, `84436`, `73994`, `62796`…) son **históricas**: `65685` y `84436` se levantaron a propósito para reproducir §4.24 en runtime limpio, y `73994` había quedado envenenada. Brillo **`Oscuro`**, ventana **1360×800**. **Trae la app al frente con `open -a` antes de capturar**; si necesitas un hover REAL —`Tooltip`, cursor— usa `APP_CONTROL_BACKEND=os`, porque el driver por defecto **no mueve el cursor del dueño** y no genera hover |
| Analyzer del scope | 0 en los archivos tocados. `lib/modules/hr` + `lib/shared/widgets` arrastran **10 avisos pre-existentes y ajenos**: `kiosk_mode_page.dart:107`, `scanner_bridge_scope.dart` (5), `smart_import_dialog.dart` (2), `whatsapp_web_viewer.dart:62` |

Chrome compartido **18/18** y release **78/78**: **históricos**, no re-medidos
en esta ronda.

> **Los números y PIDs de más abajo en este documento son HISTÓRICOS** salvo que
> digan lo contrario. Si alguno contradice esta tabla, **gana esta tabla**: es la
> única reconsultada al cerrar.

Analyzer del scope: **1 aviso, pre-existente y ajeno a Nóminas**
(`lib/modules/hr/pages/kiosk_mode_page.dart:107`,
`use_build_context_synchronously`).

**Un conteo se cita con su fecha y su árbol, o no se cita.** Durante esta ronda
hubo un 314 y un 327 intermedios que quedaron obsoletos en cuestión de minutos;
el que vale es el último, y se lee del **texto** (`All tests passed!`), nunca
del código de salida de una tubería (§5.c del workflow). Analyzer: **0 en las superficies de Payroll**; `lib/modules/hr`
entero arrastra **1 aviso pre-existente** (`kiosk_mode_page.dart:107`,
`use_build_context_synchronously`), que no es de esta tarea.

**Y lo mismo vale para un número dentro del código.** Esta ronda puso un tope de
filas en el esqueleto **dos veces** —`1..12` y después `1..6` «defendido» con las
semanas que había ese día en producción— y las dos veces estaba mal por la misma
razón: **una muestra de hoy no es un owner canónico**. Quedó derogado el mismo
día (corrección fechada en el ledger). Si un número no tiene dueño estable al que
citar, no se pone: se deriva de algo que sí lo tenga.

**Cómo se demuestra ese número**, porque leerlo del log compacto no basta:

```bash
flutter test --reporter json $(ls test/unit/payroll_*_test.dart \
  test/widgets/payroll_*_test.dart test/unit/native_session_stop_contract_test.dart \
  test/widgets/vb_*_test.dart) > out.json
```

→ **el conteo vigente es 33 suites / 364 pruebas** (tabla de arriba). El **330
en 30 suites es histórico**, del cierre anterior, y se conserva sólo para que se
vea de dónde venía la cuenta.
El reporter compacto reescribe la misma línea con `\r`, así que grepearlo por
rutas da falsas ausencias distintas en cada corrida. Y el conteo se lee del
**texto**, nunca del código de salida de una tubería (§5.c del workflow).

**`5d` fue el primer frame CERRADO según §0.b** (2026-08-01) — histórico. Desde
entonces cerraron también **5k · carga y vacío** y el **OCR paso 1**, y el **OCR
paso 2** quedó *funcionalmente cerrado y visualmente parcial*. **La matriz de §2
es la que manda**: separa implementado de verificado, y distingue lo vivo de lo
que sólo tiene harness.

---

## ⛔ ANTES QUE NADA: mira si Codex está publicando

Codex publica desde este mismo checkout. Hay **dos situaciones distintas** y se
confunden fácil, así que compruébalo en vez de suponerlo:

```bash
git status --porcelain | wc -l                       # ¿árbol limpio?
git log --oneline -1                                 # ¿en qué commit?
git rev-list --count origin/smartpegas1.0..HEAD      # ¿algo sin pushear?
pgrep -fl "flutter build|run_flutter_test_gate|firebase deploy|fastlane|gradlew"
```

| Lo que ves | Qué significa | Qué puedes hacer |
|---|---|---|
| **Procesos de build vivos** o árbol sucio que no es tuyo | Publicación **local** en curso: está leyendo el árbol | **Nada.** Ni código, ni tests, ni documentación |
| Sin procesos, árbol limpio, `HEAD == origin` | La publicación es **remota**: corre en CI sobre un SHA ya congelado | Trabaja normal. **Pero no commitees ni pushees** hasta que cierre |

**El caso remoto es el habitual.** Codex pushea, y desde ahí la calificación y
los dos publicadores corren en CI sobre ese SHA exacto. Tu árbol local ya no los
afecta — lo único que los rompería es un push que mueva `origin` en medio.

### Por qué esto está escrito

El 31/07 esta sesión escribió un `.md` mientras Codex corría su gate **local**,
y apareció como movimiento concurrente en su revisión de diff. No costó la
publicación, pero pudo haberla costado. Y la advertencia sin matiz es igual de
mala: deja a un agente esperando algo que no lo afecta.

**La ausencia de procesos no prueba que terminó bien.** Si vas a pushear,
pregúntale al dueño primero. **Y no cuentes con que el guard te frene**
(corregido el 2026-08-01: esta línea decía que «te lo va a denegar», y desde el
31/07 ya no lo hace). El hook deja pasar `commit` y `push`; lo que los sigue
exigiendo es el contrato, no la máquina. Un permiso que creías tener porque
nada te detuvo es exactamente cómo se mueve `origin` a destiempo.

### Si toca esperar, espera activamente

```bash
until ! pgrep -f "flutter build|run_flutter_test_gate|firebase deploy|fastlane|gradlew" >/dev/null 2>&1; do
  sleep 30
done
echo "sin procesos de publicación vivos"
```

Lánzalo en segundo plano y mientras tanto haz lo que **no escribe el repo**:
leer los documentos, bajar frames con `DesignSync` y mirarlos, levantar la
sesión de debug, comparar contra la app y planificar el frame que sigue.
Escribe en el scratchpad de la sesión, nunca en `.tmp/` del repositorio.

Plan padre y ledger completo: **`PAYROLL_COMPLETION_PLAN.md`** (§13
autorizaciones · §14.c lo que se le pidió a Design · §15 ledger).

---

## 0.a Tus primeros 10 minutos

En este orden. No implementes nada antes de terminarlo.

```bash
# 1 · ¿Puedo escribir? (§ el bloque de arriba)
git status --porcelain | wc -l && git log --oneline -1
pgrep -fl "flutter build|run_flutter_test_gate|firebase deploy|fastlane|gradlew"

# 2 · ¿La base está sana? Vigente: 364 en 33 suites (ver la tabla del encabezado).
#     Este comando abrevia; el completo, con vb_* y native_session, está arriba.
.fvm/flutter_sdk/bin/flutter test $(ls test/widgets/payroll_*.dart test/unit/payroll_*.dart | tr '\n' ' ')

# 3 · ¿La app corre?
scripts/dev/native_session.sh status || scripts/dev/native_session.sh start
scripts/dev/app_control.sh tap --label "RR.HH."
scripts/dev/app_control.sh tap --label "Nóminas" --index 0
scripts/dev/app_control.sh read --filter "semana"
```

Si los tres pasan, estás operativo. **Si el paso 2 falla, ése es tu trabajo
antes que cualquier frame**: sin la base verde no sabes qué rompe cada cambio.

Después: `list_files` en Design → `CHANGELOG.md` del turno → `get_file` del PNG
→ `visual_compare.py decode` → **míralo**.

## 0.b Cuándo un frame está CERRADO

No es «se ve parecido». Las cinco, o no está cerrado:

1. Comparado contra el **PNG bajado**, no contra el `spec.json` ni de memoria.
2. Pasó la **compuerta de criterio** (`AGENT_VISUAL_WORKFLOW.md` §5.b), y quedó
   escrito qué se copió, qué se descartó y qué se agregó, **con su razón**.
3. **Los dos ejes demostrados, no uno**: brillo (claro **y** oscuro) × host
   (escritorio, tablet y móvil/compacto). Claro-escritorio no es un tercio de
   la entrega: es **una de seis casillas**. Lo que no se miró se escribe `n/r`,
   nunca se deja en blanco — un hueco en blanco se lee como un sí.
4. **Batería del módulo en verde** y analyzer del scope limpio.
5. **Entrada en el ledger** (§15 del plan), escrita al cerrarlo — no al final.

Lo que no alcanzaste a hacer se declara con nombre. Un frame «casi listo» sin
decir qué le falta es peor que uno no empezado: el siguiente lo da por hecho.

## 0.c Cómo dejas este handoff para el que sigue

**Esto no es opcional: es lo que hace que el sistema funcione la próxima vez.**
Antes de cerrar tu sesión:

| Actualiza | Con qué |
|---|---|
| §2 el estado | Mueve el frame de «sin empezar» a «cerrado», con la decisión que tomaste en una línea |
| §4 la deuda | Agrega lo que descubriste y no arreglaste, **con dónde nace la corrección** |
| §3 lo aprendido | Sólo lo que le habría ahorrado tiempo a alguien: una trampa, una preferencia del dueño, un documento que resultó falso |
| `AGENT_VISUAL_WORKFLOW.md` §3.b | Si tuviste que tantear una operación, conviértela en receta |
| `AGENT_VISUAL_WORKFLOW.md` §5.c | Si te equivocaste, escribe la **causa** y el costo real |

Escribe la causa, no el síntoma. Fecha lo que corrige algo anterior. **No
escribas el relato de tu sesión ni lo que ya se ve en git.**

La prueba de que quedó bien: alguien que no estuvo acá abre este archivo y en
diez minutos está comparando un frame. Si tiene que preguntarte algo, faltó
escribirlo.

---

## 0. Lee esto primero, son 3 minutos

| Documento | Para qué |
|---|---|
| **`AGENT_VISUAL_WORKFLOW.md`** | **EL procedimiento.** Sesión de debug, tocar por identidad, leer la pantalla, traer un frame, comparar. Y §5.b, la compuerta de criterio |
| `DESIGN_HANDOFF_SYNC_CONTRACT.md` | De dónde sale un valor visual. Manda sobre todo lo demás en esa pregunta |
| `AGENT_MACOS_APP_CONTROL.md` | Referencia de cada herramienta y sus trampas |
| Este archivo | Qué está hecho, qué falta, y qué NO se puede hacer |

**No empieces a implementar sin haber leído `AGENT_VISUAL_WORKFLOW.md`.** Esta
sesión se construyó ese procedimiento porque el mismo trabajo se improvisó
cinco veces con cinco resultados distintos.

---

## 1. Lo que NO puedes hacer sin autorización

| Acción | Estado |
|---|---|
| **CHECKPOINT B** — smoke test con cartola real (writes de conciliación) | **PROHIBIDO.** Sigue sin autorizar |
| **Commit / push** | Autorización **por acción**. El guard mecánico dejó de denegarlos durante el 31/07, pero `CODEX_CLAUDE_COLLABORATION.md` §Safety los sigue exigiendo y manda el contrato: una autorización puntual no es permiso permanente |
| **Publicar la actualización** | Autorización **por acción**, ídem |
| Desplegar migraciones o funciones | Requiere autorización en el momento |
| Mandarle un prompt a Design | Permiso **por mensaje**. **Sólo para esta tarea** (2026-08-01) el dueño delegó en **Codex** los prompts *estrictamente necesarios*, registrando prompt exacto, página, turno, component ids y resultado. Delegación **acotada**: no cambia la regla general |
| Subagentes, agent teams y Workflows | **Suspendidos** por el dueño el 2026-08-01, **mientras dure esta tarea**. No es una regla permanente y **no deroga** el «sin techo de herramientas» de `CODEX_CLAUDE_COLLABORATION.md`: se trabaja secuencialmente en una sola sesión hasta que el dueño lo levante |

CHECKPOINT A (las 7 migraciones) ya fue ejecutado; el backend versionado está
activo en producción. No lo repitas.

**La app corre contra PRODUCCIÓN.** Por eso se toca por identidad y nunca por
coordenada: el 30/07 un clic de navegación cayó sobre `Quitar de la semana` y
escribió de verdad.

---

## 2. El estado real, frame por frame

**Sólo `5d` está CERRADO según §0.b; ninguno de los demás.** La tabla separa lo que
está implementado de lo que está verificado, porque mezclarlo fue justo lo que
llevó a dar por hecho lo que no estaba. Fila del registro canónico
(`canonical-ui-surfaces.md`) para Payroll: **In progress**.

**La verificación tiene DOS EJES, y hay que demostrar los dos.** Ninguna fila
queda en verde con uno solo — que es exactamente como se dio por cerrado lo que
no lo estaba:

- **Brillo** — `Claro` y `Oscuro`. Un frame sólo en claro es medio frame.
- **Host** — `Escrit.` (1440 / 1116), `Tablet` (834) y `Móvil` (390 / compacto).
  Que se vea bien en escritorio no dice **nada** de 834.

Las demás columnas: **Impl** = escrito y montado · **Design** = frame exacto
disponible y bajado · **RT** = verificado en la app viva contra datos de
producción · **T** = con regresión propia en la batería.

`n/r` = **no registrado**: nadie lo verificó *ni lo declaró*. No es `n/a` («no
aplica»), y confundirlos es lo que convierte un hueco en un supuesto.

Cada frame y **cada paso del OCR tiene su propia fila**. Agrupar
«5b · 5c · 5d · 5k · 5n» en una sola escondía que son cinco pantallas distintas
compartiendo un único «sin empezar», y con eso 5d —que está a una ronda—
parecía tan lejos como 5n.

| Frame | Impl | Design | Claro | Oscuro | Escrit. | Tablet | Móvil | RT | T | Qué falta exactamente |
|---|---|---|---|---|---|---|---|---|---|---|
| **5a** cola | sí | t5 claro + t9 `7a-pacific-p1..p3` / `7a-aubergine-p1..p3` | **sí** | **sí** | **sí** | **sí** | **sí** | **sí · vivo** | sí · **11** en `payroll_queue_surface_adaptive_test` | **CERRADO (2026-08-01, décima sesión), con las SEIS casillas vivas** contra los 4 borradores reales (S27 · 29 jun – 05 jul · $225.000 · 4 personas), sesión `62796`, y **sin pulsar `Confirmar semana`**. Comparación una a una contra `7a-p2`, que era lo que faltaba: las ocho pistas, la fila abierta con `CÓMO SE CALCULÓ` / `PAGOS DE ESTA SEMANA` / `ATAJOS` y su barra de acento calzan. **Dos defectos que sólo aparecieron mirándolo de a uno, y quedaron corregidos:** (1) `PAGOS DE ESTA SEMANA` mostraba `Bancos - Cuenta Corriente · 1110`, que es la **cuenta contable del ERP**, presentada donde 7a dibuja la cuenta **destino** del trabajador — una pantalla afirmando un destino falso. Ahora sale del dato canónico del trabajador (`bank_name` + `BankAccountType` + últimos cuatro dígitos enmascarados), viaja tipada como `PayrollRowDestinationVM` y se lee en la **misma** consulta de empleados, sin N+1. En producción **nadie tiene banco cargado**, así que hoy la fila dice `Sin cuenta de destino registrada` en ámbar, con el atajo `Cambiar método de pago` (5g) al lado: callar habría dejado la pantalla igual de muda. En compacto el dato va como `Cuenta de destino`. (2) La pista de teclado de 7a era **sólo un rótulo sin conducta**; ahora `↑`/`↓` mueven el foco **de fila** —no a los controles de adentro— y `↵` abre y cierra la enfocada, con anillo de foco visible; «una sola abierta a la vez» ya lo garantizaba el host con un único id expandido. La pista se escribe **porque la conducta existe**. `Ordenar: pendientes primero` **sigue descartado**, citando la decisión exacta: `AGENT_VISUAL_WORKFLOW.md` §5.b lo nombra como ejemplo de «No aplica acá → se descarta» («un `Ordenar: pendientes primero` que nadie va a tocar») |
| **5i** Historial | **sí** | t5 `5i.png` (sha `a5c6ea0c…`) + `handoff-t9/frames/7b-historial-pacific` (`a398f7a9…`) y `-aubergine` (`44a7297a…`) | **sí** | **sí** | **sí** | **sí** | **sí** | **sí · vivo** | sí · **12** en `payroll_history_surface_adaptive_test` | **CERRADO (2026-08-01, décima sesión), con las SEIS casillas vivas contra producción** en la sesión canónica `62796`: claro y oscuro × 1360 / 834 / 430, y el brillo devuelto a `Oscuro` comprobado por píxel. **La causa de que no coincidiera:** la superficie estaba construida contra `5i` (turno 5) y el vigente es **`7b` (turno 7)**, que **no coincide con 5i en la composición del libro de personas** —5i tarjetas, 7b tabla de seis pistas con `MÉTODO Y FECHA`—. Gana 7b por posterior. Ahora la lista es un panel de 300 a ras con divider (era tarjeta flotante), el estado se lee por **punto + rótulo** y no por píldora, el detalle vive **sobre el canvas** con la cifra dominante y `registró <nombre> · <fecha>`, y la banda son cinco celdas iguales con `A PAGAR` a 16 en acento. **Descartados con razón medida, no supuesta:** `Reabrir semana` (el RPC de reapertura exige `confirmed` y el historial sólo trae `paid`/`voided`), `Ver bitácora` (§4.4, reverificado), el **selector de mes** (el RPC pagina por keyset, no acepta mes) → adaptado a **agrupación por mes**. **`S-06` deja de bloquear esta pantalla**: en compacto la lista es el control (lista → detalle → volver) y el select de 30 semanas desapareció; S-06 sigue abierto como componente compartido (§4.b.25). Ledger del plan §15 con el registro completo de la compuerta |
| **5e** composer | sí | t5 + `7d-composer-*` | sí | **no** | sí | **n/r** | **no** | parcial | sí · 5 en `payroll_payment_composer_adaptive_test` | la matriz brillo × host, entera. **RT BLOQUEADO POR ESCRITURA, medido el 2026-08-01.** El composer sólo se abre desde `pendingTransfer`, y `_statusOf` devuelve `weekNotConfirmed` mientras la semana esté `draft`. Producción: **4 `draft`, 26 `paid`, cero `confirmed`, cero `partial`** — llegar ahí exige `commitWeek`, que es un write. **No se acepta arnés como sustituto**: se intentó y las capturas salieron con los glifos de la fuente de prueba, así que se descartaron y el generador se borró. Lo que **sí** entró, leído literal del canvas (la sección `t7` cae antes del corte de 256 KiB): hoja **560** (era 540; el 522 del HTML es ancho de contenido) y las tres tarjetas `MODO DEL PAGO` a **46** de alto, activa en `selectionRow` + borde de acento, inactiva en `sunken` + `divider`. Dos contratos nuevos con mutación probada |
| **5f** efectivo | sí | t5 + `7d-efectivo-*` | sí | **no** | sí | **n/r** | **no** | parcial | sí · 3 en `payroll_redesign_surface_test` | ídem 5e. **RT BLOQUEADO POR ESCRITURA**, misma causa que 5e (ver esa fila). Entró la hoja de **480** (era 390, que no salía de ningún archivo de Design) |
| **5j-p3** OCR propuestas | **sí** | t5 + **t9 `7c-ocr-{pacific,aubergine}`** | **sí** | **sí** | **sí** | **sí** | **sí** | **parcial · bloqueado por el picker** | sí · 6 asertos + **2 contratos de 7c** | **IMPLEMENTADO contra `7c` (proyecto `ERP Bikeshop UI Mockups`, página `Nóminas - Rediseño`, turno 7), leído literal del canvas.** La fila pasó a las **siete pistas** `26 · 76 · 1fr · 118 · 1.1fr · 148 · 84`, gap 10 y padding `10 16`; la **razón bajó bajo la persona** —`PERSONA Y RAZÓN`, como dibuja 7c— en vez de ocupar columna propia; la fila marcada pasó de `sunken` a **`selectionRow`**, que es su rol; y se agregó `PayrollReviewColumnHeader` con los rótulos exactos `FECHA · DESCRIPCIÓN EN LA CARTOLA · MONTO · PERSONA Y RAZÓN · CONFIANZA`, sólo desde 900. **La pista de acción se declara distinta**: 7c pone 84 para su enlace `Cambiar`, y acá vive el control de decisión de la gramática 2c —verbo + `⋯`—, que no se recorta para calzar un ancho. **Wording adjudicado y aplicado en todo el flujo**: `Cargar cartola · Lectura · Propuestas · Aplicar`, más el cuerpo `Carga la cartola`. **`YA APLICADA` y el atenuado a .55 de 7c NO se implementan**: no existe estado por fila de «ya aplicada» en este flujo —es una de las siete afirmaciones falsas que §3 ya documenta—. **RT: el paso 1 quedó verificado vivo en las seis casillas** con el wording nuevo (sesión `38873`); **los pasos 2–4 están bloqueados por el selector de archivos**, ver §4.23. **RT AMPLIADO el 2026-08-01, ya con el picker desbloqueado:** recorrido real con la cartola del negocio —`page-01.png · 1 página · 14 movimientos`, `14 filas · 7 cargos`, `22/07/2026–29/07/2026`, `Cierre declarado 28/07/2026`— hasta el paso 3, con el stepper diciendo `Cargar cartola lista · Lectura 14 movimientos · Propuestas 0/10 · Aplicar 0/4 efectivo`. **Tres casillas OSCURAS vivas: 1360 / 834 / 430.** El estado real de esta cartola es **10 preguntas y 4 fuera de nómina**, así que lo que domina la pantalla es la tarjeta de pregunta de la gramática 2c (`1 DE 10`), y **la tabla de siete pistas de `7c` no se dibuja porque no hay ningún calce sugerido** — es un hecho de los datos, no un hueco. **CLARO COMPLETADO el 2026-08-01 (undécima sesión)**, recargando la cartola con el brillo **ya en claro**, que era la receta que faltaba: `page-01.png · 1 página · 14 movimientos`, `14 filas · 7 cargos`, `10 necesitan tu decisión · 4 fuera de nómina`, y las **tres casillas claras 1360 / 834 / 430** (`shots-5c/ocr-light-*.png`). Con eso `5j-p3` queda con las **SEIS**. Se confirma en claro el mismo hallazgo del oscuro: **la tabla de siete pistas de `7c` no se dibuja porque esta cartola no trae ningún calce aceptado** — domina la tarjeta de pregunta 2c (`1 DE 10`). `Ir a aplicar` estuvo **deshabilitado todo el tiempo** («Falta elegir la cuenta ERP»), se salió con `Salir sin guardar` y **no se escribió nada**. La causa que lo tuvo pendiente, ya derogada: cambiar el brillo obliga a salir del módulo y cambiar el brillo obliga a salir del módulo a Configuración, y **el borrador no sobrevive a salir** (comprobado: al volver, la etapa 1 está limpia). Para capturarlo hay que **recargar la cartola ya en claro**; con `choose-file` arreglado eso ahora es posible. `Aplicar` nunca se pulsó — además está deshabilitado hasta elegir la cuenta ERP |
| **5g** método de pago | **sí** | `5g.png` íntegro (918×546) | **n/r** | **sí** | **sí** | **n/r** | **n/r** | **sí · vivo** | sí · 19 en `payroll_employee_payment_method_command_test.dart` | **IMPLEMENTADO Y CORREGIDO (2026-08-01, séptima sesión).** `payroll_method_sheet.dart` + comando estrecho con adaptador `PayrollEmployeePaymentStore` + atajo «Cambiar método de pago» en la fila. **Verificado en la app viva contra producción, en oscuro a 1360×757**: transferencia con el select del dominio real, efectivo sin campos bancarios, y el aviso «Sus **27** pagos registrados» para Vicente Díaz — el mismo 27 que reporta la lectura de producción. Capturas: `final-5g-transfer.png`, `final-5g-dominio.png`, `final-5g-efectivo.png`, `audit-5g-conteo-exacto.png`. **Owner canónico nuevo:** `BankAccountType` toma sus tres valores de `employees_bank_account_type_check`; lo reusan el editor de fichas y 5g. **Octava sesión (2026-08-01): cinco de los siete puntos de Codex RESUELTOS y las seis casillas capturadas en vivo — ver §4.b.** Nace el owner compartido **`S-05 · VbShortSelect`** (`lib/shared/widgets/vb_short_select.dart`, 22 pruebas) con popover anclado en escritorio y **bottom sheet `O-05` en compacto**; lo usan el TIPO de esta hoja y la cuenta ERP del conciliador. El tercer consumidor —la semana histórica— **es S-06 y no se migró**, con la medición que lo prueba. Quedan abiertos, con nombre: **el RPC atómico (26), bloqueado por la frontera sin writes**; **`S-06`**, que no existe en el repo; el ancho **424 vs 460** del host del diálogo, compartido con 5d; y el menú del editor de fichas, que no se pudo abrir |
| **5h** Anticipos | sí | `5h-p1/p2` | **sí** | **sí** | **sí** | **sí** | **sí** | **sí · vivo** | sí · 7 + 4 + **1** | **CERRADO (2026-08-01, décima sesión).** Las bandas se releyeron **enteras**, que era la deuda de §4.7: el 3 % que nunca se había visto es el panel **`Semana corta`** de `5h-p2` —«GUILLERMO · TERMINA EL MIÉRCOLES», con `Horas cerradas hasta el 30/07` / `Total de la semana parcial` / `Anticipo vigente` / `A entregar hoy` y los botones `Liquidar semana corta` y `Cerrar horas en Asistencias ↗`—. **Descartado como panel operable, con su razón:** `Liquidar semana corta` es liquidar **a una persona** de una semana en borrador, y el backend confirma **la semana entera** (`commitVoucher`); no existe `shortWeek`/`partialWeek` en el módulo, y además sería una escritura. Lo que el frame quiere comunicar ya lo dice la franja ámbar existente, y `Cerrar horas en Asistencias ↗` ya es la salida canónica. **Corregido de paso el defecto §4.6**: en compacto el campo del selector cortaba la glosa en seco (`Rodrigo … · $36.000 aplica`), porque `DropdownMenu` escribe su `label` en un campo sin elipsis; ahora el campo lleva persona y saldo y la glosa viaja en `labelWidget`, que sólo se dibuja dentro del menú. **SEIS casillas vivas** contra el único anticipo vigente real de producción (Rodrigo Guillermo Nieto · $36.000 · 2 movimientos), claro y oscuro × 1360/834/430, brillo devuelto a `Oscuro`. **El formulario `Nuevo anticipo` también se abrió en la sesión real y se comparó con `5h-p1/p2`** —y `Registrar anticipo` **nunca se pulsó**: se cerró con `Cancelar`, y producción sigue con 3 anticipos / $92.500 y su último `created_at` del 13/07—. **`APLICACIÓN` («Dejar vigente» vs «Imputar a una semana ahora») DESCARTADO con evidencia de backend:** `register_employee_advance_v2` recibe `p_operation_key, p_employee_id, p_amount, p_payment_method_id, p_payment_account_id, p_paid_at, p_reference, p_notes` — **sin semana ni comprobante**, y ninguna de las 13 funciones `%advance%` de producción crea e imputa a la vez. Imputar ocurre **al pagar**, que es justo lo que la pantalla ya afirma. **`MOTIVO` IMPLEMENTADO**, porque sí está soportado: la columna del ledger ya existía y se mostraba, pero el formulario mandaba siempre la misma frase de relleno; ahora hay campo y viaja en `p_notes`, delante del origen (`Locomoción · registrado desde el centro de nóminas.`). Va como **texto libre y no como la lista corta del frame**: no existe catálogo de motivos en el esquema. **`CÓMO SE ENTREGA` adaptado**: el frame ofrece dos botones `Efectivo`/`Transferencia` y la app ya tiene `Método y cuenta de entrega`, que es un superconjunto —incluye la cuenta contable—; bajar a dos botones perdería ese dato. **Defecto de compacto corregido**: a 430 la ayuda del motivo se elidía justo donde explicaba el campo (`helperText` es de una línea); ahora envuelve. Capturas del formulario en claro y oscuro × 1360/834/430. **`PayrollAdvanceEntry` migrado al vocabulario montado de Nóminas**: se fue `theme.textTheme`/`colorScheme` crudo y el aviso dejó de ser un `Container` con `surfaceContainerHighest` y radio a mano — ahora es **`E-04 · VbNotice`**, el owner compartido bajo su id. Se conservan las adaptaciones ya justificadas: método **y cuenta** real, motivo libre, sin `APLICACIÓN` ni `Semana corta`. **Trampa que dejó el arnés al descubierto:** `VbNotice` exige los roles canónicos y **se niega a pintar sin `AppTheme`**; el arnés montaba un `MaterialApp` pelado, así que hubo que construir el tema como en `vb_notice_contract_test`. **Y una prueba mía era falsa y quedó corregida:** afirmaba que «el MOTIVO viaja en `notes`» sin hacer submit nunca —`captured` era siempre `null` y no medía nada—. Ahora completa el formulario, pulsa el primario y comprueba el `PayrollAdvanceIntent` que el widget devuelve por `Navigator.pop`: `Locomoción · registrado desde el centro de nóminas.` con motivo y sólo el origen sin él. **Sin servicio ni base de datos**: el intent es el borde del widget. Mutación: quitar el motivo de `notes` → 1 fallo |
| **5l** tarjeta móvil | sí | `5l-1-p1/p2` · `5l-2` | **n/r** | **no** | n/a | n/a | sí | **no** | sí · 2 a 390 px | **NO cerrada.** Falta verificar que el marco sea el del turno 6. Su CTA bajó de 50 a `touchMobile` (**48**) el 01/08 — el frame dibuja 50 y manda `F-06 · TOUCH`—: el **48 queda probado estructuralmente** con igualdad exacta al token, pero **la acción no fue alcanzable visualmente con datos de producción**, porque sólo se dibuja en una semana ya confirmada y llegar ahí exigiría una **escritura real**. RT queda en `no`, no en «parcial»: no hay captura de esa altura y no se inventa una |
| **5m** tablet 834 | **sí** | `5m-p1/p2` | **sí** | **sí** | n/a | **sí · vivo** | n/a | **sí · vivo** | sí · **3** en `payroll_queue_surface_adaptive_test` | **CERRADO (2026-08-01).** El hueco no era visual sino de host: **a 834 la página montaba las tarjetas de teléfono**, no la tabla de 5m. El frame separa las dos preguntas y su nota 03 lo dice: bajo 900 el **chrome** es compacto —header único con drawer, «el contrato de 3c se mantiene intacto»—, pero el **contenido** sigue siendo la tabla. Ahora el host tiene banda de tablet (`_isTabletBand`, piso 720) y monta `PayrollQueueSurface`; el tier ya existía en la superficie y **nadie lo instanciaba**. Implementado además lo que la banda pedía y no estaba: **fila de 60** y el **mismo** control de decisión a **44 × 200** —nota 02 del frame, «sin cambiar de forma ni de verbo»—, y la barra monetaria de **una sola acción** se apila (nota 04). **Verificado vivo a 834 en claro y oscuro** contra los 4 borradores reales: cuatro columnas `PERSONA · TOTAL · A PAGAR · DECISIÓN`, sin `ANTICIPOS`, sin `PAGADO`, sin `MÉTODO`. **Lo único sin confirmar en vivo es la barra apilada**: el cambio está hecho y con la batería en verde, pero el hot reload que lo llevaría no llegó a aplicarse y no se relevó la sesión por eso |
| **5d** confirmar semana | **sí** | `5d.png` íntegro (150.868 B) · spec `7ed210f0…` | **sí** | **sí** | **sí** | **sí** | **sí** | **sí** | **sí** · 6 en `payroll_redesign_surface_test` | **las seis celdas capturadas e inspeccionadas** en la app viva contra datos de producción, sobre el build final (app `29616`, VM `:50292`, levantado con `EXIT_STOP=0` / `EXIT_START=0` y los seis PID del árbol anterior verificados como ausentes). Estructura leída sobre la **lista completa** y apariencia por `shot`; cada celda cerrada con `Volver a revisar` y **el submit nunca pulsado**. Usa `E-04 VbNotice` (5 pruebas) y `F-03 VbMoneyText` (4), creados en esta ronda |
| **5b** sidebar 1116 | **sí** | `5b-p1/p2` | **sí** | **sí** | **sí · 1116** | n/a | n/a | **sí · vivo** | sí · **1** en `payroll_queue_surface_adaptive_test` | **CERRADO (2026-08-01).** Comparado contra el frame en la app viva a 1116: **ya cumplía casi todo** —el método bajo la persona, `ANTICIPOS → ANTIC.`, tarjetas de semana con punto y sin etiqueta, seis pistas `caret · PERSONA · TOTAL · ANTIC. · A PAGAR · DECISIÓN`, y la barra monetaria **sin ecuación**—. **El único delta real era la franja de Asistencias**, que `5b-p2` declara **oculta** a 1116 y la app seguía dibujando. Corregido: la franja se retira en la banda comprimida y **la salida real no se pierde** —la nota de personas fuera del cálculo la ofrece con su razón, y la fila abierta conserva `Abrir en Asistencias ↗`—. Con el sidebar expandido el canvas no sobra, y una franja permanente que sólo recuerda una regla es lo primero que se retira. **Divergencia declarada:** la app comprime el pie **antes** que el frame (`FALTA` y `Confirmar` donde 5b escribe `FALTA PAGAR` y `Confirmar S28`); es más compresión, no una afirmación falsa, y se deja. **Claro y oscuro vivos a 1116**, comprobados por píxel |
| **5c** gramática de decisión | **sí** | `5c-p1/p2` + **t9 `7a-pacific-p2`, leído literal del canvas** | **sí** | **sí** | **sí** | **sí** | **sí** | **sí · vivo** | sí · **11** en `payroll_queue_surface_adaptive_test` + **3** en `payroll_redesign_surface_test` | **CERRADO (2026-08-01, undécima sesión), con las SEIS casillas vivas** contra los 4 borradores reales (S27 · 29 jun – 05 jul · $225.000 · 4 personas), sesión `44281`, sin pulsar `Confirmar semana`. `5c` no es una pantalla: es **el contrato del control de decisión** —cinco formas × cinco estados—, y el hueco estaba en la quinta. **La forma pasiva era una píldora tonal**, la misma figura que las cuatro activas; como producción tiene las cuatro semanas en `draft`, **las cuatro filas del módulo caían ahí** y la tabla entera parecía accionable sin serlo. Ahora es **texto pasivo**, leído literal de `7a` (la fila de Rocío en el canvas): `font:400 11px 'IBM Plex Sans'; color:#7E8A94` = `inkFaint`, a la derecha, sin fondo, sin borde y sin radio — la anotación del frame lo dice sola: «Rocío no tiene botón». **Entró además la envoltura compartida que `5a` no había mirado** (comparó pistas y fila abierta, no átomos): `28 de alto · 186 de ancho máximo · padding 0 10 · radio 8 · gap 6 · borde 1`, rótulo `500 11`, meta mono `9,5` al 75 %, `›` de 12 al 60 %, `▾` de 9 tras un divisor de 1 con 7 de separación. El chip `Pagado` y el de método venían de **cápsula y ~19 de alto**. **`Sin método` pasó de ámbar a `danger`**: heredaba el tono del estado de la fila y se pintaba igual que «falta confirmar», que sí se puede pagar; `7a` lo dibuja `#33191A`/`#6E332F`/`#F08C82` y el mapa de uso del turno 9 dice «danger: chip Sin método». **FOCO** como pide el frame: anillo de **3 px por fuera del borde, sin reemplazarlo**, acento al 35 % (en oscuro, el del preset = `interaction.focusRing`); «visible con teclado, no con clic» salió comprobando en el SDK montado que **un `InkWell` no toma el foco al tocarlo con el puntero**. **ADAPTADO con razón:** (a) `Falta confirmar` → **`Semana sin confirmar`** — en Design esa frase es el **efectivo entregado y pendiente**, una fila que sí se resuelve, y la tarjeta de la semana ya rotulaba `SIN CONFIRMAR`; (b) el motivo del bloqueo **no viaja en `Tooltip`** sino en `Semantics.tooltip` (ver §4.24: el `Tooltip` tumbó el módulo en vivo); (c) en el teléfono el motivo sólo se dibuja cuando es **de la persona** (`nothingToPay`), porque el de la semana era idéntico en las cuatro tarjetas y se comía los cuatro registros del primer viewport que exige `5l`; (d) la tipografía de la decisión **no encoge** entre bandas — `5b` manda «las etiquetas largas se truncan con elipsis». **DESCARTADO con razón:** los verbos por método de Design (`Transferir` / `Confirmar efectivo`) — se mantiene **`Pagar`** para los dos, decisión ya documentada: el método está una columna a la izquierda y lo que cambia es la evidencia, no la intención; y **el monto dentro del primario** (`Transferir $172.875`), porque `A PAGAR` está pegado a la izquierda a 14/700 en acento, es la cifra dominante de la fila y sigue estando a 834. La tira de **estados de semana** de `5c` ya estaba adjudicada e implementada (`EN CURSO` / `SIN CONFIRMAR` / `PAGADA` / vacío) y no se reabre  **REVISADO EN ULTRACODE (2026-08-01) y con dos correcciones, ver §4.24:** (1) mi causa raíz estaba a medias — el crash **no** es «un `Tooltip` por fila» sino **un `Tooltip` VISIBLE** al cambiar de banda, y **el defecto es anterior a `5c`**: el `tooltip:` del caret lo produce igual. Reproducido en proceso **limpio, sin hot reload**. Ahora la cola **no monta ningún `Tooltip`**, con contrato sobre toda la superficie. (2) `Semantics.tooltip` **no bastaba** para quien usa el mouse: el motivo volvió a verse, en el vehículo que dibuja el propio `7a` —la franja del pie— con el dueño canónico **`E-04 · VbNotice`**; se dice una vez cuando el motivo es compartido, y si no lo es la franja calla y cada fila abierta lleva el suyo. **P2 corregido de paso:** ese panel duplicaba la franja y dejaba la fila con cuatro paneles donde `7a` dibuja tres. **Lo único no fotografiado en vivo** es el anillo de foco de 3 px de la celda: en producción todas las filas son pasivas y el recorrido de teclado pinta antes el anillo de la FILA, que domina la captura; el de la celda queda probado por contrato (aparece con `Tab`, no con clic) y por mutación |
| **5k** siete estados | **parcial** | `5k.png` íntegro (191.845 B) | **sí** | **sí** | **sí** | **sí** | **sí** | **sí** | sí · 9 + 9 | **`carga` CERRADO** como `X-01 · VbSurfaceState` (`lib/shared/widgets/vb_skeleton.dart`) + `_PayrollLoadingSkeleton` en el gate de `payroll_redesign_page.dart`. **Las SEIS celdas capturadas en la app viva contra producción**: claro y oscuro × 1360 / 834 / 430, cada una con el esqueleto **en pantalla** —no el estado cargado, no el drawer, no el Dashboard—. **Las cuatro compactas** (claro y oscuro × 834 y × 430) son de la sesión `69949`/`:59077` —**PID histórico**, como `1320`/`:51308`; la sesión viva se lee de la tabla VIGENTE del encabezado— y **siguen vigentes**: la silueta compacta dibuja tarjetas, no tabla, así que no depende de `ghostRowsFor`. **Las DOS de escritorio se volvieron a capturar en `83620`/`:62489`** (también histórico) —oscuro y claro, las dos— después de derogar el techo de filas, porque ese conteo es exactamente lo que muestran: sin tope la tabla llena el hueco hasta la barra de dinero (**13 filas** a 1360×789) en lugar de cortarse en 6 y dejar un vacío. Para la clara se cambió el brillo y **se devolvió a `Oscuro`**, comprobado con el check en su sitio. Ruta de las capturas vigentes: `celda-oscuro-escritorio-sintecho.png`, `celda-claro-escritorio-sintecho.png`, `celda-oscuro-compacto.png`, `celda-oscuro-movil.png`, `celda-claro-tablet.png`, `celda-claro-movil.png`, en el scratchpad de la sesión. **`vacío` también HECHO**: uno general honesto que ya no afirma la causa, más «Aún no hay nadie contratado» con salida a Trabajadores — la única causa que el esquema garantiza (§4.13). **No es alcanzable en vivo sin escribir** (§4.19), así que va por contrato. **`error` diagnosticado y bloqueado por ownership** (§4.20). **`permiso` NO está implementado y NO es derivable** (§4.21): esta superficie no tiene owner ni capacidad de rol, `blockedReason` **no es RBAC** y no cuenta como cierre de permiso. Con eso, **5k está cerrado hasta donde una migración visual puede llegar, y el estado de permiso queda ABIERTO con nombre**. Cola local y `Deshacer` **descartados** con razón (ledger 01/08) |
| **5n** matriz de cierre | no | `5n-p1/p2/p3a/p3b/p4` | — | — | — | — | — | — | — | sin empezar |
| **OCR paso 1** cargar | **sí** | `5j-paso1.png` | **sí** | **sí** | **sí** | **sí** | **sí** | **sí** | sí · 6 en `payroll_ocr_step1_contract_test.dart` | **CERRADO (2026-08-01).** Tres tarjetas «qué esperar de cada fuente» **debajo** de los botones, como dibuja el frame. **Seis celdas vivas** contra producción (sesión `1320`/`:51308`, **PID histórico**) **más dos capturas con scroll a 430** que demuestran que la tercera tarjeta se alcanza entera sobre la barra fija. **Sin cargar ningún archivo.** Se descartó «IMPORTACIONES ANTERIORES» —sin lector y sin nombre de archivo que mostrar—, la «guía de encuadre» inexistente y la «confianza por línea» que no existe; se corrigió el límite a los **12 MB** reales contra los 20 del frame |
| **OCR paso 2** lectura | **sí** | `5j-paso2.png` | **sí · 1360** | **sí · 1360** | parcial | parcial | parcial | **sí · vivo (parcial)** | sí · 9 en `payroll_reconciliation_responsive_test.dart` | **FUNCIONALMENTE CERRADO; EVIDENCIA VIVA PARCIAL (2026-08-01).** **Queda derogado el «no es alcanzable en vivo sin subir un archivo real»**: sí lo es —cargar el archivo es una operación **local**, y el primer write ocurre dentro de `_apply()` (§4.c)—. Verificado contra producción con la cartola real: `page-01.png · 1 página · **14 movimientos**`, la política de cuatro filas visibles y su pie real «… 6 egresos más con todos sus campos reconocidos y sin avisos.», que hasta entonces sólo tenía prueba de harness. **Lo que falta es la matriz completa**: se capturó a **1360**; 834 y 430 no se recorrieron para esta etapa. Las capturas de harness anteriores (`shots-final/paso2-*`) quedan como **histórico**, no como evidencia vigente. **Deuda visual exacta y abierta:** separaciones `7`/`10`/`11` del panel, `fromLTRB(17, 9, 17, 11)` del pie y `fontSize 10.5`, todas preexistentes y sin fuente en Design ni owner |
| **OCR paso 4** aplicar | **sí** | `5j-paso4.png` íntegro (104.794 B) | **sí** | **sí** | **sí** | **sí** | **oscuro sí · claro NO** | **sí · vivo (oscuro)** | sí · 9 + navegación/elisión/CTA en `payroll_reconciliation_responsive_test.dart` | **CERRADO FUNCIONALMENTE, CON EVIDENCIA VIVA EN OSCURO (2026-08-01).** Recorrido completo contra **producción** con la cartola real del negocio (`tmp/pdfs/cartola_analysis/page-01.png`, fuera de git): `1 página · 14 movimientos` → **10/10 decisiones** → una sola fila de efectivo respondida (**Semana 30**) → **`Aplicar 1/4 efectivo`**. Cifras reales en pantalla: **`Total a aplicar $38.000`**, **`IMPACTO POR SEMANA · $200.750 → $162.750`**, `Pagos que se crearán 1`, `Excluidos por ti 10`, `Pendiente $38.000 − Anticipo $0 − Efectivo $38.000 = Resto $0`. **TRES celdas vivas, todas OSCURAS: 1360 / 834 / 430** en la misma sesión (`62796`), con el **CTA entero en las tres** —`Confirmar 4 semanas y aplicar conciliación`, sin `Confirmar 4 sema…`— y los pasos sin elidir. Capturas: `<scratchpad>/shots-ocr-final/final-{1360,834,430}.png`. **CLARO NO ESTÁ VERIFICADO EN VIVO PARA ESTA ETAPA**: durante la reconstrucción final no se cambió el brillo. Lo único que existe en claro son las capturas de **HARNESS** del cierre anterior (`<scratchpad>/paso4-bKOxik/paso4-light-{1360,834,430}.png`), con cajas en vez de fuentes — **históricas, sobre un build anterior a las correcciones del CTA y del stepper, y no re-verificadas**. La matriz de seis casillas de este frame **NO está completa**. **`Aplicar` nunca se pulsó** y el borrador se descartó con `Salir sin guardar`. **Deroga la línea anterior de esta fila**, que decía «visualmente de harness» y «no alcanzable en vivo sin subir un archivo real»: eso confundía *subir un archivo* —que es local— con *escribir en producción*; el primer write ocurre dentro de `_apply()` (§4.c). Se conservan las decisiones de contenido: se descartaron `Gasto a Contabilidad`, el desglose «0 nuevos, 4 ya aplicados» y el pie propio del frame; `Total a imputar` → **`Total a aplicar`**. Defectos abiertos: **`wasReplay` está muerto** (§4.22) y **claro sin verificar** |

### De dónde sale la columna T — verificado el 2026-08-01, no de memoria

**`T` no significa «la batería está verde».** Significa que *esa* superficie
tiene una prueba que la ejercita. La distinción no es cosmética: la batería
completa estaba en **307/307** el día que se escribió esta tabla, y aun así
**5m no tiene ninguna prueba propia**. Convertir un verde global en prueba
específica es exactamente cómo un frame se da por cerrado sin estarlo.

| Frame | Pruebas propias | Dónde |
|---|---|---|
| **5a** | **11** | `test/widgets/payroll_queue_surface_adaptive_test.dart` — las 8 anteriores más tres de esta ronda: `↑`/`↓` mueven el foco de fila y `↵` abre la enfocada (sin wrap-around en los extremos), la pista de teclado sólo existe en la fila abierta, y `PAGOS DE ESTA SEMANA` nombra la cuenta **destino** enmascarada o declara que falta. Mutaciones: anular `onMove` → 1 fallo; devolver la glosa a la cuenta contable → 1 fallo |
| **5i** | **12** | `test/widgets/payroll_history_surface_adaptive_test.dart`, reescrito contra 7b: banda en orden · las seis pistas con `MÉTODO Y FECHA` · el escalón que baja el método a subtítulo · saldo abierto declarado y saldo cero mudo · punto+rótulo y lista de 300 a ras · agrupación por mes sin select · ausencia de `Reabrir semana`/`Ver bitácora` · paginación y su falla · los dos pasos del compacto · historial vacío. Más el caso vivo de `payroll_redesign_surface_test.dart` («historial pagado/anulado hidrata lazy…»), migrado al disclosure compacto |
| **5e** | **7** | `test/widgets/payroll_payment_composer_adaptive_test.dart` — las 5 anteriores más los dos contratos de `7d`: hoja de **560** en escritorio, y las tres tarjetas de modo a **46** con `selectionRow`/`sunken` en **los dos brillos**. Mutaciones: fondo activo a `accentSoft` → 1 fallo; alto a 48 → 1 fallo |
| **5f** | 3 | `test/widgets/payroll_redesign_surface_test.dart` L375 «2e: efectivo confirma entrega y nunca autoavanza» · L571 · L1741 |
| **5g** | 2 | `test/widgets/payroll_redesign_surface_test.dart` L325 «2b permite una transferencia parcial…» · L624. **El sheet que falta no tiene prueba porque no existe** |
| **5h** | 7 + 4 + **5** | `test/widgets/payroll_advances_ux_test.dart` · `test/widgets/payroll_advances_surface_pagination_test.dart`. Los contratos nuevos son tres: §4.6 —el `label` del selector compacto **no** lleva la glosa, que va en `labelWidget` con elipsis; mutación: devolverla al `label` → 1 fallo—, el campo `MOTIVO` con su ayuda, y que esa ayuda **envuelve** en vez de elidirse a 430 |
| **5j-p3** | 6 asertos + **2** | `test/widgets/payroll_reconciliation_responsive_test.dart` L783·1104·1222·2135·2509·2603, sobre `PayrollReviewTableRow` — que además está **montada de verdad** en `lib/modules/hr/pages/payroll_reconciliation_page.dart:3186`, no sólo declarada |
| **5l** | 2 | `payroll_mobile_person_disclosure_test.dart:12` «la tarjeta móvil expone un disclosure accesible sin overflow a 390 px» · `payroll_redesign_surface_test.dart:1163` «5l · el CTA de la tarjeta de persona mide TOUCH 48, el valor del owner de densidad» |
| **5m** | **3** | `payroll_queue_surface_adaptive_test.dart`: las cuatro columnas a 834 —comprobando **las dos grafías** del rótulo, porque al estrecharse se abrevia a `ANTIC.` y mirar sólo `ANTICIPOS` dejaba pasar la columna entera—, la fila de 60 con el control a 44 × 200, y que el tier no se filtra a escritorio. Más el contrato de shell, que ahora distingue **chrome compacto** de **contenido de tabla** en 899/834 frente a las tarjetas de 390. Mutaciones: anular la banda de tablet → 1 fallo; bajar el umbral de `ANTICIPOS` → 1 fallo |

## 2.c La compuerta de seis dimensiones, en formato de entrega

**El dueño canónico es `AGENT_VISUAL_WORKFLOW.md` §5.b** — ahí están las seis
preguntas, con qué se resuelve cada una, qué hacer con cada resultado y el caso
que justifica la regla. No se repite acá; se lee allá, **por frame y antes de
escribir código**.

Lo que vive acá es el formato de entrega, para que el chat siguiente no tenga
que reconstruirlo:

```text
Frame <id> · turno <t> · página <…> · spec sha256 <…> · componentes <S-05, …>

1 ¿Existe en este negocio y en sus datos?  <evidencia: consulta, dato, servicio>
2 ¿La palabra es la correcta?              <la del dueño, en chileno>
3 ¿El backend/servicios/permisos lo dan?   <RPC real, o «capacidad nueva»>
4 ¿Navegación, retorno y ownership calzan? <ruta, cierre, superficie canónica>
5 ¿Aguanta los DOS EJES?                   <seis celdas, ninguna en blanco>
     brillo × host    escritorio   tablet   móvil/compacto
       claro             ?           ?            ?
       oscuro            ?           ?            ?
     (sí / no / n/r — «n/r» es no registrado, y NO es «n/a»)
6 ¿Reutiliza lo canónico?                  <component id, token, rol>

Se copia:          <…>
Se descarta:       <… + POR QUÉ>
Se agrega/adapta:  <… + POR QUÉ>
Divergencia declarada: <si Design contradice dominio, datos, accesibilidad,
                        navegación o capacidad real, se conserva su dirección
                        VISUAL y se corrige la hipótesis de producto>
```

**Un frame de Design es una propuesta sobre el aspecto, no una orden sobre el
producto** (criterio del dueño, 2026-08-01). Design manda el *looking*; que
exista, que se entienda, que se navegue y que la palabra sea la correcta los
aporta el agente. Ese bloque, relleno, es lo que se pega en el ledger (§15 del
plan) **al cerrar el frame**: sin él el frame no está cerrado, por §0.b punto 2.

### Trazabilidad de Design — incompleta, declarada

- **Component ids — recuperados el 2026-08-01** de `GUÍA GENERAL Viñabike ·
  Componentes` con `DesignSync get_file`, grepeando el archivo en disco (no
  cargándolo al contexto). Familias legibles: `A-01…03` · `D-01` · `E-01…05` ·
  `F-01…06` · `I-01…04` · `O-01…05` · `S-01…06` · `T-01…05` · `X-01`.

  Los que aplican al **diálogo de 5d**, leídos del rótulo de `O-02`
  («…Dialog (**O-03**) Side sheet (O-04) Bottom sheet (O-05)»):

  | id | Componente | En 5d |
  |---|---|---|
  | **O-03** | `Dialog` | el modal |
  | **E-04** | `VbNotice` · banner/notice | el aviso de consecuencia — el ejemplo de la propia guía es «Las horas se editan en Asistencias» |
  | **A-01** | `VbButton` (`primary` \| `text`) | los dos botones del pie |
  | **F-03** | `VbMoneyText` | las cifras |
  | **S-01** | `Checkbox` | **descartado**: los dos efectos laterales son capacidad nueva |

  **Qué owner satisface cada uno, hoy** (verificado el 2026-08-01; una versión
  anterior de este párrafo decía que *ningún* `Vb*` existía y dejaba `E-04` para
  otra ronda — **ya no es cierto y no debía quedar así**):

  | id | Owner real | Contrato |
  |---|---|---|
  | **E-04** `VbNotice` | **`lib/shared/widgets/vb_notice.dart`**, creado en esta ronda bajo su id. Color por `VinabikeSemanticTone`, geometría leída del archivo | `test/widgets/vb_notice_contract_test.dart` — 5 pruebas: 5 tonos × 6 presets × 2 brillos, geometría publicada, anuncio único, glifo decorativo mudo |
  | **F-03** `VbMoneyText` | **`lib/shared/widgets/vb_money_text.dart`**, creado en esta ronda bajo su id | `test/widgets/vb_money_text_contract_test.dart` — **4 pruebas**: formato CLP, `inkFaint` = `neutral.accent` para cero y «no aplica» cruzado en 6 presets × 2 brillos, mono tabular 700/14 a la derecha, 9 dígitos sin truncar |
  | **O-03** `Dialog` | El **tema del resolver** + `Dialog` de Material. No hace falta wrapper | cubierto por los contratos de tema del resolver |
  | **A-01** `VbButton` | El **tema del resolver** + `FilledButton` / `TextButton`. **`lib/shared/widgets/app_button.dart` NO sirve**: usa `Colors.white` y `Colors.red[600]`, hex literal que la primera regla de la guía prohíbe | ídem |
  | **S-01** `Checkbox` | No se usa en 5d — los dos efectos laterales del frame son capacidad nueva | — |

  `VbHoursText` (la otra mitad de F-03) **sigue sin owner**: la guía lo nombra
  junto a `VbMoneyText` y esta ronda sólo necesitaba dinero. Queda con nombre,
  no como «deuda» difusa: se crea junto a `vb_money_text.dart` cuando una
  superficie muestre horas.

- **Hash del `spec.json`** — registrado el 2026-08-01:
  `sha256(handoff-t5/spec.json) =`
  `7ed210f0dfff6d8afe9ec52d1e154730a1fbd7f563e15db25d442100067dd540` ·
  `sha256(handoff-t5/frames/5d.png) =`
  `13211c24ecb378c5d98e6fd8470bb2191f085010f0b3f85a83b5262991083eac`.
  Los de `handoff-t9` siguen **sin registrar**.

- **El canvas `Nóminas - Rediseño.dc.html` llega truncado, pero el turno 7 entra
  entero y el turno 5 no** (verificado el 2026-08-01; **matizado el mismo día**,
  ver el párrafo siguiente). `get_file` devuelve 256 KiB con `truncated: true`;
  el archivo va **del turno más nuevo al más viejo** —`t7` primero, después
  `t6`— y **el corte cae dentro de `6f`** («TECLADO ABIERTO · 390»). O sea:
  **ningún frame `5*` es legible desde el canvas**, y buscar ahí «Paso 4»,
  «RESUMEN ANTES DE ESCRIBIR» o «Total a imputar» devuelve **cero**
  coincidencias — no porque no existan, sino porque están detrás del tope.

  **Corrección del 2026-08-01 (cierre de 5i): el turno 7 SÍ es legible, entero y
  literal.** De la frase anterior se venía deduciendo que el canvas no servía
  para nada, y eso costó leer 7b como si fuera inaccesible. `7a`, `7b`, `7c`,
  `7d`, `7f` y `7g` están **antes** del corte, con sus `font:`, `background:`,
  `border:`, `padding:` y `grid-template-columns` exactos. Se ubican con
  `grep -n 'class="dv-oid" href="#'` sobre el archivo guardado en disco. Para
  todo el modo oscuro del módulo, **ésa es la fuente literal**; el PNG queda para
  mirar la composición.
  **Lo que sí queda como fuente para un frame del turno 5**, en este orden: el
  **PNG publicado** (recorte sin reescalar, así que medir geometría sobre él es
  legítimo — workflow §0 regla 2), el `spec.json` del turno, y la guía de
  componentes para lo compartido. Así se midió la composición del paso 4.
  **El snippet `handoff-t5/payroll_ocr_reconciliation.dart` NO sirve para el
  paso 4**: dibuja una lista de una sola columna y el frame dibuja tres. Es
  anterior, y la regla del turno es que **gana el frame**.

- **La guía llega truncada** y hay que decirlo al citarla: `get_file` devolvió
  exactamente **262.144 bytes = 256 KiB** con `truncated: true`. Los ids de
  arriba están **dentro** de la parte legible; lo que quede pasado el corte no
  se ha leído y no se supone.

  **Dónde cae el corte, verificado el 2026-08-01:** dentro de **`X-01`**, la
  sección *09 Estados de superficie*. `X-01` («Loading · empty · error ·
  no-results · read-only · sin permiso», rótulo `VbSurfaceState`) define **seis
  estados** y sólo el panel **LOADING** es legible. `empty`, `error`,
  `no-results`, `read-only` y `sin permiso` quedan pasado el corte: **no están
  leídos, y no se implementan a ojo.** Quien los necesite tiene dos caminos y
  ninguno es estimar — la ventana de Design (`design_window.sh`), que existe
  justo para esto, o pedirle a Design que publique `X-01` como archivo aparte.

- **Conflicto de motion entre dos archivos de Design (2026-08-01).** Los dos se
  leyeron con `DesignSync` y **no coinciden**: la guía publica
  `animation: vbShim 1.1s linear infinite` para `X-01`, y la anotación de `5k`
  dice «sin pulso agresivo: **1,4 s** de fundido suave». Se implementó el valor
  del **dueño del componente compartido** —1,1 s— porque `5k` compone `X-01`,
  no lo define, y la regla de CLAUDE.md es que los componentes compartidos
  salen de la guía. **Queda para que Codex lo adjudique**, con el número en una
  sola constante publicada (`VbSkeleton.sweepPeriod`) para que cambiarlo sea
  una edición. Lo que sí cumplen los dos y se respetó: es un **barrido**, nunca
  un pulso.
- Página de Design: `Nóminas - Rediseño` en el proyecto `ERP Bikeshop UI
  Mockups` (`a0fa3196-6315-4b96-bde7-7cc801e7a74e`). Turnos usados: **t5**
  (carpeta `handoff-t5`, claro, 14 frames) y **turno 7** (carpeta
  `handoff-t9`, oscuro, 5 pantallas × 2 presets). El número de carpeta **no**
  coincide con el de turno.

## 2.d Pruebas vigentes y rutas de las capturas (2026-08-01)

Batería de Nóminas + componentes compartidos: **364/364**, 33 suites,
`{"type":"done","success":true}`, `EXIT_REAL=0`.

| Qué | Dónde |
|---|---|
| `X-01 VbSkeleton` | `test/widgets/vb_skeleton_contract_test.dart` · 8 |
| Silueta de carga y vacío (5k) | `test/widgets/payroll_loading_skeleton_test.dart` · 10 |
| OCR paso 1 | `test/widgets/payroll_ocr_step1_contract_test.dart` · 6 |
| OCR paso 2 | dentro de `test/widgets/payroll_reconciliation_responsive_test.dart` · 9 |

**Capturas, en el scratchpad de la sesión** (no en el repo):

- 5k, seis celdas **vivas**: `celda-{oscuro,claro}-{escritorio,tablet,movil}*.png`,
  con las de escritorio rehechas sin techo de filas.
- OCR paso 1, seis celdas **vivas**: `paso1-{oscuro,claro}-{1360,834,430}.png`
  más `paso1-{oscuro,claro}-430-scroll.png`, que demuestran alcance real de la
  tercera tarjeta sobre la barra fija.
- OCR paso 2, seis de **HARNESS**: `shots-final/paso2-{light,dark}-{1360,834,430}.png`.
  Se regeneran con `PAYROLL_SHOT_DIR=<ruta> flutter test
  test/widgets/payroll_reconciliation_responsive_test.dart`; **sin esa variable
  el generador se salta y la batería no escribe artefactos**.

**Las de harness tienen cajas en vez de letras**: en `flutter_test` no se cargan
las fuentes reales, así que demuestran **composición, no tipografía**, y no son
evidencia viva. Decidido no gastar una ronda en «hacerlas reales».

---

## 2.a La sesión de debug: una sola, y compartida

**Hay una sesión canónica viva al cerrar este handoff.** No arranques otra:
`native_session.sh start` se niega si detecta una, y dos sesiones sobre el
mismo puerto se pisan.

```bash
scripts/dev/native_session.sh status    # screen + pid + VM service
scripts/dev/native_session.sh doctor    # sólo si no responde
```

Los PID y el puerto son **estado dinámico, no contrato**: léelos siempre de
`status` y nunca los copies de este documento. Al cerrar esta ronda la sesión
viva era `screen payroll`, app **`62796`**, VM **`:60018`**, con el brillo en
`Oscuro` y la ventana en **1360×800**. Cualquier otro PID que aparezca en este
archivo es **histórico**, aunque su párrafo diga «hoy»: manda la tabla VIGENTE
del encabezado, que es la única reconsultada al cerrar.

**Y hay una segunda instancia del mismo bundle**, la **instalada**
(`~/Applications/Vinabike ERP.app`, vista como `81847`). Ni un filtro de
capturas ni un clic por coordenada las distinguen, y las dos corren contra
producción: comprueba `pgrep -fl vinabike_erp` y toca por identidad.

**Una sesión levantada antes de tu último cambio NO prueba tu código**, y una
captura es evidencia **del código que la produjo**: si tocas algo que altera lo
que la captura muestra, la captura caduca aunque «se vea igual». El hot reload
de este proyecto se cuelga seguido; `stop && start` cuesta ~1 min y nunca miente.
Tras reiniciar la app vuelve al Inicio: hay que volver a navegar antes de juzgar.

**Codex comparte esta misma sesión.** Los dos usan `app_control.sh` contra el
mismo VM service para `read` / `shot` / `tap`, y coordinan `reload`/`restart`
avisando antes: dos reloads simultáneos se matan entre sí (§1 del workflow).

---

## 2.b Chrome global tocado desde esta tarea

No son frames de Nóminas, pero se arreglaron desde acá y afectan a todo el ERP.
Van con su contrato para que nadie los deshaga sin darse cuenta:

| Qué | Estado | Contrato |
|---|---|---|
| **Barra de estado del teléfono** | Cerrado en código; **sin ver en dispositivo** | `system_status_bar_contract_test.dart` (6×2 + edge-to-edge Android-only + host sin `SafeArea`) y `system_status_bar_layout_test.dart` (header en `y=0` a 384; boundary a 1024) |
| **Tinta del drawer compacto** | Cerrado. De 1,03:1 a 15,26:1, medido | `compact_drawer_ink_contract_test.dart` — guard de código: exige que todo `ListTile` del drawer declare su tinta |
| **Guard del repo** | El hook **dejó de denegar** commit, push y publicación (31/07 y 01/08). Siguen denegados `git rebase`, `git restore` de alcance abierto, `supabase db\|migration`, `firebase deploy`, `supabase functions deploy` y `scripts/deploy.sh` | `claude_project_safety_contract_test.dart` |
| **Novedades de la actualización** | Ya no dependen de un solo proveedor | 78/78 en `scripts/releases/*.test.mjs` |

> **Capacidad mecánica ≠ autorización (2026-08-01).** Esa fila describe qué
> **deja pasar** el hook `.claude/hooks/guard-dangerous-bash.sh`, no qué **puede
> hacer** el agente. Son dos cosas distintas y confundirlas es exactamente lo
> que este párrafo existe para impedir.
>
> `CODEX_CLAUDE_COLLABORATION.md` §Safety sigue exigiendo **autorización
> explícita del dueño, por acción**, para commit, push, publicar la
> actualización, desplegar migraciones o funciones y CHECKPOINT B. **Manda el
> contrato, no el hook**: que una comprobación mecánica se afloje no concede un
> permiso, sólo deja de impedirlo. Y una autorización puntual no se convierte
> en permiso permanente — se pide otra vez la próxima.
>
> La lista vigente es **§1 de este archivo**, alineada con
> `PAYROLL_COMPLETION_PLAN.md` §13. Si esta tabla y §1 parecen contradecirse,
> gana §1: la tabla sólo documenta el estado del guard.

El dueño de la decisión de inset es **uno solo**:
`WorkspaceSystemInsetBoundary` en `workspace_shell_scope.dart` —compacto deja
pasar el inset al `AppBar`, ancho protege todo el shell—. Si una pantalla nueva
necesita `SafeArea` arriba, la respuesta casi siempre es que no: ya está
resuelto ahí.

---

## 3. Lo que aprendimos, y que te ahorra el día

### El método

- **Un frame no se acepta a ciegas.** `AGENT_VISUAL_WORKFLOW.md` §5.b tiene la
  compuerta de seis dimensiones, obligatoria por frame, y el formato de
  registro que separa **lo copiado / lo descartado / lo agregado**. Sin esa
  separación nadie distingue después una decisión de un descuido.
- **Cuando una batería se pone roja tras un cambio de texto, la mayoría de los
  rojos NO es el texto.** Esta sesión: de 31 rojos, 7 suites no compilaban por
  un parámetro nuevo en un servicio compartido, y **tres eran defectos reales**.
- **Una afirmación vale hasta donde llegó el comando que la respalda.** Dije
  «`grep height: 50` no devuelve nada» habiendo grepeado **un archivo**, y
  quedaban cuatro sitios. Antes dije que un `reload` había entrado porque no vi
  una fila en un `read | head -4` — estaba en la línea 5. Y di una batería por
  verde porque el runner reportó `exit 0`, que era el de `tail`. **Las tres son
  el mismo error**: confundir «no lo vi» con «no está». Para decidir si algo
  entró, pregúntale a lo que **agrega**, no a lo que quita; una presencia se ve
  en cualquier posición, una ausencia hay que demostrarla sobre la lista
  entera.
- **Si el resultado de una auditoría es un párrafo explicando por qué la
  excepción se queda, la excepción no está justificada: está siendo
  defendida.** Pasó con el CTA de 50 de 5l. `universal-ui-component-system.md`
  §2 no admite que una feature conserve un override visual propio, y que una
  ronda anterior hubiera cerrado ese frame no le gana al owner de densidad.
- **Un aserto laxo protege al defecto que dice vigilar.** `>= 48` deja pasar
  exactamente el 50 que se está persiguiendo. Cuando el valor lo publica un
  owner, el contrato compara **igualdad con el token**.
- **Antes de escribir una superficie, grepea si ya existe.** Van tres widgets
  de Design escritos y jamás montados. El comando está en el workflow §4.

### Las herramientas nuevas de esta sesión

```bash
native_session.sh doctor                    # POR QUÉ no responde la sesión
app_control.sh find|tap --key|--label X     # tocar por identidad
app_control.sh read [--filter X]            # la pantalla por semántica, con ESTADO
visual_compare.py decode|side|columns       # frame de Design ↔ app
```

- El **hot reload de este proyecto se cuelga seguido**, incluso recién
  levantado. `stop && start` cuesta ~1 min y nunca miente. No es error de
  operación: no lo escondas en el reporte.
- Un `screen -x` del dueño **no bloquea nada**. Confundirlo con la causa costó
  una ronda.

### Trampas de Design

- **El número de carpeta y el de turno no coinciden**: `handoff-t9` es el turno
  7. Descubre la carpeta con `list_files`, no la adivines.
- **Lee el `CHANGELOG.md` del turno antes de implementar.** Ahí está qué
  reemplaza a qué y las correcciones a turnos anteriores.
- **Ante una diferencia entre `spec.json` y el frame, gana el frame.** El spec
  de 5a declaraba 7 columnas y su frame dibujaba 8; Design lo confirmó y lo
  corrigió.
- El turno 6 reemplaza el **chrome** móvil, no la tarjeta de persona. Lo cerrado
  contra 5l-1 sigue válido.
- **Un frame puede llegar cortado sin avisar.** `get_file` corta en 256 KiB, que
  son **exactamente 196.608 bytes** de binario. Se reconoce por los dos
  síntomas juntos: ese tamaño clavado y un PNG que no decodifica. `5c` y `5h`
  cayeron ahí — **y ya no**: Design los republicó en bandas (§4.7).
  Procedimiento en `AGENT_VISUAL_WORKFLOW.md` §3.

### El error que más caro salió: causa correcta, arreglo incompleto

Dos veces seguidas identifiqué bien la causa y me detuve antes del final de la
cadena, y las dos veces el arreglo salió publicado **sin cambiar nada**:

- **Barra de estado.** Diagnostiqué que Android 15+ ignora `setStatusBarColor`
  —cierto— y no busqué quién más tocaba el inset. Había un `SafeArea` en el
  host que se lo comía antes de que el `AppBar` pudiera usarlo, así que
  edge-to-edge solo no cambiaba un píxel. Lo encontró Codex.
- **Tinta del drawer.** Medí 1,03:1 y até el color donde se pinta. Funciona,
  pero **la fuga de tema sigue sin explicar** (§4.8): tapé el síntoma.

> **La regla:** cuando encuentres la causa, pregúntate *quién más participa en
> esta cadena* antes de escribir el arreglo. Una explicación que encaja no es
> una explicación completa, y en móvil la diferencia sólo se ve en el
> dispositivo — donde no llegas desde acá.

---

## 4. Deuda abierta, con nombre

0. **Hay valores que no se pueden verificar en vivo sin escribir en
   producción, y hay que decirlo en vez de dejarlos en `n/r` a secas.** El caso
   concreto: la altura del CTA de la tarjeta de persona (5l) sólo se dibuja en
   una semana **ya confirmada**, y confirmar una es un write real. Se cubre por
   contrato (`payroll_redesign_surface_test.dart`, prueba `5l ·`) y **se declara
   como no verificado en vivo**. Antes de gastar una ronda intentando llegar a
   una superficie, comprueba si su precondición es una escritura.

0.b **`recordTitle` viene teñido con `onShell` y se pinta sobre `surface`.**
   `PayrollTokens.recordTitle` fija `color: onShell` —la tinta del cromo navy,
   casi blanca—, así que cualquier consumidor que lo use crudo sobre una
   superficie clara **escribe blanco sobre blanco**. En oscuro las dos tintas
   son pálidas y el defecto es invisible: **apareció recién al capturar la
   casilla clara** de 5g, donde el título de la hoja salía ilegible.
   Corregido **sólo en `payroll_method_sheet.dart`**, con el mismo recurso que
   ya usaba `payroll_advances_and_cash_surfaces.dart:1310` (`color: visual.ink`).
   **Quedan tres consumidores con la misma forma y sin verificar en claro** —
   `payroll_reconciliation_surface.dart:165`, `payroll_payment_composer.dart:241`
   y `payroll_payment_evidence_surface.dart:186`—: los tres hacen `copyWith`
   **sin tocar el color**. La corrección de fondo nace en el token (que no
   debería traer tinta de cromo por defecto), no en cada pantalla, y exige su
   propia ronda de seis casillas.

1. **`PayrollTokens.accent` está fijo** en `#1668BD`, el mismo valor que `info`.
   En claro el acento debería derivarse del preset. **Decisión de producto
   pendiente**: si se toma, hay que recapturar los frames claros del turno 5.
2. **Los nombres de borde están corridos un peldaño** respecto de la escalera
   del turno 8: `PayrollTokens.border` es en realidad el `divider`, y
   `borderStrong` es el `border`. **Renombrar por nombre sin mirar el valor
   sube todos los bordes un nivel y la tabla empieza a gritar.**
3. **Avatares en oscuro**: `avatarA` oscuro y el acento de Pacific son casi el
   mismo color, así que una persona parece un control. La corrección **nace en
   `VinabikeThemeResolver`**, no en Payroll —se intentó acá y el guard de
   inventario congelado lo rechazó con razón— y necesita auditoría de
   consumidores no-Payroll y regresión 2 presets × 2 modos.
4. **`Ver bitácora`** de 5i: capacidad nueva, no existe superficie de auditoría
   por semana. **Reverificado el 2026-08-01** (los modelos de auditoría existen,
   la superficie no) y **descartado** en 5i: no se maqueta un botón que no lleva
   a ninguna parte. Sigue disponible como capacidad si el dueño la pide.
5. **Selector de mes** de 5i: **descartado como control el 2026-08-01, con su
   razón**. `get_payroll_history_page_v1` pagina por **keyset sobre
   `period_end`** y no acepta un mes, así que un selector filtraría sólo lo ya
   cargado y afirmaría que antes no hay nada. Lo que se implementó en su lugar
   es **agrupación por mes en la lista**, que sí se deriva del dato. Si alguna
   vez se quiere el selector de verdad, lo que falta es un parámetro en el RPC,
   no un widget.
5.b **`Reabrir semana` de `7b`: descartado, y no es un pendiente.**
   `revert_payroll_to_draft` exige `status = 'confirmed'`, y el historial sólo
   entrega `paid`/`voided` por contrato del RPC: el botón fallaría en **todas**
   las filas que la pantalla puede mostrar. La otra vía,
   `revert_payroll_payment`, borra `expense_payments` y
   `employee_advance_allocations` —escritura de producción, y además la ruta
   auditada la rechaza con `payroll_reconciliation_requires_audited_reversal`—.
   Reabrir una semana pagada es **capacidad nueva** y una decisión del dueño,
   no un botón que faltaba.
6. **En compacto, el selector de persona de Anticipos corta la glosa sin
   elipsis** (`Rodrigo … · $36.000 aplica`). Es del `DropdownMenu`, no un
   overflow, y es anterior a esta ronda.
7. ~~`5c.png` y `5h.png` no se pueden bajar enteros~~ → **RESUELTO el
   2026-08-01, y no por nosotros.** Design ya los republicó en bandas y borró
   los archivos únicos: lo dice la sección «Republicado después del turno 5»
   del `CHANGELOG.md` de `handoff-t5`, y lo confirma la descarga real —
   `5c-p1.png` = **104.760 bytes, 1342×287, PNG válido con `IEND`**. Existen
   `5c-p1/p2`, `5h-p1/p2` y `5n-p3a/p3b`. **El prompt del plan §14.c punto 4 ya
   no hace falta.** Lo que hay que quedarse de esto no es el dato sino la
   causa: **un bloqueo heredado se reverifica en su fuente antes de repetirlo
   en un handoff.** El que depende de un tercero caduca solo, y nadie le
   comprueba la fecha de vencimiento.
23. ~~El selector de archivos del OCR no se puede conducir~~ → **RESUELTO el
    2026-08-01, en su owner (`scripts/dev/app_control.sh`).** Mi diagnóstico
    llegó a la mitad: sí, conviven **dos procesos `vinabike_erp`** —la copia
    instalada y la de debug—, pero el script **ya seleccionaba por `unix id`**.
    La causa real es más fina y vale escribirla: **guardar ese proceso en una
    variable hace que AppleScript serialice después la referencia por NOMBRE**,
    y con dos homónimos resolvía el instalado. Se sumaba una carrera: la
    ventana podía cerrarse mientras se enumeraban. El arreglo mantiene el
    predicado de PID **inline**, no usa `open -a` y tolera esa carrera.
    **Los pasos 2, 3 y 4 del OCR vuelven a ser alcanzables**: `choose-file`
    termina en `exit 0`, la app de debug avanzó a **Lectura** y leyó
    `page-01.png · 1 página · 14 movimientos`
    (`/tmp/payroll-ocr-picker-success.png`).
    **La lección, que es lo que se repite:** una referencia de proceso guardada
    en una variable no conserva la identidad con la que la buscaste. Si hay dos
    procesos del mismo bundle, el predicado va **inline** en cada uso.

23.b **Lo que SÍ se corrigió, porque era nuestro: un selector que no responde
    ya no deja la etapa muerta.** El estado ocupado se levantaba **antes** de
    esperar al selector, así que la pantalla decía `Validando el archivo…`
    mientras el operador todavía estaba eligiendo —falso— y, si el panel no
    devolvía nunca, la etapa se quedaba ahí para siempre con `Cancelar`
    deshabilitado por `_isBusy`. Ahora el selector se espera **fuera** del
    estado ocupado, un fallo del panel se nombra (`No pudimos abrir el selector
    de archivos`) y se puede reintentar. Verificado en vivo el 2026-08-01 con
    el panel real sin responder: la etapa quedó utilizable. Tres regresiones en
    `payroll_reconciliation_responsive_test.dart`; revertir el orden rompe dos.

24. **CORREGIDO EL 2026-08-01 EN LA REVISIÓN ULTRACODE. La causa raíz no es
    «un `Tooltip` por fila»: es *un `Tooltip` VISIBLE* cuando la tabla cambia
    de banda — y el defecto es ANTERIOR a `5c`.**

    Lo que escribí en la ronda de implementación estaba a medias y en un punto
    era falso: dije que crashea «con y sin puntero encima». **No.** Reproducido
    en un proceso limpio, recién arrancado y sin un solo hot reload
    (`65685`, y confirmado después en `84436`):

    - **Sin tooltip visible**, el ciclo `1360 → 834 → 430 → 1360` con el
      `Tooltip` montado en las cuatro filas **no falla**. Ni con foco de
      teclado, ni con el puntero sintético encima.
    - **Con el tooltip VISIBLE**, el mismo ciclo cae siempre, en la primera
      celda: `A _RenderLayoutBuilder was mutated in
      _RenderLayoutBuilder.performLayout`, por
      `_OverlayPortalElement.activate → _OverlayEntryLocation._activate →
      _RenderTheater._addDeferredChild → adoptChild → markNeedsLayout`. El
      `OverlayPortal` **se reactiva** durante el reparenting que dispara el
      `LayoutBuilder`, y muta un `_RenderLayoutBuilder` desde dentro del
      `performLayout` de otro. Con hot reload el mismo choque aparece como
      `overlay.dart:1258 · '!_skipMarkNeedsLayout'`; es la misma familia.
    - **Y no es «mi» tooltip.** El `IconButton(tooltip:)` del **caret** —que
      está en la cola desde mucho antes de `5c`— tumba el módulo exactamente
      igual: hover real sobre el caret, `1360 → 834`, y cae. Es decir, `5c` no
      introdujo el defecto: **lo encontró**, porque puso una celda con tooltip
      en todas las filas y eso lo hizo imposible de no ver.

    **Por qué costó tres intentos llegar acá, que es lo que hay que copiar:**
    `scripts/dev/app_control.sh` entrega los gestos **dentro** de la app por el
    servicio de depuración y **no mueve el cursor del dueño** — es su diseño, y
    está escrito en el propio script—. Un `scroll x y` sintético **no genera
    hover**, así que dos veces di por probado un experimento que nunca ocurrió.
    Para un hover de verdad hay que forzar el driver de eventos del sistema:
    `APP_CONTROL_BACKEND=os scripts/dev/app_control.sh scroll X Y 0`, y
    **comprobar en la captura que el tooltip apareció** antes de sacar
    conclusiones.

    **Corregido:** la cola **no monta un solo `Tooltip`** —ni en las cinco
    formas de decisión ni en el caret—, con contrato sobre toda la superficie y
    mutación probada en los dos sitios. El caret no pierde nada: su `Semantics`
    ya decía «Mostrar/Ocultar detalle de <persona>» palabra por palabra y el
    estado se ve en el glifo (▸ / ▾).

    **Y el motivo del bloqueo NO se quedó sólo en `Semantics.tooltip`**, que no
    le sirve a quien usa el mouse. Vive donde el propio `7a` lo pone —«la
    franja del pie manda a Asistencias»—: una nota en línea del dueño canónico
    **`E-04 · VbNotice`**, que no monta nada sobre el overlay. Se dice **una
    vez** cuando todas las filas comparten motivo, y cuando NO lo comparten la
    franja calla y cada fila abierta lleva el suyo, porque una sola franja no
    puede hablar por dos razones sin mentirle a una.

24.b **Una aserción de accesibilidad que no probaba nada.** Afirmar sólo
    `!isEnabled` sobre un nodo semántico pasa **con y sin** el `enabled: false`,
    porque un nodo que nunca declaró el estado también da falso. `aria-disabled`
    son **dos** hechos —`hasEnabledState` presente y `isEnabled` ausente— y hay
    que afirmar los dos; medido con la mutación, que antes no mordía. Del mismo
    lote: sin `container: true` la anotación del bloqueo **se funde en el nodo
    de la FILA**, que trae el botón del caret, y el lector anunciaba la fila
    entera como un botón deshabilitado cuando el caret se abre perfectamente.

8. **Fuga de tema en el drawer compacto, sin explicar.** El drawer está
   envuelto en `WorkspaceChromeTheme.sidebarTheme` y aun así sus `ListTile`
   heredaban la tinta del tema de la app (medido: `#10243A` sobre navy,
   1,03:1). En el entorno de test la misma composición resuelve bien, así que
   la fuga es de runtime y no está diagnosticada. Hoy se tapa atando la tinta
   en el sitio donde se pinta, con el guard
   `test/widgets/compact_drawer_ink_contract_test.dart`. **Quien la explique,
   que lo escriba acá**: mientras no se sepa, cualquier widget nuevo del drawer
   nace con el mismo riesgo.
9. **El buscador del drawer no pliega tildes**: `nomi` no encuentra `Nóminas`.
   La corrección nace en el filtro y vale para todo el ERP.
10. **La barra de estado quedó CERRADA en código pero sin confirmar en un
    teléfono.** Dos intentos míos fallaron por diagnóstico incompleto (ver §3);
    Codex cerró la causa restante y publicó. El contrato está en
    `system_status_bar_contract_test.dart` + `system_status_bar_layout_test.dart`
    (6 presets × 2 modos, y el boundary a 384/1024). **Lo que falta es mirarla
    en un dispositivo**: la compilación para el Simulador falla por el equipo,
    no por el proyecto (`iOS 26.5 is not installed`, se instala en Xcode ›
    Settings › Components), y no hay Android conectado a esta máquina. Codex
    tenía un emulador API 36 levantado con un harness visual en `build/`
    (ignorado por git) — **su captura no llegó a este chat**.
12. **La sonda de «ventana tapada» del workflow §1 da FALSOS POSITIVOS, y me
    hizo declarar pendiente algo que sí se podía ver.** La receta mide cuánto
    tarda `app_control.sh read --filter zzz`: si vuelve en menos de un segundo,
    concluye que el engine no dibuja. Pero `read` también vuelve rápido cuando
    **el filtro no encuentra nada**, que es justo lo que pasa con `zzz`. Con esa
    lectura escribí que la comparación visual quedaba pendiente; un `shot` de
    control mostró la app **perfectamente rasterizada**, en oscuro, con datos de
    producción. **La regla:** para saber si el engine dibuja, mira el frame
    (`shot`) o el aviso que el propio `read` imprime (`# el engine no entregó
    frame …`), nunca un cronómetro sobre un filtro que no matchea.
13. **RESUELTO el 2026-08-01 — se implementó el vacío que sí se puede sostener,
    y los otros dos siguen sin inventarse.** Hoy hay un vacío general honesto
    («Las semanas aparecen acá cuando Asistencias cierra sus horas», sin
    declarar por qué no hay ninguna) y «Aún no hay nadie contratado» con salida
    a Trabajadores. **Y «contratado» no es «activo»**: alguien `on_leave` sigue
    contratado aunque no pueda recibir un anticipo, así que el vacío de primera
    vez usa `status IN (active, on_leave)` y **no** reutiliza
    `_employeeCanReceiveAdvance`, que responde otra pregunta. El diagnóstico que
    lo justifica, tal como quedó tras la revisión de Codex:
    · *Todo pagado* con `open.isEmpty && vouchers.any(paid)` — **falso**: un
    comprobante histórico pagado no dice nada sobre el ciclo actual. Puede haber
    una semana en curso que todavía no existe como voucher.
    · *Semana sin horas cerradas* con `open.isEmpty` + trabajadores activos —
    **tampoco**: la ausencia de voucher abierto no prueba que Asistencias no
    haya cerrado nada.
    **Sin una señal canónica del período/ciclo actual, el vacío honesto es uno
    solo y genérico.** La distinción que sí se sostiene es *nadie contratado*, y
    **la garantía se comprobó en el esquema, no en los datos de hoy** (lectura
    de producción del 2026-08-01): `employees.status` es `NOT NULL`, con default
    `'active'` y `CHECK (status = ANY ('active','inactive','on_leave',
    'terminated'))`. Los dos vacíos que no se pueden derivar quedan vigilados
    **por ausencia** en la regresión, para que nadie los reintroduzca sin la
    señal que les falta.
14. **`PayrollTokens.queueStripH` (76) no describe la tira real.** Medido el
    2026-08-01 comparando la silueta contra la superficie cargada: con datos de
    producción la tira mide ~119 px, porque `_WeekCard` crece con la barra de
    avance y la nota al pie, que **dependen del dato**. Consecuencia concreta:
    la silueta de carga no puede reservar la tira en el píxel exacto y la tabla
    aterriza ~43 px más abajo de lo insinuado (la barra de dinero **no** se
    mueve: está anclada abajo). La corrección nace en **5a** —acotar la tira o
    publicar su alto real—, no en el esqueleto; el contrato de 5k acota la
    deriva a menos de una tira entera y lo declara.
15. **Un fantasma sin borde desaparece en oscuro.** La primera versión del
    control insinuado pintaba sólo `neutralSoft` y la captura en vivo a 834 en
    oscuro mostró la tira de semanas **vacía** donde debía haber tres pastillas.
    Corregido: usa `surfaceSunken` **con borde**, igual que los controles reales
    que insinúa, y hay contrato en 6 presets × 2 brillos. **Sólo se vio en la
    app viva y en oscuro**: ni el analyzer ni las pruebas de overflow lo tocan.
16. **Navegar en compacto no se puede hacer «por identidad» sin dos pasos
    previos** — receta nueva, en `AGENT_VISUAL_WORKFLOW.md` §3.b.
17. **En claro, los controles insinuados quedan muy tenues.** Visto en las tres
    celdas claras: las pastillas de la tira de semanas y el CTA fantasma apenas
    se despegan del lienzo, mientras que en oscuro se leen sin esfuerzo. La
    causa no es el esqueleto — usa `surfaceContainerLow` + `outlineVariant`,
    **el mismo par que los controles reales que insinúa**—, así que la decisión
    es de paleta y pertenece a **5a**, no a 5k. Se anota con su medida
    pendiente: nadie ha comprobado el contraste de ese par en claro.
14. **Nada sin confirmar en git.** El árbol quedó limpio en `74df6776` y las
    ~54 rutas que arrastraba el handoff anterior ya están dentro. El
    `dart format` de más sobre 15 archivos de `lib/shared` se revirtió.

18. **`employees.is_active` no existe** y `_employeeCanReceiveAdvance` la
    comprueba igual: `employee['is_active'] == false` es siempre `null`, así que
    esa rama es código muerto. No cambia el comportamiento —decide el `status`
    que sigue— pero **afirma una salvaguarda que no está**. Nace en Anticipos
    (5h); no se tocó para no abrir otra ronda antes de cerrar 5k.
19. **El vacío de 5k no se puede alcanzar en vivo sin escribir**, y por eso su
    verificación es de contrato. Producción tiene 7 trabajadores, todos
    `active`, y semanas abiertas: llegar al vacío exigiría terminar gente o
    borrar semanas. Es el mismo caso que §4.0 — antes de gastar una ronda
    intentando llegar a una superficie, comprueba si su precondición es una
    escritura.
20. **`_run` trata TODOS los errores como ambiguos, y algunos no lo son.** La
    valla (`_authoritativeReloadRequired` + «No pudimos verificar el
    movimiento») es correcta para un fallo de transporte: el servidor pudo haber
    cometido. Pero varios `StateError` son **precondiciones que el cliente
    comprueba antes de mandar el RPC** —`_loadVoucherReconciliationVersion` lee
    la fila y falla si no existe; `updateLine` lee el voucher y falla si ya está
    confirmado—: ahí **no hubo escritura**, el comando ni salió, y decir que no
    se pudo verificar un movimiento que nunca ocurrió es la misma clase de
    afirmación falsa que 5d corrigió. **No hay error tipado propio en Nóminas**
    (sólo `StateError` con texto y `PostgrestException`), así que la corrección
    **nace en `payroll_voucher_service.dart`**, que debe distinguir «rechazado
    sin escribir» de «ambiguo». **Ese archivo es de Codex** por la partición
    registrada y esto es un cambio de contrato, no de presentación: no se tocó.
    Adivinarlo desde la UI por tipo de excepción es justo lo que la revisión
    prohibió.

21bis. **CORRECCIÓN FECHADA (2026-08-01, tarde) — «no hay capacidad de rol» era
    demasiado amplio, y en 5g me habría hecho descartar un estado que SÍ se
    puede derivar.** Lo que no existe es un **rótulo de rol** que mostrar («Tu
    rol: Asistente»); lo que sí existe, y es canónico, es la **capacidad
    booleana**: `evaluateErpAuthorization(area:…)` en
    `lib/shared/widgets/erp_authorization_gate.dart` resuelve
    `resolving | unavailable | denied | allowed` desde el perfil, con
    `ErpAuthorizationArea.hrManagement => profile.canManageUsers` y
    `ErpAuthorizationArea.payroll => profile.canAccessAccounting`.
    Y **la separación es real en la base**, verificada en producción:
    `can_manage_tenant_hr(t) = tenant match AND can_manage_tenant_users(t)`
    (migración `20260728010000`), la política `employees_update_managers`
    exige `can_manage_tenant_hr` en `USING` **y** en `WITH CHECK`, mientras que
    `employees_read_authorized` admite además `can_manage_tenant_payroll`.
    **Traducción al negocio: un contador puede operar Nóminas y leer la ficha,
    pero no editarla; un admin/manager sí.** Ése es exactamente el estado de
    sólo lectura que dibuja 5g, y no es capacidad nueva.
    La regla que queda: **antes de declarar «no derivable», busca la capacidad,
    no el rótulo.** Son cosas distintas y confundirlas descarta trabajo posible.

21. **El estado de permiso de 5k NO está implementado y NO es derivable.**
    Queda dicho sin ambigüedad porque un resumen anterior lo dio por cerrado con
    `blockedReason`, y **eso era falso**. `PayrollWeekTotalsVM.blockedReason`
    existe y se conserva, pero **sólo para sus bloqueos reales**: versión del
    backend ausente, explicación del borrador, saldo y estado. **No es RBAC y no
    cierra este estado.** El frame dibuja «Tu rol: Asistente» y esta superficie
    **no tiene owner ni capacidad de rol**: no hay de dónde leerlo, así que es
    capacidad nueva, no migración visual. `reviewPermissions` pertenece al owner
    separado de **5j** y no se toma prestado. **No se inventan roles.**

22. **`wasReplay` está MUERTO: la UI tiene un mensaje de reintento que nunca
    puede aparecer.** El cliente lo calcula
    `wasReplay: response['replayed'] == true || response['was_replay'] == true`
    (`payroll_reconciliation_service.dart`), y
    `apply_payroll_statement_reconciliation` **no emite ninguna de las dos
    claves** — verificado dos veces el 2026-08-01: sobre la migración
    `20260728213000`, y sobre **producción** con
    `pg_get_functiondef` (`says_replayed = f`, `says_was_replay = f`, también
    para `create_payroll_statement_import`). Consecuencia concreta: la
    idempotencia **sí es real** —un reintento devuelve el recibo guardado con
    `return import_row.apply_receipt;` y no escribe nada—, pero la app **no
    puede distinguirlo** y anuncia «N semanas confirmadas y conciliación
    registrada» igual que la primera vez; el mensaje «Esta conciliación ya
    estaba registrada. No se duplicó nada.» es inalcanzable.
    **Por qué nadie lo vio:** los dos arneses que lo prueban construyen el
    recibo con `wasReplay: replay` **a mano**, saltándose el parseo del JSON, o
    sea prueban una forma que el servidor no produce. Es el mismo defecto de
    familia que «un arnés sin tema no prueba la app» (§5.c del workflow), en
    versión recibo.
    **La corrección nace en la migración**, no en la UI: el RPC debe declarar
    `replayed`. Desplegar migraciones exige autorización del dueño y esta tarea
    prohíbe escrituras de producción, así que **no se tocó**. Queda vigilado por
    caracterización en `payroll_ocr_step4_contract_test.dart` («DEFECTO
    VIGENTE»): **si esa prueba se pone roja es buena noticia** —el backend
    empezó a declarar el replay— y entonces se borra y se escribe la que
    verifica el mensaje de verdad.

23. **El encabezado del paso 4 no puede afirmar «nada se escribió» siempre.**
    `_apply()` llama `createImport` **antes** que `apply`, y ese RPC inserta en
    `payroll_statement_imports` y `payroll_statement_rows`. Si el apply falla
    —una sola transacción, así que no hay pagos a medias— la cartola **sí**
    quedó registrada. El frame rotula la frase de forma incondicional; la app
    ahora dice «La cartola ya quedó registrada por el intento anterior. Ningún
    pago se ha creado todavía.» Con regresión propia.

24. **RESUELTO el 2026-08-01 — los dos generadores de capturas terminan en
    verde.** Venían saliendo en rojo, y el del **paso 2** ya lo hacía desde
    antes de esta ronda (32 excepciones, `exit 1`, seis PNG válidos). **Una
    versión anterior de esta entrada llegó a proponer que eso era aceptable
    mientras el artefacto estuviera bien. Era una mala regla y quedó derogada:**
    mientras el comando salga distinto de cero, nadie puede distinguir «falló la
    descarga de una fuente» de «la captura salió en blanco» o «la pantalla
    desbordó», que es justo lo que estas imágenes existen para delatar.
    **Causa real, corregida también en la redacción:** `GoogleFonts.textStyle`
    lanza la carga como future *fire-and-forget* con `.then` **sin `onError`**;
    en `flutter_test` la petición vuelve 400 y ese future rechaza hacia la zona.
    Y **no falla una sola vez**: el `catch` de `loadFontIfNecessary` hace
    `_loadedFonts.remove(...)` antes del `rethrow` (`google_fonts 6.3.2`), o sea
    **borra la marca y reintenta en cada resolución de estilo** — decir que
    «cachea el fallo y se calla», como decía esta entrada, era exactamente al
    revés. Sólo estalla al capturar porque el rechazo necesita el event loop
    real, y `runAsync` (que el encoder sí necesita) es el único sitio donde lo
    tiene.
    **Arreglo:** en los dos generadores se sustituye el cliente HTTP del paquete
    por uno cuyo `send` devuelve un `Completer` que **nunca completa**, así las
    cargas quedan *pendientes* en vez de rechazar; se restaura el cliente y se
    limpia la caché en `addTearDown`. **Sin `takeException`, sin filtrar
    excepciones y sin apagar `allowRuntimeFetching`** —lo primero taparía un
    overflow ajeno, lo último lanza en cada frame—. Capturar fuera de `runAsync`
    tampoco sirve: `toByteData` se cuelga esperando el event loop (medido).
    Prueba de que no cambió nada visual: las seis capturas del paso 4 salen
    **byte a byte idénticas** a las de antes del cambio.
    Sigue en pie el límite visual, dicho por lo que se ve: en estas capturas
    **el texto sale como bloques** —los glifos de la tipografía de prueba del
    arnés—, así que no se lee una sola palabra en ellas. Demuestran
    **composición** (qué hay, dónde, de qué tamaño, de qué color) y **no son
    evidencia de tipografía**: cuál familia se dibuja no se midió y no se
    afirma.

---

## 7. Lo que sigue

**Cerrados con las seis casillas vivas contra producción:** `5i` Historial,
`5a` cola, `5b` sidebar 1116, `5c` gramática de decisión, `5h` Anticipos,
`5m` tablet 834, y `5j-p3` (oscuro el 01/08, claro en la undécima sesión).
**Lo siguiente es `5n` matriz de cierre**, sin empezar. Siguen abiertos con
causa escrita: `5e`/`5f` (RT bloqueado por escritura, §2), `5l` (falta el marco
del turno 6) y `5k` en su parte de permisos (§4.21). El registro completo de
cada compuerta —qué se copió, qué se descartó y por qué, con la medición que lo
sostiene— está en el **ledger del plan §15**. Acá queda sólo lo que le sirve al
que viene.

### Lo que `5c` deja resuelto para el resto

- **La gramática de decisión es un contrato, y ya está escrito en
  `canonical-ui-surfaces.md`.** Cinco formas; una fila nueva —vacaciones,
  licencia, finiquito— cae en una de ellas o se declara una sexta en Design
  **antes** de dibujarla. La quinta, el bloqueo, es **texto pasivo**: si vuelve
  a aparecer una píldora ahí, el defecto es que la pantalla promete una acción
  que no existe.
- **Ningún control de esa columna puede montar un `Tooltip`.** Es un
  `OverlayPortal` dentro del `LayoutBuilder` de la tabla y tumba el módulo al
  cambiar el ancho de la ventana (§4.24). El motivo va en `Semantics.tooltip`.
- **Un `reload` que no confirma deja capturando código viejo.** Si
  `native_session.sh reload` no imprime `Reloaded N libraries`, la captura
  siguiente no prueba nada — costó dos rondas creerle a un frame obsoleto.

### El descubrimiento de método que cambia el resto del turno 7

**La sección `t7` del canvas cae ANTES del corte de 256 KiB.** El handoff decía
—correctamente para el turno 5— que «ningún frame `5*` es legible desde el
canvas»; de ahí se venía arrastrando el supuesto de que *nada* lo era. Falso
para el turno 7: `7a`, `7b`, `7c`, `7d`, `7f` y `7g` están **completos y
literales** en `Nóminas - Rediseño.dc.html`, con sus `font:`, `background:`,
`border:`, `padding:` y `grid-template-columns` exactos.

```bash
# el resultado grande queda en disco; sólo entra un preview de 2 KB al contexto
python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['content'])" \
  "<resultado-designsync>.txt" > canvas.html
grep -n 'class="dv-oid" href="#' canvas.html    # los anclajes de cada frame
```

Consecuencia práctica: **5e, 5f y 5j-p3 en oscuro no hay que estimarlos**, sus
frames del turno 7 (`7d-composer-*`, `7d-efectivo-*`, `7c-ocr-*`) son legibles
igual que lo fue 7b. Eso es lo que hace baratas las filas que siguen en §2.

### Lo que 5i deja resuelto para otros frames

- **`S-06` deja de ser un bloqueo de Historial.** No se migró ni se forzó: se
  **eliminó la necesidad**. En compacto la lista *es* el control (lista →
  detalle → volver), que es lo que pide la guía móvil. `S-06` sigue abierto como
  componente compartido para quien lo necesite de verdad.
- **`Reabrir semana` está cerrado como decisión, no como pendiente.** La razón
  es de backend y está medida: `revert_payroll_to_draft` exige
  `status = 'confirmed'` y el historial sólo entrega `paid`/`voided`. No lo
  vuelvas a abrir sin una capacidad nueva.
- **El nombre de quien cerró la semana ya llega a la UI.** `paid_by.name` venía
  resuelto por el servidor y **la conversión a `PayrollVoucher` lo botaba**
  (guardaba sólo el id). Hoy viaja por `PayrollRedesignData.historyActorNames`.
  Si otra superficie necesita un actor con nombre, ése es el camino.

### 5j-p3 · el wording ya está adjudicado

**Los cuatro pasos son `Cargar cartola · Lectura · Propuestas · Aplicar`**
(decisión de Codex, 2026-08-01, aplicada en código, copy y pruebas). Deroga el
wording del 2026-07-30. Las razones, para que nadie las vuelva a discutir:
**`Cargar`** y no «subir», porque el archivo se procesa **en el equipo** y no
viaja a ningún servidor —«subir» describe algo que no pasa—; **`Lectura`**
porque el paso 2 muestra lo que el OCR leyó, no una acción del operador; y
**`Propuestas`** porque el paso 3 son propuestas de pago que se aceptan o se
cambian, más preciso que el «revisar» genérico que este ERP usa en otros seis
módulos. El CTA que lleva del paso 2 al 3 dice `Ver propuestas de pago`.

### 5j-p3 · lo que falta después del renombre

`7c` ya está **leído literal** del canvas (turno 7, antes del corte). Su tabla
es `Propuestas de pago` con siete pistas
—`26px 76px minmax(190px,1fr) 118px minmax(200px,1.1fr) 148px 84px`, gap 10—,
rótulos `FECHA · DESCRIPCIÓN EN LA CARTOLA · MONTO · PERSONA Y RAZÓN ·
CONFIANZA`, píldoras `CALZA` / `REVISA` / `NO SÉ QUIÉN ES` sin porcentaje, fila
marcada en `selectionRow` y acción `Cambiar` al final.

Falta **la tabla**: llevar `Propuestas de pago` a las siete pistas de `7c` con
sus píldoras `CALZA` / `REVISA` / `NO SÉ QUIÉN ES` y la acción `Cambiar`, y
después la matriz de seis casillas del paso 3, que hoy está en `claro sí ·
oscuro no`. El recorrido en vivo necesita la cartola real: cargar el archivo es
**local** y no escribe (§4.c), y el primer write está dentro de `_apply()`.

### Lo siguiente, en orden de rendimiento

*(Lista reescrita el 2026-08-01, undécima sesión: los tres puntos anteriores
—5e/5f, 5m, 5b y 5c— quedaron cerrados o con su bloqueo medido. El orden viejo
se guardaba «por si acaso» y lo único que hacía era mandar a rehacer trabajo
hecho.)*

1. **`5n` · matriz de cierre** (`5n-p1/p2/p3a/p3b/p4`), sin empezar. Es el
   frame que audita a los demás, así que se hace **último a propósito**.
2. **`5l` · tarjeta móvil**: la composición está cerrada contra `5l-1`; falta
   confirmar que el **marco** sea el del turno 6, que es lo único que el turno 6
   reemplaza (lo dice su propia corrección en `handoff-t9/spec.json`).
3. **5e y 5f en oscuro** (`7d-composer-*`, `7d-efectivo-*`): implementados y con
   contratos, pero **el RT sigue bloqueado por escritura** — llegar a
   `confirmed`/`partial` exige `commitWeek`. No se sustituye con arnés: ya se
   intentó y las capturas salieron con glifos de la fuente de prueba. Ojo con el
   modelo de caja: los `width` del HTML son de **contenido**; los anchos reales
   son **560 y 480**.

### Trampas de esta ronda, para que no cuesten dos veces

- **Un `StatelessWidget` que pasa a `StatefulWidget` sobrevive al hot reload
  pero reinicia el estado de la página que lo contiene.** El reload entró
  (`Reloaded 38 of 5156`) y aun así la app volvió al scope `Semanas`: hay que
  **volver a navegar por identidad** antes de juzgar la pantalla. En Historial
  no cuesta nada porque es de sólo lectura; en el OCR habría costado el borrador
  entero.
- **Un ancho leído de Design no es el ancho que tendrás.** 7b se dibujó sobre un
  canvas de 1340 y el workspace de una ventana de 1360 es más angosto porque el
  rail y el cromo se lo comen. El escalón de columnas **se deriva sumando las
  pistas leídas** (`methodColumnMinWidth`), nunca tanteando en pantalla.
- **Una glosa que cabía en el frame no cabe con datos reales.**
  `Cubierto con anticipo · 27/06` salía elidido en la pista de 160. El frame usa
  `Transferencia · 07/07`, que es más corto que cualquier caso real del negocio.
  Míralo en la app viva antes de dar por buena una columna de ancho fijo.

---

## 4.d Estado del OCR tras la corrección del shell (2026-08-01)

### La causa del defecto grande, probada — y NO era `MainLayout`

Mi primera hipótesis (el shell reubicando el contenido al cruzar 900) **quedó
descartada con un arnés**: `MainLayout` conserva el estado al cruzar incluso sin
fijar el workspace y montando por `child:`, como hace el router real.

La causa está en **`_buildDeferredPageWithNoTransition`** (`app_router.dart`):
envolvía cada página en `FutureBuilder(future: erp.loadLibrary())`, y
`loadLibrary()` devuelve un **`Future` nuevo en cada llamada** aunque la
biblioteca ya esté cargada. Cada reconstrucción devolvía el builder a
`waiting`, que dibuja un esqueleto de **otro tipo** que el árbol real, y Flutter
destruía el subárbol con su `State`. Alcanzaba a **toda ruta diferida con estado
en memoria**.

Corrección: `static final Future<dynamic> _erpLibraryOnce` memoizado, parámetro
`libraryFuture` eliminado y **130** argumentos retirados. **Probado por
intervención en vivo**: antes moría al primer cruce, después el borrador
sobrevive 1360 → 834 → 430.

### ⚠️ El límite de esa corrección: un hot reload SÍ borra el borrador

Medido el mismo día: antes de `r`, `Revisar 10/10` y `Aplicar 1/4 efectivo`;
después, `Sube la cartola`. **El cruce de breakpoint está resuelto; el reload
no.** Consecuencia práctica para quien verifique en vivo: **termina la evidencia
antes de recargar**, porque recargar cuesta rehacer el recorrido completo.

### Lo que quedó cubierto, y con qué mutación

| Corrección | Regresión | Mutación |
|---|---|---|
| `Future` memoizado del router | `deferred_route_state_contract_test.dart` | revertir el router → **2 fallos** |
| La pregunta respondida se suelta al avanzar | 4 pruebas en `payroll_reconciliation_responsive_test.dart` | «nunca soltar» → **2**; «soltar hacia atrás» → **1** |
| Stepper en el breakpoint canónico | pasos `Subir/Extraer/Revisar/Aplicar` a 834, rama ancha a 900 | volver a 600 → **1** |
| CTA y acciones legibles en compacto | `didExceedMaxLines` sobre el primario del paso 4, a **834 y 430** | una línea → **2**; sin apilado en teléfono → **1** |

### Huecos que siguen abiertos, dichos con su medición

1. **La limpieza de `_stagedQuestionRowId` y el `index + delta`** no tienen
   regresión que muerda: sólo difieren con una fila «en revisión», y los
   fixtures de ese archivo no exponen la acción que la pone. Se intentó, se
   mutó (0 fallos) y se borró el test que no mordía.
2. **Textos explicativos largos elididos** a 834 y 430 —«Cruce por persona +
   fecha…», el mensaje de «no queda nada por decidir», «Calces sugeridos»— y
   los pills a 430 en la rama compacta. Piden **envolver**, no caber; es
   decisión de producto.
3. **El borrador no sobrevive al hot reload** (arriba).

### Trampa del selector de archivos, y por qué importa

El picker es un `NSOpenPanel`: fuera del árbol semántico del VM service, así que
`tap` no lo alcanza. Conducirlo con AppleScript a ciegas mandó los `⌘⇧G` **al
Find de Claude**. Y puede haber **dos instancias del mismo bundle** —la debug y
la **instalada**, vistas juntas como PID `62796` y `81847`—: ni el filtro de
capturas ni un clic por coordenada las distinguen, así que **un clic puede caer
en la instancia que corre contra producción**. Comprueba `pgrep -fl vinabike_erp`
antes de conducir cualquier diálogo nativo. El owner es
`scripts/dev/app_control.sh choose-file`.

---

## 4.c OCR de Nóminas: la contradicción resuelta, y un defecto grande encontrado

### El mapa de escrituras, leído del código y no del texto

El encabezado decía que el paso 4 era «lo siguiente» mientras la matriz lo
declaraba «funcionalmente cerrado» sólo con harness. **Lo resuelve el código:**
`PayrollReconciliationService` tiene **un solo embudo de RPC** y tres puntos de
escritura, y su propio doc lo declara — *«Preparing a draft performs no database
writes»*.

| RPC | Se dispara desde | Paso |
|---|---|---|
| `create_payroll_statement_import` | dentro de `_apply()` | **4** |
| `apply_payroll_statement_reconciliation` | dentro de `_apply()`, a continuación | **4** |
| `learn_payroll_beneficiary_alias` | opcional, si el operador marca «aprender alias» | 3 |

`createImport` **no** ocurre al cargar el archivo: ocurre dentro de `_apply()`,
inmediatamente antes de aplicar. **Por lo tanto los pasos 1, 2, 3 y la pantalla
del 4 son alcanzables en vivo contra producción con cero escrituras**, y lo
único prohibido es pulsar `Aplicar`.

**Mi error de método en las rondas anteriores fue confundir «subir un archivo»
con «escribir en producción».** `prepare()` parsea y hace OCR **en el cliente**.
Por esa confusión dos pasos quedaron con evidencia de harness sin necesidad.

### Ejecución real, no placeholders

Fixture: **cartola real del negocio ya presente en el repo**, en `tmp/pdfs/`
(fuera de git, dato del dueño). Se carga por el panel nativo — el picker es
inyectable pero en vivo abre `NSOpenPanel`, así que se maneja con System Events
(⌘⇧G + pegar la ruta desde el portapapeles; teclear la ruta carácter a carácter
falla por timing).

Con eso, contra producción y sin una sola escritura:

- **Paso 2**: `page-01.png · 1 página · 14 movimientos`, con la política de
  cuatro filas visibles y su pie real — *«… 6 egresos más con todos sus campos
  reconocidos y sin avisos.»*, que hasta ahora sólo tenía prueba de harness.
- **Paso 3**: cruce real. `Lucas Pacheco` calzado a la Semana 30 con monto
  exacto y el aviso honesto *«Fecha posterior al cierre declarado»*; otro
  trabajador con **diferencia de +$250** dentro de tolerancia, con la copy de
  dominio *«Se transfirió $250 de más»*, *«No se ajustan horas ni tarifas para
  hacerla desaparecer»* y *«Una diferencia bancaria no crea un anticipo»*.
- **El `S-05` migrado funcionando en su flujo real**: la cuenta ERP se elige
  desde el popover anclado, con la única opción que el tenant tiene.

### El paso 4 está detrás de una compuerta de dominio, no de una escritura

`Ir a aplicar` permanece deshabilitado y **dice por qué**. La cadena, leída de
`_blockers`: backend versionado ausente · sin método de transferencia con cuenta
contable · falta elegir la cuenta ERP · movimientos sin disposición · diferencias
de monto sin decidir · confirmaciones sin razón de auditoría · métodos de
transferencia incompatibles. **Es comportamiento correcto**, y alcanzarlo exige
trabajo de operador, no un permiso.

En esta ronda se llegó hasta **10/10 decisiones y `Sin decidir $0`**, y quedaron
pendientes las razones de auditoría. **No se pulsó `Aplicar` en ningún momento.**

### ⚠️ DEFECTO GRANDE: cruzar los 900 px destruye el borrador entero

**Reproducido dos veces, mismo PID `62796` y cero reinicios en el log:**

| Ancho | Lo que dice la app |
|---|---|
| 1360 | `Extraer. 14 movimientos` · `14 movimientos detectados` |
| 834 | `Sube la cartola` · `Carga y lee una cartola para comenzar la revisión` |

Se pierden **la extracción OCR y las 20+ decisiones del operador**. En una tablet
eso es *rotar el dispositivo*, y en escritorio, arrastrar el borde de la ventana.
`GUI_MOBILE_DESIGN_PRINCIPLES` lo prohíbe con esas palabras: *«an open mutable
child stays mounted when constraints cross a breakpoint»*.

**Alcance: es del shell, no de Nóminas.** `MainLayout.build` devuelve dos árboles
distintos según `showSidebar` (`ResponsiveViewport.desktopMin`), así que afecta a
**toda ruta con estado en memoria**.

**La causa NO está probada, y no se inventa.** La hipótesis obvia —que el
contenido ruteado cambie de posición y Flutter no pueda emparejar los `Element`—
**no alcanza**, porque el shell ya hace lo correcto: `_routedContentKey` es un
`GlobalKey` sobre un `KeyedSubtree` y **ambas ramas montan la misma instancia**
(`main_layout.dart:1602` en escritorio, `:1778` en compacto). El
`_PayrollReconciliationPageState` tampoco tiene `initState`,
`didChangeDependencies` ni `dispose` que descarten el borrador. Queda **acotado a
que algo por encima de `MainLayout` recrea su `State`** —y con él una
`_routedContentKey` nueva—, probablemente el host de workspace; **hay que
probarlo antes de corregir**.

**Es el próximo trabajo, y es grande**: sin esto, ninguna de las seis casillas del
OCR se puede capturar cambiando el ancho, porque el borrador no sobrevive al
cambio. Las capturas compactas de esta ronda muestran **el paso 1**, que es lo
que la app realmente dibuja tras el resize — no el paso 3.

Capturas: `<scratchpad>/shots-ocr-vertical/`.

## 4.b-bis Segunda revisión de Codex (2026-08-01, novena sesión)

La entrega anterior **tampoco quedó aceptada**, y los cuatro hallazgos eran
reales. Se corrigieron todos; queda uno declarado como no alcanzable.

| # | Hallazgo | Estado |
|---|---|---|
| 1 | El umbral táctil estaba en **600**, no en 900: la tablet abría popover | **CORREGIDO** · con regresiones en 834, 899 y 900 |
| 2 | El objetivo táctil seguía en **34** bajo 900 px | **CORREGIDO** · 48 de objetivo, 34 de caja |
| 3 | `order('id')` + `range` **afirmaba una exactitud imposible** | **CORREGIDO** · una lectura acotada, o `unavailable` |
| 4 | `999` señalado como valor sin fuente | **Sí tiene fuente**, citada abajo; y se quitó el único valor que de verdad no la tenía |
| 5 | Estados vivos que faltaban | Editor de fichas **CERRADO**; método `Cheque` **no alcanzable sin escribir**, medido |

### 1 y 2 · el umbral y el objetivo salen del mismo sitio, y no es una preferencia

**`F-06`, textual del archivo:** *«Bajo 900 px de ancho lógico la densidad se
fuerza a touch: 48 px de target sin importar la preferencia. Nada de detectar el
zoom del navegador.»* O sea Design fija **las dos cosas a la vez** y en el mismo
número, que además es el `ResponsiveBreakpoints.desktopMin` del repositorio.
Haber usado `phoneMaxExclusive` (600) fue leer el contrato del teléfono para
decidir algo que es del host táctil completo.

El patrón del objetivo también está dibujado, en tres sitios: el campo de
búsqueda dice `Alto 34 (48 touch)`, la casilla dice *«toda la fila es el hit
target (34, 48 en touch)»*, y hay un recuadro rotulado **«TOUCH — 48 con área
invisible»**. Así que **la caja de 34 no se toca: crece el área alrededor**, y el
`InkWell` —que es a la vez ancla del popover y nodo semántico— es el que mide 48.

Verificado en la app viva, no sólo en harness: a **834** el campo anuncia
`206x48` y la fila del menú `834x48`; a **1360**, `206x34` y opciones de `194x30`.

### 3 · la afirmación falsa, y por qué era falsa

El comentario del comando y `canonical-ui-surfaces.md` decían que ordenar por
`id` y paginar con `range` impedía saltos y duplicados. **No lo impide.** Un
`INSERT` o un `DELETE` entre dos páginas corre la frontera igual de todos modos,
y `payroll_voucher_lines.id` es un **UUID aleatorio**, así que ni siquiera ordena
por antigüedad. Desde el cliente no hay lectura multipágina consistente sin una
consulta atómica del servidor, y **no existe una**.

Sustituido por lo único que no puede mentir: **una lectura acotada y un solo
`count(exact)`**. El desborde lo decide el `count` que devuelve la propia
consulta —no cuántas filas llegaron—, porque el `max-rows` de PostgREST podría
recortar antes del techo y hacer parecer completa una lectura truncada. Por
encima del techo el desenlace es `unavailable`. **Techo 150**, con dos razones
medidas: 150 UUID en el `in` son ~5,5 KB de URL, y el trabajador con más líneas
en producción tiene **30**.

Los tres documentos que prometían exactitud concurrente quedaron corregidos.

### 4 · el `999` sí estaba en el archivo; lo que no estaba era otra cosa

La escalera de radios de la guía es **`4 · 6 · 8 · 10 · 14 · 999`**, con el
último rotulado **`pill`**, y el handle del bottom sheet lo escribe entero:
`width:34px;height:4px;border-radius:999px` (línea 1119 del archivo). Es un token
publicado, no un número plausible.

**Lo que sí no tenía fuente y se quitó:** el estado `read-only`, que dibujaba un
`border-bottom:1px dashed` cuyo **ritmo de punteado no es legible** —en CSS lo
resuelve el motor de render, así que no hay número que citar— y que yo había
inventado en 3/2. Se registra como *unreadable* y el estado queda **publicado y
no implementado**, sin consumidor. Se quitaron además siete `height:` de
interlínea que yo había fijado en 1.2 donde la guía **no publica ratio**: el
atajo CSS sin `line-height` significa las métricas propias de la fuente.

### 5 · un estado vivo cerrado y otro medido como inalcanzable

**Editor de fichas: CERRADO.** El menú se abrió en vivo y ofrece exactamente
`Sin especificar · Cuenta Corriente · Cuenta Vista · Cuenta de Ahorro` — sin
`Cuenta Ahorro` (la etiqueta inválida que tenía antes) y sin `Cuenta RUT`. La
traba anterior era de herramienta, no de la app: **`scroll` no movía ese panel y
`drag` sí** (receta en `AGENT_VISUAL_WORKFLOW.md` §3.b).

**Método `Cheque`: NO alcanzable sin escribir, y está medido.** En producción el
único trabajador cuyo FK apunta a `Cheque` es **`Fernando Tapia`** —que no es el
`Fernando José Tapia Carrillo` de la lista: son dos fichas distintas— y tiene
**0 líneas en 0 semanas**. La hoja se abre desde la fila de una persona en una
semana, así que llegar a su estado exigiría crearle una línea, o sea una
escritura de producción. **Se cubre por contrato**, con dos pruebas que exigen:
ninguna opción preseleccionada, el aviso presente nombrando `Cheque`, y `Guardar
método` deshabilitado; más una que comprueba que al elegir uno válido el aviso se
va y el botón se habilita.

---

## 4.b Revisión de Codex sobre 5g — estado al cerrar la octava sesión

| # | Qué pedía | Estado |
|---|---|---|
| 25 | Owner `VbShortSelect` (S-05) y migrar los tres consumidores | **HECHO en 2 de 3.** El tercero es **S-06**, no S-05 — medido, ver abajo |
| 26 | RPC atómico para la autoridad del método | **SIGUE BLOQUEADO por contrato.** No se tocó y no se finge cerrado |
| 27 | Clasificar sólo constraint/FK como rechazo | **HECHO** · `classifyStoreFailure` |
| 28 | `known(0)`/`known(n)`/`unavailable` + orden estable | **HECHO** · `PayrollRecordedPaymentCount` y `.order('id')` |
| 29 | Quitar el default destructivo de `touchesBankAccount` | **HECHO** · argumento `required`, sin default |
| 30 | La lección `text + CHECK` en `AGENT_DATABASE_CONTRACT.md` | **HECHO** · sección propia con el costo real |
| 31 | Visuales de 5g: claro, tablet, móvil, editor de fichas | **HECHO en las seis casillas**; el editor quedó **parcial**, ver abajo |

### 25 · dónde el punto tenía razón, y dónde la guía manda otra cosa

**Tenía razón en el fondo:** un control compartido va bajo su id, y «registrar
la divergencia» no deroga `AGENTS.md` ni `universal-ui-component-system.md`. El
owner existe: **`lib/shared/widgets/vb_short_select.dart`**, con popover anclado
en escritorio y **bottom sheet `O-05` en compacto**, todos sus valores leídos con
`DesignSync` del bloque `S-05` de la guía, y 22 pruebas propias.

**Pero «los tres consumidores» eran dos.** El propio `S-05` pone el techo —*«Hasta
~7 opciones, conjunto estable y conocido… El menú no es scrollable: si necesita
scroll, era el otro componente»*— y los tres se miden así, contra producción
(2026-08-01, lecturas de sólo lectura):

| Consumidor | Opciones reales | Veredicto |
|---|---|---|
| `payroll_method_sheet.dart` · TIPO | 3 del `CHECK` + «Sin especificar» = **4** | **S-05** · migrado |
| `payroll_reconciliation_page.dart:3628` · cuenta ERP | **1 por tenant**, máximo entre todos los tenants | **S-05** · migrado |
| `payroll_history_surface.dart:405` · semana histórica | **30 semanas** en el tenant vivo, **paginado** (`hasMore`), etiquetas de tres datos | **S-06** · NO migrado |

Forzar la tercera en S-05 daría un popover de 30 filas recortado sin aviso, y el
bottom sheet tampoco la salva (30 × 48 = 1.440 px contra el tope de 60 % que fija
O-05: *«con más, es una página»*). **`S-06 · VbSearchableSelect` no existe en este
repositorio y queda como pendiente con nombre.** La razón está escrita en el
propio `_CompactHistorySelector`, para que nadie la «arregle» hacia S-05.

### Lo que la app viva encontró y el harness no

**El popover se comía el viewport.** Cada opción es un `Row` con `Expanded`, así
que la columna adoptaba el ancho **máximo** admitido: medido en la app,
**1.672 px colgando de un campo de 206**. Mi prueba no lo cazó porque sólo exigía
`ancho >= ancho del campo`, que un menú del ancho de la pantalla cumple de sobra.
Corregido con `IntrinsicWidth`; el aserto ahora acota por arriba y **se comprobó
que muerde** (sin el arreglo mide 1.344). En la app quedó en **194 × 30**, que es
el interior exacto del campo de 206.

**`I-01` mide 34, igual que `S-05`.** El `NÚMERO DE CUENTA` de la hoja salía en
~40 por un `contentPadding` vertical sin fuente, así que al volverse S-05 el TIPO
los dos campos de la misma fila quedaban a distinta altura. Se corrigió el que no
tenía fuente.

### 31 · las seis casillas, en la app viva contra producción

Sesión `62796` / `:60018`, sin cargar archivos y **sin pulsar «Guardar método»**.

| | Escritorio 1360 | Tablet 834 | Móvil 430 |
|---|---|---|---|
| **Oscuro** | sí · popover | sí · popover | sí · **bottom sheet** |
| **Claro** | sí · popover | sí · popover | sí · **bottom sheet** |

Comprobado además **en vivo, no sólo en harness**: `Escape` cierra sin cambiar el
valor (el campo siguió anunciando `= Sin especificar`), elegir una opción sí lo
cambia (`= Cuenta Corriente`), y a 430 el árbol semántico dice
`Tipo de cuenta · [encabezado]` con filas de `430x48` — la anatomía de O-05, no
un popover.

**El editor de fichas quedó PARCIAL y se declara así.** Se alcanzó el campo en
vivo —`Tipo de Cuenta · = Sin especificar · [botón cerrado] · 477x48`, coherente
con los 7 trabajadores que hoy lo tienen `NULL`— pero **no se abrió su menú**: el
panel de «Salario y Horas» no respondió al scroll sintético y ese nodo no tiene
identidad tocable en su posición. El dominio sí está probado por contrato
(`BankAccountType.storageDomain` y el viaje de ida y vuelta del decode).

### 26 · el bloqueo que sigue en pie

`apply` sigue recibiendo `methodId` y `methodCode` como argumentos
independientes de un catálogo que el cliente pudo cargar hace rato, y el guard
optimista sobre `employees.updated_at` **no cubre** que alguien desactive o edite
`payment_methods` en paralelo. La solución es un **RPC tenant-scoped y atómico**
que valide el método activo y respaldado, **derive el `code` en el servidor** y
aplique el `expectedUpdatedAt` en la misma transacción. Esta tarea prohíbe writes
de producción y desplegar migraciones: **queda declarado, no resuelto.**

---

### Texto original de la revisión, para que no se pierda el porqué

25. **`S-05`: registrar la divergencia NO alcanza.** Yo argumenté coherencia con
    los otros dos selects de Payroll y **ese argumento no deroga la regla
    repo-wide**: `AGENTS.md` y `universal-ui-component-system.md` exigen que un
    control compartido se implemente **bajo su id** y prohíben la variante
    local de una feature. Lo que corresponde: crear o reutilizar un owner
    **`VbShortSelect` (S-05)** sobre `showVbAnchoredPopover` en escritorio y
    **bottom sheet en compacto** —que es lo que la guía manda para táctil—, con
    **todos sus valores leídos de DesignSync**, y migrar coherentemente a los
    **tres** consumidores: `payroll_method_sheet.dart`,
    `payroll_history_surface.dart:405` y
    `payroll_reconciliation_page.dart:3628`. Un valor que no se pueda leer **se
    reporta ilegible**, no se estima.

26. **P1 · La autoridad del método no es atómica.** `apply` recibe `methodId` y
    `methodCode` **como argumentos independientes**, tomados de un catálogo que
    el cliente pudo cargar hace rato: nada garantiza que sigan siendo el mismo
    método, ni que siga activo y con cuenta. Y el guard optimista es sobre
    `employees.updated_at`, que **no cubre** que alguien desactive o edite
    `payment_methods` en paralelo. La solución completa es un **RPC
    tenant-scoped y atómico** que valide que el método está activo y
    respaldado, **derive el `code` en el servidor** —para que las dos columnas
    no puedan divergir por un argumento mal pasado— y aplique el
    `expectedUpdatedAt` en la misma transacción. **Esta tarea prohíbe writes de
    producción y desplegar migraciones**, así que queda como **bloqueo de
    contrato declarado**: no se finge cerrado ni se despliega nada.

27. **P2 · La clasificación de errores diagnostica de más.** Hoy **todo**
    `PostgrestException` que no sea `42501` cae en `rejected`, y la UI dice «el
    tipo de cuenta o el método no son válidos». Para un timeout o un error de
    servidor eso es un **diagnóstico falso** sobre el dato del operador. Sólo
    las violaciones de **constraint / FK** son rechazo; el resto debe ser «no
    autorizado» o «no disponible», siempre **sin texto crudo del servidor**.

28. **P2 · El conteo de pagos convierte una falla en `0`.** La paginación y el
    `count(exact)` quedaron bien, pero el `catch` devuelve `0`, y en pantalla
    «0 pagos» se lee como **«no tiene pagos»**, que es una afirmación distinta
    de «no pude contarlos». Hay que modelar
    **`known(0)` / `known(n)` / `unavailable`** y probar el estado indisponible.
    Además la paginación necesita **orden estable** (`order` explícito) para no
    saltarse ni duplicar filas si algo cambia entre páginas.

29. **`touchesBankAccount = true` por defecto es inseguro.** Un llamador que lo
    omita **borra los tres campos bancarios** — exactamente el defecto
    destructivo que esta ronda vino a corregir, reintroducido como valor por
    defecto. Se deriva del método **dentro del owner**, o se exige el argumento
    sin default.

30. **`AGENT_DATABASE_CONTRACT.md` todavía no tiene la lección reusable.** La
    causa quedó escrita en el ledger y en `BankAccountType`, pero no en el
    documento que gobierna cómo se consulta la base: **`text` + `CHECK` no es
    texto libre; se lee `pg_constraint` antes de declarar el dominio de una
    columna.** Ahí es donde el siguiente agente la va a buscar.

31. **Pendientes visuales de 5g, que siguen abiertos:** claro, tablet y móvil
    sin capturar; el estado *sin método* sin capturar; el ancho **424 vivo
    contra 460 del spec** (recorte en el host del diálogo, compartido con 5d);
    y **la pantalla del editor de fichas sin verificar en vivo** tras
    corregirle la serialización de `bank_account_type`.

---

## 5. Cómo verificar que no rompiste nada

```bash
.fvm/flutter_sdk/bin/flutter test $(ls test/widgets/payroll_*.dart test/unit/payroll_*.dart | tr '\n' ' ')
```

**306/306 es HISTÓRICO** (cierre del 2026-07-31) y ya no describe nada vigente.
El número al cerrar esta sesión es **364/364 en 33 suites**, y se cita con el
comando de §0 del encabezado, no con éste. El listado de arriba tampoco incluye
`test/widgets/vb_*_test.dart` ni `test/unit/native_session_stop_contract_test.dart`,
que sí entran en la batería vigente.

El gate completo del repo quedó **verde** al cierre de publicación, incluidas
las pruebas exclusivas de navegador. Los 10 rojos que bloqueaban el intento
anterior eran contratos desactualizados fuera de `lib/modules/hr`; se
repararon antes de preparar este release.

---

## 6. Por dónde empezar

En este orden. Los dos primeros no dependen de nada ni de nadie.

1. ~~**5d** confirmación de semana~~ → **CERRADO el 2026-08-01**, seis celdas.
2. ~~**5k**, los siete estados del módulo~~ → **CERRADO hasta donde una
   migración visual puede llegar (2026-08-01).** `carga` hecho y verificado en
   las seis celdas vivas · `vacío` hecho hasta donde el modelo garantiza ·
   `conflicto` ya resuelto en 5d · `cola local` y `Deshacer` descartados con
   razón · `error` diagnosticado y bloqueado por ownership (§4.20) · `permiso`
   sin capacidad. **Lo que queda son contratos de sistema, no frames.** El
   inventario original, por si hace falta releerlo: No es una pantalla y **no se puede
   estimar como un frame**: cuatro de los siete estados no existen (esqueleto
   de carga, error con referencia de soporte, cola local offline, toast de
   éxito con `Deshacer`), dos están parciales y uno ya se resolvió en 5d.
   Cerrarlo valida 5a/5i/5e/5f/5j de paso, y **cada estado que se implemente
   hay que verificarlo en las seis celdas de sus superficies**, no sólo en una.
   **Alcance ya decidido (Codex, 01/08) — no lo vuelvas a abrir:**

   | Estado | Decisión |
   |---|---|
   | Esqueleto de carga | **Hacer.** Único sin backend nuevo; valores literales de DesignSync. El más visible: hoy el control de decisión **salta de sitio** al llegar los datos |
   | Vacíos honestos | **Hacer, pero sólo donde el modelo distinga la causa.** Tres vacíos exige tres causas distinguibles; si el modelo no las distingue, no se inventan |
   | Cola local offline | **DESCARTADA en esta ronda.** Persistencia, replay, idempotencia, seguridad, concurrencia y contabilidad — capacidad de sistema, no migración visual. **Media cola es peor que ninguna**: el usuario cree que su pago está guardado |
   | `Deshacer` de 8 s | **DESCARTADO en esta ronda.** Son writes financieros: exige contrato de reversa, permisos y auditoría |
   | Error recuperable | **Adaptar**, no copiar. Nada de `err-####` inventadas ni de prometer «borrador intacto» si el owner de estado no lo garantiza. Errores **tipados reales**, y preservar panel/input **sólo donde el owner lo demuestre** |
   | Permiso | **NO implementado y NO derivable** (corregido el 2026-08-01). `blockedReason` se conserva **sólo para sus bloqueos reales** —versión del backend, explicación del borrador, saldo y estado— y **no es RBAC**, así que no cierra este estado. Esta superficie no expone rol: es capacidad nueva. `reviewPermissions` es del owner separado de 5j. **No se inventan roles** |

   **Lo descartado no es deuda implícita ni se maqueta como UI falsa**: una
   pantalla que ofrece deshacer un pago que no puede deshacer miente sobre
   dinero, que es justo lo que 5d acaba de corregir.

   **Antes de tocar código**, mapea `Owner → Control → Operation → Consumers`
   en las cinco superficies y decide **en cuál aplica cada estado**: 5k no se
   implementa en un archivo, se reparte.
3. **Paso 4 del OCR** — pasos 1 y 2 **cerrados el 2026-08-01** (ver §2).
   **El 4 es lo siguiente y es el único punto de escritura del flujo.** Frame: `handoff-t5/frames/5j-paso4.png`;
   el oscuro está en `handoff-t9/frames/7c-ocr-*`. Ownership: la superficie vive en
   `lib/modules/hr/pages/payroll_reconciliation_page.dart`, que **es el único
   sitio del módulo con errores tipados reales**
   (`PayrollReconciliationRecoveryAction` + `canRetrySameOperation`), así que el
   estado de error de 5k se cierra ahí y no en la página de Nóminas. **Antes de
   tocar cada paso**: `DesignSync` del frame, compuerta de seis dimensiones y el
   bloque copiar/descartar/agregar, uno por paso. **Producción es sólo lectura**:
   la etapa 1 pide un archivo real y **no se sube ninguno**.
4. **El sheet de 5g** (método/banco/tipo/cuenta/titular a 460): es lo único que
   le falta a un frame ya empezado.
5. **La matriz oscuro/compacto de 5i, 5e, 5f y 5j-p3** contra los frames de
   `handoff-t9`, que ya están publicados y se pueden bajar.
6. **5n** matriz de cierre.

**Ya no hay nada bloqueado por Design** (verificado el 2026-08-01). `5c` y el
cierre de `5h` esperaban una republicación en bandas que Design **ya había
hecho**: existen `5c-p1/p2` y `5h-p1/p2`, y bajan enteros. Los dos entran a la
cola como cualquier otro frame — ver §4.7.

Cada frame se cierra demostrando **los dos ejes** —brillo × host— y se escribe
en el ledger **al cerrarlo**, no al final. Una superficie sólo en
claro-escritorio **no está entregada**: le faltan cinco casillas.
