# Releases

The canonical promotion path is:

```text
feature/current line → pull request to protected main → integrity + preview
→ intentional merge → Production environment → post-deploy smoke
```

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

Pendiente, y es lo que queda del camino crítico: **el conductor todavía espera
la calificación completa antes de despachar los publicadores**, así que los
~8 min del gate siguen en fila delante de los ~13 de compilación aunque los
workflows ya sepan correr en paralelo. Cerrarlo exige despachar los
publicadores con el `integrity_run_id` de un gate **en vuelo** y que
`verify_integrity_qualification.mjs` espere a que ese run concluya en vez de
fallar por «no completado».

**Un test frágil que esto destapó.** `ai_tool_registry_test.dart` se daba 2 ms
de presupuesto real y fallaba con la máquina cargada, sin que nada estuviera
roto. Ya era frágil; correr cuatro procesos a la vez sólo lo hizo visible. Se
le dio holgura sin cambiar lo que afirma. Un test que mide tiempo real necesita
márgenes que aguanten un corredor ocupado.

## El recuadro de novedades (2026-08-06)

`prepare_erp_update.sh` genera la nota de usuario con el **Codex local**. Esa
cuenta lleva tiempo sin cuota: el generador responde «the Codex account hit its
usage limit», el pipeline sigue adelante y la actualización sale con el texto
determinista («Esta actualización incluye ajustes en …»). Ése es el motivo real
—no un bug del recuadro— de que las publicaciones nunca hayan llevado una
descripción escrita.

La salida está en el propio pipeline: **`--notes-candidate <archivo.json>`**.
Quien conduce la publicación escribe la nota y el gate la valida; el productor
del texto es intercambiable, lo que garantiza que sea cierta es la validación.
Cuatro reglas que cuestan un intento fallido cada una si se ignoran:

1. Forma exacta: `{title ≤80, summary ≤280, modules[1..5]}`, y cada módulo
   `{id, label, items[1..3] ≤160, evidence_ids[1..12]}`. `id` y `label` salen
   de `RELEASE_NOTE_MODULES`; el label debe ser el del id, no otro.
2. **Cada `evidence_id` debe pertenecer al módulo que lo cita.** El módulo lo
   decide la ruta del archivo, no el tema: casi todo el trabajo de AliExpress
   vive en `lib/shared/` y por eso cuenta como `general`, no como `purchases`.
3. Sólo valen las evidencias del catálogo **inspeccionable** (sin binarios,
   generados ni sensibles); por ejemplo un `supabase/tests/*.sql` queda fuera.
4. Los `change_NNN` se leen del inventario del rango, no se inventan:
   `collectReleaseInventory(...)` + `createCodexReleaseContext(inv).changes`.

5. **El gate mide qué tan concreta es la nota, no sólo su forma.** Rechaza con
   «AI release notes are too generic» si los ítems no nombran algo observable.
   Cada ítem se valida contra dos vocabularios de `generate_release_notes.mjs`:
   el del módulo (`CONCRETE_RELEASE_LANGUAGE`, p. ej. en `general`: botones,
   ventanas, listas, notificaciones, búsqueda, descargas) y el de conducta
   visible (`USER_OBSERVABLE_RELEASE_LANGUAGE`: ahora, puedes, muestra, avisa,
   elige, móvil…), con un mínimo de 6 palabras. En una publicación con dos o
   más commits, **la mitad de los ítems y al menos dos deben pasar**. Escribir
   «se mejoró el flujo» nunca pasa; «Ahora el menú del móvil incorpora un botón
   para abrir otro espacio de trabajo» sí, y además se entiende.

Antes de gastar una publicación, valida el candidato en seco con
`acceptCodexReleaseEnvelope(envelope, {inventory})`: devuelve `source: "ai"`
cuando pasa, y el motivo exacto cuando no.

Firebase rollback uses the previous Hosting release. Windows rollback uses the previous signed/checksummed artifact. macOS internal rollback restores the previous verified bundle retained under the per-user updater support directory. Database rollback follows the database backup/restore runbook and must not improvise destructive reverse SQL.

For a Firebase rollback, select the last release whose retained evidence and
post-deploy checks passed, restore it through Firebase Hosting release history,
then verify its `release.json` commit and rerun `just db-health production`.
