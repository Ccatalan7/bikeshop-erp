# 🤖 AI Agent Import System Guide

**This is the MASTER file. Read this FIRST before doing any import/sync task.**

---

## 📋 How This System Works

When a user asks you to perform any data import/sync task between systems (Zoho, Odoo, Supabase/Flutter), follow this workflow:

### Step 1: Ask User What They Want

**Ask:** "What task do you want to accomplish?"

Examples:
- "Sync product prices from Zoho to Flutter"
- "Import customers from Zoho to Supabase"
- "Update SKUs from Odoo to Zoho"
- "Match products by name between systems"
- "Import suppliers from Zoho Books"

### Step 2: Identify Required Platforms

Based on the task, determine which platforms you need:
- **Zoho Inventory/Books** - Product data, contacts, invoices
- **Odoo** - ERP data, products, contacts
- **Supabase/Flutter** - App database (products, customers, etc.)

### Step 3: Ask for Credentials (Smart Reuse Pattern)

**🔑 Credential Management Philosophy:**
- **Ask ONCE per conversation session** - store in variables, reuse for multiple operations
- **Only ask again if:** User explicitly says credentials changed, or you get auth errors
- **Token expiry is handled internally** - Access tokens auto-refresh, you don't need to ask again

**If task involves Zoho:**

First time in conversation:
```python
# Ask once, store for session
print("\n🔑 I need your Zoho credentials (I'll reuse them for this session):")
zoho_client_id = input("Client ID: ").strip()
zoho_client_secret = input("Client Secret: ").strip()
zoho_refresh_token = input("Refresh Token: ").strip()
```

Later in same conversation:
```python
# Reuse stored credentials - DON'T ask again
zoho = ZohoConnection(zoho_client_id, zoho_client_secret, zoho_refresh_token)
```

**If task involves Odoo:**

First time in conversation:
```python
# Ask once, store for session
print("\n🔑 I need your Odoo API Key (I'll reuse it for this session):")
odoo_api_key = input("API Key: ").strip()
```

Later in same conversation:
```python
# Reuse stored credentials - DON'T ask again
odoo = OdooConnection(odoo_api_key)
```

**Already hardcoded in config.py (NEVER ask, NEVER expire):**
- Supabase URL + Service Role Key
- Odoo URL + Database + Username
- Zoho API domains + Organization ID
- Tenant ID

**When to ask for credentials again:**
- ✅ User says "use different credentials" or "credentials changed"
- ✅ You get 401 Unauthorized or authentication errors
- ❌ NOT on every script run in same conversation
- ❌ NOT because access token expired (handled internally)

**Smart Pattern:**
1. **First operation**: Ask for credentials, store in variables
2. **Second operation in same conversation**: Reuse stored credentials
3. **User says "update prices"**: Use existing credentials
4. **User says "sync products"**: Use existing credentials
5. **User says "my token expired"**: Ask for fresh credentials

### Step 4: Import Connection Modules

Create your script using the connection modules:

```python
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

# Import what you need
from connections.zoho_connection import ZohoConnection
from connections.odoo_connection import OdooConnection
from connections.supabase_connection import SupabaseConnection
```

### Step 5: Write Task-Specific Logic

**Example structure:**

```python
def main():
    # Smart credential management:
    # - If agent has stored credentials from earlier → reuse them
    # - If first time or auth failed → ask user
    print("\n🔑 Zoho credentials needed")
    print("   (I'll reuse these for the rest of our conversation)\n")
    client_id = input("Client ID: ").strip()
    client_secret = input("Client Secret: ").strip()
    refresh_token = input("Refresh Token: ").strip()
    
    # Initialize connections (org ID from config.py)
    zoho = ZohoConnection(client_id, client_secret, refresh_token)
    supabase = SupabaseConnection()  # Uses permanent config.py credentials
    
    # Fetch data
    zoho_products = zoho.fetch_all_products()
    flutter_products = supabase.fetch_all_products()
    
    # Your business logic here
    # - Match by name
    # - Compare fields
    # - Update records
    
    # Show results
    print(f"✅ Updated: {success_count}")
```

### Step 6: Save Script in tasks/ Folder

```bash
scripts/import_templates/tasks/sync_prices_zoho_to_flutter.py
scripts/import_templates/tasks/import_customers_from_zoho.py
scripts/import_templates/tasks/update_skus_odoo_to_zoho.py
```

