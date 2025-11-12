# 🤖 AI AGENT QUICK START GUIDE

**For AI Agents: How to handle import/sync requests in under 2 minutes**

---

## 📋 User Request Patterns

When user says:
- "import products from Zoho/Odoo"
- "sync categories from Odoo"
- "compare Zoho and Odoo products"
- "update stock from Zoho"

→ **You're in the right place!**

---

## ⚡ Quick Start (4 Steps)

### Step 1: Ask for Credentials

**Copy-paste this template to user:**

```
🔐 I need some credentials to set up the sync:

SUPABASE (Required):
- Project URL: https://______.supabase.co
- Service Role Key: eyJhbGci...
- Tenant ID: (Run this in Supabase SQL Editor: SELECT id, shop_name FROM tenants;)

[If syncing from ODOO]
ODOO:
- URL: https://______.odoo.com
- Database name: ______
- Username: ______@______.com
- API Key: (Odoo Settings > Users > Account Security > New API Key)

[If syncing from ZOHO]
ZOHO:
- Client ID: 1000.______
- Client Secret: ______
- Refresh Token: 1000.______.______
- Organization ID: ______
- API Domain: https://www.zohoapis.com (or .eu, .in, .au, .cn)
```

### Step 2: Create config.py

```bash
cd scripts/import_templates
cp config.template.py config.py
```

Then fill in the credentials user provided:

```python
SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = "eyJhbGci..."
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

# ... fill in Odoo/Zoho if needed
```

### Step 3: Run the script

Choose based on user's request:

```bash
# Odoo → Flutter (categories + products)
python3 sync_odoo_to_flutter.py

# Zoho → Flutter (products + stock)
python3 sync_zoho_to_flutter.py

# Zoho ↔ Odoo (compare + sync)
python3 sync_zoho_odoo.py
```

### Step 4: Report results

Parse the output and summarize for user:

```
✅ Sync complete!

Categories: 144 created
Products: 1,191 updated with categories
Skipped: 249 (services/custom items)

Time: 3 minutes 12 seconds
```

---

## 🎯 Credential Collection Cheatsheet

| System | Where to find | What you need |
|--------|--------------|---------------|
| **Supabase** | Dashboard > Project Settings > API | URL + Service Role Key |
| **Supabase Tenant** | SQL Editor: `SELECT * FROM tenants;` | tenant.id (UUID) |
| **Odoo** | Settings > Users > Your User > Account Security | URL, DB name, Username, API Key |
| **Zoho** | https://api-console.zoho.com/ | Client ID, Secret, Refresh Token, Org ID |

---

## 🔍 Debugging Common Errors

### "config.py not found"
```bash
cd scripts/import_templates
cp config.template.py config.py
# Edit config.py with credentials
```

### "Failed to authenticate with Odoo"
- Check API key is correct
- Verify database name matches (usually company name)
- Ensure user has product access rights

### "column categories.parent_id does not exist"
- Table is `product_categories`, not `categories`
- Check if schema is deployed: `supabase/sql/core_schema.sql`

### "invalid input syntax for type integer"
- Chilean number format (1.500,00)
- Script should use `parse_chilean_number()` function

### "division by zero"
- Products with cost=0
- Import with cost=0.01 minimum
- Or update database trigger to handle edge case

---

## 📊 Expected Output Examples

### Odoo → Flutter
```
🔗 SYNCING CATEGORIES FROM ODOO TO SUPABASE
================================================================================

1️⃣ Connecting to Supabase...
   ✅ Connected (Vinabike products: 1440)

2️⃣ Fetching products from Supabase...
   ✅ Found 1440 products

3️⃣ Connecting to Odoo...
   ✅ Connected as user ID: 2

4️⃣ Fetching products with categories from Odoo...
   ✅ Fetched 1440 products

5️⃣ Fetching unique categories from Odoo...
   ✅ Fetched 144 categories

6️⃣ Creating category hierarchy in Supabase...
   ➕ Created: Accesorios (level 0)
   ➕ Created: Accesorios / Adaptadores (level 1)
   ➕ Created: Accesorios / Asientos (level 1)
   ...
   ✅ Total categories in hierarchy: 144

7️⃣ Updating products with categories...
   ✅ Updated: 1191 products
   ⏭️  Skipped: 249 products (no category match)

================================================================================
✅ SYNC COMPLETE!
================================================================================
📊 Categories created: 144
🔗 Products updated: 1191/1440
```

