# 🚀 Purchase Invoice Accounting - Deployment Guide

## ✅ What This Fixes

This deploys the **simplified purchase invoice accounting** with:
- ✅ Uses account **1150 (Inventarios de Mercaderías)** for ALL inventory (no transit account!)
- ✅ Same accounting for both Standard and Prepayment models
- ✅ Properly creates journal entries using NEW column names
- ✅ Implements DELETE-based reversals (not reversal entries)
- ✅ Handles payment journal entries with proper Cash/Bank selection

---

## 📋 Pre-Deployment Checklist

1. **Sales invoice flow is working** ✅
   - User confirmed: "now is fixed"
   - Payment reversal ("Deshacer pago") works correctly

2. **Account 1150 name is correct** ✅
   - Name: "Inventarios de Mercaderías" (not "Inventario")
   - Verified in FIX_SALES_AND_PURCHASE_ACCOUNTS.sql

3. **Database schema uses NEW columns** ✅
   - journal_entries: `entry_date`, `entry_type`, `notes`
   - journal_lines: `journal_entry_id`, `debit`, `credit`

---

## 🎯 Deployment Steps

### Step 1: Run the SQL Script

1. Open Supabase SQL Editor
2. Copy and paste **entire contents** of: `supabase/sql/FIX_PURCHASE_INVOICE_TRIGGERS.sql`
3. Click **RUN**
4. Verify success messages:
   ```
   ✅ ✅ ✅  PURCHASE TRIGGERS CREATED!
   Functions created:
     ✅ create_purchase_invoice_journal_entry()
     ✅ delete_purchase_invoice_journal_entry()
     ✅ create_purchase_payment_journal_entry()
     ✅ delete_purchase_payment_journal_entry()
   ```

---

## 🧪 Testing Scenarios

### Test 1: Create and Confirm Purchase Invoice

**Steps:**
1. Create new purchase invoice (Borrador)
2. Add products (e.g., 5 units @ $10,000 each)
3. Set status → **Confirmada**

**Expected Results:**
- ✅ Journal entry created with entry_type = 'purchase'
- ✅ Journal lines:
  - DR: 1150 (Inventarios) = $50,000
  - DR: 1140 (IVA Crédito) = $9,500 (19%)
  - CR: 2120 (Cuentas por Pagar) = $59,500
- ✅ Inventory increased by 5 units

**Verification Query:**
```sql
SELECT 
  je.entry_number,
  je.entry_date,
  je.notes,
  je.entry_type,
  a.code,
  a.name,
  jl.debit,
  jl.credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_entry_id = je.id
JOIN accounts a ON a.id = jl.account_id
WHERE je.source_module = 'purchase_invoices'
  AND je.source_reference = '<your-invoice-id>'
ORDER BY jl.debit DESC;
```

**Expected Output:**
| code | name | debit | credit |
|------|------|-------|--------|
| 1150 | Inventarios de Mercaderías | 50000 | 0 |
| 1140 | IVA Crédito Fiscal | 9500 | 0 |
| 2120 | Cuentas por Pagar | 0 | 59500 |

---

### Test 2: Register Payment

**Steps:**
1. With invoice in status **Confirmada**
2. Click "Registrar Pago"
3. Amount: $59,500
4. Method: **Efectivo (cash)**

**Expected Results:**
- ✅ Payment journal entry created with entry_type = 'payment'
- ✅ Journal lines:
  - DR: 2120 (Cuentas por Pagar) = $59,500
  - CR: 1101 (Caja General) = $59,500
- ✅ Invoice status → **Pagada**

**Verification Query:**
```sql
SELECT 
  je.entry_number,
  je.entry_date,
  je.notes,
  je.entry_type,
  a.code,
  a.name,
  jl.debit,
  jl.credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_entry_id = je.id
JOIN accounts a ON a.id = jl.account_id
WHERE je.source_module = 'purchase_payments'
  AND je.source_reference = '<your-payment-id>'
ORDER BY jl.debit DESC;
```

