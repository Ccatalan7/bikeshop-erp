# 🧠 Project Overview

This is a **MULTI-TENANT SaaS ERP** for managing bikeshops. Multiple independent businesses use the same app with **COMPLETE DATA ISOLATION**. It includes accounting, inventory, POS, customer management, maintenance tracking, HR, website builder, marketing, and analytics. Built in **Flutter/Dart**, targeting **Windows, Android, Web**, and optionally macOS/iOS.

The backend uses Supabase exclusively, with PostgreSQL as the relational database, Supabase Auth for authentication (including OAuth2 support like Google login), and Supabase Storage for file management. All business logic follows an accounting-first approach, with audit-ready data structures and strong relational integrity across modules.

---

# 🗄️ SUPABASE PROJECT CONFIGURATION

**⚠️ NEVER GUESS THESE VALUES - THEY ARE DOCUMENTED HERE!**

## Project Details

| Field | Value |
|-------|-------|
| **Project URL** | `https://xzdvtzdqjeyqxnkqprtf.supabase.co` |
| **Project ID** | `xzdvtzdqjeyqxnkqprtf` |
| **Region** | AWS US West 1 |
| **Database Host** | `aws-0-us-west-1.pooler.supabase.com` |
| **Database Port** | `6543` (pooler) / `5432` (direct) |

## Connection Strings

**Pooler Connection (recommended for most operations):**
```
postgresql://postgres.xzdvtzdqjeyqxnkqprtf:[PASSWORD]@aws-0-us-west-1.pooler.supabase.com:6543/postgres
```

**Direct Connection (for migrations/schema changes):**
```
postgresql://postgres:[PASSWORD]@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres
```

## Important Tenant IDs

| Tenant | UUID | Description |
|--------|------|-------------|
| **Viñabike (Production)** | `5443b130-cc28-45af-a420-cd500b288890` | Primary business account, used for testing and production |

## Viñabike Business Info (for SEO/index.html)

| Field | Value |
|-------|-------|
| **Business Name** | Vinabike |
| **Address** | Álvarez 32, Local 17, Viña del Mar, Chile |
| **Phone** | +56998357797 |
| **Email** | vinabikechile@gmail.com |
| **Website** | https://vinabike.cl |

**⚠️ NEVER use placeholder data (like "contacto", "XXXX", "test") in index.html SEO content!**

## Storage Buckets

- `products` - Product images
- `website` - Website builder assets (blocks, logos, banners)
- `documents` - Business documents (invoices, reports)

## API Endpoints

- **REST API:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/`
- **Auth API:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co/auth/v1/`
- **Storage API:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/`
- **Realtime:** `wss://xzdvtzdqjeyqxnkqprtf.supabase.co/realtime/v1/`

## When Running Database Queries

**⚠️ IMPORTANT: Use REST API with Service Role Key (psql connection is unreliable)**

The database password for psql may change. Use the **REST API with service role key** instead:

```bash
# ✅ CORRECT: Use REST API with service role key from .env
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/TABLE_NAME?select=*" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq .

# ✅ EXAMPLE: Query website_pages for Viñabike tenant
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/website_pages?tenant_id=eq.5443b130-cc28-45af-a420-cd500b288890&select=id,slug,title" \
  -H "apikey: $(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d= -f2)" \
  -H "Authorization: Bearer $(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d= -f2)" | jq .

# ❌ AVOID: psql connection (password issues)
# psql "postgresql://postgres.xzdvtzdqjeyqxnkqprtf:..."  # Often fails with "Tenant or user not found"
```

**Service Role Key Location:** `.env` file → `SUPABASE_SERVICE_ROLE_KEY`

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
- ✅ **ALLOWED:** You may create standalone .sql files (e.g. `supabase/migrations/YYYYMMDD_name.sql`) for specific deployments to avoid running the entire schema, BUT you must ALSO update `core_schema.sql` as the source of truth.

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
5. ✅ **PRESENT in a canvas artifact** OR **CREATE a standalone SQL file** (e.g. `supabase/migrations/20251221_fix_name.sql`)
6. ✅ Include clear instructions: "Copy this SQL and run it in Supabase SQL Editor" or "Run the migration file"

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

# 🚨🚨🚨 WEB DEPLOYMENT: SPLIT BUILD (CRITICAL - READ CAREFULLY!) 🚨🚨🚨

**⚠️⚠️⚠️ THE PUBLIC STORE AND ERP USE DIFFERENT ENTRY POINTS! ⚠️⚠️⚠️**

**IF YOU BUILD THE STORE WRONG, IT WILL BE 9MB INSTEAD OF 4MB = SLOW LOAD TIMES!**

## The Two Builds (MEMORIZE THIS!)

| Target | Entry Point | Bundle Size | Firebase URL |
|--------|-------------|-------------|--------------|
| **PUBLIC STORE** | `lib/main_store.dart` | **~4.1 MB** ✅ | `vinabike-store.web.app` |
| **ERP ADMIN** | `lib/main.dart` | ~9.2 MB | `project-vinabike.web.app` |

## ✅ CORRECT Build Commands

```bash
# ⚠️ STORE: MUST use -t lib/main_store.dart!!!
flutter build web --release -t lib/main_store.dart -o build/web_store

# ERP: Uses default main.dart
flutter build web --release -o build/web_erp
```

## ❌ WRONG Build Commands (WILL BREAK THE STORE!)

```bash
# ❌ WRONG - This uses main.dart = 9MB bundle on store!
flutter build web --release
cp -R build/web/ build/web_store/

# ❌ WRONG - Missing the entry point flag!
flutter build web --release -o build/web_store

# ❌ WRONG - --web-renderer flag doesn't exist anymore
flutter build web --release --web-renderer html -t lib/main_store.dart
```

## Verification (DO THIS EVERY TIME!)

After building the store, ALWAYS verify the bundle size:
```bash
ls -lh build/web_store/main.dart.js
# ✅ CORRECT: ~4.1MB
# ❌ WRONG:  ~9.2MB (you used wrong entry point!)
```

## Firebase Hosting Configuration

Defined in `firebase.json`:
- Target `store` → builds from `build/web_store/` → deploys to `vinabike-store.web.app`
- Target `erp` → builds from `build/web_erp/` → deploys to `project-vinabike.web.app`

## Full Deployment Workflow

See `.agent/workflows/deploy_to_firebase.md` for the complete deployment steps including:
1. SEO sync (`./scripts/sync_seo_index.sh`)
2. Store build (with correct entry point)
3. ERP build
4. Firebase deploy

## Why This Matters

| Scenario | Bundle Size | Mobile Load (4G) | User Experience |
|----------|-------------|------------------|-----------------|
| ✅ Correct build (`main_store.dart`) | 4.1 MB | ~2-3 seconds | Fast, happy users |
| ❌ Wrong build (`main.dart`) | 9.2 MB | ~6-8 seconds | Slow, frustrated users |

**The wrong build includes ALL ERP modules (accounting, HR, inventory management, etc.) that public store visitors DON'T NEED!**

## Files Involved

- `lib/main_store.dart` - Lightweight entry point (public store only)
- `lib/main.dart` - Full entry point (all ERP modules)
- `lib/public_store/routes/public_store_router.dart` - Store-specific routes
- `lib/shared/routes/app_router.dart` - Full ERP routes
- `.agent/workflows/deploy_to_firebase.md` - Deployment workflow
- `firebase.json` - Hosting target configuration

---

# 📦 BUNDLE SIZE OPTIMIZATION (CRITICAL - PREVENTS 6MB+ BLOAT!)

**⚠️ ADDING THE WRONG PACKAGE OR IMPORT CAN INSTANTLY DOUBLE YOUR BUNDLE SIZE!**

## Target Bundle Sizes

| Build | Expected Size | Bloated Size | Status |
|-------|---------------|--------------|--------|
| **Store** (`main_store.dart`) | **~4.1 MB** | 10-11 MB | ❌ BROKEN if > 5MB |
| **ERP** (`main.dart`) | **~5.2 MB** | 9+ MB | ⚠️ Check if > 6MB |

## 🚨 BANNED PACKAGES (DO NOT IMPORT IN STORE-REACHABLE CODE!)

These packages add MEGABYTES to the bundle even if you only use one function:

| Package | Bundle Bloat | Why It's Heavy | Alternative |
|---------|--------------|----------------|-------------|
| `google_fonts` | **+6.5 MB** | Contains metadata for ALL 1000+ Google Fonts | Use CSS `font-family` directly |
| `firebase_analytics` | +2-3 MB | Full Firebase SDK | Use web analytics via JS |
| `flutter_map` | +2 MB | Mapping libraries | Use static map images or WebView |

## The `google_fonts` Disaster (Real Incident - Jan 2025)

**What happened:** Added `google_fonts` package to apply custom fonts in website builder.

**Result:** Store bundle jumped from 4.1MB → 11MB (170% increase!)

**Root cause:** `google_fonts` package includes metadata for ALL 1000+ Google Fonts, even if you only use one font. The metadata alone is ~6.5MB.

**The fix:** Use CSS `font-family` directly instead of `GoogleFonts.getFont()`:

```dart
// ❌ WRONG - Adds 6.5MB to bundle!
import 'package:google_fonts/google_fonts.dart';

TextStyle getStyle(String fontFamily) {
  return GoogleFonts.getFont(fontFamily);  // Pulls in ALL font metadata
}

// ✅ CORRECT - Zero bundle impact!
TextStyle getStyle(String fontFamily, TextStyle base) {
  return base.copyWith(fontFamily: fontFamily);  // CSS font-family applied
}

// ✅ CORRECT for TextTheme
TextTheme getTextTheme(String fontFamily, TextTheme base) {
  return base.apply(fontFamily: fontFamily);  // CSS font-family applied
}
```

**How fonts still work:** Browser loads fonts from Google Fonts CDN via `<link>` tags in `index.html` or `@font-face` CSS rules. The font NAME is applied via CSS `font-family`, not the Dart package.

## Files That MUST NOT Import Heavy Packages

These files are in the store's dependency tree. Heavy imports here bloat the store:

```
lib/modules/website/widgets/website_block_renderer.dart     ← Renders store blocks
lib/modules/website/widgets/editable_block_renderer.dart    ← Edit mode blocks
lib/modules/website/theme/website_theme_builder.dart        ← Theme application
lib/public_store/widgets/public_store_layout.dart           ← Store layout wrapper
lib/public_store/pages/*.dart                               ← All store pages
```

## Before Adding ANY New Package

**MANDATORY CHECKLIST:**

1. ✅ **Check package size:** Look at pub.dev for package size indicators
2. ✅ **Check if store needs it:** If only ERP uses it, import ONLY in ERP files
3. ✅ **Test bundle size BEFORE committing:**
   ```bash
   flutter build web --release -t lib/main_store.dart -o build/web_test
   ls -lh build/web_test/main.dart.js
   # Must be ~4.1MB, not higher!
   ```
4. ✅ **Consider alternatives:**
   - Can you use a web-only solution (CSS, JS)?
   - Can you use a lighter package?
   - Can you implement it yourself in <100 lines?

## Import Hygiene Rules

### Rule 1: Never import ERP modules in store code

```dart
// ❌ WRONG - Pulls ALL ERP modules into store bundle!
import '../../shared/routes/erp_routes_barrel.dart';

// ✅ CORRECT - Navigate to ERP via URL, don't import
context.go('/erp/some-page');
```

### Rule 2: Use conditional/deferred imports for heavy features

