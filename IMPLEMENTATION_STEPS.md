# 🚀 5-Status Purchase Invoice - Implementation Steps

## Step 1: Run SQL Migrations (5 minutes)

### 1.1 Open Supabase Dashboard
1. Go to https://supabase.com/dashboard
2. Select your project
3. Click **SQL Editor** in left sidebar

### 1.2 Run Schema Migration
1. Click **"New Query"**
2. Open file: [`supabase/sql/purchase_invoice_5status_migration.sql`](../supabase/sql/purchase_invoice_5status_migration.sql)
3. Copy **entire contents**
4. Paste into SQL Editor
5. Click **"Run"** ✅

### 1.3 Run Triggers Migration
1. Click **"New Query"** again
2. Open file: [`supabase/sql/purchase_invoice_triggers.sql`](../supabase/sql/purchase_invoice_triggers.sql)
3. Copy **entire contents**
4. Paste into SQL Editor
5. Click **"Run"** ✅

---

## Step 2: Create Account 1155 (2 minutes)

### Option A: Through Your App (Recommended)
1. Run your Flutter app
2. Navigate to **Accounting** → **Plan de Cuentas**
3. Click **"Nueva Cuenta"**
4. Fill in:
   - **Code**: `1155`
   - **Name**: `Inventario en Tránsito`
   - **Type**: `Asset` (Activo)
   - **Nature**: `Debit` (Deudor)
   - **Active**: ✅
5. Click **"Guardar"**

### Option B: Direct SQL
Run this in Supabase SQL Editor:
```sql
INSERT INTO accounts (code, name, account_type, nature, is_active)
VALUES ('1155', 'Inventario en Tránsito', 'asset', 'debit', true);
```

---

## Step 3: Test Standard Model (10 minutes)

### 3.1 Create Invoice
1. In app: **Purchases** → **Nueva factura**
2. **Dialog appears** → Select **"Pago Después de Recibir"** (blue)
3. Fill form and save

### 3.2 Process Through Statuses
1. Click invoice → Opens [`PurchaseInvoiceDetailPage`](../lib/modules/purchases/pages/purchase_invoice_detail_page.dart)
2. Click **"Enviar a Proveedor"** → Status: Sent
3. Click **"Confirmar Factura"** → Enter supplier invoice number → Status: Confirmed
4. Click **"Marcar como Recibida"** → Status: Received ✅

### 3.3 Verify Inventory
1. Go to **Inventory** → **Products**
2. ✅ Stock should have **increased**

### 3.4 Register Payment
1. Click **"Registrar Pago"** → Opens [`PurchasePaymentFormPage`](../lib/modules/purchases/pages/purchase_payment_form_page.dart)
2. Fill payment details:
   - Payment method
   - Bank account
   - Amount (pre-filled with balance)
   - Reference
3. Click **"Registrar Pago"** → Status: Paid ✅

### 3.5 Verify Accounting
1. Go to **Accounting** → **Asientos Contables**
2. Find entries with invoice reference
3. **Receipt entry**:
   - DR `1150` Inventario
   - DR `1140` IVA Crédito
   - CR `2120` Cuentas por Pagar
4. **Payment entry**:
   - DR `2120` Cuentas por Pagar
   - CR Bank Account

---

## Step 4: Test Prepayment Model (10 minutes)

### 4.1 Create Prepayment Invoice
1. **Purchases** → **Nueva factura**
2. **Dialog**: [`PurchaseModelSelectionDialog`](../lib/modules/purchases/widgets/purchase_model_selection_dialog.dart) → Select **"Pago Anticipado"** (orange)
3. Fill form and save

### 4.2 Check Model Badge
1. In invoice list: [`PurchaseInvoiceListPage`](../lib/modules/purchases/pages/purchase_invoice_list_page.dart)
2. ✅ Notice **orange "Prepago" badge**

### 4.3 Process to Paid
1. Click invoice → Send → Confirm
2. Click **"Registrar Pago"** → Fill details → Save
3. ✅ Status: Paid

### 4.4 Verify Prepayment Accounting
1. **Accounting** → **Asientos Contables**
2. **Payment entry** (when paid):
   - DR `1155` Inventario en Tránsito ⚠️ (not 1150!)
   - DR `1140` IVA Crédito
   - CR Bank Account

