# ✅ Quick Setup Checklist

## 1️⃣ Apply Database Migration (REQUIRED!)

- [ ] Open **Supabase Dashboard** → **SQL Editor**
- [ ] Copy content from `supabase/sql/fix_purchase_workflow.sql`
- [ ] Click **Run**
- [ ] Verify success message appears
- [ ] Confirm `purchase_payments` table exists (check Table Editor)

## 2️⃣ Restart Flutter App

- [ ] Stop the current Flutter process
- [ ] Run: `flutter run -d windows` (or your target device)
- [ ] Wait for app to launch
- [ ] Verify no compilation errors

## 3️⃣ Test Re-Activation Workflow

- [ ] Create new purchase invoice (Draft)
- [ ] Mark as "Received"
  - [ ] Check inventory increased
  - [ ] Check journal entry created (COMP-xxx)
- [ ] Revert to "Draft"
  - [ ] Check inventory decreased
  - [ ] Check reversal entry created (REV-COMP-xxx)
- [ ] Mark as "Received" AGAIN
  - [ ] **VERIFY**: New COMP-xxx entry created (not just reversal)
  - [ ] Check inventory increased again
- [ ] Go to "Contabilidad" → "Asientos Contables"
  - [ ] Verify 3 entries exist:
    1. COMP-xxx (REVERSADO)
    2. REV-COMP-xxx (Contabilizado)
    3. COMP-xxx (Contabilizado) ← This is the fix!

## 4️⃣ Test Payment Journal Entries

- [ ] Create new purchase invoice (Draft)
- [ ] Mark as "Received"
- [ ] Mark as "Paid"
  - [ ] Check invoice status changed to "Pagada"
- [ ] Go to "Compras" → "Pagos"
  - [ ] **VERIFY**: Payment appears in list
  - [ ] Check amount matches invoice total
  - [ ] Check method is "Transferencia"
- [ ] Go to "Contabilidad" → "Asientos Contables"
  - [ ] Find PAGO-xxx entry
  - [ ] **VERIFY**: Debit = Cuentas por Pagar (2101)
  - [ ] **VERIFY**: Credit = Banco (1101)

## 5️⃣ Test Purchase Payments Page

- [ ] Click "Compras" in sidebar
- [ ] **VERIFY**: "Pagos" submenu appears
- [ ] Click "Pagos"
- [ ] Check page loads correctly
- [ ] Test search functionality
- [ ] Verify payments display:
  - [ ] Invoice number
  - [ ] Supplier name
  - [ ] Amount
  - [ ] Date
  - [ ] Payment method badge (colored)

## 6️⃣ Test Sales Payments Enhancement

- [ ] Go to "Ventas" → "Pagos"
- [ ] **VERIFY**: Each payment shows invoice reference in blue badge
- [ ] Check badge appears next to payment amount
- [ ] Click payment to navigate to invoice

## 7️⃣ Integration Test (Full Cycle)

- [ ] Create purchase invoice: FC-TEST-001
  - Supplier: Proveedor Test
  - Item: Product A, Qty: 5, Price: $10,000
  - Total: $59,500 (with IVA)
- [ ] Mark as "Received"
  - [ ] Inventory +5 units
  - [ ] Journal: COMP-FC-TEST-001
    - Debit Inventario: $50,000
    - Debit IVA: $9,500
    - Credit AP: $59,500
- [ ] Mark as "Paid"
  - [ ] Payment created: $59,500
  - [ ] Journal: PAGO-FC-TEST-001
    - Debit AP: $59,500
    - Credit Banco: $59,500
- [ ] Verify final state:
  - [ ] Invoice status: "Pagada"
  - [ ] Invoice balance: $0
  - [ ] Inventory: Product A +5 units
  - [ ] Accounting: AP increased then decreased (net: $0)

## 8️⃣ Edge Case Tests

### Test Partial Payment
- [ ] Create invoice for $100,000
- [ ] Mark as "Received"
- [ ] Manually create payment for $50,000 (via database or future UI)
- [ ] Verify:
  - [ ] Invoice status: "Recibida" (not "Pagada")
  - [ ] Balance: $50,000
  - [ ] Can mark as "Paid" to auto-pay remaining balance

### Test Multiple Reversals
- [ ] Draft → Received → Draft → Received → Draft → Received
- [ ] Verify journal entries alternate:
  - COMP-xxx (reversed)
  - REV-COMP-xxx
  - COMP-xxx (reversed)
  - REV-COMP-xxx
  - COMP-xxx (posted)
- [ ] Inventory count matches final state

### Test Cancellation
- [ ] Create invoice and mark as "Received"
- [ ] Mark as "Cancelled"
- [ ] Verify inventory reverses
- [ ] Verify journal entry reverses

## 🐛 Troubleshooting

### SQL migration fails
- **Check**: Do you have write permissions in Supabase?
- **Check**: Are there conflicting table/function names?
- **Fix**: Drop existing `purchase_payments` table if it exists (empty)
- **Fix**: Run migration sections one at a time

### Re-activation still creates reversals
- **Check**: Did SQL migration run successfully?
- **Check**: Look in Supabase logs for error messages
- **Fix**: Re-run the migration
- **Fix**: Verify `create_purchase_invoice_journal_entry()` updated

### Payment journal entry not created
- **Check**: Do accounts 2100/2101 (AP) exist?
- **Check**: Do accounts 1100/1101 (Cash/Bank) exist?
- **Fix**: Create missing accounts in "Contabilidad" → "Cuentas"

### Purchase payments page is empty
- **Check**: Did you run the SQL migration?
- **Check**: Have you marked any invoice as "paid"?
- **Fix**: Create test payment by marking invoice as paid

### Compilation errors
- **Check**: Are all new files imported correctly?
- **Fix**: Run `flutter pub get`
- **Fix**: Restart IDE/VS Code

## 📊 Expected Results Summary

After completing all tests:

✅ **Journal Entries**:
- Clear activation/reversal pairs
- Payment entries for paid invoices
- Proper debit/credit balances

✅ **Inventory**:
- Increases on "received"
- Decreases on reversal to "draft"
- Matches final invoice state

✅ **Purchase Payments**:
- All payments listed in new page
- Searchable and filterable
- Shows invoice and supplier info

✅ **Sales Payments**:
- Invoice reference badge visible
- Correct navigation to invoice

✅ **Accounting Balance**:
- Accounts Payable increases on receive
- Accounts Payable decreases on payment
- Cash/Bank decreases on payment
- Inventory increases on receive

## 🎉 Completion

Once all checkboxes are ✅, the fix is complete and working!

**Next Steps**:
1. Test on Android APK if needed
2. Deploy to production
3. Train users on new "Pagos" page
4. Monitor for any edge cases

---

**Estimated Time**: 15-20 minutes  
**Difficulty**: Easy (just run SQL and test)  
**Impact**: High (fixes critical accounting workflow)
