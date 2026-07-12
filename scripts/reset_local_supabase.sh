#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash scripts/db/ensure_local.sh --reset
bash scripts/db/test.sh

echo
echo "Local Supabase DB bootstrapped and smoke-tested."