---

## 🔌 Available Connection Modules

### 1. `connections/zoho_connection.py`

**What it provides:**
- OAuth token refresh (automatic)
- Fetch products with pagination
- Fetch contacts with pagination
- Update product/contact by ID
- Generic GET/POST/PUT methods

**How to use:**
```python
# Ask user for credentials (they can expire)
client_id = input("Zoho Client ID: ").strip()
client_secret = input("Zoho Client Secret: ").strip()
refresh_token = input("Zoho Refresh Token: ").strip()

zoho = ZohoConnection(client_id, client_secret, refresh_token)

# Fetch all products
products = zoho.fetch_all_products()  # Returns List[Dict]
# Access token auto-refreshes internally (1-hour expiry handled automatically)
# Organization ID loaded from config.py

# Fetch all contacts
contacts = zoho.fetch_all_contacts()  # Returns List[Dict]

# Update product
zoho.update_product(product_id, {'sku': 'NEW-SKU', 'rate': 10000})

# Generic request
data = zoho.get('/items/12345')
```

### 2. `connections/odoo_connection.py`

**What it provides:**
- XML-RPC authentication
- Search and read products
- Search and read contacts
- Create/update records

**How to use:**
```python
# Ask user for API key (can expire)
api_key = input("Odoo API Key: ").strip()

odoo = OdooConnection(api_key)

# Fetch all products
products = odoo.fetch_all_products()  # Returns List[Dict]

# Search specific records
product_ids = odoo.search('product.product', [('default_code', '=', 'SKU123')])

# Read records
data = odoo.read('product.product', product_ids, ['name', 'list_price'])
```

### 3. `connections/supabase_connection.py`

**What it provides:**
- Pre-authenticated Supabase client
- Fetch products with pagination
- Fetch customers with pagination
- Update/insert records with tenant_id filtering

**How to use:**
```python
supabase = SupabaseConnection()

# Fetch all products
products = supabase.fetch_all_products()  # Returns List[Dict]

# Fetch all customers
customers = supabase.fetch_all_customers()  # Returns List[Dict]

# Update product
supabase.update_product(product_id, {'price': 10000, 'cost': 5000})

# Generic query
data = supabase.client.table('products').select('*').eq('sku', 'SKU123').execute()
```

---

## 🛠️ Common Task Patterns

### Pattern 1: Sync Data Between Two Systems

**Task:** Update prices from Zoho to Flutter

```python
from connections.zoho_connection import ZohoConnection
from connections.supabase_connection import SupabaseConnection

def sync_prices():
    # Connect
    zoho = ZohoConnection(client_id, client_secret)
    supabase = SupabaseConnection()
    
    # Fetch data
    zoho_products = zoho.fetch_all_products()
    flutter_products = supabase.fetch_all_products()
    
    # Match by name
    zoho_by_name = {normalize_name(p['name']): p for p in zoho_products}
    flutter_by_name = {normalize_name(p['name']): p for p in flutter_products}
    
    # Find differences
    updates = []
    for name, flutter_prod in flutter_by_name.items():
        if name in zoho_by_name:
            zoho_prod = zoho_by_name[name]
            if flutter_prod['price'] != zoho_prod['price']:
                updates.append({
                    'id': flutter_prod['id'],
                    'new_price': zoho_prod['price']
                })
    
    # Apply updates
    for update in updates:
        supabase.update_product(update['id'], {'price': update['new_price']})
```

### Pattern 2: Import from One System to Another

**Task:** Import customers from Zoho to Flutter

```python
from connections.zoho_connection import ZohoConnection
from connections.supabase_connection import SupabaseConnection

def import_customers():
    zoho = ZohoConnection(client_id, client_secret)
    supabase = SupabaseConnection()
    
    # Fetch contacts from Zoho
    zoho_contacts = zoho.fetch_all_contacts()
    
    # Transform to Flutter format
    for contact in zoho_contacts:
        customer_data = {
            'name': contact.get('contact_name'),
            'email': contact.get('email'),
            'phone': contact.get('phone'),
            'rut': contact.get('custom_field_hash', {}).get('cf_rut'),
        }
        
        # Insert to Supabase
        supabase.client.table('customers').insert(customer_data).execute()
```

### Pattern 3: Match and Update by Name

**Task:** Update SKUs from Odoo to Zoho

