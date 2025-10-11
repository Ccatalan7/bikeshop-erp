-- Fix for stock_movement_type enum issue
-- Run this BEFORE running fix_inventory_trigger.sql

-- First, check if movement_type is an enum and convert it to text if needed
do $$
declare
  v_is_enum boolean;
  v_enum_values text[];
begin
  -- Check if movement_type column uses an enum type
  select exists (
    select 1
    from pg_type t
    join pg_enum e on t.oid = e.enumtypid
    join pg_attribute a on a.atttypid = t.oid
    join pg_class c on c.oid = a.attrelid
    where c.relname = 'stock_movements'
      and a.attname = 'movement_type'
      and t.typtype = 'e'
  ) into v_is_enum;

  if v_is_enum then
    raise notice 'movement_type is an enum, converting to text...';
    
    -- Get existing enum values for reference
    select array_agg(enumlabel::text order by enumsortorder)
    into v_enum_values
    from pg_type t
    join pg_enum e on t.oid = e.enumtypid
    join pg_attribute a on a.atttypid = t.oid
    join pg_class c on c.oid = a.attrelid
    where c.relname = 'stock_movements'
      and a.attname = 'movement_type'
      and t.typtype = 'e';
    
    raise notice 'Existing enum values: %', v_enum_values;
    
    -- Convert column to text
    alter table public.stock_movements 
      alter column movement_type type text using movement_type::text;
    
    raise notice 'Converted movement_type to text';
  else
    raise notice 'movement_type is already text or does not exist';
  end if;
  
  -- Ensure the column exists and is nullable
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'stock_movements'
      and column_name = 'movement_type'
  ) then
    alter table public.stock_movements add column movement_type text;
    raise notice 'Added movement_type column';
  end if;
  
  -- Make sure it's nullable
  alter table public.stock_movements alter column movement_type drop not null;
  
  raise notice 'Stock movements table is ready';
exception
  when others then
    raise notice 'Error fixing movement_type: %', SQLERRM;
    raise;
end $$;

-- Alternative: If you want to keep the enum but add 'sales_invoice' to it
-- Uncomment this block if you prefer to use enums:
/*
do $$
begin
  -- Add 'sales_invoice' to the enum if it doesn't exist
  if exists (
    select 1
    from pg_type t
    join pg_attribute a on a.atttypid = t.oid
    join pg_class c on c.oid = a.attrelid
    where c.relname = 'stock_movements'
      and a.attname = 'movement_type'
      and t.typtype = 'e'
  ) then
    -- Add new enum value if not exists
    if not exists (
      select 1
      from pg_enum e
      join pg_type t on t.oid = e.enumtypid
      join pg_attribute a on a.atttypid = t.oid
      join pg_class c on c.oid = a.attrelid
      where c.relname = 'stock_movements'
        and a.attname = 'movement_type'
        and e.enumlabel = 'sales_invoice'
    ) then
      alter type stock_movement_type add value 'sales_invoice';
      raise notice 'Added sales_invoice to enum';
    end if;
    
    -- Add other common values
    if not exists (
      select 1 from pg_enum e
      join pg_type t on t.oid = e.enumtypid
      where t.typname = 'stock_movement_type'
        and e.enumlabel = 'purchase_invoice'
    ) then
      alter type stock_movement_type add value 'purchase_invoice';
    end if;
    
    if not exists (
      select 1 from pg_enum e
      join pg_type t on t.oid = e.enumtypid
      where t.typname = 'stock_movement_type'
        and e.enumlabel = 'adjustment'
    ) then
      alter type stock_movement_type add value 'adjustment';
    end if;
  end if;
exception
  when others then
    raise notice 'Could not add enum values: %', SQLERRM;
end $$;
*/

-- Verify the fix
select 
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name = 'stock_movements'
  and c.column_name = 'movement_type';
