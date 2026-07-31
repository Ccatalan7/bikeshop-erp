#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build/web_store}"
BUNDLE="$BUILD_DIR/main.dart.js"
# These are regression canaries, not a requirement that every legitimate
# feature fit inside an old snapshot forever. The defaults intentionally keep
# roughly 8-14% runway over the July 2026 storefront while still catching
# accidental ERP imports and package-scale jumps.
MAX_RAW_BYTES="${STOREFRONT_MAX_RAW_BYTES:-6000000}"
MAX_GZIP_BYTES="${STOREFRONT_MAX_GZIP_BYTES:-1700000}"
MAX_DEFERRED_TOTAL_BYTES="${STOREFRONT_MAX_DEFERRED_TOTAL_BYTES:-3600000}"
MAX_DEFERRED_CHUNK_BYTES="${STOREFRONT_MAX_DEFERRED_CHUNK_BYTES:-1600000}"

for budget in \
    "$MAX_RAW_BYTES" \
    "$MAX_GZIP_BYTES" \
    "$MAX_DEFERRED_TOTAL_BYTES" \
    "$MAX_DEFERRED_CHUNK_BYTES"; do
    if [[ ! "$budget" =~ ^[1-9][0-9]*$ ]]; then
        echo "Storefront bundle budgets must be positive integers." >&2
        exit 64
    fi
done

if [ ! -f "$BUNDLE" ]; then
    echo "Storefront bundle not found: $BUNDLE" >&2
    exit 66
fi

RAW_BYTES=$(wc -c < "$BUNDLE" | tr -d '[:space:]')
GZIP_BYTES=$(gzip -9 -c "$BUNDLE" | wc -c | tr -d '[:space:]')
PART_COUNT=$(find "$BUILD_DIR" -maxdepth 1 -type f -name 'main.dart.js_*.part.js' | wc -l | tr -d '[:space:]')
PART_TOTAL_BYTES=0
PART_MAX_BYTES=0
while IFS= read -r -d '' part; do
    part_bytes=$(wc -c < "$part" | tr -d '[:space:]')
    PART_TOTAL_BYTES=$((PART_TOTAL_BYTES + part_bytes))
    if [ "$part_bytes" -gt "$PART_MAX_BYTES" ]; then
        PART_MAX_BYTES="$part_bytes"
    fi
done < <(find "$BUILD_DIR" -maxdepth 1 -type f -name 'main.dart.js_*.part.js' -print0)

echo "Storefront bundle budget:"
echo "  main.dart.js raw:  $RAW_BYTES / $MAX_RAW_BYTES bytes"
echo "  main.dart.js gzip: $GZIP_BYTES / $MAX_GZIP_BYTES bytes"
echo "  deferred chunks:   $PART_COUNT"
echo "  deferred raw total: $PART_TOTAL_BYTES / $MAX_DEFERRED_TOTAL_BYTES bytes"
echo "  largest deferred:   $PART_MAX_BYTES / $MAX_DEFERRED_CHUNK_BYTES bytes"

if [ "$RAW_BYTES" -gt "$MAX_RAW_BYTES" ]; then
    echo "Storefront raw bundle exceeds its budget." >&2
    exit 1
fi

if [ "$GZIP_BYTES" -gt "$MAX_GZIP_BYTES" ]; then
    echo "Storefront gzip bundle exceeds its budget." >&2
    exit 1
fi

if [ "$PART_TOTAL_BYTES" -gt "$MAX_DEFERRED_TOTAL_BYTES" ]; then
    echo "Storefront deferred bundle total exceeds its budget." >&2
    exit 1
fi

if [ "$PART_MAX_BYTES" -gt "$MAX_DEFERRED_CHUNK_BYTES" ]; then
    echo "A storefront deferred chunk exceeds its budget." >&2
    exit 1
fi
