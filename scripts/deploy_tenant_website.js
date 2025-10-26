#!/usr/bin/env node

/**
 * TENANT WEBSITE DEPLOYMENT SCRIPT
 * 
 * Automatically deploys a tenant's e-commerce website to Firebase Hosting
 * with a unique subdomain (e.g., bikeshop1.web.app)
 * 
 * Usage:
 *   node scripts/deploy_tenant_website.js <tenant_id>
 *   node scripts/deploy_tenant_website.js 97ef40bf-f58c-4f76-a629-c013fb3928cf
 * 
 * Requirements:
 *   - Node.js 18+
 *   - Firebase CLI installed (`npm install -g firebase-tools`)
 *   - Supabase credentials in environment variables
 *   - Firebase project access
 * 
 * Environment Variables:
 *   SUPABASE_URL=https://your-project.supabase.co
 *   SUPABASE_SERVICE_KEY=your-service-role-key
 */

const { execSync } = require('child_process');
const { createClient } = require('@supabase/supabase-js');

// Configuration
const FIREBASE_PROJECT = 'project-vinabike';
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

// Validate environment
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ Missing environment variables:');
  console.error('   SUPABASE_URL');
  console.error('   SUPABASE_SERVICE_KEY');
  console.error('');
  console.error('Set them in .env or pass directly:');
  console.error('   SUPABASE_URL=https://... SUPABASE_SERVICE_KEY=... node scripts/deploy_tenant_website.js <tenant_id>');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

/**
 * Execute shell command with error handling
 */
function runCommand(command, options = {}) {
  try {
    console.log(`  $ ${command}`);
    execSync(command, { stdio: options.silent ? 'pipe' : 'inherit' });
    return true;
  } catch (error) {
    if (!options.ignoreErrors) {
      throw error;
    }
    return false;
  }
}

/**
 * Main deployment function
 */
