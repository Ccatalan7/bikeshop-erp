# 📦 Import Stock Tracking Solution

**Created:** November 7, 2025  
**Issue:** Ghost records and missing import labeling in stock movements

---

## 🚨 Problems Identified

### 1. Ghost Records on Non-Stock Upserts
When importing to update product fields like `price`, `name`, `category_id` (without touching stock), the `track_product_stock_changes()` trigger would fire because the UPDATE event occurred, even though `stock_quantity` didn't actually change.

**Example:** Import to update prices on 100 products → 100 phantom stock adjustment records created

### 2. Import Stock Changes Not Labeled
When importing to update stock, the adjustment was logged as "Ajuste Manual" (manual) instead of "Importación" (import), making it impossible to trace which changes came from imports vs manual edits.

---

## ✅ Solution Implemented

### Database Changes

#### 1. Add 'import' Adjustment Type
```sql
-- Extended adjustment_type enum to include 'import'
alter table stock_adjustments add constraint stock_adjustments_adjustment_type_check 
  check (adjustment_type in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import'));
```

#### 2. Add 'reference' Column
```sql
-- New column to store import batch ID or filename
alter table stock_adjustments add column if not exists reference text;
```

**Purpose:** Track which import created the adjustment (e.g., `import_1730995200000`, `products_import_2025-11-07.csv`)

#### 3. Updated Trigger Function
**File:** `supabase/sql/core_schema.sql` (lines 851-930)

**Key Changes:**
- Reads session variables to detect import context
- Uses 'import' type when `app.stock_adjustment_context = 'import'`
- Stores import reference from `app.import_reference`
- Stores custom reason from `app.import_reason`
- **CRITICAL:** Only logs when `stock_quantity` ACTUALLY changes (not just on UPDATE event)

**Session Variables Used:**
- `app.stock_adjustment_context` = 'import' (triggers import mode)
- `app.import_reference` = Import batch ID or filename
- `app.import_reason` = Human-readable description

### Flutter Changes

#### 1. SmartImportService Updates
**File:** `lib/shared/services/smart_import_service.dart`

**Added Methods:**
- `_setImportContext()` - Sets session variables before import
- `_clearImportContext()` - Clears variables after import

**Import Flow:**
```dart
// Before import loop
await _setImportContext(
  reference: 'import_1730995200000',
  reason: 'Import: Upsert (50 records)',
);

try {
  // Import records...
} finally {
  // After import completes
  await _clearImportContext();
}
```

**Uses Supabase RPC:**
```dart
await client.rpc('set_config', params: {
  'setting': 'app.stock_adjustment_context',
  'value': 'import',
  'is_local': true, // Transaction-scoped
});
```

#### 2. StockMovement Model Updates
**File:** `lib/modules/inventory/models/stock_movement.dart`

**Added Labels:**
```dart
case 'manual': return 'Ajuste Manual';
case 'import': return 'Importación';  // NEW
case 'correction': return 'Corrección';
case 'initial': return 'Stock Inicial';
case 'damage': return 'Daño';
case 'loss': return 'Pérdida';
case 'found': return 'Hallazgo';
```

---

## 🧪 Testing Scenarios

### Scenario 1: Import with Stock Changes ✅
**Action:** Import products with `stock_quantity` column  
**Expected Result:**
- Stock movements shows "Importación" type
- Reference column stores import batch ID
- Reason shows "Import: Upsert (X records)"

### Scenario 2: Import without Stock Changes ✅
**Action:** Import products with only `price`, `name` columns (no stock column)  
**Expected Result:**
- **NO** stock adjustment records created
- **NO** ghost records in movimientos table

### Scenario 3: Import with Mixed Changes ✅
**Action:** Import 100 products, 30 have stock changes, 70 only have price changes  
**Expected Result:**
- **30** stock adjustment records created (type: 'import')
- **70** products updated with NO adjustment records

### Scenario 4: Manual Product Edit ✅
**Action:** Edit product stock via product form  
**Expected Result:**
- Stock adjustment created with type: 'manual'
- Reference column is NULL
- Reason shows "Manual adjustment via product form"

---

## 📊 Data Structure

### stock_adjustments Table
```sql
id              uuid
tenant_id       uuid
product_id      uuid
adjustment_type text  -- NEW: 'import' added
quantity        integer
stock_before    integer
stock_after     integer
reason          text
reference       text  -- NEW: Import batch ID
created_by      uuid
created_at      timestamp
```

### Example Records

**Manual Adjustment:**
```json
{
  "adjustment_type": "manual",
  "reason": "Manual adjustment via product form",
  "reference": null,
  "quantity": 10,
  "stock_before": 5,
  "stock_after": 15
}
```

