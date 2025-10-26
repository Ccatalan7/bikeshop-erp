-- ============================================================================
-- WEBSITE PAGES TABLE - GrapesJS WYSIWYG Editor
-- ============================================================================
-- This migration adds the website_pages table for storing HTML/CSS content
-- created by the GrapesJS editor. This replaces the old block-based system.
-- ============================================================================

-- Create website_pages table
create table if not exists website_pages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  page_name text not null, -- 'home', 'about', 'contact', 'services', 'products', custom pages
  html_content text not null default '',
  css_content text not null default '',
  is_published boolean default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, page_name)
);

-- Create indexes
do $$ begin
  create index if not exists idx_website_pages_tenant on website_pages(tenant_id);
  create index if not exists idx_website_pages_name on website_pages(tenant_id, page_name);
  create index if not exists idx_website_pages_published on website_pages(tenant_id, is_published);
exception
  when undefined_table then raise notice '⚠ Table website_pages does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in website_pages';
end $$;

-- Enable RLS
alter table website_pages enable row level security;

-- Create RLS policies
do $$ begin
  create policy "website_pages_select" on website_pages 
    for select using (tenant_id = public.user_tenant_id());
  
  create policy "website_pages_insert" on website_pages 
    for insert with check (tenant_id = public.user_tenant_id());
  
  create policy "website_pages_update" on website_pages 
    for update using (tenant_id = public.user_tenant_id());
  
  create policy "website_pages_delete" on website_pages 
    for delete using (tenant_id = public.user_tenant_id());
  
  raise notice '✓ Created RLS policies for website_pages';
exception
  when undefined_table then raise notice '⚠ Table website_pages does not exist yet';
  when undefined_column then raise notice '⚠ Column tenant_id missing in website_pages';
  when duplicate_object then raise notice '⚠ Policies already exist for website_pages';
end $$;

-- Verify deployment
do $$ 
declare
  table_exists boolean;
  policy_count integer;
begin
  -- Check table exists
  select exists (
    select 1 from information_schema.tables 
    where table_schema = 'public' and table_name = 'website_pages'
  ) into table_exists;
  
  if table_exists then
    raise notice '✓ Table website_pages exists';
    
    -- Check RLS enabled
    if (select relrowsecurity from pg_class where relname = 'website_pages') then
      raise notice '✓ RLS enabled on website_pages';
    else
      raise warning '⚠ RLS NOT enabled on website_pages';
    end if;
    
    -- Count policies
    select count(*) into policy_count
    from pg_policies 
    where tablename = 'website_pages';
    
    raise notice '✓ % RLS policies found for website_pages', policy_count;
    
    if policy_count = 4 then
      raise notice '✅ website_pages deployment SUCCESSFUL';
    else
      raise warning '⚠ Expected 4 policies, found %', policy_count;
    end if;
  else
    raise warning '❌ Table website_pages does NOT exist';
  end if;
end $$;
