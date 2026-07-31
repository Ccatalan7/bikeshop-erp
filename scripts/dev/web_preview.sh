#!/usr/bin/env bash
# Local web preview for UI verification — the single owner of preview
# lifecycle for both apps and both modes.
#
#   scripts/dev/web_preview.sh start                    # ERP DEBUG on :54330
#   scripts/dev/web_preview.sh start --erp --release    # ERP RELEASE on :54330
#   scripts/dev/web_preview.sh build --erp --release    # rebuild ERP release
#   scripts/dev/web_preview.sh start --store            # storefront DEBUG on :54331
#   scripts/dev/web_preview.sh start --store --release  # storefront RELEASE on :54331
#   scripts/dev/web_preview.sh build --store --release  # rebuild the release bundle
#   scripts/dev/web_preview.sh url /productos --store
#   scripts/dev/web_preview.sh stop --store             # stops BOTH store variants
#   scripts/dev/web_preview.sh stop --all
#   scripts/dev/web_preview.sh log 40 --store [--release]
#   scripts/dev/web_preview.sh errors --store
#   scripts/dev/web_preview.sh serve-release --erp      # foreground static server
#   scripts/dev/web_preview.sh serve-release --store    # foreground (launch.json)
#
# Which mode to use:
#   * RELEASE (--erp/--store --release) to look at and click through the app. One
#     compiled bundle, boots in seconds, immune to the module-graph traps
#     below. Needs `build` after code changes.
#   * DEBUG for `debugPrint` logs and DWDS. ~2 700 module scripts, minutes to
#     boot, all the traps below apply.
#
# Why a script instead of ad-hoc commands:
#
# 1. A restarted DEBUG server invalidates whatever the open tab already
#    loaded. A debug web build is thousands of separate module scripts, and a
#    tab holding the previous bootstrap will never finish loading the new one:
#    the page sits on the splash logo forever while the console still looks
#    busy. It is indistinguishable from "still compiling", and waiting does
#    not fix it. ALWAYS open the URL printed by `url` — its cache-busting
#    query parameter forces the tab to drop the stale bootstrap. Measured:
#    stale tab, 227s and never mounted; cache-busted, 17s to a rendered app.
#    (Release mode has no module graph, so this trap does not exist there.)
#
# 2. The `web-server` device cannot hot restart — it needs the Dart Debug
#    Chrome extension to accept one, and a failed attempt leaves the running
#    instance unusable. Every code change costs a full restart (debug) or a
#    rebuild (release); batch the edits, run analyzer and tests first, and
#    restart once per verification round.
#
# 3. The storefront is NOT the ERP with a different route. Production builds
#    it from its own entrypoint (`lib/main_store.dart`, see scripts/deploy.sh),
#    and the ERP entrypoint only renders storefront UI on a recognised public
#    host. Previewing the store through `lib/main.dart` boots the whole ERP
#    alongside it and its extra concurrent traffic can push catalog RPCs into
#    the per-role `statement_timeout` (57014 → "No pudimos cargar el
#    catálogo"). `--store` runs the real entrypoint.
set -euo pipefail

FLUTTER="${FLUTTER_BIN:-$HOME/fvm/versions/3.38.5/bin/flutter}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_MARKER_PREFIX="vinabike-web-preview"
LEGACY_RELEASE_MARKER="vinabike-store-release-preview"

# Storefront tenant identity. Not a secret — it is already in scripts/deploy.sh
# and the published SEO snapshots. Override to preview a different shop.
STORE_TENANT_ID="${VINABIKE_STORE_TENANT_ID:-5443b130-cc28-45af-a420-cd500b288890}"
STORE_SUBDOMAIN="${VINABIKE_STORE_SUBDOMAIN:-vinabike}"

TARGET=erp
MODE=debug
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --store)   TARGET=store ;;
    --erp)     TARGET=erp ;;
    --all)     TARGET=all ;;
    --release) MODE=release ;;
    *)         ARGS+=("$arg") ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

