# Purchase Invoice SQL Fixes

## Issue
When running the SQL scripts, you got an error:
```
ERROR: 42P01: relation "chart_of_accounts" does not exist
```

## Root Cause
The SQL scripts were using incorrect table and column names that didn't match your actual database schema.

## Fixes Applied

### 1. Table Name Corrections

| Incorrect Name | Correct Name |
|----------------|--------------|
| `chart_of_accounts` | `accounts` |
| `journal_entry_lines` | `journal_lines` |

### 2. Column Name Corrections

#### In `accounts` table:
| Incorrect | Correct |
|-----------|---------|
| `category: 'current_assets'` | `category: 'currentAsset'` |
| `category: 'current_liabilities'` | `category: 'currentLiability'` |
| `category: 'cost_of_sales'` | `category: 'costOfGoodsSold'` |

#### In `journal_lines` table:
| Incorrect | Correct |
|-----------|---------|
| `journal_entry_id` | `entry_id` |
| `debit` | `debit_amount` |
| `credit` | `credit_amount` |
| *(missing)* | `account_code` |
| *(missing)* | `account_name` |

#### In `journal_entries` table:
| Incorrect | Correct |
|-----------|---------|
| `reference_type` | `source_module` |
| `reference_id` | `source_reference` |
| *(missing)* | `type` (e.g., 'purchase', 'sale', 'adjustment') |

### 3. Files Updated

✅ **`supabase/sql/purchase_invoice_accounts_setup.sql`**
- Changed `chart_of_accounts` → `accounts`
- Updated category values to camelCase

✅ **`supabase/sql/purchase_invoice_workflow.sql`**
- Changed `chart_of_accounts` → `accounts`
- Changed `journal_entry_lines` → `journal_lines`
- Changed `journal_entry_id` → `entry_id`
- Changed `debit`/`credit` → `debit_amount`/`credit_amount`
- Added `account_code` and `account_name` columns (fetched from `accounts` table)
- Updated verification queries

## How to Apply

### Step 1: Run Accounts Setup (Optional but Recommended)
```sql
-- Run this in Supabase SQL Editor
\i supabase/sql/purchase_invoice_accounts_setup.sql
```

Or copy/paste the contents into Supabase Dashboard → SQL Editor

Expected output:
```
code | name                  | type     | category            | is_active
-----|---------------------- |----------|---------------------|----------
1105 | Inventario            | asset    | currentAsset        | true
1107 | IVA Crédito Fiscal    | asset    | currentAsset        | true
2101 | Proveedores           | liability| currentLiability    | true
5101 | Costo de Ventas       | expense  | costOfGoodsSold     | true
```

### Step 2: Run Workflow Script
```sql
-- Run this in Supabase SQL Editor
\i supabase/sql/purchase_invoice_workflow.sql
```

Or copy/paste the contents into Supabase Dashboard → SQL Editor

Expected output: Multiple verification queries showing:
- Purchase invoice status distribution
- Stock movements from purchases
- Journal entries created

## Verification

After running both scripts, verify everything works:

```sql
-- 1. Check accounts exist
SELECT code, name, type, category 
FROM accounts 
WHERE code IN ('1105', '1107', '2101', '5101');

-- 2. Check functions exist
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name LIKE '%purchase%invoice%';

-- 3. Check trigger exists
SELECT trigger_name 
FROM information_schema.triggers 
WHERE trigger_name = 'purchase_invoice_change_trigger';
```

## Summary

The scripts are now fixed and ready to use. The issue was simply that the table and column names didn't match your existing database schema. All corrections have been made to match the actual structure defined in `core_schema.sql`.

**Status:** ✅ Ready to run
