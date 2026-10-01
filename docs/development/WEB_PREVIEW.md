# Running the ERP or the storefront in a browser to verify UI

> Iterating on UI? The browser is **not** the fast loop. A native macOS debug
> session hot-reloads in 2-5 s and can be clicked and screenshotted by an
> agent: see [`AGENT_MACOS_APP_CONTROL.md`](AGENT_MACOS_APP_CONTROL.md). Use
> this document when the browser itself is the thing under test.

Use `scripts/dev/web_preview.sh`. Do not improvise the commands: the traps
below cost real time and every one of them looks exactly like "the app is just
slow".

```bash
scripts/dev/web_preview.sh start --erp --release  # ERP visual: reuse existing bundle or build if absent, then serve on :54330
scripts/dev/web_preview.sh build --erp --release  # rebuild after a verified edit round
scripts/dev/web_preview.sh url /profile   # the URL you must open
scripts/dev/web_preview.sh stop
scripts/dev/web_preview.sh log 40 --erp --release
```

Use plain `start` only when `debugPrint`/DWDS evidence is required. For normal
visual verification, ERP release mode keeps one compiled bundle that opens in
seconds instead of making the browser resolve the debug module graph.

Add `--store` for the public storefront. It is a different app, so it gets a
different entrypoint, port and browser origin, and the two run side by side:

```bash
scripts/dev/web_preview.sh start --store        # storefront on :54331 (debug)
scripts/dev/web_preview.sh url /productos --store
scripts/dev/web_preview.sh stop --all
```

**To simply look at and click through either app, prefer release mode** — one
compiled bundle that boots in seconds and is immune to Traps
1, 2 and 4 below, because there is no module graph to strand and no debug
service to hold state:

```bash
scripts/dev/web_preview.sh start --store --release   # reuse existing bundle or build if absent, then serve on :54331
scripts/dev/web_preview.sh build --store --release   # rebuild after code changes
scripts/dev/web_preview.sh stop --store              # stops both store variants
```

**Corrección 2026-09-24:** `start --release` comprueba si existe un bundle, no
si corresponde al código actual. En esta ronda reutilizó uno del 16-sep aunque
el código acababa de cambiar; para verificar una edición, ejecutar `build`
antes de `start`. Ese build tampoco genera snapshots por ruta: sin el paso
`generate_product_seo_snapshots.dart`, `/productos/...` cae al `index.html`
base y no ejercita la página instantánea. No declarar verificado su traspaso
por abrir sólo esa ruta en el preview base.

Los snapshots generados son archivos HTML sin extensión. Antes de esta
corrección el servidor release del preview los enviaba como descarga; ahora
los sirve con `text/html`. La comprobación debe leer el `Content-Type` de una
ruta generada y ver la página en un navegador, no sólo recibir HTTP 200.

`web_preview.sh` is the single owner of preview lifecycle — debug and release
are modes of the same script, sharing the port-ownership rules below.
(`store_release_preview.sh` survives only as a deprecated delegate.)

**2026-09-30 — portal con Auth/Storage local:** `build --store --local`
usa `lib/main_store.dart`, el stack local y el origen separado `:54335`.
Se fija la tienda sintética con `VINABIKE_STORE_TENANT_ID` y
`VINABIKE_STORE_SUBDOMAIN`; el sello del bundle incluye ambos. El perfil
hereda las guardas de URL local y clave pública del ERP local. Una ruta
`/cuenta` en el ERP release no acredita el portal: ese montaje depende de
la autoridad ERP y sus parámetros de desarrollo se ignoran en release.
Ese error dejó un spinner mientras se intentaba comprobar la foto privada.
La regresión mínima compila el entrypoint real con defines privados y sello
de stack/tienda; el consumidor se comprueba en el portal real, con su cliente.

```bash
VINABIKE_STORE_TENANT_ID=<fixture-uuid> VINABIKE_STORE_SUBDOMAIN=<fixture-slug> scripts/dev/web_preview.sh build --store --local
scripts/dev/web_preview.sh serve-release --store --local
scripts/dev/web_preview.sh url /cuenta/login --store --local
```

### VS Code interactive Chrome debugger

The launch configurations `Debug Vinabike Store (Chrome)` and `Reset State`
use the dedicated origin `http://localhost:54332`. They intentionally do not
reuse the normal preview origin on `:54331`: a release service worker or an
old debug module graph therefore cannot replace the code being debugged.

