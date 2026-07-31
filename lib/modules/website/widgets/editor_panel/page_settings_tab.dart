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

class _PageSettingsTabState extends State<_PageSettingsTab> {
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  bool _isLoading = true;
  bool _isDetecting = false; // Prevent concurrent detection
  // ignore: unused_field
  WebsitePage? _currentPage;
  String _currentRoute = '';
  bool _isSpecialRoute = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure context is available for router
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectCurrentPage());
  }

  @override
  void dispose() {
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _detectCurrentPage() async {
    if (!mounted || _isDetecting) return;
    _isDetecting = true;

    try {
      // Prefer detecting route from actual URL, fallback to provider
      var newRoute = _getSlugFromRoute() ??
          widget.editProvider.currentPageSlug ??
          'inicio';
      if (newRoute.isEmpty) newRoute = 'inicio';

      debugPrint('📄 [PageSettingsTab] Detecting page: $newRoute');

      // Avoid reloading if route hasn't changed
      if (newRoute == _currentRoute && !_isLoading) {
        _isDetecting = false;
        return;
      }

      setState(() {
        _currentRoute = newRoute;
        _isLoading = true;
      });

      // Check if this is a special route (not a CMS page)
      final specialRoutes = ['productos', 'contacto', 'carrito', 'checkout'];
      _isSpecialRoute = specialRoutes.any((r) => _currentRoute.startsWith(r));

      // Special route check logic preserved, but early return removed.
      // We now attempt to load from DB first for ALL routes.

      await _loadPageData();
    } finally {
      _isDetecting = false;
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

  Future<void> _loadPageData() async {
    final pageSlug = _currentRoute; // Use the route we detected, not provider

    // Clear old page data first to avoid stale display
    _currentPage = null;

    // Home page check removed to use standard website_pages table logic

    try {
      final service = context.read<WebsiteService>();
      WebsitePage? page;

      // Only use provider's pageId if it matches our current route
      final providerSlug = widget.editProvider.currentPageSlug ?? '';
      final providerPageId = widget.editProvider.currentPageId;

      if (providerPageId != null && providerSlug == pageSlug) {
        page = await service.getPageById(providerPageId);
      } else {
        // Lookup by slug (our detected route)
        page = await service.getPageBySlug(pageSlug);
      }

      if (!mounted) return;

      if (page != null) {
        _currentPage = page;
        // Don't override _currentRoute here - keep what we detected
        final routeKey = _currentRoute.split('/').first;
        final pending = widget.editProvider.getPendingPageSeo(routeKey);
        _metaTitleController.text =
            pending?['meta_title'] ?? page.metaTitle ?? '';
        _metaDescriptionController.text =
            pending?['meta_description'] ?? page.metaDescription ?? '';
        setState(() => _isLoading = false);
      } else {
        // Page not found in DB - use _currentRoute for display
        if (_isSpecialRoute) {
          // Fallback: Try loading from legacy website_settings
          final service = context.read<WebsiteService>();
          final routeKey = _currentRoute.split('/').first;
          final pending = widget.editProvider.getPendingPageSeo(routeKey);
          _metaTitleController.text = pending?['meta_title'] ??
              service.getSetting('seo_${routeKey}_title', '');
          _metaDescriptionController.text = pending?['meta_description'] ??
              service.getSetting('seo_${routeKey}_description', '');
        }
        setState(() {
          // Keep _isSpecialRoute as determined earlier
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading page for SEO: $e');
      if (mounted) {
        setState(() {
          _isSpecialRoute = true;
          _isLoading = false;
        });
      }
    }
  }

  void _stageSeoChanges() {
    final routeKey = _currentRoute.split('/').first;
    if (routeKey.isEmpty) return;
    widget.editProvider.updatePageSeo(
      routeKey: routeKey,
      metaTitle: _metaTitleController.text,
      metaDescription: _metaDescriptionController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if route changed on every build (navigation might not trigger didUpdateWidget)
    final routeSlug = _getSlugFromRoute();
    if (routeSlug != null &&
        routeSlug != _currentRoute &&
        !_isLoading &&
        !_isDetecting) {
      // Schedule re-detection after this build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDetecting) _detectCurrentPage();
      });
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
