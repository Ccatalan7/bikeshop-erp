# 🔧 TROUBLESHOOTING FLOWCHART

**Quick visual guide to diagnose and fix common issues**

---

## 🚨 Problem: "DNS resolution failed" or "Connection refused"

```
┌──────────────────────────┐
│ DNS/Connection Error     │
└────────┬─────────────────┘
         │
         ▼
    ┌────────────────────┐
    │ Which platform?    │
    └────────┬───────────┘
             │
    ┌────────┴─────────┐
    │                  │
    ▼                  ▼
┌─────────┐      ┌──────────┐
│ SUPABASE│      │ ODOO/ZOHO│
└────┬────┘      └────┬─────┘
     │                │
     ▼                ▼
┌─────────────────────────┐   ┌──────────────────────┐
│ Check URL format:       │   │ Check URL format:    │
│ https://PROJECT.        │   │ https://company.     │
│ supabase.co             │   │ odoo.com             │
│                         │   │ https://books.       │
│ ❌ Wrong:               │   │ zoho.com             │
│ http://...              │   │                      │
│ .../rest/v1             │   │ ❌ Wrong:            │
│                         │   │ http://... (not s)   │
│ ✅ Correct:             │   │ /api endpoint        │
│ https://xzdvtz...       │   │                      │
│ supabase.co             │   │ ✅ Correct:          │
└─────────────────────────┘   │ https://vinabike.    │
                              │ odoo.com             │
                              └──────────────────────┘
```

**Fix:**
```bash
# Test DNS resolution
nslookup xzdvtzdqjeyqxnkqprtf.supabase.co

# Should return IP address
# If NXDOMAIN → Wrong project reference!
```

---

## 🚨 Problem: "Authentication failed" or "Invalid credentials"

```
┌────────────────────────────┐
│ Authentication Failed      │
└────────┬───────────────────┘
         │
         ▼
    ┌─────────────────┐
    │ Which platform? │
    └────────┬────────┘
             │
    ┌────────┴─────────────┐
    │                      │
    ▼                      ▼
┌──────────┐         ┌──────────┐
│ SUPABASE │         │ ODOO     │
└────┬─────┘         └────┬─────┘
     │                    │
     ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│ Using which key?│  │ Using API key?  │
└────┬────────────┘  └────┬────────────┘
     │                    │
┌────┴────┐          ┌────┴─────┐
│ anon?   │          │ Password?│
└────┬────┘          └────┬─────┘
     │                    │
     ▼                    ▼
┌──────────────────┐ ┌─────────────────────┐
│ ❌ Anon key has  │ │ ❌ Password doesn't │
│ limited access!  │ │ work for API!       │
│                  │ │                     │
│ ✅ Use SERVICE_  │ │ ✅ Generate API key │
│ ROLE key from    │ │ in Odoo settings:   │
│ dashboard        │ │ • My Profile        │
└──────────────────┘ │ • Preferences       │
                     │ • API Keys          │
                     │ • Create            │
                     └─────────────────────┘
```

**Fix for Supabase:**
```python
# Wrong key type
SUPABASE_KEY = "eyJhbGci...anon..."  # ❌

# Correct key type
SUPABASE_KEY = "eyJhbGci...service_role..."  # ✅
```

**Fix for Odoo:**
```python
# Wrong authentication
password = "your_password"  # ❌

# Correct authentication
api_key = "generated_from_odoo_settings"  # ✅
```

---

## 🚨 Problem: "Returned 0 products" or "Empty results"

