part of '../website_editor_panel.dart';

// (removed) Canvas-specific picker dialog; Canvas reuses `_ProductPickerDialog` for consistency.

/// Page settings tab for page-level SEO (meta title, description)
/// Minimal, clean interface following existing patterns
class _PageSettingsTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;

  const _PageSettingsTab({required this.editProvider});

  @override
  State<_PageSettingsTab> createState() => _PageSettingsTabState();
}

class _PageSettingsLoadStamp {
  const _PageSettingsLoadStamp({
    required this.provider,
    required this.service,
    required this.generation,
    required this.route,
    required this.pageId,
    required this.pageSlug,
    required this.documentSessionRevision,
    required this.entryLeaseGeneration,
    required this.entryLeaseIdentityRevision,
    required this.serviceIdentityEpoch,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteService service;
  final int generation;
  final String route;
  final String? pageId;
  final String? pageSlug;
  final int documentSessionRevision;
  final int entryLeaseGeneration;
  final int entryLeaseIdentityRevision;
  final int serviceIdentityEpoch;

  bool matches({
    required WebsiteEditModeProvider liveProvider,
    required WebsiteService liveService,
    required String liveRoute,
  }) {
    return identical(provider, liveProvider) &&
        identical(service, liveService) &&
        route == liveRoute &&
        pageId == liveProvider.currentPageId &&
        pageSlug == liveProvider.currentPageSlug &&
        documentSessionRevision == liveProvider.documentSessionRevision &&
        entryLeaseGeneration == liveProvider.editorEntryLeaseGeneration &&
        entryLeaseIdentityRevision ==
            liveProvider.editorEntryLeaseIdentityRevision &&
        serviceIdentityEpoch == liveService.identityEpoch;
  }
}

class _PageSettingsTabState extends State<_PageSettingsTab> {
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  bool _isLoading = true;
  int _loadGeneration = 0;
  bool _reloadScheduled = false;
  _PageSettingsLoadStamp? _activeLoad;
  _PageSettingsLoadStamp? _appliedLoad;
  WebsiteService? _listenedService;
  int _observedServiceIdentityEpoch = -1;
  // ignore: unused_field
  WebsitePage? _currentPage;
  String _currentRoute = '';
  bool _isSpecialRoute = false;

  @override
  void initState() {
    super.initState();
    // Resolve the router and service after the first frame.
    _scheduleReload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<WebsiteService>();
    if (!identical(_listenedService, service)) {
      _listenedService?.removeListener(_handleServiceChanged);
      _listenedService = service;
      _observedServiceIdentityEpoch = service.identityEpoch;
      service.addListener(_handleServiceChanged);
    }
  }

  @override
  void didUpdateWidget(covariant _PageSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.editProvider, widget.editProvider)) {
      _scheduleReload();
    }
  }

  @override
  void dispose() {
    _listenedService?.removeListener(_handleServiceChanged);
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    super.dispose();
  }

  void _handleServiceChanged() {
    final service = _listenedService;
    if (!mounted || service == null) return;
    if (_observedServiceIdentityEpoch == service.identityEpoch) return;
    _observedServiceIdentityEpoch = service.identityEpoch;
    _scheduleReload();
  }

  String _resolvedRoute() {
    var route =
        _getSlugFromRoute() ?? widget.editProvider.currentPageSlug ?? 'inicio';
    if (route.isEmpty) route = 'inicio';
    return route;
  }

