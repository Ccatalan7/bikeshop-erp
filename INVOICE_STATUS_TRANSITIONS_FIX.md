# 🐛 Invoice Status Transitions Fix

## Problem: "Marcar como enviada" Changed Status to 'confirmed'

### 🚨 Symptom
When user clicked "Marcar como enviada" button on a draft invoice, the invoice status was being changed to `'confirmed'` instead of `'sent'`.

### 🔍 Root Cause
The `recalculate_sales_invoice_payments()` function in `core_schema.sql` (lines 903-913) had incorrect logic:

**BEFORE (BROKEN):**
```sql
elsif v_total = 0 then
  -- No payments - revert to confirmed (sent)
  -- Unless it's overdue, then keep overdue
  if v_invoice.status = 'overdue' then
    v_new_status := 'overdue';
  else
    v_new_status := 'confirmed';  -- ❌ WRONG! Forces to 'confirmed'
  end if;
```

**What happened:**
1. User clicks "Marcar como enviada" → Flutter calls `updateInvoiceStatus('sent')`
2. Database updates: `UPDATE sales_invoices SET status = 'sent'`
3. Trigger `trg_sales_invoices_change` fires → calls `handle_sales_invoice_change()`
4. That function calls `recalculate_sales_invoice_payments()` (line 1918)
5. Recalculate function sees `v_total = 0` (no payments yet)
6. **BUG:** Line 913 forces status to `'confirmed'` regardless of what was just set
7. Database updates AGAIN: `UPDATE sales_invoices SET status = 'confirmed'`
8. User sees status as 'confirmed' instead of 'sent' 🤦

### ✅ Solution
**AFTER (FIXED):**
```sql
elsif v_total = 0 then
  -- No payments
  if v_invoice.status = 'paid' then
    -- If was paid but now has no payments, revert to confirmed
    v_new_status := 'confirmed';  -- ✅ CORRECT! Revert paid → confirmed
  else
    -- Otherwise keep current status (draft/sent/confirmed/overdue)
    v_new_status := v_invoice.status;  -- ✅ CORRECT! Keep manual transitions
  end if;
```

**Also fixed partial payment logic:**
```sql
elsif v_total > 0 and v_total < coalesce(v_invoice.total, 0) then
  -- Partially paid - keep current status if it's overdue, otherwise set to confirmed
  if v_invoice.status = 'overdue' then
    v_new_status := 'overdue';
  else
    v_new_status := 'confirmed';  -- Changed from 'sent' to 'confirmed'
  end if;
```

### 📝 Complete Status Logic (AFTER FIX)

| Scenario | Current Status | Payment Amount | New Status | Reason |
|----------|---------------|----------------|------------|---------|
| Cancelled | cancelled | any | cancelled | Cancelled never changes |
| Draft with full payment | draft | >= total | paid | Exception: draft can go straight to paid |
| Draft with no/partial payment | draft | < total | draft | Draft stays draft until confirmed |
| No payments, was paid | **paid** | **0** | **confirmed** | ✅ **Revert to confirmed** (undo payment) |
| No payments, not paid | draft/sent/confirmed | 0 | **SAME** | ✅ **Keep current status** (manual transitions) |
| Fully paid | any | >= total | paid | Full payment → paid |
| Partially paid | overdue | 0 < amount < total | overdue | Keep overdue if already overdue |
| Partially paid | not overdue | 0 < amount < total | confirmed | Partial payment → confirmed (ready for tracking) |
| Other | any | any | **SAME** | Fallback: keep current |

### 🎯 Expected Flow (NOW WORKS CORRECTLY)

#### Forward Flow:
```
draft → [Marcar como enviada] → sent → [Confirmar] → confirmed → [Add Payment] → paid
```

#### Backward Flow:
```
paid → [Deshacer pago] → confirmed → [Volver a enviada] → sent → [Volver a borrador] → draft
```

### 🔬 Complete Logic Trace

#### FORWARD FLOW:
```
1. draft → sent (manual)
   - User clicks "Marcar como enviada"
   - v_total = 0, current = 'draft'
   - Logic: v_total = 0 AND status != 'paid' → keep status
   - But wait! Status was JUST CHANGED to 'sent' by the UPDATE
   - So: v_total = 0, current = 'sent'
   - Result: v_new_status = 'sent' ✅

2. sent → confirmed (manual)
   - User clicks "Confirmar"
   - v_total = 0, current = 'sent'
   - Logic: v_total = 0 AND status != 'paid' → keep status
   - Status was JUST CHANGED to 'confirmed' by the UPDATE
   - So: v_total = 0, current = 'confirmed'
   - Result: v_new_status = 'confirmed' ✅

3. confirmed → paid (payment trigger)
   - User adds payment (full amount)
   - v_total = invoice.total, current = 'confirmed'
   - Logic: v_total >= total AND v_total > 0 → paid
   - Result: v_new_status = 'paid' ✅
```

