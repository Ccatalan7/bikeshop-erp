# 🏢 Multi-Tenant Architecture Guide for Vinabike ERP

**Quick reference for implementing tenant isolation in your bike shop ERP**

---

## 📊 Current vs Multi-Tenant Architecture

### **Current Setup (Single Tenant)**

```
Supabase Database:
├── auth.users (all users mixed)
├── products (all products visible to everyone)
├── sales_invoices (all invoices visible to everyone)
└── customers (all customers visible to everyone)

Problem: If user A and user B both sign up, they see each other's data!
```

### **Multi-Tenant Setup (Goal)**

```
Supabase Database:
├── tenants (bike shops: Vinabike, Shop A, Shop B)
├── auth.users (with tenant_id in metadata)
├── products (with tenant_id column → RLS filters automatically)
├── sales_invoices (with tenant_id column → RLS filters automatically)
└── customers (with tenant_id column → RLS filters automatically)

Result: Each shop sees ONLY their data via Row Level Security
```

---

## 🎯 Key Concepts

### **1. Tenant = Bike Shop**

- Vinabike Santiago = 1 tenant
- Bike Shop LA = 1 tenant  
- Pedalea Feliz = 1 tenant

### **2. Users Belong to Tenants**

```
admin@vinabike.cl      → tenant_id: "550e8400..."  (Vinabike)
cashier@vinabike.cl    → tenant_id: "550e8400..."  (Vinabike)
owner@bikeshopla.cl    → tenant_id: "660f9511..."  (Bike Shop LA)
```

### **3. All Data Has tenant_id**

**Before:**
```sql
products: id | name | price
```

**After:**
```sql
products: id | tenant_id | name | price
```

### **4. RLS Filters Automatically**

```sql
-- User queries: SELECT * FROM products;
-- RLS adds automatically: WHERE tenant_id = 'user_tenant_id'
-- User only sees their tenant's products!
```

---

## 🗄️ Database Example

### **Tenants Table**

```
| id (UUID)      | shop_name         | owner_email         | created_at |
|----------------|-------------------|---------------------|------------|
| 550e8400...    | Vinabike Santiago | admin@vinabike.cl   | 2025-01-01 |
| 660f9511...    | Bike Shop LA      | owner@bikeshopla.cl | 2025-02-15 |
```

### **Products Table (All Shops in ONE Table)**

```
| id | tenant_id   | name          | sku      | price  |
|----|-------------|---------------|----------|--------|
| 1  | 550e8400... | Bicicleta MTB | MTB-001  | 500000 | ← Vinabike
| 2  | 550e8400... | Casco Pro     | CASCO-01 | 45000  | ← Vinabike
| 3  | 660f9511... | Road Bike     | RD-100   | 800000 | ← Bike Shop LA
```

**When `admin@vinabike.cl` queries products:**
- RLS filters to only show rows where `tenant_id = '550e8400...'`
- They see ONLY products 1 and 2
- Product 3 is invisible to them!

---

## 🔧 Implementation Plan

### **Phase 1: Database Schema (1-2 hours)**

#### **Step 1.1: Create tenants table**

```sql
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_name TEXT NOT NULL,
  subdomain TEXT UNIQUE,
  owner_email TEXT,
  plan TEXT DEFAULT 'free', -- 'free', 'pro', 'enterprise'
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create your first tenant (Vinabike)
INSERT INTO tenants (shop_name, owner_email, subdomain)
VALUES ('Vinabike Santiago', 'admin@vinabike.cl', 'vinabike')
RETURNING id; -- Save this ID!
```

#### **Step 1.2: Add tenant_id to ALL tables**

**Core tables to update:**
```sql
-- Products
ALTER TABLE products ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Customers (ERP customers, not public store)
ALTER TABLE customers ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Sales
ALTER TABLE sales_invoices ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE sales_payments ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Inventory
ALTER TABLE stock_movements ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE categories ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Purchases
ALTER TABLE suppliers ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE purchase_invoices ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Accounting
ALTER TABLE accounts ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE journal_entries ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- HR
ALTER TABLE employees ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE attendances ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- Website/Store (if you want multi-store)
ALTER TABLE website_settings ADD COLUMN tenant_id UUID REFERENCES tenants(id);
ALTER TABLE online_orders ADD COLUMN tenant_id UUID REFERENCES tenants(id);
```

#### **Step 1.3: Migrate existing data to your tenant**

```sql
-- Get your tenant ID
SELECT id FROM tenants WHERE owner_email = 'admin@vinabike.cl';
-- Example result: 550e8400-e29b-41d4-a716-446655440000

-- Update ALL existing data with your tenant_id
UPDATE products SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE customers SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE sales_invoices SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE sales_payments SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE stock_movements SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE categories SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE suppliers SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE purchase_invoices SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE accounts SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE journal_entries SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE employees SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';
UPDATE attendances SET tenant_id = '550e8400-e29b-41d4-a716-446655440000';

-- Make tenant_id required (after data migration)
ALTER TABLE products ALTER COLUMN tenant_id SET NOT NULL;
ALTER TABLE customers ALTER COLUMN tenant_id SET NOT NULL;
-- Repeat for all tables
```

