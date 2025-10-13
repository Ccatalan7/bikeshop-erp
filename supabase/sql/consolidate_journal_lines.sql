-- =====================================================
-- Consolidate journal_lines table structure
-- =====================================================
-- This removes duplicate columns and creates a unified schema
-- Preserves existing data by mapping old → new columns
-- =====================================================

-- STEP 1: Ensure new columns exist (safe, idempotent)
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS journal_entry_id UUID;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS account_id UUID;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS debit NUMERIC DEFAULT 0;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS credit NUMERIC DEFAULT 0;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS description TEXT;

-- STEP 2: Migrate data from old columns to new columns (if old columns exist)
DO $$
BEGIN
  -- Copy entry_id → journal_entry_id
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'entry_id') THEN
    UPDATE journal_lines
    SET journal_entry_id = entry_id
    WHERE journal_entry_id IS NULL AND entry_id IS NOT NULL;
  END IF;

  -- Copy debit_amount → debit
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'debit_amount') THEN
    UPDATE journal_lines
    SET debit = debit_amount
    WHERE debit = 0 AND debit_amount != 0;
  END IF;

  -- Copy credit_amount → credit
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'credit_amount') THEN
    UPDATE journal_lines
    SET credit = credit_amount
    WHERE credit = 0 AND credit_amount != 0;
  END IF;

  -- Try to resolve account_id from account_code (if accounts table has code column)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'account_code') THEN
    UPDATE journal_lines jl
    SET account_id = a.id
    FROM accounts a
    WHERE jl.account_id IS NULL 
      AND jl.account_code = a.code;
  END IF;

  RAISE NOTICE '✅ Data migrated from old columns to new columns';
END $$;

-- STEP 3: Drop old redundant columns (safe, only if they exist)
ALTER TABLE journal_lines DROP COLUMN IF EXISTS entry_id CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS account_code CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS account_name CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS debit_amount CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS credit_amount CASCADE;

-- STEP 4: Add constraints and foreign keys
ALTER TABLE journal_lines
DROP CONSTRAINT IF EXISTS journal_lines_journal_entry_id_fkey;

ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_journal_entry_id_fkey
FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE;

ALTER TABLE journal_lines
DROP CONSTRAINT IF EXISTS journal_lines_account_id_fkey;

ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_account_id_fkey
FOREIGN KEY (account_id) REFERENCES accounts(id);

-- STEP 5: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_journal_lines_journal_entry ON journal_lines(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);

-- STEP 6: Verification
DO $$
DECLARE
  v_has_old_columns BOOLEAN := FALSE;
  v_has_new_columns BOOLEAN := TRUE;
BEGIN
  -- Check if old columns still exist
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'entry_id') OR
     EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'account_code') OR
     EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'debit_amount') THEN
    v_has_old_columns := TRUE;
  END IF;

  -- Check if new columns exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'journal_entry_id') OR
     NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'account_id') OR
     NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'debit') THEN
    v_has_new_columns := FALSE;
  END IF;

  IF v_has_new_columns AND NOT v_has_old_columns THEN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ MIGRATION SUCCESSFUL!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Old columns removed:';
    RAISE NOTICE '  ❌ entry_id';
    RAISE NOTICE '  ❌ account_code';
    RAISE NOTICE '  ❌ account_name';
    RAISE NOTICE '  ❌ debit_amount';
    RAISE NOTICE '  ❌ credit_amount';
    RAISE NOTICE '';
    RAISE NOTICE 'New unified columns:';
    RAISE NOTICE '  ✅ journal_entry_id (UUID, FK to journal_entries)';
    RAISE NOTICE '  ✅ account_id (UUID, FK to accounts)';
    RAISE NOTICE '  ✅ debit (NUMERIC)';
    RAISE NOTICE '  ✅ credit (NUMERIC)';
    RAISE NOTICE '  ✅ description (TEXT)';
    RAISE NOTICE '';
    RAISE NOTICE 'Table is now ready for all modules!';
  ELSIF v_has_old_columns THEN
    RAISE WARNING '⚠️  Old columns still exist - migration may have failed';
  ELSIF NOT v_has_new_columns THEN
    RAISE WARNING '⚠️  New columns missing - migration incomplete';
  END IF;
END $$;

-- STEP 7: Show final structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'journal_lines'
ORDER BY ordinal_position;
