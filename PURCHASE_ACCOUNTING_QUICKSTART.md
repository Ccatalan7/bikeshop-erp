# 🚀 Quick Start - Purchase Invoice Accounting

## TL;DR

**What:** Purchase invoice accounting using simplified approach (no transit account)

**Files:** 
- `supabase/sql/FIX_PURCHASE_INVOICE_TRIGGERS.sql` (the SQL to run)
- `PURCHASE_ACCOUNTING_DEPLOYMENT.md` (detailed guide)
- `PURCHASE_ACCOUNTING_IMPLEMENTATION.md` (complete summary)

**Time:** 15 minutes

---

## ⚡ Quick Deploy

### 1. Run SQL (2 minutes)
```bash
# Open Supabase SQL Editor
# Copy entire FIX_PURCHASE_INVOICE_TRIGGERS.sql
# Click RUN
# Look for: ✅ ✅ ✅ PURCHASE TRIGGERS CREATED!
```

### 2. Quick Test (5 minutes)
```bash
# Create purchase invoice
# Set status → Confirmada
# Check journal entries:
```

```sql
SELECT je.entry_number, je.entry_type, a.code, a.name, jl.debit, jl.credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_entry_id = je.id
JOIN accounts a ON a.id = jl.account_id
WHERE je.source_module = 'purchase_invoices'
ORDER BY je.created_at DESC
LIMIT 10;
```

**Expected:**
- ✅ Entry type = 'purchase'
- ✅ DR 1150 (Inventarios)
- ✅ DR 1140 (IVA Crédito)
- ✅ CR 2120 (Cuentas por Pagar)

### 3. Test Payment (3 minutes)
```bash
# Register payment (Cash)
# Check payment journal:
```

```sql
SELECT je.entry_number, a.code, a.name, jl.debit, jl.credit
FROM journal_entries je
JOIN journal_lines jl ON jl.journal_entry_id = je.id
JOIN accounts a ON a.id = jl.account_id
WHERE je.source_module = 'purchase_payments'
ORDER BY je.created_at DESC
LIMIT 10;
```

**Expected:**
- ✅ Entry type = 'payment'
- ✅ DR 2120 (Cuentas por Pagar)
- ✅ CR 1101 (Caja) if cash OR CR 1110 (Bancos) if bank

### 4. Test Reversal (2 minutes)
```bash
# Click "Deshacer Pago"
# Run this query:
```

```sql
SELECT COUNT(*) FROM journal_entries
WHERE source_module = 'purchase_payments';
-- Expected: 0 (entry deleted, not reversed!)
```

---

## ✅ Success Indicators

**Working:**
- ✅ Invoice confirmed → journal entry created
- ✅ Payment registered → payment entry created
- ✅ "Deshacer pago" → payment entry deleted
- ✅ Revert to Enviada → invoice entry deleted
- ✅ Account 1150 used (NOT 1155!)
- ✅ Sales invoices still work

**Not Working (Common Issues):**

❌ **Error: column "date" does not exist**
→ Run MASTER_ACCOUNTING_FIX.sql first

❌ **Account 1150 name is "Inventario"**
→ Run FIX_SALES_AND_PURCHASE_ACCOUNTS.sql first

❌ **Sales invoices broken**
→ You deployed before fixing account 1150 name - rollback and fix!

❌ **Journal entry uses account 1155**
→ You're running old version - use FIX_PURCHASE_INVOICE_TRIGGERS.sql

---

## 📊 Account Cheat Sheet

| Code | Name | Purchase DR/CR |
|------|------|----------------|
| 1150 | Inventarios de Mercaderías | **DR** (increases inventory) |
| 1140 | IVA Crédito Fiscal | **DR** (IVA recoverable) |
| 2120 | Cuentas por Pagar | **CR** (liability increases) |
| 1101 | Caja General | **CR** when pay with cash |
| 1110 | Bancos | **CR** when pay with bank |

**For comparison (Sales):**
- 1150: **CR** (decreases inventory)
- 2150: **CR** (IVA payable)
- 1120: **DR** (receivable increases)

---

## 🔄 Workflow Models

**Both use SAME accounting!**

### Standard (pay after receive)
```
Borrador → Enviada → Confirmada → Recibida → Pagada
                     ↓ journal               ↓ payment
```

### Prepayment (pay before receive)
```
Borrador → Enviada → Confirmada → Pagada → Recibida
                     ↓ journal   ↓ payment
```

---

## 🆘 Emergency Rollback

```sql
DROP FUNCTION IF EXISTS create_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS delete_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS create_purchase_payment_journal_entry(UUID);
DROP FUNCTION IF EXISTS delete_purchase_payment_journal_entry(UUID);

DELETE FROM journal_entries
WHERE source_module IN ('purchase_invoices', 'purchase_payments');
```

---

## 📚 Full Documentation

- **Deployment:** PURCHASE_ACCOUNTING_DEPLOYMENT.md
- **Implementation:** PURCHASE_ACCOUNTING_IMPLEMENTATION.md
- **Sales Fix:** FIX_SALES_AND_PURCHASE_ACCOUNTS.sql

---

**Ready?** → Open `PURCHASE_ACCOUNTING_DEPLOYMENT.md` for detailed guide 🚀