  void _scheduleReload() {
    if (!mounted || _reloadScheduled) return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadScheduled = false;
      if (!mounted) return;
      _detectCurrentPage(force: true);
    });
  }

  Future<void> _detectCurrentPage({bool force = false}) async {
    if (!mounted || (!force && _activeLoad != null)) return;

    // Prefer detecting route from actual URL, fallback to provider.
    final newRoute = _resolvedRoute();

    debugPrint('📄 [PageSettingsTab] Detecting page: $newRoute');

    // Avoid reloading if neither route nor exact owner changed.
    final service = context.read<WebsiteService>();
    final current = _appliedLoad;
    if (!force &&
        newRoute == _currentRoute &&
        !_isLoading &&
        current != null &&
        current.matches(
          liveProvider: widget.editProvider,
          liveService: service,
          liveRoute: newRoute,
        )) {
      return;
    }

    final generation = ++_loadGeneration;
    final stamp = _PageSettingsLoadStamp(
      provider: widget.editProvider,
      service: service,
      generation: generation,
      route: newRoute,
      pageId: widget.editProvider.currentPageId,
      pageSlug: widget.editProvider.currentPageSlug,
      documentSessionRevision: widget.editProvider.documentSessionRevision,
      entryLeaseGeneration: widget.editProvider.editorEntryLeaseGeneration,
      entryLeaseIdentityRevision:
          widget.editProvider.editorEntryLeaseIdentityRevision,
      serviceIdentityEpoch: service.identityEpoch,
    );
    _activeLoad = stamp;

    setState(() {
      _currentRoute = newRoute;
      _currentPage = null;
      _metaTitleController.clear();
      _metaDescriptionController.clear();
      _isLoading = true;
    });

    // Check if this is a special route (not a CMS page).
    const specialRoutes = ['productos', 'contacto', 'carrito', 'checkout'];
    _isSpecialRoute = specialRoutes.any((r) => newRoute.startsWith(r));

    // Special route check logic preserved, but early return removed.
    // We now attempt to load from DB first for ALL routes.
    try {
      await _loadPageData(stamp);
    } finally {
      if (identical(_activeLoad, stamp)) {
        _activeLoad = null;
      }
    }
  }

  /// Detect current slug from URL route (handles /tienda prefix and various patterns)
  String? _getSlugFromRoute() {
    try {
      final uri = GoRouterState.of(context).uri;
      var path = uri.path;

      // Remove /tienda prefix if present
      if (path.startsWith('/tienda')) {
        path = path.substring('/tienda'.length);
      }
      if (path.isEmpty || path == '/') return 'inicio';
      if (!path.startsWith('/')) path = '/$path';

      // Known canonical routes
      const canonicalRoutes = {
        '/productos': 'productos',
        '/contacto': 'contacto',
        '/carrito': 'carrito',
        '/checkout': 'checkout',
        '/cuenta': 'cuenta',
      };
      if (canonicalRoutes.containsKey(path)) {
        return canonicalRoutes[path]!;
      }

      // Policy pages at root level
      const policySlugs = {
        'nosotros',
        'terminos',
        'privacidad',
        'devoluciones',
        'envios'
      };
      final rootSlug = path.substring(1);
      if (policySlugs.contains(rootSlug)) return rootSlug;

      // /pagina/<slug> pattern
      if (path.startsWith('/pagina/')) return path.substring('/pagina/'.length);

      // Simple slug
      if (!rootSlug.contains('/')) return rootSlug;

      return null;
    } catch (_) {
      return null;
    }
  }

  bool _ownsLoad(_PageSettingsLoadStamp stamp) {
    if (!mounted ||
        _loadGeneration != stamp.generation ||
        !identical(_activeLoad, stamp)) {
      return false;
    }
    return stamp.matches(
      liveProvider: widget.editProvider,
      liveService: context.read<WebsiteService>(),
      liveRoute: _resolvedRoute(),
    );
  }

  void _rejectStaleLoad(_PageSettingsLoadStamp stamp) {
    if (!identical(_activeLoad, stamp)) return;
    _activeLoad = null;
    _scheduleReload();
  }

  Future<void> _loadPageData(_PageSettingsLoadStamp stamp) async {
    // Clear old page data first to avoid stale display. Controllers remain
    // hidden behind the loading state until this exact owner returns.
    _currentPage = null;

    try {
      WebsitePage? page;

      // Only use the captured page id when it belongs to the captured slug.
      if (stamp.pageId != null && stamp.pageSlug == stamp.route) {
        page = await stamp.service.getPageById(stamp.pageId!);
      } else {
        page = await stamp.service.getPageBySlug(stamp.route);
      }

      if (!_ownsLoad(stamp)) {
        _rejectStaleLoad(stamp);
        return;
      }

      final routeKey = stamp.route.split('/').first;
      final pending = stamp.provider.getPendingPageSeo(routeKey);
      if (page != null) {
        _currentPage = page;
        _metaTitleController.text =
            pending?['meta_title'] ?? page.metaTitle ?? '';
        _metaDescriptionController.text =
            pending?['meta_description'] ?? page.metaDescription ?? '';
      } else if (_isSpecialRoute) {
        // Fallback: Try loading from legacy website_settings.
        _metaTitleController.text = pending?['meta_title'] ??
            stamp.service.getSetting('seo_${routeKey}_title', '');
        _metaDescriptionController.text = pending?['meta_description'] ??
            stamp.service.getSetting('seo_${routeKey}_description', '');
      } else {
        _metaTitleController.clear();
        _metaDescriptionController.clear();
      }
      _appliedLoad = stamp;
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading page for SEO: $e');
      if (!_ownsLoad(stamp)) {
        _rejectStaleLoad(stamp);
        return;
      }
      _appliedLoad = stamp;
      setState(() {
        _isSpecialRoute = true;
        _isLoading = false;
      });
    }
  }

  void _stageSeoChanges() {
    final stamp = _appliedLoad;
    if (stamp == null ||
        !stamp.matches(
          liveProvider: widget.editProvider,
          liveService: context.read<WebsiteService>(),
          liveRoute: _resolvedRoute(),
        )) {
      _scheduleReload();
      return;
    }
    final routeKey = stamp.route.split('/').first;
    if (routeKey.isEmpty) return;
    stamp.provider.updatePageSeo(
      routeKey: routeKey,
      metaTitle: _metaTitleController.text,
      metaDescription: _metaDescriptionController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Navigation and page-document changes can retain this State. Compare the
    // immutable owner stamp on every parent rebuild and schedule one fresh
    // load; an in-flight response from the old owner can never populate these
    // controllers.
    final liveRoute = _resolvedRoute();
    final liveService = context.read<WebsiteService>();
    final owner = _activeLoad ?? _appliedLoad;
    if (liveRoute != _currentRoute ||
        (owner != null &&
            !owner.matches(
              liveProvider: widget.editProvider,
              liveService: liveService,
              liveRoute: liveRoute,
            ))) {
      _scheduleReload();
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Color(0xFF00A09D)),
        ),
      );
    }

    final pageName = _currentRoute; // Always use detected route, not DB page

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.article_outlined,
                    color: Color(0xFF00A09D), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SEO de página',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '/$pageName',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Los cambios se guardarán al presionar "Guardar" en la barra superior.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // Meta Title
          _buildField(
            label: 'Meta título',
            controller: _metaTitleController,
            hint: 'Título para Google',
            helperText: 'Lo que aparece en las búsquedas de Google',
          ),
          const SizedBox(height: 16),

          // Meta Description
          _buildField(
            label: 'Meta descripción',
            controller: _metaDescriptionController,
            hint: 'Descripción para Google',
            maxLines: 3,
            helperText: 'Resumen que aparece bajo el título en Google',
          ),
          const SizedBox(height: 24),

          // SEO preview
          _buildSeoPreview(),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (helperText != null) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: helperText,
                child: Icon(Icons.info_outline,
                    size: 14, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: (_) => _stageSeoChanges(),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildSeoPreview() {
    final title = _metaTitleController.text.isNotEmpty
        ? _metaTitleController.text
        : 'Título de la página';
    final description = _metaDescriptionController.text.isNotEmpty
        ? _metaDescriptionController.text
        : 'Descripción de la página...';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa en Google',
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1A0DAB),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.underline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'vinabike.cl › ...',
            style: TextStyle(color: Colors.green.shade700, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