Before launch, `store_chrome_debug_preflight.sh` requires `:54332` to be free.
If a prior VS Code session still owns it, stop that session with `Shift+F5`;
the guard reports the exact holder and never silently chooses a random port or
kills a process it cannot prove belongs to the debugger. Debug responses use
`no-store`, and Chrome is launched with background throttling disabled so the
canvas continues pumping frames while VS Code is foregrounded. `Reset State`
also clears the local storefront caches and auth once per new browser tab;
hot reloads within that session preserve the state created after the reset.

The trade-off is explicit: the release preview does not hot-anything and needs
a rebuild (a few minutes) to pick up code changes, but every page load after
that is seconds and never hangs. The debug server remains the right tool for
`debugPrint` logs and DWDS, and the wrong tool for "does the page work".

Lifecycle safety rules the script enforces (and you should not work around):

- before start/stop it resolves who holds the port; it only ever signals
  processes it can positively identify as its own (recorded pids and their
  children, or the release server's exact argv identity). That release
  identity includes the canonical checkout root, target, mode, and port; there
  is no global marker-based process kill. A developer's own `flutter run` on
  the same port looks identical to ours by command line, so resemblance is
  never identity — a foreign holder is reported and the script refuses,
  exit 1. A transitional exception can retire the predecessor release server,
  but only when that exact PID is the configured port's listener and its argv
  ends with this checkout's `build/web_store_preview`, port, and legacy
  `vinabike-store-release-preview` marker. The generic legacy marker is never
  searched globally or treated as ownership;
- process termination is asynchronous, so both `stop` and the stop phase of
  `start` wait until the operating system reports the port genuinely free.
  If it remains occupied past the bounded release timeout, the command fails
  instead of launching a competing server or claiming that the preview
  stopped;
- readiness is bounded (release ~60 s, debug ~600 s), checks child liveness,
  verifies before and after the content probe that the port listener belongs
  to the newly recorded PID/start-stamp tree, and probes real content. This
  prevents a draining old server from satisfying readiness for its
  replacement. The release server returns 404 for missing asset-like paths
  instead of masking them with index.html, so the `main.dart.js` probe cannot
  false-pass; only route-like navigations fall back to index.html;
- release rebuilds compile into an immutable directory under
  `build/web_erp_preview_versions/releases/` or
  `build/web_store_preview_versions/releases/`; only the target's `current`
  symlink is replaced with an atomic filesystem operation after a successful
  build. The served path therefore has no delete/rename gap, and a failed
  build leaves the last good bundle serving;
- PID records include the operating system's process start timestamp. A
  one-line legacy record or recycled PID is discarded without signaling that
  process. Marker-based recovery also captures and revalidates that timestamp,
  argv identity, and listener PID immediately before sending TERM; it never
  escalates to a broad kill or `KILL`.

## The ERP against the local Supabase stack (`--local`, 2026-09-30)

The production ERP preview compiles `lib/main.dart` without Supabase defines,
and `SupabaseConfig` then defaults to **production**. The two local profiles
are ERP `--local` and portal `--store --local`. To click through the ERP
against local Auth, REST and Storage — synthetic users, fault injection,
anything that must not touch real data — use the local profile:

```bash
scripts/dev/web_preview.sh build --local   # compile lib/main.dart for the running local stack
scripts/dev/web_preview.sh start --local   # serve it on http://localhost:54334
scripts/dev/web_preview.sh stop --local    # (stop --all also stops it)
```

- **Release only, its own origin.** Port `54334` (`ERP_LOCAL_WEB_PORT`), its
  own PID/run dir and `build/web_erp_local_preview_versions/`
  (`WEB_PREVIEW_LOCAL_BUILD_STATE_DIR`; the generic override never applies to
  it). A port equal to the production previews' (`54330`/`54331`) is refused:
  browser storage is per origin, and a production session must never share
  one with a local bundle.
- **Defines come from the running stack, privately.** `scripts/supabase_cli.sh
  status -o env` goes to a 0700 temp directory; only `API_URL`, `ANON_KEY`
  and `PUBLISHABLE_KEY` are kept, written to a 0600 JSON passed with
  `--dart-define-from-file`, and deleted right after the compile. The keys are
  never in argv, the log or the terminal. The build refuses a missing stack, a
  URL that is not exactly `http://127.0.0.1:<port>` or `http://localhost:<port>`
  (so `http://127.0.0.1:54321@host` fails), and a key that is not public (a
  `service_role` JWT or an `sb_secret_…` key).
- **No bundle crosses over.** The build fails unless the local API URL is
  compiled into the JS, and stamps the release with the stack's URL and a key
  fingerprint (`.vinabike-local-profile`, no key). The local server refuses a
  bundle without that stamp, the production previews refuse one with it, and
  `start --local` rebuilds when the stamp belongs to another stack. Code
  changes still need an explicit `build --local`, as in every release mode.
- **Signing in.** The local bundle has no production session and the login is
  the real one. Use only the disposable synthetic credentials of the named
  local fixture. A launcher can pass them by environment, as
  `scripts/e2e/run_task_form_local.sh` does; Computer Use can enter that same
  fixture's credentials in the verified local origin. Never use or save the
  owner's production password. Keep credential files private and do not
  capture the login tree. The local stack itself is started and inspected
  per [`AGENT_DATABASE_CONTRACT.md`](AGENT_DATABASE_CONTRACT.md).

This is the web client. A narrow window proves the compact web layout, not the
native phone client.

### Driving Flutter web with Playwright (2026-09-30)

Ten runs of the task-form journey found these. Each one looked like an
app defect, and one did cost three runs:

- **`locator.isVisible()` does not wait.** A Flutter menu (dropdown,
  `MenuAnchor`) opens with an animation. Until it ends, its items are
  `menuitem`s with **no name** and nothing painted. Checked too early, the
  «Asignar a» menu looked like it held only «Sin asignar» while the directory
  had answered 200 with two people: about 12 minutes chasing a non-defect.
  Use `waitFor({ state: "visible" })`.
- **Typing right after a click loses the first letter** in a field without
  `autofocus`: Flutter mounts the editable DOM element on focus. «Pastillas»
  was saved as «astillas». Wait for `toBeFocused()`, then assert `toHaveValue`.
- **Set `actionTimeout`.** Without it, a click on a missing control waits
  for the whole test timeout (12 minutes in the first run).
- **Accessible names are not the visible text.** Today `VbShellIconButton`
  doubles its name («Capturas Capturas»), the workshop dropdowns carry their
  emoji («📋 Vista: Tabla»), and a row's title lives inside its button's
  name. Match with a pattern, and read the tree (`ariaSnapshot`) when a
  locator fails.
- **Escape does not close a Flutter `Dialog`** once focus sits in the
  semantics DOM. Use its «Cerrar» button, scoped to the `dialog`.
- **A SnackBar opened under a dialog is not in the tree.** It sits behind the
  modal barrier, dimmed, and is never announced. A test that looks for it by
  text fails for that reason, not because the message is missing.
- **Save the tree on failure, never on `/login`.** The DOM password field
  holds what was typed.

The desktop workshop journey (`run_android_local_journey.sh --journey
workshop --surface web`, `e2e/workshop_local.spec.ts`, 2026-09-30) added:

- **Explore a held page instead of rerunning.** With `--hold`, a failed step
  leaves the page open with its session and it runs whatever lands in
  `.tmp/e2e/web-workshop-<fecha>-hold/cmd.js` (an async body with `page`,
  `h`, `expect`; answer in `out.txt`; `exit` ends it). The desktop names were
  learned that way in one sitting, not one run per control. The body has no
  `require`; `Buffer` is there.
- **Roles are not the phone's.** A tappable row or chip that only has a
  label is a `group` (the customer in «Seleccionar cliente», the task's
  line); the wheel-side menu offers `menuitemcheckbox`; the Enrayado wizard
  is inline on desktop and its wheels are `checkbox`es. Desktop also names
  things differently: «Productos y Servicios», «Configurar servicio Falta:
  …», the row's «Cambiar estado y ver acciones …», «Descargar o ver más
  acciones de presupuesto» (where «Facturar presupuesto» lives).
- **A text field's value is not in the tree until it has focus**: the edit
  form's title looked empty in `ariaSnapshot` and was filled on screen.
  `inputValue()` on an unfocused Flutter field is empty too.
- **Names keep their line breaks.** A caption under a field is the button's
  description, and a long group name joins lines with `\n`: `.` does not
  cross them, `[\s\S]` does.
- **`Tooltip` around a `Semantics(label:)` doubles the name and adds a second
  node** (the tooltip) with the same name; the click went to the wrong one.
  An icon button is an `IconButton` with `tooltip`, one node, one name.
- **A node past the table's visible width keeps its scrolled position.** In
  the jobs table the «Factura» column is off to the right; its menu's
  semantics box sat at x≈1236 with the table unscrolled, right on top of the
  «Detalles» cell, and only matched the drawing once the table was scrolled.
  Playwright clicked the box, and the «Detalles» editor opened «by itself»
  three runs in a row; it looked like an app defect after approving. Scroll
  the table with the wheel (`mouse.wheel(900, 0)` over it) before touching
  the right-hand columns, and back afterwards; compare `boundingBox()` with a
  screenshot when a click lands on a neighbour. For a screen-reader user on
  web this is a real mismatch; it is reported, not fixed.

The backup recovery journey (`--journey backup --surface web`,
`e2e/backup_local.spec.ts`, C2 2026-09-30) added:

- **An `AlertDialog` is `alertdialog`, not `dialog`, and its body is one
  `group`.** Title and body do not come as separate nodes: `getByText` on a
  row inside finds nothing. Read the dialog with `ariaSnapshot()`, collapse
  whitespace and match a pattern across rows. A list that shows «y N tipos
  más» after eight rows hides the rest from the tree too: what the test must
  see has to be among the first rows.
- **An `AlertDialog` whose only action is a `VbButton` publishes no node for
  that button on web** (open defect, 2026-09-30). The result's «Entendido»
  and the no-changes review's «Cerrar» are missing from the DOM (30 nodes:
  route, title, body), yet `find.bySemanticsLabel('Entendido')` finds the
  button in a widget test with the same snackbar sequence. The review with
  two actions (Cancelar + Restaurar) exposes both. Relayout and Tab do not
  bring it back. The barrier's «Cerrar» is exposed and Escape closes these
  dialogs (it did in this journey, unlike the workshop `Dialog` above), so
  the spec records `…=sin_nodo_web` and closes with Escape; it does not
  pretend the button exists. Two runs were spent before it was clear the
  button, not the locator, was missing.

