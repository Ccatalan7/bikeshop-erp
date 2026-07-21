import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/product_compatibility.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';
import 'bike_product_compatibility_service.dart';

enum SmartJobRecommendationKind { product, service }

enum SmartJobRecommendationConfidence { high, medium, low }

class SmartJobRecommendationResult {
  final bool triggerActive;
  final String? triggerSummary;
  final List<SmartJobRecommendation> recommendations;
  final List<String> dataGaps;

  const SmartJobRecommendationResult({
    required this.triggerActive,
    this.triggerSummary,
    this.recommendations = const [],
    this.dataGaps = const [],
  });

  bool get hasRecommendations => recommendations.isNotEmpty;
}

class SmartJobRecommendation {
  final String id;
  final SmartJobRecommendationKind kind;
  final SmartJobRecommendationConfidence confidence;
  final Product product;
  final String title;
  final String subtitle;
  final String reason;
  final List<String> facts;
  final List<String> dataGaps;
  final int sortScore;

  const SmartJobRecommendation({
    required this.id,
    required this.kind,
    required this.confidence,
    required this.product,
    required this.title,
    required this.subtitle,
    required this.reason,
    this.facts = const [],
    this.dataGaps = const [],
    this.sortScore = 0,
  });
}

class SmartJobRecommendationService {
  SmartJobRecommendationService({
    SupabaseClient? client,
    BikeProductCompatibilityService? compatibilityService,
  })  : _client = client ?? Supabase.instance.client,
        _compatibilityService = compatibilityService ??
            BikeProductCompatibilityService(
              client: client ?? Supabase.instance.client,
            );

  static const double _wornChainThresholdPercent = 75;

  final SupabaseClient _client;
  final BikeProductCompatibilityService _compatibilityService;

  Future<SmartJobRecommendationResult> buildWornChainRecommendations({
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required Bike? bike,
    required BikeProfile? bikeProfile,
  }) async {
    final chainWear = normalizeDiagnosisWearPercent(
      diagnosisSheet.drivetrain.chainWearPercent,
    );
    if (chainWear == null || chainWear < _wornChainThresholdPercent) {
      return const SmartJobRecommendationResult(
        triggerActive: false,
        triggerSummary: 'Sin desgaste de cadena accionable.',
      );
    }

    final dataGaps = <String>[];
    final tenantId = await TenantService().getTenantId();
    final chainSpeed = _resolveChainSpeed(bikeProfile, dataGaps);
    final categoryMatch = await _loadChainCategoryIds(
      tenantId: tenantId,
      dataGaps: dataGaps,
    );

    final recommendations = <SmartJobRecommendation>[
      ...await _loadChainProductRecommendations(
        tenantId: tenantId,
        categoryMatch: categoryMatch,
        chainSpeed: chainSpeed,
        bike: bike,
        bikeProfile: bikeProfile,
        dataGaps: dataGaps,
      ),
      ...await _loadChainServiceRecommendations(
        tenantId: tenantId,
        dataGaps: dataGaps,
      ),
    ]..sort((a, b) => b.sortScore.compareTo(a.sortScore));

    return SmartJobRecommendationResult(
      triggerActive: true,
      triggerSummary:
          'Cadena con ${chainWear.toStringAsFixed(0)}% de desgaste.',
      recommendations: recommendations.take(5).toList(growable: false),
      dataGaps: dataGaps.toList(growable: false),
    );
  }

