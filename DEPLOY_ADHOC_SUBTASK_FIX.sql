-- ============================================================================
-- FIX: Allow sub-tasks with prices to create ad-hoc items (WITHOUT duplicates)
-- Date: November 18, 2025
-- Files modified:
--   - supabase/sql/core_schema.sql (lines 12030-12048)
--   - lib/modules/bikeshop/widgets/tasks_tab_view.dart (lines 248-251)
-- ============================================================================

-- ISSUE DESCRIPTION:
-- When adding a sub-task with price to a product/service in the Tasks tab,
-- it should create an ad-hoc item for costing/invoicing purposes, but it was
-- showing both the sub-task AND a duplicate "Ad-hoc" card in the UI.
--
-- SOLUTION:
-- 1. Database: Allow sub-tasks to create ad-hoc items (for invoice generation)
-- 2. UI: Filter out auto-generated ad-hoc items from Tasks tab display
--
-- ============================================================================

-- Update trigger function to create ad-hoc items for ALL tasks with prices
-- (including sub-tasks), not just parent/standalone tasks
create or replace function public.sync_adhoc_task_to_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    -- ✅ UPDATED (Nov 18, 2025): Sub-tasks WITH prices should also create ad-hoc items
    -- These appear as separate line items in pega forms and invoices
    if NEW.is_adhoc and NEW.adhoc_price is not null and NEW.adhoc_price > 0 then
      perform public.create_adhoc_item_for_task(NEW.id);
    end if;
    
  elsif TG_OP = 'UPDATE' then
    -- Price added or updated on task (parent OR sub-task)
    if NEW.is_adhoc and NEW.adhoc_price is not null and 
       (OLD.adhoc_price is null or OLD.adhoc_price != NEW.adhoc_price) then
      
      -- If item exists, update it
      if NEW.adhoc_item_id is not null then
        update mechanic_job_items
        set 
          product_name = 'Ad-hoc: ' || NEW.task_name,
          unit_price = NEW.adhoc_price,
          total_price = NEW.adhoc_price
        where id = NEW.adhoc_item_id;
      else
        -- Create new item
        perform public.create_adhoc_item_for_task(NEW.id);
      end if;
    end if;
    
    -- Price removed
    if OLD.adhoc_price is not null and NEW.adhoc_price is null and NEW.adhoc_item_id is not null then
      delete from mechanic_job_items where id = NEW.adhoc_item_id;
    end if;
  end if;
  
  return null; -- AFTER trigger must return null
end;
$$;

-- Recreate trigger (ensures function is up to date)
drop trigger if exists trg_sync_adhoc_task_to_item on mechanic_job_tasks cascade;
create trigger trg_sync_adhoc_task_to_item
  after insert or update on mechanic_job_tasks
  for each row execute procedure public.sync_adhoc_task_to_item();

-- ============================================================================
-- FLUTTER CHANGES (MANUAL - Apply in IDE):
-- ============================================================================
-- File: lib/modules/bikeshop/widgets/tasks_tab_view.dart
-- Line: ~248
--
-- BEFORE:
--   ..._items.map((item) => _buildItemGroup(item)),
--
-- AFTER:
--   ..._items
--       .where((item) => !item.productName.startsWith('Ad-hoc: '))
--       .map((item) => _buildItemGroup(item)),
--
-- This filters out auto-created ad-hoc items from displaying as duplicate cards
-- ============================================================================

-- ============================================================================
-- TESTING:
-- ============================================================================
-- 1. Create a pega (PG-00006)
-- 2. Add a service: "Mantención Full" with 1h @ $60000/h
-- 3. Add a sub-task under that service: "test" with price $1000
-- 4. EXPECTED RESULT:
--    ✅ Tasks tab shows:
--       - "Mantención Full" card (service) with sub-task "test" ($1000)
--    ✅ NO duplicate "Ad-hoc: test" card
--    ✅ Pega total cost includes $60000 + $1000 = $61000
--    ✅ Generate invoice shows TWO line items:
--       - "Mantención Full" ($60000)
--       - "Ad-hoc: test" ($1000)
-- ============================================================================
