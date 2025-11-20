-- PHASE 1: Extend mechanic_job_items Schema
-- Safe schema extension - adds columns for unified items model
-- NO BEHAVIOR CHANGES - completely backward compatible
-- Deploy this first, test that everything still works exactly the same

-- Add item_type column: 'product' (stock items), 'service' (labor/services), 'adhoc' (manual entries)
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_items' 
      and column_name = 'item_type'
  ) then
    alter table mechanic_job_items 
    add column item_type text not null default 'product' 
    check (item_type in ('product', 'service', 'adhoc'));
    
    raise notice '✅ Added item_type column to mechanic_job_items';
  else
    raise notice '⏭️ item_type column already exists';
  end if;
  
  -- Add service_product_id: For services that reference products table (like labor.service_product_id)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_items' 
      and column_name = 'service_product_id'
  ) then
    alter table mechanic_job_items 
    add column service_product_id uuid 
    references products(id) on delete set null;
    
    raise notice '✅ Added service_product_id column to mechanic_job_items';
  else
    raise notice '⏭️ service_product_id column already exists';
  end if;
  
  -- Add index for efficient service lookups
  if not exists (
    select 1 from pg_indexes 
    where tablename = 'mechanic_job_items' 
      and indexname = 'idx_mechanic_job_items_service_product_id'
  ) then
    create index idx_mechanic_job_items_service_product_id 
    on mechanic_job_items(service_product_id) 
    where service_product_id is not null;
    
    raise notice '✅ Added index for service_product_id';
  else
    raise notice '⏭️ Index already exists';
  end if;
end $$;

-- Verification query: Check that columns were added
select 
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_name = 'mechanic_job_items'
  and column_name in ('item_type', 'service_product_id')
order by column_name;

-- Expected output:
-- item_type           | text | NO  | 'product'::text
-- service_product_id  | uuid | YES | NULL

-- ✅ PHASE 1 COMPLETE
-- Next: Test that everything still works (adding products, services, deleting jobs)
-- Then: Proceed to Phase 2 (dual-write mode)
