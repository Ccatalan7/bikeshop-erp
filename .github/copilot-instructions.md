# 🧠 Project Overview

This is a **MULTI-TENANT SaaS ERP** for managing bikeshops. Multiple independent businesses use the same app with **COMPLETE DATA ISOLATION**. It includes accounting, inventory, POS, customer management, maintenance tracking, HR, website builder, marketing, and analytics. Built in **Flutter/Dart**, targeting **Windows, Android, Web**, and optionally macOS/iOS.

The backend uses Supabase exclusively, with PostgreSQL as the relational database, Supabase Auth for authentication (including OAuth2 support like Google login), and Supabase Storage for file management. All business logic follows an accounting-first approach, with audit-ready data structures and strong relational integrity across modules.

---

# 🚨 CRITICAL: MULTI-TENANT ARCHITECTURE

**THIS IS A MULTI-TENANT SaaS APPLICATION - EVERY TABLE MUST HAVE `tenant_id`**

## Core Principle
- **EVERY** piece of data belongs to ONE tenant
- **EVERY** table (except auth/system tables) MUST have `tenant_id uuid references tenants(id) on delete cascade not null`
- **EVERY** query MUST filter by `tenant_id`
- **EVERY** insert MUST include `tenant_id`
- **NO EXCEPTIONS** - this is for subscription-based SaaS offering

## When Creating ANY Table
```sql
create table table_name (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null, -- ⚠️ MANDATORY
  -- other columns...
);

create index idx_table_name_tenant on table_name(tenant_id); -- ⚠️ MANDATORY
```

## When Creating Unique Constraints
```sql
unique(tenant_id, name)  -- ✅ Correct: per-tenant unique
unique(name)             -- ❌ Wrong: global unique = shared data
```

## Row Level Security (RLS)
- **EVERY** tenant-data table MUST have RLS enabled
- **EVERY** operation (SELECT, INSERT, UPDATE, DELETE) MUST filter by `tenant_id = user_tenant_id()`
- Use `public.user_tenant_id()` helper function to get current user's tenant

## Tables That DON'T Need tenant_id
- `auth.users` (Supabase auth system table)
- `tenants` (the tenant registry itself)
- Pure lookup/enum tables that are truly global (rare, verify first)

## Before Creating ANY Feature
1. ✅ Does the table have `tenant_id`? 
2. ✅ Does the index include `tenant_id`?
3. ✅ Are unique constraints scoped to `tenant_id`?
4. ✅ Does RLS filter by `tenant_id`?
5. ✅ Does the Flutter service filter by `tenant_id`?

**If ANY answer is NO → STOP and fix it first**

## Multi-Tenant Migration Status: ✅ COMPLETE

**Production Status:** As of October 25, 2025, the multi-tenant migration is **COMPLETE and VERIFIED**.

**Final Metrics:**
- 69 total tables (1 system table: `tenants`)
- 68 business tables with `tenant_id` column
- 194 RLS policies (100% tenant-filtered)
- 0 dangerous policies (zero cross-tenant leakage risk)
- 0 tables without policies
- **Verification Test:** `FINAL_MULTI_TENANT_VERIFICATION.sql` (12-test comprehensive suite)

**Key Achievements:**
- ✅ Complete data isolation per tenant
- ✅ All RLS policies use `tenant_id = public.user_tenant_id()`
- ✅ Zero NULL `tenant_id` values in production data
- ✅ All tables indexed on `tenant_id`
- ✅ All unique constraints scoped to `tenant_id`
- ✅ Enterprise-grade security architecture

**Reference Documents:**
- `MULTI_TENANT_MIGRATION_COMPLETE.md` - Full migration report
- `FINAL_MULTI_TENANT_VERIFICATION.sql` - Comprehensive verification test
- `CORE_SCHEMA_SYNC_COMPLETE.md` - Schema synchronization report

