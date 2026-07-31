import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/website_seo_center_models.dart';
import '../services/website_seo_center_service.dart';
import '../models/storefront_publication_status.dart';
import '../services/storefront_publication_service.dart';
import '../services/website_seo_operations_service.dart';
import '../services/website_service.dart';
import '../widgets/seo_center_lists.dart';
import '../widgets/seo_center_scope_rail.dart';
import '../widgets/seo_google_operations_panel.dart';
import '../widgets/storefront_publication_band.dart';
import '../widgets/seo_readiness_badge.dart';
import '../widgets/website_admin_ui.dart';

/// Product class boundary shared with the mobile guide.
const double _kDesktopWidth = 900;

/// Internal composition threshold: below this content width the detail stops
/// being a side pane and replaces the list body, keeping the same contextual
/// back contract used on tablet and phone. It never redefines the three
/// product classes.
const double _kDetailPaneWidth = 1180;

/// Read-only SEO control center.
///
/// This surface owns nothing. It reads the typed projection built by
/// [WebsiteSeoCenterService] from canonical owners and routes to those owners.
/// It deliberately has no form, no save action and no destructive action:
/// every earlier duplicate writer (contact data, canonical URL, Open Graph and
/// Twitter fields without a consumer, decorative schema/GTM switches, the
/// invented Merchant readiness bar, and page deletion) lived here and produced
/// states the deployed site never reflected.
///
/// The three planes stay separate at every level of the UI:
///
/// 1. app eligibility — knowable now, decided by this application;
/// 2. build inclusion — evidence from the last deployed build only;
/// 3. Google — dated evidence only, never a prediction.
///
/// The center owns no editable value, but it is the correct host for the
/// site-wide **Google operations** (connect/reconnect Search Console, submit
/// the sitemap, refresh the Merchant feed). Those are operations, not owner
/// data: they save nothing here and they belong to the whole site, which is
/// why they must not live inside one product's form. Their result is kept as
/// a separate, dated fourth fact and is never folded into the Google evidence
/// plane.
class SeoSettingsPage extends StatefulWidget {
  const SeoSettingsPage({
    super.key,
    this.embedded = false,
    this.loadProjection,
    this.operationsService,
    this.publicationService,
    this.resolvePublicationTenantId,
    this.authorityListenable,
    this.launchExternalUrl,
  });

  final bool embedded;

  /// Injection seam for widget tests. Production uses the canonical
  /// provider-owned services.
  final Future<WebsiteSeoCenterProjection> Function(BuildContext context)?
      loadProjection;

  /// Injection seam for the Google operations. Production builds the real
  /// tenant-scoped client.
  final WebsiteSeoOperationsService? operationsService;

  /// Injection seam for the storefront publication ledger. Production builds
  /// the real tenant-scoped client. The band consumes it read-only.
  final StorefrontPublicationService? publicationService;

  /// Injection seam for the tenant the publication status belongs to, so
  /// widget tests never construct `TenantService` (which reaches
  /// `Supabase.instance`). Production resolves through the shared service.
  final Future<String?> Function()? resolvePublicationTenantId;

  /// Emits whenever the authenticated user or active tenant changes.
  ///
  /// Production binds to the provider-owned [TenantService]. Tests can inject
  /// a notifier alongside [resolvePublicationTenantId] without initializing
  /// Supabase.
  final Listenable? authorityListenable;

  /// Injection seam for opening the Google consent URL.
  final Future<bool> Function(Uri url)? launchExternalUrl;

  @override
  State<SeoSettingsPage> createState() => _SeoSettingsPageState();
}

class _SeoSettingsPageState extends State<SeoSettingsPage> {
  // Created on first real load only. `TenantService` reaches
  // `Supabase.instance` in its constructor, so building it eagerly would tie
  // this widget — and every widget test of it — to an initialized backend.
  TenantService? _tenantService;
  Listenable? _authorityListenable;
  WebsiteSeoCenterService? _service;

  final Map<SeoCenterScope, _ScopeUiState> _scopeStates = {
    for (final scope in SeoCenterScope.values) scope: _ScopeUiState(),
  };

  SeoCenterScope _scope = SeoCenterScope.site;
  WebsiteSeoCenterProjection? _projection;
  WebsiteSeoCenterProjection? _groupCacheProjection;
  final Map<SeoCenterScope, SeoCenterGroup> _groupCache = {};
  bool _isLoading = true;
  bool _evidenceRefreshBusy = false;
  int _projectionGeneration = 0;
  String? _error;

  // --- Google operations state ---------------------------------------------
  late final WebsiteSeoOperationsService _operations =
      widget.operationsService ?? WebsiteSeoOperationsService();
  WebsiteSeoConnectionStatus? _connection;
  SeoGoogleOperation? _runningOperation;
  int _connectionGeneration = 0;
  final Map<SeoGoogleOperation, SeoGoogleOperationOutcome> _operationOutcomes =
      {};

