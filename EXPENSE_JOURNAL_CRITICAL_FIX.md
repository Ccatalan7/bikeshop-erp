# 🚨 CRITICAL FIX: Expense Journal Entries Not Creating

## Root Cause

**Race condition in trigger execution order:**

1. User creates expense with `posting_status='posted'`
2. `expenses` table INSERT happens
3. **Trigger fires immediately** → calls `create_expense_journal_entry()`
4. Function finds **ZERO expense_lines** (they haven't been inserted yet!)
5. Falls back to using category default account (code '5200')
6. Flutter service THEN inserts expense_lines (too late!)
7. Result: Journal entry created with wrong account OR not at all

## The Problem Flow

```
Flutter: saveExpense()
  ↓
  INSERT INTO expenses (posting_status='posted')
  ↓
  TRIGGER: process_expense_change() ← FIRES IMMEDIATELY
  ↓
  SELECT FROM expense_lines WHERE expense_id = ? ← RETURNS EMPTY!
  ↓
  Fallback to account '5200' (wrong account!)
  ↓
Flutter: _syncExpenseLines()
  ↓
  INSERT INTO expense_lines (account_id=...) ← TOO LATE!
```

## The Solution

**Move journal entry creation to the expense_lines trigger:**

1. Remove journal creation from expense INSERT trigger
2. Add new trigger on `expense_lines` table
3. When lines are inserted/updated/deleted → regenerate journal entry
4. On expense UPDATE (draft→posted) → still works (lines already exist)

## Changes Applied

### 1. Removed journal creation from expense INSERT

**File:** `supabase/sql/core_schema.sql`
**Line:** ~3760-3765

```sql
-- BEFORE:
if TG_OP = 'INSERT' then
  perform public.recalculate_expense_totals(NEW.id);
  if v_new_posted then
    perform public.create_expense_journal_entry(NEW.id); ← REMOVED
  end if;
  return NEW;

-- AFTER:
if TG_OP = 'INSERT' then
  perform public.recalculate_expense_totals(NEW.id);
  -- Journal entry will be created by expense_lines trigger
  return NEW;
```

### 2. Added expense_lines trigger

**File:** `supabase/sql/core_schema.sql`
**Location:** After `trg_expense_payments_change` (~line 3850)

```sql
create or replace function public.handle_expense_line_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense_id uuid;
  v_posting_status text;
begin
  if TG_OP = 'DELETE' then
    v_expense_id := OLD.expense_id;
  else
    v_expense_id := NEW.expense_id;
  end if;

  select posting_status into v_posting_status
    from public.expenses
   where id = v_expense_id;

  if lower(coalesce(v_posting_status, 'draft')) = 'posted' then
    perform public.delete_expense_journal_entry(v_expense_id);
    perform public.create_expense_journal_entry(v_expense_id);
  end if;

  perform public.recalculate_expense_totals(v_expense_id);

  if TG_OP = 'DELETE' then
    return OLD;
  else
    return NEW;
  end if;
end;
$$;

create trigger trg_expense_lines_change
  after insert or update or delete on public.expense_lines
  for each row execute procedure public.handle_expense_line_change();
```

## How It Works Now

```
Flutter: saveExpense()
  ↓
  INSERT INTO expenses (posting_status='posted')
  ↓
  TRIGGER: process_expense_change()
  ↓
  Recalculates totals (no journal entry yet)
  ↓
Flutter: _syncExpenseLines()
  ↓
  INSERT INTO expense_lines (account_id=...) ← Lines inserted!
  ↓
  TRIGGER: handle_expense_line_change() ← NOW FIRES!
  ↓
  SELECT posting_status FROM expenses
  ↓
  Is 'posted'? → Yes!
  ↓
  DELETE old journal entry (if exists)
  ↓
  CREATE new journal entry WITH expense_lines data ✅
```

## Testing Steps

1. **Deploy the schema:**
   ```bash
   # Copy updated core_schema.sql to Supabase SQL Editor
   # Run the entire file (or just the changed sections)
   ```

2. **Create a test expense:**
   - Go to Accounting → Expenses
   - Click "+ Nuevo Gasto"
   - Fill in:
     - Proveedor: Test Supplier
     - Concepto: Test Expense
     - Cuenta: Select expense account (e.g., "Sueldos y Salarios")
     - Monto Neto: 10000
     - Método de Pago: Select payment method
   - Save

3. **Verify journal entry:**
   ```sql
   -- Check journal entry was created
   SELECT * FROM journal_entries 
   WHERE source_module = 'expenses' 
   ORDER BY created_at DESC 
   LIMIT 1;

   -- Check journal lines use correct account
   SELECT jl.*, a.code, a.name
   FROM journal_lines jl
   JOIN journal_entries je ON je.id = jl.entry_id
   JOIN accounts a ON a.id = jl.account_id
   WHERE je.source_module = 'expenses'
   ORDER BY je.created_at DESC, jl.debit_amount DESC;
   ```

4. **Expected results:**
   - 1 journal_entry with `source_module='expenses'`
   - Journal lines with:
     - Debit: expense account (code 610100, 620100, etc. from expense_lines)
     - Debit: IVA account (code 1140) if tax > 0
     - Credit: cash/liability account from payment method
   - Totals balanced (total_debit = total_credit)

## Affected Components

- ✅ `supabase/sql/core_schema.sql` - Trigger logic updated
- ✅ Flutter expense form - No changes needed (already sets posting_status='posted')
- ✅ Dashboard charts - No changes needed (query journal_entries by entry_date)
- ✅ Expense service - No changes needed (sync pattern correct)

## Why This Wasn't Caught Earlier

- The trigger technically "worked" (no errors thrown)
- It fell back to account code '5200' silently
- Dashboard queries returned empty because account '5200' might not have been seeded
- Or entries were created but not visible because of date filtering

## Next Steps

1. Deploy `core_schema.sql` changes
2. Test expense creation
3. Verify dashboard charts populate
4. Consider adding similar pattern to other modules if they have line items
   - Purchase invoices with purchase_invoice_lines
   - Sales invoices with invoice_items (might already be correct)

---

**Status:** ✅ Fixed and ready to deploy
**Priority:** 🔴 CRITICAL - Accounting module non-functional without this
**Estimated Deploy Time:** 2 minutes