```dart
// ✅ Deferred import - only loads when actually used
import 'heavy_feature.dart' deferred as heavy;

Future<void> useHeavyFeature() async {
  await heavy.loadLibrary();
  heavy.doSomething();
}
```

### Rule 3: Check what your imports import

A single import can cascade into hundreds of files. Before adding an import:
```bash
# Check what a file imports
grep -r "^import" lib/path/to/file.dart

# Check if a package is used in store-reachable code
grep -r "package:heavy_package" lib/public_store/ lib/modules/website/
```

## Bundle Size Regression Testing

**After ANY change to website or public_store modules:**

```bash
# Quick bundle size check
flutter build web --release -t lib/main_store.dart -o build/web_check
ls -lh build/web_check/main.dart.js

# Expected output:
# -rw-r--r--  4.1M  main.dart.js  ✅ GOOD
# -rw-r--r--  10.8M main.dart.js  ❌ REGRESSION! Find and remove heavy import
```

## Debugging Bundle Size Increases

If bundle size suddenly increases:

1. **Find the commit that broke it:**
   ```bash
   git log --oneline -20
   # Binary search through commits, building and checking size
   ```

2. **Check for new imports:**
   ```bash
   git diff HEAD~5 --stat | grep -E "\.dart$"
   # Look at changed files for new imports
   ```

3. **Check for new packages:**
   ```bash
   git diff HEAD~5 pubspec.yaml
   # Look for added dependencies
   ```

4. **Use bundle analyzer (advanced):**
   ```bash
   flutter build web --release -t lib/main_store.dart --source-maps
   # Analyze with source-map-explorer or similar tool
   ```

## Summary: The Golden Rules

1. ⛔ **NEVER** use `google_fonts` package - use CSS `font-family` instead
2. ⛔ **NEVER** import ERP barrels in store code
3. ✅ **ALWAYS** check bundle size after modifying website/store code
4. ✅ **ALWAYS** verify store is ~4.1MB before deploying
5. 🔍 **INVESTIGATE** immediately if bundle exceeds 5MB

---


# 🔍 SEO & WEBSITE ARCHITECTURE (CRITICAL FOR GOOGLE MERCHANT CENTER)

**⚠️ UNDERSTANDING THIS ARCHITECTURE IS CRITICAL FOR GOOGLE MERCHANT CENTER APPROVAL!**

## Overview: 3 Data Layers

The website has THREE layers of data that must stay in sync:

```
┌─────────────────────────────────────────────────────────────────┐
│                     1. STATIC INDEX.HTML                        │
│  (What Google bot sees BEFORE Flutter loads - ~500ms window)   │
├─────────────────────────────────────────────────────────────────┤
│  Location: web/index.html                                       │
│  Synced via: scripts/sync_seo_index.sh (runs before deploy)    │
│  Contains: meta tags, JSON-LD schema, contact info, legal links│
│  ⚠️ MUST match database values or Google rejects!              │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ sync_seo_index.sh
                              │
┌─────────────────────────────────────────────────────────────────┐
│                 2. WEBSITE_SETTINGS TABLE (DB)                  │
│         (Central source of truth for site-wide settings)       │
├─────────────────────────────────────────────────────────────────┤
│  Key Settings:                                                  │
│  - contact_email, contact_phone, contact_address                │
│  - store_name, store_description                                │
│  - meta_title, meta_description, meta_keywords                  │
│  - facebook, instagram, twitter, youtube, whatsapp              │
│  - theme_*, header_*, logo_url                                  │
│                                                                 │
│  Accessed via: WebsiteService.getSetting('key', 'default')      │
│  Saved via: WebsiteService.saveSettings({'key': 'value'})       │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────────┐
│                3. WEBSITE_PAGES TABLE (DB)                      │
│             (Per-page SEO - each page has its own!)             │
├─────────────────────────────────────────────────────────────────┤
│  Per-Page Fields:                                               │
│  - slug (URL path: 'productos', 'devoluciones', etc.)          │
│  - title (browser tab title)                                    │
│  - meta_title (SEO title - can differ from title)               │
│  - meta_description (SEO description for this page)             │
│  - meta_keywords (page-specific keywords)                       │
│  - og_image_url (social sharing image for this page)           │
│  - is_published (whether page is live)                          │
│                                                                 │
│  ⚠️ ALL 9 pages need SEO configured, not just home!            │
└─────────────────────────────────────────────────────────────────┘
```

## Current Pages (Viñabike)

| Page | Slug | SEO Status | Notes |
|------|------|------------|-------|
| Inicio | `inicio` | NEEDS CHECK | Home page, uses site-wide meta |
| Productos | `productos` | NEEDS CHECK | Product catalog |
| Contacto | `contacto` | NEEDS CHECK | Contact page |
| Sobre Nosotros | `nosotros` | NEEDS CHECK | About page |
| Términos y Condiciones | `terminos` | NEEDS META | Legal page |
| Política de Privacidad | `privacidad` | NEEDS META | Legal page |
| Política de Devoluciones | `devoluciones` | NEEDS META | Legal page (refund) |
| Información de Envíos | `envios` | NEEDS META | Legal page (shipping) |

## Where Data Flows

### Website Footer/Header (LIVE)
- **Source:** `website_settings` table
- **Read by:** `public_store_layout.dart` lines 167-179
- **Keys used:**
  ```dart
  contactEmail = websiteService.getSetting('contact_email', '');
  contactPhone = websiteService.getSetting('contact_phone', '');
  contactAddress = websiteService.getSetting('contact_address', '');
  ```

### Editor Footer Controls (ERP)
- **Location:** `lib/modules/website/widgets/website_editor_panel.dart` (lines ~9198-9410)
- **Source:** Same `website_settings` table
- **Wiring:** `_FooterBlockControlsState._loadSettings()` reads, `_saveSettings()` writes
- **Keys:** Same `contact_email`, `contact_phone`, `contact_address`
- ✅ **NOT mock data** - Editor IS properly wired to database!

### Static index.html (for Google Bot)
- **Location:** `web/index.html`
- **Synced by:** `scripts/sync_seo_index.sh`
- **When synced:** Before every `flutter build web` (in deploy workflow)
- **Contains:**
  - Phone, email, address in hidden SEO div
  - JSON-LD LocalBusiness schema
  - Open Graph meta tags
  - Legal page links (refund, terms, privacy, shipping)

## The Sync Script

**File:** `scripts/sync_seo_index.sh`

**What it does:**
1. Fetches settings from Supabase `website_settings` table
2. Regenerates `web/index.html` with correct values
3. Injects JSON-LD schema, Open Graph, Twitter Cards
4. Adds legal page links

**When it runs:**
- Step 1 of `/deploy_to_firebase` workflow
- Must run BEFORE `flutter build web`

**API used:**
```bash
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/website_settings?tenant_id=eq.${TENANT_ID}&select=key,value"
```

## SEO Settings Page

**Location:** `lib/modules/website/pages/seo_settings_page.dart`

**Route:** `/website/seo`

**What it manages:**
1. Business Info (name, phone, email, full address)
2. Meta Tags (title, description, keywords)
3. Legal Pages (URLs for refund, terms, shipping, privacy)
4. Open Graph (social sharing)
5. Twitter Cards
6. Structured Data (JSON-LD toggles)
7. Analytics (GA, FB Pixel, GTM IDs)

**Key sync behavior:**
- Writes to BOTH `seo_*` prefixed keys AND legacy keys
- Example: Saves `seo_phone` AND `contact_phone` for backward compatibility

## Critical Sync Rules

### ✅ DO
1. Always run sync script before deploy
2. Check ALL pages have SEO configured (not just home)
3. Use SEO Settings page (`/website/seo`) as primary editor
4. Verify legal pages are published AND have meta descriptions

### ❌ DON'T
1. Edit `web/index.html` directly (will be overwritten by sync script)
2. Assume changes are live without deploying
3. Forget that legal pages ALSO need SEO (meta_title, meta_description)
4. Use placeholder data ("+56 9 contacto", "test@test.com")

## Debugging SEO Issues

**If Google Merchant Center rejects:**
1. Check `web/index.html` has correct phone/email (not placeholders)
2. Check ALL 4 legal page links exist in index.html
3. Check legal pages are published (`is_published: true`)
4. Run sync script and redeploy
5. Test with Google Rich Results Test

**If footer shows wrong info:**
1. Check `website_settings` table for `contact_email`, `contact_phone`
2. Verify WebsiteService loaded settings correctly
3. Check for cached data (hard refresh browser)

**If editor changes don't reflect:**
1. Editor DOES save to database (verified)
2. Check save confirmation (green snackbar)
3. Hard refresh the public store page
4. Check browser console for errors

## Per-Page SEO Checklist

For EACH page in `website_pages`, verify:
- [ ] `meta_title` is set (max 60 chars)
- [ ] `meta_description` is set (max 160 chars)
- [ ] `meta_keywords` has relevant terms
- [ ] `og_image_url` has a social sharing image
- [ ] `is_published` is `true`

**Command to check per-page SEO:**
```bash
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/website_pages?tenant_id=eq.5443b130-cc28-45af-a420-cd500b288890&select=slug,meta_title,meta_description,is_published" \
  -H "apikey: $(grep SUPABASE_ANON_KEY lib/shared/config/supabase_config.dart | cut -d\"'\" -f2)" | jq '.'
```

---

# 🔐 AUTHENTICATION, ROLES & PERMISSIONS

**Traceability and granular access control are core to this ERP.**

## 1. Role System (`user_profiles`)
Users are assigned roles in the `user_profiles` table. Logic must respect these hierarchies:
- **`owner`**: Full access to everything in tenant. Can manage subscription.
- **`admin`**: Full access to tenant operations.
- **`manager`**: Can override limits, approve voids, view sensitive financial reports.
- **`employee`**: Standard operational access (POS, Workshops, CRM).
- **`mechanic`**: specialized access for Work Orders and Maintenance.

**Checking Roles:**
- In SQL: `EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role IN ('admin', 'manager'))`
- In Flutter: `context.read<AuthProvider>().role`

## 2. Traceability Requirements (Audit Trail)
Every action must be traceable to a specific user. Anonymous operations are forbidden for business data.

### Database Columns
**ALL** transactional and business logic tables (invoices, payments, work_orders, stock_movements, chats) MUST have:
- `created_by uuid references auth.users(id) default auth.uid()`
- `updated_by uuid references auth.users(id)` (if mutable)

### Performance & Metrics
We key analytics off these columns. When building features:
- **Sales by User**: Aggregated from `sales_invoices.created_by`.
- **Productivity**: Tasks/Work Orders completed by user.
- **Commissions**: Calculated based on `created_by` or dedicated `sales_rep_id` column.

## 3. Permission Implementation Layers
1. **RLS (Row Level Security)**:
   - **MANDATORY** for Tenant Isolation (`tenant_id`).
   - Used for basic "Employee vs Customer" data visibility.
2. **RPC / Database Functions** (`SECURITY DEFINER`):
   - **CRITICAL**: Checks roles explicitly inside the function.
   - Example: `delete_conversation` allows Participants OR Admins.
   - *Never rely on RLS alone for destructive RPCs.*
3. **UI State (Flutter)**:
   - Hide/Disable buttons based on role.
   - Use `PermissionGate` widgets where available.

## 4. Best Practices for New Features
1. **Never trust the client**: Verify permissions in the backend (RLS or Function).
2. **Auto-fill User**: Use `default auth.uid()` for `created_by` in new tables.
3. **Log Destructive Actions**: Deleting invoices, voiding payments, or changing critical configs must be logged to `activity_logs`.
4. **Explicit Overrides**: If a regular user needs to perform a Manager action, implement an "Admin Override" flow (ask for admin PIN/Credentials).

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

