import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../public_store/services/public_inventory_service.dart';
import '../../../public_store/widgets/catalog_collection_presentation.dart';
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
import '../models/website_catalog_presentation.dart';
import '../services/website_service.dart';
import '../services/website_catalog_availability_loader.dart';
import '../widgets/website_admin_ui.dart';
import '../widgets/website_media_picker.dart';

enum _CatalogKindFilter { all, products, services }

/// Public sections exposed by the unified Website Catalog workspace.
enum WebsiteCatalogSection { products, categories, categoryPresentation }

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

  factory _CatalogTableMetrics.forWidth(double availableWidth) {
    final extra = math.max(0.0, availableWidth - minimumWidth);
    return _CatalogTableMetrics(
      product: 330 + (extra * 0.34),
      type: 85 + (extra * 0.06),
      web: 100,
      status: 116,
      readiness: 150 + (extra * 0.14),
      category: 160 + (extra * 0.20),
      brand: 125 + (extra * 0.12),
      stock: 100 + (extra * 0.07),
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
  });

  final bool embedded;
  final WebsiteCatalogSection section;

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
  final _presentationCategorySearchController = TextEditingController();
  final _presentationSlugController = TextEditingController();
  final _presentationAliasController = TextEditingController();
  final _presentationEyebrowController = TextEditingController();
  final _presentationTitleController = TextEditingController();
  final _presentationDescriptionController = TextEditingController();
  final _presentationSeoTitleController = TextEditingController();
  final _presentationSeoDescriptionController = TextEditingController();
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
  WebsiteCatalogPresentationRegistry _presentationRegistry =
      const WebsiteCatalogPresentationRegistry({});
  WebsiteCatalogPresentation? _presentationDraft;
  WebsiteCatalogPresentation? _presentationBaseline;
  String? _presentationOwnerId;
  bool _presentationRemovalPending = false;
  bool _syncingPresentationText = false;
  bool _isSavingPresentation = false;
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
    _presentationCategorySearchController.addListener(
      _refreshPresentationCategoryList,
    );
    _presentationSlugController.addListener(_handlePresentationTextChanged);
    _presentationEyebrowController.addListener(_handlePresentationTextChanged);
    _presentationTitleController.addListener(_handlePresentationTextChanged);
    _presentationDescriptionController
        .addListener(_handlePresentationTextChanged);
    _presentationSeoTitleController.addListener(_handlePresentationTextChanged);
    _presentationSeoDescriptionController
        .addListener(_handlePresentationTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts());
  }

  @override
  void didUpdateWidget(ProductWebsiteVisibilityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    if (widget.section == WebsiteCatalogSection.categoryPresentation &&
        _presentationDraft == null) {
      _selectPresentationTarget(
        _presentationOwnerId ?? _preferredPresentationOwnerId(),
        force: true,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categorySearchController
      ..removeListener(_refreshCategorySelectionPage)
      ..dispose();
    _presentationCategorySearchController
      ..removeListener(_refreshPresentationCategoryList)
      ..dispose();
    _presentationSlugController
      ..removeListener(_handlePresentationTextChanged)
      ..dispose();
    _presentationAliasController.dispose();
    _presentationEyebrowController
      ..removeListener(_handlePresentationTextChanged)
      ..dispose();
    _presentationTitleController
      ..removeListener(_handlePresentationTextChanged)
      ..dispose();
    _presentationDescriptionController
      ..removeListener(_handlePresentationTextChanged)
      ..dispose();
    _presentationSeoTitleController
      ..removeListener(_handlePresentationTextChanged)
      ..dispose();
    _presentationSeoDescriptionController
      ..removeListener(_handlePresentationTextChanged)
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
            'show_on_website,is_active',
          )
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .order('full_path', ascending: true)
          .order('name', ascending: true);
      final settingsResponse = await _supabase
          .from('website_settings')
          .select('key,value')
          .eq('tenant_id', tenantId)
          .inFilter('key', [
        ...PublicProductVisibilityPolicy.settingKeys,
        websiteCatalogPresentationsSettingKey,
      ]);

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
      final presentationRegistry = WebsiteCatalogPresentationRegistry.decode(
        settings[websiteCatalogPresentationsSettingKey],
      );

      if (!mounted) return;
      setState(() {
        _tenantId = tenantId;
        _products = rows;
        _websiteCategories = categories;
        _presentationRegistry = presentationRegistry;
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
      if (widget.section == WebsiteCatalogSection.categoryPresentation &&
          mounted) {
        await _selectPresentationTarget(
          _presentationOwnerId ?? _preferredPresentationOwnerId(),
          force: true,
        );
      }
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
    if (widget.section == WebsiteCatalogSection.categoryPresentation &&
        _hasUnsavedPresentationChanges &&
        !await _confirmDiscardPresentationChanges()) {
      return;
    }
    if (!mounted) return;
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

  void _refreshPresentationCategoryList() {
    if (mounted &&
        widget.section == WebsiteCatalogSection.categoryPresentation) {
      setState(() {});
    }
  }

  String _preferredPresentationOwnerId() =>
      websiteProductsCatalogPresentationId;

  _WebsiteCatalogPresentationTarget? _presentationTarget([String? ownerId]) {
    final selectedId = ownerId ?? _presentationOwnerId;
    if (selectedId == null) return null;
    if (selectedId == websiteProductsCatalogPresentationId) {
      return const _WebsiteCatalogPresentationTarget.root(
        WebsiteCatalogRoot.products,
      );
    }
    if (selectedId == websiteServicesCatalogPresentationId) {
      return const _WebsiteCatalogPresentationTarget.root(
        WebsiteCatalogRoot.services,
      );
    }
    final category =
        _websiteCategories.where((item) => item.id == selectedId).firstOrNull;
    return category == null
        ? null
        : _WebsiteCatalogPresentationTarget.category(category);
  }

  bool get _hasUnsavedPresentationChanges {
    final baseline = _presentationBaseline;
    final draft = _presentationDraft;
    if (baseline == null || draft == null) return false;
    return _presentationRemovalPending ||
        !draft.hasSamePersistedValue(baseline);
  }

  void _handlePresentationTextChanged() {
    if (_syncingPresentationText || !mounted) return;
    final current = _presentationDraft;
    final target = _presentationTarget();
    if (current == null || target == null) return;
    var next = current.copyWith(
      seoTitle: _presentationSeoTitleController.text.trim(),
      seoDescription: _presentationSeoDescriptionController.text.trim(),
    );
    if (!target.isRoot) {
      next = next.copyWith(
        slug: websiteCategorySlug(_presentationSlugController.text),
        heroEyebrow: _presentationEyebrowController.text.trim(),
        heroTitle: _presentationTitleController.text.trim(),
        heroDescription: _presentationDescriptionController.text.trim(),
      );
    }
    if (next.hasSamePersistedValue(current)) return;
    setState(() {
      _presentationDraft = next;
      _presentationRemovalPending = false;
    });
  }

  Future<void> _selectPresentationTarget(
    String? ownerId, {
    bool force = false,
  }) async {
    if (ownerId == null || ownerId.isEmpty) return;
    final target = _presentationTarget(ownerId);
    if (target == null) return;
    if (!force &&
        _presentationOwnerId == ownerId &&
        _presentationDraft != null) {
      return;
    }
    if (!force &&
        _hasUnsavedPresentationChanges &&
        !await _confirmDiscardPresentationChanges()) {
      return;
    }
    if (!mounted) return;
    _loadPresentationSession(target);
  }

  void _loadPresentationSession(
    _WebsiteCatalogPresentationTarget target,
  ) {
    final stored = _presentationRegistry.byOwnerId[target.id];
    final effective = stored ?? target.fallbackPresentation;
    _syncingPresentationText = true;
    _presentationSlugController.text = effective.slug;
    _presentationAliasController.clear();
    _presentationEyebrowController.text = effective.heroEyebrow;
    _presentationTitleController.text = effective.heroTitle;
    _presentationDescriptionController.text = effective.heroDescription;
    _presentationSeoTitleController.text = effective.seoTitle;
    _presentationSeoDescriptionController.text = effective.seoDescription;
    _syncingPresentationText = false;
    setState(() {
      _presentationOwnerId = target.id;
      _presentationBaseline = effective;
      _presentationDraft = effective;
      _presentationRemovalPending = false;
    });
  }

  void _updatePresentationDraft(
    WebsiteCatalogPresentation Function(WebsiteCatalogPresentation current)
        update,
  ) {
    final current = _presentationDraft;
    if (current == null) return;
    setState(() {
      _presentationDraft = update(current);
      _presentationRemovalPending = false;
    });
  }

  void _addPresentationAlias([String? rawValue]) {
    final current = _presentationDraft;
    final target = _presentationTarget();
    if (current == null || target == null || target.isRoot) return;
    final alias =
        websiteCategorySlug(rawValue ?? _presentationAliasController.text);
    if (alias.isEmpty) return;
    if (alias == current.slug) {
      _showSnackBar('El alias debe ser distinto de la ruta pública actual.');
      return;
    }
    if (current.slugAliases.contains(alias)) {
      _presentationAliasController.clear();
      return;
    }
    _presentationAliasController.clear();
    _updatePresentationDraft(
      (draft) => draft.copyWith(
        slugAliases: [...draft.slugAliases, alias],
      ),
    );
  }

  void _removePresentationAlias(String alias) {
    _updatePresentationDraft(
      (draft) => draft.copyWith(
        slugAliases: draft.slugAliases.where((item) => item != alias).toList(),
      ),
    );
  }

  Future<bool> _confirmDiscardPresentationChanges() async {
    if (!_hasUnsavedPresentationChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.edit_note_rounded),
        title: const Text('Hay cambios sin guardar'),
        content: const Text(
          'Si cambias de colección, este borrador se descartará. '
          'La versión pública seguirá usando la última configuración guardada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar borrador'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _savePresentation() async {
    final current = _presentationDraft;
    final target = _presentationTarget();
    if (current == null ||
        target == null ||
        _isSavingPresentation ||
        !_hasUnsavedPresentationChanges) {
      return;
    }
    final slug =
        target.isRoot ? target.root!.routeSegment : current.slug.trim();
    if (!target.isRoot && slug.isEmpty) {
      _showSnackBar('Escribe una ruta pública válida.');
      return;
    }

    final next = current.copyWith(slug: slug);
    final wasRemoval = _presentationRemovalPending;
    setState(() => _isSavingPresentation = true);
    try {
      final service = context.read<WebsiteService>();
      if (wasRemoval) {
        await service.removeCatalogPresentation(target.id);
      } else {
        await service.saveCatalogPresentation(next);
      }
      if (!mounted) return;
      _presentationRegistry = service.catalogPresentationRegistry;
      _loadPresentationSession(target);
      _showSnackBar(
        wasRemoval
            ? 'Se restableció la presentación heredada.'
            : 'Presentación web guardada.',
      );
    } catch (error) {
      if (mounted) {
        _showSnackBar('No se pudo guardar la presentación: $error');
      }
    } finally {
      if (mounted) setState(() => _isSavingPresentation = false);
    }
  }

  Future<void> _resetPresentation() async {
    final target = _presentationTarget();
    if (target == null || _isSavingPresentation) return;
    final hasStored = _presentationRegistry.byOwnerId[target.id] != null;
    if (!hasStored) {
      _loadPresentationSession(target);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: const Text('Restablecer presentación'),
        content: Text(
          'Se preparará la eliminación de los ajustes de “${target.label}”. '
          'Nada cambiará en el sitio hasta que presiones Guardar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final fallback = target.fallbackPresentation;
    _syncingPresentationText = true;
    _presentationSlugController.text = fallback.slug;
    _presentationAliasController.clear();
    _presentationEyebrowController.text = fallback.heroEyebrow;
    _presentationTitleController.text = fallback.heroTitle;
    _presentationDescriptionController.text = fallback.heroDescription;
    _presentationSeoTitleController.text = fallback.seoTitle;
    _presentationSeoDescriptionController.text = fallback.seoDescription;
    _syncingPresentationText = false;
    setState(() {
      _presentationDraft = fallback;
      _presentationRemovalPending = true;
    });
  }

  void _discardPresentationChanges() {
    final target = _presentationTarget();
    if (target == null || _isSavingPresentation) return;
    _loadPresentationSession(target);
  }

  Future<void> _reloadPresentationFromPersistence() async {
    final target = _presentationTarget();
    if (target == null || _isSavingPresentation) return;
    if (_hasUnsavedPresentationChanges &&
        !await _confirmDiscardPresentationChanges()) {
      return;
    }
    if (!mounted) return;
    setState(() => _isSavingPresentation = true);
    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();
      if (service.error != null) {
        throw Exception(service.error);
      }
      if (!mounted) return;
      _presentationRegistry = service.catalogPresentationRegistry;
      _loadPresentationSession(target);
      _showSnackBar('Se recargó la última versión guardada.');
    } catch (error) {
      if (mounted) _showSnackBar('No se pudo recargar: $error');
    } finally {
      if (mounted) setState(() => _isSavingPresentation = false);
    }
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
        WebsiteCatalogSection.categoryPresentation =>
          'Presentación del catálogo',
        WebsiteCatalogSection.products => 'Catálogo web',
      },
      description: switch (widget.section) {
        WebsiteCatalogSection.categories =>
          'Decide qué familias organizan la experiencia pública.',
        WebsiteCatalogSection.categoryPresentation =>
          'Diseña los catálogos raíz y cada colección desde un solo lugar.',
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
          else if (widget.section == WebsiteCatalogSection.categoryPresentation)
            Expanded(child: _buildCategoryPresentationPage(theme))
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

  Widget _buildCategoryPresentationPage(ThemeData theme) {
    final selected = _presentationTarget();
    final draft = _presentationDraft;
    if (selected == null || draft == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectPresentationTarget(
            _preferredPresentationOwnerId(),
            force: true,
          );
        }
      });
      return const Center(child: BrandedLoading());
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1180;
          final rail = _buildPresentationCategoryRail(theme, selected.id);
          final editor = _buildPresentationEditor(theme, selected, draft);
          final preview = _buildPresentationPreview(theme, selected, draft);

          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 260, child: rail),
                const SizedBox(width: 12),
                Expanded(
                  child: ListView(
                    children: [
                      editor,
                      const SizedBox(height: 14),
                      SizedBox(height: 620, child: preview),
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 280, child: rail),
              const SizedBox(width: 16),
              SizedBox(
                width: math.min(410, constraints.maxWidth * 0.31),
                child: SingleChildScrollView(child: editor),
              ),
              const SizedBox(width: 16),
              Expanded(child: preview),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPresentationCategoryRail(
    ThemeData theme,
    String selectedId,
  ) {
    final query = _normalizeSearch(_presentationCategorySearchController.text);
    final rows = _websiteCategories.where((category) {
      return query.isEmpty || _normalizeSearch(category.label).contains(query);
    }).toList(growable: false);
    final rootTargets = WebsiteCatalogRoot.values
        .map(_WebsiteCatalogPresentationTarget.root)
        .where(
          (target) =>
              query.isEmpty ||
              _normalizeSearch(
                '${target.label} ${target.supportingLabel}',
              ).contains(query),
        )
        .toList(growable: false);
    final targets = [
      ...rootTargets,
      ...rows.map(_WebsiteCatalogPresentationTarget.category),
    ];
    final configuredRoots = WebsiteCatalogRoot.values
        .where((root) => _presentationRegistry.forCatalogRoot(root) != null)
        .length;

    return WebsiteAdminSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Colecciones',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$configuredRoots/2 catálogos raíz · '
                  '${_presentationRegistry.categoryPresentationCount} categorías personalizadas',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _presentationCategorySearchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Buscar catálogo o categoría',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: ListView.separated(
              itemCount: targets.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              itemBuilder: (context, index) {
                final target = targets[index];
                final selected = target.id == selectedId;
                final configured =
                    _presentationRegistry.byOwnerId[target.id] != null;
                return Material(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectPresentationTarget(target.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: target.imageUrl.isNotEmpty
                                ? Image.network(
                                    target.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.category_outlined,
                                      size: 18,
                                    ),
                                  )
                                : Icon(
                                    target.isRoot
                                        ? Icons.storefront_outlined
                                        : Icons.category_outlined,
                                    size: 18,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  target.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  target.supportingLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: target.showOnWebsite
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (configured)
                            Tooltip(
                              message: 'Presentación personalizada',
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 17,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentationEditor(
    ThemeData theme,
    _WebsiteCatalogPresentationTarget target,
    WebsiteCatalogPresentation draft,
  ) {
    final hasStored = _presentationRegistry.byOwnerId[target.id] != null;
    final hasChanges = _hasUnsavedPresentationChanges;
    final statusLabel = _presentationRemovalPending
        ? 'Restablecimiento pendiente'
        : hasChanges
            ? 'Cambios sin guardar'
            : hasStored
                ? 'Versión guardada'
                : 'Usando valores heredados';
    final statusColor = hasChanges
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;

    return WebsiteAdminSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Presentación web',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: target.isRoot
                    ? 'Esta configuración controla la grilla y los filtros de '
                        '${target.publicPath}; no cambia qué artículos son públicos.'
                    : 'Estos ajustes no cambian el nombre, la jerarquía ni los '
                        'productos de la categoría.',
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 19,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (target.isRoot)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.route_outlined,
                    size: 19,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target.publicPath,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'La ruta es canónica. Aquí defines SEO, densidad y '
                          'filtros para Editar, Preview y el sitio público.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            _buildCategoryPresentationControls(theme, target, draft),
          const SizedBox(height: 16),
          _buildPresentationSeoEditor(theme, target, draft),
          const SizedBox(height: 18),
          Text('Catálogo', style: _presentationSectionStyle(theme)),
          const SizedBox(height: 10),
          _buildPresentationDropdown<WebsiteCatalogGridDensity>(
            theme,
            label: 'Densidad del grid',
            value: draft.gridDensity,
            values: WebsiteCatalogGridDensity.values,
            labelFor: (value) => value.label,
            onChanged: (value) => _updatePresentationDraft(
              (current) => current.copyWith(gridDensity: value),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            draft.gridDensity.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _buildPresentationFacetEditor(theme, draft),
          const SizedBox(height: 18),
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                hasChanges ? Icons.edit_rounded : Icons.cloud_done_outlined,
                size: 17,
                color: statusColor,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _isSavingPresentation
                    ? null
                    : _reloadPresentationFromPersistence,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Recargar'),
              ),
              TextButton(
                onPressed: _isSavingPresentation || !hasChanges
                    ? null
                    : _discardPresentationChanges,
                child: const Text('Descartar'),
              ),
              TextButton(
                onPressed: _isSavingPresentation ? null : _resetPresentation,
                child: const Text('Restablecer'),
              ),
              FilledButton.icon(
                onPressed: _isSavingPresentation || !hasChanges
                    ? null
                    : _savePresentation,
                icon: _isSavingPresentation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Guardar cambios'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresentationSeoEditor(
    ThemeData theme,
    _WebsiteCatalogPresentationTarget target,
    WebsiteCatalogPresentation draft,
  ) {
    final websiteService = context.read<WebsiteService>();
    final savedStoreName =
        websiteService.getSetting('store_name', 'VINABIKE').trim();
    final storeName = savedStoreName.isEmpty ? 'VINABIKE' : savedStoreName;
    final savedStoreDescription = websiteService
        .getSetting(
          'store_description',
          'Todo lo que necesitas para tu bicicleta en Viña del Mar',
        )
        .trim();
    final storeDescription = savedStoreDescription.isEmpty
        ? 'Todo lo que necesitas para tu bicicleta en Viña del Mar'
        : savedStoreDescription;
    final inheritedTitle = target.isRoot
        ? '${target.root == WebsiteCatalogRoot.services ? 'Servicios' : 'Productos'} | $storeName'
        : '${draft.heroTitle.isNotEmpty ? draft.heroTitle : target.label} | $storeName';
    final inheritedDescription = draft.heroDescription.isNotEmpty
        ? draft.heroDescription
        : target.description.isNotEmpty
            ? target.description
            : storeDescription;
    final inheritedImage = target.isRoot
        ? websiteService.getSetting('logo_url', '')
        : draft.heroImageUrl.isNotEmpty
            ? draft.heroImageUrl
            : target.imageUrl;
    final effectiveSocialImage =
        draft.socialImageUrl.isNotEmpty ? draft.socialImageUrl : inheritedImage;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        title: Text(
          'SEO y compartir',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          draft.allowIndexing
              ? 'Indexación permitida sólo si la ruta es pública y elegible'
              : 'No solicitar indexación',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          TextField(
            controller: _presentationSeoTitleController,
            maxLength: 65,
            decoration: InputDecoration(
              labelText: 'Título para buscadores',
              hintText: inheritedTitle,
              helperText: 'Vacío hereda el título de la colección.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _presentationSeoDescriptionController,
            minLines: 3,
            maxLines: 4,
            maxLength: 165,
            decoration: InputDecoration(
              labelText: 'Meta descripción',
              hintText: inheritedDescription,
              helperText: 'Vacía hereda la descripción pública disponible.',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Imagen al compartir',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          WebsiteImagePickerField(
            currentUrl:
                effectiveSocialImage.isEmpty ? null : effectiveSocialImage,
            enableBackgroundRemoval: false,
            onChanged: (url) => _updatePresentationDraft(
              (current) => current.copyWith(socialImageUrl: url.trim()),
            ),
          ),
          if (draft.socialImageUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _updatePresentationDraft(
                  (current) => current.copyWith(socialImageUrl: ''),
                ),
                icon: const Icon(Icons.undo_rounded, size: 17),
                label: Text(
                  target.isRoot
                      ? 'Usar imagen global del sitio'
                      : 'Usar imagen heredada de la colección',
                ),
              ),
            ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Permitir indexación'),
            subtitle: const Text(
              'Sólo puede restringir. Rutas filtradas, vacías, no publicadas '
              'y Editar/Preview siguen usando noindex.',
            ),
            value: draft.allowIndexing,
            onChanged: (value) => _updatePresentationDraft(
              (current) => current.copyWith(allowIndexing: value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPresentationControls(
    ThemeData theme,
    _WebsiteCatalogPresentationTarget target,
    WebsiteCatalogPresentation draft,
  ) {
    final effectiveImage =
        draft.heroImageUrl.isNotEmpty ? draft.heroImageUrl : target.imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _presentationSlugController,
          decoration: const InputDecoration(
            labelText: 'Segmento de ruta pública',
            prefixText: '…/categoria/',
            helperText:
                'Se usa en Productos y Servicios. Al guardar un cambio, la '
                'ruta anterior queda como alias.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'Rutas anteriores',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Tooltip(
              message:
                  'Los alias mantienen funcionando enlaces antiguos. No se '
                  'indexan y redirigen a la ruta actual tanto en Productos '
                  'como en Servicios.',
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        if (draft.slugAliases.isEmpty)
          Text(
            'Sin alias guardados.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final alias in draft.slugAliases)
                InputChip(
                  label: Text('…/categoria/$alias'),
                  tooltip: 'Quitar alias',
                  onDeleted: () => _removePresentationAlias(alias),
                ),
            ],
          ),
        const SizedBox(height: 9),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _presentationAliasController,
          builder: (context, value, _) {
            return TextField(
              controller: _presentationAliasController,
              textInputAction: TextInputAction.done,
              onSubmitted: _addPresentationAlias,
              decoration: InputDecoration(
                labelText: 'Agregar alias',
                prefixText: '…/categoria/',
                hintText: 'ruta-anterior',
                helperText: 'También puedes quitar un alias antes de guardar.',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Agregar alias',
                  onPressed: websiteCategorySlug(value.text).isEmpty
                      ? null
                      : _addPresentationAlias,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Text('Hero', style: _presentationSectionStyle(theme)),
        const SizedBox(height: 10),
        WebsiteImagePickerField(
          currentUrl: effectiveImage.isEmpty ? null : effectiveImage,
          enableBackgroundRemoval: false,
          onChanged: (url) => _updatePresentationDraft(
            (current) => current.copyWith(heroImageUrl: url),
          ),
        ),
        if (draft.heroImageUrl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _updatePresentationDraft(
                (current) => current.copyWith(heroImageUrl: ''),
              ),
              icon: const Icon(Icons.undo_rounded, size: 17),
              label: const Text('Usar imagen de la categoría'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _presentationEyebrowController,
          decoration: const InputDecoration(
            labelText: 'Antetítulo opcional',
            hintText: 'Sin texto adicional',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _presentationTitleController,
          decoration: InputDecoration(
            labelText: 'Título opcional',
            hintText: target.label,
            helperText: 'Vacío conserva el nombre real de la categoría.',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _presentationDescriptionController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Descripción opcional',
            hintText: target.description.isEmpty
                ? 'Agrega contexto para esta colección'
                : target.description,
            helperText: 'Vacía hereda la descripción de la categoría.',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _buildPresentationDropdown<WebsiteCatalogHeroSize>(
          theme,
          label: 'Altura del hero',
          value: draft.heroSize,
          values: WebsiteCatalogHeroSize.values,
          labelFor: (value) => value.label,
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(heroSize: value),
          ),
        ),
        const SizedBox(height: 10),
        _buildPresentationDropdown<WebsiteCatalogHeroAlignment>(
          theme,
          label: 'Alineación',
          value: draft.heroAlignment,
          values: WebsiteCatalogHeroAlignment.values,
          labelFor: (value) => value.label,
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(heroAlignment: value),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Oscurecimiento · ${(draft.heroOverlay * 100).round()}%',
          style: theme.textTheme.labelMedium,
        ),
        Slider(
          value: draft.heroOverlay,
          min: 0,
          max: 0.78,
          divisions: 13,
          label: '${(draft.heroOverlay * 100).round()}%',
          semanticFormatterCallback: (value) => '${(value * 100).round()}%',
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(heroOverlay: value),
          ),
        ),
        const SizedBox(height: 18),
        Text('Megamenú', style: _presentationSectionStyle(theme)),
        const SizedBox(height: 4),
        Text(
          'Imagen visual de esta categoría en el megamenú. Se usa como portada '
          'lateral cuando es una sección y como card cuando aparece dentro de '
          'otra.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        WebsiteImagePickerField(
          currentUrl:
              draft.megaMenuImageUrl.isEmpty ? null : draft.megaMenuImageUrl,
          enableBackgroundRemoval: false,
          onChanged: (url) => _updatePresentationDraft(
            (current) => current.copyWith(
              megaMenuImageUrl: url.trim(),
            ),
          ),
        ),
        if (draft.megaMenuImageUrl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _updatePresentationDraft(
                (current) => current.copyWith(megaMenuImageUrl: ''),
              ),
              icon: const Icon(Icons.hide_image_outlined, size: 17),
              label: const Text('Quitar imagen del megamenú'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Oscurecimiento del megamenú · '
          '${(draft.megaMenuOverlay * 100).round()}%',
          style: theme.textTheme.labelMedium,
        ),
        Slider(
          value: draft.megaMenuOverlay,
          min: 0,
          max: 0.85,
          divisions: 17,
          label: '${(draft.megaMenuOverlay * 100).round()}%',
          semanticFormatterCallback: (value) => '${(value * 100).round()}%',
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(megaMenuOverlay: value),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Oscurecimiento de la card · '
          '${(draft.megaMenuCardOverlay * 100).round()}%',
          style: theme.textTheme.labelMedium,
        ),
        Slider(
          value: draft.megaMenuCardOverlay,
          min: 0,
          max: 0.65,
          divisions: 13,
          label: '${(draft.megaMenuCardOverlay * 100).round()}%',
          semanticFormatterCallback: (value) => '${(value * 100).round()}%',
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(megaMenuCardOverlay: value),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ancho de portada · '
          '${draft.megaMenuOverviewWidth.round()} px',
          style: theme.textTheme.labelMedium,
        ),
        Slider(
          value: draft.megaMenuOverviewWidth,
          min: WebsiteCatalogPresentation.minMegaMenuOverviewWidth,
          max: WebsiteCatalogPresentation.maxMegaMenuOverviewWidth,
          divisions: 14,
          label: '${draft.megaMenuOverviewWidth.round()} px',
          semanticFormatterCallback: (value) => '${value.round()} píxeles',
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(megaMenuOverviewWidth: value),
          ),
        ),
        const SizedBox(height: 10),
        _buildPresentationDropdown<WebsiteMegaMenuContentAlignment>(
          theme,
          label: 'Posición del contenido',
          value: draft.megaMenuContentAlignment,
          values: WebsiteMegaMenuContentAlignment.values,
          labelFor: (value) => value.label,
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(
              megaMenuContentAlignment: value,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Contenido', style: _presentationSectionStyle(theme)),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Migas de navegación'),
          subtitle: const Text('Muestra la jerarquía completa.'),
          value: draft.showBreadcrumbs,
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(showBreadcrumbs: value),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Subcategorías relacionadas'),
          subtitle: const Text('Permite profundizar sin volver al menú.'),
          value: draft.showSubcategories,
          onChanged: (value) => _updatePresentationDraft(
            (current) => current.copyWith(showSubcategories: value),
          ),
        ),
      ],
    );
  }

  TextStyle? _presentationSectionStyle(ThemeData theme) =>
      theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      );

  Widget _buildPresentationFacetEditor(
    ThemeData theme,
    WebsiteCatalogPresentation draft,
  ) {
    final enabled = draft.facets;
    final available = WebsiteCatalogFacet.values
        .where((facet) => !enabled.contains(facet))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Filtros del catálogo',
                style: _presentationSectionStyle(theme),
              ),
            ),
            Tooltip(
              message:
                  'Cada filtro consulta todos los productos que cumplen las reglas públicas, no solo los que ya están cargados en pantalla.',
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'El orden de esta lista será el orden visible para el cliente.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Visibles · ${enabled.length}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        if (enabled.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.filter_alt_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'No hay filtros visibles en esta colección.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: enabled.length,
            onReorder: (oldIndex, newIndex) {
              var destination = newIndex;
              if (destination > oldIndex) destination -= 1;
              _movePresentationFacet(oldIndex, destination);
            },
            itemBuilder: (context, index) {
              final facet = enabled[index];
              return _buildEnabledPresentationFacet(
                theme,
                facet: facet,
                index: index,
                total: enabled.length,
              );
            },
          ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Disponibles',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: available
                .map(
                  (facet) => OutlinedButton.icon(
                    onPressed: () => _setPresentationFacetEnabled(
                      facet,
                      enabled: true,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: Text(facet.label),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _buildEnabledPresentationFacet(
    ThemeData theme, {
    required WebsiteCatalogFacet facet,
    required int index,
    required int total,
  }) {
    return Container(
      key: ValueKey('catalog-facet-${facet.storageValue}'),
      margin: EdgeInsets.only(bottom: index == total - 1 ? 0 : 7),
      padding: const EdgeInsets.fromLTRB(7, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: 'Arrastrar para ordenar',
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 19,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              _presentationFacetIcon(facet),
              size: 17,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facet.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _presentationFacetDescription(facet),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _compactFacetIconButton(
            tooltip: 'Subir ${facet.label}',
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: index == 0
                ? null
                : () => _movePresentationFacet(index, index - 1),
          ),
          _compactFacetIconButton(
            tooltip: 'Bajar ${facet.label}',
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: index == total - 1
                ? null
                : () => _movePresentationFacet(index, index + 1),
          ),
          _compactFacetIconButton(
            tooltip: 'Ocultar ${facet.label}',
            icon: Icons.close_rounded,
            onPressed: () => _setPresentationFacetEnabled(
              facet,
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactFacetIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
    );
  }

  void _movePresentationFacet(int from, int to) {
    final draft = _presentationDraft;
    if (draft == null ||
        from == to ||
        from < 0 ||
        from >= draft.facets.length ||
        to < 0 ||
        to >= draft.facets.length) {
      return;
    }
    final next = List<WebsiteCatalogFacet>.from(draft.facets);
    final facet = next.removeAt(from);
    next.insert(to, facet);
    _updatePresentationDraft(
      (current) => current.copyWith(facets: next),
    );
  }

  void _setPresentationFacetEnabled(
    WebsiteCatalogFacet facet, {
    required bool enabled,
  }) {
    final draft = _presentationDraft;
    if (draft == null) return;
    final next = List<WebsiteCatalogFacet>.from(draft.facets);
    if (enabled) {
      if (!next.contains(facet)) next.add(facet);
    } else {
      next.remove(facet);
    }
    _updatePresentationDraft(
      (current) => current.copyWith(facets: next),
    );
  }

  IconData _presentationFacetIcon(WebsiteCatalogFacet facet) => switch (facet) {
        WebsiteCatalogFacet.categories => Icons.account_tree_outlined,
        WebsiteCatalogFacet.availability => Icons.inventory_2_outlined,
        WebsiteCatalogFacet.brand => Icons.sell_outlined,
        WebsiteCatalogFacet.price => Icons.payments_outlined,
      };

  String _presentationFacetDescription(WebsiteCatalogFacet facet) =>
      switch (facet) {
        WebsiteCatalogFacet.categories => 'Navegación por categoría',
        WebsiteCatalogFacet.availability => 'Productos con o sin stock',
        WebsiteCatalogFacet.brand => 'Marcas reales del catálogo',
        WebsiteCatalogFacet.price => 'Rango de precio público',
      };

  Widget _buildPresentationDropdown<T>(
    ThemeData theme, {
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(labelFor(item)),
            ),
          )
          .toList(growable: false),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }

  Set<String> _presentationCategoryTreeIds(String categoryId) {
    final ids = <String>{categoryId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final category in _websiteCategories) {
        if (category.parentId != null &&
            ids.contains(category.parentId) &&
            ids.add(category.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  Widget _buildPresentationPreview(
    ThemeData theme,
    _WebsiteCatalogPresentationTarget target,
    WebsiteCatalogPresentation draft,
  ) {
    final category = target.category;
    final categoryIds = category == null
        ? const <String>{}
        : _presentationCategoryTreeIds(category.id);
    final eligibleProducts = _products.where((product) {
      if (!product.matchesPublicVisibilityPolicy(
        _visibilityPolicy,
        _visibleWebsiteCategoryIds,
      )) {
        return false;
      }
      if (target.root == WebsiteCatalogRoot.products) return !product.isService;
      if (target.root == WebsiteCatalogRoot.services) return product.isService;
      return categoryIds.contains(product.categoryFilterId);
    }).toList(growable: false);
    final products = eligibleProducts.take(10).toList(growable: false);
    final subcategories = category == null
        ? const <_WebsiteCategoryVisibilityOption>[]
        : _websiteCategories
            .where(
              (item) => item.parentId == category.id && item.showOnWebsite,
            )
            .toList(growable: false);
    final path = target.isRoot
        ? target.publicPath
        : publicCategoryPath(presentation: draft);
    final title = draft.heroTitle.isNotEmpty ? draft.heroTitle : target.label;
    final description = draft.heroDescription.isNotEmpty
        ? draft.heroDescription
        : target.description;
    final imageUrl =
        draft.heroImageUrl.isNotEmpty ? draft.heroImageUrl : target.imageUrl;

    return WebsiteAdminSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Vista previa',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!target.isRoot)
                    CatalogCollectionPresentationHeader(
                      presentation: draft,
                      title: title,
                      description: description,
                      imageUrl: imageUrl,
                      compact: true,
                      breadcrumbs: [
                        CatalogCollectionNavigationItem(
                          id: WebsiteCatalogRoot.products.presentationId,
                          label: 'Productos',
                        ),
                        for (var index = 0;
                            index < target.pathParts.length;
                            index++)
                          CatalogCollectionNavigationItem(
                            id: 'preview-breadcrumb-$index',
                            label: target.pathParts[index],
                            selected: index == target.pathParts.length - 1,
                          ),
                      ],
                      subcategories: subcategories
                          .map(
                            (item) => CatalogCollectionNavigationItem(
                              id: item.id,
                              label: item.shortLabel,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final showSidebar = constraints.maxWidth >= 660;
                        final grid = _buildPresentationProductGridPreview(
                          theme,
                          draft: draft,
                          products: products,
                          totalCount: eligibleProducts.length,
                        );
                        if (!showSidebar) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildPresentationFacetPreview(theme, draft),
                              const SizedBox(height: 22),
                              grid,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 190,
                              child:
                                  _buildPresentationFacetPreview(theme, draft),
                            ),
                            const SizedBox(width: 30),
                            Expanded(child: grid),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentationFacetPreview(
    ThemeData theme,
    WebsiteCatalogPresentation draft,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Filtros',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                'Buscar',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final facet in draft.facets) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _presentationFacetIcon(facet),
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  facet.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPresentationProductGridPreview(
    ThemeData theme, {
    required WebsiteCatalogPresentation draft,
    required List<_WebsiteProductVisibilityRow> products,
    required int totalCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$totalCount resultados públicos',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              draft.gridDensity.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (products.isEmpty)
          Text(
            'No hay resultados que cumplan las reglas públicas.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = websiteCatalogGridMetrics(
                width: constraints.maxWidth,
                density: draft.gridDensity,
              );
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: metrics.crossAxisCount,
                  childAspectRatio: metrics.childAspectRatio,
                  crossAxisSpacing: metrics.crossAxisSpacing,
                  mainAxisSpacing: metrics.mainAxisSpacing,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) =>
                    _PresentationProductPreview(product: products[index]),
              );
            },
          ),
      ],
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
                hintText: 'Buscar por producto, SKU o marca',
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
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
        final metrics = _CatalogTableMetrics.forWidth(constraints.maxWidth);
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
          _buildHeaderCell(theme, 'Tipo', width: metrics.type),
          _buildHeaderCell(theme, 'Marcado web', width: metrics.web),
          _buildHeaderCell(theme, 'Estado', width: metrics.status),
          _buildHeaderCell(theme, 'Calidad web', width: metrics.readiness),
          _buildHeaderCell(theme, 'Categoría', width: metrics.category),
          _buildHeaderCell(theme, 'Marca', width: metrics.brand),
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
      label = 'Bloqueado';
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

class _PresentationProductPreview extends StatelessWidget {
  const _PresentationProductPreview({required this.product});

  final _WebsiteProductVisibilityRow product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: product.imageUrl == null
                ? Icon(
                    Icons.image_not_supported_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.network(
                      product.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          ChileanUtils.formatCurrency(product.price),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
  });

  final String id;
  final String label;
  final bool showOnWebsite;
  final String? parentId;
  final int level;
  final String description;
  final String imageUrl;

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
    );
  }
}

class _WebsiteCatalogPresentationTarget {
  const _WebsiteCatalogPresentationTarget.root(this.root) : category = null;

  const _WebsiteCatalogPresentationTarget.category(this.category) : root = null;

  final WebsiteCatalogRoot? root;
  final _WebsiteCategoryVisibilityOption? category;

  bool get isRoot => root != null;

  String get id => root?.presentationId ?? category!.id;

  String get label => root?.label ?? category!.shortLabel;

  String get supportingLabel => switch (root) {
        WebsiteCatalogRoot.products => '/productos · catálogo completo',
        WebsiteCatalogRoot.services => '/servicios · catálogo completo',
        null =>
          category!.showOnWebsite ? 'En navegación' : 'Fuera de navegación',
      };

  String get description => category?.description ?? '';

  String get imageUrl => category?.imageUrl ?? '';

  bool get showOnWebsite => category?.showOnWebsite ?? true;

  List<String> get pathParts => category?.pathParts ?? const <String>[];

  String get publicPath => switch (root) {
        WebsiteCatalogRoot.products => '/productos',
        WebsiteCatalogRoot.services => '/servicios',
        null => publicCategoryPath(presentation: fallbackPresentation),
      };

  WebsiteCatalogPresentation get fallbackPresentation {
    final catalogRoot = root;
    if (catalogRoot != null) {
      return WebsiteCatalogPresentation.catalogRoot(catalogRoot);
    }
    return WebsiteCatalogPresentation.fallback(
      categoryId: category!.id,
      categoryName: category!.shortLabel,
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
