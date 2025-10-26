# 🧪 TESTING GUIDE - GRAPESJS MIGRATION

## ✅ Pre-Deployment Checklist

Before testing, ensure:
- [ ] Database schema deployed: `supabase/sql/core_schema.sql`
- [ ] `website_pages` table exists
- [ ] RLS policies created (4 policies: SELECT, INSERT, UPDATE, DELETE)
- [ ] Flutter app compiled: `flutter build web --release`

Quick verify:
```sql
-- Check table exists
\dt website_pages

-- Check RLS enabled
SELECT tablename, rowsecurity FROM pg_tables WHERE tablename = 'website_pages';
-- Should return: website_pages | t (t = true)

-- Check policies exist
SELECT policyname FROM pg_policies WHERE tablename = 'website_pages';
-- Should return 4 rows:
-- website_pages_select
-- website_pages_insert
-- website_pages_update
-- website_pages_delete
```

---

## 🧪 Test 1: Wizard Template Selection

**Goal:** Verify template HTML/CSS saves to database

**Steps:**
1. Login to ERP
2. Navigate to **Settings → Website → Setup Wizard**
3. Select template: **"Modern Store"**
4. Enter shop name: **"Test Shop"**
5. Enter subdomain: **"test-shop-123"**
6. Click **"Desplegar Sitio Web"**

**Expected Result:**
- ✅ Success message appears
- ✅ Redirected to step 4 (deployment complete)

**Database Verification:**
```sql
SELECT 
  page_name,
  length(html_content) as html_length,
  length(css_content) as css_length,
  is_published,
  created_at
FROM website_pages
WHERE tenant_id = 'YOUR_TENANT_ID'
  AND page_name = 'home';
```

**Expected Output:**
```
page_name | html_length | css_length | is_published | created_at
----------|-------------|------------|--------------|-------------------
home      | ~5000       | ~3000      | true         | 2025-01-XX XX:XX
```

**If it fails:**
- Check RLS policies (SELECT, INSERT must allow user)
- Check `tenant_id` in user metadata: `select auth.uid(), (select raw_user_meta_data from auth.users where id = auth.uid());`
- Check Supabase logs for errors

---

## 🧪 Test 2: GrapesJS Editor Load

**Goal:** Verify editor loads template HTML/CSS

**Steps:**
1. From Website Management page, click **"Abrir Editor"**
2. Wait for GrapesJS to load (should take 2-5 seconds)

**Expected Result:**
- ✅ GrapesJS interface appears with dark theme
- ✅ Left sidebar shows blocks: "Product Card", "Service Card", "Hero Section"
- ✅ Center canvas shows template content (Modern Store HTML)
- ✅ Right sidebar shows style editor, layers, traits
- ✅ Top toolbar shows device icons (desktop, tablet, mobile)

**If editor is blank:**
- Open browser console (F12)
- Check for JavaScript errors
- Check network tab for failed CDN requests (GrapesJS library)
- Verify HTML/CSS loaded from database (check Network → XHR requests to Supabase)

**If editor shows error:**
- Check `initialHtml` and `initialCss` props passed to GrapesJSEditorPage
- Verify template HTML is valid (no unclosed tags)
- Check GrapesJS console logs in IFrame

---

## 🧪 Test 3: Visual Editing

**Goal:** Verify changes in editor are saved

**Steps:**
1. In GrapesJS editor, click on hero section text
2. Change "Welcome to Our Bike Shop" → "Bienvenidos a Mi Tienda"
3. Click a product card
4. In style editor (right sidebar), change background color to red
5. Wait 30 seconds (auto-save triggers)
6. **OR** Click manual **"Save"** button in top toolbar

**Expected Result:**
- ✅ "Saved X ago" message appears in toolbar
- ✅ No errors in browser console

**Database Verification:**
```sql
SELECT 
  substring(html_content from 1 for 200) as html_preview,
  updated_at
FROM website_pages
WHERE tenant_id = 'YOUR_TENANT_ID'
  AND page_name = 'home';
```

