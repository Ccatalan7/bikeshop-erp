# 🚀 Purchase Invoice 5-Status System - Implementation Guide

## ✅ What Has Been Implemented

This guide documents the complete implementation of the 5-status purchase invoice system with dual payment models (Standard and Prepayment).

---

## 📦 Files Created/Modified

### **Database (SQL)**
1. ✅ **`supabase/sql/purchase_invoice_5status_migration.sql`**
   - Adds all new columns to `purchase_invoices` table
   - Updates status constraint to include 5 statuses
   - Adds performance indexes
   - Migrates existing data
   
2. ✅ **`supabase/sql/purchase_invoice_triggers.sql`**
   - Complete trigger system for both payment models
   - Functions: consume_inventory, reverse_inventory, create_journal_entries, settle_prepaid
   - DELETE-based reversals (Zoho Books style)
   - Payment tracking with automatic status updates

### **Models**
3. ✅ **`lib/modules/purchases/models/purchase_invoice.dart`** (UPDATED)
   - Added new fields: prepaymentModel, sentDate, confirmedDate, receivedDate, paidDate, etc.
   - Updated status enum with 5 statuses: draft, sent, confirmed, received, paid
   - Updated fromJson/toJson methods
   - Added balance calculation

### **Services**
4. ✅ **`lib/modules/purchases/services/purchase_service_extensions.dart`** (NEW)
   - Status transition methods: markAsSent, confirmInvoice, markAsReceived
   - Reversal methods: revertToDraft, revertToSent, revertToConfirmed, revertToPaid
   - Payment methods: registerPayment, deletePayment, getInvoicePayments
   - Ready to merge into main PurchaseService

### **Widgets**
5. ✅ **`lib/modules/purchases/widgets/purchase_model_selection_dialog.dart`** (NEW)
   - Beautiful dialog with two payment model options
   - Radio button selection with detailed descriptions
   - Icons and color coding for each model
   - Returns `bool? isPrepayment`

### **Documentation**
6. ✅ **`.github/Purchase_Invoice_status_flow.md`**
   - Complete standard model documentation
   - All 5 statuses with accounting/inventory logic
   - Button specifications and SQL code

7. ✅ **`.github/Purchase_Invoice_Prepayment_Flow.md`**
   - Complete prepayment model documentation
   - Different status flow sequence
   - Inventory on Order account usage

8. ✅ **`.github/Purchase_Invoice_Model_Selection.md`**
   - Model selection UX documentation
   - Database storage specifications
   - Frontend/backend integration guide

---

## 🔧 Installation Steps

### Step 1: Run Database Migrations

Run these SQL files **in order** in your Supabase SQL Editor:

```sql
-- 1. Add new columns and constraints
\i supabase/sql/purchase_invoice_5status_migration.sql

-- 2. Create triggers and functions
\i supabase/sql/purchase_invoice_triggers.sql
```

**Verify migration:**
```sql
-- Check new columns exist
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'purchase_invoices' 
  AND column_name IN ('prepayment_model', 'sent_date', 'confirmed_date', 'received_date', 'paid_date');

-- Check status constraint
SELECT pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'purchase_invoices_status_check';
```

### Step 2: Create Required Accounts

Ensure these accounts exist in your `accounts` table:

```sql
-- Check if accounts exist
SELECT code, name FROM accounts WHERE code IN ('1150', '1155', '1140', '2120');

-- If missing, create them:
INSERT INTO accounts (id, code, name, type, category, is_active) VALUES
  (gen_random_uuid(), '1150', 'Inventario', 'asset', 'currentAsset', true),
  (gen_random_uuid(), '1155', 'Inventario en Tránsito', 'asset', 'currentAsset', true),
  (gen_random_uuid(), '1140', 'IVA Crédito Fiscal', 'tax', 'taxReceivable', true),
  (gen_random_uuid(), '2120', 'Cuentas por Pagar', 'liability', 'currentLiability', true)
ON CONFLICT (code) DO NOTHING;
```

### Step 3: Update PurchaseService

**Merge the extension methods into your main `PurchaseService`:**

1. Open `lib/modules/purchases/services/purchase_service.dart`
2. Copy all methods from `purchase_service_extensions.dart`
3. Paste them into the `PurchaseService` class
4. Ensure `_supabase` client is available (adjust to use `_db.supabase` if needed)

**Alternative:** Just import and use the extensions file as-is.

