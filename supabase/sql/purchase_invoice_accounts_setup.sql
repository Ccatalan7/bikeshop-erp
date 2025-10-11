-- =====================================================
-- Purchase Invoice: Required Chart of Accounts Setup
-- =====================================================
-- This script creates the minimum required accounts for
-- purchase invoice workflow to function properly.
-- Run this BEFORE purchase_invoice_workflow.sql if you
-- don't have these accounts already.
-- =====================================================

-- Create required accounts for purchase invoice workflow
-- These follow Chilean accounting standards (Plan de Cuentas Chileno)

-- 1105 - Inventario (Asset - Current)
INSERT INTO accounts (
  id,
  code,
  name,
  type,
  category,
  is_active,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '1105',
  'Inventario',
  'asset',
  'currentAsset',
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- 1107 - IVA Crédito Fiscal (Asset - Current)
INSERT INTO accounts (
  id,
  code,
  name,
  type,
  category,
  is_active,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '1107',
  'IVA Crédito Fiscal',
  'asset',
  'currentAsset',
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- 2101 - Proveedores / Cuentas por Pagar (Liability - Current)
INSERT INTO accounts (
  id,
  code,
  name,
  type,
  category,
  is_active,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '2101',
  'Proveedores',
  'liability',
  'currentLiability',
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Optional but recommended: 5101 - Costo de Ventas (as fallback for Inventory)
INSERT INTO accounts (
  id,
  code,
  name,
  type,
  category,
  is_active,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '5101',
  'Costo de Ventas',
  'expense',
  'costOfGoodsSold',
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  category = EXCLUDED.category,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Verify accounts were created
SELECT 
  code,
  name,
  type,
  category,
  is_active
FROM accounts
WHERE code IN ('1105', '1107', '2101', '5101')
ORDER BY code;

-- =====================================================
-- Expected Output:
-- =====================================================
-- code | name                  | type     | category            | is_active
-- -----|---------------------- |----------|---------------------|----------
-- 1105 | Inventario            | asset    | currentAsset        | true
-- 1107 | IVA Crédito Fiscal    | asset    | currentAsset        | true
-- 2101 | Proveedores           | liability| currentLiability    | true
-- 5101 | Costo de Ventas       | expense  | costOfGoodsSold     | true
-- =====================================================
