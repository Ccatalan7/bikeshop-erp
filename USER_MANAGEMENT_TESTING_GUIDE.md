# 🎉 USER MANAGEMENT SYSTEM - READY TO TEST!

## ✅ What's Complete

1. **Database Schema**
   - ✅ `user_invitations` table created
   - ✅ Auto-signup trigger (`handle_new_user()`)
   - ✅ RLS policies for tenant isolation
   - ✅ All 3 existing users assigned to Vinabike tenant

2. **Backend Services**
   - ✅ `UserManagementService` with `inviteUser()` method
   - ✅ Service added to Provider tree
   - ✅ OAuth fixes deployed and working

3. **User Interface**
   - ✅ `UserManagementPage` - List users with roles/status
   - ✅ `UserInviteDialog` - Invite new users with role selection
   - ✅ `UserEditDialog` - Edit user roles and permissions
   - ✅ Navigation added to Settings → Gestión de Usuarios

---

## 🧪 HOW TO TEST

### **Test 1: Access User Management Page**

1. Navigate to **Configuración** (Settings)
2. Click on **"Gestión de Usuarios"**
3. **Expected:** See list of 3 users:
   - admin@vinabike.cl (Gerente)
   - vinabikechile@gmail.com (Gerente)
   - ccatalansandoval7@gmail.com (Gerente)

---

### **Test 2: Invite a New User**

1. In User Management page, click **"Invitar Usuario"** button
2. Fill in the form:
   - **Email:** `cashier@vinabike.cl`
   - **Rol:** Cajero (Cashier)
   - **Permisos:** Should auto-check based on role
3. Click **"Enviar Invitación"**
4. **Expected:** Success message, page refreshes

**Verify in Supabase:**
```sql
-- Check invitation was created
SELECT * FROM user_invitations 
WHERE email = 'cashier@vinabike.cl';
```

---

### **Test 3: New User Signs Up (Invited User Joins Tenant)**

1. **Log out** from current account
2. Go to **Sign Up** page
3. Create account with:
   - **Email:** `cashier@vinabike.cl` (same as invitation!)
   - **Password:** `cashier123`
4. **Expected:**
   - Account created
   - User assigned to **Vinabike tenant** (NOT new tenant!)
   - User has **Cajero role** (from invitation)
   - User sees Vinabike's products/customers

**Verify in Supabase:**
```sql
-- Check user joined Vinabike tenant
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE email = 'cashier@vinabike.cl';
-- Should show tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf' (Vinabike)
-- Should show role = 'cashier'

-- Check invitation marked as accepted
SELECT status, updated_at 
FROM user_invitations 
WHERE email = 'cashier@vinabike.cl';
-- Should show status = 'accepted'
```

---

### **Test 4: Edit User Role**

1. Log back in as **admin@vinabike.cl**
2. Go to **Settings → Gestión de Usuarios**
3. Find `cashier@vinabike.cl` in the list
4. Click the **⋮** menu → **"Editar"**
5. Change role to **"Contador"** (Accountant)
6. Adjust permissions (e.g., enable "Acceso a Contabilidad")
7. Click **"Guardar Cambios"**
8. **Expected:** Success message, list updates

**Test as cashier:**
- Log out
- Log in as `cashier@vinabike.cl`
- **Expected:** User now has accountant permissions

---

### **Test 5: Suspend/Activate User**

1. As admin, go to User Management
2. Find `cashier@vinabike.cl`
3. Click **⋮** → **"Suspender"**
4. **Expected:** User marked as SUSPENDIDO in list

**Test suspension:**
- Log out
- Try to log in as `cashier@vinabike.cl`
- **Expected:** Login fails (user is banned)

**Reactivate:**
- As admin, click **⋮** → **"Activar"**
- **Expected:** User can log in again

---

### **Test 6: Random User Signs Up (Creates New Tenant)**

1. Log out from Vinabike account
2. Go to **Sign Up** page
3. Create account with:
   - **Email:** `random.user@example.com` (NO invitation exists!)
   - **Password:** `random123`
