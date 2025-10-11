# 🧪 Sales Workflow Testing Guide

## Pre-Testing Checklist

Before you begin testing, ensure:

- [ ] SQL migration `sales_workflow_redesign.sql` has been run in Supabase
- [ ] Flutter app has been restarted
- [ ] You have access to "Ventas" and "Contabilidad" modules
- [ ] You have sample products with inventory available

---

## Test Scenarios

### ✅ Test 1: Complete Forward Flow

**Objective**: Verify the entire workflow from Draft to Paid works correctly

#### Steps:

1. **Create Invoice**
   - Navigate to `Ventas > Facturas`
   - Click `+ Nueva factura`
   - Fill in customer details
   - Add 2-3 products with quantities
   - Save as draft
   
   **Expected Result**:
   - Invoice saved with status "Borrador" (grey badge)
   - No journal entry created
   - Inventory unchanged

2. **Mark as Sent**
   - Open the invoice detail page
   - Click `Marcar como enviada`
   
   **Expected Result**:
   - Status changes to "Enviada" (blue badge)
   - No journal entry created ❌
   - Inventory unchanged ❌
   - Navigate to `Contabilidad > Asientos Contables` - should NOT see entry

3. **Confirm Invoice**
   - On invoice detail page
   - Click green `Confirmar` button
   
   **Expected Result**:
   - Status changes to "Confirmada" (purple badge)
   - Journal entry created ✅
   - Navigate to `Contabilidad > Asientos Contables`
   - Should see entry like: `INV-[invoice_number]` with:
     * Debit: Cuentas por Cobrar (total with IVA)
     * Credit: Ingresos por Ventas (subtotal)
     * Credit: IVA Débito (tax amount)
     * Debit: Costo de Ventas
     * Credit: Inventario
   - Check `Inventario > Productos` - quantities should be reduced ✅

4. **Register Payment**
   - Click `Pagar factura`
   - Enter payment details
   - Save payment
   
   **Expected Result**:
   - Status changes to "Pagada" (green badge)
   - Payment journal entry created
   - Balance becomes $0
   - Navigate to `Ventas > Pagos` - see payment listed

---

### ✅ Test 2: Backward Flow (Revert Confirmed to Sent)

**Objective**: Verify journal entries are DELETED (not reversed) when going backward

#### Steps:

1. **Create and Confirm Invoice**
   - Create new invoice with products
   - Mark as sent
   - Confirm it
   - Note the invoice number and journal entry number

2. **Verify Journal Entry Exists**
   - Navigate to `Contabilidad > Asientos Contables`
   - Find the entry for this invoice
   - Note the entry ID (e.g., `INV-20251011120000`)

3. **Check Initial Inventory**
   - Navigate to `Inventario > Productos`
   - Note the quantity of products used in the invoice
   - Should be reduced by invoice quantities

4. **Revert to Sent**
   - Open invoice detail page
   - Click `Volver a enviada`
   - Confirm in dialog
   
   **Expected Result**:
   - Status changes to "Enviada" (blue badge)
   - Navigate to `Contabilidad > Asientos Contables`
   - Original journal entry should be **DELETED** ❌ (not exist anymore)
   - Should NOT see a reversal entry (no "REV-xxx")
   - Navigate to `Inventario > Productos`
   - Quantities should be **RESTORED** to original values ✅

5. **Confirm Again**
   - Click `Confirmar` button again
   
   **Expected Result**:
   - Status changes to "Confirmada"
   - NEW journal entry created (different ID than before)
   - Inventory deducted again
   - This demonstrates idempotent behavior

---

### ✅ Test 3: Backward Flow (Revert Sent to Draft)

**Objective**: Verify reverting from Sent to Draft works correctly

#### Steps:

