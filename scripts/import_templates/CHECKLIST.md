# ✅ IMPORT/SYNC CHECKLIST

**Use this checklist before and after running sync scripts**

---

## 📋 PRE-SYNC CHECKLIST

### 1. Credentials Ready ✓

- [ ] **Supabase URL** - From dashboard project settings
- [ ] **Supabase Service Role Key** - From API settings (not anon key!)
- [ ] **Tenant ID** - From `SELECT id FROM tenants WHERE shop_name = 'YourShop'`

**If using Odoo:**
- [ ] **Odoo URL** - `https://your-company.odoo.com`
- [ ] **Database name** - Usually your company name
- [ ] **Username** - Your Odoo login email
- [ ] **API Key** - Settings > Users > Account Security > New API Key

**If using Zoho:**
- [ ] **Client ID** - From Zoho API Console
- [ ] **Client Secret** - From Zoho API Console
- [ ] **Refresh Token** - Generated using grant token
- [ ] **Organization ID** - From Zoho Books settings
- [ ] **API Domain** - Regional endpoint (US, EU, IN, AU, CN)

### 2. Configuration File ✓

- [ ] Copied `config.template.py` to `config.py`
- [ ] Filled in all required credentials
- [ ] Ran `python3 config.py` to validate (should show ✅)
- [ ] Verified `config.py` is in `.gitignore`

### 3. Database Ready ✓

- [ ] Supabase project is active (not paused)
- [ ] `product_categories` table exists
- [ ] `products` table exists
- [ ] Tenant record exists in `tenants` table
- [ ] RLS policies allow service role access

### 4. Test Connection ✓

```bash
# Quick test
python3 -c "from config import validate_config; validate_config()"
```

Expected output: `✅ Configuration validated successfully!`

---

## 🚀 DURING SYNC

### What to Watch For

✅ **Good signs:**
```
✅ Connected (Vinabike products: 1440)
✅ Fetched 144 categories
➕ Created: Accesorios / Adaptadores
✅ Updated: 1191 products
```

⚠️ **Warning signs (may be OK):**
```
⏭️ Skipped: 249 products (no category match)
⚠️ Not found in Odoo: 30
```
→ Often expected for service items, custom products

❌ **Error signs (need fixing):**
```
❌ Failed to authenticate
❌ Column parent_id does not exist
❌ Division by zero
❌ Invalid input syntax for type integer
```
→ See troubleshooting guide

### Progress Monitoring

- Script should show progress every 50-100 items
- Total time: ~2-5 minutes for 1,400+ products
- No output for >30 seconds? Check connection

---

## 📊 POST-SYNC CHECKLIST

### 1. Verify Data Counts ✓

Run in Supabase SQL Editor:

```sql
-- Check categories
SELECT COUNT(*) FROM product_categories WHERE tenant_id = 'YOUR_TENANT_ID';
-- Expected: 144 (Odoo) or varies (Zoho)

-- Check products
SELECT COUNT(*) FROM products WHERE tenant_id = 'YOUR_TENANT_ID';
-- Expected: 1440 (Vinabike example)

-- Check products WITH categories
SELECT COUNT(*) FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID' AND category_id IS NOT NULL;
-- Expected: 80-90% coverage

-- Check products WITHOUT categories
SELECT sku, name FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID' AND category_id IS NULL
LIMIT 20;
-- Review if these should have categories
```

### 2. Verify Category Hierarchy ✓

```sql
-- Check hierarchy levels
SELECT level, COUNT(*) 
FROM product_categories 
WHERE tenant_id = 'YOUR_TENANT_ID'
GROUP BY level 
ORDER BY level;

-- Expected:
-- level 0: root categories (10-20)
-- level 1: main subcategories (50-80)
-- level 2-4: deeper nesting (varies)

-- Check parent-child relationships
SELECT 
  parent.name as parent_name,
  child.name as child_name,
  child.level
FROM product_categories child
LEFT JOIN product_categories parent ON child.parent_id = parent.id
WHERE child.tenant_id = 'YOUR_TENANT_ID'
LIMIT 10;
```

### 3. Verify Product Data ✓

