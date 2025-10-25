# ✅ TENANT MIGRATION - SCHEMA UPDATE COMPLETE

## 📊 Migration Status: SCHEMA COMPLETE (17/17 Tables)

**All 17 missing tables have been updated with `tenant_id` column!**

---

## ✅ Tables Updated (17/17)

### Configuration & Settings (6)
1. ✅ **company_settings** - Added `tenant_id`, `unique(tenant_id, key)`
2. ✅ **product_brands** - Added `tenant_id`, `unique(tenant_id, name)`
3. ✅ **payment_methods** - Added `tenant_id`, `unique(tenant_id, code)`
4. ✅ **expense_categories** - Added `tenant_id`, `unique(tenant_id, name)`
5. ✅ **departments** - Added `tenant_id`, `unique(tenant_id, name)`
6. ✅ **service_packages** - Added `tenant_id`, `unique(tenant_id, name)`

### HR & Scheduling (2)
7. ✅ **work_schedules** - Added `tenant_id`, `unique(tenant_id, name)`
8. ✅ **employee_contracts** - Added `tenant_id`

### Expenses & Attachments (1)
9. ✅ **expense_attachments** - Added `tenant_id`

### Website & Ecommerce (3)
10. ✅ **website_banners** - Added `tenant_id`
11. ✅ **website_content** - Added `tenant_id`
12. ✅ **online_order_items** - Added `tenant_id`

### POS & Orders (2)
13. ✅ **orders** - Added `tenant_id`
14. ✅ **order_items** - Added `tenant_id`

### Bikeshop/Maintenance (3)
15. ✅ **mechanic_jobs** - Added `tenant_id` (parent table)
16. ✅ **mechanic_job_items** - Inherits from parent
17. ✅ **mechanic_job_labor** - Inherits from parent
18. ✅ **mechanic_job_timeline** - Inherits from parent

---

## 📝 Changes Made to Each Table

For each table, we:
1. ✅ Added column: `tenant_id uuid references tenants(id) on delete cascade not null`
2. ✅ Added index: `create index if not exists idx_[table]_tenant on [table](tenant_id);`
3. ✅ Updated unique constraints to include `tenant_id` where applicable (e.g., `unique(tenant_id, name)`)
4. ✅ Removed old migration DO blocks that checked column-by-column

---

## 🚨 NEXT STEPS - DEPLOY NOW!

### Step 1: Data Migration (CRITICAL!)
**Assign ALL existing data to Vinabike tenant:**

```sql
-- Vinabike tenant ID
DO $$
DECLARE
  v_vinabike_tenant uuid := '97ef40bf-f58c-4f76-a629-c013fb3928cf';
BEGIN
  -- Configuration & Settings
  UPDATE company_settings SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE product_brands SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE payment_methods SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE expense_categories SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE departments SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE service_packages SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  
  -- HR & Scheduling
  UPDATE work_schedules SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE employee_contracts SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  
  -- Expenses
  UPDATE expense_attachments SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  
  -- Website
  UPDATE website_banners SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE website_content SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE online_order_items SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  
  -- Orders
  UPDATE orders SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  UPDATE order_items SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  
  -- Bikeshop
  UPDATE mechanic_jobs SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
  
  RAISE NOTICE 'Data migration complete!';
END $$;
```

### Step 2: Create RLS Policies

**For ALL 17 tables, add tenant-based RLS policies:**

```sql
-- Example for company_settings (repeat pattern for all 17 tables)
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_settings_tenant_select" ON company_settings;
CREATE POLICY "company_settings_tenant_select" 
  ON company_settings FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "company_settings_tenant_insert" ON company_settings;
CREATE POLICY "company_settings_tenant_insert" 
  ON company_settings FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "company_settings_tenant_update" ON company_settings;
CREATE POLICY "company_settings_tenant_update" 
  ON company_settings FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "company_settings_tenant_delete" ON company_settings;
CREATE POLICY "company_settings_tenant_delete" 
  ON company_settings FOR DELETE 
  USING (tenant_id = public.user_tenant_id());
```

**Apply to ALL 17 tables:**
- company_settings
- product_brands
- payment_methods
- expense_categories
- departments
- service_packages
- work_schedules
- employee_contracts
- expense_attachments
- website_banners
- website_content
- online_order_items
- orders
- order_items
- mechanic_jobs
- mechanic_job_items (child)
- mechanic_job_labor (child)
- mechanic_job_timeline (child)

### Step 3: Auto-Seed Trigger for New Tenants

**Create trigger to seed default data when new tenant is created:**

