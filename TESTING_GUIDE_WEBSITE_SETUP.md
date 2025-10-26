# 🧪 Website Setup Flow - Testing Checklist

**Date:** 2025-10-26  
**Purpose:** Step-by-step guide to test the new website deployment wizard

---

## STEP 1: Deploy Database Changes ⏳

### 1.1 Open Supabase Dashboard

1. Go to: https://supabase.com/dashboard
2. Select your project: `project-vinabike`
3. Click **SQL Editor** in left sidebar
4. Click **+ New query**

### 1.2 Run Website Columns Migration

**Copy and paste this SQL:**

Location: `supabase/sql/migrations/add_website_configuration_columns.sql`

```sql
-- Add website configuration columns
do $$ begin
  alter table company_settings add column if not exists website_enabled boolean default false;
  alter table company_settings add column if not exists website_subdomain text;
  alter table company_settings add column if not exists website_url text;
  alter table company_settings add column if not exists firebase_site_name text;
  alter table company_settings add column if not exists website_deployed_at timestamptz;
  alter table company_settings add column if not exists website_status text default 'not_configured';
  
  raise notice '✅ Website configuration columns added to company_settings';
exception
  when undefined_table then 
    raise exception '❌ Table company_settings does not exist. Run core_schema.sql first.';
  when duplicate_column then 
    raise notice '⚠️  Website columns already exist in company_settings - skipping';
end $$;

-- Add unique constraint on website_subdomain
do $$ begin
  alter table company_settings add constraint unique_website_subdomain unique(website_subdomain);
  raise notice '✅ Unique constraint added to website_subdomain';
exception
  when duplicate_table then 
    raise notice '⚠️  Unique constraint already exists - skipping';
end $$;

-- Create indexes
do $$ begin
  create index if not exists idx_company_settings_website_subdomain 
    on company_settings(website_subdomain) 
    where website_subdomain is not null;
    
  create index if not exists idx_company_settings_website_status 
    on company_settings(website_status);
  
  raise notice '✅ Indexes created';
end $$;

-- Verify
select 
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'company_settings'
  and column_name in (
    'website_enabled',
    'website_subdomain',
    'website_url',
    'firebase_site_name',
    'website_deployed_at',
    'website_status'
  )
order by column_name;
```

**Click "Run" (or Ctrl+Enter)**

### 1.3 Expected Output

You should see:
```
✅ Website configuration columns added to company_settings
✅ Unique constraint added to website_subdomain
✅ Indexes created

[Table showing 6 rows with column details]
```

**✅ If you see this, database is ready!**

---

## STEP 2: Start the Flutter App 🚀

### 2.1 Clean Build (Recommended)

```powershell
cd C:\dev\ProjectVinabike

# Clean previous build
flutter clean

# Get dependencies
flutter pub get

# Build and run on Chrome
flutter run -d chrome
```

**Wait for app to compile and open in browser...**

---

## STEP 3: Create Test Account (New Tenant) 👤

### 3.1 Sign Up as New User

1. **Click "Registrarse"** (Sign Up) in login page
2. **Fill in details:**
   - Email: `test-bikeshop@example.com`
   - Password: `Test123456!`
   - Name: `Test Bike Shop`
   - RUT: `12345678-9` (test RUT)
3. **Click "Crear Cuenta"** (Create Account)
4. **Verify email** if prompted (check console for magic link)

**✅ You should now be logged in as a new tenant**

---

## STEP 4: Navigate to Website Module 🌐

### 4.1 Open Website Module

1. In the sidebar/menu, find and click **"Website"** or **"Sitio Web"**
2. You should see the **Website Management Page**

### 4.2 What You Should See

**A BLUE BANNER at the top:**

```
┌────────────────────────────────────────────────┐
│ 🚀 ¡Despliega Tu Sitio Web!                   │
│                                                │
│ Tu tienda online aún no está configurada.     │
│ Despliégala en minutos con un dominio         │
│ gratuito .web.app                              │
│                                                │
│                 [Configurar Ahora →]           │
└────────────────────────────────────────────────┘
```

**✅ If you see this blue banner, the deployment service is working!**

---

## STEP 5: Test the Setup Wizard 🧙‍♂️

### 5.1 Click "Configurar Ahora"

Click the **[Configurar Ahora]** button in the blue banner.

**A stepper wizard should open with 4 steps.**

---

### 5.2 STEP 1: Choose Template

You should see **3 template options:**

1. **Tienda Moderna** (Modern Store) - Selected by default
2. **Bike Shop Pro** - Specialized for bike shops
3. **Minimalista** - Simple and clean

**Test:**
- ✅ Click each template card
- ✅ Verify blue border appears on selected template
- ✅ Verify checkmark (✓) appears on selected template

**Click [Continuar] to proceed**

---

### 5.3 STEP 2: Configuration

You should see a form with 3 fields:

**Test each field:**

#### Field 1: Shop Name
```
Nombre de la Tienda *
[Bike Shop Test Santiago        ]
```

- ✅ Type: `Bike Shop Test Santiago`
- ✅ Verify it's required (try leaving empty)
- ✅ Notice subdomain auto-generates below

