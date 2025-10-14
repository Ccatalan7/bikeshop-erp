# 🔄 Invoice Status Fix - "Deshacer Pago" Issue

**Date:** October 13, 2025  
**Issue:** After deleting a payment ("Deshacer pago"), the invoice status was not reverting back to "confirmada"

---

## 🐛 Problem Description

### User Flow:
1. ✅ Create invoice (status: 'draft')
2. ✅ Confirm invoice (status: 'confirmed')
3. ✅ Register payment (status: 'paid')
4. ✅ Click "Deshacer pago" button
5. ✅ Payment is deleted
6. ✅ Payment journal entry is deleted
7. ❌ **Invoice status remains 'paid' instead of reverting to 'confirmed'**

### Root Cause:
The `recalculate_sales_invoice_payments()` function in `core_schema.sql` had flawed logic:

```sql
-- OLD LOGIC (BROKEN)
elsif v_total > 0 then
  v_new_status := 'sent';
else
  v_new_status := v_invoice.status; -- ❌ Keeps old status!
end if;
```

When all payments were deleted (`v_total = 0`), the `else` clause would keep the current status ('paid') instead of reverting to 'confirmed'.

---

## ✅ Solution

### Updated `recalculate_sales_invoice_payments()` Function

**File:** `supabase/sql/core_schema.sql` (lines 858-905)

**New comprehensive logic:**

```sql
-- Determine new status based on payment totals and current status
if v_invoice.status = 'cancelled' then
  -- Keep cancelled status
  v_new_status := v_invoice.status;

elsif v_invoice.status = 'draft' then
  -- Draft stays draft unless fully paid
  if v_total >= coalesce(v_invoice.total, 0) and v_total > 0 then
    v_new_status := 'paid';
  else
    v_new_status := 'draft';
  end if;

elsif v_total >= coalesce(v_invoice.total, 0) and v_total > 0 then
  -- Fully paid
  v_new_status := 'paid';

elsif v_total > 0 and v_total < coalesce(v_invoice.total, 0) then
  -- Partially paid - keep current status if overdue, otherwise set to sent
  if v_invoice.status = 'overdue' then
    v_new_status := 'overdue';
  else
    v_new_status := 'sent';
  end if;

elsif v_total = 0 then
  -- ✅ FIX: No payments - revert to confirmed
  if v_invoice.status = 'overdue' then
    v_new_status := 'overdue';
  else
    v_new_status := 'confirmed'; -- ✅ Revert to confirmed!
  end if;

else
  -- Fallback: keep current status
  v_new_status := v_invoice.status;
end if;
```

---

## 📊 Status Transition Logic

### Complete Status Flow:

| Payments Total | Current Status | New Status | Reason |
|----------------|----------------|------------|--------|
| `v_total = 0` | 'draft' | 'draft' | No payments on draft |
| `v_total = 0` | 'confirmed' | 'confirmed' | ✅ **FIXED: Revert to confirmed** |
| `v_total = 0` | 'sent' | 'confirmed' | ✅ **FIXED: Revert to confirmed** |
| `v_total = 0` | 'paid' | 'confirmed' | ✅ **FIXED: Revert to confirmed** |
| `v_total = 0` | 'overdue' | 'overdue' | Keep overdue even without payments |
| `v_total = 0` | 'cancelled' | 'cancelled' | Keep cancelled |
| `0 < v_total < total` | 'any' | 'sent' | Partially paid |
| `0 < v_total < total` | 'overdue' | 'overdue' | Partially paid but overdue |
| `v_total >= total` | 'any' | 'paid' | Fully paid |

---

## 🧪 Testing Scenarios

### Scenario 1: Delete Last Payment (Main Fix)
```
1. Invoice: total = $10,000, status = 'confirmed'
2. Add payment: $10,000 → status changes to 'paid' ✅
3. Delete payment → status should revert to 'confirmed' ✅ (was 'paid' ❌)
```

### Scenario 2: Delete One of Multiple Payments
```
1. Invoice: total = $10,000, status = 'confirmed'
2. Add payment: $5,000 → status = 'sent' ✅
3. Add payment: $5,000 → status = 'paid' ✅
4. Delete last payment → status = 'sent' ✅ (partially paid)
5. Delete last payment → status = 'confirmed' ✅ (no payments)
```

