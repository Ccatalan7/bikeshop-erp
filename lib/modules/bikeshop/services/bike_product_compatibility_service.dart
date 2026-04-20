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
      final familyAssessment = _assessTechnicalFamilyCompatibility(
        compatibilityContext: compatibilityContext,
        technicalMapping: _technicalMappingForProduct(product),
      );
      final detailedAssessment = _assessDetailedCompatibility(
        compatibilityContext: compatibilityContext,
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
    final semanticKey = technicalMapping?.semanticKey;
    if (semanticKey == null || semanticKey.isEmpty) {
      return null;
    }

    switch (semanticKey) {
      case 'rotor':
        return _assessRotorFamilyCompatibility(compatibilityContext);
      case 'rim_brake':
        return _assessRimBrakeFamilyCompatibility(compatibilityContext);
      case 'hydraulic_disc_brake':
        return _assessHydraulicDiscFamilyCompatibility(compatibilityContext);
      default:
        return null;
    }
  }

  ProductCompatibilityAssessment? _assessDetailedCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    if (specValues.isEmpty) {
      return null;
    }

    final relevantKeys =
        specValues.keys.where(_brakeRelevantSpecKeys.contains).toSet();
    if (relevantKeys.isEmpty) {
      return null;
    }

    return _assessBrakeCompatibility(
      compatibilityContext: compatibilityContext,
      specValues: specValues,
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
