class Product {
  final String id;
  final String name;
  final String sku; // Unique product identifier
  final String? barcode;
  final double price; // Sales price (without IVA)
  final double cost; // Purchase cost
  final int stockQuantity;
  final int minStockLevel;
  final int maxStockLevel;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? description;
  final ProductCategory category;
  final String? categoryId; // Custom category reference
  final String? categoryName; // Resolved category name (if available)
  final String? brand;
  final String? model;
  final Map<String, String> specifications;
  final List<String> tags;
  final ProductUnit unit;
  final double weight; // in kg
  final bool trackStock;
  final bool isActive;
  final ProductType productType; // Product or Service
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode,
    required this.price,
    required this.cost,
    required this.stockQuantity,
    this.minStockLevel = 5,
    this.maxStockLevel = 100,
    this.imageUrl,
    this.imageUrls = const [],
    this.description,
    required this.category,
    this.categoryId,
    this.categoryName,
    this.brand,
    this.model,
    this.specifications = const {},
    this.tags = const [],
    this.unit = ProductUnit.unit,
    this.weight = 0.0,
    this.trackStock = true,
    this.isActive = true,
    this.productType = ProductType.product,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String,
      barcode: json['barcode'] as String?,
      price: (json['price'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      minStockLevel: json['min_stock_level'] as int? ?? 5,
      maxStockLevel: json['max_stock_level'] as int? ?? 100,
      imageUrl: json['image_url'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? [],
      description: json['description'] as String?,
      category: ProductCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => ProductCategory.other,
      ),
      categoryId:
          json['category_id'] as String? ?? json['categoryId'] as String?,
      categoryName:
          json['category_name'] as String? ?? json['categoryName'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      specifications:
          Map<String, String>.from(json['specifications'] as Map? ?? {}),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      unit: ProductUnit.values.firstWhere(
        (u) => u.name == json['unit'],
        orElse: () => ProductUnit.unit,
      ),
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      productType: ProductType.values.firstWhere(
        (t) => t.name == json['product_type'],
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'price': price,
      'cost': cost,
      'stock_quantity': stockQuantity,
      'min_stock_level': minStockLevel,
      'max_stock_level': maxStockLevel,
      'image_url': imageUrl,
      'image_urls': imageUrls,
      'description': description,
      'category': category.name,
      'category_id': categoryId,
      'category_name': categoryName,
      'brand': brand,
      'model': model,
      'specifications': specifications,
      'tags': tags,
      'unit': unit.name,
      'weight': weight,
      'track_stock': trackStock,
      'is_active': isActive,
      'product_type': productType.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? barcode,
    double? price,
    double? cost,
    int? stockQuantity,
    int? minStockLevel,
    int? maxStockLevel,
    String? imageUrl,
    List<String>? imageUrls,
    String? description,
    ProductCategory? category,
    String? categoryId,
    String? categoryName,
    String? brand,
    String? model,
    Map<String, String>? specifications,
    List<String>? tags,
    ProductUnit? unit,
    double? weight,
    bool? trackStock,
    bool? isActive,
    ProductType? productType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      maxStockLevel: maxStockLevel ?? this.maxStockLevel,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      description: description ?? this.description,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      specifications: specifications ?? this.specifications,
      tags: tags ?? this.tags,
      unit: unit ?? this.unit,
      weight: weight ?? this.weight,
      trackStock: trackStock ?? this.trackStock,
      isActive: isActive ?? this.isActive,
      productType: productType ?? this.productType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Business logic methods
  double get priceWithIva => price * 1.19; // Chilean IVA is 19%

  double get marginPercent => price > 0 ? ((price - cost) / price) * 100 : 0;

  double get marginAmount => price - cost;

  bool get isLowStock => trackStock && stockQuantity <= minStockLevel;

  bool get isOverStock => trackStock && stockQuantity >= maxStockLevel;

  bool get isOutOfStock => trackStock && stockQuantity <= 0;

  StockStatus get stockStatus {
    if (!trackStock) return StockStatus.notTracked;
    if (stockQuantity <= 0) return StockStatus.outOfStock;
    if (stockQuantity <= minStockLevel) return StockStatus.lowStock;
    if (stockQuantity >= maxStockLevel) return StockStatus.overStock;
    return StockStatus.normal;
  }

  String get displayName => '$name${brand != null ? ' - $brand' : ''}';

  String get fullName =>
      '$name${brand != null ? ' $brand' : ''}${model != null ? ' $model' : ''}';

  @override
  String toString() {
    return 'Product(id: $id, name: $name, sku: $sku, price: \$${price.toStringAsFixed(2)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Product && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum ProductCategory {
  bicycles('Bicicletas'),
  parts('Repuestos'),
  accessories('Accesorios'),
  tools('Herramientas'),
  clothing('Ropa'),
  safety('Seguridad'),
  maintenance('Mantención'),
  electronics('Electrónicos'),
  services('Servicios'),
  other('Otros');

  const ProductCategory(this.displayName);
  final String displayName;
}

enum ProductUnit {
  unit('Unidad'),
  kg('Kilogramo'),
  gram('Gramo'),
  liter('Litro'),
  meter('Metro'),
  pair('Par'),
  set('Conjunto'),
  hour('Hora');

  const ProductUnit(this.displayName);
  final String displayName;
}

enum StockStatus {
  normal('Normal'),
  lowStock('Stock Bajo'),
  outOfStock('Sin Stock'),
  overStock('Sobre Stock'),
  notTracked('No Controlado');

  const StockStatus(this.displayName);
  final String displayName;
}

enum ProductType {
  product('Producto'),
  service('Servicio');

  const ProductType(this.displayName);
  final String displayName;
}

DateTime _parseDate(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  try {
    final dynamic dynamicValue = value;
    final result = dynamicValue.toDate();
    if (result is DateTime) {
      return result;
    }
  } catch (_) {
    // Ignore conversion errors and fallback below.
  }
  return DateTime.now();
}
