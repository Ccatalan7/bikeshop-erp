# 🏗️ Vinabike Architecture Explained

**A complete guide to understanding how your ERP + Public Store works**

---

## 📊 Current Architecture Overview

### **1. Single Codebase, Two Applications**

You have **ONE Flutter project** that serves **TWO different apps**:

```
lib/
├── modules/          ← ERP (admin, employees, internal use)
│   ├── accounting/
│   ├── inventory/
│   ├── sales/
│   ├── purchases/
│   ├── hr/
│   └── pos/
│
├── public_store/     ← Public website (customers, online shopping)
│   ├── pages/
│   ├── services/
│   └── widgets/
│
└── shared/           ← Code used by BOTH apps
    ├── models/
    ├── services/
    └── routes/
```

### **2. How It Detects Which App to Show**

**Magic happens in `lib/main.dart`:**

```dart
bool _detectPublicStoreHost() {
  final host = Uri.base.host.toLowerCase();
  return host == 'vinabike-store.web.app' ||    // Public store
         host == 'vinabike.cl' ||                // Your domain
         host == 'www.vinabike.cl';
}
```

**If URL is `vinabike-store.web.app`:**
- Shows ONLY public store routes (`/tienda/*`)
- No admin/ERP access
- Anyone can visit (no login required)

**If URL is `project-vinabike.web.app`:**
- Shows admin/ERP interface
- Requires employee login
- Full dashboard, inventory, accounting, etc.

---

## 🔐 Authentication: Two Different User Systems

### **Problem You Identified: "Things are getting mixed up"**

**You're RIGHT to be concerned!** Currently you have:

#### **ERP Users** (Admin/Employees)
- Managed by `AuthService` 
- Login at `/login`
- Stored in Supabase Auth as regular authenticated users
- Access ERP modules (inventory, accounting, POS, etc.)
- **RLS Policy:** `auth.role() = 'authenticated'`

#### **Customer Users** (Public Store)
- Managed by `CustomerAccountService`
- Login at `/tienda/auth`
- ALSO stored in Supabase Auth (same `auth.users` table!)
- Trigger creates record in `customers` table
- Access only public store
- **NO RLS policies yet!**

### **⚠️ The Confusion**

Both user types share the same `auth.users` table, but:
- ERP users get full database access via RLS
- Customers have no RLS policies defined yet
- **This is a security risk!**

---

## 🗄️ Database Architecture

### **Current Setup: One Supabase Project for Everything**

```
Supabase Project: xzdvtzdqjeyqxnkqprtf
│
├── auth.users               ← ALL users (employees + customers)
│   ├── Employee users       ← Have full RLS access
│   └── Customer users       ← No RLS policies yet!
│
├── customers                ← Customer profiles (linked to auth.users)
├── customer_addresses       ← Customer shipping addresses
├── online_orders            ← Public store orders
│
├── products                 ← Shared inventory
├── sales_invoices          ← ERP sales
├── journal_entries         ← Accounting
├── employees               ← HR data
└── ...                     ← All other ERP tables
```

### **Issues with Current Architecture:**

1. **Security Gap:** Customer users can potentially read ERP data (no RLS filtering by user type)
2. **No Isolation:** All data in one database
3. **Mixing Concerns:** Customer orders vs internal invoices in same DB
4. **Scaling:** If you sell this ERP to other bike shops, they'd see each other's data!

---

## 🚀 Firebase Hosting: How Two Sites Work

### **Your `.firebaserc` Configuration:**

```json
{
  "targets": {
    "project-vinabike": {
      "hosting": {
        "store": ["vinabike-store"],   ← Public store
        "erp": ["project-vinabike"]     ← Admin ERP
      }
    }
  }
}
```

### **Build Process:**

```bash
# Build ONCE
flutter build web --release

# Deploy to BOTH sites (same build!)
firebase deploy --only hosting:store    # → vinabike-store.web.app
firebase deploy --only hosting          # → project-vinabike.web.app
```

**Both sites serve the SAME compiled code**, but the app detects the URL and shows different interfaces!

---

## 🎯 Professional Recommendation: Multi-Tenant Architecture

### **Option 1: Keep Single Database (Current - Quick Fix)**

**Pros:**
- No migration needed
- Simple to maintain
- Works for single bike shop

**Cons:**
- Can't sell to multiple clients
- Security risks if not careful
- Customer data mixed with ERP data

**What to Fix:**
1. Add RLS policies to separate customer access from employee access
2. Add `user_type` column to distinguish employees from customers
3. Update all RLS policies to check user type

```sql
-- Example RLS fix
CREATE POLICY "Customers can only see their own orders"
ON online_orders
FOR SELECT
USING (
  auth.uid() IN (
    SELECT auth_user_id FROM customers WHERE id = online_orders.customer_id
  )
);

CREATE POLICY "Employees can see all orders"
ON online_orders
FOR SELECT
USING (
  auth.uid() IN (
    SELECT user_id FROM employees
  )
);
```

---

### **Option 2: Multi-Tenant Database (Recommended for SaaS)**

**If you want to sell this ERP to multiple bike shops:**

#### **Architecture:**

```
Supabase Project (xzdvtzdqjeyqxnkqprtf)
│
├── tenants                  ← Table of bike shops
│   ├── id: 1 → Vinabike
│   ├── id: 2 → Bike Shop LA
│   └── id: 3 → Bike Shop NYC
│
├── users (auth.users)       ← All employees + customers
│   ├── metadata.tenant_id = 1
│   ├── metadata.tenant_id = 2
│   └── ...
│
├── products                 ← Add tenant_id column
├── sales_invoices          ← Add tenant_id column
├── customers               ← Add tenant_id column
├── online_orders           ← Add tenant_id column
└── ...                     ← All tables get tenant_id
```

