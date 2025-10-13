-- =====================================================
-- Add entry_type column to journal_entries table
-- =====================================================
-- Required for purchase invoice workflow
-- =====================================================

-- Add entry_type column if it doesn't exist
ALTER TABLE journal_entries 
ADD COLUMN IF NOT EXISTS entry_type TEXT;

-- Add check constraint for valid entry types
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

-- Create index for faster filtering
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_type 
ON journal_entries(entry_type);

-- Update existing entries to have a type
UPDATE journal_entries
SET entry_type = 'manual'
WHERE entry_type IS NULL;

-- Verify the column exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_name = 'journal_entries' 
    AND column_name = 'entry_type'
  ) THEN
    RAISE NOTICE '✅ Column entry_type added successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Valid entry types:';
    RAISE NOTICE '  - manual';
    RAISE NOTICE '  - sale';
    RAISE NOTICE '  - purchase';
    RAISE NOTICE '  - purchase_invoice';
    RAISE NOTICE '  - purchase_confirmation';
    RAISE NOTICE '  - purchase_receipt';
    RAISE NOTICE '  - payment';
    RAISE NOTICE '  - adjustment';
    RAISE NOTICE '  - opening_balance';
    RAISE NOTICE '  - closing';
  ELSE
    RAISE WARNING '⚠️  Column entry_type was not created';
  END IF;
END $$;

-- Show current structure
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'journal_entries'
ORDER BY ordinal_position;
