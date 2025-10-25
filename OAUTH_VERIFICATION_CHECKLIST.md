# 🔐 OAuth Verification Checklist

## What We Fixed

**Problem:** Google Sign-In was getting stuck, redirects weren't working properly.

**Root Causes:**
1. ❌ Missing platform-specific redirect URLs in `AuthService`
2. ❌ No session refresh mechanism after metadata updates
3. ❌ Deep link handling incomplete in `main.dart`
4. ❌ Loading state management issues in `LoginScreen`

**Solutions Applied:**
1. ✅ Added platform detection in `signInWithGoogle()`:
   - Web: Uses `Uri.base.origin + '/'`
   - Desktop/Mobile: Uses `io.supabase.vinabikeerp://login-callback/`
2. ✅ Added `refreshSession()` method to force JWT refresh
3. ✅ Enhanced deep link handling with `getInitialLink()`
4. ✅ Improved async flow in login screen

---

## Verification Steps

### 1. Check Supabase Dashboard OAuth Settings

**Go to:** Supabase Dashboard → Authentication → URL Configuration

**Verify these redirect URLs are configured:**

```
# For Web App
https://your-domain.com/
http://localhost:3000/

# For Desktop App (Windows/macOS/Linux)
io.supabase.vinabikeerp://login-callback/

# For Mobile App (Android/iOS)
io.supabase.vinabikeerp://login-callback/
```

**If missing, add them manually in Supabase dashboard!**

---

### 2. Test Web OAuth Flow

**Steps:**
1. Open app in Chrome: `http://localhost:YOUR_PORT/`
2. Click "Sign in with Google"
3. **Expected:** Opens Google login in same window/tab
4. **Expected:** After selecting account, redirects back to `http://localhost:YOUR_PORT/`
5. **Expected:** You're logged in, see dashboard

**If stuck:**
- Open browser DevTools (F12)
- Check Console tab for errors
- Look for redirect URL mismatches
- Check Network tab for failed auth requests

---

### 3. Test Desktop OAuth Flow

**Steps:**
1. Run app: `flutter run -d windows` (or macos/linux)
2. Click "Sign in with Google"
3. **Expected:** Opens Google login in external browser
4. **Expected:** After selecting account, shows "Return to Vinabike ERP" link
5. **Expected:** Click link → app receives deep link callback
6. **Expected:** You're logged in in the desktop app

**If stuck:**
- Check if deep link `io.supabase.vinabikeerp://login-callback/` is registered
- Check debug console for "Deep link received:" logs
- Verify `app_links` package is configured properly

---

### 4. Test JWT Refresh After Metadata Update

**Scenario:** Admin assigns you to a tenant via SQL

**Steps:**
1. Log in as `ccatalansandoval7@gmail.com`
2. Admin runs SQL to update your `tenant_id`
3. **Old behavior:** RLS blocks all queries, you see empty lists
4. **New behavior:** Call `await authService.refreshSession()` programmatically OR log out and back in
5. **Expected:** JWT refreshes with new `tenant_id`, RLS allows queries

**Test this:**
```dart
// In any page with AuthService injected
final authService = context.read<AuthService>();
await authService.refreshSession();
// Now tenant_id should be in JWT
```

---

### 5. Check Browser Console for Errors

**Common errors:**

```
❌ "Redirect URL not whitelisted"
→ Fix: Add redirect URL in Supabase dashboard

❌ "Deep link not registered"
→ Fix: Check app_links configuration in AndroidManifest.xml / Info.plist

❌ "Session expired"
→ Fix: Call refreshSession() or log out/in

❌ "CORS error"
→ Fix: Check Supabase project URL is correct in main.dart
```

---

## Files Modified

### 1. `lib/shared/services/auth_service.dart`
- ✅ Line 67-88: `signInWithGoogle()` with platform-specific redirects
- ✅ Line 90-99: `refreshSession()` method added

### 2. `lib/shared/screens/login_screen.dart`
- ✅ Line 114-145: Improved `_signInWithGoogle()` flow
- ✅ Removed blocking Windows dialog
- ✅ Better loading state management

### 3. `lib/main.dart`
- ✅ Line 57-67: Enhanced deep link handling
- ✅ Added `getInitialLink()` for OAuth callbacks

---

## Testing Checklist

- [ ] Verify redirect URLs in Supabase dashboard
- [ ] Test Google Sign-In on web (Chrome)
- [ ] Test Google Sign-In on desktop (Windows)
- [ ] Test session refresh after SQL metadata update
- [ ] Check browser console for errors
- [ ] Verify JWT contains `tenant_id` after login
- [ ] Test RLS policies with new user
- [ ] Test auto-signup flow (new random user creates tenant)
- [ ] Test invitation flow (invited user joins existing tenant)

---

## Quick Diagnostics

### Check if user has tenant_id in JWT:

```sql
-- Run in Supabase SQL Editor
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE email = 'YOUR_EMAIL@gmail.com';
```

### Check if RLS is working:

```dart
// In Flutter app, after login
final user = Supabase.instance.client.auth.currentUser;
print('User metadata: ${user?.userMetadata}');
print('Tenant ID: ${user?.userMetadata?['tenant_id']}');

// Try fetching tenant data
final response = await Supabase.instance.client
  .from('tenants')
  .select()
  .single();
print('My tenant: $response');
```

---

## Success Criteria

✅ **OAuth flow works:** Click Google Sign-In → Redirects to Google → Select account → Redirects back to app → Logged in

✅ **JWT contains tenant_id:** Check user metadata after login

✅ **RLS allows queries:** Can fetch products, customers, invoices from my tenant

✅ **RLS blocks other tenants:** Can't see data from other tenants

✅ **Auto-signup works:** New random user gets own tenant created automatically

✅ **Invitation works:** Invited user joins existing tenant with assigned role

---

## Next Steps

1. **Deploy updated schema:** Run `DEPLOY_MULTI_TENANT_SYSTEM.sql` in Supabase
2. **Test OAuth fixes:** Try Google Sign-In with your account
3. **Build invitation UI:** Create UserManagementPage to invite employees
4. **Test complete flows:** Public signup vs invited signup

---

**Need help?** Check browser console, Supabase logs, and Flutter debug console for error messages.
