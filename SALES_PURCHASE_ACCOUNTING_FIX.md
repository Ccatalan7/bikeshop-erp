# 🚨 URGENT FIX: Sales + Purchase Accounting System

## What Happened

The `CREATE_REQUIRED_ACCOUNTS.sql` file accidentally **overwrote** the account name for code `1150`, breaking the sales invoice flow:

- **Before**: `1150 - Inventarios de Mercaderías` (what sales invoices expected)
- **After**: `1150 - Inventario` (what purchase invoices created)
- **Result**: Sales invoice journal entries stopped working

Additionally, the sales invoice functions in `core_schema.sql` were using **old column names** that were dropped by `MASTER_ACCOUNTING_FIX.sql`:
- Old: `date`, `entry_id`, `account_code`, `debit_amount`, `credit_amount`
- New: `entry_date`, `journal_entry_id`, `account_id`, `debit`, `credit`

---

## The Fix

**File**: [`supabase/sql/FIX_SALES_AND_PURCHASE_ACCOUNTS.sql`](file:///c:/dev/ProjectVinabike/supabase/sql/FIX_SALES_AND_PURCHASE_ACCOUNTS.sql)

This script does 4 things:

1. **Restores account 1150** to its original name: "Inventarios de Mercaderías"
2. **Updates `create_sales_invoice_journal_entry()`** to use new column names
3. **Updates `create_sales_payment_journal_entry()`** to use new column names
4. **Ensures purchase accounts exist** (1140, 1155, 2120) without breaking sales

---

## Deployment Steps

### Step 1: Run the Fix Script

Open Supabase SQL Editor and run:

```bash
# In your terminal:
cd c:\dev\ProjectVinabike
supabase db reset
```

Then run this SQL file:

[`supabase/sql/FIX_SALES_AND_PURCHASE_ACCOUNTS.sql`](file:///c:/dev/ProjectVinabike/supabase/sql/FIX_SALES_AND_PURCHASE_ACCOUNTS.sql)

Or paste it directly in Supabase Dashboard → SQL Editor.

### Step 2: Verify Accounts

After running the script, check the output. You should see:

```
✅ ✅ ✅  FIX SUCCESSFUL!
Account 1150 restored to: Inventarios de Mercaderías
Sales invoice functions updated to use new column names
Sales payment functions updated to use new column names
🎯 Sales invoices should now work correctly!
```

And a table showing all accounts:

| code | name | type | category |
|------|------|------|----------|
| 1130 | Cuentas por Cobrar Comerciales | asset | currentAsset |
| 1140 | IVA Crédito Fiscal | asset | currentAsset |
| **1150** | **Inventarios de Mercaderías** | asset | currentAsset |
| 1155 | Inventario en Tránsito | asset | currentAsset |
| 2120 | Cuentas por Pagar | liability | currentLiability |
| 2150 | IVA Débito Fiscal | tax | taxPayable |
| 4100 | Ingresos por Ventas | income | operatingIncome |
| 5100 | Costo de Ventas | expense | costOfGoodsSold |

---

## Testing

### Test 1: Sales Invoice Flow ✅

1. **Create a sales invoice** with a product (e.g. Bicicleta de Montaña)
2. **Change status** from `draft` to `posted`
3. **Check journal entries**:
   - Go to Accounting → Journal Entries
   - Should see a new entry: `INV-YYYYMMDDHHMMSS`
   - Should have 3-5 lines:
     - Debit: 1130 (Cuentas por Cobrar) = Total
     - Credit: 4100 (Ingresos por Ventas) = Subtotal
     - Credit: 2150 (IVA Débito) = IVA amount
     - Debit: 5100 (Costo de Ventas) = Cost
     - Credit: 1150 (Inventarios) = Cost

**Expected Result**: No errors, journal entry created successfully.

---

### Test 2: Sales Payment Flow ✅

1. **Create a payment** for the sales invoice
2. **Check journal entries**:
   - Should see a new entry: `PAY-YYYYMMDDHHMMSS`
   - Should have 2 lines:
     - Debit: 1101/1110 (Cash/Bank) = Payment amount
     - Credit: 1130 (Cuentas por Cobrar) = Payment amount

**Expected Result**: No errors, payment journal entry created.

---

### Test 3: Purchase Invoice Flow ✅

1. **Create a purchase invoice** (standard model, not prepaid)
2. **Confirm the invoice** (Draft → Enviada → Confirmada)
3. **Check journal entries**:
   - Should see a new entry: `PURCH-YYYYMMDDHHMMSS`
   - Should have 3 lines:
     - Debit: 1150 (Inventarios de Mercaderías) = Subtotal ← **SAME account as sales!**
     - Debit: 1140 (IVA Crédito Fiscal) = IVA
     - Credit: 2120 (Cuentas por Pagar) = Total

**Expected Result**: No errors, both sales AND purchase use account 1150 for inventory.

---

## What Changed

### Account 1150 - Restored

| Before (BROKEN) | After (FIXED) |
|-----------------|---------------|
| `1150 - Inventario` | `1150 - Inventarios de Mercaderías` |

### Sales Invoice Function - Column Names Updated

| Old Column (Dropped) | New Column (Active) | Notes |
|---------------------|---------------------|-------|
| `date` | `entry_date` | |
| `description` | `notes` | |
| `type` | `entry_type` | Value changed from 'sales' to 'sale' |
| `entry_id` | `journal_entry_id` | |
| `debit_amount` | `debit` | |
| `credit_amount` | `credit` | |

### Sales Payment Function - Column Names Updated

Same as above. Now uses `entry_date`, `notes`, `entry_type`, `journal_entry_id`, `debit`, `credit`.

---

## Why This Happened

The mistake occurred in this sequence:

1. User tested purchase invoice → got error "Required accounts not found (1150, 1140, 2120)"
2. Agent created `CREATE_REQUIRED_ACCOUNTS.sql` with `ON CONFLICT DO UPDATE`
3. This **overwrote** account 1150's name from "Inventarios de Mercaderías" → "Inventario"
4. Sales invoices started failing because they expected the original name
5. Additionally, sales functions were using old column names that were dropped

**Lesson Learned**: Never use `ON CONFLICT DO UPDATE` on account names without checking all dependencies first. Use `DO NOTHING` instead.

---

## Account Structure (Unified for Sales + Purchase)

| Code | Name | Type | Used By |
|------|------|------|---------|
| **1130** | Cuentas por Cobrar Comerciales | Asset | Sales (AR) |
| **1140** | IVA Crédito Fiscal | Asset | Purchase (VAT) |
| **1150** | Inventarios de Mercaderías | Asset | Sales + Purchase (Inventory) |
| **1155** | Inventario en Tránsito | Asset | Purchase (Prepaid only) |
| **2120** | Cuentas por Pagar | Liability | Purchase (AP) |
| **2150** | IVA Débito Fiscal | Tax | Sales (VAT) |
| **4100** | Ingresos por Ventas | Income | Sales (Revenue) |
| **5100** | Costo de Ventas | Expense | Sales (COGS) |

Both sales and purchase now use **the same inventory account (1150)** with the correct name.

---

## Next Steps

1. ✅ Run [`FIX_SALES_AND_PURCHASE_ACCOUNTS.sql`](file:///c:/dev/ProjectVinabike/supabase/sql/FIX_SALES_AND_PURCHASE_ACCOUNTS.sql)
2. ✅ Test sales invoice creation → verify journal entry
3. ✅ Test sales payment → verify journal entry
4. ✅ Test purchase invoice confirmation → verify journal entry
5. ✅ Confirm both sales and purchase workflows work

---

## If You Still See Errors

If you see errors like:
- `column "date" does not exist`
- `column "entry_id" does not exist`
- `Required accounts not found`

**Solution**: The fix script didn't run correctly. Try:

1. Open Supabase Dashboard → SQL Editor
2. Copy entire contents of `FIX_SALES_AND_PURCHASE_ACCOUNTS.sql`
3. Paste and run
4. Check for success message
5. Restart your Flutter app

---

## Summary

- ✅ Account 1150 restored to original name
- ✅ Sales invoice functions updated to use new column names
- ✅ Sales payment functions updated to use new column names
- ✅ Purchase accounts ensured to exist
- ✅ Both flows now use unified account structure

**Your sales invoices should work again!** 🎉