#### Field 2: Subdomain
```
Subdominio *
[bike-shop-test-santiago         ] .web.app
```

**CRITICAL TEST: Real-time availability check**

- ✅ Notice spinner appears while checking
- ✅ Wait 1-2 seconds
- ✅ Verify green checkmark (✓) appears if available
- ✅ Try changing to: `vinabike-test-123`
- ✅ Verify availability check runs again

**Try duplicate subdomain:**
- Type: `test` (if someone already used it)
- Should show validation error if taken

#### Field 3: Description (Optional)
```
Descripción (opcional)
[Best bike shop in Santiago...   ]
```

- ✅ Type any description or leave empty
- ✅ Verify it's truly optional

**Blue info box should appear:**
```
ℹ️ Tu sitio web se desplegará en Firebase Hosting de forma 
   GRATUITA. Incluye SSL (HTTPS) automático y CDN global.
```

**Click [Continuar]**

---

### 5.4 STEP 3: Deploy Website

You should see a **summary card** showing:

```
┌────────────────────────────────────┐
│ 🏪 Nombre: Bike Shop Test Santiago│
│ 🔗 URL: https://bike-shop-test-   │
│         santiago.web.app           │
│ 🎨 Plantilla: Tienda Moderna      │
└────────────────────────────────────┘
```

**Test deployment:**

1. **Click [Desplegar Sitio Web]** button
2. **You should see:**
   - Spinner appears
   - Status text: "Iniciando despliegue..."
   - Status text: "Guardando configuración..."
   - Status text: "Solicitando despliegue..."
   - Status text: "Despliegue completado"

3. **After ~3-5 seconds, you should see:**

```
┌────────────────────────────────────────────┐
│ ✓ ¡Sitio web desplegado exitosamente!     │
│                                            │
│ Tu tienda está disponible en:              │
│ https://bike-shop-test-santiago.web.app    │
│                                            │
│         [Visitar Mi Sitio Web ↗]          │
└────────────────────────────────────────────┘
```

**✅ Database should now have status = "pending"**

**Wizard should automatically advance to Step 4**

---

### 5.5 STEP 4: Custom Domain (Optional)

You should see:

```
Dominio Personalizado (Opcional)

[www.mibikeshop.cl              ]

▼ ¿Cómo configurar mi dominio?
```

**Test:**
- ✅ Try typing a custom domain (optional)
- ✅ Expand the help section (DNS instructions)
- ✅ Verify instructions are clear

**Click [Finalizar]**

---

### 5.6 Wizard Completion

**You should see:**
- ✅ Wizard closes
- ✅ Returns to Website Management Page
- ✅ Success snackbar: "¡Configuración completada! Tu sitio web está listo."

---

## STEP 6: Verify Deployment Status Banner 🎯

### 6.1 Check Banner Changed

**BEFORE wizard:** Blue banner "🚀 ¡Despliega Tu Sitio Web!"

**AFTER wizard:** Should show **ORANGE banner:**

```
┌────────────────────────────────────────────┐
│ ⏳ Despliegue Pendiente                    │
│                                            │
│ Tu sitio web está en cola para ser        │
│ desplegado. Esto puede tomar algunos      │
│ minutos.                                   │
│                                            │
│                    [Actualizar]            │
└────────────────────────────────────────────┘
```

**✅ Orange banner = configuration saved correctly!**

### 6.2 Click [Actualizar]

Click the **[Actualizar]** button to reload status from database.

- Banner should stay orange (status still "pending")

---

## STEP 7: Verify Database Saved ✅

### 7.1 Check Supabase

Go back to **Supabase SQL Editor** and run:

```sql
select 
  tenant_id,
  key,
  value,
  website_subdomain,
  website_url,
  website_status,
  website_enabled
from company_settings
where website_subdomain is not null
order by created_at desc
limit 1;
```

**Expected output:**

```
tenant_id: [UUID]
key: website_config
value: Bike Shop Test Santiago
website_subdomain: bike-shop-test-santiago
website_url: https://bike-shop-test-santiago.web.app
website_status: pending
website_enabled: true
```

**✅ If you see this row, wizard saved data correctly!**

---

## STEP 8: Simulate Deployment (Manual) 🛠️

**NOTE:** Since automated deployment via Edge Function isn't implemented yet, we'll simulate admin deploying the website.

### 8.1 Update Status to "deployed"

In **Supabase SQL Editor**, run:

```sql
-- Find the tenant_id from previous query, then:
update company_settings
set 
  website_status = 'deployed',
  website_deployed_at = now(),
  website_url = 'https://bike-shop-test-santiago.web.app'
where website_subdomain = 'bike-shop-test-santiago'
  and key = 'website_config';

-- Verify update
select 
  website_subdomain,
  website_status,
  website_deployed_at,
  website_url
from company_settings
where website_subdomain = 'bike-shop-test-santiago';
```

**Expected output:**
```
website_status: deployed
website_deployed_at: 2025-10-26 14:30:00
website_url: https://bike-shop-test-santiago.web.app
```

---

## STEP 9: Verify Deployed Status Banner 🎉

### 9.1 Refresh Website Page

