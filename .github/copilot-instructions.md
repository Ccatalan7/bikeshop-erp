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

## Public Store / Anonymous Access (CRITICAL)
**FOR PUBLIC STOREFRONTS (subdomain-based, anonymous users):**

- **EVERY** query MUST use `PublicStoreTenantProvider` to get detected tenant_id
- **EVERY** product/category query MUST filter: `.eq('tenant_id', tenantId)`
- **EVERY** order INSERT MUST include `tenant_id` from detected tenant
- **NEVER** query database without tenant_id filter (even with RLS, app must filter)
- **ALWAYS** check `tenantProvider.tenantId != null` before queries

**Common mistakes:**
- ❌ Using `InventoryService` (authenticated) instead of `PublicInventoryService` (anonymous)
- ❌ Direct Supabase queries without `.eq('tenant_id', tenantId)`
- ❌ Creating orders without `tenant_id` in orderData
- ❌ Assuming RLS handles filtering (app layer MUST filter for performance/security)

**Correct pattern:**
```dart
// ✅ CORRECT: Get tenant from subdomain detection
final tenantProvider = context.read<PublicStoreTenantProvider>();
final tenantId = tenantProvider.tenantId;

if (tenantId == null) {
  // Show error or redirect
  return;
}

// ✅ CORRECT: Filter by tenant_id
final products = await Supabase.instance.client
    .from('products')
    .select()
    .eq('tenant_id', tenantId)  // ⚠️ MANDATORY
    .eq('is_active', true);

// ✅ CORRECT: Include tenant_id in INSERT
final orderData = {
  'tenant_id': tenantId,  // ⚠️ MANDATORY
  'customer_email': email,
  'total': total,
  // ... other fields
};
```

**Pages that need tenant detection:**
- ✅ `product_catalog_page.dart` - Filter products by tenant
- ✅ `public_home_page.dart` - Filter featured products by tenant
- ✅ `product_detail_page.dart` - Verify product belongs to tenant
- ✅ `checkout_page.dart` - Include tenant_id in order creation
- ✅ Any page that queries tenant-scoped data

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

// ✅ CORRECT: DatabaseService auto-injects tenant_id (as of Oct 28, 2025)
// Just use DatabaseService.insert() - it will auto-inject tenant_id
final data = {
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
  // tenant_id is automatically added by DatabaseService
};
await databaseService.insert('payments', data);

// ✅ ALTERNATIVE: Use TenantService for manual injection
final tenantId = await TenantService().getTenantId();
final paymentData = {
  'tenant_id': tenantId,  // ⚠️ EXPLICIT
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
};
```

**⚠️ CRITICAL: DatabaseService Auto-Injection (Oct 28, 2025)**
- `DatabaseService.insert()` now **automatically injects `tenant_id`**
- Works for authenticated users (gets tenant_id from user_profiles)
- Skips injection for system tables (tenants, user_profiles, etc.)
- Preserves existing tenant_id if already in payload
- **Import services (CSV/Excel) are now tenant-safe automatically**

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

**⚠️ CRITICAL: NEVER CREATE UNNECESSARY COLUMNS OR FUNCTIONS!**

**BEFORE creating ANY database column/function/trigger, you MUST:**

1. 🔍 **SEARCH FIRST - Is there an existing column/function that does this?**
   - Don't create `stock_at_order` if `current_stock` already exists and can be used
   - Don't create `received_stock` if you can calculate it from existing data
   - Don't create new functions if existing ones can be extended

2. 🤔 **ASK: Can this be calculated/derived instead of stored?**
   - ❌ BAD: Adding `total_cost` column when you can calculate `quantity * price`
   - ❌ BAD: Adding `stock_difference` column when you can calculate `current - initial`
   - ✅ GOOD: Store only raw data, calculate derived values in code or views

3. 📊 **Check if a VIEW or Dart getter can do this instead:**
   - Use database VIEWs for complex joins/calculations (read-only)
   - Use Dart getters for simple calculations (no DB change needed)
   - Only create columns for data that MUST be persisted

4. 🔄 **Reuse existing patterns and columns:**
   - If table has `created_at`, DON'T add `creation_date`
   - If table has `updated_at`, DON'T add `last_modified`
   - If table has `status`, DON'T add `is_active` (use status values)

5. 🚫 **NEVER add columns "just in case" or "for future use"**
   - Only add what's STRICTLY NECESSARY for the current feature
   - You can always add columns later with ALTER TABLE if truly needed

**⚠️ CRITICAL: ALTER TABLE FOR EXISTING COLUMNS!**

**When adding a new column to an existing table:**

```sql
-- ✅ CORRECT: Add the column to CREATE TABLE definition
create table if not exists my_table (
  id uuid primary key,
  tenant_id uuid not null,
  new_column text,  -- Added here
  created_at timestamp with time zone default now()
);

-- ✅ CORRECT: ALSO add ALTER TABLE for existing tables
alter table my_table add column if not exists new_column text;
```

**WHY?**
- `CREATE TABLE IF NOT EXISTS` won't modify existing tables
- You MUST use `ALTER TABLE ADD COLUMN IF NOT EXISTS` to update live tables
- Otherwise deployed schema won't actually add the column!

**⚠️ AVOID DUPLICATES!**

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
   - ❌ Creating `stock_at_order` when existing columns can track this
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
- ❌ **Adding columns without ALTER TABLE statements for existing tables**
- ❌ **Creating columns that could be calculated/derived instead**
- ❌ **Adding "nice to have" columns instead of only "must have"**

**Before making any database changes:**
1. 🔍 **ALWAYS check `core_schema.sql` first**
2. 🔍 **SEARCH for existing functions/triggers with similar names or purposes**
3. 📖 Read the relevant section (tables, functions, triggers)
4. 🤔 **Ask: "Does something similar already exist?"**
5. 🤔 **Ask: "Can this be calculated instead of stored?"**
6. 🤔 **Ask: "Is this column STRICTLY NECESSARY?"**
7. ✏️ Make changes directly in `core_schema.sql`
8. ✏️ **Add ALTER TABLE if modifying existing table structure**
9. 💾 Save and inform user: "Deploy the updated `core_schema.sql` to Supabase"
10. 📝 **BE EXPLICIT:** Tell user which file and line number you modified

**This is the ONLY database schema file to edit. The 3-file split is for deployment only.**

---

# � CRITICAL: INVENTORY COLUMNS PATTERN (inventory_qty vs stock_quantity)

**⚠️ PRODUCTS TABLE HAS TWO INVENTORY COLUMNS - BOTH MUST BE UPDATED TOGETHER!**

## The Two Columns

```sql
-- products table
inventory_qty integer not null default 0,    -- Original column (Oct 2024)
stock_quantity integer not null default 0,   -- Added Oct 13, 2025 for stock monitoring
```

## Historical Context

**Timeline:**
1. **Original:** `inventory_qty` created with products table (used everywhere)
2. **Oct 13, 2025:** Added `stock_quantity` as "alias" + `min_stock_level` + `max_stock_level` for stock monitoring features
3. **Nov 1, 2025:** Smart purchase list created, uses both columns

**Why Both Exist:**
- `inventory_qty` = Legacy column, used by older modules (sales, purchases, POS, accounting)
- `stock_quantity` = Added for stock level monitoring (min/max thresholds, smart purchase list, auto-reorder)
- Both columns store the SAME value and MUST be kept in sync

## MANDATORY Pattern: Update BOTH Columns

**❌ WRONG - Only updating one column:**
```sql
update products set inventory_qty = inventory_qty - 5 where id = product_id;
```

**✅ CORRECT - Always update BOTH:**
```sql
update products 
   set inventory_qty = inventory_qty - 5,
       stock_quantity = stock_quantity - 5
 where id = product_id;
