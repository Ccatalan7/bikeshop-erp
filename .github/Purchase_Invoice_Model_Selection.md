# PURCHASE INVOICE — PAYMENT MODEL SELECTION

## Overview

When creating a new purchase invoice, the user must choose which payment model to use. This decision is made **per-invoice** (not globally) because different suppliers and scenarios require different payment flows.

The selected model determines:
- Status flow sequence
- When accounting entries are created
- When inventory is increased
- When payment can be registered

---

## 🔀 TWO PAYMENT MODELS

### 1. **Standard Model** (Pay After Receipt)
- **Use Case**: Traditional purchases from trusted suppliers
- **Flow**: Borrador → Enviada → Confirmada → Recibida → Pagada
- **Accounting Trigger**: At "Confirmada" (AP liability created)
- **Inventory Trigger**: At "Recibida" (stock increased)
- **Payment Timing**: After goods are received and verified
- **Best For**:
  - Local suppliers
  - Established relationships
  - Cash-on-delivery terms
  - Consignment orders

### 2. **Prepayment Model** (Pay Before Receipt)
- **Use Case**: Advance payment required by supplier
- **Flow**: Borrador → Enviada → Confirmada → Pagada → Recibida
- **Accounting Trigger**: At "Confirmada" (AP + Inventory on Order)
- **Inventory Trigger**: At "Recibida" (settlement from on-order to in-stock)
- **Payment Timing**: Before goods are delivered
- **Best For**:
  - International suppliers
  - New/untrusted relationships
  - Pre-order items
  - Wire transfer requirements
  - Importation scenarios

---

## 🎯 MODEL SELECTION DIALOG

### When Triggered
The model selection dialog appears when:
1. User clicks **[+ Nueva Factura de Compra]** button
2. Before the purchase invoice form opens

### Dialog Design

**Title**: "Seleccionar Modelo de Pago"

**Message**: 
```
¿Cómo se va a gestionar el pago de esta factura de compra?

Esto determina el flujo de estados y cuándo se registra el pago.
```

**Options** (Radio buttons):

```
◉ Pago Después de Recibir (Modelo Estándar)
  ├─ Flujo: Enviada → Confirmada → Recibida → Pagada
  ├─ El pago se registra DESPUÉS de recibir los productos
  └─ Ideal para: Proveedores locales, entregas contra pago

○ Pago Anticipado (Prepago)
  ├─ Flujo: Enviada → Confirmada → Pagada → Recibida
  ├─ El pago se registra ANTES de recibir los productos
  └─ Ideal para: Importaciones, transferencias bancarias, pre-órdenes
```

**Buttons**:
- [Cancelar] (outlined, grey)
- [Continuar] (filled, blue) ← Primary action

### Frontend Implementation

**PurchaseInvoiceListPage** (FAB button):
```dart
FloatingActionButton(
  onPressed: _showModelSelectionDialog,
  child: Icon(Icons.add),
  tooltip: 'Nueva Factura de Compra',
)

void _showModelSelectionDialog() async {
  final model = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Seleccionar Modelo de Pago'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Cómo se va a gestionar el pago de esta factura de compra?',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            'Esto determina el flujo de estados y cuándo se registra el pago.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          SizedBox(height: 24),
          
          // Standard Model Option
          RadioListTile<String>(
            value: 'standard',
            groupValue: _selectedModel,
            onChanged: (value) => setState(() => _selectedModel = value),
            title: Text(
              'Pago Después de Recibir (Modelo Estándar)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text('Flujo: Enviada → Confirmada → Recibida → Pagada'),
                Text('El pago se registra DESPUÉS de recibir los productos'),
                Text(
                  'Ideal para: Proveedores locales, entregas contra pago',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Prepayment Model Option
          RadioListTile<String>(
            value: 'prepayment',
            groupValue: _selectedModel,
            onChanged: (value) => setState(() => _selectedModel = value),
            title: Text(
              'Pago Anticipado (Prepago)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text('Flujo: Enviada → Confirmada → Pagada → Recibida'),
                Text('El pago se registra ANTES de recibir los productos'),
                Text(
                  'Ideal para: Importaciones, transferencias bancarias, pre-órdenes',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _selectedModel == null 
            ? null 
            : () => Navigator.pop(context, _selectedModel),
          child: Text('Continuar'),
        ),
      ],
    ),
  );
  
  if (model != null) {
    _navigateToCreateInvoice(isPrepayment: model == 'prepayment');
  }
}

void _navigateToCreateInvoice({required bool isPrepayment}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PurchaseInvoiceFormPage(
        isPrepayment: isPrepayment,
      ),
    ),
  );
}
```

