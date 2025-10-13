-- =====================================================
-- Purchase Invoice 5-Status Migration
-- =====================================================
-- This migration adds support for the 5-status workflow
-- and prepayment/standard model selection.
--
-- New statuses: draft → sent → confirmed → received → paid
-- Payment models: Standard (pay after receipt) vs Prepayment (pay before receipt)
-- =====================================================

-- =====================================================
-- Step 1: Add new columns to purchase_invoices table
-- =====================================================

-- Add prepayment model flag
ALTER TABLE purchase_invoices
ADD COLUMN IF NOT EXISTS prepayment_model BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN purchase_invoices.prepayment_model IS
  'TRUE = Prepayment model (pay before receipt), FALSE = Standard model (pay after receipt)';

-- Add status transition date columns
ALTER TABLE purchase_invoices
ADD COLUMN IF NOT EXISTS sent_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS confirmed_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS received_date TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS paid_date TIMESTAMP WITH TIME ZONE;

-- Add supplier invoice tracking fields
ALTER TABLE purchase_invoices
ADD COLUMN IF NOT EXISTS supplier_invoice_number TEXT,
ADD COLUMN IF NOT EXISTS supplier_invoice_date TIMESTAMP WITH TIME ZONE;

-- Add paid amount and balance tracking
ALTER TABLE purchase_invoices
ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS balance NUMERIC(12,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN purchase_invoices.sent_date IS 'Date when order was sent to supplier';
COMMENT ON COLUMN purchase_invoices.confirmed_date IS 'Date when supplier confirmed and issued invoice';
COMMENT ON COLUMN purchase_invoices.received_date IS 'Date when goods were physically received';
COMMENT ON COLUMN purchase_invoices.paid_date IS 'Date when invoice was paid';
COMMENT ON COLUMN purchase_invoices.supplier_invoice_number IS 'Supplier''s invoice number (their reference)';
COMMENT ON COLUMN purchase_invoices.supplier_invoice_date IS 'Date on supplier''s invoice';
COMMENT ON COLUMN purchase_invoices.paid_amount IS 'Total amount paid (sum of all payments)';
COMMENT ON COLUMN purchase_invoices.balance IS 'Remaining balance (total - paid_amount)';

-- =====================================================
-- Step 2: Update status constraint to include new statuses
-- =====================================================

-- Drop existing constraint
ALTER TABLE purchase_invoices
DROP CONSTRAINT IF EXISTS purchase_invoices_status_check;

-- Add new constraint with 5 statuses
ALTER TABLE purchase_invoices
ADD CONSTRAINT purchase_invoices_status_check
  CHECK (status IN ('draft', 'sent', 'confirmed', 'received', 'paid', 'cancelled'));

COMMENT ON CONSTRAINT purchase_invoices_status_check ON purchase_invoices IS
  'Status flow: draft → sent → confirmed → received → paid (standard) OR draft → sent → confirmed → paid → received (prepayment)';

-- =====================================================
-- Step 3: Create indexes for performance
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_status
  ON purchase_invoices(status);

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_prepayment_model
  ON purchase_invoices(prepayment_model);

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_supplier_id
  ON purchase_invoices(supplier_id);

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_date
  ON purchase_invoices(date DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_confirmed_date
  ON purchase_invoices(confirmed_date DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_paid_date
  ON purchase_invoices(paid_date DESC NULLS LAST);

-- =====================================================
-- Step 4: Migrate existing data
-- =====================================================

-- Set balance = total - paid_amount for existing records
UPDATE purchase_invoices
SET 
  balance = total - COALESCE(paid_amount, 0),
  prepayment_model = FALSE  -- Existing invoices use standard model
WHERE balance IS NULL OR balance = 0;

-- Set received_date for existing 'received' status invoices
UPDATE purchase_invoices
SET received_date = updated_at
WHERE status = 'received' AND received_date IS NULL;

-- Set paid_date for existing 'paid' status invoices
UPDATE purchase_invoices
SET paid_date = updated_at
WHERE status = 'paid' AND paid_date IS NULL;

-- =====================================================
-- Step 5: Create helper function to update balance
-- =====================================================

CREATE OR REPLACE FUNCTION update_purchase_invoice_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Automatically update balance when total or paid_amount changes
  NEW.balance := NEW.total - COALESCE(NEW.paid_amount, 0);
  RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS trg_update_purchase_invoice_balance ON purchase_invoices;

CREATE TRIGGER trg_update_purchase_invoice_balance
  BEFORE INSERT OR UPDATE OF total, paid_amount
  ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION update_purchase_invoice_balance();

-- =====================================================
-- Step 6: Verification queries
-- =====================================================

-- Check column additions
SELECT 
  column_name, 
  data_type, 
  is_nullable, 
  column_default
FROM information_schema.columns
WHERE table_name = 'purchase_invoices'
  AND column_name IN (
    'prepayment_model', 'sent_date', 'confirmed_date', 'received_date', 'paid_date',
    'supplier_invoice_number', 'supplier_invoice_date', 'paid_amount', 'balance'
  )
ORDER BY column_name;

-- Check status constraint
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'purchase_invoices'::regclass
  AND conname = 'purchase_invoices_status_check';

-- Check indexes
SELECT 
  indexname, 
  indexdef
FROM pg_indexes
WHERE tablename = 'purchase_invoices'
  AND indexname LIKE 'idx_purchase_invoices%'
ORDER BY indexname;

-- =====================================================
-- Migration Summary
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Purchase Invoice 5-Status Migration Complete!';
  RAISE NOTICE '   - Added prepayment_model column';
  RAISE NOTICE '   - Added status date columns (sent, confirmed, received, paid)';
  RAISE NOTICE '   - Added supplier invoice tracking';
  RAISE NOTICE '   - Added payment tracking (paid_amount, balance)';
  RAISE NOTICE '   - Updated status constraint (5 statuses)';
  RAISE NOTICE '   - Created performance indexes';
  RAISE NOTICE '   - Migrated existing data';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Next Steps:';
  RAISE NOTICE '   1. Run purchase_invoice_triggers.sql to create workflow triggers';
  RAISE NOTICE '   2. Update frontend code to use new fields';
  RAISE NOTICE '   3. Test both payment models end-to-end';
END $$;
