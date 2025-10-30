-- Fix employees table unique constraints to be tenant-scoped
-- Run this in Supabase SQL Editor

-- Step 1: Drop global unique constraints
alter table employees drop constraint if exists employees_employee_number_key;
alter table employees drop constraint if exists employees_email_key;
alter table employees drop constraint if exists employees_rut_key;

-- Step 2: Create tenant-scoped unique constraints
alter table employees add constraint employees_tenant_employee_number_key 
  unique (tenant_id, employee_number);

alter table employees add constraint employees_tenant_email_key 
  unique (tenant_id, email);

alter table employees add constraint employees_tenant_rut_key 
  unique (tenant_id, rut);

-- Step 3: Verify the changes
select 
  conname as constraint_name,
  pg_get_constraintdef(oid) as constraint_definition
from pg_constraint
where conrelid = 'employees'::regclass
  and contype = 'u'
order by conname;
