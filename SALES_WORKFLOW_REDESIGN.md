# 🔄 Sales Invoice Workflow Redesign

## Overview

The sales invoice workflow has been redesigned to include a new "Confirmed" status and implement a cleaner approach to status changes.

### Old Workflow
```
Draft → Sent → Paid
```

### New Workflow
```
Draft → Sent → Confirmed → Paid
      ↓        ↓          ↓
  (reversible with DELETE, not reversal entries)
```

---

## 🎯 Key Changes

### 1. New "Confirmed" Status

| Status | Description | Accounting Effect | Inventory Effect |
|--------|-------------|-------------------|------------------|
| **Draft** | Invoice being prepared | ❌ None | ❌ None |
| **Sent** | Delivered to client | ❌ None | ❌ None |
| **Confirmed** ✨ | Client accepted | ✅ Journal entry created | ✅ Inventory deducted |
| **Paid** | Payment received | ✅ Payment entry created | - |

### 2. Journal Entry Management

**Before**: Journal entries were REVERSED when going backward
- Created reversal entries (REV-xxx)
- Original entries marked as "reversed"
- Complex audit trail with nested reversals

**After** (Zoho Books approach): Journal entries are DELETED when going backward
- Cleaner database
- Simpler audit trail
- No confusing reversal chains
- Entry simply disappears when invoice reverted

### 3. Workflow Transitions

#### Forward Transitions

**Draft → Sent**
```
Action: Mark as "Enviada"
Effect: 
  - Status changes to "sent"
  - ❌ NO accounting entry
  - ❌ NO inventory change
  - Just marks delivery to client
```

**Sent → Confirmed**
```
Action: Click "Confirmar" button
Effect:
  - Status changes to "confirmed"
  - ✅ Journal entry CREATED
  - ✅ Inventory DEDUCTED
  - Invoice is now in the accounting system
```

**Confirmed → Paid**
```
Action: Register payment
Effect:
  - Status changes to "paid"
  - ✅ Payment journal entry created
  - Balance becomes $0
```

#### Backward Transitions

**Sent → Draft**
```
Action: Click "Volver a borrador"
Effect:
  - Status changes to "draft"
  - ❌ Nothing to delete (no journal entry exists)
  - ❌ Nothing to restore (no inventory change)
```

**Confirmed → Sent**
```
Action: Click "Volver a enviada"
Effect:
  - Status changes to "sent"
  - ❌ Journal entry DELETED (not reversed!)
  - ✅ Inventory RESTORED (products returned to stock)
  - Invoice removed from accounting
```

**Confirmed → Draft** (via Sent)
```
Step 1: Confirmed → Sent
  - Delete journal entry
  - Restore inventory

Step 2: Sent → Draft  
  - Just change status
```

---

## 🗄️ Database Changes

### SQL Migration: `sales_workflow_redesign.sql`

1. **Updated `sales_invoices` status constraint**
   - Added "confirmed", "confirmado", "confirmada" to allowed values

2. **Migrated existing data**
   - All "sent" invoices with journal entries → "confirmed"
   - Preserves existing accounting data

3. **Updated `handle_sales_invoice_change()` trigger**
   - Only creates journal entries for "confirmed" or "paid" status
   - DELETES journal entries when going backward (not reverses)
   - Properly handles inventory changes

4. **Updated `create_sales_invoice_journal_entry()` function**
   - Skips "sent" status (only processes "confirmed" or "paid")
   - Idempotent (safe to call multiple times)

5. **Removed `delete_sales_invoice_journal_entry()` function**
   - No longer needed (using direct DELETE now)

---

## 🎨 UI Changes

### Invoice Detail Page Buttons

#### Draft Status
```
[Editar] [Marcar como enviada]
```

#### Sent Status
```
[Editar] [Volver a borrador] [Confirmar]
                                  ↑
                             (Green button)
```

#### Confirmed Status (unpaid)
```
[Pagar factura] [Editar] [Volver a enviada]
```

#### Confirmed Status (paid)
```
[Editar]
(No revert button when paid)
```

### Status Colors

| Status | Color Badge |
|--------|-------------|
| Draft | Grey |
| Sent | Blue |
| **Confirmed** ✨ | **Purple** |
| Paid | Green |
| Overdue | Red |
| Cancelled | Orange |

---

## 📊 Accounting Impact

### Example Workflow

**Invoice**: INV-001 for $119,000 (subtotal: $100,000 + IVA: $19,000)

#### Step 1: Create as Draft
```
Status: draft
Accounting: None
Inventory: No change
```

#### Step 2: Mark as Sent
```
Status: sent
Accounting: None
Inventory: No change
Comment: "Invoice delivered to client"
```

#### Step 3: Confirm Invoice
```
Status: confirmed
Accounting: 
  Journal Entry: INV-20251011120000
    Debit:  Cuentas por Cobrar (1120)  $119,000
    Credit: Ingresos por Ventas (4100)  $100,000
    Credit: IVA Débito (2150)           $19,000
    
    Debit:  Costo de Ventas (5101)     $60,000
    Credit: Inventario (1150)           $60,000
    
Inventory: -10 units Product A
Comment: "Invoice confirmed by client"
```

