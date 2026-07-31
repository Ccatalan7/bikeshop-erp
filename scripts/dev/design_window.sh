#!/bin/bash
# Reads the Claude **Design** window on this Mac, so an agent can compare the
# implementation against the authoritative mockups without asking for
# screenshots.
#
#   design_window.sh shot [out.png]        # capture the Design window
#   design_window.sh scroll <lines> [out]  # scroll canvas, then capture
#   design_window.sh click X Y [out]       # click in window coordinates
#   design_window.sh pages [out]           # open the page selector and capture
#   design_window.sh geometry
#
# Read docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md first.
#
# Boundaries that must stay:
#   - It captures ONLY the Design window frame. Never a full-screen grab: the
#     desktop holds unrelated private windows (mail, chats) that an agent has
#     no business reading.
#   - Read-only by default. Typing into Design's composer or sending a message
#     is a message on the owner's behalf and needs explicit permission.
#   - `Design` is a window of the Claude app, not a separate process.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="$REPO_ROOT/.tmp/dev-tools"
MOUSE="$TOOLS/mouse"
WINDOW_NAME="${DESIGN_WINDOW_NAME:-Design}"

geometry() {
  osascript <<EOF 2>/dev/null
tell application "System Events" to tell process "Claude"
  set w to (first window whose name is "$WINDOW_NAME")
  set p to position of w
  set s to size of w
  return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
end tell
EOF
}

raise() {
  osascript -e "tell application \"System Events\" to tell process \"Claude\" to perform action \"AXRaise\" of (first window whose name is \"$WINDOW_NAME\")" >/dev/null 2>&1
  osascript -e 'tell application "System Events" to set frontmost of process "Claude" to true' >/dev/null 2>&1
  sleep 0.8
}

ensure_mouse() {
  [ -x "$MOUSE" ] && return 0
  mkdir -p "$TOOLS"
  xcrun -sdk macosx swiftc -O "$REPO_ROOT/scripts/dev/mouse_events.swift" -o "$MOUSE" >/dev/null
}

capture() { # capture <out>
  read -r wx wy ww wh < <(geometry)
  [ -z "${wh:-}" ] && { echo "no encuentro la ventana '$WINDOW_NAME'" >&2; exit 1; }
  screencapture -x -o -R "$wx,$wy,$ww,$wh" "$1"
  echo "$1 (${ww}x${wh})"
}

case "${1:-}" in
  geometry) geometry ;;

  shot)
    raise
    capture "${2:-$REPO_ROOT/.tmp/design.png}"
    ;;

  scroll)
    ensure_mouse; raise
    read -r wx wy ww wh < <(geometry)
    # canvas centre: the right two thirds of the window
    "$MOUSE" $(( wx + ww * 3 / 4 )) $(( wy + wh / 2 )) scroll "${2:--8}"
    sleep 0.7
    capture "${3:-$REPO_ROOT/.tmp/design.png}"
    ;;

  click)
    ensure_mouse; raise
    read -r wx wy ww wh < <(geometry)
    "$MOUSE" $(( wx + $2 )) $(( wy + $3 ))
    sleep 1.2
    capture "${4:-$REPO_ROOT/.tmp/design.png}"
    ;;

  pages)
    # The page selector sits under the document title, top-left of the canvas.
    ensure_mouse; raise
    read -r wx wy ww wh < <(geometry)
    "$MOUSE" $(( wx + 550 )) $(( wy + 55 ))
    sleep 1.4
    capture "${2:-$REPO_ROOT/.tmp/design-pages.png}"
    echo "(Esc para cerrar: osascript -e 'tell application \"System Events\" to key code 53')"
    ;;

  *)
    sed -n '2,15p' "$0"
    exit 1
    ;;
esac
