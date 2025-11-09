# Chart of Accounts Code Format Fix (Nov 8, 2025)

## Problem Identified

Your chart of accounts shows **6-digit expense codes** (610100, 610200, 620100, etc.) instead of the cleaner **4-digit codes** (6101, 6102, 6201, etc.) that you prefer.

**Screenshot shows:**
- 610100 - Sueldos y Salarios
- 610200 - Cotizaciones Previsionales y Salud  
- 610300 - Honorarios Profesionales
- 620100 - Arriendo de Locales

**Expected format:**
- 6101 - Sueldos y Salarios
- 6102 - Cotizaciones Previsionales
- 6103 - Honorarios Profesionales
- 6201 - Arriendo de Locales

---

## Root Cause

There were **TWO different account seeding mechanisms** in `core_schema.sql`:

1. **Legacy INSERT block** (lines 2080-2130): 
   - Used 6-digit codes (610100, 620100, etc.)
   - Was meant for old single-tenant databases
   - **This was the culprit** - it ran when you redeployed the schema

2. **New per-tenant function** (`seed_chart_of_accounts()`):
   - Uses clean 4-digit codes (6101, 6201, etc.)
   - Runs automatically when new tenants are created
   - This is what NEW accounts should use

When you redeployed `core_schema.sql`, the legacy block detected your existing accounts table and inserted the old 6-digit codes.

---

## Solution Applied

### 1. ✅ Removed Legacy Code (core_schema.sql)

**Removed** the old DO block with 6-digit codes (lines 2088-2136).

Now only the modern `seed_chart_of_accounts()` function exists, which uses 4-digit codes.

### 2. 📄 Created Fix Script

**File:** `supabase/sql/FIX_account_codes_to_4_digits.sql`

This script updates all existing 6-digit codes to their 4-digit equivalents:
- 610100 → 6101
- 610200 → 6102
- 620100 → 6201
- etc.

---

## How to Fix Your Database

### Step 1: Run the Fix Script

1. Open **Supabase Dashboard** → SQL Editor
2. Copy the contents of `supabase/sql/FIX_account_codes_to_4_digits.sql`
3. Paste and **Run** the script
4. Check the output to verify all codes were updated

### Step 2: Verify in Your App

1. Open the Chart of Accounts in your app
2. Verify all expense accounts now show 4-digit codes:
   - 6101 - Sueldos y Salarios
   - 6102 - Cotizaciones Previsionales
   - 6103 - Honorarios Profesionales
   - 6201 - Arriendo de Locales
   - etc.

### Step 3: Redeploy Updated core_schema.sql (Optional)

If you want to update the master schema file:

1. Copy the updated `core_schema.sql` 
2. Run it in Supabase SQL Editor
3. This ensures future tenants only get 4-digit codes

---

## Impact on Existing Data

✅ **Journal entries will still work** - They reference accounts by UUID, not by code
✅ **Invoices will still work** - Same reason (UUID references)
✅ **No data loss** - Only the account codes change, not the account IDs

---

## Prevention for Future

The fix ensures:
- ✅ New tenants always get 4-digit codes via `seed_chart_of_accounts()`
- ✅ No more conflicting code formats in the schema
- ✅ Consistent account codes across all tenants

---

## Account Code Format Standard (4-digit)

**Assets (1xxx):**
- 1101 - Caja General
- 1110 - Bancos
- 1130 - Cuentas por Cobrar
- 1140 - Inventario

**Liabilities (2xxx):**
- 2101 - Cuentas por Pagar
- 2110 - IVA Débito Fiscal
- 2120 - IVA Crédito Fiscal

**Equity (3xxx):**
- 3101 - Capital Social
- 3201 - Utilidades Retenidas

**Income (4xxx):**
- 4101 - Ventas de Productos
- 4102 - Servicios de Mantenimiento
- 4201 - Otros Ingresos

**COGS (5xxx):**
- 5101 - Costo de Ventas

**Operating Expenses (6xxx):**
- 6101-6103 - Personnel (Sueldos, Cotizaciones, Honorarios)
- 6201-6205 - Facilities (Arriendo, Servicios, Mantención)
- 6301-6302 - Marketing (Publicidad, Comisiones)
- 6401 - Travel (Viajes)
- 6501-6502 - Insurance & Taxes (Seguros, Patentes)
- 6601 - Financial (Intereses)
- 6701 - Depreciation (Depreciación)

---

## Files Modified

1. ✅ `supabase/sql/core_schema.sql` - Removed legacy 6-digit INSERT block
2. ✅ `supabase/sql/FIX_account_codes_to_4_digits.sql` - Migration script to fix existing data

---

## Next Steps

1. **Run the fix script** in Supabase SQL Editor
2. **Verify** in your app that accounts now show 4-digit codes
3. **Done!** Future tenants will automatically get 4-digit codes
