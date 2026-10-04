#!/bin/bash
# HTML storefront on http://localhost:4325 against production, read-only: the
# publishable key from the macOS Keychain (or SUPABASE_PUBLISHABLE_KEY), and the
# repository's assets/ served the way Firebase Hosting serves them.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KEY="${SUPABASE_PUBLISHABLE_KEY:-$(security find-generic-password -w -s 'Vinabike ERP Supabase publishable key' -a supabase)}"
cd "$REPO/services/storefront_html"
"$REPO/.fvm/flutter_sdk/bin/dart" pub get --offline >/dev/null 2>&1 || "$REPO/.fvm/flutter_sdk/bin/dart" pub get >/dev/null
SUPABASE_PUBLISHABLE_KEY="$KEY" STOREFRONT_ASSETS_DIR="$REPO" PORT="${PORT:-4325}" \
  exec "$REPO/.fvm/flutter_sdk/bin/dart" run bin/server.dart