A Storage outage is the real container:
`docker stop supabase_storage_bikeshop-erp`. Kong answers 502/503 at once,
and routes again after `docker start` once `/storage/v1/status` is below 500.
The launcher always leaves it started.

## Preview a pull request from any device (iPad, phone)

Every pull request that touches app code gets its own ERP web build on a
temporary Firebase Hosting channel, published by
`.github/workflows/firebase-hosting-preview.yml`. The link appears as a
comment on the pull request (posted by `github-actions`) and in the run
summary, about 8-12 minutes after the push; every new push to the PR replaces
it; it expires after 7 days. Open it in Safari on the iPad and sign in with
email and password.

What it is and is not:

- It is the **ERP** (`lib/main.dart`), built with the exact recipe of the
  `main` deployment (`firebase-hosting-merge.yml`). The storefront has its own
  publication contract and is not previewed here.
- It talks to the **production** Supabase project. Every sale, payment or edit
  made on a preview is real. Preview the screens; do not rehearse operations.
- `release.json` on the preview carries `target: "erp-preview"`, the deployed
  commit and the PR number, and the workflow refuses to finish until the
  channel serves that exact commit.
- A pull request opened from a fork gets no preview: GitHub gives forks no
  secrets.
- Google sign-in and e-mail links return to the page that started them, and
  Supabase only accepts allow-listed return addresses. Preview origins are
  dynamic (`https://project-vinabike--pr123-branch-abc123.web.app`), so the
  owner adds one wildcard once in the Supabase dashboard, Authentication →
  URL Configuration → Redirect URLs: `https://project-vinabike--*.web.app/**`.
  Email + password sign-in needs nothing.

