# ✅ PURCHASE INVOICE WORKFLOW - DATABASE SCHEMA FIX

## 🐛 Problems Found

### Problem 1: Missing Workflow Tracking Columns
When trying to change a purchase invoice from "Enviada" (Sent) to "Confirmada" (Confirmed), the app showed a 400 Bad Request error:
```
PATCH https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/purchase_invoices?id=eq.98ac9c35... 400 (Bad Request)
```

### Problem 2: Wrong Column Name in Trigger Function  
After adding the missing columns, a second error appeared:
```
PostgrestException(message: there is no unique or exclusion constraint matching the ON CONFLICT specification, code: 42P10)
```

This cryptic error was actually caused by the trigger function `create_purchase_invoice_journal_entry()` trying to access a non-existent column.

## 🔍 Root Causes

### Root Cause #1: Missing Database Columns  
The database schema was **missing critical workflow tracking columns** that exist in the Flutter model but not in the PostgreSQL table:

**Missing columns:**
- `sent_date` - Timestamp when invoice was sent to supplier
- `confirmed_date` - Timestamp when supplier confirmed invoice  
- `received_date` - Timestamp when goods were received
- `paid_date` - Timestamp when invoice was paid
- `supplier_invoice_number` - Invoice number from supplier
- `supplier_invoice_date` - Invoice date from supplier

When the Flutter app tried to update `confirmed_date` and `supplier_invoice_date`, PostgreSQL rejected the request because these columns didn't exist.

### Root Cause #2: Wrong Column Name in Database Function
The database trigger function `create_purchase_invoice_journal_entry()` was referencing **`p_invoice.iva_amount`** which doesn't exist in the `purchase_invoices` table.

**Correct column name:** `p_invoice.tax`

This is an inconsistency between:
- **sales_invoices** table: uses `iva_amount` column ✅
- **purchase_invoices** table: uses `tax` column ✅

The function was copied from sales invoices but not adapted for purchase invoices, causing it to fail when trying to create journal entries for confirmed purchase invoices.

## ✅ Solution Implemented

### 1. Updated `core_schema.sql`
Added missing columns to both:
- Initial table creation statement (lines 2865-2893)
- ALTER TABLE statement for migrations (lines 2905-2920)

**Added columns:**
```sql
sent_date timestamp with time zone,
confirmed_date timestamp with time zone,
received_date timestamp with time zone,
paid_date timestamp with time zone,
supplier_invoice_number text,
supplier_invoice_date timestamp with time zone
```

### 2. Fixed Database Trigger Function
**File:** Included in migration `supabase/migrations/add_purchase_invoice_workflow_columns.sql`

**Problem:** Function referenced `p_invoice.iva_amount` (doesn't exist)  
**Fix:** Changed to `p_invoice.tax` (correct column name)

**Before:**
```sql
debit_amount,
p_invoice.iva_amount,  -- ❌ Wrong column
```

**After:**
```sql
debit_amount,
p_invoice.tax,  -- ✅ Correct column
```

This fix is included in the migration file and will be deployed along with the column additions.

### 3. Created Migration File
**File:** `supabase/migrations/add_purchase_invoice_workflow_columns.sql`

This migration:
- ✅ Adds all 6 missing columns to `purchase_invoices` table
- ✅ Creates indexes for common date queries
- ✅ Adds documentation comments for each column
- ✅ **Recreates `create_purchase_invoice_journal_entry()` function with fix**
- ✅ Verifies columns were added successfully

### 4. Fixed `PurchaseService.confirmInvoice()`
**File:** `lib/modules/purchases/services/purchase_service.dart`

**Before:**
```dart
'supplier_invoice_date': supplierInvoiceDate.toIso8601String(),
```

**After:**
```dart
'supplier_invoice_date': supplierInvoiceDate.toUtc().toIso8601String(),
```

This ensures consistent UTC timezone storage, matching the pattern used throughout the codebase.

### 4. Enhanced `updateInvoiceStatus()` Method
Added automatic workflow date tracking:

```dart
switch (status) {
  case PurchaseInvoiceStatus.sent:
    payload['sent_date'] = now;
    break;
  case PurchaseInvoiceStatus.confirmed:
    payload['confirmed_date'] = now;
    break;
  case PurchaseInvoiceStatus.received:
    payload['received_date'] = now;
    break;
  case PurchaseInvoiceStatus.paid:
    payload['paid_date'] = now;
    break;
  default:
    break;
}
```

Now when you change an invoice status, the corresponding date field is automatically set.

## 📋 Deployment Steps

### Step 1: Deploy Migration to Supabase
1. Open Supabase Dashboard → SQL Editor
2. Paste contents of `supabase/migrations/add_purchase_invoice_workflow_columns.sql`
3. Click "Run" to execute the migration
4. You should see: `✅ All workflow tracking columns added successfully to purchase_invoices table`

### Step 2: Hot Reload Flutter App
```bash
# In the terminal running flutter run -d chrome
Press 'r' to hot reload
```

Or restart the app completely if hot reload doesn't work.

### Step 3: Test the Workflow
1. Navigate to **Purchases → Purchase Invoices**
2. Click on an existing invoice or create a new one
3. Test the workflow progression:
   - **Draft → Sent**: Should set `sent_date`
   - **Sent → Confirmed**: Should set `confirmed_date`, `supplier_invoice_number`, and `supplier_invoice_date`
   - **Confirmed → Received**: Should set `received_date` and update inventory
   - **Received → Paid**: Should set `paid_date`

### Step 4: Verify Database
Check that the workflow dates are being recorded:
```sql
select 
  invoice_number,
  status,
  sent_date,
  confirmed_date,
  received_date,
  paid_date,
  supplier_invoice_number,
  supplier_invoice_date
from purchase_invoices
where tenant_id = your_tenant_id
order by created_at desc
limit 10;
```

## 🎯 Expected Behavior After Fix

✅ **Sent → Confirmed transition works without errors**
✅ Workflow dates are automatically tracked in database
✅ Supplier invoice details are properly stored
✅ Timeline view shows accurate dates for each workflow step
✅ Consistent UTC timezone handling across all date fields

## 🔄 Workflow States

The complete purchase invoice workflow is now fully supported:

1. **Draft** → Create invoice, add items
2. **Sent** (`sent_date`) → Send order to supplier
3. **Confirmed** (`confirmed_date`, `supplier_invoice_number`, `supplier_invoice_date`) → Supplier confirms with their invoice details
4. **Received** (`received_date`) → Goods arrive, inventory updated via trigger
5. **Paid** (`paid_date`) → Payment registered, accounting updated

**Alternative path (prepayment model):**
Draft → Sent → Confirmed → **Paid** → Received

## 📝 Files Modified

1. ✅ `supabase/sql/core_schema.sql` - Added workflow columns to schema
2. ✅ `supabase/migrations/add_purchase_invoice_workflow_columns.sql` - **NEW** migration file
3. ✅ `lib/modules/purchases/services/purchase_service.dart` - Fixed timezone handling and added auto-date tracking

## 🚀 Next Steps

1. **Deploy the migration** (Step 1 above) - **REQUIRED**
2. Hot reload the Flutter app
3. Test the workflow transitions
4. Monitor for any additional errors

The 400 Bad Request error should be completely resolved after deploying the migration! 🎉
