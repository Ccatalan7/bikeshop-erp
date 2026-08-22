import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/product_compatibility.dart';
import '../config/brake_canonical_data.dart';
import '../models/bikeshop_models.dart';
import '../utils/drivetrain_compatibility_projection.dart';

class BikeProductCompatibilityCategoryMappingSeed {
  const BikeProductCompatibilityCategoryMappingSeed({
    required this.technicalFamily,
    this.templateKey,
  });

  final String technicalFamily;
  final String? templateKey;
}

class BikeProductCompatibilityService {
  BikeProductCompatibilityService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
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

  static const Set<String> _drivetrainRelevantSpecKeys = {
    'bb_shell_width_mm',
    'bb_shell_diameter_mm',
    'bb_bearing_width_mm',
    'bb_thread_standard',
    'bearing_inner_diameter_mm',
    'bearing_outer_diameter_mm',
    'bearing_size_code',
    'bb_construction',
    'bb_shell_standard',
    'bottom_bracket_family',
    'cassette_cog_sequence',
    'chain_connector_type',
    'chain_directional',
    'chain_ebike_rated',
    'chain_link_pack_qty',
    'chain_link_reusable',
    'chain_outer_width_mm',
    'chain_profile_family',
    'chain_speed',
    'chain_speeds',
    'chain_width_family',
    'chainline_mm',
    'chainring_bcd_mm',
    'chainring_bolt_count',
    'chainring_mount_type',
    'chainring_offset_mm',
    'chainring_teeth',
    'crank_arm_length_mm',
    'crank_side',
    'derailleur_cage_length',
    'derailleur_clutch',
    'drivetrain_compatibility_family',
    'drivetrain_declared_compatible_ecosystems',
    'drivetrain_mode',
    'drivetrain_primary_ecosystem',
    'drivetrain_speed',
    'drivetrain_platform',
    'drivetrain_speeds',
    'front_chainring_count',
    'front_derailleur_clamp_mm',
    'front_derailleur_mount_type',
    'front_derailleur_pull_direction',
    'hanger_model_code',
    'largest_cog_teeth',
    'link_count',
    'narrow_wide',
    'pedal_thread',
    'pulley_teeth',
    'quick_link_included',
    'rear_cog_count',
    'rear_derailleur_max_teeth',
    'rear_derailleur_min_teeth',
    'rear_derailleur_mount_type',
    'rear_derailleur_total_capacity_teeth',
    'shift_actuation_family',
    'shifter_position',
    'single_cog_teeth',
    'speed',
    'speed_compatibility',
    'speeds',
    'spindle_diameter_mm',
    'spindle_interface',
    'spindle_length_mm',
  };

