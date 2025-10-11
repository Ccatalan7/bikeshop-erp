# Purchase Invoice Reversible Status Flow

## Overview

Purchase invoices now support **bidirectional status changes**, allowing you to go back and forth between states. When you go backward, all actions (inventory and accounting) are automatically **reversed**.

## Status Flow Diagram

```
┌─────────────┐
│   DRAFT     │ ← Initial state
│  (Borrador) │
└──────┬──────┘
       │
       │ ➡️ [Marcar como Recibida]
       │    • Creates IN stock movements
       │    • Increases inventory
       │    • Creates journal entry (DR: Inventory/IVA, CR: AP)
       │
       ⬇️
┌──────────────┐
│   RECEIVED   │
│  (Recibida)  │
└──────┬───────┘
       │
       │ ⬅️ [Volver a Borrador]
       │    • Deletes stock movements
       │    • Decreases inventory
       │    • Creates reversing journal entry
       │
       │ ➡️ [Marcar como Pagada]
       │    • Records payment (future)
       │
       ⬇️
┌──────────────┐
│     PAID     │
│   (Pagada)   │
└──────┬───────┘
       │
       │ ⬅️ [Volver a Recibida]
       │    • Only changes status
       │    • Keeps inventory/accounting
       │
       │ ⬅️ [Volver a Borrador]
       │    • Deletes stock movements
       │    • Decreases inventory
       │    • Creates reversing journal entry
```

## UI Buttons

### Forward Buttons (Green/Blue)
- **"Marcar como Recibida"** (Green) - Visible when Draft
- **"Marcar como Pagada"** (Blue) - Visible when Received

### Reversal Buttons (Orange/Gray)
- **"Volver a Recibida"** (Orange) - Visible when Paid
- **"Volver a Borrador"** (Gray) - Visible when Received or Paid

## What Happens When You Revert

### Received → Draft (Volver a Borrador)

**UI Confirmation:**
```
⚠️ Confirmar reversión

¿Volver esta factura recibida a BORRADOR?

⚠️ ADVERTENCIA: Esto reversará:
• Los movimientos de inventario (reducirá el stock)
• Los asientos contables (creará asientos de reverso)

Solo usa esta opción si cometiste un error.

¿Estás seguro?
```

**Actions Performed:**

