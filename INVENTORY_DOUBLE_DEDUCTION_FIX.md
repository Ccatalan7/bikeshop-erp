# 🐛 Fix: Inventory Double Deduction Bug

## Problem

When changing a sales invoice status from **"confirmed" → "sent"**, the inventory was being **deducted twice** instead of being restored.

**Expected behavior:**
- Draft → Sent: No inventory change ✅
- Sent → Confirmed: Deduct inventory ✅
- Confirmed → Sent: **Restore inventory** ✅
- Confirmed → Paid: No inventory change ✅

**Actual behavior:**
- Draft → Sent: No inventory change ✅
- Sent → Confirmed: Deduct inventory ✅
- Confirmed → Sent: **Deduct inventory AGAIN** ❌ (BUG!)

## Root Cause

The `consume_sales_invoice_inventory()` function had an incomplete list of "non-posted" statuses:

**BEFORE:**
```sql
-- Only skipped: draft, borrador, cancelled, cancelado
if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
  raise notice 'consume_sales_invoice_inventory: status is non-posted, skipping';
  return;
end if;
```

**Missing:** `'sent'`, `'enviado'`, `'enviada'`, `'issued'`, `'emitido'`, `'emitida'`

So when status changed to "sent", the function thought it was a "posted" status and deducted inventory!

## The Flow

### What happened (BUG):
1. User creates invoice in "draft" → inventory OK
2. User marks as "sent" → inventory OK (skipped)
3. User confirms invoice → inventory deducted ✅ (from 10 to 8)
4. User reverts to "sent" → trigger executes:
   - `restore_sales_invoice_inventory(OLD)` → adds back +2 ✅ (from 8 to 10)
   - Status changes to "sent"
   - `consume_sales_invoice_inventory(NEW)` → "sent" not in skip list!
   - Deducts -2 again ❌ (from 10 to 8)
5. **Result: Inventory is 8 instead of 10!**

### What should happen (FIXED):
1. User creates invoice in "draft" → inventory OK
2. User marks as "sent" → inventory OK (skipped)
3. User confirms invoice → inventory deducted ✅ (from 10 to 8)
4. User reverts to "sent" → trigger executes:
   - `restore_sales_invoice_inventory(OLD)` → adds back +2 ✅ (from 8 to 10)
   - Status changes to "sent"
   - `consume_sales_invoice_inventory(NEW)` → **"sent" IS in skip list!** ✅
   - Skips deduction ✅
5. **Result: Inventory is 10 (correct!)**

## Solution

Updated the `consume_sales_invoice_inventory()` function to include all "sent" variations in the skip list:

**AFTER:**
```sql
-- Now skips: draft, sent, cancelled
if v_status = any (array[
  'draft', 'borrador',
  'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida',  -- ⭐ ADDED
  'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
]) then
  raise notice 'consume_sales_invoice_inventory: status is non-posted, skipping';
  return;
end if;
```

## How to Apply

1. **Run the SQL migration:**
   ```bash
   # In Supabase SQL Editor, run:
   supabase/sql/fix_inventory_sent_status.sql
   ```

2. **Hot restart your app** (if running)

3. **Test the flow:**
   - Create invoice → Sent → Confirmed → Sent
   - Check inventory is restored correctly

## Testing Scenarios

### Test 1: Forward Flow
```
Draft (inv: 10) → Sent (inv: 10) → Confirmed (inv: 8) → Paid (inv: 8)
✅ Expected: 10 → 10 → 8 → 8
```

### Test 2: Backward Flow (The Bug)
```
Confirmed (inv: 8) → Sent (inv: should be 10)
✅ Expected: Inventory restored to 10
❌ Before fix: Inventory was 6 (deducted twice!)
```

### Test 3: Back and Forth
```
Draft → Sent → Confirmed (inv: 8) → Sent (inv: 10) → Confirmed (inv: 8)
✅ Expected: Each confirm deducts, each revert restores
```

## Related Files

- **Fix:** `supabase/sql/fix_inventory_sent_status.sql`
- **Original Function:** `supabase/sql/core_schema.sql:827` (consume_sales_invoice_inventory)
- **Trigger:** `supabase/sql/sales_workflow_redesign.sql:73` (handle_sales_invoice_change)

## Impact

- **High Priority:** This affected every invoice status change from confirmed→sent
- **Data Integrity:** Could cause inventory counts to become incorrect
- **Accounting:** Journal entries were handled correctly (DELETE on backward), only inventory was affected

## Verification

After applying the fix, you can verify it's working by checking the logs:

```sql
-- Enable logging to see the skips
SELECT * FROM pg_stat_activity WHERE query LIKE '%consume_sales%';
```

You should see:
```
consume_sales_invoice_inventory: invoice <uuid>, status sent
consume_sales_invoice_inventory: status is non-posted, skipping
```

---

**Status:** ✅ FIXED  
**Date:** October 11, 2025  
**Severity:** High (Data Integrity Issue)
