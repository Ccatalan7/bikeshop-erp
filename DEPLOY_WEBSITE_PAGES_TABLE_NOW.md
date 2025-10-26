# 🚀 DEPLOY WEBSITE_PAGES TABLE - FIX BLACK SCREEN

**Date:** October 26, 2025  
**Issue:** GrapesJS Editor shows black screen because `website_pages` table doesn't exist in database  
**Solution:** Deploy the complete schema to Supabase

---

## ⚠️ CRITICAL: This Must Be Done NOW

The GrapesJS editor **CANNOT WORK** until the `website_pages` table exists in Supabase.

---

## 🔧 Deployment Steps (5 minutes)

### Option 1: Deploy Complete Schema (RECOMMENDED)

This ensures everything is in sync and nothing is missing.

1. **Go to Supabase Dashboard:**
   - Open: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql

2. **Open the SQL Editor:**
   - Click "SQL Editor" in left sidebar
   - Click "+ New query"

3. **Copy Schema File:**
   - Open: `supabase/sql/core_schema.sql` (10,949 lines)
   - Select ALL (Cmd+A / Ctrl+A)
   - Copy (Cmd+C / Ctrl+C)

4. **Paste and Run:**
   - Paste into SQL Editor
   - Click "Run" (or press Cmd+Enter)
   - Wait 1-2 minutes for completion
   - You should see: "Success. No rows returned"

5. **Verify Deployment:**
   - Copy the contents of `verify_website_pages_table.sql`
   - Paste into a new SQL query
   - Click "Run"
   - Expected results:
     - Table exists: ✅ 1 row
     - RLS enabled: ✅ rowsecurity = true
     - Policies: ✅ 4 policies
     - Columns: ✅ All columns including tenant_id

---

### Option 2: Deploy Only Website Pages Table (FASTER but risky)

Only do this if you're SURE the rest of the schema is already deployed.

```sql
-- 1. Create table
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

-- 2. Create indexes
create index if not exists idx_website_pages_tenant on website_pages(tenant_id);
create index if not exists idx_website_pages_name on website_pages(tenant_id, page_name);
create index if not exists idx_website_pages_published on website_pages(tenant_id, is_published);

-- 3. Enable RLS
alter table website_pages enable row level security;

-- 4. Create RLS policies
create policy "website_pages_select" on website_pages 
  for select using (tenant_id = public.user_tenant_id());

create policy "website_pages_insert" on website_pages 
  for insert with check (tenant_id = public.user_tenant_id());

create policy "website_pages_update" on website_pages 
  for update using (tenant_id = public.user_tenant_id());

create policy "website_pages_delete" on website_pages 
  for delete using (tenant_id = public.user_tenant_id());
```

---

## ✅ Verification After Deployment

Run this in Supabase SQL Editor:

```sql
-- Check table exists
select table_name from information_schema.tables 
where table_schema = 'public' and table_name = 'website_pages';
-- Expected: 1 row

-- Check RLS enabled
select tablename, rowsecurity from pg_tables
where schemaname = 'public' and tablename = 'website_pages';
-- Expected: rowsecurity = true

-- Check policies
select policyname, cmd from pg_policies
where tablename = 'website_pages'
order by policyname;
-- Expected: 4 rows (SELECT, INSERT, UPDATE, DELETE)

-- Check columns
select column_name, data_type from information_schema.columns
where table_schema = 'public' and table_name = 'website_pages'
order by ordinal_position;
-- Expected: 9 columns including tenant_id
```

If all checks pass → ✅ Deployment successful!

---

## 🧪 Test the Fix

After deployment:

1. **Refresh the ERP web app** in your browser (hard refresh: Cmd+Shift+R / Ctrl+Shift+R)

2. **Navigate to Website module:**
   - Login to ERP
   - Click "Sitio Web" in sidebar

3. **Run the Setup Wizard:**
   - Click "Asistente de Configuración" (if not done yet)
   - Enter shop name: "Test Bike Shop"
   - Select template: "Modern Store" or "Bike Shop"
   - Click "Crear Sitio Web"
   - Wait for success message

4. **Open the Editor:**
   - Click blue "Abrir Editor" button
   - Editor should load with GrapesJS interface (NOT black screen!)
   - You should see the template HTML loaded
   - Try dragging blocks, editing text

5. **Save and Preview:**
   - Make some changes
   - Click Save button (or wait 30s for auto-save)
   - Navigate to "/tienda" route
   - Verify your changes appear correctly

---

## 🐛 Troubleshooting

### Still Black Screen After Deployment?

1. **Check browser console (F12):**
   - Look for red errors
   - Check for 404 or 500 errors
   - Check for RLS policy errors

2. **Verify table has data:**
   ```sql
   select * from website_pages limit 5;
   ```
   - If 0 rows → Run wizard again to create page

3. **Check RLS policies work:**
   ```sql
   -- Check if you can query as authenticated user
   select * from website_pages where tenant_id = auth.uid();
   ```

4. **Clear browser cache:**
   - Hard refresh (Cmd+Shift+R / Ctrl+Shift+R)
   - Or clear all cache and cookies

### Error: "No se pudo cargar el editor"?

This means `getHomePage()` is returning null. Solutions:

1. Run the wizard to create initial page
2. Check if user is logged in
3. Verify `tenant_id` is set correctly

### Error: "relation 'website_pages' does not exist"?

The table is NOT deployed. Go back to deployment steps above.

---

## 📊 What This Fixes

✅ **Black screen in GrapesJS editor** → Table exists, can query data  
✅ **"Despliegue Pendiente" forever** → Fixed by changing status to 'deployed'  
✅ **No error messages** → Added error handling with helpful messages  
✅ **Wizard saves template** → Now saves HTML/CSS to database  
✅ **Preview works** → `/tienda` route can render saved HTML  

---

## 🎯 Next Steps After Deployment

1. Test complete workflow (wizard → editor → save → preview)
2. Test with multiple tenants (verify data isolation)
3. Wire product integration (use real products in Product Card block)
4. Add more custom blocks (Services, Testimonials, Contact Form)
5. Implement page management (multiple pages beyond just "home")

---

## 📚 Reference Files

- **Schema:** `supabase/sql/core_schema.sql` (lines 8570-8589, 8724, 9967-9970)
- **Verification:** `verify_website_pages_table.sql`
- **Wizard:** `lib/modules/website/pages/website_setup_wizard_page.dart`
- **Editor:** `lib/modules/website/pages/grapesjs_editor_page_web.dart`
- **Management:** `lib/modules/website/pages/website_management_page.dart`
- **Templates:** `lib/modules/website/templates/website_templates.dart`

---

**DEPLOY NOW** → Then test → Then celebrate! 🎉