```

**✅ CORRECT - With safety checks:**
```sql
update products 
   set inventory_qty = greatest(inventory_qty - 5, 0),
       stock_quantity = greatest(stock_quantity - 5, 0)
 where id = product_id;
```

## Where This Pattern is REQUIRED

**Database Functions (ALL must update both):**
- ✅ `consume_sales_invoice_inventory()` - Reduces stock on sales
- ✅ `consume_purchase_invoice_inventory()` - Increases stock on purchases
- ✅ `handle_sales_invoice_change()` - Trigger logic
- ✅ `handle_purchase_invoice_change()` - Trigger logic
- ✅ `restore_inventory()` - Reverses stock deductions
- ✅ ANY function that modifies product inventory

**Flutter/Dart Code:**
```dart
// ✅ CORRECT: inventory_models.dart Product.toJson()
Map<String, dynamic> toJson() {
  return {
    'inventory_qty': inventoryQty,
    'stock_quantity': inventoryQty,  // ← Both get same value!
    // ... other fields
  };
}

// ✅ CORRECT: When reading, prefer stock_quantity (more recent)
final currentStock = product['stock_quantity'] as int? ?? 
                     product['inventory_qty'] as int? ?? 0;
```

## Auto-Sync Trigger

There's a trigger that auto-syncs when one is updated:

```sql
-- In auto_add_low_stock_to_purchase_list() function
if NEW.stock_quantity != NEW.inventory_qty then
  NEW.stock_quantity := NEW.inventory_qty;  -- Keep them in sync
end if;
```

## Rules for New Code

**When creating/modifying ANY inventory-related code:**

1. ✅ **Database Functions:** Update BOTH columns in every UPDATE statement
2. ✅ **Flutter Models:** Write to both columns in `toJson()`
3. ✅ **Flutter Services:** When reading, use `stock_quantity` (or fallback to `inventory_qty`)
4. ✅ **Views/Reports:** Prefer `stock_quantity` for consistency
5. ✅ **Comments:** Always add comment: `-- Update BOTH inventory_qty (legacy) AND stock_quantity (current)`

**⚠️ DO NOT:**
- ❌ Remove either column (would break hundreds of references)
- ❌ Update only one column (causes data inconsistency)
- ❌ Create new inventory column (we already have redundancy)
- ❌ Assume they auto-sync everywhere (manual sync required in most places)

## Testing Checklist

When making inventory changes, verify:
- [ ] Both columns updated in database functions
- [ ] Both columns updated in UPDATE statements
- [ ] Both columns written in Dart `toJson()`
- [ ] Stock value is same in both columns after operation
- [ ] Smart purchase list still triggers correctly
- [ ] POS transactions still work
- [ ] Sales/purchase invoices still update stock

## Common Mistakes

```sql
-- ❌ WRONG: Missing stock_quantity
update products set inventory_qty = 100 where id = product_id;

-- ❌ WRONG: Only in INSERT (both needed for consistency)
insert into products (name, inventory_qty) values ('Product', 50);

-- ✅ CORRECT: Both columns
update products 
   set inventory_qty = 100,
       stock_quantity = 100
 where id = product_id;

