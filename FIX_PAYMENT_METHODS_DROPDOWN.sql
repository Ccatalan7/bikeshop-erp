-- ============================================================================
-- FIX: Payment Methods Dropdown Not Working
-- ============================================================================
-- PROBLEM: The payment method dropdown in "Registrar Pago" is empty/non-functional
-- CAUSE: No payment methods have been seeded for your tenant
-- SOLUTION: Run this script to seed default payment methods
--
-- This script will:
-- 1. Check if you have any payment methods
-- 2. Create default payment methods (Efectivo, Transferencia, Cheque, Tarjeta)
-- 3. Link them to proper accounting accounts (Caja and Banco)
--
-- ============================================================================

-- Step 1: Check current payment methods
SELECT 
  'Current payment methods for your tenant:' as info,
  COUNT(*) as payment_method_count
FROM payment_methods
WHERE tenant_id = public.user_tenant_id();

-- If count = 0, you need to seed payment methods

-- Step 2: Seed payment methods for your tenant
SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());

-- Step 3: Verify payment methods were created
SELECT 
  'Payment methods after seeding:' as info,
  code,
  name,
  requires_reference,
  is_active,
  sort_order
FROM payment_methods
WHERE tenant_id = public.user_tenant_id()
ORDER BY sort_order;

-- Step 4: Verify account links
SELECT 
  'Payment methods with their linked accounts:' as info,
  pm.code as payment_code,
  pm.name as payment_name,
  a.code as account_code,
  a.name as account_name
FROM payment_methods pm
JOIN accounts a ON pm.account_id = a.id
WHERE pm.tenant_id = public.user_tenant_id()
ORDER BY pm.sort_order;

-- ============================================================================
-- EXPECTED RESULT:
-- ============================================================================
-- You should see 4 payment methods:
-- 1. CASH - Efectivo → 1101 Caja
-- 2. TRANSFER - Transferencia → 1110 Banco
-- 3. CHECK - Cheque → 1110 Banco
-- 4. CARD - Tarjeta de Crédito/Débito → 1110 Banco
--
-- After running this, refresh your app and the dropdown should work!
-- ============================================================================
