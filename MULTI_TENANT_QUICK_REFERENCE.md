# 🎯 QUICK REFERENCE: Multi-Tenant System

## 🔗 Important Links

**Supabase Dashboard:** https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf

**SQL Editor:** https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql/new

**Auth Settings:** https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/auth/url-configuration

**Logs:** https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/logs/explorer

---

## 📝 Quick Commands

### Check User Tenant Assignment
```sql
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
ORDER BY created_at;
```

### Force User Refresh (after SQL updates)
```dart
final authService = context.read<AuthService>();
await authService.refreshSession();
```

### Create Invitation (SQL)
```sql
INSERT INTO user_invitations (tenant_id, email, role, invited_by, expires_at)
VALUES (
  '97ef40bf-f58c-4f76-a629-c013fb3928cf',
  'employee@example.com',
  'cashier',
  (SELECT id FROM auth.users WHERE email = 'admin@vinabike.cl'),
  NOW() + INTERVAL '7 days'
);
```

### Check Trigger Status
```sql
SELECT trigger_name 
FROM information_schema.triggers 
WHERE trigger_name = 'on_auth_user_created';
```

---

## 🗺️ System Architecture

**Vinabike Tenant ID:** `97ef40bf-f58c-4f76-a629-c013fb3928cf`

**Current Users:**
- admin@vinabike.cl → manager
- vinabikechile@gmail.com → manager  
- ccatalansandoval7@gmail.com → manager

**Auto-Signup Flow:**
1. User signs up (email or Google)
2. Trigger `handle_new_user()` fires
3. Check for pending invitation:
   - **Found:** Assign to invitation's tenant with invitation's role
   - **Not found:** Create new tenant, assign user as manager

**OAuth Redirect URLs:**
- Web: `http://localhost:3000/`
- Desktop/Mobile: `io.supabase.vinabikeerp://login-callback/`

---

## 🚨 Common Issues & Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| Google Sign-In stuck | Add redirect URLs in Supabase dashboard (Auth → URL Config) |
| User has no tenant_id | Log out → Clear cache → Log in again |
| RLS blocks queries | User needs to refresh JWT (log out/in or call `refreshSession()`) |
| New user didn't get tenant | Check trigger exists (see SQL above) |
| Invited user got own tenant | Verify invitation exists and not expired |

---

## 📚 Documentation Files

**Deployment:**
- `DEPLOY_MULTI_TENANT_STEP_BY_STEP.md` - Complete deployment guide
- `DEPLOY_MULTI_TENANT_SYSTEM.sql` - Verification script
- `MULTI_TENANT_GUIDE.md` - Architecture overview

**OAuth:**
- `OAUTH_VERIFICATION_CHECKLIST.md` - OAuth testing guide

**Schema:**
- `supabase/sql/core_schema.sql` - MASTER DATABASE FILE (10,788 lines)

---

## ⚡ Critical Rules

1. **NEVER edit the 3-file split** (`1_core_tables.sql`, `2_business_logic.sql`, `3_analytics_views.sql`) - they're GENERATED from `core_schema.sql`

2. **ALWAYS edit `core_schema.sql`** for schema changes

3. **USERS MUST LOG OUT/IN** after SQL metadata updates to refresh JWT

4. **SEARCH BEFORE CREATING** functions/triggers to avoid duplicates

5. **CHECK REDIRECT URLs** in Supabase dashboard if OAuth gets stuck

---

## 🎯 Next Phase: User Management UI

**Remaining tasks:**
1. ✅ Database schema deployed
2. ✅ OAuth fixes deployed
3. ⏳ Build `UserManagementPage` (list users)
4. ⏳ Build `UserInvitePage` (invite dialog)
5. ⏳ Build `UserEditPage` (edit roles)
6. ⏳ Add to Settings module navigation
7. ⏳ Test complete flows

**Implementation priority:**
1. `UserManagementService.inviteUser()` method
2. `UserManagementPage` with user list table
3. `UserInvitePage` with email + role form
4. Settings module integration
5. End-to-end testing

---

**Questions? Check `DEPLOY_MULTI_TENANT_STEP_BY_STEP.md` for detailed instructions!**