  // --- Storefront publication state ----------------------------------------
  //
  // Loaded independently from the projection: a publication read failure
  // renders as the band's own fail-closed state and never replaces the SEO
  // center. One tenant per round; the generation makes a late answer for a
  // previous round inert.
  late final StorefrontPublicationService _publication =
      widget.publicationService ?? StorefrontPublicationService();
  StorefrontPublicationStatus? _publicationStatus;
  String? _publicationTenantId;
  String? _publicationNotice;
  bool _publicationBusy = false;
  int _publicationGeneration = 0;
  int _authorityGeneration = 0;
  bool _authorityReloadPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadEverything();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindAuthorityListenable();
  }

  @override
  void didUpdateWidget(covariant SeoSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.authorityListenable, widget.authorityListenable) ||
        !identical(oldWidget.resolvePublicationTenantId,
            widget.resolvePublicationTenantId)) {
      _bindAuthorityListenable();
    }
  }

  @override
  void dispose() {
    _authorityListenable?.removeListener(_handleAuthorityChanged);
    for (final state in _scopeStates.values) {
      state.dispose();
    }
    super.dispose();
  }

  _ScopeUiState get _current => _scopeStates[_scope]!;

  void _bindAuthorityListenable() {
    Listenable? next = widget.authorityListenable;
    if (next == null && widget.resolvePublicationTenantId == null) {
      try {
        final providerTenant = context.read<TenantService>();
        _tenantService = providerTenant;
        next = providerTenant;
      } catch (_) {
        // A standalone/test host can exercise the read-only projection without
        // initializing Supabase. The production app always provides the shared
        // TenantService; without that provider there is no authority notifier
        // to bind, and the fail-closed async resolver remains sufficient.
        next = null;
      }
    }
    if (identical(next, _authorityListenable)) return;
    _authorityListenable?.removeListener(_handleAuthorityChanged);
    _authorityListenable = next;
    _authorityListenable?.addListener(_handleAuthorityChanged);
  }

  /// Invalidates every tenant-owned plane before clearing its visible facts.
  ///
  /// A stale response is allowed to finish, but its generation can no longer
  /// apply. One consolidated reload then starts as soon as any command already
  /// in flight releases its lock.
  void _handleAuthorityChanged() {
    if (!mounted) return;
    _authorityGeneration++;
    _projectionGeneration++;
    _connectionGeneration++;
    _publicationGeneration++;
    _authorityReloadPending = true;
    setState(() {
      _projection = null;
      _groupCacheProjection = null;
      _groupCache.clear();
      _error = null;
      _isLoading = true;
      _connection = null;
      _operationOutcomes.clear();
      _publicationStatus = null;
      _publicationTenantId = null;
      _publicationNotice = null;
      _publicationBusy = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainAuthorityReload();
    });
  }

  void _drainAuthorityReload() {
    if (!mounted ||
        !_authorityReloadPending ||
        _evidenceRefreshBusy ||
        _publicationBusy ||
        _runningOperation != null) {
      return;
    }
    _authorityReloadPending = false;
    unawaited(_reloadEverything());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_projectionGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Start the future synchronously so the element is never read after an
      // await inside this method.
      final loader = widget.loadProjection;
      final pending = loader != null ? loader(context) : _loadFromProviders();
      final projection = await pending;
      if (!mounted || generation != _projectionGeneration) return;
      setState(() {
        _projection = projection;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _projectionGeneration) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<WebsiteSeoCenterProjection> _loadFromProviders() async {
    // Resolve every dependency before the first await so the element is never
    // used across an async gap.
    final websiteService = context.read<WebsiteService>();
    final inventoryService = context.read<PublicInventoryService>();
    final tenantService = _tenantService ??= TenantService();
    final service = _service ??= WebsiteSeoCenterService();
    final tenantId = await tenantService.getTenantId();
    if (tenantId == null || tenantId.trim().isEmpty) {
      throw StateError('No se pudo identificar la tienda activa.');
    }
    return service.loadFromServices(
      tenantId: tenantId,
      websiteService: websiteService,
      publicInventoryService: inventoryService,
    );
  }

  void _openHandoff(SeoCenterHandoff handoff) {
    // Non-destructive routing only. The opened surface owns its own return
    // contract, so this never calls `go` and never closes anything itself.
    context.push(handoff.route);
  }

  // ---------------------------------------------------------------------------
  // Google operations
  // ---------------------------------------------------------------------------

  /// The single "Actualizar evidencia" action re-reads every plane — the
  /// projection, the publication conduit and the Google connection — so the
  /// operator never has to guess which button refreshes which fact.
  Future<void> _reloadEverything() async {
    if (_evidenceRefreshBusy || _publicationBusy || _runningOperation != null) {
      return;
    }
    setState(() => _evidenceRefreshBusy = true);
    try {
      await Future.wait([
        _load(),
        _refreshConnection(),
        _loadPublicationStatus(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _evidenceRefreshBusy = false);
        _drainAuthorityReload();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Storefront publication conduit
  // ---------------------------------------------------------------------------

  Future<String?> _resolvePublicationTenantId() async {
    final resolver = widget.resolvePublicationTenantId;
    if (resolver != null) return resolver();
    final tenantService = _tenantService ??= TenantService();
    return tenantService.getTenantId();
  }

  /// Reads the ledger for exactly one tenant per round.
  ///
  /// The generation is captured before the awaits: a slower response from a
  /// previous round — including one for a different tenant — can never
  /// overwrite the state of the current one.
  Future<void> _loadPublicationStatus() async {
    if (_publicationBusy) return;
    final generation = ++_publicationGeneration;
    setState(() {
      _publicationBusy = true;
      _publicationNotice = null;
    });
    String tenantId;
    try {
      try {
        tenantId = (await _resolvePublicationTenantId())?.trim() ?? '';
      } catch (_) {
        // An unresolvable tenant is a failed read, not a crash: the service
        // maps the empty tenant to its own fail-closed status.
        tenantId = '';
      }
      if (!mounted || generation != _publicationGeneration) return;
      final status = await _publication.loadStatus(tenantId);
      if (!mounted || generation != _publicationGeneration) return;
      String activeTenantId;
      try {
        activeTenantId = (await _resolvePublicationTenantId())?.trim() ?? '';
      } catch (_) {
        activeTenantId = '';
      }
      if (!mounted || generation != _publicationGeneration) return;
      if (activeTenantId != tenantId) {
        _handleAuthorityChanged();
        return;
      }
      setState(() {
        _publicationStatus = status;
        _publicationTenantId = tenantId;
      });
    } finally {
      if (mounted && generation == _publicationGeneration) {
        setState(() => _publicationBusy = false);
      }
      _drainAuthorityReload();
    }
  }

  Future<void> _retryPublication() async {
    if (_publicationBusy) return;
    final generation = ++_publicationGeneration;
    setState(() {
      _publicationBusy = true;
      _publicationNotice = null;
    });
    try {
      String tenantId;
      try {
        tenantId = (await _resolvePublicationTenantId())?.trim() ?? '';
      } catch (_) {
        tenantId = '';
      }
      if (!mounted || generation != _publicationGeneration) return;
      if (_publicationTenantId != null && _publicationTenantId != tenantId) {
        final status = await _publication.loadStatus(tenantId);
        if (!mounted || generation != _publicationGeneration) return;
        setState(() {
          _publicationStatus = status;
          _publicationTenantId = tenantId;
          _publicationNotice =
              'La tienda activa cambió. Actualizamos su estado antes de '
              'permitir un reintento.';
        });
        return;
      }
      // The retry targets the recorded failure, never the flat request id,
      // so an unrelated newer request can never be re-dispatched by mistake.
      final result = await _publication.retry(
        tenantId: tenantId,
        failedRequestId: _publicationStatus?.latestFailure?.requestId,
      );
      if (!mounted || generation != _publicationGeneration) return;
      String activeTenantId;
      try {
        activeTenantId = (await _resolvePublicationTenantId())?.trim() ?? '';
      } catch (_) {
        activeTenantId = '';
      }
      if (!mounted || generation != _publicationGeneration) return;
      if (activeTenantId != tenantId) {
        _handleAuthorityChanged();
        return;
      }
      setState(() {
        _publicationStatus = result.status;
        _publicationTenantId = tenantId;
        _publicationNotice = result.message;
      });
    } finally {
      if (mounted && generation == _publicationGeneration) {
        setState(() => _publicationBusy = false);
      }
      _drainAuthorityReload();
    }
  }

  Future<void> _openPublicationRun(Uri url) async {
    if (_publicationBusy) return;
    final authorityGeneration = _authorityGeneration;
    setState(() {
      _publicationBusy = true;
      _publicationNotice = null;
    });
    final launcher = widget.launchExternalUrl ??
        (Uri value) => launchUrl(value, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await launcher(url);
    } catch (_) {
      opened = false;
    } finally {
      if (mounted) {
        setState(() {
          _publicationBusy = false;
          // A late launcher result belongs to the authority that initiated it.
          // Never attach its feedback to a different active shop.
          if (!opened && authorityGeneration == _authorityGeneration) {
            _publicationNotice =
                'No pudimos abrir el run. Inténtalo nuevamente.';
          }
        });
        // An authority change may have queued a consolidated reload while the
        // external launcher owned the publication lock.
        _drainAuthorityReload();
      }
    }
  }

  /// One shared presentation feeds the band and the Sitio attention dot, so
  /// there is exactly one precedence in the product.
  StorefrontPublicationPresentation get _publicationPresentation =>
      StorefrontPublicationPresentation.resolve(
        status: _publicationStatus,
        release: _projection?.siteStatus.artifacts?.release,
      );

  Future<void> _refreshConnection() async {
    final generation = ++_connectionGeneration;
    final status = await _operations.connectionStatus();
    if (!mounted || generation != _connectionGeneration) return;
    setState(() => _connection = status);
  }

  Future<void> _runOperation(SeoGoogleOperation operation) async {
    if (_runningOperation != null) return;
    final authorityGeneration = _authorityGeneration;
    setState(() => _runningOperation = operation);
    try {
      switch (operation) {
        case SeoGoogleOperation.connect:
          await _startConnection(authorityGeneration);
        case SeoGoogleOperation.submitSitemap:
          _recordOutcome(
            operation,
            await _operations.submitSitemap(),
            authorityGeneration: authorityGeneration,
          );
        case SeoGoogleOperation.refreshMerchant:
          _recordOutcome(
            operation,
            await _operations.refreshMerchantFeed(),
            authorityGeneration: authorityGeneration,
          );
      }
    } finally {
      // Keep the site-wide refresh disabled until the operation's own
      // authoritative connection reread finishes. Otherwise an operator can
      // start another read in the small gap after the command but before its
      // evidence has been reconciled.
      if (mounted && authorityGeneration == _authorityGeneration) {
        await _refreshConnection();
      }
      if (mounted) {
        setState(() => _runningOperation = null);
        _drainAuthorityReload();
      }
    }
  }

  Future<void> _startConnection(int authorityGeneration) async {
    final start = await _operations.startConnection();
    if (!mounted || authorityGeneration != _authorityGeneration) return;
    final observedAt = DateTime.now().toUtc();

    if (!start.isReady) {
      _recordOutcome(
        SeoGoogleOperation.connect,
        WebsiteSeoOperationResult.failure(
          observedAt: observedAt,
          message: start.humanMessage,
          blocker: start.blocker,
        ),
        authorityGeneration: authorityGeneration,
      );
      return;
    }

    final launcher = widget.launchExternalUrl ??
        (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await launcher(start.authUrl!);
    } catch (_) {
      opened = false;
    }
    if (!mounted || authorityGeneration != _authorityGeneration) return;

    // Opening the consent screen is not a connection. The operator finishes
    // in Google and this surface only re-reads the server's status.
    _recordOutcome(
      SeoGoogleOperation.connect,
      WebsiteSeoOperationResult(
        succeeded: opened,
        observedAt: observedAt,
        message: opened
            ? 'Se abrió la autorización de Google en el navegador. Al '
                'terminar, vuelve y usa «Actualizar evidencia».'
            : 'No se pudo abrir el navegador para autorizar con Google.',
      ),
      authorityGeneration: authorityGeneration,
    );
  }

  void _recordOutcome(
    SeoGoogleOperation operation,
    WebsiteSeoOperationResult result, {
    required int authorityGeneration,
  }) {
    if (!mounted || authorityGeneration != _authorityGeneration) return;
    setState(() {
      _operationOutcomes[operation] = SeoGoogleOperationOutcome(
        succeeded: result.succeeded,
        observedAt: result.observedAt,
        message: result.humanMessage,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final evidenceBusy = _isLoading ||
        _evidenceRefreshBusy ||
        _publicationBusy ||
        _runningOperation != null;
    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'SEO y visibilidad',
      description:
          'Qué puede indexar Google, qué llegó al último build y qué informó '
          'Google. Esta pantalla solo lee.',
      actions: [
        OutlinedButton.icon(
          onPressed: evidenceBusy ? null : _reloadEverything,
          icon: evidenceBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(evidenceBusy ? 'Consultando…' : 'Actualizar evidencia'),
        ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _projection == null) {
      return const Center(child: BrandedLoading());
    }
    final error = _error;
    if (error != null && _projection == null) {
      return _LoadErrorState(message: error, onRetry: _load);
    }
    final projection = _projection;
    if (projection == null) {
      return const WebsiteAdminEmptyState(
        icon: Icons.travel_explore_outlined,
        title: 'Sin datos',
        description: 'No hay una proyección disponible para esta tienda.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= _kDesktopWidth;
        final showDetailPane = width >= _kDetailPaneWidth;
        final padding = isDesktop
            ? const EdgeInsets.fromLTRB(24, 20, 24, 20)
            : const EdgeInsets.fromLTRB(16, 16, 16, 16);

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EvidenceHeader(projection: projection, compact: !isDesktop),
              const SizedBox(height: 16),
              Expanded(
                child: isDesktop
                    ? _buildDesktop(projection, showDetailPane)
                    : _buildCompact(projection),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktop(
    WebsiteSeoCenterProjection projection,
    bool showDetailPane,
  ) {
    final group = _buildGroup(_scope, projection);
    final selected = _selectedRow(group);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeoCenterScopeRail(
          selected: _scope,
          onSelected: _selectScope,
          counters: _counters(projection),
          attention: _attention(projection),
        ),
        const SizedBox(width: 16),
        if (!showDetailPane && selected != null)
          Expanded(child: _detailSurface(selected, withBack: true))
        else ...[
          Expanded(flex: 3, child: _listSurface(group)),
          if (showDetailPane) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 380,
              child: _WorkspaceSurface(
                child: selected == null
                    ? const SeoCenterDetailPlaceholder()
                    : SeoCenterDetail(
                        row: selected,
                        onHandoff: _openHandoff,
                        scrollController: _current.detailScrollController,
                      ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildCompact(WebsiteSeoCenterProjection projection) {
    final group = _buildGroup(_scope, projection);
    final selected = _selectedRow(group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeoCenterScopeRail(
          selected: _scope,
          onSelected: _selectScope,
          layout: SeoCenterScopeRailLayout.horizontal,
          counters: _counters(projection),
          attention: _attention(projection),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: selected == null
              ? _listSurface(group)
              : _detailSurface(selected, withBack: true),
        ),
      ],
    );
  }

  /// Site-wide operational surfaces belong to the site scope only. Rendering
  /// them in every scope would suggest a product or a page can publish the
  /// store or submit a sitemap.
  ///
  /// The publication band renders first and the Google panel second, as
  /// siblings: Editor → build → deploy is the site's own process state, and
  /// Google remains a separate integration with its own facts.
  Widget? _operationsPanel(SeoCenterGroup group) {
    if (group.scope != SeoCenterScope.site) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StorefrontPublicationBand(
          status: _publicationStatus,
          release: _projection?.siteStatus.artifacts?.release,
          isBusy: _publicationBusy,
          notice: _publicationNotice,
          onRetry: _retryPublication,
          onRefreshStatus: _loadPublicationStatus,
          onOpenRun: _openPublicationRun,
        ),
        const SizedBox(height: 12),
        SeoGoogleOperationsPanel(
          status: _connection,
          isBusy: _runningOperation != null,
          runningOperation: _runningOperation,
          outcomes: _operationOutcomes,
          onRun: _runOperation,
        ),
      ],
    );
  }

  Widget _listSurface(SeoCenterGroup group) {
    return _WorkspaceSurface(
      child: SeoCenterList(
        leading: _operationsPanel(group),
        group: group,
        query: _current.query,
        searchController: _current.searchController,
        onQueryChanged: (value) => setState(() => _current.query = value),
        onlyAttention: _current.onlyAttention,
        onOnlyAttentionChanged: (value) =>
            setState(() => _current.onlyAttention = value),
        onRowSelected: (row) => setState(() => _current.selectedId = row.id),
        onHandoff: _openHandoff,
        selectedRowId: _current.selectedId,
        scrollController: _current.listScrollController,
      ),
    );
  }

  Widget _detailSurface(SeoCenterEntityRow row, {required bool withBack}) {
    return _WorkspaceSurface(
      child: SeoCenterDetail(
        row: row,
        onHandoff: _openHandoff,
        onBack:
            withBack ? () => setState(() => _current.selectedId = null) : null,
        scrollController: _current.detailScrollController,
      ),
    );
  }

  void _selectScope(SeoCenterScope scope) {
    // Each scope keeps its own query, filter, selection and scroll position so
    // a scope round trip never resets the operator's context.
    setState(() => _scope = scope);
  }

  SeoCenterEntityRow? _selectedRow(SeoCenterGroup group) {
    final id = _current.selectedId;
    if (id == null) return null;
    for (final row in group.rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Map<SeoCenterScope, String> _counters(WebsiteSeoCenterProjection p) => {
        SeoCenterScope.pages: '${p.pages.length}',
        SeoCenterScope.products: '${p.products.length}',
        SeoCenterScope.collections: '${p.collections.length}',
      };

  Map<SeoCenterScope, bool> _attention(WebsiteSeoCenterProjection p) => {
        for (final scope in SeoCenterScope.values)
          scope: _buildGroup(scope, p).attentionCount > 0 ||
              // The Sitio dot reuses the band's own presentation verdict —
              // one precedence, never a duplicate.
              (scope == SeoCenterScope.site &&
                  _publicationPresentation.needsAttention),
      };

  // ---------------------------------------------------------------------------
  // Projection -> view model
  // ---------------------------------------------------------------------------

  SeoCenterGroup _buildGroup(
    SeoCenterScope scope,
    WebsiteSeoCenterProjection projection,
  ) {
    if (!identical(_groupCacheProjection, projection)) {
      _groupCacheProjection = projection;
      _groupCache.clear();
    }
    final cached = _groupCache[scope];
    if (cached != null) return cached;

    final partialError = _partialError(projection.siteStatus);
    final group = switch (scope) {
      SeoCenterScope.site => SeoCenterGroup(
          scope: scope,
          summary:
              'Metadatos base del sitio. Cada valor pertenece a Configuración '
              'del sitio; aquí solo se leen y se comprueba su origen.',
          partialError: partialError,
          overview: SeoCenterOverview(
            title: projection.site.label.isEmpty
                ? 'Sitio público'
                : projection.site.label,
            subtitle: projection.site.canonicalPath,
            appEligibility: _eligibilityBadge(projection.site),
            buildInclusion: _buildBadge(projection.site),
            googleIndex: _googleBadge(projection.site),
            handoff: const SeoCenterHandoff(
              label: 'Abrir Configuración del sitio',
              route: '/website/settings?section=seo',
              helper: 'Sitio web > Configuración es el dueño de estos datos.',
            ),
          ),
          rows: _siteMetadataRows(projection.site),
          emptyTitle: 'Sin metadatos',
          emptyDescription: 'La tienda todavía no tiene metadatos base.',
        ),
      SeoCenterScope.pages => SeoCenterGroup(
          scope: scope,
          summary: '${projection.pages.length} páginas del sitio. '
              'Su título y descripción se editan en Estructura > Páginas.',
          counts: _counts(projection.pagesSummary),
          partialError: partialError,
          rows: [
            for (final page in projection.pages)
              _entityRow(
                page,
                handoff: const SeoCenterHandoff(
                  label: 'Abrir en Páginas',
                  route: '/website/pages',
                  helper: 'Estructura > Páginas',
                ),
              ),
          ],
          emptyTitle: 'Sin páginas',
          emptyDescription: 'Todavía no hay páginas registradas.',
        ),
      SeoCenterScope.products => SeoCenterGroup(
          scope: scope,
          summary: '${projection.products.length} productos del catálogo. '
              'Un producto sin texto propio usa el heredado o el generado, '
              'que es un origen válido y no una omisión.',
          counts: _counts(projection.productsSummary),
          partialError: partialError,
          rows: [
            for (final product in projection.products)
              _entityRow(
                product,
                handoff: SeoCenterHandoff(
                  label: 'Abrir producto',
                  route: '/inventory/products/${product.id}/edit',
                  helper: 'Inventario > Producto > pestaña SEO',
                ),
              ),
          ],
          emptyTitle: 'Sin productos',
          emptyDescription: 'El catálogo no tiene productos que proyectar.',
        ),
      SeoCenterScope.collections => SeoCenterGroup(
          scope: scope,
          summary: '${projection.publishedCategoryOwnerCount} de '
              '${projection.categoryOwnerTotal} categorías activas están '
              'publicadas como colecciones, según Catálogo web. Las demás se '
              'listan aquí como inventario interno: no aparecen en el '
              'mega-menú, la navegación pública, el sitemap ni los snapshots '
              'indexables.',
          counts: [
            SeoCenterSummaryCount(
              label: 'publicadas',
              value: '${projection.publishedCategoryOwnerCount}',
              tone: SeoBadgeTone.confirmed,
            ),
            SeoCenterSummaryCount(
              label: 'no publicadas',
              value: '${projection.unpublishedCategoryOwnerCount}',
            ),
            ..._counts(projection.collectionsSummary),
          ],
          partialError: partialError,
          rows: [
            for (final collection in projection.collections)
              _entityRow(
                collection,
                handoff: _isUnpublishedCollection(collection)
                    // An unpublished row must offer the action that resolves
                    // it, not a generic "open the workspace".
                    ? const SeoCenterHandoff(
                        label: 'Publicar en Catálogo web',
                        route: '/website/product-visibility?section=categories',
                        helper: 'Catálogo web > Categorías activa '
                            '«Mostrar en el sitio»',
                      )
                    : const SeoCenterHandoff(
                        label: 'Abrir en Catálogo web',
                        route: '/website/product-visibility?section=categories',
                        helper: 'Catálogo web > Categorías > Presentación',
                      ),
              ),
          ],
          emptyTitle: 'Sin categorías activas',
          emptyDescription: 'El catálogo no tiene categorías que proyectar.',
        ),
    };
    _groupCache[scope] = group;
    return group;
  }

  List<SeoCenterSummaryCount> _counts(WebsiteSeoGroupSummary summary) {
    return [
      SeoCenterSummaryCount(
        label: 'elegibles',
        value: '${summary.appEligible}',
        tone: SeoBadgeTone.confirmed,
      ),
      SeoCenterSummaryCount(
        label: 'no elegibles',
        value: '${summary.appIneligible}',
      ),
    ];
  }

  List<SeoCenterEntityRow> _siteMetadataRows(WebsiteSeoEntityProjection site) {
    final metadata = site.metadata;
    return [
      _metadataRow('title', 'Título base', metadata.title),
      _metadataRow('description', 'Descripción base', metadata.description),
      _metadataRow('image', 'Imagen para compartir', metadata.imageUrl),
      _metadataRow('keywords', 'Palabras clave', metadata.keywords),
    ];
  }

  SeoCenterEntityRow _metadataRow(
    String id,
    String label,
    WebsiteSeoEffectiveValue value,
  ) {
    return SeoCenterEntityRow(
      id: id,
      title: label,
      subtitle: value.isPresent ? value.value : 'Sin valor en ningún origen',
      source: _sourceBadge(value),
      facts: [
        SeoCenterFact(
          label: 'Valor efectivo',
          value: value.isPresent ? value.value : '—',
        ),
        SeoCenterFact(
          label: 'Origen',
          value: _sourceLabel(value.source),
          tone: _sourceTone(value.source),
        ),
      ],
      handoff: const SeoCenterHandoff(
        label: 'Editar en Configuración del sitio',
        route: '/website/settings?section=seo',
        helper: 'Sitio web > Configuración',
      ),
      needsAttention: false,
    );
  }

  SeoCenterEntityRow _entityRow(
    WebsiteSeoEntityProjection entity, {
    required SeoCenterHandoff handoff,
  }) {
    final eligibility = _eligibilityBadge(entity);
    return SeoCenterEntityRow(
      id: entity.id,
      title: entity.label.isEmpty ? 'Sin nombre' : entity.label,
      subtitle: entity.canonicalPath.isEmpty ? null : entity.canonicalPath,
      source: _sourceBadge(entity.metadata.title),
      appEligibility: eligibility,
      buildInclusion: _buildBadge(entity),
      googleIndex: _googleBadge(entity),
      facts: _entityFacts(entity),
      handoff: handoff,
      needsAttention: eligibility.tone == SeoBadgeTone.attention,
    );
  }

  static bool _isUnpublishedCollection(WebsiteSeoEntityProjection entity) =>
      entity.kind == WebsiteSeoEntityKind.collection &&
      entity.appEligibility.blockingIssues.contains(
        WebsiteSeoAppEligibilityIssue.ownerNotPublished,
      );

  List<SeoCenterFact> _entityFacts(WebsiteSeoEntityProjection entity) {
    final metadata = entity.metadata;
    final blocking = entity.appEligibility.blockingIssues;
    final quality = entity.appEligibility.qualityIssues;
    final isUnpublishedCollection = _isUnpublishedCollection(entity);
    // The projection keeps every diagnostic fact, but once the editor owner
    // says a collection is not public, route/content blockers are downstream
    // consequences rather than additional operator actions. Present the
    // primary owner decision only; publishing it will re-evaluate the rest.
    final presentedBlocking = isUnpublishedCollection
        ? const [WebsiteSeoAppEligibilityIssue.ownerNotPublished]
        : blocking;
    return [
      SeoCenterFact(
        // An unpublished category has no live URL. Calling its prospective
        // route "canónica" would imply the page exists.
        label: isUnpublishedCollection ? 'Ruta si se publica' : 'Ruta canónica',
        value: entity.canonicalPath.isEmpty ? '—' : entity.canonicalPath,
      ),
      if (isUnpublishedCollection)
        const SeoCenterFact(
          label: 'Estado público',
          value: 'Categoría interna. No se proyecta al mega-menú, la '
              'navegación pública, el sitemap ni los snapshots indexables '
              'mientras «Mostrar en el sitio» esté desactivado.',
        ),
      SeoCenterFact(
        label: 'Título efectivo',
        value: metadata.title.isPresent ? metadata.title.value : '—',
      ),
      SeoCenterFact(
        label: 'Origen del título',
        value: _sourceLabel(metadata.title.source),
        tone: _sourceTone(metadata.title.source),
      ),
      SeoCenterFact(
        label: 'Descripción efectiva',
        value:
            metadata.description.isPresent ? metadata.description.value : '—',
      ),
      SeoCenterFact(
        label: 'Origen de la descripción',
        value: _sourceLabel(metadata.description.source),
        tone: _sourceTone(metadata.description.source),
      ),
      SeoCenterFact(
        label: 'Origen de la imagen',
        value: _sourceLabel(metadata.imageUrl.source),
        tone: _sourceTone(metadata.imageUrl.source),
      ),
      if (presentedBlocking.isNotEmpty)
        SeoCenterFact(
          label: 'Impide la indexación',
          value: presentedBlocking.map(_issueLabel).join(' · '),
          tone: _blockingTone(presentedBlocking),
        ),
      if (quality.isNotEmpty)
        SeoCenterFact(
          label: 'Observaciones',
          value: quality.map(_issueLabel).join(' · '),
        ),
      if (entity.kind == WebsiteSeoEntityKind.product &&
          metadata.keywords.isPresent)
        SeoCenterFact(
          label: 'Frase de búsqueda aplicada',
          value: metadata.keywords.value,
        ),
    ];
  }

  // --- Plane 1: app eligibility ---------------------------------------------

  SeoBadgeState _eligibilityBadge(WebsiteSeoEntityProjection entity) {
    final evidence = entity.appEligibility;
    if (evidence.isEligible) {
      return const SeoBadgeState(
        label: 'Elegible',
        tone: SeoBadgeTone.confirmed,
      );
    }

    final blocking = evidence.blockingIssues;
    final isUnpublished =
        blocking.contains(WebsiteSeoAppEligibilityIssue.ownerNotPublished);

    if (entity.kind == WebsiteSeoEntityKind.collection && isUnpublished) {
      // Not published is a deliberate owner decision, so it is neutral. It is
      // still stated as a fact with an action, never as a defect.
      return const SeoBadgeState(
        label: 'No publicada',
        tone: SeoBadgeTone.neutral,
        detail: 'Categoría interna: fuera de menús, sitemap y snapshots',
      );
    }

    final isEmptyCollection = entity.kind == WebsiteSeoEntityKind.collection &&
        !isUnpublished &&
        blocking.contains(WebsiteSeoAppEligibilityIssue.noEligibleContent);
    if (isEmptyCollection) {
      // A published collection with no eligible products is silently dropped
      // by the sitemap generator. That contradicts the owner's intent, so it
      // is the one collection state that warns.
      //
      // The `!isUnpublished` guard is load-bearing: without it an unpublished
      // empty category would be labelled "Publicada sin productos elegibles",
      // which is simply false.
      return const SeoBadgeState(
        label: 'No elegible actualmente',
        tone: SeoBadgeTone.attention,
        detail: 'Publicada sin productos elegibles',
      );
    }

    return SeoBadgeState(
      label: 'No elegible',
      tone: _blockingTone(blocking),
      detail: blocking.isEmpty ? null : blocking.map(_issueLabel).join(' · '),
    );
  }

  /// A deliberate owner decision is neutral. Only a state that contradicts the
  /// apparent intent escalates.
  SeoBadgeTone _blockingTone(List<WebsiteSeoAppEligibilityIssue> issues) {
    const deliberate = {
      WebsiteSeoAppEligibilityIssue.ownerNotPublished,
      WebsiteSeoAppEligibilityIssue.indexingDisabled,
      WebsiteSeoAppEligibilityIssue.publicPolicyExcluded,
    };
    final hasUnexpected = issues.any((issue) => !deliberate.contains(issue));
    return hasUnexpected ? SeoBadgeTone.attention : SeoBadgeTone.neutral;
  }

  String _issueLabel(WebsiteSeoAppEligibilityIssue issue) => switch (issue) {
        WebsiteSeoAppEligibilityIssue.ownerNotPublished =>
          'No está publicado en el sitio',
        WebsiteSeoAppEligibilityIssue.indexingDisabled =>
          'Indexación desactivada por el editor',
        WebsiteSeoAppEligibilityIssue.publicPolicyExcluded =>
          'Fuera de las reglas públicas actuales',
        WebsiteSeoAppEligibilityIssue.noEligibleContent =>
          'Sin contenido elegible',
        WebsiteSeoAppEligibilityIssue.missingCanonicalPath =>
          'Sin ruta pública canónica',
        WebsiteSeoAppEligibilityIssue.missingTitle =>
          'Sin título en ningún origen',
        WebsiteSeoAppEligibilityIssue.missingDescription =>
          'Sin descripción en ningún origen',
        WebsiteSeoAppEligibilityIssue.missingImage =>
          'Sin imagen en ningún origen',
      };

  // --- Plane 2: last deployed build -----------------------------------------

  SeoBadgeState _buildBadge(WebsiteSeoEntityProjection entity) {
    final evidence = entity.buildEvidence;
    return switch (evidence.state) {
      WebsiteSeoBuildInclusionState.included => SeoBadgeState(
          label: 'Incluido',
          tone: SeoBadgeTone.confirmed,
          detail: _releaseDetail(evidence),
        ),
      WebsiteSeoBuildInclusionState.excluded => SeoBadgeState(
          label: 'No incluido',
          tone: SeoBadgeTone.attention,
          detail: _releaseDetail(evidence),
        ),
      WebsiteSeoBuildInclusionState.unknown => SeoBadgeState(
          label: 'Sin evidencia de publicación',
          tone: SeoBadgeTone.unknown,
          detail: evidence.error.isNotEmpty
              ? evidence.error
              : 'La evidencia por URL no está disponible',
        ),
    };
  }

  String? _releaseDetail(WebsiteSeoBuildEvidence evidence) {
    final parts = <String>[
      if (evidence.releaseCommit.isNotEmpty)
        'build ${_shortCommit(evidence.releaseCommit)}',
      if (evidence.releaseBuiltAt != null)
        _formatDateTime(evidence.releaseBuiltAt!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // --- Plane 3: Google -------------------------------------------------------

  SeoBadgeState _googleBadge(WebsiteSeoEntityProjection entity) {
    final evidence = entity.googleEvidence;
    final observed = evidence.observedAt;
    final origin = observed == null
        ? null
        : '${_formatDateTime(observed)} · Search Console';

    return switch (evidence.state) {
      WebsiteSeoGoogleIndexState.indexed => SeoBadgeState(
          label: 'Indexado',
          tone: SeoBadgeTone.confirmed,
          detail: origin,
        ),
      WebsiteSeoGoogleIndexState.notIndexed => SeoBadgeState(
          label: 'No indexado',
          tone: SeoBadgeTone.neutral,
          detail: origin,
        ),
      WebsiteSeoGoogleIndexState.unavailable => SeoBadgeState(
          label: evidence.configured == true
              ? 'Error al consultar Google'
              : 'Sin conexión con Google',
          tone: SeoBadgeTone.unknown,
          detail: evidence.error.isNotEmpty
              ? evidence.error
              : 'Search Console no está conectado',
        ),
      WebsiteSeoGoogleIndexState.unknown => SeoBadgeState(
          label: 'Sin consultar',
          tone: SeoBadgeTone.unknown,
          detail: evidence.lastSubmitted == null
              ? null
              : 'Sitemap enviado ${_formatDateTime(evidence.lastSubmitted!)}',
        ),
    };
  }

  // --- Metadata provenance ---------------------------------------------------

  SeoBadgeState _sourceBadge(WebsiteSeoEffectiveValue value) {
    return SeoBadgeState(
      label: _sourceLabel(value.source),
      tone: _sourceTone(value.source),
      detail: switch (value.source) {
        WebsiteSeoValueSource.inherited => 'Del sitio',
        WebsiteSeoValueSource.ownerFallback => 'A partir de sus propios datos',
        WebsiteSeoValueSource.explicit => null,
        WebsiteSeoValueSource.missing => null,
      },
    );
  }

  String _sourceLabel(WebsiteSeoValueSource source) => switch (source) {
        WebsiteSeoValueSource.explicit => 'Propio',
        WebsiteSeoValueSource.ownerFallback => 'Generado',
        WebsiteSeoValueSource.inherited => 'Heredado',
        WebsiteSeoValueSource.missing => 'Sin valor',
      };

  SeoBadgeTone _sourceTone(WebsiteSeoValueSource source) => switch (source) {
        WebsiteSeoValueSource.explicit => SeoBadgeTone.confirmed,
        WebsiteSeoValueSource.ownerFallback => SeoBadgeTone.neutral,
        WebsiteSeoValueSource.inherited => SeoBadgeTone.neutral,
        WebsiteSeoValueSource.missing => SeoBadgeTone.unknown,
      };

  String? _partialError(WebsiteSeoSiteStatus status) {
    if (!status.available) {
      final reason = status.error.trim();
      return 'No se pudo leer la evidencia del sitio publicado'
          '${reason.isEmpty ? '' : ': $reason'}. '
          'La publicación y el estado en Google se muestran como «sin '
          'evidencia»; no se deducen.';
    }

    final warnings = <String>[
      if (status.artifacts?.release.provesPublishedStoreBuild != true)
        'release.json no prueba un build limpio de la tienda',
      if (status.artifacts?.robots.rootDisallowDirectivePresent == true)
        'robots.txt bloquea el sitio completo con Disallow: /',
      if (status.searchConsole?.configured == true &&
          status.searchConsole?.ok == false)
        'Search Console respondió con error'
            '${status.searchConsole!.error.isEmpty ? '' : ': ${status.searchConsole!.error}'}',
    ];
    if (warnings.isEmpty) return null;
    return '${warnings.join('. ')}. Estos estados no se convierten en '
        'evidencia positiva.';
  }
}

/// Per-scope UI state kept by the list owner.
class _ScopeUiState {
  final TextEditingController searchController = TextEditingController();
  final ScrollController listScrollController = ScrollController();
  final ScrollController detailScrollController = ScrollController();
  String query = '';
  bool onlyAttention = false;
  String? selectedId;

  void dispose() {
    searchController.dispose();
    listScrollController.dispose();
    detailScrollController.dispose();
  }
}

/// Bounded white workspace used by the list and the detail.
class _WorkspaceSurface extends StatelessWidget {
  const _WorkspaceSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: child,
    );
  }
}

/// Deploy and Search Console evidence, stated as provenance and never as a
/// readiness score.
///
/// On compact widths the tiles collapse behind a one-line summary. Four
/// stacked tiles would otherwise eat the phone viewport and leave the actual
/// work — the scope list — with almost no room.
class _EvidenceHeader extends StatefulWidget {
  const _EvidenceHeader({
    required this.projection,
    required this.compact,
  });

  final WebsiteSeoCenterProjection projection;
  final bool compact;

  @override
  State<_EvidenceHeader> createState() => _EvidenceHeaderState();
}

class _EvidenceHeaderState extends State<_EvidenceHeader> {
  bool _expanded = false;

  WebsiteSeoCenterProjection get projection => widget.projection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = projection.siteStatus;
    final artifacts = status.artifacts;
    final searchConsole = status.searchConsole;
    final muted = theme.colorScheme.onSurfaceVariant;

    final release = artifacts?.release;
    final sitemap = artifacts?.sitemap;
    final robots = artifacts?.robots;
    final hasPublishedBuild = projection.site.buildEvidence.state ==
        WebsiteSeoBuildInclusionState.included;
    final googleQueryOk =
        searchConsole?.configured == true && searchConsole?.ok == true;

    // Built here rather than with the shared metric strip: these tiles state
    // provenance in three stacked lines (what, the observed value, where it
    // came from) and must never truncate a date into an ambiguous claim.
    final tiles = <_EvidenceTile>[
      _EvidenceTile(
        icon: Icons.rocket_launch_outlined,
        label: 'Último build publicado',
        value: hasPublishedBuild && release?.commit.isNotEmpty == true
            ? _shortCommit(release!.commit)
            : 'Sin build válido',
        provenance: hasPublishedBuild && release?.builtAt != null
            ? _formatDateTime(release!.builtAt!)
            : 'release.json no prueba una publicación',
        hasEvidence: hasPublishedBuild,
      ),
      _EvidenceTile(
        icon: Icons.list_alt_outlined,
        label: 'URLs en el sitemap',
        value: sitemap?.urlEntryCount?.toString() ?? 'Sin evidencia',
        provenance: sitemap?.documentValid == true
            ? 'sitemap.xml legible'
            : 'sitemap.xml no verificado',
        hasEvidence: sitemap?.documentValid == true,
      ),
      _EvidenceTile(
        icon: Icons.policy_outlined,
        label: 'robots.txt',
        value: robots?.rootDisallowDirectivePresent == true
            ? 'Bloquea todo el sitio'
            : robots?.documentValid == true
                ? 'Legible'
                : 'Sin evidencia',
        provenance: robots?.rootDisallowDirectivePresent == true
            ? 'Contiene Disallow: /'
            : robots?.expectedSitemapDeclared == true
                ? 'Declara el sitemap'
                : 'No se pudo comprobar',
        hasEvidence: robots?.expectedSitemapDeclared == true &&
            robots?.rootDisallowDirectivePresent != true,
      ),
      _EvidenceTile(
        icon: Icons.travel_explore_outlined,
        label: 'Search Console',
        value: searchConsole?.configured == true && searchConsole?.ok == false
            ? 'Error al consultar'
            : switch (searchConsole?.configured) {
                true => 'Evidencia disponible',
                false => 'Sin evidencia configurada',
                null => 'Sin consultar',
              },
        provenance: searchConsole?.error.isNotEmpty == true
            ? searchConsole!.error
            : searchConsole?.lastSubmitted != null
                ? 'Sitemap enviado ${_formatDateTime(searchConsole!.lastSubmitted!)}'
                : 'Sin envío registrado',
        hasEvidence: googleQueryOk,
      ),
    ];

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1020
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );

    final disclaimer = Text(
      'Lectura del ${_formatDateTime(projection.generatedAt)}. '
      'Esta pantalla no guarda nada: cada valor se edita en su módulo dueño. '
      'Google decide la indexación; aquí solo se muestra la evidencia que '
      'informó.',
      style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
    );

    if (!widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [grid, const SizedBox(height: 10), disclaimer],
      );
    }

    final summary = hasPublishedBuild && release?.builtAt != null
        ? 'build ${_shortCommit(release!.commit)} · '
            '${_formatDateTime(release.builtAt!)}'
        : 'Sin evidencia del sitio publicado';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.rocket_launch_outlined,
                      size: 17,
                      color:
                          hasPublishedBuild ? theme.colorScheme.primary : muted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Evidencia del sitio publicado',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: muted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [grid, const SizedBox(height: 10), disclaimer],
              ),
            ),
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.provenance,
    required this.hasEvidence,
  });

  final IconData icon;
  final String label;
  final String value;
  final String provenance;
  final bool hasEvidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = hasEvidence
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            provenance,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadErrorState extends StatelessWidget {
  const _LoadErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return WebsiteAdminEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'No se pudo cargar el estado SEO',
      description: message,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Reintentar'),
      ),
    );
  }
}

String _shortCommit(String commit) {
  final clean = commit.trim();
  return clean.length <= 7 ? clean : clean.substring(0, 7);
}

String _formatDateTime(DateTime value) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day ${months[local.month - 1]} ${local.year} · $hour:$minute';
}
