# 🏗️ GRAPESJS ARCHITECTURE DIAGRAM

## Before (Broken Block System)

```
┌─────────────────────────────────────────────────────────────────┐
│                    WIZARD (Step 1-4)                            │
│  - Select "template" → FAKE (just block presets)               │
│  - Save blocks as JSON to database                             │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              ODOO-STYLE EDITOR (Block-Based)                    │
│  - Drag & drop blocks (Hero, Products, Services)               │
│  - Configure each block with forms                             │
│  - Save as JSON: {type: 'hero', data: {...}}                   │
│  - ❌ PROBLEM: Preview !== Deployed site                       │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DUAL RENDERING SYSTEM                         │
│  ┌──────────────────────────┐   ┌────────────────────────────┐ │
│  │ EDITOR PREVIEW           │   │ PUBLIC STORE (/tienda)     │ │
│  │ - Renders blocks as      │   │ - Renders blocks as        │ │
│  │   Flutter widgets        │   │   Flutter widgets          │ │
│  │ - WebsiteBlockRenderer   │   │ - PublicHomePage           │ │
│  │ - ❌ Different styling   │   │ - ❌ Different styling     │ │
│  └──────────────────────────┘   └────────────────────────────┘ │
│           ❌ NOT THE SAME OUTPUT                                │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  FIREBASE DEPLOYMENT (Fake)                     │
│  - ❌ Deployed site doesn't match preview                      │
│  - ❌ Block data doesn't convert to HTML properly              │
│  - ❌ Styling inconsistencies                                  │
│  - ❌ Users complain: "What I saw ≠ What deployed"            │
└─────────────────────────────────────────────────────────────────┘
```

---

## After (GrapesJS WYSIWYG System) ✅

```
┌─────────────────────────────────────────────────────────────────┐
│                    WIZARD (Step 1-4)                            │
│  - Select template (Modern Store, Bike Shop, Minimalist)       │
│  - Template = REAL HTML + CSS code                             │
│  - Save complete HTML/CSS to database                          │
│  ✅ What saves here === What deploys                           │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│         DATABASE (website_pages table - Supabase)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ tenant_id: "abc-123"                                      │  │
│  │ page_name: "home"                                         │  │
│  │ html_content: "<div>...</div>"  (ACTUAL HTML)             │  │
│  │ css_content: ".hero { ... }"    (ACTUAL CSS)              │  │
│  │ is_published: true                                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ✅ SINGLE SOURCE OF TRUTH                                     │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              GRAPESJS WYSIWYG EDITOR (JavaScript)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ - Loads HTML/CSS from database                            │  │
│  │ - Visual drag & drop (true WYSIWYG)                       │  │
│  │ - Custom blocks: Product Card, Service Card, Hero         │  │
│  │ - Style editor (colors, fonts, spacing)                   │  │
│  │ - Device preview (desktop, tablet, mobile)                │  │
│  │ - ✅ What you see HERE === What deploys EXACTLY           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                       Auto-save every 30s                       │
│                              ▼                                  │
│         ┌───────────────────────────────────────────┐          │
│         │ Save HTML/CSS back to database            │          │
│         │ (Update same row, same HTML/CSS columns)  │          │
│         └───────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│         PREVIEW & DEPLOYMENT (SINGLE RENDERING)                 │
│  ┌──────────────────────────┐   ┌────────────────────────────┐ │
│  │ PREVIEW (/tienda)        │   │ FIREBASE DEPLOYMENT        │ │
│  │ - Fetch HTML/CSS from DB │   │ - Fetch HTML/CSS from DB   │ │
│  │ - Render in IFrame       │   │ - Generate index.html      │ │
│  │ - NO Flutter widgets     │   │ - Deploy static HTML       │ │
│  │ - Pure HTML/CSS          │   │ - Pure HTML/CSS            │ │
│  └──────────────────────────┘   └────────────────────────────┘ │
│           ✅ IDENTICAL OUTPUT                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Comparison

### Old System (Broken):
```
Template Selection → Block JSON → Flutter Widget Renderer → Different Preview vs Deploy ❌
```

### New System (Fixed):
```
Template Selection → HTML/CSS → GrapesJS Editor → HTML/CSS → Static Renderer === Deploy ✅
```

---

## Key Architectural Differences

| Aspect | Old System ❌ | New System ✅ |
|--------|--------------|--------------|
| **Content Storage** | JSON blocks | HTML + CSS |
| **Editor** | Custom Flutter widgets | GrapesJS (industry standard) |
| **Preview Rendering** | Flutter widget tree | Static HTML in IFrame |
| **Deployed Output** | Flutter-compiled JS | Static HTML files |
| **Consistency** | Preview ≠ Deployed | Preview === Deployed |
| **WYSIWYG** | Fake (approximation) | True (exact match) |
| **Multi-Tenant** | ✅ Yes (tenant_id) | ✅ Yes (tenant_id) |
| **Customization** | Limited by blocks | Unlimited (any HTML/CSS) |
| **Professional** | ❌ No | ✅ Yes (GrapesJS standard) |

---

## Database Schema Comparison

### Old System:
```sql
create table website_blocks (
  id uuid,
  tenant_id uuid,
  block_type text,           -- 'hero', 'products', 'services'
  block_data jsonb,           -- {title: "...", subtitle: "...", ...}
  is_visible boolean,
  order_index integer
);
-- ❌ PROBLEM: JSON doesn't translate directly to deployed HTML
```

### New System:
```sql
create table website_pages (
  id uuid,
  tenant_id uuid,
  page_name text,            -- 'home', 'about', 'contact'
  html_content text,         -- <div class="hero">...</div>
  css_content text,          -- .hero { background: blue; ... }
  is_published boolean
);
-- ✅ SOLUTION: HTML/CSS IS the deployed output
```

---

## GrapesJS Integration Architecture

```
┌──────────────────────────────────────────────────────────────┐
│               Flutter Web App (ERP)                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ GrapesJSEditorPage (Flutter Widget)                    │ │
│  │  ├─ HtmlElementView (Flutter Web)                      │ │
│  │  │   └─ IFrame with GrapesJS JavaScript                │ │
│  │  │       ├─ GrapesJS CDN (v0.x.x)                      │ │
│  │  │       ├─ Custom Blocks (Product, Service, Hero)     │ │
│  │  │       ├─ Style Manager (Colors, Fonts, Spacing)     │ │
│  │  │       ├─ Device Manager (Desktop, Tablet, Mobile)   │ │
│  │  │       └─ Storage: FALSE (we use Supabase)           │ │
│  │  │                                                       │ │
│  │  │  ┌─────────────────────────────────────────────┐   │ │
│  │  │  │ PostMessage API (JS ↔ Dart)                 │   │ │
│  │  │  │  - JS: editor.getHtml() + editor.getCss()   │   │ │
│  │  │  │  - Dart: Save to Supabase via HTTP API      │   │ │
│  │  │  └─────────────────────────────────────────────┘   │ │
│  │  │                                                       │ │
│  │  ├─ Auto-save Timer (30s)                              │ │
│  │  ├─ Manual Save Button                                 │ │
│  │  └─ Preview Button → Opens /tienda                     │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                   Supabase (PostgreSQL)                      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ website_pages table                                    │ │
│  │  - tenant_id (RLS: user_tenant_id())                   │ │
│  │  - html_content (TEXT)                                 │ │
│  │  - css_content (TEXT)                                  │ │
│  │  - is_published (BOOLEAN)                              │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────┐
│              StaticHTMLHomePage (Flutter Widget)             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ HtmlElementView (IFrame with static HTML)              │ │
│  │  - Fetch HTML/CSS from Supabase                        │ │
│  │  - Render in IFrame (no Flutter widgets)              │ │
│  │  - Add <script> for interactive elements              │ │
│  │  - ✅ EXACT match to GrapesJS editor output           │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Multi-Tenant Isolation (RLS)

