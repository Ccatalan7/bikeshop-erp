# Zoho Import Scripts

Python scripts for importing data from Zoho Inventory/Books to Supabase.

## 📁 File Overview

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `zoho_to_supabase_import.py` | **Main import pipeline** | Complete product image import (recommended) |
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

### First-Time Setup

1. **Get Zoho OAuth tokens:**
   ```bash
   python3 step1_get_zoho_tokens.py
   ```
   - Provide: Client ID, Client Secret, Grant Code
   - Save the `refresh_token` output

2. **Verify Supabase storage:**
   ```bash
   python3 check_supabase_buckets.py
   ```
   - Ensure `vinabike-assets` bucket exists

3. **Update credentials in main script:**
   - Edit `zoho_to_supabase_import.py`
   - Set: `ZOHO_REFRESH_TOKEN`, `SUPABASE_KEY` (service role)

### Run Import

```bash
python3 zoho_to_supabase_import.py
```

**Output:**
- Console progress (real-time)
- `unmatched_products.csv` (products not found in Zoho)
- Updated product records in Supabase

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
