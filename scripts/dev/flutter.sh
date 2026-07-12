#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if command -v fvm >/dev/null 2>&1; then
  exec fvm flutter "$@"
fi

if command -v flutter >/dev/null 2>&1; then
  exec flutter "$@"
fi

echo "Flutter is unavailable. Run 'just bootstrap' first." >&2
exit 127