**When Adding New Tables:**
1. ✅ Add `tenant_id uuid references tenants(id) on delete cascade not null`
2. ✅ Create index: `create index idx_{table}_tenant on {table}(tenant_id);`
3. ✅ Enable RLS: `alter table {table} enable row level security;`
4. ✅ Add 4 policies (SELECT, INSERT, UPDATE, DELETE) all filtering by `tenant_id = user_tenant_id()`
5. ✅ Add policy block to `core_schema.sql` following existing pattern (lines 9400-10114)
6. ✅ Run `FINAL_MULTI_TENANT_VERIFICATION.sql` to verify

---

# 🚨 CRITICAL RULE: DATABASE SCHEMA FILES

**⚠️ SCHEMA IS SPLIT INTO 3 FILES FOR DEPLOYMENT!**

**The database schema exists in TWO forms:**

1. **`supabase/sql/core_schema.sql`** (MASTER FILE - 9630 lines)
   - ✅ **EDIT THIS FILE** when making schema changes
   - ✅ This is the SINGLE SOURCE OF TRUTH
   - ✅ All changes go here FIRST

2. **Split files for deployment** (generated from master):
   - `supabase/sql/1_core_tables.sql` (Tables + seed data)
   - `supabase/sql/2_business_logic.sql` (Functions + triggers)
   - `supabase/sql/3_analytics_views.sql` (Dashboard RPCs + views)
   - ⚠️ These are GENERATED from `core_schema.sql` - don't edit directly!

**When making database changes:**
- ✅ Edit `core_schema.sql` (master file)
- ✅ After editing, tell user: "Deploy the updated `supabase/sql/core_schema.sql` OR regenerate the 3-file split"
- ✅ Be EXPLICIT: "I modified `core_schema.sql` at line X" or "I updated function Y in `core_schema.sql`"
- ❌ NEVER create new SQL files (`FIX_*.sql`, `DEPLOY_*.sql`, etc.)

**⚠️ CRITICAL: AVOID DUPLICATES!**

**BEFORE creating ANY database object, you MUST:**
1. 🔍 **READ `core_schema.sql` first** - check the ENTIRE file if needed
2. 🔍 **SEARCH for existing similar functions/triggers/tables** using grep or semantic search
3. ❌ **NEVER assume a function/trigger doesn't exist** - ALWAYS verify first
4. 🔄 **UPDATE existing functions** rather than creating new ones with different names
5. 📝 **BE EXPLICIT:** Always tell user "I modified `core_schema.sql` at line X" or "I updated function Y in `core_schema.sql`"
6. ⚠️ **Example of what NOT to do:**
   - ❌ Creating `handle_purchase_invoice_change()` when `handle_sales_invoice_change()` pattern already exists
   - ❌ Creating `create_purchase_journal_entry()` when similar function already exists
   - ❌ Creating new triggers without checking for existing trigger patterns
7. ✅ **Example of what TO do:**
   - ✅ Find existing `handle_sales_invoice_change()` function
   - ✅ Check how it works and what pattern it uses
   - ✅ Create `handle_purchase_invoice_change()` following the SAME pattern
   - ✅ Reuse existing helper functions like `ensure_account()`, `consume_inventory()`, etc.
   - ✅ Tell user: "I added `handle_purchase_invoice_change()` to `core_schema.sql` at line 4850, following the same pattern as `handle_sales_invoice_change()`"

**Common mistakes to AVOID:**
- ❌ Creating duplicate functions with slightly different names
- ❌ Creating new helper functions when similar ones exist
- ❌ Not checking existing trigger patterns before creating new ones
- ❌ Assuming tables/columns don't exist without checking
- ❌ Creating inconsistent naming (one module uses `handle_*_change`, another uses `process_*_update`)

**Before making any database changes:**
1. 🔍 **ALWAYS check `core_schema.sql` first**
2. 🔍 **SEARCH for existing functions/triggers with similar names or purposes**
3. 📖 Read the relevant section (tables, functions, triggers)
4. 🤔 **Ask: "Does something similar already exist?"**
5. ✏️ Make changes directly in `core_schema.sql`
6. 💾 Save and inform user: "Deploy the updated `core_schema.sql` to Supabase"
7. 📝 **BE EXPLICIT:** Tell user which file and line number you modified

