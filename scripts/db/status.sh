#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cd "$DB_ROOT"
printf '%-22s %s\n' "Supabase CLI" "$(supabase --version)"
printf '%-22s %s\n' "Linked project" "$(tr -d '[:space:]' <supabase/.temp/project-ref 2>/dev/null || echo none)"
if supabase status >/dev/null 2>&1; then
  printf '%-22s %s\n' "Local stack" running
  printf '%-22s %s\n' "Local database" "$(local_db_url | sed -E 's#(://[^:]+:)[^@]+@#\1<redacted>@#')"
else
  printf '%-22s %s\n' "Local stack" stopped
fi
for entry in \
  "Production DB|Vinabike ERP Supabase database password|postgres" \
  "Staging DB|Vinabike ERP Supabase staging database password|postgres" \
  "Staging ref|Vinabike ERP Supabase staging project ref|supabase"; do
  IFS='|' read -r label service account <<<"$entry"
  if security find-generic-password -s "$service" -a "$account" >/dev/null 2>&1; then
    printf '%-22s %s\n' "$label" credential-ready
  else
    printf '%-22s %s\n' "$label" missing
  fi
done
