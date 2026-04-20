import 'dart:typed_data';

import 'inventory_models.dart';

enum BulkProductScopeSource {
  selected('Selección actual'),
  filtered('Lista filtrada'),
  all('Todo el inventario');

  const BulkProductScopeSource(this.label);
  final String label;
}

enum BulkProductEditOperation {
  classification('Clasificación'),
  channels('Canales y estado'),
  pricing('Precios y costos'),
  stock('Ajuste de stock'),
  images('Imágenes');

  const BulkProductEditOperation(this.label);
  final String label;
}

enum BulkFilterStockState {
  all('Todos'),
  inStock('Con stock'),
  lowStock('Stock bajo'),
  outOfStock('Sin stock');

  const BulkFilterStockState(this.label);
  final String label;
}

enum BulkToggleState {
  keep('Mantener'),
  enable('Activar'),
  disable('Desactivar');

  const BulkToggleState(this.label);
  final String label;
}

enum BulkNumericChangeMode {
  keep('Mantener'),
  set('Fijar valor'),
  increasePercent('Subir %'),
  decreasePercent('Bajar %'),
  increaseFixed('Sumar monto'),
  decreaseFixed('Restar monto');

  const BulkNumericChangeMode(this.label);
  final String label;
}

enum BulkStockEditMode {
  target('Fijar stock objetivo'),
  delta('Ajustar por diferencia');

  const BulkStockEditMode(this.label);
  final String label;
}

enum BulkStockDirection {
  inwards('IN', 'Entrada'),
  outwards('OUT', 'Salida');

  const BulkStockDirection(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

enum BulkPriceRounding {
  none('Sin redondeo'),
  nearest10('Múltiplo de 10'),
  nearest100('Múltiplo de 100');

  const BulkPriceRounding(this.label);
  final String label;
}

BulkProductScopeSource bulkProductScopeSourceFromValue(String? value) {
  return BulkProductScopeSource.values.firstWhere(
    (item) => item.name == value,
    orElse: () => BulkProductScopeSource.filtered,
  );
}

BulkProductEditOperation bulkProductEditOperationFromValue(String? value) {
  return BulkProductEditOperation.values.firstWhere(
    (item) => item.name == value,
    orElse: () => BulkProductEditOperation.classification,
  );
}

enum BulkUpdateItemStatus {
  updated('Actualizado'),
  skipped('Sin cambios'),
  failed('Con error');

  const BulkUpdateItemStatus(this.label);
  final String label;
}

BulkUpdateItemStatus bulkUpdateItemStatusFromValue(String? value) {
  return BulkUpdateItemStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => BulkUpdateItemStatus.updated,
  );
}

enum BulkProductEditHistoryStatus {
  completed('Completado'),
  partial('Parcial'),
  failed('Fallido'),
  skipped('Sin cambios');

  const BulkProductEditHistoryStatus(this.label);
  final String label;
}

BulkProductEditHistoryStatus bulkProductEditHistoryStatusFromValue(
  String? value,
) {
  return BulkProductEditHistoryStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => BulkProductEditHistoryStatus.completed,
  );
}

enum BulkProductEditHistoryOrigin {
  recorded('Registrado'),
  legacyInferred('Legado inferido');

  const BulkProductEditHistoryOrigin(this.label);
  final String label;
}

BulkProductEditHistoryOrigin bulkProductEditHistoryOriginFromValue(
  String? value,
) {
  return BulkProductEditHistoryOrigin.values.firstWhere(
    (item) => item.name == value,
    orElse: () => BulkProductEditHistoryOrigin.recorded,
  );
}

enum BulkLegacySessionKind {
  mass('Masiva'),
  singular('Singular');

  const BulkLegacySessionKind(this.label);
  final String label;
}

BulkLegacySessionKind bulkLegacySessionKindFromValue(String? value) {
  return BulkLegacySessionKind.values.firstWhere(
    (item) => item.name == value,
    orElse: () => BulkLegacySessionKind.mass,
  );
}

class BulkProductSmartFilters {
  const BulkProductSmartFilters({
    this.keyword = '',
    this.specQuery = '',
    this.categoryId,
    this.brandId,
    this.supplierId,
    this.productType,
    this.stockState = BulkFilterStockState.all,
    this.websiteState = BulkToggleState.keep,
    this.googleMerchantState = BulkToggleState.keep,
    this.activeState = BulkToggleState.keep,
    this.onlyMissingCategory = false,
    this.onlyMissingBrand = false,
    this.onlyMissingImage = false,
  });

