# 🗑️ Quick Delete Buttons (Testing Feature)

**Date:** October 13, 2025  
**Purpose:** Temporary one-touch delete buttons for rapid testing

---

## ⚠️ WARNING: TESTING ONLY

These buttons are designed for **DEVELOPMENT/TESTING ONLY**. They:
- ❌ **No confirmation dialog**
- ❌ **No warning prompts**
- ❌ **Instant deletion**
- ⚠️ **Should be removed before production**

---

## 🎯 Features Added

### 1. Quick Delete in "Facturas de Venta" (Sales Invoices)

**Location:** `lib/modules/sales/pages/invoice_list_page.dart`

**What was added:**
- 🗑️ Red trash icon button on each invoice card
- One-touch deletion (no confirmation)
- Shows success/error toast message
- Auto-refreshes list after deletion

**Visual:**
```
┌─────────────────────────────────────────────────────┐
│ Cliente: Juan Pérez                    [🗑️] [Pagar] │
│ Factura #001 | 13/10/2025                           │
│ Total: $10,000 | Pagado: $0 | Saldo: $10,000       │
└─────────────────────────────────────────────────────┘
```

**Code added:**
```dart
// Delete button
IconButton(
  onPressed: () => _quickDeleteInvoice(invoice),
  icon: const Icon(Icons.delete_forever, color: Colors.red),
  tooltip: 'Eliminar (Testing)',
  iconSize: 20,
),

// Delete method
Future<void> _quickDeleteInvoice(Invoice invoice) async {
  await salesService.deleteInvoice(invoice.id);
  // Show toast and refresh
}
```

---

### 2. Quick Delete in "Asientos Contables" (Journal Entries)

**Location:** `lib/modules/accounting/pages/journal_entry_list_page.dart`

**What was added:**
- 🗑️ Red trash icon button on each journal entry
- Located in the ExpansionTile trailing area
- One-touch deletion (no confirmation)
- Deletes both the entry and all its lines
- Shows success/error toast message
- Auto-refreshes list after deletion

**Visual:**
```
┌────────────────────────────────────────────────────┐
│ ASI-001 | 13/10/2025 | Venta Factura #001  [🗑️] │
│ Débito: $11,900 | Crédito: $11,900              │
│ ▼ Líneas del Asiento                             │
└────────────────────────────────────────────────────┘
```

**Code added:**
```dart
// Delete button in ExpansionTile
trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      onPressed: () => _quickDeleteEntry(entry),
      icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
      tooltip: 'Eliminar (Testing)',
    ),
  ],
),

// Delete method
Future<void> _quickDeleteEntry(JournalEntry entry) async {
  await _accountingService.deleteJournalEntry(entry.id);
  // Show toast and refresh
}
```

---

## 🔧 Backend Methods Added

### JournalEntryService.deleteEntry()

**File:** `lib/modules/accounting/services/journal_entry_service.dart`

**What it does:**
1. Finds the entry by ID
2. Deletes all associated journal lines
3. Deletes the journal entry itself
4. Removes from local cache
5. Notifies listeners

```dart
Future<void> deleteEntry(String entryId) async {
  // Delete all lines first
  final lineDocs = await _databaseService.select(
    'journal_lines',
    where: 'entry_id',
    whereIn: [entryId],
  );
  
  for (final line in lineDocs) {
    await _databaseService.delete('journal_lines', lineId);
  }
  
  // Delete the entry
  await _databaseService.delete('journal_entries', entryId);
  
  // Update cache
  _journalEntries.removeWhere((e) => e.id == entryId);
  notifyListeners();
}
```

### AccountingService.deleteJournalEntry()

**File:** `lib/modules/accounting/services/accounting_service.dart`

**Wrapper method:**
```dart
Future<void> deleteJournalEntry(String entryId) async {
  await initialize();
  await _journalEntryService.deleteEntry(entryId);
}
```

---

## 🧪 Testing Workflow

### Typical Use Case:

1. **Create test data:**
   ```
   - Create sales invoice
   - Register payment
   - Check journal entry created
   ```

2. **Test feature:**
   ```
   - Verify everything works
   - Check accounting entries
   ```

