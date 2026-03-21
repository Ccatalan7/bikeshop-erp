-- ============================================================================
-- RECOVERY: Rebuild missing journal entry for expense GTO-00057
-- ============================================================================
-- Run this in Supabase SQL Editor.
--
-- What it does:
--   1. Locates expense `GTO-00057`
--   2. Recalculates totals from `expense_lines`
--   3. Deletes any stale/partial journal entry
--   4. Recreates the correct journal entry
--   5. Shows verification output before and after
--
-- Notes:
--   - Expense numbers are tenant-scoped, so this script resolves the exact row
--     and uses its UUID internally.
--   - `create_expense_journal_entry()` only works when the expense is `posted`
--     and has a non-zero total.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Inspect the target expense before recovery
-- ----------------------------------------------------------------------------
select
  e.id,
  e.tenant_id,
  e.expense_number,
  e.posting_status,
  e.payment_status,
  e.total_amount,
  e.amount_paid,
  e.balance,
  e.payment_account_id,
  e.payment_method_id,
  (
    select count(*)
    from public.expense_lines el
    where el.expense_id = e.id
  ) as expense_line_count,
  (
    select count(*)
    from public.journal_entries je
    where je.source_module = 'expenses'
      and je.source_reference = e.expense_number
  ) as existing_journal_entries
from public.expenses e
where e.expense_number = 'GTO-00057';

-- ----------------------------------------------------------------------------
-- 2) Rebuild the journal entry for GTO-00057
-- ----------------------------------------------------------------------------
do $$
declare
  v_expense_id uuid;
begin
  select id
    into v_expense_id
    from public.expenses
   where expense_number = 'GTO-00057'
   order by created_at desc
   limit 1;

  if v_expense_id is null then
    raise exception 'Expense GTO-00057 was not found.';
  end if;

  perform public.recalculate_expense_totals(v_expense_id);
  perform public.delete_expense_journal_entry(v_expense_id);
  perform public.create_expense_journal_entry(v_expense_id);

  raise notice 'Recovered journal entry for expense GTO-00057 (id=%)', v_expense_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) Verify the recreated journal entry
-- ----------------------------------------------------------------------------
select
  e.expense_number,
  e.total_amount as expense_total,
  je.id as journal_entry_id,
  je.entry_number,
  je.entry_date,
  je.description,
  je.total_debit,
  je.total_credit,
  je.status,
  je.created_at
from public.expenses e
left join public.journal_entries je
  on je.source_module = 'expenses'
 and je.source_reference = e.expense_number
where e.expense_number = 'GTO-00057'
order by je.created_at desc nulls last;

-- Optional detail check: journal lines created for the recovered entry
select
  je.entry_number,
  jl.account_code,
  jl.account_name,
  jl.description,
  jl.debit_amount,
  jl.credit_amount
from public.expenses e
join public.journal_entries je
  on je.source_module = 'expenses'
 and je.source_reference = e.expense_number
join public.journal_lines jl
  on jl.entry_id = je.id
where e.expense_number = 'GTO-00057'
order by je.created_at desc, jl.created_at asc;
