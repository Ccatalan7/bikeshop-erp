# 🚀 Smart Import/Update System

## Overview

The Smart Import system allows you to **import AND update** existing records intelligently. It supports multiple modes, field-level control, and conflict preview.

## Features

### ✅ 5 Import Modes

1. **Insert Only** - Only add new records, skip existing ones
2. **Update Only** - Only update existing records, ignore new ones
3. **Upsert** - Insert new + Update existing (most common)
4. **Replace All** - Overwrite ALL fields in existing records
5. **Update Changed** - Only update fields that are different (smart merge)

### ✅ Match Strategies

Choose which field identifies existing records:
- **Products**: SKU, name, barcode
- **Customers**: email, RUT, phone
- **Employees**: email, RUT, employee_number
- **Suppliers**: email, RUT, tax_id

### ✅ Field-Level Control

- Choose which fields to update (checkboxes)
- Protected fields never update: `id`, `tenant_id`, `created_at`
- Preview changes before applying

### ✅ Conflict Resolution

- Side-by-side comparison (Current vs. New)
- See exactly what will change
- Review before committing

---

## Usage Example

### Step 1: Import File with Smart Options

```dart
// In your import page
import 'package:file_picker/file_picker.dart';
import '../../../shared/services/smart_import_service.dart';
import '../../../shared/widgets/smart_import_dialog.dart';
import '../../../shared/models/import_options.dart';

class ProductImportPage extends StatefulWidget {
  // ... your existing code
}

class _ProductImportPageState extends State<ProductImportPage> {
  final SmartImportService _importService = SmartImportService();
  
  Future<void> _importWithSmartOptions() async {
    // 1. Pick file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );
    
    if (result == null) return;
    
    // 2. Parse file data (your existing CSV/Excel parsing logic)
    final records = await _parseFile(result.files.first);
    
    // 3. Show import options dialog
    final options = await showDialog<ImportOptions>(
      context: context,
      builder: (context) => SmartImportOptionsDialog(
        availableMatchFields: ['sku', 'name', 'barcode'],
        defaultMatchField: 'sku',
        availableUpdateFields: [
          'name',
          'description',
          'price',
          'cost',
          'stock_quantity',
          'min_stock_level',
          'category_id',
          'is_active',
        ],
      ),
    );
    
    if (options == null) return;
    
    // 4. Preview changes (optional but recommended)
    final preview = await _importService.previewImport(
      tableName: 'products',
      records: records,
      options: options,
    );
    
    if (preview.hasConflicts) {
      // Show conflict preview
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ImportConflictPreviewDialog(
          result: preview,
          onConfirm: () => Navigator.pop(context, true),
        ),
      );
      
      if (confirmed != true) return;
    }
    
    // 5. Execute import
    final importResult = await _importService.importData(
      tableName: 'products',
      records: records,
      options: options.copyWith(previewMode: false),
    );
    
    // 6. Show results
    _showImportResults(importResult);
  }
  
  void _showImportResults(ImportResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.isSuccess ? '✅ Importación Exitosa' : '⚠️ Importación Completada con Errores'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✅ Insertados: ${result.inserted}'),
            Text('🔄 Actualizados: ${result.updated}'),
            Text('⏭️ Omitidos: ${result.skipped}'),
            if (result.failed > 0)
              Text('❌ Fallidos: ${result.failed}', style: TextStyle(color: Colors.red)),
            if (result.hasErrors) ...[
              SizedBox(height: 16),
              Text('Errores:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...result.errors.take(5).map((e) => Text('• $e', style: TextStyle(fontSize: 12))),
              if (result.errors.length > 5)
                Text('... y ${result.errors.length - 5} más'),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
```

---

## Real-World Scenario

### Your Example: Update Stock Quantities

**Database 1 (Current):**
```csv
sku,name,stock_quantity
12345,Test Product,3
```

**Database 2 (Correct Stock):**
```csv
sku,name,stock_quantity
12345,Test Product,5
67890,New Product,10
```

**Steps:**

1. Export CSV from Database 2
2. Go to Products → Import
3. Upload CSV
4. Configure import options:
   - **Mode**: "Update Changed" (only update what's different)
   - **Match Field**: SKU
   - **Fields to Update**: Check only `stock_quantity` (uncheck name, price, etc.)
5. Preview shows:
   ```
   SKU: 12345
   Field         Current    New
   stock_quantity    3   →   5   ✅
   
   SKU: 67890
   (New product - will be inserted)
   ```
6. Confirm → Result:
   - ✅ 1 updated (SKU 12345: stock_quantity 3 → 5)
   - ✅ 1 inserted (SKU 67890: new product)

---

## Advanced Use Cases

### 1. Price Update Only (Don't Touch Stock)

```dart
final options = ImportOptions(
  mode: ImportMode.updateOnly,
  matchField: 'sku',
  fieldsToUpdate: ['price', 'cost'], // Only update pricing
);
```

### 2. Bulk Activate/Deactivate Products

CSV:
```csv
sku,is_active
12345,false
67890,true
```

Options:
```dart
final options = ImportOptions(
  mode: ImportMode.updateOnly,
  matchField: 'sku',
  fieldsToUpdate: ['is_active'], // Only toggle active status
);
```

### 3. Full Product Replacement (Dangerous!)

```dart
final options = ImportOptions(
  mode: ImportMode.replace, // ⚠️ Overwrites EVERYTHING
  matchField: 'sku',
  // fieldsToUpdate: null means ALL fields
);
```

---

## Protected Fields

These fields are **NEVER** updated (always protected):

- `id` - Primary key
- `tenant_id` - Multi-tenant isolation
- `created_at` - Audit trail
- `created_by` - Audit trail

You can add more in `ImportOptions`:

```dart
final options = ImportOptions(
  protectedFields: [
    'id', 
    'tenant_id', 
    'created_at',
    'sku', // ⚠️ Protect SKU from being changed
    'barcode',
  ],
);
```

---

## Integration with Existing Import

Add a button to your existing import page:

```dart
Row(
  children: [
    ElevatedButton.icon(
      icon: Icon(Icons.upload),
      label: Text('Importar (Reemplazar)'),
      onPressed: _importReplaceMode, // Old behavior
    ),
    SizedBox(width: 16),
    ElevatedButton.icon(
      icon: Icon(Icons.sync),
      label: Text('Importar con Opciones'),
      onPressed: _importWithSmartOptions, // New smart import
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
      ),
    ),
  ],
)
```

---

## Error Handling

```dart
try {
  final result = await _importService.importData(...);
  
  if (result.hasErrors) {
    // Some records failed
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('⚠️ Errores en Importación'),
        content: SingleChildScrollView(
          child: Column(
            children: result.errors.map((e) => Text(e)).toList(),
          ),
        ),
      ),
    );
  }
} catch (e) {
  // Catastrophic failure
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('❌ Error: $e'),
      backgroundColor: Colors.red,
    ),
  );
}
```

---

## Performance

- ✅ Batch operations for large imports
- ✅ Skip errors (don't fail entire import if one record is bad)
- ✅ Preview mode doesn't write to database
- ✅ Tenant-safe (all queries filter by `tenant_id`)

---

## Next Steps

1. **Test with small dataset** (5-10 records)
2. **Use preview mode** to verify changes
3. **Start with "Update Only"** to avoid accidental inserts
4. **Gradually increase** to full Upsert mode

---

## Support

If you encounter issues:

1. Check browser console (F12) for debug logs
2. Verify match field exists in both current DB and import file
3. Ensure field names match exactly (case-sensitive)
4. Test with preview mode first

---

**🎉 You now have a production-ready smart import system!**