**⚠️ CRITICAL: Split-Pane Layout - When to Use**

**Use split-pane ONLY for these specific scenarios:**
- ✅ **List+Detail modules** where user frequently switches between items (invoices, customers, products, accounts)
- ✅ **High-frequency editing** where keeping context visible speeds up workflow
- ✅ **Desktop-focused** modules with complex detail panels

**DO NOT use split-pane for:**
- ❌ **CRUD forms** with create/edit dialogs (medical leaves, contracts, employees, attendance)
- ❌ **Dashboards** or analytics pages
- ❌ **Reports** or read-only views (F29, financial reports)
- ❌ **Settings** or configuration pages
- ❌ **Simple list pages** where detail view doesn't need persistent visibility
- ❌ **Wizards** or multi-step forms

**Reference Implementations:**
- **With split-pane:** `lib/modules/sales/pages/invoice_list_page.dart` (list+detail pattern)
- **Without split-pane:** `lib/modules/hr/pages/medical_leaves_page.dart` (CRUD with dialogs)

**Reference Implementations:**
- **With split-pane:** `lib/modules/sales/pages/invoice_list_page.dart` (list+detail pattern)
- **Without split-pane:** `lib/modules/hr/pages/medical_leaves_page.dart` (CRUD with dialogs)

**Reference Implementation:** `lib/modules/sales/pages/invoice_list_page.dart`

**⚠️ MANDATORY: All pages MUST use `MainLayout` to preserve navigation pane!**

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

# 🚀 PERFORMANCE OPTIMIZATION: SERVICE-LEVEL CACHING

**CRITICAL: Implemented Dec 1, 2025 for Taller module - APPLY TO ALL MODULES**

## The Problem

Navigation between pages in the same module feels slow because:
- Every page calls `_loadData()` on init
- Every `_loadData()` fetches from database
- Even switching between tabs/pages in same module causes full reload
- Users see loading spinners constantly

## The Solution: Service-Level Caching

Cache data at the **service layer** so pages can:
1. Show cached data **instantly** (no loading spinner)
2. Fetch fresh data in background
3. Invalidate cache only when data actually changes

## Implementation Pattern

### 1. Add Caching Infrastructure to Service

```dart
class YourModuleService extends ChangeNotifier {
  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<YourModel>? _cachedItems;
  DateTime? _itemsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  
  // Loading state flag to prevent concurrent fetches
  bool _isLoadingItems = false;
  
  // Public getters for cached data (instant access)
  List<YourModel> get cachedItems => _cachedItems ?? [];
  bool get hasItemsCache => _cachedItems != null;
  
  /// Check if cache is still valid
  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }
  
  /// Invalidate cache (call after create/update/delete)
  void invalidateItemsCache() {
    _cachedItems = null;
    _itemsCacheTime = null;
  }
}
```

### 2. Update Fetch Methods to Use Cache

```dart
Future<List<YourModel>> getItems({
  String? filterParam,
  bool forceRefresh = false,
}) async {
  // Check if this is a filtered query (don't use cache for filtered results)
  final isFilteredQuery = filterParam != null && filterParam.isNotEmpty;
  
  // Return cached data if valid and not a filtered query
  if (!forceRefresh && !isFilteredQuery && _isCacheValid(_itemsCacheTime) && _cachedItems != null) {
    debugPrint('📦 [YourService] Using cached items (${_cachedItems!.length} items)');
    return _cachedItems!;
  }
  
  // Prevent concurrent fetches
  if (_isLoadingItems && !isFilteredQuery) {
    debugPrint('⏳ [YourService] Already loading items, waiting...');
    while (_isLoadingItems) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (_cachedItems != null && !isFilteredQuery) return _cachedItems!;
  }
  
  try {
    if (!isFilteredQuery) _isLoadingItems = true;
    
    // Fetch from database...
    final data = await _fetchFromDatabase(filterParam);
    
    // Cache only unfiltered results
    if (!isFilteredQuery) {
      _cachedItems = data;
      _itemsCacheTime = DateTime.now();
      debugPrint('✅ [YourService] Cached ${data.length} items');
    }
    
    return data;
  } finally {
    if (!isFilteredQuery) _isLoadingItems = false;
  }
}
```

### 3. Add Cache Invalidation to ALL CRUD Methods

```dart
Future<YourModel> createItem(YourModel item) async {
  final data = await _db.insert('your_table', item.toJson());
  invalidateItemsCache();  // ⚠️ CRITICAL: Invalidate after mutation
  notifyListeners();
  return YourModel.fromJson(data);
}

Future<YourModel> updateItem(YourModel item) async {
  final data = await _db.update('your_table', item.id!, item.toJson());
  invalidateItemsCache();  // ⚠️ CRITICAL: Invalidate after mutation
  notifyListeners();
  return YourModel.fromJson(data);
}

Future<void> deleteItem(String id) async {
  await _db.delete('your_table', id);
  invalidateItemsCache();  // ⚠️ CRITICAL: Invalidate after mutation
  notifyListeners();
}
```

### 4. Update Page `_loadData()` to Use Cache for Instant Render

```dart
Future<void> _loadData() async {
  // 🚀 INSTANT RENDER: Show cached data immediately if available
  if (_yourService.hasItemsCache && _items.isEmpty) {
    setState(() {
      _items = _yourService.cachedItems;
      _filteredItems = _items;
      _isLoading = false;  // No loading spinner!
    });
    _applyFiltersAndSort();
  } else {
    setState(() => _isLoading = true);
  }
  
  try {
    // Fetch fresh data (will use cache if still valid)
    final items = await _yourService.getItems();
    
    if (mounted) {
      setState(() {
        _items = items;
        _filteredItems = items;
        _isLoading = false;
      });
      _applyFiltersAndSort();
    }
  } catch (e) {
    if (mounted) {
      setState(() => _isLoading = false);
      // Show error...
    }
  }
}
```

## Reference Implementation

**Services WITH Caching (Production-Ready as of Dec 1, 2025):**

| Service | Cache Variables | Preloaded on Login |
|---------|-----------------|---------------------|
| `BikeshopService` | `_cachedJobs`, `_cachedBikes` | ✅ Yes |
| `CustomerService` | `_customersCache` | ✅ Yes |
| `InventoryService` | `_productsCache` | ✅ Yes |
| `CategoryService` | `_categoriesCache` | ✅ Yes |
| `BrandService` | `_brandsCache` | ✅ Yes |
| `SalesService` | `_invoices`, `_payments` | ✅ Yes |
| `PurchaseService` | `_invoiceCache`, `_supplierCache` | ✅ Yes |
| `HRService` | `_employeesCache`, `_departmentsCache` | ✅ Yes |

**Pages WITH Instant Render:**
- `pegas_list_page.dart` - Shows cached jobs instantly
- `pegas_table_page.dart` - Shows cached jobs instantly
- `customer_list_page.dart` - Shows cached customers instantly
- `product_list_page.dart` - Shows cached products instantly
- `category_list_page.dart` - Shows cached categories instantly
- `brand_list_page.dart` - Shows cached brands instantly
- `invoice_list_page.dart` - Uses Provider.watch pattern with cached data
- `purchase_invoice_list_page.dart` - Uses Provider.watch with cached data
- `employee_list_page.dart` - Shows cached employees instantly
- `supplier_list_page.dart` - Shows cached suppliers instantly

**DataPreloadService** (`lib/shared/services/data_preload_service.dart`):
- Initializes after authentication
- Preloads ALL cached data in parallel on login
- Reduces first navigation time from ~500ms to ~50ms

## Cache Configuration

| Setting | Value | Reason |
|---------|-------|--------|
| `_cacheMaxAge` | 5 minutes | Balance between freshness and performance |
| Concurrent fetch wait | 50ms polling | Prevent duplicate requests |
| Filtered queries | Always fetch | Filters may not match cache |

## When to Apply This Pattern

**APPLY TO:**
- ✅ Any module with list pages (inventory, sales, purchases, CRM, HR)
- ✅ Services that are called frequently during navigation
- ✅ Data that doesn't change every second

**DO NOT APPLY TO:**
- ❌ Realtime data (use Supabase realtime subscriptions instead)
- ❌ Dashboard/analytics (always show fresh data)
- ❌ Single-record fetches (getById) - no benefit

## Checklist for New Modules

When creating a new module:

1. ✅ **Add cache variables** to service: `_cachedItems`, `_itemsCacheTime`, `_isLoadingItems`
2. ✅ **Add public getters**: `cachedItems`, `hasItemsCache`
3. ✅ **Add invalidation method**: `invalidateItemsCache()`
4. ✅ **Update fetch method** with cache logic (see pattern above)
5. ✅ **Add invalidation calls** to ALL CRUD methods (create, update, delete, softDelete, restore)
6. ✅ **Update page `_loadData()`** to show cached data instantly
7. ✅ **Add service to DataPreloadService** for preloading on login
8. ✅ **Test navigation** - should feel instant, no loading spinners on second visit

## Services Pending Optimization

These services may benefit from caching if frequently used:

- ⏳ `AccountingService` → Chart of accounts, Journal entries (large datasets)
- ⏳ `StockMovementsService` → Stock movement history
- ⏳ `SmartTaskService` → Task templates

## Debugging Cache

Add these debug prints to track cache behavior:

```dart
debugPrint('📦 Using cached items');      // Cache hit
debugPrint('⏳ Already loading, waiting'); // Concurrent fetch prevented
debugPrint('✅ Cached ${items.length}');   // Cache stored
debugPrint('🗑️ Cache invalidated');        // After mutation
```

---

# 🖼️ SPACE MANAGEMENT & RESPONSIVE UI PATTERNS

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

# 🏪 BUSINESS DATA - VIÑABIKE (Primary Tenant)

**Use this data whenever creating content, policies, or UI that references the business:**

| Campo | Valor |
|-------|-------|
| **Nombre comercial** | Viñabike |
| **Dirección** | Álvarez 32, Local 17 |
| **Código postal** | 2520000 |
| **Ciudad** | Viña del Mar |
| **Región** | Valparaíso |
| **País** | Chile |
| **Teléfono** | +56 9 9835 7797 |
| **Email** | vinabikechile@gmail.com |
| **Métodos de pago web** | Mercado Pago, Transferencia bancaria |
| **Horario** | Lunes a Viernes 10:00 - 19:00, Sábado 10:00 - 14:00 |
| **Subdomain** | vinabike |

**⚠️ IMPORTANT:**
- Use Spanish terminology: "Región" (not "Estado"), "Código postal" (not "ZIP code")
- Format phone as `+56 9 XXXX XXXX` (Chilean mobile format)
- Currency always in CLP with proper thousand separators: `$49.990`

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

# 🌐 Website Builder - COMPLETE ARCHITECTURE

**CRITICAL: The Website Builder is a visual, block-based CMS. ALL content must be editable through the UI - NEVER hardcode content in code or SQL!**

---

## 🚨 CRITICAL: EDITOR ARCHITECTURE (Dec 2025)

**There is ONE editor system - the INLINE EDITOR. No other editor exists.**

### The Inline Editor System

The website is edited **inline** - users see the actual website preview and click elements to edit them. A side panel provides additional editing tools.

**Core Components:**

