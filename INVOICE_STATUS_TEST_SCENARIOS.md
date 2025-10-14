# 🧪 Invoice Status Logic - Complete Test Scenarios

## Status Transition Logic Summary

The `recalculate_sales_invoice_payments()` function determines invoice status based on:
1. Current status
2. Total payments received
3. Invoice total amount

## Complete Logic Decision Tree

```
IF cancelled:
  → Keep 'cancelled'

ELSE IF draft:
  IF v_total >= invoice.total AND v_total > 0:
    → 'paid'
  ELSE:
    → Keep 'draft'

ELSE IF v_total >= invoice.total AND v_total > 0:
  → 'paid' (fully paid)

ELSE IF v_total > 0 AND v_total < invoice.total:
  IF status = 'overdue':
    → Keep 'overdue'
  ELSE:
    → 'confirmed'

ELSE IF v_total = 0:
  IF status = 'paid':
    → 'confirmed' (revert from paid)
  ELSE:
    → Keep current status (draft/sent/confirmed/overdue)

ELSE:
  → Keep current status (fallback)
```

## 🎯 Test Scenarios

### Scenario 1: Full Forward Flow (Happy Path)
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create draft invoice            | -             | 0        | draft        | ✅
Click "Marcar como enviada"     | draft         | 0        | sent         | ✅
Click "Confirmar"                | sent          | 0        | confirmed    | ✅
Add payment ($1000, total=$1000)| confirmed     | 1000     | paid         | ✅
```

### Scenario 2: Full Backward Flow (Reversions)
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Start with paid invoice         | paid          | 1000     | paid         | ✅
Delete payment ("Deshacer pago")| paid          | 0        | confirmed    | ✅
Click "Volver a enviada"        | confirmed     | 0        | sent         | ✅
Click "Volver a borrador"       | sent          | 0        | draft        | ✅
```

### Scenario 3: Direct Draft → Paid (Skip Transitions)
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create draft invoice            | -             | 0        | draft        | ✅
Add full payment immediately    | draft         | 1000     | paid         | ✅
```

### Scenario 4: Partial Payments
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create and confirm invoice      | -             | 0        | confirmed    | ✅
Add partial payment ($500/$1000)| confirmed     | 500      | confirmed    | ✅
Add second payment ($500)       | confirmed     | 1000     | paid         | ✅
Delete second payment           | paid          | 500      | confirmed    | ✅
Delete first payment            | confirmed     | 0        | confirmed    | ✅
```

### Scenario 5: Manual Transitions Without Payments
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create draft                    | -             | 0        | draft        | ✅
Mark as sent                    | draft         | 0        | sent         | ✅
Confirm                         | sent          | 0        | confirmed    | ✅
Revert to sent                  | confirmed     | 0        | sent         | ✅
Revert to draft                 | sent          | 0        | draft        | ✅
Mark as sent again              | draft         | 0        | sent         | ✅
Confirm again                   | sent          | 0        | confirmed    | ✅
```

### Scenario 6: Sent + Partial Payment → Confirmed
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create draft                    | -             | 0        | draft        | ✅
Mark as sent                    | draft         | 0        | sent         | ✅
Add partial payment ($500/$1000)| sent          | 500      | confirmed    | ✅
```
**Note:** Partial payment from 'sent' should advance to 'confirmed' for tracking.

### Scenario 7: Overpayment Handling
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create confirmed invoice ($1000)| -             | 0        | confirmed    | ✅
Add payment ($1500)             | confirmed     | 1500     | paid         | ✅
```
**Note:** v_total >= invoice.total, so status becomes 'paid'.

### Scenario 8: Multiple Partial Payments
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Confirmed invoice ($1000)       | -             | 0        | confirmed    | ✅
Add payment $300                | confirmed     | 300      | confirmed    | ✅
Add payment $200                | confirmed     | 500      | confirmed    | ✅
Add payment $500 (total $1000)  | confirmed     | 1000     | paid         | ✅
Delete last payment             | paid          | 500      | confirmed    | ✅
Delete second payment           | confirmed     | 300      | confirmed    | ✅
Delete first payment            | confirmed     | 0        | confirmed    | ✅
```

### Scenario 9: Draft Payment Then Delete
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Create draft invoice            | -             | 0        | draft        | ✅
Add full payment                | draft         | 1000     | paid         | ✅
Delete payment                  | paid          | 0        | confirmed    | ✅
```
**Note:** Even though it was 'draft' before payment, deleting payment from 'paid' goes to 'confirmed' (not back to 'draft').

### Scenario 10: Cancelled Invoice (Immutable)
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Confirmed invoice               | -             | 0        | confirmed    | ✅
Cancel invoice                  | confirmed     | 0        | cancelled    | ✅
Attempt to add payment          | cancelled     | 1000     | cancelled    | ✅
```
**Note:** Cancelled status never changes regardless of payments.

