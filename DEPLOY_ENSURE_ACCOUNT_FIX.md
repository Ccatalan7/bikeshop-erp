# 🔧 Deploy ensure_account() Parent Lookup Fix

## What Was Fixed

The `ensure_account()` function already had multi-tenant support, but had a **critical bug** where parent account lookup didn't filter by `tenant_id`. This could return the wrong parent account from another tenant.

### Changes Made

**File**: `supabase/sql/core_schema.sql` (Line ~1320)

**Before**:
```sql
-- Parent lookup without tenant_id filter
if p_parent_code is not null then
  select id
    into v_parent_id
    from public.accounts
   where code = p_parent_code
   limit 1;
end if;

-- Get tenant_id after parent lookup (BUG!)
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
```

**After**:
```sql
-- Get tenant_id FIRST
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  -- Lookup parent account (must be in same tenant)
  if p_parent_code is not null and v_tenant_id is not null then
    select id
      into v_parent_id
      from public.accounts
     where tenant_id = v_tenant_id  -- ✅ Filter by tenant
       and code = p_parent_code
     limit 1;
  elsif p_parent_code is not null and v_tenant_id is null then
    -- Backward compatibility for single-tenant
    select id
      into v_parent_id
      from public.accounts
     where code = p_parent_code
     limit 1;
  end if;
```

## Why This Matters

**Multi-Tenant Data Isolation**: Without filtering by `tenant_id`, the function could:
- Find a parent account belonging to **another tenant**
- Create accounts with **cross-tenant references** (data leak!)
- Violate the core principle: "EVERY piece of data belongs to ONE tenant"

**Example Scenario**:
- Tenant A has account "1100" (Activos)
- Tenant B creates account "1105" with parent "1100"
- Without fix: Tenant B's account would reference Tenant A's parent ❌
- With fix: Tenant B's account gets NULL parent (correct) ✅

## Deployment

**Copy the ENTIRE `core_schema.sql` file and run it in Supabase SQL Editor**:

1. Open Supabase Dashboard → SQL Editor
2. Click "New Query"
3. Copy-paste the entire contents of `supabase/sql/core_schema.sql`
4. Click "Run" (RUN button, not F5)
5. Wait for "Success. No rows returned" message

**This will update**:
- `ensure_account()` - Fixed parent lookup with tenant filtering
- `create_purchase_invoice_journal_entry()` - Already has debug logging and tenant_id
- All other fixed functions from previous deployments

## Verification

After deployment, test journal entry creation:

```sql
-- Reset invoice to draft
UPDATE purchase_invoices 
SET status = 'draft', confirmed_date = NULL 
WHERE id = 'c8dbd3ef-5b8e-4cef-8070-1cc3655f56a0';

-- Move to confirmed (should create journal entry)
UPDATE purchase_invoices 
SET status = 'confirmed', confirmed_date = now() 
WHERE id = 'c8dbd3ef-5b8e-4cef-8070-1cc3655f56a0';

-- Check for journal entry
SELECT * FROM journal_entries 
WHERE source_reference = 'c8dbd3ef-5b8e-4cef-8070-1cc3655f56a0';

-- Should see 1 row with 3 journal lines:
-- DR 1105 Inventarios (subtotal)
-- DR 1107 IVA Crédito Fiscal (tax)
-- CR 2101 Cuentas por Pagar Proveedores (total)
```

## What This Fixes

✅ **Multi-tenant isolation** in parent account lookups
✅ **Prevents cross-tenant data leaks** through account hierarchy
✅ **Journal entries will now be created** when purchase invoices are confirmed
✅ **All accounting automations** that depend on ensure_account() will work correctly

## Status

- ✅ Code updated in `core_schema.sql`
- ⚠️ **DEPLOYMENT PENDING** - Run the SQL file in Supabase SQL Editor