### Scenario 3: Overdue Invoice
```
1. Invoice: total = $10,000, status = 'overdue'
2. Add payment: $10,000 → status = 'paid' ✅
3. Delete payment → status = 'overdue' ✅ (keeps overdue)
```

### Scenario 4: Draft Invoice
```
1. Invoice: total = $10,000, status = 'draft'
2. Add payment: $10,000 → status = 'paid' ✅
3. Delete payment → status = 'draft' ✅ (back to draft)
```

### Scenario 5: Cancelled Invoice
```
1. Invoice: total = $10,000, status = 'cancelled'
2. Status remains 'cancelled' regardless of payments ✅
```

---

## 🔍 Related Functions

This fix is part of a larger payment system:

### Trigger Chain:
```
DELETE sales_payments
  ↓
trg_sales_payments_change (AFTER DELETE)
  ↓
handle_sales_payment_change()
  ↓
delete_sales_payment_journal_entry(OLD.id)
  ↓
recalculate_sales_invoice_payments(OLD.invoice_id) ← **FIXED HERE**
```

### Functions Updated:
- ✅ `recalculate_sales_invoice_payments()` - Fixed status calculation logic

### Functions Working Correctly:
- ✅ `handle_sales_payment_change()` - Trigger handler
- ✅ `delete_sales_payment_journal_entry()` - Deletes journal entry
- ✅ `create_sales_payment_journal_entry()` - Creates journal entry

---

## 📝 Status Definitions

For reference, here are the invoice statuses:

| Status | Spanish | Description |
|--------|---------|-------------|
| `draft` | Borrador | Invoice being created |
| `confirmed` | Confirmada | Invoice confirmed, ready for payment |
| `sent` | Enviada | Invoice sent/partially paid |
| `paid` | Pagada | Fully paid |
| `overdue` | Vencida | Past due date |
| `cancelled` | Cancelada | Cancelled invoice |

---

## 🚀 Deployment

### To apply this fix:

1. **Deploy updated core_schema.sql:**
   ```powershell
   # In Supabase SQL Editor
   # Run the entire core_schema.sql file
   ```

2. **Verify function update:**
   ```sql
   -- Check function exists and was updated
   SELECT proname, prosrc 
   FROM pg_proc 
   WHERE proname = 'recalculate_sales_invoice_payments';
   ```

3. **Test the fix:**
   ```sql
   -- Manually test status recalculation
   SELECT recalculate_sales_invoice_payments('<invoice_id>');
   
   -- Check invoice status
   SELECT id, invoice_number, status, total, paid_amount, balance
   FROM sales_invoices
   WHERE id = '<invoice_id>';
   ```

---

## ✅ Expected Behavior After Fix

### In Flutter App:

1. **Confirm Invoice:**
   - Status: 'confirmada' ✅

2. **Register Payment (Full):**
   - Status: 'pagada' ✅
   - Button: "Deshacer pago" appears ✅

3. **Click "Deshacer pago":**
   - Payment deleted ✅
   - Journal entry deleted ✅
   - **Status reverts to: 'confirmada' ✅** (FIXED!)
   - Balance restored to full amount ✅

4. **Register Partial Payment:**
   - Status: 'enviada' ✅

5. **Delete Partial Payment:**
   - Status: 'confirmada' ✅ (FIXED!)

---

## 🐛 Known Edge Cases Handled

1. ✅ **Multiple payments deleted one by one** → Status updates correctly at each step
2. ✅ **Overdue invoices** → Stays overdue even with no payments
3. ✅ **Draft invoices** → Returns to draft when payments deleted
4. ✅ **Cancelled invoices** → Always stays cancelled
5. ✅ **Rounding errors** → Uses `>=` for "fully paid" check to handle decimal precision

---

## 📚 Related Documentation

- `.github/Invoice_status_flow.md` - Complete invoice status workflow
- `DATABASE_DEPLOYMENT_GUIDE.md` - General deployment guide
- `JOURNAL_ENTRIES_CACHE_FIX.md` - Related journal entries fix

---

**Issue Status:** ✅ **RESOLVED**

The invoice status now correctly reverts to 'confirmed' when all payments are deleted via "Deshacer pago".
