-- =====================================================
-- Consolidate journal_entries table structure
-- =====================================================
-- This removes duplicate columns and creates a unified schema
-- Preserves existing data by mapping old → new columns
-- =====================================================

-- STEP 1: Ensure new columns exist (safe, idempotent)
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS entry_type TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS source_module TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS source_reference TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS notes TEXT;

-- STEP 2: Migrate data from old columns to new columns (if duplicates exist)
DO $$
BEGIN
  -- If there are any old/duplicate columns, migrate them here
  -- For journal_entries, we mainly need to ensure consistency
  
  -- Set default entry_type for existing manual entries
  UPDATE journal_entries
  SET entry_type = 'manual'
  WHERE entry_type IS NULL;
  
  -- Set default source_module
  UPDATE journal_entries
  SET source_module = 'manual'
  WHERE source_module IS NULL;

  -- Copy reference → source_reference (if reference was used for this)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'reference') THEN
    UPDATE journal_entries
    SET source_reference = reference
    WHERE source_reference IS NULL AND reference IS NOT NULL;
  END IF;

  -- Copy description → notes (if description was used)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'description') THEN
    UPDATE journal_entries
    SET notes = description
    WHERE notes IS NULL AND description IS NOT NULL;
  END IF;

  RAISE NOTICE '✅ Data migrated from old columns to new columns';
END $$;

-- STEP 3: Handle duplicate date columns
DO $$
BEGIN
  -- If both 'entry_date' (DATE) and 'date' (TIMESTAMP) exist, consolidate
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'entry_date') AND
     EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'date') THEN
    
    -- Copy date → entry_date if entry_date is null
    UPDATE journal_entries
    SET entry_date = date::DATE
    WHERE entry_date IS NULL AND date IS NOT NULL;
    
    -- Drop the duplicate 'date' column
    ALTER TABLE journal_entries DROP COLUMN date CASCADE;
    
    RAISE NOTICE '✅ Consolidated date columns: removed duplicate "date" column';
  END IF;
END $$;

-- STEP 4: Drop old redundant columns (safe, only if they exist)
-- Note: We keep 'reference' and 'description' as they might be needed for backward compatibility
-- Only drop if we're 100% sure they're duplicates

-- STEP 5: Add constraints
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

-- STEP 6: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_type ON journal_entries(entry_type);
CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_module, source_reference);
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_date ON journal_entries(entry_date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_status ON journal_entries(status);

-- STEP 7: Verification
DO $$
DECLARE
  v_has_entry_type BOOLEAN;
  v_has_source_module BOOLEAN;
  v_has_source_reference BOOLEAN;
  v_has_notes BOOLEAN;
  v_has_duplicate_date BOOLEAN := FALSE;
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
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_entries' AND column_name = 'notes'
  ) INTO v_has_notes;

  -- Check for duplicate date columns
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'date') THEN
    v_has_duplicate_date := TRUE;
  END IF;
  
  IF v_has_entry_type AND v_has_source_module AND v_has_source_reference AND v_has_notes AND NOT v_has_duplicate_date THEN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ MIGRATION SUCCESSFUL!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Unified columns:';
    RAISE NOTICE '  ✅ entry_type (with constraint)';
    RAISE NOTICE '  ✅ source_module';
    RAISE NOTICE '  ✅ source_reference';
    RAISE NOTICE '  ✅ notes';
    RAISE NOTICE '  ✅ entry_date (DATE)';
    RAISE NOTICE '';
    RAISE NOTICE 'Table is now ready for all modules!';
  ELSE
    IF NOT v_has_entry_type THEN RAISE WARNING '  ⚠️  Missing: entry_type'; END IF;
    IF NOT v_has_source_module THEN RAISE WARNING '  ⚠️  Missing: source_module'; END IF;
    IF NOT v_has_source_reference THEN RAISE WARNING '  ⚠️  Missing: source_reference'; END IF;
    IF NOT v_has_notes THEN RAISE WARNING '  ⚠️  Missing: notes'; END IF;
    IF v_has_duplicate_date THEN RAISE WARNING '  ⚠️  Duplicate: both entry_date and date columns exist'; END IF;
  END IF;
END $$;

-- STEP 8: Show final structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'journal_entries'
ORDER BY ordinal_position;
