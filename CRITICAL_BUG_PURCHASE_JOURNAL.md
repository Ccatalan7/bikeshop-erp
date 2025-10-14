# 🚨 CRITICAL BUG: Purchase Invoice Journal Entries Being Recreated Multiple Times

## 📋 Bug Report

**Date Discovered**: 2025-10-13  
**Severity**: CRITICAL (Data Integrity)  
**Module**: Purchase Invoices  
**File**: `supabase/sql/core_schema.sql`  
**Function**: `handle_purchase_invoice_change()`

---

## ❌ THE PROBLEM

The trigger was **recreating journal entries on EVERY status change** within confirmed/received/paid range, even when invoice amounts didn't change.

### Broken Logic (BEFORE):
```sql
elsif v_old_status IN ('confirmed', 'received', 'paid') 
  AND v_new_status IN ('confirmed', 'received', 'paid') 
  AND v_old_status != v_new_status then
  -- This fires on EVERY status transition!
  perform public.delete_purchase_invoice_journal_entry(OLD.id);
  perform public.create_purchase_invoice_journal_entry(NEW);
end if;
```

---

## 💥 IMPACT ANALYSIS

### Standard Model (prepayment_model=false): Draft→Sent→Confirmed→Received→Paid

| Status Transition | OLD Logic (BROKEN) | Impact |
|------------------|-------------------|---------|
| Draft → Sent | ✅ Nothing | Correct |
| Sent → Confirmed | ✅ Create journal | Correct |
| Confirmed → Received | ❌ DELETE + CREATE journal | **Duplicate journal entries** |
| Received → Paid | ❌ DELETE + CREATE journal | **Duplicate journal entries** |

**Result**: Journal entry created 3 times (confirmed, received, paid) instead of once!

### Prepayment Model (prepayment_model=true): Draft→Sent→Confirmed→Paid→Received

| Status Transition | OLD Logic (BROKEN) | Impact |
|------------------|-------------------|---------|
| Draft → Sent | ✅ Nothing | Correct |
| Sent → Confirmed | ✅ Create journal | Correct |
| Confirmed → Paid | ❌ DELETE + CREATE journal | **Duplicate journal entries** |
| Paid → Received | ❌ DELETE + CREATE journal | **Duplicate journal entries** |

**Result**: Journal entry created 3 times (confirmed, paid, received) instead of once!

### Going Backwards (Both Models)

| Status Transition | OLD Logic (BROKEN) | Impact |
|------------------|-------------------|---------|
| Paid → Received | ❌ DELETE + CREATE journal | **Unnecessary recreation** |
| Received → Confirmed | ❌ DELETE + CREATE journal | **Unnecessary recreation** |
| Confirmed → Sent | ✅ DELETE journal | Correct |

---

## 🔧 ROOT CAUSE

The condition:
```sql
v_old_status IN ('confirmed', 'received', 'paid') AND 
v_new_status IN ('confirmed', 'received', 'paid') AND 
v_old_status != v_new_status
```

This catches **EVERY** status change within the confirmed→received→paid range, causing unnecessary DELETE + CREATE operations.

### Accounting Impact:
- **journal_entries** table: Multiple entries for same invoice (deleted and recreated)
- **journal_entry_items** table: Multiple debit/credit pairs (deleted and recreated)
- **Audit trail**: Cluttered with unnecessary delete/create operations
- **Performance**: Wasted database operations (delete + create on every status change)
- **Data integrity**: Risk of orphaned journal entries if delete fails but create succeeds

---

## ✅ CORRECT BEHAVIOR

### What SHOULD Happen:

The purchase invoice journal entry represents the accounting transaction:
```
Dr 1510 Inventory          $1,000
   Cr 2110 Accounts Payable       $1,000
```

This journal entry should:
1. **Be created ONCE** when invoice reaches 'confirmed' status
2. **Stay unchanged** when moving between confirmed→received→paid
3. **Only be deleted** when reverting to draft/sent/cancelled
4. **Only be recreated** if staying at same status but amounts changed

### Why?

- **At confirmed**: Purchase is approved, accounting transaction is locked
- **At received**: Inventory changes (handled by separate inventory trigger), journal stays same
- **At paid**: Payment creates SEPARATE journal entry (handled by payment trigger), invoice journal stays same

The invoice journal entry is **immutable** once created at confirmation!

---

## 🔧 THE FIX