  final String keyword;
  final String specQuery;
  final String? categoryId;
  final String? brandId;
  final String? supplierId;
  final ProductType? productType;
  final BulkFilterStockState stockState;
  final BulkToggleState websiteState;
  final BulkToggleState googleMerchantState;
  final BulkToggleState activeState;
  final bool onlyMissingCategory;
  final bool onlyMissingBrand;
  final bool onlyMissingImage;

  bool get hasSpecQuery => specQuery.trim().isNotEmpty;

  bool get hasAnyFilter =>
      keyword.trim().isNotEmpty ||
      specQuery.trim().isNotEmpty ||
      categoryId != null ||
      brandId != null ||
      supplierId != null ||
      productType != null ||
      stockState != BulkFilterStockState.all ||
      websiteState != BulkToggleState.keep ||
      googleMerchantState != BulkToggleState.keep ||
      activeState != BulkToggleState.keep ||
      onlyMissingCategory ||
      onlyMissingBrand ||
      onlyMissingImage;

  BulkProductSmartFilters copyWith({
    String? keyword,
    String? specQuery,
    String? categoryId,
    bool clearCategoryId = false,
    String? brandId,
    bool clearBrandId = false,
    String? supplierId,
    bool clearSupplierId = false,
    ProductType? productType,
    bool clearProductType = false,
    BulkFilterStockState? stockState,
    BulkToggleState? websiteState,
    BulkToggleState? googleMerchantState,
    BulkToggleState? activeState,
    bool? onlyMissingCategory,
    bool? onlyMissingBrand,
    bool? onlyMissingImage,
  }) {
    return BulkProductSmartFilters(
      keyword: keyword ?? this.keyword,
      specQuery: specQuery ?? this.specQuery,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      brandId: clearBrandId ? null : (brandId ?? this.brandId),
      supplierId: clearSupplierId ? null : (supplierId ?? this.supplierId),
      productType: clearProductType ? null : (productType ?? this.productType),
      stockState: stockState ?? this.stockState,
      websiteState: websiteState ?? this.websiteState,
      googleMerchantState: googleMerchantState ?? this.googleMerchantState,
      activeState: activeState ?? this.activeState,
      onlyMissingCategory: onlyMissingCategory ?? this.onlyMissingCategory,
      onlyMissingBrand: onlyMissingBrand ?? this.onlyMissingBrand,
      onlyMissingImage: onlyMissingImage ?? this.onlyMissingImage,
    );
  }
}

class BulkNumericChange {
  const BulkNumericChange({
    this.mode = BulkNumericChangeMode.keep,
    this.value,
  });

  final BulkNumericChangeMode mode;
  final double? value;

  bool get isActive => mode != BulkNumericChangeMode.keep;

  double apply(double current) {
    final safeValue = value ?? 0;
    switch (mode) {
      case BulkNumericChangeMode.keep:
        return current;
      case BulkNumericChangeMode.set:
        return safeValue;
      case BulkNumericChangeMode.increasePercent:
        return current * (1 + (safeValue / 100));
      case BulkNumericChangeMode.decreasePercent:
        return current * (1 - (safeValue / 100));
      case BulkNumericChangeMode.increaseFixed:
        return current + safeValue;
      case BulkNumericChangeMode.decreaseFixed:
        return current - safeValue;
    }
  }

  BulkNumericChange copyWith({
    BulkNumericChangeMode? mode,
    double? value,
  }) {
    return BulkNumericChange(
      mode: mode ?? this.mode,
      value: value ?? this.value,
    );
  }
}

class BulkClassificationConfig {
  const BulkClassificationConfig({
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brandName,
    this.supplierId,
    this.supplierName,
    this.onlyFillMissing = false,
  });

  final String? categoryId;
  final String? categoryName;
  final String? brandId;
  final String? brandName;
  final String? supplierId;
  final String? supplierName;
  final bool onlyFillMissing;

  bool get hasChanges =>
      categoryId != null || brandId != null || supplierId != null;

