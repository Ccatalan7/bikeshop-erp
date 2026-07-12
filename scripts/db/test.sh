#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

bash scripts/db/ensure_local.sh

files=()
if [[ "$#" -eq 0 ]]; then
  files=(supabase/tests/*.sql)
else
  for selector in "$@"; do
    selector="${selector%.sql}"
    matches=(supabase/tests/*"$selector"*.sql)
    [[ -e "${matches[0]}" ]] || {
      echo "No pgTAP test matches '$selector'" >&2
      exit 64
    }
    files+=("${matches[@]}")
  done
fi

printf 'Running %d pgTAP file(s):\n' "${#files[@]}"
printf '  %s\n' "${files[@]}"
mkdir -p .tmp/db
log_file=".tmp/db/pgtap-$(date +%Y%m%d-%H%M%S).log"
if [[ "${VINABIKE_DB_VERBOSE:-}" == "1" ]]; then
  supabase test db --local "${files[@]}" 2>&1 | tee "$log_file"
elif supabase test db --local "${files[@]}" >"$log_file" 2>&1; then
  rg '(^.*\.sql \.\. ok$|All tests successful|^Files=|^Result:)' "$log_file" || tail -20 "$log_file"
  echo "Full pgTAP output: $log_file"
else
  status=$?
  echo "pgTAP failed; last 120 log lines:" >&2
  tail -120 "$log_file" >&2
  exit "$status"
fi
