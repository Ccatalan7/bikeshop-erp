// Wheel Building System Models
// Professional spoke calculator and wheel component management

/// Wheel Hub Technical Specifications
/// Contains all measurements needed for spoke length calculation
class WheelHub {
  final String? id;
  final String? tenantId;
  final String? productId;

  // Basic Info
  final String name;
  final String? manufacturer;
  final String? model;
  final String hubType; // 'front' or 'rear'

  // Critical Measurements (mm)
  final double oldMm; // Over Locknut Dimension
  final int spokeHoles; // 24, 28, 32, 36, 40

  // Flange Measurements (for spoke calculation)
  final double leftFlangeDiameterMm;
  final double rightFlangeDiameterMm;
  final double centerToLeftFlangeMm;
  final double centerToRightFlangeMm;

  // Compatibility
  final String brakeType; // 'rim', 'disc_6bolt', 'disc_centerlock'
  final String driverType; // 'freewheel', 'cassette', 'fixed', 'none'
  final String axleType; // 'quick_release', 'thru_axle_12mm', etc.

  // Additional Specs
  final int? weightGrams;
  final String? material;
  final String? bearingType;

  // Metadata
  final String? notes;
  final String? imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WheelHub({
    this.id,
    this.tenantId,
    this.productId,
    required this.name,
    this.manufacturer,
    this.model,
    required this.hubType,
    required this.oldMm,
    required this.spokeHoles,
    required this.leftFlangeDiameterMm,
    required this.rightFlangeDiameterMm,
    required this.centerToLeftFlangeMm,
    required this.centerToRightFlangeMm,
    required this.brakeType,
    required this.driverType,
    required this.axleType,
    this.weightGrams,
    this.material,
    this.bearingType,
    this.notes,
    this.imageUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory WheelHub.fromJson(Map<String, dynamic> json) {
    return WheelHub(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      productId: json['product_id']?.toString(),
      name: json['name']?.toString() ?? '',
      manufacturer: json['manufacturer']?.toString(),
      model: json['model']?.toString(),
      hubType: json['hub_type']?.toString() ?? 'rear',
      oldMm: _parseDouble(json['old_mm']) ?? 135.0,
      spokeHoles: _parseInt(json['spoke_holes']) ?? 32,
      leftFlangeDiameterMm:
          _parseDouble(json['left_flange_diameter_mm']) ?? 50.0,
      rightFlangeDiameterMm:
          _parseDouble(json['right_flange_diameter_mm']) ?? 50.0,
      centerToLeftFlangeMm:
          _parseDouble(json['center_to_left_flange_mm']) ?? 30.0,
      centerToRightFlangeMm:
          _parseDouble(json['center_to_right_flange_mm']) ?? 30.0,
      brakeType: json['brake_type']?.toString() ?? 'disc_6bolt',
      driverType: json['driver_type']?.toString() ?? 'cassette',
      axleType: json['axle_type']?.toString() ?? 'quick_release',
      weightGrams: _parseInt(json['weight_grams']),
      material: json['material']?.toString(),
      bearingType: json['bearing_type']?.toString(),
      notes: json['notes']?.toString(),
      imageUrl: json['image_url']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (productId != null) 'product_id': productId,
      'name': name,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      'hub_type': hubType,
      'old_mm': oldMm,
      'spoke_holes': spokeHoles,
      'left_flange_diameter_mm': leftFlangeDiameterMm,
      'right_flange_diameter_mm': rightFlangeDiameterMm,
      'center_to_left_flange_mm': centerToLeftFlangeMm,
      'center_to_right_flange_mm': centerToRightFlangeMm,
      'brake_type': brakeType,
      'driver_type': driverType,
      'axle_type': axleType,
      if (weightGrams != null) 'weight_grams': weightGrams,
      if (material != null) 'material': material,
      if (bearingType != null) 'bearing_type': bearingType,
      if (notes != null) 'notes': notes,
      if (imageUrl != null) 'image_url': imageUrl,
      'is_active': isActive,
    };
  }

  String get displayName => manufacturer != null ? '$manufacturer $name' : name;
  String get oldDisplay => '${oldMm.toStringAsFixed(0)}mm';
  String get spokeHolesDisplay => '${spokeHoles}H';
}

/// Wheel Rim Technical Specifications
/// Contains ERD (Effective Rim Diameter) critical for spoke calculation
class WheelRim {
  final String? id;
  final String? tenantId;
  final String? productId;

  // Basic Info
  final String name;
  final String? manufacturer;
  final String? model;

  // Critical Measurements (mm)
  final double erdMm; // Effective Rim Diameter - CRITICAL for spoke calc
  final int spokeHoles; // 24, 28, 32, 36, 40
  final double internalWidthMm;
  final double? externalWidthMm;
  final double? rimDepthMm;

  // Specifications
  final String wheelSize; // '26"', '27.5"', '29"', '700c', '650b'
  final String brakeType; // 'rim', 'disc'
  final String rimType; // 'clincher', 'tubular', 'tubeless_ready', 'hookless'
  final String? material; // 'aluminum', 'carbon', 'steel'

  // Technical Details
  final int? maxPressurePsi;
  final int? weightGrams;
  final String? spokeHoleDrilling; // 'straight_pull', 'j_bend'

  // Metadata
  final String? notes;
  final String? imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WheelRim({
    this.id,
    this.tenantId,
    this.productId,
    required this.name,
    this.manufacturer,
    this.model,
    required this.erdMm,
    required this.spokeHoles,
    required this.internalWidthMm,
    this.externalWidthMm,
    this.rimDepthMm,
    required this.wheelSize,
    required this.brakeType,
    required this.rimType,
    this.material,
    this.maxPressurePsi,
    this.weightGrams,
    this.spokeHoleDrilling,
    this.notes,
    this.imageUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory WheelRim.fromJson(Map<String, dynamic> json) {
    return WheelRim(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      productId: json['product_id']?.toString(),
      name: json['name']?.toString() ?? '',
      manufacturer: json['manufacturer']?.toString(),
      model: json['model']?.toString(),
      erdMm: _parseDouble(json['erd_mm']) ?? 600.0,
      spokeHoles: _parseInt(json['spoke_holes']) ?? 32,
      internalWidthMm: _parseDouble(json['internal_width_mm']) ?? 19.0,
      externalWidthMm: _parseDouble(json['external_width_mm']),
      rimDepthMm: _parseDouble(json['rim_depth_mm']),
      wheelSize: json['wheel_size']?.toString() ?? '700c',
      brakeType: json['brake_type']?.toString() ?? 'disc',
      rimType: json['rim_type']?.toString() ?? 'clincher',
      material: json['material']?.toString(),
      maxPressurePsi: _parseInt(json['max_pressure_psi']),
      weightGrams: _parseInt(json['weight_grams']),
      spokeHoleDrilling: json['spoke_hole_drilling']?.toString(),
      notes: json['notes']?.toString(),
      imageUrl: json['image_url']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (productId != null) 'product_id': productId,
      'name': name,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      'erd_mm': erdMm,
      'spoke_holes': spokeHoles,
      'internal_width_mm': internalWidthMm,
      if (externalWidthMm != null) 'external_width_mm': externalWidthMm,
      if (rimDepthMm != null) 'rim_depth_mm': rimDepthMm,
      'wheel_size': wheelSize,
      'brake_type': brakeType,
      'rim_type': rimType,
      if (material != null) 'material': material,
      if (maxPressurePsi != null) 'max_pressure_psi': maxPressurePsi,
      if (weightGrams != null) 'weight_grams': weightGrams,
      if (spokeHoleDrilling != null) 'spoke_hole_drilling': spokeHoleDrilling,
      if (notes != null) 'notes': notes,
      if (imageUrl != null) 'image_url': imageUrl,
      'is_active': isActive,
    };
  }

  String get displayName => manufacturer != null ? '$manufacturer $name' : name;
  String get spokeHolesDisplay => '${spokeHoles}H';
  String get sizeDisplay => '$wheelSize (ERD: ${erdMm.toStringAsFixed(1)}mm)';
}

/// Wheel Spoke Specifications
class WheelSpoke {
  final String? id;
  final String? tenantId;
  final String? productId;

  // Basic Info
  final String name;
  final String? manufacturer;
  final String? model;

  // Critical Specs
  final int lengthMm; // Spoke length (290, 292, 294, etc.)
  final double gauge; // Wire thickness (2.0, 1.8, 2.0-1.8 for butted)
  final bool isButted;

  // Specifications
  final String material; // 'stainless_steel', 'brass', 'titanium'
  final String? finish; // 'silver', 'black', 'brass'
  final String headType; // 'j_bend', 'straight_pull'
  final String? threadType; // 'standard', 'lock'

  // Technical Details
  final int? tensileStrengthN; // Newtons
  final double? weightGrams;

  // Metadata
  final String? notes;
  final String? imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WheelSpoke({
    this.id,
    this.tenantId,
    this.productId,
    required this.name,
    this.manufacturer,
    this.model,
    required this.lengthMm,
    required this.gauge,
    this.isButted = false,
    this.material = 'stainless_steel',
    this.finish,
    this.headType = 'j_bend',
    this.threadType,
    this.tensileStrengthN,
    this.weightGrams,
    this.notes,
    this.imageUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory WheelSpoke.fromJson(Map<String, dynamic> json) {
    return WheelSpoke(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      productId: json['product_id']?.toString(),
      name: json['name']?.toString() ?? '',
      manufacturer: json['manufacturer']?.toString(),
      model: json['model']?.toString(),
      lengthMm: _parseInt(json['length_mm']) ?? 290,
      gauge: _parseDouble(json['gauge']) ?? 2.0,
      isButted: json['is_butted'] as bool? ?? false,
      material: json['material']?.toString() ?? 'stainless_steel',
      finish: json['finish']?.toString(),
      headType: json['head_type']?.toString() ?? 'j_bend',
      threadType: json['thread_type']?.toString(),
      tensileStrengthN: _parseInt(json['tensile_strength_n']),
      weightGrams: _parseDouble(json['weight_grams']),
      notes: json['notes']?.toString(),
      imageUrl: json['image_url']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (productId != null) 'product_id': productId,
      'name': name,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      'length_mm': lengthMm,
      'gauge': gauge,
      'is_butted': isButted,
      'material': material,
      if (finish != null) 'finish': finish,
      'head_type': headType,
      if (threadType != null) 'thread_type': threadType,
      if (tensileStrengthN != null) 'tensile_strength_n': tensileStrengthN,
      if (weightGrams != null) 'weight_grams': weightGrams,
      if (notes != null) 'notes': notes,
      if (imageUrl != null) 'image_url': imageUrl,
      'is_active': isActive,
    };
  }

  String get displayName => '$lengthMm mm (${gauge}g)';
  String get lengthDisplay => '${lengthMm}mm';
  String get gaugeDisplay => isButted ? '${gauge}g butted' : '${gauge}g';
}

/// Wheel Build - Saved wheel build specification
class WheelBuild {
  final String? id;
  final String? tenantId;
  final String? bikeId;
  final String? mechanicJobId;

  // Build Info
  final String buildName;
  final String wheelPosition; // 'front', 'rear'
  final DateTime? buildDate;

  // Components
  final String? hubId;
  final String? rimId;
  final String? spokeId;

  // Build Specifications
  final int spokeCount;
  final String
      lacingPattern; // 'radial', '1-cross', '2-cross', '3-cross', '4-cross'

  // Calculated Spoke Lengths
  final double? leftSpokeLengthMm;
  final double? rightSpokeLengthMm;

  // Actual Products Used
  final String? leftSpokeProductId;
  final String? rightSpokeProductId;

  // Additional Components
  final String? nippleType;
  final int? rimTapeWidthMm;

  // Metadata
  final String? notes;
  final String? mechanicNotes;
  final bool isTemplate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WheelBuild({
    this.id,
    this.tenantId,
    this.bikeId,
    this.mechanicJobId,
    required this.buildName,
    required this.wheelPosition,
    this.buildDate,
    this.hubId,
    this.rimId,
    this.spokeId,
    required this.spokeCount,
    required this.lacingPattern,
    this.leftSpokeLengthMm,
    this.rightSpokeLengthMm,
    this.leftSpokeProductId,
    this.rightSpokeProductId,
    this.nippleType,
    this.rimTapeWidthMm,
    this.notes,
    this.mechanicNotes,
    this.isTemplate = false,
    this.createdAt,
    this.updatedAt,
  });

  factory WheelBuild.fromJson(Map<String, dynamic> json) {
    return WheelBuild(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      bikeId: json['bike_id']?.toString(),
      mechanicJobId: json['mechanic_job_id']?.toString(),
      buildName: json['build_name']?.toString() ?? '',
      wheelPosition: json['wheel_position']?.toString() ?? 'rear',
      buildDate: json['build_date'] != null
          ? DateTime.parse(json['build_date'].toString())
          : null,
      hubId: json['hub_id']?.toString(),
      rimId: json['rim_id']?.toString(),
      spokeId: json['spoke_id']?.toString(),
      spokeCount: _parseInt(json['spoke_count']) ?? 32,
      lacingPattern: json['lacing_pattern']?.toString() ?? '3-cross',
      leftSpokeLengthMm: _parseDouble(json['left_spoke_length_mm']),
      rightSpokeLengthMm: _parseDouble(json['right_spoke_length_mm']),
      leftSpokeProductId: json['left_spoke_product_id']?.toString(),
      rightSpokeProductId: json['right_spoke_product_id']?.toString(),
      nippleType: json['nipple_type']?.toString(),
      rimTapeWidthMm: _parseInt(json['rim_tape_width_mm']),
      notes: json['notes']?.toString(),
      mechanicNotes: json['mechanic_notes']?.toString(),
      isTemplate: json['is_template'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      if (bikeId != null) 'bike_id': bikeId,
      if (mechanicJobId != null) 'mechanic_job_id': mechanicJobId,
      'build_name': buildName,
      'wheel_position': wheelPosition,
      if (buildDate != null)
        'build_date': buildDate!.toIso8601String().split('T')[0],
      if (hubId != null) 'hub_id': hubId,
      if (rimId != null) 'rim_id': rimId,
      if (spokeId != null) 'spoke_id': spokeId,
      'spoke_count': spokeCount,
      'lacing_pattern': lacingPattern,
      if (leftSpokeLengthMm != null) 'left_spoke_length_mm': leftSpokeLengthMm,
      if (rightSpokeLengthMm != null)
        'right_spoke_length_mm': rightSpokeLengthMm,
      if (leftSpokeProductId != null)
        'left_spoke_product_id': leftSpokeProductId,
      if (rightSpokeProductId != null)
        'right_spoke_product_id': rightSpokeProductId,
      if (nippleType != null) 'nipple_type': nippleType,
      if (rimTapeWidthMm != null) 'rim_tape_width_mm': rimTapeWidthMm,
      if (notes != null) 'notes': notes,
      if (mechanicNotes != null) 'mechanic_notes': mechanicNotes,
      'is_template': isTemplate,
    };
  }
}

// Helper functions
double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
