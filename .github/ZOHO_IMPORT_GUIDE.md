# 🔄 Zoho to Supabase Import System

**Complete Guide for AI-Assisted Data Migration**

> This guide documents the automated import system for migrating data from Zoho Inventory to Supabase. It serves as a reference for AI agents to perform autonomous imports with minimal user intervention.

---

## 📁 File Organization

All Zoho import scripts are located in:
```
/scripts/zoho_import/
```

**Script Structure:**
```
scripts/zoho_import/
├── zoho_to_supabase_import.py       # Main: Complete image import pipeline
├── step1_get_zoho_tokens.py         # OAuth: Exchange grant code for tokens
├── step2_download_images.py         # Legacy: Download images locally
├── refresh_zoho_token.py            # Utility: Get fresh access token
├── check_supabase_buckets.py        # Utility: Verify storage buckets
└── list_products_without_images.py  # Utility: Report unmatched products
```

**⚠️ Important:** Keep all import scripts in `scripts/zoho_import/` to maintain organization and prevent root folder clutter.

---

## 🎯 What We Accomplished: Image Import Case Study

### Problem Statement
Import product images from Zoho Inventory to Supabase Storage, matching products by SKU or name.

### Solution Components

#### 1. **OAuth Authentication** (`step1_get_zoho_tokens.py`)
- **User provides:** Client ID, Client Secret, Grant Code (expires in 10 minutes)
- **AI agent does:** Exchange grant code for access token + refresh token
- **Output:** Long-lived refresh token (used for all future requests)

#### 2. **Data Matching** (Smart SKU/Name Matching)
- Fetched 81 products from Supabase (tenant-scoped)
- Fetched 1,440 items from Zoho Inventory (paginated API)
- Matched 51 products: 49 by SKU, 2 by name fallback
- Identified 30 unmatched products (services, test data, different SKUs)

#### 3. **Image Processing** (Special Character Handling)
- Downloaded images from Zoho Documents API
- Sanitized filenames: `ó→o`, `ñ→n`, `á→a`, spaces→underscores
- Uploaded to Supabase Storage with tenant-scoped paths
- Updated product records with public image URLs

#### 4. **Error Handling & Reporting**
- Automatically retried with sanitized filenames
- Generated CSV report of unmatched products
- 100% success rate (51/51 matched products imported)

### Key Files
- **Main Script:** `zoho_to_supabase_import.py` (16KB, 358 lines)
- **Token Setup:** `step1_get_zoho_tokens.py` + `refresh_zoho_token.py`
- **Output:** `unmatched_products.csv` (products not found in Zoho)

---

## 🤖 AI Agent Workflow Pattern

### Principle: **Maximum Autonomy, Minimum User Input**

The AI agent should automate everything possible and only ask the user for information that is strictly impossible to obtain programmatically.

### What AI Agent MUST Do Automatically

#### 1. **Fetch Application Configuration**
```python
# ✅ DO: Read from existing app files
from lib/shared/config/supabase_config.dart:
  - SUPABASE_URL
  - SUPABASE_ANON_KEY

from user's Flutter/Dart code:
  - Database schema (table names, column names)
  - Model structures
  - Existing services patterns
```

**Never ask user for:** Supabase URL, database structure, table names, column types

#### 2. **Detect Data Structures**
```python
# ✅ DO: Query database to understand schema
supabase.table("products").select("*").limit(1).execute()
# Parse response to understand columns, types, relationships
```

**Never ask user for:** What columns exist, data types, relationships

#### 3. **Handle Authentication Automatically**
```python
# ✅ DO: Use refresh tokens to get access tokens
def get_access_token():
    if token_expired():
        return refresh_access_token(REFRESH_TOKEN)
    return CURRENT_ACCESS_TOKEN
```

**Never ask user for:** New access tokens (use refresh token instead)

