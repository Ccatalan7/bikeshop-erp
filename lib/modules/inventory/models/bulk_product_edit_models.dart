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
  });

  final String productId;
  final BulkImageFile? file;
  final bool enabled;

  BulkImageAssignment copyWith({
    BulkImageFile? file,
    bool clearFile = false,
    bool? enabled,
  }) {
    return BulkImageAssignment(
      productId: productId,
      file: clearFile ? null : (file ?? this.file),
      enabled: enabled ?? this.enabled,
    );
  }
}

class BulkUpdateResult {
  const BulkUpdateResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.errors,
  });

  final int total;
  final int succeeded;
  final int failed;
  final List<String> errors;
}
