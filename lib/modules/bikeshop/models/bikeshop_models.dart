// Bikeshop Models - Bikes, Jobs, Service Packages, Labor, Timeline

import 'dart:ui' show Color;

import '../../../shared/models/tax_treatment.dart';

/// Sentinel object used in copyWith to distinguish between "not provided" and "explicitly null"
const Object _sentinel = Object();

DateTime _parseDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.now();
}

DateTime? _parseDateNullable(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

// ============================================================
// BIKE MODEL
// ============================================================

enum BikeType {
  road,
  mountain,
  mountainHardtail,
  hybrid,
  electric,
  bmx,
  folding,
  cruiser,
  gravel,
  paseo,
  other;

  String get displayName {
    switch (this) {
      case BikeType.road:
        return 'Ruta';
      case BikeType.mountain:
        return 'MTB doble suspensión';
      case BikeType.mountainHardtail:
        return 'MTB hardtail';
      case BikeType.hybrid:
        return 'Híbrida';
      case BikeType.electric:
        return 'Eléctrica';
      case BikeType.bmx:
        return 'BMX';
      case BikeType.folding:
        return 'Plegable';
      case BikeType.cruiser:
        return 'Cruiser';
      case BikeType.gravel:
        return 'Gravel';
      case BikeType.paseo:
        return 'Paseo / Urbana';
      case BikeType.other:
        return 'Otra';
    }
  }

  String get dbValue {
    switch (this) {
      case BikeType.mountainHardtail:
        return 'mountain_hardtail';
      default:
        return name;
    }
  }

  static BikeType? fromDbValue(String? value) {
    if (value == null || value.isEmpty) return null;

    switch (value) {
      case 'mountain_hardtail':
        return BikeType.mountainHardtail;
      default:
        return BikeType.values.firstWhere(
          (type) => type.name == value,
          orElse: () => BikeType.other,
        );
    }
  }
}

class Bike {
  final String? id;
  final String tenantId;
  final String customerId;
  final String? brandId; // Foreign key to bike_brands
  final String? modelId; // Foreign key to bike_models
  final String? brand; // Legacy field for backwards compatibility
  final String? model; // Legacy field for backwards compatibility
  final int? year;
  final String? serialNumber;
  final String? color;
  final String? frameSize;
  final String? wheelSize;
  final BikeType? bikeType;
  final double? frontHubSpacingMm; // 100mm (standard), 110mm (Boost)
  final double?
      rearHubSpacingMm; // 130mm (rim), 135mm (QR), 142mm (disc), 148mm (Boost)
  final int? spokeCount; // 24, 28, 32, 36, 40
  final String? factoryRimId; // Original rim that came with the bike
  final DateTime? purchaseDate;
  final double? purchasePrice;
  final DateTime? warrantyUntil;
  final String? qrCode;
  final String? notes;
  final String? imageUrl;
  final List<String> imageUrls;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Bike({
    this.id,
    required this.tenantId,
    required this.customerId,
    this.brandId,
    this.modelId,
    this.brand,
    this.model,
    this.year,
    this.serialNumber,
    this.color,
    this.frameSize,
    this.wheelSize,
    this.bikeType,
    this.frontHubSpacingMm,
    this.rearHubSpacingMm,
    this.spokeCount,
    this.factoryRimId,
    this.purchaseDate,
    this.purchasePrice,
    this.warrantyUntil,
    this.qrCode,
    this.notes,
    this.imageUrl,
    this.imageUrls = const [],
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Bike.fromJson(Map<String, dynamic> json) {
    return Bike(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      brandId: json['brand_id']?.toString(),
      modelId: json['model_id']?.toString(),
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      year: json['year'] as int?,
      serialNumber: json['serial_number'] as String?,
      color: json['color'] as String?,
      frameSize: json['frame_size'] as String?,
      wheelSize: json['wheel_size'] as String?,
      bikeType: BikeType.fromDbValue(json['bike_type']?.toString()),
      frontHubSpacingMm: json['front_hub_spacing_mm'] != null
          ? double.tryParse(json['front_hub_spacing_mm'].toString())
          : null,
      rearHubSpacingMm: json['rear_hub_spacing_mm'] != null
          ? double.tryParse(json['rear_hub_spacing_mm'].toString())
          : null,
      spokeCount: json['spoke_count'] as int?,
      factoryRimId: json['factory_rim_id']?.toString(),
      purchaseDate: _parseDateNullable(json['purchase_date']),
      purchasePrice: json['purchase_price'] != null
          ? double.tryParse(json['purchase_price'].toString())
          : null,
      warrantyUntil: _parseDateNullable(json['warranty_until']),
      qrCode: json['qr_code'] as String?,
      notes: json['notes'] as String?,
      imageUrl: json['image_url'] as String?,
      imageUrls: json['image_urls'] != null
          ? List<String>.from(json['image_urls'] as List)
          : [],
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'customer_id': customerId,
      if (brandId != null) 'brand_id': brandId,
      if (modelId != null) 'model_id': modelId,
      'brand': brand,
      'model': model,
      'year': year,
      'serial_number': serialNumber,
      'color': color,
      'frame_size': frameSize,
      'wheel_size': wheelSize,
      'bike_type': bikeType?.dbValue,
      'front_hub_spacing_mm': frontHubSpacingMm,
      'rear_hub_spacing_mm': rearHubSpacingMm,
      'spoke_count': spokeCount,
      'factory_rim_id': factoryRimId,
      'purchase_date': purchaseDate?.toIso8601String(),
      'purchase_price': purchasePrice,
      'warranty_until': warrantyUntil?.toIso8601String(),
      'qr_code': qrCode,
      'notes': notes,
      'image_url': imageUrl,
      'image_urls': imageUrls,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Bike copyWith({
    String? id,
    String? tenantId,
    String? customerId,
    String? brandId,
    String? modelId,
    String? brand,
    String? model,
    int? year,
    String? serialNumber,
    String? color,
    String? frameSize,
    String? wheelSize,
    BikeType? bikeType,
    double? frontHubSpacingMm,
    double? rearHubSpacingMm,
    int? spokeCount,
    String? factoryRimId,
    DateTime? purchaseDate,
    double? purchasePrice,
    DateTime? warrantyUntil,
    String? qrCode,
    String? notes,
    String? imageUrl,
    List<String>? imageUrls,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Bike(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      customerId: customerId ?? this.customerId,
      brandId: brandId ?? this.brandId,
      modelId: modelId ?? this.modelId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      serialNumber: serialNumber ?? this.serialNumber,
      color: color ?? this.color,
      frameSize: frameSize ?? this.frameSize,
      wheelSize: wheelSize ?? this.wheelSize,
      bikeType: bikeType ?? this.bikeType,
      frontHubSpacingMm: frontHubSpacingMm ?? this.frontHubSpacingMm,
      rearHubSpacingMm: rearHubSpacingMm ?? this.rearHubSpacingMm,
      spokeCount: spokeCount ?? this.spokeCount,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      warrantyUntil: warrantyUntil ?? this.warrantyUntil,
      qrCode: qrCode ?? this.qrCode,
      notes: notes ?? this.notes,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayName {
    final parts = <String>[];
    if (brand != null && brand!.isNotEmpty) parts.add(brand!);
    if (model != null && model!.isNotEmpty) parts.add(model!);
    if (year != null) parts.add(year.toString());
    if (parts.isEmpty) return 'Bicicleta sin nombre';
    return parts.join(' ');
  }

  bool get isUnderWarranty {
    if (warrantyUntil == null) return false;
    return DateTime.now().isBefore(warrantyUntil!);
  }
}

class BikeProfile {
  final String? id;
  final String tenantId;
  final String bikeId;
  final String? catalogBikeId;
  final Map<String, dynamic> intakeProfile;
  final Map<String, dynamic> technicalProfile;
  final Map<String, dynamic> summarySnapshot;
  final DateTime? lastConfirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeProfile({
    this.id,
    required this.tenantId,
    required this.bikeId,
    this.catalogBikeId,
    this.intakeProfile = const {},
    this.technicalProfile = const {},
    this.summarySnapshot = const {},
    this.lastConfirmedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeProfile.fromJson(Map<String, dynamic> json) {
    return BikeProfile(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      catalogBikeId: json['catalog_bike_id']?.toString(),
      intakeProfile: json['intake_profile'] is Map
          ? Map<String, dynamic>.from(json['intake_profile'] as Map)
          : const {},
      technicalProfile: json['technical_profile'] is Map
          ? Map<String, dynamic>.from(json['technical_profile'] as Map)
          : const {},
      summarySnapshot: json['summary_snapshot'] is Map
          ? Map<String, dynamic>.from(json['summary_snapshot'] as Map)
          : const {},
      lastConfirmedAt: _parseDateNullable(json['last_confirmed_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'bike_id': bikeId,
      'catalog_bike_id': catalogBikeId,
      'intake_profile': intakeProfile,
      'technical_profile': technicalProfile,
      'summary_snapshot': summarySnapshot,
      'last_confirmed_at': lastConfirmedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  BikeProfile copyWith({
    String? id,
    String? tenantId,
    String? bikeId,
    String? catalogBikeId,
    Map<String, dynamic>? intakeProfile,
    Map<String, dynamic>? technicalProfile,
    Map<String, dynamic>? summarySnapshot,
    DateTime? lastConfirmedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BikeProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      bikeId: bikeId ?? this.bikeId,
      catalogBikeId: catalogBikeId ?? this.catalogBikeId,
      intakeProfile: intakeProfile ?? this.intakeProfile,
      technicalProfile: technicalProfile ?? this.technicalProfile,
      summarySnapshot: summarySnapshot ?? this.summarySnapshot,
      lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> get technicalValues {
    if (technicalProfile['values'] is Map) {
      return Map<String, dynamic>.from(technicalProfile['values'] as Map);
    }
    return Map<String, dynamic>.from(technicalProfile);
  }

  Map<String, dynamic> get technicalSources {
    if (technicalProfile['sources'] is Map) {
      return Map<String, dynamic>.from(technicalProfile['sources'] as Map);
    }
    return const {};
  }

  Map<String, dynamic> get technicalConfirmed {
    if (technicalProfile['confirmed'] is Map) {
      return Map<String, dynamic>.from(technicalProfile['confirmed'] as Map);
    }
    return const {};
  }

  String? get identityLine => summarySnapshot['identityLine']?.toString();

  List<String> get intakeHighlights =>
      (summarySnapshot['intakeHighlights'] as List?)
          ?.map((item) => item.toString())
          .toList() ??
      const [];

  List<String> get technicalHighlights =>
      (summarySnapshot['technicalHighlights'] as List?)
          ?.map((item) => item.toString())
          .toList() ??
      const [];

  List<String> get warnings =>
      (summarySnapshot['warnings'] as List?)
          ?.map((item) => item.toString())
          .toList() ??
      const [];
}

const Map<String, String> _bikeProfileBrakeTypeLabels = {
  'rim': 'Llanta',
  'mechanical_disc': 'Disco mecanico',
  'hydraulic_disc': 'Disco hidraulico',
  'roller_brake': 'Roller brake',
  'drum_brake': 'Tambor',
  'coaster_brake': 'Contrapedal',
  'band_brake': 'Banda',
};

const Map<String, String> _bikeProfileRimBrakeFamilyLabels = {
  'v_brake': 'V-Brake',
  'cantilever': 'Cantilever',
  'road_caliper_short_reach': 'Caliper ruta corto',
  'road_caliper_long_reach': 'Caliper ruta largo',
  'u_brake': 'U-Brake',
  'rod_brake': 'Freno de varilla',
  'other': 'Otro',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfileFreehubTypeLabels = {
  'shimano_hg': 'Shimano HG',
  'microspline': 'Micro Spline',
  'sram_xd': 'SRAM XD',
  'campagnolo': 'Campagnolo',
  'threaded_freewheel': 'Rueda libre roscada',
  'bmx_driver': 'Driver BMX',
  'fixed_threaded': 'Rosca fija / contratuerca',
  'coaster_hub': 'Maza contrapedal',
};

const Map<String, String> _bikeProfileSuspensionLayoutLabels = {
  'rigid': 'Rigida',
  'front_suspension': 'Suspension delantera',
  'full_suspension': 'Doble suspension',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfileValveTypeLabels = {
  'presta': 'Presta',
  'schrader': 'Schrader',
  'dunlop': 'Dunlop',
  'other': 'Otra',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfileBottomBracketFamilyLabels = {
  'bsa_threaded': 'BSA roscado',
  'pressfit': 'Pressfit',
  'bb30_pf30': 'BB30 / PF30',
  'mid': 'Mid / BMX',
  'one_piece': 'One-piece',
  'other': 'Otro',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfileMaintenanceLabels = {
  'regular': 'Regular',
  'occasional': 'Ocasional',
  'poor': 'Deficiente',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfilePrimaryUseLabels = {
  'urban': 'Urbano',
  'commute': 'Traslado',
  'sport': 'Deportivo',
  'trail': 'Trail',
  'downhill': 'Downhill',
  'gravel': 'Gravel',
  'delivery': 'Delivery',
  'mixed': 'Mixto',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfileYesNoUnknownLabels = {
  'yes': 'Si',
  'no': 'No',
  'unknown': 'Desconocido',
};

const Map<String, String> _bikeProfileStorageLabels = {
  'indoor': 'Interior',
  'covered_outdoor': 'Exterior cubierto',
  'outdoor': 'Exterior',
  'unknown': 'Desconocido',
};

String? _bikeProfileLabelFor(Map<String, String> options, dynamic value) {
  final rawValue = value?.toString();
  if (rawValue == null || rawValue.isEmpty) return null;
  return options[rawValue] ?? rawValue;
}

String _formatBikeSpacing(num spacing) {
  final asDouble = spacing.toDouble();
  if (asDouble == asDouble.roundToDouble()) {
    return asDouble.toStringAsFixed(0);
  }
  return asDouble.toStringAsFixed(1);
}

String? _formatSpokeHighlight(dynamic frontValue, dynamic rearValue) {
  final front = frontValue?.toString();
  final rear = rearValue?.toString();

  if ((front == null || front.isEmpty) && (rear == null || rear.isEmpty)) {
    return null;
  }

  if (front != null && front.isNotEmpty && rear != null && rear.isNotEmpty) {
    if (front == rear) {
      return 'Rayos: $front';
    }
    return 'Rayos F/R: $front / $rear';
  }

  if (front != null && front.isNotEmpty) {
    return 'Rayos delanteros: $front';
  }

  return 'Rayos traseros: $rear';
}

class BikeProfileSummaryBuilder {
  static String buildIdentityLine(Bike bike) {
    final serialNumber = bike.serialNumber?.trim();
    if (serialNumber != null && serialNumber.isNotEmpty) {
      return '${bike.displayName} (S/N: $serialNumber)';
    }
    return bike.displayName;
  }

  static List<String> buildIntakeHighlights(
      Map<String, dynamic> intakeProfile) {
    final highlights = <String>[];
    final primaryUse = _bikeProfileLabelFor(
        _bikeProfilePrimaryUseLabels, intakeProfile['primaryUse']);
    final maintenance = _bikeProfileLabelFor(
      _bikeProfileMaintenanceLabels,
      intakeProfile['declaredMaintenanceHistory'],
    );
    final accident = _bikeProfileLabelFor(
      _bikeProfileYesNoUnknownLabels,
      intakeProfile['accidentHistory'],
    );
    final storage = _bikeProfileLabelFor(
      _bikeProfileStorageLabels,
      intakeProfile['storageCondition'],
    );

    if (primaryUse != null) {
      highlights.add('Uso principal: $primaryUse');
    }
    if (maintenance != null) {
      highlights.add('Historial declarado: $maintenance');
    }
    if (accident != null) {
      highlights.add('Accidentes: $accident');
    }
    if (storage != null) {
      highlights.add('Guardado: $storage');
    }

    return highlights;
  }

  static List<String> buildTechnicalHighlights({
    required Bike bike,
    required Map<String, dynamic> technicalValues,
  }) {
    final highlights = <String>[];
    final suspensionLayout = _bikeProfileLabelFor(
      _bikeProfileSuspensionLayoutLabels,
      technicalValues['suspensionLayout'],
    );
    final brake = _bikeProfileLabelFor(
      _bikeProfileBrakeTypeLabels,
      technicalValues['brakeType'],
    );
    final rimBrakeFamily = _bikeProfileLabelFor(
      _bikeProfileRimBrakeFamilyLabels,
      technicalValues['rimBrakeFamily'],
    );
    final freehub = _bikeProfileLabelFor(
      _bikeProfileFreehubTypeLabels,
      technicalValues['freehubType'],
    );
    final drivetrainSpeeds = technicalValues['drivetrainSpeeds']?.toString();
    final drivetrainConfig =
        technicalValues['drivetrainConfig']?.toString().trim();
    final valveType = _bikeProfileLabelFor(
      _bikeProfileValveTypeLabels,
      technicalValues['valveType'],
    );
    final bottomBracketFamily = _bikeProfileLabelFor(
      _bikeProfileBottomBracketFamilyLabels,
      technicalValues['bottomBracketFamily'],
    );
    final spokeHighlight = _formatSpokeHighlight(
      technicalValues['frontSpokeHoles'],
      technicalValues['rearSpokeHoles'],
    );

    if (bike.bikeType != null) {
      highlights.add('Plataforma: ${bike.bikeType!.displayName}');
    }
    if (suspensionLayout != null) {
      highlights.add('Suspension: $suspensionLayout');
    }

    if (brake != null) {
      highlights.add(
        technicalValues['brakeType']?.toString() == 'rim' &&
                rimBrakeFamily != null
            ? 'Frenos: $brake · $rimBrakeFamily'
            : 'Frenos: $brake',
      );
    }
    if (drivetrainSpeeds != null && drivetrainSpeeds.isNotEmpty) {
      highlights.add(
        drivetrainConfig != null && drivetrainConfig.isNotEmpty
            ? 'Transmision: $drivetrainConfig'
            : 'Transmision: ${drivetrainSpeeds}v',
      );
    }
    if (bike.frontHubSpacingMm != null) {
      highlights.add(
        'Eje delantero: ${_formatBikeSpacing(bike.frontHubSpacingMm!)} mm',
      );
    }
    if (bike.rearHubSpacingMm != null) {
      highlights.add(
        'Eje trasero: ${_formatBikeSpacing(bike.rearHubSpacingMm!)} mm',
      );
    }
    if (freehub != null) {
      highlights.add('Freehub: $freehub');
    }
    if (spokeHighlight != null) {
      highlights.add(spokeHighlight);
    } else if (bike.spokeCount != null) {
      highlights.add('Rayos: ${bike.spokeCount}');
    }
    if (valveType != null) {
      highlights.add('Valvula: $valveType');
    }
    if (bottomBracketFamily != null) {
      highlights.add('Pedalier: $bottomBracketFamily');
    }

    return highlights;
  }

  static List<String> buildWarnings({
    required Bike bike,
    required Map<String, dynamic> technicalValues,
  }) {
    final warnings = <String>[];

    final brakeType = technicalValues['brakeType']?.toString();
    if (brakeType == null || brakeType.isEmpty) {
      warnings.add('Falta confirmar tipo de freno');
    } else if (brakeType == 'rim') {
      final rimBrakeFamily = technicalValues['rimBrakeFamily']?.toString();
      if (rimBrakeFamily == null || rimBrakeFamily.isEmpty) {
        warnings.add('Falta confirmar familia de freno de llanta');
      }
    }

    final drivetrainSpeeds = technicalValues['drivetrainSpeeds']?.toString();
    if (drivetrainSpeeds == null || drivetrainSpeeds.isEmpty) {
      warnings.add('Falta confirmar velocidad de transmision');
    }

    final suspensionLayout = technicalValues['suspensionLayout']?.toString();
    if (bike.bikeType != null &&
        bike.bikeType != BikeType.other &&
        (suspensionLayout == null || suspensionLayout.isEmpty)) {
      warnings.add('Falta confirmar configuracion de suspension');
    }

    return warnings;
  }

  static Map<String, dynamic> buildSummarySnapshot({
    required Bike bike,
    required Map<String, dynamic> intakeProfile,
    required Map<String, dynamic> technicalValues,
    DateTime? lastConfirmedAt,
  }) {
    final confirmedAt = lastConfirmedAt ?? DateTime.now();

    return {
      'identityLine': buildIdentityLine(bike),
      'intakeHighlights': buildIntakeHighlights(intakeProfile),
      'technicalHighlights': buildTechnicalHighlights(
        bike: bike,
        technicalValues: technicalValues,
      ),
      'warnings': buildWarnings(
        bike: bike,
        technicalValues: technicalValues,
      ),
      'lastConfirmedAt': confirmedAt.toIso8601String(),
    };
  }
}

class BikeRecordSnapshot {
  final Bike bike;
  final BikeProfile? profile;
  final String identityTitle;
  final String? identitySubtitle;
  final List<String> intakeLines;
  final List<String> technicalLines;
  final List<String> notesLines;
  final List<String> warnings;
  final DateTime? lastConfirmedAt;
  final bool hasStructuredProfile;
  final bool isProfileComplete;

  const BikeRecordSnapshot({
    required this.bike,
    required this.profile,
    required this.identityTitle,
    required this.identitySubtitle,
    required this.intakeLines,
    required this.technicalLines,
    required this.notesLines,
    required this.warnings,
    required this.lastConfirmedAt,
    required this.hasStructuredProfile,
    required this.isProfileComplete,
  });

  factory BikeRecordSnapshot.fromBikeAndProfile({
    required Bike bike,
    BikeProfile? profile,
  }) {
    final intakeProfile = profile?.intakeProfile ?? const <String, dynamic>{};
    final technicalValues =
        profile?.technicalValues ?? const <String, dynamic>{};
    final fallbackSnapshot = BikeProfileSummaryBuilder.buildSummarySnapshot(
      bike: bike,
      intakeProfile: intakeProfile,
      technicalValues: technicalValues,
      lastConfirmedAt: profile?.lastConfirmedAt,
    );
    final summarySnapshot = profile?.summarySnapshot.isNotEmpty == true
        ? profile!.summarySnapshot
        : fallbackSnapshot;

    final identityTitle = bike.displayName;
    final identitySubtitleParts = <String>[];
    if (bike.serialNumber != null && bike.serialNumber!.trim().isNotEmpty) {
      identitySubtitleParts.add('S/N: ${bike.serialNumber!.trim()}');
    }
    if (bike.color != null && bike.color!.trim().isNotEmpty) {
      identitySubtitleParts.add(bike.color!.trim());
    }
    if (bike.frameSize != null && bike.frameSize!.trim().isNotEmpty) {
      identitySubtitleParts.add('Talla ${bike.frameSize!.trim()}');
    }
    if (bike.wheelSize != null && bike.wheelSize!.trim().isNotEmpty) {
      identitySubtitleParts.add('Aro ${bike.wheelSize!.trim()}');
    }

    final notesLines = <String>[];
    if (bike.notes != null && bike.notes!.trim().isNotEmpty) {
      notesLines.add(bike.notes!.trim());
    }

    final intakeLines = (summarySnapshot['intakeHighlights'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final technicalLines = (summarySnapshot['technicalHighlights'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];
    final warnings = (summarySnapshot['warnings'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
        const <String>[];

    return BikeRecordSnapshot(
      bike: bike,
      profile: profile,
      identityTitle: identityTitle,
      identitySubtitle: identitySubtitleParts.isEmpty
          ? null
          : identitySubtitleParts.join(' • '),
      intakeLines: intakeLines,
      technicalLines: technicalLines,
      notesLines: notesLines,
      warnings: warnings,
      lastConfirmedAt: profile?.lastConfirmedAt ??
          _parseDateNullable(summarySnapshot['lastConfirmedAt']),
      hasStructuredProfile: profile != null,
      isProfileComplete: intakeLines.isNotEmpty &&
          technicalLines.isNotEmpty &&
          warnings.isEmpty,
    );
  }

  List<String> get highlights => [...intakeLines, ...technicalLines];

  List<String> get baseHighlights {
    final base = <String>[];

    if (bike.bikeType != null) {
      base.add('Tipo: ${bike.bikeType!.displayName}');
    }
    if (bike.frameSize != null && bike.frameSize!.trim().isNotEmpty) {
      base.add('Talla: ${bike.frameSize!.trim()}');
    }
    if (bike.wheelSize != null && bike.wheelSize!.trim().isNotEmpty) {
      base.add('Aro: ${bike.wheelSize!.trim()}');
    }
    if (bike.color != null && bike.color!.trim().isNotEmpty) {
      base.add('Color: ${bike.color!.trim()}');
    }
    if (bike.isUnderWarranty) {
      base.add('Garantia activa');
    }

    return base;
  }

  List<String> get summaryHighlights {
    final combined = <String>[];

    for (final line in [...baseHighlights, ...highlights]) {
      final normalized = line.trim();
      if (normalized.isEmpty || combined.contains(normalized)) continue;
      combined.add(normalized);
    }

    return combined;
  }
}

// ============================================================
// BIKE TIMELINE EVENT MODEL
// ============================================================

enum BikeEventCategory {
  state,
  visit,
  evidence,
  incident,
  component;

  String get displayName {
    switch (this) {
      case BikeEventCategory.state:
        return 'Estado';
      case BikeEventCategory.visit:
        return 'Visita';
      case BikeEventCategory.evidence:
        return 'Evidencia';
      case BikeEventCategory.incident:
        return 'Incidente';
      case BikeEventCategory.component:
        return 'Componente';
    }
  }

  String get dbValue => toString().split('.').last;

  static BikeEventCategory fromDbValue(String? value) {
    if (value == null) return BikeEventCategory.state;
    return BikeEventCategory.values.firstWhere(
      (category) => category.dbValue == value,
      orElse: () => BikeEventCategory.state,
    );
  }
}

enum BikeEventType {
  bikeRegistered,
  profileCreated,
  profileUpdated,
  jobCreated,
  jobCompleted,
  incidentReported,
  componentReplaced,
  measurementRecorded;

  String get displayName {
    switch (this) {
      case BikeEventType.bikeRegistered:
        return 'Bicicleta registrada';
      case BikeEventType.profileCreated:
        return 'Ficha creada';
      case BikeEventType.profileUpdated:
        return 'Ficha actualizada';
      case BikeEventType.jobCreated:
        return 'Trabajo creado';
      case BikeEventType.jobCompleted:
        return 'Trabajo completado';
      case BikeEventType.incidentReported:
        return 'Incidente reportado';
      case BikeEventType.componentReplaced:
        return 'Componente reemplazado';
      case BikeEventType.measurementRecorded:
        return 'Medición registrada';
    }
  }

  String get dbValue {
    return toString().split('.').last.replaceAllMapped(
        RegExp(r'[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');
  }

  static BikeEventType fromDbValue(String? value) {
    if (value == null) return BikeEventType.profileUpdated;
    return BikeEventType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => BikeEventType.profileUpdated,
    );
  }
}

enum BikeEventSeverity {
  info,
  warning,
  critical;

  String get dbValue => toString().split('.').last;

  static BikeEventSeverity? fromDbValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final severity in BikeEventSeverity.values) {
      if (severity.dbValue == value) return severity;
    }
    return null;
  }
}

class BikeEvent {
  final String? id;
  final String tenantId;
  final String bikeId;
  final String? jobId;
  final BikeEventType eventType;
  final BikeEventCategory eventCategory;
  final DateTime eventDate;
  final String title;
  final String? summary;
  final String source;
  final String? referenceNumber;
  final BikeEventSeverity? severity;
  final Map<String, dynamic> payload;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeEvent({
    this.id,
    required this.tenantId,
    required this.bikeId,
    this.jobId,
    required this.eventType,
    required this.eventCategory,
    DateTime? eventDate,
    required this.title,
    this.summary,
    this.source = 'manual',
    this.referenceNumber,
    this.severity,
    this.payload = const {},
    this.createdBy,
    this.createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : eventDate = eventDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeEvent.fromJson(Map<String, dynamic> json) {
    return BikeEvent(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      jobId: json['job_id']?.toString(),
      eventType: BikeEventType.fromDbValue(json['event_type'] as String?),
      eventCategory:
          BikeEventCategory.fromDbValue(json['event_category'] as String?),
      eventDate: _parseDate(json['event_date']),
      title: json['title']?.toString() ?? '',
      summary: json['summary'] as String?,
      source: json['source']?.toString() ?? 'manual',
      referenceNumber: json['reference_number'] as String?,
      severity: BikeEventSeverity.fromDbValue(json['severity'] as String?),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdBy: json['created_by']?.toString(),
      createdByName: json['created_by_name'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'bike_id': bikeId,
      'job_id': jobId,
      'event_type': eventType.dbValue,
      'event_category': eventCategory.dbValue,
      'event_date': eventDate.toIso8601String(),
      'title': title,
      'summary': summary,
      'source': source,
      'reference_number': referenceNumber,
      'severity': severity?.dbValue,
      'payload': payload,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

enum BikeMemoryLocation {
  none,
  front,
  rear,
  left,
  right,
  center;

  String get dbValue => toString().split('.').last;

  String get displayName {
    switch (this) {
      case BikeMemoryLocation.none:
        return 'Sin ubicación';
      case BikeMemoryLocation.front:
        return 'Delantero';
      case BikeMemoryLocation.rear:
        return 'Trasero';
      case BikeMemoryLocation.left:
        return 'Izquierdo';
      case BikeMemoryLocation.right:
        return 'Derecho';
      case BikeMemoryLocation.center:
        return 'Centro';
    }
  }

  static BikeMemoryLocation fromDbValue(String? value) {
    if (value == null) return BikeMemoryLocation.none;
    return BikeMemoryLocation.values.firstWhere(
      (location) => location.dbValue == value,
      orElse: () => BikeMemoryLocation.none,
    );
  }
}

enum BikeSystemOverallStatus {
  ok,
  attention,
  critical,
  unknown;

  String get dbValue => toString().split('.').last;

  String get displayName {
    switch (this) {
      case BikeSystemOverallStatus.ok:
        return 'Sin problemas';
      case BikeSystemOverallStatus.attention:
        return 'Atención';
      case BikeSystemOverallStatus.critical:
        return 'Crítico';
      case BikeSystemOverallStatus.unknown:
        return 'Sin revisar';
    }
  }

  static BikeSystemOverallStatus fromDbValue(String? value) {
    if (value == null) return BikeSystemOverallStatus.unknown;
    return BikeSystemOverallStatus.values.firstWhere(
      (status) => status.dbValue == value,
      orElse: () => BikeSystemOverallStatus.unknown,
    );
  }
}

enum BikeComponentLifecycleStatus {
  installed,
  removed,
  superseded;

  String get dbValue => toString().split('.').last;

  static BikeComponentLifecycleStatus fromDbValue(String? value) {
    if (value == null) return BikeComponentLifecycleStatus.installed;
    return BikeComponentLifecycleStatus.values.firstWhere(
      (status) => status.dbValue == value,
      orElse: () => BikeComponentLifecycleStatus.installed,
    );
  }
}

enum BikeObservationKind {
  measurement,
  conditionAssessment,
  diagnosisSnapshot,
  incident,
  confirmation;

  String get dbValue {
    return toString().split('.').last.replaceAllMapped(
        RegExp(r'[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');
  }

  static BikeObservationKind fromDbValue(String? value) {
    if (value == null) return BikeObservationKind.measurement;
    return BikeObservationKind.values.firstWhere(
      (kind) => kind.dbValue == value,
      orElse: () => BikeObservationKind.measurement,
    );
  }
}

enum BikeMemorySeverity {
  info,
  warning,
  critical;

  String get dbValue => toString().split('.').last;

  static BikeMemorySeverity? fromDbValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final severity in BikeMemorySeverity.values) {
      if (severity.dbValue == value) return severity;
    }
    return null;
  }
}

enum BikeInterventionType {
  replacement,
  service,
  adjustment,
  installation,
  removal,
  inspection;

  String get dbValue => toString().split('.').last;

  static BikeInterventionType fromDbValue(String? value) {
    if (value == null) return BikeInterventionType.service;
    return BikeInterventionType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => BikeInterventionType.service,
    );
  }
}

class BikeSystemState {
  final String? id;
  final String tenantId;
  final String bikeId;
  final String? jobId;
  final String? jobBikeId;
  final String systemKey;
  final BikeMemoryLocation location;
  final BikeSystemOverallStatus overallStatus;
  final String? statusNote;
  final DateTime? lastReviewedAt;
  final Map<String, dynamic> payload;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeSystemState({
    this.id,
    required this.tenantId,
    required this.bikeId,
    this.jobId,
    this.jobBikeId,
    required this.systemKey,
    this.location = BikeMemoryLocation.none,
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.statusNote,
    this.lastReviewedAt,
    this.payload = const {},
    this.createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeSystemState.fromJson(Map<String, dynamic> json) {
    return BikeSystemState(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      jobId: json['job_id']?.toString(),
      jobBikeId: json['job_bike_id']?.toString(),
      systemKey: json['system_key']?.toString() ?? '',
      location: BikeMemoryLocation.fromDbValue(json['location_key'] as String?),
      overallStatus: BikeSystemOverallStatus.fromDbValue(
          json['overall_status'] as String?),
      statusNote: json['status_note'] as String?,
      lastReviewedAt: _parseDateNullable(json['last_reviewed_at']),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'bike_id': bikeId,
      'job_id': jobId,
      'job_bike_id': jobBikeId,
      'system_key': systemKey,
      'location_key': location.dbValue,
      'overall_status': overallStatus.dbValue,
      'status_note': statusNote,
      'last_reviewed_at': lastReviewedAt?.toIso8601String(),
      'payload': payload,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class BikeComponentLifecycle {
  final String? id;
  final String tenantId;
  final String bikeId;
  final String? jobId;
  final String? jobBikeId;
  final String? mechanicJobItemId;
  final String? productId;
  final String? serviceProductId;
  final String systemKey;
  final String componentSlotKey;
  final BikeMemoryLocation location;
  final String componentLabel;
  final BikeComponentLifecycleStatus status;
  final DateTime installedAt;
  final DateTime? removedAt;
  final String? removalReason;
  final String source;
  final String? notes;
  final Map<String, dynamic> payload;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeComponentLifecycle({
    this.id,
    required this.tenantId,
    required this.bikeId,
    this.jobId,
    this.jobBikeId,
    this.mechanicJobItemId,
    this.productId,
    this.serviceProductId,
    required this.systemKey,
    required this.componentSlotKey,
    this.location = BikeMemoryLocation.none,
    required this.componentLabel,
    this.status = BikeComponentLifecycleStatus.installed,
    DateTime? installedAt,
    this.removedAt,
    this.removalReason,
    this.source = 'manual',
    this.notes,
    this.payload = const {},
    this.createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : installedAt = installedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeComponentLifecycle.fromJson(Map<String, dynamic> json) {
    return BikeComponentLifecycle(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      jobId: json['job_id']?.toString(),
      jobBikeId: json['job_bike_id']?.toString(),
      mechanicJobItemId: json['mechanic_job_item_id']?.toString(),
      productId: json['product_id']?.toString(),
      serviceProductId: json['service_product_id']?.toString(),
      systemKey: json['system_key']?.toString() ?? '',
      componentSlotKey: json['component_slot_key']?.toString() ?? '',
      location: BikeMemoryLocation.fromDbValue(json['location_key'] as String?),
      componentLabel: json['component_label']?.toString() ?? '',
      status:
          BikeComponentLifecycleStatus.fromDbValue(json['status'] as String?),
      installedAt: _parseDate(json['installed_at']),
      removedAt: _parseDateNullable(json['removed_at']),
      removalReason: json['removal_reason'] as String?,
      source: json['source']?.toString() ?? 'manual',
      notes: json['notes'] as String?,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'bike_id': bikeId,
      'job_id': jobId,
      'job_bike_id': jobBikeId,
      'mechanic_job_item_id': mechanicJobItemId,
      'product_id': productId,
      'service_product_id': serviceProductId,
      'system_key': systemKey,
      'component_slot_key': componentSlotKey,
      'location_key': location.dbValue,
      'component_label': componentLabel,
      'status': status.dbValue,
      'installed_at': installedAt.toIso8601String(),
      'removed_at': removedAt?.toIso8601String(),
      'removal_reason': removalReason,
      'source': source,
      'notes': notes,
      'payload': payload,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class BikeObservation {
  final String? id;
  final String tenantId;
  final String bikeId;
  final String? jobId;
  final String? jobBikeId;
  final String? mechanicJobItemId;
  final String? lifecycleId;
  final String? productId;
  final String? serviceProductId;
  final String systemKey;
  final String? componentSlotKey;
  final BikeMemoryLocation location;
  final BikeObservationKind observationKind;
  final String observationKey;
  final String title;
  final String? summary;
  final String? statusValue;
  final double? valueNumeric;
  final String? valueText;
  final String? unit;
  final BikeMemorySeverity? severity;
  final DateTime observedAt;
  final String source;
  final String? sourceField;
  final Map<String, dynamic> payload;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeObservation({
    this.id,
    required this.tenantId,
    required this.bikeId,
    this.jobId,
    this.jobBikeId,
    this.mechanicJobItemId,
    this.lifecycleId,
    this.productId,
    this.serviceProductId,
    required this.systemKey,
    this.componentSlotKey,
    this.location = BikeMemoryLocation.none,
    required this.observationKind,
    required this.observationKey,
    required this.title,
    this.summary,
    this.statusValue,
    this.valueNumeric,
    this.valueText,
    this.unit,
    this.severity,
    DateTime? observedAt,
    this.source = 'manual',
    this.sourceField,
    this.payload = const {},
    this.createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : observedAt = observedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeObservation.fromJson(Map<String, dynamic> json) {
    return BikeObservation(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      jobId: json['job_id']?.toString(),
      jobBikeId: json['job_bike_id']?.toString(),
      mechanicJobItemId: json['mechanic_job_item_id']?.toString(),
      lifecycleId: json['lifecycle_id']?.toString(),
      productId: json['product_id']?.toString(),
      serviceProductId: json['service_product_id']?.toString(),
      systemKey: json['system_key']?.toString() ?? '',
      componentSlotKey: json['component_slot_key']?.toString(),
      location: BikeMemoryLocation.fromDbValue(json['location_key'] as String?),
      observationKind:
          BikeObservationKind.fromDbValue(json['observation_kind'] as String?),
      observationKey: json['observation_key']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      summary: json['summary'] as String?,
      statusValue: json['status_value'] as String?,
      valueNumeric: double.tryParse(json['value_numeric']?.toString() ?? ''),
      valueText: json['value_text'] as String?,
      unit: json['unit'] as String?,
      severity: BikeMemorySeverity.fromDbValue(json['severity'] as String?),
      observedAt: _parseDate(json['observed_at']),
      source: json['source']?.toString() ?? 'manual',
      sourceField: json['source_field'] as String?,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'bike_id': bikeId,
      'job_id': jobId,
      'job_bike_id': jobBikeId,
      'mechanic_job_item_id': mechanicJobItemId,
      'lifecycle_id': lifecycleId,
      'product_id': productId,
      'service_product_id': serviceProductId,
      'system_key': systemKey,
      'component_slot_key': componentSlotKey,
      'location_key': location.dbValue,
      'observation_kind': observationKind.dbValue,
      'observation_key': observationKey,
      'title': title,
      'summary': summary,
      'status_value': statusValue,
      'value_numeric': valueNumeric,
      'value_text': valueText,
      'unit': unit,
      'severity': severity?.dbValue,
      'observed_at': observedAt.toIso8601String(),
      'source': source,
      'source_field': sourceField,
      'payload': payload,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class BikeIntervention {
  final String? id;
  final String tenantId;
  final String bikeId;
  final String? jobId;
  final String? jobBikeId;
  final String? mechanicJobItemId;
  final String? productId;
  final String? serviceProductId;
  final String? fromLifecycleId;
  final String? toLifecycleId;
  final String systemKey;
  final String? componentSlotKey;
  final BikeMemoryLocation location;
  final BikeInterventionType interventionType;
  final String title;
  final String? summary;
  final DateTime performedAt;
  final String source;
  final Map<String, dynamic> payload;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeIntervention({
    this.id,
    required this.tenantId,
    required this.bikeId,
    this.jobId,
    this.jobBikeId,
    this.mechanicJobItemId,
    this.productId,
    this.serviceProductId,
    this.fromLifecycleId,
    this.toLifecycleId,
    required this.systemKey,
    this.componentSlotKey,
    this.location = BikeMemoryLocation.none,
    required this.interventionType,
    required this.title,
    this.summary,
    DateTime? performedAt,
    this.source = 'manual',
    this.payload = const {},
    this.createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : performedAt = performedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeIntervention.fromJson(Map<String, dynamic> json) {
    return BikeIntervention(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      jobId: json['job_id']?.toString(),
      jobBikeId: json['job_bike_id']?.toString(),
      mechanicJobItemId: json['mechanic_job_item_id']?.toString(),
      productId: json['product_id']?.toString(),
      serviceProductId: json['service_product_id']?.toString(),
      fromLifecycleId: json['from_lifecycle_id']?.toString(),
      toLifecycleId: json['to_lifecycle_id']?.toString(),
      systemKey: json['system_key']?.toString() ?? '',
      componentSlotKey: json['component_slot_key']?.toString(),
      location: BikeMemoryLocation.fromDbValue(json['location_key'] as String?),
      interventionType: BikeInterventionType.fromDbValue(
          json['intervention_type'] as String?),
      title: json['title']?.toString() ?? '',
      summary: json['summary'] as String?,
      performedAt: _parseDate(json['performed_at']),
      source: json['source']?.toString() ?? 'manual',
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      createdBy: json['created_by']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'bike_id': bikeId,
      'job_id': jobId,
      'job_bike_id': jobBikeId,
      'mechanic_job_item_id': mechanicJobItemId,
      'product_id': productId,
      'service_product_id': serviceProductId,
      'from_lifecycle_id': fromLifecycleId,
      'to_lifecycle_id': toLifecycleId,
      'system_key': systemKey,
      'component_slot_key': componentSlotKey,
      'location_key': location.dbValue,
      'intervention_type': interventionType.dbValue,
      'title': title,
      'summary': summary,
      'performed_at': performedAt.toIso8601String(),
      'source': source,
      'payload': payload,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

// ============================================================
// BIKE BRAND MODEL
// ============================================================

class BikeBrand {
  final String? id;
  final String tenantId;
  final String name;
  final String? logoUrl;
  final String? country;
  final String? website;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeBrand({
    this.id,
    required this.tenantId,
    required this.name,
    this.logoUrl,
    this.country,
    this.website,
    this.description,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeBrand.fromJson(Map<String, dynamic> json) {
    return BikeBrand(
      id: json['id'] as String?,
      tenantId: json['tenant_id'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      country: json['country'] as String?,
      website: json['website'] as String?,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (country != null) 'country': country,
      if (website != null) 'website': website,
      if (description != null) 'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  BikeBrand copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? logoUrl,
    String? country,
    String? website,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BikeBrand(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      country: country ?? this.country,
      website: website ?? this.website,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================
// BIKE MODEL (specific models for each brand)
// ============================================================

class BikeModel {
  final String? id;
  final String tenantId;
  final String brandId;
  final String name;
  final int? year;
  final String? description;
  final String? imageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  BikeModel({
    this.id,
    required this.tenantId,
    required this.brandId,
    required this.name,
    this.year,
    this.description,
    this.imageUrl,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory BikeModel.fromJson(Map<String, dynamic> json) {
    return BikeModel(
      id: json['id'] as String?,
      tenantId: json['tenant_id'] as String,
      brandId: json['brand_id'] as String,
      name: json['name'] as String,
      year: json['year'] as int?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'brand_id': brandId,
      'name': name,
      if (year != null) 'year': year,
      if (description != null) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  BikeModel copyWith({
    String? id,
    String? tenantId,
    String? brandId,
    String? name,
    int? year,
    String? description,
    String? imageUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BikeModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      brandId: brandId ?? this.brandId,
      name: name ?? this.name,
      year: year ?? this.year,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get displayName {
    if (year != null) {
      return '$name ($year)';
    }
    return name;
  }
}

// ============================================================
// MECHANIC JOB STATUS & PRIORITY
// ============================================================

/// Phase grouping for job statuses (Notion-style)
enum StatusPhase {
  todo, // Not started yet
  inProgress, // Work in progress
  complete; // Finished

  String get displayName {
    switch (this) {
      case StatusPhase.todo:
        return 'Por Hacer';
      case StatusPhase.inProgress:
        return 'En Progreso';
      case StatusPhase.complete:
        return 'Completado';
    }
  }

  String get dbValue {
    switch (this) {
      case StatusPhase.todo:
        return 'todo';
      case StatusPhase.inProgress:
        return 'in_progress';
      case StatusPhase.complete:
        return 'complete';
    }
  }

  static StatusPhase fromDbValue(String? value) {
    switch (value) {
      case 'todo':
        return StatusPhase.todo;
      case 'in_progress':
        return StatusPhase.inProgress;
      case 'complete':
        return StatusPhase.complete;
      default:
        return StatusPhase.inProgress;
    }
  }
}

/// Custom job status (Notion-style, per-tenant)
class JobStatusCustom {
  final String? id;
  final String tenantId;
  final String name;
  final String code;
  final String color; // Hex color like '#3B82F6'
  final StatusPhase phase;
  final int sortOrder;
  final bool isSystem; // System statuses can't be deleted
  final bool isActive;
  final bool triggersStart; // Sets startedAt
  final bool triggersCompletion; // Sets completedAt
  final bool triggersDelivery; // Sets deliveredAt
  final DateTime createdAt;
  final DateTime updatedAt;

  JobStatusCustom({
    this.id,
    required this.tenantId,
    required this.name,
    required this.code,
    this.color = '#6B7280',
    this.phase = StatusPhase.inProgress,
    this.sortOrder = 0,
    this.isSystem = false,
    this.isActive = true,
    this.triggersStart = false,
    this.triggersCompletion = false,
    this.triggersDelivery = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory JobStatusCustom.fromJson(Map<String, dynamic> json) {
    return JobStatusCustom(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      color: json['color'] as String? ?? '#6B7280',
      phase: StatusPhase.fromDbValue(json['phase'] as String?),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isSystem: json['is_system'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      triggersStart: json['triggers_start'] as bool? ?? false,
      triggersCompletion: json['triggers_completion'] as bool? ?? false,
      triggersDelivery: json['triggers_delivery'] as bool? ?? false,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      'code': code,
      'color': color,
      'phase': phase.dbValue,
      'sort_order': sortOrder,
      'is_system': isSystem,
      'is_active': isActive,
      'triggers_start': triggersStart,
      'triggers_completion': triggersCompletion,
      'triggers_delivery': triggersDelivery,
    };
  }

  JobStatusCustom copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? code,
    String? color,
    StatusPhase? phase,
    int? sortOrder,
    bool? isSystem,
    bool? isActive,
    bool? triggersStart,
    bool? triggersCompletion,
    bool? triggersDelivery,
  }) {
    return JobStatusCustom(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      code: code ?? this.code,
      color: color ?? this.color,
      phase: phase ?? this.phase,
      sortOrder: sortOrder ?? this.sortOrder,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      triggersStart: triggersStart ?? this.triggersStart,
      triggersCompletion: triggersCompletion ?? this.triggersCompletion,
      triggersDelivery: triggersDelivery ?? this.triggersDelivery,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobStatusCustom &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// Converts hex color string to Flutter Color
  Color get colorValue {
    try {
      final hex = color.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF6B7280); // Default gray
    }
  }
}

// Legacy enum for backwards compatibility (will be gradually phased out)
enum JobStatus {
  pendiente,
  diagnostico,
  esperandoAprobacion,
  esperandoRepuestos,
  enCurso,
  finalizado,
  entregado,
  cancelado;

  String get displayName {
    switch (this) {
      case JobStatus.pendiente:
        return 'Pendiente';
      case JobStatus.diagnostico:
        return 'Diagnóstico';
      case JobStatus.esperandoAprobacion:
        return 'Esperando Aprobación';
      case JobStatus.esperandoRepuestos:
        return 'Esperando Repuestos';
      case JobStatus.enCurso:
        return 'En Curso';
      case JobStatus.finalizado:
        return 'Finalizado';
      case JobStatus.entregado:
        return 'Entregado';
      case JobStatus.cancelado:
        return 'Cancelado';
    }
  }

  String get dbValue {
    switch (this) {
      case JobStatus.pendiente:
        return 'PENDIENTE';
      case JobStatus.diagnostico:
        return 'DIAGNOSTICO';
      case JobStatus.esperandoAprobacion:
        return 'ESPERANDO_APROBACION';
      case JobStatus.esperandoRepuestos:
        return 'ESPERANDO_REPUESTOS';
      case JobStatus.enCurso:
        return 'EN_CURSO';
      case JobStatus.finalizado:
        return 'FINALIZADO';
      case JobStatus.entregado:
        return 'ENTREGADO';
      case JobStatus.cancelado:
        return 'CANCELADO';
    }
  }

  static JobStatus fromDbValue(String? value) {
    if (value == null) return JobStatus.pendiente;
    switch (value.toUpperCase()) {
      case 'PENDIENTE':
        return JobStatus.pendiente;
      case 'DIAGNOSTICO':
        return JobStatus.diagnostico;
      case 'ESPERANDO_APROBACION':
        return JobStatus.esperandoAprobacion;
      case 'ESPERANDO_REPUESTOS':
        return JobStatus.esperandoRepuestos;
      case 'EN_CURSO':
        return JobStatus.enCurso;
      case 'FINALIZADO':
        return JobStatus.finalizado;
      case 'ENTREGADO':
        return JobStatus.entregado;
      case 'CANCELADO':
        return JobStatus.cancelado;
      default:
        return JobStatus.pendiente;
    }
  }
}

enum JobPriority {
  urgente,
  alta,
  normal,
  baja;

  String get displayName {
    switch (this) {
      case JobPriority.urgente:
        return 'Urgente';
      case JobPriority.alta:
        return 'Alta';
      case JobPriority.normal:
        return 'Normal';
      case JobPriority.baja:
        return 'Baja';
    }
  }

  String get dbValue {
    return toString().split('.').last.toUpperCase();
  }

  static JobPriority fromDbValue(String? value) {
    if (value == null) return JobPriority.normal;
    switch (value.toUpperCase()) {
      case 'URGENTE':
        return JobPriority.urgente;
      case 'ALTA':
        return JobPriority.alta;
      case 'NORMAL':
        return JobPriority.normal;
      case 'BAJA':
        return JobPriority.baja;
      default:
        return JobPriority.normal;
    }
  }
}

// ============================================================
// JOB TYPE, WARRANTY OUTCOME, QUOTATION STATUS ENUMS
// ============================================================

enum JobType {
  service,
  warranty,
  quotation,
  itemService;

  String get displayName {
    switch (this) {
      case JobType.service:
        return 'Servicio';
      case JobType.warranty:
        return 'Garantía';
      case JobType.quotation:
        return 'Presupuesto';
      case JobType.itemService:
        return 'Componente';
    }
  }

  String get dbValue {
    switch (this) {
      case JobType.service:
        return 'service';
      case JobType.warranty:
        return 'warranty';
      case JobType.quotation:
        return 'quotation';
      case JobType.itemService:
        return 'item_service';
    }
  }

  static JobType fromDbValue(String? value) {
    switch (value) {
      case 'warranty':
        return JobType.warranty;
      case 'quotation':
        return JobType.quotation;
      case 'item_service':
        return JobType.itemService;
      default:
        return JobType.service;
    }
  }
}

enum WarrantyOutcome {
  pending,
  covered,
  notCovered;

  String get displayName {
    switch (this) {
      case WarrantyOutcome.pending:
        return 'Pendiente';
      case WarrantyOutcome.covered:
        return 'Cubierto';
      case WarrantyOutcome.notCovered:
        return 'No cubierto';
    }
  }

  String get dbValue {
    switch (this) {
      case WarrantyOutcome.pending:
        return 'pending';
      case WarrantyOutcome.covered:
        return 'covered';
      case WarrantyOutcome.notCovered:
        return 'not_covered';
    }
  }

  static WarrantyOutcome fromDbValue(String? value) {
    switch (value) {
      case 'covered':
        return WarrantyOutcome.covered;
      case 'not_covered':
        return WarrantyOutcome.notCovered;
      default:
        return WarrantyOutcome.pending;
    }
  }
}

enum QuotationStatus {
  pending,
  approved,
  rejected,
  expired;

  String get displayName {
    switch (this) {
      case QuotationStatus.pending:
        return 'Pendiente';
      case QuotationStatus.approved:
        return 'Aprobado';
      case QuotationStatus.rejected:
        return 'Rechazado';
      case QuotationStatus.expired:
        return 'Expirado';
    }
  }

  String get dbValue {
    switch (this) {
      case QuotationStatus.pending:
        return 'pending';
      case QuotationStatus.approved:
        return 'approved';
      case QuotationStatus.rejected:
        return 'rejected';
      case QuotationStatus.expired:
        return 'expired';
    }
  }

  static QuotationStatus fromDbValue(String? value) {
    switch (value) {
      case 'approved':
        return QuotationStatus.approved;
      case 'rejected':
        return QuotationStatus.rejected;
      case 'expired':
        return QuotationStatus.expired;
      default:
        return QuotationStatus.pending;
    }
  }
}

// ============================================================
// JOB SUBJECT MODEL (per-tenant component/item catalog)
// ============================================================

class JobSubject {
  final String? id;
  final String tenantId;
  final String name;
  final String category;
  final String icon;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JobSubject({
    this.id,
    required this.tenantId,
    required this.name,
    this.category = 'General',
    this.icon = 'build',
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JobSubject.fromJson(Map<String, dynamic> json) {
    return JobSubject(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      icon: json['icon'] as String? ?? 'build',
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson({bool forUpdate = false}) {
    final m = <String, dynamic>{
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      'category': category,
      'icon': icon,
      'description': description,
      'is_active': isActive,
      'sort_order': sortOrder,
      if (!forUpdate) 'created_at': createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    return m;
  }

  JobSubject copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? category,
    String? icon,
    String? description,
    bool? isActive,
    int? sortOrder,
  }) {
    return JobSubject(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      category: category ?? this.category,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

// ============================================================
// MECHANIC JOB MODEL
// ============================================================

class MechanicJob {
  final String? id;
  final String tenantId;
  final String? jobNumber; // ✅ Nullable - auto-generated by database
  final String customerId;
  final String?
      bikeId; // nullable: item_service / quotation / warranty jobs may not have a bike
  final String? servicePackageId;
  // --- new job type fields ---
  final JobType jobType;
  final String? subjectId;
  final JobSubject? subjectData; // loaded from join, not persisted directly
  final String? subjectNotes;
  final WarrantyOutcome? warrantyOutcome;
  final QuotationStatus? quotationStatus;
  final DateTime? quotationValidUntil;
  final String? convertedFromId;
  final DateTime? convertedAt;
  final DateTime arrivalDate;
  final DateTime? diagnosticDeadline; // Target date to send diagnostic
  final DateTime? deliveryDeadline; // Target date to deliver bike
  final DateTime? diagnosticSentAt; // Actual timestamp when diagnostic was sent
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final JobStatus status; // Legacy enum (for backwards compatibility)
  final String? statusId; // New: UUID reference to job_statuses table
  final JobStatusCustom? customStatus; // Loaded from job_statuses join
  final DateTime? statusUpdatedAt; // Timestamp of last status change
  final JobPriority priority;
  final String? clientRequest;
  final String? diagnosis;
  final String? workPerformed;
  final String? notes;
  final String? assignedTo;
  final String? assignedTechnicianName;
  final double estimatedCost;
  final double finalCost;
  final double partsCost;
  final double laborCost;
  final double discountAmount;
  final double taxAmount;
  final double totalCost;
  final TaxTreatment taxTreatment; // ← Add this field
  final String? invoiceId;
  final bool isInvoiced;
  final bool isPaid;
  final bool isWarrantyJob;
  final String? warrantyNotes;
  final bool requiresApproval;
  final bool approvedByCustomer;
  final DateTime? approvedAt;
  final List<String> imageUrls;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Soft delete fields
  final DateTime? deletedAt;
  final String? deletedBy;

  MechanicJob({
    this.id,
    required this.tenantId,
    this.jobNumber, // ✅ Optional - will be auto-generated if null
    required this.customerId,
    this.bikeId, // nullable now
    this.servicePackageId,
    this.jobType = JobType.service,
    this.subjectId,
    this.subjectData,
    this.subjectNotes,
    this.warrantyOutcome,
    this.quotationStatus,
    this.quotationValidUntil,
    this.convertedFromId,
    this.convertedAt,
    DateTime? arrivalDate,
    this.diagnosticDeadline,
    this.deliveryDeadline,
    this.diagnosticSentAt,
    this.startedAt,
    this.completedAt,
    this.deliveredAt,
    this.status = JobStatus.pendiente,
    this.statusId,
    this.customStatus,
    this.statusUpdatedAt,
    this.priority = JobPriority.normal,
    this.clientRequest,
    this.diagnosis,
    this.workPerformed,
    this.notes,
    this.assignedTo,
    this.assignedTechnicianName,
    this.estimatedCost = 0,
    this.finalCost = 0,
    this.partsCost = 0,
    this.laborCost = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.totalCost = 0,
    this.taxTreatment = TaxTreatment.noTax, // ← Add default
    this.invoiceId,
    this.isInvoiced = false,
    this.isPaid = false,
    this.isWarrantyJob = false,
    this.warrantyNotes,
    this.requiresApproval = false,
    this.approvedByCustomer = false,
    this.approvedAt,
    this.imageUrls = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deletedBy,
  })  : arrivalDate = arrivalDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MechanicJob.fromJson(Map<String, dynamic> json) {
    // Parse custom status if joined
    JobStatusCustom? customStatus;
    if (json['job_status'] != null && json['job_status'] is Map) {
      customStatus =
          JobStatusCustom.fromJson(json['job_status'] as Map<String, dynamic>);
    }

    // Parse subject if joined
    JobSubject? subjectData;
    if (json['subject'] != null && json['subject'] is Map) {
      subjectData =
          JobSubject.fromJson(json['subject'] as Map<String, dynamic>);
    }

    return MechanicJob(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobNumber: json['job_number']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString(),
      servicePackageId: json['service_package_id']?.toString(),
      jobType: JobType.fromDbValue(json['job_type'] as String?),
      subjectId: json['subject_id']?.toString(),
      subjectData: subjectData,
      subjectNotes: json['subject_notes'] as String?,
      warrantyOutcome: json['warranty_outcome'] != null
          ? WarrantyOutcome.fromDbValue(json['warranty_outcome'] as String?)
          : null,
      quotationStatus: json['quotation_status'] != null
          ? QuotationStatus.fromDbValue(json['quotation_status'] as String?)
          : null,
      quotationValidUntil: _parseDateNullable(json['quotation_valid_until']),
      convertedFromId: json['converted_from_id']?.toString(),
      convertedAt: _parseDateNullable(json['converted_at']),
      arrivalDate: _parseDate(json['arrival_date']),
      diagnosticDeadline: _parseDateNullable(json['diagnostic_deadline']),
      deliveryDeadline: _parseDateNullable(
          json['deadline']), // Read from existing 'deadline' column
      diagnosticSentAt: _parseDateNullable(json['diagnostic_sent_at']),
      startedAt: _parseDateNullable(json['started_at']),
      completedAt: _parseDateNullable(json['completed_at']),
      deliveredAt: _parseDateNullable(json['delivered_at']),
      status: JobStatus.fromDbValue(json['status'] as String?),
      statusId: json['status_id']?.toString(),
      customStatus: customStatus,
      statusUpdatedAt: _parseDateNullable(json['status_updated_at']),
      priority: JobPriority.fromDbValue(json['priority'] as String?),
      clientRequest: json['client_request'] as String?,
      diagnosis: json['diagnosis'] as String?,
      workPerformed: json['work_performed'] as String?,
      notes: json['notes'] as String?,
      assignedTo: json['assigned_to']?.toString(),
      assignedTechnicianName: json['assigned_technician_name'] as String?,
      estimatedCost:
          double.tryParse(json['estimated_cost']?.toString() ?? '0') ?? 0,
      finalCost: double.tryParse(json['final_cost']?.toString() ?? '0') ?? 0,
      partsCost: double.tryParse(json['parts_cost']?.toString() ?? '0') ?? 0,
      laborCost: double.tryParse(json['labor_cost']?.toString() ?? '0') ?? 0,
      discountAmount:
          double.tryParse(json['discount_amount']?.toString() ?? '0') ?? 0,
      taxAmount: double.tryParse(json['tax_amount']?.toString() ?? '0') ?? 0,
      totalCost: double.tryParse(json['total_cost']?.toString() ?? '0') ?? 0,
      taxTreatment: json['tax_treatment'] == 'tax_included'
          ? TaxTreatment.taxIncluded
          : TaxTreatment.noTax, // ← Add parsing
      invoiceId: json['invoice_id']?.toString(),
      isInvoiced: json['is_invoiced'] as bool? ?? false,
      isPaid: json['is_paid'] as bool? ?? false,
      isWarrantyJob: json['is_warranty_job'] as bool? ?? false,
      warrantyNotes: json['warranty_notes'] as String?,
      requiresApproval: json['requires_approval'] as bool? ?? false,
      approvedByCustomer: json['approved_by_customer'] as bool? ?? false,
      approvedAt: _parseDateNullable(json['approved_at']),
      imageUrls: json['image_urls'] != null
          ? List<String>.from(json['image_urls'] as List)
          : [],
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      deletedAt: _parseDateNullable(json['deleted_at']),
      deletedBy: json['deleted_by']?.toString(),
    );
  }

  /// Converts this job to a JSON map for database operations.
  ///
  /// When [forUpdate] is true, excludes immutable fields like created_at
  /// that should never be overwritten on updates.
  Map<String, dynamic> toJson({bool forUpdate = false}) {
    final json = <String, dynamic>{
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      if (jobNumber != null && jobNumber!.isNotEmpty)
        'job_number':
            jobNumber, // Only include if not null/empty (let DB generate it)
      'customer_id': customerId,
      'bike_id': bikeId,
      'service_package_id': servicePackageId,
      'job_type': jobType.dbValue,
      'subject_id': subjectId,
      'subject_notes': subjectNotes,
      if (warrantyOutcome != null) 'warranty_outcome': warrantyOutcome!.dbValue,
      if (quotationStatus != null) 'quotation_status': quotationStatus!.dbValue,
      'quotation_valid_until': quotationValidUntil?.toIso8601String(),
      'converted_from_id': convertedFromId,
      'converted_at': convertedAt?.toIso8601String(),
      'arrival_date':
          arrivalDate.toIso8601String(), // Always include (editable)
      'diagnostic_deadline': diagnosticDeadline?.toIso8601String(),
      'deadline': deliveryDeadline
          ?.toIso8601String(), // Write to existing 'deadline' column
      'diagnostic_sent_at': diagnosticSentAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'status': status.dbValue,
      if (statusId != null)
        'status_id': statusId, // New: custom status reference
      'priority': priority.dbValue,
      'client_request': clientRequest,
      'diagnosis': diagnosis,
      'work_performed': workPerformed,
      'notes': notes,
      'assigned_to': assignedTo,
      'assigned_technician_name': assignedTechnicianName,
      'estimated_cost': estimatedCost,
      'final_cost': finalCost,
      // Don't include parts_cost, labor_cost, total_cost - these are calculated by database triggers
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'tax_treatment': taxTreatment.toValue(),
      'invoice_id': invoiceId,
      'is_invoiced': isInvoiced,
      'is_paid': isPaid,
      'is_warranty_job': isWarrantyJob,
      'warranty_notes': warrantyNotes,
      'requires_approval': requiresApproval,
      'approved_by_customer': approvedByCustomer,
      'approved_at': approvedAt?.toIso8601String(),
      'image_urls': imageUrls,
    };

    // Only include created_at for CREATE, not UPDATE
    if (!forUpdate) {
      json['created_at'] = createdAt.toIso8601String();
    }

    // updated_at is always set by database trigger, but include it for reference
    json['updated_at'] = DateTime.now().toIso8601String();

    return json;
  }

  MechanicJob copyWith({
    String? id,
    String? tenantId,
    String? jobNumber,
    String? customerId,
    Object? bikeId = _sentinel, // sentinel for nullable field
    String? servicePackageId,
    JobType? jobType,
    Object? subjectId = _sentinel,
    Object? subjectData = _sentinel,
    Object? subjectNotes = _sentinel,
    Object? warrantyOutcome = _sentinel,
    Object? quotationStatus = _sentinel,
    Object? quotationValidUntil = _sentinel,
    Object? convertedFromId = _sentinel,
    Object? convertedAt = _sentinel,
    DateTime? arrivalDate,
    // Use Object? to allow explicitly passing null (sentinel pattern)
    Object? diagnosticDeadline = _sentinel,
    Object? deliveryDeadline = _sentinel,
    Object? diagnosticSentAt = _sentinel,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? deliveredAt,
    JobStatus? status,
    JobPriority? priority,
    String? clientRequest,
    String? diagnosis,
    String? workPerformed,
    String? notes,
    String? assignedTo,
    String? assignedTechnicianName,
    double? estimatedCost,
    double? finalCost,
    double? partsCost,
    double? laborCost,
    double? discountAmount,
    double? taxAmount,
    double? totalCost,
    String? invoiceId,
    bool? isInvoiced,
    bool? isPaid,
    bool? isWarrantyJob,
    String? warrantyNotes,
    bool? requiresApproval,
    bool? approvedByCustomer,
    DateTime? approvedAt,
    List<String>? imageUrls,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? statusId,
    JobStatusCustom? customStatus,
    DateTime? statusUpdatedAt,
  }) {
    return MechanicJob(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      jobNumber: jobNumber ?? this.jobNumber,
      customerId: customerId ?? this.customerId,
      bikeId: bikeId == _sentinel ? this.bikeId : bikeId as String?,
      servicePackageId: servicePackageId ?? this.servicePackageId,
      jobType: jobType ?? this.jobType,
      subjectId: subjectId == _sentinel ? this.subjectId : subjectId as String?,
      subjectData: subjectData == _sentinel
          ? this.subjectData
          : subjectData as JobSubject?,
      subjectNotes: subjectNotes == _sentinel
          ? this.subjectNotes
          : subjectNotes as String?,
      warrantyOutcome: warrantyOutcome == _sentinel
          ? this.warrantyOutcome
          : warrantyOutcome as WarrantyOutcome?,
      quotationStatus: quotationStatus == _sentinel
          ? this.quotationStatus
          : quotationStatus as QuotationStatus?,
      quotationValidUntil: quotationValidUntil == _sentinel
          ? this.quotationValidUntil
          : quotationValidUntil as DateTime?,
      convertedFromId: convertedFromId == _sentinel
          ? this.convertedFromId
          : convertedFromId as String?,
      convertedAt: convertedAt == _sentinel
          ? this.convertedAt
          : convertedAt as DateTime?,
      arrivalDate: arrivalDate ?? this.arrivalDate,
      // Handle sentinel: if sentinel, keep old value; if null, set to null; if DateTime, use it
      diagnosticDeadline: diagnosticDeadline == _sentinel
          ? this.diagnosticDeadline
          : diagnosticDeadline as DateTime?,
      deliveryDeadline: deliveryDeadline == _sentinel
          ? this.deliveryDeadline
          : deliveryDeadline as DateTime?,
      diagnosticSentAt: diagnosticSentAt == _sentinel
          ? this.diagnosticSentAt
          : diagnosticSentAt as DateTime?,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
      statusId: statusId ?? this.statusId,
      customStatus: customStatus ?? this.customStatus,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      priority: priority ?? this.priority,
      clientRequest: clientRequest ?? this.clientRequest,
      diagnosis: diagnosis ?? this.diagnosis,
      workPerformed: workPerformed ?? this.workPerformed,
      notes: notes ?? this.notes,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedTechnicianName:
          assignedTechnicianName ?? this.assignedTechnicianName,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      finalCost: finalCost ?? this.finalCost,
      partsCost: partsCost ?? this.partsCost,
      laborCost: laborCost ?? this.laborCost,
      discountAmount: discountAmount ?? this.discountAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      totalCost: totalCost ?? this.totalCost,
      invoiceId: invoiceId ?? this.invoiceId,
      isInvoiced: isInvoiced ?? this.isInvoiced,
      isPaid: isPaid ?? this.isPaid,
      isWarrantyJob: isWarrantyJob ?? this.isWarrantyJob,
      warrantyNotes: warrantyNotes ?? this.warrantyNotes,
      requiresApproval: requiresApproval ?? this.requiresApproval,
      approvedByCustomer: approvedByCustomer ?? this.approvedByCustomer,
      approvedAt: approvedAt ?? this.approvedAt,
      imageUrls: imageUrls ?? this.imageUrls,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get the display name for the status (prefers custom status if available)
  String get statusDisplayName {
    if (jobType == JobType.quotation) {
      final qStatus = quotationStatus ?? QuotationStatus.pending;
      return 'Presupuesto ${qStatus.displayName}';
    }

    final baseName = customStatus?.name ?? status.displayName;

    if (jobType == JobType.warranty && warrantyOutcome != null) {
      if (warrantyOutcome == WarrantyOutcome.covered) {
        return '$baseName (Cubierto)';
      }
      if (warrantyOutcome == WarrantyOutcome.notCovered) {
        return '$baseName (Rechazado)';
      }
      // If it's explicitly null or pending, we don't necessarily append, or we could append (Eval).
      // Let's just return baseName since they are evaluating it normally in the workflow.
    }

    return baseName;
  }

  /// Get the color for the status (prefers custom status if available)
  String get statusColor {
    if (jobType == JobType.quotation) {
      final qStatus = quotationStatus ?? QuotationStatus.pending;
      switch (qStatus) {
        case QuotationStatus.pending:
          return '#F59E0B'; // Amber
        case QuotationStatus.approved:
          return '#10B981'; // Green
        case QuotationStatus.rejected:
          return '#EF4444'; // Red
        case QuotationStatus.expired:
          return '#6B7280'; // Gray
      }
    }

    if (jobType == JobType.warranty && warrantyOutcome != null) {
      if (warrantyOutcome == WarrantyOutcome.covered) return '#10B981'; // Green
      if (warrantyOutcome == WarrantyOutcome.notCovered) {
        return '#EF4444'; // Red
      }
      // Pending warranties use the normal workflow color
    }

    return customStatus?.color ?? _defaultStatusColor;
  }

  /// Get the Flutter Color object for the status
  Color get colorValue {
    final hexColor = statusColor.replaceFirst('#', '0xff');
    return Color(int.tryParse(hexColor) ?? 0xFF6B7280);
  }

  String get _defaultStatusColor {
    switch (status) {
      case JobStatus.pendiente:
        return '#6B7280'; // Gray
      case JobStatus.diagnostico:
        return '#3B82F6'; // Blue
      case JobStatus.esperandoAprobacion:
        return '#F59E0B'; // Amber
      case JobStatus.esperandoRepuestos:
        return '#F97316'; // Orange
      case JobStatus.enCurso:
        return '#8B5CF6'; // Purple
      case JobStatus.finalizado:
        return '#10B981'; // Green
      case JobStatus.entregado:
        return '#06B6D4'; // Cyan
      case JobStatus.cancelado:
        return '#EF4444'; // Red
    }
  }

  /// Time remaining until delivery deadline (primary deadline for display)
  Duration? get timeRemaining {
    if (deliveryDeadline == null) return null;
    return deliveryDeadline!.difference(DateTime.now());
  }

  /// Check if delivery deadline is overdue
  bool get isOverdue {
    if (deliveryDeadline == null) return false;
    return DateTime.now().isAfter(deliveryDeadline!);
  }

  /// Check if diagnostic deadline is overdue
  bool get isDiagnosticOverdue {
    if (diagnosticDeadline == null) return false;
    return DateTime.now().isAfter(diagnosticDeadline!);
  }

  /// Calculate diagnostic time in days (actual)
  int? get diagnosticTimeDays {
    if (diagnosticSentAt == null) return null;
    return diagnosticSentAt!.difference(arrivalDate).inDays;
  }

  /// Calculate total time from arrival to delivery in days
  int? get totalTimeDays {
    if (deliveredAt == null) return null;
    return deliveredAt!.difference(arrivalDate).inDays;
  }

  bool get isActive {
    return !['FINALIZADO', 'ENTREGADO', 'CANCELADO'].contains(status.dbValue);
  }

  /// Display label for the job subject (for non-bike jobs)
  String? get subjectDisplayName {
    if (subjectData != null) return subjectData!.name;
    if (subjectNotes != null && subjectNotes!.isNotEmpty) return subjectNotes;
    return null;
  }

  /// Whether this job requires a bike (service) or just a subject/item
  bool get requiresBike => jobType == JobType.service;
}

// ============================================================
// MECHANIC JOB ITEM MODEL
// ============================================================

// ============================================================
// MECHANIC JOB BIKE MODEL (Multi-bike support)
// ============================================================
// Links bikes to jobs with per-bike work details
// Each bike in a job has its own: diagnosis, items, notes, costs

class MechanicJobBike {
  final String? id;
  final String tenantId;
  final String jobId;
  final String bikeId;
  final int orderIndex;

  // Per-bike status (each bike can have independent status)
  final String? statusId;
  JobStatusCustom?
      customStatus; // Runtime: loaded status data (not persisted directly)

  // Per-bike work details
  final String? diagnosis;
  final String? workRequested; // Solicitud del cliente
  final String? workPerformed; // Lo que se hizo
  final String? technicianNotes; // Notas del técnico
  final String? diagnosisSheetKey;
  final MechanicJobDiagnosisSheet diagnosisSheet;
  final DateTime? diagnosisSheetUpdatedAt;

  // Per-bike costs (calculated from items)
  final double partsCost;
  final double laborCost;
  final double subtotal;

  // Per-bike flags
  final bool isWarrantyWork;
  final bool requiresApproval;
  final bool approvedByCustomer;
  final DateTime? approvedAt;

  // Images for this specific bike work
  final List<String> imageUrls;

  final DateTime createdAt;
  final DateTime updatedAt;

  // Runtime: loaded bike data (not persisted)
  Bike? bike;

  MechanicJobBike({
    this.id,
    required this.tenantId,
    required this.jobId,
    required this.bikeId,
    this.orderIndex = 0,
    this.statusId,
    this.customStatus,
    this.diagnosis,
    this.workRequested,
    this.workPerformed,
    this.technicianNotes,
    this.diagnosisSheetKey,
    this.diagnosisSheet = const MechanicJobDiagnosisSheet(),
    this.diagnosisSheetUpdatedAt,
    this.partsCost = 0,
    this.laborCost = 0,
    this.subtotal = 0,
    this.isWarrantyWork = false,
    this.requiresApproval = false,
    this.approvedByCustomer = false,
    this.approvedAt,
    this.imageUrls = const [],
    this.bike,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MechanicJobBike.fromJson(Map<String, dynamic> json) {
    // Parse nested bike if available (from join)
    Bike? bike;
    if (json['bike'] != null && json['bike'] is Map) {
      bike = Bike.fromJson(json['bike'] as Map<String, dynamic>);
    }

    // Parse nested status if available (from join)
    JobStatusCustom? customStatus;
    if (json['status'] != null && json['status'] is Map) {
      customStatus =
          JobStatusCustom.fromJson(json['status'] as Map<String, dynamic>);
    }

    return MechanicJobBike(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      orderIndex: json['order_index'] as int? ?? 0,
      statusId: json['status_id']?.toString(),
      customStatus: customStatus,
      diagnosis: json['diagnosis'] as String?,
      workRequested: json['work_requested'] as String?,
      workPerformed: json['work_performed'] as String?,
      technicianNotes: json['technician_notes'] as String?,
      diagnosisSheetKey: json['diagnosis_sheet_key']?.toString(),
      diagnosisSheet: MechanicJobDiagnosisSheet.fromJson(
        json['diagnosis_sheet_data'] is Map
            ? Map<String, dynamic>.from(json['diagnosis_sheet_data'] as Map)
            : const {},
      ),
      diagnosisSheetUpdatedAt:
          _parseDateNullable(json['diagnosis_sheet_updated_at']),
      partsCost: double.tryParse(json['parts_cost']?.toString() ?? '0') ?? 0,
      laborCost: double.tryParse(json['labor_cost']?.toString() ?? '0') ?? 0,
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0,
      isWarrantyWork: json['is_warranty_work'] as bool? ?? false,
      requiresApproval: json['requires_approval'] as bool? ?? false,
      approvedByCustomer: json['approved_by_customer'] as bool? ?? false,
      approvedAt: _parseDateNullable(json['approved_at']),
      imageUrls: json['image_urls'] != null
          ? List<String>.from(json['image_urls'] as List)
          : [],
      bike: bike,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'job_id': jobId,
      'bike_id': bikeId,
      'order_index': orderIndex,
      if (statusId != null) 'status_id': statusId,
      'diagnosis': diagnosis,
      'work_requested': workRequested,
      'work_performed': workPerformed,
      'technician_notes': technicianNotes,
      'diagnosis_sheet_key': diagnosisSheet.hasMeaningfulData
          ? (diagnosisSheetKey ?? diagnosisSheet.templateKey)
          : null,
      'diagnosis_sheet_data': diagnosisSheet.hasMeaningfulData
          ? diagnosisSheet.toJson()
          : const <String, dynamic>{},
      'diagnosis_sheet_updated_at': diagnosisSheet.hasMeaningfulData
          ? (diagnosisSheetUpdatedAt ?? DateTime.now()).toIso8601String()
          : null,
      // Note: parts_cost, labor_cost, subtotal are calculated by trigger
      'is_warranty_work': isWarrantyWork,
      'requires_approval': requiresApproval,
      'approved_by_customer': approvedByCustomer,
      'approved_at': approvedAt?.toIso8601String(),
      'image_urls': imageUrls,
    };
  }

  MechanicJobBike copyWith({
    String? id,
    String? tenantId,
    String? jobId,
    String? bikeId,
    int? orderIndex,
    String? statusId,
    JobStatusCustom? customStatus,
    String? diagnosis,
    String? workRequested,
    String? workPerformed,
    String? technicianNotes,
    String? diagnosisSheetKey,
    MechanicJobDiagnosisSheet? diagnosisSheet,
    DateTime? diagnosisSheetUpdatedAt,
    double? partsCost,
    double? laborCost,
    double? subtotal,
    bool? isWarrantyWork,
    bool? requiresApproval,
    bool? approvedByCustomer,
    DateTime? approvedAt,
    List<String>? imageUrls,
    Bike? bike,
  }) {
    return MechanicJobBike(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      jobId: jobId ?? this.jobId,
      bikeId: bikeId ?? this.bikeId,
      orderIndex: orderIndex ?? this.orderIndex,
      statusId: statusId ?? this.statusId,
      customStatus: customStatus ?? this.customStatus,
      diagnosis: diagnosis ?? this.diagnosis,
      workRequested: workRequested ?? this.workRequested,
      workPerformed: workPerformed ?? this.workPerformed,
      technicianNotes: technicianNotes ?? this.technicianNotes,
      diagnosisSheetKey: diagnosisSheetKey ?? this.diagnosisSheetKey,
      diagnosisSheet: diagnosisSheet ?? this.diagnosisSheet,
      diagnosisSheetUpdatedAt:
          diagnosisSheetUpdatedAt ?? this.diagnosisSheetUpdatedAt,
      partsCost: partsCost ?? this.partsCost,
      laborCost: laborCost ?? this.laborCost,
      subtotal: subtotal ?? this.subtotal,
      isWarrantyWork: isWarrantyWork ?? this.isWarrantyWork,
      requiresApproval: requiresApproval ?? this.requiresApproval,
      approvedByCustomer: approvedByCustomer ?? this.approvedByCustomer,
      approvedAt: approvedAt ?? this.approvedAt,
      imageUrls: imageUrls ?? this.imageUrls,
      bike: bike ?? this.bike,
    );
  }

  /// Display name for this bike entry
  String get displayName => bike?.displayName ?? 'Bicicleta';
}

class MechanicJobDiagnosisSheet {
  final String templateKey;
  final SuspensionDiagnosisSheet suspension;
  final DrivetrainDiagnosisSheet drivetrain;
  final BrakeDiagnosisSheet frontBrake;
  final BrakeDiagnosisSheet rearBrake;
  final WheelDiagnosisSheet frontWheel;
  final WheelDiagnosisSheet rearWheel;
  final BottomBracketDiagnosisSheet bottomBracket;
  final CockpitDiagnosisSheet cockpit;

  const MechanicJobDiagnosisSheet({
    this.templateKey = 'basic_workshop_v1',
    this.suspension = const SuspensionDiagnosisSheet(),
    this.drivetrain = const DrivetrainDiagnosisSheet(),
    this.frontBrake = const BrakeDiagnosisSheet(),
    this.rearBrake = const BrakeDiagnosisSheet(),
    this.frontWheel = const WheelDiagnosisSheet(),
    this.rearWheel = const WheelDiagnosisSheet(),
    this.bottomBracket = const BottomBracketDiagnosisSheet(),
    this.cockpit = const CockpitDiagnosisSheet(),
  });

  bool get hasMeaningfulData =>
      suspension.hasMeaningfulData ||
      drivetrain.hasMeaningfulData ||
      frontBrake.hasMeaningfulData ||
      rearBrake.hasMeaningfulData ||
      frontWheel.hasMeaningfulData ||
      rearWheel.hasMeaningfulData ||
      bottomBracket.hasMeaningfulData ||
      cockpit.hasMeaningfulData;

  factory MechanicJobDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return MechanicJobDiagnosisSheet(
      templateKey: json['template_key']?.toString() ?? 'basic_workshop_v1',
      suspension: SuspensionDiagnosisSheet.fromJson(
        json['suspension'] is Map
            ? Map<String, dynamic>.from(json['suspension'] as Map)
            : const {},
      ),
      drivetrain: DrivetrainDiagnosisSheet.fromJson(
        json['drivetrain'] is Map
            ? Map<String, dynamic>.from(json['drivetrain'] as Map)
            : const {},
      ),
      frontBrake: BrakeDiagnosisSheet.fromJson(
        json['front_brake'] is Map
            ? Map<String, dynamic>.from(json['front_brake'] as Map)
            : const {},
      ),
      rearBrake: BrakeDiagnosisSheet.fromJson(
        json['rear_brake'] is Map
            ? Map<String, dynamic>.from(json['rear_brake'] as Map)
            : const {},
      ),
      frontWheel: WheelDiagnosisSheet.fromJson(
        json['front_wheel'] is Map
            ? Map<String, dynamic>.from(json['front_wheel'] as Map)
            : const {},
      ),
      rearWheel: WheelDiagnosisSheet.fromJson(
        json['rear_wheel'] is Map
            ? Map<String, dynamic>.from(json['rear_wheel'] as Map)
            : const {},
      ),
      bottomBracket: BottomBracketDiagnosisSheet.fromJson(
        json['bottom_bracket'] is Map
            ? Map<String, dynamic>.from(json['bottom_bracket'] as Map)
            : const {},
      ),
      cockpit: CockpitDiagnosisSheet.fromJson(
        json['cockpit'] is Map
            ? Map<String, dynamic>.from(json['cockpit'] as Map)
            : const {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'template_key': templateKey,
      'suspension': suspension.toJson(),
      'drivetrain': drivetrain.toJson(),
      'front_brake': frontBrake.toJson(),
      'rear_brake': rearBrake.toJson(),
      'front_wheel': frontWheel.toJson(),
      'rear_wheel': rearWheel.toJson(),
      'bottom_bracket': bottomBracket.toJson(),
      'cockpit': cockpit.toJson(),
    };
  }

  MechanicJobDiagnosisSheet copyWith({
    String? templateKey,
    SuspensionDiagnosisSheet? suspension,
    DrivetrainDiagnosisSheet? drivetrain,
    BrakeDiagnosisSheet? frontBrake,
    BrakeDiagnosisSheet? rearBrake,
    WheelDiagnosisSheet? frontWheel,
    WheelDiagnosisSheet? rearWheel,
    BottomBracketDiagnosisSheet? bottomBracket,
    CockpitDiagnosisSheet? cockpit,
  }) {
    return MechanicJobDiagnosisSheet(
      templateKey: templateKey ?? this.templateKey,
      suspension: suspension ?? this.suspension,
      drivetrain: drivetrain ?? this.drivetrain,
      frontBrake: frontBrake ?? this.frontBrake,
      rearBrake: rearBrake ?? this.rearBrake,
      frontWheel: frontWheel ?? this.frontWheel,
      rearWheel: rearWheel ?? this.rearWheel,
      bottomBracket: bottomBracket ?? this.bottomBracket,
      cockpit: cockpit ?? this.cockpit,
    );
  }
}

class DrivetrainDiagnosisSheet {
  final BikeSystemOverallStatus overallStatus;
  final double? chainWearPercent;
  final String? cableCondition;
  final String? chainLubricationStatus;
  final String? cassetteCondition;
  final String? chainringCondition;
  final String? rearDerailleurCondition;
  final String? frontDerailleurCondition;
  final String? shifterCondition;
  final String? notes;

  const DrivetrainDiagnosisSheet({
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.chainWearPercent,
    this.cableCondition,
    this.chainLubricationStatus,
    this.cassetteCondition,
    this.chainringCondition,
    this.rearDerailleurCondition,
    this.frontDerailleurCondition,
    this.shifterCondition,
    this.notes,
  });

  bool get hasMeaningfulData =>
      overallStatus != BikeSystemOverallStatus.unknown ||
      chainWearPercent != null ||
      (cableCondition != null && cableCondition!.isNotEmpty) ||
      (chainLubricationStatus != null && chainLubricationStatus!.isNotEmpty) ||
      (cassetteCondition != null && cassetteCondition!.isNotEmpty) ||
      (chainringCondition != null && chainringCondition!.isNotEmpty) ||
      (rearDerailleurCondition != null &&
          rearDerailleurCondition!.isNotEmpty) ||
      (frontDerailleurCondition != null &&
          frontDerailleurCondition!.isNotEmpty) ||
      (shifterCondition != null && shifterCondition!.isNotEmpty) ||
      (notes != null && notes!.trim().isNotEmpty);

  factory DrivetrainDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return DrivetrainDiagnosisSheet(
      overallStatus: BikeSystemOverallStatus.fromDbValue(
        json['overall_status']?.toString(),
      ),
      chainWearPercent:
          double.tryParse(json['chain_wear_percent']?.toString() ?? ''),
      cableCondition: json['cable_condition']?.toString(),
      chainLubricationStatus: json['chain_lubrication_status']?.toString(),
      cassetteCondition: json['cassette_condition']?.toString(),
      chainringCondition: json['chainring_condition']?.toString(),
      rearDerailleurCondition: json['rear_derailleur_condition']?.toString(),
      frontDerailleurCondition: json['front_derailleur_condition']?.toString(),
      shifterCondition: json['shifter_condition']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overall_status': overallStatus.dbValue,
      'chain_wear_percent': chainWearPercent,
      'cable_condition': cableCondition,
      'chain_lubrication_status': chainLubricationStatus,
      'cassette_condition': cassetteCondition,
      'chainring_condition': chainringCondition,
      'rear_derailleur_condition': rearDerailleurCondition,
      'front_derailleur_condition': frontDerailleurCondition,
      'shifter_condition': shifterCondition,
      'notes': notes,
    };
  }

  DrivetrainDiagnosisSheet copyWith({
    BikeSystemOverallStatus? overallStatus,
    double? chainWearPercent,
    bool clearChainWearPercent = false,
    String? cableCondition,
    bool clearCableCondition = false,
    String? chainLubricationStatus,
    bool clearChainLubricationStatus = false,
    String? cassetteCondition,
    bool clearCassetteCondition = false,
    String? chainringCondition,
    bool clearChainringCondition = false,
    String? rearDerailleurCondition,
    bool clearRearDerailleurCondition = false,
    String? frontDerailleurCondition,
    bool clearFrontDerailleurCondition = false,
    String? shifterCondition,
    bool clearShifterCondition = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return DrivetrainDiagnosisSheet(
      overallStatus: overallStatus ?? this.overallStatus,
      chainWearPercent: clearChainWearPercent
          ? null
          : (chainWearPercent ?? this.chainWearPercent),
      cableCondition:
          clearCableCondition ? null : (cableCondition ?? this.cableCondition),
      chainLubricationStatus: clearChainLubricationStatus
          ? null
          : (chainLubricationStatus ?? this.chainLubricationStatus),
      cassetteCondition: clearCassetteCondition
          ? null
          : (cassetteCondition ?? this.cassetteCondition),
      chainringCondition: clearChainringCondition
          ? null
          : (chainringCondition ?? this.chainringCondition),
      rearDerailleurCondition: clearRearDerailleurCondition
          ? null
          : (rearDerailleurCondition ?? this.rearDerailleurCondition),
      frontDerailleurCondition: clearFrontDerailleurCondition
          ? null
          : (frontDerailleurCondition ?? this.frontDerailleurCondition),
      shifterCondition: clearShifterCondition
          ? null
          : (shifterCondition ?? this.shifterCondition),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }
}

class BrakeDiagnosisSheet {
  final BikeSystemOverallStatus overallStatus;
  final double? padWearPercent;
  final String? padContaminationStatus;
  final double? rotorThicknessMm;
  final String? rotorTruenessStatus;
  final String? rotorContaminationStatus;
  final List<String> symptomKeys;
  final String? notes;

  const BrakeDiagnosisSheet({
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.padWearPercent,
    this.padContaminationStatus,
    this.rotorThicknessMm,
    this.rotorTruenessStatus,
    this.rotorContaminationStatus,
    this.symptomKeys = const [],
    this.notes,
  });

  bool get hasMeaningfulData =>
      overallStatus != BikeSystemOverallStatus.unknown ||
      padWearPercent != null ||
      (padContaminationStatus != null && padContaminationStatus!.isNotEmpty) ||
      rotorThicknessMm != null ||
      (rotorTruenessStatus != null && rotorTruenessStatus!.isNotEmpty) ||
      (rotorContaminationStatus != null &&
          rotorContaminationStatus!.isNotEmpty) ||
      symptomKeys.isNotEmpty ||
      (notes != null && notes!.trim().isNotEmpty);

  factory BrakeDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return BrakeDiagnosisSheet(
      overallStatus: BikeSystemOverallStatus.fromDbValue(
        json['overall_status']?.toString(),
      ),
      padWearPercent:
          double.tryParse(json['pad_wear_percent']?.toString() ?? ''),
      padContaminationStatus: json['pad_contamination_status']?.toString(),
      rotorThicknessMm:
          double.tryParse(json['rotor_thickness_mm']?.toString() ?? ''),
      rotorTruenessStatus: json['rotor_trueness_status']?.toString(),
      rotorContaminationStatus: json['rotor_contamination_status']?.toString(),
      symptomKeys: (json['symptom_keys'] is List)
          ? (json['symptom_keys'] as List)
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
          : const [],
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overall_status': overallStatus.dbValue,
      'pad_wear_percent': padWearPercent,
      'pad_contamination_status': padContaminationStatus,
      'rotor_thickness_mm': rotorThicknessMm,
      'rotor_trueness_status': rotorTruenessStatus,
      'rotor_contamination_status': rotorContaminationStatus,
      'symptom_keys': symptomKeys,
      'notes': notes,
    };
  }

  BrakeDiagnosisSheet copyWith({
    BikeSystemOverallStatus? overallStatus,
    double? padWearPercent,
    bool clearPadWearPercent = false,
    String? padContaminationStatus,
    bool clearPadContaminationStatus = false,
    double? rotorThicknessMm,
    bool clearRotorThicknessMm = false,
    String? rotorTruenessStatus,
    bool clearRotorTruenessStatus = false,
    String? rotorContaminationStatus,
    bool clearRotorContaminationStatus = false,
    List<String>? symptomKeys,
    bool clearSymptomKeys = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return BrakeDiagnosisSheet(
      overallStatus: overallStatus ?? this.overallStatus,
      padWearPercent:
          clearPadWearPercent ? null : (padWearPercent ?? this.padWearPercent),
      padContaminationStatus: clearPadContaminationStatus
          ? null
          : (padContaminationStatus ?? this.padContaminationStatus),
      rotorThicknessMm: clearRotorThicknessMm
          ? null
          : (rotorThicknessMm ?? this.rotorThicknessMm),
      rotorTruenessStatus: clearRotorTruenessStatus
          ? null
          : (rotorTruenessStatus ?? this.rotorTruenessStatus),
      rotorContaminationStatus: clearRotorContaminationStatus
          ? null
          : (rotorContaminationStatus ?? this.rotorContaminationStatus),
      symptomKeys:
          clearSymptomKeys ? const [] : (symptomKeys ?? this.symptomKeys),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }
}

class WheelDiagnosisSheet {
  final BikeSystemOverallStatus overallStatus;
  final String? tireCondition;
  final String? rimCondition;
  final String? spokeCondition;
  final String? hubBearingCondition;
  final String? tubelessStatus;
  final String? notes;

  const WheelDiagnosisSheet({
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.tireCondition,
    this.rimCondition,
    this.spokeCondition,
    this.hubBearingCondition,
    this.tubelessStatus,
    this.notes,
  });

  bool get hasMeaningfulData =>
      overallStatus != BikeSystemOverallStatus.unknown ||
      (tireCondition != null && tireCondition!.isNotEmpty) ||
      (rimCondition != null && rimCondition!.isNotEmpty) ||
      (spokeCondition != null && spokeCondition!.isNotEmpty) ||
      (hubBearingCondition != null && hubBearingCondition!.isNotEmpty) ||
      (tubelessStatus != null && tubelessStatus!.isNotEmpty) ||
      (notes != null && notes!.trim().isNotEmpty);

  factory WheelDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return WheelDiagnosisSheet(
      overallStatus: BikeSystemOverallStatus.fromDbValue(
        json['overall_status']?.toString(),
      ),
      tireCondition: json['tire_condition']?.toString(),
      rimCondition: json['rim_condition']?.toString(),
      spokeCondition: json['spoke_condition']?.toString(),
      hubBearingCondition: json['hub_bearing_condition']?.toString(),
      tubelessStatus: json['tubeless_status']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overall_status': overallStatus.dbValue,
      'tire_condition': tireCondition,
      'rim_condition': rimCondition,
      'spoke_condition': spokeCondition,
      'hub_bearing_condition': hubBearingCondition,
      'tubeless_status': tubelessStatus,
      'notes': notes,
    };
  }

  WheelDiagnosisSheet copyWith({
    BikeSystemOverallStatus? overallStatus,
    String? tireCondition,
    bool clearTireCondition = false,
    String? rimCondition,
    bool clearRimCondition = false,
    String? spokeCondition,
    bool clearSpokeCondition = false,
    String? hubBearingCondition,
    bool clearHubBearingCondition = false,
    String? tubelessStatus,
    bool clearTubelessStatus = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return WheelDiagnosisSheet(
      overallStatus: overallStatus ?? this.overallStatus,
      tireCondition:
          clearTireCondition ? null : (tireCondition ?? this.tireCondition),
      rimCondition:
          clearRimCondition ? null : (rimCondition ?? this.rimCondition),
      spokeCondition:
          clearSpokeCondition ? null : (spokeCondition ?? this.spokeCondition),
      hubBearingCondition: clearHubBearingCondition
          ? null
          : (hubBearingCondition ?? this.hubBearingCondition),
      tubelessStatus:
          clearTubelessStatus ? null : (tubelessStatus ?? this.tubelessStatus),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }
}

class BottomBracketDiagnosisSheet {
  final BikeSystemOverallStatus overallStatus;
  final String? bearingCondition;
  final String? noiseStatus;
  final String? notes;

  const BottomBracketDiagnosisSheet({
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.bearingCondition,
    this.noiseStatus,
    this.notes,
  });

  bool get hasMeaningfulData =>
      overallStatus != BikeSystemOverallStatus.unknown ||
      (bearingCondition != null && bearingCondition!.isNotEmpty) ||
      (noiseStatus != null && noiseStatus!.isNotEmpty) ||
      (notes != null && notes!.trim().isNotEmpty);

  factory BottomBracketDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return BottomBracketDiagnosisSheet(
      overallStatus: BikeSystemOverallStatus.fromDbValue(
        json['overall_status']?.toString(),
      ),
      bearingCondition: json['bearing_condition']?.toString(),
      noiseStatus: json['noise_status']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overall_status': overallStatus.dbValue,
      'bearing_condition': bearingCondition,
      'noise_status': noiseStatus,
      'notes': notes,
    };
  }

  BottomBracketDiagnosisSheet copyWith({
    BikeSystemOverallStatus? overallStatus,
    String? bearingCondition,
    bool clearBearingCondition = false,
    String? noiseStatus,
    bool clearNoiseStatus = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return BottomBracketDiagnosisSheet(
      overallStatus: overallStatus ?? this.overallStatus,
      bearingCondition: clearBearingCondition
          ? null
          : (bearingCondition ?? this.bearingCondition),
      noiseStatus: clearNoiseStatus ? null : (noiseStatus ?? this.noiseStatus),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }
}

class CockpitDiagnosisSheet {
  final BikeSystemOverallStatus overallStatus;
  final String? headsetBearingCondition;
  final String? headsetNoiseStatus;
  final String? notes;

  const CockpitDiagnosisSheet({
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.headsetBearingCondition,
    this.headsetNoiseStatus,
    this.notes,
  });

  bool get hasMeaningfulData =>
      overallStatus != BikeSystemOverallStatus.unknown ||
      (headsetBearingCondition != null &&
          headsetBearingCondition!.isNotEmpty) ||
      (headsetNoiseStatus != null && headsetNoiseStatus!.isNotEmpty) ||
      (notes != null && notes!.trim().isNotEmpty);

  factory CockpitDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return CockpitDiagnosisSheet(
      overallStatus: BikeSystemOverallStatus.fromDbValue(
        json['overall_status']?.toString(),
      ),
      headsetBearingCondition: json['headset_bearing_condition']?.toString(),
      headsetNoiseStatus: json['headset_noise_status']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overall_status': overallStatus.dbValue,
      'headset_bearing_condition': headsetBearingCondition,
      'headset_noise_status': headsetNoiseStatus,
      'notes': notes,
    };
  }

  CockpitDiagnosisSheet copyWith({
    BikeSystemOverallStatus? overallStatus,
    String? headsetBearingCondition,
    bool clearHeadsetBearingCondition = false,
    String? headsetNoiseStatus,
    bool clearHeadsetNoiseStatus = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return CockpitDiagnosisSheet(
      overallStatus: overallStatus ?? this.overallStatus,
      headsetBearingCondition: clearHeadsetBearingCondition
          ? null
          : (headsetBearingCondition ?? this.headsetBearingCondition),
      headsetNoiseStatus: clearHeadsetNoiseStatus
          ? null
          : (headsetNoiseStatus ?? this.headsetNoiseStatus),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }
}

class SuspensionDiagnosisSheet {
  final BikeSystemOverallStatus overallStatus;
  final String? forkCondition;
  final String? forkNoiseStatus;
  final String? rearShockCondition;
  final String? rearShockNoiseStatus;
  final String? notes;

  const SuspensionDiagnosisSheet({
    this.overallStatus = BikeSystemOverallStatus.unknown,
    this.forkCondition,
    this.forkNoiseStatus,
    this.rearShockCondition,
    this.rearShockNoiseStatus,
    this.notes,
  });

  bool get hasMeaningfulData =>
      overallStatus != BikeSystemOverallStatus.unknown ||
      (forkCondition != null && forkCondition!.isNotEmpty) ||
      (forkNoiseStatus != null && forkNoiseStatus!.isNotEmpty) ||
      (rearShockCondition != null && rearShockCondition!.isNotEmpty) ||
      (rearShockNoiseStatus != null && rearShockNoiseStatus!.isNotEmpty) ||
      (notes != null && notes!.trim().isNotEmpty);

  factory SuspensionDiagnosisSheet.fromJson(Map<String, dynamic> json) {
    return SuspensionDiagnosisSheet(
      overallStatus: BikeSystemOverallStatus.fromDbValue(
        json['overall_status']?.toString(),
      ),
      forkCondition: json['fork_condition']?.toString(),
      forkNoiseStatus: json['fork_noise_status']?.toString(),
      rearShockCondition: json['rear_shock_condition']?.toString(),
      rearShockNoiseStatus: json['rear_shock_noise_status']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overall_status': overallStatus.dbValue,
      'fork_condition': forkCondition,
      'fork_noise_status': forkNoiseStatus,
      'rear_shock_condition': rearShockCondition,
      'rear_shock_noise_status': rearShockNoiseStatus,
      'notes': notes,
    };
  }

  SuspensionDiagnosisSheet copyWith({
    BikeSystemOverallStatus? overallStatus,
    String? forkCondition,
    bool clearForkCondition = false,
    String? forkNoiseStatus,
    bool clearForkNoiseStatus = false,
    String? rearShockCondition,
    bool clearRearShockCondition = false,
    String? rearShockNoiseStatus,
    bool clearRearShockNoiseStatus = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return SuspensionDiagnosisSheet(
      overallStatus: overallStatus ?? this.overallStatus,
      forkCondition:
          clearForkCondition ? null : (forkCondition ?? this.forkCondition),
      forkNoiseStatus: clearForkNoiseStatus
          ? null
          : (forkNoiseStatus ?? this.forkNoiseStatus),
      rearShockCondition: clearRearShockCondition
          ? null
          : (rearShockCondition ?? this.rearShockCondition),
      rearShockNoiseStatus: clearRearShockNoiseStatus
          ? null
          : (rearShockNoiseStatus ?? this.rearShockNoiseStatus),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }
}

// ============================================================
// MECHANIC JOB ITEM MODEL
// ============================================================

class MechanicJobItem {
  final String? id;
  final String tenantId;
  final String jobId;
  final String?
      jobBikeId; // ✅ NEW: Links item to specific bike in multi-bike jobs
  final String? productId;
  final String? serviceProductId; // Links services to product catalog
  final String productName;
  final String? productSku;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;
  final Map<String, dynamic>? serviceConfigurationData;
  final String itemType; // 'product' | 'service' | 'adhoc'
  final String? systemKey;
  final String? componentSlotKey;
  final BikeMemoryLocation location;
  final BikeInterventionType? interventionType;
  final bool createsLifecycle;
  final DateTime createdAt;

  MechanicJobItem({
    this.id,
    required this.tenantId,
    required this.jobId,
    this.jobBikeId, // ✅ NEW
    this.productId,
    this.serviceProductId,
    required this.productName,
    this.productSku,
    this.quantity = 1,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.notes,
    this.serviceConfigurationData,
    this.itemType = 'product',
    this.systemKey,
    this.componentSlotKey,
    this.location = BikeMemoryLocation.none,
    this.interventionType,
    this.createsLifecycle = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MechanicJobItem.fromJson(Map<String, dynamic> json) {
    return MechanicJobItem(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      jobBikeId: json['job_bike_id']?.toString(), // ✅ NEW
      productId: json['product_id']?.toString(),
      serviceProductId: json['service_product_id']?.toString(),
      productName: json['product_name']?.toString() ?? '',
      productSku: json['product_sku'] as String?,
      quantity: double.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0,
      totalPrice: double.tryParse(json['total_price']?.toString() ?? '0') ?? 0,
      notes: json['notes'] as String?,
      serviceConfigurationData:
          json['service_configuration_data'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(
                  json['service_configuration_data'] as Map<String, dynamic>)
              : (json['service_configuration_data'] is Map
                  ? Map<String, dynamic>.from(
                      json['service_configuration_data'] as Map)
                  : null),
      itemType: json['item_type'] as String? ?? 'product',
      systemKey: json['system_key']?.toString(),
      componentSlotKey: json['component_slot_key']?.toString(),
      location: BikeMemoryLocation.fromDbValue(json['location_key'] as String?),
      interventionType: json['intervention_type'] != null
          ? BikeInterventionType.fromDbValue(
              json['intervention_type'] as String?,
            )
          : null,
      createsLifecycle: json['creates_lifecycle'] as bool? ?? false,
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'job_id': jobId,
      if (jobBikeId != null) 'job_bike_id': jobBikeId, // ✅ NEW
      'product_id': productId,
      'service_product_id': serviceProductId,
      'product_name': productName,
      'product_sku': productSku,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
      'service_configuration_data': serviceConfigurationData,
      'item_type': itemType,
      'system_key': systemKey,
      'component_slot_key': componentSlotKey,
      'location_key': location.dbValue,
      'intervention_type': interventionType?.dbValue,
      'creates_lifecycle': createsLifecycle,
      'created_at': createdAt.toIso8601String(),
    };
  }

  MechanicJobItem copyWith({
    String? id,
    String? tenantId,
    String? jobId,
    String? jobBikeId,
    String? productId,
    String? serviceProductId,
    String? productName,
    String? productSku,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    String? notes,
    Map<String, dynamic>? serviceConfigurationData,
    String? itemType,
    String? systemKey,
    String? componentSlotKey,
    BikeMemoryLocation? location,
    BikeInterventionType? interventionType,
    bool? createsLifecycle,
  }) {
    return MechanicJobItem(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      jobId: jobId ?? this.jobId,
      jobBikeId: jobBikeId ?? this.jobBikeId,
      productId: productId ?? this.productId,
      serviceProductId: serviceProductId ?? this.serviceProductId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      notes: notes ?? this.notes,
      serviceConfigurationData:
          serviceConfigurationData ?? this.serviceConfigurationData,
      itemType: itemType ?? this.itemType,
      systemKey: systemKey ?? this.systemKey,
      componentSlotKey: componentSlotKey ?? this.componentSlotKey,
      location: location ?? this.location,
      interventionType: interventionType ?? this.interventionType,
      createsLifecycle: createsLifecycle ?? this.createsLifecycle,
    );
  }

  // All items treated uniformly - no service/product distinction
  bool get isAdhoc => itemType == 'adhoc';
  bool get isService => itemType == 'service';
  double get lineTotal => totalPrice != 0 ? totalPrice : quantity * unitPrice;
}

// ============================================================
// MECHANIC JOB TIMELINE EVENT MODEL
// ============================================================

enum TimelineEventType {
  created,
  statusChanged,
  assigned,
  diagnosisAdded,
  partsAdded,
  laborAdded,
  photoAdded,
  noteAdded,
  approved,
  invoiced,
  paid,
  completed,
  delivered;

  String get displayName {
    switch (this) {
      case TimelineEventType.created:
        return 'Creado';
      case TimelineEventType.statusChanged:
        return 'Estado Cambiado';
      case TimelineEventType.assigned:
        return 'Asignado';
      case TimelineEventType.diagnosisAdded:
        return 'Diagnóstico Añadido';
      case TimelineEventType.partsAdded:
        return 'Repuestos Añadidos';
      case TimelineEventType.laborAdded:
        return 'Mano de Obra Añadida';
      case TimelineEventType.photoAdded:
        return 'Foto Añadida';
      case TimelineEventType.noteAdded:
        return 'Nota Añadida';
      case TimelineEventType.approved:
        return 'Aprobado';
      case TimelineEventType.invoiced:
        return 'Facturado';
      case TimelineEventType.paid:
        return 'Pagado';
      case TimelineEventType.completed:
        return 'Completado';
      case TimelineEventType.delivered:
        return 'Entregado';
    }
  }

  String get dbValue {
    return toString()
        .split('.')
        .last
        .toLowerCase()
        .replaceAll(RegExp(r'([A-Z])'), '_\$1')
        .substring(1);
  }

  static TimelineEventType fromDbValue(String? value) {
    if (value == null) return TimelineEventType.created;
    final normalized = value.toLowerCase().replaceAll('_', '');
    for (final type in TimelineEventType.values) {
      if (type.toString().split('.').last.toLowerCase() == normalized) {
        return type;
      }
    }
    return TimelineEventType.created;
  }
}

class MechanicJobTimeline {
  final String? id;
  final String tenantId;
  final String jobId;
  final TimelineEventType eventType;
  final String? oldValue;
  final String? newValue;
  final String? description;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;

  MechanicJobTimeline({
    this.id,
    required this.tenantId,
    required this.jobId,
    required this.eventType,
    this.oldValue,
    this.newValue,
    this.description,
    this.createdBy,
    this.createdByName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MechanicJobTimeline.fromJson(Map<String, dynamic> json) {
    return MechanicJobTimeline(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      eventType: TimelineEventType.fromDbValue(json['event_type'] as String?),
      oldValue: json['old_value'] as String?,
      newValue: json['new_value'] as String?,
      description: json['description'] as String?,
      createdBy: json['created_by']?.toString(),
      createdByName: json['created_by_name'] as String?,
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'job_id': jobId,
      'event_type': eventType.dbValue,
      'old_value': oldValue,
      'new_value': newValue,
      'description': description,
      'created_by': createdBy,
      'created_by_name': createdByName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

// ============================================================
// SERVICE PACKAGE MODEL
// ============================================================

class ServicePackage {
  final String? id;
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String name;
  final String? description;
  final double estimatedDurationHours;
  final double baseLaborCost;
  final List<Map<String, dynamic>> items;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServicePackage({
    this.id,
    required this.tenantId,
    required this.name,
    this.description,
    this.estimatedDurationHours = 1,
    this.baseLaborCost = 0,
    this.items = const [],
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ServicePackage.fromJson(Map<String, dynamic> json) {
    return ServicePackage(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description'] as String?,
      estimatedDurationHours: double.tryParse(
              json['estimated_duration_hours']?.toString() ?? '1') ??
          1,
      baseLaborCost:
          double.tryParse(json['base_labor_cost']?.toString() ?? '0') ?? 0,
      items: json['items'] != null
          ? List<Map<String, dynamic>>.from(json['items'] as List)
          : [],
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      'description': description,
      'estimated_duration_hours': estimatedDurationHours,
      'base_labor_cost': baseLaborCost,
      'items': items,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

// ============================================================
// MECHANIC JOB TASK MODEL (SMART TASKS SYSTEM)
// ============================================================

class MechanicJobTask {
  final String? id;
  final String tenantId;
  final String jobId;

  // Hierarchy: linked to parent mechanic_job_item (products or services)
  final String? parentItemId;

  // Task details
  final String taskName;
  final String? taskDescription;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? completedByUserId;

  // Ad-hoc pricing
  final bool isAdhoc;
  final double? adhocPrice;
  final String? adhocItemId; // Link to auto-created item

  // Linking behavior
  final bool isStandalone; // true = not linked to parent

  // Smart features
  final bool parsedFromDescription;
  final int displayOrder;

  final DateTime createdAt;
  final DateTime updatedAt;

  MechanicJobTask({
    this.id,
    required this.tenantId,
    required this.jobId,
    this.parentItemId,
    required this.taskName,
    this.taskDescription,
    this.isCompleted = false,
    this.completedAt,
    this.completedByUserId,
    this.isAdhoc = false,
    this.adhocPrice,
    this.adhocItemId,
    this.isStandalone = false,
    this.parsedFromDescription = false,
    this.displayOrder = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MechanicJobTask.fromJson(Map<String, dynamic> json) {
    return MechanicJobTask(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      parentItemId: json['parent_item_id']?.toString(),
      taskName: json['task_name']?.toString() ?? '',
      taskDescription: json['task_description']?.toString(),
      isCompleted: json['is_completed'] as bool? ?? false,
      completedAt: _parseDateNullable(json['completed_at']),
      completedByUserId: json['completed_by_user_id']?.toString(),
      isAdhoc: json['is_adhoc'] as bool? ?? false,
      adhocPrice: (json['adhoc_price'] as num?)?.toDouble(),
      adhocItemId: json['adhoc_item_id']?.toString(),
      isStandalone: json['is_standalone'] as bool? ?? false,
      parsedFromDescription: json['parsed_from_description'] as bool? ?? false,
      displayOrder: json['display_order'] as int? ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'job_id': jobId,
      'parent_item_id': parentItemId,
      'task_name': taskName,
      'task_description': taskDescription,
      'is_completed': isCompleted,
      'completed_at': completedAt?.toIso8601String(),
      'completed_by_user_id': completedByUserId,
      'is_adhoc': isAdhoc,
      'adhoc_price': adhocPrice,
      'adhoc_item_id': adhocItemId,
      'is_standalone': isStandalone,
      'parsed_from_description': parsedFromDescription,
      'display_order': displayOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  MechanicJobTask copyWith({
    String? id,
    String? tenantId,
    String? jobId,
    String? parentItemId,
    String? taskName,
    String? taskDescription,
    bool? isCompleted,
    DateTime? completedAt,
    String? completedByUserId,
    bool? isAdhoc,
    double? adhocPrice,
    String? adhocItemId,
    bool? isStandalone,
    bool? parsedFromDescription,
    int? displayOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MechanicJobTask(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      jobId: jobId ?? this.jobId,
      parentItemId: parentItemId ?? this.parentItemId,
      taskName: taskName ?? this.taskName,
      taskDescription: taskDescription ?? this.taskDescription,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      completedByUserId: completedByUserId ?? this.completedByUserId,
      isAdhoc: isAdhoc ?? this.isAdhoc,
      adhocPrice: adhocPrice ?? this.adhocPrice,
      adhocItemId: adhocItemId ?? this.adhocItemId,
      isStandalone: isStandalone ?? this.isStandalone,
      parsedFromDescription:
          parsedFromDescription ?? this.parsedFromDescription,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ============================================================
// TASK PREFERENCES MODEL (USER COLLAPSE STATE)
// ============================================================

class TaskPreferences {
  final String? id;
  final String tenantId;
  final String userId;
  final String jobId;
  final List<String> collapsedItemIds;
  final List<String> collapsedLaborIds;
  final DateTime updatedAt;

  TaskPreferences({
    this.id,
    required this.tenantId,
    required this.userId,
    required this.jobId,
    this.collapsedItemIds = const [],
    this.collapsedLaborIds = const [],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory TaskPreferences.fromJson(Map<String, dynamic> json) {
    return TaskPreferences(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      collapsedItemIds: (json['collapsed_item_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      collapsedLaborIds: (json['collapsed_labor_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'user_id': userId,
      'job_id': jobId,
      'collapsed_item_ids': collapsedItemIds,
      'collapsed_labor_ids': collapsedLaborIds,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  TaskPreferences copyWith({
    String? id,
    String? tenantId,
    String? userId,
    String? jobId,
    List<String>? collapsedItemIds,
    List<String>? collapsedLaborIds,
    DateTime? updatedAt,
  }) {
    return TaskPreferences(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      userId: userId ?? this.userId,
      jobId: jobId ?? this.jobId,
      collapsedItemIds: collapsedItemIds ?? this.collapsedItemIds,
      collapsedLaborIds: collapsedLaborIds ?? this.collapsedLaborIds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