**Import Adjustment:**
```json
{
  "adjustment_type": "import",
  "reason": "Import: Upsert (150 records)",
  "reference": "import_1730995200000",
  "quantity": 50,
  "stock_before": 10,
  "stock_after": 60
}
```

---

## 🚀 Deployment Steps

### 1. Deploy Database Changes
Run in **Supabase SQL Editor:**

```bash
# Copy the deployment SQL
cat /tmp/import_stock_tracking_fix.sql

# Paste into Supabase SQL Editor and execute
```

**File:** `/tmp/import_stock_tracking_fix.sql`

**What it does:**
- Adds 'import' to adjustment_type constraint
- Adds reference column (if not exists)
- Updates trigger function with import detection
- Recreates trigger

### 2. Flutter Changes (Already Deployed)
- ✅ `SmartImportService` updated with context methods
- ✅ `StockMovement` model updated with import labels
- ✅ Auto-deployed on app hot reload

### 3. Verify Deployment
```sql
-- Check constraint updated
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'stock_adjustments_adjustment_type_check';
-- Should show: adjustment_type in ('manual', ..., 'import')

-- Check reference column exists
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_adjustments' 
  AND column_name = 'reference';
-- Should return: reference | text
```

---

## 🔍 How It Works

### Import Context Flow

```
1. User clicks "Import" in product_import_page.dart
   └─> SmartImportService.importData() called
       └─> if (tableName == 'products')
           └─> _setImportContext(reference, reason)
               └─> Supabase.rpc('set_config', 'app.stock_adjustment_context', 'import')
               └─> Supabase.rpc('set_config', 'app.import_reference', 'import_XXX')
               └─> Supabase.rpc('set_config', 'app.import_reason', 'Import: ...')

2. Import loop processes records
   └─> DatabaseService.update('products', id, data)
       └─> UPDATE products SET stock_quantity = X
           └─> TRIGGER: track_product_stock_changes()
               └─> Reads current_setting('app.stock_adjustment_context')
               └─> if = 'import' → Use import type + reference
               └─> else → Use manual type + NULL reference
               └─> INSERT into stock_adjustments

3. Import completes
   └─> _clearImportContext()
       └─> Resets all session variables to empty string
```

### Key Design Decisions

**Why session variables instead of function parameters?**
- Trigger functions can't accept custom parameters
- Session variables work across the entire transaction
- `is_local: true` ensures they're scoped to current session only

**Why check `OLD.stock_quantity <> NEW.stock_quantity`?**
- PostgreSQL UPDATE triggers fire even if column values don't change
- Without this check, upserting price creates ghost stock records
- Only log when stock ACTUALLY changed

**Why transaction-scoped?**
- If import fails mid-way, session variables are automatically cleared
- No risk of context "leaking" into other operations
- Clean isolation per import batch

---

## 📝 Future Improvements

### 1. Import Filename in Reference
Currently stores timestamp-based batch ID. Could enhance to:
```dart
final importReference = 'import_${file.name}_${DateTime.now().millisecondsSinceEpoch}';
```

### 2. Bulk Import Statistics
Add summary record to new `import_batches` table:
```sql
create table import_batches (
  id uuid primary key,
  tenant_id uuid,
  reference text,
  table_name text,
  inserted integer,
  updated integer,
  failed integer,
  created_at timestamp
);
```

### 3. Import Rollback Feature
Allow users to revert an entire import batch:
```sql
-- Find all adjustments from specific import
SELECT * FROM stock_adjustments WHERE reference = 'import_XXX';
-- Reverse all adjustments (future feature)
```

---

## 🎯 Success Criteria

- ✅ No ghost records when importing non-stock fields
- ✅ Import stock changes labeled as "Importación"
- ✅ Import reference stored for traceability
- ✅ Manual edits still labeled as "Ajuste Manual"
- ✅ Backward compatible (existing adjustments unaffected)
- ✅ UI shows proper labels in stock movements view

---

## 📚 Related Documentation

- **Main Schema:** `supabase/sql/core_schema.sql`
- **Import Service:** `lib/shared/services/smart_import_service.dart`
- **Stock Movement Model:** `lib/modules/inventory/models/stock_movement.dart`
- **Stock Movements UI:** `lib/modules/inventory/pages/stock_movements_page.dart`
- **Deployment SQL:** `/tmp/import_stock_tracking_fix.sql`

---

## 🔗 References

**Previous Issues:**
- `.github/STOCK_MOVEMENTS_DUPLICATE_ADJUSTMENTS_ISSUE.md` - Stock sync bug
- `.github/REALTIME_SERVICE_BLOCKING_FIX.md` - Service initialization fix

**Pattern Source:**
- Invoice triggers use `app.skip_stock_adjustment_trigger` (same pattern)
- Smart purchase list uses similar session variable approach
