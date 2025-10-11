## 🔧 Purchase Invoice Workflow Fixes - Summary

### Issues Fixed

1. **✅ Re-activation Bug**: When going from `draft` → `received` → `draft` → `received` again, the system now correctly creates a new purchase journal entry instead of just creating reversal entries.

2. **✅ Payment Journal Entries**: When marking a purchase invoice as "paid", the system now automatically:
   - Creates a payment record in the `purchase_payments` table
   - Generates the corresponding journal entry (Debit: Accounts Payable, Credit: Cash/Bank)
   - Updates the invoice's `paid_amount` and `balance` fields

3. **✅ Purchase Payments Page**: Added a new submenu under "Compras" called "Pagos" that displays:
   - All purchase invoice payments
   - Payment method, amount, date
   - Invoice number and supplier name
   - Reference and notes
   - Searchable and filterable

4. **✅ Sales Payments Enhancement**: The sales payments list now shows the invoice reference number next to each payment amount in a blue badge.

---

### 📂 New Files Created

1. **`supabase/sql/fix_purchase_workflow.sql`** - Complete SQL migration to fix all workflow issues
2. **`lib/modules/purchases/models/purchase_payment.dart`** - Data model for purchase payments
3. **`lib/modules/purchases/pages/purchase_payments_list_page.dart`** - UI for viewing purchase payments

### 📝 Files Modified

1. **`lib/modules/purchases/services/purchase_service.dart`**
   - Added purchase payments methods: `getPurchasePayments()`, `getPaymentsForInvoice()`, `createPayment()`, `deletePayment()`

2. **`lib/shared/routes/app_router.dart`**
   - Added route for `/purchases/payments`

3. **`lib/shared/widgets/main_layout.dart`**
   - Added "Pagos" menu item under "Compras" section

4. **`lib/modules/sales/pages/payment_form_page.dart`**
   - Enhanced payment display to show invoice reference number

---

### 🗄️ Database Changes (SQL Migration)

The migration file `fix_purchase_workflow.sql` includes:

#### New Table: `purchase_payments`
```sql
- id (UUID, primary key)
- invoice_id (UUID, references purchase_invoices)
- invoice_number (TEXT)
- supplier_name (TEXT)
- method (TEXT: cash, card, transfer, check, other)
- amount (NUMERIC)
- date (TIMESTAMP)
- reference (TEXT)
- notes (TEXT)
- created_at, updated_at
```

#### Updated Table: `purchase_invoices`
```sql
- Added: paid_amount (NUMERIC)
- Added: balance (NUMERIC)
```

#### New Functions:
1. **`create_purchase_invoice_journal_entry()`** - Fixed to check for active entries only (not reversed ones)
2. **`create_purchase_payment_journal_entry()`** - Creates journal entry when payment is recorded
3. **`recalculate_purchase_invoice_payments()`** - Updates invoice status based on payments
4. **`handle_purchase_payment_change()`** - Trigger function for payment changes
5. **`handle_purchase_invoice_paid()`** - Auto-creates payment when invoice marked as paid

#### New Triggers:
1. **`purchase_payment_change_trigger`** - Fires on INSERT/UPDATE/DELETE of payments
2. **`purchase_invoice_paid_trigger`** - Fires when invoice status changes to 'paid'

---

### 🚀 How to Apply the Fix

#### Step 1: Run the SQL Migration
1. Go to your **Supabase Dashboard**
2. Navigate to **SQL Editor**
3. Open the file: `supabase/sql/fix_purchase_workflow.sql`
4. Copy and paste the entire content
5. Click **Run**
6. Verify you see the success message: ✅ Purchase invoice workflow fixes applied successfully!

#### Step 2: Test the Workflow

**Test Re-activation:**
1. Create a new purchase invoice in "draft" status
2. Mark it as "received" → Check that inventory increases and journal entry is created
3. Revert to "draft" → Check that inventory decreases and reversal entry is created
4. Mark as "received" again → **NEW ENTRY SHOULD BE CREATED** (not just reversal)
5. Go to "Contabilidad" → "Asientos Contables" and verify you see:
   - Original "COMP-xxx" entry (reversed)
   - "REV-COMP-xxx" entry (reversal)
   - New "COMP-xxx" entry (posted) ✅

**Test Payment Journal Entries:**
1. Create a purchase invoice and mark it as "received"
2. Then mark it as "paid"
3. Go to "Compras" → "Pagos" and verify the payment appears
4. Go to "Contabilidad" → "Asientos Contables"
5. Find the "PAGO-xxx" entry with:
   - Debit: Cuentas por Pagar (2100/2101)
   - Credit: Caja/Banco (1100/1101)

