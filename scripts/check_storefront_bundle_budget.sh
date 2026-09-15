#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build/web_store}"
BUNDLE="$BUILD_DIR/main.dart.js"
# These are regression canaries, not a requirement that every legitimate
# feature fit inside an old snapshot forever. The defaults intentionally keep
# roughly 8-14% runway over the current storefront while still catching
# accidental ERP imports and package-scale jumps.
#
# 2026-09-15 re-base. The July 2026 ceilings (raw 6 000 000, gzip 1 700 000)
# were set over a 5 467 276 / 1 541 073 bundle with 31 deferred chunks. The
# first build of `main` after the cutover (dc1e609) measured 6 687 239 /
# 1 775 132 with 23 chunks, identically on the Mac and on the CI runner: the
# storefront shell now imports the website editor host
# (persistent_editor_shell, contextual dock, block sheet, command scope, draft
# recovery) and the customer chat (messaging service, chat provider,
# attachments) eagerly, so eight chunks that used to load on demand merged
# into main.dart.js. Nobody saw it grow because the store workflow never
# reached this step between 2026-08-10 and 2026-09-15 (see
# docs/runbooks/MAIN_BRANCH_CUTOVER.md §0.3, paso 5). Putting the editor host
# and the chat behind the existing `deferred as` seams is backlog (§17.1);
# until then the ceilings keep ~9% runway over dc1e609.
MAX_RAW_BYTES="${STOREFRONT_MAX_RAW_BYTES:-7300000}"
MAX_GZIP_BYTES="${STOREFRONT_MAX_GZIP_BYTES:-1950000}"
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
