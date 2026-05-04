import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';

enum _CatalogKindFilter { all, products, services }

extension on _CatalogKindFilter {
  String get label {
    switch (this) {
      case _CatalogKindFilter.all:
        return 'Todos';
      case _CatalogKindFilter.products:
        return 'Productos';
      case _CatalogKindFilter.services:
        return 'Servicios';
    }
  }
}

enum _VisibilityFilter { all, visible, hidden }

extension on _VisibilityFilter {
  String get label {
    switch (this) {
      case _VisibilityFilter.all:
        return 'Todos';
      case _VisibilityFilter.visible:
        return 'En web';
      case _VisibilityFilter.hidden:
        return 'Ocultos';
    }
  }
}

enum _ActiveFilter { all, active, inactive }

extension on _ActiveFilter {
  String get label {
    switch (this) {
      case _ActiveFilter.all:
        return 'Todos';
      case _ActiveFilter.active:
        return 'Activos';
      case _ActiveFilter.inactive:
        return 'Inactivos';
    }
  }
}

enum _ReadinessFilter {
  all,
  ready,
  missingImage,
  missingWebsiteDescription,
  missingAny,
}

extension on _ReadinessFilter {
  String get label {
    switch (this) {
      case _ReadinessFilter.all:
        return 'Todos';
      case _ReadinessFilter.ready:
        return 'Listos para vitrina';
      case _ReadinessFilter.missingImage:
        return 'Sin imagen';
      case _ReadinessFilter.missingWebsiteDescription:
        return 'Sin descripción web';
      case _ReadinessFilter.missingAny:
        return 'Incompletos';
    }
  }
}

enum _StockFilter { all, available, outOfStock, notTracked }

extension on _StockFilter {
  String get label {
    switch (this) {
      case _StockFilter.all:
        return 'Todos';
      case _StockFilter.available:
        return 'Disponibles';
      case _StockFilter.outOfStock:
        return 'Sin stock';
      case _StockFilter.notTracked:
        return 'Sin control stock';
    }
  }
}

class ProductWebsiteVisibilityPage extends StatefulWidget {
  const ProductWebsiteVisibilityPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<ProductWebsiteVisibilityPage> createState() =>
      _ProductWebsiteVisibilityPageState();
}

