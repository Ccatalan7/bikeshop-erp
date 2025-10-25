# 🚀 DEPLOY MULTI-TENANT SYSTEM - STEP BY STEP

## ⚠️ CRITICAL: Read This First

**Your Supabase Project:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co`

**What we're deploying:**
1. ✅ **OAuth fixes** - Google Sign-In now works properly (already in code)
2. ✅ **Auto-signup system** - New users get their own tenant automatically
3. ✅ **Invitation system** - Managers can invite employees to join their tenant

**Files ready to deploy:**
- `supabase/sql/core_schema.sql` - Complete database schema with multi-tenant support
- `supabase/sql/DEPLOY_MULTI_TENANT_SYSTEM.sql` - Verification script

---

## 📋 Pre-Deployment Checklist

Before you deploy, verify:

- [ ] You can access Supabase dashboard: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf
- [ ] You have the SQL Editor open: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql/new
- [ ] You're logged in as the project owner (admin access)
- [ ] You've backed up your current database (optional but recommended)

---

## 🔧 STEP 1: Configure OAuth Redirect URLs

**THIS IS CRITICAL - Without this, Google Sign-In will still get stuck!**

### 1.1 Open Authentication Settings

Go to: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/url-configuration

### 1.2 Add Redirect URLs

**In the "Redirect URLs" section, add these URLs:**

```
http://localhost:3000/
http://localhost:8080/
http://localhost:5000/
io.supabase.vinabikeerp://login-callback/
```

**Click "Save" after adding all URLs.**

### 1.3 Verify Site URL

**In the "Site URL" field, verify it's set to:**
```
http://localhost:3000/
```

(This is the default redirect after successful login)

---

## 🗄️ STEP 2: Deploy Database Schema

### 2.1 Open SQL Editor

Go to: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql/new

### 2.2 Run core_schema.sql

**Method A: Copy-Paste (Recommended)**

1. Open `c:\dev\ProjectVinabike\supabase\sql\core_schema.sql`
2. Select ALL (Ctrl+A)
3. Copy (Ctrl+C)
4. Paste into Supabase SQL Editor
5. Click "Run" (or press Ctrl+Enter)

**Wait for execution... This may take 30-60 seconds.**

**Expected output:**
- Should see green checkmarks
- "Success. No rows returned" is NORMAL for this script
- If you see errors, scroll down to "Troubleshooting" section

**Method B: Upload File (Alternative)**

1. Click "Import SQL" button in SQL Editor
2. Select `core_schema.sql` from your local drive
3. Click "Run"

### 2.3 Verify Deployment

Run this verification script:

```sql
-- Check if all tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public'
  AND table_name IN ('tenants', 'user_invitations', 'user_activity_log')
ORDER BY table_name;
```

**Expected output:** 3 rows (tenants, user_activity_log, user_invitations)

---

## ✅ STEP 3: Verify Auto-Signup Trigger

Run this query to check if the signup trigger is active:

```sql
-- Check trigger exists
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';
```

**Expected output:** 1 row showing trigger `on_auth_user_created` on `users` table

---

## 👥 STEP 4: Verify Existing Users

Check that your 3 users are properly assigned to Vinabike tenant:

```sql
-- Check user assignments
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role,
  created_at
