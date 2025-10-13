-- =====================================================
-- Verify Required Accounts for Purchase Invoice Workflow
-- =====================================================
-- This script checks if all required accounts exist
-- and creates them if they don't
-- =====================================================

-- Check what accounts currently exist
SELECT code, name, type 
FROM accounts 
WHERE code IN ('1140', '1150', '1155', '2120')
ORDER BY code;

-- Create missing accounts
-- 1140 - IVA Crédito Fiscal
INSERT INTO accounts (id, code, name, type, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '1140', 'IVA Crédito Fiscal', 'asset', true, NOW(), NOW())
ON CONFLICT (code) DO NOTHING;

-- 1150 - Inventario
INSERT INTO accounts (id, code, name, type, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '1150', 'Inventario', 'asset', true, NOW(), NOW())
ON CONFLICT (code) DO NOTHING;

-- 1155 - Inventario en Tránsito (for prepayment model)
INSERT INTO accounts (id, code, name, type, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '1155', 'Inventario en Tránsito', 'asset', true, NOW(), NOW())
ON CONFLICT (code) DO NOTHING;

-- 2120 - Cuentas por Pagar
INSERT INTO accounts (id, code, name, type, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '2120', 'Cuentas por Pagar', 'liability', true, NOW(), NOW())
ON CONFLICT (code) DO NOTHING;

-- Verify all accounts now exist
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM accounts
  WHERE code IN ('1140', '1150', '1155', '2120');
  
  IF v_count = 4 THEN
    RAISE NOTICE '✅ All required accounts exist!';
    RAISE NOTICE '';
    RAISE NOTICE 'Accounts found:';
    RAISE NOTICE '  1140 - IVA Crédito Fiscal';
    RAISE NOTICE '  1150 - Inventario';
    RAISE NOTICE '  1155 - Inventario en Tránsito';
    RAISE NOTICE '  2120 - Cuentas por Pagar';
  ELSE
    RAISE WARNING '⚠️  Only % of 4 required accounts found', v_count;
  END IF;
END $$;

-- Final verification
SELECT code, name, type, is_active 
FROM accounts 
WHERE code IN ('1140', '1150', '1155', '2120')
ORDER BY code;
