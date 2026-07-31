import '../models/website_editor_capability.dart';
import '../models/website_page_models.dart';
import '../models/website_block_document_sanitizer.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_service.dart';

enum WebsiteSaveSection {
  siteSettings,
  headerSettings,
  footerSettings,
  themeSettings,
  pageSeo,
  navigationUpdates,
  navigationOrder,
  pageBlocks,
  navigationCreates,
}

class WebsiteEditorPageTarget {
  const WebsiteEditorPageTarget({
    required this.storagePageId,
    required this.editorPageId,
    required this.pageSlug,
  });

  /// The concrete database page used by `replace_page_blocks`.
  final String storagePageId;

  /// The editor represents Home with a null page ID.
  final String? editorPageId;
  final String? pageSlug;
}

class WebsiteEditorSaveResult {
  const WebsiteEditorSaveResult({
    required this.pageId,
    required this.pageSlug,
    required this.freshBlocks,
    required this.completedSections,
    required this.appliedToActiveDocument,
  });

  final String? pageId;
  final String? pageSlug;
  final List<Map<String, dynamic>> freshBlocks;
  final Set<WebsiteSaveSection> completedSections;
  final bool appliedToActiveDocument;
}

/// Immutable attempt snapshot captured before the first database operation.
class WebsiteEditorSaveCommand {
  WebsiteEditorSaveCommand._({
    required this.tenantId,
    required this.blocks,
    required this.siteSettings,
    required this.headerSettings,
    required this.footerSettings,
    required this.themeSettings,
    required this.pageSeo,
    required this.navigationLabels,
    required this.navigationLinkTypes,
    required this.navigationLinkValues,
    required this.navigationOpenInNewTab,
    required this.navigationItems,
    required this.navigationCreates,
    required this.navigationDeletes,
    required this.footerSectionOrder,
    required this.footerLinkOrder,
    required this.pageId,
    required this.pageSlug,
    required this.hasPageDraftChanges,
    required this.documentSessionRevision,
    required this.ownerTenantId,
    required this.ownerLeaseFingerprint,
    required this.sessionOwnerTenantId,
    required this.sessionOwnerLeaseFingerprint,
  });

  factory WebsiteEditorSaveCommand.capture({
    required String tenantId,
    required WebsiteEditModeProvider document,
  }) {
    final activePage = document.document;
    return WebsiteEditorSaveCommand._(
      tenantId: tenantId,
      blocks: sanitizeWebsiteBlocksForPersistence(
        activePage.blocks.map(_copyMap),
      ),
      siteSettings: Map<String, String>.from(document.pendingSiteSettings),
      headerSettings: Map<String, String>.from(
        document.pendingHeaderSettings,
      ),
      footerSettings: Map<String, String>.from(
        document.pendingFooterSettings,
      ),
      themeSettings: Map<String, String>.from(
        document.pendingThemeSettings,
      ),
      pageSeo: {
        for (final entry in document.pendingPageSeo.entries)
          entry.key: Map<String, String>.from(entry.value),
      },
      navigationLabels: Map<String, String>.from(
        document.pendingFooterNavLabels,
      ),
      navigationLinkTypes: Map<String, NavLinkType>.from(
        document.pendingFooterNavLinkTypes,
      ),
      navigationLinkValues: Map<String, String?>.from(
        document.pendingFooterNavLinkValues,
      ),
      navigationOpenInNewTab: Map<String, bool>.from(
        document.pendingFooterNavOpenInNewTab,
      ),
      navigationItems: {
        for (final entry in document.pendingFooterNavItems.entries)
          entry.key: _copyNavigation(entry.value),
      },
      navigationCreates: {
        for (final entry in document.pendingFooterNavCreates.entries)
          entry.key: _copyNavigation(entry.value),
      },
      navigationDeletes: Set<String>.from(
        document.pendingFooterNavDeletes,
      ),
      footerSectionOrder: document.pendingFooterSectionOrder == null
          ? null
          : List<String>.from(document.pendingFooterSectionOrder!),
      footerLinkOrder: {
        for (final entry in document.pendingFooterLinkOrder.entries)
          entry.key: List<String>.from(entry.value),
      },
      pageId: activePage.pageId,
      pageSlug: activePage.pageSlug,
      hasPageDraftChanges: document.hasPageDraftChanges,
      documentSessionRevision: activePage.sessionRevision,
      ownerTenantId: activePage.ownerTenantId,
      ownerLeaseFingerprint: activePage.ownerLeaseFingerprint,
      sessionOwnerTenantId: document.sessionOwnerTenantId,
      sessionOwnerLeaseFingerprint: document.sessionOwnerLeaseFingerprint,
    );
  }

