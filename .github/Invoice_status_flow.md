# INVOICE STATUS FLOW — HISTORICAL REVERSIBLE WORKFLOW

> [!WARNING]
> **Historical business context; not UI authority.** Reconcile the workflow with
> the current canonical invoice owner before implementing it. Every visual,
> layout, navigation, component, color, spacing, badge, modal/dialog/snackbar,
> responsive, and platform recipe below is superseded by
> [`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md) and
> [`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). Do not
> imitate another product or an old screenshot. Choose inline, in-block, pane,
> popover, sheet, blocking surface, or full route from task evidence; none is an
> automatic status-flow pattern.


## Overview

This historical document records an explicit invoice lifecycle in which each
authorized status transition activates its corresponding backend logic. It is
business-flow context, not a visual or navigation template.



This document describes the **Sales Invoice Workflow** implemented in the Vinabike ERP. The workflow follows a **reversible status model** where invoices can move forward and backward through statuses, with automatic accounting and inventory adjustments at each transition.STATUS FLOW OVERVIEW



The historical flow uses **DELETE-based reversals** rather than reversal journal
entries. Verify this against the current accounting contracts before relying on
it. Draft fields are editable through an explicit action; sending/confirming and
payment remain explicit business commands.



---Created/Sent — Status label: “Enviado”. Inventory and journal entry already processed. Button: “Registrar pago” navigates to the payment form.



## 🔄 STATUS FLOW DIAGRAMPayment Form — User enters payment method, amount, date, and notes. Button: “Guardar como pagado” or “Pagar” triggers status change to “Pagado”, which creates a payment record and a journal entry for the payment. No further inventory change occurs.



```Paid — Status label: “Pagado”. Invoice is locked from further edits. All financial records are finalized.

┌─────────────┐

│   BORRADOR  │ ← Initial state (Draft)SQL TRIGGER REFERENCE

│   (draft)   │   • Editable

└──────┬──────┘   • No accounting impactOn status change to “Enviado”: CREATE TRIGGER reduce_inventory_and_log_revenue AFTER UPDATE ON invoices FOR EACH ROW WHEN NEW.status = 'sent' BEGIN UPDATE products SET stock = stock - (SELECT quantity FROM invoice_items WHERE invoice_id = NEW.id AND product_id = products.id); INSERT INTO journal_entries (type, amount, reference_id, reference_type) VALUES ('revenue', NEW.total, NEW.id, 'invoice'); END;

       │          • No inventory impact

       │On status change to “Pagado”: CREATE TRIGGER log_payment_and_create_record AFTER UPDATE ON invoices FOR EACH ROW WHEN NEW.status = 'paid' BEGIN INSERT INTO payments (invoice_id, amount, method, date) VALUES (NEW.id, NEW.total, NEW.payment_method, CURRENT_DATE); INSERT INTO journal_entries (type, amount, reference_id, reference_type) VALUES ('payment', NEW.total, NEW.id, 'invoice'); END;

       │ ➡️ [Marcar como enviada]

       │GUI & NAVIGATION BEHAVIOR

       ⬇️

┌──────────────┐Draft view — Invoice form loads with fields locked. “Editar”
unlocks fields; “Marcar como enviado” invokes the corresponding business
transition.

│   ENVIADA    │ (Sent)

│   (sent)     │  • Delivered to customerCreated/Sent view — Status label
updates to “Enviado”. “Registrar pago” opens the canonical payment workflow
while preserving the invoice origin.

└──────┬───────┘  • No accounting impact yet

       │          • No inventory impact yetPayment workflow — User enters
payment details and an explicit save/pay command invokes the persisted
transition.

       │

       │ ⬅️ [Volver a borrador]Paid view — Status label: “Pagado”. Invoice
locked. Payment record and journal entry finalized.

       │    • Just changes status

       │HISTORICAL INTERACTION NOTES

       │ ➡️ [Confirmar]

       │    • Creates journal entry (Revenue + COGS)Status transitions must be
       │      explicit. The UI must expose current status and the next available
       │      business command, preserve return context, and use Chilean
       │      localization.

       │    • Deducts inventory

       │AGENT INSTRUCTIONS

       ⬇️

┌───────────────┐Ensure transitions are explicit and backend effects are
validated. Do not use historical screenshots as layout, component, or button
placement references.
│  CONFIRMADA   │ (Confirmed)
│ (confirmed)   │  • Accounting entry created
└──────┬────────┘  • Inventory deducted
       │           • Balance > 0 (unpaid)
       │
       │ ⬅️ [Volver a enviada]
       │    • DELETES journal entry
       │    • RESTORES inventory
       │
       │ ➡️ [Pagar factura]
       │    • Register payment
       │    • Creates payment journal entry
       │
       ⬇️
┌──────────────┐
│    PAGADA    │ (Paid)
│    (paid)    │  • Balance = 0
└──────┬───────┘  • Payment recorded
       │          • Payment journal entry created
       │
       │ ⬅️ [Deshacer pago]
       │    • DELETES payment record
       │    • DELETES payment journal entry
       │    • Returns to CONFIRMADA
       │    • Balance restored
```

