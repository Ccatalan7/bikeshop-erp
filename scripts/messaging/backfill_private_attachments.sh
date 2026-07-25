#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PROJECT_REF="xzdvtzdqjeyqxnkqprtf"
secret_key="${SUPABASE_SECRET_KEY:-}"

if [[ -z "$secret_key" ]] && command -v security >/dev/null 2>&1; then
  secret_key="$(security find-generic-password \
    -s 'Vinabike ERP Supabase secret key' \
    -a supabase -w 2>/dev/null || true)"
fi

if [[ -z "$secret_key" ]]; then
  echo "Missing Supabase production secret key in the process environment or macOS Keychain." >&2
  exit 64
fi

exec env \
  SUPABASE_SECRET_KEY="$secret_key" \
  SUPABASE_URL="https://${PROJECT_REF}.supabase.co" \
  DENO_NO_UPDATE_CHECK=1 \
  deno run \
    --allow-env=SUPABASE_SECRET_KEY,SUPABASE_URL,VINABIKE_STORAGE_BACKFILL_CONFIRM \
    --allow-net="${PROJECT_REF}.supabase.co" \
    --allow-write=.tmp/messaging-attachments \
    scripts/messaging/backfill_private_attachments.ts "$@"