| File | Purpose | Lines |
|------|---------|-------|
| `lib/public_store/widgets/public_store_layout.dart` | Layout wrapper, shows edit button, renders panel | ~1600 |
| `lib/modules/website/widgets/website_editor_panel.dart` | Side panel with tabs: Agregar/Editar/Tema | ~6600 |
| `lib/modules/website/providers/website_edit_mode_provider.dart` | State management for edit mode | ~560 |
| `lib/modules/website/widgets/editable_block_renderer.dart` | Makes blocks clickable/selectable | ~2800 |
| `lib/public_store/pages/public_home_page.dart` | HOME page with full editing support | ~800 |

### How It Works

```
User clicks "Editar Sitio" button
         ↓
public_store_layout.dart calls editProvider.enterPreviewMode()
         ↓
Top bar appears with "Editar" button
         ↓
User clicks "Editar" → editProvider.switchToEditMode()
         ↓
WebsiteEditorPanel appears on right side (dark panel)
         ↓
Blocks become clickable via EditableBlockRenderer
         ↓
Selected block shows in "Editar" tab with field editors
         ↓
User saves → WebsiteService.saveBlocks()
```

### Edit Modes

1. **Normal Mode** (`isEditMode = false`, `isPreviewMode = false`)
   - Regular visitor view
   - "Editar Sitio" floating button visible for logged-in admins

2. **Preview Mode** (`isPreviewMode = true`)
   - Top bar appears with "Editar" button
   - Site looks normal but ready to edit
   - **Activated by:** `/tienda?preview=true` or clicking "Vista Previa" button

3. **Edit Mode** (`isEditMode = true`)
   - Side panel visible (WebsiteEditorPanel)
   - Blocks are clickable/selectable
   - Changes tracked for save
   - **Activated by:** `/tienda?edit=true` or clicking "Abrir Editor" button

### URL Parameters (Dec 2025)

| URL | Mode | What User Sees |
|-----|------|----------------|
| `/tienda` | Normal | Store with "Editar Sitio" FAB (if logged in) |
| `/tienda?preview=true` | Preview | Store with elegant top bar (Publicado toggle, Editar button) |
| `/tienda?edit=true` | Edit | Store with side panel editor (full editing capability) |

### Entry Points from Website Management Page

| Button | Action | Result |
|--------|--------|--------|
| "Vista Previa" | `context.go('/tienda?preview=true')` | Preview mode with top bar |
| "Abrir Editor" | `context.go('/tienda?edit=true')` | Edit mode with side panel |
| "Nueva Pestaña" | `launchUrl('/tienda')` | Opens in new browser tab (no editor) |

---

## ⚠️ KNOWN LIMITATION: Multi-Page Editing (Dec 2025)

**CURRENT STATE: Only HOME page supports inline editing!**

### The Problem

| Page Type | Editing Support | Why |
|-----------|-----------------|-----|
| Home Page (`/tienda`) | ✅ Full editing | Uses `public_home_page.dart` with `EditableBlockRenderer` |
| Policy Pages (`/pagina/:slug`) | ❌ READ ONLY | Uses `dynamic_website_page.dart` with `WebsiteBlockRenderer` (no edit support) |

### Root Cause

`DynamicWebsitePage` (used for `/pagina/:slug` routes) does NOT:
- Import `WebsiteEditModeProvider`
- Use `EditableBlockRenderer`
- Connect to the inline editor system

It only uses `WebsiteBlockRenderer` which is **read-only**.

### Future Implementation Required

To enable editing on ALL pages:

1. **Modify `DynamicWebsitePage`:**
   - Import and watch `WebsiteEditModeProvider`
   - When `isEditMode = true`, use `EditableBlockRenderer` instead of `WebsiteBlockRenderer`
   - Load page-specific blocks into `editProvider` when entering edit mode

2. **Modify `public_store_layout.dart`:**
   - Detect current page slug from route
   - Pass current page ID to `WebsiteEditorPanel`
   - Load correct blocks for current page (not just home page)

3. **Modify `WebsiteService`:**
   - Track "current editing page" in state
   - `saveBlocks()` should save to correct page_id

**For now:** Edit policy pages via SQL or create a dedicated page editor (not inline).

---

## 🗑️ DELETED FILES (Dec 2025)

The following files were REMOVED because they caused confusion:

| Deleted File | Reason |
|--------------|--------|
| `odoo_style_editor_page.dart` | Standalone editor that was NEVER used - caused massive confusion |
| `website_editor_page.dart` | Wrapper that just returned OdooStyleEditorPage |

**The `/website/editor` route has been removed.** All editing happens inline via the public store.

---

## Core Architecture

### Database Tables
```sql
-- Pages (multi-page support)
website_pages (
  id, tenant_id, slug, title, is_published, is_home, is_system, template, meta_description, created_at, updated_at
)

-- Blocks (visual components)
website_blocks (
  id, tenant_id, page_id, block_type, order_index, is_visible, block_data JSONB, created_at, updated_at
)

-- Settings (theme, contact info, etc)
website_settings (
  id, tenant_id, key, value, created_at, updated_at
)
```

### Block System

**Block Types Available** (`lib/modules/website/models/website_block_type.dart`):
```dart
enum WebsiteBlockType {
  hero,           // Banner with title, subtitle, CTA button, background image
  carousel,       // Multi-slide hero with navigation
  products,       // Product grid from inventory
  services,       // Service cards with icons
  about,          // Company info with image
  testimonials,   // Customer reviews
  features,       // Feature/benefit grid
  cta,            // Call-to-action section
  gallery,        // Image gallery
  contact,        // Contact form
  faq,            // Accordion FAQ
  pricing,        // Pricing plans
  team,           // Team member cards
  stats,          // Statistics/metrics
  footer,         // Page footer
  categoryGrid,   // Category cards with images
  videoBanner,    // Video background section
  partnersBanner, // Partners/sponsors
  brandLogos,     // Brand logo carousel
}
```

### Block Data Structure

Each block stores its configuration in `block_data` JSONB:
```json
{
  "title": "Welcome to Vinabike",
  "subtitle": "Your cycling partner",
  "buttonText": "Shop Now",
  "buttonLink": "/tienda/productos",
  "backgroundImage": "https://...",
  "overlayColor": "#000000",
  "overlayOpacity": 0.35,
  "visibility": {
    "desktop": true,
    "tablet": true,
    "mobile": true
  }
}
```

---

## 🎨 Visual Editor Features (MUST PRESERVE)

### 1. Inline Text Editing
**Location:** `lib/modules/website/widgets/inline_editable_text.dart`

Users can click on ANY text element and edit it directly in the preview:
```dart
InlineEditableText(
  text: data['title'] ?? '',
  isEditMode: true,  // Enable inline editing
  onChanged: (newText) => _updateBlockData(block, 'title', newText),
  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
)
```

**RULE:** Every text field in a block MUST use `InlineEditableText` for direct editing.

### 2. Inline Image Editing
**Location:** `lib/modules/website/widgets/inline_editable_image.dart`

Users can click on images to upload/replace:
```dart
InlineEditableImage(
  imageUrl: data['backgroundImage'],
  isEditMode: true,
  onChanged: (newUrl) => _updateBlockData(block, 'backgroundImage', newUrl),
  width: double.infinity,
  height: 400,
)
```

**RULE:** Every image in a block MUST use `InlineEditableImage` for click-to-upload.

### 3. Block Field Schema System
**Location:** `lib/modules/website/models/website_block_definition.dart`

Every block defines its editable fields:
```dart
WebsiteBlockDefinition(
  type: WebsiteBlockType.hero,
  title: 'Hero / Banner',
  fields: [
    WebsiteBlockFieldSchema(
      key: 'title',
      label: 'Título',
      type: WebsiteBlockFieldType.text,
    ),
    WebsiteBlockFieldSchema(
      key: 'buttonText',
      label: 'Texto del botón',
      type: WebsiteBlockFieldType.text,
    ),
    WebsiteBlockFieldSchema(
      key: 'buttonLink',
      label: 'Enlace del botón',
      type: WebsiteBlockFieldType.text,
    ),
    WebsiteBlockFieldSchema(
      key: 'backgroundImage',
      label: 'Imagen de fondo',
      type: WebsiteBlockFieldType.image,
    ),
  ],
)
```

### 4. Field Types Available
```dart
enum WebsiteBlockFieldType {
  text,      // Single line text
  textarea,  // Multi-line text
  richtext,  // Rich text editor (HTML)
  color,     // Color picker
  image,     // Image upload
  number,    // Numeric input
  toggle,    // Boolean switch
  select,    // Dropdown options
  chips,     // Tag/chip list
  repeater,  // Repeatable items (testimonials, team members, etc.)
}
```

### 5. Repeater Fields (Lists)
For blocks with multiple items (testimonials, services, team):
```dart
WebsiteBlockFieldSchema(
  key: 'services',
  label: 'Servicios',
  type: WebsiteBlockFieldType.repeater,
  itemLabel: 'Servicio',
  minItems: 1,
  itemFields: [
    WebsiteBlockFieldSchema(key: 'icon', label: 'Ícono', type: WebsiteBlockFieldType.select),
    WebsiteBlockFieldSchema(key: 'title', label: 'Título', type: WebsiteBlockFieldType.text),
    WebsiteBlockFieldSchema(key: 'description', label: 'Descripción', type: WebsiteBlockFieldType.textarea),
  ],
)
```

---

## 🚨 CRITICAL RULES FOR WEBSITE DEVELOPMENT

### ❌ NEVER DO THIS:
```sql
-- WRONG: Hardcoding content in SQL
INSERT INTO website_blocks (block_data) VALUES ('{
  "content": "<h1>Hardcoded Title</h1><p>Hardcoded paragraph...</p>"
}');
```

```dart
// WRONG: Hardcoding content in Dart
Widget build(context) {
  return Text('Welcome to Vinabike'); // Hardcoded!
}
```

### ✅ ALWAYS DO THIS:
```dart
// CORRECT: Read from block_data, editable through UI
Widget build(context) {
  final title = data['title'] ?? 'Default Title';
  return InlineEditableText(
    text: title,
    isEditMode: isEditMode,
    onChanged: (v) => onUpdateBlock('title', v),
  );
}
```

---

## 📦 Creating New Block Types

When adding a NEW block type, you MUST:

### 1. Add Enum Value
```dart
// lib/modules/website/models/website_block_type.dart
enum WebsiteBlockType {
  // ... existing types
  myNewBlock,  // Add new type
}
```

### 2. Add Icon
```dart
// In WebsiteBlockTypeX extension
IconData get icon => switch (this) {
  // ...
  WebsiteBlockType.myNewBlock => Icons.my_icon,
};
```

### 3. Register Block Definition
```dart
// lib/modules/website/models/website_block_registry.dart
WebsiteBlockType.myNewBlock: WebsiteBlockDefinition(
  type: WebsiteBlockType.myNewBlock,
  title: 'Mi Nuevo Bloque',
  description: 'Descripción del bloque',
  defaultData: {
    'title': 'Título por defecto',
    'content': 'Contenido por defecto',
    'imageUrl': null,
    'buttonText': null,
    'buttonLink': null,
  },
  fields: [
    // Define ALL editable fields
    WebsiteBlockFieldSchema(key: 'title', label: 'Título', type: WebsiteBlockFieldType.text),
    WebsiteBlockFieldSchema(key: 'content', label: 'Contenido', type: WebsiteBlockFieldType.textarea),
    WebsiteBlockFieldSchema(key: 'imageUrl', label: 'Imagen', type: WebsiteBlockFieldType.image),
    WebsiteBlockFieldSchema(key: 'buttonText', label: 'Texto del Botón', type: WebsiteBlockFieldType.text),
    WebsiteBlockFieldSchema(key: 'buttonLink', label: 'Enlace', type: WebsiteBlockFieldType.text),
  ],
),
```