---

## 📊 STATUS DEFINITIONS

### 1. **Borrador** (Draft)
- **Spanish Label**: "Borrador"
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Invoice is being prepared, fully editable
- **Available Actions**:
  - ✏️ Edit invoice
  - ➡️ Mark as "Enviada"

---

### 2. **Enviada** (Sent)
- **Spanish Label**: "Enviada"
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: ❌ None
- **Inventory Effect**: ❌ None
- **Description**: Invoice has been delivered to customer but not yet confirmed/accepted
- **Available Actions**:
  - ✏️ Edit invoice
  - ⬅️ Revert to "Borrador"
  - ✅ Confirm invoice (triggers accounting + inventory)

---

### 3. **Confirmada** (Confirmed)
- **Spanish Label**: "Confirmada"
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: ✅ Journal entry created
  - **Debit**: Cuentas por Cobrar (1120)
  - **Credit**: Ingresos por Ventas (4100)
  - **Credit**: IVA Débito Fiscal (2150)
  - **Debit**: Costo de Ventas (5101)
  - **Credit**: Inventarios (1150)
- **Inventory Effect**: ✅ Stock reduced
- **Description**: Customer has accepted the invoice, it's now in the accounting books
- **Available Actions** (if balance > 0):
  - ✏️ Edit invoice (with caution)
  - 💰 Pay invoice (register payment)
  - ⬅️ Revert to "Enviada" (deletes journal entry, restores inventory)

---

### 4. **Pagada** (Paid)
- **Spanish Label**: "Pagada"
- **State presentation**: Theme-owned and legible without color alone
- **Accounting Effect**: ✅ Payment journal entry created
  - **Debit**: Cash/Bank account
  - **Credit**: Cuentas por Cobrar (1120)
- **Inventory Effect**: — (already deducted when confirmed)
- **Description**: Invoice has been fully paid, balance = 0
- **Available Actions**:
  - ✏️ Edit invoice (limited)
  - ⬅️ Undo last payment (deletes payment, returns to "Confirmada")

---

## 🔀 STATUS TRANSITIONS

### Forward Transitions

#### **Borrador → Enviada**
```
User Action: Click "Marcar como enviada"
Backend Effect:
  • Status = 'sent'
  • ❌ No journal entry
  • ❌ No inventory change
GUI Update:
  • State label changes to "Enviada"
  • Buttons: [Editar] [Volver a borrador] [Confirmar]
```