class _ProductWebsiteVisibilityPageState
    extends State<ProductWebsiteVisibilityPage> {
  static const _productSelectColumns =
      'id,name,sku,product_type,category_id,category_name,brand_id,brand,'
      'price,inventory_qty,stock_quantity,track_stock,is_active,is_published,'
      'show_on_website,image_url,image_url_optimized,image_urls,description,'
      'website_description,updated_at';

  final _searchController = TextEditingController();
  final _horizontalScrollController = ScrollController();
  final _verticalScrollController = ScrollController();
  final _supabase = Supabase.instance.client;
  final _tenantService = TenantService();

  List<_WebsiteProductVisibilityRow> _products = [];
  List<_WebsiteProductVisibilityRow> _filteredProducts = [];
  final Set<String> _selectedProductIds = <String>{};
  final Set<String> _selectedCategoryIds = <String>{};
  final Set<String> _selectedBrandIds = <String>{};

  String? _tenantId;
  bool _isLoading = true;
  bool _isApplying = false;
  String? _error;

  final Set<_CatalogKindFilter> _kindFilters = <_CatalogKindFilter>{};
  final Set<_VisibilityFilter> _visibilityFilters = <_VisibilityFilter>{};
  final Set<_ActiveFilter> _activeFilters = <_ActiveFilter>{};
  final Set<_ReadinessFilter> _readinessFilters = <_ReadinessFilter>{};
  final Set<_StockFilter> _stockFilters = <_StockFilter>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('No se pudo determinar el tenant activo.');
      }

      final response = await _supabase
          .from('products')
          .select(_productSelectColumns)
          .eq('tenant_id', tenantId)
          .order('name', ascending: true);

      final rows = (response as List)
          .map((row) => _WebsiteProductVisibilityRow.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _tenantId = tenantId;
        _products = rows;
        _selectedProductIds.removeWhere(
          (id) => !_products.any((product) => product.id == id),
        );
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    if (!mounted) return;
    final query = _normalizeSearch(_searchController.text);
    final selectedCategoryIds = Set<String>.from(_selectedCategoryIds);
    final selectedBrandIds = Set<String>.from(_selectedBrandIds);

    final filtered = _products.where((product) {
      if (query.isNotEmpty && !product.matchesQuery(query)) return false;

      if (!_matchesKindFilters(product)) return false;
      if (!_matchesVisibilityFilters(product)) return false;
      if (!_matchesActiveFilters(product)) return false;
      if (!_matchesReadinessFilters(product)) return false;
      if (!_matchesStockFilters(product)) return false;

      if (selectedCategoryIds.isNotEmpty &&
          !selectedCategoryIds.contains(product.categoryFilterId)) {
        return false;
      }

      if (selectedBrandIds.isNotEmpty &&
          !selectedBrandIds.contains(product.brandFilterId)) {
        return false;
      }

      return true;
    }).toList(growable: false);

    setState(() => _filteredProducts = filtered);
  }

  bool _matchesKindFilters(_WebsiteProductVisibilityRow product) {
    if (_kindFilters.isEmpty || _kindFilters.contains(_CatalogKindFilter.all)) {
      return true;
    }
    return _kindFilters.any((filter) {
      switch (filter) {
        case _CatalogKindFilter.all:
          return true;
        case _CatalogKindFilter.products:
          return !product.isService;
        case _CatalogKindFilter.services:
          return product.isService;
      }
    });
  }

  bool _matchesVisibilityFilters(_WebsiteProductVisibilityRow product) {
    if (_visibilityFilters.isEmpty ||
        _visibilityFilters.contains(_VisibilityFilter.all)) {
      return true;
    }
    return _visibilityFilters.any((filter) {
      switch (filter) {
        case _VisibilityFilter.all:
          return true;
        case _VisibilityFilter.visible:
          return product.isVisibleOnWebsite;
        case _VisibilityFilter.hidden:
          return !product.isVisibleOnWebsite;
      }
    });
  }

  bool _matchesActiveFilters(_WebsiteProductVisibilityRow product) {
    if (_activeFilters.isEmpty || _activeFilters.contains(_ActiveFilter.all)) {
      return true;
    }
    return _activeFilters.any((filter) {
      switch (filter) {
        case _ActiveFilter.all:
          return true;
        case _ActiveFilter.active:
          return product.isActive;
        case _ActiveFilter.inactive:
          return !product.isActive;
      }
    });
  }

  bool _matchesReadinessFilters(_WebsiteProductVisibilityRow product) {
    if (_readinessFilters.isEmpty ||
        _readinessFilters.contains(_ReadinessFilter.all)) {
      return true;
    }
    return _readinessFilters.any((filter) {
      switch (filter) {
        case _ReadinessFilter.all:
          return true;
        case _ReadinessFilter.ready:
          return product.hasImage && product.hasWebsiteDescription;
        case _ReadinessFilter.missingImage:
          return !product.hasImage;
        case _ReadinessFilter.missingWebsiteDescription:
          return !product.hasWebsiteDescription;
        case _ReadinessFilter.missingAny:
          return !product.hasImage || !product.hasWebsiteDescription;
      }
    });
  }

  bool _matchesStockFilters(_WebsiteProductVisibilityRow product) {
    if (_stockFilters.isEmpty || _stockFilters.contains(_StockFilter.all)) {
      return true;
    }
    return _stockFilters.any((filter) {
      switch (filter) {
        case _StockFilter.all:
          return true;
        case _StockFilter.available:
          return product.isAvailableForWebsite;
        case _StockFilter.outOfStock:
          return product.tracksStock && product.stockQuantity <= 0;
        case _StockFilter.notTracked:
          return !product.tracksStock;
      }
    });
  }

  Future<void> _setProductsVisibility(
    List<_WebsiteProductVisibilityRow> sourceRows,
    bool visible,
  ) async {
    if (_isApplying || sourceRows.isEmpty) return;

    final tenantId = _tenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    final rows = visible
        ? sourceRows.where((product) => product.isActive).toList()
        : sourceRows;
    final skippedInactive = visible ? sourceRows.length - rows.length : 0;

    if (rows.isEmpty) {
      _showSnackBar('No hay productos activos para publicar en la web.');
      return;
    }

    setState(() => _isApplying = true);
    try {
      final ids = rows.map((product) => product.id).toList(growable: false);
      await _updateProductIds(ids, visible: visible, tenantId: tenantId);
      _updateRowsLocally(ids.toSet(), visible: visible);
      await _clearProductCaches(tenantId);

      final verb = visible ? 'publicados' : 'ocultados';
      final skippedText = skippedInactive > 0
          ? ' $skippedInactive inactivo${skippedInactive == 1 ? '' : 's'} omitido${skippedInactive == 1 ? '' : 's'}.'
          : '';
      _showSnackBar(
          '${ids.length} producto${ids.length == 1 ? '' : 's'} $verb.$skippedText');
    } catch (e) {
      _showSnackBar('No se pudo actualizar la visibilidad: $e');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _showOnlyCurrentResult() async {
    if (_filteredProducts.isEmpty || _isApplying) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mostrar solo este resultado'),
        content: Text(
          'Se publicarán ${_filteredProducts.length} productos del filtro actual y se ocultará el resto del catálogo web. Los productos inactivos seguirán inactivos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final tenantId = _tenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    final showIds = _filteredProducts
        .where((product) => product.isActive)
        .map((product) => product.id)
        .toSet();
    final hideIds = _products
        .where((product) => !showIds.contains(product.id))
        .map((product) => product.id)
        .toSet();

    setState(() => _isApplying = true);
    try {
      if (showIds.isNotEmpty) {
        await _updateProductIds(showIds.toList(),
            visible: true, tenantId: tenantId);
      }
      if (hideIds.isNotEmpty) {
        await _updateProductIds(hideIds.toList(),
            visible: false, tenantId: tenantId);
      }
      _updateRowsLocally(showIds, visible: true);
      _updateRowsLocally(hideIds, visible: false);
      await _clearProductCaches(tenantId);
      _showSnackBar('Catálogo web actualizado con el filtro actual.');
    } catch (e) {
      _showSnackBar('No se pudo aplicar el filtro como catálogo web: $e');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _updateProductIds(
    List<String> ids, {
    required bool visible,
    required String tenantId,
  }) async {
    const chunkSize = 200;
    final now = DateTime.now().toUtc().toIso8601String();
    for (var start = 0; start < ids.length; start += chunkSize) {
      final chunk = ids.skip(start).take(chunkSize).toList(growable: false);
      await _supabase
          .from('products')
          .update({
            'show_on_website': visible,
            'is_published': visible,
            'updated_at': now,
          })
          .eq('tenant_id', tenantId)
          .inFilter('id', chunk);
    }
  }

  void _updateRowsLocally(Set<String> ids, {required bool visible}) {
    if (ids.isEmpty) return;
    setState(() {
      _products = _products
          .map((product) => ids.contains(product.id)
              ? product.copyWith(
                  isPublished: visible,
                  showOnWebsite: visible,
                  updatedAt: DateTime.now(),
                )
              : product)
          .toList(growable: false);
      if (!visible) {
        _selectedProductIds.removeAll(ids);
      }
    });
    _applyFilters();
  }

  Future<void> _clearProductCaches(String tenantId) async {
    shared_inventory.InventoryService? inventoryService;
    PublicInventoryService? publicInventoryService;
    try {
      inventoryService = context.read<shared_inventory.InventoryService>();
    } catch (_) {
      // Some lightweight embedded contexts may not expose the ERP inventory provider.
    }
    try {
      publicInventoryService = context.read<PublicInventoryService>();
    } catch (_) {
      // Public inventory cache is best-effort here.
    }

    await inventoryService?.refresh();
    publicInventoryService?.clearCache(tenantId: tenantId);
  }

  void _toggleSelected(String productId, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.add(productId);
      } else {
        _selectedProductIds.remove(productId);
      }
    });
  }

  void _toggleFilteredSelection(bool selected) {
    setState(() {
      final filteredIds = _filteredProducts.map((product) => product.id);
      if (selected) {
        _selectedProductIds.addAll(filteredIds);
      } else {
        _selectedProductIds.removeAll(filteredIds);
      }
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<_FilterOption> get _categoryOptions {
    final byId = <String, _FilterOption>{};
    final counts = <String, int>{};
    for (final product in _products) {
      final id = product.categoryFilterId;
      counts[id] = (counts[id] ?? 0) + 1;
      byId.putIfAbsent(
        id,
        () => _FilterOption(id: id, label: product.categoryLabel),
      );
    }
    final options = byId.values
        .map((option) => option.copyWith(count: counts[option.id] ?? 0))
        .toList();
    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  List<_FilterOption> get _brandOptions {
    final byId = <String, _FilterOption>{};
    final counts = <String, int>{};
    for (final product in _products) {
      final id = product.brandFilterId;
      counts[id] = (counts[id] ?? 0) + 1;
      byId.putIfAbsent(
        id,
        () => _FilterOption(id: id, label: product.brandLabel),
      );
    }
    final options = byId.values
        .map((option) => option.copyWith(count: counts[option.id] ?? 0))
        .toList();
    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  List<_WebsiteProductVisibilityRow> get _selectedProducts => _products
      .where((product) => _selectedProductIds.contains(product.id))
      .toList(growable: false);

  int get _visibleCount =>
      _products.where((product) => product.isVisibleOnWebsite).length;
  int get _readyCount => _products
      .where((product) => product.hasImage && product.hasWebsiteDescription)
      .length;
  int get _missingImageCount =>
      _products.where((product) => !product.hasImage).length;
  int get _missingDescriptionCount =>
      _products.where((product) => !product.hasWebsiteDescription).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme),
        if (_isLoading)
          const Expanded(child: Center(child: BrandedLoading()))
        else if (_error != null)
          Expanded(child: _buildErrorState(theme))
        else ...[
          _buildSummaryStrip(theme),
          _buildFilterPanel(theme),
          _buildActionBar(theme),
          Expanded(child: _buildProductTable(theme)),
        ],
      ],
    );

    if (widget.embedded) return body;
    return MainLayout(child: body);
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, widget.embedded ? 12 : 18, 16, 12),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/website'),
              tooltip: 'Volver',
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visibilidad de productos',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Controla qué productos y servicios aparecen en la tienda online.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isApplying ? null : _loadProducts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _buildSummaryMetric(theme, 'Catálogo', _products.length.toString()),
          _buildSummaryMetric(theme, 'En web', _visibleCount.toString()),
          _buildSummaryMetric(theme, 'Listos', _readyCount.toString()),
          _buildSummaryMetric(
              theme, 'Sin imagen', _missingImageCount.toString()),
          _buildSummaryMetric(
            theme,
            'Sin descripción web',
            _missingDescriptionCount.toString(),
          ),
          _buildSummaryMetric(
              theme, 'Resultado', _filteredProducts.length.toString()),
          _buildSummaryMetric(
              theme, 'Seleccionados', _selectedProductIds.length.toString()),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(ThemeData theme, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPanel(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;
          final searchWidth = isCompact
              ? constraints.maxWidth
              : math.min(320.0, constraints.maxWidth);
          final standardWidth = isCompact ? constraints.maxWidth : 178.0;
          final wideWidth = isCompact ? constraints.maxWidth : 238.0;

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Buscar producto, SKU, marca...',
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _searchController.clear,
                          ),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: standardWidth,
                child: _buildEnumMultiSelectFilter<_CatalogKindFilter>(
                  label: 'Tipo',
                  values: _CatalogKindFilter.values
                      .where((value) => value != _CatalogKindFilter.all)
                      .toList(growable: false),
                  selectedValues: _kindFilters,
                  titleFor: (value) => value.label,
                  onChanged: (values) {
                    setState(() {
                      _kindFilters
                        ..clear()
                        ..addAll(values);
                    });
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: standardWidth,
                child: _buildEnumMultiSelectFilter<_VisibilityFilter>(
                  label: 'Estado web',
                  values: _VisibilityFilter.values
                      .where((value) => value != _VisibilityFilter.all)
                      .toList(growable: false),
                  selectedValues: _visibilityFilters,
                  titleFor: (value) => value.label,
                  onChanged: (values) {
                    setState(() {
                      _visibilityFilters
                        ..clear()
                        ..addAll(values);
                    });
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: standardWidth,
                child: _buildEnumMultiSelectFilter<_ActiveFilter>(
                  label: 'Activo',
                  values: _ActiveFilter.values
                      .where((value) => value != _ActiveFilter.all)
                      .toList(growable: false),
                  selectedValues: _activeFilters,
                  titleFor: (value) => value.label,
                  onChanged: (values) {
                    setState(() {
                      _activeFilters
                        ..clear()
                        ..addAll(values);
                    });
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: wideWidth,
                child: _buildEnumMultiSelectFilter<_ReadinessFilter>(
                  label: 'Calidad web',
                  values: _ReadinessFilter.values
                      .where((value) => value != _ReadinessFilter.all)
                      .toList(growable: false),
                  selectedValues: _readinessFilters,
                  titleFor: (value) => value.label,
                  onChanged: (values) {
                    setState(() {
                      _readinessFilters
                        ..clear()
                        ..addAll(values);
                    });
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: standardWidth,
                child: _buildEnumMultiSelectFilter<_StockFilter>(
                  label: 'Stock',
                  values: _StockFilter.values
                      .where((value) => value != _StockFilter.all)
                      .toList(growable: false),
                  selectedValues: _stockFilters,
                  titleFor: (value) => value.label,
                  onChanged: (values) {
                    setState(() {
                      _stockFilters
                        ..clear()
                        ..addAll(values);
                    });
                    _applyFilters();
                  },
                ),
              ),
              SizedBox(
                width: wideWidth,
                child: _buildOptionMultiSelectFilter(
                  label: 'Categorías',
                  options: _categoryOptions,
                  selectedIds: _selectedCategoryIds,
                ),
              ),
              SizedBox(
                width: wideWidth,
                child: _buildOptionMultiSelectFilter(
                  label: 'Marcas',
                  options: _brandOptions,
                  selectedIds: _selectedBrandIds,
                ),
              ),
              SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Limpiar'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEnumMultiSelectFilter<T>({
    required String label,
    required List<T> values,
    required Set<T> selectedValues,
    required String Function(T value) titleFor,
    required ValueChanged<Set<T>> onChanged,
  }) {
    return _SearchableMultiSelectDropdown<T>(
      label: label,
      emptySummary: 'Todos',
      options: values
          .map((value) => _MultiSelectFilterOption<T>(
                value: value,
                label: titleFor(value),
              ))
          .toList(growable: false),
      selectedValues: selectedValues,
      onChanged: onChanged,
    );
  }

  Widget _buildOptionMultiSelectFilter({
    required String label,
    required List<_FilterOption> options,
    required Set<String> selectedIds,
  }) {
    return _SearchableMultiSelectDropdown<String>(
      label: label,
      emptySummary: 'Todos',
      options: options
          .map((option) => _MultiSelectFilterOption<String>(
                value: option.id,
                label: option.label,
                count: option.count,
              ))
          .toList(growable: false),
      selectedValues: selectedIds,
      onChanged: (values) {
        setState(() {
          selectedIds
            ..clear()
            ..addAll(values);
        });
        _applyFilters();
      },
    );
  }

  void _resetFilters() {
    setState(() {
      _kindFilters.clear();
      _visibilityFilters.clear();
      _activeFilters.clear();
      _readinessFilters.clear();
      _stockFilters.clear();
      _selectedCategoryIds.clear();
      _selectedBrandIds.clear();
    });
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    } else {
      _applyFilters();
    }
  }

  Widget _buildActionBar(ThemeData theme) {
    final selectedRows = _selectedProducts;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: _isApplying || _filteredProducts.isEmpty
                ? null
                : () => _setProductsVisibility(_filteredProducts, true),
            icon: _isApplying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.visibility_outlined),
            label: const Text('Mostrar filtrados'),
          ),
          OutlinedButton.icon(
            onPressed: _isApplying || _filteredProducts.isEmpty
                ? null
                : () => _setProductsVisibility(_filteredProducts, false),
            icon: const Icon(Icons.visibility_off_outlined),
            label: const Text('Ocultar filtrados'),
          ),
          OutlinedButton.icon(
            onPressed: _isApplying || selectedRows.isEmpty
                ? null
                : () => _setProductsVisibility(selectedRows, true),
            icon: const Icon(Icons.check_box_outlined),
            label: Text('Mostrar seleccionados (${selectedRows.length})'),
          ),
          OutlinedButton.icon(
            onPressed: _isApplying || selectedRows.isEmpty
                ? null
                : () => _setProductsVisibility(selectedRows, false),
            icon: const Icon(Icons.indeterminate_check_box_outlined),
            label: const Text('Ocultar seleccionados'),
          ),
          TextButton.icon(
            onPressed: _isApplying || _filteredProducts.isEmpty
                ? null
                : _showOnlyCurrentResult,
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Solo resultado actual'),
          ),
          if (_selectedProductIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selectedProductIds.clear),
              child: const Text('Limpiar selección'),
            ),
        ],
      ),
    );
  }

  Widget _buildProductTable(ThemeData theme) {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Text(
          'No hay productos para el filtro actual.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(constraints.maxWidth, 1240.0);
        final selectedFilteredCount = _filteredProducts
            .where((product) => _selectedProductIds.contains(product.id))
            .length;
        final allFilteredSelected =
            selectedFilteredCount == _filteredProducts.length &&
                _filteredProducts.isNotEmpty;

        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  _buildTableHeader(
                    theme,
                    allFilteredSelected: allFilteredSelected,
                    hasPartialSelection: selectedFilteredCount > 0 &&
                        selectedFilteredCount < _filteredProducts.length,
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _verticalScrollController,
                        itemCount: _filteredProducts.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                        itemBuilder: (context, index) => _buildProductRow(
                          theme,
                          _filteredProducts[index],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(
    ThemeData theme, {
    required bool allFilteredSelected,
    required bool hasPartialSelection,
  }) {
    return Container(
      height: 44,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value: hasPartialSelection ? null : allFilteredSelected,
              tristate: true,
              onChanged: (value) => _toggleFilteredSelection(value == true),
            ),
          ),
          _buildHeaderCell(theme, 'Producto', width: 360),
          _buildHeaderCell(theme, 'Tipo', width: 96),
          _buildHeaderCell(theme, 'Web', width: 96),
          _buildHeaderCell(theme, 'Calidad web', width: 170),
          _buildHeaderCell(theme, 'Categoría', width: 180),
          _buildHeaderCell(theme, 'Marca', width: 140),
          _buildHeaderCell(theme, 'Stock', width: 110),
          _buildHeaderCell(theme, 'Precio', width: 110, alignRight: true),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    ThemeData theme,
    String label, {
    required double width,
    bool alignRight = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildProductRow(
      ThemeData theme, _WebsiteProductVisibilityRow product) {
    final selected = _selectedProductIds.contains(product.id);
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : theme.colorScheme.surface,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value: selected,
              onChanged: (value) => _toggleSelected(product.id, value == true),
            ),
          ),
          SizedBox(
            width: 360,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: product.imageUrl == null
                      ? Icon(
                          Icons.image_not_supported_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.sku.isEmpty ? 'Sin SKU' : product.sku,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 96, child: Text(product.typeLabel)),
          SizedBox(
            width: 96,
            child: Switch(
              value: product.isVisibleOnWebsite,
              onChanged: _isApplying || !product.isActive
                  ? null
                  : (value) => _setProductsVisibility([product], value),
            ),
          ),
          SizedBox(
            width: 170,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildStatusChip(
                  theme,
                  product.hasImage ? 'Imagen' : 'Sin imagen',
                  product.hasImage,
                ),
                _buildStatusChip(
                  theme,
                  product.hasWebsiteDescription ? 'Texto web' : 'Sin texto web',
                  product.hasWebsiteDescription,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              product.categoryLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              product.brandLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 110, child: Text(product.stockLabel)),
          SizedBox(
            width: 110,
            child: Text(
              ChileanUtils.formatCurrency(product.price),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Editar producto',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () =>
                  context.go('/inventory/products/${product.id}/edit'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme, String label, bool good) {
    final color = good ? theme.colorScheme.primary : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 42,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'No se pudo cargar el catálogo.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? '',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadProducts,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _WebsiteProductVisibilityRow {
  const _WebsiteProductVisibilityRow({
    required this.id,
    required this.name,
    required this.sku,
    required this.productType,
    required this.categoryId,
    required this.categoryName,
    required this.brandId,
    required this.brand,
    required this.price,
    required this.stockQuantity,
    required this.trackStock,
    required this.isActive,
    required this.isPublished,
    required this.showOnWebsite,
    required this.imageUrl,
    required this.imageUrls,
    required this.description,
    required this.websiteDescription,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String sku;
  final String productType;
  final String? categoryId;
  final String? categoryName;
  final String? brandId;
  final String? brand;
  final double price;
  final int stockQuantity;
  final bool trackStock;
  final bool isActive;
  final bool isPublished;
  final bool showOnWebsite;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? description;
  final String? websiteDescription;
  final DateTime updatedAt;

  factory _WebsiteProductVisibilityRow.fromJson(Map<String, dynamic> json) {
    final optimizedImage = json['image_url_optimized']?.toString();
    final primaryImage = json['image_url']?.toString();
    final rawImageUrls = json['image_urls'];
    final imageUrls = rawImageUrls is List
        ? rawImageUrls.map((value) => value.toString()).toList(growable: false)
        : const <String>[];
    final inventoryQty = (json['inventory_qty'] as num?)?.toInt();
    final stockQty = (json['stock_quantity'] as num?)?.toInt();
    return _WebsiteProductVisibilityRow(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Sin nombre',
      sku: json['sku']?.toString() ?? '',
      productType: json['product_type']?.toString() ?? 'product',
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name']?.toString(),
      brandId: json['brand_id']?.toString(),
      brand: json['brand']?.toString(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      stockQuantity: math.max(inventoryQty ?? 0, stockQty ?? 0),
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      isPublished: json['is_published'] as bool? ?? false,
      showOnWebsite: json['show_on_website'] as bool? ?? false,
      imageUrl: _firstNonEmpty([optimizedImage, primaryImage, ...imageUrls]),
      imageUrls: imageUrls,
      description: json['description']?.toString(),
      websiteDescription: json['website_description']?.toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isService => productType == 'service';
  bool get tracksStock => !isService && trackStock;
  bool get isVisibleOnWebsite => isActive && isPublished && showOnWebsite;
  bool get hasImage => imageUrl != null || imageUrls.isNotEmpty;
  bool get hasWebsiteDescription =>
      websiteDescription != null && websiteDescription!.trim().isNotEmpty;
  bool get isAvailableForWebsite =>
      isService || !tracksStock || stockQuantity > 0;

  String get typeLabel => isService ? 'Servicio' : 'Producto';
  String get categoryLabel =>
      _cleanLabel(categoryName, fallback: 'Sin categoría');
  String get brandLabel => _cleanLabel(brand, fallback: 'Sin marca');
  String get categoryFilterId => categoryId?.trim().isNotEmpty == true
      ? categoryId!.trim()
      : '__category_none__';
  String get brandFilterId =>
      brandId?.trim().isNotEmpty == true ? brandId!.trim() : '__brand_none__';
  String get stockLabel {
    if (isService) return 'Servicio';
    if (!tracksStock) return 'Sin control';
    if (stockQuantity <= 0) return 'Sin stock';
    return '$stockQuantity un.';
  }

  bool matchesQuery(String normalizedQuery) {
    final haystack = _normalizeSearch([
      name,
      sku,
      categoryName ?? '',
      brand ?? '',
      description ?? '',
      websiteDescription ?? '',
    ].join(' '));
    return haystack.contains(normalizedQuery);
  }

  _WebsiteProductVisibilityRow copyWith({
    bool? isPublished,
    bool? showOnWebsite,
    DateTime? updatedAt,
  }) {
    return _WebsiteProductVisibilityRow(
      id: id,
      name: name,
      sku: sku,
      productType: productType,
      categoryId: categoryId,
      categoryName: categoryName,
      brandId: brandId,
      brand: brand,
      price: price,
      stockQuantity: stockQuantity,
      trackStock: trackStock,
      isActive: isActive,
      isPublished: isPublished ?? this.isPublished,
      showOnWebsite: showOnWebsite ?? this.showOnWebsite,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      description: description,
      websiteDescription: websiteDescription,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static String _cleanLabel(String? value, {required String fallback}) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
  }
}

class _MultiSelectFilterOption<T> {
  const _MultiSelectFilterOption({
    required this.value,
    required this.label,
    this.count,
  });

  final T value;
  final String label;
  final int? count;

  String get displayLabel => count == null ? label : '$label ($count)';
}

class _SearchableMultiSelectDropdown<T> extends StatefulWidget {
  const _SearchableMultiSelectDropdown({
    required this.label,
    required this.options,
    required this.selectedValues,
    required this.onChanged,
    this.emptySummary = 'Todos',
  });

  final String label;
  final List<_MultiSelectFilterOption<T>> options;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onChanged;
  final String emptySummary;

  @override
  State<_SearchableMultiSelectDropdown<T>> createState() =>
      _SearchableMultiSelectDropdownState<T>();
}

class _SearchableMultiSelectDropdownState<T>
    extends State<_SearchableMultiSelectDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _queryController = TextEditingController();
  final Set<T> _workingSelection = <T>{};
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _workingSelection.addAll(widget.selectedValues);
    _queryController.addListener(_refreshOverlay);
  }

  @override
  void didUpdateWidget(covariant _SearchableMultiSelectDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isOpen) {
      _workingSelection
        ..clear()
        ..addAll(widget.selectedValues);
    }
  }

  @override
  void dispose() {
    _removeOverlay(updateState: false);
    _queryController
      ..removeListener(_refreshOverlay)
      ..dispose();
    super.dispose();
  }

  void _refreshOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    if (widget.options.isEmpty) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final size = renderObject.size;
    final overlay = Overlay.of(context);

    _workingSelection
      ..clear()
      ..addAll(widget.selectedValues);
    _queryController.clear();

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final theme = Theme.of(context);
        final query = _normalizeSearch(_queryController.text);
        final filteredOptions = widget.options.where((option) {
          if (query.isEmpty) return true;
          return _normalizeSearch(option.displayLabel).contains(query);
        }).toList(growable: false);
        final menuWidth = math.max(size.width, 300.0);
        final listHeight = filteredOptions.isEmpty
            ? 76.0
            : math.min(300.0, math.max(64.0, filteredOptions.length * 42.0));

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            Positioned(
              width: menuWidth,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0, size.height + 6),
                child: Material(
                  elevation: 12,
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _queryController,
                            autofocus: true,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              hintText: 'Buscar ${widget.label.toLowerCase()}',
                              suffixIcon: _queryController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: _queryController.clear,
                                    ),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                onPressed: _workingSelection.isEmpty
                                    ? null
                                    : () => _updateSelection(<T>{}),
                                child: const Text('Limpiar'),
                              ),
                              const SizedBox(width: 4),
                              TextButton(
                                onPressed: filteredOptions.isEmpty
                                    ? null
                                    : () => _updateSelection(
                                          filteredOptions
                                              .map((option) => option.value)
                                              .toSet(),
                                        ),
                                child: const Text('Seleccionar visibles'),
                              ),
                              const Spacer(),
                              Text(
                                '${_workingSelection.length} sel.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: listHeight,
                            child: filteredOptions.isEmpty
                                ? Center(
                                    child: Text(
                                      'Sin resultados',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: filteredOptions.length,
                                    itemBuilder: (context, index) {
                                      final option = filteredOptions[index];
                                      final selected = _workingSelection
                                          .contains(option.value);
                                      return CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        value: selected,
                                        title: Text(
                                          option.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        secondary: option.count == null
                                            ? null
                                            : Text(option.count.toString()),
                                        onChanged: (checked) {
                                          final next =
                                              Set<T>.from(_workingSelection);
                                          if (checked == true) {
                                            next.add(option.value);
                                          } else {
                                            next.remove(option.value);
                                          }
                                          _updateSelection(next);
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _removeOverlay({bool updateState = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (updateState && mounted && _isOpen) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
  }

  void _updateSelection(Set<T> values) {
    _workingSelection
      ..clear()
      ..addAll(values);
    widget.onChanged(Set<T>.from(_workingSelection));
    _overlayEntry?.markNeedsBuild();
  }

  String _summaryText() {
    if (widget.selectedValues.isEmpty) return widget.emptySummary;
    final selectedLabels = widget.options
        .where((option) => widget.selectedValues.contains(option.value))
        .map((option) => option.label)
        .toList(growable: false);
    if (selectedLabels.isEmpty) {
      return '${widget.selectedValues.length} seleccionados';
    }
    if (selectedLabels.length <= 2) return selectedLabels.join(', ');
    return '${selectedLabels.take(2).join(', ')} +${selectedLabels.length - 2}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = widget.selectedValues.isNotEmpty;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.options.isEmpty ? null : _toggleOverlay,
        child: InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            suffixIcon: Icon(
              _isOpen
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
            ),
          ),
          child: Text(
            widget.options.isEmpty ? 'Sin opciones' : _summaryText(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: hasSelection
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: hasSelection ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption({
    required this.id,
    required this.label,
    this.count = 0,
  });

  final String id;
  final String label;
  final int count;

  _FilterOption copyWith({int? count}) => _FilterOption(
        id: id,
        label: label,
        count: count ?? this.count,
      );
}

String _normalizeSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .trim();
}
