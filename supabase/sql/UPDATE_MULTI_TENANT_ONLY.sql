-- ============================================================================
-- VINABIKE ERP - MULTI-TENANT UPDATE (ONLY NEW COMPONENTS)
-- ============================================================================
-- This script adds ONLY the new multi-tenant components without re-creating
-- existing policies and tables. Run this instead of full core_schema.sql
-- ============================================================================

-- ============================================================================
-- STEP 1: Create user_invitations table (if not exists)
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('manager', 'cashier', 'mechanic', 'accountant', 'viewer')),
  permissions JSONB DEFAULT '{}'::jsonb,
  invited_by UUID REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(tenant_id, email, status)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_invitations_email ON user_invitations(email) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_user_invitations_tenant ON user_invitations(tenant_id);

-- ============================================================================
-- STEP 2: Enable RLS on user_invitations
-- ============================================================================

ALTER TABLE user_invitations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS tenant_invitations_select ON user_invitations;
DROP POLICY IF EXISTS tenant_invitations_insert ON user_invitations;
DROP POLICY IF EXISTS tenant_invitations_update ON user_invitations;

-- Users can view invitations for their tenant
CREATE POLICY tenant_invitations_select ON user_invitations
  FOR SELECT
  USING (tenant_id = public.user_tenant_id());

-- Users with manage_users permission can create invitations
CREATE POLICY tenant_invitations_insert ON user_invitations
  FOR INSERT
  WITH CHECK (
    tenant_id = public.user_tenant_id() 
    AND (current_setting('request.jwt.claims', true)::json->'user_metadata'->>'permissions')::jsonb->>'manage_users' = 'true'
  );

-- Users with manage_users permission can update invitations
CREATE POLICY tenant_invitations_update ON user_invitations
  FOR UPDATE
  USING (
    tenant_id = public.user_tenant_id() 
    AND (current_setting('request.jwt.claims', true)::json->'user_metadata'->>'permissions')::jsonb->>'manage_users' = 'true'
  );

-- ============================================================================
-- STEP 3: Create or replace auto-signup trigger function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invitation user_invitations%ROWTYPE;
  v_new_tenant_id UUID;
  v_tenant_name TEXT;
BEGIN
  -- Check if user was invited
  SELECT * INTO v_invitation
  FROM user_invitations
  WHERE email = NEW.email
    AND status = 'pending'
    AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    -- User was invited - assign to existing tenant with invitation's role
    NEW.raw_user_meta_data = jsonb_build_object(
      'tenant_id', v_invitation.tenant_id,
      'role', v_invitation.role,
      'permissions', v_invitation.permissions
    );

    -- Mark invitation as accepted
    UPDATE user_invitations
    SET status = 'accepted',
        updated_at = NOW()
    WHERE id = v_invitation.id;

    -- Log activity
    INSERT INTO user_activity_log (tenant_id, user_id, action, details)
    VALUES (
      v_invitation.tenant_id,
      NEW.id,
      'user_joined_via_invitation',
      jsonb_build_object(
        'email', NEW.email,
        'role', v_invitation.role,
        'invited_by', v_invitation.invited_by
      )
    );

  ELSE
    -- No invitation - create new tenant for this user
    v_tenant_name := COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.email
    ) || '''s Shop';

    INSERT INTO tenants (shop_name, owner_email, plan, is_active)
    VALUES (v_tenant_name, NEW.email, 'free', true)
    RETURNING id INTO v_new_tenant_id;

    -- Assign user as manager of new tenant
    NEW.raw_user_meta_data = jsonb_build_object(
      'tenant_id', v_new_tenant_id,
      'role', 'manager',
      'permissions', jsonb_build_object(
        'manage_users', true,
        'manage_inventory', true,
        'manage_sales', true,
        'manage_purchases', true,
        'manage_customers', true,
        'manage_suppliers', true,
        'manage_accounting', true,
        'manage_hr', true,
        'manage_maintenance', true,
        'view_reports', true,
        'manage_settings', true,
        'manage_website', true,
        'manage_marketing', true
      )
    );

    -- Log activity
    INSERT INTO user_activity_log (tenant_id, user_id, action, details)
    VALUES (
      v_new_tenant_id,
      NEW.id,
      'tenant_created',
      jsonb_build_object(
        'email', NEW.email,
        'shop_name', v_tenant_name
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 4: Create trigger on auth.users (drop existing first)
-- ============================================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- STEP 5: Verify deployment
-- ============================================================================

DO $$
BEGIN
  -- Check user_invitations table exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_invitations') THEN
    RAISE EXCEPTION 'ERROR: user_invitations table was not created!';
  END IF;
  
  -- Check trigger exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created'
  ) THEN
    RAISE EXCEPTION 'ERROR: Signup trigger was not created!';
  END IF;
  
  RAISE NOTICE '✅ Multi-tenant update deployed successfully!';
  RAISE NOTICE '✅ Auto-signup trigger active';
  RAISE NOTICE '✅ Invitation system ready';
END $$;

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

SELECT 
  '🎉 DEPLOYMENT COMPLETE!' as status,
  COUNT(*) as total_tenants
FROM tenants;

SELECT 
  '👥 Current Users' as info,
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
ORDER BY created_at;