#### **Enviada → Confirmada**
```
User Action: Invoke "Confirmar"
Backend Effect:
  • Status = 'confirmed'
  • ✅ Journal entry CREATED (revenue + COGS)
  • ✅ Inventory DEDUCTED
  • Stock movements recorded (type='OUT')
SQL Trigger: handle_sales_invoice_change()
  → consume_sales_invoice_inventory()
  → create_sales_invoice_journal_entry()
GUI Update:
  • State label changes to "Confirmada"
  • Buttons: [Pagar factura] [Editar] [Volver a enviada]
  • Give scoped non-blocking confirmation: "Factura confirmada - contabilizada"
```

#### **Confirmada → Pagada**
```
User Action: Click "Pagar factura" → Fill payment form → "Marcar como pagado"

Payment Form Fields:
  • Payment Method (Dropdown) → Populated dynamically from payment_methods table
    Examples: "Efectivo", "Transferencia Bancaria", "Tarjeta", "Cheque"
  • Amount
  • Date
  • Reference (required for transfer/check based on payment_methods.requires_reference)
  • Notes

Backend Effect:
  • Payment record CREATED (with payment_method_id reference)
  • Payment journal entry CREATED (account determined by payment_methods.account_id)
  • Status auto-updates to 'paid' when balance = 0
  • Inventory unchanged (already deducted)

SQL Trigger: handle_sales_payment_change()
  → create_sales_payment_journal_entry() (reads payment_methods.account_id dynamically)
  → recalculate_sales_invoice_payments()

Payment Method → Account Mapping (DYNAMIC configuration):
  • Efectivo → 1101 Caja General (from payment_methods table)
  • Transferencia Bancaria → 1110 Bancos (from payment_methods table)
  • Tarjeta → 1110 Bancos (from payment_methods table)
  • Cheque → 1110 Bancos (from payment_methods table)
  • **Users can add new methods via UI** (e.g., "Transfer BCI", "Transfer Santander")

GUI Update:
  • State label changes to "Pagada"
  • Shows payment method name (e.g., "Pagado con: Efectivo")
  • Buttons: [Editar] [Deshacer pago]
  • Give scoped non-blocking confirmation: "Pago registrado correctamente"
```

---

### Backward Transitions (Reversals)

#### **Enviada → Borrador**
```
User Action: Click "Volver a borrador"
Confirmation requirement (surface chosen under the canonical GUI guide):
  Title: "Revertir a borrador"
  Message: "Esto eliminará el asiento contable y restaurará el inventario. ¿Está seguro?"
Backend Effect:
  • Status = 'draft'
  • ❌ Nothing to delete (no journal entry exists)
  • ❌ Nothing to restore (no inventory change)
GUI Update:
  • State label changes to "Borrador"
  • Buttons: [Editar] [Marcar como enviada]
  • Give scoped confirmation: "Factura revertida a borrador"
```

#### **Confirmada → Enviada**
```
User Action: Click "Volver a enviada"
Confirmation requirement (surface chosen under the canonical GUI guide):
  Title: "Revertir a enviada"
  Message: "Esto eliminará el asiento contable y restaurará el inventario. ¿Está seguro?"
Backend Effect:
  • Status = 'sent'
  • ✅ Journal entry DELETED (not reversed!)
  • ✅ Inventory RESTORED (stock increased back)
  • Stock movements deleted
SQL Trigger: handle_sales_invoice_change()
  → DELETE FROM journal_entries WHERE source_reference = invoice_id
  → restore_sales_invoice_inventory()
GUI Update:
  • State label changes to "Enviada"
  • Buttons: [Editar] [Volver a borrador] [Confirmar]
  • Give scoped confirmation: "Factura revertida a enviada"
```

