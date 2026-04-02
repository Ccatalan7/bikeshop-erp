import '../../../shared/models/product.dart'
    show PurchaseTreatment, parsePurchaseTreatment;

class SmartPurchaseListItem {
  final String id;
  final String? productId;
  final String productName;
  final String? productSku;
  final PurchaseTreatment purchaseTreatment;
  final String? categoryId;
  final String? categoryName;
  final String? supplierId;
  final String? supplierName;
  final int suggestedQuantity;
  final int? actualQuantity;
  final String status; // pending, ordered, received, ignored, cancelled
  final double priority; // 0-100 scale
  final double? rotationKpi; // Sales per day
  final int? daysSinceLastPurchase;
  final int currentStock;
  final int minStockLevel;
  final int? stockAtOrder; // Stock quantity when purchase order was generated
  final int?
      stockAtReceipt; // Stock quantity when invoice was received (final stock after purchase)
  final double? avgDailyConsumption;
  final int leadTimeDays;
  final DateTime? estimatedStockoutDate;
  final String? notes;
  final String? addedBy;
  final DateTime addedDate;
  final String? linkedPurchaseInvoiceId;
  final String? linkedExpenseId;
  final DateTime? orderedDate;
  final DateTime? receivedDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SmartPurchaseListItem({
    required this.id,
    this.productId,
    required this.productName,
    this.productSku,
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.categoryId,
    this.categoryName,
    this.supplierId,
    this.supplierName,
    required this.suggestedQuantity,
    this.actualQuantity,
    required this.status,
    required this.priority,
    this.rotationKpi,
    this.daysSinceLastPurchase,
    required this.currentStock,
    required this.minStockLevel,
    this.stockAtOrder,
    this.stockAtReceipt,
    this.avgDailyConsumption,
    required this.leadTimeDays,
    this.estimatedStockoutDate,
    this.notes,
    this.addedBy,
    required this.addedDate,
    this.linkedPurchaseInvoiceId,
    this.linkedExpenseId,
    this.orderedDate,
    this.receivedDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SmartPurchaseListItem.fromJson(Map<String, dynamic> json) {
    // Extract category from nested products join
    String? categoryId;
    String? categoryName;
    var purchaseTreatment = PurchaseTreatment.inventory;

    if (json['products'] != null && json['products'] is Map) {
      final products = json['products'] as Map<String, dynamic>;
      categoryId = products['category_id'] as String?;
      purchaseTreatment = parsePurchaseTreatment(
        products['purchase_treatment'],
        productType: products['product_type'] as String?,
        trackStock: products['track_stock'] as bool?,
      );

      if (products['product_categories'] != null &&
          products['product_categories'] is Map) {
        final category = products['product_categories'] as Map<String, dynamic>;
        categoryId = category['id'] as String?;
        categoryName =
            category['full_path'] as String? ?? category['name'] as String?;
      }
    }

    // Fallback to direct fields if they exist
    categoryId ??= json['category_id'] as String?;
    categoryName ??= json['category_name'] as String?;

    return SmartPurchaseListItem(
      id: json['id'] as String,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String? ?? '',
      productSku: json['product_sku'] as String?,
      purchaseTreatment: purchaseTreatment,
      categoryId: categoryId,
      categoryName: categoryName,
      supplierId: json['supplier_id'] as String?,
      supplierName: json['supplier_name'] as String?,
      suggestedQuantity: json['suggested_quantity'] as int? ?? 1,
      actualQuantity: json['actual_quantity'] as int?,
      status: json['status'] as String? ?? 'pending',
      priority: (json['priority'] as num?)?.toDouble() ?? 50.0,
      rotationKpi: (json['rotation_kpi'] as num?)?.toDouble(),
      daysSinceLastPurchase: json['days_since_last_purchase'] as int?,
      currentStock: json['current_stock'] as int? ?? 0,
      minStockLevel: json['min_stock_level'] as int? ?? 0,
      stockAtOrder: json['stock_at_order'] as int?,
      stockAtReceipt: json['stock_at_receipt'] as int?,
      avgDailyConsumption: (json['avg_daily_consumption'] as num?)?.toDouble(),
      leadTimeDays: json['lead_time_days'] as int? ?? 0,
      estimatedStockoutDate: json['estimated_stockout_date'] != null
          ? DateTime.parse(json['estimated_stockout_date'] as String)
          : null,
      notes: json['notes'] as String?,
      addedBy: json['added_by'] as String?,
      addedDate: json['added_date'] != null
          ? DateTime.parse(json['added_date'] as String)
          : DateTime.now(),
      linkedPurchaseInvoiceId: json['linked_purchase_invoice_id'] as String?,
      linkedExpenseId: json['linked_expense_id'] as String?,
      orderedDate: json['ordered_date'] != null
          ? DateTime.parse(json['ordered_date'] as String)
          : null,
      receivedDate: json['received_date'] != null
          ? DateTime.parse(json['received_date'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'purchase_treatment': purchaseTreatment.dbValue,
      'category_id': categoryId,
      'category_name': categoryName,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'suggested_quantity': suggestedQuantity,
      'actual_quantity': actualQuantity,
      'status': status,
      'priority': priority,
      'rotation_kpi': rotationKpi,
      'days_since_last_purchase': daysSinceLastPurchase,
      'current_stock': currentStock,
      'min_stock_level': minStockLevel,
      'stock_at_order': stockAtOrder,
      'stock_at_receipt': stockAtReceipt,
      'avg_daily_consumption': avgDailyConsumption,
      'lead_time_days': leadTimeDays,
      'estimated_stockout_date': estimatedStockoutDate?.toIso8601String(),
      'notes': notes,
      'added_by': addedBy,
      'added_date': addedDate.toIso8601String(),
      'linked_purchase_invoice_id': linkedPurchaseInvoiceId,
      'linked_expense_id': linkedExpenseId,
      'ordered_date': orderedDate?.toIso8601String(),
      'received_date': receivedDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SmartPurchaseListItem copyWith({
    String? id,
    String? productId,
    String? productName,
    String? productSku,
    PurchaseTreatment? purchaseTreatment,
    String? categoryId,
    String? categoryName,
    String? supplierId,
    String? supplierName,
    int? suggestedQuantity,
    int? actualQuantity,
    String? status,
    double? priority,
    double? rotationKpi,
    int? daysSinceLastPurchase,
    int? currentStock,
    int? minStockLevel,
    int? stockAtOrder,
    int? stockAtReceipt,
    double? avgDailyConsumption,
    int? leadTimeDays,
    DateTime? estimatedStockoutDate,
    String? notes,
    String? addedBy,
    DateTime? addedDate,
    String? linkedPurchaseInvoiceId,
    String? linkedExpenseId,
    DateTime? orderedDate,
    DateTime? receivedDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SmartPurchaseListItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      purchaseTreatment: purchaseTreatment ?? this.purchaseTreatment,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      suggestedQuantity: suggestedQuantity ?? this.suggestedQuantity,
      actualQuantity: actualQuantity ?? this.actualQuantity,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      rotationKpi: rotationKpi ?? this.rotationKpi,
      daysSinceLastPurchase:
          daysSinceLastPurchase ?? this.daysSinceLastPurchase,
      currentStock: currentStock ?? this.currentStock,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      stockAtOrder: stockAtOrder ?? this.stockAtOrder,
      stockAtReceipt: stockAtReceipt ?? this.stockAtReceipt,
      avgDailyConsumption: avgDailyConsumption ?? this.avgDailyConsumption,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      estimatedStockoutDate:
          estimatedStockoutDate ?? this.estimatedStockoutDate,
      notes: notes ?? this.notes,
      addedBy: addedBy ?? this.addedBy,
      addedDate: addedDate ?? this.addedDate,
      linkedPurchaseInvoiceId:
          linkedPurchaseInvoiceId ?? this.linkedPurchaseInvoiceId,
      linkedExpenseId: linkedExpenseId ?? this.linkedExpenseId,
      orderedDate: orderedDate ?? this.orderedDate,
      receivedDate: receivedDate ?? this.receivedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper getters
  int get quantityToBuy => actualQuantity ?? suggestedQuantity;

  bool get isPending => status == 'pending';
  bool get isOrdered => status == 'ordered';
  bool get isReceived => status == 'received';
  bool get isIgnored => status == 'ignored';
  bool get isCancelled => status == 'cancelled';

  bool get hasLinkedDocument =>
      linkedPurchaseInvoiceId != null || linkedExpenseId != null;

  // Priority levels
  String get priorityLevel {
    if (priority >= 80) return 'critical';
    if (priority >= 60) return 'high';
    if (priority >= 40) return 'medium';
    return 'low';
  }

  // Urgency indicator
  bool get isUrgent => priority >= 80 || currentStock == 0;
  bool get isOutOfStock => currentStock <= 0;
  bool get isBelowMinimum => currentStock <= minStockLevel;
}