#### **Step 1.4: Update auth.users metadata**

```sql
-- Link your admin user to your tenant
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || 
  jsonb_build_object('tenant_id', '550e8400-e29b-41d4-a716-446655440000')
WHERE email = 'admin@vinabike.cl';
```

---

### **Phase 2: Row Level Security Policies (1 hour)**

#### **Step 2.1: Create RLS helper function**

```sql
CREATE OR REPLACE FUNCTION auth.user_tenant_id()
RETURNS UUID AS $$
  SELECT COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::uuid,
    NULL
  );
$$ LANGUAGE SQL STABLE;
```

#### **Step 2.2: Apply RLS to all tables**

**Template for each table:**
```sql
-- Example for products table
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Allow users to see only their tenant's data
CREATE POLICY "tenant_isolation_select" ON products
  FOR SELECT
  USING (tenant_id = auth.user_tenant_id());

CREATE POLICY "tenant_isolation_insert" ON products
  FOR INSERT
  WITH CHECK (tenant_id = auth.user_tenant_id());

CREATE POLICY "tenant_isolation_update" ON products
  FOR UPDATE
  USING (tenant_id = auth.user_tenant_id())
  WITH CHECK (tenant_id = auth.user_tenant_id());

CREATE POLICY "tenant_isolation_delete" ON products
  FOR DELETE
  USING (tenant_id = auth.user_tenant_id());
```

**Apply to all tables:**
- products
- customers
- sales_invoices
- sales_payments
- stock_movements
- categories
- suppliers
- purchase_invoices
- accounts
- journal_entries
- employees
- attendances
- website_settings
- online_orders

---

### **Phase 3: Flutter Code Updates (2-3 hours)**

#### **Step 3.1: Get tenant_id in Flutter**

```dart
// lib/shared/services/tenant_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantService {
  final _supabase = Supabase.instance.client;
  
  String? get currentTenantId {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    return user.userMetadata?['tenant_id'] as String?;
  }
  
  Future<Map<String, dynamic>?> getCurrentTenant() async {
    final tenantId = currentTenantId;
    if (tenantId == null) return null;
    
    final response = await _supabase
      .from('tenants')
      .select()
      .eq('id', tenantId)
      .single();
    
    return response;
  }
}
```

#### **Step 3.2: Update service inserts to include tenant_id**

**Example: InventoryService**

```dart
// BEFORE
Future<void> createProduct(Product product) async {
  await _supabase.from('products').insert(product.toJson());
}

// AFTER
Future<void> createProduct(Product product) async {
  final tenantId = _tenantService.currentTenantId;
  if (tenantId == null) throw Exception('No tenant found');
  
  final data = product.toJson();
  data['tenant_id'] = tenantId;
  
  await _supabase.from('products').insert(data);
}
```

**Update ALL services that create records:**
- InventoryService
- CustomerService
- SalesService
- PurchaseService
- AccountingService
- HRService

#### **Step 3.3: Add TenantService to providers**

```dart
// lib/main.dart
ChangeNotifierProvider(create: (_) => TenantService()),
```

---

### **Phase 4: Tenant Sign-Up Flow (2 hours)**

#### **Step 4.1: Create tenant registration page**

```dart
// lib/shared/pages/tenant_registration_page.dart
class TenantRegistrationPage extends StatefulWidget {
  // Form fields:
  // - Shop name
  // - Owner email
  // - Owner password
  // - Subdomain (optional)
  
  Future<void> _register() async {
    // 1. Sign up user
    final authResponse = await supabase.auth.signUp(
      email: email,
      password: password,
    );
    
    // 2. Create tenant
    final tenant = await supabase.from('tenants').insert({
      'shop_name': shopName,
      'owner_email': email,
      'subdomain': subdomain,
    }).select().single();
    
    // 3. Link user to tenant
    await supabase.auth.updateUser(
      UserAttributes(
        data: {'tenant_id': tenant['id']},
      ),
    );
    
    // 4. Create default data (optional)
    await _createDefaultAccounts(tenant['id']);
  }
}
```

#### **Step 4.2: Create employee invitation system**