  Future<SmartJobRecommendationResult> buildBrakePadRecommendations({
    required BrakeDiagnosisSheet brakeSheet,
    required BikeProfile? bikeProfile,
    required String brakeSystemKey,
  }) async {
    final wear = normalizeDiagnosisWearPercent(brakeSheet.padWearPercent);
    final needsReplacement = (wear != null && wear >= 75) ||
        brakeSheet.padContaminationStatus == 'replace';

    if (!needsReplacement) {
      return const SmartJobRecommendationResult(
        triggerActive: false,
        triggerSummary: 'Sin sugerencias listas para agregar.',
      );
    }

    final tenantId = await TenantService().getTenantId();
    final dataGaps = <String>[];
    final technicalValues =
        bikeProfile?.technicalValues ?? const <String, dynamic>{};
    final brakeType = _normalizeToken(technicalValues['brakeType']);
    final isRimBrake = brakeType == 'rim' || brakeType == 'llanta';
    final positionLabel =
        brakeSystemKey == 'rear_brake' ? 'trasero' : 'delantero';
    final partLabel = isRimBrake ? 'zapatas' : 'pastillas';

    final recommendations = <SmartJobRecommendation>[
      ...await _loadBrakePadProductRecommendations(
        tenantId: tenantId,
        isRimBrake: isRimBrake,
        positionLabel: positionLabel,
        partLabel: partLabel,
        dataGaps: dataGaps,
      ),
      ...await _loadBrakePadServiceRecommendations(
        tenantId: tenantId,
        isRimBrake: isRimBrake,
        positionLabel: positionLabel,
        partLabel: partLabel,
      ),
    ]..sort((a, b) => b.sortScore.compareTo(a.sortScore));

    if (recommendations.isEmpty) {
      dataGaps.add(
        'No se encontraron productos/servicios activos para $partLabel de freno.',
      );
    }

    return SmartJobRecommendationResult(
      triggerActive: true,
      triggerSummary:
          'Freno $positionLabel con ${wear?.toStringAsFixed(0) ?? 'alto'}% de desgaste.',
      recommendations: recommendations.take(5).toList(growable: false),
      dataGaps: dataGaps,
    );
  }

  Future<List<SmartJobRecommendation>> _loadBrakePadProductRecommendations({
    required String? tenantId,
    required bool isRimBrake,
    required String positionLabel,
    required String partLabel,
    required List<String> dataGaps,
  }) async {
    var productQuery = _client
        .from('products')
        .select(Product.listPreviewSelect)
        .eq('is_active', true)
        .eq('product_type', 'product')
        .or('name.ilike.%pastilla%,name.ilike.%zapata%,name.ilike.%brake pad%,category_name.ilike.%pastilla%,category_name.ilike.%zapata%');

    if (tenantId != null && tenantId.isNotEmpty) {
      productQuery = productQuery.eq('tenant_id', tenantId);
    }

    final productRows = await productQuery.order('name').limit(80);
    final candidates = <SmartJobRecommendation>[];

    for (final raw in productRows as List) {
      final product = Product.fromJson(Map<String, dynamic>.from(raw as Map));
      final haystack = _normalizeToken(
        '${product.name} ${product.categoryName ?? ''} ${product.model ?? ''}',
      );

      if (isRimBrake && haystack.contains('disco')) continue;
      if (!isRimBrake && haystack.contains('zapata')) continue;

      var score = isRimBrake && haystack.contains('zapata') ? 95 : 65;
      if (!isRimBrake &&
          (haystack.contains('pastilla') || haystack.contains('brake pad'))) {
        score += 25;
      }

      final facts = <String>['Freno $positionLabel', partLabel];
      final gaps = <String>[];
      if (product.tracksInventory) {
        if (product.availableStockQuantity > 0) {
          score += 30;
          facts.add('${product.availableStockQuantity} en stock');
        } else {
          score -= 20;
          gaps.add('Producto sin stock.');
        }
      }

      if (isRimBrake) {
        gaps.add('Confirmar tipo exacto de zapata/freno de llanta.');
      } else {
        gaps.add('Confirmar forma exacta de pastilla/caliper.');
      }

      candidates.add(
        SmartJobRecommendation(
          id: 'brake-pad-product-${product.id}',
          kind: SmartJobRecommendationKind.product,
          confidence:
              product.tracksInventory && product.availableStockQuantity <= 0
                  ? SmartJobRecommendationConfidence.low
                  : SmartJobRecommendationConfidence.medium,
          product: product,
          title: product.name,
          subtitle: [
            if (product.brand?.trim().isNotEmpty == true) product.brand!.trim(),
            if (product.sku.trim().isNotEmpty) 'SKU ${product.sku}',
          ].join(' · '),
          reason:
              'Repuesto sugerido por desgaste de $partLabel del freno $positionLabel.',
          facts: facts,
          dataGaps: gaps,
          sortScore: score,
        ),
      );
    }

    candidates.sort((a, b) => b.sortScore.compareTo(a.sortScore));
    return candidates.take(3).toList(growable: false);
  }

