enum TaskStatus {
  pending,
  inProgress,
  blocked,
  completed,
  cancelled,
}

enum TaskPriority {
  low,
  normal,
  high,
  urgent,
}

/// Una nota es captura rápida sin ciclo de ejecución ni asignado; una tarea
/// es trabajo con responsable. El servidor rechaza notas asignadas.
enum TaskKind { task, note }

/// `private` sólo existe para su creador (y asignado). `team` y `company`
/// comparten alcance de tenant hoy; se distinguen en el dato para cuando
/// exista estructura de equipos.
enum TaskVisibility { private, team, company }

/// Contexto principal opcional de una tarea o nota.
///
/// La tarea sigue siendo una entidad neutral: este valor sólo agrega el lugar
/// del ERP al que pertenece. Taller conserva un segundo nivel propio para sus
/// servicios; los demás módulos enlazan una única entidad completa.
enum TaskContextKind {
  none,
  workshopJob,
  customer,
  supplier,
  salesInvoice,
  purchaseInvoice,
}

/// Proyección mínima y navegable de una entidad vinculable desde Tareas.
class TaskContextTarget {
  const TaskContextTarget({
    required this.kind,
    required this.id,
    required this.label,
    required this.route,
    this.context,
    this.searchText,
  });

  final TaskContextKind kind;
  final String id;
  final String label;
  final String route;
  final String? context;
  final String? searchText;
}

class TaskModel {
  final String? id;
  final String tenantId;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? dueDate;

  // Assignment and Tracking
  final String? assignedTo;
  final String createdBy;

  // DB relationships (joined data if needed)
  final String? assigneeName;
  final String? creatorName;

  // Polymorphic Relations
  final String? linkedJobId;
  final String? linkedPurchaseInvoiceId;
  final String? linkedSalesInvoiceId;
  final String? linkedCustomerId;
  final String? linkedSupplierId;

  // Convenience references for UI badging (optional, populated via joins/service)
  final String? linkedJobNumber;
  final String? linkedPurchaseInvoiceNumber;
  final String? linkedSalesInvoiceNumber;
  final String? linkedCustomerName;
  final String? linkedSupplierName;

  // Attachments: list of {name, url, type, size, uploaded_at}
  final List<Map<String, dynamic>> attachments;

  // Work-tray lifecycle (kernel 20260826220000)
  final TaskKind kind;
  final TaskVisibility visibility;
  final int version;
  final DateTime? assignedAt;
  final DateTime? acknowledgedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? completedBy;
  final DateTime? blockedAt;
  final String? blockedReason;

  final DateTime createdAt;
  final DateTime updatedAt;

