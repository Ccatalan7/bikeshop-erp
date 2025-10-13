-- =====================================================
-- Verify and Fix journal_lines table structure
-- =====================================================
-- Ensures all required columns exist for purchase workflow
-- =====================================================

-- Check current structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'journal_lines'
ORDER BY ordinal_position;

-- Add missing columns
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS journal_entry_id UUID;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS account_id UUID;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS debit NUMERIC DEFAULT 0;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS credit NUMERIC DEFAULT 0;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS description TEXT;

-- Add foreign key constraint to journal_entries
ALTER TABLE journal_lines
DROP CONSTRAINT IF EXISTS journal_lines_journal_entry_id_fkey;

ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_journal_entry_id_fkey
FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE;

-- Add foreign key constraint to accounts
ALTER TABLE journal_lines
DROP CONSTRAINT IF EXISTS journal_lines_account_id_fkey;

ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_account_id_fkey
FOREIGN KEY (account_id) REFERENCES accounts(id);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_journal_lines_journal_entry ON journal_lines(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);

-- Verification
DO $$
DECLARE
  v_has_journal_entry_id BOOLEAN;
  v_has_account_id BOOLEAN;
  v_has_debit BOOLEAN;
  v_has_credit BOOLEAN;
  v_has_description BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_lines' AND column_name = 'journal_entry_id'
  ) INTO v_has_journal_entry_id;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_lines' AND column_name = 'account_id'
  ) INTO v_has_account_id;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_lines' AND column_name = 'debit'
  ) INTO v_has_debit;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_lines' AND column_name = 'credit'
  ) INTO v_has_credit;
  
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'journal_lines' AND column_name = 'description'
  ) INTO v_has_description;
  
  IF v_has_journal_entry_id AND v_has_account_id AND v_has_debit AND v_has_credit AND v_has_description THEN
    RAISE NOTICE '✅ All required columns exist!';
    RAISE NOTICE '';
    RAISE NOTICE 'journal_lines table is ready for purchase invoice workflow';
  ELSE
    RAISE WARNING '⚠️  Missing columns:';
    IF NOT v_has_journal_entry_id THEN RAISE WARNING '  - journal_entry_id'; END IF;
    IF NOT v_has_account_id THEN RAISE WARNING '  - account_id'; END IF;
    IF NOT v_has_debit THEN RAISE WARNING '  - debit'; END IF;
    IF NOT v_has_credit THEN RAISE WARNING '  - credit'; END IF;
    IF NOT v_has_description THEN RAISE WARNING '  - description'; END IF;
  END IF;
END $$;

-- Final structure check
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'journal_lines'
ORDER BY ordinal_position;
