# 🔄 Zoho to Supabase Import System with Stock Tracking

**Complete Guide for AI-Assisted Data Migration**

> This guide documents the automated import system for migrating data from Zoho Inventory to Supabase **with automatic stock adjustment tracking**. It serves as a reference for AI agents to perform autonomous imports with minimal user intervention.

---

## 🎯 Key Innovation: Transaction-Scoped Import Context

**The Problem:** Supabase Python client treats each call as a separate HTTP request (separate transaction), so session variables set via RPC don't persist to subsequent UPDATE calls.

**The Solution:** Use a PostgreSQL RPC function that sets context variables AND updates products in **ONE TRANSACTION**, allowing the trigger to detect import operations and create stock adjustment records.

**Why This Matters:** Import stock changes are labeled as "Importación" (not "Ajuste Manual"), creating a clear audit trail of automated vs manual stock changes.

---

## 📁 File Organization

All Zoho import scripts are located in:
```
/scripts/zoho_import/
```

**Script Structure:**
```
scripts/zoho_import/
├── test_import_with_tracking.py     # NEW: Import with stock tracking (USE THIS)
├── zoho_to_supabase_import.py       # Legacy: Image import only
├── step1_get_zoho_tokens.py         # OAuth: Exchange grant code for tokens
├── refresh_zoho_token.py            # Utility: Get fresh access token
└── test_products.csv                # Sample: Test data for imports
```

**⚠️ Important:** Use `test_import_with_tracking.py` as the template for ALL future imports. It demonstrates the correct session variable + RPC pattern.

---

## 🎯 What We Accomplished: Import Stock Tracking System

### Problem Statement
When importing products from Zoho Inventory, stock changes were creating "ghost" adjustment records or being labeled as manual changes. Need to:
1. **Prevent ghost records**: Only create adjustments when stock actually changes
2. **Label imports correctly**: Show "Importación" origin (not "Ajuste Manual")
3. **Track import batches**: Reference column links adjustments to specific import session

### Solution Architecture

#### 1. **Database Schema** (`core_schema.sql`)

**Stock Adjustments Table** (lines 799-811):
```sql
create table if not exists stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade not null,
  adjustment_type text not null check (adjustment_type in (
    'manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import'
  )),
  quantity integer not null,        -- Change amount (e.g., -10, +50)
  stock_before integer not null,    -- Stock before change
  stock_after integer not null,     -- Stock after change
  reason text,
  notes text,
  reference text,                   -- NEW: Import batch ID
  created_by uuid references auth.users(id),
  created_at timestamp with time zone default now()
);
```

**Key Addition**: `reference` column stores import batch identifier (e.g., `import_1762563467750`)

**Session Variables Helper** (`set_config` RPC, lines 1629-1654):
```sql
create or replace function public.set_config(
  setting_name text,
  new_value text,
  is_local boolean default false
)
returns text
security definer
language plpgsql
as $$
begin
  return pg_catalog.set_config(setting_name, new_value, is_local);
end;
$$;

grant execute on function public.set_config(text, text, boolean) to authenticated;
```

**Purpose**: Exposes PostgreSQL's `set_config()` to authenticated users, allowing session variable setting from Python client.

**Single-Transaction Import RPC** (`import_product_with_context`, lines 1656-1720):
```sql
create or replace function public.import_product_with_context(
  p_tenant_id uuid,
  p_sku text,
  p_product_data jsonb,
  p_import_reference text,
  p_import_reason text default 'Zoho Import'
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_updated_count integer := 0;
begin
  -- Set import context (transaction-scoped)
  perform pg_catalog.set_config('app.stock_adjustment_context', 'import', true);
  perform pg_catalog.set_config('app.import_reference', p_import_reference, true);
  perform pg_catalog.set_config('app.import_reason', p_import_reason, true);
  
  -- Update product (trigger sees context)
  update products
  set
    name = coalesce((p_product_data->>'name')::text, name),
    price = coalesce((p_product_data->>'price')::numeric, price),
    stock_quantity = coalesce((p_product_data->>'stock_quantity')::integer, stock_quantity),
    inventory_qty = coalesce((p_product_data->>'stock_quantity')::integer, inventory_qty),
    description = coalesce((p_product_data->>'description')::text, description),
    updated_at = now()
  where tenant_id = p_tenant_id and sku = p_sku;
  
  get diagnostics v_updated_count = row_count;
  
  -- Clear context
  perform pg_catalog.set_config('app.stock_adjustment_context', '', true);
  perform pg_catalog.set_config('app.import_reference', '', true);
  perform pg_catalog.set_config('app.import_reason', '', true);
  
  return jsonb_build_object('success', true, 'updated_count', v_updated_count);
end;
$$;

grant execute on function public.import_product_with_context(uuid, text, jsonb, text, text) to authenticated;
```