  final String tenantId;
  final List<Map<String, dynamic>> blocks;
  final Map<String, String> siteSettings;
  final Map<String, String> headerSettings;
  final Map<String, String> footerSettings;
  final Map<String, String> themeSettings;
  final Map<String, Map<String, String>> pageSeo;
  final Map<String, String> navigationLabels;
  final Map<String, NavLinkType> navigationLinkTypes;
  final Map<String, String?> navigationLinkValues;
  final Map<String, bool> navigationOpenInNewTab;
  final Map<String, WebsiteNavigation> navigationItems;
  final Map<String, WebsiteNavigation> navigationCreates;
  final Set<String> navigationDeletes;
  final List<String>? footerSectionOrder;
  final Map<String, List<String>> footerLinkOrder;
  final String? pageId;
  final String? pageSlug;
  final bool hasPageDraftChanges;
  final int documentSessionRevision;

  /// Typed owner captured with the document snapshot: the saved command is
  /// self-contained evidence of who authorized it.
  final String? ownerTenantId;
  final String? ownerLeaseFingerprint;

  /// Typed owner of the editor SESSION (stamped at the granted entry).
  /// Sitewide/SEO-only saves from documentless routes attribute to it.
  final String? sessionOwnerTenantId;
  final String? sessionOwnerLeaseFingerprint;
}

abstract class WebsiteSaveGateway {
  bool isTenantProjectionActive(String tenantId);

  /// Installed by the coordinator for the duration of ONE save command and
  /// invoked immediately before EVERY internal mutable request of a
  /// composite operation (after any preceding read). Throws when the
  /// saving authority is no longer current.
  abstract void Function()? writeGuard;

  /// Records a server-classified authority rejection observed during a
  /// WRITE for [tenantId] on the same durable denial latch the read path
  /// uses.
  void recordEditorAuthorityRejection(String tenantId);

  /// Monotonic auth-identity token (see WebsiteService.identityEpoch): the
  /// coordinator captures it with the command and refuses any mutable
  /// operation or acknowledgement once it moves.
  int get identityEpoch;

  /// The SERVICE's current typed capability for [tenantId] (null while
  /// unknown). The provider can lag one build behind an auth event, so the
  /// coordinator requires THIS truth — fingerprint AND authorityEpoch — to
  /// match the command's session owner before any write.
  WebsiteEditorCapabilitySnapshot? currentCapability(String tenantId);

  Future<void> saveSettings(
    String tenantId,
    Map<String, String> settings,
  );

  Future<void> savePageSeo({
    required String tenantId,
    required String routeKey,
    required Map<String, String> values,
  });

  Future<WebsiteEditorPageTarget> resolvePage({
    required String tenantId,
    required String? pageId,
    required String? pageSlug,
  });

  Future<List<Map<String, dynamic>>> replacePageBlocks({
    required String tenantId,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
  });

  Future<WebsiteNavigation?> getNavigation({
    required String tenantId,
    required String navigationId,
  });

  Future<void> updateNavigation({
    required String tenantId,
    required WebsiteNavigation navigation,
  });

  Future<void> deleteNavigation({
    required String tenantId,
    required String navigationId,
  });

  Future<void> upsertNavigationCreate({
    required String tenantId,
    required String persistedId,
    required WebsiteNavigation navigation,
  });

  Future<void> reorderNavigation({
    required String tenantId,
    required List<String> orderedIds,
  });
}

class WebsiteServiceSaveGateway implements WebsiteSaveGateway {
  WebsiteServiceSaveGateway(this._service);

  final WebsiteService _service;

  @override
  void Function()? writeGuard;

  @override
  void recordEditorAuthorityRejection(String tenantId) {
    _service.recordEditorAuthorityRejectionForTenant(tenantId);
  }

  @override
  bool isTenantProjectionActive(String tenantId) {
    return _service.isTenantProjectionActive(tenantId);
  }

  @override
  int get identityEpoch => _service.identityEpoch;

  @override
  WebsiteEditorCapabilitySnapshot? currentCapability(String tenantId) =>
      _service.editorCapabilitySync(tenantId);

  @override
  Future<void> saveSettings(
    String tenantId,
    Map<String, String> settings,
  ) {
    return _service.saveSettingsForTenant(
      tenantId,
      settings,
      writeGuard: writeGuard,
    );
  }

