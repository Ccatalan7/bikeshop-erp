import '../../../shared/models/product.dart' show ProductDimensions;

class Product {
  final String? id;
  final String name;
  final String sku;
  final String? description;
  final String? categoryId;
  final String? categoryName; // For display purposes, populated from JOIN
  final String? supplierId;
  final String? supplierName; // For display purposes, populated from JOIN
  final String? supplierReference;
  final String? brand;
  final String? model;
  final String? manufacturer;
  final String? manufacturerSku;
  final String? gtin;
  final String? hsCode;
  final String? countryOfOrigin;
  final String? color;
  final String? size;
  final String? material;
  final ProductDimensions? dimensions;
  final double price;
  final double cost;
  final int inventoryQty;
  final int minStockLevel;
  final int? maxStockLevel;
  final String? imageUrl;
  final List<String> additionalImages;
  final Map<String, String> specifications;
  final List<String> tags;
  final int warrantyMonths;
  final String lifecycleStatus;
  final bool serialized;
  final bool lotTracking;
  final bool expirationTracking;
  final int? expiryDays;
  final int leadTimeDays;
  final int reorderQuantity;
  final String? warehouseLocation;
  final String priceCurrency;
  final String costCurrency;
  final double? taxRate;
  final bool isActive;
  final bool isPublished;
  final ProductType productType;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    this.id,
    required this.name,
    required this.sku,
    this.description,
    this.categoryId,
    this.categoryName,
    this.supplierId,
    this.supplierName,
    this.supplierReference,
    this.brand,
    this.model,
    this.manufacturer,
    this.manufacturerSku,
    this.gtin,
    this.hsCode,
    this.countryOfOrigin,
    this.color,
    this.size,
    this.material,
    this.dimensions,
    required this.price,
    required this.cost,
    this.inventoryQty = 0,
    this.minStockLevel = 1,
    this.maxStockLevel,
    this.imageUrl,
    this.additionalImages = const [],
    this.specifications = const {},
    this.tags = const [],
    this.warrantyMonths = 0,
    this.lifecycleStatus = 'active',
    this.serialized = false,
    this.lotTracking = false,
    this.expirationTracking = false,
    this.expiryDays,
    this.leadTimeDays = 0,
    this.reorderQuantity = 0,
    this.warehouseLocation,
    this.priceCurrency = 'CLP',
    this.costCurrency = 'CLP',
    this.taxRate,
    this.isActive = true,
    this.isPublished = true,
    this.productType = ProductType.product,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString(),
      name: json['name'],
      sku: json['sku'],
      description: json['description'],
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'], // From JOIN query
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name'], // From trigger or JOIN query
      supplierReference: json['supplier_reference'],
      brand: json['brand'],
      model: json['model'],
      manufacturer: json['manufacturer'],
      manufacturerSku: json['manufacturer_sku'],
      gtin: json['gtin'],
      hsCode: json['hs_code'],
      countryOfOrigin: json['country_of_origin'],
      color: json['color'],
      size: json['size'],
      material: json['material'],
      dimensions: ProductDimensions.fromJsonNullable(json['dimensions']),
      price: (json['price'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      inventoryQty: json['inventory_qty'] ?? 0,
      minStockLevel: json['min_stock_level'] ?? 1,
      maxStockLevel: json['max_stock_level'],
      imageUrl: json['image_url'],
      additionalImages: json['additional_images'] != null
          ? List<String>.from(json['additional_images'])
          : (json['image_urls'] != null
              ? List<String>.from(json['image_urls'])
              : []),
      specifications:
          Map<String, String>.from(json['specifications'] as Map? ?? {}),
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : const [],
      warrantyMonths: json['warranty_months'] ?? 0,
      lifecycleStatus: json['lifecycle_status'] ?? 'active',
      serialized: json['serialized'] ?? false,
      lotTracking: json['lot_tracking'] ?? false,
      expirationTracking: json['expiration_tracking'] ?? false,
      expiryDays: json['expiry_days'],
      leadTimeDays: json['lead_time_days'] ?? 0,
      reorderQuantity: json['reorder_quantity'] ?? 0,
      warehouseLocation: json['warehouse_location'],
      priceCurrency: (json['price_currency'] ?? 'CLP').toString().toUpperCase(),
      costCurrency: (json['cost_currency'] ?? 'CLP').toString().toUpperCase(),
      taxRate:
          json['tax_rate'] is num ? (json['tax_rate'] as num).toDouble() : null,
      isActive: json['is_active'] ?? true,
      isPublished: json['is_published'] ??
          json['show_on_website'] ??
          json['published'] ??
          true,
      productType: _parseProductType(json['product_type']),
      createdAt: json['created_at'] is String
          ? DateTime.parse(json['created_at'])
          : (json['created_at'] as dynamic).toDate(),
      updatedAt: json['updated_at'] is String
          ? DateTime.parse(json['updated_at'])
          : (json['updated_at'] as dynamic).toDate(),
    );
  }