#### BACKWARD FLOW:
```
1. paid → confirmed (payment deletion)
   - User deletes payment ("Deshacer pago")
   - v_total = 0, current = 'paid'
   - Logic: v_total = 0 AND status = 'paid' → revert to 'confirmed'
   - Result: v_new_status = 'confirmed' ✅

2. confirmed → sent (manual)
   - User clicks "Volver a enviada"
   - v_total = 0, current = 'confirmed'
   - Status was JUST CHANGED to 'sent' by the UPDATE
   - Logic: v_total = 0 AND status != 'paid' → keep status
   - So: v_total = 0, current = 'sent'
   - Result: v_new_status = 'sent' ✅

3. sent → draft (manual)
   - User clicks "Volver a borrador"
   - v_total = 0, current = 'sent'
   - Status was JUST CHANGED to 'draft' by the UPDATE
   - Logic: v_invoice.status = 'draft' branch executes
   - v_total < total → v_new_status = 'draft'
   - Result: v_new_status = 'draft' ✅
```

#### PARTIAL PAYMENT SCENARIOS:
```
1. confirmed + partial payment
   - Current = 'confirmed', add payment (50% of total)
   - v_total > 0 AND v_total < total
   - Logic: status != 'overdue' → confirmed
   - Result: v_new_status = 'confirmed' ✅ (stays confirmed)

2. sent + partial payment
   - Current = 'sent', add payment (50% of total)
   - v_total > 0 AND v_total < total
   - Logic: status != 'overdue' → confirmed
   - Result: v_new_status = 'confirmed' ✅ (advances to confirmed)
```

### 🧪 Testing Checklist

**Test 1: Draft → Sent**
1. Create draft invoice
2. Click "Marcar como enviada"
3. ✅ Status should be **'sent'** (not 'confirmed')

**Test 2: Sent → Confirmed**
1. Invoice in 'sent' status
2. Click "Confirmar"
3. ✅ Status should be **'confirmed'**

**Test 3: Confirmed → Paid → Confirmed**
1. Invoice in 'confirmed' status
2. Add payment (full amount)
3. ✅ Status should be **'paid'**
4. Click "Deshacer pago"
5. ✅ Status should revert to **'confirmed'** (not 'sent' or 'draft')

**Test 4: Partial Payment**
1. Invoice in 'sent' status
2. Add partial payment (e.g., 50% of total)
3. ✅ Status should change to **'confirmed'** (not stay 'sent')
4. Add second payment to complete
5. ✅ Status should change to **'paid'**

**Test 5: Reverse Transitions**
1. Paid invoice → Undo payment → Should go to 'confirmed'
2. Confirmed invoice → "Volver a enviada" → Should go to 'sent'
3. Sent invoice → "Volver a borrador" → Should go to 'draft'

### 📁 Files Modified
- ✅ `supabase/sql/core_schema.sql` (lines 896-918)
  - Fixed `recalculate_sales_invoice_payments()` function
  - When `v_total = 0`: Keep current status instead of forcing 'confirmed'
  - When partially paid: Set to 'confirmed' instead of 'sent'

### 🚀 Deployment
```sql
-- Run updated core_schema.sql in Supabase SQL Editor
-- The function will be recreated with correct logic
```

### ⚠️ Related Issues Fixed Earlier
This is the SECOND fix to `recalculate_sales_invoice_payments()`:

1. **First fix** (INVOICE_STATUS_FIX.md): When undoing payment (`v_total = 0`), was keeping old status instead of reverting to 'confirmed'
2. **Second fix** (THIS FIX): When manually changing status with no payments, was forcing to 'confirmed' instead of respecting the new status

Both issues were in the same function but different logic branches!

### 🧠 Lesson Learned
**Never force status changes in recalculate functions!**
- `recalculate_sales_invoice_payments()` should ONLY change status when payments dictate it (paid, partially paid)
- When no payments exist, **respect the current status** (user might have manually transitioned draft→sent→confirmed)
- Only override status when payment amounts require it (e.g., full payment forces 'paid')

---

**Status:** ✅ FIXED (Ready for deployment and testing)
