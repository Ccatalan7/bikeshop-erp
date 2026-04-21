import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/product_compatibility.dart';
import '../config/brake_canonical_data.dart';
import '../models/bikeshop_models.dart';

class BikeProductCompatibilityService {
  BikeProductCompatibilityService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Map<String, _CachedProductSpecs> _productSpecCache = {};
  final Map<String, _CachedCategoryTechMapping> _categoryTechMappingCache = {};

  static const Duration _cacheMaxAge = Duration(minutes: 5);

  static const Set<String> _brakeRelevantSpecKeys = {
    'bleed_port',
    'brake_position',
    'brake_system',
    'brake_type',
    'caliper_hydraulic',
    'compound_type',
    'fluid_type',
    'hose_fitting_type',
    'hose_length_mm',
    'mount_standard',
    'pad_compatibility_note',
    'pad_finned',
    'pad_shape_code',
    'pad_spring_included',
    'piston_count',
    'reach_adjust',
    'rotor_diameter_mm',
    'rotor_floating',
    'rotor_material',
    'rotor_mount_type',
    'rotor_thickness_mm',
    'tool_size_mm',
  };

  static const Set<String> _wheelRelevantSpecKeys = {
    'bearing_application',
    'bearing_size_code',
    'bearing_system',
    'freehub_type',
    'headset_standard',
    'hub_spacing_mm',
    'sealant_volume_ml',
    'spoke_bend_type',
    'spoke_gauge',
    'spoke_holes',
    'spoke_length_mm',
    'steerer_type',
    'valve_length_mm',
    'valve_type',
    'wheel_position',
    'wheel_size',
  };

  Future<Map<String, ProductCompatibilityAssessment>>
      buildAutocompleteAssessments({
    required Bike bike,
    required BikeProfile profile,
    required List<Product> products,
  }) async {
    if (products.isEmpty) {
      return const {};
    }

    final compatibilityContext = _buildCompatibilityContext(
      bike: bike,
      technicalValues: profile.technicalValues,
    );
    if (compatibilityContext == null) {
      return const {};
    }

    await Future.wait([
      _ensureProductSpecs(products: products, tenantId: bike.tenantId),
      _ensureCategoryTechMappings(products: products, tenantId: bike.tenantId),
    ]);

    final assessments = <String, ProductCompatibilityAssessment>{};
    for (final product in products) {
      final technicalMapping = _technicalMappingForProduct(product);
      final familyAssessment = _assessTechnicalFamilyCompatibility(
        compatibilityContext: compatibilityContext,
        technicalMapping: technicalMapping,
      );
      final detailedAssessment = _assessDetailedCompatibility(
        compatibilityContext: compatibilityContext,
        technicalMapping: technicalMapping,
        specValues: _productSpecCache[product.id]?.values ?? const {},
      );
      final resolvedAssessment = _mergeAssessments(
        familyAssessment: familyAssessment,
        detailedAssessment: detailedAssessment,
      );
      if (resolvedAssessment != null) {
        assessments[product.id] = resolvedAssessment;
      }
    }

    return assessments;
  }

  Future<void> _ensureProductSpecs({
    required List<Product> products,
    required String tenantId,
  }) async {
    final missingIds = products.map((product) => product.id).where((productId) {
      final cached = _productSpecCache[productId];
      return cached == null || !_isCacheFresh(cached.fetchedAt);
    }).toList(growable: false);

    if (missingIds.isEmpty) {
      return;
    }

    final fetchedAt = DateTime.now();
    final valuesByProductId = <String, Map<String, dynamic>>{
      for (final productId in missingIds) productId: <String, dynamic>{},
    };

    final rows = await _client.from('product_spec_values').select('''
          product_id,
          value_text,
          value_number,
          value_boolean,
          value_option,
          value_json,
          display_value,
          spec_definitions!inner(key)
        ''').eq('tenant_id', tenantId).inFilter('product_id', missingIds);

    for (final row in rows) {
      final productId = row['product_id']?.toString();
      final definition = row['spec_definitions'];
      final specKey = definition is Map ? definition['key']?.toString() : null;
      if (productId == null || specKey == null) {
        continue;
      }

      final value = _resolveSpecValue(row);
      if (value == null) {
        continue;
      }

      valuesByProductId[productId]?[specKey] = value;
    }

    for (final entry in valuesByProductId.entries) {
      _productSpecCache[entry.key] = _CachedProductSpecs(
        values: entry.value,
        fetchedAt: fetchedAt,
      );
    }
  }

