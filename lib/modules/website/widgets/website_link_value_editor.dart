import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';

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
    return showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: darkStyle ? ThemeData.dark() : Theme.of(context),
        child: _WebsiteLinkConfigurator(
          initialValue: initialValue,
          allowInternal: allowInternal,
          allowExternal: allowExternal,
          allowAnchor: allowAnchor,
        ),
      ),
    );
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
              color:
                  darkStyle ? Colors.white.withValues(alpha: 0.9) : Colors.grey[700],
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
              color:
                  darkStyle ? Colors.white.withValues(alpha: 0.5) : Colors.grey[600],
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
          color: darkStyle ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
          border: Border.all(
            color:
                darkStyle ? Colors.white.withValues(alpha: 0.1) : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color:
                  darkStyle ? Colors.white.withValues(alpha: 0.7) : Colors.grey[700],
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
              color:
                  darkStyle ? Colors.white.withValues(alpha: 0.4) : Colors.grey[500],
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
    if (href.isEmpty) return 'Sin enlace';
    if (href.startsWith('http')) return 'Externo: $href';
    if (href.startsWith('#')) return 'Ancla: $href';

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
        if (cat != null) return 'Catálogo: Categoria #$cat';
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
    if (href.isEmpty) return Icons.link_off;
    if (href.startsWith('http')) return Icons.open_in_new;
    if (href.startsWith('#')) return Icons.tag;
    if (href.startsWith('/productos')) return Icons.shopping_bag_outlined;
    if (href.startsWith('/pagina')) return Icons.article_outlined;
    return Icons.link;
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

  const _CategoryOption({
    required this.id,
    required this.name,
  });
}

class _WebsiteLinkConfigurator extends StatefulWidget {
  final String initialValue;
  final bool allowInternal;
  final bool allowExternal;
  final bool allowAnchor;

  const _WebsiteLinkConfigurator({
    required this.initialValue,
    required this.allowInternal,
    required this.allowExternal,
    required this.allowAnchor,
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

    final uri = Uri.tryParse(v);
    final path = uri?.path ?? v;
    final isCatalogPath = path == '/productos' || path == '/tienda/productos';

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
    } else if (isCatalogPath) {
      _internalType = _InternalDestinationType.special;
      _selectedSpecialHref = '/productos';
      _selectedPageHref = '';
      _customInternalHref = '';
    } else if (path.startsWith('/pagina/') || path.startsWith('/shop/')) {
      _internalType = _InternalDestinationType.page;
      _selectedPageHref = v;
      _selectedSpecialHref = '/';
      _customInternalHref = '';
    } else {
      _internalType = _InternalDestinationType.custom;
      _customInternalHref = v;
      _selectedSpecialHref = '/';
      _selectedPageHref = '';
    }

    // Catalog filter parsing.
    _isCatalog = path == '/productos' || path == '/tienda/productos';
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
      _catalogCategoryId = category.isEmpty ? null : category;

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

    final uri =
        Uri(path: '/productos', queryParameters: qp.isEmpty ? null : qp);
    return uri.toString();
  }

  String _currentInternalHref() {
    return switch (_internalType) {
      _InternalDestinationType.special => _selectedSpecialHref,
      _InternalDestinationType.page => _selectedPageHref,
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

      // Load from product_categories table
      final rows = await Supabase.instance.client
          .from('product_categories')
          .select('id,name,is_active')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true);

      final parsed = <_CategoryOption>[];
      for (final row in (rows as List)) {
        final map = row as Map<String, dynamic>;
        final id = map['id']?.toString();
        final name = map['name']?.toString();
        final isActive = map['is_active'] == true;
        if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
        if (!isActive) continue;
        parsed.add(_CategoryOption(id: id, name: name));
      }

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

  Future<String?> _pickWebsitePageHref(BuildContext context) async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) return null;

