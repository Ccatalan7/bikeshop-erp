#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This bootstrap is for macOS." >&2
  exit 64
fi

if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

brew bundle --file "$ROOT_DIR/Brewfile" --no-upgrade

export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
export PATH="$VOLTA_HOME/bin:/opt/homebrew/opt/libpq/bin:$PATH"

node_version="$(jq -r .node toolchain.json)"
npm_version="$(jq -r .npm toolchain.json)"
flutter_version="$(jq -r .flutter toolchain.json)"

volta install "node@$node_version" "npm@$npm_version"
fvm install "$flutter_version"
fvm use "$flutter_version" --force

npm ci
uv sync --project tools/invoice-parser-service

if ! docker info >/dev/null 2>&1 && command -v colima >/dev/null 2>&1; then
  colima start --cpu 4 --memory 8 --disk 60
fi

bash scripts/dev/doctor.sh
