# PURCHASE INVOICE STATUS FLOW — STANDARD MODEL (PAY AFTER RECEIPT)

## Overview

This document describes the **Standard Purchase Invoice Workflow** implemented in the Vinabike ERP. This is the traditional "Pay After Receipt" model where:
- Orders are sent to suppliers
- Suppliers confirm and issue invoices
- Goods are received and verified
- Payment is made after receipt

The workflow **mirrors the sales invoice flow** but handles supplier invoices with inventory IN movements and Accounts Payable accounting.

The system uses **DELETE-based reversals** (like Zoho Books and sales invoices) for purchase invoices. When going backward, journal entries are deleted completely, not marked as reversed. This provides a cleaner, simpler approach for draft/in-progress invoices.

**Payment Model Selection**: When creating a new purchase invoice, a dialog prompts the user to choose between:
- **Standard Model** (this document): Pay after receiving goods
- **Prepayment Model**: Pay before receiving goods (see Purchase_Invoice_Prepayment_Flow.md)

Each invoice stores its selected model in the `prepayment_model` boolean field, which determines which status flow and accounting logic to use.

**Key Principle**: Inventory only increases when products are physically **RECIBIDA** (received in store), not when confirmed by supplier.

---

## 🔄 STATUS FLOW DIAGRAM

```
┌─────────────┐
│   BORRADOR  │ ← Initial state (Draft)
│   (draft)   │   • Editable
└──────┬──────┘   • No accounting impact
       │          • No inventory impact
       │
       │ ➡️ [Marcar como Enviada]
       │    • Button in detail page
       │    • Just status change
       │    • No accounting/inventory
       │
       ⬇️
┌──────────────┐
│   ENVIADA    │ (Sent to Supplier)
│    (sent)    │  • Order sent to supplier
└──────┬───────┘  • Waiting confirmation
       │          • No accounting/inventory
       │
       │ ⬅️ [Volver a Borrador]
       │    • Just status change
       │
       │ ➡️ [Confirmar Factura]
       │    • Button in detail page
       │    • Creates journal entry (Inventory + IVA / AP)
       │    • NO inventory increase yet
       │
       ⬇️
┌───────────────┐
│  CONFIRMADA   │ (Confirmed by Supplier)
│ (confirmed)   │  • Supplier issued invoice
└──────┬────────┘  • Accounting entry created
       │           • Inventory NOT increased yet
       │
       │ ⬅️ [Volver a Enviada]
       │    • Creates REVERSAL journal entry
       │    • No inventory change
       │
       │ ➡️ [Marcar como Recibida]
       │    • Button in detail page
       │    • INCREASES inventory (IN)
       │    • Triggers: consume_purchase_invoice_inventory()
       │
       ⬇️
┌──────────────┐
│  RECIBIDA    │ (Received in Store)
│  (received)  │  • Goods physically in stock
└──────┬───────┘  • Inventory INCREASED
       │          • Ready to pay
       │
       │ ⬅️ [Volver a Confirmada]
       │    • Creates REVERSAL for inventory
       │    • DECREASES inventory back
       │    • Triggers: reverse_purchase_invoice_inventory()
       │
       │ ➡️ [Pagar Factura] → Payment Form
       │    • Button navigates to payment page
       │    • User enters payment details
       │    • Click [Guardar Pago]
       │    • Creates payment journal entry
       │
       ⬇️
┌──────────────┐
│    PAGADA    │ (Paid to Supplier)
│    (paid)    │  • Supplier has been paid
└──────┬───────┘  • Payment recorded
       │          • Payment journal entry created
       │
       │ ⬅️ [Deshacer Pago]
       │    • Button in detail page
       │    • DELETES payment record
       │    • DELETES payment journal entry
       │    • Returns to RECIBIDA status
```

---

## 📊 STATUS DEFINITIONS

### 1. **Borrador** (Draft)
- **Spanish Label**: "Borrador"
- **Badge Color**: Grey (`Colors.grey[200]` / `Colors.grey[800]`)
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Purchase invoice is being prepared, not yet sent to supplier
- **Available Actions**:
  - ✏️ **[Editar]** button → Opens form in edit mode
  - ➡️ **[Marcar como Enviada]** button → Changes status to 'sent'
  - 🗑️ **[Eliminar]** button → Deletes draft invoice

---

### 2. **Enviada** (Sent to Supplier)
- **Spanish Label**: "Enviada"
- **Badge Color**: Blue (`Colors.blue[100]` / `Colors.blue[800]`)
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Order sent to supplier, waiting for their confirmation
- **Available Actions**:
  - ✏️ **[Editar]** button → Opens form in edit mode
  - ⬅️ **[Volver a Borrador]** button → Changes status to 'draft'
  - ✅ **[Confirmar Factura]** button (Green) → Changes status to 'confirmed' + triggers accounting

---

### 3. **Confirmada** (Confirmed by Supplier)
- **Spanish Label**: "Confirmada"
- **Badge Color**: Purple (`Colors.purple[100]` / `Colors.purple[800]`)
- **Accounting Effect**: ✅ Journal entry created
  - **Debit**: Inventario (1105 or 1150)
  - **Debit**: IVA Crédito Fiscal (1107 or 1140)
  - **Credit**: Cuentas por Pagar / Proveedores (2101 or 2120)
- **Inventory Effect**: ❌ None (not received yet)
- **Description**: Supplier confirmed order and issued invoice, but goods not delivered yet
- **Available Actions**:
  - ✏️ **[Editar]** button → Limited editing (accounting exists)
  - ⬅️ **[Volver a Enviada]** button → Creates reversal entry, returns to 'sent'
  - 📦 **[Marcar como Recibida]** button → Changes status to 'received' + increases inventory

---

