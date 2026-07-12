#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is required; run the project bootstrap first" >&2
  exit 127
fi

mode="${1:-staged}"
common=(
  --config .gitleaks.toml
  --gitleaks-ignore-path .gitleaksignore
  --redact=100
  --no-banner
)

case "$mode" in
  staged)
    gitleaks git --staged "${common[@]}" .
    ;;
  working)
    gitleaks git --pre-commit "${common[@]}" .
    ;;
  history)
    gitleaks git --log-opts='--all' "${common[@]}" .
    ;;
  *)
    echo "Usage: $0 [staged|working|history]" >&2
    exit 64
    ;;
esac