#### **Pagada → Confirmada** (via Undo Payment)
```
User Action: Click "Deshacer pago"
Confirmation requirement (surface chosen under the canonical GUI guide):
  Title: "Deshacer pago"
  Message: "Se eliminará el pago de $X y su asiento contable asociado. ¿Continuar?"
Backend Effect:
  • Payment record DELETED
  • Payment journal entry DELETED
  • Status auto-updates to 'confirmed' (balance > 0)
  • Inventory unchanged
SQL Trigger: Payment deletion trigger
  → DELETE payment journal entry
  → recalculate_sales_invoice_payments() → status = 'confirmed'
GUI Update:
  • State label changes to "Confirmada"
  • Balance restored
  • Buttons: [Pagar factura] [Editar] [Volver a enviada]
  • Give scoped confirmation: "Pago eliminado correctamente"
```

---

## 🧮 ACCOUNTING LOGIC

### Journal Entry Structure (Confirmed Status)

**Example Invoice**: INV-001
- Subtotal: $100,000 CLP
- IVA (19%): $19,000 CLP
- Total: $119,000 CLP
- Product cost: $60,000 CLP

**Journal Entry Created**:
```
Entry Number: INV-20251012143000
Date: 2025-10-12
Type: sales
Status: posted

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 1120 Cuentas por Cobrar     │ 119,000  │          │
│ 4100 Ingresos por Ventas    │          │ 100,000  │
│ 2150 IVA Débito Fiscal      │          │  19,000  │
│ 5101 Costo de Ventas        │  60,000  │          │
│ 1150 Inventarios            │          │  60,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 179,000  │ 179,000  │
└─────────────────────────────┴──────────┴──────────┘
```

### Payment Journal Entry (Paid Status)

**Example 1: Payment via "Efectivo"** (Cash payment)

- Payment Method: Efectivo (from payment_methods table)
- Linked Account: 1101 Caja General (from payment_methods.account_id)
- Amount: $119,000 CLP

**Journal Entry Created** (account determined dynamically):
```
Entry Number: PAY-20251012144500
Date: 2025-10-12
Type: payment
Status: posted
Description: Pago factura INV-001 - Efectivo

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 1101 Caja General           │ 119,000  │          │  ← From payment_methods.account_id
│ 1120 Cuentas por Cobrar     │          │ 119,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 119,000  │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

**Example 2: Payment via "Transferencia Bancaria"** (Bank transfer)

- Payment Method: Transferencia Bancaria (from payment_methods table)
- Linked Account: 1110 Bancos - Cuenta Corriente (from payment_methods.account_id)
- Amount: $119,000 CLP

**Journal Entry Created** (account determined dynamically):
```
Entry Number: PAY-20251012144600
Date: 2025-10-12
Type: payment
Status: posted
Description: Pago factura INV-001 - Transferencia Bancaria

Lines:
┌─────────────────────────────┬──────────┬──────────┐
│ Account                     │  Debit   │  Credit  │
├─────────────────────────────┼──────────┼──────────┤
│ 1110 Bancos                 │ 119,000  │          │  ← From payment_methods.account_id
│ 1120 Cuentas por Cobrar     │          │ 119,000  │
├─────────────────────────────┼──────────┼──────────┤
│ TOTAL                       │ 119,000  │ 119,000  │
└─────────────────────────────┴──────────┴──────────┘
```

**Key Feature**: Account assignment is **100% dynamic** based on `payment_methods` table configuration. 
No code changes needed to add new payment methods or reassign accounts!

---

## 📦 INVENTORY LOGIC

### Stock Movement (Confirmed)

When invoice is confirmed, stock movements are created:

```sql
INSERT INTO stock_movements (
  product_id,
  quantity,
  type,
  reference_type,
  reference_id,
  notes
) VALUES (
  <product_id>,
  <quantity>,  -- Negative value (e.g., -10)
  'OUT',
  'sales_invoice',
  <invoice_id>,
  'Venta según factura INV-001'
);

UPDATE products
SET stock = stock - <quantity>
WHERE id = <product_id>;
```

### Inventory Restoration (Revert to Sent)

When reverting from "Confirmada" to "Enviada":

```sql
DELETE FROM stock_movements
WHERE reference_type = 'sales_invoice'
  AND reference_id = <invoice_id>;

