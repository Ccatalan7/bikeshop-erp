#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

staging_url="${SUPABASE_STAGING_URL:-https://bczzjhjrpmtpgwdvlbut.supabase.co}"
publishable_key="${SUPABASE_STAGING_PUBLISHABLE_KEY:-}"
e2e_email="${E2E_EMAIL:-e2e-agent@staging.vinabike.invalid}"
e2e_password="${E2E_PASSWORD:-}"

if command -v security >/dev/null 2>&1; then
  [[ -n "$publishable_key" ]] || publishable_key="$(security find-generic-password \
    -s 'Vinabike ERP Supabase staging publishable key' -a supabase -w 2>/dev/null || true)"
  [[ -n "$e2e_password" ]] || e2e_password="$(security find-generic-password \
    -s 'Vinabike ERP staging E2E password' -a "$e2e_email" -w 2>/dev/null || true)"
fi

[[ -n "$publishable_key" ]] || {
  echo 'Missing SUPABASE_STAGING_PUBLISHABLE_KEY or staging Keychain credential' >&2
  exit 64
}
[[ -n "$e2e_password" ]] || {
  echo 'Missing E2E_PASSWORD or staging E2E Keychain credential' >&2
  exit 64
}

if [[ "${E2E_SKIP_BUILD:-0}" != 1 ]]; then
  scripts/dev/flutter.sh build web --release --pwa-strategy=none --no-wasm-dry-run \
    -t lib/main.dart \
    -o build/web_erp \
    --dart-define="SUPABASE_URL=$staging_url" \
    --dart-define="SUPABASE_ANON_KEY=$publishable_key"
fi

export E2E_BASE_URL="${E2E_BASE_URL:-http://127.0.0.1:4173}"
export E2E_EMAIL="$e2e_email"
export E2E_PASSWORD="$e2e_password"

exec npm run e2e
