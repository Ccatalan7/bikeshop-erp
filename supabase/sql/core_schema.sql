-- Core data schema for Vinabike ERP.
-- Run this script in the Supabase SQL editor to provision base tables.
-- UUID columns default to gen_random_uuid(); ensure the extension is enabled first.

create extension if not exists "pgcrypto";

--------------------------------------------------------------------------------
-- ⚠️ CLEANUP: Remove old legacy task triggers/functions (Nov 18, 2025)
--------------------------------------------------------------------------------
-- CRITICAL: Drop ALL triggers on mechanic_job_items and mechanic_job_tasks
-- that reference old task functions (cascade will remove dependencies)
do $$
declare
  r record;
begin
  -- Drop ALL triggers on mechanic_job_tasks first (prevent any misattached triggers)
  for r in (
    select trigger_name 
    from information_schema.triggers 
    where event_object_table = 'mechanic_job_tasks'
  ) loop
    execute format('drop trigger if exists %I on mechanic_job_tasks cascade', r.trigger_name);
    raise notice 'Dropped task trigger: %', r.trigger_name;
  end loop;
  
  -- Drop ALL triggers on mechanic_job_items that might cause conflicts
  for r in (
    select trigger_name 
    from information_schema.triggers 
    where event_object_table = 'mechanic_job_items'
      and trigger_name like '%task%'
  ) loop
    execute format('drop trigger if exists %I on mechanic_job_items cascade', r.trigger_name);
    raise notice 'Dropped trigger: %', r.trigger_name;
  end loop;
  
  -- Drop ALL triggers on mechanic_jobs related to tasks
  for r in (
    select trigger_name 
    from information_schema.triggers 
    where event_object_table = 'mechanic_jobs'
      and trigger_name like '%task%'
  ) loop
    execute format('drop trigger if exists %I on mechanic_jobs cascade', r.trigger_name);
    raise notice 'Dropped trigger: %', r.trigger_name;
  end loop;
end $$;

-- Data fix: ensure every mechanic job has a unique job_number and align the sequence
do $$
declare
  v_job_id uuid;
  v_max_number integer;
begin
  -- Backfill missing/blank job numbers
  for v_job_id in
    select id
    from mechanic_jobs
    where job_number is null or btrim(job_number) = ''
  loop
    update mechanic_jobs
    set job_number = public.generate_mechanic_job_number()
    where id = v_job_id;
  end loop;

  -- Align the sequence with the highest PG-##### that currently exists
  select max((substring(job_number from '[0-9]+$'))::integer)
  into v_max_number
  from mechanic_jobs
  where job_number ~ '^PG-[0-9]+$';

  if v_max_number is null then
    v_max_number := 0;
  end if;

  perform setval('public.mechanic_job_number_seq', v_max_number);
end $$;

-- Drop old functions explicitly
drop function if exists public.auto_create_task_for_job_item() cascade;
drop function if exists public.auto_create_task_for_job_labor() cascade;
drop function if exists public.sync_tasks_with_job_status() cascade;
drop function if exists public.get_job_task_summary(uuid) cascade;

-- Drop old indexes
drop index if exists idx_mechanic_job_tasks_item cascade;
drop index if exists idx_mechanic_job_tasks_labor cascade;
drop index if exists idx_mechanic_job_tasks_status cascade;
drop index if exists idx_mechanic_job_tasks_assigned cascade;

-- Migrate old column names to new schema (safe - preserves data)
do $$
begin
  -- Rename title → task_name (if old column exists)
  if exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'title'
  ) and not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'task_name'
  ) then
    alter table mechanic_job_tasks rename column title to task_name;
    raise notice '✅ Renamed title → task_name';
  end if;

  -- Rename job_item_id → parent_item_id
  if exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'job_item_id'
  ) and not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'parent_item_id'
  ) then
    alter table mechanic_job_tasks rename column job_item_id to parent_item_id;
    raise notice '✅ Renamed job_item_id → parent_item_id';
  end if;

  -- Rename job_labor_id → parent_labor_id
  if exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'job_labor_id'
  ) and not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'parent_labor_id'
  ) then
    alter table mechanic_job_tasks rename column job_labor_id to parent_labor_id;
    raise notice '✅ Renamed job_labor_id → parent_labor_id';
  end if;

  -- Migrate status → is_completed (if old column exists)
  if exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'status'
  ) and not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'is_completed'
  ) then
    alter table mechanic_job_tasks add column is_completed boolean;
    update mechanic_job_tasks 
      set is_completed = (status = 'completed') 
      where is_completed is null;
    alter table mechanic_job_tasks alter column is_completed set not null;
    alter table mechanic_job_tasks alter column is_completed set default false;
    alter table mechanic_job_tasks drop column status cascade;
    raise notice '✅ Migrated status → is_completed';
  end if;

  -- Drop old columns that don't exist in new schema
  alter table mechanic_job_tasks drop column if exists task_type cascade;
  alter table mechanic_job_tasks drop column if exists priority cascade;
  alter table mechanic_job_tasks drop column if exists assigned_to cascade;
  alter table mechanic_job_tasks drop column if exists assigned_technician_name cascade;
  alter table mechanic_job_tasks drop column if exists estimated_duration_minutes cascade;
  alter table mechanic_job_tasks drop column if exists actual_duration_minutes cascade;
  alter table mechanic_job_tasks drop column if exists started_at cascade;
  alter table mechanic_job_tasks drop column if exists is_auto_generated cascade;
  alter table mechanic_job_tasks drop column if exists completed_by cascade;
  alter table mechanic_job_tasks drop column if exists completed_by_name cascade;
  alter table mechanic_job_tasks drop column if exists notes cascade;

  raise notice '✅ Legacy task schema cleanup complete';
exception
  when others then
    raise notice '⚠️ Migration note: %', sqlerrm;
end $$;
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- ⚙️ REQUIRED SUPABASE DASHBOARD CONFIGURATION (After deploying this schema)
--------------------------------------------------------------------------------
-- 
-- 1. PASSWORD RESET CONFIGURATION:
--    Navigate to: Authentication → URL Configuration in Supabase Dashboard
--    
--    Add these Redirect URLs:
--    - For Web (Production): https://your-domain.com/#/reset-password
--    - For Web (Localhost): http://localhost:8080/#/reset-password
--    - For Mobile (Deep Link): io.supabase.vinabikeerp://reset-password/
--    
--    These URLs allow users to reset their password via email link.
--    The Flutter app handles the /reset-password route automatically.
--
-- 2. SITE URL:
--    Set your production domain as the Site URL
--    Example: https://vinabike.cl or https://app.yourdomain.com
--
-- 3. EMAIL TEMPLATES (Optional - Customize in Dashboard):
--    Authentication → Email Templates → Reset Password
--    The default template works, but you can customize with your branding.
--
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- MULTI-TENANT ARCHITECTURE
--------------------------------------------------------------------------------
-- Tenants table: Each tenant represents a bike shop (e.g., Vinabike, Shop A, Shop B)
-- All data is isolated by tenant_id via Row Level Security (RLS)
--------------------------------------------------------------------------------

create table if not exists tenants (
  id uuid primary key default gen_random_uuid(),
  shop_name text not null,
  subdomain text unique, -- For multi-domain support (e.g., vinabike.bikeshop-erp.app)
  owner_email text,
  plan text default 'free' check (plan in ('free', 'pro', 'enterprise')),
  is_active boolean default true,
  logo_url text,
  custom_domain text, -- For custom domain support (e.g., www.vinabike.cl)
  currency text default 'CLP',
  timezone text default 'America/Santiago',
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add custom_domain column if it doesn't exist (for existing databases)
do $$ begin
  alter table tenants add column if not exists custom_domain text;
exception
  when duplicate_column then null;
end $$;

-- Add index on custom_domain for faster lookups
create index if not exists idx_tenants_custom_domain on tenants(custom_domain);

-- Set production custom domain for Vinabike tenant (shop id 5443b130-cc28-45af-a420-cd500b288890)
do $$
begin
  update tenants
    set custom_domain = 'vinabike.cl'
  where id = '5443b130-cc28-45af-a420-cd500b288890';
end $$;

-- Add constraint: subdomain must be URL-safe (lowercase alphanumeric and hyphens)
do $$ begin
  alter table tenants add constraint subdomain_format 
    check (subdomain ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$');
exception
  when duplicate_object then null;
end $$;

-- Reserved subdomains table: Prevent tenants from using system subdomains
create table if not exists reserved_subdomains (
  subdomain text primary key,
  reason text not null,
  created_at timestamp with time zone not null default now()
);

-- Populate reserved subdomains
insert into reserved_subdomains (subdomain, reason) values
  ('www', 'System reserved'),
  ('api', 'System reserved'),
  ('admin', 'System reserved'),
  ('app', 'System reserved'),
  ('mail', 'System reserved'),
  ('ftp', 'System reserved'),
  ('store', 'System reserved'),
  ('shop', 'System reserved'),
  ('dashboard', 'System reserved'),
  ('login', 'System reserved'),
  ('signup', 'System reserved'),
  ('auth', 'System reserved'),
  ('cdn', 'System reserved'),
  ('static', 'System reserved'),
  ('assets', 'System reserved')
on conflict (subdomain) do nothing;

-- User profiles: Link auth.users to tenants with roles
create table if not exists user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  tenant_id uuid references tenants(id) on delete cascade not null,
  role text not null check (role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant')),
  permissions jsonb not null default '{}'::jsonb,
  is_active boolean default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(user_id, tenant_id)
);

create index if not exists idx_user_profiles_user on user_profiles(user_id);
create index if not exists idx_user_profiles_tenant on user_profiles(tenant_id);

-- User activity log: Track user actions within each tenant
create table if not exists user_activity_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  action text not null, -- 'login', 'logout', 'role_changed', 'user_created', 'suspended', etc.
  details jsonb,
  performed_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone not null default now()
);

-- User invitations table: Track employee invitations
create table if not exists user_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  email text not null,
  role text not null check (role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant')),
  permissions jsonb not null,
  invited_by uuid references auth.users(id) not null,
  employee_id uuid references employees(id) on delete cascade,
  metadata jsonb,
  status text default 'pending' check (status in ('pending', 'accepted', 'expired')),
  expires_at timestamp with time zone not null,
  accepted_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

create index if not exists idx_invitations_email_status on user_invitations(email, status);
create index if not exists idx_user_invitations_employee_id on user_invitations(employee_id);

do $$ begin
  create index if not exists idx_invitations_tenant on user_invitations(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table user_invitations does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in user_invitations';
end $$;

-- Clean up any old policies first
do $$
begin
  drop policy if exists "users_view_own_invitations" on user_invitations;
  drop policy if exists "managers_create_invitations" on user_invitations;
  drop policy if exists "managers_view_tenant_invitations" on user_invitations;
exception
  when undefined_table then null;
  when undefined_object then null;
end $$;

-- Enable RLS on user_invitations
alter table user_invitations enable row level security;

-- Drop old policies
drop policy if exists "user_invitations_insert" on user_invitations;
drop policy if exists "user_invitations_select" on user_invitations;
drop policy if exists "user_invitations_update" on user_invitations;
drop policy if exists "user_invitations_delete" on user_invitations;
drop policy if exists "managers_create_invitations" on user_invitations;
drop policy if exists "managers_view_tenant_invitations" on user_invitations;
drop policy if exists "user_invitations_select_anonymous" on user_invitations;
drop policy if exists "user_invitations_update_anonymous" on user_invitations;

-- Allow authenticated users to create invitations in their tenant
create policy "user_invitations_insert" on user_invitations
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

-- Allow authenticated users to view invitations in their tenant
create policy "user_invitations_select" on user_invitations
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Allow anonymous users to view invitations by token (for accepting invitations)
create policy "user_invitations_select_anonymous" on user_invitations
  for select
  to anon
  using (status = 'pending');

-- Allow authenticated users to update invitations in their tenant
create policy "user_invitations_update" on user_invitations
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Allow anonymous users to update invitation status when accepting
create policy "user_invitations_update_anonymous" on user_invitations
  for update
  to anon
  using (status = 'pending');

-- Allow authenticated users to delete invitations in their tenant
create policy "user_invitations_delete" on user_invitations
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- CRITICAL: Nuclear cleanup for purchase_payments type caching issue
-- This MUST run first before any table or function definitions
do $$
begin
  -- Drop all triggers
  drop trigger if exists trg_purchase_payments_change on purchase_payments cascade;
  
  -- Drop all functions (all possible signatures)
  drop function if exists handle_purchase_payment_change() cascade;
  drop function if exists create_purchase_payment_journal_entry(uuid) cascade;
  drop function if exists create_purchase_payment_journal_entry(purchase_payments) cascade;
  drop function if exists delete_purchase_payment_journal_entry(uuid) cascade;
  
  -- Drop OLD trigger version of recalculate function (the one causing the error!)
  drop function if exists recalculate_purchase_invoice_payments() cascade;
  
  -- Drop old columns if they exist
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'purchase_payments' and column_name = 'payment_date'
  ) then
    alter table purchase_payments drop column payment_date cascade;
  end if;
  
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'purchase_payments' and column_name = 'bank_account_id'
  ) then
    alter table purchase_payments drop column bank_account_id cascade;
  end if;
  
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'purchase_payments' and column_name = 'purchase_invoice_id'
  ) then
    alter table purchase_payments drop column purchase_invoice_id cascade;
  end if;
  
  raise notice 'Nuclear cleanup complete for purchase_payments';
exception
  when others then
    raise notice 'Cleanup error (may be safe to ignore): %', sqlerrm;
end $$;

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  email text unique,
  auth_user_id uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone not null default now()
);

-- Migration: Add missing columns to customers table
do $$
begin
  -- Fix id column default if missing
  begin
    alter table customers alter column id set default gen_random_uuid();
  exception when others then
    raise notice 'Could not set default for customers.id: %', sqlerrm;
  end;

  -- Drop or make company_id nullable (not needed for customers table)
  if exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'company_id') then
    begin
      alter table customers drop column company_id cascade;
      raise notice 'Dropped company_id column from customers table';
    exception when others then
      -- If can't drop, make it nullable
      begin
        alter table customers alter column company_id drop not null;
        raise notice 'Made company_id nullable in customers table';
      exception when others then
        raise notice 'Could not modify company_id: %', sqlerrm;
      end;
    end;
  end if;

  -- Add rut column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'rut') then
    alter table customers add column rut text;
  end if;

  -- Add phone column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'phone') then
    alter table customers add column phone text;
  end if;

  -- Add address column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'address') then
    alter table customers add column address text;
  end if;

  -- Add region column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'region') then
    alter table customers add column region text;
  end if;

  -- Add tenant_id column for multi-tenant support
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'tenant_id') then
    alter table customers add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice 'Added tenant_id column to customers table';
  end if;

  -- Add is_active column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'is_active') then
    alter table customers add column is_active boolean not null default true;
  end if;

  -- Add image_url column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'image_url') then
    alter table customers add column image_url text;
  end if;

  -- Add updated_at column
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'updated_at') then
    alter table customers add column updated_at timestamp with time zone not null default now();
  end if;

  -- Add auth_user_id column for linking to Supabase Auth
  if not exists (select 1 from information_schema.columns where table_name = 'customers' and column_name = 'auth_user_id') then
    alter table customers add column auth_user_id uuid references auth.users(id) on delete set null;
    create index if not exists idx_customers_auth_user on customers(auth_user_id);
  end if;
end $$;

-- Customer addresses table for multiple shipping addresses
create table if not exists customer_addresses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  customer_id uuid not null references customers(id) on delete cascade,
  label text not null, -- e.g., "Home", "Work", "Mom's House"
  recipient_name text not null,
  phone text not null,
  street_address text not null,
  street_number text,
  apartment text, -- Depto, oficina, etc.
  comuna text not null, -- Comuna (e.g., "Las Condes", "Providencia")
  city text not null, -- Ciudad (e.g., "Santiago", "Valparaíso")
  region text not null, -- Región (e.g., "Región Metropolitana")
  postal_code text,
  additional_info text, -- Referencias adicionales
  is_default boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_customer_addresses_customer on customer_addresses(customer_id);
create index if not exists idx_customer_addresses_default on customer_addresses(customer_id, is_default) where is_default = true;

-- Trigger to ensure only one default address per customer
create or replace function ensure_single_default_address()
returns trigger as $$
begin
  if new.is_default then
    update customer_addresses
    set is_default = false
    where customer_id = new.customer_id
      and id != new.id
      and is_default = true;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists customer_address_default_trigger on customer_addresses;
create trigger customer_address_default_trigger
  before insert or update on customer_addresses
  for each row
  when (new.is_default = true)
  execute function ensure_single_default_address();

-- Enable RLS for customer_addresses table
alter table customer_addresses enable row level security;

-- Drop any existing policies
drop policy if exists "customer_addresses_select" on customer_addresses;
drop policy if exists "customer_addresses_insert" on customer_addresses;
drop policy if exists "customer_addresses_update" on customer_addresses;
drop policy if exists "customer_addresses_delete" on customer_addresses;
drop policy if exists "public_customer_addresses_select_own" on customer_addresses;
drop policy if exists "public_customer_addresses_insert_own" on customer_addresses;
drop policy if exists "public_customer_addresses_update_own" on customer_addresses;
drop policy if exists "public_customer_addresses_delete_own" on customer_addresses;

-- ERP POLICIES (for tenant users via user_tenant_id())
create policy "customer_addresses_select" on customer_addresses 
  for select 
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "customer_addresses_insert" on customer_addresses 
  for insert 
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "customer_addresses_update" on customer_addresses 
  for update 
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "customer_addresses_delete" on customer_addresses 
  for delete 
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- PUBLIC STORE POLICIES (for website customers via auth_user_id)
-- Website customers don't have user_profiles, so user_tenant_id() returns NULL
-- They can only access their OWN addresses linked to their customer record
create policy "public_customer_addresses_select_own" on customer_addresses 
  for select 
  to authenticated
  using (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  );

create policy "public_customer_addresses_insert_own" on customer_addresses 
  for insert 
  to authenticated
  with check (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
    AND tenant_id IS NOT NULL
  );

create policy "public_customer_addresses_update_own" on customer_addresses 
  for update 
  to authenticated
  using (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  );

create policy "public_customer_addresses_delete_own" on customer_addresses 
  for delete 
  to authenticated
  using (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  );

-- Loyalty table for customer loyalty program
create table if not exists loyalty (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  customer_id uuid not null references customers(id) on delete cascade unique,
  points integer not null default 0,
  tier text not null default 'bronze' check (tier in ('bronze', 'silver', 'gold', 'platinum')),
  last_updated timestamp with time zone not null default now(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_loyalty_tenant on loyalty(tenant_id);
create index if not exists idx_loyalty_customer on loyalty(customer_id);
create index if not exists idx_loyalty_tier on loyalty(tier);

-- Enable RLS for loyalty table
alter table loyalty enable row level security;

drop policy if exists "loyalty_select" on loyalty;
drop policy if exists "loyalty_insert" on loyalty;
drop policy if exists "loyalty_update" on loyalty;
drop policy if exists "loyalty_delete" on loyalty;

create policy "loyalty_select" on loyalty
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "loyalty_insert" on loyalty
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "loyalty_update" on loyalty
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "loyalty_delete" on loyalty
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Company settings table for global app configuration
create table if not exists company_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  key text not null,
  value text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, key) -- Each tenant has their own settings
);

do $$ begin
  create index if not exists idx_company_settings_tenant on company_settings(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table company_settings does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in company_settings';
end $$;

-- Migration: Drop old single-tenant constraint, ensure multi-tenant constraint exists
do $$ 
begin
  -- Drop old global unique constraint on 'key' alone (wrong for multi-tenant)
  if exists (
    select 1 from pg_constraint 
    where conname = 'company_settings_key_key'
  ) then
    alter table company_settings drop constraint company_settings_key_key;
    raise notice '✓ Dropped old global unique constraint on key';
  end if;
  
  -- Ensure correct per-tenant unique constraint exists
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'company_settings'
    and c.contype = 'u'
    and array_length(c.conkey, 1) = 2  -- Composite constraint (tenant_id, key)
  ) then
    alter table company_settings add constraint company_settings_tenant_key_unique unique (tenant_id, key);
    raise notice '✓ Created per-tenant unique constraint (tenant_id, key)';
  else
    raise notice '✓ Per-tenant unique constraint already exists';
  end if;
exception
  when others then
    raise notice '⚠ Constraint migration: %', SQLERRM;
end $$;

-- Note: Default settings will be seeded via trigger when tenant is created

--------------------------------------------------------------------------------
-- BACKUP & RESTORE SYSTEM
--------------------------------------------------------------------------------
-- Stores metadata about database backups for disaster recovery and data rollback
-- Each backup captures a snapshot of all tenant data with summary statistics
--------------------------------------------------------------------------------

create table if not exists database_backups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  backup_name text not null, -- e.g., "Before Year-End Closing", "Auto Backup"
  backup_type text not null check (backup_type in ('manual', 'automatic', 'scheduled')),
  status text not null default 'in_progress' check (status in ('in_progress', 'completed', 'failed', 'restored')),
  
  -- Backup metadata
  backup_data jsonb not null, -- Stores the actual data snapshot
  
  -- Summary statistics (for preview before restore)
  summary jsonb, -- { "products": 1440, "customers": 350, "invoices": 1200, ... }
  
  -- Metadata
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  restored_at timestamp with time zone, -- When this backup was restored
  restored_by uuid references auth.users(id), -- Who restored it
  
  -- Size tracking
  backup_size_bytes bigint, -- Size of backup data in bytes
  
  -- Notes
  notes text, -- User-provided description
  
  -- Error tracking
  error_message text -- If backup failed
);

create index if not exists idx_database_backups_tenant on database_backups(tenant_id);
create index if not exists idx_database_backups_created_at on database_backups(created_at desc);
create index if not exists idx_database_backups_type on database_backups(backup_type);
create index if not exists idx_database_backups_status on database_backups(status);

-- RLS policies for backups
alter table database_backups enable row level security;

drop policy if exists "backups_select" on database_backups;
drop policy if exists "backups_insert" on database_backups;
drop policy if exists "backups_update" on database_backups;
drop policy if exists "backups_delete" on database_backups;

create policy "backups_select" on database_backups
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "backups_insert" on database_backups
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "backups_update" on database_backups
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "backups_delete" on database_backups
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Backup schedule configuration (per tenant)
create table if not exists backup_schedules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null unique,
  
  -- Schedule settings
  enabled boolean not null default false,
  frequency text not null default 'daily' check (frequency in ('hourly', 'daily', 'weekly', 'monthly')),
  time_of_day time, -- When to run daily/weekly backups (e.g., 02:00:00)
  day_of_week int, -- 0-6 for weekly backups (0 = Sunday)
  day_of_month int, -- 1-31 for monthly backups
  
  -- Retention policy
  keep_last_n_backups int not null default 7, -- Keep last 7 backups
  auto_delete_old boolean not null default true,
  
  -- Last run tracking
  last_run_at timestamp with time zone,
  next_run_at timestamp with time zone,
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_backup_schedules_tenant on backup_schedules(tenant_id);
create index if not exists idx_backup_schedules_next_run on backup_schedules(next_run_at) where enabled = true;

-- RLS policies for backup schedules
alter table backup_schedules enable row level security;

drop policy if exists "backup_schedules_select" on backup_schedules;
drop policy if exists "backup_schedules_insert" on backup_schedules;
drop policy if exists "backup_schedules_update" on backup_schedules;
drop policy if exists "backup_schedules_delete" on backup_schedules;

create policy "backup_schedules_select" on backup_schedules
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "backup_schedules_insert" on backup_schedules
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "backup_schedules_update" on backup_schedules
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "backup_schedules_delete" on backup_schedules
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

--------------------------------------------------------------------------------

create table if not exists product_brands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  description text,
  website text,
  country text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name) -- Each tenant can have their own brands
);

do $$ begin
  create index if not exists idx_product_brands_tenant on product_brands(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table product_brands does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in product_brands';
end $$;

create index if not exists idx_product_brands_name on product_brands (lower(name));
create index if not exists idx_product_brands_is_active on product_brands (is_active);

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'product_brands'
     and t.tgname = 'trg_product_brands_updated_at'
  ) then
    create trigger trg_product_brands_updated_at
      before update on product_brands
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- ============================================================================
-- BIKE BRANDS & MODELS - For Taller/Workshop Module
-- ============================================================================
create table if not exists bike_brands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  logo_url text,
  country text,
  website text,
  description text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name) -- Each tenant can have their own bike brands
);

create index if not exists idx_bike_brands_tenant on bike_brands(tenant_id);
create index if not exists idx_bike_brands_name on bike_brands(lower(name));
create index if not exists idx_bike_brands_is_active on bike_brands(is_active);

-- Enable RLS for bike_brands
alter table bike_brands enable row level security;

drop policy if exists "bike_brands_select" on bike_brands;
drop policy if exists "bike_brands_insert" on bike_brands;
drop policy if exists "bike_brands_update" on bike_brands;
drop policy if exists "bike_brands_delete" on bike_brands;

create policy "bike_brands_select" on bike_brands
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_brands_insert" on bike_brands
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_brands_update" on bike_brands
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_brands_delete" on bike_brands
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger for updated_at
do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'bike_brands'
     and t.tgname = 'trg_bike_brands_updated_at'
  ) then
    create trigger trg_bike_brands_updated_at
      before update on bike_brands
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create table if not exists bike_models (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  brand_id uuid not null references bike_brands(id) on delete cascade,
  name text not null,
  year integer,
  description text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, brand_id, name) -- Each brand can have one model with same name
);

create index if not exists idx_bike_models_tenant on bike_models(tenant_id);
create index if not exists idx_bike_models_brand on bike_models(brand_id);
create index if not exists idx_bike_models_name on bike_models(lower(name));
create index if not exists idx_bike_models_is_active on bike_models(is_active);

-- Enable RLS for bike_models
alter table bike_models enable row level security;

drop policy if exists "bike_models_select" on bike_models;
drop policy if exists "bike_models_insert" on bike_models;
drop policy if exists "bike_models_update" on bike_models;
drop policy if exists "bike_models_delete" on bike_models;

create policy "bike_models_select" on bike_models
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_models_insert" on bike_models
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_models_update" on bike_models
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_models_delete" on bike_models
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger for updated_at
do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'bike_models'
     and t.tgname = 'trg_bike_models_updated_at'
  ) then
    create trigger trg_bike_models_updated_at
      before update on bike_models
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- ============================================================================
-- BIKE CATALOG (ENCYCLOPEDIA) - Global Reference Database
-- ============================================================================
-- Purpose: Store comprehensive bike specifications from external APIs
-- (BikeBook.io, Bike Index) for reference and compatibility matching.
-- This is a GLOBAL table (no tenant_id) - shared across all shops.

create table if not exists bike_catalog (
  id uuid primary key default gen_random_uuid(),
  
  -- Identity
  brand text not null,
  model_name text not null,
  model_year integer not null,
  bike_type text, -- road, mountain, hybrid, gravel, bmx, city
  
  -- Frame & Geometry
  frame_material text, -- aluminum, carbon, steel, titanium
  frame_size_range text[], -- ['S', 'M', 'L'] or ['48cm', '52cm']
  wheel_size text, -- 700c, 29", 27.5", 26", 650b, 20"
  
  -- Drivetrain
  drivetrain_speeds integer, -- 8, 9, 10, 11, 12
  drivetrain_config text, -- '1x11', '2x10', '3x8'
  cassette_range text, -- '11-42', '11-50'
  cassette_max_teeth integer,
  chain_speeds integer,
  crankset_model text,
  rear_derailleur_model text,
  front_derailleur_model text,
  
  -- Braking
  brake_type text, -- rim, mechanical_disc, hydraulic_disc
  brake_model text,
  brake_rotor_size_front_mm integer,
  brake_rotor_size_rear_mm integer,
  
  -- Wheels & Hubs
  front_hub_model text,
  rear_hub_model text,
  front_hub_spacing_mm numeric(5,1), -- 100, 110
  rear_hub_spacing_mm numeric(5,1), -- 130, 135, 142, 148
  front_axle_type text, -- QR, thru_15mm, thru_20mm
  rear_axle_type text, -- QR, thru_12mm
  freehub_type text, -- shimano_hg, sram_xd, microspline
  spoke_count integer, -- 24, 28, 32, 36
  
  -- Tires
  tire_size_front text, -- '700x25c', '29x2.2'
  tire_size_rear text,
  max_tire_width_mm numeric(5,1),
  
  -- Cockpit
  handlebar_type text, -- drop, flat, riser
  stem_length_mm integer,
  seatpost_diameter_mm numeric(4,1), -- 27.2, 30.9, 31.6
  
  -- Additional Info
  weight_kg numeric(5,2),
  msrp_usd numeric(10,2),
  manufacturer_url text,
  image_url text,
  
  -- Full specs storage (raw JSON from API)
  full_specs_json jsonb,
  
  -- Data Quality
  data_source text not null, -- 'bikebook', 'bike_index', 'manual'
  data_confidence numeric(3,2) default 0.5, -- 0.0 to 1.0
  external_id text, -- ID from source API
  last_verified_at timestamp with time zone,
  
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  
  unique(brand, model_name, model_year)
);

-- Indexes for fast lookup
create index if not exists idx_bike_catalog_brand on bike_catalog(lower(brand));
create index if not exists idx_bike_catalog_model on bike_catalog(lower(model_name));
create index if not exists idx_bike_catalog_year on bike_catalog(model_year);
create index if not exists idx_bike_catalog_search on bike_catalog(lower(brand), model_year, lower(model_name));
create index if not exists idx_bike_catalog_type on bike_catalog(bike_type) where bike_type is not null;
create index if not exists idx_bike_catalog_source on bike_catalog(data_source);
create index if not exists idx_bike_catalog_specs on bike_catalog using gin(full_specs_json);

-- Full-text search
create index if not exists idx_bike_catalog_model_fts on bike_catalog using gin(to_tsvector('english', model_name));

-- No RLS needed - this is a global reference table accessible to all authenticated users
alter table bike_catalog enable row level security;

drop policy if exists "bike_catalog_select_all" on bike_catalog;
drop policy if exists "bike_catalog_insert_admin" on bike_catalog;
drop policy if exists "bike_catalog_update_admin" on bike_catalog;

create policy "bike_catalog_select_all" on bike_catalog
  for select to authenticated
  using (true); -- Anyone authenticated can read

create policy "bike_catalog_insert_admin" on bike_catalog
  for insert to authenticated
  with check (true); -- For now, any authenticated user can add bikes (later restrict to admin role)

create policy "bike_catalog_update_admin" on bike_catalog
  for update to authenticated
  using (true);

-- Trigger for updated_at
do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'bike_catalog'
     and t.tgname = 'trg_bike_catalog_updated_at'
  ) then
    create trigger trg_bike_catalog_updated_at
      before update on bike_catalog
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- ============================================================================
-- WHEEL BUILDING SYSTEM - Professional Spoke Calculator & Parts Compatibility
-- ============================================================================
-- This system enables mechanics to:
-- 1. Calculate exact spoke lengths (implements prowheelbuilder.com algorithm)
-- 2. Find compatible hubs, rims, spokes for wheel rebuilds
-- 3. Store wheel build specifications for future reference
-- 4. Generate parts lists automatically

-- Table: wheel_hubs
-- Technical specifications for bicycle hubs
create table if not exists wheel_hubs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  
  -- Basic Info
  name text not null,
  manufacturer text,
  model text,
  hub_type text check (hub_type in ('front', 'rear')) not null,
  
  -- Critical Measurements (in mm)
  old_mm numeric(5,1) not null, -- Over Locknut Dimension (130, 135, 142, 148, etc.)
  spoke_holes integer not null check (spoke_holes in (24, 28, 32, 36, 40)),
  
  -- Flange Measurements (for spoke length calculation)
  left_flange_diameter_mm numeric(5,2) not null,
  right_flange_diameter_mm numeric(5,2) not null,
  center_to_left_flange_mm numeric(5,2) not null,
  center_to_right_flange_mm numeric(5,2) not null,
  
  -- Compatibility
  brake_type text check (brake_type in ('rim', 'disc_6bolt', 'disc_centerlock')) not null,
  driver_type text check (driver_type in ('freewheel', 'cassette', 'fixed', 'none')) not null,
  axle_type text check (axle_type in ('quick_release', 'thru_axle_12mm', 'thru_axle_15mm', 'thru_axle_20mm', 'bolt_on')) not null,
  
  -- Additional Specs
  weight_grams integer,
  material text, -- 'aluminum', 'steel', 'carbon'
  bearing_type text, -- 'loose_ball', 'sealed_cartridge'
  
  -- Metadata
  notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_hubs_tenant on wheel_hubs(tenant_id);
create index if not exists idx_wheel_hubs_product on wheel_hubs(product_id);
create index if not exists idx_wheel_hubs_old on wheel_hubs(old_mm);
create index if not exists idx_wheel_hubs_spoke_holes on wheel_hubs(spoke_holes);
create index if not exists idx_wheel_hubs_hub_type on wheel_hubs(hub_type);

alter table wheel_hubs enable row level security;

drop policy if exists "wheel_hubs_select" on wheel_hubs;
drop policy if exists "wheel_hubs_insert" on wheel_hubs;
drop policy if exists "wheel_hubs_update" on wheel_hubs;
drop policy if exists "wheel_hubs_delete" on wheel_hubs;

create policy "wheel_hubs_select" on wheel_hubs for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_hubs_insert" on wheel_hubs for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "wheel_hubs_update" on wheel_hubs for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_hubs_delete" on wheel_hubs for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Table: wheel_rims
-- Technical specifications for bicycle rims
create table if not exists wheel_rims (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  
  -- Basic Info
  name text not null,
  manufacturer text,
  model text,
  
  -- Critical Measurements (in mm)
  erd_mm numeric(5,2) not null, -- Effective Rim Diameter (critical for spoke calc)
  spoke_holes integer not null check (spoke_holes in (24, 28, 32, 36, 40)),
  internal_width_mm numeric(4,1) not null,
  external_width_mm numeric(4,1),
  rim_depth_mm numeric(4,1),
  
  -- Specifications
  wheel_size text not null, -- '26"', '27.5"', '29"', '700c', '650b'
  brake_type text check (brake_type in ('rim', 'disc')) not null,
  rim_type text check (rim_type in ('clincher', 'tubular', 'tubeless_ready', 'hookless')) not null,
  material text, -- 'aluminum', 'carbon', 'steel'
  
  -- Technical Details
  max_pressure_psi integer,
  weight_grams integer,
  spoke_hole_drilling text, -- 'straight_pull', 'j_bend'
  
  -- Metadata
  notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_rims_tenant on wheel_rims(tenant_id);
create index if not exists idx_wheel_rims_product on wheel_rims(product_id);
create index if not exists idx_wheel_rims_erd on wheel_rims(erd_mm);
create index if not exists idx_wheel_rims_spoke_holes on wheel_rims(spoke_holes);
create index if not exists idx_wheel_rims_wheel_size on wheel_rims(wheel_size);

alter table wheel_rims enable row level security;

drop policy if exists "wheel_rims_select" on wheel_rims;
drop policy if exists "wheel_rims_insert" on wheel_rims;
drop policy if exists "wheel_rims_update" on wheel_rims;
drop policy if exists "wheel_rims_delete" on wheel_rims;

create policy "wheel_rims_select" on wheel_rims for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_rims_insert" on wheel_rims for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "wheel_rims_update" on wheel_rims for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_rims_delete" on wheel_rims for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Table: wheel_spokes
-- Technical specifications for bicycle spokes
create table if not exists wheel_spokes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  
  -- Basic Info
  name text not null,
  manufacturer text,
  model text,
  
  -- Critical Specs
  length_mm integer not null, -- Spoke length (290, 292, 294, etc.)
  gauge numeric(3,2) not null, -- Wire thickness (2.0, 1.8, 2.0-1.8 for butted)
  is_butted boolean not null default false,
  
  -- Specifications
  material text not null default 'stainless_steel', -- 'stainless_steel', 'brass', 'titanium'
  finish text, -- 'silver', 'black', 'brass'
  head_type text check (head_type in ('j_bend', 'straight_pull')) not null default 'j_bend',
  thread_type text, -- 'standard', 'lock'
  
  -- Technical Details
  tensile_strength_n integer, -- Newtons
  weight_grams numeric(4,2),
  
  -- Metadata
  notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_spokes_tenant on wheel_spokes(tenant_id);
create index if not exists idx_wheel_spokes_product on wheel_spokes(product_id);
create index if not exists idx_wheel_spokes_length on wheel_spokes(length_mm);
create index if not exists idx_wheel_spokes_gauge on wheel_spokes(gauge);

alter table wheel_spokes enable row level security;

drop policy if exists "wheel_spokes_select" on wheel_spokes;
drop policy if exists "wheel_spokes_insert" on wheel_spokes;
drop policy if exists "wheel_spokes_update" on wheel_spokes;
drop policy if exists "wheel_spokes_delete" on wheel_spokes;

create policy "wheel_spokes_select" on wheel_spokes for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_spokes_insert" on wheel_spokes for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "wheel_spokes_update" on wheel_spokes for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_spokes_delete" on wheel_spokes for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Table: wheel_builds
-- Saved wheel build specifications and calculations
create table if not exists wheel_builds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  
  -- References
  bike_id uuid references bikes(id) on delete set null,
  mechanic_job_id uuid references mechanic_jobs(id) on delete set null,
  
  -- Build Info
  build_name text not null,
  wheel_position text check (wheel_position in ('front', 'rear')) not null,
  build_date date default current_date,
  
  -- Components
  hub_id uuid references wheel_hubs(id) on delete set null,
  rim_id uuid references wheel_rims(id) on delete set null,
  spoke_id uuid references wheel_spokes(id) on delete set null,
  
  -- Build Specifications
  spoke_count integer not null,
  lacing_pattern text not null, -- 'radial', '1-cross', '2-cross', '3-cross', '4-cross'
  
  -- Calculated Spoke Lengths (in mm)
  left_spoke_length_mm numeric(5,2),
  right_spoke_length_mm numeric(5,2),
  
  -- Actual Spoke Products Used (for inventory)
  left_spoke_product_id uuid references products(id) on delete set null,
  right_spoke_product_id uuid references products(id) on delete set null,
  
  -- Additional Components
  nipple_type text, -- 'brass', 'aluminum', 'brass_lock'
  rim_tape_width_mm integer,
  
  -- Metadata
  notes text,
  mechanic_notes text,
  is_template boolean not null default false, -- Reusable templates
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_builds_tenant on wheel_builds(tenant_id);
create index if not exists idx_wheel_builds_bike on wheel_builds(bike_id);
create index if not exists idx_wheel_builds_job on wheel_builds(mechanic_job_id);
create index if not exists idx_wheel_builds_hub on wheel_builds(hub_id);
create index if not exists idx_wheel_builds_rim on wheel_builds(rim_id);

alter table wheel_builds enable row level security;

drop policy if exists "wheel_builds_select" on wheel_builds;
drop policy if exists "wheel_builds_insert" on wheel_builds;
drop policy if exists "wheel_builds_update" on wheel_builds;
drop policy if exists "wheel_builds_delete" on wheel_builds;

create policy "wheel_builds_select" on wheel_builds for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_builds_insert" on wheel_builds for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "wheel_builds_update" on wheel_builds for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "wheel_builds_delete" on wheel_builds for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================================
-- SPOKE LENGTH CALCULATOR - Implements ProWheelBuilder Algorithm
-- ============================================================================
-- Formula: Spoke Length = √(R² + H² + D² - 2*R*H*cos(α))
-- Where:
--   R = Effective Rim Radius (ERD/2)
--   H = Flange Radius (Flange Diameter/2)
--   D = Distance from wheel center to flange
--   α = Spoke angle based on lacing pattern and spoke holes

create or replace function public.calculate_spoke_length(
  p_erd_mm numeric,                      -- Rim ERD
  p_flange_diameter_mm numeric,          -- Hub flange diameter
  p_center_to_flange_mm numeric,         -- Hub center to flange distance
  p_spoke_holes integer,                 -- Number of spoke holes (24, 28, 32, 36)
  p_cross_pattern integer default 3      -- Lacing pattern (0=radial, 1-4=cross)
) returns numeric
language plpgsql
as $$
declare
  v_rim_radius numeric;
  v_flange_radius numeric;
  v_spoke_angle_rad numeric;
  v_spoke_length numeric;
  v_pi numeric := 3.14159265359;
begin
  -- Input validation
  if p_erd_mm is null or p_erd_mm <= 0 then
    raise exception 'Invalid ERD: %', p_erd_mm;
  end if;
  
  if p_spoke_holes not in (24, 28, 32, 36, 40) then
    raise exception 'Invalid spoke hole count: %. Must be 24, 28, 32, 36, or 40', p_spoke_holes;
  end if;
  
  if p_cross_pattern < 0 or p_cross_pattern > 4 then
    raise exception 'Invalid cross pattern: %. Must be 0-4', p_cross_pattern;
  end if;
  
  -- Calculate radii
  v_rim_radius := p_erd_mm / 2.0;
  v_flange_radius := p_flange_diameter_mm / 2.0;
  
  -- Calculate spoke angle based on lacing pattern
  -- Radial (0-cross): angle = 0
  -- Cross patterns: angle depends on number of crossings
  if p_cross_pattern = 0 then
    v_spoke_angle_rad := 0;
  else
    -- Angle between spoke holes in radians
    v_spoke_angle_rad := (2 * v_pi * p_cross_pattern) / p_spoke_holes;
  end if;
  
  -- ProWheelBuilder Formula:
  -- L = √(R² + H² + D² - 2*R*H*cos(α))
  v_spoke_length := sqrt(
    power(v_rim_radius, 2) +
    power(v_flange_radius, 2) +
    power(p_center_to_flange_mm, 2) -
    (2 * v_rim_radius * v_flange_radius * cos(v_spoke_angle_rad))
  );
  
  -- Return length rounded to 0.1mm precision
  return round(v_spoke_length, 1);
end;
$$;

-- Function: Find compatible hubs for a given rim and bike OLD
create or replace function public.find_compatible_hubs(
  p_tenant_id uuid,
  p_rim_id uuid,
  p_bike_old_mm numeric default null,
  p_hub_type text default 'rear'
) returns table (
  hub_id uuid,
  hub_name text,
  manufacturer text,
  old_mm numeric,
  spoke_holes integer,
  compatibility_score integer,
  notes text
)
language plpgsql
as $$
declare
  v_rim_spoke_holes integer;
  v_rim_brake_type text;
begin
  -- Get rim specs
  select r.spoke_holes, r.brake_type
  into v_rim_spoke_holes, v_rim_brake_type
  from wheel_rims r
  where r.id = p_rim_id and r.tenant_id = p_tenant_id;
  
  if not found then
    raise exception 'Rim not found: %', p_rim_id;
  end if;
  
  -- Find matching hubs
  return query
  select
    h.id as hub_id,
    h.name as hub_name,
    h.manufacturer,
    h.old_mm,
    h.spoke_holes,
    -- Compatibility scoring
    case
      when h.spoke_holes = v_rim_spoke_holes then 100 -- Perfect match
      when h.brake_type = v_rim_brake_type then 80    -- Brake match
      when p_bike_old_mm is not null and h.old_mm = p_bike_old_mm then 90 -- OLD match
      else 50 -- Partial match
    end as compatibility_score,
    case
      when h.spoke_holes <> v_rim_spoke_holes then '⚠️ Spoke hole mismatch'
      when h.brake_type <> v_rim_brake_type then '⚠️ Brake type mismatch'
      else '✅ Compatible'
    end as notes
  from wheel_hubs h
  where h.tenant_id = p_tenant_id
    and h.is_active = true
    and h.hub_type = p_hub_type
    and h.spoke_holes = v_rim_spoke_holes -- Strict: spoke holes must match
  order by compatibility_score desc, h.name;
end;
$$;

-- Function: Find compatible spokes for a wheel build
create or replace function public.find_compatible_spokes(
  p_tenant_id uuid,
  p_required_length_mm numeric,
  p_tolerance_mm numeric default 2.0 -- ±2mm tolerance
) returns table (
  spoke_id uuid,
  spoke_name text,
  length_mm integer,
  gauge numeric,
  manufacturer text,
  stock_quantity integer,
  length_difference_mm numeric
)
language plpgsql
as $$
begin
  return query
  select
    ws.id as spoke_id,
    ws.name as spoke_name,
    ws.length_mm,
    ws.gauge,
    ws.manufacturer,
    coalesce(p.inventory_qty, 0) as stock_quantity,
    abs(ws.length_mm - p_required_length_mm) as length_difference_mm
  from wheel_spokes ws
  left join products p on p.id = ws.product_id
  where ws.tenant_id = p_tenant_id
    and ws.is_active = true
    and ws.length_mm between (p_required_length_mm - p_tolerance_mm) and (p_required_length_mm + p_tolerance_mm)
  order by length_difference_mm, stock_quantity desc, ws.manufacturer;
end;
$$;

-- Triggers for updated_at
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_wheel_hubs_updated_at') then
    create trigger trg_wheel_hubs_updated_at before update on wheel_hubs
      for each row execute procedure public.set_updated_at();
  end if;
  
  if not exists (select 1 from pg_trigger where tgname = 'trg_wheel_rims_updated_at') then
    create trigger trg_wheel_rims_updated_at before update on wheel_rims
      for each row execute procedure public.set_updated_at();
  end if;
  
  if not exists (select 1 from pg_trigger where tgname = 'trg_wheel_spokes_updated_at') then
    create trigger trg_wheel_spokes_updated_at before update on wheel_spokes
      for each row execute procedure public.set_updated_at();
  end if;
  
  if not exists (select 1 from pg_trigger where tgname = 'trg_wheel_builds_updated_at') then
    create trigger trg_wheel_builds_updated_at before update on wheel_builds
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  sku text unique,
  price numeric(12,2) not null default 0,
  cost numeric(12,2) not null default 0,
  brand_id uuid references public.product_brands(id) on delete set null,
  inventory_qty integer not null default 0,
  created_at timestamp with time zone not null default now()
);

-- Migration: Add missing columns to products table
do $$
begin
  -- Add barcode if not exists
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'barcode') then
    alter table products add column barcode text;
  end if;

  -- Add stock_quantity (alias for inventory_qty)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'stock_quantity') then
    alter table products add column stock_quantity integer not null default 0;
  end if;

  -- Add min_stock_level
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'min_stock_level') then
    alter table products add column min_stock_level integer not null default 5;
  end if;

  -- Add max_stock_level
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'max_stock_level') then
    alter table products add column max_stock_level integer not null default 100;
  end if;

  -- Add image_url
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'image_url') then
    alter table products add column image_url text;
  end if;

  -- Add image_urls array
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'image_urls') then
    alter table products add column image_urls text[] not null default array[]::text[];
  end if;

  -- Add description
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'description') then
    alter table products add column description text;
  end if;

  -- Add category (enum/text)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'category') then
    alter table products add column category text not null default 'other';
  end if;

  -- Add category_id (FK to categories table)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'category_id') then
    alter table products add column category_id uuid;
  end if;

  -- Add category_name (resolved name)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'category_name') then
    alter table products add column category_name text;
  end if;

  -- Add brand reference
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'brand_id') then
    alter table products add column brand_id uuid references public.product_brands(id) on delete set null;
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.products'::regclass
       and conname = 'products_brand_id_fkey'
  ) then
    alter table products
      add constraint products_brand_id_fkey
        foreign key (brand_id) references public.product_brands(id) on delete set null;
  end if;

  -- Add brand
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'brand') then
    alter table products add column brand text;
  end if;

  -- Add model
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'model') then
    alter table products add column model text;
  end if;

  -- Add specifications (jsonb)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'specifications') then
    alter table products add column specifications jsonb not null default '{}'::jsonb;
  end if;

  -- Add supplier relationship
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'supplier_id') then
    alter table products add column supplier_id uuid references public.suppliers(id) on delete set null;
  end if;

  -- Add supplier reference codes
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'supplier_reference') then
    alter table products add column supplier_reference text;
  end if;

  -- Add supplier code (Código Proveedor for this specific supplier)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'supplier_code') then
    alter table products add column supplier_code text;
  end if;

  -- Add manufacturer metadata
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'manufacturer') then
    alter table products add column manufacturer text;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'manufacturer_sku') then
    alter table products add column manufacturer_sku text;
  end if;

  -- Add international product identifiers
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'gtin') then
    alter table products add column gtin text;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'hs_code') then
    alter table products add column hs_code text;
  end if;

  -- Add origin and variant attributes
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'country_of_origin') then
    alter table products add column country_of_origin text;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'color') then
    alter table products add column color text;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'size') then
    alter table products add column size text;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'material') then
    alter table products add column material text;
  end if;

  -- Add dimensional data
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'dimensions') then
    alter table products add column dimensions jsonb not null default '{}'::jsonb;
  end if;

  -- Add warranty and lifecycle controls
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'warranty_months') then
    alter table products add column warranty_months integer not null default 0;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'lifecycle_status') then
    alter table products add column lifecycle_status text not null default 'active';
  end if;

  -- Add tracking flags
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'serialized') then
    alter table products add column serialized boolean not null default false;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'lot_tracking') then
    alter table products add column lot_tracking boolean not null default false;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'expiration_tracking') then
    alter table products add column expiration_tracking boolean not null default false;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'expiry_days') then
    alter table products add column expiry_days integer;
  end if;

  -- Add planning attributes
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'lead_time_days') then
    alter table products add column lead_time_days integer not null default 0;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'reorder_quantity') then
    alter table products add column reorder_quantity integer not null default 0;
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'warehouse_location') then
    alter table products add column warehouse_location text;
  end if;

  -- Add pricing metadata
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'price_currency') then
    alter table products add column price_currency text not null default 'CLP';
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'cost_currency') then
    alter table products add column cost_currency text not null default 'CLP';
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'tax_rate') then
    alter table products add column tax_rate numeric(5,2);
  end if;

  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'is_published') then
    alter table products add column is_published boolean not null default true;
  end if;

  -- Add is_google_merchant (requires is_published to be true)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'is_google_merchant') then
    alter table products add column is_google_merchant boolean not null default false;
  end if;

  -- Add tags array
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'tags') then
    alter table products add column tags text[] not null default array[]::text[];
  end if;

  -- Add unit
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'unit') then
    alter table products add column unit text not null default 'unit';
  end if;

  -- Add weight
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'weight') then
    alter table products add column weight numeric(10,2) not null default 0;
  end if;

  -- Add track_stock
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'track_stock') then
    alter table products add column track_stock boolean not null default true;
  end if;

  -- Add is_active
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'is_active') then
    alter table products add column is_active boolean not null default true;
  end if;

  -- Add product_type (product or service)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'product_type') then
    alter table products add column product_type text not null default 'product';
  end if;

  -- Add is_service (computed from product_type, for inventory triggers)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'is_service') then
    alter table products add column is_service boolean not null default false;
  end if;

  -- Sync is_service with product_type for existing records
  update products set is_service = (product_type = 'service') where is_service != (product_type = 'service');

  -- Add updated_at
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'updated_at') then
    alter table products add column updated_at timestamp with time zone not null default now();
  end if;

  -- Normalize existing brands into product_brands table and backfill brand_id
  with normalized_brands as (
    select lower(btrim(brand)) as normalized_name,
           min(btrim(brand)) as canonical_name
      from products
     where brand is not null
       and btrim(brand) <> ''
     group by lower(btrim(brand))
  )
  insert into product_brands (name, created_at, updated_at)
  select canonical_name, now(), now()
    from normalized_brands nb
   where not exists (
     select 1
       from product_brands pb
      where lower(pb.name) = nb.normalized_name
   );

  update products p
     set brand_id = pb.id
    from product_brands pb
   where p.brand_id is null
     and p.brand is not null
     and btrim(p.brand) <> ''
     and lower(pb.name) = lower(btrim(p.brand));

  update products p
     set brand = pb.name
    from product_brands pb
   where p.brand_id = pb.id
     and (p.brand is distinct from pb.name);

  -- Sync inventory_qty to stock_quantity for existing records
  update products set stock_quantity = inventory_qty where stock_quantity = 0 and inventory_qty > 0;

  -- Services must never track stock (backfill existing rows)
  update products
     set is_service = true,
         track_stock = false,
         inventory_qty = 0,
         stock_quantity = 0,
         min_stock_level = 0,
         max_stock_level = 0
   where product_type = 'service'
     and (
       is_service is distinct from true
       or track_stock is distinct from false
       or coalesce(inventory_qty, 0) <> 0
       or coalesce(stock_quantity, 0) <> 0
       or coalesce(min_stock_level, 0) <> 0
       or coalesce(max_stock_level, 0) <> 0
     );
end $$;

-- Keep service flags consistent even if callers forget.
create or replace function public.sync_product_service_flags()
returns trigger
language plpgsql
as $$
begin
  if NEW.product_type is null then
    NEW.product_type := 'product';
  end if;

  NEW.is_service := (NEW.product_type = 'service');

  if NEW.is_service then
    NEW.track_stock := false;
    NEW.inventory_qty := 0;
    NEW.stock_quantity := 0;
    NEW.min_stock_level := 0;
    NEW.max_stock_level := 0;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_sync_product_service_flags on products;
create trigger trg_sync_product_service_flags
  before insert or update of product_type, is_service, track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
  on products
  for each row
  execute function public.sync_product_service_flags();

create index if not exists idx_products_supplier_id on products(supplier_id);
create index if not exists idx_products_brand_id on products(brand_id);
create index if not exists idx_products_gtin on products(gtin);
create index if not exists idx_products_hs_code on products(hs_code);

-- ============================================================================
-- PUBLIC STORE SEARCH (RPC)
-- ============================================================================
-- Tokenized AND search + accent-insensitive normalization.
-- Example: "camara 26" matches "Cámara ... 26x1,95...".

create extension if not exists pg_trgm;
create extension if not exists unaccent;

create or replace function public.search_products(
  p_search_term text,
  p_tenant_id uuid,
  p_limit int default 10
)
returns setof public.products
language sql
security invoker
set search_path = public
as $$
  with q as (
    select
      unaccent(lower(coalesce(p_search_term, ''))) as term,
      array_remove(
        regexp_split_to_array(
          regexp_replace(unaccent(lower(coalesce(p_search_term, ''))), '[^a-z0-9]+', ' ', 'g'),
          '\\s+'
        ),
        ''
      ) as tokens
  )
  select p.*
  from public.products p
  cross join q
  where
    q.term <> ''
    and p.tenant_id = p_tenant_id
    and p.is_active = true
    and (
      p.product_type = 'service'
      or coalesce(p.track_stock, true) = false
      or coalesce(p.inventory_qty, 0) > 0
      or coalesce(p.stock_quantity, 0) > 0
    )

    -- AND semantics across tokens, OR semantics across fields
    and (
      select bool_and(
        case
          -- Numeric-only tokens (e.g. "26") often represent sizes.
          -- Avoid matching them inside long identifier fields like SKU/barcodes,
          -- which can create false positives.
          when t ~ '^[0-9]+$' then
            (
              unaccent(lower(coalesce(p.name, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.description, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.brand, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.model, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.manufacturer, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.category_name, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.sku, ''))) ~ ('(^|[^0-9])' || t || '([^0-9]|$)')
              or unaccent(lower(coalesce(p.manufacturer_sku, ''))) ~ ('(^|[^0-9])' || t || '([^0-9]|$)')
            )
          else
            (
              unaccent(lower(coalesce(p.name, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.sku, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.description, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.brand, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.model, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.manufacturer, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.manufacturer_sku, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.barcode, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.gtin, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.category_name, ''))) like '%' || t || '%'
            )
        end
      )
      from unnest(q.tokens) as t
    )

  order by
    -- Prefer direct substring hits in the most relevant fields
    case when unaccent(lower(coalesce(p.sku, ''))) = q.term then 5 else 0 end desc,
    case when unaccent(lower(coalesce(p.name, ''))) like '%' || q.term || '%' then 4 else 0 end desc,
    case when unaccent(lower(coalesce(p.sku, ''))) like '%' || q.term || '%' then 3 else 0 end desc,
    case when unaccent(lower(coalesce(p.brand, ''))) like '%' || q.term || '%' then 2 else 0 end desc,

    -- Then trigram similarity
    greatest(
      similarity(unaccent(lower(coalesce(p.name, ''))), q.term),
      similarity(unaccent(lower(coalesce(p.sku, ''))), q.term),
      similarity(unaccent(lower(coalesce(p.description, ''))), q.term)
    ) desc,

    -- Stable ordering
    p.name asc

  limit greatest(p_limit, 0);
$$;

grant execute on function public.search_products(text, uuid, int) to anon;
grant execute on function public.search_products(text, uuid, int) to authenticated;

-- ============================================================================
-- PRODUCT SETS SYSTEM - Juegos/Sets de Productos
-- ============================================================================
-- Allows products to be defined as "sets" containing multiple components.
-- Example: "Juego Mazas Shimano Deore" = Front Hub + Rear Hub
-- Stock is tracked at component level, not at set level.
-- ============================================================================

-- Add set-related columns to products table
do $$
begin
  -- is_set: True if this product is a parent set product
  if not exists (select 1 from information_schema.columns 
    where table_name = 'products' and column_name = 'is_set') then
    alter table products add column is_set boolean not null default false;
  end if;

  -- set_type: Type of set for UI hints ('pair', 'front_rear', 'left_right', 'custom')
  if not exists (select 1 from information_schema.columns 
    where table_name = 'products' and column_name = 'set_type') then
    alter table products add column set_type text;
  end if;

  -- parent_set_id: If this is a component, references the parent set
  if not exists (select 1 from information_schema.columns 
    where table_name = 'products' and column_name = 'parent_set_id') then
    alter table products add column parent_set_id uuid references products(id) on delete set null;
  end if;

  -- component_label: For components, stores the label like "Delantero", "Trasero"
  if not exists (select 1 from information_schema.columns 
    where table_name = 'products' and column_name = 'component_label') then
    alter table products add column component_label text;
  end if;

  -- component_position: For ordering components in the set (1, 2, 3...)
  if not exists (select 1 from information_schema.columns 
    where table_name = 'products' and column_name = 'component_position') then
    alter table products add column component_position integer;
  end if;
end $$;

-- Indexes for fast lookups
create index if not exists idx_products_parent_set 
  on products(parent_set_id) where parent_set_id is not null;
create index if not exists idx_products_is_set 
  on products(is_set) where is_set = true;

-- Product Set Components Table: Links parent sets to their child products
create table if not exists product_set_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  
  -- Parent set product
  set_product_id uuid references products(id) on delete cascade not null,
  
  -- Child component product
  component_product_id uuid references products(id) on delete cascade not null,
  
  -- Component metadata
  component_label text not null,        -- "Delantero", "Trasero", "Izquierdo", "Derecho"
  component_position integer not null,  -- Order: 1, 2, 3...
  quantity_in_set integer not null default 1,  -- Usually 1, could be 2 for "par de pedales"
  
  -- Pricing ratios (for calculating component prices from set price)
  cost_ratio numeric(5,4),   -- 0.4 = 40% of set cost goes to this component
  price_ratio numeric(5,4),  -- 0.6 = 60% of set price goes to this component
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  
  -- Constraints
  unique(set_product_id, component_product_id),
  unique(set_product_id, component_position)
);

-- Indexes for product_set_components
create index if not exists idx_product_set_components_tenant 
  on product_set_components(tenant_id);
create index if not exists idx_product_set_components_set 
  on product_set_components(set_product_id);
create index if not exists idx_product_set_components_component 
  on product_set_components(component_product_id);

-- Enable RLS on product_set_components
alter table product_set_components enable row level security;

-- RLS Policies for product_set_components
drop policy if exists "product_set_components_select" on product_set_components;
drop policy if exists "product_set_components_insert" on product_set_components;
drop policy if exists "product_set_components_update" on product_set_components;
drop policy if exists "product_set_components_delete" on product_set_components;

create policy "product_set_components_select" on product_set_components
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "product_set_components_insert" on product_set_components
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "product_set_components_update" on product_set_components
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "product_set_components_delete" on product_set_components
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger for updated_at on product_set_components
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_product_set_components_updated_at') then
    create trigger trg_product_set_components_updated_at 
      before update on product_set_components
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- Function: Get component availability for a set
-- Returns the minimum stock across all components (= max full sets available)
create or replace function public.get_set_availability(p_set_product_id uuid)
returns table (
  component_id uuid,
  component_name text,
  component_label text,
  component_position integer,
  stock_quantity integer,
  quantity_needed integer
)
language plpgsql
as $$
begin
  return query
  select 
    psc.component_product_id as component_id,
    p.name as component_name,
    psc.component_label,
    psc.component_position,
    coalesce(p.stock_quantity, p.inventory_qty, 0)::integer as stock_quantity,
    psc.quantity_in_set as quantity_needed
  from product_set_components psc
  join products p on p.id = psc.component_product_id
  where psc.set_product_id = p_set_product_id
  order by psc.component_position;
end;
$$;

-- Function: Get full sets available (min stock across all components)
create or replace function public.get_full_sets_count(p_set_product_id uuid)
returns integer
language plpgsql
as $$
declare
  v_min_sets integer;
begin
  select min(
    floor(coalesce(p.stock_quantity, p.inventory_qty, 0)::numeric / psc.quantity_in_set)
  )::integer
  into v_min_sets
  from product_set_components psc
  join products p on p.id = psc.component_product_id
  where psc.set_product_id = p_set_product_id;
  
  return coalesce(v_min_sets, 0);
end;
$$;

-- Function: Check if set has partial availability
create or replace function public.is_set_partial(p_set_product_id uuid)
returns boolean
language plpgsql
as $$
declare
  v_has_stock boolean;
  v_missing_stock boolean;
begin
  -- Check if at least one component has stock
  select exists (
    select 1 from product_set_components psc
    join products p on p.id = psc.component_product_id
    where psc.set_product_id = p_set_product_id
      and coalesce(p.stock_quantity, p.inventory_qty, 0) >= psc.quantity_in_set
  ) into v_has_stock;
  
  -- Check if at least one component is missing stock
  select exists (
    select 1 from product_set_components psc
    join products p on p.id = psc.component_product_id
    where psc.set_product_id = p_set_product_id
      and coalesce(p.stock_quantity, p.inventory_qty, 0) < psc.quantity_in_set
  ) into v_missing_stock;
  
  -- Partial = some have stock AND some don't
  return v_has_stock and v_missing_stock;
end;
$$;

-- View: Products with set information (enriches products with component data)
create or replace view public.products_with_sets as
select 
  p.*,
  -- For sets: aggregate component info
  case when p.is_set then
    (select json_agg(
      json_build_object(
        'id', psc.id,
        'component_product_id', psc.component_product_id,
        'component_label', psc.component_label,
        'component_position', psc.component_position,
        'component_name', cp.name,
        'component_sku', cp.sku,
        'stock_quantity', coalesce(cp.stock_quantity, cp.inventory_qty, 0),
        'quantity_in_set', psc.quantity_in_set,
        'cost_ratio', psc.cost_ratio,
        'price_ratio', psc.price_ratio
      ) order by psc.component_position
    )
    from product_set_components psc
    join products cp on cp.id = psc.component_product_id
    where psc.set_product_id = p.id)
  end as set_components,
  -- For sets: calculate availability
  case when p.is_set then public.get_full_sets_count(p.id) end as full_sets_available,
  case when p.is_set then public.is_set_partial(p.id) end as is_partial,
  -- For components: get parent set info
  case when p.parent_set_id is not null then
    (select json_build_object(
      'id', ps.id,
      'name', ps.name,
      'sku', ps.sku
    ) from products ps where ps.id = p.parent_set_id)
  end as parent_set_info
from products p;

-- ============================================================================
-- STOCK ADJUSTMENTS TABLE - Track manual stock changes
-- ============================================================================
create table if not exists stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade not null,
  adjustment_type text not null check (adjustment_type in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import')),
  quantity integer not null, -- Positive or negative
  stock_before integer not null,
  stock_after integer not null,
  reason text,
  notes text,
  reference text, -- For imports: stores import batch ID or filename
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, id)
);

-- Migration: Add reference column for existing tables (if created before this was added)
alter table stock_adjustments add column if not exists reference text;

-- Migration: Update constraint to include 'import' type
do $$ 
begin
  alter table stock_adjustments drop constraint if exists stock_adjustments_adjustment_type_check;
  alter table stock_adjustments add constraint stock_adjustments_adjustment_type_check 
    check (adjustment_type in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import'));
exception
  when others then null;
end $$;

create index if not exists idx_stock_adjustments_tenant on stock_adjustments(tenant_id);
create index if not exists idx_stock_adjustments_product on stock_adjustments(product_id);
create index if not exists idx_stock_adjustments_created_at on stock_adjustments(created_at);

-- Enable RLS
alter table stock_adjustments enable row level security;

drop policy if exists "stock_adjustments_select" on stock_adjustments;
drop policy if exists "stock_adjustments_insert" on stock_adjustments;
drop policy if exists "stock_adjustments_update" on stock_adjustments;
drop policy if exists "stock_adjustments_delete" on stock_adjustments;

create policy "stock_adjustments_select" on stock_adjustments
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "stock_adjustments_insert" on stock_adjustments
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "stock_adjustments_update" on stock_adjustments
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "stock_adjustments_delete" on stock_adjustments
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger to auto-populate created_by
drop trigger if exists trg_stock_adjustments_set_created_by on stock_adjustments;
create trigger trg_stock_adjustments_set_created_by
  before insert on stock_adjustments
  for each row
  execute function set_created_by();

-- Trigger to track manual stock changes on products table
create or replace function track_product_stock_changes()
returns trigger as $$
declare
  v_adjustment_type text;
  v_reason text;
  v_reference text;
begin
  -- Services and non-stock-tracked items should not generate stock adjustments.
  if coalesce(NEW.product_type, 'product') = 'service'
     or coalesce(NEW.track_stock, true) = false then
    return NEW;
  end if;

  -- CRITICAL: Only track MANUAL changes, not automatic ones from invoice triggers
  -- Skip if this update is triggered by invoice consumption functions
  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true' then
    return NEW;
  end if;
  
  -- Only track if stock_quantity actually changed
  if (TG_OP = 'UPDATE' and OLD.stock_quantity <> NEW.stock_quantity) then
    -- Determine adjustment type based on context
    if current_setting('app.stock_adjustment_context', true) = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(
        current_setting('app.import_reason', true),
        'Stock updated via import'
      );
      v_reference := current_setting('app.import_reference', true); -- Import filename or batch ID
    else
      v_adjustment_type := 'manual';
      v_reason := 'Manual adjustment via product form';
      v_reference := null;
    end if;
    
    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity - OLD.stock_quantity,
      OLD.stock_quantity,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );
  elsif (TG_OP = 'INSERT' and NEW.stock_quantity > 0) then
    -- Track initial stock when product is created with stock
    -- Check if this is part of an import
    if current_setting('app.stock_adjustment_context', true) = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(
        current_setting('app.import_reason', true),
        'Initial stock via import'
      );
      v_reference := current_setting('app.import_reference', true);
    else
      v_adjustment_type := 'initial';
      v_reason := 'Initial stock on product creation';
      v_reference := null;
    end if;
    
    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity,
      0,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );
  end if;
  
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_track_product_stock_changes on products;
create trigger trg_track_product_stock_changes
  after insert or update of stock_quantity
  on products
  for each row
  execute function track_product_stock_changes();

-- ============================================================================
-- PRODUCT TRIGGERS - Sync denormalized fields
-- ============================================================================

-- Function to sync category_name when category_id changes
create or replace function sync_product_category_name()
returns trigger as $$
begin
  -- Update category_name from product_categories table
  if NEW.category_id is not null then
    select name into NEW.category_name
    from product_categories
    where id = NEW.category_id;
  else
    NEW.category_name := null;
  end if;
  
  -- Update supplier_name from suppliers table
  if NEW.supplier_id is not null then
    select name into NEW.supplier_name
    from suppliers
    where id = NEW.supplier_id;
  else
    NEW.supplier_name := null;
  end if;
  
  return NEW;
end;
$$ language plpgsql;

-- Trigger to sync category_name and supplier_name on INSERT or UPDATE
drop trigger if exists trg_sync_product_denormalized_fields on products;
create trigger trg_sync_product_denormalized_fields
  before insert or update of category_id, supplier_id
  on products
  for each row
  execute function sync_product_category_name();

-- Function to update category_name when category name changes
create or replace function sync_products_on_category_change()
returns trigger as $$
begin
  -- When a category name changes, update all products using that category
  if TG_OP = 'UPDATE' and OLD.name is distinct from NEW.name then
    update products
    set category_name = NEW.name
    where category_id = NEW.id;
  end if;
  
  return NEW;
end;
$$ language plpgsql;

-- Trigger on product_categories to sync product names
drop trigger if exists trg_sync_products_on_category_change on product_categories;
create trigger trg_sync_products_on_category_change
  after update of name
  on product_categories
  for each row
  execute function sync_products_on_category_change();

-- Function to update supplier_name when supplier name changes
create or replace function sync_products_on_supplier_change()
returns trigger as $$
begin
  -- When a supplier name changes, update all products using that supplier
  if TG_OP = 'UPDATE' and OLD.name is distinct from NEW.name then
    update products
    set supplier_name = NEW.name
    where supplier_id = NEW.id;
  end if;
  
  return NEW;
end;
$$ language plpgsql;

-- Trigger on suppliers to sync product supplier names
drop trigger if exists trg_sync_products_on_supplier_change on suppliers;
create trigger trg_sync_products_on_supplier_change
  after update of name
  on suppliers
  for each row
  execute function sync_products_on_supplier_change();

-- ============================================================================
-- PRODUCT CATEGORIES - Hierarchical (Odoo-style)
-- ============================================================================

-- Step 1: Create the new product_categories table if it doesn't exist
create table if not exists product_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  full_path text not null, -- e.g., "Accesorios / Asientos / Tija"
  parent_id uuid references product_categories(id) on delete cascade,
  level integer not null default 0, -- 0 = root, 1 = child, 2 = grandchild, etc.
  description text,
  image_url text,
  is_active boolean not null default true,
  show_on_website boolean not null default false, -- Whether to show in public store navigation
  sort_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, full_path) -- Each tenant can have same category paths
);

-- Add show_on_website column if not exists (for existing tables)
alter table product_categories add column if not exists show_on_website boolean not null default false;

-- Step 2: Create indexes for product_categories
create index if not exists idx_product_categories_parent_id on product_categories(parent_id);
create index if not exists idx_product_categories_full_path on product_categories(full_path);
create index if not exists idx_product_categories_level on product_categories(level);
create index if not exists idx_product_categories_is_active on product_categories(is_active);
create index if not exists idx_product_categories_name on product_categories using gin (to_tsvector('spanish', coalesce(name, '')));

-- Step 3: Migrate existing data from 'categories' to 'product_categories' (if old table exists)
do $$
declare
  old_table_exists boolean;
  has_sort_order boolean;
  has_description boolean;
  has_image_url boolean;
  migration_sql text;
begin
  -- Check if old 'categories' table exists
  select exists (
    select from pg_tables
    where schemaname = 'public'
    and tablename = 'categories'
  ) into old_table_exists;

  if old_table_exists then
    raise notice 'Found old categories table, migrating data...';
    
    -- Check which columns exist in old table
    select exists (
      select 1 from information_schema.columns 
      where table_schema = 'public' 
      and table_name = 'categories' 
      and column_name = 'sort_order'
    ) into has_sort_order;
    
    select exists (
      select 1 from information_schema.columns 
      where table_schema = 'public' 
      and table_name = 'categories' 
      and column_name = 'description'
    ) into has_description;
    
    select exists (
      select 1 from information_schema.columns 
      where table_schema = 'public' 
      and table_name = 'categories' 
      and column_name = 'image_url'
    ) into has_image_url;
    
    -- Build dynamic SQL based on available columns
    migration_sql := 'insert into product_categories (id, name, full_path, parent_id, level, description, image_url, is_active, sort_order, created_at, updated_at) ' ||
                     'select id, name, name as full_path, null as parent_id, 0 as level, ';
    
    if has_description then
      migration_sql := migration_sql || 'description, ';
    else
      migration_sql := migration_sql || 'null as description, ';
    end if;
    
    if has_image_url then
      migration_sql := migration_sql || 'image_url, ';
    else
      migration_sql := migration_sql || 'null as image_url, ';
    end if;
    
    migration_sql := migration_sql || 'coalesce(is_active, true) as is_active, ';
    
    if has_sort_order then
      migration_sql := migration_sql || 'coalesce(sort_order, 0) as sort_order, ';
    else
      migration_sql := migration_sql || '0 as sort_order, ';
    end if;
    
    migration_sql := migration_sql || 'created_at, updated_at from categories on conflict (id) do nothing';
    
    -- Execute migration
    execute migration_sql;

    raise notice 'Migrated % categories from old table', (select count(*) from categories);
  else
    raise notice 'Old categories table does not exist, skipping migration';
  end if;
end $$;

-- Step 4: Drop old foreign key constraint if it exists and points to wrong table
do $$
begin
  -- Check if constraint exists and points to 'categories' table
  if exists (
    select 1
    from pg_constraint c
    join pg_class t on c.conrelid = t.oid
    join pg_class ft on c.confrelid = ft.oid
    where t.relname = 'products'
    and c.conname = 'products_category_id_fkey'
    and ft.relname = 'categories'
  ) then
    alter table products drop constraint products_category_id_fkey;
    raise notice 'Dropped old products_category_id_fkey constraint pointing to categories table';
  end if;
end $$;

-- Step 5: Add new foreign key constraint pointing to product_categories
do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.products'::regclass
       and conname = 'products_category_id_fkey'
  ) then
    alter table products
      add constraint products_category_id_fkey
        foreign key (category_id) references public.product_categories(id) on delete set null;
    raise notice 'Added products_category_id_fkey constraint pointing to product_categories';
  end if;
end $$;

create index if not exists idx_products_category_id on products(category_id);
 
create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  rut text,
  email text,
  phone text,
  address text,
  city text,
  region text,
  comuna text,
  contact_person text,
  website text,
  type text not null default 'local',
  bank_details jsonb not null default '{}'::jsonb,
  payment_terms text not null default 'net30',
  notes text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.suppliers
  add column if not exists rut text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists region text,
  add column if not exists comuna text,
  add column if not exists contact_person text,
  add column if not exists website text,
  add column if not exists type text not null default 'local',
  add column if not exists bank_details jsonb not null default '{}'::jsonb,
  add column if not exists payment_terms text not null default 'net30',
  add column if not exists notes text,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now(),
  add column if not exists default_tax_treatment text not null default 'no_tax' check (default_tax_treatment in ('no_tax', 'tax_included'));

comment on column suppliers.default_tax_treatment is
  'Suggested tax treatment for purchases from this supplier. tax_included = invoice with IVA, no_tax = receipt or international purchase. User can override per transaction.';

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'suppliers'
      and t.tgname = 'trg_suppliers_updated_at'
  ) then
    create trigger trg_suppliers_updated_at
      before update on suppliers
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_suppliers_name on suppliers using gin (to_tsvector('spanish', coalesce(name, '')));
create index if not exists idx_suppliers_tenant on suppliers(tenant_id);

-- Add unique constraint for tenant_id + name (multi-tenant isolation)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'suppliers'::regclass
    and conname = 'suppliers_tenant_name_unique'
  ) then
    alter table suppliers add constraint suppliers_tenant_name_unique unique (tenant_id, name);
  end if;
end $$;

-- ============================================================================
-- SMART PURCHASE LIST - Intelligent purchase planning
-- ============================================================================
create table if not exists smart_purchase_list (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  product_name text not null,
  product_sku text,
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  suggested_quantity integer not null default 1,
  actual_quantity integer, -- User can override suggested quantity
  status text not null default 'pending'
    check (status in ('pending','ordered','received','ignored','cancelled','archived')),
  priority numeric(5,2) not null default 50, -- 0-100 scale
  rotation_kpi numeric(5,2), -- How fast the item moves (sales per day)
  days_since_last_purchase integer,
  current_stock integer not null default 0,
  min_stock_level integer not null default 0,
  stock_at_order integer, -- Stock quantity when purchase order was generated
  stock_at_receipt integer, -- Stock quantity when invoice was received (final stock after purchase)
  avg_daily_consumption numeric(10,2), -- Average units sold per day
  lead_time_days integer not null default 0,
  estimated_stockout_date timestamp with time zone, -- When stock will run out
  notes text,
  added_by uuid references auth.users(id) on delete set null,
  added_date timestamp with time zone not null default now(),
  linked_purchase_invoice_id uuid references purchase_invoices(id) on delete set null,
  linked_expense_id uuid references expenses(id) on delete set null,
  ordered_date timestamp with time zone,
  received_date timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_smart_purchase_list_tenant on smart_purchase_list(tenant_id);
create index if not exists idx_smart_purchase_list_product on smart_purchase_list(product_id);
create index if not exists idx_smart_purchase_list_supplier on smart_purchase_list(supplier_id);
create index if not exists idx_smart_purchase_list_status on smart_purchase_list(status);
create index if not exists idx_smart_purchase_list_priority on smart_purchase_list(priority desc);
create index if not exists idx_smart_purchase_list_added_date on smart_purchase_list(added_date desc);

-- Add stock_at_order column if it doesn't exist (migration for existing tables)
alter table smart_purchase_list add column if not exists stock_at_order integer;

-- Add stock_at_receipt column if it doesn't exist (migration for existing tables)
alter table smart_purchase_list add column if not exists stock_at_receipt integer;

-- Add category columns if they don't exist (migration for existing tables)
alter table smart_purchase_list add column if not exists category_id uuid references product_categories(id) on delete set null;
alter table smart_purchase_list add column if not exists category_name text;

-- Add index for category filtering
create index if not exists idx_smart_purchase_list_category on smart_purchase_list(category_id);

-- Enable RLS for smart_purchase_list
alter table smart_purchase_list enable row level security;

drop policy if exists "smart_purchase_list_select" on smart_purchase_list;
drop policy if exists "smart_purchase_list_insert" on smart_purchase_list;
drop policy if exists "smart_purchase_list_update" on smart_purchase_list;
drop policy if exists "smart_purchase_list_delete" on smart_purchase_list;

create policy "smart_purchase_list_select" on smart_purchase_list
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "smart_purchase_list_insert" on smart_purchase_list
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "smart_purchase_list_update" on smart_purchase_list
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "smart_purchase_list_delete" on smart_purchase_list
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger function to auto-add products to smart purchase list when stock is low
create or replace function public.auto_add_low_stock_to_purchase_list()
returns trigger
language plpgsql
security definer
as $$
declare
  v_supplier_id uuid;
  v_supplier_name text;
  v_rotation_kpi numeric(5,2);
  v_avg_daily_consumption numeric(10,2);
  v_days_since_last_purchase integer;
  v_suggested_qty integer;
  v_priority numeric(5,2);
  v_lead_time_days integer;
  v_estimated_stockout_date timestamp with time zone;
  v_current_stock integer;
begin
  -- Sync inventory_qty to match stock_quantity (stock_quantity is source of truth)
  -- This ensures both columns stay in sync for backward compatibility
  if NEW.stock_quantity != NEW.inventory_qty then
    NEW.inventory_qty := NEW.stock_quantity;
  end if;
  
  -- Use whichever column is set (prefer stock_quantity as source of truth)
  v_current_stock := coalesce(NEW.stock_quantity, NEW.inventory_qty, 0);
  
  -- AUTO-REMOVAL: If stock is now ABOVE minimum level, remove from pending list
  if v_current_stock > NEW.min_stock_level then
    delete from smart_purchase_list
    where product_id = NEW.id
    and status = 'pending'
    and tenant_id = NEW.tenant_id;
    
    if found then
      raise notice '🗑️ Auto-removed product % (%) from purchase list - stock restored to %', NEW.name, NEW.sku, v_current_stock;
    end if;
    
    return NEW;
  end if;
  
  -- AUTO-ADD: Trigger when stock is at or below minimum level
  if v_current_stock <= NEW.min_stock_level then
    
    -- Check if product is already in the purchase list with pending/ordered status
    if exists (
      select 1 from smart_purchase_list
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id
    ) then
      -- Already in list, just update the current stock
      update smart_purchase_list
      set current_stock = v_current_stock,
          updated_at = now()
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id;
      
      return NEW;
    end if;
    
    -- Get supplier info (use default supplier if product has one)
    select s.id, s.name into v_supplier_id, v_supplier_name
    from suppliers s
    where s.tenant_id = NEW.tenant_id
    and s.is_active = true
    order by s.created_at asc
    limit 1;
    
    -- Calculate rotation KPI (sales per day over last 30 days)
    -- Use JSONB items array since we don't have a separate line items table
    select 
      coalesce(
        (select count(*)::numeric / 30.0
         from sales_invoices si,
         jsonb_array_elements(si.items) as item
         where item->>'product_id' = NEW.id::text
         and si.tenant_id = NEW.tenant_id
         and si.date >= now() - interval '30 days'),
        0
      ) into v_rotation_kpi;
    
    -- Average daily consumption
    v_avg_daily_consumption := greatest(v_rotation_kpi, 0.1);
    
    -- Days since last purchase
    -- Use JSONB items array since we don't have a separate line items table
    select 
      extract(day from now() - max(pi.date))::integer into v_days_since_last_purchase
    from purchase_invoices pi,
    jsonb_array_elements(pi.items) as item
    where item->>'product_id' = NEW.id::text
    and pi.tenant_id = NEW.tenant_id;
    
    v_days_since_last_purchase := coalesce(v_days_since_last_purchase, 999);
    
    -- Suggested quantity: enough to reach max stock or at least cover 30 days
    v_suggested_qty := greatest(
      NEW.max_stock_level - v_current_stock,
      ceil(v_avg_daily_consumption * 30)::integer,
      1
    );
    
    -- Lead time (default 7 days, could be supplier-specific in the future)
    v_lead_time_days := 7;
    
    -- Estimated stockout date
    if v_avg_daily_consumption > 0 then
      v_estimated_stockout_date := now() + (v_current_stock / v_avg_daily_consumption || ' days')::interval;
    else
      v_estimated_stockout_date := null;
    end if;
    
    -- Calculate priority (0-100 scale)
    -- Formula: rotation * 0.6 + urgency * 0.3 + days_since_purchase * 0.1
    v_priority := least(100, greatest(0,
      (v_rotation_kpi * 10 * 0.6) + -- rotation scaled to 0-100
      (case 
        when v_current_stock = 0 then 100 
        when coalesce(NEW.min_stock_level, 0) = 0 then 50 -- Default urgency when min_stock_level is 0 or null
        else (1 - (v_current_stock::numeric / NEW.min_stock_level)) * 100 
      end * 0.3) + -- urgency
      (least(v_days_since_last_purchase, 100) * 0.1) -- days since last purchase capped at 100
    ));
    
    -- Insert into smart purchase list
    insert into smart_purchase_list (
      tenant_id,
      product_id,
      product_name,
      product_sku,
      supplier_id,
      supplier_name,
      suggested_quantity,
      status,
      priority,
      rotation_kpi,
      days_since_last_purchase,
      current_stock,
      min_stock_level,
      avg_daily_consumption,
      lead_time_days,
      estimated_stockout_date,
      notes,
      added_date
    ) values (
      NEW.tenant_id,
      NEW.id,
      NEW.name,
      NEW.sku,
      v_supplier_id,
      v_supplier_name,
      v_suggested_qty,
      'pending',
      v_priority,
      v_rotation_kpi,
      v_days_since_last_purchase,
      v_current_stock,
      NEW.min_stock_level,
      v_avg_daily_consumption,
      v_lead_time_days,
      v_estimated_stockout_date,
      'Auto-added: stock at or below minimum level',
      now()
    );
    
    raise notice '✅ Auto-added product % (%) to purchase list with priority %', NEW.name, NEW.sku, v_priority;
  end if;
  
  return NEW;
end;
$$;

-- Trigger on products table to monitor stock levels
drop trigger if exists trg_auto_add_low_stock on products;
create trigger trg_auto_add_low_stock
  after insert or update of stock_quantity, inventory_qty
  on products
  for each row
  execute function public.auto_add_low_stock_to_purchase_list();

-- Function to update smart_purchase_list when purchase invoice status changes
create or replace function public.auto_update_purchase_list_on_invoice_status()
returns trigger
language plpgsql
security definer
as $$
declare
  v_item jsonb;
  v_product_id uuid;
begin
  -- When invoice is confirmed or received, mark linked items as ordered
  if NEW.status in ('confirmed', 'received') and OLD.status not in ('confirmed', 'received') then
    -- Loop through items in the JSONB array
    for v_item in select * from jsonb_array_elements(NEW.items)
    loop
      v_product_id := (v_item->>'product_id')::uuid;
      
      if v_product_id is not null then
        update smart_purchase_list spl
        set 
          status = 'ordered',
          linked_purchase_invoice_id = NEW.id,
          ordered_date = coalesce(ordered_date, now()),
          stock_at_order = (select stock_quantity from products where id = v_product_id),
          updated_at = now()
        where spl.product_id = v_product_id
          and spl.tenant_id = NEW.tenant_id
          and spl.status = 'pending'
          and (spl.linked_purchase_invoice_id is null or spl.linked_purchase_invoice_id = NEW.id);
      end if;
    end loop;
  end if;
  
  -- When invoice is received or paid, UPDATE status to 'received' (keep history!)
  if NEW.status in ('received', 'paid') and OLD.status not in ('received', 'paid') then
    -- Loop through items in the JSONB array
    for v_item in select * from jsonb_array_elements(NEW.items)
    loop
      v_product_id := (v_item->>'product_id')::uuid;
      
      if v_product_id is not null then
        -- Update status to 'received' and record the date + final stock
        update smart_purchase_list
        set 
          status = 'received',
          received_date = now(),
          stock_at_receipt = (select stock_quantity from products where id = v_product_id),
          updated_at = now()
        where product_id = v_product_id
          and tenant_id = NEW.tenant_id
          and status in ('pending', 'ordered')
          and (linked_purchase_invoice_id is null or linked_purchase_invoice_id = NEW.id);
        
        raise notice '✅ Marked product % as received in purchase list (invoice % received)', v_product_id, NEW.id;
      end if;
    end loop;
  end if;
  
  return NEW;
end;
$$;

-- Trigger on purchase_invoices to update purchase list when status changes
drop trigger if exists trg_update_purchase_list_on_status_change on purchase_invoices;
create trigger trg_update_purchase_list_on_status_change
  after update of status
  on purchase_invoices
  for each row
  execute function public.auto_update_purchase_list_on_invoice_status();

-- Function to backfill stock_at_receipt for existing received items
-- This calculates the stock at receipt by adding purchased quantity to stock_at_order
create or replace function public.backfill_stock_at_receipt_for_received_items()
returns void
language plpgsql
security definer
as $$
declare
  v_item record;
  v_purchased_qty integer;
  v_invoice_item jsonb;
begin
  -- Loop through all received items that don't have stock_at_receipt yet
  for v_item in 
    select 
      spl.id,
      spl.product_id,
      spl.stock_at_order,
      spl.linked_purchase_invoice_id,
      spl.tenant_id
    from smart_purchase_list spl
    where spl.status = 'received'
      and spl.stock_at_receipt is null
      and spl.linked_purchase_invoice_id is not null
      and spl.stock_at_order is not null
  loop
    -- Get the purchased quantity from the invoice
    select 
      sum((item->>'quantity')::integer) into v_purchased_qty
    from purchase_invoices pi,
         jsonb_array_elements(pi.items) as item
    where pi.id = v_item.linked_purchase_invoice_id
      and (item->>'product_id')::uuid = v_item.product_id;
    
    if v_purchased_qty is not null then
      -- Calculate stock_at_receipt = stock_at_order + purchased_quantity
      update smart_purchase_list
      set stock_at_receipt = v_item.stock_at_order + v_purchased_qty
      where id = v_item.id;
      
      raise notice '✅ Backfilled stock_at_receipt for product % (was %, purchased %, now %)', 
        v_item.product_id, v_item.stock_at_order, v_purchased_qty, v_item.stock_at_order + v_purchased_qty;
    end if;
  end loop;
end;
$$;

-- Run the backfill function for existing data (safe to run multiple times)
select public.backfill_stock_at_receipt_for_received_items();

-- ============================================================================
-- RPC WRAPPER FOR SESSION VARIABLES (set_config)
-- ============================================================================
-- Expose PostgreSQL's set_config() function as Supabase RPC
-- This allows authenticated clients to set transaction-scoped session variables
-- Used for import tracking context (app.stock_adjustment_context, app.import_reference, etc.)

create or replace function public.set_config(
  setting_name text,
  new_value text,
  is_local boolean default true
)
returns text
language plpgsql
security definer
as $$
begin
  -- Set the configuration parameter
  perform pg_catalog.set_config(setting_name, new_value, is_local);
  return new_value;
end;
$$;

-- Grant execute to authenticated users (for import services)
grant execute on function public.set_config(text, text, boolean) to authenticated;

-- ============================================================================
-- IMPORT PRODUCT WITH CONTEXT (Single Transaction)
-- ============================================================================
-- This function updates a product's stock within an import context
-- It sets session variables and updates the product in ONE transaction
-- so the trigger can detect it's an import operation

create or replace function public.import_product_with_context(
  p_tenant_id uuid,
  p_sku text,
  p_product_data jsonb,
  p_import_reference text,
  p_import_reason text default 'Importación desde archivo'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_result jsonb;
  v_updated_count integer;
begin
  -- Set import context for this transaction
  perform pg_catalog.set_config('app.stock_adjustment_context', 'import', true);
  perform pg_catalog.set_config('app.import_reference', p_import_reference, true);
  perform pg_catalog.set_config('app.import_reason', p_import_reason, true);
  
  -- Update the product (trigger will see the import context)
  update products
  set
    name = coalesce((p_product_data->>'name')::text, name),
    description = coalesce((p_product_data->>'description')::text, description),
    price = coalesce((p_product_data->>'price')::numeric, price),
    cost = coalesce((p_product_data->>'cost')::numeric, cost),
    stock_quantity = coalesce((p_product_data->>'stock_quantity')::integer, stock_quantity),
    inventory_qty = coalesce((p_product_data->>'stock_quantity')::integer, inventory_qty),
    category_id = coalesce((p_product_data->>'category_id')::uuid, category_id),
    supplier_id = coalesce((p_product_data->>'supplier_id')::uuid, supplier_id),
    barcode = coalesce((p_product_data->>'barcode')::text, barcode),
    image_url = coalesce((p_product_data->>'image_url')::text, image_url),
    is_active = coalesce((p_product_data->>'is_active')::boolean, is_active),
    updated_at = now()
  where tenant_id = p_tenant_id
    and sku = p_sku;
  
  get diagnostics v_updated_count = row_count;
  
  -- Clear import context
  perform pg_catalog.set_config('app.stock_adjustment_context', '', true);
  perform pg_catalog.set_config('app.import_reference', '', true);
  perform pg_catalog.set_config('app.import_reason', '', true);
  
  -- Return result
  v_result = jsonb_build_object(
    'success', v_updated_count > 0,
    'updated_count', v_updated_count,
    'sku', p_sku
  );
  
  return v_result;
end;
$$;

-- Grant execute to authenticated users (for import services)
grant execute on function public.import_product_with_context(uuid, text, jsonb, text, text) to authenticated;

-- ============================================================================
-- NOTE: stock_movements_view is defined later in this file (around line 4363)
-- after all required columns have been added to sales_invoices and purchase_invoices
-- ============================================================================

-- ============================================================================
-- FIX: Migrate 'tax' type accounts to 'liability' (Dec 1, 2025)
-- The accounting equation only considers: asset, liability, equity, income, expense
-- 'tax' type was causing IVA accounts to be excluded from balance sheet calculations
-- ============================================================================
do $$
begin
  -- Fix IVA Débito Fiscal (sales tax collected - we owe to government = liability)
  update accounts 
  set type = 'liability', category = 'currentLiability'
  where code = '2150' and type = 'tax';
  
  -- Fix IVA Crédito Fiscal (purchase tax paid - government owes us = asset)
  update accounts 
  set type = 'asset', category = 'currentAsset'
  where code = '2120' and type = 'tax';
  
  -- Fix any other tax accounts to liability by default
  update accounts 
  set type = 'liability', category = 'currentLiability'
  where type = 'tax';
  
  raise notice '✅ Migrated tax-type accounts to proper liability/asset types';
exception
  when undefined_table then null;
  when undefined_column then null;
end $$;

create table if not exists accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  code text not null,
  name text not null,
  type text not null
    check (type in ('asset','liability','equity','income','expense')),
  category text not null
    check (category in (
      'currentAsset','fixedAsset','otherAsset',
      'currentLiability','longTermLiability',
      'capital','retainedEarnings',
      'operatingIncome','nonOperatingIncome',
      'costOfGoodsSold','operatingExpense','financialExpense',
      'taxPayable','taxReceivable','taxExpense'
    )),
  description text,
  parent_id uuid,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, code), -- Each tenant can have same account codes
  unique(tenant_id, id) -- Enable composite FK references (multi-tenant isolation)
);

-- Add tenant_id index for accounts
create index if not exists idx_accounts_tenant on accounts(tenant_id);

-- Add composite FK for accounts.parent_id (self-reference, tenant-scoped)
do $$ begin
  alter table accounts drop constraint if exists accounts_parent_id_fkey;
  alter table accounts add constraint accounts_parent_id_fkey
    foreign key (tenant_id, parent_id) references accounts(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  accounts.parent_id FK: %', sqlerrm;
end $$;

alter table public.accounts
  add column if not exists tenant_id uuid references tenants(id) on delete cascade,
  add column if not exists code text,
  add column if not exists name text,
  add column if not exists type text,
  add column if not exists category text,
  add column if not exists description text,
  add column if not exists parent_id uuid,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  begin
    alter table public.accounts
      alter column code set not null;
  exception when others then
    null;
  end;

  begin
    alter table public.accounts
      alter column name set not null;
  exception when others then
    null;
  end;
end $$;

-- ⚠️ MULTI-TENANT: Ensure accounts have unique code PER TENANT (not globally)
do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'u'
       and conname = 'accounts_tenant_id_code_key'
  ) then
    alter table public.accounts
      add constraint accounts_tenant_id_code_key unique (tenant_id, code);
  end if;
end $$;

-- Remove old 'tax' type constraint and add new one without 'tax'
do $$
begin
  -- Drop old constraint if it includes 'tax'
  alter table public.accounts drop constraint if exists accounts_type_check;
  
  -- Add new constraint without 'tax' type
  alter table public.accounts
    add constraint accounts_type_check
      check (type in ('asset','liability','equity','income','expense'));
exception
  when undefined_table then null;
  when others then raise notice '⚠️ accounts_type_check: %', sqlerrm;
end $$;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'c'
       and conname = 'accounts_category_check'
  ) then
    alter table public.accounts
      add constraint accounts_category_check
        check (category in (
          'currentAsset','fixedAsset','otherAsset',
          'currentLiability','longTermLiability',
          'capital','retainedEarnings',
          'operatingIncome','nonOperatingIncome',
          'costOfGoodsSold','operatingExpense','financialExpense',
          'taxPayable','taxReceivable','taxExpense'
        ));
  end if;
end $$;

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'accounts'
       and column_name = 'parent_id'
  ) then
    if not exists (
      select 1
        from pg_constraint
       where conrelid = 'public.accounts'::regclass
         and contype = 'f'
         and conname = 'accounts_parent_id_fkey'
    ) then
      alter table public.accounts
        add constraint accounts_parent_id_fkey
          foreign key (parent_id)
          references public.accounts(id)
          on delete set null;
    end if;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'accounts'
      and t.tgname = 'trg_accounts_updated_at'
  ) then
    create trigger trg_accounts_updated_at
      before update on accounts
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

do $$
begin
  begin
    alter table public.accounts drop column if exists company_id;
  exception when others then
    begin
      alter table public.accounts alter column company_id drop not null;
    exception when others then
      null;
    end;
  end;
end $$;

create or replace function public.migrate_accounts_to_uuid()
returns void as $$
declare
  v_accounts_id_is_uuid boolean;
  v_accounts_parent_type text;
  v_journal_account_type text;
begin
  select case when data_type = 'uuid' then true else false end
    into v_accounts_id_is_uuid
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'accounts'
     and column_name = 'id'
   limit 1;

  if coalesce(v_accounts_id_is_uuid, false) then
    return;
  end if;

  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'accounts'
       and column_name = 'id_uuid'
  ) then
    alter table public.accounts add column id_uuid uuid;
  end if;

  update public.accounts
     set id_uuid = coalesce(id_uuid, gen_random_uuid());

  alter table public.accounts
    alter column id_uuid set not null;

  select data_type
    into v_journal_account_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'journal_lines'
     and column_name = 'account_id'
   limit 1;

  if v_journal_account_type is not null then
    if v_journal_account_type <> 'uuid' then
      if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'journal_lines'
           and column_name = 'account_id_uuid'
      ) then
        alter table public.journal_lines add column account_id_uuid uuid;
      end if;

      update public.journal_lines jl
         set account_id_uuid = a.id_uuid
        from public.accounts a
       where jl.account_id is not null
         and a.id::text = jl.account_id::text;

      alter table public.journal_lines drop column account_id;
      alter table public.journal_lines rename column account_id_uuid to account_id;
    else
      update public.journal_lines jl
         set account_id = a.id_uuid
        from public.accounts a
       where jl.account_id is not null
         and a.id::text = jl.account_id::text
         and jl.account_id <> a.id_uuid;
    end if;
  end if;

  select data_type
    into v_accounts_parent_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'accounts'
     and column_name = 'parent_id'
   limit 1;

  if v_accounts_parent_type is not null then
    if v_accounts_parent_type <> 'uuid' then
      if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'accounts'
           and column_name = 'parent_id_uuid'
      ) then
        alter table public.accounts add column parent_id_uuid uuid;
      end if;

      update public.accounts child
         set parent_id_uuid = parent.id_uuid
        from public.accounts parent
       where child.parent_id is not null
         and parent.id::text = child.parent_id::text;

      alter table public.accounts drop column parent_id;
      alter table public.accounts rename column parent_id_uuid to parent_id;
    else
      update public.accounts child
         set parent_id = parent.id_uuid
        from public.accounts parent
       where child.parent_id is not null
         and parent.id::text = child.parent_id::text
         and child.parent_id <> parent.id_uuid;
    end if;
  end if;

  if v_journal_account_type is not null then
    alter table public.journal_lines
      drop constraint if exists journal_lines_account_id_fkey;
  end if;

  if exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'f'
       and conname = 'accounts_parent_id_fkey'
  ) then
    alter table public.accounts
      drop constraint accounts_parent_id_fkey;
  end if;

  alter table public.accounts
    drop constraint if exists accounts_pkey;

  alter table public.accounts drop column id;
  alter table public.accounts rename column id_uuid to id;
  alter table public.accounts add primary key (id);
  alter table public.accounts alter column id set default gen_random_uuid();

  if exists (
    select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind = 'S'
       and n.nspname = 'public'
       and c.relname = 'accounts_id_seq'
  ) then
    execute 'drop sequence public.accounts_id_seq';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'accounts'
       and column_name = 'parent_id'
  ) then
    if not exists (
      select 1
        from pg_constraint
       where conrelid = 'public.accounts'::regclass
         and contype = 'f'
         and conname = 'accounts_parent_id_fkey'
    ) then
      alter table public.accounts
        add constraint accounts_parent_id_fkey
          foreign key (parent_id)
          references public.accounts(id)
          on delete set null;
    end if;
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'account_id'
  ) then
    if not exists (
      select 1
        from pg_constraint
       where conrelid = 'public.journal_lines'::regclass
         and contype = 'f'
         and conname = 'journal_lines_account_id_fkey'
    ) then
      alter table public.journal_lines
        add constraint journal_lines_account_id_fkey
          foreign key (account_id)
          references public.accounts(id);
    end if;
  end if;
end;
$$ language plpgsql;

-- Execute migration silently
do $$
begin
  perform public.migrate_accounts_to_uuid();
end $$;

-- Note: Default accounts are now seeded per-tenant via trigger (see handle_new_tenant function)
-- Legacy INSERT removed - all tenants use seed_chart_of_accounts() with 4-digit codes

create or replace function public.ensure_account(
  p_code text,
  p_name text,
  p_type text,
  p_category text,
  p_description text default null,
  p_parent_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_parent_id uuid;
begin
  perform public.migrate_accounts_to_uuid();

  if p_code is null then
    return null;
  end if;

  -- Get current tenant_id (will be null for non-authenticated contexts)
  declare
    v_tenant_id uuid := public.user_tenant_id();
  begin
    -- Lookup parent account (must be in same tenant)
    if p_parent_code is not null and v_tenant_id is not null then
      select id
        into v_parent_id
        from public.accounts
       where tenant_id = v_tenant_id
         and code = p_parent_code
       limit 1;
    elsif p_parent_code is not null and v_tenant_id is null then
      -- Backward compatibility for single-tenant
      select id
        into v_parent_id
        from public.accounts
       where code = p_parent_code
       limit 1;
    end if;
    if v_tenant_id is null then
      raise exception 'Cannot create account without tenant_id. User must be authenticated.';
    end if;
    
    -- Multi-tenant structure: use (tenant_id, code) unique constraint
    insert into public.accounts (tenant_id, code, name, type, category, description, parent_id)
    values (v_tenant_id, p_code, p_name, p_type, p_category, p_description, v_parent_id)
    on conflict (tenant_id, code) do update
      set name = excluded.name,
          type = excluded.type,
          category = excluded.category,
          description = coalesce(excluded.description, accounts.description),
          parent_id = coalesce(excluded.parent_id, accounts.parent_id),
          is_active = true,
          updated_at = now()
    returning id into v_account_id;
  end;

  return v_account_id;
end;
$$;

-- Overloaded version that accepts explicit tenant_id (for use in triggers)
create or replace function public.ensure_account(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_type text,
  p_category text,
  p_description text default null,
  p_parent_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_parent_id uuid;
begin
  perform public.migrate_accounts_to_uuid();

  if p_code is null then
    return null;
  end if;

  -- Lookup parent account (must be in same tenant)
  if p_parent_code is not null and p_tenant_id is not null then
    select id
      into v_parent_id
      from public.accounts
     where tenant_id = p_tenant_id
       and code = p_parent_code
     limit 1;
  elsif p_parent_code is not null and p_tenant_id is null then
    -- Backward compatibility for single-tenant
    select id
      into v_parent_id
      from public.accounts
     where code = p_parent_code
     limit 1;
  end if;

  if p_tenant_id is null then
    raise exception 'Cannot create account without tenant_id. Tenant ID is required for multi-tenant system.';
  end if;

  -- Multi-tenant structure: use (tenant_id, code) unique constraint
  insert into public.accounts (tenant_id, code, name, type, category, description, parent_id)
  values (p_tenant_id, p_code, p_name, p_type, p_category, p_description, v_parent_id)
  on conflict (tenant_id, code) do update
    set name = excluded.name,
        type = excluded.type,
        category = excluded.category,
        description = coalesce(excluded.description, accounts.description),
        parent_id = coalesce(excluded.parent_id, accounts.parent_id),
        is_active = true,
        updated_at = now()
  returning id into v_account_id;

  return v_account_id;
end;
$$;

create table if not exists sales_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  invoice_number text not null,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  customer_rut text,
  date timestamp with time zone not null default now(),
  due_date timestamp with time zone,
  reference text,
  status text not null default 'draft'
    check (lower(status) = any (array[
      'draft','borrador',
      'sent','enviado','enviada','emitido','emitida','issued',
      'confirmed','confirmado','confirmada',
      'paid','pagado','pagada',
      'overdue','vencido','vencida',
      'cancelled','cancelado','cancelada','anulado','anulada'
    ])),
  subtotal numeric(12,2) not null default 0,
  iva_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  balance numeric(12,2) not null default 0,
  items jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, invoice_number) -- Each tenant can have same invoice numbers
);

-- Add flexible tax columns to sales_invoices
alter table sales_invoices 
  add column if not exists tax_treatment text not null default 'no_tax' check (tax_treatment in ('no_tax', 'tax_included')),
  add column if not exists net_amount numeric(12,2) not null default 0;

comment on column sales_invoices.tax_treatment is
  'Actual tax treatment for THIS invoice. no_tax = full amount is revenue, tax_included = amount includes 19% IVA (divide by 1.19)';

comment on column sales_invoices.net_amount is
  'Net amount excluding IVA. If tax_included: total ÷ 1.19, if no_tax: equals total';

-- Migrate existing invoices: calculate net_amount and tax_treatment based on iva_amount
do $$
begin
  -- CRITICAL: Disable triggers during migration to avoid journal entry creation without user context
  alter table sales_invoices disable trigger trg_sales_invoices_change;
  
  -- Set net_amount based on existing iva_amount
  update sales_invoices
  set net_amount = total - iva_amount
  where net_amount = 0 and total > 0;
  
  -- Set tax_treatment based on whether IVA was applied
  update sales_invoices
  set tax_treatment = case 
    when iva_amount > 0 then 'tax_included'
    else 'no_tax'
  end
  where tax_treatment = 'no_tax' and total > 0;
  
  -- Re-enable trigger
  alter table sales_invoices enable trigger trg_sales_invoices_change;
  
  raise notice 'Migrated % sales invoices with tax data', (select count(*) from sales_invoices where total > 0);
exception
  when undefined_table then
    raise notice 'sales_invoices table does not exist yet, skipping migration';
  when undefined_object then
    raise notice 'trg_sales_invoices_change trigger does not exist yet, running migration without disabling triggers';
    -- Try migration anyway (table exists but trigger doesn't)
    update sales_invoices
    set net_amount = total - iva_amount
    where net_amount = 0 and total > 0;
    
    update sales_invoices
    set tax_treatment = case 
      when iva_amount > 0 then 'tax_included'
      else 'no_tax'
    end
    where tax_treatment = 'no_tax' and total > 0;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sales_invoices'
      and t.tgname = 'trg_sales_invoices_updated_at'
  ) then
    create trigger trg_sales_invoices_updated_at
      before update on sales_invoices
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_sales_invoices_customer_id
  on sales_invoices(customer_id);

alter table public.sales_invoices
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0,
  add column if not exists discount_amount numeric(12,2) not null default 0;

-- Add source tracking for sales invoices (for stock movements)
alter table public.sales_invoices
  add column if not exists source text check (source in ('pos', 'manual_sale', 'ecommerce', 'mechanic_job'));

-- Add created_by tracking for audit trail
alter table public.sales_invoices
  add column if not exists created_by uuid references auth.users(id);

-- Function to auto-populate created_by on INSERT
create or replace function set_created_by()
returns trigger as $$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$$ language plpgsql security definer;

-- Trigger to auto-populate created_by for sales_invoices
drop trigger if exists trg_sales_invoices_set_created_by on sales_invoices;
create trigger trg_sales_invoices_set_created_by
  before insert on sales_invoices
  for each row
  execute function set_created_by();

do $$
begin
  begin
    alter table public.sales_invoices
      drop constraint if exists sales_invoices_status_check;
  exception when others then
    null;
  end;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.sales_invoices'::regclass
       and conname = 'sales_invoices_status_check'
  ) then
    alter table public.sales_invoices
      add constraint sales_invoices_status_check
        check (lower(status) = any (array[
          'draft','borrador',
          'sent','enviado','enviada','emitido','emitida','issued',
          'confirmed','confirmado','confirmada',
          'paid','pagado','pagada',
          'overdue','vencido','vencida',
          'cancelled','cancelado','cancelada','anulado','anulada'
        ]));
  end if;
end $$;

-- ============================================================================
-- PAYMENT METHODS TABLE (Dynamic, UI-Configurable)
-- ============================================================================
-- This table allows flexible payment method configuration without code changes.
-- Each payment method is wired to a specific accounting account.
-- Users can add new methods via UI (e.g., "Transferencia BCI", "Transferencia Santander")

create table if not exists payment_methods (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  code text not null,
  name text not null,
  account_id uuid not null,
  requires_reference boolean not null default false,
  default_tax_treatment text not null default 'no_tax' check (default_tax_treatment in ('no_tax', 'tax_included')),
  icon text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, code), -- Each tenant has their own payment methods
  unique(tenant_id, id) -- Enable composite FK references (multi-tenant isolation)
);

-- Add composite FK for payment_methods.account_id (tenant-scoped)
do $$ begin
  alter table payment_methods drop constraint if exists payment_methods_account_id_fkey;
  alter table payment_methods add constraint payment_methods_account_id_fkey
    foreign key (tenant_id, account_id) references accounts(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  payment_methods.account_id FK: %', sqlerrm;
end $$;

do $$ begin
  create index if not exists idx_payment_methods_tenant on payment_methods(tenant_id);
  create index if not exists idx_payment_methods_code on payment_methods(tenant_id, code);
exception
  when undefined_table then raise notice '⚠ Table payment_methods does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in payment_methods';
end $$;
create index if not exists idx_payment_methods_sort_order on payment_methods(sort_order);
create index if not exists idx_payment_methods_account_id on payment_methods(account_id);

-- ============================================================================
-- JOB STATUSES TABLE (Dynamic, UI-Configurable - Notion-style)
-- ============================================================================
-- Custom statuses for mechanic jobs (pegas), fully customizable per tenant.
-- Users can create, edit, delete, reorder statuses with custom names and colors.
-- Grouped by phase: todo (not started), in_progress, complete

create table if not exists job_statuses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  code text not null, -- Internal code for backwards compatibility (e.g., 'PENDIENTE')
  color text not null default '#6B7280', -- Hex color (gray default)
  phase text not null default 'in_progress'
    check (phase in ('todo', 'in_progress', 'complete')),
  sort_order integer not null default 0,
  is_system boolean not null default false, -- System statuses can't be deleted
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, code), -- Each tenant has unique codes
  unique(tenant_id, id) -- Enable composite FK references (multi-tenant isolation)
);

do $$ begin
  create index if not exists idx_job_statuses_tenant on job_statuses(tenant_id);
  create index if not exists idx_job_statuses_code on job_statuses(tenant_id, code);
  create index if not exists idx_job_statuses_phase on job_statuses(tenant_id, phase);
  create index if not exists idx_job_statuses_sort on job_statuses(tenant_id, sort_order);
exception
  when undefined_table then raise notice '⚠ Table job_statuses does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in job_statuses';
end $$;

-- RLS policies for job_statuses
alter table job_statuses enable row level security;

drop policy if exists "job_statuses_select" on job_statuses;
drop policy if exists "job_statuses_insert" on job_statuses;
drop policy if exists "job_statuses_update" on job_statuses;
drop policy if exists "job_statuses_delete" on job_statuses;

create policy "job_statuses_select" on job_statuses
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "job_statuses_insert" on job_statuses
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "job_statuses_update" on job_statuses
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "job_statuses_delete" on job_statuses
  for delete to authenticated
  using (tenant_id = public.user_tenant_id() and is_system = false); -- Can't delete system statuses

-- Add status_id column to mechanic_jobs (migration)
alter table mechanic_jobs add column if not exists status_id uuid;

-- Add foreign key constraint after table exists
do $$ begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'mechanic_jobs_status_id_fkey'
  ) then
    alter table mechanic_jobs add constraint mechanic_jobs_status_id_fkey
      foreign key (tenant_id, status_id) references job_statuses(tenant_id, id) on delete set null;
    raise notice '✅ Added mechanic_jobs.status_id foreign key';
  end if;
exception
  when others then raise notice '⚠️ mechanic_jobs.status_id FK: %', sqlerrm;
end $$;

create index if not exists idx_mechanic_jobs_status_id on mechanic_jobs(status_id);

-- ============================================================================
-- 🏗️ MULTI-TENANT ONBOARDING SYSTEM - FOUNDATION DATA SEEDING
-- ============================================================================
-- This section contains ALL functions for automatic tenant initialization.
-- 
-- ARCHITECTURE OVERVIEW:
-- ----------------------
-- 1. User signs up → auth.users INSERT
-- 2. Trigger: on_auth_user_created (line ~11338)
--    └─> Calls: handle_new_user() (line ~11221)
--        ├─> If invited: Joins existing tenant
--        └─> If new: Creates tenant → tenants INSERT
-- 3. Trigger: trg_tenant_initialization (line ~2087)
--    └─> Calls: handle_new_tenant() (line ~2056)
--        ├─> seed_chart_of_accounts() - 30 standard accounts
--        ├─> seed_payment_methods_for_tenant() - 4 payment methods + 2 accounts
--        ├─> seed_company_settings() - 8 default settings
--        └─> seed_website_settings() - 7 e-commerce defaults
--
-- RESULT: New tenant is 100% ready to use with accounting, payments, settings configured.
--
-- MANUAL SEEDING (for existing tenants created before this system):
-- DO $$
-- DECLARE tenant_rec RECORD;
-- BEGIN
--   FOR tenant_rec IN SELECT id FROM tenants LOOP
--     PERFORM public.seed_chart_of_accounts(tenant_rec.id);
--     PERFORM public.seed_payment_methods_for_tenant(tenant_rec.id);
--     PERFORM public.seed_company_settings(tenant_rec.id);
--     PERFORM public.seed_website_settings(tenant_rec.id);
--   END LOOP;
-- END $$;
-- ============================================================================

-- ============================================================================
-- SEED DEFAULT PAYMENT METHODS FOR A TENANT
-- ============================================================================
-- Creates 4 payment methods: Efectivo, Transferencia, Cheque, Tarjeta
-- Also creates 2 accounts if missing: 1101 Caja, 1110 Bancos
-- Called automatically by handle_new_tenant() trigger
drop function if exists public.seed_payment_methods_for_tenant(uuid);

create or replace function public.seed_payment_methods_for_tenant(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_account_id uuid;
  v_bank_account_id uuid;
  v_count int;
begin
  -- Disable RLS temporarily for this function
  perform set_config('request.jwt.claim.sub', p_tenant_id::text, true);
  
  -- Find or create cash account (1101 - Caja)
  select id into v_cash_account_id
  from accounts
  where tenant_id = p_tenant_id
    and code = '1101'
  limit 1;

  if v_cash_account_id is null then
    insert into accounts (tenant_id, code, name, type, category, is_active)
    values (p_tenant_id, '1101', 'Caja', 'asset', 'currentAsset', true)
    returning id into v_cash_account_id;
    raise notice 'Created cash account: %', v_cash_account_id;
  else
    raise notice 'Found existing cash account: %', v_cash_account_id;
  end if;

  -- Find or create bank account (1110 - Banco)
  select id into v_bank_account_id
  from accounts
  where tenant_id = p_tenant_id
    and code = '1110'
  limit 1;

  if v_bank_account_id is null then
    insert into accounts (tenant_id, code, name, type, category, is_active)
    values (p_tenant_id, '1110', 'Banco', 'asset', 'currentAsset', true)
    returning id into v_bank_account_id;
    raise notice 'Created bank account: %', v_bank_account_id;
  else
    raise notice 'Found existing bank account: %', v_bank_account_id;
  end if;

  -- Insert default payment methods (only if they don't exist)
  -- CRITICAL: Use lowercase codes to match Flutter POS expectations
  v_count := 0;
  
  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'cash') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'cash', 'Efectivo', v_cash_account_id, false, 'no_tax', 'cash', 1, true);
    v_count := v_count + 1;
    raise notice 'Created payment method: Efectivo';
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'transfer') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'transfer', 'Transferencia', v_bank_account_id, true, 'no_tax', 'bank', 2, true);
    v_count := v_count + 1;
    raise notice 'Created payment method: Transferencia';
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'check') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'check', 'Cheque', v_bank_account_id, true, 'no_tax', 'receipt', 3, true);
    v_count := v_count + 1;
    raise notice 'Created payment method: Cheque';
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'card') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'card', 'Tarjeta de Crédito/Débito', v_bank_account_id, false, 'tax_included', 'credit_card', 4, true);
    v_count := v_count + 1;
    raise notice 'Created payment method: Tarjeta';
  end if;

  -- MercadoPago with IVA (tax_included) - for online payments
  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'mercadopago') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'mercadopago', 'MercadoPago', v_bank_account_id, true, 'tax_included', 'payment', 5, true);
    v_count := v_count + 1;
    raise notice 'Created payment method: MercadoPago';
  end if;

  return format('✓ Created %s payment methods for tenant %s', v_count, p_tenant_id);
end;
$$;

-- ============================================================================
-- SEED JOB STATUSES FOR A TENANT (Notion-style custom statuses)
-- ============================================================================
-- Creates default job statuses matching the original enum but as customizable records.
-- Users can add, edit, delete (non-system) statuses via UI.
-- Grouped by phase: todo (waiting), in_progress (active work), complete (finished)
-- Called automatically by handle_new_tenant() trigger
drop function if exists public.seed_job_statuses_for_tenant(uuid);

create or replace function public.seed_job_statuses_for_tenant(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  -- Phase: TODO (not started yet)
  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'PENDIENTE') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'PENDIENTE', 'Pendiente', '#6B7280', 'todo', 1, true);
    v_count := v_count + 1;
  end if;

  -- Phase: IN_PROGRESS (active work)
  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'DIAGNOSTICO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'DIAGNOSTICO', 'Diagnóstico', '#3B82F6', 'in_progress', 2, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'ESPERANDO_APROBACION') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'ESPERANDO_APROBACION', 'Esperando Aprobación', '#F59E0B', 'in_progress', 3, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'ESPERANDO_REPUESTOS') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'ESPERANDO_REPUESTOS', 'Esperando Repuestos', '#F97316', 'in_progress', 4, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'EN_CURSO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'EN_CURSO', 'En Curso', '#8B5CF6', 'in_progress', 5, true);
    v_count := v_count + 1;
  end if;

  -- Phase: COMPLETE (finished)
  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'FINALIZADO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'FINALIZADO', 'Finalizado', '#10B981', 'complete', 6, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'ENTREGADO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'ENTREGADO', 'Entregado', '#06B6D4', 'complete', 7, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'CANCELADO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'CANCELADO', 'Cancelado', '#EF4444', 'complete', 8, true);
    v_count := v_count + 1;
  end if;

  raise notice '✓ Created % job statuses for tenant %', v_count, p_tenant_id;
  return format('✓ Created %s job statuses for tenant %s', v_count, p_tenant_id);
end;
$$;

-- ============================================================================
-- MIGRATE EXISTING MECHANIC_JOBS TO USE STATUS_ID
-- ============================================================================
-- This function links existing jobs (using text status) to the new job_statuses table
-- Run this AFTER seeding job_statuses for all tenants
drop function if exists public.migrate_job_statuses();

create or replace function public.migrate_job_statuses()
returns text
language plpgsql
security definer
as $$
declare
  v_count int := 0;
  v_job record;
  v_status_id uuid;
begin
  -- First, seed job statuses for all existing tenants that don't have them
  for v_job in (select distinct tenant_id from mechanic_jobs) loop
    perform public.seed_job_statuses_for_tenant(v_job.tenant_id);
  end loop;

  -- Now update all mechanic_jobs to set status_id based on status text
  for v_job in (
    select id, tenant_id, status from mechanic_jobs where status_id is null
  ) loop
    select id into v_status_id
    from job_statuses
    where tenant_id = v_job.tenant_id
      and code = v_job.status
    limit 1;

    if v_status_id is not null then
      update mechanic_jobs set status_id = v_status_id where id = v_job.id;
      v_count := v_count + 1;
    end if;
  end loop;

  return format('✓ Migrated %s jobs to use status_id', v_count);
end;
$$;

-- Run migration automatically
select public.migrate_job_statuses();

-- ============================================================================
-- SEED CHART OF ACCOUNTS FOR A TENANT
-- ============================================================================
-- Creates 30 Chilean standard accounts for bikeshop operations
-- Includes: Assets, Liabilities, Equity, Income, Expenses, Tax (IVA 19%)
-- Based on Chilean GAAP and typical bikeshop business requirements
-- Called automatically by handle_new_tenant() trigger
drop function if exists public.seed_chart_of_accounts(uuid);

create or replace function public.seed_chart_of_accounts(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  raise notice 'Seeding chart of accounts for tenant %', p_tenant_id;
  
  -- Insert standard accounts for Chilean bikeshop operations
  -- Only insert if they don't already exist (idempotent)
  
  -- ASSETS
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '1101', 'Caja General', 'asset', 'currentAsset', 
    'Efectivo disponible en caja y fondos inmediatos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '1101');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '1110', 'Bancos - Cuenta Corriente', 'asset', 'currentAsset',
    'Saldos disponibles en cuentas corrientes bancarias', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '1110');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '1130', 'Cuentas por Cobrar Comerciales', 'asset', 'currentAsset',
    'Saldos pendientes de cobro a clientes por ventas a crédito', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '1130');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '1105', 'Inventario de Productos', 'asset', 'currentAsset',
    'Valor de productos y repuestos en stock', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '1105');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '1190', 'Otros Activos Corrientes', 'asset', 'currentAsset',
    'Activos circulantes no clasificados en otra cuenta específica', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '1190');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- LIABILITIES
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '2101', 'Cuentas por Pagar Comerciales', 'liability', 'currentLiability',
    'Saldos pendientes de pago a proveedores', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '2101');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- TAX ACCOUNTS (Critical for Chilean IVA)
  -- IVA Débito = LIABILITY (tax we owe to government from sales)
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '2150', 'IVA Débito Fiscal', 'liability', 'currentLiability',
    'IVA recaudado en ventas (19%)', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '2150');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- IVA Crédito = ASSET (tax refund we're owed from purchases)
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '2120', 'IVA Crédito Fiscal', 'asset', 'currentAsset',
    'IVA pagado en compras (19%)', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '2120');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability',
    'Obligaciones por gastos operacionales', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '2105');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- SUELDOS POR PAGAR (Salaries Payable - for payroll)
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '2106', 'Sueldos por Pagar', 'liability', 'currentLiability',
    'Obligaciones pendientes de pago por remuneraciones al personal', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '2106');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- EQUITY
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '3101', 'Capital Social', 'equity', 'capital',
    'Aporte inicial de los socios', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '3101');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '3201', 'Utilidades Retenidas', 'equity', 'retainedEarnings',
    'Ganancias acumuladas de periodos anteriores', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '3201');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- INCOME
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '4100', 'Ventas de Productos', 'income', 'operatingIncome',
    'Ingresos por venta de bicicletas, repuestos y accesorios', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '4100');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '4102', 'Servicios de Mantenimiento', 'income', 'operatingIncome',
    'Ingresos por servicios de reparación y mantención', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '4102');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '4201', 'Otros Ingresos', 'income', 'nonOperatingIncome',
    'Ingresos no operacionales', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '4201');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- EXPENSES - Cost of Goods Sold
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '5100', 'Costo de Ventas', 'expense', 'costOfGoodsSold',
    'Costo directo de productos vendidos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '5100');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- EXPENSES - Personnel
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6101', 'Sueldos y Salarios', 'expense', 'operatingExpense',
    'Remuneraciones del personal y pagos de nómina', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6101');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6102', 'Cotizaciones Previsionales', 'expense', 'operatingExpense',
    'Aportes previsionales, salud y seguros del personal', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6102');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6103', 'Honorarios Profesionales', 'expense', 'operatingExpense',
    'Servicios profesionales externos y consultorías', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6103');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- EXPENSES - Facilities
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6201', 'Arriendo de Locales', 'expense', 'operatingExpense',
    'Pagos de arriendo de oficinas, locales y bodegas', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6201');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6202', 'Servicios Básicos', 'expense', 'operatingExpense',
    'Electricidad, agua, gas y otros servicios básicos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6202');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6203', 'Telefonía e Internet', 'expense', 'operatingExpense',
    'Planes de telefonía fija, móvil y servicios de internet', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6203');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6204', 'Mantención y Reparaciones', 'expense', 'operatingExpense',
    'Mantenimiento de infraestructura y equipos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6204');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6205', 'Suministros de Oficina', 'expense', 'operatingExpense',
    'Materiales de oficina, papelería e insumos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6205');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- EXPENSES - Marketing
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6301', 'Marketing y Publicidad', 'expense', 'operatingExpense',
    'Campañas de marketing, publicidad y promoción', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6301');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6302', 'Comisiones de Venta', 'expense', 'operatingExpense',
    'Comisiones pagadas a vendedores', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6302');
  v_count := v_count + (case when found then 1 else 0 end);
  
  -- EXPENSES - Other
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6401', 'Gastos de Viaje', 'expense', 'operatingExpense',
    'Traslados, alojamiento y viáticos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6401');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6501', 'Seguros', 'expense', 'operatingExpense',
    'Primas de seguros patrimoniales y de responsabilidad', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6501');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6502', 'Patentes y Contribuciones', 'expense', 'taxExpense',
    'Patentes municipales y contribuciones', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6502');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6601', 'Gastos Financieros', 'expense', 'financialExpense',
    'Intereses de créditos y comisiones bancarias', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6601');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6701', 'Depreciación', 'expense', 'operatingExpense',
    'Depreciación de activos fijos', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6701');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into accounts (tenant_id, code, name, type, category, description, is_active)
  select p_tenant_id, '6801', 'Gastos Varios', 'expense', 'operatingExpense',
    'Gastos menores no clasificados', true
  where not exists (select 1 from accounts where tenant_id = p_tenant_id and code = '6801');
  v_count := v_count + (case when found then 1 else 0 end);
  
  raise notice '✓ Created % accounts for tenant %', v_count, p_tenant_id;
  return format('✓ Created %s accounts for tenant %s', v_count, p_tenant_id);
end;
$$;

-- ============================================================================
-- SEED COMPANY SETTINGS FOR A TENANT
-- ============================================================================
-- Creates 8 default settings: tax_rate_iva (19%), business_name, currency (CLP),
-- fiscal_year_start_month (1), invoice_prefix, purchase_prefix, enable_inventory
-- Called automatically by handle_new_tenant() trigger
drop function if exists public.seed_company_settings(uuid);

create or replace function public.seed_company_settings(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_name text;
  v_owner_email text;
  v_count int := 0;
begin
  raise notice 'Seeding company settings for tenant %', p_tenant_id;
  
  -- Get tenant info
  select shop_name, owner_email into v_shop_name, v_owner_email
  from tenants where id = p_tenant_id;
  
  -- Insert default settings (only if they don't exist)
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'tax_rate_iva', '19'
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'tax_rate_iva');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'business_name', coalesce(v_shop_name, 'Mi Tienda de Bicicletas')
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'business_name');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'contact_email', coalesce(v_owner_email, '')
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'contact_email');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'currency', 'CLP'
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'currency');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'fiscal_year_start_month', '1'
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'fiscal_year_start_month');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'invoice_prefix', 'FV-'
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'invoice_prefix');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'purchase_prefix', 'FC-'
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'purchase_prefix');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into company_settings (tenant_id, key, value)
  select p_tenant_id, 'enable_inventory', 'true'
  where not exists (select 1 from company_settings where tenant_id = p_tenant_id and key = 'enable_inventory');
  v_count := v_count + (case when found then 1 else 0 end);
  
  raise notice '✓ Created % company settings for tenant %', v_count, p_tenant_id;
  return format('✓ Created %s company settings for tenant %s', v_count, p_tenant_id);
end;
$$;

-- ============================================================================
-- SEED WEBSITE SETTINGS FOR A TENANT
-- ============================================================================
-- Creates 7 e-commerce defaults: site_title, site_description, contact_email,
-- enable_ecommerce (true), currency (CLP), shipping_enabled (false), theme
-- Called automatically by handle_new_tenant() trigger
drop function if exists public.seed_website_settings(uuid);

create or replace function public.seed_website_settings(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_name text;
  v_owner_email text;
  v_subdomain text;
  v_count int := 0;
begin
  raise notice 'Seeding website settings for tenant %', p_tenant_id;
  
  -- Get tenant info
  select shop_name, owner_email, subdomain into v_shop_name, v_owner_email, v_subdomain
  from tenants where id = p_tenant_id;
  
  -- Insert default website settings
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'site_title', coalesce(v_shop_name, 'Mi Tienda'), 'Título del sitio web'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'site_title');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'site_description', 'Venta y reparación de bicicletas', 'Descripción del sitio'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'site_description');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'contact_email', coalesce(v_owner_email, ''), 'Email de contacto'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'contact_email');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'enable_ecommerce', 'true', 'Habilitar tienda online'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'enable_ecommerce');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'currency', 'CLP', 'Moneda de la tienda'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'currency');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'shipping_enabled', 'false', 'Habilitar envíos'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'shipping_enabled');
  v_count := v_count + (case when found then 1 else 0 end);
  
  insert into website_settings (tenant_id, key, value, description)
  select p_tenant_id, 'theme', 'light', 'Tema visual del sitio'
  where not exists (select 1 from website_settings where tenant_id = p_tenant_id and key = 'theme');
  v_count := v_count + (case when found then 1 else 0 end);
  
  raise notice '✓ Created % website settings for tenant %', v_count, p_tenant_id;
  return format('✓ Created %s website settings for tenant %s', v_count, p_tenant_id);
end;
$$;

-- ============================================================================
-- AUTO-SEED ALL FOUNDATION DATA FOR NEW TENANTS (Complete Trigger)
-- ============================================================================
-- This is the master trigger that orchestrates all seeding functions
-- Ensures every new tenant gets a complete, production-ready environment

create or replace function public.handle_new_tenant()
returns trigger
language plpgsql
security definer
as $$
begin
  raise notice '🏗️ Initializing new tenant: % (ID: %)', NEW.shop_name, NEW.id;
  
  -- Seed chart of accounts (CRITICAL - must come first, needed by payment methods)
  perform public.seed_chart_of_accounts(NEW.id);
  raise notice '  ✓ Chart of accounts created';
  
  -- Seed payment methods (uses accounts created above)
  perform public.seed_payment_methods_for_tenant(NEW.id);
  raise notice '  ✓ Payment methods configured';
  
  -- Seed job statuses (Notion-style custom statuses for pegas)
  perform public.seed_job_statuses_for_tenant(NEW.id);
  raise notice '  ✓ Job statuses configured';
  
  -- Seed company settings
  perform public.seed_company_settings(NEW.id);
  raise notice '  ✓ Company settings initialized';
  
  -- Seed website settings
  perform public.seed_website_settings(NEW.id);
  raise notice '  ✓ Website settings initialized';
  
  -- Seed website pages and navigation (multi-page support)
  perform public.seed_website_pages(NEW.id);
  raise notice '  ✓ Website pages and navigation created';
  
  -- Seed job roles (employee-user linking system)
  perform public.seed_job_roles_for_tenant(NEW.id);
  raise notice '  ✓ Job roles catalog created';
  
  raise notice '✅ Tenant % fully initialized and ready for use!', NEW.shop_name;
  return NEW;
end;
$$;

-- Create trigger to auto-seed payment methods on tenant creation
drop trigger if exists trg_tenant_initialization on tenants;
create trigger trg_tenant_initialization
  after insert on tenants
  for each row
  execute function public.handle_new_tenant();

-- ============================================================================
-- MANUAL SEEDING FOR EXISTING TENANTS
-- ============================================================================
-- For existing tenants that were created before this trigger was added,
-- run this manually to seed their payment methods:
--
-- SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());
--
-- Or seed ALL existing tenants at once:
--
-- DO $$
-- DECLARE
--   tenant_record RECORD;
-- BEGIN
--   FOR tenant_record IN SELECT id FROM tenants LOOP
--     PERFORM public.seed_payment_methods_for_tenant(tenant_record.id);
--   END LOOP;
-- END $$;
-- ============================================================================

-- ============================================================================
-- SALES PAYMENTS TABLE (Updated to use payment_method_id)
-- ============================================================================
create table if not exists sales_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  invoice_id uuid not null references sales_invoices(id) on delete cascade,
  invoice_reference text,
  payment_method_id uuid not null,
  amount numeric(12,2) not null default 0,
  date timestamp with time zone not null default now(),
  reference text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add composite FK for sales_payments.payment_method_id (tenant-scoped)
do $$ begin
  alter table sales_payments drop constraint if exists sales_payments_payment_method_id_fkey;
  alter table sales_payments add constraint sales_payments_payment_method_id_fkey
    foreign key (tenant_id, payment_method_id) references payment_methods(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  sales_payments.payment_method_id FK: %', sqlerrm;
end $$;

-- Migration: Handle existing sales_payments with old 'method' column
-- CRITICAL: This must run BEFORE creating indexes on payment_method_id
do $$
declare
  v_has_method_column boolean;
  v_has_payment_method_id boolean;
  v_cash_method_id uuid;
begin
  -- Check if payment_method_id column already exists
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_payments'
      and column_name = 'payment_method_id'
  ) into v_has_payment_method_id;

  -- Check if old 'method' column exists
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_payments'
      and column_name = 'method'
  ) into v_has_method_column;

  if v_has_method_column and not v_has_payment_method_id then
    raise notice 'Migrating sales_payments from method column to payment_method_id...';
    
    -- Get cash payment method ID as default
    select id into v_cash_method_id from payment_methods where code = 'cash' limit 1;
    
    if v_cash_method_id is null then
      raise exception 'Cash payment method not found! Ensure payment_methods table is populated.';
    end if;
    
    -- Add new column (nullable first)
    alter table sales_payments add column payment_method_id uuid;
    
    -- Migrate data: map old method values to payment_method_id
    update sales_payments sp
    set payment_method_id = pm.id
    from payment_methods pm
    where sp.payment_method_id is null
      and (
        (sp.method = 'cash' and pm.code = 'cash') or
        (sp.method = 'transfer' and pm.code = 'transfer') or
        (sp.method = 'card' and pm.code = 'card') or
        (sp.method = 'check' and pm.code = 'check') or
        (sp.method = 'other' and pm.code = 'cash')  -- Default 'other' to cash
      );
    
    -- Set default for any remaining nulls
    update sales_payments
    set payment_method_id = v_cash_method_id
    where payment_method_id is null;
    
    -- Add composite foreign key constraint (tenant-scoped)
    alter table sales_payments 
      add constraint sales_payments_payment_method_id_fkey 
      foreign key (tenant_id, payment_method_id) 
      references payment_methods(tenant_id, id);
    
    -- Drop old method column and constraint
    alter table sales_payments drop constraint if exists sales_payments_method_check;
    alter table sales_payments drop column if exists method;
    
    -- Make payment_method_id NOT NULL
    alter table sales_payments alter column payment_method_id set not null;
    
    raise notice 'Migration complete!';
  elsif not v_has_payment_method_id then
    raise notice 'No existing sales_payments data, payment_method_id will be added by CREATE TABLE';
  else
    raise notice 'payment_method_id already exists, skipping migration';
  end if;
end $$;

create index if not exists idx_sales_payments_invoice_id
  on sales_payments(invoice_id);
create index if not exists idx_sales_payments_payment_method_id
  on sales_payments(payment_method_id);

alter table public.sales_payments
  add column if not exists invoice_reference text,
  add column if not exists notes text,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sales_payments'
      and t.tgname = 'trg_sales_payments_updated_at'
  ) then
    create trigger trg_sales_payments_updated_at
      before update on sales_payments
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create or replace function public.recalculate_sales_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status
    into v_invoice
    from public.sales_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select coalesce(sum(amount), 0)
    into v_total
    from public.sales_payments
   where invoice_id = p_invoice_id;

  v_balance := greatest(coalesce(v_invoice.total, 0) - v_total, 0);

  -- Determine new status based on payment totals and current status
  if v_invoice.status = 'cancelled' then
    -- Keep cancelled status
    v_new_status := v_invoice.status;
  elsif v_invoice.status = 'draft' then
    -- Draft stays draft unless fully paid
    if v_total >= coalesce(v_invoice.total, 0) and v_total > 0 then
      v_new_status := 'paid';
    else
      v_new_status := 'draft';
    end if;
  elsif v_total >= coalesce(v_invoice.total, 0) and v_total > 0 then
    -- Fully paid
    v_new_status := 'paid';
  elsif v_total > 0 and v_total < coalesce(v_invoice.total, 0) then
    -- Partially paid - keep current status if it's overdue, otherwise set to confirmed
    if v_invoice.status = 'overdue' then
      v_new_status := 'overdue';
    else
      v_new_status := 'confirmed';
    end if;
  elsif v_total = 0 then
    -- No payments
    if v_invoice.status = 'paid' then
      -- If was paid but now has no payments, revert to confirmed
      v_new_status := 'confirmed';
    else
      -- Otherwise keep current status (draft/sent/confirmed/overdue)
      v_new_status := v_invoice.status;
    end if;
  else
    -- Fallback: keep current status
    v_new_status := v_invoice.status;
  end if;

  update public.sales_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;

  -- SYNC: Update mechanic_jobs if this invoice is linked to a job
  perform public.sync_invoice_status_to_job(p_invoice_id);
end;
$$ language plpgsql;

create or replace function public.create_sales_payment_journal_entry(p_payment public.sales_payments)
returns void as $$
declare
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_receivable_account_id uuid;
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_description text;
  v_tenant_id uuid;
begin
  if p_payment.invoice_id is null then
    return;
  end if;

  -- Skip if payment is soft deleted
  if p_payment.deleted_at is not null then
    raise notice 'create_sales_payment_journal_entry: Payment % is deleted, skipping', p_payment.id;
    return;
  end if;

  v_tenant_id := p_payment.tenant_id;

  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_payment_journal_entry: No tenant_id on payment %, skipping', p_payment.id;
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_payments'
              and source_reference = p_payment.id::text
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         customer_name,
         total
    into v_invoice
    from public.sales_invoices
   where id = p_payment.invoice_id;

  if not found then
    return;
  end if;

  -- Get payment method and its associated account (DYNAMIC!)
  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = p_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', p_payment.id;
  end if;

  -- Use the account from payment method configuration
  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_description := format('Pago factura %s - %s', 
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(p_payment.date, now()),
    v_description,
    'payment',
    'sales_payments',
    v_invoice.invoice_number,
    'posted',
    p_payment.amount,
    p_payment.amount,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    format('Cobro a %s', coalesce(v_invoice.customer_name, 'Cliente')),
    p_payment.amount,
    0,
    now(),
    now()
  ), (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    format('Pago factura %s', coalesce(v_invoice.invoice_number, v_invoice.id::text)),
    0,
    p_payment.amount,
    now(),
    now()
  );
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.delete_sales_payment_journal_entry(p_payment_id uuid)
returns void as $$
begin
  if p_payment_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'sales_payments'
     and source_reference = p_payment_id::text;
end;
$$ language plpgsql security definer set search_path = public;

-- ============================================================================
-- PURCHASE PAYMENT JOURNAL ENTRY FUNCTIONS (Mirror sales payment pattern)
-- ============================================================================

create or replace function public.recalculate_purchase_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status,
         prepayment_model
    into v_invoice
    from public.purchase_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select coalesce(sum(amount), 0)
    into v_total
    from public.purchase_payments
   where invoice_id = p_invoice_id;

  v_balance := greatest(coalesce(v_invoice.total, 0) - v_total, 0);

  -- Status transition logic based on prepayment model
  -- Standard model: Draft→Sent→Confirmed→Received→Paid
  -- Prepayment model: Draft→Sent→Confirmed→Paid→Received
  
  if v_invoice.status = 'cancelled' then
    -- Cancelled invoices stay cancelled regardless of payments
    v_new_status := 'cancelled';
    
  elsif v_invoice.status IN ('draft', 'sent') then
    -- Pre-confirmation statuses: stay as-is regardless of payments
    v_new_status := v_invoice.status;
    
  elsif v_total >= coalesce(v_invoice.total, 0) then
    -- Fully paid
    v_new_status := 'paid';
    
  elsif v_total > 0 then
    -- Partially paid
    if v_invoice.prepayment_model then
      -- Prepayment model: partial payment keeps it at 'paid' if was paid/received
      if v_invoice.status IN ('paid', 'received') then
        v_new_status := 'paid';
      else
        v_new_status := 'confirmed';
      end if;
    else
      -- Standard model: partial payment keeps it at 'received' if was received/paid
      if v_invoice.status IN ('received', 'paid') then
        v_new_status := 'received';
      else
        v_new_status := 'confirmed';
      end if;
    end if;
    
  else
    -- No payments (v_total = 0): revert to previous status in workflow
    if v_invoice.prepayment_model then
      -- Prepayment model: Confirmed→Paid→Received
      if v_invoice.status IN ('paid', 'received') then
        -- If was paid or received, revert to confirmed (no payment means not paid yet)
        v_new_status := 'confirmed';
      else
        v_new_status := v_invoice.status;
      end if;
    else
      -- Standard model: Confirmed→Received→Paid
      if v_invoice.status = 'paid' then
        -- If was paid, revert to received (goods received but payment removed)
        v_new_status := 'received';
      else
        -- If at received/confirmed, stay there (never reached paid)
        v_new_status := v_invoice.status;
      end if;
    end if;
  end if;

  update public.purchase_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;
end;
$$ language plpgsql;

-- CRITICAL: Drop ALL versions of function to clear cached type definition
-- Drop old version with uuid parameter (if exists from previous schema)
drop function if exists public.create_purchase_payment_journal_entry(uuid) cascade;
drop function if exists public.create_purchase_payment_journal_entry(p_payment_id uuid) cascade;
-- Drop new version with composite type parameter
drop function if exists public.create_purchase_payment_journal_entry(public.purchase_payments) cascade;
drop function if exists public.create_purchase_payment_journal_entry(p_payment public.purchase_payments) cascade;

-- WORKAROUND: Use payment ID instead of composite type to avoid type cache issues
create or replace function public.create_purchase_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_payable_account_id uuid;
  v_payable_account_code text := '2101';
  v_payable_account_name text := 'Cuentas por Pagar Proveedores';
  v_description text;
  v_tenant_id uuid;
begin
  -- Fetch payment data from table instead of using composite type parameter
  select id, invoice_id, amount, date, payment_method_id, tenant_id
    into v_payment
    from public.purchase_payments
   where id = p_payment_id;

  if not found or v_payment.invoice_id is null then
    return;
  end if;

  v_tenant_id := v_payment.tenant_id;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'purchase_payments'
              and source_reference = v_payment.id::text
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         supplier_name,
         total
    into v_invoice
    from public.purchase_invoices
   where id = v_payment.invoice_id;

  if not found then
    return;
  end if;

  -- Get payment method and its associated account (DYNAMIC!)
  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = v_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', v_payment.id;
  end if;

  -- Use the account from payment method configuration
  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_payable_account_id := public.ensure_account(
    v_payable_account_code,
    v_payable_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    null
  );

  v_description := format('Pago factura compra %s - %s', 
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(v_payment.date, now()),
    v_description,
    'payment',
    'purchase_payments',
    v_invoice.invoice_number,
    'posted',
    v_payment.amount,
    v_payment.amount,
    now(),
    now()
  );

  -- DR: Accounts Payable (reduce liability)
  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_payable_account_id,
    v_payable_account_code,
    v_payable_account_name,
    v_description,
    v_payment.amount,
    0,
    now(),
    now()
  );

  -- CR: Cash/Bank account (reduce asset)
  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    v_description,
    0,
    v_payment.amount,
    now(),
    now()
  );
end;
$$;

create or replace function public.delete_purchase_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_payment_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'purchase_payments'
     and source_reference = p_payment_id::text;
end;
$$;

-- CRITICAL: Drop trigger FIRST, then function to clear cached type definition
-- Using CASCADE to ensure all dependencies are dropped
drop trigger if exists trg_purchase_payments_change on public.purchase_payments cascade;
drop function if exists public.handle_purchase_payment_change() cascade;

create or replace function public.handle_purchase_payment_change()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'UPDATE' then
    perform public.delete_purchase_payment_journal_entry(OLD.id);
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'DELETE' then
    perform public.delete_purchase_payment_journal_entry(OLD.id);
    perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
  end if;
  return NULL;
end;
$$ language plpgsql;

create or replace function public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_resolved_product_id uuid;
  v_quantity_int integer;
  v_status text;
  v_items_count integer;
begin
  -- CRITICAL: Set flag to skip stock_adjustment trigger for automatic changes
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  -- Early exit if invoice ID is null
  if p_invoice.id is null then
    raise notice 'consume_sales_invoice_inventory: invoice ID is null';
    return;
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  raise notice 'consume_sales_invoice_inventory: invoice %, status %', p_invoice.id, v_status;

  -- Only process if status is posted (not draft/cancelled)
  if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
    raise notice 'consume_sales_invoice_inventory: status is non-posted, skipping';
    return;
  end if;

  -- Check if inventory reduction already done
  v_reference := concat('sales_invoice:', p_invoice.id::text);
  if exists (
       select 1
         from public.stock_movements
        where reference = v_reference
          and type = 'OUT'
     ) then
    raise notice 'consume_sales_invoice_inventory: inventory already reduced for %', v_reference;
    return;
  end if;

  -- Count items
  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;
  
  raise notice 'consume_sales_invoice_inventory: processing % items', v_items_count;

  -- Process each item
  for v_item in
    select 
      (item->>'product_id')::uuid as product_id,
      (item->>'product_sku')::text as product_sku,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
  loop
    v_resolved_product_id := v_item.product_id;

    -- Try to resolve by SKU if product_id is null
    if v_resolved_product_id is null and v_item.product_sku is not null and v_item.product_sku != '' then
      select id
        into v_resolved_product_id
        from public.products
       where sku = v_item.product_sku
       limit 1;
      
      raise notice 'consume_sales_invoice_inventory: resolved product % by SKU %', v_resolved_product_id, v_item.product_sku;
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    if v_resolved_product_id is null then
      raise notice 'consume_sales_invoice_inventory: skipping item - product_id is null, sku: %', v_item.product_sku;
      continue;
    end if;

    if v_quantity_int <= 0 then
      raise notice 'consume_sales_invoice_inventory: skipping item - quantity <= 0, product: %', v_resolved_product_id;
      continue;
    end if;

    -- Reduce inventory (update BOTH inventory_qty and stock_quantity)
    update public.products
       set inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
           stock_quantity = greatest(coalesce(stock_quantity, 0) - v_quantity_int, 0),
           updated_at = now()
     where id = v_resolved_product_id
       and coalesce(is_service, false) = false;

    if found then
      raise notice 'consume_sales_invoice_inventory: reduced inventory for product % by %', v_resolved_product_id, v_quantity_int;
      
      -- Create stock movement record
      insert into public.stock_movements (
        id,
        product_id,
        warehouse_id,
        type,
        movement_type,
        quantity,
        reference,
        notes,
        date,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_resolved_product_id,
        null,
        'OUT',
        'sales_invoice',
        -v_quantity_int, -- Negative for OUT movements
        v_reference,
        format('Salida por factura %s', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)),
        coalesce(p_invoice.date, now()),
        now(),
        now()
      );
    else
      raise notice 'consume_sales_invoice_inventory: product % is a service or does not exist', v_resolved_product_id;
    end if;
  end loop;

  raise notice 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.restore_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_movement record;
  v_has_inventory_qty boolean := false;
  v_has_stock_quantity boolean := false;
  v_has_is_service boolean := false;
  v_has_track_stock boolean := false;
  v_has_updated_at boolean := false;
  v_update_assignments text := '';
  v_update_sql text;
  v_quantity_int integer;
begin
  if p_invoice.id is null then
    return;
  end if;

  v_reference := concat('sales_invoice:', p_invoice.id::text);

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'inventory_qty'
         )
    into v_has_inventory_qty;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'stock_quantity'
         )
    into v_has_stock_quantity;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'is_service'
         )
    into v_has_is_service;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'track_stock'
         )
    into v_has_track_stock;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'updated_at'
         )
    into v_has_updated_at;

  if not v_has_inventory_qty and not v_has_stock_quantity then
    delete from public.stock_movements
     where reference = v_reference;
    return;
  end if;

  if v_has_inventory_qty then
    v_update_assignments := v_update_assignments || 'inventory_qty = coalesce(inventory_qty, 0) + $1';
  end if;

  if v_has_stock_quantity then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'stock_quantity = coalesce(stock_quantity, 0) + $1';
  end if;

  if v_has_updated_at then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'updated_at = now()';
  end if;

  if v_update_assignments = '' then
    delete from public.stock_movements
     where reference = v_reference;
    return;
  end if;

  v_update_sql := 'update public.products set ' || v_update_assignments || ' where id = $2';

  if v_has_is_service then
    v_update_sql := v_update_sql || ' and coalesce(is_service, false) = false';
  end if;

  if v_has_track_stock then
    v_update_sql := v_update_sql || ' and coalesce(track_stock, true) = true';
  end if;

  for v_movement in
    select product_id, quantity
      from public.stock_movements
     where reference = v_reference
  loop
    if v_movement.product_id is null or v_movement.quantity = 0 then
      continue;
    end if;

    v_quantity_int := abs(coalesce(v_movement.quantity::int, 0));

    if v_quantity_int = 0 then
      continue;
    end if;

    execute v_update_sql using v_quantity_int, v_movement.product_id;
  end loop;

  delete from public.stock_movements
   where reference = v_reference;
end;
$$;

create or replace function public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_receivable_account_id uuid;
  v_revenue_account_code text := '4100';
  v_revenue_account_name text := 'Ingresos Operacionales';
  v_revenue_account_id uuid;
  v_iva_account_code text := '2150';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_iva_account_id uuid;
  v_inventory_account_code text := '1105';
  v_inventory_account_name text := 'Inventarios';
  v_inventory_account_id uuid;
  v_cogs_account_code text := '5100';
  v_cogs_account_name text := 'Costo de Ventas';
  v_cogs_account_id uuid;
  v_invoice_number text;
  v_customer_name text;
  v_description text;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
  v_total numeric(12,2);
  v_total_cost numeric(12,2);
  v_tenant_id uuid;
begin
  if p_invoice.id is null then
    return;
  end if;

  if coalesce(p_invoice.status, 'draft') in ('draft', 'cancelled') then
    return;
  end if;

  v_tenant_id := p_invoice.tenant_id;

  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_invoice_journal_entry: No tenant_id on invoice %, skipping', p_invoice.id;
    return;
  end if;

  -- Check for existing journal entry using invoice_number (consistent with INSERT)
  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_invoices'
              and source_reference = p_invoice.invoice_number
              and tenant_id = v_tenant_id
       )
    into v_exists;

  if v_exists then
    raise notice 'create_sales_invoice_journal_entry: Entry already exists for invoice %, skipping', p_invoice.invoice_number;
    return;
  end if;
  
  raise notice 'create_sales_invoice_journal_entry: Creating entry for invoice % (status: %)', p_invoice.invoice_number, p_invoice.status;

  -- ✅ CRITICAL: Use net_amount (tax-adjusted) if available, fallback to subtotal
  -- For tax_included invoices: net_amount = total ÷ 1.19, iva_amount = total - net_amount
  -- For no_tax invoices: net_amount = total, iva_amount = 0
  -- POS invoices may only have subtotal field populated, so fallback to it
  v_subtotal := coalesce(p_invoice.net_amount, p_invoice.subtotal, 0);
  v_iva := coalesce(p_invoice.iva_amount, 0);
  v_total := coalesce(p_invoice.total, v_subtotal + v_iva);

  if v_total = 0 then
    return;
  end if;

  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_tenant_id,
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_tenant_id,
    v_iva_account_code,
    v_iva_account_name,
    'liability',
    'currentLiability',
    'IVA generado en ventas',
    null
  );

  select coalesce(sum((item->>'cost')::numeric), 0)
    into v_total_cost
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
   where (item->>'cost') is not null
     and (item->>'cost') <> '';

  if v_total_cost > 0 then
    v_inventory_account_id := public.ensure_account(
      v_tenant_id,
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_tenant_id,
      v_cogs_account_code,
      v_cogs_account_name,
      'expense',
      'costOfGoodsSold',
      'Costo de ventas',
      null
    );
  end if;

  v_invoice_number := coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_customer_name := coalesce(nullif(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'sales',
    'sales_invoices',
    p_invoice.invoice_number,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    v_description,
    v_total,
    0,
    now(),
    now()
  );

  if v_subtotal <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_revenue_account_id,
      v_revenue_account_code,
      v_revenue_account_name,
      format('Ingreso por venta %s', v_invoice_number),
      0,
      v_subtotal,
      now(),
      now()
    );
  end if;

  if v_iva <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA débito factura %s', v_invoice_number),
      0,
      v_iva,
      now(),
      now()
    );
  end if;

  if v_total_cost > 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_cogs_account_id,
      v_cogs_account_code,
      v_cogs_account_name,
      format('Costo de ventas %s', v_invoice_number),
      v_total_cost,
      0,
      now(),
      now()
    ), (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_inventory_account_id,
      v_inventory_account_code,
      v_inventory_account_name,
      format('Salida inventario factura %s', v_invoice_number),
      0,
      v_total_cost,
      now(),
      now()
    );
  end if;
end;
$$;

create or replace function public.delete_sales_invoice_journal_entry(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invoice_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'sales_invoices'
     and source_reference = p_invoice_id::text;
end;
$$;

create or replace function public.handle_sales_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
  v_old_status text;
  v_new_status text;
  v_old_posted boolean;
  v_new_posted boolean;
begin
  raise notice 'handle_sales_invoice_change: TG_OP=%', TG_OP;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice 'handle_sales_invoice_change: trigger depth > 1, returning';
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    raise notice 'handle_sales_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- Only process if status is "confirmed" or "paid" (NOT "draft" or "sent")
    if not (v_new_status = any (v_non_posted)) then
      raise notice 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    end if;
    
    perform public.recalculate_sales_invoice_payments(NEW.id);
    -- SYNC: Update linked pega with invoice data
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    
    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      -- Both statuses are posted: restore old inventory, consume new
      raise notice 'handle_sales_invoice_change: both posted, restore and consume';
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      -- Changed from posted to non-posted: restore inventory
      raise notice 'handle_sales_invoice_change: changed to non-posted, restore only';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      -- Changed from non-posted to posted: consume inventory
      raise notice 'handle_sales_invoice_change: changed to posted, consume';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      -- Both non-posted: no inventory change
      raise notice 'handle_sales_invoice_change: both non-posted, no inventory change';
    end if;

    -- JOURNAL ENTRY HANDLING (DELETE-based reversals, Zoho Books style)
    if v_old_posted and not v_new_posted then
      -- Confirmed/Paid → Draft/Sent: DELETE journal entry
      raise notice 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
        
      -- Soft-delete associated payments
      raise notice 'handle_sales_invoice_change: reverting to non-posted, soft-deleting payments';
      update public.sales_payments 
      set deleted_at = now() 
      where invoice_id = OLD.id
        and deleted_at is null;
        
    elsif not v_old_posted and v_new_posted then
      -- Draft/Sent → Confirmed: CREATE journal entry
      raise notice 'handle_sales_invoice_change: changing to posted, creating journal entry';
      perform public.create_sales_invoice_journal_entry(NEW);
      
    elsif v_old_posted and v_new_posted then
      -- Both posted: delete old, create new (amounts might have changed)
      raise notice 'handle_sales_invoice_change: both posted, recreating journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      -- Both non-posted: no journal entry action
      raise notice 'handle_sales_invoice_change: both non-posted, no journal entry action';
    end if;
    
    perform public.recalculate_sales_invoice_payments(NEW.id);
    -- SYNC: Update linked pega with invoice changes
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice '🔵 handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- If was posted, restore inventory
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;
    
    -- DELETE invoice journal entry (using invoice_number as reference)
    delete from public.journal_entries
    where source_module = 'sales_invoices'
      and source_reference = OLD.invoice_number;
    
    -- DELETE all payment journal entries for this invoice
    delete from public.journal_entries
    where source_module = 'sales_payments'
      and source_reference = OLD.invoice_number;
    
    raise notice '🔵 handle_sales_invoice_change: DELETE completed, now cascade trigger should fire';
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  -- Drop and recreate trigger to ensure it uses latest function
  drop trigger if exists trg_sales_invoices_change on public.sales_invoices;
  
  create trigger trg_sales_invoices_change
    after insert or update or delete on public.sales_invoices
    for each row execute procedure public.handle_sales_invoice_change();
    
  raise notice 'Trigger trg_sales_invoices_change created successfully';
exception
  when others then
    raise notice 'Error creating trigger: %', SQLERRM;
end $$;

create or replace function public.handle_sales_payment_change()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    perform public.recalculate_sales_invoice_payments(NEW.invoice_id);
    perform public.create_sales_payment_journal_entry(NEW);
    return NEW;
  elsif TG_OP = 'UPDATE' then
    if NEW.invoice_id is distinct from OLD.invoice_id then
      perform public.recalculate_sales_invoice_payments(OLD.invoice_id);
    end if;
    perform public.delete_sales_payment_journal_entry(OLD.id);
    perform public.recalculate_sales_invoice_payments(NEW.invoice_id);
    perform public.create_sales_payment_journal_entry(NEW);
    return NEW;
  elsif TG_OP = 'DELETE' then
    perform public.delete_sales_payment_journal_entry(OLD.id);
    perform public.recalculate_sales_invoice_payments(OLD.invoice_id);
    return OLD;
  end if;
  return NULL;
end;
$$ language plpgsql;

do $$
begin
  if not exists (
    select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'sales_payments'
       and t.tgname = 'trg_sales_payments_change'
  ) then
    create trigger trg_sales_payments_change
      after insert or update or delete on public.sales_payments
      for each row execute procedure public.handle_sales_payment_change();
  end if;
end $$;

create table if not exists purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  invoice_number text not null,
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  supplier_rut text,
  date timestamp with time zone not null default now(),
  due_date timestamp with time zone,
  reference text,
  notes text,
  status text not null default 'draft'
    check (status in ('draft','sent','confirmed','received','paid','cancelled')),
  subtotal numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  balance numeric(12,2) not null default 0,
  prepayment_model boolean not null default false,
  items jsonb not null default '[]'::jsonb,
  additional_costs jsonb not null default '[]'::jsonb,
  sent_date timestamp with time zone,
  confirmed_date timestamp with time zone,
  received_date timestamp with time zone,
  paid_date timestamp with time zone,
  supplier_invoice_number text,
  supplier_invoice_date timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, invoice_number) -- Each tenant can have same invoice numbers
);

alter table public.purchase_invoices
  add column if not exists invoice_number text not null,
  add column if not exists supplier_id uuid references public.suppliers(id) on delete set null,
  add column if not exists supplier_name text,
  add column if not exists supplier_rut text,
  add column if not exists date timestamp with time zone not null default now(),
  add column if not exists due_date timestamp with time zone,
  add column if not exists reference text,
  add column if not exists notes text,
  add column if not exists status text not null default 'draft',
  add column if not exists subtotal numeric(12,2) not null default 0,
  add column if not exists tax numeric(12,2) not null default 0,
  add column if not exists total numeric(12,2) not null default 0,
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0,
  add column if not exists prepayment_model boolean not null default false,
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists additional_costs jsonb not null default '[]'::jsonb,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now(),
  add column if not exists tax numeric(12,2) not null default 0,
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists tax_treatment text not null default 'no_tax' check (tax_treatment in ('no_tax', 'tax_included')),
  add column if not exists net_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0,
  add column if not exists prepayment_model boolean not null default false,
  add column if not exists sent_date timestamp with time zone,
  add column if not exists confirmed_date timestamp with time zone,
  add column if not exists received_date timestamp with time zone,
  add column if not exists paid_date timestamp with time zone,
  add column if not exists supplier_invoice_number text,
  add column if not exists supplier_invoice_date timestamp with time zone;

-- Add created_by tracking for purchase invoices (for audit trail)
alter table public.purchase_invoices
  add column if not exists created_by uuid references auth.users(id);

-- Trigger to auto-populate created_by for purchase_invoices
drop trigger if exists trg_purchase_invoices_set_created_by on purchase_invoices;
create trigger trg_purchase_invoices_set_created_by
  before insert on purchase_invoices
  for each row
  execute function set_created_by();

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.purchase_invoices'::regclass
       and contype = 'c'
       and conname = 'purchase_invoices_status_check'
  ) then
    alter table public.purchase_invoices
      add constraint purchase_invoices_status_check
        check (status in ('draft','sent','confirmed','received','paid','cancelled'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'purchase_invoices'
      and t.tgname = 'trg_purchase_invoices_updated_at'
  ) then
    create trigger trg_purchase_invoices_updated_at
      before update on purchase_invoices
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_purchase_invoices_supplier_id
  on purchase_invoices(supplier_id);

-- Add comments for tax fields
comment on column purchase_invoices.tax_treatment is 'Indicates whether this purchase invoice includes IVA. tax_included = invoice with IVA (divide by 1.19 for net), no_tax = receipt or international purchase (full amount is cost). User controls per transaction.';
comment on column purchase_invoices.net_amount is 'Net amount before IVA. When tax_treatment=tax_included, this is total÷1.19. When tax_treatment=no_tax, this equals total.';

-- Migration: Calculate net_amount and set tax_treatment for existing records
do $$
begin
  -- CRITICAL: Disable triggers during migration to avoid journal entry creation without user context
  alter table purchase_invoices disable trigger trg_purchase_invoices_change;
  
  -- Calculate net_amount from existing tax column
  update purchase_invoices 
  set net_amount = total - tax 
  where net_amount = 0 and total > 0;
  
  -- Set tax_treatment based on existing tax column
  -- If tax > 0, assume it was a purchase with IVA included
  update purchase_invoices 
  set tax_treatment = case 
    when tax > 0 then 'tax_included' 
    else 'no_tax' 
  end 
  where tax_treatment = 'no_tax' and total > 0;
  
  -- Re-enable trigger
  alter table purchase_invoices enable trigger trg_purchase_invoices_change;
  
  raise notice 'Migrated % purchase invoices with tax data', (select count(*) from purchase_invoices where total > 0);
exception
  when undefined_table then
    raise notice 'purchase_invoices table does not exist yet, skipping migration';
  when undefined_object then
    raise notice 'trg_purchase_invoices_change trigger does not exist yet, running migration without disabling triggers';
    -- Try migration anyway (table exists but trigger doesn't)
    update purchase_invoices 
    set net_amount = total - tax 
    where net_amount = 0 and total > 0;
    
    update purchase_invoices 
    set tax_treatment = case 
      when tax > 0 then 'tax_included' 
      else 'no_tax' 
    end 
    where tax_treatment = 'no_tax' and total > 0;
end $$;

create index if not exists idx_purchase_invoices_date
  on purchase_invoices(date);

-- ============================================================================
-- STOCK MOVEMENTS VIEW - FINAL VERSION (Recreated after column additions)
-- ============================================================================
-- Strategy: Calculate BACKWARD from current stock
-- Most recent transaction: stock_after = products.stock_quantity
-- Previous transactions: work backwards subtracting quantities

-- Drop existing view first (needed when changing column structure)
drop view if exists stock_movements_view cascade;

create view stock_movements_view as
with all_movements as (
  -- 1. Purchase Invoices (IN)
  select 
    gen_random_uuid() as id,
    (item->>'product_id')::uuid as product_id,
    p.name as product_name,
    p.sku as product_sku,
    pi.date as transaction_date,
    'purchase' as movement_type,
    'manual_purchase' as source,
    pi.id as reference_id,
    pi.invoice_number as reference_number,
    ((item->>'quantity')::numeric)::integer as quantity, -- Positive
    pi.notes,
    pi.created_by,
    pi.created_at,
    pi.tenant_id
  from purchase_invoices pi,
       jsonb_array_elements(pi.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  where pi.status in ('received', 'paid')

  union all

  -- 2. Sales Invoices (OUT)
  select 
    gen_random_uuid() as id,
    (item->>'product_id')::uuid as product_id,
    p.name as product_name,
    p.sku as product_sku,
    si.date as transaction_date,
    'sale' as movement_type,
    coalesce(si.source, 'manual_sale') as source,
    si.id as reference_id,
    si.invoice_number as reference_number,
    -((item->>'quantity')::numeric)::integer as quantity, -- Negaive
    si.reference as notes,
    si.created_by,
    si.created_at,
    si.tenant_id
  from sales_invoices si,
       jsonb_array_elements(si.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  where si.status in ('confirmed', 'paid')

  union all

  -- 3. Mechanic Jobs (OUT) - UNINVOICED OR PENDING INVOICE
  -- Include Job if:
  --   a) No invoice linked (mj.invoice_id IS NULL)
  --   b) Invoice linked but NOT confirmed/paid (gap filling)
  select 
    mji.id,
    mji.product_id,
    coalesce(mji.product_name, p.name) as product_name,
    coalesce(mji.product_sku, p.sku) as product_sku,
    mj.created_at as transaction_date,
    'mechanic_job' as movement_type,
    'workshop' as source,
    mj.id as reference_id,
    mj.job_number as reference_number,
    -(mji.quantity)::integer as quantity, -- Negative
    mj.notes,
    null::uuid as created_by,
    mji.created_at,
    mj.tenant_id
  from mechanic_job_items mji
  join mechanic_jobs mj on mji.job_id = mj.id
  left join products p on mji.product_id = p.id
  left join sales_invoices si on mj.invoice_id = si.id -- Check invoice status
  where 
    -- Include if invoice not present OR present but filtered out of Sales block above
    (mj.invoice_id is null OR si.status not in ('confirmed', 'paid') OR si.id is null)
    and mj.status not in ('borrador', 'draft', 'cancelado', 'cancelled')
    and (mji.item_type = 'product' or mji.item_type is null)
    and mji.product_id is not null

  union all

  -- 4. Stock Adjustments (IN/OUT)
  select 
    sa.id,
    sa.product_id,
    p.name as product_name,
    p.sku as product_sku,
    sa.created_at as transaction_date,
    'adjustment' as movement_type,
    sa.adjustment_type as source,
    sa.id as reference_id,
    'ADJ-' || to_char(sa.created_at, 'YYYYMMDD-HH24MISS') as reference_number,
    sa.quantity, 
    sa.reason as notes,
    sa.created_by,
    sa.created_at,
    sa.tenant_id
  from stock_adjustments sa
  left join products p on sa.product_id = p.id
),
movements_with_running_stock as (
  select 
    m.*,
    p.stock_quantity as current_stock,
    -- Calculate stock_after by working backwards from current stock
    p.stock_quantity - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id 
        order by m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ), 
      0
    )::integer as calculated_stock_after
  from all_movements m
  left join products p on m.product_id = p.id
)
select 
  id,
  product_id,
  product_name,
  product_sku,
  transaction_date,
  movement_type,
  source,
  reference_id,
  reference_number,
  quantity,
  (calculated_stock_after - quantity)::integer as stock_before,
  calculated_stock_after as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

-- Ensure RLS is enabled
alter view stock_movements_view set (security_invoker = on);

create index if not exists idx_purchase_invoices_invoice_number
  on purchase_invoices(invoice_number);

-- ============================================================================
-- PURCHASE PAYMENTS TABLE (Uses payment_method_id for dynamic configuration)
-- ============================================================================
create table if not exists purchase_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  invoice_id uuid not null references purchase_invoices(id) on delete cascade,
  invoice_reference text,
  payment_method_id uuid not null,
  amount numeric(12,2) not null default 0,
  date timestamp with time zone not null default now(),
  reference text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add composite FK for purchase_payments.payment_method_id (tenant-scoped)
do $$ begin
  alter table purchase_payments drop constraint if exists purchase_payments_payment_method_id_fkey;
  alter table purchase_payments add constraint purchase_payments_payment_method_id_fkey
    foreign key (tenant_id, payment_method_id) references payment_methods(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  purchase_payments.payment_method_id FK: %', sqlerrm;
end $$;

-- Migration: Handle existing purchase_payments with old column names
-- CRITICAL: This must run BEFORE creating indexes
do $$
declare
  v_has_invoice_id boolean;
  v_has_old_invoice_id boolean;
  v_has_payment_method_id boolean;
  v_has_old_method boolean;
  v_has_date boolean;
  v_cash_method_id uuid;
begin
  -- Check if columns exist
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'invoice_id'
  ) into v_has_invoice_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'purchase_invoice_id'
  ) into v_has_old_invoice_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'payment_method_id'
  ) into v_has_payment_method_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name in ('method', 'payment_method')
  ) into v_has_old_method;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'date'
  ) into v_has_date;

  -- Add date column if missing
  if not v_has_date then
    raise notice 'Adding date column to purchase_payments...';
    alter table purchase_payments add column date timestamp with time zone not null default now();
  end if;

  -- Check for old payment_date column and migrate
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'payment_date'
  ) then
    raise notice 'Found old payment_date column, migrating to date...';
    -- Copy data if date is default and payment_date has real data
    update purchase_payments 
    set date = payment_date 
    where payment_date != date;
    -- Drop old column
    alter table purchase_payments drop column payment_date;
  end if;

  -- Check for old bank_account_id column and drop it
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'bank_account_id'
  ) then
    raise notice 'Found old bank_account_id column, dropping it (use payment_method_id instead)...';
    alter table purchase_payments drop column bank_account_id;
  end if;

  -- Migrate invoice_id column name
  if v_has_old_invoice_id and v_has_invoice_id then
    -- BOTH columns exist - this shouldn't happen, but let's fix it
    raise notice 'WARNING: Both purchase_invoice_id and invoice_id exist! Copying data and dropping old column...';
    -- Copy data from old column to new column if new is null
    update purchase_payments set invoice_id = purchase_invoice_id where invoice_id is null;
    -- Drop the old column
    alter table purchase_payments drop column purchase_invoice_id;
    v_has_old_invoice_id := false;
  elsif v_has_old_invoice_id and not v_has_invoice_id then
    raise notice 'Renaming purchase_invoice_id to invoice_id...';
    alter table purchase_payments rename column purchase_invoice_id to invoice_id;
    v_has_invoice_id := true;
  elsif not v_has_invoice_id then
    raise notice 'ERROR: Neither purchase_invoice_id nor invoice_id exists!';
  end if;

  -- Add invoice_id if it doesn't exist at all
  if not v_has_invoice_id then
    raise notice 'Adding invoice_id column to purchase_payments...';
    alter table purchase_payments add column invoice_id uuid not null references purchase_invoices(id) on delete cascade;
  end if;

  -- Migrate payment method column
  if v_has_old_method and not v_has_payment_method_id then
    raise notice 'Migrating purchase_payments payment method to payment_method_id...';
    
    -- Get cash payment method ID as default
    select id into v_cash_method_id from payment_methods where code = 'cash' limit 1;
    
    if v_cash_method_id is null then
      raise exception 'Cash payment method not found! Ensure payment_methods table is populated.';
    end if;
    
    -- Add new column (nullable first)
    alter table purchase_payments add column payment_method_id uuid;
    
    -- Try to migrate from 'method' column
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'purchase_payments'
        and column_name = 'method'
    ) then
      update purchase_payments pp
      set payment_method_id = pm.id
      from payment_methods pm
      where pp.payment_method_id is null
        and (
          (lower(pp.method) = 'cash' and pm.code = 'cash') or
          (lower(pp.method) in ('transfer', 'transferencia') and pm.code = 'transfer') or
          (lower(pp.method) in ('card', 'tarjeta') and pm.code = 'card') or
          (lower(pp.method) in ('check', 'cheque') and pm.code = 'check')
        );
      alter table purchase_payments drop column method;
    end if;

    -- Try to migrate from 'payment_method' column
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'purchase_payments'
        and column_name = 'payment_method'
    ) then
      update purchase_payments pp
      set payment_method_id = pm.id
      from payment_methods pm
      where pp.payment_method_id is null
        and (
          (lower(pp.payment_method) = 'cash' and pm.code = 'cash') or
          (lower(pp.payment_method) in ('transfer', 'transferencia') and pm.code = 'transfer') or
          (lower(pp.payment_method) in ('card', 'tarjeta') and pm.code = 'card') or
          (lower(pp.payment_method) in ('check', 'cheque') and pm.code = 'check')
        );
      alter table purchase_payments drop column payment_method;
    end if;
    
    -- Set default for any remaining nulls
    update purchase_payments
    set payment_method_id = v_cash_method_id
    where payment_method_id is null;
    
    -- Add composite foreign key constraint (tenant-scoped)
    alter table purchase_payments 
      add constraint purchase_payments_payment_method_id_fkey 
      foreign key (tenant_id, payment_method_id) 
      references payment_methods(tenant_id, id);
    
    -- Make payment_method_id NOT NULL
    alter table purchase_payments alter column payment_method_id set not null;
    
    raise notice 'Migration complete for purchase_payments!';
  elsif not v_has_payment_method_id then
    raise notice 'Adding payment_method_id to purchase_payments...';
    -- Add column without FK constraint (will be added separately via composite FK)
    alter table purchase_payments add column payment_method_id uuid not null;
  end if;

  raise notice 'purchase_payments migration check complete';
end $$;

create index if not exists idx_purchase_payments_invoice_id
  on purchase_payments(invoice_id);
create index if not exists idx_purchase_payments_payment_method_id
  on purchase_payments(payment_method_id);

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'purchase_payments'
      and t.tgname = 'trg_purchase_payments_updated_at'
  ) then
    create trigger trg_purchase_payments_updated_at
      before update on purchase_payments
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- Trigger already dropped and function recreated earlier (line ~1367)
-- Now just create the trigger with the refreshed function
create trigger trg_purchase_payments_change
  after insert or update or delete on public.purchase_payments
  for each row execute procedure public.handle_purchase_payment_change();

-- ============================================================================
-- EXPENSES MODULE - Professional Expense Management
-- ============================================================================

create sequence if not exists expense_number_seq;

-- Keep sequence in sync with existing data (prevents duplicate expense numbers).
do $$
declare
  v_max bigint;
begin
  select coalesce(
    max(
      (regexp_replace(expense_number, '^GTO-', ''))::bigint
    ),
    0
  )
  into v_max
  from public.expenses
  where expense_number ~ '^GTO-[0-9]+$';

  perform setval('expense_number_seq', v_max, true);
exception
  when undefined_table then null;
  when undefined_function then null;
  when others then
    raise notice '⚠️ expense_number_seq sync failed: %', sqlerrm;
end $$;

create table if not exists expense_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  description text,
  default_account_id uuid,
  default_tax_rate numeric(5,2) not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name) -- Each tenant has their own expense categories
);

-- Auto-category helpers (based on chart of accounts)
create or replace function public.get_expense_category_name_for_account(
  p_account_code text,
  p_account_name text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := coalesce(p_account_code, '');
  v_base_code text;
  v_name text := lower(coalesce(p_account_name, ''));
begin
  -- Support subaccounts like 6101-01
  v_base_code := regexp_replace(v_code, '-.*$', '');

  -- Prefer mapping by account code (stable)
  if v_base_code like '51%' then
    return 'Costo de Ventas';
  end if;

  if v_base_code like '610%' then
    return 'Nómina';
  end if;

  if v_base_code = '6201' then
    return 'Arriendo';
  elsif v_base_code = '6202' then
    return 'Servicios Básicos';
  elsif v_base_code = '6203' then
    return 'Telefonía e Internet';
  elsif v_base_code = '6204' then
    return 'Mantención y Reparaciones';
  elsif v_base_code = '6205' then
    return 'Suministros de Oficina';
  end if;

  if v_base_code = '6301' then
    return 'Marketing y Publicidad';
  elsif v_base_code = '6302' then
    return 'Comisiones de Venta';
  end if;

  if v_base_code = '6401' then
    return 'Gastos de Viaje';
  end if;

  if v_base_code = '6501' then
    return 'Seguros';
  elsif v_base_code = '6502' then
    return 'Patentes y Contribuciones';
  end if;

  if v_base_code = '6601' then
    return 'Gastos Financieros';
  end if;

  if v_base_code = '6701' then
    return 'Depreciación';
  end if;

  if v_base_code = '6801' then
    return 'Gastos Varios';
  end if;

  -- Fallback by name keywords (handles custom accounts)
  if v_name like '%nómina%' or v_name like '%nomina%' or v_name like '%sueldo%' or v_name like '%salario%' then
    return 'Nómina';
  end if;
  if v_name like '%arriendo%' then
    return 'Arriendo';
  end if;
  if v_name like '%internet%' or v_name like '%telefon%' then
    return 'Telefonía e Internet';
  end if;
  if v_name like '%luz%' or v_name like '%agua%' or v_name like '%gas%' or v_name like '%servicio básico%' or v_name like '%servicios básicos%' then
    return 'Servicios Básicos';
  end if;

  return 'Otros Gastos';
end;
$$;

create or replace function public.ensure_expense_category(
  p_tenant_id uuid,
  p_name text,
  p_description text,
  p_default_account_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id
    into v_id
    from public.expense_categories
   where tenant_id = p_tenant_id
     and lower(name) = lower(p_name)
   limit 1;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.expense_categories (
    tenant_id,
    name,
    description,
    default_account_id,
    default_tax_rate
  ) values (
    p_tenant_id,
    p_name,
    nullif(p_description, ''),
    p_default_account_id,
    0
  ) returning id into v_id;

  return v_id;
end;
$$;

-- Add composite FK for expense_categories.default_account_id (tenant-scoped)
do $$ begin
  alter table expense_categories drop constraint if exists expense_categories_default_account_id_fkey;
  alter table expense_categories add constraint expense_categories_default_account_id_fkey
    foreign key (tenant_id, default_account_id) references accounts(tenant_id, id) on delete set null;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  expense_categories.default_account_id FK: %', sqlerrm;
end $$;

do $$ begin
  create index if not exists idx_expense_categories_tenant on expense_categories(tenant_id);
  create index if not exists idx_expense_categories_name on expense_categories(tenant_id, lower(name));
exception
  when undefined_table then raise notice '⚠ Table expense_categories does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in expense_categories';
end $$;

create table if not exists expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  expense_number text not null,
  category_id uuid references expense_categories(id),
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  supplier_rut text,
  document_type text not null default 'invoice',
  document_number text,
  issue_date timestamp with time zone not null default now(),
  due_date timestamp with time zone,
  payment_terms text,
  currency text not null default 'CLP',
  exchange_rate numeric(12,6) not null default 1,
  posting_status text not null default 'draft'
    check (posting_status in ('draft','posted','void')),
  payment_status text not null default 'pending'
    check (payment_status in ('pending','scheduled','partial','paid','void')),
  subtotal numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  amount_paid numeric(14,2) not null default 0,
  balance numeric(14,2) not null default 0,
  notes text,
  reference text,
  approval_status text not null default 'pending'
    check (approval_status in ('pending','approved','rejected')),
  approved_by uuid references auth.users(id),
  approved_at timestamp with time zone,
  posted_at timestamp with time zone,
  paid_at timestamp with time zone,
  liability_account_id uuid,
  payment_account_id uuid,
  payment_method_id uuid,
  tags text[] default '{}',
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, expense_number) -- Each tenant can have same expense numbers
);

-- Add composite FKs for expenses (tenant-scoped)
do $$ begin
  -- liability_account_id -> accounts
  alter table expenses drop constraint if exists expenses_liability_account_id_fkey;
  alter table expenses add constraint expenses_liability_account_id_fkey
    foreign key (tenant_id, liability_account_id) references accounts(tenant_id, id) on delete restrict;
  
  -- payment_account_id -> accounts
  alter table expenses drop constraint if exists expenses_payment_account_id_fkey;
  alter table expenses add constraint expenses_payment_account_id_fkey
    foreign key (tenant_id, payment_account_id) references accounts(tenant_id, id) on delete restrict;
  
  -- payment_method_id -> payment_methods
  alter table expenses drop constraint if exists expenses_payment_method_id_fkey;
  alter table expenses add constraint expenses_payment_method_id_fkey
    foreign key (tenant_id, payment_method_id) references payment_methods(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  expenses FKs: %', sqlerrm;
end $$;

-- Drop old global unique constraint if it exists (migration from single-tenant)
do $$
begin
  if exists (
    select 1
    from information_schema.table_constraints
    where constraint_schema = 'public'
      and table_name = 'expenses'
      and constraint_name = 'expenses_expense_number_key'
  ) then
    alter table public.expenses drop constraint expenses_expense_number_key;
    raise notice 'Dropped old global unique constraint expenses_expense_number_key';
  end if;
end $$;

alter table public.expenses
  add column if not exists expense_number text,
  add column if not exists category_id uuid references public.expense_categories(id),
  add column if not exists supplier_id uuid references public.suppliers(id) on delete set null,
  add column if not exists supplier_name text,
  add column if not exists supplier_rut text,
  add column if not exists document_type text not null default 'invoice',
  add column if not exists document_number text,
  add column if not exists issue_date timestamp with time zone not null default now(),
  add column if not exists due_date timestamp with time zone,
  add column if not exists payment_terms text,
  add column if not exists currency text not null default 'CLP',
  add column if not exists exchange_rate numeric(12,6) not null default 1,
  add column if not exists posting_status text not null default 'draft',
  add column if not exists payment_status text not null default 'pending',
  add column if not exists subtotal numeric(14,2) not null default 0,
  add column if not exists tax_amount numeric(14,2) not null default 0,
  add column if not exists total_amount numeric(14,2) not null default 0,
  add column if not exists amount_paid numeric(14,2) not null default 0,
  add column if not exists balance numeric(14,2) not null default 0,
  add column if not exists notes text,
  add column if not exists reference text,
  add column if not exists approval_status text not null default 'pending',
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamp with time zone,
  add column if not exists posted_at timestamp with time zone,
  add column if not exists paid_at timestamp with time zone,
  add column if not exists liability_account_id uuid,
  add column if not exists payment_account_id uuid,
  add column if not exists payment_method_id uuid,
  add column if not exists tags text[] default '{}',
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'expenses'
       and column_name = 'expense_number'
       and is_nullable = 'YES'
  ) then
    alter table public.expenses
      alter column expense_number set not null;
  end if;

  -- Ensure tenant-scoped uniqueness (multi-tenant).
  -- Never re-add a global unique constraint on expense_number.
  if exists (
    select 1
      from information_schema.table_constraints
     where table_schema = 'public'
       and table_name = 'expenses'
       and constraint_type = 'UNIQUE'
       and constraint_name = 'expenses_expense_number_key'
  ) then
    alter table public.expenses drop constraint expenses_expense_number_key;
  end if;

  if not exists (
    select 1
      from pg_constraint c
     where c.conrelid = 'public.expenses'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(tenant_id, expense_number)%'
  ) then
    alter table public.expenses
      add constraint expenses_expense_number_tenant_key unique (tenant_id, expense_number);
  end if;

  if not exists (
    select 1
      from information_schema.check_constraints
     where constraint_schema = 'public'
       and constraint_name = 'expenses_posting_status_check'
  ) then
    alter table public.expenses
      add constraint expenses_posting_status_check
        check (posting_status in ('draft','posted','void'));
  end if;

  if not exists (
    select 1
      from information_schema.check_constraints
     where constraint_schema = 'public'
       and constraint_name = 'expenses_payment_status_check'
  ) then
    alter table public.expenses
      add constraint expenses_payment_status_check
        check (payment_status in ('pending','scheduled','partial','paid','void'));
  end if;
end $$;

create index if not exists idx_expenses_issue_date on expenses(issue_date);
create index if not exists idx_expenses_supplier_id on expenses(supplier_id);
create index if not exists idx_expenses_category_id on expenses(category_id);
create index if not exists idx_expenses_posting_status on expenses(posting_status);
create index if not exists idx_expenses_payment_status on expenses(payment_status);
create index if not exists idx_expenses_tenant on expenses(tenant_id);

-- RLS policies for expenses table
alter table expenses enable row level security;

drop policy if exists "expenses_select" on expenses;
drop policy if exists "expenses_insert" on expenses;
drop policy if exists "expenses_update" on expenses;
drop policy if exists "expenses_delete" on expenses;

create policy "expenses_select" on expenses
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expenses_insert" on expenses
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "expenses_update" on expenses
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expenses_delete" on expenses
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

create table if not exists expense_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  expense_id uuid not null references expenses(id) on delete cascade,
  line_index integer not null default 0,
  account_id uuid not null,
  account_code text not null,
  account_name text not null,
  description text,
  quantity numeric(12,4) not null default 1,
  unit_price numeric(14,4) not null default 0,
  subtotal numeric(14,2) not null default 0,
  tax_rate numeric(6,3) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  cost_center text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add composite FK for expense_lines.account_id (tenant-scoped)
do $$ begin
  alter table expense_lines drop constraint if exists expense_lines_account_id_fkey;
  alter table expense_lines add constraint expense_lines_account_id_fkey
    foreign key (tenant_id, account_id) references accounts(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  expense_lines.account_id FK: %', sqlerrm;
end $$;

create index if not exists idx_expense_lines_expense_id
  on expense_lines(expense_id);
create index if not exists idx_expense_lines_account_id
  on expense_lines(account_id);
create index if not exists idx_expense_lines_tenant on expense_lines(tenant_id);

-- RLS policies for expense_lines table
alter table expense_lines enable row level security;

drop policy if exists "expense_lines_select" on expense_lines;
drop policy if exists "expense_lines_insert" on expense_lines;
drop policy if exists "expense_lines_update" on expense_lines;
drop policy if exists "expense_lines_delete" on expense_lines;

create policy "expense_lines_select" on expense_lines
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_lines_insert" on expense_lines
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "expense_lines_update" on expense_lines
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_lines_delete" on expense_lines
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

create table if not exists expense_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  expense_id uuid not null references expenses(id) on delete cascade,
  payment_method_id uuid,
  payment_account_id uuid,
  amount numeric(14,2) not null default 0,
  payment_date timestamp with time zone not null default now(),
  reference text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add composite FKs for expense_payments (tenant-scoped)
do $$ begin
  -- payment_method_id -> payment_methods
  alter table expense_payments drop constraint if exists expense_payments_payment_method_id_fkey;
  alter table expense_payments add constraint expense_payments_payment_method_id_fkey
    foreign key (tenant_id, payment_method_id) references payment_methods(tenant_id, id) on delete restrict;
  
  -- payment_account_id -> accounts
  alter table expense_payments drop constraint if exists expense_payments_payment_account_id_fkey;
  alter table expense_payments add constraint expense_payments_payment_account_id_fkey
    foreign key (tenant_id, payment_account_id) references accounts(tenant_id, id) on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice '⚠️  expense_payments FKs: %', sqlerrm;
end $$;

create index if not exists idx_expense_payments_expense_id
  on expense_payments(expense_id);
create index if not exists idx_expense_payments_method
  on expense_payments(payment_method_id);

create table if not exists expense_attachments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  expense_id uuid not null references expenses(id) on delete cascade,
  file_name text not null,
  file_url text not null,
  file_type text,
  file_size integer,
  uploaded_by uuid references auth.users(id),
  uploaded_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_expense_attachments_tenant on expense_attachments(tenant_id);
  create index if not exists idx_expense_attachments_expense_id on expense_attachments(expense_id);
exception
  when undefined_table then raise notice '⚠ Table expense_attachments does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in expense_attachments';
end $$;

create or replace function public.generate_expense_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next bigint;
begin
  select nextval('expense_number_seq') into v_next;
  return format('GTO-%s', lpad(v_next::text, 5, '0'));
exception
  when others then
    raise notice 'generate_expense_number fallback due to %', SQLERRM;
    return concat('GTO-', lpad((extract(epoch from now())::bigint % 100000)::text, 5, '0'));
end;
$$;

create or replace function public.prepare_expense_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_posting text := lower(coalesce(NEW.posting_status, 'draft'));
  v_payment text := lower(coalesce(NEW.payment_status, 'pending'));
begin
  if TG_OP = 'INSERT' then
    if coalesce(NEW.expense_number, '') = '' then
      NEW.expense_number := public.generate_expense_number();
    end if;
    NEW.created_at := coalesce(NEW.created_at, now());
    if v_posting = 'posted' then
      NEW.posted_at := coalesce(NEW.posted_at, now());
    end if;
    if v_payment = 'paid' then
      NEW.paid_at := coalesce(NEW.paid_at, now());
    end if;
  elsif TG_OP = 'UPDATE' then
    if v_posting = 'posted' and lower(coalesce(OLD.posting_status, 'draft')) <> 'posted' then
      NEW.posted_at := coalesce(NEW.posted_at, now());
    elsif v_posting <> 'posted' then
      NEW.posted_at := null;
    end if;

    if v_payment = 'paid' and lower(coalesce(OLD.payment_status, 'pending')) <> 'paid' then
      NEW.paid_at := coalesce(NEW.paid_at, now());
    elsif v_payment <> 'paid' then
      NEW.paid_at := null;
    end if;
  end if;

  NEW.updated_at := now();
  return NEW;
end;
$$;

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expenses_prepare'
       and tgrelid = 'public.expenses'::regclass
  ) then
    create trigger trg_expenses_prepare
      before insert or update on public.expenses
      for each row execute procedure public.prepare_expense_record();
  end if;
end $$;

create or replace function public.prepare_expense_line()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_account record;
begin
  NEW.quantity := coalesce(NEW.quantity, 1);
  NEW.unit_price := coalesce(NEW.unit_price, 0);
  NEW.subtotal := round(NEW.quantity * NEW.unit_price, 2);
  NEW.tax_rate := coalesce(NEW.tax_rate, 0);

  -- If the client doesn't provide these fields, they often come in as default 0
  -- (because the columns are NOT NULL DEFAULT 0). Treat 0 as "unset" when the
  -- computed subtotal is > 0.
  if NEW.tax_amount is null or (NEW.tax_amount = 0 and NEW.tax_rate <> 0 and NEW.subtotal <> 0) then
    NEW.tax_amount := round((NEW.subtotal * NEW.tax_rate) / 100, 2);
  end if;

  if NEW.total is null or (NEW.total = 0 and NEW.subtotal <> 0) then
    NEW.total := NEW.subtotal + coalesce(NEW.tax_amount, 0);
  end if;

  if (NEW.account_code is null or NEW.account_name is null) and NEW.account_id is not null then
    select code, name
      into v_account
      from public.accounts
     where id = NEW.account_id;
    if found then
      NEW.account_code := coalesce(NEW.account_code, v_account.code);
      NEW.account_name := coalesce(NEW.account_name, v_account.name);
    end if;
  end if;

  if TG_OP = 'INSERT' then
    NEW.created_at := coalesce(NEW.created_at, now());
  end if;

  NEW.updated_at := now();
  return NEW;
end;
$$;

-- NOTE: handle_expense_line_change() is defined later at line ~3851
-- (removed duplicate definition here to avoid overwriting the correct version)

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expense_lines_prepare'
       and tgrelid = 'public.expense_lines'::regclass
  ) then
    create trigger trg_expense_lines_prepare
      before insert or update on public.expense_lines
      for each row execute procedure public.prepare_expense_line();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expense_lines_change'
       and tgrelid = 'public.expense_lines'::regclass
  ) then
    create trigger trg_expense_lines_change
      after insert or update or delete on public.expense_lines
      for each row execute procedure public.handle_expense_line_change();
  end if;
end $$;

create or replace function public.prepare_expense_payment()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.payment_date is null then
    NEW.payment_date := now();
  end if;

  if TG_OP = 'INSERT' then
    NEW.created_at := coalesce(NEW.created_at, now());
  end if;

  NEW.updated_at := now();
  return NEW;
end;
$$;

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expense_payments_prepare'
       and tgrelid = 'public.expense_payments'::regclass
  ) then
    create trigger trg_expense_payments_prepare
      before insert or update on public.expense_payments
      for each row execute procedure public.prepare_expense_payment();
  end if;
end $$;

create or replace function public.recalculate_expense_totals(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense record;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_paid numeric(14,2) := 0;
  v_payment_method_count integer := 0;
  v_payment_account_count integer := 0;
  v_single_payment_method_id uuid;
  v_single_payment_account_id uuid;
  v_category_id uuid;
  v_line_account_id uuid;
  v_line_account_code text;
  v_line_account_name text;
  v_category_name text;
  v_category_desc text;
  v_prev_payment text;
  v_new_payment text;
begin
  if p_expense_id is null then
    return;
  end if;

    select e.id,
      e.tenant_id,
      e.category_id,
         lower(coalesce(e.payment_status, 'pending')) as payment_status,
         lower(coalesce(e.posting_status, 'draft')) as posting_status,
         e.paid_at,
         e.payment_method_id,
      e.payment_account_id,
         e.amount_paid as current_amount_paid,
         e.balance as current_balance
    into v_expense
    from public.expenses e
   where e.id = p_expense_id
   for update;

  if not found then
    return;
  end if;

  select
      coalesce(sum(subtotal), 0),
      coalesce(sum(tax_amount), 0),
      coalesce(sum(total), 0)
    into v_subtotal, v_tax, v_total
    from public.expense_lines
   where expense_id = p_expense_id;

  select coalesce(sum(amount), 0)
    into v_paid
    from public.expense_payments
   where expense_id = p_expense_id;

  -- If payments exist, reflect the payment method/account in the header when unambiguous.
  -- This keeps list views informative (and avoids "Sin medio de pago" for paid expenses).
  if v_paid > 0 then
    select
      count(distinct ep.payment_method_id),
      (array_agg(distinct ep.payment_method_id))[1]
      into v_payment_method_count, v_single_payment_method_id
      from public.expense_payments ep
     where ep.expense_id = p_expense_id
       and coalesce(ep.amount, 0) > 0
       and ep.payment_method_id is not null;

    select
      count(distinct ep.payment_account_id),
      (array_agg(distinct ep.payment_account_id))[1]
      into v_payment_account_count, v_single_payment_account_id
      from public.expense_payments ep
     where ep.expense_id = p_expense_id
       and coalesce(ep.amount, 0) > 0
       and ep.payment_account_id is not null;
  end if;

  v_prev_payment := v_expense.payment_status;

  -- Auto-assign category from expense line account (never override manual category)
  v_category_id := v_expense.category_id;
  if v_category_id is null then
    select el.account_id,
           el.account_code,
           el.account_name
      into v_line_account_id,
           v_line_account_code,
           v_line_account_name
      from public.expense_lines el
     where el.expense_id = p_expense_id
     order by el.line_index asc, el.created_at asc
     limit 1;

    if v_line_account_id is not null then
      v_category_name := public.get_expense_category_name_for_account(
        v_line_account_code,
        v_line_account_name
      );
      v_category_desc := coalesce(v_line_account_name, v_category_name);

      v_category_id := public.ensure_expense_category(
        v_expense.tenant_id,
        v_category_name,
        v_category_desc,
        v_line_account_id
      );
    end if;
  end if;

  -- If already marked as paid with payment_method_id set (immediate payment on creation)
  -- and no separate payment records exist, respect that status
  if v_prev_payment = 'paid' 
     and v_expense.payment_method_id is not null 
     and v_paid = 0 
     and v_total > 0 then
    v_new_payment := 'paid';
    v_paid := v_total; -- Use total as paid amount
  elsif v_total = 0 then
    v_new_payment := v_prev_payment;
  elsif v_paid <= 0 then
    if v_prev_payment = 'scheduled' then
      v_new_payment := 'scheduled';
    else
      v_new_payment := 'pending';
    end if;
  elsif v_paid + 0.01 < v_total then
    v_new_payment := 'partial';
  else
    v_new_payment := 'paid';
  end if;

  update public.expenses
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total,
         amount_paid = v_paid,
         balance = greatest(v_total - v_paid, 0),
         category_id = coalesce(category_id, v_category_id),
         payment_method_id = case
           when v_payment_method_count = 1 and v_expense.payment_method_id is null
             then v_single_payment_method_id
           else payment_method_id
         end,
         payment_account_id = case
           when v_payment_account_count = 1 and v_expense.payment_account_id is null
             then v_single_payment_account_id
           else payment_account_id
         end,
         payment_status = case
           when v_expense.posting_status = 'void' then payment_status
           when v_prev_payment = 'void' then 'void'
           else v_new_payment
         end,
         paid_at = case
           when v_expense.posting_status <> 'void'
             and v_total > 0
             and v_paid + 0.01 >= v_total then coalesce(paid_at, now())
           when v_new_payment <> 'paid' then null
           else paid_at
         end,
         updated_at = now()
   where id = p_expense_id;
end;
$$;

create or replace function public.create_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_account_code text := '2105';
  v_liability_account_name text := 'Cuentas por Pagar - Gastos';
  v_tax_account_id uuid;
  v_tax_account_code text := '2120';
  v_tax_account_name text := 'IVA Crédito Fiscal';
  v_cash_account record;
  v_total numeric(14,2);
  v_tax_total numeric(14,2);
  v_credit_account_id uuid;
  v_credit_account_code text;
  v_credit_account_name text;
  v_description text;
  v_supplier text;
  v_document text;
  v_line record;
  v_line_count integer := 0;
  v_default_account record;
begin
  select e.*
    into v_expense
    from public.expenses e
   where e.id = p_expense_id;

  if not found then
    return;
  end if;

  if lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted' then
    return;
  end if;

  v_total := coalesce(v_expense.total_amount, 0);

  if v_total = 0 then
    return;
  end if;

  -- Delete existing journal entry if it exists (to recreate it fresh)
  select exists (
           select 1
             from public.journal_entries
            where source_module = 'expenses'
              and source_reference = v_expense.id::text
         )
    into v_exists;

  if v_exists then
    perform public.delete_expense_journal_entry(p_expense_id);
  end if;

  v_liability_account_id := coalesce(
    v_expense.liability_account_id,
    public.ensure_account(
      v_expense.tenant_id,
      v_liability_account_code,
      v_liability_account_name,
      'liability',
      'currentLiability',
      'Obligaciones por gastos pendientes de pago',
      null
    )
  );

  -- Ensure record has a known tuple structure even when no payment account/method is set
  select null::uuid as id, null::text as code, null::text as name
    into v_cash_account;

  if v_expense.payment_account_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.accounts a
     where a.id = v_expense.payment_account_id;
  elsif v_expense.payment_method_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.payment_methods pm
      join public.accounts a on a.id = pm.account_id
     where pm.id = v_expense.payment_method_id;
  end if;

  v_tax_account_id := public.ensure_account(
    v_expense.tenant_id,
    v_tax_account_code,
    v_tax_account_name,
    'asset',
    'currentAsset',
    'Crédito fiscal IVA soportado en compras',
    null
  );

  v_supplier := coalesce(nullif(v_expense.supplier_name, ''), 'Proveedor');
  v_document := coalesce(nullif(v_expense.document_number, ''), v_expense.expense_number);
  v_description := format('Gasto %s - %s', v_document, v_supplier);

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_expense.issue_date, now()),
    v_description,
    'purchase',
    'expenses',
    v_expense.expense_number,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  for v_line in
    select el.*
      from public.expense_lines el
     where el.expense_id = v_expense.id
     order by el.line_index, el.created_at
  loop
    v_line_count := v_line_count + 1;
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_expense.tenant_id,
      v_entry_id,
      v_line.account_id,
      v_line.account_code,
      v_line.account_name,
      coalesce(nullif(v_line.description, ''), v_description),
      coalesce(v_line.subtotal, 0),
      0,
      now(),
      now()
    );
  end loop;

  if v_line_count = 0 then
    if v_expense.category_id is not null then
      select a.id, a.code, a.name
        into v_default_account
        from public.expense_categories ec
        join public.accounts a on a.id = ec.default_account_id
       where ec.id = v_expense.category_id;
    end if;

    if not found or v_default_account.id is null then
      select public.ensure_account(
               v_expense.tenant_id,
               '5200',
               'Gastos Generales',
               'expense',
               'operatingExpense',
               'Gastos generales y administrativos',
               null
             ) as id,
             '5200' as code,
             'Gastos Generales' as name
        into v_default_account;
    end if;

    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_expense.tenant_id,
      v_entry_id,
      v_default_account.id,
      v_default_account.code,
      v_default_account.name,
      v_description,
      coalesce(v_expense.subtotal, v_total - coalesce(v_expense.tax_amount, 0)),
      0,
      now(),
      now()
    );
  end if;

  v_tax_total := coalesce(v_expense.tax_amount, 0);
  if v_tax_total <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_expense.tenant_id,
      v_entry_id,
      v_tax_account_id,
      v_tax_account_code,
      v_tax_account_name,
      format('IVA crédito gasto %s', v_document),
      v_tax_total,
      0,
      now(),
      now()
    );
  end if;

  if lower(coalesce(v_expense.payment_status, 'pending')) = 'paid'
     and coalesce(v_expense.balance, 0) <= 0.01
     and v_cash_account.id is not null then
    v_credit_account_id := v_cash_account.id;
    v_credit_account_code := v_cash_account.code;
    v_credit_account_name := v_cash_account.name;
  else
    v_credit_account_id := v_liability_account_id;
    select code, name
      into v_credit_account_code, v_credit_account_name
      from public.accounts
     where id = v_credit_account_id;
  end if;

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_expense.tenant_id,
    v_entry_id,
    v_credit_account_id,
    v_credit_account_code,
    v_credit_account_name,
    v_description,
    0,
    v_total,
    now(),
    now()
  );
end;
$$;

create or replace function public.delete_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_expense_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'expenses'
     and source_reference = p_expense_id::text;
end;
$$;

create or replace function public.create_expense_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_expense record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_code text := '2105';
  v_liability_name text := 'Cuentas por Pagar - Gastos';
  v_cash_account record;
  v_description text;
begin
  select ep.*
    into v_payment
    from public.expense_payments ep
   where ep.id = p_payment_id;

  if not found then
    return;
  end if;

  select e.*
    into v_expense
    from public.expenses e
   where e.id = v_payment.expense_id;

  if not found then
    return;
  end if;

  if lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted' then
    return;
  end if;

  if coalesce(v_payment.amount, 0) = 0 then
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'expense_payments'
              and source_reference = v_payment.id::text
         )
    into v_exists;

  if v_exists then
    return;
  end if;

  v_liability_account_id := coalesce(
    v_expense.liability_account_id,
    public.ensure_account(
      v_expense.tenant_id,
      v_liability_code,
      v_liability_name,
      'liability',
      'currentLiability',
      'Obligaciones por gastos pendientes de pago',
      null
    )
  );

  if v_payment.payment_account_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.accounts a
     where a.id = v_payment.payment_account_id;
  elsif v_payment.payment_method_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.payment_methods pm
      join public.accounts a on a.id = pm.account_id
     where pm.id = v_payment.payment_method_id;
  end if;

  if v_cash_account.id is null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.accounts a
     where a.code = '1101'
     limit 1;
  end if;

  v_description := format('Pago gasto %s', coalesce(v_expense.expense_number, v_expense.id::text));

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_payment.payment_date, now()),
    v_description,
    'payment',
    'expense_payments',
    v_expense.expense_number,
    'posted',
    v_payment.amount,
    v_payment.amount,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_expense.tenant_id,
    v_entry_id,
    v_liability_account_id,
    (select code from public.accounts where id = v_liability_account_id),
    (select name from public.accounts where id = v_liability_account_id),
    v_description,
    v_payment.amount,
    0,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_expense.tenant_id,
    v_entry_id,
    v_cash_account.id,
    v_cash_account.code,
    v_cash_account.name,
    v_description,
    0,
    v_payment.amount,
    now(),
    now()
  );
end;
$$;

create or replace function public.delete_expense_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_payment_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'expense_payments'
     and source_reference = p_payment_id::text;
end;
$$;

create or replace function public.process_expense_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_posted boolean := lower(coalesce(OLD.posting_status, 'draft')) = 'posted';
  v_new_posted boolean := lower(coalesce(NEW.posting_status, 'draft')) = 'posted';
begin
  if pg_trigger_depth() > 1 then
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    perform public.recalculate_expense_totals(NEW.id);
    -- Journal entry will be created by expense_lines trigger after lines are inserted
    return NEW;

  elsif TG_OP = 'UPDATE' then
    perform public.recalculate_expense_totals(NEW.id);

    if v_old_posted and not v_new_posted then
      perform public.delete_expense_journal_entry(OLD.id);
    elsif not v_old_posted and v_new_posted then
      perform public.create_expense_journal_entry(NEW.id);
    elsif v_old_posted and v_new_posted then
      perform public.delete_expense_journal_entry(OLD.id);
      perform public.create_expense_journal_entry(NEW.id);
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    if v_old_posted then
      perform public.delete_expense_journal_entry(OLD.id);
    end if;
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expenses_change'
       and tgrelid = 'public.expenses'::regclass
  ) then
    create trigger trg_expenses_change
      after insert or update or delete on public.expenses
      for each row execute procedure public.process_expense_change();
  end if;
end $$;

create or replace function public.handle_expense_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    perform public.recalculate_expense_totals(NEW.expense_id);
    perform public.create_expense_payment_journal_entry(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    perform public.recalculate_expense_totals(NEW.expense_id);
    perform public.delete_expense_payment_journal_entry(OLD.id);
    perform public.create_expense_payment_journal_entry(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    perform public.recalculate_expense_totals(OLD.expense_id);
    perform public.delete_expense_payment_journal_entry(OLD.id);
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expense_payments_change'
       and tgrelid = 'public.expense_payments'::regclass
  ) then
    create trigger trg_expense_payments_change
      after insert or update or delete on public.expense_payments
      for each row execute procedure public.handle_expense_payment_change();
  end if;
end $$;

-- ================================================
-- Trigger for expense_lines changes
-- ================================================
create or replace function public.handle_expense_line_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense_id uuid;
  v_posting_status text;
begin
  -- Get the expense_id from the relevant row
  if TG_OP = 'DELETE' then
    v_expense_id := OLD.expense_id;
  else
    v_expense_id := NEW.expense_id;
  end if;

  -- Check if parent expense is posted
  select posting_status into v_posting_status
    from public.expenses
   where id = v_expense_id;

  -- If posted, regenerate journal entry
  if lower(coalesce(v_posting_status, 'draft')) = 'posted' then
    perform public.delete_expense_journal_entry(v_expense_id);
    perform public.create_expense_journal_entry(v_expense_id);
  end if;

  -- Recalculate expense totals
  perform public.recalculate_expense_totals(v_expense_id);

  if TG_OP = 'DELETE' then
    return OLD;
  else
    return NEW;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
      from pg_trigger
     where tgname = 'trg_expense_lines_change'
       and tgrelid = 'public.expense_lines'::regclass
  ) then
    create trigger trg_expense_lines_change
      after insert or update or delete on public.expense_lines
      for each row execute procedure public.handle_expense_line_change();
  end if;
end $$;

create table if not exists stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid not null references products(id) on delete cascade,
  warehouse_id uuid,
  type text not null check (type in ('IN','OUT','INVENTORY_ADJUST','TRANSFER_OUT','TRANSFER_IN')),
  movement_type text,
  quantity numeric(12,2) not null,
  reference text,
  notes text,
  date timestamp with time zone not null default now(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  entry_number text not null,
  entry_date timestamp with time zone not null default now(),
  description text not null,
  type text not null,
  source_module text,
  source_reference text,
  status text not null default 'draft',
  total_debit numeric(14,2) not null default 0,
  total_credit numeric(14,2) not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_entries'
       and column_name = 'date'
  ) then
    begin
      alter table public.journal_entries rename column date to entry_date;
    exception when others then
      null;
    end;
  end if;
end $$;

create table if not exists journal_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  entry_id uuid not null references journal_entries(id) on delete cascade,
  account_id uuid not null,
  account_code text not null,
  account_name text not null,
  description text,
  debit_amount numeric(14,2) not null default 0,
  credit_amount numeric(14,2) not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$
begin
  begin
    alter table public.customers drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.products drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.sales_invoices drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.sales_payments drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.stock_movements drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.journal_entries drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.journal_lines drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.suppliers drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.accounts drop column if exists company_id;
  exception when others then
    null;
  end;
end $$;

do $$
declare
  v_account_id_is_uuid boolean;
begin
  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'account_id'
       and data_type = 'uuid'
  ) into v_account_id_is_uuid;

  if not v_account_id_is_uuid then
    begin
      alter table public.journal_lines drop column account_id;
    exception when undefined_column then
      null;
    end;

    alter table public.journal_lines
      add column account_id uuid;
  end if;
end $$;

do $$
begin
  begin
    alter table public.journal_lines
      alter column account_id set not null;
  exception when others then
    null;
  end;
end $$;

do $$
declare
  v_has_old_entry_column boolean;
  v_has_new_entry_column boolean;
  rec record;
begin
  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'journal_entry_id'
  ) into v_has_old_entry_column;

  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'entry_id'
  ) into v_has_new_entry_column;

  if not v_has_old_entry_column then
    return;
  end if;

  if not v_has_new_entry_column then
    alter table public.journal_lines rename column journal_entry_id to entry_id;
    return;
  end if;

  execute 'update public.journal_lines set entry_id = journal_entry_id where entry_id is null';

  for rec in (
    select constraint_name
      from information_schema.constraint_column_usage
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'journal_entry_id'
  ) loop
    execute format('alter table public.journal_lines drop constraint %I', rec.constraint_name);
  end loop;

  alter table public.journal_lines drop column journal_entry_id;

  begin
    alter table public.journal_lines
      alter column entry_id set not null;
  exception when others then
    null;
  end;
end $$;

alter table public.stock_movements
  add column if not exists date timestamp with time zone not null default now(),
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now(),
  add column if not exists type text,
  add column if not exists movement_type text,
  add column if not exists quantity numeric(12,2),
  add column if not exists reference text,
  add column if not exists notes text;

do $$
begin
  begin
    alter table public.stock_movements
      alter column warehouse_id drop not null;
  exception when others then
    null;
  end;

  begin
    alter table public.stock_movements
      alter column movement_type drop not null;
  exception when others then
    null;
  end;
end $$;

alter table public.journal_entries
  add column if not exists entry_number text,
  add column if not exists entry_date timestamp with time zone not null default now(),
  add column if not exists description text,
  add column if not exists type text,
  add column if not exists source_module text,
  add column if not exists source_reference text,
  add column if not exists status text not null default 'draft',
  add column if not exists total_debit numeric(14,2) not null default 0,
  add column if not exists total_credit numeric(14,2) not null default 0,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

alter table public.journal_lines
  add column if not exists entry_id uuid,
  add column if not exists account_id uuid,
  add column if not exists account_code text,
  add column if not exists account_name text,
  add column if not exists description text,
  add column if not exists debit_amount numeric(14,2) not null default 0,
  add column if not exists credit_amount numeric(14,2) not null default 0,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_lines'::regclass
      and contype = 'f'
      and conname = 'journal_lines_entry_id_fkey'
  ) then
    alter table public.journal_lines
      add constraint journal_lines_entry_id_fkey
        foreign key (entry_id)
        references public.journal_entries(id)
        on delete cascade;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_lines'::regclass
      and contype = 'f'
      and conname = 'journal_lines_account_id_fkey'
  ) then
    alter table public.journal_lines
      add constraint journal_lines_account_id_fkey
        foreign key (account_id)
        references public.accounts(id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'stock_movements'
      and t.tgname = 'trg_stock_movements_updated_at'
  ) then
    create trigger trg_stock_movements_updated_at
      before update on stock_movements
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'journal_entries'
      and t.tgname = 'trg_journal_entries_updated_at'
  ) then
    create trigger trg_journal_entries_updated_at
      before update on journal_entries
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'journal_lines'
      and t.tgname = 'trg_journal_lines_updated_at'
  ) then
    create trigger trg_journal_lines_updated_at
      before update on journal_lines
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_stock_movements_product_id
  on stock_movements(product_id);

create index if not exists idx_journal_entries_entry_number
  on journal_entries(entry_number);

drop index if exists idx_journal_entries_date;
create index if not exists idx_journal_entries_entry_date
  on journal_entries(entry_date);

create index if not exists idx_journal_lines_entry_id
  on journal_lines(entry_id);

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  customer_id uuid references customers(id) on delete set null,
  source text not null check (source in ('POS', 'Website')),
  order_date timestamp with time zone not null default now(),
  total numeric(12,2) not null default 0,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_orders_tenant on orders(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table orders does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in orders';
end $$;

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  tenant_id uuid references tenants(id) on delete cascade not null,
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id) on delete restrict,
  quantity integer not null,
  price numeric(12,2) not null,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_order_items_tenant on order_items(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table order_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in order_items';
end $$;

create or replace function public.handle_order_item_insert()
returns trigger as $$
begin
  -- Update BOTH inventory_qty (legacy) AND stock_quantity (current)
  update products
     set inventory_qty = inventory_qty - new.quantity,
         stock_quantity = greatest(stock_quantity - new.quantity, 0)
   where id = new.product_id;
  return new;
end;
$$ language plpgsql;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'order_items'
      and t.tgname = 'trg_order_item_insert'
  ) then
    create trigger trg_order_item_insert
      after insert on order_items
      for each row execute procedure public.handle_order_item_insert();
  end if;
end $$;

-- Function to handle sales item updates
create or replace function public.handle_sales_item()
returns trigger as $$
declare
  v_company_id uuid;
  v_warehouse_id uuid;
begin
  select company_id
    into v_company_id
    from public.sales_orders
   where id = new.order_id;

  select w.id
    into v_warehouse_id
    from public.warehouses w
   where w.company_id = v_company_id
   order by w.created_at
   limit 1;

  if v_warehouse_id is null then
    raise exception 'No default warehouse configured for company %', v_company_id;
  end if;

  -- Update BOTH inventory_qty (legacy) AND stock_quantity (current)
  update public.products
     set inventory_qty = inventory_qty - new.quantity,
         stock_quantity = greatest(stock_quantity - new.quantity, 0)
   where id = new.product_id
     and is_service = false;

  insert into public.stock_movements (product_id, warehouse_id, movement_type, quantity, reference)
  values (new.product_id, v_warehouse_id, 'outbound', new.quantity, 'sales_order:' || new.order_id);

  return new;
end;
$$ language plpgsql;

-- Function to handle purchase item updates
create or replace function public.handle_purchase_item()
returns trigger as $$
declare
  v_company_id uuid;
  v_warehouse_id uuid;
begin
  select company_id
    into v_company_id
    from public.purchase_orders
   where id = new.purchase_order_id;

  select w.id
    into v_warehouse_id
    from public.warehouses w
   where w.company_id = v_company_id
   order by w.created_at
   limit 1;

  if v_warehouse_id is null then
    raise exception 'No default warehouse configured for company %', v_company_id;
  end if;

  -- Update BOTH inventory_qty (legacy) AND stock_quantity (current)
  update public.products
     set inventory_qty = inventory_qty + new.quantity,
         stock_quantity = stock_quantity + new.quantity
   where id = new.product_id
     and is_service = false;

  insert into public.stock_movements (product_id, warehouse_id, movement_type, quantity, reference)
  values (new.product_id, v_warehouse_id, 'inbound', new.quantity, 'purchase_order:' || new.purchase_order_id);

  return new;
end;
$$ language plpgsql;

-- ============================================================================
-- PURCHASE INVOICE WORKFLOW FUNCTIONS (Mirror sales invoice pattern)
-- ============================================================================

create or replace function public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
  
  -- Set handling variables
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
begin
  -- CRITICAL: Set flag to skip stock_adjustment trigger for automatic changes
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  
  if p_invoice.id is null then
    raise notice 'consume_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'consume_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      (item->>'product_name')::text as product_name,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      raise notice 'consume_purchase_invoice_inventory: skipping item with null product_id';
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      raise notice 'consume_purchase_invoice_inventory: skipping item % with zero quantity', v_resolved_product_id;
      continue;
    end if;

    -- CHECK IF PRODUCT IS A SET
    select is_set into v_is_set from products where id = v_resolved_product_id;
    
    if v_is_set then
        -- LOGIC FOR SETS: Explode into components
        raise notice 'consume_purchase_invoice_inventory: exploding set % into components', v_resolved_product_id;
        
        for v_child in
            select 
                component_product_id, 
                quantity_in_set
            from product_set_components
            where set_product_id = v_resolved_product_id
        loop
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            
            -- Update Component Inventory
            update public.products
            set 
              inventory_qty = inventory_qty + v_child_qty,
              stock_quantity = stock_quantity + v_child_qty
            where id = v_child.component_product_id;
            
            -- Record Stock Movement for Component
            insert into public.stock_movements (
              product_id,
              quantity,
              movement_type,
              type,
              reference,
              notes,
              date,
              created_at,
              updated_at
            ) values (
              v_child.component_product_id,
              v_child_qty,
              'purchase_invoice',
              'IN',
              v_reference,
              format('Entrada por compra de set %s (Factura %s)', v_item.product_name, p_invoice.invoice_number),
              p_invoice.date,
              now(),
              now()
            );
        end loop;
        
    else
        -- STANDARD LOGIC: Update product inventory directly
        update public.products
        set 
          inventory_qty = inventory_qty + v_quantity_int,
          stock_quantity = stock_quantity + v_quantity_int
        where id = v_resolved_product_id;

        -- Record stock movement
        insert into public.stock_movements (
          product_id,
          quantity,
          movement_type,
          type,
          reference,
          notes,
          date,
          created_at,
          updated_at
        ) values (
          v_resolved_product_id,
          v_quantity_int,
          'purchase_invoice',
          'IN',
          v_reference,
          format('Entrada según factura compra %s', p_invoice.invoice_number),
          p_invoice.date,
          now(),
          now()
        );
    end if;

  end loop;

  raise notice 'consume_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.restore_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
  
  -- Set variables
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
begin
  if p_invoice.id is null then
    raise notice 'restore_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'restore_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  -- Delete ALL stock movements for this reference (cleans up both sets and normal products)
  delete from public.stock_movements
  where reference = v_reference;

  -- DECREASE inventory (restore = undo IN movement)
  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      continue;
    end if;

    -- CHECK IF PRODUCT IS A SET
    select is_set into v_is_set from products where id = v_resolved_product_id;

    if v_is_set then
        -- SET LOGIC: Restore components
        for v_child in
            select 
                component_product_id, 
                quantity_in_set
            from product_set_components
            where set_product_id = v_resolved_product_id
        loop
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            
            update public.products
            set 
              inventory_qty = greatest(inventory_qty - v_child_qty, 0),
              stock_quantity = greatest(stock_quantity - v_child_qty, 0)
            where id = v_child.component_product_id;
        end loop;
        
    else
        -- STANDARD LOGIC
        update public.products
        set 
          inventory_qty = greatest(inventory_qty - v_quantity_int, 0),
          stock_quantity = greatest(stock_quantity - v_quantity_int, 0)
        where id = v_resolved_product_id;
    end if;

  end loop;
  
  raise notice 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_inventory_account_id uuid;
  v_iva_account_id uuid;
  v_payable_account_id uuid;
  v_description text;
begin
  raise notice '🔵 START create_purchase_invoice_journal_entry for invoice %', p_invoice.id;
  
  if p_invoice.id is null then
    raise notice '❌ Invoice ID is null, returning';
    return;
  end if;
  
  raise notice '✅ Invoice ID: %, tenant_id: %', p_invoice.id, p_invoice.tenant_id;

  -- Check if journal entry already exists
  select exists (
    select 1
    from public.journal_entries
    where source_module = 'purchase_invoices'
      and source_reference = p_invoice.id::text
  ) into v_exists;

  if v_exists then
    raise notice '⚠️ Entry already exists for invoice %, skipping', p_invoice.id;
    return;
  end if;
  
  raise notice '✅ No existing entry found, proceeding...';

  -- Ensure accounts exist
  raise notice '🔵 Ensuring accounts exist...';
  
  v_inventory_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Valor del inventario de productos',
    null
  );
  raise notice '✅ Inventory account: %', v_inventory_account_id;

  v_iva_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2120',
    'IVA Crédito Fiscal',
    'asset',
    'currentAsset',
    'IVA pagado en compras, recuperable',
    null
  );
  raise notice '✅ IVA account: %', v_iva_account_id;

  v_payable_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    'liability',
    'currentLiability',
    'Obligaciones con proveedores',
    null
  );
  raise notice '✅ Payable account: %', v_payable_account_id;

  v_description := format('Factura compra %s - %s', 
    p_invoice.invoice_number, 
    coalesce(p_invoice.supplier_name, 'Proveedor')
  );
  
  raise notice '🔵 Creating journal entry header...';

  -- Create journal entry header
  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    p_invoice.tenant_id,
    public.get_next_document_number(p_invoice.tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'purchase',
    'purchase_invoices',
    p_invoice.invoice_number,
    'posted',
    p_invoice.total,
    p_invoice.total,
    now(),
    now()
  );

  -- DR: Inventory (increase asset)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    tenant_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    v_description,
    p_invoice.subtotal,
    0,
    now(),
    now()
  );

  -- DR: IVA Crédito (increase asset, recoverable tax)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    tenant_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    p_invoice.tenant_id,
    '2120',
    'IVA Crédito Fiscal',
    v_description,
    p_invoice.tax,
    0,
    now(),
    now()
  );

  -- CR: Accounts Payable (increase liability)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    tenant_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_payable_account_id,
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    v_description,
    0,
    p_invoice.total,
    now(),
    now()
  );
  
  raise notice '✅ Journal entry created successfully for invoice %', p_invoice.id;
  raise notice '🎉 DONE - Entry ID: %, Total: %', v_entry_id, p_invoice.total;
end;
$$;

create or replace function public.delete_purchase_invoice_journal_entry(p_invoice_number text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invoice_number is null then
    return;
  end if;

  -- Delete invoice journal entry
  delete from public.journal_entries
  where source_module = 'purchase_invoices'
    and source_reference = p_invoice_number;

  -- Delete all payment journal entries for this invoice
  delete from public.journal_entries
  where source_module = 'purchase_payments'
    and source_reference = p_invoice_number;

  raise notice 'delete_purchase_invoice_journal_entry: deleted entries for invoice %', p_invoice_number;
end;
$$;

create or replace function public.handle_purchase_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text;
  v_new_status text;
begin
  raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- Inventory: ONLY if inserted directly as 'received' (rare case)
    if v_new_status = 'received' then
      raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;
    
    -- Journal: If inserted at 'confirmed' or later
    if v_new_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;
    
    perform public.recalculate_purchase_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;
    
    raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    -- INVENTORY HANDLING: ONLY at 'received' status
    -- Different logic for standard vs prepayment models:
    --
    -- STANDARD MODEL: Draft→Confirmed→RECEIVED→Paid
    --   Inventory added at 'received', stays through 'paid'
    --   So: received<->paid transitions do NOT change inventory
    --
    -- PREPAYMENT MODEL: Draft→Confirmed→Paid→RECEIVED
    --   Inventory added at 'received' (after payment)
    --   So: received<->paid transitions DO change inventory
    
    if NEW.prepayment_model then
      -- PREPAYMENT MODEL: Inventory changes whenever entering/leaving 'received'
      if v_old_status != 'received' AND v_new_status = 'received' then
        -- Transitioning TO received (from any status): add inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);
        
      elsif v_old_status = 'received' AND v_new_status != 'received' then
        -- Transitioning FROM received (to any status): remove inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);
        
      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Staying at received but invoice data changed: update inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] staying at received, updating inventory';
        perform public.restore_purchase_invoice_inventory(OLD);
        perform public.consume_purchase_invoice_inventory(NEW);
      end if;
      
    else
      -- STANDARD MODEL: Inventory changes only when entering/leaving 'received' from/to non-paid statuses
      if v_old_status NOT IN ('received', 'paid') AND v_new_status = 'received' then
        -- Transitioning TO received from confirmed/sent/draft: add inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);
        
      elsif v_old_status = 'received' AND v_new_status NOT IN ('received', 'paid') then
        -- Transitioning FROM received to confirmed/sent/draft: remove inventory
        -- Note: received→paid does NOT remove (goods stay in standard flow)
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);
        
      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Staying at received but invoice data changed: update inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] staying at received, updating inventory';
        perform public.restore_purchase_invoice_inventory(OLD);
        perform public.consume_purchase_invoice_inventory(NEW);
      end if;
    end if;

    -- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting
    -- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)
    -- It should NOT be recreated when moving between confirmed→received→paid
    -- It should ONLY be recreated if staying at same status but amounts changed
    
    if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
      -- Transitioning TO confirmed/received/paid: create journal entry
      raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
      
    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
      -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
      raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
      
    elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then
      -- Staying at same confirmed+ status but invoice data might have changed
      -- Only recreate journal if amounts changed (not just status transition)
      if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR 
         OLD.tax IS DISTINCT FROM NEW.tax OR 
         OLD.total IS DISTINCT FROM NEW.total OR
         OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then
        raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';
        perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
        perform public.create_purchase_invoice_journal_entry(NEW);
      end if;
    end if;
    
    -- Only recalculate if this is NOT a payment-only update (prevents infinite recursion)
    -- If only paid_amount, balance, or status changed → skip recalculate (it's from recalculate itself)
    -- If items, total, subtotal, tax, or other fields changed → call recalculate
    if OLD.items IS DISTINCT FROM NEW.items OR
       OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
       OLD.tax IS DISTINCT FROM NEW.tax OR
       OLD.total IS DISTINCT FROM NEW.total OR
       OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR
       OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then
      raise notice 'handle_purchase_invoice_change: invoice data changed, recalculating payments';
      perform public.recalculate_purchase_invoice_payments(NEW.id);
    else
      raise notice 'handle_purchase_invoice_change: only payment fields changed, skipping recalculate to avoid recursion';
    end if;
    
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- Restore inventory if was received
    if v_old_status = 'received' then
      raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
    end if;
    
    -- Delete journal entry if was confirmed or later
    if v_old_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
    end if;
    
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  drop trigger if exists trg_purchase_invoices_change on public.purchase_invoices;
  
  create trigger trg_purchase_invoices_change
    after insert or update or delete on public.purchase_invoices
    for each row execute procedure public.handle_purchase_invoice_change();
    
  raise notice 'Trigger trg_purchase_invoices_change created successfully';
exception
  when others then
    raise notice 'Error creating trigger: %', SQLERRM;
end $$;

-- Basic RLS scaffolding: enable on each table; policies to be tailored per role.
alter table customers enable row level security;
alter table customer_addresses enable row level security;
alter table products enable row level security;
alter table product_brands enable row level security;
alter table sales_invoices enable row level security;
alter table sales_payments enable row level security;
alter table stock_movements enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table journal_entries enable row level security;
alter table journal_lines enable row level security;
alter table suppliers enable row level security;
alter table purchase_invoices enable row level security;
alter table bikes enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation


-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- TODO: add role-specific policies matching Sales, Inventory, HR, Mechanic, Cashier profiles.

-- ============================================================================
-- FINANCIAL REPORTING FUNCTIONS
-- Professional accounting reports for Chilean GAAP compliance
-- ============================================================================

-- Function 1: Get account balance for a specific period
-- Returns the net balance (debits - credits for assets/expenses, credits - debits for liabilities/equity/income)
create or replace function public.get_account_balance(
  p_account_id uuid,
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account record;
  v_total_debit numeric(14,2) := 0;
  v_total_credit numeric(14,2) := 0;
  v_balance numeric(14,2) := 0;
begin
  -- Get account type to determine balance calculation
  select type into v_account
  from accounts
  where id = p_account_id
    and tenant_id = user_tenant_id();
  
  if not found then
    raise exception 'Account not found: %', p_account_id;
  end if;
  
  -- Sum debits and credits for this account in the period
  select
    coalesce(sum(debit_amount), 0),
    coalesce(sum(credit_amount), 0)
  into v_total_debit, v_total_credit
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  where jl.account_id = p_account_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id();
  
  -- Calculate balance based on account type
  -- Assets and Expenses: Debit increases balance (debit - credit)
  -- Liabilities, Equity, Income: Credit increases balance (credit - debit)
  if v_account.type in ('asset', 'expense') then
    v_balance := v_total_debit - v_total_credit;
  else
    v_balance := v_total_credit - v_total_debit;
  end if;
  
  return v_balance;
end;
$$;

-- Function 2: Get balances by account type with details
-- Returns all accounts of a specific type with their balances for a period
create or replace function public.get_balances_by_type(
  p_account_type text,
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_category text,
  parent_id uuid,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.category as account_category,
    a.parent_id,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      -- Assets and Expenses: Debit balance
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      -- Liabilities, Equity, Income: Credit balance
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and je.tenant_id = user_tenant_id()
  where a.type = p_account_type
    and a.is_active = true
    and a.tenant_id = user_tenant_id()
  group by a.id, a.code, a.name, a.category, a.parent_id, a.type
  order by a.code;
end;
$$;

-- Function 3: Get balances by category (more granular than type)
-- Useful for grouping in financial statements
create or replace function public.get_balances_by_category(
  p_account_category text,
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_type text,
  parent_id uuid,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.type as account_type,
    a.parent_id,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and je.tenant_id = user_tenant_id()
  where a.category = p_account_category
    and a.is_active = true
    and a.tenant_id = user_tenant_id()
  group by a.id, a.code, a.name, a.type, a.parent_id
  order by a.code;
end;
$$;

-- Function 4: Get trial balance (all accounts with balances)
-- Essential for verifying that debits = credits
create or replace function public.get_trial_balance(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  account_code text,
  account_name text,
  account_type text,
  account_category text,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.code as account_code,
    a.name as account_name,
    a.type as account_type,
    a.category as account_category,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and je.tenant_id = user_tenant_id()
  where a.is_active = true
    and a.tenant_id = user_tenant_id()
  group by a.id, a.code, a.name, a.type, a.category
  having coalesce(sum(jl.debit_amount), 0) <> 0 
      or coalesce(sum(jl.credit_amount), 0) <> 0
  order by a.code;
end;
$$;

-- Function 5: Calculate net income for a period
-- Income Statement bottom line: Total Income - Total Expenses
create or replace function public.calculate_net_income(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_income numeric(14,2) := 0;
  v_total_expense numeric(14,2) := 0;
  v_net_income numeric(14,2) := 0;
begin
  -- Calculate total income (credit balance for income accounts)
  select coalesce(sum(
    case
      when a.type = 'income' then
        coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0)
      else 0
    end
  ), 0)
  into v_total_income
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and a.type = 'income'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id()
    and a.tenant_id = user_tenant_id();
  
  -- Calculate total expenses (debit balance for expense accounts)
  select coalesce(sum(
    case
      when a.type = 'expense' then
        coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0)
      else 0
    end
  ), 0)
  into v_total_expense
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and a.type = 'expense'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id()
    and a.tenant_id = user_tenant_id();
  
  -- Net Income = Income - Expenses
  v_net_income := v_total_income - v_total_expense;
  
  return v_net_income;
end;
$$;

-- Function 6: Get cumulative balance (for Balance Sheet - all transactions up to date)
-- Unlike period balance, this includes ALL transactions from the beginning of time
create or replace function public.get_cumulative_balance(
  p_account_id uuid,
  p_as_of_date timestamp with time zone
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account record;
  v_total_debit numeric(14,2) := 0;
  v_total_credit numeric(14,2) := 0;
  v_balance numeric(14,2) := 0;
begin
  select type into v_account
  from accounts
  where id = p_account_id
    and tenant_id = user_tenant_id();
  
  if not found then
    raise exception 'Account not found: %', p_account_id;
  end if;
  
  -- Sum all debits and credits up to the date
  select
    coalesce(sum(debit_amount), 0),
    coalesce(sum(credit_amount), 0)
  into v_total_debit, v_total_credit
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  where jl.account_id = p_account_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id();
  
  -- Calculate balance based on account type
  if v_account.type in ('asset', 'expense') then
    v_balance := v_total_debit - v_total_credit;
  else
    v_balance := v_total_credit - v_total_debit;
  end if;
  
  return v_balance;
end;
$$;

-- Function 7: Get cumulative balances by type (for Balance Sheet)
create or replace function public.get_cumulative_balances_by_type(
  p_account_type text,
  p_as_of_date timestamp with time zone
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_category text,
  parent_id uuid,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.category as account_category,
    a.parent_id,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and je.tenant_id = user_tenant_id()
  where a.type = p_account_type
    and a.is_active = true
    and a.tenant_id = user_tenant_id()
  group by a.id, a.code, a.name, a.category, a.parent_id, a.type
  order by a.code;
end;
$$;

-- Function 8: Verify accounting equation (Assets = Liabilities + Equity)
-- Returns true if balanced, false if not (with difference amount)
create or replace function public.verify_accounting_equation(
  p_as_of_date timestamp with time zone
)
returns table (
  is_balanced boolean,
  total_assets numeric(14,2),
  total_liabilities numeric(14,2),
  total_equity numeric(14,2),
  difference numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assets numeric(14,2) := 0;
  v_liabilities numeric(14,2) := 0;
  v_equity numeric(14,2) := 0;
  v_diff numeric(14,2) := 0;
  v_is_balanced boolean := false;
begin
  -- Calculate total assets
  select coalesce(sum(
    coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0)
  ), 0)
  into v_assets
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and a.type = 'asset'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id()
    and a.tenant_id = user_tenant_id();
  
  -- Calculate total liabilities
  select coalesce(sum(
    coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0)
  ), 0)
  into v_liabilities
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and a.type = 'liability'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id()
    and a.tenant_id = user_tenant_id();
  
  -- Calculate total equity
  select coalesce(sum(
    coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0)
  ), 0)
  into v_equity
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and a.type = 'equity'
    and jl.tenant_id = user_tenant_id()
    and je.tenant_id = user_tenant_id()
    and a.tenant_id = user_tenant_id();
  
  -- Calculate difference (should be near zero)
  v_diff := v_assets - (v_liabilities + v_equity);
  
  -- Consider balanced if difference is less than 1 peso (rounding tolerance)
  v_is_balanced := abs(v_diff) < 1.00;
  
  return query
  select v_is_balanced, v_assets, v_liabilities, v_equity, v_diff;
end;
$$;

-- Function 9: Get income statement data grouped by category
-- Returns structured data ready for Income Statement report
create or replace function public.get_income_statement_data(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_cash_flow then
    -- CASH FLOW STATEMENT (Estado de Flujo de Efectivo)
    -- Shows ACTUAL cash movements, not accrual accounting
    return query
    
    -- CASH IN: Payments received from customers
    select 
      'operatingIncome'::text as category,
      'Ingresos de Efectivo'::text as category_label,
      '4000'::text as account_code,
      'Cobros de Clientes'::text as account_name,
      coalesce(sum(sp.amount), 0)::numeric(14,2) as amount
    from sales_payments sp
    where sp.date >= p_start_date
      and sp.date <= p_end_date
      and sp.tenant_id = user_tenant_id()
      
    union all
    
    -- CASH OUT: Payments to suppliers (inventory purchases)
    select 
      'costOfGoodsSold'::text as category,
      'Egresos de Efectivo - Proveedores'::text as category_label,
      '5000'::text as account_code,
      'Pagos a Proveedores'::text as account_name,
      coalesce(sum(pp.amount), 0)::numeric(14,2) as amount
    from purchase_payments pp
    where pp.date >= p_start_date
      and pp.date <= p_end_date
      and pp.tenant_id = user_tenant_id()
      
    union all
    
    -- CASH OUT: Operating expenses paid (payroll, rent, utilities, etc.)
    select 
      a.category,
      'Egresos de Efectivo - Gastos'::text as category_label,
      a.code as account_code,
      a.name as account_name,
      coalesce(sum(el.total), 0)::numeric(14,2) as amount
    from expenses e
    join expense_lines el on el.expense_id = e.id
    join accounts a on a.id = el.account_id
    where e.payment_status = 'paid'
      and e.paid_at >= p_start_date
      and e.paid_at <= p_end_date
      and e.tenant_id = user_tenant_id()
      and a.type = 'expense'
    group by a.category, a.code, a.name;

  else
    -- INCOME STATEMENT (Estado de Resultados) - Accrual Basis
    -- Shows revenue when earned, expenses when incurred
    return query
    select
      a.category,
      case a.category
        when 'operatingIncome' then 'Ingresos Operacionales'
        when 'nonOperatingIncome' then 'Ingresos No Operacionales'
        when 'costOfGoodsSold' then 'Costo de Ventas'
        when 'operatingExpense' then 'Gastos Operacionales'
        when 'financialExpense' then 'Gastos Financieros'
        when 'taxExpense' then 'Impuestos'
        else a.category
      end as category_label,
      a.code as account_code,
      a.name as account_name,
      case
        when a.type = 'income' then
          coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
        when a.type = 'expense' then
          coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
        else 0
      end::numeric(14,2) as amount
    from accounts a
    join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
    join journal_entries je on je.id = jl.entry_id
      and je.entry_date >= p_start_date
      and je.entry_date <= p_end_date
      and je.status = 'posted'
      and je.tenant_id = user_tenant_id()
    where a.type in ('income', 'expense')
      and a.is_active = true
      and a.tenant_id = user_tenant_id()
    group by a.id, a.code, a.name, a.type, a.category
    having (coalesce(sum(jl.debit_amount), 0) <> 0 
         or coalesce(sum(jl.credit_amount), 0) <> 0)
    order by a.code;
  end if;
end;
$$;

-- Function 10.1: Income vs Expense time series for dashboards (last N months)
-- Function 10.1: Get income/expense time series (Monthly)
create or replace function public.get_income_expense_timeseries(
  p_months integer default 12,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric(14,2),
  expense numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  with month_windows as (
    select
      date_trunc('month', current_timestamp) - make_interval(months => m.month_index) as period_start
    from generate_series(0, greatest(p_months, 1) - 1) as m(month_index)
  )
  select
    mw.period_start::date,
    (mw.period_start + interval '1 month' - interval '1 day')::date as period_end,
    
    -- INCOME CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sum of Sales Payments received in this period
        (
          select sum(amount)
          from sales_payments sp
          where sp.date >= mw.period_start
            and sp.date < mw.period_start + interval '1 month'
            and sp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Sum of Income Journal Entries (posted)
        (
          select
            sum(coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'income'
            and je.entry_date >= mw.period_start
            and je.entry_date < mw.period_start + interval '1 month'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as income,

    -- EXPENSE CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sum of Purchase Payments made in this period
        (
          select sum(amount)
          from purchase_payments pp
          where pp.date >= mw.period_start
            and pp.date < mw.period_start + interval '1 month'
            and pp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Sum of Expense Journal Entries (posted)
        (
          select
            sum(coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'expense'
            and je.entry_date >= mw.period_start
            and je.entry_date < mw.period_start + interval '1 month'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as expense

  from month_windows mw
  order by mw.period_start;
$$;

-- Grant execute permissions to authenticated users
grant execute on function public.get_income_expense_timeseries(integer, boolean) to authenticated;


-- Function 10.1b: Get income/expense time series aggregated by day
create or replace function public.get_income_expense_daily_timeseries(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric(14,2),
  expense numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  with day_windows as (
    select
      (date_trunc('day', p_start_date) + make_interval(days => d.day_index))::date as period_start
    from generate_series(0, extract(days from (p_end_date - p_start_date))::integer) as d(day_index)
  )
  select
    dw.period_start::date,
    dw.period_start::date as period_end,

    -- INCOME CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sales Payments
        (
          select sum(amount)
          from sales_payments sp
          where sp.date >= dw.period_start
            and sp.date < dw.period_start + interval '1 day'
            and sp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Income Journal Entries
        (
          select
            sum(coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'income'
            and je.entry_date >= dw.period_start
            and je.entry_date < dw.period_start + interval '1 day'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as income,

    -- EXPENSE CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Purchase Payments
        (
          select sum(amount)
          from purchase_payments pp
          where pp.date >= dw.period_start
            and pp.date < dw.period_start + interval '1 day'
            and pp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Expense Journal Entries
        (
          select
            sum(coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'expense'
            and je.entry_date >= dw.period_start
            and je.entry_date < dw.period_start + interval '1 day'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as expense

  from day_windows dw
  order by dw.period_start;
$$;

-- Grant execute permissions to authenticated users
grant execute on function public.get_income_expense_daily_timeseries(timestamp with time zone, timestamp with time zone, boolean) to authenticated;

-- Function 10.2: Top expense accounts for a period (for donut charts)
create or replace function public.get_expense_breakdown(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_limit integer default 6
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id,
    a.code,
    a.name,
    coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      as amount
  from accounts a
  join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
  join journal_entries je on je.id = jl.entry_id AND je.tenant_id = user_tenant_id()
  where a.type = 'expense'
    and a.is_active = true
    and a.tenant_id = user_tenant_id()
    and je.status = 'posted'
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
  group by a.id, a.code, a.name
  having coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0) <> 0
  order by amount desc
  limit greatest(p_limit, 1);
end;
$$;

-- Grant execute permissions to authenticated users
grant execute on function public.get_expense_breakdown(timestamp with time zone, timestamp with time zone, integer) to authenticated;

-- Function 10: Get balance sheet data grouped by category
-- Returns structured data ready for Balance Sheet report
create or replace function public.get_balance_sheet_data(
  p_as_of_date timestamp with time zone
)
returns table (
  account_type text,
  type_label text,
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.type as account_type,
    case a.type
      when 'asset' then 'ACTIVOS'
      when 'liability' then 'PASIVOS'
      when 'equity' then 'PATRIMONIO'
      else a.type
    end as type_label,
    a.category,
    case a.category
      when 'currentAsset' then 'Activos Circulantes'
      when 'fixedAsset' then 'Activos Fijos'
      when 'otherAsset' then 'Otros Activos'
      when 'currentLiability' then 'Pasivos Circulantes'
      when 'longTermLiability' then 'Pasivos Largo Plazo'
      when 'capital' then 'Capital'
      when 'retainedEarnings' then 'Utilidades Retenidas'
      else a.category
    end as category_label,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'asset' then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      when a.type in ('liability', 'equity') then
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
      else 0
    end::numeric(14,2) as amount
  from accounts a
  left join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and je.tenant_id = user_tenant_id()
  where a.type in ('asset', 'liability', 'equity')
    and a.is_active = true
    and a.tenant_id = user_tenant_id()
  group by a.id, a.code, a.name, a.type, a.category
  having (coalesce(sum(jl.debit_amount), 0) <> 0 
       or coalesce(sum(jl.credit_amount), 0) <> 0)
  order by 
    case a.type 
      when 'asset' then 1 
      when 'liability' then 2 
      when 'equity' then 3 
      else 4 
    end,
    a.category,
    a.code;
end;
$$;

-- ============================================================
-- BIKESHOP MODULE - Mechanic & Service Manager
-- ============================================================
-- Complete bikeshop/workshop management system with:
-- - Bike registration and tracking
-- - Service jobs (pegas) with workflow management
-- - Service packages/templates
-- - Labor and parts tracking
-- - Timeline/history for each bike
-- - Photos and documentation
-- - Integration with inventory, accounting, and CRM

-- Table: bikes
-- Stores registered bicycles linked to customers
create table if not exists bikes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  customer_id uuid not null references customers(id) on delete cascade,
  brand_id uuid references bike_brands(id) on delete set null,
  model_id uuid references bike_models(id) on delete set null,
  brand text, -- Legacy field, kept for backwards compatibility
  model text, -- Legacy field, kept for backwards compatibility
  year integer,
  serial_number text,
  color text,
  frame_size text,
  wheel_size text,
  bike_type text check (bike_type in ('road','mountain','hybrid','electric','bmx','folding','cruiser','gravel','other')),
  front_hub_spacing_mm numeric(5,1), -- Front OLD: 100mm (road), 110mm (MTB Boost), etc.
  rear_hub_spacing_mm numeric(5,1), -- Rear OLD: 130mm, 135mm, 142mm, 148mm (Boost), etc.
  spoke_count integer check (spoke_count in (24, 28, 32, 36, 40)), -- Number of spokes per wheel
  factory_rim_id uuid references wheel_rims(id) on delete set null, -- Original rim that came with the bike
  purchase_date date,
  purchase_price numeric(12,2),
  warranty_until date,
  qr_code text, -- For quick bike lookup via QR scan
  notes text,
  image_url text, -- Primary image
  image_urls text[] not null default array[]::text[], -- Multiple images
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, serial_number), -- Each tenant can have same serial numbers
  unique(tenant_id, qr_code) -- Each tenant can have same QR codes
);

-- Migration: Add missing columns to bikes table
do $$
begin
  -- Add brand_id foreign key
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'brand_id') then
    alter table bikes add column brand_id uuid references bike_brands(id) on delete set null;
  end if;
  
  -- Add model_id foreign key
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'model_id') then
    alter table bikes add column model_id uuid references bike_models(id) on delete set null;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'customer_id') then
    alter table bikes add column customer_id uuid not null references customers(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'brand') then
    alter table bikes add column brand text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'model') then
    alter table bikes add column model text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'year') then
    alter table bikes add column year integer;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'serial_number') then
    alter table bikes add column serial_number text unique;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'color') then
    alter table bikes add column color text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'frame_size') then
    alter table bikes add column frame_size text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'wheel_size') then
    alter table bikes add column wheel_size text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'bike_type') then
    alter table bikes add column bike_type text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'purchase_date') then
    alter table bikes add column purchase_date date;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'purchase_price') then
    alter table bikes add column purchase_price numeric(12,2);
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'warranty_until') then
    alter table bikes add column warranty_until date;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'qr_code') then
    alter table bikes add column qr_code text unique;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'notes') then
    alter table bikes add column notes text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'image_url') then
    alter table bikes add column image_url text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'image_urls') then
    alter table bikes add column image_urls text[] not null default array[]::text[];
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'is_active') then
    alter table bikes add column is_active boolean not null default true;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'created_at') then
    alter table bikes add column created_at timestamp with time zone not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'updated_at') then
    alter table bikes add column updated_at timestamp with time zone not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'front_hub_spacing_mm') then
    alter table bikes add column front_hub_spacing_mm numeric(5,1);
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'rear_hub_spacing_mm') then
    alter table bikes add column rear_hub_spacing_mm numeric(5,1);
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'spoke_count') then
    alter table bikes add column spoke_count integer check (spoke_count in (24, 28, 32, 36, 40));
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'factory_rim_id') then
    alter table bikes add column factory_rim_id uuid references wheel_rims(id) on delete set null;
  end if;
end $$;

create index if not exists idx_bikes_tenant on bikes(tenant_id);
create index if not exists idx_bikes_customer_id on bikes(customer_id);
create index if not exists idx_bikes_brand_id on bikes(brand_id);
create index if not exists idx_bikes_model_id on bikes(model_id);
create index if not exists idx_bikes_serial_number on bikes(serial_number) where serial_number is not null;
create index if not exists idx_bikes_qr_code on bikes(qr_code) where qr_code is not null;
create index if not exists idx_bikes_brand_model on bikes using gin (to_tsvector('spanish', coalesce(brand || ' ' || model, '')));

-- Table: service_packages
-- Predefined service templates (e.g., "Basic Tune-up", "Full Overhaul")
create table if not exists service_packages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  description text,
  estimated_duration_hours numeric(5,2) not null default 1,
  base_labor_cost numeric(12,2) not null default 0,
  items jsonb not null default '[]'::jsonb, -- Array of {product_id, quantity, description}
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name) -- Each tenant has their own service packages
);

do $$ begin
  create index if not exists idx_service_packages_tenant on service_packages(tenant_id);
  create index if not exists idx_service_packages_name on service_packages using gin (to_tsvector('spanish', coalesce(name, '')));
exception
  when undefined_table then raise notice '⚠ Table service_packages does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in service_packages';
end $$;

-- Table: mechanic_jobs (pegas)
-- Main table for tracking service jobs/work orders
create table if not exists mechanic_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_number text not null unique default public.generate_mechanic_job_number(), -- Auto-generated: PG-00001
  customer_id uuid not null references customers(id) on delete cascade,
  bike_id uuid not null references bikes(id) on delete cascade,
  service_package_id uuid references service_packages(id) on delete set null,
  
  -- Dates and timeline
  arrival_date timestamp with time zone not null default now(),
  deadline timestamp with time zone,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  delivered_at timestamp with time zone,
  
  -- Status and priority
  -- NOTE: status CHECK constraint removed (Oct 2025) to support flexible job_statuses system
  -- Valid statuses are now managed via job_statuses table (Notion-style custom statuses)
  status text not null default 'PENDIENTE',
  priority text not null default 'NORMAL'
    check (priority in ('URGENTE','ALTA','NORMAL','BAJA')),
  
  -- Job details
  client_request text, -- What the client reported
  diagnosis text, -- Mechanic's diagnosis
  work_performed text, -- What was actually done
  notes text, -- Internal notes
  
  -- Assignment
  assigned_to uuid references customers(id) on delete set null, -- Will be employee_id when HR module exists
  assigned_technician_name text, -- Temporary until employees table exists
  
  -- Costs and invoicing
  estimated_cost numeric(12,2) not null default 0,
  final_cost numeric(12,2) not null default 0,
  parts_cost numeric(12,2) not null default 0,
  labor_cost numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  total_cost numeric(12,2) not null default 0,
  
  -- Invoicing
  invoice_id uuid references sales_invoices(id) on delete cascade, -- CHANGED: cascade delete instead of set null
  is_invoiced boolean not null default false,
  is_paid boolean not null default false,
  
  -- Warranty
  is_warranty_job boolean not null default false,
  warranty_notes text,
  
  -- Customer approval
  requires_approval boolean not null default false,
  approved_by_customer boolean not null default false,
  approved_at timestamp with time zone,
  
  -- Images and attachments
  image_urls text[] not null default array[]::text[],
  
  -- Soft delete
  deleted_at timestamp with time zone,
  deleted_by uuid references auth.users(id) on delete set null,
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add tax_treatment column to mechanic_jobs
alter table mechanic_jobs 
  add column if not exists tax_treatment text not null default 'no_tax' 
  check (tax_treatment in ('no_tax', 'tax_included'));

comment on column mechanic_jobs.tax_treatment is
  'Tax treatment for the invoice created from this job. no_tax = no IVA, tax_included = 19% IVA included';

-- Migration: Add missing columns to mechanic_jobs table
do $$
begin
  -- CRITICAL: Update foreign key constraint for invoice_id (from SET NULL to CASCADE)
  -- This ensures pega is deleted when invoice is deleted (bidirectional cascade)
  if exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'mechanic_jobs_invoice_id_fkey'
      and table_name = 'mechanic_jobs'
  ) then
    alter table mechanic_jobs drop constraint mechanic_jobs_invoice_id_fkey;
    alter table mechanic_jobs add constraint mechanic_jobs_invoice_id_fkey
      foreign key (invoice_id) references sales_invoices(id) on delete cascade;
    raise notice '✅ Updated mechanic_jobs.invoice_id foreign key to ON DELETE CASCADE';
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'job_number') then
    alter table mechanic_jobs add column job_number text not null unique;
  end if;
  -- Ensure job_number always auto-generates even on legacy tables
  alter table mechanic_jobs alter column job_number set default public.generate_mechanic_job_number();
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'customer_id') then
    alter table mechanic_jobs add column customer_id uuid not null references customers(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'bike_id') then
    alter table mechanic_jobs add column bike_id uuid not null references bikes(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'service_package_id') then
    alter table mechanic_jobs add column service_package_id uuid references service_packages(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'arrival_date') then
    alter table mechanic_jobs add column arrival_date timestamp with time zone not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'deadline') then
    alter table mechanic_jobs add column deadline timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'started_at') then
    alter table mechanic_jobs add column started_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'completed_at') then
    alter table mechanic_jobs add column completed_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'delivered_at') then
    alter table mechanic_jobs add column delivered_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'status') then
    alter table mechanic_jobs add column status text not null default 'PENDIENTE';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'priority') then
    alter table mechanic_jobs add column priority text not null default 'NORMAL';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'client_request') then
    alter table mechanic_jobs add column client_request text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'diagnosis') then
    alter table mechanic_jobs add column diagnosis text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'work_performed') then
    alter table mechanic_jobs add column work_performed text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'notes') then
    alter table mechanic_jobs add column notes text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'assigned_to') then
    alter table mechanic_jobs add column assigned_to uuid references customers(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'assigned_technician_name') then
    alter table mechanic_jobs add column assigned_technician_name text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'estimated_cost') then
    alter table mechanic_jobs add column estimated_cost numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'final_cost') then
    alter table mechanic_jobs add column final_cost numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'parts_cost') then
    alter table mechanic_jobs add column parts_cost numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'labor_cost') then
    alter table mechanic_jobs add column labor_cost numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'discount_amount') then
    alter table mechanic_jobs add column discount_amount numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'tax_amount') then
    alter table mechanic_jobs add column tax_amount numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'total_cost') then
    alter table mechanic_jobs add column total_cost numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'invoice_id') then
    alter table mechanic_jobs add column invoice_id uuid references sales_invoices(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'is_invoiced') then
    alter table mechanic_jobs add column is_invoiced boolean not null default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'is_paid') then
    alter table mechanic_jobs add column is_paid boolean not null default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'is_warranty_job') then
    alter table mechanic_jobs add column is_warranty_job boolean not null default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'warranty_notes') then
    alter table mechanic_jobs add column warranty_notes text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'requires_approval') then
    alter table mechanic_jobs add column requires_approval boolean not null default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'approved_by_customer') then
    alter table mechanic_jobs add column approved_by_customer boolean not null default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'approved_at') then
    alter table mechanic_jobs add column approved_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'image_urls') then
    alter table mechanic_jobs add column image_urls text[] not null default array[]::text[];
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'deleted_at') then
    alter table mechanic_jobs add column deleted_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'deleted_by') then
    alter table mechanic_jobs add column deleted_by uuid references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'created_at') then
    alter table mechanic_jobs add column created_at timestamp with time zone not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_jobs' and column_name = 'updated_at') then
    alter table mechanic_jobs add column updated_at timestamp with time zone not null default now();
  end if;
end $$;

do $$ begin
  create index if not exists idx_mechanic_jobs_tenant on mechanic_jobs(tenant_id);
  create index if not exists idx_mechanic_jobs_customer_id on mechanic_jobs(customer_id);
  create index if not exists idx_mechanic_jobs_bike_id on mechanic_jobs(bike_id);
  create index if not exists idx_mechanic_jobs_status on mechanic_jobs(status);
  create index if not exists idx_mechanic_jobs_priority on mechanic_jobs(priority);
  create index if not exists idx_mechanic_jobs_assigned_to on mechanic_jobs(assigned_to) where assigned_to is not null;
  create index if not exists idx_mechanic_jobs_deadline on mechanic_jobs(deadline) where deadline is not null;
  create index if not exists idx_mechanic_jobs_job_number on mechanic_jobs(job_number);
exception
  when undefined_table then raise notice '⚠ Table mechanic_jobs does not exist';
  when undefined_column then raise notice '⚠ Column missing in mechanic_jobs';
end $$;

-- ============================================================
-- TABLE: mechanic_job_bikes (MULTI-BIKE SUPPORT)
-- ============================================================
-- Links bikes to jobs with per-bike details
-- Each bike in a job has its own: diagnosis, items, notes, costs, STATUS
create table if not exists mechanic_job_bikes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  bike_id uuid not null references bikes(id) on delete cascade,
  order_index integer not null default 0,
  
  -- Per-bike status (each bike can have independent status)
  status_id uuid references job_statuses(id) on delete set null,
  
  -- Per-bike work details
  diagnosis text,
  work_requested text,        -- Solicitud del cliente (per bike)
  work_performed text,        -- Lo que se hizo
  technician_notes text,      -- Notas del técnico
  
  -- Per-bike cost tracking (calculated from items)
  parts_cost numeric(12,2) not null default 0,
  labor_cost numeric(12,2) not null default 0,
  subtotal numeric(12,2) not null default 0,
  
  -- Per-bike flags
  is_warranty_work boolean not null default false,
  requires_approval boolean not null default false,
  approved_by_customer boolean not null default false,
  approved_at timestamp with time zone,
  
  -- Images for this specific bike work
  image_urls text[] not null default array[]::text[],
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add status_id column if not exists (for existing tables)
alter table mechanic_job_bikes add column if not exists status_id uuid references job_statuses(id) on delete set null;

-- Indexes for mechanic_job_bikes
create index if not exists idx_mechanic_job_bikes_tenant on mechanic_job_bikes(tenant_id);
create index if not exists idx_mechanic_job_bikes_job on mechanic_job_bikes(job_id);
create index if not exists idx_mechanic_job_bikes_bike on mechanic_job_bikes(bike_id);
create index if not exists idx_mechanic_job_bikes_status on mechanic_job_bikes(status_id);

-- Unique constraint: each bike can only appear once per job
do $$ begin
  alter table mechanic_job_bikes drop constraint if exists mechanic_job_bikes_job_bike_unique;
  alter table mechanic_job_bikes add constraint mechanic_job_bikes_job_bike_unique unique (job_id, bike_id);
exception when others then null;
end $$;

-- Enable RLS for mechanic_job_bikes
alter table mechanic_job_bikes enable row level security;

drop policy if exists "mechanic_job_bikes_select" on mechanic_job_bikes;
drop policy if exists "mechanic_job_bikes_insert" on mechanic_job_bikes;
drop policy if exists "mechanic_job_bikes_update" on mechanic_job_bikes;
drop policy if exists "mechanic_job_bikes_delete" on mechanic_job_bikes;

create policy "mechanic_job_bikes_select" on mechanic_job_bikes
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_bikes_insert" on mechanic_job_bikes
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "mechanic_job_bikes_update" on mechanic_job_bikes
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_bikes_delete" on mechanic_job_bikes
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Table: mechanic_job_items
-- Parts/products used in a job
create table if not exists mechanic_job_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  job_bike_id uuid references mechanic_job_bikes(id) on delete cascade, -- Multi-bike support
  product_id uuid references products(id) on delete set null,
  product_name text not null, -- Cached in case product is deleted
  product_sku text,
  quantity numeric(10,2) not null default 1,
  unit_price numeric(12,2) not null default 0,
  total_price numeric(12,2) not null default 0,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'job_id') then
    alter table mechanic_job_items add column job_id uuid not null references mechanic_jobs(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'product_id') then
    alter table mechanic_job_items add column product_id uuid references products(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'product_name') then
    alter table mechanic_job_items add column product_name text not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'product_sku') then
    alter table mechanic_job_items add column product_sku text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'quantity') then
    alter table mechanic_job_items add column quantity numeric(10,2) not null default 1;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'unit_price') then
    alter table mechanic_job_items add column unit_price numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'total_price') then
    alter table mechanic_job_items add column total_price numeric(12,2) not null default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'notes') then
    alter table mechanic_job_items add column notes text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'created_at') then
    alter table mechanic_job_items add column created_at timestamp with time zone not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'updated_at') then
    alter table mechanic_job_items add column updated_at timestamp with time zone not null default now();
  end if;
  -- Multi-bike support: add job_bike_id column
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'job_bike_id') then
    alter table mechanic_job_items add column job_bike_id uuid references mechanic_job_bikes(id) on delete cascade;
    raise notice '✅ Added job_bike_id column to mechanic_job_items';
  end if;
end $$;

create index if not exists idx_mechanic_job_items_job_id on mechanic_job_items(job_id);
create index if not exists idx_mechanic_job_items_product_id on mechanic_job_items(product_id) where product_id is not null;
create index if not exists idx_mechanic_job_items_job_bike on mechanic_job_items(job_bike_id) where job_bike_id is not null;

-- ✅ PHASE 1: Add columns to unify items and services
-- item_type: 'product' (from products table), 'service' (from labor/services), 'adhoc' (manual entry)
-- service_product_id: For services that reference products table (like labor does)
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'item_type') then
    alter table mechanic_job_items add column item_type text not null default 'product' check (item_type in ('product', 'service', 'adhoc'));
    raise notice '✅ Added item_type column to mechanic_job_items';
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_items' and column_name = 'service_product_id') then
    alter table mechanic_job_items add column service_product_id uuid references products(id) on delete set null;
    raise notice '✅ Added service_product_id column to mechanic_job_items';
  end if;
  
  -- Add index for service lookups
  if not exists (select 1 from pg_indexes where tablename = 'mechanic_job_items' and indexname = 'idx_mechanic_job_items_service_product_id') then
    create index idx_mechanic_job_items_service_product_id on mechanic_job_items(service_product_id) where service_product_id is not null;
    raise notice '✅ Added index for service_product_id';
  end if;
end $$;

drop function if exists mirror_labor_to_items_insert cascade;
drop function if exists mirror_labor_to_items_update cascade;
drop function if exists mirror_labor_to_items_delete cascade;
drop table if exists mechanic_job_labor cascade;

-- ============================================================
-- TABLE: mechanic_job_tasks (SMART TASKS SYSTEM)
-- ============================================================
-- Smart task checklist for mechanic jobs
-- Features:
-- - Auto-parsed from product/service descriptions
-- - Ad-hoc tasks with optional pricing
-- - Hierarchical (linked to parent items/labor)
-- - Completion tracking with timestamps
-- - Three-way sync with invoice and pega forms
create table if not exists mechanic_job_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  job_bike_id uuid references mechanic_job_bikes(id) on delete cascade, -- Multi-bike support
  
  -- Link to parent product/service (PRIMARY KEY BINDING)
  -- NULL = standalone ad-hoc task
  parent_item_id uuid references mechanic_job_items(id) on delete cascade,
  
  -- Task details
  task_name text not null,
  task_description text,
  is_completed boolean not null default false,
  completed_at timestamp with time zone,
  completed_by_user_id uuid references auth.users(id) on delete set null,
  
  -- Ad-hoc pricing (creates additional line item when set)
  is_adhoc boolean not null default false,
  adhoc_price numeric(12,2), -- NULL = included in parent, NOT NULL = separate charge
  adhoc_item_id uuid references mechanic_job_items(id) on delete set null, -- Link to auto-created item
  
  -- Linking behavior
  is_standalone boolean not null default false, -- true = not linked to any parent
  
  -- Smart features
  parsed_from_description boolean not null default false, -- Auto-generated from P/S description
  display_order integer not null default 0, -- User can reorder tasks
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  
  -- Constraints
  check (
    -- Ad-hoc task must have price if it's not free
    (is_adhoc = false) OR 
    (is_adhoc = true and (adhoc_price is null or adhoc_price >= 0))
  ),
  check (
    -- Must have parent OR be standalone
    parent_item_id is not null OR
    is_standalone = true
  )
);

-- Add columns if not exist (migration safety)
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'tenant_id') then
    alter table mechanic_job_tasks add column tenant_id uuid references tenants(id) on delete cascade not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'job_id') then
    alter table mechanic_job_tasks add column job_id uuid not null references mechanic_jobs(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'parent_item_id') then
    alter table mechanic_job_tasks add column parent_item_id uuid references mechanic_job_items(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'task_name') then
    alter table mechanic_job_tasks add column task_name text;
    update mechanic_job_tasks set task_name = 'Task' where task_name is null;
    alter table mechanic_job_tasks alter column task_name set not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'task_description') then
    alter table mechanic_job_tasks add column task_description text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_completed') then
    alter table mechanic_job_tasks add column is_completed boolean;
    update mechanic_job_tasks set is_completed = false where is_completed is null;
    alter table mechanic_job_tasks alter column is_completed set not null;
    alter table mechanic_job_tasks alter column is_completed set default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'completed_at') then
    alter table mechanic_job_tasks add column completed_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'completed_by_user_id') then
    alter table mechanic_job_tasks add column completed_by_user_id uuid references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_adhoc') then
    alter table mechanic_job_tasks add column is_adhoc boolean;
    update mechanic_job_tasks set is_adhoc = false where is_adhoc is null;
    alter table mechanic_job_tasks alter column is_adhoc set not null;
    alter table mechanic_job_tasks alter column is_adhoc set default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'adhoc_price') then
    alter table mechanic_job_tasks add column adhoc_price numeric(12,2);
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'adhoc_item_id') then
    alter table mechanic_job_tasks add column adhoc_item_id uuid references mechanic_job_items(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_standalone') then
    alter table mechanic_job_tasks add column is_standalone boolean;
    update mechanic_job_tasks set is_standalone = false where is_standalone is null;
    alter table mechanic_job_tasks alter column is_standalone set not null;
    alter table mechanic_job_tasks alter column is_standalone set default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'parsed_from_description') then
    alter table mechanic_job_tasks add column parsed_from_description boolean;
    update mechanic_job_tasks set parsed_from_description = false where parsed_from_description is null;
    alter table mechanic_job_tasks alter column parsed_from_description set not null;
    alter table mechanic_job_tasks alter column parsed_from_description set default false;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'display_order') then
    alter table mechanic_job_tasks add column display_order integer;
    update mechanic_job_tasks set display_order = 0 where display_order is null;
    alter table mechanic_job_tasks alter column display_order set not null;
    alter table mechanic_job_tasks alter column display_order set default 0;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'created_at') then
    alter table mechanic_job_tasks add column created_at timestamp with time zone;
    update mechanic_job_tasks set created_at = now() where created_at is null;
    alter table mechanic_job_tasks alter column created_at set not null;
    alter table mechanic_job_tasks alter column created_at set default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'updated_at') then
    alter table mechanic_job_tasks add column updated_at timestamp with time zone;
    update mechanic_job_tasks set updated_at = now() where updated_at is null;
    alter table mechanic_job_tasks alter column updated_at set not null;
    alter table mechanic_job_tasks alter column updated_at set default now();
  end if;
  -- Multi-bike support: add job_bike_id column
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'job_bike_id') then
    alter table mechanic_job_tasks add column job_bike_id uuid references mechanic_job_bikes(id) on delete cascade;
    raise notice '✅ Added job_bike_id column to mechanic_job_tasks';
  end if;
  
  -- ============================================================
  -- MIGRATION: Drop old task schema columns (Nov 18, 2025)
  -- ============================================================
  -- Remove old columns: title, status, task_type, job_item_id, job_labor_id
  -- These were replaced by: task_name, is_completed, parent_item_id, parent_labor_id
  
  -- Drop old constraints first
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'title') then
    -- Drop NOT NULL constraint if exists
    alter table mechanic_job_tasks alter column title drop not null;
    alter table mechanic_job_tasks drop column title cascade;
    raise notice 'Dropped old column: title';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'status') then
    alter table mechanic_job_tasks drop column status cascade;
    raise notice 'Dropped old column: status';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'task_type') then
    alter table mechanic_job_tasks drop column task_type cascade;
    raise notice 'Dropped old column: task_type';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'job_item_id') then
    alter table mechanic_job_tasks drop column job_item_id cascade;
    raise notice 'Dropped old column: job_item_id';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'job_labor_id') then
    alter table mechanic_job_tasks drop column job_labor_id cascade;
    raise notice 'Dropped old column: job_labor_id';
  end if;

  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'parent_labor_id') then
    update mechanic_job_tasks t
    set parent_item_id = coalesce(parent_item_id, mi.id)
    from mechanic_job_items mi
    where t.parent_labor_id is not null
      and mi.job_id = t.job_id
      and mi.item_type = 'service'
      and mi.notes = 'Mirrored from labor ID: ' || t.parent_labor_id::text;
    alter table mechanic_job_tasks drop column parent_labor_id cascade;
    raise notice 'Dropped old column: parent_labor_id';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'priority') then
    alter table mechanic_job_tasks drop column priority cascade;
    raise notice 'Dropped old column: priority';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'assigned_to') then
    alter table mechanic_job_tasks drop column assigned_to cascade;
    raise notice 'Dropped old column: assigned_to';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'assigned_technician_name') then
    alter table mechanic_job_tasks drop column assigned_technician_name cascade;
    raise notice 'Dropped old column: assigned_technician_name';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'estimated_duration_minutes') then
    alter table mechanic_job_tasks drop column estimated_duration_minutes cascade;
    raise notice 'Dropped old column: estimated_duration_minutes';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'started_at') then
    alter table mechanic_job_tasks drop column started_at cascade;
    raise notice 'Dropped old column: started_at';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_auto_generated') then
    alter table mechanic_job_tasks drop column is_auto_generated cascade;
    raise notice 'Dropped old column: is_auto_generated';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'description') then
    alter table mechanic_job_tasks drop column description cascade;
    raise notice 'Dropped old column: description';
  end if;
end $$;

create index if not exists idx_mechanic_job_tasks_tenant on mechanic_job_tasks(tenant_id);
create index if not exists idx_mechanic_job_tasks_job on mechanic_job_tasks(job_id);
create index if not exists idx_mechanic_job_tasks_parent_item on mechanic_job_tasks(parent_item_id) where parent_item_id is not null;
create index if not exists idx_mechanic_job_tasks_completion on mechanic_job_tasks(is_completed, job_id);

-- ============================================================
-- TABLE: mechanic_job_task_preferences (USER COLLAPSE STATE)
-- ============================================================
-- Stores per-user, per-job UI preferences for task collapsing
create table if not exists mechanic_job_task_preferences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  
  -- Which parent items/labor are collapsed (array of IDs)
  collapsed_item_ids uuid[] not null default '{}',
  
  updated_at timestamp with time zone not null default now(),
  
  unique(user_id, job_id)
);

create index if not exists idx_task_prefs_user_job on mechanic_job_task_preferences(user_id, job_id);
create index if not exists idx_task_prefs_tenant on mechanic_job_task_preferences(tenant_id);

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'mechanic_job_task_preferences'
      and column_name = 'collapsed_labor_ids'
  ) then
    update mechanic_job_task_preferences prefs
    set collapsed_item_ids = coalesce(
      (
        select array_agg(distinct merged.item_id)
        from (
          select unnest(coalesce(prefs.collapsed_item_ids, '{}')) as item_id
          union
          select mi.id
          from mechanic_job_items mi
          join unnest(coalesce(prefs.collapsed_labor_ids, '{}')) as labor_map(labor_id)
            on mi.job_id = prefs.job_id
           and mi.item_type = 'service'
           and mi.notes = 'Mirrored from labor ID: ' || labor_map.labor_id::text
        ) merged
      ),
      '{}'
    )
    where prefs.collapsed_labor_ids is not null
      and array_length(prefs.collapsed_labor_ids, 1) > 0;

    alter table mechanic_job_task_preferences drop column collapsed_labor_ids cascade;
    raise notice 'Dropped old column: collapsed_labor_ids';
  end if;
end $$;
-- Table: mechanic_job_timeline
-- Audit trail / history of status changes and events
create table if not exists mechanic_job_timeline (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  event_type text not null check (event_type in (
    'created',
    'status_changed',
    'assigned',
    'diagnosis_added',
    'parts_added',
    'labor_added',
    'photo_added',
    'note_added',
    'approved',
    'invoiced',
    'paid',
    'completed',
    'delivered'
  )),
  old_value text,
  new_value text,
  description text,
  created_by uuid references customers(id) on delete set null, -- Will be user_id
  created_by_name text,
  created_at timestamp with time zone not null default now()
);

do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'job_id') then
    alter table mechanic_job_timeline add column job_id uuid not null references mechanic_jobs(id) on delete cascade;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'event_type') then
    alter table mechanic_job_timeline add column event_type text not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'old_value') then
    alter table mechanic_job_timeline add column old_value text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'new_value') then
    alter table mechanic_job_timeline add column new_value text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'description') then
    alter table mechanic_job_timeline add column description text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'created_by') then
    alter table mechanic_job_timeline add column created_by uuid references customers(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'created_by_name') then
    alter table mechanic_job_timeline add column created_by_name text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_timeline' and column_name = 'created_at') then
    alter table mechanic_job_timeline add column created_at timestamp with time zone not null default now();
  end if;
end $$;

create index if not exists idx_mechanic_job_timeline_job_id on mechanic_job_timeline(job_id);
create index if not exists idx_mechanic_job_timeline_created_at on mechanic_job_timeline(created_at desc);

-- ============================================================
-- ❌ OLD LEGACY TASK FUNCTIONS REMOVED (Nov 18, 2025)
-- ============================================================
-- The following OLD functions have been COMPLETELY REMOVED:
--   - auto_create_task_for_job_item() 
--   - auto_create_task_for_job_labor()
--   - sync_tasks_with_job_status()
--   - get_job_task_summary()
--   - trg_auto_create_task_for_item
--   - trg_auto_create_task_for_labor
--   - trg_sync_tasks_with_job_status
--
-- The NEW smart task system uses:
--   - auto_parse_item_description() (line ~12100)
--   - Automatically parses bullet points from descriptions
--   - Creates sub-tasks linked to parent products/services
-- ============================================================

-- ============================================================
-- MECHANIC JOB COST CALCULATION TRIGGERS
-- Auto-update parts_cost, labor_cost, and total_cost in mechanic_jobs
-- when items or labor are added/updated/deleted
-- ============================================================

-- Function: Recalculate mechanic job costs
create or replace function public.update_mechanic_job_costs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parts_cost numeric;
  v_labor_cost numeric;
  v_total_cost numeric;
begin
  -- Calculate parts cost (everything except service-type items)
  select coalesce(sum(total_price), 0)
  into v_parts_cost
  from mechanic_job_items
  where job_id = coalesce(NEW.job_id, OLD.job_id)
    and coalesce(item_type, 'product') <> 'service';
  
  -- Calculate labor cost (service-type items)
  select coalesce(sum(total_price), 0)
  into v_labor_cost
  from mechanic_job_items
  where job_id = coalesce(NEW.job_id, OLD.job_id)
    and coalesce(item_type, 'product') = 'service';
  
  -- Calculate total
  v_total_cost := v_parts_cost + v_labor_cost;
  
  -- Update mechanic_jobs table
  update mechanic_jobs
  set 
    parts_cost = v_parts_cost,
    labor_cost = v_labor_cost,
    total_cost = v_total_cost,
    updated_at = now()
  where id = coalesce(NEW.job_id, OLD.job_id);
  
  return coalesce(NEW, OLD);
end;
$$;

-- Triggers for mechanic_job_items
drop trigger if exists trg_update_job_costs_on_item_insert on mechanic_job_items;
create trigger trg_update_job_costs_on_item_insert
  after insert on mechanic_job_items
  for each row
  execute function public.update_mechanic_job_costs();

drop trigger if exists trg_update_job_costs_on_item_update on mechanic_job_items;
create trigger trg_update_job_costs_on_item_update
  after update on mechanic_job_items
  for each row
  when (OLD.total_price is distinct from NEW.total_price)
  execute function public.update_mechanic_job_costs();

drop trigger if exists trg_update_job_costs_on_item_delete on mechanic_job_items;
create trigger trg_update_job_costs_on_item_delete
  after delete on mechanic_job_items
  for each row
  execute function public.update_mechanic_job_costs();

-- ============================================================
-- BIKESHOP MODULE - Trigger Functions and Business Logic
-- ============================================================

-- Function: Cascade delete between mechanic jobs and invoices
-- When a pega is deleted, also delete its associated invoice
-- When an invoice is deleted, also delete its associated pega
-- ============================================================
-- BIDIRECTIONAL CASCADE DELETE - Trigger Approach (RLS-Compatible)
-- ============================================================
-- Foreign key CASCADE doesn't work with RLS policies, so we use triggers
-- with SECURITY DEFINER to bypass RLS when cascading deletes.
-- ============================================================

create or replace function public.cascade_delete_pega_invoice()
returns trigger
language plpgsql
security definer  -- Run with function owner's privileges (bypasses RLS)
set search_path = public
as $$
declare
  v_count int;
  v_recursion_guard boolean;
  v_pega_id uuid;
  v_invoice_id uuid;
begin
  -- Get recursion guard from transaction-level setting
  begin
    v_recursion_guard := current_setting('app.cascade_delete_in_progress', true)::boolean;
  exception
    when others then
      v_recursion_guard := false;
  end;
  
  -- If already in recursion, skip to prevent infinite loop
  if v_recursion_guard then
    raise notice '⏭️ Skipping cascade (recursion guard active)';
    return OLD;
  end if;
  
  -- Set recursion guard
  perform set_config('app.cascade_delete_in_progress', 'true', true);
  
  -- Handle invoice deletion → delete pega
  if TG_TABLE_NAME = 'sales_invoices' then
    raise notice '🗑️ [TRIGGER] Invoice % deleted (tenant=%)', OLD.id, OLD.tenant_id;
    
    -- Find linked pegas
    select id into v_pega_id
    from mechanic_jobs
    where invoice_id = OLD.id 
      and tenant_id = OLD.tenant_id
    limit 1;
    
    if v_pega_id is not null then
      raise notice '🔍 Found pega % linked to invoice %', v_pega_id, OLD.id;
      
      -- Delete using direct SQL (SECURITY DEFINER bypasses RLS)
      execute format('delete from mechanic_jobs where id = %L', v_pega_id);
      
      get diagnostics v_count = ROW_COUNT;
      
      if v_count > 0 then
        raise notice '✅ Deleted pega % linked to invoice %', v_pega_id, OLD.id;
      else
        raise notice '❌ Failed to delete pega %', v_pega_id;
      end if;
    else
      raise notice '⚠️ No pega found with invoice_id=%', OLD.id;
    end if;
  end if;

  -- Handle pega deletion → delete invoice  
  if TG_TABLE_NAME = 'mechanic_jobs' then
    if OLD.invoice_id is not null then
      raise notice '🗑️ [TRIGGER] Pega % deleted (tenant=%)', OLD.id, OLD.tenant_id;
      raise notice '🔍 Looking for linked invoice %', OLD.invoice_id;
      
      -- Verify invoice exists
      select id into v_invoice_id
      from sales_invoices
      where id = OLD.invoice_id
        and tenant_id = OLD.tenant_id;
      
      if v_invoice_id is not null then
        raise notice '🔍 Found invoice % linked to pega %', v_invoice_id, OLD.id;
        
        -- Delete using direct SQL (SECURITY DEFINER bypasses RLS)
        execute format('delete from sales_invoices where id = %L', v_invoice_id);
        
        get diagnostics v_count = ROW_COUNT;
        
        if v_count > 0 then
          raise notice '✅ Deleted invoice % linked to pega %', v_invoice_id, OLD.id;
        else
          raise notice '❌ Failed to delete invoice %', v_invoice_id;
        end if;
      else
        raise notice '⚠️ Invoice % not found (may already be deleted)', OLD.invoice_id;
      end if;
    else
      raise notice '⚠️ Pega % has no linked invoice_id', OLD.id;
    end if;
  end if;
  
  -- Clear recursion guard
  perform set_config('app.cascade_delete_in_progress', 'false', true);
  
  return OLD;
exception
  when others then
    -- Clear recursion guard on error
    perform set_config('app.cascade_delete_in_progress', 'false', true);
    raise notice '❌ ERROR in cascade_delete_pega_invoice: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    return OLD;
end;
$$;

-- Create triggers for BOTH directions
drop trigger if exists trg_delete_pega_cascade_invoice on mechanic_jobs cascade;
create trigger trg_delete_pega_cascade_invoice
  after delete on mechanic_jobs
  for each row
  execute function public.cascade_delete_pega_invoice();

drop trigger if exists trg_delete_invoice_cascade_pega on sales_invoices cascade;
create trigger trg_delete_invoice_cascade_pega
  after delete on sales_invoices
  for each row
  execute function public.cascade_delete_pega_invoice();

-- Function: Auto-generate job number (PG-#####)
-- Sequence for generating unique mechanic job numbers
drop sequence if exists public.mechanic_job_number_seq cascade;
create sequence public.mechanic_job_number_seq
  start with 1
  increment by 1
  no cycle;

-- Function: Generate unique mechanic job number (uses sequence - no race conditions)
create or replace function public.generate_mechanic_job_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_number integer;
  v_job_number text;
begin
  -- Get next value from sequence (guaranteed unique, no race conditions)
  v_next_number := nextval('public.mechanic_job_number_seq');
  
  -- Format as PG-00001, PG-00002, etc.
  v_job_number := 'PG-' || lpad(v_next_number::text, 5, '0');
  
  return v_job_number;
end;
$$;

-- Function: Recalculate mechanic job costs
-- Sums parts and labor, applies tax, calculates total
create or replace function public.recalculate_mechanic_job_costs(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_tax_amount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_tax_rate numeric(5,4) := 0.19; -- 19% IVA in Chile
begin
  if p_job_id is null then
    return;
  end if;

  -- Sum parts cost
  select coalesce(sum(total_price), 0)
  into v_parts_cost
  from mechanic_job_items
  where job_id = p_job_id
    and coalesce(item_type, 'product') <> 'service';

  -- Sum labor cost (service-type items)
  select coalesce(sum(total_price), 0)
  into v_labor_cost
  from mechanic_job_items
  where job_id = p_job_id
    and coalesce(item_type, 'product') = 'service';

  -- Get current discount from job
  select coalesce(discount_amount, 0)
  into v_discount
  from mechanic_jobs
  where id = p_job_id;

  -- Calculate totals
  v_subtotal := v_parts_cost + v_labor_cost;
  v_tax_amount := (v_subtotal - v_discount) * v_tax_rate;
  v_total := v_subtotal - v_discount + v_tax_amount;

  -- Update job costs
  update mechanic_jobs
  set
    parts_cost = v_parts_cost,
    labor_cost = v_labor_cost,
    final_cost = v_subtotal,
    tax_amount = v_tax_amount,
    total_cost = v_total,
    updated_at = now()
  where id = p_job_id;

  raise notice 'Recalculated job % costs: parts=%, labor=%, total=%', p_job_id, v_parts_cost, v_labor_cost, v_total;
end;
$$;

-- Function: Create sales invoice from mechanic job
-- Automatically creates an invoice with parts, labor, and IVA (19%)
-- Called AFTER job insert to link job to invoice
-- ============================================================================
-- PEGA (MECHANIC JOB) → INVOICE AUTOMATIC LINKING (Updated Nov 3, 2025)
-- ============================================================================
-- CHANGES:
-- 1. Use job.arrival_date instead of job.created_at for invoice date
-- 2. Allow invoice creation even with empty items (draft for future work)
-- 3. Invoice created as 'draft' status for user review before posting
-- ============================================================================

create or replace function public.create_invoice_from_mechanic_job(p_job_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_customer record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_invoice_date timestamp with time zone;
  v_subtotal numeric(12,2) := 0;
  v_iva numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_items jsonb := '[]'::jsonb;
  v_item_counter integer := 0;
  v_job_item record;
  v_tenant_id uuid;
begin
  -- Get job details
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id;
  
  if not found then
    raise notice 'Job % not found', p_job_id;
    return null;
  end if;
  
  v_tenant_id := v_job.tenant_id;
  
  -- Ensure job totals are current before creating invoice
  perform public.recalculate_mechanic_job_costs(p_job_id);

  -- If invoice already exists, don't create another
  if v_job.invoice_id is not null then
    raise notice 'Job % already has invoice %', p_job_id, v_job.invoice_id;
    return v_job.invoice_id;
  end if;
  
  -- Get customer details
  select * into v_customer
  from public.customers
  where id = v_job.customer_id;
  
  if not found then
    raise notice 'Customer % not found for job %', v_job.customer_id, p_job_id;
    return null;
  end if;
  
  -- ✅ CRITICAL FIX: Use arrival_date instead of created_at for invoice date
  -- This ensures invoice date matches when the job/work actually started
  v_invoice_date := coalesce(v_job.arrival_date, v_job.created_at);
  
  -- Add items (products + services) from mechanic_job_items
  for v_job_item in
    select 
      product_id,
      service_product_id,
      product_name,
      quantity,
      unit_price,
      total_price,
      item_type
    from public.mechanic_job_items
    where job_id = p_job_id
    order by created_at
  loop
    v_item_counter := v_item_counter + 1;

    v_items := v_items || jsonb_build_object(
      'id', gen_random_uuid()::text,
      'product_id', case when coalesce(v_job_item.item_type, 'product') = 'service'
                         then coalesce(v_job_item.service_product_id::text, '')
                         else coalesce(v_job_item.product_id::text, '')
                    end,
      'product_name', v_job_item.product_name,
      'quantity', v_job_item.quantity,
      'unit_price', v_job_item.unit_price,
      'discount', 0,
      'line_total', coalesce(v_job_item.total_price, v_job_item.quantity * v_job_item.unit_price, 0),
      'cost', 0
    );

    v_subtotal := v_subtotal + coalesce(v_job_item.total_price, v_job_item.quantity * v_job_item.unit_price, 0);
  end loop;
  
  -- ✅ CHANGED: Allow invoice creation even with empty items
  -- Draft invoices can be created for future work planning
  -- User can add items later before posting
  
  -- Calculate IVA based on job's tax treatment
  -- ✅ FIX: Read tax_treatment from job instead of hardcoding
  if v_job.tax_treatment = 'tax_included' then
    -- Tax included: net = subtotal ÷ 1.19, iva = subtotal - net
    v_iva := round(v_subtotal - (v_subtotal / 1.19), 2);
  else
    -- No tax: iva = 0
    v_iva := 0;
  end if;
  
  v_total := v_subtotal;  -- Total is always the subtotal (what customer pays)
  
  -- Generate invoice number using new sequential system
  v_invoice_number := public.get_next_document_number(v_tenant_id, 'sales_invoice');
  
  -- Create the invoice with status 'draft' for user review
  insert into public.sales_invoices (
    tenant_id,
    invoice_number,
    customer_id,
    customer_name,
    customer_rut,
    date,
    due_date,
    reference,
    status,
    subtotal,
    iva_amount,
    net_amount,
    tax_treatment,
    total,
    paid_amount,
    balance,
    items,
    created_at,
    updated_at
  ) values (
    v_tenant_id,
    v_invoice_number,
    v_customer.id,
    v_customer.name,
    v_customer.rut,
    v_invoice_date,  -- ✅ Now uses arrival_date
    v_invoice_date + interval '30 days',  -- 30-day payment terms
    'Pega ' || v_job.job_number,
    'draft',  -- Always start as draft for review
    v_subtotal,
    v_iva,
    case 
      when v_job.tax_treatment = 'tax_included' then v_subtotal / 1.19
      else v_subtotal
    end,  -- net_amount
    v_job.tax_treatment,  -- tax_treatment from job
    v_total,
    0,  -- Not paid yet
    v_total,  -- Full balance pending
    v_items,
    now(),
    now()
  ) returning id into v_invoice_id;
  
  -- Link invoice to job
  update public.mechanic_jobs
  set invoice_id = v_invoice_id,
      is_invoiced = true,
      updated_at = now()
  where id = p_job_id;
  
  raise notice 'Created draft invoice % for job % (customer: %, date: %, total: $%)', 
    v_invoice_id, v_job.job_number, v_customer.name, v_invoice_date, v_total;
  
  return v_invoice_id;
end;
$$;

-- ============================================================================
-- AUTO-CREATE INVOICE TRIGGER FOR NEW PEGAS
-- ============================================================================
-- Automatically creates a draft invoice when a new pega is created
-- This ensures strong bidirectional linking from the moment of creation
-- ============================================================================

create or replace function public.auto_create_invoice_for_new_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
begin
  -- Only create invoice if customer is specified
  if NEW.customer_id is not null then
    -- Create draft invoice linked to this job
    -- Job now exists in DB (AFTER INSERT), so function can query it
    v_invoice_id := public.create_invoice_from_mechanic_job(NEW.id);
    
    -- Update the job record with the invoice_id
    if v_invoice_id is not null then
      update public.mechanic_jobs
      set invoice_id = v_invoice_id,
          is_invoiced = true
      where id = NEW.id;
      
      raise notice 'Auto-created invoice % for new pega %', v_invoice_id, NEW.job_number;
    end if;
  end if;
  
  return NEW;
end;
$$;

-- Drop old trigger if exists
drop trigger if exists trg_auto_create_invoice_for_job on public.mechanic_jobs;

-- Create trigger to auto-create invoice on pega INSERT
-- CHANGED TO AFTER INSERT so job exists in DB when function queries it
create trigger trg_auto_create_invoice_for_job
  after insert on public.mechanic_jobs
  for each row
  execute function public.auto_create_invoice_for_new_job();

-- ============================================================================
-- SYNC INVOICE CHANGES BACK TO PEGA (Bidirectional Sync)
-- ============================================================================
-- When invoice items are modified, sync them back to the mechanic job
-- This ensures pega always reflects the latest invoice state
-- ============================================================================

create or replace function public.sync_invoice_to_job_on_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
begin
  -- Skip if invoice is not linked to a pega
  -- Check if this invoice references a mechanic job
  select id into v_job_id
  from public.mechanic_jobs
  where invoice_id = NEW.id
  limit 1;
  
  if v_job_id is null then
    -- Not a pega-linked invoice, skip sync
    return NEW;
  end if;
  
  -- Skip if this UPDATE was triggered by job → invoice sync
  if current_setting('app.syncing_job_to_invoice', true) = 'true' then
    raise notice 'Skipping invoice→job sync (job→invoice sync in progress)';
    return NEW;
  end if;

  -- Prevent circular triggers (invoice → job → invoice → ...)
  -- Check if we're already inside a job sync operation
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then
    raise notice 'Skipping invoice→job sync (circular prevention)';
    return NEW;
  end if;
  
  -- Set flag to prevent circular sync
  perform set_config('app.syncing_invoice_to_job', 'true', true);
  
  -- Call existing sync function to update job items from invoice
  -- Function only needs invoice_id, it finds the job internally
  perform public.sync_invoice_items_to_job(NEW.id);
  
  raise notice 'Synced invoice % changes to pega %', NEW.id, v_job_id;
  
  return NEW;
end;
$$;

-- Drop old trigger if exists
drop trigger if exists trg_sync_invoice_to_job on public.sales_invoices;

-- Create trigger to sync invoice changes to job
create trigger trg_sync_invoice_to_job
  after update of items on public.sales_invoices
  for each row
  when (OLD.items is distinct from NEW.items)
  execute function public.sync_invoice_to_job_on_change();

-- ============================================================================
-- CRITICAL: BI-DIRECTIONAL PEGA ↔ INVOICE SYNC
-- ============================================================================

-- Function: Sync invoice items back to mechanic_job_items
-- Called when invoice items are modified to keep pega in sync
create or replace function public.sync_invoice_items_to_job(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
  v_invoice record;
  v_item jsonb;
  v_subtotal numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_parts_cost numeric(12,2) := 0;
  v_product_id uuid;
  v_product_type text;
  v_product_name text;
  v_quantity numeric(12,2);
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_tenant_id uuid;
begin
  -- Prevent circular sync: if we're already deep in triggers, skip
  if pg_trigger_depth() > 2 then
    raise notice 'sync_invoice_items_to_job: trigger depth too deep (%), skipping to prevent circular sync', pg_trigger_depth();
    return;
  end if;

  -- Find the job linked to this invoice
  select id into v_job_id
  from mechanic_jobs
  where invoice_id = p_invoice_id;
  
  if v_job_id is null then
    raise notice 'No job linked to invoice %', p_invoice_id;
    return;
  end if;
  
  -- Get invoice details
  select * into v_invoice
  from sales_invoices
  where id = p_invoice_id;
  
  if not found then
    raise notice 'Invoice % not found', p_invoice_id;
    return;
  end if;
  
  -- Get tenant_id from invoice
  v_tenant_id := v_invoice.tenant_id;
  
  -- Set a flag to prevent reverse sync
  perform set_config('app.syncing_invoice_to_job', 'true', true);
  
  -- Delete existing job items (we'll recreate them from invoice)
  delete from mechanic_job_items where job_id = v_job_id;
  
  -- Process each invoice item
  for v_item in select * from jsonb_array_elements(v_invoice.items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::numeric, 1);
    v_unit_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_line_total := coalesce((v_item->>'line_total')::numeric, v_quantity * v_unit_price, 0);
    v_product_name := v_item->>'product_name';

    -- Check if it's labor (no product_id) or a part
    -- Determine product info (if exists)
    v_product_type := null;
    v_product_name := null;
    if v_product_id is not null then
      select product_type, name
      into v_product_type, v_product_name
      from products
      where id = v_product_id;
      if not found then
        v_product_type := null;
        v_product_name := null;
      end if;
    end if;

    if v_product_id is null or v_product_type = 'service' then
      v_labor_cost := v_labor_cost + v_line_total;
    else
      v_parts_cost := v_parts_cost + v_line_total;
    end if;

    insert into mechanic_job_items (
      tenant_id,
      job_id,
      product_id,
      product_name,
      quantity,
      unit_price,
      total_price,
      notes,
      item_type,
      service_product_id,
      created_at,
      updated_at
    ) values (
      v_tenant_id,
      v_job_id,
      case when v_product_type = 'service' then null else v_product_id end,
      coalesce(v_product_name, v_item->>'product_name'),
      case when v_quantity is null or v_quantity = 0 then 1 else v_quantity end,
      v_unit_price,
      v_line_total,
      'Synced from invoice',
      case when v_product_id is null or v_product_type = 'service' then 'service' else 'product' end,
      case when v_product_id is null or v_product_type = 'service' then v_product_id else null end,
      now(),
      now()
    );
  end loop;
  
  v_subtotal := v_parts_cost + v_labor_cost;
  
  -- Update job costs
  update mechanic_jobs
  set 
    labor_cost = v_labor_cost,
    parts_cost = v_parts_cost,
    final_cost = v_subtotal,
    estimated_cost = v_subtotal,
    total_cost = v_invoice.total,
    tax_amount = v_invoice.iva_amount,
    updated_at = now()
  where id = v_job_id;
  
  -- Clear the sync flag
  perform set_config('app.syncing_invoice_to_job', '', true);
  
  raise notice 'Synced invoice % items to job (parts: $%, labor: $%)', 
    p_invoice_id, v_parts_cost, v_labor_cost;
end;
$$;

-- Function: Sync invoice status/payment changes to mechanic_job
-- Called when invoice status or payment changes
create or replace function public.sync_invoice_status_to_job(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
  v_invoice record;
  v_is_paid boolean;
begin
  -- Find the job linked to this invoice
  select id into v_job_id
  from mechanic_jobs
  where invoice_id = p_invoice_id;
  
  if v_job_id is null then
    raise notice 'No job linked to invoice %', p_invoice_id;
    return;
  end if;
  
  -- Get invoice details
  select * into v_invoice
  from sales_invoices
  where id = p_invoice_id;
  
  if not found then
    raise notice 'Invoice % not found', p_invoice_id;
    return;
  end if;
  
  -- Determine if paid
  v_is_paid := (lower(v_invoice.status) = 'paid');
  
  -- Update job status AND tax treatment
  update mechanic_jobs
  set 
    is_invoiced = true,
    is_paid = v_is_paid,
    tax_treatment = v_invoice.tax_treatment,  -- ✅ Sync tax treatment from invoice to job
    updated_at = now()
  where id = v_job_id;
  
  raise notice 'Synced invoice % status (%) and tax treatment (%) to job (is_paid: %)', 
    p_invoice_id, v_invoice.status, v_invoice.tax_treatment, v_is_paid;
end;
$$;

-- ============================================================
-- REMOVED: handle_invoice_deleted_for_job trigger
-- Reason: Conflicts with cascade_delete_pega_invoice trigger
-- The cascade delete provides proper bidirectional deletion
-- (delete invoice → delete pega, delete pega → delete invoice)
-- ============================================================

-- ============================================================
-- REVERSE SYNC: Job → Invoice
-- ============================================================

-- Called when mechanic_job_items change
create or replace function public.sync_job_to_invoice(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
  v_job record;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_iva_amount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_syncing_flag text;
begin
  -- Check if we're currently syncing invoice → job (prevent circular sync)
  v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);
  if v_syncing_flag = 'true' then
    raise notice 'sync_job_to_invoice: skipping due to invoice→job sync in progress';
    return;
  end if;

  -- ✅ REMOVED trigger depth check - it was preventing syncs during cascade deletes
  -- When deleting services with subtasks, trigger depth > 2 and sync would fail
  -- The circular sync flag above is sufficient protection

  -- Get the job and its linked invoice
  select * into v_job
  from mechanic_jobs
  where id = p_job_id;
  
  if not found then
    raise notice 'Job % not found', p_job_id;
    return;
  end if;
  
  v_invoice_id := v_job.invoice_id;
  
  if v_invoice_id is null then
    raise notice 'Job % has no linked invoice', p_job_id;
    return;
  end if;
  
  select coalesce(discount_amount, 0)
  into v_discount
  from mechanic_jobs
  where id = p_job_id;
  
  -- Build invoice items array from mechanic_job_items (products + services)
  for v_item in 
    select * from mechanic_job_items where job_id = p_job_id
  loop
    v_items := v_items || jsonb_build_object(
      'product_id', case when coalesce(v_item.item_type, 'product') = 'service'
                         then coalesce(v_item.service_product_id::text, '')
                         else v_item.product_id::text
                    end,
      'product_name', v_item.product_name,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0)
    );

    if coalesce(v_item.item_type, 'product') in ('service', 'adhoc') then
      v_labor_cost := v_labor_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    else
      v_parts_cost := v_parts_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    end if;
  end loop;
  
  -- Calculate totals with FRESH data (not using stale v_job record)
  v_subtotal := v_parts_cost + v_labor_cost - v_discount;
  
  -- ✅ FIX: Calculate IVA based on job's tax treatment (not hardcoded)
  if v_job.tax_treatment = 'tax_included' then
    -- Tax included: net = subtotal ÷ 1.19, iva = subtotal - net
    v_iva_amount := round(v_subtotal - (v_subtotal / 1.19), 0);
  else
    -- No tax: iva = 0
    v_iva_amount := 0;
  end if;
  
  v_total := v_subtotal;  -- Total is always the subtotal (what customer pays)
  
  -- Update the invoice with fresh calculations
  perform set_config('app.syncing_job_to_invoice', 'true', true);

  update sales_invoices
  set
    items = v_items,
    subtotal = v_subtotal,
    iva_amount = v_iva_amount,
    net_amount = case 
      when v_job.tax_treatment = 'tax_included' then v_subtotal / 1.19
      else v_subtotal
    end,
    tax_treatment = v_job.tax_treatment,
    total = v_total,
    discount_amount = v_discount,
    updated_at = now()
  where id = v_invoice_id;
  
  -- Let the payment recalculation function handle balance and status
  perform public.recalculate_sales_invoice_payments(v_invoice_id);

  -- Clear job → invoice flag now that invoice update is done
  perform set_config('app.syncing_job_to_invoice', '', true);
  
  raise notice 'Synced job % to invoice % (% items, subtotal: $%, total: $%)', p_job_id, v_invoice_id, jsonb_array_length(v_items), v_subtotal, v_total;
end;
$$;

-- Function: Consume inventory for mechanic job
-- Called when job status changes to EN_CURSO or FINALIZADO
create or replace function public.consume_mechanic_job_inventory(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_job_number text;
begin
  if p_job_id is null then
    return;
  end if;

  -- Get job number
  select job_number into v_job_number
  from mechanic_jobs
  where id = p_job_id;

  v_reference := concat('mechanic_job:', p_job_id::text);

  -- Check if inventory already consumed
  if exists (
    select 1 from stock_movements
    where reference = v_reference and type = 'OUT'
  ) then
    raise notice 'Inventory already consumed for job %', v_job_number;
    return;
  end if;

  -- Consume inventory for each item
  for v_item in
    select 
      product_id,
      product_name,
      quantity
    from mechanic_job_items
    where job_id = p_job_id
      and product_id is not null
  loop
    -- Create stock movement
    insert into stock_movements (
      product_id,
      type,
      quantity,
      reference,
      notes,
      date,
      created_at
    ) values (
      v_item.product_id,
      'OUT',
      v_item.quantity,
      v_reference,
      'Mechanic Job ' || v_job_number || ': ' || v_item.product_name,
      now(),
      now()
    );

    -- Update product inventory
    update products
    set 
      inventory_qty = inventory_qty - v_item.quantity::integer,
      stock_quantity = stock_quantity - v_item.quantity::integer,
      updated_at = now()
    where id = v_item.product_id;

    raise notice 'Consumed % x % for job %', v_item.quantity, v_item.product_name, v_job_number;
  end loop;
end;
$$;

-- Function: Restore inventory for mechanic job
-- Called when job is cancelled or parts removed
create or replace function public.restore_mechanic_job_inventory(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_movement record;
begin
  if p_job_id is null then
    return;
  end if;

  v_reference := concat('mechanic_job:', p_job_id::text);

  -- Restore inventory from each stock movement
  for v_movement in
    select 
      product_id,
      quantity
    from stock_movements
    where reference = v_reference and type = 'OUT'
  loop
    -- Create reversal stock movement
    insert into stock_movements (
      product_id,
      type,
      quantity,
      reference,
      notes,
      date,
      created_at
    ) values (
      v_movement.product_id,
      'IN',
      v_movement.quantity,
      v_reference || ':reversed',
      'Inventory restored - job cancelled or modified',
      now(),
      now()
    );

    -- Update product inventory
    update products
    set 
      inventory_qty = inventory_qty + v_movement.quantity::integer,
      stock_quantity = stock_quantity + v_movement.quantity::integer,
      updated_at = now()
    where id = v_movement.product_id;
  end loop;

  -- Delete original stock movements
  delete from stock_movements
  where reference = v_reference and type = 'OUT';
end;
$$;

-- Function: Create journal entry for completed mechanic job
-- Posts revenue when job is marked as FINALIZADO
create or replace function public.create_mechanic_job_journal_entry(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_entry_id uuid;
  v_revenue_account_id uuid;
  v_cogs_account_id uuid;
  v_inventory_account_id uuid;
  v_tax_payable_account_id uuid;
  v_ar_account_id uuid;
begin
  if p_job_id is null then
    return;
  end if;

  -- Get job details
  select * into v_job
  from mechanic_jobs
  where id = p_job_id;

  if not found then
    raise notice 'Job % not found', p_job_id;
    return;
  end if;

  -- Don't create journal entry if already invoiced (invoice will handle it)
  if v_job.is_invoiced then
    raise notice 'Job % already invoiced, skipping journal entry', v_job.job_number;
    return;
  end if;

  -- Check if journal entry already exists
  if exists (
    select 1 from journal_entries
    where source_module = 'mechanic_jobs'
      and source_reference = p_job_id::text
  ) then
    raise notice 'Journal entry already exists for job %', v_job.job_number;
    return;
  end if;

  -- Get or create necessary accounts
  v_revenue_account_id := public.ensure_account('4100', 'Ingresos Operacionales', 'income', 'operatingIncome');
  v_cogs_account_id := public.ensure_account('5100', 'Costo de Ventas', 'expense', 'costOfGoodsSold');
  v_inventory_account_id := public.ensure_account('1105', 'Inventarios', 'asset', 'currentAsset');
  v_tax_payable_account_id := public.ensure_account('210200', 'IVA por Pagar', 'liability', 'currentLiability');
  v_ar_account_id := public.ensure_account('1130', 'Cuentas por Cobrar Comerciales', 'asset', 'currentAsset');

  -- Create journal entry
  insert into journal_entries (
    entry_number,
    entry_date,
    description,
    source_module,
    source_reference,
    status,
    created_at,
    updated_at
  ) values (
    public.get_next_document_number(v_job.tenant_id, 'journal_entry'),
    coalesce(v_job.completed_at, now()),
    'Mechanic Job ' || v_job.job_number || ' - ' || coalesce(v_job.diagnosis, 'Service completed'),
    'mechanic_jobs',
    v_job.job_number,
    'posted',
    now(),
    now()
  ) returning id into v_entry_id;

  -- Debit: Accounts Receivable (total including tax)
  insert into journal_lines (
    entry_id,
    account_id,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_ar_account_id,
    'Service Revenue - Job ' || v_job.job_number,
    v_job.total_cost,
    0,
    now(),
    now()
  );

  -- Credit: Service Revenue (subtotal minus discount)
  insert into journal_lines (
    entry_id,
    account_id,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_revenue_account_id,
    'Service Revenue - Job ' || v_job.job_number,
    0,
    v_job.final_cost - v_job.discount_amount,
    now(),
    now()
  );

  -- Credit: Tax Payable (IVA)
  if v_job.tax_amount > 0 then
    insert into journal_lines (
      entry_id,
      account_id,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      v_entry_id,
      v_tax_payable_account_id,
      'IVA - Job ' || v_job.job_number,
      0,
      v_job.tax_amount,
      now(),
      now()
    );
  end if;

  -- Debit: Cost of Services (parts cost)
  -- Credit: Inventory (parts cost)
  if v_job.parts_cost > 0 then
    insert into journal_lines (
      entry_id,
      account_id,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      v_entry_id,
      v_cogs_account_id,
      'COGS - Parts - Job ' || v_job.job_number,
      v_job.parts_cost,
      0,
      now(),
      now()
    );

    insert into journal_lines (
      entry_id,
      account_id,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      v_entry_id,
      v_inventory_account_id,
      'Inventory Reduction - Job ' || v_job.job_number,
      0,
      v_job.parts_cost,
      now(),
      now()
    );
  end if;

  raise notice 'Created journal entry for job %', v_job.job_number;
end;
$$;

-- Function: Delete journal entry for mechanic job
create or replace function public.delete_mechanic_job_journal_entry(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_job_id is null then
    return;
  end if;

  delete from journal_entries
  where source_module = 'mechanic_jobs'
    and source_reference = p_job_id::text;
end;
$$;

-- Function: Log timeline event
create or replace function public.log_mechanic_job_timeline(
  p_job_id uuid,
  p_event_type text,
  p_old_value text default null,
  p_new_value text default null,
  p_description text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  -- Get tenant_id from the job
  select tenant_id into v_tenant_id
  from mechanic_jobs
  where id = p_job_id;

  if v_tenant_id is null then
    raise warning 'Cannot log timeline: job % not found or has no tenant_id', p_job_id;
    return;
  end if;

  insert into mechanic_job_timeline (
    tenant_id,
    job_id,
    event_type,
    old_value,
    new_value,
    description,
    created_at
  ) values (
    v_tenant_id,
    p_job_id,
    p_event_type,
    p_old_value,
    p_new_value,
    p_description,
    now()
  );
end;
$$;

-- Main trigger function: Handle mechanic job changes
create or replace function public.handle_mechanic_job_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text;
  v_new_status text;
  v_should_consume_inventory boolean := false;
  v_should_restore_inventory boolean := false;
  v_should_create_journal boolean := false;
  v_should_delete_journal boolean := false;
begin
  raise notice 'handle_mechanic_job_change: TG_OP=%', TG_OP;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    -- For BEFORE INSERT: Only set job_number and timestamps
    if TG_WHEN = 'BEFORE' then
      -- Generate job number if not provided
      if NEW.job_number is null or NEW.job_number = '' then
        NEW.job_number := public.generate_mechanic_job_number();
      end if;

      -- Set timestamps based on status
      if NEW.status = 'EN_CURSO' and NEW.started_at is null then
        NEW.started_at := now();
      end if;
      if NEW.status = 'FINALIZADO' and NEW.completed_at is null then
        NEW.completed_at := now();
      end if;
      if NEW.status = 'ENTREGADO' and NEW.delivered_at is null then
        NEW.delivered_at := now();
      end if;

      return NEW;
    end if;

    -- For AFTER INSERT: Log timeline and handle inventory/journal
    if TG_WHEN = 'AFTER' then
      -- Log creation
      perform public.log_mechanic_job_timeline(
        NEW.id,
        'created',
        null,
        NEW.status,
        'Job created: ' || coalesce(NEW.client_request, 'Service request')
      );

      -- NOTE: Invoice creation is now handled in Flutter after items are added
      -- This ensures all job items are included in the invoice

      -- Consume inventory if starting with EN_CURSO or FINALIZADO status
      if NEW.status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then
        v_should_consume_inventory := true;
      end if;

      -- Create journal entry if starting with FINALIZADO
      if NEW.status in ('FINALIZADO', 'ENTREGADO') and not NEW.is_invoiced then
        v_should_create_journal := true;
      end if;
    end if;

    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;

    -- Update timestamps on status change
    if v_old_status <> v_new_status then
      perform public.log_mechanic_job_timeline(
        NEW.id,
        'status_changed',
        v_old_status,
        v_new_status,
        'Status changed from ' || v_old_status || ' to ' || v_new_status
      );

      if v_new_status = 'EN_CURSO' and NEW.started_at is null then
        NEW.started_at := now();
      end if;
      if v_new_status = 'FINALIZADO' and NEW.completed_at is null then
        NEW.completed_at := now();
      end if;
      if v_new_status = 'ENTREGADO' and NEW.delivered_at is null then
        NEW.delivered_at := now();
      end if;

      -- AWESOME: Sync invoice status with job status
      if NEW.invoice_id is not null then
        if v_new_status = 'ENTREGADO' then
          -- Job delivered → mark invoice as sent/issued
          update public.sales_invoices
          set status = 'enviado',
              updated_at = now()
          where id = NEW.invoice_id
            and status = 'draft';
        elsif v_new_status = 'CANCELADO' then
          -- Job cancelled → mark invoice as cancelled
          update public.sales_invoices
          set status = 'cancelado',
              updated_at = now()
          where id = NEW.invoice_id
            and status != 'paid';
        end if;
      end if;

      -- Handle inventory consumption/restoration based on status transitions
      if v_old_status not in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') 
         and v_new_status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then
        -- Moving to active/completed status: consume inventory
        v_should_consume_inventory := true;
      elsif v_old_status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') 
            and v_new_status = 'CANCELADO' then
        -- Cancelling: restore inventory
        v_should_restore_inventory := true;
      end if;

      -- Handle journal entries based on status transitions
      if v_new_status in ('FINALIZADO', 'ENTREGADO') 
         and v_old_status not in ('FINALIZADO', 'ENTREGADO')
         and not NEW.is_invoiced then
        -- Job completed: create journal entry
        v_should_create_journal := true;
      elsif v_new_status = 'CANCELADO' 
            and v_old_status in ('FINALIZADO', 'ENTREGADO') then
        -- Job cancelled after completion: delete journal entry
        v_should_delete_journal := true;
      end if;
    end if;

    -- Log other changes
    if OLD.diagnosis is distinct from NEW.diagnosis and NEW.diagnosis is not null then
      perform public.log_mechanic_job_timeline(
        NEW.id,
        'diagnosis_added',
        null,
        null,
        'Diagnosis updated'
      );
    end if;

    if OLD.assigned_to is distinct from NEW.assigned_to then
      perform public.log_mechanic_job_timeline(
        NEW.id,
        'assigned',
        OLD.assigned_technician_name,
        NEW.assigned_technician_name,
        'Technician assigned'
      );
    end if;

    if OLD.approved_by_customer <> NEW.approved_by_customer and NEW.approved_by_customer then
      perform public.log_mechanic_job_timeline(
        NEW.id,
        'approved',
        null,
        null,
        'Customer approved the work'
      );
    end if;

    if OLD.is_invoiced <> NEW.is_invoiced and NEW.is_invoiced then
      perform public.log_mechanic_job_timeline(
        NEW.id,
        'invoiced',
        null,
        NEW.invoice_id::text,
        'Job invoiced'
      );
      -- Delete our journal entry since invoice will create its own
      v_should_delete_journal := true;
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    -- Restore inventory if job was active
    if OLD.status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then
      perform public.restore_mechanic_job_inventory(OLD.id);
    end if;

    -- Delete journal entry if exists
    perform public.delete_mechanic_job_journal_entry(OLD.id);

    return OLD;
  end if;

  -- For BEFORE triggers on INSERT, must return NEW to allow the insert
  if TG_WHEN = 'BEFORE' and TG_OP = 'INSERT' then
    return NEW;
  end if;

  -- Execute deferred operations for AFTER triggers
  if TG_WHEN = 'AFTER' then
    if v_should_restore_inventory then
      perform public.restore_mechanic_job_inventory(NEW.id);
    end if;

    if v_should_consume_inventory then
      perform public.consume_mechanic_job_inventory(NEW.id);
    end if;

    if v_should_delete_journal then
      perform public.delete_mechanic_job_journal_entry(NEW.id);
    end if;

    if v_should_create_journal then
      perform public.create_mechanic_job_journal_entry(NEW.id);
    end if;
  end if;

  return NULL;
end;
$$;

-- Create trigger for mechanic jobs (BEFORE INSERT to set job_number)
drop trigger if exists trg_mechanic_jobs_before_insert on mechanic_jobs cascade;
create trigger trg_mechanic_jobs_before_insert
  before insert on mechanic_jobs
  for each row execute procedure public.handle_mechanic_job_change();

-- Create trigger for mechanic jobs (AFTER INSERT/UPDATE/DELETE for logging and business logic)
drop trigger if exists trg_mechanic_jobs_change on mechanic_jobs cascade;
create trigger trg_mechanic_jobs_change
  after insert or update or delete on mechanic_jobs
  for each row execute procedure public.handle_mechanic_job_change();

-- Trigger function: Handle mechanic job items changes
-- BEFORE trigger to calculate item total_price
create or replace function public.calculate_mechanic_job_item_total()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Calculate total_price = quantity × unit_price
  NEW.total_price := coalesce(NEW.quantity, 0) * coalesce(NEW.unit_price, 0);
  return NEW;
end;
$$;

drop trigger if exists trg_calculate_mechanic_job_item_total on mechanic_job_items cascade;
create trigger trg_calculate_mechanic_job_item_total
  before insert or update on mechanic_job_items
  for each row execute procedure public.calculate_mechanic_job_item_total();

-- AFTER trigger to update job costs and sync to invoice
create or replace function public.handle_mechanic_job_items_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    -- Recalculate job costs
    perform public.recalculate_mechanic_job_costs(NEW.job_id);
    
    -- Note: Sync to invoice is handled by statement-level trigger
    
    -- Log event
    perform public.log_mechanic_job_timeline(
      NEW.job_id,
      'parts_added',
      null,
      NEW.product_name,
      'Added part: ' || NEW.product_name || ' (Qty: ' || NEW.quantity || ')'
    );
    
    return NEW;

  elsif TG_OP = 'UPDATE' then
    -- Recalculate job costs
    perform public.recalculate_mechanic_job_costs(NEW.job_id);
    
    -- Note: Sync to invoice is handled by statement-level trigger
    
    return NEW;

  elsif TG_OP = 'DELETE' then
    -- Recalculate job costs
    perform public.recalculate_mechanic_job_costs(OLD.job_id);
    
    -- Note: Sync to invoice is handled by statement-level trigger
    
    return OLD;
  end if;

  return NULL;
end;
$$;

-- Create trigger for mechanic job items
drop trigger if exists trg_mechanic_job_items_change on mechanic_job_items cascade;
create trigger trg_mechanic_job_items_change
  after insert or update or delete on mechanic_job_items
  for each row execute procedure public.handle_mechanic_job_items_change();

-- Statement-level triggers to sync job to invoice AFTER all row operations complete
drop trigger if exists trg_mechanic_job_items_sync_invoice_insert on mechanic_job_items cascade;
drop trigger if exists trg_mechanic_job_items_sync_invoice_update on mechanic_job_items cascade;
drop trigger if exists trg_mechanic_job_items_sync_invoice_delete on mechanic_job_items cascade;

create or replace function public.sync_job_items_to_invoice_statement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
  v_invoice_id uuid;
  v_syncing_flag text;
begin
  -- Check if we're currently syncing invoice → job (prevent circular sync)
  v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);
  if v_syncing_flag = 'true' then
    raise notice 'sync_job_items_to_invoice_statement: skipping due to invoice→job sync in progress';
    return null;
  end if;

  -- Handle DELETE operations - get job_id from old_table
  if TG_OP = 'DELETE' then
    for v_job_id in select distinct job_id from old_table
    loop
      -- Recalculate costs first to update job record with new totals
      perform public.recalculate_mechanic_job_costs(v_job_id);
      
      -- Find the linked invoice
      select invoice_id into v_invoice_id from mechanic_jobs where id = v_job_id;
      
      if v_invoice_id is not null then
        -- Sync this job to its invoice (will remove deleted items)
        perform public.sync_job_to_invoice(v_job_id);
      end if;
    end loop;
    return null;
  end if;

  -- Handle INSERT and UPDATE - sync immediately since we're adding/changing items
  for v_job_id in select distinct job_id from new_table
  loop
    -- Recalculate costs first to update job record with new totals
    perform public.recalculate_mechanic_job_costs(v_job_id);
    
    -- Find the linked invoice
    select invoice_id into v_invoice_id from mechanic_jobs where id = v_job_id;
    
    if v_invoice_id is not null then
      -- Sync this job to its invoice (will recalculate fresh totals from DB)
      perform public.sync_job_to_invoice(v_job_id);
    end if;
  end loop;
  
  return null;
end;
$$;

create trigger trg_mechanic_job_items_sync_invoice_insert
  after insert on mechanic_job_items
  referencing new table as new_table
  for each statement execute procedure public.sync_job_items_to_invoice_statement();

create trigger trg_mechanic_job_items_sync_invoice_update
  after update on mechanic_job_items
  referencing new table as new_table
  for each statement execute procedure public.sync_job_items_to_invoice_statement();

create trigger trg_mechanic_job_items_sync_invoice_delete
  after delete on mechanic_job_items
  referencing old table as old_table
  for each statement execute procedure public.sync_job_items_to_invoice_statement();

-- Trigger: Auto-update updated_at timestamp
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  NEW.updated_at := now();
  return NEW;
end;
$$;

drop trigger if exists trg_bikes_updated_at on bikes cascade;
create trigger trg_bikes_updated_at
  before update on bikes
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_service_packages_updated_at on service_packages cascade;
create trigger trg_service_packages_updated_at
  before update on service_packages
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_mechanic_jobs_updated_at on mechanic_jobs cascade;
create trigger trg_mechanic_jobs_updated_at
  before update on mechanic_jobs
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_mechanic_job_items_updated_at on mechanic_job_items cascade;
create trigger trg_mechanic_job_items_updated_at
  before update on mechanic_job_items
  for each row execute procedure public.set_updated_at();

-- ============================================================================
-- SMART TASKS SYSTEM - Functions & Triggers
-- ============================================================================
-- Three-way sync system for tasks, items, and invoices
-- Features:
-- - Auto-parse product/service descriptions into sub-tasks
-- - Ad-hoc tasks with pricing → auto-create items
-- - Hierarchical task structure (parent → sub-tasks)
-- - Completion tracking with user attribution
-- ============================================================================

-- Function: Parse product/service description into tasks
-- Intelligently extracts bullet points and creates sub-tasks
create or replace function public.parse_description_to_tasks(
  p_tenant_id uuid,
  p_job_id uuid,
  p_parent_item_id uuid default null,
  p_description text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task_line text;
  v_task_name text;
  v_task_count integer := 0;
  v_lines text[];
begin
  if p_description is null or trim(p_description) = '' then
    return 0;
  end if;
  
  -- Split description by newlines
  v_lines := string_to_array(p_description, E'\n');
  
  -- Parse each line
  foreach v_task_line in array v_lines
  loop
    v_task_line := trim(v_task_line);
    
    -- Check if line starts with bullet markers: -, •, *, →, ✓, ☐, ☑, 1., 2., etc.
    if v_task_line ~ '^[-•*→✓☐☑]' or v_task_line ~ '^\d+\.' then
      -- Remove bullet marker and clean up
      v_task_name := regexp_replace(v_task_line, '^[-•*→✓☐☑]\s*', '');
      v_task_name := regexp_replace(v_task_name, '^\d+\.\s*', '');
      v_task_name := trim(v_task_name);
      
      -- Skip empty lines
      if length(v_task_name) > 0 then
        insert into mechanic_job_tasks (
          tenant_id,
          job_id,
          parent_item_id,
          task_name,
          parsed_from_description,
          is_standalone,
          display_order
        ) values (
          p_tenant_id,
          p_job_id,
          p_parent_item_id,
          v_task_name,
          true,
          false,
          v_task_count
        );
        
        v_task_count := v_task_count + 1;
      end if;
    end if;
  end loop;
  
  return v_task_count;
end;
$$;

-- Function: Create ad-hoc item for task with pricing
-- Called when user adds price to ad-hoc task
create or replace function public.create_adhoc_item_for_task(
  p_task_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task record;
  v_item_id uuid;
  v_syncing_flag text;
begin
  -- Prevent circular sync
  v_syncing_flag := current_setting('app.syncing_task_to_item', true);
  if v_syncing_flag = 'true' then
    raise notice 'create_adhoc_item_for_task: skipping due to circular sync prevention';
    return null;
  end if;
  
  -- Get task details
  select * into v_task
  from mechanic_job_tasks
  where id = p_task_id;
  
  if not found or not v_task.is_adhoc or v_task.adhoc_price is null then
    return null;
  end if;
  
  -- Check if item already exists
  if v_task.adhoc_item_id is not null then
    return v_task.adhoc_item_id;
  end if;
  
  -- Set sync flag
  perform pg_catalog.set_config('app.syncing_task_to_item', 'true', true);
  
  -- Create mechanic_job_item
  insert into mechanic_job_items (
    tenant_id,
    job_id,
    product_name,
    quantity,
    unit_price,
    total_price
  ) values (
    v_task.tenant_id,
    v_task.job_id,
    'Ad-hoc: ' || v_task.task_name,
    1,
    v_task.adhoc_price,
    v_task.adhoc_price
  )
  returning id into v_item_id;
  
  -- Link task to item
  update mechanic_job_tasks
  set adhoc_item_id = v_item_id
  where id = p_task_id;
  
  -- Clear sync flag
  perform pg_catalog.set_config('app.syncing_task_to_item', '', true);
  
  raise notice 'Created ad-hoc item % for task %', v_item_id, p_task_id;
  return v_item_id;
end;
$$;

-- Trigger: Auto-parse description when mechanic_job_item is added
create or replace function public.auto_parse_item_description()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_description text;
  v_task_count integer;
  v_product_id uuid;
  v_service_product_id uuid;
begin
  -- CRITICAL: IMMEDIATELY RETURN if not on correct tables
  -- This prevents ANY field access on wrong table
  if TG_TABLE_NAME <> 'mechanic_job_items' then
    raise notice 'auto_parse_item_description: skipping table %, trigger: %', TG_TABLE_NAME, TG_NAME;
    return null;  -- AFTER trigger, return null is correct
  end if;
  
  -- Use exception handling to safely access fields
  begin
    -- Try to get product_id or service_product_id safely
    v_product_id := (NEW).product_id;
    v_service_product_id := (NEW).service_product_id;
  exception
    when undefined_column then
      raise warning 'auto_parse_item_description: column access error on table %, skipping', TG_TABLE_NAME;
      return null;
  end;
  
  -- Get product/service description
  if v_product_id is not null then
    select description into v_description
    from products
    where id = v_product_id;
    
    if v_description is not null then
      v_task_count := public.parse_description_to_tasks(
        NEW.tenant_id,
        NEW.job_id,
        NEW.id,
        v_description
      );
      
      if v_task_count > 0 then
        raise notice 'Auto-parsed % tasks from product description', v_task_count;
      end if;
    end if;
    
  elsif v_service_product_id is not null then
    select description into v_description
    from products
    where id = v_service_product_id;
    
    if v_description is not null then
      v_task_count := public.parse_description_to_tasks(
        NEW.tenant_id,
        NEW.job_id,
        NEW.id,
        v_description
      );
      
      if v_task_count > 0 then
        raise notice 'Auto-parsed % tasks from service description', v_task_count;
      end if;
    end if;
  end if;
  
  return null;  -- AFTER trigger must return null
end;
$$;

drop trigger if exists trg_auto_parse_item_description on mechanic_job_items cascade;
create trigger trg_auto_parse_item_description
  after insert on mechanic_job_items
  for each row execute procedure public.auto_parse_item_description();

-- Trigger: Auto-create item when ad-hoc task gets price
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

drop trigger if exists trg_sync_adhoc_task_to_item on mechanic_job_tasks cascade;
create trigger trg_sync_adhoc_task_to_item
  after insert or update on mechanic_job_tasks
  for each row execute procedure public.sync_adhoc_task_to_item();

-- Trigger: Set completed_at timestamp when task is completed
create or replace function public.set_task_completed_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.is_completed and not OLD.is_completed then
    NEW.completed_at := now();
    NEW.completed_by_user_id := auth.uid();
  elsif not NEW.is_completed and OLD.is_completed then
    NEW.completed_at := null;
    NEW.completed_by_user_id := null;
  end if;
  
  return NEW;
end;
$$;

drop trigger if exists trg_set_task_completed_at on mechanic_job_tasks cascade;
create trigger trg_set_task_completed_at
  before update on mechanic_job_tasks
  for each row
  when (OLD.is_completed is distinct from NEW.is_completed)
  execute procedure public.set_task_completed_at();

-- Trigger: updated_at for tasks
drop trigger if exists trg_mechanic_job_tasks_updated_at on mechanic_job_tasks cascade;
create trigger trg_mechanic_job_tasks_updated_at
  before update on mechanic_job_tasks
  for each row execute procedure public.set_updated_at();

-- Trigger: Cleanup ad-hoc item when task is deleted
-- This ensures that when a task with an adhoc_item_id is deleted,
-- the associated ad-hoc item in mechanic_job_items is also removed
create or replace function public.cleanup_adhoc_item_on_task_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise notice '🗑️ [DB] cleanup_adhoc_item_on_task_delete triggered for task: % (name: %)', OLD.id, OLD.task_name;
  
  -- If task had an ad-hoc item linked, delete it
  if OLD.adhoc_item_id is not null then
    raise notice '🗑️ [DB] Task has adhoc_item_id: %, deleting item', OLD.adhoc_item_id;
    delete from mechanic_job_items where id = OLD.adhoc_item_id;
    raise notice '🗑️ [DB] Ad-hoc item deleted';
  else
    raise notice '🗑️ [DB] Task has no adhoc_item_id, nothing to clean up';
  end if;
  
  return OLD;
end;
$$;

drop trigger if exists trg_cleanup_adhoc_item_on_task_delete on mechanic_job_tasks cascade;
create trigger trg_cleanup_adhoc_item_on_task_delete
  after delete on mechanic_job_tasks
  for each row execute procedure public.cleanup_adhoc_item_on_task_delete();

-- ============================================================================
-- HR & ATTENDANCES MODULE
-- ============================================================================
-- Complete HR foundation with employees, departments, contracts, schedules,
-- and Odoo-style attendance tracking with check-in/check-out functionality
-- ============================================================================

-- Departments table (organizes employees by area)
create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  code text,
  manager_id uuid,
  description text,
  active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name) -- Each tenant has their own departments
);

do $$ begin
  create index if not exists idx_departments_tenant on departments(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table departments does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in departments';
end $$;

-- Employees table (core HR entity)
create table if not exists employees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  user_id uuid references auth.users(id), -- Link to Supabase auth for login
  employee_number text not null,
  first_name text not null,
  last_name text not null,
  email text,
  phone text,
  rut text, -- Chilean ID number
  birth_date date,
  hire_date date not null default current_date,
  termination_date date,
  department_id uuid references departments(id),
  job_title text not null,
  system_role text, -- Links to job_roles.system_role
  employment_type text check (employment_type in ('full_time', 'part_time', 'contractor', 'intern')) not null default 'full_time',
  status text check (status in ('active', 'inactive', 'on_leave', 'terminated')) not null default 'active',
  photo_url text,
  address text,
  city text,
  emergency_contact_name text,
  emergency_contact_phone text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  -- Tenant-scoped unique constraints
  unique (tenant_id, employee_number),
  unique (tenant_id, email),
  unique (tenant_id, rut)
);

-- Migration: Add missing columns to employees table
do $$
begin
  -- Add all potentially missing columns
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'user_id') then
    alter table employees add column user_id uuid references auth.users(id);
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'employee_number') then
    alter table employees add column employee_number text;
    -- Add unique constraint separately
    alter table employees add constraint employees_employee_number_key unique (employee_number);
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'email') then
    alter table employees add column email text unique;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'phone') then
    alter table employees add column phone text;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'rut') then
    alter table employees add column rut text unique;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'birth_date') then
    alter table employees add column birth_date date;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'hire_date') then
    alter table employees add column hire_date date not null default current_date;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'termination_date') then
    alter table employees add column termination_date date;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'department_id') then
    alter table employees add column department_id uuid references departments(id);
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'job_title') then
    alter table employees add column job_title text not null default 'Sin cargo';
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'employment_type') then
    alter table employees add column employment_type text check (employment_type in ('full_time', 'part_time', 'contractor', 'intern')) not null default 'full_time';
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'status') then
    alter table employees add column status text check (status in ('active', 'inactive', 'on_leave', 'terminated')) not null default 'active';
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'photo_url') then
    alter table employees add column photo_url text;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'address') then
    alter table employees add column address text;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'city') then
    alter table employees add column city text;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'emergency_contact_name') then
    alter table employees add column emergency_contact_name text;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'emergency_contact_phone') then
    alter table employees add column emergency_contact_phone text;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'notes') then
    alter table employees add column notes text;
  end if;
  
  -- Add created_at and updated_at columns if they don't exist
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'created_at') then
    alter table employees add column created_at timestamp with time zone not null default now();
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'updated_at') then
    alter table employees add column updated_at timestamp with time zone not null default now();
  end if;
  
  -- Fix company_id column if it exists - make it nullable
  if exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'company_id') then
    begin
      -- Try to make company_id nullable
      alter table employees alter column company_id drop not null;
      raise notice 'Made company_id nullable in employees table';
    exception when others then
      raise notice 'Could not modify company_id: %', sqlerrm;
    end;
  end if;
end $$;

-- ============================================================================
-- HYBRID EMPLOYEE-USER LINKING SYSTEM
-- ============================================================================
-- This creates a smart role system that links employees to users
-- Employees can exist without users (HR records only)
-- Users can be linked to employees for system access

-- Step 1: Add linking columns to existing tables
do $$
begin
  -- Add employee_id to user_profiles for bidirectional linking
  if not exists (select 1 from information_schema.columns where table_name = 'user_profiles' and column_name = 'employee_id') then
    alter table user_profiles add column employee_id uuid references employees(id) on delete set null;
    create index idx_user_profiles_employee on user_profiles(employee_id);
  end if;
  
  -- Add system_role to employees (maps to user_profiles.role)
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'system_role') then
    alter table employees add column system_role text 
      check (system_role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'));
    comment on column employees.system_role is 'System access role if employee has user account';
  end if;
  
  -- Add tenant_id to employees (was missing!)
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'tenant_id') then
    alter table employees add column tenant_id uuid references tenants(id) on delete cascade not null;
    create index idx_employees_tenant on employees(tenant_id);
  end if;
end $$;

-- Step 2: Create job_roles catalog (standardized roles with suggestions)
create table if not exists job_roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  system_role text not null check (system_role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant')),
  display_name text not null, -- 'Administrador', 'Gerente', 'Cajero', 'Mecánico', 'Contador'
  suggested_titles text[] not null default '{}', -- ['Gerente General', 'Gerente de Ventas']
  default_permissions jsonb not null,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, system_role)
);

create index if not exists idx_job_roles_tenant on job_roles(tenant_id);
create index if not exists idx_job_roles_system_role on job_roles(system_role);

-- RLS policies for job_roles
alter table job_roles enable row level security;

drop policy if exists "job_roles_select" on job_roles;
drop policy if exists "job_roles_insert" on job_roles;
drop policy if exists "job_roles_update" on job_roles;
drop policy if exists "job_roles_delete" on job_roles;

create policy "job_roles_select" on job_roles for select to authenticated
  using (tenant_id = public.user_tenant_id());
  
create policy "job_roles_insert" on job_roles for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
  
create policy "job_roles_update" on job_roles for update to authenticated
  using (tenant_id = public.user_tenant_id());
  
create policy "job_roles_delete" on job_roles for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Step 3: Seed default job roles for each tenant
create or replace function seed_job_roles_for_tenant(p_tenant_id uuid)
returns void
security definer
set search_path = public
language plpgsql
as $$
begin
  -- Delete existing roles for clean slate
  delete from job_roles where tenant_id = p_tenant_id;
  
  -- Admin role
  insert into job_roles (tenant_id, system_role, display_name, suggested_titles, default_permissions, sort_order)
  values (
    p_tenant_id,
    'admin',
    'Administrador',
    array['Administrador General', 'Gerente General', 'Dueño'],
    '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb,
    1
  );
  
  -- Manager role
  insert into job_roles (tenant_id, system_role, display_name, suggested_titles, default_permissions, sort_order)
  values (
    p_tenant_id,
    'manager',
    'Gerente',
    array['Gerente de Ventas', 'Gerente de Taller', 'Gerente de Operaciones', 'Subgerente'],
    '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": false}'::jsonb,
    2
  );
  
  -- Cashier role
  insert into job_roles (tenant_id, system_role, display_name, suggested_titles, default_permissions, sort_order)
  values (
    p_tenant_id,
    'cashier',
    'Cajero',
    array['Cajero', 'Vendedor', 'Encargado de Ventas'],
    '{"access_pos": true, "create_invoices": true, "edit_prices": false, "delete_invoices": false, "access_accounting": false, "manage_users": false, "edit_settings": false}'::jsonb,
    3
  );
  
  -- Mechanic role
  insert into job_roles (tenant_id, system_role, display_name, suggested_titles, default_permissions, sort_order)
  values (
    p_tenant_id,
    'mechanic',
    'Mecánico',
    array['Mecánico Junior', 'Mecánico Senior', 'Técnico', 'Jefe de Taller', 'Especialista en Suspensiones'],
    '{"access_pos": false, "create_invoices": false, "edit_prices": false, "delete_invoices": false, "access_accounting": false, "manage_users": false, "edit_settings": false}'::jsonb,
    4
  );
  
  -- Accountant role
  insert into job_roles (tenant_id, system_role, display_name, suggested_titles, default_permissions, sort_order)
  values (
    p_tenant_id,
    'accountant',
    'Contador',
    array['Contador', 'Contador General', 'Asistente Contable'],
    '{"access_pos": false, "create_invoices": false, "edit_prices": false, "delete_invoices": false, "access_accounting": true, "manage_users": false, "edit_settings": false}'::jsonb,
    5
  );
  
  raise notice 'Seeded 5 job roles for tenant %', p_tenant_id;
end;
$$;

-- Indexes for employees table
create index if not exists idx_employees_user_id on employees(user_id);
create index if not exists idx_employees_department on employees(department_id);
create index if not exists idx_employees_status on employees(status);
create index if not exists idx_employees_employee_number on employees(employee_number);
create index if not exists idx_employees_rut on employees(rut);
create index if not exists idx_employees_name on employees using gin (
  to_tsvector('spanish', coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
);

-- Now add the foreign key from departments to employees for manager
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints 
    where constraint_name = 'departments_manager_id_fkey_employees'
  ) then
    alter table departments 
      drop constraint if exists departments_manager_id_fkey,
      add constraint departments_manager_id_fkey_employees 
        foreign key (manager_id) references employees(id);
  end if;
end $$;

-- Work schedules table (defines expected working hours)
create table if not exists work_schedules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  description text,
  monday_start time,
  monday_end time,
  tuesday_start time,
  tuesday_end time,
  wednesday_start time,
  wednesday_end time,
  thursday_start time,
  thursday_end time,
  friday_start time,
  friday_end time,
  saturday_start time,
  saturday_end time,
  sunday_start time,
  sunday_end time,
  weekly_hours numeric(5,2) not null default 45.00, -- Standard Chilean work week
  timezone text not null default 'America/Santiago',
  active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name)
);

do $$ begin
  create index if not exists idx_work_schedules_tenant on work_schedules(tenant_id);
  create index if not exists idx_work_schedules_active on work_schedules(active);
exception
  when undefined_table then raise notice '⚠ Table work_schedules does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in work_schedules';
end $$;

-- Contracts table (employment contracts with salary info)
create table if not exists employee_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid not null references employees(id) on delete cascade,
  contract_type text check (contract_type in ('indefinite', 'fixed_term', 'project_based', 'seasonal')) not null default 'indefinite',
  start_date date not null,
  end_date date,
  salary_amount numeric(12,2) not null,
  salary_currency text not null default 'CLP',
  salary_period text check (salary_period in ('monthly', 'biweekly', 'weekly', 'hourly')) not null default 'monthly',
  work_schedule_id uuid references work_schedules(id),
  weekly_hours numeric(5,2),
  position_title text not null,
  department_id uuid references departments(id),
  status text check (status in ('draft', 'active', 'expired', 'terminated')) not null default 'draft',
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_contracts_tenant on employee_contracts(tenant_id);
  create index if not exists idx_contracts_employee on employee_contracts(employee_id);
  create index if not exists idx_contracts_status on employee_contracts(status);
exception
  when undefined_table then raise notice '⚠ Table employee_contracts does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in employee_contracts';
end $$;
create index if not exists idx_contracts_dates on employee_contracts(start_date, end_date);

-- Attendances table (Odoo-style check-in/check-out tracking)
create table if not exists attendances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid not null references employees(id) on delete cascade,
  check_in timestamp with time zone not null,
  check_out timestamp with time zone,
  worked_hours numeric(10,2), -- Calculated automatically on check-out
  overtime_hours numeric(10,2) default 0, -- Hours beyond scheduled
  break_minutes integer default 0, -- Lunch/coffee breaks
  location_check_in text, -- Optional: "Office", "Remote", "Client Site"
  location_check_out text,
  notes text,
  status text check (status in ('ongoing', 'completed', 'approved', 'rejected')) not null default 'ongoing',
  approved_by uuid references employees(id),
  approved_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_attendances_employee on attendances(employee_id);
create index if not exists idx_attendances_dates on attendances(check_in, check_out);
create index if not exists idx_attendances_status on attendances(status);
create index if not exists idx_attendances_employee_date on attendances(employee_id, check_in);

-- Function: Calculate worked hours when checking out
create or replace function public.calculate_attendance_hours()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours numeric(10,2);
  v_scheduled_hours numeric(5,2);
  v_overtime numeric(10,2);
begin
  -- Only calculate if check_out is set and check_in exists
  if NEW.check_out is not null and NEW.check_in is not null then
    -- Calculate total worked hours
    v_hours := extract(epoch from (NEW.check_out - NEW.check_in)) / 3600.0;
    v_hours := round(v_hours - (coalesce(NEW.break_minutes, 0) / 60.0), 2);
    
    NEW.worked_hours := v_hours;
    
    -- Calculate overtime (compare with scheduled hours from contract)
    select 
      case 
        when c.weekly_hours is not null then c.weekly_hours / 5.0 -- Assuming 5-day work week
        when ws.weekly_hours is not null then ws.weekly_hours / 5.0
        else 9.0 -- Default 9 hours/day
      end
    into v_scheduled_hours
    from employees e
    left join employee_contracts c on c.employee_id = e.id and c.status = 'active'
    left join work_schedules ws on ws.id = c.work_schedule_id
    where e.id = NEW.employee_id
    limit 1;
    
    v_scheduled_hours := coalesce(v_scheduled_hours, 9.0);
    v_overtime := greatest(0, v_hours - v_scheduled_hours);
    NEW.overtime_hours := v_overtime;
    
    -- Auto-complete status
    if NEW.status = 'ongoing' then
      NEW.status := 'completed';
    end if;
  end if;
  
  return NEW;
end;
$$;

-- Trigger: Auto-calculate hours on check-out
drop trigger if exists trg_calculate_attendance_hours on attendances cascade;
create trigger trg_calculate_attendance_hours
  before insert or update on attendances
  for each row execute procedure public.calculate_attendance_hours();

-- Function: Prevent duplicate ongoing attendances for same employee
create or replace function public.prevent_duplicate_checkin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ongoing_count integer;
begin
  -- Only check on INSERT or when status becomes 'ongoing'
  if (TG_OP = 'INSERT' or (TG_OP = 'UPDATE' and NEW.status = 'ongoing')) 
     and NEW.status = 'ongoing' and NEW.check_out is null then
    
    select count(*) into v_ongoing_count
    from attendances
    where employee_id = NEW.employee_id
      and status = 'ongoing'
      and check_out is null
      and id != coalesce(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);
    
    if v_ongoing_count > 0 then
      raise exception 'Employee % already has an ongoing attendance session', NEW.employee_id;
    end if;
  end if;
  
  return NEW;
end;
$$;

drop trigger if exists trg_prevent_duplicate_checkin on attendances cascade;
create trigger trg_prevent_duplicate_checkin
  before insert or update on attendances
  for each row execute procedure public.prevent_duplicate_checkin();

-- Function: Get current checked-in employees
-- Drop and recreate to change return type signature
drop function if exists public.get_checked_in_employees();

create or replace function public.get_checked_in_employees()
returns table (
  attendance_id uuid,
  employee_id uuid,
  employee_name text,
  check_in timestamp with time zone,
  hours_worked numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select 
    a.id as attendance_id,
    a.employee_id,
    e.first_name || ' ' || e.last_name as employee_name,
    a.check_in,
    round(extract(epoch from (now() - a.check_in)) / 3600.0, 2) as hours_worked
  from attendances a
  join employees e on e.id = a.employee_id
  where a.status = 'ongoing'
    and a.check_out is null
  order by a.check_in;
end;
$$;

-- Function: Get attendance summary for period
create or replace function public.get_attendance_summary(
  p_employee_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (
  total_days integer,
  total_hours numeric,
  total_overtime numeric,
  average_hours numeric,
  late_arrivals integer,
  early_departures integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select 
    count(distinct date(a.check_in))::integer as total_days,
    coalesce(sum(a.worked_hours), 0) as total_hours,
    coalesce(sum(a.overtime_hours), 0) as total_overtime,
    coalesce(avg(a.worked_hours), 0) as average_hours,
    count(*) filter (where extract(hour from a.check_in) > 9)::integer as late_arrivals,
    count(*) filter (where extract(hour from a.check_out) < 18)::integer as early_departures
  from attendances a
  where a.employee_id = p_employee_id
    and a.status in ('completed', 'approved')
    and date(a.check_in) between p_start_date and p_end_date;
end;
$$;

-- Updated_at triggers for HR tables
drop trigger if exists trg_departments_updated_at on departments cascade;
create trigger trg_departments_updated_at
  before update on departments
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_employees_updated_at on employees cascade;
create trigger trg_employees_updated_at
  before update on employees
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_work_schedules_updated_at on work_schedules cascade;
create trigger trg_work_schedules_updated_at
  before update on work_schedules
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_employee_contracts_updated_at on employee_contracts cascade;
create trigger trg_employee_contracts_updated_at
  before update on employee_contracts
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_attendances_updated_at on attendances cascade;
create trigger trg_attendances_updated_at
  before update on attendances
  for each row execute procedure public.set_updated_at();

-- Note: Default work schedules will be seeded via trigger when tenant is created
-- (Cannot seed global data in multi-tenant architecture - each tenant needs their own)

-- Note: Default departments will be seeded via trigger when tenant is created
-- (Cannot seed global data in multi-tenant architecture - each tenant needs their own)

-- ============================================================================
-- HR MODULE: ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on HR tables
alter table employees enable row level security;
alter table departments enable row level security;
alter table attendances enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- ============================================================================
-- E-COMMERCE / WEBSITE MODULE TABLES
-- ============================================================================
-- This section implements the website builder and online store functionality.
-- Features:
-- - Homepage content management (banners, featured products, promotional text)
-- - Product visibility control for online store
-- - Customer orders from website (sync with sales invoices)
-- - Website settings and configuration
-- - Google Merchant Center feed support

-- Website banners (hero images, promotional banners)
create table if not exists website_banners (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  title text not null,
  subtitle text,
  image_url text,
  link text,
  cta_text text, -- Call-to-action button text
  cta_link text, -- Call-to-action button link
  active boolean default true,
  order_index integer default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_website_banners_tenant on website_banners(tenant_id);
  create index if not exists idx_website_banners_active on website_banners(active, order_index);
exception
  when undefined_table then raise notice '⚠ Table website_banners does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in website_banners';
end $$;

-- Featured products (handpicked products to display on homepage)
create table if not exists featured_products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  active boolean default true,
  order_index integer default 0,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_featured_products_tenant on featured_products(tenant_id);
  create index if not exists idx_featured_products_product on featured_products(product_id);
  create index if not exists idx_featured_products_active on featured_products(active, order_index);
exception
  when undefined_table then raise notice '⚠ Table featured_products does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in featured_products';
end $$;

-- Website content (rich text content blocks for homepage, about page, etc.)
create table if not exists website_content (
  id text primary key, -- e.g., 'homepage_promo', 'about_us', 'terms_conditions'
  tenant_id uuid references tenants(id) on delete cascade not null,
  title text not null,
  content text, -- HTML or markdown content
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_website_content_tenant on website_content(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table website_content does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in website_content';
end $$;

-- Website blocks (Odoo-style visual editor blocks)
create table if not exists website_blocks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  page_id uuid, -- References website_pages (added later via ALTER)
  block_type text not null, -- 'hero', 'products', 'services', 'about', 'testimonials', 'features', 'cta', 'gallery', 'contact'
  block_data jsonb not null default '{}'::jsonb, -- All block properties (title, subtitle, images, etc.)
  is_visible boolean default true,
  order_index integer default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_website_blocks_tenant on website_blocks(tenant_id);
  create index if not exists idx_website_blocks_visible on website_blocks(is_visible, order_index);
  create index if not exists idx_website_blocks_type on website_blocks(block_type);
exception
  when undefined_table then raise notice '⚠ Table website_blocks does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in website_blocks';
end $$;

-- ============================================================================
-- WEBSITE PAGES - Multi-page support for visual editor (Dec 2025)
-- ============================================================================
-- Enables creating multiple pages (Home, Services, About, Contact, etc.)
-- Each page can have its own set of blocks, SEO settings, and publish status

create table if not exists website_pages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  
  -- Page identification
  slug text not null, -- URL path: 'inicio', 'servicios', 'contacto', 'mi-pagina'
  title text not null, -- Page title for browser tab and SEO
  
  -- SEO fields
  meta_title text, -- Override for <title> tag (if different from title)
  meta_description text, -- Meta description for search engines
  meta_keywords text, -- Comma-separated keywords
  og_image_url text, -- Open Graph image for social sharing
  
  -- Page status
  is_published boolean default false, -- Only published pages are visible to public
  is_home boolean default false, -- Only ONE page per tenant can be home
  is_system boolean default false, -- System pages can't be deleted (home, products, cart)
  
  -- Template
  template text default 'default', -- 'default', 'landing', 'blog', 'product-list'
  
  -- Timestamps
  published_at timestamp with time zone, -- When page was first published
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  
  -- Constraints
  unique(tenant_id, slug) -- Each tenant can have one page per slug
);

create index if not exists idx_website_pages_tenant on website_pages(tenant_id);
create index if not exists idx_website_pages_slug on website_pages(slug);
create index if not exists idx_website_pages_published on website_pages(is_published) where is_published = true;
create index if not exists idx_website_pages_home on website_pages(tenant_id, is_home) where is_home = true;

-- RLS for website_pages
alter table website_pages enable row level security;

drop policy if exists "website_pages_select" on website_pages;
drop policy if exists "website_pages_insert" on website_pages;
drop policy if exists "website_pages_update" on website_pages;
drop policy if exists "website_pages_delete" on website_pages;

-- Authenticated users can:
-- 1. View ANY published page (for browsing public stores while logged in)
-- 2. View their own tenant's pages (including unpublished, for editing)
create policy "website_pages_select" on website_pages
  for select to authenticated
  using (
    is_published = true  -- Anyone can see published pages
    OR tenant_id = public.user_tenant_id()  -- Owners can see all their pages
  );

create policy "website_pages_insert" on website_pages
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "website_pages_update" on website_pages
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "website_pages_delete" on website_pages
  for delete to authenticated
  using (tenant_id = public.user_tenant_id() and is_system = false);

-- Public access policy for published pages (anonymous users viewing website)
drop policy if exists "website_pages_select_public" on website_pages;
create policy "website_pages_select_public" on website_pages
  for select to anon
  using (is_published = true);

-- Trigger to ensure only one home page per tenant
create or replace function ensure_single_home_page()
returns trigger as $$
begin
  if NEW.is_home = true then
    update website_pages
    set is_home = false, updated_at = now()
    where tenant_id = NEW.tenant_id
      and id != NEW.id
      and is_home = true;
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_ensure_single_home_page on website_pages;
create trigger trg_ensure_single_home_page
  before insert or update of is_home on website_pages
  for each row
  when (NEW.is_home = true)
  execute function ensure_single_home_page();

-- Trigger to set published_at on first publish
create or replace function set_published_at()
returns trigger as $$
begin
  if NEW.is_published = true and OLD.is_published = false and NEW.published_at is null then
    NEW.published_at := now();
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_set_published_at on website_pages;
create trigger trg_set_published_at
  before update of is_published on website_pages
  for each row
  execute function set_published_at();

-- ============================================================================
-- WEBSITE NAVIGATION - Menu and link management (Dec 2025)
-- ============================================================================
-- Enables creating header menus, footer links, and dropdown navigation
-- Links can point to pages, external URLs, product categories, or anchors

create table if not exists website_navigation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  
  -- Menu location
  menu_location text not null default 'header', -- 'header', 'footer', 'sidebar'
  
  -- Link display
  label text not null, -- Text shown to users
  icon text, -- Optional icon name (e.g., 'home', 'shopping_bag')
  
  -- Link target
  link_type text not null default 'page', -- 'page', 'external', 'anchor', 'category', 'action'
  link_value text, -- page_id (uuid), URL, #anchor, category_id, or action name
  open_in_new_tab boolean default false,
  
  -- Hierarchy (for dropdowns)
  parent_id uuid references website_navigation(id) on delete cascade,
  
  -- Order and visibility
  order_index integer default 0,
  is_visible boolean default true,
  
  -- Responsive visibility
  show_on_desktop boolean default true,
  show_on_mobile boolean default true,
  
  -- Styling (optional)
  css_class text, -- Custom CSS class for styling
  highlight boolean default false, -- Makes item stand out (e.g., "Contact Us" button)
  
  -- Timestamps
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_website_navigation_tenant on website_navigation(tenant_id);
create index if not exists idx_website_navigation_location on website_navigation(menu_location);
create index if not exists idx_website_navigation_parent on website_navigation(parent_id);
create index if not exists idx_website_navigation_order on website_navigation(menu_location, order_index);

-- RLS for website_navigation
alter table website_navigation enable row level security;

drop policy if exists "website_navigation_select" on website_navigation;
drop policy if exists "website_navigation_insert" on website_navigation;
drop policy if exists "website_navigation_update" on website_navigation;
drop policy if exists "website_navigation_delete" on website_navigation;

create policy "website_navigation_select" on website_navigation
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "website_navigation_insert" on website_navigation
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "website_navigation_update" on website_navigation
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "website_navigation_delete" on website_navigation
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Public access policy for navigation (anonymous users viewing website)
drop policy if exists "website_navigation_select_public" on website_navigation;
create policy "website_navigation_select_public" on website_navigation
  for select to anon
  using (is_visible = true);

-- ============================================================================
-- MIGRATION: Add page_id to website_blocks (links blocks to pages)
-- ============================================================================
alter table website_blocks add column if not exists page_id uuid references website_pages(id) on delete cascade;
create index if not exists idx_website_blocks_page on website_blocks(page_id);

-- ============================================================================
-- SEED DEFAULT PAGES FOR NEW TENANTS
-- ============================================================================
-- This function creates default pages when a new tenant is created
-- Called from handle_new_tenant() trigger

create or replace function seed_website_pages(p_tenant_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_home_page_id uuid;
  v_products_page_id uuid;
  v_contact_page_id uuid;
  v_about_page_id uuid;
  v_terms_page_id uuid;
  v_privacy_page_id uuid;
  v_returns_page_id uuid;
  v_shipping_page_id uuid;
begin
  -- Create Home page (system page, is_home = true)
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'inicio', 'Inicio', true, true, true, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_home_page_id;
  
  -- Create Products page (system page)
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'productos', 'Productos', true, false, true, 'product-list')
  on conflict (tenant_id, slug) do nothing
  returning id into v_products_page_id;
  
  -- Create Contact page
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'contacto', 'Contacto', true, false, false, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_contact_page_id;
  
  -- ============================================
  -- POLICY PAGES (Required for Google Merchant)
  -- ============================================
  
  -- About Us page
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'nosotros', 'Sobre Nosotros', true, false, false, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_about_page_id;
  
  -- Terms and Conditions
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'terminos', 'Términos y Condiciones', true, false, false, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_terms_page_id;
  
  -- Privacy Policy
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'privacidad', 'Política de Privacidad', true, false, false, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_privacy_page_id;
  
  -- Returns Policy
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'devoluciones', 'Política de Devoluciones', true, false, false, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_returns_page_id;
  
  -- Shipping Info
  insert into website_pages (tenant_id, slug, title, is_published, is_home, is_system, template)
  values (p_tenant_id, 'envios', 'Información de Envíos', true, false, false, 'default')
  on conflict (tenant_id, slug) do nothing
  returning id into v_shipping_page_id;
  
  -- Migrate existing blocks to home page (for existing tenants)
  update website_blocks
  set page_id = v_home_page_id
  where tenant_id = p_tenant_id and page_id is null;
  
  -- Create default navigation for header (only if no nav exists)
  if not exists (select 1 from website_navigation where tenant_id = p_tenant_id and menu_location = 'header') then
    insert into website_navigation (tenant_id, menu_location, label, link_type, link_value, order_index)
    values 
      (p_tenant_id, 'header', 'Inicio', 'page', v_home_page_id::text, 0),
      (p_tenant_id, 'header', 'Productos', 'page', v_products_page_id::text, 1),
      (p_tenant_id, 'header', 'Contacto', 'page', v_contact_page_id::text, 2);
  end if;
  
  raise notice '✅ Seeded website pages and navigation for tenant %', p_tenant_id;
end;
$$;

-- ============================================================================
-- SEED POLICY PAGE CONTENT (Required for Google Merchant Center compliance)
-- ============================================================================
-- Creates professional content blocks for policy pages
-- Call this after seed_website_pages to populate content

create or replace function seed_policy_page_content(p_tenant_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_page_id uuid;
  v_order_index integer;
begin
  -- ============================================
  -- ABOUT US PAGE (Sobre Nosotros)
  -- ============================================
  select id into v_page_id from website_pages 
  where tenant_id = p_tenant_id and slug = 'nosotros';
  
  if v_page_id is not null and not exists (
    select 1 from website_blocks where page_id = v_page_id
  ) then
    -- Hero section
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'hero', 0, true, jsonb_build_object(
      'title', 'Sobre Nosotros',
      'subtitle', 'Conoce nuestra historia y compromiso con el ciclismo',
      'background_color', '#1a1a2e',
      'text_color', '#ffffff',
      'height', 'small'
    ));
    
    -- Content section
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'rich_text', 1, true, jsonb_build_object(
      'content', '<div style="max-width: 800px; margin: 0 auto; padding: 60px 20px;">
        <h2 style="font-size: 32px; margin-bottom: 24px; color: #1a1a2e;">Nuestra Historia</h2>
        <p style="font-size: 18px; line-height: 1.8; color: #444; margin-bottom: 24px;">
          Somos una empresa chilena dedicada al mundo del ciclismo, con años de experiencia 
          brindando productos de calidad y servicio técnico especializado. Nuestra pasión 
          por las bicicletas nos impulsa a ofrecer siempre lo mejor a nuestros clientes.
        </p>
        <h2 style="font-size: 32px; margin-bottom: 24px; color: #1a1a2e; margin-top: 48px;">Nuestra Misión</h2>
        <p style="font-size: 18px; line-height: 1.8; color: #444; margin-bottom: 24px;">
          Promover el ciclismo como estilo de vida saludable y sustentable, ofreciendo 
          productos de calidad, asesoría experta y servicio técnico profesional.
        </p>
        <h2 style="font-size: 32px; margin-bottom: 24px; color: #1a1a2e; margin-top: 48px;">¿Por qué elegirnos?</h2>
        <ul style="font-size: 18px; line-height: 2; color: #444;">
          <li>Amplia variedad de bicicletas y accesorios</li>
          <li>Servicio técnico con mecánicos certificados</li>
          <li>Garantía en todos nuestros productos</li>
          <li>Atención personalizada y asesoría experta</li>
          <li>Envíos a todo Chile</li>
        </ul>
      </div>',
      'background_color', '#ffffff'
    ));
  end if;
  
  -- ============================================
  -- TERMS AND CONDITIONS PAGE
  -- ============================================
  select id into v_page_id from website_pages 
  where tenant_id = p_tenant_id and slug = 'terminos';
  
  if v_page_id is not null and not exists (
    select 1 from website_blocks where page_id = v_page_id
  ) then
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'hero', 0, true, jsonb_build_object(
      'title', 'Términos y Condiciones',
      'subtitle', 'Condiciones de uso de nuestro sitio web y servicios',
      'background_color', '#1a1a2e',
      'text_color', '#ffffff',
      'height', 'small'
    ));
    
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'rich_text', 1, true, jsonb_build_object(
      'content', '<div style="max-width: 800px; margin: 0 auto; padding: 60px 20px;">
        <p style="color: #666; margin-bottom: 32px;">Última actualización: Diciembre 2025</p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">1. Aceptación de los Términos</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Al acceder y utilizar este sitio web, usted acepta estar sujeto a estos términos y 
          condiciones de uso. Si no está de acuerdo con alguna parte de estos términos, 
          le rogamos que no utilice nuestro sitio web.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">2. Uso del Sitio</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Este sitio web está destinado únicamente para uso personal y no comercial. 
          Usted se compromete a utilizar el sitio de manera responsable y de acuerdo 
          con la legislación vigente en Chile.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">3. Productos y Precios</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Los precios mostrados en el sitio incluyen IVA y están expresados en pesos chilenos (CLP). 
          Nos reservamos el derecho de modificar los precios sin previo aviso. Las fotografías 
          de los productos son referenciales.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">4. Proceso de Compra</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Al realizar una compra, usted confirma que la información proporcionada es veraz y completa. 
          Nos reservamos el derecho de cancelar pedidos si detectamos información incorrecta o 
          actividad fraudulenta.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">5. Propiedad Intelectual</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Todo el contenido de este sitio web, incluyendo textos, imágenes, logotipos y diseños, 
          está protegido por derechos de autor y no puede ser reproducido sin autorización expresa.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">6. Limitación de Responsabilidad</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          No seremos responsables por daños indirectos, incidentales o consecuentes derivados 
          del uso de nuestro sitio web o productos, más allá de lo establecido por la ley chilena.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">7. Legislación Aplicable</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Estos términos se rigen por las leyes de la República de Chile. Cualquier disputa 
          será sometida a los tribunales competentes de la ciudad de Viña del Mar.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">8. Contacto</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444;">
          Para consultas sobre estos términos, contáctenos a través de nuestro formulario 
          de contacto o al correo electrónico indicado en el sitio.
        </p>
      </div>',
      'background_color', '#ffffff'
    ));
  end if;
  
  -- ============================================
  -- PRIVACY POLICY PAGE
  -- ============================================
  select id into v_page_id from website_pages 
  where tenant_id = p_tenant_id and slug = 'privacidad';
  
  if v_page_id is not null and not exists (
    select 1 from website_blocks where page_id = v_page_id
  ) then
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'hero', 0, true, jsonb_build_object(
      'title', 'Política de Privacidad',
      'subtitle', 'Cómo protegemos y utilizamos tu información',
      'background_color', '#1a1a2e',
      'text_color', '#ffffff',
      'height', 'small'
    ));
    
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'rich_text', 1, true, jsonb_build_object(
      'content', '<div style="max-width: 800px; margin: 0 auto; padding: 60px 20px;">
        <p style="color: #666; margin-bottom: 32px;">Última actualización: Diciembre 2025</p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">1. Información que Recopilamos</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
          Recopilamos información que usted nos proporciona directamente:
        </p>
        <ul style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          <li>Nombre y apellidos</li>
          <li>Dirección de correo electrónico</li>
          <li>Número de teléfono</li>
          <li>Dirección de envío y facturación</li>
          <li>RUT (para facturación)</li>
          <li>Información de pago (procesada de forma segura por terceros)</li>
        </ul>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">2. Uso de la Información</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
          Utilizamos su información para:
        </p>
        <ul style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          <li>Procesar y enviar sus pedidos</li>
          <li>Comunicarnos sobre su compra o servicio técnico</li>
          <li>Enviar información sobre promociones (solo si usted lo autoriza)</li>
          <li>Mejorar nuestros productos y servicios</li>
          <li>Cumplir con obligaciones legales y tributarias</li>
        </ul>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">3. Protección de Datos</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Implementamos medidas de seguridad técnicas y organizativas para proteger su información 
          personal contra acceso no autorizado, alteración o destrucción. Utilizamos conexiones 
          seguras (HTTPS/SSL) para todas las transacciones.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">4. Compartir Información</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          No vendemos ni compartimos su información personal con terceros, excepto cuando es 
          necesario para procesar su pedido (empresas de envío, procesadores de pago) o 
          cuando la ley lo requiere.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">5. Cookies</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Utilizamos cookies para mejorar su experiencia de navegación, recordar sus preferencias 
          y analizar el uso del sitio. Puede configurar su navegador para rechazar cookies, 
          aunque esto podría afectar algunas funcionalidades.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">6. Sus Derechos</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
          Conforme a la Ley 19.628 sobre Protección de Datos Personales, usted tiene derecho a:
        </p>
        <ul style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          <li>Acceder a sus datos personales</li>
          <li>Solicitar la rectificación de datos inexactos</li>
          <li>Solicitar la eliminación de sus datos</li>
          <li>Oponerse al tratamiento de sus datos</li>
        </ul>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">7. Contacto</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444;">
          Para ejercer sus derechos o consultas sobre privacidad, contáctenos a través 
          de nuestro formulario de contacto.
        </p>
      </div>',
      'background_color', '#ffffff'
    ));
  end if;
  
  -- ============================================
  -- RETURNS POLICY PAGE
  -- ============================================
  select id into v_page_id from website_pages 
  where tenant_id = p_tenant_id and slug = 'devoluciones';
  
  if v_page_id is not null and not exists (
    select 1 from website_blocks where page_id = v_page_id
  ) then
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'hero', 0, true, jsonb_build_object(
      'title', 'Política de Devoluciones',
      'subtitle', 'Garantía y cambios de productos',
      'background_color', '#1a1a2e',
      'text_color', '#ffffff',
      'height', 'small'
    ));
    
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'rich_text', 1, true, jsonb_build_object(
      'content', '<div style="max-width: 800px; margin: 0 auto; padding: 60px 20px;">
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Garantía Legal</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Todos nuestros productos cuentan con garantía legal de 6 meses según la Ley del 
          Consumidor chilena (Ley 19.496). Esta garantía cubre defectos de fabricación 
          y mal funcionamiento bajo uso normal.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Derecho a Retracto</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Para compras realizadas a través de nuestro sitio web, usted tiene derecho a 
          retractarse de la compra dentro de los 10 días siguientes a la recepción del 
          producto, siempre que este se encuentre en su empaque original, sin uso y 
          con todos sus accesorios.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Proceso de Devolución</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
          Para solicitar una devolución:
        </p>
        <ol style="font-size: 16px; line-height: 2; color: #444; margin-bottom: 32px;">
          <li>Contáctenos indicando su número de pedido y motivo de la devolución</li>
          <li>Recibirá instrucciones para el envío del producto</li>
          <li>Una vez recibido y verificado el producto, procesaremos el reembolso</li>
          <li>El reembolso se realizará por el mismo medio de pago utilizado</li>
        </ol>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Excepciones</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
          No se aceptan devoluciones en los siguientes casos:
        </p>
        <ul style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          <li>Productos usados o con señales de uso</li>
          <li>Productos sin empaque original o accesorios</li>
          <li>Daños causados por mal uso o accidentes</li>
          <li>Productos personalizados o a pedido</li>
          <li>Desgaste normal de componentes (neumáticos, frenos, cadenas)</li>
        </ul>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Cambios</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Aceptamos cambios de talla o modelo dentro de 15 días desde la recepción, 
          sujeto a disponibilidad de stock. El cliente asume el costo de envío del cambio.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Contacto</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444;">
          Para gestionar devoluciones o cambios, contáctenos a través de nuestro 
          formulario de contacto o directamente en nuestra tienda.
        </p>
      </div>',
      'background_color', '#ffffff'
    ));
  end if;
  
  -- ============================================
  -- SHIPPING INFO PAGE
  -- ============================================
  select id into v_page_id from website_pages 
  where tenant_id = p_tenant_id and slug = 'envios';
  
  if v_page_id is not null and not exists (
    select 1 from website_blocks where page_id = v_page_id
  ) then
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'hero', 0, true, jsonb_build_object(
      'title', 'Información de Envíos',
      'subtitle', 'Despacho a todo Chile',
      'background_color', '#1a1a2e',
      'text_color', '#ffffff',
      'height', 'small'
    ));
    
    insert into website_blocks (tenant_id, page_id, block_type, order_index, is_visible, block_data)
    values (p_tenant_id, v_page_id, 'rich_text', 1, true, jsonb_build_object(
      'content', '<div style="max-width: 800px; margin: 0 auto; padding: 60px 20px;">
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Cobertura</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Realizamos envíos a todo Chile continental. Para zonas extremas (Arica, Punta Arenas, 
          Chiloé y otras islas), los tiempos y costos pueden variar.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Costos de Envío</h2>
        <div style="background: #f8f9fa; padding: 24px; border-radius: 8px; margin-bottom: 32px;">
          <p style="font-size: 18px; color: #1a1a2e; margin-bottom: 16px;"><strong>Región Metropolitana:</strong></p>
          <ul style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
            <li>Envío estándar: $3.990</li>
            <li>Envío express (24-48 hrs): $5.990</li>
          </ul>
          <p style="font-size: 18px; color: #1a1a2e; margin-bottom: 16px;"><strong>Regiones:</strong></p>
          <ul style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 16px;">
            <li>Zona norte y sur: Desde $5.990</li>
            <li>Zonas extremas: Desde $9.990</li>
          </ul>
          <p style="font-size: 18px; color: #28a745; font-weight: bold;">
            🚚 ¡Envío GRATIS en compras sobre $50.000!
          </p>
        </div>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Tiempos de Entrega</h2>
        <ul style="font-size: 16px; line-height: 2; color: #444; margin-bottom: 32px;">
          <li><strong>Viña del Mar / Valparaíso:</strong> 1-2 días hábiles</li>
          <li><strong>Región Metropolitana:</strong> 2-3 días hábiles</li>
          <li><strong>Otras regiones:</strong> 3-5 días hábiles</li>
          <li><strong>Zonas extremas:</strong> 5-10 días hábiles</li>
        </ul>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Retiro en Tienda</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          También puede retirar su compra sin costo en nuestra tienda. Recibirá un correo 
          de confirmación cuando su pedido esté listo para retiro (generalmente 24 horas hábiles).
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Seguimiento</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444; margin-bottom: 32px;">
          Una vez despachado su pedido, recibirá un correo con el número de seguimiento 
          para rastrear su envío en tiempo real.
        </p>
        
        <h2 style="font-size: 24px; margin-bottom: 16px; color: #1a1a2e;">Bicicletas</h2>
        <p style="font-size: 16px; line-height: 1.8; color: #444;">
          Las bicicletas se envían parcialmente armadas para mayor seguridad. Incluimos 
          instrucciones de armado final. Para bicicletas de alta gama, recomendamos 
          retiro en tienda donde nuestros mecánicos realizan el armado completo sin costo adicional.
        </p>
      </div>',
      'background_color', '#ffffff'
    ));
  end if;
  
  raise notice '✅ Seeded policy page content for tenant %', p_tenant_id;
end;
$$;


-- Website settings (store configuration)
create table if not exists website_settings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  key text not null,
  value text,
  description text,
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, key)
);

do $$ begin
  create index if not exists idx_website_settings_tenant on website_settings(tenant_id);
  create index if not exists idx_website_settings_key on website_settings(key);
exception
  when undefined_table then raise notice '⚠ Table website_settings does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in website_settings';
end $$;

-- ============================================================================
-- WEBSITE BACKUPS - Snapshot/restore system for website blocks (Dec 2025)
-- ============================================================================
-- Allows saving complete snapshots of website content that can be restored later
-- Useful for: before major redesigns, seasonal versions, recovering from mistakes

create table if not exists website_backups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  
  -- Backup metadata
  name text not null, -- User-friendly name: "Before holiday redesign", "V1 Launch"
  description text, -- Optional notes about this backup
  
  -- Snapshot data (complete copy of website state)
  blocks_snapshot jsonb not null default '[]'::jsonb, -- Array of all website_blocks
  settings_snapshot jsonb not null default '{}'::jsonb, -- All website_settings as key-value pairs
  pages_snapshot jsonb default '[]'::jsonb, -- Array of website_pages (for multi-page support)
  
  -- Metadata
  block_count integer default 0, -- How many blocks in this backup
  is_auto_backup boolean default false, -- True if system-generated (e.g., before restore)
  
  -- Timestamps
  created_at timestamp with time zone not null default now(),
  created_by uuid references auth.users(id) on delete set null -- Who created the backup
);

create index if not exists idx_website_backups_tenant on website_backups(tenant_id);
create index if not exists idx_website_backups_created on website_backups(created_at desc);
create index if not exists idx_website_backups_auto on website_backups(is_auto_backup);

-- RLS for website_backups
alter table website_backups enable row level security;

drop policy if exists "website_backups_select" on website_backups;
drop policy if exists "website_backups_insert" on website_backups;
drop policy if exists "website_backups_update" on website_backups;
drop policy if exists "website_backups_delete" on website_backups;

create policy "website_backups_select" on website_backups
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "website_backups_insert" on website_backups
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "website_backups_update" on website_backups
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "website_backups_delete" on website_backups
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Function to create a website backup
create or replace function public.create_website_backup(
  p_name text,
  p_description text default null,
  p_is_auto boolean default false
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_tenant_id uuid;
  v_backup_id uuid;
  v_blocks jsonb;
  v_settings jsonb;
  v_pages jsonb;
  v_block_count integer;
begin
  -- Get current user's tenant
  v_tenant_id := public.user_tenant_id();
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;
  
  -- Snapshot all blocks
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', id,
      'block_type', block_type,
      'block_data', block_data,
      'is_visible', is_visible,
      'order_index', order_index,
      'page_id', page_id
    ) order by order_index
  ), '[]'::jsonb)
  into v_blocks
  from website_blocks
  where tenant_id = v_tenant_id;
  
  -- Count blocks
  select count(*) into v_block_count from website_blocks where tenant_id = v_tenant_id;
  
  -- Snapshot all settings as key-value object
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  into v_settings
  from website_settings
  where tenant_id = v_tenant_id;
  
  -- Snapshot all pages
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', id,
      'slug', slug,
      'title', title,
      'meta_title', meta_title,
      'meta_description', meta_description,
      'is_published', is_published,
      'is_home', is_home,
      'template', template
    ) order by created_at
  ), '[]'::jsonb)
  into v_pages
  from website_pages
  where tenant_id = v_tenant_id;
  
  -- Insert backup
  insert into website_backups (
    tenant_id,
    name,
    description,
    blocks_snapshot,
    settings_snapshot,
    pages_snapshot,
    block_count,
    is_auto_backup,
    created_by
  ) values (
    v_tenant_id,
    p_name,
    p_description,
    v_blocks,
    v_settings,
    v_pages,
    v_block_count,
    p_is_auto,
    auth.uid()
  )
  returning id into v_backup_id;
  
  return v_backup_id;
end;
$$;

-- Function to restore a website backup
create or replace function public.restore_website_backup(
  p_backup_id uuid,
  p_create_safety_backup boolean default true
)
returns boolean
language plpgsql
security definer
as $$
declare
  v_tenant_id uuid;
  v_backup record;
  v_block record;
begin
  -- Get current user's tenant
  v_tenant_id := public.user_tenant_id();
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;
  
  -- Get the backup
  select * into v_backup
  from website_backups
  where id = p_backup_id and tenant_id = v_tenant_id;
  
  if not found then
    raise exception 'Backup not found or access denied';
  end if;
  
  -- Create safety backup before restoring (so user can undo)
  if p_create_safety_backup then
    perform public.create_website_backup(
      'Auto-backup before restore: ' || v_backup.name,
      'Automatic backup created before restoring to: ' || v_backup.name,
      true -- is_auto_backup
    );
  end if;
  
  -- Delete current blocks
  delete from website_blocks where tenant_id = v_tenant_id;
  
  -- Restore blocks from snapshot
  for v_block in select * from jsonb_array_elements(v_backup.blocks_snapshot)
  loop
    insert into website_blocks (
      id,
      tenant_id,
      block_type,
      block_data,
      is_visible,
      order_index,
      page_id
    ) values (
      coalesce((v_block.value->>'id')::uuid, gen_random_uuid()),
      v_tenant_id,
      v_block.value->>'block_type',
      (v_block.value->'block_data')::jsonb,
      coalesce((v_block.value->>'is_visible')::boolean, true),
      coalesce((v_block.value->>'order_index')::integer, 0),
      (v_block.value->>'page_id')::uuid
    );
  end loop;
  
  -- Restore settings (upsert each key-value pair)
  -- First, get all keys from the snapshot
  insert into website_settings (tenant_id, key, value)
  select 
    v_tenant_id,
    key,
    value
  from jsonb_each_text(v_backup.settings_snapshot)
  on conflict (tenant_id, key) do update
  set value = excluded.value, updated_at = now();
  
  return true;
end;
$$;

grant execute on function public.create_website_backup(text, text, boolean) to authenticated;
grant execute on function public.restore_website_backup(uuid, boolean) to authenticated;

-- Online orders (customer orders from website, separate from POS orders)
create table if not exists online_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  order_number text not null,
  customer_id uuid references customers(id) on delete set null,
  customer_email text not null,
  customer_name text not null,
  customer_phone text,
  customer_address text, -- Legacy: billing address (kept for backward compatibility)
  
  -- Order details
  subtotal numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  shipping_cost numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  
  -- Delivery type and shipping address
  delivery_type text not null default 'shipping' check (delivery_type in ('shipping', 'pickup')),
  shipping_address_line1 text,
  shipping_address_line2 text,
  shipping_city text,
  shipping_state text,
  shipping_postal_code text,
  shipping_country text default 'Chile',
  shipping_carrier text,
  tracking_url text,
  
  -- Order status (added ready_for_pickup for in-store pickup orders)
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'processing', 'ready_for_pickup', 'shipped', 'delivered', 'cancelled')),
  payment_status text not null default 'pending' check (payment_status in ('pending', 'paid', 'failed', 'refunded')),
  
  -- Payment details
  payment_method text,
  payment_reference text, -- Stripe/MercadoPago transaction ID
  paid_at timestamp with time zone,
  
  -- Tracking
  tracking_number text,
  shipped_at timestamp with time zone,
  delivered_at timestamp with time zone,
  ready_for_pickup_at timestamp with time zone, -- When order is ready for in-store pickup
  
  -- Cancellation/refund
  cancelled_at timestamp with time zone,
  cancelled_reason text,
  refund_amount numeric(12,2) default 0,
  refunded_at timestamp with time zone,
  
  -- ERP integration: Link to sales invoice when order is processed
  sales_invoice_id uuid references sales_invoices(id) on delete set null,
  
  -- Notes
  customer_notes text,
  internal_notes text,
  notes text, -- Admin notes
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, order_number)
);

-- Add new columns to existing table (for deployed databases)
do $$ begin
  -- Delivery type and shipping address
  alter table online_orders add column if not exists delivery_type text default 'shipping';
  alter table online_orders add column if not exists shipping_address_line1 text;
  alter table online_orders add column if not exists shipping_address_line2 text;
  alter table online_orders add column if not exists shipping_city text;
  alter table online_orders add column if not exists shipping_state text;
  alter table online_orders add column if not exists shipping_postal_code text;
  alter table online_orders add column if not exists shipping_country text default 'Chile';
  alter table online_orders add column if not exists shipping_carrier text;
  alter table online_orders add column if not exists tracking_url text;
  
  -- Pickup and cancellation
  alter table online_orders add column if not exists ready_for_pickup_at timestamp with time zone;
  alter table online_orders add column if not exists cancelled_at timestamp with time zone;
  alter table online_orders add column if not exists cancelled_reason text;
  alter table online_orders add column if not exists refund_amount numeric(12,2) default 0;
  alter table online_orders add column if not exists refunded_at timestamp with time zone;
  
  -- Admin notes
  alter table online_orders add column if not exists notes text;
  
  -- Update constraint to include ready_for_pickup
  alter table online_orders drop constraint if exists online_orders_status_check;
  alter table online_orders add constraint online_orders_status_check 
    check (status in ('pending', 'confirmed', 'processing', 'ready_for_pickup', 'shipped', 'delivered', 'cancelled'));
    
  -- Update constraint for delivery type
  alter table online_orders drop constraint if exists online_orders_delivery_type_check;
  alter table online_orders add constraint online_orders_delivery_type_check 
    check (delivery_type in ('shipping', 'pickup'));
  
  -- CLEANUP: Remove duplicate invoice_id column (consolidated to sales_invoice_id)
  -- First copy any data from invoice_id to sales_invoice_id if sales_invoice_id is null
  update online_orders 
  set sales_invoice_id = invoice_id 
  where sales_invoice_id is null and invoice_id is not null;
  
  -- Drop the redundant column
  alter table online_orders drop column if exists invoice_id;
    
  raise notice '✅ Added new columns to online_orders table';
exception
  when others then 
    raise notice '⚠ Some columns may already exist or table not found: %', sqlerrm;
end $$;

do $$ begin
  create index if not exists idx_online_orders_tenant on online_orders(tenant_id);
  create index if not exists idx_online_orders_customer on online_orders(customer_id);
  create index if not exists idx_online_orders_status on online_orders(status);
  create index if not exists idx_online_orders_payment_status on online_orders(payment_status);
  create index if not exists idx_online_orders_invoice on online_orders(sales_invoice_id);
  create index if not exists idx_online_orders_number on online_orders(order_number);
  create index if not exists idx_online_orders_created on online_orders(created_at desc);
exception
  when undefined_table then raise notice '⚠ Table online_orders does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in online_orders';
end $$;

-- Online order items
create table if not exists online_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  order_id uuid references online_orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_name text not null, -- Store name for historical record
  product_sku text,
  quantity integer not null,
  unit_price numeric(12,2) not null,
  subtotal numeric(12,2) not null,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_online_order_items_tenant on online_order_items(tenant_id);
  create index if not exists idx_online_order_items_order on online_order_items(order_id);
  create index if not exists idx_online_order_items_product on online_order_items(product_id);
exception
  when undefined_table then raise notice '⚠ Table online_order_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in online_order_items';
end $$;

-- Product visibility for online store (control which products appear on website)
alter table public.products
  add column if not exists show_on_website boolean default true,
  add column if not exists website_description text, -- SEO-friendly description
  add column if not exists website_featured boolean default false;

create index if not exists idx_products_website on products(show_on_website) where show_on_website = true;
create index if not exists idx_products_featured on products(website_featured) where website_featured = true;

-- ============================================================================
-- ROW LEVEL SECURITY FOR WEBSITE TABLES
-- ============================================================================

-- Website banners: RLS enabled (tenant-filtered policies added later)
alter table website_banners enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Featured products: RLS enabled (tenant-filtered policies added later)
alter table featured_products enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Website content: RLS enabled (tenant-filtered policies added later)
alter table website_content enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Website blocks: RLS enabled (tenant-filtered policies added later)
alter table website_blocks enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Website settings: RLS enabled (tenant-filtered policies added later)
alter table website_settings enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Online orders: RLS enabled (tenant-filtered policies added later)
alter table online_orders enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- Online order items: RLS enabled (tenant-filtered policies added later)
alter table online_order_items enable row level security;

-- Old non-tenant-filtered policies REMOVED to enforce multi-tenant isolation

-- ============================================================================
-- EMAIL PUSH NOTIFICATIONS (Gmail/Zoho instant notifications)
-- ============================================================================

-- Store push subscription state for instant email notifications
create table if not exists email_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  tenant_id uuid references tenants(id) on delete cascade not null,
  provider text not null check (provider in ('gmail', 'zoho')),
  
  -- Email address for lookup (Added Jan 10, 2026)
  email_address text,
  
  -- Gmail specific: historyId for incremental sync
  gmail_history_id text,
  gmail_expiration timestamp with time zone,
  
  -- Zoho specific  
  zoho_webhook_id text,
  
  -- Notification trigger: update this to trigger realtime to app
  new_mail_notification boolean default false,
  notification_data jsonb,
  
  -- Status
  is_active boolean default true,
  last_notification_at timestamp with time zone,
  error_message text,
  
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  
  unique(user_id, provider)
);

-- Indexes for email push subscriptions
create index if not exists idx_email_push_user on email_push_subscriptions(user_id);
create index if not exists idx_email_push_provider on email_push_subscriptions(provider);
create index if not exists idx_email_push_email on email_push_subscriptions(email_address);

-- RLS for email push subscriptions
alter table email_push_subscriptions enable row level security;

drop policy if exists "users_view_own_push_subscriptions" on email_push_subscriptions;
create policy "users_view_own_push_subscriptions" on email_push_subscriptions
  for select using (auth.uid() = user_id);

drop policy if exists "users_manage_own_push_subscriptions" on email_push_subscriptions;
create policy "users_manage_own_push_subscriptions" on email_push_subscriptions
  for all using (auth.uid() = user_id);

-- Enable realtime for push notifications to Flutter app
alter publication supabase_realtime add table email_push_subscriptions;

-- Function to trigger notification (called by Edge Function webhooks)
create or replace function public.notify_new_email(
  p_user_id uuid,
  p_provider text,
  p_history_id text default null,
  p_notification_data jsonb default null
)
returns void
language plpgsql
security definer
as $$
begin
  -- Update the subscription to trigger realtime notification
  update email_push_subscriptions
  set 
    new_mail_notification = true,
    notification_data = p_notification_data,
    gmail_history_id = coalesce(p_history_id, gmail_history_id),
    last_notification_at = now(),
    updated_at = now()
  where user_id = p_user_id and provider = p_provider;
  
  -- If no subscription exists, create one
  if not found then
    insert into email_push_subscriptions (user_id, tenant_id, provider, gmail_history_id, new_mail_notification, notification_data, last_notification_at)
    select 
      p_user_id,
      up.tenant_id,
      p_provider,
      p_history_id,
      true,
      p_notification_data,
      now()
    from user_profiles up
    where up.user_id = p_user_id
    limit 1;
  end if;
end;
$$;

-- Grant execute to service role (for Edge Functions)
grant execute on function public.notify_new_email(uuid, text, text, jsonb) to service_role;

-- ============================================================================
-- ONLINE ORDER SCHEMA EXTENSIONS
-- ============================================================================

-- Add delivery type and fulfillment tracking to online_orders
alter table online_orders
  add column if not exists delivery_type text not null default 'shipping' 
    check (delivery_type in ('shipping', 'pickup')),
  add column if not exists ready_for_pickup_at timestamp with time zone,
  add column if not exists cancelled_at timestamp with time zone,
  add column if not exists cancelled_reason text,
  add column if not exists refund_amount numeric(12,2) default 0,
  add column if not exists refunded_at timestamp with time zone;

-- Add shipping address details (separate from customer_address which is formatted)
alter table online_orders
  add column if not exists shipping_recipient_name text,
  add column if not exists shipping_phone text,
  add column if not exists shipping_street_address text,
  add column if not exists shipping_apartment text,
  add column if not exists shipping_comuna text,
  add column if not exists shipping_city text,
  add column if not exists shipping_region text,
  add column if not exists shipping_postal_code text;

-- Update status constraint to include ready_for_pickup
do $$
begin
  alter table online_orders drop constraint if exists online_orders_status_check;
  alter table online_orders add constraint online_orders_status_check 
    check (status in ('pending', 'confirmed', 'processing', 'ready_for_pickup', 'shipped', 'delivered', 'cancelled'));
exception when others then
  raise notice 'Could not update online_orders status constraint: %', sqlerrm;
end $$;

-- ============================================================================
-- FUNCTIONS FOR ONLINE ORDER PROCESSING
-- ============================================================================

-- Function to automatically create sales invoice from online order
-- This function handles different payment methods with different tax treatments:
--
-- MERCADOPAGO/CARD:
--   - tax_treatment = 'tax_included' (IVA 19%)
--   - invoice_status = 'paid' (if payment confirmed) or 'confirmed' (if pending)
--   - Creates payment record automatically
--   - Triggers inventory deduction + journal entry
--
-- WIRE TRANSFER/CASH:
--   - tax_treatment = 'no_tax' (no IVA on informal sales)
--   - invoice_status = 'sent' (pending manual confirmation)
--   - NO payment record (user confirms manually in ERP)
--   - Inventory NOT deducted until confirmed
create or replace function public.process_online_order(p_order_id uuid)
returns uuid -- Returns sales_invoice_id
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_items jsonb;
  v_next_number integer;
  v_year text;
  v_payment_method record;
  v_tenant_id uuid;
  v_net_amount numeric(12,2);
  v_iva_amount numeric(12,2);
  v_tax_treatment text;
  v_invoice_status text;
  v_should_create_payment boolean;
begin
  -- Get order details WITH ROW LOCK to prevent race conditions
  -- This ensures only one process can create an invoice for this order
  select * into v_order
  from online_orders
  where id = p_order_id
  for update;
  
  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;
  
  -- CRITICAL: Get tenant_id from the order
  v_tenant_id := v_order.tenant_id;
  if v_tenant_id is null then
    raise exception 'Order has no tenant_id: %', p_order_id;
  end if;
  
  -- Check if invoice already exists
  if v_order.sales_invoice_id is not null then
    -- Invoice exists - check if we need to update it to 'paid' status
    -- This handles the case where webhook arrives after invoice was created
    if v_order.payment_status = 'paid' then
      -- Get payment method for creating payment record
      select * into v_payment_method
      from payment_methods
      where tenant_id = v_tenant_id
        and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
        and is_active = true
      limit 1;
      
      -- If payment method not found, try fallback
      if v_payment_method is null then
        select * into v_payment_method
        from payment_methods
        where tenant_id = v_tenant_id
          and is_active = true
        order by sort_order
        limit 1;
      end if;
      
      -- Check if invoice is not already paid
      perform 1 from sales_invoices 
      where id = v_order.sales_invoice_id 
        and status != 'paid';
        
      if found then
        -- Update invoice to paid status
        update sales_invoices
        set status = 'paid',
            paid_amount = total,
            balance = 0,
            updated_at = now()
        where id = v_order.sales_invoice_id;
        
        -- Create payment record if not exists
        if not exists (
          select 1 from sales_payments 
          where invoice_id = v_order.sales_invoice_id
        ) and v_payment_method.id is not null then
          insert into sales_payments (
            tenant_id,
            invoice_id,
            invoice_reference,
            payment_method_id,
            amount,
            date,
            reference,
            notes
          ) values (
            v_tenant_id,
            v_order.sales_invoice_id,
            (select invoice_number from sales_invoices where id = v_order.sales_invoice_id),
            v_payment_method.id,
            v_order.total,
            coalesce(v_order.paid_at, now()),
            v_order.payment_reference,
            'Pago automático - Pedido online #' || v_order.order_number ||
            ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
          );
          
          raise notice 'Created payment record for existing invoice (order: %)', v_order.order_number;
        end if;
        
        raise notice 'Updated existing invoice to paid status (order: %)', v_order.order_number;
      end if;
    end if;
    
    return v_order.sales_invoice_id;
  end if;
  
  -- Get payment method configuration
  select * into v_payment_method
  from payment_methods
  where tenant_id = v_tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
    and is_active = true
  limit 1;
  
  -- If payment method not found, try fallback
  if v_payment_method is null then
    select * into v_payment_method
    from payment_methods
    where tenant_id = v_tenant_id
      and is_active = true
    order by sort_order
    limit 1;
  end if;
  
  -- ============================================================================
  -- DETERMINE TAX TREATMENT BASED ON PAYMENT METHOD
  -- ============================================================================
  -- MercadoPago/Card = tax_included (IVA 19%)
  -- Transfer/Cash = no_tax (use tax_amount from order, which frontend sets to 0)
  -- ============================================================================
  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    -- Calculate IVA: net = total / 1.19, iva = total - net
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
  else
    -- Transfer, cash, check = no tax
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
  end if;
  
  -- ============================================================================
  -- DETERMINE INVOICE STATUS BASED ON PAYMENT METHOD + STATUS
  -- ============================================================================
  -- MercadoPago + paid = 'paid' (fully processed)
  -- MercadoPago + pending = 'confirmed' (waiting for webhook)
  -- Transfer = 'sent' (waiting for manual bank confirmation)
  -- Cash on delivery = 'sent' (waiting for delivery confirmation)
  -- ============================================================================
  if v_order.payment_status = 'paid' then
    v_invoice_status := 'paid';
    v_should_create_payment := true;
  elsif lower(v_order.payment_method) = 'mercadopago' and v_order.payment_status = 'pending' then
    v_invoice_status := 'confirmed';
    v_should_create_payment := false;
  else
    -- Transfer, cash on delivery, or unknown = sent (pending)
    v_invoice_status := 'sent';
    v_should_create_payment := false;
  end if;
  
  -- Generate invoice number PER TENANT in format: INV-25-00001
  v_year := to_char(now(), 'YY');
  
  select coalesce(max(cast(substring(invoice_number from '\d+$') as integer)), 0) + 1
  into v_next_number
  from sales_invoices
  where tenant_id = v_tenant_id
    and invoice_number ~ ('^INV-' || v_year || '-\d+$');
  
  v_invoice_number := 'INV-' || v_year || '-' || lpad(v_next_number::text, 5, '0');
  
  -- Build items JSONB array from order items
  select jsonb_agg(
    jsonb_build_object(
      'product_id', oi.product_id,
      'product_name', oi.product_name,
      'product_sku', oi.product_sku,
      'quantity', oi.quantity,
      'price', oi.unit_price,
      'subtotal', oi.subtotal
    )
  ) into v_items
  from online_order_items oi
  where oi.order_id = p_order_id;
  
  -- Default to empty array if no items
  if v_items is null then
    v_items := '[]'::jsonb;
  end if;
  
  -- Create sales invoice WITH tenant_id
  -- Only 'paid' status triggers inventory deduction + journal entry
  insert into sales_invoices (
    tenant_id,
    invoice_number,
    customer_id,
    customer_name,
    date,
    due_date,
    status,
    tax_treatment,
    net_amount,
    subtotal,
    iva_amount,
    total,
    paid_amount,
    balance,
    items,
    reference
  ) values (
    v_tenant_id,
    v_invoice_number,
    v_order.customer_id,
    v_order.customer_name,
    now(),
    now() + interval '30 days',
    v_invoice_status,
    v_tax_treatment,
    v_net_amount,
    v_order.subtotal,
    v_iva_amount,
    v_order.total,
    case when v_should_create_payment then v_order.total else 0 end,
    case when v_should_create_payment then 0 else v_order.total end,
    v_items,
    'Pedido online #' || v_order.order_number || 
    case 
      when v_order.delivery_type = 'pickup' then ' (Retiro en tienda)'
      else ' (Envío)'
    end
  )
  returning id into v_invoice_id;
  
  raise notice 'Created invoice % (status: %, tax: %) for online order %', 
    v_invoice_number, v_invoice_status, v_tax_treatment, v_order.order_number;
  
  -- ============================================================================
  -- CRITICAL: Directly call inventory and journal functions here
  -- The trigger handle_sales_invoice_change has pg_trigger_depth() > 1 check
  -- which blocks processing when called from within another trigger
  -- So we call these functions directly to ensure they run
  -- ============================================================================
  if v_invoice_status in ('paid', 'confirmed') then
    -- Need to fetch the full invoice record to pass to functions
    declare
      v_invoice_record sales_invoices%rowtype;
    begin
      select * into v_invoice_record from sales_invoices where id = v_invoice_id;
      
      -- Consume inventory (deduct stock)
      raise notice 'Calling consume_sales_invoice_inventory for invoice %', v_invoice_number;
      perform public.consume_sales_invoice_inventory(v_invoice_record);
      
      -- Create sale journal entry
      raise notice 'Calling create_sales_invoice_journal_entry for invoice %', v_invoice_number;
      perform public.create_sales_invoice_journal_entry(v_invoice_record);
    end;
  end if;
  
  -- Link invoice to order + update order status
  update online_orders
  set 
    sales_invoice_id = v_invoice_id,
    status = case 
      when status = 'pending' then 'confirmed' 
      else status 
    end,
    updated_at = now()
  where id = p_order_id;
  
  -- Create payment record ONLY if payment is confirmed
  if v_should_create_payment and v_payment_method.id is not null then
    insert into sales_payments (
      tenant_id,
      invoice_id,
      invoice_reference,
      payment_method_id,
      amount,
      date,
      reference,
      notes
    ) values (
      v_tenant_id,
      v_invoice_id,
      v_invoice_number,
      v_payment_method.id,
      v_order.total,
      coalesce(v_order.paid_at, now()),
      v_order.payment_reference,
      'Pago automático - Pedido online #' || v_order.order_number ||
      ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
    );
    
    raise notice 'Created payment record for invoice % (method: %)', 
      v_invoice_number, v_payment_method.name;
  elsif not v_should_create_payment then
    raise notice 'Invoice % pending manual payment confirmation (method: %)',
      v_invoice_number, v_order.payment_method;
  end if;
  
  return v_invoice_id;
end;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: cancel_online_order
-- PURPOSE: Cancel an online order, handle refunds, restore inventory
-- CALLED BY: ERP admin panel when cancelling/refunding orders
--------------------------------------------------------------------------------
create or replace function public.cancel_online_order(
  p_order_id uuid,
  p_reason text default 'Cancelado por el administrador',
  p_refund_amount numeric default null -- null = full refund, 0 = no refund
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_order record;
  v_invoice record;
  v_actual_refund numeric;
  v_result jsonb;
begin
  -- Get the order with tenant context
  select * into v_order
  from online_orders
  where id = p_order_id
    and tenant_id = public.user_tenant_id();
    
  if v_order is null then
    raise exception 'Order not found or access denied: %', p_order_id;
  end if;
  
  -- Check if already cancelled
  if v_order.status = 'cancelled' then
    raise exception 'Order is already cancelled';
  end if;
  
  -- Get associated invoice if exists
  if v_order.sales_invoice_id is not null then
    select * into v_invoice
    from sales_invoices
    where id = v_order.sales_invoice_id;
  end if;
  
  -- Determine refund amount
  if p_refund_amount is null then
    v_actual_refund := v_order.total;
  else
    v_actual_refund := least(p_refund_amount, v_order.total);
  end if;
  
  -- Start cancellation process
  -- 1. Cancel/delete the invoice (which will restore inventory and delete journal entries)
  if v_invoice is not null then
    -- If invoice is posted (confirmada/pagada), we need to revert it first
    if v_invoice.status in ('confirmada', 'pagada') then
      -- Delete payments first (triggers will handle journal entry reversal)
      delete from sales_payments where invoice_id = v_invoice.id;
      
      -- Set invoice back to borrador (which triggers inventory restoration)
      update sales_invoices
      set status = 'borrador',
          updated_at = now()
      where id = v_invoice.id;
    end if;
    
    -- Now delete the invoice
    delete from sales_invoices where id = v_invoice.id;
    
    raise notice 'Deleted invoice % and restored inventory', v_invoice.invoice_number;
  end if;
  
  -- 2. Update the order status
  update online_orders
  set 
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_reason = p_reason,
    refund_amount = v_actual_refund,
    refunded_at = case when v_actual_refund > 0 then now() else null end,
    invoice_id = null, -- Clear invoice reference
    updated_at = now()
  where id = p_order_id;
  
  -- Build result
  v_result := jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'order_number', v_order.order_number,
    'status', 'cancelled',
    'refund_amount', v_actual_refund,
    'invoice_deleted', v_invoice is not null,
    'invoice_number', coalesce(v_invoice.invoice_number, null),
    'message', format('Order %s cancelled. Refund: $%s', v_order.order_number, v_actual_refund)
  );
  
  return v_result;
end;
$$;

--------------------------------------------------------------------------------
-- FUNCTION: confirm_online_order_payment
-- PURPOSE: Manually confirm wire transfer or other pending payments
-- CALLED BY: ERP admin panel when customer confirms bank transfer
-- This function:
-- 1. Updates invoice status to 'confirmed' (triggers inventory deduction)
-- 2. Creates payment record (triggers journal entry + updates invoice to paid)
-- 3. Updates order payment_status to 'paid'
--------------------------------------------------------------------------------
create or replace function public.confirm_online_order_payment(
  p_order_id uuid,
  p_payment_reference text default null,
  p_payment_date timestamp with time zone default now()
)
returns uuid -- Returns payment_id
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_invoice record;
  v_payment_method_id uuid;
  v_payment_id uuid;
begin
  -- Get order with tenant context
  select * into v_order
  from online_orders
  where id = p_order_id
    and tenant_id = public.user_tenant_id();
  
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id;
  end if;
  
  -- Check order has invoice
  if v_order.sales_invoice_id is null then
    raise exception 'Order has no invoice. Call process_online_order first.';
  end if;
  
  -- Get invoice
  select * into v_invoice
  from sales_invoices
  where id = v_order.sales_invoice_id;
  
  if not found then
    raise exception 'Invoice not found: %', v_order.sales_invoice_id;
  end if;
  
  -- Check invoice isn't already paid
  if v_invoice.status = 'paid' then
    raise notice 'Invoice already paid';
    return null;
  end if;
  
  -- Get payment method
  select id into v_payment_method_id
  from payment_methods
  where tenant_id = v_order.tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'transfer'))
    and is_active = true
  limit 1;
  
  -- Fallback to any transfer method
  if v_payment_method_id is null then
    select id into v_payment_method_id
    from payment_methods
    where tenant_id = v_order.tenant_id
      and lower(code) in ('transfer', 'transferencia', 'bank_transfer')
      and is_active = true
    limit 1;
  end if;
  
  if v_payment_method_id is null then
    raise exception 'No payment method found for tenant %', v_order.tenant_id;
  end if;
  
  -- Update invoice to confirmed (triggers inventory deduction if not already done)
  update sales_invoices
  set 
    status = 'confirmed',
    updated_at = now()
  where id = v_invoice.id
    and status != 'paid'; -- Only update if not already paid
  
  -- Create payment record (triggers journal entry + updates invoice to paid)
  insert into sales_payments (
    tenant_id,
    invoice_id,
    invoice_reference,
    payment_method_id,
    amount,
    date,
    reference,
    notes
  ) values (
    v_order.tenant_id,
    v_invoice.id,
    v_invoice.invoice_number,
    v_payment_method_id,
    v_order.total,
    p_payment_date,
    p_payment_reference,
    'Confirmación manual - Transferencia bancaria - Pedido #' || v_order.order_number
  )
  returning id into v_payment_id;
  
  -- Update order payment status
  update online_orders
  set 
    payment_status = 'paid',
    paid_at = p_payment_date,
    payment_reference = coalesce(p_payment_reference, payment_reference),
    updated_at = now()
  where id = p_order_id;
  
  raise notice 'Payment confirmed for order % (invoice %)', 
    v_order.order_number, v_invoice.invoice_number;
  
  return v_payment_id;
end;
$$;

grant execute on function public.confirm_online_order_payment(uuid, text, timestamp with time zone) to authenticated;

--------------------------------------------------------------------------------
-- TRIGGER: Auto-create invoice for non-MercadoPago orders on creation
-- MercadoPago orders wait for webhook confirmation before invoice creation
--------------------------------------------------------------------------------
create or replace function public.handle_new_online_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only create invoice immediately for non-MercadoPago orders
  -- MercadoPago orders wait for webhook confirmation
  if lower(coalesce(NEW.payment_method, '')) not in ('mercadopago', 'mercado_pago') then
    -- Create invoice with 'sent' status (pending payment)
    perform public.process_online_order(NEW.id);
    raise notice 'Auto-created invoice for non-MercadoPago order %', NEW.order_number;
  else
    raise notice 'MercadoPago order % - invoice will be created on payment confirmation', NEW.order_number;
  end if;
  
  return NEW;
end;
$$;

-- Create trigger (replace if exists)
drop trigger if exists trg_online_order_auto_invoice on online_orders;
create trigger trg_online_order_auto_invoice
  after insert on online_orders
  for each row
  execute function public.handle_new_online_order();

--------------------------------------------------------------------------------
-- FUNCTION: update_online_order_status
-- PURPOSE: Update order status with proper business logic
-- CALLED BY: ERP admin panel for order management
--------------------------------------------------------------------------------
create or replace function public.update_online_order_status(
  p_order_id uuid,
  p_new_status text,
  p_tracking_number text default null,
  p_tracking_url text default null,
  p_carrier text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_order record;
  v_invoice_id uuid;
begin
  -- Get current order
  select * into v_order
  from online_orders
  where id = p_order_id
    and tenant_id = public.user_tenant_id();
    
  if v_order is null then
    raise exception 'Order not found or access denied: %', p_order_id;
  end if;
  
  -- Validate status transition
  if v_order.status = 'cancelled' then
    raise exception 'Cannot change status of cancelled order';
  end if;
  
  -- Handle status-specific logic
  case p_new_status
    -- Order confirmed (usually after payment)
    when 'confirmed' then
      -- If no invoice yet, create one
      if v_order.sales_invoice_id is null and v_order.payment_status = 'paid' then
        v_invoice_id := public.process_online_order(p_order_id);
      end if;
      
    -- Processing (preparing order)
    when 'processing' then
      if v_order.sales_invoice_id is null then
        raise exception 'Cannot process order without invoice. Confirm order first.';
      end if;
      
    -- Ready for pickup (in-store pickup orders)
    when 'ready_for_pickup' then
      if v_order.delivery_type != 'pickup' then
        raise exception 'Can only mark pickup orders as ready_for_pickup';
      end if;
      update online_orders
      set ready_for_pickup_at = now()
      where id = p_order_id;
      
    -- Shipped
    when 'shipped' then
      if v_order.delivery_type != 'shipping' then
        raise exception 'Can only ship delivery orders, not pickup orders';
      end if;
      update online_orders
      set 
        shipped_at = now(),
        tracking_number = coalesce(p_tracking_number, tracking_number),
        tracking_url = coalesce(p_tracking_url, tracking_url),
        shipping_carrier = coalesce(p_carrier, shipping_carrier)
      where id = p_order_id;
      
    -- Delivered
    when 'delivered' then
      update online_orders
      set delivered_at = now()
      where id = p_order_id;
      
    -- Cancelled
    when 'cancelled' then
      -- Use dedicated cancel function
      return public.cancel_online_order(p_order_id, coalesce(p_notes, 'Cancelado'));
      
    else
      raise exception 'Invalid status: %', p_new_status;
  end case;
  
  -- Update the status
  update online_orders
  set 
    status = p_new_status,
    notes = coalesce(p_notes, notes),
    updated_at = now()
  where id = p_order_id;
  
  return jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'old_status', v_order.status,
    'new_status', p_new_status,
    'invoice_id', coalesce(v_invoice_id, v_order.sales_invoice_id)
  );
end;
$$;

--------------------------------------------------------------------------------
-- TRIGGER: auto_process_paid_online_order
-- PURPOSE: Automatically process order when payment is received
-- FLOW: Customer pays → webhook updates payment_status → trigger creates invoice
--       OR if invoice exists → updates invoice to 'paid' status
--------------------------------------------------------------------------------
create or replace function public.handle_online_order_payment()
returns trigger
language plpgsql
security definer
as $$
declare
  v_invoice_id uuid;
begin
  -- Only process when payment_status changes to 'paid'
  if NEW.payment_status = 'paid' and 
     (OLD.payment_status is null or OLD.payment_status != 'paid') and
     NEW.status != 'cancelled' then
     
    -- Call process_online_order regardless of whether invoice exists
    -- If invoice exists, it will update it to 'paid' status
    -- If invoice doesn't exist, it will create one
    v_invoice_id := public.process_online_order(NEW.id);
    
    raise notice 'Auto-processed order % -> Invoice %', NEW.order_number, v_invoice_id;
  end if;
  
  return NEW;
end;
$$;

-- Create the trigger
do $$
begin
  -- Drop existing trigger if any
  drop trigger if exists trg_auto_process_paid_online_order on online_orders;
  
  -- Create new trigger (AFTER to allow the row to be committed first)
  create trigger trg_auto_process_paid_online_order
    after update of payment_status on online_orders
    for each row
    execute function public.handle_online_order_payment();
    
  raise notice 'Created trigger trg_auto_process_paid_online_order';
end $$;

-- Grant execute permissions
grant execute on function public.cancel_online_order(uuid, text, numeric) to authenticated;
grant execute on function public.update_online_order_status(uuid, text, text, text, text, text) to authenticated;

-- Function to generate order number
create or replace function public.generate_online_order_number()
returns text
language plpgsql
as $$
declare
  v_year text;
  v_count integer;
  v_number text;
begin
  v_year := to_char(now(), 'YY');
  
  select count(*) + 1 into v_count
  from online_orders
  where extract(year from created_at) = extract(year from now());
  
  v_number := 'WEB-' || v_year || '-' || lpad(v_count::text, 5, '0');
  
  return v_number;
end;
$$;

-- Trigger to auto-generate order number
create or replace function public.auto_generate_order_number()
returns trigger as $$
begin
  if NEW.order_number is null or NEW.order_number = '' then
    NEW.order_number := public.generate_online_order_number();
  end if;
  return NEW;
end;
$$ language plpgsql;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_auto_generate_order_number'
  ) then
    create trigger trg_auto_generate_order_number
      before insert on online_orders
      for each row execute procedure auto_generate_order_number();
  end if;
end $$;

-- Note: Default website settings are now seeded per-tenant via TenantSignupService
-- This legacy INSERT is skipped for multi-tenant databases
-- Settings will be created when a new tenant signs up
do $$
begin
  -- Only insert if website_settings table doesn't have tenant_id unique constraint
  if not exists (
    select 1 from information_schema.table_constraints 
    where table_name = 'website_settings' 
      and constraint_type = 'UNIQUE'
      and constraint_name like '%tenant%'
  ) then
    -- Old single-tenant structure: insert default settings
    insert into website_settings (key, value, description) values
      ('store_name', 'Vinabike', 'Nombre de la tienda'),
      ('store_tagline', 'Bicicletas y Accesorios en Chile', 'Eslogan de la tienda'),
      ('store_email', 'contacto@vinabike.cl', 'Email de contacto'),
      ('store_phone', '+56 9 XXXX XXXX', 'Teléfono de contacto'),
      ('store_address', 'Santiago, Chile', 'Dirección de la tienda'),
      ('shipping_cost', '5000', 'Costo de envío por defecto (CLP)'),
      ('free_shipping_threshold', '50000', 'Monto mínimo para envío gratis (CLP)'),
      ('google_analytics_id', '', 'Google Analytics tracking ID'),
      ('facebook_pixel_id', '', 'Facebook Pixel ID'),
      ('meta_description', 'Tienda online de bicicletas y accesorios en Chile', 'Meta descripción para SEO'),
      ('meta_keywords', 'bicicletas, bikes, chile, ciclismo, accesorios', 'Palabras clave para SEO'),
      ('mercadopago_public_key', '', 'MercadoPago Public Key (TEST-xxxx for sandbox)'),
      ('mercadopago_access_token', '', 'MercadoPago Access Token (TEST-xxxx for sandbox)'),
      ('mercadopago_test_mode', 'true', 'MercadoPago modo prueba (true/false)')
    on conflict (key) do nothing;
  else
    raise notice 'Skipping default website_settings INSERT - multi-tenant structure detected. Settings will be seeded per-tenant.';
  end if;
end $$;

-- Seed default homepage content
insert into website_content (id, title, content) values
  ('homepage_hero', 'Título Principal', '<h1>Bienvenido a Vinabike</h1><p>Las mejores bicicletas de Chile</p>'),
  ('homepage_promo', 'Promoción Destacada', '<p>¡Aprovecha nuestras ofertas especiales!</p>'),
  ('about_us', 'Sobre Nosotros', '<p>Somos una empresa dedicada a ofrecer las mejores bicicletas y accesorios en Chile.</p>'),
  ('terms_conditions', 'Términos y Condiciones', '<p>Términos y condiciones de uso del sitio web.</p>'),
  ('privacy_policy', 'Política de Privacidad', '<p>Política de privacidad y manejo de datos.</p>'),
  ('shipping_info', 'Información de Envío', '<p>Enviamos a todo Chile. Costo de envío: $5.000. Envío gratis en compras sobre $50.000.</p>')
on conflict (id) do nothing;

--------------------------------------------------------------------------------
-- MULTI-TENANT MIGRATION: Add tenant_id to all tables
--------------------------------------------------------------------------------
do $$
begin
  raise notice 'Starting multi-tenant migration...';

  -- Products
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'tenant_id') then
    alter table products add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to products';
  end if;

  -- Categories
  if not exists (select 1 from information_schema.columns where table_name = 'categories' and column_name = 'tenant_id') then
    alter table categories add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to categories';
  end if;

  -- Product Categories
  if not exists (select 1 from information_schema.columns where table_name = 'product_categories' and column_name = 'tenant_id') then
    alter table product_categories add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to product_categories';
  end if;

  -- Product Brands
  if not exists (select 1 from information_schema.columns where table_name = 'product_brands' and column_name = 'tenant_id') then
    alter table product_brands add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to product_brands';
  end if;

  -- Stock Movements
  if not exists (select 1 from information_schema.columns where table_name = 'stock_movements' and column_name = 'tenant_id') then
    alter table stock_movements add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to stock_movements';
  end if;

  -- Warehouses (if exists)
  if exists (select 1 from information_schema.tables where table_name = 'warehouses') then
    if not exists (select 1 from information_schema.columns where table_name = 'warehouses' and column_name = 'tenant_id') then
      alter table warehouses add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to warehouses';
    end if;
  end if;

  -- Sales Invoices
  if not exists (select 1 from information_schema.columns where table_name = 'sales_invoices' and column_name = 'tenant_id') then
    alter table sales_invoices add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to sales_invoices';
  end if;

  -- Sales Invoice Items (if table exists)
  if exists (select 1 from information_schema.tables where table_name = 'sales_invoice_items') then
    if not exists (select 1 from information_schema.columns where table_name = 'sales_invoice_items' and column_name = 'tenant_id') then
      alter table sales_invoice_items add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to sales_invoice_items';
    end if;
  else
    raise notice '⚠ Table sales_invoice_items does not exist, skipping';
  end if;

  -- Sales Payments
  if not exists (select 1 from information_schema.columns where table_name = 'sales_payments' and column_name = 'tenant_id') then
    alter table sales_payments add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to sales_payments';
  end if;

  -- Suppliers
  if not exists (select 1 from information_schema.columns where table_name = 'suppliers' and column_name = 'tenant_id') then
    alter table suppliers add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to suppliers';
  end if;

  -- Purchase Invoices
  if not exists (select 1 from information_schema.columns where table_name = 'purchase_invoices' and column_name = 'tenant_id') then
    alter table purchase_invoices add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to purchase_invoices';
  end if;

  -- Purchase Invoice Items (if table exists)
  if exists (select 1 from information_schema.tables where table_name = 'purchase_invoice_items') then
    if not exists (select 1 from information_schema.columns where table_name = 'purchase_invoice_items' and column_name = 'tenant_id') then
      alter table purchase_invoice_items add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to purchase_invoice_items';
    end if;
  else
    raise notice '⚠ Table purchase_invoice_items does not exist, skipping';
  end if;

  -- Purchase Payments
  if not exists (select 1 from information_schema.columns where table_name = 'purchase_payments' and column_name = 'tenant_id') then
    alter table purchase_payments add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to purchase_payments';
  end if;

  -- Customer Bikes (if exists)
  if exists (select 1 from information_schema.tables where table_name = 'customer_bikes') then
    if not exists (select 1 from information_schema.columns where table_name = 'customer_bikes' and column_name = 'tenant_id') then
      alter table customer_bikes add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to customer_bikes';
    end if;
  else
    raise notice '⚠ Table customer_bikes does not exist, skipping';
  end if;

  -- Accounts (Chart of Accounts)
  if not exists (select 1 from information_schema.columns where table_name = 'accounts' and column_name = 'tenant_id') then
    alter table accounts add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to accounts';
  end if;

  -- Journal Entries
  if not exists (select 1 from information_schema.columns where table_name = 'journal_entries' and column_name = 'tenant_id') then
    alter table journal_entries add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to journal_entries';
  end if;

  -- Journal Entry Lines (if table exists)
  if exists (select 1 from information_schema.tables where table_name = 'journal_entry_lines') then
    if not exists (select 1 from information_schema.columns where table_name = 'journal_entry_lines' and column_name = 'tenant_id') then
      alter table journal_entry_lines add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to journal_entry_lines';
    end if;
  else
    raise notice '⚠ Table journal_entry_lines does not exist, skipping';
  end if;

  -- Fiscal Periods (if table exists)
  if exists (select 1 from information_schema.tables where table_name = 'fiscal_periods') then
    if not exists (select 1 from information_schema.columns where table_name = 'fiscal_periods' and column_name = 'tenant_id') then
      alter table fiscal_periods add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to fiscal_periods';
    end if;
  else
    raise notice '⚠ Table fiscal_periods does not exist, skipping';
  end if;

  -- Employees
  if not exists (select 1 from information_schema.columns where table_name = 'employees' and column_name = 'tenant_id') then
    alter table employees add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to employees';
  end if;

  -- Attendances
  if not exists (select 1 from information_schema.columns where table_name = 'attendances' and column_name = 'tenant_id') then
    alter table attendances add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to attendances';
  end if;

  -- Contracts (if exists)
  if exists (select 1 from information_schema.tables where table_name = 'contracts') then
    if not exists (select 1 from information_schema.columns where table_name = 'contracts' and column_name = 'tenant_id') then
      alter table contracts add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to contracts';
    end if;
  else
    raise notice '⚠ Table contracts does not exist, skipping';
  end if;

  -- Payroll (if exists)
  if exists (select 1 from information_schema.tables where table_name = 'payroll') then
    if not exists (select 1 from information_schema.columns where table_name = 'payroll' and column_name = 'tenant_id') then
      alter table payroll add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to payroll';
    end if;
  else
    raise notice '⚠ Table payroll does not exist, skipping';
  end if;

  -- Website Settings
  if not exists (select 1 from information_schema.columns where table_name = 'website_settings' and column_name = 'tenant_id') then
    alter table website_settings add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to website_settings';
  end if;

  -- Website Blocks
  if not exists (select 1 from information_schema.columns where table_name = 'website_blocks' and column_name = 'tenant_id') then
    alter table website_blocks add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to website_blocks';
  end if;

  -- Website Content (if exists)
  if exists (select 1 from information_schema.tables where table_name = 'website_content') then
    if not exists (select 1 from information_schema.columns where table_name = 'website_content' and column_name = 'tenant_id') then
      alter table website_content add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to website_content';
    end if;
  else
    raise notice '⚠ Table website_content does not exist, skipping';
  end if;

  -- Online Orders
  if not exists (select 1 from information_schema.columns where table_name = 'online_orders' and column_name = 'tenant_id') then
    alter table online_orders add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to online_orders';
  end if;

  -- Work Orders (if exists)
  if exists (select 1 from information_schema.tables where table_name = 'work_orders') then
    if not exists (select 1 from information_schema.columns where table_name = 'work_orders' and column_name = 'tenant_id') then
      alter table work_orders add column tenant_id uuid references tenants(id) on delete cascade;
      raise notice '✓ Added tenant_id to work_orders';
    end if;
  else
    raise notice '⚠ Table work_orders does not exist, skipping';
  end if;

  -- Payment Methods
  if not exists (select 1 from information_schema.columns where table_name = 'payment_methods' and column_name = 'tenant_id') then
    alter table payment_methods add column tenant_id uuid references tenants(id) on delete cascade;
    raise notice '✓ Added tenant_id to payment_methods';
  end if;

  raise notice 'Multi-tenant migration complete!';
end $$;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Function to extract tenant_id from JWT (in public schema, not auth)
-- Function to get all users in a tenant (for user management UI)
create or replace function public.get_tenant_users(p_tenant_id uuid)
returns table (
  id uuid,
  email text,
  role text,
  permissions jsonb,
  is_active boolean,
  last_sign_in timestamp with time zone,
  created_at timestamp with time zone,
  employee_id uuid,
  employee_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select 
    u.id,
    u.email::text,
    coalesce(up.role, 'viewer')::text as role,
    coalesce(up.permissions, '{}'::jsonb) as permissions,
    coalesce(up.is_active, true) as is_active,
    u.last_sign_in_at,
    u.created_at,
    e.id as employee_id,
    (e.first_name || ' ' || e.last_name) as employee_name
  from auth.users u
  inner join user_profiles up on up.user_id = u.id
  left join employees e on e.user_id = u.id and e.tenant_id = p_tenant_id
  where up.tenant_id = p_tenant_id
  order by u.created_at desc;
end;
$$;

-- Function to delete a user (must be called by tenant manager)
-- This is a security definer function that can delete auth.users
create or replace function delete_tenant_user(p_user_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_tenant_id uuid;
  v_caller_role text;
  v_caller_tenant_id uuid;
  v_caller_user_id uuid;
begin
  -- Get caller's user ID from the session
  v_caller_user_id := auth.uid();
  
  if v_caller_user_id is null then
    raise exception 'Not authenticated';
  end if;
  
  -- Get caller's tenant_id and role from auth.users metadata
  select 
    (raw_app_meta_data->>'tenant_id')::uuid,
    (raw_app_meta_data->>'role')::text
  into v_caller_tenant_id, v_caller_role
  from auth.users
  where id = v_caller_user_id;
  
  -- Only managers can delete users
  if v_caller_role != 'manager' then
    raise exception 'Only managers can delete users. Your role: %', v_caller_role;
  end if;
  
  -- Get the target user's tenant_id
  select (raw_app_meta_data->>'tenant_id')::uuid into v_tenant_id
  from auth.users
  where id = p_user_id;
  
  -- Verify same tenant
  if v_tenant_id != v_caller_tenant_id then
    raise exception 'Cannot delete user from different tenant';
  end if;
  
  -- Unlink from employee
  update employees
  set user_id = null
  where user_id = p_user_id;
  
  -- Delete the auth user
  delete from auth.users where id = p_user_id;
  
  raise notice 'User % deleted successfully', p_user_id;
end;
$$;

--------------------------------------------------------------------------------
-- HELPER FUNCTION: Get current user's tenant_id from user_profiles
--------------------------------------------------------------------------------
create or replace function public.user_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  -- Bypass RLS by using security definer with explicit query
  select tenant_id into v_tenant_id
  from user_profiles 
  where user_id = auth.uid() 
  limit 1;
  
  return v_tenant_id;
end;
$$;

-- Grant execute to authenticated users
grant execute on function public.user_tenant_id() to authenticated;

--------------------------------------------------------------------------------
-- RLS POLICIES: User Profiles
--------------------------------------------------------------------------------
alter table user_profiles enable row level security;

-- Drop existing policies first to allow clean redeployment
drop policy if exists "Users can view their own profiles" on user_profiles;
drop policy if exists "Admins can manage profiles in their tenant" on user_profiles;
drop policy if exists "Users can create their own profile during signup" on user_profiles;

-- Users can view their own profiles
create policy "Users can view their own profiles" on user_profiles
  for select
  using (auth.uid() = user_id);

-- Users can create their own profile during signup (for tenant creation)
create policy "Users can create their own profile during signup" on user_profiles
  for insert
  with check (auth.uid() = user_id);

-- Admins can manage all profiles in their tenant
create policy "Admins can manage profiles in their tenant" on user_profiles
  for all
  using (tenant_id = user_tenant_id());

--------------------------------------------------------------------------------
-- ROW LEVEL SECURITY POLICIES: Tenant Isolation
--------------------------------------------------------------------------------
do $$
begin
  raise notice 'Applying Row Level Security policies...';

  -- Enable RLS on all tables (only if they exist)
  -- ⚠️ TENANTS TABLE: RLS DISABLED - causes circular dependency issues with user_tenant_id()
  if exists (select 1 from information_schema.tables where table_name = 'tenants') then
    alter table tenants disable row level security;
  end if;
  
  if exists (select 1 from information_schema.tables where table_name = 'user_activity_log') then
    alter table user_activity_log enable row level security;
  end if;
  
  alter table customers enable row level security;
  alter table products enable row level security;
  alter table categories enable row level security;
  alter table product_categories enable row level security;
  alter table product_brands enable row level security;
  alter table stock_movements enable row level security;
  alter table sales_invoices enable row level security;
  
  if exists (select 1 from information_schema.tables where table_name = 'sales_invoice_items') then
    alter table sales_invoice_items enable row level security;
  end if;
  
  alter table sales_payments enable row level security;
  alter table suppliers enable row level security;
  alter table purchase_invoices enable row level security;
  
  if exists (select 1 from information_schema.tables where table_name = 'purchase_invoice_items') then
    alter table purchase_invoice_items enable row level security;
  end if;
  
  alter table purchase_payments enable row level security;
  
  if exists (select 1 from information_schema.tables where table_name = 'customer_bikes') then
    alter table customer_bikes enable row level security;
  end if;
  
  alter table accounts enable row level security;
  alter table journal_entries enable row level security;
  
  if exists (select 1 from information_schema.tables where table_name = 'journal_entry_lines') then
    alter table journal_entry_lines enable row level security;
  end if;
  
  if exists (select 1 from information_schema.tables where table_name = 'fiscal_periods') then
    alter table fiscal_periods enable row level security;
  end if;
  
  alter table employees enable row level security;
  alter table attendances enable row level security;
  alter table website_settings enable row level security;
  alter table website_blocks enable row level security;
  alter table online_orders enable row level security;
  alter table payment_methods enable row level security;

  raise notice '✓ Enabled RLS on all tables';
end $$;

-- Drop all existing policies before recreating (idempotent deployment)
do $$ 
begin
  drop policy if exists "tenant_select_own" on tenants;
  drop policy if exists "tenant_update_own" on tenants;
  drop policy if exists "user_activity_log_select" on user_activity_log;
  drop policy if exists "user_activity_log_insert" on user_activity_log;
  drop policy if exists "customers_select" on customers;
  drop policy if exists "customers_insert" on customers;
  drop policy if exists "customers_update" on customers;
  drop policy if exists "customers_delete" on customers;
  drop policy if exists "products_select" on products;
  drop policy if exists "products_insert" on products;
  drop policy if exists "products_update" on products;
  drop policy if exists "products_delete" on products;
  drop policy if exists "categories_select" on categories;
  drop policy if exists "categories_insert" on categories;
  drop policy if exists "categories_update" on categories;
  drop policy if exists "categories_delete" on categories;
  drop policy if exists "product_categories_select" on product_categories;
  drop policy if exists "product_categories_insert" on product_categories;
  drop policy if exists "product_categories_update" on product_categories;
  drop policy if exists "product_categories_delete" on product_categories;
  drop policy if exists "product_brands_select" on product_brands;
  drop policy if exists "product_brands_insert" on product_brands;
  drop policy if exists "product_brands_update" on product_brands;
  drop policy if exists "product_brands_delete" on product_brands;
  drop policy if exists "stock_movements_select" on stock_movements;
  drop policy if exists "stock_movements_insert" on stock_movements;
  drop policy if exists "sales_invoices_select" on sales_invoices;
  drop policy if exists "sales_invoices_insert" on sales_invoices;
  drop policy if exists "sales_invoices_update" on sales_invoices;
  drop policy if exists "sales_invoices_delete" on sales_invoices;
  drop policy if exists "sales_payments_select" on sales_payments;
  drop policy if exists "sales_payments_insert" on sales_payments;
  drop policy if exists "sales_payments_delete" on sales_payments;
  drop policy if exists "suppliers_select" on suppliers;
  drop policy if exists "suppliers_insert" on suppliers;
  drop policy if exists "suppliers_update" on suppliers;
  drop policy if exists "suppliers_delete" on suppliers;
  drop policy if exists "purchase_invoices_select" on purchase_invoices;
  drop policy if exists "purchase_invoices_insert" on purchase_invoices;
  drop policy if exists "purchase_invoices_update" on purchase_invoices;
  drop policy if exists "purchase_invoices_delete" on purchase_invoices;
  drop policy if exists "purchase_payments_select" on purchase_payments;
  drop policy if exists "purchase_payments_insert" on purchase_payments;
  drop policy if exists "purchase_payments_delete" on purchase_payments;
  drop policy if exists "accounts_select" on accounts;
  drop policy if exists "accounts_insert" on accounts;
  drop policy if exists "accounts_update" on accounts;
  drop policy if exists "accounts_delete" on accounts;
  drop policy if exists "journal_entries_select" on journal_entries;
  drop policy if exists "journal_entries_insert" on journal_entries;
  drop policy if exists "employees_select" on employees;
  drop policy if exists "employees_insert" on employees;
  drop policy if exists "employees_update" on employees;
  drop policy if exists "employees_delete" on employees;
  drop policy if exists "attendances_select" on attendances;
  drop policy if exists "attendances_insert" on attendances;
  drop policy if exists "attendances_update" on attendances;
  drop policy if exists "website_settings_select" on website_settings;
  drop policy if exists "website_settings_insert" on website_settings;
  drop policy if exists "website_settings_update" on website_settings;
  drop policy if exists "website_blocks_select" on website_blocks;
  drop policy if exists "website_blocks_insert" on website_blocks;
  drop policy if exists "website_blocks_update" on website_blocks;
  drop policy if exists "website_blocks_delete" on website_blocks;
  drop policy if exists "online_orders_select" on online_orders;
  drop policy if exists "online_orders_insert" on online_orders;
  drop policy if exists "online_orders_update" on online_orders;
  drop policy if exists "payment_methods_select" on payment_methods;
  drop policy if exists "payment_methods_insert" on payment_methods;
  drop policy if exists "payment_methods_update" on payment_methods;
  raise notice '✓ Dropped all existing RLS policies (idempotent deployment)';
exception
  when undefined_table then 
    raise notice '⚠ Some tables do not exist yet, skipping policy drops';
  when undefined_object then 
    raise notice '⚠ Some policies do not exist yet, skipping';
  when undefined_column then
    raise notice '⚠ Column tenant_id does not exist in some tables yet, skipping policy drops';
end $$;

-- Tenants table: Users can only see their own tenant
-- Special policy: Allow INSERT for authenticated users (for signup)
-- Special policy: Allow anonymous SELECT for public store tenant detection (subdomain lookup)
do $$ begin
  create policy "tenant_select_own" on tenants for select using (
    id = public.user_tenant_id()
  );
  create policy "tenant_select_anon" on tenants for select to anon using (
    is_active = true
  );
  create policy "tenant_insert_authenticated" on tenants for insert with check (auth.uid() IS NOT NULL);
  create policy "tenant_update_own" on tenants for update using (
    id = public.user_tenant_id()
  );
  raise notice '✓ Created RLS policies for tenants';
exception
  when undefined_table then raise notice '⚠ Table tenants does not exist yet';
  when undefined_column then raise notice '⚠ Column missing in tenants table';
  when duplicate_object then raise notice '⚠ Policies already exist for tenants';
end $$;

-- User Activity Log: Tenant isolation
do $$ begin
  create policy "user_activity_log_select" on user_activity_log for select using (tenant_id = public.user_tenant_id());
  create policy "user_activity_log_insert" on user_activity_log for insert with check (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for user_activity_log';
exception
  when undefined_table then raise notice '⚠ Table user_activity_log does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in user_activity_log';
  when duplicate_object then raise notice '⚠ Policies already exist for user_activity_log';
end $$;

-- Customers: Tenant isolation
do $$ begin
  create policy "customers_select" on customers for select using (tenant_id = public.user_tenant_id());
  create policy "customers_insert" on customers for insert with check (tenant_id = public.user_tenant_id());
  create policy "customers_update" on customers for update using (tenant_id = public.user_tenant_id());
  create policy "customers_delete" on customers for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for customers';
exception
  when undefined_table then raise notice '⚠ Table customers does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in customers';
  when duplicate_object then raise notice '⚠ Policies already exist for customers';
end $$;

-- Products: Tenant isolation
do $$ begin
  create policy "products_select" on products for select using (tenant_id = public.user_tenant_id());
  create policy "products_insert" on products for insert with check (tenant_id = public.user_tenant_id());
  create policy "products_update" on products for update using (tenant_id = public.user_tenant_id());
  create policy "products_delete" on products for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for products';
exception
  when undefined_table then raise notice '⚠ Table products does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in products';
  when duplicate_object then raise notice '⚠ Policies already exist for products';
end $$;

-- Categories: Tenant isolation
do $$ begin
  create policy "categories_select" on categories for select using (tenant_id = public.user_tenant_id());
  create policy "categories_insert" on categories for insert with check (tenant_id = public.user_tenant_id());
  create policy "categories_update" on categories for update using (tenant_id = public.user_tenant_id());
  create policy "categories_delete" on categories for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for categories';
exception
  when undefined_table then raise notice '⚠ Table categories does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in categories';
  when duplicate_object then raise notice '⚠ Policies already exist for categories';
end $$;

-- Product Categories: Tenant isolation
do $$ begin
  create policy "product_categories_select" on product_categories for select to authenticated using (tenant_id = public.user_tenant_id());
  create policy "product_categories_insert" on product_categories for insert to authenticated with check (tenant_id = public.user_tenant_id());
  create policy "product_categories_update" on product_categories for update to authenticated using (tenant_id = public.user_tenant_id());
  create policy "product_categories_delete" on product_categories for delete to authenticated using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for product_categories';
exception
  when undefined_table then raise notice '⚠ Table product_categories does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in product_categories';
  when duplicate_object then raise notice '⚠ Policies already exist for product_categories';
end $$;

-- Product Brands: Tenant isolation
do $$ begin
  create policy "product_brands_select" on product_brands for select using (tenant_id = public.user_tenant_id());
  create policy "product_brands_insert" on product_brands for insert with check (tenant_id = public.user_tenant_id());
  create policy "product_brands_update" on product_brands for update using (tenant_id = public.user_tenant_id());
  create policy "product_brands_delete" on product_brands for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for product_brands';
exception
  when undefined_table then raise notice '⚠ Table product_brands does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in product_brands';
  when duplicate_object then raise notice '⚠ Policies already exist for product_brands';
end $$;

-- Stock Movements: Tenant isolation
do $$ begin
  create policy "stock_movements_select" on stock_movements for select using (tenant_id = public.user_tenant_id());
  create policy "stock_movements_insert" on stock_movements for insert with check (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for stock_movements';
exception
  when undefined_table then raise notice '⚠ Table stock_movements does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in stock_movements';
  when duplicate_object then raise notice '⚠ Policies already exist for stock_movements';
end $$;

-- Sales Invoices: Tenant isolation
do $$ begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'sales_invoices') then
    alter table sales_invoices enable row level security;
    
    drop policy if exists "sales_invoices_select" on sales_invoices;
    drop policy if exists "sales_invoices_insert" on sales_invoices;
    drop policy if exists "sales_invoices_update" on sales_invoices;
    drop policy if exists "sales_invoices_delete" on sales_invoices;
    
    create policy "sales_invoices_select" on sales_invoices 
      for select 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    create policy "sales_invoices_insert" on sales_invoices 
      for insert 
      to authenticated
      with check (tenant_id = public.user_tenant_id());
      
    create policy "sales_invoices_update" on sales_invoices 
      for update 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    create policy "sales_invoices_delete" on sales_invoices 
      for delete 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    raise notice '✓ Created RLS policies for sales_invoices';
  else
    raise notice '⚠ Table sales_invoices does not exist yet';
  end if;
exception
  when undefined_column then raise notice '⚠ Column tenant_id missing in sales_invoices';
end $$;

-- Sales Invoice Items: Tenant isolation (if table exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'sales_invoice_items') then
    execute 'create policy "sales_invoice_items_select" on sales_invoice_items for select using (tenant_id = public.user_tenant_id())';
    execute 'create policy "sales_invoice_items_insert" on sales_invoice_items for insert with check (tenant_id = public.user_tenant_id())';
    execute 'create policy "sales_invoice_items_update" on sales_invoice_items for update using (tenant_id = public.user_tenant_id())';
    execute 'create policy "sales_invoice_items_delete" on sales_invoice_items for delete using (tenant_id = public.user_tenant_id())';
    raise notice '✓ Created RLS policies for sales_invoice_items';
  else
    raise notice '⚠ Table sales_invoice_items does not exist, skipping RLS policies';
  end if;
end $$;

-- Sales Payments: Tenant isolation
do $$ begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'sales_payments') then
    alter table sales_payments enable row level security;
    
    drop policy if exists "sales_payments_select" on sales_payments;
    drop policy if exists "sales_payments_insert" on sales_payments;
    drop policy if exists "sales_payments_update" on sales_payments;
    drop policy if exists "sales_payments_delete" on sales_payments;
    
    create policy "sales_payments_select" on sales_payments 
      for select 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    create policy "sales_payments_insert" on sales_payments 
      for insert 
      to authenticated
      with check (tenant_id = public.user_tenant_id());
      
    create policy "sales_payments_update" on sales_payments 
      for update 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    create policy "sales_payments_delete" on sales_payments 
      for delete 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    raise notice '✓ Created RLS policies for sales_payments';
  else
    raise notice '⚠ Table sales_payments does not exist yet';
  end if;
exception
  when undefined_column then raise notice '⚠ Column tenant_id missing in sales_payments';
end $$;

-- Suppliers: Tenant isolation
do $$ begin
  create policy "suppliers_select" on suppliers for select using (tenant_id = public.user_tenant_id());
  create policy "suppliers_insert" on suppliers for insert with check (tenant_id = public.user_tenant_id());
  create policy "suppliers_update" on suppliers for update using (tenant_id = public.user_tenant_id());
  create policy "suppliers_delete" on suppliers for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for suppliers';
exception
  when undefined_table then raise notice '⚠ Table suppliers does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in suppliers';
  when duplicate_object then raise notice '⚠ Policies already exist for suppliers';
end $$;

-- Purchase Invoices: Tenant isolation
do $$ begin
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'purchase_invoices') then
    alter table purchase_invoices enable row level security;
    
    drop policy if exists "purchase_invoices_select" on purchase_invoices;
    drop policy if exists "purchase_invoices_insert" on purchase_invoices;
    drop policy if exists "purchase_invoices_update" on purchase_invoices;
    drop policy if exists "purchase_invoices_delete" on purchase_invoices;
    
    create policy "purchase_invoices_select" on purchase_invoices 
      for select 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    create policy "purchase_invoices_insert" on purchase_invoices 
      for insert 
      to authenticated
      with check (tenant_id = public.user_tenant_id());
      
    create policy "purchase_invoices_update" on purchase_invoices 
      for update 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    create policy "purchase_invoices_delete" on purchase_invoices 
      for delete 
      to authenticated
      using (tenant_id = public.user_tenant_id());
      
    raise notice '✓ Created RLS policies for purchase_invoices';
  else
    raise notice '⚠ Table purchase_invoices does not exist yet';
  end if;
exception
  when undefined_column then raise notice '⚠ Column tenant_id missing in purchase_invoices';
end $$;

-- Purchase Invoice Items: Tenant isolation (if table exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'purchase_invoice_items') then
    execute 'create policy "purchase_invoice_items_select" on purchase_invoice_items for select using (tenant_id = public.user_tenant_id())';
    execute 'create policy "purchase_invoice_items_insert" on purchase_invoice_items for insert with check (tenant_id = public.user_tenant_id())';
    execute 'create policy "purchase_invoice_items_update" on purchase_invoice_items for update using (tenant_id = public.user_tenant_id())';
    execute 'create policy "purchase_invoice_items_delete" on purchase_invoice_items for delete using (tenant_id = public.user_tenant_id())';
    raise notice '✓ Created RLS policies for purchase_invoice_items';
  else
    raise notice '⚠ Table purchase_invoice_items does not exist, skipping RLS policies';
  end if;
end $$;

-- Purchase Payments: Tenant isolation
do $$ begin
  alter table purchase_payments enable row level security;
  
  drop policy if exists "purchase_payments_select" on purchase_payments;
  drop policy if exists "purchase_payments_insert" on purchase_payments;
  drop policy if exists "purchase_payments_update" on purchase_payments;
  drop policy if exists "purchase_payments_delete" on purchase_payments;
  
  create policy "purchase_payments_select" on purchase_payments 
    for select 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  create policy "purchase_payments_insert" on purchase_payments 
    for insert 
    to authenticated
    with check (tenant_id = public.user_tenant_id());
    
  create policy "purchase_payments_update" on purchase_payments 
    for update 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  create policy "purchase_payments_delete" on purchase_payments 
    for delete 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  raise notice '✓ Created RLS policies for purchase_payments';
exception
  when undefined_table then raise notice '⚠ Table purchase_payments does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in purchase_payments';
  when duplicate_object then raise notice '⚠ Policies already exist for purchase_payments';
end $$;

-- Customer Bikes: Tenant isolation (if table exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'customer_bikes') then
    execute 'create policy "customer_bikes_select" on customer_bikes for select using (tenant_id = public.user_tenant_id())';
    execute 'create policy "customer_bikes_insert" on customer_bikes for insert with check (tenant_id = public.user_tenant_id())';
    execute 'create policy "customer_bikes_update" on customer_bikes for update using (tenant_id = public.user_tenant_id())';
    execute 'create policy "customer_bikes_delete" on customer_bikes for delete using (tenant_id = public.user_tenant_id())';
    raise notice '✓ Created RLS policies for customer_bikes';
  else
    raise notice '⚠ Table customer_bikes does not exist, skipping RLS policies';
  end if;
end $$;

-- Accounts (Chart of Accounts): Tenant isolation + Role check
do $$ begin
  create policy "accounts_select" on accounts for select using (tenant_id = public.user_tenant_id());
  create policy "accounts_insert" on accounts for insert with check (
    tenant_id = public.user_tenant_id() and
    (auth.jwt() -> 'user_metadata' ->> 'role') in ('manager', 'accountant')
  );
  create policy "accounts_update" on accounts for update using (
    tenant_id = public.user_tenant_id() and
    (auth.jwt() -> 'user_metadata' ->> 'role') in ('manager', 'accountant')
  );
  create policy "accounts_delete" on accounts for delete using (
    tenant_id = public.user_tenant_id() and
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'manager'
  );
  raise notice '✓ Created RLS policies for accounts';
exception
  when undefined_table then raise notice '⚠ Table accounts does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in accounts';
  when duplicate_object then raise notice '⚠ Policies already exist for accounts';
end $$;

-- Journal Entries: Tenant isolation + Role check
do $$ begin
  create policy "journal_entries_select" on journal_entries for select using (
    tenant_id = public.user_tenant_id() and
    (auth.jwt() -> 'user_metadata' ->> 'role') in ('admin', 'manager', 'accountant')
  );
  create policy "journal_entries_insert" on journal_entries for insert with check (
    tenant_id = public.user_tenant_id() and
    (auth.jwt() -> 'user_metadata' ->> 'role') in ('admin', 'manager', 'accountant')
  );
  raise notice '✓ Created RLS policies for journal_entries';
exception
  when undefined_table then raise notice '⚠ Table journal_entries does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in journal_entries';
  when duplicate_object then raise notice '⚠ Policies already exist for journal_entries';
end $$;

-- Journal Entry Lines: Tenant isolation + Role check (if table exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'journal_entry_lines') then
    execute 'create policy "journal_entry_lines_select" on journal_entry_lines for select using (
      tenant_id = public.user_tenant_id() and
      (auth.jwt() -> ''user_metadata'' ->> ''role'') in (''admin'', ''manager'', ''accountant'')
    )';
    execute 'create policy "journal_entry_lines_insert" on journal_entry_lines for insert with check (
      tenant_id = public.user_tenant_id() and
      (auth.jwt() -> ''user_metadata'' ->> ''role'') in (''admin'', ''manager'', ''accountant'')
    )';
  end if;
end $$;

-- Fiscal Periods: Tenant isolation (if table exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'fiscal_periods') then
    execute 'create policy "fiscal_periods_select" on fiscal_periods for select using (tenant_id = public.user_tenant_id())';
    execute 'create policy "fiscal_periods_insert" on fiscal_periods for insert with check (tenant_id = public.user_tenant_id() and (auth.jwt() -> ''user_metadata'' ->> ''role'') in (''manager'', ''accountant''))';
    raise notice '✓ Created RLS policies for fiscal_periods';
  else
    raise notice '⚠ Table fiscal_periods does not exist, skipping RLS policies';
  end if;
end $$;

-- Employees: Tenant isolation
do $$ begin
  create policy "employees_select" on employees for select using (tenant_id = public.user_tenant_id());
  create policy "employees_insert" on employees for insert with check (
    tenant_id = public.user_tenant_id()
  );
  create policy "employees_update" on employees for update using (
    tenant_id = public.user_tenant_id()
  );
  create policy "employees_delete" on employees for delete using (
    tenant_id = public.user_tenant_id()
  );
  raise notice '✓ Created RLS policies for employees';
exception
  when undefined_table then raise notice '⚠ Table employees does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in employees';
  when duplicate_object then raise notice '⚠ Policies already exist for employees';
end $$;

-- Attendances: Tenant isolation
do $$ begin
  drop policy if exists "attendances_select" on attendances;
  drop policy if exists "attendances_insert" on attendances;
  drop policy if exists "attendances_update" on attendances;
  drop policy if exists "attendances_delete" on attendances;
  
  create policy "attendances_select" on attendances 
    for select 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  create policy "attendances_insert" on attendances 
    for insert 
    to authenticated
    with check (tenant_id = public.user_tenant_id());
    
  create policy "attendances_update" on attendances 
    for update 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  create policy "attendances_delete" on attendances 
    for delete 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  raise notice '✓ Created RLS policies for attendances';
exception
  when undefined_table then raise notice '⚠ Table attendances does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in attendances';
  when duplicate_object then raise notice '⚠ Policies already exist for attendances';
end $$;

-- Website Settings: Tenant isolation
do $$ begin
  create policy "website_settings_select" on website_settings for select using (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  create policy "website_settings_insert" on website_settings for insert with check (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  create policy "website_settings_update" on website_settings for update using (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  raise notice '✓ Created RLS policies for website_settings';
exception
  when undefined_table then raise notice '⚠ Table website_settings does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in website_settings';
  when duplicate_object then raise notice '⚠ Policies already exist for website_settings';
end $$;

-- Journal Entries: Tenant isolation (accounting)
do $$ begin
  create policy "journal_entries_select" on journal_entries for select to authenticated using (tenant_id = public.user_tenant_id());
  create policy "journal_entries_insert" on journal_entries for insert to authenticated with check (tenant_id = public.user_tenant_id());
  create policy "journal_entries_update" on journal_entries for update to authenticated using (tenant_id = public.user_tenant_id());
  create policy "journal_entries_delete" on journal_entries for delete to authenticated using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for journal_entries';
exception
  when undefined_table then raise notice '⚠ Table journal_entries does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in journal_entries';
  when duplicate_object then raise notice '⚠ Policies already exist for journal_entries';
end $$;

-- Journal Lines: Tenant isolation (accounting)
do $$ begin
  create policy "journal_lines_select" on journal_lines for select to authenticated using (tenant_id = public.user_tenant_id());
  create policy "journal_lines_insert" on journal_lines for insert to authenticated with check (tenant_id = public.user_tenant_id());
  create policy "journal_lines_update" on journal_lines for update to authenticated using (tenant_id = public.user_tenant_id());
  create policy "journal_lines_delete" on journal_lines for delete to authenticated using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for journal_lines';
exception
  when undefined_table then raise notice '⚠ Table journal_lines does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in journal_lines';
  when duplicate_object then raise notice '⚠ Policies already exist for journal_lines';
end $$;

-- Orders: Tenant isolation (POS)
do $$ begin
  create policy "orders_select" on orders for select using (tenant_id = public.user_tenant_id());
  create policy "orders_insert" on orders for insert with check (tenant_id = public.user_tenant_id());
  create policy "orders_update" on orders for update using (tenant_id = public.user_tenant_id());
  create policy "orders_delete" on orders for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for orders';
exception
  when undefined_table then raise notice '⚠ Table orders does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in orders';
  when duplicate_object then raise notice '⚠ Policies already exist for orders';
end $$;

-- Order Items: Tenant isolation (POS)
do $$ begin
  create policy "order_items_select" on order_items for select using (tenant_id = public.user_tenant_id());
  create policy "order_items_insert" on order_items for insert with check (tenant_id = public.user_tenant_id());
  create policy "order_items_update" on order_items for update using (tenant_id = public.user_tenant_id());
  create policy "order_items_delete" on order_items for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for order_items';
exception
  when undefined_table then raise notice '⚠ Table order_items does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in order_items';
  when duplicate_object then raise notice '⚠ Policies already exist for order_items';
end $$;

-- Departments: Tenant isolation (HR)
do $$ begin
  create policy "departments_select" on departments for select using (tenant_id = public.user_tenant_id());
  create policy "departments_insert" on departments for insert with check (tenant_id = public.user_tenant_id());
  create policy "departments_update" on departments for update using (tenant_id = public.user_tenant_id());
  create policy "departments_delete" on departments for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for departments';
exception
  when undefined_table then raise notice '⚠ Table departments does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in departments';
  when duplicate_object then raise notice '⚠ Policies already exist for departments';
end $$;

-- Company Settings: Tenant isolation (CRITICAL - logo/company data)
do $$ begin
  create policy "company_settings_select" on company_settings 
    for select to authenticated
    using (tenant_id = public.user_tenant_id());
  create policy "company_settings_insert" on company_settings 
    for insert to authenticated
    with check (tenant_id = public.user_tenant_id());
  create policy "company_settings_update" on company_settings 
    for update to authenticated
    using (tenant_id = public.user_tenant_id());
  create policy "company_settings_delete" on company_settings 
    for delete to authenticated
    using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for company_settings';
exception
  when undefined_table then raise notice '⚠ Table company_settings does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in company_settings';
  when duplicate_object then raise notice '⚠ Policies already exist for company_settings';
end $$;

-- Bikes: Tenant isolation (Customer bikes/vehicles)
do $$ begin
  create policy "bikes_select" on bikes for select using (tenant_id = public.user_tenant_id());
  create policy "bikes_insert" on bikes for insert with check (tenant_id = public.user_tenant_id());
  create policy "bikes_update" on bikes for update using (tenant_id = public.user_tenant_id());
  create policy "bikes_delete" on bikes for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for bikes';
exception
  when undefined_table then raise notice '⚠ Table bikes does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in bikes';
  when duplicate_object then raise notice '⚠ Policies already exist for bikes';
end $$;

-- Mechanic Jobs: Tenant isolation
do $$ begin
  create policy "mechanic_jobs_select" on mechanic_jobs for select using (tenant_id = public.user_tenant_id());
  create policy "mechanic_jobs_insert" on mechanic_jobs for insert with check (tenant_id = public.user_tenant_id());
  create policy "mechanic_jobs_update" on mechanic_jobs for update using (tenant_id = public.user_tenant_id());
  create policy "mechanic_jobs_delete" on mechanic_jobs for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for mechanic_jobs';
exception
  when undefined_table then raise notice '⚠ Table mechanic_jobs does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in mechanic_jobs';
  when duplicate_object then raise notice '⚠ Policies already exist for mechanic_jobs';
end $$;

-- Mechanic Job Items: Tenant isolation
do $$ begin
  create policy "mechanic_job_items_select" on mechanic_job_items for select using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_items_insert" on mechanic_job_items for insert with check (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_items_update" on mechanic_job_items for update using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_items_delete" on mechanic_job_items for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for mechanic_job_items';
exception
  when undefined_table then raise notice '⚠ Table mechanic_job_items does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in mechanic_job_items';
  when duplicate_object then raise notice '⚠ Policies already exist for mechanic_job_items';
end $$;

-- Mechanic Job Tasks: Tenant isolation (SMART TASKS SYSTEM)
alter table mechanic_job_tasks enable row level security;

drop policy if exists "mechanic_job_tasks_select" on mechanic_job_tasks;
drop policy if exists "mechanic_job_tasks_insert" on mechanic_job_tasks;
drop policy if exists "mechanic_job_tasks_update" on mechanic_job_tasks;
drop policy if exists "mechanic_job_tasks_delete" on mechanic_job_tasks;

create policy "mechanic_job_tasks_select" on mechanic_job_tasks
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_tasks_insert" on mechanic_job_tasks
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "mechanic_job_tasks_update" on mechanic_job_tasks
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_tasks_delete" on mechanic_job_tasks
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================
-- FUNCTION: Recalculate per-bike costs (Multi-bike support)
-- Called when items change to update the parent job_bike costs
-- ============================================================
create or replace function public.recalculate_job_bike_costs()
returns trigger
security definer
language plpgsql
as $$
declare
  v_job_bike_id uuid;
  v_parts_cost numeric(12,2);
  v_labor_cost numeric(12,2);
begin
  -- Get the job_bike_id from the changed item
  if TG_OP = 'DELETE' then
    v_job_bike_id := OLD.job_bike_id;
  else
    v_job_bike_id := NEW.job_bike_id;
  end if;
  
  -- Skip if no job_bike_id (legacy single-bike jobs)
  if v_job_bike_id is null then
    return coalesce(NEW, OLD);
  end if;
  
  -- Calculate costs for this bike
  select 
    coalesce(sum(case when item_type = 'product' or item_type is null then total_price else 0 end), 0),
    coalesce(sum(case when item_type = 'service' then total_price else 0 end), 0)
  into v_parts_cost, v_labor_cost
  from mechanic_job_items
  where job_bike_id = v_job_bike_id;
  
  -- Update the job_bike record
  update mechanic_job_bikes
  set 
    parts_cost = v_parts_cost,
    labor_cost = v_labor_cost,
    subtotal = v_parts_cost + v_labor_cost,
    updated_at = now()
  where id = v_job_bike_id;
  
  return coalesce(NEW, OLD);
end;
$$;

-- Trigger to recalculate bike costs when items change
drop trigger if exists trg_mechanic_job_items_bike_costs on mechanic_job_items;
create trigger trg_mechanic_job_items_bike_costs
  after insert or update or delete on mechanic_job_items
  for each row
  execute function public.recalculate_job_bike_costs();

-- Mechanic Job Task Preferences: User-specific (no tenant check needed, user_id is sufficient)
alter table mechanic_job_task_preferences enable row level security;

drop policy if exists "task_prefs_select" on mechanic_job_task_preferences;
drop policy if exists "task_prefs_insert" on mechanic_job_task_preferences;
drop policy if exists "task_prefs_update" on mechanic_job_task_preferences;
drop policy if exists "task_prefs_delete" on mechanic_job_task_preferences;

create policy "task_prefs_select" on mechanic_job_task_preferences
  for select
  to authenticated
  using (user_id = auth.uid() and tenant_id = public.user_tenant_id());

create policy "task_prefs_insert" on mechanic_job_task_preferences
  for insert
  to authenticated
  with check (user_id = auth.uid() and tenant_id = public.user_tenant_id());

create policy "task_prefs_update" on mechanic_job_task_preferences
  for update
  to authenticated
  using (user_id = auth.uid() and tenant_id = public.user_tenant_id());

create policy "task_prefs_delete" on mechanic_job_task_preferences
  for delete
  to authenticated
  using (user_id = auth.uid() and tenant_id = public.user_tenant_id());

-- Mechanic Job Timeline: Tenant isolation
alter table mechanic_job_timeline enable row level security;

drop policy if exists "mechanic_job_timeline_select" on mechanic_job_timeline;
drop policy if exists "mechanic_job_timeline_insert" on mechanic_job_timeline;
drop policy if exists "mechanic_job_timeline_update" on mechanic_job_timeline;
drop policy if exists "mechanic_job_timeline_delete" on mechanic_job_timeline;

create policy "mechanic_job_timeline_select" on mechanic_job_timeline
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_timeline_insert" on mechanic_job_timeline
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "mechanic_job_timeline_update" on mechanic_job_timeline
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_timeline_delete" on mechanic_job_timeline
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- Expense Attachments: Tenant isolation
do $$ begin
  create policy "expense_attachments_select" on expense_attachments for select using (tenant_id = public.user_tenant_id());
  create policy "expense_attachments_insert" on expense_attachments for insert with check (tenant_id = public.user_tenant_id());
  create policy "expense_attachments_update" on expense_attachments for update using (tenant_id = public.user_tenant_id());
  create policy "expense_attachments_delete" on expense_attachments for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for expense_attachments';
exception
  when undefined_table then raise notice '⚠ Table expense_attachments does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in expense_attachments';
  when duplicate_object then raise notice '⚠ Policies already exist for expense_attachments';
end $$;

-- Expense Lines: Tenant isolation
do $$ begin
  create policy "expense_lines_select" on expense_lines for select using (tenant_id = public.user_tenant_id());
  create policy "expense_lines_insert" on expense_lines for insert with check (tenant_id = public.user_tenant_id());
  create policy "expense_lines_update" on expense_lines for update using (tenant_id = public.user_tenant_id());
  create policy "expense_lines_delete" on expense_lines for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for expense_lines';
exception
  when undefined_table then raise notice '⚠ Table expense_lines does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in expense_lines';
  when duplicate_object then raise notice '⚠ Policies already exist for expense_lines';
end $$;

-- Expense Payments: Tenant isolation
do $$ begin
  create policy "expense_payments_select" on expense_payments for select using (tenant_id = public.user_tenant_id());
  create policy "expense_payments_insert" on expense_payments for insert with check (tenant_id = public.user_tenant_id());
  create policy "expense_payments_update" on expense_payments for update using (tenant_id = public.user_tenant_id());
  create policy "expense_payments_delete" on expense_payments for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for expense_payments';
exception
  when undefined_table then raise notice '⚠ Table expense_payments does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in expense_payments';
  when duplicate_object then raise notice '⚠ Policies already exist for expense_payments';
end $$;

-- Website Blocks: Tenant isolation
do $$ begin
  create policy "website_blocks_select" on website_blocks for select using (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  create policy "website_blocks_insert" on website_blocks for insert with check (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  create policy "website_blocks_update" on website_blocks for update using (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  create policy "website_blocks_delete" on website_blocks for delete using (
    tenant_id in (select tenant_id from user_profiles where user_id = auth.uid())
  );
  raise notice '✓ Created RLS policies for website_blocks';
exception
  when undefined_table then raise notice '⚠ Table website_blocks does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in website_blocks';
  when duplicate_object then raise notice '⚠ Policies already exist for website_blocks';
end $$;

-- Online Orders: Tenant isolation
do $$ begin
  create policy "online_orders_select" on online_orders for select using (tenant_id = public.user_tenant_id());
  create policy "online_orders_insert" on online_orders for insert with check (tenant_id = public.user_tenant_id());
  create policy "online_orders_update" on online_orders for update using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for online_orders';
exception
  when undefined_table then raise notice '⚠ Table online_orders does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in online_orders';
  when duplicate_object then raise notice '⚠ Policies already exist for online_orders';
end $$;

-- Payment Methods: Tenant isolation
do $$ begin
  alter table payment_methods enable row level security;
  
  drop policy if exists "payment_methods_select" on payment_methods;
  drop policy if exists "payment_methods_insert" on payment_methods;
  drop policy if exists "payment_methods_update" on payment_methods;
  drop policy if exists "payment_methods_delete" on payment_methods;
  
  create policy "payment_methods_select" on payment_methods 
    for select 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  create policy "payment_methods_insert" on payment_methods 
    for insert 
    to authenticated
    with check (tenant_id = public.user_tenant_id());
    
  create policy "payment_methods_update" on payment_methods 
    for update 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  create policy "payment_methods_delete" on payment_methods 
    for delete 
    to authenticated
    using (tenant_id = public.user_tenant_id());
    
  raise notice '✓ Created RLS policies for payment_methods';
exception
  when undefined_table then raise notice '⚠ Table payment_methods does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in payment_methods';
  when duplicate_object then raise notice '⚠ Policies already exist for payment_methods';
end $$;

-- Website Banners: Tenant isolation
do $$ begin
  create policy "website_banners_select" on website_banners for select using (tenant_id = public.user_tenant_id());
  create policy "website_banners_insert" on website_banners for insert with check (tenant_id = public.user_tenant_id());
  create policy "website_banners_update" on website_banners for update using (tenant_id = public.user_tenant_id());
  create policy "website_banners_delete" on website_banners for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for website_banners';
exception
  when undefined_table then raise notice '⚠ Table website_banners does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in website_banners';
  when duplicate_object then raise notice '⚠ Policies already exist for website_banners';
end $$;

-- Featured Products: Tenant isolation
do $$ begin
  create policy "featured_products_select" on featured_products for select using (tenant_id = public.user_tenant_id());
  create policy "featured_products_insert" on featured_products for insert with check (tenant_id = public.user_tenant_id());
  create policy "featured_products_update" on featured_products for update using (tenant_id = public.user_tenant_id());
  create policy "featured_products_delete" on featured_products for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for featured_products';
exception
  when undefined_table then raise notice '⚠ Table featured_products does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in featured_products';
  when duplicate_object then raise notice '⚠ Policies already exist for featured_products';
end $$;

-- Website Content: Tenant isolation
do $$ begin
  create policy "website_content_select" on website_content for select using (tenant_id = public.user_tenant_id());
  create policy "website_content_insert" on website_content for insert with check (tenant_id = public.user_tenant_id());
  create policy "website_content_update" on website_content for update using (tenant_id = public.user_tenant_id());
  create policy "website_content_delete" on website_content for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for website_content';
exception
  when undefined_table then raise notice '⚠ Table website_content does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in website_content';
  when duplicate_object then raise notice '⚠ Policies already exist for website_content';
end $$;

-- Online Order Items: Tenant isolation
do $$ begin
  create policy "online_order_items_select" on online_order_items for select using (tenant_id = public.user_tenant_id());
  create policy "online_order_items_insert" on online_order_items for insert with check (tenant_id = public.user_tenant_id());
  create policy "online_order_items_update" on online_order_items for update using (tenant_id = public.user_tenant_id());
  create policy "online_order_items_delete" on online_order_items for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for online_order_items';
exception
  when undefined_table then raise notice '⚠ Table online_order_items does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in online_order_items';
  when duplicate_object then raise notice '⚠ Policies already exist for online_order_items';
end $$;

--------------------------------------------------------------------------------
-- AUTO-SIGNUP SYSTEM: Automatic Tenant Creation & Invitation Handling
--------------------------------------------------------------------------------
-- This trigger automatically handles new user signups:
-- 1. If user has a pending invitation → Join existing tenant with assigned role
-- 2. If no invitation → Create new tenant and assign as manager
--------------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
  v_tenant_id uuid;
  v_invitation record;
  v_shop_name text;
  v_subdomain text;
  v_subdomain_base text;
  v_counter integer := 1;
begin
  -- Check if user was invited (has pending invitation)
  -- Use LOWER() for case-insensitive email matching
  select * into v_invitation
  from user_invitations
  where lower(email) = lower(new.email)
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if found then
    -- ========================================================================
    -- SCENARIO: User was invited → Join existing tenant
    -- ========================================================================
    v_tenant_id := v_invitation.tenant_id;
    
    raise notice '✅ User % joining tenant % via invitation (role: %)', new.email, v_tenant_id, v_invitation.role;
    
    -- Create user_profile entry linking user to tenant
    begin
      insert into user_profiles (user_id, tenant_id, role, is_active, permissions)
      values (new.id, v_tenant_id, v_invitation.role, true, 
        case v_invitation.role
          when 'admin' then '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb
          when 'manager' then '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb
          when 'cashier' then '{"access_pos": true, "create_invoices": true, "edit_prices": false, "delete_invoices": false, "access_accounting": false, "manage_users": false, "edit_settings": false}'::jsonb
          when 'accountant' then '{"access_pos": false, "create_invoices": false, "edit_prices": false, "delete_invoices": false, "access_accounting": true, "manage_users": false, "edit_settings": false}'::jsonb
          when 'mechanic' then '{"access_pos": false, "create_invoices": false, "edit_prices": false, "delete_invoices": false, "access_accounting": false, "manage_users": false, "edit_settings": false}'::jsonb
          else '{}'::jsonb
        end
      );
      raise notice '✅ Created user_profile for user %', new.id;
    exception
      when others then
        raise exception '❌ Failed to create user_profile: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    end;
    
    -- Update user metadata to include tenant_id and role
    begin
      update auth.users
      set 
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'tenant_id', v_tenant_id,
          'role', v_invitation.role
        ),
        email_confirmed_at = now() -- Auto-confirm email for invited users
      where id = new.id;
      raise notice '✅ Updated user metadata and confirmed email';
    exception
      when others then
        raise warning '⚠️ Failed to update user metadata: %', SQLERRM;
    end;
    
    -- Mark invitation as accepted
    begin
      update user_invitations
      set status = 'accepted', accepted_at = now()
      where id = v_invitation.id;
      raise notice '✅ Marked invitation as accepted';
    exception
      when others then
        raise warning '⚠️ Failed to mark invitation as accepted: %', SQLERRM;
    end;
    
    raise notice '✅ User % joined tenant % via invitation', new.email, v_tenant_id;
  else
    -- ========================================================================
    -- SCENARIO: No invitation → Create new tenant (new business owner)
    -- ========================================================================
    
    raise notice '⚠️ No pending invitation found for %, creating new tenant', new.email;
    
    -- Extract shop name from signup data or email
    v_shop_name := coalesce(
      new.raw_user_meta_data->>'shop_name',
      split_part(new.email, '@', 1) || '''s Shop'
    );
    
    -- Generate base subdomain from shop name or email
    v_subdomain_base := coalesce(
      new.raw_user_meta_data->>'subdomain',
      lower(regexp_replace(split_part(new.email, '@', 1), '[^a-z0-9]', '', 'g'))
    );
    
    v_subdomain := v_subdomain_base;
    
    -- Handle duplicate subdomains by appending counter
    while exists (select 1 from tenants where subdomain = v_subdomain) loop
      v_subdomain := v_subdomain_base || v_counter;
      v_counter := v_counter + 1;
      
      -- Prevent infinite loop
      if v_counter > 100 then
        raise exception 'Could not generate unique subdomain for %', new.email;
      end if;
    end loop;
    
    -- Create new tenant
    begin
      insert into tenants (shop_name, subdomain, owner_email, plan, is_active, currency, timezone)
      values (
        v_shop_name,
        v_subdomain,
        new.email,
        'free',  -- Start with free plan
        true,
        'CLP',
        'America/Santiago'
      )
      returning id into v_tenant_id;
      raise notice '✅ Created new tenant % with subdomain %', v_tenant_id, v_subdomain;
    exception
      when others then
        raise exception '❌ Failed to create tenant: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    end;
    
    -- Create user_profile entry linking user to tenant as admin
    begin
      insert into user_profiles (user_id, tenant_id, role, is_active, permissions)
      values (new.id, v_tenant_id, 'admin', true, 
        '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb
      );
      raise notice '✅ Created user_profile for admin user %', new.id;
    exception
      when others then
        raise exception '❌ Failed to create user_profile for new tenant: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    end;
    
    -- Update user metadata to include tenant_id and role
    begin
      update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
        'tenant_id', v_tenant_id,
        'role', 'admin'
      )
      where id = new.id;
      raise notice '✅ Updated user metadata for new tenant owner';
    exception
      when others then
        raise warning '⚠️ Failed to update user metadata: %', SQLERRM;
    end;
    
    raise notice '✅ Created new tenant % for user % with subdomain %', v_tenant_id, new.email, v_subdomain;
  end if;

  return new;
end;
$$;

-- Drop existing trigger if it exists
drop trigger if exists on_auth_user_created on auth.users;

-- ENABLED: Automatic tenant creation trigger
-- This automatically creates tenant + user_profile when users sign up
-- Works for both auto-confirm and email confirmation flows

-- Create trigger on new user signup (AFTER INSERT so user ID exists)
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ============================================================================
-- MISSING TABLES - Add tenant_id to tables created manually in Supabase
-- ============================================================================

-- CRITICAL MIGRATION: Add tenant_id to ALL existing tables that are missing it
do $$
declare
  vinabike_tenant_id uuid := '97ef40bf-f58c-4f76-a629-c013fb3928cf';
  v_table text;
  v_tables text[] := ARRAY[
    'analytics_snapshots', 'attendance_records', 'campaign_metrics', 'campaigns',
    'companies', 'company_settings', 'content_items', 'content_media',
    'employee_contracts', 'featured_products', 'inventory_adjustments', 'leave_requests',
    'online_order_items', 'payroll_entries', 'payroll_runs', 'purchase_order_items',
    'purchase_orders', 'sales_order_items', 'sales_orders', 'service_packages',
    'shifts', 'users_profiles', 'vehicles', 'website_banners', 'work_order_items',
    'work_schedules'
  ];
begin
  raise notice 'Starting tenant_id migration for existing tables...';
  
  foreach v_table in array v_tables loop
    begin
      -- Check if table exists and doesn't have tenant_id
      if exists (select 1 from information_schema.tables where table_name = v_table and table_schema = 'public')
        and not exists (select 1 from information_schema.columns where table_name = v_table and column_name = 'tenant_id')
      then
        execute format('alter table %I add column tenant_id uuid references tenants(id) on delete cascade', v_table);
        execute format('update %I set tenant_id = $1 where tenant_id is null', v_table) using vinabike_tenant_id;
        execute format('alter table %I alter column tenant_id set not null', v_table);
        execute format('create index if not exists idx_%s_tenant on %I(tenant_id)', v_table, v_table);
        raise notice '✅ Added tenant_id to %', v_table;
      else
        raise notice '⏭️  Skipped % (already has tenant_id or does not exist)', v_table;
      end if;
    exception when others then
      raise notice '❌ Error migrating %: %', v_table, SQLERRM;
    end;
  end loop;
  
  raise notice 'tenant_id migration complete!';
end $$;

-- Analytics snapshots
create table if not exists analytics_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  snapshot_date date not null,
  metric_name text not null,
  metric_value numeric(12,2),
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, snapshot_date, metric_name)
);

do $$ begin
  create index if not exists idx_analytics_snapshots_tenant on analytics_snapshots(tenant_id);
  create index if not exists idx_analytics_snapshots_date on analytics_snapshots(snapshot_date);
exception
  when undefined_table then raise notice '⚠ Table analytics_snapshots does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in analytics_snapshots';
end $$;

-- Attendance records
create table if not exists attendance_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid references employees(id) on delete cascade,
  check_in timestamp with time zone,
  check_out timestamp with time zone,
  date date not null,
  status text check (status in ('present', 'absent', 'late', 'half_day', 'leave')) default 'present',
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_attendance_records_tenant on attendance_records(tenant_id);
  create index if not exists idx_attendance_records_employee on attendance_records(employee_id);
  create index if not exists idx_attendance_records_date on attendance_records(date);
exception
  when undefined_table then raise notice '⚠ Table attendance_records does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in attendance_records';
end $$;

-- Campaigns
create table if not exists campaigns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  description text,
  campaign_type text check (campaign_type in ('email', 'sms', 'push', 'promo')) not null,
  status text check (status in ('draft', 'scheduled', 'active', 'paused', 'completed')) default 'draft',
  start_date timestamp with time zone,
  end_date timestamp with time zone,
  target_segment jsonb, -- Customer segmentation criteria
  message_template text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name)
);

do $$ begin
  create index if not exists idx_campaigns_tenant on campaigns(tenant_id);
  create index if not exists idx_campaigns_status on campaigns(status);
exception
  when undefined_table then raise notice '⚠ Table campaigns does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in campaigns';
end $$;

-- Campaign metrics
create table if not exists campaign_metrics (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  campaign_id uuid references campaigns(id) on delete cascade,
  metric_date date not null,
  sent_count integer default 0,
  opened_count integer default 0,
  clicked_count integer default 0,
  converted_count integer default 0,
  revenue_generated numeric(12,2) default 0,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_campaign_metrics_tenant on campaign_metrics(tenant_id);
  create index if not exists idx_campaign_metrics_campaign on campaign_metrics(campaign_id);
exception
  when undefined_table then raise notice '⚠ Table campaign_metrics does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in campaign_metrics';
end $$;

-- Companies (multi-company support within tenant)
create table if not exists companies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  legal_name text,
  tax_id text,
  address text,
  city text,
  country text default 'Chile',
  phone text,
  email text,
  is_default boolean default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, tax_id)
);

do $$ begin
  create index if not exists idx_companies_tenant on companies(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table companies does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in companies';
end $$;

-- Content items (for website builder CMS)
create table if not exists content_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  title text not null,
  slug text not null,
  content_type text check (content_type in ('page', 'blog', 'promo', 'faq')) not null,
  content text,
  meta_description text,
  published boolean default false,
  published_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, slug)
);

do $$ begin
  create index if not exists idx_content_items_tenant on content_items(tenant_id);
  create index if not exists idx_content_items_slug on content_items(slug);
exception
  when undefined_table then raise notice '⚠ Table content_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in content_items';
end $$;

-- Content media (images/videos for CMS)
create table if not exists content_media (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  content_item_id uuid references content_items(id) on delete cascade,
  media_type text check (media_type in ('image', 'video', 'document')) not null,
  url text not null,
  alt_text text,
  display_order integer default 0,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_content_media_tenant on content_media(tenant_id);
  create index if not exists idx_content_media_content on content_media(content_item_id);
exception
  when undefined_table then raise notice '⚠ Table content_media does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in content_media';
end $$;

-- Inventory adjustments
create table if not exists inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  warehouse_id uuid references warehouses(id) on delete cascade,
  adjustment_type text check (adjustment_type in ('add', 'subtract', 'set')) not null,
  quantity integer not null,
  reason text,
  reference text,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_inventory_adjustments_tenant on inventory_adjustments(tenant_id);
  create index if not exists idx_inventory_adjustments_product on inventory_adjustments(product_id);
exception
  when undefined_table then raise notice '⚠ Table inventory_adjustments does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in inventory_adjustments';
end $$;

-- Leave requests
create table if not exists leave_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid references employees(id) on delete cascade,
  leave_type text check (leave_type in ('vacation', 'sick', 'personal', 'unpaid', 'bereavement')) not null,
  start_date date not null,
  end_date date not null,
  days_count numeric(5,2) not null,
  status text check (status in ('pending', 'approved', 'rejected', 'cancelled')) default 'pending',
  reason text,
  approved_by uuid references auth.users(id),
  approved_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_leave_requests_tenant on leave_requests(tenant_id);
  create index if not exists idx_leave_requests_employee on leave_requests(employee_id);
  create index if not exists idx_leave_requests_status on leave_requests(status);
exception
  when undefined_table then raise notice '⚠ Table leave_requests does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in leave_requests';
end $$;

-- Payroll runs
create table if not exists payroll_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  period_start date not null,
  period_end date not null,
  payment_date date not null,
  status text check (status in ('draft', 'processing', 'completed', 'paid')) default 'draft',
  total_gross numeric(12,2) default 0,
  total_deductions numeric(12,2) default 0,
  total_net numeric(12,2) default 0,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_payroll_runs_tenant on payroll_runs(tenant_id);
  create index if not exists idx_payroll_runs_period on payroll_runs(period_start, period_end);
exception
  when undefined_table then raise notice '⚠ Table payroll_runs does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in payroll_runs';
end $$;

-- Payroll entries
create table if not exists payroll_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  payroll_run_id uuid references payroll_runs(id) on delete cascade,
  employee_id uuid references employees(id) on delete cascade,
  gross_salary numeric(12,2) not null,
  overtime_hours numeric(5,2) default 0,
  overtime_pay numeric(12,2) default 0,
  bonuses numeric(12,2) default 0,
  deductions numeric(12,2) default 0,
  net_salary numeric(12,2) not null,
  payment_status text check (payment_status in ('pending', 'paid', 'failed')) default 'pending',
  payment_method text,
  payment_reference text,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_payroll_entries_tenant on payroll_entries(tenant_id);
  create index if not exists idx_payroll_entries_run on payroll_entries(payroll_run_id);
  create index if not exists idx_payroll_entries_employee on payroll_entries(employee_id);
exception
  when undefined_table then raise notice '⚠ Table payroll_entries does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in payroll_entries';
end $$;

-- Purchase orders
create table if not exists purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  order_number text not null,
  supplier_id uuid references suppliers(id) on delete cascade,
  order_date date not null,
  expected_date date,
  status text check (status in ('draft', 'sent', 'confirmed', 'received', 'cancelled')) default 'draft',
  subtotal numeric(12,2) default 0,
  tax_amount numeric(12,2) default 0,
  total_amount numeric(12,2) default 0,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, order_number)
);

do $$ begin
  create index if not exists idx_purchase_orders_tenant on purchase_orders(tenant_id);
  create index if not exists idx_purchase_orders_supplier on purchase_orders(supplier_id);
  create index if not exists idx_purchase_orders_status on purchase_orders(status);
exception
  when undefined_table then raise notice '⚠ Table purchase_orders does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in purchase_orders';
end $$;

-- Purchase order items
create table if not exists purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  purchase_order_id uuid references purchase_orders(id) on delete cascade,
  product_id uuid references products(id) on delete cascade,
  quantity integer not null,
  unit_price numeric(12,2) not null,
  subtotal numeric(12,2) not null,
  tax_rate numeric(5,2) default 19,
  tax_amount numeric(12,2) default 0,
  total numeric(12,2) not null,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_purchase_order_items_tenant on purchase_order_items(tenant_id);
  create index if not exists idx_purchase_order_items_order on purchase_order_items(purchase_order_id);
exception
  when undefined_table then raise notice '⚠ Table purchase_order_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in purchase_order_items';
end $$;

-- Sales orders
create table if not exists sales_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  order_number text not null,
  customer_id uuid references customers(id) on delete cascade,
  order_date date not null,
  expected_date date,
  status text check (status in ('draft', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled')) default 'draft',
  subtotal numeric(12,2) default 0,
  tax_amount numeric(12,2) default 0,
  total_amount numeric(12,2) default 0,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, order_number)
);

do $$ begin
  create index if not exists idx_sales_orders_tenant on sales_orders(tenant_id);
  create index if not exists idx_sales_orders_customer on sales_orders(customer_id);
  create index if not exists idx_sales_orders_status on sales_orders(status);
exception
  when undefined_table then raise notice '⚠ Table sales_orders does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in sales_orders';
end $$;

-- Sales order items
create table if not exists sales_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  sales_order_id uuid references sales_orders(id) on delete cascade,
  product_id uuid references products(id) on delete cascade,
  quantity integer not null,
  unit_price numeric(12,2) not null,
  discount_percent numeric(5,2) default 0,
  subtotal numeric(12,2) not null,
  tax_rate numeric(5,2) default 19,
  tax_amount numeric(12,2) default 0,
  total numeric(12,2) not null,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_sales_order_items_tenant on sales_order_items(tenant_id);
  create index if not exists idx_sales_order_items_order on sales_order_items(sales_order_id);
exception
  when undefined_table then raise notice '⚠ Table sales_order_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in sales_order_items';
end $$;

-- Shifts (for scheduling)
create table if not exists shifts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid references employees(id) on delete cascade,
  shift_date date not null,
  start_time time not null,
  end_time time not null,
  break_duration integer default 60, -- minutes
  status text check (status in ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled')) default 'scheduled',
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_shifts_tenant on shifts(tenant_id);
  create index if not exists idx_shifts_employee on shifts(employee_id);
  create index if not exists idx_shifts_date on shifts(shift_date);
exception
  when undefined_table then raise notice '⚠ Table shifts does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in shifts';
end $$;

-- User profiles (extended user data)
create table if not exists users_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid references tenants(id) on delete cascade not null,
  full_name text,
  avatar_url text,
  phone text,
  address text,
  city text,
  country text default 'Chile',
  preferences jsonb default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_users_profiles_tenant on users_profiles(tenant_id);
exception
  when undefined_table then raise notice '⚠ Table users_profiles does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in users_profiles';
end $$;

-- Vehicles (for bike shop - customer bikes)
create table if not exists vehicles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  customer_id uuid references customers(id) on delete cascade,
  vehicle_type text check (vehicle_type in ('bike', 'ebike', 'scooter', 'motorcycle', 'other')) default 'bike',
  brand text,
  model text,
  year integer,
  serial_number text,
  color text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_vehicles_tenant on vehicles(tenant_id);
  create index if not exists idx_vehicles_customer on vehicles(customer_id);
  create index if not exists idx_vehicles_serial on vehicles(serial_number);
exception
  when undefined_table then raise notice '⚠ Table vehicles does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in vehicles';
end $$;

-- Work order items (parts/services for work orders)
create table if not exists work_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  work_order_id uuid references work_orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  item_type text check (item_type in ('part', 'service', 'labor')) not null,
  description text not null,
  quantity numeric(10,2) not null default 1,
  unit_price numeric(12,2) not null,
  subtotal numeric(12,2) not null,
  created_at timestamp with time zone not null default now()
);

do $$ begin
  create index if not exists idx_work_order_items_tenant on work_order_items(tenant_id);
  create index if not exists idx_work_order_items_work_order on work_order_items(work_order_id);
exception
  when undefined_table then raise notice '⚠ Table work_order_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in work_order_items';
end $$;

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES FOR MISSING TABLES
-- ============================================================================

-- Enable RLS and create policies for all missing tables
-- Each table wrapped in its own exception handler

-- analytics_snapshots
do $$ begin
  alter table analytics_snapshots enable row level security;
  drop policy if exists analytics_snapshots_tenant_isolation on analytics_snapshots;
  create policy analytics_snapshots_tenant_isolation on analytics_snapshots
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- attendance_records
do $$ begin
  alter table attendance_records enable row level security;
  drop policy if exists attendance_records_tenant_isolation on attendance_records;
  create policy attendance_records_tenant_isolation on attendance_records
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- campaigns
do $$ begin
  alter table campaigns enable row level security;
  drop policy if exists campaigns_tenant_isolation on campaigns;
  create policy campaigns_tenant_isolation on campaigns
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- campaign_metrics
do $$ begin
  alter table campaign_metrics enable row level security;
  drop policy if exists campaign_metrics_tenant_isolation on campaign_metrics;
  create policy campaign_metrics_tenant_isolation on campaign_metrics
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- companies
do $$ begin
  alter table companies enable row level security;
  drop policy if exists companies_tenant_isolation on companies;
  create policy companies_tenant_isolation on companies
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- content_items
do $$ begin
  alter table content_items enable row level security;
  drop policy if exists content_items_tenant_isolation on content_items;
  create policy content_items_tenant_isolation on content_items
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- content_media
do $$ begin
  alter table content_media enable row level security;
  drop policy if exists content_media_tenant_isolation on content_media;
  create policy content_media_tenant_isolation on content_media
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- inventory_adjustments
do $$ begin
  alter table inventory_adjustments enable row level security;
  drop policy if exists inventory_adjustments_tenant_isolation on inventory_adjustments;
  create policy inventory_adjustments_tenant_isolation on inventory_adjustments
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- leave_requests
do $$ begin
  alter table leave_requests enable row level security;
  drop policy if exists leave_requests_tenant_isolation on leave_requests;
  create policy leave_requests_tenant_isolation on leave_requests
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- payroll_runs
do $$ begin
  alter table payroll_runs enable row level security;
  drop policy if exists payroll_runs_tenant_isolation on payroll_runs;
  create policy payroll_runs_tenant_isolation on payroll_runs
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- payroll_entries
do $$ begin
  alter table payroll_entries enable row level security;
  drop policy if exists payroll_entries_tenant_isolation on payroll_entries;
  create policy payroll_entries_tenant_isolation on payroll_entries
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- purchase_orders
do $$ begin
  alter table purchase_orders enable row level security;
  drop policy if exists purchase_orders_tenant_isolation on purchase_orders;
  create policy purchase_orders_tenant_isolation on purchase_orders
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- purchase_order_items
do $$ begin
  alter table purchase_order_items enable row level security;
  drop policy if exists purchase_order_items_tenant_isolation on purchase_order_items;
  create policy purchase_order_items_tenant_isolation on purchase_order_items
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- sales_orders
do $$ begin
  alter table sales_orders enable row level security;
  drop policy if exists sales_orders_tenant_isolation on sales_orders;
  create policy sales_orders_tenant_isolation on sales_orders
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- sales_order_items
do $$ begin
  alter table sales_order_items enable row level security;
  drop policy if exists sales_order_items_tenant_isolation on sales_order_items;
  create policy sales_order_items_tenant_isolation on sales_order_items
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- shifts
do $$ begin
  alter table shifts enable row level security;
  drop policy if exists shifts_tenant_isolation on shifts;
  create policy shifts_tenant_isolation on shifts
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- users_profiles
do $$ begin
  alter table users_profiles enable row level security;
  drop policy if exists users_profiles_tenant_isolation on users_profiles;
  create policy users_profiles_tenant_isolation on users_profiles
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- vehicles
do $$ begin
  alter table vehicles enable row level security;
  drop policy if exists vehicles_tenant_isolation on vehicles;
  create policy vehicles_tenant_isolation on vehicles
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

-- work_order_items
do $$ begin
  alter table work_order_items enable row level security;
  drop policy if exists work_order_items_tenant_isolation on work_order_items;
  create policy work_order_items_tenant_isolation on work_order_items
    for all using (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

--------------------------------------------------------------------------------
-- PUBLIC STORE RLS POLICIES
-- Allow both anonymous AND authenticated website customers to read tenant-scoped data
-- These policies enable public-facing storefronts to work with or without auth
-- 
-- ARCHITECTURE NOTE:
-- - ERP Users: Have user_profiles record → use user_tenant_id() function
-- - Website Customers: Have customers record (NO user_profiles) → use explicit tenant_id filter
-- - Anonymous Visitors: No auth → use explicit tenant_id filter
--
-- SECURITY NOTE: These policies allow broad read access, but the application
-- layer (PublicInventoryService) MUST filter by tenant_id using .eq('tenant_id', tenantId)
-- to prevent cross-tenant data leakage. These policies provide defense-in-depth
-- but rely on app-layer filtering for tenant isolation.
--------------------------------------------------------------------------------

-- Drop existing policies first (both anon and authenticated versions)
drop policy if exists "public_products_select" on products;
drop policy if exists "public_products_select_authenticated" on products;
drop policy if exists "public_categories_select" on categories;
drop policy if exists "public_categories_select_authenticated" on categories;
drop policy if exists "public_product_categories_select" on product_categories;
drop policy if exists "public_product_categories_select_authenticated" on product_categories;
drop policy if exists "public_website_banners_select" on website_banners;
drop policy if exists "public_website_banners_select_authenticated" on website_banners;
drop policy if exists "public_website_content_select" on website_content;
drop policy if exists "public_website_content_select_authenticated" on website_content;
drop policy if exists "public_website_settings_select" on website_settings;
drop policy if exists "public_website_settings_select_authenticated" on website_settings;
drop policy if exists "public_website_blocks_select" on website_blocks;
drop policy if exists "public_website_blocks_select_authenticated" on website_blocks;
drop policy if exists "public_tenants_select" on tenants;
drop policy if exists "public_tenants_select_authenticated" on tenants;
drop policy if exists "public_orders_insert" on orders;
drop policy if exists "public_order_items_insert" on order_items;
drop policy if exists "public_online_orders_insert" on online_orders;
drop policy if exists "public_online_order_items_insert" on online_order_items;
drop policy if exists "public_online_orders_select_authenticated" on online_orders;
drop policy if exists "public_online_order_items_select_authenticated" on online_order_items;
drop policy if exists "public_featured_products_select" on featured_products;
drop policy if exists "public_featured_products_select_authenticated" on featured_products;
drop policy if exists "public_product_brands_select" on product_brands;
drop policy if exists "public_product_brands_select_authenticated" on product_brands;
drop policy if exists "public_customers_select_own" on customers;
drop policy if exists "public_customers_update_own" on customers;
drop policy if exists "public_customers_insert_own" on customers;
drop policy if exists "public_mechanic_jobs_select_own" on mechanic_jobs;
drop policy if exists "public_bikes_select_own" on bikes;

-- ============================================================================
-- TENANT DETECTION POLICIES
-- ============================================================================

-- Tenants: Public read access (for subdomain lookup)
-- Required for public store tenant detection from URL
create policy "public_tenants_select" on tenants 
  for select 
  to anon
  using (is_active = true);

-- Tenants: Authenticated users can also lookup tenants (for website customers)
create policy "public_tenants_select_authenticated" on tenants 
  for select 
  to authenticated
  using (is_active = true);

-- ============================================================================
-- WEBSITE CONTENT POLICIES (anon + authenticated)
-- ============================================================================

-- Website blocks: Public read access (for homepage content)
-- App must filter by tenant_id explicitly
create policy "public_website_blocks_select" on website_blocks 
  for select 
  to anon
  using (is_visible = true);

create policy "public_website_blocks_select_authenticated" on website_blocks 
  for select 
  to authenticated
  using (is_visible = true);

-- ============================================================================
-- PRODUCT CATALOG POLICIES (anon + authenticated)
-- These allow BOTH anonymous visitors AND logged-in website customers
-- to browse products. The app layer filters by tenant_id.
-- ============================================================================

-- Products: Public read access (only active products)
-- App must filter by tenant_id explicitly
-- Note: We allow products with 0 stock to be displayed (can show as "out of stock")
create policy "public_products_select" on products 
  for select 
  to anon
  using (is_active = true);

-- Products: Authenticated website customers can also browse
-- This is SEPARATE from ERP products_select which uses user_tenant_id()
-- Website customers don't have user_profiles, so they need this policy
create policy "public_products_select_authenticated" on products 
  for select 
  to authenticated
  using (
    is_active = true 
    -- Allow if user is ERP user (has user_profiles) OR is website customer
    -- ERP users already have products_select policy, but this won't conflict
    -- because PostgreSQL RLS policies are OR'd together
  );

-- Product Categories: Public read access (hierarchical categories)
-- App must filter by tenant_id explicitly
create policy "public_product_categories_select" on product_categories 
  for select 
  to anon
  using (is_active = true);

create policy "public_product_categories_select_authenticated" on product_categories 
  for select 
  to authenticated
  using (is_active = true);

-- Legacy Categories: Public read access (if table exists)
-- App must filter by tenant_id explicitly
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'categories') then
    execute 'create policy "public_categories_select" on categories for select to anon using (true)';
    execute 'create policy "public_categories_select_authenticated" on categories for select to authenticated using (true)';
  end if;
exception when duplicate_object then null;
end $$;

-- Website banners: Public read access (only active)
-- App must filter by tenant_id explicitly
create policy "public_website_banners_select" on website_banners 
  for select 
  to anon
  using (active = true);

create policy "public_website_banners_select_authenticated" on website_banners 
  for select 
  to authenticated
  using (active = true);

-- Website content: Public read access (tenant-isolated)
-- App must filter by tenant_id explicitly for multi-tenant routing
do $$ begin
  drop policy if exists "public_website_content_select" on website_content;
  drop policy if exists "public_website_content_select_authenticated" on website_content;
  create policy "public_website_content_select" on website_content 
    for select 
    to anon
    using (tenant_id is not null); -- Defense-in-depth: require valid tenant
  create policy "public_website_content_select_authenticated" on website_content 
    for select 
    to authenticated
    using (tenant_id is not null);
exception
  when undefined_table then raise notice '⚠ Table website_content does not exist';
end $$;

-- Website settings: Public read access
-- App must filter by tenant_id explicitly
create policy "public_website_settings_select" on website_settings 
  for select 
  to anon
  using (true);

create policy "public_website_settings_select_authenticated" on website_settings 
  for select 
  to authenticated
  using (true);

-- Featured products: Public read access
-- App must filter by tenant_id explicitly
create policy "public_featured_products_select" on featured_products 
  for select 
  to anon
  using (active = true);

create policy "public_featured_products_select_authenticated" on featured_products 
  for select 
  to authenticated
  using (active = true);

-- Product brands: Public read access
-- App must filter by tenant_id explicitly
create policy "public_product_brands_select" on product_brands 
  for select 
  to anon
  using (is_active = true);

create policy "public_product_brands_select_authenticated" on product_brands 
  for select 
  to authenticated
  using (is_active = true);

-- ============================================================================
-- CUSTOMER ACCOUNT POLICIES
-- Allow website customers to view/manage their own data
-- ============================================================================

-- Customers: Authenticated users can view their own customer record
create policy "public_customers_select_own" on customers 
  for select 
  to authenticated
  using (auth_user_id = auth.uid());

-- Customers: Authenticated users can update their own customer record
create policy "public_customers_update_own" on customers 
  for update 
  to authenticated
  using (auth_user_id = auth.uid());

-- Customers: INSERT own record (for website signup - user can only create their own customer record)
-- This is CRITICAL because website customers don't have user_profiles, so user_tenant_id() returns NULL
-- and the regular customers_insert policy fails
create policy "public_customers_insert_own" on customers 
  for insert 
  to authenticated
  with check (
    auth_user_id = auth.uid() AND  -- Can only create their own record
    tenant_id IS NOT NULL          -- Must specify a valid tenant
  );

-- Online Orders: Authenticated customers can view their own orders
create policy "public_online_orders_select_authenticated" on online_orders 
  for select 
  to authenticated
  using (customer_id IN (
    SELECT id FROM customers WHERE auth_user_id = auth.uid()
  ));

-- Online Order Items: Authenticated customers can view their own order items
create policy "public_online_order_items_select_authenticated" on online_order_items 
  for select 
  to authenticated
  using (order_id IN (
    SELECT id FROM online_orders WHERE customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  ));

-- Mechanic Jobs (Pegas): Website customers can view their own service history
create policy "public_mechanic_jobs_select_own" on mechanic_jobs 
  for select 
  to authenticated
  using (customer_id IN (
    SELECT id FROM customers WHERE auth_user_id = auth.uid()
  ));

-- Bikes: Website customers can view their own bikes
create policy "public_bikes_select_own" on bikes 
  for select 
  to authenticated
  using (customer_id IN (
    SELECT id FROM customers WHERE auth_user_id = auth.uid()
  ));

-- ⚠️ WRITE POLICIES FOR GUEST CHECKOUT
-- These allow anonymous users to create orders
-- The app MUST validate tenant_id matches the storefront subdomain
-- TODO: Consider adding trigger validation for tenant_id on INSERT

-- Online Orders: Anonymous users can create orders (guest checkout)
-- SECURITY: App must set correct tenant_id from subdomain detection
create policy "public_online_orders_insert" on online_orders 
  for insert 
  to anon
  with check (
    tenant_id is not null and
    status in ('pending', 'processing')
  );

-- Online Orders: Authenticated users can also create orders
create policy "public_online_orders_insert_authenticated" on online_orders 
  for insert 
  to authenticated
  with check (
    tenant_id is not null and
    status in ('pending', 'processing')
  );

-- Online Order Items: Anonymous users can create order items
-- SECURITY: App must set correct tenant_id from subdomain detection
create policy "public_online_order_items_insert" on online_order_items 
  for insert 
  to anon
  with check (tenant_id is not null);

-- Online Order Items: Authenticated users can also create order items
create policy "public_online_order_items_insert_authenticated" on online_order_items 
  for insert 
  to authenticated
  with check (tenant_id is not null);

-- Legacy Orders: Anonymous users can create orders (if table is used for POS+online)
-- SECURITY: App must set correct tenant_id from subdomain detection
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'orders') then
    execute 'create policy "public_orders_insert" on orders for insert to anon with check (tenant_id is not null)';
  end if;
exception when duplicate_object then null;
end $$;

-- Legacy Order Items: Anonymous users can create order items
-- SECURITY: App must set correct tenant_id from subdomain detection
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'order_items') then
    execute 'create policy "public_order_items_insert" on order_items for insert to anon with check (tenant_id is not null)';
  end if;
end $$;

notify pgrst, 'reload schema';

-- ==============================================================================
-- F29 TAX DECLARATIONS & HR ENHANCEMENTS
-- ==============================================================================
-- Chilean Monthly Tax Declaration (Formulario 29) + Enhanced HR Module
-- Includes: Medical leaves (licencias médicas), payroll integration, contracts
-- Date: December 2024
-- ==============================================================================

-- ============================================================================
-- F29 TAX DECLARATIONS MODULE
-- ============================================================================

-- F29 monthly tax declarations
create table if not exists f29_declarations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  period_month integer not null check (period_month between 1 and 12),
  period_year integer not null check (period_year between 2000 and 2100),
  status text not null check (status in ('draft', 'submitted', 'paid')) default 'draft',
  
  -- IVA Section (Lines 1-43)
  iva_debito_ventas numeric(15,2) default 0, -- Line 3: Domestic sales IVA
  iva_debito_exportaciones numeric(15,2) default 0, -- Line 5: Exports (usually 0)
  iva_debito_activos_fijos numeric(15,2) default 0, -- Line 7: Fixed asset sales IVA
  iva_debito_total numeric(15,2) default 0, -- Line 15: Total IVA débito
  
  iva_credito_compras numeric(15,2) default 0, -- Line 30: Purchases IVA
  iva_credito_importaciones numeric(15,2) default 0, -- Line 31: Import IVA
  iva_credito_activos_fijos numeric(15,2) default 0, -- Line 32: Fixed asset purchases IVA
  iva_credito_total numeric(15,2) default 0, -- Line 40: Total IVA crédito
  
  iva_remanente_mes_anterior numeric(15,2) default 0, -- Line 35: Previous month credit carryover
  iva_remanente_mes_siguiente numeric(15,2) default 0, -- Line 42: Credit to carry forward
  iva_neto numeric(15,2) default 0, -- Line 43: Net IVA (débito - crédito)
  
  -- PPM Section (Lines 50-60)
  ppm_ventas_netas numeric(15,2) default 0, -- Line 50: Net sales base
  ppm_tasa_porcentaje numeric(5,2) default 1.0, -- Line 52: PPM rate (%)
  ppm_monto numeric(15,2) default 0, -- Line 54: PPM amount to pay
  ppm_remanente numeric(15,2) default 0, -- Line 56: PPM credit carryover
  
  -- Retenciones - Tax Withholdings (Lines 70-100)
  retencion_segunda_categoria numeric(15,2) default 0, -- Line 72: Employee income tax
  retencion_honorarios numeric(15,2) default 0, -- Line 74: Professional fees (10%)
  retencion_arrendamiento numeric(15,2) default 0, -- Line 76: Rental income
  
  -- Otros Impuestos - Other Taxes (Lines 110-150)
  impuesto_adicional numeric(15,2) default 0, -- Line 115: Additional tax
  impuesto_especifico numeric(15,2) default 0, -- Line 117: Specific tax
  
  -- Totals
  total_a_pagar numeric(15,2) default 0, -- Total amount to pay
  total_a_favor numeric(15,2) default 0, -- Total credit in favor
  
  -- Filing tracking
  folio_number text, -- SII confirmation folio
  filed_at timestamp with time zone,
  paid_at timestamp with time zone,
  payment_reference text,
  due_date date,
  
  -- Metadata
  notes text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  
  unique(tenant_id, period_year, period_month)
);

create index if not exists idx_f29_declarations_tenant on f29_declarations(tenant_id);
create index if not exists idx_f29_declarations_period on f29_declarations(tenant_id, period_year, period_month);
create index if not exists idx_f29_declarations_status on f29_declarations(tenant_id, status);

-- Enable RLS
alter table f29_declarations enable row level security;

-- RLS Policies
drop policy if exists "f29_select" on f29_declarations;
drop policy if exists "f29_insert" on f29_declarations;
drop policy if exists "f29_update" on f29_declarations;
drop policy if exists "f29_delete" on f29_declarations;

create policy "f29_select" on f29_declarations for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "f29_insert" on f29_declarations for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "f29_update" on f29_declarations for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "f29_delete" on f29_declarations for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================================
-- F29 AUTO-GENERATION RPC FUNCTION
-- ============================================================================

create or replace function public.generate_f29_from_accounting(
  p_tenant_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_start_date date;
  v_end_date date;
  v_iva_debito numeric(15,2);
  v_iva_credito numeric(15,2);
  v_ventas_netas numeric(15,2);
  v_ppm_monto numeric(15,2);
  v_retencion_honorarios numeric(15,2);
  v_retencion_segunda numeric(15,2);
  v_iva_neto numeric(15,2);
  v_total_pagar numeric(15,2);
  v_due_date date;
  v_f29_id uuid;
begin
  -- Calculate period dates
  v_start_date := make_date(p_year, p_month, 1);
  v_end_date := (v_start_date + interval '1 month' - interval '1 day')::date;
  
  -- Due date: 12th of following month
  v_due_date := make_date(p_year, p_month, 1) + interval '1 month 12 days' - interval '1 day';
  
  -- Calculate IVA Débito (Sales tax collected) - Account 2150
  -- Sum CREDIT movements (IVA débito is a liability, increases with CREDIT)
  select coalesce(sum(jl.credit_amount - jl.debit_amount), 0)
  into v_iva_debito
  from journal_lines jl
  join journal_entries je on jl.entry_id = je.id
  join accounts a on jl.account_id = a.id
  where je.tenant_id = p_tenant_id
    and a.code = '2150'
    and je.entry_date >= v_start_date
    and je.entry_date <= v_end_date
    and je.status = 'posted';
  
  -- Calculate IVA Crédito (Purchase tax paid) - Account 2120
  -- Sum DEBIT movements (IVA crédito is an asset, increases with DEBIT)
  select coalesce(sum(jl.debit_amount - jl.credit_amount), 0)
  into v_iva_credito
  from journal_lines jl
  join journal_entries je on jl.entry_id = je.id
  join accounts a on jl.account_id = a.id
  where je.tenant_id = p_tenant_id
    and a.code = '2120'
    and je.entry_date >= v_start_date
    and je.entry_date <= v_end_date
    and je.status = 'posted';
  
  -- Calculate Net Sales (Revenue) - Account 4100
  -- Sum CREDIT movements (revenue is CREDIT)
  select coalesce(sum(jl.credit_amount - jl.debit_amount), 0)
  into v_ventas_netas
  from journal_lines jl
  join journal_entries je on jl.entry_id = je.id
  join accounts a on jl.account_id = a.id
  where je.tenant_id = p_tenant_id
    and a.code = '4100'
    and je.entry_date >= v_start_date
    and je.entry_date <= v_end_date
    and je.status = 'posted';
  
  -- Calculate PPM (1% of net sales by default)
  -- TODO: Get tenant-specific PPM rate from settings
  v_ppm_monto := v_ventas_netas * 0.01;
  
  -- Calculate withholdings (if HR module tracks this)
  -- TODO: Query payroll/honorarios tables when implemented
  v_retencion_honorarios := 0;
  v_retencion_segunda := 0;
  
  -- Calculate net IVA (positive = owe to SII, negative = SII owes us)
  v_iva_neto := v_iva_debito - v_iva_credito;
  
  -- Calculate total to pay
  v_total_pagar := greatest(v_iva_neto, 0) + v_ppm_monto + v_retencion_honorarios + v_retencion_segunda;
  
  -- Insert or update F29 declaration
  insert into f29_declarations (
    tenant_id,
    period_month,
    period_year,
    status,
    iva_debito_ventas,
    iva_debito_total,
    iva_credito_compras,
    iva_credito_total,
    iva_neto,
    ppm_ventas_netas,
    ppm_monto,
    retencion_honorarios,
    retencion_segunda_categoria,
    total_a_pagar,
    total_a_favor,
    due_date,
    updated_at
  ) values (
    p_tenant_id,
    p_month,
    p_year,
    'draft',
    v_iva_debito,
    v_iva_debito,
    v_iva_credito,
    v_iva_credito,
    v_iva_neto,
    v_ventas_netas,
    v_ppm_monto,
    v_retencion_honorarios,
    v_retencion_segunda,
    case when v_iva_neto >= 0 then v_total_pagar else 0 end,
    case when v_iva_neto < 0 then abs(v_iva_neto) else 0 end,
    v_due_date,
    now()
  )
  on conflict (tenant_id, period_year, period_month)
  do update set
    iva_debito_ventas = excluded.iva_debito_ventas,
    iva_debito_total = excluded.iva_debito_total,
    iva_credito_compras = excluded.iva_credito_compras,
    iva_credito_total = excluded.iva_credito_total,
    iva_neto = excluded.iva_neto,
    ppm_ventas_netas = excluded.ppm_ventas_netas,
    ppm_monto = excluded.ppm_monto,
    retencion_honorarios = excluded.retencion_honorarios,
    retencion_segunda_categoria = excluded.retencion_segunda_categoria,
    total_a_pagar = excluded.total_a_pagar,
    total_a_favor = excluded.total_a_favor,
    due_date = excluded.due_date,
    updated_at = now()
  returning id into v_f29_id;
  
  return jsonb_build_object(
    'success', true,
    'f29_id', v_f29_id,
    'period', format('%s/%s', p_month, p_year),
    'iva_debito', v_iva_debito,
    'iva_credito', v_iva_credito,
    'iva_neto', v_iva_neto,
    'ventas_netas', v_ventas_netas,
    'ppm_monto', v_ppm_monto,
    'total_a_pagar', v_total_pagar
  );
end;
$$;

grant execute on function public.generate_f29_from_accounting(uuid, integer, integer) to authenticated;

-- ============================================================================
-- ENHANCED HR MODULE - MEDICAL LEAVES (LICENCIAS MÉDICAS)
-- ============================================================================

-- Medical leaves (doctor notes / licencias médicas)
create table if not exists medical_leaves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid references employees(id) on delete cascade not null,
  
  -- Leave details
  leave_type text not null check (leave_type in (
    'enfermedad_comun', -- Common illness
    'accidente_trabajo', -- Work accident
    'enfermedad_profesional', -- Occupational disease
    'maternal', -- Maternity leave
    'paternal', -- Paternity leave
    'pre_post_natal' -- Pre/post natal
  )),
  
  -- Dates
  start_date date not null,
  end_date date not null,
  days_count integer generated always as (end_date - start_date + 1) stored,
  
  -- Medical certificate
  certificate_number text, -- Folio de licencia médica
  doctor_name text,
  doctor_rut text,
  issuing_institution text, -- COMPIN, IST, Mutual, etc.
  
  -- Status
  status text not null check (status in (
    'pending', -- Waiting approval
    'approved', -- Approved by COMPIN/IST
    'rejected', -- Rejected
    'paid' -- Subsidy paid
  )) default 'pending',
  
  -- Financial
  daily_subsidy_amount numeric(10,2), -- Subsidio diario
  total_subsidy_amount numeric(10,2), -- Total subsidy
  paid_by text check (paid_by in ('employer', 'mutual', 'isapre', 'fonasa')),
  paid_at timestamp with time zone,
  
  -- Attachments
  certificate_url text, -- Scanned medical certificate
  approval_url text, -- COMPIN/IST approval
  
  -- Notes
  diagnosis text,
  notes text,
  
  -- Metadata
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create index if not exists idx_medical_leaves_tenant on medical_leaves(tenant_id);
create index if not exists idx_medical_leaves_employee on medical_leaves(employee_id);
create index if not exists idx_medical_leaves_dates on medical_leaves(start_date, end_date);
create index if not exists idx_medical_leaves_status on medical_leaves(tenant_id, status);

alter table medical_leaves enable row level security;

drop policy if exists "medical_leaves_select" on medical_leaves;
drop policy if exists "medical_leaves_insert" on medical_leaves;
drop policy if exists "medical_leaves_update" on medical_leaves;
drop policy if exists "medical_leaves_delete" on medical_leaves;

create policy "medical_leaves_select" on medical_leaves for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "medical_leaves_insert" on medical_leaves for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "medical_leaves_update" on medical_leaves for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "medical_leaves_delete" on medical_leaves for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================================
-- ENHANCED EMPLOYEES TABLE (add missing Chilean labor fields)
-- ============================================================================

-- Add columns to existing employees table if not exist
alter table employees add column if not exists rut text unique;
alter table employees add column if not exists prevision text check (prevision in ('AFP Capital', 'AFP Cuprum', 'AFP Habitat', 'AFP Modelo', 'AFP PlanVital', 'AFP Provida', 'AFP Uno', 'IPS (ex INP)'));
alter table employees add column if not exists salud text check (salud in ('Fonasa A', 'Fonasa B', 'Fonasa C', 'Fonasa D', 'Isapre Banmédica', 'Isapre Consalud', 'Isapre Cruz Blanca', 'Isapre Colmena', 'Isapre Nueva Masvida', 'Isapre Vida Tres'));
alter table employees add column if not exists afp_commission numeric(5,2) default 1.16; -- Comisión AFP (%)
alter table employees add column if not exists health_plan_pesos numeric(10,2); -- Plan de salud en pesos
alter table employees add column if not exists health_plan_uf numeric(5,2); -- Plan de salud en UF
alter table employees add column if not exists seguro_cesantia boolean default true; -- Unemployment insurance
alter table employees add column if not exists salary_type text check (salary_type in ('monthly', 'hourly', 'daily')) default 'monthly';
alter table employees add column if not exists base_salary numeric(12,2) not null default 0;
alter table employees add column if not exists mobility_allowance numeric(10,2) default 0; -- Asignación de movilización
alter table employees add column if not exists lunch_allowance numeric(10,2) default 0; -- Asignación de colación
alter table employees add column if not exists housing_allowance numeric(10,2) default 0; -- Asignación de casa
alter table employees add column if not exists bonus_amount numeric(10,2) default 0; -- Bonos
alter table employees add column if not exists bank_name text;
alter table employees add column if not exists bank_account_type text check (bank_account_type in ('Cuenta Corriente', 'Cuenta Vista', 'Cuenta de Ahorro'));
alter table employees add column if not exists bank_account_number text;
alter table employees add column if not exists emergency_contact_name text;
alter table employees add column if not exists emergency_contact_phone text;
alter table employees add column if not exists nationality text default 'Chilena';
alter table employees add column if not exists marital_status text check (marital_status in ('Soltero/a', 'Casado/a', 'Divorciado/a', 'Viudo/a', 'Conviviente Civil'));
alter table employees add column if not exists dependents_count integer default 0; -- Cargas familiares
alter table employees add column if not exists education_level text;
alter table employees add column if not exists blood_type text;

-- ============================================================================
-- CONTRACTS TABLE (if not exists, create it)
-- ============================================================================

create table if not exists employment_contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid references employees(id) on delete cascade not null,
  
  -- Contract type
  contract_type text not null check (contract_type in (
    'indefinido', -- Indefinite term
    'plazo_fijo', -- Fixed term
    'obra_faena', -- Specific work/project
    'part_time', -- Part-time
    'honorarios' -- Contractor (not employee)
  )),
  
  -- Contract period
  start_date date not null,
  end_date date, -- NULL for indefinite contracts
  
  -- Position
  position_title text not null,
  department text,
  job_description text,
  
  -- Schedule
  weekly_hours integer default 45, -- Hours per week
  work_schedule text, -- e.g., "Lunes a Viernes 9:00-18:00"
  
  -- Compensation
  base_salary numeric(12,2) not null,
  payment_frequency text check (payment_frequency in ('monthly', 'biweekly', 'weekly')) default 'monthly',
  payment_method text check (payment_method in ('bank_transfer', 'check', 'cash')) default 'bank_transfer',
  
  -- Benefits
  includes_transportation boolean default false,
  includes_lunch boolean default false,
  includes_housing boolean default false,
  includes_health_insurance boolean default false,
  includes_life_insurance boolean default false,
  vacation_days integer default 15, -- Días de vacaciones al año
  
  -- Status
  status text not null check (status in ('active', 'terminated', 'suspended')) default 'active',
  termination_date date,
  termination_reason text,
  
  -- Documents
  contract_url text, -- Signed contract PDF
  addendum_urls jsonb, -- Array of addendum URLs
  
  -- Metadata
  notes text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create index if not exists idx_employment_contracts_tenant on employment_contracts(tenant_id);
create index if not exists idx_employment_contracts_employee on employment_contracts(employee_id);
create index if not exists idx_employment_contracts_status on employment_contracts(tenant_id, status);

alter table employment_contracts enable row level security;

drop policy if exists "employment_contracts_select" on employment_contracts;
drop policy if exists "employment_contracts_insert" on employment_contracts;
drop policy if exists "employment_contracts_update" on employment_contracts;
drop policy if exists "employment_contracts_delete" on employment_contracts;

create policy "employment_contracts_select" on employment_contracts for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "employment_contracts_insert" on employment_contracts for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "employment_contracts_update" on employment_contracts for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "employment_contracts_delete" on employment_contracts for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================================
-- PAYROLL RECORDS (LIQUIDACIONES DE SUELDO)
-- ============================================================================

create table if not exists payroll_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  employee_id uuid references employees(id) on delete cascade not null,
  
  -- Period
  period_month integer not null check (period_month between 1 and 12),
  period_year integer not null check (period_year between 2000 and 2100),
  payment_date date not null,
  
  -- Haberes (Income)
  base_salary numeric(12,2) default 0,
  overtime_hours numeric(5,2) default 0,
  overtime_amount numeric(10,2) default 0,
  bonus_amount numeric(10,2) default 0,
  commission_amount numeric(10,2) default 0,
  mobility_allowance numeric(10,2) default 0,
  lunch_allowance numeric(10,2) default 0,
  housing_allowance numeric(10,2) default 0,
  other_allowances numeric(10,2) default 0,
  total_haberes numeric(12,2) default 0,
  
  -- Descuentos Legales (Legal Deductions)
  afp_deduction numeric(10,2) default 0, -- 10% or 11.44% with commission
  health_deduction numeric(10,2) default 0, -- 7% minimum
  unemployment_deduction numeric(10,2) default 0, -- Seguro cesantía 0.6%
  income_tax numeric(10,2) default 0, -- Impuesto único segunda categoría
  total_legal_deductions numeric(12,2) default 0,
  
  -- Otros Descuentos (Other Deductions)
  loan_deduction numeric(10,2) default 0, -- Préstamos
  advance_deduction numeric(10,2) default 0, -- Anticipos
  other_deductions numeric(10,2) default 0,
  total_other_deductions numeric(12,2) default 0,
  
  -- Totals
  total_deductions numeric(12,2) default 0,
  net_salary numeric(12,2) default 0, -- Líquido a pagar
  
  -- Employer contributions (NOT deducted from employee)
  employer_prevision numeric(10,2) default 0, -- ~3%
  employer_health numeric(10,2) default 0,
  employer_unemployment numeric(10,2) default 0, -- 2.4%
  employer_mutual numeric(10,2) default 0, -- Accident insurance ~0.9%
  employer_total_cost numeric(12,2) default 0,
  
  -- Status
  status text not null check (status in ('draft', 'approved', 'paid')) default 'draft',
  paid_at timestamp with time zone,
  payment_reference text,
  
  -- Documents
  payslip_url text, -- PDF de liquidación
  
  -- Metadata
  notes text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  
  unique(tenant_id, employee_id, period_year, period_month)
);

create index if not exists idx_payroll_records_tenant on payroll_records(tenant_id);
create index if not exists idx_payroll_records_employee on payroll_records(employee_id);
create index if not exists idx_payroll_records_period on payroll_records(tenant_id, period_year, period_month);

alter table payroll_records enable row level security;

drop policy if exists "payroll_records_select" on payroll_records;
drop policy if exists "payroll_records_insert" on payroll_records;
drop policy if exists "payroll_records_update" on payroll_records;
drop policy if exists "payroll_records_delete" on payroll_records;

create policy "payroll_records_select" on payroll_records for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "payroll_records_insert" on payroll_records for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "payroll_records_update" on payroll_records for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "payroll_records_delete" on payroll_records for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================================
-- RPC: Calculate Payroll for Employee
-- ============================================================================

create or replace function public.calculate_payroll(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_employee record;
  v_base_salary numeric(12,2);
  v_total_haberes numeric(12,2);
  v_afp_deduction numeric(10,2);
  v_health_deduction numeric(10,2);
  v_unemployment_deduction numeric(10,2);
  v_income_tax numeric(10,2);
  v_total_deductions numeric(12,2);
  v_net_salary numeric(12,2);
  v_payroll_id uuid;
begin
  -- Get employee details
  select * into v_employee
  from employees
  where id = p_employee_id and tenant_id = p_tenant_id;
  
  if not found then
    return jsonb_build_object('success', false, 'error', 'Employee not found');
  end if;
  
  -- Get base salary
  v_base_salary := coalesce(v_employee.base_salary, 0);
  
  -- Calculate total haberes (income)
  v_total_haberes := v_base_salary +
                     coalesce(v_employee.mobility_allowance, 0) +
                     coalesce(v_employee.lunch_allowance, 0) +
                     coalesce(v_employee.housing_allowance, 0) +
                     coalesce(v_employee.bonus_amount, 0);
  
  -- Calculate AFP deduction (10% + commission, typically ~11.44%)
  v_afp_deduction := v_base_salary * (10.0 + coalesce(v_employee.afp_commission, 1.16)) / 100.0;
  
  -- Calculate health deduction (7% minimum or plan value)
  v_health_deduction := greatest(
    v_base_salary * 0.07, -- 7% minimum
    coalesce(v_employee.health_plan_pesos, 0)
  );
  
  -- Calculate unemployment insurance deduction (0.6%)
  v_unemployment_deduction := case 
    when v_employee.seguro_cesantia then v_base_salary * 0.006 
    else 0 
  end;
  
  -- TODO: Calculate income tax (Segunda Categoría)
  -- Requires tax brackets and tramos implementation
  v_income_tax := 0;
  
  -- Calculate total deductions
  v_total_deductions := v_afp_deduction + v_health_deduction + v_unemployment_deduction + v_income_tax;
  
  -- Calculate net salary
  v_net_salary := v_total_haberes - v_total_deductions;
  
  -- Insert or update payroll record
  insert into payroll_records (
    tenant_id,
    employee_id,
    period_month,
    period_year,
    payment_date,
    base_salary,
    mobility_allowance,
    lunch_allowance,
    housing_allowance,
    bonus_amount,
    total_haberes,
    afp_deduction,
    health_deduction,
    unemployment_deduction,
    income_tax,
    total_legal_deductions,
    total_deductions,
    net_salary,
    employer_prevision,
    employer_unemployment,
    employer_total_cost,
    status,
    updated_at
  ) values (
    p_tenant_id,
    p_employee_id,
    p_month,
    p_year,
    make_date(p_year, p_month, 1) + interval '1 month' - interval '1 day', -- Last day of month
    v_base_salary,
    coalesce(v_employee.mobility_allowance, 0),
    coalesce(v_employee.lunch_allowance, 0),
    coalesce(v_employee.housing_allowance, 0),
    coalesce(v_employee.bonus_amount, 0),
    v_total_haberes,
    v_afp_deduction,
    v_health_deduction,
    v_unemployment_deduction,
    v_income_tax,
    v_afp_deduction + v_health_deduction + v_unemployment_deduction + v_income_tax,
    v_total_deductions,
    v_net_salary,
    v_base_salary * 0.03, -- 3% employer prevision
    v_base_salary * 0.024, -- 2.4% employer unemployment
    v_base_salary * 0.0564, -- Total employer cost ~5.64%
    'draft',
    now()
  )
  on conflict (tenant_id, employee_id, period_year, period_month)
  do update set
    base_salary = excluded.base_salary,
    mobility_allowance = excluded.mobility_allowance,
    lunch_allowance = excluded.lunch_allowance,
    housing_allowance = excluded.housing_allowance,
    bonus_amount = excluded.bonus_amount,
    total_haberes = excluded.total_haberes,
    afp_deduction = excluded.afp_deduction,
    health_deduction = excluded.health_deduction,
    unemployment_deduction = excluded.unemployment_deduction,
    income_tax = excluded.income_tax,
    total_legal_deductions = excluded.total_legal_deductions,
    total_deductions = excluded.total_deductions,
    net_salary = excluded.net_salary,
    employer_prevision = excluded.employer_prevision,
    employer_unemployment = excluded.employer_unemployment,
    employer_total_cost = excluded.employer_total_cost,
    updated_at = now()
  returning id into v_payroll_id;
  
  return jsonb_build_object(
    'success', true,
    'payroll_id', v_payroll_id,
    'employee_name', v_employee.name,
    'period', format('%s/%s', p_month, p_year),
    'base_salary', v_base_salary,
    'total_haberes', v_total_haberes,
    'total_deductions', v_total_deductions,
    'net_salary', v_net_salary
  );
end;
$$;

grant execute on function public.calculate_payroll(uuid, uuid, integer, integer) to authenticated;

comment on function public.generate_f29_from_accounting is 
'Auto-generates F29 declaration from accounting data. Future enhancement: integrate with payroll_records for employee withholdings (línea 72).';

comment on table f29_declarations is 
'Chilean monthly tax declaration (Formulario 29). Integrates with accounting (IVA), HR (withholdings), and revenue data.';

--------------------------------------------------------------------------------
-- BACKUP & RESTORE FUNCTIONS
--------------------------------------------------------------------------------

-- Function: Create a full database backup for tenant
create or replace function public.create_backup(
  p_tenant_id uuid,
  p_backup_name text,
  p_backup_type text default 'manual',
  p_notes text default null
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_backup_id uuid;
  v_backup_data jsonb;
  v_summary jsonb;
  v_product_count int;
  v_product_category_count int;
  v_customer_count int;
  v_supplier_count int;
  v_sales_invoice_count int;
  v_purchase_invoice_count int;
  v_employee_count int;
  v_journal_entry_count int;
  v_mechanic_job_count int;
  v_bike_count int;
  v_product_brand_count int;
  v_bike_brand_count int;
  v_bike_model_count int;
  v_online_order_count int;
  v_website_banner_count int;
  v_backup_size bigint;
begin
  -- Collect summary statistics
  select count(*) into v_product_count from products where tenant_id = p_tenant_id;
  select count(*) into v_product_category_count from product_categories where tenant_id = p_tenant_id;
  select count(*) into v_customer_count from customers where tenant_id = p_tenant_id;
  select count(*) into v_supplier_count from suppliers where tenant_id = p_tenant_id;
  select count(*) into v_sales_invoice_count from sales_invoices where tenant_id = p_tenant_id;
  select count(*) into v_purchase_invoice_count from purchase_invoices where tenant_id = p_tenant_id;
  select count(*) into v_employee_count from employees where tenant_id = p_tenant_id;
  select count(*) into v_journal_entry_count from journal_entries where tenant_id = p_tenant_id;
  select count(*) into v_mechanic_job_count from mechanic_jobs where tenant_id = p_tenant_id;
  select count(*) into v_bike_count from bikes where tenant_id = p_tenant_id;
  select count(*) into v_product_brand_count from product_brands where tenant_id = p_tenant_id;
  select count(*) into v_bike_brand_count from bike_brands where tenant_id = p_tenant_id;
  select count(*) into v_bike_model_count from bike_models where tenant_id = p_tenant_id;
  select count(*) into v_online_order_count from online_orders where tenant_id = p_tenant_id;
  select count(*) into v_website_banner_count from website_banners where tenant_id = p_tenant_id;
  
  -- Build summary object
  v_summary := jsonb_build_object(
    'products', v_product_count,
    'product_categories', v_product_category_count,
    'customers', v_customer_count,
    'suppliers', v_supplier_count,
    'sales_invoices', v_sales_invoice_count,
    'purchase_invoices', v_purchase_invoice_count,
    'employees', v_employee_count,
    'journal_entries', v_journal_entry_count,
    'mechanic_jobs', v_mechanic_job_count,
    'bikes', v_bike_count,
    'product_brands', v_product_brand_count,
    'bike_brands', v_bike_brand_count,
    'bike_models', v_bike_model_count,
    'online_orders', v_online_order_count,
    'website_banners', v_website_banner_count,
    'captured_at', now()
  );
  
  -- Collect backup data (all tenant tables)
  v_backup_data := jsonb_build_object(
    'products', (select jsonb_agg(to_jsonb(t.*)) from products t where tenant_id = p_tenant_id),
    'product_categories', (select jsonb_agg(to_jsonb(t.*)) from product_categories t where tenant_id = p_tenant_id),
    'customers', (select jsonb_agg(to_jsonb(t.*)) from customers t where tenant_id = p_tenant_id),
    'suppliers', (select jsonb_agg(to_jsonb(t.*)) from suppliers t where tenant_id = p_tenant_id),
    'sales_invoices', (select jsonb_agg(to_jsonb(t.*)) from sales_invoices t where tenant_id = p_tenant_id),
    'sales_payments', (select jsonb_agg(to_jsonb(t.*)) from sales_payments t where tenant_id = p_tenant_id),
    'purchase_invoices', (select jsonb_agg(to_jsonb(t.*)) from purchase_invoices t where tenant_id = p_tenant_id),
    'purchase_payments', (select jsonb_agg(to_jsonb(t.*)) from purchase_payments t where tenant_id = p_tenant_id),
    'employees', (select jsonb_agg(to_jsonb(t.*)) from employees t where tenant_id = p_tenant_id),
    'employee_contracts', (select jsonb_agg(to_jsonb(t.*)) from employee_contracts t where tenant_id = p_tenant_id),
    'attendance_records', (select jsonb_agg(to_jsonb(t.*)) from attendance_records t where tenant_id = p_tenant_id),
    'accounts', (select jsonb_agg(to_jsonb(t.*)) from accounts t where tenant_id = p_tenant_id),
    'journal_entries', (select jsonb_agg(to_jsonb(t.*)) from journal_entries t where tenant_id = p_tenant_id),
    'journal_lines', (select jsonb_agg(to_jsonb(t.*)) from journal_lines t where entry_id in (select id from journal_entries where tenant_id = p_tenant_id)),
    'stock_movements', (select jsonb_agg(to_jsonb(t.*)) from stock_movements t where tenant_id = p_tenant_id),
    'company_settings', (select jsonb_agg(to_jsonb(t.*)) from company_settings t where tenant_id = p_tenant_id),
    'payment_methods', (select jsonb_agg(to_jsonb(t.*)) from payment_methods t where tenant_id = p_tenant_id),
    'bikes', (select jsonb_agg(to_jsonb(t.*)) from bikes t where tenant_id = p_tenant_id),
    'mechanic_jobs', (select jsonb_agg(to_jsonb(t.*)) from mechanic_jobs t where tenant_id = p_tenant_id),
    'mechanic_job_items', (select jsonb_agg(to_jsonb(t.*)) from mechanic_job_items t where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id)),
    'mechanic_job_timeline', (select jsonb_agg(to_jsonb(t.*)) from mechanic_job_timeline t where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id)),
    'product_brands', (select jsonb_agg(to_jsonb(t.*)) from product_brands t where tenant_id = p_tenant_id),
    'bike_brands', (select jsonb_agg(to_jsonb(t.*)) from bike_brands t where tenant_id = p_tenant_id),
    'bike_models', (select jsonb_agg(to_jsonb(t.*)) from bike_models t where tenant_id = p_tenant_id),
    'website_settings', (select jsonb_agg(to_jsonb(t.*)) from website_settings t where tenant_id = p_tenant_id),
    'website_banners', (select jsonb_agg(to_jsonb(t.*)) from website_banners t where tenant_id = p_tenant_id),
    'website_content', (select jsonb_agg(to_jsonb(t.*)) from website_content t where tenant_id = p_tenant_id),
    'website_blocks', (select jsonb_agg(to_jsonb(t.*)) from website_blocks t where tenant_id = p_tenant_id),
    'featured_products', (select jsonb_agg(to_jsonb(t.*)) from featured_products t where tenant_id = p_tenant_id),
    'online_orders', (select jsonb_agg(to_jsonb(t.*)) from online_orders t where tenant_id = p_tenant_id),
    'online_order_items', (select jsonb_agg(to_jsonb(t.*)) from online_order_items t where order_id in (select id from online_orders where tenant_id = p_tenant_id))
  );
  
  -- Calculate backup size
  v_backup_size := length(v_backup_data::text);
  
  -- Insert backup record
  insert into database_backups (
    tenant_id,
    backup_name,
    backup_type,
    status,
    backup_data,
    summary,
    backup_size_bytes,
    notes,
    created_by
  ) values (
    p_tenant_id,
    p_backup_name,
    p_backup_type,
    'completed',
    v_backup_data,
    v_summary,
    v_backup_size,
    p_notes,
    auth.uid()
  ) returning id into v_backup_id;
  
  return jsonb_build_object(
    'success', true,
    'backup_id', v_backup_id,
    'summary', v_summary,
    'size_mb', round((v_backup_size / 1024.0 / 1024.0)::numeric, 2)
  );
exception
  when others then
    -- Log failed backup
    insert into database_backups (
      tenant_id,
      backup_name,
      backup_type,
      status,
      backup_data,
      error_message,
      created_by
    ) values (
      p_tenant_id,
      p_backup_name,
      p_backup_type,
      'failed',
      '{}'::jsonb,
      SQLERRM,
      auth.uid()
    );
    
    return jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
end;
$$;

grant execute on function public.create_backup(uuid, text, text, text) to authenticated;

-- Function: Restore database from backup
create or replace function public.restore_backup(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_backup_data jsonb;
  v_summary jsonb;
  v_tables_restored int := 0;
  v_records_restored int := 0;
begin
  -- Get backup data
  select backup_data, summary into v_backup_data, v_summary
  from database_backups
  where id = p_backup_id and tenant_id = p_tenant_id and status = 'completed';
  
  if not found then
    return jsonb_build_object('success', false, 'error', 'Backup not found or invalid');
  end if;
  
  -- START TRANSACTION: Delete existing data and restore backup
  -- WARNING: This will delete ALL tenant data and restore from backup
  
  -- Delete existing data (in STRICT reverse dependency order)
  -- Level 5: Deepest children first
  delete from journal_lines where entry_id in (select id from journal_entries where tenant_id = p_tenant_id);
  delete from mechanic_job_items where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id);
  delete from mechanic_job_timeline where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id);
  delete from online_order_items where order_id in (select id from online_orders where tenant_id = p_tenant_id);
  delete from employee_contracts where tenant_id = p_tenant_id;
  delete from attendance_records where tenant_id = p_tenant_id;
  
  -- Level 4: Tables that reference Level 5 or standalone with FKs
  delete from journal_entries where tenant_id = p_tenant_id;
  delete from sales_payments where tenant_id = p_tenant_id;
  delete from purchase_payments where tenant_id = p_tenant_id;
  delete from mechanic_jobs where tenant_id = p_tenant_id;
  delete from bikes where tenant_id = p_tenant_id;
  delete from online_orders where tenant_id = p_tenant_id;
  delete from stock_movements where tenant_id = p_tenant_id;
  
  -- Level 3: Invoices and e-commerce content
  delete from sales_invoices where tenant_id = p_tenant_id;
  delete from purchase_invoices where tenant_id = p_tenant_id;
  delete from featured_products where tenant_id = p_tenant_id;
  delete from website_blocks where tenant_id = p_tenant_id;
  delete from website_content where tenant_id = p_tenant_id;
  delete from website_banners where tenant_id = p_tenant_id;
  delete from website_settings where tenant_id = p_tenant_id;
  delete from company_settings where tenant_id = p_tenant_id;
  
  -- Level 2: Payment methods (references accounts), then products/employees/bikes
  delete from payment_methods where tenant_id = p_tenant_id;  -- BEFORE accounts!
  delete from products where tenant_id = p_tenant_id;
  delete from employees where tenant_id = p_tenant_id;
  delete from bike_models where tenant_id = p_tenant_id;
  
  -- Level 1: Base tables (brands, categories, customers, suppliers, accounts)
  delete from accounts where tenant_id = p_tenant_id;  -- AFTER payment_methods!
  delete from product_categories where tenant_id = p_tenant_id;
  delete from product_brands where tenant_id = p_tenant_id;
  delete from bike_brands where tenant_id = p_tenant_id;
  delete from customers where tenant_id = p_tenant_id;
  delete from suppliers where tenant_id = p_tenant_id;
  
  -- Restore data from backup
  -- Product Brands (restore before products)
  if v_backup_data ? 'product_brands' and v_backup_data->'product_brands' is not null and jsonb_typeof(v_backup_data->'product_brands') = 'array' then
    insert into product_brands select * from jsonb_populate_recordset(null::product_brands, v_backup_data->'product_brands');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Product Categories (restore BEFORE products - they have FK dependency)
  if v_backup_data ? 'product_categories' and v_backup_data->'product_categories' is not null and jsonb_typeof(v_backup_data->'product_categories') = 'array' then
    insert into product_categories select * from jsonb_populate_recordset(null::product_categories, v_backup_data->'product_categories');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Products (restore AFTER categories - products reference category_id)
  if v_backup_data ? 'products' and v_backup_data->'products' is not null and jsonb_typeof(v_backup_data->'products') = 'array' then
    insert into products select * from jsonb_populate_recordset(null::products, v_backup_data->'products');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Customers
  if v_backup_data ? 'customers' and v_backup_data->'customers' is not null and jsonb_typeof(v_backup_data->'customers') = 'array' then
    insert into customers select * from jsonb_populate_recordset(null::customers, v_backup_data->'customers');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Suppliers
  if v_backup_data ? 'suppliers' and v_backup_data->'suppliers' is not null and jsonb_typeof(v_backup_data->'suppliers') = 'array' then
    insert into suppliers select * from jsonb_populate_recordset(null::suppliers, v_backup_data->'suppliers');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Sales Invoices
  if v_backup_data ? 'sales_invoices' and v_backup_data->'sales_invoices' is not null and jsonb_typeof(v_backup_data->'sales_invoices') = 'array' then
    insert into sales_invoices select * from jsonb_populate_recordset(null::sales_invoices, v_backup_data->'sales_invoices');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Sales Payments
  if v_backup_data ? 'sales_payments' and v_backup_data->'sales_payments' is not null and jsonb_typeof(v_backup_data->'sales_payments') = 'array' then
    insert into sales_payments select * from jsonb_populate_recordset(null::sales_payments, v_backup_data->'sales_payments');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Purchase Invoices
  if v_backup_data ? 'purchase_invoices' and v_backup_data->'purchase_invoices' is not null and jsonb_typeof(v_backup_data->'purchase_invoices') = 'array' then
    insert into purchase_invoices select * from jsonb_populate_recordset(null::purchase_invoices, v_backup_data->'purchase_invoices');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Purchase Payments
  if v_backup_data ? 'purchase_payments' and v_backup_data->'purchase_payments' is not null and jsonb_typeof(v_backup_data->'purchase_payments') = 'array' then
    insert into purchase_payments select * from jsonb_populate_recordset(null::purchase_payments, v_backup_data->'purchase_payments');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Employees & Contracts
  if v_backup_data ? 'employees' and v_backup_data->'employees' is not null and jsonb_typeof(v_backup_data->'employees') = 'array' then
    insert into employees select * from jsonb_populate_recordset(null::employees, v_backup_data->'employees');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  if v_backup_data ? 'employee_contracts' and v_backup_data->'employee_contracts' is not null and jsonb_typeof(v_backup_data->'employee_contracts') = 'array' then
    insert into employee_contracts select * from jsonb_populate_recordset(null::employee_contracts, v_backup_data->'employee_contracts');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Attendance
  if v_backup_data ? 'attendance_records' and v_backup_data->'attendance_records' is not null and jsonb_typeof(v_backup_data->'attendance_records') = 'array' then
    insert into attendance_records select * from jsonb_populate_recordset(null::attendance_records, v_backup_data->'attendance_records');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Accounting
  if v_backup_data ? 'accounts' and v_backup_data->'accounts' is not null and jsonb_typeof(v_backup_data->'accounts') = 'array' then
    insert into accounts select * from jsonb_populate_recordset(null::accounts, v_backup_data->'accounts');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Payment Methods (restore after accounts - they reference account_id)
  if v_backup_data ? 'payment_methods' and v_backup_data->'payment_methods' is not null and jsonb_typeof(v_backup_data->'payment_methods') = 'array' then
    insert into payment_methods select * from jsonb_populate_recordset(null::payment_methods, v_backup_data->'payment_methods');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  if v_backup_data ? 'journal_entries' and v_backup_data->'journal_entries' is not null and jsonb_typeof(v_backup_data->'journal_entries') = 'array' then
    insert into journal_entries select * from jsonb_populate_recordset(null::journal_entries, v_backup_data->'journal_entries');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  if v_backup_data ? 'journal_lines' and v_backup_data->'journal_lines' is not null and jsonb_typeof(v_backup_data->'journal_lines') = 'array' then
    insert into journal_lines select * from jsonb_populate_recordset(null::journal_lines, v_backup_data->'journal_lines');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Stock Movements
  if v_backup_data ? 'stock_movements' and v_backup_data->'stock_movements' is not null and jsonb_typeof(v_backup_data->'stock_movements') = 'array' then
    insert into stock_movements select * from jsonb_populate_recordset(null::stock_movements, v_backup_data->'stock_movements');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Bike Brands (restore before bike_models and bikes)
  if v_backup_data ? 'bike_brands' and v_backup_data->'bike_brands' is not null and jsonb_typeof(v_backup_data->'bike_brands') = 'array' then
    insert into bike_brands select * from jsonb_populate_recordset(null::bike_brands, v_backup_data->'bike_brands');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Bike Models (restore before bikes)
  if v_backup_data ? 'bike_models' and v_backup_data->'bike_models' is not null and jsonb_typeof(v_backup_data->'bike_models') = 'array' then
    insert into bike_models select * from jsonb_populate_recordset(null::bike_models, v_backup_data->'bike_models');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Bikes
  if v_backup_data ? 'bikes' and v_backup_data->'bikes' is not null and jsonb_typeof(v_backup_data->'bikes') = 'array' then
    insert into bikes select * from jsonb_populate_recordset(null::bikes, v_backup_data->'bikes');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Mechanic Jobs (Pegas)
  if v_backup_data ? 'mechanic_jobs' and v_backup_data->'mechanic_jobs' is not null and jsonb_typeof(v_backup_data->'mechanic_jobs') = 'array' then
    insert into mechanic_jobs select * from jsonb_populate_recordset(null::mechanic_jobs, v_backup_data->'mechanic_jobs');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Mechanic Job Items
  if v_backup_data ? 'mechanic_job_items' and v_backup_data->'mechanic_job_items' is not null and jsonb_typeof(v_backup_data->'mechanic_job_items') = 'array' then
    insert into mechanic_job_items select * from jsonb_populate_recordset(null::mechanic_job_items, v_backup_data->'mechanic_job_items');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Mechanic Job Timeline
  if v_backup_data ? 'mechanic_job_timeline' and v_backup_data->'mechanic_job_timeline' is not null and jsonb_typeof(v_backup_data->'mechanic_job_timeline') = 'array' then
    insert into mechanic_job_timeline select * from jsonb_populate_recordset(null::mechanic_job_timeline, v_backup_data->'mechanic_job_timeline');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Company Settings
  if v_backup_data ? 'company_settings' and v_backup_data->'company_settings' is not null and jsonb_typeof(v_backup_data->'company_settings') = 'array' then
    insert into company_settings select * from jsonb_populate_recordset(null::company_settings, v_backup_data->'company_settings');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Website Settings
  if v_backup_data ? 'website_settings' and v_backup_data->'website_settings' is not null and jsonb_typeof(v_backup_data->'website_settings') = 'array' then
    insert into website_settings select * from jsonb_populate_recordset(null::website_settings, v_backup_data->'website_settings');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Website Banners
  if v_backup_data ? 'website_banners' and v_backup_data->'website_banners' is not null and jsonb_typeof(v_backup_data->'website_banners') = 'array' then
    insert into website_banners select * from jsonb_populate_recordset(null::website_banners, v_backup_data->'website_banners');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Website Content
  if v_backup_data ? 'website_content' and v_backup_data->'website_content' is not null and jsonb_typeof(v_backup_data->'website_content') = 'array' then
    insert into website_content select * from jsonb_populate_recordset(null::website_content, v_backup_data->'website_content');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Website Blocks
  if v_backup_data ? 'website_blocks' and v_backup_data->'website_blocks' is not null and jsonb_typeof(v_backup_data->'website_blocks') = 'array' then
    insert into website_blocks select * from jsonb_populate_recordset(null::website_blocks, v_backup_data->'website_blocks');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Featured Products
  if v_backup_data ? 'featured_products' and v_backup_data->'featured_products' is not null and jsonb_typeof(v_backup_data->'featured_products') = 'array' then
    insert into featured_products select * from jsonb_populate_recordset(null::featured_products, v_backup_data->'featured_products');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Online Orders
  if v_backup_data ? 'online_orders' and v_backup_data->'online_orders' is not null and jsonb_typeof(v_backup_data->'online_orders') = 'array' then
    insert into online_orders select * from jsonb_populate_recordset(null::online_orders, v_backup_data->'online_orders');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Online Order Items
  if v_backup_data ? 'online_order_items' and v_backup_data->'online_order_items' is not null and jsonb_typeof(v_backup_data->'online_order_items') = 'array' then
    insert into online_order_items select * from jsonb_populate_recordset(null::online_order_items, v_backup_data->'online_order_items');
    v_tables_restored := v_tables_restored + 1;
  end if;
  
  -- Update backup record
  update database_backups
  set status = 'restored',
      restored_at = now(),
      restored_by = auth.uid()
  where id = p_backup_id;
  
  return jsonb_build_object(
    'success', true,
    'backup_id', p_backup_id,
    'tables_restored', v_tables_restored,
    'summary', v_summary
  );
exception
  when others then
    return jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
end;
$$;

grant execute on function public.restore_backup(uuid, uuid) to authenticated;

-- Function: Get backup summary without loading full data
create or replace function public.get_backup_summary(p_backup_id uuid)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'id', id,
    'backup_name', backup_name,
    'backup_type', backup_type,
    'status', status,
    'summary', summary,
    'size_mb', round((backup_size_bytes / 1024.0 / 1024.0)::numeric, 2),
    'created_at', created_at,
    'created_by', created_by,
    'notes', notes
  ) into v_result
  from database_backups
  where id = p_backup_id;
  
  return v_result;
end;
$$;

grant execute on function public.get_backup_summary(uuid) to authenticated;

-- Function: Delete old backups based on retention policy
create or replace function public.cleanup_old_backups(p_tenant_id uuid)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_keep_count int;
  v_auto_delete boolean;
  v_deleted_count int := 0;
  v_backup_ids uuid[];
begin
  -- Get retention settings
  select keep_last_n_backups, auto_delete_old 
  into v_keep_count, v_auto_delete
  from backup_schedules
  where tenant_id = p_tenant_id;
  
  if not found or not v_auto_delete then
    return jsonb_build_object('success', true, 'deleted_count', 0, 'message', 'Auto-delete disabled');
  end if;
  
  -- Get IDs of backups to delete (keep newest N, delete older)
  select array_agg(id) into v_backup_ids
  from (
    select id
    from database_backups
    where tenant_id = p_tenant_id
      and status = 'completed'
    order by created_at desc
    offset v_keep_count
  ) old_backups;
  
  if v_backup_ids is not null then
    delete from database_backups
    where id = any(v_backup_ids);
    
    get diagnostics v_deleted_count = row_count;
  end if;
  
  return jsonb_build_object(
    'success', true,
    'deleted_count', v_deleted_count,
    'kept_count', v_keep_count
  );
end;
$$;

grant execute on function public.cleanup_old_backups(uuid) to authenticated;

-- ============================================================
-- DOCUMENT NUMBERING SYSTEM
-- Sequential human-friendly numbers for all document types
-- ============================================================

-- Table: document_sequences
-- Stores last used number for each document type per tenant
create table if not exists document_sequences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  document_type text not null, -- 'sales_invoice', 'purchase_invoice', 'journal_entry', etc.
  last_number integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, document_type)
);

create index if not exists idx_document_sequences_tenant on document_sequences(tenant_id);

-- RLS for document_sequences
alter table document_sequences enable row level security;

drop policy if exists "document_sequences_select" on document_sequences;
drop policy if exists "document_sequences_insert" on document_sequences;
drop policy if exists "document_sequences_update" on document_sequences;

create policy "document_sequences_select" on document_sequences
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "document_sequences_insert" on document_sequences
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "document_sequences_update" on document_sequences
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

-- Function: get_next_document_number
-- Generates next sequential number for a document type
-- Format: PREFIX-NNNN (e.g., FV-0143)
create or replace function public.get_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
as $$
declare
  v_next_number integer;
  v_prefix text;
  v_formatted_number text;
begin
  -- Default prefixes if not provided
  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);
  
  -- Insert or update sequence (atomic operation)
  insert into document_sequences (tenant_id, document_type, last_number)
  values (p_tenant_id, p_document_type, 1)
  on conflict (tenant_id, document_type)
  do update set
    last_number = document_sequences.last_number + 1,
    updated_at = now()
  returning last_number into v_next_number;
  
  -- Format: PREFIX-NNNNN (e.g., FV-00143)
  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  
  return v_formatted_number;
end;
$$;

grant execute on function public.get_next_document_number(uuid, text, text) to authenticated;

-- Function: preview_next_document_number
-- Returns what the NEXT number would be, WITHOUT incrementing
-- Used for form previews - number is only "consumed" when actually saving
create or replace function public.preview_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
as $$
declare
  v_current_number integer;
  v_next_number integer;
  v_prefix text;
  v_formatted_number text;
begin
  -- Default prefixes if not provided
  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);
  
  -- Get current sequence value (or 0 if none)
  select coalesce(last_number, 0) into v_current_number
  from document_sequences
  where tenant_id = p_tenant_id and document_type = p_document_type;
  
  -- Next number is current + 1 (or 1 if no sequence exists)
  v_next_number := coalesce(v_current_number, 0) + 1;
  
  -- Format: PREFIX-NNNNN (e.g., FV-00143)
  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  
  return v_formatted_number;
end;
$$;

grant execute on function public.preview_next_document_number(uuid, text, text) to authenticated;

-- =====================================================
-- FACTORY RESET CONFIGURATIONS
-- =====================================================

-- Table: reset_configurations
-- Stores saved factory reset configurations for custom resets
create table if not exists reset_configurations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  description text,
  delete_sales boolean not null default false,
  delete_purchases boolean not null default false,
  delete_inventory boolean not null default false,
  delete_stock_movements boolean not null default false,
  delete_customers boolean not null default false,
  delete_suppliers boolean not null default false,
  delete_accounting boolean not null default false,
  delete_employees boolean not null default false,
  delete_mechanic boolean not null default false,
  delete_ecommerce boolean not null default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  unique(tenant_id, name)
);

create index if not exists idx_reset_configurations_tenant on reset_configurations(tenant_id);

-- RLS for reset_configurations
alter table reset_configurations enable row level security;

drop policy if exists "reset_configurations_select" on reset_configurations;
drop policy if exists "reset_configurations_insert" on reset_configurations;
drop policy if exists "reset_configurations_update" on reset_configurations;
drop policy if exists "reset_configurations_delete" on reset_configurations;

create policy "reset_configurations_select" on reset_configurations
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "reset_configurations_insert" on reset_configurations
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "reset_configurations_update" on reset_configurations
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "reset_configurations_delete" on reset_configurations
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================
-- DATA MIGRATION: RECALCULATE EXISTING PEGA COSTS
-- Run this once to fix pegas that already have items but show $0
-- ============================================================

do $$
declare
  v_job record;
  v_parts_cost numeric;
  v_labor_cost numeric;
  v_updated_count integer := 0;
begin
  raise notice 'Starting pega cost recalculation...';
  
  for v_job in select id, job_number from mechanic_jobs loop
    -- Calculate parts cost (products only)
    select coalesce(sum(total_price), 0)
    into v_parts_cost
    from mechanic_job_items
    where job_id = v_job.id
      and coalesce(item_type, 'product') not in ('service', 'adhoc');
    
    -- Calculate labor cost (services + ad-hoc tasks)
    select coalesce(sum(total_price), 0)
    into v_labor_cost
    from mechanic_job_items
    where job_id = v_job.id
      and coalesce(item_type, 'product') in ('service', 'adhoc');
    
    -- Update job if costs changed
    update mechanic_jobs
    set 
      parts_cost = v_parts_cost,
      labor_cost = v_labor_cost,
      total_cost = v_parts_cost + v_labor_cost,
      updated_at = now()
    where id = v_job.id
      and (parts_cost != v_parts_cost or labor_cost != v_labor_cost or total_cost != (v_parts_cost + v_labor_cost));
    
    if found then
      v_updated_count := v_updated_count + 1;
      raise notice 'Updated pega %: parts=$%, labor=$%, total=$%', 
        v_job.job_number, v_parts_cost, v_labor_cost, v_parts_cost + v_labor_cost;
    end if;
  end loop;
  
  raise notice 'Pega cost recalculation complete! Updated % pegas.', v_updated_count;
end $$;



--------------------------------------------------------------------------------
-- MESSAGING SYSTEM
--------------------------------------------------------------------------------
-- Unified messaging for internal ERP chats and customer support
-- Supports: Employee-to-employee chats, customer support tickets
-- RLS: Employees see internal + support, Customers see only their own support
--------------------------------------------------------------------------------

-- Conversations table
create table if not exists conversations (
  id uuid default gen_random_uuid() primary key,
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  type text not null check (type in ('internal', 'support')),
  title text, -- Optional title for group chats or ticket subjects
  context_type text, -- 'job', 'invoice', etc.
  context_id uuid, -- ID of the related entity
  status text default 'active' check (status in ('pending', 'active', 'resolved', 'rejected')),
  created_by uuid references auth.users(id) default auth.uid(),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  reject_reason text,
  last_message_at timestamptz default now(),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Add columns if they don't exist (for existing tables)
alter table conversations add column if not exists status text default 'active';
alter table conversations add column if not exists created_by uuid references auth.users(id) default auth.uid();
alter table conversations add column if not exists accepted_by uuid references auth.users(id);
alter table conversations add column if not exists accepted_at timestamptz;
alter table conversations add column if not exists reject_reason text;

-- Conversation participants table
create table if not exists conversation_participants (
  conversation_id uuid references public.conversations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  role text default 'member' check (role in ('admin', 'member')),
  last_read_at timestamptz default now(),
  created_at timestamptz default now(),
  primary key (conversation_id, user_id)
);

-- Messages table
create table if not exists messages (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references public.conversations(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  content text,
  type text default 'text' check (type in ('text', 'image', 'file', 'system', 'action_request')),
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

-- Conversation contexts table (multi-context support)
create table if not exists conversation_contexts (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references public.conversations(id) on delete cascade,
  context_type text not null check (context_type in ('job', 'invoice', 'bike', 'product', 'order', 'customer')),
  context_id uuid not null,
  is_primary boolean default false,
  added_by uuid references auth.users(id),
  added_at timestamptz default now(),
  tenant_id uuid references public.tenants(id) default user_tenant_id(),
  unique(conversation_id, context_type, context_id)
);

-- Indexes for performance
create index if not exists idx_conversations_tenant on public.conversations(tenant_id);
create index if not exists idx_conversations_status on public.conversations(status);
create index if not exists idx_conversations_type_status on public.conversations(type, status);
create index if not exists idx_participants_user on public.conversation_participants(user_id);
create index if not exists idx_messages_conversation on public.messages(conversation_id);
create index if not exists idx_messages_created_at on public.messages(created_at);
create index if not exists idx_conv_contexts_lookup on public.conversation_contexts(context_type, context_id);
create index if not exists idx_conv_contexts_conversation on public.conversation_contexts(conversation_id);

-- Helper function to check if user is a conversation participant
create or replace function is_conversation_participant(conv_id uuid)
returns boolean as $$
begin
  return exists (
    select 1 from public.conversation_participants
    where conversation_id = conv_id and user_id = auth.uid()
  );
end;
$$ language plpgsql stable security definer;

-- Update last_message_at trigger
create or replace function update_conversation_timestamp()
returns trigger as $$
begin
  update public.conversations
  set last_message_at = new.created_at,
      updated_at = new.created_at
  where id = new.conversation_id;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_update_conversation_timestamp on messages;
create trigger trg_update_conversation_timestamp
after insert on public.messages
for each row execute function update_conversation_timestamp();

-- Enable RLS
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.conversation_contexts enable row level security;

-- Drop existing policies to recreate them (NON-RECURSIVE VERSIONS)
drop policy if exists "Users can view conversations they participate in" on public.conversations;
drop policy if exists "Users can create conversations" on public.conversations;
drop policy if exists "Users can update their conversations" on public.conversations;
drop policy if exists "Users can view participants of their conversations" on public.conversation_participants;
drop policy if exists "Users can join conversations" on public.conversation_participants;
drop policy if exists "Users can add themselves as participants" on public.conversation_participants;
drop policy if exists "Users can view messages in their conversations" on public.messages;
drop policy if exists "Users can insert messages in their conversations" on public.messages;
drop policy if exists "Users can send messages" on public.messages;
drop policy if exists "Users can view contexts of their conversations" on public.conversation_contexts;
drop policy if exists "Participants can add contexts" on public.conversation_contexts;

-- ============================================================================
-- NON-RECURSIVE RLS POLICIES (Fixed Dec 24, 2024)
-- These policies use direct subqueries instead of is_conversation_participant()
-- to avoid infinite recursion when conversation_participants policy triggers itself
-- ============================================================================

-- CONVERSATIONS POLICIES
-- INSERT: Any authenticated user can create support conversations
create policy "Users can create conversations"
  on public.conversations for insert
  to authenticated
  with check (TRUE);  -- Simple: any authenticated user can create

-- SELECT: Creator, participants, or employees for support
create policy "Users can view conversations they participate in"
  on public.conversations for select
  to authenticated
  using (
    created_by = auth.uid()
    OR id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR (type = 'support' AND EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid()))
  );

-- UPDATE: Creator, participants, or employees
create policy "Users can update their conversations"
  on public.conversations for update
  to authenticated
  using (
    created_by = auth.uid()
    OR id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- PARTICIPANTS POLICIES (CRITICAL: must not reference itself!)
-- SELECT: Your own participations, conversations you created, or employees see all
create policy "Users can view participants of their conversations"
  on public.conversation_participants for select
  to authenticated
  using (
    user_id = auth.uid()
    OR conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- INSERT: Can add yourself, or employees can add anyone
create policy "Users can add themselves as participants"
  on public.conversation_participants for insert
  to authenticated
  with check (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- MESSAGES POLICIES
-- SELECT: Conversations you created, participate in, or employees for support
create policy "Users can view messages in their conversations"
  on public.messages for select
  to authenticated
  using (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- INSERT: Must be sender and (creator, participant, or employee)
create policy "Users can send messages"
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    AND (
      conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
      OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
    )
  );

-- CONVERSATION CONTEXTS POLICIES
create policy "Users can view contexts of their conversations"
  on public.conversation_contexts for select
  to authenticated
  using (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

create policy "Participants can add contexts"
  on public.conversation_contexts for insert
  to authenticated
  with check (
    conversation_id IN (SELECT id FROM public.conversations WHERE created_by = auth.uid())
    OR conversation_id IN (SELECT conversation_id FROM public.conversation_participants WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
  );

-- Grant permissions
grant select, insert, update on public.conversations to authenticated;
grant select, insert, update on public.conversation_participants to authenticated;
grant select, insert on public.messages to authenticated;
grant select, insert on public.conversation_contexts to authenticated;

-- Delete conversation RPC
-- Updated 2025-12-24: Fix permissions for support chats
CREATE OR REPLACE FUNCTION delete_conversation(p_conversation_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_participant BOOLEAN;
    v_is_employee BOOLEAN;
    v_user_role TEXT;
    v_chat_type TEXT;
BEGIN
    -- Get conversation details
    SELECT type INTO v_chat_type 
    FROM conversations 
    WHERE id = p_conversation_id;
    
    IF v_chat_type IS NULL THEN
        RETURN; -- Conversation does not exist
    END IF;

    -- Check if user is a participant using a more direct query
    IF EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = v_user_id
    ) THEN
        v_is_participant := true;
    ELSE
        v_is_participant := false;
    END IF;

    -- Check if user is an employee
    IF EXISTS (SELECT 1 FROM employees WHERE user_id = v_user_id) THEN
        v_is_employee := true;
    ELSE
        v_is_employee := false;
    END IF;
    
    -- AUTH LOGIC:
    -- 1. Participant can delete (Standard)
    -- 2. Employee can delete 'support' chats (Shared Inbox)
    
    END IF;

    -- Get user role
    SELECT role INTO v_user_role FROM user_profiles WHERE user_id = v_user_id;
    
    -- AUTH LOGIC:
    -- 1. Participant can delete (Standard)
    -- 2. Employee can delete 'support' chats (Shared Inbox)
    -- 3. Admins/Managers can delete any chat
    
    IF v_is_participant 
       OR (v_is_employee AND v_chat_type = 'support')
       OR (v_user_role IN ('admin', 'manager', 'owner')) THEN
        -- Allowed
        NULL;
    ELSE
        RAISE EXCEPTION 'User is not authorized to delete this conversation (Code: P0001)';
    END IF;
    
    -- DELETE OPERATIONS
    
    -- 1. Messages (Foreign Key)
    DELETE FROM messages WHERE conversation_id = p_conversation_id;
    
    -- 2. Participants
    DELETE FROM conversation_participants WHERE conversation_id = p_conversation_id;
    
    -- 3. Conversation
    DELETE FROM conversations WHERE id = p_conversation_id;
    
END;
$$;

-- RPC to allow customers (or employees) to confirm an invoice
CREATE OR REPLACE FUNCTION public.confirm_invoice_approval(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer_id uuid;
BEGIN
  -- Get invoice customer
  SELECT customer_id INTO v_customer_id
  FROM public.sales_invoices
  WHERE id = p_invoice_id;

  -- Check permissions (must be the customer or an admin/employee)
  -- Employees are checked via user_profiles usually, but here we focus on Customer approval
  IF v_customer_id != auth.uid() THEN
     -- Check if employee
     IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid()) THEN
        RAISE EXCEPTION 'Not authorized to approve this invoice';
     END IF;
  END IF;

  -- Update status
  UPDATE public.sales_invoices
  SET status = 'confirmed'
  WHERE id = p_invoice_id;
END;
$$;
-- Enable RLS on sales_invoices if not already enabled (it should be)
ALTER TABLE public.sales_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_invoice_items ENABLE ROW LEVEL SECURITY;

-- 1. Sales Invoices: Customers can view their own invoices
CREATE POLICY "Customers can view their own invoices"
ON public.sales_invoices
FOR SELECT
TO authenticated
USING (
  customer_id = auth.uid()
);

-- 2. Sales Invoices: Employees can view all (assuming user_profiles check)
CREATE POLICY "Employees can view all invoices"
ON public.sales_invoices
FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
);

-- 3. Sales Invoice Items: Customers can view items of their invoices
CREATE POLICY "Customers can view their own invoice items"
ON public.sales_invoice_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.sales_invoices i
    WHERE i.id = sales_invoice_items.invoice_id
    AND i.customer_id = auth.uid()
  )
);

-- 4. Sales Invoice Items: Employees can view all items
CREATE POLICY "Employees can view all invoice items"
ON public.sales_invoice_items
FOR SELECT
TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = auth.uid())
);
-- Secure RPC to handle action request responses (bypassing RLS for specific updates)
create or replace function public.respond_to_action_request(
  p_message_id uuid,
  p_action_type text,
  p_status text,
  p_metadata_updates jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer -- Runs with elevated privileges
as $$
declare
  v_message_exists boolean;
  v_current_metadata jsonb;
  v_new_metadata jsonb;
begin
  -- 1. Verify existence
  select exists(select 1 from public.messages where id = p_message_id)
  into v_message_exists;

  if not v_message_exists then
    raise exception 'StartChat: Message not found';
  end if;

  -- 2. Get current metadata
  select metadata into v_current_metadata
  from public.messages
  where id = p_message_id;

  -- 3. Merge updates
  -- We update status, responded_at, and any other fields provided
  v_new_metadata := v_current_metadata || 
                    jsonb_build_object(
                      'status', p_status,
                      'responded_at', now()
                    ) || p_metadata_updates;

  -- 4. Update the message
  update public.messages
  set metadata = v_new_metadata
  where id = p_message_id;

end;
$$;
-- RPC to get basic public user info (name, avatar, role) for chat participants
-- This bypasses strict RLS and table structure differences
-- IMPORTANT: Checks employees FIRST, then user_profiles+employees, then customers, then auth.users
create or replace function public.get_public_user_info(p_user_id uuid)
returns jsonb
language plpgsql
security definer -- Runs with elevated privileges
as $$
declare
  v_result jsonb;
begin
  -- 1. Try to find in employees table directly (via user_id)
  select jsonb_build_object(
    'id', user_id,
    'name', coalesce(nullif(trim(first_name || ' ' || last_name), ''), 'Soporte'),
    'avatar_url', photo_url,
    'role', 'employee'
  )
  into v_result
  from public.employees
  where user_id = p_user_id
  limit 1;

  if v_result is not null then
    return v_result;
  end if;

  -- 2. Try user_profiles joined with employees (for when employee_id is linked)
  select jsonb_build_object(
    'id', up.user_id,
    'name', coalesce(nullif(trim(e.first_name || ' ' || e.last_name), ''), 'Soporte'),
    'avatar_url', e.photo_url,
    'role', 'employee'
  )
  into v_result
  from public.user_profiles up
  inner join public.employees e on e.id = up.employee_id
  where up.user_id = p_user_id
  limit 1;

  if v_result is not null then
    return v_result;
  end if;

  -- 3. If not an employee, try customers
  select jsonb_build_object(
    'id', auth_user_id,
    'name', coalesce(name, 'Cliente'),
    'avatar_url', image_url,
    'role', 'customer'
  )
  into v_result
  from public.customers
  where auth_user_id = p_user_id
  limit 1;

  if v_result is not null then
    return v_result;
  end if;

  -- 4. Fallback: try auth.users metadata
  select jsonb_build_object(
    'id', id,
    'name', coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', split_part(email, '@', 1)),
    'avatar_url', raw_user_meta_data->>'avatar_url',
    'role', 'unknown'
  )
  into v_result
  from auth.users
  where id = p_user_id;

  return coalesce(v_result, jsonb_build_object('id', p_user_id, 'name', 'Soporte', 'avatar_url', null, 'role', 'employee'));
end;
$$;
