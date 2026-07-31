#!/usr/bin/env bash
# Guard the dedicated VS Code Chrome-debug origin before Flutter starts.
#
# The VS Code launch owns :54332. The normal preview lifecycle keeps :54331,
# so release verification and an interactive debugger never reuse each
# other's service worker, storage, bootstrap, or module graph.
set -euo pipefail

PORT="${VINABIKE_STORE_CHROME_DEBUG_PORT:-54332}"
LISTENER="$(lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1 || true)"

if [ -z "$LISTENER" ]; then
  echo "Vinabike Store Chrome debug port $PORT is ready."
  exit 0
fi

echo "Vinabike Store Chrome debug port $PORT is still occupied:" >&2
ps -p "$LISTENER" -ww -o pid=,command= >&2 || true
echo >&2
echo "Stop the previous VS Code debug session with Shift+F5, then start again." >&2
echo "The preflight refuses to select a random port or kill an unverified process." >&2
exit 1
