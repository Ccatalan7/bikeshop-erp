-- =====================================================
-- Verify and Fix journal_entries table structure
-- =====================================================
-- This ensures all required columns exist
-- =====================================================

-- Check current structure
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'journal_entries'
ORDER BY ordinal_position;

-- Add missing columns one by one
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS entry_type TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS source_module TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS source_reference TEXT;

-- Add constraints
ALTER TABLE journal_entries
DROP CONSTRAINT IF EXISTS journal_entries_entry_type_check;

ALTER TABLE journal_entries
ADD CONSTRAINT journal_entries_entry_type_check 
CHECK (entry_type IN (
  'manual',
  'sale',
  'purchase',
  'purchase_invoice',
  'purchase_confirmation',
  'purchase_receipt',
  'payment',
  'adjustment',
  'opening_balance',
  'closing'
));

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_type ON journal_entries(entry_type);
CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_module, source_reference);
CREATE INDEX IF NOT EXISTS idx_journal_entries_date ON journal_entries(entry_date);

-- Update existing entries
UPDATE journal_entries
SET 
  entry_type = COALESCE(entry_type, 'manual'),
  source_module = COALESCE(source_module, 'manual'),
  source_reference = COALESCE(source_reference, id::TEXT)
WHERE entry_type IS NULL OR source_module IS NULL;

-- Verification
DO $$
DECLARE
  v_has_entry_type BOOLEAN;
  v_has_source_module BOOLEAN;
  v_has_source_reference BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_entries' AND column_name = 'entry_type'
  ) INTO v_has_entry_type;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_entries' AND column_name = 'source_module'
  ) INTO v_has_source_module;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_entries' AND column_name = 'source_reference'
  ) INTO v_has_source_reference;
  
  IF v_has_entry_type AND v_has_source_module AND v_has_source_reference THEN
    RAISE NOTICE '✅ All required columns exist!';
    RAISE NOTICE '';
    RAISE NOTICE 'journal_entries table is ready for purchase invoice workflow';
  ELSE
    RAISE WARNING '⚠️  Missing columns:';
    IF NOT v_has_entry_type THEN RAISE WARNING '  - entry_type'; END IF;
    IF NOT v_has_source_module THEN RAISE WARNING '  - source_module'; END IF;
    IF NOT v_has_source_reference THEN RAISE WARNING '  - source_reference'; END IF;
  END IF;
END $$;

-- Final structure check
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'journal_entries'
ORDER BY ordinal_position;
