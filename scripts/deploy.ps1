$ErrorActionPreference = "Stop"

# Match the canonical shell wrapper's privacy boundary for the native
# PowerShell deployment path.
$env:SUPABASE_TELEMETRY_DISABLED = '1'
$env:DO_NOT_TRACK = '1'
$env:OTEL_SDK_DISABLED = 'true'
$env:OTEL_TRACES_EXPORTER = 'none'
$env:OTEL_METRICS_EXPORTER = 'none'
$env:OTEL_LOGS_EXPORTER = 'none'
$storePerfLogs = if ([string]::IsNullOrWhiteSpace($env:STORE_PERF_LOGS)) {
    'false'
} else {
    $env:STORE_PERF_LOGS
}

function Resolve-SupabaseSecretKey {
    if (-not [string]::IsNullOrWhiteSpace($env:SUPABASE_SECRET_KEY)) {
        return $env:SUPABASE_SECRET_KEY
    }

    throw 'Could not load SUPABASE_SECRET_KEY from the process environment. Inject it from Windows Credential Manager or another protected environment source.'
}

# Fail before the expensive web builds when snapshot access is unavailable.
$env:SUPABASE_SECRET_KEY = Resolve-SupabaseSecretKey

Write-Host "Syncing SEO index..."
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    throw 'Bash is required for SEO sync, bundle validation, and release evidence.'
}
bash ./scripts/sync_seo_index.sh

$storeBuildCommit = (& git rev-parse HEAD).Trim()
if ([string]::IsNullOrWhiteSpace($storeBuildCommit)) {
    $storeBuildCommit = 'unknown'
}
$storeBuildDirty = if ((& git status --porcelain --untracked-files=normal)) {
    'true'
} else {
    'false'
}
$storeBuildTag = if ([string]::IsNullOrWhiteSpace($env:VINABIKE_BUILD_TAG)) {
    $storeBuildCommit
} else {
    $env:VINABIKE_BUILD_TAG
}

Write-Host "Building Store..."
if (Test-Path -LiteralPath 'build/web_store') {
    Remove-Item -LiteralPath 'build/web_store' -Recurse -Force
}
flutter build web --release --pwa-strategy=none --dart-define=STORE_PERF_LOGS=$storePerfLogs --dart-define=VINABIKE_BUILD_TAG=$storeBuildTag -t lib/main_store.dart -o build/web_store
bash ./scripts/check_storefront_bundle_budget.sh build/web_store

Write-Host "Generating SEO snapshots..."
dart run scripts/generate_product_seo_snapshots.dart --build-dir build/web_store --tenant-id 5443b130-cc28-45af-a420-cd500b288890 --store-url https://vinabike.cl --product-scope published
bash ./scripts/write_storefront_release_evidence.sh build/web_store $storeBuildCommit manual manual-powershell $storeBuildDirty

Write-Host "Store bundle size:"
Get-Item build/web_store/main.dart.js | Select-Object Name, @{N='Size(MB)';E={[math]::Round($_.Length/1MB,2)}}

Write-Host "Building ERP..."
if (Test-Path -LiteralPath 'build/web_erp') {
    Remove-Item -LiteralPath 'build/web_erp' -Recurse -Force
}
flutter build web --release --dart-define=STORE_PERF_LOGS=$storePerfLogs --dart-define=VINABIKE_BUILD_TAG=$storeBuildTag -t lib/main.dart -o build/web_erp

Write-Host "ERP bundle size:"
Get-Item build/web_erp/main.dart.js | Select-Object Name, @{N='Size(MB)';E={[math]::Round($_.Length/1MB,2)}}

Write-Host "Deploying to Firebase..."
firebase deploy --only hosting
