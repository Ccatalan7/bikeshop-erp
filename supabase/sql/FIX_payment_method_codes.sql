-- ============================================================================
-- FIX: Update existing payment method codes to lowercase
-- ============================================================================
-- This fixes existing tenants that have UPPERCASE codes (CASH, CARD, etc.)
-- Changes them to lowercase (cash, card, etc.) to match Flutter expectations
-- ============================================================================

UPDATE payment_methods 
SET code = 'cash' 
WHERE code = 'CASH';

UPDATE payment_methods 
SET code = 'card' 
WHERE code = 'CARD';

UPDATE payment_methods 
SET code = 'check' 
WHERE code = 'CHECK';

UPDATE payment_methods 
SET code = 'transfer' 
WHERE code = 'TRANSFER';

-- Verify the changes
SELECT 
  tenant_id,
  code,
  name,
  updated_at
FROM payment_methods
ORDER BY tenant_id, sort_order;

-- Expected result: All codes should be lowercase (cash, card, check, transfer)
