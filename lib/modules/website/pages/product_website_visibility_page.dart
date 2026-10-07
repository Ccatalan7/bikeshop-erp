import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../public_store/services/public_inventory_service.dart';
import '../../inventory/models/inventory_models.dart';
import '../../inventory/pages/product_form_page.dart';
import '../../inventory/widgets/product_editor_dialog.dart';
import '../../../shared/models/product_tax_treatment.dart';
import '../../../shared/models/public_product_visibility_policy.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/operational_status_badge.dart';
import '../services/website_service.dart';
import '../services/website_catalog_availability_loader.dart';
import '../widgets/website_admin_ui.dart';

enum _CatalogKindFilter { all, products, services }

/// Public sections exposed by the unified Website Catalog workspace.
enum WebsiteCatalogSection { products, categories }

typedef WebsiteCatalogOpenCategoryPage = void Function(
  String categoryId,
  String categoryName, {
  required bool services,
});

/// Which items the products table lists: its own tab for each (approved
/// editor proposal, 2026-10-06: «Productos · Servicios · Categorías»).
enum WebsiteCatalogItemKind { products, services }

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
        return 'Marcados web';
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

enum _CategoryProductCountFilter { all, withProducts, empty }

extension on _CategoryProductCountFilter {
  String get label {
    switch (this) {
      case _CategoryProductCountFilter.all:
        return 'Todas';
      case _CategoryProductCountFilter.withProducts:
        return 'Con productos';
      case _CategoryProductCountFilter.empty:
        return 'Sin productos';
    }
  }
}

enum _PublicCatalogListView {
  all,
  publicProducts,
  publicServices,
  markedWeb,
  hiddenByRules,
}

enum _CatalogResultAction { publish, hide, replaceCatalog }

class _CatalogActionMetric {
  const _CatalogActionMetric(this.label, this.value);

  final String label;
  final String value;
}

