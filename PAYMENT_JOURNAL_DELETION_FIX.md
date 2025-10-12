# 🔧 Payment Journal Entry Deletion Fix

## 🐛 Problem Description

When reverting a paid invoice back to confirmed status by deleting the payment:
- ✅ Payment record is deleted successfully
- ❌ Payment journal entry remains in the database (orphaned)

This causes inconsistency in the accounting module.

---

## 🎯 Root Cause

The `delete_sales_payment_journal_entry()` function was either:
1. Not properly configured with `SECURITY DEFINER` to bypass RLS
2. Not granted to the correct roles
3. The trigger wasn't firing correctly

---

## ✅ Solution Applied

### SQL Script: `fix_payment_journal_deletion_complete.sql`

This script:
1. ✅ Recreates `delete_sales_payment_journal_entry()` with `SECURITY DEFINER`
2. ✅ Grants execution to all relevant roles (authenticated, anon, service_role)
3. ✅ Recreates the `handle_sales_payment_change()` trigger function (now `SECURITY DEFINER` so it can bypass RLS)
4. ✅ Reinstalls the trigger `trg_sales_payments_change`
5. ✅ Cleans up any existing orphaned payment journal entries
6. ✅ Provides verification and diagnostic output

---

## 🚀 How to Deploy

### Step 1: Run the SQL Migration

```bash
# In Supabase Dashboard:
# 1. Go to SQL Editor
# 2. Open file: supabase/sql/fix_payment_journal_deletion_complete.sql
# 3. Click "Run"
```

**OR** via command line:
```bash
# If using Supabase CLI
supabase db reset
# OR apply just this migration
psql -h your-db-host -U postgres -d postgres -f supabase/sql/fix_payment_journal_deletion_complete.sql
```

### Step 2: Verify the Fix

Check the output logs for:
```
✅ Function delete_sales_payment_journal_entry exists
✅ Function has SECURITY DEFINER (bypasses RLS)
✅ Trigger trg_sales_payments_change exists
✅ All orphaned payment journal entries cleaned up
```

---

## 🧪 How to Test

### Test Scenario: Complete Payment Workflow

1. **Create and Confirm Invoice**
   - Navigate to `Ventas > Facturas`
   - Create new invoice with products
   - Mark as "Enviada"
   - Click "Confirmar" → Status = Confirmada
   - Verify journal entry created in `Contabilidad > Asientos Contables`

2. **Register Payment**
   - Open invoice detail page
   - Click "Pagar factura"
   - Enter payment details
   - Submit → Status = Pagada
   - Check `Contabilidad > Asientos Contables`
   - Should see TWO entries:
     - Sales invoice entry (INV-xxx)
     - Payment entry (PAGO-xxx)

3. **Delete Payment (Revert to Confirmed)**
   - On invoice detail page, click "Deshacer pago"
   - Confirm deletion
   - ✅ Status should return to "Confirmada"
   - ✅ Invoice balance should show unpaid amount
   - ✅ Payment record should be deleted from `sales_payments`
   - ✅ **Payment journal entry should be DELETED** from `journal_entries`

4. **Verify in Accounting Module**
   - Navigate to `Contabilidad > Asientos Contables`
   - Search for payment entry (PAGO-xxx)
   - **Expected Result**: Entry should NOT exist
   - Sales invoice entry (INV-xxx) should still exist

---

## 📊 What Happens Under the Hood

### When Payment is Created (Confirmed → Paid)
```sql
INSERT INTO sales_payments (...) 
  ↓
TRIGGER: handle_sales_payment_change() 
  ↓
FUNCTION: create_sales_payment_journal_entry()
  ↓
Journal Entry Created:
  Debit:  Banco/Caja (1100)         $119,000
  Credit: Cuentas por Cobrar (1130) $119,000
```

