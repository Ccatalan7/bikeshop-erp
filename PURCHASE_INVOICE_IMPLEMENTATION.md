# Purchase Invoice Workflow Implementation

## Overview
This implementation adds complete status workflow functionality to purchase invoices, mirroring the sales invoice system but adapted for purchase accounting.

## Status Flow
1. **Draft** → Initial state when creating a new invoice
2. **Received** → Marks goods as received, increases inventory, creates accounting entries
3. **Paid** → Marks invoice as paid (accounting handled by triggers)
4. **Cancelled** → Marks invoice as cancelled (no inventory/accounting impact)

## Database Layer (SQL)

### File: `supabase/sql/purchase_invoice_workflow.sql`

#### Functions Created:

1. **`consume_purchase_invoice_inventory()`**
   - Finds all 'received' purchase invoices without stock movements
   - Creates IN stock movements for each invoice item
   - Increases product inventory quantities
   - Prevents duplicate processing

2. **`create_purchase_invoice_journal_entry(invoice_id UUID)`**
   - Creates accounting journal entries for purchase invoices
   - **Debit accounts:**
     - Inventory (1105) or Expense (5101): subtotal amount
     - IVA Crédito Fiscal (1107): IVA amount
   - **Credit account:**
     - Accounts Payable (2101): total amount
   - Uses dynamic account lookup (by code or name)
   - Prevents duplicate journal entries

3. **`handle_purchase_invoice_change()`**
   - Trigger function that fires on INSERT or UPDATE
   - When status changes to 'received': processes inventory and creates journal entry
   - Includes error handling and logging

#### Trigger:
- **`purchase_invoice_change_trigger`**
  - Fires AFTER INSERT OR UPDATE OF status
  - Automatically processes invoices when status changes

### Accounting Logic (Chilean Standards)

```
Purchase Invoice Total: $100,000 CLP
Subtotal: $84,033.61
IVA (19%): $15,966.39

Journal Entry:
  Debit: Inventario (1105)           $84,033.61
  Debit: IVA Crédito Fiscal (1107)   $15,966.39
  Credit: Proveedores (2101)        $100,000.00
```

## Application Layer (Dart/Flutter)

### Updated Files:

#### 1. `lib/modules/purchases/services/purchase_service.dart`

**New Methods:**
- `updateInvoiceStatus(String invoiceId, PurchaseInvoiceStatus status)` - Generic status updater
- `markAsReceived(String invoiceId)` - Mark as received (triggers inventory + accounting)
- `markAsPaid(String invoiceId)` - Mark as paid
- `cancelInvoice(String invoiceId)` - Cancel invoice

**Behavior:**
- Updates database via Supabase
- Triggers refresh accounting service
- Updates local cache
- Notifies listeners for UI refresh

#### 2. `lib/modules/purchases/pages/purchase_invoice_form_page.dart`

**UI Enhancements:**
- Status chip display showing current status with color coding
- **"Marcar como Recibida"** button (green) - visible when status = draft
- **"Marcar como Pagada"** button (blue) - visible when status = received
- Confirmation dialogs for status changes
- Loading states during status updates

**Status Colors:**
- Draft: Grey
- Received: Green
- Paid: Blue
- Cancelled: Red

**New Methods:**
- `_markAsReceived()` - Handles received status change with confirmation
- `_markAsPaid()` - Handles paid status change with confirmation
- `_buildStatusChip()` - Renders status badge

#### 3. `lib/modules/purchases/pages/purchase_invoice_list_page.dart`
- Already had status display (no changes needed)
- Shows colored status badges in list view

## Workflow Comparison

### Sales Invoice (OUT)
1. Create → Draft
2. Send → Sent (decreases inventory, creates AR journal entry)
3. Collect → Paid (records payment)

### Purchase Invoice (IN)
1. Create → Draft
2. Receive → Received (increases inventory, creates AP journal entry)
3. Pay → Paid (records payment)

## Key Differences from Sales

| Aspect | Sales Invoice | Purchase Invoice |
|--------|---------------|------------------|
| **Inventory** | Decreases (OUT) | Increases (IN) |
| **Account Type** | Accounts Receivable | Accounts Payable |
| **IVA** | IVA Débito Fiscal | IVA Crédito Fiscal |
| **Primary Action** | "Enviar" (Send) | "Recibir" (Receive) |
| **Movement Type** | `sales_invoice` | `purchase_invoice` |
| **Journal Entry** | DR: AR, CR: Sales/IVA | DR: Inv/IVA, CR: AP |

## Testing Steps

### 1. Database Setup
```sql
-- Run the workflow script
\i supabase/sql/purchase_invoice_workflow.sql

-- Verify functions exist
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name LIKE '%purchase%';

-- Verify trigger exists
SELECT trigger_name 
FROM information_schema.triggers 
WHERE trigger_name = 'purchase_invoice_change_trigger';
```

### 2. Create Test Purchase Invoice
1. Open app → Navigate to "Compras"
2. Click "Nueva Factura"
3. Select/create supplier
4. Add products (e.g., "Bicicleta MTB x2")
5. Save as Draft
6. Note initial inventory levels

### 3. Test Received Status
1. Click "Marcar como Recibida"
2. Confirm dialog
3. **Expected results:**
   - Status changes to "Recibida" (green)
   - Inventory increases by purchased quantities
   - Stock movements created with type=IN, movement_type=purchase_invoice
   - Journal entry created with reference_type=purchase_invoice

