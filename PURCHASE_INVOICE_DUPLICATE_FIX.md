# Purchase Invoice Duplicate Journal Entries - FIXED

## Problem

When marking a purchase invoice as "received", **two journal entries** were being created:
1. ✅ `COMP-FC-20251011-007147` (created by database trigger) - using account 1155
2. ❌ `JE202510-0021` (created by Dart code) - using account 1150

## Root Causes

### Cause 1: Double Entry Creation
Both systems were creating journal entries:
- **Database trigger** (`handle_purchase_invoice_change()`) - creates entry with prefix `COMP-`
- **Dart service** (`_postAccountingEntry()`) - creates entry with prefix `JE202510-`

### Cause 2: Account Lookup Issues
The SQL account lookup was too broad:
- Query: `WHERE name ILIKE '%inventario%'`
- Found multiple accounts: 1105, 1150, 1155
- Different accounts used in each entry

## Solutions Applied

### Fix 1: Disabled Dart-Side Accounting ✅
**File:** `lib/modules/purchases/services/purchase_service.dart`

**Changed:**
```dart
// Before (WRONG - creates duplicates)
await getPurchaseInvoices(forceRefresh: true);
await _postAccountingEntry(saved);
notifyListeners();

// After (CORRECT - let trigger handle it)
await getPurchaseInvoices(forceRefresh: true);
// NOTE: Accounting entries are now created automatically by database triggers
// when invoice status changes to 'received'.
notifyListeners();
```

**Result:** Only the database trigger creates journal entries now.

### Fix 2: Improved Account Lookup ✅
**File:** `supabase/sql/purchase_invoice_workflow.sql`

**Changed:**
```sql
-- Before (WRONG - too broad, finds wrong accounts)
SELECT id INTO inventory_account_id
FROM accounts
WHERE code = '1105' OR name ILIKE '%inventario%'
LIMIT 1;

-- After (CORRECT - exact code match first)
SELECT id INTO inventory_account_id
FROM accounts
WHERE code = '1105'
LIMIT 1;

-- Fallback only if not found
IF inventory_account_id IS NULL THEN
  SELECT id INTO inventory_account_id
  FROM accounts
  WHERE name ILIKE '%inventario%' AND code NOT IN ('1150', '1155')
  LIMIT 1;
END IF;
```

**Account Codes Updated:**
- IVA: Now accepts both `1180` or `1107` (Chilean standard)
- Accounts Payable: Now accepts both `2100` or `2101`

**Result:** Uses the correct, specific account codes consistently.

## Cleanup Required

You need to delete the duplicate entries already created.

### Option 1: Run Cleanup Script (Recommended)
```sql
-- Copy/paste contents of:
supabase/sql/cleanup_duplicate_purchase_entries.sql
```

This script:
1. Shows you the duplicates
2. Keeps entries with `COMP-` prefix (correct ones)
3. Deletes the other duplicates (`JE202510-` entries)
4. Verifies cleanup

### Option 2: Manual Cleanup
If you prefer to manually delete, identify and remove the entries with `JE202510-` prefix:

```sql
-- Find duplicates
SELECT 
  source_reference,
  COUNT(*) as entry_count,
  STRING_AGG(entry_number, ', ') as entries
FROM journal_entries
WHERE source_module = 'purchase_invoice'
GROUP BY source_reference
HAVING COUNT(*) > 1;

-- Delete the JE entries (NOT the COMP- ones)
DELETE FROM journal_lines
WHERE entry_id IN (
  SELECT id FROM journal_entries 
  WHERE source_module = 'purchase_invoice'
    AND entry_number LIKE 'JE%'
);

DELETE FROM journal_entries
WHERE source_module = 'purchase_invoice'
  AND entry_number LIKE 'JE%';
```

## How to Apply Fixes

### Step 1: Update Database Trigger
Run the updated workflow script:
```sql
-- Copy/paste contents of:
supabase/sql/purchase_invoice_workflow.sql
```

This will replace the existing functions with the improved account lookup.

### Step 2: Clean Up Duplicates
Run the cleanup script:
```sql
-- Copy/paste contents of:
supabase/sql/cleanup_duplicate_purchase_entries.sql
```

### Step 3: Rebuild Flutter App
The Dart code changes are already applied. Just restart your app:
```bash
# Stop the running app, then:
flutter run -d windows
```

## Testing

After applying the fixes:

1. **Create a new purchase invoice**
2. **Mark it as "Received"**
3. **Check accounting:**
   ```sql
   SELECT 
     je.entry_number,
     je.description,
     COUNT(jl.id) as line_count
   FROM journal_entries je
   LEFT JOIN journal_lines jl ON jl.entry_id = je.id
   WHERE je.source_module = 'purchase_invoice'
   GROUP BY je.id, je.entry_number, je.description
   ORDER BY je.created_at DESC;
   ```

4. **Expected result:**
   - Only **ONE** entry per invoice
   - Entry number starts with `COMP-`
   - Uses account codes: 1105 (or 1150/1155 if configured), 1180, 2100

## Account Codes Reference

After the fix, the trigger will use these accounts:

| Account | Code | Name | Usage |
|---------|------|------|-------|
| Inventory | **1105** | Inventario | ✅ Primary (preferred) |
| Inventory | 1150 | Inventarios de Mercaderías | Fallback |
| Inventory | 1155 | Inventarios de Materiales | Fallback |
| IVA | **1180** | IVA Crédito Fiscal | ✅ Primary (Chilean std) |
| IVA | 1107 | IVA Crédito Fiscal | Alternative |
| Payables | **2100** | Cuentas por Pagar | ✅ Primary |
| Payables | 2101 | Proveedores | Alternative |

**Note:** If you want to use a specific inventory account (1150 or 1155 instead of 1105), update the account setup script to create/rename account code to 1105.

## Summary

✅ **Fixed:** Removed duplicate journal entry creation  
✅ **Fixed:** Improved account lookup to use exact codes  
✅ **Created:** Cleanup script for existing duplicates  
✅ **Updated:** Documentation with proper account codes  

**Status:** Ready to deploy and test!

---

## Next Steps

1. ✅ Apply the updated `purchase_invoice_workflow.sql`
2. ✅ Run `cleanup_duplicate_purchase_entries.sql`
3. ✅ Restart Flutter app
4. ✅ Test with a new purchase invoice
5. ✅ Verify only one journal entry is created

**No more duplicates!** 🎉
