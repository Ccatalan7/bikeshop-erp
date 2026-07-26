# PURCHASE INVOICE STATUS FLOW — STANDARD MODEL (PAY AFTER RECEIPT)


> [!WARNING]
> **Historical business context; not UI authority.** Reconcile this flow with
> the current canonical purchase owner before implementing it. Every visual,
> layout, navigation, component, color, spacing, badge, modal/dialog/snackbar,
> responsive, and platform recipe below is superseded by
> [GUI_DESIGN_PRINCIPLES.md](GUI_DESIGN_PRINCIPLES.md) and
> [GUI_MOBILE_DESIGN_PRINCIPLES.md](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> imitate another product, old screenshot, or local widget. Choose inline,
> in-block, pane, popover, sheet, blocking surface, or full route from task
> evidence; none is an automatic status-flow pattern.


## Overview

This document describes the **Standard Purchase Invoice Workflow** implemented in the Vinabike ERP. This is the traditional "Pay After Receipt" model where:
- Orders are sent to suppliers
- Suppliers confirm and issue invoices
- Goods are received and verified
- Payment is made after receipt

The workflow **mirrors the sales invoice flow** but handles supplier invoices with inventory IN movements and Accounts Payable accounting.

This historical flow uses **DELETE-based reversals** for purchase invoices. When going backward, journal entries are deleted completely, not marked as reversed. This provides a cleaner, simpler approach for draft/in-progress invoices.

**Payment Model Selection**: Before the first save, the create flow requires the
user to choose between:
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
       │ ➡️ [Pagar Factura] → Payment workflow
       │    • Opens through the host selected by the canonical GUI rules
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
- **State presentation**: Theme-owned and legible without color alone
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
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Order sent to supplier, waiting for their confirmation
- **Available Actions**:
  - ✏️ **[Editar]** button → Opens form in edit mode
  - ⬅️ **[Volver a Borrador]** button → Changes status to 'draft'
  - ✅ **[Confirmar Factura]** button → Changes status to 'confirmed' + triggers accounting

---

### 3. **Confirmada** (Confirmed by Supplier)
- **Spanish Label**: "Confirmada"
- **State presentation**: Theme-owned and legible without color alone
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
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: — (already created when confirmed)
- **Inventory Effect**: ✅ Stock INCREASED (IN movement)
  - **Trigger**: `consume_purchase_invoice_inventory()`
  - **Stock movements**: type='IN', movement_type='purchase_invoice'
  - **Products table**: `inventory_qty += quantity`
- **Description**: Goods physically received in store, inventory updated, ready to pay
- **Available Actions**:
  - ✏️ **[Editar]** button → Very limited editing
  - 💰 **[Pagar Factura]** button → Opens the canonical payment workflow
  - ⬅️ **[Volver a Confirmada]** button → Creates reversal for inventory, decreases stock

---

### 5. **Pagada** (Paid to Supplier)
- **Spanish Label**: "Pagada"
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: ✅ Payment journal entry created
  - **Debit**: Cuentas por Pagar (2101 or 2120)
  - **Credit**: Cash/Bank account (1110 or 1101)
- **Inventory Effect**: — (already increased when received)
- **Description**: Invoice has been paid to supplier, process complete
- **Available Actions**:
  - ✏️ **[Ver Detalles]** button → View-only mode
  - ⬅️ **[Deshacer Pago]** button → Deletes payment record AND payment journal entry, returns to 'received'

---

## 🔀 STATUS TRANSITIONS — DETAILED BUTTON & TRIGGER MAPPING

### Forward Transitions

#### **Borrador → Enviada**

**User Interaction**:
1. User opens purchase invoice in detail page
2. Sees status "Borrador"
3. Invokes **[Marcar como Enviada]**

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

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
- State label changes to **"Enviada"**
- Buttons visible:
  - **[Editar]** (outlined)
  - **[Volver a Borrador]**
  - **[Confirmar Factura]** ← Primary action
- Scoped feedback: "Factura marcada como enviada"

---

#### **Enviada → Confirmada**

**User Interaction**:
1. User sees status "Enviada"
2. Invokes **[Confirmar Factura]**
3. Optional explicit confirmation when risk warrants it
   - Title: "Confirmar factura de compra"
   - Message: "Esto creará un asiento contable (Inventario + IVA / Cuentas por Pagar). ¿Continuar?"
   - Buttons: [Cancelar] [Confirmar]

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

**SQL Trigger**: ✅ `handle_purchase_invoice_change()`

**Trigger Logic** (following sales invoice pattern):
```sql
CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
RETURNS TRIGGER AS $$
DECLARE
  v_old_status TEXT;
  v_new_status TEXT;
  v_old_posted BOOLEAN;
  v_new_posted BOOLEAN;
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_new_status := lower(trim(NEW.status));
    v_new_posted := NOT (v_new_status = ANY(v_non_posted));
    
    IF v_new_posted THEN
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    END IF;
    
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_status := lower(trim(OLD.status));
    v_new_status := lower(trim(NEW.status));
    v_old_posted := NOT (v_old_status = ANY(v_non_posted));
    v_new_posted := NOT (v_new_status = ANY(v_non_posted));
    
    IF v_old_posted AND NOT v_new_posted THEN
      -- Confirmed → Sent: DELETE journal entry
      DELETE FROM public.journal_entries
      WHERE source_module = 'purchase_invoices' 
        AND source_reference = OLD.id::text;
        
    ELSIF NOT v_old_posted AND v_new_posted THEN
      -- Sent → Confirmed: CREATE journal entry
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
      
    ELSIF v_old_posted AND v_new_posted THEN
      -- Both posted states: recreate
      DELETE FROM public.journal_entries
      WHERE source_module = 'purchase_invoices' 
        AND source_reference = OLD.id::text;
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    END IF;
    
    -- Handle inventory transitions
    IF v_old_status != 'received' AND v_new_status = 'received' THEN
      PERFORM public.consume_purchase_invoice_inventory(NEW);
    ELSIF v_old_status = 'received' AND v_new_status != 'received' THEN
      PERFORM public.restore_purchase_invoice_inventory(NEW);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Trigger Function**: `create_purchase_invoice_journal_entry(invoice_record)`

**Function Implementation** (following sales invoice pattern):
```sql
CREATE OR REPLACE FUNCTION public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
RETURNS VOID AS $$
DECLARE
  v_entry_id INTEGER;
  v_inventory_account_id INTEGER;
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
  
  -- Ensure accounts exist (helper function from core_schema.sql)
  v_inventory_account_id := public.ensure_account('1105', 'Inventario');
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
    'COMP-FC-' || p_invoice.invoice_number,
    p_invoice.date,
    'purchase_invoice',
    'posted',
    'purchase_invoices',
    p_invoice.id::text,
    'Compra según factura ' || p_invoice.invoice_number || 
    CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END
  ) RETURNING id INTO v_entry_id;
  
  -- Create journal lines
  INSERT INTO public.journal_lines (entry_id, account_id, debit_amount, credit_amount, description)
  VALUES
    -- DR: Inventory
    (v_entry_id, v_inventory_account_id, p_invoice.subtotal, 0, 
     'Inventario compra FC-' || p_invoice.invoice_number),
    -- DR: IVA Crédito Fiscal
    (v_entry_id, v_iva_account_id, p_invoice.iva_amount, 0, 
     'IVA Crédito Fiscal'),
    -- CR: Accounts Payable
    (v_entry_id, v_ap_account_id, 0, p_invoice.total, 
     'Cuentas por Pagar' || 
     CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END);