```sql
-- Table for invitations
CREATE TABLE employee_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) NOT NULL,
  email TEXT NOT NULL,
  role TEXT NOT NULL,
  invited_by UUID REFERENCES auth.users(id),
  token TEXT UNIQUE NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  accepted_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

```dart
// Invite flow
Future<void> inviteEmployee(String email, String role) async {
  final tenantId = _tenantService.currentTenantId;
  
  await supabase.from('employee_invitations').insert({
    'tenant_id': tenantId,
    'email': email,
    'role': role,
    'token': generateToken(),
    'expires_at': DateTime.now().add(Duration(days: 7)),
  });
  
  // Send email with invitation link
}
```

---

### **Phase 5: Testing (1 hour)**

#### **Test Checklist:**

1. **Create second test tenant:**
   ```sql
   INSERT INTO tenants (shop_name, owner_email, subdomain)
   VALUES ('Test Shop', 'test@example.com', 'testshop');
   ```

2. **Sign up test user and link to test tenant**

3. **Verify isolation:**
   - Login as admin@vinabike.cl → See Vinabike products
   - Login as test@example.com → See ZERO products (blank state)
   - Create product as test user → Not visible to Vinabike

4. **Test all modules:**
   - Products
   - Sales
   - Purchases
   - Accounting
   - HR
   - Online orders

---

## 🎨 Storage Multi-Tenant

### **Organize storage by tenant_id:**

```dart
// Upload product image
Future<String> uploadProductImage(File file, String productId) async {
  final tenantId = _tenantService.currentTenantId;
  final path = '$tenantId/products/$productId.jpg';
  
  await supabase.storage
    .from('product-images')
    .upload(path, file);
  
  return supabase.storage
    .from('product-images')
    .getPublicUrl(path);
}
```

### **Storage RLS policy:**

```sql
CREATE POLICY "tenant_storage_isolation" ON storage.objects
  FOR ALL
  USING (
    (storage.foldername(name))[1] = auth.user_tenant_id()::text
  );
```

---

## 💰 Pricing Model (Future)

### **Tenant Plans:**

```sql
ALTER TABLE tenants ADD COLUMN plan TEXT DEFAULT 'free';

-- Free: 1 user, 50 products
-- Pro: Unlimited users, unlimited products ($50/month)
-- Enterprise: Multi-location, custom features ($200/month)
```

### **Enforce limits:**

```sql
-- Prevent free plan from exceeding limits
CREATE POLICY "free_plan_product_limit" ON products
  FOR INSERT
  WITH CHECK (
    CASE 
      WHEN (SELECT plan FROM tenants WHERE id = tenant_id) = 'free'
      THEN (SELECT COUNT(*) FROM products WHERE tenant_id = NEW.tenant_id) < 50
      ELSE true
    END
  );
```

---

## 📋 Migration Checklist

- [ ] Phase 1.1: Create tenants table
- [ ] Phase 1.2: Add tenant_id to all tables (20+ tables)
- [ ] Phase 1.3: Migrate existing data to your tenant
- [ ] Phase 1.4: Update auth.users metadata
- [ ] Phase 2.1: Create RLS helper function
- [ ] Phase 2.2: Apply RLS policies (all tables)
- [ ] Phase 3.1: Create TenantService
- [ ] Phase 3.2: Update all services to include tenant_id
- [ ] Phase 3.3: Add TenantService to providers
- [ ] Phase 4.1: Create tenant registration page
- [ ] Phase 4.2: Create employee invitation system
- [ ] Phase 5: Test tenant isolation thoroughly

---

## ⚡ Quick Start Commands

```sql
-- 1. Create tenants table (run in Supabase SQL Editor)
-- Copy from Phase 1.1

-- 2. Add tenant_id to products (example)
ALTER TABLE products ADD COLUMN tenant_id UUID REFERENCES tenants(id);

-- 3. Create your tenant
INSERT INTO tenants (shop_name, owner_email, subdomain)
VALUES ('Vinabike Santiago', 'admin@vinabike.cl', 'vinabike')
RETURNING id;

-- 4. Migrate existing products
UPDATE products SET tenant_id = '<your-tenant-id>';

-- 5. Link your user
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || 
  jsonb_build_object('tenant_id', '<your-tenant-id>')
WHERE email = 'admin@vinabike.cl';

-- 6. Enable RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- 7. Create policy
CREATE POLICY "tenant_isolation" ON products
  FOR ALL
  USING (tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::uuid);
```

---

## 🚨 Important Notes

1. **Backup database before migration!**
2. **Test on staging environment first**
3. **Update all 20+ tables, not just products**
4. **Every INSERT must include tenant_id**
5. **Public store customers vs ERP tenants are different concepts**

---

## 🆘 Troubleshooting

**Problem:** "User can't see any data after migration"
- Check: User has tenant_id in metadata?
- Check: Data has tenant_id column populated?
- Check: RLS policies exist on table?

**Problem:** "User sees data from other tenants"
- Check: RLS enabled on table?
- Check: Policy uses correct tenant_id check?

**Problem:** "Can't insert new records"
- Check: Service includes tenant_id in insert?
- Check: tenant_id matches user's metadata?

---

## 📞 Next Steps

1. Read this guide on Windows laptop
2. Present to AI agent there: "Implement multi-tenant architecture following MULTI_TENANT_GUIDE.md"
3. Start with Phase 1 (database schema)
4. Test thoroughly before production
5. Consider staging environment for testing

**Estimated total time: 6-8 hours**

Good luck! 🚀
