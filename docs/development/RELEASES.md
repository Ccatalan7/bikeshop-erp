# Releases

The canonical promotion path is:

```text
commit on main (shared checkout) → git push origin main → integrity gate
→ Production environment → post-deploy smoke
```

Owner decision, 2026-09-25: no feature branches and no pull requests. The
owner's account is a repository admin and `enforce_admins` is off, so a direct
push to `main` bypasses the pull-request requirement; every deploy workflow
still runs `erp-integrity-gate.yml` before publishing. See
`.github/copilot-instructions.md` «Trabajar directamente en `main`».

- `main` is protected and rejects force-pushes/deletion.
- Firebase ERP/store and Windows release workflows consume the merged commit.
- Production jobs use the `Production` GitHub Environment; pull-request previews use `staging`.
- A workflow dispatch is diagnostic or exceptional and must still run its integrity dependency.
- Never deploy a dirty working tree or run direct production upload helpers as a normal release path.
- Record commit SHA, actor, environment, timestamps, checks and rollback reference.
- Web builds publish `release.json` and retained SHA-256 evidence. Promotion is
  successful only when the live Firebase target reports the exact merged commit.
- The ERP production job then runs the read-only inventory/payment/journal/trace
  invariant dashboard. A critical violation fails the release record without
  attempting an automatic data repair.

**A job queued without a runner blocks every later ERP web deploy
(2026-10-06).** `firebase-hosting-merge.yml` shares one concurrency group
(`production-erp-main`, `cancel-in-progress: false`). On 2026-10-05 the
`build_and_deploy` job of `1a8346f0` stayed `queued` on `ubuntu-latest` with
no runner for 18 hours (no annotations, no pending environment approval), and
every later push waited behind it as `pending` with no jobs: the ERP web did
not publish for a day while the store, on its own workflow, did. Check
`gh run list --status queued` when a deploy shows `pending` without jobs, and
cancel the stuck run; the next queued one deploys the latest commit.

**Storefront correction, 2026-10-01:** when a storefront push fails its gate,
a subsequent fix confined to tests/docs does not trigger its `paths` filter.
Read the live version before reporting delivery; the daily rebuild is pending
work until its release is verified. `workflow_dispatch` requires a real durable
publication UUID, and cannot substitute for the missing production ledger.
The exceptional store-only Mac path documented in
`docs/runbooks/MAIN_BRANCH_CUTOVER.md` remains available under delivery authority:
use a clean export of the approved commit, verify every source byte/mode and
its existing exact-SHA integrity qualification, run SEO/build/budget/snapshot
guards, write truthful `manual-shell` evidence, publish only `hosting:store`,
and compare the release and checksums on both live origins. Preserve shared
changes and stop before upload if the source or another storefront deployment
has advanced. The C5 receipt is
`.tmp/e2e/store-publication-2706b1f8-20261001/evidence.json`.

## Cuánto tarda publicar, y por qué (2026-08-07)

Línea base medida en el run 31153201788, antes de tocar nada:

| Etapa | Tiempo | Detalle |
|---|---|---|
| Gate de integridad | 13 min 39 s | 9 min la suite Flutter, 2,5 min compilar web, 1 min analyze |
| Build macOS | ~12 min 30 s | en paralelo con Android |
| Build Android | ~14 min | |

El gate y los publicadores corren **en fila**, así que una publicación completa
son ~28 minutos. La comparación con «en mi máquina son 3 minutos» engaña: un
corredor de GitHub tiene 2 vCPU y parte de cero, mientras el escritorio
reutiliza todo lo compilado. La misma suite tarda 4 min local y 9 en CI.

Lo aplicado:

1. **El gate corre la suite en cuatro partes paralelas** (`FLUTTER_TEST_SHARD_INDEX`
   / `FLUTTER_TEST_SHARD_TOTAL` en `run_flutter_test_gate.sh`, matriz en el
   workflow). `fail-fast: false` a propósito: el reporte debe decir todo lo que
   está roto, no lo primero.
2. **Caché de dependencias** (`~/.pub-cache`, y Gradle en Android) en el gate y
   en los dos publicadores. Antes sólo Windows cacheaba. Medido después:
   `pub get` con caché tibio tarda 0,5 s, así que el ahorro real está en Gradle
   (8 de los 12,5 min de Android), no en Dart. La estimación optimista inicial
   era falsa.
3. **Analyze, la compilación web y los contratos corren en un job hermano**
   (`checks`), al lado de las cuatro partes.
