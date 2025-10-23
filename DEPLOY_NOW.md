# 🚨 CRITICAL: Expense Journal Entries Not Recording

## The Problem

**THE SCHEMA CHANGES HAVE NOT BEEN DEPLOYED YET!**

I fixed the code in `core_schema.sql`, but it's only sitting in your local file. Your database still has the old broken triggers!

## What I Fixed (But Needs Deployment)

1. **Removed** journal entry creation from expense INSERT trigger (was creating entries with 0 lines)
2. **Added** new trigger on `expense_lines` table that creates journal entries AFTER lines are inserted
3. **Renamed** journal_entries.date → entry_date (with migration)

## How to Deploy (3 Options)

### Option 1: Supabase Dashboard (RECOMMENDED - Takes 2 minutes)

1. **Open Supabase Dashboard:**
   - Go to https://supabase.com/dashboard
   - Select your project
   - Click "SQL Editor" in left sidebar

2. **Copy the entire schema:**
   - Open `supabase/sql/core_schema.sql` in VS Code
   - Select ALL (Cmd+A)
   - Copy (Cmd+C)

3. **Paste and run:**
   - Paste into Supabase SQL Editor
   - Click "RUN" button (bottom right)
   - Wait for success message

4. **Verify deployment:**
   - Copy the contents of `DEPLOY_CHECK.sql`
   - Paste in a NEW query in SQL Editor
   - Run it
   - Should see ✅ for all checks

### Option 2: Supabase CLI (If you have it installed)

```bash
# Install Supabase CLI if you don't have it
brew install supabase/tap/supabase

# Login
supabase login

# Link project
supabase link --project-ref YOUR_PROJECT_REF

# Deploy schema
supabase db push
```

### Option 3: Direct psql (Requires PostgreSQL installed)

```bash
# Install PostgreSQL if needed
brew install postgresql

# Get your database URL from Supabase dashboard
# Settings → Database → Connection string (Direct connection)

# Run the schema
psql "your-connection-string" -f supabase/sql/core_schema.sql
```

## After Deployment

1. **Run the check script:**
   - Go to Supabase SQL Editor
   - Copy/paste `DEPLOY_CHECK.sql`
   - Run it
   - Verify all checks pass ✅

2. **Test expense creation:**
   - Go to Accounting → Expenses
   - Create a new expense with:
     - Proveedor: Test
     - Concepto: Test expense
     - Cuenta: Any expense account (e.g., Sueldos y Salarios)
     - Monto Neto: 10000
     - Método de Pago: Any payment method
   - Click Save

3. **Verify journal entry:**
   - Run this in SQL Editor:
   ```sql
   SELECT 
     e.expense_number,
     e.posting_status,
     e.total_amount,
     (SELECT COUNT(*) FROM expense_lines WHERE expense_id = e.id) as lines,
     (SELECT COUNT(*) FROM journal_entries WHERE source_module = 'expenses' AND source_reference = e.id::text) as journals
   FROM expenses e
   ORDER BY e.created_at DESC
   LIMIT 5;
   ```
   - Last expense should have `journals = 1`

4. **Check dashboard:**
   - Refresh your dashboard
   - Expense chart should now show data

## Why This Happened

1. You edited `core_schema.sql` locally (or I edited it for you)
2. But local file ≠ database
3. Database still has old broken triggers
4. Need to **DEPLOY** to apply changes

## Quick Status Check

**Before deploying, your database has:**
- ❌ Old expense trigger (creates journal on INSERT, before lines exist)
- ❌ No expense_lines trigger (missing!)
- ❌ journal_entries.date column (should be entry_date)

**After deploying, your database will have:**
- ✅ Fixed expense trigger (no journal on INSERT)
- ✅ New expense_lines trigger (creates journal AFTER lines inserted)
- ✅ journal_entries.entry_date column (renamed)

---

**Next Step:** Go to Supabase Dashboard → SQL Editor → Paste `core_schema.sql` → RUN

This takes literally 2 minutes. I promise it will fix your issue! 🎯
