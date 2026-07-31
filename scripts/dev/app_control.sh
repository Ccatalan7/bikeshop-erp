#!/bin/bash
# Eyes and hands on the running macOS debug app, for agent verification.
#
#   app_control.sh shot [out.png]        # exact rendered frame (VM service)
#   app_control.sh window [out.png]      # OS screenshot of the app window
#   app_control.sh click X Y [wait]      # tap in FRAME coordinates
#   app_control.sh scroll X Y [lines]    # scroll wheel at that point
#   app_control.sh drag X Y X2 Y2        # press, move, release
#   app_control.sh read [--filter text]   # semantics tree, optionally filtered
#   app_control.sh find --key|--label X  # live, hittable targets
#   app_control.sh tap  --key|--label X  # resolve and tap one live target
#   app_control.sh type "texto"
#   app_control.sh key <keycode>         # 36=return 53=esc 48=tab 51=delete
#   app_control.sh geometry              # pid + window frame + frame size
#
# Read docs/development/AGENT_MACOS_APP_CONTROL.md first.
#
# Why it is built this way:
#   - `shot` uses the Dart VM service `_flutter.screenshot`, so it returns the
#     app's own rendered frame — no Screen Recording permission needed and no
#     other window can occlude it.
#   - Coordinates are the physical pixels read from `shot`. The app backend
#     divides them by the live device-pixel ratio before creating logical
#     PointerEvents; the OS backend maps them into screen coordinates.
#   - Input is posted as CGEvents. AppleScript `click at` does not reach a
#     Flutter window.
#   - Everything targets the DEBUG app by executable path. Never target by
#     process name: an installed old build shares the name and will silently
#     receive the clicks.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="$REPO_ROOT/.tmp/dev-tools"
MOUSE="$TOOLS/mouse"
LOG="${NATIVE_SESSION_LOG:-$REPO_ROOT/.tmp/native-session/run.log}"
DEBUG_APP_GLOB="build/macos/Build/Products/Debug/vinabike_erp.app/Contents/MacOS/vinabike_erp"

pid="$(pgrep -f "$DEBUG_APP_GLOB" | head -1)"
if [ -z "$pid" ]; then
  echo "la app debug no está corriendo. Usa scripts/dev/native_session.sh start" >&2
  exit 1
fi

ensure_mouse() {
  [ -x "$MOUSE" ] && return 0
  mkdir -p "$TOOLS"
  xcrun -sdk macosx swiftc -O "$REPO_ROOT/scripts/dev/mouse_events.swift" -o "$MOUSE" >/dev/null || {
    echo "no pude compilar el driver de mouse (¿faltan las Command Line Tools?)" >&2
    exit 1
  }
}

window_frame() { # -> "X Y W H" (screen points)
  osascript <<EOF 2>/dev/null
tell application "System Events" to tell (first process whose unix id is $pid)
  set p to position of window 1
  set s to size of window 1
  return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
end tell
EOF
}

vm_uri() {
  grep -a "Dart VM Service on macOS is available at:" "$LOG" 2>/dev/null |
    tail -1 | sed 's/.*at: //' | tr -d ' \r\n'
}

# Send a gesture through the app's own debug input extensions.
# Returns non-zero when they are unavailable (release build, older build, no VM
# service) so the caller can fall back to the CGEvent driver.
vm_input() { # vm_input <verb> <x> <y> [a] [b]
  local uri
  uri="$(vm_uri)"
  [ -z "$uri" ] && return 1
  python3 - "$uri" "$@" <<'PY'
import json, sys, urllib.parse, urllib.request
uri = sys.argv[1].strip().rstrip('/')
verb, x, y = sys.argv[2], sys.argv[3], sys.argv[4]
a = sys.argv[5] if len(sys.argv) > 5 else None
b = sys.argv[6] if len(sys.argv) > 6 else None

def call(method, **params):
    url = f"{uri}/{method}?{urllib.parse.urlencode(params)}" if params else f"{uri}/{method}"
    with urllib.request.urlopen(url, timeout=25) as response:
        return json.load(response)

try:
    isolate = call('getVM')['result']['isolates'][0]['id']
    available = call('getIsolate', isolateId=isolate)['result'].get('extensionRPCs', [])
    required = {'ext.vinabike.input.info', 'ext.vinabike.input.tap'}
    if not required.issubset(available):
        sys.exit(1)                      # build predates the channel
    info = call('ext.vinabike.input.info', isolateId=isolate).get('result', {})
    dpr = float(info.get('devicePixelRatio') or 0)
    if not (dpr > 0):
        sys.exit(1)
    logical_x, logical_y = float(x) / dpr, float(y) / dpr
    if verb == 'click':
        call('ext.vinabike.input.tap', isolateId=isolate,
             x=logical_x, y=logical_y)
    elif verb == 'scroll':
        # The CGEvent driver takes "lines"; positive scrolls the content up.
        # Flutter wants pixels of scroll delta, inverted.
        call('ext.vinabike.input.scroll', isolateId=isolate,
             x=logical_x, y=logical_y,
             dy=-float(a if a is not None else -5) * 40)
    elif verb == 'drag':
        if a is None or b is None:
            sys.exit(1)
        call('ext.vinabike.input.drag', isolateId=isolate,
             x=logical_x, y=logical_y,
             x2=float(a) / dpr, y2=float(b) / dpr)
    else:
        sys.exit(1)
except SystemExit:
    raise
except Exception:
    sys.exit(1)
PY
}