#### 4. **Discover API Endpoints**
```python
# ✅ DO: Try common patterns, iterate on failures
endpoints = [
    f"{base_url}/items/{item_id}",
    f"{base_url}/inventory/v1/documents/{doc_id}",
    f"{base_url}/items/image/{image_id}"
]
# Test each, adapt based on response
```

**Never ask user for:** Exact API endpoint URLs (try standard patterns)

#### 5. **Determine Matching Strategy**
```python
# ✅ DO: Try multiple matching strategies
def match_records(source, target):
    # 1. Try exact ID match
    # 2. Try SKU/unique identifier match
    # 3. Try name match (normalized)
    # 4. Try fuzzy matching
    # Report which strategy worked
```

**Never ask user for:** How to match records (try smart heuristics)

#### 6. **Handle Multi-Tenant Architecture**
```python
# ✅ DO: Auto-detect tenant ID from auth context
tenant_id = supabase.table("user_profiles") \
    .select("tenant_id") \
    .eq("user_id", auth.uid()) \
    .single() \
    .execute() \
    .data["tenant_id"]
```

**Never ask user for:** Tenant ID (fetch from user_profiles)

### What AI Agent MUST Ask User For

#### 1. **Initial OAuth Credentials** (First-time setup only)
```
❓ "I need Zoho OAuth credentials for first-time setup. Please provide:
   1. Client ID (from Zoho API Console - Self Client setup)
   2. Client Secret (from Zoho API Console - Self Client setup)
   3. Grant Code (valid for 10 minutes - generate fresh from Zoho Console)
   
   Get these from: https://api-console.zoho.com/
   > Self Client > Generate Code (select scopes: ZohoInventory.FullAccess.all)"

✅ User provides: Client ID, Client Secret, Grant Code (all three required)
❌ AI never asks again (uses refresh token from now on)
```

#### 2. **Service Role Key** (For RLS bypass in imports)
```
❓ "I need Supabase Service Role Key to bypass RLS for bulk imports.
   Go to: Supabase Dashboard > Settings > API > Service Role Key
   Click 'Reveal' and paste here."

✅ User provides: Service role JWT token
❌ AI stores securely for future imports
```

#### 3. **Business Rules Clarification** (Only if ambiguous)
```
❓ "I found 30 unmatched products. Should I:
   A) Skip them
   B) Create new products in Supabase
   C) Manual review first"

✅ Ask only when logic is unclear
❌ Never ask for technical details
```

---

## 🔧 Generic Import Template

Use this pattern for **ANY** Zoho to Supabase import (products, customers, invoices, etc.)

### Phase 1: Setup & Configuration
```python
# 1. Read app configuration (automatic)
supabase_url = read_from_flutter_config()
supabase_key = get_service_role_key()  # Ask user once, store
zoho_refresh_token = get_refresh_token()  # Ask user once, store

# 2. Detect schema (automatic)
target_table = "products"  # or "customers", "invoices", etc.
sample = supabase.table(target_table).select("*").limit(1).execute()
schema = parse_schema(sample)  # {column: type, ...}

# 3. Determine source endpoint (automatic)
zoho_endpoint = detect_zoho_endpoint(target_table)
# products -> /inventory/v1/items
# customers -> /inventory/v1/contacts
# invoices -> /inventory/v1/invoices
```

### Phase 2: Data Extraction
```python
# 4. Fetch from Zoho (automatic, handle pagination)
def fetch_all_zoho_data(endpoint):
    all_items = []
    page = 1
    while True:
        response = zoho_api.get(endpoint, params={"page": page, "per_page": 200})
        items = response.json().get("items", [])
        if not items:
            break
        all_items.extend(items)
        page += 1
    return all_items

# 5. Fetch from Supabase (automatic, tenant-scoped)
supabase_data = supabase.table(target_table) \
    .select("*") \
    .eq("tenant_id", tenant_id) \
    .execute() \
    .data
```

