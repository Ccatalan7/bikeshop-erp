# 🚀 Deploy Website Configuration Columns

**Date:** 2025-10-25  
**Feature:** Multi-Tenant Website Deployment  
**File:** `supabase/sql/migrations/add_website_configuration_columns.sql`

---

## 📋 What This Does

Adds 6 new columns to the `company_settings` table to support multi-tenant website deployment:

1. `website_enabled` - Boolean flag to activate website
2. `website_subdomain` - Unique subdomain (e.g., "bikeshop-santiago")
3. `website_url` - Full deployed URL (e.g., "https://bikeshop-santiago.web.app")
4. `firebase_site_name` - Firebase Hosting site name
5. `website_deployed_at` - Timestamp of last deployment
6. `website_status` - Deployment status (not_configured, pending, deployed, failed)

---

## 🔧 Deployment Steps

### Option 1: Deploy via Supabase Dashboard (Recommended)

1. **Login to Supabase Dashboard:**
   - Go to https://supabase.com/dashboard
   - Select your project: `project-vinabike`

2. **Open SQL Editor:**
   - Click "SQL Editor" in the left sidebar
   - Click "New query"

3. **Copy and Paste SQL:**
   - Open `supabase/sql/migrations/add_website_configuration_columns.sql`
   - Copy the entire file contents
   - Paste into the SQL Editor

4. **Run the Migration:**
   - Click "Run" button (or press Ctrl+Enter)
   - Wait for success messages

5. **Verify Output:**
   You should see:
   ```
   ✅ Website configuration columns added to company_settings
   ✅ Column comments added
   ✅ Unique constraint added to website_subdomain
   ✅ Indexes created for website_subdomain and website_status
   ✅ VERIFICATION PASSED: All 6 website configuration columns exist
   ```

6. **Check Schema:**
   The query will display the updated `company_settings` schema at the end

---

### Option 2: Deploy via Supabase CLI

```powershell
# Navigate to project directory
cd C:\dev\ProjectVinabike

# Run the migration
supabase db push

# Or run the specific migration file
supabase db execute -f supabase/sql/migrations/add_website_configuration_columns.sql
```

---

## ✅ Verification

After deployment, run this query to verify the columns exist:

```sql
select 
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'company_settings'
  and column_name in (
    'website_enabled',
    'website_subdomain',
    'website_url',
    'firebase_site_name',
    'website_deployed_at',
    'website_status'
  )
order by column_name;
```

**Expected output:** 6 rows showing all website configuration columns

---

## 🔍 Test the Columns

After deployment, test by inserting a sample website configuration:

```sql
-- Get your tenant_id
select id, name from tenants limit 1;

-- Insert test website configuration
insert into company_settings (tenant_id, key, value, website_subdomain, website_status)
values (
  'YOUR-TENANT-ID-HERE',
  'website_config',
  'test',
  'test-bikeshop',
  'not_configured'
)
on conflict (tenant_id, key) do update
set 
  website_subdomain = excluded.website_subdomain,
  website_status = excluded.website_status;

-- Verify the insert
select 
  tenant_id,
  key,
  website_subdomain,
  website_status,
  website_url,
  website_deployed_at
from company_settings
where website_subdomain is not null;
```

---

## 🚨 Troubleshooting

### Error: "Table company_settings does not exist"
**Solution:** Run `core_schema.sql` first to create the base table

### Error: "Duplicate column"
**Solution:** Columns already exist - this is OK, migration is idempotent

### Error: "Unique constraint already exists"
**Solution:** Constraint already exists - this is OK, migration is idempotent

---

## 📚 Next Steps

After deploying these columns:

1. ✅ **Create Flutter UI** for website setup
   - Create `lib/modules/website/pages/website_setup_page.dart`
   - Use code from `MULTI_TENANT_WEBSITE_SETUP_GUIDE.md`

2. ✅ **Test deployment script**
   - Run `.\scripts\deploy_tenant_website.ps1 -TenantId "UUID"`
   - Verify website deploys to unique subdomain

3. ✅ **Create Supabase Edge Function** (optional)
   - Create `supabase/functions/deploy-tenant-website/index.ts`
   - Enable one-click deployment from Flutter UI

---

## 📄 Related Files

- `supabase/sql/core_schema.sql` - Master schema (lines 271-292)
- `MULTI_TENANT_WEBSITE_SETUP_GUIDE.md` - Complete implementation guide
- `MULTI_TENANT_WEBSITE_QUICKSTART.md` - Quick start guide
- `scripts/deploy_tenant_website.ps1` - PowerShell deployment script
- `scripts/deploy_tenant_website.js` - Node.js deployment script

---

**Status:** Ready to deploy ✅  
**Risk:** LOW (idempotent migration, safe to re-run)  
**Estimated time:** 2 minutes
