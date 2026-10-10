import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/services/tenant_service.dart';
import 'catalog_web_models.dart';
import 'catalog_web_service.dart';

/// One catalog projection for the whole workspace: products, «Por
/// resolver», services, categories and featured read the same rows, so a
/// change in one tab is already true in the others.
class CatalogWebController extends ChangeNotifier {
  CatalogWebController({
    CatalogWebService? service,
    TenantService? tenantService,
    this.saveSettings,
    this.afterWrite,
  })  : _service = service ?? CatalogWebService(),
        _tenantService = tenantService ?? TenantService();

  final CatalogWebService _service;
  final TenantService _tenantService;

  /// Writes site settings through the website owner (`WebsiteService`).
  final Future<void> Function(Map<String, String> settings)? saveSettings;

  /// Clears the store caches the ERP keeps after a write.
  final Future<void> Function(String tenantId)? afterWrite;

  String? _tenantId;
  List<CatalogWebItem> _items = const [];
  CatalogRules _rules = const CatalogRules();
  List<CatalogCategoryCount> _categories = const [];
  List<String> _featuredIds = const [];
  List<int> _featuredBlockLimits = const [];
  Map<String, String> _serviceTexts = const {};
  Map<String, String> _categoryTexts = const {};
  bool _loading = false;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  String? get tenantId => _tenantId;
  List<CatalogWebItem> get items => _items;
  CatalogRules get rules => _rules;
  List<CatalogCategoryCount> get categories => _categories;
  List<String> get featuredIds => _featuredIds;

  /// How many featured products the page shows: the largest visible block
  /// that reads «Destacados», or 0 when none does.
  int get featuredShown => _featuredBlockLimits.isEmpty
      ? 0
      : _featuredBlockLimits.reduce((a, b) => a > b ? a : b);

  /// A service's «qué incluye» and a category's description, for previews.
  String serviceText(String id) => _serviceTexts[id] ?? '';
  String categoryText(String id) => _categoryTexts[id] ?? '';
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;
  bool get loaded => _tenantId != null && _error == null;

  CatalogWebItem? itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Products and kits (and consumables): the «Productos» tab.
  List<CatalogWebItem> get goods => [
        for (final item in _items)
          if (item.kind != CatalogItemKind.service) item,
      ];

  List<CatalogWebItem> get services => [
        for (final item in _items)
          if (item.kind == CatalogItemKind.service) item,
      ];

  int countGoods(CatalogItemState state) =>
      goods.where((item) => item.state == state).length;