### Phase 3: Matching & Transformation
```python
# 6. Smart matching (automatic)
def match_records(zoho_items, supabase_records):
    matches = []
    for record in supabase_records:
        # Try ID match
        zoho_item = find_by_id(zoho_items, record['external_id'])
        if zoho_item:
            matches.append((record, zoho_item))
            continue
        
        # Try SKU/unique identifier
        zoho_item = find_by_sku(zoho_items, record['sku'])
        if zoho_item:
            matches.append((record, zoho_item))
            continue
        
        # Try name match (normalized)
        zoho_item = find_by_name(zoho_items, record['name'])
        if zoho_item:
            matches.append((record, zoho_item))
    
    return matches

# 7. Transform data (automatic, schema-aware)
def transform_zoho_to_supabase(zoho_item, schema):
    transformed = {"tenant_id": tenant_id}  # Always include
    
    # Map Zoho fields to Supabase columns
    field_map = detect_field_mapping(zoho_item, schema)
    for zoho_field, supabase_column in field_map.items():
        transformed[supabase_column] = zoho_item.get(zoho_field)
    
    return transformed
```

### Phase 4: Import & Verification
```python
# 8. Upsert to Supabase (automatic, with error handling)
for supabase_record, zoho_item in matches:
    try:
        # Transform Zoho data
        data = transform_zoho_to_supabase(zoho_item, schema)
        
        # Handle special cases (images, attachments)
        if has_images(zoho_item):
            image_url = download_and_upload_image(zoho_item)
            data['image_url'] = image_url
        
        # Upsert (update if exists, insert if new)
        supabase.table(target_table) \
            .upsert(data, on_conflict="id") \
            .execute()
        
        success_count += 1
    except Exception as e:
        errors.append((supabase_record, str(e)))

# 9. Generate report (automatic)
print(f"✅ Success: {success_count}")
print(f"❌ Errors: {len(errors)}")
export_unmatched_to_csv(unmatched_records)
```

---

## 📋 Import Checklist for AI Agents

Before starting ANY import, verify:

- [ ] **1. Credentials Available**
  - [ ] Zoho refresh token exists (or ask for Client ID/Secret/Grant Code)
  - [ ] Supabase service role key exists (or ask user to provide)
  
- [ ] **2. Schema Understanding**
  - [ ] Read Flutter model files to understand data structure
  - [ ] Query Supabase to confirm table exists
  - [ ] Verify RLS policies won't block service role
  
- [ ] **3. Matching Strategy**
  - [ ] Identify unique identifiers (SKU, email, invoice_number, etc.)
  - [ ] Plan primary + fallback matching logic
  - [ ] Handle duplicates gracefully
  
- [ ] **4. Multi-Tenant Compliance**
  - [ ] Always include `tenant_id` in inserts
  - [ ] Filter queries by `tenant_id`
  - [ ] Verify user's tenant ID from user_profiles
  
- [ ] **5. Special Data Handling**
  - [ ] Images → Download + Upload to Supabase Storage
  - [ ] Dates → Convert timezones (Zoho UTC → App timezone)
  - [ ] Currency → Verify CLP formatting
  - [ ] Relationships → Handle foreign keys correctly
  
- [ ] **6. Error Recovery**
  - [ ] Log all errors with context
  - [ ] Generate CSV of failed/unmatched records
  - [ ] Allow re-running without duplicating successful imports

---

## 🗂️ Common Import Scenarios

### Scenario 1: Import Products with Images
**Script:** `zoho_to_supabase_import.py`

**What it does:**
1. Fetches products from Supabase (tenant-scoped)
2. Fetches items from Zoho Inventory (all pages)
3. Matches by SKU first, name second
4. Downloads images from Zoho Documents API
5. Sanitizes filenames (special characters)
6. Uploads to Supabase Storage
7. Updates product records with image URLs

**User provides:** Grant code (first time only)

**AI agent does:** Everything else

---

