#!/bin/bash
# Ficha HTML de prueba en http://localhost:4325 (sólo lectura, llave publicable
# del Llavero de macOS o de SUPABASE_PUBLISHABLE_KEY).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KEY="${SUPABASE_PUBLISHABLE_KEY:-$(security find-generic-password -w -s 'Vinabike ERP Supabase publishable key' -a supabase)}"
SUPABASE_PUBLISHABLE_KEY="$KEY" exec "$REPO/.fvm/flutter_sdk/bin/dart" \
  --packages="$REPO/.dart_tool/package_config.json" \
  "$REPO/tool/storefront_html_prototype/proto_server.dart" --repo "$REPO" --port "${PORT:-4325}"
