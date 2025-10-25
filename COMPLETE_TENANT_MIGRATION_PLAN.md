# 🔒 COMPLETE TENANT ISOLATION MIGRATION PLAN

**Date:** October 25, 2025  
**Status:** 🚧 WORK IN PROGRESS - CRITICAL GAPS IDENTIFIED

---

## 🎯 OBJECTIVE

**Make EVERY piece of data and functionality tenant-isolated.**

Not just the examples (Reiniciar Sistema, reports), but a **SYSTEMATIC architectural change** where:
1. ✅ Every table has `tenant_id` (except global reference tables)
2. ✅ Every query filters by `tenant_id`
3. ✅ Every function respects tenant boundaries
4. ✅ Every file (logos, images) is tenant-isolated
5. ✅ Every setting is per-tenant
6. ✅ No cross-tenant data leakage possible

---

## 📊 CURRENT STATE AUDIT

### ✅ Tables WITH tenant_id (SAFE)
1. ✅ `tenants` - The root table (has `id`)
2. ✅ `user_activity_log` - Has `tenant_id`
3. ✅ `user_invitations` - Has `tenant_id`
4. ✅ `customers` - Has `tenant_id`
5. ✅ `customer_addresses` - Has `tenant_id` (via customer FK)
6. ✅ `products` - Has `tenant_id`
7. ✅ `product_categories` - Has `tenant_id`
8. ✅ `categories` - Has `tenant_id`
9. ✅ `suppliers` - Has `tenant_id`
10. ✅ `accounts` - Has `tenant_id`
11. ✅ `sales_invoices` - Has `tenant_id`
12. ✅ `sales_payments` - Has `tenant_id`
13. ✅ `purchase_invoices` - Has `tenant_id`
14. ✅ `purchase_payments` - Has `tenant_id`
15. ✅ `expenses` - Has `tenant_id`
16. ✅ `expense_lines` - Has `tenant_id`
17. ✅ `expense_payments` - Has `tenant_id`
18. ✅ `stock_movements` - Has `tenant_id`
19. ✅ `journal_entries` - Has `tenant_id`
20. ✅ `journal_lines` - Has `tenant_id`
21. ✅ `bikes` - Has `tenant_id` (via customer FK)
22. ✅ `mechanic_jobs` - Has `tenant_id`
23. ✅ `employees` - Has `tenant_id`
24. ✅ `attendances` - Has `tenant_id`
25. ✅ `website_blocks` - Has `tenant_id`
26. ✅ `website_settings` - Has `tenant_id`
27. ✅ `online_orders` - Has `tenant_id`

### ❌ Tables WITHOUT tenant_id (CRITICAL GAPS)

#### **GLOBAL SETTINGS & CONFIGURATION**
28. ❌ **`company_settings`** - NO tenant_id!
   - Stores: `company_logo`, `home_icon`, etc.
   - **PROBLEM:** All tenants share the same logo!
   - **FIX NEEDED:** Add `tenant_id`, migrate data

29. ❌ **`payment_methods`** - NO tenant_id!
   - Stores: Cash, Transfer, Card payment methods
   - **PROBLEM:** All tenants share payment methods
   - **FIX NEEDED:** Add `tenant_id`, seed per tenant

#### **PRODUCT & INVENTORY**
30. ❌ **`product_brands`** - NO tenant_id!
   - Stores: Shimano, Trek, etc.
   - **DECISION NEEDED:** Global reference table OR per-tenant?
   - **RECOMMENDATION:** Per-tenant (each shop may have different brands)

#### **WEBSITE & E-COMMERCE**
31. ❌ **`website_banners`** - NO tenant_id!
   - **PROBLEM:** Banners shared across tenants
   - **FIX NEEDED:** Add `tenant_id`

32. ❌ **`website_content`** - NO tenant_id!
   - **PROBLEM:** Website content shared
   - **FIX NEEDED:** Add `tenant_id`

33. ❌ **`online_order_items`** - NO tenant_id!
   - **PROBLEM:** Order items not directly isolated
   - **FIX NEEDED:** Add `tenant_id` (even though FK to online_orders)

#### **BIKESHOP MODULE**
34. ❌ **`service_packages`** - NO tenant_id!
   - Stores: "Tune-up básico", "Revisión completa"
   - **PROBLEM:** Service packages shared
   - **FIX NEEDED:** Add `tenant_id`