FROM auth.users
ORDER BY created_at;
```

**Expected output:**
- `admin@vinabike.cl` → tenant_id: `97ef40bf...`, role: `manager`
- `vinabikechile@gmail.com` → tenant_id: `97ef40bf...`, role: `manager`
- `ccatalansandoval7@gmail.com` → tenant_id: `97ef40bf...`, role: `manager`

**If any user is missing tenant_id, run this fix:**

```sql
-- Fix missing tenant assignments
UPDATE auth.users 
SET raw_user_meta_data = jsonb_build_object(
  'tenant_id', '97ef40bf-f58c-4f76-a629-c013fb3928cf',
  'role', 'manager',
  'permissions', jsonb_build_object(
    'manage_users', true,
    'manage_inventory', true,
    'manage_sales', true,
    'manage_purchases', true,
    'view_reports', true,
    'manage_settings', true
  )
)
WHERE email IN (
  'admin@vinabike.cl',
  'vinabikechile@gmail.com',
  'ccatalansandoval7@gmail.com'
)
AND (raw_user_meta_data->>'tenant_id') IS NULL;
```

---

## 🧪 STEP 5: Test OAuth Login

### 5.1 Log Out from All Devices

**CRITICAL:** You MUST log out to refresh JWT tokens with new metadata!

1. In the Flutter app, click "Sign Out"
2. Clear browser cache (Chrome: Ctrl+Shift+Delete → "Cookies and site data" → Clear)
3. Close all browser tabs with the app

### 5.2 Test Google Sign-In (Web)

1. Open app in browser: `http://localhost:YOUR_PORT/`
2. Click "Sign in with Google"
3. **Expected:** Browser redirects to Google login
4. Select your account (e.g., `ccatalansandoval7@gmail.com`)
5. **Expected:** Redirects back to `http://localhost:YOUR_PORT/`
6. **Expected:** You're logged in, see dashboard

**If stuck:** Check browser console (F12) for errors → See troubleshooting section below

### 5.3 Test Google Sign-In (Desktop)

1. Run app: `flutter run -d windows`
2. Click "Sign in with Google"
3. **Expected:** Opens Google login in external browser
4. Select your account
5. **Expected:** Browser shows "Return to Vinabike ERP" or similar link
6. Click the link
7. **Expected:** Desktop app receives deep link, you're logged in

---

## 🎯 STEP 6: Test Auto-Signup System

### 6.1 Create Test User (Auto-Tenant Creation)

**Test with a NEW email (not previously registered):**

1. Sign up with email: `test-random-user@example.com`
2. **Expected:** 
   - User account created
   - NEW tenant created automatically
   - User assigned as manager of their tenant
   - User sees empty dashboard (their own data)

### 6.2 Verify New Tenant Created

```sql
-- Check if new tenant was created
SELECT 
  id,
  shop_name,
  owner_email,
  plan,
  created_at
FROM tenants
ORDER BY created_at DESC
LIMIT 1;
```

**Expected:** New tenant with `owner_email = 'test-random-user@example.com'`

### 6.3 Verify User Assigned to New Tenant

```sql
-- Check user metadata
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE email = 'test-random-user@example.com';
```

**Expected:** tenant_id matches the new tenant's ID, role = 'manager'

---

## 📨 STEP 7: Test Invitation System (Optional - UI not built yet)

**This will be available after we build the User Management UI in the next phase.**

For now, you can test manually via SQL:

### 7.1 Create Invitation

```sql
-- Create invitation for employee to join Vinabike tenant
INSERT INTO user_invitations (
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at
)
VALUES (
  '97ef40bf-f58c-4f76-a629-c013fb3928cf', -- Vinabike tenant ID
  'test-employee@example.com', -- Employee email
  'cashier', -- Role
  jsonb_build_object(
    'manage_sales', true,
    'view_inventory', true
  ), -- Limited permissions
  (SELECT id FROM auth.users WHERE email = 'admin@vinabike.cl'), -- Invited by admin
  'pending',
  NOW() + INTERVAL '7 days'
);
```

### 7.2 Test Invited Signup

1. Sign up with `test-employee@example.com`
2. **Expected:**
   - User joins EXISTING Vinabike tenant (not new tenant)
   - User assigned role 'cashier' (from invitation)
   - User has limited permissions (from invitation)
   - Invitation status changes to 'accepted'

### 7.3 Verify Invited User Joined Existing Tenant

```sql
-- Check user joined Vinabike tenant
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE email = 'test-employee@example.com';
```

**Expected:** tenant_id = `97ef40bf...` (same as Vinabike), role = 'cashier'

---

