import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/stock_adjustment_origin.dart';
import '../../../shared/models/product.dart'
    show PurchaseTreatment, parsePurchaseTreatment;
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/bulk_product_edit_models.dart';
import '../models/inventory_models.dart';
import 'inventory_service.dart' as inventory_services;
import 'product_image_fingerprint_service.dart';

class BulkProductEditService {
  static final DateTime _legacyInferenceCutoffAt = DateTime.utc(2026, 4, 8);
  static const String _customClearSentinel = '__bulk_clear__';

  BulkProductEditService({
    DatabaseService? databaseService,
    TenantService? tenantService,
  })  : _db = databaseService ?? DatabaseService(),
        _tenantService = tenantService ?? TenantService(),
        _inventoryService = inventory_services.InventoryService(
          databaseService ?? DatabaseService(),
          tenantService ?? TenantService(),
        );

  final DatabaseService _db;
  final TenantService _tenantService;
  final inventory_services.InventoryService _inventoryService;

  List<Product> applyScopeFilters({
    required List<Product> baseProducts,
    required BulkProductSmartFilters filters,
    Map<String, String> specSearchIndex = const {},
  }) {
    var filtered = baseProducts.where((product) => !product.isSetComponent);

    if (filters.categoryId != null) {
      filtered =
          filtered.where((product) => product.categoryId == filters.categoryId);
    }

    if (filters.brandId != null) {
      filtered =
          filtered.where((product) => product.brandId == filters.brandId);
    }

    if (filters.supplierId != null) {
      filtered =
          filtered.where((product) => product.supplierId == filters.supplierId);
    }

    if (filters.productType != null) {
      filtered = filtered
          .where((product) => product.productType == filters.productType);
    }

    switch (filters.stockState) {
      case BulkFilterStockState.all:
        break;
      case BulkFilterStockState.inStock:
        filtered = filtered.where(
            (product) => product.tracksInventory && product.inventoryQty > 0);
      case BulkFilterStockState.lowStock:
        filtered = filtered
            .where((product) => product.tracksInventory && product.isLowStock);
      case BulkFilterStockState.outOfStock:
        filtered = filtered.where(
            (product) => product.tracksInventory && product.isOutOfStock);
    }

    switch (filters.websiteState) {
      case BulkToggleState.keep:
        break;
      case BulkToggleState.enable:
        filtered = filtered.where((product) => product.isPublished);
      case BulkToggleState.disable:
        filtered = filtered.where((product) => !product.isPublished);
    }

    switch (filters.googleMerchantState) {
      case BulkToggleState.keep:
        break;
      case BulkToggleState.enable:
        filtered = filtered.where((product) => product.isGoogleMerchant);
      case BulkToggleState.disable:
        filtered = filtered.where((product) => !product.isGoogleMerchant);
    }

    switch (filters.activeState) {
      case BulkToggleState.keep:
        break;
      case BulkToggleState.enable:
        filtered = filtered.where((product) => product.isActive);
      case BulkToggleState.disable:
        filtered = filtered.where((product) => !product.isActive);
    }

    if (filters.onlyMissingCategory) {
      filtered = filtered
          .where((product) => (product.categoryId ?? '').trim().isEmpty);
    }

    if (filters.onlyMissingBrand) {
      filtered = filtered.where((product) =>
          (product.brandId ?? '').trim().isEmpty &&
          (product.brand ?? '').trim().isEmpty);
    }

    if (filters.onlyMissingImage) {
      filtered =
          filtered.where((product) => (product.imageUrl ?? '').trim().isEmpty);
    }

    if (filters.keyword.trim().isNotEmpty) {
      final tokens = filters.keyword
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((token) => token.trim().isNotEmpty)
          .map((token) => _stemSearchTerm(_normalizeText(token)))
          .toList();
      filtered = filtered.where((product) => _matchesTokens(product, tokens));
    }

    if (filters.specQuery.trim().isNotEmpty) {
      final specTokens = filters.specQuery
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((token) => token.trim().isNotEmpty)
          .map((token) => _stemSearchTerm(_normalizeText(token)))
          .toList();
      filtered = filtered.where((product) {
        final productId = product.id;
        if (productId == null) return false;
        final searchable = specSearchIndex[productId] ?? '';
        return specTokens.every(searchable.contains);
      });
    }

    return filtered.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Map<String, String>> loadSpecSearchIndex(
      Iterable<String> productIds) async {
    final ids = productIds
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const {};

    final buffer = <String, List<String>>{};

    for (final chunk in _chunk(ids, 200)) {
      final rows = await _db.supabase
          .from('product_spec_values')
          .select('product_id, display_value, spec_definitions!inner(key)')
          .inFilter('product_id', chunk);

      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final productId = row['product_id']?.toString();
        if (productId == null || productId.isEmpty) continue;
        final def = row['spec_definitions'] as Map<String, dynamic>?;
        final key = def?['key']?.toString();
        final value = row['display_value']?.toString();
        if ((key ?? '').trim().isEmpty && (value ?? '').trim().isEmpty) {
          continue;
        }
        final parts = <String>[];
        if ((key ?? '').trim().isNotEmpty) parts.add(_normalizeText(key!));
        if ((value ?? '').trim().isNotEmpty) parts.add(_normalizeText(value!));
        if (parts.isEmpty) continue;
        buffer.putIfAbsent(productId, () => <String>[]).add(parts.join(' '));
      }
    }

    return {
      for (final entry in buffer.entries)
        entry.key: _normalizeText(entry.value.join(' ')),
    };
  }

  Map<String, BulkImageFile> autoAssignImages({
    required List<Product> products,
    required List<BulkImageFile> files,
  }) {
    final assignments = <String, BulkImageFile>{};
    final usedProductIds = <String>{};
    final candidateProducts =
        products.where((product) => product.id != null).toList(growable: false);

    for (final file in files) {
      final match = _findBestImageMatch(
        file,
        candidateProducts,
        usedProductIds,
      );
      if (match == null) continue;
      final productId = match.product.id;
      if (productId == null) continue;
      assignments[productId] = file;
      usedProductIds.add(productId);
    }

    return assignments;
  }

  Future<BulkUpdateResult> applyClassification({
    required List<Product> products,
    required Map<String, BulkClassificationRowDraft> drafts,
  }) async {
    var succeeded = 0;
    var skipped = 0;
    final errors = <String>[];
    final items = <BulkUpdateItemResult>[];
    final activeProducts = products.where((product) {
      final productId = product.id;
      if (productId == null) return false;
      final draft = drafts[productId];
      return draft != null && draft.enabled;
    }).toList(growable: false);

    for (final product in activeProducts) {
      final productId = product.id;
      if (productId == null) continue;
      final draft = drafts[productId];
      if (draft == null || !draft.enabled) continue;

      final payload = <String, dynamic>{};
      final beforeValues = <String, dynamic>{
        'category': product.categoryName,
        'brand': product.brand,
        'supplier': product.supplierName,
      };
      final afterValues = <String, dynamic>{
        'category': draft.categoryName,
        'brand': draft.brandName,
        'supplier': draft.supplierName,
      };
      final changedFields = <String>[];

      if ((draft.categoryId ?? '').trim() !=
          (product.categoryId ?? '').trim()) {
        payload['category_id'] = draft.categoryId;
        changedFields.add('category');
      }

      if ((draft.brandId ?? '').trim() != (product.brandId ?? '').trim() ||
          (draft.brandName ?? '').trim() != (product.brand ?? '').trim()) {
        payload['brand_id'] = draft.brandId;
        payload['brand'] = draft.brandName;
        changedFields.add('brand');
      }

      if ((draft.supplierId ?? '').trim() !=
          (product.supplierId ?? '').trim()) {
        payload['supplier_id'] = draft.supplierId;
        changedFields.add('supplier');
      }

      if (payload.isEmpty) {
        skipped += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.skipped,
            summary: 'Sin cambios efectivos en categoría, marca o proveedor.',
            beforeValues: beforeValues,
            afterValues: beforeValues,
          ),
        );
        continue;
      }

