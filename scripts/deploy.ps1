$ErrorActionPreference = "Stop"

function Resolve-SupabaseSecretKey {
    if (-not [string]::IsNullOrWhiteSpace($env:SUPABASE_SECRET_KEY)) {
        return $env:SUPABASE_SECRET_KEY
    }

    if (Test-Path -LiteralPath '.env') {
        $secretLine = Get-Content -LiteralPath '.env' |
            Where-Object { $_ -match '^\s*SUPABASE_SECRET_KEY\s*=' } |
            Select-Object -First 1
        if ($secretLine) {
            $key = ($secretLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
            if (-not [string]::IsNullOrWhiteSpace($key)) {
                return $key
            }
        }
    }

    if (Get-Command supabase -ErrorAction SilentlyContinue) {
        $keysJson = supabase projects api-keys `
            --project-ref xzdvtzdqjeyqxnkqprtf `
            --reveal --output json 2>$null
        if ($LASTEXITCODE -eq 0) {
            $keys = @($keysJson | ConvertFrom-Json)
            $secret = @($keys | Where-Object { $_.type -eq 'secret' }) |
                Select-Object -First 1
            if ($secret -and -not [string]::IsNullOrWhiteSpace($secret.api_key)) {
                return $secret.api_key
            }
        }
    }

    throw 'Could not load SUPABASE_SECRET_KEY from the environment, .env, or authenticated Supabase CLI.'
}

# Fail before the expensive web builds when snapshot access is unavailable.
$env:SUPABASE_SECRET_KEY = Resolve-SupabaseSecretKey

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
