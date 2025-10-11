-- =====================================================
-- Fix Accounts Type and Category Issue
-- =====================================================
-- This fixes accounts that were created with invalid type/category
-- "revenue" should be "income"
-- "operatingRevenue" should be "operatingIncome"
-- =====================================================

-- Update any accounts with wrong type or category
UPDATE public.accounts
SET type = 'income',
    category = 'operatingIncome',
    updated_at = NOW()
WHERE code = '4100'
  AND (type = 'revenue' OR category = 'operatingRevenue');

-- Verify the fix
DO $$
DECLARE
  v_fixed INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_fixed
  FROM public.accounts
  WHERE code = '4100' 
    AND type = 'income' 
    AND category = 'operatingIncome';
  
  IF v_fixed > 0 THEN
    RAISE NOTICE '✅ Fixed revenue account: type="income", category="operatingIncome"';
  ELSE
    RAISE NOTICE 'ℹ️  No accounts needed fixing';
  END IF;
END $$;
