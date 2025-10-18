# 🔄 Logo Sync Fix - Deployment Guide

## Problem
Logo changes were not syncing across devices because the URL was stored in **SharedPreferences** (local to each device/browser). Each device had its own separate copy of the logo URL.

## Solution
Changed logo storage from **SharedPreferences** to **Supabase database** (`company_settings` table), making it globally synced across all devices.

---

## ⚠️ CRITICAL: Deploy in This Order

### Step 1: Deploy Database Schema First
```bash
# Open Supabase Dashboard
# Go to SQL Editor
# Copy and paste the ENTIRE content of supabase/sql/core_schema.sql
# Click "Run" to execute
```

**What this does:**
- Creates `company_settings` table
- Inserts default values for `home_icon` and `company_logo`
- Enables global sync for appearance settings

### Step 2: Build and Deploy Flutter App
```bash
flutter build web --release
firebase deploy
```

---

## 🔍 How It Works Now

### Before (Broken)
```
Computer A: Upload logo → Save URL to SharedPreferences (local)
Computer B: Has old/no logo because its SharedPreferences is separate
```

### After (Fixed)
```
Computer A: Upload logo → Save URL to Supabase database (global)
Computer B: Loads logo from Supabase database → Gets latest URL automatically
```

### Three-Layer Sync System
1. **Database storage** - Logo URL stored in Supabase `company_settings` table
2. **Auto-refresh on startup** - App refreshes logo 2 seconds after launch
3. **Manual refresh button** - Users can click "Refrescar" to force update

---

## 📋 What Changed

### Database (supabase/sql/core_schema.sql)
- Added `company_settings` table with:
  - `id` (UUID primary key)
  - `key` (unique text: 'home_icon', 'company_logo')
  - `value` (text: stores icon code or logo URL)
  - `created_at` and `updated_at` timestamps
- Auto-inserts default values on table creation

### Flutter Code (lib/modules/settings/services/appearance_service.dart)
- **Removed:** SharedPreferences import and usage
- **Added:** Supabase client integration
- **Changed:**
  - `_loadSettings()` - Reads from `company_settings` table
  - `setHomeIcon()` - Upserts to `company_settings` table
  - `uploadCompanyLogo()` - Upserts to `company_settings` table
  - `removeCompanyLogo()` - Updates `company_settings` table (sets value to null)
  - Cache-buster still works (appended dynamically in getter)

### UI (lib/modules/settings/pages/appearance_settings_page.dart)
- Added "Refrescar" button next to "Eliminar" button
- Button calls `appearanceService.refreshLogo()` to force cache update
- Shows "Logo actualizado" snackbar confirmation

---

## ✅ Testing Steps

1. **Deploy database schema** (Step 1 above)
2. **Deploy Flutter app** (Step 2 above)
3. **Test sync:**
   - Open app on Computer A
   - Go to Settings → Appearance
   - Upload a new logo
   - Open app on Computer B (different device/browser)
   - Logo should appear within 2 seconds (auto-refresh)
   - If not, click "Refrescar" button
4. **Verify database:**
   - Open Supabase Dashboard → Table Editor
   - Check `company_settings` table
   - Should see row with key='company_logo' and value=URL

---

## 🐛 Troubleshooting

### Logo still not syncing
- Check Supabase logs for errors
- Verify `company_settings` table exists and has data
- Clear browser cache completely (Cmd+Shift+R on Mac, Ctrl+Shift+R on Windows)
- Check network tab for 403/404 errors on logo URL

### Database deployment failed
- Make sure you copied the ENTIRE core_schema.sql file
- Check for syntax errors in Supabase SQL editor
- Verify you have admin access to the Supabase project

### App crashes after deployment
- Check Flutter console for errors
- Verify Supabase connection is working
- Ensure `supabase_flutter` package is properly initialized

---

## 📊 Migration Notes

**Existing users:** Old logo URLs stored in SharedPreferences will NOT automatically migrate. Users will need to:
- Re-upload their logo once after this update, OR
- Manually insert their logo URL into the `company_settings` table

**SQL to manually migrate existing logo:**
```sql
INSERT INTO company_settings (key, value)
VALUES ('company_logo', 'YOUR_EXISTING_LOGO_URL_HERE')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

---

## 🎯 Expected Behavior

After successful deployment:
- ✅ Upload logo on any device → All devices see it
- ✅ Change logo → All devices update automatically
- ✅ Delete logo → Removed from all devices
- ✅ Click "Refrescar" → Forces immediate update
- ✅ Restart app → Auto-refreshes logo within 2 seconds
- ✅ Works across different browsers and computers

---

## 🔐 Security Note

The `company_settings` table should have Row Level Security (RLS) enabled:
```sql
-- Enable RLS
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read
CREATE POLICY "Allow authenticated read" ON company_settings
  FOR SELECT TO authenticated USING (true);

-- Allow authenticated users to update (admin only recommended)
CREATE POLICY "Allow authenticated update" ON company_settings
  FOR UPDATE TO authenticated USING (true);
```

Add this to `supabase/sql/rls_policies.sql` if needed.
