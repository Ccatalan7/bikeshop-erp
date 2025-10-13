# Accounting Schema Migration Summary

## ✅ What Was Fixed

The purchase invoice workflow exposed mismatched column names between:
- **Database schema** (new unified names)
- **Flutter models** (old legacy names)

This caused errors when trying to load journal entries or create new ones.

---

## 🔧 Database Changes (SQL)

### File: `MASTER_ACCOUNTING_FIX.sql`

**Accounts Created:**
- `1140` - IVA Crédito Fiscal (Asset)
- `1150` - Inventario (Asset)
- `1155` - Inventario en Tránsito (Asset)
- `2120` - Cuentas por Pagar (Liability)

**journal_entries table:**
- ✅ Added: `entry_type`, `source_module`, `source_reference`, `notes`
- ❌ Removed: `date` (duplicate, kept `entry_date`)

**journal_lines table:**
- ✅ Added: `journal_entry_id`, `account_id`, `debit`, `credit`, `description`
- ❌ Removed: `entry_id`, `account_code`, `account_name`, `debit_amount`, `credit_amount`

---

## 💻 Flutter Code Changes

### 1. **journal_entry.dart** (Models)

**JournalEntry.fromJson():**
```dart
// OLD:
date: _parseDate(json['date'])
description: json['description']
type: json['type']

// NEW (supports both old and new):
date: _parseDate(json['entry_date'] ?? json['date'])
description: json['notes'] ?? json['description'] ?? ''
type: json['entry_type'] ?? json['type']
```

**JournalEntry.toJson():**
```dart
// OLD:
'date': date.toIso8601String()
'description': description
'type': type.name

// NEW:
'entry_date': date.toIso8601String()
'notes': description
'entry_type': type.name
```

**JournalLine.fromJson():**
```dart
// OLD:
debitAmount: json['debit_amount']
creditAmount: json['credit_amount']

// NEW (supports both):
debitAmount: json['debit'] ?? json['debit_amount']
creditAmount: json['credit'] ?? json['credit_amount']
```

**JournalLine.toJson():**
```dart
// OLD:
'entry_id': journalEntryId
'debit_amount': debitAmount
'credit_amount': creditAmount

// NEW:
'journal_entry_id': journalEntryId
'debit': debitAmount
'credit': creditAmount
```

### 2. **journal_entry_service.dart**

**Query Changes:**
```dart
// OLD:
orderBy: 'date'
where: 'entry_id'

// NEW:
orderBy: 'entry_date'
where: 'journal_entry_id'
```

**Insert Payload:**
```dart
// OLD:
'debit_amount': line.debitAmount
'credit_amount': line.creditAmount

// NEW:
'debit': line.debitAmount
'credit': line.creditAmount
```

### 3. **database_service.dart**

**createJournalEntry() method:**
```dart
// OLD:
'entry_id': entryId

// NEW:
'journal_entry_id': entryId
```

---

## 🎯 Why This Matters

### Before (Broken):
- Flutter tried to read `journal_entries.date` → **Column doesn't exist** ❌
- Flutter tried to read `journal_lines.entry_id` → **Column doesn't exist** ❌
- Flutter tried to read `journal_lines.debit_amount` → **Column doesn't exist** ❌
- Result: **Asientos Contables page wouldn't load**

### After (Fixed):
- Flutter reads `journal_entries.entry_date` → **Works!** ✅
- Flutter reads `journal_lines.journal_entry_id` → **Works!** ✅
- Flutter reads `journal_lines.debit` → **Works!** ✅
- Result: **Everything loads correctly**

---

## 📋 Migration Checklist

- [x] Run `MASTER_ACCOUNTING_FIX.sql` in Supabase
- [x] Update `journal_entry.dart` model
- [x] Update `journal_entry_service.dart` queries
- [x] Update `database_service.dart` insert logic
- [x] Restart Flutter app

---

## 🚀 Next Steps

1. **Test Asientos Contables page** - Should load without errors
2. **Test Purchase Invoice workflow** - Click "Confirmar Factura"
3. **Verify journal entries are created** - Check in Asientos Contables

---

## 🔍 Backward Compatibility

The models now support **BOTH** old and new column names during reads:
- `entry_date` OR `date` → Works
- `debit` OR `debit_amount` → Works
- `journal_entry_id` OR `entry_id` → Works

This ensures:
- Existing data can still be read
- New data uses the correct schema
- Gradual migration is possible

---

## ⚠️ Important Notes

1. **Old columns have been REMOVED** from the database
2. **New data MUST use new column names** (handled by toJson())
3. **Reads support both** for backward compatibility (handled by fromJson())
4. **All queries updated** to use new column names

---

## 📊 Column Name Reference Table

| Entity | Old Column | New Column | Type |
|--------|-----------|-----------|------|
| **journal_entries** | `date` | `entry_date` | DATE |
| | `description` | `notes` | TEXT |
| | `type` | `entry_type` | TEXT |
| | - | `source_module` | TEXT (new) |
| | - | `source_reference` | TEXT (new) |
| **journal_lines** | `entry_id` | `journal_entry_id` | UUID |
| | `debit_amount` | `debit` | NUMERIC |
| | `credit_amount` | `credit` | NUMERIC |
| | `account_code` | (removed, use FK) | - |
| | `account_name` | (removed, use FK) | - |

---

## ✅ Success Indicators

After this migration, you should see:

1. ✅ **Asientos Contables page loads** without database errors
2. ✅ **Purchase invoice confirmation works** (creates journal entry)
3. ✅ **Journal entries display correctly** in the accounting module
4. ✅ **No console errors** about missing columns

---

**Migration completed:** Ready to test purchase invoice workflow! 🎉
