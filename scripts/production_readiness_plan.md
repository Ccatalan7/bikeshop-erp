# 🚀 Production Readiness Plan for Vinabike ERP

**Current Status:** testbike1 tenant has 84 products (many imported from Zoho)
**Goal:** Prepare system for production use with clean data and optimal settings

---

## 📋 Pre-Flight Checklist

### ✅ Current State
- **Tenant:** testbike1 (subdomain: testbike1)
- **User:** use the dedicated E2E account from the operating-system credential store; never document a login here.
- **Products:** 84 items (imported from Zoho Books)
- **Database:** https://xzdvtzdqjeyqxnkqprtf.supabase.co
- **Tenant ID:** 5443b130-cc28-45af-a420-cd500b288890

---

## 🎯 Task 1: Test Zoho Single Product Import

**Goal:** Verify import process works correctly with proper column mapping

### Column Mapping (Zoho → Supabase)
```
name          → name
sku           → sku  
description   → description
rate          → price
purchase_rate → cost (purchase_account_name)
stock_on_hand → stock_quantity
item_type     → (detect: 'inventory' or 'service')
category_name → category_id (lookup or create)
unit          → (optional: add to description)
hsn_or_sac    → (tax code, optional)
```

**Steps:**
1. ✅ Fetch products from Zoho Books API
2. ✅ Find one product NOT in database (avoid duplicates)
3. ✅ Import using `import_product_with_context()` RPC
4. ✅ Verify stock adjustment created with "Importación" origin
5. ✅ Confirm tenant isolation (product has correct tenant_id)

**Expected Outcome:** One new product added with full audit trail

---

## 🎯 Task 2: Audit Chart of Accounts

**Goal:** Remove conceptual duplicates in Chilean accounting structure

### Known Issues to Check:
- ❌ **Inventario** vs **Mercaderías** vs **Inventario de Productos**
  - Should have ONE account: "1120 - Inventarios" (Asset account)
  
- ❌ **Costo de Ventas** duplicates
  - Should have ONE account: "5101 - Costo de Ventas" (Expense account)
  
- ❌ **IVA Débito** vs **IVA por Pagar**
  - Keep: "2110 - IVA Débito Fiscal" (current sales tax liability)
  
- ❌ **IVA Crédito** vs **IVA por Recuperar**
  - Keep: "2120 - IVA Crédito Fiscal" (recoverable purchase tax)

### Action Plan:
1. Read `seed_chart_of_accounts()` function in core_schema.sql (lines 1721-2091)
2. Identify duplicate concepts (not just exact name duplicates)
3. Consolidate to ONE account per concept
4. Update account references in:
   - `handle_sales_invoice_change()` function
   - `handle_purchase_invoice_change()` function
   - `create_sales_payment_journal_entry()` function
   - `create_purchase_payment_journal_entry()` function

**Expected Outcome:** Clean, non-redundant Chilean chart of accounts

---

## 🎯 Task 3: Clean Testing Data

**Goal:** Remove all test/demo data, keep only structural setup

### Data to KEEP:
- ✅ Chart of Accounts (cleaned version)
- ✅ Payment Methods (4 seeded: Efectivo, Transferencia, Cheque, Tarjeta)
- ✅ Company Settings (IVA 19%, CLP, timezone, prefixes)
- ✅ Website Settings (e-commerce defaults)
- ✅ Tenant record (testbike1)
- ✅ User profile (vinabikechile@gmail.com)

### Data to DELETE:
- ❌ All test products (84 items)
- ❌ All test customers
- ❌ All test suppliers
- ❌ All test invoices (sales/purchases)
- ❌ All test payments
- ❌ All test mechanic jobs (pegas)
- ❌ All test bikes
- ❌ All stock adjustments
- ❌ All journal entries (will be recreated on first real transaction)

