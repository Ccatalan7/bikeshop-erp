# 🔍 Smart Purchase List - Debugging Real-Time Updates

## How to Test Real-Time Sync

### Test 1: Verify Trigger is Working

1. **Open Supabase SQL Editor** and run:
```sql
-- Check if trigger exists
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgname = 'trg_auto_add_low_stock';

-- Should return:
-- tgname: trg_auto_add_low_stock
-- tgenabled: O (enabled)
```

2. **Manually trigger the function**:
```sql
-- Find a product with stock above minimum
SELECT id, name, stock_quantity, min_stock_level 
FROM products 
WHERE stock_quantity > min_stock_level 
LIMIT 1;

-- Manually reduce stock below minimum
UPDATE products 
SET stock_quantity = min_stock_level - 1,
    inventory_qty = min_stock_level - 1
WHERE id = '<product_id_from_above>';

-- Check if it was added to smart_purchase_list
SELECT product_name, current_stock, min_stock_level, status, priority
FROM smart_purchase_list
WHERE product_id = '<product_id_from_above>';
```

### Test 2: Real-Time Update in App

1. **Open Smart Purchase List page** in your app
2. **Keep the page OPEN** (don't navigate away)
3. **In another browser tab/window**, create a sale invoice that reduces stock below minimum
4. **Watch the Smart Purchase List** - the product should appear automatically (within 1-2 seconds)

### Test 3: Performance Test

1. **Clear browser cache** (hard refresh)
2. **Open Smart Purchase List** for first time
3. **Check DevTools Console** for logs:
   ```
   ⚡ Fast load: X items from smart_purchase_list
   🔔 Real-time listeners active for smart purchase list
   ✅ SmartPurchaseListService initialized with X items at <timestamp>
   ```
4. **Measure load time** - should be <500ms even with hundreds of items

## Why Real-Time Might Not Update

### Issue 1: Page Not Open
**Problem:** You created the sale, then navigated to Smart Purchase List
**Solution:** Real-time listeners only work when page is MOUNTED
**Fix:** Keep page open while creating sales to see real-time updates

### Issue 2: Trigger Not Firing
**Problem:** Sales invoice might not update `stock_quantity` column
**Check:** Verify `consume_sales_invoice_inventory()` function updates stock
**SQL to verify:**
```sql
-- Check if function exists
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name = 'consume_sales_invoice_inventory';

-- Check last update on products table
SELECT id, name, stock_quantity, updated_at 
FROM products 
WHERE updated_at > NOW() - INTERVAL '1 hour'
ORDER BY updated_at DESC;
```

### Issue 3: Supabase Realtime Not Enabled
**Problem:** Realtime might be disabled for tables
**Check in Supabase Dashboard:**
1. Go to Database > Replication
2. Verify `smart_purchase_list` table has Realtime enabled
3. Verify `products` table has Realtime enabled

### Issue 4: Stock Not Actually Below Minimum
**Problem:** Stock reduced but still above `min_stock_level`
**Check:**
```sql
SELECT 
  p.name,
  p.stock_quantity as current,
  p.min_stock_level as minimum,
  p.stock_quantity - p.min_stock_level as difference,
  CASE 
    WHEN p.stock_quantity <= p.min_stock_level THEN '✅ Should trigger'
    ELSE '❌ Above minimum'
  END as should_add
FROM products p
WHERE p.id = '<your_product_id>';
```

## Expected Behavior

### Scenario 1: Fresh Load (First Visit)
- User opens Smart Purchase List
- `initialize()` called
- Fetches all items in ONE query (fast)
- Sets up real-time listeners
- UI displays immediately
- **Time: ~200-500ms**

### Scenario 2: Filter Change
- User changes status/supplier/search filter
- `getFilteredItems()` called
- Filters applied in-memory (no database query)
- UI updates immediately
- **Time: ~0ms (instant)**

### Scenario 3: Stock Goes Low (Page Open)
- User makes a sale (stock reduced)
- `products` table UPDATE triggers `trg_auto_add_low_stock`
- Trigger checks: `stock_quantity <= min_stock_level`
- Trigger inserts into `smart_purchase_list`
- Real-time listener fires `_handlePurchaseListChange()`
- New item added to `_items` list
- `notifyListeners()` triggers UI rebuild
- **Time: ~1-2 seconds**

### Scenario 4: Stock Goes Low (Page NOT Open)
- User makes a sale (stock reduced)
- Trigger adds item to `smart_purchase_list` table
- NO real-time update (page not listening)
- User navigates to Smart Purchase List
- `initialize()` fetches updated list (includes new item)
- UI displays with new item
- **Time: ~200-500ms (next visit)**

## Debug Console Output

When working correctly, you should see:

```
// On page load:
⚡ Fast load: 15 items from smart_purchase_list
🔔 Real-time listeners active for smart purchase list
✅ SmartPurchaseListService initialized with 15 items at 2025-11-03 14:30:00

// When stock changes (page open):
🔔 Purchase list change: INSERT
➕ Added item: Shimano Deore XT
📦 Enriched product cache with 1 products

// When filtering:
⚡ Applying filters to cached data (instant)
```

## Common Mistakes

❌ **Creating sale → Immediately navigate to Smart Purchase List**
- Realtime listener not active during sale creation
- Use manual "Recargar" button OR wait 1-2 seconds

✅ **Keep Smart Purchase List open → Create sale → Watch update**
- Realtime listener active
- Update happens automatically

❌ **Running in debug mode expecting instant load**
- Debug mode has overhead (DevTools, hot reload, etc.)
- Production build is 2-3x faster

✅ **Test in production build (`flutter build web --release`)**
- No debug overhead
- Actual performance visible

## Performance Expectations

| Environment | Initial Load | Filter Change | Real-Time Update |
|-------------|--------------|---------------|------------------|
| Debug (Dev Server) | ~1-2 seconds | Instant | 1-2 seconds |
| Production (Firebase) | ~200-500ms | Instant | 1-2 seconds |
| With 1500 products (Production) | ~500ms-1s | Instant | 1-2 seconds |

## Next Steps

1. **Test trigger manually** (SQL above)
2. **Enable Realtime in Supabase** (Database > Replication)
3. **Test with page open** (keep page mounted during sale)
4. **Deploy to production** and test performance
5. **Monitor console** for debug logs

If still not working after these checks, we may need to add explicit logging to the trigger function!