  BulkClassificationConfig copyWith({
    String? categoryId,
    String? categoryName,
    bool clearCategory = false,
    String? brandId,
    String? brandName,
    bool clearBrand = false,
    String? supplierId,
    String? supplierName,
    bool clearSupplier = false,
    bool? onlyFillMissing,
  }) {
    return BulkClassificationConfig(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryName: clearCategory ? null : (categoryName ?? this.categoryName),
      brandId: clearBrand ? null : (brandId ?? this.brandId),
      brandName: clearBrand ? null : (brandName ?? this.brandName),
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
      onlyFillMissing: onlyFillMissing ?? this.onlyFillMissing,
    );
  }
}

class BulkChannelsConfig {
  const BulkChannelsConfig({
    this.website = BulkToggleState.keep,
    this.googleMerchant = BulkToggleState.keep,
    this.active = BulkToggleState.keep,
  });

  final BulkToggleState website;
  final BulkToggleState googleMerchant;
  final BulkToggleState active;

  bool get hasChanges =>
      website != BulkToggleState.keep ||
      googleMerchant != BulkToggleState.keep ||
      active != BulkToggleState.keep;

  BulkChannelsConfig copyWith({
    BulkToggleState? website,
    BulkToggleState? googleMerchant,
    BulkToggleState? active,
  }) {
    return BulkChannelsConfig(
      website: website ?? this.website,
      googleMerchant: googleMerchant ?? this.googleMerchant,
      active: active ?? this.active,
    );
  }
}

class BulkPricingConfig {
  const BulkPricingConfig({
    this.price = const BulkNumericChange(),
    this.cost = const BulkNumericChange(),
    this.rounding = BulkPriceRounding.none,
  });

  final BulkNumericChange price;
  final BulkNumericChange cost;
  final BulkPriceRounding rounding;

  bool get hasChanges => price.isActive || cost.isActive;

  BulkPricingConfig copyWith({
    BulkNumericChange? price,
    BulkNumericChange? cost,
    BulkPriceRounding? rounding,
  }) {
    return BulkPricingConfig(
      price: price ?? this.price,
      cost: cost ?? this.cost,
      rounding: rounding ?? this.rounding,
    );
  }
}

class BulkClassificationRowDraft {
  const BulkClassificationRowDraft({
    required this.productId,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brandName,
    this.supplierId,
    this.supplierName,
    this.enabled = true,
  });

  final String productId;
  final String? categoryId;
  final String? categoryName;
  final String? brandId;
  final String? brandName;
  final String? supplierId;
  final String? supplierName;
  final bool enabled;

  BulkClassificationRowDraft copyWith({
    String? categoryId,
    String? categoryName,
    bool clearCategory = false,
    String? brandId,
    String? brandName,
    bool clearBrand = false,
    String? supplierId,
    String? supplierName,
    bool clearSupplier = false,
    bool? enabled,
  }) {
    return BulkClassificationRowDraft(
      productId: productId,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryName: clearCategory ? null : (categoryName ?? this.categoryName),
      brandId: clearBrand ? null : (brandId ?? this.brandId),
      brandName: clearBrand ? null : (brandName ?? this.brandName),
      supplierId: clearSupplier ? null : (supplierId ?? this.supplierId),
      supplierName: clearSupplier ? null : (supplierName ?? this.supplierName),
      enabled: enabled ?? this.enabled,
    );
  }
}

class BulkChannelsRowDraft {
  const BulkChannelsRowDraft({
    required this.productId,
    required this.website,
    required this.googleMerchant,
    required this.active,
    this.enabled = true,
  });

  final String productId;
  final bool website;
  final bool googleMerchant;
  final bool active;
  final bool enabled;

  BulkChannelsRowDraft copyWith({
    bool? website,
    bool? googleMerchant,
    bool? active,
    bool? enabled,
  }) {
    return BulkChannelsRowDraft(
      productId: productId,
      website: website ?? this.website,
      googleMerchant: googleMerchant ?? this.googleMerchant,
      active: active ?? this.active,
      enabled: enabled ?? this.enabled,
    );
  }
}

class BulkPricingRowDraft {
  const BulkPricingRowDraft({
    required this.productId,
    required this.price,
    required this.cost,
    this.enabled = true,
  });

  final String productId;
  final double price;
  final double cost;
  final bool enabled;

  BulkPricingRowDraft copyWith({
    double? price,
    double? cost,
    bool? enabled,
  }) {
    return BulkPricingRowDraft(
      productId: productId,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      enabled: enabled ?? this.enabled,
    );
  }
}

