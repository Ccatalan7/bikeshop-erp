/// Website and e-commerce data models
library;

class WebsiteBanner {
  final String id;
  final String tenantId;
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
    required this.tenantId,
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
      tenantId: json['tenant_id']?.toString() ?? '',
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
      'tenant_id': tenantId,
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
    String? tenantId,
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
      tenantId: tenantId ?? this.tenantId,
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
  final String tenantId;
  final String productId;
  final bool active;
  final int orderIndex;
  final DateTime createdAt;

  FeaturedProduct({
    required this.id,
    required this.tenantId,
    required this.productId,
    required this.active,
    required this.orderIndex,
    required this.createdAt,
  });

  factory FeaturedProduct.fromJson(Map<String, dynamic> json) {
    return FeaturedProduct(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      productId: json['product_id'] as String,
      active: json['active'] as bool? ?? true,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'product_id': productId,
      'active': active,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WebsiteContent {
  final String id;
  final String tenantId;
  final String title;
  final String? content;
  final DateTime updatedAt;

  WebsiteContent({
    required this.id,
    required this.tenantId,
    required this.title,
    this.content,
    required this.updatedAt,
  });

  factory WebsiteContent.fromJson(Map<String, dynamic> json) {
    return WebsiteContent(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      title: json['title'] as String,
      content: json['content'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ThemePreset {
  final String id;
  final String tenantId;
  final String name;
  final String? description;
  final int primaryColor;
  final int accentColor;
  final int backgroundColor;
  final int textColor;
  final String headingFont;
  final String bodyFont;
  final double headingSize;
  final double bodySize;
  final double sectionSpacing;
  final double containerPadding;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ThemePreset({
    required this.id,
    required this.tenantId,
    required this.name,
    this.description,
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.textColor,
    required this.headingFont,
    required this.bodyFont,
    required this.headingSize,
    required this.bodySize,
    required this.sectionSpacing,
    required this.containerPadding,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ThemePreset.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, double fallback) {
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    int parseColor(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return fallback;
        final parsed = int.tryParse(trimmed);
        if (parsed != null) return parsed;
        final hex = trimmed.replaceAll('#', '');
        final hexValue = int.tryParse(hex, radix: 16);
        if (hexValue != null) {
          return hex.length <= 6 ? 0xFF000000 | hexValue : hexValue;
        }
      }
      return fallback;
    }

    DateTime parseDate(dynamic value, DateTime fallback) {
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.toUtc();
      }
      return fallback;
    }

    final now = DateTime.now().toUtc();

    return ThemePreset(
      id: (json['id'] ?? '').toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: (json['name'] ?? 'Preset sin título').toString(),
      description: json['description'] as String?,
      primaryColor: parseColor(json['primaryColor'], 0xFF2E7D32),
      accentColor: parseColor(json['accentColor'], 0xFFFF6F00),
      backgroundColor: parseColor(json['backgroundColor'], 0xFFFFFFFF),
      textColor: parseColor(json['textColor'], 0xFF212121),
      headingFont: (json['headingFont'] ?? 'Roboto').toString(),
      bodyFont: (json['bodyFont'] ?? 'Roboto').toString(),
      headingSize: parseDouble(json['headingSize'], 48.0),
      bodySize: parseDouble(json['bodySize'], 16.0),
      sectionSpacing: parseDouble(json['sectionSpacing'], 64.0),
      containerPadding: parseDouble(json['containerPadding'], 24.0),
      createdAt: parseDate(json['createdAt'], now),
      updatedAt: parseDate(json['updatedAt'], now),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'name': name,
      'description': description,
      'primaryColor': primaryColor,
      'accentColor': accentColor,
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'headingFont': headingFont,
      'bodyFont': bodyFont,
      'headingSize': headingSize,
      'bodySize': bodySize,
      'sectionSpacing': sectionSpacing,
      'containerPadding': containerPadding,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ThemePreset copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? description,
    int? primaryColor,
    int? accentColor,
    int? backgroundColor,
    int? textColor,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    double? sectionSpacing,
    double? containerPadding,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ThemePreset(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      description: description ?? this.description,
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      headingFont: headingFont ?? this.headingFont,
      bodyFont: bodyFont ?? this.bodyFont,
      headingSize: headingSize ?? this.headingSize,
      bodySize: bodySize ?? this.bodySize,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      containerPadding: containerPadding ?? this.containerPadding,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class WebsiteSetting {
  final String id;
  final String tenantId;
  final String key;
  final String? value;
  final String? description;
  final DateTime updatedAt;

  WebsiteSetting({
    required this.id,
    required this.tenantId,
    required this.key,
    this.value,
    this.description,
    required this.updatedAt,
  });

  factory WebsiteSetting.fromJson(Map<String, dynamic> json) {
    return WebsiteSetting(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      key: json['key'] as String,
      value: json['value'] as String?,
      description: json['description'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'key': key,
      'value': value,
      'description': description,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class OnlineOrder {
  final String id;
  final String tenantId;
  final String orderNumber;
  final String? customerId;
  final String customerEmail;
  final String customerName;
  final String? customerPhone;
  final String? customerAddress;

  final String deliveryType;
  final String? shippingAddressLine1;
  final String? shippingAddressLine2;
  final String? shippingCity;
  final String? shippingState;
  final String? shippingPostalCode;
  final String? shippingCountry;
  final String? shippingCarrier;
  final String? trackingUrl;

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
  final DateTime? readyForPickupAt;
  final DateTime? cancelledAt;
  final String? cancelledReason;

  final String? salesInvoiceId;

  final String? customerNotes;
  final String? internalNotes;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;

  final List<OnlineOrderItem> items;

  OnlineOrder({
    required this.id,
    required this.tenantId,
    required this.orderNumber,
    this.customerId,
    required this.customerEmail,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.deliveryType = 'shipping',
    this.shippingAddressLine1,
    this.shippingAddressLine2,
    this.shippingCity,
    this.shippingState,
    this.shippingPostalCode,
    this.shippingCountry,
    this.shippingCarrier,
    this.trackingUrl,
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
    this.readyForPickupAt,
    this.cancelledAt,
    this.cancelledReason,
    this.salesInvoiceId,
    this.customerNotes,
    this.internalNotes,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  factory OnlineOrder.fromJson(Map<String, dynamic> json) {
    return OnlineOrder(
      id: json['id'] as String,
      tenantId: json['tenant_id']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? 'N/A',
      customerId: json['customer_id'] as String?,
      customerEmail: json['customer_email']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? 'Cliente',
      customerPhone: json['customer_phone'] as String?,
      customerAddress: json['customer_address'] as String?,
      deliveryType: json['delivery_type']?.toString() ?? 'shipping',
      shippingAddressLine1: json['shipping_address_line1'] as String?,
      shippingAddressLine2: json['shipping_address_line2'] as String?,
      shippingCity: json['shipping_city'] as String?,
      shippingState: json['shipping_state'] as String?,
      shippingPostalCode: json['shipping_postal_code'] as String?,
      shippingCountry: json['shipping_country'] as String?,
      shippingCarrier: json['shipping_carrier'] as String?,
      trackingUrl: json['tracking_url'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      paymentMethod: json['payment_method'] as String?,
      paymentReference: json['payment_reference'] as String?,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      trackingNumber: json['tracking_number'] as String?,
      shippedAt: json['shipped_at'] != null
          ? DateTime.parse(json['shipped_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      readyForPickupAt: json['ready_for_pickup_at'] != null
          ? DateTime.parse(json['ready_for_pickup_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      cancelledReason: json['cancelled_reason'] as String?,
      salesInvoiceId: json['sales_invoice_id'] as String?,
      customerNotes: json['customer_notes'] as String?,
      internalNotes: json['internal_notes'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      items: (json['online_order_items'] as List<dynamic>?)
              ?.map((item) =>
                  OnlineOrderItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_email': customerEmail,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'delivery_type': deliveryType,
      'shipping_address_line1': shippingAddressLine1,
      'shipping_address_line2': shippingAddressLine2,
      'shipping_city': shippingCity,
      'shipping_state': shippingState,
      'shipping_postal_code': shippingPostalCode,
      'shipping_country': shippingCountry,
      'shipping_carrier': shippingCarrier,
      'tracking_url': trackingUrl,
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
      'ready_for_pickup_at': readyForPickupAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancelled_reason': cancelledReason,
      'sales_invoice_id': salesInvoiceId,
      'customer_notes': customerNotes,
      'internal_notes': internalNotes,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  OnlineOrder copyWith({
    String? id,
    String? tenantId,
    String? orderNumber,
    String? customerId,
    String? customerEmail,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? deliveryType,
    String? shippingAddressLine1,
    String? shippingAddressLine2,
    String? shippingCity,
    String? shippingState,
    String? shippingPostalCode,
    String? shippingCountry,
    String? shippingCarrier,
    String? trackingUrl,
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
    DateTime? readyForPickupAt,
    DateTime? cancelledAt,
    String? cancelledReason,
    String? salesInvoiceId,
    String? customerNotes,
    String? internalNotes,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<OnlineOrderItem>? items,
  }) {
    return OnlineOrder(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      orderNumber: orderNumber ?? this.orderNumber,
      customerId: customerId ?? this.customerId,
      customerEmail: customerEmail ?? this.customerEmail,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      deliveryType: deliveryType ?? this.deliveryType,
      shippingAddressLine1: shippingAddressLine1 ?? this.shippingAddressLine1,
      shippingAddressLine2: shippingAddressLine2 ?? this.shippingAddressLine2,
      shippingCity: shippingCity ?? this.shippingCity,
      shippingState: shippingState ?? this.shippingState,
      shippingPostalCode: shippingPostalCode ?? this.shippingPostalCode,
      shippingCountry: shippingCountry ?? this.shippingCountry,
      shippingCarrier: shippingCarrier ?? this.shippingCarrier,
      trackingUrl: trackingUrl ?? this.trackingUrl,
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
      readyForPickupAt: readyForPickupAt ?? this.readyForPickupAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledReason: cancelledReason ?? this.cancelledReason,
      salesInvoiceId: salesInvoiceId ?? this.salesInvoiceId,
      customerNotes: customerNotes ?? this.customerNotes,
      internalNotes: internalNotes ?? this.internalNotes,
      notes: notes ?? this.notes,
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
      case 'ready_for_pickup':
        return 'Listo para retiro';
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

  String get deliveryDisplayName {
    switch (deliveryType) {
      case 'pickup':
        return 'Retiro en tienda';
      case 'shipping':
        return 'Despacho';
      default:
        return deliveryType;
    }
  }

  String get shippingAddressDisplay {
    final parts = [
      shippingAddressLine1,
      shippingAddressLine2,
      shippingCity,
      shippingState,
      shippingCountry,
    ]
        .map((part) => part?.trim())
        .where((part) => part != null && part.isNotEmpty)
        .cast<String>()
        .toList();

    if (parts.isEmpty) {
      return customerAddress?.trim().isNotEmpty == true
          ? customerAddress!.trim()
          : 'Sin dirección registrada';
    }

    return parts.toSet().join(', ');
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
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      productId: json['product_id'] as String?,
      productName: json['product_name']?.toString() ?? 'Producto',
      productSku: json['product_sku'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
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