  Future<List<SmartJobRecommendation>> _loadBrakePadServiceRecommendations({
    required String? tenantId,
    required bool isRimBrake,
    required String positionLabel,
    required String partLabel,
  }) async {
    var serviceQuery = _client
        .from('products')
        .select(Product.listPreviewSelect)
        .eq('is_active', true)
        .eq('product_type', 'service')
        .or('name.ilike.%pastilla%,name.ilike.%zapata%,name.ilike.%freno%,name.ilike.%brake%');

    if (tenantId != null && tenantId.isNotEmpty) {
      serviceQuery = serviceQuery.eq('tenant_id', tenantId);
    }

    final serviceRows = await serviceQuery.order('name').limit(40);
    final candidates = <SmartJobRecommendation>[];

    for (final raw in serviceRows as List) {
      final service = Product.fromJson(Map<String, dynamic>.from(raw as Map));
      final name = _normalizeToken(service.name);
      var score = 25;

      if (_containsAny(name, const ['cambio', 'reemplazo', 'instalacion'])) {
        score += 55;
      }
      if (isRimBrake && name.contains('zapata')) score += 35;
      if (!isRimBrake && name.contains('pastilla')) score += 35;
      if (name.contains('freno') || name.contains('brake')) score += 20;

      candidates.add(
        SmartJobRecommendation(
          id: 'brake-pad-service-${service.id}',
          kind: SmartJobRecommendationKind.service,
          confidence: score >= 90
              ? SmartJobRecommendationConfidence.high
              : SmartJobRecommendationConfidence.medium,
          product: service,
          title: service.name,
          subtitle: service.sku.trim().isNotEmpty ? 'SKU ${service.sku}' : '',
          reason:
              'Servicio sugerido por desgaste de $partLabel del freno $positionLabel.',
          facts: ['Servicio', 'Freno $positionLabel'],
          dataGaps: const [],
          sortScore: score,
        ),
      );
    }

    candidates.sort((a, b) => b.sortScore.compareTo(a.sortScore));
    return candidates.take(2).toList(growable: false);
  }

  Future<_ChainCategoryMatch> _loadChainCategoryIds({
    required String? tenantId,
    required List<String> dataGaps,
  }) async {
    try {
      var mappingQuery = _client
          .from('category_tech_mappings')
          .select('category_id, technical_family')
          .eq('status', 'active')
          .inFilter('technical_family', const ['chain', 'bike_chain']);

      if (tenantId != null && tenantId.isNotEmpty) {
        mappingQuery = mappingQuery.eq('tenant_id', tenantId);
      }

      final rows = await mappingQuery;
      final categoryIds = <String>{
        for (final raw in rows as List)
          if ((raw as Map)['category_id']?.toString().isNotEmpty == true)
            raw['category_id'].toString(),
      };

      if (categoryIds.isNotEmpty) {
        return _ChainCategoryMatch(
          categoryIds: categoryIds.toList(growable: false),
          fromTechnicalFamily: true,
        );
      }
    } catch (_) {
      dataGaps.add('No se pudo leer el puente técnico de categorías.');
    }

    dataGaps.add(
      'No hay categoría mapeada a technical_family = chain para usar el motor de compatibilidad.',
    );
    return const _ChainCategoryMatch();
  }

