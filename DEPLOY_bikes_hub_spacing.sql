-- ========================================
-- Deploy to Supabase: Add Hub Spacing to Bikes
-- ========================================
-- COPY THIS SQL AND RUN IN SUPABASE SQL EDITOR
--
-- Purpose: Add hub spacing columns to bikes table for smart hub filtering
-- Impact: Enables wizard to show ONLY hubs that match bike's exact OLD measurements
-- Migration-safe: Uses IF NOT EXISTS to avoid errors on existing columns
-- ========================================

do $$
begin
  -- Add front hub spacing (100mm standard, 110mm Boost)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'bikes' and column_name = 'front_hub_spacing_mm'
  ) then
    alter table bikes add column front_hub_spacing_mm numeric(5,1);
    raise notice 'Added front_hub_spacing_mm column';
  else
    raise notice 'Column front_hub_spacing_mm already exists';
  end if;
  
  -- Add rear hub spacing (130mm, 135mm, 142mm, 148mm Boost)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'bikes' and column_name = 'rear_hub_spacing_mm'
  ) then
    alter table bikes add column rear_hub_spacing_mm numeric(5,1);
    raise notice 'Added rear_hub_spacing_mm column';
  else
    raise notice 'Column rear_hub_spacing_mm already exists';
  end if;
  
  -- Add spoke count (24, 28, 32, 36, 40)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'bikes' and column_name = 'spoke_count'
  ) then
    alter table bikes add column spoke_count integer check (spoke_count in (24, 28, 32, 36, 40));
    raise notice 'Added spoke_count column';
  else
    raise notice 'Column spoke_count already exists';
  end if;
end $$;

-- Verify migration
select 
  column_name, 
  data_type, 
  is_nullable
from information_schema.columns
where table_name = 'bikes'
  and column_name in ('front_hub_spacing_mm', 'rear_hub_spacing_mm', 'spoke_count')
order by column_name;
