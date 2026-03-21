-- ============================================================================
-- DELETE: Last 2 expenses for Viñabike + their linked expense JEs
-- Tenant: 5443b130-cc28-45af-a420-cd500b288890
-- ============================================================================
-- Run this in Supabase SQL Editor.
--
-- What it does:
--   1. Previews the last 2 expenses for Viñabike (newest by created_at)
--   2. Deletes linked expense journal entries (and their journal_lines via FK cascade)
--   3. Deletes the expense rows
--   4. Child expense records (`expense_lines`, `expense_payments`, `expense_attachments`)
--      should cascade automatically from the expense delete
--   5. Shows a verification query after deletion
--
-- IMPORTANT:
--   - This is based on the LAST 2 created expenses for the Viñabike tenant.
--   - Review the preview query result before running the DO block.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Preview which expenses will be deleted
-- ----------------------------------------------------------------------------
with last_two as (
  select
    e.id,
    e.expense_number,
    e.created_at,
    e.issue_date,
    e.supplier_name,
    e.total_amount
  from public.expenses e
  where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  order by e.created_at desc, e.expense_number desc
  limit 2
)
select
  lt.*,
  (
    select count(*)
    from public.journal_entries je
    where je.source_module = 'expenses'
      and (
        je.source_reference = lt.expense_number
        or je.source_reference = lt.id::text
      )
  ) as linked_expense_je_count
from last_two lt
order by lt.created_at desc, lt.expense_number desc;

-- ----------------------------------------------------------------------------
-- 2) Delete the linked expense JEs first, then the expenses
-- ----------------------------------------------------------------------------
do $$
declare
  v_expense record;
  v_deleted_count integer := 0;
begin
  for v_expense in
    select
      e.id,
      e.expense_number,
      e.created_at
    from public.expenses e
    where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    order by e.created_at desc, e.expense_number desc
    limit 2
  loop
    -- Delete any expense JE linked by current expense_number reference
    -- or older legacy UUID reference.
    perform public.delete_expense_journal_entry(v_expense.id);

    -- Delete the expense itself.
    delete from public.expenses
    where id = v_expense.id
      and tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

    v_deleted_count := v_deleted_count + 1;
    raise notice 'Deleted expense % (%)', v_expense.expense_number, v_expense.id;
  end loop;

  raise notice 'Deleted % expense(s) for Viñabike.', v_deleted_count;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) Verification: show the current newest 5 expenses after cleanup
-- ----------------------------------------------------------------------------
select
  e.id,
  e.expense_number,
  e.created_at,
  e.issue_date,
  e.supplier_name,
  e.total_amount
from public.expenses e
where e.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by e.created_at desc, e.expense_number desc
limit 5;
