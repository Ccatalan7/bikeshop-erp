# Stock Movements Module - Deployment Guide

**Date:** November 1, 2025  
**Status:** ✅ Ready to Deploy

---

## 📋 What's New

### UI Enhancements ✅ Already in Code
1. **Date Range Picker** - Filter movements by date range
2. **Invoice Navigation** - Click reference numbers to open invoices
3. **Visual Improvements** - Active filter highlighting, clear buttons

### Database Changes ⚠️ Requires Deployment

#### 1. New Columns
```sql
-- Sales invoices: Track source and creator
ALTER TABLE sales_invoices 
  ADD COLUMN source text CHECK (source IN ('pos', 'manual_sale', 'ecommerce', 'mechanic_job')),
  ADD COLUMN created_by uuid REFERENCES auth.users(id);

-- Purchase invoices: Track creator
ALTER TABLE purchase_invoices 
  ADD COLUMN created_by uuid REFERENCES auth.users(id);
```

#### 2. Auto-Population Trigger
```sql
-- Function to auto-populate created_by on INSERT
CREATE OR REPLACE FUNCTION set_created_by()
RETURNS trigger AS $$
BEGIN
  IF NEW.created_by IS NULL THEN
    NEW.created_by := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply to both tables
CREATE TRIGGER trg_sales_invoices_set_created_by
  BEFORE INSERT ON sales_invoices
  FOR EACH ROW EXECUTE FUNCTION set_created_by();

CREATE TRIGGER trg_purchase_invoices_set_created_by
  BEFORE INSERT ON purchase_invoices
  FOR EACH ROW EXECUTE FUNCTION set_created_by();
```

#### 3. Updated View
```sql
-- stock_movements_view now uses:
-- - coalesce(si.source, 'manual_sale') instead of hardcoded 'manual_sale'
-- - si.created_by instead of null::uuid
-- - pi.created_by instead of null::uuid
```

---

## 🚀 Deployment Steps

### Option 1: Deploy Entire Schema (Recommended)
```bash
# From project root
cd /Users/Claudio/Dev/bikeshop-erp

# Deploy via Supabase CLI
supabase db push
```

### Option 2: Manual Deployment (Supabase SQL Editor)

Copy and execute these sections from `supabase/sql/core_schema.sql` **in order**:

1. **Sales Invoices Enhancement** (lines 2075-2102)
   - Adds `source` and `created_by` columns
   - Creates `set_created_by()` function
   - Creates trigger for sales_invoices

2. **Purchase Invoices Enhancement** (lines 4185-4195)
   - Adds `created_by` column
   - Creates trigger for purchase_invoices

3. **Stock Movements View - Final Version** (lines 4235-4323)
   - Recreates view with **actual stock calculations using window functions**
   - Replaces the initial placeholder version
   - **Critical:** This implements stock_before and stock_after properly!

**Note:** The schema creates the view twice:
- First time (line 1412): With placeholder zeros for stock_before/stock_after
- Second time (line 4235): With **actual calculations** using window functions
This ensures the schema can be deployed in a single transaction without errors.

### What Gets Fixed

**Before deployment:**
- Stock Inicial: 0 (placeholder)
- Stock Final: 0 (placeholder)
- ❌ No way to see actual stock levels

**After deployment:**
- Stock Inicial: **Actual stock before movement** (calculated)
- Stock Final: **Actual stock after movement** (calculated)
- ✅ See real stock levels at time of transaction
- ✅ Verify if sales caused stockouts
- ✅ Track cumulative effect of movements

---

## ✅ Post-Deployment Verification

### 1. Verify Columns Exist
```sql
-- Check sales_invoices
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_invoices' 
  AND column_name IN ('source', 'created_by');
-- Should return 2 rows

-- Check purchase_invoices
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'purchase_invoices' 
  AND column_name = 'created_by';
-- Should return 1 row
```

### 2. Test View Query
```sql
SELECT 
  product_name,
  transaction_date,
  movement_type,
  quantity,
  stock_before,    -- Should show REAL values now, not 0
  stock_after,     -- Should show REAL values now, not 0
  source,          -- Should show actual values
  created_by       -- Should show user UUIDs (or NULL for old records)
FROM stock_movements_view 
WHERE product_id = (SELECT id FROM products WHERE sku = 'YOUR_PRODUCT_SKU' LIMIT 1)
ORDER BY transaction_date DESC 
LIMIT 10;

-- Example expected output:
-- product_name | transaction_date | movement_type | quantity | stock_before | stock_after | source
-- Bicicleta X  | 2025-11-01       | sale          | -3       | 13          | 10          | pos
-- Bicicleta X  | 2025-10-30       | purchase      | +5       | 8           | 13          | manual_purchase
-- Bicicleta X  | 2025-10-28       | sale          | -2       | 10          | 8           | manual_sale
```

