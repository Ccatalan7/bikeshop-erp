# Nóminas → migración a los diseños de Claude Design · handoff vivo

**Actualizado 2026-07-31, cierre de la segunda sesión.** Reemplaza al handoff
anterior del mismo día: lo que decía sigue valiendo, pero la mitad ya está
hecha y el método cambió.

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
pregúntale al dueño primero — igual el guard mecánico del repo te lo va a
denegar, así que la pregunta es de todos modos suya.

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

# 2 · ¿La base está sana? Debe dar 306/306 o más.
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
3. Verificado en **claro, oscuro y compacto**. Sólo claro-escritorio no cuenta.
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
| Commit / push | El repo tiene un **guard mecánico** que deniega la llamada. Se le entrega al dueño el comando exacto |
| Desplegar migraciones | Requiere autorización en el momento |
| Mandarle un prompt a Design | Permiso **por mensaje** |

CHECKPOINT A (las 7 migraciones) ya fue ejecutado; el backend versionado está
activo en producción. No lo repitas.

**La app corre contra PRODUCCIÓN.** Por eso se toca por identidad y nunca por
coordenada: el 30/07 un clic de navegación cayó sobre `Quitar de la semana` y
escribió de verdad.

---

## 2. El estado real, frame por frame

### Cerrado

| Frame | Qué quedó |
|---|---|
| **5a** cola de semanas | Columna `PAGADO`; `A PAGAR` = `total − anticipos` (era el saldo, y una fila pagada mostraba `$0` rompiendo la aritmética del pie); chip de decisión con método y fecha; fila abierta con sus tres paneles; resumen de la semana en el header; franja de quién queda fuera del cálculo; tercer tier de columnas para 5m. **Claro, oscuro y compacto** |
| **5i** Historial | Banda de aritmética completa y en orden (`TOTAL · ANTICIPOS · A PAGAR · PAGADO · SALDO`) con tonos por función; personas y saldo en la lista; pie «Origen de los pagos»; `—` en vez de `$0`. Claro |
| **5e** transferencia | El caso se **declara** (Completo / Con diferencia / Parcial) en vez de inferirse del monto, más la nota de consecuencia antes del botón |
| **5f** efectivo | Desglose rotulado; la nota que justifica la pantalla («el efectivo no tiene cartola: esta confirmación ES el comprobante»); qué pasa al desmarcar el anticipo; `Entregado por` |
| **5j paso 3** | **La tabla de Design instalada**, reemplazando el ledger que otro turno improvisó. Un vocabulario solo para la certeza. Persona **y semana** en la fila |
| **5g** parcial | El retorno al pago —«el punto del flujo»—: las tres entradas vuelven al composer de esa misma fila. **Falta su sheet propio** |

### Sin empezar

**5c** gramática de decisión · **5d** confirmación de semana · **5h** anticipos ·
**5k** los siete estados del módulo · **5n** matriz de cierre · **pasos 1, 2 y 4
del OCR** · el **sheet de 5g**.

### El pase oscuro

Design entregó **`handoff-t9`** (turno 7 de su página) con 5a, 5i, 5j-p3, 5e y
5f en **Pacific y Aubergine**. De ahí ya se implementó la quinta capa `overlay`
para los sheets. **Falta comparar frame por frame** el resto.

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

---

## 4. Deuda abierta, con nombre

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
   por semana.
5. **Selector de mes** de 5i, con su nota honesta de cuántas semanas quedan
   antes.
6. **~54 rutas sin confirmar** en el árbol. Commit es del dueño.

---

## 5. Cómo verificar que no rompiste nada

```bash
.fvm/flutter_sdk/bin/flutter test $(ls test/widgets/payroll_*.dart test/unit/payroll_*.dart | tr '\n' ' ')
```

**306/306 verde** al cierre de esta sesión. Analyzer del scope limpio.

El gate completo del repo quedó **verde** al cierre de publicación, incluidas
las pruebas exclusivas de navegador. Los 10 rojos que bloqueaban el intento
anterior eran contratos desactualizados fuera de `lib/modules/hr`; se
repararon antes de preparar este release.

---

## 6. Por dónde empezar

1. Bajar `handoff-t9/frames/7a-pacific-p2.png` y `7a-aubergine-p2.png`, y
   cerrar el pase oscuro de 5a comparando de verdad.
2. **5h** (Anticipos) y **5c/5d**, que son de uso real y no dependen de nada.
3. Los pasos **1, 2 y 4 del OCR**, que es la superficie con más carga cognitiva.
4. **5k**: los siete estados del módulo son un contrato que deben cumplir las
   cinco superficies, no una pantalla.

Cada frame se cierra en **las tres vistas** —claro, oscuro y compacto— y se
escribe en el ledger **al cerrarlo**, no al final. Una superficie sólo en
claro-escritorio **no está entregada**.
