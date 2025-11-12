# 🔄 Import & Sync Templates

**AI-Friendly Import/Sync System for Multi-Platform Integration**

This directory contains ready-to-use templates for syncing data between:
- **Zoho** (Inventory/Books)
- **Odoo** (ERP)
- **Flutter App** (Supabase database)

## 🎯 For AI Agents

When a user asks to sync/import data, follow these steps:

### 1️⃣ Setup Configuration

Ask user for these credentials:

**Supabase (Required for all syncs):**
- Project URL: `https://YOUR_PROJECT.supabase.co`
- Service Role Key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`
- Tenant ID: `00000000-0000-0000-0000-000000000000`

**Zoho (If syncing from/to Zoho):**
- Client ID: `1000.XXXXXXXXXXXXXXXXXXXXXXXXXXXX`
- Client Secret: `your_client_secret_here`
- Refresh Token: `1000.xxxx.yyyy`
- Organization ID: `123456789`
- API Domain: `https://www.zohoapis.com` (or regional variant)

**Odoo (If syncing from/to Odoo):**
- URL: `https://your-company.odoo.com`
- Database name: `your-database`
- Username: `user@example.com`
- API Key: `your_api_key_here`

### 2️⃣ Create config.py

```bash
cd scripts/import_templates
cp config.template.py config.py
# Edit config.py with user's credentials
```

### 3️⃣ Run the appropriate sync script

```bash
# Odoo → Flutter
python3 sync_odoo_to_flutter.py

# Zoho → Flutter
python3 sync_zoho_to_flutter.py

# Zoho ↔ Odoo (comparison + sync)
python3 sync_zoho_odoo.py
```

---

## 📋 Available Scripts

### 1. `sync_odoo_to_flutter.py`

**What it does:**
- Fetches ALL categories from Odoo with hierarchical structure
- Creates categories in Supabase (Parent / Child / Grandchild)
- Fetches all products from Odoo
- Matches products by SKU (default_code)
- Updates product categories in Supabase

**When to use:**
- Initial import from Odoo
- Periodic category updates
- After restructuring categories in Odoo

**Output:**
```
✅ Categories created: 144
🔗 Products updated: 1191/1440
```

---

### 2. `sync_zoho_to_flutter.py`

**What it does:**
- Fetches all items from Zoho Inventory
- Handles Chilean number format (1.500,00 → 1500.00)
- Maps Zoho fields to Supabase schema
- Upserts products (update if exists, insert if new)
- Updates stock quantities

**When to use:**
- Initial product import from Zoho
- Stock quantity updates
- Syncing prices/costs from Zoho

**Zoho → Supabase Field Mapping:**
```
item_name       → name
sku             → sku
rate            → price (selling price)
purchase_rate   → cost
stock_on_hand   → stock_quantity, inventory_qty
description     → description
brand           → brand
upc             → barcode
```

---

### 3. `sync_zoho_odoo.py`

**What it does:**
- Compares products between Zoho and Odoo
- Finds products only in Zoho
- Finds products only in Odoo
- Detects differences (name, price, stock)
- Optionally creates missing products in either system

**When to use:**
- Reconciling two systems
- Migration from Zoho to Odoo (or vice versa)
- Finding data discrepancies

**Interactive prompts:**
```
1. Create missing products in Odoo from Zoho
2. Create missing products in Zoho from Odoo
3. Both (create in both systems)
4. Skip (just show comparison)
```

---

## 🔧 Configuration File

`config.template.py` contains:
- All credential placeholders
- Helper functions for API connections
- Validation logic
- Batch size and rate limiting settings

