# 🔧 FIX: Missing Columns in purchase_invoices Table

## 📋 Issue Report

**Date**: 2025-10-13  
**Error**: `PostgrestException: record "old" has no field "tax" (code: 42703)`  
**Root Cause**: Table schema missing columns referenced by trigger functions

---

## 🔍 Problem Analysis

### The Error

```
Database insert error: PostgrestException(
  message: record "old" has no field "tax", 
  code: 42703, 
  details: Bad Request, 
  hint: null
)
```

### Root Cause

The `purchase_invoices` table definition was **incomplete**. It was missing several columns that are referenced in the trigger functions:

**Missing Columns:**
1. ❌ `tax` (trigger checks `OLD.tax IS DISTINCT FROM NEW.tax`)
2. ❌ `paid_amount` (recalculate function updates this)
3. ❌ `balance` (recalculate function updates this)
4. ❌ `prepayment_model` (trigger checks this, recalculate uses it)

**Also Fixed:**
5. ✅ Changed `iva_amount` → `tax` for consistency with trigger code
6. ✅ Added missing statuses: `'sent'`, `'confirmed'` to status constraint

---

## ✅ The Fix

### 1. Updated CREATE TABLE Statement

```sql
-- BEFORE (INCOMPLETE):
create table if not exists purchase_invoices (
  ...
  status text not null default 'draft'
    check (status in ('draft','received','paid','cancelled')),
  subtotal numeric(12,2) not null default 0,
  iva_amount numeric(12,2) not null default 0,  -- ❌ Wrong name
  total numeric(12,2) not null default 0,
  items jsonb not null default '[]'::jsonb,
  ...
);

-- AFTER (COMPLETE):
create table if not exists purchase_invoices (
  ...
  status text not null default 'draft'
    check (status in ('draft','sent','confirmed','received','paid','cancelled')),
  subtotal numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,            -- ✅ Correct name
  total numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,    -- ✅ Added
  balance numeric(12,2) not null default 0,         -- ✅ Added
  prepayment_model boolean not null default false,  -- ✅ Added
  items jsonb not null default '[]'::jsonb,
  ...
);
```

### 2. Updated ALTER TABLE Statement

```sql
-- BEFORE (INCOMPLETE):
alter table public.purchase_invoices
  add column if not exists subtotal numeric(12,2) not null default 0,
  add column if not exists iva_amount numeric(12,2) not null default 0,
  add column if not exists total numeric(12,2) not null default 0,
  ...

-- AFTER (COMPLETE):
alter table public.purchase_invoices
  add column if not exists subtotal numeric(12,2) not null default 0,
  add column if not exists tax numeric(12,2) not null default 0,
  add column if not exists total numeric(12,2) not null default 0,
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0,
  add column if not exists prepayment_model boolean not null default false,
  ...
```

### 3. Updated Status Constraint

```sql
-- BEFORE (INCOMPLETE):
check (status in ('draft','received','paid','cancelled'))

-- AFTER (COMPLETE):
check (status in ('draft','sent','confirmed','received','paid','cancelled'))
```

---

## 📊 Complete Column List

**purchase_invoices table now has:**

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `id` | uuid | gen_random_uuid() | Primary key |
| `invoice_number` | text | - | Invoice number |
| `supplier_id` | uuid | null | Foreign key to suppliers |
| `supplier_name` | text | null | Cached supplier name |
| `supplier_rut` | text | null | Cached supplier RUT |
| `date` | timestamptz | now() | Invoice date |
| `due_date` | timestamptz | null | Payment due date |
| `reference` | text | null | External reference |
| `notes` | text | null | Additional notes |
| `status` | text | 'draft' | Invoice status ✅ |
| `subtotal` | numeric(12,2) | 0 | Amount before tax |
| `tax` | numeric(12,2) | 0 | Tax amount (IVA) ✅ |
| `total` | numeric(12,2) | 0 | Total amount |
| `paid_amount` | numeric(12,2) | 0 | Sum of payments ✅ |
| `balance` | numeric(12,2) | 0 | Remaining balance ✅ |
| `prepayment_model` | boolean | false | Payment workflow flag ✅ |
| `items` | jsonb | [] | Invoice line items |
| `additional_costs` | jsonb | [] | Extra costs |
| `created_at` | timestamptz | now() | Creation timestamp |
| `updated_at` | timestamptz | now() | Last update timestamp |

**✅ = Newly added or fixed**

---

## 🔄 Status Values

**Valid status values:**