  TaskModel({
    this.id,
    required this.tenantId,
    required this.title,
    this.description,
    this.status = TaskStatus.pending,
    this.priority = TaskPriority.normal,
    this.dueDate,
    this.assignedTo,
    required this.createdBy,
    this.assigneeName,
    this.creatorName,
    this.linkedJobId,
    this.linkedPurchaseInvoiceId,
    this.linkedSalesInvoiceId,
    this.linkedCustomerId,
    this.linkedSupplierId,
    this.linkedJobNumber,
    this.linkedPurchaseInvoiceNumber,
    this.linkedSalesInvoiceNumber,
    this.linkedCustomerName,
    this.linkedSupplierName,
    this.attachments = const [],
    this.kind = TaskKind.task,
    this.visibility = TaskVisibility.team,
    this.version = 1,
    this.assignedAt,
    this.acknowledgedAt,
    this.startedAt,
    this.completedAt,
    this.completedBy,
    this.blockedAt,
    this.blockedReason,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static TaskStatus _parseStatus(String? value) {
    switch (value) {
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'blocked':
        return TaskStatus.blocked;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      case 'pending':
        return TaskStatus.pending;
      default:
        return TaskStatus.pending;
    }
  }

  static String _statusToString(TaskStatus status) {
    switch (status) {
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.blocked:
        return 'blocked';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.cancelled:
        return 'cancelled';
      case TaskStatus.pending:
        return 'pending';
    }
  }

  static TaskKind _parseKind(String? value) =>
      value == 'note' ? TaskKind.note : TaskKind.task;

  static TaskVisibility _parseVisibility(String? value) {
    switch (value) {
      case 'private':
        return TaskVisibility.private;
      case 'company':
        return TaskVisibility.company;
      default:
        return TaskVisibility.team;
    }
  }

  static String kindToString(TaskKind kind) =>
      kind == TaskKind.note ? 'note' : 'task';

  static String visibilityToString(TaskVisibility visibility) {
    switch (visibility) {
      case TaskVisibility.private:
        return 'private';
      case TaskVisibility.team:
        return 'team';
      case TaskVisibility.company:
        return 'company';
    }
  }

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  static TaskPriority _parsePriority(String? value) {
    switch (value) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'urgent':
        return TaskPriority.urgent;
      case 'normal':
        return TaskPriority.normal;
      default:
        return TaskPriority.normal;
    }
  }

  static String _priorityToString(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'low';
      case TaskPriority.high:
        return 'high';
      case TaskPriority.urgent:
        return 'urgent';
      case TaskPriority.normal:
        return 'normal';
    }
  }

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      status: _parseStatus(json['status']),
      priority: _parsePriority(json['priority']),
      dueDate:
          json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      assignedTo: json['assigned_to']?.toString(),
      createdBy: json['created_by']?.toString() ?? '',
      assigneeName: json['assignee_name'],
      creatorName: json['creator_name'],
      linkedJobId: json['linked_job_id']?.toString(),
      linkedPurchaseInvoiceId: json['linked_purchase_invoice_id']?.toString(),
      linkedSalesInvoiceId: json['linked_sales_invoice_id']?.toString(),
      linkedCustomerId: json['linked_customer_id']?.toString(),
      linkedSupplierId: json['linked_supplier_id']?.toString(),
      linkedJobNumber: json['linked_job_number'],
      linkedPurchaseInvoiceNumber: json['linked_purchase_invoice_number'],
      linkedSalesInvoiceNumber: json['linked_sales_invoice_number'],
      linkedCustomerName: json['linked_customer_name'],
      linkedSupplierName: json['linked_supplier_name'],
      attachments: json['attachments'] != null
          ? List<Map<String, dynamic>>.from((json['attachments'] as List)
              .map((e) => Map<String, dynamic>.from(e)))
          : [],
      kind: _parseKind(json['task_kind']?.toString()),
      visibility: _parseVisibility(json['visibility']?.toString()),
      version: (json['version'] as num?)?.toInt() ?? 1,
      assignedAt: _parseDate(json['assigned_at']),
      acknowledgedAt: _parseDate(json['acknowledged_at']),
      startedAt: _parseDate(json['started_at']),
      completedAt: _parseDate(json['completed_at']),
      completedBy: json['completed_by']?.toString(),
      blockedAt: _parseDate(json['blocked_at']),
      blockedReason: json['blocked_reason']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  static String statusToString(TaskStatus status) => _statusToString(status);

