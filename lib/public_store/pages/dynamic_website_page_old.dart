import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_page_models.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/editable_block_renderer.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/widgets/branded_loading.dart';
import '../../shared/services/tenant_service.dart';
import '../providers/public_store_tenant_provider.dart';

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

class _DynamicWebsitePageState extends State<DynamicWebsitePage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _blocks = [];

  // Page info for editing
  String? _pageId;
  bool _editModeChecked =
      false; // Track if we've checked edit mode for this navigation

  // Theme settings
  Color _primaryColor = const Color(0xFF2E7D32);
  Color _accentColor = const Color(0xFFFF6F00);
  Color _textColor = Colors.black87;
  String _headingFont = 'Roboto';
  String _bodyFont = 'Roboto';
  double _headingSize = 48.0;
  double _bodySize = 16.0;
  double _sectionSpacing = 64.0;
  double _containerPadding = 24.0;

  static const List<String> _responsiveBreakpoints = [
    'desktop',
    'tablet',
    'mobile'
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 [DynamicWebsitePage] Init with slug: "${widget.slug}"');
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
      _loadPageData().then((_) {
        // After loading new page data, update edit provider if in edit mode
        _updateEditProviderIfNeeded();
      });
    }
  }

  /// Update the edit provider with new page's blocks if we're in edit mode
  void _updateEditProviderIfNeeded() {
    if (!mounted) return;

    final editProvider = context.read<WebsiteEditModeProvider>();

    // If we're already in edit mode (or preview mode), update the blocks for the new page
    if (editProvider.isEditMode || editProvider.isPreviewMode) {
      // Check if we're on a different page than what the provider has
      if (editProvider.currentPageSlug != widget.slug) {
        final websiteService = context.read<WebsiteService>();
        final blocks = List<Map<String, dynamic>>.from(_blocks);
        final settings = Map<String, dynamic>.from(websiteService.settings);

        debugPrint(
            '🔄 [DynamicPage] Page changed while in edit mode: ${editProvider.currentPageSlug} → ${widget.slug}');
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

    // Get query parameters from GoRouter
    final goRouterState = GoRouterState.of(context);
    final queryParams = goRouterState.uri.queryParameters;

    final shouldEdit = queryParams['edit'] == 'true';
    final shouldPreview = queryParams['preview'] == 'true';

    // Only process once per navigation (avoid infinite rebuilds)
    if (_editModeChecked) return;

    if (shouldEdit || shouldPreview) {
      _editModeChecked = true;

      final editProvider = context.read<WebsiteEditModeProvider>();
      final websiteService = context.read<WebsiteService>();

      // Schedule for next frame to avoid calling during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final websiteService = context.read<WebsiteService>();

      // Try to get tenant ID from public store provider (anonymous visitors)
      // OR from TenantService (authenticated ERP users)
      String? tenantId;

      try {
        final tenantProvider = context.read<PublicStoreTenantProvider>();
        tenantId = tenantProvider.tenantId;
      } catch (_) {
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
        // Re-try after a short delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _loadPageData();
        }
        return;
      }

      debugPrint(
          '🏪 [DynamicWebsitePage] Loading page "${widget.slug}" for tenant: $tenantId');

      // Load settings first (for theme)
      if (websiteService.settings.isEmpty) {
        await websiteService.loadSettingsForTenant(tenantId);
      }
      _loadThemeFromSettings(websiteService);

      // Load pages using public method (no auth required)
      await websiteService.loadPagesForTenant(tenantId);
      final pages = websiteService.pages;

      debugPrint('📄 [DynamicWebsitePage] Found ${pages.length} pages total');

      // Find the page by slug (or home page for empty slug)
      WebsitePage? page;
      if (widget.slug.isEmpty) {
        // Look for home page
        page = pages.firstWhere(
          (p) => p.isHome && p.isPublished,
          orElse: () => pages.firstWhere(
            (p) => p.isPublished,
            orElse: () => throw Exception('No published pages found'),
          ),
        );
      } else {
        // Find by slug
        page = pages.firstWhere(
          (p) => p.slug == widget.slug && p.isPublished,
          orElse: () => throw Exception('Page not found: ${widget.slug}'),
        );
      }

      // Store page ID for editing
      _pageId = page.id;

      debugPrint(
          '📄 [DynamicWebsitePage] Found page: "${page.title}" (id: ${page.id}, slug: ${page.slug})');

      // Load blocks for this page (pass tenantId explicitly for public store)
      final blocks = await websiteService.loadBlocksForPage(
        page.id,
        tenantId: tenantId,
      );

      debugPrint(
          '📦 [DynamicWebsitePage] Loaded ${blocks.length} raw blocks from database');
      for (final block in blocks) {
        debugPrint(
            '   - Block: ${block['block_type']} (id: ${block['id']}, page_id: ${block['page_id']})');
      }

      // Filter visible blocks only (but keep all for editing)
      _blocks = blocks.where((block) {
        return block['is_visible'] == true;
      }).toList();

      debugPrint(
          '✅ [DynamicWebsitePage] Showing ${_blocks.length} visible blocks');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ [DynamicWebsitePage] Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _loadThemeFromSettings(WebsiteService service) {
    final primary = service.getSetting('theme_primary_color');
    final accent = service.getSetting('theme_accent_color');
    final text = service.getSetting('theme_text_color');
    final headingFont = service.getSetting('theme_heading_font');
    final bodyFont = service.getSetting('theme_body_font');
    final headingSize = service.getSetting('theme_heading_size');
    final bodySize = service.getSetting('theme_body_size');
    final sectionSpacing = service.getSetting('theme_section_spacing');
    final containerPadding = service.getSetting('theme_container_padding');

    final parsedPrimary = _tryParseColor(primary);
    final parsedAccent = _tryParseColor(accent);
    final parsedText = _tryParseColor(text);

    if (parsedPrimary != null) _primaryColor = parsedPrimary;
    if (parsedAccent != null) _accentColor = parsedAccent;
    if (parsedText != null) _textColor = parsedText;
    if (headingFont.isNotEmpty) _headingFont = headingFont;
    if (bodyFont.isNotEmpty) _bodyFont = bodyFont;

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
    // Check edit mode from URL parameters (called every build, but only acts once per navigation)
    _checkEditModeFromRouter(context);

    // Watch edit mode provider for changes
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;

    // Get tenant ID for product loading (try public store provider or use cached)
    String? tenantId;
    try {
      final tenantProvider = context.watch<PublicStoreTenantProvider>();
      tenantId = tenantProvider.tenantId;
    } catch (_) {
      // PublicStoreTenantProvider not available (ERP host)
      // tenantId will be fetched in _loadPageData
    }

    // If in edit mode, use blocks from provider (which tracks changes)
    final blocksToRender = isEditMode ? editProvider.blocks : _blocks;

    if (_isLoading) {
      return const Center(
        child: BrandedLoading(message: 'Cargando...'),
      );
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
          ? EditableBlockRenderer.build(
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
              onNavigate: (route) => context.go(route),
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
              onNavigate: (route) => context.go(route),
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