### 4.5 Receive Goods
1. Click **"Marcar como Recibida"** → Status: Received
2. ✅ Inventory increases

### 4.6 Verify Settlement Entry
1. **Accounting** → Find **second entry**
2. **Settlement entry**:
   - DR `1150` Inventario
   - CR `1155` Inventario en Tránsito ✅

---

## Step 5: Test Payment Form ⭐ (5 minutes)

### 5.1 Open Payment Form
1. Any invoice in Confirmed/Received status
2. Click **"Registrar Pago"**
3. Opens: [`purchase_payment_form_page.dart`](../lib/modules/purchases/pages/purchase_payment_form_page.dart)

### 5.2 Fill Payment Details
- **Date**: Select payment date
- **Amount**: Pre-filled with invoice balance
- **Payment Method**: Choose from dropdown
- **Bank Account**: Select account
- **Reference**: Optional (e.g., "Transfer #123")
- **Notes**: Optional

### 5.3 Verify Features
- ✅ Invoice summary shown at top
- ✅ Validation on amount
- ✅ Warning if amount > balance
- ✅ Bank accounts loaded from database

### 5.4 Save Payment
1. Click **"Registrar Pago"**
2. ✅ Payment saved to `purchase_payments` table
3. ✅ Journal entry created
4. ✅ Invoice status updated
5. ✅ Returns to detail page

---

## Step 6: Test Reversals (5 minutes)

### 6.1 Create Test Invoice
1. Standard model invoice
2. Process to Received status

### 6.2 Revert Backward
1. Detail page → Click **"Volver a Confirmada"**
2. Confirm dialog
3. ✅ Status: Confirmed

### 6.3 Verify DELETE-based Reversal
1. **Accounting** → Search invoice reference
2. ✅ Journal entry **DELETED** (not reversed!)
3. **Inventory** → Check stock
4. ✅ Stock **decreased** back to original

### 6.4 Test Multiple Reversals
1. From Confirmed → **"Volver a Enviada"**
2. From Sent → **"Volver a Borrador"**
3. ✅ All transitions work smoothly

### 6.5 Test Undo Payment
1. Process invoice to Paid
2. Click **"Deshacer Pago"**
3. ✅ Last payment deleted
4. ✅ Journal entry deleted
5. ✅ Status reverts to previous

---

## 📁 Key Files Reference

### Frontend Pages
- [`purchase_invoice_list_page.dart`](../lib/modules/purchases/pages/purchase_invoice_list_page.dart) - List with model selection
- [`purchase_invoice_form_page.dart`](../lib/modules/purchases/pages/purchase_invoice_form_page.dart) - Create/edit invoices
- [`purchase_invoice_detail_page.dart`](../lib/modules/purchases/pages/purchase_invoice_detail_page.dart) - Detail with timeline
- [`purchase_payment_form_page.dart`](../lib/modules/purchases/pages/purchase_payment_form_page.dart) - Payment registration ⭐

### Widgets
- [`purchase_model_selection_dialog.dart`](../lib/modules/purchases/widgets/purchase_model_selection_dialog.dart) - Model selection dialog

### Services
- [`purchase_service.dart`](../lib/modules/purchases/services/purchase_service.dart) - Business logic with 10 new methods

### Models
- [`purchase_invoice.dart`](../lib/modules/purchases/models/purchase_invoice.dart) - Data model with 8 new fields

### Database
- [`purchase_invoice_5status_migration.sql`](../supabase/sql/purchase_invoice_5status_migration.sql) - Schema changes
- [`purchase_invoice_triggers.sql`](../supabase/sql/purchase_invoice_triggers.sql) - Automation triggers

### Navigation
- [`app_router.dart`](../lib/shared/routes/app_router.dart) - Routing configuration

### Documentation
- [`QUICK_START_5STATUS.md`](../QUICK_START_5STATUS.md) - Quick setup guide
- [`PURCHASE_INVOICE_5STATUS_COMPLETE.md`](../PURCHASE_INVOICE_5STATUS_COMPLETE.md) - Complete reference
- [`PURCHASE_INVOICE_IMPLEMENTATION_GUIDE.md`](../PURCHASE_INVOICE_IMPLEMENTATION_GUIDE.md) - Technical details