**This is the ONLY database schema file to edit. The 3-file split is for deployment only.**

---

# 🔧 COPILOT WORKFLOW CHECKLIST

**For ANY database-related task:**

1. ✅ **READ** `supabase/sql/core_schema.sql` first - ENTIRE file if needed
2. ✅ **SEARCH** for existing tables/functions/triggers with similar names or purposes
3. ✅ **CHECK** if similar patterns already exist (e.g., `handle_sales_invoice_change` → use same pattern for purchases)
4. ✅ **REUSE** existing helper functions (`ensure_account`, `consume_inventory`, etc.)
5. ✅ **UPDATE** existing code or add new code following EXISTING patterns
6. ✅ **NEVER** create duplicate functions/triggers with different names
7. ✅ **VERIFY** column names match what's in `core_schema.sql`
8. ✅ **INFORM** user: "I modified `core_schema.sql` at line X" or "I added function Y to `core_schema.sql`"
9. ✅ **TELL USER:** "Deploy the updated `core_schema.sql` to Supabase"

**CRITICAL: Before creating ANY function/trigger:**
- 🔍 Search `core_schema.sql` for: `CREATE OR REPLACE FUNCTION public.[function_name]`
- 🔍 Search for similar patterns (e.g., if creating purchase trigger, look for sales trigger)
- 🔍 Check what helper functions exist (ensure_account, consume_inventory, etc.)
- ❌ NEVER create `create_purchase_invoice_journal_entry` if `create_sales_invoice_journal_entry` already exists - study the existing one first!
- 📝 **BE EXPLICIT:** Tell user "I added `create_purchase_invoice_journal_entry()` to `core_schema.sql` at line 4680"

**For ANY Flutter code changes:**

1. ✅ Check if database schema needs updating first
2. ✅ **READ `core_schema.sql`** to verify table/column names
3. ✅ Adapt Flutter code to match database schema (not vice versa)
4. ✅ Use correct column names from `core_schema.sql`
5. ✅ Test compilation before marking complete

**For ANY new feature:**

1. ✅ **Database schema first (in `core_schema.sql`)**
   - ⚠️ **MUST have `tenant_id` column** (except auth/system tables)
   - ⚠️ **MUST have index on `tenant_id`**
   - ⚠️ **MUST have RLS policies filtering by `tenant_id`**
   - Check what tables/functions/triggers already exist
   - Follow existing patterns and naming conventions
   - Reuse existing helper functions
2. ✅ Backend triggers/functions (in `core_schema.sql`)
   - ⚠️ **MUST filter by `tenant_id` in WHERE clauses**
   - Search for similar triggers/functions first
   - Use same pattern as existing code
3. ✅ Flutter models and services
   - ⚠️ **MUST include `tenant_id` in queries**
   - ⚠️ **MUST get `tenant_id` from auth context**
4. ✅ UI implementation
5. ✅ Navigation integration (add to main menu)

**REMEMBER:**
- 🚫 No new SQL files
- 🚫 No duplicate functions/triggers (search first!)
- 🚫 No markdown guides for simple tasks
- 🚫 No assumptions about schema - always check first
- 🚫 No creating new patterns when existing patterns work
- 🚫 **NO TABLES WITHOUT `tenant_id`** (except auth/system)
- 🚫 **NO GLOBAL UNIQUE CONSTRAINTS** (must be per-tenant)
- 🚫 **NO QUERIES WITHOUT `tenant_id` FILTER**
- ✅ Always search for existing similar code
- ✅ Always follow existing naming conventions
- ✅ Always reuse existing helper functions
- ✅ Always verify changes compile before finishing
- ✅ **ALWAYS add `tenant_id` to new tables**
- ✅ **ALWAYS create RLS policies for tenant isolation**
- ✅ **ALWAYS test with multiple tenants to verify isolation**

---

# 🧱 Modular Architecture

Each module is independent but shares a unified data layer. Modules include:

- **Sales**: Invoices, payments, discounts
- **Purchases**: Purchase orders, supplier credits, receipts
- **Inventory**: Products, stock movements, warehouses
- **Maintenance**: Work orders, parts used, labor cost
- **CRM**: Customer profiles, bike history, loyalty
- **Accounting**: Chart of accounts, journal entries, tax rules
- **HR (RRHH)**: Employees, contracts, attendance, payroll, planning
- **Website Builder**: Product catalog, online orders, CMS
- **Marketing**: Campaigns, email/SMS, customer segmentation
- **Analytics**: Dashboards, KPIs, sales trends, inventory turnover
- **Settings**: Company info, currency, theme, language, timezone

---

# 🔗 Integration Logic

- Online orders from Website Builder deduct inventory and generate invoices
- Marketing campaigns use CRM data and feed into Analytics
- POS, Website, and Maintenance all sync with Inventory and Accounting
- HR data (attendance, payroll) flows into Accounting
- Analytics pulls from all modules for unified dashboards

---

# 🧮 Database Schema (PostgreSQL)

Use normalized tables with foreign keys and constraints. Example:

`sql
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name TEXT,
  sku TEXT UNIQUE,
  price NUMERIC,
  cost NUMERIC,
  inventory_qty INTEGER
);

CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER REFERENCES customers(id),
  source TEXT CHECK (source IN ('POS', 'Website')),
  date TIMESTAMP,
  total NUMERIC
);

CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER REFERENCES orders(id),
  product_id INTEGER REFERENCES products(id),
  quantity INTEGER,
  price NUMERIC
);
`

Use triggers or service logic to update inventory and accounting entries.

---

# 🔐 Authentication

Use Supabase Auth with OAuth2 (Google, GitHub, etc.) for secure login. Supports:

- Email/password
- Social login
- Role-based access control via Row Level Security (RLS)
- Token expiration and automatic refresh
- Seamless integration with PostgreSQL user tables

---

# 🧭 Navigation Design Rules

- Use minimalistic menu structure with one entry per module
- Avoid redundant submenus like “New Purchase Invoice”
- Use in-page navigation for actions (e.g., “+ New Invoice” button)
- Maintain consistent drawer/sidebar layout across all modules
- Use local routing (Navigator.push, GoRouter) for transitions
- Role-based menu visibility (admin, cashier, mechanic, accountant)

---

## 🔗 Module Integration Rules
- Every new module must:
  - Be imported into `main.dart` (or the central navigation file).
  - Add its main ListPage (e.g., CustomerListPage, InventoryListPage) to the sidebar/drawer.
  - Add a dashboard shortcut if relevant (e.g., “Clientes”, “Inventario”).
  - Ensure navigation works end-to-end: Dashboard → Module → Detail/Form pages.
- No module is considered “done” until it is visible and accessible from the main navigation.


---

# 🎨 GUI Design System

Use a unified widget set across all screens:

- Buttons: consistent style (primary, secondary, danger)
- Forms: reusable components with validation
- Lists: paginated, searchable, filterable
- Modals: consistent layout and behavior
- Icons: use Material Icons or custom SVGs

Support:

- Dark mode toggle (global)
- Language selector (i18n)
- Time zone sync (auto-detect or manual)

---

# 🌍 Localization & Regional Context

App is primarily used in Chile

- Currency: CLP (Chilean Peso)
- Tax: IVA (19%), applied to invoices and purchases
- Language: Spanish (default), English (optional)
- Date format: DD/MM/YYYY
- Time zone: America/Santiago

---

# 👥 HR & Workforce Management (RRHH)

Include the following modules:

- Employees: personal data, job title, department
- Contracts: salary, working hours, legal terms
- Attendance: clock-in/out, calendar view, kiosk mode
- Payroll: salary computation, tax, payment status
- Planning: shift scheduling, technician availability
- Leaves: vacation, sick leave, approval workflows
- Timesheets: logged hours per task/project
- Roles & Permissions: access control per module

---

# 🌐 Website Builder

**CRITICAL: Multi-Tenant Website Deployment**

Each tenant can have their own e-commerce website with a unique Firebase subdomain (e.g., `bikeshop1.web.app`).