```
┌──────────────────────────┐
│ Empty Results            │
└────────┬─────────────────┘
         │
         ▼
    ┌──────────────────────┐
    │ Check tenant_id      │
    └────────┬─────────────┘
             │
             ▼
    ┌────────────────────────────┐
    │ Query all tenants:         │
    │ SELECT * FROM tenants;     │
    └────────┬───────────────────┘
             │
    ┌────────▼─────────┐
    │ Found tenants?   │
    └────────┬─────────┘
             │
      ┌──────┴──────┐
      │             │
     YES           NO
      │             │
      │             ▼
      │   ┌──────────────────┐
      │   │ Database issue!  │
      │   │ Check connection │
      │   └──────────────────┘
      │
      ▼
┌──────────────────────────────┐
│ Compare tenant_id in:        │
│ • config.py                  │
│ • Database query result      │
└────────┬─────────────────────┘
         │
    ┌────▼────┐
    │ Match?  │
    └────┬────┘
         │
  ┌──────┴──────┐
  │             │
 YES           NO
  │             │
  │             ▼
  │   ┌──────────────────────┐
  │   │ ❌ Using wrong       │
  │   │ tenant_id!           │
  │   │                      │
  │   │ ✅ Update config.py  │
  │   │ with correct UUID    │
  │   └──────────────────────┘
  │
  ▼
┌────────────────────────┐
│ Check RLS policies     │
│ (if using anon key)    │
└────────────────────────┘
```

**Fix:**
```python
# Find your tenant
client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
tenants = client.table("tenants").select("*").execute()
for tenant in tenants.data:
    print(f"Shop: {tenant['shop_name']}, ID: {tenant['id']}")

# Copy correct ID to config.py
TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"  # Vinabike
```

---

## 🚨 Problem: "Invalid number format" or "Could not convert string to float"

```
┌──────────────────────────┐
│ Number Parsing Error     │
└────────┬─────────────────┘
         │
         ▼
    ┌─────────────────────────┐
    │ Which number format?    │
    └────────┬────────────────┘
             │
    ┌────────┴─────────┐
    │                  │
    ▼                  ▼
┌──────────┐      ┌──────────┐
│ Chilean  │      │ US       │
└────┬─────┘      └────┬─────┘
     │                 │
     ▼                 ▼
┌─────────────┐   ┌──────────────┐
│ "1.500,00"  │   │ "1,500.00"   │
└─────┬───────┘   └──────┬───────┘
      │                  │
      ▼                  ▼
┌─────────────────────────────┐
│ Use parse_chilean_number()  │
│ • Removes dots              │
│ • Replaces comma with dot   │
│ • Converts to float         │
└─────────────────────────────┘
```

**Fix:**
```python
# Wrong (direct conversion)
price = float("1.500,00")  # ❌ ValueError!

# Correct (use helper)
from config import parse_chilean_number
price = parse_chilean_number("1.500,00")  # ✅ 1500.0
```

---

## 🚨 Problem: "Missing categories" or "Only got X of Y"

```
┌────────────────────────────┐
│ Missing Categories         │
└────────┬───────────────────┘
         │
         ▼
    ┌──────────────────────────┐
    │ Check Odoo query filter  │
    └────────┬─────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Are you filtering categories    │
│ by product assignments?         │
└────────┬────────────────────────┘
         │
    ┌────▼────┐
    │ Filter? │
    └────┬────┘
         │
  ┌──────┴──────┐
  │             │
 YES           NO
  │             │
  ▼             │
┌───────────────────────────┐    │
│ ❌ Problem found!         │    │
│ Some categories have no   │    │
│ products assigned yet     │    │
│                           │    │
│ ✅ Fetch ALL categories:  │    │
│ models.execute_kw(        │    │
│   'product.category',     │    │
│   'search_read',          │    │
│   [[]]  ← Empty filter!   │    │
│ )                         │    │
└───────────────────────────┘    │
                                 │
                                 ▼
                          ┌──────────────┐
                          │ Check other  │
                          │ issues below │
                          └──────────────┘
```

**Fix:**
```python
# Wrong (only categories with products)
product_category_ids = set(p['categ_id'][0] for p in products)
categories = models.execute_kw(
    'product.category', 'search_read',
    [[['id', 'in', list(product_category_ids)]]]
)

# Correct (all categories)
categories = models.execute_kw(
    'product.category', 'search_read',
    [[]]  # Empty filter = fetch all
)
```