### 4. Verify Inventory Impact
```sql
-- Check stock movements
SELECT * FROM stock_movements 
WHERE movement_type = 'purchase_invoice' 
ORDER BY created_at DESC;

-- Check product inventory
SELECT name, sku, inventory_qty 
FROM products 
WHERE id IN (SELECT DISTINCT product_id FROM stock_movements 
             WHERE movement_type = 'purchase_invoice');
```

### Check journal entries from purchase invoices
```sql
-- Check journal entries
SELECT je.*, 
       (SELECT SUM(debit_amount) FROM journal_lines WHERE entry_id = je.id) as total_debit,
       (SELECT SUM(credit_amount) FROM journal_lines WHERE entry_id = je.id) as total_credit
FROM journal_entries je
WHERE source_module = 'purchase_invoice'
ORDER BY created_at DESC;

-- Check journal entry lines (should see Inventory DR, IVA CR DR, AP CR)
SELECT jel.*, a.code, a.name
FROM journal_lines jel
JOIN accounts a ON a.id = jel.account_id
WHERE entry_id IN (
  SELECT id FROM journal_entries WHERE source_module = 'purchase_invoice'
)
ORDER BY jel.created_at DESC;
```

### 6. Test Paid Status
1. With invoice at "Recibida" status
2. Click "Marcar como Pagada"
3. Confirm dialog
4. **Expected results:**
   - Status changes to "Pagada" (blue)
   - UI updates immediately

### 7. Test Error Handling
- Try marking as received without products → Should prevent
- Try marking cancelled invoice → No inventory change
- Check database logs for NOTICE/WARNING messages

## Troubleshooting

### Common Issues

#### 1. "Inventory/Expense account not found"
**Solution:** Create chart of accounts entry:
```sql
INSERT INTO chart_of_accounts (id, code, name, type, category)
VALUES (gen_random_uuid(), '1105', 'Inventario', 'asset', 'current_assets');
```

#### 2. "Accounts Payable account not found"
**Solution:** Create chart of accounts entry:
```sql
INSERT INTO chart_of_accounts (id, code, name, type, category)
VALUES (gen_random_uuid(), '2101', 'Proveedores', 'liability', 'current_liabilities');
```

#### 3. "IVA Crédito Fiscal account not found"
**Solution:** (Warning only, will skip IVA entry)
```sql
INSERT INTO chart_of_accounts (id, code, name, type, category)
VALUES (gen_random_uuid(), '1107', 'IVA Crédito Fiscal', 'asset', 'current_assets');
```

#### 4. Inventory not increasing
**Check:**
```sql
-- Verify trigger is installed
SELECT * FROM pg_trigger WHERE tgname = 'purchase_invoice_change_trigger';

-- Check for errors in logs
SELECT * FROM stock_movements WHERE movement_type = 'purchase_invoice';

-- Manually trigger processing
SELECT consume_purchase_invoice_inventory();
```

#### 5. Duplicate stock movements
**Prevention:** Function checks for existing movements before creating new ones
```sql
-- Clean up duplicates if needed (CAREFUL!)
DELETE FROM stock_movements 
WHERE id NOT IN (
  SELECT MIN(id) FROM stock_movements 
  GROUP BY product_id, reference, movement_type
);
```

## Manual Operations

### Process all unprocessed received invoices:
```sql
SELECT consume_purchase_invoice_inventory();
```

### Create journal entry for specific invoice:
```sql
SELECT create_purchase_invoice_journal_entry('your-invoice-uuid-here');
```

### Check invoice processing status:
```sql
SELECT 
  pi.invoice_number,
  pi.status,
  pi.total,
  COUNT(sm.id) as stock_movements_count,
  COUNT(je.id) as journal_entries_count
FROM purchase_invoices pi
LEFT JOIN stock_movements sm ON sm.reference = pi.id::text AND sm.movement_type = 'purchase_invoice'
LEFT JOIN journal_entries je ON je.source_reference = pi.id::text AND je.source_module = 'purchase_invoice'
WHERE pi.status = 'received'
GROUP BY pi.id, pi.invoice_number, pi.status, pi.total;
```

## Future Enhancements

1. **Payment Recording:**
   - Create payment form/dialog
   - Record payment transactions
   - Link payments to invoices
   - Update accounting (DR: AP, CR: Cash/Bank)

2. **Purchase Returns:**
   - Create credit note mechanism
   - Reverse inventory movements
   - Reverse accounting entries

3. **Partial Receipts:**
   - Allow marking items as partially received
   - Track received vs ordered quantities
   - Multiple receipt operations per invoice

4. **Multi-warehouse:**
   - Select warehouse for receipt
   - Track inventory by location

5. **Cost Allocation:**
   - Split additional costs across products
   - Update product cost basis

## Compliance Notes

- ✅ Chilean accounting standards (IVA Crédito Fiscal)
- ✅ Audit trail (all movements logged with references)
- ✅ Double-entry bookkeeping (balanced journal entries)
- ✅ Inventory accuracy (synchronized with purchases)
- ✅ Status-based workflow (clear lifecycle)
- ✅ User confirmations (prevents accidental changes)

## Related Files

- SQL: `supabase/sql/purchase_invoice_workflow.sql`
- Service: `lib/modules/purchases/services/purchase_service.dart`
- Model: `lib/modules/purchases/models/purchase_invoice.dart`
- UI Form: `lib/modules/purchases/pages/purchase_invoice_form_page.dart`
- UI List: `lib/modules/purchases/pages/purchase_invoice_list_page.dart`
- Stock Movements: `lib/modules/inventory/pages/stock_movement_list_page.dart`
- Accounting: `lib/modules/accounting/services/accounting_service.dart`

---

**Implementation Status:** ✅ Complete and ready for testing
**Version:** 1.0
**Date:** 2024