### 4. **Recibida** (Received in Store)
- **Spanish Label**: "Recibida"
- **Badge Color**: Green (`Colors.green[100]` / `Colors.green[800]`)
- **Accounting Effect**: — (already created when confirmed)
- **Inventory Effect**: ✅ Stock INCREASED (IN movement)
  - **Trigger**: `consume_purchase_invoice_inventory()`
  - **Stock movements**: type='IN', movement_type='purchase_invoice'
  - **Products table**: `inventory_qty += quantity`
- **Description**: Goods physically received in store, inventory updated, ready to pay
- **Available Actions**:
  - ✏️ **[Editar]** button → Very limited editing
  - 💰 **[Pagar Factura]** button → Navigates to payment form page
  - ⬅️ **[Volver a Confirmada]** button → Creates reversal for inventory, decreases stock

---

### 5. **Pagada** (Paid to Supplier)
- **Spanish Label**: "Pagada"
- **Badge Color**: Blue (`Colors.blue[100]` / `Colors.blue[800]`)
- **Accounting Effect**: ✅ Payment journal entry created
  - **Debit**: Cuentas por Pagar (2101 or 2120)
  - **Credit**: Cash/Bank account (1110 or 1101)
- **Inventory Effect**: — (already increased when received)
- **Description**: Invoice has been paid to supplier, process complete
- **Available Actions**:
  - ✏️ **[Ver Detalles]** button → View-only mode
  - ⬅️ **[Deshacer Pago]** button (Red text) → Deletes payment record AND payment journal entry, returns to 'received'

---

## 🔀 STATUS TRANSITIONS — DETAILED BUTTON & TRIGGER MAPPING

### Forward Transitions

#### **Borrador → Enviada**

**User Interaction**:
1. User opens purchase invoice in detail page
2. Sees status badge: Grey "Borrador"
3. Clicks green button **[Marcar como Enviada]**