```sql
-- Every query automatically filters by tenant_id

-- TENANT A (BikeShop Santiago)
SELECT html_content FROM website_pages 
WHERE tenant_id = user_tenant_id();
-- Returns: <div>Bienvenidos a BikeShop Santiago...</div>

-- TENANT B (MountainBikes Valparaiso)  
SELECT html_content FROM website_pages 
WHERE tenant_id = user_tenant_id();
-- Returns: <div>Welcome to MountainBikes Valpo...</div>

-- ✅ Complete isolation - no cross-tenant data leakage
-- ✅ Same GrapesJS editor serves all tenants
-- ✅ Each tenant sees only their HTML/CSS
```

---

## Deployment Flow (Firebase Hosting)

```
┌─────────────────────────────────────────────────────────────┐
│  Admin runs: .\scripts\deploy_tenant_website.ps1           │
│  -TenantId "abc-123"                                        │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Script fetches from Supabase:                              │
│  SELECT html_content, css_content                           │
│  FROM website_pages                                         │
│  WHERE tenant_id = 'abc-123' AND page_name = 'home'        │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Generate complete index.html:                              │
│  <!DOCTYPE html>                                            │
│  <html>                                                     │
│    <head>                                                   │
│      <style>{{ css_content }}</style>                       │
│    </head>                                                  │
│    <body>                                                   │
│      {{ html_content }}                                     │
│      <script>/* Shopping cart logic */</script>             │
│    </body>                                                  │
│  </html>                                                    │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Create Firebase Hosting site:                              │
│  firebase hosting:sites:create bikeshop-santiago            │
│  firebase deploy --only hosting:bikeshop-santiago           │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  ✅ Site live at:                                           │
│  https://bikeshop-santiago.web.app                          │
│                                                              │
│  ✅ Shows EXACT HTML from GrapesJS editor                   │
│  ✅ No compilation, no transformation, pure static HTML     │
└─────────────────────────────────────────────────────────────┘
```

---

## Why This Architecture Wins

✅ **True WYSIWYG** - What you edit === What deploys (100% accuracy)  
✅ **Industry Standard** - GrapesJS is used by thousands of companies  
✅ **No Vendor Lock-in** - Static HTML can be moved to any host  
✅ **Performance** - Static HTML loads faster than Flutter-compiled JS  
✅ **SEO** - Search engines index static HTML better  
✅ **Multi-Tenant** - Complete isolation via RLS policies  
✅ **Scalable** - Same editor serves unlimited tenants  
✅ **Customizable** - Users can add any HTML/CSS they want  
✅ **Professional** - Rival any modern website builder  
✅ **Maintainable** - Fewer moving parts, simpler debugging  

---

## Summary

**Old System:** Complex, inconsistent, dual-rendering nightmare ❌  
**New System:** Simple, consistent, true WYSIWYG architecture ✅  

**The golden rule:**  
> HTML/CSS in database = HTML/CSS in editor = HTML/CSS deployed

No transformations, no conversions, no surprises. Just pure, professional website building.