  Future<void> _ensureCategoryTechMappings({
    required List<Product> products,
    required String tenantId,
  }) async {
    final missingCategoryIds = products
        .map((product) => product.categoryId?.trim())
        .whereType<String>()
        .where((categoryId) => categoryId.isNotEmpty)
        .where((categoryId) {
          final cached = _categoryTechMappingCache[categoryId];
          return cached == null || !_isCacheFresh(cached.fetchedAt);
        })
        .toSet()
        .toList(growable: false);

    if (missingCategoryIds.isEmpty) {
      return;
    }

    final fetchedAt = DateTime.now();
    final mappingByCategoryId = <String, _CategoryTechMapping?>{
      for (final categoryId in missingCategoryIds) categoryId: null,
    };

    final mappingRows = await _client
        .from('category_tech_mappings')
        .select('''
          category_id,
          technical_family,
          template_id
        ''')
        .eq('tenant_id', tenantId)
        .inFilter('category_id', missingCategoryIds);

    final templateIds = mappingRows
        .map((row) => row['template_id']?.toString())
        .whereType<String>()
        .where((templateId) => templateId.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final templateKeyById = <String, String?>{};
    if (templateIds.isNotEmpty) {
      final templateRows =
          await _client.from('spec_templates').select('id, key').inFilter(
                'id',
                templateIds,
              );

      for (final row in templateRows) {
        final templateId = row['id']?.toString();
        if (templateId == null || templateId.isEmpty) {
          continue;
        }
        templateKeyById[templateId] =
            _normalizeSemanticToken(row['key']?.toString());
      }
    }

    for (final row in mappingRows) {
      final categoryId = row['category_id']?.toString();
      final technicalFamily =
          _normalizeSemanticToken(row['technical_family']?.toString());
      if (categoryId == null || categoryId.isEmpty || technicalFamily == null) {
        continue;
      }

      final templateId = row['template_id']?.toString();
      mappingByCategoryId[categoryId] = _CategoryTechMapping(
        technicalFamily: technicalFamily,
        templateKey: templateId == null || templateId.isEmpty
            ? null
            : templateKeyById[templateId],
      );
    }

    for (final entry in mappingByCategoryId.entries) {
      _categoryTechMappingCache[entry.key] = _CachedCategoryTechMapping(
        mapping: entry.value,
        fetchedAt: fetchedAt,
      );
    }
  }

  _CategoryTechMapping? _technicalMappingForProduct(Product product) {
    final categoryId = product.categoryId?.trim();
    if (categoryId == null || categoryId.isEmpty) {
      return null;
    }
    return _categoryTechMappingCache[categoryId]?.mapping;
  }

  bool _isCacheFresh(DateTime fetchedAt) {
    return DateTime.now().difference(fetchedAt) < _cacheMaxAge;
  }

  ProductCompatibilityAssessment? _mergeAssessments({
    required ProductCompatibilityAssessment? familyAssessment,
    required ProductCompatibilityAssessment? detailedAssessment,
  }) {
    if (familyAssessment?.level == ProductCompatibilityLevel.incompatible) {
      return familyAssessment;
    }

    return detailedAssessment ?? familyAssessment;
  }

  ProductCompatibilityAssessment? _assessTechnicalFamilyCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required _CategoryTechMapping? technicalMapping,
  }) {
    final semanticKeys = _semanticKeysForMapping(technicalMapping);
    if (semanticKeys.isEmpty) {
      return null;
    }

    for (final semanticKey in semanticKeys) {
      switch (semanticKey) {
        case 'rotor':
          return _assessRotorFamilyCompatibility(compatibilityContext);
        case 'hub':
        case 'hub_generic':
        case 'front_hub':
        case 'rear_hub':
          return _assessHubFamilyCompatibility(compatibilityContext);
        case 'rim':
          return _assessRimFamilyCompatibility(compatibilityContext);
        case 'spoke':
          return _assessSpokeFamilyCompatibility(compatibilityContext);
        case 'tube':
        case 'tube_anti_pinchazo':
          return _assessTubeFamilyCompatibility(compatibilityContext);
        case 'rim_strip':
          return _assessRimStripFamilyCompatibility(compatibilityContext);
        case 'tubeless_valve':
          return _assessTubelessValveFamilyCompatibility(
            compatibilityContext,
          );
        case 'tubeless_consumable':
        case 'tubeless_sealant':
          return _assessTubelessConsumableFamilyCompatibility(
            compatibilityContext,
          );
        case 'headset':
          return _assessHeadsetFamilyCompatibility(compatibilityContext);
        case 'bearing':
          return _assessBearingFamilyCompatibility(compatibilityContext);
        case 'bottom_bracket':
          return _assessBottomBracketFamilyCompatibility(
            compatibilityContext,
          );
        case 'rim_brake':
          return _assessRimBrakeFamilyCompatibility(compatibilityContext);
        case 'hydraulic_disc_brake':
          return _assessHydraulicDiscFamilyCompatibility(compatibilityContext);
        case 'mechanical_disc_brake':
          return _assessMechanicalDiscFamilyCompatibility(
            compatibilityContext,
          );
        case 'disc_brake':
        case 'disc':
          return _assessDiscBrakeFamilyCompatibility(compatibilityContext);
        case 'brake_pad':
          return _assessBrakePadFamilyCompatibility(compatibilityContext);
        case 'brake_caliper':
          return _assessBrakeCaliperFamilyCompatibility(compatibilityContext);
        case 'brake_lever':
          return _assessBrakeLeverFamilyCompatibility(compatibilityContext);
      }
    }

    return null;
  }

  List<String> _semanticKeysForMapping(_CategoryTechMapping? technicalMapping) {
    if (technicalMapping == null) {
      return const [];
    }

    return {
      if (technicalMapping.templateKey != null &&
          technicalMapping.templateKey!.isNotEmpty)
        technicalMapping.templateKey!,
      if (technicalMapping.technicalFamily.isNotEmpty)
        technicalMapping.technicalFamily,
    }.toList(growable: false);
  }

  ProductCompatibilityAssessment? _assessDetailedCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required _CategoryTechMapping? technicalMapping,
    required Map<String, dynamic> specValues,
  }) {
    if (specValues.isEmpty) {
      return null;
    }

    final relevantKeys = specValues.keys
        .where(
          (key) =>
              _brakeRelevantSpecKeys.contains(key) ||
              _wheelRelevantSpecKeys.contains(key),
        )
        .toSet();
    if (relevantKeys.isEmpty) {
      return null;
    }

    if (relevantKeys.any(_brakeRelevantSpecKeys.contains)) {
      return _assessBrakeCompatibility(
        compatibilityContext: compatibilityContext,
        specValues: specValues,
      );
    }

    final semanticKeys = _semanticKeysForMapping(technicalMapping);
    if (semanticKeys.isEmpty) {
      return null;
    }

    for (final semanticKey in semanticKeys) {
      switch (semanticKey) {
        case 'hub':
        case 'hub_generic':
        case 'front_hub':
        case 'rear_hub':
          return _assessDetailedHubCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'rim':
          return _assessDetailedRimCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'tube':
        case 'tube_anti_pinchazo':
          return _assessDetailedTubeCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'rim_strip':
          return _assessDetailedRimStripCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'tubeless_valve':
          return _assessDetailedTubelessValveCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
      }
    }

    return null;
  }

  ProductCompatibilityAssessment? _assessDetailedHubCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final wheelPosition = _canonicalWheelPosition(specValues['wheel_position']);
    final hubSpacingMm = _parseDoubleValue(specValues['hub_spacing_mm']);
    final spokeHoles = _parseIntValue(specValues['spoke_holes']);
    final freehubType = _canonicalFreehubType(specValues['freehub_type']);

    if (wheelPosition == null &&
        hubSpacingMm == null &&
        spokeHoles == null &&
        freehubType == null) {
      return null;
    }

    if (wheelPosition == null || wheelPosition == 'both') {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Maza; la ficha debe confirmar si es delantera o trasera',
        sortPriority: 20,
      );
    }

    final isFront = wheelPosition == 'front';
    final expectedSpacing = isFront
        ? compatibilityContext.frontHubSpacingMm
        : compatibilityContext.rearHubSpacingMm;
    final expectedSpokeHoles = isFront
        ? compatibilityContext.frontSpokeHoles
        : compatibilityContext.rearSpokeHoles;
    final expectedFreehubType = isFront
        ? null
        : _canonicalFreehubType(compatibilityContext.freehubType);

    if (hubSpacingMm != null &&
        expectedSpacing != null &&
        !_sameNumericValue(hubSpacingMm, expectedSpacing)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Maza ${_wheelPositionLabel(wheelPosition)} ${_formatMeasurement(hubSpacingMm)} mm no coincide con la bici (${_formatMeasurement(expectedSpacing)} mm)',
      );
    }

    if (spokeHoles != null &&
        expectedSpokeHoles != null &&
        spokeHoles != expectedSpokeHoles) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Maza ${_wheelPositionLabel(wheelPosition)} ${spokeHoles}H no coincide con la bici (${expectedSpokeHoles}H)',
      );
    }

    if (!isFront &&
        freehubType != null &&
        expectedFreehubType != null &&
        freehubType != expectedFreehubType) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Maza trasera con driver ${_freehubTypeLabel(freehubType)} no coincide con la bici (${_freehubTypeLabel(expectedFreehubType)})',
      );
    }

    final matchedParts = <String>[];
    final unresolvedParts = <String>[];

    if (hubSpacingMm != null) {
      if (expectedSpacing != null) {
        matchedParts.add('ancho ${_formatMeasurement(hubSpacingMm)} mm');
      } else {
        unresolvedParts.add('ancho del cuadro/horquilla');
      }
    }

    if (spokeHoles != null) {
      if (expectedSpokeHoles != null) {
        matchedParts.add('${spokeHoles}H');
      } else {
        unresolvedParts.add('perforaciones de la rueda');
      }
    }

    if (!isFront && freehubType != null) {
      if (expectedFreehubType != null) {
        matchedParts.add('driver ${_freehubTypeLabel(freehubType)}');
      } else {
        unresolvedParts.add('driver / freehub de la bici');
      }
    }

    if (matchedParts.isNotEmpty && unresolvedParts.isEmpty) {
      return ProductCompatibilityAssessment.compatible(
        detail:
            'Maza ${_wheelPositionLabel(wheelPosition)} compatible (${matchedParts.join(' · ')})',
      );
    }

    final detailParts = <String>[
      'Maza ${_wheelPositionLabel(wheelPosition)}',
      if (matchedParts.isNotEmpty) 'coincide ${matchedParts.join(' · ')}',
      if (unresolvedParts.isNotEmpty)
        'falta confirmar ${unresolvedParts.join(', ')}',
    ];

    return ProductCompatibilityAssessment.caution(
      detail: detailParts.join('; '),
      sortPriority: 18,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedRimCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final productWheelSize = _canonicalWheelSize(specValues['wheel_size']);
    final bikeWheelSize = _canonicalWheelSize(compatibilityContext.wheelSize);
    final productSpokeHoles = _parseIntValue(specValues['spoke_holes']);
    final productValveType = _canonicalValveType(specValues['valve_type']);
    final bikeValveType = _canonicalValveType(compatibilityContext.valveType);

    if (productWheelSize == null &&
        productSpokeHoles == null &&
        productValveType == null) {
      return null;
    }

    if (productWheelSize != null &&
        bikeWheelSize != null &&
        productWheelSize != bikeWheelSize) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Llanta $productWheelSize no coincide con la bici ($bikeWheelSize)',
      );
    }

    final matchingSides = <String>[];
    final knownSpokeSides = <String>[];
    if (productSpokeHoles != null) {
      if (compatibilityContext.frontSpokeHoles != null) {
        knownSpokeSides.add('delantera');
        if (productSpokeHoles == compatibilityContext.frontSpokeHoles) {
          matchingSides.add('delantera');
        }
      }
      if (compatibilityContext.rearSpokeHoles != null) {
        knownSpokeSides.add('trasera');
        if (productSpokeHoles == compatibilityContext.rearSpokeHoles) {
          matchingSides.add('trasera');
        }
      }

      if (knownSpokeSides.isNotEmpty && matchingSides.isEmpty) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Llanta ${productSpokeHoles}H no coincide con la bici (${knownSpokeSides.join(' / ')})',
        );
      }
    }

    final matchedParts = <String>[];
    final unresolvedParts = <String>[];
    final cautionParts = <String>[];

    if (productWheelSize != null) {
      if (bikeWheelSize != null) {
        matchedParts.add('aro $productWheelSize');
      } else {
        unresolvedParts.add('rodado de la bici');
      }
    }

    if (productSpokeHoles != null) {
      if (matchingSides.isNotEmpty) {
        final sideHint = matchingSides.length == 2
            ? 'ambas ruedas'
            : 'rueda ${matchingSides.first}';
        matchedParts.add('${productSpokeHoles}H ($sideHint)');
      } else if (knownSpokeSides.isEmpty) {
        unresolvedParts.add('perforaciones de la rueda');
      }
    }

    if (productValveType != null) {
      if (bikeValveType != null) {
        if (productValveType == bikeValveType) {
          matchedParts.add('válvula ${_valveTypeLabel(productValveType)}');
        } else {
          cautionParts.add(
            'ojo con el taladro de válvula (${_valveTypeLabel(productValveType)} vs ${_valveTypeLabel(bikeValveType)})',
          );
        }
      } else {
        unresolvedParts.add('tipo de válvula de la bici');
      }
    }

    if (matchedParts.length >= 2 &&
        unresolvedParts.isEmpty &&
        cautionParts.isEmpty) {
      return ProductCompatibilityAssessment.compatible(
        detail: 'Llanta compatible (${matchedParts.join(' · ')})',
      );
    }

    final detailParts = <String>[
      'Llanta',
      if (matchedParts.isNotEmpty) 'coincide ${matchedParts.join(' · ')}',
      if (cautionParts.isNotEmpty) cautionParts.join(' · '),
      if (unresolvedParts.isNotEmpty)
        'falta confirmar ${unresolvedParts.join(', ')}',
    ];

    return ProductCompatibilityAssessment.caution(
      detail: detailParts.join('; '),
      sortPriority: 18,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedTubeCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final productWheelSize = _canonicalWheelSize(specValues['wheel_size']);
    final bikeWheelSize = _canonicalWheelSize(compatibilityContext.wheelSize);
    final productValveType = _canonicalValveType(specValues['valve_type']);
    final bikeValveType = _canonicalValveType(compatibilityContext.valveType);

    if (productWheelSize == null && productValveType == null) {
      return null;
    }

    if (productWheelSize != null &&
        bikeWheelSize != null &&
        productWheelSize != bikeWheelSize) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cámara $productWheelSize no coincide con la bici ($bikeWheelSize)',
      );
    }

    if (productValveType != null &&
        bikeValveType != null &&
        productValveType != bikeValveType) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cámara con válvula ${_valveTypeLabel(productValveType)} no coincide con la bici (${_valveTypeLabel(bikeValveType)})',
      );
    }

    final matchedParts = <String>[];
    final unresolvedParts = <String>[];

    if (productWheelSize != null) {
      if (bikeWheelSize != null) {
        matchedParts.add('aro $productWheelSize');
      } else {
        unresolvedParts.add('rodado de la bici');
      }
    }

    if (productValveType != null) {
      if (bikeValveType != null) {
        matchedParts.add('válvula ${_valveTypeLabel(productValveType)}');
      } else {
        unresolvedParts.add('tipo de válvula de la bici');
      }
    }

    if (matchedParts.isNotEmpty && unresolvedParts.isEmpty) {
      return ProductCompatibilityAssessment.compatible(
        detail: 'Cámara compatible (${matchedParts.join(' · ')})',
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Cámara; coincide ${matchedParts.join(' · ')}${matchedParts.isNotEmpty && unresolvedParts.isNotEmpty ? '; ' : ''}${unresolvedParts.isNotEmpty ? 'falta confirmar ${unresolvedParts.join(', ')}' : ''}',
      sortPriority: 18,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedRimStripCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final productWheelSize = _canonicalWheelSize(specValues['wheel_size']);
    final bikeWheelSize = _canonicalWheelSize(compatibilityContext.wheelSize);
    final productValveType = _canonicalValveType(specValues['valve_type']);
    final bikeValveType = _canonicalValveType(compatibilityContext.valveType);

    if (productWheelSize == null && productValveType == null) {
      return null;
    }

    if (productWheelSize != null &&
        bikeWheelSize != null &&
        productWheelSize != bikeWheelSize) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cubre cámara $productWheelSize no coincide con la bici ($bikeWheelSize)',
      );
    }

    if (productValveType != null &&
        bikeValveType != null &&
        productValveType != bikeValveType) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cubre cámara para válvula ${_valveTypeLabel(productValveType)} no coincide con la bici (${_valveTypeLabel(bikeValveType)})',
      );
    }

    final matchedParts = <String>[];
    final unresolvedParts = <String>[];

    if (productWheelSize != null) {
      if (bikeWheelSize != null) {
        matchedParts.add('aro $productWheelSize');
      } else {
        unresolvedParts.add('rodado de la bici');
      }
    }

    if (productValveType != null) {
      if (bikeValveType != null) {
        matchedParts.add('válvula ${_valveTypeLabel(productValveType)}');
      } else {
        unresolvedParts.add('tipo de válvula de la bici');
      }
    }

    if (matchedParts.isNotEmpty && unresolvedParts.isEmpty) {
      return ProductCompatibilityAssessment.compatible(
        detail: 'Cubre cámara compatible (${matchedParts.join(' · ')})',
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Cubre cámara; coincide ${matchedParts.join(' · ')}${matchedParts.isNotEmpty && unresolvedParts.isNotEmpty ? '; ' : ''}${unresolvedParts.isNotEmpty ? 'falta confirmar ${unresolvedParts.join(', ')}' : ''}',
      sortPriority: 20,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedTubelessValveCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final productValveType = _canonicalValveType(specValues['valve_type']);
    final bikeValveType = _canonicalValveType(compatibilityContext.valveType);

    if (productValveType == null) {
      return null;
    }

    if (bikeValveType != null && productValveType != bikeValveType) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Válvula tubeless ${_valveTypeLabel(productValveType)} no coincide con la bici (${_valveTypeLabel(bikeValveType)})',
      );
    }

    if (bikeValveType != null) {
      return ProductCompatibilityAssessment.compatible(
        detail:
            'Válvula tubeless compatible (${_valveTypeLabel(productValveType)})',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Válvula tubeless; falta confirmar el tipo de válvula de la bici',
      sortPriority: 18,
    );
  }

  ProductCompatibilityAssessment? _assessRotorFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Rotor para disco; falta confirmar el sistema de freno de la bici',
        sortPriority: 32,
      );
    }

    if (!_isDiscBrakeType(brakeType)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Rotor para disco, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Rotor para disco; revisar diametro y rueda',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessHubFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final hasHubFacts = compatibilityContext.frontHubSpacingMm != null ||
        compatibilityContext.rearHubSpacingMm != null ||
        compatibilityContext.frontSpokeHoles != null ||
        compatibilityContext.rearSpokeHoles != null ||
        compatibilityContext.freehubType != null;

    if (!hasHubFacts) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Maza; falta confirmar ancho, perforaciones y driver del wheelset',
        sortPriority: 36,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Maza; revisar posición, ancho, perforaciones y compatibilidad del driver',
      sortPriority: 26,
    );
  }

  ProductCompatibilityAssessment? _assessRimFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final wheelSize = compatibilityContext.wheelSize;
    if (wheelSize == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Aro; falta confirmar rodado, perforaciones y sistema de freno',
        sortPriority: 36,
      );
    }

    final brakeType = compatibilityContext.brakeType;
    final brakeHint =
        brakeType == null ? 'sistema de freno' : _brakeTypePhrase(brakeType);

    return ProductCompatibilityAssessment.caution(
      detail:
          'Aro $wheelSize; revisar perforaciones y compatibilidad con $brakeHint',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessSpokeFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final frontSpokeHoles = compatibilityContext.frontSpokeHoles;
    final rearSpokeHoles = compatibilityContext.rearSpokeHoles;
    if (frontSpokeHoles == null && rearSpokeHoles == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Rayo; falta confirmar largo, calibre y perforaciones de la rueda',
        sortPriority: 38,
      );
    }

    final knownHoleCounts = <int>{
      if (frontSpokeHoles != null) frontSpokeHoles,
      if (rearSpokeHoles != null) rearSpokeHoles,
    }.toList()
      ..sort();

    return ProductCompatibilityAssessment.caution(
      detail:
          'Rayo; revisar largo, calibre y perforaciones (${knownHoleCounts.join('/')}H)',
      sortPriority: 28,
    );
  }

  ProductCompatibilityAssessment? _assessTubeFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final wheelSize = compatibilityContext.wheelSize;
    final valveType = compatibilityContext.valveType;

    if (wheelSize == null && valveType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Cámara; falta confirmar rodado y tipo de válvula de la bici',
        sortPriority: 36,
      );
    }

    final detailParts = <String>[
      'Cámara',
      if (wheelSize != null) 'aro $wheelSize',
      if (valveType != null) 'válvula ${_valveTypeLabel(valveType)}',
    ];

    return ProductCompatibilityAssessment.caution(
      detail: '${detailParts.join(' · ')}; revisar ancho exacto del neumático',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessRimStripFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    if (compatibilityContext.wheelSize == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Cubre cámara; falta confirmar rodado y ancho del aro',
        sortPriority: 36,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Cubre cámara para aro ${compatibilityContext.wheelSize}; revisar ancho del aro y perforación de válvula',
      sortPriority: 26,
    );
  }

  ProductCompatibilityAssessment? _assessTubelessValveFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final wheelSize = compatibilityContext.wheelSize;
    if (wheelSize == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Válvula tubeless; falta confirmar rodado, largo y compatibilidad del aro',
        sortPriority: 36,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Válvula tubeless para aro $wheelSize; revisar largo de válvula y formato del aro',
      sortPriority: 26,
    );
  }

  ProductCompatibilityAssessment? _assessTubelessConsumableFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    if (compatibilityContext.wheelSize == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Consumible tubeless; falta confirmar si la bici usa un sistema tubeless compatible',
        sortPriority: 38,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Consumible tubeless para aro ${compatibilityContext.wheelSize}; revisar si el aro y neumático trabajan tubeless',
      sortPriority: 30,
    );
  }

  ProductCompatibilityAssessment? _assessHeadsetFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    if (compatibilityContext.bikeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Juego de dirección; falta confirmar el estándar de dirección de la bici',
        sortPriority: 40,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Juego de dirección; revisar estándar, rodamientos superior/inferior y tipo de cuadro',
      sortPriority: 34,
    );
  }

  ProductCompatibilityAssessment? _assessBearingFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final hasBearingContext = compatibilityContext.frontHubSpacingMm != null ||
        compatibilityContext.rearHubSpacingMm != null ||
        compatibilityContext.bottomBracketFamily != null ||
        compatibilityContext.bikeType != null;

    if (!hasBearingContext) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Rodamiento; falta contexto para saber si corresponde a maza, dirección o pedalier',
        sortPriority: 40,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Rodamiento; revisar si corresponde a maza, dirección o pedalier y confirmar medida exacta',
      sortPriority: 34,
    );
  }

  ProductCompatibilityAssessment? _assessBottomBracketFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final bottomBracketFamily = compatibilityContext.bottomBracketFamily;
    if (bottomBracketFamily == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Pedalier / BB; falta confirmar el estándar de la bici',
        sortPriority: 36,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Pedalier / BB ${_bottomBracketFamilyLabel(bottomBracketFamily)}; revisar estándar, eje y ancho de caja',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessRimBrakeFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto para freno de llanta; falta confirmar el sistema de la bici',
        sortPriority: 32,
      );
    }

    if (brakeType != 'rim') {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Producto para freno de llanta, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    final rimBrakeFamily = compatibilityContext.rimBrakeFamily;
    if (rimBrakeFamily == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Freno de llanta; falta confirmar el subtipo exacto',
        sortPriority: 24,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Freno de llanta; revisar subtipo ${_rimBrakeFamilyLabel(rimBrakeFamily)}',
      sortPriority: 22,
    );
  }

  ProductCompatibilityAssessment? _assessHydraulicDiscFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto hidraulico; falta confirmar el sistema de freno de la bici',
        sortPriority: 32,
      );
    }

    if (brakeType == 'disc') {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto hidraulico; falta confirmar si la bici es mecanica o hidraulica',
        sortPriority: 24,
      );
    }

    if (brakeType != 'hydraulic_disc') {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Producto hidraulico, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Producto hidraulico; revisar rotor, montaje y manguera',
      sortPriority: 22,
    );
  }

  ProductCompatibilityAssessment? _assessMechanicalDiscFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto para disco mecanico; falta confirmar el sistema de freno de la bici',
        sortPriority: 32,
      );
    }

    if (brakeType == 'disc') {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto para disco mecanico; falta confirmar si la bici es mecanica o hidraulica',
        sortPriority: 24,
      );
    }

    if (brakeType != 'mechanical_disc') {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Producto para disco mecanico, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Producto para disco mecanico; revisar rotor, montaje y tiro',
      sortPriority: 22,
    );
  }

  ProductCompatibilityAssessment? _assessDiscBrakeFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto para freno de disco; falta confirmar el sistema de la bici',
        sortPriority: 32,
      );
    }

    if (!_isDiscBrakeType(brakeType)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Producto para freno de disco, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Producto para freno de disco; revisar subtipo, rotor y montaje',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessBrakePadFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Pastillas de freno; falta confirmar si la bici usa freno de disco',
        sortPriority: 32,
      );
    }

    if (!_isDiscBrakeType(brakeType)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Pastillas de freno para disco, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Pastillas de freno; revisar forma y compatibilidad del caliper',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessBrakeCaliperFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Caliper de freno; falta confirmar si la bici usa freno de disco',
        sortPriority: 32,
      );
    }

    if (!_isDiscBrakeType(brakeType)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Caliper para disco, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    if (brakeType == 'hydraulic_disc') {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Caliper hidraulico; revisar montaje, manguera y rotor',
        sortPriority: 22,
      );
    }

    if (brakeType == 'mechanical_disc') {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Caliper mecanico; revisar montaje, tiro y rotor',
        sortPriority: 22,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Caliper para disco; falta confirmar si la bici es mecanica o hidraulica',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessBrakeLeverFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Manilla de freno; falta confirmar el sistema de freno de la bici',
        sortPriority: 34,
      );
    }

    if (brakeType == 'coaster_brake') {
      return const ProductCompatibilityAssessment.incompatible(
        detail:
            'Manilla de freno no corresponde a una bici con freno contrapedal',
      );
    }

    if (brakeType == 'hydraulic_disc') {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Manilla de freno; revisar sistema hidraulico y compatibilidad del conjunto',
        sortPriority: 26,
      );
    }

    if (brakeType == 'mechanical_disc' || brakeType == 'rim') {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Manilla de freno; revisar tiro y compatibilidad del sistema',
        sortPriority: 26,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Manilla de freno; revisar compatibilidad con el sistema de la bici',
      sortPriority: 30,
    );
  }

  ProductCompatibilityAssessment? _assessBrakeCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final bikeBrakeType = compatibilityContext.brakeType;
    final productBrakeType = _canonicalBrakeType(specValues['brake_type']);
    final productRotorSize = _parseRotorSize(specValues['rotor_diameter_mm']);
    final productWheel =
        canonicalBrakeWheelValue(specValues['brake_position']?.toString());
    final productFluidType =
        canonicalBrakeFluidTypeValue(specValues['fluid_type']?.toString());

    if (productFluidType != null) {
      if (bikeBrakeType == null) {
        return const ProductCompatibilityAssessment.caution(
          detail:
              'Producto hidraulico; falta confirmar el sistema de freno de la bici',
          sortPriority: 30,
        );
      }
      if (bikeBrakeType == 'disc') {
        return const ProductCompatibilityAssessment.caution(
          detail: 'Producto hidraulico; revisar si la bici usa DOT o mineral',
          sortPriority: 28,
        );
      }
      if (bikeBrakeType != 'hydraulic_disc') {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Producto hidraulico, pero la bici usa ${_brakeTypePhrase(bikeBrakeType)}',
        );
      }
    }

    if (productRotorSize != null) {
      if (bikeBrakeType == null) {
        return ProductCompatibilityAssessment.caution(
          detail:
              'Rotor ${productRotorSize} mm; falta confirmar el sistema de freno de la bici',
          sortPriority: 28,
        );
      }

      if (!_isDiscBrakeType(bikeBrakeType)) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Rotor ${productRotorSize} mm, pero la bici usa ${_brakeTypePhrase(bikeBrakeType)}',
        );
      }
    }

    if (productBrakeType != null) {
      if (bikeBrakeType == null) {
        return ProductCompatibilityAssessment.caution(
          detail:
              'Producto para ${_brakeTypePhrase(productBrakeType)}; falta confirmar la bici',
          sortPriority: 30,
        );
      }

      if (bikeBrakeType == 'disc' && productBrakeType != 'rim') {
        return const ProductCompatibilityAssessment.caution(
          detail:
              'La bici tiene freno de disco, pero falta confirmar si es mecanico o hidraulico',
          sortPriority: 26,
        );
      }

      if (!_areBrakeTypesCompatible(bikeBrakeType, productBrakeType)) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'La bici usa ${_brakeTypePhrase(bikeBrakeType)} y el producto es para ${_brakeTypePhrase(productBrakeType)}',
        );
      }
    }

    if (productRotorSize != null) {
      final rotorAssessment = _assessRotorCompatibility(
        compatibilityContext: compatibilityContext,
        rotorSizeMm: productRotorSize,
        wheel: productWheel,
      );
      if (rotorAssessment != null) {
        return rotorAssessment;
      }
    }

    if (productFluidType != null && bikeBrakeType == 'hydraulic_disc') {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Producto hidraulico; revisar si usa DOT o mineral',
        sortPriority: 30,
      );
    }

    if (productBrakeType != null && productBrakeType != 'disc') {
      return ProductCompatibilityAssessment.compatible(
        detail: 'Compatible con ${_brakeTypePhrase(productBrakeType)}',
      );
    }

    if (productBrakeType == 'disc') {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Producto de disco; revisar si corresponde a mecanico o hidraulico',
        sortPriority: 35,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Hay señales de compatibilidad, pero faltan datos para confirmarla',
      sortPriority: 45,
    );
  }

  ProductCompatibilityAssessment? _assessRotorCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required int rotorSizeMm,
    required String? wheel,
  }) {
    final expectedSizes = <int>{};

    switch (wheel) {
      case 'front':
        if (compatibilityContext.frontRotorSizeMm != null) {
          expectedSizes.add(compatibilityContext.frontRotorSizeMm!);
        }
        break;
      case 'rear':
        if (compatibilityContext.rearRotorSizeMm != null) {
          expectedSizes.add(compatibilityContext.rearRotorSizeMm!);
        }
        break;
      case 'both':
      case null:
        if (compatibilityContext.frontRotorSizeMm != null) {
          expectedSizes.add(compatibilityContext.frontRotorSizeMm!);
        }
        if (compatibilityContext.rearRotorSizeMm != null) {
          expectedSizes.add(compatibilityContext.rearRotorSizeMm!);
        }
        break;
    }

    if (expectedSizes.isEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Rotor ${rotorSizeMm} mm; falta confirmar el diametro de la bici',
        sortPriority: 30,
      );
    }

    if (expectedSizes.contains(rotorSizeMm)) {
      return ProductCompatibilityAssessment.compatible(
        detail: 'Rotor ${rotorSizeMm} mm compatible con la bici',
        sortPriority: 0,
      );
    }

    final sortedExpectedSizes = expectedSizes.toList()..sort();
    return ProductCompatibilityAssessment.incompatible(
      detail:
          'Rotor ${rotorSizeMm} mm no coincide con la bici (${sortedExpectedSizes.join('/')} mm)',
    );
  }

  _BikeCompatibilityContext? _buildCompatibilityContext({
    required Bike bike,
    required Map<String, dynamic> technicalValues,
  }) {
    final compatibilityContext = _BikeCompatibilityContext(
      bikeType: bike.bikeType?.dbValue,
      wheelSize: _normalizeCompatibilityValue(bike.wheelSize),
      frontHubSpacingMm: bike.frontHubSpacingMm,
      rearHubSpacingMm: bike.rearHubSpacingMm,
      brakeType: _canonicalBrakeType(technicalValues['brakeType']),
      rimBrakeFamily: _canonicalRimBrakeFamily(
        technicalValues['rimBrakeFamily'],
      ),
      frontRotorSizeMm: _parseRotorSize(technicalValues['frontRotorSizeMm']),
      rearRotorSizeMm: _parseRotorSize(technicalValues['rearRotorSizeMm']),
      drivetrainConfig: _normalizeCompatibilityValue(
        technicalValues['drivetrainConfig'],
      ),
      drivetrainSpeeds: _parseIntValue(technicalValues['drivetrainSpeeds']),
      freehubType: _normalizeCompatibilityValue(technicalValues['freehubType']),
      frontSpokeHoles:
          _parseIntValue(technicalValues['frontSpokeHoles']) ?? bike.spokeCount,
      rearSpokeHoles:
          _parseIntValue(technicalValues['rearSpokeHoles']) ?? bike.spokeCount,
      valveType: _normalizeCompatibilityValue(technicalValues['valveType']),
      bottomBracketFamily: _normalizeCompatibilityValue(
        technicalValues['bottomBracketFamily'],
      ),
    );

    if (!compatibilityContext.hasKernelFacts) {
      return null;
    }

    return compatibilityContext;
  }

  dynamic _resolveSpecValue(Map<String, dynamic> row) {
    final optionValue = row['value_option'];
    if (optionValue != null && optionValue.toString().trim().isNotEmpty) {
      return optionValue;
    }

    final textValue = row['value_text'];
    if (textValue != null && textValue.toString().trim().isNotEmpty) {
      return textValue;
    }

    if (row['value_number'] != null) {
      return row['value_number'];
    }

    if (row['value_boolean'] != null) {
      return row['value_boolean'];
    }

    if (row['value_json'] != null) {
      return row['value_json'];
    }

    final displayValue = row['display_value'];
    if (displayValue != null && displayValue.toString().trim().isNotEmpty) {
      return displayValue;
    }

    return null;
  }

  int? _parseRotorSize(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue is num) {
      return rawValue.round();
    }

    final rawText = rawValue.toString().trim();
    if (rawText.isEmpty) {
      return null;
    }

    final exactValue = canonicalBrakeRotorSizeValue(rawText);
    if (exactValue != null) {
      return int.tryParse(exactValue);
    }

    final match = RegExp(r'(140|160|180|203)').firstMatch(rawText);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _parseIntValue(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.round();
    }
    return int.tryParse(rawValue.toString().trim());
  }

  double? _parseDoubleValue(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue is double) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toDouble();
    }
    return double.tryParse(rawValue.toString().trim());
  }

  bool _sameNumericValue(double left, double right) {
    return (left - right).abs() < 0.6;
  }

  bool _areBrakeTypesCompatible(String bikeBrakeType, String productBrakeType) {
    if (bikeBrakeType == productBrakeType) {
      return true;
    }

    final bikeIsDisc = _isDiscBrakeType(bikeBrakeType);
    final productIsDisc = _isDiscBrakeType(productBrakeType);

    if (productBrakeType == 'disc') {
      return bikeIsDisc;
    }

    if (bikeBrakeType == 'disc') {
      return productIsDisc;
    }

    if (bikeBrakeType == 'rim' && productBrakeType == 'rim') {
      return true;
    }

    return false;
  }

  bool _isDiscBrakeType(String? brakeType) {
    return brakeType == 'disc' || _discBrakeTypes.contains(brakeType);
  }

  String? _canonicalBrakeType(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized == 'rim' ||
        normalized.contains('llanta') ||
        normalized.contains('v_brake') ||
        normalized.contains('v brake') ||
        normalized.contains('cantilever') ||
        normalized.contains('caliper')) {
      return 'rim';
    }

    if (normalized == 'mechanical_disc' ||
        normalized == 'disc_mechanical' ||
        (normalized.contains('mecanic') && normalized.contains('disc')) ||
        (normalized.contains('mecanico') && normalized.contains('disc')) ||
        (normalized.contains('mecanico') && normalized.contains('disco'))) {
      return 'mechanical_disc';
    }

    if (normalized == 'hydraulic_disc' ||
        normalized == 'disc_hydraulic' ||
        normalized.contains('hidraulic') ||
        normalized.contains('hidraulico')) {
      return 'hydraulic_disc';
    }

    if (normalized == 'disc' || normalized == 'disco') {
      return 'disc';
    }

    if (normalized.contains('roller')) {
      return 'roller_brake';
    }
    if (normalized.contains('drum') || normalized.contains('tambor')) {
      return 'drum_brake';
    }
    if (normalized.contains('coaster') || normalized.contains('contrapedal')) {
      return 'coaster_brake';
    }
    if (normalized.contains('band') || normalized.contains('banda')) {
      return 'band_brake';
    }

    return normalized;
  }

  String? _canonicalRimBrakeFamily(dynamic rawValue) {
    final normalized = _normalizeSemanticToken(rawValue?.toString());
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    if (kRimBrakeFamilyOptionValues.contains(normalized) ||
        normalized == 'other' ||
        normalized == 'unknown') {
      return normalized;
    }

    return normalized;
  }

  String? _canonicalWheelSize(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString()).replaceAll('"', '');
    if (normalized.isEmpty ||
        normalized == 'other' ||
        normalized == 'otra' ||
        normalized == 'unknown' ||
        normalized == 'desconocido') {
      return null;
    }

    if (normalized.contains('700c')) {
      return '700c';
    }
    if (normalized.contains('650b') || normalized.contains('27.5')) {
      return '27.5"';
    }
    if (RegExp(r'(^|[^0-9])29([^0-9]|$)').hasMatch(normalized)) {
      return '29"';
    }
    if (RegExp(r'(^|[^0-9])26([^0-9]|$)').hasMatch(normalized)) {
      return '26"';
    }
    if (RegExp(r'(^|[^0-9])24([^0-9]|$)').hasMatch(normalized)) {
      return '24"';
    }
    if (RegExp(r'(^|[^0-9])20([^0-9]|$)').hasMatch(normalized)) {
      return '20"';
    }
    if (RegExp(r'(^|[^0-9])16([^0-9]|$)').hasMatch(normalized)) {
      return '16"';
    }
    if (RegExp(r'(^|[^0-9])12([^0-9]|$)').hasMatch(normalized)) {
      return '12"';
    }

    return rawValue.toString().trim();
  }

  String? _canonicalWheelPosition(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.contains('delan') || normalized == 'front') {
      return 'front';
    }
    if (normalized.contains('tras') || normalized == 'rear') {
      return 'rear';
    }
    if (normalized.contains('universal') ||
        normalized.contains('amb') ||
        normalized == 'both') {
      return 'both';
    }

    return null;
  }

  String _wheelPositionLabel(String wheelPosition) {
    switch (wheelPosition) {
      case 'front':
        return 'delantera';
      case 'rear':
        return 'trasera';
      case 'both':
        return 'universal';
      default:
        return wheelPosition;
    }
  }

  String? _canonicalValveType(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.contains('desconoc')) {
      return null;
    }
    if (normalized.contains('presta')) {
      return 'presta';
    }
    if (normalized.contains('schrader')) {
      return 'schrader';
    }
    if (normalized.contains('dunlop')) {
      return 'dunlop';
    }
    if (normalized == 'other' || normalized.contains('otra')) {
      return 'other';
    }

    return normalized;
  }

  String? _canonicalFreehubType(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.contains('desconoc')) {
      return null;
    }
    if (normalized.contains('shimano') && normalized.contains('hg')) {
      return 'shimano_hg';
    }
    if (normalized.contains('micro spline') ||
        normalized.contains('microspline')) {
      return 'microspline';
    }
    if (normalized.contains('sram') && normalized.contains('xd')) {
      return 'sram_xd';
    }
    if (normalized.contains('campagnolo')) {
      return 'campagnolo';
    }
    if (normalized.contains('roscada') ||
        normalized.contains('threaded') ||
        normalized.contains('rueda libre')) {
      return 'threaded_freewheel';
    }
    if (normalized.contains('driver') || normalized.contains('bmx')) {
      return 'bmx_driver';
    }
    if (normalized.contains('fija') || normalized.contains('fixed')) {
      return 'fixed_threaded';
    }
    if (normalized.contains('contrapedal') || normalized.contains('coaster')) {
      return 'coaster_hub';
    }

    return _normalizeSemanticToken(rawValue.toString());
  }

  String _brakeTypeLabel(String brakeType) {
    if (brakeType == 'disc') {
      return 'Disco';
    }
    return kBrakeTypeDisplayLabels[brakeType] ?? brakeType;
  }

  String _brakeTypePhrase(String brakeType) {
    switch (brakeType) {
      case 'rim':
        return 'freno de llanta';
      case 'disc':
        return 'freno de disco';
      case 'mechanical_disc':
        return 'freno de disco mecanico';
      case 'hydraulic_disc':
        return 'freno de disco hidraulico';
      case 'roller_brake':
        return 'roller brake';
      case 'drum_brake':
        return 'freno de tambor';
      case 'coaster_brake':
        return 'freno contrapedal';
      case 'band_brake':
        return 'freno de banda';
      default:
        return _brakeTypeLabel(brakeType).toLowerCase();
    }
  }

  String _rimBrakeFamilyLabel(String rimBrakeFamily) {
    return kRimBrakeFamilyOptions[rimBrakeFamily] ?? rimBrakeFamily;
  }

  String _valveTypeLabel(String valveType) {
    switch (valveType) {
      case 'presta':
        return 'Presta';
      case 'schrader':
        return 'Schrader';
      case 'dunlop':
        return 'Dunlop';
      case 'other':
        return 'otra';
      default:
        return valveType;
    }
  }

  String _freehubTypeLabel(String freehubType) {
    switch (freehubType) {
      case 'shimano_hg':
        return 'Shimano HG';
      case 'microspline':
        return 'Micro Spline';
      case 'sram_xd':
        return 'SRAM XD';
      case 'campagnolo':
        return 'Campagnolo';
      case 'threaded_freewheel':
        return 'Rueda libre roscada';
      case 'bmx_driver':
        return 'Driver BMX';
      case 'fixed_threaded':
        return 'Rosca fija / contratuerca';
      case 'coaster_hub':
        return 'Maza contrapedal';
      default:
        return freehubType;
    }
  }

  String _formatMeasurement(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  String _bottomBracketFamilyLabel(String bottomBracketFamily) {
    switch (bottomBracketFamily) {
      case 'bsa_threaded':
        return 'BSA roscado';
      case 'pressfit':
        return 'Pressfit';
      case 'bb30_pf30':
        return 'BB30 / PF30';
      case 'mid':
        return 'Mid / BMX';
      case 'one_piece':
        return 'One-piece';
      case 'unknown':
        return 'sin confirmar';
      default:
        return bottomBracketFamily;
    }
  }

  String? _normalizeCompatibilityValue(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeSemanticToken(String? rawValue) {
    final normalized = _normalizeCompatibilityValue(rawValue);
    if (normalized == null) {
      return null;
    }

    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _normalizeText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }
}

const Set<String> _discBrakeTypes = {
  'mechanical_disc',
  'hydraulic_disc',
};

class _CachedProductSpecs {
  final Map<String, dynamic> values;
  final DateTime fetchedAt;

  const _CachedProductSpecs({
    required this.values,
    required this.fetchedAt,
  });
}

class _CachedCategoryTechMapping {
  final _CategoryTechMapping? mapping;
  final DateTime fetchedAt;

  const _CachedCategoryTechMapping({
    required this.mapping,
    required this.fetchedAt,
  });
}

class _CategoryTechMapping {
  final String technicalFamily;
  final String? templateKey;

  const _CategoryTechMapping({
    required this.technicalFamily,
    required this.templateKey,
  });

  String get semanticKey => templateKey ?? technicalFamily;
}

class _BikeCompatibilityContext {
  final String? bikeType;
  final String? wheelSize;
  final double? frontHubSpacingMm;
  final double? rearHubSpacingMm;
  final String? brakeType;
  final String? rimBrakeFamily;
  final int? frontRotorSizeMm;
  final int? rearRotorSizeMm;
  final String? drivetrainConfig;
  final int? drivetrainSpeeds;
  final String? freehubType;
  final int? frontSpokeHoles;
  final int? rearSpokeHoles;
  final String? valveType;
  final String? bottomBracketFamily;

  const _BikeCompatibilityContext({
    required this.bikeType,
    required this.wheelSize,
    required this.frontHubSpacingMm,
    required this.rearHubSpacingMm,
    required this.brakeType,
    required this.rimBrakeFamily,
    required this.frontRotorSizeMm,
    required this.rearRotorSizeMm,
    required this.drivetrainConfig,
    required this.drivetrainSpeeds,
    required this.freehubType,
    required this.frontSpokeHoles,
    required this.rearSpokeHoles,
    required this.valveType,
    required this.bottomBracketFamily,
  });

  bool get hasKernelFacts {
    return bikeType != null ||
        wheelSize != null ||
        frontHubSpacingMm != null ||
        rearHubSpacingMm != null ||
        brakeType != null ||
        rimBrakeFamily != null ||
        frontRotorSizeMm != null ||
        rearRotorSizeMm != null ||
        drivetrainConfig != null ||
        drivetrainSpeeds != null ||
        freehubType != null ||
        frontSpokeHoles != null ||
        rearSpokeHoles != null ||
        valveType != null ||
        bottomBracketFamily != null;
  }
}