```python
from connections.zoho_connection import ZohoConnection
from connections.odoo_connection import OdooConnection

def update_skus():
    # Ask for credentials
    print("\n🔑 Zoho Credentials:")
    zoho_client_id = input("Client ID: ").strip()
    zoho_client_secret = input("Client Secret: ").strip()
    zoho_refresh_token = input("Refresh Token: ").strip()
    
    print("\n🔑 Odoo Credentials:")
    odoo_api_key = input("API Key: ").strip()
    
    # Initialize connections
    zoho = ZohoConnection(zoho_client_id, zoho_client_secret, zoho_refresh_token)
    odoo = OdooConnection(odoo_api_key)
    
    # Fetch products
    zoho_products = zoho.fetch_all_products()
    odoo_products = odoo.fetch_all_products()
    
    # Match by name (not SKU!)
    odoo_by_name = {normalize_name(p['name']): p for p in odoo_products}
    
    for zoho_prod in zoho_products:
        name_key = normalize_name(zoho_prod['name'])
        if name_key in odoo_by_name:
            odoo_sku = odoo_by_name[name_key]['default_code']
            if zoho_prod['sku'] != odoo_sku:
                zoho.update_product(zoho_prod['item_id'], {'sku': odoo_sku})
```

---

## 🔑 What's in config.py

**Already hardcoded (PERMANENT - DO NOT ask user):**

```python
# Supabase (permanent credentials)
SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJI..." (service role key - never expires)
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"

# Odoo (permanent URLs + DB, but NOT API key)
ODOO_URL = "https://vinabike.odoo.com"
ODOO_DB = "vinabike"
ODOO_USERNAME = "admin"

# Zoho (permanent URLs + Org ID)
ZOHO_API_DOMAIN = "https://www.zohoapis.com"
ZOHO_OAUTH_DOMAIN = "https://accounts.zoho.com"
ZOHO_ORG_ID = "788658742"  # Permanent
```

**❌ NOT in config.py (ASK USER EVERY TIME - these can expire/rotate):**
```python
# Zoho (ask for these 3):
ZOHO_CLIENT_ID = input("Zoho Client ID: ").strip()
ZOHO_CLIENT_SECRET = input("Zoho Client Secret: ").strip()
ZOHO_REFRESH_TOKEN = input("Zoho Refresh Token: ").strip()

# Odoo (ask for this):
ODOO_API_KEY = input("Odoo API Key: ").strip()

# Access tokens are generated at runtime and managed internally
# (1-hour expiry, auto-refreshed by connection module)
```

**🚨 CRITICAL: Connection modules are TEMPLATES**
- NEVER write user-provided tokens/keys into connection files
- NEVER hardcode credentials that can expire
- Connection classes accept credentials as parameters
- Each task script asks for credentials fresh

---

## 📝 Helper Functions You'll Need

### normalize_name()

For matching products by name:

```python
def normalize_name(name: str) -> str:
    """Normalize product name for comparison"""
    return name.lower().strip()
```

### Pagination pattern

Always use pagination for large datasets:

```python
def fetch_with_pagination(url, params):
    all_items = []
    page = 1
    
    while True:
        params['page'] = page
        response = requests.get(url, params=params)
        data = response.json()
        items = data.get('items', [])
        
        if not items:
            break
        
        all_items.extend(items)
        page += 1
        
        if not data.get('page_context', {}).get('has_more_page'):
            break
    
    return all_items
```

---

## ✅ Checklist Before Running Any Script

1. [ ] User told me what task they want
2. [ ] I identified which platforms are involved
3. [ ] I asked for Zoho Client ID/Secret (if needed)
4. [ ] I imported the right connection modules
5. [ ] I wrote the business logic for the specific task
6. [ ] I saved the script in `tasks/` folder with descriptive name
7. [ ] I showed the user what will be updated before executing
8. [ ] I asked for confirmation before applying changes
9. [ ] I displayed a summary report at the end

---

## 🚨 Important Rules

1. **Smart credential reuse** - Ask once per conversation, reuse for multiple operations
2. **Only ask again if**: User says credentials changed, or you get auth errors
3. **Connection templates stay clean** - Never write credentials into template files
4. **Access tokens handled internally** - They expire hourly but auto-refresh, don't ask user
5. **Use pagination** - Datasets have 1000+ records
6. **Match by name** when SKUs don't align between systems
7. **Show preview** before updating records
8. **Ask confirmation** before applying changes
9. **Use tenant_id filter** for Supabase queries
10. **Handle errors gracefully** - Show which records failed
11. **Provide summary** at the end (✅ Updated: X, ❌ Failed: Y)