### Fixed Logic (AFTER):
```sql
-- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting
-- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)
-- It should NOT be recreated when moving between confirmed→received→paid
-- It should ONLY be recreated if staying at same status but amounts changed

if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
  -- Transitioning TO confirmed/received/paid: create journal entry
  raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
  perform public.create_purchase_invoice_journal_entry(NEW);
  
elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
  -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
  raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
  perform public.delete_purchase_invoice_journal_entry(OLD.id);
  
elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then
  -- Staying at same confirmed+ status but invoice data might have changed
  -- Only recreate journal if amounts changed (not just status transition)
  if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR 
     OLD.tax IS DISTINCT FROM NEW.tax OR 
     OLD.total IS DISTINCT FROM NEW.total OR
     OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then
    raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';
    perform public.delete_purchase_invoice_journal_entry(OLD.id);
    perform public.create_purchase_invoice_journal_entry(NEW);
  end if;
end if;
```

### Key Changes:
1. ❌ **REMOVED**: `v_old_status != v_new_status` condition (was causing recreations)
2. ✅ **ADDED**: `v_old_status = v_new_status` check (only recreate if SAME status)
3. ✅ **ADDED**: Amount comparison (subtotal, tax, total, supplier) before recreating
4. ✅ **ADDED**: Clear comments explaining the correct behavior

---

## 📊 EXPECTED BEHAVIOR AFTER FIX

### Standard Model Forward (Draft→Sent→Confirmed→Received→Paid):

| Status Transition | Journal Action | Inventory Action | Correct? |
|------------------|---------------|------------------|----------|
| Draft → Sent | Nothing | Nothing | ✅ |
| Sent → Confirmed | **CREATE journal** | Nothing | ✅ |
| Confirmed → Received | Nothing | **ADD inventory** | ✅ |
| Received → Paid | Nothing | Nothing | ✅ |

**Result**: Journal created ONCE at confirmed, never touched again ✅

### Prepayment Model Forward (Draft→Sent→Confirmed→Paid→Received):

| Status Transition | Journal Action | Inventory Action | Correct? |
|------------------|---------------|------------------|----------|
| Draft → Sent | Nothing | Nothing | ✅ |
| Sent → Confirmed | **CREATE journal** | Nothing | ✅ |
| Confirmed → Paid | Nothing | Nothing | ✅ |
| Paid → Received | Nothing | **ADD inventory** | ✅ |

**Result**: Journal created ONCE at confirmed, never touched again ✅

### Standard Model Backward (Paid→Received→Confirmed→Sent):

| Status Transition | Journal Action | Inventory Action | Correct? |
|------------------|---------------|------------------|----------|
| Paid → Received | Nothing | Nothing | ✅ |
| Received → Confirmed | Nothing | **RESTORE inventory** | ✅ |
| Confirmed → Sent | **DELETE journal** | Nothing | ✅ |

**Result**: Journal deleted ONCE when reverting to sent ✅

### Prepayment Model Backward (Received→Paid→Confirmed→Sent):

| Status Transition | Journal Action | Inventory Action | Correct? |
|------------------|---------------|------------------|----------|
| Received → Paid | Nothing | **RESTORE inventory** | ✅ |
| Paid → Confirmed | Nothing | Nothing | ✅ |
| Confirmed → Sent | **DELETE journal** | Nothing | ✅ |

**Result**: Journal deleted ONCE when reverting to sent ✅

### Edge Case: Editing Amounts at Confirmed Status:

| Action | Journal Action | Inventory Action | Correct? |
|--------|---------------|------------------|----------|
| Edit subtotal/tax/total | **DELETE + CREATE journal** | Nothing | ✅ |
| Change supplier | **DELETE + CREATE journal** | Nothing | ✅ |
| Edit notes only | Nothing | Nothing | ✅ |

**Result**: Journal recreated ONLY when amounts change ✅

---

## 🧪 TEST SCENARIOS