```sql
-- Check price ranges
SELECT 
  MIN(price) as min_price,
  MAX(price) as max_price,
  AVG(price) as avg_price
FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID' AND price > 0;

-- Check stock quantities
SELECT 
  COUNT(*) FILTER (WHERE stock_quantity > 0) as with_stock,
  COUNT(*) FILTER (WHERE stock_quantity = 0) as no_stock
FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID';

-- Check for NULL/empty required fields
SELECT 
  COUNT(*) FILTER (WHERE sku IS NULL OR sku = '') as missing_sku,
  COUNT(*) FILTER (WHERE name IS NULL OR name = '') as missing_name,
  COUNT(*) FILTER (WHERE brand IS NULL OR brand = '') as missing_brand
FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID';
```

### 4. Flutter App Verification ✓

- [ ] Open Flutter app and navigate to Products
- [ ] Check categories appear in sidebar/menu
- [ ] Click a category → products filter correctly
- [ ] Search for a product → finds it
- [ ] Open product detail → all fields populated
- [ ] Check product images load (if synced)
- [ ] Verify stock quantities are correct

### 5. Sample Product Checks ✓

Pick 3-5 random products and verify:

```sql
-- Pick random products
SELECT id, sku, name, price, stock_quantity, 
       (SELECT name FROM product_categories WHERE id = products.category_id) as category
FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID'
ORDER BY RANDOM()
LIMIT 5;
```

For each product:
- [ ] SKU matches source system (Odoo/Zoho)
- [ ] Name matches
- [ ] Price matches
- [ ] Stock quantity matches
- [ ] Category is correct
- [ ] Image loads (if applicable)

---

## 🔍 TROUBLESHOOTING CHECKLIST

### Categories Not Showing

- [ ] Check `product_categories` table has data
- [ ] Verify `tenant_id` is correct
- [ ] Check Flutter app filters by `tenant_id`
- [ ] Clear Flutter app cache and restart

### Products Without Categories

- [ ] Are they service items? (expected)
- [ ] Are SKUs missing in source system?
- [ ] Run comparison: which SKUs don't match?
- [ ] Manually assign categories if needed

### Duplicate Products

```sql
-- Find duplicate SKUs
SELECT sku, COUNT(*) 
FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID'
GROUP BY sku 
HAVING COUNT(*) > 1;
```

If found:
- [ ] Delete duplicates (keep newest)
- [ ] Re-run sync with deduplication

### Performance Issues

- [ ] Too many products? Reduce batch size
- [ ] Rate limiting? Increase delay between requests
- [ ] Network slow? Check internet connection
- [ ] Database slow? Check Supabase usage metrics

---

## 📝 DOCUMENTATION CHECKLIST

After successful sync:

- [ ] Note sync date and time
- [ ] Record total products synced
- [ ] Note any products skipped/errors
- [ ] Document custom mappings (if any)
- [ ] Save script output to log file
- [ ] Update team on sync status

---

## 🔄 RECURRING SYNC CHECKLIST

If setting up periodic syncs:

- [ ] Decide sync frequency (daily? weekly?)
- [ ] Choose sync strategy (full or delta)
- [ ] Set up cron job or cloud function
- [ ] Configure error notifications
- [ ] Test dry run first
- [ ] Monitor first few runs
- [ ] Document sync schedule

---

## 🚨 ROLLBACK CHECKLIST

If something goes wrong:

1. **Stop the script** (Ctrl+C)
2. **Export current data** (backup)
3. **Identify issue** (check error logs)
4. **Restore from backup** (if needed)
5. **Fix configuration** (update config.py)
6. **Test with 1 product** (dry run)
7. **Re-run sync** (monitor closely)

---

## 📊 SUCCESS METRICS

**Sync is successful if:**

✅ All expected products imported
✅ 80%+ products have categories
✅ No duplicate products
✅ Stock quantities accurate
✅ Flutter app displays correctly
✅ Performance is acceptable
✅ No critical errors

**Good enough for production:**
- Categories: 100% coverage (all created)
- Products: 95%+ imported successfully
- With categories: 80%+ (service items may not have)
- Errors: <5% of total

---

## 🎯 NEXT STEPS AFTER SYNC

- [ ] Test Flutter app thoroughly
- [ ] Train team on new category structure
- [ ] Update documentation
- [ ] Schedule next sync (if recurring)
- [ ] Monitor for data discrepancies
- [ ] Set up alerts for stock/price changes

---

**Keep this checklist handy for every sync operation!**