-- ✅ CORRECT: Both in INSERT
insert into products (name, inventory_qty, stock_quantity) 
values ('Product', 50, 50);
```

## Why We Keep Both Columns

**Benefits of redundancy:**
1. ✅ Backward compatibility with existing code
2. ✅ Safety net - if one gets corrupted, other is backup
3. ✅ Different semantic meaning (legacy vs monitoring)
4. ✅ Minimal storage cost, significant stability benefit
5. ✅ Consolidation would require touching 100+ locations (high risk, low reward)

**This pattern is PRODUCTION-TESTED and MUST be maintained going forward.**

---

# �🔧 COPILOT WORKFLOW CHECKLIST

**For ANY database-related task:**

1. ✅ **READ** `supabase/sql/core_schema.sql` first - ENTIRE file if needed
2. ✅ **SEARCH** for existing tables/functions/triggers with similar names or purposes
3. ✅ **ASK YOURSELF: "Can I solve this WITHOUT adding new columns?"**
   - Can I use existing columns?
   - Can I calculate this in Dart instead of storing it?
   - Can I use a database VIEW instead of a new column?
4. ✅ **CHECK** if similar patterns already exist (e.g., `handle_sales_invoice_change` → use same pattern for purchases)
5. ✅ **REUSE** existing helper functions (`ensure_account`, `consume_inventory`, etc.)
6. ✅ **UPDATE** existing code or add new code following EXISTING patterns
7. ✅ **NEVER** create duplicate functions/triggers with different names
8. ✅ **NEVER** create columns that are "nice to have" - only STRICTLY NECESSARY ones
9. ✅ **VERIFY** column names match what's in `core_schema.sql`
10. ✅ **IF YOU ADD A COLUMN:** Also add `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` statement
11. ✅ **IF MODIFYING INVENTORY:** Update BOTH `inventory_qty` AND `stock_quantity` columns (see inventory columns section above)
12. ✅ **INFORM** user: "I modified `core_schema.sql` at line X" or "I added function Y to `core_schema.sql`"
13. ✅ **TELL USER:** "Deploy the updated `core_schema.sql` to Supabase"
14. ✅ **PROVIDE DEPLOYMENT SNIPPET:** Extract the exact lines to deploy and present them in a canvas artifact for easy copy-paste

**⚠️ CRITICAL: Before creating ANY column:**
- 🔍 Search for existing columns that could serve the same purpose
- 🤔 Ask: "Can I calculate this value instead of storing it?"
- 🤔 Ask: "Will this column DEFINITELY be used, or is it speculative?"
- 🤔 Ask: "Can a Dart getter or database VIEW solve this instead?"
- ❌ If answer is "maybe" or "just in case" → DON'T CREATE IT
- ✅ Only create if it's ABSOLUTELY ESSENTIAL for the feature to work

**⚠️ CRITICAL: Before creating ANY function/trigger:**
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
5. ✅ **CHECK EXISTING CODE** for tenant_id handling patterns
6. ✅ **VERIFY** all queries include `.eq('tenant_id', tenantId)` or use services that filter
7. ✅ **VERIFY** all inserts include `'tenant_id': tenantId` in data maps
8. ✅ Test compilation before marking complete

**When modifying existing pages/services:**
- 🔍 **SEARCH** for similar queries in the file - do they filter by tenant_id?
- 🔍 **GREP** for `from('table_name')` to find all database queries
- 🔍 **CHECK** if page uses authenticated or anonymous access pattern
- ⚠️ **NEVER** remove existing `.eq('tenant_id', ...)` filters
- ⚠️ **NEVER** assume query is safe without tenant_id filter

**For ANY new feature:**

1. ✅ **Database schema first (in `core_schema.sql`)**
   - ⚠️ **MUST have `tenant_id` column** (except auth/system tables)
   - ⚠️ **MUST have index on `tenant_id`**
   - ⚠️ **MUST have RLS policies filtering by `tenant_id`**
   - ⚠️ **ASK: Can I build this WITHOUT adding new columns?**
   - ⚠️ **ONLY add columns that are STRICTLY NECESSARY**
   - ⚠️ **IF adding columns: MUST add ALTER TABLE statement**
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
   - ⚠️ **Import services MUST use `DatabaseService` (auto-injects tenant_id)**
4. ✅ UI implementation
5. ✅ Navigation integration (add to main menu)

**REMEMBER:**
- 🚫 No new SQL files
- 🚫 No duplicate functions/triggers (search first!)
- 🚫 No markdown guides for simple tasks
- 🚫 No assumptions about schema - always check first
- 🚫 No creating new patterns when existing patterns work
- 🚫 **NO COLUMNS UNLESS STRICTLY NECESSARY** (can't be calculated, can't use existing)
- 🚫 **NO TABLES WITHOUT `tenant_id`** (except auth/system)
- 🚫 **NO GLOBAL UNIQUE CONSTRAINTS** (must be per-tenant)
- 🚫 **NO QUERIES WITHOUT `tenant_id` FILTER** (authenticated OR anonymous)
- 🚫 **NO ORDER/INSERT WITHOUT `tenant_id`** (public store guest checkout)
- 🚫 **NO DIRECT SUPABASE QUERIES IN PUBLIC STORE** (use PublicInventoryService or filter by tenant_id)
- 🚫 **NO DIRECT SUPABASE CLIENT IN IMPORT SERVICES** (use DatabaseService for auto-injection)
- 🚫 **NO ADDING COLUMNS WITHOUT ALTER TABLE STATEMENTS**
- ✅ Always search for existing similar code
- ✅ Always follow existing naming conventions
- ✅ Always reuse existing helper functions
- ✅ Always verify changes compile before finishing
- ✅ **ASK: "Can I calculate this instead of storing it?"**
- ✅ **ALWAYS add `tenant_id` to new tables**
- ✅ **ALWAYS create RLS policies for tenant isolation**
- ✅ **ALWAYS test with multiple tenants to verify isolation**
- ✅ **ALWAYS use PublicStoreTenantProvider for public store pages**
- ✅ **ALWAYS check tenant_id != null before database operations**
- ✅ **ALWAYS use DatabaseService for import services** (CSV/Excel imports)
- ✅ **ALWAYS add ALTER TABLE when adding columns to existing tables**
- ✅ **ALWAYS update BOTH inventory_qty AND stock_quantity when modifying product stock** (see inventory columns pattern)
- ✅ **ALWAYS provide deployment snippet in canvas artifact after modifying core_schema.sql**

---

# 📤 DEPLOYMENT SNIPPET WORKFLOW

**WHEN YOU MODIFY `core_schema.sql`, YOU MUST:**

1. ✅ Make the changes to `core_schema.sql`
2. ✅ Note the line numbers you modified (e.g., "lines 4309-4419")
3. ✅ Tell user: "I modified `core_schema.sql` at lines X-Y (function/view/table name)"
4. ✅ **EXTRACT the exact SQL code** from those lines
5. ✅ **PRESENT in a canvas artifact** titled "Deploy to Supabase: [Description]"
6. ✅ Include clear instructions: "Copy this SQL and run it in Supabase SQL Editor"

**Example canvas format:**
```
Title: Deploy to Supabase: Stock Movements View Fix

Content:
-- Fix stock_movements_view calculation
-- Lines 4309-4419 from core_schema.sql

drop view if exists stock_movements_view cascade;

create view stock_movements_view as
-- ... full SQL here ...