class BulkStockSharedConfig {
  const BulkStockSharedConfig({
    this.mode = BulkStockEditMode.target,
    this.direction = BulkStockDirection.outwards,
    this.reasonType = 'count',
    this.sharedNote = '',
    this.defaultQuantity,
    required this.effectiveAt,
  });

  final BulkStockEditMode mode;
  final BulkStockDirection direction;
  final String reasonType;
  final String sharedNote;
  final int? defaultQuantity;
  final DateTime effectiveAt;

  BulkStockSharedConfig copyWith({
    BulkStockEditMode? mode,
    BulkStockDirection? direction,
    String? reasonType,
    String? sharedNote,
    int? defaultQuantity,
    bool clearDefaultQuantity = false,
    DateTime? effectiveAt,
  }) {
    return BulkStockSharedConfig(
      mode: mode ?? this.mode,
      direction: direction ?? this.direction,
      reasonType: reasonType ?? this.reasonType,
      sharedNote: sharedNote ?? this.sharedNote,
      defaultQuantity: clearDefaultQuantity
          ? null
          : (defaultQuantity ?? this.defaultQuantity),
      effectiveAt: effectiveAt ?? this.effectiveAt,
    );
  }
}

class BulkStockRowDraft {
  const BulkStockRowDraft({
    required this.productId,
    required this.quantity,
    required this.reasonType,
    this.note,
    this.enabled = true,
  });

  final String productId;
  final int quantity;
  final String reasonType;
  final String? note;
  final bool enabled;

  BulkStockRowDraft copyWith({
    int? quantity,
    String? reasonType,
    String? note,
    bool? enabled,
  }) {
    return BulkStockRowDraft(
      productId: productId,
      quantity: quantity ?? this.quantity,
      reasonType: reasonType ?? this.reasonType,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
    );
  }
}

class BulkImageFile {
  const BulkImageFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

class BulkImageAssignment {
  const BulkImageAssignment({
    required this.productId,
    this.file,
    this.enabled = true,
    this.forceReplace = false,
  });

  final String productId;
  final BulkImageFile? file;
  final bool enabled;
  final bool forceReplace;

  BulkImageAssignment copyWith({
    BulkImageFile? file,
    bool clearFile = false,
    bool? enabled,
    bool? forceReplace,
  }) {
    return BulkImageAssignment(
      productId: productId,
      file: clearFile ? null : (file ?? this.file),
      enabled: enabled ?? this.enabled,
      forceReplace: forceReplace ?? this.forceReplace,
    );
  }
}

class BulkUpdateItemResult {
  const BulkUpdateItemResult({
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.status,
    required this.summary,
    this.executionAt,
    this.beforeValues = const {},
    this.afterValues = const {},
    this.changedFields = const [],
    this.error,
  });

  final String productId;
  final String productName;
  final String productSku;
  final BulkUpdateItemStatus status;
  final String summary;
  final DateTime? executionAt;
  final Map<String, dynamic> beforeValues;
  final Map<String, dynamic> afterValues;
  final List<String> changedFields;
  final String? error;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'status': status.name,
      'summary': summary,
      'execution_at': executionAt?.toIso8601String(),
      'before_values': beforeValues,
      'after_values': afterValues,
      'changed_fields': changedFields,
      'error': error,
    };
  }

  factory BulkUpdateItemResult.fromJson(Map<String, dynamic> json) {
    return BulkUpdateItemResult(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productSku: json['product_sku']?.toString() ?? '',
      status: bulkUpdateItemStatusFromValue(json['status']?.toString()),
      summary: json['summary']?.toString() ?? '',
      executionAt: json['execution_at'] == null
          ? null
          : DateTime.parse(json['execution_at'].toString()),
      beforeValues: json['before_values'] is Map
          ? Map<String, dynamic>.from(json['before_values'] as Map)
          : const {},
      afterValues: json['after_values'] is Map
          ? Map<String, dynamic>.from(json['after_values'] as Map)
          : const {},
      changedFields: json['changed_fields'] is List
          ? List<String>.from(json['changed_fields'] as List)
          : const [],
      error: json['error']?.toString(),
    );
  }
}