### SQL Script:
```sql
-- Delete all transactional data for testbike1 tenant
DO $$
DECLARE
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
BEGIN
  DELETE FROM sales_invoice_items WHERE invoice_id IN (
    SELECT id FROM sales_invoices WHERE tenant_id = v_tenant_id
  );
  DELETE FROM sales_invoices WHERE tenant_id = v_tenant_id;
  DELETE FROM sales_payments WHERE tenant_id = v_tenant_id;
  
  DELETE FROM purchase_invoice_items WHERE invoice_id IN (
    SELECT id FROM purchase_invoices WHERE tenant_id = v_tenant_id
  );
  DELETE FROM purchase_invoices WHERE tenant_id = v_tenant_id;
  DELETE FROM purchase_payments WHERE tenant_id = v_tenant_id;
  
  DELETE FROM mechanic_job_parts WHERE job_id IN (
    SELECT id FROM mechanic_jobs WHERE tenant_id = v_tenant_id
  );
  DELETE FROM mechanic_jobs WHERE tenant_id = v_tenant_id;
  
  DELETE FROM bikes WHERE tenant_id = v_tenant_id;
  DELETE FROM customers WHERE tenant_id = v_tenant_id;
  DELETE FROM suppliers WHERE tenant_id = v_tenant_id;
  DELETE FROM products WHERE tenant_id = v_tenant_id;
  
  DELETE FROM stock_adjustments WHERE tenant_id = v_tenant_id;
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  
  RAISE NOTICE 'All testing data deleted for tenant %', v_tenant_id;
END $$;
```

**Expected Outcome:** Clean slate with only structural data

---

## 🎯 Task 4: Verify Default Settings

**Goal:** Ensure seeded settings are optimal for Chilean bike shop

### Company Settings to Verify:
```sql
SELECT key, value FROM company_settings 
WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
ORDER BY key;
```

**Expected Values:**
- `currency`: "CLP"
- `tax_rate`: "19" (IVA 19%)
- `timezone`: "America/Santiago"
- `fiscal_year_start`: "01-01"
- `invoice_prefix`: "FV-" (Factura de Venta)
- `purchase_invoice_prefix`: "FC-" (Factura de Compra)
- `language`: "es" (Spanish)
- `country`: "CL" (Chile)

### Website Settings to Verify:
```sql
SELECT key, value FROM website_settings 
WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
ORDER BY key;
```

**Expected Values:**
- `currency`: "CLP"
- `enable_ecommerce`: "true"
- `shipping_enabled`: "true"
- `stock_display`: "show_quantity"
- `low_stock_threshold`: "5"
- `tax_included_in_prices`: "true" (Chilean retail practice)

**Expected Outcome:** All settings aligned with Chilean business practices

---

## 🎯 Task 5: Test Tenant Isolation

**Goal:** Verify RLS policies prevent data leaks between tenants

### Test Scenarios:
1. **Create second test user** with different tenant
2. **Attempt cross-tenant queries** (should fail)
3. **Verify invoice creation** only creates entries for own tenant
4. **Verify product search** only returns own tenant's products

### Test Script:
```python
# Create user in Vinabike Shop tenant
client.auth.sign_up({
    "email": "test2@example.com",
    "password": "test123"
})

# Link to Vinabike Shop (different tenant)
vinabike_tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
client.table('user_profiles').insert({
    'user_id': new_user_id,
    'tenant_id': vinabike_tenant_id,
    'role': 'admin'
}).execute()

# Try to query testbike1 products (should return empty)
products = client.auth.sign_in_with_password({
    "email": "test2@example.com",
    "password": "test123"
})
result = client.table('products') \
    .select('*') \
    .eq('tenant_id', '5443b130-cc28-45af-a420-cd500b288890') \
    .execute()

# Should return 0 products (RLS blocks access)
assert len(result.data) == 0, "RLS FAILURE: Cross-tenant access detected!"
```

**Expected Outcome:** Zero cross-tenant data leaks

---

## 🎯 Task 6: Bulk Import 1400+ Zoho Products

**Goal:** Import entire Zoho Books inventory with performance monitoring

### Prerequisites:
- ✅ Task 1 completed (single product import working)
- ✅ Task 3 completed (database cleaned)
- ✅ Column mappings verified
- ✅ Stock tracking confirmed working

### Import Strategy:
1. **Batch Size:** 50 products at a time (balance speed vs error handling)
2. **Error Handling:** Log failed products, continue with rest
3. **Progress Tracking:** Print every 10th product
4. **Stock Adjustments:** Auto-created via `import_product_with_context()` RPC
5. **Categories:** Create missing categories on-the-fly

### Performance Metrics to Monitor:
- Import speed (products/second)
- Success rate (% imported without errors)
- Stock adjustment creation (should be 1:1 for products with stock changes)
- Database size growth
- Flutter app load time (with 1400 products)