alter view stock_movements_view set (security_invoker = on);
```

**When to provide deployment snippet:**
- ✅ Creating or modifying a VIEW
- ✅ Creating or modifying a FUNCTION
- ✅ Creating or modifying a TRIGGER
- ✅ Adding/modifying RLS policies
- ✅ Adding new tables with indexes
- ✅ Any ALTER TABLE statements
- ❌ NOT needed for Flutter code changes (those auto-deploy on app restart)

**Benefits:**
- User can copy-paste directly into Supabase SQL Editor
- No need to search through 13,000+ line file
- Clear documentation of what changed
- Easy to review before deploying

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

**📘 CRITICAL: Read `.github/GUI_DESIGN_PRINCIPLES.md` for complete design guidelines**

**Core Principles:**
- **Minimalism:** Professional, clean, data-dense (no circus colors/excessive icons)
- **Typography:** 14px body, 13px labels, 18-24px headers
- **Colors:** Whites/grays + single accent (blue), semantic colors sparingly
- **Tables:** Subtle borders, compact spacing (48px rows), right-align numbers
- **Buttons:** 1 primary (filled), 2-3 secondary (outlined/text), strategic icons only
- **Forms:** Two-column layout (desktop), grouped fields, 12-16px spacing
- **Split-Pane:** Use ONLY for list+detail modules (invoices, customers, products), NOT for dashboards/reports/settings

**Reference Implementation:** `lib/modules/sales/pages/invoice_list_page.dart`

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

# � CRITICAL: REALTIME SERVICE INITIALIZATION

**⚠️ NEVER use `async void` in constructor-called methods - causes UI freezing!**

## The Problem

Service constructors calling `async void` methods block UI thread during Supabase realtime subscription setup.

**❌ WRONG - Blocks UI:**
```dart
class CustomerService extends ChangeNotifier {
  CustomerService() {
    _setupCustomersRealtime(); // Freezes app until complete
  }
  
  async void _setupCustomersRealtime() { // ❌ Blocks!
    await Supabase.instance.client.from('customers').stream(...).listen(...);
  }
}
```

**✅ CORRECT - Non-blocking:**
```dart
class CustomerService extends ChangeNotifier {
  CustomerService() {
    _setupCustomersRealtime(); // Returns immediately
  }
  
  Future<void> _setupCustomersRealtime() async { // ✅ Non-blocking!
    await Supabase.instance.client.from('customers').stream(...).listen(...);
  }
}
```

## The Rule

**When creating ANY service with realtime subscriptions:**
- ✅ Use `Future<void>` for setup methods (NOT `async void`)
- ✅ Constructor calls setup method as fire-and-forget
- ✅ Test navigation - should be instant, no freeze

**Why:** `async void` = synchronous blocking call | `Future<void>` = async non-blocking

**See:** `.github/REALTIME_SERVICE_BLOCKING_FIX.md` for detailed documentation

---

# �🖼️ SPACE MANAGEMENT & RESPONSIVE UI PATTERNS

**CRITICAL LESSONS LEARNED FROM PRODUCTION TESTING (Oct 31, 2025)**

## 1. Resizable Navigation Pane

**Pattern:** User-adjustable sidebar width with persistence

**Implementation:**
```dart
// NavigationService (shared/services/navigation_service.dart)
class NavigationService extends ChangeNotifier {
  static const double _minDrawerWidth = 200;
  static const double _maxDrawerWidth = 400;
  static const double _defaultDrawerWidth = 280;
  double _drawerWidth = _defaultDrawerWidth;
  
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _drawerWidth = prefs.getDouble('navigation_drawer_width') ?? _defaultDrawerWidth;
    notifyListeners();
  }
  
  void updateDrawerWidth(double newWidth) {
    _drawerWidth = newWidth.clamp(_minDrawerWidth, _maxDrawerWidth);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('navigation_drawer_width', _drawerWidth);
    });
    notifyListeners();
  }
}

// MainLayout (shared/widgets/main_layout.dart)
Row(
  children: [
    // Sidebar with dynamic width
    AnimatedContainer(
      width: navigationService.drawerWidth,
      child: AppSidebar(),
    ),
    // Main content area with left border (serves as resize handle)
    Expanded(
      child: Container(
        decoration: navigationService.isDrawerVisible
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              )
            : null,
        child: MouseRegion(
          cursor: navigationService.isDrawerVisible 
              ? SystemMouseCursors.resizeColumn 
              : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: navigationService.isDrawerVisible
                ? (details) {
                    navigationService.updateDrawerWidth(
                      navigationService.drawerWidth + details.delta.dx,
                    );
                  }
                : null,
            child: Column(
              children: [
                // App bar and content...
              ],
            ),
          ),
        ),
      ),
    ),
  ],
)
```

**Key Principles:**
- ✅ Use `SharedPreferences` to persist user preference
- ✅ Clamp width to reasonable min/max (200-400px)
- ✅ Use `MouseRegion` with `SystemMouseCursors.resizeColumn` for visual feedback
- ✅ Use `GestureDetector.onHorizontalDragUpdate` for drag handling
- ✅ **CRITICAL:** The 1px border IS the visual divider - no separate resize handle
- ✅ **CRITICAL:** Wrap the entire content Column with MouseRegion + GestureDetector, not a separate widget
- ✅ **CRITICAL:** Border must be on the Container wrapping the content, not on a separate resize handle
- ✅ This ensures horizontal lines extend fully without gaps
- ✅ `notifyListeners()` for real-time UI updates

**Common Mistakes to AVOID:**
- ❌ Creating a separate resize handle widget between sidebar and content
- ❌ Adding extra width for the resize handle (creates gaps in horizontal dividers)
- ❌ Putting the border on the resize handle instead of the content area
- ❌ Using a thick transparent area for dragging (makes UI look broken)

**Apply To:** Any resizable panel (sidebar, detail panels, split views)

---

## 2. Responsive Table Layout with Horizontal Scroll

**Pattern:** Tables that shrink to minimum width but use available space

**Implementation:**
```dart
// Sales Invoice Line Items (modules/sales/pages/invoice_form_page.dart)
// Column width constants
static const double _colIndexWidth = 40;
static const double _colQuantityWidth = 120;
static const double _colPriceWidth = 130;
static const double _colDiscountWidth = 130;
static const double _colTotalWidth = 130;
static const double _colActionsWidth = 48;

Widget _buildLineItemsSection() {
  return LayoutBuilder(
    builder: (context, constraints) {
      const minTableWidth = 800.0; // Reduced from 900
      final tableWidth = constraints.maxWidth > minTableWidth 
          ? constraints.maxWidth 
          : minTableWidth;
      
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _buildTableHeader(),
              ..._lineItems.map((item, index) => _buildLineRow(item, index)),
            ],
          ),
        ),
      );
    },
  );
}

