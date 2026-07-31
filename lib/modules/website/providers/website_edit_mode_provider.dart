import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../models/website_page_models.dart';
import '../models/website_action.dart';
import '../models/website_editor_capability.dart';
import '../models/website_block_document_sanitizer.dart';
import '../models/canvas_element_factory.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';

const _uuid = Uuid();

/// Device preview modes for the website editor
enum DevicePreviewMode {
  desktop,
  tablet,
  mobile,
}

/// The single storefront mode FSM owned by [WebsiteEditModeProvider].
///
/// `public` is the visitor view, `preview` shows the editor top bar without
/// the inspector, and `edit` shows the full editor. Exactly one value is
/// active at any time; the URL is only an entry command plus a write-through
/// projection of this state, never a second owner.
enum WebsiteEditorMode {
  public,
  preview,
  edit,
}


/// The active task surface inside the Website Builder.
///
/// Page composition is the only workspace that owns the persistent block
/// inspector. Management workspaces use the full viewport while preserving the
/// editor draft in this provider.
enum WebsiteWorkspaceMode {
  pageEditor,
  catalog,
  structure,
  settings,
  operations,
}

/// Immutable identity/content snapshot for the active Website Builder page.
///
/// The provider remains the only state owner. Consumers that need a stable
/// command snapshot use this value instead of reading several mutable getters
/// at different times.
class WebsiteEditorDocument {
  const WebsiteEditorDocument({
    required this.pageId,
    required this.pageSlug,
    required this.blocks,
    required this.sessionRevision,
    required this.hasUnsavedChanges,
    required this.ownerTenantId,
    required this.ownerLeaseFingerprint,
  });

  final String? pageId;
  final String? pageSlug;
  final List<Map<String, dynamic>> blocks;
  final int sessionRevision;
  final bool hasUnsavedChanges;

  /// Typed owner captured when the session/document opened under a granted
  /// lease. The save preflight validates it against BOTH the current lease
  /// and the target tenant; null means the document is not attributable and
  /// can never save.
  final String? ownerTenantId;
  final String? ownerLeaseFingerprint;
}

/// Provider for website inline edit mode state.
/// Tracks edit mode, selected block, and pending changes.
///
/// Two modes:
/// - Preview mode: Shows the top bar (isPreviewMode = true)
/// - Edit mode: Shows the side panel (isEditMode = true)
class WebsiteEditModeProvider extends ChangeNotifier {
  int _navigationStateRevision = 0;

  int get navigationStateRevision => _navigationStateRevision;

  @override
  void notifyListeners() {
    _navigationStateRevision++;
    super.notifyListeners();
  }

  WebsiteEditorMode _mode = WebsiteEditorMode.public;
  WebsiteEditorCapabilitySnapshot? _entryLease;
  int _entryLeaseGeneration = 0;
  // TYPED identity of a transiently SUSPENDED lease. Retained drafts belong
  // to exactly this identity: only a granted snapshot with the SAME
  // fingerprint may resume them; any other fingerprint clears every bucket
  // before being adopted.
  WebsiteEditorCapabilitySnapshot? _suspendedLease;
  String? get _suspendedLeaseFingerprint => _suspendedLease?.fingerprint;
  WebsiteWorkspaceMode _workspaceMode = WebsiteWorkspaceMode.pageEditor;
  DevicePreviewMode _devicePreviewMode =
      DevicePreviewMode.desktop; // Persist preview options

  String? _selectedBlockId;
  int _selectionVersion = 0; // Tracks explicit selection events
  final Map<String, int> _carouselSlideSelections = {};
  final Map<String, String?> _canvasElementSelections = {};
  final _WebsiteEditorPageDraftState _pageDraft =
      _WebsiteEditorPageDraftState();
  final _WebsiteEditorSitewideDraftState _sitewideDraft =
      _WebsiteEditorSitewideDraftState();
  final _WebsiteEditorSeoDraftState _seoDraft = _WebsiteEditorSeoDraftState();
  Map<String, dynamic> _settings = {};

  // Screenshot capability
  final GlobalKey _screenshotKey = GlobalKey();
  GlobalKey get screenshotKey => _screenshotKey;

  // Key for capturing the preview area for color picking
  final GlobalKey previewRepaintKey = GlobalKey();

  // Transient selection for on-canvas inline editing
  String? _selectedFooterNavId;
  final int _maxHistory = 50;

  // Getters
  /// The canonical single mode owner. Boolean getters below are derived
  /// projections kept for call-site compatibility during the FSM migration.
  WebsiteEditorMode get mode => _mode;

  /// Identity-bound authority lease to honor untrusted editor entry commands
  /// (`?edit=true`/`?preview=true` deep links, the OAuth editor restore).
  /// Null means unresolved. See [WebsiteEditorCapabilitySnapshot] for the
  /// fingerprint contract; the single truth producer is
  /// `WebsiteService.editorCapabilitySync/resolveEditorCapability`.
  WebsiteEditorCapabilitySnapshot? get editorEntryLease => _entryLease;
  bool get editorEntryLeaseGranted => _entryLease?.granted == true;
  bool get editorEntryLeaseDenied =>
      _entryLease != null && !_entryLease!.granted;

  /// Anti-ABA generation. An async capability resolution captures this value
  /// before awaiting and its result is discarded if a revocation happened in
  /// between (A -> B -> A cannot re-apply the stale A response).
  int get editorEntryLeaseGeneration => _entryLeaseGeneration;

  /// Bumps ONLY on identity transitions (revoke, or adopting over a
  /// different suspended fingerprint) — never on a same-identity suspension.
  /// The route adapter uses it to decide whether a pending URL entry command
  /// dies (identity change) or stays pending for the same identity's regrant
  /// (suspension): both cases bump [editorEntryLeaseGeneration], so the
  /// generation alone cannot make that distinction.
  int get editorEntryLeaseIdentityRevision => _entryLeaseIdentityRevision;
  int _entryLeaseIdentityRevision = 0;

  /// Adopts a resolved capability snapshot for [generation]. A stale
  /// generation is ignored. Safe during build (deferred notification).
  /// Returns true when the lease effectively changed, so the caller can emit
  /// exactly one CMS revalidation per transition.
  bool adoptEditorEntryLease(
    int generation,
    WebsiteEditorCapabilitySnapshot lease,
  ) {
    if (generation != _entryLeaseGeneration) return false;
    if (_entryLease?.fingerprint == lease.fingerprint &&
        _entryLease?.granted == lease.granted &&
        _entryLease?.authorityEpoch == lease.authorityEpoch) {
      return false;
    }
    final live = _entryLease;
    if (live != null &&
        (live.fingerprint != lease.fingerprint ||
            live.authorityEpoch != lease.authorityEpoch)) {
      // CENTRAL takeover: adopting over a DIFFERENT live identity is an
      // identity transition by itself — in-flight completions invalidate,
      // the identity revision bumps and every bucket/owner clears BEFORE B
      // is adopted. No caller has to remember to revoke first.
      _entryLeaseGeneration++;
      _entryLeaseIdentityRevision++;
      _clearEditorSessionState();
    }
    final suspended = _suspendedLease;
    if (suspended != null &&
        (suspended.fingerprint != lease.fingerprint ||
            suspended.authorityEpoch != lease.authorityEpoch)) {
      // The retained drafts belong to the suspended identity; a DIFFERENT
      // identity (granted or not) can never inherit them — and any of that
      // identity's in-flight completions die with the generation bump.
      _entryLeaseGeneration++;
      _entryLeaseIdentityRevision++;
      _clearEditorSessionState();
    }
    _suspendedLease = null;
    _entryLease = lease;
    if (lease.granted) {
      // The granted entry stamps the SESSION owner: sitewide/SEO drafts on
      // documentless routes are attributable to exactly this identity.
      _sessionOwnerLease = lease;
    }
    _notifyAfterFrame();
    return true;
  }

  /// Typed owner of the editor SESSION (stamped on the granted entry).
  /// Documentless routes (cart/checkout/contact/catalog/detail) still edit
  /// sitewide/SEO drafts; those attribute to this owner. Page-block saves
  /// additionally require the bound page-document owner.
  String? get sessionOwnerTenantId => _sessionOwnerLease?.storefrontTenantId;
  String? get sessionOwnerLeaseFingerprint => _sessionOwnerLease?.fingerprint;
  WebsiteEditorCapabilitySnapshot? _sessionOwnerLease;

  /// Best available TYPED identity evidence for the session, in trust
  /// order: live lease, suspended lease, session owner, document owner.
  /// Entry/restore boundaries compare its FIELDS against the requesting
  /// identity — never a parsed fingerprint string.
  WebsiteEditorCapabilitySnapshot? get editorSessionIdentity =>
      _entryLease ??
      _suspendedLease ??
      _sessionOwnerLease ??
      _documentOwnerLease;

  /// Transiently suspends the lease for the SAME identity (a re-resolution
  /// error, not an identity change). The FSM projects `public` immediately —
  /// no editor chrome, draft content or unpublished-site bypass stays
  /// visible — while every draft bucket is RETAINED in memory (hidden) so a
  /// successful retry of that exact identity continues without data loss.
  bool suspendEditorEntryLease() {
    _entryLeaseGeneration++;
    final hadLease = _entryLease != null;
    // A lease-less programmatic session is attributable through its typed
    // document owner; the suspension retains the drafts for that identity.
    _suspendedLease = _entryLease ??
        _suspendedLease ??
        _documentOwnerLease ??
        _sessionOwnerLease;
    _entryLease = null;
    if (_mode != WebsiteEditorMode.public) {
      _mode = WebsiteEditorMode.public;
      _selectedBlockId = null;
      _notifyAfterFrame();
      return true;
    }
    if (hadLease) _notifyAfterFrame();
    return hadLease;
  }

  /// Identity fingerprint whose hidden drafts a suspension retained, if any.
  String? get suspendedEditorLeaseFingerprint => _suspendedLeaseFingerprint;

  /// Revokes the lease because the IDENTITY changed (logout, user switch,
  /// tenant switch, or authority durably denied). Every draft bucket of the
  /// previous fingerprint — page, sitewide and SEO — is discarded through
  /// [closeEditor]: a draft authored under identity A must never survive
  /// into, or be applied by, a later identity B. Always called BEFORE a new
  /// identity's lease is adopted, even when both identities are granted.
  bool revokeEditorEntryLease() {
    _entryLeaseGeneration++;
    _entryLeaseIdentityRevision++;
    final hadLease =
        _entryLease != null || _suspendedLeaseFingerprint != null;
    _entryLease = null;
    _suspendedLease = null;
    // An identity change orphans BOTH owners unconditionally, session and
    // document alike — even when no visible session needs closing.
    _documentOwnerLease = null;
    _sessionOwnerLease = null;
    if (_mode != WebsiteEditorMode.public ||
        _pageDraft.isActive ||
        hasUnsavedChanges) {
      closeEditor(); // Discards page + sitewide + SEO buckets (deferred notify).
      return true;
    }
    if (hadLease) _notifyAfterFrame();
    return hadLease;
  }
  bool get isPreviewMode => _mode == WebsiteEditorMode.preview;
  bool get isEditMode => _mode == WebsiteEditorMode.edit;
  bool get isInEditorContext => _mode != WebsiteEditorMode.public;
  WebsiteWorkspaceMode get workspaceMode => _workspaceMode;
  bool get isPageEditorWorkspace =>
      _workspaceMode == WebsiteWorkspaceMode.pageEditor;
  bool get isManagementWorkspace => !isPageEditorWorkspace;
  DevicePreviewMode get devicePreviewMode => _devicePreviewMode;
  String? get selectedBlockId => _selectedBlockId;
  int get selectionVersion => _selectionVersion;