One-time setup, owner only: the workflow runs in the GitHub environment
`Preview` and needs the secret `FIREBASE_SERVICE_ACCOUNT_PROJECT_VINABIKE`
there (the same service account the merge workflow reads from `Production`).
If the secret is scoped to `Production`, add it to `Preview` in GitHub →
Settings → Environments. The workflow also accepts a manual run
(Actions → *ERP web preview* → *Run workflow*, on any branch), which is how
the setup is verified without opening a pull request: the run summary shows
the link.

## Trap 0 — the storefront is not the ERP on another route

Production builds the store from its own entrypoint, `lib/main_store.dart`
(see `scripts/deploy.sh`). `lib/main.dart` only renders storefront UI when
`_detectPublicStoreHost()` recognises the host, so previewing the store through
the ERP entrypoint — with `--dart-define=FORCE_SUBDOMAIN=…`, say — boots the
entire ERP behind it: extra providers, extra preloads, extra concurrent
PostgREST traffic against the same project.

Catalog RPCs that normally answer in well under a second then run long enough
to cross the per-role `statement_timeout` (`anon` 3s, `authenticated` 8s) and
come back as `PostgrestException(57014, canceling statement due to statement
timeout)`. The catalog renders "No pudimos cargar el catálogo", which reads as
a broken query, or as something that only breaks on localhost. It is neither —
the same code loads 553 products fine from `--store`.

Two corollaries worth remembering when a page half-loads:

- the elapsed time in the console tells you which role the request used —
  ~4-5s means `anon`, ~12s means a signed-in session;