4. **El gate corre al lado de los builds**, no delante: en macOS `build`
   depende sólo de `source-guard`, y `publish` exige el gate por las dos rutas
   —`qualification` con calificación externa, `integrity` sin ella—; en Android
   `publish` arranca en paralelo y vuelve a verificar en un paso propio,
   inmediatamente antes de firmar y subir. Si el gate falla no se publica nada;
   sólo se gastó CPU compilando.

### Tres cosas que corrigen la intuición (2026-08-07)

**`needs` no es una puerta: es una espera.** Con `if: always()` un job igual
espera a que termine todo lo que nombra en `needs`, pase o falle. Poner
`needs: [source-guard, integrity]` en el build «para conservar la referencia»
deja el gate en fila delante del build igual que antes, y el paralelismo es
sólo aparente. Lo que se paraleliza se saca de `needs`; lo que se exige se
comprueba en el job que publica. El contrato vive en
`test/unit/macos_release_artifact_gate_test.dart`, que ahora afirma justamente
eso: `build` no puede nombrar a `integrity` ni a `qualification`, y `publish`
tiene que nombrar a los tres.

**Repartir no sirve si una parte carga con todo.** La primera medición del gate
en cuatro partes dio 794 s contra 819 s de línea base: 25 segundos. Las partes
1-3 terminaron en 492-571 s y la parte 0 en 794 s, porque analyze, la
compilación web y los contratos colgaban de `matrix.shard == 0`. El gate vale
lo que su parte más lenta; poner el trabajo extra dentro de una parte es
ponerlo en el camino crítico. Por eso existe ahora el job `checks`.

**Un cuarto de la suite tarda 433 s, no 135.** `flutter test` paga un costo
fijo de compilación en cada corredor, y ese costo no se reparte. La suite
completa tardaba 541 s; un cuarto tarda 433 s. Subir de cuatro partes a ocho no
baja el gate a la mitad —agrega ocho arranques en frío—, así que el techo de
esta técnica ya está cerca. Lo que queda por atacar es el costo fijo, no el
número de partes.

### Lo medido, y lo que queda (2026-08-07)

| Etapa | Antes | Ahora |
|---|---|---|
| Gate de integridad | 13 min 39 s | **8 min 42 s** (run 31163160950) |
| Publicación completa | ~28 min | **25 min 21 s** |

El gate bajó cinco minutos y eso se cobra en cada publicación y en cada PR. Lo
que sigue en el camino crítico es que **el conductor espera la calificación
completa antes de despachar los publicadores**: los ~9 min del gate quedan en
fila delante de los ~15 de compilación aunque los workflows ya sepan correr en
paralelo.

Las dos piezas para cerrarlo ya están y son la ruta normal desde el momento en
que se use la bandera:

- `qualify_erp_update.mjs --dispatch-only` despacha el gate y escribe su
  referencia apenas existe, sin esperar a que termine.
- `verify_integrity_qualification.mjs --wait-seconds <n>` espera a un run **en
  vuelo** en vez de rechazarlo por «no completado». Ambos publicadores lo
  invocan con 2400 s. Un run ya concluido en fracaso nunca se reintenta: se
  rechaza en el acto.

Con eso el orden pasa a ser: preparar → despachar gate → arrancar los dos
publicadores de inmediato → cada uno compila mientras el gate corre y verifica
ese run exacto antes de firmar y subir.

**Probado el 2026-08-07** en la publicación de `27d2e52e`:

| | Fila (25/06 anterior) | Camino rápido |
|---|---|---|
| macOS | 25 min 21 s | **13 min 58 s** |
| Android | 25 min 21 s | 18 min 29 s |

Y la misma trampa cobró de nuevo, en el sitio que se había «arreglado»:
Android tardó cuatro minutos y medio más que macOS porque su `publish` todavía
nombraba a `qualification` en `needs`. Con `always()` eso lo hacía esperar a
que el gate entero terminara, así que la compilación arrancaba diez minutos
tarde. macOS, que depende sólo de `source-guard`, arrancó de inmediato. La
exigencia del gate no va en `needs`: va en el paso que corre justo antes de
firmar y subir, y ahora el contrato de Android afirma exactamente eso —
`publish` no puede nombrar a `qualification`, y el paso de verificación tiene
que preceder al de compilar/firmar/subir.

**Segunda medición, 2026-08-07** (`07d433d6`, ya sin `qualification` en el
`needs` de Android): macOS **11 min 39 s**, Android **18 min 39 s**. Android no
mejoró, y el desglose dice exactamente por qué:

