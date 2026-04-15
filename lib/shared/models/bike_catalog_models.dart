// Bike Catalog Models - Encyclopedia Reference Data

/// Bike Catalog Entry - Reference data from external APIs
/// This is GLOBAL data (no tenant_id) - shared encyclopedia
class BikeCatalogEntry {
  final String? id;
  final String brand;
  final String modelName;
  final int modelYear;
  final String? bikeType; // road, mountain, hybrid, gravel, bmx, city

  // Frame & Geometry
  final String? frameMaterial; // aluminum, carbon, steel, titanium
  final List<String>? frameSizeRange; // ['S', 'M', 'L']
  final String? wheelSize; // 700c, 29", 27.5", 26"

  // Drivetrain
  final int? drivetrainSpeeds;
  final String? drivetrainConfig; // '1x11', '2x10', '3x8'
  final String? cassetteRange; // '11-42', '11-50'
  final int? cassetteMaxTeeth;
  final int? chainSpeeds;
  final String? cranksetModel;
  final String? rearDerailleurModel;
  final String? frontDerailleurModel;

  // Braking
  final String?
      brakeType; // rim, mechanical_disc, hydraulic_disc, roller_brake, drum_brake, coaster_brake, band_brake
  final String? brakeModel;
  final int? brakeRotorSizeFrontMm;
  final int? brakeRotorSizeRearMm;

  // Wheels & Hubs
  final String? frontHubModel;
  final String? rearHubModel;
  final double? frontHubSpacingMm;
  final double? rearHubSpacingMm;
  final String? frontAxleType; // QR, thru_15mm, thru_20mm
  final String? rearAxleType; // QR, thru_12mm
  final String? freehubType; // shimano_hg, sram_xd, microspline
  final int? spokeCount;

  // Tires
  final String? tireSizeFront;
  final String? tireSizeRear;
  final double? maxTireWidthMm;

  // Cockpit
  final String? handlebarType; // drop, flat, riser
  final int? stemLengthMm;
  final double? seatpostDiameterMm;

  // Additional Info
  final double? weightKg;
  final double? msrpUsd;
  final String? manufacturerUrl;
  final String? imageUrl;

  // Full specs (raw JSON)
  final Map<String, dynamic>? fullSpecsJson;