3. **Clean up quickly:**
   ```
   - Click 🗑️ on journal entry → Gone instantly
   - Click 🗑️ on invoice → Gone instantly
   - Repeat as needed
   ```

4. **No need for:**
   ```
   ❌ Opening detail page
   ❌ Finding delete option in menu
   ❌ Confirming multiple dialogs
   ❌ Waiting for animations
   ```

---

## ⚠️ Known Behaviors

### Sales Invoice Deletion:

✅ **What gets deleted:**
- Invoice record
- Related payments (if any)
- Journal entries created by payments
- Stock movements (if applicable)

⚠️ **What happens:**
- Direct database deletion
- Cascading deletes handled by database
- Cache updated immediately

### Journal Entry Deletion:

✅ **What gets deleted:**
- Journal entry record
- All journal lines
- Entry removed from cache

⚠️ **What does NOT happen:**
- No reversal entry created
- No audit trail (direct delete)
- Source invoices/payments NOT affected

---

## 🚨 Important Notes

### 1. Foreign Key Constraints

If an invoice has payments or related data, deletion might fail due to FK constraints. The error toast will show:
```
Error: update or delete violates foreign key constraint
```

**Solution:** Delete child records first (payments → invoice)

### 2. Journal Entries from Invoices

Journal entries created automatically by invoices/payments can be deleted, but:
- ⚠️ **This breaks the link** between invoice and accounting
- ⚠️ **Invoice totals won't match** journal entry totals
- ⚠️ **Only do this for testing/cleanup**

### 3. Data Consistency

These buttons bypass normal business logic:
- No status checks
- No balance validations
- No audit logging
- **Use only for test data!**

---

## 🗑️ Before Production

**Remove these buttons by:**

1. **Remove UI buttons:**
   ```dart
   // Comment out or delete:
   // invoice_list_page.dart lines ~250-256
   IconButton(
     onPressed: () => _quickDeleteInvoice(invoice),
     ...
   ),
   
   // journal_entry_list_page.dart lines ~320-328
   trailing: Row(...),
   ```

2. **Remove backend methods (optional):**
   ```dart
   // journal_entry_service.dart - deleteEntry()
   // accounting_service.dart - deleteJournalEntry()
   // invoice_list_page.dart - _quickDeleteInvoice()
   // journal_entry_list_page.dart - _quickDeleteEntry()
   ```

3. **Or add confirmation dialogs:**
   ```dart
   Future<void> _quickDeleteInvoice(Invoice invoice) async {
     final confirmed = await showDialog<bool>(...);
     if (!confirmed) return;
     // ... rest of code
   }
   ```

---

## 📋 Files Modified

| File | Changes |
|------|---------|
| `invoice_list_page.dart` | Added delete button + _quickDeleteInvoice() method |
| `journal_entry_list_page.dart` | Added delete button + _quickDeleteEntry() method |
| `journal_entry_service.dart` | Added deleteEntry() method |
| `accounting_service.dart` | Added deleteJournalEntry() wrapper |

---

## ✅ Benefits for Testing

1. **Faster iteration** - No multi-step deletion process
2. **Quick cleanup** - Remove test data instantly
3. **Rapid prototyping** - Test → Delete → Test again
4. **Less friction** - No confirmation fatigue
5. **Visible action** - Toast confirms deletion

---

## 🎯 Usage Example

```
Testing payment flow:
1. Create invoice              ✅
2. Register payment            ✅
3. Check journal entry         ✅
4. Found bug in logic          ❌
5. Click 🗑️ on journal entry  💨 Gone!
6. Click 🗑️ on invoice        💨 Gone!
7. Fix code                    🔧
8. Test again                  🔄
```

**Without quick delete buttons:**
```
5. Navigate to journal entry detail
6. Find delete option
7. Confirm dialog 1
8. Confirm dialog 2
9. Wait for animation
10. Navigate back
11. Navigate to invoice detail
12. Find delete option
13. Confirm dialog 1
14. Confirm dialog 2
15. Wait for animation
16. Navigate back
17. Finally ready to test again... 😫
```

---

**Status:** ✅ **ACTIVE - FOR TESTING ONLY**

Remove before deploying to production!