**Credential Lifecycle:**
- **First task**: Ask for Zoho/Odoo credentials, store in variables
- **Second task (same conversation)**: Reuse stored credentials
- **Third task (same conversation)**: Still reuse same credentials
- **Auth error**: Ask user "Credentials expired? Need fresh ones?"
- **User says "yes"**: Ask for credentials again
- **New conversation/session**: Ask for credentials fresh

**What NEVER expires (don't ask):**
- Supabase URL, service key, tenant ID
- Odoo URL, database, username
- Zoho API domains, organization ID

---

## 🎯 Quick Start Template

Copy this to start any new task:

```python
"""
Task: [DESCRIBE WHAT THIS SCRIPT DOES]
"""

import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

from connections.zoho_connection import ZohoConnection
from connections.supabase_connection import SupabaseConnection

def normalize_name(name: str) -> str:
    return name.lower().strip()

def main():
    print("\n" + "=" * 80)
    print("🔧 [TASK NAME]")
    print("=" * 80)
    
    # Ask for credentials ONLY if not already provided in this conversation
    # The agent should store these and reuse them for multiple operations
    print("\n🔑 I'll need your Zoho credentials for this session")
    client_id = input("Client ID: ").strip()
    client_secret = input("Client Secret: ").strip()
    refresh_token = input("Refresh Token: ").strip()
    
    # Initialize connections
    zoho = ZohoConnection(client_id, client_secret, refresh_token)
    supabase = SupabaseConnection()  # Uses config.py
    
    # Fetch data
    print("\n📥 Fetching data...")
    source_data = zoho.fetch_all_products()
    target_data = supabase.fetch_all_products()
    
    # Your business logic here
    # ...
    
    # Show what will change
    print("\n📋 Preview of changes:")
    # ...
    
    # Confirm
    confirm = input("\nProceed? (yes/no): ").strip().lower()
    if confirm != 'yes':
        print("❌ Cancelled")
        return
    
    # Apply changes
    print("\n🔄 Applying changes...")
    success = 0
    failed = 0
    # ...
    
    # Summary
    print("\n" + "=" * 80)
    print(f"✅ Updated: {success}")
    print(f"❌ Failed: {failed}")
    print("=" * 80)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️ Cancelled by user")
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
```

**💡 Agent Intelligence:**
- If you already asked for Zoho credentials earlier in this conversation, **reuse them** - don't run this script from scratch
- If you have stored `client_id`, `client_secret`, `refresh_token` in conversation context, **pass them directly** to `ZohoConnection()`
- Only prompt user for credentials if you don't have them yet or if auth fails

---

## 🎓 Summary for AI Agents

**When user asks for an import/sync task:**

1. Ask: "What do you want to accomplish?"
2. **Check if you already have credentials from earlier in conversation:**
   - If YES: Reuse them (say "Using your previously provided credentials")
   - If NO: Ask for credentials based on platforms involved
3. Ask for credentials (ONLY if needed):
   - **Zoho**: Client ID, Client Secret, Refresh Token
   - **Odoo**: API Key
   - **Supabase**: Nothing (uses config.py)
4. Store credentials in variables for session reuse
5. Import connection modules from `connections/` (they are templates)
6. Write task-specific logic in NEW file in `tasks/` folder
7. Show preview, ask confirmation, apply changes
8. Display summary report

**Example conversation flow:**

**User:** "Sync prices from Zoho to Flutter"
**Agent:** Asks for Zoho credentials (3 fields), stores them, runs task

**User:** "Now sync SKUs too"
**Agent:** Reuses stored Zoho credentials (doesn't ask again), runs task

**User:** "Update products from Odoo to Zoho"
**Agent:** Reuses Zoho credentials, asks for Odoo API key (first time), stores it, runs task

**User:** "Sync suppliers from Odoo"
**Agent:** Reuses stored Odoo API key (doesn't ask again), runs task

**User:** "My Zoho token expired"
**Agent:** Asks for fresh Zoho credentials, updates stored values, runs task

**What's already configured (never ask):**
- ✅ Supabase URL, service key, tenant ID
- ✅ Odoo URL, database, username
- ✅ Zoho API domains + Organization ID