// Product column with minimum width
Container(
  constraints: BoxConstraints(
    minWidth: 250, // Reduced from 300
    maxWidth: tableWidth - fixedColumnsWidth,
  ),
  child: ProductAutocompleteField(...),
)
```

**Key Principles:**
- ✅ Use `LayoutBuilder` to detect available width
- ✅ Define minimum table width (typically 800px for complex tables)
- ✅ Use `constraints.maxWidth` when available space > minimum
- ✅ Wrap in `SingleChildScrollView` with `Axis.horizontal` for overflow
- ✅ Set `minWidth` on flexible columns (e.g., product name 250px)
- ✅ Fixed columns use exact widths (e.g., index 40px, actions 48px)
- ✅ Flexible column takes remaining space: `maxWidth: tableWidth - fixedColumnsWidth`

**Apply To:** Any data table, invoice line items, product lists, grid views

---

## 3. Overlay Dropdowns with Scroll Tracking

**Pattern:** Dropdown that follows parent widget when page scrolls

**Problem:** Absolute positioning (`Positioned` with `localToGlobal`) doesn't update on scroll

**Solution:** Use `CompositedTransformFollower` with `LayerLink`

**Implementation:**
```dart
// ProductAutocompleteField (shared/widgets/product_autocomplete_field.dart)
class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  final LayerLink _layerLink = LayerLink();
  
  void _showOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    
    // Minimum 300px width for dropdown (even if field is narrow)
    final dropdownWidth = size.width < 300 ? 300.0 : size.width;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: dropdownWidth, // Fixed minimum width
        child: CompositedTransformFollower(
          link: _layerLink, // Tracks target position
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4), // 4px gap below field
          child: Material(
            elevation: 8,
            child: _buildDropdownContent(),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }
  
  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink, // Links target to follower
      child: TextField(...),
    );
  }
}
```

**Key Principles:**
- ✅ Use `LayerLink` to connect target widget and overlay
- ✅ Wrap target in `CompositedTransformTarget`
- ✅ Use `CompositedTransformFollower` for overlay (NOT `Positioned` with absolute coordinates)
- ✅ Set minimum width for dropdown content (e.g., 300px for product search)
- ✅ Dropdown automatically follows target when scrolling
- ✅ Add small offset (4px) for visual separation

**Apply To:** Autocomplete fields, custom dropdowns, context menus, tooltips

---

## 4. Overlay Click Handling with Focus Delay

**Pattern:** Prevent overlay from closing before tap events register

**Problem:** Focus loss triggers overlay removal before tap completes

**Solution:** 200ms delay before removing overlay

**Implementation:**
```dart
_focusNode.addListener(() {
  if (_focusNode.hasFocus) {
    _showOverlay();
  } else {
    // Add delay to allow tap events to complete
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_focusNode.hasFocus && mounted) {
        _removeOverlay();
      }
    });
  }
});