frame_shot() { # frame_shot <out.png> -> prints "W H"
  local out="$1" uri
  uri="$(vm_uri)"
  [ -z "$uri" ] && { echo "sin VM service en el log" >&2; return 1; }
  python3 - "$uri" "$out" <<'PY'
import base64, json, sys, urllib.parse, urllib.request
uri, out = sys.argv[1].strip().rstrip('/'), sys.argv[2]
def call(method, **params):
    query = urllib.parse.urlencode(params)
    url = f"{uri}/{method}?{query}" if query else f"{uri}/{method}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)
isolate = call('getVM')['result']['isolates'][0]['id']
png = call('_flutter.screenshot', isolateId=isolate)['result']['screenshot']
raw = base64.b64decode(png)
open(out, 'wb').write(raw)
import struct
width, height = struct.unpack('>II', raw[16:24])
print(f"{width} {height}")
PY
}

focus() {
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1
  sleep 0.4
}

# frame_to_screen X Y -> "SX SY"
frame_to_screen() {
  local fx="$1" fy="$2" tmp
  tmp="$(mktemp -t frameshot).png"
  read -r fw fh < <(frame_shot "$tmp") || exit 1
  rm -f "$tmp"
  read -r wx wy ww wh < <(window_frame)
  # The frame is rendered at device pixels (DPR 1 or 2 depending on the
  # display), so derive the scale instead of assuming it; what is left of the
  # window height after the scaled frame is the title bar.
  python3 -c "
scale = $ww / $fw
title = $wh - $fh * scale
print(int($wx + $fx * scale), int($wy + max(title, 0) + $fy * scale))"
}

case "${1:-}" in
  shot)
    out="${2:-$REPO_ROOT/.tmp/app-shot.png}"
    read -r w h < <(frame_shot "$out") || exit 1
    echo "$out (${w}x${h})"
    ;;

  window)
    out="${2:-$REPO_ROOT/.tmp/app-window.png}"
    read -r wx wy ww wh < <(window_frame)
    screencapture -x -o -R "$wx,$wy,$ww,$wh" "$out"
    echo "$out (${ww}x${wh} @ $wx,$wy)"
    ;;

  geometry)
    read -r wx wy ww wh < <(window_frame)
    tmp="$(mktemp -t frameshot).png"
    read -r fw fh < <(frame_shot "$tmp") && rm -f "$tmp"
    echo "pid $pid · ventana ${ww}x${wh} @ $wx,$wy · frame ${fw}x${fh}"
    ;;

  # ── Tocar por identidad, no por píxel ─────────────────────────────────────
  #
  # `click X Y` obliga a leer coordenadas de una captura, y captura y clic no
  # viven en el mismo espacio: el frame llega a 1360x757 o a 3024x1632 según
  # devicePixelRatio y tamaño de ventana. Un reinicio basta para que toda
  # coordenada guardada apunte a otro lado, y el clic cae donde no debe — que
  # en una app contra producción es exactamente el accidente del 30/07.
  #
  #   app_control.sh find  --key payroll-confirm-week
  #   app_control.sh find  --label "Confirmar semana"
  #   app_control.sh tap   --key payroll-confirm-week
  #
  # `tap` se niega si hay más de un candidato: tocar "alguno" es como se
  # dispara una acción que nadie pidió. Para desempatar, `--index N`.
  # Lee la pantalla como la lee un lector de pantalla: estructura, texto y
  # ESTADO (deshabilitado, seleccionado, con foco, abierto/cerrado). Una
  # captura dice cómo se ve; esto dice qué está. Y cuesta texto, no una imagen.
  #
  #   app_control.sh read
  #   app_control.sh read --filter "confirmar"
  read)
    shift
    filter=""
    if [ $# -gt 0 ]; then
      if [ "$1" != "--filter" ] || [ $# -ne 2 ] || [ -z "${2:-}" ]; then
        echo "uso: app_control.sh read [--filter texto]" >&2
        exit 2
      fi
      filter="$2"
    fi
    uri="$(vm_uri)"
    [ -n "$uri" ] || { echo "sin VM service en el log" >&2; exit 1; }
    python3 - "$uri" "$filter" <<'PY'
import json, sys, urllib.parse, urllib.request
uri, filter_text = sys.argv[1].strip().rstrip('/'), sys.argv[2]

def call(name, **params):
    query = urllib.parse.urlencode({k: v for k, v in params.items() if v != ''})
    url = f"{uri}/{name}?{query}" if query else f"{uri}/{name}"
    with urllib.request.urlopen(url, timeout=40) as response:
        return json.load(response)

isolate = call('getVM')['result']['isolates'][0]['id']
available = call('getIsolate', isolateId=isolate)['result'].get('extensionRPCs', [])
if 'ext.vinabike.input.tree' not in available:
    sys.exit('el build corriendo no expone la lectura de pantalla: reinicia la sesión')
try:
    payload = call('ext.vinabike.input.tree', isolateId=isolate,
                   filter=filter_text)['result']
except urllib.error.HTTPError as error:
    sys.exit(error.read().decode())
for line in payload.get('lines', []):
    print(line)
PY
    ;;

  find|tap)
    verb="$1"; shift
    key=""; label=""; index=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --key|--label|--index)
          option="$1"
          if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
            echo "$option requiere un valor" >&2
            exit 2
          fi
          case "$option" in
            --key) key="$2" ;;
            --label) label="$2" ;;
            --index) index="$2" ;;
          esac
          shift 2
          ;;
        *) echo "argumento desconocido: $1" >&2; exit 2 ;;
      esac
    done
    [ -n "$key$label" ] || { echo "usa --key o --label" >&2; exit 2; }
    method="ext.vinabike.input.find"
    [ "$verb" = tap ] && method="ext.vinabike.input.tapOn"
    uri="$(vm_uri)"
    [ -n "$uri" ] || { echo "sin VM service en el log" >&2; exit 1; }
    python3 - "$uri" "$method" "$key" "$label" "$index" <<'PY'
