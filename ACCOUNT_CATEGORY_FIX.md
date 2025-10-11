# 🔧 Account Type and Category Fix

## Issue
When trying to confirm a sales invoice, you got these errors:

**First error:**
```
new row for relation "accounts" violates check constraint "accounts_category_check"
Failing row contains (..., revenue, null, ..., operatingRevenue, ...)
```

**Second error (after first fix):**
```
new row for relation "accounts" violates check constraint "accounts_type_check"
Failing row contains (..., revenue, null, ..., operatingIncome, ...)
```

## Root Cause
The `sales_workflow_redesign.sql` migration had **TWO** errors:
1. Using **`revenue`** as type → Should be **`income`**
2. Using **`operatingRevenue`** as category → Should be **`operatingIncome`**

**Valid types** according to `accounts_type_check`:
- `asset`, `liability`, `equity`, **`income`** ✅, `expense`, `tax`

**Valid categories** according to `accounts_category_check`:
- `currentAsset`, `fixedAsset`, `otherAsset`
- `currentLiability`, `longTermLiability`
- `capital`, `retainedEarnings`
- **`operatingIncome`** ✅, `nonOperatingIncome`
- `costOfGoodsSold`, `operatingExpense`, `financialExpense`
- `taxPayable`, `taxReceivable`, `taxExpense`

## Fix Applied

### 1. Updated Migration File
**File**: `supabase/sql/sales_workflow_redesign.sql`

**Changed**:
```sql
-- Before
v_revenue_account_id := public.ensure_account(
  v_revenue_account_code, v_revenue_account_name, 'revenue', 'operatingRevenue', ...

-- After
v_revenue_account_id := public.ensure_account(
  v_revenue_account_code, v_revenue_account_name, 'income', 'operatingIncome', ...
```

### 2. Updated Fix Script
**File**: `supabase/sql/fix_accounts_category.sql`

This script now updates both `type` and `category` for any existing accounts.

---

## 🚀 How to Fix Your Database

Run these SQL scripts in Supabase **in this order**:

### Step 1: Fix Existing Accounts
```sql
-- In Supabase SQL Editor
-- Run: supabase/sql/fix_accounts_category.sql
```

This will update the account that was already created with the wrong type/category.

### Step 2: Run the Sales Workflow Migration
```sql
-- In Supabase SQL Editor
-- Run: supabase/sql/sales_workflow_redesign.sql
```

This will apply the complete sales workflow redesign with the correct type and category.

---

## ✅ After Running Both Scripts

You should be able to:
1. Confirm sales invoices without errors
2. Journal entries will be created with the correct account type and category
3. All accounting will work properly

---

## 🧪 Test It

1. **Hot restart** your Flutter app (press 'r' in terminal)
2. Create a new sales invoice or use existing one
3. Mark as "Enviada" (sent)
4. Click "Confirmar" (confirm)
5. ✅ Should succeed without errors
6. Check `Contabilidad > Asientos Contables` - journal entry created
7. Check the account in the database:
   ```sql
   SELECT code, name, type, category 
   FROM accounts 
   WHERE code = '4100';
   ```
   Should show: `4100 | Ingresos por Ventas | income | operatingIncome`

---

**Files Modified**:
1. ✅ `supabase/sql/sales_workflow_redesign.sql` - Fixed type and category
2. ✅ `supabase/sql/fix_accounts_category.sql` - Cleanup script (updated)

**Status**: Ready to deploy!
