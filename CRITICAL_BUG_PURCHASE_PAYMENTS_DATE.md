# 🚨 CRITICAL BUG #8: Missing `date` Column in purchase_payments Table

## 📋 Summary
**Severity**: 🔴 **CRITICAL** - Application crash when recording payments  
**Module**: Purchases → Payment Registration  
**Impact**: Unable to record any purchase payments  
**Status**: ✅ **FIXED**

---

## 🐛 The Problem

### User Error Message
```
Error al registrar pago: PostgrestException(message: Could not find the 'date' column of 'purchase_payments' in the schema cache, code: PGRST204, details: Bad Request, hint: null)
```

### Root Cause
The `purchase_payments` table definition in `core_schema.sql` includes a `date` column (line 2191):
```sql
date timestamp with time zone not null default now(),
```

However, there was **NO migration logic** to add this column if the table already exists in the database without it.

When Flutter tries to insert a payment with the `date` field:
```dart
'date': date.toIso8601String(),
```

Supabase returns an error because the column doesn't exist in the deployed database.

---

## 🔍 Discovery Process

1. **User reported**: "when I try to complete the payment it displays that error"
2. **Error analysis**: Supabase can't find 'date' column in purchase_payments table
3. **Schema check**: Column exists in CREATE TABLE statement (line 2191)
4. **Migration check**: No ALTER TABLE to add 'date' column if missing
5. **Conclusion**: Missing migration logic for existing tables

---

## ✅ The Fix

### Changes Made to `core_schema.sql`

**Added variable declaration** (line ~2203):
```sql
declare
  v_has_invoice_id boolean;
  v_has_old_invoice_id boolean;
  v_has_payment_method_id boolean;
  v_has_old_method boolean;
  v_has_date boolean;  -- NEW: Check if date column exists
  v_cash_method_id uuid;
```

**Added date column check** (line ~2233):
```sql
select exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'purchase_payments'
    and column_name = 'date'
) into v_has_date;

-- Add date column if missing
if not v_has_date then
  raise notice 'Adding date column to purchase_payments...';
  alter table purchase_payments add column date timestamp with time zone not null default now();
end if;
```

### How It Works
1. **Check**: Query information_schema to see if 'date' column exists
2. **Add if missing**: If column doesn't exist, add it with default value of now()
3. **Safe for new installations**: If column already exists, skip the ALTER TABLE
4. **Safe for upgrades**: If column missing in old database, it will be added

---

## 🧪 Testing Checklist

### After Deploying core_schema.sql

- [ ] **Test 1: New Payment on Standard Invoice**
  1. Create a standard purchase invoice (prepayment_model = false)
  2. Confirm the invoice (status → 'confirmed')
  3. Receive goods (status → 'received')
  4. Click "Registrar Pago" button
  5. Fill payment details (amount, method, reference)
  6. Click "Guardar Pago"
  7. **Expected**: Payment saved successfully, no date column error
  8. **Verify in database**: 
     ```sql
     SELECT id, invoice_id, amount, date, payment_method_id 
     FROM purchase_payments 
     ORDER BY created_at DESC 
     LIMIT 1;
     ```

- [ ] **Test 2: New Payment on Prepayment Invoice**
  1. Create a prepayment purchase invoice (prepayment_model = true)
  2. Confirm the invoice (status → 'confirmed')
  3. Click "Registrar Pago" button (payment BEFORE receiving goods)
  4. Fill payment details
  5. Click "Guardar Pago"
  6. **Expected**: Payment saved, status changes to 'paid'
  7. **Verify**: date column populated correctly

- [ ] **Test 3: Edit Existing Payment**
  1. Open an existing payment
  2. Change the payment date
  3. Click "Actualizar Pago"
  4. **Expected**: Update succeeds, date column updated
  5. **Verify**: No "date column not found" error

- [ ] **Test 4: Payment with Custom Date**
  1. Create new payment
  2. Change the payment date (click calendar icon)
  3. Select a different date
  4. Save payment
  5. **Expected**: Payment saved with correct custom date
  6. **Verify in database**: date field matches selected date

- [ ] **Test 5: Multiple Payments**
  1. Create invoice with total $100,000
  2. Add payment #1: $50,000 on 2025-10-14
  3. Add payment #2: $30,000 on 2025-10-15
  4. Add payment #3: $20,000 on 2025-10-16
  5. **Expected**: All payments saved with correct dates
  6. **Verify**: Payments list shows all dates correctly

---

## 🔄 Data Migration

### For Existing purchase_payments Records

If you have existing payments with missing dates, they will have `now()` as the default value after running the migration. If you need to correct these dates:

```sql
-- Find payments with default dates (likely incorrect)
SELECT id, invoice_id, amount, date, created_at
FROM purchase_payments
WHERE date = created_at  -- date was set to now() during migration
ORDER BY created_at DESC;

-- Manually update specific payment dates if needed
UPDATE purchase_payments
SET date = '2025-10-14 10:30:00-03'::timestamptz
WHERE id = 'payment-id-here';
```

---

## 📊 Impact Analysis

### Before Fix
- ❌ Unable to save any purchase payments
- ❌ "date column not found" error on payment form
- ❌ Prepayment workflow completely blocked
- ❌ Standard invoice payment workflow blocked
- ❌ Application unusable for recording supplier payments

### After Fix
- ✅ Payments save successfully with date field
- ✅ Prepayment workflow functional
- ✅ Standard invoice workflow functional
- ✅ Payment dates stored correctly in database
- ✅ Payment history displays dates correctly

---

## 🎓 Lessons Learned

1. **Migration completeness**: When adding columns to existing tables, ALWAYS include migration logic to handle existing installations
2. **Column existence checks**: Use information_schema queries to check if columns exist before ALTER TABLE
3. **Default values**: Provide sensible defaults (now() for timestamps) for new columns
4. **Testing coverage**: Test on both fresh installs AND upgrades from older schemas
5. **Error messages**: PostgreSQL PGRST204 errors indicate schema cache mismatches (column name mismatch or missing column)

---

## 🚀 Deployment Instructions

1. **Backup existing data**:
   ```sql
   -- Export purchase_payments before deployment
   COPY (SELECT * FROM purchase_payments) TO '/tmp/purchase_payments_backup.csv' CSV HEADER;
   ```

2. **Deploy updated core_schema.sql**:
   - Open Supabase Dashboard → SQL Editor
   - Copy entire `core_schema.sql` file
   - Paste and run
   - Watch for "Adding date column to purchase_payments..." message
   - Verify no errors

3. **Verify migration**:
   ```sql
   -- Check that date column exists
   SELECT column_name, data_type, is_nullable, column_default
   FROM information_schema.columns
   WHERE table_name = 'purchase_payments'
   ORDER BY ordinal_position;
   ```

4. **Test payment registration** (see checklist above)

5. **Monitor for errors**:
   ```sql
   -- Check recent payments have dates
   SELECT id, invoice_id, amount, date, created_at
   FROM purchase_payments
   ORDER BY created_at DESC
   LIMIT 10;
   ```

---

## 🔗 Related Issues

- **Bug #5**: Missing columns in purchase_invoices table (FIX_MISSING_PURCHASE_INVOICE_COLUMNS.md)
- **Bug #6**: Column name mismatch (iva_amount → tax) (FIX_PREPAYMENT_TAX_COLUMN_MAPPING.md)
- **Pattern**: Schema evolution requires migration logic for existing tables

---

**Fixed**: October 14, 2025  
**File Modified**: `supabase/sql/core_schema.sql` (lines ~2203, ~2233)  
**Testing Status**: ⏳ Awaiting deployment and user testing