4. **Expected:**
   - New account created
   - **NEW TENANT created automatically** (not Vinabike!)
   - User is **manager** of new tenant
   - User sees **EMPTY data** (no products, no customers)

**Verify in Supabase:**
```sql
-- Check new tenant was created
SELECT * FROM tenants 
WHERE owner_email = 'random.user@example.com';
-- Should show a NEW tenant (different ID from Vinabike)

-- Check user assigned to new tenant
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE email = 'random.user@example.com';
-- Should show tenant_id = <new tenant ID>
-- Should show role = 'manager'
```

**Verify tenant isolation:**
- As `random.user@example.com`, try to see products
- **Expected:** Empty list (can't see Vinabike's products)
- Create a test product
- Log in as `admin@vinabike.cl`
- **Expected:** Can't see random user's product

---

### **Test 7: Delete User**

1. As admin, go to User Management
2. Find `cashier@vinabike.cl`
3. Click **⋮** → **"Eliminar"**
4. Confirm deletion
5. **Expected:** User removed from list

**Note:** You CANNOT delete yourself (the delete option is hidden)

---

### **Test 8: Reset Password**

1. As admin, go to User Management
2. Find any user
3. Click **⋮** → **"Resetear contraseña"**
4. **Expected:**
   - Success message
   - User receives password reset email
   - User can click link to reset password

---

## 🎯 SUCCESS CRITERIA

✅ **Invitation System:**
- Invitations create records in `user_invitations` table
- Invited users join EXISTING tenant (Vinabike)
- Invited users get assigned role from invitation

✅ **Auto-Signup System:**
- Random users (no invitation) create NEW tenant automatically
- Random users become managers of their own tenant
- Random users see EMPTY data (tenant isolation)

✅ **User Management UI:**
- Can list all users in tenant
- Can invite users with role selection
- Can edit user roles and permissions
- Can suspend/activate users
- Can delete users (except self)
- Can trigger password reset

✅ **Tenant Isolation:**
- Users from different tenants can't see each other's data
- Products, customers, invoices filtered by tenant_id
- RLS policies enforce isolation automatically

---

## 🚨 TROUBLESHOOTING

### **Problem: Invitation not working**

**Check:**
```sql
SELECT * FROM user_invitations WHERE status = 'pending';
```
- Should show pending invitation
- Check `expires_at` is in the future

**Fix:** Email must match exactly (case-insensitive, trimmed)

---

### **Problem: User joined wrong tenant**

**Check:**
```sql
SELECT * FROM user_invitations WHERE email = 'user@email.com';
```
- If no invitation exists → user creates new tenant (expected)
- If invitation exists but expired → user creates new tenant
- If invitation exists and valid → user should join invitation's tenant

**Fix:** Make sure invitation `expires_at` is 7 days in future

---

### **Problem: User sees wrong data**

**Check:**
```sql
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id
FROM auth.users
WHERE email = 'user@email.com';
```
- Verify `tenant_id` matches expected tenant
- If wrong: user needs to log out and back in to refresh JWT

---

### **Problem: Can't edit/delete users**

**Check:**
- Are you a manager?
- Do you have `manage_users` permission?

**Verify:**
```sql
SELECT 
  email,
  raw_user_meta_data->>'role' as role,
  raw_user_meta_data->'permissions'->>'manage_users' as can_manage
FROM auth.users
WHERE email = 'your@email.com';
```

---

## 📋 NEXT STEPS

After testing successfully:

1. **Phase 5: RRHH Integration** (optional)
   - Link user accounts to employee records
   - Show user status in employee list
   - Create user directly from employee detail page

2. **Phase 6: UI Role Guards**
   - Hide "Delete" button from non-managers
   - Hide "User Management" from non-managers
   - Show role-appropriate dashboard

3. **Phase 7: Email Notifications** (optional)
   - Send invitation emails with signup link
   - Send welcome emails to new users
   - Send password reset emails

---

**Ready to test? Start with Test 1 and work your way down!** 🚀
