# Quick Start: Purchase Invoice Workflow

## Step 1: Apply Database Changes

You need to run the SQL script on your Supabase database. Choose one of these methods:

### Option A: Supabase Dashboard (Recommended)
1. Go to https://supabase.com/dashboard
2. Select your project
3. Click on "SQL Editor" in the left sidebar
4. Click "New Query"
5. Copy and paste the entire contents of `supabase/sql/purchase_invoice_workflow.sql`
6. Click "Run" or press Ctrl+Enter
7. Check the results panel - you should see verification queries showing your purchase invoices

### Option B: Supabase CLI (if installed)
```bash
# From project root
supabase db reset  # Warning: this resets ALL data!

# OR apply just this script
psql -h db.your-project.supabase.co -U postgres -d postgres -f supabase/sql/purchase_invoice_workflow.sql
```

### Option C: PostgreSQL Client
If you have direct database access:
```bash
psql "postgresql://postgres:[password]@db.[project-ref].supabase.co:5432/postgres" < supabase/sql/purchase_invoice_workflow.sql
```

## Step 2: Verify Installation

After running the script, verify it worked:

### Check Functions Exist
```sql
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name LIKE '%purchase%invoice%'
ORDER BY routine_name;
```

Expected output:
- `consume_purchase_invoice_inventory`
- `create_purchase_invoice_journal_entry`
- `handle_purchase_invoice_change`

### Check Trigger Exists
```sql
SELECT trigger_name, event_manipulation, event_object_table
FROM information_schema.triggers 
WHERE trigger_name = 'purchase_invoice_change_trigger';
```

Expected output:
- trigger_name: `purchase_invoice_change_trigger`
- event_manipulation: `INSERT` or `UPDATE`
- event_object_table: `purchase_invoices`

## Step 3: Test in Application

### Create a Test Purchase Invoice
1. **Run your Flutter app:**
   ```bash
   flutter run -d windows
   ```

2. **Navigate to Purchases:**
   - Click "Compras" in the sidebar
   - Click "Nueva Factura de Compra"

3. **Fill in the form:**
   - Select or create a supplier
   - Add a product (e.g., "Bicicleta MTB" x 2)
   - Save as Draft
   - Note the current inventory level of the product

4. **Mark as Received:**
   - Click the green "Marcar como Recibida" button
   - Confirm in the dialog
   - Watch for:
     - Status changes to green "Recibida"
     - Success message appears

5. **Verify Results:**
   - Go to "Inventario" → "Movimientos"
   - You should see a new IN movement for "Compra: [invoice number]"
   - Go to "Contabilidad" → "Asientos Contables"
   - You should see a new entry "COMP-[invoice number]"
   - Check product inventory - it should have increased

### Test Status Flow
```
Draft → [Save] → Draft (gray chip)
  ↓
[Marcar como Recibida] → Received (green chip)
  - Inventory increases ✅
  - Journal entry created ✅
  ↓
[Marcar como Pagada] → Paid (blue chip)
  - Status updated ✅
```

## Step 4: Verify Database Changes

Run these queries in Supabase SQL Editor:

### Check Stock Movements
```sql
SELECT 
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.notes,
  p.name as product_name,
  p.inventory_qty,
  sm.created_at
FROM stock_movements sm
JOIN products p ON p.id = sm.product_id
WHERE sm.movement_type = 'purchase_invoice'
ORDER BY sm.created_at DESC
LIMIT 5;
```

### Check Journal Entries
```sql
SELECT 
  je.entry_number,
  je.description,
  je.date,
  (SELECT SUM(debit) FROM journal_entry_lines WHERE journal_entry_id = je.id) as total_debit,
  (SELECT SUM(credit) FROM journal_entry_lines WHERE journal_entry_id = je.id) as total_credit
FROM journal_entries je
WHERE je.reference_type = 'purchase_invoice'
ORDER BY je.created_at DESC
LIMIT 5;
```

### Check Journal Entry Details
```sql
SELECT 
  je.entry_number,
  coa.code,
  coa.name as account_name,
  jel.debit,
  jel.credit,
  jel.description
FROM journal_entries je
JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id
JOIN chart_of_accounts coa ON coa.id = jel.account_id
WHERE je.reference_type = 'purchase_invoice'
ORDER BY je.created_at DESC, coa.code
LIMIT 20;
```

Expected structure for each purchase:
```
Entry: COMP-00001
  DR: 1105 Inventario          $84,033.61
  DR: 1107 IVA Crédito Fiscal  $15,966.39
  CR: 2101 Proveedores        $100,000.00
```

## Troubleshooting

### Issue: "Account not found" error

**Solution:** Create the required accounts first:

```sql
-- Create Inventario account (if doesn't exist)
INSERT INTO chart_of_accounts (id, code, name, type, category, is_active)
VALUES (gen_random_uuid(), '1105', 'Inventario', 'asset', 'current_assets', true)
ON CONFLICT (code) DO NOTHING;

-- Create IVA Crédito Fiscal account
INSERT INTO chart_of_accounts (id, code, name, type, category, is_active)
VALUES (gen_random_uuid(), '1107', 'IVA Crédito Fiscal', 'asset', 'current_assets', true)
ON CONFLICT (code) DO NOTHING;

-- Create Proveedores (Accounts Payable) account
INSERT INTO chart_of_accounts (id, code, name, type, category, is_active)
VALUES (gen_random_uuid(), '2101', 'Proveedores', 'liability', 'current_liabilities', true)
ON CONFLICT (code) DO NOTHING;
```

### Issue: Inventory not increasing

**Check trigger is active:**
```sql
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgrelid = 'purchase_invoices'::regclass;
```

**Manually trigger processing:**
```sql
SELECT consume_purchase_invoice_inventory();
```

### Issue: Duplicate stock movements

The script prevents this automatically, but if it happens:
```sql
-- Check for duplicates
SELECT reference, product_id, COUNT(*)
FROM stock_movements
WHERE movement_type = 'purchase_invoice'
GROUP BY reference, product_id
HAVING COUNT(*) > 1;
```

## What Changed

### Files Modified:
1. ✅ `lib/modules/purchases/services/purchase_service.dart` - Added status update methods
2. ✅ `lib/modules/purchases/pages/purchase_invoice_form_page.dart` - Added status buttons and UI

### Files Created:
1. ✅ `supabase/sql/purchase_invoice_workflow.sql` - Database triggers and functions
2. ✅ `PURCHASE_INVOICE_IMPLEMENTATION.md` - Full documentation
3. ✅ `PURCHASE_INVOICE_QUICKSTART.md` - This file

### No Changes Needed:
- `purchase_invoice.dart` - Model already had status enum
- `purchase_invoice_list_page.dart` - Already had status display

## Summary

Your purchase invoice module now works like the sales invoice module:

✅ **Status-based workflow** (Draft → Received → Paid)  
✅ **Automatic inventory increase** when marked as received  
✅ **Automatic accounting entries** following Chilean standards  
✅ **User confirmations** before status changes  
✅ **Audit trail** with complete logging  
✅ **UI feedback** with colored status chips  

The only thing you need to do is **run the SQL script** on your Supabase database!

---

**Next Steps:**
1. Run the SQL script (Step 1 above)
2. Test in your app (Step 3 above)
3. Verify everything works (Step 4 above)

If you encounter any issues, check the Troubleshooting section or refer to `PURCHASE_INVOICE_IMPLEMENTATION.md` for detailed debugging steps.