STORE_DEFINES=(
  --dart-define=STORE_PERF_LOGS=true
  --dart-define=PUBLIC_STORE_IGNORE_AUTH=true
  "--dart-define=PUBLIC_STORE_TENANT_ID=$STORE_TENANT_ID"
  "--dart-define=PUBLIC_STORE_SUBDOMAIN=$STORE_SUBDOMAIN"
)

configure() {
  local target="$1" mode="${2:-debug}"
  case "$target" in
    erp)
      PORT="${ERP_WEB_PORT:-54330}"
      ENTRYPOINT="lib/main.dart"
      DEFINES=()
      DEFAULT_BUILD_STATE_DIR="$ROOT/build/web_erp_preview_versions"
      ;;
    store)
      PORT="${STORE_WEB_PORT:-54331}"
      ENTRYPOINT="lib/main_store.dart"
      DEFINES=("${STORE_DEFINES[@]}")
      DEFAULT_BUILD_STATE_DIR="$ROOT/build/web_store_preview_versions"
      ;;
    *) echo "unknown target: $target" >&2; exit 2 ;;
  esac
  local run_key="$target"
  [ "$mode" = release ] && run_key="$target-release"
  RUN_DIR="${TMPDIR:-/tmp}/erp-web-preview/$run_key"
  LOG="$RUN_DIR/run.log"
  PID_FILE="$RUN_DIR/run.pid"
  # Release bundles are immutable versions. `current` is an atomically
  # replaced symlink, so a failed or concurrent build never removes the last
  # good bundle from underneath the running server.
  BUILD_STATE_DIR="${WEB_PREVIEW_BUILD_STATE_DIR:-$DEFAULT_BUILD_STATE_DIR}"
  BUILD_RELEASES_DIR="$BUILD_STATE_DIR/releases"
  BUILD_DIR="$BUILD_STATE_DIR/current"
  mkdir -p "$RUN_DIR"
}

# ---------------------------------------------------------------------------
# Port ownership. Before start/stop, resolve exactly who holds the port. We
# only ever signal processes we can positively identify as ours (pid recorded
# in one of our run dirs, or a command line carrying our release marker /
# entrypoint on our port). Anything else aborts with the evidence — never
# kill an unrelated process.
# ---------------------------------------------------------------------------
port_listener_pid() {
  lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true
}

release_scope_marker() {
  # This exact identity is carried in the release server argv. Including the
  # canonical checkout, target, mode and port prevents one checkout or preview
  # mode from finding/signalling another one's server.
  printf '%s|root=%s|target=%s|mode=release|port=%s' \
    "$RELEASE_MARKER_PREFIX" "$ROOT" "$TARGET" "$PORT"
}

legacy_release_scope_suffix() {
  # Transitional identity emitted by the predecessor release-preview script.
  # The generic marker is not ownership: root, build directory and port must
  # also be the exact terminal argv suffix of the process listening here.
  printf ' - %s %s %s' \
    "$ROOT/build/web_store_preview" "$PORT" "$LEGACY_RELEASE_MARKER"
}

recorded_pid() {
  sed -n '1p' "$1" 2>/dev/null | tr -d '[:space:]' || true
}

process_start_stamp() {
  ps -p "$1" -o lstart= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}

pid_record_matches_live_process() {
  local pid_file="$1" pid stored_start current_start
  [ -f "$pid_file" ] || return 1
  pid="$(recorded_pid "$pid_file")"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  # Legacy one-line files are deliberately not trusted. A PID alone can be
  # recycled by the OS and is not process identity.
  stored_start="$(sed -n '2p' "$pid_file" 2>/dev/null || true)"
  [ -n "$stored_start" ] || return 1
  current_start="$(process_start_stamp "$pid")"
  [ -n "$current_start" ] && [ "$current_start" = "$stored_start" ]
}

