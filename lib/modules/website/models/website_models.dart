/// Website and e-commerce data models
library;

class WebsiteBanner {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? link;
  final String? ctaText;
  final String? ctaLink;
  final bool active;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  WebsiteBanner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.link,
    this.ctaText,
    this.ctaLink,
    required this.active,
    required this.orderIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WebsiteBanner.fromJson(Map<String, dynamic> json) {
    return WebsiteBanner(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['image_url'] as String?,
      link: json['link'] as String?,
      ctaText: json['cta_text'] as String?,
      ctaLink: json['cta_link'] as String?,
      active: json['active'] as bool? ?? true,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'image_url': imageUrl,
      'link': link,
      'cta_text': ctaText,
      'cta_link': ctaLink,
      'active': active,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WebsiteBanner copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? link,
    String? ctaText,
    String? ctaLink,
    bool? active,
    int? orderIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WebsiteBanner(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      link: link ?? this.link,
      ctaText: ctaText ?? this.ctaText,
      ctaLink: ctaLink ?? this.ctaLink,
      active: active ?? this.active,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class FeaturedProduct {
  final String id;
  final String productId;
  final bool active;
  final int orderIndex;
  final DateTime createdAt;

  FeaturedProduct({
    required this.id,
    required this.productId,
    required this.active,
    required this.orderIndex,
    required this.createdAt,
  });

  factory FeaturedProduct.fromJson(Map<String, dynamic> json) {
    return FeaturedProduct(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      active: json['active'] as bool? ?? true,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'active': active,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WebsiteContent {
  final String id;
  final String title;
  final String? content;
  final DateTime updatedAt;

  WebsiteContent({
    required this.id,
    required this.title,
    this.content,
    required this.updatedAt,
  });

  factory WebsiteContent.fromJson(Map<String, dynamic> json) {
    return WebsiteContent(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class WebsiteSetting {
  final String id;
  final String key;
  final String? value;
  final String? description;
  final DateTime updatedAt;

  WebsiteSetting({
    required this.id,
    required this.key,
    this.value,
    this.description,
    required this.updatedAt,
  });

  factory WebsiteSetting.fromJson(Map<String, dynamic> json) {
    return WebsiteSetting(
      id: json['id'] as String,
      key: json['key'] as String,
      value: json['value'] as String?,
      description: json['description'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'value': value,
      'description': description,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class OnlineOrder {
  final String id;
  final String orderNumber;
  final String? customerId;
  final String customerEmail;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;
  
  final double subtotal;
  final double taxAmount;
  final double shippingCost;
  final double discountAmount;
  final double total;
  
  final String status;
  final String paymentStatus;
  
  final String? paymentMethod;
  final String? paymentReference;
  final DateTime? paidAt;
  
  final String? trackingNumber;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  
  final String? salesInvoiceId;
  
  final String? customerNotes;
  final String? internalNotes;
  
  final DateTime createdAt;
  final DateTime updatedAt;
  
  final List<OnlineOrderItem> items;

  OnlineOrder({
    required this.id,
    required this.orderNumber,
    this.customerId,
    required this.customerEmail,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    required this.subtotal,
    required this.taxAmount,
    required this.shippingCost,
    required this.discountAmount,
    required this.total,
    required this.status,
    required this.paymentStatus,
    this.paymentMethod,
    this.paymentReference,
    this.paidAt,
    this.trackingNumber,
    this.shippedAt,
    this.deliveredAt,
    this.salesInvoiceId,
    this.customerNotes,
    this.internalNotes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  factory OnlineOrder.fromJson(Map<String, dynamic> json) {
    return OnlineOrder(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String,
      customerId: json['customer_id'] as String?,
      customerEmail: json['customer_email'] as String,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      customerAddress: json['customer_address'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      paymentMethod: json['payment_method'] as String?,
      paymentReference: json['payment_reference'] as String?,
      paidAt: json['paid_at'] != null ? DateTime.parse(json['paid_at'] as String) : null,
      trackingNumber: json['tracking_number'] as String?,
      shippedAt: json['shipped_at'] != null ? DateTime.parse(json['shipped_at'] as String) : null,
      deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at'] as String) : null,
      salesInvoiceId: json['sales_invoice_id'] as String?,
      customerNotes: json['customer_notes'] as String?,
      internalNotes: json['internal_notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      items: [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_email': customerEmail,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'subtotal': subtotal,
      'tax_amount': taxAmount,
      'shipping_cost': shippingCost,
      'discount_amount': discountAmount,
      'total': total,
      'status': status,
      'payment_status': paymentStatus,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference,
      'paid_at': paidAt?.toIso8601String(),
      'tracking_number': trackingNumber,
      'shipped_at': shippedAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'sales_invoice_id': salesInvoiceId,
      'customer_notes': customerNotes,
      'internal_notes': internalNotes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  OnlineOrder copyWith({
    String? id,
    String? orderNumber,
    String? customerId,
    String? customerEmail,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    double? subtotal,
    double? taxAmount,
    double? shippingCost,
    double? discountAmount,
    double? total,
    String? status,
    String? paymentStatus,
    String? paymentMethod,
    String? paymentReference,
    DateTime? paidAt,
    String? trackingNumber,
    DateTime? shippedAt,
    DateTime? deliveredAt,
    String? salesInvoiceId,
    String? customerNotes,
    String? internalNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<OnlineOrderItem>? items,
  }) {
    return OnlineOrder(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      customerEmail: customerEmail ?? this.customerEmail,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      shippingCost: shippingCost ?? this.shippingCost,
      discountAmount: discountAmount ?? this.discountAmount,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      paidAt: paidAt ?? this.paidAt,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      shippedAt: shippedAt ?? this.shippedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      salesInvoiceId: salesInvoiceId ?? this.salesInvoiceId,
      customerNotes: customerNotes ?? this.customerNotes,
      internalNotes: internalNotes ?? this.internalNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }

  String get statusDisplayName {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'confirmed':
        return 'Confirmado';
      case 'processing':
        return 'En Proceso';
      case 'shipped':
        return 'Enviado';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  String get paymentStatusDisplayName {
    switch (paymentStatus) {
      case 'pending':
        return 'Pendiente';
      case 'paid':
        return 'Pagado';
      case 'failed':
        return 'Fallido';
      case 'refunded':
        return 'Reembolsado';
      default:
        return paymentStatus;
    }
  }
}

class OnlineOrderItem {
  final String id;
  final String orderId;
  final String? productId;
  final String productName;
  final String? productSku;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final DateTime createdAt;

  OnlineOrderItem({
    required this.id,
    required this.orderId,
    this.productId,
    required this.productName,
    this.productSku,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.createdAt,
  });

  factory OnlineOrderItem.fromJson(Map<String, dynamic> json) {
    return OnlineOrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String,
      productSku: json['product_sku'] as String?,
      quantity: json['quantity'] as int,
      unitPrice: (json['unit_price'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'quantity': quantity,
      'unit_price': unitPrice,
      'subtotal': subtotal,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
