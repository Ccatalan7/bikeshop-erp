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
  final String? brandId;
  final String? brand;
  final String? model;
  final Map<String, String> specifications;
  final String? supplierId;
  final String? supplierReference;
  final String? manufacturer;
  final String? manufacturerSku;
  final String? gtin;
  final String? hsCode;
  final String? countryOfOrigin;
  final String? color;
  final String? size;
  final String? material;
  final ProductDimensions? dimensions;
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
  final List<String> tags;
  final ProductUnit unit;
  final double weight; // in kg
  final bool trackStock;
  final bool isActive;
  final bool isPublished;
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
    this.brandId,
    this.brand,
    this.model,
    this.specifications = const {},
    this.supplierId,
    this.supplierReference,
    this.manufacturer,
    this.manufacturerSku,
    this.gtin,
    this.hsCode,
    this.countryOfOrigin,
    this.color,
    this.size,
    this.material,
    this.dimensions,
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
    this.tags = const [],
    this.unit = ProductUnit.unit,
    this.weight = 0.0,
    this.trackStock = true,
    this.isActive = true,
    this.isPublished = true,
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
      brandId: json['brand_id'] as String? ?? json['brandId'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      specifications:
          Map<String, String>.from(json['specifications'] as Map? ?? {}),
      supplierId: json['supplier_id'] as String?,
      supplierReference: json['supplier_reference'] as String?,
      manufacturer: json['manufacturer'] as String?,
      manufacturerSku: json['manufacturer_sku'] as String?,
      gtin: json['gtin'] as String?,
      hsCode: json['hs_code'] as String?,
      countryOfOrigin: json['country_of_origin'] as String?,
      color: json['color'] as String?,
      size: json['size'] as String?,
      material: json['material'] as String?,
      dimensions: ProductDimensions.fromJsonNullable(json['dimensions']),
      warrantyMonths: json['warranty_months'] as int? ?? 0,
      lifecycleStatus: json['lifecycle_status'] as String? ?? 'active',
      serialized: json['serialized'] as bool? ?? false,
      lotTracking: json['lot_tracking'] as bool? ?? false,
      expirationTracking: json['expiration_tracking'] as bool? ?? false,
      expiryDays: json['expiry_days'] as int?,
      leadTimeDays: json['lead_time_days'] as int? ?? 0,
      reorderQuantity: json['reorder_quantity'] as int? ?? 0,
      warehouseLocation: json['warehouse_location'] as String?,
      priceCurrency:
          (json['price_currency'] as String? ?? 'CLP').toString().toUpperCase(),
      costCurrency:
          (json['cost_currency'] as String? ?? 'CLP').toString().toUpperCase(),
      taxRate: (json['tax_rate'] as num?)?.toDouble(),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      unit: ProductUnit.values.firstWhere(
        (u) => u.name == json['unit'],
        orElse: () => ProductUnit.unit,
      ),
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      isPublished: json['is_published'] as bool? ??
          json['show_on_website'] as bool? ??
          (json['published'] as bool? ?? true),
      productType: ProductType.values.firstWhere(
        (t) => t.name == json['product_type'],
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
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
      'brand_id': brandId,
      'brand': brand,
      'model': model,
      'specifications': specifications,
      'supplier_id': supplierId,
      'supplier_reference': supplierReference,
      'manufacturer': manufacturer,
      'manufacturer_sku': manufacturerSku,
      'gtin': gtin,
      'hs_code': hsCode,
      'country_of_origin': countryOfOrigin,
      'color': color,
      'size': size,
      'material': material,
      'dimensions': dimensions?.toJson(),
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
      'tags': tags,
      'unit': unit.name,
      'weight': weight,
      'track_stock': trackStock,
      'is_active': isActive,
      'is_published': isPublished,
      'show_on_website': isPublished,
      'product_type': productType.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    json.removeWhere((_, value) => value == null);

    return json;
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
    String? brandId,
    bool brandIdHasValue = false,
    String? brand,
    bool brandHasValue = false,
    String? model,
    Map<String, String>? specifications,
    String? supplierId,
    String? supplierReference,
    String? manufacturer,
    String? manufacturerSku,
    String? gtin,
    String? hsCode,
    String? countryOfOrigin,
    String? color,
    String? size,
    String? material,
    ProductDimensions? dimensions,
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
    List<String>? tags,
    ProductUnit? unit,
    double? weight,
    bool? trackStock,
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
      brandId: (brandIdHasValue || brandId != null) ? brandId : this.brandId,
      brand: (brandHasValue || brand != null) ? brand : this.brand,
      model: model ?? this.model,
      specifications: specifications ?? this.specifications,
      supplierId: supplierId ?? this.supplierId,
      supplierReference: supplierReference ?? this.supplierReference,
      manufacturer: manufacturer ?? this.manufacturer,
      manufacturerSku: manufacturerSku ?? this.manufacturerSku,
      gtin: gtin ?? this.gtin,
      hsCode: hsCode ?? this.hsCode,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      color: color ?? this.color,
      size: size ?? this.size,
      material: material ?? this.material,
      dimensions: dimensions ?? this.dimensions,
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
      tags: tags ?? this.tags,
      unit: unit ?? this.unit,
      weight: weight ?? this.weight,
      trackStock: trackStock ?? this.trackStock,
      isActive: isActive ?? this.isActive,
      isPublished: isPublished ?? this.isPublished,
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

class ProductDimensions {
  final double? length;
  final double? width;
  final double? height;
  final String unit;

  const ProductDimensions({
    this.length,
    this.width,
    this.height,
    this.unit = 'cm',
  });

  factory ProductDimensions.fromJson(Map<String, dynamic> json) {
    return ProductDimensions(
      length: _toDouble(json['length']),
      width: _toDouble(json['width']),
      height: _toDouble(json['height']),
      unit: (json['unit'] as String? ?? 'cm').trim(),
    );
  }

  static ProductDimensions? fromJsonNullable(dynamic value) {
    if (value == null) return null;
    if (value is ProductDimensions) return value;
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.isEmpty) return null;
      final dims = ProductDimensions.fromJson(map);
      return dims.isEmpty ? null : dims;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'unit': unit};
    if (length != null) result['length'] = length;
    if (width != null) result['width'] = width;
    if (height != null) result['height'] = height;
    return result;
  }

  bool get isEmpty =>
      (length == null || length == 0) &&
      (width == null || width == 0) &&
      (height == null || height == 0);

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      final normalized = value
          .trim()
          .replaceAll(RegExp(r'[^0-9,.-]'), '')
          .replaceAll(',', '.');
      return double.tryParse(normalized);
    }
    return null;
  }
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
