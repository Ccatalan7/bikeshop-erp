# 🎯 Zoho Import Quick Reference

**One-page cheat sheet for AI agents**

## 🚀 Running an Import

```bash
cd scripts/zoho_import
python3 zoho_to_supabase_import.py
```

## 🤖 AI Agent Rules

### ✅ ALWAYS DO (Automatic)
- Read app config from Flutter files
- Fetch database schema automatically
- Use refresh tokens (never ask for new access tokens)
- Try multiple matching strategies (SKU → Name → Fuzzy)
- Auto-detect tenant_id from user_profiles
- Generate CSV reports of unmatched records
- Sanitize filenames (special characters)
- Include tenant_id in ALL inserts

### ❌ NEVER ASK USER FOR
- Supabase URL (read from `lib/shared/config/supabase_config.dart`)
- Database schema (query Supabase)
- Table/column names (read from Flutter models)
- Tenant ID (fetch from user_profiles)
- API endpoint URLs (try standard patterns)
- Access tokens (use refresh token)

### ❓ ONLY ASK USER FOR
- **First-time OAuth:** Client ID, Client Secret, Grant Code (all three, 10-min expiry)
- **Service Role Key:** For RLS bypass (ask once, store)
- **Business decisions:** "Skip unmatched?" "Create new?" (if ambiguous)

## 📋 Import Template (4 Phases)

```python
# Phase 1: Setup (automatic)
config = read_flutter_config()
schema = detect_schema(table_name)
tenant_id = get_tenant_from_auth()

# Phase 2: Extract (automatic)
zoho_data = fetch_all_zoho(endpoint)
supabase_data = fetch_all_supabase(table, tenant_id)

# Phase 3: Match (automatic)
matches = smart_match(zoho_data, supabase_data)
# Try: ID → SKU → Name → Fuzzy

# Phase 4: Import (automatic)
for match in matches:
    data = transform(match)
    data['tenant_id'] = tenant_id  # Always!
    upsert(table, data)
```

## 🔐 Security Checklist

- [ ] Use service role key ONLY for imports
- [ ] Always filter by tenant_id (even with service role)
- [ ] Never hardcode credentials (use env vars)
- [ ] Log all import activities (audit trail)
- [ ] Test with small dataset first (dry run)

## 📊 Common Endpoints

| Data Type | Zoho Endpoint | Match By |
|-----------|---------------|----------|
| Products | `/inventory/v1/items` | SKU → Name |
| Customers | `/inventory/v1/contacts` | Email → Phone |
| Invoices | `/inventory/v1/invoices` | invoice_number |
| Images | `/inventory/v1/documents/{id}` | document_id |
| Suppliers | `/inventory/v1/vendors` | Email → Tax ID |

## 🛠️ Troubleshooting

| Error | Fix |
|-------|-----|
| Access token expired | `python3 refresh_zoho_token.py` |
| Bucket not found | Create in Supabase Dashboard |
| RLS policy block | Use service role key |
| No matches found | Check SKUs match Zoho |
| Special char error | Already handled (sanitize) |

## 📁 File Locations

- **Scripts:** `/scripts/zoho_import/`
- **Guide:** `/.github/ZOHO_IMPORT_GUIDE.md`
- **Config:** Edit variables in each script

## 🎓 Full Documentation

See: [`.github/ZOHO_IMPORT_GUIDE.md`](ZOHO_IMPORT_GUIDE.md)