### Scenario 2: Import Customers/Contacts
**Pseudocode:**
```python
# Endpoint: /inventory/v1/contacts
# Match by: email (primary), phone (fallback), name (last resort)
# Special fields: 
#   - billing_address → JSON structure
#   - shipping_address → JSON structure
#   - contact_persons → Array (may need separate table)

zoho_contacts = fetch_all("/inventory/v1/contacts")
supabase_customers = fetch_customers(tenant_id)

for customer in supabase_customers:
    zoho_contact = match_by_email(customer.email) \
                   or match_by_phone(customer.phone)
    
    if zoho_contact:
        update_customer(customer.id, {
            'zoho_contact_id': zoho_contact['contact_id'],
            'billing_address': parse_address(zoho_contact['billing_address']),
            'shipping_address': parse_address(zoho_contact['shipping_address']),
            # ... other fields
        })
```

---

### Scenario 3: Import Invoices
**Pseudocode:**
```python
# Endpoint: /inventory/v1/invoices
# Match by: invoice_number (unique)
# Special handling:
#   - Line items → Separate table (invoice_items)
#   - Payments → Link to sales_payments table
#   - Customer → Must exist in customers table first

zoho_invoices = fetch_all("/inventory/v1/salesorders")  # or /invoices

for zoho_invoice in zoho_invoices:
    # 1. Ensure customer exists
    customer = ensure_customer_exists(zoho_invoice['customer_id'])
    
    # 2. Create invoice header
    invoice = create_invoice({
        'tenant_id': tenant_id,
        'customer_id': customer.id,
        'invoice_number': zoho_invoice['invoice_number'],
        'total': zoho_invoice['total'],
        'status': map_status(zoho_invoice['status']),
        # ... other fields
    })
    
    # 3. Create line items
    for line in zoho_invoice['line_items']:
        product = find_product_by_sku(line['sku'])
        create_line_item(invoice.id, product.id, line['quantity'], line['rate'])
    
    # 4. Create payment records
    for payment in zoho_invoice.get('payments', []):
        create_payment(invoice.id, payment['amount'], payment['date'])
```

---

### Scenario 4: Import Chart of Accounts
**Pseudocode:**
```python
# Endpoint: /books/v3/chartofaccounts (Zoho Books, not Inventory)
# Match by: account_code (unique)
# Special: Hierarchical structure (parent accounts)

zoho_accounts = fetch_all("/books/v3/chartofaccounts")

# First pass: Create all accounts
for zoho_account in zoho_accounts:
    create_or_update_account({
        'tenant_id': tenant_id,
        'account_code': zoho_account['account_code'],
        'account_name': zoho_account['account_name'],
        'account_type': map_account_type(zoho_account['account_type']),
        'is_active': zoho_account['status'] == 'active',
        # parent_id set in second pass
    })

# Second pass: Link parent-child relationships
for zoho_account in zoho_accounts:
    if zoho_account.get('parent_account_id'):
        link_parent_account(
            zoho_account['account_code'],
            zoho_account['parent_account_id']
        )
```

---

## 🔐 Security Best Practices

### 1. **Never Hardcode Credentials**
```python
# ❌ BAD
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# ✅ GOOD
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
# Store in .env file, add to .gitignore
```

### 2. **Use Service Role Key Only for Imports**
```python
# Service role bypasses RLS - use ONLY for:
# - Bulk imports (bypassing tenant RLS temporarily)
# - Admin operations
# 
# For app runtime, ALWAYS use anon key + user JWT
```

### 3. **Validate Tenant Isolation**
```python
# ALWAYS filter by tenant_id, even with service role
supabase.table("products") \
    .insert({"tenant_id": tenant_id, ...})  # ✅ Explicit tenant

# NEVER trust user input for tenant_id
tenant_id = get_authenticated_user_tenant()  # From user_profiles
```

