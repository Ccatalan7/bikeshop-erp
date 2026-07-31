# Running the ERP or the storefront in a browser to verify UI

> Iterating on UI? The browser is **not** the fast loop. A native macOS debug
> session hot-reloads in 2-5 s and can be clicked and screenshotted by an
> agent: see [`AGENT_MACOS_APP_CONTROL.md`](AGENT_MACOS_APP_CONTROL.md). Use
> this document when the browser itself is the thing under test.

Use `scripts/dev/web_preview.sh`. Do not improvise the commands: the traps
below cost real time and every one of them looks exactly like "the app is just
slow".

```bash
scripts/dev/web_preview.sh start --erp --release  # ERP visual: build if needed + serve on :54330
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
scripts/dev/web_preview.sh start --store --release   # build if needed + serve on :54331
scripts/dev/web_preview.sh build --store --release   # rebuild after code changes
scripts/dev/web_preview.sh stop --store              # stops both store variants
```

`web_preview.sh` is the single owner of preview lifecycle — debug and release
are modes of the same script, sharing the port-ownership rules below.
(`store_release_preview.sh` survives only as a deprecated delegate.)

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
- `get_public_product_facets_v1` is heavy enough to time out intermittently on
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
