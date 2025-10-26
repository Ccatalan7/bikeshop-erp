# ============================================================================
# TENANT WEBSITE DEPLOYMENT SCRIPT (PowerShell)
# ============================================================================
# 
# Automatically deploys a tenant's e-commerce website to Firebase Hosting
# with a unique subdomain (e.g., bikeshop1.web.app)
# 
# Usage:
#   .\scripts\deploy_tenant_website.ps1 -TenantId "97ef40bf-f58c-4f76-a629-c013fb3928cf"
# 
# Requirements:
#   - PowerShell 7+
#   - Firebase CLI installed (npm install -g firebase-tools)
#   - Flutter SDK in PATH
#   - Supabase credentials in environment variables
# 
# Environment Variables (set before running):
#   $env:SUPABASE_URL = "https://your-project.supabase.co"
#   $env:SUPABASE_SERVICE_KEY = "your-service-role-key"
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [string]$FirebaseProject = "project-vinabike"
)

# Configuration
$ErrorActionPreference = "Stop"
$SUPABASE_URL = $env:SUPABASE_URL
$SUPABASE_SERVICE_KEY = $env:SUPABASE_SERVICE_KEY

# Colors for output
function Write-Success { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Info { Write-Host "→ $args" -ForegroundColor Cyan }
function Write-Warning { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Error-Custom { Write-Host "✗ $args" -ForegroundColor Red }
function Write-Header { 
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host " $args" -ForegroundColor Magenta
    Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
}

# Validate environment
if (-not $SUPABASE_URL -or -not $SUPABASE_SERVICE_KEY) {
    Write-Error-Custom "Missing environment variables!"
    Write-Host ""
    Write-Host "Please set:" -ForegroundColor Yellow
    Write-Host '  $env:SUPABASE_URL = "https://your-project.supabase.co"' -ForegroundColor Gray
    Write-Host '  $env:SUPABASE_SERVICE_KEY = "your-service-role-key"' -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Validate UUID format
if ($TenantId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
    Write-Error-Custom "Invalid tenant ID format: $TenantId"
    Write-Host "Expected UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    exit 1
}

Write-Header "🚀 TENANT WEBSITE DEPLOYMENT"

try {
    # ========================================================================
    # STEP 1: Fetch Tenant Configuration
    # ========================================================================
    Write-Info "Step 1/6: Fetching tenant configuration..."
    
    $headers = @{
        "apikey" = $SUPABASE_SERVICE_KEY
        "Authorization" = "Bearer $SUPABASE_SERVICE_KEY"
        "Content-Type" = "application/json"
    }
    
    $url = "$SUPABASE_URL/rest/v1/company_settings?tenant_id=eq.$TenantId&select=website_subdomain,website_status"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    
    if ($response.Count -eq 0) {
        throw "Tenant not found: $TenantId"
    }
    
    $config = $response[0]
    $siteName = $config.website_subdomain
    
    if (-not $siteName) {
        throw "No subdomain configured. Tenant must request website setup first."
    }
    
    Write-Success "Tenant ID: $TenantId"
    Write-Success "Site name: $siteName"
    Write-Success "Current status: $($config.website_status)"
    Write-Host ""
    
    # ========================================================================
    # STEP 2: Create Firebase Hosting Site
    # ========================================================================
    Write-Info "Step 2/6: Creating Firebase Hosting site..."
    
    try {
        firebase hosting:sites:create $siteName --project $FirebaseProject 2>&1 | Out-Null
        Write-Success "Created new site: $siteName"
    } catch {
        Write-Warning "Site already exists (continuing...)"
    }
    Write-Host ""
    
    # ========================================================================
    # STEP 3: Configure Deployment Target
    # ========================================================================
    Write-Info "Step 3/6: Configuring deployment target..."
    firebase target:apply hosting $siteName $siteName --project $FirebaseProject
    Write-Success "Target configured"
    Write-Host ""
    
    # ========================================================================
    # STEP 4: Build Flutter Web App
    # ========================================================================
    Write-Info "Step 4/6: Building Flutter web app..."
    flutter clean
    flutter pub get
    flutter build web --release --web-renderer canvaskit
    Write-Success "Build complete"
    Write-Host ""
    
    # ========================================================================
    # STEP 5: Deploy to Firebase Hosting
    # ========================================================================
    Write-Info "Step 5/6: Deploying to Firebase Hosting..."
    firebase deploy --only hosting:$siteName --project $FirebaseProject
    
    $websiteUrl = "https://$siteName.web.app"
    Write-Success "Deployed to: $websiteUrl"
    Write-Host ""
    
    # ========================================================================
    # STEP 6: Update Database
    # ========================================================================
    Write-Info "Step 6/6: Updating database..."
    
    $updateData = @{
        website_url = $websiteUrl
        firebase_site_name = $siteName
        website_deployed_at = (Get-Date).ToUniversalTime().ToString("o")
        website_status = "deployed"
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json
    
    $updateUrl = "$SUPABASE_URL/rest/v1/company_settings?tenant_id=eq.$TenantId"
    Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $updateData | Out-Null
    
    Write-Success "Database updated"
    Write-Host ""
    
    # ========================================================================
    # SUCCESS!
    # ========================================================================
    Write-Header "✅ DEPLOYMENT SUCCESSFUL!"
    
    Write-Host "🌐 Website URL:   $websiteUrl" -ForegroundColor Green
    Write-Host "📦 Firebase Site: $siteName" -ForegroundColor Green
    Write-Host "🆔 Tenant ID:     $TenantId" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Open the website in your browser"
    Write-Host "  2. Verify products are displaying correctly"
    Write-Host "  3. Test the complete purchase flow"
    Write-Host "  4. (Optional) Set up custom domain"
    Write-Host ""
    
    exit 0
    
} catch {
    # ========================================================================
    # ERROR HANDLING
    # ========================================================================
    Write-Header "❌ DEPLOYMENT FAILED"
    
    Write-Error-Custom $_.Exception.Message
    Write-Host ""
    
    # Update database with error status
    try {
        $errorData = @{
            website_status = "error"
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json
        
        $updateUrl = "$SUPABASE_URL/rest/v1/company_settings?tenant_id=eq.$TenantId"
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method Patch -Body $errorData | Out-Null
        Write-Info "Database updated with error status"
    } catch {
        Write-Error-Custom "Failed to update database: $($_.Exception.Message)"
    }
    
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Check Firebase CLI is installed: firebase --version"
    Write-Host "  2. Verify Firebase authentication: firebase login"
    Write-Host "  3. Check Supabase credentials are correct"
    Write-Host "  4. Ensure tenant has requested website setup first"
    Write-Host "  5. Check Flutter is installed: flutter doctor"
    Write-Host ""
    
    exit 1
}