1. **Inventory Reversal:**
   - Finds all IN stock movements for this invoice
   - Checks if enough inventory exists to reverse
   - Decreases product inventory by purchased quantities
   - Deletes the stock movements
   - **Fails if insufficient inventory** (can't go negative)

2. **Accounting Reversal:**
   - Finds the original journal entry (COMP-XXX)
   - Creates a **reversing entry** with prefix `REV-`
   - Swaps debits and credits (debits become credits, credits become debits)
   - Marks original entry as **'reversed'** (audit trail preserved)
   - Does NOT delete original entry

**Example:**

Original Entry (COMP-FC001):
```
DR  1105  Inventario           100,000
DR  1180  IVA Crédito Fiscal    19,000
CR  2100  Proveedores          119,000
```

Reversing Entry (REV-COMP-FC001):
```
DR  2100  Proveedores          119,000
CR  1105  Inventario           100,000
CR  1180  IVA Crédito Fiscal    19,000
```

**Net Effect:** Both entries cancel out, returning to zero.

### Paid → Received (Volver a Recibida)

**UI Confirmation:**
```
Confirmar reversión

¿Volver esta factura pagada a RECIBIDA?

Esto solo cambiará el estado. El inventario y
la contabilidad se mantendrán intactos.

¿Continuar?
```

**Actions Performed:**
- Only changes status from `paid` to `received`
- **No inventory changes**
- **No accounting changes**
- Future: Will remove payment records when payment system is implemented

### Paid → Draft (Volver a Borrador)

Same as **Received → Draft**, plus:
- Future: Will remove payment records

## Database Implementation

### New SQL Functions

1. **`reverse_purchase_invoice_inventory(invoice_id UUID)`**
   - Validates sufficient inventory exists
   - Decreases product quantities
   - Deletes stock movements
   - Returns `true` on success, throws exception on failure

2. **`reverse_purchase_invoice_journal_entry(invoice_id UUID)`**
   - Creates reversing journal entry
   - Marks original as 'reversed'
   - Preserves audit trail
   - Returns `true` on success

3. **`handle_purchase_invoice_reversal()`**
   - Trigger function (BEFORE UPDATE)
   - Detects backward status changes
   - Calls reversal functions automatically
   - Logs all actions

### Triggers

Two triggers work together:

1. **`purchase_invoice_reversal_trigger`** (BEFORE UPDATE)
   - Handles backward transitions
   - Calls reversal functions

2. **`purchase_invoice_change_trigger`** (AFTER UPDATE)
   - Handles forward transitions
   - Creates inventory/accounting

## Safety Features

### 1. Inventory Check
```sql
IF movement_rec.inventory_qty < movement_rec.quantity THEN
  RAISE EXCEPTION 'Cannot reverse: insufficient inventory';
END IF;
```

**Example:**
- Invoice received: +10 units → Inventory = 10
- Sold 5 units → Inventory = 5
- Try to revert → ❌ **FAILS** (need 10, have 5)

### 2. Audit Trail Preservation
- Original journal entries are **NOT deleted**
- They are marked as `'reversed'`
- Reversing entries are created separately
- Full audit trail maintained

### 3. User Confirmation
- All reversal actions require explicit confirmation
- Warning messages explain consequences
- Different confirmations for different reversals

### 4. Error Handling
- Database-level validation
- Clear error messages
- Transaction rollback on failure

## Testing Guide

### Test Case 1: Forward and Back

1. Create purchase invoice with products (e.g., "Bicicleta MTB" x 5)
2. Note current inventory: 10 units
3. Mark as Received
   - ✅ Inventory = 15 units
   - ✅ Stock movement created (IN +5)
   - ✅ Journal entry created (COMP-XXX)
4. Click "Volver a Borrador"
   - ✅ Inventory = 10 units (back to original)
   - ✅ Stock movement deleted
   - ✅ Reversing entry created (REV-COMP-XXX)
   - ✅ Original entry marked 'reversed'

### Test Case 2: Insufficient Inventory

1. Create invoice with 10 units
2. Mark as Received → Inventory +10
3. Sell 8 units → Inventory = 2
4. Try "Volver a Borrador"
   - ❌ **Error:** "insufficient inventory"
   - Cannot reverse (would make inventory = -8)

### Test Case 3: Paid → Received → Draft

1. Mark as Received
2. Mark as Paid
3. Click "Volver a Recibida"
   - ✅ Status changes only
   - ✅ Inventory unchanged
   - ✅ Accounting unchanged
4. Click "Volver a Borrador"
   - ✅ Reverses inventory
   - ✅ Reverses accounting

## Verification Queries

### Check Reversed Entries
```sql
-- Show all reversed journal entries
SELECT 
  entry_number,
  description,
  status,
  date
FROM journal_entries
WHERE status = 'reversed'
ORDER BY date DESC;

-- Show all reversing entries
SELECT 
  entry_number,
  description,
  type,
  date
FROM journal_entries
WHERE type = 'reversal'
ORDER BY date DESC;

-- Show matched pairs (original + reversal)
SELECT 
  je1.entry_number as original,
  je1.status as original_status,
  je2.entry_number as reversal,
  je1.description
FROM journal_entries je1
LEFT JOIN journal_entries je2 
  ON je2.entry_number = 'REV-' || je1.entry_number
WHERE je1.source_module = 'purchase_invoice'
ORDER BY je1.date DESC;
```

### Check Inventory Changes
```sql
-- Show product with movements
SELECT 
  p.name,
  p.sku,
  p.inventory_qty as current_inventory,
  COUNT(sm.id) as movement_count,
  SUM(CASE WHEN sm.type = 'IN' THEN sm.quantity ELSE 0 END) as total_in,
  SUM(CASE WHEN sm.type = 'OUT' THEN sm.quantity ELSE 0 END) as total_out
FROM products p
LEFT JOIN stock_movements sm ON sm.product_id = p.id
GROUP BY p.id, p.name, p.sku, p.inventory_qty
HAVING COUNT(sm.id) > 0;
```

## Files Modified/Created

### SQL Scripts
- ✅ `supabase/sql/purchase_invoice_reversal.sql` (NEW)
  - Reversal functions
  - Updated triggers
  - Verification queries

### Dart Service
- ✅ `lib/modules/purchases/services/purchase_service.dart`
  - `revertToDraft()` method
  - `revertToReceived()` method

### UI
- ✅ `lib/modules/purchases/pages/purchase_invoice_form_page.dart`
  - Reversal buttons in header
  - `_revertToDraft()` action method
  - `_revertToReceived()` action method
  - Confirmation dialogs with warnings

## Deployment Steps

### 1. Run SQL Script
```sql
-- In Supabase SQL Editor:
-- Copy/paste: supabase/sql/purchase_invoice_reversal.sql
```

### 2. Restart Flutter App
```bash
flutter run -d windows
```

### 3. Test Flow
1. Create test invoice
2. Try forward flow (Draft → Received → Paid)
3. Try backward flow (Paid → Received → Draft)
4. Verify inventory and accounting

## Common Scenarios

### Scenario 1: Correcting Quantity Mistake
**Situation:** Received 10 units instead of 5

**Solution:**
1. Click "Volver a Borrador"
2. Edit invoice (change quantity to 5)
3. Save
4. Click "Marcar como Recibida" again

### Scenario 2: Wrong Supplier
**Situation:** Invoice created for wrong supplier

**Solution:**
1. Click "Volver a Borrador"
2. Change supplier
3. Save
4. Click "Marcar como Recibida"

### Scenario 3: Duplicate Invoice
**Situation:** Invoice was entered twice by mistake

**Solution:**
1. Click "Volver a Borrador"
2. Delete the duplicate invoice
3. Keep only the correct one

## Important Notes

⚠️ **Reversal Requirements:**
- Can only revert if sufficient inventory exists
- Original entries are preserved (audit trail)
- Reversing entries are created (not deleted)
- All actions are logged with NOTICE messages

✅ **Best Practices:**
- Only use reversal for genuine mistakes
- Check inventory before reverting
- Review audit trail after reversal
- Document reason for reversal (future feature)

🔒 **Security:**
- Consider adding permission checks for reversals
- Log who performed the reversal (future feature)
- Add approval workflow for high-value reversals (future feature)

---

**Status:** ✅ Fully implemented and ready to test!