## Website Architecture

**Deployment Model:** Single Firebase Project, Multiple Hosting Sites
- One Firebase project hosts up to 36 tenant websites
- Each tenant gets unique subdomain: `{tenant-subdomain}.web.app`
- Same Flutter codebase serves all tenants (data filtered by `tenant_id`)
- **Cost:** FREE (Firebase Hosting free tier)

## Database Schema for Website Configuration

The `company_settings` table includes website deployment columns:

```sql
-- Website configuration columns (already in core_schema.sql)
website_enabled boolean default false
website_subdomain text unique  -- e.g., "bikeshop-santiago"
website_url text  -- e.g., "https://bikeshop-santiago.web.app"
firebase_site_name text  -- Firebase Hosting site name
website_deployed_at timestamptz  -- Last deployment timestamp
website_status text  -- not_configured, pending, deployed, error
```

## Tenant Website Workflow

### For Tenants (Shop Owners):
1. Login to ERP → Settings → Website Setup
2. Enter shop name (e.g., "Bike Shop Santiago")
3. Subdomain auto-generates (e.g., "bike-shop-santiago")
4. Click "Create My Website"
5. Status changes to "pending"
6. Wait for deployment (admin runs script)
7. Receive notification when live
8. Manage content via Website module

### For Admin (Deployment):
1. Receive website request notification
2. Run deployment script: `.\scripts\deploy_tenant_website.ps1 -TenantId "UUID"`
3. Script automatically:
   - Creates Firebase Hosting site
   - Builds Flutter web app
   - Deploys to `{subdomain}.web.app`
   - Updates database with URL and status
4. Tenant receives notification

## Deployment Scripts

**PowerShell (Windows):**
```powershell
# Set environment variables
$env:SUPABASE_URL = "https://your-project.supabase.co"
$env:SUPABASE_SERVICE_KEY = "your-service-role-key"

# Deploy tenant website
.\scripts\deploy_tenant_website.ps1 -TenantId "UUID"
```

**Node.js (Cross-platform):**
```bash
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_SERVICE_KEY="your-service-role-key"

node scripts/deploy_tenant_website.js UUID
```

## URL-Based Tenant Detection

The app detects which tenant's website is being accessed:

```dart
// In main.dart
Future<void> main() async {
  String? tenantSubdomain;
  if (kIsWeb) {
    final hostname = Uri.base.host; // e.g., "bikeshop1.web.app"
    if (hostname.endsWith('.web.app')) {
      tenantSubdomain = hostname.split('.').first;
    }
  }
  
  runApp(MyApp(tenantSubdomain: tenantSubdomain));
}
```

Services then filter data by tenant:
```dart
// In services, load tenant_id from subdomain
final tenantId = await getTenantIdFromSubdomain(tenantSubdomain);
// All queries automatically filter by tenant_id via RLS
```

## Website Features Per Tenant

Each tenant can customize:
- Product catalog with images, descriptions, prices
- Shop name and branding (logo, colors)
- Homepage banners and featured products
- Website content (About, Contact, etc.)
- Online order processing
- Payment gateway integration (MercadoPago)
- Customer login and order history

## Data Isolation

- ✅ Each tenant sees ONLY their data (RLS policies)
- ✅ Same codebase serves all tenants
- ✅ Subdomain determines which tenant's data to show
- ✅ Complete separation: products, orders, customers, settings

## Reference Documentation

- **Setup Guide:** `MULTI_TENANT_WEBSITE_SETUP_GUIDE.md`
- **Quick Start:** `MULTI_TENANT_WEBSITE_QUICKSTART.md`
- **Deployment Scripts:** `scripts/deploy_tenant_website.ps1`, `scripts/deploy_tenant_website.js`

## When Creating Website Features

1. ✅ Ensure data is tenant-scoped (filtered by `tenant_id`)
2. ✅ Test with multiple tenant subdomains
3. ✅ Verify URL detection works correctly
4. ✅ Ensure RLS policies protect cross-tenant access
5. ✅ Test deployment script with dummy tenant

---