### 4. Add Renderer
```dart
// lib/modules/website/widgets/website_block_renderer.dart
case WebsiteBlockType.myNewBlock:
  return _buildMyNewBlock(
    context: context,
    data: data,
    primaryColor: primaryColor,
    // ... other params
  );

static Widget _buildMyNewBlock({
  required BuildContext context,
  required Map<String, dynamic> data,
  required Color primaryColor,
  // ...
}) {
  final title = data['title'] as String? ?? 'Default';
  final content = data['content'] as String? ?? '';
  final imageUrl = data['imageUrl'] as String?;
  final buttonText = data['buttonText'] as String?;
  final buttonLink = data['buttonLink'] as String?;
  
  return Container(
    // Build UI using data from block_data
    // ALL content comes from editable fields!
  );
}
```

### 5. Add to Editor Preview
The Odoo-style editor automatically handles preview if block is registered properly.

---

## 🔘 Button/Link System

**Every block that can have buttons MUST support:**

1. **Button Text** (`buttonText`): The label on the button
2. **Button Link** (`buttonLink`): Where it navigates to

**Valid link formats:**
- `/tienda` - Internal store home
- `/tienda/productos` - Product catalog
- `/tienda/categoria/mtb` - Category page
- `/pagina/nosotros` - Custom page by slug
- `https://external.com` - External URL

**Implementation:**
```dart
if (buttonText != null && buttonText.isNotEmpty)
  ElevatedButton(
    onPressed: () {
      if (buttonLink != null) {
        if (buttonLink.startsWith('http')) {
          // External link
          launchUrl(Uri.parse(buttonLink));
        } else {
          // Internal navigation
          onNavigate?.call(buttonLink);
        }
      }
    },
    child: Text(buttonText),
  )
```

---

## 🖼️ Media System

### Image Fields
```dart
WebsiteBlockFieldSchema(
  key: 'imageUrl',
  label: 'Imagen',
  type: WebsiteBlockFieldType.image,
)
```

Images are:
1. Uploaded to Supabase Storage (`website/blocks/` folder)
2. URL stored in `block_data.imageUrl`
3. Rendered with `InlineEditableImage` for click-to-replace

### Video Fields (VideoBanner block)
```dart
defaultData: {
  'videoUrl': null,  // YouTube/Vimeo URL
  'posterImage': null,  // Fallback image
  'autoplay': true,
  'loop': true,
  'muted': true,
}
```

---

## 📄 Multi-Page System

### Page Templates
```dart
enum PageTemplate {
  defaultTemplate,  // General purpose
  landing,          // Marketing landing page
  productList,      // Product catalog
  blog,             // Blog/article page
}
```

### Creating Pages
Pages are created in the Website Editor:
1. Click "Nueva Página" button
2. Enter title and slug
3. Select template (determines default blocks)
4. Add/edit blocks
5. Publish

### Route Structure
```
/tienda                    - Home page (is_home = true)
/tienda/productos          - Product catalog
/tienda/producto/:id       - Product detail
/pagina/:slug              - Custom pages (nosotros, terminos, etc.)
/cuenta                    - Customer account
```

### Policy Pages Routing (Dec 2025 fix)
- Use `StaticPolicyPage` (in `lib/public_store/pages/static_policy_page.dart`) for policy/info slugs like `/nosotros`, `/terminos`, `/privacidad`, `/devoluciones`, `/envios`.
- Wrap it in `PublicStoreWrapper` in `app_router.dart`; do **not** route these to `DynamicWebsitePage` (causes redirect loops and loses inline editing).
- `StaticPolicyPage` already wires `WebsiteEditModeProvider` + `EditableBlockRenderer`, so `?edit=true` / `?preview=true` keep inline editing on these pages.
- Provide a `fallbackTitle` per slug to avoid null titles when the page row is missing or unpublished.

---

## 🎨 Theme System

Theme settings stored in `website_settings`:
```
theme_primary_color     - Main brand color
theme_accent_color      - Secondary/highlight color
theme_background_color  - Page background
theme_text_color        - Default text color
theme_heading_font      - Font family for titles
theme_body_font         - Font family for body text
theme_heading_size      - Base heading size (px)
theme_body_size         - Base body size (px)
theme_section_spacing   - Gap between blocks (px)
theme_container_padding - Content padding (px)
```

All blocks inherit theme settings automatically.

---

## ⚠️ Checklist for Website Features

When creating ANY website feature:

- [ ] **Is all content editable?** (No hardcoded text/images)
- [ ] **Does it use InlineEditableText?** (For text fields)
- [ ] **Does it use InlineEditableImage?** (For images)
- [ ] **Is there a block definition?** (In website_block_registry.dart)
- [ ] **Are all fields defined?** (With proper types)
- [ ] **Does it support buttons/links?** (buttonText + buttonLink)
- [ ] **Does it respect theme settings?** (Colors, fonts)
- [ ] **Is it responsive?** (desktop/tablet/mobile visibility)
- [ ] **Is there a renderer?** (In website_block_renderer.dart)
- [ ] **Is the default data sensible?** (Placeholder content, not real data)
- [ ] **Does the editable block use LayoutBuilder?** (For vertical centering when resized)
- [ ] **Does the GestureDetector have HitTestBehavior.opaque?** (For click-anywhere selection)

---

## 🎯 CRITICAL: Editable Block Rendering Patterns (Dec 2025)

**Location:** `lib/modules/website/widgets/editable_block_renderer.dart`

### Block Selection Architecture

The `EditableBlockRenderer` widget wraps each block with:
1. **GestureDetector** - For tap-to-select functionality
2. **Stack** - For overlay elements (selection border, resize handles, action bar)
3. **ConstrainedBox** - For enforcing custom block heights when resized

**CRITICAL:** The GestureDetector MUST have `behavior: HitTestBehavior.opaque` to capture taps on empty areas within the block bounds.

```dart
return GestureDetector(
  behavior: HitTestBehavior.opaque, // ⚠️ CRITICAL: Captures taps on empty space
  onTap: () => editProvider.selectBlock(widget.blockId),
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      // Block content
      // Selection border (Positioned.fill)
      // Resize handles (if selected)
      // Action bar (if selected)
    ],
  ),
);
```

### Block Height Categories

Blocks are categorized into two types based on how they handle custom heights:

#### 1. Full-Bleed Blocks (Media fills entire height)
These blocks stretch their media (images/videos) to fill the entire block height:
- `hero` - Background image fills block
- `carousel` - Slides fill block height
- `videoBanner` - Video fills block

**Pattern:** Pass `blockHeight` to the block builder and use it directly:
```dart
final fullBleedBlocks = {'hero', 'carousel', 'videoBanner'};

// In hero/carousel/videoBanner builders:
final blockHeight = (data['blockHeight'] as num?)?.toDouble() ?? 480;
return SizedBox(
  height: blockHeight,
  child: Stack(
    fit: StackFit.expand, // Image/video fills entire space
    children: [
      // Background media
      // Overlay content (centered)
    ],
  ),
);
```

#### 2. Content Blocks (Content centers vertically)
These blocks center their content vertically within the constrained height:
- `services`, `features`, `about`, `cta`, `faq`
- `contact`, `pricing`, `testimonials`, `stats`, `team`
- `gallery`, `categoryGrid`, `partnersBanner`, `brandLogos`

**Pattern:** Use `LayoutBuilder` to detect constrained height and center content:
```dart
Widget _buildEditableServices(BuildContext context) {
  // ... parse data, create content Column ...
  
  final content = Column(
    mainAxisSize: MainAxisSize.min, // ⚠️ CRITICAL: Don't expand unnecessarily
    children: [
      // Title, subtitle, items, etc.
    ],
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      final hasFixedHeight = constraints.maxHeight.isFinite;
      
      return Container(
        width: double.infinity, // ⚠️ Fill horizontal space for click detection
        height: hasFixedHeight ? constraints.maxHeight : null,
        padding: hasFixedHeight
            ? const EdgeInsets.symmetric(horizontal: 24) // No vertical padding when constrained
            : const EdgeInsets.symmetric(vertical: 64, horizontal: 24), // Normal padding
        child: Center( // ⚠️ Centers content vertically AND horizontally
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      );
    },
  );
}
```

### Why LayoutBuilder Pattern is Required

1. **Resize Feature:** Users can drag the bottom edge of blocks to resize them
2. **Height Constraint:** The wrapper passes `ConstrainedBox` with `minHeight`/`maxHeight` to the block
3. **Vertical Centering:** Without `LayoutBuilder`, content would stick to top of block
4. **Click Detection:** Without `width: double.infinity`, empty areas won't register taps

### Common Mistakes to AVOID

❌ **Missing HitTestBehavior.opaque on GestureDetector:**
```dart
// WRONG: Taps on empty space don't select block
GestureDetector(
  onTap: () => selectBlock(id),
  child: ...
)

// CORRECT: Taps anywhere in bounds select block
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => selectBlock(id),
  child: ...
)
```

❌ **Not using LayoutBuilder for content blocks:**
```dart
// WRONG: Content sticks to top when block is resized
return Container(
  padding: EdgeInsets.all(64),
  child: Column(children: [...]),
);

// CORRECT: Content centers vertically when height is constrained
return LayoutBuilder(
  builder: (context, constraints) {
    final hasFixedHeight = constraints.maxHeight.isFinite;
    return Container(
      height: hasFixedHeight ? constraints.maxHeight : null,
      child: Center(child: content),
    );
  },
);
```

❌ **Missing mainAxisSize: MainAxisSize.min on Column:**
```dart
// WRONG: Column expands to fill all space, breaks centering
Column(
  children: [...]
)

// CORRECT: Column only takes needed space
Column(
  mainAxisSize: MainAxisSize.min,
  children: [...]
)
```

❌ **Missing width: double.infinity on Container:**
```dart
// WRONG: Click area only covers content width
Container(
  child: Center(child: content),
)

// CORRECT: Click area covers full block width
Container(
  width: double.infinity,
  child: Center(child: content),
)
```

### Adding a New Editable Block

When creating a new editable block in `editable_block_renderer.dart`:

1. **Add case to switch statement:**
```dart
case WebsiteBlockType.myNewBlock:
  return _buildEditableMyNewBlock(context);
```

2. **Create builder method following the pattern:**
```dart
Widget _buildEditableMyNewBlock(BuildContext context) {
  final editProvider = context.read<WebsiteEditModeProvider>();
  final theme = Theme.of(context);
  
  // 1. Parse data from widget.data
  final title = (widget.data['title'] ?? 'Default Title').toString();
  final items = widget.data['items'] as List? ?? [];
  
  // 2. Define styles
  final headingStyle = theme.textTheme.displaySmall?.copyWith(
    fontFamily: widget.headingFont,
  );
  
  // 3. Build content with mainAxisSize: MainAxisSize.min
  final content = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      InlineEditableTextV2(
        text: title,
        baseStyle: headingStyle,
        textAlign: TextAlign.center,
        isEditMode: true,
        placeholder: 'Título',
        fieldKey: '${widget.blockId}_title',
        onTextChanged: (value) =>
            editProvider.updateBlockData(widget.blockId, 'title', value),
      ),
      // ... more content
    ],
  );
  
  // 4. Wrap with LayoutBuilder for vertical centering
  return LayoutBuilder(
    builder: (context, constraints) {
      final hasFixedHeight = constraints.maxHeight.isFinite;
      
      return Container(
        width: double.infinity,
        height: hasFixedHeight ? constraints.maxHeight : null,
        padding: hasFixedHeight
            ? const EdgeInsets.symmetric(horizontal: 24)
            : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        color: Colors.white, // Optional background
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      );
    },
  );
}
```

