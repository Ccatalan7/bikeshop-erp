import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/inline_edit_toolbar.dart'
    show AddBlockDialog;
import '../../modules/website/widgets/block_spacer_handle.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/models/product.dart';
import '../../shared/services/tenant_service.dart';
import '../theme/public_store_theme.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../services/public_store_scroll_state.dart';
import '../widgets/public_store_layout.dart';

class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key});

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage>
    with AutomaticKeepAliveClientMixin {
  List<Product> _featuredProducts = [];
  bool _editModeChecked =
      false; // Track if we've checked edit mode for this navigation
  bool _syncedEditorContextForHome = false;
  bool _featuredProductsLoaded = false; // Load featured products once
  String? _resolvedTenantId;
  bool _isResolvingTenantId = false;

  PublicStoreScrollState? _scrollState;
  int _lastHomeRefreshSignal = 0;

  // Progressive rendering to reduce first-frame jank on mobile.
  // We render only a couple of blocks initially, then expand shortly after.
  static const int _initialBlockRenderLimitDefault = 2;
  static const int _initialBlockRenderLimitAndroid = 1;

  int _progressiveBlockLimit = _initialBlockRenderLimitDefault;
  int? _progressiveScheduledTarget;
  int? _progressiveScheduledIntermediateTarget;
  String? _lastProgressiveTenantId;

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
    _progressiveBlockLimit = _initialBlockRenderLimit;
    // Debug: initState
    // Load featured products once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Debug: postFrameCallback - loading data
      _ensureTenantId();
      _loadFeaturedProductsOnce();
    });
  }

  void _onHomeRefreshSignal() {
    final scrollState = _scrollState;
    if (!mounted || scrollState == null) return;

    final currentValue = scrollState.homeRefreshSignal.value;
    if (currentValue == _lastHomeRefreshSignal) return;
    _lastHomeRefreshSignal = currentValue;

    // Fire-and-forget: this is a user action (logo/home) and should feel instant.
    unawaited(_refreshHomeFromLogoOrHomeClick());
  }

  Future<void> _refreshHomeFromLogoOrHomeClick() async {
    if (!mounted) return;

    final editProvider = context.read<WebsiteEditModeProvider>();
    // Never clobber editor state while actively editing.
    if (editProvider.isEditMode) return;

    final tenantId = await _effectiveTenantId();
    if (!mounted) return;
    if (tenantId == null || tenantId.isEmpty) return;

    // 1) Refresh Website blocks/settings (force refresh bypasses TTL skips).
    try {
      final websiteService = context.read<WebsiteService>();
      await websiteService.loadPublicStoreDataUnified(
        tenantId,
        forceRefresh: true,
      );
    } catch (_) {
      // Ignore; home should still render with existing cached data.
    }

    // 2) Refresh featured products.
    if (!mounted) return;
    setState(() {
      _featuredProductsLoaded = false;
      _featuredProducts = [];
    });
    await _loadFeaturedProductsOnce();
  }

  int get _initialBlockRenderLimit {
    if (kIsWeb) return _initialBlockRenderLimitDefault;
    return defaultTargetPlatform == TargetPlatform.android
        ? _initialBlockRenderLimitAndroid
        : _initialBlockRenderLimitDefault;
  }

  int get _intermediateBlockRenderLimit {
    // On Android we build 1 block for first paint, then quickly expand to 2.
    final initial = _initialBlockRenderLimit;
    if (kIsWeb) return initial;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return initial < 2 ? 2 : initial;
    }
    return initial;
  }

  Future<void> _ensureTenantId() async {
    if (!mounted) return;
    if (_resolvedTenantId != null && _resolvedTenantId!.isNotEmpty) return;
    if (_isResolvingTenantId) return;
    _isResolvingTenantId = true;
    try {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final providerId = tenantProvider.tenantId;
      if (providerId != null && providerId.isNotEmpty) {
        _resolvedTenantId = providerId;
        return;
      }
    } catch (_) {
      // Provider may not exist in ERP host; ignore.
    }

    try {
      final id = await TenantService().getTenantId();
      if (!mounted) return;
      if (id != null && id.isNotEmpty) {
        setState(() => _resolvedTenantId = id);
      }
    } finally {
      _isResolvingTenantId = false;
    }
  }

  Future<String?> _effectiveTenantId() async {
    if (!mounted) return _resolvedTenantId;

    try {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final providerId = tenantProvider.tenantId;
      if (providerId != null && providerId.isNotEmpty) {
        if (_resolvedTenantId != providerId && mounted) {
          setState(() => _resolvedTenantId = providerId);
        }
        return providerId;
      }
    } catch (_) {
      // PublicStoreTenantProvider not available (ERP host)
    }

    if (_resolvedTenantId != null && _resolvedTenantId!.isNotEmpty) {
      return _resolvedTenantId;
    }

    final id = await TenantService().getTenantId();
    if (!mounted) return id ?? _resolvedTenantId;
    if (id != null && id.isNotEmpty && _resolvedTenantId != id) {
      setState(() => _resolvedTenantId = id);
    }
    return id ?? _resolvedTenantId;
  }

  Future<void> _loadFeaturedProductsOnce() async {
    if (!mounted) return;
    if (_featuredProductsLoaded) return;

    final tenantId = await _effectiveTenantId();
    if (!mounted) return;
    if (tenantId == null || tenantId.isEmpty) return;

    try {
      final inventoryService = context.read<PublicInventoryService>();
      final products = await inventoryService.getFeaturedProductsForTenant(
        tenantId: tenantId,
        limit: 8,
      );
      if (!mounted) return;
      setState(() {
        _featuredProducts = products;
        _featuredProductsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _featuredProductsLoaded = true);
    }
  }

  /// Check edit mode using GoRouter state (called from build method)
  void _checkEditModeFromRouter(BuildContext context) {
    // Get query parameters from GoRouter
    final goRouterState = GoRouterState.of(context);
    final queryParams = goRouterState.uri.queryParameters;

    final shouldPreview = queryParams['preview'] == 'true';
    // If both are present, preview wins (prevents mode bouncing).
    final shouldEdit = !shouldPreview && queryParams['edit'] == 'true';

    // Only process once per navigation (avoid infinite rebuilds)
    if (_editModeChecked) return;

    if (!shouldEdit && !shouldPreview) {
      _editModeChecked = true;
      return;
    }

    final editProvider = context.read<WebsiteEditModeProvider>();
    final websiteService = context.read<WebsiteService>();

    // Wait until the service has data; otherwise we risk entering edit mode
    // with empty blocks/settings on the very first frame.
    if (websiteService.blocks.isEmpty && !websiteService.hasLoadedForTenant) {
      return;
    }

    _editModeChecked = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // URL params should only be used to ENTER editor context.
      // Once already inside the editor shell, ignore URL forcing to prevent
      // preview/edit bouncing on persistent shell routes.
      if (editProvider.isInEditorContext) return;

      final blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
      final settings = Map<String, dynamic>.from(websiteService.settings);

      if (shouldEdit) {
        editProvider.enterEditMode(blocks, settings);
      } else {
        editProvider.enterPreviewMode(blocks, settings);
      }
    });
  }

  /// When navigating back to the HOME route while already inside the editor shell,
  /// we must also reset the editor page context and swap the provider blocks to
  /// the HOME blocks.
  ///
  /// Otherwise the home page will keep rendering the previous page's blocks
  /// because `PublicHomePage` prefers `editProvider.blocks` in editor context.
  void _syncEditorContextToHomeIfNeeded({
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
  }) {
    if (_syncedEditorContextForHome) return;
    // Home is kept alive in the shell. Never let an offstage home instance
    // overwrite the editor provider while the user is viewing another page.
    if (!TickerMode.of(context)) return;
    if (!editProvider.isInEditorContext) return;

    final currentSlug = (editProvider.currentPageSlug ?? '').trim();
    if (currentSlug.isEmpty) {
      // Already home.
      _syncedEditorContextForHome = true;
      return;
    }

    // Wait until we have blocks/settings available.
    if (websiteService.blocks.isEmpty && !websiteService.hasLoadedForTenant) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_syncedEditorContextForHome) return;
      if (!TickerMode.of(context)) return;

      // Re-check in case something changed between scheduling and execution.
      final slugNow = (editProvider.currentPageSlug ?? '').trim();
      if (slugNow.isEmpty) {
        _syncedEditorContextForHome = true;
        return;
      }

      final blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
      final settings = Map<String, dynamic>.from(websiteService.settings);

      debugPrint(
          '🔄 [PublicHomePage] Sync editor context: ${editProvider.currentPageSlug} → home (${blocks.length} blocks)');

      if (editProvider.isEditMode) {
        editProvider.enterEditMode(blocks, settings, pageId: null, pageSlug: null);
      } else {
        editProvider.enterPreviewMode(blocks, settings, pageId: null, pageSlug: null);
      }

      _syncedEditorContextForHome = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset edit mode check on navigation
    _editModeChecked = false;
    _syncedEditorContextForHome = false;

    final nextScrollState = context.read<PublicStoreScrollState>();
    if (_scrollState != nextScrollState) {
      _scrollState?.homeRefreshSignal.removeListener(_onHomeRefreshSignal);
      _scrollState = nextScrollState;
      _lastHomeRefreshSignal = nextScrollState.homeRefreshSignal.value;
      nextScrollState.homeRefreshSignal.addListener(_onHomeRefreshSignal);
    }
  }

  void _scheduleProgressiveExpansionIfNeeded({
    required String? tenantId,
    required bool isEditMode,
    required int blockCount,
  }) {
    if (!mounted) return;

    final initialLimit = _initialBlockRenderLimit;
    final intermediateLimit = _intermediateBlockRenderLimit;

    // Editing needs full fidelity immediately.
    if (isEditMode) {
      _progressiveScheduledTarget = null;
      _progressiveScheduledIntermediateTarget = null;
      _progressiveBlockLimit = blockCount;
      return;
    }

    // Reset when tenant changes.
    if (_lastProgressiveTenantId != tenantId) {
      _lastProgressiveTenantId = tenantId;
      _progressiveScheduledTarget = null;
      _progressiveScheduledIntermediateTarget = null;
      _progressiveBlockLimit = initialLimit;
    }

    if (blockCount <= initialLimit) {
      _progressiveScheduledTarget = null;
      _progressiveScheduledIntermediateTarget = null;
      _progressiveBlockLimit = blockCount;
      return;
    }

    if (_progressiveBlockLimit >= blockCount) return;

    // Phase 1: expand to a small intermediate count on the next frame.
    final desiredIntermediate =
        intermediateLimit < blockCount ? intermediateLimit : blockCount;

    if (_progressiveBlockLimit < desiredIntermediate &&
        _progressiveScheduledIntermediateTarget != desiredIntermediate) {
      _progressiveScheduledIntermediateTarget = desiredIntermediate;
      Future.delayed(const Duration(milliseconds: 16), () {
        if (!mounted) return;
        if (_progressiveScheduledIntermediateTarget != desiredIntermediate) {
          return;
        }
        if (_progressiveBlockLimit >= desiredIntermediate) return;
        setState(() {
          _progressiveBlockLimit = desiredIntermediate;
        });
      });
    }

    // Phase 2: expand to full content shortly after first paint.
    if (_progressiveScheduledTarget == blockCount) return;
    _progressiveScheduledTarget = blockCount;

    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      // Only expand if we're still targeting the same block count.
      if (_progressiveScheduledTarget != blockCount) return;
      if (_progressiveBlockLimit >= blockCount) return;
      setState(() {
        _progressiveBlockLimit = blockCount;
      });
    });
  }

  // Note: _updateEditProviderIfNeeded was removed - not needed with simple routing

  String _currentBreakpoint(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) {
      return 'mobile';
    }
    if (width < 1024) {
      return 'tablet';
    }
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
          if (decoded is Map) {
            source = decoded;
          }
        } catch (_) {
          source = null;
        }
      }
    }

    if (source is Map) {
      source.forEach((key, value) {
        final keyString = key.toString();
        if (!visibility.containsKey(keyString)) {
          return;
        }
        final parsed = _toBool(value);
        if (parsed != null) {
          visibility[keyString] = parsed;
        }
      });
    }

    return visibility;
  }

  @override
  void dispose() {
    // Debug: dispose
    _scrollState?.homeRefreshSignal.removeListener(_onHomeRefreshSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Debug: build called

    // Check for edit/preview mode from URL query parameters (using GoRouter)
    // We check this here to prevent a 1-frame flash where hidden blocks are filtered out
    // before the edit provider fully initializes.
    final qp = GoRouterState.of(context).uri.queryParameters;
    final forceEditMode = qp['edit'] == 'true';

    _checkEditModeFromRouter(context);
    // Note: _updateEditProviderIfNeeded() removed - not needed with simple routing

    // Read data from providers - WATCH WebsiteService to rebuild when blocks load
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final websiteService = context
        .watch<WebsiteService>(); // Changed to watch() for progressive loading
    final editProvider = context.watch<WebsiteEditModeProvider>();

    _syncEditorContextToHomeIfNeeded(
      editProvider: editProvider,
      websiteService: websiteService,
    );

    if (tenantProvider.tenantId == null &&
        (_resolvedTenantId == null || _resolvedTenantId!.isEmpty)) {
      // ERP/editor host: resolve tenant via TenantService so product blocks can load.
      _ensureTenantId();
    }

    String eff(String key, String fallback) {
      if (editProvider.isInEditorContext) {
        return editProvider.getEffectiveThemeSetting(key, fallback);
      }
      return fallback;
    }

    final primarySetting = websiteService.getSetting('theme_primary_color', '');
    final accentSetting = websiteService.getSetting('theme_accent_color', '');
    final headingFontSetting =
        websiteService.getSetting('theme_heading_font', '');
    final bodyFontSetting = websiteService.getSetting('theme_body_font', '');
    final headingSizeSetting =
        websiteService.getSetting('theme_heading_size', '');
    final bodySizeSetting = websiteService.getSetting('theme_body_size', '');
    final textColorSetting = websiteService.getSetting('theme_text_color', '');
    final sectionSpacingSetting =
        websiteService.getSetting('theme_section_spacing', '');
    final containerPaddingSetting =
        websiteService.getSetting('theme_container_padding', '');

    final primaryColor = _resolveColor(
      eff('theme_primary_color', primarySetting),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      eff('theme_accent_color', accentSetting),
      PublicStoreTheme.accentGreen,
    );
    final headingFont = eff('theme_heading_font', headingFontSetting);
    final bodyFont = eff('theme_body_font', bodyFontSetting);
    final headingSize = _resolveDouble(
      eff('theme_heading_size', headingSizeSetting),
      48.0,
      min: 24.0,
      max: 72.0,
    );
    final bodySize = _resolveDouble(
      eff('theme_body_size', bodySizeSetting),
      16.0,
      min: 12.0,
      max: 24.0,
    );
    final textColor = _resolveColor(
      eff('theme_text_color', textColorSetting),
      PublicStoreTheme.textPrimary,
    );
    final sectionSpacing = _resolveDouble(
      eff('theme_section_spacing', sectionSpacingSetting),
      64.0,
      min: 32.0,
      max: 128.0,
    );
    final containerPadding = _resolveDouble(
      eff('theme_container_padding', containerPaddingSetting),
      24.0,
      min: 16.0,
      max: 64.0,
    );

    // Debug: verify live theme preview values are applied
    if (editProvider.isInEditorContext &&
        (editProvider.pendingThemeSettings.containsKey('theme_heading_font') ||
            editProvider.pendingThemeSettings.containsKey('theme_body_font') ||
            editProvider.pendingThemeSettings
                .containsKey('theme_heading_size') ||
            editProvider.pendingThemeSettings.containsKey('theme_body_size'))) {
      debugPrint(
          '🧪 [ThemePreview] effective headingFont="$headingFont" bodyFont="$bodyFont" headingSize=$headingSize bodySize=$bodySize');
      debugPrint(
          '🧪 [ThemePreview] pendingThemeSettings=${editProvider.pendingThemeSettings}');
    }

    // Use blocks from WebsiteService (loaded by main.dart progressively)
    final blocksToRender = websiteService.blocks;
    final isDataLoading = !websiteService.hasLoadedForTenant;

    // Show a minimal loading state while blocks/settings are still loading.
    if (isDataLoading && blocksToRender.isEmpty) {
      final viewportHeight = MediaQuery.of(context).size.height;
      final minHeight = viewportHeight - 200;

      return SizedBox(
        height: minHeight > 400 ? minHeight : 400,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show empty state ONLY if:
    // 1. Tenant detection finished AND failed
    // 2. No blocks loaded (true public store failure)
    // 3. NOT when blocks ARE loaded (ERP preview mode - blocks loaded via authenticated user)
    if (tenantProvider.hasError &&
        tenantProvider.tenantId == null &&
        blocksToRender.isEmpty &&
        !websiteService.hasLoadedForTenant) {
      final viewportHeight = MediaQuery.of(context).size.height;
      final minHeight = viewportHeight - 200;

      return SizedBox(
        height: minHeight > 400 ? minHeight : 400,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Tienda no encontrada',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Verifica la URL e intenta nuevamente',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    final currentBreakpoint = _currentBreakpoint(context);

    // Use Selector to only rebuild when edit mode state or block IDs change
    // This prevents full page rebuilds when only block DATA changes (which is handled by each block)
    return Selector<
        WebsiteEditModeProvider,
        ({
          bool isEditMode,
          bool isPreviewMode,
          bool isInEditorContext,
          List<String> blockIds
        })>(
      selector: (_, provider) {
        final blocks =
            provider.isInEditorContext ? provider.blocks : blocksToRender;
        final ids = blocks.map((b) => b['id']?.toString() ?? '').toList();
        return (
          isEditMode: provider.isEditMode,
          isPreviewMode: provider.isPreviewMode,
          isInEditorContext: provider.isInEditorContext,
          blockIds: ids,
        );
      },
      // Custom shouldRebuild to compare block IDs by content, not reference
      shouldRebuild: (prev, next) {
        if (prev.isEditMode != next.isEditMode) return true;
        if (prev.isPreviewMode != next.isPreviewMode) return true;
        if (prev.isInEditorContext != next.isInEditorContext) return true;
        if (prev.blockIds.length != next.blockIds.length) return true;
        for (int i = 0; i < prev.blockIds.length; i++) {
          if (prev.blockIds[i] != next.blockIds[i]) return true;
        }
        return false;
      },
      builder: (context, state, _) {
        final editProvider = context.read<WebsiteEditModeProvider>();

        // If URL forces edit mode, we treat it as edit mode even if provider isn't ready
        // BUT: if provider is explicitly in Preview Mode, respect that (don't force edit)
        final isProviderInPreviewMode = editProvider.isPreviewMode;
        final effectiveForceEdit = forceEditMode && !isProviderInPreviewMode;

        final isEditMode = state.isEditMode || effectiveForceEdit;
        final isInEditorContext = state.isInEditorContext || effectiveForceEdit;

        // Use edit provider blocks if in editor context, otherwise use the blocks we have
        // Note: If forceEditMode is true but provider IS NOT ready (state.isInEditorContext is false),
        // we use blocksToRender (from service) but display them with edit-mode visibility rules.
        final finalBlocks =
            state.isInEditorContext ? editProvider.blocks : blocksToRender;

        // In editor context, show all blocks (even hidden ones, with opacity)
        // In normal mode, filter by visibility
        final visibleBlocks = List<Map<String, dynamic>>.from(
          finalBlocks.where((block) {
            if (isInEditorContext) {
              return true; // Show all blocks in editor context
            }

            final isGloballyVisible = block['is_visible'] ?? true;
            if (!isGloballyVisible) {
              return false;
            }

            final data = Map<String, dynamic>.from(block['block_data'] ?? {});
            final visibility = _normalizeBlockVisibility(data['visibility']);
            return visibility[currentBreakpoint] ?? true;
          }),
        )..sort(
            (a, b) => (a['sort_order'] ?? a['order_index'] ?? 0)
                .compareTo(b['sort_order'] ?? b['order_index'] ?? 0),
          );

        // Build the page content (blocks)
        final effectiveTenantId = tenantProvider.tenantId ?? _resolvedTenantId;

        _scheduleProgressiveExpansionIfNeeded(
          tenantId: effectiveTenantId,
          isEditMode: isEditMode,
          blockCount: visibleBlocks.length,
        );

        Widget pageContent = _buildPageContent(
          context: context,
          visibleBlocks: visibleBlocks,
          isEditMode: isEditMode,
          editProvider: editProvider,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          textColor: textColor,
          sectionSpacing: sectionSpacing,
          containerPadding: containerPadding,
          tenantId: effectiveTenantId,
          isInitialLoading: false, // Loading handled by main.dart
        );

        // Just return the page content - toolbar and side panel are handled by PublicStoreLayout
        return pageContent;
      },
    );
  }

  /// Build the main page content (blocks list)
  Widget _buildPageContent({
    required BuildContext context,
    required List<Map<String, dynamic>> visibleBlocks,
    required bool isEditMode,
    required WebsiteEditModeProvider editProvider,
    required Color primaryColor,
    required Color accentColor,
    required String headingFont,
    required String bodyFont,
    required double headingSize,
    required double bodySize,
    required Color textColor,
    required double sectionSpacing,
    required double containerPadding,
    String? tenantId,
    bool isInitialLoading = false,
  }) {
    // If still loading initial data, show empty container (not "Próximamente")
    // This prevents the flash of "Coming Soon" while blocks are loading
    if (isInitialLoading && visibleBlocks.isEmpty) {
      return const SizedBox.shrink();
    }

    if (visibleBlocks.isNotEmpty) {
      final blocksToBuild =
          (!isEditMode && visibleBlocks.length > _progressiveBlockLimit)
              ? visibleBlocks.take(_progressiveBlockLimit).toList()
              : visibleBlocks;

      // NOTE: PublicStoreLayout provides the scroll container.
      // Keep this widget NON-scrollable to avoid nested scroll views.
      return Column(
        children: [
          for (int i = 0; i < blocksToBuild.length; i++) ...[
            // Use _BlockDataSelector to read block data from provider
            // This ensures each block only rebuilds when ITS data changes
            _BlockDataSelector(
              key:
                  ValueKey('${blocksToBuild[i]['id']}_${tenantId}_$isEditMode'),
              blockId: blocksToBuild[i]['id']?.toString() ?? '',
              fallbackBlockData: blocksToBuild[i],
              isInEditorContext: isEditMode,
              builder: (context, blockData) => _buildBlockFromData(
                blockData,
                primaryColor,
                accentColor,
                headingFont: headingFont,
                bodyFont: bodyFont,
                headingSize: headingSize,
                bodySize: bodySize,
                textColor: textColor,
                sectionSpacing: sectionSpacing,
                containerPadding: containerPadding,
                isEditMode: isEditMode,
                tenantId: tenantId,
              ),
            ),
            // Add spacer between blocks (not after the last one)
            if (i < blocksToBuild.length - 1)
              _buildBlockSpacer(
                blockId: blocksToBuild[i]['id']?.toString() ?? '',
                blockData: Map<String, dynamic>.from(
                    blocksToBuild[i]['block_data'] ?? {}),
                defaultSpacing: sectionSpacing,
                isEditMode: isEditMode,
                editProvider: editProvider,
              ),
          ],
          SizedBox(height: sectionSpacing),

          // Add block button at the end in edit mode
          if (isEditMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: _AddBlockButtonLarge(
                onAdd: (type) => editProvider.addBlock(type),
              ),
            ),
        ],
      );
    } else if (isEditMode) {
      // Edit mode with no blocks - show empty state with add button
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.web,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'Tu sitio web está vacío',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Agrega bloques para construir tu página',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[500],
                      ),
                ),
                const SizedBox(height: 32),
                _AddBlockButtonLarge(
                  onAdd: (type) => editProvider.addBlock(type),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // No blocks - show coming soon page for visitors
      return Container(
        constraints: const BoxConstraints(minHeight: 500),
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.storefront,
                size: 100,
                color: primaryColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 32),
              Text(
                'Próximamente',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Estamos preparando algo increíble para ti',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Build a spacer handle between blocks
  Widget _buildBlockSpacer({
    required String blockId,
    required Map<String, dynamic> blockData,
    required double defaultSpacing,
    required bool isEditMode,
    required WebsiteEditModeProvider editProvider,
  }) {
    // Get spacing from block data, default to theme setting
    final spacingAfter =
        (blockData['spacingAfter'] as num?)?.toDouble() ?? defaultSpacing;

    if (isEditMode) {
      return BlockSpacerHandle(
        currentSpacing: spacingAfter,
        minSpacing: 0,
        maxSpacing: 200,
        snapIncrement: 4,
        isActive: true,
        onSpacingChanged: (newSpacing) {
          // Update in provider (will be saved when user saves)
          editProvider.updateBlockData(blockId, 'spacingAfter', newSpacing);
        },
        onSpacingChangeEnd: (finalSpacing) {
          // Already updated in onSpacingChanged
        },
      );
    } else {
      // Non-edit mode: just show the spacing
      return SizedBox(height: spacingAfter);
    }
  }

  Widget _buildBlockFromData(
    Map<String, dynamic> blockData,
    Color primaryColor,
    Color accentColor, {
    required String headingFont,
    required String bodyFont,
    required double headingSize,
    required double bodySize,
    required Color textColor,
    required double sectionSpacing,
    required double containerPadding,
    bool isEditMode = false,
    String? tenantId,
  }) {
    final blockId = blockData['id']?.toString() ?? '';
    final blockType = (blockData['block_type'] ?? '').toString();
    final data = Map<String, dynamic>.from(blockData['block_data'] ?? {});
    final isVisible = blockData['is_visible'] ?? true;

    // Debug: trace style data flow
    if (blockType == 'hero') {
      final style = data['style'];
      debugPrint('🎨 [_buildBlockFromData] Hero isEditMode=$isEditMode');
      debugPrint('🎨 [_buildBlockFromData] Hero data.style=$style');
      if (style is Map) {
        debugPrint(
            '🎨 [_buildBlockFromData] backgroundType=${style['backgroundType']}, gradientColor1=${style['gradientColor1']}');
      }
    }

    data.remove('visibility');
    final resolvedHeadingFont = headingFont.isNotEmpty ? headingFont : null;
    final resolvedBodyFont = bodyFont.isNotEmpty ? bodyFont : null;

    final baseTheme = Theme.of(context);
    final themedText = baseTheme.textTheme.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );

    // Full-width blocks (like Commencal's edge-to-edge banners) get no horizontal padding
    final blockTypeNormalized = blockType.toLowerCase();
    final fullBleed = _toBool(data['fullBleed']) ?? false;
    final isFullWidthBlock = fullBleed ||
        const [
          'hero',
          'carousel',
          'videobanner',
          'categorygrid',
          'partnersbanner',
        ].contains(blockTypeNormalized);

    final horizontalPadding =
        isFullWidthBlock ? 0.0 : containerPadding.clamp(0.0, 200.0).toDouble();

    // Use editable renderer if in edit mode
    final blockHeight = (data['blockHeight'] as num?)?.toDouble();

    Widget content = isEditMode
        ? DeferredEditableBlockRenderer.build(
            context: context,
            blockId: blockId,
            blockType: blockType,
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            featuredProducts:
                blockType == 'products' ? _featuredProducts : null,
            headingFont: resolvedHeadingFont,
            bodyFont: resolvedBodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
              onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
            isVisible: isVisible,
            tenantId: tenantId,
          )
        : WebsiteBlockRenderer.build(
            context: context,
            blockType: blockType,
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            featuredProducts:
                blockType == 'products' ? _featuredProducts : null,
            previewMode: false,
            headingFont: resolvedHeadingFont,
            bodyFont: resolvedBodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
              onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
            tenantId: tenantId,
          );

    // Apply custom block height if set (for non-edit mode - edit mode handles it in EditableBlockRenderer)
    // Blocks use LayoutBuilder internally to fill/center within this height
    // Dynamic content blocks should NOT have fixed height - they need to grow with content
    if (!isEditMode && blockHeight != null) {
      // Blocks with dynamic content should NOT have fixed height (clips content)
      const dynamicContentBlocks = {
        'products',
        'services',
        'features',
        'testimonials',
        'faq',
        'team',
        'pricing',
        'stats',
        'gallery',
        'categorygrid',
        'brandlogos',
        'partnersbanner',
      };
      final isDynamicContent =
          dynamicContentBlocks.contains(blockTypeNormalized);

      if (!isDynamicContent) {
        // Only apply fixed height for blocks that support it (hero, carousel, canvas, etc.)
        content = SizedBox(
          height: blockHeight,
          width: double.infinity,
          child: content,
        );
      }
      // Dynamic content blocks: don't wrap - let them size naturally
    }

    // Only apply horizontal padding - vertical spacing is now handled by BlockSpacerHandle
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Theme(
        data: baseTheme.copyWith(textTheme: themedText),
        child: content,
      ),
    );
  }

  Color _resolveColor(String raw, Color fallback) {
    final value = raw.trim();
    if (value.isEmpty) return fallback;

    Color? parsed;
    int? intValue;

    String cleaned = value.toLowerCase();
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

    if (intValue != null) {
      parsed = Color(intValue);
    }

    return parsed ?? fallback;
  }

  double _resolveDouble(
    String raw,
    double fallback, {
    double? min,
    double? max,
  }) {
    final value = raw.trim();
    if (value.isEmpty) {
      return fallback;
    }

    final parsed = double.tryParse(value);
    if (parsed == null) {
      return fallback;
    }

    var result = parsed;
    if (min != null && result < min) {
      result = min;
    }
    if (max != null && result > max) {
      result = max;
    }
    return result;
  }
}

/// Large add block button for the end of the page
class _AddBlockButtonLarge extends StatelessWidget {
  final void Function(String blockType) onAdd;

  const _AddBlockButtonLarge({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () async {
            final blockType = await showDialog<String>(
              context: context,
              builder: (context) => const AddBlockDialog(),
            );
            if (blockType != null) {
              onAdd(blockType);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.blue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Agregar nuevo bloque',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Haz clic para agregar contenido a tu página',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A widget that selects block data from the provider and only rebuilds when THAT block's data changes.
/// This prevents all blocks from rebuilding when any block is edited.
class _BlockDataSelector extends StatelessWidget {
  final String blockId;
  final Map<String, dynamic> fallbackBlockData;
  final bool isInEditorContext;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;

  const _BlockDataSelector({
    super.key,
    required this.blockId,
    required this.fallbackBlockData,
    required this.isInEditorContext,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    // If not in editor context, use fallback data (from WebsiteService)
    if (!isInEditorContext) {
      return builder(context, fallbackBlockData);
    }

    // In editor context, select only THIS block's data from the provider
    return Selector<WebsiteEditModeProvider, Map<String, dynamic>?>(
      selector: (_, provider) {
        // Find this block in the provider's blocks list
        for (final block in provider.blocks) {
          if (block['id']?.toString() == blockId) {
            return block;
          }
        }
        return null;
      },
      // Compare block data by content, not reference
      // For canvas blocks, ignore activeElementId since it's managed internally
      shouldRebuild: (prev, next) {
        if (prev == null && next == null) return false;
        if (prev == null || next == null) return true;

        final prevData = Map<String, dynamic>.from(prev['block_data'] ?? {});
        final nextData = Map<String, dynamic>.from(next['block_data'] ?? {});

        // For canvas blocks, don't rebuild for activeElementId changes
        // The canvas widget manages this internally
        final blockType = (prev['block_type'] ?? '').toString().toLowerCase();
        if (blockType == 'canvas') {
          // Remove transient properties before comparing
          prevData.remove('activeElementId');
          nextData.remove('activeElementId');
        }

        // Compare remaining data
        // Use string representation for deep comparison
        return prevData.toString() != nextData.toString();
      },
      builder: (context, blockData, _) {
        // Use the selected block data, or fallback if not found
        return builder(context, blockData ?? fallbackBlockData);
      },
    );
  }
}