  @override
  Future<void> savePageSeo({
    required String tenantId,
    required String routeKey,
    required Map<String, String> values,
  }) async {
    final normalizedRoute = routeKey.trim();
    if (normalizedRoute.isEmpty) return;
    final metaTitle = values['meta_title'] ?? '';
    final metaDescription = values['meta_description'] ?? '';

    if (normalizedRoute == 'inicio') {
      await _service.saveSettingsForTenant(
        tenantId,
        {
          'seo_meta_title': metaTitle,
          'seo_meta_description': metaDescription,
          'meta_title': metaTitle,
          'meta_description': metaDescription,
        },
        writeGuard: writeGuard,
      );
    }

    final existing = await _service.getPageBySlug(
      normalizedRoute,
      tenantId: tenantId,
      rethrowErrors: true,
    );
    if (existing != null) {
      // Re-validate AFTER the read and before the page write.
      writeGuard?.call();
      await _service.updatePage(
        existing.copyWith(
          metaTitle: metaTitle,
          metaDescription: metaDescription,
        ),
        writeGuard: writeGuard,
      );
      return;
    }

    await _service.saveSettingsForTenant(
      tenantId,
      {
        'seo_${normalizedRoute}_title': metaTitle,
        'seo_${normalizedRoute}_description': metaDescription,
      },
      writeGuard: writeGuard,
    );
  }

