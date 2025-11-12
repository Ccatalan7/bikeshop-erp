# 📐 SYSTEM ARCHITECTURE

**Visual guide to the import/sync system**

---

## 🌐 Multi-Platform Integration Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BIKESHOP ERP ECOSYSTEM                          │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│              │         │              │         │              │
│    ZOHO      │         │     ODOO     │         │   FLUTTER    │
│  Inventory   │         │     ERP      │         │     APP      │
│              │         │              │         │              │
│  • Products  │         │  • Products  │         │  • Supabase  │
│  • Stock     │         │  • Categories│         │  • Products  │
│  • Prices    │         │  • Structure │         │  • Categories│
│  • Images    │         │  • Hierarchy │         │  • Multi-    │
│              │         │              │         │    tenant    │
└──────┬───────┘         └──────┬───────┘         └──────┬───────┘
       │                        │                        │
       │                        │                        │
       │                        │                        │
       └────────────┬───────────┴────────────┬───────────┘
                    │                        │
                    ▼                        ▼
            ┌───────────────┐       ┌───────────────┐
            │  sync_zoho_   │       │  sync_odoo_   │
            │  to_flutter   │       │  to_flutter   │
            └───────┬───────┘       └───────┬───────┘
                    │                       │
                    └───────────┬───────────┘
                                │
                                ▼
                        ┌───────────────┐
                        │  sync_zoho_   │
                        │     odoo      │
                        │  (compare)    │
                        └───────────────┘
```

---

## 🔄 Data Flow: Odoo → Flutter

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: FETCH CATEGORIES FROM ODOO                              │
└─────────────────────────────────────────────────────────────────┘

    Odoo product.category API
           │
           ├─ complete_name: "Accesorios / Asientos / Tija"
           ├─ parent_id: reference to parent category
           ├─ name: "Tija"
           └─ id: 42
           
           ▼ Parse hierarchy
           
    Split by ' / ' separator
           │
           ├─ Level 0: "Accesorios" (root)
           ├─ Level 1: "Asientos" (child)
           └─ Level 2: "Tija" (grandchild)

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: CREATE IN SUPABASE                                      │
└─────────────────────────────────────────────────────────────────┘

    INSERT INTO product_categories
           │
           ├─ name: "Tija"
           ├─ full_path: "Accesorios / Asientos / Tija"
           ├─ parent_id: UUID of "Asientos"
           ├─ level: 2
           └─ tenant_id: YOUR_TENANT_ID

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: MATCH PRODUCTS                                          │
└─────────────────────────────────────────────────────────────────┘

    Fetch products from both systems
           │
           ├─ Odoo: default_code = "ABC123"
           └─ Supabase: sku = "ABC123"
           
           ▼ Match by SKU
           
    UPDATE products SET category_id = (category UUID)
    WHERE sku = "ABC123"
```

---

## 🔄 Data Flow: Zoho → Flutter

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: AUTHENTICATE WITH ZOHO                                  │
└─────────────────────────────────────────────────────────────────┘

    POST oauth/v2/token
    {
      refresh_token: YOUR_REFRESH_TOKEN,
      client_id: YOUR_CLIENT_ID,
      client_secret: YOUR_CLIENT_SECRET
    }
           │
           ▼
    access_token (valid 1 hour)

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: FETCH ITEMS FROM ZOHO                                   │
└─────────────────────────────────────────────────────────────────┘

    GET /inventory/v1/items?page=1&per_page=200
    Authorization: Zoho-oauthtoken {access_token}
           │
           ├─ item_name: "Neumático 26x2.1"
           ├─ sku: "NEU-26-2.1"
           ├─ rate: "15.990,00" (Chilean format!)
           ├─ purchase_rate: "10.500,00"
           └─ stock_on_hand: "25"

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: TRANSFORM DATA                                          │
└─────────────────────────────────────────────────────────────────┘

    parse_chilean_number("15.990,00")
           │
           ├─ Remove dots: "15990,00"
           ├─ Replace comma: "15990.00"
           └─ Convert to float: 15990.0
           
    Map fields:
           │
           ├─ item_name → name
           ├─ sku → sku
           ├─ rate → price
           ├─ purchase_rate → cost
           └─ stock_on_hand → stock_quantity

┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: UPSERT TO SUPABASE                                      │
└─────────────────────────────────────────────────────────────────┘

    Check if SKU exists
           │
           ├─ EXISTS: UPDATE products SET ...
           └─ NOT EXISTS: INSERT INTO products ...