write_pid_record() {
  local pid="$1" start_stamp next_file
  start_stamp="$(process_start_stamp "$pid")"
  [ -n "$start_stamp" ] || {
    echo "could not record preview process identity for pid $pid" >&2
    return 1
  }
  next_file="$PID_FILE.next"
  printf '%s\n%s\n' "$pid" "$start_stamp" >"$next_file"
  mv -f -- "$next_file" "$PID_FILE"
}

pid_is_descendant_of() {
  local candidate="$1" ancestor="$2" parent
  while [ "$candidate" -gt 1 ] 2>/dev/null; do
    [ "$candidate" = "$ancestor" ] && return 0
    parent="$(ps -p "$candidate" -o ppid= 2>/dev/null | tr -d '[:space:]' || true)"
    case "$parent" in
      ''|*[!0-9]*) return 1 ;;
    esac
    candidate="$parent"
  done
  return 1
}

pid_matches_release_scope() {
  local pid="$1" cmd marker
  [ -z "$pid" ] && return 1
  marker="$(release_scope_marker)"
  cmd="$(ps -p "$pid" -ww -o command= 2>/dev/null || true)"
  case "$cmd" in
    *"$marker"*) return 0 ;;
  esac
  return 1
}

pid_matches_legacy_release_listener() {
  local pid="$1" cmd suffix
  [ "$TARGET" = store ] || return 1
  [ -n "$pid" ] || return 1
  [ "$(port_listener_pid)" = "$pid" ] || return 1
  suffix="$(legacy_release_scope_suffix)"
  cmd="$(ps -p "$pid" -ww -o command= 2>/dev/null || true)"
  case "$cmd" in
    *"$suffix") return 0 ;;
  esac
  return 1
}

release_scope_pids() {
  # Enumerate first, then apply an exact literal marker check. Unlike a global
  # pattern kill, no process is signalled merely for sharing the generic
  # marker.
  local candidate command marker
  marker="$(release_scope_marker)"
  while read -r candidate command; do
    case "$candidate" in
      ''|*[!0-9]*) continue ;;
    esac
    case "$command" in
      *"$marker"*) printf '%s\n' "$candidate" ;;
    esac
  done < <(ps -ax -ww -o pid=,command= 2>/dev/null || true)
}

pid_is_ours() {
  local pid="$1" run_key pid_file recorded
  [ -z "$pid" ] && return 1
  for run_key in erp erp-release store store-release; do
    pid_file="${TMPDIR:-/tmp}/erp-web-preview/$run_key/run.pid"
    if pid_record_matches_live_process "$pid_file"; then
      recorded="$(recorded_pid "$pid_file")"
      # Flutter can wrap the listener more than one process deep.
      if pid_is_descendant_of "$pid" "$recorded"; then
        return 0
      fi
    fi
  done
  # A release server without a usable PID file can still be recovered, but
  # only when its argv proves this exact ROOT + port + target + mode.
  pid_matches_release_scope "$pid" && return 0
  # Deliberately NOT matched: a `web-server --web-port $PORT` command line.
  # A developer's own `flutter run` looks identical, and this script once
  # killed one through exactly that pattern. Identity comes from recorded
  # pids, never from resemblance.
  return 1
}

require_port_free_or_ours() {
  local pid
  pid="$(port_listener_pid)"
  [ -z "$pid" ] && return 0
  if pid_is_ours "$pid"; then
    return 0
  fi
  echo "port $PORT is held by a process this script does not own:" >&2
  ps -p "$pid" -ww -o pid=,command= >&2 || true
  echo "refusing to touch it. Stop it yourself, or change the port via" >&2
  echo "ERP_WEB_PORT / STORE_WEB_PORT." >&2
  exit 1
}