UPDATE products
SET stock = stock + <quantity>  -- Restore
WHERE id = <product_id>;
```

---

## GUI interaction contract

- Expose the current state with a clear label and semantics. A badge is
  optional, and no literal state hue is prescribed by this document.
- Expose only commands allowed by the business state, grouped by their actual
  scope and frequency.
- Let the canonical visual system determine action weight, status treatment,
  iconography, and feedback. Do not translate the state machine into one bright
  color per state.
- A risky reversal must communicate its exact accounting, payment, or inventory
  consequence and require an intentional decision. The appropriate blocking or
  non-blocking surface depends on risk and host; a centered dialog is not
  automatic.
- Preserve invoice/list context when opening payment or related records, and
  return to the exact origin after completion or cancellation.

---

## 🔐 BUSINESS RULES

### Status Transition Rules

| From       | To         | Allowed? | Condition |
|------------|------------|----------|-----------|
| Borrador   | Enviada    | ✅ Yes   | Always |
| Enviada    | Borrador   | ✅ Yes   | Always |
| Enviada    | Confirmada | ✅ Yes   | Always |
| Confirmada | Enviada    | ✅ Yes   | **Only if balance > 0** (unpaid) |
| Confirmada | Pagada     | ✅ Auto  | When payment covers full balance |
| Pagada     | Confirmada | ✅ Auto  | When payment is deleted and balance > 0 |
| Pagada     | Enviada    | ❌ No    | Must undo payment first |

### Edit Restrictions

- **Borrador**: Fully editable
- **Enviada**: Fully editable
- **Confirmada**: Editable with caution (changes trigger new accounting entry)
- **Pagada**: Limited editing (cannot change amounts/items)

### Deletion Rules

- **Journal Entries**: DELETED when reverting (not reversed)
- **Stock Movements**: DELETED when reverting
- **Payments**: Can be deleted individually, invoice returns to "Confirmada"

---

## 🗄️ DATABASE TRIGGERS

### Main Trigger: `handle_sales_invoice_change()`

Located in: `supabase/sql/sales_workflow_redesign.sql`

**Trigger Events**:
- `AFTER INSERT ON sales_invoices`
- `AFTER UPDATE ON sales_invoices`
- `AFTER DELETE ON sales_invoices`

**Logic**:
```sql
IF TG_OP = 'INSERT' THEN
  IF status IN ('confirmed', 'paid') THEN
    → consume_sales_invoice_inventory()
    → create_sales_invoice_journal_entry()
  END IF

ELSIF TG_OP = 'UPDATE' THEN
  IF old_status = 'confirmed' AND new_status = 'sent' THEN
    → restore_sales_invoice_inventory()
    → DELETE FROM journal_entries
  ELSIF old_status = 'sent' AND new_status = 'confirmed' THEN
    → consume_sales_invoice_inventory()
    → create_sales_invoice_journal_entry()
  END IF

ELSIF TG_OP = 'DELETE' THEN
  IF status IN ('confirmed', 'paid') THEN
    → restore_sales_invoice_inventory()
    → DELETE FROM journal_entries
  END IF
END IF
```

### Payment Trigger: `handle_sales_payment_change()`

**Trigger Events**:
- `AFTER INSERT ON sales_payments`
- `AFTER UPDATE ON sales_payments`
- `AFTER DELETE ON sales_payments`

**Called When**:
- Payment is inserted
- Payment is updated
- Payment is deleted

**Logic**:
```sql
IF TG_OP = 'INSERT' THEN
  → create_sales_payment_journal_entry(NEW)  -- Reads payment_methods.account_id dynamically
  → recalculate_sales_invoice_payments(NEW.invoice_id)

ELSIF TG_OP = 'UPDATE' THEN
  → delete_sales_payment_journal_entry(OLD.id)
  → create_sales_payment_journal_entry(NEW)  -- Reads payment_methods.account_id dynamically
  → recalculate_sales_invoice_payments(NEW.invoice_id)

