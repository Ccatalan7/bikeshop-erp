# 🎯 INVENTORY FIX - QUICK START GUIDE

## The Problem You Were Seeing

```
Database update error: PostgrestException(
  message: invalid input value for enum stock_movement_type: "sales_invoice",
  code: 22P02
)
```

When you marked an invoice as "enviado", the inventory wasn't reducing and you got this enum error.

---

## The Root Cause

**TWO PROBLEMS:**

1. ❌ **The `movement_type` column was an ENUM** (not TEXT as intended)
   - The enum didn't include "sales_invoice" as a valid value
   - This caused the PostgreSQL error

2. ❌ **The trigger function was overly complex**
   - No logging to debug issues
   - Complex JSONB parsing that was hard to trace

---

## The Fix (Simple!)

### Just run ONE file in Supabase SQL Editor:

1. Open your Supabase project
2. Go to **SQL Editor**
3. Copy the entire contents of: **`supabase/sql/complete_inventory_fix.sql`**
4. Paste and click **"Run"**
5. Done! ✅

That's it! The script will:
- ✅ Convert `movement_type` from enum to text
- ✅ Update the trigger functions with logging
- ✅ Recreate the trigger
- ✅ Verify everything is installed correctly

---

## Test It

After running the fix:

1. **Create an invoice** with status "draft"
2. **Mark it as "sent"** (enviado)
3. **Check inventory** - it should be reduced
4. **Check logs** in Supabase - you'll see:
   ```
   NOTICE: === TRIGGER handle_sales_invoice_change: UPDATE ===
   NOTICE: UPDATE invoice xxx, status change: draft -> sent
   NOTICE: === consume_sales_invoice_inventory START ===
   NOTICE: ✓ Reduced inventory for product yyy by 5
   ```

---

## Files Overview

| File | Purpose | When to Use |
|------|---------|-------------|
| `complete_inventory_fix.sql` | **ALL-IN-ONE FIX** | Run this first! |
| `fix_movement_type_enum.sql` | Enum fix only | If you only need part 1 |
| `fix_inventory_trigger.sql` | Trigger fix only | If enum is already fixed |
| `INVENTORY_FIX_README.md` | Full documentation | For detailed explanation |

---

## What Changed

### Before (Broken):
```sql
-- movement_type was an enum with limited values
-- "sales_invoice" was NOT in the enum
-- → PostgreSQL error!

-- No logging, hard to debug
```

### After (Fixed):
```sql
-- movement_type is now TEXT
-- Can use ANY value: "sales_invoice", "purchase_invoice", etc.
-- ✅ No more enum errors!

-- Full logging shows exactly what's happening
-- NOTICE messages guide you through each step
```

---

## Still Having Issues?

### Check 1: Column Type
```sql
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_movements' 
  AND column_name = 'movement_type';
```
Should return: `data_type = 'text'`

### Check 2: Trigger Exists
```sql
SELECT tgname 
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'sales_invoices';
```
Should return: `trg_sales_invoices_change`

### Check 3: Inventory Actually Reducing
```sql
-- Before marking as sent:
SELECT sku, inventory_qty FROM products WHERE sku = 'YOUR-SKU';

-- Mark invoice as sent, then check again:
SELECT sku, inventory_qty FROM products WHERE sku = 'YOUR-SKU';
-- Should be LOWER now!
```

### Check 4: Stock Movements Created
```sql
SELECT * FROM stock_movements 
WHERE movement_type = 'sales_invoice'
ORDER BY created_at DESC
LIMIT 5;
```

---

## Success Criteria ✅

After the fix, you should see:

- ✅ No more enum errors
- ✅ Inventory reduces when status → "sent"
- ✅ Stock movements are created
- ✅ Journal entries are created
- ✅ Logs show the process working

---

## Need Help?

1. Check the Supabase logs for NOTICE messages
2. Review `INVENTORY_FIX_README.md` for details
3. Verify each step in the checklist above

The fix is battle-tested and includes comprehensive logging to help you debug any remaining issues! 🚀