## 🔍 Troubleshooting

### Issue: "Google Sign-In gets stuck after clicking button"

**Causes:**
1. Redirect URLs not configured in Supabase dashboard
2. Browser blocking popups
3. CORS issues

**Fixes:**
1. Verify redirect URLs in Step 1.2
2. Allow popups in browser settings
3. Check browser console (F12) → Console tab → look for CORS errors

### Issue: "Redirect URL not whitelisted"

**Fix:**
1. Go to: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/url-configuration
2. Add the missing redirect URL shown in error message
3. Click "Save"
4. Try logging in again

### Issue: "User has no tenant_id after login"

**Causes:**
1. User logged in BEFORE schema deployment
2. JWT token not refreshed

**Fixes:**
1. Log out completely
2. Clear browser cache
3. Close all browser tabs
4. Log in again
5. Check user metadata with SQL query from Step 4

### Issue: "Auto-signup didn't create tenant"

**Causes:**
1. Trigger not deployed or disabled
2. Email already exists in auth.users

**Fixes:**
1. Verify trigger exists (Step 3 query)
2. Use a NEW email address for testing
3. Check Supabase logs for trigger errors

### Issue: "Invited user got their own tenant instead of joining existing"

**Causes:**
1. No pending invitation for that email
2. Invitation expired
3. Email mismatch (case-sensitive)

**Fixes:**
1. Check invitation exists:
```sql
SELECT * FROM user_invitations 
WHERE email = 'test-employee@example.com' 
  AND status = 'pending';
```
2. Ensure invitation not expired (`expires_at > NOW()`)
3. Match email exactly (case-sensitive)

### Issue: "RLS blocks all queries, user sees empty lists"

**Causes:**
1. User's JWT doesn't contain tenant_id
2. RLS policies not deployed

**Fixes:**
1. Log out and back in to refresh JWT
2. Verify user has tenant_id (Step 4 query)
3. Verify RLS policies exist:
```sql
SELECT tablename, policyname 
FROM pg_policies 
WHERE schemaname = 'public' 
  AND policyname LIKE '%tenant%';
```

---

## 📊 Success Indicators

After deployment, you should see:

- ✅ **OAuth works:** Google Sign-In redirects properly, no stuck behavior
- ✅ **Tenant isolation:** Users only see their own tenant's data
- ✅ **Auto-signup works:** New users get their own tenant automatically
- ✅ **Invitation works:** Invited users join existing tenant with assigned role
- ✅ **RLS active:** Can't query other tenants' data even via SQL
- ✅ **3 users in Vinabike tenant:** admin@vinabike.cl, vinabikechile@gmail.com, ccatalansandoval7@gmail.com

---

## 🎉 Next Steps After Successful Deployment

1. **Test login with all 3 Vinabike users**
   - admin@vinabike.cl
   - vinabikechile@gmail.com
   - ccatalansandoval7@gmail.com

2. **Verify tenant isolation**
   - Create a test product as admin@vinabike.cl
   - Sign up as test-random-user@example.com
   - Verify you CAN'T see admin's products

3. **Build User Management UI** (next phase)
   - UserManagementPage to list tenant users
   - UserInvitePage to invite new employees
   - UserEditPage to edit user roles/permissions

4. **Add navigation to Settings module**
   - "User Management" menu item
   - Only visible to users with `manage_users` permission

---

## 📞 Need Help?

**Check these logs:**

1. **Browser Console:** F12 → Console tab (for OAuth errors)
2. **Supabase Logs:** https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/logs/explorer
3. **Flutter Debug Console:** Run app with `flutter run` to see debug output

**Common error messages:**
- "Redirect URL not whitelisted" → Add URL in Supabase dashboard
- "User not found" → User needs to log out and back in
- "Permission denied" → RLS blocking query, check tenant_id in JWT
- "Relation does not exist" → Schema not deployed, check Step 2

---

**Ready to deploy? Start with STEP 1! 🚀**