// Wrap dropdown items in InkWell for better tap detection
MouseRegion(
  child: ListView.builder(
    itemBuilder: (context, index) {
      return InkWell( // Better than ListTile onTap
        onTap: () => _onProductSelected(product),
        child: ListTile(
          title: Text(product.name),
          subtitle: Text('SKU: ${product.sku}'),
        ),
      );
    },
  ),
)
```

**Key Principles:**
- ✅ Use `Future.delayed(Duration(milliseconds: 200))` before removing overlay
- ✅ Check `mounted` before removing overlay (widget may be disposed)
- ✅ Wrap list items in `InkWell` (more reliable than `ListTile.onTap`)
- ✅ Use `MouseRegion` to keep overlay open when mouse hovers
- ✅ 200ms is the sweet spot (100ms too fast, 300ms feels sluggish)

**Apply To:** Any overlay with clickable content (autocomplete, menus, pickers)

---

## 5. Hover-Based UI Elements (Desktop)

**Pattern:** Show actions/controls only when hovering over specific areas

**Implementation:**
```dart
// Sales Invoice Line Items - Hover-based reorder arrows
Widget _buildLineRow(LineItem item, int index) {
  return StatefulBuilder(
    builder: (context, setState) {
      bool isHovered = false;
      
      return MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: Row(
          children: [
            // Index column
            SizedBox(
              width: _colIndexWidth,
              child: Text('${index + 1}'),
            ),
            // Product column
            Expanded(child: ProductField(...)),
            // Actions column with conditional arrows
            SizedBox(
              width: _colActionsWidth,
              child: Row(
                children: [
                  if (isHovered && index > 0)
                    IconButton(
                      icon: Icon(Icons.arrow_upward, size: 16),
                      onPressed: () => _moveLineUp(index),
                    ),
                  if (isHovered && index < _lineItems.length - 1)
                    IconButton(
                      icon: Icon(Icons.arrow_downward, size: 16),
                      onPressed: () => _moveLineDown(index),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16),
                    onPressed: () => _removeLine(index),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

**Key Principles:**
- ✅ Use `StatefulBuilder` for per-row hover state (not setState on whole list)
- ✅ Use `MouseRegion` with `onEnter`/`onExit` callbacks
- ✅ Conditional rendering: `if (isHovered) Widget(...)`
- ✅ Keep hover state local to the widget (not global state)
- ✅ Use small icons (size: 16) for compact inline actions
- ✅ Always show critical actions (delete), hide secondary actions (reorder)

**Apply To:** List items, table rows, cards, inline editing

---

## 6. Duplicate Items Handling in Lists

**Pattern:** Allow same product/item on multiple lines (no auto-merge)

**Problem:** Users expect e-commerce behavior (same product = separate lines, each customizable)

**Implementation:**
```dart
// DON'T merge duplicates
void _addProductLine(ProductSelection selection) {
  // ❌ OLD: Check for duplicates and increment quantity
  // final existingIndex = _lineItems.indexWhere((item) => 
  //     item.productId == selection.product?.id);
  // if (existingIndex >= 0) {
  //   _lineItems[existingIndex].quantity += 1;
  //   return;
  // }
  
  // ✅ NEW: Always create new line
  setState(() {
    _lineItems.add(LineItem(
      productId: selection.product?.id,
      productName: selection.displayText,
      quantity: 1,
      price: selection.product?.price ?? 0,
    ));
  });
}
```

**Key Principles:**
- ✅ Each line is independent (separate quantity, discount, notes)
- ✅ User can manually adjust quantities if they want consolidation
- ✅ Matches e-commerce UX (Amazon, Shopify, etc.)
- ✅ Allows different discounts per line for same product
- ✅ Simpler code (no duplicate detection logic)

**Apply To:** Invoice line items, cart items, order items, parts lists

---

## 7. Grid Table Layout Guidelines

**When to use Grid Tables:**
- Invoice line items (5+ columns)
- Product lists with multiple attributes
- Financial tables (journals, ledgers)
- Any table with mixed input types (text, numbers, dropdowns)

**Column Width Strategy:**
```dart
// Fixed columns (exact widths)
const double _colIndexWidth = 40;      // Row number
const double _colActionsWidth = 48;    // Icon buttons
const double _colQuantityWidth = 120;  // Number inputs
const double _colPriceWidth = 130;     // Currency values
const double _colDiscountWidth = 130;  // Percentage/amount

// Flexible column (takes remaining space)
// Product name, description, notes
final productColumnWidth = tableWidth - (
  _colIndexWidth + _colQuantityWidth + _colPriceWidth + 
  _colDiscountWidth + _colTotalWidth + _colActionsWidth
);
```

**Column Sizing Rules:**
- **Index/Row#:** 40px (max 2-digit numbers)
- **Actions (icons):** 48px (Material design touch target)
- **Numeric inputs:** 120-130px (fits 6-8 digits)
- **Text/Description:** Flexible (minWidth: 250px, takes remaining space)
- **Checkbox:** 48px (touch target)

**Apply To:** Any complex data table with multiple column types

---

## 8. Common GUI Mistakes to AVOID

❌ **Using absolute positioning for scrollable content**
- Overlays detach from parent when scrolling
- Use `CompositedTransformFollower` instead

❌ **Fixed widths on flexible content**
- Product names, descriptions need to expand
- Use `minWidth` constraints, not fixed `width`

❌ **No minimum width on dropdowns**
- Narrow fields create unreadable dropdowns
- Always set minimum (e.g., 300px for product search)

❌ **Auto-merging duplicate items**
- Users expect separate lines for flexibility
- Let users manually consolidate if needed

❌ **Removing overlays immediately on focus loss**
- Tap events don't have time to register
- Add 200ms delay before removal

❌ **Global hover state for lists**
- Causes entire list to rebuild on hover
- Use `StatefulBuilder` for per-row state

❌ **Non-resizable panels on desktop**
- Different workflows need different layouts
- Add drag handles with `SharedPreferences` persistence

❌ **Tables that don't use available space**
- Wasted whitespace on large screens
- Use `LayoutBuilder` + `constraints.maxWidth`

---

## 9. Quick Reference: Apply These Patterns

When creating **any form with line items** (invoices, orders, carts):
1. Use grid table layout with fixed + flexible columns
2. Set minTableWidth to 800px (or appropriate for your columns)
3. Wrap in `LayoutBuilder` + `SingleChildScrollView(horizontal)`
4. Allow duplicate products on separate lines
5. Add hover-based reorder arrows (desktop only)

When creating **any autocomplete/search field**:
1. Use `CompositedTransformFollower` + `LayerLink` for overlay
2. Set minimum dropdown width (300px for product search)
3. Add 200ms delay before removing overlay on focus loss
4. Wrap items in `InkWell` for reliable tap detection
5. Use `MouseRegion` to keep overlay open on hover

When creating **any resizable panel**:
1. Add width management to service (`ChangeNotifier`)
2. Use `SharedPreferences` to persist user preference
3. Add `MouseRegion` with resize cursor
4. Use `GestureDetector.onHorizontalDragUpdate` for dragging
5. Clamp width to reasonable min/max

**These patterns are PRODUCTION-TESTED and should be reused across ALL modules.**

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

---

# 📦 Import Services (CSV/Excel/Zoho) - Stock Tracking Pattern

**ALL import services that modify stock MUST use single-transaction RPC pattern.**

## ✅ Automatic Protection (Oct 28, 2025 → Enhanced Nov 8, 2025)

### Background: Why Transaction Scope Matters

**The Problem (Discovered Nov 8, 2025):**
- Supabase Python client treats each RPC call as a separate HTTP request
- Each HTTP request = separate database transaction
- Session variables only persist WITHIN a transaction
- Setting context in one call, then updating in another call = context lost!

**The Solution:**
- Create RPC functions that bundle context-setting AND data-update in ONE function
- ONE function call = ONE HTTP request = ONE database transaction
- Trigger fires within same transaction → sees session variables → labels import correctly

### Pattern: Single-Transaction RPC Functions

**Database RPC Template** (add to `core_schema.sql`):
```sql
create or replace function public.import_{table}_with_context(
  p_tenant_id uuid,
  p_unique_id text,              -- SKU, email, invoice_number, etc.
  p_{table}_data jsonb,
  p_import_reference text,
  p_import_reason text default 'Import'
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_updated_count integer := 0;
begin
  -- Set import context (transaction-scoped)
  perform pg_catalog.set_config('app.stock_adjustment_context', 'import', true);
  perform pg_catalog.set_config('app.import_reference', p_import_reference, true);
  perform pg_catalog.set_config('app.import_reason', p_import_reason, true);
  
  -- Update record (trigger sees context in same transaction)
  update {table}
  set
    column1 = coalesce((p_{table}_data->>'column1')::type, column1),
    column2 = coalesce((p_{table}_data->>'column2')::type, column2),
    updated_at = now()
  where tenant_id = p_tenant_id and unique_column = p_unique_id;
  
  get diagnostics v_updated_count = row_count;
  
  -- Clear context
  perform pg_catalog.set_config('app.stock_adjustment_context', '', true);
  perform pg_catalog.set_config('app.import_reference', '', true);
  perform pg_catalog.set_config('app.import_reason', '', true);
  
  return jsonb_build_object('success', true, 'updated_count', v_updated_count);
end;
$$;

grant execute on function public.import_{table}_with_context(uuid, text, jsonb, text, text) to authenticated;
```

**Python Import Script Pattern**:
```python
# ✅ CORRECT: Single RPC = single transaction
import_ref = f"import_{int(time.time() * 1000)}"

result = client.rpc('import_product_with_context', {
    'p_tenant_id': tenant_id,
    'p_sku': sku,
    'p_product_data': {
        'name': product_name,
        'price': price,
        'stock_quantity': new_stock
    },
    'p_import_reference': import_ref,
    'p_import_reason': f'Import: {sku}'
}).execute()

# ❌ WRONG: Separate calls = separate transactions (context lost)
client.rpc('set_config', {...}).execute()  # Transaction 1
client.table('products').update({...}).execute()  # Transaction 2 (no context!)
```

## 🚨 Import Service Checklist

When creating ANY import service (products, categories, customers, suppliers, etc.):

1. ✅ **Check if RPC function exists** in `core_schema.sql`
   - Search for: `import_{table}_with_context`
   - If missing, create using template above
   
2. ✅ **Use single-transaction RPC pattern** in Python/Dart
   - ONE `client.rpc()` call bundles context + update
   - Generate `import_reference` once per import batch
   
3. ✅ **Authenticate and get tenant_id**
   - Sign in with email/password
   - Fetch tenant_id from `user_profiles` table
   
4. ✅ **Handle errors gracefully**
   - Show which rows failed
   - Don't stop entire import on single error
   
5. ✅ **Support both CSV and Excel formats**
   - Use pandas for parsing
   - Validate data before inserting
   
6. ✅ **Show progress indicator during bulk imports**
   - Print/log each item processed
   - Display summary at end
   
7. ✅ **Test with multiple tenants to verify isolation**
   - Import same SKU for different tenants
   - Verify data doesn't leak between tenants

## 📋 Existing Import Infrastructure

**Database Functions** (in `core_schema.sql`):
- `set_config(text, text, boolean)` - Exposes PostgreSQL session variables (lines 1629-1654)
- `import_product_with_context(uuid, text, jsonb, text, text)` - Products import (lines 1656-1720)
- `track_product_stock_changes()` - Trigger that detects import context (lines 863-958)

**Stock Adjustments Table**:
- `adjustment_type` includes `'import'` value (line 802)
- `reference` column stores import batch ID (line 815)

**Test Scripts**:
- `scripts/zoho_import/test_import_with_tracking.py` - Working example (469 lines)
- `scripts/zoho_import/test_products.csv` - Sample test data

**Documentation**:
- `.github/IMPORT_STOCK_TRACKING_GUIDE.md` - Complete implementation guide
- `.github/ZOHO_IMPORT_QUICKREF.md` - One-page cheat sheet for AI agents

## 🎯 Production Verification

✅ **Verified working Nov 8, 2025:**
- Stock adjustments created with `type='import'`
- Reference column populated with `import_TIMESTAMP`
- UI displays "Importación" origin label (not "Ajuste Manual")
- No ghost records (only actual stock changes logged)
- Multi-tenant isolation working correctly

---

# � Import Services (CSV/Excel) - Multi-Tenant Rules (LEGACY - SUPERSEDED BY ABOVE)

**ALL import services MUST follow these rules:**

## ✅ Automatic Protection (Oct 28, 2025)

- **Import services are NOW tenant-safe automatically** via `DatabaseService.insert()`
- No manual tenant_id injection needed - it's handled at database layer
- Works for ALL authenticated users across ALL modules

## 🔧 When Creating Import Services

**ALWAYS use DatabaseService for imports:**

```dart
// ✅ CORRECT: DatabaseService auto-injects tenant_id
class ProductImportService {
  final DatabaseService _db = DatabaseService();
  
  Future<void> _upsertProduct(Map<String, dynamic> productData) async {
    // Just use DatabaseService.insert() - tenant_id added automatically
    await _db.insert('products', productData);
  }
}

// ❌ WRONG: Direct Supabase client bypasses auto-injection
class ProductImportService {
  Future<void> _upsertProduct(Map<String, dynamic> productData) async {
    // This bypasses DatabaseService - tenant_id NOT added!
    await Supabase.instance.client.from('products').insert(productData);
  }
}
```

## 🚨 Import Service Checklist

When creating ANY import service (products, categories, customers, suppliers, etc.):

1. ✅ Use `DatabaseService` for ALL inserts/updates (NOT direct Supabase client)
2. ✅ Import service class extends `ChangeNotifier` for UI updates
3. ✅ Handle errors gracefully (show which rows failed)
4. ✅ Support both CSV and Excel formats
5. ✅ Validate data before inserting (SKU/name required, prices > 0, etc.)
6. ✅ Show progress indicator during bulk imports
7. ✅ Test with multiple tenants to verify isolation

## 🔍 How Auto-Injection Works

- `DatabaseService.insert()` checks if table needs tenant_id
- Fetches current user's tenant_id from `user_profiles` table
- Injects tenant_id into payload before INSERT
- Skips system tables: `tenants`, `user_profiles`, `reserved_subdomains`, `user_invitations`
- Logs injection activity: `✅ Auto-injected tenant_id: [uuid] into [table]`

## 📦 Existing Import Services (All Protected)

- ✅ `ProductImportService` → Products
- ✅ `CategoryImportService` → Product categories
- ✅ `CustomerImportService` → Customers
- ✅ `SupplierImportService` → Suppliers
- ✅ `EmployeeImportService` → Employees (if exists)

**All use DatabaseService → All tenant-safe automatically!**

---

# �🚀 Multi-Tenant Onboarding System (AUTO-INITIALIZATION)

**Location:** `supabase/sql/core_schema.sql` lines 1608-2091, 11221-11345

## Automated Flow

When a user signs up, the system **automatically creates**:

1. **Tenant** (shop, subdomain, currency CLP, timezone America/Santiago)
2. **User Profile** (links user to tenant with 'admin' role)
3. **30 Chilean Accounting Accounts** (Assets, Liabilities, Equity, Income, Expenses, Tax)
4. **4 Payment Methods** (Efectivo→Caja, Transferencia→Banco, Cheque, Tarjeta)
5. **8 Company Settings** (IVA 19%, currency, fiscal year, invoice/purchase prefixes)
6. **7 Website Settings** (e-commerce defaults, theme, currency)

**Trigger Chain:**
```
User signup → on_auth_user_created → handle_new_user() 
                                           ↓
                                    Creates tenant
                                           ↓
                            trg_tenant_initialization → handle_new_tenant()
                                                              ↓
                                                    seed_chart_of_accounts()
                                                    seed_payment_methods_for_tenant()
                                                    seed_company_settings()
                                                    seed_website_settings()
```

## User Invitation Flow

- If user has pending invitation → joins existing tenant with invited role
- Otherwise → creates new tenant and becomes admin
- Subdomain auto-generated from email (handles collisions with counter)

## Manual Seeding (Existing Tenants)

```sql
-- Seed all foundation data for existing tenant
DO $$
DECLARE tenant_rec RECORD;
BEGIN
  FOR tenant_rec IN SELECT id FROM tenants LOOP
    PERFORM public.seed_chart_of_accounts(tenant_rec.id);
    PERFORM public.seed_payment_methods_for_tenant(tenant_rec.id);
    PERFORM public.seed_company_settings(tenant_rec.id);
    PERFORM public.seed_website_settings(tenant_rec.id);
  END LOOP;
END $$;
```

---

# 📦 Barcode Scanner Support

The app supports **3 types of barcode scanners**:

## 1. USB/Keyboard Scanners (Recommended for Desktop/POS)
- Works on all platforms (Windows, macOS, Linux, Web)
- No drivers needed - plug and play
- Scanner emulates keyboard input
- Most economical option
- Examples: Symbol LS2208, Honeywell Voyager, Inateck BCST-70

## 2. Bluetooth Scanners (Mobile/Tablet)
- For Windows, Android, iOS
- Wireless freedom
- Requires Bluetooth pairing
- Examples: Socket Mobile, Honeywell Voyager 1602g

## 3. Mobile Phone as Scanner (NEW)
- Use phone camera as wireless scanner
- No additional hardware needed
- Perfect for inventory/warehouse
- Cross-platform (any phone with camera)

**Implementation:** `lib/modules/settings/pages/barcode_scanner_config_page.dart`

---

# 🔄 Key Business Logic Patterns

## Invoice → Journal Entry Flow

**Sales Invoice:**
1. User creates invoice → `sales_invoices` INSERT
2. Trigger `trg_sales_invoices_change` fires
3. Calls `handle_sales_invoice_change()`
4. If posted → creates journal entry with:
   - DEBIT: Cuentas por Cobrar (1130)
   - CREDIT: Ventas (4101) + IVA Débito (2110)
5. Deducts inventory via `consume_sales_invoice_inventory()`

**Purchase Invoice:**
1. User creates invoice → `purchase_invoices` INSERT
2. Trigger `trg_purchase_invoices_change` fires
3. If posted → creates journal entry with:
   - DEBIT: Expense account + IVA Crédito (2120)
   - CREDIT: Cuentas por Pagar (2101)
4. Increases inventory via `consume_purchase_invoice_inventory()`

**Payment Recording:**
- Trigger on `sales_payments`/`purchase_payments` INSERT
- Creates journal entry:
  - DEBIT: Payment method account (Caja/Banco)
  - CREDIT: Cuentas por Cobrar/Pagar
- Updates invoice `paid_amount` and `status`

## Mechanic Job (Pega) → Invoice Flow

**Location:** `lib/modules/bikeshop/services/bikeshop_service.dart`

1. Mechanic completes job with parts + labor
2. Job status = 'completed' or 'ready_for_delivery'
3. User clicks "Generate Invoice"
4. System creates `sales_invoice` with:
   - Line items from `mechanic_job_parts` (products used)
   - Labor line item from `mechanic_jobs.labor_cost`
   - Customer from `mechanic_jobs.customer_id`
   - Links invoice back: `mechanic_jobs.invoice_id = invoice.id`
5. Invoice posting triggers accounting entries (see above)

**Bidirectional Cascade Delete:**
- Deleting pega → deletes invoice (trigger: `cascade_delete_pega_invoice`)
- Deleting invoice → deletes pega (same trigger)
- Prevents orphaned records

---

# 🎨 UI/UX Standards

## Calendar/Timeline Views

- Use **flutter_calendar_carousel** for month view
- Color coding by status (pending, in_progress, completed)
- Click event → detail panel (split view on desktop, modal on mobile)
- Show bike brand/model instead of internal codes
- Timeline items sorted by date DESC

## Form Validation

- Required fields marked with red asterisk (*)
- Real-time validation on blur
- Error messages below field (red text)
- Success messages via SnackBar (green)
- Prevent submit if validation fails

## Responsive Design

- Desktop (>900px): Sidebar + content area
- Tablet (600-900px): Collapsible drawer
- Mobile (<600px): Bottom navigation + hamburger menu
- Tables adapt to cards on mobile
- Forms stack vertically on narrow screens

## Loading States

- Show CircularProgressIndicator while fetching data
- Skeleton loaders for lists (shimmer effect)
- Disable buttons during async operations
- Display "No data" message if results empty

---

# 🔐 Row Level Security (RLS) Best Practices

## Policy Template (Copy-Paste for New Tables)

```sql
-- Enable RLS
alter table table_name enable row level security;

-- Drop old policies
drop policy if exists "table_select" on table_name;
drop policy if exists "table_insert" on table_name;
drop policy if exists "table_update" on table_name;
drop policy if exists "table_delete" on table_name;

-- Create new policies
create policy "table_select" on table_name
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "table_insert" on table_name
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "table_update" on table_name
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "table_delete" on table_name
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());
```

**CRITICAL:** Always include `to authenticated` or policy defaults to public role (bypasses RLS)!

---

# 📝 Naming Conventions

## Database

- Tables: `snake_case` plural (e.g., `sales_invoices`, `mechanic_jobs`)
- Columns: `snake_case` (e.g., `invoice_number`, `total_amount`)
- Functions: `snake_case` (e.g., `create_sales_invoice_journal_entry`)
- Triggers: `trg_<table>_<action>` (e.g., `trg_sales_invoices_change`)
- Indexes: `idx_<table>_<column>` (e.g., `idx_products_tenant`)
- Foreign keys: `<table_singular>_id` (e.g., `customer_id`, `product_id`)

## Flutter/Dart

- Classes: `PascalCase` (e.g., `SalesInvoice`, `BikeshopService`)
- Files: `snake_case` (e.g., `sales_invoice.dart`, `bikeshop_service.dart`)
- Variables/functions: `camelCase` (e.g., `getTenantId()`, `invoiceNumber`)
- Constants: `lowerCamelCase` (e.g., `defaultCurrency = 'CLP'`)
- Private members: prefix with `_` (e.g., `_tenantId`, `_loadData()`)

## SQL Variables

- Prefix with `v_` for local variables (e.g., `v_tenant_id`, `v_total`)
- Prefix with `p_` for parameters (e.g., `p_invoice_id`, `p_tenant_id`)

---

# 🧪 Testing Multi-Tenant Isolation

```sql
-- Verify RLS is working
SELECT 
  schemaname, 
  tablename, 
  rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename NOT LIKE 'pg_%'
ORDER BY tablename;
-- All tenant tables should have rowsecurity = true

-- Check policies exist
SELECT tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE tablename = 'your_table_name';
-- Should show 4 policies (SELECT, INSERT, UPDATE, DELETE) with {authenticated} role

-- Test data isolation
SELECT * FROM your_table WHERE tenant_id = public.user_tenant_id();
-- Should only return current user's tenant data
```

**Never test in SQL Editor with service role** - it bypasses RLS! Always test from Flutter app as authenticated user.