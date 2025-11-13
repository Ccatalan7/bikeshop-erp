# Notion → Pegas (Mechanic Jobs) Sync

This script syncs data from a Notion database to your `mechanic_jobs` table in Supabase.

## 🎯 Features

- ✅ Fetches all records from Notion database (with pagination)
- ✅ Smart column mapping (handles Spanish/English names)
- ✅ Auto-creates customers if they don't exist
- ✅ Updates existing jobs (matches by Notion ID)
- ✅ Maps Notion property types to database columns
- ✅ Status translation (Pendiente → pending, etc.)

## 📋 Setup

### 1. Install Dependencies

```bash
cd scripts/notion_import
pip3 install notion-client requests supabase
```

### 2. Get Notion Integration Token

1. Go to https://www.notion.so/my-integrations
2. Click **"+ New integration"**
3. Name it: "Bikeshop ERP Sync"
4. Select your workspace
5. Copy the **"Internal Integration Token"**
6. **IMPORTANT**: Go to your Notion database → Click **"••• " menu** → **"Add connections"** → Select your integration

### 3. Get Notion Database ID

1. Open your Pegas/Mechanic Jobs database in Notion
2. Copy the URL (looks like): `https://www.notion.so/workspace/XXXXXXXXX?v=YYYYY`
3. The database ID is the 32-character string `XXXXXXXXX` (before `?v=`)
4. Remove dashes if present (e.g., `abc-def-ghi` → `abcdefghi`)

### 4. Configure the Script

Edit `notion_pegas_sync.py` and set:

```python
NOTION_API_KEY = "secret_xxxxxxxxxxxxxxxxxxxxx"  # Your integration token
NOTION_DATABASE_ID = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # Your database ID
```

## 🔧 Column Mapping

The script maps Notion properties to database columns. Current mapping:

| Notion Property (EN) | Notion Property (ES) | Database Column |
|---------------------|---------------------|-----------------|
| Customer | Cliente | customer_name → customer_id |
| Bike | Bicicleta | bike_description |
| Status | Estado | status |
| Description | Descripción | description |
| Labor Cost | Costo Mano de Obra | labor_cost |
| Start Date | Fecha Inicio | start_date |
| Completion Date | Fecha Término | completion_date |
| Notes | Notas | notes |
| Phone | Teléfono | customer_phone |
| Email | - | customer_email |

### Status Mapping

| Notion Status | Database Status |
|--------------|----------------|
| Pending / Pendiente | pending |
| In Progress / En Progreso | in_progress |
| Completed / Completado | completed |
| Ready for Delivery / Listo para Entrega | ready_for_delivery |

## 🚀 Usage

```bash
cd scripts/notion_import
python3 notion_pegas_sync.py
```

### Example Output

```
🚀 Notion → Pegas Sync Script

✅ Initialized Notion Sync
   Database ID: abc123...
   Tenant: 5443b130-...

📦 Fetching data from Notion database...
   Fetched page 1 (10 records so far)
   Fetched page 2 (15 records so far)
✅ Total Notion records fetched: 15

🔄 Syncing to database...

✅ Created new customer: Juan Pérez
✅ Created: Giant TCR 2024 - Cambio de piñones
✅ Updated: Trek Marlin 7 - Mantención completa
...

============================================================
📊 SYNC SUMMARY
============================================================
Created:  8
Updated:  7
Skipped:  0
Errors:   0
============================================================

✅ Sync complete!
```

## 📝 Adding Custom Mappings

To map additional Notion properties, edit the `COLUMN_MAPPING` dict:

```python
COLUMN_MAPPING = {
    "Your Notion Property": "database_column_name",
    "Otra Propiedad": "otra_columna",
}
```

## 🔄 Supported Property Types

- ✅ Title
- ✅ Rich Text
- ✅ Number
- ✅ Select (single choice)
- ✅ Multi-select
- ✅ Date
- ✅ Checkbox
- ✅ URL
- ✅ Email
- ✅ Phone Number
- ✅ People (extracts names)

## ⚠️ Important Notes

1. **First Run**: The script will create new mechanic jobs and customers
2. **Subsequent Runs**: Updates existing jobs based on Notion ID
3. **Customer Matching**: Searches by name (case-insensitive)
4. **Notion ID**: Added as a column to track sync (stores Notion page ID)

## 🐛 Troubleshooting

**Error: "Database not found"**
- Make sure you shared your database with the integration (step 2.6 above)

**Error: "Unauthorized"**
- Check your integration token is correct
- Ensure token has access to the workspace

**No records synced**
- Check your database ID is correct (32 chars, no dashes)
- Verify the database has records

## 🔗 References

- [Notion API Documentation](https://developers.notion.com/)
- [Database Query Endpoint](https://developers.notion.com/reference/post-database-query)
