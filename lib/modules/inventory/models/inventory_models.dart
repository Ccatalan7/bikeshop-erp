import '../../../shared/models/product.dart'
    show ProductDimensions, PurchaseTreatment, parsePurchaseTreatment;

class Product {
  static const String listPreviewSelect =
      'id,tenant_id,name,sku,category_id,category_name,supplier_id,'
      'supplier_name,supplier_code,brand_id,brand,model,barcode,price,cost,'
      'inventory_qty,stock_quantity,min_stock_level,max_stock_level,'
      'image_url,image_url_optimized,image_fingerprint,image_urls,'
      'website_name,website_price,website_image_url,'
      'website_image_url_optimized,website_image_urls,'
      'website_seo_title,website_seo_description,website_search_terms,'
      'website_merchant_title,website_merchant_description,'
      'website_merchant_brand,website_merchant_gtin,'
      'website_merchant_mpn,website_google_product_category,'
      'warehouse_location,is_active,'
      'is_published,is_google_merchant,purchase_treatment,product_type,'
      'track_stock,is_set,set_type,parent_set_id,component_label,'
      'component_position,created_at,updated_at';

  final String? id;
  final String tenantId;
  final String name;
  final String sku;
  final String? description;
  final String? categoryId;
  final String? categoryName; // For display purposes, populated from JOIN
  final String? supplierId;
  final String? supplierName; // For display purposes, populated from JOIN
  final String? supplierReference;
  final String? supplierCode; // Código Proveedor
  final String? brandId;
  final String? brand;
  final String? model;
  final String? manufacturer;
  final String? manufacturerSku;
  final String? gtin;
  final String? barcode;
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
  final String?
      imageUrlOptimized; // WebP optimized version for fast web loading
  final Map<String, dynamic>? imageFingerprint;
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
  final String? websiteDescription; // Defines the description for the website
  final String? websiteName;
  final double? websitePrice;
  final String? websiteImageUrl;
  final String? websiteImageUrlOptimized;
  final List<String> websiteImageUrls;
  final String? websiteSeoTitle;
  final String? websiteSeoDescription;
  final List<String> websiteSearchTerms;
  final String? websiteMerchantTitle;
  final String? websiteMerchantDescription;
  final String? websiteMerchantBrand;
  final String? websiteMerchantGtin;
  final String? websiteMerchantMpn;
  final String? websiteGoogleProductCategory;
  final bool isGoogleMerchant;
  final PurchaseTreatment purchaseTreatment;
  final ProductType productType;
  // Set-related fields
  final bool isSet;
  final String? setType;
  final String? parentSetId;
  final String? componentLabel;
  final int? componentPosition;
  final bool? isPartial;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    this.id,
    required this.tenantId,
    required this.name,
    required this.sku,
    this.description,
    this.websiteDescription,
    this.categoryId,
    this.categoryName,
    this.supplierId,
    this.supplierName,
    this.supplierReference,
    this.supplierCode,
    this.brandId,
    this.brand,
    this.model,
    this.manufacturer,
    this.manufacturerSku,
    this.gtin,
    this.barcode,
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
    this.imageUrlOptimized,
    this.imageFingerprint,
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
    this.isGoogleMerchant = false,
    this.websiteName,
    this.websitePrice,
    this.websiteImageUrl,
    this.websiteImageUrlOptimized,
    this.websiteImageUrls = const [],
    this.websiteSeoTitle,
    this.websiteSeoDescription,
    this.websiteSearchTerms = const [],
    this.websiteMerchantTitle,
    this.websiteMerchantDescription,
    this.websiteMerchantBrand,
    this.websiteMerchantGtin,
    this.websiteMerchantMpn,
    this.websiteGoogleProductCategory,
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.productType = ProductType.product,
    this.isSet = false,
    this.setType,
    this.parentSetId,
    this.componentLabel,
    this.componentPosition,
    this.isPartial,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Returns true if this product is a service (doesn't track inventory)
  bool get isService => productType == ProductType.service;

  bool get isWorkshopConsumable =>
      purchaseTreatment == PurchaseTreatment.workshopConsumable;

  /// Returns true if this product tracks inventory
  bool get tracksInventory => !isService && !isWorkshopConsumable;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name'],
      sku: json['sku'],
      description: json['description'],
      websiteDescription: json['website_description'],
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'], // From JOIN query
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name'], // From trigger or JOIN query
      supplierReference: json['supplier_reference'],
      supplierCode: json['supplier_code'],
      brandId: json['brand_id']?.toString(),
      brand: json['brand'],
      model: json['model'],
      manufacturer: json['manufacturer'],
      manufacturerSku: json['manufacturer_sku'],
      gtin: json['gtin'],
      barcode: json['barcode'],
      hsCode: json['hs_code'],
      countryOfOrigin: json['country_of_origin'],
      color: json['color'],
      size: json['size'],
      material: json['material'],
      dimensions: ProductDimensions.fromJsonNullable(json['dimensions']),
      price: (json['price'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      inventoryQty:
          (json['stock_quantity'] ?? json['inventory_qty'] ?? 0) as int,
      minStockLevel: json['min_stock_level'] ?? 1,
      maxStockLevel: json['max_stock_level'],
      imageUrl: json['image_url'],
      imageUrlOptimized: json['image_url_optimized'],
      imageFingerprint: json['image_fingerprint'] != null
          ? Map<String, dynamic>.from(json['image_fingerprint'] as Map)
          : null,
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
      websiteName: json['website_name'],
      websitePrice: json['website_price'] is num
          ? (json['website_price'] as num).toDouble()
          : null,
      websiteImageUrl: json['website_image_url'],
      websiteImageUrlOptimized: json['website_image_url_optimized'],
      websiteImageUrls: json['website_image_urls'] != null
          ? List<String>.from(json['website_image_urls'])
          : const [],
      websiteSeoTitle: json['website_seo_title'],
      websiteSeoDescription: json['website_seo_description'],
      websiteSearchTerms: json['website_search_terms'] != null
          ? List<String>.from(json['website_search_terms'])
          : const [],
      websiteMerchantTitle: json['website_merchant_title'],
      websiteMerchantDescription: json['website_merchant_description'],
      websiteMerchantBrand: json['website_merchant_brand'],
      websiteMerchantGtin: json['website_merchant_gtin'],
      websiteMerchantMpn: json['website_merchant_mpn'],
      websiteGoogleProductCategory: json['website_google_product_category'],
      isGoogleMerchant: json['is_google_merchant'] ?? false,
      purchaseTreatment: parsePurchaseTreatment(
        json['purchase_treatment'],
        productType: json['product_type']?.toString(),
        trackStock: json['track_stock'] as bool?,
      ),
      productType: _parseProductType(json['product_type']),
      isSet: json['is_set'] ?? false,
      setType: json['set_type'],
      parentSetId: json['parent_set_id']?.toString(),
      componentLabel: json['component_label'],
      componentPosition: json['component_position'],
      isPartial: json['is_partial'],
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : (json['created_at'] is String
              ? DateTime.parse(json['created_at'])
              : (json['created_at'] as dynamic).toDate()),
      updatedAt: json['updated_at'] == null
          ? DateTime.now()
          : (json['updated_at'] is String
              ? DateTime.parse(json['updated_at'])
              : (json['updated_at'] as dynamic).toDate()),
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

  Map<String, dynamic> toJson({bool includeNulls = false}) {
    final json = {
      'tenant_id': tenantId,
      'name': name,
      'sku': sku,
      'description': description,
      'website_description': websiteDescription,
      'category_id': categoryId,
      'supplier_id': supplierId,
      'supplier_reference': supplierReference,
      'supplier_code': supplierCode,
      'brand_id': brandId,
      'brand': brand,
      'model': model,
      'manufacturer': manufacturer,
      'manufacturer_sku': manufacturerSku,
      'gtin': gtin,
      'barcode': barcode,
      'hs_code': hsCode,
      'country_of_origin': countryOfOrigin,
      'color': color,
      'size': size,
      'material': material,
      'dimensions': dimensions?.toJson() ?? const <String, dynamic>{},
      'price': price,
      'cost': cost,
      'inventory_qty': tracksInventory ? inventoryQty : 0,
      'stock_quantity': tracksInventory ? inventoryQty : 0,
      'min_stock_level': minStockLevel,
      'max_stock_level': maxStockLevel,
      'image_url': imageUrl,
      'image_url_optimized': imageUrlOptimized,
      'image_fingerprint': imageFingerprint,
      'image_urls': additionalImages,
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
      'website_name': websiteName,
      'website_price': websitePrice,
      'website_image_url': websiteImageUrl,
      'website_image_url_optimized': websiteImageUrlOptimized,
      'website_image_urls': websiteImageUrls,
      'website_seo_title': websiteSeoTitle,
      'website_seo_description': websiteSeoDescription,
      'website_search_terms': websiteSearchTerms,
      'website_merchant_title': websiteMerchantTitle,
      'website_merchant_description': websiteMerchantDescription,
      'website_merchant_brand': websiteMerchantBrand,
      'website_merchant_gtin': websiteMerchantGtin,
      'website_merchant_mpn': websiteMerchantMpn,
      'website_google_product_category': websiteGoogleProductCategory,
      'is_google_merchant': isGoogleMerchant,
      'show_on_website': isPublished,
      'purchase_treatment': purchaseTreatment.dbValue,
      'product_type': productType.name,
      'is_service': isService, // Computed from product_type for DB triggers
      'track_stock': tracksInventory, // Services don't track stock
      // Set-related fields
      'is_set': isSet,
      'set_type': setType,
      'parent_set_id': parentSetId,
      'component_label': componentLabel,
      'component_position': componentPosition,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    if (!includeNulls) {
      json.removeWhere((_, value) => value == null);
    }

    // Only include id if it's not null (for updates)
    if (id != null) {
      json['id'] = id;
    }

    return json;
  }

  Product copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? sku,
    String? description,
    String? websiteDescription,
    bool websiteDescriptionHasValue = false,
    String? categoryId,
    String? categoryName,
    String? supplierId,
    String? supplierName,
    String? supplierReference,
    String? supplierCode,
    String? brandId,
    bool brandIdHasValue = false,
    String? brand,
    bool brandHasValue = false,
    String? model,
    String? manufacturer,
    String? manufacturerSku,
    String? gtin,
    bool gtinHasValue = false,
    String? barcode,
    bool barcodeHasValue = false,
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
    bool imageUrlHasValue = false,
    String? imageUrlOptimized,
    bool imageUrlOptimizedHasValue = false,
    Map<String, dynamic>? imageFingerprint,
    bool imageFingerprintHasValue = false,
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
    String? websiteName,
    bool websiteNameHasValue = false,
    double? websitePrice,
    bool websitePriceHasValue = false,
    String? websiteImageUrl,
    bool websiteImageUrlHasValue = false,
    String? websiteImageUrlOptimized,
    bool websiteImageUrlOptimizedHasValue = false,
    List<String>? websiteImageUrls,
    String? websiteSeoTitle,
    bool websiteSeoTitleHasValue = false,
    String? websiteSeoDescription,
    bool websiteSeoDescriptionHasValue = false,
    List<String>? websiteSearchTerms,
    String? websiteMerchantTitle,
    bool websiteMerchantTitleHasValue = false,
    String? websiteMerchantDescription,
    bool websiteMerchantDescriptionHasValue = false,
    String? websiteMerchantBrand,
    bool websiteMerchantBrandHasValue = false,
    String? websiteMerchantGtin,
    bool websiteMerchantGtinHasValue = false,
    String? websiteMerchantMpn,
    bool websiteMerchantMpnHasValue = false,
    String? websiteGoogleProductCategory,
    bool websiteGoogleProductCategoryHasValue = false,
    bool? isGoogleMerchant,
    PurchaseTreatment? purchaseTreatment,
    ProductType? productType,
    bool? isSet,
    String? setType,
    String? parentSetId,
    String? componentLabel,
    int? componentPosition,
    bool? isPartial,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      description: description ?? this.description,
      websiteDescription:
          (websiteDescriptionHasValue || websiteDescription != null)
              ? websiteDescription
              : this.websiteDescription,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierReference: supplierReference ?? this.supplierReference,
      supplierCode: supplierCode ?? this.supplierCode,
      brandId: (brandIdHasValue || brandId != null) ? brandId : this.brandId,
      brand: (brandHasValue || brand != null) ? brand : this.brand,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      manufacturerSku: manufacturerSku ?? this.manufacturerSku,
      gtin: (gtinHasValue || gtin != null) ? gtin : this.gtin,
      barcode: (barcodeHasValue || barcode != null) ? barcode : this.barcode,
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
      imageUrl:
          (imageUrlHasValue || imageUrl != null) ? imageUrl : this.imageUrl,
      imageUrlOptimized:
          (imageUrlOptimizedHasValue || imageUrlOptimized != null)
              ? imageUrlOptimized
              : this.imageUrlOptimized,
      imageFingerprint: (imageFingerprintHasValue || imageFingerprint != null)
          ? imageFingerprint
          : this.imageFingerprint,
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
      websiteName: (websiteNameHasValue || websiteName != null)
          ? websiteName
          : this.websiteName,
      websitePrice: (websitePriceHasValue || websitePrice != null)
          ? websitePrice
          : this.websitePrice,
      websiteImageUrl: (websiteImageUrlHasValue || websiteImageUrl != null)
          ? websiteImageUrl
          : this.websiteImageUrl,
      websiteImageUrlOptimized:
          (websiteImageUrlOptimizedHasValue || websiteImageUrlOptimized != null)
              ? websiteImageUrlOptimized
              : this.websiteImageUrlOptimized,
      websiteImageUrls: websiteImageUrls ?? this.websiteImageUrls,
      websiteSeoTitle: (websiteSeoTitleHasValue || websiteSeoTitle != null)
          ? websiteSeoTitle
          : this.websiteSeoTitle,
      websiteSeoDescription:
          (websiteSeoDescriptionHasValue || websiteSeoDescription != null)
              ? websiteSeoDescription
              : this.websiteSeoDescription,
      websiteSearchTerms: websiteSearchTerms ?? this.websiteSearchTerms,
      websiteMerchantTitle:
          (websiteMerchantTitleHasValue || websiteMerchantTitle != null)
              ? websiteMerchantTitle
              : this.websiteMerchantTitle,
      websiteMerchantDescription: (websiteMerchantDescriptionHasValue ||
              websiteMerchantDescription != null)
          ? websiteMerchantDescription
          : this.websiteMerchantDescription,
      websiteMerchantBrand:
          (websiteMerchantBrandHasValue || websiteMerchantBrand != null)
              ? websiteMerchantBrand
              : this.websiteMerchantBrand,
      websiteMerchantGtin:
          (websiteMerchantGtinHasValue || websiteMerchantGtin != null)
              ? websiteMerchantGtin
              : this.websiteMerchantGtin,
      websiteMerchantMpn:
          (websiteMerchantMpnHasValue || websiteMerchantMpn != null)
              ? websiteMerchantMpn
              : this.websiteMerchantMpn,
      websiteGoogleProductCategory: (websiteGoogleProductCategoryHasValue ||
              websiteGoogleProductCategory != null)
          ? websiteGoogleProductCategory
          : this.websiteGoogleProductCategory,
      isGoogleMerchant: isGoogleMerchant ?? this.isGoogleMerchant,
      purchaseTreatment: purchaseTreatment ?? this.purchaseTreatment,
      productType: productType ?? this.productType,
      isSet: isSet ?? this.isSet,
      setType: setType ?? this.setType,
      parentSetId: parentSetId ?? this.parentSetId,
      componentLabel: componentLabel ?? this.componentLabel,
      componentPosition: componentPosition ?? this.componentPosition,
      isPartial: isPartial ?? this.isPartial,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isLowStock => inventoryQty <= minStockLevel;
  bool get isOutOfStock => inventoryQty <= 0;

  /// Returns true if this product is a component of a set (has a parent set)
  bool get isSetComponent => parentSetId != null && parentSetId!.isNotEmpty;

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
  final String tenantId;
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
    required this.tenantId,
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
      tenantId: json['tenant_id']?.toString() ?? '',
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
      'tenant_id': tenantId,
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
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String name;
  final String? description;
  final String? address;
  final bool isActive;
  final bool isDefault;
  final DateTime createdAt;

  Warehouse({
    this.id,
    required this.tenantId,
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
      tenantId: json['tenant_id']?.toString() ?? '',
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
      'tenant_id': tenantId,
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

enum ProductSortOption {
  createdAtDesc('Más recientes'),
  createdAtAsc('Más antiguos'),
  nameAsc('Nombre A-Z'),
  nameDesc('Nombre Z-A'),
  skuAsc('SKU A-Z'),
  skuDesc('SKU Z-A'),
  priceDesc('Precio: Mayor a menor'),
  priceAsc('Precio: Menor a mayor'),
  stockDesc('Stock: Mayor a menor'),
  stockAsc('Stock: Menor a mayor');

  final String label;
  const ProductSortOption(this.label);
}