wait_for_port_release() {
  local deadline holder
  deadline=$(( $(date +%s) + ${PORT_RELEASE_TIMEOUT:-15} ))
  while holder="$(port_listener_pid)" && [ -n "$holder" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "port $PORT did not become free after the preview stop request:" >&2
      ps -p "$holder" -ww -o pid=,command= >&2 || true
      echo "refusing to start or report the preview as stopped." >&2
      return 1
    fi
    sleep 0.2
  done
}

# ---------------------------------------------------------------------------
# Release build. Compiles into an immutable version and atomically replaces a
# symlink only on success. The server follows that link per request, so there
# is no delete/rename gap and a failed compile leaves the last good bundle.
# ---------------------------------------------------------------------------
build_release() {
  cd "$ROOT"
  local version staging release next_link
  version="$(date +%Y%m%d%H%M%S)-$$"
  mkdir -p "$BUILD_RELEASES_DIR"
  staging="$BUILD_STATE_DIR/.building-$version"
  release="$BUILD_RELEASES_DIR/$version"
  next_link="$BUILD_STATE_DIR/.current-$version"
  rm -rf -- "$staging"
  echo "building $TARGET release bundle (one-time wait per code revision)…"
  if ! "$FLUTTER" build web --release --pwa-strategy=none \
      -t "$ENTRYPOINT" ${DEFINES[@]+"${DEFINES[@]}"} \
      -o "$staging"; then
    rm -rf -- "$staging"
    return 1
  fi
  [ -f "$staging/main.dart.js" ] || { echo "build produced no main.dart.js" >&2; exit 1; }
  mv -- "$staging" "$release"
  ln -s "releases/$version" "$next_link"
  python3 - "$next_link" "$BUILD_DIR" <<'PY'
import os, sys
os.replace(sys.argv[1], sys.argv[2])
PY
  # Keep the active release and the two newest fallbacks. Cleanup is confined
  # to direct children of the generated releases directory.
  python3 - "$BUILD_RELEASES_DIR" "$BUILD_DIR" <<'PY'
import os, shutil, sys
releases, current_link = sys.argv[1], sys.argv[2]
active = os.path.realpath(current_link)
versions = sorted(
    (entry for entry in os.scandir(releases) if entry.is_dir(follow_symlinks=False)),
    key=lambda entry: entry.stat(follow_symlinks=False).st_mtime,
    reverse=True,
)
keep = {active, *(entry.path for entry in versions[:2])}
for entry in versions:
    if entry.path not in keep:
        shutil.rmtree(entry.path)
PY
  echo "release bundle ready at $BUILD_DIR -> releases/$version"
}

# SPA static server. Asset-like paths (a dot in the last segment) that do not
# exist must 404 — otherwise a missing main.dart.js would be answered with
# index.html and a readiness poll would false-pass. Only route-like paths
# fall back to index.html.
serve_release() {
  [ -f "$BUILD_DIR/index.html" ] || {
    echo "no release bundle at $BUILD_DIR — run: $0 build --$TARGET --release" >&2
    exit 1
  }
  exec python3 - "$BUILD_DIR" "$PORT" "$(release_scope_marker)" <<'PY'
import os, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

root, port = sys.argv[1], int(sys.argv[2])

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=root, **k)
    def send_head(self):
        clean = self.path.split('?', 1)[0].split('#', 1)[0]
        if not os.path.isfile(self.translate_path(clean)):
            last = clean.rsplit('/', 1)[-1]
            if '.' in last:
                self.send_error(404, 'asset not found')
                return None
            self.path = '/index.html'
        return super().send_head()
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
    def log_message(self, *a):
        pass

ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
PY
}