  static const Set<String> _drivetrainSpeedSpecKeys = {
    'chain_speed',
    'chain_speeds',
    'drivetrain_speed',
    'drivetrain_speeds',
    'rear_cog_count',
    'speed',
    'speed_compatibility',
    'speeds',
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

  @visibleForTesting
  void primeCompatibilityCaches({
    Map<String, Map<String, dynamic>> productSpecsByProductId = const {},
    Map<String, BikeProductCompatibilityCategoryMappingSeed?>
        categoryMappingsByCategoryId = const {},
    DateTime? fetchedAt,
  }) {
    final resolvedFetchedAt = fetchedAt ?? DateTime.now();

    for (final entry in productSpecsByProductId.entries) {
      _productSpecCache[entry.key] = _CachedProductSpecs(
        values: Map<String, dynamic>.from(entry.value),
        fetchedAt: resolvedFetchedAt,
      );
    }

    for (final entry in categoryMappingsByCategoryId.entries) {
      final seed = entry.value;
      final technicalFamily = seed == null
          ? null
          : _normalizeSemanticToken(seed.technicalFamily.trim());
      final templateKey = seed == null || seed.templateKey == null
          ? null
          : _normalizeSemanticToken(seed.templateKey!.trim());

      _categoryTechMappingCache[entry.key] = _CachedCategoryTechMapping(
        mapping: technicalFamily == null
            ? null
            : _CategoryTechMapping(
                technicalFamily: technicalFamily,
                templateKey: templateKey,
              ),
        fetchedAt: resolvedFetchedAt,
      );
    }
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

    final client = _client ?? Supabase.instance.client;
    // El scorer lee el registro unificado. Antes leía `product_spec_values`,
    // donde el valor de una lista es la etiqueta congelada en la fila; ahora la
    // resuelve desde el vocabulario, así que un renombre no rompe una
    // compatibilidad que ya estaba puntuada.
    final rows = await client.from('spec_facts').select('''
          subject_id,
          value_text,
          value_number,
          value_boolean,
          spec_definitions!inner(key),
          spec_fact_values(position, spec_definition_values!inner(label))
        ''')
        .eq('tenant_id', tenantId)
        .eq('subject_type', 'product')
        .isFilter('subject_scope', null)
        .inFilter('subject_id', missingIds);

    for (final row in rows) {
      final productId = row['subject_id']?.toString();
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

    final client = _client ?? Supabase.instance.client;
    final mappingRows = await client
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
          await client.from('spec_templates').select('id, key').inFilter(
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
        case 'chain':
        case 'bike_chain':
          return _assessChainFamilyCompatibility(compatibilityContext);
        case 'chain_link':
          return _assessChainLinkFamilyCompatibility(compatibilityContext);
        case 'cassette':
          return _assessCassetteFamilyCompatibility(compatibilityContext);
        case 'freewheel':
          return _assessFreewheelFamilyCompatibility(compatibilityContext);
        case 'fixed_cog':
          return _assessFixedCogFamilyCompatibility(compatibilityContext);
        case 'rear_derailleur':
          return _assessRearDerailleurFamilyCompatibility(
            compatibilityContext,
          );
        case 'front_derailleur':
          return _assessFrontDerailleurFamilyCompatibility(
            compatibilityContext,
          );
        case 'shifter':
          return _assessShifterFamilyCompatibility(compatibilityContext);
        case 'crankset':
        case 'chainring':
        case 'drivetrain_kit':
          return _assessCrankDriveFamilyCompatibility(
            compatibilityContext,
            label: _drivetrainFamilyLabel(semanticKey),
          );
        case 'bottom_bracket_axle':
        case 'bottom_bracket_cup':
        case 'bottom_bracket_bearing':
          return _assessBottomBracketFamilyCompatibility(
            compatibilityContext,
          );
        case 'derailleur_hanger':
          return const ProductCompatibilityAssessment.caution(
            detail:
                'Postiza de cambio; confirmar modelo exacto de cuadro y montaje',
            sortPriority: 34,
          );
        case 'derailleur_pulley':
          return const ProductCompatibilityAssessment.caution(
            detail:
                'Roldana de cambio; confirmar dientes, caja y compatibilidad del cambio',
            sortPriority: 34,
          );
        case 'chain_guide':
          return const ProductCompatibilityAssessment.caution(
            detail:
                'Guia de cadena; confirmar montaje, plato y linea de cadena',
            sortPriority: 34,
          );
        case 'cassette_spacer':
          return const ProductCompatibilityAssessment.caution(
            detail:
                'Espaciador de cassette; confirmar driver/freehub, generacion del cuerpo y espesor',
            sortPriority: 34,
          );
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
              _drivetrainRelevantSpecKeys.contains(key) ||
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
        case 'chain':
        case 'bike_chain':
        case 'chain_link':
          return _assessDetailedChainCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'cassette':
          return _assessDetailedRearCogCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
            familyLabel: 'Cassette',
          );
        case 'freewheel':
          return _assessDetailedRearCogCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
            familyLabel: 'Piñón / rueda libre',
          );
        case 'fixed_cog':
          return _assessDetailedRearCogCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
            familyLabel: 'Piñón fijo',
          );
        case 'rear_derailleur':
          return _assessDetailedRearDerailleurCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'front_derailleur':
          return _assessDetailedFrontDerailleurCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'shifter':
          return _assessDetailedShifterCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
        case 'bottom_bracket':
        case 'bottom_bracket_axle':
        case 'bottom_bracket_cup':
        case 'bottom_bracket_bearing':
          return _assessDetailedBottomBracketCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
            familyLabel: _drivetrainFamilyLabel(semanticKey),
          );
        case 'crankset':
          return _assessDetailedCranksetCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
            familyLabel: _drivetrainFamilyLabel(semanticKey),
          );
        case 'drivetrain_kit':
          return _assessDetailedDrivetrainKitCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
            familyLabel: _drivetrainFamilyLabel(semanticKey),
          );
        case 'chainring':
          return _assessDetailedChainringCompatibility(
            compatibilityContext: compatibilityContext,
            specValues: specValues,
          );
      }
    }

    return null;
  }

  ProductCompatibilityAssessment? _assessChainFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    if (expectedSpeed == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Cadena; falta confirmar velocidad de transmisión de la bici',
        sortPriority: 34,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Cadena; falta confirmar velocidad compatible del producto (${expectedSpeed}v esperada)',
      sortPriority: 28,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedChainCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    final productSpeeds = _chainSpeedsFromSpecs(specValues);
    final productOuterWidths = _chainOuterWidthsFromSpecs(specValues);
    final effectiveProductSpeeds = productSpeeds.isNotEmpty
        ? productSpeeds
        : _chainSpeedsFromOuterWidths(productOuterWidths);
    final expectedWidths = _expectedChainWidthFamilies(compatibilityContext);
    final productWidths = _chainWidthFamiliesFromSpecs(specValues);
    final bikePlatform = _canonicalDrivetrainPlatform(
      compatibilityContext.drivetrainPlatform ??
          compatibilityContext.shiftActuationFamily,
    );
    final productFamilies =
        _drivetrainCompatibilityFamiliesFromSpecs(specValues);
    final productPlatforms = _drivetrainPlatformsFromSpecs(specValues);

    if (expectedSpeed == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Cadena; falta confirmar velocidad de transmisión de la bici',
        sortPriority: 34,
      );
    }

    if (effectiveProductSpeeds.isEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Cadena; el producto no tiene velocidad estructurada ni ancho externo nominal util para resolverla (${expectedSpeed}v esperada)',
        sortPriority: 36,
      );
    }

    if (!effectiveProductSpeeds.contains(expectedSpeed)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cadena ${_formatSpeedSet(effectiveProductSpeeds)} no coincide con la bici (${expectedSpeed}v)',
      );
    }

    if (expectedWidths.isNotEmpty &&
        productWidths.isNotEmpty &&
        expectedWidths.intersection(productWidths).isEmpty) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cadena ${_formatChainWidthSet(productWidths)} no coincide con la bici (${_formatChainWidthSet(expectedWidths)})',
      );
    }

    if (bikePlatform != null &&
        productFamilies.isNotEmpty &&
        hasExplicitDrivetrainFamilyConflict(
          bikePlatform: bikePlatform,
          productFamilies: productFamilies,
        )) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cadena declara ${_formatDrivetrainCompatibilityFamilySet(productFamilies)} y no coincide con plataforma ${_drivetrainPlatformLabel(bikePlatform)}',
      );
    }

    if (bikePlatform != null &&
        productPlatforms.isNotEmpty &&
        !_anyDrivetrainPlatformCompatible(
          bikePlatform: bikePlatform,
          productPlatforms: productPlatforms,
        )) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cadena para ${_formatDrivetrainPlatformSet(productPlatforms)} no coincide con plataforma ${_drivetrainPlatformLabel(bikePlatform)}',
      );
    }

    final matchedParts = <String>['${expectedSpeed}v'];
    final reviewParts = <String>[];

    if (productOuterWidths.isNotEmpty) {
      matchedParts.add(_formatChainOuterWidthSet(productOuterWidths));
    }

    if (expectedWidths.isNotEmpty) {
      if (productWidths.isNotEmpty) {
        matchedParts.add(_formatChainWidthSet(productWidths));
      } else {
        reviewParts.add('familia de ancho');
      }
    }

    if (productSpeeds.isEmpty && productOuterWidths.isNotEmpty) {
      reviewParts.add('velocidad inferida desde ancho externo');
    }

    if (bikePlatform != null) {
      if (productPlatforms.isNotEmpty) {
        matchedParts.add(_formatDrivetrainPlatformSet(productPlatforms));
      } else if (productFamilies.isNotEmpty) {
        reviewParts.add('plataforma exacta');
      } else {
        reviewParts.add('perfil/plataforma');
      }
    }

    return ProductCompatibilityAssessment.compatible(
      detail:
          'Cadena compatible (${matchedParts.join(' · ')})${reviewParts.isNotEmpty ? '; falta afinar ${reviewParts.join(', ')}' : ''}',
      sortPriority: reviewParts.isEmpty ? 6 : 8,
    );
  }

  ProductCompatibilityAssessment? _assessChainLinkFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    if (expectedSpeed == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Missing link; falta confirmar velocidad de transmisión de la bici',
        sortPriority: 34,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Missing link; falta confirmar velocidad compatible del producto (${expectedSpeed}v esperada)',
      sortPriority: 28,
    );
  }

  ProductCompatibilityAssessment? _assessCassetteFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final expectedFreehub =
        _canonicalFreehubType(compatibilityContext.freehubType);
    if (_isThreadedRearCogFamily(expectedFreehub)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cassette no corresponde a bici con ${_freehubTypeLabel(expectedFreehub!)}',
      );
    }

    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    if (expectedFreehub == null || expectedSpeed == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Cassette; falta confirmar driver/freehub y velocidades',
        sortPriority: 32,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Cassette para ${expectedSpeed}v; confirmar driver ${_freehubTypeLabel(expectedFreehub)} y rango',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessFreewheelFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final expectedFreehub =
        _canonicalFreehubType(compatibilityContext.freehubType);
    if (expectedFreehub != null && _isCassetteDriverFamily(expectedFreehub)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Piñón/rueda libre roscada no corresponde a bici con ${_freehubTypeLabel(expectedFreehub)}',
      );
    }

    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    if (expectedFreehub == null || expectedSpeed == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Piñón/rueda libre; falta confirmar rosca/driver y velocidades',
        sortPriority: 32,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Piñón/rueda libre para ${expectedSpeed}v; confirmar rosca y rango',
      sortPriority: 24,
    );
  }

  ProductCompatibilityAssessment? _assessFixedCogFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final expectedFreehub =
        _canonicalFreehubType(compatibilityContext.freehubType);
    if (expectedFreehub != null &&
        expectedFreehub != 'fixed_threaded' &&
        expectedFreehub != 'threaded_freewheel') {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Piñón fijo no corresponde a bici con ${_freehubTypeLabel(expectedFreehub)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Piñón fijo; confirmar rosca fija, dientes y ancho de cadena',
      sortPriority: 28,
    );
  }

  ProductCompatibilityAssessment? _assessRearDerailleurFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    if (expectedSpeed == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Cambio trasero; falta confirmar velocidades de transmisión de la bici',
        sortPriority: 34,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Cambio trasero para ${expectedSpeed}v; confirmar indexado, montaje y piñón máximo',
      sortPriority: 26,
    );
  }

  ProductCompatibilityAssessment? _assessFrontDerailleurFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final frontCount = _frontChainringCountFromContext(compatibilityContext);
    if (frontCount == 1) {
      return const ProductCompatibilityAssessment.incompatible(
        detail: 'Desviador delantero no corresponde a transmisión 1x',
      );
    }

    if (frontCount == null) {
      return const ProductCompatibilityAssessment.caution(
        detail: 'Desviador delantero; falta confirmar si la bici es 2x o 3x',
        sortPriority: 34,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          'Desviador delantero para ${frontCount}x; confirmar abrazadera, tiro e indexado',
      sortPriority: 26,
    );
  }

  ProductCompatibilityAssessment? _assessShifterFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final rearSpeed = _chainSpeedFromContext(compatibilityContext);
    final frontCount = _frontChainringCountFromContext(compatibilityContext);
    if (rearSpeed == null && frontCount == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Shifter; falta confirmar velocidades y configuracion de transmisión',
        sortPriority: 34,
      );
    }

    final parts = <String>[
      if (frontCount != null) '${frontCount}x',
      if (rearSpeed != null) '${rearSpeed}v',
    ];
    return ProductCompatibilityAssessment.caution(
      detail: 'Shifter para ${parts.join(' ')}; confirmar lado e indexado',
      sortPriority: 26,
    );
  }

  ProductCompatibilityAssessment? _assessCrankDriveFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext, {
    required String label,
  }) {
    final frontCount = _frontChainringCountFromContext(compatibilityContext);
    final bottomBracketFamily =
        _canonicalBottomBracketFamily(compatibilityContext.bottomBracketFamily);
    if (frontCount == null && bottomBracketFamily == null) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$label; falta confirmar configuracion delantera y pedalier de la bici',
        sortPriority: 34,
      );
    }

    final parts = <String>[
      if (frontCount != null) '${frontCount}x',
      if (bottomBracketFamily != null)
        _bottomBracketFamilyLabel(bottomBracketFamily),
    ];
    return ProductCompatibilityAssessment.caution(
      detail: '$label ${parts.join(' · ')}; confirmar montaje y medidas',
      sortPriority: 28,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedRearCogCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
    required String familyLabel,
  }) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    final productSpeeds = _drivetrainSpeedsFromSpecs(specValues);
    final expectedFreehub =
        _canonicalFreehubType(compatibilityContext.freehubType);
    final productFreehub = _canonicalFreehubType(specValues['freehub_type']);

    if (expectedSpeed != null &&
        productSpeeds.isNotEmpty &&
        !productSpeeds.contains(expectedSpeed)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel ${_formatSpeedSet(productSpeeds)} no coincide con la bici (${expectedSpeed}v)',
      );
    }

    if (expectedFreehub != null &&
        productFreehub != null &&
        !_areFreehubTypesCompatible(expectedFreehub, productFreehub)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel para ${_freehubTypeLabel(productFreehub)} no coincide con la bici (${_freehubTypeLabel(expectedFreehub)})',
      );
    }

    final bikePlatform = _canonicalDrivetrainPlatform(
      compatibilityContext.drivetrainPlatform ??
          compatibilityContext.shiftActuationFamily,
    );
    final productFamilies =
        _drivetrainCompatibilityFamiliesFromSpecs(specValues);
    final productPlatforms = _drivetrainPlatformsFromSpecs(specValues);
    final productLargestCog = _parseIntValue(specValues['largest_cog_teeth']);
    final hasFamilyConflict = bikePlatform != null &&
        productFamilies.isNotEmpty &&
        hasExplicitDrivetrainFamilyConflict(
          bikePlatform: bikePlatform,
          productFamilies: productFamilies,
        );
    final hasPlatformMismatch = bikePlatform != null &&
        productPlatforms.isNotEmpty &&
        !_anyDrivetrainPlatformCompatible(
          bikePlatform: bikePlatform,
          productPlatforms: productPlatforms,
        );

    final matchedParts = <String>[];
    final unresolvedParts = <String>[];

    if (expectedSpeed != null) {
      if (productSpeeds.contains(expectedSpeed)) {
        matchedParts.add('${expectedSpeed}v');
      } else {
        unresolvedParts.add('velocidades del producto');
      }
    } else if (productSpeeds.isNotEmpty) {
      unresolvedParts.add('velocidades de la bici');
    }

    if (expectedFreehub != null) {
      if (productFreehub != null &&
          _areFreehubTypesCompatible(expectedFreehub, productFreehub)) {
        matchedParts.add(_freehubTypeLabel(expectedFreehub));
      } else {
        unresolvedParts.add('driver/freehub del producto');
      }
    } else if (productFreehub != null) {
      unresolvedParts.add('driver/freehub de la bici');
    }

    if (bikePlatform != null &&
        productPlatforms.isEmpty &&
        productFamilies.isNotEmpty) {
      unresolvedParts.add('plataforma exacta');
    }

    if (productLargestCog == null) {
      unresolvedParts.add('rango/piñón mayor');
    }

    if (hasFamilyConflict) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$familyLabel coincide en base (${matchedParts.join(' · ')}), pero revisar ecosistema ${_formatDrivetrainCompatibilityFamilySet(productFamilies)} vs ${_drivetrainPlatformLabel(bikePlatform)}',
        sortPriority: 22,
      );
    }

    if (hasPlatformMismatch) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$familyLabel coincide en base (${matchedParts.join(' · ')}), pero revisar plataforma ${_formatDrivetrainPlatformSet(productPlatforms)} vs ${_drivetrainPlatformLabel(bikePlatform)}',
        sortPriority: 22,
      );
    }

    if (matchedParts.length >= 2 && unresolvedParts.length == 1) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$familyLabel coincide ${matchedParts.join(' · ')}; falta confirmar ${unresolvedParts.join(', ')} y excepciones de cuerpo/espaciadores',
        sortPriority: 18,
      );
    }

    if (matchedParts.length >= 2 && unresolvedParts.isEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$familyLabel coincide ${matchedParts.join(' · ')}; revisar rango real, cuerpo exacto y posibles separadores/excepciones del sistema',
        sortPriority: 16,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          '$familyLabel; ${matchedParts.isNotEmpty ? 'coincide ${matchedParts.join(' · ')}; ' : ''}falta confirmar ${unresolvedParts.isEmpty ? 'ficha completa' : unresolvedParts.join(', ')}',
      sortPriority: 28,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedRearDerailleurCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    final productSpeeds = _drivetrainSpeedsFromSpecs(specValues);
    final expectedLargestCog = compatibilityContext.largestCogTeeth;
    final productMaxCog =
        _parseIntValue(specValues['rear_derailleur_max_teeth']);
    final bikeActuation = _canonicalShiftActuationFamily(
      compatibilityContext.shiftActuationFamily ??
          compatibilityContext.drivetrainPlatform,
    );
    final productActuation = _canonicalShiftActuationFamily(
      specValues['shift_actuation_family'] ?? specValues['drivetrain_platform'],
    );
    final productCageLength =
        _normalizeCompatibilityValue(specValues['derailleur_cage_length']);
    final productTotalCapacity =
        _parseIntValue(specValues['rear_derailleur_total_capacity_teeth']);

    if (expectedSpeed != null &&
        productSpeeds.isNotEmpty &&
        !productSpeeds.contains(expectedSpeed)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cambio trasero ${_formatSpeedSet(productSpeeds)} no coincide con la bici (${expectedSpeed}v)',
      );
    }

    if (expectedLargestCog != null &&
        productMaxCog != null &&
        productMaxCog < expectedLargestCog) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cambio trasero soporta maximo ${productMaxCog}T, pero la bici necesita ${expectedLargestCog}T',
      );
    }

    if (bikeActuation != null &&
        productActuation != null &&
        !_areShiftActuationFamiliesCompatible(
            bikeActuation, productActuation)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Cambio trasero ${_shiftActuationFamilyLabel(productActuation)} no coincide con la bici (${_shiftActuationFamilyLabel(bikeActuation)})',
      );
    }

    final matchedParts = <String>[
      if (expectedSpeed != null && productSpeeds.contains(expectedSpeed))
        '${expectedSpeed}v',
      if (expectedLargestCog != null &&
          productMaxCog != null &&
          productMaxCog >= expectedLargestCog)
        'max ${productMaxCog}T',
      if (bikeActuation != null &&
          productActuation != null &&
          _areShiftActuationFamiliesCompatible(bikeActuation, productActuation))
        _shiftActuationFamilyLabel(productActuation),
    ];
    final reviewParts = <String>[
      if (productCageLength != null)
        'montaje y caja ${productCageLength.replaceAll('_', ' ')}'
      else
        'caja y montaje',
      if (productTotalCapacity != null)
        'capacidad real (${productTotalCapacity}T)'
      else
        'capacidad total',
    ];

    if (matchedParts.isNotEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Cambio trasero coincide ${matchedParts.join(' · ')}; falta confirmar ${reviewParts.join(' y ')}',
        sortPriority: matchedParts.length >= 2 ? 18 : 22,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Cambio trasero; falta velocidad estructurada del producto o de la bici',
      sortPriority: 30,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedFrontDerailleurCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final expectedFrontCount =
        _frontChainringCountFromContext(compatibilityContext);
    if (expectedFrontCount == 1) {
      return const ProductCompatibilityAssessment.incompatible(
        detail: 'Desviador delantero no corresponde a transmisión 1x',
      );
    }

    final productFrontCounts = _frontChainringCountsFromSpecs(specValues);
    if (expectedFrontCount != null &&
        productFrontCounts.isNotEmpty &&
        !productFrontCounts.contains(expectedFrontCount)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Desviador delantero ${_formatFrontCountSet(productFrontCounts)} no coincide con la bici (${expectedFrontCount}x)',
      );
    }

    if (expectedFrontCount != null &&
        productFrontCounts.contains(expectedFrontCount)) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Desviador delantero coincide ${expectedFrontCount}x; falta confirmar abrazadera/montaje, tiro y tamaño del plato grande',
        sortPriority: 22,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Desviador delantero; falta cantidad de platos estructurada del producto o de la bici',
      sortPriority: 30,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedShifterCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final position = _canonicalShifterPosition(specValues['shifter_position']);
    final checksRearSide = position == null ||
        position == 'right' ||
        position == 'pair' ||
        position == 'universal';
    final checksFrontSide = position == null ||
        position == 'left' ||
        position == 'pair' ||
        position == 'universal';
    final expectedRearSpeed = _chainSpeedFromContext(compatibilityContext);
    final expectedFrontCount =
        _frontChainringCountFromContext(compatibilityContext);
    final productSpeeds = _drivetrainSpeedsFromSpecs(specValues);
    final productFrontCounts = _frontChainringCountsFromSpecs(specValues);
    final bikeActuation = _canonicalShiftActuationFamily(
      compatibilityContext.shiftActuationFamily ??
          compatibilityContext.drivetrainPlatform,
    );
    final productActuation = _canonicalShiftActuationFamily(
      specValues['shift_actuation_family'] ?? specValues['drivetrain_platform'],
    );

    final checks = <ProductCompatibilityAssessment>[];

    if (bikeActuation != null &&
        productActuation != null &&
        !_areShiftActuationFamiliesCompatible(
            bikeActuation, productActuation)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Shifter ${_shiftActuationFamilyLabel(productActuation)} no coincide con la bici (${_shiftActuationFamilyLabel(bikeActuation)})',
      );
    }

    if (checksRearSide) {
      if (expectedRearSpeed != null && productSpeeds.isNotEmpty) {
        if (!productSpeeds.contains(expectedRearSpeed)) {
          return ProductCompatibilityAssessment.incompatible(
            detail:
                'Shifter ${_formatSpeedSet(productSpeeds)} no coincide con la bici (${expectedRearSpeed}v)',
          );
        }
        checks.add(ProductCompatibilityAssessment.compatible(
          detail: '${expectedRearSpeed}v',
        ));
      }
    }

    if (checksFrontSide &&
        expectedFrontCount != null &&
        productFrontCounts.isNotEmpty) {
      if (!productFrontCounts.contains(expectedFrontCount)) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Shifter ${_formatFrontCountSet(productFrontCounts)} no coincide con la bici (${expectedFrontCount}x)',
        );
      }
      checks.add(ProductCompatibilityAssessment.compatible(
        detail: '${expectedFrontCount}x',
      ));
    }

    if (bikeActuation != null &&
        productActuation != null &&
        _areShiftActuationFamiliesCompatible(bikeActuation, productActuation)) {
      checks.add(ProductCompatibilityAssessment.compatible(
        detail: _shiftActuationFamilyLabel(productActuation),
      ));
    }

    if (checks.isNotEmpty) {
      final matchedDetails = checks.map((check) => check.detail).join(' · ');
      final exactRearMatch = position == 'right' &&
          expectedRearSpeed != null &&
          productSpeeds.contains(expectedRearSpeed) &&
          bikeActuation != null &&
          productActuation != null &&
          _areShiftActuationFamiliesCompatible(bikeActuation, productActuation);

      if (exactRearMatch) {
        return ProductCompatibilityAssessment.compatible(
          detail: 'Shifter compatible ($matchedDetails)',
          sortPriority: 14,
        );
      }

      final reviewParts = <String>[
        if (position == null) 'lado exacto',
        if (position == 'right' &&
            (bikeActuation == null || productActuation == null))
          'familia de indexado exacta',
        if (position == 'left' ||
            position == 'pair' ||
            position == 'universal' ||
            position == null)
          'tiro/indexado delantero',
      ];

      return ProductCompatibilityAssessment.caution(
        detail:
            'Shifter coincide $matchedDetails; falta confirmar ${reviewParts.isEmpty ? 'ficha completa' : reviewParts.join(', ')}',
        sortPriority: 22,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Shifter; falta ficha de lado/velocidades o configuracion de la bici',
      sortPriority: 30,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedBottomBracketCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
    required String familyLabel,
  }) {
    final expectedFamily =
        _canonicalBottomBracketFamily(compatibilityContext.bottomBracketFamily);
    final productFamily = _canonicalBottomBracketFamily(
      specValues['bb_shell_standard'] ?? specValues['bottom_bracket_family'],
    );
    final expectedShellWidth = compatibilityContext.bbShellWidthMm;
    final productShellWidth =
        _parseDoubleValue(specValues['bb_shell_width_mm']);
    final expectedShellDiameter = compatibilityContext.bbShellDiameterMm;
    final productShellDiameter =
        _parseDoubleValue(specValues['bb_shell_diameter_mm']);
    final expectedSpindleInterface =
        _canonicalSpindleInterface(compatibilityContext.spindleInterface);
    final productSpindleInterface =
        _canonicalSpindleInterface(specValues['spindle_interface']);

    if (expectedFamily != null &&
        productFamily != null &&
        expectedFamily != productFamily) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel ${_bottomBracketFamilyLabel(productFamily)} no coincide con la bici (${_bottomBracketFamilyLabel(expectedFamily)})',
      );
    }

    if (expectedShellWidth != null &&
        productShellWidth != null &&
        !_sameNumericValue(expectedShellWidth, productShellWidth)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel ancho ${_formatMeasurement(productShellWidth)} mm no coincide con la bici (${_formatMeasurement(expectedShellWidth)} mm)',
      );
    }

    if (expectedShellDiameter != null &&
        productShellDiameter != null &&
        !_sameNumericValue(expectedShellDiameter, productShellDiameter)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel diametro ${_formatMeasurement(productShellDiameter)} mm no coincide con la bici (${_formatMeasurement(expectedShellDiameter)} mm)',
      );
    }

    if (expectedSpindleInterface != null &&
        productSpindleInterface != null &&
        expectedSpindleInterface != productSpindleInterface) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel eje ${_spindleInterfaceLabel(productSpindleInterface)} no coincide con la bici (${_spindleInterfaceLabel(expectedSpindleInterface)})',
      );
    }

    final matchedParts = _matchedBottomBracketParts(
      compatibilityContext: compatibilityContext,
      specValues: specValues,
    );

    if (matchedParts.isNotEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$familyLabel coincide ${matchedParts.join(' · ')}; falta confirmar estándar real del shell, montaje y combinación completa del sistema',
        sortPriority: matchedParts.length >= 2 ? 18 : 22,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          '$familyLabel; falta familia de pedalier estructurada del producto o de la bici',
      sortPriority: 32,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedCranksetCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
    required String familyLabel,
  }) {
    final bbAssessment = _assessDetailedBottomBracketCompatibility(
      compatibilityContext: compatibilityContext,
      specValues: specValues,
      familyLabel: familyLabel,
    );
    if (bbAssessment?.level == ProductCompatibilityLevel.incompatible) {
      return bbAssessment;
    }

    final expectedFrontCount =
        _frontChainringCountFromContext(compatibilityContext);
    final productFrontCounts = _frontChainringCountsFromSpecs(specValues);
    if (expectedFrontCount != null &&
        productFrontCounts.isNotEmpty &&
        !productFrontCounts.contains(expectedFrontCount)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel ${_formatFrontCountSet(productFrontCounts)} no coincide con la bici (${expectedFrontCount}x)',
      );
    }

    final matchedParts = <String>[
      ..._matchedBottomBracketParts(
        compatibilityContext: compatibilityContext,
        specValues: specValues,
      ),
      if (expectedFrontCount != null &&
          productFrontCounts.contains(expectedFrontCount))
        '${expectedFrontCount}x',
    ];

    if (matchedParts.isNotEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            '$familyLabel coincide ${matchedParts.join(' · ')}; falta confirmar línea de cadena, largo, montaje y estándar real del crankset',
        sortPriority: 20,
      );
    }

    return ProductCompatibilityAssessment.caution(
      detail:
          '$familyLabel; falta ficha de platos/pedalier o datos upstream de la bici',
      sortPriority: 32,
    );
  }

  List<String> _matchedBottomBracketParts({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final expectedFamily =
        _canonicalBottomBracketFamily(compatibilityContext.bottomBracketFamily);
    final productFamily = _canonicalBottomBracketFamily(
      specValues['bb_shell_standard'] ?? specValues['bottom_bracket_family'],
    );
    final expectedShellWidth = compatibilityContext.bbShellWidthMm;
    final productShellWidth =
        _parseDoubleValue(specValues['bb_shell_width_mm']);
    final expectedShellDiameter = compatibilityContext.bbShellDiameterMm;
    final productShellDiameter =
        _parseDoubleValue(specValues['bb_shell_diameter_mm']);
    final expectedSpindleInterface =
        _canonicalSpindleInterface(compatibilityContext.spindleInterface);
    final productSpindleInterface =
        _canonicalSpindleInterface(specValues['spindle_interface']);

    return <String>[
      if (expectedFamily != null && productFamily == expectedFamily)
        _bottomBracketFamilyLabel(expectedFamily),
      if (expectedShellWidth != null &&
          productShellWidth != null &&
          _sameNumericValue(expectedShellWidth, productShellWidth))
        '${_formatMeasurement(productShellWidth)} mm',
      if (expectedShellDiameter != null &&
          productShellDiameter != null &&
          _sameNumericValue(expectedShellDiameter, productShellDiameter))
        'diam ${_formatMeasurement(productShellDiameter)} mm',
      if (expectedSpindleInterface != null &&
          productSpindleInterface == expectedSpindleInterface)
        _spindleInterfaceLabel(productSpindleInterface!),
    ];
  }

  ProductCompatibilityAssessment? _assessDetailedDrivetrainKitCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
    required String familyLabel,
  }) {
    final baseAssessment = _assessDetailedCranksetCompatibility(
      compatibilityContext: compatibilityContext,
      specValues: specValues,
      familyLabel: familyLabel,
    );
    if (baseAssessment == null ||
        baseAssessment.level == ProductCompatibilityLevel.incompatible) {
      return baseAssessment;
    }

    final suffix =
        'falta confirmar parte trasera de la transmisión y contenido real del kit';
    final baseDetail = baseAssessment.detail;
    final detail = baseDetail == null || baseDetail.trim().isEmpty
        ? '$familyLabel; $suffix'
        : baseDetail.contains('parte trasera')
            ? baseDetail
            : '$baseDetail; $suffix';

    return ProductCompatibilityAssessment.caution(
      detail: detail,
      sortPriority: baseAssessment.level == ProductCompatibilityLevel.compatible
          ? 24
          : baseAssessment.sortPriority,
    );
  }

  ProductCompatibilityAssessment? _assessDetailedChainringCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
  }) {
    final expectedSpeed = _chainSpeedFromContext(compatibilityContext);
    final productSpeeds = _drivetrainSpeedsFromSpecs(specValues);
    final expectedWidths = _expectedChainWidthFamilies(compatibilityContext);
    final productWidths = _chainWidthFamiliesFromSpecs(specValues);
    final bikePlatform = _canonicalDrivetrainPlatform(
      compatibilityContext.drivetrainPlatform ??
          compatibilityContext.shiftActuationFamily,
    );
    final productFamilies =
        _drivetrainCompatibilityFamiliesFromSpecs(specValues);
    final productPlatforms = _drivetrainPlatformsFromSpecs(specValues);

    if (expectedSpeed != null &&
        productSpeeds.isNotEmpty &&
        !productSpeeds.contains(expectedSpeed)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Corona/plato ${_formatSpeedSet(productSpeeds)} no coincide con la bici (${expectedSpeed}v)',
      );
    }

    if (expectedWidths.isNotEmpty &&
        productWidths.isNotEmpty &&
        expectedWidths.intersection(productWidths).isEmpty) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Corona/plato ${_formatChainWidthSet(productWidths)} no coincide con la bici (${_formatChainWidthSet(expectedWidths)})',
      );
    }

    if (bikePlatform != null &&
        productFamilies.isNotEmpty &&
        hasExplicitDrivetrainFamilyConflict(
          bikePlatform: bikePlatform,
          productFamilies: productFamilies,
        )) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Corona/plato coincide en base, pero revisar ecosistema ${_formatDrivetrainCompatibilityFamilySet(productFamilies)} vs ${_drivetrainPlatformLabel(bikePlatform)}',
        sortPriority: 22,
      );
    }

    if (bikePlatform != null &&
        productPlatforms.isNotEmpty &&
        !_anyDrivetrainPlatformCompatible(
          bikePlatform: bikePlatform,
          productPlatforms: productPlatforms,
        )) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Corona/plato coincide en base, pero revisar plataforma ${_formatDrivetrainPlatformSet(productPlatforms)} vs ${_drivetrainPlatformLabel(bikePlatform)}',
        sortPriority: 22,
      );
    }

    final matchedParts = <String>[
      if (expectedSpeed != null && productSpeeds.contains(expectedSpeed))
        '${expectedSpeed}v',
      if (expectedWidths.isNotEmpty &&
          productWidths.isNotEmpty &&
          expectedWidths.intersection(productWidths).isNotEmpty)
        _formatChainWidthSet(productWidths),
      if (bikePlatform != null &&
          productPlatforms.isNotEmpty &&
          _anyDrivetrainPlatformCompatible(
            bikePlatform: bikePlatform,
            productPlatforms: productPlatforms,
          ))
        _formatDrivetrainPlatformSet(productPlatforms),
    ];

    if (matchedParts.isNotEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Corona/plato coincide ${matchedParts.join(' · ')}; falta confirmar BCD/montaje y offset',
        sortPriority: matchedParts.length >= 2 ? 20 : 24,
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail:
          'Corona/plato; falta velocidad o datos de montaje estructurados para confirmar compatibilidad',
      sortPriority: 32,
    );
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
        !_areFreehubTypesCompatible(expectedFreehubType, freehubType)) {
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

    if (!isFront && matchedParts.isNotEmpty && unresolvedParts.isEmpty) {
      return ProductCompatibilityAssessment.caution(
        detail:
            'Maza ${_wheelPositionLabel(wheelPosition)} coincide ${matchedParts.join(' · ')}; revisar generacion/largo real del cuerpo, eje y estandar del conjunto',
        sortPriority: 16,
      );
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
              'Rotor $productRotorSize mm; falta confirmar el sistema de freno de la bici',
          sortPriority: 28,
        );
      }

      if (!_isDiscBrakeType(bikeBrakeType)) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Rotor $productRotorSize mm, pero la bici usa ${_brakeTypePhrase(bikeBrakeType)}',
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
        detail: 'Rotor $rotorSizeMm mm; falta confirmar el diametro de la bici',
        sortPriority: 30,
      );
    }

    if (expectedSizes.contains(rotorSizeMm)) {
      return ProductCompatibilityAssessment.compatible(
        detail: 'Rotor $rotorSizeMm mm compatible con la bici',
        sortPriority: 0,
      );
    }

    final sortedExpectedSizes = expectedSizes.toList()..sort();
    return ProductCompatibilityAssessment.incompatible(
      detail:
          'Rotor $rotorSizeMm mm no coincide con la bici (${sortedExpectedSizes.join('/')} mm)',
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
      drivetrainPlatform: _normalizeCompatibilityValue(
        technicalValues['drivetrainPlatform'] ??
            technicalValues['drivetrainPlatformFamily'],
      ),
      shiftActuationFamily: _normalizeCompatibilityValue(
        technicalValues['shiftActuationFamily'] ??
            technicalValues['shift_actuation_family'],
      ),
      chainWidthFamily: _normalizeCompatibilityValue(
        technicalValues['chainWidthFamily'] ??
            technicalValues['chain_width_family'],
      ),
      largestCogTeeth: _parseIntValue(
        technicalValues['largestCogTeeth'] ??
            technicalValues['rearLargestCogTeeth'] ??
            technicalValues['largest_cog_teeth'],
      ),
      frontSpokeHoles:
          _parseIntValue(technicalValues['frontSpokeHoles']) ?? bike.spokeCount,
      rearSpokeHoles:
          _parseIntValue(technicalValues['rearSpokeHoles']) ?? bike.spokeCount,
      valveType: _normalizeCompatibilityValue(technicalValues['valveType']),
      bottomBracketFamily: _normalizeCompatibilityValue(
        technicalValues['bottomBracketFamily'],
      ),
      bbShellWidthMm: _parseDoubleValue(
        technicalValues['bbShellWidthMm'] ??
            technicalValues['bb_shell_width_mm'],
      ),
      bbShellDiameterMm: _parseDoubleValue(
        technicalValues['bbShellDiameterMm'] ??
            technicalValues['bb_shell_diameter_mm'],
      ),
      spindleInterface: _normalizeCompatibilityValue(
        technicalValues['spindleInterface'] ??
            technicalValues['spindle_interface'],
      ),
    );

    if (!compatibilityContext.hasKernelFacts) {
      return null;
    }

    return compatibilityContext;
  }

  dynamic _resolveSpecValue(Map<String, dynamic> row) {
    // Un hecho de lista trae sus etiquetas en `spec_fact_values`, en el orden
    // en que se eligieron. Un escalar viene en su columna tipada.
    final listaCruda = row['spec_fact_values'];
    if (listaCruda is List && listaCruda.isNotEmpty) {
      final entradas = listaCruda.whereType<Map>().toList()
        ..sort((a, b) => ((a['position'] as num?)?.toInt() ?? 0)
            .compareTo((b['position'] as num?)?.toInt() ?? 0));
      final etiquetas = entradas
          .map((entrada) =>
              (entrada['spec_definition_values'] as Map?)?['label'] as String?)
          .whereType<String>()
          .toList(growable: false);
      if (etiquetas.isEmpty) return null;
      return etiquetas.length == 1 ? etiquetas.first : etiquetas;
    }

    final number = row['value_number'];
    if (number != null) return number;
    final boolean = row['value_boolean'];
    if (boolean != null) return boolean;
    final text = row['value_text'];
    if (text != null && text.toString().trim().isNotEmpty) return text;
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

  int? _chainSpeedFromContext(_BikeCompatibilityContext context) {
    final config = context.drivetrainConfig;
    if (config == 'singlespeed' ||
        config == 'single_speed' ||
        config == 'single speed') {
      return 1;
    }

    final configMatch =
        config == null ? null : RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(config);
    if (configMatch != null) {
      final rearCogCount = int.tryParse(configMatch.group(2) ?? '');
      if (_isPlausibleChainSpeed(rearCogCount)) return rearCogCount;
    }

    final speed = context.drivetrainSpeeds;
    return _isPlausibleChainSpeed(speed) ? speed : null;
  }

  Set<int> _chainSpeedsFromSpecs(Map<String, dynamic> specValues) {
    return _drivetrainSpeedsFromSpecs(specValues);
  }

  Set<int> _drivetrainSpeedsFromSpecs(Map<String, dynamic> specValues) {
    final speeds = <int>{};
    for (final entry in specValues.entries) {
      if (!_drivetrainSpeedSpecKeys.contains(entry.key)) continue;
      speeds.addAll(_parseChainSpeedValues(entry.value));
    }
    return speeds;
  }

  Set<String> _chainWidthFamiliesFromSpecs(Map<String, dynamic> specValues) {
    final widths = <String>{};
    final rawValue = specValues['chain_width_family'];
    if (rawValue == null) return widths;

    void parse(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          parse(item);
        }
        return;
      }
      if (value is Map) {
        for (final item in value.values) {
          parse(item);
        }
        return;
      }

      final canonical = _canonicalChainWidthFamily(value);
      if (canonical != null) widths.add(canonical);
    }

    parse(rawValue);
    return widths;
  }

  Set<double> _chainOuterWidthsFromSpecs(Map<String, dynamic> specValues) {
    final widths = <double>{};
    final rawValue = specValues['chain_outer_width_mm'];
    if (rawValue == null) return widths;

    void parse(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          parse(item);
        }
        return;
      }
      if (value is Map) {
        for (final item in value.values) {
          parse(item);
        }
        return;
      }

      final normalized = value.toString().trim().replaceAll(',', '.');
      final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(normalized);
      final parsed = match == null ? null : double.tryParse(match.group(0)!);
      if (parsed != null && parsed >= 5 && parsed <= 8) {
        widths.add(double.parse(parsed.toStringAsFixed(2)));
      }
    }

    parse(rawValue);
    return widths;
  }

  Set<int> _chainSpeedsFromOuterWidths(Set<double> outerWidths) {
    final speeds = <int>{};
    for (final width in outerWidths) {
      if (width >= 7.75) {
        speeds.add(6);
      } else if (width >= 7.0) {
        speeds.addAll(const {6, 7, 8});
      } else if (width >= 6.55 && width <= 6.75) {
        speeds.add(9);
      } else if (width >= 5.84 && width <= 6.02) {
        speeds.add(10);
      } else if (width >= 5.55 && width <= 5.69) {
        speeds.add(11);
      } else if (width >= 5.20 && width <= 5.35) {
        speeds.add(12);
      }
    }
    return speeds;
  }

  Set<String> _expectedChainWidthFamilies(_BikeCompatibilityContext context) {
    final explicit = _canonicalChainWidthFamily(context.chainWidthFamily);
    if (explicit != null) {
      return {explicit};
    }

    final speed = _chainSpeedFromContext(context);
    if (speed == null) {
      return const {};
    }

    if (speed == 1) {
      return {'one_eighth', 'three_thirty_seconds'};
    }
    if (speed >= 5 && speed <= 8) {
      return {'three_thirty_seconds'};
    }
    if (speed >= 9) {
      return {'eleven_128'};
    }

    return const {};
  }

  String? _canonicalChainWidthFamily(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized == 'other' ||
        normalized == 'otro' ||
        normalized.contains('desconoc')) {
      return null;
    }

    if (normalized.contains('1/8') ||
        normalized.contains('one eighth') ||
        normalized.contains('bmx')) {
      return 'one_eighth';
    }
    if (normalized.contains('3/32') ||
        normalized.contains('6-8') ||
        normalized.contains('5-8')) {
      return 'three_thirty_seconds';
    }
    if (normalized.contains('11/128') ||
        normalized.contains('9-11') ||
        normalized.contains('narrow') ||
        normalized.contains('angost')) {
      return 'eleven_128';
    }

    return _normalizeSemanticToken(rawValue.toString());
  }

  int? _frontChainringCountFromContext(_BikeCompatibilityContext context) {
    final config = context.drivetrainConfig;
    if (config == 'singlespeed' ||
        config == 'single_speed' ||
        config == 'single speed') {
      return 1;
    }

    final configMatch =
        config == null ? null : RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(config);
    if (configMatch != null) {
      final frontCount = int.tryParse(configMatch.group(1) ?? '');
      if (_isPlausibleFrontChainringCount(frontCount)) return frontCount;
    }

    return null;
  }

  Set<int> _frontChainringCountsFromSpecs(Map<String, dynamic> specValues) {
    final counts = <int>{};
    final rawValue = specValues['front_chainring_count'];
    if (rawValue == null) return counts;

    void parse(dynamic value) {
      if (value == null) return;
      if (value is num) {
        final count = value.round();
        if (_isPlausibleFrontChainringCount(count)) counts.add(count);
        return;
      }
      if (value is List) {
        for (final item in value) {
          parse(item);
        }
        return;
      }
      if (value is Map) {
        for (final item in value.values) {
          parse(item);
        }
        return;
      }
      for (final match in RegExp(r'\d').allMatches(value.toString())) {
        final count = int.tryParse(match.group(0) ?? '');
        if (_isPlausibleFrontChainringCount(count)) counts.add(count!);
      }
    }

    parse(rawValue);
    return counts;
  }

  Set<int> _parseChainSpeedValues(dynamic rawValue) {
    final speeds = <int>{};
    if (rawValue == null) return speeds;

    if (rawValue is num) {
      final speed = rawValue.round();
      if (_isPlausibleChainSpeed(speed)) speeds.add(speed);
      return speeds;
    }

    if (rawValue is List) {
      for (final value in rawValue) {
        speeds.addAll(_parseChainSpeedValues(value));
      }
      return speeds;
    }

    if (rawValue is Map) {
      for (final value in rawValue.values) {
        speeds.addAll(_parseChainSpeedValues(value));
      }
      return speeds;
    }

    final text = _normalizeText(rawValue.toString());
    final rangeMatch =
        RegExp(r'(\d{1,2})\s*(?:-|a|to)\s*(\d{1,2})').firstMatch(text);
    if (rangeMatch != null) {
      final start = int.tryParse(rangeMatch.group(1) ?? '');
      final end = int.tryParse(rangeMatch.group(2) ?? '');
      if (_isPlausibleChainSpeed(start) && _isPlausibleChainSpeed(end)) {
        for (var speed = start!; speed <= end!; speed++) {
          if (_isPlausibleChainSpeed(speed)) speeds.add(speed);
        }
      }
    }

    for (final match in RegExp(r'\d{1,2}').allMatches(text)) {
      final speed = int.tryParse(match.group(0) ?? '');
      if (_isPlausibleChainSpeed(speed)) speeds.add(speed!);
    }

    return speeds;
  }

  bool _isPlausibleChainSpeed(int? value) {
    if (value == null) return false;
    return value == 1 || (value >= 5 && value <= 13);
  }

  bool _isPlausibleFrontChainringCount(int? value) {
    if (value == null) return false;
    return value >= 1 && value <= 3;
  }

  String _formatSpeedSet(Set<int> speeds) {
    final sorted = speeds.toList()..sort();
    return '${sorted.join('/')}v';
  }

  String _formatFrontCountSet(Set<int> counts) {
    final sorted = counts.toList()..sort();
    return sorted.map((count) => '${count}x').join('/');
  }

  String _formatChainWidthSet(Set<String> widths) {
    final sorted = widths.map(_chainWidthFamilyLabel).toList()..sort();
    return sorted.join('/');
  }

  String _formatChainOuterWidthSet(Set<double> widths) {
    final sorted = widths.toList()..sort();
    return '${sorted.map((value) => value.toStringAsFixed(value == value.roundToDouble() ? 0 : value * 10 == (value * 10).roundToDouble() ? 1 : 2)).join('/')} mm';
  }

  String _chainWidthFamilyLabel(String width) {
    switch (width) {
      case 'one_eighth':
        return '1/8';
      case 'three_thirty_seconds':
        return '3/32';
      case 'eleven_128':
        return '11/128';
      default:
        return width;
    }
  }

  Set<String> _drivetrainPlatformsFromSpecs(
    Map<String, dynamic> specValues,
  ) {
    return drivetrainPlatformsFromCompatibilitySpecs(specValues);
  }

  Set<String> _drivetrainCompatibilityFamiliesFromSpecs(
    Map<String, dynamic> specValues,
  ) {
    return drivetrainCompatibilityFamiliesFromCompatibilitySpecs(specValues);
  }

  String _formatDrivetrainPlatformSet(Set<String> platforms) {
    final sorted = platforms.map(_drivetrainPlatformLabel).toList()..sort();
    return sorted.join('/');
  }

  String _formatDrivetrainCompatibilityFamilySet(Set<String> families) {
    final sorted = families.map(_drivetrainCompatibilityFamilyLabel).toList()
      ..sort();
    return sorted.join('/');
  }

  bool _anyDrivetrainPlatformCompatible({
    required String bikePlatform,
    required Set<String> productPlatforms,
  }) {
    return productPlatforms.any(
      (productPlatform) => _areDrivetrainPlatformsCompatible(
        bikePlatform,
        productPlatform,
      ),
    );
  }

  bool _areDrivetrainPlatformsCompatible(
    String bikePlatform,
    String productPlatform,
  ) {
    if (bikePlatform == productPlatform) {
      return true;
    }

    if (_isUniversalDrivetrainPlatform(productPlatform)) {
      return true;
    }

    if (bikePlatform == 'shimano_hg_sis' &&
        (productPlatform == 'universal_5_8' ||
            productPlatform == 'universal_9_11' ||
            productPlatform == 'kmc_compatible')) {
      return true;
    }

    if ((bikePlatform == 'shimano_hg_plus' ||
            bikePlatform == 'shimano_linkglide') &&
        productPlatform == 'kmc_compatible') {
      return true;
    }

    if (bikePlatform == 'sram_eagle' &&
        (productPlatform == 'sram_t_type' ||
            productPlatform == 'kmc_compatible')) {
      return true;
    }

    return false;
  }

  bool _isUniversalDrivetrainPlatform(String platform) {
    return platform == 'generic' ||
        platform == 'friction_universal' ||
        platform == 'universal_5_8' ||
        platform == 'universal_9_11' ||
        platform == 'kmc_compatible';
  }

  bool _areShiftActuationFamiliesCompatible(
    String bikeActuation,
    String productActuation,
  ) {
    if (bikeActuation == productActuation) {
      return true;
    }

    return productActuation == 'friction_universal';
  }

  bool _areFreehubTypesCompatible(String expected, String product) {
    if (expected == product) {
      return true;
    }

    // XD cassettes can normally run on an XDR driver with the right spacer,
    // but an XDR cassette should not be treated as fitting a shorter XD body.
    return expected == 'sram_xdr' && product == 'sram_xd';
  }

  bool _isCassetteDriverFamily(String? freehubType) {
    return freehubType == 'shimano_hg' ||
        freehubType == 'shimano_hg_road_11' ||
        freehubType == 'microspline' ||
        freehubType == 'sram_xd' ||
        freehubType == 'sram_xdr' ||
        freehubType == 'campagnolo' ||
        freehubType == 'campagnolo_n3w';
  }

  bool _isThreadedRearCogFamily(String? freehubType) {
    return freehubType == 'threaded_freewheel' ||
        freehubType == 'fixed_threaded' ||
        freehubType == 'bmx_driver' ||
        freehubType == 'coaster_hub';
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
      if (normalized.contains('road') || normalized.contains('11')) {
        return 'shimano_hg_road_11';
      }
      return 'shimano_hg';
    }
    if (normalized.contains('micro spline') ||
        normalized.contains('microspline')) {
      return 'microspline';
    }
    if (normalized.contains('sram') && normalized.contains('xdr')) {
      return 'sram_xdr';
    }
    if (normalized.contains('sram') && normalized.contains('xd')) {
      return 'sram_xd';
    }
    if (normalized.contains('n3w')) {
      return 'campagnolo_n3w';
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

  String? _canonicalDrivetrainPlatform(dynamic rawValue) {
    return drivetrainCompatibilityPlatformToken(rawValue);
  }

  String? _canonicalShiftActuationFamily(dynamic rawValue) {
    final platform = _canonicalDrivetrainPlatform(rawValue);
    if (platform == 'shimano_hg_plus') return 'shimano_dynasys_11_12';
    if (platform == 'shimano_linkglide') return 'shimano_linkglide';
    if (platform == 'sram_eagle') return 'sram_x_actuation';
    if (platform == 'sram_flattop') return 'sram_axs_road';
    if (platform == 'sram_t_type') return 'sram_t_type';
    if (platform == 'campagnolo') return 'campagnolo';
    if (platform == 'microshift_advent') return 'microshift_advent';
    if (platform == 'friction_universal') return 'friction_universal';

    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.contains('desconoc')) {
      return null;
    }

    if (normalized.contains('cues') || normalized.contains('linkglide')) {
      return 'shimano_linkglide';
    }
    if (normalized.contains('dynasys') && normalized.contains('10')) {
      return 'shimano_dynasys_10';
    }
    if (normalized.contains('dynasys') ||
        (normalized.contains('shimano') &&
            (normalized.contains('11') || normalized.contains('12')))) {
      return 'shimano_dynasys_11_12';
    }
    if (normalized.contains('ruta') ||
        normalized.contains('road') ||
        normalized.contains('tiagra') ||
        normalized.contains('sora') ||
        normalized.contains('claris')) {
      return 'shimano_road';
    }
    if (normalized.contains('sis') ||
        normalized.contains('6-9') ||
        normalized.contains('6 a 9')) {
      return 'shimano_sis_6_9';
    }
    if (normalized.contains('exact')) {
      return 'sram_exact';
    }
    if (normalized.contains('x-actuation') ||
        normalized.contains('x actuation')) {
      return 'sram_x_actuation';
    }
    if (normalized.contains('axs')) {
      return 'sram_axs_road';
    }

    return platform;
  }

  String? _canonicalSpindleInterface(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.contains('desconoc')) {
      return null;
    }
    if (normalized.contains('jis')) return 'square_jis';
    if (normalized.contains('iso')) return 'square_iso';
    if (normalized.contains('cuadrado') || normalized.contains('square')) {
      return 'square_taper';
    }
    if (normalized.contains('dub')) return 'sram_dub';
    if (normalized.contains('isis')) return 'isis';
    if (normalized.contains('octalink')) return 'octalink';
    if (normalized.contains('19mm') || normalized.contains('19 mm')) {
      return 'bmx_19';
    }
    if (normalized.contains('22mm') || normalized.contains('22 mm')) {
      return 'bmx_22';
    }
    if (normalized.contains('bmx') &&
        (normalized.contains('24mm') || normalized.contains('24 mm'))) {
      return 'bmx_24';
    }
    if (normalized.contains('hollowtech') ||
        normalized.contains('24mm') ||
        normalized.contains('24 mm') ||
        normalized.contains('integrado')) {
      return 'hollowtech_24';
    }
    if (normalized.contains('one-piece') || normalized.contains('americano')) {
      return 'one_piece';
    }

    return _normalizeSemanticToken(rawValue.toString());
  }

  String? _canonicalBottomBracketFamily(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.contains('desconoc')) {
      return null;
    }

    if (normalized.contains('bsa') ||
        normalized.contains('ingles') ||
        normalized.contains('english') ||
        normalized.contains('1.37')) {
      return 'bsa_threaded';
    }
    // Las cajas roscadas que no son inglesas comparten familia con ella sólo en
    // que se enroscan; su rosca es distinta y no intercambian motor, así que
    // cada una es su propia familia.
    if (normalized.contains('italiano') || normalized.contains('36x24')) {
      return 'italian_threaded';
    }
    if (normalized.contains('t47')) {
      return 't47_threaded';
    }
    if (normalized.contains('frances') || normalized.contains('french')) {
      return 'french_threaded';
    }
    if (normalized.contains('suizo') || normalized.contains('swiss')) {
      return 'swiss_threaded';
    }
    if (normalized.contains('euro bmx')) {
      return 'euro_bmx_threaded';
    }
    if (normalized.contains('spanish')) {
      return 'spanish_bmx';
    }
    // El vocabulario chileno nombra estas cajas por su código, no por la
    // palabra «pressfit»: `BB86 / BB92 41 mm`, `BB386EVO 46 mm`, `BB90 / BB95`,
    // `BBRight / OSBB`. Sin esto el scorer no reconoce ninguna caja a presión
    // moderna y las deja como familia cruda.
    if (normalized.contains('pressfit') ||
        normalized.contains('press fit') ||
        normalized.contains('bb86') ||
        normalized.contains('bb92') ||
        normalized.contains('bb386') ||
        normalized.contains('bb90') ||
        normalized.contains('bb95') ||
        normalized.contains('bbright') ||
        normalized.contains('osbb')) {
      return 'pressfit';
    }
    if (normalized.contains('bb30') || normalized.contains('pf30')) {
      return 'bb30_pf30';
    }
    if (normalized.contains('mid')) {
      return 'mid';
    }
    if (normalized.contains('american') ||
        normalized.contains('americano') ||
        normalized.contains('one_piece') ||
        normalized.contains('one-piece')) {
      return 'one_piece';
    }
    if (normalized.contains('cuadrado') ||
        normalized.contains('square') ||
        normalized.contains('cartucho')) {
      return 'square_taper_cartridge';
    }
    if (normalized.contains('hollowtech') ||
        normalized.contains('24mm') ||
        normalized.contains('externo')) {
      return 'hollowtech_24';
    }

    return _normalizeSemanticToken(rawValue.toString());
  }

  String? _canonicalShifterPosition(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    final normalized = _normalizeText(rawValue.toString());
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.contains('desconoc')) {
      return null;
    }
    if (normalized.contains('izq') ||
        normalized.contains('left') ||
        normalized.contains('delanter')) {
      return 'left';
    }
    if (normalized.contains('der') ||
        normalized.contains('right') ||
        normalized.contains('traser')) {
      return 'right';
    }
    if (normalized.contains('par') ||
        normalized.contains('juego') ||
        normalized.contains('pair')) {
      return 'pair';
    }
    if (normalized.contains('universal')) {
      return 'universal';
    }

    return null;
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
      case 'shimano_hg_road_11':
        return 'Shimano HG Road 11';
      case 'microspline':
        return 'Micro Spline';
      case 'sram_xd':
        return 'SRAM XD';
      case 'sram_xdr':
        return 'SRAM XDR';
      case 'campagnolo':
        return 'Campagnolo';
      case 'campagnolo_n3w':
        return 'Campagnolo N3W';
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
      case 'square_taper_cartridge':
        return 'Cuadrado cartucho';
      case 'hollowtech_24':
        return 'Hollowtech / 24mm';
      case 'unknown':
        return 'sin confirmar';
      default:
        return bottomBracketFamily;
    }
  }

  String _drivetrainPlatformLabel(String platform) {
    switch (platform) {
      case 'shimano_hg_sis':
        return 'Shimano HG/SIS';
      case 'shimano_hg_plus':
        return 'Shimano HG+';
      case 'shimano_linkglide':
        return 'Shimano Linkglide/CUES';
      case 'sram_eagle':
        return 'SRAM Eagle';
      case 'sram_flattop':
        return 'SRAM FlatTop';
      case 'sram_t_type':
        return 'SRAM T-Type';
      case 'campagnolo':
        return 'Campagnolo';
      case 'microshift_advent':
        return 'Microshift Advent/Acolyte';
      case 'friction_universal':
        return 'Friccion/universal';
      case 'single_speed_bmx':
        return 'Single speed/BMX';
      case 'universal_5_8':
        return 'Universal 5-8v';
      case 'universal_9_11':
        return 'Universal 9-11v';
      case 'kmc_compatible':
        return 'KMC compatible';
      case 'generic':
        return 'generico compatible';
      default:
        return platform;
    }
  }

  String _shiftActuationFamilyLabel(String actuation) {
    switch (actuation) {
      case 'shimano_sis_6_9':
        return 'Shimano SIS 6-9v';
      case 'shimano_dynasys_10':
        return 'Shimano Dynasys 10v';
      case 'shimano_dynasys_11_12':
        return 'Shimano Dynasys 11/12v';
      case 'shimano_linkglide':
        return 'Shimano CUES/Linkglide';
      case 'shimano_road':
        return 'Shimano ruta';
      case 'sram_exact':
        return 'SRAM Exact Actuation';
      case 'sram_x_actuation':
        return 'SRAM X-Actuation/Eagle';
      case 'sram_axs_road':
        return 'SRAM AXS road';
      case 'sram_t_type':
        return 'SRAM T-Type';
      case 'campagnolo':
        return 'Campagnolo';
      case 'microshift_advent':
        return 'Microshift Advent/Acolyte';
      case 'friction_universal':
        return 'friccion/universal';
      default:
        return actuation;
    }
  }

  String _spindleInterfaceLabel(String spindleInterface) {
    switch (spindleInterface) {
      case 'square_jis':
        return 'Cuadrado JIS';
      case 'square_iso':
        return 'Cuadrado ISO';
      case 'square_taper':
        return 'Cuadrado';
      case 'hollowtech_24':
        return 'Hollowtech / 24 mm';
      case 'sram_dub':
        return 'SRAM DUB';
      case 'isis':
        return 'ISIS';
      case 'octalink':
        return 'Octalink';
      case 'bmx_19':
        return 'BMX 19 mm';
      case 'bmx_22':
        return 'BMX 22 mm';
      case 'bmx_24':
        return 'BMX 24 mm';
      case 'one_piece':
        return 'One-piece/americano';
      default:
        return spindleInterface;
    }
  }

  String _drivetrainFamilyLabel(String family) {
    switch (family) {
      case 'crankset':
        return 'Volante/pedivela';
      case 'chainring':
        return 'Corona/plato';
      case 'drivetrain_kit':
        return 'Kit transmisión';
      case 'bottom_bracket':
        return 'Motor / pedalier';
      case 'bottom_bracket_axle':
        return 'Eje de motor';
      case 'bottom_bracket_cup':
        return 'Cubeta de motor';
      case 'bottom_bracket_bearing':
        return 'Rodamiento de motor';
      default:
        return family;
    }
  }

  String _drivetrainCompatibilityFamilyLabel(String family) {
    switch (family) {
      case 'shimano_ecosystem':
        return 'ecosistema Shimano';
      case 'sram_ecosystem':
        return 'ecosistema SRAM';
      case 'campagnolo_ecosystem':
        return 'ecosistema Campagnolo';
      case 'microshift_ecosystem':
        return 'ecosistema Microshift';
      case 'kmc_multi_compatible':
        return 'KMC multicompatible';
      case 'single_speed_bmx':
        return 'single speed/BMX';
      case 'universal_generic':
        return 'generico/universal';
      default:
        return family;
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
  final String? drivetrainPlatform;
  final String? shiftActuationFamily;
  final String? chainWidthFamily;
  final int? largestCogTeeth;
  final int? frontSpokeHoles;
  final int? rearSpokeHoles;
  final String? valveType;
  final String? bottomBracketFamily;
  final double? bbShellWidthMm;
  final double? bbShellDiameterMm;
  final String? spindleInterface;

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
    required this.drivetrainPlatform,
    required this.shiftActuationFamily,
    required this.chainWidthFamily,
    required this.largestCogTeeth,
    required this.frontSpokeHoles,
    required this.rearSpokeHoles,
    required this.valveType,
    required this.bottomBracketFamily,
    required this.bbShellWidthMm,
    required this.bbShellDiameterMm,
    required this.spindleInterface,
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
        drivetrainPlatform != null ||
        shiftActuationFamily != null ||
        chainWidthFamily != null ||
        largestCogTeeth != null ||
        frontSpokeHoles != null ||
        rearSpokeHoles != null ||
        valveType != null ||
        bottomBracketFamily != null ||
        bbShellWidthMm != null ||
        bbShellDiameterMm != null ||
        spindleInterface != null;
  }
}
