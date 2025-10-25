-- ============================================================================
-- FIX: Add tenant_id to company_settings table
-- ============================================================================

-- Add tenant_id column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'company_settings' AND column_name = 'tenant_id'
  ) THEN
    ALTER TABLE company_settings 
      ADD COLUMN tenant_id uuid references tenants(id) on delete cascade;
    RAISE NOTICE '✓ Added tenant_id column to company_settings';
  ELSE
    RAISE NOTICE '⚠ tenant_id column already exists in company_settings';
  END IF;
END $$;

-- Assign all existing company_settings to Vinabike tenant
UPDATE company_settings 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Make tenant_id NOT NULL
ALTER TABLE company_settings 
  ALTER COLUMN tenant_id SET NOT NULL;

-- Drop old unique constraint if it exists
DO $$
BEGIN
  ALTER TABLE company_settings DROP CONSTRAINT IF EXISTS company_settings_key_key;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- Add new unique constraint scoped to tenant
ALTER TABLE company_settings 
  DROP CONSTRAINT IF EXISTS company_settings_tenant_id_key_key,
  ADD CONSTRAINT company_settings_tenant_id_key_key UNIQUE (tenant_id, key);

-- Create index
CREATE INDEX IF NOT EXISTS idx_company_settings_tenant ON company_settings(tenant_id);

-- Enable RLS
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

-- Drop old policies if they exist
DROP POLICY IF EXISTS "company_settings_select" ON company_settings;
DROP POLICY IF EXISTS "company_settings_insert" ON company_settings;
DROP POLICY IF EXISTS "company_settings_update" ON company_settings;

-- Create RLS policies
CREATE POLICY "company_settings_select" 
  ON company_settings FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

CREATE POLICY "company_settings_insert" 
  ON company_settings FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

CREATE POLICY "company_settings_update" 
  ON company_settings FOR UPDATE 
  USING (tenant_id = public.user_tenant_id());

RAISE NOTICE '========================================';
RAISE NOTICE '✓ company_settings is now tenant-isolated';
RAISE NOTICE '========================================';