**Critical Design**: All three operations (set context, update product, clear context) happen in **ONE database transaction**, so the trigger sees the import context.

**Stock Tracking Trigger** (lines 863-958):
```sql
create or replace function track_product_stock_changes()
returns trigger
language plpgsql
security definer
as $$
declare
  v_skip_trigger text;
  v_import_context text;
  v_import_reference text;
  v_import_reason text;
  v_adjustment_type text := 'manual';
begin
  -- Check if trigger should be skipped (for invoice operations)
  v_skip_trigger := current_setting('app.skip_stock_adjustment_trigger', true);
  if v_skip_trigger = 'true' then
    return new;
  end if;
  
  -- Only track if stock actually changed
  if (tg_op = 'UPDATE' and old.stock_quantity = new.stock_quantity) then
    return new;
  end if;
  
  -- Detect import context
  v_import_context := current_setting('app.stock_adjustment_context', true);
  if v_import_context = 'import' then
    v_adjustment_type := 'import';
    v_import_reference := current_setting('app.import_reference', true);
    v_import_reason := current_setting('app.import_reason', true);
  end if;
  
  -- Create adjustment record
  insert into stock_adjustments (
    tenant_id, product_id, adjustment_type,
    quantity, stock_before, stock_after,
    reason, reference, created_by
  ) values (
    new.tenant_id, new.id, v_adjustment_type,
    new.stock_quantity - coalesce(old.stock_quantity, 0),
    coalesce(old.stock_quantity, 0), new.stock_quantity,
    v_import_reason, v_import_reference, auth.uid()
  );
  
  return new;
end;
$$;
```

**Key Logic**:
- Checks `app.stock_adjustment_context` session variable
- If `'import'` → creates adjustment with `type='import'` and imports the `reference`
- If not set → creates adjustment with `type='manual'`

#### 2. **Python Import Script** (`test_import_with_tracking.py`)

**Authentication Flow**:
```python
def initialize_supabase():
    """Initialize Supabase client with user authentication."""
    client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    
    # Sign in with email/password
    auth_response = client.auth.sign_in_with_password({
        "email": "vinabikechile@gmail.com",
        "password": "000000"
    })
    
    if not auth_response.user:
        raise Exception("Authentication failed")
    
    return client, auth_response.user.id
```

**Tenant ID Detection**:
```python
def get_user_tenant_id(supabase, user_id):
    """Get tenant_id from user_profiles table."""
    response = supabase.table('user_profiles') \
        .select('tenant_id') \
        .eq('id', user_id) \
        .single() \
        .execute()
    
    return response.data['tenant_id']
```

**Single-Transaction Import Pattern**:
```python
def import_products(supabase, tenant_id):
    """Import products using single-transaction RPC."""
    import_ref = f"import_{int(time.time() * 1000)}"
    
    # Read CSV
    df = pd.read_csv('test_products.csv')
    
    # Get current stock levels
    products_response = supabase.table('products') \
        .select('id, sku, stock_quantity') \
        .eq('tenant_id', tenant_id) \
        .execute()
    current_stock = {p['sku']: p['stock_quantity'] for p in products_response.data}
    
    # Import each product
    for _, row in df.iterrows():
        sku = str(row['sku']).strip()
        new_stock = int(row['stock_quantity'])
        old_stock = current_stock.get(sku, 0)
        
        # Build product data
        product_data = {
            'name': row['name'],
            'price': float(row['price']),
            'stock_quantity': new_stock,
            'description': row.get('description', '')
        }
        
        # Call RPC function (sets context + updates in ONE transaction)
        result = supabase.rpc(
            'import_product_with_context',
            {
                'p_tenant_id': tenant_id,
                'p_sku': sku,
                'p_product_data': product_data,
                'p_import_reference': import_ref,
                'p_import_reason': f'CSV Import: {sku}'
            }
        ).execute()
        
        if result.data.get('updated_count', 0) > 0:
            print(f"✅ Imported {sku}: {old_stock} → {new_stock}")
```