---

## 🚨 Problem: "Only fetched 1000 products" (Pagination)

```
┌────────────────────────────┐
│ Pagination Issue           │
└────────┬───────────────────┘
         │
         ▼
    ┌──────────────────────────┐
    │ Using pagination loop?   │
    └────────┬─────────────────┘
             │
      ┌──────┴──────┐
      │             │
     YES           NO
      │             │
      │             ▼
      │   ┌──────────────────────┐
      │   │ ❌ Default limit:    │
      │   │ 1000 rows            │
      │   │                      │
      │   │ ✅ Add pagination:   │
      │   │ while True:          │
      │   │   response = client  │
      │   │     .range(offset,   │
      │   │            offset+   │
      │   │            BATCH-1)  │
      │   │   if len < BATCH:    │
      │   │     break            │
      │   │   offset += BATCH    │
      │   └──────────────────────┘
      │
      ▼
┌────────────────────────────┐
│ Check break condition      │
└────────┬───────────────────┘
         │
         ▼
    ┌─────────────────────────┐
    │ Break when:             │
    │ • len(response) == 0    │
    │ • len(response) < BATCH │
    └─────────────────────────┘
```

**Fix:**
```python
# Wrong (only first page)
products = client.table("products").select("*").execute()

# Correct (all pages)
offset = 0
BATCH_SIZE = 1000
all_products = []
while True:
    response = client.table("products")\
        .select("*")\
        .eq("tenant_id", TENANT_ID)\
        .range(offset, offset + BATCH_SIZE - 1)\
        .execute()
    
    all_products.extend(response.data)
    
    if len(response.data) < BATCH_SIZE:
        break  # Last page
    
    offset += BATCH_SIZE
```

---

## 🚨 Problem: "Rate limit exceeded" or "429 Too Many Requests"

```
┌────────────────────────────┐
│ Rate Limit Exceeded        │
└────────┬───────────────────┘
         │
         ▼
    ┌──────────────────────────┐
    │ Which API?               │
    └────────┬─────────────────┘
             │
    ┌────────┴─────────┐
    │                  │
    ▼                  ▼
┌─────────┐      ┌──────────┐
│ ZOHO    │      │ ODOO     │
└────┬────┘      └────┬─────┘
     │                │
     │                ▼
     │           ┌──────────────────┐
     │           │ Usually no limit │
     │           │ (self-hosted)    │
     │           └──────────────────┘
     │
     ▼
┌────────────────────────────────┐
│ Zoho limits:                   │
│ • 10 requests/second           │
│ • 100 requests/minute          │
│ • 3000 requests/day            │
└────────┬───────────────────────┘
         │
         ▼
    ┌──────────────────┐
    │ Add delays:      │
    │ time.sleep(0.15) │
    │ per request      │
    └──────────────────┘
```

**Fix:**
```python
import time

# Add delay between requests
for item in zoho_items:
    process_item(item)
    time.sleep(0.15)  # 150ms = ~6 requests/second (safe)

# Or use batch processing
BATCH_SIZE = 50  # Process in chunks
for i in range(0, len(items), BATCH_SIZE):
    batch = items[i:i+BATCH_SIZE]
    process_batch(batch)
    time.sleep(1)  # 1 second between batches
```

---

## 🚨 Problem: "Category hierarchy broken" or "Parent not found"

```
┌────────────────────────────┐
│ Hierarchy Issue            │
└────────┬───────────────────┘
         │
         ▼
    ┌──────────────────────────┐
    │ Check creation order     │
    └────────┬─────────────────┘
             │
             ▼
┌───────────────────────────────┐
│ Are you creating parents      │
│ before children?              │
└────────┬──────────────────────┘
         │
    ┌────▼────┐
    │ Order?  │
    └────┬────┘
         │
  ┌──────┴──────┐
  │             │
 YES           NO
  │             │
  │             ▼
  │   ┌──────────────────────┐
  │   │ ❌ Wrong order!      │
  │   │                      │
  │   │ ✅ Sort by level:    │
  │   │ categories.sort(     │
  │   │   key=lambda x:      │
  │   │   x['level']         │
  │   │ )                    │
  │   │                      │
  │   │ Process level 0,     │
  │   │ then 1, then 2...    │
  │   └──────────────────────┘
  │
  ▼
┌────────────────────────────┐
│ Check UUID mapping         │
│ Odoo ID → Supabase UUID    │
└────────────────────────────┘
```