  /// Transient inspector/canvas selection. This is UI state and must never be
  /// persisted into block data or mark the page as changed.
  int carouselSlideSelection(String blockId, int slideCount) {
    if (slideCount <= 0) return 0;
    return (_carouselSlideSelections[blockId] ?? 0)
        .clamp(0, slideCount - 1)
        .toInt();
  }

  String _canvasSelectionKey(String blockId, int? slideIndex) =>
      '$blockId:${slideIndex == null ? 'root' : 'slide_$slideIndex'}';

  /// Selected nested Canvas layer for a standalone Canvas block or a composed
  /// carousel slide. This is editor-only state: it never enters block_data,
  /// persistence, dirty tracking, or undo history.
  String? canvasElementSelection(String blockId, {int? slideIndex}) =>
      _canvasElementSelections[_canvasSelectionKey(blockId, slideIndex)];

  /// Select a nested Canvas layer while restoring its owning block/slide.
  /// Repeated selection is intentional and increments [selectionVersion] so
  /// the inspector can recover after another surface cleared its context.
  void selectCanvasElement(
    String blockId,
    String? elementId, {
    int? slideIndex,
    int? slideCount,
  }) {
    _selectedBlockId = blockId;
    if (slideIndex != null && slideCount != null && slideCount > 0) {
      _carouselSlideSelections[blockId] =
          slideIndex.clamp(0, slideCount - 1).toInt();
    }
    _canvasElementSelections[_canvasSelectionKey(blockId, slideIndex)] =
        elementId;
    _selectionVersion++;
    notifyListeners();
  }

  /// Nested selection for the currently selected block, used by the inspector
  /// identity and scroll reset contract.
  String? get selectedCanvasElementId {
    final blockId = _selectedBlockId;
    if (blockId == null) return null;
    final block = getBlock(blockId);
    if (block == null) return null;
    final type = (block['block_type'] ?? block['type'] ?? '').toString();
    if (type == WebsiteBlockType.carousel.name) {
      final data = Map<String, dynamic>.from(block['block_data'] ?? const {});
      final slides = data['slides'];
      final count = slides is List ? slides.length : 0;
      if (count <= 0) return null;
      return canvasElementSelection(
        blockId,
        slideIndex: carouselSlideSelection(blockId, count),
      );
    }
    if (type == WebsiteBlockType.canvas.name) {
      return canvasElementSelection(blockId);
    }
    return null;
  }

  void selectCarouselSlide(String blockId, int index, int slideCount) {
    if (slideCount <= 0) return;
    final normalized = index.clamp(0, slideCount - 1).toInt();
    _carouselSlideSelections[blockId] = normalized;
    _selectedBlockId = blockId;
    _selectionVersion++;
    notifyListeners();
  }

  bool get hasUnsavedChanges =>
      _pageDraft.hasUnsavedChanges ||
      _sitewideDraft.hasHeaderChanges ||
      _sitewideDraft.hasSiteSettingsChanges ||
      _seoDraft.hasChanges ||
      _sitewideDraft.hasThemeChanges ||
      _sitewideDraft.hasFooterChanges;
  bool get hasPageDraftChanges => _pageDraft.hasUnsavedChanges;
  bool get hasSitewideDraftChanges =>
      _sitewideDraft.hasHeaderChanges ||
      _sitewideDraft.hasSiteSettingsChanges ||
      _sitewideDraft.hasThemeChanges ||
      _sitewideDraft.hasFooterChanges;
  bool get hasSeoDraftChanges => _seoDraft.hasChanges;
  bool get hasHeaderChanges => _sitewideDraft.hasHeaderChanges;
  bool get hasSiteSettingsChanges => _sitewideDraft.hasSiteSettingsChanges;
  bool get hasThemeChanges => _sitewideDraft.hasThemeChanges;
  bool get hasFooterChanges => _sitewideDraft.hasFooterChanges;
  List<Map<String, dynamic>> get blocks =>
      List<Map<String, dynamic>>.unmodifiable(
        _pageDraft.blocks.map(_deepUnmodifiableMap),
      );
  Map<String, dynamic> get settings => _deepUnmodifiableMap(_settings);
  Map<String, String> get pendingHeaderSettings =>
      Map<String, String>.unmodifiable(_sitewideDraft.pendingHeaderSettings);
  Map<String, String> get pendingSiteSettings =>
      Map<String, String>.unmodifiable(_sitewideDraft.pendingSiteSettings);
  Map<String, String> get pendingFooterSettings =>
      Map<String, String>.unmodifiable(_sitewideDraft.pendingFooterSettings);
  Map<String, String> get pendingThemeSettings =>
      Map<String, String>.unmodifiable(_sitewideDraft.pendingThemeSettings);
  Map<String, Map<String, String>> get pendingPageSeo =>
      Map<String, Map<String, String>>.unmodifiable(
        _seoDraft.pendingByRoute.map(
          (route, values) => MapEntry(
            route,
            Map<String, String>.unmodifiable(values),
          ),
        ),
      );
  Map<String, List<String>> get pendingFooterLinkOrder =>
      Map<String, List<String>>.unmodifiable(
        _sitewideDraft.pendingFooterLinkOrder.map(
          (sectionId, ids) => MapEntry(
            sectionId,
            List<String>.unmodifiable(ids),
          ),
        ),
      );

  Map<String, String> get pendingFooterNavLabels =>
      Map<String, String>.unmodifiable(_sitewideDraft.pendingFooterNavLabels);
  Map<String, NavLinkType> get pendingFooterNavLinkTypes =>
      Map<String, NavLinkType>.unmodifiable(
        _sitewideDraft.pendingFooterNavLinkTypes,
      );
  Map<String, String?> get pendingFooterNavLinkValues =>
      Map<String, String?>.unmodifiable(
        _sitewideDraft.pendingFooterNavLinkValues,
      );
  Map<String, bool> get pendingFooterNavOpenInNewTab =>
      Map<String, bool>.unmodifiable(
        _sitewideDraft.pendingFooterNavOpenInNewTab,
      );
  Map<String, WebsiteNavigation> get pendingFooterNavItems =>
      Map<String, WebsiteNavigation>.unmodifiable(
        _sitewideDraft.pendingFooterNavItems.map(
          (id, navigation) => MapEntry(id, _immutableNavigation(navigation)),
        ),
      );
  Map<String, WebsiteNavigation> get pendingFooterNavCreates =>
      Map<String, WebsiteNavigation>.unmodifiable(
        _sitewideDraft.pendingFooterNavCreates.map(
          (id, navigation) => MapEntry(id, _immutableNavigation(navigation)),
        ),
      );
  Set<String> get pendingFooterNavDeletes =>
      Set<String>.unmodifiable(_sitewideDraft.pendingFooterNavDeletes);

  String? get selectedFooterNavId => _selectedFooterNavId;
  bool get canUndo => _pageDraft.historyIndex > 0;
  bool get canRedo => _pageDraft.historyIndex < _pageDraft.history.length - 1;

  // Multi-page editing getters
  String? get currentPageId => _pageDraft.pageId;
  String? get currentPageSlug => _pageDraft.pageSlug;
  int get documentSessionRevision => _pageDraft.sessionRevision;
  bool get isEditingHomePage => _pageDraft.pageId == null;
  bool ownsPageDocument({
    String? pageId,
    String? pageSlug,
  }) =>
      _matchesActivePage(pageId, pageSlug);
  WebsiteEditorDocument get document => WebsiteEditorDocument(
        pageId: _pageDraft.pageId,
        pageSlug: _pageDraft.pageSlug,
        blocks: List<Map<String, dynamic>>.unmodifiable(
          _pageDraft.blocks.map(_deepUnmodifiableMap),
        ),
        sessionRevision: _pageDraft.sessionRevision,
        hasUnsavedChanges: _pageDraft.hasUnsavedChanges,
        ownerTenantId: documentOwnerTenantId,
        ownerLeaseFingerprint: documentOwnerLeaseFingerprint,
      );

  /// Switch task surfaces without reloading or clearing the current page draft.
  void openWorkspace(WebsiteWorkspaceMode mode) {
    if (_workspaceMode == mode) return;
    _workspaceMode = mode;
    notifyListeners();
  }

  void returnToPageEditor() {
    openWorkspace(WebsiteWorkspaceMode.pageEditor);
  }

  /// Update the current page context without resetting blocks/settings.
  ///
  /// Useful when the page row is created/resolved at save-time and we want
  /// subsequent saves to target the correct page.
  void updateCurrentPageContext({
    String? pageId,
    String? pageSlug,
  }) {
    if (_pageDraft.pageId == pageId && _pageDraft.pageSlug == pageSlug) return;
    _pageDraft.pageId = pageId;
    _pageDraft.pageSlug = pageSlug;
    _pageDraft.sessionRevision++;
    notifyListeners();
  }

  /// Save acknowledgement for a page row resolved/created by the coordinator.
  ///
  /// This does not start a new document session. The coordinator first checks
  /// [documentSessionRevision], so changing this storage identity cannot make
  /// its own completion look stale.
  void acknowledgeSavedPageContext({
    String? pageId,
    String? pageSlug,
  }) {
    if (_pageDraft.pageId == pageId && _pageDraft.pageSlug == pageSlug) return;
    _pageDraft.pageId = pageId;
    _pageDraft.pageSlug = pageSlug;
    notifyListeners();
  }

  /// Mark header as having unsaved changes
  void markHeaderChanged() {
    _sitewideDraft.hasHeaderChanges = true;
    notifyListeners();
  }