**Expected Output:**
- ✅ HTML contains "Bienvenidos a Mi Tienda"
- ✅ CSS contains `background-color: red` or `background: red`
- ✅ `updated_at` timestamp is recent

**If save fails:**
- Check RLS policies (UPDATE must allow user)
- Check browser console for errors
- Check PostMessage API (Dart receiving updates from JS)
- Verify Supabase API key is valid

---

## 🧪 Test 4: Preview at /tienda

**Goal:** Verify preview shows EXACT HTML from editor

**Steps:**
1. After editing in GrapesJS, click **"Preview"** button
2. New tab opens at `/tienda`
3. Verify page renders

**Expected Result:**
- ✅ Page shows "Bienvenidos a Mi Tienda" (your edited text)
- ✅ Product card has red background (your edited style)
- ✅ Same fonts, spacing, layout as in GrapesJS editor
- ✅ Responsive design works (resize browser window)

**Database Verification:**
```sql
-- Same query as test 3, should show edited content
SELECT html_content, css_content
FROM website_pages
WHERE tenant_id = 'YOUR_TENANT_ID'
  AND page_name = 'home';
```

**If preview is blank:**
- Check browser console for errors
- Verify `StaticHTMLHomePage` component loaded
- Check tenant detection (subdomain or user metadata)
- Verify HTML/CSS fetched from database (Network tab)

**If preview shows old content:**
- Clear browser cache (Ctrl+Shift+R)
- Verify database was updated (run query above)
- Check `updated_at` timestamp matches recent save

**If preview shows different content than editor:**
- ⚠️ This is the bug we fixed! Should NOT happen with new system
- Verify `/tienda` route uses `StaticHTMLHomePage`, not old `PublicHomePage`
- Check `app_router.dart` line ~168 for correct import

---

## 🧪 Test 5: Multi-Tenant Isolation

**Goal:** Verify tenants can't see each other's websites

**Prerequisites:**
- Create 2 test users in different tenants
- Run wizard for both tenants with different templates

**Steps:**
1. Login as **Tenant A** user
2. Open GrapesJS editor
3. Edit home page: "Tenant A Website"
4. Save
5. Logout
6. Login as **Tenant B** user
7. Open GrapesJS editor

**Expected Result:**
- ✅ Tenant B editor shows DIFFERENT content than Tenant A
- ✅ Tenant B cannot see Tenant A's HTML/CSS
- ✅ Preview at `/tienda` shows correct tenant's website

**Database Verification:**
```sql
-- As superuser (admin role)
SELECT 
  tenant_id,
  page_name,
  substring(html_content from 1 for 100) as content_preview
FROM website_pages
WHERE page_name = 'home'
ORDER BY tenant_id;
```

**Expected Output:**
```
tenant_id                | page_name | content_preview
------------------------|-----------|------------------------------------------
abc-123-tenant-a        | home      | ...Tenant A Website...
def-456-tenant-b        | home      | ...Tenant B Website...
```

**If tenants see each other's content:**
- ⚠️ RLS POLICY BUG - CRITICAL SECURITY ISSUE
- Check RLS policies use `user_tenant_id()` function
- Verify function returns correct tenant_id for current user
- Check policy syntax: `USING (tenant_id = public.user_tenant_id())`

---

## 🧪 Test 6: Device Responsive Preview

**Goal:** Verify responsive design works in editor and preview

**Steps:**
1. In GrapesJS editor, click **mobile icon** (top toolbar)
2. Canvas should resize to 375px width (iPhone size)
3. Verify layout adjusts (stacked columns, smaller text)
4. Click **tablet icon**
5. Canvas should resize to 768px width (iPad size)
6. Click **desktop icon**
7. Canvas returns to full width

**Expected Result:**
- ✅ Layout changes for each device
- ✅ No horizontal scrollbars on mobile
- ✅ Text is readable on all devices
- ✅ Images scale proportionally

