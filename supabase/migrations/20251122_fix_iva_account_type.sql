-- Fix: IVA accounts should be proper balance sheet accounts
-- IVA Débito (2150) = LIABILITY (tax we owe to government)
-- IVA Crédito (2120) = ASSET (tax refund we're owed)

-- Update IVA Débito Fiscal to be a liability
UPDATE accounts
SET type = 'liability',
    category = 'currentLiability'
WHERE code = '2150'
  AND type = 'tax';

-- Update IVA Crédito Fiscal to be an asset  
UPDATE accounts
SET type = 'asset',
    category = 'currentAsset'
WHERE code = '2120'
  AND type = 'tax';

-- Also catch any other tax accounts by category
UPDATE accounts
SET type = 'liability',
    category = 'currentLiability'
WHERE category = 'taxPayable'
  AND type = 'tax';

UPDATE accounts
SET type = 'asset',
    category = 'currentAsset'
WHERE category = 'taxReceivable'
  AND type = 'tax';

-- Report what was updated
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM accounts WHERE code IN ('2150', '2120');
  RAISE NOTICE 'Updated % IVA accounts to proper balance sheet types', v_count;
END $$;
