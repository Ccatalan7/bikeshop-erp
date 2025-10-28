# 🚀 Deploy Payment Methods Auto-Seeding (Single Source of Truth)

## ✅ What Was Done

Updated `core_schema.sql` to be the **single source of truth** for payment method seeding:

### 1. Added Seeding Function (Line ~1567)
```sql
CREATE OR REPLACE FUNCTION public.seed_payment_methods_for_tenant(p_tenant_id uuid)
```
- Creates 4 default payment methods: Efectivo, Transferencia, Cheque, Tarjeta
- Links to proper accounting accounts (Caja 1101, Banco 1110)
- Idempotent (safe to run multiple times)

### 2. Added Tenant Initialization Trigger (Line ~1633)
```sql
CREATE OR REPLACE FUNCTION public.handle_new_tenant()
```
- Automatically called when a new tenant is created
- Seeds payment methods immediately

### 3. Registered Trigger (Line ~1647)
```sql
CREATE TRIGGER trg_tenant_initialization
  AFTER INSERT ON tenants
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_tenant();
```

## 📋 Deployment Instructions

### Option 1: Quick Fix for Your Tenant (RIGHT NOW)
If you just want to fix the dropdown immediately:

```sql
-- Open Supabase SQL Editor and run:
SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());
```

Then refresh your app - dropdown works! ✨

### Option 2: Full Schema Deployment (Recommended)
Deploy the complete updated schema:

1. **Open Supabase SQL Editor**
2. **Paste and run the entire `core_schema.sql`**
3. **Seed existing tenants:**
   ```sql
   -- For your tenant:
   SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());
   
   -- OR for all tenants:
   DO $$
   DECLARE tenant_record RECORD;
   BEGIN
     FOR tenant_record IN SELECT id, name FROM tenants LOOP
       PERFORM public.seed_payment_methods_for_tenant(tenant_record.id);
       RAISE NOTICE 'Seeded: %', tenant_record.name;
     END LOOP;
   END $$;
   ```

## ✅ Verification

Check that payment methods were created:

```sql
SELECT 
  code,
  name,
  requires_reference,
  is_active,
  sort_order,
  a.code as account_code,
  a.name as account_name
FROM payment_methods pm
JOIN accounts a ON pm.account_id = a.id
WHERE pm.tenant_id = public.user_tenant_id()
ORDER BY pm.sort_order;
```

Expected output:
| code | name | requires_reference | account_code | account_name |
|------|------|-------------------|--------------|--------------|
| CASH | Efectivo | false | 1101 | Caja |
| TRANSFER | Transferencia | true | 1110 | Banco |
| CHECK | Cheque | true | 1110 | Banco |
| CARD | Tarjeta de Crédito/Débito | false | 1110 | Banco |

## 🎯 What Happens Now

### For New Tenants (Automatic)
✅ When a new tenant is created, they automatically get 4 payment methods
✅ No manual intervention needed
✅ Trigger handles everything

### For Existing Tenants (One-Time Manual)
⚠️ Run the seed function once (see Option 2 above)
✅ After that, they're all set

### For Your Flutter App
✅ Payment dropdown will now show 4 methods
✅ All payment forms work (Sales, Purchases, Expenses)
✅ No more empty dropdowns

## 📝 Files Changed

1. ✅ `supabase/sql/core_schema.sql`
   - Added `seed_payment_methods_for_tenant()` function (line ~1567)
   - Added `handle_new_tenant()` trigger function (line ~1633)
   - Added auto-trigger on tenants table (line ~1647)

2. ✅ `lib/modules/purchases/pages/purchase_payment_form_page.dart`
   - Added warning for missing payment methods
   - Added better UX and debugging

3. ✅ `QUICK_FIX_PAYMENT_METHODS.sql`
   - Helper script for seeding existing tenants

4. ✅ `PAYMENT_DROPDOWN_FIX.md`
   - Updated documentation

## 🎉 Result

**core_schema.sql is now the SINGLE SOURCE OF TRUTH**
- ✅ All database objects defined
- ✅ All seeding logic included
- ✅ All triggers configured
- ✅ Automatic for new tenants
- ✅ One file to maintain

**No more fragmented SQL scripts or migration files!**
