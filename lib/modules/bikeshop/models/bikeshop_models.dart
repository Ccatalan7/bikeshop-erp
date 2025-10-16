// Bikeshop Models - Bikes, Jobs, Service Packages, Labor, Timeline

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
  final String customerId;
  final String? brand;
  final String? model;
  final int? year;
  final String? serialNumber;
  final String? color;
  final String? frameSize;
  final String? wheelSize;
  final BikeType? bikeType;
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
    required this.customerId,
    this.brand,
    this.model,
    this.year,
    this.serialNumber,
    this.color,
    this.frameSize,
    this.wheelSize,
    this.bikeType,
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
      customerId: json['customer_id']?.toString() ?? '',
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
      'customer_id': customerId,
      'brand': brand,
      'model': model,
      'year': year,
      'serial_number': serialNumber,
      'color': color,
      'frame_size': frameSize,
      'wheel_size': wheelSize,
      'bike_type': bikeType?.toString().split('.').last,
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
    String? customerId,
    String? brand,
    String? model,
    int? year,
    String? serialNumber,
    String? color,
    String? frameSize,
    String? wheelSize,
    BikeType? bikeType,
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
      customerId: customerId ?? this.customerId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      serialNumber: serialNumber ?? this.serialNumber,
      color: color ?? this.color,
      frameSize: frameSize ?? this.frameSize,
      wheelSize: wheelSize ?? this.wheelSize,
      bikeType: bikeType ?? this.bikeType,
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
// MECHANIC JOB STATUS & PRIORITY
// ============================================================

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
  final String jobNumber;
  final String customerId;
  final String bikeId;
  final String? servicePackageId;
  final DateTime arrivalDate;
  final DateTime? deadline;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;
  final JobStatus status;
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

  MechanicJob({
    this.id,
    required this.jobNumber,
    required this.customerId,
    required this.bikeId,
    this.servicePackageId,
    DateTime? arrivalDate,
    this.deadline,
    this.startedAt,
    this.completedAt,
    this.deliveredAt,
    this.status = JobStatus.pendiente,
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
  })  : arrivalDate = arrivalDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MechanicJob.fromJson(Map<String, dynamic> json) {
    return MechanicJob(
      id: json['id']?.toString(),
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
      priority: JobPriority.fromDbValue(json['priority'] as String?),
      clientRequest: json['client_request'] as String?,
      diagnosis: json['diagnosis'] as String?,
      workPerformed: json['work_performed'] as String?,
      notes: json['notes'] as String?,
      assignedTo: json['assigned_to']?.toString(),
      assignedTechnicianName: json['assigned_technician_name'] as String?,
      estimatedCost: double.tryParse(json['estimated_cost']?.toString() ?? '0') ?? 0,
      finalCost: double.tryParse(json['final_cost']?.toString() ?? '0') ?? 0,
      partsCost: double.tryParse(json['parts_cost']?.toString() ?? '0') ?? 0,
      laborCost: double.tryParse(json['labor_cost']?.toString() ?? '0') ?? 0,
      discountAmount: double.tryParse(json['discount_amount']?.toString() ?? '0') ?? 0,
      taxAmount: double.tryParse(json['tax_amount']?.toString() ?? '0') ?? 0,
      totalCost: double.tryParse(json['total_cost']?.toString() ?? '0') ?? 0,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'job_number': jobNumber,
      'customer_id': customerId,
      'bike_id': bikeId,
      'service_package_id': servicePackageId,
      'arrival_date': arrivalDate.toIso8601String(),
      'deadline': deadline?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'status': status.dbValue,
      'priority': priority.dbValue,
      'client_request': clientRequest,
      'diagnosis': diagnosis,
      'work_performed': workPerformed,
      'notes': notes,
      'assigned_to': assignedTo,
      'assigned_technician_name': assignedTechnicianName,
      'estimated_cost': estimatedCost,
      'final_cost': finalCost,
      'parts_cost': partsCost,
      'labor_cost': laborCost,
      'discount_amount': discountAmount,
      'tax_amount': taxAmount,
      'total_cost': totalCost,
      'invoice_id': invoiceId,
      'is_invoiced': isInvoiced,
      'is_paid': isPaid,
      'is_warranty_job': isWarrantyJob,
      'warranty_notes': warrantyNotes,
      'requires_approval': requiresApproval,
      'approved_by_customer': approvedByCustomer,
      'approved_at': approvedAt?.toIso8601String(),
      'image_urls': imageUrls,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  MechanicJob copyWith({
    String? id,
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
  }) {
    return MechanicJob(
      id: id ?? this.id,
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
      priority: priority ?? this.priority,
      clientRequest: clientRequest ?? this.clientRequest,
      diagnosis: diagnosis ?? this.diagnosis,
      workPerformed: workPerformed ?? this.workPerformed,
      notes: notes ?? this.notes,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedTechnicianName: assignedTechnicianName ?? this.assignedTechnicianName,
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

class MechanicJobItem {
  final String? id;
  final String jobId;
  final String? productId;
  final String productName;
  final String? productSku;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final String? notes;
  final DateTime createdAt;

  MechanicJobItem({
    this.id,
    required this.jobId,
    this.productId,
    required this.productName,
    this.productSku,
    this.quantity = 1,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MechanicJobItem.fromJson(Map<String, dynamic> json) {
    return MechanicJobItem(
      id: json['id']?.toString(),
      jobId: json['job_id']?.toString() ?? '',
      productId: json['product_id']?.toString(),
      productName: json['product_name']?.toString() ?? '',
      productSku: json['product_sku'] as String?,
      quantity: double.tryParse(json['quantity']?.toString() ?? '1') ?? 1,
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0,
      totalPrice: double.tryParse(json['total_price']?.toString() ?? '0') ?? 0,
      notes: json['notes'] as String?,
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'job_id': jobId,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

// ============================================================
// MECHANIC JOB LABOR MODEL
// ============================================================

class MechanicJobLabor {
  final String? id;
  final String jobId;
  final String? technicianId;
  final String technicianName;
  final String? description;
  final double hoursWorked;
  final double hourlyRate;
  final double totalCost;
  final DateTime workDate;
  final DateTime createdAt;

  MechanicJobLabor({
    this.id,
    required this.jobId,
    this.technicianId,
    required this.technicianName,
    this.description,
    this.hoursWorked = 0,
    this.hourlyRate = 0,
    this.totalCost = 0,
    DateTime? workDate,
    DateTime? createdAt,
  })  : workDate = workDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory MechanicJobLabor.fromJson(Map<String, dynamic> json) {
    return MechanicJobLabor(
      id: json['id']?.toString(),
      jobId: json['job_id']?.toString() ?? '',
      technicianId: json['technician_id']?.toString(),
      technicianName: json['technician_name']?.toString() ?? '',
      description: json['description'] as String?,
      hoursWorked: double.tryParse(json['hours_worked']?.toString() ?? '0') ?? 0,
      hourlyRate: double.tryParse(json['hourly_rate']?.toString() ?? '0') ?? 0,
      totalCost: double.tryParse(json['total_cost']?.toString() ?? '0') ?? 0,
      workDate: _parseDate(json['work_date']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'job_id': jobId,
      'technician_id': technicianId,
      'technician_name': technicianName,
      'description': description,
      'hours_worked': hoursWorked,
      'hourly_rate': hourlyRate,
      'total_cost': totalCost,
      'work_date': workDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
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
    return toString().split('.').last.toLowerCase().replaceAll(RegExp(r'([A-Z])'), '_\$1').substring(1);
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
      name: json['name']?.toString() ?? '',
      description: json['description'] as String?,
      estimatedDurationHours:
          double.tryParse(json['estimated_duration_hours']?.toString() ?? '1') ?? 1,
      baseLaborCost: double.tryParse(json['base_labor_cost']?.toString() ?? '0') ?? 0,
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
