// Bikeshop Models - Bikes, Jobs, Service Packages, Labor, Timeline

import 'dart:ui' show Color;

import '../../../shared/models/tax_treatment.dart';

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
  hybrid,
  electric,
  bmx,
  folding,
  cruiser,
  gravel,
  other;

  String get displayName {
    switch (this) {
      case BikeType.road:
        return 'Ruta';
      case BikeType.mountain:
        return 'Montaña';
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
      case BikeType.other:
        return 'Otra';
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
      bikeType: json['bike_type'] != null
          ? BikeType.values.firstWhere(
              (e) => e.toString().split('.').last == json['bike_type'],
              orElse: () => BikeType.other,
            )
          : null,
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
      'bike_type': bikeType?.toString().split('.').last,
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
  todo,       // Not started yet
  inProgress, // Work in progress
  complete;   // Finished

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
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JobStatusCustom && runtimeType == other.runtimeType && id == other.id;

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
// MECHANIC JOB MODEL
// ============================================================

class MechanicJob {
  final String? id;
  final String tenantId;
  final String? jobNumber; // ✅ Nullable - auto-generated by database
  final String customerId;
  final String bikeId;
  final String? servicePackageId;
  final DateTime arrivalDate;
  final DateTime? deadline;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final JobStatus status; // Legacy enum (for backwards compatibility)
  final String? statusId; // New: UUID reference to job_statuses table
  final JobStatusCustom? customStatus; // Loaded from job_statuses join
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
    required this.bikeId,
    this.servicePackageId,
    DateTime? arrivalDate,
    this.deadline,
    this.startedAt,
    this.completedAt,
    this.deliveredAt,
    this.status = JobStatus.pendiente,
    this.statusId,
    this.customStatus,
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
      customStatus = JobStatusCustom.fromJson(json['job_status'] as Map<String, dynamic>);
    }
    
    return MechanicJob(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobNumber: json['job_number']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      servicePackageId: json['service_package_id']?.toString(),
      arrivalDate: _parseDate(json['arrival_date']),
      deadline: _parseDateNullable(json['deadline']),
      startedAt: _parseDateNullable(json['started_at']),
      completedAt: _parseDateNullable(json['completed_at']),
      deliveredAt: _parseDateNullable(json['delivered_at']),
      status: JobStatus.fromDbValue(json['status'] as String?),
      statusId: json['status_id']?.toString(),
      customStatus: customStatus,
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
      'arrival_date': arrivalDate.toIso8601String(), // Always include (editable)
      'deadline': deadline?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'status': status.dbValue,
      if (statusId != null) 'status_id': statusId, // New: custom status reference
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
    String? bikeId,
    String? servicePackageId,
    DateTime? arrivalDate,
    DateTime? deadline,
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
  }) {
    return MechanicJob(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      jobNumber: jobNumber ?? this.jobNumber,
      customerId: customerId ?? this.customerId,
      bikeId: bikeId ?? this.bikeId,
      servicePackageId: servicePackageId ?? this.servicePackageId,
      arrivalDate: arrivalDate ?? this.arrivalDate,
      deadline: deadline ?? this.deadline,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      status: status ?? this.status,
      statusId: statusId ?? this.statusId,
      customStatus: customStatus ?? this.customStatus,
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
  String get statusDisplayName => customStatus?.name ?? status.displayName;
  
  /// Get the color for the status (prefers custom status if available)
  String get statusColor => customStatus?.color ?? _defaultStatusColor;
  
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

  Duration? get timeRemaining {
    if (deadline == null) return null;
    return deadline!.difference(DateTime.now());
  }

  bool get isOverdue {
    if (deadline == null) return false;
    return DateTime.now().isAfter(deadline!);
  }

  bool get isActive {
    return !['FINALIZADO', 'ENTREGADO', 'CANCELADO'].contains(status.dbValue);
  }
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
  
  // Per-bike work details
  final String? diagnosis;
  final String? workRequested;     // Solicitud del cliente
  final String? workPerformed;     // Lo que se hizo
  final String? technicianNotes;   // Notas del técnico
  
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
    this.diagnosis,
    this.workRequested,
    this.workPerformed,
    this.technicianNotes,
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
    
    return MechanicJobBike(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      bikeId: json['bike_id']?.toString() ?? '',
      orderIndex: json['order_index'] as int? ?? 0,
      diagnosis: json['diagnosis'] as String?,
      workRequested: json['work_requested'] as String?,
      workPerformed: json['work_performed'] as String?,
      technicianNotes: json['technician_notes'] as String?,
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
      'diagnosis': diagnosis,
      'work_requested': workRequested,
      'work_performed': workPerformed,
      'technician_notes': technicianNotes,
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
    String? diagnosis,
    String? workRequested,
    String? workPerformed,
    String? technicianNotes,
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
      diagnosis: diagnosis ?? this.diagnosis,
      workRequested: workRequested ?? this.workRequested,
      workPerformed: workPerformed ?? this.workPerformed,
      technicianNotes: technicianNotes ?? this.technicianNotes,
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

// ============================================================
// MECHANIC JOB ITEM MODEL
// ============================================================

class MechanicJobItem {
  final String? id;
  final String tenantId;
  final String jobId;
  final String? jobBikeId;  // ✅ NEW: Links item to specific bike in multi-bike jobs
  final String? productId;
  final String? serviceProductId; // Links services to product catalog
  final String productName;
  final String? productSku;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;
  final String itemType; // 'product' | 'service' | 'adhoc'
  final DateTime createdAt;

  MechanicJobItem({
    this.id,
    required this.tenantId,
    required this.jobId,
    this.jobBikeId,  // ✅ NEW
    this.productId,
    this.serviceProductId,
    required this.productName,
    this.productSku,
    this.quantity = 1,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.notes,
    this.itemType = 'product',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MechanicJobItem.fromJson(Map<String, dynamic> json) {
    return MechanicJobItem(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? '',
      jobBikeId: json['job_bike_id']?.toString(),  // ✅ NEW
      productId: json['product_id']?.toString(),
      serviceProductId: json['service_product_id']?.toString(),
      productName: json['product_name']?.toString() ?? '',
      productSku: json['product_sku'] as String?,
      quantity: double.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0,
      totalPrice: double.tryParse(json['total_price']?.toString() ?? '0') ?? 0,
      notes: json['notes'] as String?,
      itemType: json['item_type'] as String? ?? 'product',
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'job_id': jobId,
      if (jobBikeId != null) 'job_bike_id': jobBikeId,  // ✅ NEW
      'product_id': productId,
      'service_product_id': serviceProductId,
      'product_name': productName,
      'product_sku': productSku,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
      'item_type': itemType,
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
    String? itemType,
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
      itemType: itemType ?? this.itemType,
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
