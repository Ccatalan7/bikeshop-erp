# Inventory Reduction Fix for Sales Invoices

## Problem
When a sales invoice was marked as "enviado" (sent), the inventory was not being reduced as expected. The error was:
```
PostgrestException(message: invalid input value for enum stock_movement_type: "sales_invoice", code: 22P02)
```

## Root Cause
There were TWO issues:

### 1. **CRITICAL: Enum Type Mismatch**
The `stock_movements.movement_type` column was created as an ENUM in the database, but "sales_invoice" was not one of the allowed values. The schema file defines it as TEXT, but someone must have altered it to an enum type directly in Supabase.

### 2. **Complex Function Logic**
The original implementation had:
1. **Overly complex JSONB parsing**: The function tried multiple different paths to extract product_id and quantity, which made debugging difficult
2. **Dynamic SQL construction**: Building SQL strings dynamically made it hard to trace errors
3. **Lack of logging**: No debug information was available to trace what was happening
4. **Column existence checks**: The function spent time checking if columns exist instead of just using them

## Solution
I've simplified and improved the `consume_sales_invoice_inventory` function:

1. **Simplified JSONB parsing**: Now directly accesses `product_id`, `product_sku`, and `quantity` from the items array
2. **Direct SQL updates**: No more dynamic SQL string building - just a straightforward UPDATE statement
3. **Added logging**: `RAISE NOTICE` statements track execution flow
4. **Better error handling**: Clearer logic for skipping invalid items

## Changes Made

### Files Modified
1. `supabase/sql/core_schema.sql` - Updated with the fixed functions
2. `supabase/sql/fix_inventory_trigger.sql` - Standalone fix script (can be run independently)

### Key Improvements
- The function now logs each step: invoice processing, item parsing, inventory updates
- Stock movements are correctly created with negative quantities for OUT movements
- Better handling of edge cases (null product_id, zero quantity, services)
- Simplified trigger logic with clear status transition handling

## How to Apply the Fix

### **CRITICAL: Apply in Order!**

### Step 1: Fix the Enum Type (REQUIRED FIRST)
1. Go to your Supabase project dashboard
2. Navigate to SQL Editor
3. Copy and paste the contents of `supabase/sql/fix_movement_type_enum.sql`
4. Click "Run"
5. Check the output - it should say "Converted movement_type to text" or "movement_type is already text"

### Step 2: Apply the Trigger Fix
1. Still in SQL Editor
2. Copy and paste the contents of `supabase/sql/fix_inventory_trigger.sql`
3. Click "Run"
4. Check the output for "Trigger trg_sales_invoices_change created successfully"

### Option 2: Re-run the Core Schema (Fresh Install Only)
If you're setting up a new environment:
1. Run `supabase/sql/core_schema.sql` (it now includes the fix)
2. Run `supabase/sql/add_categories.sql` (if using categories)
3. Run `supabase/sql/seed_demo.sql` (if you want demo data)

### Option 3: Manual Testing
After applying the fix, test it:

1. Check your product inventory levels:
   ```sql
   SELECT id, name, sku, inventory_qty FROM products WHERE sku = 'YOUR-PRODUCT-SKU';
   ```

2. Create a sales invoice with status 'draft'
3. Mark it as 'sent' (enviado)
4. Check inventory again - it should have decreased
5. Check stock movements:
   ```sql
   SELECT * FROM stock_movements 
   WHERE reference LIKE 'sales_invoice:%' 
   ORDER BY created_at DESC;
   ```

## Debugging
If the fix doesn't work, check the PostgreSQL logs for `NOTICE` messages:

```sql
-- Enable logging (if needed)
SET client_min_messages = NOTICE;

-- Then perform the status update and watch for log messages
```

The function will output messages like:
- `consume_sales_invoice_inventory: invoice <id>, status sent`
- `consume_sales_invoice_inventory: processing 2 items`
- `consume_sales_invoice_inventory: reduced inventory for product <id> by 5`

## Expected Behavior

### When Status Changes from "draft" to "sent"/"enviado":
1. ✅ Inventory is reduced by the quantity in the invoice
2. ✅ A stock_movements record is created with type='OUT'
3. ✅ Journal entries are created for revenue and COGS
4. ❌ No payment record is created (that happens when marked as "paid")

### When Status Changes from "sent" to "paid"/"pagado":
1. ✅ Inventory stays the same (already reduced)
2. ✅ Payment record is created
3. ✅ Journal entry for payment is created

### When Status Changes from "sent" back to "draft":
1. ✅ Inventory is restored (increased back)
2. ✅ Stock_movements record shows the reversal

## Technical Details

### Item Structure Expected
The function expects items in the sales_invoices JSONB field to have this structure:
```json
[
  {
    "product_id": "uuid-here",
    "product_sku": "SKU-123",
    "product_name": "Product Name",
    "quantity": 5,
    "unit_price": 10000,
    ...
  }
]
```

This matches the output of `InvoiceItem.toFirestoreMap()` in the Flutter app.

### Stock Movements
Each inventory reduction creates a stock_movements record:
- `type`: 'OUT'
- `movement_type`: 'sales_invoice'
- `quantity`: negative number (e.g., -5)
- `reference`: 'sales_invoice:<invoice_id>'

## Rollback
If you need to rollback, you can restore the old functions from your previous backup or the git history of `core_schema.sql` before this commit.

## Contact
If issues persist, check:
1. Supabase logs for errors
2. PostgreSQL function execution logs
3. Network console in Flutter app for API errors
4. The items field in your sales_invoices table to ensure it has the right structure