#### Step 4: Receive Payment
```
Status: paid
Accounting:
  Payment Entry: PAGO-INV-001
    Debit:  Caja/Banco (1100)           $119,000
    Credit: Cuentas por Cobrar (1120)   $119,000
    
Balance: $0
Comment: "Payment received"
```

### Reversal Example

**Confirmed → Sent (undo confirmation)**

```
Before:
  Status: confirmed
  Journal Entries:
    - INV-20251011120000 (posted)
  Inventory: Product A = 90 units

Action: Click "Volver a enviada"

After:
  Status: sent
  Journal Entries:
    (DELETED - entry completely removed)
  Inventory: Product A = 100 units (restored)
```

**No reversal entry created!** The journal entry is simply deleted.

---

## 🔄 Comparison: Sales vs Purchases

| Aspect | Sales Invoices | Purchase Invoices |
|--------|----------------|-------------------|
| **Workflow** | Draft → Sent → Confirmed → Paid | Draft → Received → Paid |
| **Accounting Trigger** | "Confirmed" status | "Received" status |
| **Going Backward** | DELETE journal entries | REVERSE journal entries |
| **Audit Trail** | Simpler (entries deleted) | Complete (reversals kept) |
| **Approach** | Zoho Books style | Traditional accounting |

**Why Different?**

- **Sales**: Customer-facing, simpler flow, less regulatory scrutiny
- **Purchases**: Vendor-facing, more complex, stricter audit requirements

Both approaches are valid for their use cases!

---

## ✅ Setup Instructions

### 1. Run SQL Migration

```sql
-- In Supabase SQL Editor
-- Run: supabase/sql/sales_workflow_redesign.sql
```

This will:
- Add "confirmed" status to allowed values
- Migrate existing "sent" invoices to "confirmed"
- Update triggers to delete (not reverse) entries
- Update journal entry creation logic

### 2. Restart Flutter App

```bash
flutter run -d windows
```

### 3. Test the New Workflow

**Test Forward Flow:**
1. Create new invoice (Draft)
2. Mark as "Enviada" → Check no journal entry created
3. Click "Confirmar" → Check journal entry created, inventory deducted
4. Register payment → Check payment entry created

**Test Backward Flow:**
1. Create invoice and confirm it
2. Check journal entry exists in "Asientos Contables"
3. Click "Volver a enviada"
4. Verify:
   - Journal entry is DELETED (not reversed)
   - Inventory is RESTORED
   - Invoice status is "sent"

---

## 📋 Migration Checklist

- [ ] Backup your database before running migration
- [ ] Run `sales_workflow_redesign.sql` in Supabase
- [ ] Verify existing "sent" invoices migrated to "confirmed"
- [ ] Restart Flutter app
- [ ] Test creating new invoice (Draft → Sent → Confirmed)
- [ ] Test reverting invoice (Confirmed → Sent)
- [ ] Verify journal entry is deleted (not reversed)
- [ ] Test payment registration
- [ ] Check inventory changes correctly

---

## 🐛 Troubleshooting

### "Status 'confirmed' not allowed"
- **Cause**: SQL migration not run
- **Fix**: Run `sales_workflow_redesign.sql` in Supabase

### Journal entry still created when "sent"
- **Cause**: Old trigger function still active
- **Fix**: Re-run the migration to update trigger

### Can't revert from "confirmed" to "sent"
- **Cause**: Payments exist on the invoice
- **Fix**: Only unpaid invoices can be reverted

### Inventory not restored when reverting
- **Cause**: Trigger not updating properly
- **Fix**: Check Supabase logs, re-run migration

---

## 📚 User Training Notes

### For Sales Team

1. **Draft**: Create the invoice with all details
2. **Send**: Mark as "Enviada" when you deliver it to the client
   - At this point, it's just a record - no accounting impact
3. **Confirm**: Click "Confirmar" when client accepts the invoice
   - This is when it enters the accounting system
   - Inventory is deducted at this point
4. **Pay**: Register payment when client pays

### For Accounting Team

- Invoices only appear in accounting when **confirmed**
- "Sent" invoices are not in the books yet
- Reverting from "confirmed" to "sent" **deletes** the journal entry
- No reversal entries are created for sales (simpler than purchases)

---

## 🎓 Benefits of This Approach

✅ **Clearer Status Flow**: Sent ≠ Confirmed
✅ **Cleaner Database**: No reversal entry clutter
✅ **Better Control**: Accounting only happens when confirmed
✅ **Simpler Audit**: Deleted entries vs complex reversal chains
✅ **Industry Standard**: Matches Zoho Books, QuickBooks approach
✅ **User-Friendly**: Clear buttons for each action

---

**Migration File**: `supabase/sql/sales_workflow_redesign.sql`  
**Affected Modules**: Sales, Accounting  
**Database Tables**: `sales_invoices`, `journal_entries`, `journal_lines`  
**Breaking Change**: ⚠️ Yes - existing "sent" invoices become "confirmed"  
**Rollback**: Backup database before migration
