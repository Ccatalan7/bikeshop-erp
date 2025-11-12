# 🚀 QUICK START POSTER

**Print this page and tape it to your wall! Complete import system in one view.**

---

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    BIKESHOP ERP IMPORT SYSTEM v1.0                        ║
║                                                                           ║
║  3 Scripts | 3 Platforms | 1 Config File | Production-Ready ✅           ║
╚═══════════════════════════════════════════════════════════════════════════╝

┌───────────────────────────────────────────────────────────────────────────┐
│ 📋 STEP 1: SETUP (ONE-TIME)                                               │
└───────────────────────────────────────────────────────────────────────────┘

$ cd scripts/import_templates
$ cp config.template.py config.py
$ nano config.py  # Fill these:

    SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
    SUPABASE_SERVICE_ROLE_KEY = "eyJhbGci..."  ← Dashboard → Settings → API
    TENANT_ID = "uuid-here"  ← Run: SELECT id, shop_name FROM tenants;
    
    ODOO_URL = "https://your-company.odoo.com"
    ODOO_API_KEY = "your_api_key"  ← Odoo → My Profile → API Keys
    
    ZOHO_CLIENT_ID = "1000.XXXX"  ← Zoho API Console
    ZOHO_REFRESH_TOKEN = "1000.xxx.yyy"  ← OAuth flow

$ python3 config.py  # Test: should print "✅ All configurations valid!"

┌───────────────────────────────────────────────────────────────────────────┐
│ 🎯 STEP 2: CHOOSE YOUR SCRIPT                                             │
└───────────────────────────────────────────────────────────────────────────┘

┌────────────────────────┬──────────────────────────┬────────────────────────┐
│  sync_odoo_to_flutter  │  sync_zoho_to_flutter    │   sync_zoho_odoo       │
├────────────────────────┼──────────────────────────┼────────────────────────┤
│                        │                          │                        │
│  🏗️  STRUCTURE         │  📊 INVENTORY            │  🔍 COMPARE            │
│                        │                          │                        │
│  • Creates categories  │  • Updates stock         │  • Side-by-side view   │
│  • 144 with hierarchy  │  • Updates prices        │  • Find differences    │
│  • Links products      │  • Fast (no categories)  │  • Sync missing items  │
│  • First-time setup    │  • Daily updates         │  • Interactive choice  │
│                        │                          │                        │
│  Use when:             │  Use when:               │  Use when:             │
│  ☑ New tenant          │  ☑ Regular maintenance   │  ☑ Migrating systems   │
│  ☑ Fix categories      │  ☑ After stocktake       │  ☑ Audit data          │
│  ☑ New products added  │  ☑ Price changes         │  ☑ Find discrepancies  │
│                        │                          │                        │
│  Duration: ~4 min      │  Duration: ~3 min        │  Duration: ~5 min      │
│  (1,440 products)      │  (1,440 products)        │  (comparison)          │
│                        │                          │                        │
└────────────────────────┴──────────────────────────┴────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│ ▶️  STEP 3: RUN THE SCRIPT                                                 │
└───────────────────────────────────────────────────────────────────────────┘

$ python3 sync_odoo_to_flutter.py

Expected output:

    🔄 ODOO → FLUTTER SYNC
    ════════════════════════════════
    
    1️⃣ Connecting to Supabase...
       ✅ Connected! Found 1440 products
    
    2️⃣ Fetching categories from Odoo...
       ✅ Found 144 categories
    
    3️⃣ Creating hierarchy...
       ➕ Created: Accesorios (level 0)
       ➕ Created: Accesorios / Asientos (level 1)
       ...
       ✅ Total: 144 categories
    
    4️⃣ Updating products...
       Progress: 500/1440 (34.7%)
       Progress: 1000/1440 (69.4%)
       Progress: 1440/1440 (100.0%)
       ✅ Updated: 1191 products
    
    ✅ SYNC COMPLETE!
    ════════════════════════════════
    Categories: 144
    Products: 1191/1440 (82.7%)

┌───────────────────────────────────────────────────────────────────────────┐
│ ✅ STEP 4: VERIFY                                                          │
└───────────────────────────────────────────────────────────────────────────┘

In Supabase SQL Editor:

    -- Count categories
    SELECT COUNT(*) FROM product_categories WHERE tenant_id = 'YOUR_TENANT_ID';
    -- Expected: 144
    
    -- Count products with categories
    SELECT COUNT(*) FROM products 
    WHERE tenant_id = 'YOUR_TENANT_ID' AND category_id IS NOT NULL;
    -- Expected: ~1,191 (82.7%)
    
    -- View hierarchy
    SELECT level, name, full_path FROM product_categories 
    WHERE tenant_id = 'YOUR_TENANT_ID' 
    ORDER BY level, name LIMIT 10;

In Flutter App:

    ☑ Open Products module
    ☑ Check category filter works
    ☑ Open random product
    ☑ Verify category appears
    ☑ Check stock quantity (if ran Zoho sync)