class BulkProductEditHistoryEntry {
  const BulkProductEditHistoryEntry({
    required this.id,
    required this.operation,
    required this.scopeSource,
    required this.status,
    required this.scopeProductCount,
    required this.enabledProductCount,
    required this.succeededProductCount,
    required this.skippedProductCount,
    required this.failedProductCount,
    required this.createdAt,
    this.origin = BulkProductEditHistoryOrigin.recorded,
    this.legacySessionKind = BulkLegacySessionKind.mass,
    this.isHydrated = false,
    this.endedAt,
    this.createdBy,
    this.actorName,
    this.summary,
    this.infoMessage,
    this.filtersSnapshot = const {},
    this.configSnapshot = const {},
    this.items = const [],
    this.errors = const [],
  });

  final String id;
  final BulkProductEditOperation operation;
  final BulkProductScopeSource scopeSource;
  final BulkProductEditHistoryStatus status;
  final int scopeProductCount;
  final int enabledProductCount;
  final int succeededProductCount;
  final int skippedProductCount;
  final int failedProductCount;
  final DateTime createdAt;
  final BulkProductEditHistoryOrigin origin;
  final BulkLegacySessionKind legacySessionKind;
  final bool isHydrated;
  final DateTime? endedAt;
  final String? createdBy;
  final String? actorName;
  final String? summary;
  final String? infoMessage;
  final Map<String, dynamic> filtersSnapshot;
  final Map<String, dynamic> configSnapshot;
  final List<BulkUpdateItemResult> items;
  final List<String> errors;

  bool get isLegacyInferred =>
      origin == BulkProductEditHistoryOrigin.legacyInferred;

  bool get isLegacyMassSession =>
      isLegacyInferred && legacySessionKind == BulkLegacySessionKind.mass;

  bool get isLegacySingularSession =>
      isLegacyInferred && legacySessionKind == BulkLegacySessionKind.singular;

  factory BulkProductEditHistoryEntry.fromJson(Map<String, dynamic> json) {
    final hasHydratedPayload = json.containsKey('filters_snapshot') ||
        json.containsKey('config_snapshot') ||
        json.containsKey('product_changes') ||
        json.containsKey('errors');

    return BulkProductEditHistoryEntry(
      id: json['id']?.toString() ?? '',
      operation:
          bulkProductEditOperationFromValue(json['operation']?.toString()),
      scopeSource:
          bulkProductScopeSourceFromValue(json['scope_source']?.toString()),
      status: bulkProductEditHistoryStatusFromValue(
        json['status']?.toString(),
      ),
      scopeProductCount: (json['scope_product_count'] as num?)?.toInt() ?? 0,
      enabledProductCount:
          (json['enabled_product_count'] as num?)?.toInt() ?? 0,
      succeededProductCount:
          (json['succeeded_product_count'] as num?)?.toInt() ?? 0,
      skippedProductCount:
          (json['skipped_product_count'] as num?)?.toInt() ?? 0,
      failedProductCount: (json['failed_product_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'].toString()),
      origin: bulkProductEditHistoryOriginFromValue(json['origin']?.toString()),
      legacySessionKind: bulkLegacySessionKindFromValue(
          json['legacy_session_kind']?.toString()),
      isHydrated: hasHydratedPayload,
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'].toString()),
      createdBy: json['created_by']?.toString(),
      actorName: json['actor_name']?.toString(),
      summary: json['summary']?.toString(),
      infoMessage: json['info_message']?.toString(),
      filtersSnapshot: json['filters_snapshot'] is Map
          ? Map<String, dynamic>.from(json['filters_snapshot'] as Map)
          : const {},
      configSnapshot: json['config_snapshot'] is Map
          ? Map<String, dynamic>.from(json['config_snapshot'] as Map)
          : const {},
      items: json['product_changes'] is List
          ? (json['product_changes'] as List)
              .whereType<Map>()
              .map((item) => BulkUpdateItemResult.fromJson(
                  Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      errors: json['errors'] is List
          ? List<String>.from(json['errors'] as List)
          : const [],
    );
  }
}

class BulkUpdateResult {
  const BulkUpdateResult({
    required this.total,
    required this.succeeded,
    required this.skipped,
    required this.failed,
    required this.errors,
    this.items = const [],
  });

  final int total;
  final int succeeded;
  final int skipped;
  final int failed;
  final List<String> errors;
  final List<BulkUpdateItemResult> items;
}