  // Data Quality
  final String dataSource; // bikebook, bike_index, manual
  final double? dataConfidence; // 0.0 to 1.0
  final String? externalId;
  final DateTime? lastVerifiedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  BikeCatalogEntry({
    this.id,
    required this.brand,
    required this.modelName,
    required this.modelYear,
    this.bikeType,
    this.frameMaterial,
    this.frameSizeRange,
    this.wheelSize,
    this.drivetrainSpeeds,
    this.drivetrainConfig,
    this.cassetteRange,
    this.cassetteMaxTeeth,
    this.chainSpeeds,
    this.cranksetModel,
    this.rearDerailleurModel,
    this.frontDerailleurModel,
    this.brakeType,
    this.brakeModel,
    this.brakeRotorSizeFrontMm,
    this.brakeRotorSizeRearMm,
    this.frontHubModel,
    this.rearHubModel,
    this.frontHubSpacingMm,
    this.rearHubSpacingMm,
    this.frontAxleType,
    this.rearAxleType,
    this.freehubType,
    this.spokeCount,
    this.tireSizeFront,
    this.tireSizeRear,
    this.maxTireWidthMm,
    this.handlebarType,
    this.stemLengthMm,
    this.seatpostDiameterMm,
    this.weightKg,
    this.msrpUsd,
    this.manufacturerUrl,
    this.imageUrl,
    this.fullSpecsJson,
    required this.dataSource,
    this.dataConfidence,
    this.externalId,
    this.lastVerifiedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Display name: "Trek Marlin 5 (2024)"
  String get displayName => '$brand $modelName ($modelYear)';

  /// Short name: "Trek Marlin 5"
  String get shortName => '$brand $modelName';

  factory BikeCatalogEntry.fromJson(Map<String, dynamic> json) {
    return BikeCatalogEntry(
      id: json['id'] as String?,
      brand: json['brand'] as String,
      modelName: json['model_name'] as String,
      modelYear: json['model_year'] as int,
      bikeType: json['bike_type'] as String?,
      frameMaterial: json['frame_material'] as String?,
      frameSizeRange: (json['frame_size_range'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      wheelSize: json['wheel_size'] as String?,
      drivetrainSpeeds: json['drivetrain_speeds'] as int?,
      drivetrainConfig: json['drivetrain_config'] as String?,
      cassetteRange: json['cassette_range'] as String?,
      cassetteMaxTeeth: json['cassette_max_teeth'] as int?,
      chainSpeeds: json['chain_speeds'] as int?,
      cranksetModel: json['crankset_model'] as String?,
      rearDerailleurModel: json['rear_derailleur_model'] as String?,
      frontDerailleurModel: json['front_derailleur_model'] as String?,
      brakeType: json['brake_type'] as String?,
      brakeModel: json['brake_model'] as String?,
      brakeRotorSizeFrontMm: json['brake_rotor_size_front_mm'] as int?,
      brakeRotorSizeRearMm: json['brake_rotor_size_rear_mm'] as int?,
      frontHubModel: json['front_hub_model'] as String?,
      rearHubModel: json['rear_hub_model'] as String?,
      frontHubSpacingMm: (json['front_hub_spacing_mm'] as num?)?.toDouble(),
      rearHubSpacingMm: (json['rear_hub_spacing_mm'] as num?)?.toDouble(),
      frontAxleType: json['front_axle_type'] as String?,
      rearAxleType: json['rear_axle_type'] as String?,
      freehubType: json['freehub_type'] as String?,
      spokeCount: json['spoke_count'] as int?,
      tireSizeFront: json['tire_size_front'] as String?,
      tireSizeRear: json['tire_size_rear'] as String?,
      maxTireWidthMm: (json['max_tire_width_mm'] as num?)?.toDouble(),
      handlebarType: json['handlebar_type'] as String?,
      stemLengthMm: json['stem_length_mm'] as int?,
      seatpostDiameterMm: (json['seatpost_diameter_mm'] as num?)?.toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      msrpUsd: (json['msrp_usd'] as num?)?.toDouble(),
      manufacturerUrl: json['manufacturer_url'] as String?,
      imageUrl: json['image_url'] as String?,
      fullSpecsJson: json['full_specs_json'] as Map<String, dynamic>?,
      dataSource: json['data_source'] as String,
      dataConfidence: (json['data_confidence'] as num?)?.toDouble(),
      externalId: json['external_id'] as String?,
      lastVerifiedAt: json['last_verified_at'] != null
          ? DateTime.parse(json['last_verified_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'brand': brand,
      'model_name': modelName,
      'model_year': modelYear,
      if (bikeType != null) 'bike_type': bikeType,
      if (frameMaterial != null) 'frame_material': frameMaterial,
      if (frameSizeRange != null) 'frame_size_range': frameSizeRange,
      if (wheelSize != null) 'wheel_size': wheelSize,
      if (drivetrainSpeeds != null) 'drivetrain_speeds': drivetrainSpeeds,
      if (drivetrainConfig != null) 'drivetrain_config': drivetrainConfig,
      if (cassetteRange != null) 'cassette_range': cassetteRange,
      if (cassetteMaxTeeth != null) 'cassette_max_teeth': cassetteMaxTeeth,
      if (chainSpeeds != null) 'chain_speeds': chainSpeeds,
      if (cranksetModel != null) 'crankset_model': cranksetModel,
      if (rearDerailleurModel != null)
        'rear_derailleur_model': rearDerailleurModel,
      if (frontDerailleurModel != null)
        'front_derailleur_model': frontDerailleurModel,
      if (brakeType != null) 'brake_type': brakeType,
      if (brakeModel != null) 'brake_model': brakeModel,
      if (brakeRotorSizeFrontMm != null)
        'brake_rotor_size_front_mm': brakeRotorSizeFrontMm,
      if (brakeRotorSizeRearMm != null)
        'brake_rotor_size_rear_mm': brakeRotorSizeRearMm,
      if (frontHubModel != null) 'front_hub_model': frontHubModel,
      if (rearHubModel != null) 'rear_hub_model': rearHubModel,
      if (frontHubSpacingMm != null) 'front_hub_spacing_mm': frontHubSpacingMm,
      if (rearHubSpacingMm != null) 'rear_hub_spacing_mm': rearHubSpacingMm,
      if (frontAxleType != null) 'front_axle_type': frontAxleType,
      if (rearAxleType != null) 'rear_axle_type': rearAxleType,
      if (freehubType != null) 'freehub_type': freehubType,
      if (spokeCount != null) 'spoke_count': spokeCount,
      if (tireSizeFront != null) 'tire_size_front': tireSizeFront,
      if (tireSizeRear != null) 'tire_size_rear': tireSizeRear,
      if (maxTireWidthMm != null) 'max_tire_width_mm': maxTireWidthMm,
      if (handlebarType != null) 'handlebar_type': handlebarType,
      if (stemLengthMm != null) 'stem_length_mm': stemLengthMm,
      if (seatpostDiameterMm != null)
        'seatpost_diameter_mm': seatpostDiameterMm,
      if (weightKg != null) 'weight_kg': weightKg,
      if (msrpUsd != null) 'msrp_usd': msrpUsd,
      if (manufacturerUrl != null) 'manufacturer_url': manufacturerUrl,
      if (imageUrl != null) 'image_url': imageUrl,
      if (fullSpecsJson != null) 'full_specs_json': fullSpecsJson,
      'data_source': dataSource,
      if (dataConfidence != null) 'data_confidence': dataConfidence,
      if (externalId != null) 'external_id': externalId,
      if (lastVerifiedAt != null)
        'last_verified_at': lastVerifiedAt!.toIso8601String(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}
