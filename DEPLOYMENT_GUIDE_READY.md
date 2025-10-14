# 🚀 DEPLOYMENT GUIDE - Purchase Invoice System

## 📋 Pre-Deployment Checklist

**Date**: 2025-10-13  
**Status**: ✅ **READY TO DEPLOY**  

### ✅ All Critical Bugs Fixed

1. ✅ **Inventory Bug** - Fixed (only at 'received' status)
2. ✅ **Journal Bug** - Fixed (created once, not recreated on status changes)
3. ✅ **Payment Recalc Bug** - Fixed (respects both prepayment models)
4. ✅ **Infinite Recursion Bug** - Fixed (guard prevents trigger loop)
5. ✅ **Flutter Integration** - Verified (clean delegation to SQL triggers)
6. ✅ **Syntax Errors** - Fixed (purchase_payment_form_page.dart)

### ✅ Documentation Complete

- `CRITICAL_BUG_PURCHASE_INVENTORY.md` - Inventory bug + 5 test scenarios
- `CRITICAL_BUG_PURCHASE_JOURNAL.md` - Journal bug + 6 test scenarios
- `CRITICAL_BUG_PURCHASE_PAYMENT_RECALC.md` - Payment bug + 5 test scenarios
- `CRITICAL_FIX_INFINITE_RECURSION.md` - Recursion bug + fix explanation
- `COMPREHENSIVE_FORWARD_BACKWARD_VERIFICATION.md` - 20 comprehensive test scenarios
- `FLUTTER_SQL_INTEGRATION_VERIFIED.md` - Flutter integration verification

---

## 🚀 Deployment Steps

### Step 1: Backup Existing Data

```sql
-- 1. Backup purchase invoices
CREATE TABLE purchase_invoices_backup_20251013 AS 
SELECT * FROM purchase_invoices;

-- 2. Backup purchase payments
CREATE TABLE purchase_payments_backup_20251013 AS 
SELECT * FROM purchase_payments;

-- 3. Backup journal entries
CREATE TABLE journal_entries_backup_20251013 AS 
SELECT * FROM journal_entries WHERE source_module IN ('purchase_invoices', 'purchase_payments');

-- 4. Backup stock movements
CREATE TABLE stock_movements_backup_20251013 AS 
SELECT * FROM stock_movements WHERE reference LIKE 'PINV-%';

-- 5. Verify backups
SELECT COUNT(*) FROM purchase_invoices_backup_20251013;
SELECT COUNT(*) FROM purchase_payments_backup_20251013;
SELECT COUNT(*) FROM journal_entries_backup_20251013;
SELECT COUNT(*) FROM stock_movements_backup_20251013;
```

### Step 2: Check for Existing Data Corruption

Run these queries to identify any corruption from the bugs:

```sql
-- 1. Find duplicate inventory movements (should be 0 after fix)
SELECT reference, COUNT(*) as count
FROM stock_movements
WHERE reference LIKE 'PINV-%'
GROUP BY reference
HAVING COUNT(*) > 1;

-- 2. Find duplicate journal entries (should be 0 after fix)
SELECT reference, COUNT(*) as count
FROM journal_entries
WHERE source_module = 'purchase_invoices'
GROUP BY reference
HAVING COUNT(*) > 1;

-- 3. Find invoices with status='paid' but zero payments (should be 0 after fix)
SELECT pi.id, pi.invoice_number, pi.status, pi.paid_amount
FROM purchase_invoices pi
WHERE pi.status = 'paid' AND pi.paid_amount = 0;

-- 4. Find invoices with status='received' but zero payments in prepayment model (should be 0 after fix)
SELECT pi.id, pi.invoice_number, pi.status, pi.paid_amount, pi.prepayment_model
FROM purchase_invoices pi
WHERE pi.prepayment_model = true 
  AND pi.status = 'received' 
  AND pi.paid_amount = 0;
```

**If corruption found:**
- Document the invoices/payments affected
- May need to manually fix status or delete duplicate entries
- Keep backup tables for reference

### Step 3: Deploy core_schema.sql

**⚠️ CRITICAL: This will drop and recreate ALL functions and triggers!**

1. Open Supabase Dashboard → SQL Editor
2. Create a new query
3. Copy the **ENTIRE** contents of `supabase/sql/core_schema.sql`
4. Paste into SQL Editor
5. **Review carefully** (scroll through to verify it looks correct)
6. Click **Run**
7. **Wait for completion** (may take 30-60 seconds)
8. **Check for errors** in the output

**Expected Output:**
```
CREATE TABLE
CREATE TABLE
...
CREATE OR REPLACE FUNCTION
...
NOTICE: Trigger trg_purchase_invoices_change created successfully
NOTICE: Trigger trg_purchase_payments_change created successfully
...
Query OK
```