╔═══════════════════════════════════════════════════════════════════════════╗
║ 🔥 COMMON WORKFLOWS                                                       ║
╚═══════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────┐
│ 🆕 FRESH SETUP (New Tenant)                                     │
├─────────────────────────────────────────────────────────────────┤
│ $ python3 sync_odoo_to_flutter.py    # Categories + structure  │
│ $ python3 sync_zoho_to_flutter.py    # Stock + prices          │
│ → Verify in Flutter app                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 📅 WEEKLY MAINTENANCE                                           │
├─────────────────────────────────────────────────────────────────┤
│ $ python3 sync_zoho_to_flutter.py    # Update inventory        │
│ → Done! (Automate with cron job)                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 🔍 MONTHLY AUDIT                                                │
├─────────────────────────────────────────────────────────────────┤
│ $ python3 sync_zoho_odoo.py          # Find discrepancies      │
│ → Review comparison                                             │
│ → Choose sync direction                                         │
│ → Re-run Flutter sync if needed                                 │
└─────────────────────────────────────────────────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════╗
║ 🚨 TROUBLESHOOTING (Top 5 Errors)                                        ║
╚═══════════════════════════════════════════════════════════════════════════╝

❌ "DNS resolution failed"
   → Check SUPABASE_URL format: https://PROJECT.supabase.co
   → Run: nslookup YOUR_PROJECT.supabase.co

❌ "Authentication failed"
   → Use SERVICE_ROLE key, not anon key
   → For Odoo: Use API key, not password

❌ "Returned 0 products"
   → Check TENANT_ID is correct
   → Run: SELECT id, shop_name FROM tenants;

❌ "Invalid number format"
   → Chilean format? Use parse_chilean_number()
   → "1.500,00" → 1500.0

❌ "Missing categories"
   → Fetch ALL categories, not just assigned ones
   → Use empty filter: [[]] in Odoo query

🔧 Full flowcharts → TROUBLESHOOTING_FLOWCHART.md

╔═══════════════════════════════════════════════════════════════════════════╗
║ 📚 DOCUMENTATION QUICK LINKS                                              ║
╚═══════════════════════════════════════════════════════════════════════════╝

📖 README.md                        Complete technical documentation
🤖 AI_AGENT_GUIDE.md               Quick start for AI agents (4 steps)
✅ CHECKLIST.md                     Pre/post-sync verification
📊 SCRIPT_SELECTION_GUIDE.md       Which script for which use case
🔧 TROUBLESHOOTING_FLOWCHART.md    Visual error resolution
🏗️ ARCHITECTURE.md                 System diagrams & data flow
📦 PACKAGE_SUMMARY.md              Overview & statistics
📄 INDEX.md                        Master index (start here)

╔═══════════════════════════════════════════════════════════════════════════╗
║ 📊 PRODUCTION STATS (Vinabike)                                            ║
╚═══════════════════════════════════════════════════════════════════════════╝

✅ Products synced: 1,440
✅ Categories created: 144 (with hierarchy)
✅ Products categorized: 1,191 (82.7%)
✅ Success rate: 99.9%
✅ Average duration: 3-4 minutes per script
✅ Zero data leaks (multi-tenant safe)

╔═══════════════════════════════════════════════════════════════════════════╗
║ 🎯 QUICK DECISION MATRIX                                                  ║
╚═══════════════════════════════════════════════════════════════════════════╝

NEED CATEGORIES? → sync_odoo_to_flutter.py
NEED STOCK/PRICES? → sync_zoho_to_flutter.py
NEED TO COMPARE? → sync_zoho_odoo.py
FIRST-TIME SETUP? → Both Odoo + Zoho scripts
REGULAR UPDATES? → Only Zoho script
MIGRATING SYSTEMS? → Comparison script first

╔═══════════════════════════════════════════════════════════════════════════╗
║ 🔗 AUTOMATION (Cron Job Example)                                          ║
╚═══════════════════════════════════════════════════════════════════════════╝

# Daily stock update at 6 AM
0 6 * * * cd /path/to/scripts/import_templates && \
          python3 sync_zoho_to_flutter.py >> /var/log/sync.log 2>&1

# Weekly reconciliation on Fridays at 11 PM
0 23 * * 5 cd /path/to/scripts/import_templates && \
           python3 sync_zoho_odoo.py >> /var/log/compare.log 2>&1

╔═══════════════════════════════════════════════════════════════════════════╗
║ 📞 HELP & SUPPORT                                                         ║
╚═══════════════════════════════════════════════════════════════════════════╝

First time using?        → AI_AGENT_GUIDE.md
Script not working?      → TROUBLESHOOTING_FLOWCHART.md
Don't know which script? → SCRIPT_SELECTION_GUIDE.md
Want technical details?  → README.md
Need visual explanation? → ARCHITECTURE.md

🎓 Complete learning path in INDEX.md (by experience level)

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║              🎉 YOU'RE READY TO IMPORT/SYNC! 🎉                          ║
║                                                                           ║
║  1. Fill config.py         ← Credentials                                 ║
║  2. Choose script          ← See decision matrix above                   ║
║  3. Run: python3 sync_*.py ← Execute                                     ║
║  4. Verify results         ← Check Flutter app + SQL                     ║
║                                                                           ║
║  Questions? Check INDEX.md → Points to right documentation               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

         Version 1.0 | Production-Ready ✅ | Tested with 1,440 Products
```

---

**💾 Save this poster as reference! All commands and workflows in one place.**

**🖨️ Print and hang near your desk for quick reference during imports.**

**📱 Keep INDEX.md bookmarked → it links to all detailed documentation.**