  @override
  Future<WebsiteEditorPageTarget> resolvePage({
    required String tenantId,
    required String? pageId,
    required String? pageSlug,
  }) async {
    final normalizedPageId = pageId?.trim() ?? '';
    final normalizedSlug = pageSlug?.trim() ?? '';

    if (normalizedPageId.isNotEmpty) {
      final page = await _service.getPageByIdForTenant(
        normalizedPageId,
        tenantId,
        rethrowErrors: true,
      );
      if (page == null) {
        throw StateError('La página del editor no pertenece al tenant activo.');
      }
      return WebsiteEditorPageTarget(
        storagePageId: page.id,
        editorPageId: page.id,
        pageSlug: normalizedSlug.isEmpty ? page.slug : normalizedSlug,
      );
    }

    final isHome =
        normalizedSlug.isEmpty || normalizedSlug.toLowerCase() == 'home';
    if (isHome) {
      final homePage = await _service.getHomePageForTenant(
        tenantId,
        rethrowErrors: true,
      );
      if (homePage == null) {
        throw StateError(
          'La página de inicio no existe; créala antes de guardar bloques.',
        );
      }
      return WebsiteEditorPageTarget(
        storagePageId: homePage.id,
        editorPageId: null,
        pageSlug: pageSlug,
      );
    }

    final existing = await _service.getPageBySlug(
      normalizedSlug,
      tenantId: tenantId,
      rethrowErrors: true,
    );
    if (existing == null) {
      throw StateError(
        'La página "$normalizedSlug" no existe; créala antes de guardar.',
      );
    }
    return WebsiteEditorPageTarget(
      storagePageId: existing.id,
      editorPageId: existing.id,
      pageSlug: normalizedSlug,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> replacePageBlocks({
    required String tenantId,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
  }) {
    return _service.replacePageBlocks(
      tenantId: tenantId,
      pageId: pageId,
      blocks: blocks,
      writeGuard: writeGuard,
    );
  }

  @override
  Future<WebsiteNavigation?> getNavigation({
    required String tenantId,
    required String navigationId,
  }) {
    return _service.getNavigationByIdForTenant(navigationId, tenantId);
  }

  @override
  Future<void> updateNavigation({
    required String tenantId,
    required WebsiteNavigation navigation,
  }) async {
    await _service.updateNavigationForTenant(
      navigation,
      tenantId,
      writeGuard: writeGuard,
    );
  }

  @override
  Future<void> deleteNavigation({
    required String tenantId,
    required String navigationId,
  }) {
    return _service.deleteNavigationForTenant(
      navigationId,
      tenantId,
      writeGuard: writeGuard,
    );
  }

  @override
  Future<void> upsertNavigationCreate({
    required String tenantId,
    required String persistedId,
    required WebsiteNavigation navigation,
  }) async {
    await _service.upsertNavigationForTenant(
      tenantId: tenantId,
      persistedId: persistedId,
      navigation: navigation,
      writeGuard: writeGuard,
    );
  }

  @override
  Future<void> reorderNavigation({
    required String tenantId,
    required List<String> orderedIds,
  }) {
    return _service.reorderNavigationIdsForTenant(
      tenantId,
      orderedIds,
      writeGuard: writeGuard,
    );
  }
}

/// Single owner of the Website Builder save protocol.
///
/// Idempotent families are confirmed first. Page blocks are then replaced by
/// one transactional RPC. Navigation creates run last with UUIDs derived from
/// their durable draft IDs, making a retry converge on the same rows.
class WebsiteSaveCoordinator {
  WebsiteSaveCoordinator(this._gateway);

  factory WebsiteSaveCoordinator.forService(WebsiteService service) {
    return WebsiteSaveCoordinator(WebsiteServiceSaveGateway(service));
  }

  final WebsiteSaveGateway _gateway;
  _WebsiteSaveOperation? _inFlight;

  Future<WebsiteEditorSaveResult> save({
    required String tenantId,
    required WebsiteEditModeProvider document,
  }) {
    final command = WebsiteEditorSaveCommand.capture(
      tenantId: tenantId,
      document: document,
    );
    final scope = _WebsiteSaveScope.fromCommand(command, document);
    final active = _inFlight;
    if (active != null) {
      if (active.scope == scope) return active.future;
      return Future<WebsiteEditorSaveResult>.error(
        StateError(
          'Ya hay otro documento del Website Builder guardándose. '
          'Espera a que termine y vuelve a guardar.',
        ),
      );
    }

    final operation = _execute(command, document);
    final tracked = _WebsiteSaveOperation(scope, operation);
    _inFlight = tracked;
    void clearInFlight() {
      if (identical(_inFlight, tracked)) _inFlight = null;
    }

    operation.then<void>(
      (_) => clearInFlight(),
      onError: (Object _, StackTrace __) => clearInFlight(),
    );
    return operation;
  }

  Future<WebsiteEditorSaveResult> _execute(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
  ) async {
    _validate(command);
    _validateDocumentAuthority(command, document);
    final commandEpoch = _gateway.identityEpoch;
    _gateway.writeGuard =
        () => _requireCurrentAuthority(command, document, commandEpoch);
    try {
      return await _executeGuardedOperations(
        command,
        document,
        commandEpoch,
      );
    } catch (error) {
      // ANY late failure — network, 5xx, malformed, a read inside
      // resolvePage/getNavigation/SEO — that lands after an identity change
      // is SUPERSEDED first: zero error publication, acknowledgement or
      // revocation may touch the NEW session.
      if (error is! WebsiteEditorWriteSupersededException &&
          !_authorityStillCurrent(command, document, commandEpoch)) {
        throw WebsiteEditorWriteSupersededException(
          'El guardado pertenece a una identidad anterior.',
          cause: error,
        );
      }
      if (WebsiteService.isEditorAuthorityRejection(error)) {
        if (_authorityStillCurrent(command, document, commandEpoch)) {
          // The CURRENT command was rejected by the server: latch the
          // durable denial and revoke the provider exactly once. The single
          // CMS signal is emitted by the layout when it adopts the denied
          // capability — never a second one from here.
          _gateway.recordEditorAuthorityRejection(command.tenantId);
          document.revokeEditorEntryLease();
          throw WebsiteEditorAuthorityException(
            'El servidor rechazó la autorización al guardar.',
            cause: error,
          );
        }
        // Superseded write: typed outcome only — no latch, no revoke, no
        // signal, and the NEW session stays untouched.
        throw WebsiteEditorWriteSupersededException(
          'El guardado pertenece a una identidad anterior.',
          cause: error,
        );
      }
      rethrow;
    } finally {
      _gateway.writeGuard = null;
    }
  }

  Future<WebsiteEditorSaveResult> _executeGuardedOperations(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
    int commandEpoch,
  ) async {
    final completed = <WebsiteSaveSection>{};
    _requireCurrentAuthority(command, document, commandEpoch);
    final target = command.hasPageDraftChanges
        ? await _gateway.resolvePage(
            tenantId: command.tenantId,
            pageId: command.pageId,
            pageSlug: command.pageSlug,
          )
        : null;

    if (command.siteSettings.isNotEmpty) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.saveSettings(command.tenantId, command.siteSettings);
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedSiteSettings(command.siteSettings);
      }
      completed.add(WebsiteSaveSection.siteSettings);
    }
    if (command.headerSettings.isNotEmpty) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.saveSettings(command.tenantId, command.headerSettings);
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedHeaderSettings(command.headerSettings);
      }
      completed.add(WebsiteSaveSection.headerSettings);
    }
    if (command.footerSettings.isNotEmpty) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.saveSettings(command.tenantId, command.footerSettings);
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedFooterSettings(command.footerSettings);
      }
      completed.add(WebsiteSaveSection.footerSettings);
    }
    if (command.themeSettings.isNotEmpty) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.saveSettings(command.tenantId, command.themeSettings);
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedThemeSettings(command.themeSettings);
      }
      completed.add(WebsiteSaveSection.themeSettings);
    }

    for (final entry in command.pageSeo.entries) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.savePageSeo(
        tenantId: command.tenantId,
        routeKey: entry.key,
        values: entry.value,
      );
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedPageSeo({entry.key: entry.value});
      }
      completed.add(WebsiteSaveSection.pageSeo);
    }

    for (final navigationId in command.navigationDeletes) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.deleteNavigation(
        tenantId: command.tenantId,
        navigationId: navigationId,
      );
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedNavigationDeletes({navigationId});
      }
    }
    await _saveExistingNavigationUpdates(
      command,
      document: document,
      commandEpoch: commandEpoch,
      deferredUntilCreates: false,
      resolvedDraftIds: const {},
    );
    var freshBlocks = command.blocks;
    if (target != null) {
      _requireCurrentAuthority(command, document, commandEpoch);
      freshBlocks = await _gateway.replacePageBlocks(
        tenantId: command.tenantId,
        pageId: target.storagePageId,
        blocks: command.blocks,
      );
      if (_matchesCapturedDocument(command, document) &&
          _authorityStillCurrent(command, document, commandEpoch)) {
        document.acknowledgeSavedPageContext(
          pageId: target.editorPageId,
          pageSlug: target.pageSlug,
        );
        document.acknowledgeSavedBlocks(
          attemptedBlocks: command.blocks,
          freshBlocks: freshBlocks,
        );
      }
      completed.add(WebsiteSaveSection.pageBlocks);
    }

    final resolvedDraftIds = {
      for (final draftId in command.navigationCreates.keys)
        draftId: _persistedNavigationId(draftId),
    };
    await _saveNavigationCreates(
      command,
      document,
      commandEpoch,
      resolvedDraftIds,
    );
    await _saveExistingNavigationUpdates(
      command,
      document: document,
      commandEpoch: commandEpoch,
      deferredUntilCreates: true,
      resolvedDraftIds: resolvedDraftIds,
    );

    final sectionOrder = command.footerSectionOrder;
    if (sectionOrder != null && sectionOrder.isNotEmpty) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.reorderNavigation(
        tenantId: command.tenantId,
        orderedIds: sectionOrder
            .map((id) => resolvedDraftIds[id] ?? id)
            .toList(growable: false),
      );
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedFooterSectionOrder(sectionOrder);
      }
      completed.add(WebsiteSaveSection.navigationOrder);
    }
    for (final entry in command.footerLinkOrder.entries) {
      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.reorderNavigation(
        tenantId: command.tenantId,
        orderedIds: entry.value
            .map((id) => resolvedDraftIds[id] ?? id)
            .toList(growable: false),
      );
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedFooterLinkOrder(entry.key, entry.value);
      }
      completed.add(WebsiteSaveSection.navigationOrder);
    }

    final hasNavigationSection = command.navigationLabels.isNotEmpty ||
        command.navigationLinkTypes.isNotEmpty ||
        command.navigationLinkValues.isNotEmpty ||
        command.navigationOpenInNewTab.isNotEmpty ||
        command.navigationItems.isNotEmpty ||
        command.navigationCreates.isNotEmpty ||
        command.navigationDeletes.isNotEmpty ||
        command.footerSectionOrder != null ||
        command.footerLinkOrder.isNotEmpty;
    if (hasNavigationSection &&
        _canAcknowledge(command, document, commandEpoch)) {
      document.acknowledgeSavedFooterChanges(
        footerSettings: const {},
        sectionOrder: command.footerSectionOrder,
        linkOrder: command.footerLinkOrder,
        navigationLabels: command.navigationLabels,
        navigationLinkTypes: command.navigationLinkTypes,
        navigationLinkValues: command.navigationLinkValues,
        navigationOpenInNewTab: command.navigationOpenInNewTab,
        navigationItems: command.navigationItems,
        navigationCreates: command.navigationCreates,
        navigationDeletes: command.navigationDeletes,
      );
    }
    if (hasNavigationSection) {
      if (command.navigationDeletes.isNotEmpty ||
          _existingNavigationIds(command).isNotEmpty) {
        completed.add(WebsiteSaveSection.navigationUpdates);
      }
      if (command.navigationCreates.isNotEmpty) {
        completed.add(WebsiteSaveSection.navigationCreates);
      }
    }

    return WebsiteEditorSaveResult(
      pageId: target?.editorPageId ?? command.pageId,
      pageSlug: target?.pageSlug ?? command.pageSlug,
      freshBlocks: freshBlocks,
      completedSections: Set.unmodifiable(completed),
      appliedToActiveDocument: _matchesCapturedDocument(command, document) &&
          _authorityStillCurrent(command, document, commandEpoch),
    );
  }

  /// The document must carry a typed owner, and that owner must match BOTH
  /// the current granted lease and the tenant this save targets. Runs before
  /// the FIRST gateway operation, so an identity or tenant switch during the
  /// editing session can never produce a single write: a draft authored
  /// under identity/tenant A never travels into B.
  void _validateDocumentAuthority(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
  ) {
    final lease = document.editorEntryLease;
    final sessionFingerprint = command.sessionOwnerLeaseFingerprint;
    if (lease == null ||
        !lease.granted ||
        sessionFingerprint == null ||
        sessionFingerprint != lease.fingerprint ||
        command.sessionOwnerTenantId != command.tenantId ||
        lease.storefrontTenantId != command.tenantId ||
        // The SERVICE truth must agree — fingerprint AND epoch: a provider
        // still holding A while the service is already B (same tenant, or
        // A→B→A with a recycled fingerprint) writes nothing.
        _gateway.currentCapability(command.tenantId)?.fingerprint !=
            sessionFingerprint ||
        _gateway.currentCapability(command.tenantId)?.authorityEpoch !=
            lease.authorityEpoch) {
      throw const WebsiteEditorAuthorityException(
        'La sesión del editor no está autorizada para este tenant.',
      );
    }
    if (command.hasPageDraftChanges) {
      // Page blocks additionally require the BOUND document owner: an
      // ownerless page draft can never reach the gateway.
      final ownerFingerprint = command.ownerLeaseFingerprint;
      if (ownerFingerprint == null ||
          ownerFingerprint != lease.fingerprint ||
          command.ownerTenantId != command.tenantId) {
        throw const WebsiteEditorAuthorityException(
          'El documento no está autorizado para guardar en este tenant.',
        );
      }
    }
  }

  /// Re-validates CURRENT authority; called before EVERY mutable gateway
  /// operation (and therefore after every await), so an identity switch —
  /// even to another grant on the SAME tenant — aborts all later writes.
  /// Acknowledged sections stay: they were confirmed by the gateway.
  void _requireCurrentAuthority(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
    int commandEpoch,
  ) {
    if (!_authorityStillCurrent(command, document, commandEpoch)) {
      // A mid-save identity change makes THIS command obsolete: typed
      // superseded outcome — no denial latch, no revocation, and the new
      // session is never touched. (A rejection of the still-current command
      // is classified separately from the server error.)
      throw const WebsiteEditorWriteSupersededException(
        'La autoridad del editor cambió durante el guardado.',
      );
    }
  }

  /// The provider can lag one build behind an auth event, so BOTH the
  /// gateway identity epoch and the lease fingerprint must still be the
  /// command's own.
  bool _authorityStillCurrent(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
    int commandEpoch,
  ) {
    final lease = document.editorEntryLease;
    final serviceTruth = _gateway.currentCapability(command.tenantId);
    return _gateway.identityEpoch == commandEpoch &&
        serviceTruth != null &&
        serviceTruth.fingerprint == command.sessionOwnerLeaseFingerprint &&
        lease != null &&
        lease.granted &&
        serviceTruth.authorityEpoch == lease.authorityEpoch &&
        lease.fingerprint == command.sessionOwnerLeaseFingerprint &&
        lease.storefrontTenantId == command.tenantId;
  }

  /// Acknowledgements clear PROVIDER drafts: after identity churn (even
  /// A -> B on the SAME tenant) the drafts belong to B and A's completed
  /// operation must not touch them.
  bool _canAcknowledge(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
    int commandEpoch,
  ) {
    return _gateway.isTenantProjectionActive(command.tenantId) &&
        _authorityStillCurrent(command, document, commandEpoch);
  }

  bool _matchesCapturedDocument(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
  ) {
    return _gateway.isTenantProjectionActive(command.tenantId) &&
        document.documentSessionRevision == command.documentSessionRevision &&
        document.currentPageId == command.pageId &&
        _normalizedPageSlug(document.currentPageSlug) ==
            _normalizedPageSlug(command.pageSlug);
  }

  Future<void> _saveExistingNavigationUpdates(
    WebsiteEditorSaveCommand command, {
    required WebsiteEditModeProvider document,
    required int commandEpoch,
    required bool deferredUntilCreates,
    required Map<String, String> resolvedDraftIds,
  }) async {
    final navigationIds = _existingNavigationIds(command).toList()..sort();
    for (final navigationId in navigationIds) {
      final staged = command.navigationItems[navigationId];
      final parentId = staged?.parentId;
      final dependsOnCreate =
          parentId != null && command.navigationCreates.containsKey(parentId);
      if (dependsOnCreate != deferredUntilCreates) continue;

      _requireCurrentAuthority(command, document, commandEpoch);
      final existing = await _gateway.getNavigation(
        tenantId: command.tenantId,
        navigationId: navigationId,
      );
      if (existing == null) {
        throw StateError(
          'No existe la navegación $navigationId en el tenant activo.',
        );
      }

      _requireCurrentAuthority(command, document, commandEpoch);
      await _gateway.updateNavigation(
        tenantId: command.tenantId,
        navigation: _applyNavigationDraft(
          command,
          draftId: navigationId,
          base: staged ?? existing,
          persistedId: existing.id,
          persistedParentId: parentId == null
              ? null
              : (resolvedDraftIds[parentId] ?? parentId),
          createdAt: existing.createdAt,
          linkedPage: existing.linkedPage,
          children: existing.children,
        ),
      );
      if (_canAcknowledge(command, document, commandEpoch)) {
        document.acknowledgeSavedNavigationUpdate(
          navigationId: navigationId,
          navigationLabels: command.navigationLabels,
          navigationLinkTypes: command.navigationLinkTypes,
          navigationLinkValues: command.navigationLinkValues,
          navigationOpenInNewTab: command.navigationOpenInNewTab,
          navigationItems: command.navigationItems,
        );
      }
    }
  }

  Future<void> _saveNavigationCreates(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
    int commandEpoch,
    Map<String, String> resolvedDraftIds,
  ) async {
    final remaining =
        Map<String, WebsiteNavigation>.from(command.navigationCreates);
    while (remaining.isNotEmpty) {
      var savedAny = false;
      for (final entry in remaining.entries.toList(growable: false)) {
        final draftId = entry.key;
        final staged = command.navigationItems[draftId] ?? entry.value;
        final parentId = staged.parentId;
        if (parentId != null &&
            command.navigationCreates.containsKey(parentId) &&
            remaining.containsKey(parentId)) {
          continue;
        }

        final persistedId = resolvedDraftIds[draftId]!;
        final persistedParentId =
            parentId == null ? null : (resolvedDraftIds[parentId] ?? parentId);
        final navigation = _applyNavigationDraft(
          command,
          draftId: draftId,
          base: staged,
          persistedId: persistedId,
          persistedParentId: persistedParentId,
          createdAt: staged.createdAt,
          linkedPage: staged.linkedPage,
          children: staged.children,
        );
        final existing = await _gateway.getNavigation(
          tenantId: command.tenantId,
          navigationId: persistedId,
        );
        if (existing != null &&
            !_navigationMatchesIdempotentRetry(existing, navigation)) {
          throw StateError(
            'El UUID del borrador ya pertenece a otra navegación.',
          );
        }
        _requireCurrentAuthority(command, document, commandEpoch);
        await _gateway.upsertNavigationCreate(
          tenantId: command.tenantId,
          persistedId: persistedId,
          navigation: navigation,
        );
        remaining.remove(draftId);
        savedAny = true;
      }
      if (!savedAny) {
        throw StateError(
          'No se pudo resolver la jerarquía de navegación pendiente.',
        );
      }
    }
  }

  bool _navigationMatchesIdempotentRetry(
    WebsiteNavigation existing,
    WebsiteNavigation attempted,
  ) {
    String? normalizedLinkValue(WebsiteNavigation navigation) {
      final raw = navigation.linkValue?.trim();
      if (navigation.linkType == NavLinkType.page &&
          raw != null &&
          raw.isNotEmpty &&
          !raw.startsWith('/') &&
          !raw.contains('-')) {
        return '/$raw';
      }
      return navigation.linkValue;
    }

    return existing.id == attempted.id &&
        existing.tenantId == attempted.tenantId &&
        existing.menuLocation == attempted.menuLocation &&
        existing.label == attempted.label &&
        existing.icon == attempted.icon &&
        existing.linkType == attempted.linkType &&
        normalizedLinkValue(existing) == normalizedLinkValue(attempted) &&
        existing.openInNewTab == attempted.openInNewTab &&
        existing.parentId == attempted.parentId &&
        existing.orderIndex == attempted.orderIndex &&
        existing.isVisible == attempted.isVisible &&
        existing.showOnDesktop == attempted.showOnDesktop &&
        existing.showOnMobile == attempted.showOnMobile &&
        existing.cssClass == attempted.cssClass &&
        existing.highlight == attempted.highlight;
  }

  WebsiteNavigation _applyNavigationDraft(
    WebsiteEditorSaveCommand command, {
    required String draftId,
    required WebsiteNavigation base,
    required String persistedId,
    required String? persistedParentId,
    required DateTime createdAt,
    required WebsitePage? linkedPage,
    required List<WebsiteNavigation> children,
  }) {
    final hasLinkValue = command.navigationLinkValues.containsKey(draftId);
    return WebsiteNavigation(
      id: persistedId,
      tenantId: command.tenantId,
      menuLocation: base.menuLocation,
      label: command.navigationLabels[draftId] ?? base.label,
      icon: base.icon,
      linkType: command.navigationLinkTypes[draftId] ?? base.linkType,
      linkValue:
          hasLinkValue ? command.navigationLinkValues[draftId] : base.linkValue,
      openInNewTab:
          command.navigationOpenInNewTab[draftId] ?? base.openInNewTab,
      parentId: persistedParentId,
      orderIndex: base.orderIndex,
      isVisible: base.isVisible,
      showOnDesktop: base.showOnDesktop,
      showOnMobile: base.showOnMobile,
      cssClass: base.cssClass,
      highlight: base.highlight,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      children: children,
      linkedPage: linkedPage,
    );
  }

  Set<String> _existingNavigationIds(WebsiteEditorSaveCommand command) {
    return <String>{
      ...command.navigationLabels.keys,
      ...command.navigationLinkTypes.keys,
      ...command.navigationLinkValues.keys,
      ...command.navigationOpenInNewTab.keys,
      ...command.navigationItems.keys,
    }..removeWhere(
        (id) =>
            command.navigationCreates.containsKey(id) ||
            command.navigationDeletes.contains(id),
      );
  }

  void _validate(WebsiteEditorSaveCommand command) {
    if (command.tenantId.trim().isEmpty) {
      throw StateError('El tenant del guardado es obligatorio.');
    }

    final persistedIds = <String>{};
    for (final draftId in command.navigationCreates.keys) {
      final persistedId = _persistedNavigationId(draftId);
      if (!persistedIds.add(persistedId)) {
        throw StateError(
          'Dos borradores de navegación comparten el mismo UUID persistente.',
        );
      }
    }

    for (final draftId in command.navigationCreates.keys) {
      final visited = <String>{draftId};
      var parentId = command.navigationCreates[draftId]?.parentId;
      while (
          parentId != null && command.navigationCreates.containsKey(parentId)) {
        if (!visited.add(parentId)) {
          throw StateError(
            'La navegación pendiente contiene una jerarquía circular.',
          );
        }
        parentId = command.navigationCreates[parentId]?.parentId;
      }
    }
  }
}