**Expected Output:**
| code | name | debit | credit |
|------|------|-------|--------|
| 2120 | Cuentas por Pagar | 59500 | 0 |
| 1101 | Caja General | 0 | 59500 |

---

### Test 3: Payment with Bank Transfer

**Steps:**
1. Create another purchase invoice
2. Confirm invoice
3. Register payment with method: **Transferencia (transfer)**

**Expected Results:**
- ✅ Payment journal entry uses account **1110 (Bancos)** instead of 1101
- ✅ Journal lines:
  - DR: 2120 (Cuentas por Pagar)
  - CR: 1110 (Bancos - Cuenta Corriente)

---

### Test 4: Undo Payment

**Steps:**
1. With invoice in status **Pagada**
2. Click "Deshacer Pago"

**Expected Results:**
- ✅ Payment journal entry **DELETED** (not reversed!)
- ✅ Invoice status → **Confirmada** (or **Recibida** if Standard model)
- ✅ Accounts Payable balance restored

**Verification Query:**
```sql
SELECT COUNT(*) as payment_entries
FROM journal_entries
WHERE source_module = 'purchase_payments'
  AND source_reference = '<your-payment-id>';
-- Expected: 0
```

---

### Test 5: Revert Invoice to Sent

**Steps:**
1. With invoice in status **Confirmada** (must have no payment)
2. Change status → **Enviada**

**Expected Results:**
- ✅ Invoice journal entry **DELETED**
- ✅ Inventory decreased (reversed)
- ✅ No orphaned journal entries

**Verification Query:**
```sql
SELECT COUNT(*) as invoice_entries
FROM journal_entries
WHERE source_module = 'purchase_invoices'
  AND source_reference = '<your-invoice-id>';
-- Expected: 0
```

---

## 🔍 Account Structure Verification

Run this query to confirm all required accounts exist:

```sql
SELECT code, name, type, category
FROM accounts
WHERE code IN ('1150', '1140', '2120', '1101', '1110')
ORDER BY code;
```

**Expected Output:**
| code | name | type | category |
|------|------|------|----------|
| 1101 | Caja General | asset | currentAsset |
| 1110 | Bancos - Cuenta Corriente | asset | currentAsset |
| 1140 | IVA Crédito Fiscal | asset | currentAsset |
| 1150 | Inventarios de Mercaderías | asset | currentAsset |
| 2120 | Cuentas por Pagar | liability | currentLiability |

**❌ If account 1150 name is "Inventario":**
- Run FIX_SALES_AND_PURCHASE_ACCOUNTS.sql first!
- This was the original bug that broke sales invoices

---

## 🎯 Key Differences from Sales Flow

| Aspect | Sales Invoice | Purchase Invoice |
|--------|---------------|------------------|
| **Entry Type** | 'sale' | 'purchase' |
| **Inventory** | Decreases (CR 1150) | Increases (DR 1150) |
| **Revenue/Expense** | CR 4100 (Ingresos) | DR 1150 (direct to inventory) |
| **Receivable/Payable** | DR 1120 (AR) | CR 2120 (AP) |
| **VAT** | CR 2150 (IVA Débito) | DR 1140 (IVA Crédito) |
| **Payment** | Increases Cash/Bank | Decreases Cash/Bank |
| **COGS** | DR 5100 (cost) | N/A (cost in 1150) |

---

## ⚠️ Common Issues & Solutions

### Issue 1: Function Already Exists Error
**Symptom:** `ERROR: function "create_purchase_invoice_journal_entry" already exists`

**Solution:** Script uses `CREATE OR REPLACE`, so this should not happen. If it does:
```sql
DROP FUNCTION IF EXISTS create_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS delete_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS create_purchase_payment_journal_entry(UUID);
DROP FUNCTION IF EXISTS delete_purchase_payment_journal_entry(UUID);
```
Then re-run FIX_PURCHASE_INVOICE_TRIGGERS.sql

---