**Fix:**
```python
# Wrong (random order)
for category in categories:
    create_category(category)  # Child might come before parent!

# Correct (level order)
categories_by_level = sorted(categories, key=lambda x: x['level'])
category_map = {}  # Odoo ID → Supabase UUID

for category in categories_by_level:
    # Parent created first (lower level)
    parent_uuid = category_map.get(category['parent_id'])
    
    result = client.table("product_categories").insert({
        "name": category['name'],
        "parent_id": parent_uuid,
        "level": category['level']
    }).execute()
    
    category_map[category['id']] = result.data[0]['id']
```

---

## 🚨 Problem: "Script hangs" or "No progress"

```
┌────────────────────────────┐
│ Script Hanging             │
└────────┬───────────────────┘
         │
         ▼
    ┌──────────────────────────┐
    │ Check for:               │
    └────────┬─────────────────┘
             │
    ┌────────┴─────────────┐
    │                      │
    ▼                      ▼
┌──────────┐         ┌──────────┐
│ Infinite │         │ Blocking │
│ Loop?    │         │ I/O?     │
└────┬─────┘         └────┬─────┘
     │                    │
     ▼                    ▼
┌─────────────────┐  ┌──────────────────┐
│ Check break     │  │ Check timeouts   │
│ conditions:     │  │ in API calls     │
│ • while True    │  │                  │
│ • for loop end  │  │ Add timeout:     │
│ • Exit flag     │  │ requests.get(    │
│                 │  │   timeout=30     │
│ Add progress:   │  │ )                │
│ print(i/total)  │  └──────────────────┘
└─────────────────┘
```

**Fix:**
```python
# Add progress indicators
total = len(items)
for i, item in enumerate(items):
    process_item(item)
    
    # Progress every 100 items
    if (i + 1) % 100 == 0:
        print(f"Progress: {i+1}/{total} ({(i+1)/total*100:.1f}%)")

# Add timeouts to API calls
import requests
response = requests.get(url, timeout=30)  # 30 second timeout
```

---

## 📊 Quick Diagnostic Commands

**Check Supabase connection:**
```bash
python3 -c "
from supabase import create_client
import sys
try:
    client = create_client('YOUR_URL', 'YOUR_KEY')
    result = client.table('tenants').select('count').execute()
    print('✅ Connected! Tenants:', len(result.data))
except Exception as e:
    print('❌ Error:', e)
    sys.exit(1)
"
```

**Check Odoo connection:**
```bash
python3 -c "
import xmlrpc.client
try:
    common = xmlrpc.client.ServerProxy('https://vinabike.odoo.com/xmlrpc/2/common')
    uid = common.authenticate('vinabike', 'vinabikechile@gmail.com', 'API_KEY', {})
    print('✅ Connected! User ID:', uid)
except Exception as e:
    print('❌ Error:', e)
"
```

**Check Zoho token:**
```bash
python3 -c "
import requests
response = requests.post('https://accounts.zoho.com/oauth/v2/token', data={
    'refresh_token': 'YOUR_REFRESH_TOKEN',
    'client_id': 'YOUR_CLIENT_ID',
    'client_secret': 'YOUR_CLIENT_SECRET',
    'grant_type': 'refresh_token'
})
if response.status_code == 200:
    print('✅ Token valid!')
else:
    print('❌ Token error:', response.text)
"
```

---

**Still stuck? Check `AI_AGENT_GUIDE.md` section "Common Errors and Solutions"**