  Future<List<SmartJobRecommendation>> _loadChainProductRecommendations({
    required String? tenantId,
    required _ChainCategoryMatch categoryMatch,
    required int? chainSpeed,
    required Bike? bike,
    required BikeProfile? bikeProfile,
    required List<String> dataGaps,
  }) async {
    if (categoryMatch.categoryIds.isEmpty) return const [];

    var productQuery = _client
        .from('products')
        .select(Product.listPreviewSelect)
        .eq('is_active', true)
        .eq('product_type', 'product')
        .inFilter('category_id', categoryMatch.categoryIds);

    if (tenantId != null && tenantId.isNotEmpty) {
      productQuery = productQuery.eq('tenant_id', tenantId);
    }

    final productRows = await productQuery.order('name').limit(80);
    final products = <Product>[
      for (final raw in productRows as List)
        Product.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];

    if (products.isEmpty) return const [];

    if (bike == null || bikeProfile == null) {
      dataGaps.add('Falta contexto de bicicleta para evaluar compatibilidad.');
      return const [];
    }

    final assessments =
        await _compatibilityService.buildAutocompleteAssessments(
      bike: bike,
      profile: bikeProfile,
      products: products,
    );

    final candidates = <SmartJobRecommendation>[];
    var skippedWithoutCompatibleAssessment = 0;
    for (final product in products) {
      final assessment = assessments[product.id];
      if (assessment == null ||
          assessment.level != ProductCompatibilityLevel.compatible) {
        skippedWithoutCompatibleAssessment++;
        continue;
      }

      final facts = <String>[
        categoryMatch.fromTechnicalFamily
            ? 'Familia técnica: cadena'
            : 'Categoría: Cadenas',
      ];
      final dataGaps = <String>[];
      var score = categoryMatch.fromTechnicalFamily ? 70 : 45;

      if (chainSpeed != null) {
        score += 70;
        facts.add('${chainSpeed}v compatible');
      } else {
        score += 8;
      }

      if (product.tracksInventory) {
        if (product.availableStockQuantity > 0) {
          score += 30;
          facts.add('${product.availableStockQuantity} en stock');
        } else {
          score -= 20;
          dataGaps.add('Producto sin stock.');
        }
      } else {
        facts.add('Sin control de stock');
      }

      candidates.add(
        SmartJobRecommendation(
          id: 'chain-product-${product.id}',
          kind: SmartJobRecommendationKind.product,
          confidence:
              !product.tracksInventory || product.availableStockQuantity > 0
                  ? SmartJobRecommendationConfidence.high
                  : SmartJobRecommendationConfidence.medium,
          product: product,
          title: product.name,
          subtitle: [
            if (product.brand?.trim().isNotEmpty == true) product.brand!.trim(),
            if (product.sku.trim().isNotEmpty) 'SKU ${product.sku}',
          ].join(' · '),
          reason: chainSpeed != null
              ? 'Cadena validada por compatibilidad para transmisión ${chainSpeed}v.'
              : 'Cadena validada por motor de compatibilidad.',
          facts: facts,
          dataGaps: [
            if (assessment.detail != null) assessment.detail!,
            ...dataGaps,
          ],
          sortScore: score,
        ),
      );
    }

    candidates.sort((a, b) => b.sortScore.compareTo(a.sortScore));
    if (candidates.isEmpty && chainSpeed != null) {
      dataGaps.add(
        'No se sugieren cadenas sin validación del motor de compatibilidad; $skippedWithoutCompatibleAssessment productos quedaron fuera.',
      );
    }
    return candidates.take(3).toList(growable: false);
  }

