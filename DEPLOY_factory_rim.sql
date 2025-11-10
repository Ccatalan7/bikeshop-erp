-- ========================================
-- Deploy to Supabase: Add Factory Rim to Bikes
-- ========================================
-- COPY THIS SQL AND RUN IN SUPABASE SQL EDITOR
--
-- Purpose: Add factory_rim_id to bikes table for "Replace Hub Only" feature
-- Impact: Allows bikes to reference their original rim for hub-only replacements
-- Migration-safe: Uses IF NOT EXISTS to avoid errors on existing columns
-- ========================================

do $$
begin
  -- Add factory rim reference (for "Replace Hub Only" builds)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'bikes' and column_name = 'factory_rim_id'
  ) then
    alter table bikes add column factory_rim_id uuid references wheel_rims(id) on delete set null;
    raise notice 'Added factory_rim_id column';
  else
    raise notice 'Column factory_rim_id already exists';
  end if;
end $$;

-- Verify migration
select 
  column_name, 
  data_type, 
  is_nullable
from information_schema.columns
where table_name = 'bikes'
  and column_name = 'factory_rim_id';
