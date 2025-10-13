-- =====================================================
-- CREATE ALL REQUIRED ACCOUNTS FOR PURCHASE INVOICES
-- =====================================================
-- This creates the 4 accounts needed for the workflow
-- Safe to run multiple times (uses ON CONFLICT)
-- =====================================================

-- Step 1: Create the 4 required accounts
INSERT INTO accounts (id, code, name, type, is_active, created_at, updated_at)
VALUES 
  -- Asset Accounts
  (gen_random_uuid(), '1140', 'IVA Crédito Fiscal', 'asset', true, NOW(), NOW()),
  (gen_random_uuid(), '1150', 'Inventario', 'asset', true, NOW(), NOW()),
  (gen_random_uuid(), '1155', 'Inventario en Tránsito', 'asset', true, NOW(), NOW()),
  -- Liability Account
  (gen_random_uuid(), '2120', 'Cuentas por Pagar', 'liability', true, NOW(), NOW())
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  is_active = true,
  updated_at = NOW();

-- Step 2: Verify they were created
SELECT 
  code,
  name,
  type,
  is_active
FROM accounts
WHERE code IN ('1140', '1150', '1155', '2120')
ORDER BY code;

-- Step 3: Confirmation
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM accounts
  WHERE code IN ('1140', '1150', '1155', '2120')
    AND is_active = true;
  
  IF v_count = 4 THEN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ✅ ✅  SUCCESS!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'All 4 required accounts created:';
    RAISE NOTICE '  ✅ 1140 - IVA Crédito Fiscal';
    RAISE NOTICE '  ✅ 1150 - Inventario';
    RAISE NOTICE '  ✅ 1155 - Inventario en Tránsito';
    RAISE NOTICE '  ✅ 2120 - Cuentas por Pagar';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 You can now confirm purchase invoices!';
    RAISE NOTICE '';
    RAISE NOTICE 'Try again in the app:';
    RAISE NOTICE '  1. Go to the invoice';
    RAISE NOTICE '  2. Click "Confirmar Factura"';
    RAISE NOTICE '  3. Should work now! ✅';
  ELSE
    RAISE WARNING '⚠️  Only % of 4 accounts were created/found', v_count;
    RAISE WARNING 'Please check the accounts table manually';
  END IF;
END $$;