  Future<List<SmartJobRecommendation>> _loadChainServiceRecommendations({
    required String? tenantId,
    required List<String> dataGaps,
  }) async {
    var serviceQuery = _client
        .from('products')
        .select(Product.listPreviewSelect)
        .eq('is_active', true)
        .eq('product_type', 'service')
        .or('name.ilike.%cadena%,name.ilike.%chain%');

    if (tenantId != null && tenantId.isNotEmpty) {
      serviceQuery = serviceQuery.eq('tenant_id', tenantId);
    }

    final serviceRows = await serviceQuery.order('name').limit(20);
    final services = <Product>[
      for (final raw in serviceRows as List)
        Product.fromJson(Map<String, dynamic>.from(raw as Map)),
    ];

    if (services.isEmpty) {
      dataGaps
          .add('No hay servicio activo de cadena para proponer mano de obra.');
      return const [];
    }

    final profileByProductId = await _loadServiceProfileKeys(
      services.map((service) => service.id).toList(growable: false),
      tenantId: tenantId,
    );

    final candidates = <SmartJobRecommendation>[];
    var hasReplacementService = false;

    for (final service in services) {
      final normalizedName = _normalizeToken(service.name);
      final profileKey = profileByProductId[service.id];
      var score = 20;
      final facts = <String>['Servicio'];
      final gaps = <String>[];

      if (_containsAny(normalizedName, const [
        'reemplazo',
        'cambio',
        'instalacion',
        'instalacion',
      ])) {
        score += 95;
        hasReplacementService = true;
        facts.add('Mano de obra de reemplazo');
      } else if (_containsAny(normalizedName, const [
        'reparacion',
        'reparar',
      ])) {
        score += 65;
        facts.add('Mano de obra cercana');
      } else if (_containsAny(normalizedName, const [
        'limpieza',
        'cepillado',
        'lubricacion',
      ])) {
        score += 25;
        facts.add('Servicio complementario');
      }

      if (profileKey != null && profileKey.contains('chain')) {
        score += 20;
        facts.add('Perfil $profileKey');
      } else {
        gaps.add('Servicio sin perfil estructurado de reemplazo de cadena.');
      }

      candidates.add(
        SmartJobRecommendation(
          id: 'chain-service-${service.id}',
          kind: SmartJobRecommendationKind.service,
          confidence: score >= 100
              ? SmartJobRecommendationConfidence.high
              : SmartJobRecommendationConfidence.medium,
          product: service,
          title: service.name,
          subtitle: service.sku.trim().isNotEmpty ? 'SKU ${service.sku}' : '',
          reason: 'Servicio sugerido por desgaste de cadena.',
          facts: facts,
          dataGaps: gaps,
          sortScore: score,
        ),
      );
    }

    if (!hasReplacementService) {
      dataGaps.add(
        'Falta un servicio/perfil claro para reemplazo de cadena; se usa el más cercano.',
      );
    }

    candidates.sort((a, b) => b.sortScore.compareTo(a.sortScore));
    return candidates.take(2).toList(growable: false);
  }

  Future<Map<String, String?>> _loadServiceProfileKeys(
    List<String> productIds, {
    required String? tenantId,
  }) async {
    if (productIds.isEmpty) return const {};

    var query = _client
        .from('service_product_profile_mappings')
        .select('product_id, service_profiles(key, service_family)')
        .eq('status', 'active')
        .inFilter('product_id', productIds);

    if (tenantId != null && tenantId.isNotEmpty) {
      query = query.eq('tenant_id', tenantId);
    }

    final rows = await query;
    final result = <String, String?>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final productId = row['product_id']?.toString();
      if (productId == null || productId.isEmpty) continue;

      final profile = row['service_profiles'];
      final profileMap =
          profile is Map ? Map<String, dynamic>.from(profile) : const {};
      result[productId] = profileMap['key']?.toString() ??
          profileMap['service_family']?.toString();
    }

    return result;
  }

  int? _resolveChainSpeed(BikeProfile? bikeProfile, List<String> dataGaps) {
    final technicalValues =
        bikeProfile?.technicalValues ?? const <String, dynamic>{};
    final config = _normalizeToken(technicalValues['drivetrainConfig']);

    if (config == 'singlespeed' ||
        config == 'single_speed' ||
        config == 'single speed') {
      return 1;
    }

    final configMatch = RegExp(r'(\d+)\s*x\s*(\d+)').firstMatch(config);
    if (configMatch != null) {
      final rearCogCount = int.tryParse(configMatch.group(2) ?? '');
      if (_isPlausibleChainSpeed(rearCogCount)) return rearCogCount;
    }

    final rawSpeeds = _parseIntValue(technicalValues['drivetrainSpeeds']);
    if (_isPlausibleChainSpeed(rawSpeeds)) return rawSpeeds;

    if (rawSpeeds != null && rawSpeeds > 13) {
      dataGaps.add(
        'drivetrainSpeeds parece total ($rawSpeeds); falta drivetrainConfig tipo 3x7.',
      );
    } else {
      dataGaps.add('Falta confirmar velocidad de transmisión de la bici.');
    }

    return null;
  }

  int? _parseIntValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  bool _isPlausibleChainSpeed(int? value) {
    if (value == null) return false;
    return value == 1 || (value >= 5 && value <= 13);
  }

  String _normalizeToken(Object? raw) {
    return (raw ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }
}

class _ChainCategoryMatch {
  final List<String> categoryIds;
  final bool fromTechnicalFamily;

  const _ChainCategoryMatch({
    this.categoryIds = const [],
    this.fromTechnicalFamily = false,
  });
}
