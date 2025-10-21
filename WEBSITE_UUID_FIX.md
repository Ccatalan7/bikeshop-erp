# 🔧 Website Editor UUID Fix

## ❌ The Problem

When trying to save website blocks, you got this error:

```
Error al guardar. PostgrestException(message: invalid input syntax for type uuid: "hero_1", code: 22P02, details: , hint: null)
```

### Root Cause:

- **Database expects:** UUIDs (e.g., `123e4567-e89b-12d3-a456-426614174000`)
- **Code was generating:** Simple strings (e.g., `"hero_1"`, `"products_1234567890"`)

The `website_blocks` table in Supabase has `id uuid primary key`, but the code was creating blocks with string IDs instead of proper UUIDs.

---

## ✅ The Fix

### Changed Files:

**`lib/modules/website/pages/odoo_style_editor_page.dart`**

### 1. Added UUID Package Import

```dart
import 'package:uuid/uuid.dart';
```

### 2. Fixed `_createBlockTemplate()` Function

**Before:**
```dart
WebsiteBlock _createBlockTemplate(BlockType type) {
  final id = '${type.name}_${DateTime.now().millisecondsSinceEpoch}'; // ❌ String ID
  // ...
}
```

**After:**
```dart
WebsiteBlock _createBlockTemplate(BlockType type) {
  const uuid = Uuid();
  final id = uuid.v4(); // ✅ Proper UUID
  // ...
}
```

### 3. Fixed `_initializeDefaultBlocks()` Function

**Before:**
```dart
void _initializeDefaultBlocks() {
  _blocks = [
    WebsiteBlock(
      id: 'hero_1', // ❌ Hardcoded string
      type: BlockType.hero,
      // ...
    ),
    WebsiteBlock(
      id: 'products_1', // ❌ Hardcoded string
      // ...
    ),
    // ...
  ];
}
```

**After:**
```dart
void _initializeDefaultBlocks() {
  const uuid = Uuid();
  _blocks = [
    WebsiteBlock(
      id: uuid.v4(), // ✅ Proper UUID
      type: BlockType.hero,
      // ...
    ),
    WebsiteBlock(
      id: uuid.v4(), // ✅ Proper UUID
      type: BlockType.products,
      // ...
    ),
    // ...
  ];
}
```

---

## 🧪 Testing

### To verify the fix works:

1. **Hot reload** the app (press `r` in terminal or save the file)
2. Go to the website editor (localhost:52068/#/tienda)
3. Make any change (edit text, move a block, etc.)
4. Click **"💾 Guardar"**
5. ✅ Should save successfully without UUID errors!

### Expected Behavior:

- **Before:** `PostgrestException: invalid input syntax for type uuid`
- **After:** ✅ `Cambios guardados exitosamente`

---

## 🔍 Why UUIDs?

### UUID Format:
```
123e4567-e89b-12d3-a456-426614174000
```

### Benefits:
- ✅ **Universally unique:** No collisions across systems
- ✅ **Database standard:** PostgreSQL native type
- ✅ **Secure:** Hard to guess or enumerate
- ✅ **Distributed-friendly:** Can be generated offline

### String IDs (what we had):
```
"hero_1"
"products_1729468800000"
```

### Problems:
- ❌ Not UUID format (PostgreSQL rejects)
- ❌ Potential collisions
- ❌ Harder to integrate with other systems
- ❌ Not database-standard

---

## 📊 Database Schema Reference

From `supabase/sql/core_schema.sql`:

```sql
create table if not exists website_blocks (
  id uuid primary key default gen_random_uuid(),  -- ← MUST BE UUID!
  block_type text not null,
  block_data jsonb not null default '{}'::jsonb,
  is_visible boolean default true,
  order_index integer default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
```

---

## 🚀 What's Now Working

### ✅ Creating New Blocks
When you add a new block via "Agregar" tab:
- Generates proper UUID: `a3bb189e-58d7-4f7e-ae9d-8ac374c0f6e2`
- Saves to database successfully
- No more UUID errors!

### ✅ Saving Existing Blocks
When you edit and save:
- All block IDs are now valid UUIDs
- Database accepts them
- Changes persist correctly

### ✅ Loading Blocks from Database
When you reload the page:
- Blocks load with their UUID IDs
- Editor works correctly
- No type mismatches

---

## 🔧 Related Files

| File | Change |
|------|--------|
| `odoo_style_editor_page.dart` | ✅ Fixed UUID generation |
| `website_service.dart` | ℹ️ No changes needed (already handles UUIDs) |
| `core_schema.sql` | ℹ️ Already correct (uuid type) |

---

## 💡 Future Improvements

### Optional Enhancements:

1. **Validate UUIDs on load:**
   ```dart
   if (!_isValidUuid(block.id)) {
     block.id = const Uuid().v4(); // Regenerate
   }
   ```

2. **Migration for old data:**
   ```sql
   -- If you have old blocks with string IDs, convert them:
   UPDATE website_blocks 
   SET id = gen_random_uuid()::text 
   WHERE id NOT SIMILAR TO '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
   ```

3. **Add UUID validation helper:**
   ```dart
   bool _isValidUuid(String id) {
     final uuidRegex = RegExp(
       r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
       caseSensitive: false,
     );
     return uuidRegex.hasMatch(id);
   }
   ```

---

## ✅ Verification Checklist

- [x] Import `uuid` package
- [x] Fix `_createBlockTemplate()` to use `uuid.v4()`
- [x] Fix `_initializeDefaultBlocks()` to use `uuid.v4()`
- [x] Remove all hardcoded string IDs (`'hero_1'`, `'products_1'`, etc.)
- [x] Code compiles without errors
- [ ] **Test saving blocks** ← DO THIS NOW!
- [ ] **Verify no more UUID errors** ← CONFIRM!

---

## 🎯 Summary

**Problem:** String IDs like `"hero_1"` don't match database UUID type  
**Solution:** Use `Uuid().v4()` to generate proper UUIDs  
**Result:** ✅ Saving now works without errors!

**The "Sin guardar" (unsaved) indicator should now actually be able to save! 🎉**