---

## 💾 DATABASE STORAGE

### Schema Addition

Add `prepayment_model` field to `purchase_invoices` table:

```sql
ALTER TABLE purchase_invoices
ADD COLUMN prepayment_model BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN purchase_invoices.prepayment_model IS 
  'TRUE = Prepayment model (pay before receipt), FALSE = Standard model (pay after receipt)';
```

### Storage Logic

```dart
// PurchaseInvoiceFormPage
Future<void> _saveInvoice() async {
  final invoiceData = {
    'invoice_number': _invoiceNumberController.text,
    'supplier_id': _selectedSupplierId,
    'total': _calculateTotal(),
    'status': 'draft',
    'prepayment_model': widget.isPrepayment, // ← Model stored here
    // ... other fields
  };
  
  await _supabase.from('purchase_invoices').insert(invoiceData);
}
```

---

## 🔄 FLOW BEHAVIOR BY MODEL

### Status Flow Differences

**Standard Model** (`prepayment_model = FALSE`):
```
Borrador → Enviada → Confirmada → Recibida → Pagada
                         ↓            ↓         ↓
                    Accounting   Inventory  Payment
```

**Prepayment Model** (`prepayment_model = TRUE`):
```
Borrador → Enviada → Confirmada → Pagada → Recibida
                         ↓          ↓         ↓
                    Accounting  Payment  Inventory
```

### Button Visibility Logic

```dart
// PurchaseInvoiceDetailPage
Widget _buildActionButtons() {
  final isPrepayment = _invoice.prepaymentModel;
  
  if (_invoice.status == 'confirmed') {
    if (isPrepayment) {
      // Prepayment model: can pay before receiving
      return ElevatedButton(
        onPressed: _navigateToPayment,
        child: Text('Registrar Pago'),
      );
    } else {
      // Standard model: must receive before paying
      return ElevatedButton(
        onPressed: _markAsReceived,
        child: Text('Marcar como Recibida'),
      );
    }
  }
  
  if (_invoice.status == 'received' && !isPrepayment) {
    // Standard model: can pay after receiving
    return ElevatedButton(
      onPressed: _navigateToPayment,
      child: Text('Pagar Factura'),
    );
  }
  
  if (_invoice.status == 'paid' && isPrepayment) {
    // Prepayment model: can receive after paying
    return ElevatedButton(
      onPressed: _markAsReceived,
      child: Text('Marcar como Recibida'),
    );
  }
  
  // ... other statuses
}
```

### SQL Trigger Logic

