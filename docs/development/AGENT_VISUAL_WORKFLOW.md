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
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $P) to set size of front window to {430, 928}"
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

### Cambiar a oscuro, y volver

No hay comando: se hace por la UI del módulo de Configuración.

```bash
scripts/dev/app_control.sh tap --label "Configuración"
scripts/dev/app_control.sh tap --label "Apariencia"
scripts/dev/app_control.sh tap --label "Oscuro"      # o "Claro"
```

**Escribe la preferencia persistida del dueño. Déjala en `Claro` al terminar** —
la app es suya, no un banco de pruebas.

**Si el toggle se resiste, no insistas a ciegas.** El pase oscuro también se
verifica sin la UI: `payroll_redesign_dark_host_test.dart` monta las superficies
en 6 presets × 2 modos y `payroll_visual_tokens_test.dart` verifica capas,
escalera de elevación y que un sheet no se confunda con el fondo. Para juzgar la
**composición** contra el frame igual necesitas la captura, pero no te bloquees:
sigue con un frame que no dependa del oscuro y vuelve después.

### Cambiar de breakpoint

```bash
P=$(scripts/dev/app_control.sh geometry | sed -n 's/^pid \([0-9]*\).*/\1/p')
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $P) to set size of front window to {430, 928}"
```

**430** compacto · **880** tablet · **1180** sidebar expandido · **1672**
escritorio. Devuélvela como estaba al terminar.

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
| 5 | **¿El layout aguanta en las tres vistas?** claro, oscuro, compacto — y con los recursos que este ERP ya usa | la app corriendo en cada breakpoint |
| 6 | **¿Rompe armonía con otros módulos?** ¿Reinventa un control que ya es canónico? | `universal-ui-component-system.md`, la guía de componentes |

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

### Prometer y detenerse

Cerré un turno diciendo «sigo ahora mismo, no me detengo» y terminé el turno.

> **La regla:** si dices que sigues, sigue. Y si el trabajo es largo, el ledger
> se escribe **al cerrar cada frame**, no al final: es lo único que sobrevive si
> el chat se acaba.

---

## 6. Qué necesita al dueño

Sin excepción: **commit, push, desplegar migraciones, y CHECKPOINT B** (writes
reales de conciliación). El repo tiene un guard mecánico que deniega esas
llamadas; no se rodea. Se le entrega el comando exacto y la evidencia.

Enviarle un prompt a Design es actuar en nombre del dueño: **requiere permiso
por mensaje**. Al pegarlo, la codificación va en la llamada a `pbcopy`, si no
los acentos salen rotos:

```bash
printf '%s' "$(cat prompt.txt)" | \
  __CF_USER_TEXT_ENCODING=0x1F6:0x8000100:0x8000100 pbcopy
```