35. ❌ **`mechanic_job_items`** - NO tenant_id!
   - **PROBLEM:** Parts used in jobs not directly isolated
   - **FIX NEEDED:** Add `tenant_id`

36. ❌ **`mechanic_job_labor`** - NO tenant_id!
   - **PROBLEM:** Labor entries not directly isolated
   - **FIX NEEDED:** Add `tenant_id`

37. ❌ **`mechanic_job_timeline`** - NO tenant_id!
   - **PROBLEM:** Timeline entries not directly isolated
   - **FIX NEEDED:** Add `tenant_id`

#### **HR MODULE**
38. ❌ **`departments`** - NO tenant_id!
   - Stores: "Ventas", "Taller", "Administración"
   - **PROBLEM:** Departments shared across tenants
   - **FIX NEEDED:** Add `tenant_id`

39. ❌ **`work_schedules`** - NO tenant_id!
   - **PROBLEM:** Work schedules not isolated
   - **FIX NEEDED:** Add `tenant_id`

40. ❌ **`employee_contracts`** - NO tenant_id!
   - **PROBLEM:** Contracts not directly isolated
   - **FIX NEEDED:** Add `tenant_id`

#### **EXPENSE MODULE**
41. ❌ **`expense_categories`** - NO tenant_id!
   - Stores: "Rent", "Utilities", "Salaries"
   - **PROBLEM:** Expense categories shared
   - **FIX NEEDED:** Add `tenant_id`, seed per tenant

42. ❌ **`expense_attachments`** - NO tenant_id!
   - **PROBLEM:** File attachments not directly isolated
   - **FIX NEEDED:** Add `tenant_id`

#### **POS/ORDERS**
43. ❌ **`orders`** - NO tenant_id!
   - **PROBLEM:** POS orders not isolated
   - **FIX NEEDED:** Add `tenant_id`

44. ❌ **`order_items`** - NO tenant_id!
   - **PROBLEM:** Order line items not isolated
   - **FIX NEEDED:** Add `tenant_id`

---

## 🚨 CRITICAL SECURITY IMPLICATIONS

### **What Can Go Wrong RIGHT NOW:**

1. **Logo de la Empresa:**
   - ❌ `company_settings` has NO `tenant_id`
   - ❌ If Claudio uploads logo → ALL tenants see it
   - ❌ If Vinabike changes logo → Claudio's shop changes too
   - ❌ **DATA LEAK:** Logos are not tenant-isolated!

2. **Payment Methods:**
   - ❌ `payment_methods` has NO `tenant_id`
   - ❌ All tenants share: "Efectivo", "Transferencia", etc.
   - ❌ If one tenant adds custom payment method → all see it
   - ❌ If one tenant deletes "Efectivo" → all lose it!

3. **Expense Categories:**
   - ❌ `expense_categories` has NO `tenant_id`
   - ❌ All tenants share expense categories
   - ❌ Cross-tenant category pollution possible

4. **Departments:**
   - ❌ `departments` has NO `tenant_id`
   - ❌ Vinabike creates "Ventas" → Claudio sees it
   - ❌ Deleting department affects all tenants

5. **Service Packages:**
   - ❌ `service_packages` has NO `tenant_id`
   - ❌ All bikeshops share same service packages
   - ❌ Custom packages visible to all tenants

---

## 🔧 MIGRATION STRATEGY

### **Phase 1: ADD tenant_id to ALL Tables** (THIS WEEKEND)

```sql
-- Add tenant_id to all missing tables
ALTER TABLE company_settings ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE product_brands ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE website_banners ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE website_content ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE online_order_items ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE service_packages ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE mechanic_job_items ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE mechanic_job_labor ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE mechanic_job_timeline ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE departments ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE work_schedules ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE employee_contracts ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE expense_attachments ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;

-- Make tenant_id NOT NULL (after assigning existing data)
-- ALTER TABLE company_settings ALTER COLUMN tenant_id SET NOT NULL;
-- ... repeat for all tables
```

### **Phase 2: MIGRATE Existing Data** (THIS WEEKEND)