```sql
CREATE OR REPLACE FUNCTION handle_purchase_invoice_change()
RETURNS TRIGGER AS $$
DECLARE
  v_is_prepayment BOOLEAN;
BEGIN
  v_is_prepayment := NEW.prepayment_model;
  
  -- Accounting entry creation
  IF (OLD.status = 'sent' AND NEW.status = 'confirmed') THEN
    IF v_is_prepayment THEN
      -- Prepayment: use Inventory on Order account
      PERFORM create_prepaid_purchase_confirmation_entry(NEW.id);
    ELSE
      -- Standard: use Inventory account directly
      PERFORM create_purchase_invoice_journal_entry(NEW.id);
    END IF;
  END IF;
  
  -- Inventory increase
  IF (OLD.status != 'received' AND NEW.status = 'received') THEN
    PERFORM consume_purchase_invoice_inventory(NEW.id);
    
    IF v_is_prepayment THEN
      -- Prepayment: settle from on-order to in-stock
      PERFORM settle_prepaid_inventory_on_order(NEW.id);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## 📊 UI INDICATORS

### Model Badge Display

Show the selected model in the invoice detail page:

```dart
// PurchaseInvoiceDetailPage - Header section
Row(
  children: [
    // Status badge
    _buildStatusBadge(_invoice.status),
    
    SizedBox(width: 8),
    
    // Model indicator
    Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _invoice.prepaymentModel 
          ? Colors.orange[50] 
          : Colors.blue[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _invoice.prepaymentModel 
            ? Colors.orange[300]! 
            : Colors.blue[300]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _invoice.prepaymentModel 
              ? Icons.payment 
              : Icons.local_shipping,
            size: 14,
            color: _invoice.prepaymentModel 
              ? Colors.orange[700] 
              : Colors.blue[700],
          ),
          SizedBox(width: 4),
          Text(
            _invoice.prepaymentModel ? 'Prepago' : 'Estándar',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _invoice.prepaymentModel 
                ? Colors.orange[700] 
                : Colors.blue[700],
            ),
          ),
        ],
      ),
    ),
  ],
)
```

### Timeline View

Show different timelines based on model:

```dart
Widget _buildTimeline() {
  final isPrepayment = _invoice.prepaymentModel;
  
  if (isPrepayment) {
    return Column(
      children: [
        _buildTimelineStep('Borrador', _invoice.createdAt, completed: true),
        _buildTimelineStep('Enviada', _invoice.sentDate, completed: _invoice.status != 'draft'),
        _buildTimelineStep('Confirmada', _invoice.confirmedDate, completed: _isStatusReached('confirmed')),
        _buildTimelineStep('Pagada', _invoice.paidDate, completed: _isStatusReached('paid'), highlighted: true),
        _buildTimelineStep('Recibida', _invoice.receivedDate, completed: _isStatusReached('received')),
      ],
    );
  } else {
    return Column(
      children: [
        _buildTimelineStep('Borrador', _invoice.createdAt, completed: true),
        _buildTimelineStep('Enviada', _invoice.sentDate, completed: _invoice.status != 'draft'),
        _buildTimelineStep('Confirmada', _invoice.confirmedDate, completed: _isStatusReached('confirmed')),
        _buildTimelineStep('Recibida', _invoice.receivedDate, completed: _isStatusReached('received'), highlighted: true),
        _buildTimelineStep('Pagada', _invoice.paidDate, completed: _isStatusReached('paid')),
      ],
    );
  }
}
```

---

## ✅ IMPLEMENTATION CHECKLIST

### Database
- [ ] Add `prepayment_model` BOOLEAN column to `purchase_invoices` table
- [ ] Update SQL triggers to check `prepayment_model` field
- [ ] Create separate accounting functions for each model
- [ ] Add migration script

### Backend
- [ ] Update PurchaseService to handle both models
- [ ] Add validation logic for status transitions per model
- [ ] Implement model-specific accounting functions

### Frontend
- [ ] Create model selection dialog in PurchaseInvoiceListPage
- [ ] Update PurchaseInvoiceFormPage to accept `isPrepayment` parameter
- [ ] Update PurchaseInvoiceDetailPage to show model badge
- [ ] Implement conditional button visibility based on model
- [ ] Create model-specific timeline views
- [ ] Add model filter in list page (optional)

### Testing
- [ ] Test standard model flow end-to-end
- [ ] Test prepayment model flow end-to-end
- [ ] Test that models cannot be changed after creation
- [ ] Test backward transitions for both models
- [ ] Test accounting entries for both models

---

## 🚫 RESTRICTIONS

### Model Change Prevention

Once an invoice is created with a specific model, **it cannot be changed**:

```dart
// In edit form
if (_existingInvoice != null) {
  // Show read-only model indicator
  ListTile(
    leading: Icon(Icons.lock),
    title: Text('Modelo de Pago'),
    subtitle: Text(
      _invoice.prepaymentModel 
        ? 'Prepago (no se puede cambiar)' 
        : 'Estándar (no se puede cambiar)'
    ),
    enabled: false,
  );
}
```

### Rationale
Changing the model after creation would require:
- Reversing all accounting entries
- Changing status flow sequence
- Updating inventory logic
- Risk of data inconsistency

**Solution**: If wrong model was selected, delete the invoice and create a new one.

---

## 📖 DOCUMENTATION REFERENCES

- **Standard Model Flow**: See `Purchase_Invoice_status_flow.md`
- **Prepayment Model Flow**: See `Purchase_Invoice_Prepayment_Flow.md`
- **Accounting Logic**: Both documents contain complete accounting entry examples
- **SQL Implementation**: Trigger functions documented in both flow documents
