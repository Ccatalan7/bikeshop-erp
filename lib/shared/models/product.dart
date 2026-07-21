class Product {
  // Shared preview payload for ERP/POS card/list surfaces.
  static const String listPreviewSelect =
      'id,name,sku,barcode,price,cost,inventory_qty,stock_quantity,'
      'min_stock_level,max_stock_level,image_url,image_url_optimized,'
      'category,category_id,category_name,brand_id,brand,model,'
      'supplier_id,supplier_name,supplier_code,'
      'purchase_treatment,product_type,parent_set_id,'
      'track_stock,is_active,is_published,'
      'created_at,updated_at';

  // Shared preview payload for storefront/product-card surfaces.
  static const String storefrontPreviewSelect =
      'id,name,sku,barcode,price,inventory_qty,stock_quantity,'
      'image_url,image_url_optimized,image_urls,description,'
      'website_description,website_name,website_price,website_image_url,'
      'website_image_url_optimized,website_image_urls,'
      'website_seo_title,website_seo_description,website_search_terms,'
      'website_merchant_title,website_merchant_description,'
      'website_merchant_brand,website_merchant_gtin,'
      'website_merchant_mpn,website_google_product_category,'
      'category,category_id,category_name,brand_id,brand,'
      'model,manufacturer,manufacturer_sku,gtin,color,size,material,weight,'
      'specifications,product_type,track_stock,tax_rate,'
      'is_active,is_published,show_on_website,created_at,updated_at';

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
  final String?
      imageUrlOptimized; // WebP optimized version for fast web loading
  final List<String> imageUrls;
  final String? description;
  final String? websiteDescription;
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
  final ProductCategory category;
  final String? categoryId; // Custom category reference
  final String? categoryName; // Resolved category name (if available)
  final String? brandId;
  final String? brand;
  final String? model;
  final Map<String, String> specifications;
  final String? supplierId;
  final String? supplierName; // Denormalized supplier name
  final String? supplierReference;
  final String? supplierCode; // Código Proveedor
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
  final PurchaseTreatment purchaseTreatment;
  final ProductType productType; // Product or Service
  final DateTime createdAt;
  final DateTime updatedAt;

  // SET FIELDS - For product sets (juegos) like front/rear hub pairs
  final bool isSet; // True if this is a parent set product
  final SetType? setType; // Type hint: pair, front_rear, left_right, custom
  final String? parentSetId; // If component, references parent set
  final String? componentLabel; // For components: "Delantero", "Trasero"
  final int? componentPosition; // For ordering components
  final List<SetComponent>?
      setComponents; // For sets: linked components with stock
  final int? fullSetsAvailable; // For sets: max complete sets from stock
  final bool? isPartial; // For sets: true if some components missing

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
    this.imageUrlOptimized,
    this.imageUrls = const [],
    this.description,
    this.websiteDescription,
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
    required this.category,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brand,
    this.model,
    this.specifications = const {},
    this.supplierId,
    this.supplierName,
    this.supplierReference,
    this.supplierCode,
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
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.productType = ProductType.product,
    required this.createdAt,
    required this.updatedAt,
    // Set fields
    this.isSet = false,
    this.setType,
    this.parentSetId,
    this.componentLabel,
    this.componentPosition,
    this.setComponents,
    this.fullSetsAvailable,
    this.isPartial,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final inventoryQty = json['inventory_qty'] as int?;
    final stockQty = json['stock_quantity'] as int?;
    final websiteName = _emptyToNull(json['website_name']);
    final websitePrice = (json['website_price'] as num?)?.toDouble();
    final websiteImageUrl = _emptyToNull(json['website_image_url']);
    final websiteImageUrlOptimized =
        _emptyToNull(json['website_image_url_optimized']);
    final websiteImageUrls =
        (json['website_image_urls'] as List?)?.cast<String>() ?? const [];
    final websiteSearchTerms =
        (json['website_search_terms'] as List?)?.cast<String>() ?? const [];
    final baseImageUrls = (json['image_urls'] as List?)?.cast<String>() ?? [];

    return Product(
      id: json['id'] as String,
      name: websiteName ?? json['name'] as String,
      sku: json['sku'] as String,
      barcode: json['barcode'] as String?,
      price: websitePrice ?? (json['price'] as num).toDouble(),
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      // stock_quantity is the canonical sellable balance. Falling back is only
      // for old payloads that do not include the current column; taking the
      // maximum would advertise stock when the canonical balance is zero.
      stockQuantity: stockQty ?? inventoryQty ?? 0,
      minStockLevel: json['min_stock_level'] as int? ?? 5,
      maxStockLevel: json['max_stock_level'] as int? ?? 100,
      imageUrl: websiteImageUrl ?? json['image_url'] as String?,
      imageUrlOptimized:
          websiteImageUrlOptimized ?? json['image_url_optimized'] as String?,
      imageUrls: websiteImageUrls.isNotEmpty ? websiteImageUrls : baseImageUrls,
      description: json['description'] as String?,
      websiteDescription: json['website_description'] as String?,
      websiteName: websiteName,
      websitePrice: websitePrice,
      websiteImageUrl: websiteImageUrl,
      websiteImageUrlOptimized: websiteImageUrlOptimized,
      websiteImageUrls: websiteImageUrls,
      websiteSeoTitle: _emptyToNull(json['website_seo_title']),
      websiteSeoDescription: _emptyToNull(json['website_seo_description']),
      websiteSearchTerms: websiteSearchTerms,
      websiteMerchantTitle: _emptyToNull(json['website_merchant_title']),
      websiteMerchantDescription:
          _emptyToNull(json['website_merchant_description']),
      websiteMerchantBrand: _emptyToNull(json['website_merchant_brand']),
      websiteMerchantGtin: _emptyToNull(json['website_merchant_gtin']),
      websiteMerchantMpn: _emptyToNull(json['website_merchant_mpn']),
      websiteGoogleProductCategory:
          _emptyToNull(json['website_google_product_category']),
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
      specifications: (json['specifications'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ) ??
          const {},
      supplierId: json['supplier_id'] as String?,
      supplierName: json['supplier_name'] as String?,
      supplierReference: json['supplier_reference'] as String?,
      supplierCode: json['supplier_code'] as String?,
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
      purchaseTreatment: parsePurchaseTreatment(
        json['purchase_treatment'],
        productType: json['product_type']?.toString(),
        trackStock: json['track_stock'] as bool?,
      ),
      productType: ProductType.values.firstWhere(
        (t) => t.name == json['product_type'],
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      // Set fields
      isSet: json['is_set'] as bool? ?? false,
      setType: _parseSetType(json['set_type']),
      parentSetId: json['parent_set_id'] as String?,
      componentLabel: json['component_label'] as String?,
      componentPosition: json['component_position'] as int?,
      setComponents: _parseSetComponents(json['set_components']),
      fullSetsAvailable: json['full_sets_available'] as int?,
      isPartial: json['is_partial'] as bool?,
    );
  }

  static SetType? _parseSetType(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    return SetType.values.firstWhere(
      (t) => t.name == str,
      orElse: () => SetType.custom,
    );
  }

  static List<SetComponent>? _parseSetComponents(dynamic value) {
    if (value == null) return null;
    if (value is! List) return null;
    return value
        .map((e) => SetComponent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'price': price,
      'cost': cost,
      'inventory_qty': stockQuantity,
      'stock_quantity': stockQuantity,
      'min_stock_level': minStockLevel,
      'max_stock_level': maxStockLevel,
      'image_url': imageUrl,
      'image_url_optimized': imageUrlOptimized,
      'image_urls': imageUrls,
      'description': description,
      'website_description': websiteDescription,
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
      'category': category.name,
      'category_id': categoryId,
      'category_name': categoryName,
      'brand_id': brandId,
      'brand': brand,
      'model': model,
      'specifications': specifications,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'supplier_reference': supplierReference,
      'supplier_code': supplierCode,
      'manufacturer': manufacturer,
      'manufacturer_sku': manufacturerSku,
      'gtin': gtin,
      'hs_code': hsCode,
      'country_of_origin': countryOfOrigin,
      'color': color,
      'size': size,
      'material': material,
      'dimensions': dimensions?.toJson() ?? const <String, dynamic>{},
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
      'track_stock': !isService &&
          purchaseTreatment == PurchaseTreatment.inventory &&
          trackStock,
      'is_active': isActive,
      'is_published': isPublished,
      'show_on_website': isPublished,
      'purchase_treatment': purchaseTreatment.dbValue,
      'product_type': productType.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // Set fields
      'is_set': isSet,
      'set_type': setType?.name,
      'parent_set_id': parentSetId,
      'component_label': componentLabel,
      'component_position': componentPosition,
    };

    json.removeWhere((_, value) => value == null);

    return json;
  }

  Product copyWith({
    String? id,
    String? name,
    String? sku,
    String? barcode,
    bool barcodeHasValue = false,
    double? price,
    double? cost,
    int? stockQuantity,
    int? minStockLevel,
    int? maxStockLevel,
    String? imageUrl,
    String? imageUrlOptimized,
    List<String>? imageUrls,
    String? description,
    String? websiteDescription,
    bool websiteDescriptionHasValue = false,
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
    String? supplierName,
    String? supplierReference,
    String? supplierCode,
    String? manufacturer,
    String? manufacturerSku,
    String? gtin,
    bool gtinHasValue = false,
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
    PurchaseTreatment? purchaseTreatment,
    ProductType? productType,
    DateTime? createdAt,
    DateTime? updatedAt,
    // Set fields
    bool? isSet,
    SetType? setType,
    String? parentSetId,
    String? componentLabel,
    int? componentPosition,
    List<SetComponent>? setComponents,
    int? fullSetsAvailable,
    bool? isPartial,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: (barcodeHasValue || barcode != null) ? barcode : this.barcode,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minStockLevel: minStockLevel ?? this.minStockLevel,
      maxStockLevel: maxStockLevel ?? this.maxStockLevel,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrlOptimized: imageUrlOptimized ?? this.imageUrlOptimized,
      imageUrls: imageUrls ?? this.imageUrls,
      description: description ?? this.description,
      websiteDescription:
          (websiteDescriptionHasValue || websiteDescription != null)
              ? websiteDescription
              : this.websiteDescription,
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
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      brandId: (brandIdHasValue || brandId != null) ? brandId : this.brandId,
      brand: (brandHasValue || brand != null) ? brand : this.brand,
      model: model ?? this.model,
      specifications: specifications ?? this.specifications,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierReference: supplierReference ?? this.supplierReference,
      supplierCode: supplierCode ?? this.supplierCode,
      manufacturer: manufacturer ?? this.manufacturer,
      manufacturerSku: manufacturerSku ?? this.manufacturerSku,
      gtin: (gtinHasValue || gtin != null) ? gtin : this.gtin,
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
      purchaseTreatment: purchaseTreatment ?? this.purchaseTreatment,
      productType: productType ?? this.productType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // Set fields
      isSet: isSet ?? this.isSet,
      setType: setType ?? this.setType,
      parentSetId: parentSetId ?? this.parentSetId,
      componentLabel: componentLabel ?? this.componentLabel,
      componentPosition: componentPosition ?? this.componentPosition,
      setComponents: setComponents ?? this.setComponents,
      fullSetsAvailable: fullSetsAvailable ?? this.fullSetsAvailable,
      isPartial: isPartial ?? this.isPartial,
    );
  }

  // Business logic methods
  double get priceWithIva => price * 1.19; // Chilean IVA is 19%

  double get marginPercent => price > 0 ? ((price - cost) / price) * 100 : 0;

  double get marginAmount => price - cost;

  /// Returns true if this product is a service (doesn't track inventory)
  bool get isService => productType == ProductType.service;

  bool get isWorkshopConsumable =>
      purchaseTreatment == PurchaseTreatment.workshopConsumable;

  /// Returns true if this product tracks inventory
  bool get tracksInventory => !isService && !isWorkshopConsumable && trackStock;

  bool get isLowStock => tracksInventory && stockQuantity <= minStockLevel;

  bool get isOverStock => tracksInventory && stockQuantity >= maxStockLevel;

  bool get isOutOfStock => tracksInventory && stockQuantity <= 0;

  StockStatus get stockStatus {
    if (isService || !trackStock) return StockStatus.notTracked;
    if (stockQuantity <= 0) return StockStatus.outOfStock;
    if (stockQuantity <= minStockLevel) return StockStatus.lowStock;
    if (stockQuantity >= maxStockLevel) return StockStatus.overStock;
    return StockStatus.normal;
  }

  String get displayName => '$name${brand != null ? ' - $brand' : ''}';

  String get fullName =>
      '$name${brand != null ? ' $brand' : ''}${model != null ? ' $model' : ''}';

  // SET-SPECIFIC COMPUTED PROPERTIES

  /// Returns true if this product is a component of a set
  bool get isComponent => parentSetId != null;

  /// Returns true if this set has some but not all components in stock
  bool get hasPartialStock => isSet && (isPartial ?? false);

  /// Returns true if all components have stock for at least one full set
  bool get hasFullSetStock => isSet && (fullSetsAvailable ?? 0) > 0;

  /// Display string for set stock status
  String get setStockStatusDisplay {
    if (!isSet) return '';
    if (hasPartialStock) return '🟡 Parcial';
    if (hasFullSetStock) return '🟢 Completo';
    return '🔴 Sin Stock';
  }

  /// Returns the number of components in this set
  int get componentCount => setComponents?.length ?? 0;

  /// Returns stock status for a set: e.g., "(2/2)" or "(1/2)"
  String get setComponentsStockDisplay {
    if (!isSet || setComponents == null) return '';
    final available = setComponents!.where((c) => c.hasStock).length;
    final total = setComponents!.length;
    return '($available/$total)';
  }

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

enum PurchaseTreatment {
  inventory('inventory', 'Inventario'),
  workshopConsumable('workshop_consumable', 'Consumible Taller');

  const PurchaseTreatment(this.dbValue, this.displayName);
  final String dbValue;
  final String displayName;
}

PurchaseTreatment parsePurchaseTreatment(
  dynamic value, {
  String? productType,
  bool? trackStock,
}) {
  if (value != null) {
    final raw = value.toString().trim();
    return PurchaseTreatment.values.firstWhere(
      (t) => t.name == raw || t.dbValue == raw,
      orElse: () => PurchaseTreatment.inventory,
    );
  }

  final isProduct =
      productType == null || productType == ProductType.product.name;
  if (isProduct && trackStock == false) {
    return PurchaseTreatment.workshopConsumable;
  }

  return PurchaseTreatment.inventory;
}

/// Type of product set for UI hints and auto-generation
enum SetType {
  pair('Par'), // Left + Right (pedals, grips)
  frontRear('Delantero/Trasero'), // Front + Rear (hubs, brakes, wheels)
  leftRight('Izquierdo/Derecho'), // Left + Right with different labels
  custom('Personalizado'); // User-defined components

  const SetType(this.displayName);
  final String displayName;

  /// Returns default component labels for this set type
  List<String> get defaultLabels {
    switch (this) {
      case SetType.pair:
        return ['Izquierdo', 'Derecho'];
      case SetType.frontRear:
        return ['Delantero', 'Trasero'];
      case SetType.leftRight:
        return ['Izquierdo', 'Derecho'];
      case SetType.custom:
        return ['Componente 1', 'Componente 2'];
    }
  }
}

/// Represents a component within a product set
class SetComponent {
  final String id;
  final String productId;
  final String productName;
  final String productSku;
  final String componentLabel; // "Delantero", "Trasero"
  final int position;
  final int quantityInSet;
  final int stockQuantity; // Current stock of this component
  final double? costRatio; // Ratio of set cost (e.g., 0.4 = 40%)
  final double? priceRatio; // Ratio of set price (e.g., 0.6 = 60%)

  const SetComponent({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.componentLabel,
    required this.position,
    this.quantityInSet = 1,
    required this.stockQuantity,
    this.costRatio,
    this.priceRatio,
  });

  factory SetComponent.fromJson(Map<String, dynamic> json) {
    return SetComponent(
      id: json['id'] as String? ?? '',
      productId: json['component_product_id'] as String? ??
          json['product_id'] as String? ??
          '',
      productName: json['component_name'] as String? ??
          json['product_name'] as String? ??
          '',
      productSku: json['component_sku'] as String? ??
          json['product_sku'] as String? ??
          '',
      componentLabel: json['component_label'] as String? ?? '',
      position:
          json['component_position'] as int? ?? json['position'] as int? ?? 0,
      quantityInSet: json['quantity_in_set'] as int? ?? 1,
      stockQuantity: json['stock_quantity'] as int? ?? 0,
      costRatio: (json['cost_ratio'] as num?)?.toDouble(),
      priceRatio: (json['price_ratio'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'component_product_id': productId,
      'component_name': productName,
      'component_sku': productSku,
      'component_label': componentLabel,
      'component_position': position,
      'quantity_in_set': quantityInSet,
      'stock_quantity': stockQuantity,
      'cost_ratio': costRatio,
      'price_ratio': priceRatio,
    };
  }

  /// Whether this component has sufficient stock for at least one set
  bool get hasStock => stockQuantity >= quantityInSet;

  /// Display string for stock status
  String get stockDisplay => '$stockQuantity ${hasStock ? '✓' : '✗'}';

  SetComponent copyWith({
    String? id,
    String? productId,
    String? productName,
    String? productSku,
    String? componentLabel,
    int? position,
    int? quantityInSet,
    int? stockQuantity,
    double? costRatio,
    double? priceRatio,
  }) {
    return SetComponent(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productSku: productSku ?? this.productSku,
      componentLabel: componentLabel ?? this.componentLabel,
      position: position ?? this.position,
      quantityInSet: quantityInSet ?? this.quantityInSet,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      costRatio: costRatio ?? this.costRatio,
      priceRatio: priceRatio ?? this.priceRatio,
    );
  }
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

String? _emptyToNull(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