### Test 1: Standard Model Forward - Journal Created Once
```sql
-- 1. Create purchase invoice
INSERT INTO purchase_invoices (supplier_id, invoice_number, status, subtotal, tax, total, prepayment_model)
VALUES ('[supplier-uuid]', 'PINV-TEST-001', 'draft', 1000, 190, 1190, false);

-- Check: No journal entry yet
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 0 rows

-- 2. Mark as sent
UPDATE purchase_invoices SET status = 'sent' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Still no journal entry
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 0 rows

-- 3. Confirm invoice
UPDATE purchase_invoices SET status = 'confirmed' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal entry created (FIRST TIME)
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 1 row, created_at = now()

-- Save the created_at timestamp
\set first_created_at (SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-001')

-- 4. Mark as received
UPDATE purchase_invoices SET status = 'received' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal entry UNCHANGED (same created_at)
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: Same as :first_created_at (NOT recreated!)

-- 5. Mark as paid
UPDATE purchase_invoices SET status = 'paid' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal entry STILL UNCHANGED
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: Same as :first_created_at (NOT recreated!)

-- ✅ PASS: Journal created ONCE at confirmed, never recreated
```

### Test 2: Prepayment Model Forward - Journal Created Once
```sql
-- 1. Create purchase invoice (prepayment model)
INSERT INTO purchase_invoices (supplier_id, invoice_number, status, subtotal, tax, total, prepayment_model)
VALUES ('[supplier-uuid]', 'PINV-TEST-002', 'draft', 2000, 380, 2380, true);

-- 2. Confirm invoice
UPDATE purchase_invoices SET status = 'confirmed' WHERE invoice_number = 'PINV-TEST-002';

-- Check: Journal entry created
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-002';
-- Expected: 1 row

\set first_created_at (SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-002')

-- 3. Mark as paid
UPDATE purchase_invoices SET status = 'paid' WHERE invoice_number = 'PINV-TEST-002';

-- Check: Journal entry UNCHANGED (NOT recreated on payment!)
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-002';
-- Expected: Same as :first_created_at

-- 4. Mark as received
UPDATE purchase_invoices SET status = 'received' WHERE invoice_number = 'PINV-TEST-002';

-- Check: Journal entry STILL UNCHANGED
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-002';
-- Expected: Same as :first_created_at

-- ✅ PASS: Journal created ONCE at confirmed, never recreated (even with prepayment)
```

### Test 3: Standard Model Backward - Journal Deleted Once
```sql
-- Start with paid invoice (from Test 1)
UPDATE purchase_invoices SET status = 'paid' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal exists
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 1 row

-- 1. Revert to received
UPDATE purchase_invoices SET status = 'received' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal STILL EXISTS (not deleted)
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 1 row

-- 2. Revert to confirmed
UPDATE purchase_invoices SET status = 'confirmed' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal STILL EXISTS
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 1 row

-- 3. Revert to sent
UPDATE purchase_invoices SET status = 'sent' WHERE invoice_number = 'PINV-TEST-001';

-- Check: Journal DELETED
SELECT * FROM journal_entries WHERE reference = 'PINV-TEST-001';
-- Expected: 0 rows

-- ✅ PASS: Journal deleted ONCE when reverting to sent
```

### Test 4: Edit Amounts at Confirmed Status - Journal Recreated
```sql
-- Create and confirm invoice
INSERT INTO purchase_invoices (supplier_id, invoice_number, status, subtotal, tax, total, prepayment_model)
VALUES ('[supplier-uuid]', 'PINV-TEST-003', 'confirmed', 1000, 190, 1190, false);

-- Check: Journal created
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-003';
\set first_created_at (SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-003')

-- Wait 1 second to ensure timestamp difference
SELECT pg_sleep(1);

-- Edit subtotal (amounts changed, status same)
UPDATE purchase_invoices 
SET subtotal = 1500, tax = 285, total = 1785 
WHERE invoice_number = 'PINV-TEST-003';

-- Check: Journal RECREATED (new created_at)
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-003';
-- Expected: Different from :first_created_at (recreated!)

-- ✅ PASS: Journal recreated when amounts change at same status
```

### Test 5: Edit Notes at Confirmed Status - Journal Unchanged
```sql
-- Start with confirmed invoice (from Test 4)
UPDATE purchase_invoices SET status = 'confirmed', subtotal = 1000, tax = 190, total = 1190 
WHERE invoice_number = 'PINV-TEST-003';

-- Check: Journal exists
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-003';
\set before_edit (SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-003')

-- Wait 1 second
SELECT pg_sleep(1);

-- Edit notes only (amounts unchanged, status same)
UPDATE purchase_invoices 
SET notes = 'Updated notes, amounts unchanged' 
WHERE invoice_number = 'PINV-TEST-003';

-- Check: Journal UNCHANGED (same created_at)
SELECT created_at FROM journal_entries WHERE reference = 'PINV-TEST-003';
-- Expected: Same as :before_edit (NOT recreated!)

-- ✅ PASS: Journal unchanged when non-amount fields edited
```

