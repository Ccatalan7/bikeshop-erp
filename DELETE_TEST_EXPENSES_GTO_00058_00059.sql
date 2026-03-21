-- ============================================================================
-- DELETE: Test expenses GTO-00058 and GTO-00059 + their linked expense JEs
-- Tenant: 5443b130-cc28-45af-a420-cd500b288890
-- ============================================================================
-- Run this in Supabase SQL Editor.
--
-- What it does:
--   1. Previews expenses GTO-00058 and GTO-00059 for Viñabike
--   2. Deletes linked expense journal entries first
--   3. Deletes the expense rows themselves
--   4. Child rows (`expense_lines`, `expense_payments`, `expense_attachments`)
--      should cascade automatically with the expense delete
--   5. Verifies the rows are gone
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Preview the exact expenses that will be deleted
-- ----------------------------------------------------------------------------
select
  e.id,
  e.tenant_id,
  e.expense_number,
  e.created_at,
  e.issue_date,
  e.supplier_name,
  e.total_amount,
  (
    select count(*)
    from public.journal_entries je
    where je.source_module = 'expenses'
      and (
        je.source_reference = e.expense_number
        or je.source_reference = e.id::text
      )
  ) as linked_expense_je_count
from public.expenses e
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and e.expense_number in ('GTO-00058', 'GTO-00059')
order by e.expense_number;

-- ----------------------------------------------------------------------------
-- 2) Delete the linked JEs first, then the expenses
-- ----------------------------------------------------------------------------
do $$
declare
  v_expense record;
  v_deleted_count integer := 0;
begin
  for v_expense in
    select e.id, e.expense_number
    from public.expenses e
    where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and e.expense_number in ('GTO-00058', 'GTO-00059')
    order by e.expense_number
  loop
    perform public.delete_expense_journal_entry(v_expense.id);

    delete from public.expenses
    where id = v_expense.id
      and tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

    v_deleted_count := v_deleted_count + 1;
    raise notice 'Deleted expense % (%)', v_expense.expense_number, v_expense.id;
  end loop;

  raise notice 'Deleted % expense(s).', v_deleted_count;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) Verification: these should return zero rows
-- ----------------------------------------------------------------------------
select
  e.id,
  e.expense_number,
  e.created_at,
  e.total_amount
from public.expenses e
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and e.expense_number in ('GTO-00058', 'GTO-00059');

select
  je.id,
  je.entry_number,
  je.source_reference,
  je.created_at
from public.journal_entries je
where je.source_module = 'expenses'
  and je.source_reference in ('GTO-00058', 'GTO-00059');
