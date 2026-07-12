# PURCHASE INVOICE STATUS FLOW — PREPAYMENT MODEL (PAGO ANTICIPADO)

## Overview

This document describes the **Prepayment Purchase Invoice Workflow** for businesses that pay suppliers in advance before receiving goods. This model reflects real-world scenarios where:
- Orders are sent to suppliers
- Suppliers confirm and issue digital invoices
- Payment is made upfront (wire transfer)
- Goods are delivered later and verified

This is an **alternative model** to the standard "Pay After Receipt" flow. **The model is selected at invoice creation time** via a dialog prompt, allowing each invoice to use whichever payment flow is appropriate for that specific supplier/order.

---

## 🔄 STATUS FLOW DIAGRAM

```
┌─────────────┐
│   BORRADOR  │ ← Initial state (Draft)
│   (draft)   │   • Order being prepared
└──────┬──────┘   • No accounting impact
       │          • No communication sent
       │
       │ ➡️ [Enviar a Proveedor]
       │    • Send order to supplier
       │    • No accounting impact
       │
       ⬇️
┌──────────────┐
│   ENVIADA    │ (Sent to Supplier)
│    (sent)    │  • Order sent, waiting confirmation
└──────┬───────┘  • No accounting impact yet
       │
       │ ⬅️ [Volver a Borrador]
       │    • Just status change
       │    • Cancel order
       │
       │ ➡️ [Confirmar Recepción Factura]
       │    • Supplier confirmed and issued invoice
       │    • Creates AP liability
       │
       ⬇️
┌───────────────┐
│  CONFIRMADA   │ (Confirmed - Invoice Received)
│ (confirmed)   │  • Supplier issued digital invoice
└──────┬────────┘  • AP liability recorded
       │           • Ready to pay
       │
       │ ⬅️ [Volver a Enviada]
       │    • Reverses AP entry
       │    • Supplier cancelled invoice
       │
       │ ➡️ [Registrar Pago]
       │    • Wire transfer made
       │    • Creates advance payment
       │
       ⬇️
┌──────────────┐
│    PAGADA    │ (Paid - Prepaid)
│    (paid)    │  • Money already sent
└──────┬───────┘  • Advance to supplier recorded
       │          • Waiting for goods delivery
       │
       │ ⬅️ [Volver a Confirmada]
       │    • Reverses payment (refund scenario)
       │    • Returns to payable status
       │
       │ ➡️ [Marcar como Recibida]
       │    • Goods delivered and verified
       │    • INCREASES inventory
       │    • Settles advance payment
       │
       ⬇️
┌──────────────┐
│  RECIBIDA    │ (Received - Goods in Stock)
│  (received)  │  • Products physically in store
└──────┬───────┘  • Inventory increased
       │          • Advance settled
       │          • COMPLETE ✅
       │
       │ ⬅️ [Volver a Pagada]
       │    • Goods returned to supplier
       │    • Reverses inventory
       │    • Returns to advance status
```

---

## 📊 STATUS DEFINITIONS

### 1. **Borrador** (Draft)
- **Spanish Label**: "Borrador"
- **Badge Color**: Grey (`Colors.grey[200]` / `Colors.grey[800]`)
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Purchase order is being prepared internally, not yet sent to supplier
- **Available Actions**:
  - ✏️ **[Editar]** button → Opens form in edit mode, allows full editing
  - ➡️ **[Enviar a Proveedor]** button → Triggers:
    - Status changes to 'sent'
    - Sets `sent_date` = NOW()
    - ❌ No accounting entries
    - ❌ No inventory changes
    - ❌ No SQL triggers
    - Frontend: `_sendToSupplier()` → `PurchaseService.updateInvoiceStatus()`
  - 🗑️ **[Eliminar]** button → Deletes invoice record completely from database

---

