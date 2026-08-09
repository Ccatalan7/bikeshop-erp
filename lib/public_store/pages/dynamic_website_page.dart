import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_editor_capability.dart';
import '../../modules/website/models/website_page_composition.dart';
import '../../modules/website/models/website_page_models.dart';
import '../../modules/website/models/website_responsive_authoring.dart';
import '../../modules/website/models/website_seo_settings_aliases.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/theme/website_resolved_theme.dart';
import '../../modules/website/widgets/website_editor_document_binding.dart';
import '../../shared/services/tenant_service.dart';
import '../../shared/utils/seo_helper.dart';
import '../providers/public_store_tenant_provider.dart';
import '../widgets/full_page_loading.dart';
import '../widgets/page_composition.dart';
import '../widgets/public_store_layout.dart';
import 'static_policy_page.dart'
    show PublicWebsiteContactFacts, hasMeaningfulPublicWebsitePageContent;

/// Dynamic page that renders website_blocks for any page based on slug
///
/// This widget:
/// 1. Loads the page by slug from website_pages
/// 2. Loads blocks associated with that page from website_blocks
/// 3. Projects and renders blocks through the shared PageComposition
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
  WebsitePage? _page;
  String? _pageId;
  String? _snapshotFingerprint;
  // Audience/provenance of the currently held content. Editor-provenance
  // content may only render while the exact lease that authorized it is
  // still granted; see the audience guard in build().
  WebsitePageContentAudience _blocksAudience =
      WebsitePageContentAudience.public;
  WebsiteEditorCapabilitySnapshot? _blocksLease;
  int _loadGeneration = 0;
  WebsiteService? _observedWebsiteService;
  bool _cmsRevalidationPending = false;
  bool _cmsRevalidationScheduled = false;

  // Kept alive: the storefront shell keeps ONE stable content anchor
  // across Public|Preview|Edit, so the old element-activation conflicts
  // that forced this off no longer exist. Route changes still remount
  // legitimately.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _seedFromSnapshot(widget.slug);
    _loadPageData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final websiteService = context.read<WebsiteService>();
    if (!identical(_observedWebsiteService, websiteService)) {
      _observedWebsiteService?.cmsPageFreshnessSignal
          .removeListener(_handleCmsPageFreshnessSignal);
      _observedWebsiteService = websiteService;
      websiteService.cmsPageFreshnessSignal
          .addListener(_handleCmsPageFreshnessSignal);
    }

    if (_cmsRevalidationPending && TickerMode.of(context)) {
      _cmsRevalidationPending = false;
      _scheduleCmsPageOriginRevalidation();
    }
  }

  @override
  void didUpdateWidget(DynamicWebsitePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) {
      _seedFromSnapshot(widget.slug, clearOnMiss: true);
      // The rebuild after loading binds the new page document idempotently.
      _loadPageData();
    }
  }

  @override
  void dispose() {
    _observedWebsiteService?.cmsPageFreshnessSignal
        .removeListener(_handleCmsPageFreshnessSignal);
    super.dispose();
  }

  void _handleCmsPageFreshnessSignal() {
    if (!mounted) return;
    if (!TickerMode.of(context)) {
      _cmsRevalidationPending = true;
      return;
    }
    _scheduleCmsPageOriginRevalidation();
  }

  void _scheduleCmsPageOriginRevalidation() {
    if (_cmsRevalidationScheduled) return;
    _cmsRevalidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cmsRevalidationScheduled = false;
      if (!mounted) return;
      if (!TickerMode.of(context)) {
        _cmsRevalidationPending = true;
        return;
      }
      unawaited(_loadPageData());
    });
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
      _page = snapshot.page;
      _pageId = snapshot.page.id;
      _snapshotFingerprint = snapshot.fingerprint;
      _blocks = snapshot.blocks.toList(growable: false);
      _isLoading = false;
      _error = null;
      return true;
    }

    if (clearOnMiss) {
      _page = null;
      _pageId = null;
      _snapshotFingerprint = null;
      _blocks = [];
      _isLoading = true;
      _error = null;
    }
    return false;
  }

  /// Invalidates an editor-provenance snapshot whose lease was lost and
  /// reloads through the public read path. The current frame already renders
  /// the safe loading state; the reset happens post-frame (build-safe).
  void _invalidateEditorContentAndReloadPublic() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_blocksAudience != WebsitePageContentAudience.editor) return;
      setState(() {
        _page = null;
        _pageId = null;
        _snapshotFingerprint = null;
        _blocks = [];
        _blocksAudience = WebsitePageContentAudience.public;
        _blocksLease = null;
        _isLoading = true;
        _error = null;
      });
      // The reload arrives exclusively through the central CMS revalidation
      // signal emitted on the lease transition (exactly one load per
      // transition; no second local path).
    });
  }

  /// Attaches this CMS page's document to the open editor session once its
  /// blocks are loaded. Mode entry/exit is owned by the FSM route binding in
  /// the storefront layout; this consumer only supplies its page document.
  void _bindEditorDocument(WebsiteEditModeProvider editProvider) {
    if (_isLoading || _pageId == null) return;
    WebsiteEditorDocumentBinding.bind(
      context,
      editProvider: editProvider,
      ready: true,
      blocks: () => List<Map<String, dynamic>>.from(_blocks),
      settings: () =>
          Map<String, dynamic>.from(context.read<WebsiteService>().settings),
      pageId: _pageId,
      pageSlug: widget.slug,
    );
  }

  Future<void> _loadPageData() async {
    final loadGeneration = ++_loadGeneration;
    final requestedSlug = widget.slug;
    debugPrint(
        '🔄 [DynamicPage] _loadPageData() called for slug: "$requestedSlug"');

    final shouldShowLoading = _pageId == null;
    if (mounted && (_isLoading != shouldShowLoading || _error != null)) {
      setState(() {
        // Keep a matching snapshot visible while the origin is revalidated.
        _isLoading = shouldShowLoading;
        _error = null;
      });
    }
    _scheduleSeoUpdate(
      _page,
      _blocks,
      loadGeneration,
      originConfirmed: false,
    );

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

      WebsiteEditModeProvider? editProvider;
      try {
        editProvider = context.read<WebsiteEditModeProvider>();
      } catch (_) {
        editProvider = null;
      }
      // The provider is the sole mode owner and the layout's capability gate
      // has already applied (or refused) any URL entry command by the time
      // this routed child builds: an unauthorized visitor can never request
      // the editor load path from here.
      final editorRequested = editProvider?.isInEditorContext == true;

      // Start the joined page+blocks request immediately. Theme settings may
      // load alongside it; they must not create a page -> blocks waterfall.
      final requestLease = editProvider?.editorEntryLease;
      final requestGeneration = editProvider?.editorEntryLeaseGeneration;
      final requestIdentityRevision =
          editProvider?.editorEntryLeaseIdentityRevision;
      final requestServiceEpoch = websiteService.identityEpoch;
      final requestServiceIdentity =
          websiteService.editorCapabilityRequestIdentity;
      var adoptedAudience = editorRequested
          ? WebsitePageContentAudience.editor
          : WebsitePageContentAudience.public;
      final Future<PageSnapshotLoadResult> pageFuture;
      if (editorRequested) {
        pageFuture = () async {
          try {
            final editorSnapshot =
                await websiteService.loadEditorPageWithBlocks(
              requestedSlug,
              tenantId: tenantId!,
            );
            return editorSnapshot == null
                ? const PageSnapshotLoadResult.originMissing()
                : PageSnapshotLoadResult.origin(editorSnapshot);
          } on WebsiteEditorAuthorityException {
            // Editor authority was lost: either the local gate denied, or
            // the server (RLS/auth) rejected a read a stale cached grant
            // still believed authorized. Revoke the lease/FSM and adopt
            // ONLY the public result, never draft content. Transient errors
            // never take this branch (they rethrow upstream unclassified).
            // The single CMS revalidation for this transition is emitted by
            // the layout when it adopts the durable denial — emitting here
            // too would double the reload.
            if (mounted) {
              try {
                context
                    .read<WebsiteEditModeProvider>()
                    .revokeEditorEntryLease();
              } catch (_) {}
            }
            adoptedAudience = WebsitePageContentAudience.public;
            return websiteService.loadPageWithBlocksResult(
              requestedSlug,
              tenantId: tenantId!,
            );
          }
        }();
      } else {
        pageFuture = websiteService.loadPageWithBlocksResult(
          requestedSlug,
          tenantId: tenantId,
        );
      }
      final settingsFuture = !websiteService.hasSettingsForTenant(tenantId)
          ? websiteService.loadSettingsForTenant(tenantId)
          : Future<void>.value();
      await settingsFuture;
      final loadResult = await pageFuture;
      final snapshot = loadResult.snapshot;

      if (loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug ||
          !mounted) {
        return;
      }

      if (loadResult.isAuthoritativelyMissing) {
        setState(() {
          _page = null;
          _pageId = null;
          _snapshotFingerprint = null;
          _blocks = const [];
          _isLoading = false;
          _error = 'Esta página no está disponible.';
        });
        _scheduleSeoUpdate(
          null,
          const [],
          loadGeneration,
          originConfirmed: false,
        );
        return;
      }

      if (snapshot == null ||
          (!editorRequested && !snapshot.page.isPublished)) {
        throw Exception('Page not found: $requestedSlug');
      }

      debugPrint(
          '📄 [DynamicWebsitePage] Found page: "${snapshot.page.title}" (id: ${snapshot.page.id}, slug: ${snapshot.page.slug})');

      final nextBlocks = snapshot.blocks.toList(growable: false);
      // Editor-provenance content may only be adopted while the EXACT lease
      // that requested it is still granted; a stale editor response after a
      // revocation is dropped (the audience guard in build() reloads public).
      if (adoptedAudience == WebsitePageContentAudience.editor) {
        final currentLease = editProvider?.editorEntryLease;
        if (currentLease == null ||
            !currentLease.granted ||
            requestLease == null ||
            currentLease.fingerprint != requestLease.fingerprint ||
            currentLease.authorityEpoch != requestLease.authorityEpoch ||
            requestGeneration != editProvider?.editorEntryLeaseGeneration ||
            requestIdentityRevision !=
                editProvider?.editorEntryLeaseIdentityRevision ||
            requestServiceEpoch != websiteService.identityEpoch ||
            requestServiceIdentity !=
                websiteService.editorCapabilityRequestIdentity) {
          return;
        }
      }
      final didContentChange = _snapshotFingerprint != snapshot.fingerprint ||
          _pageId != snapshot.page.id ||
          _blocksAudience != adoptedAudience;
      if (didContentChange || _isLoading || _error != null) {
        setState(() {
          _page = snapshot.page;
          _pageId = snapshot.page.id;
          _snapshotFingerprint = snapshot.fingerprint;
          _blocks = nextBlocks;
          _blocksAudience = adoptedAudience;
          _blocksLease = adoptedAudience == WebsitePageContentAudience.editor
              ? requestLease
              : null;
          _isLoading = false;
          _error = null;
        });
      }
      _scheduleSeoUpdate(
        snapshot.page,
        nextBlocks,
        loadGeneration,
        originConfirmed: !editorRequested && loadResult.isOriginConfirmed,
      );

      // The setState above triggers a rebuild, whose document binding keeps
      // the canonical page context synchronized inside the editor shell.
    } on WebsiteEditorReadSupersededException {
      // An obsolete completion for a previous identity: discard silently —
      // no error surface, no revocation, no data. The current identity's
      // own load (triggered by the lease transition) owns the screen.
      return;
    } catch (e) {
      debugPrint('❌ [DynamicWebsitePage] Error: $e');
      if (mounted &&
          loadGeneration == _loadGeneration &&
          requestedSlug == widget.slug) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
        _scheduleSeoUpdate(
          _page,
          _blocks,
          loadGeneration,
          originConfirmed: false,
        );
      }
    }
  }

  void _scheduleSeoUpdate(
    WebsitePage? page,
    List<Map<String, dynamic>> blocks,
    int loadGeneration, {
    bool originConfirmed = false,
  }) {
    final requestedSlug = widget.slug;
    final websiteService = context.read<WebsiteService>();
    final storeName = websiteService
        .getSetting(
          'seo_business_name',
          websiteService.getSetting('store_name', ''),
        )
        .trim();
    final configuredTitle = page?.metaTitle?.trim() ?? '';
    final pageTitle = page?.title.trim() ?? '';
    final fallbackPageTitle = requestedSlug
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final effectivePageTitle =
        pageTitle.isNotEmpty ? pageTitle : fallbackPageTitle;
    final title = configuredTitle.isNotEmpty
        ? configuredTitle
        : storeName.isEmpty
            ? effectivePageTitle
            : '$effectivePageTitle | $storeName';

    final configuredDescription = page?.metaDescription?.trim() ?? '';
    final globalDescription = websiteService
        .getSetting(
          'seo_meta_description',
          websiteService.getSetting(
            'meta_description',
            websiteService.getSetting('store_description', ''),
          ),
        )
        .trim();
    final description = configuredDescription.isNotEmpty
        ? configuredDescription
        : globalDescription.isNotEmpty
            ? globalDescription
            : effectivePageTitle;

    final configuredImage = page?.ogImageUrl?.trim() ?? '';
    final fallbackImage =
        websiteService.getSetting('seo_og_image', '').trim().isNotEmpty
            ? websiteService.getSetting('seo_og_image', '').trim()
            : websiteService.getSetting('logo_url', '').trim();
    // The canonical ERP-mounted flag: an inherited-widget lookup here is
    // reachable from initState and would assert (ModalRoute dependOn). The
    // SEO route derives from the page's own slug under that flag.
    final isErpMounted = PublicStoreRuntimeConfig.isErpMounted;
    final currentUri = Uri(
      path: isErpMounted
          ? '/tienda/pagina/$requestedSlug'
          : '/pagina/$requestedSlug',
    );
    final contactFacts = PublicWebsiteContactFacts(
      phone: websiteService
          .getSetting(
            'seo_phone',
            websiteService.getSetting(
              'contact_phone',
              websiteService.getSetting('business_phone', ''),
            ),
          )
          .trim(),
      email: websiteService
          .getSetting(
            'seo_email',
            websiteService.getSetting('contact_email', ''),
          )
          .trim(),
      address: <String>{
        websiteService
            .getSetting(
              'seo_address_street',
              websiteService.getSetting('contact_address', ''),
            )
            .trim(),
        websiteService
            .getSetting(
              'seo_address_city',
              websiteService.getSetting('seo_address_locality', ''),
            )
            .trim(),
        websiteService.getSetting('seo_address_region', '').trim(),
        websiteService.getSetting('seo_address_postal', '').trim(),
        websiteService.getSetting('seo_address_country', '').trim(),
      }.where((part) => part.isNotEmpty).join(', '),
    );
    final hasEligibleContent = originConfirmed &&
        page != null &&
        hasMeaningfulPublicWebsitePageContent(
          blocks,
          isContactPage: requestedSlug == 'contacto',
          contactFacts: contactFacts,
        );
    final routeProjection = projectStorefrontSeoRoute(
      currentUri,
      isErpMounted: isErpMounted,
      ownerIsPublished: originConfirmed && (page?.isPublished ?? false),
      hasEligibleContent: hasEligibleContent,
    );
    final configuredStoreUrl = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      websiteService.getSetting('store_url', ''),
    );
    final canonicalBase = configuredStoreUrl.isEmpty
        ? null
        : Uri.tryParse(
            configuredStoreUrl.endsWith('/')
                ? configuredStoreUrl
                : '$configuredStoreUrl/',
          );
    final canonicalUrl = canonicalBase
        ?.resolve(routeProjection.canonicalPath)
        .replace(query: null, fragment: null)
        .toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          loadGeneration != _loadGeneration ||
          requestedSlug != widget.slug ||
          !TickerMode.of(context)) {
        return;
      }
      SeoHelper.updateSeo(
        title: title,
        description: description,
        imageUrl: configuredImage.isNotEmpty
            ? configuredImage
            : fallbackImage.isEmpty
                ? null
                : fallbackImage,
        keywords: page?.metaKeywords,
        canonicalUrl: canonicalUrl,
        robots: routeProjection.robots,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Watch edit mode provider for changes
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isInEditorContext = editProvider.isInEditorContext;
    final resolvedTheme = WebsiteResolvedTheme.of(context);

    // Audience guard: editor-provenance content must never render a single
    // frame beyond its authorizing lease. On revoke/suspend the snapshot is
    // invalidated BEFORE painting and the page reloads through the public
    // read; an unpublished public origin then resolves to unavailable.
    final editorContentAuthorized =
        _blocksAudience != WebsitePageContentAudience.editor ||
            (editProvider.isInEditorContext &&
                editProvider.editorEntryLeaseGranted &&
                _blocksLease != null &&
                editProvider.editorEntryLease?.fingerprint ==
                    _blocksLease?.fingerprint &&
                editProvider.editorEntryLease?.authorityEpoch ==
                    _blocksLease?.authorityEpoch);
    if (!editorContentAuthorized) {
      _invalidateEditorContentAndReloadPublic();
      return const FullPageLoading();
    }
    // Desired vs loaded audience. A late lease grant triggers the CENTRAL
    // CMS revalidation signal (emitted by the layout on the lease
    // transition); while the desired editor audience is still pending, the
    // page renders loading and never binds a public snapshot into the editor
    // session.
    final desiredEditorAudience =
        isInEditorContext && editProvider.editorEntryLeaseGranted;
    final audienceSatisfied = desiredEditorAudience
        ? (_blocksAudience == WebsitePageContentAudience.editor &&
            _blocksLease != null &&
            _blocksLease?.fingerprint ==
                editProvider.editorEntryLease?.fingerprint &&
            _blocksLease?.authorityEpoch ==
                editProvider.editorEntryLease?.authorityEpoch)
        : _blocksAudience == WebsitePageContentAudience.public;

    // The FSM route command in the storefront layout already owns the mode;
    // this consumer only binds its page document once blocks are loaded AND
    // the loaded audience matches the session's audience.
    if (audienceSatisfied) {
      _bindEditorDocument(editProvider);
    }

    // Watch website service so page data changes can apply without full reload.
    // Theme values are resolved once by PublicStoreLayout and published via
    // WebsiteResolvedTheme.
    context.watch<WebsiteService>();

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
    final matchesPage = editProvider.ownsPageDocument(
      pageId: _pageId,
      pageSlug: widget.slug,
    );

    final blocksToRender =
        (isInEditorContext && matchesPage) ? editProvider.blocks : _blocks;

    if (_isLoading && _pageId == null) {
      return const FullPageLoading();
    }

    if (_error != null) {
      return _buildErrorView(resolvedTheme);
    }
    if (isInEditorContext && !matchesPage) {
      return const FullPageLoading();
    }

    final mode = editProvider.isEditMode
        ? WebsitePageCompositionMode.edit
        : editProvider.isPreviewMode
            ? WebsitePageCompositionMode.preview
            : WebsitePageCompositionMode.public;
    final logicalWidth = MediaQuery.sizeOf(context).width;
    final composition = WebsitePageComposition.project(
      blocks: blocksToRender,
      mode: mode,
      breakpoint: WebsiteViewport.fromLogicalWidth(logicalWidth).wireName,
      logicalWidth: logicalWidth,
      sectionSpacing: resolvedTheme.sectionSpacing,
    );

    return PageComposition(
      composition: composition,
      primaryColor: resolvedTheme.primaryColor,
      accentColor: resolvedTheme.accentColor,
      textColor: resolvedTheme.textColor,
      containerPadding: resolvedTheme.containerPadding,
      headingFont: resolvedTheme.headingFont,
      bodyFont: resolvedTheme.bodyFont,
      headingSize: resolvedTheme.headingSize,
      bodySize: resolvedTheme.bodySize,
      tenantId: tenantId,
      onNavigate: (route) => PublicStoreLayout.navigateToHref(context, route),
      isNavigationEligible: (href) =>
          PublicStoreLayout.isHrefPubliclyEligible(context, href),
      onAddBlock: (type, {atIndex}) =>
          editProvider.addBlock(type, atIndex: atIndex),
      onSpacingChanged: (blockId, spacing) =>
          editProvider.updateBlockData(blockId, 'spacingAfter', spacing),
      emptyState: _buildEmptyState(
        mode == WebsitePageCompositionMode.edit,
        resolvedTheme,
      ),
    );
  }

  Widget _buildEmptyState(
    bool isEditMode,
    WebsiteResolvedTheme resolvedTheme,
  ) {
    return Container(
      padding: EdgeInsets.all(resolvedTheme.containerPadding),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.web_stories_outlined,
              size: 64,
              color: resolvedTheme.textColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              isEditMode
                  ? 'Esta página no tiene bloques'
                  : 'Esta página está en construcción',
              style: TextStyle(
                fontSize: resolvedTheme.headingSize * 0.5,
                fontFamily: resolvedTheme.headingFont,
                color: resolvedTheme.textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isEditMode
                  ? 'Usa el panel de la derecha para agregar bloques'
                  : 'Vuelve pronto para ver el contenido',
              style: TextStyle(
                fontSize: resolvedTheme.bodySize,
                fontFamily: resolvedTheme.bodyFont,
                color: resolvedTheme.textColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(WebsiteResolvedTheme resolvedTheme) {
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
                color: resolvedTheme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Ha ocurrido un error al cargar la página',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: resolvedTheme.textColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  PublicStoreLayout.navigateToHref(context, '/tienda'),
              icon: const Icon(Icons.home),
              label: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    );
  }
}
