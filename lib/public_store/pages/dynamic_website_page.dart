import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_font_registry.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/services/tenant_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../widgets/full_page_loading.dart';
import '../widgets/public_store_layout.dart';

/// Dynamic page that renders website_blocks for any page based on slug
///
/// This widget:
/// 1. Loads the page by slug from website_pages
/// 2. Loads blocks associated with that page from website_blocks
/// 3. Renders blocks using WebsiteBlockRenderer (or EditableBlockRenderer if in edit mode)
/// 4. Applies theme settings (colors, fonts, spacing)
///
/// Dec 2025 - Multi-page website support with inline editing
class DynamicWebsitePage extends StatefulWidget {
  final String slug;

  const DynamicWebsitePage({
    super.key,
    required this.slug,
  });

  @override
  State<DynamicWebsitePage> createState() => _DynamicWebsitePageState();
}

class _DynamicWebsitePageState extends State<DynamicWebsitePage>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _blocks = [];

  // Page info for editing
  String? _pageId;
  bool _editModeChecked =
      false; // Track if we've checked edit mode for this navigation
  int _loadGeneration = 0;

  // Theme settings
  Color _primaryColor = const Color(0xFF2E7D32);
  Color _accentColor = const Color(0xFFFF6F00);
  Color _textColor = Colors.black87;
  String _headingFont = 'Oswald';
  String _bodyFont = 'Barlow';
  double _headingSize = 48.0;
  double _bodySize = 16.0;
  double _sectionSpacing = 64.0;
  double _containerPadding = 24.0;

  static const List<String> _responsiveBreakpoints = [
    'desktop',
    'tablet',
    'mobile'
  ];

  // DISABLED: AutomaticKeepAliveClientMixin causes element activation conflicts
  // during edit/preview mode switches. The performance cost of reloading is acceptable.
  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    _seedFromSnapshot(widget.slug);
    _loadPageData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset edit mode check flag on each navigation
    _editModeChecked = false;
  }

  @override
  void didUpdateWidget(DynamicWebsitePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _editModeChecked = false; // Reset on slug change
      _seedFromSnapshot(widget.slug, clearOnMiss: true);
      _loadPageData().then((_) {
        // After loading new page data, update edit provider if in edit mode
        _updateEditProviderIfNeeded();
      });
    }
  }

  String? _publicTenantId() {
    try {
      return context.read<PublicStoreTenantProvider>().tenantId;
    } catch (_) {
      return null;
    }
  }

  bool _seedFromSnapshot(String slug, {bool clearOnMiss = false}) {
    final tenantId = _publicTenantId();
    final snapshot = tenantId == null || tenantId.isEmpty
        ? null
        : context
            .read<WebsiteService>()
            .peekPageWithBlocks(slug, tenantId: tenantId);

    if (snapshot != null && snapshot.page.isPublished) {
      _pageId = snapshot.page.id;
      _blocks = snapshot.blocks
          .where((block) => block['is_visible'] == true)
          .toList();
      _isLoading = false;
      _error = null;
      return true;
    }

    if (clearOnMiss) {
      _pageId = null;
      _blocks = [];
      _isLoading = true;
      _error = null;
    }
    return false;
  }

  /// Update the edit provider with new page's blocks if we're in edit mode
  void _updateEditProviderIfNeeded() {
    if (!mounted) return;
    // Dynamic pages are kept alive across shell branch navigation. Only the
    // active (ticker-enabled) page should sync provider state.
    if (!TickerMode.of(context)) return;

    final editProvider = context.read<WebsiteEditModeProvider>();

    bool providerHasBlocksForThisPage() {
      if (_pageId == null) return false;

      final contextMatches = (editProvider.currentPageId == _pageId) ||
          (editProvider.currentPageSlug == widget.slug);
      if (!contextMatches) return false;

      final providerBlocks = editProvider.blocks;
      if (providerBlocks.isEmpty) return false;

      final hasPageId = providerBlocks.any((b) => b['page_id'] != null);
      if (!hasPageId) return true;

      return providerBlocks
          .every((b) => b['page_id']?.toString() == _pageId.toString());
    }

    // If we're already in edit mode (or preview mode), update the blocks for the new page
    if (editProvider.isEditMode || editProvider.isPreviewMode) {
      // Check if provider isn't actually synced to this page (context + blocks).
      if (!providerHasBlocksForThisPage()) {
        final websiteService = context.read<WebsiteService>();
        final blocks = List<Map<String, dynamic>>.from(_blocks);
        final settings = Map<String, dynamic>.from(websiteService.settings);

        debugPrint(
            '🔄 [DynamicPage] Sync editor context while in edit mode: ${editProvider.currentPageSlug} → ${widget.slug}');
        debugPrint(
            '📄 [DynamicPage] Updating provider with ${_blocks.length} blocks for: ${widget.slug}');

        if (editProvider.isEditMode) {
          editProvider.enterEditMode(
            blocks,
            settings,
            pageId: _pageId,
            pageSlug: widget.slug,
          );
        } else {
          editProvider.enterPreviewMode(
            blocks,
            settings,
            pageId: _pageId,
            pageSlug: widget.slug,
          );
        }

        _editModeChecked =
            true; // Mark as checked so _checkEditModeFromRouter doesn't double-process
      }
    }
  }

  /// Check edit mode using GoRouter state (called from build method)
  void _checkEditModeFromRouter(BuildContext context) {
    // Don't check edit mode until blocks are loaded
    if (_isLoading || _pageId == null) return;

    // URL params should only be used to ENTER editor context.
    // Once already inside the editor shell, ignore URL forcing to prevent
    // preview/edit bouncing on persistent shell routes.
    final editProvider = context.read<WebsiteEditModeProvider>();
    if (editProvider.isInEditorContext) {
      _editModeChecked = true;
      return;
    }

    // Get query parameters from GoRouter
    final goRouterState = GoRouterState.of(context);
    final queryParams = goRouterState.uri.queryParameters;

    final shouldPreview = queryParams['preview'] == 'true';
    // If both are present, preview wins (prevents mode bouncing).
    final shouldEdit = !shouldPreview && queryParams['edit'] == 'true';

    // Only process once per navigation (avoid infinite rebuilds)
    if (_editModeChecked) return;

    if (shouldEdit || shouldPreview) {
      _editModeChecked = true;

      final editProvider = context.read<WebsiteEditModeProvider>();
      final websiteService = context.read<WebsiteService>();

      // Schedule for next frame to avoid calling during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!TickerMode.of(context)) return;

        final blocks = List<Map<String, dynamic>>.from(_blocks);
        final settings = Map<String, dynamic>.from(websiteService.settings);

        debugPrint(
            '📄 [DynamicPage] Setting up edit mode for page: ${widget.slug} (${_blocks.length} blocks)');

        if (shouldEdit) {
          editProvider.enterEditMode(
            blocks,
            settings,
            pageId: _pageId,
            pageSlug: widget.slug,
          );
          debugPrint('✏️ [DynamicPage] Entered EDIT mode for: ${widget.slug}');
        } else {
          editProvider.enterPreviewMode(
            blocks,
            settings,
            pageId: _pageId,
            pageSlug: widget.slug,
          );
          debugPrint(
              '👁️ [DynamicPage] Entered PREVIEW mode for: ${widget.slug}');
        }
      });
    }
  }

  String _currentBreakpoint(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) return 'mobile';
    if (width < 1024) return 'tablet';
    return 'desktop';
  }

  bool? _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'si' ||
          normalized == 'sí') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  Map<String, bool> _normalizeBlockVisibility(dynamic raw) {
    final visibility = {
      for (final breakpoint in _responsiveBreakpoints) breakpoint: true,
    };

    dynamic source = raw;
    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) {
        source = null;
      } else {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) source = decoded;
        } catch (_) {
          source = null;
        }
      }
    }

    if (source is Map) {
      source.forEach((key, value) {
        final keyString = key.toString();
        if (!visibility.containsKey(keyString)) return;
        final parsed = _toBool(value);
        if (parsed != null) visibility[keyString] = parsed;
      });
    }

    return visibility;
  }

  Color? _tryParseColor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    int? intValue;
    var cleaned = trimmed.toLowerCase();

    if (cleaned.startsWith('color(')) {
      final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      intValue = int.tryParse(inside);
    }

    intValue ??= int.tryParse(cleaned);
    if (intValue == null && cleaned.startsWith('0x')) {
      intValue = int.tryParse(cleaned);
    }

    if (intValue == null) {
      cleaned = cleaned.replaceAll('#', '');
      intValue = int.tryParse(cleaned, radix: 16);
      if (intValue != null && cleaned.length <= 6) {
        intValue = 0xFF000000 | intValue;
      }
    }

    return intValue != null ? Color(intValue) : null;
  }

  Future<void> _loadPageData() async {
    final loadGeneration = ++_loadGeneration;
    final requestedSlug = widget.slug;
    debugPrint(
        '🔄 [DynamicPage] _loadPageData() called for slug: "$requestedSlug"');

    if (mounted) {
      setState(() {
        // Keep a matching snapshot visible while the origin is revalidated.
        _isLoading = _pageId == null;
        _error = null;
      });
    }

    try {
      final websiteService = context.read<WebsiteService>();

      // Try to get tenant ID from public store provider (anonymous visitors)
      // OR from TenantService (authenticated ERP users)
      String? tenantId;

      try {
        final tenantProvider = context.read<PublicStoreTenantProvider>();
        tenantId = tenantProvider.tenantId;
        debugPrint(
            '🔄 [DynamicPage] Got tenantId from provider: $tenantId (isLoading: ${tenantProvider.isLoading})');
      } catch (e) {
        debugPrint(
            '🔄 [DynamicPage] PublicStoreTenantProvider not available: $e');
        // PublicStoreTenantProvider not available, try TenantService
      }

      // If no public tenant, try authenticated tenant
      if (tenantId == null) {
        final tenantService = TenantService();
        tenantId = await tenantService.getTenantId();
      }

      // Wait for tenant detection if still not ready
      if (tenantId == null) {
        debugPrint('⏳ [DynamicWebsitePage] Waiting for tenant detection...');
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted &&
            loadGeneration == _loadGeneration &&
            requestedSlug == widget.slug) {
          _loadPageData();
        }
        return;
      }

      if (loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug ||
          !mounted) {
        return;
      }

      // Tenant detection can finish after initState. Seed at that point too so
      // a revisit still paints before the origin request completes.
      if (_pageId == null) {
        setState(() {
          _seedFromSnapshot(requestedSlug);
        });
      }

      debugPrint(
          '🏪 [DynamicWebsitePage] Loading page "$requestedSlug" for tenant: $tenantId');

      // Start the joined page+blocks request immediately. Theme settings may
      // load alongside it; they must not create a page -> blocks waterfall.
      final pageFuture = websiteService.loadPageWithBlocks(
        requestedSlug,
        tenantId: tenantId,
      );
      final settingsFuture = websiteService.settings.isEmpty
          ? websiteService.loadSettingsForTenant(tenantId)
          : Future<void>.value();
      await settingsFuture;
      final snapshot = await pageFuture;

      if (loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug ||
          !mounted) {
        return;
      }

      if (snapshot == null || !snapshot.page.isPublished) {
        throw Exception('Page not found: $requestedSlug');
      }

      WebsiteEditModeProvider? editProvider;
      try {
        editProvider = context.read<WebsiteEditModeProvider>();
      } catch (_) {
        editProvider = null;
      }

      debugPrint(
          '📄 [DynamicWebsitePage] Found page: "${snapshot.page.title}" (id: ${snapshot.page.id}, slug: ${snapshot.page.slug})');

      setState(() {
        _loadThemeFromSettings(
          websiteService,
          editProvider: editProvider,
        );
        _pageId = snapshot.page.id;
        _blocks = snapshot.blocks
            .where((block) => block['is_visible'] == true)
            .toList();
        _isLoading = false;
        _error = null;
      });

      // If we arrived here while already inside the persistent editor shell
      // (edit/preview), keep its canonical page context synchronized.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!TickerMode.of(context)) return;
        _updateEditProviderIfNeeded();
      });
    } catch (e) {
      debugPrint('❌ [DynamicWebsitePage] Error: $e');
      if (mounted &&
          loadGeneration == _loadGeneration &&
          requestedSlug == widget.slug) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _loadThemeFromSettings(
    WebsiteService service, {
    WebsiteEditModeProvider? editProvider,
  }) {
    String eff(String key, String fallback) {
      if (editProvider != null && editProvider.isInEditorContext) {
        return editProvider.getEffectiveThemeSetting(key, fallback);
      }
      return fallback;
    }

    final primary =
        eff('theme_primary_color', service.getSetting('theme_primary_color'));
    final accent =
        eff('theme_accent_color', service.getSetting('theme_accent_color'));
    final text =
        eff('theme_text_color', service.getSetting('theme_text_color'));
    final headingFont =
        eff('theme_heading_font', service.getSetting('theme_heading_font'));
    final bodyFont =
        eff('theme_body_font', service.getSetting('theme_body_font'));
    final headingSize =
        eff('theme_heading_size', service.getSetting('theme_heading_size'));
    final bodySize =
        eff('theme_body_size', service.getSetting('theme_body_size'));
    final sectionSpacing = eff(
        'theme_section_spacing', service.getSetting('theme_section_spacing'));
    final containerPadding = eff('theme_container_padding',
        service.getSetting('theme_container_padding'));

    final parsedPrimary = _tryParseColor(primary);
    final parsedAccent = _tryParseColor(accent);
    final parsedText = _tryParseColor(text);

    if (parsedPrimary != null) _primaryColor = parsedPrimary;
    if (parsedAccent != null) _accentColor = parsedAccent;
    if (parsedText != null) _textColor = parsedText;
    if (headingFont.isNotEmpty) {
      _headingFont = WebsiteFontRegistry.resolveHeadingFont(headingFont);
    }
    if (bodyFont.isNotEmpty) {
      _bodyFont = WebsiteFontRegistry.resolveBodyFont(bodyFont);
    }

    final parsedHeadingSize = double.tryParse(headingSize);
    final parsedBodySize = double.tryParse(bodySize);
    final parsedSectionSpacing = double.tryParse(sectionSpacing);
    final parsedContainerPadding = double.tryParse(containerPadding);

    if (parsedHeadingSize != null) {
      _headingSize = parsedHeadingSize.clamp(24.0, 72.0);
    }
    if (parsedBodySize != null) _bodySize = parsedBodySize.clamp(12.0, 24.0);
    if (parsedSectionSpacing != null) {
      _sectionSpacing = parsedSectionSpacing.clamp(32.0, 128.0);
    }
    if (parsedContainerPadding != null) {
      _containerPadding = parsedContainerPadding.clamp(16.0, 64.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Check edit mode from URL parameters (called every build, but only acts once per navigation)
    _checkEditModeFromRouter(context);

    // Watch edit mode provider for changes
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;
    final isInEditorContext = editProvider.isInEditorContext;

    // Watch website service so theme changes can apply without full reload
    final websiteService = context.watch<WebsiteService>();
    _loadThemeFromSettings(websiteService, editProvider: editProvider);

    // Get tenant ID for product loading (try public store provider or use cached)
    String? tenantId;
    try {
      final tenantProvider = context.watch<PublicStoreTenantProvider>();
      tenantId = tenantProvider.tenantId;
    } catch (_) {
      // PublicStoreTenantProvider not available (ERP host)
      // tenantId will be fetched in _loadPageData
    }

    // In editor context (preview or edit), render the provider blocks for THIS page.
    // This ensures switching to preview after saving shows the updated content.
    final matchesPage = (editProvider.currentPageId != null &&
            editProvider.currentPageId == _pageId) ||
        (editProvider.currentPageSlug != null &&
            editProvider.currentPageSlug == widget.slug);

    final blocksToRender =
        (isInEditorContext && matchesPage) ? editProvider.blocks : _blocks;

    if (_isLoading && _pageId == null) {
      return const FullPageLoading();
    }

    if (_error != null) {
      return _buildErrorView();
    }

    // Return just the blocks - PublicStoreLayout handles Scaffold and scrolling
    return Column(
      children: _buildBlockWidgets(blocksToRender, isEditMode, tenantId),
    );
  }

  /// Build block widgets (non-sliver version for Column layout)
  List<Widget> _buildBlockWidgets(
      List<Map<String, dynamic>> blocks, bool isEditMode, String? tenantId) {
    final breakpoint = _currentBreakpoint(context);
    final visibleBlocks = <Map<String, dynamic>>[];

    for (final block in blocks) {
      final blockData = block['block_data'] as Map<String, dynamic>? ?? {};
      final visibility = _normalizeBlockVisibility(blockData['visibility']);

      // In edit mode, show all blocks; in view mode, respect visibility settings
      if (isEditMode || visibility[breakpoint] == true) {
        visibleBlocks.add(block);
      }
    }

    if (visibleBlocks.isEmpty) {
      return [_buildEmptyState(isEditMode)];
    }

    return visibleBlocks.map((block) {
      final blockId = block['id']?.toString() ?? '';
      final blockType = block['block_type']?.toString() ?? 'hero';
      final blockData = block['block_data'] as Map<String, dynamic>? ?? {};
      final isVisible = block['is_visible'] == true;

      // Use EditableBlockRenderer in edit mode, WebsiteBlockRenderer in view mode
      final blockWidget = isEditMode
          ? DeferredEditableBlockRenderer.build(
              context: context,
              blockId: blockId,
              blockType: blockType,
              data: blockData,
              primaryColor: _primaryColor,
              accentColor: _accentColor,
              headingFont: _headingFont,
              bodyFont: _bodyFont,
              headingSize: _headingSize,
              bodySize: _bodySize,
              onNavigate: (route) =>
                  PublicStoreLayout.navigateToHref(context, route),
              isVisible: isVisible,
              tenantId: tenantId,
            )
          : WebsiteBlockRenderer.build(
              context: context,
              blockType: blockType,
              data: blockData,
              primaryColor: _primaryColor,
              accentColor: _accentColor,
              headingFont: _headingFont,
              bodyFont: _bodyFont,
              headingSize: _headingSize,
              bodySize: _bodySize,
              onNavigate: (route) =>
                  PublicStoreLayout.navigateToHref(context, route),
              tenantId: tenantId,
            );

      return Padding(
        padding: EdgeInsets.only(bottom: _sectionSpacing),
        child: blockWidget,
      );
    }).toList();
  }

  Widget _buildEmptyState(bool isEditMode) {
    return Container(
      padding: EdgeInsets.all(_containerPadding),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.web_stories_outlined,
              size: 64,
              color: _textColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isEditMode
                  ? 'Esta página no tiene bloques'
                  : 'Esta página está en construcción',
              style: TextStyle(
                fontSize: _headingSize * 0.5,
                fontFamily: _headingFont,
                color: _textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEditMode
                  ? 'Usa el panel de la derecha para agregar bloques'
                  : 'Vuelve pronto para ver el contenido',
              style: TextStyle(
                fontSize: _bodySize,
                fontFamily: _bodyFont,
                color: _textColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Página no encontrada',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Ha ocurrido un error al cargar la página',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: _textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/tienda'),
              icon: const Icon(Icons.home),
              label: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}