3. **For full-bleed blocks (with background images/videos):**
```dart
Widget _buildEditableMyMediaBlock(BuildContext context) {
  final blockHeight = (widget.data['blockHeight'] as num?)?.toDouble() ?? 480;
  
  return SizedBox(
    height: blockHeight,
    width: double.infinity,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Background image/video (fills entire space)
        InlineEditableImage(
          imageUrl: widget.data['backgroundImage'],
          fit: BoxFit.cover,
          isEditMode: true,
          onChanged: (url) => editProvider.updateBlockData(
              widget.blockId, 'backgroundImage', url),
        ),
        // Overlay content (centered)
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [/* Title, subtitle, button */],
          ),
        ),
      ],
    ),
  );
}
```

### Block Rendering Checklist (New Blocks)

When adding a new editable block:

- [ ] Added case to `_buildEditableBlock()` switch statement
- [ ] Created `_buildEditableMyBlock()` method
- [ ] Used `InlineEditableTextV2` for all text fields
- [ ] Used `InlineEditableImage` for all images
- [ ] Set `mainAxisSize: MainAxisSize.min` on all Columns
- [ ] Wrapped return with `LayoutBuilder` (for content blocks)
- [ ] Set `width: double.infinity` on Container
- [ ] Used `Center` widget for vertical centering
- [ ] Used `ConstrainedBox` with appropriate maxWidth
- [ ] Tested click-anywhere-to-select behavior
- [ ] Tested resize behavior (content centers vertically)
- [ ] Tested with both short and tall content

---

## 🔍 Reference Files

| File | Purpose |
|------|---------|
| `lib/public_store/widgets/public_store_layout.dart` | Main layout with edit button & panel integration |
| `lib/modules/website/widgets/website_editor_panel.dart` | Side panel editor (6600 lines) |
| `lib/modules/website/providers/website_edit_mode_provider.dart` | Edit state management |
| `lib/modules/website/widgets/editable_block_renderer.dart` | **CRITICAL:** Makes blocks clickable/selectable/resizable in edit mode. Contains all `_buildEditable*` methods |
| `lib/public_store/pages/public_home_page.dart` | Home page with full editing support |
| `lib/public_store/pages/dynamic_website_page.dart` | Other pages (READ-ONLY, no editing yet) |
| `lib/modules/website/models/website_block_type.dart` | Block type enum |
| `lib/modules/website/models/website_block_definition.dart` | Field schema definitions |
| `lib/modules/website/models/website_block_registry.dart` | Block registration & defaults |
| `lib/modules/website/widgets/website_block_renderer.dart` | Renders blocks (read-only, for public view) |
| `lib/modules/website/widgets/inline_editable_text.dart` | Inline text editing widget (V1) |
| `lib/modules/website/widgets/inline_editable_text_v2.dart` | Inline text editing widget (V2 with formatting) |
| `lib/modules/website/widgets/inline_editable_image.dart` | Inline image editing/upload widget |
| `lib/modules/website/services/website_service.dart` | Database operations for blocks/pages (**includes page_id in saves**) |

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

# 💰 Tax Treatment (IVA 19%) - CRITICAL DIFFERENCES

## Sales Invoices: Tax is INCLUDED in Price

**Concept:** Customer sees final price on shelf/website. Tax is embedded.

**Example:** Selling a bicycle for $119,000 CLP
- Display price: $119,000 (what customer pays)
- When "IVA Incluido" selected:
  - Neto (Net): $100,000 (calculated: $119,000 ÷ 1.19)
  - IVA (19%): $19,000 (calculated: $119,000 - $100,000)
  - Total: $119,000 (unchanged - customer pays this amount)

**Calculation Logic:**
```dart
// Sales Invoice (lib/modules/sales/pages/invoice_form_page.dart)
double get _netAmount {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal / 1.19;  // Extract net by dividing
  } else {
    return _subtotal;
  }
}

double get _iva {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal - _netAmount;  // Tax is difference
  } else {
    return 0;
  }
}

double get _total => _subtotal;  // Total stays the same (what customer sees)
```

**Use Cases:**
- POS sales (retail)
- Service invoices (Pegas Module)
- Customer-facing transactions
- E-commerce product prices

---

## Purchase Invoices: Tax is ADDED on Top

**Concept:** Supplier quotes net price. We add tax on top to calculate total.

