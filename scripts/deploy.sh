#!/bin/bash
set -e

echo "Syncing SEO index..."
if command -v bash &> /dev/null; then
    bash ./scripts/sync_seo_index.sh
else
    echo "Bash not found, skipping sync_seo_index.sh"
fi

echo "Building Store..."
flutter build web --release --dart-define=STORE_PERF_LOGS=true -t lib/main_store.dart -o build/web_store

echo "Generating SEO snapshots..."
dart run scripts/generate_product_seo_snapshots.dart --build-dir build/web_store --tenant-id 5443b130-cc28-45af-a420-cd500b288890 --store-url https://vinabike.cl

echo "Store bundle size:"
ls -lh build/web_store/main.dart.js | awk '{print $5}'

echo "Building ERP..."
flutter build web --release --dart-define=STORE_PERF_LOGS=true -t lib/main.dart -o build/web_erp

echo "ERP bundle size:"
ls -lh build/web_erp/main.dart.js | awk '{print $5}'

echo "Deploying to Firebase..."
firebase deploy --only hosting