# 🌐 Website Builder (Legacy Info)

- Product catalog with images, descriptions, prices
- Online orders sync with Inventory and Accounting
- CMS for homepage, blog, promotions
- Customer login and order history
- Payment gateway integration (free-tier or mock)

---

# 📣 Marketing Module

- Campaign builder (email, SMS, push)
- Customer segmentation based on CRM data
- Promotion rules (discounts, bundles)
- Scheduled and triggered campaigns
- Integration with Analytics for performance tracking

---

# 📊 Analytics Dashboard

- Sales by product/category/date
- Inventory turnover and valuation
- Customer lifetime value
- Maintenance cost breakdown
- HR metrics (attendance, payroll trends)
- Campaign performance (open rate, conversion)

---

# 📦 Suggested Folder Structure

`plaintext
lib/
├── modules/
│   ├── sales/
│   ├── purchases/
│   ├── inventory/
│   ├── maintenance/
│   ├── accounting/
│   ├── crm/
│   ├── hr/
│   ├── website/
│   ├── marketing/
│   ├── analytics/
│   └── settings/
├── shared/
│   ├── models/
│   ├── services/
│   ├── widgets/
│   └── themes/
`

Each module:

- Has its own routes (GoRouter)
- Uses shared models (e.g. Product, Order, Customer, Employee)
- Follows the same UI design system

---

# 🧠 Copilot Expectations

Copilot must:

- Maintain consistent naming across modules
- Reuse shared models and widgets
- Respect business rules (e.g. inventory deduction, tax calculation)
- Avoid GUI fragmentation (no random button styles)
- Handle dark mode, language, and time zone globally
- Generate audit-ready accounting logic
- Use PostgreSQL syntax and constraints
- Avoid hardcoded values—use config or constants
- Use modular architecture with clean separation of concerns

---

# 🖼️ Image Handling Rules

- All modules that involve products, customers, employees, or marketing must support images.
- Use a unified image service (`ImageService`) in `lib/shared/services/` for:
  - Uploading images (to Supabase storage or Firebase storage).
  - Fetching images with caching (use `CachedNetworkImage`).
  - Handling placeholders (default icon if no image).
  - Handling errors (broken link → fallback image).
- Store only the image URL/path in the database, not the binary.
- Organize assets in `assets/images/` for static icons, logos, and placeholders.
- For product images:
  - Support multiple images per product.
  - Use thumbnails in lists, full-size in detail pages.
- For employee/customer profile pictures:
  - Circular avatar style, consistent sizing.
- For marketing/website:
  - Support banners and campaign images with responsive scaling.
- Always optimize for performance:
  - Use lazy loading for lists.
  - Use compressed formats (WebP/optimized JPEG).
- Respect dark mode (ensure images/icons adapt or remain visible).

---

# 🔍 Search & Filtering Rules

- Any list or dropdown with more than ~10 possible items must include a search bar at the top.
- Examples:
  - Chart of Accounts → searchable by code and name.
  - Customer/Supplier selection → searchable by name, RUT, or email.
  - Product selection → searchable by SKU, name, or category.
- Use a consistent search widget across modules:
  - TextField with prefix search icon.
  - Real-time filtering as the user types.
  - Case-insensitive matching.
- For very large datasets (100+ items), implement pagination or lazy loading with search.
- Always place the search bar **above the list** (not hidden in a menu).
- Respect localization: search must work with Spanish characters (ñ, á, é, í, ó, ú).

---

# 🚀 Firebase Hosting: Multi-Site Deployment

## Firebase Project Configuration

**Project:** `project-vinabike`  
**Hosting Sites:**
- `project-vinabike` (ERP admin interface)
- `vinabike-store` (Public storefront - main)
- Up to 34 additional tenant websites (e.g., `bikeshop1`, `bikeshop2`, etc.)

## Deployment Architecture