1. **Create and Send Invoice**
   - Create new invoice
   - Mark as sent (don't confirm)

2. **Revert to Draft**
   - Click `Volver a borrador`
   - Confirm in dialog
   
   **Expected Result**:
   - Status changes to "Borrador" (grey badge)
   - No journal entries involved (since sent doesn't create entries)
   - No inventory changes (since sent doesn't affect inventory)
   - Invoice is editable again

---

### ✅ Test 4: Cannot Revert Paid Invoice

**Objective**: Verify business rule - paid invoices cannot be reverted

#### Steps:

1. **Create and Complete Invoice**
   - Create invoice
   - Mark as sent
   - Confirm
   - Register full payment

2. **Attempt to Revert**
   - Invoice detail page should NOT show `Volver a enviada` button
   
   **Expected Result**:
   - No revert button visible when status is "Pagada"
   - Only `Editar` button available (for non-critical fields)

---

### ✅ Test 5: POS Integration

**Objective**: Verify POS creates confirmed invoices (not just sent)

#### Steps:

1. **Complete POS Sale**
   - Navigate to `POS` module
   - Add products to cart
   - Register payment (cash/card/transfer)
   - Complete sale

2. **Check Invoice Status**
   - Navigate to `Ventas > Facturas`
   - Find the POS invoice (should be at top of list)
   
   **Expected Result**:
   - Status should be "Confirmada" ✅ (not "Enviada")
   - Journal entry should exist in `Contabilidad`
   - Inventory should be deducted
   - This ensures POS sales immediately enter accounting

---

### ✅ Test 6: Status Color Coding

**Objective**: Verify all status badges display correct colors

#### Steps:

1. **Create Multiple Invoices**
   - Create invoice A - leave as draft
   - Create invoice B - mark as sent
   - Create invoice C - confirm
   - Create invoice D - confirm and pay

2. **Check List Page**
   - Navigate to `Ventas > Facturas`
   
   **Expected Result**:
   | Invoice | Status | Color |
   |---------|--------|-------|
   | A | Borrador | Grey |
   | B | Enviada | Blue |
   | C | Confirmada | Purple |
   | D | Pagada | Green |

3. **Check Detail Pages**
   - Open each invoice
   - Verify status badge in summary section matches list colors

4. **Check Form Page**
   - Open invoice in edit mode
   - Status chip in header should match colors

---

### ✅ Test 7: Inventory Tracking

**Objective**: Verify inventory changes happen only on confirmation

#### Test Matrix:

| Status Change | Inventory Effect |
|---------------|------------------|
| Draft → Sent | ❌ No change |
| Sent → Confirmed | ✅ Deduct quantities |
| Confirmed → Sent | ✅ Restore quantities |
| Sent → Draft | ❌ No change |
| Draft → Sent → Confirmed | ✅ Deduct on confirm |

#### Steps:

1. **Record Initial Inventory**
   - Note quantities of 3 test products

2. **Test Each Transition**
   - For each row in matrix above:
     * Perform the status change
     * Check `Inventario > Productos`
     * Verify expected behavior

---

### ✅ Test 8: Journal Entry Deletion vs Reversal

**Objective**: Compare sales (DELETE) vs purchases (REVERSE) approaches

#### Steps:

1. **Test Sales Invoice (DELETE approach)**
   - Create and confirm sales invoice
   - Note journal entry ID: `INV-001`
   - Revert to sent
   - Navigate to `Contabilidad > Asientos Contables`
   - Search for `INV-001`
   
   **Expected Result**:
   - Entry is DELETED (no results found)
   - No reversal entry created

2. **Test Purchase Invoice (REVERSE approach)**
   - Navigate to `Compras > Facturas`
   - Create and receive purchase invoice
   - Note journal entry ID
   - Revert to draft
   - Navigate to `Contabilidad > Asientos Contables`
   
   **Expected Result**:
   - Original entry still exists (marked as reversed)
   - Reversal entry created (REV-xxx)
   - This demonstrates the difference in approaches

---

### ✅ Test 9: Data Migration Verification

**Objective**: Verify existing invoices migrated correctly

#### Steps:

1. **Check Pre-Migration Invoices**
   - Navigate to `Ventas > Facturas`
   - Look for invoices created before migration
   - Check their status

   **Expected Result**:
   - Old "Enviada" invoices WITH journal entries → now "Confirmada"
   - Old "Enviada" invoices WITHOUT journal entries → still "Enviada"

2. **Verify Journal Entry Integrity**
   - For migrated invoices
   - Open detail page
   - Click `Contabilidad` tab (if available) or check `Asientos Contables`
   - Ensure journal entries are intact

---

### ✅ Test 10: Error Handling

**Objective**: Verify proper error messages and validation

#### Test Cases:

1. **Confirm Invoice Without Items**
   - Try to confirm empty invoice
   - Should show error message

2. **Confirm with Insufficient Inventory**
   - Create invoice with quantity > available stock
   - Try to confirm
   - Should show inventory error

3. **Network Interruption**
   - Start confirming invoice
   - Disable network mid-operation
   - Should show error, invoice should remain in previous state

4. **Duplicate Confirmation**
   - Confirm invoice
   - Try to confirm again (if possible)
   - Should be idempotent (no duplicate entries)

---

## Regression Testing

### Areas to Verify

- [ ] **Reports Module**: If you have sales reports, verify they include "Confirmada" status
- [ ] **Dashboard**: Check KPIs still calculate correctly
- [ ] **Customer Portal**: If customers can view invoices, check status display
- [ ] **Email Notifications**: Status change emails should reflect new workflow
- [ ] **Export/Import**: CSV exports should include confirmed status

---

## Performance Testing

### Large Dataset Test

1. Create 100 invoices
2. Confirm all 100
3. Revert 50 to sent
4. Check database size
5. Verify no performance degradation

**Expected Result**:
- Reverting should delete entries, freeing up space
- Database should be smaller than with reversal approach
- Operations should remain fast

---

## Comparison Checklist

### Sales vs Purchases

| Aspect | Sales | Purchases |
|--------|-------|-----------|
| Workflow | Draft → Sent → Confirmed → Paid | Draft → Received → Paid |
| Accounting Trigger | "Confirmed" | "Received" |
| Backward Method | DELETE entries | REVERSE entries |
| Audit Trail | Simpler (entries deleted) | Complete (reversals kept) |
| Database Impact | Cleaner (less clutter) | More records (audit trail) |

Test both workflows side-by-side to understand the difference.

---

## Known Limitations

1. **Paid Invoices**: Cannot be reverted (by design)
2. **Cancelled Invoices**: Cannot transition to any other status
3. **Overdue Status**: Auto-calculated, cannot be manually set
4. **Partial Payments**: Don't change status from confirmed to paid until fully paid

---

## Troubleshooting

### Issue: "Status 'confirmed' not allowed"

**Cause**: SQL migration not run  
**Fix**: Run `sales_workflow_redesign.sql` in Supabase SQL Editor

### Issue: Journal entry still created when "sent"

**Cause**: Old trigger function still active  
**Fix**: 
```sql
-- In Supabase SQL Editor
SELECT proname FROM pg_proc WHERE proname LIKE '%sales_invoice%';
-- Should see updated function, if not re-run migration
```

### Issue: Can't revert from confirmed to sent

**Cause**: Payments exist on invoice  
**Fix**: Delete payments first (if testing), or this is expected behavior

### Issue: Inventory not restored

**Cause**: Trigger not firing properly  
**Fix**: Check Supabase logs:
```sql
SELECT * FROM public.journal_entries 
WHERE source_module = 'sales_invoices' 
ORDER BY created_at DESC 
LIMIT 10;
```

### Issue: Old invoices have wrong status

**Cause**: Migration data update didn't run  
**Fix**: Manually run migration section:
```sql
UPDATE public.sales_invoices
SET status = 'confirmed'
WHERE status = 'sent'
  AND id IN (
    SELECT DISTINCT je.source_reference::integer
    FROM public.journal_entries je
    WHERE je.source_module = 'sales_invoices'
      AND je.status = 'posted'
  );
```

---

## Success Criteria

✅ All test scenarios pass  
✅ Journal entries deleted (not reversed) when going backward  
✅ Inventory correctly restored when reverting  
✅ POS creates confirmed invoices  
✅ All status colors display correctly  
✅ No duplicate journal entries  
✅ Database performs well with new approach  
✅ Existing invoices migrated correctly  

---

## Reporting Issues

If you find issues during testing:

1. **Document**:
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Screenshots/error messages

2. **Check Database**:
   ```sql
   -- Check invoice status
   SELECT id, invoice_number, status FROM sales_invoices WHERE id = X;
   
   -- Check journal entries
   SELECT * FROM journal_entries WHERE source_reference = 'X' AND source_module = 'sales_invoices';
   
   -- Check inventory
   SELECT * FROM products WHERE id = X;
   ```

3. **Check Logs**:
   - Supabase → Logs → Database
   - Look for trigger execution errors

---

**Testing Timeframe**: Plan 2-3 hours for comprehensive testing  
**Critical Tests**: 1, 2, 5 (must pass before production use)  
**Optional Tests**: 7, 8, 9 (recommended but not blocking)

Good luck with testing! 🚀