```text
Require the integrity qualification …  20:45:31 → 20:52:36   (7 min 05 s esperando)
Build, sign, upload, and verify …      20:52:36 → 21:00:39   (8 min 03 s)
```

**En Android compilar y subir son el mismo paso.** Como la verificación tiene
que ir antes de subir, termina yendo antes de compilar, y la espera al gate
vuelve al camino crítico aunque el job arranque de inmediato. macOS no lo sufre
porque `build` y `publish` son jobs distintos: sólo el segundo espera.

**Corregido el 2026-08-07:** el publicador Android ahora separa sus fases dentro
del mismo proceso protegido: resuelve la versión, compila, firma y valida el APK
localmente; después espera la calificación exacta; y sólo entonces permite la
primera escritura a Storage y verifica el read-back. La clave es que el gate no
protege el gasto local de CPU: protege la mutación de producción. Si falla, el
APK construido se descarta sin subir nada. Los contratos fijan el orden
`flutter build` → firma verificada → gate exact-SHA → primera subida, por lo que
no se puede volver a adelantar una escritura remota ni poner la espera delante
del build por accidente. La medición real de esta publicación debe reemplazar
cualquier estimación anterior.

Cómo se corre el camino rápido:

```bash
bash scripts/releases/prepare_erp_update.sh
node scripts/releases/qualify_erp_update.mjs --prepared-state auto --dispatch-only
# y enseguida, sin esperar:
bash scripts/publish_macos_update.sh --prepared-state auto &
node scripts/releases/publish_android_workflow.mjs --prepared-state auto &
```

**Si el rango toca `packages/vinabike_public_core/` o
`services/storefront_html/`, también se publica el servidor HTML** de
vinabike.cl, desde el commit que se sube y antes de que termine la
publicación de la tienda:
`bash services/storefront_html/deploy_cloud_run.sh` (necesita `gcloud` con
sesión; ~5 min). La tienda Firebase compara el origen que responde Cloud Run
con el de su commit y falla si no calzan
(`check_storefront_html_routes.mjs`). Esa regla estaba sólo en la sección de
URLs del documento padre y no en este procedimiento: la 1.0.20 (2026-10-10)
publicó macOS, Android y la web del ERP, y la tienda falló dos veces seguidas,
la segunda sólo por esto, con «Desde», «A cotizar» y el JSON-LD de servicios
ya en el código y no en vivo. Se ve con
`git diff --stat <base> HEAD -- packages/vinabike_public_core services/storefront_html`.

**Un test frágil que esto destapó.** `ai_tool_registry_test.dart` se daba 2 ms
de presupuesto real y fallaba con la máquina cargada, sin que nada estuviera
roto. Ya era frágil; correr cuatro procesos a la vez sólo lo hizo visible. Se
le dio holgura sin cambiar lo que afirma. Un test que mide tiempo real necesita
márgenes que aguanten un corredor ocupado.

## Versiones y novedades verificadas (corregido el 2026-10-01)

Cada entrega de código nuevo avanza la versión visible: **1.0.4, 1.0.5…**.
`release_version.mjs` lee los manifiestos publicados de escritorio y Android
antes del commit y actualiza el patch de `pubspec.yaml`. Respeta una subida
intencional de minor/major; rechaza versiones inferiores a las publicadas. Un
reintento limpio del mismo commit conserva la versión. El contador de bundle
macOS y el código de APK Android siguen siendo crecientes, separados de la
versión que ve la persona. Los publicadores protegidos también rechazan otro
commit con la misma versión visible; no se renumeran artefactos históricos.

La congelación anterior tenía una causa concreta: `pubspec.yaml` seguía en
1.0.3 mientras el publicador avanzaba sólo el código técnico. Las notas tenían
otra: Gemini recibía módulos y cantidades de archivos, no la conducta real.
El rango, rutas y vocabulario pasaban la validación incluso al inventar mejoras
de presupuestos, navegación o rendimiento sobre un cambio sólo de Debug.

Ahora el agente escribe las novedades al implementar y verificar el cambio.
El publicador las reúne automáticamente **sin reescribirlas**. Antes de crear
el commit, preparación exige un registro nuevo en `docs/releases/changes/`:

```json
{
  "schema_version": 1,
  "id": "search-input",
  "source": "ai",
  "scope": "release",
  "platforms": ["macos", "android"],
  "module": "general",
  "title": "Búsqueda disponible al volver a abrirla",
  "summary": "El buscador vuelve a recibir lo que escribes después de cerrarlo y abrirlo otra vez.",
  "items": ["Puedes cerrar y volver a abrir el buscador sin perder la posibilidad de escribir."],
  "evidence": [{"path": "ruta/real/del/dueno.dart", "sha256": "sha256 exacto del archivo verificado"}]
}
```

