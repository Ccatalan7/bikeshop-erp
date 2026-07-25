#!/bin/bash
set -e

WEB_BUILD_MODE=()
WEB_BUNDLE_NAME="main.dart.js"
CHECK_ONLY=false

if [ "${1:-}" = "--wasm" ]; then
    WEB_BUILD_MODE=(--wasm)
    WEB_BUNDLE_NAME="main.dart.wasm"
elif [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=true
elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--wasm|--check]" >&2
    exit 64
fi

resolve_bin() {
    local requested="$1"
    local fallback="$2"

    if [ -n "$fallback" ] && [ -x "$fallback" ]; then
        printf '%s' "$fallback"
        return 0
    fi

    if command -v "$requested" > /dev/null 2>&1; then
        command -v "$requested"
        return 0
    fi

    local home_candidate="$HOME/flutter/bin/$requested"
    if [ -x "$home_candidate" ]; then
        printf '%s' "$home_candidate"
        return 0
    fi

    echo "$requested not found. Set ${requested^^}_BIN or add it to PATH." >&2
    exit 127
}

FLUTTER_BIN=$(resolve_bin flutter "${FLUTTER_BIN:-}")
DART_BIN=$(resolve_bin dart "${DART_BIN:-}")

resolve_supabase_secret_key() {
    local key="${SUPABASE_SECRET_KEY:-}"

    if [ -n "$key" ]; then
        printf '%s' "$key"
        return 0
    fi

    if command -v security >/dev/null 2>&1; then
        key=$(security find-generic-password \
            -s 'Vinabike ERP Supabase secret key' \
            -a supabase -w 2>/dev/null || true)
        if [ -n "$key" ]; then
            printf '%s' "$key"
            return 0
        fi
    fi

    echo "Could not load SUPABASE_SECRET_KEY from the process environment or macOS Keychain." >&2
    exit 64
}

# Resolve this before the expensive Flutter build so a missing credential fails
# immediately. Pass it only to the maintenance process that needs it.
SUPABASE_SECRET_KEY_FOR_SNAPSHOTS=$(resolve_supabase_secret_key)

if [ "$CHECK_ONLY" = true ]; then
    bash ./scripts/sync_seo_index.sh --check
    echo "Deployment credential preflight passed."
    exit 0
fi

echo "Syncing SEO index..."
if command -v bash &> /dev/null; then
    bash ./scripts/sync_seo_index.sh
else
    echo "Bash not found, skipping sync_seo_index.sh"
fi

echo "Building Store..."
"$FLUTTER_BIN" build web "${WEB_BUILD_MODE[@]}" --release --pwa-strategy=none --dart-define=STORE_PERF_LOGS=true -t lib/main_store.dart -o build/web_store

echo "Generating SEO snapshots..."
SUPABASE_SECRET_KEY="$SUPABASE_SECRET_KEY_FOR_SNAPSHOTS" \
    "$DART_BIN" run scripts/generate_product_seo_snapshots.dart --build-dir build/web_store --tenant-id 5443b130-cc28-45af-a420-cd500b288890 --store-url https://vinabike.cl --product-scope published

echo "Store bundle size:"
du -h "build/web_store/$WEB_BUNDLE_NAME" | awk '{print $1}'

echo "Building ERP..."
"$FLUTTER_BIN" build web "${WEB_BUILD_MODE[@]}" --release --dart-define=STORE_PERF_LOGS=true -t lib/main.dart -o build/web_erp

echo "ERP bundle size:"
du -h "build/web_erp/$WEB_BUNDLE_NAME" | awk '{print $1}'

echo "Deploying to Firebase..."
firebase deploy --only hosting