END;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- `purchase_invoices.status` = 'confirmed'
- ✅ `journal_entries` record created
- ✅ `journal_lines` records created (3 lines: Inventory DR, IVA DR, AP CR)
- ❌ NO inventory changes yet

**GUI Update**:
- State label changes to **"Confirmada"**
- Buttons visible:
  - **[Editar]** (outlined, disabled or limited)
  - **[Volver a Enviada]**
  - **[Marcar como Recibida]** ← Primary action
- Scoped feedback: "Factura confirmada - asiento contable creado"

---

#### **Confirmada → Recibida**

**User Interaction**:
1. User sees status "Confirmada"
2. Invokes **[Marcar como Recibida]**
3. Explicit receipt verification is required
   - Title: "Marcar productos como recibidos"
   - Message: "¿Los productos fueron entregados físicamente en la tienda? Esto aumentará el inventario."
   - Buttons: [Cancelar] [Confirmar Recepción]

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

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

**Trigger Logic** (shown above, handles inventory on status change):
```sql
-- In handle_purchase_invoice_change():
IF v_old_status != 'received' AND v_new_status = 'received' THEN
  PERFORM public.consume_purchase_invoice_inventory(NEW);
END IF;
```

**Trigger Function**: `consume_purchase_invoice_inventory(invoice_record)`