**Preview Verification:**
1. Open `/tienda` in browser
2. Press F12 → Toggle device toolbar (Ctrl+Shift+M)
3. Select iPhone 12 Pro
4. Verify layout matches editor mobile preview
5. Select iPad
6. Verify layout matches editor tablet preview

**If responsive doesn't work:**
- Check CSS includes media queries: `@media (max-width: 768px) { ... }`
- Verify `<meta name="viewport">` tag in HTML head
- Check GrapesJS device manager configuration
- Verify templates use responsive CSS (flexbox, grid)

---

## 🧪 Test 7: Custom Blocks

**Goal:** Verify custom blocks (Product, Service, Hero) work

**Steps:**
1. In GrapesJS editor, click **"Blocks"** tab (left sidebar)
2. Find **"Product Card"** block
3. Drag onto canvas
4. Verify product card appears with placeholder image, price, button
5. Drag **"Service Card"** block
6. Drag **"Hero Section"** block
7. Click each block and edit text
8. Save

**Expected Result:**
- ✅ All 3 custom blocks appear in blocks panel
- ✅ Blocks can be dragged onto canvas
- ✅ Blocks render with correct styling
- ✅ Blocks can be edited (text, colors, images)
- ✅ Preview shows blocks correctly

**If blocks don't appear:**
- Check GrapesJS initialization code in `grapesjs_editor_page.dart`
- Verify `editor.BlockManager.add()` calls
- Check block HTML is valid
- Check block category: `category: 'Bike Shop'`

**If blocks render incorrectly:**
- Check block CSS (inline styles in block HTML)
- Verify template CSS doesn't conflict with block styles
- Check browser console for CSS errors

---

## 🧪 Test 8: Auto-Save

**Goal:** Verify auto-save works every 30 seconds

**Steps:**
1. Open GrapesJS editor
2. Make a change (edit text)
3. Wait 30 seconds without clicking save
4. Watch toolbar for "Saved X ago" message

**Expected Result:**
- ✅ After 30 seconds, "Saved just now" appears
- ✅ No errors in console
- ✅ Database `updated_at` timestamp updates

**Database Verification:**
```sql
SELECT 
  updated_at,
  now() - updated_at as time_since_save
FROM website_pages
WHERE tenant_id = 'YOUR_TENANT_ID'
  AND page_name = 'home';
```

**Expected Output:**
```
updated_at              | time_since_save
------------------------|------------------
2025-01-XX XX:XX:XX    | 00:00:05  (5 seconds ago)
```

**If auto-save doesn't work:**
- Check `_autoSaveTimer` in `grapesjs_editor_page.dart`
- Verify PostMessage API receives updates from GrapesJS
- Check `_currentHtml` and `_currentCss` are not null
- Verify `_saveToDatabase(silent: true)` is called

---

## 🧪 Test 9: Error Handling

**Goal:** Verify graceful error handling

**Test Scenario 1: No Website Configured**
1. Create new tenant (never ran wizard)
2. Try to open `/tienda`

**Expected Result:**
- ✅ Error message: "No se encontró contenido del sitio web. Configura tu sitio primero."
- ✅ Retry button appears
- ✅ No JavaScript errors

**Test Scenario 2: Invalid HTML**
1. Manually insert invalid HTML in database:
   ```sql
   UPDATE website_pages SET html_content = '<div>Unclosed tag'
   WHERE tenant_id = 'YOUR_ID';
   ```
2. Open `/tienda`

**Expected Result:**
- ⚠️ Browser may try to render (browsers are forgiving)
- ✅ GrapesJS editor should show error or warning
- ✅ No app crash

**Test Scenario 3: Network Error**
1. Open editor
2. Disconnect internet
3. Try to save

**Expected Result:**
- ✅ Error message: "Error saving: ..."
- ✅ Red snackbar appears
- ✅ User can retry after reconnecting

---

