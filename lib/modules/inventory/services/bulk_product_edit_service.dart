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

      if (onlyWhenMissingImage &&
          !assignment.forceReplace &&
          (product.imageUrl ?? '').trim().isNotEmpty) {
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