**Why This Works**:
1. All logic in ONE RPC call = ONE database transaction
2. Session variables set inside function are visible to trigger
3. Trigger detects `app.stock_adjustment_context='import'`
4. Creates adjustment with `type='import'` and proper `reference`

#### 3. **Production Verification**

Screenshot shows Stock Movements UI with:
- ✅ Adjustment type: "Ajuste"
- ✅ Origin: **"Importación"** (not "Ajuste Manual")
- ✅ Reference: `ADJ-L20251108-XXXXXX` (display format of `import_TIMESTAMP`)
- ✅ Stock tracking: 456→123 (Δ -333), 123→456 (Δ +333)
- ✅ No ghost records: Only actual stock changes logged

### Key Files
- **Database Schema:** `supabase/sql/core_schema.sql` (lines 799-811, 1629-1720, 863-958)
- **Import Script:** `scripts/zoho_import/test_import_with_tracking.py` (469 lines)
- **Test Data:** `scripts/zoho_import/test_products.csv` (15 products)

---

## 🤖 AI Agent Workflow Pattern

### Principle: **Maximum Autonomy, Minimum User Input**

The AI agent should automate everything possible and only ask the user for information that is strictly impossible to obtain programmatically.

### What AI Agent MUST Do Automatically

#### 1. **Use Single-Transaction RPC Pattern**
```python
# ✅ CORRECT: All context + update in ONE transaction
result = supabase.rpc('import_product_with_context', {
    'p_tenant_id': tenant_id,
    'p_sku': sku,
    'p_product_data': product_data,
    'p_import_reference': import_ref,
    'p_import_reason': f'Import from {source}'
}).execute()

# ❌ WRONG: Separate calls = separate transactions
supabase.rpc('set_config', {...}).execute()  # Transaction 1
supabase.table('products').update({...}).execute()  # Transaction 2 (context lost!)
```

**Critical Rule**: Session variables ONLY persist within a single database transaction. Supabase Python client creates separate transactions for each HTTP request, so you MUST use RPC functions that bundle context + update together.

#### 2. **Fetch Application Configuration**
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

#### 3. **Detect Data Structures**
```python
# ✅ DO: Query database to understand schema
supabase.table("products").select("*").limit(1).execute()
# Parse response to understand columns, types, relationships
```

**Never ask user for:** What columns exist, data types, relationships

#### 4. **Handle Authentication Automatically**
```python
# ✅ DO: Use refresh tokens to get access tokens
def get_access_token():
    if token_expired():
        return refresh_access_token(REFRESH_TOKEN)
    return CURRENT_ACCESS_TOKEN
```

**Never ask user for:** New access tokens (use refresh token instead)

#### 5. **Discover API Endpoints**
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

#### 6. **Determine Matching Strategy**
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

#### 7. **Handle Multi-Tenant Architecture**
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

## 🔧 Generic Import Template (With Stock Tracking)

Use this pattern for **ANY** Zoho to Supabase import that needs stock adjustment tracking.

### Phase 1: Setup & Configuration
```python
# 1. Initialize Supabase with authentication
from supabase import create_client

SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGc..."  # Read from config

client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

# 2. Authenticate user
auth_response = client.auth.sign_in_with_password({
    "email": "user@example.com",
    "password": "password"
})

user_id = auth_response.user.id

# 3. Get tenant_id from user_profiles
tenant_response = client.table('user_profiles') \
    .select('tenant_id') \
    .eq('id', user_id) \
    .single() \
    .execute()

tenant_id = tenant_response.data['tenant_id']

# 4. Generate import reference (batch ID)
import time
import_ref = f"import_{int(time.time() * 1000)}"
```