### 2. **Enviada** (Sent to Supplier)
- **Spanish Label**: "Enviada"
- **Badge Color**: Blue (`Colors.blue[100]` / `Colors.blue[800]`)
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Order sent to supplier, waiting for their confirmation and invoice issuance
- **Available Actions**:
  - ✏️ **[Editar]** button → Opens form in edit mode (if supplier hasn't confirmed yet)
  - ⬅️ **[Volver a Borrador]** button → Triggers:
    - Status changes to 'draft'
    - Clears `sent_date`
    - ❌ No accounting reversals (none exist)
    - ❌ No inventory changes
    - ❌ No SQL triggers
    - Frontend: `_revertToDraft()` → `PurchaseService.updateInvoiceStatus()`
  - ✅ **[Confirmar Recepción Factura]** button (Green/Purple) → Triggers:
    - Opens modal dialog to enter supplier invoice number and date
    - Status changes to 'confirmed'
    - Sets `confirmed_date` = NOW()
    - Sets `supplier_invoice_number` = user input
    - Sets `supplier_invoice_date` = user input
    - ✅ **SQL Trigger**: `handle_purchase_invoice_prepaid_change()`
    - ✅ **Accounting**: Creates journal entry via `create_prepaid_purchase_confirmation_entry()`
      - DR: Inventario en Tránsito (1155) $100,000
      - DR: IVA Crédito Fiscal (1140) $19,000
      - CR: Cuentas por Pagar (2120) $119,000
    - ❌ No inventory changes yet
    - Frontend: `_confirmSupplierInvoice()` → `PurchaseService.confirmSupplierInvoice()`

---

### 3. **Confirmada** (Confirmed - Invoice Issued by Supplier)
- **Spanish Label**: "Confirmada"
- **Badge Color**: Purple (`Colors.purple[100]` / `Colors.purple[800]`)
- **Accounting Effect**: ✅ AP liability recorded
  - **Debit**: Inventario (1105) $100,000
  - **Debit**: IVA Crédito Fiscal (1107) $19,000
  - **Credit**: Cuentas por Pagar (2101) $119,000
- **Inventory Effect**: ❌ None (not in stock yet)
- **Description**: Supplier has confirmed order and issued their digital invoice (factura electrónica)
- **Available Actions**:
  - ✏️ **[Editar]** button → Limited editing (accounting entry already exists, cannot modify amounts/items easily)
  - ⬅️ **[Volver a Enviada]** button → Triggers:
    - Shows confirmation dialog warning about deletion
    - Status changes to 'sent'
    - Clears `confirmed_date`, `supplier_invoice_number`, `supplier_invoice_date`
    - ✅ **SQL Trigger**: `handle_purchase_invoice_prepaid_change()`
    - ✅ **Accounting**: DELETES journal entry completely (Zoho Books style)
      - DELETE FROM journal_entries WHERE source_module = 'purchase_invoices' AND source_reference = invoice_id
      - journal_lines cascade deleted
      - Clean slate (as if never confirmed)
    - ❌ No inventory changes (wasn't received yet)
    - Frontend: `_revertToSent()` → `PurchaseService.revertToSent()`
  - 💰 **[Registrar Pago]** button (Orange) → Triggers:
    - Navigates to `PurchasePrepaymentFormPage`
    - User enters payment details (method, date, bank account, reference)
    - User clicks [Confirmar Pago Anticipado]
    - Status changes to 'paid'
    - Sets `paid_date` = payment date
    - Sets `paid_amount` = invoice total
    - Sets `balance` = 0
    - ✅ **SQL Trigger**: `recalculate_purchase_invoice_payments()`
    - ✅ **Accounting**: Creates payment entry via `create_prepaid_purchase_payment_entry()`
      - Entry number: PAGO-PREPAID-XXX
      - DR: Cuentas por Pagar (2120) $119,000
      - CR: Banco (1101) or Caja (1110) $119,000
    - ❌ No inventory changes yet
    - Frontend: `_navigateToPrepayment()` → `PurchaseService.registerPrepayment()`

---

### 4. **Pagada** (Paid - Prepaid)
- **Spanish Label**: "Pagada"
- **Badge Color**: Orange/Amber (`Colors.orange[100]` / `Colors.orange[800]`)
- **Accounting Effect**: ✅ Payment recorded
  - **Debit**: Cuentas por Pagar (2120) $119,000 (settles liability)
  - **Credit**: Banco (1101) $119,000 (money out)
  - **Net Balance**: AP = $0, Inventario en Tránsito = $100k DR (asset on order)
- **Inventory Effect**: ❌ None (still waiting for goods)
- **Description**: Payment sent to supplier via wire transfer, waiting for goods delivery
- **Available Actions**:
  - 📦 **[Marcar como Recibida]** button (Green) → Triggers:
    - Shows verification dialog with checklist (products match, quantities correct, condition OK)
    - Status changes to 'received'
    - Sets `received_date` = NOW()
    - ✅ **SQL Trigger**: `handle_purchase_invoice_prepaid_change()`
    - ✅ **Inventory**: Creates stock via `consume_purchase_invoice_inventory()`
      - For each product:
        - INSERT `stock_movements`: type='IN', movement_type='purchase_invoice_prepaid'
        - UPDATE `products.inventory_qty` += quantity
    - ✅ **Accounting**: Settles inventory via `settle_prepaid_inventory_on_order()`
      - Entry number: RECEP-XXX
      - DR: Inventario (1150) $100,000 (goods now in stock)
      - CR: Inventario en Tránsito (1155) $100,000 (clear "on order")
      - IVA stays in IVA Crédito (1140) unchanged
    - Frontend: `_markAsReceived()` → `PurchaseService.markPrepaidAsReceived()`
  - ⬅️ **[Volver a Confirmada]** button (Grey) → Triggers:
    - Shows confirmation dialog for refund/cancellation scenario
    - Status changes to 'confirmed'
    - Clears `paid_date`, `paid_amount`, sets `balance` = total
    - ✅ **SQL Trigger**: `recalculate_purchase_invoice_payments()` on DELETE
    - ✅ **Accounting**: DELETES payment entry and its journal lines
      - Removes PAGO-PREPAID-XXX entry completely
      - AP liability restored to $119,000 CR
    - ❌ No inventory changes (wasn't received yet)
    - Frontend: `_revertToConfirmed()` → `PurchaseService.deletePayment()`

---

### 5. **Recibida** (Received - Goods in Stock)
- **Spanish Label**: "Recibida"
- **Badge Color**: Green (`Colors.green[100]` / `Colors.green[800]`)
- **Accounting Effect**: ✅ Inventory settled
  - **Debit**: Inventario (1150) $100,000 (goods in stock)
  - **Credit**: Inventario en Tránsito (1155) $100,000 (settled)
  - **Final Balance Sheet**: 
    - Inventario (1150): +$100k DR
    - IVA Crédito Fiscal (1140): +$19k DR
    - Banco (1101): -$119k CR (paid earlier)
    - Net: $100k inventory + $19k tax credit, paid $119k cash
- **Inventory Effect**: ✅ Stock INCREASED
  - `products.inventory_qty` increased for all items
  - `stock_movements` records created (type='IN', movement_type='purchase_invoice_prepaid')
- **Description**: Products delivered, counted, and verified against invoice. Stock updated. **PROCESS COMPLETE**
- **Available Actions**:
  - ✏️ **[Ver Detalles Completos]** button → View-only mode, shows complete purchase timeline
  - 🖨️ **[Imprimir Resumen]** button → Generates printable summary of entire prepaid purchase
  - ⬅️ **[Volver a Pagada]** button (Grey, for returns only) → Triggers:
    - Shows confirmation dialog: "Devolver productos recibidos"
    - Status changes to 'paid'
    - Clears `received_date`
    - ✅ **SQL Trigger**: `handle_purchase_invoice_prepaid_change()`
    - ✅ **Inventory**: Reverses via `reverse_purchase_invoice_inventory()`
      - Checks if sufficient inventory exists (throws error if not)
      - For each product:
        - UPDATE `products.inventory_qty` -= quantity
        - DELETE `stock_movements` records (movement_type='purchase_invoice_prepaid')
    - ✅ **Accounting**: Settlement entry DELETED (Zoho Books style)
      - DELETE FROM journal_entries WHERE source_module = 'purchase_invoices' AND entry_type = 'purchase_receipt'
      - journal_lines cascade deleted
      - Clean removal (as if goods were never received)
    - Error if ANY product has insufficient inventory
    - Frontend: `_revertToPaid()` → `PurchaseService.revertToPaid()`

---

## 🔀 STATUS TRANSITIONS

### Forward Transitions

#### **Borrador → Enviada**

**User Interaction**:
1. User opens purchase invoice detail page
2. Sees status badge: Grey "Borrador"
3. Clicks blue button **[Enviar a Proveedor]**

**Frontend Action** (`PurchaseInvoiceFormPage` - Prepayment Mode):
```dart
void _sendToSupplier() async {
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.updateInvoiceStatus(
      widget.invoiceId,
      'sent',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Orden enviada al proveedor')),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error al enviar orden: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Effect**:
```dart
// PurchaseService.updateInvoiceStatus()
Future<void> updateInvoiceStatus(int invoiceId, String newStatus) async {
  await _supabase
      .from('purchase_invoices')
      .update({
        'status': newStatus,
        'sent_date': DateTime.now().toIso8601String(),
      })
      .eq('id', invoiceId);
}
```

**SQL Trigger**: ❌ None (simple status update)

**Database Changes**:
- `purchase_invoices.status` = 'sent'
- `purchase_invoices.sent_date` = NOW()
- ❌ No journal entries created
- ❌ No inventory changes

**GUI Update**:
- Badge changes to blue **"Enviada"**
- Buttons visible:
  - **[Editar]** (outlined)
  - **[Volver a Borrador]** (outlined, grey)
  - **[Confirmar Recepción Factura]** (filled, purple) ← Primary action
- SnackBar: "Orden enviada al proveedor"
```
User Action: Click "Enviar a Proveedor"
Backend Effect:
  • Status = 'sent'
  • sent_date = NOW()
  • ❌ No journal entry
  • ❌ No inventory change
SQL Trigger: None (simple status update)
GUI Update:
  • Badge changes to blue "Enviada"
  • Buttons: [Editar] [Volver a Borrador] [Confirmar Recepción Factura]
  • SnackBar: "Orden enviada al proveedor"
```

#### **Enviada → Confirmada**

**User Interaction**:
1. User sees status badge: Blue "Enviada"
2. Supplier confirms order and issues digital invoice (factura electrónica)
3. User clicks purple button **[Confirmar Recepción Factura]**
4. Modal dialog appears:
   - Title: "Confirmar factura del proveedor"
   - Fields:
     - **Número de Factura** (Supplier's invoice number) - Required
     - **Fecha de Factura** (Invoice date) - Required, datepicker
     - **RUT Proveedor** (auto-filled from supplier)
     - **Monto Total** (auto-filled, readonly)
   - Buttons: [Cancelar] [Confirmar y Crear Pasivo]

**Frontend Action**:
```dart
void _confirmSupplierInvoice() async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => ConfirmSupplierInvoiceDialog(
      supplierId: _invoice.supplierId,
      total: _invoice.total,
    ),
  );
  
  if (result == null) return; // User cancelled
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.confirmSupplierInvoice(
      invoiceId: widget.invoiceId,
      supplierInvoiceNumber: result['invoiceNumber'],
      supplierInvoiceDate: result['invoiceDate'],
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Factura confirmada - pasivo registrado (AP)'),
          backgroundColor: Colors.purple,
        ),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error al confirmar factura: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service**:
```dart
// PurchaseService.confirmSupplierInvoice()
Future<void> confirmSupplierInvoice({
  required int invoiceId,
  required String supplierInvoiceNumber,
  required DateTime supplierInvoiceDate,
}) async {
  await _supabase.from('purchase_invoices').update({
    'status': 'confirmed',
    'supplier_invoice_number': supplierInvoiceNumber,
    'supplier_invoice_date': supplierInvoiceDate.toIso8601String(),
    'confirmed_date': DateTime.now().toIso8601String(),
  }).eq('id', invoiceId);
  
  // Trigger will create journal entry
}
```

**SQL Trigger**: ✅ `handle_purchase_invoice_prepaid_change()`

**Trigger Logic** (integrated into main purchase trigger):
```sql
-- In handle_purchase_invoice_change():
-- Prepayment model uses same trigger, but different account codes
IF TG_OP = 'UPDATE' THEN
  v_old_status := lower(trim(OLD.status));
  v_new_status := lower(trim(NEW.status));
  v_old_posted := NOT (v_old_status = ANY(v_non_posted));
  v_new_posted := NOT (v_new_status = ANY(v_non_posted));
  
  -- For prepayment: Confirmada creates entry with Inventory on Order (1155)
  IF NOT v_old_posted AND v_new_posted AND NEW.prepayment_model = true THEN
    PERFORM public.create_prepaid_purchase_confirmation_entry(NEW);
  END IF;
END IF;
```

**Journal Entry Function** (following core_schema.sql pattern):
```sql
CREATE OR REPLACE FUNCTION public.create_prepaid_purchase_confirmation_entry(p_invoice public.purchase_invoices)
RETURNS VOID AS $$
DECLARE
  v_entry_id INTEGER;
  v_inventory_transit_id INTEGER;
  v_iva_account_id INTEGER;
  v_ap_account_id INTEGER;
  v_supplier_name TEXT;
BEGIN
  -- Check if entry already exists
  IF EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE source_module = 'purchase_invoices'
      AND source_reference = p_invoice.id::text
  ) THEN
    RETURN;
  END IF;
  
  -- Get supplier name
  SELECT name INTO v_supplier_name
  FROM public.suppliers
  WHERE id = p_invoice.supplier_id;
  
  -- Ensure accounts exist
  v_inventory_transit_id := public.ensure_account('1155', 'Inventario en Tránsito');
  v_iva_account_id := public.ensure_account('1107', 'IVA Crédito Fiscal');
  v_ap_account_id := public.ensure_account('2101', 'Cuentas por Pagar');
  
  -- Create journal entry
  INSERT INTO public.journal_entries (
    entry_number,
    entry_date,
    entry_type,
    status,
    source_module,
    source_reference,
    notes
  ) VALUES (
    'CONF-COMP-' || p_invoice.invoice_number,
    p_invoice.date,
    'purchase_confirmation',
    'posted',
    'purchase_invoices',
    p_invoice.id::text,
    'Confirmación factura proveedor ' || 
    COALESCE(p_invoice.supplier_invoice_number, p_invoice.invoice_number) ||
    CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END
  ) RETURNING id INTO v_entry_id;
  
  -- Create journal lines (Prepayment uses Inventory on Order - 1155)
  INSERT INTO public.journal_lines (entry_id, account_id, debit_amount, credit_amount, description)
  VALUES
    -- DR: Inventory on Order (1155) - goods expected
    (v_entry_id, v_inventory_transit_id, p_invoice.subtotal, 0, 
     'Inventario en tránsito - FC ' || p_invoice.invoice_number),
    -- DR: IVA Crédito Fiscal (1107)
    (v_entry_id, v_iva_account_id, p_invoice.iva_amount, 0, 
     'IVA Crédito Fiscal'),
    -- CR: Accounts Payable (2101)
    (v_entry_id, v_ap_account_id, 0, p_invoice.total, 
     'Pasivo proveedor' || 
     CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END);
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- `purchase_invoices.status` = 'confirmed'
- `purchase_invoices.supplier_invoice_number` = entered value
- `purchase_invoices.supplier_invoice_date` = entered date
- `purchase_invoices.confirmed_date` = NOW()
- ✅ `journal_entries` record created (entry_type='purchase_confirmation')
- ✅ `journal_lines` records created:
  - DR: Inventario en Tránsito (1155) $100,000
  - DR: IVA Crédito Fiscal (1140) $19,000
  - CR: Cuentas por Pagar (2120) $119,000
- ❌ NO inventory changes yet (products not received)

**GUI Update**:
- Badge changes to purple **"Confirmada"**
- Shows supplier invoice info:
  - "Factura Proveedor: #12345"
  - "Fecha Factura: 12/10/2025"
  - "Pasivo Registrado: $119,000 CLP"
- Buttons visible:
  - **[Ver Factura]** (outlined, view supplier invoice)
  - **[Volver a Enviada]** (outlined, grey)
  - **[Registrar Pago]** (filled, orange/amber) ← Primary action
- SnackBar: "Factura confirmada - pasivo registrado (AP)"
```
User Action: Click "Confirmar Recepción Factura"
  (User enters supplier's invoice number and date)
Backend Effect:
  • Status = 'confirmed'
  • confirmed_date = NOW()
  • supplier_invoice_number = user_input
  • ✅ Journal entry CREATED (AP liability)
  • ❌ No inventory change yet
SQL Trigger: handle_purchase_invoice_change()
  → create_purchase_invoice_ap_entry()
GUI Update:
  • Badge changes to purple "Confirmada"
  • Buttons: [Editar] [Volver a Enviada] [Registrar Pago]
  • SnackBar: "Factura confirmada - pasivo registrado"
  • Shows: Supplier invoice #, Amount payable
```

#### **Confirmada → Pagada**

**User Interaction**:
1. User sees status badge: Purple "Confirmada"
2. User clicks orange button **[Registrar Pago]**
3. Navigates to **Prepaid Payment Form Page**
4. User fills payment form:
   - **Método de Pago**: Transferencia, Cheque, Efectivo (dropdown)
   - **Monto**: Auto-filled with invoice total (readonly in prepayment)
   - **Fecha de Pago**: Datepicker (defaults to today)
   - **Cuenta Bancaria**: Dropdown (if Transferencia/Cheque)
   - **Número de Transferencia/Cheque**: Text field
   - **Referencia**: Text field (e.g., "Pago anticipo proveedor X")
   - **Notas**: Text area (optional)
5. Clicks **[Confirmar Pago Anticipado]** button

**Frontend Navigation**:
```dart
void _navigateToPrepayment() async {
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PurchasePrepaymentFormPage(
        invoiceId: widget.invoiceId,
        supplierId: _invoice.supplierId,
        supplierName: _invoice.supplierName,
        invoiceTotal: _invoice.total,
        supplierInvoiceNumber: _invoice.supplierInvoiceNumber,
      ),
    ),
  );
  
  if (result == true) {
    _loadInvoice(); // Refresh
  }
}
```

**Payment Form Page**:
```dart
// PurchasePrepaymentFormPage
void _confirmPrepayment() async {
  if (!_formKey.currentState!.validate()) return;
  
  // Confirmation dialog for prepayment
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Confirmar pago anticipado'),
      content: Text(
        '⚠️ Está a punto de PAGAR \$${_invoice.total.toStringAsFixed(0)} CLP '
        'al proveedor ${widget.supplierName}.\n\n'
        'Los productos AÚN NO han sido recibidos.\n\n'
        '¿Proceder con el pago anticipado?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: Text('Sí, Pagar Ahora'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.registerPrepayment(
      invoiceId: widget.invoiceId,
      amount: _invoice.total, // Full amount
      paymentMethod: _selectedMethod,
      paymentDate: _selectedDate,
      bankAccountId: _selectedBankAccountId,
      reference: _referenceController.text,
      checkNumber: _checkNumberController.text,
      notes: _notesController.text,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pago anticipado registrado - esperando entrega'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error al registrar pago: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service**:
```dart
// PurchaseService.registerPrepayment()
Future<void> registerPrepayment({
  required int invoiceId,
  required double amount,
  required String paymentMethod,
  required DateTime paymentDate,
  int? bankAccountId,
  String? reference,
  String? checkNumber,
  String? notes,
}) async {
  await _supabase.from('purchase_payments').insert({
    'purchase_invoice_id': invoiceId,
    'amount': amount,
    'payment_method': paymentMethod,
    'payment_date': paymentDate.toIso8601String(),
    'bank_account_id': bankAccountId,
    'reference': reference,
    'check_number': checkNumber,
    'notes': notes,
    'is_prepayment': true, // Flag for prepayment
  });
  
  // Trigger will create payment entry and update status
}
```

**SQL Trigger**: ✅ `recalculate_purchase_invoice_payments()`

**Trigger Logic** (same as standard, but aware of prepayment):
```sql
CREATE OR REPLACE FUNCTION recalculate_purchase_invoice_payments()
RETURNS TRIGGER AS $$
DECLARE
  v_invoice_id INTEGER;
  v_total_paid NUMERIC;
  v_invoice_total NUMERIC;
  v_is_prepaid BOOLEAN;
BEGIN
  v_invoice_id := COALESCE(NEW.purchase_invoice_id, OLD.purchase_invoice_id);
  
  -- Get invoice data
  SELECT total, prepayment_model INTO v_invoice_total, v_is_prepaid
  FROM purchase_invoices
  WHERE id = v_invoice_id;
  
  -- Calculate total paid
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM purchase_payments
  WHERE purchase_invoice_id = v_invoice_id;
  
  -- Update invoice
  IF v_total_paid >= v_invoice_total THEN
    UPDATE purchase_invoices
    SET 
      status = 'paid',
      paid_amount = v_total_paid,
      balance = 0,
      paid_date = (SELECT MAX(payment_date) FROM purchase_payments WHERE purchase_invoice_id = v_invoice_id)
    WHERE id = v_invoice_id;
  ELSE
    UPDATE purchase_invoices
    SET 
      paid_amount = v_total_paid,
      balance = v_invoice_total - v_total_paid
    WHERE id = v_invoice_id;
  END IF;
  
  -- Create payment journal entry
  IF TG_OP = 'INSERT' THEN
    PERFORM create_prepaid_purchase_payment_entry(NEW.id);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Payment Journal Entry Function**:
```sql
CREATE OR REPLACE FUNCTION create_prepaid_purchase_payment_entry(p_payment_id INTEGER)
RETURNS VOID AS $$
DECLARE
  v_payment RECORD;
  v_invoice RECORD;
  v_entry_id INTEGER;
  v_bank_account_id INTEGER;
BEGIN
  -- Get payment and invoice data
  SELECT 
    p.*,
    i.invoice_number,
    i.supplier_id
  INTO v_payment
  FROM purchase_payments p
  JOIN purchase_invoices i ON p.purchase_invoice_id = i.id
  WHERE p.id = p_payment_id;
  
  -- Determine bank account
  IF v_payment.payment_method IN ('Transferencia', 'Cheque') THEN
    v_bank_account_id := v_payment.bank_account_id;
  ELSE
    v_bank_account_id := (SELECT id FROM accounts WHERE code = '1110'); -- Caja
  END IF;
  
  -- Create journal entry
  INSERT INTO journal_entries (
    entry_number,
    entry_date,
    entry_type,
    status,
    source_module,
    source_reference,
    notes
  ) VALUES (
    'PAGO-PREPAID-' || v_payment.invoice_number,
    v_payment.payment_date,
    'prepayment',
    'posted',
    'purchase_payments',
    p_payment_id,
    'Pago anticipado factura ' || v_payment.invoice_number || ' - ' || v_payment.payment_method
  ) RETURNING id INTO v_entry_id;
  
  -- Journal lines
  INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description)
  VALUES
    -- DR: Accounts Payable (settle the liability)
    (v_entry_id, 
     (SELECT id FROM accounts WHERE code = '2120'), 
     v_payment.amount, 0, 
     'Pago anticipado proveedor'),
    -- CR: Bank/Cash (money out)
    (v_entry_id, 
     v_bank_account_id, 
     0, v_payment.amount, 
     'Salida ' || v_payment.payment_method || COALESCE(' #' || v_payment.check_number, ''));
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- ✅ `purchase_payments` record created (is_prepayment=true)
- `purchase_invoices.status` = 'paid'
- `purchase_invoices.paid_amount` = payment amount
- `purchase_invoices.balance` = 0
- `purchase_invoices.paid_date` = payment date
- ✅ `journal_entries` record created (entry_type='prepayment')
- ✅ `journal_lines` records created:
  - DR: Cuentas por Pagar (2120) $119,000
  - CR: Banco (1101) or Caja (1110) $119,000
- ❌ NO inventory changes (products not received yet)

**Accounting Status After Payment**:
```
Current balances:
  1155 Inventario en Tránsito: +$100,000 DR
  1140 IVA Crédito Fiscal: +$19,000 DR
  2120 Cuentas por Pagar: $0 (was $119,000 CR, now settled)
  1101 Banco: -$119,000 CR (money paid out)
  
→ Net: We have a $100k asset "on order" + $19k IVA credit, paid in cash
```

**GUI Update**:
- Badge changes to orange **"Pagada"**
- Shows payment information:
  - "⚠️ Pago Anticipado Realizado"
  - "Método: Transferencia"
  - "Monto: $119,000 CLP"
  - "Fecha: 12/10/2025"
  - "Estado: Esperando Entrega de Productos"
- Buttons visible:
  - **[Ver Comprobante]** (outlined, view payment details)
  - **[Volver a Confirmada]** (outlined, grey, for cancellation)
  - **[Marcar como Recibida]** (filled, green) ← Primary action (waiting for delivery)
- SnackBar: "Pago anticipado registrado - esperando entrega"
```
User Action: Click "Registrar Pago"
  → Payment form (amount, date, bank account, reference)
  → Click "Confirmar Pago"
Backend Effect:
  • Status = 'paid'
  • paid_date = NOW()
  • payment_method = user_input
  • payment_reference = user_input
  • ✅ Payment journal entry CREATED
  • ❌ No inventory change
SQL Trigger: handle_purchase_payment()
  → create_purchase_payment_entry()
GUI Update:
  • Badge changes to orange "Pagada"
  • Buttons: [Marcar como Recibida] [Volver a Confirmada]
  • SnackBar: "Pago registrado - esperando entrega"
  • Shows: Payment date, method, waiting for delivery
```

#### **Pagada → Recibida**

**User Interaction**:
1. User sees status badge: Orange "Pagada"
2. Warning message: "⚠️ Pago anticipado realizado - Esperando entrega de productos"
3. Supplier delivers products to store
4. User clicks green button **[Marcar como Recibida]**
5. **Verification Dialog** appears:
   - Title: "Confirmar recepción de productos"
   - Content:
     - "¿Los productos fueron entregados físicamente en la tienda?"
     - Checklist of items to verify:
       - ✓ Productos coinciden con factura
       - ✓ Cantidades correctas
       - ✓ Condición física adecuada
       - ✓ Embalaje intacto
     - Note: "Esto aumentará el inventario y completará el proceso de compra prepagada."
   - Buttons: [Cancelar] [Confirmar Recepción]

**Frontend Action**:
```dart
void _markAsReceived() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Confirmar recepción de productos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Los productos fueron entregados físicamente en la tienda?\n'),
          Text('Verifique:', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(children: [Icon(Icons.check_circle_outline, size: 16), SizedBox(width: 4), Text('Productos coinciden con factura')]),
          Row(children: [Icon(Icons.check_circle_outline, size: 16), SizedBox(width: 4), Text('Cantidades correctas')]),
          Row(children: [Icon(Icons.check_circle_outline, size: 16), SizedBox(width: 4), Text('Condición física adecuada')]),
          Row(children: [Icon(Icons.check_circle_outline, size: 16), SizedBox(width: 4), Text('Embalaje intacto')]),
          SizedBox(height: 12),
          Text(
            'Esto aumentará el inventario y completará el proceso de compra prepagada.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: Text('Confirmar Recepción'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.markPrepaidAsReceived(widget.invoiceId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Productos recibidos - inventario actualizado - compra completada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error al marcar como recibida: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service**:
```dart
// PurchaseService.markPrepaidAsReceived()
Future<void> markPrepaidAsReceived(int invoiceId) async {
  await _supabase.from('purchase_invoices').update({
    'status': 'received',
    'received_date': DateTime.now().toIso8601String(),
  }).eq('id', invoiceId);
  
  // Trigger will handle inventory and settlement entry
}
```

**SQL Trigger**: ✅ `handle_purchase_invoice_prepaid_change()`

**Trigger Logic**:
```sql
IF (TG_OP = 'UPDATE' 
    AND OLD.status != 'received' 
    AND NEW.status = 'received'
    AND NEW.prepayment_model = true) THEN
  
  -- Increase inventory
  PERFORM consume_purchase_invoice_inventory(NEW.id);
  
  -- Settle Inventory on Order to Inventory (Option A)
  PERFORM settle_prepaid_inventory_on_order(NEW.id);
END IF;
```

**Inventory Function** (same as standard):
```sql
CREATE OR REPLACE FUNCTION consume_purchase_invoice_inventory(p_invoice_id INTEGER)
RETURNS VOID AS $$
DECLARE
  v_item RECORD;
  v_invoice RECORD;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice FROM purchase_invoices WHERE id = p_invoice_id;
  
  -- Loop through items
  FOR v_item IN 
    SELECT product_id, quantity 
    FROM purchase_invoice_items 
    WHERE purchase_invoice_id = p_invoice_id
  LOOP
    -- Create stock movement (IN)
    INSERT INTO stock_movements (
      product_id,
      quantity,
      type,
      movement_type,
      reference,
      notes,
      created_at
    ) VALUES (
      v_item.product_id,
      v_item.quantity,
      'IN',
      CASE WHEN v_invoice.prepayment_model THEN 'purchase_invoice_prepaid' 
           ELSE 'purchase_invoice' END,
      p_invoice_id,
      'Recepción compra ' || v_invoice.invoice_number,
      NOW()
    );
    
    -- Increase product inventory
    UPDATE products
    SET 
      inventory_qty = inventory_qty + v_item.quantity,
      updated_at = NOW()
    WHERE id = v_item.product_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
```

**Settlement Function** (Option A - Inventory on Order):
```sql
CREATE OR REPLACE FUNCTION settle_prepaid_inventory_on_order(p_invoice_id INTEGER)
RETURNS VOID AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id INTEGER;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice FROM purchase_invoices WHERE id = p_invoice_id;
  
  -- Create settlement journal entry
  INSERT INTO journal_entries (
    entry_number,
    entry_date,
    entry_type,
    status,
    source_module,
    source_reference,
    notes
  ) VALUES (
    'RECEP-' || v_invoice.invoice_number,
    v_invoice.received_date,
    'purchase_receipt',
    'posted',
    'purchase_invoices',
    p_invoice_id,
    'Recepción productos prepagados - factura ' || v_invoice.supplier_invoice_number
  ) RETURNING id INTO v_entry_id;
  
  -- Settlement lines: Move from "on order" to "in stock"
  INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description)
  VALUES
    -- DR: Inventario (1150) - goods now in stock
    (v_entry_id, 
     (SELECT id FROM accounts WHERE code = '1150'), 
     v_invoice.subtotal, 0, 
     'Inventario recibido'),
    -- CR: Inventario en Tránsito (1155) - clear the "on order"
    (v_entry_id, 
     (SELECT id FROM accounts WHERE code = '1155'), 
     0, v_invoice.subtotal, 
     'Liquidación inventario en tránsito');
  
  -- Note: IVA stays in IVA Crédito (1140) - no change needed
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- `purchase_invoices.status` = 'received'
- `purchase_invoices.received_date` = NOW()
- ✅ `stock_movements` records created (type='IN', movement_type='purchase_invoice_prepaid')
- ✅ `products.inventory_qty` INCREASED for each item
- ✅ `journal_entries` record created (entry_type='purchase_receipt')
- ✅ `journal_lines` records created:
  - DR: Inventario (1150) $100,000
  - CR: Inventario en Tránsito (1155) $100,000

**Final Accounting Status**:
```
After receipt settlement:
  1150 Inventario: +$100,000 DR (goods in stock)
  1140 IVA Crédito Fiscal: +$19,000 DR (can offset tax)
  1155 Inventario en Tránsito: $0 (settled)
  2120 Cuentas por Pagar: $0 (already paid)
  1101 Banco: -$119,000 CR (paid earlier)
  
→ Net: We have $100k inventory + $19k IVA credit, paid $119k cash
→ Complete prepaid purchase cycle finished!
```

**GUI Update**:
- Badge changes to green **"Recibida"**
- Shows completion information:
  - "✅ Compra Completada"
  - "Productos Recibidos: 12/10/2025"
  - "Inventario Actualizado"
  - "Pago Realizado: 10/10/2025 ($119,000 CLP)"
- Timeline view showing all statuses:
  1. ✅ Borrador → Enviada (08/10/2025)
  2. ✅ Enviada → Confirmada (09/10/2025)
  3. ✅ Confirmada → Pagada (10/10/2025) - PREPAGO
  4. ✅ Pagada → Recibida (12/10/2025)
- Buttons visible:
  - **[Ver Detalles Completos]** (outlined)
  - **[Imprimir Resumen]** (outlined)
  - **[Volver a Pagada]** (outlined, grey, for returns only)
- SnackBar: "✅ Productos recibidos - inventario actualizado - compra completada"
```
User Action: Click "Marcar como Recibida"
  → Verification form (count products, verify quantities)
  → Click "Confirmar Recepción"
Backend Effect:
  • Status = 'received'
  • received_date = NOW()
  • ✅ Inventory INCREASED
  • Stock movements created (type='IN')
  • ✅ Settlement entry (if using Inventory on Order account)
SQL Trigger: handle_purchase_receipt()
  → consume_purchase_invoice_inventory()
  → settle_inventory_on_order() [Optional]
GUI Update:
  • Badge changes to green "Recibida"
  • Buttons: [Ver Detalles] [Volver a Pagada]
  • SnackBar: "Productos recibidos - inventario actualizado"
  • Shows: Received date, stock updated
```

---

### Backward Transitions (Reversals)

#### **Enviada → Borrador**
```
User Action: Click "Volver a Borrador"
Confirmation Dialog:
  Title: "Cancelar orden enviada"
  Message: "¿Volver esta orden a BORRADOR?
  
  Esto cancelará la orden enviada al proveedor.
  ¿Continuar?"
Backend Effect:
  • Status = 'draft'
  • sent_date = NULL
  • ❌ No accounting changes
  • ❌ No inventory changes
SQL Trigger: None
GUI Update:
  • Badge changes to grey "Borrador"
  • Buttons: [Editar] [Enviar a Proveedor] [Eliminar]
  • SnackBar: "Orden revertida a borrador"
```

#### **Confirmada → Enviada**
```
User Action: Click "Volver a Enviada"
Confirmation Dialog:
  Title: "Cancelar factura confirmada"
  Message: "¿Volver esta factura a ENVIADA?
  
  Esto eliminará el registro del pasivo contable.
  Úselo solo si el proveedor canceló su factura.
  ¿Continuar?"
Backend Effect:
  • Status = 'sent'
  • confirmed_date = NULL
  • supplier_invoice_number = NULL
  • ✅ AP entry DELETED or REVERSED
  • ❌ No inventory changes
SQL Trigger: handle_purchase_invoice_reversal()
  → delete_or_reverse_ap_entry()
GUI Update:
  • Badge changes to blue "Enviada"
  • Buttons: [Editar] [Volver a Borrador] [Confirmar Recepción Factura]
  • SnackBar: "Factura revertida - pasivo eliminado"
```

#### **Pagada → Confirmada**
```
User Action: Click "Volver a Confirmada"
Confirmation Dialog:
  Title: "Revertir pago realizado"
  Message: "¿Volver esta factura pagada a CONFIRMADA?
  
  Esto revertirá el pago registrado.
  Úselo solo si el pago fue cancelado o reembolsado.
  ¿Continuar?"
Backend Effect:
  • Status = 'confirmed'
  • paid_date = NULL
  • payment_method = NULL
  • payment_reference = NULL
  • ✅ Payment entry REVERSED
  • ❌ No inventory changes
SQL Trigger: handle_purchase_payment_reversal()
  → reverse_purchase_payment_entry()
GUI Update:
  • Badge changes to purple "Confirmada"
  • Buttons: [Editar] [Volver a Enviada] [Registrar Pago]
  • SnackBar: "Pago revertido - factura pendiente de pago"
```

#### **Recibida → Pagada**
```
User Action: Click "Volver a Pagada"
Confirmation Dialog:
  Title: "Devolver productos recibidos"
  Message: "¿Volver esta factura a PAGADA?
  
  Esto indica que los productos fueron devueltos al proveedor.
  El inventario se disminuirá.
  ¿Continuar?"
Backend Effect:
  • Status = 'paid'
  • received_date = NULL
  • ✅ Inventory DECREASED
  • Stock movements deleted or marked as returned
  • ✅ Settlement reversed (if applicable)
SQL Trigger: handle_purchase_return()
  → reverse_purchase_invoice_inventory()
  → reverse_settlement_entry()
GUI Update:
  • Badge changes to orange "Pagada"
  • Buttons: [Marcar como Recibida] [Volver a Confirmada]
  • SnackBar: "Productos devueltos - inventario ajustado"
```

---

## 🧮 ACCOUNTING LOGIC (PREPAYMENT MODEL)

### Option A: Using "Inventory on Order" Account

This is the most accurate prepayment accounting.

#### **Confirmada**: Record AP Liability
```
Entry Number: CONF-COMP-FC-001
Date: 2025-10-12
Type: purchase_confirmation
Status: posted

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 1155 Inventario en Tránsito │ 100,000  │          │
│ 1140 IVA Crédito Fiscal     │  19,000  │          │
│ 2120 Cuentas por Pagar      │          │ 119,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 119,000  │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

#### **Pagada**: Record Payment
```
Entry Number: PAGO-COMP-FC-001
Date: 2025-10-12
Type: purchase_payment
Status: posted

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 2120 Cuentas por Pagar      │ 119,000  │          │
│ 1101 Banco                  │          │ 119,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 119,000  │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

#### **Recibida**: Settle to Inventory
```
Entry Number: RECEP-COMP-FC-001
Date: 2025-10-12
Type: purchase_receipt
Status: posted

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 1150 Inventario             │ 100,000  │          │
│ 1155 Inventario en Tránsito │          │ 100,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 100,000  │ 100,000  │
└─────────────────────────────┴──────────┴──────────┘

Note: IVA already recorded in Confirmed step
Inventory increased at this step
```

### Option B: Simplified (Direct to Inventory)

Simpler approach, records inventory immediately when confirmed.

#### **Confirmada**: Record everything
```
Entry Number: CONF-COMP-FC-001
Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ 1150 Inventario             │ 100,000  │          │
│ 1140 IVA Crédito Fiscal     │  19,000  │          │
│ 2120 Cuentas por Pagar      │          │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

#### **Pagada**: Pay the liability
```
Entry Number: PAGO-COMP-FC-001
Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ 2120 Cuentas por Pagar      │ 119,000  │          │
│ 1101 Banco                  │          │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

#### **Recibida**: Just update stock, no accounting
- Verify quantities
- Update product stock
- No journal entry needed

**Recommendation**: Use Option A for accurate prepayment tracking.

---

## 📦 INVENTORY LOGIC

### Stock Movement (Recibida Status Only)

Products are only added to inventory when marked as "Recibida":

```sql
INSERT INTO stock_movements (
  product_id,
  quantity,
  type,
  movement_type,
  reference,
  notes,
  created_at
) VALUES (
  <product_id>,
  <quantity>,  -- Positive value
  'IN',
  'purchase_invoice_prepaid',
  <invoice_id>,
  'Recepción de compra prepagada - Factura COMP-FC-001',
  NOW()
);

UPDATE products
SET 
  inventory_qty = inventory_qty + <quantity>,
  updated_at = NOW()
WHERE id = <product_id>;
```

### Inventory Reversal (Recibida → Pagada)

When products are returned:

```sql
-- Check if we can reverse (products haven't been sold)
SELECT inventory_qty >= <quantity>
FROM products
WHERE id = <product_id>;

-- If OK, decrease inventory
UPDATE products
SET 
  inventory_qty = inventory_qty - <quantity>,
  updated_at = NOW()
WHERE id = <product_id>;

-- Delete or mark stock movements as returned
DELETE FROM stock_movements
WHERE movement_type = 'purchase_invoice_prepaid'
  AND reference = <invoice_id>;
```

---

## 🎨 GUI COMPONENTS

### Status Badge Colors

| Status     | Color        | Hex/Material |
|------------|--------------|--------------|
| Borrador   | Grey         | Colors.grey[200] / Colors.grey[800] |
| Enviada    | Blue         | Colors.blue[100] / Colors.blue[800] |
| Confirmada | Purple       | Colors.purple[100] / Colors.purple[800] |
| Pagada     | Orange/Amber | Colors.orange[100] / Colors.orange[800] |
| Recibida   | Green        | Colors.green[100] / Colors.green[800] |

### Button Layout by Status

#### **Borrador** (Grey Badge)
```dart
// PurchaseInvoiceFormPage - Prepayment Model - Borrador
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    OutlinedButton.icon(
      icon: Icon(Icons.edit),
      label: Text('Editar'),
      onPressed: _editInvoice,
    ),
    SizedBox(width: 8),
    ElevatedButton.icon(
      icon: Icon(Icons.send),
      label: Text('Enviar a Proveedor'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
      onPressed: _sendToSupplier,
    ),
    SizedBox(width: 8),
    TextButton.icon(
      icon: Icon(Icons.delete, color: Colors.red),
      label: Text('Eliminar', style: TextStyle(color: Colors.red)),
      onPressed: _deleteInvoice,
    ),
  ],
)
```

**Visual**: `[📝 Editar] [📤 Enviar a Proveedor (Blue)] [🗑️ Eliminar (Red)]`

---

#### **Enviada** (Blue Badge)
```dart
// PurchaseInvoiceFormPage - Prepayment Model - Enviada
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    OutlinedButton.icon(
      icon: Icon(Icons.edit),
      label: Text('Editar'),
      onPressed: _editInvoice,
    ),
    SizedBox(width: 8),
    OutlinedButton.icon(
      icon: Icon(Icons.arrow_back),
      label: Text('Volver a Borrador'),
      onPressed: _revertToDraft,
    ),
    SizedBox(width: 8),
    ElevatedButton.icon(
      icon: Icon(Icons.receipt_long),
      label: Text('Confirmar Recepción Factura'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
      onPressed: _confirmSupplierInvoice,
    ),
  ],
)
```

**Visual**: `[📝 Editar] [⬅️ Volver a Borrador] [🧾 Confirmar Recepción Factura (Purple)]`

---

#### **Confirmada** (Purple Badge)
```dart
// PurchaseInvoiceFormPage - Prepayment Model - Confirmada
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Info banner
    Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.purple),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Factura confirmada por proveedor. Pasivo registrado: \$${_invoice.total.toStringAsFixed(0)} CLP',
              style: TextStyle(color: Colors.purple[900]),
            ),
          ),
        ],
      ),
    ),
    SizedBox(height: 12),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          icon: Icon(Icons.visibility),
          label: Text('Ver Factura'),
          onPressed: _viewSupplierInvoice,
        ),
        SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(Icons.arrow_back),
          label: Text('Volver a Enviada'),
          onPressed: _revertToSent,
        ),
        SizedBox(width: 8),
        ElevatedButton.icon(
          icon: Icon(Icons.payment),
          label: Text('Registrar Pago'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
          onPressed: _navigateToPrepayment,
        ),
      ],
    ),
  ],
)
```

**Visual**: 
```
┌─────────────────────────────────────────────────────────┐
│ ℹ️ Factura confirmada. Pasivo: $119,000 CLP            │
└─────────────────────────────────────────────────────────┘
[👁️ Ver Factura] [⬅️ Volver a Enviada] [💰 Registrar Pago (Orange)]
```

---

#### **Pagada** (Orange Badge)
```dart
// PurchaseInvoiceFormPage - Prepayment Model - Pagada
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Warning banner - PREPAID
    Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange[800]),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠️ PAGO ANTICIPADO REALIZADO',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[900]),
                ),
                SizedBox(height: 4),
                Text(
                  'Monto: \$${_invoice.paidAmount.toStringAsFixed(0)} CLP | '
                  'Fecha: ${DateFormat('dd/MM/yyyy').format(_invoice.paidDate!)}',
                  style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                ),
                Text(
                  'Estado: Esperando entrega de productos',
                  style: TextStyle(fontSize: 12, color: Colors.orange[800], fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    SizedBox(height: 12),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          icon: Icon(Icons.receipt),
          label: Text('Ver Comprobante'),
          onPressed: _viewPaymentReceipt,
        ),
        SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(Icons.arrow_back),
          label: Text('Volver a Confirmada'),
          onPressed: _revertToConfirmed,
        ),
        SizedBox(width: 8),
        ElevatedButton.icon(
          icon: Icon(Icons.inventory_2),
          label: Text('Marcar como Recibida'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          onPressed: _markAsReceived,
        ),
      ],
    ),
  ],
)
```

**Visual**: 
```
┌──────────────────────────────────────────────────────────┐
│ ⚠️ PAGO ANTICIPADO REALIZADO                            │
│ Monto: $119,000 CLP | Fecha: 10/10/2025                 │
│ Estado: Esperando entrega de productos                   │
└──────────────────────────────────────────────────────────┘
[🧾 Ver Comprobante] [⬅️ Volver a Confirmada] [📦 Marcar como Recibida (Green)]
```

---

#### **Recibida** (Green Badge)
```dart
// PurchaseInvoiceFormPage - Prepayment Model - Recibida
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Success banner
    Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green[800]),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✅ COMPRA COMPLETADA',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900]),
                ),
                SizedBox(height: 4),
                Text(
                  'Productos recibidos: ${DateFormat('dd/MM/yyyy').format(_invoice.receivedDate!)}',
                  style: TextStyle(fontSize: 12, color: Colors.green[800]),
                ),
                Text(
                  'Pago realizado: ${DateFormat('dd/MM/yyyy').format(_invoice.paidDate!)} (\$${_invoice.paidAmount.toStringAsFixed(0)} CLP)',
                  style: TextStyle(fontSize: 12, color: Colors.green[800]),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    SizedBox(height: 12),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          icon: Icon(Icons.summarize),
          label: Text('Ver Detalles Completos'),
          onPressed: _viewFullDetails,
        ),
        SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(Icons.print),
          label: Text('Imprimir Resumen'),
          onPressed: _printSummary,
        ),
        SizedBox(width: 8),
        OutlinedButton.icon(
          icon: Icon(Icons.arrow_back),
          label: Text('Volver a Pagada'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
          onPressed: _revertToPaid, // Only for returns
        ),
      ],
    ),
  ],
)
```

**Visual**: 
```
┌──────────────────────────────────────────────────────────┐
│ ✅ COMPRA COMPLETADA                                     │
│ Productos recibidos: 12/10/2025                          │
│ Pago realizado: 10/10/2025 ($119,000 CLP)               │
└──────────────────────────────────────────────────────────┘
[📄 Ver Detalles Completos] [🖨️ Imprimir Resumen] [⬅️ Volver a Pagada (Grey)]
```

---

## 🔐 BUSINESS RULES

### Status Transition Rules

| From       | To         | Allowed? | Condition |
|------------|------------|----------|-----------|
| Borrador   | Enviada    | ✅ Yes   | Always |
| Enviada    | Borrador   | ✅ Yes   | Always |
| Enviada    | Confirmada | ✅ Yes   | Requires supplier invoice # |
| Confirmada | Enviada    | ✅ Yes   | If supplier cancels invoice |
| Confirmada | Pagada     | ✅ Yes   | Requires payment details |
| Pagada     | Confirmada | ✅ Yes   | If payment cancelled/refunded |
| Pagada     | Recibida   | ✅ Yes   | Requires verification |
| Recibida   | Pagada     | ✅ Yes   | **Only if sufficient inventory** (return scenario) |

### Edit Restrictions

- **Borrador**: Fully editable
- **Enviada**: Editable (if supplier hasn't confirmed)
- **Confirmada**: Limited editing (supplier invoice already exists)
- **Pagada**: Very limited (payment already made)
- **Recibida**: View only (can revert to return goods)

### Deletion Rules

- **Can only delete Borrador status**
- All other statuses must be reverted step by step
- **Journal Entries**: Can use DELETE or REVERSAL (configurable)
- **Stock Movements**: DELETED when reverting from Recibida

---

## 🔄 COMPARISON: PAY AFTER vs PREPAYMENT

| Aspect | Pay After Receipt | Prepayment (New) |
|--------|-------------------|------------------|
| **Flow** | Draft → Received → Paid | Draft → Sent → Confirmed → Paid → Received |
| **Payment Timing** | After goods arrive | Before goods arrive |
| **Risk** | Supplier (delivers first) | Buyer (pays first) |
| **Inventory Timing** | At "Received" | At "Received" (same) |
| **AP Created** | At "Received" | At "Confirmed" |
| **Payment Entry** | After receipt | Before receipt |
| **Statuses** | 3 statuses | 5 statuses |
| **Use Case** | Standard suppliers | Trusted suppliers, international |
| **Accounting** | Simpler | More detailed |

---

## 🗄️ DATABASE SCHEMA ADDITIONS

### New Fields for Purchase Invoices

```sql
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS:
  sent_date TIMESTAMP,
  confirmed_date TIMESTAMP,
  supplier_invoice_number TEXT,
  supplier_invoice_date DATE,
  paid_date TIMESTAMP,
  payment_method TEXT,
  payment_reference TEXT,
  received_date TIMESTAMP,
  prepayment_model BOOLEAN DEFAULT false
```

### New Status Values

```sql
ALTER TABLE purchase_invoices
  DROP CONSTRAINT IF EXISTS purchase_invoices_status_check;

ALTER TABLE purchase_invoices
  ADD CONSTRAINT purchase_invoices_status_check
    CHECK (lower(status) = ANY (ARRAY[
      'draft', 'borrador',
      'sent', 'enviado', 'enviada',
      'confirmed', 'confirmado', 'confirmada',
      'paid', 'pagado', 'pagada',
      'received', 'recibido', 'recibida',
      'cancelled', 'cancelado', 'cancelada'
    ]));
```

---

## 🧪 TESTING SCENARIOS

### Test 1: Complete Prepayment Flow
1. Create invoice (Draft)
2. Send to supplier → Status = Sent
3. Confirm invoice (enter supplier's invoice #) → AP created
4. Register payment → Payment entry created
5. Mark as received → Inventory increased

### Test 2: Supplier Cancels After Confirmation
1. Create, send, confirm invoice
2. Supplier cancels
3. Revert Confirmed → Sent
4. Verify AP entry deleted/reversed

### Test 3: Payment Then Cancellation (Refund)
1. Create, send, confirm, pay
2. Need refund
3. Revert Paid → Confirmed
4. Verify payment reversed
5. Can revert to Sent if needed

### Test 4: Goods Return After Receipt
1. Complete full flow to Received
2. Goods defective, return to supplier
3. Revert Received → Paid
4. Verify inventory decreased
5. Supplier refunds
6. Revert Paid → Confirmed

### Test 5: Compare Both Models
1. Create invoice with prepayment model enabled
2. Complete flow: Draft → Sent → Confirmed → Paid → Received
3. Create another invoice with standard model
4. Complete flow: Draft → Received → Paid
5. Compare journal entries and timing

---

## ⚙️ SETTINGS CONFIGURATION

### Purchase Invoice Workflow Model Selection

```dart
// In Settings module
enum PurchaseInvoiceWorkflowModel {
  payAfterReceipt,    // Standard: Draft → Received → Paid
  prepayment,         // Prepaid: Draft → Sent → Confirmed → Paid → Received
}

class CompanySettings {
  // ...
  PurchaseInvoiceWorkflowModel purchaseWorkflowModel;
  // ...
}
```

### Settings UI

```
┌─────────────────────────────────────────────────┐
│ Configuración de Compras                        │
├─────────────────────────────────────────────────┤
│                                                 │
│ Modelo de Flujo de Facturas de Compra:         │
│                                                 │
│ ○ Pago Después de Recepción (Estándar)         │
│   Flujo: Borrador → Recibida → Pagada          │
│   Recomendado para proveedores locales.        │
│                                                 │
│ ● Pago Anticipado (Prepago)                    │
│   Flujo: Borrador → Enviada → Confirmada →     │
│          Pagada → Recibida                      │
│   Recomendado para proveedores internacionales │
│   o de confianza que requieren pago adelantado.│
│                                                 │
│         [Guardar Configuración]                 │
└─────────────────────────────────────────────────┘
```

---

## 🌍 LOCALIZATION (Chilean Context)

- **Currency**: CLP (Chilean Peso)
- **Tax**: IVA 19% (crédito fiscal)
- **Date Format**: DD/MM/YYYY
- **Language**: Spanish
- **Payment Methods**: Transferencia bancaria, Cheque, Efectivo
- **Supplier Invoice**: "Factura Electrónica" (required in Chile)

---

## 🔧 AGENT INSTRUCTIONS

### When Implementing Prepayment Flow:

1. ✅ Add `prepayment_model` boolean to purchase invoices table
2. ✅ Create new status enum values (sent, confirmed, paid, received)
3. ✅ Implement conditional logic based on workflow model:
   ```dart
   if (invoice.prepaymentModel) {
     // Use 5-status flow
   } else {
     // Use 3-status flow
   }
   ```
4. ✅ Create separate UI components for each model
5. ✅ Add Settings toggle to switch between models
6. ✅ Ensure backward compatibility with existing invoices
7. ✅ Test both flows thoroughly

### Accounting Implementation:

1. For **Confirmed** status:
   - Option A: DR: Inventory on Order, CR: AP
   - Option B: DR: Inventory, CR: AP
2. For **Paid** status:
   - DR: AP, CR: Bank
3. For **Received** status:
   - Option A: DR: Inventory, CR: Inventory on Order
   - Option B: Just update stock (no entry)

### Code References (To Be Created):

- **Service**: `lib/modules/purchases/services/purchase_service_prepaid.dart`
- **UI**: `lib/modules/purchases/pages/purchase_invoice_form_page_prepaid.dart`
- **SQL**: `supabase/sql/purchase_invoice_prepaid_workflow.sql`
- **Settings**: `lib/modules/settings/models/company_settings.dart`

---

## ✅ IMPLEMENTATION CHECKLIST

- [ ] Update database schema (new status values, new fields)
- [ ] Create Settings option for workflow model selection
- [ ] Implement conditional routing in PurchaseService
- [ ] Create new SQL triggers for prepayment flow
- [ ] Update UI to show different buttons based on model
- [ ] Add status badge colors (orange for Pagada in prepayment)
- [ ] Implement accounting logic (Option A or B)
- [ ] Create reversal functions for each transition
- [ ] Add inventory control (only at Recibida)
- [ ] Write comprehensive tests
- [ ] Document user guide for both models
- [ ] Train users on when to use each model

---

## 📝 NOTES

**When to Use Prepayment Model**:
- International suppliers requiring upfront payment
- High-trust supplier relationships
- Expensive equipment or special orders
- Supplier financing agreements
- Wholesale purchases with prepayment discounts

**When to Use Pay After Receipt Model**:
- Standard local suppliers
- Cash on delivery scenarios
- New supplier relationships (lower trust)
- Small regular orders
- Suppliers offering net payment terms (30, 60, 90 days)

**Key Benefit**: Having both models gives flexibility to match real business practices with different supplier types! 🎯
