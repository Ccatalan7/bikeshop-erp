# 🚀 Database Deployment Guide - Payment Methods Migration

**Date:** October 13, 2025  
**Issue:** Migrating from hardcoded payment methods to dynamic `payment_methods` table

---

## 🎯 Problem Summary

Your existing database has:
- ❌ `sales_payments.method` (text) - OLD column
- ❌ `purchase_payments.payment_method` or `purchase_payments.method` (text) - OLD column
- ❌ `purchase_payments.purchase_invoice_id` - OLD column name

New schema requires:
- ✅ `sales_payments.payment_method_id` (uuid) - NEW column
- ✅ `purchase_payments.payment_method_id` (uuid) - NEW column
- ✅ `purchase_payments.invoice_id` (uuid) - NEW column name

**Recent Fixes:**
- ✅ Fixed migration function output (changed `select` to silent `perform` in DO block)
- ✅ Migration blocks now execute silently without console output

---

## 📋 Deployment Options

### **Option 1: Fresh Database (Recommended if possible)**

If you can reset your database without losing important data:

```powershell
# In Supabase Dashboard → SQL Editor
# Just run core_schema.sql
# It now has proper migration blocks that run BEFORE indexes
```

✅ Simplest approach  
✅ No data migration needed  
✅ Clean slate  

---

### **Option 2: Existing Database with Data (Most Common)**

If you have existing data that must be preserved:

#### **Step 1: Run FIX_payment_method_migration.sql**

```sql
-- Copy entire contents of:
-- supabase/sql/FIX_payment_method_migration.sql
-- Paste into Supabase SQL Editor and run
```

**What it does:**
1. ✅ Adds `payment_method_id` to `sales_payments`
2. ✅ Migrates old `method` data to new `payment_method_id`
3. ✅ Fixes `purchase_payments.purchase_invoice_id` → `invoice_id`
4. ✅ Adds `payment_method_id` to `purchase_payments`
5. ✅ Creates all necessary indexes
6. ✅ Cleans up old columns

#### **Step 2: Verify Migration Succeeded**

```sql
-- Check sales_payments structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'sales_payments'
  AND column_name IN ('method', 'payment_method_id')
ORDER BY column_name;

-- Expected: Only payment_method_id should appear
-- method column should be gone

-- Check purchase_payments structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'purchase_payments'
  AND column_name IN ('purchase_invoice_id', 'invoice_id', 'method', 'payment_method', 'payment_method_id')
ORDER BY column_name;

-- Expected: 
-- invoice_id (uuid, NO)
-- payment_method_id (uuid, NO)
-- Old columns should be gone

-- Verify payment methods exist
SELECT code, name, is_active FROM payment_methods ORDER BY sort_order;

-- Expected: 4 rows (cash, transfer, card, check)
```

#### **Step 3: Run core_schema.sql**

```sql
-- Copy entire contents of:
-- supabase/sql/core_schema.sql
-- Paste into Supabase SQL Editor and run
```

The migration blocks will detect that columns already exist and skip them.

---

## ⚠️ Common Errors and Solutions

### **Error: "column payment_method_id does not exist"**

**Cause:** Index creation attempted before column migration

**Solution:** 
- Make sure you run FIX script first (Option 2)
- OR use updated core_schema.sql which has migration blocks BEFORE indexes

### **Error: "column invoice_id does not exist"**

**Cause:** `purchase_payments` has old column name `purchase_invoice_id`

**Solution:** 
- Run FIX script which renames it
- OR update your existing purchase_payments manually:

```sql
ALTER TABLE purchase_payments RENAME COLUMN purchase_invoice_id TO invoice_id;
```

### **Error: "relation payment_methods does not exist"**

**Cause:** Running scripts out of order

**Solution:** 
- Ensure `payment_methods` table section runs first in core_schema.sql
- Check if accounts table exists (payment_methods needs it)

### **Error: "Cash payment method not found"**

**Cause:** Payment methods seed data didn't run

**Solution:**
```sql
-- Manually insert payment methods
INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'cash', 'Efectivo', id, false, 'cash', 1
FROM accounts WHERE code = '1101'
ON CONFLICT (code) DO NOTHING;

INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'transfer', 'Transferencia Bancaria', id, true, 'bank', 2
FROM accounts WHERE code = '1110'
ON CONFLICT (code) DO NOTHING;

INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'card', 'Tarjeta de Débito/Crédito', id, false, 'credit_card', 3
FROM accounts WHERE code = '1110'
ON CONFLICT (code) DO NOTHING;

INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'check', 'Cheque', id, true, 'receipt', 4
FROM accounts WHERE code = '1110'
ON CONFLICT (code) DO NOTHING;
```