### Step 4: Update List Page to Show Dialog

**In `lib/modules/purchases/pages/purchase_invoice_list_page.dart`:**

Add the import:
```dart
import '../widgets/purchase_model_selection_dialog.dart';
```

Update the FAB button's `onPressed`:
```dart
FloatingActionButton(
  onPressed: () async {
    // Show model selection dialog
    final isPrepayment = await showPurchaseModelSelectionDialog(context);
    
    if (isPrepayment != null && mounted) {
      // Navigate to form with model selection
      context.push('/purchases/invoices/new?prepayment=$isPrepayment');
    }
  },
  child: const Icon(Icons.add),
  tooltip: 'Nueva Factura de Compra',
)
```

### Step 5: Update Form Page to Accept Model

**In `lib/modules/purchases/pages/purchase_invoice_form_page.dart`:**

Add constructor parameter:
```dart
class PurchaseInvoiceFormPage extends StatefulWidget {
  final String? invoiceId;  // existing
  final bool isPrepayment;  // NEW

  const PurchaseInvoiceFormPage({
    super.key,
    this.invoiceId,
    this.isPrepayment = false,  // default to standard
  });
  
  // ...
}
```

Save `prepayment_model` when creating invoice:
```dart
Future<void> _saveInvoice() async {
  final invoiceData = {
    'invoice_number': _invoiceNumberController.text,
    'supplier_id': _selectedSupplierId,
    'total': _calculateTotal(),
    'status': 'draft',
    'prepayment_model': widget.isPrepayment,  // ← Save model
    // ... other fields
  };
  
  await _purchaseService.savePurchaseInvoice(
    PurchaseInvoice.fromJson(invoiceData)
  );
}
```

Show model indicator in form (read-only for edits):
```dart
if (widget.invoiceId != null && _invoice != null)
  ListTile(
    leading: Icon(
      _invoice!.prepaymentModel ? Icons.payment : Icons.local_shipping,
      color: _invoice!.prepaymentModel ? Colors.orange : Colors.blue,
    ),
    title: const Text('Modelo de Pago'),
    subtitle: Text(
      _invoice!.prepaymentModel 
        ? 'Prepago (no se puede cambiar)' 
        : 'Estándar (no se puede cambiar)'
    ),
    enabled: false,
  ),
```

### Step 6: Update List Page Status Filters

**In `purchase_invoice_list_page.dart`, update status filter dropdown:**

```dart
final statusOptions = [
  {'value': 'all', 'label': 'Todos'},
  {'value': 'draft', 'label': 'Borrador'},
  {'value': 'sent', 'label': 'Enviada'},       // NEW
  {'value': 'confirmed', 'label': 'Confirmada'}, // NEW
  {'value': 'received', 'label': 'Recibida'},
  {'value': 'paid', 'label': 'Pagada'},
  {'value': 'cancelled', 'label': 'Anulada'},
];
```

Update `_statusColor()` and `_statusLabel()` methods:
```dart
Color _statusColor(PurchaseInvoiceStatus status) {
  switch (status) {
    case PurchaseInvoiceStatus.draft:
      return Colors.grey;
    case PurchaseInvoiceStatus.sent:
      return Colors.blue;
    case PurchaseInvoiceStatus.confirmed:
      return Colors.purple;
    case PurchaseInvoiceStatus.received:
      return Colors.green;
    case PurchaseInvoiceStatus.paid:
      return Colors.blue;
    case PurchaseInvoiceStatus.cancelled:
      return Colors.red;
  }
}
```

### Step 7: Create Detail Page (TODO)

**Create `lib/modules/purchases/pages/purchase_invoice_detail_page.dart`**

This is the most complex page - it needs:
- Status badge display
- Model badge display (Prepago vs Estándar)
- Timeline view with 5 steps
- Conditional action buttons based on status and model
- Confirmation dialogs for each transition
- Payment list and payment deletion

**See the documentation files for complete specifications.**

### Step 8: Create Payment Form Page (TODO)

**Create `lib/modules/purchases/pages/purchase_payment_form_page.dart`**

Form fields:
- Payment method (Efectivo, Transferencia, Cheque, etc.)
- Payment date
- Bank account (dropdown)
- Amount
- Reference
- Notes

**Calls `purchaseService.registerPayment()` on save.**

---

## 🧪 Testing Checklist

