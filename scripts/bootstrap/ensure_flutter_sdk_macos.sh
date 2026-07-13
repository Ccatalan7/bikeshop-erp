#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This repair command is for macOS." >&2
  exit 64
fi

if ! command -v fvm >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Run the full macOS bootstrap instead:" >&2
    echo "  bash scripts/bootstrap/bootstrap_macos.sh" >&2
    exit 127
  fi
  brew install fvm
fi

flutter_version="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)"
if [[ -z "$flutter_version" ]]; then
  echo "Could not read the Flutter version from .fvmrc." >&2
  exit 65
fi

fvm install "$flutter_version"
fvm use "$flutter_version" --force
fvm flutter pub get --enforce-lockfile

test -x .fvm/flutter_sdk/bin/flutter
echo "Flutter $flutter_version is ready. Reload the VS Code window."