**If errors occur:**
- **DO NOT PANIC**
- Copy the error message
- Check if tables already exist (should be fine, CREATE TABLE IF NOT EXISTS)
- Check if functions have syntax errors (shouldn't happen, we tested)
- Restore from backup if needed

### Step 4: Verify Deployment

Run these queries to verify triggers are in place:

```sql
-- 1. Check invoice trigger exists
SELECT tgname, tgtype, tgenabled
FROM pg_trigger
WHERE tgname = 'trg_purchase_invoices_change';

-- 2. Check payment trigger exists
SELECT tgname, tgtype, tgenabled
FROM pg_trigger
WHERE tgname = 'trg_purchase_payments_change';

-- 3. Check functions exist
SELECT proname, prosrc
FROM pg_proc
WHERE proname IN (
  'handle_purchase_invoice_change',
  'handle_purchase_payment_change',
  'recalculate_purchase_invoice_payments',
  'consume_purchase_invoice_inventory',
  'restore_purchase_invoice_inventory',
  'create_purchase_invoice_journal_entry',
  'delete_purchase_invoice_journal_entry'
);

-- 4. Verify recursion guard (check function source contains the guard)
SELECT prosrc
FROM pg_proc
WHERE proname = 'handle_purchase_invoice_change';
-- Should contain: "if OLD.items IS DISTINCT FROM NEW.items"
```

### Step 5: Test Basic Operations

**Test 1: Create Invoice (Standard Model)**
```sql
-- 1. Insert new invoice
INSERT INTO purchase_invoices (
  invoice_number, supplier_id, invoice_date, due_date,
  subtotal, tax, total, status, prepayment_model, items
) VALUES (
  'TEST-001', 
  (SELECT id FROM suppliers LIMIT 1),
  CURRENT_DATE,
  CURRENT_DATE + INTERVAL '30 days',
  1000, 190, 1190,
  'draft',
  false,
  '[{"product_id": "00000000-0000-0000-0000-000000000001", "quantity": 10, "price": 100}]'::jsonb
);

-- 2. Confirm invoice
UPDATE purchase_invoices 
SET status = 'confirmed' 
WHERE invoice_number = 'TEST-001';

-- 3. Check journal entry created
SELECT * FROM journal_entries 
WHERE source_module = 'purchase_invoices' 
  AND source_reference LIKE 'PINV-%';

-- 4. Mark as received
UPDATE purchase_invoices 
SET status = 'received' 
WHERE invoice_number = 'TEST-001';

-- 5. Check inventory added (should be ONE stock movement)
SELECT * FROM stock_movements 
WHERE reference LIKE '%TEST-001%';

-- 6. Add payment
INSERT INTO purchase_payments (
  invoice_id, payment_date, amount, payment_method_id
) VALUES (
  (SELECT id FROM purchase_invoices WHERE invoice_number = 'TEST-001'),
  CURRENT_DATE,
  1190,
  (SELECT id FROM payment_methods LIMIT 1)
);

-- 7. Check status changed to 'paid'
SELECT id, invoice_number, status, paid_amount, balance
FROM purchase_invoices 
WHERE invoice_number = 'TEST-001';
-- Should be: status='paid', paid_amount=1190, balance=0

-- 8. Check payment journal entry created
SELECT * FROM journal_entries 
WHERE source_module = 'purchase_payments';

-- 9. Clean up
DELETE FROM purchase_invoices WHERE invoice_number = 'TEST-001';
```

**Expected Results:**
- ✅ Invoice created
- ✅ Journal entry created when confirmed (only once!)
- ✅ Inventory added when received (only once!)
- ✅ Status changed to 'paid' after payment
- ✅ Payment journal entry created
- ✅ No stack overflow errors
- ✅ No duplicate entries

**Test 2: Delete Payment (Test Recalculation)**
```sql
-- 1. Create invoice and payment (reuse TEST-001 or create TEST-002)
-- ...

-- 2. Delete payment
DELETE FROM purchase_payments 
WHERE invoice_id = (SELECT id FROM purchase_invoices WHERE invoice_number = 'TEST-001');

-- 3. Check status reverted
SELECT id, invoice_number, status, paid_amount, balance
FROM purchase_invoices 
WHERE invoice_number = 'TEST-001';
-- Standard model: Should revert to 'received'
-- Prepayment model: Should revert to 'confirmed'

-- 4. Check payment journal deleted
SELECT * FROM journal_entries 
WHERE source_module = 'purchase_payments';
-- Should be empty (deleted)

-- 5. Check invoice journal still exists
SELECT * FROM journal_entries 
WHERE source_module = 'purchase_invoices';
-- Should still exist (not deleted when payment removed)
```

**Expected Results:**
- ✅ Status reverted correctly based on prepayment_model
- ✅ Payment journal deleted
- ✅ Invoice journal still exists
- ✅ No stack overflow errors

---

## 🧪 Comprehensive Testing

After basic tests pass, run the **20 comprehensive test scenarios** from:
- `COMPREHENSIVE_FORWARD_BACKWARD_VERIFICATION.md`

**Test Sets:**
1. **Standard Model** (8 tests) - Draft→Paid→Draft flow
2. **Prepayment Model** (7 tests) - Draft→Received→Draft flow
3. **Edge Cases** (5 tests) - Manual status changes, item edits, etc.

**For each test:**
- ✅ Document the starting state
- ✅ Perform the action
- ✅ Verify expected result
- ✅ Check for stack overflow errors
- ✅ Check for duplicate entries
- ✅ Mark test as PASS or FAIL

---

## ⚠️ Rollback Plan

**If deployment fails or critical issues found:**

```sql
-- 1. Restore data from backup
TRUNCATE purchase_invoices CASCADE;
INSERT INTO purchase_invoices SELECT * FROM purchase_invoices_backup_20251013;

TRUNCATE purchase_payments CASCADE;
INSERT INTO purchase_payments SELECT * FROM purchase_payments_backup_20251013;

DELETE FROM journal_entries WHERE source_module IN ('purchase_invoices', 'purchase_payments');
INSERT INTO journal_entries SELECT * FROM journal_entries_backup_20251013;

DELETE FROM stock_movements WHERE reference LIKE 'PINV-%';
INSERT INTO stock_movements SELECT * FROM stock_movements_backup_20251013;

-- 2. Verify restoration
SELECT COUNT(*) FROM purchase_invoices;
SELECT COUNT(*) FROM purchase_payments;

-- 3. Re-deploy old schema (if you have it backed up)
-- Or manually disable triggers:
DROP TRIGGER IF EXISTS trg_purchase_invoices_change ON purchase_invoices;
DROP TRIGGER IF EXISTS trg_purchase_payments_change ON purchase_payments;
```

---

## 📊 Success Criteria

Deployment is successful if:

1. ✅ All triggers created without errors
2. ✅ Basic test operations complete successfully
3. ✅ No stack overflow errors
4. ✅ No duplicate inventory movements
5. ✅ No duplicate journal entries
6. ✅ Status recalculation works correctly
7. ✅ Both prepayment models work correctly
8. ✅ Forward and backward flows work correctly

---

## 🎉 Post-Deployment

**After successful deployment:**

1. ✅ Update Flutter app (already done, no changes needed)
2. ✅ Monitor Supabase logs for errors
3. ✅ Test with real data (not just TEST invoices)
4. ✅ Train users on new workflow (if any changes)
5. ✅ Keep backup tables for 30 days (then drop)
6. ✅ **Remove quick delete testing buttons** (see QUICK_DELETE_BUTTONS.md)
7. ✅ Document any issues found during production use

**Monitoring Queries:**
```sql
-- Check for stack overflow errors in logs
-- (Supabase Dashboard → Logs → Filter for "stack depth")

-- Check for duplicate entries (should always be 0)
SELECT reference, COUNT(*) FROM stock_movements 
WHERE reference LIKE 'PINV-%' AND created_at > NOW() - INTERVAL '7 days'
GROUP BY reference HAVING COUNT(*) > 1;

SELECT reference, COUNT(*) FROM journal_entries 
WHERE source_module = 'purchase_invoices' AND created_at > NOW() - INTERVAL '7 days'
GROUP BY reference HAVING COUNT(*) > 1;
```

---

## 📞 Support

**If issues arise:**
1. Check Supabase logs for detailed error messages
2. Review relevant documentation (CRITICAL_*.md files)
3. Check if issue is related to one of the four bugs we fixed
4. Test in isolation (create TEST invoice with minimal data)
5. Contact support with error details and reproduction steps

**Common Issues:**
- **Stack overflow** → Check if recursion guard is in place
- **Duplicate inventory** → Check inventory trigger (should only fire at 'received')
- **Duplicate journals** → Check journal trigger (should only create once at 'confirmed')
- **Wrong status after payment deletion** → Check recalculate function (should respect prepayment_model)

---

**Deployment Prepared By**: AI Agent (GitHub Copilot)  
**Date**: 2025-10-13  
**Ready**: ✅ YES  
**Risk Level**: ⚠️ MEDIUM (4 critical bugs fixed, comprehensive testing needed)  
**Estimated Time**: 30-60 minutes (backup + deploy + basic tests)

---

🚀 **READY TO DEPLOY!**