### When Payment is Deleted (Paid → Confirmed)
```sql
DELETE FROM sales_payments WHERE id = payment_id
  ↓
TRIGGER: handle_sales_payment_change() [TG_OP = 'DELETE']
  ↓
FUNCTION: delete_sales_payment_journal_entry(payment_id)
  ↓
DELETE FROM journal_lines WHERE entry_id = ...
DELETE FROM journal_entries WHERE source_reference = payment_id
  ↓
FUNCTION: recalculate_sales_invoice_payments()
  ↓
Invoice status: paid → confirmed
Invoice balance: $0 → $119,000
```

---

## 🔍 Diagnostic Queries

### Check for Orphaned Payment Journal Entries
```sql
SELECT 
  je.entry_number,
  je.description,
  je.date,
  je.total_debit,
  je.source_reference as missing_payment_id
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND NOT EXISTS (
    SELECT 1 FROM sales_payments sp 
    WHERE sp.id::text = je.source_reference
  );
```

### Check Function Configuration
```sql
SELECT 
  proname as function_name,
  prosecdef as is_security_definer,
  provolatile,
  proacl as permissions
FROM pg_proc
WHERE proname = 'delete_sales_payment_journal_entry';
```

### Check Trigger Configuration
```sql
SELECT 
  t.tgname AS trigger_name,
  c.relname AS table_name,
  p.proname AS function_name,
  pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE c.relname = 'sales_payments'
ORDER BY t.tgname;
```

---

## 🔄 Comparison: Sales vs Purchase Workflows

| Aspect | Sales Invoice | Purchase Invoice |
|--------|---------------|------------------|
| **Journal Entry on Status Change** | Deleted | Reversed (REV-xxx) |
| **Payment Journal Entry** | Deleted when payment removed | Reversed when payment removed |
| **Audit Trail** | Simpler (entries deleted) | Complete (reversals kept) |
| **Approach** | Zoho Books style | Traditional accounting |

Both are correct, just different philosophies!

---

## 🛠️ Troubleshooting

### Issue: Function not found error
**Solution**: Re-run the migration script

### Issue: Permission denied error
**Solution**: Check that you're running as postgres user or service_role

### Issue: Journal entry still not deleted
**Solution**: 
1. Check Supabase logs for RAISE NOTICE messages
2. Run diagnostic queries above
3. Verify RLS policies on journal_entries table
4. Check that SECURITY DEFINER is set on the function

### Issue: Trigger not firing
**Solution**: 
```sql
-- Verify trigger exists
SELECT * FROM pg_trigger WHERE tgname = 'trg_sales_payments_change';

-- Reinstall if needed
DROP TRIGGER IF EXISTS trg_sales_payments_change ON sales_payments;
CREATE TRIGGER trg_sales_payments_change
  AFTER INSERT OR UPDATE OR DELETE ON sales_payments
  FOR EACH ROW EXECUTE FUNCTION handle_sales_payment_change();
```

---

## 📝 Files Modified

- ✅ `supabase/sql/fix_payment_journal_deletion_complete.sql` (NEW)
- ✅ `PAYMENT_JOURNAL_DELETION_FIX.md` (NEW - This file)

---

## ✅ Checklist

- [ ] SQL migration script run successfully
- [ ] Verification queries show all green checkmarks
- [ ] Any orphaned entries cleaned up
- [ ] Test workflow completed successfully
- [ ] Payment journal entries are deleted when payments are removed
- [ ] Invoice status correctly returns to "Confirmada" after payment deletion

---

## 🎓 Key Learnings

1. **SECURITY DEFINER is critical** for functions that need to bypass RLS
2. **Proper grants** must be in place for authenticated, anon, and service_role
3. **Triggers must be reinstalled** after modifying the trigger function
4. **Orphaned records** should be cleaned up as part of the fix
5. **Diagnostic output** helps verify the fix was applied correctly

---

**Status**: ✅ Ready to deploy and test
**Impact**: 🟢 Low risk - only affects payment journal entry deletion
**Rollback**: Easy - revert to previous function definition if needed