```

---

## 🔄 Data Flow: Zoho ↔ Odoo

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: FETCH FROM BOTH SYSTEMS                                 │
└─────────────────────────────────────────────────────────────────┘

    ┌─ Zoho Items ─┐        ┌─ Odoo Products ─┐
    │ SKU: ABC     │        │ SKU: ABC        │
    │ SKU: DEF     │        │ SKU: GHI        │
    │ SKU: JKL     │        │ SKU: JKL        │
    └──────────────┘        └─────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: COMPARE BY SKU                                          │
└─────────────────────────────────────────────────────────────────┘

    in_both:     [ABC, JKL]   ← Common products
    only_zoho:   [DEF]         ← Missing in Odoo
    only_odoo:   [GHI]         ← Missing in Zoho

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: DETECT DIFFERENCES                                      │
└─────────────────────────────────────────────────────────────────┘

    For products in both:
           │
           ├─ Compare names
           ├─ Compare prices (allow 1% variance)
           └─ Compare stock quantities
           
    Result: List of differences

┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: USER CHOOSES SYNC DIRECTION                             │
└─────────────────────────────────────────────────────────────────┘

    1. Create missing in Odoo ← from Zoho
    2. Create missing in Zoho ← from Odoo
    3. Both directions
    4. Skip (comparison only)
```

---

## 🏗️ Category Hierarchy Structure

```
Supabase: product_categories table

┌──────────────────────────────────────────────────────────────┐
│ id (UUID) │ name        │ parent_id │ level │ full_path      │
├──────────────────────────────────────────────────────────────┤
│ uuid-1    │ Accesorios  │ null      │ 0     │ Accesorios     │
│ uuid-2    │ Asientos    │ uuid-1    │ 1     │ Accesorios/... │
│ uuid-3    │ Tija        │ uuid-2    │ 2     │ Accesorios/... │
└──────────────────────────────────────────────────────────────┘

Visual representation:

Accesorios (uuid-1)
└── Asientos (uuid-2)
    └── Tija (uuid-3)

Flutter UI:
┌─────────────────────┐
│ 📁 Accesorios       │
│   📁 Asientos       │
│     📄 Tija         │
│   📁 Adaptadores    │
│   📁 Bombines       │
└─────────────────────┘
```

---

## 🔐 Authentication Flow

### Odoo XML-RPC
```
┌──────────────────────────────────────────┐
│ 1. Authenticate                           │
│    common.authenticate(                   │
│      database, username, api_key, {}      │
│    )                                      │
│    → Returns: uid (user ID)               │
└────────────────┬──────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────┐
│ 2. Execute Methods                        │
│    models.execute_kw(                     │
│      database, uid, api_key,              │
│      'product.product', 'search_read',    │
│      [[filters]], {fields: [...]}         │
│    )                                      │
│    → Returns: List of records             │
└───────────────────────────────────────────┘
```

### Zoho OAuth 2.0
```
┌──────────────────────────────────────────┐
│ 1. Get Access Token (from refresh token) │
│    POST /oauth/v2/token                   │
│    {                                      │
│      refresh_token,                       │
│      client_id,                           │
│      client_secret                        │
│    }                                      │
│    → Returns: access_token (1h valid)     │
└────────────────┬──────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────┐
│ 2. API Requests                           │
│    GET /inventory/v1/items                │
│    Authorization: Zoho-oauthtoken TOKEN   │
│    → Returns: List of items               │
└───────────────────────────────────────────┘
```

### Supabase Service Role
```
┌──────────────────────────────────────────┐
│ Direct API Access (no auth flow)         │
│    from supabase import create_client     │
│    client = create_client(url, key)       │
│                                           │
│    client.table('products')               │
│          .select('*')                     │
│          .eq('tenant_id', TENANT_ID)      │
│          .execute()                       │
│    → Returns: List of products            │
└───────────────────────────────────────────┘

⚠️ Service Role Key bypasses Row Level Security!
   Always filter by tenant_id manually!
```

---

## 🔄 Error Handling Flow