### Phase 2: Data Extraction
```python
# 5. Fetch from Zoho (if needed)
def fetch_zoho_inventory():
    # Use Zoho API with OAuth token
    # Return list of items
    pass

# 6. Read from CSV (for testing or manual imports)
import pandas as pd
df = pd.read_csv('import_data.csv')

# 7. Get current state from Supabase (for comparison)
products_response = client.table('products') \
    .select('id, sku, stock_quantity') \
    .eq('tenant_id', tenant_id) \
    .execute()

current_stock = {p['sku']: p['stock_quantity'] for p in products_response.data}
```

### Phase 3: Import with Context (Single-Transaction Pattern)
```python
# 8. Import each record using RPC function
for _, row in df.iterrows():
    sku = str(row['sku']).strip()
    new_stock = int(row['stock_quantity'])
    old_stock = current_stock.get(sku, 0)
    
    # Build product data (jsonb)
    product_data = {
        'name': row['name'],
        'price': float(row['price']),
        'stock_quantity': new_stock,
        'description': row.get('description', '')
    }
    
    # Call single-transaction RPC
    try:
        result = client.rpc(
            'import_product_with_context',
            {
                'p_tenant_id': tenant_id,
                'p_sku': sku,
                'p_product_data': product_data,
                'p_import_reference': import_ref,
                'p_import_reason': f'Import from {source}: {sku}'
            }
        ).execute()
        
        if result.data.get('updated_count', 0) > 0:
            print(f"✅ Imported {sku}: {old_stock} → {new_stock}")
        else:
            print(f"⚠️  Product not found: {sku}")
            
    except Exception as e:
        print(f"❌ Error importing {sku}: {str(e)}")
```

### Phase 4: Verification & Reporting
```python
# 9. Verify stock adjustments were created
adjustments = client.table('stock_adjustments') \
    .select('*') \
    .eq('tenant_id', tenant_id) \
    .eq('reference', import_ref) \
    .eq('adjustment_type', 'import') \
    .execute()

print(f"\n📊 IMPORT SUMMARY")
print(f"==============================")
print(f"Import Reference: {import_ref}")
print(f"Stock Adjustments Created: {len(adjustments.data)}")
print(f"Total Products Processed: {len(df)}")
```

### Key Differences from Old Approach

**❌ OLD (DOESN'T WORK):**
```python
# Set context via RPC
client.rpc('set_config', {
    'setting_name': 'app.stock_adjustment_context',
    'new_value': 'import',
    'is_local': True
}).execute()  # Transaction 1

# Update product
client.table('products').update({
    'stock_quantity': new_stock
}).eq('sku', sku).execute()  # Transaction 2 (context lost!)
```

**Problem**: Separate HTTP requests = separate transactions. Session variables don't persist.

**✅ NEW (WORKS):**
```python
# Single RPC bundles context + update
client.rpc('import_product_with_context', {
    'p_tenant_id': tenant_id,
    'p_sku': sku,
    'p_product_data': product_data,
    'p_import_reference': import_ref,
    'p_import_reason': reason
}).execute()  # ONE transaction, trigger sees context
```

**Solution**: RPC function handles everything in one database transaction.

---

## 📋 Import Checklist for AI Agents

Before starting ANY import, verify:

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

- [ ] **1. Database RPC Function Exists**
  - [ ] Check if `import_{table}_with_context()` RPC function exists in `core_schema.sql`
  - [ ] If not, create following the `import_product_with_context()` pattern (lines 1656-1720)
  - [ ] Function must: set context vars → update record → clear context vars (all in ONE transaction)
  - [ ] Grant execute permission to `authenticated` role
  
- [ ] **2. Stock Tracking Trigger Exists**
  - [ ] For products: `track_product_stock_changes()` trigger (lines 863-958) already exists
  - [ ] For other entities with stock: create similar trigger that checks `app.stock_adjustment_context`
  
- [ ] **3. Credentials Available**
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