async function deployTenantWebsite(tenantId) {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║         🚀 TENANT WEBSITE DEPLOYMENT                          ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');

  try {
    // ============================================================================
    // STEP 1: Fetch Tenant Configuration
    // ============================================================================
    console.log('📋 Step 1/6: Fetching tenant configuration...');
    const { data: config, error } = await supabase
      .from('company_settings')
      .select('website_subdomain, website_status')
      .eq('tenant_id', tenantId)
      .single();

    if (error) {
      throw new Error(`Failed to fetch tenant: ${error.message}`);
    }

    if (!config) {
      throw new Error(`Tenant not found: ${tenantId}`);
    }

    const siteName = config.website_subdomain;

    if (!siteName) {
      throw new Error('No subdomain configured. Tenant must request website setup first.');
    }

    console.log(`   ✓ Tenant ID: ${tenantId}`);
    console.log(`   ✓ Site name: ${siteName}`);
    console.log(`   ✓ Current status: ${config.website_status}`);
    console.log('');

    // ============================================================================
    // STEP 2: Create Firebase Hosting Site
    // ============================================================================
    console.log('🔧 Step 2/6: Creating Firebase Hosting site...');
    const siteCreated = runCommand(
      `firebase hosting:sites:create ${siteName} --project ${FIREBASE_PROJECT}`,
      { ignoreErrors: true, silent: true }
    );

    if (siteCreated) {
      console.log(`   ✓ Created new site: ${siteName}`);
    } else {
      console.log(`   ⚠️  Site already exists (continuing...)`);
    }
    console.log('');

    // ============================================================================
    // STEP 3: Configure Deployment Target
    // ============================================================================
    console.log('🎯 Step 3/6: Configuring deployment target...');
    runCommand(
      `firebase target:apply hosting ${siteName} ${siteName} --project ${FIREBASE_PROJECT}`
    );
    console.log(`   ✓ Target configured`);
    console.log('');

    // ============================================================================
    // STEP 4: Build Flutter Web App
    // ============================================================================
    console.log('🔨 Step 4/6: Building Flutter web app...');
    runCommand('flutter clean');
    runCommand('flutter pub get');
    runCommand('flutter build web --release --web-renderer canvaskit');
    console.log(`   ✓ Build complete`);
    console.log('');

    // ============================================================================
    // STEP 5: Deploy to Firebase Hosting
    // ============================================================================
    console.log('🚀 Step 5/6: Deploying to Firebase Hosting...');
    runCommand(
      `firebase deploy --only hosting:${siteName} --project ${FIREBASE_PROJECT}`
    );
    const url = `https://${siteName}.web.app`;
    console.log(`   ✓ Deployed to: ${url}`);
    console.log('');

    // ============================================================================
    // STEP 6: Update Database
    // ============================================================================
    console.log('💾 Step 6/6: Updating database...');
    const { error: updateError } = await supabase
      .from('company_settings')
      .update({
        website_url: url,
        firebase_site_name: siteName,
        website_deployed_at: new Date().toISOString(),
        website_status: 'deployed',
        updated_at: new Date().toISOString(),
      })
      .eq('tenant_id', tenantId);

    if (updateError) {
      throw new Error(`Database update failed: ${updateError.message}`);
    }

    console.log(`   ✓ Database updated`);
    console.log('');

    // ============================================================================
    // SUCCESS!
    // ============================================================================
    console.log('╔════════════════════════════════════════════════════════════════╗');
    console.log('║         ✅ DEPLOYMENT SUCCESSFUL!                              ║');
    console.log('╚════════════════════════════════════════════════════════════════╝');
    console.log('');
    console.log(`🌐 Website URL: ${url}`);
    console.log(`📦 Firebase Site: ${siteName}`);
    console.log(`🆔 Tenant ID: ${tenantId}`);
    console.log('');
    console.log('Next steps:');
    console.log('  1. Open the website in your browser');
    console.log('  2. Verify products are displaying correctly');
    console.log('  3. Test the complete purchase flow');
    console.log('  4. (Optional) Set up custom domain');
    console.log('');

    process.exit(0);
  } catch (error) {
    // ============================================================================
    // ERROR HANDLING
    // ============================================================================
    console.error('');
    console.error('╔════════════════════════════════════════════════════════════════╗');
    console.error('║         ❌ DEPLOYMENT FAILED                                   ║');
    console.error('╚════════════════════════════════════════════════════════════════╝');
    console.error('');
    console.error('Error:', error.message);
    console.error('');

    // Update database with error status
    try {
      await supabase
        .from('company_settings')
        .update({
          website_status: 'error',
          updated_at: new Date().toISOString(),
        })
        .eq('tenant_id', tenantId);
      console.error('Database updated with error status.');
    } catch (dbError) {
      console.error('Failed to update database:', dbError.message);
    }

    console.error('');
    console.error('Troubleshooting:');
    console.error('  1. Check Firebase CLI is installed: firebase --version');
    console.error('  2. Verify Firebase authentication: firebase login');
    console.error('  3. Check Supabase credentials are correct');
    console.error('  4. Ensure tenant has requested website setup first');
    console.error('  5. Check Flutter is installed: flutter doctor');
    console.error('');

    process.exit(1);
  }
}

// ============================================================================
// MAIN ENTRY POINT
// ============================================================================

// Get tenant ID from command line
const tenantId = process.argv[2];

if (!tenantId) {
  console.error('Usage: node scripts/deploy_tenant_website.js <tenant_id>');
  console.error('');
  console.error('Example:');
  console.error('  node scripts/deploy_tenant_website.js 97ef40bf-f58c-4f76-a629-c013fb3928cf');
  console.error('');
  console.error('To find tenant IDs, query the tenants table in Supabase.');
  process.exit(1);
}

// Validate UUID format
const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!uuidRegex.test(tenantId)) {
  console.error(`Invalid tenant ID format: ${tenantId}`);
  console.error('Expected UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx');
  process.exit(1);
}

// Run deployment
deployTenantWebsite(tenantId);