  /// Update pending header settings (will be saved with main save button)
  void updateHeaderSettings(Map<String, String> settings) {
    _sitewideDraft.pendingHeaderSettings = Map<String, String>.from(settings);
    _sitewideDraft.hasHeaderChanges = true;
    debugPrint(
        '📝 [EditProvider] Header settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Commits only the header values that still match the save snapshot.
  ///
  /// A user can keep editing while a request is in flight. Compare-and-clear
  /// prevents that newer draft from being erased when the older request
  /// completes.
  void acknowledgeSavedHeaderSettings(Map<String, String> savedSnapshot) {
    _mergeSavedSettingsBaseline(savedSnapshot);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingHeaderSettings, savedSnapshot);
    _sitewideDraft.hasHeaderChanges =
        _sitewideDraft.pendingHeaderSettings.isNotEmpty;
    notifyListeners();
  }

  /// Update a single footer setting for live preview
  void updateFooterSetting(String key, String value) {
    _sitewideDraft.pendingFooterSettings[key] = value;
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple footer settings at once
  void updateFooterSettings(Map<String, String> settings) {
    _sitewideDraft.pendingFooterSettings.addAll(settings);
    _sitewideDraft.hasFooterChanges = true;
    debugPrint(
        '🦶 [EditProvider] Footer settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective footer setting (pending value if exists, otherwise from settings)
  String getEffectiveFooterSetting(String key, String defaultValue) {
    if (_sitewideDraft.pendingFooterSettings.containsKey(key)) {
      return _sitewideDraft.pendingFooterSettings[key]!;
    }
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  /// Get pending footer section order (for visual display)
  List<String>? get pendingFooterSectionOrder {
    final order = _sitewideDraft.pendingFooterSectionOrder;
    return order == null ? null : List<String>.unmodifiable(order);
  }

  /// Get pending footer link order for a section
  List<String>? getPendingFooterLinkOrder(String sectionId) {
    final order = _sitewideDraft.pendingFooterLinkOrder[sectionId];
    return order == null ? null : List<String>.unmodifiable(order);
  }

  /// Update pending footer section order (does not save until Guardar)
  void updateFooterSectionOrder(List<String> orderedIds) {
    _sitewideDraft.pendingFooterSectionOrder =
        List<String>.from(orderedIds, growable: false);
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer section order updated (pending save)');
    notifyListeners();
  }

  /// Update pending footer link order for a section (does not save until Guardar)
  void updateFooterLinkOrder(String sectionId, List<String> orderedIds) {
    _sitewideDraft.pendingFooterLinkOrder[sectionId] =
        List<String>.from(orderedIds, growable: false);
    _sitewideDraft.hasFooterChanges = true;
    debugPrint(
        '🦶 [EditProvider] Footer link order for $sectionId updated (pending save)');
    notifyListeners();
  }

  /// Select a footer navigation item for on-canvas inline editing.
  void selectFooterNavItem(String? navId) {
    _selectedFooterNavId = navId;
    _selectionVersion++;
    debugPrint(
        '👉 [EditProvider] Footer Nav Selected: $navId (v$_selectionVersion)');
    notifyListeners();
  }

  /// Update a footer navigation label (live preview + saved with Guardar).
  void updateFooterNavLabel(String navId, String label) {
    _sitewideDraft.pendingFooterNavLabels[navId] = label;
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav label updated: $navId = $label');
    notifyListeners();
  }

  /// Update a footer navigation destination (live preview + saved with Guardar).
  void updateFooterNavDestination(
    String navId, {
    required NavLinkType linkType,
    required String? linkValue,
    bool? openInNewTab,
  }) {
    _sitewideDraft.pendingFooterNavLinkTypes[navId] = linkType;
    _sitewideDraft.pendingFooterNavLinkValues[navId] = linkValue;
    if (openInNewTab != null) {
      _sitewideDraft.pendingFooterNavOpenInNewTab[navId] = openInNewTab;
    }
    _sitewideDraft.hasFooterChanges = true;
    debugPrint(
        '🦶 [EditProvider] Footer nav destination updated: $navId = ${linkType.value}:$linkValue');
    notifyListeners();
  }

  /// Update a footer navigation item as staged editor state.
  ///
  /// Used by the side-panel footer editor for fields beyond label/destination
  /// such as visibility, parent section, and device visibility.
  void updateFooterNavItem(WebsiteNavigation nav) {
    final storedNavigation = _immutableNavigation(nav);
    if (_sitewideDraft.pendingFooterNavCreates.containsKey(nav.id)) {
      _sitewideDraft.pendingFooterNavCreates[nav.id] = storedNavigation;
    } else {
      _sitewideDraft.pendingFooterNavItems[nav.id] = storedNavigation;
    }
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav item updated: ${nav.id}');
    notifyListeners();
  }

  WebsiteNavigation createFooterNavDraft(WebsiteNavigation nav) {
    final draftId = nav.id.trim().isEmpty ? 'draft_${_uuid.v4()}' : nav.id;
    final draft = WebsiteNavigation(
      id: draftId,
      tenantId: nav.tenantId,
      menuLocation: nav.menuLocation,
      label: nav.label,
      icon: nav.icon,
      linkType: nav.linkType,
      linkValue: nav.linkValue,
      openInNewTab: nav.openInNewTab,
      parentId: nav.parentId,
      orderIndex: nav.orderIndex,
      isVisible: nav.isVisible,
      showOnDesktop: nav.showOnDesktop,
      showOnMobile: nav.showOnMobile,
      cssClass: nav.cssClass,
      highlight: nav.highlight,
      createdAt: nav.createdAt,
      updatedAt: nav.updatedAt,
      children: List<WebsiteNavigation>.unmodifiable(
        nav.children.map(_immutableNavigation),
      ),
      linkedPage: nav.linkedPage,
    );

    _sitewideDraft.pendingFooterNavCreates[draft.id] = draft;
    _sitewideDraft.pendingFooterNavDeletes.remove(draft.id);
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav draft created: ${draft.id}');
    notifyListeners();
    return _immutableNavigation(draft);
  }

  void deleteFooterNavItem(WebsiteNavigation nav) {
    final ids = <String>{};

    void collect(WebsiteNavigation item) {
      ids.add(item.id);
      for (final child in item.children) {
        collect(child);
      }
    }

    collect(nav);

    var foundDraftChild = true;
    while (foundDraftChild) {
      foundDraftChild = false;
      for (final draft in _sitewideDraft.pendingFooterNavCreates.values) {
        if (draft.parentId != null &&
            ids.contains(draft.parentId) &&
            ids.add(draft.id)) {
          foundDraftChild = true;
        }
      }
    }

    for (final id in ids) {
      if (_sitewideDraft.pendingFooterNavCreates.remove(id) == null) {
        _sitewideDraft.pendingFooterNavDeletes.add(id);
      }
      _sitewideDraft.pendingFooterNavItems.remove(id);
      _sitewideDraft.pendingFooterNavLabels.remove(id);
      _sitewideDraft.pendingFooterNavLinkTypes.remove(id);
      _sitewideDraft.pendingFooterNavLinkValues.remove(id);
      _sitewideDraft.pendingFooterNavOpenInNewTab.remove(id);
    }

    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer nav items deleted: ${ids.join(', ')}');
    notifyListeners();
  }

  String getEffectiveFooterNavLabel(String navId, String savedLabel) {
    if (_sitewideDraft.pendingFooterNavLabels.containsKey(navId)) {
      return _sitewideDraft.pendingFooterNavLabels[navId]!;
    }
    return savedLabel;
  }

  NavLinkType getEffectiveFooterNavLinkType(String navId, NavLinkType saved) {
    return _sitewideDraft.pendingFooterNavLinkTypes[navId] ?? saved;
  }

  String? getEffectiveFooterNavLinkValue(String navId, String? saved) {
    if (_sitewideDraft.pendingFooterNavLinkValues.containsKey(navId)) {
      return _sitewideDraft.pendingFooterNavLinkValues[navId];
    }
    return saved;
  }

  bool getEffectiveFooterNavOpenInNewTab(String navId, bool saved) {
    if (_sitewideDraft.pendingFooterNavOpenInNewTab.containsKey(navId)) {
      return _sitewideDraft.pendingFooterNavOpenInNewTab[navId]!;
    }
    return saved;
  }

  WebsiteNavigation getEffectiveFooterNavItem(WebsiteNavigation saved) {
    final staged = _sitewideDraft.pendingFooterNavItems[saved.id];
    final source = staged ?? saved;
    final hasLinkValue =
        _sitewideDraft.pendingFooterNavLinkValues.containsKey(saved.id);

    return WebsiteNavigation(
      id: saved.id,
      tenantId: saved.tenantId,
      menuLocation: source.menuLocation,
      label: _sitewideDraft.pendingFooterNavLabels[saved.id] ?? source.label,
      icon: source.icon,
      linkType:
          _sitewideDraft.pendingFooterNavLinkTypes[saved.id] ?? source.linkType,
      linkValue: hasLinkValue
          ? _sitewideDraft.pendingFooterNavLinkValues[saved.id]
          : source.linkValue,
      openInNewTab: _sitewideDraft.pendingFooterNavOpenInNewTab[saved.id] ??
          source.openInNewTab,
      parentId: source.parentId,
      orderIndex: source.orderIndex,
      isVisible: source.isVisible,
      showOnDesktop: source.showOnDesktop,
      showOnMobile: source.showOnMobile,
      cssClass: source.cssClass,
      highlight: source.highlight,
      createdAt: saved.createdAt,
      updatedAt: source.updatedAt,
      children: source.children,
      linkedPage: saved.linkedPage,
    );
  }

  List<WebsiteNavigation> getEffectiveFooterNavigation(
    List<WebsiteNavigation> savedRoots,
  ) {
    final byId = <String, WebsiteNavigation>{};

    void collect(WebsiteNavigation item) {
      byId[item.id] = item;
      for (final child in item.children) {
        collect(child);
      }
    }

    for (final root in savedRoots) {
      collect(root);
    }
    byId.addAll(_sitewideDraft.pendingFooterNavCreates);
    byId.removeWhere(
        (id, _) => _sitewideDraft.pendingFooterNavDeletes.contains(id));

    final effectiveById = <String, WebsiteNavigation>{
      for (final entry in byId.entries)
        entry.key: getEffectiveFooterNavItem(entry.value),
    };
    final childrenByParent = <String, List<WebsiteNavigation>>{};
    final roots = <WebsiteNavigation>[];

    for (final item in effectiveById.values) {
      final parentId = item.parentId;
      if (parentId == null || !effectiveById.containsKey(parentId)) {
        roots.add(item);
      } else {
        childrenByParent.putIfAbsent(parentId, () => []).add(item);
      }
    }

    WebsiteNavigation buildNode(WebsiteNavigation item, Set<String> path) {
      if (path.contains(item.id)) return item.copyWith(children: const []);
      final nextPath = <String>{...path, item.id};
      final children = List<WebsiteNavigation>.from(
        childrenByParent[item.id] ?? const <WebsiteNavigation>[],
      )..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      return item.copyWith(
        children: children.map((child) => buildNode(child, nextPath)).toList(),
      );
    }

    roots.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return roots.map((root) => buildNode(root, const <String>{})).toList();
  }

  void acknowledgeSavedFooterSettings(Map<String, String> savedSnapshot) {
    _mergeSavedSettingsBaseline(savedSnapshot);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingFooterSettings, savedSnapshot);
    _recomputeFooterChanges();
    notifyListeners();
  }

  /// Removes only navigation deletes already confirmed by the database.
  ///
  /// This acknowledgement happens per successful operation so a later block
  /// or navigation failure cannot replay an old delete on retry.
  void acknowledgeSavedNavigationDeletes(Set<String> savedNavigationIds) {
    _sitewideDraft.pendingFooterNavDeletes.removeAll(savedNavigationIds);
    _recomputeFooterChanges();
    notifyListeners();
  }

  /// Compare-and-clears the staged fields for one confirmed navigation row.
  ///
  /// A concurrent edit made after the save snapshot remains pending because
  /// each field is removed only while it still equals the confirmed value.
  void acknowledgeSavedNavigationUpdate({
    required String navigationId,
    required Map<String, String> navigationLabels,
    required Map<String, NavLinkType> navigationLinkTypes,
    required Map<String, String?> navigationLinkValues,
    required Map<String, bool> navigationOpenInNewTab,
    required Map<String, WebsiteNavigation> navigationItems,
  }) {
    _removeMatchingMapEntry(
      _sitewideDraft.pendingFooterNavLabels,
      navigationLabels,
      navigationId,
    );
    _removeMatchingMapEntry(
      _sitewideDraft.pendingFooterNavLinkTypes,
      navigationLinkTypes,
      navigationId,
    );
    _removeMatchingMapEntry(
      _sitewideDraft.pendingFooterNavLinkValues,
      navigationLinkValues,
      navigationId,
    );
    _removeMatchingMapEntry(
      _sitewideDraft.pendingFooterNavOpenInNewTab,
      navigationOpenInNewTab,
      navigationId,
    );
    _removeMatchingMapEntry(
      _sitewideDraft.pendingFooterNavItems,
      navigationItems,
      navigationId,
      equals: _navigationHasSamePersistedValue,
    );
    _recomputeFooterChanges();
    notifyListeners();
  }

  void acknowledgeSavedFooterSectionOrder(List<String> savedOrder) {
    if (_deepEquals(
      _sitewideDraft.pendingFooterSectionOrder,
      savedOrder,
    )) {
      _sitewideDraft.pendingFooterSectionOrder = null;
    }
    _recomputeFooterChanges();
    notifyListeners();
  }

  void acknowledgeSavedFooterLinkOrder(
    String sectionId,
    List<String> savedOrder,
  ) {
    final pending = _sitewideDraft.pendingFooterLinkOrder[sectionId];
    if (_deepEquals(pending, savedOrder)) {
      _sitewideDraft.pendingFooterLinkOrder.remove(sectionId);
    }
    _recomputeFooterChanges();
    notifyListeners();
  }

  /// Acknowledges the complete footer/navigation section after every operation
  /// in that section has succeeded.
  ///
  /// Navigation creates are intentionally cleared only here: they are the last
  /// writes in [WebsiteSaveCoordinator], so a failed earlier section remains
  /// safely retryable without duplicating rows.
  void acknowledgeSavedFooterChanges({
    required Map<String, String> footerSettings,
    required List<String>? sectionOrder,
    required Map<String, List<String>> linkOrder,
    required Map<String, String> navigationLabels,
    required Map<String, NavLinkType> navigationLinkTypes,
    required Map<String, String?> navigationLinkValues,
    required Map<String, bool> navigationOpenInNewTab,
    required Map<String, WebsiteNavigation> navigationItems,
    required Map<String, WebsiteNavigation> navigationCreates,
    required Set<String> navigationDeletes,
  }) {
    _mergeSavedSettingsBaseline(footerSettings);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingFooterSettings, footerSettings);

    if (_deepEquals(_sitewideDraft.pendingFooterSectionOrder, sectionOrder)) {
      _sitewideDraft.pendingFooterSectionOrder = null;
    }

    _removeMatchingMapEntries(
      _sitewideDraft.pendingFooterLinkOrder,
      linkOrder,
      equals: _deepEquals,
    );
    _removeMatchingMapEntries(
        _sitewideDraft.pendingFooterNavLabels, navigationLabels);
    _removeMatchingMapEntries(
      _sitewideDraft.pendingFooterNavLinkTypes,
      navigationLinkTypes,
    );
    _removeMatchingMapEntries(
      _sitewideDraft.pendingFooterNavLinkValues,
      navigationLinkValues,
    );
    _removeMatchingMapEntries(
      _sitewideDraft.pendingFooterNavOpenInNewTab,
      navigationOpenInNewTab,
    );
    _removeMatchingMapEntries(
      _sitewideDraft.pendingFooterNavItems,
      navigationItems,
      equals: _navigationHasSamePersistedValue,
    );
    _removeMatchingMapEntries(
      _sitewideDraft.pendingFooterNavCreates,
      navigationCreates,
      equals: _navigationHasSamePersistedValue,
    );
    for (final navId in navigationDeletes) {
      _sitewideDraft.pendingFooterNavDeletes.remove(navId);
    }

    _recomputeFooterChanges();

    if (_selectedFooterNavId != null &&
        !_sitewideDraft.pendingFooterNavCreates
            .containsKey(_selectedFooterNavId) &&
        navigationCreates.containsKey(_selectedFooterNavId)) {
      _selectedFooterNavId = null;
    }
    notifyListeners();
  }

  void _recomputeFooterChanges() {
    _sitewideDraft.hasFooterChanges =
        _sitewideDraft.pendingFooterSettings.isNotEmpty ||
            _sitewideDraft.pendingFooterSectionOrder != null ||
            _sitewideDraft.pendingFooterLinkOrder.isNotEmpty ||
            _sitewideDraft.pendingFooterNavLabels.isNotEmpty ||
            _sitewideDraft.pendingFooterNavLinkTypes.isNotEmpty ||
            _sitewideDraft.pendingFooterNavLinkValues.isNotEmpty ||
            _sitewideDraft.pendingFooterNavOpenInNewTab.isNotEmpty ||
            _sitewideDraft.pendingFooterNavItems.isNotEmpty ||
            _sitewideDraft.pendingFooterNavCreates.isNotEmpty ||
            _sitewideDraft.pendingFooterNavDeletes.isNotEmpty;
  }

  /// Update a single theme setting for live preview
  void updateThemeSetting(String key, String value) {
    _sitewideDraft.pendingThemeSettings[key] = value;
    _sitewideDraft.hasThemeChanges = true;
    debugPrint('🎨 [EditProvider] Theme setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple theme settings at once
  void updateThemeSettings(Map<String, String> settings) {
    _sitewideDraft.pendingThemeSettings.addAll(settings);
    _sitewideDraft.hasThemeChanges = true;
    debugPrint(
        '🎨 [EditProvider] Theme settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective theme setting (pending value if exists, otherwise from settings)
  String getEffectiveThemeSetting(String key, String defaultValue) {
    // First check pending theme settings (live preview)
    if (_sitewideDraft.pendingThemeSettings.containsKey(key)) {
      return _sitewideDraft.pendingThemeSettings[key]!;
    }
    // Fall back to saved settings
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  void acknowledgeSavedThemeSettings(Map<String, String> savedSnapshot) {
    _mergeSavedSettingsBaseline(savedSnapshot);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingThemeSettings, savedSnapshot);
    _sitewideDraft.hasThemeChanges =
        _sitewideDraft.pendingThemeSettings.isNotEmpty;
    notifyListeners();
  }

  /// Update a single site-wide setting for live preview (saved with Guardar)
  void updateSiteSetting(String key, String value) {
    _sitewideDraft.pendingSiteSettings[key] = value;
    _sitewideDraft.hasSiteSettingsChanges = true;
    debugPrint('🏁 [EditProvider] Site setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple site-wide settings at once (saved with Guardar)
  void updateSiteSettings(Map<String, String> settings) {
    _sitewideDraft.pendingSiteSettings.addAll(settings);
    _sitewideDraft.hasSiteSettingsChanges = true;
    debugPrint(
        '🏁 [EditProvider] Site settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective site-wide setting (pending value if exists, otherwise from settings)
  String getEffectiveSiteSetting(String key, String defaultValue) {
    if (_sitewideDraft.pendingSiteSettings.containsKey(key)) {
      return _sitewideDraft.pendingSiteSettings[key]!;
    }
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  void acknowledgeSavedSiteSettings(Map<String, String> savedSnapshot) {
    _mergeSavedSettingsBaseline(savedSnapshot);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingSiteSettings, savedSnapshot);
    _sitewideDraft.hasSiteSettingsChanges =
        _sitewideDraft.pendingSiteSettings.isNotEmpty;
    notifyListeners();
  }

  Map<String, String>? getPendingPageSeo(String routeKey) {
    final values = _seoDraft.pendingByRoute[routeKey];
    return values == null ? null : Map<String, String>.unmodifiable(values);
  }

  /// Stage page-level SEO changes (saved on global Guardar).
  ///
  /// We keep this keyed by route key so users can adjust multiple pages
  /// without losing edits when navigating inside the persistent editor.
  void updatePageSeo({
    required String routeKey,
    required String metaTitle,
    required String metaDescription,
  }) {
    _seoDraft.pendingByRoute[routeKey] = {
      'meta_title': metaTitle,
      'meta_description': metaDescription,
    };
    _seoDraft.hasChanges = true;
    debugPrint('🔎 [EditProvider] Page SEO updated (pending save): $routeKey');
    notifyListeners();
  }

  void acknowledgeSavedPageSeo(
    Map<String, Map<String, String>> savedSnapshot,
  ) {
    _removeMatchingMapEntries(
      _seoDraft.pendingByRoute,
      savedSnapshot,
      equals: _deepEquals,
    );
    _seoDraft.hasChanges = _seoDraft.pendingByRoute.isNotEmpty;
    notifyListeners();
  }

  void _clearActivePageDraftState() {
    _pageDraft.hasUnsavedChanges = false;
    _selectedBlockId = null;
    _selectedFooterNavId = null;
    _carouselSlideSelections.clear();
    _canvasElementSelections.clear();
  }

  void _clearSitewideAndSeoDrafts() {
    _sitewideDraft.hasHeaderChanges = false;
    _sitewideDraft.hasSiteSettingsChanges = false;
    _seoDraft.hasChanges = false;
    _sitewideDraft.hasThemeChanges = false;
    _sitewideDraft.hasFooterChanges = false;

    _sitewideDraft.pendingHeaderSettings = {};
    _sitewideDraft.pendingSiteSettings = {};
    _sitewideDraft.pendingFooterSettings = {};
    _sitewideDraft.pendingThemeSettings = {};
    _sitewideDraft.pendingFooterSectionOrder = null;
    _sitewideDraft.pendingFooterLinkOrder = {};
    _sitewideDraft.pendingFooterNavLabels.clear();
    _sitewideDraft.pendingFooterNavLinkTypes.clear();
    _sitewideDraft.pendingFooterNavLinkValues.clear();
    _sitewideDraft.pendingFooterNavOpenInNewTab.clear();
    _sitewideDraft.pendingFooterNavItems.clear();
    _sitewideDraft.pendingFooterNavCreates.clear();
    _sitewideDraft.pendingFooterNavDeletes.clear();
    _seoDraft.pendingByRoute.clear();
    _selectedFooterNavId = null;
  }

  List<Map<String, dynamic>> _deepCopyBlocks(
    Iterable<Map<String, dynamic>> blocks,
  ) =>
      sanitizeWebsiteBlocksForPersistence(blocks.map(_deepCopyMap));

  void _rebaselineBlockHistory() {
    _pageDraft.blocks = _deepCopyBlocks(_pageDraft.blocks);
    _reconcileTransientCanvasSelections();
    _pageDraft.history
      ..clear()
      ..add(_deepCopyBlocks(_pageDraft.blocks));
    _pageDraft.historyIndex = 0;
  }

  void _reconcileTransientCanvasSelections() {
    final validCanvasKeys = <String>{};
    final elementIdsByCanvasKey = <String, Set<String>>{};
    final validCarouselBlockIds = <String>{};
    final blockIds = <String>{};

    Set<String> elementIds(Object? rawElements) {
      if (rawElements is! List) return const <String>{};
      return rawElements
          .whereType<Map>()
          .map((element) => element['id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    }

    for (final block in _pageDraft.blocks) {
      final blockId = block['id']?.toString().trim() ?? '';
      if (blockId.isEmpty) continue;
      blockIds.add(blockId);

      final blockType =
          (block['block_type'] ?? block['type'] ?? '').toString().toLowerCase();
      final rawData = block['block_data'] ?? block['data'];
      final data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{};

      if (blockType == WebsiteBlockType.canvas.name) {
        final key = _canvasSelectionKey(blockId, null);
        validCanvasKeys.add(key);
        elementIdsByCanvasKey[key] = elementIds(data['elements']);
        continue;
      }

      if (blockType != WebsiteBlockType.carousel.name) continue;
      validCarouselBlockIds.add(blockId);
      final rawSlides = data['slides'];
      final slides = rawSlides is List ? rawSlides : const <dynamic>[];
      if (slides.isEmpty) {
        _carouselSlideSelections.remove(blockId);
        continue;
      }

      final selectedIndex = (_carouselSlideSelections[blockId] ?? 0)
          .clamp(0, slides.length - 1)
          .toInt();
      _carouselSlideSelections[blockId] = selectedIndex;
      for (var slideIndex = 0; slideIndex < slides.length; slideIndex++) {
        final key = _canvasSelectionKey(blockId, slideIndex);
        validCanvasKeys.add(key);
        final rawSlide = slides[slideIndex];
        elementIdsByCanvasKey[key] =
            elementIds(rawSlide is Map ? rawSlide['elements'] : null);
      }
    }

    _carouselSlideSelections.removeWhere(
      (blockId, _) => !validCarouselBlockIds.contains(blockId),
    );
    _canvasElementSelections.removeWhere((key, elementId) {
      if (!validCanvasKeys.contains(key)) return true;
      return elementId != null &&
          !(elementIdsByCanvasKey[key]?.contains(elementId) ?? false);
    });
    if (_selectedBlockId != null && !blockIds.contains(_selectedBlockId)) {
      _selectedBlockId = null;
    }
  }

  /// Restore only the active page from its last loaded/saved snapshot.
  ///
  /// Sitewide and cross-page SEO drafts intentionally survive page switches.
  void discardActivePageDraft() {
    if (_pageDraft.history.isNotEmpty) {
      _pageDraft.blocks = _deepCopyBlocks(_pageDraft.history.first);
      _rebaselineBlockHistory();
    }

    _clearActivePageDraftState();
    notifyListeners();
  }

  /// Discard settings/header/footer/theme/navigation and cross-page SEO.
  void discardSitewideDrafts() {
    _clearSitewideAndSeoDrafts();
    notifyListeners();
  }

  /// Restore every draft scope from its last saved baseline.
  void discardPendingChanges() {
    if (_pageDraft.history.isNotEmpty) {
      _pageDraft.blocks = _deepCopyBlocks(_pageDraft.history.first);
      _rebaselineBlockHistory();
    }
    _clearActivePageDraftState();
    _clearSitewideAndSeoDrafts();
    notifyListeners();
  }

  bool _matchesActivePage(String? pageId, String? pageSlug) {
    if (!_pageDraft.isActive) return false;
    final activeId = _pageDraft.pageId?.trim() ?? '';
    final nextId = pageId?.trim() ?? '';
    if (activeId.isNotEmpty || nextId.isNotEmpty) {
      return activeId.isNotEmpty && activeId == nextId;
    }
    return _normalizePageSlug(_pageDraft.pageSlug) ==
        _normalizePageSlug(pageSlug);
  }

  bool _activatePageSnapshot(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    required WebsiteEditorMode mode,
    String? pageId,
    String? pageSlug,
  }) {
    assert(mode != WebsiteEditorMode.public,
        'A page document activates only inside an editor mode.');
    final samePage = _matchesActivePage(pageId, pageSlug);
    final nextBlocks = _deepCopyBlocks(blocks);
    final nextSettings = _deepCopyMap(settings);
    final modeChanged = _mode != mode;
    final workspaceChanged = _workspaceMode != WebsiteWorkspaceMode.pageEditor;
    final settingsChanged = !_deepEquals(_settings, nextSettings);
    var blocksChanged = false;

    _mode = mode;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    if (settingsChanged) _settings = nextSettings;

    if (!samePage || !_pageDraft.hasUnsavedChanges) {
      blocksChanged = !_deepEquals(_pageDraft.blocks, nextBlocks);
      if (!samePage || blocksChanged) {
        _pageDraft.blocks = nextBlocks;
        _clearActivePageDraftState();
        _rebaselineBlockHistory();
      }
    }
    if (!samePage) {
      _pageDraft.pageId = pageId;
      _pageDraft.pageSlug = pageSlug;
      _pageDraft.isActive = true;
      _pageDraft.sessionRevision++;
    }
    return !samePage ||
        modeChanged ||
        workspaceChanged ||
        settingsChanged ||
        blocksChanged;
  }

  bool _isDisposed = false;
  bool _deferredNotifyScheduled = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Build-safe notification: outside the build phase it notifies
  /// immediately (so an async lease grant schedules a real rebuild on the
  /// next frame); during build it coalesces every mutation of the logical
  /// transition into ONE deferred post-frame notification. A provider
  /// disposed before the deferred callback fires is silently skipped.
  void _notifyAfterFrame() {
    if (_isDisposed) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_deferredNotifyScheduled) return;
    _deferredNotifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deferredNotifyScheduled = false;
      if (_isDisposed) return;
      notifyListeners();
    });
  }

  /// Opens the editor session on a page document in an explicit editor mode.
  ///
  /// This is the canonical entry API. [mode] must be `preview` or `edit`;
  /// exits go through [closeEditor] and pure mode transitions through
  /// [setMode].
  void openEditorDocument(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    required WebsiteEditorMode mode,
    String? pageId,
    String? pageSlug,
  }) {
    // A programmatic open renders for its caller but does NOT grant the
    // untrusted-entry lease: URL/OAuth commands still require the identity
    // fingerprint from the single capability truth, and a lease revocation
    // (logout, tenant/user/role change) also demotes programmatic sessions.
    _stampDocumentOwnerFromLease();
    final changed = _activatePageSnapshot(
      blocks,
      settings,
      mode: mode,
      pageId: pageId,
      pageSlug: pageSlug,
    );
    if (changed) notifyListeners();
  }

  /// Typed owner of the OPEN document: the tenant and lease fingerprint that
  /// authorized it. Save/attribution boundaries validate against these
  /// fields; a session opened without a lease has no owner and can neither
  /// save nor survive an authority-unknown window.
  String? get documentOwnerTenantId => _documentOwnerLease?.storefrontTenantId;
  String? get documentOwnerLeaseFingerprint => _documentOwnerLease?.fingerprint;
  WebsiteEditorCapabilitySnapshot? _documentOwnerLease;

  void _stampDocumentOwnerFromLease() {
    final lease = _entryLease;
    if (lease != null && lease.granted) {
      _documentOwnerLease = lease;
    }
  }

  /// Activates a routed page document without changing the current mode.
  ///
  /// Shared by the Home, dynamic CMS and policy consumers once their data is
  /// loaded. Safe to call from `build`: it is idempotent for an unchanged
  /// document and defers its notification to the end of the frame.
  void activatePageDocument(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    if (!isInEditorContext) return;
    // The routed Dynamic/Policy consumers bind through here (never through
    // openEditorDocument): the granted lease stamps the document owner.
    _stampDocumentOwnerFromLease();
    final changed = _activatePageSnapshot(
      blocks,
      settings,
      mode: _mode,
      pageId: pageId,
      pageSlug: pageSlug,
    );
    if (changed) _notifyAfterFrame();
  }

  /// Test/migration alias of [openEditorDocument] with `mode: preview`.
  void enterPreviewMode(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    openEditorDocument(
      blocks,
      settings,
      mode: WebsiteEditorMode.preview,
      pageId: pageId,
      pageSlug: pageSlug,
    );
  }

  /// Test/migration alias of [openEditorDocument] with `mode: edit`.
  void enterEditMode(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    openEditorDocument(
      blocks,
      settings,
      mode: WebsiteEditorMode.edit,
      pageId: pageId,
      pageSlug: pageSlug,
    );
  }

  /// Transitions the FSM between `edit` and `preview` while preserving the
  /// active document and drafts. `public` delegates to [closeEditor].
  void setMode(WebsiteEditorMode next) {
    if (next == WebsiteEditorMode.public) {
      closeEditor();
      return;
    }
    assert(isInEditorContext,
        'setMode requires an open editor session; use openEditorDocument.');
    if (_mode == next &&
        _workspaceMode == WebsiteWorkspaceMode.pageEditor &&
        (next == WebsiteEditorMode.edit || _selectedBlockId == null)) {
      return;
    }
    _mode = next;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    if (next == WebsiteEditorMode.preview) _selectedBlockId = null;
    notifyListeners();
  }

  /// Applies a URL/OAuth-derived mode command. The URI is an input command
  /// only: it can request entering `preview` or `edit`, and it never exits an
  /// open session (`public` request is ignored; exits are owned by
  /// [closeEditor]).
  ///
  /// UNTRUSTED input is honored only after the single capability gate
  /// resolved to granted; anything else fails closed to the current (public)
  /// mode so an anonymous `?edit=true` deep link can never mount editor
  /// chrome or bypass the unpublished-site holding page.
  ///
  /// Safe to call from `build`: the field mutates synchronously so the caller
  /// renders the requested mode in the same frame, and the notification is
  /// deferred to the end of the frame.
  void applyRouteModeCommand(WebsiteEditorMode request) {
    if (request == WebsiteEditorMode.public) return;
    if (!editorEntryLeaseGranted) return;
    if (_mode == request) return;
    _mode = request;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    if (request == WebsiteEditorMode.preview) _selectedBlockId = null;
    _notifyAfterFrame();
  }

  /// Set device preview mode (desktop, tablet, mobile)
  void setDevicePreviewMode(DevicePreviewMode mode) {
    if (_devicePreviewMode == mode) return;
    _devicePreviewMode = mode;
    notifyListeners();
  }

  /// Closes the editor session completely (back to the visitor view).
  ///
  /// Idempotent with respect to the mode: a suspended session (mode already
  /// `public` with retained hidden drafts) is still fully cleared, so an
  /// identity-change revocation can never leave another identity's buckets
  /// behind.
  void closeEditor() {
    if (_mode == WebsiteEditorMode.public &&
        !_pageDraft.isActive &&
        !hasUnsavedChanges) {
      return;
    }
    _clearEditorSessionState();
    // A NORMAL close under a live granted lease keeps the session
    // attributable: close -> reopen -> sitewide save must work without a
    // new grant. Identity-change revocations null the lease FIRST, so this
    // restamp is a no-op there and every owner stays cleared.
    _restampSessionOwnerFromLease();
    // Deferred so revocations observed during a build stay build-safe; the
    // buckets themselves are already cleared synchronously above.
    _notifyAfterFrame();
  }

  void _restampSessionOwnerFromLease() {
    final lease = _entryLease;
    if (lease != null && lease.granted) {
      _sessionOwnerLease = lease;
    }
  }

  /// Synchronously clears the whole session: mode, document, page bucket,
  /// sitewide/SEO buckets, history, settings and the suspended-lease
  /// fingerprint. Never notifies by itself.
  void _clearEditorSessionState() {
    _mode = WebsiteEditorMode.public;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _selectedBlockId = null;
    _suspendedLease = null;
    _documentOwnerLease = null;
    _sessionOwnerLease = null;
    _clearActivePageDraftState();
    _clearSitewideAndSeoDrafts();
    _pageDraft.blocks = [];
    _pageDraft.history.clear();
    _pageDraft.historyIndex = -1;
    _settings = {};
    _pageDraft.pageId = null;
    _pageDraft.pageSlug = null;
    _pageDraft.isActive = false;
    _pageDraft.sessionRevision++;
  }

  /// Installs the database-confirmed block document without discarding edits
  /// made after the save snapshot was captured.
  ///
  /// When the live draft still matches [attemptedBlocks], the saved document
  /// becomes the sole history baseline. If it changed while the request was in
  /// flight, the fresh document becomes the discard baseline and the newer
  /// client draft remains active above it.
  void acknowledgeSavedBlocks({
    required List<Map<String, dynamic>> attemptedBlocks,
    required List<Map<String, dynamic>> freshBlocks,
  }) {
    final currentDraft = _deepCopyBlocks(_pageDraft.blocks);
    final attemptedDocument = _deepCopyBlocks(attemptedBlocks);
    final hasNewerDraft = !_deepEquals(currentDraft, attemptedDocument);

    _pageDraft.blocks = _deepCopyBlocks(freshBlocks);
    _rebaselineBlockHistory();

    if (hasNewerDraft) {
      _pageDraft.blocks = currentDraft;
      _pageDraft.history.add(_deepCopyBlocks(currentDraft));
      _pageDraft.historyIndex = 1;
      _pageDraft.hasUnsavedChanges = true;
      _reconcileTransientCanvasSelections();
    } else {
      _pageDraft.hasUnsavedChanges = false;
    }
    notifyListeners();
  }

  /// Select a block for editing
  void selectBlock(String? blockId) {
    _selectedBlockId = blockId;
    _selectionVersion++;
    debugPrint(
        '👉 [EditProvider] Block Selected: $blockId (v$_selectionVersion)');
    notifyListeners();
  }

  /// Update block data without notifying listeners (for real-time drag preview)
  /// Use this during drag operations to avoid rebuilding the entire widget tree
  void updateBlockDataSilent(String blockId, String key, dynamic value) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    final block = _pageDraft.blocks[blockIndex];
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    blockData[key] = _deepCopyValue(value);
    final nextBlock = sanitizeWebsiteBlockForPersistence({
      ...block,
      'block_data': blockData,
    });
    if (_deepEquals(nextBlock, block)) {
      // Same no-op guard as updateBlockData: a transient-only or same-value
      // write must never enable Guardar.
      return;
    }
    _pageDraft.blocks[blockIndex] = nextBlock;
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    // Don't call notifyListeners() - caller is responsible for UI updates
  }

  /// Update block data
  /// [saveHistory] - Set to false for transient updates (like activeElementId changes) to avoid history pollution
  void updateBlockData(String blockId, String key, dynamic value,
      {bool saveHistory = true}) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint('⚠️ [EditProvider] updateBlockData: block $blockId not found');
      return;
    }

    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    blockData[key] = _deepCopyValue(value);

    _syncDerivedActions(
      blockType: blockType,
      updatedKey: key,
      blockData: blockData,
    );
    final nextBlock = sanitizeWebsiteBlockForPersistence({
      ...block,
      'block_data': blockData,
    });
    if (_deepEquals(nextBlock, block)) {
      // The sanitized persisted document did not change, so the mutation was
      // transient-only (e.g. a legacy Canvas `activeElementId` write) or a
      // same-value write. Selection alone must never enable Guardar.
      debugPrint('ℹ️ [EditProvider] updateBlockData: blockId=$blockId, '
          'key=$key ignored (no persisted change)');
      return;
    }
    _pageDraft.blocks[blockIndex] = nextBlock;
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint('✅ [EditProvider] updateBlockData: blockId=$blockId, key=$key, '
        'hasUnsavedChanges=${_pageDraft.hasUnsavedChanges}');
    notifyListeners();
  }

  /// Update multiple block data keys atomically (single notification)
  /// Use this when updating related values that should be saved together
  void updateBlockDataMultiple(String blockId, Map<String, dynamic> updates,
      {bool saveHistory = true}) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint(
          '⚠️ [EditProvider] updateBlockDataMultiple: block $blockId not found');
      return;
    }

    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});

    // Apply all updates atomically
    for (final entry in updates.entries) {
      blockData[entry.key] = _deepCopyValue(entry.value);
    }

    // If multiple keys updated, sync derived actions if any CTA-related keys changed.
    final changedKeys = updates.keys.toSet();
    const ctaKeys = {
      'ctaText',
      'ctaLink',
      'buttonText',
      'buttonLink',
      'showCta',
      'actions',
      'label',
      'link',
      'style',
      'viewAllText',
      'viewAllLink',
      'showViewAll',
      'actionVariant',
    };
    if (changedKeys.intersection(ctaKeys).isNotEmpty) {
      _syncDerivedActions(
        blockType: blockType,
        updatedKey: 'multiple',
        blockData: blockData,
      );
    }

    final nextBlock = sanitizeWebsiteBlockForPersistence({
      ...block,
      'block_data': blockData,
    });
    if (_deepEquals(nextBlock, block)) {
      // Same no-op guard as updateBlockData: a transient-only or same-value
      // multi-update must never dirty the draft or pollute history.
      debugPrint('ℹ️ [EditProvider] updateBlockDataMultiple: blockId=$blockId '
          'ignored (no persisted change)');
      return;
    }
    _pageDraft.blocks[blockIndex] = nextBlock;
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint(
        '✅ [EditProvider] updateBlockDataMultiple: blockId=$blockId, keys=${updates.keys.join(", ")}');
    notifyListeners();
  }

  /// Atomically updates fields on one item in a schema-defined collection.
  ///
  /// [collectionKeys] must list the canonical key first and persisted aliases
  /// afterwards. The first key that is present in the latest document wins,
  /// including an explicitly empty canonical list. The resulting collection
  /// is then written to every key in one history entry and one notification.
  ///
  /// Legacy repeaters are index-owned. A stable [identityKey]/[identityValue]
  /// may be supplied only when the payload already persists that identity.
  bool updateBlockRepeaterItemMultiple(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required Map<String, dynamic> updates,
    String? identityKey,
    Object? identityValue,
    bool saveHistory = true,
  }) {
    if (collectionKeys.isEmpty || updates.isEmpty) return false;

    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint(
        '⚠️ [EditProvider] updateBlockRepeaterItemMultiple: '
        'block $blockId not found',
      );
      return false;
    }

    final block = _pageDraft.blocks[blockIndex];
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});

    Object? source;
    for (final key in collectionKeys) {
      if (blockData.containsKey(key)) {
        source = blockData[key];
        break;
      }
    }
    if (source is! List) {
      debugPrint(
        '⚠️ [EditProvider] updateBlockRepeaterItemMultiple: '
        'no list found for ${collectionKeys.join(", ")}',
      );
      return false;
    }

    final next = List<dynamic>.from(_deepCopyValue(source) as List);
    var resolvedIndex = itemIndex;
    if (identityKey != null && identityValue != null) {
      final identityIndex = next.indexWhere(
        (item) => item is Map && item[identityKey] == identityValue,
      );
      if (identityIndex != -1) resolvedIndex = identityIndex;
    }

    if (resolvedIndex < 0 || resolvedIndex >= next.length) {
      debugPrint(
        '⚠️ [EditProvider] updateBlockRepeaterItemMultiple: '
        'item $resolvedIndex is outside collection bounds ${next.length}',
      );
      return false;
    }
    final rawItem = next[resolvedIndex];
    if (rawItem is! Map) {
      debugPrint(
        '⚠️ [EditProvider] updateBlockRepeaterItemMultiple: '
        'item $resolvedIndex is not an object',
      );
      return false;
    }

    final item = Map<String, dynamic>.from(rawItem);
    for (final entry in updates.entries) {
      item[entry.key] = _deepCopyValue(entry.value);
    }
    next[resolvedIndex] = item;

    for (final key in collectionKeys) {
      blockData[key] = _deepCopyValue(next);
    }
    _pageDraft.blocks[blockIndex] = sanitizeWebsiteBlockForPersistence({
      ...block,
      'block_data': blockData,
    });
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint(
      '✅ [EditProvider] updateBlockRepeaterItemMultiple: '
      'blockId=$blockId, collections=${collectionKeys.join(", ")}, '
      'item=$resolvedIndex, keys=${updates.keys.join(", ")}',
    );
    notifyListeners();
    return true;
  }

  void _syncDerivedActions({
    required String blockType,
    required String updatedKey,
    required Map<String, dynamic> blockData,
  }) {
    final typeLower = blockType.trim().toLowerCase();
    final isCtaLike = typeLower == 'hero' ||
        typeLower == 'cta' ||
        typeLower == 'videobanner' ||
        typeLower == 'button' ||
        typeLower == 'products';
    if (!isCtaLike) return;

    // If user edits actions directly in the future, don't fight it.
    if (updatedKey == 'actions') return;

    final labelKeys = switch (typeLower) {
      'button' => const ['label', 'text'],
      'products' => const ['viewAllText'],
      _ => const ['ctaText', 'buttonText'],
    };
    final hrefKeys = switch (typeLower) {
      'button' => const ['link'],
      'products' => const ['viewAllLink'],
      _ => const ['ctaLink', 'buttonLink'],
    };
    final enabled = switch (typeLower) {
      'videobanner' => blockData['showCta'] != false,
      'products' => blockData['showViewAll'] != false,
      _ => true,
    };
    final action = WebsiteActionValue.resolvePrimary(
      blockData,
      labelKeys: labelKeys,
      hrefKeys: hrefKeys,
      variantKeys:
          typeLower == 'button' ? const ['style'] : const ['actionVariant'],
      defaultLabel:
          typeLower == 'products' ? 'Ver todos los productos' : 'Ver más',
      defaultVariant: typeLower == 'button'
          ? WebsiteActionVariant.fromStorage(blockData['style']?.toString())
          : WebsiteActionVariant.outline,
      enabled: enabled,
    );
    final effective = action ?? const WebsiteActionValue(label: '', href: '');
    blockData['actions'] =
        WebsiteActionValue.mergePrimary(blockData['actions'], effective);
    if (action == null) {
      if (enabled) {
        for (final key in hrefKeys) {
          blockData[key] = '';
        }
      }
      return;
    }
    for (final key in labelKeys) {
      blockData[key] = action.label;
    }
    for (final key in hrefKeys) {
      blockData[key] = action.href;
    }
    if (typeLower == 'button') {
      blockData['style'] = action.variant.storageValue;
    } else {
      blockData['actionVariant'] = action.variant.storageValue;
    }
  }

  /// Convenience: add a Canvas element to the currently selected Canvas block.
  /// Returns true if an element was added.
  bool addCanvasElementToSelectedCanvas(String elementType) {
    final selected = _selectedBlockId;
    if (selected == null) return false;
    return addCanvasElementToCanvasBlock(selected, elementType);
  }

  /// Add a Canvas element to a specific Canvas block by id.
  /// Returns true if successful.
  bool addCanvasElementToCanvasBlock(String canvasBlockId, String elementType) {
    final blockIndex =
        _pageDraft.blocks.indexWhere((b) => b['id'] == canvasBlockId);
    if (blockIndex == -1) return false;
    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    if (blockType == WebsiteBlockType.carousel.name) {
      final data = Map<String, dynamic>.from(block['block_data'] ?? const {});
      final rawSlides = data['slides'];
      if (rawSlides is! List || rawSlides.isEmpty) return false;
      final slides = rawSlides
          .whereType<Map>()
          .map((slide) => Map<String, dynamic>.from(slide))
          .toList();
      if (slides.isEmpty) return false;
      final slideIndex = carouselSlideSelection(canvasBlockId, slides.length);
      final slide = Map<String, dynamic>.from(slides[slideIndex]);
      final rawElements = slide['elements'];
      final elements = rawElements is List
          ? rawElements
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final id = 'el_${DateTime.now().microsecondsSinceEpoch}';
      elements.add(createCanvasElement(id: id, type: elementType));
      slides[slideIndex] = {
        ...slide,
        'useComposition': true,
        'elements': elements,
      };
      updateBlockData(canvasBlockId, 'slides', slides);
      selectCanvasElement(
        canvasBlockId,
        id,
        slideIndex: slideIndex,
        slideCount: slides.length,
      );
      return true;
    }
    if (blockType != WebsiteBlockType.canvas.name) return false;

    final data = Map<String, dynamic>.from(block['block_data'] ?? {});
    final rawElements = data['elements'];
    final elements = rawElements is List
        ? rawElements
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'el_$now';
    final next = createCanvasElement(id: id, type: elementType);

    elements.add(next);
    updateBlockData(canvasBlockId, 'elements', elements);
    selectCanvasElement(canvasBlockId, id);
    return true;
  }

  /// Save current state to history
  void _saveToHistory() {
    _pageDraft.blocks = _deepCopyBlocks(_pageDraft.blocks);
    _reconcileTransientCanvasSelections();

    // Remove any future history if we're not at the end
    if (_pageDraft.historyIndex < _pageDraft.history.length - 1) {
      _pageDraft.history
          .removeRange(_pageDraft.historyIndex + 1, _pageDraft.history.length);
    }

    // Deep copy blocks
    final snapshot = _deepCopyBlocks(_pageDraft.blocks);
    _pageDraft.history.add(snapshot);
    _pageDraft.historyIndex = _pageDraft.history.length - 1;

    // Limit history size
    if (_pageDraft.history.length > _maxHistory) {
      // Keep index 0: it is the saved/loaded discard baseline.
      _pageDraft.history.removeAt(1);
      _pageDraft.historyIndex--;
    }

    debugPrint('💾 [EditProvider] Saved to history: '
        'index=${_pageDraft.historyIndex}, '
        'total=${_pageDraft.history.length}, '
        'canUndo=$canUndo, canRedo=$canRedo');
  }

  /// Undo last change
  void undo() {
    if (!canUndo) return;

    _pageDraft.historyIndex--;
    _pageDraft.blocks =
        _deepCopyBlocks(_pageDraft.history[_pageDraft.historyIndex]);
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = _pageDraft.historyIndex != 0;
    debugPrint(
      '⏪ [EditProvider] Undo: index=${_pageDraft.historyIndex}',
    );
    notifyListeners();
  }

  /// Redo last undone change
  void redo() {
    if (!canRedo) return;

    _pageDraft.historyIndex++;
    _pageDraft.blocks =
        _deepCopyBlocks(_pageDraft.history[_pageDraft.historyIndex]);
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    debugPrint(
      '⏩ [EditProvider] Redo: index=${_pageDraft.historyIndex}',
    );
    notifyListeners();
  }

  /// Get block by ID
  Map<String, dynamic>? getBlock(String blockId) {
    try {
      return _deepUnmodifiableMap(
        _pageDraft.blocks.firstWhere((b) => b['id'] == blockId),
      );
    } catch (_) {
      return null;
    }
  }

  /// Get block data
  Map<String, dynamic> getBlockData(String blockId) {
    final block = getBlock(blockId);
    return Map<String, dynamic>.from(block?['block_data'] ?? {});
  }

  /// Move block up
  void moveBlockUp(String blockId) {
    debugPrint('🔼 [EditProvider] moveBlockUp called for blockId: $blockId');
    final index = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    debugPrint('🔼 [EditProvider] Block index: $index');
    if (index <= 0) {
      debugPrint(
          '🔼 [EditProvider] Cannot move up - already at top or not found');
      return;
    }

    final block = _pageDraft.blocks.removeAt(index);
    _pageDraft.blocks.insert(index - 1, block);

    // Update sort_order for all blocks to match new positions
    _updateSortOrders();

    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    debugPrint('🔼 [EditProvider] Moved block from $index to ${index - 1}');
    notifyListeners();
  }

  /// Move block down
  void moveBlockDown(String blockId) {
    debugPrint('🔽 [EditProvider] moveBlockDown called for blockId: $blockId');
    final index = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    debugPrint(
        '🔽 [EditProvider] Block index: $index, total blocks: ${_pageDraft.blocks.length}');
    if (index == -1 || index >= _pageDraft.blocks.length - 1) {
      debugPrint(
          '🔽 [EditProvider] Cannot move down - already at bottom or not found');
      return;
    }

    final block = _pageDraft.blocks.removeAt(index);
    _pageDraft.blocks.insert(index + 1, block);

    // Update sort_order for all blocks to match new positions
    _updateSortOrders();

    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    debugPrint('🔽 [EditProvider] Moved block from $index to ${index + 1}');
    notifyListeners();
  }

  /// Reorder blocks via drag-and-drop (Structure panel).
  void reorderBlocks(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pageDraft.blocks.length) return;
    if (newIndex < 0) return;
    if (newIndex > _pageDraft.blocks.length) {
      newIndex = _pageDraft.blocks.length;
    }

    // Flutter's ReorderableListView gives newIndex in the "post-removal" space.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final item = _pageDraft.blocks.removeAt(oldIndex);
    _pageDraft.blocks.insert(newIndex, item);

    _updateSortOrders();
    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
  }

  /// Update sort_order values to match current list positions
  void _updateSortOrders() {
    for (int i = 0; i < _pageDraft.blocks.length; i++) {
      _pageDraft.blocks[i] = {
        ..._pageDraft.blocks[i],
        'sort_order': i,
        'order_index': i,
      };
    }
  }

  /// Delete block
  void deleteBlock(String blockId) {
    final previousLength = _pageDraft.blocks.length;
    _pageDraft.blocks.removeWhere((b) => b['id'] == blockId);
    if (_pageDraft.blocks.length == previousLength) return;
    if (_selectedBlockId == blockId) {
      _selectedBlockId = null;
    }
    // Update sort_order for remaining blocks
    _updateSortOrders();
    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
  }

  /// Duplicate block
  void duplicateBlock(String blockId) {
    final index = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (index == -1) return;

    final original = _pageDraft.blocks[index];
    final duplicate = _deepCopyMap(original);
    duplicate['id'] = _uuid.v4(); // Use proper UUID for database compatibility

    _pageDraft.blocks.insert(index + 1, duplicate);
    _updateSortOrders(); // Update sort_order values after duplicate
    _selectedBlockId = duplicate['id'] as String?;
    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
    debugPrint(
        '📋 [EditProvider] Duplicated block at index $index with new ID: ${duplicate['id']}');
  }

  /// Toggle block visibility
  void toggleBlockVisibility(String blockId) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    final block = _pageDraft.blocks[blockIndex];
    _pageDraft.blocks[blockIndex] = {
      ...block,
      'is_visible': !(block['is_visible'] ?? true),
    };
    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
  }

  /// Add a new block
  void addBlock(String blockType, {int? atIndex}) {
    final newBlock = {
      'id': _uuid.v4(), // Use proper UUID for database compatibility
      'block_type': blockType,
      'block_data': _defaultDataForType(blockType),
      'is_visible': true,
      'sort_order': _pageDraft.blocks.length,
    };

    if (atIndex != null &&
        atIndex >= 0 &&
        atIndex <= _pageDraft.blocks.length) {
      _pageDraft.blocks.insert(atIndex, newBlock);
    } else {
      _pageDraft.blocks.add(newBlock);
    }

    // Update sort_order for all blocks
    _updateSortOrders();

    _selectedBlockId = newBlock['id'] as String?;
    _selectionVersion++;
    _pageDraft.hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
  }

  Map<String, dynamic> _defaultDataForType(String blockType) {
    final normalized = blockType.trim();
    for (final type in WebsiteBlockType.values) {
      if (type.name.toLowerCase() == normalized.toLowerCase()) {
        return _deepCopyMap(
          WebsiteBlockRegistry.definitionFor(type).defaultData,
        );
      }
    }
    return _legacyDefaultDataForUnknownType(blockType);
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) =>
      source.map((key, value) => MapEntry(key, _deepCopyValue(value)));

  Map<String, dynamic> _deepUnmodifiableMap(Map<String, dynamic> source) =>
      Map<String, dynamic>.unmodifiable(
        source.map(
          (key, value) => MapEntry(key, _deepUnmodifiableValue(value)),
        ),
      );

  dynamic _deepUnmodifiableValue(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        value.map(
          (key, nested) =>
              MapEntry(key.toString(), _deepUnmodifiableValue(nested)),
        ),
      );
    }
    if (value is List) {
      return List<dynamic>.unmodifiable(
        value.map(_deepUnmodifiableValue),
      );
    }
    if (value is Set) {
      return Set<dynamic>.unmodifiable(
        value.map(_deepUnmodifiableValue),
      );
    }
    return value;
  }

  WebsiteNavigation _immutableNavigation(WebsiteNavigation navigation) {
    return navigation.copyWith(
      children: List<WebsiteNavigation>.unmodifiable(
        navigation.children.map(_immutableNavigation),
      ),
    );
  }

  dynamic _deepCopyValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _deepCopyValue(nested)),
      );
    }
    if (value is List) return value.map(_deepCopyValue).toList();
    return value;
  }

  bool _deepEquals(dynamic left, dynamic right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_deepEquals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_deepEquals(left[index], right[index])) return false;
      }
      return true;
    }
    if (left is Set && right is Set) {
      return left.length == right.length && left.containsAll(right);
    }
    return left == right;
  }

  void _mergeSavedSettingsBaseline(Map<String, String> savedSnapshot) {
    _settings.addAll(savedSnapshot);
  }

  void _removeMatchingMapEntries<K, V>(
    Map<K, V> current,
    Map<K, V> savedSnapshot, {
    bool Function(V left, V right)? equals,
  }) {
    final hasSameValue =
        equals ?? (V left, V right) => _deepEquals(left, right);
    for (final entry in savedSnapshot.entries) {
      if (current.containsKey(entry.key) &&
          hasSameValue(current[entry.key] as V, entry.value)) {
        current.remove(entry.key);
      }
    }
  }

  void _removeMatchingMapEntry<K, V>(
    Map<K, V> current,
    Map<K, V> savedSnapshot,
    K key, {
    bool Function(V left, V right)? equals,
  }) {
    if (!current.containsKey(key) || !savedSnapshot.containsKey(key)) return;
    final hasSameValue =
        equals ?? (V left, V right) => _deepEquals(left, right);
    final currentValue = current[key] as V;
    final savedValue = savedSnapshot[key] as V;
    if (hasSameValue(currentValue, savedValue)) {
      current.remove(key);
    }
  }

  bool _navigationHasSamePersistedValue(
    WebsiteNavigation left,
    WebsiteNavigation right,
  ) {
    return left.id == right.id &&
        left.tenantId == right.tenantId &&
        left.menuLocation == right.menuLocation &&
        left.label == right.label &&
        left.icon == right.icon &&
        left.linkType == right.linkType &&
        left.linkValue == right.linkValue &&
        left.openInNewTab == right.openInNewTab &&
        left.parentId == right.parentId &&
        left.orderIndex == right.orderIndex &&
        left.isVisible == right.isVisible &&
        left.showOnDesktop == right.showOnDesktop &&
        left.showOnMobile == right.showOnMobile &&
        left.cssClass == right.cssClass &&
        left.highlight == right.highlight;
  }

  /// Compatibility fallback for marketplace/legacy block types not registered
  /// in [WebsiteBlockRegistry]. Registered blocks must never add defaults here.
  Map<String, dynamic> _legacyDefaultDataForUnknownType(String blockType) {
    switch (blockType) {
      case 'hero':
        return {
          'title': 'Servicios y Productos de Bicicleta',
          'subtitle': 'Todo lo que necesitas para tu bicicleta',
          'buttonText': 'Ver Productos',
          'buttonLink': '/productos',
          'backgroundImage': '',
        };
      case 'carousel':
        return {
          'slides': [
            {
              'title': 'Bienvenido a nuestra tienda',
              'subtitle': 'Descubre los mejores productos para tu bicicleta',
              'imageUrl': '',
              'ctaText': 'Ver catálogo',
              'ctaLink': '/productos',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
            {
              'title': 'Servicio técnico certificado',
              'subtitle': 'Agenda tu mantención sin salir de casa',
              'imageUrl': '',
              'ctaText': 'Agendar ahora',
              'ctaLink': '/tienda/servicios',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
          ],
          'autoPlay': true,
          'intervalSeconds': 5,
          'showIndicators': true,
          'showArrows': true,
          'animation': 'slide',
        };
      case 'products':
        return {
          'title': 'Productos Destacados',
          'subtitle': 'Los mejores productos para ti',
          'showPrice': true,
          'maxProducts': 8,
        };
      case 'text':
        return {
          'text': 'Haz clic para editar este texto',
          'preset': 'paragraph', // heading | subheading | paragraph | caption
          'maxWidth': 800,
          'formatting': const <String, dynamic>{},
        };
      case 'button':
        return {
          'label': 'Botón',
          'link': '/',
          'style': 'filled', // filled | outline | text
        };
      case 'divider':
        return {
          'thickness': 1.0,
          'color': '#E0E0E0',
          'widthPct': 1.0,
        };
      case 'about':
        return {
          'title': 'Sobre Nosotros',
          'description':
              'Somos una tienda especializada en bicicletas y accesorios. Contamos con años de experiencia brindando productos de calidad y el mejor servicio a nuestros clientes.',
          'image': '',
        };
      case 'services':
        return {
          'title': 'Nuestros Servicios',
          'services': [
            {
              'icon': 'build',
              'title': 'Reparación',
              'description': 'Servicio técnico profesional'
            },
            {
              'icon': 'tune',
              'title': 'Mantención',
              'description': 'Mantención preventiva y correctiva'
            },
            {
              'icon': 'shopping_bag',
              'title': 'Venta',
              'description': 'Bicicletas y accesorios'
            },
          ],
        };
      case 'features':
        return {
          'title': '¿Por qué elegirnos?',
          'features': [
            {
              'icon': 'local_shipping',
              'title': 'Envío Rápido',
              'description': 'Envíos a Chile continental en 3 a 12 días hábiles'
            },
            {
              'icon': 'verified',
              'title': 'Productos Originales',
              'description': 'Garantía de autenticidad'
            },
            {
              'icon': 'support_agent',
              'title': 'Atención Personalizada',
              'description': 'Asesoramiento experto'
            },
          ],
        };
      case 'testimonials':
        return {
          'title': 'Lo que dicen nuestros clientes',
          'testimonials': [
            {
              'name': 'Cliente Satisfecho',
              'text': 'Excelente servicio y productos de calidad.',
              'rating': 5
            },
          ],
        };
      case 'stats':
        return {
          'title': 'Nuestros Números',
          'stats': [
            {'value': '1000+', 'label': 'Clientes Satisfechos'},
            {'value': '500+', 'label': 'Productos'},
            {'value': '10+', 'label': 'Años de Experiencia'},
          ],
        };
      case 'team':
        return {
          'title': 'Nuestro Equipo',
          'members': [
            {'name': 'Nombre', 'role': 'Cargo', 'image': ''},
          ],
        };
      case 'faq':
        return {
          'title': 'Preguntas Frecuentes',
          'questions': [
            {
              'question': '¿Cuál es el horario de atención?',
              'answer': 'Lunes a Viernes de 9:00 a 18:00'
            },
            {
              'question': '¿Hacen envíos a regiones?',
              'answer': 'Sí, enviamos a Chile continental'
            },
          ],
        };
      case 'pricing':
        return {
          'title': 'Nuestros Planes',
          'plans': [
            {
              'name': 'Básico',
              'price': '9.990',
              'features': ['Feature 1', 'Feature 2']
            },
            {
              'name': 'Pro',
              'price': '19.990',
              'features': ['Feature 1', 'Feature 2', 'Feature 3'],
              'highlighted': true
            },
          ],
        };
      case 'contact':
        return {
          'title': 'Contáctanos',
          'subtitle': 'Estamos aquí para ayudarte',
          'showMap': false,
          'showForm': true,
        };
      case 'cta':
        return {
          'title': '¿Listo para empezar?',
          'description': 'Visítanos o contáctanos para más información',
          'buttonText': 'Contactar',
          'buttonLink': '/tienda/contacto',
        };
      case 'gallery':
        return {
          'title': 'Galería',
          'images': [],
        };
      case 'categoryGrid':
        return {
          'title': 'Explora Nuestras Categorías',
          'subtitle': 'Encuentra lo que buscas',
          'categories': [
            {
              'title': 'Mountain Bike',
              'subtitle': 'Conquista cualquier terreno',
              'imageUrl': '',
              'ctaText': 'Ver colección',
              'ctaLink': '/productos',
              'size': 'large',
            },
            {
              'title': 'Ruta',
              'subtitle': 'Velocidad y rendimiento',
              'imageUrl': '',
              'ctaText': 'Ver colección',
              'ctaLink': '/productos',
              'size': 'large',
            },
            {
              'title': 'Urbano',
              'subtitle': 'Movilidad en la ciudad',
              'imageUrl': '',
              'ctaText': 'Ver gama',
              'ctaLink': '/productos',
              'size': 'medium',
            },
            {
              'title': 'Accesorios',
              'subtitle': 'Todo lo que necesitas',
              'imageUrl': '',
              'ctaText': 'Explorar',
              'ctaLink': '/productos',
              'size': 'medium',
            },
          ],
        };
      case 'videoBanner':
        return {
          'title': 'Vive la Aventura',
          'subtitle': 'La experiencia de rodar sin límites',
          'imageUrl': '',
          'videoUrl': '',
          'ctaText': 'Descubrir más',
          'ctaLink': '/productos',
          'showCta': true,
          'overlayOpacity': 0.5,
        };
      case 'partnersBanner':
        return {
          'title': 'Nuestras Ubicaciones',
          'imageUrl': '',
          'items': [
            'Santiago, Chile',
            'Viña del Mar, Chile',
            'Concepción, Chile',
          ],
        };
      case 'brandLogos':
        return {
          'title': 'MARCAS',
          'accentColor': '#E53935',
          'brands': [
            {'name': 'Marca 1', 'imageUrl': '', 'link': ''},
            {'name': 'Marca 2', 'imageUrl': '', 'link': ''},
            {'name': 'Marca 3', 'imageUrl': '', 'link': ''},
          ],
        };
      default:
        return {};
    }
  }
}

class _WebsiteEditorPageDraftState {
  bool isActive = false;
  String? pageId;
  String? pageSlug;
  int sessionRevision = 0;
  List<Map<String, dynamic>> blocks = [];
  bool hasUnsavedChanges = false;
  final List<List<Map<String, dynamic>>> history = [];
  int historyIndex = -1;
}

class _WebsiteEditorSitewideDraftState {
  bool hasHeaderChanges = false;
  Map<String, String> pendingHeaderSettings = {};

  bool hasSiteSettingsChanges = false;
  Map<String, String> pendingSiteSettings = {};

  bool hasFooterChanges = false;
  Map<String, String> pendingFooterSettings = {};
  List<String>? pendingFooterSectionOrder;
  Map<String, List<String>> pendingFooterLinkOrder = {};
  final Map<String, String> pendingFooterNavLabels = {};
  final Map<String, NavLinkType> pendingFooterNavLinkTypes = {};
  final Map<String, String?> pendingFooterNavLinkValues = {};
  final Map<String, bool> pendingFooterNavOpenInNewTab = {};
  final Map<String, WebsiteNavigation> pendingFooterNavItems = {};
  final Map<String, WebsiteNavigation> pendingFooterNavCreates = {};
  final Set<String> pendingFooterNavDeletes = {};

  bool hasThemeChanges = false;
  Map<String, String> pendingThemeSettings = {};
}

class _WebsiteEditorSeoDraftState {
  bool hasChanges = false;
  final Map<String, Map<String, String>> pendingByRoute = {};
}

String _normalizePageSlug(String? value) {
  var normalized = value?.trim().toLowerCase() ?? '';
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized == 'home' || normalized == 'inicio' ? '' : normalized;
}