### 4. **Log Import Activities**
```python
# Create audit trail
create_import_log({
    'tenant_id': tenant_id,
    'import_type': 'zoho_products',
    'records_imported': success_count,
    'errors': len(errors),
    'timestamp': datetime.now(),
    'executed_by': user_id
})
```

---

## 🧪 Testing Import Scripts

### Before Running Production Import

1. **Test with Small Dataset**
```python
# Limit to first 10 records
test_items = zoho_items[:10]
test_products = supabase_products[:10]
```

2. **Dry Run Mode**
```python
DRY_RUN = True  # Set to False for actual import

if DRY_RUN:
    print(f"Would import: {data}")
else:
    supabase.table("products").insert(data).execute()
```

3. **Backup Before Import**
```sql
-- In Supabase SQL Editor
CREATE TABLE products_backup_20251105 AS 
SELECT * FROM products WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890';
```

4. **Verify After Import**
```python
# Check counts match
expected_count = len(matches)
actual_count = supabase.table("products") \
    .select("id", count="exact") \
    .eq("tenant_id", tenant_id) \
    .is_not("image_url", "null") \
    .execute() \
    .count

assert actual_count >= expected_count - tolerance
```

---

## 📊 Expected Outputs

Every import script should generate:

### 1. **Console Output** (Real-time progress)
```
======================================================================
🚀 ZOHO TO SUPABASE IMPORT: Products
======================================================================

📡 Connecting to Zoho and Supabase...
📥 Fetching products from Supabase... (81 products)
📥 Fetching items from Zoho... (1,440 items across 8 pages)

🔍 Matching products...
✅ Matched 51 products: 49 by SKU, 2 by name
⚠️  No match found for 30 products

📦 Processing 51 matched products...
[1/51] Product Name (SKU: 12345)
  📥 Downloading image...
  📤 Uploading to Supabase...
  ✅ Success!
...

======================================================================
📊 IMPORT SUMMARY
======================================================================
✅ Successfully imported: 51
❌ Errors: 0
📦 Total matched: 51/81
======================================================================
```

### 2. **CSV Report** (`unmatched_products.csv`)
```csv
SKU,Name,Has Image,Product ID
NNV7,ALIEXPRESS,No,abc-123-def
TES-PRU-87011,prueba 2,No,xyz-789-ghi
...
```

### 3. **Error Log** (`import_errors_20251105.log`)
```
[2025-11-05 17:39:42] ERROR: Failed to upload image for SKU AE0227
  Reason: Invalid key (special characters)
  Zoho ID: 3479156000004801021
  File: ./temp_zoho_images/AE0227_Asiento West Biking Prostático.jpg
  
[2025-11-05 17:39:45] ERROR: Product not found in Zoho
  Supabase ID: f4e2d1c3-b5a6-4789-0123-456789abcdef
  SKU: NNV7
  Name: ALIEXPRESS
```

---

## 🚀 Quick Start Commands

### From Project Root:

```bash
# Navigate to import scripts
cd scripts/zoho_import

# 1. First-time setup (get refresh token)
python3 step1_get_zoho_tokens.py
# Paste: Client ID, Client Secret, Grant Code
# Save the refresh_token output

# 2. Refresh access token (if needed)
python3 refresh_zoho_token.py

# 3. Run full import (products + images)
python3 zoho_to_supabase_import.py

# 4. Check results
cat unmatched_products.csv
```

### Dependencies:
```bash
pip3 install requests supabase-py
```

---

## 🔄 Future Import Extensions

### Products (Full Import)
- **Current:** Images only
- **Future:** Full product data (price, cost, description, categories, variants)
- **Script:** Extend `zoho_to_supabase_import.py`

### Customers/Contacts
- **Endpoint:** `/inventory/v1/contacts`
- **Match by:** Email → Phone → Name
- **Special:** Address parsing, contact persons array

### Invoices (Sales Orders)
- **Endpoint:** `/inventory/v1/salesorders`
- **Match by:** invoice_number (unique)
- **Special:** Line items (separate table), payment links