### Issue 2: Column "date" Does Not Exist
**Symptom:** `ERROR: column "date" does not exist`

**Solution:** Your schema still uses OLD column names. Run MASTER_ACCOUNTING_FIX.sql first to update schema.

---

### Issue 3: Account 1150 Name Wrong
**Symptom:** Journal entries work but sales invoices broken

**Solution:** Run FIX_SALES_AND_PURCHASE_ACCOUNTS.sql to restore account 1150 name.

---

### Issue 4: Inventory Not Increasing
**Symptom:** Journal entry created but stock quantity unchanged

**Solution:** Check if `consume_purchase_invoice_inventory()` function exists and is called by trigger.

---

## 📊 Post-Deployment Validation

Run this comprehensive check:

```sql
-- 1. Verify functions exist
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name LIKE '%purchase%journal%'
ORDER BY routine_name;

-- Expected:
-- create_purchase_invoice_journal_entry
-- create_purchase_payment_journal_entry
-- delete_purchase_invoice_journal_entry
-- delete_purchase_payment_journal_entry

-- 2. Check for existing journal entries
SELECT 
  source_module,
  COUNT(*) as entry_count,
  SUM(total_debit) as total_debit,
  SUM(total_credit) as total_credit
FROM journal_entries
WHERE source_module IN ('purchase_invoices', 'purchase_payments')
GROUP BY source_module;

-- 3. Verify account balances
SELECT 
  a.code,
  a.name,
  SUM(jl.debit) as total_debit,
  SUM(jl.credit) as total_credit,
  SUM(jl.debit - jl.credit) as balance
FROM journal_lines jl
JOIN accounts a ON a.id = jl.account_id
WHERE a.code IN ('1150', '1140', '2120', '1101', '1110')
GROUP BY a.code, a.name
ORDER BY a.code;
```

---

## ✅ Success Criteria

- [ ] All 4 functions created without errors
- [ ] Test purchase invoice → journal entry created
- [ ] Journal entry uses account 1150 (not 1155!)
- [ ] Payment → journal entry created with correct Cash/Bank account
- [ ] "Deshacer pago" → payment journal entry deleted
- [ ] Reverting to Enviada → invoice journal entry deleted
- [ ] Both Standard and Prepayment models work identically
- [ ] Sales invoice flow still works (account 1150 shared correctly)

---

## 🎉 Next Steps

After successful deployment:

1. **Update Flutter UI** (if needed):
   - Ensure purchase invoice status transitions call Supabase updates
   - Verify payment registration sends correct payment_method
   - Add "Deshacer Pago" button if not present

2. **Test Both Models**:
   - Standard: Borrador → Enviada → Confirmada → Recibida → Pagada
   - Prepayment: Borrador → Enviada → Confirmada → Pagada → Recibida

3. **Monitor Journal Entries**:
   - Check Accounting module for correct entries
   - Verify account balances update correctly
   - Test filtering by source_module = 'purchase_invoices'

4. **Document Final Workflow**:
   - Update Purchase_Invoice_status_flow.md if needed
   - Add screenshots of journal entries
   - Create user guide for purchase accounting

---

## 📝 Rollback Plan

If something goes wrong:

```sql
-- 1. Drop all purchase invoice functions
DROP FUNCTION IF EXISTS create_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS delete_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS create_purchase_payment_journal_entry(UUID);
DROP FUNCTION IF EXISTS delete_purchase_payment_journal_entry(UUID);

-- 2. Delete all purchase journal entries (if needed)
DELETE FROM journal_entries
WHERE source_module IN ('purchase_invoices', 'purchase_payments');

-- 3. Re-run FIX_SALES_AND_PURCHASE_ACCOUNTS.sql to ensure sales still works
```

---

**💡 Remember:**
- This is a **simplified approach** - no transit account complexity!
- Both purchase models use **SAME accounting** - only workflow timing differs
- Account 1150 is **SHARED** with sales - handle with care!
- Use **DELETE-based reversals**, not reversal journal entries

Good luck! 🚀
