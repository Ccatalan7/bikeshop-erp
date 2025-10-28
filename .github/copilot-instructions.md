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

---

# 🚨 TROUBLESHOOTING: MULTI-TENANT ISSUES

**When ANY feature breaks after multi-tenant migration, follow this checklist:**

## 1. Check Database Functions First
Most common issue: Functions creating records without `tenant_id`

```sql
-- ❌ WRONG: Missing tenant_id
insert into journal_entries (entry_number, total, ...) values (...);

-- ✅ CORRECT: Include tenant_id
declare
  v_tenant_id uuid;
begin
  v_tenant_id := p_invoice.tenant_id;  -- Get from input parameter
  insert into journal_entries (tenant_id, entry_number, total, ...) values (v_tenant_id, ...);
end;
```

**Common broken functions:**
- `create_sales_invoice_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_purchase_invoice_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_sales_payment_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_purchase_payment_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_invoice_from_mechanic_job()` → Must include `tenant_id` when creating invoice

**Fix pattern:**
1. Add `v_tenant_id uuid;` to function variables
2. Get tenant_id from parameter: `v_tenant_id := p_record.tenant_id;`
3. Add `tenant_id` column to ALL INSERT statements
4. Deploy updated `core_schema.sql`

## 2. Check RLS Policies
Symptoms: "new row violates row-level security policy" or empty results

```sql
-- ❌ WRONG: Missing 'to authenticated'
create policy "table_select" on table_name for select 
  using (tenant_id = public.user_tenant_id());

-- ✅ CORRECT: Include 'to authenticated'
create policy "table_select" on table_name 
  for select 
  to authenticated
  using (tenant_id = public.user_tenant_id());
```

**Fix ALL CRUD policies for each table:**
```sql
alter table table_name enable row level security;

drop policy if exists "table_select" on table_name;
drop policy if exists "table_insert" on table_name;
drop policy if exists "table_update" on table_name;
drop policy if exists "table_delete" on table_name;

create policy "table_select" on table_name for select to authenticated
  using (tenant_id = public.user_tenant_id());
  
create policy "table_insert" on table_name for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
  
create policy "table_update" on table_name for update to authenticated
  using (tenant_id = public.user_tenant_id());
  
create policy "table_delete" on table_name for delete to authenticated
  using (tenant_id = public.user_tenant_id());
```

**Remove role-based restrictions during testing:**
- ❌ `(auth.jwt() -> 'user_metadata' ->> 'role') = 'manager'` → Blocks regular users
- ✅ Just use `tenant_id = public.user_tenant_id()` → All authenticated users in same tenant

## 3. Check Flutter Code
Symptoms: Insert fails, "tenant_id cannot be null"

```dart
// ❌ WRONG: Missing tenant_id
final paymentData = {
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
};

// ✅ CORRECT: Include tenant_id
final userId = Supabase.instance.client.auth.currentUser?.id;
final profileResponse = await Supabase.instance.client
    .from('user_profiles')
    .select('tenant_id')
    .eq('user_id', userId)
    .single();
final tenantId = profileResponse['tenant_id'] as String;

final paymentData = {
  'tenant_id': tenantId,  // ⚠️ CRITICAL
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
};
```

**Or use TenantService:**
```dart
final tenantId = await TenantService().getTenantId();
final data = {
  'tenant_id': tenantId,
  // ... other fields
};
```

## 4. Debugging Steps (In Order)

**Step 1: Check if query returns data**
```sql
-- Run in Supabase SQL Editor as authenticated user
SELECT auth.uid() as my_user_id, public.user_tenant_id() as my_tenant_id;
SELECT * FROM table_name WHERE tenant_id = public.user_tenant_id();
```

**Step 2: Check RLS policies exist**
```sql
SELECT tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE tablename = 'table_name';
```
Expected: 4 policies (SELECT, INSERT, UPDATE, DELETE) with `{authenticated}` role

**Step 3: Check function includes tenant_id**
```sql
-- Search for INSERT statements in function
SELECT routine_definition 
FROM information_schema.routines 
WHERE routine_name = 'function_name';
```
All INSERTs must include `tenant_id` column

**Step 4: Check Flutter includes tenant_id**
- Add debug print: `debugPrint('📦 Insert data: $data');`
- Verify `tenant_id` is in the printed map
- Check if `tenant_id` value is not null

## 5. Common Error Messages & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `new row violates row-level security policy` | RLS blocking INSERT/UPDATE | Add `to authenticated` to policy, ensure `tenant_id` included in data |
| `Column tenant_id cannot be null` | Flutter not sending tenant_id | Fetch tenant_id from user_profiles, include in INSERT |
| `Query returned empty` | RLS filtering out data | Check user's tenant_id matches data's tenant_id |
| `Payment method not found` | Empty payment_methods table | Run `seed_payment_methods_for_tenant()` function |
| `Cannot delete` | Role restriction in policy | Remove role check, use only tenant_id check |
| Function returns NULL | Missing tenant_id in function | Add `v_tenant_id` variable, include in all INSERTs |

## 6. Quick Fix Checklist

When a feature is broken:
- [ ] Database function includes `tenant_id` in ALL INSERTs?
- [ ] RLS policies have `to authenticated`?
- [ ] RLS policies for ALL operations (SELECT, INSERT, UPDATE, DELETE)?
- [ ] Flutter code fetches and includes `tenant_id`?
- [ ] Redeploy `core_schema.sql` after function fixes?
- [ ] Restart Flutter app after schema deployment?
- [ ] Test with actual user (not service role in SQL Editor)?

## 7. Testing Multi-Tenant Isolation

**Always verify tenant isolation:**
```sql
-- Create test data for current tenant
INSERT INTO test_table (tenant_id, name) 
VALUES (public.user_tenant_id(), 'My Data');

-- Switch to different user (different tenant)
-- Verify you CANNOT see the other tenant's data
SELECT * FROM test_table;  -- Should only see your tenant's data
```

**Critical: SQL Editor runs as service role (bypasses RLS)**
- Testing in SQL Editor shows ALL tenants' data
- Always test from Flutter app as authenticated user
- Use `auth.uid()` and `public.user_tenant_id()` to verify user context

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