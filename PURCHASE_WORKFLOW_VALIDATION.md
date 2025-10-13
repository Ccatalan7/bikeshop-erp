# ✅ Purchase Invoice Workflow - Final Validation Checklist

## Status: Trigger is installed correctly ✅

Based on your verification results:
- ✅ Trigger installed
- ✅ Function exists  
- ✅ No orphaned entries

**The database is ready. Now let's validate the complete workflow.**

---

## 🧪 Test Plan

### Test 1: Basic Trigger Test (In Supabase)

1. Open `supabase/sql/realtime_trigger_test.sql`
2. Find a confirmed invoice ID from your database
3. Replace `<INVOICE_ID>` in the "MANUAL TEST" section
4. Run the test
5. Should show: ✅ Trigger worked! Entry deleted!

**Expected Result**: Journal entry is deleted when status changes from confirmed → sent

---

### Test 2: App Integration Test

1. **Open your Flutter app**
2. **Go to Compras → Facturas de compra**
3. **Find an invoice at "Confirmada" status**
4. **Open the invoice detail page**
5. **Click "Volver a Enviada"**
6. **Wait for refresh**
7. **Go to Contabilidad → Asientos contables**
8. **Search for the invoice number**

**Expected Result**: No journal entry should exist for that invoice ✅

---

### Test 3: Complete Standard Workflow

Create a new invoice with **Standard** payment model:

#### Step-by-Step:

| Step | Action | What to Check | Expected Result |
|------|--------|---------------|-----------------|
| 1 | Create draft invoice | Status badge | "Borrador" (gray) |
| 2 | Click "Enviar a Proveedor" | Status changes | "Enviada" (blue) |
| 3 | Click "Confirmar Factura" | Asientos contables | 1 new entry created ✅ |
| 4 | Click "Volver a Enviada" | Asientos contables | Entry **DELETED** ✅ |
| 5 | Click "Confirmar Factura" again | Asientos contables | Entry created again ✅ |
| 6 | Click "Marcar como Recibida" | Inventario | Stock increased ✅ |
| 7 | Click "Volver a Confirmada" | Inventario | Stock decreased ✅ |
| 8 | Click "Marcar como Recibida" again | Status | "Recibida" |
| 9 | Click "Registrar Pago" | Payment form appears | Fill and save |
| 10 | Check status after payment | Status badge | "Pagada" (green) ✅ |

**All checks must pass ✅**

---

### Test 4: Complete Prepayment Workflow

Create a new invoice with **Prepago** payment model:

| Step | Action | What to Check | Expected Result |
|------|--------|---------------|-----------------|
| 1 | Create draft invoice (Prepago) | Model badge | "Prepago" (orange) |
| 2 | Click "Enviar a Proveedor" | Status | "Enviada" |
| 3 | Click "Confirmar Factura" | Asientos contables | 1 entry created (account 1155) ✅ |
| 4 | Click "Volver a Enviada" | Asientos contables | Entry **DELETED** ✅ |
| 5 | Click "Confirmar Factura" again | Status | "Confirmada" |
| 6 | Click "Registrar Pago" | Asientos contables | Payment entry (DR 1155, CR Bank) ✅ |
| 7 | Check status after payment | Status | "Pagada" |
| 8 | Click "Marcar como Recibida" | Inventario | Stock increased ✅ |
| 9 | Check settlement entry | Asientos contables | DR 1150, CR 1155 ✅ |
| 10 | Click "Volver a Pagada" | Inventario | Stock decreased ✅ |
| 11 | Check settlement deleted | Asientos contables | Settlement entry gone ✅ |

**All checks must pass ✅**

---

## 🔍 Validation Queries

Run these in Supabase to verify data integrity:

### Check 1: No orphaned journal entries
```sql
-- Should return 0 rows
SELECT 
  pi.invoice_number,
  pi.status,
  je.entry_number,
  je.entry_type
FROM purchase_invoices pi
JOIN journal_entries je ON je.source_reference = pi.id::TEXT
WHERE pi.status IN ('draft', 'sent')
  AND je.source_module = 'purchase_invoices';
```

