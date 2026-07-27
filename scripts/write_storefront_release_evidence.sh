#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build/web_store}"
COMMIT="${2:-unknown}"
RUN_ID="${3:-manual}"
SOURCE="${4:-manual}"
DIRTY="${5:-false}"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Storefront build directory not found: $BUILD_DIR" >&2
    exit 66
fi

if [ "$DIRTY" != "true" ] && [ "$DIRTY" != "false" ]; then
    echo "Dirty flag must be true or false, got: $DIRTY" >&2
    exit 64
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to write storefront release evidence." >&2
    exit 127
fi

jq -n \
    --arg commit "$COMMIT" \
    --arg run "$RUN_ID" \
    --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg source "$SOURCE" \
    --argjson dirty "$DIRTY" \
    '{
      commit: $commit,
      run: $run,
      built_at: $built_at,
      target: "store",
      source: $source,
      dirty: $dirty
    }' \
    > "$BUILD_DIR/release.json"

if command -v sha256sum >/dev/null 2>&1; then
    HASH_COMMAND=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    HASH_COMMAND=(shasum -a 256)
else
    echo "sha256sum or shasum is required for release evidence." >&2
    exit 127
fi

(
    cd "$BUILD_DIR"
    while IFS= read -r -d '' file; do
        "${HASH_COMMAND[@]}" "$file"
    done < <(
        find . -type f \
            \( -name 'flutter_bootstrap.js' \
               -o -name 'main.dart.js' \
               -o -name 'main.dart.js_*.part.js' \
               -o -name 'main.dart.wasm' \
               -o -name 'main.dart.mjs' \
               -o -name '*.html' \
               -o -name 'sitemap.xml' \
               -o -name 'robots.txt' \
               -o -name 'manifest*.json' \
               -o -name 'release.json' \) \
            -print0 \
            | sort -z
    )
) > "$BUILD_DIR/release.sha256"

if [ ! -s "$BUILD_DIR/release.sha256" ]; then
    echo "Storefront release checksum manifest is empty." >&2
    exit 65
fi

echo "Storefront release evidence written for $COMMIT ($SOURCE, dirty=$DIRTY)."
