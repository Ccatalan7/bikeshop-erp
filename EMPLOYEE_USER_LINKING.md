# Employee-User Linking System

## Overview
Hybrid system that links employees with user accounts when granting system access.

## Features Built (October 29, 2025)

### ✅ Database Schema (`core_schema.sql`)
- **`job_roles` table**: Standardized roles (admin, manager, cashier, mechanic, accountant)
- **`employees.system_role`**: Links employee to job role
- **`employees.tenant_id`**: Multi-tenant support
- **`user_profiles.employee_id`**: Bidirectional link to employee
- **Auto-seeding**: New tenants get 5 job roles automatically

### ✅ Flutter Services
- **JobRoleService** (`lib/shared/services/job_role_service.dart`)
  - Get all roles for tenant
  - Get role by code
  - Get suggested job titles
  - Get default permissions
  - Smart role inference from job title

- **HRService** (`lib/modules/hr/services/hr_service.dart`)
  - `createUserForEmployee()` - Create user invitation
  - `linkEmployeeToUser()` - Bidirectional linking
  - `unlinkEmployeeFromUser()` - Remove link

### ✅ Flutter UI
- **Employee Form** (`lib/modules/hr/pages/employee_list_page.dart`)
  - Role selection dropdown
  - Smart job title suggestions (dropdown when role selected)
  - "Grant System Access" checkbox
  - Email validation for user creation
  - Success/error feedback

### ✅ Models
- **JobRole** (`lib/shared/models/job_role.dart`)
  - systemRole, displayName, suggestedTitles, defaultPermissions
  - Smart inference: "Gerente de Ventas" → 'manager'
  
- **Employee** (`lib/modules/hr/models/hr_models.dart`)
  - Added `systemRole` field
  - Updated serialization (fromMap/toMap)

## How It Works

### 1. Create Employee Without System Access
```dart
Employee(
  firstName: 'Juan',
  lastName: 'Pérez',
  jobTitle: 'Mecánico Senior',
  systemRole: 'mechanic', // Optional: for reporting/analytics
  // NO user account created
)
```

### 2. Create Employee With System Access
```dart
// User fills form:
// - Selects "Mecánico" role → Suggests job titles
// - Checks "Grant System Access"
// - Provides email

// System:
// 1. Creates employee with system_role='mechanic'
// 2. Creates user_invitation record
// 3. Links employee_id to invitation
// 4. Sends invitation email (TODO: edge function)
// 5. On acceptance: bidirectional link created
```

### 3. User Invitation Flow
```sql
-- Invitation created
INSERT INTO user_invitations (
  tenant_id,
  email,
  role, -- 'mechanic'
  permissions, -- Default from job_role
  employee_id -- Link to employee
);

-- When user accepts:
-- 1. Create user in auth.users
-- 2. Create user_profile with employee_id
-- 3. Update employee with user_id
```

## Database Tables

### job_roles
```sql
- tenant_id (multi-tenant)
- system_role (admin, manager, cashier, mechanic, accountant)
- display_name (Administrador, Gerente, Cajero, Mecánico, Contador)
- suggested_titles (array of job title suggestions)
- default_permissions (JSONB with role permissions)
- sort_order, is_active
```

### employees
```sql
- system_role → job_roles.system_role (optional)
- user_id → auth.users.id (when granted access)
```

### user_profiles
```sql
- employee_id → employees.id (bidirectional link)
```

### user_invitations (NEW)
```sql
- tenant_id
- email
- role (from job_roles.system_role)
- permissions (default from job_role)
- employee_id (links to employee)
- status (pending, accepted, expired)
- invited_by
- metadata (first_name, last_name, etc.)
```

## Smart Role Inference

```dart
JobRole.inferSystemRole('Gerente de Ventas') → 'manager'
JobRole.inferSystemRole('Cajero') → 'cashier'
JobRole.inferSystemRole('Mecánico Senior') → 'mechanic'
JobRole.inferSystemRole('Contador General') → 'accountant'
```

## UI Flow

1. **Open Employee Form** → Shows role dropdown
2. **Select Role** (e.g., "Gerente") → Job title field becomes dropdown with suggestions:
   - Gerente de Ventas
   - Gerente de Taller
   - Gerente de Operaciones
   - Subgerente
   - Otro (personalizado)...
3. **Choose Job Title** → Can pick suggestion or enter custom
4. **Check "Grant System Access"** → Shows blue info box with permissions preview
5. **Enter Email** → Required for user account creation
6. **Save** → Creates employee + user invitation

## Permissions (From job_roles)

```javascript
// Admin
{
  "access_pos": true,
  "create_invoices": true,
  "edit_prices": true,
  "delete_invoices": true,
  "access_accounting": true,
  "manage_users": true,
  "edit_settings": true
}

// Manager
{
  "access_pos": true,
  "create_invoices": true,
  "edit_prices": true,
  "delete_invoices": true,
  "access_accounting": true,
  "manage_users": true,
  "edit_settings": false // Only difference from admin
}

// Cashier
{
  "access_pos": true,
  "create_invoices": true,
  "edit_prices": false,
  "delete_invoices": false,
  "access_accounting": false,
  "manage_users": false,
  "edit_settings": false
}

// Mechanic
{
  "access_pos": false,
  "create_invoices": false,
  "edit_prices": false,
  "delete_invoices": false,
  "access_accounting": false,
  "manage_users": false,
  "edit_settings": false
}

// Accountant
{
  "access_pos": false,
  "create_invoices": false,
  "edit_prices": false,
  "delete_invoices": false,
  "access_accounting": true, // Only accounting access
  "manage_users": false,
  "edit_settings": false
}
```

## TODO

- [ ] Implement email invitation edge function (Supabase)
- [ ] Add "Resend Invitation" button in employee detail
- [ ] Show invitation status in employee list/detail
- [ ] Add "Revoke Access" button to unlink user
- [ ] Update user management page to show linked employee
- [ ] Create role management page (edit suggested titles, permissions)
- [ ] Add audit log for user access grants/revocations

## Testing

1. Create new tenant → Verify 5 job roles seeded
2. Create employee without access → No invitation created
3. Create employee with access → Invitation created, email sent (TODO)
4. Accept invitation → Employee and user linked bidirectionally
5. Test with multiple tenants → Verify data isolation

## Files Modified/Created

### Created
- `lib/shared/models/job_role.dart`
- `lib/shared/services/job_role_service.dart`
- `supabase/sql/verify_user_setup.sql`

### Modified
- `supabase/sql/core_schema.sql` (lines 9182-9360, 11289-11354)
- `lib/modules/hr/models/hr_models.dart` (Employee model)
- `lib/modules/hr/services/hr_service.dart` (user creation methods)
- `lib/modules/hr/pages/employee_list_page.dart` (form UI)
- `lib/main.dart` (JobRoleService provider)
