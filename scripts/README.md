# 🔄 Import & Sync Scripts Directory

**Organized scripts for data import and synchronization**

---

## 🎉 **NEW: Complete Template System Available!**

📦 **Full import/sync package in `import_templates/` directory**

**What's included:**
- ✅ 3 production-ready scripts (Odoo→Flutter, Zoho→Flutter, Zoho↔Odoo)
- ✅ Universal config template (single file for all platforms)
- ✅ 8 comprehensive documentation files (2,500+ lines)
- ✅ AI-friendly guides (designed for future AI agents)
- ✅ Troubleshooting flowcharts (visual error resolution)
- ✅ Tested with 1,440 products (Vinabike production data)

**Start here:** [`import_templates/INDEX.md`](./import_templates/INDEX.md) or [`import_templates/QUICK_START_POSTER.md`](./import_templates/QUICK_START_POSTER.md)

---

## 📁 Directory Structure

```
scripts/
├── import_templates/          ⭐ NEW: AI-friendly sync templates
│   ├── config.template.py     - Configuration template
│   ├── sync_odoo_to_flutter.py
│   ├── sync_zoho_to_flutter.py
│   ├── sync_zoho_odoo.py
│   ├── README.md              - Full documentation
│   └── AI_AGENT_GUIDE.md      - Quick start for AI agents
│
├── zoho_import/               - Legacy Zoho-specific imports
│   ├── import_all_zoho_products.py
│   ├── zoho_to_supabase_import.py
│   └── README.md
│
└── odoo_import/               - Odoo comparison scripts
    ├── compare_categories.py
    └── README.md
```

---

## 🆕 **Use `import_templates/` for new imports!**

The `import_templates/` directory contains:
- **Unified configuration** (one config file for all platforms)
- **Better error handling** (validates credentials first)
- **Progress indicators** (see what's happening in real-time)
- **AI-friendly** (designed for easy AI agent usage)

### Quick Start

1. **Copy config template:**
   ```bash
   cd scripts/import_templates
   cp config.template.py config.py
   ```

2. **Fill in credentials** (Supabase, Odoo, Zoho)

3. **Run sync:**
   ```bash
   # Odoo → Flutter
   python3 sync_odoo_to_flutter.py
   
   # Zoho → Flutter
   python3 sync_zoho_to_flutter.py
   
   # Zoho ↔ Odoo
   python3 sync_zoho_odoo.py
   ```

📖 **Full documentation:** `import_templates/README.md`

---

## 🔧 When to Use Which Script

| You want to... | Use this |
|----------------|----------|
| ⭐ Import categories from Odoo | `import_templates/sync_odoo_to_flutter.py` |
| ⭐ Import products from Odoo | `import_templates/sync_odoo_to_flutter.py` |
| ⭐ Import products from Zoho | `import_templates/sync_zoho_to_flutter.py` |
| ⭐ Compare Zoho vs Odoo | `import_templates/sync_zoho_odoo.py` |
| Import Zoho products (bulk) | `zoho_import/import_all_zoho_products.py` |
| Import only images from Zoho | `zoho_import/zoho_to_supabase_import.py` |

---

## 📚 Documentation

- **`import_templates/README.md`** - Full sync system docs
- **`import_templates/AI_AGENT_GUIDE.md`** - Quick reference for AI
- **`zoho_import/README.md`** - Legacy Zoho import docs
- **`.github/IMPORT_STOCK_TRACKING_GUIDE.md`** - Stock adjustment tracking
- **`.github/ZOHO_IMPORT_QUICKREF.md`** - One-page Zoho cheatsheet

---

## 🎯 For AI Agents

When user asks for imports/syncs:

1. **Ask for credentials** (Supabase, Odoo/Zoho)
2. **Use `import_templates/`** (not legacy scripts)
3. **Follow `AI_AGENT_GUIDE.md`** for step-by-step
4. **Report results** with summary stats

---

## 🔐 Security

**NEVER commit these files:**
- `config.py` (contains API keys)
- `*.log` (may contain sensitive data)
- Export files with customer data

All protected by `.gitignore` in each directory.

---

## 🚀 Migration Path

If using legacy scripts:

```
OLD                                    NEW
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
zoho_import/*.py                →      import_templates/sync_zoho_to_flutter.py
odoo_import/compare_*.py        →      import_templates/sync_zoho_odoo.py
Manual Odoo scripts             →      import_templates/sync_odoo_to_flutter.py
```

Benefits:
- ✅ Single config file
- ✅ Better error messages
- ✅ Progress indicators
- ✅ Credential validation
- ✅ AI-friendly design

---

**Made with ❤️ for seamless multi-platform integration**