### Test 6: Check for Duplicate Journal Entries
```sql
-- Find any purchase invoices with multiple journal entries
SELECT 
  je.reference,
  COUNT(*) as journal_count,
  array_agg(je.id ORDER BY je.created_at) as journal_ids,
  array_agg(je.created_at ORDER BY je.created_at) as created_timestamps
FROM journal_entries je
WHERE je.reference LIKE 'PINV-%'
GROUP BY je.reference
HAVING COUNT(*) > 1;

-- Expected: 0 rows (no duplicates!)

-- ✅ PASS: No duplicate journal entries for any purchase invoice
```

---

## 🎯 BUSINESS LOGIC

### Purchase Invoice Journal Entry Purpose:

The journal entry created at 'confirmed' status represents the **purchase transaction**:

```
Dr 1510 Inventory (or expense account)     $1,190
   Cr 2110 Accounts Payable                      $1,190
```

This entry:
- Records the **liability** to the supplier (Accounts Payable credit)
- Records the **asset** received (Inventory debit, or expense if non-inventory)
- Is created at **confirmation** (when purchase is approved)
- Remains **unchanged** as invoice moves through received→paid
- Is **deleted** only if invoice is reverted to draft/sent/cancelled

### Separate Journal Entries:

1. **Payment Journal Entry** (created by payment trigger):
   ```
   Dr 2110 Accounts Payable     $1,190
      Cr 1101 Cash (or bank)          $1,190
   ```
   - Created when payment is registered
   - Records the **payment** of the liability
   - Separate from invoice journal entry

2. **Inventory Movement** (handled by inventory trigger):
   - Physical stock change at 'received' status
   - No journal entry needed (already recorded at confirmation)

### Why Journal Should NOT Be Recreated:

- **At received**: Physical goods arrive, but accounting transaction was already recorded at confirmation
- **At paid**: Payment is recorded in SEPARATE journal entry (payment trigger), invoice journal stays same
- **At status changes**: Unless amounts changed, the accounting transaction is immutable

**Recreating the journal on every status change would:**
- ❌ Create duplicate journal entries
- ❌ Clutter audit trail
- ❌ Waste database resources
- ❌ Risk orphaned entries if delete fails
- ❌ Violate accounting principle of immutable transactions

---

## 📦 DEPLOYMENT NOTES

### Files Changed:
- `supabase/sql/core_schema.sql` (handle_purchase_invoice_change function, lines ~3130-3165)

### Deployment Steps:
1. Backup current database (see DEPLOYMENT_CHECKLIST.md)
2. Run entire `core_schema.sql` in Supabase SQL Editor
3. Verify trigger recreated successfully
4. Run test scenarios 1-6 above
5. Check for duplicate journal entries (Test 6)
6. Monitor Supabase logs for errors

### Rollback Plan:
If issues detected:
1. Restore from backup
2. Investigate failed test scenario
3. Fix trigger logic
4. Redeploy

---

## 🎓 LESSONS LEARNED

### How This Bug Was Found:
User asked: **"what about journal entries (creation and deleting) in both models, either going forward or backwards? did you checked that too???? remember what #file:copilot-instructions.md says"**

Agent investigated and found the journal entry recreation bug immediately after fixing the inventory bug.

### Prevention:
1. ✅ **Always trace EVERY status transition** (not just happy path)
2. ✅ **Test BOTH prepayment models** (standard and prepayment)
3. ✅ **Test BOTH directions** (forward and backward status changes)
4. ✅ **Check for unnecessary operations** (delete+create when nothing changed)
5. ✅ **Follow copilot-instructions.md rules**: Check existing patterns, avoid assumptions
6. ✅ **User skepticism is valuable**: Questions like "did you check both models?" catch bugs!

### Related Bugs:
- See CRITICAL_BUG_PURCHASE_INVENTORY.md for inventory double/triple-counting bug
- Both bugs had same root cause: Treating all non-draft statuses the same instead of explicit checks

---

## ✅ STATUS

- [x] Bug identified
- [x] Root cause analyzed
- [x] Fix implemented
- [x] Documentation created
- [ ] Database deployed
- [ ] Tests executed
- [ ] Production verification

**Next Step**: Deploy `core_schema.sql` and run test scenarios 1-6 to verify the fix!
