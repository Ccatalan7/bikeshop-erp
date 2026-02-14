-- =============================================
-- Deploy Bug Reports table + Storage bucket
-- For the Debug module (internal bug tracking)
-- =============================================

-- 1. Create bug_reports table
CREATE TABLE IF NOT EXISTS bug_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'bug' CHECK (type IN ('bug', 'suggestion')),
  description TEXT,
  module TEXT,              -- e.g. "Taller → Trabajos"
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved')),
  image_urls TEXT[] DEFAULT '{}',
  reported_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reported_by_name TEXT,    -- cached display name for quick listing
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_bug_reports_tenant ON bug_reports(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bug_reports_status ON bug_reports(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_bug_reports_module ON bug_reports(tenant_id, module);

-- 3. RLS policies (same pattern as other tenant tables)
ALTER TABLE bug_reports ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read bugs from their tenant
CREATE POLICY "bug_reports_select" ON bug_reports
  FOR SELECT TO authenticated
  USING (
    tenant_id IN (
      SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid()
    )
  );

-- Allow authenticated users to insert bugs for their tenant
CREATE POLICY "bug_reports_insert" ON bug_reports
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id IN (
      SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid()
    )
  );

-- Allow authenticated users to update bugs from their tenant
CREATE POLICY "bug_reports_update" ON bug_reports
  FOR UPDATE TO authenticated
  USING (
    tenant_id IN (
      SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid()
    )
  );

-- Allow authenticated users to delete bugs from their tenant
CREATE POLICY "bug_reports_delete" ON bug_reports
  FOR DELETE TO authenticated
  USING (
    tenant_id IN (
      SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid()
    )
  );

-- 4. Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_bug_reports_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bug_reports_updated_at ON bug_reports;
CREATE TRIGGER trg_bug_reports_updated_at
  BEFORE UPDATE ON bug_reports
  FOR EACH ROW
  EXECUTE FUNCTION update_bug_reports_updated_at();

-- 5. Storage bucket for bug screenshots
INSERT INTO storage.buckets (id, name, public)
VALUES ('bug-screenshots', 'bug-screenshots', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies: authenticated users can upload/read/delete
CREATE POLICY "bug_screenshots_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'bug-screenshots');

CREATE POLICY "bug_screenshots_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'bug-screenshots');

CREATE POLICY "bug_screenshots_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'bug-screenshots');

-- Public read access for displaying images
CREATE POLICY "bug_screenshots_public_read" ON storage.objects
  FOR SELECT TO anon
  USING (bucket_id = 'bug-screenshots');
