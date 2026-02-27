enum TaskStatus {
  pending,
  inProgress,
  completed,
  cancelled,
}

enum TaskPriority {
  low,
  normal,
  high,
  urgent,
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
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static TaskStatus _parseStatus(String? value) {
    switch (value) {
      case 'in_progress':
        return TaskStatus.inProgress;
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
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.cancelled:
        return 'cancelled';
      case TaskStatus.pending:
      default:
        return 'pending';
    }
  }

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
      default:
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
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