**Frontend Action** (`PurchaseInvoiceDetailPage`):
```dart
void _markAsSent() async {
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.updateInvoiceStatus(
      widget.invoiceId,
      'sent',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura marcada como enviada')),
      );
      Navigator.pop(context, true); // Refresh parent
    }
  } catch (e) {
    _showError('Error al marcar como enviada: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Effect** (`PurchaseService.updateInvoiceStatus()`):
```dart
Future<void> updateInvoiceStatus(int invoiceId, String newStatus) async {
  await _supabase
      .from('purchase_invoices')
      .update({'status': newStatus})
      .eq('id', invoiceId);
  // Simple status update, no triggers needed
}
```

**SQL Trigger**: ❌ None (simple status change)

**Database Changes**:
- `purchase_invoices.status` = 'sent'
- ❌ No journal entries created
- ❌ No inventory changes

**GUI Update**:
- Badge changes to blue **"Enviada"**
- Buttons visible:
  - **[Editar]** (outlined)
  - **[Volver a Borrador]** (outlined, grey)
  - **[Confirmar Factura]** (filled, green) ← Primary action
- SnackBar: "Factura marcada como enviada"

---

#### **Enviada → Confirmada**

**User Interaction**:
1. User sees status badge: Blue "Enviada"
2. Clicks green button **[Confirmar Factura]**
3. Optional: Confirmation dialog appears
   - Title: "Confirmar factura de compra"
   - Message: "Esto creará un asiento contable (Inventario + IVA / Cuentas por Pagar). ¿Continuar?"
   - Buttons: [Cancelar] [Confirmar]

**Frontend Action**:
```dart
void _confirmInvoice() async {
  // Show confirmation dialog
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Confirmar factura de compra'),
      content: Text('Esto creará un asiento contable (Inventario + IVA / Cuentas por Pagar). ¿Continuar?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Confirmar'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.updateInvoiceStatus(
      widget.invoiceId,
      'confirmed',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura confirmada - asiento contable creado')),
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

**SQL Trigger**: ✅ `handle_purchase_invoice_change()`

**Trigger Logic**:
```sql
CREATE OR REPLACE FUNCTION handle_purchase_invoice_change()
RETURNS TRIGGER AS $$
BEGIN
  -- When status changes to 'confirmed'
  IF (TG_OP = 'UPDATE' AND OLD.status != 'confirmed' AND NEW.status = 'confirmed') THEN
    -- Create journal entry
    PERFORM create_purchase_invoice_journal_entry(NEW.id);
    
    -- Do NOT increase inventory yet (wait for 'received')
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Trigger Function**: `create_purchase_invoice_journal_entry(invoice_id)`

**Journal Entry Created**:
```sql
INSERT INTO journal_entries (
  entry_number,
  entry_date,
  entry_type,
  status,
  source_module,
  source_reference,
  notes
) VALUES (
  'COMP-FC-' || invoice.invoice_number,
  NOW(),
  'purchase_invoice',
  'posted',
  'purchase_invoices',
  invoice.id,
  'Compra según factura ' || invoice.invoice_number
) RETURNING id INTO v_entry_id;

-- Journal Lines
INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description)
VALUES
  -- DR: Inventory
  (v_entry_id, <inventory_account_id>, invoice.subtotal, 0, 'Inventario compra'),
  -- DR: IVA Crédito
  (v_entry_id, <iva_credit_account_id>, invoice.tax_amount, 0, 'IVA Crédito Fiscal'),
  -- CR: Accounts Payable
  (v_entry_id, <ap_account_id>, 0, invoice.total, 'Cuentas por Pagar - ' || supplier.name);
```

**Database Changes**:
- `purchase_invoices.status` = 'confirmed'
- ✅ `journal_entries` record created
- ✅ `journal_lines` records created (3 lines: Inventory DR, IVA DR, AP CR)
- ❌ NO inventory changes yet

**GUI Update**:
- Badge changes to purple **"Confirmada"**
- Buttons visible:
  - **[Editar]** (outlined, disabled or limited)
  - **[Volver a Enviada]** (outlined, grey)
  - **[Marcar como Recibida]** (filled, green) ← Primary action
- SnackBar: "Factura confirmada - asiento contable creado"

---

#### **Confirmada → Recibida**

**User Interaction**:
1. User sees status badge: Purple "Confirmada"
2. Clicks green button **[Marcar como Recibida]**
3. Optional: Verification dialog
   - Title: "Marcar productos como recibidos"
   - Message: "¿Los productos fueron entregados físicamente en la tienda? Esto aumentará el inventario."
   - Buttons: [Cancelar] [Confirmar Recepción]

**Frontend Action**:
```dart
void _markAsReceived() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Marcar productos como recibidos'),
      content: Text('¿Los productos fueron entregados físicamente en la tienda? Esto aumentará el inventario.'),
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
    await _purchaseService.markAsReceived(widget.invoiceId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Productos recibidos - inventario actualizado')),
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

**Backend Service** (`PurchaseService.markAsReceived()`):
```dart
Future<void> markAsReceived(int invoiceId) async {
  await _supabase
      .from('purchase_invoices')
      .update({'status': 'received', 'received_date': DateTime.now().toIso8601String()})
      .eq('id', invoiceId);
  
  // Trigger will handle inventory increase automatically
}
```

**SQL Trigger**: ✅ `handle_purchase_invoice_change()`

**Trigger Logic**:
```sql
IF (TG_OP = 'UPDATE' AND OLD.status != 'received' AND NEW.status = 'received') THEN
  -- Increase inventory
  PERFORM consume_purchase_invoice_inventory(NEW.id);
END IF;
```

**Trigger Function**: `consume_purchase_invoice_inventory(invoice_id)`

**Inventory Changes**:
```sql
CREATE OR REPLACE FUNCTION consume_purchase_invoice_inventory(p_invoice_id INTEGER)
RETURNS VOID AS $$
DECLARE
  v_item RECORD;
BEGIN
  -- Loop through invoice items
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
      v_item.quantity,  -- Positive value
      'IN',
      'purchase_invoice',
      p_invoice_id,
      'Compra recibida según factura ' || (SELECT invoice_number FROM purchase_invoices WHERE id = p_invoice_id),
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

**Database Changes**:
- `purchase_invoices.status` = 'received'
- `purchase_invoices.received_date` = NOW()
- ✅ `stock_movements` records created (type='IN', movement_type='purchase_invoice')
- ✅ `products.inventory_qty` INCREASED for each item

**GUI Update**:
- Badge changes to green **"Recibida"**
- Buttons visible:
  - **[Ver Detalles]** (outlined)
  - **[Volver a Confirmada]** (outlined, grey)
  - **[Pagar Factura]** (filled, blue) ← Primary action
- SnackBar: "Productos recibidos - inventario actualizado"

---

#### **Recibida → Pagada**

**User Interaction**:
1. User sees status badge: Green "Recibida"
2. Clicks blue button **[Pagar Factura]**
3. Navigates to **Payment Form Page** (`PurchasePaymentFormPage`)
4. User fills payment form:
   - Payment method (Efectivo, Transferencia, Cheque)
   - Amount (defaults to remaining balance)
   - Payment date (defaults to today)
   - Bank account (if Transferencia/Cheque)
   - Reference/Notes
5. Clicks **[Guardar Pago]** button

**Frontend Navigation**:
```dart
void _navigateToPayment() async {
  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PurchasePaymentFormPage(
        invoiceId: widget.invoiceId,
        invoiceTotal: _invoice.total,
        remainingBalance: _invoice.balance,
      ),
    ),
  );
  
  if (result == true) {
    // Payment recorded successfully
    _loadInvoice(); // Refresh invoice data
  }
}
```

**Payment Form Page** (`PurchasePaymentFormPage`):
```dart
void _savePayment() async {
  if (!_formKey.currentState!.validate()) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.registerPayment(
      invoiceId: widget.invoiceId,
      amount: _amountController.value,
      paymentMethod: _selectedMethod,
      paymentDate: _selectedDate,
      bankAccountId: _selectedBankAccountId,
      reference: _referenceController.text,
      notes: _notesController.text,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pago registrado correctamente')),
      );
      Navigator.pop(context, true); // Return to detail page
    }
  } catch (e) {
    _showError('Error al registrar pago: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service** (`PurchaseService.registerPayment()`):
```dart
Future<void> registerPayment({
  required int invoiceId,
  required double amount,
  required String paymentMethod,
  required DateTime paymentDate,
  int? bankAccountId,
  String? reference,
  String? notes,
}) async {
  // Insert payment record
  await _supabase.from('purchase_payments').insert({
    'purchase_invoice_id': invoiceId,
    'amount': amount,
    'payment_method': paymentMethod,
    'payment_date': paymentDate.toIso8601String(),
    'bank_account_id': bankAccountId,
    'reference': reference,
    'notes': notes,
  });
  
  // Trigger will create journal entry and update invoice status
}
```

**SQL Trigger**: ✅ `recalculate_purchase_invoice_payments()`

**Trigger on Payments Table**:
```sql
CREATE TRIGGER recalculate_purchase_payments_trigger
AFTER INSERT OR UPDATE OR DELETE ON purchase_payments
FOR EACH ROW
EXECUTE FUNCTION recalculate_purchase_invoice_payments();
```

**Trigger Function**:
```sql
CREATE OR REPLACE FUNCTION recalculate_purchase_invoice_payments()
RETURNS TRIGGER AS $$
DECLARE
  v_invoice_id INTEGER;
  v_total_paid NUMERIC;
  v_invoice_total NUMERIC;
  v_balance NUMERIC;
  v_new_status TEXT;
BEGIN
  -- Get invoice ID
  v_invoice_id := COALESCE(NEW.purchase_invoice_id, OLD.purchase_invoice_id);
  
  -- Calculate total paid
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM purchase_payments
  WHERE purchase_invoice_id = v_invoice_id;
  
  -- Get invoice total
  SELECT total INTO v_invoice_total
  FROM purchase_invoices
  WHERE id = v_invoice_id;
  
  -- Calculate balance
  v_balance := v_invoice_total - v_total_paid;
  
  -- Determine new status
  IF v_total_paid >= v_invoice_total THEN
    v_new_status := 'paid';
  ELSE
    v_new_status := 'received'; -- Preserve received status if partially paid
  END IF;
  
  -- Update invoice
  UPDATE purchase_invoices
  SET 
    paid_amount = v_total_paid,
    balance = v_balance,
    status = v_new_status
  WHERE id = v_invoice_id;
  
  -- Create payment journal entry (if INSERT)
  IF TG_OP = 'INSERT' THEN
    PERFORM create_purchase_payment_journal_entry(NEW.id);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Payment Journal Entry Function**:
```sql
CREATE OR REPLACE FUNCTION create_purchase_payment_journal_entry(p_payment_id INTEGER)
RETURNS VOID AS $$
DECLARE
  v_payment RECORD;
  v_invoice RECORD;
  v_entry_id INTEGER;
BEGIN
  -- Get payment and invoice data
  SELECT p.*, i.invoice_number 
  INTO v_payment
  FROM purchase_payments p
  JOIN purchase_invoices i ON p.purchase_invoice_id = i.id
  WHERE p.id = p_payment_id;
  
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
    'PAGO-COMP-' || v_payment.invoice_number || '-' || p_payment_id,
    v_payment.payment_date,
    'payment',
    'posted',
    'purchase_payments',
    p_payment_id,
    'Pago factura compra ' || v_payment.invoice_number
  ) RETURNING id INTO v_entry_id;
  
  -- Journal lines
  INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description)
  VALUES
    -- DR: Accounts Payable
    (v_entry_id, <ap_account_id>, v_payment.amount, 0, 'Pago a proveedor'),
    -- CR: Bank/Cash
    (v_entry_id, <bank_account_id>, 0, v_payment.amount, 'Salida de ' || v_payment.payment_method);
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- ✅ `purchase_payments` record created
- ✅ `journal_entries` record created (payment entry)
- ✅ `journal_lines` records created (2 lines: AP DR, Bank CR)
- `purchase_invoices.paid_amount` = total of all payments
- `purchase_invoices.balance` = total - paid_amount
- `purchase_invoices.status` = 'paid' (if fully paid)
- ❌ No inventory changes