---

## ✅ Success Checklist

After completing all steps, verify:

- [ ] Model selection dialog appears
- [ ] Can create Standard invoices (blue badge)
- [ ] Can create Prepayment invoices (orange badge)
- [ ] Timeline shows 5 steps
- [ ] Timeline order differs by model
- [ ] Buttons change based on status
- [ ] Payment form opens and works
- [ ] Inventory increases on receipt
- [ ] Journal entries created automatically
- [ ] Reversals DELETE entries (not reverse)
- [ ] Payment registration works
- [ ] No errors in console

---

## 🐛 Troubleshooting

| Issue | Solution | File to Check |
|-------|----------|---------------|
| Column doesn't exist | Run migration SQL | [`purchase_invoice_5status_migration.sql`](../supabase/sql/purchase_invoice_5status_migration.sql) |
| Function not found | Run triggers SQL | [`purchase_invoice_triggers.sql`](../supabase/sql/purchase_invoice_triggers.sql) |
| Account 1155 not found | Create account manually | See Step 2 above |
| Dialog not showing | Hard reload app | [`purchase_invoice_list_page.dart`](../lib/modules/purchases/pages/purchase_invoice_list_page.dart) |
| Payment form crashes | Check bank accounts exist | [`purchase_payment_form_page.dart`](../lib/modules/purchases/pages/purchase_payment_form_page.dart) |
| Inventory not updating | Check triggers | [`purchase_invoice_triggers.sql`](../supabase/sql/purchase_invoice_triggers.sql) |
| Service method error | Verify PurchaseService | [`purchase_service.dart`](../lib/modules/purchases/services/purchase_service.dart) |

---

## 🎯 What Each File Does

### Database Layer
- **`purchase_invoice_5status_migration.sql`**: Adds 9 columns (prepayment_model, dates, supplier info, payment tracking)
- **`purchase_invoice_triggers.sql`**: 7 SQL functions for automation (inventory, accounting, payments)

### Data Models
- **`purchase_invoice.dart`**: Invoice model with 8 new fields, 5-status enum

### Business Logic
- **`purchase_service.dart`**: 
  - `markInvoiceAsSent()` - Draft → Sent
  - `confirmInvoice()` - Sent → Confirmed
  - `markInvoiceAsReceived()` - Confirmed → Received
  - `registerInvoicePayment()` - Create payment
  - `undoLastPayment()` - Delete payment
  - `revertInvoiceTo*()` - Backward transitions (5 methods)

### UI Components
- **`purchase_invoice_list_page.dart`**: 
  - Model selection dialog integration
  - 5-status filters
  - Prepayment badges
  
- **`purchase_invoice_detail_page.dart`**:
  - 5-step timeline
  - 8 button configurations
  - Model-aware UI
  
- **`purchase_payment_form_page.dart`**:
  - Payment registration
  - Journal entry creation
  - Invoice status updates

- **`purchase_model_selection_dialog.dart`**:
  - Standard vs Prepayment choice
  - Visual model descriptions

### Navigation
- **`app_router.dart`**:
  - `/purchases/new?prepayment=true` - Create with model
  - `/purchases/:id/detail` - View detail
  - `/purchases/:id/edit` - Edit invoice

---

## 📊 Status Flow Reference

### Standard Model
```
Draft → Sent → Confirmed → Received → Paid
  ↓       ↓         ↓          ↓        ↓
  Delete  Delete    Delete    Delete   Delete
  (reversible at any point)
```

**Accounting**:
- Received: DR 1150, DR 1140, CR 2120
- Paid: DR 2120, CR Bank

### Prepayment Model
```
Draft → Sent → Confirmed → Paid → Received
  ↓       ↓         ↓        ↓       ↓
  Delete  Delete    Delete  Delete  Delete
  (reversible at any point)
```

**Accounting**:
- Paid: DR 1155, DR 1140, CR Bank
- Received: DR 1150, CR 1155

---

## 🎉 Ready to Deploy!

Once all tests pass:
1. Commit changes to git
2. Deploy to staging
3. Run integration tests
4. Deploy to production
5. Train users on new workflow

**Total implementation**: ~3,500 lines of code  
**Total setup time**: ~30 minutes  
**Result**: Production-grade purchase invoice system! 🚀