    final rows = await Supabase.instance.client
        .from('website_pages')
        .select('id,slug,title,is_home,is_published,is_system')
        .eq('tenant_id', tenantId)
        .eq('is_published', true)
        .order('is_home', ascending: false)
        .order('title', ascending: true);

    if (!context.mounted) return null;

    final pages = (rows as List)
        .map((e) => e as Map<String, dynamic>)
        .map((e) {
          final slug = (e['slug'] ?? '').toString();
          final title = (e['title'] ?? '').toString();
          final isHome = e['is_home'] == true;
          return (slug: slug, title: title, isHome: isHome);
        })
        .where((p) => p.isHome || p.slug.isNotEmpty)
        .toList(growable: false);

    String routeForSlug({required String slug, required bool isHome}) {
      if (isHome) return '/';
      const systemSlugToPath = {
        'nosotros': '/nosotros',
        'terminos': '/terminos',
        'privacidad': '/privacidad',
        'devoluciones': '/devoluciones',
        'envios': '/envios',
      };
      return systemSlugToPath[slug] ?? '/pagina/$slug';
    }

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
            ), dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
          )
        : parentTheme;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        final searchController = TextEditingController();
        var filtered = pages;

        return Theme(
          data: editorTheme,
          child: Dialog(
            backgroundColor: editorTheme.dialogBackgroundColor,
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
                              final href = routeForSlug(
                                slug: p.slug,
                                isHome: p.isHome,
                              );
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
                                  href,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.5)
                                        : Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                hoverColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                onTap: () => Navigator.pop(context, href),
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

  Future<void> _pickCategory(BuildContext context) async {
    await _ensureCategoriesLoaded();
    if (!mounted) return;

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
            ), dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
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
            backgroundColor: editorTheme.dialogBackgroundColor,
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
                              .where((c) => c.name.toLowerCase().contains(term))
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
                                title: Text(c.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                subtitle: Text(
                                  c.id,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.5)
                                        : Colors.grey[600],
                                    fontSize: 12,
                                  ),
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
          onPressed: () {
            final url = _generateUrl();
            Navigator.of(context).pop(url);
          },
          child: const Text('Guardar'),
        ),
      ],
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
              value: _InternalDestinationType.custom,
              child: Text('Ruta personalizada'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _internalType = v);
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
          InputDecorator(
            decoration: _decoration('Página').copyWith(
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _selectedPageHref = '');
                },
                icon: const Icon(Icons.clear),
              ),
            ),
            child: InkWell(
              onTap: () async {
                final href = await _pickWebsitePageHref(context);
                if (!mounted) return;
                if (href == null || href.trim().isEmpty) return;
                setState(() {
                  _selectedPageHref = href;
                  _isCatalog = href.startsWith('/productos');
                  if (_isCatalog) _ensureCategoriesLoaded();
                });
              },
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedPageHref.isEmpty
                          ? 'Toca para elegir página...'
                          : _selectedPageHref,
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
          )
        else
          TextFormField(
            initialValue: _customInternalHref,
            decoration: _decoration('Ruta interna')
                .copyWith(prefixIcon: const Icon(Icons.link)),
            onChanged: (v) {
              _customInternalHref = v;
              final uri = Uri.tryParse(v.trim());
              final path = uri?.path ?? v.trim();
              final nextIsCatalog =
                  path == '/productos' || path == '/tienda/productos';
              if (nextIsCatalog && !_isCatalog) {
                setState(() => _isCatalog = true);
                _ensureCategoriesLoaded();
              } else if (!nextIsCatalog && _isCatalog) {
                setState(() {
                  _isCatalog = false;
                  _catalogSearchController.clear();
                  _catalogType = _CatalogTypeFilter.any;
                  _catalogCategoryId = null;
                });
              }
            },
          ),
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
                  initialValue: (_catalogCategoryId != null &&
                          _catalogCategoryId!.isNotEmpty)
                      ? _catalogCategoryId
                      : null,
                  decoration: _decoration('Categoría'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ..._categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name),
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
        ],
      ],
    );
  }
}
