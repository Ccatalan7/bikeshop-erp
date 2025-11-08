# 🎯 Zoho Import Quick Reference

**One-page cheat sheet for AI agents implementing import with stock tracking**

---

## 🚀 Running an Import

```bash
cd scripts/zoho_import
python3 test_import_with_tracking.py  # ← USE THIS (with stock tracking)
```

---

## � Critical Pattern: Single-Transaction RPC

### ❌ WRONG (Doesn't Work)
```python
# Separate calls = separate transactions = context lost
client.rpc('set_config', {...}).execute()  # Transaction 1
client.table('products').update({...}).execute()  # Transaction 2 ❌
```

### ✅ CORRECT (Production-Tested)
```python
# Single RPC = single transaction = trigger sees context
client.rpc('import_product_with_context', {
    'p_tenant_id': tenant_id,
    'p_sku': sku,
    'p_product_data': {...},
    'p_import_reference': f"import_{timestamp}",
    'p_import_reason': 'Zoho Import'
}).execute()  # ✅ Everything in ONE transaction
```

**Why:** Supabase Python client treats each call as separate HTTP request (separate transaction). Session variables ONLY persist within a transaction.

---

## 🤖 AI Agent Rules

### ✅ ALWAYS DO (Automatic)
- **Use RPC functions for imports** (bundle context + update in ONE transaction)
- **Generate import reference:** `f"import_{int(time.time() * 1000)}"`
- **Authenticate with email/password** (get tenant_id from user_profiles)
- **Filter by tenant_id** (multi-tenant isolation)
- **Only update changed fields** (use coalesce pattern in RPC)
- **Verify stock adjustments created** (query by import_reference)

### ❌ NEVER DO
- **Separate set_config + update calls** (loses context across transactions)
- **Direct table updates without RPC** (bypasses import tracking)
- **Hardcode tenant_id** (fetch from auth context)
- **Skip import_reference** (needed for audit trail)
- **Update unchanged stock** (trigger prevents ghost records)

### ❓ ONLY ASK USER FOR
- **Email/password for authentication** (first time per session)
- **Zoho credentials** (Client ID/Secret/Grant Code - first time only)
- **Business decisions** ("Skip unmatched?" - only if ambiguous)

---

## 📋 Import Checklist

Before ANY import:

- [ ] **1. Database RPC exists?**
  - [ ] Check `core_schema.sql` for `import_{table}_with_context()` function
  - [ ] If missing, create following template (see IMPORT_STOCK_TRACKING_GUIDE.md)
  - [ ] Grant execute to `authenticated` role
  
- [ ] **2. Stock tracking trigger exists?**
  - [ ] For products: `track_product_stock_changes()` (already exists)
  - [ ] For other tables: create similar trigger if needed
  
- [ ] **3. Python script ready?**
  - [ ] Use `test_import_with_tracking.py` as template
  - [ ] Replace table name, columns, unique identifier
  - [ ] Test with small CSV first

---

## 🔧 Quick Start Template

```python
from supabase import create_client
import pandas as pd
import time

# 1. Initialize & authenticate
client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
auth_response = client.auth.sign_in_with_password({
    "email": "user@example.com",
    "password": "password"
})

# 2. Get tenant_id
tenant_id = client.table('user_profiles') \
    .select('tenant_id') \
    .eq('id', auth_response.user.id) \
    .single().execute().data['tenant_id']

# 3. Generate import reference
import_ref = f"import_{int(time.time() * 1000)}"

# 4. Import each record
df = pd.read_csv('data.csv')
for _, row in df.iterrows():
    result = client.rpc('import_{table}_with_context', {
        'p_tenant_id': tenant_id,
        'p_unique_id': row['sku'],  # or email, invoice_number, etc.
        'p_{table}_data': {
            'column1': row['column1'],
            'column2': row['column2']
        },
        'p_import_reference': import_ref,
        'p_import_reason': f'Import: {row["sku"]}'
    }).execute()
    
    print(f"✅ {row['sku']}" if result.data['updated_count'] > 0 else f"⚠️ {row['sku']}")

# 5. Verify
adjustments = client.table('stock_adjustments') \
    .select('*') \
    .eq('reference', import_ref) \
    .execute()
print(f"📝 Created {len(adjustments.data)} adjustments")
```

---

## 📊 Common Scenarios

| Data Type | RPC Function | Match By | Special Handling |
|-----------|--------------|----------|------------------|
| Products ✅ | `import_product_with_context()` | SKU | Stock tracking automatic |
| Customers | `import_customer_with_context()` | Email | Create if not exists |
| Suppliers | `import_supplier_with_context()` | Email/Tax ID | Validate before import |
| Invoices | `import_invoice_with_context()` | invoice_number | Create line items separately |

✅ = Implemented | Others = Use template to create

---

## 🛠️ Troubleshooting

| Error | Fix |
|-------|-----|
| `function does not exist` | Create RPC function in `core_schema.sql` |
| `updated_count = 0` | Product/record doesn't exist (check unique ID) |
| No stock adjustments | Check trigger exists and fires |
| "Ajuste Manual" label | RPC not used (context not set) |
| Context not detected | Separate calls used (must be ONE transaction) |

---

## 📁 File Locations

- **Guide (Full):** `.github/IMPORT_STOCK_TRACKING_GUIDE.md`
- **Quick Ref:** `.github/ZOHO_IMPORT_QUICKREF.md` (this file)
- **Database Schema:** `supabase/sql/core_schema.sql` (lines 1656-1720, 863-958)
- **Working Script:** `scripts/zoho_import/test_import_with_tracking.py`
- **Test Data:** `scripts/zoho_import/test_products.csv`

---

## 🎓 Remember

1. **ONE RPC call = ONE transaction** (session variables visible to trigger)
2. **Separate calls = separate transactions** (context lost between calls)
3. **Always generate import_reference** (enables audit trail)
4. **Always include tenant_id** (multi-tenant isolation)
5. **Coalesce pattern preserves unchanged fields** (only updates what's provided)

**This pattern is PRODUCTION-VERIFIED as of Nov 8, 2025.**