```
┌──────────────────────────────────────────┐
│ Start Sync                                │
└────────────────┬──────────────────────────┘
                 │
                 ▼
        ┌─────────────────┐
        │ Validate Config │
        └────────┬─────────┘
                 │
        ┌────────▼─────────┐
        │ All fields OK?   │
        └────────┬─────────┘
                 │
          ┌──────┴──────┐
          │             │
         YES           NO
          │             │
          │             ▼
          │    ┌────────────────┐
          │    │ Show errors    │
          │    │ Exit with code │
          │    └────────────────┘
          │
          ▼
┌──────────────────────────────────────────┐
│ Connect to APIs                           │
└────────────────┬──────────────────────────┘
                 │
        ┌────────▼─────────┐
        │ Connection OK?   │
        └────────┬─────────┘
                 │
          ┌──────┴──────┐
          │             │
         YES           NO
          │             │
          │             ▼
          │    ┌────────────────┐
          │    │ Retry 3 times  │
          │    │ Then fail      │
          │    └────────────────┘
          │
          ▼
┌──────────────────────────────────────────┐
│ Process Items (with try/catch per item)  │
└────────────────┬──────────────────────────┘
                 │
        ┌────────▼─────────┐
        │ Item processed?  │
        └────────┬─────────┘
                 │
          ┌──────┴──────┐
          │             │
         YES           NO
          │             │
          │             ▼
          │    ┌────────────────┐
          │    │ Log error      │
          │    │ Continue next  │
          │    └────────────────┘
          │
          ▼
┌──────────────────────────────────────────┐
│ Summary Report                            │
│ • Inserted: X                             │
│ • Updated: Y                              │
│ • Errors: Z                               │
└───────────────────────────────────────────┘
```

---

## 📊 Data Transformation Pipeline

### Chilean Number Format
```
Input:  "1.500,00" (Chilean format)
  │
  ├─ Step 1: Remove dots     → "1500,00"
  ├─ Step 2: Replace comma   → "1500.00"
  └─ Step 3: Convert to float → 1500.0

Output: 1500.0 (standard float)
```

### Category Path Parsing
```
Input:  "Componentes / Frenos / Pastillas"
  │
  ├─ Split by ' / '
  │
  ├─ Part 1: "Componentes"    (level 0, no parent)
  ├─ Part 2: "Frenos"         (level 1, parent=Componentes)
  └─ Part 3: "Pastillas"      (level 2, parent=Frenos)

Output: 3 category records with parent-child links
```

### Field Mapping (Zoho → Supabase)
```
Zoho Field          →  Supabase Field
─────────────────────────────────────────
item_name           →  name
sku                 →  sku
rate                →  price
purchase_rate       →  cost
stock_on_hand       →  stock_quantity
stock_on_hand       →  inventory_qty
description         →  description
brand               →  brand
upc                 →  barcode
status='active'     →  is_active=true
created_time        →  created_at
```

---

## 🎯 Multi-Tenant Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        SUPABASE                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Tenants Table                                        │   │
│  │ ┌─────────────┬──────────────────┬──────────────┐  │   │
│  │ │ id          │ shop_name        │ subdomain    │  │   │
│  │ ├─────────────┼──────────────────┼──────────────┤  │   │
│  │ │ uuid-vinabike│ Vinabike        │ vinabike     │  │   │
│  │ │ uuid-testbike│ TestBike        │ testbike     │  │   │
│  │ └─────────────┴──────────────────┴──────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Products Table                                       │   │
│  │ ┌─────────┬──────────────┬──────────┬─────────────┐ │   │
│  │ │ id      │ tenant_id    │ sku      │ name        │ │   │
│  │ ├─────────┼──────────────┼──────────┼─────────────┤ │   │
│  │ │ prod-1  │ uuid-vinabike│ ABC123   │ Product A   │ │   │
│  │ │ prod-2  │ uuid-vinabike│ DEF456   │ Product B   │ │   │
│  │ │ prod-3  │ uuid-testbike│ ABC123   │ Product A   │ │   │
│  │ └─────────┴──────────────┴──────────┴─────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

CRITICAL: Every query MUST filter by tenant_id!

✅ Correct:
   SELECT * FROM products WHERE tenant_id = 'uuid-vinabike';

❌ Wrong:
   SELECT * FROM products;  ← Returns all tenants!
```

---

## 🔍 Monitoring & Logging

```
Script Output:
┌────────────────────────────────────────┐
│ 🔄 ODOO → FLUTTER SYNC                 │
│ ════════════════════════════════════   │
│                                        │
│ 1️⃣ Connecting to Supabase...          │
│    ✅ Connected (1440 products)        │
│                                        │
│ 2️⃣ Fetching categories from Odoo...   │
│    ✅ Found 144 categories             │
│                                        │
│ 3️⃣ Creating hierarchy...              │
│    ➕ Created: Accesorios (level 0)   │
│    ➕ Created: Accesorios/Asientos     │
│    ...                                 │
│                                        │
│ 4️⃣ Updating products...               │
│    Progress: 500/1440                  │
│    Progress: 1000/1440                 │
│    ✅ Updated: 1191 products           │
│                                        │
│ ✅ SYNC COMPLETE!                      │
│ ════════════════════════════════════   │
│ Categories: 144                        │
│ Products: 1191/1440                    │
└────────────────────────────────────────┘
```

---

**Need more diagrams? Let me know what to visualize!**