```
┌─────────────────────────────────────────────────┐
│         SINGLE FLUTTER CODEBASE                 │
│   (Same build deployed to multiple sites)      │
└─────────────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┬──────────────┐
         │                       │              │
┌────────▼────────┐   ┌─────────▼────────┐    ...
│ project-vinabike │   │ vinabike-store   │
│  (Admin ERP)     │   │ (Public Store)   │
│  .web.app        │   │ .web.app         │
└──────────────────┘   └──────────────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
         ┌───────────────────────┐
         │   SUPABASE DATABASE   │
         │  (RLS filters data)   │
         └───────────────────────┘
```

## Deployment Commands

**Build once:**
```bash
flutter build web --release --web-renderer canvaskit
```

**Deploy to specific site:**
```bash
# Deploy to admin ERP
firebase deploy --only hosting:erp

# Deploy to public store
firebase deploy --only hosting:store

# Deploy to specific tenant (using script)
.\scripts\deploy_tenant_website.ps1 -TenantId "UUID"
```

**Deploy to all sites:**
```bash
firebase deploy --only hosting
```

## Firebase Configuration Files

**firebase.json:**
```json
{
  "hosting": [
    {
      "target": "erp",
      "public": "build/web",
      "rewrites": [{"source": "**", "destination": "/index.html"}]
    },
    {
      "target": "store",
      "public": "build/web",
      "rewrites": [{"source": "**", "destination": "/index.html"}]
    }
  ]
}
```

**.firebaserc:**
```json
{
  "projects": {
    "default": "project-vinabike"
  },
  "targets": {
    "project-vinabike": {
      "hosting": {
        "erp": ["project-vinabike"],
        "store": ["vinabike-store"]
      }
    }
  }
}
```

## Adding New Tenant Sites

When deploying a new tenant website, the deployment script automatically:
1. Creates Firebase Hosting site: `firebase hosting:sites:create {subdomain}`
2. Configures target: `firebase target:apply hosting {subdomain} {subdomain}`
3. Builds Flutter app: `flutter build web --release`
4. Deploys to site: `firebase deploy --only hosting:{subdomain}`
5. Updates database with URL and deployment status

## URL Structure

- **Admin ERP:** `https://project-vinabike.web.app`
- **Public Store (main):** `https://vinabike-store.web.app`
- **Tenant Websites:** `https://{tenant-subdomain}.web.app`

## Cost and Limits

- **Hosting:** FREE (10GB storage, 360MB/day transfer per site)
- **SSL:** FREE (auto-included)
- **Max sites per project:** 36
- **Current sites:** 2 (erp + store) + tenant sites as needed

---

# 📝 Development & Deployment Best Practices

## Before Any Database Change

1. ✅ **READ** `core_schema.sql` to check for existing similar code
2. ✅ **SEARCH** for existing functions/triggers/tables
3. ✅ **VERIFY** tenant_id is included in new tables
4. ✅ **ADD** RLS policies for new tables
5. ✅ **TEST** with `FINAL_MULTI_TENANT_VERIFICATION.sql`
6. ✅ **DEPLOY** updated `core_schema.sql` to Supabase

## Before Any Flutter Change

1. ✅ Verify database schema exists for the feature
2. ✅ Check if models need updating
3. ✅ Ensure services filter by `tenant_id`
4. ✅ Test compilation locally
5. ✅ Test on Windows, Web, and Android (if applicable)

## Before Deploying to Firebase

1. ✅ Run `flutter clean`
2. ✅ Run `flutter pub get`
3. ✅ Run `flutter build web --release`
4. ✅ Verify build/web directory exists
5. ✅ Test locally: `flutter run -d chrome`
6. ✅ Deploy: `firebase deploy --only hosting:{target}`
7. ✅ Verify deployment at live URL
8. ✅ Test complete user flow on deployed site

## Multi-Tenant Testing Checklist

After any schema change:
1. ✅ Run `FINAL_MULTI_TENANT_VERIFICATION.sql`
2. ✅ Verify 0 dangerous policies
3. ✅ Verify 0 tables without policies
4. ✅ Test login as different tenants
5. ✅ Verify data isolation (Tenant A can't see Tenant B's data)
6. ✅ Test all CRUD operations per tenant
7. ✅ Verify website subdomain detection works