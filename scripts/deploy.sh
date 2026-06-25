#!/bin/bash
set -e

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

echo "Syncing SEO index..."
if command -v bash &> /dev/null; then
    bash ./scripts/sync_seo_index.sh
else
    echo "Bash not found, skipping sync_seo_index.sh"
fi

echo "Building Store..."
"$FLUTTER_BIN" build web --release --pwa-strategy=none --dart-define=STORE_PERF_LOGS=true -t lib/main_store.dart -o build/web_store

echo "Generating SEO snapshots..."
"$DART_BIN" run scripts/generate_product_seo_snapshots.dart --build-dir build/web_store --tenant-id 5443b130-cc28-45af-a420-cd500b288890 --store-url https://vinabike.cl --product-scope published

echo "Store bundle size:"
ls -lh build/web_store/main.dart.js | awk '{print $5}'

echo "Building ERP..."
"$FLUTTER_BIN" build web --release --dart-define=STORE_PERF_LOGS=true -t lib/main.dart -o build/web_erp

echo "ERP bundle size:"
ls -lh build/web_erp/main.dart.js | awk '{print $5}'

echo "Deploying to Firebase..."
firebase deploy --only hosting