ELSIF TG_OP = 'DELETE' THEN
  → delete_sales_payment_journal_entry(OLD.id)
  → recalculate_sales_invoice_payments(OLD.invoice_id)
END IF
```

**Key Feature**: Journal entry function queries `payment_methods` table to get account_id:
```sql
SELECT pm.id, pm.code, pm.name, a.id as account_id, a.code, a.name
FROM payment_methods pm
JOIN accounts a ON a.id = pm.account_id
WHERE pm.id = p_payment.payment_method_id;

-- Then uses account_id dynamically for journal lines
```

### Invoice Status Recalculation: `recalculate_sales_invoice_payments()`

**Logic**:
```sql
v_total_paid = SUM(payments.amount)
v_balance = invoice.total - v_total_paid

IF v_total_paid >= invoice.total THEN
  status = 'paid'
ELSIF v_balance > 0 AND old_status IN ('confirmed', 'paid') THEN
  status = 'confirmed'  -- ⭐ Preserve confirmed status
ELSE
  status = 'sent'
END IF

UPDATE sales_invoices
SET paid_amount = v_total_paid,
    balance = v_balance,
    status = v_new_status
```

---

## 🧪 TESTING SCENARIOS

### Test 1: Complete Forward Flow
1. Create invoice (Draft)
2. Mark as Sent → Verify no journal entry, no inventory change
3. Confirm → Verify journal entry created, inventory deducted
4. Pay → Verify payment entry created, status = Paid

### Test 2: Backward Flow (Confirmed → Sent)
1. Create and confirm invoice
2. Verify journal entry exists
3. Revert to Sent
4. Verify journal entry DELETED (not reversed)
5. Verify inventory RESTORED

### Test 3: Payment Undo
1. Create, confirm, and pay invoice
2. Undo payment
3. Verify status returns to "Confirmada"
4. Verify payment journal entry deleted
5. Verify balance restored

### Test 4: Multiple Payments
1. Create and confirm invoice for $100,000
2. Pay $50,000 → Status stays "Confirmada"
3. Pay $50,000 → Status becomes "Pagada"
4. Undo last payment → Status returns to "Confirmada"

---

## 🌍 LOCALIZATION (Chilean Context)

- **Currency**: CLP (Chilean Peso)
- **Tax**: IVA 19%
- **Date Format**: DD/MM/YYYY
- **Language**: Spanish (primary)
- **All UI labels in Spanish**:
  - "Borrador", "Enviada", "Confirmada", "Pagada"
  - "Marcar como enviada", "Confirmar", "Pagar factura"
  - "Volver a borrador", "Volver a enviada", "Deshacer pago"

---

## 🔧 AGENT INSTRUCTIONS

### When Implementing Status Transitions:
1. ✅ Always use button-driven transitions
2. ✅ Require an explicit, consequence-aware decision for risky reversals; let
   the canonical surface-selection rules choose its host
3. ✅ Use DELETE for journal entries (not reversal entries)
4. ✅ Restore inventory when reverting
5. ✅ Update UI immediately after status change
6. ✅ Provide feedback at the scope and duration of the operation
7. ✅ Use theme-owned state treatment with text and semantics, never literal
   feature colors

### When Debugging:
1. Check `journal_entries` table for source_module='sales_invoices'
2. Check `stock_movements` table for reference_type='sales_invoice'
3. Verify `paid_amount` and `balance` fields on invoice
4. Check trigger execution logs in Supabase

### Code References:
- **UI**: `lib/modules/sales/pages/invoice_detail_page.dart`
- **Service**: `lib/modules/sales/services/sales_service.dart`
- **SQL Triggers**: `supabase/sql/sales_workflow_redesign.sql`
- **Payment Logic**: `supabase/sql/fix_payment_status_logic.sql`
