#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
export PATH="$VOLTA_HOME/bin:/opt/homebrew/opt/libpq/bin:$HOME/.local/bin:$PATH"

mode="${1:-fast}"

bash scripts/dev/check_secrets.sh working
node -e "JSON.parse(require('fs').readFileSync('toolchain.json')); JSON.parse(require('fs').readFileSync('.fvmrc'))"
node scripts/ci/check_local_markdown_links.mjs
bash -n scripts/dev/*.sh scripts/bootstrap/*.sh scripts/supabase_cli.sh scripts/db/*.sh
bash test/scripts/supabase_cli_safety_test.sh
bash test/scripts/database_migration_workflow_test.sh
bash test/scripts/production_validation_manager_test.sh

if [[ "$mode" == "fast" ]]; then
  echo "Fast verification passed."
  exit 0
fi

scripts/dev/flutter.sh pub get
scripts/dev/flutter.sh analyze --no-fatal-infos --no-fatal-warnings lib test
scripts/dev/flutter.sh test
echo "Full application verification passed."