```sql
CREATE OR REPLACE FUNCTION public.seed_tenant_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Default payment methods
  INSERT INTO payment_methods (tenant_id, code, name, active)
  VALUES 
    (NEW.id, 'CASH', 'Efectivo', true),
    (NEW.id, 'TRANSFER', 'Transferencia', true),
    (NEW.id, 'CARD', 'Tarjeta', true),
    (NEW.id, 'MERCADOPAGO', 'MercadoPago', true);
  
  -- Default expense categories
  INSERT INTO expense_categories (tenant_id, name, description)
  VALUES
    (NEW.id, 'Arriendo', 'Arriendo de local'),
    (NEW.id, 'Servicios', 'Luz, agua, internet'),
    (NEW.id, 'Sueldos', 'Salarios y honorarios'),
    (NEW.id, 'Insumos', 'Material de oficina'),
    (NEW.id, 'Otros', 'Gastos varios');
  
  -- Default departments
  INSERT INTO departments (tenant_id, name, description)
  VALUES
    (NEW.id, 'Ventas', 'Departamento de ventas'),
    (NEW.id, 'Taller', 'Taller mecánico'),
    (NEW.id, 'Administración', 'Administración y contabilidad');
  
  -- Default company settings
  INSERT INTO company_settings (tenant_id, key, value)
  VALUES
    (NEW.id, 'home_icon', 'store'),
    (NEW.id, 'company_name', NEW.name),
    (NEW.id, 'currency', 'CLP'),
    (NEW.id, 'tax_rate', '19'),
    (NEW.id, 'timezone', 'America/Santiago');
  
  -- Default work schedule (45h week, Chilean standard)
  INSERT INTO work_schedules (tenant_id, name, description, 
    monday_start, monday_end,
    tuesday_start, tuesday_end,
    wednesday_start, wednesday_end,
    thursday_start, thursday_end,
    friday_start, friday_end,
    weekly_hours, active)
  VALUES
    (NEW.id, 'Horario Estándar', 'Lunes a Viernes 9:00-18:00',
    '09:00', '18:00',
    '09:00', '18:00',
    '09:00', '18:00',
    '09:00', '18:00',
    '09:00', '18:00',
    45.00, true);
  
  RAISE NOTICE 'Default data seeded for tenant: %', NEW.name;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_seed_tenant_defaults ON tenants;
CREATE TRIGGER trigger_seed_tenant_defaults
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION public.seed_tenant_defaults();
```

---

## 🔐 Security Impact

**BEFORE Migration:**
- ❌ Logo uploads affected ALL tenants
- ❌ Payment methods shared (delete "Efectivo" → all lose it)
- ❌ Departments shared (Vinabike creates "Ventas" → Claudio sees it)
- ❌ Company settings global (home_icon shared)
- ❌ Work schedules shared
- ❌ Website content shared

**AFTER Migration:**
- ✅ Each tenant has own logo
- ✅ Each tenant has own payment methods
- ✅ Each tenant has own departments
- ✅ Each tenant has own company settings
- ✅ Each tenant has own work schedules
- ✅ Each tenant has own website content
- ✅ Complete data isolation

---

## 📋 Deployment Checklist

1. ✅ **Schema updated** - All 17 tables have `tenant_id` column
2. ⏳ **Deploy to Supabase** - Run updated `core_schema.sql`
3. ⏳ **Migrate existing data** - Assign all to Vinabike tenant
4. ⏳ **Create RLS policies** - Enable tenant filtering at DB level
5. ⏳ **Create auto-seed trigger** - Default data for new tenants
6. ⏳ **Test with 2 test tenants** - Verify complete isolation
7. ⏳ **Update Flutter services** - Ensure app-level filtering works

---

## 🎯 File Modified

**Updated in this migration:**
- `supabase/sql/core_schema.sql` (10,925 lines)
  - Added `tenant_id` to 17 tables
  - Added indexes on `tenant_id` for all 17 tables
  - Added `unique(tenant_id, name/code/key)` constraints where applicable
  - Removed old migration DO blocks

---

## ⚠️ CRITICAL REMINDERS

1. **Deploy the FULL `core_schema.sql`** - Don't create separate migration files
2. **Run data migration IMMEDIATELY after deploy** - Assign existing data to Vinabike
3. **RLS policies are CRITICAL** - Without them, app-level filtering can be bypassed
4. **Test with TWO test tenants** - NOT with Vinabike production data
5. **Auto-seed trigger prevents empty states** - New tenants get default payment methods, departments, etc.

---

## 🚀 Ready to Deploy!

**The schema is ready. Next:**
1. Deploy `core_schema.sql` to Supabase
2. Run data migration script
3. Create RLS policies
4. Create auto-seed trigger
5. Test with test tenants
6. Celebrate complete multi-tenant isolation! 🎉