#### **RLS Policies for Multi-Tenant:**

```sql
-- Every table gets this policy
CREATE POLICY "Tenant isolation"
ON products
FOR ALL
USING (
  tenant_id = (auth.jwt() -> 'user_metadata' ->> 'tenant_id')::uuid
);
```

**Pros:**
- One Supabase project for ALL clients
- Each bike shop is isolated
- Easy to add new tenants
- Cost-effective

**Cons:**
- Need to migrate all data
- Add `tenant_id` to every table
- More complex queries

---

### **Option 3: Separate Supabase Project per Client (Enterprise)**

**Create new Supabase project for each bike shop:**

```
Supabase Project 1 (Vinabike)
├── customers
├── products
├── sales_invoices
└── ...

Supabase Project 2 (Bike Shop LA)
├── customers
├── products
├── sales_invoices
└── ...
```

**Pros:**
- Complete isolation
- Custom configuration per client
- No data mixing risks

**Cons:**
- Expensive ($25/month per project minimum)
- Complex deployment
- Hard to maintain updates across projects

---

## 💡 My Professional Recommendation

### **For Your Current Stage (Single Bike Shop):**

**Keep single database BUT:**

1. **Add user type distinction:**
```sql
ALTER TABLE customers ADD COLUMN auth_user_id UUID REFERENCES auth.users(id);
CREATE TABLE employees (
  id UUID PRIMARY KEY,
  auth_user_id UUID REFERENCES auth.users(id),
  role TEXT, -- 'admin', 'cashier', 'mechanic', etc.
  ...
);
```

2. **Fix RLS policies:**
   - Customers can ONLY access their own data
   - Employees can access ERP data
   - Separate online_orders from sales_invoices

3. **Add to Supabase Auth metadata:**
```dart
await supabase.auth.signUp(
  email: email,
  password: password,
  data: {
    'user_type': 'customer',  // or 'employee'
  },
);
```

4. **Update RLS to check user_type:**
```sql
CREATE POLICY "Employees only"
ON sales_invoices
USING (
  (auth.jwt() -> 'user_metadata' ->> 'user_type') = 'employee'
);
```

---

### **For Future SaaS (Multiple Bike Shops):**

**Go with Option 2 (Multi-Tenant):**

1. Create `tenants` table
2. Add `tenant_id` to all tables
3. Update RLS policies
4. Sign up flow:
   - New shop owner creates account
   - System creates new tenant
   - Owner becomes admin of that tenant
   - Owner invites employees

**Pricing Model:**
- Free tier: 1 employee, 100 products
- Pro tier: Unlimited employees, products ($50/month)
- Enterprise: Multiple locations ($200/month)

**All using ONE Supabase project!**

---

## 🎨 Frontend Separation

### **Current: Smart Routing**

```dart
// lib/shared/routes/app_router.dart
if (forcePublicStoreHost) {
  // Only allow /tienda/* routes
  if (!isPublicRoute) return '/tienda';
}

if (isPublicRoute) {
  // No auth required for /tienda/*
  return null;
}

// ERP routes require authentication
if (!isLoggedIn) return '/login';
```

### **Better: Separate Entry Points (Optional)**

**Create two different main files:**

```
lib/
├── main_erp.dart        ← ERP app
├── main_store.dart      ← Public store
└── shared/             ← Common code
```

**Build separately:**
```bash
# ERP build
flutter build web --target lib/main_erp.dart

# Store build  
flutter build web --target lib/main_store.dart
```

**Pros:**
- Smaller bundle sizes
- Clear separation
- Different themes/configs

**Cons:**
- More complex build process
- Duplicate some code

---

## 📋 Action Plan for You

### **Immediate (This Week):**

1. ✅ **Fix email verification** (disable temporarily for testing)
2. 🔒 **Add RLS policies for customers**
3. 📝 **Add user_type to auth metadata**
4. 🧪 **Test that customers can't access ERP data**

### **Short Term (This Month):**

5. 🏗️ **Create proper employee management**
6. 👥 **Migrate any admin users to employees table**
7. 🔐 **Add role-based permissions (admin, cashier, etc.)**
8. 📊 **Separate online_orders from sales_invoices logic**

### **Long Term (If Going SaaS):**

9. 🏢 **Implement multi-tenant architecture**
10. 💳 **Add subscription/billing logic**
11. 📦 **Tenant onboarding flow**
12. 🎨 **White-label capabilities**

---

## 🤔 FAQ

### **Q: Should the website be a separate project?**
**A:** Not necessarily. Your current approach works, but you need better data isolation via RLS policies.

### **Q: Should I use separate Supabase projects?**
**A:** Only if selling to multiple clients. For one shop, use one project with proper RLS.

### **Q: How do different builds work?**
**A:** Same build deployed to two Firebase Hosting sites. The app detects the URL and shows different UI.

### **Q: What about storage/buckets?**
**A:** You should create separate buckets:
- `erp-documents` (employee-only access)
- `product-images` (public read)
- `customer-uploads` (customer-only access)

### **Q: Each new ERP user gets their own Supabase project?**
**A:** NO! Use multi-tenant (one project, many clients with `tenant_id` filtering).

---

## 🎯 Next Steps

**Tell me which path you want:**

1. **Path A: Fix current setup** (quick, works for one shop)
   - I'll write the RLS policies
   - Add user type distinction
   - Secure customer access

2. **Path B: Prepare for SaaS** (longer, supports multiple shops)
   - Design multi-tenant schema
   - Migration plan
   - Tenant onboarding flow

3. **Path C: Separate the apps** (cleanest, more work)
   - Split into two Flutter projects
   - Separate databases
   - Different deployment pipelines

**Which sounds right for your goals?**
