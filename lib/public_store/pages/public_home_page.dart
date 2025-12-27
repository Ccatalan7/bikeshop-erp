import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/models/website_models.dart';
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
  bool _featuredProductsLoaded = false; // Load featured products once
  String? _resolvedTenantId;
  bool _isResolvingTenantId = false;

  static const List<String> _responsiveBreakpoints = [
    'desktop',
    'tablet',
    'mobile'
  ];

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint('🏠 [PublicHomePage] initState() called');
    // Load featured products once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🏠 [PublicHomePage] postFrameCallback - loading data');
      _ensureTenantId();
      _loadFeaturedProductsOnce();
    });
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
    // If we're disposed, we can no longer safely touch context/provider.
    if (!mounted) return _resolvedTenantId;
    try {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final providerId = tenantProvider.tenantId;
      if (providerId != null && providerId.isNotEmpty) return providerId;
    } catch (_) {}
    if (_resolvedTenantId != null && _resolvedTenantId!.isNotEmpty) {
      return _resolvedTenantId;
    }
    final id = await TenantService().getTenantId();
    if (!mounted) return _resolvedTenantId;
    if (id != null && id.isNotEmpty) {
      setState(() => _resolvedTenantId = id);
      return id;
    }
    return null;
  }

  Future<void> _loadFeaturedProductsOnce() async {
    if (_featuredProductsLoaded || !mounted) return;

    final tenantId = await _effectiveTenantId();
    if (tenantId == null || tenantId.isEmpty) return;
    _featuredProductsLoaded = true;

    if (!mounted) return;
    final websiteService = context.read<WebsiteService>();
    final featuredEntries =
        await websiteService.loadFeaturedProductsForTenant(tenantId);
    final activeFeatured = featuredEntries.where((fp) => fp.active).toList();

    if (activeFeatured.isNotEmpty && mounted) {
      final products = await _fetchFeaturedProducts(activeFeatured);
      if (mounted) {
        setState(() => _featuredProducts = products);
      }
    }
  }

  // ignore: unused_element
  void _checkAutoEditMode() {
    if (!mounted || _editModeChecked) return;
    _editModeChecked = true;

    // Check URL for edit=true or preview=true parameters
    // Handle both regular URLs and hash-based routing (/#/path?edit=true)
    final uri = Uri.base;

    var shouldEdit = uri.queryParameters['edit'] == 'true';
    var shouldPreview = uri.queryParameters['preview'] == 'true';

    // For hash-based routing, the query params are in the fragment
    // URL format: http://localhost:64749/#/tienda?edit=true
    // The fragment would be: /tienda?edit=true
    if ((!shouldEdit && !shouldPreview) && uri.fragment.isNotEmpty) {
      // The fragment contains the path AND query string
      // We need to parse it as a URI to extract query params
      final fragmentWithScheme = 'http://x${uri.fragment}';
      final fragmentUri = Uri.tryParse(fragmentWithScheme);

      if (fragmentUri != null) {
        shouldEdit = fragmentUri.queryParameters['edit'] == 'true';
        shouldPreview = fragmentUri.queryParameters['preview'] == 'true';
      }
    }

    if (shouldEdit || shouldPreview) {
      final editProvider = context.read<WebsiteEditModeProvider>();
      final websiteService = context.read<WebsiteService>();

      // If not already in editor context, enter the appropriate mode
      if (!editProvider.isInEditorContext) {
        final blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
        final settings = Map<String, dynamic>.from(websiteService.settings);

        if (shouldEdit) {
          // Go directly to edit mode (with side panel)
          editProvider.enterEditMode(blocks, settings);
          debugPrint('🎨 [HomePage] Auto-entered EDIT mode from URL');
        } else {
          // Go to preview mode (top bar only)
          editProvider.enterPreviewMode(blocks, settings);
          debugPrint('👁️ [HomePage] Auto-entered PREVIEW mode from URL');
        }
      }
    }
  }

  /// Check edit mode using GoRouter state (called from build method)
  void _checkEditModeFromRouter(BuildContext context) {
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

      // If not already in editor context, enter the appropriate mode
      if (!editProvider.isInEditorContext) {
        // Schedule for next frame to avoid calling during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          final blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
          final settings = Map<String, dynamic>.from(websiteService.settings);

          if (shouldEdit) {
            editProvider.enterEditMode(blocks, settings);
          } else {
            editProvider.enterPreviewMode(blocks, settings);
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset edit mode check on navigation
    _editModeChecked = false;
  }

  /// Update the edit provider with home page blocks if we're in edit mode
  /// and coming from a different page
  // ignore: unused_element
  void _updateEditProviderIfNeeded() {
    if (!mounted) return;

    final editProvider = context.read<WebsiteEditModeProvider>();

    // If we're already in edit mode (or preview mode), update the blocks for home page
    if (editProvider.isEditMode || editProvider.isPreviewMode) {
      // Check if we're coming from a different page (not home)
      if (editProvider.currentPageSlug != null &&
          editProvider.currentPageSlug!.isNotEmpty) {
        final websiteService = context.read<WebsiteService>();
        final blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
        final settings = Map<String, dynamic>.from(websiteService.settings);

        debugPrint(
            '🔄 [HomePage] Page changed while in edit mode: ${editProvider.currentPageSlug} → home');
        debugPrint(
            '📄 [HomePage] Updating provider with ${blocks.length} blocks for home page');

        if (editProvider.isEditMode) {
          editProvider.enterEditMode(blocks, settings);
        } else {
          editProvider.enterPreviewMode(blocks, settings);
        }

        _editModeChecked = true;
      }
    }
  }

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

  Future<List<Product>> _fetchFeaturedProducts(
    List<FeaturedProduct> featuredEntries,
  ) async {
    if (featuredEntries.isEmpty) {
      return const [];
    }

    final tenantId = await _effectiveTenantId();
    if (tenantId == null || tenantId.isEmpty) return const [];

    final productIds =
        featuredEntries.map((entry) => entry.productId).toSet().toList();

    try {
      final response = await Supabase.instance.client
          .from('products')
          .select()
          .eq('tenant_id', tenantId) // ⚠️ CRITICAL: Filter by tenant_id
          .inFilter('id', productIds)
          .eq('show_on_website', true)
          .eq('is_active', true);

      final productsById = <String, Product>{};
      for (final row in response as List<dynamic>) {
        try {
          final map = Map<String, dynamic>.from(row as Map);
          final product = _productFromMap(map);
          productsById[product.id] = product;
        } catch (error) {
          // Skip malformed products silently
        }
      }

      final orderedProducts = <Product>[];
      for (final entry in featuredEntries
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex))) {
        final product = productsById[entry.productId];
        if (product != null) {
          orderedProducts.add(product);
        }
      }

      // Filter out out-of-stock products unless in edit mode (admin editing website)
      final editProvider = context.read<WebsiteEditModeProvider>();
      final isEditMode = editProvider.isEditMode || editProvider.isPreviewMode;

      var result = orderedProducts.take(8).toList();
      if (!isEditMode) {
        result = result.where((p) => p.stockQuantity > 0).toList();
      }

      return result;
    } catch (error) {
      return const [];
    }
  }

  Product _productFromMap(Map<String, dynamic> json) {
    final price = (json['price'] as num?)?.toDouble() ?? 0.0;
    final cost = (json['cost'] as num?)?.toDouble() ?? 0.0;
    final stockQuantity =
        json['inventory_qty'] as int? ?? json['stock_quantity'] as int? ?? 0;
    final minStock =
        json['min_stock_level'] as int? ?? json['min_stock'] as int? ?? 0;
    final maxStock =
        json['max_stock_level'] as int? ?? json['max_stock'] as int? ?? 0;
    final categoryValue = (json['category'] as String?) ?? 'other';

    final productTypeValue = (json['product_type'] as String?)?.toLowerCase();

    return Product(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?) ?? 'Sin nombre',
      sku: (json['sku'] as String?) ?? '',
      barcode: json['barcode'] as String?,
      price: price,
      cost: cost,
      stockQuantity: stockQuantity,
      minStockLevel: minStock,
      maxStockLevel: maxStock > 0 ? maxStock : 100,
      imageUrl: json['image_url'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      category: ProductCategory.values.firstWhere(
        (c) => c.name == categoryValue,
        orElse: () => ProductCategory.other,
      ),
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      specifications:
          Map<String, String>.from(json['specifications'] as Map? ?? {}),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      unit: ProductUnit.values.firstWhere(
        (u) => u.name == json['unit'],
        orElse: () => ProductUnit.unit,
      ),
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      productType: ProductType.values.firstWhere(
        (t) => t.name == productTypeValue,
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    try {
      final dynamic dynamicValue = value;
      final result = dynamicValue.toDate();
      if (result is DateTime) {
        return result;
      }
    } catch (_) {
      // Ignore conversion errors and fallback below.
    }
    return DateTime.now();
  }

  @override
  void dispose() {
    debugPrint('🏠 [PublicHomePage] dispose() called');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    debugPrint(
        '🏠 [PublicHomePage] build() called - wantKeepAlive: $wantKeepAlive');

    // Check for edit/preview mode from URL query parameters (using GoRouter)
    // We check this here to prevent a 1-frame flash where hidden blocks are filtered out
    // before the edit provider fully initializes.
    final qp = GoRouterState.of(context).uri.queryParameters;
    final forceEditMode = qp['edit'] == 'true';

    _checkEditModeFromRouter(context);

    // Read data from providers - WATCH WebsiteService to rebuild when blocks load
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final websiteService = context
        .watch<WebsiteService>(); // Changed to watch() for progressive loading
    if (tenantProvider.tenantId == null &&
        (_resolvedTenantId == null || _resolvedTenantId!.isEmpty)) {
      // ERP/editor host: resolve tenant via TenantService so product blocks can load.
      _ensureTenantId();
    }

    final primaryColor = _resolveColor(
      websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );
    final headingFont = websiteService.getSetting('theme_heading_font', '');
    final bodyFont = websiteService.getSetting('theme_body_font', '');
    final headingSize = _resolveDouble(
      websiteService.getSetting('theme_heading_size', ''),
      48.0,
      min: 24.0,
      max: 72.0,
    );
    final bodySize = _resolveDouble(
      websiteService.getSetting('theme_body_size', ''),
      16.0,
      min: 12.0,
      max: 24.0,
    );
    final textColor = _resolveColor(
      websiteService.getSetting('theme_text_color', ''),
      PublicStoreTheme.textPrimary,
    );
    final sectionSpacing = _resolveDouble(
      websiteService.getSetting('theme_section_spacing', ''),
      64.0,
      min: 32.0,
      max: 128.0,
    );
    final containerPadding = _resolveDouble(
      websiteService.getSetting('theme_container_padding', ''),
      24.0,
      min: 16.0,
      max: 64.0,
    );

    // Use blocks from WebsiteService (loaded by main.dart progressively)
    final blocksToRender = websiteService.blocks;
    final isDataLoading = !websiteService.hasLoadedForTenant;

    // Show loading skeleton if data is still loading (and we don't have blocks yet)
    if (isDataLoading && blocksToRender.isEmpty) {
      // Use LayoutBuilder to fill the full available height
      // This prevents the footer from appearing in the middle of the screen
      return LayoutBuilder(
        builder: (context, constraints) {
          // Calculate minimum height to fill viewport (minus header/footer space)
          final viewportHeight = MediaQuery.of(context).size.height;
          final minHeight =
              viewportHeight - 200; // Approximate header + footer height

          return SizedBox(
            height: minHeight > 400 ? minHeight : 400,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      );
    }

    // Show empty state ONLY if:
    // 1. No tenant detected AND no blocks loaded (true public store failure)
    // 2. NOT when blocks ARE loaded (ERP preview mode - blocks loaded via authenticated user)
    if (tenantProvider.tenantId == null &&
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
    return Selector<WebsiteEditModeProvider,
        ({bool isEditMode, bool isInEditorContext, List<String> blockIds})>(
      selector: (_, provider) {
        final blocks =
            provider.isInEditorContext ? provider.blocks : blocksToRender;
        final ids = blocks.map((b) => b['id']?.toString() ?? '').toList();
        return (
          isEditMode: provider.isEditMode,
          isInEditorContext: provider.isInEditorContext,
          blockIds: ids,
        );
      },
      // Custom shouldRebuild to compare block IDs by content, not reference
      shouldRebuild: (prev, next) {
        if (prev.isEditMode != next.isEditMode) return true;
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
        final isEditMode = state.isEditMode || forceEditMode;
        final isInEditorContext = state.isInEditorContext || forceEditMode;

        // Use edit provider blocks if in editor context, otherwise use the blocks we have
        // Note: If forceEditMode is true but provider IS NOT ready (state.isInEditorContext is false),
        // we use blocksToRender (from service) but display them with edit-mode visibility rules.
        final finalBlocks =
            state.isInEditorContext ? editProvider.blocks : blocksToRender;

        // In editor context, show all blocks (even hidden ones, with opacity)
        // In normal mode, filter by visibility
        final visibleBlocks = List<Map<String, dynamic>>.from(
          finalBlocks.where((block) {
            if (isInEditorContext)
              return true; // Show all blocks in editor context

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
      return SingleChildScrollView(
        child: Column(
          children: [
            for (int i = 0; i < visibleBlocks.length; i++) ...[
              // Use _BlockDataSelector to read block data from provider
              // This ensures each block only rebuilds when ITS data changes
              _BlockDataSelector(
                key: ValueKey('${visibleBlocks[i]['id']}_$tenantId'),
                blockId: visibleBlocks[i]['id']?.toString() ?? '',
                fallbackBlockData: visibleBlocks[i],
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
              if (i < visibleBlocks.length - 1)
                _buildBlockSpacer(
                  blockId: visibleBlocks[i]['id']?.toString() ?? '',
                  blockData: Map<String, dynamic>.from(
                      visibleBlocks[i]['block_data'] ?? {}),
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
        ),
      );
    } else if (isEditMode) {
      // Edit mode with no blocks - show empty state with add button
      return SingleChildScrollView(
        child: Column(
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
        ),
      );
    } else {
      // No blocks - show coming soon page for visitors
      return SingleChildScrollView(
        child: Container(
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
            onNavigate: (route) => context.go(route),
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
            onNavigate: (route) => context.go(route),
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
