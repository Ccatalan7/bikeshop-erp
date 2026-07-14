import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/website_destination.dart';
import 'website_workspace_scope.dart';

// ==============================================================================
// PUBLIC WIDGET: The "Button" that opens the configuration dialog
// ==============================================================================

class WebsiteLinkValueEditor extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  final String? helpText;

  final bool allowInternal;
  final bool allowExternal;
  final bool allowAnchor;

  final bool dense;
  final bool darkStyle;

  const WebsiteLinkValueEditor({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helpText,
    this.allowInternal = true,
    this.allowExternal = true,
    this.allowAnchor = true,
    this.dense = false,
    this.darkStyle = false,
    bool showValuePreview = true, // Legacy param, ignored now
  });

  /// Opens the standardized link configurator dialog and returns the selected
  /// href (or null if cancelled). This is the canonical way to invoke the
  /// picker from any UI surface (panel, on-canvas toolbars, etc.).
  static Future<String?> pickLink({
    required BuildContext context,
    required String initialValue,
    bool allowInternal = true,
    bool allowExternal = true,
    bool allowAnchor = true,
    bool darkStyle = false,
  }) {
    final workspace = WebsiteWorkspaceScope.maybeOf(context);
    return showDialog<_WebsiteLinkPickerResult>(
      context: context,
      builder: (context) => Theme(
        data: darkStyle ? ThemeData.dark() : Theme.of(context),
        child: _WebsiteLinkConfigurator(
          initialValue: initialValue,
          allowInternal: allowInternal,
          allowExternal: allowExternal,
          allowAnchor: allowAnchor,
          hasWorkspaceScope: workspace != null,
        ),
      ),
    ).then((result) {
      if (result == null) return null;
      final panel = result.openPanel;
      if (panel != null && workspace != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          workspace.open(panel);
        });
      }
      return result.href;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: darkStyle
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 6),
        ],
        _buildTrigger(context),
        if (helpText != null && helpText!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helpText!,
            style: TextStyle(
              fontSize: 11,
              color: darkStyle
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.grey[600],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrigger(BuildContext context) {
    // Generate a human-readable summary of the current link
    final summary = _summarizeLink(value);
    final icon = _getLinkIcon(value);

    return InkWell(
      onTap: () => _openConfigDialog(context),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: darkStyle
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey[100],
          border: Border.all(
            color: darkStyle
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: darkStyle
                  ? Colors.white.withValues(alpha: 0.7)
                  : Colors.grey[700],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: darkStyle
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.grey[800],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.edit,
              size: 14,
              color: darkStyle
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.grey[500],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openConfigDialog(BuildContext context) async {
    final newValue = await WebsiteLinkValueEditor.pickLink(
      context: context,
      initialValue: value,
      allowInternal: allowInternal,
      allowExternal: allowExternal,
      allowAnchor: allowAnchor,
      darkStyle: darkStyle,
    );

    if (newValue != null && newValue != value) {
      onChanged(newValue);
    }
  }

  String _summarizeLink(String href) {
    final destination = WebsiteDestination.parse(href);
    if (destination.kind == WebsiteDestinationKind.none) return 'Sin enlace';
    if (destination.kind == WebsiteDestinationKind.external) {
      return 'Externo: ${destination.href}';
    }
    if (destination.kind == WebsiteDestinationKind.anchor) {
      return 'Sección: #${destination.reference ?? ''}';
    }
    if (destination.kind == WebsiteDestinationKind.page) {
      return 'Página: ${destination.reference ?? destination.href}';
    }
    if (destination.kind == WebsiteDestinationKind.category) {
      final uri = Uri.tryParse(destination.href);
      final query =
          (uri?.queryParameters['q'] ?? uri?.queryParameters['search'] ?? '')
              .trim();
      return query.isEmpty
          ? 'Categoría del catálogo'
          : 'Catálogo filtrado: categoría + "$query"';
    }
    if (destination.kind == WebsiteDestinationKind.product) {
      return 'Producto específico';
    }

    // Check special mapping
    const specialMap = _WebsiteLinkConfigurator._specialDestinations;
    // Try exact match first
    for (final entry in specialMap.entries) {
      if (entry.key == href) return entry.value;
    }

    // Check approximate special matches (e.g. catalog filters)
    if (href.startsWith('/productos') || href.startsWith('/tienda/productos')) {
      final uri = Uri.tryParse(href);
      if (uri != null) {
        final q = uri.queryParameters['q'];
        if (q != null && q.isNotEmpty) return 'Catálogo: "$q"';

        final type = uri.queryParameters['type'];
        if (type == 'service') return 'Catálogo (Servicios)';
        if (type == 'product') return 'Catálogo (Productos)';

        final cat =
            uri.queryParameters['category'] ?? uri.queryParameters['cat'];
        if (cat != null) return 'Catálogo: categoría seleccionada';
      }
      return 'Catálogo';
    }

    if (href.startsWith('/pagina/') || href.startsWith('/shop/')) {
      // Try to extract slug
      final slug = href.split('/').last;
      return 'Página: $slug';
    }

    return 'Interno: $href';
  }

  IconData _getLinkIcon(String href) {
    return switch (WebsiteDestination.parse(href).kind) {
      WebsiteDestinationKind.none => Icons.link_off,
      WebsiteDestinationKind.external => Icons.open_in_new,
      WebsiteDestinationKind.anchor => Icons.tag,
      WebsiteDestinationKind.page => Icons.article_outlined,
      WebsiteDestinationKind.category => Icons.category_outlined,
      WebsiteDestinationKind.product => Icons.inventory_2_outlined,
      WebsiteDestinationKind.system => Icons.route_outlined,
      WebsiteDestinationKind.custom => Icons.code,
    };
  }
}

// ==============================================================================
// PRIVATE CONFIGURATOR: The Dialog Content
// ==============================================================================

enum WebsiteLinkEditMode {
  internal,
  external,
  anchor,
}

enum _InternalDestinationType {
  special,
  page,
  category,
  product,
  custom,
}

enum _CatalogTypeFilter {
  any,
  product,
  service,
}

class _CategoryOption {
  final String id;
  final String name;
  final String fullPath;
  final bool showOnWebsite;
  final int markedWebProductCount;

  const _CategoryOption({
    required this.id,
    required this.name,
    required this.fullPath,
    required this.showOnWebsite,
    required this.markedWebProductCount,
  });

  String get label => fullPath.trim().isEmpty ? name : fullPath;
  bool get isReady => showOnWebsite && markedWebProductCount > 0;
}

class _PageOption {
  const _PageOption({
    required this.id,
    required this.title,
    required this.slug,
    required this.href,
    required this.isPublished,
    required this.isHome,
  });

  final String id;
  final String title;
  final String slug;
  final String href;
  final bool isPublished;
  final bool isHome;
}

class _ProductOption {
  const _ProductOption({
    required this.id,
    required this.name,
    required this.sku,
    required this.isActive,
    required this.isPublished,
    required this.showOnWebsite,
  });

  final String id;
  final String name;
  final String sku;
  final bool isActive;
  final bool isPublished;
  final bool showOnWebsite;

  bool get isReady => isActive && isPublished && showOnWebsite;
  String get label => name.trim().isEmpty ? sku : name;
}

class _WebsiteLinkPickerResult {
  const _WebsiteLinkPickerResult(this.href, {this.openPanel});

  final String href;
  final WebsiteWorkspacePanel? openPanel;
}

class _WebsiteLinkConfigurator extends StatefulWidget {
  final String initialValue;
  final bool allowInternal;
  final bool allowExternal;
  final bool allowAnchor;
  final bool hasWorkspaceScope;

  const _WebsiteLinkConfigurator({
    required this.initialValue,
    required this.allowInternal,
    required this.allowExternal,
    required this.allowAnchor,
    required this.hasWorkspaceScope,
  });

  static const Map<String, String> _specialDestinations = {
    '/': 'Inicio',
    '/productos': 'Catálogo (Todos)',
    '/contacto': 'Contacto',
    '/carrito': 'Carrito',
    '/checkout': 'Checkout',
    '/cuenta': 'Mi cuenta',
    '/cuenta/login': 'Login',
    '/cuenta/pedidos': 'Mis pedidos',
    '/nosotros': 'Sobre Nosotros',
    '/terminos': 'Términos y Condiciones',
    '/privacidad': 'Política de Privacidad',
    '/devoluciones': 'Devoluciones',
    '/envios': 'Envíos',
  };

  @override
  State<_WebsiteLinkConfigurator> createState() =>
      _WebsiteLinkConfiguratorState();
}

class _WebsiteLinkConfiguratorState extends State<_WebsiteLinkConfigurator> {
  WebsiteLinkEditMode _mode = WebsiteLinkEditMode.internal;

  _InternalDestinationType _internalType = _InternalDestinationType.special;
  String _selectedSpecialHref = '/';
  String _selectedPageHref = '';
  _PageOption? _selectedPage;
  bool _loadingSelectedPage = false;
  bool _selectedPageLookupComplete = false;
  String _customInternalHref = '';

  // Catalog filters
  bool _isCatalog = false;
  final TextEditingController _catalogSearchController =
      TextEditingController();
  _CatalogTypeFilter _catalogType = _CatalogTypeFilter.any;
  String? _catalogCategoryId;

  // Anchor
  final TextEditingController _anchorController = TextEditingController();

  // External
  final TextEditingController _externalController = TextEditingController();

  bool _loadingCategories = false;
  List<_CategoryOption> _categories = const [];
  String? _categoriesError;

  bool _loadingProducts = false;
  List<_ProductOption> _products = const [];
  String? _productsError;
  String? _selectedProductId;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _hydrateFromValue(widget.initialValue);
  }

  @override
  void dispose() {
    _catalogSearchController.dispose();
    _anchorController.dispose();
    _externalController.dispose();
    super.dispose();
  }

  void _hydrateFromValue(String raw) {
    final v = raw.trim();

    // Default mode selection.
    if (v.startsWith('http://') || v.startsWith('https://')) {
      _mode = WebsiteLinkEditMode.external;
      _externalController.text = v;
      _isCatalog = false;
      return;
    }

    if (v.startsWith('#')) {
      _mode = WebsiteLinkEditMode.anchor;
      _anchorController.text = v.substring(1);
      _isCatalog = false;
      return;
    }

    _mode = WebsiteLinkEditMode.internal;

    final normalizedValue = WebsiteDestination.normalizeHref(v);
    final destination = WebsiteDestination.parse(normalizedValue);
    final uri = Uri.tryParse(normalizedValue);
    final path = uri?.path ?? normalizedValue;
    final isCatalogPath = path == '/productos' || path == '/tienda/productos';
    final catalogParameters = uri?.queryParameters ?? const <String, String>{};
    final hasCompositeCatalogFilter = isCatalogPath &&
        [
          catalogParameters['q'],
          catalogParameters['search'],
          catalogParameters['type'],
          catalogParameters['product_type'],
          catalogParameters['tipo'],
        ].any((value) => value?.trim().isNotEmpty == true);

    // Internal type: special
    final normalized = _normalizeInternalHref(v);
    const specialMap = _WebsiteLinkConfigurator._specialDestinations;
    final specialKey = specialMap.keys.firstWhere(
      (k) => _normalizeInternalHref(k) == normalized,
      orElse: () => '',
    );

    if (specialKey.isNotEmpty) {
      _internalType = _InternalDestinationType.special;
      _selectedSpecialHref = specialKey;
      _selectedPageHref = '';
      _customInternalHref = '';
    } else if (hasCompositeCatalogFilter) {
      // A category plus search/type is one filtered-catalog destination. Keep
      // it in the catalog-filter editor so every filter remains visible and
      // survives reopening the CTA control.
      _internalType = _InternalDestinationType.special;
      _selectedSpecialHref = '/productos';
      _selectedPageHref = '';
      _customInternalHref = '';
    } else if (destination.kind == WebsiteDestinationKind.category) {
      _internalType = _InternalDestinationType.category;
      _catalogCategoryId = destination.reference;
      _selectedSpecialHref = '/productos';
      _selectedPageHref = '';
      _customInternalHref = '';
      _isCatalog = false;
      _ensureCategoriesLoaded();
    } else if (destination.kind == WebsiteDestinationKind.product) {
      _internalType = _InternalDestinationType.product;
      _selectedProductId = destination.reference;
      _selectedSpecialHref = '/productos';
      _selectedPageHref = '';
      _customInternalHref = '';
      _isCatalog = false;
      _ensureProductsLoaded();
    } else if (isCatalogPath) {
      _internalType = _InternalDestinationType.special;
      _selectedSpecialHref = '/productos';
      _selectedPageHref = '';
      _customInternalHref = '';
    } else if (path.startsWith('/pagina/') || path.startsWith('/shop/')) {
      _internalType = _InternalDestinationType.page;
      _selectedPageHref = normalizedValue;
      _selectedSpecialHref = '/';
      _customInternalHref = '';
      _ensureSelectedPageLoaded();
    } else {
      _internalType = _InternalDestinationType.custom;
      _customInternalHref = normalizedValue;
      _selectedSpecialHref = '/';
      _selectedPageHref = '';
    }

    // Catalog filter parsing.
    _isCatalog =
        isCatalogPath && _internalType == _InternalDestinationType.special;
    if (_isCatalog) {
      final qp = uri?.queryParameters ?? const <String, String>{};
      final q = (qp['q'] ?? qp['search'] ?? '').trim();
      final type =
          (qp['type'] ?? qp['product_type'] ?? qp['tipo'] ?? '').trim();
      final category = (qp['category'] ??
              qp['category_id'] ??
              qp['cat'] ??
              qp['categoria'] ??
              '')
          .trim();

      _catalogSearchController.text = q;
      _catalogType = switch (type.toLowerCase()) {
        'product' || 'producto' || 'productos' => _CatalogTypeFilter.product,
        'service' || 'servicio' || 'servicios' => _CatalogTypeFilter.service,
        _ => _CatalogTypeFilter.any,
      };
      if (_internalType != _InternalDestinationType.category) {
        _catalogCategoryId = category.isEmpty ? null : category;
      }

      // We only try to load categories if the user is editing catalog filters.
      _ensureCategoriesLoaded();
    } else {
      _catalogSearchController.clear();
      _catalogType = _CatalogTypeFilter.any;
      _catalogCategoryId = null;
    }
  }

  String _normalizeInternalHref(String href) {
    // Normalize only internal paths; keep query string for stable matching.
    final v = href.trim();
    if (v.isEmpty) return '';
    final uri = Uri.tryParse(v);
    if (uri == null) return v;

    final path = uri.path.startsWith('/tienda/')
        ? uri.path.replaceFirst('/tienda', '')
        : uri.path;

    final qp = Map<String, String>.from(uri.queryParameters);

    // Normalize legacy category key to canonical for comparison.
    if (qp.containsKey('categoria') && !qp.containsKey('category')) {
      qp['category'] = qp.remove('categoria')!;
    }

    // Strip empty.
    qp.removeWhere((k, val) => val.trim().isEmpty);

    return Uri(path: path, queryParameters: qp.isEmpty ? null : qp).toString();
  }

  String _buildCatalogHref() {
    final qp = <String, String>{};

    final q = _catalogSearchController.text.trim();
    if (q.isNotEmpty) qp['q'] = q;

    switch (_catalogType) {
      case _CatalogTypeFilter.any:
        break;
      case _CatalogTypeFilter.product:
        qp['type'] = 'product';
      case _CatalogTypeFilter.service:
        qp['type'] = 'service';
    }

    final category = (_catalogCategoryId ?? '').trim();
    if (category.isNotEmpty) qp['category'] = category;

    return WebsiteDestination.routeForCatalog(
      categoryId: qp['category'],
      searchQuery: qp['q'],
      productType: qp['type'],
    );
  }

  String _currentInternalHref() {
    return switch (_internalType) {
      _InternalDestinationType.special => _selectedSpecialHref,
      _InternalDestinationType.page => _selectedPageHref,
      _InternalDestinationType.category => _catalogCategoryId == null
          ? ''
          : WebsiteDestination.routeForCatalog(
              categoryId: _catalogCategoryId,
            ),
      _InternalDestinationType.product =>
        _selectedProductId == null ? '' : '/productos/$_selectedProductId',
      _InternalDestinationType.custom => _customInternalHref,
    };
  }

  String _generateUrl() {
    return switch (_mode) {
      WebsiteLinkEditMode.external => _externalController.text.trim(),
      WebsiteLinkEditMode.anchor => _anchorController.text.trim().isEmpty
          ? ''
          : '#${_anchorController.text.trim()}',
      WebsiteLinkEditMode.internal => () {
          final internalHref = _currentInternalHref().trim();
          if (internalHref.isEmpty) return '';

          final uri = Uri.tryParse(internalHref);
          final path = uri?.path ?? internalHref;
          final isCatalog = path == '/productos' || path == '/tienda/productos';

          if (!isCatalog) return internalHref;
          return _buildCatalogHref();
        }(),
    };
  }

  Future<void> _ensureCategoriesLoaded() async {
    if (_loadingCategories) return;
    if (_categories.isNotEmpty) return;

    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });

    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo determinar tenant_id');
      }

      final rows = await Supabase.instance.client
          .from('product_categories')
          .select('id,name,full_path,is_active,show_on_website')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true);
      final productRows = await Supabase.instance.client
          .from('products')
          .select('category_id')
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .eq('is_published', true)
          .eq('show_on_website', true);

      final markedWebCounts = <String, int>{};
      for (final row in (productRows as List)) {
        final categoryId =
            (row as Map<String, dynamic>)['category_id']?.toString();
        if (categoryId == null || categoryId.isEmpty) continue;
        markedWebCounts[categoryId] = (markedWebCounts[categoryId] ?? 0) + 1;
      }

      final parsed = <_CategoryOption>[];
      for (final row in (rows as List)) {
        final map = row as Map<String, dynamic>;
        final id = map['id']?.toString();
        final name = map['name']?.toString();
        final fullPath = map['full_path']?.toString();
        final isActive = map['is_active'] == true;
        if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
        if (!isActive) continue;
        parsed.add(_CategoryOption(
          id: id,
          name: name,
          fullPath: fullPath ?? name,
          showOnWebsite: map['show_on_website'] == true,
          markedWebProductCount: markedWebCounts[id] ?? 0,
        ));
      }
      parsed.sort((a, b) => a.label.compareTo(b.label));

      if (!mounted) return;
      setState(() {
        _categories = parsed;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCategories = false;
        _categoriesError = e.toString();
      });
      if (kDebugMode) {
        debugPrint('❌ [WebsiteLinkValueEditor] load categories failed: $e');
      }
    }
  }

  Future<void> _ensureProductsLoaded() async {
    if (_loadingProducts || _products.isNotEmpty) return;
    setState(() {
      _loadingProducts = true;
      _productsError = null;
    });

    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo determinar tenant_id');
      }
      final rows = await Supabase.instance.client
          .from('products')
          .select('id,name,sku,is_active,is_published,show_on_website')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true)
          .limit(2000);
      final parsed = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map(
            (row) => _ProductOption(
              id: (row['id'] ?? '').toString(),
              name: (row['name'] ?? '').toString(),
              sku: (row['sku'] ?? '').toString(),
              isActive: row['is_active'] == true,
              isPublished: row['is_published'] == true,
              showOnWebsite: row['show_on_website'] == true,
            ),
          )
          .where((product) => product.id.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _products = parsed;
        _loadingProducts = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _productsError = error.toString();
        _loadingProducts = false;
      });
      if (kDebugMode) {
        debugPrint('❌ [WebsiteLinkValueEditor] load products failed: $error');
      }
    }
  }

  Future<void> _pickProduct(BuildContext context) async {
    await _ensureProductsLoaded();
    if (!mounted || !context.mounted) return;
    if (_productsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando productos: $_productsError')),
      );
      return;
    }

    final selected = await showDialog<_ProductOption>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = query.isEmpty
                ? _products
                : _products.where((product) {
                    final term = query.toLowerCase();
                    return product.name.toLowerCase().contains(term) ||
                        product.sku.toLowerCase().contains(term);
                  }).toList(growable: false);
            return AlertDialog(
              title: const Text('Elegir producto'),
              content: SizedBox(
                width: 540,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nombre o SKU…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialogState(() => query = value.trim());
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.inventory_2_outlined,
                              color: product.isReady
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.amber.shade700,
                            ),
                            title: Text(product.label),
                            subtitle: Text(
                              product.isReady
                                  ? 'SKU ${product.sku} · Publicado en web'
                                  : 'SKU ${product.sku} · No disponible en web',
                            ),
                            trailing: Icon(
                              product.isReady
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded,
                              size: 19,
                              color: product.isReady
                                  ? Colors.green.shade600
                                  : Colors.amber.shade700,
                            ),
                            onTap: () => Navigator.pop(dialogContext, product),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedProductId = selected.id);
  }

  _ProductOption? get _selectedProductOption {
    final id = _selectedProductId;
    if (id == null || id.isEmpty) return null;
    for (final product in _products) {
      if (product.id == id || product.sku == id) return product;
    }
    return null;
  }

  Future<_PageOption?> _pickWebsitePage(BuildContext context) async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) return null;

    final rows = await Supabase.instance.client
        .from('website_pages')
        .select('id,slug,title,is_home,is_published,is_system')
        .eq('tenant_id', tenantId)
        .order('is_home', ascending: false)
        .order('title', ascending: true);

    if (!context.mounted) return null;

    final pages = (rows as List)
        .map((e) => e as Map<String, dynamic>)
        .map((e) {
          final slug = (e['slug'] ?? '').toString();
          final title = (e['title'] ?? '').toString();
          final isHome = e['is_home'] == true;
          return _PageOption(
            id: (e['id'] ?? '').toString(),
            slug: slug,
            title: title,
            isHome: isHome,
            isPublished: e['is_published'] == true,
            href: WebsiteDestination.routeForPage(
              slug: slug,
              isHome: isHome,
            ),
          );
        })
        .where((p) => p.isHome || p.slug.isNotEmpty)
        .toList(growable: false);

    // Capture theme from parent to ensure dark mode persists in dialog
    final parentTheme = Theme.of(context);
    final isDark = parentTheme.brightness == Brightness.dark;

    // Custom dark theme for the editor style
    final editorTheme = isDark
        ? parentTheme.copyWith(
            scaffoldBackgroundColor: const Color(0xFF1E1E1E),
            dividerColor: Colors.white.withValues(alpha: 0.1),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2C2C2C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              prefixIconColor: Colors.white.withValues(alpha: 0.4),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
            textTheme: parentTheme.textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            listTileTheme: ListTileThemeData(
              iconColor: Colors.white.withValues(alpha: 0.7),
              textColor: Colors.white,
            ),
            dialogTheme:
                const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
          )
        : parentTheme;

    final selected = await showDialog<_PageOption>(
      context: context,
      builder: (context) {
        final searchController = TextEditingController();
        var filtered = pages;

        return Theme(
          data: editorTheme,
          child: Dialog(
            backgroundColor: editorTheme.dialogTheme.backgroundColor,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 500,
              height: 600,
              child: Scaffold(
                backgroundColor: editorTheme.scaffoldBackgroundColor,
                appBar: AppBar(
                  title: const Text('Ir a página'),
                  centerTitle: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: StatefulBuilder(
                  builder: (context, setState) {
                    void applyFilter(String q) {
                      final term = q.trim().toLowerCase();
                      setState(() {
                        if (term.isEmpty) {
                          filtered = pages;
                        } else {
                          filtered = pages
                              .where((p) =>
                                  p.title.toLowerCase().contains(term) ||
                                  p.slug.toLowerCase().contains(term))
                              .toList(growable: false);
                        }
                      });
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: TextField(
                            controller: searchController,
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Buscar páginas (título o ruta)',
                            ),
                            onChanged: applyFilter,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 64),
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    p.isHome
                                        ? Icons.home_filled
                                        : Icons.article,
                                    size: 20,
                                    color: isDark
                                        ? const Color(0xFF64B5F6)
                                        : Colors.blue,
                                  ),
                                ),
                                title: Text(
                                  p.isHome ? 'Inicio' : p.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  p.isPublished
                                      ? p.href
                                      : '${p.href} · Borrador',
                                  style: TextStyle(
                                    color: p.isPublished
                                        ? (isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.5)
                                            : Colors.grey[600])
                                        : Colors.amber.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Icon(
                                  p.isPublished
                                      ? Icons.check_circle_outline
                                      : Icons.edit_note_outlined,
                                  size: 19,
                                  color: p.isPublished
                                      ? Colors.green.shade600
                                      : Colors.amber.shade700,
                                ),
                                hoverColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                onTap: () => Navigator.pop(context, p),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    return selected;
  }

  Future<void> _ensureSelectedPageLoaded() async {
    final destination = WebsiteDestination.parse(_selectedPageHref);
    final slug = destination.kind == WebsiteDestinationKind.page
        ? destination.reference
        : null;
    if (slug == null || slug.isEmpty || _loadingSelectedPage) return;
    setState(() => _loadingSelectedPage = true);
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        if (mounted) {
          setState(() {
            _selectedPageLookupComplete = true;
            _loadingSelectedPage = false;
          });
        }
        return;
      }
      final rows = await Supabase.instance.client
          .from('website_pages')
          .select('id,slug,title,is_home,is_published')
          .eq('tenant_id', tenantId)
          .eq('slug', slug)
          .limit(1);
      final list = rows as List;
      _PageOption? page;
      if (list.isNotEmpty) {
        final row = Map<String, dynamic>.from(list.first as Map);
        final pageSlug = (row['slug'] ?? '').toString();
        final isHome = row['is_home'] == true;
        page = _PageOption(
          id: (row['id'] ?? '').toString(),
          title: (row['title'] ?? '').toString(),
          slug: pageSlug,
          href: WebsiteDestination.routeForPage(
            slug: pageSlug,
            isHome: isHome,
          ),
          isPublished: row['is_published'] == true,
          isHome: isHome,
        );
      }
      if (!mounted) return;
      setState(() {
        _selectedPage = page;
        _selectedPageLookupComplete = true;
        _loadingSelectedPage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selectedPageLookupComplete = true;
        _loadingSelectedPage = false;
      });
    }
  }

  Future<void> _pickCategory(BuildContext context) async {
    await _ensureCategoriesLoaded();
    if (!mounted || !context.mounted) return;

    if (_categoriesError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando categorías: $_categoriesError')),
      );
      return;
    }

    // Reuse the same theme logic (you might want to extract this to a method in a real refactor)
    final parentTheme = Theme.of(context);
    final isDark = parentTheme.brightness == Brightness.dark;

    final editorTheme = isDark
        ? parentTheme.copyWith(
            scaffoldBackgroundColor: const Color(0xFF1E1E1E),
            dividerColor: Colors.white.withValues(alpha: 0.1),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2C2C2C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              prefixIconColor: Colors.white.withValues(alpha: 0.4),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
            textTheme: parentTheme.textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            listTileTheme: ListTileThemeData(
              iconColor: Colors.white.withValues(alpha: 0.7),
              textColor: Colors.white,
            ),
            dialogTheme:
                const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
          )
        : parentTheme;

    final selected = await showDialog<_CategoryOption>(
      context: context,
      builder: (context) {
        final searchController = TextEditingController();
        var filtered = _categories;

        return Theme(
          data: editorTheme,
          child: Dialog(
            backgroundColor: editorTheme.dialogTheme.backgroundColor,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 500,
              height: 600,
              child: Scaffold(
                backgroundColor: editorTheme.scaffoldBackgroundColor,
                appBar: AppBar(
                  title: const Text('Elegir categoría'),
                  centerTitle: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                body: StatefulBuilder(
                  builder: (context, setState) {
                    void applyFilter(String q) {
                      final term = q.trim().toLowerCase();
                      setState(() {
                        if (term.isEmpty) {
                          filtered = _categories;
                        } else {
                          filtered = _categories
                              .where(
                                  (c) => c.label.toLowerCase().contains(term))
                              .toList(growable: false);
                        }
                      });
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: TextField(
                            controller: searchController,
                            style: TextStyle(
                                color: isDark ? Colors.white : Colors.black),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Buscar categoría…',
                            ),
                            onChanged: applyFilter,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 64),
                            itemBuilder: (context, index) {
                              final c = filtered[index];
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.category_outlined,
                                    size: 20,
                                    color: isDark
                                        ? const Color(0xFF64B5F6)
                                        : Colors.blue,
                                  ),
                                ),
                                title: Text(c.label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                subtitle: Text(
                                  c.showOnWebsite
                                      ? '${c.markedWebProductCount} productos marcados para web'
                                      : 'Oculta del catálogo público',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.5)
                                        : Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Icon(
                                  c.isReady
                                      ? Icons.check_circle_outline
                                      : Icons.warning_amber_rounded,
                                  color: c.isReady
                                      ? Colors.green.shade600
                                      : Colors.amber.shade700,
                                  size: 20,
                                ),
                                hoverColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                onTap: () => Navigator.pop(context, c),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    setState(() => _catalogCategoryId = selected.id);
  }

  _CategoryOption? get _selectedCategoryOption {
    final id = _catalogCategoryId;
    if (id == null || id.isEmpty) return null;
    for (final category in _categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  InputDecoration _decoration(String label) {
    // Standardize input decoration for the dialog
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowedModes = <WebsiteLinkEditMode>[];
    if (widget.allowInternal) allowedModes.add(WebsiteLinkEditMode.internal);
    if (widget.allowExternal) allowedModes.add(WebsiteLinkEditMode.external);
    if (widget.allowAnchor) allowedModes.add(WebsiteLinkEditMode.anchor);

    if (!allowedModes.contains(_mode) && allowedModes.isNotEmpty) {
      _mode = allowedModes.first;
    }

    return AlertDialog(
      title: const Text('Configurar enlace'),
      content: SizedBox(
        width: 500, // Constrained width for the floating block feel
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<WebsiteLinkEditMode>(
                initialValue: _mode,
                decoration: _decoration('Tipo de enlace'),
                items: [
                  if (widget.allowInternal)
                    const DropdownMenuItem(
                      value: WebsiteLinkEditMode.internal,
                      child: Text('Interno (Página/Catálogo)'),
                    ),
                  if (widget.allowExternal)
                    const DropdownMenuItem(
                      value: WebsiteLinkEditMode.external,
                      child: Text('Externo (URL)'),
                    ),
                  if (widget.allowAnchor)
                    const DropdownMenuItem(
                      value: WebsiteLinkEditMode.anchor,
                      child: Text('Ancla (#)'),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _mode = v);
                },
              ),
              const SizedBox(height: 16),
              if (_mode == WebsiteLinkEditMode.external)
                TextFormField(
                  controller: _externalController,
                  decoration: _decoration('URL externa')
                      .copyWith(prefixIcon: const Icon(Icons.open_in_new)),
                )
              else if (_mode == WebsiteLinkEditMode.anchor)
                TextFormField(
                  controller: _anchorController,
                  decoration: _decoration('ID de ancla')
                      .copyWith(prefixIcon: const Icon(Icons.tag)),
                )
              else
                _buildInternalSection(),
              if (_validationMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _validationMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }

  void _apply({WebsiteWorkspacePanel? openPanel}) {
    final url = _generateUrl().trim();
    if (url.isEmpty) {
      setState(() => _validationMessage = 'Selecciona un destino.');
      return;
    }
    if (_mode == WebsiteLinkEditMode.external &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      setState(() => _validationMessage =
          'La URL externa debe comenzar con http:// o https://.');
      return;
    }
    Navigator.of(context).pop(
      _WebsiteLinkPickerResult(url, openPanel: openPanel),
    );
  }

  Widget _buildPageDestination() {
    final page = _selectedPage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: _decoration('Página').copyWith(
            suffixIcon: IconButton(
              tooltip: 'Quitar página',
              onPressed: _selectedPageHref.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectedPageHref = '';
                        _selectedPage = null;
                        _selectedPageLookupComplete = false;
                      });
                    },
              icon: const Icon(Icons.clear),
            ),
          ),
          child: InkWell(
            onTap: () async {
              final selected = await _pickWebsitePage(context);
              if (!mounted || selected == null) return;
              setState(() {
                _selectedPage = selected;
                _selectedPageHref = selected.href;
                _selectedPageLookupComplete = true;
                _validationMessage = null;
              });
            },
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    page?.title ??
                        (_selectedPageHref.isEmpty
                            ? 'Elegir una página…'
                            : _selectedPageHref),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontStyle: _selectedPageHref.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_loadingSelectedPage) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ] else if (_selectedPageHref.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildReadinessCard(
            ready: page?.isPublished ?? false,
            message: page == null && _selectedPageLookupComplete
                ? 'No existe una página CMS con esta ruta.'
                : page == null
                    ? 'Comprobando la página seleccionada…'
                    : page.isPublished
                        ? 'Página publicada y lista para recibir visitas.'
                        : 'La página existe, pero todavía está en borrador.',
            actionLabel: 'Administrar página',
            panel: WebsiteWorkspacePanel.pages,
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryDestination() {
    final category = _selectedCategoryOption;
    final missingSelection = !_loadingCategories &&
        _catalogCategoryId != null &&
        _categories.isNotEmpty &&
        category == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: category?.id,
                isExpanded: true,
                decoration: _decoration('Categoría'),
                hint: Text(_loadingCategories
                    ? 'Cargando categorías…'
                    : 'Seleccionar categoría'),
                items: _categories
                    .map(
                      (option) => DropdownMenuItem<String?>(
                        value: option.id,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _loadingCategories
                    ? null
                    : (value) {
                        setState(() {
                          _catalogCategoryId = value;
                          _validationMessage = null;
                        });
                      },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Buscar categoría',
              onPressed:
                  _loadingCategories ? null : () => _pickCategory(context),
              icon: _loadingCategories
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ],
        ),
        if (_categoriesError != null) ...[
          const SizedBox(height: 8),
          Text('No se pudieron cargar las categorías.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (category != null || missingSelection) ...[
          const SizedBox(height: 8),
          _buildReadinessCard(
            ready: category?.isReady ?? false,
            message: missingSelection
                ? 'La categoría guardada ya no existe o no está activa.'
                : category!.isReady
                    ? 'Categoría visible con ${category.markedWebProductCount} productos marcados para web.'
                    : category.showOnWebsite
                        ? 'La categoría está visible, pero no tiene productos marcados para web.'
                        : 'La categoría está oculta del catálogo público.',
            actionLabel: 'Configurar categoría',
            panel: WebsiteWorkspacePanel.catalogCategories,
          ),
        ],
      ],
    );
  }

  Widget _buildProductDestination() {
    final product = _selectedProductOption;
    final missingSelection = !_loadingProducts &&
        _selectedProductId != null &&
        _products.isNotEmpty &&
        product == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: _decoration('Producto').copyWith(
            suffixIcon: IconButton(
              tooltip: 'Buscar producto',
              onPressed: _loadingProducts ? null : () => _pickProduct(context),
              icon: _loadingProducts
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ),
          child: InkWell(
            onTap: _loadingProducts ? null : () => _pickProduct(context),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    product?.label ??
                        (_selectedProductId == null
                            ? 'Elegir un producto…'
                            : _selectedProductId!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontStyle: _selectedProductId == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_productsError != null) ...[
          const SizedBox(height: 8),
          Text('No se pudieron cargar los productos.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (product != null || missingSelection) ...[
          const SizedBox(height: 8),
          _buildReadinessCard(
            ready: product?.isReady ?? false,
            message: missingSelection
                ? 'El producto guardado ya no existe.'
                : product!.isReady
                    ? 'Producto publicado y disponible para enlaces web.'
                    : 'El producto existe, pero no está publicado en la web.',
            actionLabel: 'Configurar producto',
            panel: WebsiteWorkspacePanel.catalogProducts,
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedDestination() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: _customInternalHref,
          decoration: _decoration('Ruta interna')
              .copyWith(prefixIcon: const Icon(Icons.code)),
          onChanged: (value) => _customInternalHref = value,
        ),
        const SizedBox(height: 8),
        _buildReadinessCard(
          ready: false,
          message:
              'Usa esta opción solo para rutas especiales. No crea una página CMS ni un elemento de navegación.',
          actionLabel: 'Revisar destinos',
          panel: WebsiteWorkspacePanel.destinations,
        ),
      ],
    );
  }

  Widget _buildReadinessCard({
    required bool ready,
    required String message,
    required String actionLabel,
    required WebsiteWorkspacePanel panel,
  }) {
    final theme = Theme.of(context);
    final background = ready
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.32)
        : Colors.amber.withValues(alpha: 0.12);
    final foreground =
        ready ? theme.colorScheme.primary : Colors.amber.shade800;
    final canManage = widget.hasWorkspaceScope;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          if (canManage) ...[
            const SizedBox(width: 6),
            TextButton(
              onPressed: () => _apply(openPanel: panel),
              child: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInternalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<_InternalDestinationType>(
          initialValue: _internalType,
          decoration: _decoration('Destino'),
          items: const [
            DropdownMenuItem(
              value: _InternalDestinationType.special,
              child: Text('Destino especial'),
            ),
            DropdownMenuItem(
              value: _InternalDestinationType.page,
              child: Text('Página del sitio'),
            ),
            DropdownMenuItem(
              value: _InternalDestinationType.category,
              child: Text('Categoría del catálogo'),
            ),
            DropdownMenuItem(
              value: _InternalDestinationType.product,
              child: Text('Producto específico'),
            ),
            DropdownMenuItem(
              value: _InternalDestinationType.custom,
              child: Text('Ruta interna avanzada'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _internalType = v;
              _validationMessage = null;
              _isCatalog = v == _InternalDestinationType.special &&
                  _selectedSpecialHref == '/productos';
            });
            if (v == _InternalDestinationType.category) {
              _ensureCategoriesLoaded();
            } else if (v == _InternalDestinationType.product) {
              _ensureProductsLoaded();
            }
          },
        ),
        const SizedBox(height: 16),
        if (_internalType == _InternalDestinationType.special)
          DropdownButtonFormField<String>(
            initialValue: _selectedSpecialHref,
            decoration: _decoration('Seleccionar destino'),
            items: _WebsiteLinkConfigurator._specialDestinations.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ),
                )
                .toList(growable: false),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _selectedSpecialHref = v;
                final uri = Uri.tryParse(v);
                final path = uri?.path ?? v;
                _isCatalog =
                    path == '/productos' || path == '/tienda/productos';
                if (_isCatalog) {
                  // Seed filters based on shortcut.
                  final qp = uri?.queryParameters ?? const <String, String>{};
                  final type = (qp['type'] ?? '').trim().toLowerCase();
                  _catalogType = switch (type) {
                    'product' => _CatalogTypeFilter.product,
                    'service' => _CatalogTypeFilter.service,
                    _ => _CatalogTypeFilter.any,
                  };
                  _ensureCategoriesLoaded();
                } else {
                  _catalogSearchController.clear();
                  _catalogType = _CatalogTypeFilter.any;
                  _catalogCategoryId = null;
                }
              });
            },
          )
        else if (_internalType == _InternalDestinationType.page)
          _buildPageDestination()
        else if (_internalType == _InternalDestinationType.category)
          _buildCategoryDestination()
        else if (_internalType == _InternalDestinationType.product)
          _buildProductDestination()
        else
          _buildAdvancedDestination(),
        if (_isCatalog) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Filtros del catálogo',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _catalogSearchController,
            decoration: _decoration('Buscar')
                .copyWith(prefixIcon: const Icon(Icons.search)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_CatalogTypeFilter>(
            initialValue: _catalogType,
            decoration: _decoration('Tipo'),
            items: const [
              DropdownMenuItem(
                value: _CatalogTypeFilter.any,
                child: Text('Todos'),
              ),
              DropdownMenuItem(
                value: _CatalogTypeFilter.product,
                child: Text('Productos'),
              ),
              DropdownMenuItem(
                value: _CatalogTypeFilter.service,
                child: Text('Servicios'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _catalogType = v);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _selectedCategoryOption?.id,
                  decoration: _decoration('Categoría'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ..._categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _catalogCategoryId = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Buscar categoría…',
                onPressed:
                    _loadingCategories ? null : () => _pickCategory(context),
                icon: _loadingCategories
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ],
          ),
          if (_selectedCategoryOption case final category?) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: category.isReady
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: category.isReady
                      ? Colors.green.withValues(alpha: 0.35)
                      : Colors.amber.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    category.isReady
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: category.isReady
                        ? Colors.green.shade700
                        : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.isReady
                          ? 'Categoría visible con ${category.markedWebProductCount} productos marcados para web.'
                          : category.showOnWebsite
                              ? 'La categoría está visible, pero no tiene productos marcados para web.'
                              : 'La categoría está oculta. Publícala en Catálogo web > Categorías antes de usar este enlace.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