### Zoho → Flutter
```
🔄 ZOHO → FLUTTER SYNC
================================================================================

📊 Configuration:
   Zoho Org: 788658742
   Zoho API: https://www.zohoapis.com
   Supabase: https://xzdvtzdqjeyqxnkqprtf.supabase.co

🔗 Connecting to services...
   ✅ Supabase connected
   🔄 Getting Zoho access token...
   ✅ Zoho authenticated

📥 Fetching items from Zoho Inventory...
   Fetched page 1: 200 items
   Fetched page 2: 200 items
   ...
   ✅ Fetched 1440 items

📦 SYNCING PRODUCTS
   ✅ Inserted: 144
   ✅ Updated: 1296
   ⏭️  Skipped: 0

✅ SYNC COMPLETE!
📊 Total products in Supabase: 1440
```

### Zoho ↔ Odoo
```
🔄 ZOHO ↔ ODOO SYNC
================================================================================

📥 Fetching products from Zoho...
   ✅ Found 1440 products

📥 Fetching products from Odoo...
   ✅ Found 1440 products

🔍 COMPARING PRODUCTS
   ✅ In both systems: 1380
   📗 Only in Zoho: 30
   📘 Only in Odoo: 30
   ⚠️  Products with differences: 45

🤔 SYNC OPTIONS
1. Create missing products in Odoo from Zoho
2. Create missing products in Zoho from Odoo
3. Both (create in both systems)
4. Skip (just show comparison)

Your choice (1-4): _
```

---

## 🎨 Customization Examples

### Filtering by product type
```python
# Only sync 'product' type (not 'service')
odoo_products = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.product', 'search_read',
    [[['type', '=', 'product']]],  # Add filter here
    {'fields': ['default_code', 'name']}
)
```

### Custom field mapping
```python
def map_zoho_to_supabase(zoho_item: Dict) -> Dict:
    return {
        'tenant_id': TENANT_ID,
        'name': zoho_item.get('item_name'),
        'sku': zoho_item.get('sku'),
        # Add custom field
        'weight': zoho_item.get('weight', 0),
        'dimensions': zoho_item.get('dimensions', ''),
    }
```

### Dry run mode
```python
# Test without actually inserting/updating
DRY_RUN = True

if DRY_RUN:
    print(f"Would insert: {product_data}")
else:
    client.table("products").insert(product_data).execute()
```

---

## 🚀 Performance Tips

1. **Batch operations**: Process 100-200 items at a time
2. **Rate limiting**: Wait 0.5s between API calls
3. **Parallel fetching**: Fetch from both systems simultaneously
4. **Cache results**: Store category mappings in memory
5. **Progress indicators**: Show user script is working

---

## 🔐 Security Checklist

- [ ] config.py is in .gitignore
- [ ] Never log API keys/tokens
- [ ] Use service role key (not anon key)
- [ ] Filter all queries by tenant_id
- [ ] Validate user input
- [ ] Handle errors gracefully

---

## 📝 Script Selection Matrix

| User wants to... | Use this script |
|------------------|-----------------|
| Import categories from Odoo | `sync_odoo_to_flutter.py` |
| Import products from Odoo | `sync_odoo_to_flutter.py` |
| Update categories from Odoo | `sync_odoo_to_flutter.py` |
| Import products from Zoho | `sync_zoho_to_flutter.py` |
| Update stock from Zoho | `sync_zoho_to_flutter.py` |
| Compare Zoho vs Odoo | `sync_zoho_odoo.py` |
| Migrate from Zoho to Odoo | `sync_zoho_odoo.py` |
| Keep both in sync | `sync_zoho_odoo.py` |

---

## 💡 Pro Tips

1. **Always test with 1 product first**: Modify script to limit results
2. **Check tenant isolation**: Verify tenant_id is included in all queries
3. **Handle Chilean numbers**: Use `parse_chilean_number()` for Zoho
4. **Empty categories are fine**: Odoo has many empty placeholder categories
5. **SKU is the key**: All matching is done by SKU (default_code)
6. **Categories are hierarchical**: "Parent / Child / Grandchild" format

---

## 🎓 Learning Resources

- [Supabase Python Client Docs](https://supabase.com/docs/reference/python/introduction)
- [Odoo External API Guide](https://www.odoo.com/documentation/16.0/developer/reference/external_api.html)
- [Zoho Inventory API Docs](https://www.zoho.com/inventory/api/v1/)
- [Python XML-RPC Client](https://docs.python.org/3/library/xmlrpc.client.html)

---

## ✅ Post-Sync Checklist

After successful sync, tell user:

```
✅ Sync completed successfully!

Next steps:
1. Verify products in Flutter app
2. Check categories are displaying correctly
3. Test search and filtering by category
4. Verify stock quantities are accurate
5. Check products without categories (if any)

To re-run: python3 scripts/import_templates/sync_[source]_to_[target].py
```

---

**Remember: Always ask for credentials first, never assume!**