class _CatalogActionConfirmation {
  const _CatalogActionConfirmation({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.icon,
    required this.accentColor,
    required this.metrics,
    required this.note,
    required this.canConfirm,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String confirmLabel;
  final IconData icon;
  final Color accentColor;
  final List<_CatalogActionMetric> metrics;
  final String note;
  final bool canConfirm;
}

extension on _PublicCatalogListView {
  String get label {
    switch (this) {
      case _PublicCatalogListView.all:
        return 'Todo el catálogo';
      case _PublicCatalogListView.publicProducts:
        return 'Visible en Productos';
      case _PublicCatalogListView.publicServices:
        return 'Visible en Servicios';
      case _PublicCatalogListView.markedWeb:
        return 'Marcado para web';
      case _PublicCatalogListView.hiddenByRules:
        return 'Bloqueado por reglas';
    }
  }

  IconData get icon {
    switch (this) {
      case _PublicCatalogListView.all:
        return Icons.filter_list_outlined;
      case _PublicCatalogListView.publicProducts:
        return Icons.storefront_outlined;
      case _PublicCatalogListView.publicServices:
        return Icons.design_services_outlined;
      case _PublicCatalogListView.markedWeb:
        return Icons.public_outlined;
      case _PublicCatalogListView.hiddenByRules:
        return Icons.rule_folder_outlined;
    }
  }
}

class _CatalogTableMetrics {
  const _CatalogTableMetrics({
    required this.product,
    required this.type,
    required this.web,
    required this.status,
    required this.readiness,
    required this.category,
    required this.brand,
    required this.stock,
    required this.price,
  });

  static const double selection = 48;
  static const double action = 40;
  static const double horizontalPadding = 16;
  static const double minimumWidth = 1366;

  /// A tab of one kind drops «Tipo», and the services tab «Stock» too: the
  /// room goes to the product name.
  factory _CatalogTableMetrics.forWidth(
    double availableWidth, {
    bool showType = true,
    bool showStock = true,
  }) {
    final type = showType ? 85.0 : 0.0;
    final stock = showStock ? 100.0 : 0.0;
    final extra = math.max(
      0.0,
      availableWidth - minimumWidth + (85 - type) + (100 - stock),
    );
    return _CatalogTableMetrics(
      product: 330 +
          (extra * (0.34 + (showType ? 0 : 0.06) + (showStock ? 0 : 0.07))),
      type: showType ? type + (extra * 0.06) : 0,
      web: 100,
      status: 116,
      readiness: 150 + (extra * 0.14),
      category: 160 + (extra * 0.20),
      brand: 125 + (extra * 0.12),
      stock: showStock ? stock + (extra * 0.07) : 0,
      price: 100 + (extra * 0.07),
    );
  }

  final double product;
  final double type;
  final double web;
  final double status;
  final double readiness;
  final double category;
  final double brand;
  final double stock;
  final double price;

  double get totalWidth =>
      horizontalPadding +
      selection +
      product +
      type +
      web +
      status +
      readiness +
      category +
      brand +
      stock +
      price +
      action;
}

class ProductWebsiteVisibilityPage extends StatefulWidget {
  const ProductWebsiteVisibilityPage({
    super.key,
    this.embedded = false,
    this.section = WebsiteCatalogSection.products,
    this.kind,
    this.onOpenCategoryPage,
  });

  final bool embedded;
  final WebsiteCatalogSection section;

  /// Opens a published category's own page on the editor canvas, where its
  /// look is edited (approved editor proposal, 2026-10-06: the catalog says
  /// what is published; the design belongs to «Páginas»).
  final WebsiteCatalogOpenCategoryPage? onOpenCategoryPage;

  /// Only products or only services, as their own tab; null lists both with
  /// a «Tipo» filter (the standalone ERP route).
  final WebsiteCatalogItemKind? kind;

  @override
  State<ProductWebsiteVisibilityPage> createState() =>
      _ProductWebsiteVisibilityPageState();
}

class _ProductWebsiteVisibilityPageState
    extends State<ProductWebsiteVisibilityPage> {
  static const _productSelectColumns =
      'id,name,sku,product_type,category_id,category_name,brand_id,brand,'
      'price,tax_rate,inventory_qty,stock_quantity,track_stock,is_active,is_published,'
      'is_set,set_type,parent_set_id,'
      'show_on_website,image_url,image_url_optimized,image_urls,description,'
      'website_description,website_image_url,website_image_url_optimized,'
      'website_image_urls,updated_at';

  final _searchController = TextEditingController();
  final _categorySearchController = TextEditingController();
  final _horizontalScrollController = ScrollController();
  final _verticalScrollController = ScrollController();
  final _supabase = Supabase.instance.client;
  final _tenantService = TenantService();

  List<_WebsiteProductVisibilityRow> _products = [];
  List<_WebsiteProductVisibilityRow> _filteredProducts = [];
  List<_WebsiteCategoryVisibilityOption> _websiteCategories = [];
  final Set<String> _selectedProductIds = <String>{};
  final Set<String> _selectedCategoryIds = <String>{};
  final Set<String> _selectedBrandIds = <String>{};

  String? _tenantId;
  bool _isLoading = true;
  bool _isApplying = false;
  bool _isSavingRules = false;
  bool _showCategorySelectionPage = false;
  bool _showAdvancedFilters = false;
  bool _showPublicRules = false;
  bool _showCatalogSummaryDetails = false;
  String? _error;
  PublicProductVisibilityPolicy _visibilityPolicy =
      const PublicProductVisibilityPolicy();
  final Set<String> _categoryDraftSelection = <String>{};

  final Set<_CatalogKindFilter> _kindFilters = <_CatalogKindFilter>{};
  final Set<_VisibilityFilter> _visibilityFilters = <_VisibilityFilter>{};
  final Set<_ActiveFilter> _activeFilters = <_ActiveFilter>{};
  final Set<_ReadinessFilter> _readinessFilters = <_ReadinessFilter>{};
  final Set<_StockFilter> _stockFilters = <_StockFilter>{};
  _CategoryProductCountFilter _categoryProductCountFilter =
      _CategoryProductCountFilter.all;
  _PublicCatalogListView _publicCatalogListView = _PublicCatalogListView.all;

  @override
  void initState() {
    super.initState();
    _showCategorySelectionPage =
        widget.section == WebsiteCatalogSection.categories;
    _searchController.addListener(_applyFilters);
    _categorySearchController.addListener(_refreshCategorySelectionPage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts());
  }

  @override
  void didUpdateWidget(ProductWebsiteVisibilityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _selectedProductIds.clear();
      _applyFilters();
    }
    if (oldWidget.section == widget.section) return;
    setState(() {
      _showCategorySelectionPage =
          widget.section == WebsiteCatalogSection.categories;
      if (_showCategorySelectionPage && _websiteCategories.isNotEmpty) {
        _categoryDraftSelection
          ..clear()
          ..addAll(_visibleWebsiteCategoryIds);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categorySearchController
      ..removeListener(_refreshCategorySelectionPage)
      ..dispose();
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
      final categoriesResponse = await _supabase
          .from('product_categories')
          .select(
            'id,name,full_path,parent_id,level,description,image_url,'
            'show_on_website,is_active,sort_order',
          )
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .order('full_path', ascending: true)
          .order('name', ascending: true);
      final settingsResponse = await _supabase
          .from('website_settings')
          .select('key,value')
          .eq('tenant_id', tenantId)
          .inFilter('key', PublicProductVisibilityPolicy.settingKeys);

      final rawProductRows = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      final canonicalAvailability =
          await WebsiteCatalogAvailabilityLoader(_supabase).load(
        tenantId: tenantId,
        productIds: rawProductRows.map((row) => row['id']?.toString() ?? ''),
      );
      WebsiteCatalogAvailabilityLoader.applyToRows(
        rows: rawProductRows,
        availabilityByProductId: canonicalAvailability,
      );
      final rows = rawProductRows
          .map((row) => _WebsiteProductVisibilityRow.fromJson(
                row,
              ))
          .toList(growable: false);
      final categories = (categoriesResponse as List)
          .map((row) => _WebsiteCategoryVisibilityOption.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false);
      final settings = <String, String>{};
      for (final row in settingsResponse as List) {
        final map = Map<String, dynamic>.from(row as Map);
        settings[map['key']?.toString() ?? ''] = map['value']?.toString() ?? '';
      }

      if (!mounted) return;
      setState(() {
        _tenantId = tenantId;
        _products = rows;
        _websiteCategories = categories;
        if (widget.section == WebsiteCatalogSection.categories) {
          _categoryDraftSelection
            ..clear()
            ..addAll(categories
                .where((category) => category.showOnWebsite)
                .map((category) => category.id));
          _showCategorySelectionPage = true;
        }
        _visibilityPolicy =
            PublicProductVisibilityPolicy.fromSettings(settings);
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

  Future<void> _refreshWorkspace() async {
    await _loadProducts();
  }

  void _applyFilters() {
    if (!mounted) return;
    final query = _normalizeSearch(_searchController.text);
    final selectedCategoryIds = Set<String>.from(_selectedCategoryIds);
    final selectedBrandIds = Set<String>.from(_selectedBrandIds);
    final publicCatalogListView = _publicCatalogListView;
    final visibleWebsiteCategoryIds = _visibleWebsiteCategoryIds;

    final filtered = _products.where((product) {
      if (!_matchesPublicCatalogListView(
        product,
        publicCatalogListView,
        visibleWebsiteCategoryIds,
      )) {
        return false;
      }

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

  bool _matchesPublicCatalogListView(
    _WebsiteProductVisibilityRow product,
    _PublicCatalogListView view,
    Set<String> visibleWebsiteCategoryIds,
  ) {
    switch (view) {
      case _PublicCatalogListView.all:
        return true;
      case _PublicCatalogListView.publicProducts:
        return product.isVisibleInPublicProductsCatalog(
          _visibilityPolicy,
          visibleWebsiteCategoryIds,
        );
      case _PublicCatalogListView.publicServices:
        return product.isVisibleInPublicServicesCatalog(
          _visibilityPolicy,
          visibleWebsiteCategoryIds,
        );
      case _PublicCatalogListView.markedWeb:
        return product.isVisibleOnWebsite;
      case _PublicCatalogListView.hiddenByRules:
        return product.isHiddenFromPublicByPolicy(
          _visibilityPolicy,
          visibleWebsiteCategoryIds,
        );
    }
  }

  void _refreshCategorySelectionPage() {
    if (mounted && _showCategorySelectionPage) {
      setState(() {});
    }
  }

  bool _matchesKindFilters(_WebsiteProductVisibilityRow product) {
    switch (widget.kind) {
      case WebsiteCatalogItemKind.products:
        if (product.isService) return false;
      case WebsiteCatalogItemKind.services:
        if (!product.isService) return false;
      case null:
        break;
    }
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
          return product.tracksStock && product.availableStockQuantity <= 0;
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

    final activeRows = visible
        ? sourceRows.where((product) => product.isActive).toList()
        : sourceRows;
    final rows = visible
        ? activeRows
            .where((product) => product.hasTaxClassification)
            .toList(growable: false)
        : activeRows;
    final skippedInactive = visible ? sourceRows.length - activeRows.length : 0;
    final skippedUnclassified = visible ? activeRows.length - rows.length : 0;

    if (rows.isEmpty) {
      _showSnackBar(
        skippedUnclassified > 0
            ? 'No se puede publicar: falta clasificar IVA 19% o Exento.'
            : 'No hay productos activos para publicar en la web.',
      );
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
      final taxText = skippedUnclassified > 0
          ? ' $skippedUnclassified sin clasificación tributaria omitido${skippedUnclassified == 1 ? '' : 's'}.'
          : '';
      _showSnackBar(
          '${ids.length} producto${ids.length == 1 ? '' : 's'} $verb.$skippedText$taxText');
    } catch (e) {
      _showSnackBar('No se pudo actualizar la visibilidad: $e');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _confirmAndRunResultAction(
    _CatalogResultAction action,
  ) async {
    if (_isApplying || _filteredProducts.isEmpty) return;

    final confirmation = _buildResultActionConfirmation(action);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (context) => _CatalogActionConfirmationDialog(
        confirmation: confirmation,
      ),
    );
    if (!mounted || confirmed != true) return;

    switch (action) {
      case _CatalogResultAction.publish:
        await _setProductsVisibility(_filteredProducts, true);
        return;
      case _CatalogResultAction.hide:
        await _setProductsVisibility(_filteredProducts, false);
        return;
      case _CatalogResultAction.replaceCatalog:
        await _showOnlyCurrentResult();
        return;
    }
  }

  _CatalogActionConfirmation _buildResultActionConfirmation(
    _CatalogResultAction action,
  ) {
    final theme = Theme.of(context);
    final rows = _filteredProducts;
    final activeRows = rows.where((product) => product.isActive).toList();
    final publishableRows = activeRows
        .where((product) => product.hasTaxClassification)
        .toList(growable: false);
    final skippedInactive = rows.length - activeRows.length;
    final skippedUnclassified = activeRows.length - publishableRows.length;
    final markedInResult =
        rows.where((product) => product.isMarkedForWebsite).length;
    final visibleWithCurrentRules = publishableRows
        .where(
          (product) => product
              .copyWith(isPublished: true, showOnWebsite: true)
              .matchesPublicVisibilityPolicy(
                _visibilityPolicy,
                _visibleWebsiteCategoryIds,
              ),
        )
        .length;

    final omissions = <String>[
      if (skippedInactive > 0)
        '$skippedInactive inactivo${skippedInactive == 1 ? '' : 's'}',
      if (skippedUnclassified > 0)
        '$skippedUnclassified sin clasificación tributaria',
    ];
    final omissionText =
        omissions.isEmpty ? '' : ' Se omitirán ${omissions.join(' y ')}.';

    switch (action) {
      case _CatalogResultAction.publish:
        return _CatalogActionConfirmation(
          eyebrow: 'PUBLICACIÓN DEL RESULTADO',
          title: 'Publicar resultado actual',
          description:
              'Se activará “Marcado web” para los productos aptos del resultado actual. Las reglas públicas decidirán cuáles quedan visibles.',
          confirmLabel: 'Publicar ${publishableRows.length}',
          icon: Icons.visibility_outlined,
          accentColor: theme.colorScheme.primary,
          metrics: [
            _CatalogActionMetric('Resultado actual', '${rows.length}'),
            _CatalogActionMetric(
              'Se marcarán para web',
              '${publishableRows.length}',
            ),
            _CatalogActionMetric(
              'Visibles con reglas actuales',
              '$visibleWithCurrentRules',
            ),
          ],
          note: 'No se modifican precios, stock ni categorías.$omissionText',
          canConfirm: publishableRows.isNotEmpty,
        );
      case _CatalogResultAction.hide:
        return _CatalogActionConfirmation(
          eyebrow: 'VISIBILIDAD DEL RESULTADO',
          title: 'Ocultar resultado actual',
          description:
              'Se desactivará “Marcado web” para los productos del resultado actual que hoy están marcados.',
          confirmLabel: 'Ocultar $markedInResult',
          icon: Icons.visibility_off_outlined,
          accentColor: const Color(0xFF526773),
          metrics: [
            _CatalogActionMetric('Resultado actual', '${rows.length}'),
            _CatalogActionMetric('Marcados actualmente', '$markedInResult'),
            _CatalogActionMetric(
              'Ya estaban ocultos',
              '${rows.length - markedInResult}',
            ),
          ],
          note:
              'No se eliminan productos ni se modifica inventario; sólo se retira su marcado web.',
          canConfirm: markedInResult > 0,
        );
      case _CatalogResultAction.replaceCatalog:
        final showIds = publishableRows.map((product) => product.id).toSet();
        final markedIds = _products
            .where((product) => product.isMarkedForWebsite)
            .map((product) => product.id)
            .toSet();
        final toMark = showIds.difference(markedIds).length;
        final toHide = markedIds.difference(showIds).length;
        return _CatalogActionConfirmation(
          eyebrow: 'REEMPLAZO DEL CATÁLOGO',
          title: 'Dejar visible sólo este resultado',
          description:
              'El resultado apto pasará a ser el conjunto marcado para web. Todo producto marcado que quede fuera se ocultará.',
          confirmLabel: 'Reemplazar catálogo',
          icon: Icons.filter_alt_outlined,
          accentColor: const Color(0xFF8A6B2E),
          metrics: [
            _CatalogActionMetric(
              'Quedarán marcados',
              '${publishableRows.length}',
            ),
            _CatalogActionMetric('Nuevos marcados', '$toMark'),
            _CatalogActionMetric('Se ocultarán', '$toHide'),
          ],
          note:
              'Esta acción afecta el catálogo completo, no sólo las filas visibles.$omissionText',
          canConfirm: toMark > 0 || toHide > 0,
        );
    }
  }

  Future<void> _showOnlyCurrentResult() async {
    if (_filteredProducts.isEmpty || _isApplying) return;

    final publishableRows = _filteredProducts
        .where((product) => product.isActive && product.hasTaxClassification)
        .toList(growable: false);

    final tenantId = _tenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    final showIds = publishableRows.map((product) => product.id).toSet();
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
    await context.read<WebsiteService>().updateProductWebsiteVisibilityBatch(
          tenantId: tenantId,
          productIds: ids,
          showOnWebsite: visible,
        );
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

  Future<void> _clearProductCaches(
    String tenantId, {
    bool refreshCategories = false,
  }) async {
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
    publicInventoryService?.clearProductCache(tenantId: tenantId);
    if (refreshCategories && publicInventoryService != null) {
      await publicInventoryService.refreshCategoriesForTenant(
        tenantId: tenantId,
      );
    }
  }

  Future<void> _saveVisibilityPolicy(
    PublicProductVisibilityPolicy policy,
  ) async {
    if (_isSavingRules) return;
    final tenantId = _tenantId;
    if (tenantId == null || tenantId.isEmpty) return;

    final previous = _visibilityPolicy;
    setState(() {
      _visibilityPolicy = policy;
      _isSavingRules = true;
    });
    _applyFilters();

    try {
      await _saveWebsiteSettings(policy.toSettings(), tenantId: tenantId);
      await _clearProductCaches(tenantId);
      _showSnackBar('Reglas del catálogo público actualizadas.');
    } catch (e) {
      if (mounted) {
        setState(() => _visibilityPolicy = previous);
        _applyFilters();
      }
      _showSnackBar('No se pudieron guardar las reglas: $e');
    } finally {
      if (mounted) setState(() => _isSavingRules = false);
    }
  }

  Future<bool> _saveWebsiteCategories(Set<String> categoryIds) async {
    if (_isSavingRules) return false;
    final tenantId = _tenantId;
    if (tenantId == null || tenantId.isEmpty) return false;

    final previous = List<_WebsiteCategoryVisibilityOption>.from(
      _websiteCategories,
    );
    final selected = Set<String>.from(categoryIds);

    setState(() {
      _isSavingRules = true;
      _websiteCategories = _websiteCategories
          .map((category) => category.copyWith(
                showOnWebsite: selected.contains(category.id),
              ))
          .toList(growable: false);
    });
    _applyFilters();

    try {
      await context.read<WebsiteService>().replaceWebsiteCategoryVisibility(
            tenantId: tenantId,
            visibleCategoryIds: selected,
          );

      await _clearProductCaches(
        tenantId,
        refreshCategories: true,
      );
      _showSnackBar('Categorías públicas actualizadas.');
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _websiteCategories = previous);
        _applyFilters();
      }
      _showSnackBar('No se pudieron guardar las categorías: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isSavingRules = false);
    }
  }

  void _openCategorySelectionPage() {
    setState(() {
      _categoryDraftSelection
        ..clear()
        ..addAll(_visibleWebsiteCategoryIds);
      _categorySearchController.clear();
      _categoryProductCountFilter = _CategoryProductCountFilter.all;
      _showCategorySelectionPage = true;
    });
  }

  Future<void> _closeCategorySelectionPage() async {
    if (widget.section == WebsiteCatalogSection.categories) return;
    if (!_categoryDraftHasChanges) {
      setState(() => _showCategorySelectionPage = false);
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar cambios'),
        content: const Text(
          'Hay cambios de categorías sin guardar. Si sales ahora se perderán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      setState(() => _showCategorySelectionPage = false);
    }
  }

  Future<void> _saveCategorySelectionPage() async {
    final saved = await _saveWebsiteCategories(_categoryDraftSelection);
    if (saved && mounted && widget.section == WebsiteCatalogSection.products) {
      setState(() => _showCategorySelectionPage = false);
    }
  }

  void _discardCategorySelectionChanges() {
    setState(() {
      _categoryDraftSelection
        ..clear()
        ..addAll(_visibleWebsiteCategoryIds);
      if (widget.section == WebsiteCatalogSection.products) {
        _showCategorySelectionPage = false;
      }
    });
  }

  Future<void> _saveWebsiteSettings(
    Map<String, String> settings, {
    required String tenantId,
  }) async {
    try {
      final service = context.read<WebsiteService>();
      await service.saveSettings(settings);
      return;
    } catch (_) {
      // Some embedded contexts may not expose WebsiteService; write directly.
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();
    for (final entry in settings.entries) {
      final updated = await _supabase
          .from('website_settings')
          .update({
            'value': entry.value,
            'updated_at': timestamp,
          })
          .eq('tenant_id', tenantId)
          .eq('key', entry.key)
          .select('id');

      if ((updated as List).isEmpty) {
        await _supabase.from('website_settings').insert({
          'tenant_id': tenantId,
          'key': entry.key,
          'value': entry.value,
          'updated_at': timestamp,
        });
      }
    }
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

  void _clearTableFilters() {
    _kindFilters.clear();
    _visibilityFilters.clear();
    _activeFilters.clear();
    _readinessFilters.clear();
    _stockFilters.clear();
    _selectedCategoryIds.clear();
    _selectedBrandIds.clear();
  }

  void _showPublicCatalogListView(_PublicCatalogListView view) {
    setState(() {
      _publicCatalogListView = view;
      _selectedProductIds.clear();
    });
    _applyFilters();
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

  Set<String> get _visibleWebsiteCategoryIds => _websiteCategories
      .where((category) => category.showOnWebsite)
      .map((category) => category.id)
      .toSet();

  bool get _categoryDraftHasChanges {
    final live = _visibleWebsiteCategoryIds;
    if (live.length != _categoryDraftSelection.length) return true;
    return !_categoryDraftSelection.every(live.contains);
  }

  Map<String, int> get _categoryProductCounts {
    final counts = <String, int>{};
    for (final product in _products) {
      final id = product.categoryId?.trim();
      if (id == null || id.isEmpty) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get _categoryMarkedWebCounts {
    final counts = <String, int>{};
    for (final product in _products) {
      final id = product.categoryId?.trim();
      if (id == null || id.isEmpty || !product.isVisibleOnWebsite) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  List<_WebsiteCategoryVisibilityOption> get _selectedCategorySelectionRows {
    final rows = _websiteCategories
        .where((category) => _categoryDraftSelection.contains(category.id))
        .toList(growable: false);
    rows.sort((a, b) => a.label.compareTo(b.label));
    return rows;
  }

  int get _markedWebCount =>
      _products.where((product) => product.isVisibleOnWebsite).length;
  int get _publicProductCount {
    final categoryIds = _visibleWebsiteCategoryIds;
    return _products
        .where((product) => product.isVisibleInPublicProductsCatalog(
              _visibilityPolicy,
              categoryIds,
            ))
        .length;
  }

  int get _publicServiceCount {
    final categoryIds = _visibleWebsiteCategoryIds;
    return _products
        .where((product) => product.isVisibleInPublicServicesCatalog(
              _visibilityPolicy,
              categoryIds,
            ))
        .length;
  }

  int get _policyBlockedWebCount {
    final categoryIds = _visibleWebsiteCategoryIds;
    return _products
        .where((product) =>
            product.isVisibleOnWebsite &&
            !product.matchesPublicVisibilityPolicy(
              _visibilityPolicy,
              categoryIds,
            ))
        .length;
  }

  int get _missingImageCount =>
      _products.where((product) => !product.hasImage).length;

  int get _missingDescriptionCount =>
      _products.where((product) => !product.hasWebsiteDescription).length;

  String get _visibleWebsiteCategorySummary {
    final labels = _websiteCategories
        .where((category) => category.showOnWebsite)
        .map((category) => category.shortLabel)
        .toList(growable: false)
      ..sort();
    return labels.isEmpty ? 'Ninguna categoría pública' : labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WebsiteAdminShell(
      embedded: widget.embedded,
      showHeaderWhenEmbedded: false,
      title: switch (widget.section) {
        WebsiteCatalogSection.categories => 'Categorías del catálogo',
        WebsiteCatalogSection.products => 'Catálogo web',
      },
      description: switch (widget.section) {
        WebsiteCatalogSection.categories =>
          'Decide qué familias organizan la experiencia pública.',
        WebsiteCatalogSection.products =>
          'Controla qué productos y servicios puede encontrar el cliente.',
      },
      actions: [
        IconButton.outlined(
          tooltip: 'Actualizar catálogo',
          onPressed: _isApplying ? null : _refreshWorkspace,
          icon: const Icon(Icons.refresh_rounded, size: 19),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading)
            const Expanded(child: Center(child: BrandedLoading()))
          else if (_error != null)
            Expanded(child: _buildErrorState(theme))
          else if (_showCategorySelectionPage)
            Expanded(child: _buildCategorySelectionPage(theme))
          else ...[
            _buildSummaryStrip(theme),
            if (_showPublicRules) _buildPublicRulesPanel(theme),
            if (_showAdvancedFilters) _buildFilterPanel(theme),
            _buildActionBar(theme),
            Expanded(child: _buildProductTable(theme)),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(ThemeData theme) {
    final activeFilterCount = _activeTableFilterCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1160;
          final search = SizedBox(
            width: compact ? constraints.maxWidth : 420,
            height: 40,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: widget.kind == WebsiteCatalogItemKind.services
                    ? 'Buscar por servicio o código'
                    : 'Buscar por producto, SKU o marca',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
          );

          final viewControl = _buildCatalogViewMenu(theme);
          final filtersControl = _buildToolbarActionButton(
            theme,
            icon: _showAdvancedFilters
                ? Icons.filter_alt_off_outlined
                : Icons.filter_alt_outlined,
            label: activeFilterCount == 0
                ? 'Filtros'
                : 'Filtros ($activeFilterCount)',
            selected: _showAdvancedFilters || activeFilterCount > 0,
            onPressed: () => setState(() {
              _showAdvancedFilters = !_showAdvancedFilters;
              if (_showAdvancedFilters) _showPublicRules = false;
            }),
          );
          final rulesControl = Tooltip(
            message: _publicRulesSummary,
            child: _buildToolbarActionButton(
              theme,
              icon: Icons.tune_outlined,
              label: 'Reglas públicas',
              selected: _showPublicRules,
              onPressed: () => setState(() {
                _showPublicRules = !_showPublicRules;
                if (_showPublicRules) _showAdvancedFilters = false;
              }),
            ),
          );
          final actionsControl = _buildResultActionsMenu(theme);
          final refreshControl = _buildToolbarActionButton(
            theme,
            icon: Icons.refresh_rounded,
            tooltip: 'Actualizar catálogo',
            compact: true,
            onPressed: _isApplying ? null : _loadProducts,
          );
          final resultCount = Text(
            '${_filteredProducts.length} de ${_products.length}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          );

          final compactControls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              viewControl,
              filtersControl,
              rulesControl,
              actionsControl,
              refreshControl,
              resultCount,
            ],
          );

          final toolbar = compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 8),
                    compactControls,
                  ],
                )
              : Row(
                  children: [
                    search,
                    const SizedBox(width: 12),
                    viewControl,
                    const SizedBox(width: 8),
                    filtersControl,
                    const SizedBox(width: 8),
                    rulesControl,
                    const Spacer(),
                    resultCount,
                    const SizedBox(width: 12),
                    actionsControl,
                    const SizedBox(width: 8),
                    refreshControl,
                  ],
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toolbar,
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 4),
              _buildCatalogOverview(theme),
              if (_showCatalogSummaryDetails) ...[
                const SizedBox(height: 4),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 10),
                _buildCatalogSummaryDetails(theme),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCatalogOverview(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final metricChildren = <Widget>[
          _buildCatalogOverviewMetric(
            theme,
            value: _publicProductCount.toString(),
            label: 'Productos públicos',
            tooltip: 'Ver los productos que realmente aparecen en /productos.',
            selected:
                _publicCatalogListView == _PublicCatalogListView.publicProducts,
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.publicProducts,
            ),
          ),
          _buildCatalogOverviewMetric(
            theme,
            value:
                '${_visibleWebsiteCategoryIds.length} / ${_websiteCategories.length}',
            label: 'Categorías en navegación',
            tooltip:
                'Aparecen como filtros en la tienda. No limitan los productos salvo que actives “Limitar catálogo por categoría”.',
            onTap: _openCategorySelectionPage,
          ),
          _buildCatalogOverviewMetric(
            theme,
            value: _policyBlockedWebCount.toString(),
            label: 'Bloqueados por reglas',
            tooltip: 'Ver los artículos marcados para web que no se publican.',
            selected:
                _publicCatalogListView == _PublicCatalogListView.hiddenByRules,
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.hiddenByRules,
            ),
          ),
        ];
        final compactMetrics = Wrap(
          spacing: 2,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: metricChildren,
        );
        final disclosure = TextButton.icon(
          onPressed: () => setState(() {
            _showCatalogSummaryDetails = !_showCatalogSummaryDetails;
          }),
          icon: Icon(
            _showCatalogSummaryDetails
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            size: 18,
          ),
          label: Text(
            _showCatalogSummaryDetails ? 'Ocultar desglose' : 'Ver desglose',
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              compactMetrics,
              Align(alignment: Alignment.centerRight, child: disclosure),
            ],
          );
        }

        return Row(
          children: [
            Text(
              'PUBLICACIÓN',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0;
                        index < metricChildren.length;
                        index++) ...[
                      Expanded(child: metricChildren[index]),
                      if (index != metricChildren.length - 1)
                        VerticalDivider(
                          width: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            disclosure,
          ],
        );
      },
    );
  }

  Widget _buildCatalogOverviewMetric(
    ThemeData theme, {
    required String value,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final foreground =
        selected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCatalogSummaryDetails(ThemeData theme) {
    final sections = [
      _buildCatalogBreakdownSection(
        theme,
        title: 'Publicación',
        children: [
          _buildCatalogBreakdownRow(
            theme,
            label: 'Productos públicos',
            value: _publicProductCount.toString(),
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.publicProducts,
            ),
          ),
          _buildCatalogBreakdownRow(
            theme,
            label: 'Servicios públicos',
            value: _publicServiceCount.toString(),
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.publicServices,
            ),
          ),
          _buildCatalogBreakdownRow(
            theme,
            label: 'Marcados para web',
            value: _markedWebCount.toString(),
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.markedWeb,
            ),
          ),
          _buildCatalogBreakdownRow(
            theme,
            label: 'Total en ERP',
            value: _products.length.toString(),
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.all,
            ),
          ),
        ],
      ),
      _buildCatalogBreakdownSection(
        theme,
        title: 'Preparación web',
        children: [
          _buildCatalogBreakdownRow(
            theme,
            label: 'Bloqueados por reglas',
            value: _policyBlockedWebCount.toString(),
            onTap: () => _showPublicCatalogListView(
              _PublicCatalogListView.hiddenByRules,
            ),
          ),
          _buildCatalogBreakdownRow(
            theme,
            label: 'Sin imagen',
            value: _missingImageCount.toString(),
          ),
          _buildCatalogBreakdownRow(
            theme,
            label: 'Sin descripción web',
            value: _missingDescriptionCount.toString(),
          ),
        ],
      ),
      _buildCatalogBreakdownSection(
        theme,
        title:
            'Navegación por categoría · ${_visibleWebsiteCategoryIds.length} de ${_websiteCategories.length}',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _visibleWebsiteCategorySummary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openCategorySelectionPage,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Configurar navegación'),
            ),
          ),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < sections.length; index++) ...[
                sections[index],
                if (index != sections.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < sections.length; index++) ...[
                Expanded(child: sections[index]),
                if (index != sections.length - 1) ...[
                  const SizedBox(width: 18),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  const SizedBox(width: 18),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCatalogBreakdownSection(
    ThemeData theme, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        ...children,
      ],
    );
  }

  Widget _buildCatalogBreakdownRow(
    ThemeData theme, {
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: row,
    );
  }

  Widget _buildToolbarActionButton(
    ThemeData theme, {
    required IconData icon,
    required VoidCallback? onPressed,
    String? label,
    String? tooltip,
    bool selected = false,
    bool compact = false,
  }) {
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final button = SizedBox(
      height: 40,
      width: compact ? 40 : null,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.07)
              : theme.colorScheme.surface,
          disabledForegroundColor:
              theme.colorScheme.onSurface.withValues(alpha: 0.38),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : theme.colorScheme.outlineVariant,
          ),
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
          minimumSize: Size(compact ? 40 : 0, 40),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: compact ? const SizedBox.shrink() : Text(label ?? ''),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  int get _activeTableFilterCount {
    var count = 0;
    if (_kindFilters.isNotEmpty) count++;
    if (_visibilityFilters.isNotEmpty) count++;
    if (_activeFilters.isNotEmpty) count++;
    if (_readinessFilters.isNotEmpty) count++;
    if (_stockFilters.isNotEmpty) count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    if (_selectedBrandIds.isNotEmpty) count++;
    return count;
  }

  String get _publicRulesSummary {
    final parts = <String>[
      'Stock: ${_visibilityPolicy.stockPolicy.label.toLowerCase()}',
      _visibilityPolicy.requireImage ? 'imagen obligatoria' : 'imagen opcional',
    ];
    if (_visibilityPolicy.requireVisibleCategory) {
      parts.add(
        'catálogo limitado a ${_visibleWebsiteCategoryIds.length} categorías',
      );
    } else {
      parts.add('categorías solo para navegación');
    }
    return parts.join(' · ');
  }

  int _countForCatalogView(_PublicCatalogListView view) {
    switch (view) {
      case _PublicCatalogListView.all:
        return _products.length;
      case _PublicCatalogListView.publicProducts:
        return _publicProductCount;
      case _PublicCatalogListView.publicServices:
        return _publicServiceCount;
      case _PublicCatalogListView.markedWeb:
        return _markedWebCount;
      case _PublicCatalogListView.hiddenByRules:
        return _policyBlockedWebCount;
    }
  }

  Widget _buildCatalogViewMenu(ThemeData theme) {
    return PopupMenuButton<_PublicCatalogListView>(
      tooltip: 'Cambiar vista del catálogo',
      initialValue: _publicCatalogListView,
      onSelected: _showPublicCatalogListView,
      itemBuilder: (context) => _PublicCatalogListView.values
          .map(
            (view) => CheckedPopupMenuItem<_PublicCatalogListView>(
              value: view,
              checked: view == _publicCatalogListView,
              child: SizedBox(
                width: 230,
                child: Row(
                  children: [
                    Icon(view.icon, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(view.label)),
                    Text(_countForCatalogView(view).toString()),
                  ],
                ),
              ),
            ),
          )
          .toList(growable: false),
      child: _buildToolbarMenuButton(
        theme,
        icon: _publicCatalogListView.icon,
        label: _publicCatalogListView.label,
      ),
    );
  }

  Widget _buildResultActionsMenu(ThemeData theme) {
    final enabled = !_isApplying && _filteredProducts.isNotEmpty;
    final backgroundColor = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final foregroundColor = enabled
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final borderColor =
        enabled ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Publicar el resultado actual',
            child: Semantics(
              button: true,
              enabled: enabled,
              label: 'Publicar el resultado actual',
              child: InkWell(
                onTap: enabled
                    ? () => _confirmAndRunResultAction(
                          _CatalogResultAction.publish,
                        )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: foregroundColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Publicar',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: enabled
                ? theme.colorScheme.onPrimary.withValues(alpha: 0.28)
                : theme.colorScheme.outlineVariant,
          ),
          PopupMenuButton<_CatalogResultAction>(
            tooltip: 'Otras acciones sobre el resultado',
            enabled: enabled,
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            elevation: 8,
            color: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            onSelected: _confirmAndRunResultAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _CatalogResultAction.hide,
                height: 58,
                child: _CatalogActionMenuItem(
                  icon: Icons.visibility_off_outlined,
                  title: 'Ocultar resultado',
                  subtitle: 'Quita el marcado web de estas filas',
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _CatalogResultAction.replaceCatalog,
                height: 64,
                child: _CatalogActionMenuItem(
                  icon: Icons.filter_alt_outlined,
                  title: 'Usar resultado como catálogo',
                  subtitle: 'Oculta todo lo que quede fuera',
                ),
              ),
            ],
            child: SizedBox(
              width: 36,
              height: 40,
              child: Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarMenuButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    final foregroundColor = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_drop_down, size: 18, color: foregroundColor),
        ],
      ),
    );
  }

  Widget _buildPublicRulesPanel(ThemeData theme) {
    final selectedCategoryIds = _visibleWebsiteCategoryIds;
    final saving = _isSavingRules || _isApplying;

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
          final compact = constraints.maxWidth < 900;
          final categoryWidth = compact
              ? constraints.maxWidth
              : math.min(360.0, constraints.maxWidth);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tune_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reglas del catálogo público',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (saving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? constraints.maxWidth : 300,
                    child: _buildStockPolicySelector(theme, saving),
                  ),
                  _buildRuleSwitch(
                    theme,
                    label: 'Requerir imagen',
                    value: _visibilityPolicy.requireImage,
                    enabled: !saving,
                    onChanged: (value) => _saveVisibilityPolicy(
                      _visibilityPolicy.copyWith(requireImage: value),
                    ),
                  ),
                  _buildRuleSwitch(
                    theme,
                    label: 'Limitar catálogo por categoría',
                    tooltip:
                        'Activado: solo se publican productos de las categorías visibles en la tienda. Desactivado: esas categorías siguen apareciendo como filtros, pero no restringen los productos.',
                    value: _visibilityPolicy.requireVisibleCategory,
                    enabled: !saving,
                    onChanged: (value) => _saveVisibilityPolicy(
                      _visibilityPolicy.copyWith(
                        requireVisibleCategory: value,
                      ),
                    ),
                  ),
                  if (_visibilityPolicy.requireVisibleCategory)
                    _buildRuleSwitch(
                      theme,
                      label: 'Incluir sin categoría',
                      tooltip:
                          'Permite publicar productos sin categoría aunque el catálogo esté limitado por categoría.',
                      value: _visibilityPolicy.includeUncategorized,
                      enabled: !saving,
                      onChanged: (value) => _saveVisibilityPolicy(
                        _visibilityPolicy.copyWith(
                          includeUncategorized: value,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: categoryWidth,
                    child: _buildCategorySelectionEntry(
                      theme,
                      selectedCategoryIds: selectedCategoryIds,
                      enabled: !saving,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategorySelectionEntry(
    ThemeData theme, {
    required Set<String> selectedCategoryIds,
    required bool enabled,
  }) {
    final selectedCount = selectedCategoryIds.length;
    final summary = _categorySelectionSummaryText(selectedCategoryIds);
    final tooltip = _visibilityPolicy.requireVisibleCategory
        ? 'Aparecen como filtros en la tienda y la regla activa limita el catálogo a esta selección.'
        : 'Aparecen como filtros en la tienda. En este momento no limitan qué productos se publican.';

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? _openCategorySelectionPage : null,
        child: InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Categorías en navegación',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selectedCount == 0
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        selectedCount == 0 ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$selectedCount/${_websiteCategories.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categorySelectionSummaryText(Set<String> selectedCategoryIds) {
    if (selectedCategoryIds.isEmpty) return 'Ninguna seleccionada';
    final labels = _websiteCategories
        .where((category) => selectedCategoryIds.contains(category.id))
        .map((category) => category.shortLabel)
        .toList(growable: false);
    if (labels.isEmpty) return '${selectedCategoryIds.length} seleccionadas';
    if (labels.length <= 2) return labels.join(', ');
    return '${labels.take(2).join(', ')} +${labels.length - 2}';
  }

  Widget _buildStockPolicySelector(ThemeData theme, bool saving) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Stock público',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: SegmentedButton<PublicCatalogStockPolicy>(
        showSelectedIcon: false,
        segments: PublicCatalogStockPolicy.values
            .map((policy) => ButtonSegment<PublicCatalogStockPolicy>(
                  value: policy,
                  label: Text(policy.label),
                ))
            .toList(growable: false),
        selected: {_visibilityPolicy.stockPolicy},
        onSelectionChanged: saving
            ? null
            : (values) {
                final next = values.first;
                _saveVisibilityPolicy(
                  _visibilityPolicy.copyWith(stockPolicy: next),
                );
              },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
        ),
      ),
    );
  }

  Widget _buildRuleSwitch(
    ThemeData theme, {
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    String? tooltip,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (tooltip != null) ...[
            const SizedBox(width: 5),
            Tooltip(
              message: tooltip,
              waitDuration: const Duration(milliseconds: 350),
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelectionPage(ThemeData theme) {
    final productCounts = _categoryProductCounts;
    final markedWebCounts = _categoryMarkedWebCounts;
    final rows = _filteredCategorySelectionRows(productCounts);
    final selectedRows = _selectedCategorySelectionRows;
    final selectedProductsCount = _categoryDraftSelection.fold<int>(
      0,
      (sum, id) => sum + (productCounts[id] ?? 0),
    );
    final saving = _isSavingRules || _isApplying;
    final categoryScopeSummary = _visibilityPolicy.requireVisibleCategory
        ? 'No reasigna productos; la regla activa limita el catálogo a esta selección.'
        : 'No reasigna productos ni limita el catálogo.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.section == WebsiteCatalogSection.products) ...[
                IconButton(
                  tooltip: 'Volver a productos',
                  onPressed: saving ? null : _closeCategorySelectionPage,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categorías en navegación',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_categoryDraftSelection.length} de ${_websiteCategories.length} visibles · '
                      '$selectedProductsCount productos asociados. $categoryScopeSummary',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: saving ? null : _discardCategorySelectionChanges,
                child: const Text('Descartar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: saving || !_categoryDraftHasChanges
                    ? null
                    : _saveCategorySelectionPage,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCategorySelectionToolbar(theme, rows.length),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1040;
                final selectedBlock = _buildCategoryListBlock(
                  theme,
                  title: 'En navegación',
                  subtitle: 'Aparecen como filtros en la tienda',
                  rows: selectedRows,
                  productCounts: productCounts,
                  markedWebCounts: markedWebCounts,
                  saving: saving,
                  selectedList: true,
                  emptyMessage: 'No hay categorías seleccionadas.',
                );
                final availableBlock = _buildCategoryListBlock(
                  theme,
                  title: 'Fuera de navegación',
                  subtitle: 'No aparecen como filtros en la tienda',
                  rows: rows,
                  productCounts: productCounts,
                  markedWebCounts: markedWebCounts,
                  saving: saving,
                  selectedList: false,
                  emptyMessage: _categorySearchController.text.trim().isEmpty
                      ? 'No quedan categorías disponibles.'
                      : 'Sin categorías para este filtro.',
                );

                if (compact) {
                  return Column(
                    children: [
                      Expanded(child: availableBlock),
                      const SizedBox(height: 10),
                      Expanded(child: selectedBlock),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: availableBlock),
                    const SizedBox(width: 24),
                    Expanded(child: selectedBlock),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySelectionToolbar(ThemeData theme, int visibleRows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final searchWidth = compact
            ? constraints.maxWidth
            : math.min(360.0, constraints.maxWidth);

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: _categorySearchController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Buscar categoría o ruta...',
                  suffixIcon: _categorySearchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _categorySearchController.clear,
                        ),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
              ),
            ),
            _buildCategorySegmentedFilter<_CategoryProductCountFilter>(
              theme,
              values: _CategoryProductCountFilter.values,
              selected: _categoryProductCountFilter,
              labelFor: (value) => value.label,
              onChanged: (value) =>
                  setState(() => _categoryProductCountFilter = value),
            ),
            Text(
              '$visibleRows resultados',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryListBlock(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required List<_WebsiteCategoryVisibilityOption> rows,
    required Map<String, int> productCounts,
    required Map<String, int> markedWebCounts,
    required bool saving,
    required bool selectedList,
    required String emptyMessage,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: Row(
              children: [
                Icon(
                  selectedList
                      ? Icons.checklist_rtl_outlined
                      : Icons.list_alt_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title (${rows.length})',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedList)
                  TextButton(
                    onPressed: saving || rows.isEmpty
                        ? null
                        : () => setState(_categoryDraftSelection.clear),
                    child: const Text('Quitar todas'),
                  )
                else
                  TextButton(
                    onPressed: saving || rows.isEmpty
                        ? null
                        : () {
                            setState(() {
                              _categoryDraftSelection.addAll(
                                rows.map((category) => category.id),
                              );
                            });
                          },
                    child: const Text('Agregar resultados'),
                  ),
              ],
            ),
          ),
          _buildCategorySelectionHeader(theme),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      emptyMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final category = rows[index];
                      return _buildCategorySelectionRow(
                        theme,
                        category,
                        productCount: productCounts[category.id] ?? 0,
                        markedWebCount: markedWebCounts[category.id] ?? 0,
                        saving: saving,
                        selectedList: selectedList,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySegmentedFilter<T>(
    ThemeData theme, {
    required List<T> values,
    required T selected,
    required String Function(T value) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      selected: {selected},
      segments: values
          .map((value) => ButtonSegment<T>(
                value: value,
                label: Text(labelFor(value)),
              ))
          .toList(growable: false),
      onSelectionChanged: (values) => onChanged(values.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
      ),
    );
  }

  Widget _buildCategorySelectionHeader(ThemeData theme) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(
            child: Text(
              'Categoría',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: 78,
            child: Tooltip(
              message: 'Productos en esta categoría',
              child: Text(
                'Prod.',
                textAlign: TextAlign.right,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Tooltip(
              message:
                  'Productos con publicación web activada en esta categoría; las reglas públicas todavía pueden ocultarlos.',
              child: Text(
                'Web',
                textAlign: TextAlign.right,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildCategorySelectionRow(
    ThemeData theme,
    _WebsiteCategoryVisibilityOption category, {
    required int productCount,
    required int markedWebCount,
    required bool saving,
    required bool selectedList,
  }) {
    return InkWell(
      onTap: saving
          ? null
          : () {
              setState(() {
                if (selectedList) {
                  _categoryDraftSelection.remove(category.id);
                } else {
                  _categoryDraftSelection.add(category.id);
                }
              });
            },
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: selectedList ? 'Quitar' : 'Agregar',
                onPressed: saving
                    ? null
                    : () {
                        setState(() {
                          if (selectedList) {
                            _categoryDraftSelection.remove(category.id);
                          } else {
                            _categoryDraftSelection.add(category.id);
                          }
                        });
                      },
                icon: Icon(
                  selectedList
                      ? Icons.remove_circle_outline
                      : Icons.add_circle_outline,
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selectedList &&
                      category.showOnWebsite &&
                      widget.onOpenCategoryPage != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      key: ValueKey('catalog-open-category-${category.id}'),
                      onPressed: () => widget.onOpenCategoryPage!(
                        category.id,
                        category.shortLabel,
                        services: _categoryListsOnlyServices(category.id),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text('Su página'),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 78,
              child: Text(
                productCount.toString(),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            SizedBox(
              width: 86,
              child: Text(
                markedWebCount.toString(),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            SizedBox(
              width: 44,
              child: Icon(
                selectedList
                    ? Icons.keyboard_arrow_left_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A category whose items are all services lives under /servicios.
  bool _categoryListsOnlyServices(String categoryId) {
    var any = false;
    for (final product in _products) {
      if (product.categoryId != categoryId) continue;
      if (!product.isService) return false;
      any = true;
    }
    return any;
  }

  List<_WebsiteCategoryVisibilityOption> _filteredCategorySelectionRows(
    Map<String, int> productCounts,
  ) {
    final query = _normalizeSearch(_categorySearchController.text);
    final rows = _websiteCategories.where((category) {
      if (_categoryDraftSelection.contains(category.id)) return false;
      if (query.isNotEmpty &&
          !_normalizeSearch(category.label).contains(query)) {
        return false;
      }

      final count = productCounts[category.id] ?? 0;
      switch (_categoryProductCountFilter) {
        case _CategoryProductCountFilter.all:
          return true;
        case _CategoryProductCountFilter.withProducts:
          return count > 0;
        case _CategoryProductCountFilter.empty:
          return count == 0;
      }
    }).toList(growable: false);
    rows.sort((a, b) => a.label.compareTo(b.label));
    return rows;
  }

  Widget _buildFilterPanel(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnCount = constraints.maxWidth >= 1200
              ? 7
              : constraints.maxWidth >= 820
                  ? 4
                  : constraints.maxWidth >= 520
                      ? 2
                      : 1;
          const spacing = 10.0;
          final fieldWidth =
              (constraints.maxWidth - (spacing * (columnCount - 1))) /
                  columnCount;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filtros de esta lista',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _activeTableFilterCount == 0 ? null : _resetFilters,
                    child: const Text('Limpiar filtros'),
                  ),
                  IconButton(
                    tooltip: 'Cerrar filtros',
                    onPressed: () =>
                        setState(() => _showAdvancedFilters = false),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.kind == null)
                    SizedBox(
                      width: fieldWidth,
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
                    width: fieldWidth,
                    child: _buildEnumMultiSelectFilter<_VisibilityFilter>(
                      label: 'Marcado web',
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
                    width: fieldWidth,
                    child: _buildEnumMultiSelectFilter<_ActiveFilter>(
                      label: 'Estado ERP',
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
                    width: fieldWidth,
                    child: _buildEnumMultiSelectFilter<_ReadinessFilter>(
                      label: 'Preparación web',
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
                    width: fieldWidth,
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
                    width: fieldWidth,
                    child: Tooltip(
                      message:
                          'Solo filtra esta lista; no cambia las categorías públicas.',
                      child: _buildOptionMultiSelectFilter(
                        label: 'Categoría del producto',
                        options: _categoryOptions,
                        selectedIds: _selectedCategoryIds,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _buildOptionMultiSelectFilter(
                      label: 'Marca',
                      options: _brandOptions,
                      selectedIds: _selectedBrandIds,
                    ),
                  ),
                ],
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
      _clearTableFilters();
    });
    _applyFilters();
  }

  Widget _buildActionBar(ThemeData theme) {
    final selectedRows = _selectedProducts;
    if (selectedRows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${selectedRows.length} seleccionado${selectedRows.length == 1 ? '' : 's'}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          FilledButton.icon(
            onPressed: _isApplying
                ? null
                : () => _setProductsVisibility(selectedRows, true),
            icon: _isApplying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.visibility_outlined),
            label: const Text('Publicar'),
          ),
          OutlinedButton.icon(
            onPressed: _isApplying
                ? null
                : () => _setProductsVisibility(selectedRows, false),
            icon: const Icon(Icons.visibility_off_outlined),
            label: const Text('Ocultar'),
          ),
          TextButton(
            onPressed:
                _isApplying ? null : () => setState(_selectedProductIds.clear),
            child: const Text('Cancelar selección'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTable(ThemeData theme) {
    if (_filteredProducts.isEmpty) {
      final message = _publicCatalogListView == _PublicCatalogListView.all
          ? 'No hay productos para el filtro actual.'
          : 'No hay filas para ${_publicCatalogListView.label.toLowerCase()}.';
      return Center(
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _CatalogTableMetrics.forWidth(
          constraints.maxWidth,
          showType: widget.kind == null,
          showStock: widget.kind != WebsiteCatalogItemKind.services,
        );
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
              width: metrics.totalWidth,
              child: Column(
                children: [
                  _buildTableHeader(
                    theme,
                    metrics: metrics,
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
                          metrics,
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
    required _CatalogTableMetrics metrics,
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
            width: _CatalogTableMetrics.selection,
            child: Checkbox(
              value: hasPartialSelection ? null : allFilteredSelected,
              tristate: true,
              onChanged: (value) => _toggleFilteredSelection(value == true),
            ),
          ),
          _buildHeaderCell(theme, 'Producto', width: metrics.product),
          if (metrics.type > 0)
            _buildHeaderCell(theme, 'Tipo', width: metrics.type),
          _buildHeaderCell(theme, 'Marcado web', width: metrics.web),
          _buildHeaderCell(theme, 'En la tienda', width: metrics.status),
          _buildHeaderCell(theme, 'Calidad web', width: metrics.readiness),
          _buildHeaderCell(theme, 'Categoría', width: metrics.category),
          _buildHeaderCell(theme, 'Marca', width: metrics.brand),
          if (metrics.stock > 0)
            _buildHeaderCell(theme, 'Stock', width: metrics.stock),
          _buildHeaderCell(
            theme,
            'Precio',
            width: metrics.price,
            alignRight: true,
          ),
          const SizedBox(width: _CatalogTableMetrics.action),
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
    ThemeData theme,
    _WebsiteProductVisibilityRow product,
    _CatalogTableMetrics metrics,
  ) {
    final selected = _selectedProductIds.contains(product.id);
    final VoidCallback? editWebsite = _isApplying
        ? null
        : () {
            _openProductWebsiteEditor(product);
          };
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : theme.colorScheme.surface,
      child: Row(
        children: [
          SizedBox(
            width: _CatalogTableMetrics.selection,
            child: Checkbox(
              value: selected,
              onChanged: (value) => _toggleSelected(product.id, value == true),
            ),
          ),
          SizedBox(
            width: metrics.product,
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
          if (metrics.type > 0)
            SizedBox(width: metrics.type, child: Text(product.typeLabel)),
          SizedBox(
            width: metrics.web,
            child: _buildWebIntentSwitch(theme, product),
          ),
          SizedBox(
            width: metrics.status,
            child: _buildPublicStatusBadge(product),
          ),
          SizedBox(
            width: metrics.readiness,
            child: _buildReadinessStatus(theme, product),
          ),
          SizedBox(
            width: metrics.category,
            child: Text(
              product.categoryLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: metrics.brand,
            child: Text(
              product.brandLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (metrics.stock > 0)
            SizedBox(width: metrics.stock, child: Text(product.stockLabel)),
          SizedBox(
            width: metrics.price,
            child: Text(
              ChileanUtils.formatCurrency(product.price),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: _CatalogTableMetrics.action,
            child: Semantics(
              button: true,
              enabled: editWebsite != null,
              label: 'Editar página web de ${product.name}',
              onTap: editWebsite,
              child: ExcludeSemantics(
                child: IconButton(
                  tooltip: 'Editar página web del producto',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: editWebsite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProductWebsiteEditor(
    _WebsiteProductVisibilityRow product,
  ) async {
    final saved = await showProductEditorDialog(
      context: context,
      productId: product.id,
      initialProductType:
          product.isService ? ProductType.service : ProductType.product,
      initialSection: ProductFormSection.website,
    );

    if (saved == true && mounted) {
      await _loadProducts();
    }
  }

  Widget _buildWebIntentSwitch(
    ThemeData theme,
    _WebsiteProductVisibilityRow product,
  ) {
    final visibleCategoryIds = _visibleWebsiteCategoryIds;
    final blocked = product.isHiddenFromPublicByPolicy(
      _visibilityPolicy,
      visibleCategoryIds,
    );
    final canChange = !_isApplying && product.isActive;
    final tooltip = blocked
        ? '${product.publicVisibilityTooltip(_visibilityPolicy, visibleCategoryIds)} Sigue encendido porque el producto permanece marcado para web.'
        : product.isMarkedForWebsite
            ? 'Marcado para web y publicado. Desactívalo para quitarlo de la web.'
            : product.isActive
                ? 'No está marcado para web. Actívalo para solicitar su publicación.'
                : 'Producto inactivo: no se puede cambiar su marcado web.';

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: '${product.name}: marcado para web',
        value: product.isMarkedForWebsite ? 'Sí' : 'No',
        child: Align(
          alignment: Alignment.centerLeft,
          child: Switch(
            value: product.isMarkedForWebsite,
            onChanged: canChange
                ? (value) => _setProductsVisibility([product], value)
                : null,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return theme.colorScheme.onSurface.withValues(alpha: 0.38);
              }
              if (states.contains(WidgetState.selected)) return Colors.white;
              return theme.colorScheme.onSurfaceVariant;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return product.isMarkedForWebsite
                    ? const Color(0xFFBCC5BF)
                    : theme.colorScheme.surfaceContainerHighest;
              }
              if (!states.contains(WidgetState.selected)) {
                return theme.colorScheme.surfaceContainerHighest;
              }
              return blocked
                  ? const Color(0xFF8F9F94)
                  : theme.colorScheme.primary;
            }),
            trackOutlineColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return blocked
                    ? const Color(0xFF77877C)
                    : theme.colorScheme.primary;
              }
              return theme.colorScheme.outlineVariant;
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildPublicStatusBadge(_WebsiteProductVisibilityRow product) {
    final visibleCategoryIds = _visibleWebsiteCategoryIds;
    final blocked = product.isHiddenFromPublicByPolicy(
      _visibilityPolicy,
      visibleCategoryIds,
    );
    final published = product.matchesPublicVisibilityPolicy(
      _visibilityPolicy,
      visibleCategoryIds,
    );

    final String label;
    final Color accentColor;
    if (!product.isActive) {
      label = 'Inactivo';
      accentColor = const Color(0xFF94A3B8);
    } else if (blocked) {
      // Why it does not show, in the row itself: «Sin stock», «Sin foto»…
      // (the sentence stays in the tooltip).
      label =
          product.publicBlockReason(_visibilityPolicy, visibleCategoryIds) ??
              'No sale';
      accentColor = const Color(0xFF9A742F);
    } else if (published) {
      label = 'Publicado';
      accentColor = const Color(0xFF5F7D68);
    } else {
      label = 'Oculto';
      accentColor = const Color(0xFF64748B);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: OperationalStatusBadge(
        label: label,
        accentColor: accentColor,
        maxWidth: 108,
        compact: true,
        tooltip: product.publicVisibilityTooltip(
          _visibilityPolicy,
          visibleCategoryIds,
        ),
      ),
    );
  }

  Widget _buildReadinessStatus(
    ThemeData theme,
    _WebsiteProductVisibilityRow product,
  ) {
    final missing = <String>[
      if (!product.hasImage) 'imagen',
      if (!product.hasWebsiteDescription) 'texto web',
    ];
    final ready = missing.isEmpty;
    final color = ready ? theme.colorScheme.primary : theme.colorScheme.error;
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle_outline : Icons.error_outline,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ready ? 'Lista para web' : 'Falta ${missing.join(' y ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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

class _CatalogActionMenuItem extends StatelessWidget {
  const _CatalogActionMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CatalogActionConfirmationDialog extends StatelessWidget {
  const _CatalogActionConfirmationDialog({
    required this.confirmation,
  });

  final _CatalogActionConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = ThemeData.estimateBrightnessForColor(
              confirmation.accentColor,
            ) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: confirmation.accentColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      confirmation.icon,
                      size: 21,
                      color: confirmation.accentColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          confirmation.eyebrow,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: confirmation.accentColor,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          confirmation.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    confirmation.description,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          for (var index = 0;
                              index < confirmation.metrics.length;
                              index++) ...[
                            if (index > 0)
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: theme.colorScheme.outlineVariant,
                              ),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      confirmation.metrics[index].value,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      confirmation.metrics[index].label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        height: 1.15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 17,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          confirmation.note,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              color: theme.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: confirmation.canConfirm
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    icon: Icon(confirmation.icon, size: 18),
                    label: Text(confirmation.confirmLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: confirmation.accentColor,
                      foregroundColor: foreground,
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    required this.taxRate,
    required this.stockQuantity,
    required this.isSet,
    required this.parentSetId,
    required this.trackStock,
    required this.isActive,
    required this.isPublished,
    required this.showOnWebsite,
    required this.imageUrl,
    required this.imageUrls,
    required this.description,
    required this.websiteDescription,
    required this.websiteImageUrl,
    required this.websiteImageUrlOptimized,
    required this.websiteImageUrls,
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
  final double? taxRate;
  final int stockQuantity;
  final bool isSet;
  final String? parentSetId;
  final bool trackStock;
  final bool isActive;
  final bool isPublished;
  final bool showOnWebsite;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? description;
  final String? websiteDescription;
  final String? websiteImageUrl;
  final String? websiteImageUrlOptimized;
  final List<String> websiteImageUrls;
  final DateTime updatedAt;

  factory _WebsiteProductVisibilityRow.fromJson(Map<String, dynamic> json) {
    final optimizedImage = json['image_url_optimized']?.toString();
    final primaryImage = json['image_url']?.toString();
    final websiteImageUrl = _emptyToNull(json['website_image_url']);
    final websiteImageUrlOptimized =
        _emptyToNull(json['website_image_url_optimized']);
    final rawImageUrls = json['image_urls'];
    final rawWebsiteImageUrls = json['website_image_urls'];
    final imageUrls = rawImageUrls is List
        ? rawImageUrls.map((value) => value.toString()).toList(growable: false)
        : const <String>[];
    final websiteImageUrls = rawWebsiteImageUrls is List
        ? rawWebsiteImageUrls
            .map((value) => value.toString())
            .toList(growable: false)
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
      taxRate: (json['tax_rate'] as num?)?.toDouble(),
      stockQuantity: math.max(inventoryQty ?? 0, stockQty ?? 0),
      isSet: json['is_set'] as bool? ?? false,
      parentSetId: json['parent_set_id']?.toString(),
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      isPublished: json['is_published'] as bool? ?? false,
      showOnWebsite: json['show_on_website'] as bool? ?? false,
      imageUrl: _firstNonEmpty([
        websiteImageUrlOptimized,
        websiteImageUrl,
        optimizedImage,
        primaryImage,
        ...websiteImageUrls,
        ...imageUrls,
      ]),
      imageUrls: imageUrls,
      description: json['description']?.toString(),
      websiteDescription: json['website_description']?.toString(),
      websiteImageUrl: websiteImageUrl,
      websiteImageUrlOptimized: websiteImageUrlOptimized,
      websiteImageUrls: websiteImageUrls,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  bool get isService => productType == 'service';
  int get availableStockQuantity => stockQuantity;
  bool get hasTaxClassification => hasSupportedProductTaxRate(taxRate);
  bool get tracksStock => !isService && trackStock;
  bool get isMarkedForWebsite => isPublished && showOnWebsite;
  bool get isVisibleOnWebsite => isActive && isPublished && showOnWebsite;
  bool get hasImage => imageUrl != null || imageUrls.isNotEmpty;
  bool get hasWebsiteDescription =>
      websiteDescription != null && websiteDescription!.trim().isNotEmpty;
  bool get isAvailableForWebsite =>
      isService || !tracksStock || availableStockQuantity > 0;
  bool get hasPublicImage =>
      _isNotBlank(websiteImageUrl) ||
      _isNotBlank(websiteImageUrlOptimized) ||
      websiteImageUrls.any(_isNotBlank) ||
      _isNotBlank(imageUrl) ||
      imageUrls.any(_isNotBlank);

  bool matchesPublicVisibilityPolicy(
    PublicProductVisibilityPolicy policy,
    Set<String> visibleCategoryIds,
  ) {
    if (!isVisibleOnWebsite) return false;
    if (!isAllowedByStockPolicy(policy.stockPolicy)) return false;
    if (policy.requireImage && !hasPublicImage) return false;
    if (policy.requireVisibleCategory) {
      final category = categoryId?.trim();
      if (category == null || category.isEmpty) {
        if (!policy.includeUncategorized) return false;
      } else if (!visibleCategoryIds.contains(category)) {
        return false;
      }
    }
    return true;
  }

  bool isVisibleInPublicProductsCatalog(
    PublicProductVisibilityPolicy policy,
    Set<String> visibleCategoryIds,
  ) {
    return !isService &&
        matchesPublicVisibilityPolicy(policy, visibleCategoryIds);
  }

  bool isVisibleInPublicServicesCatalog(
    PublicProductVisibilityPolicy policy,
    Set<String> visibleCategoryIds,
  ) {
    return isService &&
        matchesPublicVisibilityPolicy(policy, visibleCategoryIds);
  }

  bool isHiddenFromPublicByPolicy(
    PublicProductVisibilityPolicy policy,
    Set<String> visibleCategoryIds,
  ) {
    return isVisibleOnWebsite &&
        !matchesPublicVisibilityPolicy(policy, visibleCategoryIds);
  }

  bool isAllowedByStockPolicy(PublicCatalogStockPolicy policy) {
    if (isService) return true;
    switch (policy) {
      case PublicCatalogStockPolicy.availableOnly:
        return !tracksStock || availableStockQuantity > 0;
      case PublicCatalogStockPolicy.outOfStockOnly:
        return tracksStock && availableStockQuantity <= 0;
      case PublicCatalogStockPolicy.all:
        return true;
    }
  }

  /// Why a product marked for the site does not show, in two words, or null
  /// when nothing blocks it. The same order as [publicVisibilityTooltip].
  String? publicBlockReason(
    PublicProductVisibilityPolicy policy,
    Set<String> visibleCategoryIds,
  ) {
    if (!isVisibleOnWebsite) return null;
    if (!isAllowedByStockPolicy(policy.stockPolicy)) {
      return policy.stockPolicy == PublicCatalogStockPolicy.outOfStockOnly
          ? 'Con stock'
          : 'Sin stock';
    }
    if (policy.requireImage && !hasPublicImage) return 'Sin foto';
    if (policy.requireVisibleCategory) {
      final category = categoryId?.trim();
      if (category == null || category.isEmpty) {
        if (!policy.includeUncategorized) return 'Sin categoría';
      } else if (!visibleCategoryIds.contains(category)) {
        return 'Categoría oculta';
      }
    }
    return null;
  }

  String publicVisibilityTooltip(
    PublicProductVisibilityPolicy policy,
    Set<String> visibleCategoryIds,
  ) {
    if (!isActive) return 'Inactivo: no aparece en la tienda online.';
    if (!hasTaxClassification) {
      return isVisibleOnWebsite
          ? 'Publicado sin clasificación tributaria. Clasifícalo o despublícalo.'
          : 'Falta definir IVA 19% o Exento antes de publicar.';
    }
    if (!isPublished || !showOnWebsite) return 'Oculto de la tienda online.';
    if (!isAllowedByStockPolicy(policy.stockPolicy)) {
      return 'Marcado web, pero la regla de stock lo oculta.';
    }
    if (policy.requireImage && !hasPublicImage) {
      return 'Marcado web, pero la regla de imagen lo oculta.';
    }
    if (policy.requireVisibleCategory) {
      final category = categoryId?.trim();
      if (category == null || category.isEmpty) {
        if (!policy.includeUncategorized) {
          return 'Marcado web, pero la regla de categoría oculta productos sin categoría.';
        }
      } else if (!visibleCategoryIds.contains(category)) {
        return 'Marcado web, pero su categoría no está seleccionada para el catálogo público.';
      }
    }
    return isService ? 'Visible en /servicios.' : 'Visible en /productos.';
  }

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
    if (availableStockQuantity <= 0) return 'Sin stock';
    return '$availableStockQuantity un.';
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
      taxRate: taxRate,
      stockQuantity: stockQuantity,
      isSet: isSet,
      parentSetId: parentSetId,
      trackStock: trackStock,
      isActive: isActive,
      isPublished: isPublished ?? this.isPublished,
      showOnWebsite: showOnWebsite ?? this.showOnWebsite,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      description: description,
      websiteDescription: websiteDescription,
      websiteImageUrl: websiteImageUrl,
      websiteImageUrlOptimized: websiteImageUrlOptimized,
      websiteImageUrls: websiteImageUrls,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String? _emptyToNull(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
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

  static bool _isNotBlank(String? value) => value?.trim().isNotEmpty == true;
}

class _WebsiteCategoryVisibilityOption {
  const _WebsiteCategoryVisibilityOption({
    required this.id,
    required this.label,
    required this.showOnWebsite,
    required this.parentId,
    required this.level,
    required this.description,
    required this.imageUrl,
    this.sortOrder = 0,
  });

  final String id;
  final String label;
  final bool showOnWebsite;
  final String? parentId;
  final int level;
  final String description;
  final String imageUrl;

  /// The catalog's order (`sort_order`, then the name), as the store groups.
  final int sortOrder;

  List<String> get pathParts => label
      .split('/')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  String get shortLabel {
    final parts = label
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? label : parts.last;
  }

  factory _WebsiteCategoryVisibilityOption.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    final fullPath = json['full_path']?.toString().trim() ?? '';
    return _WebsiteCategoryVisibilityOption(
      id: json['id']?.toString() ?? '',
      label: fullPath.isNotEmpty ? fullPath : name,
      showOnWebsite: json['show_on_website'] as bool? ?? false,
      parentId: json['parent_id']?.toString(),
      level: (json['level'] as num?)?.toInt() ?? 0,
      description: json['description']?.toString().trim() ?? '',
      imageUrl: json['image_url']?.toString().trim() ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  _WebsiteCategoryVisibilityOption copyWith({bool? showOnWebsite}) {
    return _WebsiteCategoryVisibilityOption(
      id: id,
      label: label,
      showOnWebsite: showOnWebsite ?? this.showOnWebsite,
      parentId: parentId,
      level: level,
      description: description,
      imageUrl: imageUrl,
      sortOrder: sortOrder,
    );
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