### Check 2: All confirmed invoices have journal entries
```sql
-- All rows should have entry_count > 0
SELECT 
  pi.invoice_number,
  pi.status,
  COUNT(je.id) AS entry_count
FROM purchase_invoices pi
LEFT JOIN journal_entries je ON je.source_reference = pi.id::TEXT
WHERE pi.status = 'confirmed'
GROUP BY pi.id, pi.invoice_number, pi.status;
```

### Check 3: All received invoices have stock movements
```sql
-- All rows should have movement_count > 0
SELECT 
  pi.invoice_number,
  pi.status,
  COUNT(sm.id) AS movement_count
FROM purchase_invoices pi
LEFT JOIN stock_movements sm ON sm.reference = pi.id::TEXT
WHERE pi.status IN ('received', 'paid')
GROUP BY pi.id, pi.invoice_number, pi.status;
```

---

## ❌ Known Issues & Fixes

### Issue 1: Entry not deleted in app, but works in SQL
**Cause**: App not refreshing properly  
**Fix**: Add manual refresh after status change  
**Check**: `purchase_service.dart` line 479 - should call `getPurchaseInvoices(forceRefresh: true)`

### Issue 2: Trigger fires but entry still exists
**Cause**: entry_type value doesn't match  
**Fix**: Run Step 4 of `quick_fix_journal_deletion.sql` again  
**Verify**: 
```sql
SELECT DISTINCT entry_type 
FROM journal_entries 
WHERE source_module = 'purchase_invoices';
```
Should only show: `purchase_invoice`, `purchase_confirmation`, `purchase_receipt`, `payment`

### Issue 3: Multiple entries for same invoice
**Cause**: Re-confirming without reverting creates duplicate  
**Fix**: Trigger should prevent this, but check:
```sql
SELECT source_reference, COUNT(*) AS entry_count
FROM journal_entries
WHERE source_module = 'purchase_invoices'
GROUP BY source_reference
HAVING COUNT(*) > 2; -- More than 2 is suspicious
```

---

## 📊 Success Criteria

All these must be TRUE:

- [ ] **Trigger installed** and enabled
- [ ] **Function exists** and has correct logic
- [ ] **No orphaned entries** (sent invoices with journal entries)
- [ ] **Reverting from Confirmada deletes** journal entry
- [ ] **Reverting from Recibida deletes** stock movements
- [ ] **Prepayment settlement entry** created on receive
- [ ] **App refreshes** after each status change
- [ ] **No console errors** during workflow
- [ ] **Asientos contables shows** correct entries
- [ ] **Inventario updates** correctly

---

## 🎯 Final Validation Steps

1. **Run all 4 tests** above ✅
2. **Run all 3 validation queries** ✅
3. **Check no orphaned data** ✅
4. **Test with real suppliers/products** ✅
5. **Verify accounting entries balance** ✅
6. **Test both payment models** ✅
7. **Test all reversal paths** ✅
8. **Verify inventory accuracy** ✅

---

## 📝 Test Results Template

```
Date: ___________
Tester: ___________

Standard Model Test:
[ ] Draft → Sent ✅
[ ] Sent → Confirmed (entry created) ✅
[ ] Confirmed → Sent (entry deleted) ✅
[ ] Re-confirm ✅
[ ] Received (inventory +) ✅
[ ] Revert (inventory -) ✅
[ ] Paid ✅

Prepayment Model Test:
[ ] Draft → Sent ✅
[ ] Sent → Confirmed (entry created) ✅
[ ] Confirmed → Sent (entry deleted) ✅
[ ] Re-confirm ✅
[ ] Paid (account 1155) ✅
[ ] Received (settlement created) ✅
[ ] Revert (settlement deleted) ✅

Database Validation:
[ ] No orphaned entries ✅
[ ] All confirmations have entries ✅
[ ] All receipts have stock movements ✅

Notes/Issues:
_______________________________________
_______________________________________
```

---

## 🚀 Next Steps After Validation

Once all tests pass:

1. **Document any issues** found during testing
2. **Update training materials** for users
3. **Create backup** of working database
4. **Deploy to production** (if separate environment)
5. **Train users** on new workflow
6. **Monitor** first week of usage
7. **Collect feedback** from users

---

**Status**: Ready for validation testing  
**Estimated Time**: 30 minutes for complete testing  
**Priority**: Test #2 (App Integration) first, then complete workflows
