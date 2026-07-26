# PURCHASE INVOICE — PAYMENT MODEL SELECTION

> [!WARNING]
> **Historical business context; not UI authority.** Reconcile this model with
> the current purchase architecture before implementation. Every visual,
> layout, navigation, component, color, spacing, badge, modal/dialog/snackbar,
> responsive, and platform recipe below is superseded by
> [`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md) and
> [`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> copy an old widget or treat selection as an automatic centered dialog. Choose
> inline, in-block, pane, popover, sheet, blocking surface, or full route from
> task evidence; none is a mandatory pattern.

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

## MODEL-SELECTION DECISION

### When Triggered
The model-selection decision is required when:
1. User clicks **[+ Nueva Factura de Compra]** button
2. Before the purchase invoice form opens

The host and interaction surface are deliberately unspecified. Preserve the
originating list context and choose the surface under the canonical GUI guides.

### Decision content

**Title**: "Seleccionar Modelo de Pago"

**Message**: 
```
¿Cómo se va a gestionar el pago de esta factura de compra?

Esto determina el flujo de estados y cuándo se registra el pago.
```

**Options**:

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

**Commands**:
- Cancelar
- Continuar, enabled only after a valid model is selected

### Frontend behavior

- The create command requests one explicit model before the first save.
- Cancel returns to the exact originating list state.
- Continue opens the canonical purchase-invoice editor with the selected model.
- The interaction must not create a second writer or bypass the canonical
  validation/permission path.
- A durable route is optional and must be selected from history/return
  semantics, not because this historical prompt used one.

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

### Action availability logic

```dart
// PurchaseInvoiceFormPage
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

## UI information contract

- The selected model must remain clearly visible and accessible by text and
  semantics wherever it changes the next action.
- A badge, chip, timeline, colored container, or icon is optional. Let the
  current task, information density, viewport, and canonical visual system
  determine the representation.
- When history materially helps a decision, show the correct sequence for the
  selected model. Do not render a lifecycle graphic merely as decoration.
- Status and model must never be communicated by color alone or through
  feature-owned literal hues.

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
- [ ] Add an explicit model-selection interaction to the canonical create flow
- [ ] Update PurchaseInvoiceFormPage to accept `isPrepayment` parameter
- [ ] Expose the selected model clearly without prescribing a badge
- [ ] Implement conditional action availability based on model
- [ ] Expose model-specific history only where it supports the task
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

The canonical editor must expose the persisted model as read-only and explain
that it cannot be changed. This is a behavioral requirement, not a prescription
for a disabled tile, lock icon, badge, or other particular control.

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