**Example:** Buying inventory for $100,000 CLP net
- Supplier quotes: $100,000 net
- When "IVA Incluido" selected:
  - Subtotal (Neto): $100,000 (supplier's quoted price)
  - IVA (19%): $19,000 (calculated: $100,000 × 0.19)
  - Total: $119,000 (calculated: $100,000 + $19,000)

**Calculation Logic:**
```dart
// Purchase Invoice (lib/modules/purchases/pages/purchase_invoice_form_page.dart)
double get _netAmount {
  return _subtotal;  // Net is always the subtotal for purchases
}

double get _iva {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal * 0.19;  // Add 19% tax
  } else {
    return 0;
  }
}

double get _total {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal + _iva;  // Add tax to get total
  } else {
    return _subtotal;
  }
}
```

**Use Cases:**
- Purchasing inventory from suppliers
- Buying parts/components
- Import costs
- Service provider invoices

---

## Why the Difference?

**Sales (Tax Included):**
- Retail customers see **final prices** (tax already embedded)
- We **extract** the tax component for accounting: `net = total ÷ 1.19`
- Customer pays the displayed amount (no surprise at checkout)

**Purchases (Tax Added):**
- Suppliers quote **net prices** (before tax)
- We **add** tax on top to get total: `total = net + (net × 0.19)`
- Common in B2B transactions where tax is itemized separately

## Accounting Impact

**Sales IVA (Débito Fiscal):**
- Credit account (liability)
- We owe this to SII (Chilean tax authority)
- Account code: 2110

**Purchase IVA (Crédito Fiscal):**
- Debit account (asset)
- We can claim this back from SII
- Account code: 2120

**Net IVA Payable:**
```
Sales IVA - Purchase IVA = Amount owed to tax authority
```

**Example:**
- Sold $1,190,000 with IVA → Sales IVA = $190,000 (liability)
- Bought $595,000 with IVA → Purchase IVA = $95,000 (asset)
- Net IVA Payable = $190,000 - $95,000 = $95,000 owed to SII

---

**⚠️ CRITICAL FOR COPILOT:**
- **NEVER** use the same calculation for sales and purchases
- **ALWAYS** check if you're in sales or purchases module
- Sales: Divide by 1.19 to extract tax
- Purchases: Multiply by 0.19 to add tax
- This is Chilean tax law compliance - incorrect calculations = legal issues

---

**Bidirectional Cascade Delete:**

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

# 🛒 GOOGLE MERCHANT CENTER INTEGRATION

**Complete guide for feeding products to Google Merchant Center and getting approved.**

## Architecture Overview

```
Products Table (with is_google_merchant=true)
         ↓
Supabase Edge Function (google-merchant-feed)
         ↓
XML RSS 2.0 Feed (https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant=vinabike)
         ↓
Google Merchant Center (fetches feed every 24h)
         ↓
Google Shopping / Free Listings
```

**Feed URL Pattern:**
- By subdomain: `https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant={subdomain}`
- By custom domain: `https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?domain={custom_domain}`

**Feed Location:** `supabase/functions/google-merchant-feed/index.ts`

---

## 🚨 CRITICAL: Product Approval Requirements

### Mandatory Fields (Google WILL Reject Without These)

| Field | Database Column | Description | Example |
|-------|-----------------|-------------|---------|
| **ID** | `id` (UUID) | Unique product identifier | `775815ba-4c04-4ad8-b037-33d9ed70f06a` |
| **Title** | `name` | Product name (150 char max) | `Aceite Mineral Shimano SM-DBOIL 1 Litro` |
| **Description** | `description` | Min 150 chars! | Detailed product description |
| **Link** | Generated | Product URL | `https://vinabike.cl/productos/{id}` |
| **Image Link** | `image_url` | Main product image | Must be HTTPS, min 100x100px |
| **Price** | `price` + `price_currency` | With currency | `15990 CLP` |
| **Availability** | `stock_quantity` | In stock / Out of stock | Based on stock > 0 |
| **Brand** | `brand_id` → `product_brands.name` | Manufacturer | `Shimano`, `KMC` |
| **Condition** | Hardcoded | Always `new` | `new` |

### Product Identifiers: GTIN vs MPN vs identifier_exists

**🚨 THE #1 REJECTION REASON: Incorrect identifier setup!**

Google requires ONE of these combinations:
1. ✅ **GTIN** (preferred) - Universal Product Code (UPC/EAN/ISBN)
2. ✅ **Brand + MPN** - Manufacturer Part Number
3. ✅ **identifier_exists=false** - For custom/handmade products only

**Database Columns:**
- `gtin` → `<g:gtin>` tag (12-14 digits)
- `sku` → `<g:mpn>` tag (Manufacturer Part Number)

---

## 📋 REAL-WORLD EXAMPLE: Fixing Rejected Products

### Case Study: Shimano SM-DBOIL Mineral Oil

**Initial State (REJECTED):**
```json
{
  "name": "ACEITE MINERAL SHIMANO SM-DBOIL 1 LITRO",
  "sku": "S56467",
  "gtin": null,           // ❌ EMPTY!
  "mpn": "022255354042"   // ❌ WRONG FIELD! This is a UPC, not MPN
}
```

**Google's Rejection Reason:** "Missing GTIN for this product"

**The Problem:** The UPC barcode `022255354042` was stored in the wrong field (`mpn` instead of `gtin`).

**The Fix:**
```sql
UPDATE products 
SET gtin = '022255354042', 
    mpn = null  -- Clear the wrong field
WHERE id = '775815ba-4c04-4ad8-b037-33d9ed70f06a';
```

**Corrected State (APPROVED):**
```json
{
  "name": "Aceite Mineral Shimano SM-DBOIL 1 Litro",
  "sku": "S56467",
  "gtin": "022255354042",  // ✅ CORRECT! UPC in GTIN field
  "mpn": null
}
```

**Feed Output After Fix:**
```xml
<item>
  <g:id>775815ba-4c04-4ad8-b037-33d9ed70f06a</g:id>
  <g:title>Aceite Mineral Shimano SM-DBOIL 1 Litro</g:title>
  <g:gtin>022255354042</g:gtin>  <!-- ✅ Now in correct tag -->
  <g:mpn>S56467</g:mpn>          <!-- SKU becomes MPN -->
  <g:brand>Shimano</g:brand>
  ...
</item>
```

---

## 🔤 UNDERSTANDING GTIN, MPN, SKU, and BARCODE

### Field Definitions

| Field | What It Is | Who Assigns It | Format | Example |
|-------|-----------|----------------|--------|---------|
| **GTIN** | Global Trade Item Number | Manufacturer | 8-14 digits (UPC/EAN) | `022255354042` |
| **MPN** | Manufacturer Part Number | Manufacturer | Alphanumeric | `SM-DBOIL-1L` |
| **SKU** | Stock Keeping Unit | Retailer (YOU) | Any format | `S56467` |
| **Barcode** | Physical barcode on product | Usually = GTIN | Numeric | `022255354042` |

### How to Identify a GTIN

**GTIN is a UPC, EAN, or ISBN barcode number:**
- **UPC-A** (USA/Canada): 12 digits, starts with 0-1 → `022255354042`
- **EAN-13** (International): 13 digits → `4715575883212`
- **ISBN** (Books): 13 digits, starts with 978/979 → `9780123456789`

**To find GTIN:**
1. Look at product barcode → that number IS the GTIN
2. Search manufacturer's website for product specs
3. Use barcode lookup sites: `https://www.barcodelookup.com/`

### Database Column Mapping

| Database Column | Feed Tag | What to Store |
|-----------------|----------|---------------|
| `gtin` | `<g:gtin>` | UPC/EAN barcode number (12-14 digits) |
| `sku` | `<g:mpn>` | Your internal SKU (retailer code) |
| `barcode` | Fallback for gtin | If gtin is empty, feed uses barcode |

**⚠️ CRITICAL: `sku` maps to `<g:mpn>`, NOT the other way around!**

Our feed logic:
```typescript
// GTIN: prefer gtin field, fallback to barcode
const gtin = product.gtin || product.barcode || ''

// MPN: use SKU (our internal code)
const mpn = product.sku || ''
```

---

## 🏷️ Products WITHOUT GTIN (identifier_exists=false)

For products that genuinely don't have a GTIN:
- Custom/handmade products
- Local/artisan products
- Very old products without barcodes
- Store-branded items

**Feed Logic:**
```typescript
if (gtin && gtin.length >= 8) {
  itemXml += `<g:gtin>${gtin}</g:gtin>`
} else {
  // No valid GTIN - must explicitly mark
  itemXml += `<g:identifier_exists>false</g:identifier_exists>`
}
```

**⚠️ WARNING:** Google scrutinizes products with `identifier_exists=false`. Only use for genuinely unique products!

---

## 📝 Product Data Quality Checklist

### Before Enabling Google Merchant for a Product:

- [ ] **Title:** Clear, descriptive, NO ALL CAPS (feed auto-fixes excessive caps)
- [ ] **Description:** Minimum 150 characters (feed auto-expands if shorter)
- [ ] **Image:** At least 100x100px, HTTPS URL, white/clean background preferred
- [ ] **Price:** Greater than 0, correct currency (CLP for Chile)
- [ ] **Brand:** Must be set (either brand_id or brand text field)
- [ ] **GTIN:** If product has barcode, enter the barcode number here
- [ ] **SKU:** Your internal stock code (becomes MPN in feed)
- [ ] **Stock:** Set accurate inventory (affects availability status)
- [ ] **Category:** Assigned to a product category

### Enable in Product Form:

1. Set `is_published = true` (required for website)
2. Set `is_google_merchant = true` (enables in feed)
3. Set `lifecycle_status = 'active'`

---

## 🔧 Database Fields for Google Merchant

### Products Table Columns (Relevant to Feed)

```sql
-- Core product data
name text not null,
sku text,                    -- Becomes <g:mpn>
description text,
price numeric not null,
price_currency text default 'CLP',
stock_quantity integer,

-- Images
image_url text,              -- Main image → <g:image_link>
image_urls text[],           -- Gallery → <g:additional_image_link>

-- Identifiers
gtin text,                   -- UPC/EAN → <g:gtin>
barcode text,                -- Fallback for GTIN

-- Brand & Category
brand_id uuid references product_brands(id),
brand text,                  -- Fallback if no brand_id
category_id uuid references product_categories(id),
category_name text,          -- Fallback for category

-- Visibility flags
is_active boolean default true,
is_published boolean default false,      -- Must be true for website
is_google_merchant boolean default false, -- Must be true for feed
lifecycle_status text default 'active',
```

### Updating GTIN via API

```bash
# Get product current state
source .env && curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/products?id=eq.{PRODUCT_ID}" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq '.[0] | {name, sku, gtin, mpn, barcode}'

# Update GTIN
source .env && curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/products?id=eq.{PRODUCT_ID}" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -X PATCH \
  -d '{"gtin": "YOUR_BARCODE_NUMBER"}' | jq '.[0] | {name, sku, gtin}'
```

---

## 🔄 Feed Refresh & Troubleshooting

### Google Merchant Center Re-fetch

After fixing product data:
1. Wait 1-4 hours for feed cache to expire (Cache-Control: 1 hour)
2. Or manually trigger re-fetch in Google Merchant Center:
   - Products → Feeds → Your Feed → Fetch Now
3. Products re-index within 24-48 hours

### Common Rejection Reasons & Fixes

| Rejection | Cause | Fix |
|-----------|-------|-----|
| "Missing GTIN" | GTIN field empty for branded product | Add barcode to `gtin` column |
| "Invalid GTIN" | Wrong format or checksum | Verify barcode, use valid UPC/EAN |
| "Mismatched identifiers" | GTIN doesn't match product | Double-check barcode matches product |
| "Description too short" | Less than ~100 chars | Add more detail (feed auto-expands) |
| "Image too small" | Less than 100x100px | Upload larger image |
| "Price missing" | price = 0 or null | Set valid price > 0 |
| "Generic image" | Product image shows brand logo only | Use actual product photo |

### Testing Feed Locally

```bash
# Fetch feed and check product output
curl "https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant=vinabike" | head -100

# Count products in feed
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant=vinabike" | grep -c "<item>"
```

---

## 🛠️ Flutter Product Form: Google Merchant Fields

**Location:** `lib/modules/inventory/pages/product_form_page.dart`

The product form includes these Google Merchant-relevant fields:

1. **Basic Info Tab:**
   - Name (becomes title)
   - SKU (becomes MPN)
   - Description (needs 150+ chars)
   - Price & Currency

2. **Details Tab:**
   - Brand (dropdown from product_brands)
   - GTIN field (for barcode)
   - Category (for product_type)

3. **Publishing Section:**
   - `is_published` toggle → Required for website
   - `is_google_merchant` toggle → Enables in feed

---

## 📊 Google Merchant Category (google_product_category)

The feed uses numeric category IDs from Google's taxonomy:

```typescript
// Current hardcoded: Cycling Accessories
itemXml += `<g:google_product_category>3618</g:google_product_category>`
```

**Common Cycling Categories:**
- `1085` - Bicycles
- `3618` - Bicycle Parts & Accessories
- `3636` - Bicycle Tires & Tubes
- `3612` - Bicycle Frames

**Future Enhancement:** Map `product_categories` to Google taxonomy IDs.

---

## ✅ Copilot Checklist: Adding Products to Google Merchant

When enabling a product for Google Merchant:

1. ✅ **Verify product has GTIN or set `identifier_exists=false`**
   - If barcode exists → Put it in `gtin` column
   - If no barcode → Product needs `identifier_exists=false` (auto-handled by feed)

2. ✅ **Check description length** → Must be 150+ characters

3. ✅ **Verify image exists** → `image_url` must be set, HTTPS

4. ✅ **Confirm price > 0** → Feed filters out $0 products

5. ✅ **Set brand** → Either `brand_id` or `brand` text must be set

6. ✅ **Enable flags:**
   ```sql
   UPDATE products SET
     is_active = true,
     is_published = true,
     is_google_merchant = true,
     lifecycle_status = 'active'
   WHERE id = 'product-uuid';
   ```

7. ✅ **Test in feed** → Check XML output for correct tags

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

---

# 💰 PAYROLL SYSTEM ARCHITECTURE (Dec 2025)

**Complete documentation of the Payroll Voucher system and its integration with Accounting.**

## Overview

The Payroll system automates:
1. Salary calculations based on attendance/hours worked
2. Expense creation for each employee payment
3. Journal entry generation for proper accounting

## Database Tables

| Table | Purpose |
|-------|---------|
| `payroll_vouchers` | Header record for each payroll period (weekly/monthly) |
| `payroll_voucher_lines` | One line per employee with hours, rates, totals |
| `employees.salary_account_id` | FK to personal expense account (6101-XX) |

## Account Structure (6101-XX Hierarchy)

```
6101 - Sueldos y Salarios (Parent)
├── 6101-01 - Salario - [Employee 1]
├── 6101-02 - Salario - [Employee 2]
└── 6101-XX - Salario - [Employee N]
```

**Auto-creation:** When an employee is created, trigger `trg_create_employee_salary_account` automatically creates a sub-account under 6101.

## Key Fields for Payment Tracking

**In `payroll_voucher_lines`:**
```sql
payment_method_id UUID REFERENCES payment_methods(id)  -- FK to payment method
payment_account_id UUID REFERENCES accounts(id)        -- FK to Bank/Cash account (source)
salary_account_id UUID REFERENCES accounts(id)         -- FK to expense account (destination)
```

**⚠️ CRITICAL:** Both `payment_method_id` AND `payment_account_id` must be populated for correct journal entries!

## RPC Functions

### `generate_payroll_voucher_draft(period_start, period_end, period_label)`
- Creates voucher header and line items from attendance summary
- Pre-fills hours, rates, and calculated amounts
- Status: `draft`

### `pay_payroll_voucher(voucher_id)`
- Creates an `expense` record for each employee line
- Creates `expense_lines` with proper account references
- Triggers `create_expense_journal_entry()` via database triggers
- Status: `paid`

## Journal Entry Flow

When `pay_payroll_voucher` is called:

```
1. INSERT expenses (payment_status='paid', balance=0, posting_status='posted')
      ↓
2. INSERT expense_lines (account_id = salary_account_id from employee)
      ↓
3. TRIGGER: trg_expense_lines_change fires handle_expense_line_change()
      ↓
4. TRIGGER calls: create_expense_journal_entry(expense_id)
      ↓
5. JE Created with:
   - DEBIT: 6101-XX (Salary Expense)
   - CREDIT: 1102 (Bank) or 1101 (Cash)
```

## Income Statement Visibility

**Accrual Mode (Devengado):** Queries `journal_entries` + `journal_lines` by account type

**Cash Flow Mode (Efectivo):** Queries:
1. `sales_payments` for income
2. `purchase_payments` for supplier payments
3. `expenses` (where `payment_status='paid'`) for operating expenses including payroll

**⚠️ If payroll doesn't appear in Cash Flow mode, check:**
- `expenses.paid_at` is within date range
- `expenses.payment_status = 'paid'`
- `expenses.balance = 0`
- The `get_income_statement_data` function has the UNION for paid expenses

---

# 🔢 ACCOUNTING CONSISTENCY RULES (CRITICAL!)

**Common bugs and how to prevent them when creating accounting-related features.**

## Rule 1: Journal Entries Must Balance

```sql
-- ✅ Every JE must have: SUM(debits) = SUM(credits)
-- Verify with:
SELECT je.entry_number, 
       SUM(jl.debit_amount) as total_debit,
       SUM(jl.credit_amount) as total_credit
FROM journal_entries je
JOIN journal_lines jl ON jl.entry_id = je.id
GROUP BY je.id, je.entry_number
HAVING SUM(jl.debit_amount) <> SUM(jl.credit_amount);
-- Should return NO ROWS if balanced
```

## Rule 2: Expense JE Requires `balance = 0` AND `payment_status = 'paid'`

See `create_expense_journal_entry()` lines 7412-7414:
```sql
if payment_status = 'paid'
   AND balance <= 0.01
   AND v_cash_account.id IS NOT NULL then
   -- Creates CREDIT to Bank/Cash
```

**⚠️ If you create expenses via RPC, include:**
```sql
payment_status := 'paid',
balance := 0,
payment_account_id := [valid bank/cash account UUID],
payment_method_id := [valid payment method UUID],
```

## Rule 3: Account Types Must Be Correct

| Account Code Range | Type | Category | Shows In |
|--------------------|------|----------|----------|
| 4000-4999 | `income` | `operatingIncome` | Income Statement (Ingresos) |
| 5000-5199 | `expense` | `costOfGoodsSold` | Income Statement (Costo de Ventas) |
| 6000-6999 | `expense` | `operatingExpense` | Income Statement (Gastos Operacionales) |
| 1000-1999 | `asset` | varies | Balance Sheet (Activos) |
| 2000-2999 | `liability` | varies | Balance Sheet (Pasivos) |

**⚠️ If expenses don't appear in reports, verify:**
```sql
SELECT code, name, type, category, is_active 
FROM accounts WHERE code LIKE '6%';
-- Must have: type='expense', category='operatingExpense', is_active=true
```

## Rule 4: Cash Flow Reports Need Specific Tables

**Cash Flow Mode reads from:**
- `sales_payments` - for realized income
- `purchase_payments` - for supplier payments
- `expenses` (paid) - for direct expenses (payroll, operating)

**⚠️ If you create a new payment type, update `get_income_statement_data` to include it!**

## Rule 5: Always Set `is_active = true` for New Accounts

The Income Statement filter includes:
```sql
WHERE a.is_active = true
```

If accounts are created without `is_active` or with `false`, they won't appear.

## Debugging Checklist

When a transaction doesn't appear in financial reports:

1. ✅ Does the journal entry exist? (`SELECT * FROM journal_entries WHERE source_reference = ...`)
2. ✅ Does it have journal lines? (`SELECT * FROM journal_lines WHERE entry_id = ...`)
3. ✅ Is `status = 'posted'`? (Draft entries don't count)
4. ✅ Is `entry_date` within the report's date range?
5. ✅ Do the accounts have correct `type` and `category`?
6. ✅ Are the accounts `is_active = true`?
7. ✅ For Cash Flow: is `paid_at` within the date range?
8. ✅ For Cash Flow: is `payment_status = 'paid'` and `balance = 0`?

---

# 🔧 PAYROLL DEPLOYMENT CHECKLIST

**When deploying payroll changes:**

1. ✅ **Schema:** `payroll_vouchers`, `payroll_voucher_lines` tables exist
2. ✅ **Columns:** `payment_method_id`, `payment_account_id` on lines table
3. ✅ **Employee Accounts:** All employees have `salary_account_id` populated
4. ✅ **Account 6101:** Parent account exists with correct structure
5. ✅ **RPC:** `pay_payroll_voucher` includes `balance = 0` in expense INSERT
6. ✅ **RPC:** Uses explicit `payment_account_id` and `payment_method_id` from lines
7. ✅ **Cash Flow:** `get_income_statement_data` has UNION for paid expenses

**Quick Fix SQL if payroll expenses are missing from Cash Flow:**

```sql
-- Verify expenses exist and are paid
SELECT expense_number, payment_status, balance, paid_at 
FROM expenses WHERE reference LIKE 'Semana%';

-- If balance is NULL or > 0, fix:
UPDATE expenses SET balance = 0 
WHERE payment_status = 'paid' AND (balance IS NULL OR balance > 0);

-- Regenerate journal entries if needed
UPDATE expenses SET updated_at = NOW() 
WHERE reference LIKE 'Semana%' AND payment_status = 'paid';
```

---

# 📊 ACCOUNTING FUNDAMENTALS (IFRS/GAAP COMPLIANT)

**THIS SECTION IS CRITICAL FOR ANYONE WORKING ON FINANCIAL FEATURES.**

This ERP follows international accounting standards (IFRS/GAAP). Understanding these principles is **mandatory** before making changes to accounting-related code.

---

## 1️⃣ The Two Financial Statements

| Statement | Spanish Name | Purpose | Accounting Method |
|-----------|--------------|---------|-------------------|
| **Income Statement** | Estado de Resultados | Shows profitability (Did we make money?) | **Accrual** |
| **Cash Flow Statement** | Estado de Flujo de Efectivo | Shows liquidity (Do we have money?) | **Cash** |

### Key Mental Model:
- **Income Statement:** *Did we make money?* (Profitability)
- **Cash Flow Statement:** *Do we have money?* (Liquidity)

**⚠️ CRITICAL: A profitable business can fail if it runs out of cash. These are DIFFERENT concepts!**

---

## 2️⃣ Accrual vs Cash Basis Accounting

| Aspect | Accrual Basis (Devengado) | Cash Basis (Efectivo) |
|--------|---------------------------|------------------------|
| **Revenue recognition** | When earned (sale made) | When cash received |
| **Expense recognition** | When incurred (obligation exists) | When cash paid |
| **Primary focus** | Profitability | Liquidity |
| **Used for** | Income Statement | Cash Flow Statement |

### Example:
You sell a bike on December 15 for $1,000, customer pays on January 5.

- **Income Statement (December):** Shows $1,000 revenue ✅
- **Cash Flow Statement (December):** Shows $0 from this sale ❌
- **Cash Flow Statement (January):** Shows $1,000 received ✅

---

## 3️⃣ COGS: The Most Common Misunderstanding

> **COGS measures cost recognition; cash flow measures cash movement — the difference is inventory and payables.**

### ❌ Common Mistake:
*"COGS equals cash spent on inventory"* — **WRONG**

### ✅ Correct Understanding:

| Concept | What It Is | When Recorded | Which Report |
|---------|------------|---------------|--------------|
| **COGS** | Cost of goods **SOLD** | When sale happens | Income Statement |
| **Payments to Suppliers** | Cash paid for inventory | When cash is paid | Cash Flow Statement |

### Example:
You buy 100 bikes in January for $500 each ($50,000 total).
You sell 80 bikes in March.

- **Income Statement (January):** COGS = $0 (nothing sold yet)
- **Income Statement (March):** COGS = $40,000 (80 bikes × $500)
- **Cash Flow Statement (January):** Payments to Suppliers = -$50,000

### The Formula:
```
Cash Paid to Suppliers = COGS + Increase in Inventory − Increase in Accounts Payable
```

**High COGS with low cash outflow** → You're buying on credit
**Low COGS with high cash outflow** → You're paying down old supplier bills

---

## 4️⃣ Journal Entry Rules

### Double-Entry Accounting:
Every transaction has **two sides** that must balance:
```
DEBIT = CREDIT (always!)
```

### The Nature of Accounts:

| Account Type | Normal Balance | To Increase | To Decrease |
|--------------|----------------|-------------|-------------|
| **Asset** (1xxx) | Debit | Debit | Credit |
| **Liability** (2xxx) | Credit | Credit | Debit |
| **Equity** (3xxx) | Credit | Credit | Debit |
| **Revenue** (4xxx) | Credit | Credit | Debit |
| **Expense** (5xxx-6xxx) | Debit | Debit | Credit |

### Common Journal Entries:

**Sale (Invoice Created):**
```
DEBIT:  1200 Accounts Receivable     $1,000
CREDIT: 4100 Sales Revenue                   $1,000
DEBIT:  5100 Cost of Goods Sold      $600
CREDIT: 1300 Inventory                       $600
```

**Sale Payment Received:**
```
DEBIT:  1102 Bank                    $1,000
CREDIT: 1200 Accounts Receivable             $1,000
```

**Purchase (Invoice Created):**
```
DEBIT:  1300 Inventory               $500
CREDIT: 2100 Accounts Payable                $500
```

**Purchase Payment Made:**
```
DEBIT:  2100 Accounts Payable        $500
CREDIT: 1102 Bank                            $500
```

**Payroll Expense:**
```
DEBIT:  6101-XX Salary - [Employee]  $5,000
CREDIT: 1102 Bank                            $5,000
```

---

## 5️⃣ Account Code Structure (Chile SII Aligned)

```
1xxx - ASSETS (Activos)
  1100 - Cash & Bank
    1101 - Caja General
    1102 - Bancos - Cuenta Corriente
  1200 - Accounts Receivable
  1300 - Inventory (Inventario)

2xxx - LIABILITIES (Pasivos)
  2100 - Accounts Payable (Proveedores)
  2200 - Taxes Payable

3xxx - EQUITY (Patrimonio)
  3100 - Capital
  3200 - Retained Earnings

4xxx - REVENUE (Ingresos)
  4100 - Sales Revenue (Ventas)

5xxx - COST OF GOODS SOLD (Costo de Ventas)
  5100 - COGS (calculated when inventory is sold)

6xxx - OPERATING EXPENSES (Gastos Operacionales)
  6100 - Payroll & HR
    6101 - Sueldos y Salarios
      6101-01 - Salario - [Employee 1]
      6101-02 - Salario - [Employee 2]
  6200 - Rent & Utilities
  6300 - Marketing & Advertising
  6400 - Office Expenses
```

---

## 6️⃣ Report Implementation in This ERP

### Income Statement (Devengado) - `get_income_statement_data(is_cash_flow=false)`

Queries **journal entries** and **journal lines** to show:
- Revenue (when earned)
- COGS (when sold)
- Operating Expenses (when incurred)

```sql
-- Uses journal entries grouped by account
FROM accounts a
JOIN journal_lines jl ON jl.account_id = a.id
JOIN journal_entries je ON je.id = jl.entry_id
WHERE je.entry_date BETWEEN start_date AND end_date
  AND je.status = 'posted'
```

### Cash Flow Statement (Efectivo) - `get_income_statement_data(is_cash_flow=true)`

Queries **payment tables** to show actual cash movements:
- Cash IN: `sales_payments` (customer payments)
- Cash OUT: `purchase_payments` (supplier payments)
- Cash OUT: `expenses` where `payment_status='paid'` (operating expenses)

```sql
-- Uses payment tables directly
FROM sales_payments WHERE date BETWEEN start_date AND end_date
UNION ALL
FROM purchase_payments WHERE date BETWEEN start_date AND end_date
UNION ALL
FROM expenses WHERE paid_at BETWEEN start_date AND end_date
```

---

## 7️⃣ Common Accounting Bugs and Prevention

### Bug: Expenses don't appear in Cash Flow
**Cause:** Missing `payment_status = 'paid'` or `paid_at` is NULL
**Fix:** Set both when paying an expense

### Bug: COGS shows on wrong report
**Cause:** Confusing "payments to suppliers" with COGS
**Fix:** Purchase payments → Cash Flow; COGS from sales → Income Statement

### Bug: Journal entry doesn't balance
**Cause:** Only created debit side, forgot credit
**Fix:** Every INSERT into journal_lines must have matching debit/credit

### Bug: Transaction appears in wrong period
**Cause:** Using `created_at` instead of `entry_date` or `paid_at`
**Fix:** Always use the proper date field for the report type

### Bug: Account shows $0 in reports
**Cause:** `is_active = false` or wrong `type`/`category`
**Fix:** Verify account configuration

---

## 8️⃣ Before Creating Any Accounting Feature

**Mandatory Questions:**

1. ✅ Is this going on the Income Statement or Cash Flow Statement?
2. ✅ Am I using accrual (journal entries) or cash (payment tables)?
3. ✅ Does every journal entry balance (debits = credits)?
4. ✅ Am I using the correct account codes and types?
5. ✅ Is the timing correct (entry_date for accrual, paid_at for cash)?

**⚠️ DO NOT:**
- ❌ Confuse COGS with payments to suppliers
- ❌ Put cash transactions in journal entries (use payment tables)
- ❌ Create unbalanced journal entries
- ❌ Forget to set `is_active = true` on new accounts
- ❌ Use wrong account types/categories

**✅ ALWAYS:**
- ✅ Understand the difference between profitability and liquidity
- ✅ Use proper account codes from the chart of accounts
- ✅ Test reports in both Devengado AND Efectivo modes
- ✅ Verify journal entries balance
- ✅ Check that transactions appear in correct periods