#!/usr/bin/env bash
# Deprecated thin wrapper. `scripts/dev/web_preview.sh` is the single owner of
# preview lifecycle; this name survives only for muscle memory.
#
#   store_release_preview.sh start|build|serve|stop|url [path]
# maps to
#   web_preview.sh <cmd> --store --release   (serve → serve-release)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="${1:-start}"
shift || true
[ "$CMD" = serve ] && CMD=serve-release
exec bash "$HERE/web_preview.sh" "$CMD" "$@" --store --release