**Function Implementation** (following sales invoice pattern):
```sql
CREATE OR REPLACE FUNCTION public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
RETURNS VOID AS $$
DECLARE
  v_item RECORD;
  v_items JSONB;
  v_reference TEXT;
  v_product_id UUID;
  v_quantity_int INTEGER;
BEGIN
  v_items := p_invoice.items;
  v_reference := 'purchase_invoice:' || p_invoice.id::text;
  
  -- Check if already processed
  IF EXISTS (
    SELECT 1 FROM public.stock_movements
    WHERE reference = v_reference
  ) THEN
    RETURN;
  END IF;
  
  -- Loop through invoice items
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    v_product_id := (v_item.value->>'product_id')::uuid;
    v_quantity_int := coalesce((v_item.value->>'quantity')::integer, 0);
    
    IF v_product_id IS NULL OR v_quantity_int <= 0 THEN
      CONTINUE;
    END IF;
    
    -- Increase inventory (IN movement)
    UPDATE public.products
    SET inventory_qty = inventory_qty + v_quantity_int
    WHERE id = v_product_id
      AND is_service = false;
    
    -- Create stock movement record
    INSERT INTO public.stock_movements (
      product_id,
      quantity,
      movement_type,
      reference,
      notes,
      created_at
    ) VALUES (
      v_product_id,
      v_quantity_int,  -- Positive for IN
      'purchase_invoice',
      v_reference,
      'Compra FC-' || p_invoice.invoice_number,
      NOW()
    );
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
- State label changes to **"Recibida"**
- Buttons visible:
  - **[Ver Detalles]** (outlined)
  - **[Volver a Confirmada]**
  - **[Pagar Factura]** ← Primary action
- Scoped feedback: "Productos recibidos - inventario actualizado"

---

#### **Recibida → Pagada**

**User Interaction**:
1. User sees status "Recibida"
2. Invokes **[Pagar Factura]**
3. Opens the canonical payment workflow through the host selected by the
   current task and GUI guides
4. User fills payment form:
   - **Payment method** (Dropdown populated from `payment_methods` table)
     - Examples: "Efectivo", "Transferencia Bancaria", "Tarjeta", "Cheque"
     - Dynamic: users can add new methods via Contabilidad → Métodos de Pago
   - Amount (defaults to remaining balance)
   - Payment date (defaults to today)
   - Reference (auto-shown if `payment_methods.requires_reference = true`)
   - Notes
5. Clicks **[Guardar Pago]** button

**Frontend navigation behavior**:
Open the canonical payment editor through the lightest justified host and
restore the exact invoice/list context after save or cancellation. Route
replacement is not prescribed.

**Payment editor behavior**:
Load active payment methods from the canonical source, validate the required
amount/date/reference fields, invoke the shared payment command once, preserve
entered values after recoverable failure, and return through the host contract.

**Backend Service** (`PurchaseService.registerPayment()`):
```dart
Future<void> registerPayment({
  required int invoiceId,
  required double amount,
  required String paymentMethodId, // UUID from payment_methods table
  required DateTime paymentDate,
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
EXECUTE FUNCTION handle_purchase_payment_change();
```

**Trigger Function** (following sales payment pattern):
```sql
CREATE OR REPLACE FUNCTION public.handle_purchase_payment_change()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Create payment journal entry
    PERFORM public.create_purchase_payment_journal_entry(NEW);
    
    -- Note: Invoice status update should be handled by application logic
    -- or calculated on-the-fly when querying invoice status
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Delete payment journal entry
    DELETE FROM public.journal_entries
    WHERE source_module = 'purchase_payments'
      AND source_reference = OLD.id::text;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

**Payment Journal Entry Function** (Dynamic - Uses payment_methods table):
```sql
CREATE OR REPLACE FUNCTION public.create_purchase_payment_journal_entry(p_payment public.purchase_payments)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID := gen_random_uuid();
  v_exists BOOLEAN;
  v_payment_method RECORD;
  v_cash_account_id UUID;
  v_cash_account_code TEXT;
  v_cash_account_name TEXT;
  v_payable_account_id UUID;
  v_payable_account_code TEXT := '2101';
  v_payable_account_name TEXT := 'Cuentas por Pagar Proveedores';
  v_description TEXT;
BEGIN
  IF p_payment.invoice_id IS NULL THEN
    RETURN;
  END IF;

  -- Check if entry already exists
  SELECT EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE source_module = 'purchase_payments'
      AND source_reference = p_payment.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Get invoice info
  SELECT id, invoice_number, supplier_name, total
  INTO v_invoice
  FROM public.purchase_invoices
  WHERE id = p_payment.invoice_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- ⭐ Get payment method and its associated account (DYNAMIC!)
  SELECT pm.id, pm.code, pm.name, 
         a.id as account_id, a.code as account_code, a.name as account_name
  INTO v_payment_method
  FROM public.payment_methods pm
  JOIN public.accounts a ON a.id = pm.account_id
  WHERE pm.id = p_payment.payment_method_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment method not found for payment %', p_payment.id;
  END IF;

  -- Use the account from payment method configuration
  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_payable_account_id := public.ensure_account(
    v_payable_account_code,
    v_payable_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    NULL
  );

  v_description := format('Pago factura compra %s - %s', 
    COALESCE(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  -- Create journal entry header
  INSERT INTO public.journal_entries (
    id, entry_number, date, description, type,
    source_module, source_reference, status,
    total_debit, total_credit, created_at, updated_at
  ) VALUES (
    v_entry_id,
    CONCAT('PPAY-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')),
    COALESCE(p_payment.date, NOW()),
    v_description,
    'payment',
    'purchase_payments',
    p_payment.id::text,
    'posted',
    p_payment.amount,
    p_payment.amount,
    NOW(),
    NOW()
  );

  -- DR: Accounts Payable (reduce liability)
  INSERT INTO public.journal_lines (
    id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_entry_id, v_payable_account_id,
    v_payable_account_code, v_payable_account_name,
    v_description, p_payment.amount, 0, NOW(), NOW()
  );

  -- CR: Cash/Bank account (reduce asset) ← Account determined by payment_methods table!
  INSERT INTO public.journal_lines (
    id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_entry_id, v_cash_account_id,
    v_cash_account_code, v_cash_account_name,
    v_description, 0, p_payment.amount, NOW(), NOW()
  );
END;
$$;
$$ LANGUAGE plpgsql;
```

**Database Changes**:
- ✅ `purchase_payments` record created
- ✅ `journal_entries` record created (payment entry)
- ✅ `journal_lines` records created (2 lines: AP DR, Bank CR)
- `purchase_invoices.paid_amount` = total of all payments (calculated by app)
- `purchase_invoices.balance` = total - paid_amount (calculated by app)
- `purchase_invoices.status` = 'paid' (if fully paid, updated by app)
- ❌ No inventory changes

**GUI Update**:
- State label changes to **"Pagada"** (if fully paid)
- Buttons visible:
  - **[Ver Detalles]** (outlined)
  - **[Deshacer Pago]**
- Shows payment information:
  - Payment date
  - Payment method
  - Amount paid
- Scoped feedback: "Pago registrado correctamente"

---

### Backward Transitions (Reversals)

#### **Enviada → Borrador**

**User Interaction**:
1. User sees status "Enviada"
2. Invokes **[Volver a Borrador]**
3. Optional: Simple confirmation
   - Message: "¿Cancelar orden enviada y volver a borrador?"
   - Buttons: [No] [Sí]

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

**SQL Trigger**: ❌ None (simple status change)

**Database Changes**:
- `purchase_invoices.status` = 'draft'
- ❌ No journal entries affected
- ❌ No inventory changes

**GUI Update**:
- State label changes to **"Borrador"**
- Buttons visible: **[Editar]** **[Marcar como Enviada]** **[Eliminar]**
- Scoped feedback: "Factura revertida a borrador"

---

#### **Confirmada → Enviada**

**User Interaction**:
1. User sees status "Confirmada"
2. Invokes **[Volver a Enviada]**
3. **Explicit confirmation requirement** (surface selected by the canonical GUI guide):
   - Title: "Revertir factura confirmada"
   - Message: "⚠️ Esto creará un asiento contable de REVERSO y eliminará el pasivo. ¿Continuar?"
   - Buttons: [Cancelar] [Sí, Revertir]

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

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

**Trigger Logic** (shown earlier):
```sql
-- In handle_purchase_invoice_change():
IF v_old_posted AND NOT v_new_posted THEN
  -- Confirmed → Sent: DELETE journal entry (historical DELETE-based approach)
  DELETE FROM public.journal_entries
  WHERE source_module = 'purchase_invoices' 
    AND source_reference = OLD.id::text;
  -- journal_lines cascade deleted automatically
END IF;
```

**Database Changes**:
- `purchase_invoices.status` = 'sent'
- ✅ `journal_entries` record **DELETED** (source_module='purchase_invoices')
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
- State label changes to **"Enviada"**
- Buttons visible: **[Editar]** **[Volver a Borrador]** **[Confirmar Factura]**
- Scoped feedback: "Factura revertida a enviada - asiento contable eliminado"

---

#### **Recibida → Confirmada**

**User Interaction**:
1. User sees status "Recibida"
2. Invokes **[Volver a Confirmada]**
3. **Explicit confirmation requirement** (surface selected by the canonical GUI guide):
   - Title: "Revertir productos recibidos"
   - Message: "⚠️ Esto DISMINUIRÁ el inventario. Solo si los productos NO han sido vendidos. ¿Continuar?"
   - Buttons: [Cancelar] [Sí, Revertir]

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

**Backend Service**:
```dart
Future<void> revertToConfirmed(int invoiceId) async {
  await _supabase
      .from('purchase_invoices')
      .update({'status': 'confirmed'})
      .eq('id', invoiceId);
  // Trigger will check inventory and restore
}
```

**SQL Trigger**: ✅ `handle_purchase_invoice_change()`

**Trigger Logic** (shown earlier):
```sql
-- In handle_purchase_invoice_change():
ELSIF v_old_status = 'received' AND v_new_status != 'received' THEN
  PERFORM public.restore_purchase_invoice_inventory(NEW);
END IF;
```

**Inventory Restoration Function** (following sales invoice pattern):
```sql
CREATE OR REPLACE FUNCTION public.restore_purchase_invoice_inventory(p_invoice public.purchase_invoices)
RETURNS VOID AS $$
DECLARE
  v_movement RECORD;
  v_reference TEXT;
  v_quantity_int INTEGER;
BEGIN
  v_reference := 'purchase_invoice:' || p_invoice.id::text;
  
  -- Find all stock movements for this invoice
  FOR v_movement IN
    SELECT product_id, quantity
    FROM public.stock_movements
    WHERE reference = v_reference
      AND movement_type = 'purchase_invoice'
  LOOP
    -- Use abs() to ensure we subtract the correct amount
    v_quantity_int := abs(coalesce(v_movement.quantity::int, 0));
    
    IF v_quantity_int <= 0 THEN
      CONTINUE;
    END IF;
    
    -- Decrease inventory (reverse the IN movement)
    UPDATE public.products
    SET inventory_qty = GREATEST(0, inventory_qty - v_quantity_int)
    WHERE id = v_movement.product_id
      AND is_service = false;
  END LOOP;
  
  -- Delete stock movement records
  DELETE FROM public.stock_movements
  WHERE reference = v_reference
    AND movement_type = 'purchase_invoice';
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
- State label changes to **"Confirmada"**
- Buttons visible: **[Editar]** **[Volver a Enviada]** **[Marcar como Recibida]**
- Scoped feedback: "Factura revertida a confirmada - inventario disminuido"

---

#### **Pagada → Recibida** (Undo Payment)

**User Interaction**:
1. User sees status "Pagada"
2. Invokes **[Deshacer Pago]**
3. **Explicit confirmation requirement** (surface selected by the canonical GUI guide):
   - Title: "Deshacer pago"
   - Message: "Se eliminará el registro de pago de $119,000 CLP y su asiento contable. ¿Continuar?"
   - Buttons: [Cancelar] [Sí, Deshacer]

**Frontend behavior**:
- Invoke the canonical business command once and keep loading/error state with
  the current host.
- Communicate the persisted outcome at the scope of the operation.
- Preserve the exact originating list/editor context; this historical document
  does not prescribe route replacement or a transient surface.

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

**SQL Trigger**: ✅ Similar pattern to sales payments (DELETE-based)

**Expected Trigger Logic** (to be implemented in core_schema.sql):
```sql
CREATE OR REPLACE FUNCTION public.handle_purchase_payment_deletion()
RETURNS TRIGGER AS $$
BEGIN
  -- Delete payment journal entry
  DELETE FROM public.journal_entries
  WHERE source_module = 'purchase_payments'
    AND source_reference = OLD.id::text;
  
  -- Note: Invoice status update should be handled by application logic
  -- or a separate trigger that recalculates paid_amount and balance
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_purchase_payment_deletion
AFTER DELETE ON purchase_payments
FOR EACH ROW
EXECUTE FUNCTION public.handle_purchase_payment_deletion();
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
- State label changes to **"Recibida"**
- Buttons visible: **[Ver Detalles]** **[Volver a Confirmada]** **[Pagar Factura]**
- Balance shows unpaid amount again
- Scoped feedback: "Pago eliminado correctamente"

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

Historical note: this document records complete deletion of the draft or
in-progress entry rather than using it as a visual or product-model precedent.
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

## GUI interaction contract

- Expose current state with a clear label and semantics. A badge is optional,
  and this document does not prescribe a hue, icon, chip, or container.
- Expose only the commands allowed by the current business state, grouped by
  actual scope and frequency.
- Let the canonical visual system determine action weight, feedback, status
  treatment, and responsive composition. Do not assign one bright color to
  each lifecycle state.
- Risky reversals must state their accounting, payment, and inventory
  consequences and require an intentional decision. The correct interaction
  surface depends on risk and host; a centered dialog is not automatic.
- Preserve purchase-list filters, selection, scroll, and invoice context while
  entering payment, receipt, or reversal work.

## 🔐 BUSINESS RULES

### Status Transition Rules

| From       | To         | Allowed? | Condition | Accounting Impact | Inventory Impact |
|------------|------------|----------|-----------|-------------------|------------------|
| Borrador   | Enviada    | ✅ Yes   | Always | ❌ None | ❌ None |
| Enviada    | Borrador   | ✅ Yes   | Always | ❌ None | ❌ None |
| Enviada    | Confirmada | ✅ Yes   | Always | ✅ Creates AP entry | ❌ None |
| Confirmada | Enviada    | ✅ Yes   | Always | ✅ DELETES entry (historical DELETE-based approach) | ❌ None |
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
- **Journal Entries**: 
  - For Confirmada → Enviada: **DELETED** (historical DELETE-based approach, clean slate)
  - For Recibida → Confirmada: **PRESERVED** (accounting stays intact)
- **Stock Movements**: DELETED when reverting from Recibida → Confirmada
- **Payments**: Can be deleted individually (via "Deshacer Pago"), invoice returns to "Recibida"
- **Audit Trail**: Maintained via application logs and stock movement history

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
| **Reversal Method** | DELETE journal entries | DELETE journal entries (same) |
| **Audit Trail** | Simpler (entries deleted) | Simpler (entries deleted) |
| **Primary Confirm Action** | "Confirmar" → Accounting + Inventory | "Confirmar Factura" → Accounting only |
| **Secondary Action** | "Pagar factura" → Payment | "Marcar como Recibida" → Inventory |
| **Payment Action** | Uses the canonical payment command | Uses the canonical payment command; host is selected by task evidence |
| **Movement Type** | `sales_invoice` | `purchase_invoice` |
| **Stock Movement Type** | OUT | IN |
| **Journal Entry** | DR: AR, CR: Sales/IVA/Inventory | DR: Inv/IVA, CR: AP |
| **Reversal Approach** | historical DELETE-based approach (DELETE) | historical DELETE-based approach (DELETE) |
| **Why Same Reversal?** | Both use DELETE for draft/in-progress invoices (cleaner) | Both use DELETE for draft/in-progress invoices (cleaner) |

---

## 🗄️ DATABASE TRIGGERS

### Main Trigger: `handle_purchase_invoice_change()`

**Location**: Should be in `supabase/sql/core_schema.sql` (following sales invoice pattern)

**Trigger Events**:
- `AFTER INSERT ON purchase_invoices`
- `AFTER UPDATE ON purchase_invoices`

**Logic** (mirroring `handle_sales_invoice_change()`):
```sql
CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
RETURNS TRIGGER AS $$
DECLARE
  v_old_status TEXT;
  v_new_status TEXT;
  v_old_posted BOOLEAN;
  v_new_posted BOOLEAN;
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_new_status := lower(trim(NEW.status));
    v_new_posted := NOT (v_new_status = ANY(v_non_posted));
    
    IF v_new_posted THEN
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    END IF
    
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_status := lower(trim(OLD.status));
    v_new_status := lower(trim(NEW.status));
    v_old_posted := NOT (v_old_status = ANY(v_non_posted));
    v_new_posted := NOT (v_new_status = ANY(v_non_posted));
    
    -- Handle accounting (journal entries)
    IF v_old_posted AND NOT v_new_posted THEN
      -- Confirmed → Sent: DELETE journal entry
      DELETE FROM public.journal_entries
      WHERE source_module = 'purchase_invoices' 
        AND source_reference = OLD.id::text;
    ELSIF NOT v_old_posted AND v_new_posted THEN
      -- Sent → Confirmed: CREATE journal entry
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    ELSIF v_old_posted AND v_new_posted THEN
      -- Both posted: recreate
      DELETE FROM public.journal_entries
      WHERE source_module = 'purchase_invoices' 
        AND source_reference = OLD.id::text;
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    END IF;
    
    -- Handle inventory (Confirmed ↔ Recibida)
    IF v_old_status != 'received' AND v_new_status = 'received' THEN
      PERFORM public.consume_purchase_invoice_inventory(NEW);
    ELSIF v_old_status = 'received' AND v_new_status != 'received' THEN
      PERFORM public.restore_purchase_invoice_inventory(NEW);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER trg_purchase_invoice_change
AFTER INSERT OR UPDATE ON purchase_invoices
FOR EACH ROW
EXECUTE FUNCTION public.handle_purchase_invoice_change();
```

### Inventory Functions

**`consume_purchase_invoice_inventory(invoice_record)`**:
- Processes invoice items from JSONB
- Creates IN movements (positive quantity)
- Increases product inventory
- Prevents duplicate processing (checks reference)

**`restore_purchase_invoice_inventory(invoice_record)`**:
- Finds stock movements by reference
- Uses abs() to ensure correct quantity
- Decreases product inventory
- Deletes stock movement records

### Accounting Functions

**`create_purchase_invoice_journal_entry(invoice_record)`**:
- Uses `ensure_account()` helper to get account IDs
- Creates posted journal entry
- DR: Inventory (1105) + IVA Crédito Fiscal (1107)
- CR: Accounts Payable (2101)
- Prevents duplicate entries (checks source_reference)
- Uses proper column names: entry_id, debit_amount, credit_amount

**`create_purchase_payment_journal_entry(payment_record)`**:
- Creates payment journal entry
- DR: Accounts Payable (2101)
- CR: Bank/Cash (1101)
- Linked via source_module='purchase_payments' and source_reference=payment.id

**Note on Reversal Approach**:
This document describes **DELETE-based reversals** (historical DELETE-based approach) for draft/in-progress invoices. When reverting from Confirmed → Sent, the journal entry is **deleted completely**, not reversed with a REV- entry. This provides a cleaner approach for invoices that haven't been finalized.

---

## 🧪 TESTING SCENARIOS

### Test 1: Complete Forward Flow
1. Create purchase invoice (Borrador)
2. Mark as Enviada → Verify NO journal entry, NO inventory change
3. Mark as Confirmada → Verify journal entry created, NO inventory change yet
4. Mark as Recibida → Verify inventory INCREASED
5. Mark as Pagada → Verify payment entry created, status = Pagada

### Test 2: Backward Flow (Recibida → Confirmada)
1. Create, mark as enviada, confirmada, and recibida
2. Verify journal entry exists
3. Verify inventory increased
4. Revert to Confirmada
5. Verify journal entry STILL EXISTS (accounting preserved)
6. Verify inventory DECREASED back

### Test 3: Delete Journal Entry (Confirmada → Enviada)
1. Create and mark as confirmada
2. Verify journal entry exists
3. Revert to Enviada
4. Verify journal entry DELETED (not reversed, deleted!)
5. Net effect: as if never confirmed

### Test 4: Insufficient Inventory Reversal
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
2. ✅ Require an explicit, consequence-aware decision for risky reversals; let the canonical surface-selection rules choose its host
3. ✅ Use REVERSAL entries for journal entries (not delete)
4. ✅ Check inventory availability before reversing
5. ✅ Update UI immediately after status change
6. ✅ Provide feedback at the scope and duration of the operation
7. ✅ Use theme-owned state treatment with text and semantics, never literal feature colors

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
- **Sales use DELETE entries** (historical DELETE-based approach)
- This maintains better audit trail for purchases (supplier relationships)
- Both approaches are valid, chosen for different business needs
- Inventory can only be reversed if sufficient stock exists