import json, sys, urllib.parse, urllib.request
uri, method, key, label, index = (a.strip() for a in sys.argv[1:6])
uri = uri.rstrip('/')

def call(name, **params):
    query = urllib.parse.urlencode({k: v for k, v in params.items() if v != ''})
    url = f"{uri}/{name}?{query}" if query else f"{uri}/{name}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)

isolate = call('getVM')['result']['isolates'][0]['id']
available = call('getIsolate', isolateId=isolate)['result'].get('extensionRPCs', [])
if method not in available:
    sys.exit("el build corriendo no expone %s: reinicia la sesión" % method)
try:
    result = call(method, isolateId=isolate, key=key, label=label, index=index)
except urllib.error.HTTPError as error:
    sys.exit(error.read().decode())
payload = result.get('result', result)
if payload.get('ok') is not True:
    sys.exit(str(payload.get('error') or 'la app rechazó la solicitud'))
for candidate_index, match in enumerate(payload.get('matches', [payload.get('tapped')])):
    if not match:
        continue
    print("[%d] %-34s %6.0f,%-6.0f %4.0fx%-4.0f  %-18s %s" % (
        candidate_index,
        (match.get('key') or '—')[:34],
        match['centerX'], match['centerY'],
        match['width'], match['height'],
        match.get('widget', ''),
        match.get('label') or '',
    ))
PY
    ;;

  click|scroll|drag)
    case "$1" in
      click) [ $# -ge 3 ] || { echo "uso: app_control.sh click X Y" >&2; exit 2; } ;;
      scroll) [ $# -ge 3 ] || { echo "uso: app_control.sh scroll X Y [líneas]" >&2; exit 2; } ;;
      drag) [ $# -ge 5 ] || { echo "uso: app_control.sh drag X Y X2 Y2" >&2; exit 2; } ;;
    esac
    # DEFAULT: deliver the gesture INSIDE the app through the debug service
    # extensions in `lib/dev/agent_input.dart`. The owner's cursor never moves,
    # the window does not need focus, and an installed build cannot intercept
    # the click, because nothing is aimed at a screen coordinate.
    #
    # `APP_CONTROL_BACKEND=os` forces the old CGEvent driver — real system
    # events. Keep it for verifying the OS event path itself (a window that
    # receives no events at all), which synthetic pointers cannot prove.
    if [ "${APP_CONTROL_BACKEND:-app}" != "os" ] && vm_input "$@"; then
      :
    else
    ensure_mouse
    focus
    read -r sx sy < <(frame_to_screen "$2" "$3")
    case "$1" in
      click)  "$MOUSE" "$sx" "$sy" ;;
      scroll) "$MOUSE" "$sx" "$sy" scroll "${4:--5}" ;;
      drag)
        read -r sx2 sy2 < <(frame_to_screen "$4" "$5")
        "$MOUSE" "$sx" "$sy" drag "$sx2" "$sy2"
        ;;
    esac
    fi
    # Settle time only. The old `${6:-${4:-1}}` fell back to $4, which is a
    # DESTINATION COORDINATE for drag and the scroll amount for scroll — so
    # `drag 600 831 1300 831` slept 1300 seconds and looked like a hang.
    # The settle argument sits in a different position per verb, so read it
    # from a named variable instead of guessing by index.
    settle="${APP_CONTROL_SETTLE:-1}"
    case "$settle" in
      ''|*[!0-9.]*) settle=1 ;;
    esac
    sleep "$settle"
    ;;

  type)
    focus
    osascript -e "tell application \"System Events\" to keystroke \"$2\"" >/dev/null 2>&1
    ;;

  key)
    focus
    osascript -e "tell application \"System Events\" to key code $2" >/dev/null 2>&1
    ;;

  *)
    sed -n '2,16p' "$0"
    exit 1
    ;;
esac
