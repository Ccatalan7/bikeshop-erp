# 🧾 Zoho Books Accounting Import - Quick Start

**Import sales invoices, purchase invoices, journal entries, and expenses from Zoho Books**

---

## 📋 Prerequisites

You'll need these credentials from Zoho Books:

### 1. Zoho OAuth Credentials

**Get from:** https://api-console.zoho.com/

1. Click "Add Client" → "Server-based Applications"
2. Fill in:
   - Client Name: `Bikeshop ERP Import`
   - Homepage URL: `http://localhost`
   - Authorized Redirect URIs: `http://localhost:8000/oauth/callback`
3. Click "Create"
4. Copy **Client ID** and **Client Secret**

### 2. Generate Refresh Token

1. Open this URL in browser (replace YOUR_CLIENT_ID):
   ```
   https://accounts.zoho.com/oauth/v2/auth?scope=ZohoBooks.fullaccess.all&client_id=YOUR_CLIENT_ID&response_type=code&access_type=offline&redirect_uri=http://localhost:8000/oauth/callback
   ```

2. Authorize the app → You'll be redirected to a URL like:
   ```
   http://localhost:8000/oauth/callback?code=1000.xxxxx.yyyyy
   ```

3. Copy the `code` parameter value

4. Exchange code for refresh token:
   ```bash
   curl -X POST "https://accounts.zoho.com/oauth/v2/token" \
     -d "code=YOUR_CODE" \
     -d "client_id=YOUR_CLIENT_ID" \
     -d "client_secret=YOUR_CLIENT_SECRET" \
     -d "redirect_uri=http://localhost:8000/oauth/callback" \
     -d "grant_type=authorization_code"
   ```

5. Copy the `refresh_token` from response

### 3. Organization ID

**Get from:** Zoho Books → Settings → Organization → Organization ID

---

## 🚀 Setup Steps

### Step 1: Create config.py

```bash
cd /Users/Claudio/Dev/bikeshop-erp/scripts/import_templates
cp config.template.py config.py
```

### Step 2: Fill in Credentials

Edit `config.py`:

```python
# Supabase (from dashboard)
SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = "eyJhbGci..."
TENANT_ID = "your-tenant-uuid-here"

# Zoho Books
ZOHO_CLIENT_ID = "1000.XXXXXXXXXXXX"
ZOHO_CLIENT_SECRET = "your_client_secret"
ZOHO_REFRESH_TOKEN = "1000.xxxx.yyyy"
ZOHO_ORG_ID = "123456789"
ZOHO_API_DOMAIN = "https://www.zohoapis.com"  # or regional variant
```

### Step 3: Install Dependencies

```bash
pip3 install supabase requests python-dateutil
```

### Step 4: Run Import

```bash
python3 sync_zoho_books_accounting.py
```

---

## 📊 What Gets Imported

### Sales Invoices (`sales_invoices` table)
- Invoice number
- Customer (auto-created if doesn't exist)
- Date, due date
- Subtotal, tax, discount, total
- Payment status (draft/posted/paid/cancelled)
- Tax treatment (tax_included/no_tax)
- Line items (if your schema supports it)

### Purchase Invoices (`purchase_invoices` table)
- Bill number → invoice_number
- Supplier (auto-created if doesn't exist)
- Date, due date
- Subtotal, tax, total
- Payment status
- Tax treatment
- Line items

### Journal Entries (`journal_entries` + `journal_lines` tables)
- Entry number
- Date
- Description
- Total amount
- Debit/credit lines
- Account matching by name

### Expenses
- Currently skipped (enable when expense module is ready)

---

## 🎯 Expected Output

```
================================================================================
🧾 ZOHO BOOKS ACCOUNTING DATA IMPORT
================================================================================
📍 Tenant ID: abc123-def456...
🏢 Organization ID: 123456789
================================================================================
✅ Connected to tenant: Vinabike
✅ Zoho Books authentication successful

================================================================================
📥 IMPORTING SALES INVOICES
================================================================================
  📄 Fetching page 1...
  ✅ Fetched 247 items across 2 page(s)
  ✅ Created customer: Juan Pérez
  ✅ Imported: FV-00001 ($125,000)
  ✅ Imported: FV-00002 ($89,500)
  ...

✅ Imported: 247
⏭️  Skipped: 0 (already exist)
❌ Errors: 0

================================================================================
📥 IMPORTING PURCHASE INVOICES (BILLS)
================================================================================
  ✅ Created supplier: Proveedor ABC
  ✅ Imported: FC-00001 ($450,000)
  ...

✅ Imported: 89
⏭️  Skipped: 0 (already exist)
❌ Errors: 0

================================================================================
📥 IMPORTING JOURNAL ENTRIES
================================================================================
  ✅ Imported: AC-00001 ($1,250,000)
  ⚠️  Account not found: Caja Menor - skipping line
  ...

✅ Imported: 156
⏭️  Skipped: 0 (already exist)
❌ Errors: 2

================================================================================
✅ IMPORT COMPLETED SUCCESSFULLY
================================================================================
📊 Summary available in Flutter app
💡 Check Accounting module to verify imported data
```

---

## ⚠️ Important Notes

### 1. Duplicate Prevention
- Script checks for existing invoices/entries by number
- Re-running the script is safe (skips duplicates)

### 2. Customer/Supplier Auto-Creation
- If customer/supplier doesn't exist, it's created automatically
- Matching is done by name
- Review created records in Flutter app after import

### 3. Product Matching
- Line items try to match products by name (fuzzy match)
- If product not found, line item is created without product_id
- Review and fix manually in Flutter app

### 4. Account Matching
- Journal lines match accounts by name
- If account not found, line is skipped with warning
- Ensure your chart of accounts is complete before importing

### 5. Status Mapping
```
Zoho Status        → App Status
----------------   -------------
draft/sent/viewed  → draft
overdue/partially  → posted
paid               → paid
void/cancelled     → cancelled
```

### 6. Tax Treatment
- If tax_total > 0 → `tax_included`
- If tax_total = 0 → `no_tax`

---

## 🔧 Troubleshooting

### Error: "Failed to refresh token"
- Check client_id, client_secret, refresh_token are correct
- Refresh token expires after 3 months if not used
- Generate new refresh token using steps above

### Error: "Tenant XYZ not found"
- Get correct tenant_id from Supabase:
  ```sql
  SELECT id, shop_name FROM tenants;
  ```
- Or from Flutter app user_profiles table

### Error: "Account not found"
- Run chart of accounts import first
- Or create missing accounts manually
- Journal lines with missing accounts are skipped

### Error: "Customer/Supplier creation failed"
- Check RLS policies on customers/suppliers tables
- Ensure service_role_key has permission to insert

---

## 📞 Need Help?

1. Check import logs for specific errors
2. Review TROUBLESHOOTING_FLOWCHART.md
3. Check Zoho Books API status: https://status.zoho.com/

---

**Last Updated:** November 12, 2025  
**Version:** 1.0
