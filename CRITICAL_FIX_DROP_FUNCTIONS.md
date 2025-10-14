# 🚨 CRITICAL FIX: Drop Trigger and Functions in Correct Order

## Issue
User deployed `core_schema.sql` but got error:
```
ERROR: cannot drop function handle_purchase_payment_change() because other objects depend on it
DETAIL: trigger trg_purchase_payments_change on table purchase_payments depends on function handle_purchase_payment_change()
HINT: Use DROP ... CASCADE to drop the dependent objects too.
```

## Root Cause
**Order of operations matters!** Must drop trigger BEFORE dropping the function it depends on.

### Original Problem:
```
"record 'new' has no field 'purchase_invoice_id'"
```

### Why DROP CASCADE is NOT the solution:
- CASCADE would work but is dangerous (drops ALL dependent objects)
- Better to explicitly control the drop order

## The Fix Applied

### Correct Drop Order (Line ~1367):

```sql
-- CRITICAL: Drop trigger FIRST, then function to clear cached type definition
drop trigger if exists trg_purchase_payments_change on public.purchase_payments;
drop function if exists public.handle_purchase_payment_change();

create or replace function public.handle_purchase_payment_change()
returns trigger as $$
...
```

### Then Later, Recreate Trigger (Line ~2370):

```sql
-- Trigger already dropped and function recreated earlier (line ~1367)
-- Now just create the trigger with the refreshed function
create trigger trg_purchase_payments_change
  after insert or update or delete on public.purchase_payments
  for each row execute procedure public.handle_purchase_payment_change();
```

## Why DROP is Needed

PostgreSQL caches composite type definitions in:
1. ✅ **Triggers** - FIXED with DROP TRIGGER + CREATE TRIGGER
2. ✅ **Functions with composite type parameters** - FIXED with DROP FUNCTION + CREATE FUNCTION
3. ✅ **Functions that return trigger** (use NEW/OLD) - FIXED with DROP FUNCTION + CREATE FUNCTION

**CREATE OR REPLACE** alone is NOT enough for functions with composite type parameters - you must **DROP** them first to clear the type cache.

## Deployment Instructions

**User must deploy the updated core_schema.sql again:**

1. **Open Supabase Dashboard** → SQL Editor
2. **Copy ENTIRE** `core_schema.sql` (all 3901 lines)
3. **Paste and Run**
4. **Watch for these messages**:
   ```
   DROP FUNCTION create_purchase_payment_journal_entry
   CREATE FUNCTION create_purchase_payment_journal_entry
   DROP FUNCTION handle_purchase_payment_change
   CREATE FUNCTION handle_purchase_payment_change
   DROP TRIGGER trg_purchase_payments_change
   CREATE TRIGGER trg_purchase_payments_change
   ```
5. **Test payment immediately**

## Verification Query

Run this after deployment to verify functions were recreated:

```sql
-- Check function signatures
SELECT 
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS arguments,
    pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'create_purchase_payment_journal_entry',
    'handle_purchase_payment_change'
  )
ORDER BY p.proname;
```

## Expected Result

After redeployment, payment registration should work:
- ✅ No "purchase_invoice_id" error
- ✅ Payment saves successfully
- ✅ Journal entry created
- ✅ Status updates correctly

---

**Status**: Fixed in core_schema.sql  
**Action Required**: User must redeploy entire schema file  
**Priority**: 🔴 CRITICAL
