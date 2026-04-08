import 'dart:math' as math;

import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bulk_product_edit_models.dart';
import '../models/inventory_models.dart';
import 'inventory_service.dart' as inventory_services;

class BulkProductEditService {
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
        if ((key ?? '').trim().isEmpty && (value ?? '').trim().isEmpty)
          continue;
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
    final usedFiles = <String>{};

    for (final product in products) {
      final productId = product.id;
      if (productId == null) continue;

      BulkImageFile? bestFile;
      var bestScore = 0;
      for (final file in files) {
        if (usedFiles.contains(file.name)) continue;
        final score = _scoreFileAgainstProduct(file.name, product);
        if (score > bestScore) {
          bestScore = score;
          bestFile = file;
        }
      }

      if (bestFile != null && bestScore >= 40) {
        assignments[productId] = bestFile;
        usedFiles.add(bestFile.name);
      }
    }

    return assignments;
  }

  Future<BulkUpdateResult> applyClassification({
    required List<Product> products,
    required Map<String, BulkClassificationRowDraft> drafts,
  }) async {
    var succeeded = 0;
    final errors = <String>[];
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

      if ((draft.categoryId ?? '').trim() !=
          (product.categoryId ?? '').trim()) {
        payload['category_id'] = draft.categoryId;
      }

      if ((draft.brandId ?? '').trim() != (product.brandId ?? '').trim() ||
          (draft.brandName ?? '').trim() != (product.brand ?? '').trim()) {
        payload['brand_id'] = draft.brandId;
        payload['brand'] = draft.brandName;
      }

      if ((draft.supplierId ?? '').trim() !=
          (product.supplierId ?? '').trim()) {
        payload['supplier_id'] = draft.supplierId;
      }

      if (payload.isEmpty) {
        succeeded += 1;
        continue;
      }

      payload['updated_at'] = DateTime.now().toIso8601String();

      try {
        await _db.update('products', productId, payload,
            applyTimestamps: false);
        succeeded += 1;
      } catch (error) {
        errors.add('${product.name}: $error');
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      failed: errors.length,
      errors: errors,
    );
  }

  Future<BulkUpdateResult> applyChannels({
    required List<Product> products,
    required Map<String, BulkChannelsRowDraft> drafts,
  }) async {
    var succeeded = 0;
    final errors = <String>[];
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

      if (normalizedWebsite != product.isPublished) {
        payload['is_published'] = normalizedWebsite;
        payload['show_on_website'] = normalizedWebsite;
      }

      if (normalizedMerchant != product.isGoogleMerchant) {
        payload['is_google_merchant'] = normalizedMerchant;
      }

      if (draft.active != product.isActive) {
        payload['is_active'] = draft.active;
      }

      if (payload.isEmpty) {
        succeeded += 1;
        continue;
      }

      payload['updated_at'] = DateTime.now().toIso8601String();

      try {
        await _db.update('products', productId, payload,
            applyTimestamps: false);
        succeeded += 1;
      } catch (error) {
        errors.add('${product.name}: $error');
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      failed: errors.length,
      errors: errors,
    );
  }

  Future<BulkUpdateResult> applyPricing({
    required List<Product> products,
    required Map<String, BulkPricingRowDraft> drafts,
  }) async {
    var succeeded = 0;
    final errors = <String>[];
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

      final nextPrice = draft.price.clamp(0, double.infinity);
      final nextCost = draft.cost.clamp(0, double.infinity);

      try {
        await _db.update(
          'products',
          productId,
          {
            'price': nextPrice,
            'cost': nextCost,
            'updated_at': DateTime.now().toIso8601String(),
          },
          applyTimestamps: false,
        );
        succeeded += 1;
      } catch (error) {
        errors.add('${product.name}: $error');
      }
    }

    return BulkUpdateResult(
      total: activeProducts.length,
      succeeded: succeeded,
      failed: errors.length,
      errors: errors,
    );
  }

  Future<BulkUpdateResult> applyStock({
    required List<Product> products,
    required BulkStockSharedConfig sharedConfig,
    required Map<String, BulkStockRowDraft> drafts,
  }) async {
    var succeeded = 0;
    final errors = <String>[];
    var total = 0;

    for (final product in products) {
      final productId = product.id;
      if (productId == null) continue;

      final draft = drafts[productId];
      if (draft == null || !draft.enabled || !product.tracksInventory) {
        continue;
      }

      final quantity = math.max(0, draft.quantity);
      var delta = 0;
      String type;

      if (sharedConfig.mode == BulkStockEditMode.target) {
        delta = quantity - product.inventoryQty;
        if (delta == 0) {
          continue;
        }
        type = delta > 0 ? 'IN' : 'OUT';
      } else {
        if (quantity == 0) {
          continue;
        }
        delta = quantity;
        type = sharedConfig.direction.dbValue;
      }

      total += 1;
      final note = (draft.note ?? sharedConfig.sharedNote).trim();

      try {
        await _inventoryService.applyStockAdjustment(
          productId: productId,
          quantity: delta.abs(),
          type: type,
          reasonType: draft.reasonType,
          note: note.isEmpty ? null : note,
          effectiveAt: sharedConfig.effectiveAt,
        );
        succeeded += 1;
      } catch (error) {
        errors.add('${product.name}: $error');
      }
    }

    return BulkUpdateResult(
      total: total,
      succeeded: succeeded,
      failed: errors.length,
      errors: errors,
    );
  }

  Future<BulkUpdateResult> applyImages({
    required List<Product> products,
    required Map<String, BulkImageAssignment> assignments,
    required bool onlyWhenMissingImage,
  }) async {
    var succeeded = 0;
    final errors = <String>[];
    var total = 0;

    for (final product in products) {
      final productId = product.id;
      if (productId == null) continue;
      final assignment = assignments[productId];
      if (assignment == null ||
          !assignment.enabled ||
          assignment.file == null) {
        continue;
      }

      if (onlyWhenMissingImage && (product.imageUrl ?? '').trim().isNotEmpty) {
        continue;
      }

      total += 1;

      try {
        final upload = await ImageService.uploadProductImageWithOptimization(
          bytes: assignment.file!.bytes,
          fileName: assignment.file!.name,
        );

        await _db.update(
          'products',
          productId,
          {
            'image_url': upload.originalUrl,
            'image_url_optimized': upload.optimizedUrl,
            'updated_at': DateTime.now().toIso8601String(),
          },
          applyTimestamps: false,
        );
        succeeded += 1;
      } catch (error) {
        errors.add('${product.name}: $error');
      }
    }

    return BulkUpdateResult(
      total: total,
      succeeded: succeeded,
      failed: errors.length,
      errors: errors,
    );
  }

  Future<String?> getTenantId() => _tenantService.getTenantId();

  int _scoreFileAgainstProduct(String fileName, Product product) {
    final stem = _normalizeText(fileName.replaceAll(RegExp(r'\.[^.]+ ?$'), ''));
    final tokens = <String>{
      _normalizeText(product.sku),
      _normalizeText(product.barcode ?? ''),
      _normalizeText(product.manufacturerSku ?? ''),
      _normalizeText(product.supplierCode ?? ''),
      _normalizeText(product.name),
      _normalizeText(product.model ?? ''),
    }..removeWhere((value) => value.trim().isEmpty);

    var score = 0;
    for (final token in tokens) {
      if (stem == token) {
        score = math.max(score, 100);
      } else if (stem.contains(token)) {
        score = math.max(score, token.length >= 4 ? 80 : 50);
      } else if (token.contains(stem) && stem.length >= 4) {
        score = math.max(score, 60);
      }
    }

    return score;
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
