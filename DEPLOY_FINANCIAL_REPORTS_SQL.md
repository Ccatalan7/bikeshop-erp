# 🚀 Deployment Guide: Financial Reports SQL Functions

## ⚠️ IMPORTANT: Database Schema Deployment Required

The Financial Reports module requires SQL functions to be deployed to your Supabase database. If you see errors like:

```
La función de base de datos no existe.
```

or

```
function public.get_income_statement_data does not exist
```

**You need to deploy the SQL schema!**

---

## 📋 Deployment Steps

### Option 1: Supabase Dashboard (Recommended for Beginners)

1. **Open Supabase Dashboard**
   - Go to https://supabase.com/dashboard
   - Select your project

2. **Navigate to SQL Editor**
   - Click on "SQL Editor" in the left sidebar
   - Click "New Query"

3. **Copy the Schema File**
   - Open: `supabase/sql/core_schema.sql`
   - Copy ALL the contents (4585 lines)

4. **Paste and Execute**
   - Paste into the SQL Editor
   - Click "Run" (or press Ctrl+Enter)
   - Wait for execution to complete (may take 30-60 seconds)

5. **Verify Success**
   - Look for green success messages
   - If you see errors, scroll up to find the first error and fix it

---

### Option 2: Supabase CLI (Recommended for Developers)

#### Prerequisites
```powershell
# Install Supabase CLI if not already installed
scoop install supabase
# or
npm install -g supabase
```

#### Deployment Commands
```powershell
# 1. Navigate to project directory
cd C:\dev\ProjectVinabike

# 2. Login to Supabase (if not already logged in)
supabase login

# 3. Link to your project (if not already linked)
supabase link --project-ref YOUR_PROJECT_REF

# 4. Deploy the schema
supabase db push
# or manually execute the file:
supabase db execute -f supabase/sql/core_schema.sql
```

---

### Option 3: psql Command Line (Advanced)

If you have direct PostgreSQL access:

```powershell
# Get your connection string from Supabase Dashboard > Settings > Database
psql "postgresql://postgres:[YOUR_PASSWORD]@[YOUR_PROJECT_REF].supabase.co:5432/postgres" -f supabase/sql/core_schema.sql
```

---

## ✅ What Gets Deployed

The `core_schema.sql` file contains **10 financial reporting functions**:

### 1. **get_account_balance** 
- Purpose: Get balance for a specific account in a date range
- Used by: All reports

### 2. **get_balances_by_type**
- Purpose: Get balances grouped by account type (asset, liability, etc.)
- Used by: Balance Sheet

### 3. **get_balances_by_category**
- Purpose: Get balances grouped by detailed category
- Used by: Income Statement

### 4. **get_trial_balance**
- Purpose: Get all accounts with activity
- Used by: Trial Balance report (coming soon)

### 5. **calculate_net_income**
- Purpose: Calculate net income for a period
- Used by: Income Statement, Balance Sheet (for ROE/ROA)

### 6. **get_cumulative_balance**
- Purpose: Get cumulative balance from inception to date
- Used by: Balance Sheet

### 7. **get_cumulative_balances_by_type**
- Purpose: Get cumulative balances by account type
- Used by: Balance Sheet

### 8. **verify_accounting_equation**
- Purpose: Verify Assets = Liabilities + Equity
- Used by: Balance Sheet validation

### 9. **get_income_statement_data** ⭐
- Purpose: Pre-formatted Income Statement data
- Used by: Income Statement Page

### 10. **get_balance_sheet_data** ⭐
- Purpose: Pre-formatted Balance Sheet data
- Used by: Balance Sheet Page

---

## 🔍 Verification

After deployment, verify the functions exist:

```sql
-- Run this in Supabase SQL Editor
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE 'get_%statement%'
OR routine_name LIKE 'calculate_%'
OR routine_name LIKE 'verify_%';
```

**Expected Results:** You should see 10 functions listed.

---

## 🐛 Troubleshooting

### Error: "permission denied for schema public"
**Solution:** Make sure you're using the postgres role or have sufficient permissions.

### Error: "syntax error near..."
**Solution:** 
1. Make sure you copied the ENTIRE file (all 4585 lines)
2. Don't modify the file before deploying
3. Execute the file as-is

### Error: "function already exists"
**Solution:** The functions use `CREATE OR REPLACE`, so this shouldn't happen. But if it does:
```sql
-- Drop and recreate
DROP FUNCTION IF EXISTS public.get_income_statement_data CASCADE;
DROP FUNCTION IF EXISTS public.get_balance_sheet_data CASCADE;
-- Then re-run the schema file
```

### Error: "relation does not exist"
**Solution:** Make sure your base tables exist first:
- `accounts`
- `journal_entries`
- `journal_lines`

If they don't exist, you need to deploy the full schema first.

---

## 📊 Testing After Deployment

Once deployed, test the reports:

1. **Navigate to Financial Reports**
   - Open app: Contabilidad → Reportes Financieros

2. **Test Income Statement**
   - Click "Estado de Resultados"
   - Select date range (e.g., "Mes Actual")
   - Should load without errors

3. **Test Balance Sheet**
   - Click "Balance General"
   - Select a date
   - Should show accounting equation validation

4. **Expected Results**
   - If you have no journal entries yet, reports will show zeros
   - If you have data, reports should display properly formatted lines
   - No error messages should appear

---

## 🔄 Re-deploying (After Schema Updates)

If the schema is updated in the future:

```powershell
# Pull latest changes
git pull

# Re-deploy schema
supabase db execute -f supabase/sql/core_schema.sql
```

The `CREATE OR REPLACE` statements ensure safe re-deployment without data loss.

---

## 📞 Need Help?

If you encounter issues:

1. **Check Supabase Logs**
   - Dashboard → Logs → Postgres Logs
   - Look for error messages

2. **Verify Connection**
   - Make sure your Flutter app is connected to the correct Supabase project
   - Check `lib/shared/config/supabase_config.dart`

3. **Test SQL Manually**
   - Try running the functions manually in SQL Editor:
   ```sql
   SELECT * FROM get_income_statement_data(
     '2025-01-01'::date,
     '2025-12-31'::date
   );
   ```

---

## ✅ Success Criteria

You'll know the deployment succeeded when:

- ✅ No errors in Supabase SQL Editor
- ✅ All 10 functions visible in database
- ✅ Income Statement page loads without errors
- ✅ Balance Sheet page loads without errors
- ✅ Reports display data (or zeros if no journal entries)

---

## 🎯 Next Steps After Deployment

1. **Create Test Data**
   - Add some journal entries in Contabilidad → Asientos contables
   - Make sure entries are "posted" (status = 'posted')

2. **Generate Your First Report**
   - Go to Estado de Resultados
   - Select current month
   - See your financial data!

3. **Explore Financial Ratios**
   - Go to Balance General
   - View liquidity, leverage, and profitability ratios

4. **Export Reports** (Coming Soon)
   - PDF export will be available in Phase 4
   - Excel export with formulas

---

**Happy Reporting! 📊✨**