## 🧪 Test 10: Firebase Deployment (Manual)

**Goal:** Verify deployment script works (future implementation)

**Current Status:** ⚠️ Script exists but needs updating for new system

**Future Test:**
```powershell
# Update script to fetch from website_pages table
.\scripts\deploy_tenant_website.ps1 -TenantId "YOUR_TENANT_ID"
```

**Expected Result:**
- ✅ Script fetches HTML/CSS from database
- ✅ Generates index.html file
- ✅ Deploys to Firebase Hosting
- ✅ Site live at https://{subdomain}.web.app
- ✅ Deployed site shows EXACT content from editor

**This is TODO for next session!**

---

## 📊 Test Results Template

Copy this template and fill in results:

```
Test Date: ______________
Tested By: ______________
Flutter Version: ______________
Database Version: ______________

Test 1: Wizard Template Selection          [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 2: GrapesJS Editor Load               [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 3: Visual Editing                     [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 4: Preview at /tienda                 [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 5: Multi-Tenant Isolation             [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 6: Device Responsive Preview          [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 7: Custom Blocks                      [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 8: Auto-Save                          [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 9: Error Handling                     [ ] PASS  [ ] FAIL
  Notes: _________________________________

Test 10: Firebase Deployment (Manual)      [ ] PASS  [ ] FAIL
  Notes: _________________________________

Overall Status: [ ] ALL TESTS PASS  [ ] SOME FAILURES  [ ] CRITICAL BUGS

Critical Issues Found:
_________________________________
_________________________________

Next Steps:
_________________________________
_________________________________
```

---

## 🚨 Troubleshooting Common Issues

### Issue: GrapesJS doesn't load
**Symptoms:** Blank editor, no toolbars  
**Causes:**
- CDN blocked (firewall, ad blocker)
- JavaScript errors (check console)
- IFrame not registered (view factory issue)

**Fix:**
1. Check browser console for errors
2. Verify CDN accessible: https://unpkg.com/grapesjs
3. Check `ui.platformViewRegistry.registerViewFactory()` called
4. Try different browser (Chrome, Firefox)

---

### Issue: Preview shows old content
**Symptoms:** /tienda doesn't match editor  
**Causes:**
- Browser cache
- Database not updated
- Wrong route (using old PublicHomePage)

**Fix:**
1. Hard refresh: Ctrl+Shift+R
2. Verify database: `SELECT updated_at FROM website_pages WHERE ...`
3. Check router uses `StaticHTMLHomePage`, not `PublicHomePage`
4. Clear browser cache completely

---

### Issue: Save button does nothing
**Symptoms:** Click save, no confirmation  
**Causes:**
- RLS policy blocks UPDATE
- Null tenant_id
- PostMessage not working

**Fix:**
1. Check RLS: `SELECT * FROM website_pages WHERE tenant_id = user_tenant_id();`
2. Verify tenant_id: `SELECT auth.uid(), user_tenant_id();`
3. Check browser console for PostMessage errors
4. Verify `_currentHtml` and `_currentCss` not null

---

### Issue: Multi-tenant sees other tenant's site
**Symptoms:** Tenant A sees Tenant B's content  
**⚠️ CRITICAL SECURITY BUG**

**Fix:**
1. Check RLS policies: `SELECT * FROM pg_policies WHERE tablename = 'website_pages';`
2. Verify policy uses `user_tenant_id()` function
3. Test function: `SELECT user_tenant_id();` (should return current user's tenant)
4. Re-deploy RLS policies from `core_schema.sql`

---

## ✅ Success Criteria

Migration is successful if:
- ✅ All 9 tests pass (test 10 is future work)
- ✅ Editor loads and saves without errors
- ✅ Preview matches editor 100%
- ✅ Multi-tenant isolation works
- ✅ Responsive design works on all devices
- ✅ No console errors
- ✅ Database queries are fast (<100ms)

---

**Ready to test? Start with Test 1 and work your way down!** 🚀
