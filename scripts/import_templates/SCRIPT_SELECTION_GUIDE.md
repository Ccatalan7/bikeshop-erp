# 📊 SCRIPT SELECTION MATRIX

**Which script should you use? Quick decision guide.**

---

## 🎯 Quick Decision Tree

```
Start here:
  │
  ▼
┌─────────────────────────────────────────┐
│ What do you want to do?                 │
└────────┬────────────────────────────────┘
         │
    ┌────┴─────────────────┐
    │                      │
    ▼                      ▼
┌────────────┐      ┌─────────────┐
│ First-time │      │ Regular     │
│ setup?     │      │ updates?    │
└────┬───────┘      └─────┬───────┘
     │                    │
     ▼                    ▼
Start with          Which data
Odoo sync           needs updating?
     │                    │
     │         ┌──────────┴──────────┐
     │         │                     │
     │         ▼                     ▼
     │    ┌─────────┐         ┌──────────┐
     │    │ Stock & │         │ Compare  │
     │    │ Prices  │         │ systems  │
     │    └────┬────┘         └────┬─────┘
     │         │                   │
     │         ▼                   ▼
     │    Use Zoho         Use Zoho-Odoo
     │    sync             comparison
     │
     ▼
Use Odoo sync
```

---

## 📋 Feature Comparison Table

| Feature | Odoo→Flutter | Zoho→Flutter | Zoho↔Odoo |
|---------|--------------|--------------|-----------|
| **Creates categories** | ✅ Yes (with hierarchy) | ❌ No | ❌ No |
| **Updates product categories** | ✅ Yes | ❌ No | ❌ No |
| **Updates stock quantities** | ⚠️ Optional | ✅ Yes | ⚠️ Compare only |
| **Updates prices** | ⚠️ Optional | ✅ Yes | ⚠️ Compare only |
| **Creates missing products** | ⚠️ Optional | ✅ Yes | ✅ Yes (both directions) |
| **Detects differences** | ❌ No | ❌ No | ✅ Yes |
| **Requires both APIs** | Odoo + Supabase | Zoho + Supabase | Zoho + Odoo |
| **Interactive mode** | ❌ No | ❌ No | ✅ Yes |
| **Best for** | Fresh setup | Stock updates | Reconciliation |

---

## 🎯 Use Case → Script Mapping

### Scenario 1: Fresh Flutter App Setup
**Goal:** Import all products and categories for the first time

**Recommended script:** `sync_odoo_to_flutter.py`

**Why?**
- Creates complete category hierarchy
- Links products to categories
- One-time setup, comprehensive

**Steps:**
1. Run `sync_odoo_to_flutter.py` (imports structure)
2. Optionally run `sync_zoho_to_flutter.py` (updates stock/prices)

---

### Scenario 2: Daily/Weekly Stock Updates
**Goal:** Keep product quantities and prices in sync

**Recommended script:** `sync_zoho_to_flutter.py`

**Why?**
- Zoho is typically the inventory system of record
- Updates stock_quantity, inventory_qty, price, cost
- Fast (no category processing)

**Frequency:** Daily or after significant stock changes

---

### Scenario 3: Finding Data Discrepancies
**Goal:** See which products exist in Zoho vs Odoo, compare prices

**Recommended script:** `sync_zoho_odoo.py`

**Why?**
- Shows side-by-side comparison
- Highlights differences (name, price, stock)
- Interactive: you choose what to sync

**Use when:**
- Migrating between systems
- Auditing data integrity
- Deciding which system is "truth"

---

### Scenario 4: New Product Added in Odoo
**Goal:** Import new products with correct categories

**Recommended script:** `sync_odoo_to_flutter.py`

**Why?**
- Ensures category links are correct
- Imports product structure from Odoo

**Alternative:** Add manually in Flutter, then sync stock from Zoho

---

### Scenario 5: New Product Added in Zoho
**Goal:** Import new product to Flutter

**Options:**
1. **Quick:** `sync_zoho_to_flutter.py` (imports product, no category)
2. **Complete:** Add to Odoo first → `sync_odoo_to_flutter.py` (includes category)

**Decision:**
- If category doesn't matter → Option 1
- If you need category structure → Option 2

---

### Scenario 6: Migrating from Zoho to Odoo
**Goal:** Create products in Odoo that only exist in Zoho

**Recommended script:** `sync_zoho_odoo.py`

**Steps:**
1. Run comparison mode
2. Choose option: "Create missing in Odoo"
3. Review created products
4. Run `sync_odoo_to_flutter.py` to import categories

---

### Scenario 7: Migrating from Odoo to Zoho
**Goal:** Create products in Zoho that only exist in Odoo

**Recommended script:** `sync_zoho_odoo.py`

**Steps:**
1. Run comparison mode
2. Choose option: "Create missing in Zoho"
3. Verify in Zoho Inventory

---

### Scenario 8: Bidirectional Sync (Keep Both Systems Equal)
**Goal:** Zoho and Odoo should have same products

**Recommended script:** `sync_zoho_odoo.py`

**Steps:**
1. Run comparison mode
2. Choose option: "Both directions"
3. Creates missing products in both systems
4. Run `sync_odoo_to_flutter.py` (imports to Flutter)

---

## 🔄 Workflow Combinations

### Complete New Tenant Onboarding

```
Step 1: Categories & Structure
  python3 sync_odoo_to_flutter.py
  → Creates 144 categories
  → Links existing products

Step 2: Stock & Pricing
  python3 sync_zoho_to_flutter.py
  → Updates quantities
  → Updates prices/costs

Step 3: Verify in Flutter App
  → Check products appear
  → Check categories work
  → Check stock is correct
```

