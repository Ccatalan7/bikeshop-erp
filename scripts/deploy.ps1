$ErrorActionPreference = "Stop"

Write-Host "Syncing SEO index..."
# Run the shell script using bash if available, or just skip if it's simple replacements
# Since it's a .sh file, likely needs bash. Git Bash is usually available.
if (Get-Command bash -ErrorAction SilentlyContinue) {
    bash ./scripts/sync_seo_index.sh
} else {
    Write-Warning "Bash not found, skipping sync_seo_index.sh"
}

Write-Host "Building Store..."
flutter build web --release --dart-define=STORE_PERF_LOGS=true -t lib/main_store.dart -o build/web_store

Write-Host "Generating SEO snapshots..."
dart run scripts/generate_product_seo_snapshots.dart --build-dir build/web_store --tenant-id 5443b130-cc28-45af-a420-cd500b288890 --store-url https://vinabike.cl --product-scope published

Write-Host "Store bundle size:"
Get-Item build/web_store/main.dart.js | Select-Object Name, @{N='Size(MB)';E={[math]::Round($_.Length/1MB,2)}}

Write-Host "Building ERP..."
flutter build web --release --dart-define=STORE_PERF_LOGS=true -t lib/main.dart -o build/web_erp

Write-Host "ERP bundle size:"
Get-Item build/web_erp/main.dart.js | Select-Object Name, @{N='Size(MB)';E={[math]::Round($_.Length/1MB,2)}}

Write-Host "Deploying to Firebase..."
firebase deploy --only hosting
