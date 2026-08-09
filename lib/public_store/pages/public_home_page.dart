import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_page_composition.dart';
import '../../modules/website/models/website_responsive_authoring.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/models/website_editor_capability.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/theme/website_resolved_theme.dart';
import '../../modules/website/widgets/website_editor_document_binding.dart';
import '../../shared/models/product.dart';
import '../../shared/models/public_product_visibility_policy.dart';
import '../../shared/services/tenant_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../services/public_store_scroll_state.dart';
import '../widgets/page_composition.dart';
import '../widgets/public_store_layout.dart';

class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key});

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage>
    with AutomaticKeepAliveClientMixin {
  List<Product> _featuredProducts = [];
  bool _featuredProductsLoaded = false; // Load featured products once
  String? _resolvedTenantId;
  bool _isResolvingTenantId = false;

  PublicStoreScrollState? _scrollState;
  int _lastHomeRefreshSignal = 0;

  // ---- Authority-bound HOME editor snapshot (RPC-only) -------------------
  // The public bootstrap (websiteService.blocks) stays 100% public: draft
  // and hidden HOME blocks arrive EXCLUSIVELY through
  // loadEditorPageWithBlocks('') under the exact granted lease.
  CachedPageSnapshot? _editorSnapshot;
  WebsiteEditorCapabilitySnapshot? _editorSnapshotLease;
  int _editorLoadSerial = 0;
  bool _editorLoadInFlight = false;
  WebsiteService? _observedFreshnessService;
  PublicInventoryService? _observedInventoryService;
  bool _inventoryRevalidationPending = false;
  bool _inventoryRevalidationScheduled = false;
  bool _inventoryTickerActive = true;
  bool _featuredProductsLoadActive = false;

  // Progressive rendering to reduce first-frame jank on mobile.
  // We render only a couple of blocks initially, then expand shortly after.
  static const int _initialBlockRenderLimitDefault = 2;
  static const int _initialBlockRenderLimitAndroid = 1;

  int _progressiveBlockLimit = _initialBlockRenderLimitDefault;
  int? _progressiveScheduledTarget;
  int? _progressiveScheduledIntermediateTarget;
  String? _lastProgressiveTenantId;

  // Kept alive: the storefront shell keeps ONE stable content anchor
  // across Public|Preview|Edit, so the old element-activation conflicts
  // that forced this off no longer exist. Route changes still remount
  // legitimately.
  @override
  bool get wantKeepAlive => true;

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

    // 2) Refresh featured products without replacing the current cards with
    // placeholders while the origin request is in flight.
    if (!mounted) return;
    await _loadFeaturedProductsOnce(forceRefresh: true);
  }

  void _handlePublicInventoryInvalidated() {
    if (!mounted) return;
    _inventoryRevalidationPending = true;
    _scheduleInventoryRevalidation();
  }

  void _scheduleInventoryRevalidation() {
    if (!mounted ||
        !_inventoryTickerActive ||
        _inventoryRevalidationScheduled ||
        !_inventoryRevalidationPending) {
      return;
    }
    _inventoryRevalidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inventoryRevalidationScheduled = false;
      if (!mounted || !_inventoryTickerActive) return;
      if (!_inventoryRevalidationPending) return;
      if (_featuredProductsLoadActive) return;

      _inventoryRevalidationPending = false;
      unawaited(_loadFeaturedProductsOnce(forceRefresh: true));
    });
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

  Future<void> _loadFeaturedProductsOnce({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (_featuredProductsLoaded && !forceRefresh) return;
    if (_featuredProductsLoadActive) {
      if (forceRefresh) {
        _inventoryRevalidationPending = true;
      }
      return;
    }
    _featuredProductsLoadActive = true;

    try {
      final tenantId = await _effectiveTenantId();
      if (!mounted) return;
      if (tenantId == null || tenantId.isEmpty) return;

      final inventoryService = context.read<PublicInventoryService>();
      final websiteService = context.read<WebsiteService>();
      final visibilityPolicy =
          PublicProductVisibilityPolicy.hasAnySetting(websiteService.settings)
              ? PublicProductVisibilityPolicy.fromSettings(
                  websiteService.settings,
                )
              : null;
      final products = await inventoryService.getFeaturedProductsForTenant(
        tenantId: tenantId,
        policy: visibilityPolicy,
        limit: 8,
      );
      if (!mounted) return;
      final nextProducts = products.take(8).toList(growable: false);
      if (!_featuredProductsLoaded ||
          !_samePublicProductSnapshots(_featuredProducts, nextProducts)) {
        setState(() {
          _featuredProducts = nextProducts;
          _featuredProductsLoaded = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (!_featuredProductsLoaded) {
        setState(() => _featuredProductsLoaded = true);
      }
    } finally {
      _featuredProductsLoadActive = false;
      if (mounted && _inventoryTickerActive && _inventoryRevalidationPending) {
        _scheduleInventoryRevalidation();
      }
    }
  }

  bool _samePublicProductSnapshots(
    List<Product> current,
    List<Product> next,
  ) {
    if (current.length != next.length) return false;
    return _publicProductFingerprint(current) ==
        _publicProductFingerprint(next);
  }

  String _publicProductFingerprint(List<Product> products) {
    return jsonEncode([
      for (final product in products)
        <String, dynamic>{
          ...product.toJson(),
          'available_stock_quantity': product.availableStockQuantity,
          'full_sets_available': product.fullSetsAvailable,
          'is_partial': product.isPartial,
        },
    ]);
  }

  /// The ONE freshness listener: a lease transition invalidates the editor
  /// snapshot so the next build re-requests it under the CURRENT lease.
  void _handleCmsFreshnessSignal() {
    if (!mounted) return;
    if (_editorSnapshot == null && !_editorLoadInFlight) return;
    setState(() {
      _editorSnapshot = null;
      _editorSnapshotLease = null;
      _editorLoadSerial++; // Supersedes any in-flight editor load.
      _editorLoadInFlight = false;
    });
  }

  /// Loads the HOME editor projection through the authority-bound RPC. The
  /// FULL identity context — provider generation and identity revision,
  /// lease fingerprint + authorityEpoch, tenant, service epoch and request
  /// identity — is captured BEFORE the await and re-validated (plus
  /// mounted/editor-context) at completion; a stale completion never binds.
  void _ensureEditorSnapshot({
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String? tenantId,
  }) {
    final lease = editProvider.editorEntryLease;
    if (!editProvider.isInEditorContext ||
        lease == null ||
        !lease.granted ||
        tenantId == null ||
        tenantId.isEmpty) {
      return;
    }
    final heldLease = _editorSnapshotLease;
    if (_editorSnapshot != null &&
        heldLease != null &&
        heldLease.fingerprint == lease.fingerprint &&
        heldLease.authorityEpoch == lease.authorityEpoch) {
      return;
    }
    if (_editorLoadInFlight) return;
    _editorLoadInFlight = true;
    final serial = ++_editorLoadSerial;
    final generation = editProvider.editorEntryLeaseGeneration;
    final identityRevision = editProvider.editorEntryLeaseIdentityRevision;
    final leaseFingerprint = lease.fingerprint;
    final leaseEpoch = lease.authorityEpoch;
    final serviceEpoch = websiteService.identityEpoch;
    final requestIdentity = websiteService.editorCapabilityRequestIdentity;
    unawaited(() async {
      CachedPageSnapshot? snapshot;
      var authorityLost = false;
      try {
        snapshot = await websiteService.loadEditorPageWithBlocks(
          '',
          tenantId: tenantId,
        );
      } on WebsiteEditorReadSupersededException {
        // Obsolete completion: silently release ONLY this loader's flight
        // state so the current identity can retry; the new session is
        // never touched.
        if (mounted && serial == _editorLoadSerial) {
          _editorLoadInFlight = false;
        }
        return;
      } on WebsiteEditorAuthorityException {
        authorityLost = true;
      } catch (_) {
        // Transient: Home keeps rendering the public bootstrap; the
        // pending lease will retry on a later signal/build.
      }
      if (!mounted || serial != _editorLoadSerial) return;
      _editorLoadInFlight = false;
      if (authorityLost) {
        // One revocation; the SINGLE CMS signal is emitted by the layout
        // when it adopts the durable denial.
        editProvider.revokeEditorEntryLease();
        return;
      }
      final currentLease = editProvider.editorEntryLease;
      if (!editProvider.isInEditorContext ||
          currentLease == null ||
          !currentLease.granted ||
          currentLease.fingerprint != leaseFingerprint ||
          currentLease.authorityEpoch != leaseEpoch ||
          generation != editProvider.editorEntryLeaseGeneration ||
          identityRevision != editProvider.editorEntryLeaseIdentityRevision ||
          serviceEpoch != websiteService.identityEpoch ||
          requestIdentity != websiteService.editorCapabilityRequestIdentity) {
        return; // The identity context moved: never adopt this result.
      }
      if (snapshot == null) return; // No HOME page row yet.
      setState(() {
        _editorSnapshot = snapshot;
        _editorSnapshotLease = currentLease;
      });
    }());
  }

  /// Attaches the HOME document to the open editor session once the
  /// AUTHORITY-BOUND editor snapshot for the exact current lease is loaded.
  /// Mode entry/exit is owned by the FSM route binding in the storefront
  /// layout; this consumer only supplies its page document.
  void _bindEditorDocument({
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
  }) {
    final lease = editProvider.editorEntryLease;
    final snapshot = _editorSnapshot;
    final heldLease = _editorSnapshotLease;
    final snapshotIsCurrent = snapshot != null &&
        lease != null &&
        lease.granted &&
        heldLease != null &&
        heldLease.fingerprint == lease.fingerprint &&
        heldLease.authorityEpoch == lease.authorityEpoch;
    WebsiteEditorDocumentBinding.bind(
      context,
      editProvider: editProvider,
      ready: snapshotIsCurrent,
      blocks: () => List<Map<String, dynamic>>.from(
        snapshotIsCurrent ? snapshot.blocks : const <Map<String, dynamic>>[],
      ),
      settings: () => Map<String, dynamic>.from(websiteService.settings),
      // The HOME document has a REAL owner: the canonical home row. Save
      // targets exactly this page.
      pageId: snapshotIsCurrent ? snapshot.page.id : null,
      pageSlug: snapshotIsCurrent ? snapshot.page.slug : null,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextScrollState = context.read<PublicStoreScrollState>();
    if (_scrollState != nextScrollState) {
      _scrollState?.homeRefreshSignal.removeListener(_onHomeRefreshSignal);
      _scrollState = nextScrollState;
      _lastHomeRefreshSignal = nextScrollState.homeRefreshSignal.value;
      nextScrollState.homeRefreshSignal.addListener(_onHomeRefreshSignal);
    }

    final freshnessOwner = context.read<WebsiteService>();
    if (!identical(_observedFreshnessService, freshnessOwner)) {
      _observedFreshnessService?.cmsPageFreshnessSignal
          .removeListener(_handleCmsFreshnessSignal);
      _observedFreshnessService = freshnessOwner;
      freshnessOwner.cmsPageFreshnessSignal
          .addListener(_handleCmsFreshnessSignal);
    }

    PublicInventoryService? nextInventoryService;
    try {
      nextInventoryService = context.read<PublicInventoryService>();
    } catch (_) {
      // ERP-hosted previews may not provide the public inventory service.
    }
    if (_observedInventoryService != nextInventoryService) {
      _observedInventoryService
          ?.removeListener(_handlePublicInventoryInvalidated);
      _observedInventoryService = nextInventoryService;
      nextInventoryService?.addListener(_handlePublicInventoryInvalidated);
    }

    _inventoryTickerActive = TickerMode.of(context);
    if (_inventoryTickerActive && _inventoryRevalidationPending) {
      _scheduleInventoryRevalidation();
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

  @override
  void dispose() {
    _observedFreshnessService?.cmsPageFreshnessSignal
        .removeListener(_handleCmsFreshnessSignal);
    // Debug: dispose
    _scrollState?.homeRefreshSignal.removeListener(_onHomeRefreshSignal);
    _observedInventoryService
        ?.removeListener(_handlePublicInventoryInvalidated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Debug: build called

    // Read data from providers - WATCH WebsiteService to rebuild when blocks load
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final websiteService = context
        .watch<WebsiteService>(); // Changed to watch() for progressive loading
    final editProvider = context.watch<WebsiteEditModeProvider>();

    // The FSM route command in the storefront layout already owns the mode;
    // this consumer requests its authority-bound editor snapshot and binds
    // the HOME document once THAT is ready (public bootstrap never binds).
    _ensureEditorSnapshot(
      editProvider: editProvider,
      websiteService: websiteService,
      tenantId: tenantProvider.tenantId ?? _resolvedTenantId,
    );
    _bindEditorDocument(
      editProvider: editProvider,
      websiteService: websiteService,
    );

    if (tenantProvider.tenantId == null &&
        (_resolvedTenantId == null || _resolvedTenantId!.isEmpty)) {
      // ERP/editor host: resolve tenant via TenantService so product blocks can load.
      _ensureTenantId();
    }

    final resolvedTheme = WebsiteResolvedTheme.of(context);
    final primaryColor = resolvedTheme.primaryColor;
    final accentColor = resolvedTheme.accentColor;
    final headingFont = resolvedTheme.headingFont;
    final bodyFont = resolvedTheme.bodyFont;
    final headingSize = resolvedTheme.headingSize;
    final bodySize = resolvedTheme.bodySize;
    final textColor = resolvedTheme.textColor;
    final sectionSpacing = resolvedTheme.sectionSpacing;
    final containerPadding = resolvedTheme.containerPadding;

    // Debug: verify live theme preview values are applied
    if (editProvider.isInEditorContext &&
        (editProvider.pendingThemeSettings.containsKey('theme_heading_font') ||
            editProvider.pendingThemeSettings.containsKey('theme_body_font') ||
            editProvider.pendingThemeSettings.containsKey(
              'theme_heading_size',
            ) ||
            editProvider.pendingThemeSettings.containsKey('theme_body_size'))) {
      debugPrint(
        '🧪 [ThemePreview] effective headingFont="$headingFont" bodyFont="$bodyFont" headingSize=$headingSize bodySize=$bodySize',
      );
      debugPrint(
        '🧪 [ThemePreview] pendingThemeSettings=${editProvider.pendingThemeSettings}',
      );
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
        child: const Center(child: CircularProgressIndicator()),
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

    final logicalWidth = MediaQuery.sizeOf(context).width;
    final currentBreakpoint =
        WebsiteViewport.fromLogicalWidth(logicalWidth).wireName;
    final mode = switch (editProvider.mode) {
      WebsiteEditorMode.edit => WebsitePageCompositionMode.edit,
      WebsiteEditorMode.preview => WebsitePageCompositionMode.preview,
      WebsiteEditorMode.public => WebsitePageCompositionMode.public,
    };
    final ownsHomeDocument = _editorSnapshot != null
        ? editProvider.ownsPageDocument(
            pageId: _editorSnapshot!.page.id,
            pageSlug: _editorSnapshot!.page.slug,
          )
        : editProvider.ownsPageDocument();
    if (editProvider.isInEditorContext && !ownsHomeDocument) {
      return const Center(child: CircularProgressIndicator());
    }
    final sourceBlocks =
        editProvider.isInEditorContext ? editProvider.blocks : blocksToRender;
    final composition = WebsitePageComposition.project(
      blocks: sourceBlocks,
      mode: mode,
      breakpoint: currentBreakpoint,
      logicalWidth: logicalWidth,
      sectionSpacing: sectionSpacing,
    );
    final effectiveTenantId = tenantProvider.tenantId ?? _resolvedTenantId;
    final isEditMode = mode == WebsitePageCompositionMode.edit;
    _scheduleProgressiveExpansionIfNeeded(
      tenantId: effectiveTenantId,
      isEditMode: isEditMode,
      blockCount: composition.blocks.length,
    );

    return PageComposition(
      composition: composition,
      visibleBlockLimit: isEditMode ? null : _progressiveBlockLimit,
      primaryColor: primaryColor,
      accentColor: accentColor,
      textColor: textColor,
      containerPadding: containerPadding,
      featuredProducts: _featuredProducts,
      featuredProductsReady: _featuredProductsLoaded,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      tenantId: effectiveTenantId,
      onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
      isNavigationEligible: (href) =>
          PublicStoreLayout.isHrefPubliclyEligible(context, href),
      onAddBlock: (type, {atIndex}) =>
          editProvider.addBlock(type, atIndex: atIndex),
      onSpacingChanged: (blockId, spacing) =>
          editProvider.updateBlockData(blockId, 'spacingAfter', spacing),
      emptyState: _buildEmptyCompositionState(
        context,
        isEditMode: isEditMode,
        primaryColor: primaryColor,
      ),
    );
  }

  Widget _buildEmptyCompositionState(
    BuildContext context, {
    required bool isEditMode,
    required Color primaryColor,
  }) {
    if (isEditMode) {
      return Container(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.web, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'Tu sitio web está vacío',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Text(
              'Agrega bloques para construir tu página',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
