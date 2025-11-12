# Zoho Import Scripts

⚠️ **CRITICAL: READ THIS ENTIRE FILE BEFORE TOUCHING ANY SCRIPTS!** ⚠️

Python scripts for importing data from Zoho Inventory/Books to Supabase.

---

## 🎯 WHAT YOU NEED TO PROVIDE (USER INPUT REQUIRED)

**Before running ANY script, you MUST have:**

1. **Zoho Client ID** - Get from Zoho API Console
2. **Zoho Client Secret** - Get from Zoho API Console  
3. **Zoho Grant Token** - Generate from Zoho API Console (expires in 10 min!)
4. **Supabase Service Role Key** - Get from Supabase Dashboard > Settings > API

**Once you have these 4 things, follow the Quick Start section below.**

---

## 📁 File Overview

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `import_all_zoho_products.py` | ⭐ **BULK IMPORT: ALL products + images** | Factory reset → fresh database (1,440 products) |
| `zoho_to_supabase_import.py` | **Image-only import** | Products exist, need images only |
| `import_two_products_with_images.py` | Test import (2 products) | Testing/debugging import logic |
| `step1_get_zoho_tokens.py` | OAuth token exchange | First-time setup only |
| `refresh_zoho_token.py` | Get fresh access token | When access token expires |
| `check_supabase_buckets.py` | Verify storage buckets | Before running imports |
| `list_products_without_images.py` | Report unmatched products | After import to review results |
| `step2_download_images.py` | Legacy: Download only | Not needed (use main script) |
| `import_zoho_images.py` | Legacy: Old approach | Deprecated |

## 🚀 Quick Start

### Prerequisites
```bash
pip3 install requests supabase-py
```

### STEP 1: Get Zoho OAuth Tokens (REQUIRED FIRST!)

**YOU MUST RUN THIS FIRST - NOTHING ELSE WILL WORK WITHOUT TOKENS!**

```bash
python3 step1_get_zoho_tokens.py
```

**When prompted, provide:**
- ✅ Zoho Client ID (from Zoho API Console)
- ✅ Zoho Client Secret (from Zoho API Console)
- ✅ Zoho Grant Token (generate fresh one, expires in 10 min!)

**Output:** You'll get a `refresh_token` - **SAVE THIS!** You need it for all other scripts.

**⚠️ If grant token expires before you run this, generate a new one from Zoho API Console!**

---

### STEP 2: Verify Supabase Storage
---

### STEP 2: Verify Supabase Storage

```bash
python3 check_supabase_buckets.py
```
- Ensure `vinabike-assets` bucket exists
- If not, create it in Supabase Dashboard: Storage > New Bucket > `vinabike-assets` (public)

---

### STEP 3: Update Main Script with Tokens

**Edit `zoho_to_supabase_import.py` and update these lines:**

```python
# Line ~20: Paste your refresh_token from Step 1
ZOHO_REFRESH_TOKEN = "1000.xxxxx.xxxxx"  # ← UPDATE THIS!

# Line ~30: Paste your Supabase service role key
SUPABASE_KEY = "eyJhbGc..."  # ← UPDATE THIS!
```

**⚠️ DO NOT commit these tokens to git! Add to .gitignore!**

---

### STEP 4: Run Import

**OPTION A: Bulk Import (ALL 1,440 Products) - Recommended for Factory Reset**

```bash
python3 import_all_zoho_products.py
```

**Features:**
- ✅ Imports ALL products from Zoho (1,440 products)
- ✅ Includes name, SKU, price, cost, stock quantities
- ✅ Downloads and uploads images to Storage
- ✅ Skips existing products (idempotent)
- ✅ Progress reporting (every 50 products)
- ✅ **Does NOT import categories** (use Odoo for that)

**Expected runtime:** 10-20 minutes for full import

**Use when:**
- Fresh database after factory reset
- Initial production data migration
- Bulk product catalog setup

---

**OPTION B: Image-Only Import (For Existing Products)**

```bash
python3 zoho_to_supabase_import.py
```

**Output:**
- Console progress (real-time)
- `unmatched_products.csv` (products not found in Zoho)
- Updated product records in Supabase

**Use when:**
- Products already exist in Supabase
- Only need to add/update images

## 🔧 Configuration

Edit these variables in each script:

```python
# Zoho Configuration
ZOHO_CLIENT_ID = "your_client_id"
ZOHO_CLIENT_SECRET = "your_client_secret"
ZOHO_REFRESH_TOKEN = "your_refresh_token"
ZOHO_ORG_ID = "788658742"
ZOHO_REGION = "com"  # US region

# Supabase Configuration
SUPABASE_URL = "https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_KEY = "your_service_role_key"  # Service role for imports
SUPABASE_TENANT_ID = "5443b130-cc28-45af-a420-cd500b288890"
SUPABASE_BUCKET = "vinabike-assets"
```

## 📊 Expected Results

### Success Output:
```
======================================================================
📊 IMPORT SUMMARY
======================================================================
✅ Successfully imported: 51
❌ Errors: 0
📦 Total matched: 51/81
======================================================================
```

### Generated Files:
- `unmatched_products.csv` - Products in Supabase not found in Zoho
- `temp_zoho_images/` - Temporary download folder (auto-cleaned)

## 🔍 Troubleshooting

### Error: "Access token expired"
```bash
python3 refresh_zoho_token.py
# Use the new access token or refresh token
```

### Error: "Bucket not found"
- Verify bucket exists: `python3 check_supabase_buckets.py`
- Create in Supabase Dashboard: Storage > New bucket > `vinabike-assets` (public)

### Error: "Row Level Security policy"
- Use **service role key** (not anon key)
- Get from: Supabase Dashboard > Settings > API > Service Role Key

### No matches found
- Check if SKUs match between Zoho and Supabase
- Review `unmatched_products.csv` for details
- Try adding products to Zoho or updating SKUs

## 📚 Documentation

See comprehensive guide: [`.github/ZOHO_IMPORT_GUIDE.md`](../../.github/ZOHO_IMPORT_GUIDE.md)

- Full import workflow
- AI agent guidelines
- Future import scenarios (customers, invoices, etc.)
- Security best practices

## 🗑️ Cleanup

After successful import:
```bash
# Remove temporary files
rm -rf temp_zoho_images/
rm unmatched_products.csv

# Keep scripts for future imports!
```

## 🔒 Security

⚠️ **Never commit credentials to git!**

Add to `.gitignore`:
```
scripts/zoho_import/*.env
scripts/zoho_import/temp_*
scripts/zoho_import/*_backup*
scripts/zoho_import/*.csv
```

Store sensitive data in environment variables or `.env` files.
