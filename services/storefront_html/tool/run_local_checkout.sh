#!/bin/bash
# The HTML storefront on http://localhost:4328 against the LOCAL Supabase
# stack, with the test store of local_checkout_seed.sql: the place to place
# orders, test Mercado Pago's hand-off and the customer session without
# touching production. Seeds first (idempotent), then serves.
#
#   bash services/storefront_html/tool/run_local_checkout.sh [--no-seed]
#
# Needs the local stack running (scripts/db/ensure_local.sh). Edge Functions
# (Mercado Pago, Google Places) are not served locally: the browser test
# answers them itself.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO"
if [[ "${1:-}" != "--no-seed" ]]; then
  bash scripts/db/query.sh local --file services/storefront_html/tool/local_checkout_seed.sql >/dev/null
fi
STATUS="$(bash scripts/supabase_cli.sh status -o env 2>/dev/null)"
API_URL="$(printf '%s\n' "$STATUS" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')"
ANON_KEY="$(printf '%s\n' "$STATUS" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')"
if [[ -z "$API_URL" || -z "$ANON_KEY" ]]; then
  echo "The local Supabase stack is not running (scripts/db/ensure_local.sh)." >&2
  exit 1
fi
PORT="${PORT:-4328}"
SUPABASE_URL="$API_URL" SUPABASE_PUBLISHABLE_KEY="$ANON_KEY" \
  STOREFRONT_TENANT_ID=7e570000-0000-4000-8000-000000000001 \
  STOREFRONT_ORIGIN="http://localhost:$PORT" PORT="$PORT" \
  exec bash services/storefront_html/run_local.sh
