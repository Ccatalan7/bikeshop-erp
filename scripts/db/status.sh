#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cd "$DB_ROOT"

EXPECTED_PRODUCTION_REF="xzdvtzdqjeyqxnkqprtf"

print_status() {
  printf '%-24s %s\n' "$1" "$2"
}

credential_status() {
  local label="$1"
  local service="$2"
  local account="$3"
  local env_name="$4"
  local keychain_error=""
  local keychain_status=0

  if [[ -n "${!env_name:-}" ]]; then
    print_status "$label" "credential-ready (environment)"
    return
  fi

  if ! command -v security >/dev/null 2>&1; then
    print_status "$label" "inaccessible (no supported credential store)"
    return
  fi

  if keychain_error="$(
    security find-generic-password \
      -s "$service" \
      -a "$account" \
      2>&1 >/dev/null
  )"; then
    print_status "$label" "credential-ready (Keychain)"
    return
  else
    keychain_status=$?
  fi

  if printf '%s\n' "$keychain_error" |
    grep -Eiq \
      'SecKeychainSearchCreateFromAttributes|interaction.*not allowed|not permitted|denied|keychain.*locked'; then
    print_status "$label" "inaccessible (Keychain access denied)"
  elif [[ "$keychain_status" -eq 44 ]] ||
    printf '%s\n' "$keychain_error" |
      grep -Eiq 'specified item could not be found|item not found'; then
    print_status "$label" "missing"
  else
    print_status "$label" "inaccessible (Keychain error)"
  fi
}

classify_cli_error() {
  local error_text="$1"
  if printf '%s\n' "$error_text" |
    grep -Eiq 'not logged in|access token.*(missing|invalid)|unauthorized|(^|[^0-9])401([^0-9]|$)'; then
    printf '%s\n' "missing or invalid"
  else
    printf '%s\n' "inaccessible"
  fi
}

if cli_version="$(run_supabase_cli --version 2>/dev/null)"; then
  print_status "Supabase CLI" "$cli_version (telemetry disabled)"
else
  print_status "Supabase CLI" "unavailable"
fi

linked_ref="$(tr -d '[:space:]' <supabase/.temp/project-ref 2>/dev/null || true)"
if [[ "$linked_ref" == "$EXPECTED_PRODUCTION_REF" ]]; then
  print_status "Linked project" "$linked_ref (production)"
elif [[ -n "$linked_ref" ]]; then
  print_status "Linked project" "$linked_ref (unexpected)"
else
  print_status "Linked project" "missing"
fi

if run_supabase_cli status >/dev/null 2>&1; then
  print_status "Local stack" "running"
  print_status "Local database" \
    "$(local_db_url | sed -E 's#(://[^:]+:)[^@]+@#\1<redacted>@#')"
else
  print_status "Local stack" "stopped"
fi

credential_status \
  "CLI credential" \
  "Supabase CLI" \
  "supabase" \
  "SUPABASE_ACCESS_TOKEN"
credential_status \
  "Production DB" \
  "Vinabike ERP Supabase database password" \
  "postgres" \
  "SUPABASE_DB_PASSWORD"
credential_status \
  "Publishable key" \
  "Vinabike ERP Supabase publishable key" \
  "supabase" \
  "SUPABASE_PUBLISHABLE_KEY"
credential_status \
  "Secret key" \
  "Vinabike ERP Supabase secret key" \
  "supabase" \
  "SUPABASE_SECRET_KEY"
credential_status \
  "Staging DB" \
  "Vinabike ERP Supabase staging database password" \
  "postgres" \
  "SUPABASE_STAGING_DB_PASSWORD"
credential_status \
  "Staging ref" \
  "Vinabike ERP Supabase staging project ref" \
  "supabase" \
  "SUPABASE_STAGING_PROJECT_REF"
credential_status \
  "Staging publishable" \
  "Vinabike ERP Supabase staging publishable key" \
  "supabase" \
  "SUPABASE_STAGING_PUBLISHABLE_KEY"

projects_error=""
projects_json=""
if projects_json="$(run_supabase_cli projects list --output json 2>&1)"; then
  if command -v jq >/dev/null 2>&1 &&
    jq -e --arg project_ref "$EXPECTED_PRODUCTION_REF" \
      '.[]? | select(.ref == $project_ref)' \
      >/dev/null 2>&1 <<<"$projects_json"; then
    print_status "CLI authentication" "authenticated (production accessible)"

    keys_error=""
    keys_json=""
    if keys_json="$(
      run_supabase_cli projects api-keys \
        --project-ref "$EXPECTED_PRODUCTION_REF" \
        --output json \
        2>&1
    )"; then
      publishable_state="publishable-missing"
      secret_state="secret-missing"
      if jq -e '.[]? | select(.type == "publishable")' \
        >/dev/null 2>&1 <<<"$keys_json"; then
        publishable_state="publishable-ready"
      fi
      if jq -e '.[]? | select(.type == "secret")' \
        >/dev/null 2>&1 <<<"$keys_json"; then
        secret_state="secret-ready"
      fi
      print_status "Project API keys" "$publishable_state, $secret_state"
    else
      keys_error="$keys_json"
      print_status "Project API keys" "$(classify_cli_error "$keys_error")"
    fi
  elif command -v jq >/dev/null 2>&1; then
    print_status "CLI authentication" "authenticated (production inaccessible)"
    print_status "Project API keys" "inaccessible"
  else
    print_status "CLI authentication" "inaccessible (jq unavailable)"
    print_status "Project API keys" "inaccessible"
  fi
else
  projects_error="$projects_json"
  print_status "CLI authentication" "$(classify_cli_error "$projects_error")"
  print_status "Project API keys" "inaccessible"
fi