El ejemplo ilustra la forma; una evidencia inventada no pasa. El registro real
usa rutas cambiadas en el rango y hashes completos de sus blobs finales. Para
una eliminación se cita el blob anterior. Cada archivo de implementación o
publicación cambiado debe estar cubierto por un registro; documentación y tests
por sí solos no sustentan una conducta publicada. La nota dice qué deja de
fallar o qué puede hacer ahora la persona, sin jerga, relleno, datos privados,
beneficios supuestos ni afirmar que un test equivale a aceptación de producto.
Se revisa cada afirmación contra el código y la verificación real antes de
registrarla. El hash detecta revisiones pendientes; no prueba la veracidad del
texto por sí solo.

`scope` puede ser `release`, `debug` o `internal`. Sólo `release` aparece en
las plataformas declaradas. Debug/internal llevan `title`, `summary` vacíos e
`items: []`; no anuncian beneficios. La subida automática de versión genera su
registro interno de metadatos. Si una plataforma sólo tiene cambios internos,
la nota declara que no hay cambios funcionales visibles. Los registros ya
publicados son inmutables: una corrección agrega otro. Para un canal atrasado,
se revisa todo su rango real; nunca se corta el historial para ocultar cambios.

El ensamblador valida evidencia, cobertura, alcance, plataforma, módulo dueño,
texto plano y límites: título 80, resumen 280, 1–5 módulos, hasta 3 ítems de 160
caracteres por módulo y hasta 12 rutas en el manifiesto. Con más de una novedad
visible, el resumen de la plataforma es la unión de sus títulos con «. », y
también tiene el tope de 280: el 2026-10-01 cinco títulos sumaron 281 y la
validación falló. Un título nuevo se escribe corto (unas 45 letras) y se mide
la unión antes de dar el registro por bueno. El tope de tres ítems también es
**por módulo en todo el rango**, no por registro: el 2026-10-02 un registro nuevo
del taller con tres ítems falló («Curate each module into at most three
distinct release items») porque otro del mismo rango, aún sin publicar, ya
tenía tres. Mientras el registro anterior no esté publicado (`A` desde la
base), se funden los dos en él con tres ítems y la evidencia unida; un
registro nuevo sólo cabe si el módulo tiene ítems libres. El registro conserva
la evidencia completa; no se recortan afirmaciones para cumplir los límites.

El módulo dueño lo decide `moduleForReleasePath` por palabras de la ruta, en
orden (taller, inventario, ventas…, sitio web después), no por la carpeta:
`lib/public_store/pages/product_catalog_page.dart` cuenta como **Inventario**
por `product_`, y `checkout_page.dart` como Ventas. Un registro `website` cuya
única fuente es una de ésas falla con «A release module needs evidence from
its source owner» (2026-10-07, arreglo del catálogo del editor). Se funde en
un registro abierto del sitio que ya tenga fuente del sitio; poner
`inventory` sería mentirle a quien lee las notas.

**Qué lleva registro y qué no (2026-10-09).** Sólo cuenta como conducta
publicada el código que viaja en una app: `lib/`, `android/`, `macos/`,
`windows/`, `ios/`, `scripts/`, `.github/workflows/`, `pubspec.yaml`, el
núcleo `packages/vinabike_public_core/` y `services/storefront_html/`
(`requiresReviewedChange` en `scripts/releases/reviewed_release_changes.mjs`).
Un cambio sólo de `supabase/` (migraciones, Edge Functions) o de `web/` no
lleva registro propio: uno que sólo cite esas rutas falla con «Documentation
or tests alone cannot establish a shipped behavior», aunque no sea
documentación. Sí hay que refrescar la huella de un registro abierto que cite
uno de esos archivos. Pasó con el aviso de pedidos web al teléfono
(`20261009020000` + `push-notification`).

`--check-index` valida lo que está **en el índice de git**, no el árbol de
trabajo: hay que hacer `git add` del registro y de sus fuentes antes de
correrlo. Sin eso valida la versión anterior y dice «verified» igual; el
2026-10-02 un ítem de 186 letras pasó así y se commiteó, y el error recién
apareció al volver a validar después del commit.