      payload['updated_at'] = DateTime.now().toIso8601String();

      try {
        await _db.update('products', productId, payload,
            applyTimestamps: false);
        succeeded += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.updated,
            summary: _summarizeFieldTransitions(
              changedFields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
          ),
        );
      } catch (error) {
        errors.add('${product.name}: $error');
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.failed,
            summary: _summarizeFieldTransitions(
              changedFields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
            error: error.toString(),
          ),
        );
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: errors.length,
      errors: errors,
      items: items,
    );
  }

  Future<BulkUpdateResult> applyChannels({
    required List<Product> products,
    required Map<String, BulkChannelsRowDraft> drafts,
  }) async {
    var succeeded = 0;
    var skipped = 0;
    final errors = <String>[];
    final items = <BulkUpdateItemResult>[];
    final activeProducts = products.where((product) {
      final productId = product.id;
      if (productId == null) return false;
      final draft = drafts[productId];
      return draft != null && draft.enabled;
    }).toList(growable: false);

    for (final product in activeProducts) {
      final productId = product.id;
      if (productId == null) continue;
      final draft = drafts[productId];
      if (draft == null || !draft.enabled) continue;

      final payload = <String, dynamic>{};

      final normalizedWebsite = draft.googleMerchant ? true : draft.website;
      final normalizedMerchant =
          normalizedWebsite ? draft.googleMerchant : false;
      final beforeValues = <String, dynamic>{
        'website': product.isPublished,
        'google_merchant': product.isGoogleMerchant,
        'active': product.isActive,
      };
      final afterValues = <String, dynamic>{
        'website': normalizedWebsite,
        'google_merchant': normalizedMerchant,
        'active': draft.active,
      };
      final changedFields = <String>[];

      if (normalizedWebsite != product.isPublished) {
        payload['is_published'] = normalizedWebsite;
        payload['show_on_website'] = normalizedWebsite;
        changedFields.add('website');
      }

      if (normalizedMerchant != product.isGoogleMerchant) {
        payload['is_google_merchant'] = normalizedMerchant;
        changedFields.add('google_merchant');
      }

      if (draft.active != product.isActive) {
        payload['is_active'] = draft.active;
        changedFields.add('active');
      }

      if (payload.isEmpty) {
        skipped += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.skipped,
            summary: 'Sin cambios efectivos en canales o estado.',
            beforeValues: beforeValues,
            afterValues: beforeValues,
          ),
        );
        continue;
      }

      payload['updated_at'] = DateTime.now().toIso8601String();

      try {
        await _db.update('products', productId, payload,
            applyTimestamps: false);
        succeeded += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.updated,
            summary: _summarizeFieldTransitions(
              changedFields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
          ),
        );
      } catch (error) {
        errors.add('${product.name}: $error');
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.failed,
            summary: _summarizeFieldTransitions(
              changedFields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
            error: error.toString(),
          ),
        );
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: errors.length,
      errors: errors,
      items: items,
    );
  }

  Future<BulkUpdateResult> applyPricing({
    required List<Product> products,
    required Map<String, BulkPricingRowDraft> drafts,
  }) async {
    var succeeded = 0;
    var skipped = 0;
    final errors = <String>[];
    final items = <BulkUpdateItemResult>[];
    final activeProducts = products.where((product) {
      final productId = product.id;
      if (productId == null) return false;
      final draft = drafts[productId];
      return draft != null && draft.enabled;
    }).toList(growable: false);

    for (final product in activeProducts) {
      final productId = product.id;
      if (productId == null) continue;
      final draft = drafts[productId];
      if (draft == null || !draft.enabled) continue;

      final nextPrice = draft.price.clamp(0, double.infinity).toDouble();
      final nextCost = draft.cost.clamp(0, double.infinity).toDouble();
      final beforeValues = <String, dynamic>{
        'price': product.price,
        'cost': product.cost,
      };
      final afterValues = <String, dynamic>{
        'price': nextPrice,
        'cost': nextCost,
      };
      final changedFields = <String>[];

      if (_doubleChanged(product.price, nextPrice)) {
        changedFields.add('price');
      }
      if (_doubleChanged(product.cost, nextCost)) {
        changedFields.add('cost');
      }

      if (changedFields.isEmpty) {
        skipped += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.skipped,
            summary: 'Sin cambios efectivos en precio o costo.',
            beforeValues: beforeValues,
            afterValues: beforeValues,
          ),
        );
        continue;
      }

      final payload = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (changedFields.contains('price')) {
        payload['price'] = nextPrice;
      }
      if (changedFields.contains('cost')) {
        payload['cost'] = nextCost;
      }

      try {
        await _db.update(
          'products',
          productId,
          payload,
          applyTimestamps: false,
        );
        succeeded += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.updated,
            summary: _summarizeFieldTransitions(
              changedFields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
          ),
        );
      } catch (error) {
        errors.add('${product.name}: $error');
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.failed,
            summary: _summarizeFieldTransitions(
              changedFields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
            error: error.toString(),
          ),
        );
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: errors.length,
      errors: errors,
      items: items,
    );
  }

  Future<BulkUpdateResult> applyStock({
    required List<Product> products,
    required BulkStockSharedConfig sharedConfig,
    required Map<String, BulkStockRowDraft> drafts,
  }) async {
    var succeeded = 0;
    var skipped = 0;
    final errors = <String>[];
    final items = <BulkUpdateItemResult>[];
    final activeProducts = products.where((product) {
      final productId = product.id;
      if (productId == null) return false;
      final draft = drafts[productId];
      return draft != null && draft.enabled;
    }).toList(growable: false);

    for (final product in activeProducts) {
      final productId = product.id;
      if (productId == null) continue;

      final draft = drafts[productId];
      if (draft == null || !draft.enabled) {
        continue;
      }

      if (!product.tracksInventory) {
        skipped += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.skipped,
            summary: 'El producto no lleva control de stock.',
            beforeValues: const {},
            afterValues: const {},
          ),
        );
        continue;
      }

      final quantity = math.max(0, draft.quantity);
      var delta = 0;
      String type;
      final note = (draft.note ?? sharedConfig.sharedNote).trim();

      if (sharedConfig.mode == BulkStockEditMode.target) {
        delta = quantity - product.inventoryQty;
        if (delta == 0) {
          skipped += 1;
          items.add(
            BulkUpdateItemResult(
              productId: productId,
              productName: product.name,
              productSku: product.sku,
              status: BulkUpdateItemStatus.skipped,
              summary: 'El stock objetivo coincide con el stock actual.',
              beforeValues: {'stock': product.inventoryQty},
              afterValues: {'stock': product.inventoryQty},
            ),
          );
          continue;
        }
        type = delta > 0 ? 'IN' : 'OUT';
      } else {
        if (quantity == 0) {
          skipped += 1;
          items.add(
            BulkUpdateItemResult(
              productId: productId,
              productName: product.name,
              productSku: product.sku,
              status: BulkUpdateItemStatus.skipped,
              summary: 'La diferencia definida es 0, no se aplicó ajuste.',
              beforeValues: {'stock': product.inventoryQty},
              afterValues: {'stock': product.inventoryQty},
            ),
          );
          continue;
        }
        delta = quantity;
        type = sharedConfig.direction.dbValue;
      }

      final nextStock = type == 'IN'
          ? product.inventoryQty + delta.abs()
          : product.inventoryQty - delta.abs();
      final beforeValues = <String, dynamic>{
        'stock': product.inventoryQty,
      };
      final afterValues = <String, dynamic>{
        'stock': nextStock,
        'direction': type,
        'reason_type': draft.reasonType,
        'note': note,
        'effective_at': sharedConfig.effectiveAt.toIso8601String(),
      };

      try {
        await _inventoryService.applyStockAdjustment(
          productId: productId,
          quantity: delta.abs(),
          type: type,
          reasonType: draft.reasonType,
          note: note.isEmpty ? null : note,
          effectiveAt: sharedConfig.effectiveAt,
          adjustmentOrigin: StockAdjustmentOrigin.massEditPanel.value,
        );
        succeeded += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.updated,
            summary:
                'Stock ${product.inventoryQty} -> $nextStock · ${_reasonLabel(draft.reasonType)}',
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: const ['stock'],
          ),
        );
      } catch (error) {
        errors.add('${product.name}: $error');
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.failed,
            summary:
                'Stock ${product.inventoryQty} -> $nextStock · ${_reasonLabel(draft.reasonType)}',
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: const ['stock'],
            error: error.toString(),
          ),
        );
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: errors.length,
      errors: errors,
      items: items,
    );
  }

  Future<BulkUpdateResult> applyImages({
    required List<Product> products,
    required Map<String, BulkImageAssignment> assignments,
    required bool onlyWhenMissingImage,
  }) async {
    var succeeded = 0;
    var skipped = 0;
    final errors = <String>[];
    final items = <BulkUpdateItemResult>[];
    final activeProducts = products.where((product) {
      final productId = product.id;
      if (productId == null) return false;
      final assignment = assignments[productId];
      return assignment != null && assignment.enabled;
    }).toList(growable: false);

    for (final product in activeProducts) {
      final productId = product.id;
      if (productId == null) continue;
      final assignment = assignments[productId];
      if (assignment == null || !assignment.enabled) {
        continue;
      }

      if (assignment.file == null) {
        skipped += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.skipped,
            summary: 'Sin archivo asignado para esta fila.',
            beforeValues: {'image_url': product.imageUrl},
            afterValues: {'image_url': product.imageUrl},
          ),
        );
        continue;
      }

      if (onlyWhenMissingImage &&
          !assignment.forceReplace &&
          (product.imageUrl ?? '').trim().isNotEmpty) {
        skipped += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.skipped,
            summary:
                'Se conservó la imagen existente por política de no sobrescribir.',
            beforeValues: {'image_url': product.imageUrl},
            afterValues: {'image_url': product.imageUrl},
          ),
        );
        continue;
      }

      final beforeValues = <String, dynamic>{
        'image_url': product.imageUrl,
      };

      try {
        final upload = await ImageService.uploadProductImageWithOptimization(
          bytes: assignment.file!.bytes,
          fileName: assignment.file!.name,
        );
        final afterValues = <String, dynamic>{
          'image_url': upload.originalUrl,
          'image_url_optimized': upload.optimizedUrl,
          'file_name': assignment.file!.name,
          'force_replace': assignment.forceReplace,
        };

        await _db.update(
          'products',
          productId,
          {
            'image_url': upload.originalUrl,
            'image_url_optimized': upload.optimizedUrl,
            'image_fingerprint':
                ProductImageFingerprintService.computeStorageJson(
              assignment.file!.bytes,
            ),
            'updated_at': DateTime.now().toIso8601String(),
          },
          applyTimestamps: false,
        );
        succeeded += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.updated,
            summary: 'Imagen actualizada con ${assignment.file!.name}.',
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: const ['image_url'],
          ),
        );
      } catch (error) {
        errors.add('${product.name}: $error');
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.failed,
            summary:
                'Intento de actualizar imagen con ${assignment.file!.name}.',
            beforeValues: beforeValues,
            afterValues: {'file_name': assignment.file!.name},
            changedFields: const ['image_url'],
            error: error.toString(),
          ),
        );
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: errors.length,
      errors: errors,
      items: items,
    );
  }

  Future<BulkUpdateResult> applyCustom({
    required List<Product> products,
    required Set<String> enabledProductIds,
    required List<BulkCustomProductFieldDefinition> fields,
    required Map<String, Map<String, dynamic>> rowValues,
    required Map<String, String> categoryNamesById,
    required Map<String, String> brandNamesById,
    required Map<String, String> supplierNamesById,
  }) async {
    var succeeded = 0;
    var skipped = 0;
    final errors = <String>[];
    final items = <BulkUpdateItemResult>[];
    final activeProducts = products.where((product) {
      final productId = product.id;
      return productId != null && enabledProductIds.contains(productId);
    }).toList(growable: false);

    for (final product in activeProducts) {
      final productId = product.id;
      if (productId == null) continue;

      final payload = <String, dynamic>{};
      final beforeValues = <String, dynamic>{};
      final afterValues = <String, dynamic>{};
      final changedFields = <String>[];
      int? targetStock;

      try {
        final values = rowValues[productId] ?? const <String, dynamic>{};
        for (final field in fields) {
          if (!values.containsKey(field.key)) continue;
          final rawValue = values[field.key];
          final normalized = _normalizeCustomValue(field, rawValue);
          final beforeValue = _readCustomFieldValue(product, field.key);
          final afterValue = _displayReadyCustomValue(
            field: field,
            value: normalized,
            categoryNamesById: categoryNamesById,
            brandNamesById: brandNamesById,
            supplierNamesById: supplierNamesById,
          );
          final currentValue = _displayReadyCustomValue(
            field: field,
            value: beforeValue,
            categoryNamesById: categoryNamesById,
            brandNamesById: brandNamesById,
            supplierNamesById: supplierNamesById,
          );

          if (_customValuesEquivalent(field, beforeValue, normalized)) {
            continue;
          }

          if (field.key == 'stock') {
            if (!product.tracksInventory) {
              throw Exception(
                'Stock actual solo aplica a productos con control de inventario.',
              );
            }
            final parsedStock =
                normalized is int ? normalized : _parseNullableInt(normalized);
            if (parsedStock == null || parsedStock < 0) {
              throw Exception(
                  'Stock actual requiere un número mayor o igual a 0.');
            }
            targetStock = parsedStock;
            beforeValues[field.key] = currentValue;
            afterValues[field.key] = afterValue;
            changedFields.add(field.key);
            continue;
          }

          _writeCustomPayload(
            payload: payload,
            field: field,
            value: normalized,
            brandNamesById: brandNamesById,
          );
          beforeValues[field.key] = currentValue;
          afterValues[field.key] = afterValue;
          changedFields.add(field.key);
        }

        if (payload.isEmpty && targetStock == null) {
          skipped += 1;
          items.add(
            BulkUpdateItemResult(
              productId: productId,
              productName: product.name,
              productSku: product.sku,
              status: BulkUpdateItemStatus.skipped,
              summary: 'Sin cambios efectivos en campos personalizados.',
              beforeValues: beforeValues,
              afterValues: beforeValues,
            ),
          );
          continue;
        }

        _normalizeCustomPayloadDependencies(
          payload: payload,
          afterValues: afterValues,
        );

        final conversionTarget = _customInventoryConversionTarget(
          product: product,
          payload: payload,
        );
        if (conversionTarget != null && targetStock != null) {
          throw Exception(
            'No se puede ajustar Stock actual y convertir el producto a servicio/consumible en la misma fila.',
          );
        }
        if (conversionTarget != null) {
          await _inventoryService.convertProductInventoryToNonStock(
            productId: productId,
            targetPurchaseTreatment: conversionTarget.purchaseTreatment,
            targetProductType: conversionTarget.productType,
            reason: 'Edición masiva personalizada',
          );
        }

        if (payload.isNotEmpty) {
          payload['updated_at'] = DateTime.now().toIso8601String();

          await _db.update(
            'products',
            productId,
            payload,
            applyTimestamps: false,
          );
        }
        if (targetStock != null) {
          final delta = targetStock - product.inventoryQty;
          await _inventoryService.applyStockAdjustment(
            productId: productId,
            quantity: delta.abs(),
            type: delta > 0 ? 'IN' : 'OUT',
            reasonType: 'count',
            note: 'Edición masiva personalizada: Stock actual',
            effectiveAt: DateTime.now(),
            adjustmentOrigin: StockAdjustmentOrigin.massEditPanel.value,
          );
        }
        succeeded += 1;
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.updated,
            summary: _summarizeCustomFieldTransitions(
              changedFields,
              fields,
              beforeValues,
              afterValues,
            ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
          ),
        );
      } catch (error) {
        errors.add('${product.name}: $error');
        items.add(
          BulkUpdateItemResult(
            productId: productId,
            productName: product.name,
            productSku: product.sku,
            status: BulkUpdateItemStatus.failed,
            summary: changedFields.isEmpty
                ? 'No se pudo preparar la actualización personalizada.'
                : _summarizeCustomFieldTransitions(
                    changedFields,
                    fields,
                    beforeValues,
                    afterValues,
                  ),
            beforeValues: beforeValues,
            afterValues: afterValues,
            changedFields: changedFields,
            error: error.toString(),
          ),
        );
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      skipped: skipped,
      failed: errors.length,
      errors: errors,
      items: items,
    );
  }

  Future<void> recordHistory({
    required BulkProductEditOperation operation,
    required BulkProductScopeSource scopeSource,
    required int scopeProductCount,
    required Map<String, dynamic> filtersSnapshot,
    required Map<String, dynamic> configSnapshot,
    required BulkUpdateResult result,
  }) async {
    await _db.insert(
      'product_bulk_edit_history',
      {
        'operation': operation.name,
        'scope_source': scopeSource.name,
        'status': _resolveHistoryStatus(result).name,
        'actor_name': _resolveActorName(),
        'summary': _buildHistorySummary(operation, result),
        'scope_product_count': scopeProductCount,
        'enabled_product_count': result.total,
        'succeeded_product_count': result.succeeded,
        'skipped_product_count': result.skipped,
        'failed_product_count': result.failed,
        'filters_snapshot': filtersSnapshot,
        'config_snapshot': configSnapshot,
        'product_changes': result.items.map((item) => item.toJson()).toList(),
        'errors': result.errors,
      },
      applyTimestamps: false,
    );
  }

  Future<List<BulkProductEditHistoryEntry>> loadHistory(
      {int limit = 30}) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) return const [];

    final rows = await _db.supabase
        .from('product_bulk_edit_history')
        .select(
          'id, operation, scope_source, status, created_by, actor_name, summary, '
          'scope_product_count, enabled_product_count, succeeded_product_count, '
          'skipped_product_count, failed_product_count, created_at',
        )
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((row) => BulkProductEditHistoryEntry.fromJson(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList(growable: false);
  }

  Future<List<BulkProductEditHistoryEntry>> loadLegacyInferredHistory({
    int limit = 30,
    int sessionGapSeconds = 30,
    int massDistinctProductsThreshold = 2,
    int twoProductMassMaxGapSeconds = 10,
  }) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) return const [];

    final rawRows = await _db.supabase
        .from('stock_adjustments')
        .select(
          'id, product_id, created_by, created_at, quantity, stock_before, '
          'stock_after, adjustment_type, reason, reference, notes',
        )
        .eq('tenant_id', tenantId)
        .inFilter('adjustment_type', ['manual', 'count_gain', 'count_loss'])
        .order('created_by')
        .order('created_at');

    final rows = (rawRows as List)
        .whereType<Map>()
        .map(
          (row) => _LegacyStockAdjustmentRow.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .where((row) => row.isEligibleLegacySource)
        .where((row) => !row.createdAt.isBefore(_legacyInferenceCutoffAt))
        .where((row) => row.productId.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) {
        final actorComparison =
            (a.createdBy ?? '').compareTo(b.createdBy ?? '');
        if (actorComparison != 0) return actorComparison;

        final bucketComparison = a.bucketKey.compareTo(b.bucketKey);
        if (bucketComparison != 0) return bucketComparison;

        final createdAtComparison = a.createdAt.compareTo(b.createdAt);
        if (createdAtComparison != 0) return createdAtComparison;

        return a.id.compareTo(b.id);
      });

    if (rows.isEmpty) return const [];

    final productIds = rows
        .map((row) => row.productId)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    final productMap = await _loadLegacyHistoryProducts(
      tenantId: tenantId,
      productIds: productIds,
    );

    final sessionGap = Duration(seconds: sessionGapSeconds);
    final sessions = <_LegacyStockAdjustmentSession>[];
    _LegacyStockAdjustmentSession? currentSession;

    for (final row in rows) {
      final sameActor = currentSession?.createdBy == row.createdBy;
      final sameBucket = currentSession?.bucketKey == row.bucketKey;
      final withinGap = sameActor &&
          sameBucket &&
          currentSession != null &&
          row.createdAt.difference(currentSession.endAt) <= sessionGap;

      if (!withinGap) {
        if (currentSession != null) {
          sessions.add(currentSession);
        }
        currentSession = _LegacyStockAdjustmentSession(
          createdBy: row.createdBy,
          bucketKey: row.bucketKey,
          rows: <_LegacyStockAdjustmentRow>[row],
        );
        continue;
      }

      currentSession = currentSession.copyWith(
        rows: [...currentSession.rows, row],
      );
    }

    if (currentSession != null) {
      sessions.add(currentSession);
    }

    final inferredSessions = sessions.toList(growable: false)
      ..sort((a, b) => b.startAt.compareTo(a.startAt));

    return inferredSessions
        .take(limit)
        .map(
          (session) => _mapLegacySessionToHistoryEntry(
            session: session,
            productMap: productMap,
            sessionGapSeconds: sessionGapSeconds,
            massDistinctProductsThreshold: massDistinctProductsThreshold,
            twoProductMassMaxGapSeconds: twoProductMassMaxGapSeconds,
          ),
        )
        .toList(growable: false);
  }

  Future<BulkProductEditHistoryEntry?> getHistoryById(String id) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) return null;

    final row = await _db.supabase
        .from('product_bulk_edit_history')
        .select('*')
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .maybeSingle();

    if (row == null) return null;
    return BulkProductEditHistoryEntry.fromJson(
      Map<String, dynamic>.from(row as Map),
    );
  }

  Future<String?> getTenantId() => _tenantService.getTenantId();

  Future<Map<String, Product>> _loadLegacyHistoryProducts({
    required String tenantId,
    required List<String> productIds,
  }) async {
    if (productIds.isEmpty) return const {};

    final result = <String, Product>{};
    for (final chunk in _chunk(productIds, 200)) {
      final rows = await _db.supabase
          .from('products')
          .select()
          .eq('tenant_id', tenantId)
          .inFilter('id', chunk);

      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        final product = Product.fromJson(row);
        final productId = product.id;
        if (productId == null || productId.isEmpty) continue;
        result[productId] = product;
      }
    }

    return result;
  }

  BulkProductEditHistoryEntry _mapLegacySessionToHistoryEntry({
    required _LegacyStockAdjustmentSession session,
    required Map<String, Product> productMap,
    required int sessionGapSeconds,
    required int massDistinctProductsThreshold,
    required int twoProductMassMaxGapSeconds,
  }) {
    final groupedRows = <String, List<_LegacyStockAdjustmentRow>>{};
    for (final row in session.rows) {
      groupedRows
          .putIfAbsent(row.productId, () => <_LegacyStockAdjustmentRow>[])
          .add(row);
    }

    final items = groupedRows.entries.map((entry) {
      final productRows = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final firstRow = productRows.first;
      final lastRow = productRows.last;
      final product = productMap[entry.key];
      final netQuantity =
          productRows.fold<int>(0, (sum, row) => sum + row.quantity);
      final movementCount = productRows.length;

      final baseSummary = movementCount == 1
          ? '${session.originLabel}: stock ${firstRow.stockBefore} -> ${lastRow.stockAfter}'
          : '$movementCount movimientos de ${session.originLabel.toLowerCase()}: stock ${firstRow.stockBefore} -> ${lastRow.stockAfter}';
      final deltaSummary =
          ' (delta ${netQuantity >= 0 ? '+' : ''}$netQuantity).';

      return BulkUpdateItemResult(
        productId: entry.key,
        productName: product?.name ?? firstRow.productNameFallback,
        productSku: product?.sku ?? firstRow.productSkuFallback,
        status: BulkUpdateItemStatus.updated,
        summary: '$baseSummary$deltaSummary',
        executionAt: lastRow.createdAt,
        beforeValues: {'stock': firstRow.stockBefore},
        afterValues: {'stock': lastRow.stockAfter},
        changedFields: const ['stock'],
      );
    }).toList(growable: false)
      ..sort((a, b) =>
          a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));

    final references = session.rows
        .map((row) => row.reference?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final notes = session.rows
        .map((row) => row.notes?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final durationSeconds = session.endAt.difference(session.startAt).inSeconds;
    final sessionId =
        'legacy-${session.createdBy ?? 'unknown'}-${session.startAt.millisecondsSinceEpoch}';
    final legacySessionKind = _resolveLegacySessionKind(
      session: session,
      massDistinctProductsThreshold: massDistinctProductsThreshold,
      twoProductMassMaxGapSeconds: twoProductMassMaxGapSeconds,
    );

    return BulkProductEditHistoryEntry(
      id: sessionId,
      origin: BulkProductEditHistoryOrigin.legacyInferred,
      legacySessionKind: legacySessionKind,
      isHydrated: true,
      operation: BulkProductEditOperation.stock,
      scopeSource: BulkProductScopeSource.filtered,
      status: BulkProductEditHistoryStatus.completed,
      scopeProductCount: session.distinctProductCount,
      enabledProductCount: session.rows.length,
      succeededProductCount: items.length,
      skippedProductCount: 0,
      failedProductCount: 0,
      createdAt: session.startAt,
      endedAt: session.endAt,
      createdBy: session.createdBy,
      actorName: _resolveHistoricalActorName(session.createdBy),
      summary:
          '${session.originLabel}: ${session.rows.length} movimientos en ${session.distinctProductCount} productos.',
      infoMessage:
          'Esta sesión fue reconstruida heurísticamente desde stock_adjustments usando proximidad temporal. Es útil como pista histórica, pero no reemplaza el historial canónico grabado por la función de edición masiva. Se marca como masiva cuando toca 3 o más productos distintos dentro de una ventana de ${sessionGapSeconds}s, o exactamente 2 productos si toda la sesión cabe dentro de ${twoProductMassMaxGapSeconds}s; si no, queda como singular. También se excluyen movimientos anteriores al 08/04/2026 para descartar ajustes previos a la introducción del módulo en el repo.',
      filtersSnapshot: const {},
      configSnapshot: {
        'origen': 'stock_adjustments',
        'tipo_inferido': session.bucketKey,
        'clasificacion_sesion': legacySessionKind.label,
        'corte_desde_repo': '2026-04-08',
        'ventana_maxima_dos_productos_segundos': twoProductMassMaxGapSeconds,
        'regla':
            'Mismo usuario + gap <= ${sessionGapSeconds}s; masiva si toca >= 3 productos distintos, o exactamente 2 productos dentro de ${twoProductMassMaxGapSeconds}s',
        'motivo_origen': session.sourceReason,
        'movimientos_originales': session.rows.length,
        'productos_distintos': session.distinctProductCount,
        'duracion_segundos': durationSeconds,
        if (references.isNotEmpty) 'referencias_detectadas': references,
        if (notes.isNotEmpty) 'notas_detectadas': notes,
      },
      items: items,
      errors: const [],
    );
  }

  BulkLegacySessionKind _resolveLegacySessionKind({
    required _LegacyStockAdjustmentSession session,
    required int massDistinctProductsThreshold,
    required int twoProductMassMaxGapSeconds,
  }) {
    final distinctProducts = session.distinctProductCount;
    if (distinctProducts < massDistinctProductsThreshold) {
      return BulkLegacySessionKind.singular;
    }

    if (distinctProducts > massDistinctProductsThreshold) {
      return BulkLegacySessionKind.mass;
    }

    final durationSeconds = session.endAt.difference(session.startAt).inSeconds;
    return durationSeconds <= twoProductMassMaxGapSeconds
        ? BulkLegacySessionKind.mass
        : BulkLegacySessionKind.singular;
  }

  String _resolveHistoricalActorName(String? createdBy) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (createdBy != null && createdBy == currentUser?.id) {
      return _resolveActorName();
    }
    if (createdBy == null || createdBy.trim().isEmpty) {
      return 'Usuario histórico';
    }
    return 'Usuario ${createdBy.substring(0, math.min(8, createdBy.length))}';
  }

  BulkProductEditHistoryStatus _resolveHistoryStatus(BulkUpdateResult result) {
    if (result.succeeded == 0 && result.failed == 0) {
      return BulkProductEditHistoryStatus.skipped;
    }
    if (result.succeeded == 0 && result.failed > 0) {
      return BulkProductEditHistoryStatus.failed;
    }
    if (result.failed > 0) {
      return BulkProductEditHistoryStatus.partial;
    }
    return BulkProductEditHistoryStatus.completed;
  }

  String _buildHistorySummary(
    BulkProductEditOperation operation,
    BulkUpdateResult result,
  ) {
    return '${operation.label}: ${result.succeeded} actualizados, '
        '${result.skipped} sin cambios, ${result.failed} con error.';
  }

  String _resolveActorName() {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final email = user?.email?.trim();
    final fullName = metadata['full_name']?.toString().trim();
    final name = metadata['name']?.toString().trim();
    if (email != null && email.isNotEmpty) return email;
    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (name != null && name.isNotEmpty) return name;
    return 'Usuario actual';
  }

  dynamic _readCustomFieldValue(Product product, String key) {
    return switch (key) {
      'name' => product.name,
      'sku' => product.sku,
      'supplier_code' => product.supplierCode,
      'barcode' => product.barcode,
      'gtin' => product.gtin,
      'description' => product.description,
      'product_type' => product.productType.name,
      'purchase_treatment' => product.purchaseTreatment.dbValue,
      'is_set' => product.isSet,
      'set_type' => product.setType,
      'category_id' => product.categoryId,
      'brand_id' => product.brandId,
      'model' => product.model,
      'supplier_id' => product.supplierId,
      'price' => product.price,
      'cost' => product.cost,
      'stock' => product.inventoryQty,
      'min_stock_level' => product.minStockLevel,
      'is_active' => product.isActive,
      'is_published' => product.isPublished,
      'is_google_merchant' => product.isGoogleMerchant,
      'website_name' => product.websiteName,
      'website_price' => product.websitePrice,
      'website_description' => product.websiteDescription,
      'website_seo_title' => product.websiteSeoTitle,
      'website_seo_description' => product.websiteSeoDescription,
      'website_search_terms' => product.websiteSearchTerms,
      'website_merchant_title' => product.websiteMerchantTitle,
      'website_merchant_description' => product.websiteMerchantDescription,
      'website_merchant_brand' => product.websiteMerchantBrand,
      'website_merchant_gtin' => product.websiteMerchantGtin,
      'website_merchant_mpn' => product.websiteMerchantMpn,
      'website_google_product_category' => product.websiteGoogleProductCategory,
      _ => null,
    };
  }

  dynamic _normalizeCustomValue(
    BulkCustomProductFieldDefinition field,
    dynamic value,
  ) {
    if (value == _customClearSentinel) {
      if (!field.allowClear) {
        throw Exception('${field.label} no puede quedar vacío.');
      }
      return null;
    }

    switch (field.type) {
      case BulkCustomProductFieldType.toggle:
        if (value is bool) return value;
        return value?.toString().toLowerCase() == 'true';
      case BulkCustomProductFieldType.choice:
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) {
          if (field.isRequired) {
            throw Exception('${field.label} requiere una opción.');
          }
          return null;
        }
        final allowedValues =
            field.choices.map((choice) => choice.value).toSet();
        if (!allowedValues.contains(text)) {
          throw Exception('${field.label} tiene una opción inválida.');
        }
        return text;
      case BulkCustomProductFieldType.integer:
        final parsed = _parseNullableInt(value);
        if (parsed == null && field.isRequired) {
          throw Exception('${field.label} requiere un número entero.');
        }
        if (field.key == 'stock' && parsed != null && parsed < 0) {
          throw Exception('${field.label} no puede ser negativo.');
        }
        return parsed;
      case BulkCustomProductFieldType.decimal:
        final parsed = _parseNullableDouble(value);
        if (parsed == null && field.isRequired) {
          throw Exception('${field.label} requiere un número válido.');
        }
        return parsed;
      case BulkCustomProductFieldType.textList:
        final parsed = _parseTextList(value);
        if (parsed.isEmpty && field.isRequired) {
          throw Exception('${field.label} no puede quedar vacío.');
        }
        return parsed;
      case BulkCustomProductFieldType.category:
      case BulkCustomProductFieldType.brand:
      case BulkCustomProductFieldType.supplier:
      case BulkCustomProductFieldType.text:
      case BulkCustomProductFieldType.longText:
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) {
          if (field.isRequired) {
            throw Exception('${field.label} no puede quedar vacío.');
          }
          return null;
        }
        return text;
    }
  }

  void _writeCustomPayload({
    required Map<String, dynamic> payload,
    required BulkCustomProductFieldDefinition field,
    required dynamic value,
    required Map<String, String> brandNamesById,
  }) {
    switch (field.key) {
      case 'product_type':
        payload['product_type'] = value;
        if (value == ProductType.service.name) {
          payload['purchase_treatment'] = PurchaseTreatment.inventory.dbValue;
          payload['track_stock'] = false;
          payload['inventory_qty'] = 0;
          payload['stock_quantity'] = 0;
          payload['min_stock_level'] = 0;
          payload['max_stock_level'] = 0;
          payload['is_google_merchant'] = false;
          payload['is_set'] = false;
          payload['set_type'] = null;
        }
      case 'purchase_treatment':
        payload['purchase_treatment'] = value;
        if (value == PurchaseTreatment.workshopConsumable.dbValue) {
          payload['track_stock'] = false;
          payload['inventory_qty'] = 0;
          payload['stock_quantity'] = 0;
          payload['min_stock_level'] = 0;
          payload['max_stock_level'] = 0;
          payload['is_set'] = false;
          payload['set_type'] = null;
        }
      case 'is_set':
        payload['is_set'] = value;
        if (value == false) {
          payload['set_type'] = null;
        }
      case 'set_type':
        payload['set_type'] = value;
        if (value != null) {
          payload['is_set'] = true;
        }
      case 'brand_id':
        payload['brand_id'] = value;
        payload['brand'] = value == null ? null : brandNamesById[value];
      case 'is_active':
        payload['is_active'] = value;
        if (value == false) {
          payload['is_published'] = false;
          payload['show_on_website'] = false;
          payload['is_google_merchant'] = false;
        }
      case 'is_published':
        payload['is_published'] = value;
        payload['show_on_website'] = value;
        if (value == false) {
          payload['is_google_merchant'] = false;
        }
      case 'is_google_merchant':
        payload['is_google_merchant'] = value;
        if (value == true) {
          payload['is_published'] = true;
          payload['show_on_website'] = true;
        }
      default:
        payload[field.key] = value;
    }
  }

  void _normalizeCustomPayloadDependencies({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> afterValues,
  }) {
    if (payload['product_type'] == ProductType.service.name) {
      payload['purchase_treatment'] = PurchaseTreatment.inventory.dbValue;
      payload['track_stock'] = false;
      payload['inventory_qty'] = 0;
      payload['stock_quantity'] = 0;
      payload['min_stock_level'] = 0;
      payload['max_stock_level'] = 0;
      payload['is_google_merchant'] = false;
      payload['is_set'] = false;
      payload['set_type'] = null;
      if (afterValues.containsKey('purchase_treatment')) {
        afterValues['purchase_treatment'] =
            PurchaseTreatment.inventory.displayName;
      }
      if (afterValues.containsKey('is_set')) {
        afterValues['is_set'] = false;
      }
      if (afterValues.containsKey('set_type')) {
        afterValues['set_type'] = null;
      }
    }

    if (payload['purchase_treatment'] ==
        PurchaseTreatment.workshopConsumable.dbValue) {
      payload['track_stock'] = false;
      payload['inventory_qty'] = 0;
      payload['stock_quantity'] = 0;
      payload['min_stock_level'] = 0;
      payload['max_stock_level'] = 0;
      payload['is_set'] = false;
      payload['set_type'] = null;
      if (afterValues.containsKey('is_set')) {
        afterValues['is_set'] = false;
      }
      if (afterValues.containsKey('set_type')) {
        afterValues['set_type'] = null;
      }
    }

    if (payload['is_set'] == false) {
      payload['set_type'] = null;
      if (afterValues.containsKey('set_type')) {
        afterValues['set_type'] = null;
      }
    }
  }

  _CustomInventoryConversionTarget? _customInventoryConversionTarget({
    required Product product,
    required Map<String, dynamic> payload,
  }) {
    final currentTracksInventory = product.tracksInventory;
    if (!currentTracksInventory || product.inventoryQty <= 0) {
      return null;
    }

    final targetProductType = ProductType.values.firstWhere(
      (type) =>
          type.name == (payload['product_type'] ?? product.productType.name),
      orElse: () => product.productType,
    );
    final targetPurchaseTreatment = targetProductType == ProductType.service
        ? PurchaseTreatment.inventory
        : parsePurchaseTreatment(
            payload['purchase_treatment'] ?? product.purchaseTreatment.dbValue,
            productType: targetProductType.name,
            trackStock: payload['track_stock'] as bool?,
          );
    final targetTracksInventory = targetProductType != ProductType.service &&
        targetPurchaseTreatment == PurchaseTreatment.inventory;

    if (targetTracksInventory) {
      return null;
    }

    return _CustomInventoryConversionTarget(
      productType: targetProductType,
      purchaseTreatment: targetPurchaseTreatment,
    );
  }

  dynamic _displayReadyCustomValue({
    required BulkCustomProductFieldDefinition field,
    required dynamic value,
    required Map<String, String> categoryNamesById,
    required Map<String, String> brandNamesById,
    required Map<String, String> supplierNamesById,
  }) {
    if (value == null) return null;
    switch (field.key) {
      case 'category_id':
        return categoryNamesById[value] ?? value;
      case 'brand_id':
        return brandNamesById[value] ?? value;
      case 'supplier_id':
        return supplierNamesById[value] ?? value;
      default:
        if (field.type == BulkCustomProductFieldType.choice) {
          return field.choices
                  .where((choice) => choice.value == value)
                  .firstOrNull
                  ?.label ??
              value;
        }
        return value;
    }
  }

  bool _customValuesEquivalent(
    BulkCustomProductFieldDefinition field,
    dynamic before,
    dynamic after,
  ) {
    switch (field.type) {
      case BulkCustomProductFieldType.decimal:
        final beforeDouble = _parseNullableDouble(before);
        final afterDouble = _parseNullableDouble(after);
        if (beforeDouble == null || afterDouble == null) {
          return beforeDouble == afterDouble;
        }
        return !_doubleChanged(beforeDouble, afterDouble);
      case BulkCustomProductFieldType.integer:
        return _parseNullableInt(before) == _parseNullableInt(after);
      case BulkCustomProductFieldType.textList:
        final beforeList = _parseTextList(before);
        final afterList = _parseTextList(after);
        if (beforeList.length != afterList.length) return false;
        for (var i = 0; i < beforeList.length; i += 1) {
          if (beforeList[i] != afterList[i]) return false;
        }
        return true;
      case BulkCustomProductFieldType.toggle:
        return before == after;
      case BulkCustomProductFieldType.choice:
      case BulkCustomProductFieldType.category:
      case BulkCustomProductFieldType.brand:
      case BulkCustomProductFieldType.supplier:
      case BulkCustomProductFieldType.text:
      case BulkCustomProductFieldType.longText:
        return (before?.toString().trim() ?? '') ==
            (after?.toString().trim() ?? '');
    }
  }

  int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text.replaceAll(RegExp(r'[^0-9-]'), ''));
  }

  double? _parseNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(
      text.replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll(',', '.'),
    );
  }

  List<String> _parseTextList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return value
        .toString()
        .split(RegExp(r'[\n,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _summarizeCustomFieldTransitions(
    List<String> fieldKeys,
    List<BulkCustomProductFieldDefinition> fields,
    Map<String, dynamic> beforeValues,
    Map<String, dynamic> afterValues,
  ) {
    final labels = {
      for (final field in fields) field.key: field.label,
    };
    return fieldKeys
        .map(
          (field) => '${labels[field] ?? field}: '
              '${_formatFieldValue(field, beforeValues[field])} -> '
              '${_formatFieldValue(field, afterValues[field])}',
        )
        .join(' · ');
  }

  bool _doubleChanged(double current, double next) {
    return (current - next).abs() > 0.009;
  }

  String _summarizeFieldTransitions(
    List<String> fields,
    Map<String, dynamic> beforeValues,
    Map<String, dynamic> afterValues,
  ) {
    return fields
        .map(
          (field) => '${_fieldLabel(field)}: '
              '${_formatFieldValue(field, beforeValues[field])} -> '
              '${_formatFieldValue(field, afterValues[field])}',
        )
        .join(' · ');
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'category':
        return 'Categoría';
      case 'brand':
        return 'Marca';
      case 'supplier':
        return 'Proveedor';
      case 'website':
        return 'Portal web';
      case 'google_merchant':
        return 'Merchant';
      case 'active':
        return 'Activo';
      case 'price':
        return 'Precio';
      case 'cost':
        return 'Costo';
      case 'image_url':
        return 'Imagen';
      case 'stock':
        return 'Stock';
      default:
        return field;
    }
  }

  String _formatFieldValue(String field, dynamic value) {
    if (value == null) {
      return 'Vacío';
    }
    if (field == 'price' || field == 'cost') {
      final amount =
          value is num ? value.toDouble() : double.tryParse('$value');
      if (amount != null) {
        return ChileanUtils.formatCurrency(amount);
      }
    }
    if (value is bool) {
      return value ? 'Sí' : 'No';
    }
    if (value is List) {
      return value.isEmpty ? 'Vacío' : value.join(', ');
    }
    if (value is num) {
      return value.toString();
    }
    final text = value.toString().trim();
    return text.isEmpty ? 'Vacío' : text;
  }

  String _reasonLabel(String reasonType) {
    switch (reasonType) {
      case 'count':
        return 'Reconteo / reevaluación';
      case 'found':
        return 'Hallazgo / recuperación';
      case 'loss':
        return 'Merma';
      case 'damage':
        return 'Daño';
      case 'theft':
        return 'Robo / extravío';
      case 'internal_use':
        return 'Uso interno / taller';
      case 'manual':
        return 'Otro ajuste manual';
      default:
        return reasonType;
    }
  }

  _BulkImageAutoMatch? _findBestImageMatch(
    BulkImageFile file,
    List<Product> products,
    Set<String> usedProductIds,
  ) {
    final evidence = _buildImageEvidence(file.name);
    if (!evidence.hasStrongSignal) return null;

    final ranked = <_BulkImageAutoMatch>[];
    for (final product in products) {
      final productId = product.id;
      if (productId == null || usedProductIds.contains(productId)) continue;
      final score = _scoreFileAgainstProduct(evidence, product);
      if (score > 0) {
        ranked.add(_BulkImageAutoMatch(product: product, score: score));
      }
    }

    if (ranked.isEmpty) return null;
    ranked.sort((a, b) => b.score.compareTo(a.score));

    final top = ranked.first;
    final secondScore = ranked.length > 1 ? ranked[1].score : 0;
    final hasComfortableLead =
        top.score >= 95 || (top.score - secondScore) >= 15;

    if (!hasComfortableLead || top.score < 52) {
      return null;
    }

    return top;
  }

  int _scoreFileAgainstProduct(_BulkImageEvidence evidence, Product product) {
    final compactStem = evidence.compactStem;
    final productCodes = _productCodeTokens(product);

    for (final code in productCodes) {
      if (code.isEmpty) continue;
      if (compactStem == code) return 140;
      if (evidence.codeLikeTokens.contains(code)) return 125;
      if (compactStem.contains(code) && code.length >= 5) return 118;
    }

    if (evidence.looksGeneric) return 0;

    final productName = _normalizeEvidenceText(product.name);
    final brandText = _normalizeEvidenceText(product.brand ?? '');
    final modelText = _normalizeEvidenceText(product.model ?? '');

    var score = 0;

    if (productName.isNotEmpty &&
        !_isGenericImagePhrase(productName) &&
        evidence.normalizedStem == productName) {
      score = math.max(score, 92);
    }

    if (productName.isNotEmpty &&
        productName.length >= 8 &&
        evidence.normalizedStem.contains(productName)) {
      score = math.max(score, 84);
    }

    final productTokens = _productMeaningfulTokens(product);
    final overlap = evidence.tokens.intersection(productTokens);
    if (overlap.isNotEmpty) {
      score += overlap.length * 16;
    }

    final brandTokens = _extractMeaningfulTokens(brandText);
    if (brandTokens.isNotEmpty &&
        overlap.intersection(brandTokens).isNotEmpty) {
      score += 12;
    }

    final modelTokens = _extractMeaningfulTokens(modelText);
    if (modelTokens.isNotEmpty &&
        overlap.intersection(modelTokens).isNotEmpty) {
      score += 10;
    }

    if (evidence.tokens.length == 1 && overlap.length == 1) {
      score -= 18;
    }

    if (overlap.length >= 2) {
      score += 10;
    }

    return score;
  }

  _BulkImageEvidence _buildImageEvidence(String fileName) {
    final stem = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final normalizedStem = _normalizeEvidenceText(stem);
    final tokens = _extractMeaningfulTokens(normalizedStem);
    final codeLikeTokens = tokens.where(_looksLikeProductCode).toSet();
    final looksGeneric = tokens.isEmpty ||
        tokens.every(_isGenericImageToken) ||
        (tokens.length == 1 && _isGenericImagePhrase(normalizedStem));

    return _BulkImageEvidence(
      normalizedStem: normalizedStem,
      compactStem: normalizedStem.replaceAll(' ', ''),
      tokens: tokens,
      codeLikeTokens: codeLikeTokens,
      looksGeneric: looksGeneric,
    );
  }

  Set<String> _productCodeTokens(Product product) {
    return {
      _normalizeCode(product.sku),
      _normalizeCode(product.barcode ?? ''),
      _normalizeCode(product.manufacturerSku ?? ''),
      _normalizeCode(product.supplierCode ?? ''),
    }..removeWhere((value) => value.trim().isEmpty);
  }

  Set<String> _productMeaningfulTokens(Product product) {
    return {
      ..._extractMeaningfulTokens(_normalizeEvidenceText(product.name)),
      ..._extractMeaningfulTokens(_normalizeEvidenceText(product.brand ?? '')),
      ..._extractMeaningfulTokens(_normalizeEvidenceText(product.model ?? '')),
      ..._extractMeaningfulTokens(
          _normalizeEvidenceText(product.categoryName ?? '')),
      ..._extractMeaningfulTokens(
          _normalizeEvidenceText(product.manufacturerSku ?? '')),
    };
  }

  Set<String> _extractMeaningfulTokens(String text) {
    return text
        .split(RegExp(r'\s+'))
        .map((token) => _stemSearchTerm(token.trim()))
        .where((token) => token.isNotEmpty)
        .where((token) => !_isGenericImageToken(token))
        .where((token) => token.length >= 3 || _looksLikeProductCode(token))
        .toSet();
  }

  bool _looksLikeProductCode(String token) {
    if (token.length < 4) return false;
    if (RegExp(r'^\d{8,}$').hasMatch(token)) return true;
    return RegExp(r'^(?=.*\d)[a-z0-9]+$').hasMatch(token);
  }

  bool _isGenericImagePhrase(String text) {
    return {
      'test',
      'image',
      'photo',
      'picture',
      'screenshot',
      'scan',
      'archivo',
      'file',
      'untitled',
      'nuevo',
      'copy',
      'copia',
    }.contains(text);
  }

  bool _isGenericImageToken(String token) {
    return {
      'img',
      'image',
      'photo',
      'pic',
      'picture',
      'screenshot',
      'screen',
      'scan',
      'archivo',
      'file',
      'test',
      'temp',
      'tmp',
      'copy',
      'copia',
      'new',
      'nuevo',
      'final',
      'whatsapp',
      'documento',
      'document',
      'camera',
      'foto',
    }.contains(token);
  }

  String _normalizeEvidenceText(String text) {
    final normalized = _normalizeText(text)
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  String _normalizeCode(String text) {
    return _normalizeText(text).replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _matchesTokens(Product product, List<String> tokens) {
    final searchableText = [
      _normalizeText(product.name),
      _normalizeText(product.sku),
      _normalizeText(product.brand ?? ''),
      _normalizeText(product.model ?? ''),
      _normalizeText(product.categoryName ?? ''),
      _normalizeText(product.supplierName ?? ''),
      _normalizeText(product.barcode ?? ''),
      _normalizeText(product.manufacturerSku ?? ''),
      _normalizeText(product.supplierCode ?? ''),
      _normalizeText(product.specifications.values.join(' ')),
    ].join(' ');

    return tokens.every((token) {
      if (RegExp(r'^\d+$').hasMatch(token)) {
        return RegExp('(?:^|\\s|[^0-9])$token(?:\$|\\s|[^0-9])')
            .hasMatch(searchableText);
      }
      return searchableText.contains(token);
    });
  }

  String _normalizeText(String text) {
    if (text.isEmpty) return text;
    var normalized = text.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');
    return normalized;
  }

  String _stemSearchTerm(String term) {
    if (term.length <= 3) return term;
    if (term.endsWith('es')) {
      if (term == 'mes' || term == 'tres') return term;
      final beforeEs = term.substring(0, term.length - 2);
      if (beforeEs.isNotEmpty) {
        final lastChar = beforeEs[beforeEs.length - 1];
        if ('ldrn'.contains(lastChar)) return beforeEs;
      }
    }
    if (term.endsWith('s')) {
      if (term == 'cas' ||
          term == 'dos' ||
          term == 'mas' ||
          term == 'las' ||
          term == 'los' ||
          term == 'sus') {
        return term;
      }
      return term.substring(0, term.length - 1);
    }
    return term;
  }

  Iterable<List<String>> _chunk(List<String> items, int size) sync* {
    for (var index = 0; index < items.length; index += size) {
      yield items.sublist(index, math.min(index + size, items.length));
    }
  }
}

class _LegacyStockAdjustmentRow {
  const _LegacyStockAdjustmentRow({
    required this.id,
    required this.productId,
    required this.createdAt,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.adjustmentType,
    this.createdBy,
    this.reason,
    this.reference,
    this.notes,
  });

  final String id;
  final String productId;
  final DateTime createdAt;
  final int quantity;
  final int stockBefore;
  final int stockAfter;
  final String? adjustmentType;
  final String? createdBy;
  final String? reason;
  final String? reference;
  final String? notes;

  String get productNameFallback => 'Producto $productId';
  String get productSkuFallback => productId;
  bool get isEligibleLegacySource {
    if (adjustmentType == 'manual') {
      return true;
    }
    if (adjustmentType == 'count_gain' || adjustmentType == 'count_loss') {
      return (reason ?? '').startsWith('Regularización por conteo');
    }
    return false;
  }

  String get bucketKey {
    if (adjustmentType == 'count_gain' || adjustmentType == 'count_loss') {
      return 'count_regularization';
    }
    return 'manual_adjustment';
  }

  factory _LegacyStockAdjustmentRow.fromJson(Map<String, dynamic> json) {
    return _LegacyStockAdjustmentRow(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      adjustmentType: json['adjustment_type']?.toString(),
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(json['created_at'].toString()),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      stockBefore: (json['stock_before'] as num?)?.toInt() ?? 0,
      stockAfter: (json['stock_after'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString(),
      reference: json['reference']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

class _LegacyStockAdjustmentSession {
  const _LegacyStockAdjustmentSession({
    required this.createdBy,
    required this.bucketKey,
    required this.rows,
  });

  final String? createdBy;
  final String bucketKey;
  final List<_LegacyStockAdjustmentRow> rows;

  DateTime get startAt => rows
      .map((row) => row.createdAt)
      .reduce((left, right) => left.isBefore(right) ? left : right);
  DateTime get endAt => rows
      .map((row) => row.createdAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
  int get distinctProductCount =>
      rows.map((row) => row.productId).toSet().length;
  String get sourceReason =>
      rows.map((row) => row.reason?.trim()).whereType<String>().firstWhere(
            (value) => value.isNotEmpty,
            orElse: () => bucketKey,
          );
  String get originLabel {
    switch (bucketKey) {
      case 'count_regularization':
        return 'Regularización por conteo inferida';
      default:
        return 'Ajuste manual inferido';
    }
  }

  _LegacyStockAdjustmentSession copyWith({
    String? createdBy,
    String? bucketKey,
    List<_LegacyStockAdjustmentRow>? rows,
  }) {
    return _LegacyStockAdjustmentSession(
      createdBy: createdBy ?? this.createdBy,
      bucketKey: bucketKey ?? this.bucketKey,
      rows: rows ?? this.rows,
    );
  }
}

class _BulkImageEvidence {
  const _BulkImageEvidence({
    required this.normalizedStem,
    required this.compactStem,
    required this.tokens,
    required this.codeLikeTokens,
    required this.looksGeneric,
  });

  final String normalizedStem;
  final String compactStem;
  final Set<String> tokens;
  final Set<String> codeLikeTokens;
  final bool looksGeneric;

  bool get hasStrongSignal =>
      codeLikeTokens.isNotEmpty || (!looksGeneric && tokens.length >= 2);
}

class _BulkImageAutoMatch {
  const _BulkImageAutoMatch({
    required this.product,
    required this.score,
  });

  final Product product;
  final int score;
}

class _CustomInventoryConversionTarget {
  const _CustomInventoryConversionTarget({
    required this.productType,
    required this.purchaseTreatment,
  });

  final ProductType productType;
  final PurchaseTreatment purchaseTreatment;
}
