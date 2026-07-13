-- ============================================================================
-- RECOVERY: Rebuild ALL missing expense journal entries for Viñabike
-- Tenant: 5443b130-cc28-45af-a420-cd500b288890
-- ============================================================================
-- Run this in Supabase SQL Editor.
--
-- What it does:
--   1. Lists all posted Viñabike expenses missing a linked JE
--   2. Recalculates totals for each expense
--   3. Deletes any stale expense JE (by expense_number or legacy UUID reference)
--   4. Recreates the correct JE
--   5. Prints how many expenses were repaired
--   6. Shows remaining missing rows after recovery
--
-- Missing JE criteria in this script:
--   - expense belongs to Viñabike tenant
--   - posting_status = 'posted'
--   - total_amount > 0
--   - there is NO `journal_entries` row with:
--       source_module = 'expenses'
--       source_reference = expenses.expense_number
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Preview: which expenses are currently missing a JE?
-- ----------------------------------------------------------------------------
select
  e.id,
  e.expense_number,
  e.issue_date,
  e.supplier_name,
  e.posting_status,
  e.payment_status,
  e.total_amount,
  (
    select count(*)
    from public.expense_lines el
    where el.expense_id = e.id
  ) as expense_line_count
from public.expenses e
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and lower(coalesce(e.posting_status, 'draft')) = 'posted'
  and coalesce(e.total_amount, 0) > 0
  and not exists (
    select 1
    from public.journal_entries je
    where je.source_module = 'expenses'
      and je.source_reference = e.expense_number
  )
order by e.issue_date desc, e.expense_number desc;

-- ----------------------------------------------------------------------------
-- 2) Bulk recovery
-- ----------------------------------------------------------------------------
do $$
declare
  v_expense record;
  v_fixed_count integer := 0;
begin
  for v_expense in
    select
      e.id,
      e.expense_number
    from public.expenses e
    where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and lower(coalesce(e.posting_status, 'draft')) = 'posted'
      and coalesce(e.total_amount, 0) > 0
      and not exists (
        select 1
        from public.journal_entries je
        where je.source_module = 'expenses'
          and je.source_reference = e.expense_number
      )
    order by e.issue_date asc nulls last, e.created_at asc nulls last
  loop
    perform public.recalculate_expense_totals(v_expense.id);
    perform public.delete_expense_journal_entry(v_expense.id);
    perform public.create_expense_journal_entry(v_expense.id);

    v_fixed_count := v_fixed_count + 1;
    raise notice 'Recovered expense JE: % (%)', v_expense.expense_number, v_expense.id;
  end loop;

  raise notice 'Total recovered missing expense JEs: %', v_fixed_count;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) Verification summary: how many are still missing?
-- ----------------------------------------------------------------------------
select
  count(*) as remaining_missing_expense_je_count
from public.expenses e
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and lower(coalesce(e.posting_status, 'draft')) = 'posted'
  and coalesce(e.total_amount, 0) > 0
  and not exists (
    select 1
    from public.journal_entries je
    where je.source_module = 'expenses'
      and je.source_reference = e.expense_number
  );

-- ----------------------------------------------------------------------------
-- 4) Detailed verification: any rows still missing after recovery
-- ----------------------------------------------------------------------------
select
  e.id,
  e.expense_number,
  e.issue_date,
  e.supplier_name,
  e.posting_status,
  e.payment_status,
  e.total_amount
from public.expenses e
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and lower(coalesce(e.posting_status, 'draft')) = 'posted'
  and coalesce(e.total_amount, 0) > 0
  and not exists (
    select 1
    from public.journal_entries je
    where je.source_module = 'expenses'
      and je.source_reference = e.expense_number
  )
order by e.issue_date desc, e.expense_number desc;

-- ----------------------------------------------------------------------------
-- 5) Optional audit view: latest recovered expense journal entries
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
join public.journal_entries je
  on je.source_module = 'expenses'
 and je.source_reference = e.expense_number
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and lower(coalesce(e.posting_status, 'draft')) = 'posted'
order by je.created_at desc
limit 50;