```sql
-- Assign all existing data to Vinabike tenant
DO $$
DECLARE
  v_vinabike_id UUID := '97ef40bf-f58c-4f76-a629-c013fb3928cf';
BEGIN
  UPDATE company_settings SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE payment_methods SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE product_brands SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE website_banners SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE website_content SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE online_order_items SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE service_packages SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE mechanic_job_items SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE mechanic_job_labor SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE mechanic_job_timeline SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE departments SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE work_schedules SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE employee_contracts SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE expense_categories SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE expense_attachments SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE orders SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
  UPDATE order_items SET tenant_id = v_vinabike_id WHERE tenant_id IS NULL;
END $$;
```

### **Phase 3: CREATE RLS Policies** (THIS WEEKEND)

```sql
-- Enable RLS on all new tenant-isolated tables
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
-- ... all other tables

-- Create tenant-based policies
CREATE POLICY "company_settings_select" ON company_settings FOR SELECT USING (tenant_id = user_tenant_id());
CREATE POLICY "payment_methods_select" ON payment_methods FOR SELECT USING (tenant_id = user_tenant_id());
-- ... all CRUD policies for all tables
```

### **Phase 4: UPDATE Flutter Services** (THIS WEEKEND)

Update ALL services to inject `tenant_id`:
- ✅ `factory_reset_service.dart` - DONE
- ⚠️ `company_settings_service.dart` - NEEDS UPDATE
- ⚠️ `payment_methods_service.dart` - NEEDS UPDATE
- ⚠️ `departments_service.dart` - NEEDS UPDATE
- ⚠️ `service_packages_service.dart` - NEEDS UPDATE
- ⚠️ All other services...

### **Phase 5: AUDIT Database Functions** (THIS WEEKEND)

Check EVERY database function for tenant filtering:
- ✅ Report functions - DONE
- ⚠️ Helper functions (ensure_account, etc.) - VERIFY
- ⚠️ Trigger functions - VERIFY ALL
- ⚠️ Stored procedures - VERIFY ALL

---

## 📋 IMMEDIATE ACTION ITEMS

### **TONIGHT (Before Deployment):**

1. ✅ Run the ALTER TABLE script (Phase 1)
2. ✅ Run the UPDATE script (Phase 2) - assign to Vinabike
3. ✅ Create RLS policies (Phase 3)
4. ✅ Update `core_schema.sql` with these changes
5. ✅ Deploy to Supabase

### **THIS WEEKEND:**

6. ⚠️ Seed default data per tenant:
   - Payment methods (Efectivo, Transferencia, etc.)
   - Expense categories (Rent, Utilities, etc.)
   - Departments (Ventas, Taller, etc.)

7. ⚠️ Create trigger to auto-seed on new tenant creation

8. ⚠️ Update ALL Flutter services to inject tenant_id

9. ⚠️ Test with TWO test tenants (not Vinabike!)

---

## 🎯 ARCHITECTURAL DECISION: Global vs Per-Tenant Data

### **Per-Tenant (Each tenant has own copy):**
✅ `payment_methods` - Different shops, different payment options
✅ `expense_categories` - Different expense structures
✅ `departments` - Different org structures
✅ `service_packages` - Different service offerings
✅ `product_brands` - Some brands exclusive to shops
✅ `company_settings` - Obviously per-tenant (logo, etc.)

### **Global (Shared reference data):**
❌ NONE - Everything should be per-tenant for complete isolation

**Reasoning:** Even "reference data" like brands should be per-tenant because:
- Different shops carry different brands
- Custom brands per shop
- Deletion by one tenant shouldn't affect others
- Complete data isolation is safer

---

## 🚨 STOP-SHIP CRITERIA

**DO NOT deploy to production until:**
- [ ] All 17 tables have `tenant_id` column
- [ ] All existing data assigned to correct tenant
- [ ] All RLS policies created for new columns
- [ ] All Flutter services updated to inject `tenant_id`
- [ ] Factory reset tested on test tenant (not Vinabike!)
- [ ] Company logo upload tested (no cross-tenant visibility)
- [ ] Payment methods tested (no cross-tenant sharing)

---

## 📞 NEXT STEPS

**User (YOU) decides:**
1. Do we execute this migration NOW (tonight)?
2. Do we need more testing before deploying?
3. Are there any other tables/features I missed?

**I will:**
1. Create the complete migration SQL script
2. Update `core_schema.sql` with all changes
3. Create RLS policies for all new tenant_id columns
4. Help update Flutter services
5. Create test plan for verification

**READY TO EXECUTE?** Say the word and I'll create the complete migration script.