Go back to your Flutter app (Website Management Page).

**Click the [Actualizar] button** or refresh the page.

### 9.2 Banner Should Turn GREEN

```
┌────────────────────────────────────────────┐
│ ✅ Sitio Web Activo                        │
│                                            │
│ https://bike-shop-test-santiago.web.app    │
│ Desplegado: 26/10/2025 14:30              │
│                                            │
│         [Visitar ↗]  [⚙️]                  │
└────────────────────────────────────────────┘
```

**✅ Green banner = deployment successful!**

### 9.3 Test Buttons

- **Click [Visitar ↗]** - Should try to open URL in new tab
- **Click [⚙️]** - Should open wizard again (to update config)

---

## STEP 10: Test Existing Website Features 🎨

Now that deployment status is tracked, test the existing website module features still work:

### 10.1 Click "Abrir Editor" (Visual Editor)

In the **"🎨 Editor Visual"** card, click **[Abrir Editor]**

**You should see:**
- ✅ Odoo-style editor opens
- ✅ Existing website blocks load
- ✅ Can edit content
- ✅ Preview works

**This proves new deployment features don't break existing editor!**

### 10.2 Test Other Sections

Click through each management card:

- ✅ **Banners** - Opens banner management
- ✅ **Productos Destacados** - Opens featured products
- ✅ **Contenido** - Opens content management
- ✅ **Pedidos Online** - Opens orders page
- ✅ **Configuración** - Opens website settings

**All should work normally!**

---

## STEP 11: Test Multi-Tenant Isolation 🔒

### 11.1 Create Second Test Account

**Logout** and create another account:

1. Email: `second-bikeshop@example.com`
2. Password: `Test123456!`
3. Name: `Second Bike Shop`

### 11.2 Go to Website Module

Navigate to **Website** module.

**You should see:**
- ✅ Blue banner "🚀 ¡Despliega Tu Sitio Web!"
- ✅ NO mention of first tenant's website
- ✅ Completely fresh start

### 11.3 Run Wizard Again

1. Click **[Configurar Ahora]**
2. Choose template
3. Enter shop name: `Second Test Shop`
4. Subdomain: `second-test-shop` (different from first!)
5. Complete wizard

**You should see:**
- ✅ Different subdomain (no conflict)
- ✅ Orange pending banner
- ✅ First tenant's data not visible

---

## STEP 12: Verify Isolation in Database 🛡️

### 12.1 Check Both Tenants Exist

In **Supabase SQL Editor**:

```sql
select 
  cs.website_subdomain,
  cs.website_status,
  cs.value as shop_name,
  t.name as tenant_name
from company_settings cs
join tenants t on t.id = cs.tenant_id
where cs.website_subdomain is not null
order by cs.created_at;
```

**Expected output:**

```
Row 1:
  website_subdomain: bike-shop-test-santiago
  website_status: deployed
  shop_name: Bike Shop Test Santiago
  tenant_name: Test Bike Shop

Row 2:
  website_subdomain: second-test-shop
  website_status: pending
  shop_name: Second Test Shop
  tenant_name: Second Bike Shop
```

**✅ Two separate tenants with separate websites!**

### 12.2 Verify Subdomain Uniqueness

Try to create duplicate subdomain in Supabase:

```sql
-- This should FAIL with unique constraint violation
insert into company_settings (tenant_id, key, value, website_subdomain)
values (
  (select id from tenants limit 1),
  'test_duplicate',
  'test',
  'bike-shop-test-santiago'  -- Already exists!
);
```

**Expected error:**
```
ERROR: duplicate key value violates unique constraint "unique_website_subdomain"
```

**✅ Uniqueness constraint working!**

---

## ✅ TESTING COMPLETE!

### Summary of What You Tested:

1. ✅ Database migration (6 columns added)
2. ✅ Blue banner shows for unconfigured websites
3. ✅ Wizard opens with 4 steps
4. ✅ Template selection works
5. ✅ Configuration form validates
6. ✅ Subdomain availability check works
7. ✅ Deployment saves to database
8. ✅ Orange banner shows for pending status
9. ✅ Green banner shows for deployed status
10. ✅ Existing website features still work
11. ✅ Multi-tenant isolation works
12. ✅ Subdomain uniqueness enforced

---

## 🚨 Common Issues & Fixes

### Issue 1: Blue banner doesn't appear
**Fix:** Check database - website_status should be 'not_configured' or null

### Issue 2: Subdomain availability always fails
**Fix:** Check database connection, verify company_settings table exists

### Issue 3: Wizard doesn't save
**Fix:** Check browser console for errors, verify tenant_id exists in users table

### Issue 4: Existing editor broken
**Fix:** This shouldn't happen - check for compilation errors

---

## 🎯 Next Steps After Testing

Once testing is complete:

1. ✅ **Keep the test accounts** for demo purposes
2. ✅ **Document any bugs** found during testing
3. ✅ **Consider implementing** automated deployment via Supabase Edge Function
4. ✅ **Add email notifications** when deployment completes
5. ✅ **Create admin dashboard** to monitor pending deployments

---

**Happy Testing! 🚀**