**Test Purchase Payments Page:**
1. Click "Compras" → "Pagos" in the menu
2. Verify all purchase payments are listed
3. Test the search functionality
4. Check that amounts, dates, and references display correctly

**Test Sales Payments Enhancement:**
1. Go to "Ventas" → "Pagos"
2. Verify each payment shows the invoice number in a blue badge next to the amount

---

### 📊 Accounting Flow

#### Purchase Invoice Lifecycle:

**Draft → Received:**
```
Journal Entry Created:
  Debit:  Inventario (1105)         $subtotal
  Debit:  IVA Crédito (1180)        $iva
  Credit: Cuentas por Pagar (2101)  $total
  
Inventory Updated:
  +quantity units to stock
```

**Received → Draft (Reversal):**
```
Journal Entry Reversed:
  Original entry marked as "reversed"
  
Reversal Entry Created:
  Debit:  Cuentas por Pagar (2101)  $total
  Credit: Inventario (1105)         $subtotal
  Credit: IVA Crédito (1180)        $iva
  
Inventory Updated:
  -quantity units from stock
```

**Draft → Received (Re-activation):**
```
New Journal Entry Created:
  Debit:  Inventario (1105)         $subtotal
  Debit:  IVA Crédito (1180)        $iva
  Credit: Cuentas por Pagar (2101)  $total
  
Inventory Updated:
  +quantity units to stock
```

**Received → Paid:**
```
Payment Entry Created:
  Debit:  Cuentas por Pagar (2101)  $payment_amount
  Credit: Caja/Banco (1100/1101)    $payment_amount

Purchase Invoice Updated:
  paid_amount += $payment_amount
  balance = total - paid_amount
  status = 'paid' (if fully paid)
```

---

### 🎨 UI Enhancements

#### Purchase Payments Page
- **Location**: Compras → Pagos
- **Features**:
  - Real-time search
  - Total count and sum display
  - Color-coded payment methods
  - Shows invoice number and supplier
  - Displays payment reference and notes
  - Pull-to-refresh support

#### Sales Payments Page
- **Enhancement**: Invoice reference badge
- **Display**: Blue badge showing invoice number (e.g., "INV-001")
- **Position**: Next to payment amount in title row

---

### 🐛 Troubleshooting

**If re-activation still creates only reversals:**
- Verify the SQL migration ran successfully
- Check that `create_purchase_invoice_journal_entry()` function was updated
- Look for the line: `AND status = 'posted'` in the EXISTS query

**If payment journal entries are not created:**
- Check that accounts 2100/2101 (Accounts Payable) exist
- Check that accounts 1100/1101 (Cash/Bank) exist
- Verify `purchase_payment_change_trigger` is installed

**If purchase payments page is empty:**
- Run the SQL migration to create the `purchase_payments` table
- Mark an invoice as "paid" to auto-generate a payment
- Check Supabase logs for any errors

**If sales invoice reference doesn't show:**
- Verify the `invoice_reference` field is populated in `sales_payments` table
- This should be auto-filled by existing triggers

---

### ✅ Verification Checklist

- [ ] SQL migration executed successfully in Supabase
- [ ] New `purchase_payments` table exists
- [ ] `purchase_invoices` table has `paid_amount` and `balance` columns
- [ ] Re-activation creates new journal entry (not just reversal)
- [ ] Marking as "paid" creates payment record and journal entry
- [ ] "Pagos" menu item appears under "Compras"
- [ ] Purchase payments page loads and displays data
- [ ] Sales payments show invoice reference badge
- [ ] No compilation errors in Flutter app

---

### 📌 Next Steps

1. **Run the SQL migration** in Supabase (most important!)
2. **Restart your Flutter app** to load the new code
3. **Test each scenario** described above
4. **Verify accounting entries** are correct in the journal

---

### 💡 Additional Notes

- **Payment methods**: cash, card, transfer, check, other
- **Auto-payment**: When marking as "paid", system creates a "transfer" payment automatically
- **Audit trail**: Original entries are marked as "reversed" but never deleted
- **Balance tracking**: Invoice `balance` is always `total - paid_amount`
- **Status changes**: 
  - `paid_amount >= total` → status becomes "paid"
  - `paid_amount > 0 but < total` → status becomes "received"
  - `paid_amount = 0` → status stays as current (draft/received)

---

**Last Updated**: 2025-10-11  
**Migration File**: `supabase/sql/fix_purchase_workflow.sql`  
**Modules Affected**: Purchases, Accounting, Sales (payments display)