start() {
  # Debug and release variants of one target share its canonical origin.
  # Starting either always retires the other without touching another target.
  stop_one "$TARGET" debug >/dev/null
  stop_one "$TARGET" release >/dev/null
  configure "$TARGET" "$MODE"
  # TERM is asynchronous. Do not launch while an old listener is still
  # draining, and do not let the new readiness probe observe that listener.
  wait_for_port_release
  require_port_free_or_ours
  : >"$LOG"
  cd "$ROOT"
  if [ "$MODE" = release ]; then
    [ -f "$BUILD_DIR/index.html" ] || build_release
    nohup bash "$0" serve-release "--$TARGET" --release >"$LOG" 2>&1 &
    write_pid_record "$!"
    echo "started $TARGET release preview (pid $(recorded_pid "$PID_FILE"))"
  else
    nohup "$FLUTTER" run -d web-server \
      --web-hostname 127.0.0.1 --web-port "$PORT" \
      -t "$ENTRYPOINT" ${DEFINES[@]+"${DEFINES[@]}"} \
      >"$LOG" 2>&1 &
    write_pid_record "$!"
    echo "started $TARGET debug ($ENTRYPOINT, pid $(recorded_pid "$PID_FILE")), compiling…"
  fi
  wait_ready
  echo
  if [ "$MODE" = release ]; then
    echo "OPEN: $(print_url "${1:-/}")"
  else
    echo "OPEN THIS EXACT URL — a plain reload keeps the stale bootstrap:"
    print_url "${1:-/}"
  fi
}

print_url() {
  # Cache-busting matters for the debug module graph (see header note 1).
  # Always `localhost`, never `127.0.0.1`: browser storage is per origin, so
  # the loopback address would start from an empty session. The two targets
  # run on different ports, so their storage is already separate.
  echo "http://localhost:$PORT${1:-/}?cb=$(date +%s)"
}

wait_ready() {
  # Bounded, liveness-checked readiness. The content probe is meaningful
  # because the release server 404s missing assets instead of masking them
  # with index.html.
  local deadline probe listener confirmed_listener recorded
  if [ "$MODE" = release ]; then
    deadline=$(( $(date +%s) + ${READY_TIMEOUT:-60} ))
  else
    deadline=$(( $(date +%s) + ${READY_TIMEOUT:-600} ))
  fi
  while true; do
    if ! pid_record_matches_live_process "$PID_FILE"; then
      echo "preview process exited early; last output:" >&2
      tail -20 "$LOG" >&2
      exit 1
    fi
    recorded="$(recorded_pid "$PID_FILE")"
    listener="$(port_listener_pid)"
    if [ -n "$listener" ] && pid_is_descendant_of "$listener" "$recorded"; then
      if probe="$(curl -sf "http://127.0.0.1:$PORT/main.dart.js" -r 0-64 2>/dev/null)" \
          && [ -n "$probe" ]; then
        # Re-read ownership after the request to close the listener hand-off
        # race. A response from an old or replacement process is not readiness
        # evidence for the process whose PID/start stamp we just recorded.
        confirmed_listener="$(port_listener_pid)"
        if [ "$confirmed_listener" = "$listener" ] \
            && pid_is_descendant_of "$confirmed_listener" "$recorded"; then
          break
        fi
      fi
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "preview not ready before the deadline; last output:" >&2
      tail -20 "$LOG" >&2
      exit 1
    fi
    sleep 2
  done
  echo "server assets ready at http://127.0.0.1:$PORT"
  if [ "$MODE" = debug ]; then
    echo "the debug client boots only after its printed URL is opened; server-side readiness cannot observe that render"
  fi
}

kill_tree() {
  # Recorded pid plus descendants (flutter wraps a dartvm child). Signals
  # only pids we positively recorded — never a pattern.
  local pid="$1" child
  [ -z "$pid" ] && return 0
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill_tree "$child"
  done
  kill "$pid" 2>/dev/null || true
}

