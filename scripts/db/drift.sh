#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

left="${1:-local}"
right="${2:-staging}"
for environment in "$left" "$right"; do
  [[ "$environment" =~ ^(local|staging|production)$ ]] || {
    echo "Environment must be local, staging or production" >&2
    exit 64
  }
done

mkdir -p .tmp/db
timestamp="$(date +%Y%m%d-%H%M%S)"
left_file=".tmp/db/schema-manifest-$left-$timestamp.csv"
right_file=".tmp/db/schema-manifest-$right-$timestamp.csv"
diff_file=".tmp/db/schema-drift-$left-$right-$timestamp.diff"
manifest="supabase/manual_checks/diagnostics/schema_manifest.sql"

bash scripts/db/query.sh "$left" --file "$manifest" --format csv >"$left_file"
bash scripts/db/query.sh "$right" --file "$manifest" --format csv >"$right_file"

if diff -u "$left_file" "$right_file" >"$diff_file"; then
  echo "Schema drift: none ($left == $right)."
  exit 0
fi

node scripts/db/drift_summary.mjs "$left_file" "$right_file" "$left" "$right" || true
echo "Full manifests and diff: $left_file, $right_file, $diff_file"

[[ "${VINABIKE_DRIFT_FAIL:-}" == "1" ]] && exit 2
exit 0
