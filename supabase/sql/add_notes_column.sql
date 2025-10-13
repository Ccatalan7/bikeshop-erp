-- Add notes column to journal_entries table
-- This is used by purchase invoice triggers to store descriptions

ALTER TABLE journal_entries 
ADD COLUMN IF NOT EXISTS notes TEXT;

-- Verification
DO $$
DECLARE
  v_has_notes BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_entries' AND column_name = 'notes'
  ) INTO v_has_notes;
  
  IF v_has_notes THEN
    RAISE NOTICE '✅ notes column added successfully!';
  ELSE
    RAISE WARNING '⚠️  Failed to add notes column';
  END IF;
END $$;