---

### Weekly Maintenance Routine

```
Monday: Stock Update
  python3 sync_zoho_to_flutter.py
  → Fresh stock quantities

Friday: Reconciliation Check
  python3 sync_zoho_odoo.py
  → Compare systems
  → Fix discrepancies
```

---

### Emergency: "Products Missing in Flutter!"

```
Step 1: Identify Source
  → Where do products exist?
  → Zoho only? Odoo only? Both?

Step 2: Import from Source
  → If in Odoo: sync_odoo_to_flutter.py
  → If in Zoho: sync_zoho_to_flutter.py
  → If both: Use comparison script first

Step 3: Verify
  → Run SQL query:
    SELECT COUNT(*) FROM products WHERE tenant_id = '...'
```

---

## 📊 Performance Comparison

| Script | 100 products | 1,000 products | 1,500 products |
|--------|--------------|----------------|----------------|
| **Odoo→Flutter** | ~30 sec | ~3 min | ~4-5 min |
| **Zoho→Flutter** | ~20 sec | ~2 min | ~3 min |
| **Zoho↔Odoo** | ~40 sec | ~4 min | ~6 min |

*Times include category processing, network latency, and rate limiting*

**Factors affecting speed:**
- ✅ Fast: Service role key (bypasses RLS)
- ⚠️ Slow: Many categories (recursive hierarchy)
- ⚠️ Slow: Zoho rate limits (150ms between requests)
- ✅ Fast: Batch operations (100 items at once)

---

## 🎯 Script Selection Quiz

**Answer these questions to find your script:**

### Question 1: Do you need categories?
- ✅ Yes → **Odoo→Flutter** (only script with categories)
- ❌ No → Continue to Q2

### Question 2: Which system has correct data?
- 📦 Zoho (inventory) → **Zoho→Flutter**
- 🏢 Odoo (structure) → **Odoo→Flutter**
- 🤷 Not sure → **Zoho↔Odoo** (compare first)

### Question 3: Do you need to sync between Zoho and Odoo?
- ✅ Yes → **Zoho↔Odoo**
- ❌ No → Continue to Q4

### Question 4: What data needs updating?
- 📊 Stock & prices → **Zoho→Flutter**
- 📁 Categories & structure → **Odoo→Flutter**
- 🔍 Everything (first-time) → **Odoo→Flutter** first, then **Zoho→Flutter**

---

## 🚀 Quick Reference Commands

### Import Everything (Fresh Setup)
```bash
cd scripts/import_templates

# Step 1: Categories + structure
python3 sync_odoo_to_flutter.py

# Step 2: Stock + prices
python3 sync_zoho_to_flutter.py
```

### Update Stock Only (Regular Maintenance)
```bash
cd scripts/import_templates
python3 sync_zoho_to_flutter.py
```

### Compare Systems (Troubleshooting)
```bash
cd scripts/import_templates
python3 sync_zoho_odoo.py
```

---

## 📌 Decision Matrix Summary

| If you want to... | Use this script | Why |
|-------------------|-----------------|-----|
| **Set up new tenant** | `sync_odoo_to_flutter.py` | Creates categories + structure |
| **Update inventory daily** | `sync_zoho_to_flutter.py` | Fast, focuses on stock/prices |
| **Find missing products** | `sync_zoho_odoo.py` | Shows discrepancies |
| **Migrate Zoho→Odoo** | `sync_zoho_odoo.py` | Creates missing in Odoo |
| **Migrate Odoo→Zoho** | `sync_zoho_odoo.py` | Creates missing in Zoho |
| **Fix broken categories** | `sync_odoo_to_flutter.py` | Rebuilds hierarchy |
| **Emergency stock sync** | `sync_zoho_to_flutter.py` | Fastest option |
| **Audit data integrity** | `sync_zoho_odoo.py` | Detailed comparison |

---

## 🎓 Pro Tips

### When to Use Multiple Scripts

✅ **Common combo: Odoo + Zoho sync**
```bash
# Monthly: Structure update
python3 sync_odoo_to_flutter.py

# Weekly: Stock update
python3 sync_zoho_to_flutter.py
```

✅ **Migration scenario**
```bash
# Step 1: Reconcile source systems
python3 sync_zoho_odoo.py

# Step 2: Import to Flutter
python3 sync_odoo_to_flutter.py
```

---

### When to Use Single Script

✅ **Fresh setup with Odoo as source of truth**
```bash
python3 sync_odoo_to_flutter.py  # Done!
```

✅ **Only use Zoho for inventory**
```bash
python3 sync_zoho_to_flutter.py  # Done!
```

---

## 🔍 Troubleshooting: Wrong Script Used?

### Symptom: Products imported but no categories
**Cause:** Used `sync_zoho_to_flutter.py` instead of `sync_odoo_to_flutter.py`

**Fix:**
```bash
python3 sync_odoo_to_flutter.py  # Will add categories to existing products
```

---

### Symptom: Categories created but stock is zero
**Cause:** Used `sync_odoo_to_flutter.py` but Odoo doesn't have stock data

**Fix:**
```bash
python3 sync_zoho_to_flutter.py  # Updates stock from Zoho
```

---

### Symptom: "Already exists" errors
**Cause:** Product created in wrong system first

**Fix:**
```bash
# Find duplicates
python3 sync_zoho_odoo.py  # Shows which products exist where

# Then choose correct sync direction
```

---

**Still not sure? Check `AI_AGENT_GUIDE.md` for step-by-step instructions!**