---

## ✅ Final Verification Checklist

Run these queries to confirm everything is correct:

```sql
-- 1. Check payment_methods table
SELECT * FROM payment_methods WHERE is_active = true ORDER BY sort_order;
-- Expected: 4 rows

-- 2. Check sales_payments structure
\d sales_payments
-- Should have: invoice_id, payment_method_id (uuid)
-- Should NOT have: method

-- 3. Check purchase_payments structure
\d purchase_payments
-- Should have: invoice_id, payment_method_id (uuid)
-- Should NOT have: purchase_invoice_id, method, payment_method

-- 4. Check indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename IN ('sales_payments', 'purchase_payments')
  AND indexname LIKE '%payment_method%'
ORDER BY tablename, indexname;
-- Expected: 2 indexes (one per table)

-- 5. Test a join query
SELECT 
  sp.id,
  sp.amount,
  pm.name as payment_method,
  pm.requires_reference
FROM sales_payments sp
LEFT JOIN payment_methods pm ON pm.id = sp.payment_method_id
LIMIT 5;
-- Should work without errors

-- 6. Check foreign key constraints
SELECT
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name IN ('sales_payments', 'purchase_payments')
  AND kcu.column_name LIKE '%payment_method%'
ORDER BY tc.table_name;
-- Expected: Both tables should have FK to payment_methods(id)
```

---

## 🧪 Testing After Deployment

### **Test 1: Create a Sale Payment**

```sql
-- Get a sales invoice ID
SELECT id, invoice_number, balance 
FROM sales_invoices 
WHERE balance > 0 
LIMIT 1;

-- Get cash payment method ID
SELECT id, name FROM payment_methods WHERE code = 'cash';

-- Create a test payment
INSERT INTO sales_payments (invoice_id, payment_method_id, amount, date)
VALUES (
  '<invoice_id_from_above>',
  '<cash_method_id_from_above>',
  1000.00,
  NOW()
);

-- Verify it worked
SELECT 
  sp.*,
  pm.name as payment_method_name
FROM sales_payments sp
JOIN payment_methods pm ON pm.id = sp.payment_method_id
ORDER BY sp.created_at DESC
LIMIT 1;
```

### **Test 2: Verify Triggers Work**

```sql
-- The payment should have created a journal entry automatically
SELECT 
  je.entry_number,
  je.description,
  je.total_debit,
  je.total_credit
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
ORDER BY je.created_at DESC
LIMIT 1;

-- Check the journal lines
SELECT 
  jl.account_code,
  jl.account_name,
  jl.debit_amount,
  jl.credit_amount
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
WHERE je.source_module = 'sales_payments'
ORDER BY je.created_at DESC, jl.debit_amount DESC
LIMIT 5;

-- Expected:
-- DR: 1101 Caja (for cash payment)
-- CR: 1130 Cuentas por Cobrar
```

---

## 🎯 Quick Decision Tree

```
Do you have existing data in sales_payments or purchase_payments?
│
├─ NO (Fresh database)
│  └─> Just run core_schema.sql
│     └─> ✅ Done!
│
└─ YES (Existing data)
   └─> Run FIX_payment_method_migration.sql first
       ├─> Check verification queries
       ├─> Then run core_schema.sql
       └─> ✅ Done!
```

---

## 📞 Troubleshooting Checklist

If Flutter app shows "No hay métodos de pago disponibles":

- [ ] Verified `payment_methods` table exists
- [ ] Verified 4 payment methods are inserted and `is_active = true`
- [ ] Verified accounts table has entries for codes: 1101, 1110
- [ ] Verified PaymentMethodService is registered in main.dart
- [ ] Restarted Flutter app after database changes
- [ ] Checked Flutter console for error messages

If payment registration fails:

- [ ] Verified `sales_payments.payment_method_id` column exists (uuid type)
- [ ] Verified foreign key constraint exists
- [ ] Verified trigger `trg_sales_payments_change` exists
- [ ] Verified function `handle_sales_payment_change()` exists
- [ ] Checked Supabase logs for backend errors

---

## 📚 Files Reference

1. **core_schema.sql** - Main schema with migration blocks (UPDATED)
2. **FIX_payment_method_migration.sql** - Standalone migration script (NEW)
3. **FLUTTER_PROGRESS_REPORT.md** - Flutter code changes summary
4. **DATABASE_DEPLOYMENT_GUIDE.md** - This file

---

**Good luck with deployment! 🚀**

If you encounter any errors not covered here, share the exact error message and the step where it occurred.