class _WebsiteSaveOperation {
  const _WebsiteSaveOperation(this.scope, this.future);

  final _WebsiteSaveScope scope;
  final Future<WebsiteEditorSaveResult> future;
}

class _WebsiteSaveScope {
  const _WebsiteSaveScope({
    required this.tenantId,
    required this.document,
    required this.documentSessionRevision,
    required this.pageId,
    required this.pageSlug,
  });

  factory _WebsiteSaveScope.fromCommand(
    WebsiteEditorSaveCommand command,
    WebsiteEditModeProvider document,
  ) {
    return _WebsiteSaveScope(
      tenantId: command.tenantId,
      document: document,
      documentSessionRevision: command.documentSessionRevision,
      pageId: command.pageId,
      pageSlug: _normalizedPageSlug(command.pageSlug),
    );
  }

  final String tenantId;
  final WebsiteEditModeProvider document;
  final int documentSessionRevision;
  final String? pageId;
  final String pageSlug;

  @override
  bool operator ==(Object other) {
    return other is _WebsiteSaveScope &&
        tenantId == other.tenantId &&
        identical(document, other.document) &&
        documentSessionRevision == other.documentSessionRevision &&
        pageId == other.pageId &&
        pageSlug == other.pageSlug;
  }

  @override
  int get hashCode => Object.hash(
        tenantId,
        identityHashCode(document),
        documentSessionRevision,
        pageId,
        pageSlug,
      );
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String _normalizedPageSlug(String? slug) {
  var normalized = slug?.trim().toLowerCase() ?? '';
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized == 'home' ? '' : normalized;
}

String _persistedNavigationId(String draftId) {
  final normalized =
      draftId.startsWith('draft_') ? draftId.substring(6) : draftId;
  if (!_uuidPattern.hasMatch(normalized)) {
    throw StateError(
      'El borrador de navegación no contiene un UUID persistible.',
    );
  }
  return normalized;
}

Map<String, dynamic> _copyMap(Map<String, dynamic> source) {
  return source.map(
    (key, value) => MapEntry(key, _copyValue(value)),
  );
}

dynamic _copyValue(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _copyValue(nested)),
    );
  }
  if (value is List) return value.map(_copyValue).toList();
  return value;
}

WebsiteNavigation _copyNavigation(WebsiteNavigation source) {
  return WebsiteNavigation(
    id: source.id,
    tenantId: source.tenantId,
    menuLocation: source.menuLocation,
    label: source.label,
    icon: source.icon,
    linkType: source.linkType,
    linkValue: source.linkValue,
    openInNewTab: source.openInNewTab,
    parentId: source.parentId,
    orderIndex: source.orderIndex,
    isVisible: source.isVisible,
    showOnDesktop: source.showOnDesktop,
    showOnMobile: source.showOnMobile,
    cssClass: source.cssClass,
    highlight: source.highlight,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
    children: source.children.map(_copyNavigation).toList(),
    linkedPage: source.linkedPage,
  );
}
