-- =====================================================
-- Create Account 1155: Inventario en Tránsito
-- =====================================================
-- Required for prepayment purchase invoice workflow
-- This account holds inventory that has been paid for
-- but not yet physically received
-- =====================================================

INSERT INTO accounts (
  id,
  code,
  name,
  type,
  parent_id,
  is_active,
  created_at,
  updated_at
)
VALUES (
  gen_random_uuid(),
  '1155',
  'Inventario en Tránsito',
  'asset',
  (SELECT id FROM accounts WHERE code = '1000' LIMIT 1), -- Parent: Activos
  true,
  NOW(),
  NOW()
)
ON CONFLICT (code) DO UPDATE
SET 
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  is_active = EXCLUDED.is_active,
  updated_at = NOW();

-- Verify the account was created
SELECT 
  id,
  code,
  name,
  type,
  is_active
FROM accounts
WHERE code = '1155';

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Account 1155 created successfully!';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Account Details:';
  RAISE NOTICE '   Code: 1155';
  RAISE NOTICE '   Name: Inventario en Tránsito';
  RAISE NOTICE '   Type: Asset (Activo)';
  RAISE NOTICE '   Purpose: Prepaid inventory (paid but not received)';
  RAISE NOTICE '';
  RAISE NOTICE '🔄 Used in workflow:';
  RAISE NOTICE '   Borrador → Enviada → Confirmada → PAGADA → Recibida';
  RAISE NOTICE '';
  RAISE NOTICE '💡 Journal entries:';
  RAISE NOTICE '   On CONFIRM: DR 1155 Inventario en Tránsito';
  RAISE NOTICE '   On RECEIVE: DR 1150 Inventario, CR 1155 Inventario en Tránsito';
END $$;
