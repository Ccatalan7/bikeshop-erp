# Transición canónica de `smartpegas1.0` a `main`

- Estado: **transición ejecutada el 2026-09-15 por la ruta simplificada
  (sección 0) a través del PR #29; en observación (paso 7) hasta el
  2026-09-22 como mínimo; `smartpegas1.0` todavía no se retira**
- Propietario de la decisión: dueño del repositorio
- Clase de cambio: Git/GitHub de alto impacto, con un despliegue web productivo
- Última revisión del diseño: 2026-09-15 (sección 0); 2026-07-29 (secciones 1-19)

## 0. Ruta simplificada (revisión 2026-09-15)

### 0.1 Qué cambió desde el diseño de julio

| Superficie | 2026-07-29 | 2026-09-15 |
| --- | --- | --- |
| `origin/main` | `7f87d3af…`, 1 commit exclusivo | `75cb391f…` (`P` de la PR #2, 2026-08-10), **0 commits exclusivos** |
| `origin/smartpegas1.0` | `32404d36…`, 596 por delante | `f51f3777…` (2026-09-07), 94 por delante, 0 por detrás |
| PR de promoción | #2 abierta y conflictiva | #2 fusionada el 2026-08-10; no existe PR abierta |
| Freeze de deploy (5.3) | propuesto | no implementado en ningún workflow |
| Tienda ante un push a `main` | publicaba | **publica** (corregido el 2026-09-15: la fila anterior decía «build y verificación solamente»; el paso `Deploy store target` corre cuando `is_publication != 'true'`, es decir, en todo push que llegue verde). Lo que **no** existe es el conducto durable por `request_id`: su contrato `20260728230000_add_storefront_publication_contract.sql` no está en producción |
| Instaladores ante un push a `main` | artifact-only | artifact-only, sin cambio |
| ERP web ante un push a `main` | publicaba | publica (`firebase-hosting-merge.yml`: integrity → build → deploy → verificación de commit → health de producción) |
| `erp-integrity-gate.yml` por push | sólo `smartpegas1.0` | `main` y `smartpegas1.0` (cambio preparatorio de esta revisión) |
| Environment `Production` | `main` y `smartpegas1.0` | sin cambio |

Consecuencia: `main` es hoy un **ancestro puro** de `smartpegas1.0`. Cualquier
PR `smartpegas1.0 → main` fusiona sin conflicto y el commit `P` tiene
exactamente el árbol de `F`, sin puente `M`, sin `-s ours` y sin reparar nada.
Las secciones 5.1, 11 y 12 quedan **sin efecto** mientras
`git rev-list --count origin/smartpegas1.0..origin/main` sea `0`; si alguna
vez vuelve a ser mayor que cero, se retoma el diseño de julio.

### 0.2 Lo que se nota y lo que no

- **Se nota una sola cosa:** `project-vinabike.web.app` (ERP web) pasa del
  build del 2026-08-10 al de `P`, es decir, recibe las cinco semanas de cambios
  que los instaladores de escritorio ya tienen. Es un cambio hacia adelante con
  el mismo código que corre el escritorio. Rollback: Firebase Hosting → sitio
  `project-vinabike` → release anterior (un clic), o forward-fix desde `main`.
- **También se nota, si el run llega verde:** la tienda (`vinabike.cl`) se
  publica desde el mismo push (corrección 2026-09-15; antes decía que sólo se
  compilaba). Hasta ese día ningún push la había publicado desde el
  2026-07-27 por dos defectos de `main`, no por diseño: ver paso 5.
- **No se nota:** los
  instaladores macOS/Windows sólo compilan artefactos; Android no se dispara;
  Supabase no recibe ninguna escritura; el checkout del Mac no cambia ningún
  archivo al cambiar de rama porque `tree(P) = tree(F)`; la URL de instalación
  de Windows apunta a `main`, donde el script es idéntico.

### 0.3 Secuencia

**Paso 0 · Preparación (rama de agente, esta revisión).** Trigger de
`erp-integrity-gate.yml` con `main`; `prepare_erp_update.sh` con
`VINABIKE_ERP_RELEASE_BRANCH:-main` y su test; documentos de distribución y
`copilot-instructions.md` apuntando a `main` con notas transicionales; esta
sección. Se fusiona en `smartpegas1.0` **inmediatamente antes** del paso 3.
Entre ese merge y el paso 4 no se publica ningún release: el preparador falla
cerrado porque `origin/main` todavía no es `F`.

**Paso 1 · Congelar.** En el Mac: sin publicadores, sin agentes escribiendo,
`git status --porcelain=v1` vacío en dos lecturas, `git ls-remote origin
main smartpegas1.0` estable entre dos lecturas. Se sigue 9.1 y 9.2 tal cual.

**Paso 2 · Respaldo.** Los dos tags de 10.4 (`cutover-backup/main-before-…` y
`cutover-backup/smart-before-…`) con push atómico. Si el entorno no puede
empujar tags (el proxy de las sesiones en la nube devuelve 403 para
`refs/tags/*`), se crean con la API de GitHub como **ramas** del mismo nombre
apuntando a `N` y `F`; cumplen la misma función forense y no se mueven.
Hecho el 2026-09-15: `cutover-backup/main-before-20260915` → `75cb391f…` y
`cutover-backup/smart-before-20260915` → `f51f3777…`.

**Paso 3 · PR `smartpegas1.0 → main`.** Título «Promote smartpegas1.0 to
canonical main (fast-forward tree)». Esperar `PR Integrity` (cuatro partes de
la suite más «Static analysis and packaged web build») y `Secret Scan`. Si
GitHub muestra un check requerido en estado *expected* que nunca llega, el
nombre guardado en la protección de `main` está obsoleto: corregir únicamente
ese contexto como en 12.1 y volver a leer la protección completa.
Ejecutado el 2026-09-15 como PR #29 con cabeza en la rama de agente
`claude/gifted-fermi-otkemj`, que ya contenía `smartpegas1.0` (`2c16b78`) más
el paso 0: equivale a fusionar el paso 0 en `smartpegas1.0` primero, y el
paso 6 deja ambas ramas en `P`. La primera corrida de `PR Integrity` cayó por
un guard de arquitectura que buscaba un nombre de método renombrado en el
último commit del Mac (`analyzer clean` no es `flutter test`); se corrigió en
el mismo PR sin tocar el invariante.

*Precisión 2026-09-15:* el check «expected» que nunca llegaba existía de
verdad —`integrity / Database and application regression gate`, nombre de
antes de partir el gate en shards— y no se corrigió en el paso 3: las PR #29 y
#30 se fusionaron como admin (`enforce_admins=false`) con la protección en
`BLOCKED`. Se reparó por §12.1 después del cutover, con el registro exacto en
§18 («Cambio exacto de protección»); desde entonces una PR normal llega a
`CLEAN` sola.

**Paso 4 · Merge.** Botón «Merge pull request» → «Create a merge commit». Nunca
squash ni rebase: ambos cambian los SHA que los manifests de release citan.
Verificar desde cualquier clon:

```bash
git fetch origin main smartpegas1.0
git diff --exit-code origin/smartpegas1.0 origin/main --
git merge-base --is-ancestor origin/smartpegas1.0 origin/main
```

**Paso 5 · Observar los runs del push a `main`.** «Deploy to Firebase Hosting
on merge» debe terminar con `release.json.commit` igual a `P` y health de
producción en verde; «Deploy Storefront» (push) debe terminar con su paso
`Deploy store target` en verde y `release.json.commit` igual a `P` en
`vinabike-store.web.app` **y** `vinabike.cl`; macOS/Windows deben quedar
artifact-only; `Secret Scan` y `ERP Integrity Gate` en verde. Smoke manual del
ERP web: login y tres rutas de uso diario.

*Corrección 2026-09-15 (esta línea decía «“Deploy Storefront” debe terminar
sin job de deploy»).* El workflow de la tienda sí publica en un push: cada paso
de `build_and_deploy` corre cuando `is_publication != 'true'`, y el run del
2026-07-27 (`30236101497`) lo demuestra con `Deploy store target: success`. Lo
que no existe en producción es el conducto **durable** (`workflow_dispatch`
con `request_id`, ledger `storefront_publication_*`, cron y la edge function
`dispatch-storefront-publication`): su migración
`20260728230000_add_storefront_publication_contract.sql` no está aplicada, y
sin ella el dueño no puede publicar desde el editor del sitio. Mientras eso
siga así, la tienda se publica **por el push a `main`** o, si ese run no
llega, desde el Mac con la porción `hosting:store` de `scripts/deploy.sh`
(sync SEO → build `web_store` → presupuesto → snapshots →
`write_storefront_release_evidence.sh` → `firebase deploy --only
hosting:store`), verificando `release.json` en los dos orígenes. El comando
`verify` de `storefront_publication_workflow.mjs` no sirve para una
publicación manual: exige `GITHUB_RUN_ID` y compara el `run` de la evidencia.

Por qué ningún push publicó la tienda entre el 2026-07-27 y el 2026-09-15 —dos
defectos de `main`, ninguno del diseño—:

1. El 2026-08-05 (`069e6b5e`) se agregó a mano a `firebase.json` la regla
   `/accept-invitation → https://project-vinabike.web.app/accept-invitation`
   (302) para que una invitación abierta en el dominio de la tienda llegue al
   ERP. `generate_product_seo_snapshots.dart` validaba **todas** las reglas del
   target `store` con el contrato de sus redirects generados (301, rutas
   relativas) y reventaba con «firebase.json contiene un
   source/destination/type inválido». Cayeron así el push del 2026-08-10
   (`31409100983`, paso «Generate SEO snapshots, sitemap, and product
   redirects») y `scripts/deploy.sh` en el Mac; la tienda en vivo quedó en
   `32404d36` (código del 2026-07-27, evidencia `manual-shell`, `dirty:
   true`, construida el 2026-09-02). Arreglo: el generador sólo posee las
   reglas que lista su manifiesto y conserva las demás tal cual, en su orden.
2. El primer build de `main` después del cutover (`dc1e609`) superó el
   presupuesto del bundle (`main.dart.js` 6 687 239 B contra 6 000 000; gzip
   1 775 132 contra 1 700 000), igual en el Mac y en CI (`35030810512`, paso
   «Build storefront release»). El bundle en vivo pesa 5 467 276 B: siete
   semanas de trabajo dejaron el host del editor del sitio y el chat de
   clientes importados de forma ansiosa en la tienda, y ocho trozos diferidos
   se fundieron en el principal. El canario nunca corrió en CI en ese período
   por el defecto 1. Se re-basó el presupuesto con ~9 % de holgura y el
   diferimiento quedó en §17.1.

**Paso 6 · Alinear.** `git push origin <P>:refs/heads/smartpegas1.0`
(fast-forward). En el Mac: `git fetch origin && git switch main` (ningún archivo
cambia; los cambios locales pendientes se conservan). VS Code, tareas y agentes
pasan a `main` por los documentos del paso 0.

**Paso 7 · Observación y retiro.** Sección 17 sin cambios: mínimo 7 días, una
PR normal fusionada, un deploy web normal y un release desde `main`. Después
se retira `smartpegas1.0` de la policy de `Production`, de los triggers y del
texto transicional; se conserva el tag de respaldo; borrar la rama es una
decisión aparte.

### 0.4 Rollback

No se mueve `main` hacia atrás nunca. Un problema del ERP web se resuelve con
el rollback de release de Firebase Hosting o con un forward-fix desde `main`;
un problema de release de escritorio no puede ocurrir porque ningún job de
publicación se dispara por push. Todo lo demás de la sección 16 sigue vigente.

### 0.5 Lo que el dueño hace con sus manos

1. Aprobar la PR de preparación (paso 0) o dejar que el agente la fusione.
2. Mirar la PR `smartpegas1.0 → main` que abre el agente y pulsar «Merge pull
   request» → «Create a merge commit».
3. Abrir `project-vinabike.web.app`, iniciar sesión y mirar tres pantallas.

Todo lo demás lo ejecuta y verifica el agente desde el Mac. Las PR abiertas de
Dependabot contra `main` se rebasan solas al moverse la base.

## 1. Propósito

Este runbook convierte `main` en la única línea canónica del proyecto sin
mezclar en el árbol final el contenido antiguo de `main`.

El resultado obligatorio es:

```text
F = último commit limpio, completo y aprobado de smartpegas1.0
N = punta de main inmediatamente antes del cutover
M = commit puente que conecta F con N sin cambiar el árbol de F
T = merge de prueba sintético que GitHub calcula para la PR con base N y head M
P = commit que GitHub deja en main al fusionar la PR

tree(M) = tree(F)
tree(T) = tree(M) = tree(F)
tree(P) = tree(M) = tree(F)
F y N son ancestros de P
origin/main = origin/smartpegas1.0 = P al cerrar la operación
```

El contenido viejo de `main` queda conservado solo como historia auditable. No
queda incorporado al checkout, al build ni al producto final.

Este documento no autoriza por sí mismo ningún commit, push, merge, cambio de
protección, ejecución de workflow, deploy, release ni escritura en producción.
Cada acción remota requiere autorización explícita del dueño durante la ventana
de ejecución.

## 2. Fuera de alcance

- No resolver funcionalmente los conflictos con el código viejo de `main`.
- No usar `force-push`, rebase, squash, `reset`, `stash` ni `git clean`.
- No desproteger `main` ni usar bypass administrativo.
- No publicar actualizaciones de macOS, Windows o Android durante el cutover.
- No ejecutar migraciones, reparaciones ni escrituras de negocio en Supabase
  durante este runbook. Si el publisher durable requiere una migración, debe
  haberse desplegado y verificado en una tarea separada y autorizada antes de
  fijar `F`.
- La única excepción durante la ventana son las escrituras acotadas del ledger
  y de su control canónico de activación/desactivación que forman parte de una
  publicación durable expresamente autorizada; deben seguir el contrato de
  base de datos y sus propios owners, nunca SQL ad hoc.
- No desplegar Cloudflare Worker u otros servicios manuales.
- No borrar `smartpegas1.0` durante esta operación.
- No limpiar o descartar trabajo local sin una clasificación explícita.

## 3. Autoridades relacionadas

Este runbook ejecuta la fase de rama canónica de
[Engineering environment and repository cleanup plan](../development/ENGINEERING_ENVIRONMENT_AND_REPOSITORY_CLEANUP_PLAN.md)
y no reemplaza las políticas existentes:

- [Releases](../development/RELEASES.md)
- [Production incident runbook](PRODUCTION_INCIDENT.md)
- [Repository structure](../development/REPOSITORY_STRUCTURE.md)
- [macOS desktop distribution](../MACOS_DESKTOP_DISTRIBUTION.md)
- [Windows desktop distribution](../WINDOWS_DESKTOP_DISTRIBUTION.md)
- [Android direct distribution](../ANDROID_DIRECT_DISTRIBUTION.md)
- [Codex/Claude collaboration](../development/CODEX_CLAUDE_COLLABORATION.md)
- [Agent database contract](../development/AGENT_DATABASE_CONTRACT.md)
- [Repository agent instructions](../../.github/copilot-instructions.md)

Si una verificación de producción o de base de datos falla, prevalecen esos
runbooks especializados.

## 4. Línea base observada al diseñar el plan

Esta tabla es evidencia fechada, no una entrada válida para ejecutar. Todos los
valores deben volver a consultarse en la ventana real.

| Superficie | Estado observado el 2026-07-29 |
| --- | --- |
| Rama predeterminada | `main` |
| `origin/main` | `7f87d3afdc6ce564f68d281fe199f3a0a8558f6f` |
| `origin/smartpegas1.0` | `32404d36bcae026a1560cf0080f85f6ac7cdf157` |
| Divergencia | `main`: 1 commit exclusivo; `smartpegas1.0`: 596 |
| Contenido exclusivo de `main` | Un shim de 22 líneas en `.github/workflows/macos-release.yml` |
| PR de promoción | PR #2, `smartpegas1.0 → main`, abierta y conflictiva |
| Protección | `main` protegida; `smartpegas1.0` sin protección |
| Actualización estricta | `required_status_checks.strict=true` en `main` |
| Conversaciones | `required_conversation_resolution=true` en `main` |
| Check requerido obsoleto | Se exige `integrity / Database and application regression gate`, pero el workflow produce `integrity / Application regression gate` |
| Eliminación automática de head branch | Desactivada (`delete_branch_on_merge=false`) |
| Workflows visibles | 3 en `main`; 9 en `smartpegas1.0` |
| Environment `Production` | Autoriza `main` y `smartpegas1.0`; sin reviewer ni espera |
| Última release | `macos-v1.0.3-40`, ligada a `32404d36…` |
| Tienda pública | `release.json` apunta a `32404d36…`, `source: manual-shell`, `dirty: true` |
| ERP web | `/release.json` devuelve el HTML de la tienda, no evidencia ERP válida |
| Integraciones externas | Deployments del environment GitHub `Preview` creados por `vercel[bot]`; último observado el 2026-07-13. Hay cero webhooks clásicos, pero la GitHub App debe revalidarse |
| Checkout compartido | Sucio y cambiando activamente; no apto para cutover |
| Actions activas | Ninguna al momento de la consulta remota |

Dos consecuencias son bloqueantes:

1. “Todo el proyecto” significa el árbol **commiteado** de `F`. Los archivos
   modificados o sin seguimiento no forman parte de una rama y se perderían de
   la promoción si no se clasifican y aterrizan primero.
2. Un build limpio de la tienda puede diferir del build `dirty: true` que hoy
   está público. No se debe reemplazarlo hasta demostrar que todo cambio
   intencional de ese build está incluido en `F`.

## 5. Decisiones de diseño adoptadas

### 5.1 Preservar historia sin preservar el árbol viejo

La ruta gobernada es:

1. Crear desde `F` un merge especial que reconozca a `N` como segundo padre,
   pero conserve exactamente el árbol de `F`.
2. Avanzar `smartpegas1.0` de `F` a ese puente `M` mediante fast-forward.
3. Confirmar que la PR tiene head `M`, validar su merge de prueba `T` y esperar
   los checks requeridos de la PR.
4. Fusionar la PR con merge commit, sin bypass.
5. Verificar que el árbol promovido `P` siga siendo idéntico a `F`.
6. Solo después de verificar producción, avanzar `smartpegas1.0` a `P`.

La dirección es crítica:

```text
M^1 = F
M^2 = N
tree(M) = tree(F)
```

El puente se crea estando sobre `F` e incorporando `N` con la estrategia
`ours`. Hacerlo desde `main` conservaría el árbol antiguo y sería catastrófico.
`-s ours` tampoco debe confundirse con `-X ours`: la segunda opción todavía
intenta mezclar archivos.

### 5.2 Mantener la protección y la PR

No se hará un push administrativo directo a `main`. Antes del merge se
actualizará únicamente el contexto requerido obsoleto, conservando todas las
demás reglas. La PR debe quedar mergeable por sus propios checks.

### 5.3 Congelar deploys automáticos y promoverlos de forma secuencial

El push que crea `P` coincide con filtros de ERP, tienda, macOS, Windows y
secret scan. macOS y Windows son artifact-only en un push, pero ERP y tienda sí
publican en Firebase.

La opción de menor riesgo exige aterrizar antes en `smartpegas1.0` controles
permanentes de emergencia, sin reemplazar el contrato canónico de publicación
que termine formando parte de `F`:

- variable de repositorio `VINABIKE_PRODUCTION_DEPLOY_FREEZE`;
- variable de repositorio
  `VINABIKE_PRODUCTION_MANUAL_DEPLOY_AUTHORIZATION`, cuyo único valor habilitante
  es exactamente `<target>:<sha>` y cuyo estado normal es `disabled`;
- ruta manual ligada a un SHA exacto para ERP y tienda;
- source guard que demuestre que el SHA solicitado coincide con `github.sha`;
- separación clara entre build/evidence y deploy/readback, con el job de deploy
  dependiente del source guard y del build;
- condición fail-closed: en un push solo se permite deploy cuando la variable
  existe y vale exactamente `false`; ausente, `true` o cualquier valor inválido
  significa no desplegar;
- condición manual también fail-closed: durante el freeze solo se permite el
  target cuyo valor sea exactamente `erp:<github.sha>` o
  `store:<github.sha>`; ausente, `disabled`, otro target u otro SHA significa
  no desplegar;
- filtro de paths razonable para que un cambio solo documental no despliegue el
  ERP;
- pruebas estáticas que fallen si el freeze o la vinculación de SHA se rompen.

Para ERP, la interfaz propuesta puede usar `expected_commit` y una confirmación
booleana explícita durante el freeze. Para tienda, la interfaz se decide a
partir del árbol final:

- si el publisher simple sigue siendo canónico, debe ofrecer una vinculación
  equivalente a `expected_commit`;
- si aterriza el publisher durable actualmente en desarrollo, se conserva su
  input único `request_id`. En ese protocolo, `R=requested_revision` es la
  revisión numérica positiva y monotónica del contenido/owner; **no** es un SHA
  ni se compara con `P`. El paso `begin` debe ligar por separado el commit Git
  ejecutado `P` mediante `github.sha`/`p_github_sha`, y `release.json.commit`
  también debe resultar `P`. Sus pasos `begin/seal/complete` siguen siendo los
  únicos owners del intento. Antes de fijar `F`, el contrato debe incorporar
  una operación canónica, autorizada e idealmente atómica que habilite el
  dispatch y encole/coalesca la revisión actual, devolviendo `request_id` y
  `R`; también debe incorporar su desactivación canónica. No se agregan inputs
  paralelos, no se usa SQL ad hoc y no se exige nunca `R=P`. El guard
  `store:<github.sha>` debe ejecutarse antes de que `begin` escriba o reclame
  el intento.

El freeze se activa antes de fusionar a `main`. Una vez que `P` esté validado
como objeto Git, se despacha ERP y luego tienda, nunca ambos a la vez. Al cerrar
las verificaciones se devuelve la autorización manual a `disabled` y se cambia
el freeze a `false`; cambiar una variable no genera otro push ni otro deploy.
En modo Git-only, la autorización manual permanece `disabled`, y el
`dispatch_enabled` del publisher durable permanece `false`: el freeze por sí
solo no basta para impedir rutas manuales.

Si este control no ha sido implementado y probado, el plan de mínimo riesgo
queda bloqueado. Aceptar dos deploys productivos simultáneos requiere una
decisión de riesgo separada; no es el camino predeterminado de este runbook.

### 5.4 No publicar instaladores

Los workflows macOS y Windows pueden compilar artefactos por el push a `main`,
pero `publish_release` debe permanecer en `false`. Android no se dispara por
push. Durante la ventana:

- no se usan las tareas `Publish ... Update`;
- no se despacha ningún workflow con `publish_release=true`;
- no se crean ni mueven tags de release; las únicas excepciones son los dos
  tags forenses `cutover-backup/*` definidos en 10.4;
- no se reutiliza ningún prepared state anterior: está ligado a otro SHA.

## 6. Alternativas rechazadas

| Alternativa | Motivo de rechazo |
| --- | --- |
| Force-push de `smartpegas1.0` sobre `main` | Reescribe historia, exige debilitar protección y aumenta el costo de recuperación. |
| Merge normal resolviendo conflictos | Puede incorporar silenciosamente contenido viejo que el dueño no quiere. |
| `git merge -X ours` | Resuelve conflictos a favor de una rama, pero todavía mezcla archivos no conflictivos. |
| Crear el merge `-s ours` desde `main` | El árbol resultante sería el `main` viejo. |
| Squash o rebase | Rompe la ancestría utilizada por releases y reduce auditabilidad. |
| Push directo de admin de un commit fabricado | Omite PR, checks requeridos y la gobernanza que se quiere establecer. |
| Dejar que ERP y tienda desplieguen juntos | Duplica el radio de impacto y complica diagnóstico y rollback. |
| Borrar `smartpegas1.0` al fusionar | Elimina demasiado pronto una referencia operativa y forense útil. |
| Volver `main` a `N` después del cutover | Restauraría el proyecto viejo y volvería a disparar su workflow peligroso. |

## 7. Registro de riesgos

| Riesgo | Control obligatorio |
| --- | --- |
| Promover trabajo incompleto | Clasificar todo el WIP y definir un `F` limpio, remoto y estable. |
| Regresión de la tienda actualmente `dirty: true` | Comparar el build limpio candidato con el comportamiento público y aterrizar todos los cambios intencionales antes del cutover. |
| Conservar el árbol equivocado | Validar padres y hashes de árbol de `M` antes de cualquier push. |
| Carrera con otro agente o desarrollador | Freeze humano, dos lecturas consecutivas estables y `ls-remote` inmediatamente antes de cada mutación. |
| Bypass accidental de protección | Usar PR merge, no `--admin`, no push directo a `main`. |
| Check requerido inexistente | Corregir solo el contexto obsoleto y reconsultar la protección completa. |
| Dos deploys web simultáneos | Freeze de workflow y dispatch secuencial ligado a `P`. |
| Fallo después de que Firebase ya publicó | Conservar identificadores de releases previas y restaurar por target; corregir Git hacia adelante. |
| Publicación accidental de instaladores | Mantener `publish_release=false` y comprobar tags/releases antes y después. |
| Activación de automatizaciones nuevas | Inventariar Dependabot y Technology Radar y observar su primer ciclo. |
| Deploy externo a GitHub Actions | Inventariar Vercel, GitHub Apps, webhooks y cualquier integración que reaccione a `main`; congelarla o demostrar que es inerte. |
| Reutilización de handoff de release viejo | Invalidar todo estado preparado anterior y regenerarlo desde el próximo SHA real. |
| Eliminación o avance accidental de `smartpegas1.0` | No usar `--delete-branch`; alinear y luego proteger/bloquear la rama. |
| Mutación accidental de datos | Prohibir migraciones, reparaciones y escrituras ad hoc; permitir únicamente el ledger/control canónico de una publicación durable autorizada y ejecutar el resto de verificaciones en lectura. |
| Rollback destructivo | Nunca revertir el merge completo ni mover refs hacia atrás; rollback de hosting o forward-fix. |

## 8. Roles y autorizaciones

Antes de reservar la ventana deben quedar registrados:

| Rol | Persona | Responsabilidad |
| --- | --- | --- |
| Dueño del cambio |  | Autoriza freeze, configuración GitHub, merge y deploys. |
| Operador |  | Ejecuta un paso a la vez y registra salidas. |
| Verificador independiente |  | Comprueba SHAs, árboles, checks y producción antes de continuar. |
| Observador de producción |  | Ejecuta smokes y decide rollback por target. |

Una misma persona puede ocupar más de un rol, pero ninguna mutación de `main` o
producción se ejecuta sin lectura en voz alta de la condición de éxito y de
aborto del paso.

## 9. Fase 0 — Preparar el candidato final `F`

Esta fase ocurre en `smartpegas1.0`, antes de la ventana de cutover.

### 9.1 Detener trabajo concurrente

- Pausar agentes, editores que escriban archivos, publicadores, deploy helpers y
  release tasks.
- Inventariar procesos Flutter, Firebase, GitHub CLI y scripts de publicación.
- Ejecutar `git worktree list --porcelain`, inventariar cada checkout y
  confirmar que ninguno escribe, publica ni tiene `main` o `smartpegas1.0` como
  rama activa durante la ventana. No crear otro worktree para el cutover.
- No matar procesos automáticamente; recuperar su control y cerrarlos de forma
  deliberada.
- Confirmar que no existe `.git/index.lock`.

### 9.2 Clasificar el árbol sucio

Cada ruta modificada o sin seguimiento debe quedar en una de estas categorías:

1. **Producto intencional:** revisar, probar y commitear.
2. **Generado canónico:** reproducir con su owner y commitear solo si la política
   del repositorio lo exige.
3. **Local/temporal/secreto:** excluir mediante su política; nunca commitear.
4. **Cambio concurrente no terminado:** terminarlo o posponer todo el cutover.

No se permite “guardar para después” mediante `stash`, limpiar por patrón o
descartar en masa. Al finalizar:

```bash
git status --porcelain=v1
```

debe producir salida vacía y mantenerse vacía en dos lecturas separadas.

Los documentos de gobernanza que este runbook enlaza deben clasificarse
explícitamente como producto intencional y formar parte de `F`, incluido este
archivo, `CLAUDE.md`, `docs/development/CODEX_CLAUDE_COLLABORATION.md` y
`docs/development/AGENT_DATABASE_CONTRACT.md`. No basta con que existan como
archivos locales sin seguimiento.

### 9.3 Aterrizar los controles de transición

Preparar y revisar en `smartpegas1.0`:

- freeze y dispatch exact-SHA de ERP/tienda descritos en 5.3, con cambios
  explícitos en `.github/workflows/firebase-hosting-merge.yml`,
  `.github/workflows/firebase-hosting-store.yml` y sus tests;
- primer `workflow_dispatch` seguro del workflow ERP;
- trigger de `erp-integrity-gate.yml` válido para `main` y, durante la
  observación, también para `smartpegas1.0`;
- contexto de branch canónica que no declare `main` antes de tiempo: la
  instrucción puede cambiar de `smartpegas1.0` a `main` solo cuando la versión
  nueva de esa instrucción ya exista en `origin/main`;
- inventario de referencias operativas a `smartpegas1.0` en `.github`,
  `.vscode`, `scripts`, tests y documentos de distribución;
- confirmación de que los publicadores calculan rama/SHA en vivo y no dependen
  de un prepared state anterior.

El checkout observado durante el diseño contiene trabajo concurrente que cambia
`firebase-hosting-store.yml` a un protocolo durable con `request_id` y
`storefront_publication_workflow.mjs`, incluido un ledger en Supabase. Su dueño
debe decidir y terminar ese trabajo antes de fijar `F`. Este runbook no puede
sobrescribirlo ni asumir simultáneamente la interfaz antigua y la nueva.

Si el protocolo durable entra en `F`:

- completar su migración, revisión y autorización en una tarea separada antes de
  fijar `F`; este runbook solo verifica su presencia y estado, no la ejecuta;
- ejecutar sus tests sin escribir en producción;
- confirmar que `requested_revision` es una revisión numérica del owner y que
  `p_github_sha` liga por separado la ejecución al SHA exacto;
- definir, autorizar y probar una operación canónica que active el dispatch y
  encole/coalesca la revisión corriente en una sola transición segura,
  devolviendo `request_id` y `requested_revision`; debe existir también una
  desactivación canónica. Cambiar la tabla directamente no es aceptable;
- comprobar estáticamente y por test que el guard
  `store:<github.sha>` ocurre antes de `begin`;
- adaptar el freeze solo al camino automático de `push`, sin romper
  `begin/seal/complete` ni la finalización de fallos;
- documentar y autorizar las escrituras de ledger/control de la fase 14.2.

Si no entra en `F`, el dueño de ese cambio debe retirarlo o posponerlo en una
tarea separada y dejar el árbol limpio. El cutover nunca descarta ese WIP.

Las referencias históricas pueden conservarse. Las referencias operativas
deben quedar explícitamente transicionales o apuntar a `main` después del
cutover.

### 9.4 Gates del candidato

Ejecutar desde un checkout limpio y registrar:

- secret scan con redacción;
- tests de helpers de release;
- generación reproducible de assets empaquetados;
- analyzer;
- suite Flutter completa;
- build ERP web;
- build storefront y presupuesto de bundle;
- validación de los nuevos contratos de workflow/freeze;
- preview real de la PR según `RELEASES.md`; si el preview está suspendido,
  restaurarlo o registrar antes de la ventana una excepción explícita,
  autorizada y con una validación efímera equivalente. El check actual
  `PR Integrity` por sí solo no es un preview;
- health/invariants de producción en modo solo lectura.

La autoridad concreta sigue siendo el integrity gate del repositorio. Cualquier
fallo bloquea la transición; no se separa como “no relacionado” si afecta el
árbol completo que se pretende promover.

### 9.5 Resolver la diferencia entre Git y producción

Antes de fijar `F`:

- reconstruir de forma limpia la tienda desde el candidato;
- comparar rutas críticas, navegación, imágenes, SEO, checkout y
  `release.json` con `vinabike.cl`;
- demostrar que todo comportamiento intencional del build `dirty: true` está
  contenido en commits;
- identificar qué sirve actualmente el target ERP y acordar que su primer
  deploy endurecido es un cambio productivo intencional;
- registrar una release Firebase previa realmente restaurable para cada target,
  con identificador, hashes/readback y smoke del baseline;
- si no existe una restauración ERP verificable, bloquear el deploy ERP. El
  dueño debe posponer todo el cutover o elegir explícitamente el modo Git-only
  definido en 10.1 y dejar producción congelada.

Solo entonces:

```text
F = origin/smartpegas1.0
```

se congela como el candidato completo.

## 10. Fase 1 — Preflight y freeze de la ventana

### 10.1 Condiciones Go/No-Go

Todas deben ser verdaderas:

- [ ] Autorización explícita del dueño y ventana comunicada.
- [ ] Modo elegido: **completo** (Git + deploys secuenciales) o **Git-only**
      (producción permanece congelada y se promueve en una tarea posterior).
- [ ] Cero escritores, publicadores y deploys activos.
- [ ] Todos los worktrees y procesos están inventariados; ninguno escribe,
      publica ni tiene `main`/`smartpegas1.0` como rama activa.
- [ ] Checkout limpio; local `HEAD` = remoto `smartpegas1.0`.
- [ ] `F` pasó el gate completo.
- [ ] Build limpio de tienda aceptado frente al público actual.
- [ ] Freeze de deploy implementado, probado y disponible en `F`.
- [ ] Contrato final de publicación de tienda —simple o durable— decidido,
      probado y ligado a un SHA exacto.
- [ ] Si el contrato durable aterrizó, sus migraciones están verificadas y sus
      escrituras de ledger/control fueron autorizadas para la fase de
      publicación; sus operaciones canónicas de activación+encolado y
      desactivación están probadas.
- [ ] La PR tiene integrity y preview reales, o una excepción de preview
      explícita, autorizada y acompañada por evidencia equivalente.
- [ ] En modo completo, releases previas ERP/tienda demostradas restaurables
      con evidencia y smoke; “aparece en el historial” no basta.
- [ ] Backups y smokes preparados.
- [ ] PR #2 sigue siendo `smartpegas1.0 → main`, o se ha autorizado una PR nueva.
- [ ] `main` continúa protegida y permite merge commits.
- [ ] `required_status_checks.strict=true`; GitHub exige que la PR esté
      actualizada con la punta vigente de `main`.
- [ ] `required_conversation_resolution=true` y todas las conversaciones de la
      PR están resueltas.
- [ ] Rulesets y merge queue fueron reconsultados y no cambian la semántica del
      merge commit explícito.
- [ ] Ningún SHA remoto cambió desde el inicio del freeze.
- [ ] Las URLs fetch/push de `origin` y la identidad de `gh` resuelven
      exactamente a `Ccatalan7/bikeshop-erp`, default branch `main`.
- [ ] No hay workflows queued/running/waiting.
- [ ] Todos los documentos/enlaces de la sección 3 existen dentro del árbol de
      `F`, no solo en el checkout local.
- [ ] Vercel y cualquier GitHub App, webhook o integración externa que escuche
      pushes/merges a `main` está inventariada y congelada o demostrada inerte.
- [ ] Production autoriza `main`.
- [ ] No hay release de macOS/Windows/Android planificada en la misma ventana.
- [ ] Operador y verificador entienden que no existe rollback de Git hacia `N`.

Una sola casilla falsa significa **NO-GO**.

### 10.2 Capturar variables nuevas

No reutilizar los SHAs de la sección 4:

```bash
set -euo pipefail

CUTOVER_REPO="Ccatalan7/bikeshop-erp"
CUTOVER_PR="2"
CUTOVER_WINDOW_ID="$(date -u +%Y%m%dT%H%M%SZ)"

git remote get-url origin
git remote get-url --push origin
gh repo view "$CUTOVER_REPO" \
  --json nameWithOwner,defaultBranchRef \
  --jq '[.nameWithOwner,.defaultBranchRef.name] | @tsv'

CUTOVER_MAIN_OLD="$(
  git ls-remote --exit-code origin refs/heads/main | awk '{print $1}'
)"
CUTOVER_SMART_FINAL="$(
  git ls-remote --exit-code origin refs/heads/smartpegas1.0 | awk '{print $1}'
)"
```

Las tres primeras salidas deben identificar el repositorio esperado, mediante
URL HTTPS o SSH canónica, y producir `Ccatalan7/bikeshop-erp<TAB>main`. Cualquier
remote alternativo bloquea la ventana.

Guardar las variables en el registro de ejecución. Luego:

```bash
git fetch --prune origin main smartpegas1.0

test "$(git rev-parse origin/main)" = "$CUTOVER_MAIN_OLD"
test "$(git rev-parse origin/smartpegas1.0)" = "$CUTOVER_SMART_FINAL"
test -z "$(git status --porcelain=v1)"

test "$(
  git rev-list --count origin/smartpegas1.0..origin/main
)" = "1"

test "$(
  git diff --name-only \
    "$(git merge-base origin/main origin/smartpegas1.0)" \
    origin/main
)" = ".github/workflows/macos-release.yml"
```

Revisar nuevamente los commits exclusivos de `main`. Si ya no corresponden
exactamente al baseline auditado, detenerse y rediseñar; no adaptar el comando
en caliente.

### 10.3 Capturar configuración y evidencia

Guardar fuera del árbol versionado:

- configuración completa de protección de `main`;
- contextos requeridos;
- settings de merge y `delete_branch_on_merge`;
- rulesets del repositorio y configuración/estado de merge queue;
- policy del environment `Production`;
- lista/estado de workflows;
- GitHub Apps, webhooks, checks y deployments externos a Actions, incluido
  cualquier vínculo con Vercel;
- para Vercel, consultar específicamente los deployments del environment
  GitHub `Preview` y las GitHub Apps instaladas, no inferir ausencia desde la
  lista vacía de webhooks; registrar la fecha del último deployment y decidir
  con evidencia si la integración está activa, dormida o retirada;
- runs activos;
- deployments GitHub y Firebase vigentes;
- `release.json` y hashes de ERP/tienda;
- última release y manifests de macOS, Windows y Android;
- estado de PR #2 y su head SHA.

No guardar tokens, valores de secrets ni logs crudos dentro del repositorio.

### 10.4 Crear referencias de respaldo

Crear dos tags anotados, únicos y fechados, que no se moverán:

```bash
CUTOVER_MAIN_BACKUP="cutover-backup/main-before-$CUTOVER_WINDOW_ID"
CUTOVER_SMART_BACKUP="cutover-backup/smart-before-$CUTOVER_WINDOW_ID"

git tag --annotate \
  --message "main before canonical cutover $CUTOVER_WINDOW_ID" \
  "$CUTOVER_MAIN_BACKUP" "$CUTOVER_MAIN_OLD"
git tag --annotate \
  --message "smart before canonical cutover $CUTOVER_WINDOW_ID" \
  "$CUTOVER_SMART_BACKUP" "$CUTOVER_SMART_FINAL"

git push --atomic origin \
  "refs/tags/$CUTOVER_MAIN_BACKUP" \
  "refs/tags/$CUTOVER_SMART_BACKUP"
```

Apuntan a `N` y `F`, respectivamente. Verificar sus objetos local y remotamente.
Los tags son evidencia forense, no autorización para volver `main` hacia atrás.

### 10.5 Activar freeze productivo

La variable no existe en el baseline observado. El dueño debe autorizar su
creación y activación:

```bash
gh variable set VINABIKE_PRODUCTION_DEPLOY_FREEZE \
  --repo "$CUTOVER_REPO" \
  --body "true"

gh variable set VINABIKE_PRODUCTION_MANUAL_DEPLOY_AUTHORIZATION \
  --repo "$CUTOVER_REPO" \
  --body "disabled"

test "$(
  gh variable get VINABIKE_PRODUCTION_DEPLOY_FREEZE \
    --repo "$CUTOVER_REPO" \
    --json value \
    --jq .value
)" = "true"

test "$(
  gh variable get VINABIKE_PRODUCTION_MANUAL_DEPLOY_AUTHORIZATION \
    --repo "$CUTOVER_REPO" \
    --json value \
    --jq .value
)" = "disabled"
```

No continuar si el workflow contenido en `F` no demuestra que un push a `main`
omitirá ambos jobs de deploy cuando el freeze sea `true`, ausente o inválido, y
que ninguna ruta manual puede desplegar con autorización `disabled`.

## 11. Fase 2 — Crear y validar el puente `M`

Usar una rama local temporal y única en el mismo checkout; no crear otro
worktree:

```bash
CUTOVER_LOCAL_BRANCH="codex/main-cutover-bridge-$CUTOVER_WINDOW_ID"
git switch --create "$CUTOVER_LOCAL_BRANCH" \
  "$CUTOVER_SMART_FINAL"
git merge --no-ff --no-commit -s ours "$CUTOVER_MAIN_OLD"
```

Antes del commit:

```bash
test "$(git rev-parse MERGE_HEAD)" = "$CUTOVER_MAIN_OLD"
git diff --cached --exit-code "$CUTOVER_SMART_FINAL" --
git diff --exit-code "$CUTOVER_SMART_FINAL" --
```

Si alguna comparación muestra contenido, ejecutar `git merge --abort` y
detenerse.

Crear el commit:

```bash
git commit -m "merge: connect legacy main history before canonical promotion"
CUTOVER_BRIDGE="$(git rev-parse HEAD)"
test -z "$(git status --porcelain=v1)"
```

Validar todos los invariantes:

```bash
test "$(git show -s --format=%P "$CUTOVER_BRIDGE")" = \
  "$CUTOVER_SMART_FINAL $CUTOVER_MAIN_OLD"

test "$(git rev-parse "$CUTOVER_BRIDGE^{tree}")" = \
  "$(git rev-parse "$CUTOVER_SMART_FINAL^{tree}")"

git diff --exit-code "$CUTOVER_SMART_FINAL" "$CUTOVER_BRIDGE" --
git merge-base --is-ancestor "$CUTOVER_SMART_FINAL" "$CUTOVER_BRIDGE"
git merge-base --is-ancestor "$CUTOVER_MAIN_OLD" "$CUTOVER_BRIDGE"
```

El verificador independiente debe repetir estas consultas. `M` no se publica si
falla una sola.

## 12. Fase 3 — Avanzar la PR sin tocar `main`

Releer la punta remota inmediatamente antes del push:

```bash
test "$(
  git ls-remote --exit-code origin refs/heads/smartpegas1.0 |
    awk '{print $1}'
)" = "$CUTOVER_SMART_FINAL"

git push origin \
  "${CUTOVER_BRIDGE}:refs/heads/smartpegas1.0"
```

Este push debe ser fast-forward. Si Git lo rechaza, no forzar: otra actividad
rompió el freeze.

Comprobar:

- la PR usa exactamente `CUTOVER_BRIDGE` como head;
- el árbol mostrado por GitHub es el esperado;
- `main` no cambió;
- no hubo deploy web por este push.

Esperar hasta que GitHub cambie `mergeable` de `CONFLICTING` a `MERGEABLE` y
`mergeStateStatus` deje de ser `DIRTY`. Puede permanecer `BLOCKED` mientras se
reparan checks requeridos o conversaciones; debe llegar a `CLEAN` en 12.1:

```bash
gh pr view "$CUTOVER_PR" \
  --repo "$CUTOVER_REPO" \
  --json headRefOid,mergeable,mergeStateStatus
```

Capturar y validar el merge de prueba sintético:

```bash
git fetch origin "refs/pull/${CUTOVER_PR}/merge"
CUTOVER_TEST_MERGE="$(git rev-parse FETCH_HEAD)"

test "$(git show -s --format=%P "$CUTOVER_TEST_MERGE")" = \
  "$CUTOVER_MAIN_OLD $CUTOVER_BRIDGE"

test "$(git rev-parse "$CUTOVER_TEST_MERGE^{tree}")" = \
  "$(git rev-parse "$CUTOVER_SMART_FINAL^{tree}")"

git diff --exit-code "$CUTOVER_SMART_FINAL" "$CUTOVER_TEST_MERGE" --
```

Los workflows `pull_request` ejecutan el merge de prueba `T` como
`GITHUB_SHA`, aunque GitHub puede adjuntar el check-run al head `M`. GitHub
puede considerar satisfecho un contexto requerido con un check-run del mismo
nombre sobre `M` originado por `push`. Por eso, no basta con la marca verde: el
verificador debe abrir el run, confirmar `event=pull_request`,
`GITHUB_SHA=T` y registrar ambas identidades. Esta obligación del runbook evita
aceptar como sustituto el check de `push`. La evidencia debe incluir el preview
exigido por `RELEASES.md` o la excepción equivalente aprobada en 10.1.

Esperar los checks:

```bash
gh pr checks "$CUTOVER_PR" \
  --repo "$CUTOVER_REPO" \
  --watch
```

### 12.1 Reparar el required check obsoleto

Con los required checks de la PR visibles y `T` registrado:

1. Exportar la protección completa.
2. Sustituir únicamente el contexto obsoleto por el nombre exacto producido.
3. Revisar el diff del payload con otra persona.
4. Usar la superficie estrecha
   `PATCH /repos/{owner}/{repo}/branches/main/protection/required_status_checks`,
   conservando `strict=true`, Secret Scan y todos los contextos/checks válidos.
   Sustituir solo el contexto obsoleto.
5. Releer la configuración desde GitHub.
6. Confirmar `MERGEABLE/CLEAN`, conversaciones resueltas y merge posible sin
   `--admin`.

No aplicar un payload parcial que pueda resetear otras opciones de protección.

## 13. Fase 4 — Promover a `main` con producción congelada

Último Go/No-Go:

- `origin/main = N`;
- head de PR = `M`;
- merge de prueba `T` validado y checks requeridos de la PR verdes;
- `required_status_checks.strict=true`;
- `required_conversation_resolution=true` y cero conversaciones pendientes;
- deploy freeze = `true`;
- cero Actions activas salvo checks esperados ya terminados;
- backups verificados;
- smokes y rollback listos.

Releer la base remota inmediatamente antes de enviar el merge:

```bash
test "$(
  git ls-remote --exit-code origin refs/heads/main | awk '{print $1}'
)" = "$CUTOVER_MAIN_OLD"
```

Si `main` se movió, detenerse. `--match-head-commit` protege el head de la PR,
no sustituye esta comprobación de la base ni el modo estricto de protección.

Fusionar:

```bash
gh pr merge "$CUTOVER_PR" \
  --repo "$CUTOVER_REPO" \
  --merge \
  --match-head-commit "$CUTOVER_BRIDGE"
```

No usar `--admin` ni `--delete-branch`.

Capturar el nuevo commit:

```bash
git fetch origin main smartpegas1.0
CUTOVER_PROMOTED="$(git rev-parse origin/main)"
```

Validar antes de desplegar:

```bash
git merge-base --is-ancestor "$CUTOVER_MAIN_OLD" "$CUTOVER_PROMOTED"
git merge-base --is-ancestor "$CUTOVER_BRIDGE" "$CUTOVER_PROMOTED"

test "$(git rev-parse "$CUTOVER_PROMOTED^{tree}")" = \
  "$(git rev-parse "$CUTOVER_SMART_FINAL^{tree}")"

git diff --exit-code "$CUTOVER_SMART_FINAL" "$CUTOVER_PROMOTED" --
```

Además:

- todos los workflows presentes en el árbol de `F` deben quedar registrados
  desde `main`, con el número exacto capturado en 10.3;
- ERP/tienda pueden tener runs, pero sus jobs de deploy deben estar skipped por
  el freeze;
- todos los runs asociados a `P` —ERP, tienda, integrity, Secret Scan y gates
  macOS/Windows— deben llegar a estado terminal antes del primer dispatch
  productivo; una excepción explícita debe justificar cualquier gate
  independiente que siga activo;
- Secret Scan debe quedar verde;
- macOS/Windows pueden ejecutar gates artifact-only;
- no debe existir un tag, release o actualización de coworker nueva;
- no debe existir un deployment inesperado de Vercel u otra integración
  externa;
- `smartpegas1.0` debe seguir existiendo.

Si un deploy web se inició automáticamente, detener la secuencia y activar el
runbook de incidente. No despachar el segundo target.

## 14. Fase 5 — Desplegar el mismo SHA, un target a la vez

Esta fase requiere autorización separada y solo se ejecuta en modo completo.
En modo Git-only se omite entera: producción conserva su última release, el
freeze permanece en `true` y se abre una tarea de promoción posterior con
rollback verificable. No se presenta Git-only como despliegue terminado.

Los dos workflows deben ejecutar desde `main`, ligados a
`CUTOVER_PROMOTED`. La interfaz exacta registrada en `F` manda; no se inventan
inputs durante la ventana.

### 14.1 ERP

1. Cambiar temporalmente la autorización manual a
   `erp:<valor de CUTOVER_PROMOTED>` y releerla.
2. Despachar manualmente `firebase-hosting-merge.yml`.
3. Elegir `ref=main`.
4. Introducir `expected_commit=CUTOVER_PROMOTED`.
5. Confirmar explícitamente el deploy durante freeze.
6. Comprobar que el run usa exactamente ese head SHA.
7. Esperar `integrity → build → deploy → live verify → db health`.
8. Devolver inmediatamente la autorización manual a `disabled` y releerla.

Éxito mínimo:

- workflow verde;
- deployment de target ERP verde;
- `https://project-vinabike.web.app/release.json` es JSON ERP;
- `.commit == CUTOVER_PROMOTED`;
- health/invariants de producción verdes;
- login y rutas ERP críticas pasan smoke.

Si falla, no desplegar tienda. Si Firebase ya publicó, restaurar la release ERP
previa identificada y verificarla; mantener `main` en `P` y corregir hacia
adelante.

### 14.2 Tienda

Solo después de cerrar ERP:

1. Confirmar cuál interfaz de tienda contiene `CUTOVER_PROMOTED`.
2. Cambiar temporalmente la autorización manual a
   `store:<valor de CUTOVER_PROMOTED>` y releerla.
3. Si es simple, usar su input exact-SHA y confirmación de freeze.
4. Si es durable:
   - invocar la operación canónica de activación+encolado que quedó probada en
     `F`, nunca SQL ad hoc;
   - capturar de su respuesta `request_id` y
     `R=requested_revision`, y comprobar que `R` es el entero positivo esperado
     del owner, sin compararlo con el SHA;
   - permitir que el dispatcher/workflow canónico ejecute
     `begin → seal → deploy → verify → complete`;
   - comprobar que el guard exacto
     `store:<github.sha>` pasó **antes** de `begin` y que `begin` registró
     `p_github_sha=CUTOVER_PROMOTED`;
   - tratar cualquier `finalize-failure` como evidencia de publicación fallida,
     no como permiso para repetir con otra interfaz.
5. En ambos casos, comprobar que el run usa `ref=main` y
   `github.sha=CUTOVER_PROMOTED`.
6. Esperar integrity, build, presupuesto, SEO, deploy y readback.
7. Devolver la autorización manual a `disabled`; si es durable, invocar su
   desactivación canónica para dejar `dispatch_enabled=false`, y verificar
   ambos estados.

Éxito mínimo:

- workflow y deployment verdes;
- `vinabike-store.web.app/release.json` y `vinabike.cl/release.json` nombran
  `CUTOVER_PROMOTED`;
- `dirty` es `false`;
- home, navegación, búsqueda, producto, carrito/checkout, imágenes, SEO,
  redirects y auth pasan smoke;
- no existe regresión frente a los cambios intencionales del build anterior.

Si falla, restaurar la release previa solo para el target tienda, verificar su
`release.json` y corregir hacia adelante.

## 15. Fase 6 — Alinear ramas y establecer `main` como canónica

En modo completo, solo cuando ambos targets estén verificados. En modo Git-only,
solo después de validar el árbol de `P`, confirmar que todos los deploys fueron
omitidos y registrar formalmente que producción sigue pendiente:

```bash
test "$(git rev-parse origin/main)" = "$CUTOVER_PROMOTED"
test "$(git rev-parse origin/smartpegas1.0)" = "$CUTOVER_BRIDGE"
git merge-base --is-ancestor "$CUTOVER_BRIDGE" "$CUTOVER_PROMOTED"

git push origin \
  "${CUTOVER_PROMOTED}:refs/heads/smartpegas1.0"
```

La actualización debe ser fast-forward. Verificar:

```bash
git fetch origin main smartpegas1.0
test "$(git rev-parse origin/main)" = \
  "$(git rev-parse origin/smartpegas1.0)"
```

Después:

1. Proteger/bloquear `smartpegas1.0` contra pushes, force-push y borrado.
2. Cambiar el checkout canónico a `main` con fast-forward limpio.
3. Confirmar que VS Code, tareas, agentes y scripts resuelven rama y SHA desde
   `main`.
4. Marcar cualquier prepared state anterior como inválido.
5. Consultar todos los runs ERP/tienda creados desde la activación del freeze.
   No puede quedar ninguno queued, waiting o in-progress; una ejecución vieja
   no debe reevaluar el valor después de descongelar.
6. Confirmar que `VINABIKE_PRODUCTION_MANUAL_DEPLOY_AUTHORIZATION=disabled` y,
   si existe publisher durable, `dispatch_enabled=false`.
7. Solo en modo completo, cambiar
   `VINABIKE_PRODUCTION_DEPLOY_FREEZE=false` y releerla. En modo Git-only debe
   permanecer `true`.
8. No hacer un release de instaladores solo para “probar el cutover”.

El próximo release real debe prepararse nuevamente desde un commit posterior de
`main`. La ancestría preservada permite seguir usando el último release en `F`
como baseline; publicar inmediatamente `P`, cuyo árbol no cambia respecto de
`F`, puede fallar correctamente por no haber cambios de producto.

## 16. Rollback y condiciones de aborto

En cualquier salida —éxito, fallo o aborto—, la primera acción de cierre es
devolver la autorización manual a `disabled`. Si el publisher durable fue
habilitado, ejecutar también su desactivación canónica hasta verificar
`dispatch_enabled=false`. Si alguno de esos estados no puede verificarse,
mantener el freeze en `true` y activar el runbook de incidente antes de
continuar.

| Momento | Respuesta segura |
| --- | --- |
| Antes de crear `M` | Corregir precondición; ninguna mutación remota. |
| Merge `-s ours` aún sin commit | `git merge --abort`. |
| `M` local | Conservarlo para diagnóstico; no publicar. |
| `M` ya en `smartpegas1.0`, `main` aún en `N` | Detenerse. El árbol de smart no cambió; no reescribir la rama. Corregir la PR o los checks. |
| `P` ya en `main`, deploys congelados | No mover refs atrás. Corregir configuración o código hacia adelante. |
| Fallo del ERP | No desplegar tienda; restaurar la release Firebase ERP previa si ya se publicó. |
| Fallo de tienda | Mantener ERP válido; restaurar solo la release de tienda previa. |
| Publicación accidental de desktop/Android | Activar el runbook de incidente y el rollback específico de esa plataforma. Android exige forward-fix con version code mayor. |
| Mutación o anomalía de datos | Detener deploys, preservar evidencia y seguir el contrato/runbook de base de datos. |

Prohibiciones absolutas después de `P`:

- no force-push de `N` sobre `main`;
- no revertir ciegamente el merge completo;
- no restaurar el workflow viejo de `main`;
- no borrar tags/releases para ocultar el intento;
- no reparar datos “a intuición”.

El rollback de Git no es simétrico. La recuperación correcta es rollback del
artefacto por target o una corrección hacia adelante desde `P`.

## 17. Observación y retiro posterior de `smartpegas1.0`

Mantener `smartpegas1.0` protegida, inmóvil y fuera del trabajo diario durante:

- un mínimo de 7 días;
- al menos un PR normal posterior fusionado a `main`;
- al menos un deploy web normal posterior desde `main`;
- idealmente el siguiente release planificado de las plataformas instalables.

Observar:

- checks requeridos y protecciones;
- ERP/tienda y sus `release.json`;
- primer ciclo de Dependabot;
- primer Technology Radar programado;
- gates macOS/Windows artifact-only;
- primer Android dispatch desde el workflow ya registrado en default;
- tareas locales de publicación y generación de notas;
- cualquier referencia operativa restante a `smartpegas1.0`.

Al cumplir las condiciones:

1. Retirar `smartpegas1.0` de la policy del environment `Production`.
2. Cambiar triggers, pruebas e instrucciones transicionales a `main` solamente.
3. Mantener el tag de respaldo y el historial.
4. Decidir por separado si la rama se conserva archivada o se elimina. La
   eliminación requiere autorización nueva y no forma parte de este runbook.

### 17.1 Backlog registrado el 2026-09-15 (no ejecutado ese día)

Cada punto es una tarea con su propia PR; ninguno bloquea el cierre de §19.

1. **Instalar el conducto durable de publicación de la tienda en
   producción:** desplegar `20260728230000_add_storefront_publication_contract.sql`
   con `scripts/db/deploy_migration.sh` y su `--verify`, cargar en Vault el
   secreto que la edge function `dispatch-storefront-publication` usa para
   firmar el `workflow_dispatch` (GitHub App con permiso `actions:write`
   sobre `firebase-hosting-store.yml`), desplegar esa función con
   `scripts/supabase_cli.sh`, activar `dispatch_enabled` en
   `storefront_publication_targets` en un paso separado y probar una
   publicación de punta a punta desde el editor del sitio. Hasta entonces la
   tienda se publica por push a `main` (paso 5).
2. **Retirar `smartpegas1.0` después del 2026-09-22** (7 días desde el
   cutover), siguiendo §17: `on.push.branches` de `secret-scan.yml` y
   `erp-integrity-gate.yml`, la custom branch policy del environment
   `Production`, y los textos transicionales en
   `.github/copilot-instructions.md` («Mandatory Workspace And Branch
   Continuity» y la nota del environment en los runbooks de escritorio) y
   `docs/MACOS_DESKTOP_DISTRIBUTION.md`. El tag de respaldo se conserva.
3. **Diferir en la tienda lo que sólo usa el dueño:** poner el host del
   editor del sitio (`persistent_editor_shell`, dock contextual, hoja de
   bloques, command scope, recuperación de borradores) y el chat de clientes
   detrás de los `deferred as` que ya existen, y volver a bajar el
   presupuesto de `check_storefront_bundle_budget.sh` a la medida del
   resultado (paso 5, defecto 2).
4. **Deuda de carga en Supabase**, medida en
   `docs/development/SUPABASE_WORKFLOW.md` («Backlog de carga residual,
   2026-09-15»): Realtime `list_changes`, políticas RLS sin `(select …)`,
   pollers del ERP y de la tienda, purga de `cron.job_run_details` y de
   `net._http_response`, y los `raise … errcode 40001` restantes de
   `20260829160000_supply_need_refinement_modes.sql`.

## 18. Registro de ejecución

Ruta simplificada (§0), ejecutada el 2026-09-15:

| Campo | Valor |
| --- | --- |
| Fecha/hora UTC inicio | 2026-09-15 ~21:30 (merge de la PR #29) |
| Modo: completo / Git-only | completo, ruta simplificada de §0 |
| Dueño / operador / verificador | dueño (merge de #29 y #30); agentes Claude (sesión en la nube: preparación y promoción; sesión en el Mac: publicaciones, tienda, secreto, documentación) |
| `N` — main anterior | `75cb391f…` |
| `F` — smart final aprobado | `f51f3777…` (+ paso 0 en `claude/gifted-fermi-otkemj`) |
| Tags de respaldo | ramas `cutover-backup/main-before-20260915` → `75cb391f…`, `cutover-backup/smart-before-20260915` → `f51f3777…` |
| `M` — puente | sin efecto (`main` era ancestro puro) |
| `T` — merge de prueba y runs que lo evaluaron | sin efecto; `PR Integrity` y `Secret Scan` de la PR #29 |
| Cambio exacto de protección | 2026-09-15 ~23:20 UTC, §12.1: `required_status_checks.checks` de `main` pasó de `[Reject newly committed credentials, integrity / Database and application regression gate]` (el segundo no lo produce ningún job desde que el gate se partió en shards; toda PR quedaba `BLOCKED` y #29/#30 se fusionaron como admin) a `[Reject newly committed credentials, integrity / Static analysis and packaged web build, integrity / Application regression gate 0..3]`; `strict=true`, `enforce_admins=false`, `required_conversation_resolution=true` y el resto sin cambio; PATCH sobre `…/protection/required_status_checks` únicamente; la PR #31 pasó a `CLEAN` |
| `P` — main promovida | `820ea45d` (PR #29); head observado al cerrar: `dc1e6093` (PR #30) |
| Árbol esperado / árbol observado | `tree(P) = tree(F)`; `git diff --exit-code origin/smartpegas1.0 origin/main` vacío |
| Run ERP / deployment / release anterior | `35026128013` (`820ea45`, deploy en verde, health rojo por el secreto) y `35030810641` (`dc1e609`, todo en verde al primer intento); `release.json` en vivo: `{"commit":"dc1e609…","run":"35030810641","built_at":"2026-09-15T22:48:12Z"}`; release anterior: build del 2026-08-10 |
| Run tienda / deployment / release anterior | `35026128122` (gate 1 rojo, test de mensajería corregido en #30) y `35030810512` (rojo en «Build storefront release» por el presupuesto); en vivo sigue `32404d36` (`manual-shell`, `dirty: true`, 2026-09-02) hasta que se fusione la PR #31 y el push publique, o se publique desde el Mac (paso 5) |
| Runs macOS/Windows/secret scan | push `dc1e609`: `Secret Scan` `35030810046` verde, `ERP Integrity Gate` `35030810103`, gates macOS `35030810951` y Windows `35030810513` artifact-only; publicaciones por `workflow_dispatch` sobre `dc1e609`: macOS `35030916303`, Android `35030919542`, Windows `35030922803`, las tres en verde |
| Tags/releases antes y después | macOS `macos-v1.0.3-177` → `macos-v1.0.3-180` (`macos-latest` cita `dc1e609`, `vinabike_erp_macos_1.0.3-180.zip`); Windows → `windows-v1.0.3_61-55` (`windows-release-manifest.json` cita `dc1e609`); Android → `latest.json` privado con `version_name 1.0.3`, `build_number 66`, `version_code 2066`, `vinabike-erp-1.0.3+66-arm64-v8a.apk` (97,6 MB), `published_at 2026-09-15T23:12:17Z`; evidencia `android-release-manifest.json` con `commit dc1e609` en el artifact `vinabike-erp-android-release-evidence` del run |
| SHA final de ambas ramas | `origin/main = origin/smartpegas1.0 = dc1e6093` |
| Freeze activado/desactivado | no implementado (§0.1); no aplica |
| Smokes | ERP web: `release.json` y health de producción por el workflow; escritorio: el aviso de actualización a 1.0.3 (180) llegó a la app instalada del dueño el 2026-09-15 ~23:15 UTC |
| Incidencias y decisiones | (1) secreto `SUPABASE_DB_PASSWORD` de `Production` desactualizado desde 2026-08-10, refrescado 22:36 UTC desde el Keychain; (2) la tienda no se publicaba por push desde el 2026-07-27 por la regla `/accept-invitation` y, hoy, por el presupuesto del bundle —paso 5—; (3) el revisor Copilot cae por el tamaño de `copilot-instructions.md`, no es hallazgo; (4) required check obsoleto en la protección de `main`, reparado (fila de arriba); (5) backlog en §17.1 |
| Fecha/hora UTC cierre | pendiente: se cierra cuando la tienda sirva el SHA de `main` (paso 5) y termine la observación de §17 (a partir del 2026-09-22) |

## 19. Criterio de cierre

La transición de rama está cerrada cuando:

- `origin/main` y `origin/smartpegas1.0` apuntan al mismo `P`;
- el árbol de `P` es idéntico al `F` aprobado;
- ambas historias son ancestros de `P`;
- `main` conserva protección y checks reales;
- ningún instalador fue publicado accidentalmente;
- el checkout, agentes y tareas usan `main`;
- `smartpegas1.0` está protegida y fuera del flujo operativo;
- toda la tabla de ejecución tiene evidencia.

En modo completo, el cierre operacional además exige:

- ERP y tienda sirven el mismo SHA limpio `P`;
- ambos rollbacks previos siguen identificados;
- freeze volvió a `false`.

En modo Git-only:

- producción no se declara promovida;
- freeze permanece en `true`;
- el registro enlaza una tarea posterior, con dueño y ventana, para ERP/tienda;
- no se reanudan deploys automáticos hasta cerrar esa tarea.

Hasta cumplir el criterio del modo elegido, la operación permanece abierta y
`smartpegas1.0` no se retira.
