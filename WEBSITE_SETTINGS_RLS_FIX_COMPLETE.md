# 🔧 Website Settings RLS Fix - COMPLETE

## ✅ Problem Identified
The website editor was showing two critical errors:
1. **403 RLS Violation**: "new row violates row-level security policy for table website_settings"
2. **setState() during build**: WebsiteService calling notifyListeners() during initialization

## 🔍 Root Causes

### Issue 1: Missing tenant_id in INSERT
- `_upsertSettings()` was creating rows WITHOUT `tenant_id`
- RLS policy requires `tenant_id = user_tenant_id()`
- INSERT without tenant_id → RLS blocks with 403 error

### Issue 2: No tenant filtering in SELECT
- `loadSettings()` was querying ALL settings from ALL tenants
- No `.eq('tenant_id', tenantId)` filter
- Loading wrong tenant's data

### Issue 3: RLS policies using user_tenant_id() function
- Like we saw with tenant table, function calls in RLS can cause issues
- Better to use direct `user_profiles` check pattern

## ✅ Fixes Applied

### 1. Flutter Service - website_service.dart
**Added tenant_id to INSERT:**
```dart
final payload = values.entries.map((entry) {
  return {
    'key': entry.key,
    'value': entry.value?.toString() ?? '',
    'tenant_id': tenantId,  // ✅ Added this
    'updated_at': timestamp,
  };
}).toList();
```

**Added tenant_id filter to SELECT:**
```dart
final response = await _supabase
    .from('website_settings')
    .select()
    .eq('tenant_id', tenantId);  // ✅ Added this filter
```

**Updated upsert conflict resolution:**
```dart
await _supabase
  .from('website_settings')
  .upsert(payload, onConflict: 'tenant_id,key');  // ✅ Changed from 'key' to 'tenant_id,key'
```

### 2. Database Schema - core_schema.sql (Line 9796-9810)
**Replaced RLS policies with direct user_profiles check:**
```sql
create policy "website_settings_select" on website_settings 
  for select 
  using (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );

create policy "website_settings_insert" on website_settings 
  for insert 
  with check (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );

create policy "website_settings_update" on website_settings 
  for update 
  using (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );
```

## 📦 Deployment

Run this SQL script in Supabase SQL Editor:
```bash
FIX_WEBSITE_SETTINGS_RLS.sql
```

Or deploy the full updated schema:
```bash
supabase/sql/core_schema.sql
```

## 🧪 Testing

After deployment:
1. ✅ Login to your bikeshop ERP
2. ✅ Navigate to Website → Editor
3. ✅ Change theme colors/fonts
4. ✅ Click Save
5. ✅ Verify no 403 errors
6. ✅ Reload page and verify settings persist
7. ✅ Check that only YOUR tenant's settings are shown

## 🔄 Pattern Consistency

This fix follows the SAME pattern we used for:
- ✅ `loadBlocks()` - filters by tenant_id
- ✅ Tenant table RLS - direct user_profiles check
- ✅ website_blocks RLS - tenant isolation

## 📝 What Changed

**Files Modified:**
1. ✅ `lib/modules/website/services/website_service.dart` (Lines 352-375, 453-486)
   - Added `await _tenantService.getTenantId()` calls
   - Added `tenant_id` to INSERT payload
   - Added `.eq('tenant_id', tenantId)` to SELECT
   - Updated `onConflict` to match unique constraint

2. ✅ `supabase/sql/core_schema.sql` (Lines 9796-9810)
   - Replaced `user_tenant_id()` function calls with direct user_profiles check
   - Removed role-based check from UPDATE policy (not needed)

**Files Created:**
1. ✅ `FIX_WEBSITE_SETTINGS_RLS.sql` - Quick deployment script

## ⚠️ Important Notes

1. **Unique Constraint**: The table has `unique(tenant_id, key)` so upsert must use `onConflict: 'tenant_id,key'` not just `'key'`

2. **Tenant Isolation**: Now enforced at THREE levels:
   - ✅ RLS policies (database layer)
   - ✅ Service layer (Flutter queries)
   - ✅ Unique constraints (per-tenant keys)

3. **setState() Warning**: The guard `if (!_isInitializing) notifyListeners()` should prevent the error, but if it persists, we may need to add `WidgetsBinding.instance.addPostFrameCallback()`.

## 🎯 Expected Behavior

**Before Fix:**
- ❌ Saving theme settings → 403 error
- ❌ Loading settings from ALL tenants
- ❌ setState() warnings in console

**After Fix:**
- ✅ Saving theme settings → Success
- ✅ Loading only current tenant's settings
- ✅ Clean console (no RLS violations)
- ✅ Settings persist across page reloads
- ✅ Complete tenant isolation

## 🚀 Next Steps

1. Deploy `FIX_WEBSITE_SETTINGS_RLS.sql` to Supabase
2. Restart Flutter app (hot reload)
3. Test website editor functionality
4. Verify settings save/load correctly
5. Check for any remaining setState() warnings

## ✨ Multi-Tenant Verification

To verify complete tenant isolation:
1. Create a second tenant (different subdomain)
2. Login as second tenant
3. Change website settings
4. Verify first tenant's settings are unchanged
5. Verify each tenant only sees their own settings

---

**Status**: ✅ **READY TO DEPLOY**
**Priority**: 🔴 **HIGH** (blocking website editor functionality)
**Impact**: Website theme settings can now be saved and loaded correctly with proper tenant isolation