  static ProductType _parseProductType(dynamic value) {
    if (value == null) return ProductType.product;
    if (value is String) {
      return ProductType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ProductType.product,
      );
    }
    return ProductType.product;
  }

  Map<String, dynamic> toJson() {
    final json = {
      'name': name,
      'sku': sku,
      'description': description,
      'category_id': categoryId,
      'supplier_id': supplierId,
      'supplier_reference': supplierReference,
      'brand': brand,
      'model': model,
      'manufacturer': manufacturer,
      'manufacturer_sku': manufacturerSku,
      'gtin': gtin,
      'hs_code': hsCode,
      'country_of_origin': countryOfOrigin,
      'color': color,
      'size': size,
      'material': material,
      'dimensions': dimensions?.toJson(),
      'price': price,
      'cost': cost,
      'inventory_qty': inventoryQty,
      'stock_quantity': inventoryQty,
      'min_stock_level': minStockLevel,
      'max_stock_level': maxStockLevel,
      'image_url': imageUrl,
      'image_urls': additionalImages,
      'additional_images': additionalImages,
      'specifications': specifications,
      'tags': tags,
      'warranty_months': warrantyMonths,
      'lifecycle_status': lifecycleStatus,
      'serialized': serialized,
      'lot_tracking': lotTracking,
      'expiration_tracking': expirationTracking,
      'expiry_days': expiryDays,
      'lead_time_days': leadTimeDays,
      'reorder_quantity': reorderQuantity,
      'warehouse_location': warehouseLocation,
      'price_currency': priceCurrency,
      'cost_currency': costCurrency,
      'tax_rate': taxRate,
      'is_active': isActive,
      'is_published': isPublished,
      'show_on_website': isPublished,
      'product_type': productType.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    json.removeWhere((_, value) => value == null);

    // Only include id if it's not null (for updates)
    if (id != null) {
      json['id'] = id;
    }

    return json;
  }

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? description,
    String? categoryId,
    String? categoryName,
    String? supplierId,
    String? supplierName,
    String? supplierReference,
    String? brand,
    String? model,
    String? manufacturer,
    String? manufacturerSku,
    String? gtin,
    String? hsCode,
    String? countryOfOrigin,
    String? color,
    String? size,
    String? material,
    ProductDimensions? dimensions,
    double? price,
    double? cost,
    int? inventoryQty,
    int? minStockLevel,
    int? maxStockLevel,
    String? imageUrl,
    List<String>? additionalImages,
    Map<String, String>? specifications,
    List<String>? tags,
    int? warrantyMonths,
    String? lifecycleStatus,
    bool? serialized,
    bool? lotTracking,
    bool? expirationTracking,
    int? expiryDays,
    int? leadTimeDays,
    int? reorderQuantity,
    String? warehouseLocation,
    String? priceCurrency,
    String? costCurrency,
    double? taxRate,
    bool? isActive,
    bool? isPublished,
    ProductType? productType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierReference: supplierReference ?? this.supplierReference,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      manufacturerSku: manufacturerSku ?? this.manufacturerSku,
      gtin: gtin ?? this.gtin,
      hsCode: hsCode ?? this.hsCode,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      color: color ?? this.color,
      size: size ?? this.size,
      material: material ?? this.material,
      dimensions: dimensions ?? this.dimensions,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      inventoryQty: inventoryQty ?? this.inventoryQty,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      maxStockLevel: maxStockLevel ?? this.maxStockLevel,
      imageUrl: imageUrl ?? this.imageUrl,
      additionalImages: additionalImages ?? this.additionalImages,
      specifications: specifications ?? this.specifications,
      tags: tags ?? this.tags,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      serialized: serialized ?? this.serialized,
      lotTracking: lotTracking ?? this.lotTracking,
      expirationTracking: expirationTracking ?? this.expirationTracking,
      expiryDays: expiryDays ?? this.expiryDays,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      reorderQuantity: reorderQuantity ?? this.reorderQuantity,
      warehouseLocation: warehouseLocation ?? this.warehouseLocation,
      priceCurrency: priceCurrency ?? this.priceCurrency,
      costCurrency: costCurrency ?? this.costCurrency,
      taxRate: taxRate ?? this.taxRate,
      isActive: isActive ?? this.isActive,
      isPublished: isPublished ?? this.isPublished,
      productType: productType ?? this.productType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isLowStock => inventoryQty <= minStockLevel;
  bool get isOutOfStock => inventoryQty <= 0;

  double get marginAmount => price - cost;
  double get marginPercentage => cost > 0 ? (marginAmount / cost) * 100 : 0;

  double get inventoryValue => cost * inventoryQty;
}