**GUI Update**:
- Badge changes to blue **"Pagada"** (if fully paid)
- Buttons visible:
  - **[Ver Detalles]** (outlined)
  - **[Deshacer Pago]** (text button, red color)
- Shows payment information:
  - Payment date
  - Payment method
  - Amount paid
- SnackBar: "Pago registrado correctamente"

---

### Backward Transitions (Reversals)

#### **Enviada → Borrador**

**User Interaction**:
1. User sees status badge: Blue "Enviada"
2. Clicks grey button **[Volver a Borrador]**
3. Optional: Simple confirmation
   - Message: "¿Cancelar orden enviada y volver a borrador?"
   - Buttons: [No] [Sí]

**Frontend Action**:
```dart
void _revertToDraft() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Volver a borrador'),
      content: Text('¿Cancelar orden enviada y volver a borrador?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('No'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Sí'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.updateInvoiceStatus(widget.invoiceId, 'draft');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura revertida a borrador')),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**SQL Trigger**: ❌ None (simple status change)

**Database Changes**:
- `purchase_invoices.status` = 'draft'
- ❌ No journal entries affected
- ❌ No inventory changes

**GUI Update**:
- Badge changes to grey **"Borrador"**
- Buttons visible: **[Editar]** **[Marcar como Enviada]** **[Eliminar]**
- SnackBar: "Factura revertida a borrador"

---

#### **Confirmada → Enviada**

**User Interaction**:
1. User sees status badge: Purple "Confirmada"
2. Clicks grey button **[Volver a Enviada]**
3. **Confirmation Dialog** (IMPORTANT):
   - Title: "Revertir factura confirmada"
   - Message: "⚠️ Esto creará un asiento contable de REVERSO y eliminará el pasivo. ¿Continuar?"
   - Buttons: [Cancelar] [Sí, Revertir]

**Frontend Action**:
```dart
void _revertToSent() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Revertir factura confirmada'),
      content: Text(
        '⚠️ Esto creará un asiento contable de REVERSO y eliminará el pasivo. ¿Continuar?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: Text('Sí, Revertir'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.revertToSent(widget.invoiceId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura revertida a enviada - asiento reverso creado')),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error al revertir: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service** (`PurchaseService.revertToSent()`):
```dart
Future<void> revertToSent(int invoiceId) async {
  // Update status - trigger will handle reversal
  await _supabase
      .from('purchase_invoices')
      .update({'status': 'sent'})
      .eq('id', invoiceId);
}
```

**SQL Trigger**: ✅ `handle_purchase_invoice_change()`

**Trigger Logic**:
```sql
CREATE OR REPLACE FUNCTION handle_purchase_invoice_change()
RETURNS TRIGGER AS $$
BEGIN
  -- Confirmada → Enviada: Delete journal entry
  IF (OLD.status = 'confirmed' AND NEW.status = 'sent') THEN
    -- Delete the journal entry completely (Zoho Books style)
    DELETE FROM journal_entries
    WHERE source_module = 'purchase_invoices'
      AND source_reference = OLD.id
      AND entry_type = 'purchase_invoice';
    -- journal_lines cascade deleted automatically
    
    -- No inventory to reverse (wasn't received yet)
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- `purchase_invoices.status` = 'sent'
- ✅ `journal_entries` record **DELETED** (entry_type='purchase_invoice')
- ✅ `journal_lines` records **DELETED** (cascade deletion)
- ❌ No inventory changes (products weren't received)

**Deletion Effect**:
```
Before: 
  Journal Entry COMP-FC-001 exists with 3 lines

