-- Fix for stock_adjustments table missing updated_at column
-- This column is expected by Supabase/triggers

-- Add updated_at column if not exists
ALTER TABLE stock_adjustments 
ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();

-- Create trigger to auto-update updated_at on row update
CREATE OR REPLACE FUNCTION update_stock_adjustments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stock_adjustments_updated_at ON stock_adjustments;
CREATE TRIGGER trg_stock_adjustments_updated_at
  BEFORE UPDATE ON stock_adjustments
  FOR EACH ROW
  EXECUTE FUNCTION update_stock_adjustments_updated_at();