stop_one() {
  local target="$1" mode="${2:-debug}"
  configure "$target" "$mode"
  local killed=0 recorded=""
  if [ -f "$PID_FILE" ]; then
    recorded="$(recorded_pid "$PID_FILE")"
    if pid_record_matches_live_process "$PID_FILE"; then
      kill_tree "$recorded"
      killed=1
    elif [ -n "$recorded" ]; then
      echo "refusing stale PID record for $target ($mode): pid $recorded is not the recorded process" >&2
    fi
    rm -f "$PID_FILE"
  fi
  if [ "$mode" = release ]; then
    # Recover an orphaned release server only through its exact scoped marker.
    # Recheck its OS start stamp and marker immediately before signalling to
    # avoid acting on a recycled PID between discovery and kill.
    local candidate start_stamp
    while IFS= read -r candidate; do
      start_stamp="$(process_start_stamp "$candidate")"
      if [ -n "$start_stamp" ] \
          && pid_matches_release_scope "$candidate" \
          && [ "$(process_start_stamp "$candidate")" = "$start_stamp" ]; then
        kill_tree "$candidate"
        killed=1
      fi
    done < <(release_scope_pids)

    # The predecessor script used a generic marker and left no trustworthy PID
    # record. Compatibility is deliberately limited to the current listener
    # whose terminal argv proves this ROOT + legacy build path + PORT. Do not
    # enumerate the marker: a non-listener decoy must never be signalled.
    local legacy_listener legacy_start_stamp
    legacy_listener="$(port_listener_pid)"
    if [ -n "$legacy_listener" ] \
        && pid_matches_legacy_release_listener "$legacy_listener"; then
      legacy_start_stamp="$(process_start_stamp "$legacy_listener")"
      if [ -n "$legacy_start_stamp" ] \
          && [ "$(port_listener_pid)" = "$legacy_listener" ] \
          && pid_matches_legacy_release_listener "$legacy_listener" \
          && [ "$(process_start_stamp "$legacy_listener")" = "$legacy_start_stamp" ]; then
        kill_tree "$legacy_listener"
        killed=1
      fi
    fi
  fi
  if [ "$killed" = 1 ]; then
    echo "stop requested for $target ($mode)"
  else
    echo "nothing recorded to stop for $target ($mode)"
  fi
}

stop() {
  case "$TARGET" in
    all)
      stop_one erp debug
      stop_one erp release
      configure erp release
      wait_for_port_release
      echo "ERP preview port $PORT released"
      stop_one store debug
      stop_one store release
      configure store release
      wait_for_port_release
      echo "store preview port $PORT released"
      ;;
    *)
      # Both variants share the port; stop is always total for the target.
      stop_one "$TARGET" debug
      stop_one "$TARGET" release
      configure "$TARGET" release
      wait_for_port_release
      echo "$TARGET preview port $PORT released"
      ;;
  esac
}

errors() {
  # Flutter's own error stream is the first thing to read when a pane renders
  # blank: a widget that throws while painting produces no visual error on
  # web and the stack lands here, not in the browser console.
  [ -f "$LOG" ] || { echo "no log at $LOG" >&2; exit 1; }
  awk '
    /EXCEPTION CAUGHT BY|GLOBAL ERROR CAUGHT|Failed assertion|Another exception/ { hit=1 }
    hit && !/^flutter: #/ { print }
    /^flutter: *$/ { hit=0 }
  ' "$LOG" | head -"${1:-60}"
}

CMD="${1:-start}"
if [ "$TARGET" = all ] && [ "$CMD" != stop ]; then
  echo "--all only applies to stop" >&2; exit 2
fi
[ "$TARGET" != all ] && configure "$TARGET" "$MODE"

case "$CMD" in
  start)         start "${2:-/}" ;;
  build)         [ "$MODE" = release ] || { echo "build requires --release" >&2; exit 2; }
                 build_release ;;
  serve-release) configure "$TARGET" release; serve_release ;;
  wait)          wait_ready ;;
  url)           print_url "${2:-/}" ;;
  errors)        errors "${2:-60}" ;;
  stop)          stop ;;
  log)           tail -"${2:-40}" "$LOG" ;;
  *) echo "usage: $0 {start|build|serve-release|wait|url [path]|errors [n]|stop|log [n]} [--erp|--store|--all] [--release]" >&2; exit 2 ;;
esac