### 3. Verify Stock Calculation Logic
```sql
-- Get a product with movements
SELECT p.sku, p.name, p.stock_quantity as current_stock
FROM products p
WHERE p.stock_quantity > 0
LIMIT 1;

-- Check its movements
SELECT 
  transaction_date,
  movement_type,
  quantity,
  stock_before,
  stock_after,
  stock_after - stock_before as calculated_change,
  quantity as actual_change
FROM stock_movements_view
WHERE product_sku = 'YOUR_SKU_FROM_ABOVE'
ORDER BY transaction_date DESC;

-- Verify: 
-- 1. Most recent movement's stock_after should equal products.stock_quantity
-- 2. Each movement: (stock_after - stock_before) should equal quantity
-- 3. Stock levels should never be negative (unless stockout occurred)
```

### 3. Test Trigger (Create & Delete Test Invoice)
```sql
-- Create test invoice
INSERT INTO sales_invoices (
  tenant_id, 
  invoice_number, 
  customer_name, 
  status, 
  total,
  source,
  items
) VALUES (
  public.user_tenant_id(), 
  'TEST-DEPLOY-001', 
  'Test Customer', 
  'sent',  -- Must be 'sent' or 'paid' to appear in movements
  100,
  'manual_sale',
  '[{"product_id": "YOUR_PRODUCT_ID", "quantity": 2, "price": 50}]'::jsonb
);

-- Verify created_by was auto-populated
SELECT created_by, source 
FROM sales_invoices 
WHERE invoice_number = 'TEST-DEPLOY-001';
-- created_by should match auth.uid()
-- source should be 'manual_sale'

-- Check if movement appears with correct stock calculation
SELECT 
  product_name,
  quantity,
  stock_before,
  stock_after,
  transaction_date
FROM stock_movements_view 
WHERE reference_number = 'TEST-DEPLOY-001';
-- Should show: quantity: -2, stock_before and stock_after with real values

-- Cleanup
DELETE FROM sales_invoices WHERE invoice_number = 'TEST-DEPLOY-001';
```

---

## 🧪 UI Testing Checklist

After database deployment, test in the Flutter app:

1. Navigate to **Inventario → Movimientos**
2. Select a product with history
3. **Date Range Filter:**
   - Click "Rango de fechas" button
   - Select start and end dates
   - Verify movements are filtered
   - Click X button to clear filter
4. **Invoice Navigation:**
   - Click a blue underlined reference number
   - Verify it opens the correct invoice detail page
   - Test both purchase and sale references
5. **New Data Display:**
   - Create a new sale/purchase invoice with items
   - Check stock movements for that product
   - Verify `stock_before` shows actual stock level (not 0)
   - Verify `stock_after` = `stock_before` + `quantity`
   - Verify most recent movement's `stock_after` matches `products.stock_quantity`
   - Verify `source` displays correctly (not hardcoded 'manual_sale')
   - Verify movement appears in the list immediately

---

## 🔄 Rollback Plan (If Needed)

If deployment causes issues:

```sql
-- Remove triggers
DROP TRIGGER IF EXISTS trg_sales_invoices_set_created_by ON sales_invoices;
DROP TRIGGER IF EXISTS trg_purchase_invoices_set_created_by ON purchase_invoices;

-- Remove function
DROP FUNCTION IF EXISTS set_created_by();

-- Remove columns (only if absolutely necessary)
ALTER TABLE sales_invoices DROP COLUMN IF EXISTS source;
ALTER TABLE sales_invoices DROP COLUMN IF EXISTS created_by;
ALTER TABLE purchase_invoices DROP COLUMN IF EXISTS created_by;

-- Revert view to old version (manually copy from git history)
```

---

## 📊 Expected Impact

### Performance
- ✅ Minimal - Only adds 2-3 columns and lightweight triggers
- ✅ View query remains efficient (no complex joins added)

### Data Integrity
- ✅ NULL values allowed for backward compatibility
- ✅ Old records will show NULL for created_by
- ✅ New records auto-populate created_by
- ✅ Source defaults to 'manual_sale' if NULL (coalesce)

### User Experience
- ✅ Date filtering improves usability for large datasets
- ✅ Invoice navigation saves time (no manual search)
- ✅ Source tracking provides better audit trail

---

## 🎯 Next Steps After Deployment

1. **Monitor for 24 hours**
   - Check for any errors in Supabase logs
   - Verify triggers are firing correctly
   - Test multi-tenant isolation

2. **User Training**
   - Show users the new date range picker
   - Demonstrate invoice navigation feature
   - Explain source values (pos, manual_sale, etc.)

3. **Future Enhancements**
   - Implement stock_before/stock_after calculation
   - Add stock adjustment transactions
   - Add stock transfer between warehouses
   - Export movements to Excel/PDF

---

**Deployment Time Estimate:** 5-10 minutes  
**Risk Level:** Low (backward compatible, non-breaking changes)  
**User Downtime:** None (online schema migration)

---

*Ready to deploy! All code changes are already in the repository. Just need to apply the database schema updates.*