enum ProductCategory {
  bicycle,
  parts,
  accessories,
  clothing,
  tools,
  maintenance,
  other,
}

class StockMovement {
  final String? id;
  final String productId;
  final String? productName;
  final String? productSku;
  final int quantity;
  final StockMovementType type;
  final String? reference;
  final String? notes;
  final double? unitCost;
  final DateTime date;
  final int? userId;
  final String? userName;

  StockMovement({
    this.id,
    required this.productId,
    this.productName,
    this.productSku,
    required this.quantity,
    required this.type,
    this.reference,
    this.notes,
    this.unitCost,
    DateTime? date,
    this.userId,
    this.userName,
  }) : date = date ?? DateTime.now();

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id'],
      productId: json['product_id'],
      productName: json['product_name'],
      productSku: json['product_sku'],
      quantity: json['quantity'],
      type: StockMovementType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      reference: json['reference'],
      notes: json['notes'],
      unitCost: json['unit_cost']?.toDouble(),
      date: DateTime.parse(json['date']),
      userId: json['user_id'],
      userName: json['user_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'quantity': quantity,
      'type': type.toString().split('.').last,
      'reference': reference,
      'notes': notes,
      'unit_cost': unitCost,
      'date': date.toIso8601String(),
      'user_id': userId,
    };
  }
}

enum StockMovementType {
  purchase, // Compra (entrada)
  sale, // Venta (salida)
  adjustment, // Ajuste manual
  transfer, // Transferencia
  return_in, // Devolución entrada
  return_out, // Devolución salida
  damaged, // Producto dañado
  lost, // Producto perdido
}

class Warehouse {
  final int? id;
  final String name;
  final String? description;
  final String? address;
  final bool isActive;
  final bool isDefault;
  final DateTime createdAt;

  Warehouse({
    this.id,
    required this.name,
    this.description,
    this.address,
    this.isActive = true,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      address: json['address'],
      isActive: json['is_active'] ?? true,
      isDefault: json['is_default'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'address': address,
      'is_active': isActive,
      'is_default': isDefault,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ProductStock {
  final int productId;
  final int warehouseId;
  final int quantity;
  final String? productName;
  final String? warehouseName;

  ProductStock({
    required this.productId,
    required this.warehouseId,
    required this.quantity,
    this.productName,
    this.warehouseName,
  });

  factory ProductStock.fromJson(Map<String, dynamic> json) {
    return ProductStock(
      productId: json['product_id'],
      warehouseId: json['warehouse_id'],
      quantity: json['quantity'],
      productName: json['product_name'],
      warehouseName: json['warehouse_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'warehouse_id': warehouseId,
      'quantity': quantity,
    };
  }
}

enum ProductType {
  product('Producto'),
  service('Servicio');

  const ProductType(this.displayName);
  final String displayName;
}
