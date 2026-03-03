-- ============================================================
-- Native Spreadsheets Module
-- ============================================================

-- 1. Spreadsheets metadata table
CREATE TABLE IF NOT EXISTS public.spreadsheets (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id UUID NOT NULL DEFAULT public.user_tenant_id(),
  name TEXT NOT NULL DEFAULT 'Planilla sin título',
  row_count INTEGER NOT NULL DEFAULT 100,
  col_count INTEGER NOT NULL DEFAULT 26,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Cell data table (one row per cell that has content)
CREATE TABLE IF NOT EXISTS public.spreadsheet_cells (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  spreadsheet_id UUID NOT NULL REFERENCES public.spreadsheets(id) ON DELETE CASCADE,
  row_index INTEGER NOT NULL,
  col_index INTEGER NOT NULL,
  raw_value TEXT, -- what the user typed (e.g. "=SUM(A1:A5)" or "Hello")
  display_value TEXT, -- computed/displayed value
  cell_type TEXT NOT NULL DEFAULT 'text', -- text, number, formula
  bold BOOLEAN NOT NULL DEFAULT false,
  italic BOOLEAN NOT NULL DEFAULT false,
  text_align TEXT NOT NULL DEFAULT 'left', -- left, center, right
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(spreadsheet_id, row_index, col_index)
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_spreadsheets_tenant
  ON public.spreadsheets(tenant_id);
CREATE INDEX IF NOT EXISTS idx_cells_spreadsheet
  ON public.spreadsheet_cells(spreadsheet_id);
CREATE INDEX IF NOT EXISTS idx_cells_position
  ON public.spreadsheet_cells(spreadsheet_id, row_index, col_index);

-- 4. Updated_at triggers
CREATE TRIGGER set_spreadsheets_updated_at
  BEFORE UPDATE ON public.spreadsheets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_cells_updated_at
  BEFORE UPDATE ON public.spreadsheet_cells
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 5. RLS
ALTER TABLE public.spreadsheets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spreadsheet_cells ENABLE ROW LEVEL SECURITY;

-- Spreadsheets: tenant-scoped
CREATE POLICY "Tenant users can view spreadsheets"
  ON public.spreadsheets FOR SELECT
  USING (tenant_id = public.user_tenant_id());

CREATE POLICY "Tenant users can create spreadsheets"
  ON public.spreadsheets FOR INSERT
  WITH CHECK (tenant_id = public.user_tenant_id());

CREATE POLICY "Tenant users can update spreadsheets"
  ON public.spreadsheets FOR UPDATE
  USING (tenant_id = public.user_tenant_id());

CREATE POLICY "Tenant users can delete spreadsheets"
  ON public.spreadsheets FOR DELETE
  USING (tenant_id = public.user_tenant_id());

-- Cells: access through parent spreadsheet's tenant
CREATE POLICY "Tenant users can view cells"
  ON public.spreadsheet_cells FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.spreadsheets s
      WHERE s.id = spreadsheet_id AND s.tenant_id = public.user_tenant_id()
    )
  );

CREATE POLICY "Tenant users can insert cells"
  ON public.spreadsheet_cells FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.spreadsheets s
      WHERE s.id = spreadsheet_id AND s.tenant_id = public.user_tenant_id()
    )
  );

CREATE POLICY "Tenant users can update cells"
  ON public.spreadsheet_cells FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.spreadsheets s
      WHERE s.id = spreadsheet_id AND s.tenant_id = public.user_tenant_id()
    )
  );

CREATE POLICY "Tenant users can delete cells"
  ON public.spreadsheet_cells FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.spreadsheets s
      WHERE s.id = spreadsheet_id AND s.tenant_id = public.user_tenant_id()
    )
  );
