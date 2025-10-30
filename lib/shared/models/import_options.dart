/// Import/Update options for smart data importing
class ImportOptions {
  /// How to handle existing records
  final ImportMode mode;
  
  /// Field to use for matching existing records (e.g., 'sku', 'email', 'rut')
  final String matchField;
  
  /// Which fields to update (null = all fields)
  final List<String>? fieldsToUpdate;
  
  /// Fields to never update (always protected)
  final List<String> protectedFields;
  
  /// Preview changes before applying
  final bool previewMode;
  
  /// Skip records with errors vs. fail entire import
  final bool skipErrors;

  const ImportOptions({
    this.mode = ImportMode.upsert,
    this.matchField = 'sku',
    this.fieldsToUpdate,
    this.protectedFields = const ['id', 'tenant_id', 'created_at'],
    this.previewMode = false,
    this.skipErrors = true,
  });

  ImportOptions copyWith({
    ImportMode? mode,
    String? matchField,
    List<String>? fieldsToUpdate,
    List<String>? protectedFields,
    bool? previewMode,
    bool? skipErrors,
  }) {
    return ImportOptions(
      mode: mode ?? this.mode,
      matchField: matchField ?? this.matchField,
      fieldsToUpdate: fieldsToUpdate ?? this.fieldsToUpdate,
      protectedFields: protectedFields ?? this.protectedFields,
      previewMode: previewMode ?? this.previewMode,
      skipErrors: skipErrors ?? this.skipErrors,
    );
  }
}

enum ImportMode {
  /// Insert new records only, skip existing (matched by matchField)
  insertOnly,
  
  /// Update existing records only, skip new records
  updateOnly,
  
  /// Insert new records, update existing (UPSERT)
  upsert,
  
  /// Replace ALL fields in existing records (full overwrite)
  replace,
  
  /// Update only changed fields (smart merge)
  updateChanged,
}

extension ImportModeExtension on ImportMode {
  String get label {
    switch (this) {
      case ImportMode.insertOnly:
        return 'Solo Insertar Nuevos';
      case ImportMode.updateOnly:
        return 'Solo Actualizar Existentes';
      case ImportMode.upsert:
        return 'Insertar y Actualizar (Upsert)';
      case ImportMode.replace:
        return 'Reemplazar Todo';
      case ImportMode.updateChanged:
        return 'Actualizar Solo Cambios';
    }
  }

  String get description {
    switch (this) {
      case ImportMode.insertOnly:
        return 'Ignorar productos que ya existen, solo agregar nuevos';
      case ImportMode.updateOnly:
        return 'Ignorar productos nuevos, solo actualizar existentes';
      case ImportMode.upsert:
        return 'Agregar nuevos y actualizar existentes';
      case ImportMode.replace:
        return 'Sobrescribir TODOS los campos de productos existentes';
      case ImportMode.updateChanged:
        return 'Solo actualizar campos que sean diferentes';
    }
  }
}

/// Result of an import operation with conflict details
class ImportResult {
  final int inserted;
  final int updated;
  final int skipped;
  final int failed;
  final List<ImportConflict> conflicts;
  final List<String> errors;

  const ImportResult({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.failed = 0,
    this.conflicts = const [],
    this.errors = const [],
  });

  int get total => inserted + updated + skipped + failed;
  bool get hasConflicts => conflicts.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => failed == 0 && errors.isEmpty;
}

/// Represents a conflict between existing and imported data
class ImportConflict {
  final String matchValue; // e.g., SKU value
  final Map<String, dynamic> existingData;
  final Map<String, dynamic> importedData;
  final List<String> changedFields;

  const ImportConflict({
    required this.matchValue,
    required this.existingData,
    required this.importedData,
    required this.changedFields,
  });

  /// Get the differences between existing and imported data
  Map<String, FieldChange> get changes {
    final result = <String, FieldChange>{};
    for (final field in changedFields) {
      result[field] = FieldChange(
        field: field,
        oldValue: existingData[field],
        newValue: importedData[field],
      );
    }
    return result;
  }
}

/// Represents a change in a single field
class FieldChange {
  final String field;
  final dynamic oldValue;
  final dynamic newValue;

  const FieldChange({
    required this.field,
    required this.oldValue,
    required this.newValue,
  });

  bool get hasChanged => oldValue != newValue;
}
