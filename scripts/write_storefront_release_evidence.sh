#!/bin/bash
set -euo pipefail

# Positional arguments 1-5 preserve the original interface. Optional
# publication arguments 6-9 override their environment equivalents:
#
#   6 / STOREFRONT_PUBLICATION_REQUEST_ID
#   7 / STOREFRONT_PUBLICATION_OWNER_REVISION
#   8 / STOREFRONT_OWNER_SOURCE_SHA256
#   9 / STOREFRONT_BUILD_INPUT_SHA256
#
# A code-push or manual build omits all four and records `publication: null`.
if [ "$#" -gt 9 ]; then
    echo "Too many arguments for storefront release evidence." >&2
    exit 64
fi

BUILD_DIR="${1:-build/web_store}"
COMMIT="${2:-unknown}"
RUN_ID="${3:-manual}"
SOURCE="${4:-manual}"
DIRTY="${5:-false}"
REQUEST_ID="${6:-${STOREFRONT_PUBLICATION_REQUEST_ID:-}}"
OWNER_REVISION="${7:-${STOREFRONT_PUBLICATION_OWNER_REVISION:-}}"
OWNER_SOURCE_SHA256="${8:-${STOREFRONT_OWNER_SOURCE_SHA256:-}}"
BUILD_INPUT_SHA256="${9:-${STOREFRONT_BUILD_INPUT_SHA256:-}}"

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

PUBLICATION_JSON="null"
if [ -z "$REQUEST_ID" ]; then
    if [ -n "$OWNER_REVISION" ] ||
       [ -n "$OWNER_SOURCE_SHA256" ] ||
       [ -n "$BUILD_INPUT_SHA256" ]; then
        echo "Publication metadata requires a request_id." >&2
        exit 64
    fi
else
    if ! [[ "$REQUEST_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
        echo "Publication request_id must be a canonical RFC UUID." >&2
        exit 64
    fi
    if ! [[ "$OWNER_REVISION" =~ ^[1-9][0-9]*$ ]]; then
        echo "Publication owner_revision must be a positive integer." >&2
        exit 64
    fi
    if ! [[ "$OWNER_SOURCE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Publication owner_source_sha256 must be a SHA-256 digest." >&2
        exit 64
    fi
    if ! [[ "$BUILD_INPUT_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Publication build_input_sha256 must be a SHA-256 digest." >&2
        exit 64
    fi

    REQUEST_ID=$(printf '%s' "$REQUEST_ID" | tr '[:upper:]' '[:lower:]')
    OWNER_SOURCE_SHA256=$(
        printf '%s' "$OWNER_SOURCE_SHA256" | tr '[:upper:]' '[:lower:]'
    )
    BUILD_INPUT_SHA256=$(
        printf '%s' "$BUILD_INPUT_SHA256" | tr '[:upper:]' '[:lower:]'
    )
    PUBLICATION_JSON=$(
        jq -cn \
            --arg request_id "$REQUEST_ID" \
            --argjson owner_revision "$OWNER_REVISION" \
            --arg owner_source_sha256 "$OWNER_SOURCE_SHA256" \
            --arg build_input_sha256 "$BUILD_INPUT_SHA256" \
            '{
              request_id: $request_id,
              owner_revision: $owner_revision,
              owner_source_sha256: $owner_source_sha256,
              build_input_sha256: $build_input_sha256
            }'
    )
fi

jq -n \
    --arg commit "$COMMIT" \
    --arg run "$RUN_ID" \
    --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg source "$SOURCE" \
    --argjson dirty "$DIRTY" \
    --argjson publication "$PUBLICATION_JSON" \
    '{
      commit: $commit,
      run: $run,
      built_at: $built_at,
      target: "store",
      source: $source,
      dirty: $dirty,
      publication: $publication
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