  Map<String, dynamic> toJson() {
    final json = {
      'tenant_id': tenantId,
      'title': title,
      'description': description,
      'status': _statusToString(status),
      'priority': _priorityToString(priority),
      'due_date': dueDate?.toIso8601String(),
      'assigned_to': assignedTo,
      'created_by': createdBy,
      'linked_job_id': linkedJobId,
      'linked_purchase_invoice_id': linkedPurchaseInvoiceId,
      'linked_sales_invoice_id': linkedSalesInvoiceId,
      'linked_customer_id': linkedCustomerId,
      'linked_supplier_id': linkedSupplierId,
      'attachments': attachments,
      'task_kind': kindToString(kind),
      'visibility': visibilityToString(visibility),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    json.removeWhere((_, value) => value == null);

    if (id != null) {
      json['id'] = id;
    }

    return json;
  }

  TaskModel copyWith({
    String? id,
    String? tenantId,
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? dueDate,
    String? assignedTo,
    String? createdBy,
    String? assigneeName,
    String? creatorName,
    String? linkedJobId,
    String? linkedPurchaseInvoiceId,
    String? linkedSalesInvoiceId,
    String? linkedCustomerId,
    String? linkedSupplierId,
    String? linkedJobNumber,
    String? linkedPurchaseInvoiceNumber,
    String? linkedSalesInvoiceNumber,
    String? linkedCustomerName,
    String? linkedSupplierName,
    List<Map<String, dynamic>>? attachments,
    TaskKind? kind,
    TaskVisibility? visibility,
    int? version,
    DateTime? assignedAt,
    DateTime? acknowledgedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? completedBy,
    DateTime? blockedAt,
    String? blockedReason,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      assignedTo: assignedTo ?? this.assignedTo,
      createdBy: createdBy ?? this.createdBy,
      assigneeName: assigneeName ?? this.assigneeName,
      creatorName: creatorName ?? this.creatorName,
      linkedJobId: linkedJobId ?? this.linkedJobId,
      linkedPurchaseInvoiceId:
          linkedPurchaseInvoiceId ?? this.linkedPurchaseInvoiceId,
      linkedSalesInvoiceId: linkedSalesInvoiceId ?? this.linkedSalesInvoiceId,
      linkedCustomerId: linkedCustomerId ?? this.linkedCustomerId,
      linkedSupplierId: linkedSupplierId ?? this.linkedSupplierId,
      linkedJobNumber: linkedJobNumber ?? this.linkedJobNumber,
      linkedPurchaseInvoiceNumber:
          linkedPurchaseInvoiceNumber ?? this.linkedPurchaseInvoiceNumber,
      linkedSalesInvoiceNumber:
          linkedSalesInvoiceNumber ?? this.linkedSalesInvoiceNumber,
      linkedCustomerName: linkedCustomerName ?? this.linkedCustomerName,
      linkedSupplierName: linkedSupplierName ?? this.linkedSupplierName,
      attachments: attachments ?? this.attachments,
      kind: kind ?? this.kind,
      visibility: visibility ?? this.visibility,
      version: version ?? this.version,
      assignedAt: assignedAt ?? this.assignedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      blockedAt: blockedAt ?? this.blockedAt,
      blockedReason: blockedReason ?? this.blockedReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isDone =>
      status == TaskStatus.completed || status == TaskStatus.cancelled;
  bool get isBlocked => status == TaskStatus.blocked;

  TaskContextKind get contextKind {
    if (linkedJobId != null) return TaskContextKind.workshopJob;
    if (linkedCustomerId != null) return TaskContextKind.customer;
    if (linkedSupplierId != null) return TaskContextKind.supplier;
    if (linkedSalesInvoiceId != null) return TaskContextKind.salesInvoice;
    if (linkedPurchaseInvoiceId != null) return TaskContextKind.purchaseInvoice;
    return TaskContextKind.none;
  }

  /// Contextos no-Taller. Taller se representa con su cabecera y sus servicios
  /// reales porque tiene una jerarquía adicional que este resumen no aplana.
  TaskContextTarget? get linkedContextTarget {
    if (linkedCustomerId != null) {
      return TaskContextTarget(
        kind: TaskContextKind.customer,
        id: linkedCustomerId!,
        label: linkedCustomerName ?? 'Cliente',
        route: '/clientes/${Uri.encodeComponent(linkedCustomerId!)}',
      );
    }
    if (linkedSupplierId != null) {
      return TaskContextTarget(
        kind: TaskContextKind.supplier,
        id: linkedSupplierId!,
        label: linkedSupplierName ?? 'Proveedor',
        route: '/purchases/suppliers/${Uri.encodeComponent(linkedSupplierId!)}',
      );
    }
    if (linkedSalesInvoiceId != null) {
      return TaskContextTarget(
        kind: TaskContextKind.salesInvoice,
        id: linkedSalesInvoiceId!,
        label: linkedSalesInvoiceNumber == null
            ? 'Venta'
            : 'Venta #$linkedSalesInvoiceNumber',
        route: '/sales/invoices/${Uri.encodeComponent(linkedSalesInvoiceId!)}',
      );
    }
    if (linkedPurchaseInvoiceId != null) {
      return TaskContextTarget(
        kind: TaskContextKind.purchaseInvoice,
        id: linkedPurchaseInvoiceId!,
        label: linkedPurchaseInvoiceNumber == null
            ? 'Compra'
            : 'Compra #$linkedPurchaseInvoiceNumber',
        route: '/purchases/${Uri.encodeComponent(linkedPurchaseInvoiceId!)}',
      );
    }
    return null;
  }

  /// «Por aceptar» para el asignado: asignada y sin acuse de recibo.
  bool get awaitsAcknowledgement =>
      assignedTo != null && acknowledgedAt == null && !isDone;
}