### Inventory Adjustments
- **Endpoint:** `/inventory/v1/inventoryadjustments`
- **Purpose:** Sync stock levels
- **Match by:** product SKU + adjustment date

### Suppliers/Vendors
- **Endpoint:** `/inventory/v1/vendors` (Zoho Books)
- **Match by:** Email → Tax ID → Name
- **Special:** Payment terms mapping

### Purchase Orders
- **Endpoint:** `/inventory/v1/purchaseorders`
- **Match by:** PO number
- **Special:** Link to suppliers, receiving status

---

## 💡 AI Agent Decision Tree

```
START: User requests Zoho import

1. What to import?
   → Products ───┐
   → Customers ──┤
   → Invoices ───┤──> Determine Zoho endpoint
   → Accounts ───┤
   → Other ──────┘

2. Check credentials:
   ├─ Refresh token exists? ──YES──> Use it
   └─ NO ──> Ask user for: Client ID, Secret, Grant Code
             ──> Exchange for refresh token
             ──> Store for future use

3. Check Supabase access:
   ├─ Service role key exists? ──YES──> Use it
   └─ NO ──> Ask user to provide from dashboard
             ──> Store securely

4. Fetch app configuration:
   ├─> Read supabase_config.dart for URL/keys
   ├─> Parse Flutter models for schema
   └─> Query database for tenant_id

5. Execute import:
   ├─> Fetch from Zoho (paginated)
   ├─> Fetch from Supabase (tenant-scoped)
   ├─> Match records (SKU → Name → Fuzzy)
   ├─> Transform data (Zoho → Supabase schema)
   ├─> Handle special fields (images, addresses, etc.)
   └─> Upsert to Supabase

6. Generate reports:
   ├─> Console summary (success/errors/unmatched)
   ├─> CSV of unmatched records
   └─> Error log with details

7. Cleanup:
   └─> Delete temp files, close connections

END
```

---

## 📚 References

### Zoho API Documentation
- **Inventory API:** https://www.zoho.com/inventory/api/v1/
- **Books API:** https://www.zoho.com/books/api/v3/
- **OAuth 2.0:** https://www.zoho.com/accounts/protocol/oauth.html
- **Documents API:** `/inventory/v1/documents/{document_id}`

### Supabase Documentation
- **Storage:** https://supabase.com/docs/guides/storage
- **Python Client:** https://supabase.com/docs/reference/python
- **RLS Policies:** https://supabase.com/docs/guides/auth/row-level-security

### Multi-Tenant Best Practices
- Always include `tenant_id` in all tables
- Filter queries by `tenant_id = user_tenant_id()`
- Use service role ONLY for imports (bypass RLS temporarily)
- See: `.github/copilot-instructions.md` → Multi-Tenant Architecture

---

## 📝 Changelog

### 2025-11-05: Image Import Implementation
- ✅ Created OAuth token exchange script
- ✅ Implemented smart SKU/name matching
- ✅ Added special character sanitization for filenames
- ✅ Achieved 100% success rate (51/51 matched products)
- ✅ Generated unmatched products report (30 items)
- ✅ Organized all scripts in `scripts/zoho_import/`

### Future Additions:
- [ ] Full product data import (beyond images)
- [ ] Customer/contact import
- [ ] Invoice import with line items
- [ ] Automated scheduling (cron jobs)
- [ ] Incremental sync (only new/updated records)

---

## 🤝 Contributing

When extending this system:

1. **Follow the file organization:** All Zoho scripts in `scripts/zoho_import/`
2. **Use the generic template:** Phase 1-4 pattern above
3. **Maximize automation:** AI agent should do everything possible
4. **Document user inputs:** What MUST the user provide and why
5. **Generate reports:** Console + CSV for every import
6. **Test with small datasets:** Always dry-run before production

---

**Last Updated:** November 5, 2025  
**Maintained by:** AI Agent  
**Contact:** See project README for support