### Scenario 11: Overdue Invoice
```
Action                          | Status Before | Payments | Status After | ✓
--------------------------------|---------------|----------|--------------|---
Confirmed invoice (past due)    | -             | 0        | confirmed    | ✅
System sets to overdue          | confirmed     | 0        | overdue      | ✅
Add partial payment ($500/$1000)| overdue       | 500      | overdue      | ✅
Add remaining payment ($500)    | overdue       | 1000     | paid         | ✅
```
**Note:** Overdue status persists through partial payments until fully paid.

## 🚨 Edge Cases to Test

### Edge Case 1: Zero-Amount Invoice
```
Invoice total = $0
Add payment $0
Expected: Should handle gracefully (probably stay in current status)
```

### Edge Case 2: Negative Payment (Refund)
```
Confirmed invoice $1000
Add payment $1000 → paid
Add payment -$1000 (refund) → total = $0
Expected: Should revert to 'confirmed'
```

### Edge Case 3: Race Condition (Rapid Status Changes)
```
User clicks "Marcar como enviada"
Before trigger completes, user clicks "Confirmar"
Expected: Should end up in 'confirmed' state
```

### Edge Case 4: Manual Override During Payment
```
Invoice is 'sent'
Add payment $1000 (full) → should become 'paid'
While trigger runs, user manually sets to 'cancelled'
Expected: Last write wins (probably 'paid' due to trigger)
```

## 📋 Quick Test Checklist

Use this for rapid manual testing:

- [ ] Draft → Sent (manual)
- [ ] Sent → Confirmed (manual)
- [ ] Confirmed → Paid (payment)
- [ ] Paid → Confirmed (delete payment)
- [ ] Confirmed → Sent (manual)
- [ ] Sent → Draft (manual)
- [ ] Draft → Paid (direct payment)
- [ ] Sent + partial payment → Confirmed
- [ ] Confirmed + partial payment → stays Confirmed
- [ ] Multiple partial payments → Paid
- [ ] Cancelled → stays Cancelled (even with payment)
- [ ] Overdue + partial → stays Overdue
- [ ] Overdue + full payment → Paid

## 🔍 Debugging Tips

If status transitions don't work:

1. **Check Supabase Logs:**
   ```sql
   -- Enable function logging
   SET client_min_messages TO NOTICE;
   
   -- Watch for these messages:
   -- "handle_sales_invoice_change: UPDATE invoice <id>, old status <x>, new status <y>"
   -- "recalculate_sales_invoice_payments: setting status to <status>"
   ```

2. **Check Payment Totals:**
   ```sql
   SELECT 
     id,
     status,
     total,
     paid_amount,
     balance,
     (SELECT COALESCE(SUM(amount), 0) FROM sales_payments WHERE invoice_id = si.id) as calculated_paid
   FROM sales_invoices si
   WHERE id = '<invoice-id>';
   ```

3. **Check Trigger Depth:**
   ```sql
   -- If trigger depth > 1, recalculate is skipped to prevent infinite recursion
   -- Look for: "trigger depth > 1, returning" in logs
   ```

4. **Verify Payment Records:**
   ```sql
   SELECT * FROM sales_payments WHERE invoice_id = '<invoice-id>' ORDER BY created_at;
   ```

## 🎬 Test Script (SQL)

Run this in Supabase SQL Editor to test programmatically:

```sql
-- Create test invoice
INSERT INTO sales_invoices (customer_id, invoice_number, date, total, status)
VALUES ('customer-uuid', 'TEST-001', NOW(), 1000.00, 'draft')
RETURNING id;

-- Test 1: Manual transition to sent
UPDATE sales_invoices SET status = 'sent' WHERE invoice_number = 'TEST-001';
SELECT status FROM sales_invoices WHERE invoice_number = 'TEST-001';
-- Expected: sent

-- Test 2: Manual transition to confirmed
UPDATE sales_invoices SET status = 'confirmed' WHERE invoice_number = 'TEST-001';
SELECT status FROM sales_invoices WHERE invoice_number = 'TEST-001';
-- Expected: confirmed

-- Test 3: Add full payment
INSERT INTO sales_payments (invoice_id, payment_method_id, amount, date)
SELECT id, (SELECT id FROM payment_methods WHERE code = 'cash'), 1000.00, NOW()
FROM sales_invoices WHERE invoice_number = 'TEST-001';
SELECT status FROM sales_invoices WHERE invoice_number = 'TEST-001';
-- Expected: paid

-- Test 4: Delete payment
DELETE FROM sales_payments WHERE invoice_id = (SELECT id FROM sales_invoices WHERE invoice_number = 'TEST-001');
SELECT status FROM sales_invoices WHERE invoice_number = 'TEST-001';
-- Expected: confirmed

-- Cleanup
DELETE FROM sales_invoices WHERE invoice_number = 'TEST-001';
```

---

**Last Updated:** After fixing both forward and backward transition logic  
**Status:** ✅ Ready for deployment and testing
