-- =====================================================
-- MASTER MIGRATION: Purchase Invoice Accounting Fix
-- =====================================================
-- Run this ONE file to fix all accounting table issues
-- This ensures a clean, unified schema across all modules
-- =====================================================

-- =====================================================
-- PART 1: Ensure Required Accounts Exist
-- =====================================================

INSERT INTO accounts (id, code, name, type, is_active, created_at, updated_at)
VALUES 
  (gen_random_uuid(), '1140', 'IVA Crédito Fiscal', 'asset', true, NOW(), NOW()),
  (gen_random_uuid(), '1150', 'Inventario', 'asset', true, NOW(), NOW()),
  (gen_random_uuid(), '1155', 'Inventario en Tránsito', 'asset', true, NOW(), NOW()),
  (gen_random_uuid(), '2120', 'Cuentas por Pagar', 'liability', true, NOW(), NOW())
ON CONFLICT (code) DO NOTHING;

DO $$
BEGIN
  RAISE NOTICE '✅ Verified required accounts exist';
END $$;

-- =====================================================
-- PART 2: Consolidate journal_entries Table
-- =====================================================

-- Add new columns if they don't exist
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS entry_type TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS source_module TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS source_reference TEXT;
ALTER TABLE journal_entries ADD COLUMN IF NOT EXISTS notes TEXT;

-- Migrate data from old columns to new
UPDATE journal_entries SET entry_type = 'manual' WHERE entry_type IS NULL;
UPDATE journal_entries SET source_module = 'manual' WHERE source_module IS NULL;

DO $$
BEGIN
  -- Copy reference → source_reference if reference column exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'reference') THEN
    UPDATE journal_entries
    SET source_reference = reference
    WHERE source_reference IS NULL AND reference IS NOT NULL;
  END IF;

  -- Copy description → notes if description column exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'description') THEN
    UPDATE journal_entries
    SET notes = description
    WHERE notes IS NULL AND description IS NOT NULL;
  END IF;

  -- Handle duplicate date columns (entry_date vs date)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'entry_date') AND
     EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'date') THEN
    UPDATE journal_entries SET entry_date = date::DATE WHERE entry_date IS NULL AND date IS NOT NULL;
    ALTER TABLE journal_entries DROP COLUMN date CASCADE;
  END IF;
END $$;

-- Add constraints
ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entries_entry_type_check;
ALTER TABLE journal_entries
ADD CONSTRAINT journal_entries_entry_type_check 
CHECK (entry_type IN ('manual', 'sale', 'purchase', 'purchase_invoice', 'purchase_confirmation', 'purchase_receipt', 'payment', 'adjustment', 'opening_balance', 'closing'));

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_type ON journal_entries(entry_type);
CREATE INDEX IF NOT EXISTS idx_journal_entries_source ON journal_entries(source_module, source_reference);
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_date ON journal_entries(entry_date);
CREATE INDEX IF NOT EXISTS idx_journal_entries_status ON journal_entries(status);

DO $$
BEGIN
  RAISE NOTICE '✅ Consolidated journal_entries table';
END $$;

-- =====================================================
-- PART 3: Consolidate journal_lines Table
-- =====================================================

-- Add new columns if they don't exist
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS journal_entry_id UUID;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS account_id UUID;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS debit NUMERIC DEFAULT 0;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS credit NUMERIC DEFAULT 0;
ALTER TABLE journal_lines ADD COLUMN IF NOT EXISTS description TEXT;

-- Migrate data from old columns to new
DO $$
BEGIN
  -- Copy entry_id → journal_entry_id
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'entry_id') THEN
    UPDATE journal_lines SET journal_entry_id = entry_id WHERE journal_entry_id IS NULL AND entry_id IS NOT NULL;
  END IF;

  -- Copy debit_amount → debit
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'debit_amount') THEN
    UPDATE journal_lines SET debit = debit_amount WHERE debit = 0 AND debit_amount != 0;
  END IF;

  -- Copy credit_amount → credit
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'credit_amount') THEN
    UPDATE journal_lines SET credit = credit_amount WHERE credit = 0 AND credit_amount != 0;
  END IF;

  -- Resolve account_id from account_code
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'account_code') THEN
    UPDATE journal_lines jl
    SET account_id = a.id
    FROM accounts a
    WHERE jl.account_id IS NULL AND jl.account_code = a.code;
  END IF;
END $$;

-- Drop old redundant columns
ALTER TABLE journal_lines DROP COLUMN IF EXISTS entry_id CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS account_code CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS account_name CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS debit_amount CASCADE;
ALTER TABLE journal_lines DROP COLUMN IF EXISTS credit_amount CASCADE;

-- Add foreign key constraints
ALTER TABLE journal_lines DROP CONSTRAINT IF EXISTS journal_lines_journal_entry_id_fkey;
ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_journal_entry_id_fkey
FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE;

ALTER TABLE journal_lines DROP CONSTRAINT IF EXISTS journal_lines_account_id_fkey;
ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_account_id_fkey
FOREIGN KEY (account_id) REFERENCES accounts(id);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_journal_lines_journal_entry ON journal_lines(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines(account_id);

DO $$
BEGIN
  RAISE NOTICE '✅ Consolidated journal_lines table';
END $$;

-- =====================================================
-- FINAL VERIFICATION
-- =====================================================

DO $$
DECLARE
  v_accounts_count INTEGER;
  v_je_ready BOOLEAN := TRUE;
  v_jl_ready BOOLEAN := TRUE;
BEGIN
  -- Check accounts
  SELECT COUNT(*) INTO v_accounts_count
  FROM accounts WHERE code IN ('1140', '1150', '1155', '2120');
  
  -- Check journal_entries columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'entry_type') OR
     NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'source_module') OR
     NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'notes') THEN
    v_je_ready := FALSE;
  END IF;
  
  -- Check journal_lines columns
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'journal_entry_id') OR
     NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'account_id') OR
     NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'debit') THEN
    v_jl_ready := FALSE;
  END IF;
  
  -- Check for old columns still existing (should be gone)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'entry_id') OR
     EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_lines' AND column_name = 'debit_amount') THEN
    v_jl_ready := FALSE;
    RAISE WARNING '⚠️  Old journal_lines columns still exist!';
  END IF;
  
  IF v_accounts_count = 4 AND v_je_ready AND v_jl_ready THEN
    RAISE NOTICE '================================================';
    RAISE NOTICE '✅ ✅ ✅  MIGRATION COMPLETE!  ✅ ✅ ✅';
    RAISE NOTICE '================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Accounts verified: % of 4 required', v_accounts_count;
    RAISE NOTICE 'journal_entries: READY ✅';
    RAISE NOTICE 'journal_lines: READY ✅';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 You can now use the Purchase Invoice workflow!';
    RAISE NOTICE '';
    RAISE NOTICE 'Try: Confirmar Factura on FC-20251012-796918';
  ELSE
    RAISE WARNING '⚠️  Migration incomplete:';
    IF v_accounts_count < 4 THEN RAISE WARNING '  - Only % of 4 required accounts found', v_accounts_count; END IF;
    IF NOT v_je_ready THEN RAISE WARNING '  - journal_entries table missing columns'; END IF;
    IF NOT v_jl_ready THEN RAISE WARNING '  - journal_lines table not ready'; END IF;
  END IF;
END $$;
