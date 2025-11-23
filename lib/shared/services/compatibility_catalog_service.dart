import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/compatibility_models.dart';
import 'tenant_service.dart';

class CompatibilityCatalogService {
  final SupabaseClient _client;
  final TenantService _tenantService;

  CompatibilityCatalogService({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  /// Fetch active component types from product_categories (with compatibility metadata).
  /// Categories with non-empty compatibility_metadata are treated as component types.
  Future<List<CompatComponentType>> fetchComponentTypes({bool includeInactive = false}) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      throw Exception('No tenant available for compatibility catalog');
    }

    try {
      var query = _client
          .from('product_categories')
          .select()
          .eq('tenant_id', tenantId);

      if (!includeInactive) {
        query = query.eq('is_active', true);
      }

      final List data = await query
          .order('level', ascending: true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);
      
      // Convert categories to CompatComponentType (only those with compatibility metadata)
      return data
          .map((row) {
            final metadata = row['compatibility_metadata'] as Map?;
            final componentCode = metadata?['component_code'] as String?;
            
            // Skip categories without compatibility metadata
            if (componentCode == null || componentCode.isEmpty) {
              return null;
            }
            
            return CompatComponentType.fromCategoryJson(Map<String, dynamic>.from(row as Map));
          })
          .whereType<CompatComponentType>()
          .toList();
    } catch (e, stackTrace) {
      debugPrint('❌ CompatibilityCatalogService.fetchComponentTypes failed: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  /// Fetch attribute schema from category's compatibility_metadata.
  /// Attributes are stored directly in the metadata JSON instead of separate tables.
  Future<List<CompatAttributeField>> fetchAttributeSchema(String categoryId) async {
    if (categoryId.isEmpty) {
      return const [];
    }

    try {
      // Fetch category with compatibility metadata
      final categoryData = await _client
          .from('product_categories')
          .select('compatibility_metadata')
          .eq('id', categoryId)
          .maybeSingle();

      if (categoryData == null) {
        return const [];
      }

      final metadata = categoryData['compatibility_metadata'] as Map? ?? {};
      final attributes = metadata['attributes'] as List? ?? [];

      // Convert JSON attributes to CompatAttributeField objects
      return attributes.map<CompatAttributeField?>((attr) {
        try {
          final attrMap = attr as Map;
          
          // Create attribute definition from metadata
          final definition = CompatAttributeDefinition(
            id: '', // Not used when stored in metadata
            tenantId: '',
            key: attrMap['key']?.toString() ?? '',
            label: attrMap['label']?.toString() ?? '',
            attributeType: attrMap['type']?.toString() ?? 'text',
            unitCode: attrMap['unit']?.toString(),
            description: attrMap['description']?.toString(),
            minValue: attrMap['min_value'] != null ? double.tryParse(attrMap['min_value'].toString()) : null,
            maxValue: attrMap['max_value'] != null ? double.tryParse(attrMap['max_value'].toString()) : null,
            precisionScale: attrMap['precision_scale'] as int?,
            isGlobal: attrMap['is_global'] as bool? ?? false,
          );

          // Create options from enum_values
          final enumValues = attrMap['enum_values'] as List? ?? [];
          final options = enumValues.asMap().entries.map((entry) {
            return CompatAttributeOption(
              id: '',
              attributeId: '',
              valueKey: entry.value.toString(),
              displayName: entry.value.toString(),
              description: null,
              sortOrder: entry.key,
            );
          }).toList();

          return CompatAttributeField(
            id: '',
            componentTypeId: categoryId,
            isRequired: attrMap['required'] as bool? ?? false,
            isPrimary: attrMap['primary'] as bool? ?? false,
            matchWeight: attrMap['match_weight'] != null 
                ? double.tryParse(attrMap['match_weight'].toString()) ?? 1.0 
                : 1.0,
            uiGroup: attrMap['ui_group']?.toString(),
            uiOrder: attrMap['ui_order'] as int? ?? 0,
            validation: attrMap['validation'] as Map<String, dynamic>? ?? {},
            attribute: definition,
            options: options,
          );
        } catch (e) {
          debugPrint('⚠️ Failed to parse attribute: $e');
          return null;
        }
      }).whereType<CompatAttributeField>().toList()
        ..sort((a, b) => a.uiOrder.compareTo(b.uiOrder));
    } catch (e, stackTrace) {
      debugPrint('❌ CompatibilityCatalogService.fetchAttributeSchema failed: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }
}