- `get_public_product_facets_v2` (v1 until 2026-09-16; v2 adds the
  technical-spec facets) is heavy enough to time out intermittently on
  production too. Facets degrade silently, so a 500 there is not the reason a
  catalog is empty.

## Trap 1 — a restarted server strands the open tab

A debug web build is not one bundle; it is thousands of separate module
scripts. When the server restarts, a tab that already loaded the previous
bootstrap keeps asking for modules that no longer exist. The page then sits on
the splash logo **forever**: the server answers requests, the console still
prints application logs, and nothing ever renders.

This is indistinguishable from a slow first compile, and waiting never fixes
it. Measured on this repository: a stranded tab sat at 227 s with the Flutter
view never mounted; the same build, opened with a cache-busting parameter,
rendered in 17 s.

**Always open the URL printed by `web_preview.sh url`.** Its `?cb=<timestamp>`
forces the tab to drop the stale bootstrap. A plain reload is not enough.

Symptom check, from the browser console:

```js
document.querySelectorAll('script').length   // ~16 = stranded, ~2700 = healthy
document.querySelectorAll('flutter-view').length  // 0 = never mounted
```

## Trap 1b — `localhost` and `127.0.0.1` are different origins

The signed-in Supabase session lives in browser storage, which is per origin.
Opening the preview on `127.0.0.1` therefore starts from empty storage and
drops you at the login screen even though the session on `localhost` is still
valid. The script only ever prints `localhost`; do not "helpfully" swap it for
the loopback address.

That session survives server restarts, so one manual login covers a whole
working session. Credentials are never stored in the repository, in
configuration, or in agent instructions.

The two targets already sit on different ports, so they never share storage:
an ERP login on `:54330` cannot leak a session into the storefront on `:54331`.
That is deliberate — a storefront visitor is anonymous, and a stray ERP session
silently changes both the Postgres role and the account UI in the header.

## Trap 2 — there is no hot restart here

The `web-server` device cannot hot restart. It needs the Dart Debug Chrome
extension to accept one, and a failed attempt leaves the running instance
unusable, forcing a full restart anyway.

So the number to optimise is **how many restarts**, not how fast one is:

1. make all the related edits;
2. run `flutter analyze` and the focused tests;
3. restart once;
4. verify every affected screen in that single session.

Restarting after each individual edit is the slowest possible loop.

## Trap 3 — "server ready" is not "app ready"

`flutter run` reports that it is serving as soon as it can answer requests. The
browser then still has to load and boot the whole debug build. No server-side
probe can observe that client render, so `start` deliberately stops waiting
once the real JavaScript asset is available and prints the cache-busted URL.
Open that exact URL and wait for the visible app before taking a screenshot;
an arbitrary sleep only makes fast runs slow and still false-passes slow ones.

## Trap 4 — a backgrounded browser pane pumps zero frames

If the preview is driven through an embedded/automation browser pane rather
than a tab the user is actively looking at, the compositor throttles
`requestAnimationFrame` to **zero** while the pane is not displayed (measured:
0 rAF callbacks in 3 s). Flutter web schedules every frame through rAF, so
while hidden the app cannot paint, cannot run `addPostFrameCallback`s, and
cannot finish boot (`runApp`'s first build waits on the first frame).

What this looks like from the outside — all false alarms:

- the splash logo "never mounts" although all ~2 700 modules loaded;
- screenshots show a stale frame: a disabled button, a spinner, or the
  restrictive `Producto no disponible` SEO title, minutes after the state
  behind them already recovered (the logs show `✅ Found product` while the
  pixels still show the old frame);
- taps do nothing, because gesture resolution needs a frame;
- patching `document.visibilityState` changes nothing — the throttle is the
  compositor's, not the DOM's.

Interacting with the pane makes it worse: each tool call fronts and hides it,
and each re-front fires a lifecycle resume, which triggers the storefront's
freshness monitor (`markCacheStale` → product revalidation), so the app is
disproportionately observed in its 1–2 s "revalidating" window. Verify with
console logs, `localStorage`, and network evidence instead of pixels, and
treat a screenshot of an embedded pane as "last painted frame", not "current
state". A real foregrounded browser tab — the user's own — does not have this
problem, which is why the same build looks fine to a human and broken to the
automation.

## What this does not cover

Flutter web paints into a canvas and does not publish an accessibility tree by
default, so `read_page` / `find` return an empty document and UI automation has
to click screenshot coordinates. Enabling semantics from `main.dart` was tried
and reverted: requesting it during bootstrap leaves the engine without a
mounted renderer and the app never paints. If you retry this, verify a real
rendered screen before keeping the change.