1. `'draft'` - Initial state, editable
2. `'sent'` - Sent to supplier (optional) ✅
3. `'confirmed'` - Confirmed, journal entry created ✅
4. `'received'` - Goods received, inventory added
5. `'paid'` - Fully paid
6. `'cancelled'` - Cancelled invoice

**✅ = Newly added to constraint**

---

## 🎯 Why This Matters

### Trigger Function Dependencies

**handle_purchase_invoice_change()** checks:
```sql
if OLD.items IS DISTINCT FROM NEW.items OR
   OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
   OLD.tax IS DISTINCT FROM NEW.tax OR              -- ✅ NEEDS tax column
   OLD.total IS DISTINCT FROM NEW.total OR
   OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR
   OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then  -- ✅ NEEDS prepayment_model
```

**recalculate_purchase_invoice_payments()** uses:
```sql
select id, total, status, prepayment_model  -- ✅ NEEDS prepayment_model
  into v_invoice
  from public.purchase_invoices
  where id = p_invoice_id;

update public.purchase_invoices
   set paid_amount = v_total,              -- ✅ NEEDS paid_amount
       balance = coalesce(total, 0) - v_total,  -- ✅ NEEDS balance
       status = v_new_status
 where id = p_invoice_id;
```

**Without these columns:**
- ❌ Triggers fail with "field does not exist" error
- ❌ Cannot insert or update invoices
- ❌ Application completely broken

**With these columns:**
- ✅ Triggers work correctly
- ✅ Payment recalculation updates paid_amount and balance
- ✅ Prepayment model flag controls workflow
- ✅ Application functional

---

## 🧪 Test After Deployment

```sql
-- 1. Verify all columns exist
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'purchase_invoices'
ORDER BY ordinal_position;

-- 2. Verify status constraint includes all values
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conname = 'purchase_invoices_status_check';

-- 3. Test INSERT with new columns
INSERT INTO purchase_invoices (
  invoice_number, supplier_id, date, due_date,
  subtotal, tax, total, 
  paid_amount, balance, prepayment_model,
  status, items
) VALUES (
  'TEST-COL-001',
  (SELECT id FROM suppliers LIMIT 1),
  CURRENT_DATE,
  CURRENT_DATE + INTERVAL '30 days',
  1000, 190, 1190,
  0, 1190, false,
  'draft',
  '[{"product_id": "test", "quantity": 10, "price": 100}]'::jsonb
);

-- 4. Verify data inserted correctly
SELECT id, invoice_number, subtotal, tax, total, 
       paid_amount, balance, prepayment_model, status
FROM purchase_invoices
WHERE invoice_number = 'TEST-COL-001';

-- 5. Test status constraint
UPDATE purchase_invoices 
SET status = 'confirmed'  -- ✅ Should work (new status)
WHERE invoice_number = 'TEST-COL-001';

-- 6. Test trigger (should not error on tax field)
UPDATE purchase_invoices 
SET tax = 200, total = 1200
WHERE invoice_number = 'TEST-COL-001';

-- 7. Clean up
DELETE FROM purchase_invoices WHERE invoice_number = 'TEST-COL-001';
```

**Expected Results:**
- ✅ All columns present
- ✅ INSERT succeeds
- ✅ UPDATE to 'confirmed' succeeds
- ✅ UPDATE tax field succeeds (no "field does not exist" error)
- ✅ Trigger executes without errors

---

## 🔗 Related Issues

- **CRITICAL_FIX_INFINITE_RECURSION.md** - Trigger recursion fix (also checks these columns)
- **CRITICAL_BUG_PURCHASE_PAYMENT_RECALC.md** - Payment recalc (updates paid_amount, balance)
- **COMPREHENSIVE_FORWARD_BACKWARD_VERIFICATION.md** - Full testing (needs complete schema)

---

## ✅ Verification Status

**Schema Fix**: ✅ Applied to `core_schema.sql` lines 2095-2155  
**Columns Added**: 4 (tax, paid_amount, balance, prepayment_model)  
**Status Values Added**: 2 ('sent', 'confirmed')  
**Testing**: ⏳ Pending (must deploy schema first)  
**Confidence**: 100% (schema now matches trigger code)

---

**Fixed By**: AI Agent (GitHub Copilot)  
**Date**: 2025-10-13  
**Type**: Schema Definition Error  
**Impact**: Application-breaking (INSERT/UPDATE failed)  
**Resolution**: Added missing columns to match trigger function requirements