### Standard Model Flow
- [ ] Create invoice with Standard model
- [ ] Draft → Sent transition
- [ ] Sent → Confirmed transition (check accounting entry created)
- [ ] Confirmed → Received transition (check inventory increased)
- [ ] Received → Paid transition (check payment recorded)
- [ ] Paid → Received reversal (check payment deleted)
- [ ] Received → Confirmed reversal (check inventory decreased)
- [ ] Confirmed → Sent reversal (check accounting entry deleted)

### Prepayment Model Flow
- [ ] Create invoice with Prepayment model
- [ ] Draft → Sent transition
- [ ] Sent → Confirmed transition (check accounting entry with Inventory on Order)
- [ ] Confirmed → Paid transition (check payment recorded before receipt)
- [ ] Paid → Received transition (check inventory + settlement entry)
- [ ] Received → Paid reversal (check inventory + settlement deleted)
- [ ] Paid → Confirmed reversal (check payment deleted)
- [ ] Confirmed → Sent reversal (check accounting entry deleted)

### Database Verification
- [ ] Check `journal_entries` created with correct accounts
- [ ] Check `stock_movements` created with correct type
- [ ] Check `products.inventory_qty` updated correctly
- [ ] Check DELETE-based reversals (no reversal entries created)
- [ ] Check payment tracking updates `paid_amount` and `balance`
- [ ] Check status auto-updates when payment added/removed

---

## 📊 Current Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Database Schema | ✅ Complete | Migration file ready |
| SQL Triggers | ✅ Complete | All 7 functions implemented |
| Dart Model | ✅ Complete | 5 statuses, all new fields |
| Service Methods | ✅ Complete | All transitions implemented |
| Model Selection Dialog | ✅ Complete | Beautiful UI, ready to use |
| List Page Updates | ⚠️ Partial | Need to wire up dialog + filters |
| Form Page Updates | ⚠️ Partial | Need to accept isPrepayment param |
| Detail Page | ❌ TODO | Most complex page |
| Payment Form Page | ❌ TODO | Separate page for payment entry |

---

## 🎯 Next Steps for Full Completion

1. **Wire up the model selection dialog** in list page FAB button
2. **Update form page** to accept and save `isPrepayment` parameter
3. **Create detail page** with full UI:
   - Status badges (5 colors)
   - Model badge (Prepago vs Estándar)
   - Timeline visualization
   - Conditional buttons (8 different button configurations)
   - Confirmation dialogs for all transitions
   - Payment list with delete option
4. **Create payment form page** for payment entry
5. **Add navigation** from list to detail page (click on invoice row)
6. **Test end-to-end** both workflows with real data

---

## 💡 Key Design Decisions

1. **Per-Invoice Model Selection**: Model chosen at creation via dialog (not global setting)
2. **DELETE-based Reversals**: Following Zoho Books approach (cleaner than REVERSAL entries)
3. **Automatic Status Updates**: Payment tracking trigger auto-updates status
4. **Two Accounting Flows**: Standard uses Inventory (1150), Prepayment uses Inventory on Order (1155)
5. **Inventory Safety**: Reversal checks for sufficient inventory before decreasing

---

## 📚 Reference Documentation

- **Standard Flow**: `.github/Purchase_Invoice_status_flow.md`
- **Prepayment Flow**: `.github/Purchase_Invoice_Prepayment_Flow.md`
- **Model Selection**: `.github/Purchase_Invoice_Model_Selection.md`
- **Service Extensions**: `lib/modules/purchases/services/purchase_service_extensions.dart`

---

## 🆘 Troubleshooting

**Issue: Migration fails**
- Check if columns already exist
- Use `ADD COLUMN IF NOT EXISTS` syntax
- Run diagnostic queries to verify state

**Issue: Triggers not firing**
- Check trigger exists: `SELECT * FROM pg_trigger WHERE tgname LIKE '%purchase%'`
- Check function exists: `SELECT proname FROM pg_proc WHERE proname LIKE '%purchase%'`
- Enable logging: Add `RAISE NOTICE` statements

**Issue: Accounting entries not created**
- Verify accounts exist (1150, 1155, 1140, 2120)
- Check journal_entries table for errors
- Look at Supabase logs

**Issue: Inventory not updating**
- Check stock_movements table for records
- Verify products.inventory_qty before/after
- Check for trigger errors in logs

---

**🎉 Ready to implement! The foundation is solid - just need to build the UI pages now!**
