# 🔄 Journal Entries Cache/Refresh Issue - FIXED

**Date:** October 13, 2025  
**Issue:** Journal entries ("Asientos Contables") were not refreshing properly after factory reset or data changes

---

## 🐛 Problem Description

### Symptoms:
1. After running "Reiniciar Sistema" (factory reset), journal entries still appeared in the list
2. User had to perform a hot restart to see the empty list
3. No way to manually refresh the journal entries list

### Root Cause:
The `JournalEntryService` uses a caching mechanism with an `_isLoaded` flag:
```dart
bool _isLoaded = false;

Future<void> ensureLoaded() async {
  if (_isLoaded) return; // ❌ Returns immediately if already loaded
  await loadJournalEntries();
}
```

Once data was loaded, `_isLoaded` was set to `true` and all subsequent calls would return cached data without hitting the database.

---

## ✅ Solution

### 1. Added `reload()` method to JournalEntryService

**File:** `lib/modules/accounting/services/journal_entry_service.dart`

```dart
/// Force reload of journal entries from database
Future<void> reload({int limit = 100}) async {
  _isLoaded = false; // Reset cache flag
  await loadJournalEntries(limit: limit);
}
```

### 2. Added `reloadJournalEntries()` to AccountingService

**File:** `lib/modules/accounting/services/accounting_service.dart`

```dart
/// Force reload of journal entries from database
Future<void> reloadJournalEntries({int limit = 100}) async {
  await _journalEntryService.reload(limit: limit);
}
```

### 3. Updated Journal Entry List Page

**File:** `lib/modules/accounting/pages/journal_entry_list_page.dart`

**Changes:**
- Updated `_loadJournalEntries()` to call `reloadJournalEntries()` instead of just `getJournalEntries()`
- Added a **refresh icon button** next to "Nuevo Asiento" button
- Refresh button is disabled while loading

```dart
// Always reload fresh data from database
await _accountingService.reloadJournalEntries();
```

**UI Update:**
```dart
IconButton(
  onPressed: _isLoading ? null : _loadJournalEntries,
  icon: const Icon(Icons.refresh),
  tooltip: 'Actualizar',
  style: IconButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
  ),
),
```

### 4. Updated Factory Reset Page

**File:** `lib/modules/settings/pages/factory_reset_page.dart`

**Changes:**
- Added Provider imports for service access
- After factory reset completes, calls `reloadJournalEntries()` on AccountingService
- This ensures the cache is cleared immediately after reset

```dart
// Clear all service caches to force reload
try {
  final accountingService = context.read<AccountingService>();
  await accountingService.reloadJournalEntries();
} catch (e) {
  debugPrint('Could not reload accounting service: $e');
}
```

### 5. Fixed Factory Reset Table Names

**File:** `lib/modules/settings/services/factory_reset_service.dart`

**Fixed incorrect table names:**
- ❌ `pos_transactions` → (removed, table doesn't exist)
- ❌ `attendance` → ✅ `attendance_records`
- ❌ `payroll` → ✅ `payroll_runs`

**Added missing deletion:**
- ✅ Added `sales_orders` deletion (before customers, due to FK constraint)

---

## 🧪 Testing Results

### Before Fix:
```
1. Go to Asientos Contables → 1 entry shown
2. Go to Settings → Reiniciar Sistema → Confirm
3. Go back to Asientos Contables → ❌ Still shows 1 entry (cached)
4. Hot restart → ✅ Now shows 0 entries
```

### After Fix:
```
1. Go to Asientos Contables → Entries shown
2. Click refresh button → ✅ Reloads from database
3. Go to Settings → Reiniciar Sistema → Confirm
4. Go back to Asientos Contables → ✅ Shows 0 entries immediately (no restart needed)
```

**Logs confirm it works:**
```
✅ Factory reset completed successfully
🔍 Loading journal entries with limit: 100
✅ DB Result: 0 rows from journal_entries
✅ Loaded 0 entries in 260ms
```

---

## 📋 Files Modified

| File | Changes |
|------|---------|
| `journal_entry_service.dart` | Added `reload()` method to force cache invalidation |
| `accounting_service.dart` | Added `reloadJournalEntries()` wrapper method |
| `journal_entry_list_page.dart` | Updated to use reload + added refresh icon button |
| `factory_reset_page.dart` | Added service cache clearing after reset |
| `factory_reset_service.dart` | Fixed table names (attendance_records, payroll_runs, sales_orders) |

---

## 🎯 User Impact

### Before:
- ❌ Confusing behavior after data changes
- ❌ Required app restart to see fresh data
- ❌ No manual refresh option

### After:
- ✅ Data always reflects database state
- ✅ Manual refresh button for immediate updates
- ✅ Factory reset properly clears cache
- ✅ No restart needed after data operations

---

## 🔍 Related Patterns

This caching issue could potentially affect other services:
- ✅ **AccountingService** - Fixed
- ⚠️ **SalesService** - May have similar caching (check if needed)
- ⚠️ **PurchaseService** - May have similar caching (check if needed)
- ⚠️ **InventoryService** - May have similar caching (check if needed)

**Recommendation:** Audit other services for similar `_isLoaded` patterns and add `reload()` methods as needed.

---

## 📚 Best Practices Going Forward

1. **Always provide a reload method** for services that cache data
2. **Add refresh buttons** to list pages for user-initiated reloads
3. **Clear caches** after destructive operations (delete, reset, etc.)
4. **Use Provider.read()** to access services for cache management
5. **Log database queries** to verify data freshness (helpful for debugging)

---

**Issue Status:** ✅ **RESOLVED**

The journal entries list now refreshes properly after factory reset and includes a manual refresh button for on-demand updates.