  /// Every open issue, by code, items worth the most first.
  Map<String, List<CatalogWebItem>> get issues {
    final grouped = <String, List<CatalogWebItem>>{};
    for (final item in _items) {
      for (final issue in item.issues) {
        grouped.putIfAbsent(issue, () => []).add(item);
      }
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final byStock =
            (b.sellable > 0 ? 1 : 0).compareTo(a.sellable > 0 ? 1 : 0);
        if (byStock != 0) return byStock;
        final byValue = b.stockValue.compareTo(a.stockValue);
        if (byValue != 0) return byValue;
        final bySales = b.soldCounter12m.compareTo(a.soldCounter12m);
        if (bySales != 0) return bySales;
        return b.webPrice.compareTo(a.webPrice);
      });
    }
    return grouped;
  }

  /// Issues worth a look today: blocked items with stock, money lost, and
  /// everything the rule cannot sell.
  int get openIssueCount =>
      _items.where((item) => item.issues.isNotEmpty).length;

  Future<void> load({bool quiet = false}) async {
    final generation = ++_generation;
    if (!quiet) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final tenantId = _tenantId ?? await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('No se pudo determinar la tienda activa.');
      }
      final results = await Future.wait<Object>([
        _service.loadItems(tenantId),
        _service.loadRules(tenantId),
        _service.loadCategoryCounts(tenantId),
        _service.loadFeaturedIds(tenantId),
        _service.loadServiceTexts(tenantId),
        _service
            .loadFeaturedBlockLimits(tenantId)
            .catchError((Object _) => const <int>[8]),
      ]);
      if (generation != _generation) return;
      _tenantId = tenantId;
      _items = results[0] as List<CatalogWebItem>;
      _rules = results[1] as CatalogRules;
      _categories = results[2] as List<CatalogCategoryCount>;
      _featuredIds = results[3] as List<String>;
      final texts = results[4] as ({
        Map<String, String> services,
        Map<String, String> categories
      });
      _featuredBlockLimits = results[5] as List<int>;
      _serviceTexts = texts.services;
      _categoryTexts = texts.categories;
      _error = null;
    } catch (error) {
      if (generation != _generation) return;
      _error = '$error';
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Runs [write] against the tenant, then reads the projection again so
  /// every tab shows what the store now does.
  Future<T> _write<T>(Future<T> Function(String tenantId) write) async {
    final tenantId = _tenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo determinar la tienda activa.');
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await write(tenantId);
      if (afterWrite != null) unawaited(afterWrite!(tenantId));
      await load(quiet: true);
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<CatalogWebSaleResult> setWebSale(
    Iterable<String> productIds, {
    required bool on,
  }) =>
      _write((tenantId) => _service.setWebSale(
            tenantId: tenantId,
            productIds: productIds,
            on: on,
          ));

  Future<List<String>> copySkuToGtin([Iterable<String>? productIds]) =>
      _write((tenantId) => _service.copySkuToGtin(
            tenantId: tenantId,
            productIds: productIds,
          ));

  Future<void> undoSkuToGtin(Iterable<String> productIds) =>
      _write((tenantId) => _service.undoSkuToGtin(
            tenantId: tenantId,
            productIds: productIds,
          ));

  Future<void> setClearance(String productId, DateTime? until) =>
      _write((tenantId) => _service.setClearance(
            tenantId: tenantId,
            productId: productId,
            until: until,
          ));

  Future<void> setPriceMode(String productId, CatalogPriceMode mode) =>
      _write((tenantId) => _service.setPriceMode(
            tenantId: tenantId,
            productId: productId,
            mode: mode,
          ));

  Future<int> classifyTax(Iterable<String> productIds, {required int rate}) =>
      _write((tenantId) => _service.classifyTax(
            tenantId: tenantId,
            productIds: productIds,
            rate: rate,
          ));

  Future<void> convertItem(String productId, {required bool toConsumable}) =>
      _write((tenantId) => _service.convertItem(
            tenantId: tenantId,
            productId: productId,
            toConsumable: toConsumable,
          ));

  Future<void> dismissIssue(
    String productId,
    String issue, {
    bool dismissed = true,
  }) =>
      _write((tenantId) => _service.dismissIssue(
            tenantId: tenantId,
            productId: productId,
            issue: issue,
            dismissed: dismissed,
          ));

  Future<int> archiveEmptyRecords(Iterable<String> productIds) =>
      _write((tenantId) => _service.archiveEmptyRecords(
            tenantId: tenantId,
            productIds: productIds,
          ));

  Future<void> setCategoryVisible(String categoryId, bool visible) =>
      _write((tenantId) {
        final visibleIds = {
          for (final category in _categories)
            if (category.visible) category.id,
        };
        if (visible) {
          visibleIds.add(categoryId);
        } else {
          visibleIds.remove(categoryId);
        }
        return _service.replaceCategoryVisibility(
          tenantId: tenantId,
          visibleCategoryIds: visibleIds,
        );
      });

  Future<List<CatalogFeaturedSuggestion>> featuredSuggestions({
    int limit = 16,
    int minStock = 2,
  }) async {
    final tenantId = _tenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) return const [];
    return _service.loadFeaturedSuggestions(
      tenantId,
      limit: limit,
      minStock: minStock,
    );
  }

  Future<void> replaceFeatured(List<String> productIds) =>
      _write((tenantId) => _service.replaceFeatured(
            tenantId: tenantId,
            productIds: productIds,
          ));

  Future<void> saveRules(CatalogRules rules) => _write((tenantId) async {
        final save = saveSettings;
        if (save == null) {
          throw StateError('No hay dónde guardar los ajustes de la tienda.');
        }
        await save(rules.toSettings());
      });
}