### Import Script Template:
```python
import_ref = f"zoho_bulk_import_{int(time.time() * 1000)}"
success_count = 0
error_count = 0
start_time = time.time()

for i, item in enumerate(zoho_products, 1):
    try:
        result = client.rpc('import_product_with_context', {
            'p_tenant_id': tenant_id,
            'p_sku': item['sku'],
            'p_product_data': {
                'name': item['name'],
                'description': item.get('description'),
                'price': item.get('rate', 0),
                'cost': item.get('purchase_rate', 0),
                'stock_quantity': item.get('stock_on_hand', 0)
            },
            'p_import_reference': import_ref,
            'p_import_reason': f'Zoho Bulk Import: {item["name"]}'
        }).execute()
        
        success_count += 1
        if i % 10 == 0:
            print(f"✅ {i}/1400 products imported")
    except Exception as e:
        error_count += 1
        print(f"❌ {item['sku']}: {str(e)}")

elapsed = time.time() - start_time
print(f"\n📊 Import Summary:")
print(f"   Success: {success_count}")
print(f"   Errors: {error_count}")
print(f"   Time: {elapsed:.1f}s ({success_count/elapsed:.1f} products/sec)")
```

**Expected Outcome:** 1400+ products imported with <5% error rate

---

## 🎯 Task 7: Make core_schema.sql Idempotent

**Goal:** Schema can be deployed multiple times without breaking data

### Current Issues to Fix:
1. ❌ **Missing `IF NOT EXISTS` in ALTER TABLE**
   - Example: `ALTER TABLE products ADD COLUMN technical_specs jsonb`
   - Fix: `ALTER TABLE products ADD COLUMN IF NOT EXISTS technical_specs jsonb`

2. ❌ **Duplicate policy creation**
   - Already fixed with `DROP POLICY IF EXISTS` (Oct 2025)
   - ✅ Verified working

3. ❌ **Seed functions run multiple times**
   - Example: `seed_chart_of_accounts()` adds duplicate accounts
   - Fix: Add `ON CONFLICT DO NOTHING` to INSERT statements

4. ❌ **Function replacements without backward compatibility**
   - Use `CREATE OR REPLACE FUNCTION` (already done)
   - ✅ Verified working

### Migration Safety Checklist:
- [ ] All `ALTER TABLE ADD COLUMN` use `IF NOT EXISTS`
- [ ] All `CREATE INDEX` use `IF NOT EXISTS`
- [ ] All `INSERT` in seed functions use `ON CONFLICT DO NOTHING`
- [ ] All `CREATE POLICY` preceded by `DROP POLICY IF EXISTS`
- [ ] All `CREATE TABLE` use `IF NOT EXISTS`
- [ ] Test deployment on fresh database
- [ ] Test deployment on existing database (no errors)

**Expected Outcome:** Schema deploys cleanly on both fresh and existing databases

---

## 🚦 Execution Order

1. ✅ **Task 1:** Test single product import (30 min)
2. ✅ **Task 2:** Audit chart of accounts (1 hour)
3. ✅ **Task 4:** Verify default settings (15 min)
4. ✅ **Task 5:** Test tenant isolation (30 min)
5. ✅ **Task 7:** Make schema idempotent (1 hour)
6. ⚠️  **Task 3:** Clean testing data (15 min) - **DO LAST, AFTER VERIFICATION**
7. 🚀 **Task 6:** Bulk import Zoho products (2-3 hours)

---

## ⚠️ Rollback Plan

If anything goes wrong:

1. **Database Snapshot:** Take Supabase backup before Task 3
2. **Export Current Data:** Export 84 products to CSV before deletion
3. **Schema Backup:** Commit current core_schema.sql to git
4. **Test Environment:** Create separate tenant for testing first

**Restore Command:**
```sql
-- Restore from backup via Supabase Dashboard:
-- Projects → Your Project → Database → Backups → Restore
```

---

## ✅ Success Criteria

- [ ] Single product import working with stock tracking
- [ ] Chart of accounts has no conceptual duplicates
- [ ] All default settings optimized for Chilean bike shop
- [ ] RLS tenant isolation verified (no leaks)
- [ ] Schema is idempotent (can deploy multiple times)
- [ ] 1400+ products imported successfully
- [ ] Flutter app handles 1400 products without performance issues
- [ ] Stock adjustments labeled correctly ("Importación" vs "Ajuste Manual")

---

## 📞 Support

**If stuck, check:**
- `.github/ZOHO_IMPORT_GUIDE.md` - Complete import documentation
- `.github/ZOHO_IMPORT_QUICKREF.md` - Quick reference for AI agents
- `.github/IMPORT_STOCK_TRACKING_GUIDE.md` - Stock adjustment tracking
- `supabase/sql/core_schema.sql` - Database schema reference

**Contact:**
- Claudio (vinabikechile@gmail.com)
