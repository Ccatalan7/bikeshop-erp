class Product {
  final String? id;
  final String name;
  final String sku;
  final String? description;
  final String? categoryId;
  final String? categoryName; // For display purposes, populated from JOIN
  final String? supplierId;
  final String? supplierName; // For display purposes, populated from JOIN
  final String? brand;
  final String? model;
  final double price;
  final double cost;
  final int inventoryQty;
  final int minStockLevel;
  final String? imageUrl;
  final List<String> additionalImages;
  final bool isActive;
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
    this.brand,
    this.model,
    required this.price,
    required this.cost,
    this.inventoryQty = 0,
    this.minStockLevel = 1,
    this.imageUrl,
    this.additionalImages = const [],
    this.isActive = true,
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
      brand: json['brand'],
      model: json['model'],
      price: (json['price'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      inventoryQty: json['inventory_qty'] ?? 0,
      minStockLevel: json['min_stock_level'] ?? 1,
      imageUrl: json['image_url'],
      additionalImages: json['additional_images'] != null
          ? List<String>.from(json['additional_images'])
          : [],
      isActive: json['is_active'] ?? true,
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
      'brand': brand,
      'model': model,
      'price': price,
      'cost': cost,
      'inventory_qty': inventoryQty,
      'min_stock_level': minStockLevel,
      'image_url': imageUrl,
      'additional_images': additionalImages,
      'is_active': isActive,
      'product_type': productType.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

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
    String? brand,
    String? model,
    double? price,
    double? cost,
    int? inventoryQty,
    int? minStockLevel,
    String? imageUrl,
    List<String>? additionalImages,
    bool? isActive,
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
      brand: brand ?? this.brand,
      model: model ?? this.model,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      inventoryQty: inventoryQty ?? this.inventoryQty,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      imageUrl: imageUrl ?? this.imageUrl,
      additionalImages: additionalImages ?? this.additionalImages,
      isActive: isActive ?? this.isActive,
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
