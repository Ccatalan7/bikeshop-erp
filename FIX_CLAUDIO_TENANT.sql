-- ============================================================================
-- FIX: Update ccatalansandoval7@gmail.com to correct tenant
-- ============================================================================
-- This updates the user metadata to the correct tenant
-- Run this in SQL Editor with service role
-- ============================================================================

-- First, verify the tenant IDs
SELECT id, shop_name, owner_email FROM tenants;
-- Vinabike: 97ef40bf-f58c-4f76-a629-c013fb3928cf
-- Claudio: 5fb195aa-2ec5-4a5d-b057-ed61156312ec

-- Update Claudio's user record to point to HIS tenant (not Vinabike)
UPDATE auth.users
SET raw_user_meta_data = jsonb_build_object(
  'tenant_id', '5fb195aa-2ec5-4a5d-b057-ed61156312ec',
  'role', 'manager',
  'permissions', jsonb_build_object(
    'access_pos', true,
    'manage_inventory', true,
    'view_reports', true,
    'manage_accounting', true,
    'manage_users', true,
    'delete_invoices', true,
    'edit_prices', true,
    'access_hr', true
  )
)
WHERE email = 'ccatalansandoval7@gmail.com';

-- Verify the update
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE email = 'ccatalansandoval7@gmail.com';

-- ============================================================================
-- AFTER RUNNING THIS:
-- 1. Sign out COMPLETELY from the app (click sign out button)
-- 2. Sign back in as ccatalansandoval7@gmail.com
-- 3. Check products - should see ZERO Vinabike products
-- ============================================================================
