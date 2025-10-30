import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/import_options.dart';
import 'database_service.dart';
import 'tenant_service.dart';

/// Generic smart import service with upsert capabilities
class SmartImportService extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final TenantService _tenantService = TenantService();

  /// Import data with smart update/insert logic
  /// 
  /// [tableName] - Target table (e.g., 'products', 'customers')
  /// [records] - List of data maps to import
  /// [options] - Import configuration
  Future<ImportResult> importData({
    required String tableName,
    required List<Map<String, dynamic>> records,
    required ImportOptions options,
  }) async {
    debugPrint('🔄 Smart Import: $tableName (${records.length} records)');
    debugPrint('📋 Mode: ${options.mode.label}');
    debugPrint('🔍 Match Field: ${options.matchField}');

    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw Exception('Tenant ID not found');
    }

    int inserted = 0;
    int updated = 0;
    int skipped = 0;
    int failed = 0;
    final conflicts = <ImportConflict>[];
    final errors = <String>[];

    for (final record in records) {
      try {
        final matchValue = record[options.matchField];
        if (matchValue == null) {
          if (options.skipErrors) {
            errors.add('Registro sin ${options.matchField}: $record');
            failed++;
            continue;
          } else {
            throw Exception('Campo de coincidencia ${options.matchField} no encontrado');
          }
        }

        // Check if record exists
        final existing = await _findExisting(
          tableName: tableName,
          matchField: options.matchField,
          matchValue: matchValue,
          tenantId: tenantId,
        );

        if (existing == null) {
          // Record doesn't exist
          if (options.mode == ImportMode.updateOnly) {
            skipped++;
            debugPrint('⏭️ Skipped (not found): $matchValue');
            continue;
          }

          // Insert new record
          await _db.insert(tableName, record);
          inserted++;
          debugPrint('✅ Inserted: $matchValue');
        } else {
          // Record exists
          if (options.mode == ImportMode.insertOnly) {
            skipped++;
            debugPrint('⏭️ Skipped (already exists): $matchValue');
            continue;
          }

          // Prepare update data
          final updateData = _prepareUpdateData(
            existing: existing,
            imported: record,
            options: options,
          );

          // updateData is ready to use as-is - no need to filter computed fields
          // since category_name and supplier_name are now real columns kept in sync by triggers
          final filteredUpdateData = updateData;

          debugPrint('🔍 Comparing record: $matchValue');
          debugPrint('   Existing fields: ${existing.keys.toList()}');
          debugPrint('   Imported fields: ${record.keys.toList()}');
          debugPrint('   Update data (before filter): $updateData');
          debugPrint('   Update data (after filter): $filteredUpdateData');

          if (filteredUpdateData.isEmpty) {
            skipped++;
            debugPrint('⏭️ Skipped (no valid changes after filtering): $matchValue');
            continue;
          }

                    // Detect conflicts for preview
          if (options.previewMode) {
            final changedFields = filteredUpdateData.keys.toList();
            conflicts.add(ImportConflict(
              matchValue: matchValue.toString(),
              existingData: existing,
              importedData: record,
              changedFields: changedFields,
            ));
            updated++; // Count as update for preview statistics
            debugPrint('📋 Preview: Will update $matchValue');
            continue;
          }

          // Update existing record
          debugPrint('🔄 Attempting update for $matchValue with data: $filteredUpdateData');
          try {
            await _db.update(
              tableName,
              existing['id'],
              filteredUpdateData,
            );
            updated++;
            debugPrint('✅ Updated: $matchValue (${filteredUpdateData.length} fields)');
          } catch (updateError) {
            debugPrint('❌ Update failed for $matchValue: $updateError');
            if (options.skipErrors) {
              errors.add('Error actualizando ${record[options.matchField]}: $updateError');
              failed++;
            } else {
              rethrow;
            }
          }
        }
      } catch (e) {
        if (options.skipErrors) {
          errors.add('Error en registro ${record[options.matchField]}: $e');
          failed++;
          debugPrint('❌ Failed: ${record[options.matchField]} - $e');
        } else {
          rethrow;
        }
      }
    }

    final result = ImportResult(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      failed: failed,
      conflicts: conflicts,
      errors: errors,
    );

    debugPrint('✅ Import Complete: +$inserted ↻$updated ⏭$skipped ❌$failed');
    notifyListeners();
    return result;
  }

  /// Find existing record by match field
  Future<Map<String, dynamic>?> _findExisting({
    required String tableName,
    required String matchField,
    required dynamic matchValue,
    required String tenantId,
  }) async {
    try {
      // Use Supabase client directly for complex query
      final client = Supabase.instance.client;
      final results = await client
          .from(tableName)
          .select()
          .eq(matchField, matchValue)
          .eq('tenant_id', tenantId)
          .limit(1);

      if ((results as List).isEmpty) {
        return null;
      }

      return results.first;
    } catch (e) {
      debugPrint('⚠️ Error finding existing record: $e');
      return null;
    }
  }

  /// Prepare data for update based on import mode
  Map<String, dynamic> _prepareUpdateData({
    required Map<String, dynamic> existing,
    required Map<String, dynamic> imported,
    required ImportOptions options,
  }) {
    final updateData = <String, dynamic>{};

    // Get fields to process
    final fieldsToCheck = options.fieldsToUpdate ?? imported.keys.toList();
    
    debugPrint('🔧 _prepareUpdateData:');
    debugPrint('   Mode: ${options.mode}');
    debugPrint('   Fields to check: $fieldsToCheck');
    debugPrint('   Protected fields: ${options.protectedFields}');

    for (final field in fieldsToCheck) {
      // Skip protected fields
      if (options.protectedFields.contains(field)) {
        debugPrint('   ⏭️ Skip $field (protected)');
        continue;
      }

      // Skip if field not in imported data
      if (!imported.containsKey(field)) {
        debugPrint('   ⏭️ Skip $field (not in imported data)');
        continue;
      }

      final existingValue = existing[field];
      final importedValue = imported[field];
      
      // Normalize values for comparison (handle type mismatches)
      final normalizedExisting = _normalizeValue(existingValue);
      final normalizedImported = _normalizeValue(importedValue);
      
      debugPrint('   🔍 $field: "$existingValue" → "$importedValue" (${normalizedExisting == normalizedImported ? "same" : "CHANGED"})');

      // Mode-specific logic
      switch (options.mode) {
        case ImportMode.replace:
        case ImportMode.upsert:
          // Replace/Upsert: Always update (even if same)
          updateData[field] = importedValue;
          debugPrint('   ✅ Will update $field (mode: ${options.mode})');
          break;

        case ImportMode.updateChanged:
        case ImportMode.updateOnly:
          // Update only if different (use normalized comparison)
          if (normalizedExisting != normalizedImported) {
            updateData[field] = importedValue;
            debugPrint('   ✅ Will update $field (changed)');
          } else {
            debugPrint('   ⏭️ Skip $field (no change)');
          }
          break;

        case ImportMode.insertOnly:
          // Should never reach here (handled earlier)
          break;
      }
    }
    
    debugPrint('   📦 Final updateData: $updateData');

    return updateData;
  }

  /// Normalize value for comparison (handle type mismatches)
  dynamic _normalizeValue(dynamic value) {
    if (value == null) return null;
    
    // Convert string representations to actual types
    if (value is String) {
      final trimmed = value.trim();
      
      // Try to parse as boolean first (case-insensitive)
      final lowerValue = trimmed.toLowerCase();
      if (lowerValue == 'true') return true;
      if (lowerValue == 'false') return false;
      
      // Try to parse as number
      final numValue = num.tryParse(trimmed);
      if (numValue != null) return numValue;
      
      // Return trimmed string
      return trimmed;
    }
    
    // Keep booleans as-is (don't convert to string)
    if (value is bool) {
      return value;
    }
    
    return value;
  }

  /// Get preview of changes without applying them
  Future<ImportResult> previewImport({
    required String tableName,
    required List<Map<String, dynamic>> records,
    required ImportOptions options,
  }) async {
    return importData(
      tableName: tableName,
      records: records,
      options: options.copyWith(previewMode: true),
    );
  }
}