After:
  Journal Entry COMP-FC-001 completely removed from database
  All journal_lines removed (cascade)
  
Net Effect: Clean slate, as if invoice was never confirmed
```

**GUI Update**:
- Badge changes to blue **"Enviada"**
- Buttons visible: **[Editar]** **[Volver a Borrador]** **[Confirmar Factura]**
- SnackBar: "Factura revertida a enviada - asiento contable eliminado"

---

#### **Recibida → Confirmada**

**User Interaction**:
1. User sees status badge: Green "Recibida"
2. Clicks grey button **[Volver a Confirmada]**
3. **Confirmation Dialog** (CRITICAL):
   - Title: "Revertir productos recibidos"
   - Message: "⚠️ Esto DISMINUIRÁ el inventario. Solo si los productos NO han sido vendidos. ¿Continuar?"
   - Buttons: [Cancelar] [Sí, Revertir]

**Frontend Action**:
```dart
void _revertToConfirmed() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Revertir productos recibidos'),
      content: Text(
        '⚠️ Esto DISMINUIRÁ el inventario.\n\n'
        'Solo si los productos NO han sido vendidos.\n\n'
        '¿Continuar?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text('Sí, Revertir'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.revertToConfirmed(widget.invoiceId);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura revertida a confirmada - inventario disminuido')),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    _showError('Error al revertir: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service**:
```dart
Future<void> revertToConfirmed(int invoiceId) async {
  // Trigger will check inventory and reverse
  await _supabase
      .from('purchase_invoices')
      .update({'status': 'confirmed'})
      .eq('id', invoiceId);
}
```

**SQL Trigger**: ✅ `handle_purchase_invoice_reversal()`

**Trigger Logic**:
```sql
IF (OLD.status = 'received' AND NEW.status = 'confirmed') THEN
  -- Reverse inventory (decrease stock)
  PERFORM reverse_purchase_invoice_inventory(OLD.id);
  
  -- No journal entry reversal (accounting stays intact)
END IF;
```

**Inventory Reversal Function**:
```sql
CREATE OR REPLACE FUNCTION reverse_purchase_invoice_inventory(p_invoice_id INTEGER)
RETURNS VOID AS $$
DECLARE
  v_item RECORD;
  v_current_qty INTEGER;
BEGIN
  -- Loop through invoice items
  FOR v_item IN 
    SELECT product_id, quantity 
    FROM purchase_invoice_items 
    WHERE purchase_invoice_id = p_invoice_id
  LOOP
    -- Check if we have enough inventory
    SELECT inventory_qty INTO v_current_qty
    FROM products
    WHERE id = v_item.product_id;
    
    IF v_current_qty < v_item.quantity THEN
      RAISE EXCEPTION 'Inventario insuficiente para producto % (disponible: %, necesario: %)',
        v_item.product_id, v_current_qty, v_item.quantity;
    END IF;
    
    -- Decrease inventory
    UPDATE products
    SET 
      inventory_qty = inventory_qty - v_item.quantity,
      updated_at = NOW()
    WHERE id = v_item.product_id;
    
    -- Delete stock movements
    DELETE FROM stock_movements
    WHERE movement_type = 'purchase_invoice'
      AND reference = p_invoice_id
      AND product_id = v_item.product_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- `purchase_invoices.status` = 'confirmed'
- ✅ `products.inventory_qty` DECREASED for each item
- ✅ `stock_movements` records DELETED (type='IN' removed)
- ❌ NO journal entry changes (accounting preserved)

**Error Handling**:
- If ANY product has insufficient inventory → Transaction FAILS
- Error message: "Inventario insuficiente para producto X (disponible: Y, necesario: Z)"
- No partial reversals (all or nothing)

**GUI Update**:
- Badge changes to purple **"Confirmada"**
- Buttons visible: **[Editar]** **[Volver a Enviada]** **[Marcar como Recibida]**
- SnackBar: "Factura revertida a confirmada - inventario disminuido"

---

#### **Pagada → Recibida** (Undo Payment)

**User Interaction**:
1. User sees status badge: Blue "Pagada"
2. Clicks red text button **[Deshacer Pago]**
3. **Confirmation Dialog**:
   - Title: "Deshacer pago"
   - Message: "Se eliminará el registro de pago de $119,000 CLP y su asiento contable. ¿Continuar?"
   - Buttons: [Cancelar] [Sí, Deshacer]

**Frontend Action**:
```dart
void _undoPayment() async {
  // Get last payment
  final lastPayment = await _purchaseService.getLastPayment(widget.invoiceId);
  
  if (lastPayment == null) {
    _showError('No hay pagos para deshacer');
    return;
  }
  
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Deshacer pago'),
      content: Text(
        'Se eliminará el registro de pago de \$${lastPayment.amount.toStringAsFixed(0)} CLP '
        'y su asiento contable.\n\n¿Continuar?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text('Sí, Deshacer'),
        ),
      ],
    ),
  );
  
  if (confirmed != true) return;
  
  setState(() => _isLoading = true);
  
  try {
    await _purchaseService.deletePayment(lastPayment.id);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pago eliminado correctamente')),
      );
      _loadInvoice(); // Refresh
    }
  } catch (e) {
    _showError('Error al eliminar pago: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Backend Service**:
```dart
Future<void> deletePayment(int paymentId) async {
  // Delete payment - trigger will handle journal entry and status update
  await _supabase
      .from('purchase_payments')
      .delete()
      .eq('id', paymentId);
}
```

**SQL Trigger**: ✅ `recalculate_purchase_invoice_payments()` (on DELETE)

**Trigger Logic**:
```sql
IF TG_OP = 'DELETE' THEN
  -- Delete payment journal entry
  DELETE FROM journal_entries
  WHERE source_module = 'purchase_payments'
    AND source_reference = OLD.id;
  
  -- Recalculate invoice status
  v_invoice_id := OLD.purchase_invoice_id;
  
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM purchase_payments
  WHERE purchase_invoice_id = v_invoice_id;
  
  SELECT total INTO v_invoice_total
  FROM purchase_invoices
  WHERE id = v_invoice_id;
  
  -- If no more payments, return to 'received'
  IF v_total_paid = 0 THEN
    v_new_status := 'received';
  ELSIF v_total_paid >= v_invoice_total THEN
    v_new_status := 'paid';
  ELSE
    v_new_status := 'received'; -- Partially paid
  END IF;
  
  UPDATE purchase_invoices
  SET 
    paid_amount = v_total_paid,
    balance = v_invoice_total - v_total_paid,
    status = v_new_status
  WHERE id = v_invoice_id;
  
  RETURN OLD;
END IF;
```

**Database Changes**:
- ✅ `purchase_payments` record DELETED
- ✅ `journal_entries` record DELETED (payment entry removed completely)
- ✅ `journal_lines` records DELETED (cascaded deletion)
- `purchase_invoices.status` = 'received'
- `purchase_invoices.paid_amount` recalculated
- `purchase_invoices.balance` restored
- ❌ No inventory changes

**GUI Update**:
- Badge changes to green **"Recibida"**
- Buttons visible: **[Ver Detalles]** **[Volver a Confirmada]** **[Pagar Factura]**
- Balance shows unpaid amount again
- SnackBar: "Pago eliminado correctamente"

---

## 🧮 ACCOUNTING LOGIC

### Journal Entry Structure (Confirmed Status)

**Example Purchase Invoice**: COMP-FC-001
- Subtotal: $100,000 CLP
- IVA (19%): $19,000 CLP
- Total: $119,000 CLP

**Journal Entry Created** (Forward: Enviada → Confirmada):
```
Entry Number: COMP-FC-001
Date: 2025-10-12
Type: purchase_invoice
Status: posted

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 1105 Inventario             │ 100,000  │          │
│ 1107 IVA Crédito Fiscal     │  19,000  │          │
│ 2101 Cuentas por Pagar      │          │ 119,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 119,000  │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

**Entry Deletion** (Backward: Confirmada → Enviada):
```
Action: DELETE FROM journal_entries WHERE entry_number = 'COMP-FC-001'

Result:
  - Journal entry COMP-FC-001 completely removed
  - All journal_lines cascade deleted
  - Clean slate (as if never confirmed)

Note: This follows Zoho Books approach for draft/in-progress invoices.
For auditing, use application logs or database audit tables if needed.
```

### Payment Journal Entry (Paid Status)

**Payment**: $119,000 CLP via "Transferencia"

**Journal Entry Created**:
```
Entry Number: PAGO-FC-001
Date: 2025-10-12
Type: payment
Status: posted

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 2101 Cuentas por Pagar      │ 119,000  │          │
│ 1101 Banco                  │          │ 119,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 119,000  │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

---

## 📦 INVENTORY LOGIC

### Stock Movement (Received)

When invoice is marked as received, stock movements are created:

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
  <quantity>,  -- Positive value (e.g., 50)
  'IN',
  'purchase_invoice',
  <invoice_id>,
  'Compra según factura COMP-FC-001',
  NOW()
);

UPDATE products
SET 
  inventory_qty = inventory_qty + <quantity>,
  updated_at = NOW()
WHERE id = <product_id>;
```

### Inventory Reversal (Revert to Draft)

When reverting from "Recibida" to "Borrador":

```sql
-- Check if sufficient inventory exists
SELECT inventory_qty >= <quantity>
FROM products
WHERE id = <product_id>;

-- If sufficient, decrease inventory
UPDATE products
SET 
  inventory_qty = inventory_qty - <quantity>,
  updated_at = NOW()
WHERE id = <product_id>;

-- Delete stock movements
DELETE FROM stock_movements
WHERE movement_type = 'purchase_invoice'
  AND reference = <invoice_id>;
```

**Important**: If insufficient inventory exists, reversal fails with error:
```
Cannot reverse invoice: insufficient inventory for some products
```

---

## 🎨 GUI COMPONENTS

### Status Badge Colors

| Status     | Color  | Hex/Material |
|------------|--------|--------------|
| Borrador   | Grey   | Colors.grey[200] / Colors.grey[800] |
| Recibida   | Green  | Colors.green[100] / Colors.green[800] |
| Pagada     | Blue   | Colors.blue[100] / Colors.blue[800] |
| Cancelada  | Red    | Colors.red[100] / Colors.red[800] |

### Button Layout by Status

#### **Borrador** (Grey Badge)
```dart
// PurchaseInvoiceDetailPage - Borrador status
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
      label: Text('Marcar como Enviada'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
      onPressed: _markAsSent,
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

**Visual**: `[📝 Editar] [📤 Marcar como Enviada (Blue)] [🗑️ Eliminar (Red)]`

---

#### **Enviada** (Blue Badge)
```dart
// PurchaseInvoiceDetailPage - Enviada status
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
      icon: Icon(Icons.check_circle),
      label: Text('Confirmar Factura'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
      onPressed: _confirmInvoice,
    ),
  ],
)
```

**Visual**: `[📝 Editar] [⬅️ Volver a Borrador] [✅ Confirmar Factura (Green)]`

---

#### **Confirmada** (Purple Badge)
```dart
// PurchaseInvoiceDetailPage - Confirmada status
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    OutlinedButton.icon(
      icon: Icon(Icons.edit),
      label: Text('Editar'),
      onPressed: _editInvoice, // Limited
    ),
    SizedBox(width: 8),
    OutlinedButton.icon(
      icon: Icon(Icons.arrow_back),
      label: Text('Volver a Enviada'),
      onPressed: _revertToSent,
    ),
    SizedBox(width: 8),
    ElevatedButton.icon(
      icon: Icon(Icons.inventory),
      label: Text('Marcar como Recibida'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
      onPressed: _markAsReceived,
    ),
  ],
)
```

**Visual**: `[📝 Editar] [⬅️ Volver a Enviada] [📦 Marcar como Recibida (Green)]`

---

#### **Recibida** (Green Badge)
```dart
// PurchaseInvoiceDetailPage - Recibida status
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    OutlinedButton.icon(
      icon: Icon(Icons.visibility),
      label: Text('Ver Detalles'),
      onPressed: _viewDetails,
    ),
    SizedBox(width: 8),
    OutlinedButton.icon(
      icon: Icon(Icons.arrow_back),
      label: Text('Volver a Confirmada'),
      onPressed: _revertToConfirmed,
    ),
    SizedBox(width: 8),
    ElevatedButton.icon(
      icon: Icon(Icons.payment),
      label: Text('Pagar Factura'),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
      onPressed: _navigateToPayment,
    ),
  ],
)
```

**Visual**: `[👁️ Ver Detalles] [⬅️ Volver a Confirmada] [💰 Pagar Factura (Blue)]`

---

#### **Pagada** (Blue Badge)
```dart
// PurchaseInvoiceDetailPage - Pagada status
Row(
  mainAxisAlignment: MainAxisAlignment.end,
  children: [
    OutlinedButton.icon(
      icon: Icon(Icons.visibility),
      label: Text('Ver Detalles'),
      onPressed: _viewDetails,
    ),
    SizedBox(width: 8),
    TextButton.icon(
      icon: Icon(Icons.undo, color: Colors.red),
      label: Text('Deshacer Pago', style: TextStyle(color: Colors.red)),
      onPressed: _undoPayment,
    ),
  ],
)
```

**Visual**: `[👁️ Ver Detalles] [🔄 Deshacer Pago (Red)]`

---

## 🔐 BUSINESS RULES

### Status Transition Rules

| From       | To         | Allowed? | Condition | Accounting Impact | Inventory Impact |
|------------|------------|----------|-----------|-------------------|------------------|
| Borrador   | Enviada    | ✅ Yes   | Always | ❌ None | ❌ None |
| Enviada    | Borrador   | ✅ Yes   | Always | ❌ None | ❌ None |
| Enviada    | Confirmada | ✅ Yes   | Always | ✅ Creates AP entry | ❌ None |
| Confirmada | Enviada    | ✅ Yes   | Always | ✅ Creates REVERSAL entry | ❌ None |
| Confirmada | Recibida   | ✅ Yes   | Always | ❌ None | ✅ Increases inventory |
| Recibida   | Confirmada | ✅ Yes   | **Only if sufficient inventory** | ❌ None | ✅ Decreases inventory |
| Recibida   | Pagada     | ✅ Auto  | When payment >= balance | ✅ Creates payment entry | ❌ None |
| Pagada     | Recibida   | ✅ Auto  | When payment deleted | ✅ Deletes payment entry | ❌ None |

### Edit Restrictions

- **Borrador**: ✅ Fully editable (all fields, all items)
- **Enviada**: ✅ Fully editable (order not yet confirmed)
- **Confirmada**: ⚠️ Limited editing (accounting entry exists, cannot change amounts/items easily)
- **Recibida**: ⚠️ Very limited (inventory already updated, changes require complex reversals)
- **Pagada**: ❌ View only (payment recorded, process complete)

### Deletion Rules

- **Can only delete Borrador and Enviada statuses**
- Confirmada/Recibida/Pagada invoices must be reverted step by step
- **Journal Entries**: REVERSED (not deleted) - creates reversal entry with REV- prefix
- **Stock Movements**: DELETED when reverting from Recibida → Confirmada
- **Payments**: Can be deleted individually (via "Deshacer Pago"), invoice returns to "Recibida"
- **Audit Trail**: Complete history maintained with reversal entries

---

## 🔄 KEY DIFFERENCES: SALES vs PURCHASES

| Aspect | Sales Invoice | Purchase Invoice |
|--------|---------------|------------------|
| **Statuses** | Borrador → Enviada → Confirmada → Pagada | Borrador → Enviada → Confirmada → Recibida → Pagada |
| **Total Statuses** | 4 statuses | 5 statuses |
| **Inventory Direction** | OUT (decrease) | IN (increase) |
| **Inventory Timing** | At "Confirmada" | At "Recibida" |
| **Account Type** | Accounts Receivable (AR) | Accounts Payable (AP) |
| **Accounting Timing** | At "Confirmada" | At "Confirmada" (both same) |
| **IVA Type** | IVA Débito Fiscal (2150) | IVA Crédito Fiscal (1107/1140) |
| **Reversal Method** | DELETE journal entries | CREATE reversal entries (REV-xxx) |
| **Audit Trail** | Simpler (entries deleted) | Complete (reversals kept) |
| **Primary Confirm Action** | "Confirmar" → Accounting + Inventory | "Confirmar Factura" → Accounting only |
| **Secondary Action** | "Pagar factura" → Payment | "Marcar como Recibida" → Inventory |
| **Payment Action** | Same page, inline payment | Navigates to payment form page |
| **Movement Type** | `sales_invoice` | `purchase_invoice` |
| **Stock Movement Type** | OUT | IN |
| **Journal Entry** | DR: AR, CR: Sales/IVA/Inventory | DR: Inv/IVA, CR: AP |
| **Reversal Approach** | Zoho Books style (clean) | Traditional accounting (audit) |
| **Why Different?** | Customer-facing (simpler) | Supplier-facing (audit trail) |

---

## 🗄️ DATABASE TRIGGERS

### Main Trigger: `handle_purchase_invoice_change()`

Located in: `supabase/sql/purchase_invoice_workflow.sql`

**Trigger Events**:
- `AFTER INSERT ON purchase_invoices`
- `AFTER UPDATE ON purchase_invoices`

**Logic**:
```sql
IF TG_OP = 'INSERT' THEN
  IF status = 'received' THEN
    → consume_purchase_invoice_inventory()
    → create_purchase_invoice_journal_entry()
  END IF

ELSIF TG_OP = 'UPDATE' THEN
  IF old_status != 'received' AND new_status = 'received' THEN
    → consume_purchase_invoice_inventory()
    → create_purchase_invoice_journal_entry()
  END IF
END IF
```

### Reversal Trigger: `handle_purchase_invoice_status_reversal()`

Located in: `supabase/sql/purchase_invoice_reversal.sql`

**Logic**:
```sql
IF old_status = 'received' AND new_status = 'draft' THEN
  → reverse_purchase_invoice_inventory()
  → reverse_purchase_invoice_journal_entry()
  
ELSIF old_status = 'paid' AND new_status = 'received' THEN
  -- Just status change, no reversals
  
ELSIF old_status = 'paid' AND new_status = 'draft' THEN
  → reverse_purchase_invoice_inventory()
  → reverse_purchase_invoice_journal_entry()
  -- Future: Delete payment record
END IF
```

### Inventory Functions

**`consume_purchase_invoice_inventory()`**:
- Finds all 'received' invoices without stock movements
- Creates IN movements
- Increases product inventory
- Prevents duplicate processing

**`reverse_purchase_invoice_inventory(invoice_id)`**:
- Checks if sufficient inventory exists
- Decreases product quantities
- Deletes stock movements
- Throws exception if insufficient inventory

### Accounting Functions

**`create_purchase_invoice_journal_entry(invoice_id)`**:
- Creates posted journal entry
- DR: Inventory + IVA Crédito
- CR: Accounts Payable
- Prevents duplicate entries

**`reverse_purchase_invoice_journal_entry(invoice_id)`**:
- Finds original journal entry
- Creates reversal entry (REV-xxx)
- Marks original as "reversed" (future)
- Maintains complete audit trail

---

## 🧪 TESTING SCENARIOS

### Test 1: Complete Forward Flow
1. Create purchase invoice (Draft)
2. Mark as Received → Verify journal entry created, inventory increased
3. Mark as Paid → Verify payment entry created, status = Paid

### Test 2: Backward Flow (Received → Draft)
1. Create and mark as received
2. Verify journal entry exists
3. Verify inventory increased
4. Revert to Draft
5. Verify REVERSAL entry created (not deleted)
6. Verify inventory DECREASED back

### Test 3: Insufficient Inventory Reversal
1. Create and receive purchase invoice (+50 units)
2. Create sales invoice consuming 40 units
3. Try to revert purchase to draft
4. Verify error: "Cannot reverse: insufficient inventory"

### Test 4: Paid → Received → Draft
1. Create, receive, and pay invoice
2. Revert from Paid to Received → Verify only status changes
3. Revert from Received to Draft → Verify reversal entry + inventory decrease

### Test 5: Multiple Products
1. Create invoice with 3 different products
2. Mark as received
3. Verify all 3 products have increased inventory
4. Verify journal entry has correct total
5. Revert to draft
6. Verify all 3 products decreased back

---

## 🌍 LOCALIZATION (Chilean Context)

- **Currency**: CLP (Chilean Peso)
- **Tax**: IVA 19% (as **credit** for purchases, deductible from tax liability)
- **Date Format**: DD/MM/YYYY
- **Language**: Spanish (primary)
- **All UI labels in Spanish**:
  - "Borrador", "Recibida", "Pagada"
  - "Marcar como Recibida", "Marcar como Pagada"
  - "Volver a Borrador", "Volver a Recibida"

---

## 🔧 AGENT INSTRUCTIONS

### When Implementing Status Transitions:
1. ✅ Always use button-driven transitions
2. ✅ Show confirmation dialogs for backward transitions
3. ✅ Use REVERSAL entries for journal entries (not delete)
4. ✅ Check inventory availability before reversing
5. ✅ Update UI immediately after status change
6. ✅ Show appropriate snackbar messages
7. ✅ Keep status badge colors consistent

### When Debugging:
1. Check `journal_entries` table for source_module='purchase_invoice'
2. Look for reversal entries with type='reversal'
3. Check `stock_movements` table for movement_type='purchase_invoice'
4. Verify product `inventory_qty` increased/decreased correctly
5. Check trigger execution logs in Supabase

### Code References:
- **UI**: `lib/modules/purchases/pages/purchase_invoice_form_page.dart`
- **Service**: `lib/modules/purchases/services/purchase_service.dart`
- **SQL Triggers**: `supabase/sql/purchase_invoice_workflow.sql`
- **Reversal Logic**: `supabase/sql/purchase_invoice_reversal.sql`

### Important Notes:
- **Purchases use REVERSAL entries** (traditional accounting)
- **Sales use DELETE entries** (Zoho Books style)
- This maintains better audit trail for purchases (supplier relationships)
- Both approaches are valid, chosen for different business needs
- Inventory can only be reversed if sufficient stock exists
