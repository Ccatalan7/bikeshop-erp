#!/bin/bash
# Eyes and hands on the running macOS debug app, for agent verification.
#
#   app_control.sh shot [out.png]        # exact rendered frame (VM service)
#   app_control.sh window [out.png]      # OS screenshot of the app window
#   app_control.sh click X Y [wait]      # tap in FRAME coordinates
#   app_control.sh scroll X Y [lines]    # scroll wheel at that point
#   app_control.sh drag X Y X2 Y2        # press, move, release
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
#   - Click coordinates are the SAME ones you read off `shot`. The window is
#     larger than the frame (title bar + platform scaling), so this script
#     derives the mapping instead of letting the caller guess it.
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
    if 'ext.vinabike.input.tap' not in available:
        sys.exit(1)                      # build predates the channel
    if verb == 'click':
        call('ext.vinabike.input.tap', isolateId=isolate, x=x, y=y)
    elif verb == 'scroll':
        # The CGEvent driver takes "lines"; positive scrolls the content up.
        # Flutter wants pixels of scroll delta, inverted.
        call('ext.vinabike.input.scroll', isolateId=isolate, x=x, y=y,
             dy=-float(a if a is not None else -5) * 40)
    elif verb == 'drag':
        call('ext.vinabike.input.drag', isolateId=isolate, x=x, y=y, x2=a, y2=b)
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

  click|scroll|drag)
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