**Siempre con `--from-commit <base>`.** Sin él, `--check-index` revisa la
forma y las huellas de los registros del índice, pero no el rango: no ve un
archivo cambiado que ningún registro cubre ni el tope de tres novedades por
módulo. El 2026-10-08 `ae0218a7` salió así con `scripts/dev/web_preview.sh`
sin registro y una cuarta novedad del sitio; lo atrapó la validación con base
del commit siguiente, que tuvo que agregar el registro y fundir novedades.

Se valida antes de **cada** commit, también uno «sólo de CI» o de
configuración: si toca un archivo que un registro abierto cita como evidencia
(un flujo de `.github/workflows/`, `firebase.json`), ese registro necesita su
hash nuevo. El 2026-10-05 un cambio al filtro del flujo de la tienda salió sin
validar y con la huella vieja; lo atrapó la validación del commit siguiente.
Un archivo puede estar citado por **varios** registros abiertos: se buscan
todos y entran al mismo commit. Abierto es el que se **agregó** después de
la base (`git diff --name-status <base> -- docs/releases/changes/`, filas
`A`); un `grep -l <ruta>` también encuentra los ya publicados, y esos no se
tocan aunque citen el archivo: el validador los rechaza («Published change
records are immutable») y no revisa su huella vieja. El 2026-10-07 un
refresco por `grep` cambió 11 registros publicados y hubo que devolverlos. Y la validación no va en una cadena `… | head && git commit`: el
estado de una tubería es el del último comando, así que un validador que
falla deja pasar el commit. El 2026-10-07 un arreglo del carrusel se
commiteó así con la huella vieja en `editor-html-view.json` (también lo
cita) y necesitó un commit aparte.

**La base no es el último commit «chore: publica…» que uno recuerda
(2026-10-09).** Una ronda validó sus registros contra `0e386312` (el
«publica» del 8-oct en la mañana) cuando la 1.0.18 había salido después, de
`615749ba`. Con la base equivocada, tres registros ya publicados en la 1.0.18
parecían abiertos y se les fundieron novedades y huellas nuevas (el de
categorías, el de servicios y el de WhatsApp). Nada lo atajó durante un día:
los despliegues de Firebase y de la tienda **no validan registros**; sólo los
publicadores de macOS, Android y Windows lo hacen, contra la versión
publicada. Apareció recién al preparar la 1.0.19 («Published change records
are immutable»): hubo que devolver los tres a como se publicaron y escribir
dos registros nuevos. La base se lee siempre con
`node scripts/releases/release_version.mjs --prepare --macos` (campo
`notes_base`), también para un commit que sólo publica la web.

La base publicada exacta es la que imprime la preparación («Notes base»):
`resolve_previous_release_commit.sh` da la última versión de escritorio y
`resolve_paired_release_notes_base.mjs` la cruza con la última de Android.
`node scripts/releases/release_version.mjs --prepare --macos` imprime su
`notes_base` por otro camino; **si las dos no coinciden, se para antes de
publicar**. El 2026-10-06 el resolvedor tomaba la primera versión que listaba
la API de GitHub, y la API puso 1.0.9 y 1.0.8 antes de 1.0.10 (no ordena por
fecha). La preparación de 1.0.11 eligió la base de 1.0.9, validó un rango con
registros ya publicados en 1.0.10 y huellas viejas, y los dos publicadores
fallaron sin publicar nada: una ronda entera perdida. Desde ese día ordena por
`published_at`.

```bash
node scripts/releases/generate_release_notes.mjs \
  --check-index --from-commit <base-publicada-exacta>
node scripts/releases/generate_release_notes.mjs \
  --from-commit <base-publicada-exacta> --to-commit <corte-exacto> \
  --platform android --output <notas.json>
```

CI vuelve a validar el rango y los hashes antes de firmar/publicar. Falta de
registro o evidencia obsoleta **bloquea** la entrega: no produce una nota
vacía de valor para que el job quede verde. No usa Gemini ni credenciales de
modelos. El texto sigue siendo escrito y revisado por la IA que implementa;
`source: ai` conserva el contrato de las apps instaladas. El log correcto es
`Release notes source: ai; provider: reviewed-change-records`. Las utilidades
históricas de generación con metadatos quedan fuera del publicador estándar.

Firebase rollback uses the previous Hosting release. Windows rollback uses the previous signed/checksummed artifact. macOS internal rollback restores the previous verified bundle retained under the per-user updater support directory. Database rollback follows the database backup/restore runbook and must not improvise destructive reverse SQL.

For a Firebase rollback, select the last release whose retained evidence and
post-deploy checks passed, restore it through Firebase Hosting release history,
then verify its `release.json` commit and rerun `just db-health production`.