**Never commit `config.py` to git!** (It's in `.gitignore`)

---

## 📊 Data Flow Diagrams

### Odoo → Flutter
```
Odoo Categories (complete_name: "Parent / Child")
    ↓
Parse hierarchy, create parent-child relationships
    ↓
Supabase product_categories (parent_id, level, full_path)
    ↓
Match products by SKU (default_code)
    ↓
Update product.category_id
```

### Zoho → Flutter
```
Zoho Items API (item_name, sku, rate, stock_on_hand)
    ↓
Parse Chilean numbers (1.500,00 → 1500.00)
    ↓
Map fields (item_name → name, rate → price, etc.)
    ↓
Upsert to Supabase products (by SKU)
```

### Zoho ↔ Odoo
```
Fetch from both systems
    ↓
Compare by SKU
    ↓
Find: in_both, only_zoho, only_odoo
    ↓
Detect differences in common products
    ↓
User chooses sync direction
    ↓
Create missing products
```

---

## 🚨 Common Issues & Solutions

### 1. "Failed to authenticate with Odoo"
- Check API key is valid
- Verify database name matches
- Ensure API key has product.product access

### 2. "column categories.parent_id does not exist"
- Table is `product_categories`, not `categories`
- Schema should have parent_id column
- Deploy `core_schema.sql` if missing

### 3. "invalid input syntax for type integer"
- Chilean number format issue (1.500,00)
- Use `parse_chilean_number()` function
- Remove dots, replace comma with period

### 4. "division by zero" database error
- Products with cost=0 trigger calculation errors
- Import with cost=0.01 minimum
- Or handle in database trigger logic

### 5. Rate limiting errors
- Increase `RATE_LIMIT_DELAY` in config
- Reduce `BATCH_SIZE`
- Zoho: max 100 requests/minute
- Odoo: depends on hosting plan

---

## 🎨 Customization

### Adding new field mappings

Edit the `map_zoho_to_supabase()` or similar functions:

```python
def map_zoho_to_supabase(zoho_item: Dict) -> Dict:
    return {
        'tenant_id': TENANT_ID,
        'name': zoho_item.get('item_name', ''),
        'sku': zoho_item.get('sku', ''),
        # Add your custom mappings here
        'custom_field': zoho_item.get('cf_custom_field', ''),
    }
```

### Filtering products

Add filters to API queries:

```python
# Only active products
odoo_products = models.execute_kw(
    ODOO_DB, uid, ODOO_API_KEY,
    'product.product', 'search_read',
    [[['active', '=', True]]],  # Filter added here
    {'fields': ['default_code', 'name']}
)
```

### Custom sync strategies

Modify the comparison logic in `sync_zoho_odoo.py`:

```python
# Example: Only sync if price differs by more than 10%
if abs(zoho_price - odoo_price) / max(zoho_price, odoo_price, 1) > 0.10:
    diffs.append('price')
```

---

## 📚 API Documentation Links

- **Zoho Inventory API**: https://www.zoho.com/inventory/api/v1/
- **Zoho OAuth**: https://www.zoho.com/accounts/protocol/oauth.html
- **Odoo External API**: https://www.odoo.com/documentation/16.0/developer/reference/external_api.html
- **Supabase Python Client**: https://supabase.com/docs/reference/python/introduction

---

## 🛡️ Security Best Practices

1. **Never commit `config.py`** - Contains sensitive credentials
2. **Use service role key carefully** - Can bypass Row Level Security
3. **Rotate API keys regularly** - Generate new keys every 90 days
4. **Use environment variables** - For production deployments
5. **Log sensitive data carefully** - Don't log API keys/tokens
6. **Validate tenant_id** - Ensure all operations filter by tenant

---

## 🧪 Testing

Before running on production data:

```bash
# 1. Test with a single product
# Modify script to limit to 1 item:
# all_items = all_items[:1]

# 2. Use a test tenant
TENANT_ID = "test-tenant-uuid"

# 3. Dry run (print without executing)
# Comment out insert/update statements, just print data

# 4. Backup database first
# Export Supabase data or use database snapshots
```

---

## 📝 Changelog

**2025-11-11: Initial creation**
- Created config template with validation
- Added Odoo → Flutter sync (categories + products)
- Added Zoho → Flutter sync (products + stock)
- Added Zoho ↔ Odoo comparison tool
- Documented all scripts with examples

---

## 🤝 Contributing

To add a new sync template:

1. Create `sync_SOURCE_to_TARGET.py`
2. Import config and validate
3. Add docstring explaining what it does
4. Include progress indicators
5. Handle errors gracefully
6. Update this README

---

## ❓ FAQ

**Q: Can I sync customers/suppliers?**
A: Yes! Use the same pattern. Fetch from API, map fields, upsert to Supabase.

**Q: How do I handle images?**
A: Zoho/Odoo return image URLs. Store in `image_url` field. For bulk uploads, use Supabase Storage.

**Q: What about invoices/orders?**
A: Sales data requires more complex logic (line items, payments). Consider separate scripts.

**Q: Can I schedule automatic syncs?**
A: Yes! Use cron jobs or cloud functions to run scripts periodically.

**Q: What if SKUs don't match?**
A: Use fuzzy matching by name, or maintain a mapping table (source_sku → our_sku).

---

## 📞 Support

For AI agents: Reference this README when user asks about imports/syncs.

For users: Run script with `--help` flag for detailed usage instructions.

For developers: Check individual script docstrings for implementation details.

---

**Made with ❤️ for seamless multi-platform integration**
