import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../models/website_page_models.dart';
import '../models/website_action.dart';
import '../models/website_editor_capability.dart';
import '../models/website_block_document_sanitizer.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_public_visibility.dart';
import '../models/canvas_element_factory.dart';
import '../models/website_canvas_manipulation.dart';
import '../models/website_canvas_layer_identity.dart';
import '../models/website_canvas_responsive_document.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_responsive_field_state.dart';
import '../models/website_repeater_mutation.dart';

export '../models/website_repeater_mutation.dart';

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

/// Editor chrome that is selectable but is not a block.
///
/// The published header and footer are edited through the same selection field
/// as blocks, under a reserved id — that is how the desktop inspector has
/// always reached them (`_EditBlockTab` branches on these two ids before it
/// looks the selection up in the document). Naming them makes that contract
/// explicit instead of leaving two bare strings scattered across the module,
/// and it is what lets the rest of the editor tell "chrome is selected" apart
/// from "the selection points at a block that no longer exists".
///
/// They are deliberately NOT rows in `blocks`: the header is site-wide
/// settings, not page content, and inserting a synthetic block for it would
/// put a thing in the document that save, reorder, undo and the block registry
/// would all have to learn to skip.
enum WebsiteEditorChromeTarget {
  header('header', 'Encabezado'),
  footer('footer', 'Pie de página');

  const WebsiteEditorChromeTarget(this.selectionId, this.label);

  /// The reserved value carried by `selectedBlockId`.
  final String selectionId;

  /// What the operator is told they are editing.
  final String label;

  static WebsiteEditorChromeTarget? forSelection(String? selectionId) {
    if (selectionId == null) return null;
    for (final target in values) {
      if (target.selectionId == selectionId) return target;
    }
    return null;
  }
}

/// Independently persisted site-wide draft buckets.
///
/// Async controls bind to one bucket instead of borrowing the active page
/// document. A page route may change while a header/theme/footer picker is
/// open; the site-wide session remains the owner, while any write inside the
/// same bucket invalidates the pending intent through that bucket's epoch.
enum WebsiteSitewideDraftBucket {
  header,
  siteSettings,
  theme,
  footer,
}

/// Canonical synthetic source owned by footer navigation dialogs.
///
/// Footer navigation is persisted outside `website_settings`, but it belongs
/// to the footer draft bucket. Naming its aggregate source lets the same
/// site-wide intent guard settings and navigation without a second FSM.
abstract final class WebsiteSitewideAsyncSourceKey {
  static const String footerNavigation = '@footer/navigation';
}

/// A request to bring one block back into view after an operation moved it.
///
/// Typed and revisioned on purpose. The provider owns *what* must become
/// visible; the canvas owns *how* it scrolls. A bare block id could not tell a
/// repeated move of the same block from a stale request already served, so the
/// revision is what the canvas compares — never coordinates, which only the
/// laid-out canvas knows.
@immutable
class WebsiteEditorBlockRevealRequest {
  const WebsiteEditorBlockRevealRequest({
    required this.blockId,
    required this.revision,
  });

  final String blockId;

  /// Monotonic per session. Two consecutive moves of the same block are two
  /// distinct requests.
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is WebsiteEditorBlockRevealRequest &&
      other.blockId == blockId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(blockId, revision);

  @override
  String toString() => 'WebsiteEditorBlockRevealRequest($blockId, v$revision)';
}

/// The persisted node owned by one inline manipulation.
///
/// Root fields and repeater-item fields share the same transaction contract,
/// but an item must retain its collection and stable identity. Keeping that
/// distinction typed prevents a stale inline editor from redirecting a write
/// to a sibling item after a reorder.
@immutable
sealed class WebsiteInlineManipulationOwner {
  const WebsiteInlineManipulationOwner();
}

@immutable
final class WebsiteInlineBlockOwner extends WebsiteInlineManipulationOwner {
  const WebsiteInlineBlockOwner();
}

@immutable
final class WebsiteInlineRepeaterOwner extends WebsiteInlineManipulationOwner {
  WebsiteInlineRepeaterOwner({
    required List<String> collectionKeys,
    required this.itemIndex,
    this.identityKey,
    this.identityValue,
  }) : collectionKeys = List<String>.unmodifiable(collectionKeys);

  final List<String> collectionKeys;
  final int itemIndex;
  final String? identityKey;
  final Object? identityValue;
}

/// One responsive property participating in an inline transaction.
///
/// [sharedCompanionKeys] are compatibility aliases. They are updated only
/// when the captured write scope is shared; a viewport override owns only the
/// canonical key.
@immutable
class WebsiteInlineManipulationProperty {
  WebsiteInlineManipulationProperty({
    required this.canonicalKey,
    required this.policy,
    Iterable<String> sharedCompanionKeys = const <String>[],
  }) : sharedCompanionKeys = Set<String>.unmodifiable(
          sharedCompanionKeys.where((key) => key != canonicalKey),
        );

  factory WebsiteInlineManipulationProperty.fromSchema(
    WebsiteBlockFieldSchema schema, {
    Iterable<String> sharedCompanionKeys = const <String>[],
  }) {
    return WebsiteInlineManipulationProperty(
      canonicalKey: schema.key,
      policy: schema.responsivePolicy,
      sharedCompanionKeys: <String>{
        ...schema.migrationAliases,
        ...sharedCompanionKeys,
      },
    );
  }

  final String canonicalKey;
  final WebsiteResponsivePropertyPolicy policy;
  final Set<String> sharedCompanionKeys;
}

/// Exact target rendered when an inline interaction began.
@immutable
class WebsiteInlineManipulationTarget {
  WebsiteInlineManipulationTarget({
    required this.blockId,
    required this.owner,
    required this.viewport,
    required Iterable<WebsiteInlineManipulationProperty> properties,
    this.requiresSelection = true,
  }) : properties = List<WebsiteInlineManipulationProperty>.unmodifiable(
          properties,
        );

  final String blockId;
  final WebsiteInlineManipulationOwner owner;
  final WebsiteViewport viewport;
  final List<WebsiteInlineManipulationProperty> properties;
  final bool requiresSelection;
}

/// Immutable optimistic lease captured before an inline recognizer enters the
/// gesture arena.
///
/// Equality deliberately remains identity-based. Two arms that look identical
/// still carry distinct monotonic generations, so an old pointer can never
/// adopt a later arm (the ABA case).
class WebsiteInlineManipulationLease {
  WebsiteInlineManipulationLease._({
    required Object ownerIdentity,
    required this.target,
    required this.generation,
    required this.pageId,
    required this.pageSlug,
    required this.documentSessionRevision,
    required this.documentEpoch,
    required this.selectionVersion,
    required this.stateEpoch,
    required this.blockStateEpoch,
    required Map<String, dynamic> sourceBlock,
    required Map<String, WebsiteWriteScope> writeScopes,
  })  : _ownerIdentity = ownerIdentity,
        sourceBlock = Map<String, dynamic>.unmodifiable(sourceBlock),
        writeScopes = Map<String, WebsiteWriteScope>.unmodifiable(writeScopes);

  final Object _ownerIdentity;
  final WebsiteInlineManipulationTarget target;
  final int generation;
  final String? pageId;
  final String? pageSlug;
  final int documentSessionRevision;
  final int documentEpoch;
  final int selectionVersion;
  final int stateEpoch;
  final int blockStateEpoch;
  final Map<String, dynamic> sourceBlock;
  final Map<String, WebsiteWriteScope> writeScopes;

  bool _consumed = false;

  bool _consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

/// Outcome of one one-shot discrete inline lease.
///
/// `unchanged` is admitted (the lease was current) but intentionally creates
/// no history. A binding may recapture after it. `rejected` is stale or invalid
/// and must never be refreshed from that callback.
enum WebsiteInlineMutationResult {
  committed,
  unchanged,
  rejected;

  bool get accepted => this != WebsiteInlineMutationResult.rejected;
  bool get changed => this == WebsiteInlineMutationResult.committed;
}

/// One immutable, one-shot authority token for an asynchronous editor intent.
///
/// Pickers, confirmation dialogs and catalogs yield control before they
/// return. Without a captured owner, their result can otherwise land in a
/// different page or in a new block that happens to reuse the same id. This
/// token does not claim an inline/Canvas gesture session and never notifies;
/// it only lets the provider validate the exact owner synchronously when the
/// asynchronous surface returns.
class WebsiteEditorAsyncIntent {
  WebsiteEditorAsyncIntent._({
    required Object ownerIdentity,
    required this.generation,
    required this.blockId,
    required this.requiresSelection,
    required this.pageId,
    required this.pageSlug,
    required this.documentSessionRevision,
    required this.documentEpoch,
    required this.selectionVersion,
    required this.stateEpoch,
    required this.blockStateEpoch,
    required Map<String, dynamic>? sourceBlock,
  })  : _ownerIdentity = ownerIdentity,
        sourceBlock = sourceBlock == null
            ? null
            : Map<String, dynamic>.unmodifiable(sourceBlock);

  final Object _ownerIdentity;
  final int generation;
  final String? blockId;
  final bool requiresSelection;
  final String? pageId;
  final String? pageSlug;
  final int documentSessionRevision;
  final int documentEpoch;
  final int selectionVersion;
  final int stateEpoch;
  final int blockStateEpoch;
  final Map<String, dynamic>? sourceBlock;

  bool _consumed = false;

  bool _consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

/// Provider-owned editing session for a continuous page-block field.
///
/// Each input event still updates the live preview, but all accepted events
/// replace one provisional history slot. The provider keeps the exact initial
/// document/history so Escape or a net-zero edit can restore it without
/// clobbering another operation. Callers only transport this opaque token.
class WebsiteContinuousFieldEdit {
  WebsiteContinuousFieldEdit._({
    required Object ownerIdentity,
    required this.blockId,
    required this.scopeKey,
    required Object? baselineValue,
    required WebsiteEditorAsyncIntent intent,
    required List<Map<String, dynamic>> initialBlocks,
    required List<List<Map<String, dynamic>>> initialHistory,
    required this.initialHistoryIndex,
  })  : _ownerIdentity = ownerIdentity,
        _baselineValue = _deepCopyContinuousValue(baselineValue),
        _intent = intent,
        _initialBlocks = initialBlocks,
        _initialHistory = initialHistory;

  final Object _ownerIdentity;
  final String blockId;
  final String scopeKey;
  final Object? _baselineValue;
  WebsiteEditorAsyncIntent _intent;
  final List<Map<String, dynamic>> _initialBlocks;
  final List<List<Map<String, dynamic>>> _initialHistory;
  final int initialHistoryIndex;

  bool _active = true;
  bool _hasWrites = false;
}

Object? _deepCopyContinuousValue(Object? value) {
  if (value is Map) {
    return value.map<Object?, Object?>(
      (key, nested) => MapEntry(key, _deepCopyContinuousValue(nested)),
    );
  }
  if (value is List) return value.map(_deepCopyContinuousValue).toList();
  if (value is Set) return value.map(_deepCopyContinuousValue).toSet();
  return value;
}

/// One immutable, one-shot authority token for a site-wide async control.
///
/// Unlike [WebsiteEditorAsyncIntent], this token deliberately does not bind a
/// page id or block selection. Header, theme and footer drafts survive routed
/// page changes and are owned by the editor session. The provider instance,
/// session context, authority generation, bucket epoch and exact source-key
/// snapshot must all still match when the async surface returns.
class WebsiteSitewideAsyncIntent {
  WebsiteSitewideAsyncIntent._({
    required Object ownerIdentity,
    required this.generation,
    required this.bucket,
    required this.sessionEpoch,
    required this.entryLeaseGeneration,
    required this.entryLeaseIdentityRevision,
    required this.sessionOwnerTenantId,
    required this.sessionOwnerLeaseFingerprint,
    required this.bucketEpoch,
    required Map<String, dynamic> sourceValues,
  })  : _ownerIdentity = ownerIdentity,
        sourceValues = Map<String, dynamic>.unmodifiable(sourceValues);

  final Object _ownerIdentity;
  final int generation;
  final WebsiteSitewideDraftBucket bucket;
  final int sessionEpoch;
  final int entryLeaseGeneration;
  final int entryLeaseIdentityRevision;
  final String? sessionOwnerTenantId;
  final String? sessionOwnerLeaseFingerprint;
  final int bucketEpoch;
  final Map<String, dynamic> sourceValues;

  bool _consumed = false;

  bool _consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

/// One immutable, one-shot authority token for a semantic repeater command.
///
/// The provider constructs it from an exact page/block source. Consumers can
/// only hand it back once; equality remains identity-based so a callback from
/// an older build cannot adopt an equal-looking later arm.
class WebsiteRepeaterMutationLease {
  WebsiteRepeaterMutationLease._({
    required Object ownerIdentity,
    required this.target,
    required this.generation,
    required this.pageId,
    required this.pageSlug,
    required this.documentSessionRevision,
    required this.documentEpoch,
    required this.selectionVersion,
    required this.stateEpoch,
    required this.blockStateEpoch,
    required Map<String, dynamic> sourceBlock,
  })  : _ownerIdentity = ownerIdentity,
        sourceBlock = Map<String, dynamic>.unmodifiable(sourceBlock);

  final Object _ownerIdentity;
  final WebsiteRepeaterCollectionTarget target;
  final int generation;
  final String? pageId;
  final String? pageSlug;
  final int documentSessionRevision;
  final int documentEpoch;
  final int selectionVersion;
  final int stateEpoch;
  final int blockStateEpoch;
  final Map<String, dynamic> sourceBlock;

  bool _consumed = false;

  bool _consume() {
    if (_consumed) return false;
    _consumed = true;
    return true;
  }
}

class _AppliedWebsiteRepeaterMutation {
  const _AppliedWebsiteRepeaterMutation({
    required this.owner,
    required this.outcome,
  });

  final Map<String, dynamic> owner;
  final WebsiteRepeaterMutationOutcome outcome;
}

@immutable
class _PreparedInlineManipulationArm {
  const _PreparedInlineManipulationArm({
    required this.generation,
    required this.property,
    required this.pageId,
    required this.pageSlug,
    required this.documentSessionRevision,
    required this.documentEpoch,
  });

  final int generation;
  final WebsiteInlineManipulationProperty property;
  final String? pageId;
  final String? pageSlug;
  final int documentSessionRevision;
  final int documentEpoch;
}

/// Provider for website inline edit mode state.
/// Tracks edit mode, selected block, and pending changes.
///
/// Two modes:
/// - Preview mode: Shows the top bar (isPreviewMode = true)
/// - Edit mode: Shows the side panel (isEditMode = true)
class WebsiteEditModeProvider extends ChangeNotifier {
  int _navigationStateRevision = 0;
  int _pageDocumentEpoch = 0;
  int _inlineManipulationGeneration = 0;
  int _repeaterMutationGeneration = 0;
  int _asyncIntentGeneration = 0;
  final Object _asyncIntentOwnerIdentity = Object();
  int _sitewideAsyncSessionEpoch = 0;
  int _inlineManipulationStateEpoch = 0;
  final Map<String, int> _inlineManipulationBlockEpochs = {};
  WebsiteInlineManipulationLease? _inlineManipulationSession;
  _PreparedInlineManipulationArm? _preparedInlineManipulationArm;
  WebsiteContinuousFieldEdit? _activeContinuousFieldEdit;
  bool _committingContinuousFieldEdit = false;
  bool _suppressContinuousNotifications = false;
  bool _continuousNotificationPending = false;
  final Map<String, WebsiteViewport> _renderedBlockViewports = {};

  int get navigationStateRevision => _navigationStateRevision;
  int get pageDocumentEpoch => _pageDocumentEpoch;

  void _markPageDocumentMutation() {
    _invalidateInlineManipulation();
    if (!_committingContinuousFieldEdit) {
      _invalidateContinuousFieldEdit();
    }
    _pageDocumentEpoch++;
  }

  @override
  void notifyListeners() {
    if (_suppressContinuousNotifications) {
      _continuousNotificationPending = true;
      return;
    }
    _navigationStateRevision++;
    super.notifyListeners();
  }

  /// Publishes renderer-only geometry without pretending navigation changed.
  ///
  /// A Canvas reporting its laid-out width may enable an inspector control,
  /// but it cannot invalidate a route decision or a save/navigation lease.
  void _notifyTransientRendererLayout() {
    if (_isDisposed) return;
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
  WebsiteWriteScope _writeScope = WebsiteWriteScope.shared;
  final Map<String, WebsiteWriteScope> _fieldWriteScopes = {};
  final Map<WebsiteCanvasDocumentTarget, Size> _renderedCanvasSizes = {};
  int _renderedCanvasMeasurementGeneration = 0;

  int get renderedCanvasMeasurementGeneration =>
      _renderedCanvasMeasurementGeneration;

  String? _selectedBlockId;
  int _selectionVersion = 0; // Tracks explicit selection events
  WebsiteEditorBlockRevealRequest? _blockRevealRequest;
  int _blockRevealRevision = 0;
  WebsiteCanvasManipulationSession? _canvasManipulationSession;
  int _canvasManipulationGeneration = 0;
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
    _sitewideAsyncSessionEpoch++;
    final hadLease = _entryLease != null;
    // A lease-less programmatic session is attributable through its typed
    // document owner; the suspension retains the drafts for that identity.
    _suspendedLease = _entryLease ??
        _suspendedLease ??
        _documentOwnerLease ??
        _sessionOwnerLease;
    _entryLease = null;
    _resetCanvasTouchMode();
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
    final hadLease = _entryLease != null || _suspendedLeaseFingerprint != null;
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
  WebsiteViewport get previewViewport => switch (_devicePreviewMode) {
        DevicePreviewMode.desktop => WebsiteViewport.desktop,
        DevicePreviewMode.tablet => WebsiteViewport.tablet,
        DevicePreviewMode.mobile => WebsiteViewport.mobile,
      };
  WebsiteWriteScope get writeScope => _writeScope;
  String? get selectedBlockId => _selectedBlockId;
  int get selectionVersion => _selectionVersion;

  /// The exact inline gesture currently allowed to commit.
  WebsiteInlineManipulationLease? get inlineManipulationSession =>
      _inlineManipulationSession;

  /// Records the responsive band one page block actually renders in.
  ///
  /// The device selector is only a request. A constrained frame may render a
  /// different band, so inline height, spacing and text transactions bind to
  /// this measured/projected value instead of [previewViewport]. This is
  /// transient geometry: it never dirties the page or creates history.
  void reportRenderedBlockViewport(
    String blockId,
    WebsiteViewport viewport,
  ) {
    if (_isDisposed || !_documentContainsBlock(blockId)) return;
    final previous = _renderedBlockViewports[blockId];
    if (previous == viewport) return;
    _renderedBlockViewports[blockId] = viewport;
    _invalidateInlineManipulation(blockId: blockId);
    _notifyTransientRendererLayout();
  }

  /// Last viewport geometry published by the block renderer.
  WebsiteViewport? renderedBlockViewportFor(String blockId) =>
      _renderedBlockViewports[blockId];

  /// Arms a callback-only inline control before it knows its block id.
  ///
  /// `BlockSpacerHandle` receives an existing `(blockId, value)` closure from
  /// page composition. Pointer-down happens inside the handle, while that
  /// closure is the only place the exact block id exists. This synchronous
  /// handshake lets the next matching [updateBlockData] call bind the target
  /// without changing page-composition's public API or writing the value.
  int? prepareInlineManipulationArm(
    WebsiteInlineManipulationProperty property,
  ) {
    if (_isDisposed ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor) {
      return null;
    }
    _inlineManipulationSession = null;
    final generation = ++_inlineManipulationGeneration;
    _preparedInlineManipulationArm = _PreparedInlineManipulationArm(
      generation: generation,
      property: property,
      pageId: _pageDraft.pageId,
      pageSlug: _pageDraft.pageSlug,
      documentSessionRevision: _pageDraft.sessionRevision,
      documentEpoch: _pageDocumentEpoch,
    );
    return generation;
  }

  void abandonPreparedInlineManipulationArm(int generation) {
    if (_preparedInlineManipulationArm?.generation == generation) {
      _preparedInlineManipulationArm = null;
    }
  }

  /// Captures one complete inline transaction before pointer slop.
  WebsiteInlineManipulationLease? beginInlineManipulation(
    WebsiteInlineManipulationTarget target,
  ) {
    _preparedInlineManipulationArm = null;
    _inlineManipulationSession = null;
    final lease = _captureInlineManipulation(
      target,
      generation: ++_inlineManipulationGeneration,
    );
    _inlineManipulationSession = lease;
    return lease;
  }

  /// Captures a one-shot guard for a discrete inspector mutation.
  ///
  /// Unlike [beginInlineManipulation], capture neither claims/cancels the
  /// gesture session nor notifies, writes, dirties or creates history. This is
  /// what lets every scalar binding retain its own exact callback guard.
  WebsiteInlineManipulationLease? captureInlineMutationLease(
    WebsiteInlineManipulationTarget target,
  ) {
    return _captureInlineManipulation(
      target,
      generation: ++_inlineManipulationGeneration,
    );
  }

  /// Captures the exact editor/document owner before an asynchronous surface.
  ///
  /// This is deliberately side-effect free: it does not notify, dirty the
  /// document, create history or claim either manipulation FSM. A caller must
  /// hand the same token back to [commitAsyncIntent] after its `await`.
  WebsiteEditorAsyncIntent? captureAsyncIntent({
    String? blockId,
    bool requiresSelection = true,
  }) {
    if (_isDisposed ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        (requiresSelection &&
            (blockId == null || _selectedBlockId != blockId))) {
      return null;
    }

    Map<String, dynamic>? sourceBlock;
    if (blockId != null) {
      final block = _pageDraft.blocks.cast<Map<String, dynamic>?>().firstWhere(
            (candidate) => candidate?['id']?.toString() == blockId,
            orElse: () => null,
          );
      if (block == null) return null;
      sourceBlock = _deepUnmodifiableMap(_deepCopyMap(block));
    }

    return WebsiteEditorAsyncIntent._(
      ownerIdentity: _asyncIntentOwnerIdentity,
      generation: ++_asyncIntentGeneration,
      blockId: blockId,
      requiresSelection: requiresSelection,
      pageId: _pageDraft.pageId,
      pageSlug: _pageDraft.pageSlug,
      documentSessionRevision: _pageDraft.sessionRevision,
      documentEpoch: _pageDocumentEpoch,
      selectionVersion: _selectionVersion,
      stateEpoch: _inlineManipulationStateEpoch,
      blockStateEpoch:
          blockId == null ? 0 : (_inlineManipulationBlockEpochs[blockId] ?? 0),
      sourceBlock: sourceBlock,
    );
  }

  /// Validates and consumes one asynchronous intent, then runs its mutation.
  ///
  /// Validation and [operation] run in one synchronous provider call, so no
  /// page, selection, viewport or scope change can slip between admission and
  /// the canonical write. Rejected intents are consumed permanently.
  WebsiteInlineMutationResult commitAsyncIntent(
    WebsiteEditorAsyncIntent expectedIntent,
    WebsiteInlineMutationResult Function() operation,
  ) {
    if (!expectedIntent._consume() || !_validateAsyncIntent(expectedIntent)) {
      return WebsiteInlineMutationResult.rejected;
    }
    return operation();
  }

  /// Starts one exact continuous edit for a page-block field.
  ///
  /// Beginning B finalizes A first. This keeps a single provisional history
  /// owner and prevents two focused controls from replacing each other's undo
  /// slot.
  WebsiteContinuousFieldEdit? beginContinuousFieldEdit({
    required String blockId,
    required String scopeKey,
    required Object? baselineValue,
  }) {
    finalizeActiveContinuousFieldEdit();
    final intent = captureAsyncIntent(blockId: blockId);
    if (intent == null) return null;
    final edit = WebsiteContinuousFieldEdit._(
      ownerIdentity: _asyncIntentOwnerIdentity,
      blockId: blockId,
      scopeKey: scopeKey,
      baselineValue: baselineValue,
      intent: intent,
      initialBlocks: _deepCopyBlocks(_pageDraft.blocks),
      initialHistory:
          _pageDraft.history.map(_deepCopyBlocks).toList(growable: false),
      initialHistoryIndex: _pageDraft.historyIndex,
    );
    _activeContinuousFieldEdit = edit;
    return edit;
  }

  /// Applies one live-preview tick while coalescing the whole focus session
  /// into one undo slot.
  WebsiteInlineMutationResult commitContinuousFieldEdit(
    WebsiteContinuousFieldEdit expectedEdit,
    String scopeKey,
    Object? nextValue,
    WebsiteInlineMutationResult Function() operation,
  ) {
    if (!identical(expectedEdit._ownerIdentity, _asyncIntentOwnerIdentity) ||
        expectedEdit.scopeKey != scopeKey ||
        !expectedEdit._active ||
        !identical(_activeContinuousFieldEdit, expectedEdit)) {
      return WebsiteInlineMutationResult.rejected;
    }
    if (_deepEquals(nextValue, expectedEdit._baselineValue)) {
      return _restoreContinuousFieldEdit(
        expectedEdit,
        keepActive: true,
      );
    }

    _committingContinuousFieldEdit = true;
    _suppressContinuousNotifications = true;
    WebsiteInlineMutationResult result;
    try {
      result = commitAsyncIntent(expectedEdit._intent, operation);
    } finally {
      _committingContinuousFieldEdit = false;
      _suppressContinuousNotifications = false;
    }

    if (!result.accepted) {
      expectedEdit._active = false;
      if (identical(_activeContinuousFieldEdit, expectedEdit)) {
        _activeContinuousFieldEdit = null;
      }
      _flushContinuousNotification();
      return WebsiteInlineMutationResult.rejected;
    }

    if (result.changed) {
      _coalesceContinuousHistory(expectedEdit);
    }
    final nextIntent = captureAsyncIntent(blockId: expectedEdit.blockId);
    if (nextIntent == null) {
      expectedEdit._active = false;
      _activeContinuousFieldEdit = null;
    } else {
      expectedEdit._intent = nextIntent;
    }
    _flushContinuousNotification();
    return result;
  }

  /// Finalizes the current value. The coalesced history slot remains as the
  /// single operation the user can undo.
  WebsiteInlineMutationResult finishContinuousFieldEdit(
    WebsiteContinuousFieldEdit expectedEdit,
    String scopeKey,
  ) {
    if (!identical(expectedEdit._ownerIdentity, _asyncIntentOwnerIdentity) ||
        expectedEdit.scopeKey != scopeKey ||
        !expectedEdit._active ||
        !identical(_activeContinuousFieldEdit, expectedEdit)) {
      return WebsiteInlineMutationResult.rejected;
    }
    final result = commitAsyncIntent(
      expectedEdit._intent,
      () => WebsiteInlineMutationResult.unchanged,
    );
    expectedEdit._active = false;
    _activeContinuousFieldEdit = null;
    return result;
  }

  /// Cancels an uncontended edit and restores its exact pre-focus document,
  /// history (including redo) and dirty state.
  WebsiteInlineMutationResult cancelContinuousFieldEdit(
    WebsiteContinuousFieldEdit expectedEdit,
    String scopeKey,
  ) {
    if (!identical(expectedEdit._ownerIdentity, _asyncIntentOwnerIdentity) ||
        expectedEdit.scopeKey != scopeKey ||
        !expectedEdit._active ||
        !identical(_activeContinuousFieldEdit, expectedEdit)) {
      return WebsiteInlineMutationResult.rejected;
    }
    return _restoreContinuousFieldEdit(expectedEdit, keepActive: false);
  }

  WebsiteInlineMutationResult _restoreContinuousFieldEdit(
    WebsiteContinuousFieldEdit expectedEdit, {
    required bool keepActive,
  }) {
    final hadWrites = expectedEdit._hasWrites;

    _committingContinuousFieldEdit = true;
    _suppressContinuousNotifications = true;
    WebsiteInlineMutationResult admitted;
    try {
      admitted = commitAsyncIntent(
        expectedEdit._intent,
        () => WebsiteInlineMutationResult.unchanged,
      );
      if (admitted.accepted && hadWrites) {
        _pageDraft.blocks = _deepCopyBlocks(expectedEdit._initialBlocks);
        _pageDraft.history
          ..clear()
          ..addAll(expectedEdit._initialHistory.map(_deepCopyBlocks));
        _pageDraft.historyIndex = expectedEdit.initialHistoryIndex;
        expectedEdit._hasWrites = false;
        _markPageDocumentMutation();
        _reconcileTransientCanvasSelections();
        _refreshPageDirtyState();
        _continuousNotificationPending = true;
      }
    } finally {
      _committingContinuousFieldEdit = false;
      _suppressContinuousNotifications = false;
    }

    if (!admitted.accepted) {
      expectedEdit._active = false;
      _activeContinuousFieldEdit = null;
      _flushContinuousNotification();
      return WebsiteInlineMutationResult.rejected;
    }

    if (keepActive) {
      final nextIntent = captureAsyncIntent(blockId: expectedEdit.blockId);
      if (nextIntent == null) {
        expectedEdit._active = false;
        _activeContinuousFieldEdit = null;
        _flushContinuousNotification();
        return WebsiteInlineMutationResult.rejected;
      }
      expectedEdit._intent = nextIntent;
    } else {
      expectedEdit._active = false;
      _activeContinuousFieldEdit = null;
    }
    _flushContinuousNotification();
    return hadWrites
        ? WebsiteInlineMutationResult.committed
        : WebsiteInlineMutationResult.unchanged;
  }

  /// Save/undo/another focus use this synchronous boundary before reading the
  /// document. No new write or history entry is created.
  void finalizeActiveContinuousFieldEdit() {
    final active = _activeContinuousFieldEdit;
    if (active != null) finishContinuousFieldEdit(active, active.scopeKey);
  }

  void _coalesceContinuousHistory(WebsiteContinuousFieldEdit edit) {
    if (_deepEquals(_pageDraft.blocks, edit._initialBlocks)) {
      _pageDraft.history
        ..clear()
        ..addAll(edit._initialHistory.map(_deepCopyBlocks));
      _pageDraft.historyIndex = edit.initialHistoryIndex;
      edit._hasWrites = false;
      _refreshPageDirtyState();
      return;
    }

    final prefix = <List<Map<String, dynamic>>>[];
    final prefixEnd = (edit.initialHistoryIndex + 1).clamp(
      0,
      edit._initialHistory.length,
    );
    for (var index = 0; index < prefixEnd; index++) {
      prefix.add(_deepCopyBlocks(edit._initialHistory[index]));
    }
    if (prefix.isEmpty) prefix.add(_deepCopyBlocks(edit._initialBlocks));
    prefix.add(_deepCopyBlocks(_pageDraft.blocks));
    if (prefix.length > _maxHistory) prefix.removeAt(1);
    _pageDraft.history
      ..clear()
      ..addAll(prefix);
    _pageDraft.historyIndex = _pageDraft.history.length - 1;
    edit._hasWrites = true;
    _refreshPageDirtyState();
  }

  void _invalidateContinuousFieldEdit() {
    final active = _activeContinuousFieldEdit;
    if (active == null) return;
    active._active = false;
    _activeContinuousFieldEdit = null;
  }

  void _flushContinuousNotification() {
    if (!_continuousNotificationPending) return;
    _continuousNotificationPending = false;
    _notifyAfterFrame();
  }

  /// Captures the exact site-wide owner before a picker or dialog awaits.
  ///
  /// [sourceKeys] is mandatory and intentionally narrow. It records the
  /// effective values the control was displaying, while [bucket] supplies the
  /// coarse anti-ABA epoch that also rejects a concurrent write to a sibling
  /// field in the same persisted bucket.
  WebsiteSitewideAsyncIntent? captureSitewideAsyncIntent({
    required WebsiteSitewideDraftBucket bucket,
    required Iterable<String> sourceKeys,
  }) {
    if (_isDisposed ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor) {
      return null;
    }

    final normalizedKeys = sourceKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet();
    if (normalizedKeys.isEmpty) return null;

    final sourceValues = <String, dynamic>{
      for (final key in normalizedKeys)
        key: _deepUnmodifiableValue(
          _sitewideAsyncSourceValue(bucket, key),
        ),
    };
    return WebsiteSitewideAsyncIntent._(
      ownerIdentity: _asyncIntentOwnerIdentity,
      generation: ++_asyncIntentGeneration,
      bucket: bucket,
      sessionEpoch: _sitewideAsyncSessionEpoch,
      entryLeaseGeneration: _entryLeaseGeneration,
      entryLeaseIdentityRevision: _entryLeaseIdentityRevision,
      sessionOwnerTenantId: sessionOwnerTenantId,
      sessionOwnerLeaseFingerprint: sessionOwnerLeaseFingerprint,
      bucketEpoch: _sitewideBucketEpoch(bucket),
      sourceValues: sourceValues,
    );
  }

  /// Validates and consumes one site-wide async intent, then performs exactly
  /// one synchronous canonical provider transaction.
  WebsiteInlineMutationResult commitSitewideAsyncIntent(
    WebsiteSitewideAsyncIntent expectedIntent,
    WebsiteInlineMutationResult Function() operation,
  ) {
    if (!expectedIntent._consume() ||
        !_validateSitewideAsyncIntent(expectedIntent)) {
      return WebsiteInlineMutationResult.rejected;
    }
    return operation();
  }

  bool _validateSitewideAsyncIntent(
    WebsiteSitewideAsyncIntent expectedIntent,
  ) {
    if (_isDisposed ||
        !identical(
          expectedIntent._ownerIdentity,
          _asyncIntentOwnerIdentity,
        ) ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        _sitewideAsyncSessionEpoch != expectedIntent.sessionEpoch ||
        _entryLeaseGeneration != expectedIntent.entryLeaseGeneration ||
        _entryLeaseIdentityRevision !=
            expectedIntent.entryLeaseIdentityRevision ||
        sessionOwnerTenantId != expectedIntent.sessionOwnerTenantId ||
        sessionOwnerLeaseFingerprint !=
            expectedIntent.sessionOwnerLeaseFingerprint ||
        _sitewideBucketEpoch(expectedIntent.bucket) !=
            expectedIntent.bucketEpoch) {
      return false;
    }

    for (final entry in expectedIntent.sourceValues.entries) {
      if (!_deepEquals(
        _sitewideAsyncSourceValue(expectedIntent.bucket, entry.key),
        entry.value,
      )) {
        return false;
      }
    }
    return true;
  }

  int _sitewideBucketEpoch(WebsiteSitewideDraftBucket bucket) =>
      switch (bucket) {
        WebsiteSitewideDraftBucket.header => _sitewideDraft.headerEpoch,
        WebsiteSitewideDraftBucket.siteSettings =>
          _sitewideDraft.siteSettingsEpoch,
        WebsiteSitewideDraftBucket.theme => _sitewideDraft.themeEpoch,
        WebsiteSitewideDraftBucket.footer => _sitewideDraft.footerEpoch,
      };

  void _markSitewideBucketMutation(WebsiteSitewideDraftBucket bucket) {
    switch (bucket) {
      case WebsiteSitewideDraftBucket.header:
        _sitewideDraft.headerEpoch++;
        return;
      case WebsiteSitewideDraftBucket.siteSettings:
        _sitewideDraft.siteSettingsEpoch++;
        return;
      case WebsiteSitewideDraftBucket.theme:
        _sitewideDraft.themeEpoch++;
        return;
      case WebsiteSitewideDraftBucket.footer:
        _sitewideDraft.footerEpoch++;
        return;
    }
  }

  dynamic _sitewideAsyncSourceValue(
    WebsiteSitewideDraftBucket bucket,
    String key,
  ) {
    if (bucket == WebsiteSitewideDraftBucket.footer &&
        key == WebsiteSitewideAsyncSourceKey.footerNavigation) {
      return _footerNavigationAsyncSourceSnapshot();
    }

    final pending = switch (bucket) {
      WebsiteSitewideDraftBucket.header => _sitewideDraft.pendingHeaderSettings,
      WebsiteSitewideDraftBucket.siteSettings =>
        _sitewideDraft.pendingSiteSettings,
      WebsiteSitewideDraftBucket.theme => _sitewideDraft.pendingThemeSettings,
      WebsiteSitewideDraftBucket.footer => _sitewideDraft.pendingFooterSettings,
    };
    if (pending.containsKey(key)) return pending[key];
    return _settings[key]?.toString();
  }

  Map<String, dynamic> _footerNavigationAsyncSourceSnapshot() =>
      <String, dynamic>{
        'sectionOrder': _deepCopyValue(
          _sitewideDraft.pendingFooterSectionOrder,
        ),
        'linkOrder': _deepCopyValue(
          _sitewideDraft.pendingFooterLinkOrder,
        ),
        'labels': _deepCopyValue(_sitewideDraft.pendingFooterNavLabels),
        'linkTypes': _sitewideDraft.pendingFooterNavLinkTypes.map(
          (id, type) => MapEntry(id, type.value),
        ),
        'linkValues': _deepCopyValue(_sitewideDraft.pendingFooterNavLinkValues),
        'openInNewTab':
            _deepCopyValue(_sitewideDraft.pendingFooterNavOpenInNewTab),
        'items': _sitewideDraft.pendingFooterNavItems.map(
          (id, navigation) => MapEntry(
            id,
            _websiteNavigationAsyncSourceSnapshot(navigation),
          ),
        ),
        'creates': _sitewideDraft.pendingFooterNavCreates.map(
          (id, navigation) => MapEntry(
            id,
            _websiteNavigationAsyncSourceSnapshot(navigation),
          ),
        ),
        'deletes': Set<String>.from(
          _sitewideDraft.pendingFooterNavDeletes,
        ),
      };

  Map<String, dynamic> _websiteNavigationAsyncSourceSnapshot(
    WebsiteNavigation navigation,
  ) =>
      <String, dynamic>{
        'id': navigation.id,
        'tenantId': navigation.tenantId,
        'menuLocation': navigation.menuLocation.name,
        'label': navigation.label,
        'icon': navigation.icon,
        'linkType': navigation.linkType.value,
        'linkValue': navigation.linkValue,
        'openInNewTab': navigation.openInNewTab,
        'parentId': navigation.parentId,
        'orderIndex': navigation.orderIndex,
        'isVisible': navigation.isVisible,
        'showOnDesktop': navigation.showOnDesktop,
        'showOnMobile': navigation.showOnMobile,
        'cssClass': navigation.cssClass,
        'highlight': navigation.highlight,
        'children': navigation.children
            .map(_websiteNavigationAsyncSourceSnapshot)
            .toList(growable: false),
      };

  bool _validateAsyncIntent(WebsiteEditorAsyncIntent expectedIntent) {
    if (_isDisposed ||
        !identical(
          expectedIntent._ownerIdentity,
          _asyncIntentOwnerIdentity,
        ) ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        _pageDraft.pageId != expectedIntent.pageId ||
        _pageDraft.pageSlug != expectedIntent.pageSlug ||
        _pageDraft.sessionRevision != expectedIntent.documentSessionRevision ||
        _pageDocumentEpoch != expectedIntent.documentEpoch ||
        _inlineManipulationStateEpoch != expectedIntent.stateEpoch ||
        (expectedIntent.requiresSelection &&
            (_selectedBlockId != expectedIntent.blockId ||
                _selectionVersion != expectedIntent.selectionVersion))) {
      return false;
    }

    final blockId = expectedIntent.blockId;
    if (blockId == null) return expectedIntent.sourceBlock == null;
    if ((_inlineManipulationBlockEpochs[blockId] ?? 0) !=
        expectedIntent.blockStateEpoch) {
      return false;
    }
    final block = _pageDraft.blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate?['id']?.toString() == blockId,
          orElse: () => null,
        );
    return block != null &&
        expectedIntent.sourceBlock != null &&
        _deepEquals(block, expectedIntent.sourceBlock);
  }

  /// Captures one exact, side-effect-free guard for a semantic collection
  /// command.
  ///
  /// Capture never writes, dirties, notifies or creates history. A malformed
  /// path, ambiguous persisted identity or missing selection fails closed.
  WebsiteRepeaterMutationLease? captureRepeaterMutationLease(
    WebsiteRepeaterCollectionTarget target,
  ) {
    if (_isDisposed ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        !_validRepeaterTarget(target) ||
        (target.requiresSelection && _selectedBlockId != target.blockId)) {
      return null;
    }

    final block = _pageDraft.blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate?['id']?.toString() == target.blockId,
          orElse: () => null,
        );
    if (block == null || _repeaterTargetCollection(block, target) == null) {
      return null;
    }

    return WebsiteRepeaterMutationLease._(
      ownerIdentity: _asyncIntentOwnerIdentity,
      target: target,
      generation: ++_repeaterMutationGeneration,
      pageId: _pageDraft.pageId,
      pageSlug: _pageDraft.pageSlug,
      documentSessionRevision: _pageDraft.sessionRevision,
      documentEpoch: _pageDocumentEpoch,
      selectionVersion: _selectionVersion,
      stateEpoch: _inlineManipulationStateEpoch,
      blockStateEpoch: _inlineManipulationBlockEpochs[target.blockId] ?? 0,
      sourceBlock: _deepUnmodifiableMap(_deepCopyMap(block)),
    );
  }

  /// Applies one semantic collection command under its captured exact source.
  ///
  /// The command is resolved inside the current provider document, never from
  /// a widget-authored replacement list. Admission, mutation, one history
  /// entry and notification are synchronous in this owner.
  WebsiteRepeaterMutationOutcome commitRepeaterMutation(
    WebsiteRepeaterMutationLease expectedLease,
    WebsiteRepeaterCommand command,
  ) {
    if (!expectedLease._consume() ||
        !_validateRepeaterMutationLease(expectedLease)) {
      return const WebsiteRepeaterMutationOutcome.rejected();
    }

    final target = expectedLease.target;
    final blockIndex = _pageDraft.blocks.indexWhere(
      (block) => block['id']?.toString() == target.blockId,
    );
    if (blockIndex == -1) {
      return const WebsiteRepeaterMutationOutcome.rejected();
    }

    final block = _pageDraft.blocks[blockIndex];
    final rawData = block['block_data'];
    if (rawData is! Map) {
      return const WebsiteRepeaterMutationOutcome.rejected();
    }
    final currentData = _deepCopyMap(
      rawData.map((key, value) => MapEntry(key.toString(), value)),
    );
    final applied = _applyRepeaterMutationAtOwner(
      currentData,
      target: target,
      ancestorIndex: 0,
      command: command,
    );
    if (applied == null) {
      return const WebsiteRepeaterMutationOutcome.rejected();
    }
    if (!applied.outcome.result.changed) return applied.outcome;

    final nextBlock = sanitizeWebsiteBlockForPersistence(<String, dynamic>{
      ...block,
      'block_data': applied.owner,
    });
    if (_deepEquals(nextBlock, block)) {
      return WebsiteRepeaterMutationOutcome.unchanged(
        selectionIndex: applied.outcome.selectionIndex,
        selectionItem: applied.outcome.selectionItem,
      );
    }

    final structuralKeys = target.ancestors.isEmpty
        ? target.collectionKeys
        : target.ancestors.first.collectionKeys;
    _resetCanvasManipulationForStructuralWrite(
      target.blockId,
      structuralKeys,
    );
    _pageDraft.blocks[blockIndex] = nextBlock;
    _reconcileTransientCanvasSelections();
    _saveToHistory();
    notifyListeners();
    return applied.outcome;
  }

  WebsiteInlineManipulationLease? _captureInlineManipulation(
    WebsiteInlineManipulationTarget target, {
    required int generation,
  }) {
    if (_isDisposed ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        target.properties.isEmpty ||
        _renderedBlockViewports[target.blockId] != target.viewport ||
        (target.requiresSelection && _selectedBlockId != target.blockId)) {
      return null;
    }

    final blockIndex = _pageDraft.blocks.indexWhere(
      (block) => block['id']?.toString() == target.blockId,
    );
    if (blockIndex == -1) return null;
    if (target.owner
        case WebsiteInlineRepeaterOwner(
          collectionKeys: final collectionKeys,
          itemIndex: final itemIndex,
          identityKey: final identityKey,
          identityValue: final identityValue,
        )) {
      if (_blockRepeaterItemData(
            target.blockId,
            collectionKeys: collectionKeys,
            itemIndex: itemIndex,
            identityKey: identityKey,
            identityValue: identityValue,
          ) ==
          null) {
        return null;
      }
    }

    final writeScopes = <String, WebsiteWriteScope>{};
    for (final property in target.properties) {
      if (writeScopes.containsKey(property.canonicalKey)) return null;
      writeScopes[property.canonicalKey] = _inlineWriteScope(
        target: target,
        property: property,
      );
    }
    final sourceBlock = _deepUnmodifiableMap(
      _deepCopyMap(_pageDraft.blocks[blockIndex]),
    );
    final lease = WebsiteInlineManipulationLease._(
      ownerIdentity: _asyncIntentOwnerIdentity,
      target: target,
      generation: generation,
      pageId: _pageDraft.pageId,
      pageSlug: _pageDraft.pageSlug,
      documentSessionRevision: _pageDraft.sessionRevision,
      documentEpoch: _pageDocumentEpoch,
      selectionVersion: _selectionVersion,
      stateEpoch: _inlineManipulationStateEpoch,
      blockStateEpoch: _inlineManipulationBlockEpochs[target.blockId] ?? 0,
      sourceBlock: sourceBlock,
      writeScopes: writeScopes,
    );
    return lease;
  }

  WebsiteWriteScope _inlineWriteScope({
    required WebsiteInlineManipulationTarget target,
    required WebsiteInlineManipulationProperty property,
  }) {
    return switch (target.owner) {
      WebsiteInlineBlockOwner() => fieldWriteScope(
          blockId: target.blockId,
          propertyKey: property.canonicalKey,
          policy: property.policy,
          viewport: target.viewport,
        ),
      WebsiteInlineRepeaterOwner(
        collectionKeys: final collectionKeys,
        itemIndex: final itemIndex,
        identityKey: final identityKey,
        identityValue: final identityValue,
      ) =>
        repeaterFieldWriteScope(
          blockId: target.blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          propertyKey: property.canonicalKey,
          policy: property.policy,
          viewport: target.viewport,
          identityKey: identityKey,
          identityValue: identityValue,
        ),
    };
  }

  /// Cancels only the exact generation named by the caller.
  bool cancelInlineManipulation(
    WebsiteInlineManipulationLease expectedLease,
  ) {
    if (!identical(_inlineManipulationSession, expectedLease) ||
        !expectedLease._consume()) {
      return false;
    }
    _inlineManipulationSession = null;
    return true;
  }

  /// Commits all changed inline values as one provider transaction/history
  /// entry, even when different properties captured different responsive
  /// scopes.
  bool commitInlineManipulation(
    WebsiteInlineManipulationLease expectedLease,
    Map<String, Object?> values,
  ) {
    if (!expectedLease._consume() ||
        !_validateInlineManipulation(
          expectedLease,
          values,
          requiresActiveSession: true,
        )) {
      return false;
    }
    _inlineManipulationSession = null;
    return _commitInlineMutationValues(expectedLease, values);
  }

  /// Applies a captured discrete mutation once, or fails without side effects.
  WebsiteInlineMutationResult commitInlineMutation(
    WebsiteInlineManipulationLease expectedLease,
    Map<String, Object?> values,
  ) {
    if (!expectedLease._consume() ||
        !_validateInlineManipulation(
          expectedLease,
          values,
          requiresActiveSession: false,
        )) {
      return WebsiteInlineMutationResult.rejected;
    }
    return _commitInlineMutationValues(expectedLease, values)
        ? WebsiteInlineMutationResult.committed
        : WebsiteInlineMutationResult.unchanged;
  }

  bool _commitInlineMutationValues(
    WebsiteInlineManipulationLease expectedLease,
    Map<String, Object?> values,
  ) {
    final target = expectedLease.target;
    return switch (target.owner) {
      WebsiteInlineBlockOwner() => _transformBlockData(
          target.blockId,
          (current) => _applyInlineManipulationValues(
            current,
            lease: expectedLease,
            values: values,
          ),
        ),
      WebsiteInlineRepeaterOwner(
        collectionKeys: final collectionKeys,
        itemIndex: final itemIndex,
        identityKey: final identityKey,
        identityValue: final identityValue,
      ) =>
        _transformBlockRepeaterItemData(
          target.blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          identityKey: identityKey,
          identityValue: identityValue,
          operation: 'commitInlineManipulation',
          transform: (item) => _applyInlineManipulationValues(
            item,
            lease: expectedLease,
            values: values,
          ),
        ),
    };
  }

  bool _validateInlineManipulation(
    WebsiteInlineManipulationLease expectedLease,
    Map<String, Object?> values, {
    required bool requiresActiveSession,
  }) {
    bool reject() {
      if (identical(_inlineManipulationSession, expectedLease)) {
        _inlineManipulationSession = null;
      }
      return false;
    }

    if (_isDisposed ||
        !identical(
          expectedLease._ownerIdentity,
          _asyncIntentOwnerIdentity,
        ) ||
        values.isEmpty ||
        (requiresActiveSession &&
            !identical(_inlineManipulationSession, expectedLease)) ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        _pageDraft.pageId != expectedLease.pageId ||
        _pageDraft.pageSlug != expectedLease.pageSlug ||
        _pageDraft.sessionRevision != expectedLease.documentSessionRevision ||
        _pageDocumentEpoch != expectedLease.documentEpoch ||
        _inlineManipulationStateEpoch != expectedLease.stateEpoch ||
        (_inlineManipulationBlockEpochs[expectedLease.target.blockId] ?? 0) !=
            expectedLease.blockStateEpoch ||
        _renderedBlockViewports[expectedLease.target.blockId] !=
            expectedLease.target.viewport ||
        (expectedLease.target.requiresSelection &&
            (_selectedBlockId != expectedLease.target.blockId ||
                _selectionVersion != expectedLease.selectionVersion))) {
      return reject();
    }

    final block = _pageDraft.blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) =>
              candidate?['id']?.toString() == expectedLease.target.blockId,
          orElse: () => null,
        );
    if (block == null || !_deepEquals(block, expectedLease.sourceBlock)) {
      return reject();
    }

    final properties = <String, WebsiteInlineManipulationProperty>{
      for (final property in expectedLease.target.properties)
        property.canonicalKey: property,
    };
    for (final entry in values.entries) {
      final property = properties[entry.key];
      if (property == null || !_validInlineValue(entry.key, entry.value)) {
        return reject();
      }
    }
    for (final property in expectedLease.target.properties) {
      if (_inlineWriteScope(
            target: expectedLease.target,
            property: property,
          ) !=
          expectedLease.writeScopes[property.canonicalKey]) {
        return reject();
      }
    }
    return true;
  }

  bool _validInlineValue(String propertyKey, Object? value) {
    if (value is! num) return true;
    final number = value.toDouble();
    if (!number.isFinite) return false;
    if (propertyKey == WebsiteBlockMetaFields.spacingAfter.key) {
      return number >= 0;
    }
    if (propertyKey == WebsiteBlockMetaFields.blockHeight.key ||
        propertyKey.toLowerCase().contains('width')) {
      return number > 0;
    }
    return true;
  }

  Map<String, dynamic> _applyInlineManipulationValues(
    Map<String, dynamic> source, {
    required WebsiteInlineManipulationLease lease,
    required Map<String, Object?> values,
  }) {
    final properties = <String, WebsiteInlineManipulationProperty>{
      for (final property in lease.target.properties)
        property.canonicalKey: property,
    };
    var next = source;
    for (final entry in values.entries) {
      final property = properties[entry.key]!;
      final scope = lease.writeScopes[entry.key]!;
      if (scope == WebsiteWriteScope.viewport) {
        next = WebsiteResponsiveDataCodec.setForViewport(
          data: next,
          propertyKey: entry.key,
          value: entry.value,
          viewport: lease.target.viewport,
          policy: property.policy,
        );
        continue;
      }
      next = WebsiteResponsiveDataCodec.setShared(
        data: next,
        propertyKey: entry.key,
        value: entry.value,
        policies: <String, WebsiteResponsivePropertyPolicy>{
          entry.key: property.policy,
        },
      );
      for (final companion in property.sharedCompanionKeys) {
        next = WebsiteResponsiveDataCodec.setShared(
          data: next,
          propertyKey: companion,
          value: entry.value,
          policies: <String, WebsiteResponsivePropertyPolicy>{
            companion: property.policy,
          },
        );
      }
    }
    return next;
  }

  bool _bindPreparedInlineManipulation(
    String blockId,
    String propertyKey,
  ) {
    final prepared = _preparedInlineManipulationArm;
    if (prepared == null || prepared.property.canonicalKey != propertyKey) {
      return false;
    }
    _preparedInlineManipulationArm = null;
    if (_pageDraft.pageId != prepared.pageId ||
        _pageDraft.pageSlug != prepared.pageSlug ||
        _pageDraft.sessionRevision != prepared.documentSessionRevision ||
        _pageDocumentEpoch != prepared.documentEpoch) {
      return true;
    }
    final viewport = _renderedBlockViewports[blockId];
    if (viewport == null) return true;
    final lease = _captureInlineManipulation(
      WebsiteInlineManipulationTarget(
        blockId: blockId,
        owner: const WebsiteInlineBlockOwner(),
        viewport: viewport,
        properties: <WebsiteInlineManipulationProperty>[prepared.property],
        requiresSelection: false,
      ),
      generation: prepared.generation,
    );
    _inlineManipulationSession = lease;
    return true;
  }

  void _invalidateInlineManipulation({String? blockId}) {
    if (blockId == null) {
      _inlineManipulationStateEpoch++;
    } else {
      _inlineManipulationBlockEpochs[blockId] =
          (_inlineManipulationBlockEpochs[blockId] ?? 0) + 1;
    }
    final session = _inlineManipulationSession;
    if (blockId == null || session?.target.blockId == blockId) {
      _inlineManipulationSession = null;
    }
    if (blockId == null) _preparedInlineManipulationArm = null;
  }

  /// The one direct-manipulation session, bound to one block/slide/layer.
  WebsiteCanvasManipulationSession? get canvasManipulationSession =>
      _canvasManipulationSession;

  WebsiteCanvasDocumentTarget? get selectedCanvasDocumentTarget {
    final blockId = _selectedBlockId;
    if (blockId == null) return null;
    final block = getBlock(blockId);
    if (block == null) return null;
    final type = (block['block_type'] ?? block['type'] ?? '').toString();
    if (type == WebsiteBlockType.canvas.name) {
      return WebsiteCanvasDocumentTarget(blockId: blockId);
    }
    if (type != WebsiteBlockType.carousel.name) return null;
    final data = Map<String, dynamic>.from(block['block_data'] ?? const {});
    final slides = data['slides'];
    final count = slides is List ? slides.length : 0;
    if (count <= 0) return null;
    return WebsiteCanvasDocumentTarget(
      blockId: blockId,
      slideIndex: carouselSlideSelection(blockId, count),
    );
  }

  /// The viewport one concrete Canvas document is rendering right now.
  ///
  /// This cannot be inferred from [previewViewport]: a compact authoring host,
  /// block padding, or a Carousel slide may constrain the Canvas to a different
  /// logical width. Until the renderer reports a real size there is no safe
  /// direct-manipulation target, so callers fail closed instead of guessing.
  WebsiteViewport? renderedCanvasViewport(
    WebsiteCanvasDocumentTarget target,
  ) {
    final size = _renderedCanvasSizes[target];
    if (size == null || !size.width.isFinite || size.width <= 0) return null;
    final document = canvasDocument(
      target.blockId,
      slideIndex: target.slideIndex,
    );
    if (document == null) return null;
    return WebsiteCanvasResponsiveDocument.viewportForRenderedCanvasWidth(
      document,
      size.width,
    );
  }

  /// Records renderer geometry without dirtying the document or its history.
  ///
  /// The report is posted after layout by [CanvasBlock]. Crossing a responsive
  /// band invalidates an armed session for that document immediately: a touch
  /// admitted against one projection may never commit into another.
  void reportRenderedCanvasSize(
    WebsiteCanvasDocumentTarget target,
    Size size, {
    required int expectedMeasurementGeneration,
  }) {
    if (_isDisposed ||
        expectedMeasurementGeneration != _renderedCanvasMeasurementGeneration ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    if (canvasDocument(
          target.blockId,
          slideIndex: target.slideIndex,
        ) ==
        null) {
      return;
    }
    final previousViewport = renderedCanvasViewport(target);
    final previous = _renderedCanvasSizes[target];
    final sameSize = previous != null &&
        (previous.width - size.width).abs() < 0.5 &&
        (previous.height - size.height).abs() < 0.5;
    if (!sameSize) _renderedCanvasSizes[target] = size;
    final nextViewport = renderedCanvasViewport(target);
    final session = _canvasManipulationSession;
    var invalidatedSession = false;
    if (session?.target.document == target &&
        (nextViewport == null || session!.viewport != nextViewport)) {
      _resetCanvasTouchMode();
      invalidatedSession = true;
    } else if (previousViewport != nextViewport) {
      _invalidateInlineManipulation(blockId: target.blockId);
    }
    if (invalidatedSession) {
      notifyListeners();
    } else if (previousViewport != nextViewport || previous == null) {
      _notifyTransientRendererLayout();
    }
  }

  /// The selected layer, named the way the operator reads it.
  ///
  /// One owner for the sentence the dock and the `O-05` sheet both say.
  String? get selectedCanvasLayerLabel {
    final target = selectedCanvasLayerTarget;
    if (target == null) return null;
    final document = canvasDocument(
      target.document.blockId,
      slideIndex: target.document.slideIndex,
    );
    if (document == null) return null;
    final effectiveViewport =
        renderedCanvasViewport(target.document) ?? previewViewport;
    final layers = WebsiteCanvasResponsiveDocument.projectLayers(
      data: document,
      viewport: effectiveViewport,
    );
    for (final layer in layers) {
      if (layer.id == target.layerId) {
        return WebsiteCanvasLayerIdentity.describe(layer);
      }
    }
    return null;
  }

  WebsiteCanvasLayerTarget? get selectedCanvasLayerTarget {
    final document = selectedCanvasDocumentTarget;
    if (document == null) return null;
    final layerId = canvasElementSelection(
      document.blockId,
      slideIndex: document.slideIndex,
    );
    if (layerId == null || layerId.isEmpty) return null;
    return WebsiteCanvasLayerTarget(document: document, layerId: layerId);
  }

  WebsiteCanvasManipulationAvailability canvasManipulationAvailability(
    WebsiteCanvasManipulationMode mode, {
    WebsiteCanvasLayerTarget? target,
    WebsiteViewport? viewport,
  }) {
    if (_mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.editorInactive,
      );
    }
    final resolved = target ?? selectedCanvasLayerTarget;
    if (resolved == null || resolved != selectedCanvasLayerTarget) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.selectionMismatch,
      );
    }
    final document = canvasDocument(
      resolved.document.blockId,
      slideIndex: resolved.document.slideIndex,
    );
    if (document == null) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.documentMissing,
      );
    }
    final renderedViewport = renderedCanvasViewport(resolved.document);
    if (renderedViewport == null) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.canvasNotMeasured,
      );
    }
    final requestedViewport = viewport ?? renderedViewport;
    if (requestedViewport != renderedViewport) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.viewportMismatch,
      );
    }
    final layers = WebsiteCanvasResponsiveDocument.projectLayers(
      data: document,
      viewport: requestedViewport,
    );
    final matches =
        layers.where((layer) => layer.id == resolved.layerId).toList();
    if (matches.isEmpty) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.layerMissing,
      );
    }
    if (matches.length != 1) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.layerAmbiguous,
      );
    }
    final layer = matches.single;
    if (!layer.visible) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.layerHidden,
      );
    }
    if (layer.data['locked'] == true) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.layerLocked,
      );
    }
    if (mode == WebsiteCanvasManipulationMode.crop &&
        layer.kind != WebsiteCanvasLayerKind.image) {
      return const WebsiteCanvasManipulationAvailability.blocked(
        WebsiteCanvasManipulationBlockReason.modeUnsupported,
      );
    }
    return const WebsiteCanvasManipulationAvailability.available();
  }

  bool startCanvasManipulation(
    WebsiteCanvasManipulationMode mode, {
    required WebsiteCanvasLayerTarget target,
    required WebsiteViewport viewport,
  }) {
    if (_isDisposed) return false;
    if (!canvasManipulationAvailability(
      mode,
      target: target,
      viewport: viewport,
    ).isAvailable) {
      return false;
    }
    final current = _canvasManipulationSession;
    if (current != null &&
        current.matches(
          document: target.document,
          layerId: target.layerId,
          mode: mode,
          viewport: viewport,
        )) {
      return true;
    }
    final next = WebsiteCanvasManipulationSession(
      target: target,
      mode: mode,
      viewport: viewport,
      generation: ++_canvasManipulationGeneration,
    );
    _canvasManipulationSession = next;
    notifyListeners();
    return true;
  }

  bool stopCanvasManipulation({
    required WebsiteCanvasManipulationSession expectedSession,
  }) {
    if (_isDisposed) return false;
    final current = _canvasManipulationSession;
    if (current == null) return false;
    if (current != expectedSession) return false;
    _canvasManipulationSession = null;
    notifyListeners();
    return true;
  }

  /// Commits one direct-manipulation patch under the exact arm that admitted
  /// its pointer.
  ///
  /// Session comparison, live availability and persistence are synchronous in
  /// this owner. A stale pointer therefore cannot reuse a later arm with the
  /// same target, mode and viewport (the ABA case).
  bool commitCanvasManipulation(
    WebsiteCanvasManipulationSession expectedSession,
    Map<String, dynamic> expectedDocument,
    int expectedDocumentEpoch,
    Map<String, Object?> values, {
    required WebsiteWriteScope scope,
  }) {
    if (_isDisposed) return false;
    if (values.isEmpty || _canvasManipulationSession != expectedSession) {
      return false;
    }
    if (!canvasManipulationAvailability(
      expectedSession.mode,
      target: expectedSession.target,
      viewport: expectedSession.viewport,
    ).isAvailable) {
      return false;
    }
    final document = expectedSession.target.document;
    final liveDocument = canvasDocument(
      document.blockId,
      slideIndex: document.slideIndex,
    );
    // The pointer owns an optimistic lease over one exact source document.
    // Comparing that snapshot here, in the same synchronous owner that writes,
    // closes the no-frame race: another command, undo/redo or a rebaseline may
    // replace the document after pointer-down and before pointer-up without a
    // widget rebuild ever advancing CanvasBlock's local source epoch.
    if (_pageDocumentEpoch != expectedDocumentEpoch ||
        liveDocument == null ||
        !_deepEquals(liveDocument, expectedDocument)) {
      return false;
    }
    // Attribution is transaction state too. A gesture admitted while writes
    // were common cannot silently land as a viewport override merely because
    // the default scope changed before the finger lifted.
    if (scope != _writeScope) return false;
    return setCanvasLayerProperties(
      document.blockId,
      expectedSession.target.layerId,
      values,
      slideIndex: document.slideIndex,
      scope: scope,
      viewport: expectedSession.viewport,
    );
  }

  /// Compatibility projection while the dock migrates to the typed session.

  /// Direct manipulation never survives a selection or document change.
  void _resetCanvasTouchMode() {
    _canvasManipulationSession = null;
    _invalidateInlineManipulation();
  }

  void _resetCanvasManipulationForStructuralWrite(
    String blockId,
    Iterable<String> keys,
  ) {
    final session = _canvasManipulationSession;
    if (session == null || session.target.document.blockId != blockId) return;
    if (keys.any((key) => key == 'elements' || key == 'slides')) {
      _canvasManipulationSession = null;
    }
  }

  /// The block the canvas still owes the operator a look at, or null.
  ///
  /// Only an *operation* that displaced a block publishes one — the three
  /// reorder commands plus undo/redo. Selection never does: revealing on every
  /// tap would scroll the page out from under the finger that just chose a
  /// block it could already see.
  WebsiteEditorBlockRevealRequest? get blockRevealRequest =>
      _blockRevealRequest;

  /// Publishes exactly one reveal request. Callers invoke it only after they
  /// actually mutated, so a no-op move never scrolls the canvas.
  void _requestBlockReveal(String blockId) {
    _blockRevealRevision++;
    _blockRevealRequest = WebsiteEditorBlockRevealRequest(
      blockId: blockId,
      revision: _blockRevealRevision,
    );
  }

  /// Reveal for the block a history step just moved, when it survived the step.
  ///
  /// Undo/redo restore an order the operator cannot see from the dock alone:
  /// the identity badge does not change, so without this the reverted result is
  /// invisible exactly like the move was.
  void _requestSelectedBlockRevealIfPresent() {
    final selected = _selectedBlockId;
    if (selected == null) return;
    if (!_documentContainsBlock(selected)) return;
    _requestBlockReveal(selected);
  }

  bool _documentContainsBlock(String blockId) =>
      _pageDraft.blocks.any((block) => block['id']?.toString() == blockId);

  /// The chrome the selection points at, or null when it points at a block.
  ///
  /// Consumers use this to decide *what kind of thing* is selected before they
  /// look it up in the document — the contextual dock could not mount for the
  /// header precisely because it skipped this question and went straight to
  /// `blocks.indexWhere`, which is -1 for chrome by construction.
  WebsiteEditorChromeTarget? get selectedChromeTarget =>
      WebsiteEditorChromeTarget.forSelection(_selectedBlockId);

  /// A selection is valid when it names a live block **or** editor chrome.
  ///
  /// Chrome ids are never dangling: the header and the footer exist for as
  /// long as the site does. Treating them as missing is what made selecting
  /// the header and then undoing, reordering or crossing Preview silently
  /// deselect it — on every host, not only on touch.
  bool _selectionStillExists(String selectionId) =>
      WebsiteEditorChromeTarget.forSelection(selectionId) != null ||
      _documentContainsBlock(selectionId);

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
    final nextTarget = elementId == null
        ? null
        : WebsiteCanvasLayerTarget(
            document: WebsiteCanvasDocumentTarget(
              blockId: blockId,
              slideIndex: slideIndex,
            ),
            layerId: elementId,
          );
    _selectedBlockId = blockId;
    // A nested editor re-emits the already-active selection at the end of a
    // gesture so the inspector can restore focus. That is not a selection
    // change and must not silently turn off the explicit touch mode the
    // operator armed in O-05. A genuinely different document/layer (or a
    // cleared layer) still invalidates the exact session before publication.
    if (_canvasManipulationSession?.target != nextTarget) {
      _resetCanvasTouchMode();
    }
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
    final previous = carouselSlideSelection(blockId, slideCount);
    if (_selectedBlockId != blockId || previous != normalized) {
      _resetCanvasTouchMode();
    }
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

  /// Immutable saved/loaded baseline for durable-draft conflict detection.
  ///
  /// The live [document] may contain unsaved edits. Persisting its digest as
  /// the baseline would make every local draft appear compatible with any
  /// server state. History slot zero is the owner already used by Discard;
  /// exposing a detached copy lets [WebsiteEditorDraftStore] bind recovery to
  /// that exact document without gaining write access to provider internals.
  List<Map<String, dynamic>> get pageDraftBaselineBlocks =>
      List<Map<String, dynamic>>.unmodifiable(
        (_pageDraft.history.isEmpty
                ? _pageDraft.blocks
                : _pageDraft.history.first)
            .map(_deepUnmodifiableMap),
      );

  /// Switch task surfaces without reloading or clearing the current page draft.
  void openWorkspace(WebsiteWorkspaceMode mode) {
    if (_workspaceMode == mode) return;
    _resetCanvasTouchMode();
    _sitewideAsyncSessionEpoch++;
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
    _resetCanvasTouchMode();
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.header);
    _sitewideDraft.hasHeaderChanges = true;
    notifyListeners();
  }

  /// Update pending header settings (will be saved with main save button)
  void updateHeaderSettings(Map<String, String> settings) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.header);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.header);
    _mergeSavedSettingsBaseline(savedSnapshot);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingHeaderSettings, savedSnapshot);
    _sitewideDraft.hasHeaderChanges =
        _sitewideDraft.pendingHeaderSettings.isNotEmpty;
    notifyListeners();
  }

  /// Update a single footer setting for live preview
  void updateFooterSetting(String key, String value) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
    _sitewideDraft.pendingFooterSettings[key] = value;
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple footer settings at once
  void updateFooterSettings(Map<String, String> settings) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
    _sitewideDraft.pendingFooterSectionOrder =
        List<String>.from(orderedIds, growable: false);
    _sitewideDraft.hasFooterChanges = true;
    debugPrint('🦶 [EditProvider] Footer section order updated (pending save)');
    notifyListeners();
  }

  /// Update pending footer link order for a section (does not save until Guardar)
  void updateFooterLinkOrder(String sectionId, List<String> orderedIds) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.footer);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.theme);
    _sitewideDraft.pendingThemeSettings[key] = value;
    _sitewideDraft.hasThemeChanges = true;
    debugPrint('🎨 [EditProvider] Theme setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple theme settings at once
  void updateThemeSettings(Map<String, String> settings) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.theme);
    _sitewideDraft.pendingThemeSettings.addAll(settings);
    _sitewideDraft.hasThemeChanges = true;
    debugPrint(
        '🎨 [EditProvider] Theme settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective header setting (pending value if exists, otherwise from
  /// settings). Mirrors [getEffectiveThemeSetting] so header consumers
  /// (storefront logo, header controls) preview the staged draft in Edit
  /// and Preview while Public keeps saved values.
  String getEffectiveHeaderSetting(String key, String defaultValue) {
    if (_sitewideDraft.pendingHeaderSettings.containsKey(key)) {
      return _sitewideDraft.pendingHeaderSettings[key]!;
    }
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.theme);
    _mergeSavedSettingsBaseline(savedSnapshot);
    _removeMatchingMapEntries(
        _sitewideDraft.pendingThemeSettings, savedSnapshot);
    _sitewideDraft.hasThemeChanges =
        _sitewideDraft.pendingThemeSettings.isNotEmpty;
    notifyListeners();
  }

  /// Update a single site-wide setting for live preview (saved with Guardar)
  void updateSiteSetting(String key, String value) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.siteSettings);
    _sitewideDraft.pendingSiteSettings[key] = value;
    _sitewideDraft.hasSiteSettingsChanges = true;
    debugPrint('🏁 [EditProvider] Site setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple site-wide settings at once (saved with Guardar)
  void updateSiteSettings(Map<String, String> settings) {
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.siteSettings);
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
    _markSitewideBucketMutation(WebsiteSitewideDraftBucket.siteSettings);
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
    _resetCanvasTouchMode();
    // A pending reveal belongs to the document that requested it. Carrying one
    // across a page/session change would scroll a new canvas to a stale id.
    _blockRevealRequest = null;
    _selectedFooterNavId = null;
    _carouselSlideSelections.clear();
    _canvasElementSelections.clear();
    _clearRenderedCanvasMeasurements();
    _renderedBlockViewports.clear();
    _inlineManipulationBlockEpochs.clear();
    _fieldWriteScopes.clear();
    _canvasFieldScopes.clear();
  }

  void _clearRenderedCanvasMeasurements() {
    _renderedCanvasSizes.clear();
    _renderedCanvasMeasurementGeneration++;
  }

  void _clearSitewideAndSeoDrafts() {
    for (final bucket in WebsiteSitewideDraftBucket.values) {
      _markSitewideBucketMutation(bucket);
    }
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
    _markPageDocumentMutation();
    _reconcileTransientCanvasSelections();
    _pageDraft.history
      ..clear()
      ..add(_deepCopyBlocks(_pageDraft.blocks));
    _pageDraft.historyIndex = 0;
  }

  void _reconcileTransientCanvasSelections() {
    final validCanvasKeys = <String>{};
    final validCanvasTargets = <WebsiteCanvasDocumentTarget>{};
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
        validCanvasTargets.add(WebsiteCanvasDocumentTarget(blockId: blockId));
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
        validCanvasTargets.add(
          WebsiteCanvasDocumentTarget(
            blockId: blockId,
            slideIndex: slideIndex,
          ),
        );
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
    _renderedCanvasSizes.removeWhere(
      (target, _) => !validCanvasTargets.contains(target),
    );
    // Chrome is exempt: it is not in `blockIds` and never will be. See
    // [_selectionStillExists].
    final selected = _selectedBlockId;
    if (selected != null &&
        !blockIds.contains(selected) &&
        WebsiteEditorChromeTarget.forSelection(selected) == null) {
      _selectedBlockId = null;
    }

    final manipulation = _canvasManipulationSession;
    if (manipulation != null &&
        !canvasManipulationAvailability(
          manipulation.mode,
          target: manipulation.target,
          viewport: manipulation.viewport,
        ).isAvailable) {
      _canvasManipulationSession = null;
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

    if (modeChanged || workspaceChanged) {
      _resetCanvasTouchMode();
      _sitewideAsyncSessionEpoch++;
    }
    _mode = mode;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    if (settingsChanged) {
      _settings = nextSettings;
      for (final bucket in WebsiteSitewideDraftBucket.values) {
        _markSitewideBucketMutation(bucket);
      }
    }

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

  /// Keeps the block selection across an `edit -> preview -> edit` excursion.
  ///
  /// Preview no longer clears it. Every consumer of [selectedBlockId] in the
  /// app is Edit-only chrome — the contextual dock, the `O-05` sheet, the
  /// inspector and its tabs, and the editable renderer, all mounted behind an
  /// `isEditMode` gate — so retaining the value cannot paint a selection on a
  /// visitor's Preview, while clearing it did three things at once: it lost the
  /// operator's place, it made the returning Edit look like the header had been
  /// selected instead, and it fed `null` straight into the durable draft
  /// snapshot, which captures [selectedBlockId] on every notification.
  ///
  /// Only re-entering Edit validates: Preview cannot mutate the document, but a
  /// reload or a revocation in between can, and a selection pointing at a block
  /// that no longer exists must resolve to no selection, never to a dangling
  /// id. Closing the editor, a revocation and a real document change keep
  /// clearing it through their own owners.
  void _dropDanglingSelectionForEdit(WebsiteEditorMode next) {
    if (next != WebsiteEditorMode.edit) return;
    final selected = _selectedBlockId;
    if (selected == null) return;
    if (_selectionStillExists(selected)) return;
    _selectedBlockId = null;
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
    if (_mode == next && _workspaceMode == WebsiteWorkspaceMode.pageEditor) {
      return;
    }
    _resetCanvasTouchMode();
    _sitewideAsyncSessionEpoch++;
    _mode = next;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _dropDanglingSelectionForEdit(next);
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
    _resetCanvasTouchMode();
    _sitewideAsyncSessionEpoch++;
    _mode = request;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    // Same retention rule as [setMode]: the URL is the other door into the very
    // same transition, and a mode toggle on web goes through this one.
    _dropDanglingSelectionForEdit(request);
    _notifyAfterFrame();
  }

  /// Set device preview mode (desktop, tablet, mobile)
  void setDevicePreviewMode(DevicePreviewMode mode) {
    final scopeChanged = mode == DevicePreviewMode.desktop &&
        _writeScope != WebsiteWriteScope.shared;
    if (_devicePreviewMode == mode && !scopeChanged) return;
    _resetCanvasTouchMode();
    _devicePreviewMode = mode;
    if (scopeChanged) _writeScope = WebsiteWriteScope.shared;
    notifyListeners();
  }

  /// Sets the default attribution shown by responsive field shells.
  ///
  /// Each field remains authoritative and applies its schema policy when it
  /// writes. Desktop is the shared/base value, so a desktop viewport can never
  /// retain a viewport-scoped default.
  void setWriteScope(WebsiteWriteScope scope) {
    final next = previewViewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : scope;
    if (_writeScope == next) return;
    _invalidateInlineManipulation();
    _writeScope = next;
    notifyListeners();
  }

  String _fieldWriteScopeKey(
    String blockId,
    String propertyKey,
    WebsiteViewport viewport,
  ) =>
      '$blockId|${viewport.name}|$propertyKey';

  /// Effective attribution for one field.
  ///
  /// The editor-level [writeScope] is only a default. Once the user chooses a
  /// scope in a ResponsiveFieldShell, that exact block/property/viewport owns
  /// its next writes independently from every neighbouring control.
  WebsiteWriteScope fieldWriteScope({
    required String blockId,
    required String propertyKey,
    required WebsiteResponsivePropertyPolicy policy,
    WebsiteViewport? viewport,
  }) {
    final targetViewport = viewport ?? previewViewport;
    if (!policy.supportsViewportOverride ||
        targetViewport == WebsiteViewport.desktop) {
      return WebsiteWriteScope.shared;
    }
    return _fieldWriteScopes[
            _fieldWriteScopeKey(blockId, propertyKey, targetViewport)] ??
        _writeScope;
  }

  /// Changes only the transient attribution of one field.
  ///
  /// This is UI state: it never creates history, dirty state or serialized
  /// data. The first actual value mutation still flows through
  /// [setBlockResponsiveProperty].
  void setFieldWriteScope({
    required String blockId,
    required String propertyKey,
    required WebsiteResponsivePropertyPolicy policy,
    required WebsiteWriteScope scope,
    WebsiteViewport? viewport,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final next = !policy.supportsViewportOverride ||
            targetViewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : scope;
    final key = _fieldWriteScopeKey(blockId, propertyKey, targetViewport);
    if (_fieldWriteScopes[key] == next) return;
    _invalidateInlineManipulation(blockId: blockId);
    _fieldWriteScopes[key] = next;
    notifyListeners();
  }

  WebsiteResponsiveFieldState<T> responsiveFieldState<T>({
    required String blockId,
    required WebsiteBlockFieldSchema schema,
    required WebsiteResponsiveDecoder<T> decode,
    WebsiteAuthoringHostClass hostClass = WebsiteAuthoringHostClass.desktop,
    WebsiteViewport? viewport,
    T? fallback,
    WebsiteLegacyResponsiveReader<T>? readLegacyOverride,
    String? unavailableReason,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final resolved = resolveBlockProperty<T>(
      blockId,
      schema.key,
      viewport: targetViewport,
      decode: decode,
      fallback: fallback,
      readLegacyOverride: readLegacyOverride,
    );
    final context = WebsiteAuthoringContext(
      hostClass: hostClass,
      previewViewport: targetViewport,
      writeScope: fieldWriteScope(
        blockId: blockId,
        propertyKey: schema.key,
        policy: schema.responsivePolicy,
        viewport: targetViewport,
      ),
    );
    return WebsiteResponsiveFieldState<T>.resolve(
      schema: schema,
      context: context,
      resolved: resolved,
      unavailableReason: unavailableReason,
    );
  }

  /// Installs a previously validated durable page draft above the current
  /// authoritative baseline.
  ///
  /// Storage parsing, retention and baseline-digest checks belong to
  /// `WebsiteEditorDraftStore`. This final mutation boundary repeats the
  /// authority and page checks immediately before touching state, refuses to
  /// overwrite a newer in-memory draft, and rebuilds history as
  /// `server baseline -> recovered draft`. A recovery therefore remains fully
  /// undoable and Discard still returns to the latest loaded/saved document.
  bool restoreDurablePageDraft({
    required WebsiteEditorCapabilitySnapshot authority,
    required List<Map<String, dynamic>> recoveredBlocks,
    required WebsiteViewport recoveredViewport,
    required WebsiteWriteScope recoveredWriteScope,
    String? recoveredSelectedBlockId,
    String? pageId,
    String? pageSlug,
  }) {
    final liveLease = _entryLease;
    final documentLease = _documentOwnerLease;
    if (liveLease == null ||
        documentLease == null ||
        !liveLease.granted ||
        liveLease.fingerprint != authority.fingerprint ||
        liveLease.authorityEpoch != authority.authorityEpoch ||
        documentLease.fingerprint != authority.fingerprint ||
        documentLease.authorityEpoch != authority.authorityEpoch) {
      throw const WebsiteEditorAuthorityException(
        'El borrador local pertenece a otra autoridad de edición.',
      );
    }
    if (!_matchesActivePage(pageId, pageSlug)) {
      throw StateError('El borrador local pertenece a otra página.');
    }
    if (_pageDraft.hasUnsavedChanges) {
      throw StateError(
        'No se puede reemplazar un borrador en memoria con otro local.',
      );
    }

    final baseline = _deepCopyBlocks(
      _pageDraft.history.isEmpty ? _pageDraft.blocks : _pageDraft.history.first,
    );
    final recovered = _deepCopyBlocks(
      sanitizeWebsiteBlocksForPersistence(recoveredBlocks),
    );
    final contentChanged = !_deepEquals(baseline, recovered);

    _pageDraft.blocks = recovered;
    _markPageDocumentMutation();
    _pageDraft.history
      ..clear()
      ..add(_deepCopyBlocks(baseline));
    if (contentChanged) {
      _pageDraft.history.add(_deepCopyBlocks(recovered));
      _pageDraft.historyIndex = 1;
    } else {
      _pageDraft.historyIndex = 0;
    }
    _pageDraft.hasUnsavedChanges = contentChanged;

    _devicePreviewMode = switch (recoveredViewport) {
      WebsiteViewport.desktop => DevicePreviewMode.desktop,
      WebsiteViewport.tablet => DevicePreviewMode.tablet,
      WebsiteViewport.mobile => DevicePreviewMode.mobile,
    };
    _writeScope = recoveredViewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : recoveredWriteScope;

    _carouselSlideSelections.clear();
    _canvasElementSelections.clear();
    final selectedId = recoveredSelectedBlockId?.trim();
    _selectedBlockId = _mode == WebsiteEditorMode.edit &&
            selectedId != null &&
            selectedId.isNotEmpty &&
            _pageDraft.blocks.any(
              (block) => block['id']?.toString() == selectedId,
            )
        ? selectedId
        : null;
    _selectionVersion++;
    _reconcileTransientCanvasSelections();
    notifyListeners();
    return contentChanged;
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
    _sitewideAsyncSessionEpoch++;
    _mode = WebsiteEditorMode.public;
    _workspaceMode = WebsiteWorkspaceMode.pageEditor;
    _selectedBlockId = null;
    _blockRevealRequest = null;
    _resetCanvasTouchMode();
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
    _resetCanvasTouchMode();
    _selectionVersion++;
    debugPrint(
        '👉 [EditProvider] Block Selected: $blockId (v$_selectionVersion)');
    notifyListeners();
  }

  WebsiteResolvedResponsiveValue<T> resolveBlockProperty<T>(
    String blockId,
    String propertyKey, {
    WebsiteViewport? viewport,
    required WebsiteResponsiveDecoder<T> decode,
    T? fallback,
    WebsiteLegacyResponsiveReader<T>? readLegacyOverride,
  }) {
    return WebsiteResponsiveDataCodec.resolve<T>(
      data: getBlockData(blockId),
      propertyKey: propertyKey,
      viewport: viewport ?? previewViewport,
      decode: decode,
      fallback: fallback,
      readLegacyOverride: readLegacyOverride,
    );
  }

  bool hasBlockResponsiveOverride(
    String blockId,
    String propertyKey, {
    WebsiteViewport? viewport,
  }) {
    return WebsiteResponsiveDataCodec.hasOverride(
      getBlockData(blockId),
      propertyKey,
      viewport ?? previewViewport,
    );
  }

  String _repeaterResponsivePropertyKey({
    required List<String> collectionKeys,
    required int itemIndex,
    required String propertyKey,
    String? identityKey,
    Object? identityValue,
  }) {
    final collection =
        collectionKeys.isEmpty ? 'collection' : collectionKeys[0];
    final item = identityKey != null && identityValue != null
        ? '$identityKey:${identityValue.toString()}'
        : 'index:$itemIndex';
    return '$collection[$item].$propertyKey';
  }

  Map<String, dynamic>? _blockRepeaterItemData(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    String? identityKey,
    Object? identityValue,
  }) {
    if (collectionKeys.isEmpty) return null;
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return null;
    final rawData = _pageDraft.blocks[blockIndex]['block_data'];
    if (rawData is! Map) return null;

    Object? source;
    for (final key in collectionKeys) {
      if (rawData.containsKey(key)) {
        source = rawData[key];
        break;
      }
    }
    if (source is! List) return null;

    var resolvedIndex = itemIndex;
    if (identityKey != null && identityValue != null) {
      final identityIndex = source.indexWhere(
        (item) => item is Map && item[identityKey] == identityValue,
      );
      if (identityIndex != -1) resolvedIndex = identityIndex;
    }
    if (resolvedIndex < 0 || resolvedIndex >= source.length) return null;
    final rawItem = source[resolvedIndex];
    return rawItem is Map ? Map<String, dynamic>.from(rawItem) : null;
  }

  WebsiteWriteScope repeaterFieldWriteScope({
    required String blockId,
    required List<String> collectionKeys,
    required int itemIndex,
    required String propertyKey,
    required WebsiteResponsivePropertyPolicy policy,
    WebsiteViewport? viewport,
    String? identityKey,
    Object? identityValue,
  }) {
    return fieldWriteScope(
      blockId: blockId,
      propertyKey: _repeaterResponsivePropertyKey(
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        propertyKey: propertyKey,
        identityKey: identityKey,
        identityValue: identityValue,
      ),
      policy: policy,
      viewport: viewport,
    );
  }

  void setRepeaterFieldWriteScope({
    required String blockId,
    required List<String> collectionKeys,
    required int itemIndex,
    required String propertyKey,
    required WebsiteResponsivePropertyPolicy policy,
    required WebsiteWriteScope scope,
    WebsiteViewport? viewport,
    String? identityKey,
    Object? identityValue,
  }) {
    setFieldWriteScope(
      blockId: blockId,
      propertyKey: _repeaterResponsivePropertyKey(
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        propertyKey: propertyKey,
        identityKey: identityKey,
        identityValue: identityValue,
      ),
      policy: policy,
      scope: scope,
      viewport: viewport,
    );
  }

  /// Resolves one responsive property owned by a slide/repeater item.
  ///
  /// The item itself owns the canonical `responsive` container. Tablet and
  /// mobile therefore inherit directly from that item's shared value, exactly
  /// like root block properties, without leaking an override to neighbouring
  /// slides that happen to use the same field key.
  WebsiteResolvedResponsiveValue<T> resolveBlockRepeaterItemProperty<T>(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required String propertyKey,
    required WebsiteResponsiveDecoder<T> decode,
    WebsiteViewport? viewport,
    T? fallback,
    WebsiteLegacyResponsiveReader<T>? readLegacyOverride,
    String? identityKey,
    Object? identityValue,
  }) {
    final item = _blockRepeaterItemData(
          blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          identityKey: identityKey,
          identityValue: identityValue,
        ) ??
        const <String, dynamic>{};
    return WebsiteResponsiveDataCodec.resolve<T>(
      data: item,
      propertyKey: propertyKey,
      viewport: viewport ?? previewViewport,
      decode: decode,
      fallback: fallback,
      readLegacyOverride: readLegacyOverride,
    );
  }

  WebsiteResponsiveFieldState<T> responsiveRepeaterFieldState<T>({
    required String blockId,
    required List<String> collectionKeys,
    required int itemIndex,
    required WebsiteBlockFieldSchema schema,
    required WebsiteResponsiveDecoder<T> decode,
    WebsiteAuthoringHostClass hostClass = WebsiteAuthoringHostClass.desktop,
    WebsiteViewport? viewport,
    T? fallback,
    WebsiteLegacyResponsiveReader<T>? readLegacyOverride,
    String? unavailableReason,
    String? identityKey,
    Object? identityValue,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final resolved = resolveBlockRepeaterItemProperty<T>(
      blockId,
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      propertyKey: schema.key,
      viewport: targetViewport,
      decode: decode,
      fallback: fallback,
      readLegacyOverride: readLegacyOverride,
      identityKey: identityKey,
      identityValue: identityValue,
    );
    return WebsiteResponsiveFieldState<T>.resolve(
      schema: schema,
      context: WebsiteAuthoringContext(
        hostClass: hostClass,
        previewViewport: targetViewport,
        writeScope: repeaterFieldWriteScope(
          blockId: blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          propertyKey: schema.key,
          policy: schema.responsivePolicy,
          viewport: targetViewport,
          identityKey: identityKey,
          identityValue: identityValue,
        ),
      ),
      resolved: resolved,
      unavailableReason: unavailableReason,
    );
  }

  bool setBlockRepeaterItemResponsiveProperty(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required String propertyKey,
    required Object? value,
    required WebsiteResponsivePropertyPolicy policy,
    WebsiteViewport? viewport,
    WebsiteWriteScope? scope,
    Set<String> displayCopyWhitelist = const {},
    String? identityKey,
    Object? identityValue,
    bool saveHistory = true,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final requestedScope = scope ??
        repeaterFieldWriteScope(
          blockId: blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          propertyKey: propertyKey,
          policy: policy,
          viewport: targetViewport,
          identityKey: identityKey,
          identityValue: identityValue,
        );
    final effectiveScope = WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: targetViewport,
      writeScope: requestedScope,
    ).effectiveWriteScope(policy);

    return _transformBlockRepeaterItemData(
      blockId,
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      identityKey: identityKey,
      identityValue: identityValue,
      saveHistory: saveHistory,
      operation: 'setBlockRepeaterItemResponsiveProperty',
      transform: (item) => effectiveScope == WebsiteWriteScope.shared
          ? WebsiteResponsiveDataCodec.setShared(
              data: item,
              propertyKey: propertyKey,
              value: value,
              policies: {propertyKey: policy},
              displayCopyWhitelist: displayCopyWhitelist,
            )
          : WebsiteResponsiveDataCodec.setForViewport(
              data: item,
              propertyKey: propertyKey,
              value: value,
              viewport: targetViewport,
              policy: policy,
              displayCopyWhitelist: displayCopyWhitelist,
            ),
    );
  }

  /// Atomically writes a related set of responsive properties on one repeater
  /// item. Focal X/Y is the primary consumer: one drag must create one history
  /// entry and one undo step, never two partially-applied coordinates.
  bool setBlockRepeaterItemResponsiveProperties(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required Map<String, Object?> values,
    required Map<String, WebsiteResponsivePropertyPolicy> policies,
    WebsiteViewport? viewport,
    WebsiteWriteScope? scope,
    Set<String> displayCopyWhitelist = const {},
    String? identityKey,
    Object? identityValue,
    bool saveHistory = true,
  }) {
    if (values.isEmpty) return false;
    final targetViewport = viewport ?? previewViewport;
    return _transformBlockRepeaterItemData(
      blockId,
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      identityKey: identityKey,
      identityValue: identityValue,
      saveHistory: saveHistory,
      operation: 'setBlockRepeaterItemResponsiveProperties',
      transform: (item) {
        var next = item;
        for (final entry in values.entries) {
          final policy = policies[entry.key];
          if (policy == null) {
            throw ArgumentError(
              'Missing responsive policy for ${entry.key}.',
            );
          }
          final requestedScope = scope ??
              repeaterFieldWriteScope(
                blockId: blockId,
                collectionKeys: collectionKeys,
                itemIndex: itemIndex,
                propertyKey: entry.key,
                policy: policy,
                viewport: targetViewport,
                identityKey: identityKey,
                identityValue: identityValue,
              );
          final effectiveScope = WebsiteAuthoringContext(
            hostClass: WebsiteAuthoringHostClass.desktop,
            previewViewport: targetViewport,
            writeScope: requestedScope,
          ).effectiveWriteScope(policy);
          next = effectiveScope == WebsiteWriteScope.shared
              ? WebsiteResponsiveDataCodec.setShared(
                  data: next,
                  propertyKey: entry.key,
                  value: entry.value,
                  policies: policies,
                  displayCopyWhitelist: displayCopyWhitelist,
                )
              : WebsiteResponsiveDataCodec.setForViewport(
                  data: next,
                  propertyKey: entry.key,
                  value: entry.value,
                  viewport: targetViewport,
                  policy: policy,
                  displayCopyWhitelist: displayCopyWhitelist,
                );
        }
        return next;
      },
    );
  }

  bool clearBlockRepeaterItemResponsiveOverride(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required String propertyKey,
    WebsiteViewport? viewport,
    Map<String, WebsiteResponsivePropertyPolicy> policies = const {},
    Set<String> displayCopyWhitelist = const {},
    Iterable<String> legacyPropertyKeys = const <String>[],
    String? identityKey,
    Object? identityValue,
    bool saveHistory = true,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final changed = _transformBlockRepeaterItemData(
      blockId,
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      identityKey: identityKey,
      identityValue: identityValue,
      saveHistory: saveHistory,
      operation: 'clearBlockRepeaterItemResponsiveOverride',
      transform: (item) {
        final next = WebsiteResponsiveDataCodec.clearOverride(
          data: item,
          propertyKey: propertyKey,
          viewport: targetViewport,
          policies: policies,
          displayCopyWhitelist: displayCopyWhitelist,
        );
        if (targetViewport == WebsiteViewport.mobile) {
          for (final legacyKey in legacyPropertyKeys) {
            next.remove(legacyKey);
          }
        }
        return next;
      },
    );
    if (changed) {
      setRepeaterFieldWriteScope(
        blockId: blockId,
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        propertyKey: propertyKey,
        policy: policies[propertyKey] ??
            WebsiteResponsivePropertyPolicy.responsiveOptional,
        scope: WebsiteWriteScope.shared,
        viewport: targetViewport,
        identityKey: identityKey,
        identityValue: identityValue,
      );
    }
    return changed;
  }

  /// Clears a related set of repeater overrides and legacy aliases as one
  /// transaction/history entry.
  bool clearBlockRepeaterItemResponsiveOverrides(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required Iterable<String> propertyKeys,
    required Map<String, WebsiteResponsivePropertyPolicy> policies,
    WebsiteViewport? viewport,
    Set<String> displayCopyWhitelist = const {},
    Map<String, Iterable<String>> legacyPropertyKeys = const {},
    String? identityKey,
    Object? identityValue,
    bool saveHistory = true,
  }) {
    final keys = propertyKeys.toList(growable: false);
    if (keys.isEmpty) return false;
    final targetViewport = viewport ?? previewViewport;
    final changed = _transformBlockRepeaterItemData(
      blockId,
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      identityKey: identityKey,
      identityValue: identityValue,
      saveHistory: saveHistory,
      operation: 'clearBlockRepeaterItemResponsiveOverrides',
      transform: (item) {
        var next = item;
        for (final propertyKey in keys) {
          next = WebsiteResponsiveDataCodec.clearOverride(
            data: next,
            propertyKey: propertyKey,
            viewport: targetViewport,
            policies: policies,
            displayCopyWhitelist: displayCopyWhitelist,
          );
          if (targetViewport == WebsiteViewport.mobile) {
            for (final legacyKey
                in legacyPropertyKeys[propertyKey] ?? const <String>[]) {
              next.remove(legacyKey);
            }
          }
        }
        return next;
      },
    );
    if (changed) {
      for (final propertyKey in keys) {
        setRepeaterFieldWriteScope(
          blockId: blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          propertyKey: propertyKey,
          policy: policies[propertyKey] ??
              WebsiteResponsivePropertyPolicy.responsiveOptional,
          scope: WebsiteWriteScope.shared,
          viewport: targetViewport,
          identityKey: identityKey,
          identityValue: identityValue,
        );
      }
    }
    return changed;
  }

  /// Writes one responsive field through the existing document transaction,
  /// history, dirty-state and save pipeline.
  ///
  /// [scope] is normally supplied by the field shell. When omitted, the
  /// editor-level value is only a default; the property policy still coerces
  /// shared-only and desktop writes to the shared/base value.
  bool setBlockResponsiveProperty(
    String blockId,
    String propertyKey,
    dynamic value, {
    required WebsiteResponsivePropertyPolicy policy,
    WebsiteViewport? viewport,
    WebsiteWriteScope? scope,
    Set<String> displayCopyWhitelist = const {},
    bool saveHistory = true,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final requestedScope = scope ??
        fieldWriteScope(
          blockId: blockId,
          propertyKey: propertyKey,
          policy: policy,
          viewport: targetViewport,
        );
    final effectiveScope = WebsiteAuthoringContext(
      hostClass: WebsiteAuthoringHostClass.desktop,
      previewViewport: targetViewport,
      writeScope: requestedScope,
    ).effectiveWriteScope(policy);

    return _transformBlockData(
      blockId,
      (current) {
        if (effectiveScope == WebsiteWriteScope.shared) {
          return WebsiteResponsiveDataCodec.setShared(
            data: current,
            propertyKey: propertyKey,
            value: value,
            policies: {propertyKey: policy},
            displayCopyWhitelist: displayCopyWhitelist,
          );
        }
        return WebsiteResponsiveDataCodec.setForViewport(
          data: current,
          propertyKey: propertyKey,
          value: value,
          viewport: targetViewport,
          policy: policy,
          displayCopyWhitelist: displayCopyWhitelist,
        );
      },
      sharedPropertyKey:
          effectiveScope == WebsiteWriteScope.shared ? propertyKey : null,
      saveHistory: saveHistory,
    );
  }

  /// Atomically writes a related set of root responsive properties.
  bool setBlockResponsiveProperties(
    String blockId,
    Map<String, Object?> values, {
    required Map<String, WebsiteResponsivePropertyPolicy> policies,
    WebsiteViewport? viewport,
    WebsiteWriteScope? scope,
    Set<String> displayCopyWhitelist = const {},
    bool saveHistory = true,
  }) {
    if (values.isEmpty) return false;
    final targetViewport = viewport ?? previewViewport;
    return _transformBlockData(
      blockId,
      (current) {
        var next = current;
        for (final entry in values.entries) {
          final policy = policies[entry.key];
          if (policy == null) {
            throw ArgumentError(
              'Missing responsive policy for ${entry.key}.',
            );
          }
          final requestedScope = scope ??
              fieldWriteScope(
                blockId: blockId,
                propertyKey: entry.key,
                policy: policy,
                viewport: targetViewport,
              );
          final effectiveScope = WebsiteAuthoringContext(
            hostClass: WebsiteAuthoringHostClass.desktop,
            previewViewport: targetViewport,
            writeScope: requestedScope,
          ).effectiveWriteScope(policy);
          next = effectiveScope == WebsiteWriteScope.shared
              ? WebsiteResponsiveDataCodec.setShared(
                  data: next,
                  propertyKey: entry.key,
                  value: entry.value,
                  policies: policies,
                  displayCopyWhitelist: displayCopyWhitelist,
                )
              : WebsiteResponsiveDataCodec.setForViewport(
                  data: next,
                  propertyKey: entry.key,
                  value: entry.value,
                  viewport: targetViewport,
                  policy: policy,
                  displayCopyWhitelist: displayCopyWhitelist,
                );
        }
        return next;
      },
      saveHistory: saveHistory,
    );
  }

  bool clearBlockResponsiveOverride(
    String blockId,
    String propertyKey, {
    WebsiteViewport? viewport,
    Map<String, WebsiteResponsivePropertyPolicy> policies = const {},
    Set<String> displayCopyWhitelist = const {},
    Iterable<String> legacyPropertyKeys = const <String>[],
    bool saveHistory = true,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final changed = _transformBlockData(
      blockId,
      (current) {
        final next = WebsiteResponsiveDataCodec.clearOverride(
          data: current,
          propertyKey: propertyKey,
          viewport: targetViewport,
          policies: policies,
          displayCopyWhitelist: displayCopyWhitelist,
        );
        if (targetViewport == WebsiteViewport.mobile) {
          for (final legacyKey in legacyPropertyKeys) {
            next.remove(legacyKey);
          }
        }
        return next;
      },
      saveHistory: saveHistory,
    );
    if (changed) {
      setFieldWriteScope(
        blockId: blockId,
        propertyKey: propertyKey,
        policy: policies[propertyKey] ??
            WebsiteResponsivePropertyPolicy.responsiveOptional,
        scope: WebsiteWriteScope.shared,
        viewport: targetViewport,
      );
    }
    return changed;
  }

  /// Clears a related set of root overrides and legacy aliases atomically.
  bool clearBlockResponsiveOverrides(
    String blockId,
    Iterable<String> propertyKeys, {
    required Map<String, WebsiteResponsivePropertyPolicy> policies,
    WebsiteViewport? viewport,
    Set<String> displayCopyWhitelist = const {},
    Map<String, Iterable<String>> legacyPropertyKeys = const {},
    bool saveHistory = true,
  }) {
    final keys = propertyKeys.toList(growable: false);
    if (keys.isEmpty) return false;
    final targetViewport = viewport ?? previewViewport;
    final changed = _transformBlockData(
      blockId,
      (current) {
        var next = current;
        for (final propertyKey in keys) {
          next = WebsiteResponsiveDataCodec.clearOverride(
            data: next,
            propertyKey: propertyKey,
            viewport: targetViewport,
            policies: policies,
            displayCopyWhitelist: displayCopyWhitelist,
          );
          if (targetViewport == WebsiteViewport.mobile) {
            for (final legacyKey
                in legacyPropertyKeys[propertyKey] ?? const <String>[]) {
              next.remove(legacyKey);
            }
          }
        }
        return next;
      },
      saveHistory: saveHistory,
    );
    if (changed) {
      for (final propertyKey in keys) {
        setFieldWriteScope(
          blockId: blockId,
          propertyKey: propertyKey,
          policy: policies[propertyKey] ??
              WebsiteResponsivePropertyPolicy.responsiveOptional,
          scope: WebsiteWriteScope.shared,
          viewport: targetViewport,
        );
      }
    }
    return changed;
  }

  bool _transformBlockData(
    String blockId,
    Map<String, dynamic> Function(Map<String, dynamic> current) transform, {
    String? sharedPropertyKey,
    bool saveHistory = true,
  }) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return false;

    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    final current = _deepCopyMap(
      Map<String, dynamic>.from(block['block_data'] ?? const {}),
    );
    final nextData = transform(current);
    if (sharedPropertyKey != null) {
      _syncDerivedActions(
        blockType: blockType,
        updatedKey: sharedPropertyKey,
        blockData: nextData,
      );
    }
    final nextBlock = sanitizeWebsiteBlockForPersistence({
      ...block,
      'block_data': nextData,
    });
    if (_deepEquals(nextBlock, block)) return false;

    _pageDraft.blocks[blockIndex] = nextBlock;
    _reconcileTransientCanvasSelections();
    if (saveHistory) {
      _saveToHistory();
    } else {
      _markPageDocumentMutation();
      _refreshPageDirtyState();
    }
    notifyListeners();
    return true;
  }

  /// Update block data without notifying listeners (for real-time drag preview)
  /// Use this during drag operations to avoid rebuilding the entire widget tree
  void updateBlockDataSilent(String blockId, String key, dynamic value) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    _resetCanvasManipulationForStructuralWrite(blockId, <String>[key]);

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
    _markPageDocumentMutation();
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    // Don't call notifyListeners() - caller is responsible for UI updates
  }

  /// Update block data
  /// [saveHistory] - Set to false for transient updates (like activeElementId changes) to avoid history pollution
  void updateBlockData(String blockId, String key, dynamic value,
      {bool saveHistory = true}) {
    // Callback-only direct-manipulation controls use this first invocation as
    // a synchronous target handshake. Binding consumes the call deliberately:
    // pointer-down must never mutate the document or create history.
    if (_bindPreparedInlineManipulation(blockId, key)) return;

    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint('⚠️ [EditProvider] updateBlockData: block $blockId not found');
      return;
    }

    _resetCanvasManipulationForStructuralWrite(blockId, <String>[key]);

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
    } else {
      _markPageDocumentMutation();
    }
    debugPrint('✅ [EditProvider] updateBlockData: blockId=$blockId, key=$key, '
        'hasUnsavedChanges=${_pageDraft.hasUnsavedChanges}');
    notifyListeners();
  }

  /// Migrates and changes one responsive-visibility value atomically.
  ///
  /// Visibility has its own breakpoint generation because changing an image,
  /// focal point or Canvas override must never change public visibility at the
  /// 620/1000 legacy canaries. Only this explicit operator action stamps the
  /// canonical 600/900 generation.
  WebsiteVisibilityUpdateOutcome updateBlockResponsiveVisibility(
    String blockId,
    String breakpoint,
    bool isVisible, {
    bool confirmLegacyMigration = false,
  }) {
    final block = _pageDraft.blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate?['id']?.toString() == blockId,
          orElse: () => null,
        );
    if (block == null) return WebsiteVisibilityUpdateOutcome.blockNotFound;
    final blockData = block['block_data'];
    final data = blockData is Map
        ? blockData.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final rawVisibility = data['visibility'];
    final generation = websiteVisibilityGeneration(rawVisibility);
    final needsConfirmation =
        generation == WebsiteVisibilityBreakpointGeneration.legacy &&
            !canMigrateWebsiteVisibilityWithoutBehaviorChange(rawVisibility);
    if (needsConfirmation && !confirmLegacyMigration) {
      return WebsiteVisibilityUpdateOutcome.requiresMigrationConfirmation;
    }
    updateBlockData(
      blockId,
      'visibility',
      updatedWebsiteBlockVisibility(
        rawVisibility,
        breakpoint: breakpoint,
        isVisible: isVisible,
        useCanonicalBreakpoints:
            generation == WebsiteVisibilityBreakpointGeneration.canonical ||
                !needsConfirmation ||
                confirmLegacyMigration,
      ),
    );
    return WebsiteVisibilityUpdateOutcome.applied;
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

    _resetCanvasManipulationForStructuralWrite(blockId, updates.keys);

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
    } else {
      _markPageDocumentMutation();
    }
    debugPrint(
        '✅ [EditProvider] updateBlockDataMultiple: blockId=$blockId, keys=${updates.keys.join(", ")}');
    notifyListeners();
  }

  bool _validRepeaterTarget(WebsiteRepeaterCollectionTarget target) {
    bool validKeys(List<String> keys) {
      return keys.isNotEmpty &&
          keys.every((key) => key.trim().isNotEmpty) &&
          keys.toSet().length == keys.length;
    }

    if (target.blockId.isEmpty ||
        !validKeys(target.collectionKeys) ||
        target.itemIdentityKey.isEmpty ||
        (target.minItems != null && target.minItems! < 0) ||
        (target.maxItems != null && target.maxItems! < 0) ||
        (target.minItems != null &&
            target.maxItems != null &&
            target.minItems! > target.maxItems!)) {
      return false;
    }
    for (final ancestor in target.ancestors) {
      if (!validKeys(ancestor.collectionKeys) ||
          ancestor.itemIdentityKey.isEmpty ||
          ancestor.item.fallbackIndex < 0) {
        return false;
      }
    }
    return true;
  }

  bool _validateRepeaterMutationLease(
    WebsiteRepeaterMutationLease expectedLease,
  ) {
    final target = expectedLease.target;
    if (_isDisposed ||
        !identical(
          expectedLease._ownerIdentity,
          _asyncIntentOwnerIdentity,
        ) ||
        _mode != WebsiteEditorMode.edit ||
        _workspaceMode != WebsiteWorkspaceMode.pageEditor ||
        _pageDraft.pageId != expectedLease.pageId ||
        _pageDraft.pageSlug != expectedLease.pageSlug ||
        _pageDraft.sessionRevision != expectedLease.documentSessionRevision ||
        _pageDocumentEpoch != expectedLease.documentEpoch ||
        _inlineManipulationStateEpoch != expectedLease.stateEpoch ||
        (_inlineManipulationBlockEpochs[target.blockId] ?? 0) !=
            expectedLease.blockStateEpoch ||
        (target.requiresSelection &&
            (_selectedBlockId != target.blockId ||
                _selectionVersion != expectedLease.selectionVersion))) {
      return false;
    }

    final block = _pageDraft.blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate?['id']?.toString() == target.blockId,
          orElse: () => null,
        );
    return block != null &&
        _deepEquals(block, expectedLease.sourceBlock) &&
        _repeaterTargetCollection(block, target) != null;
  }

  List<dynamic>? _repeaterTargetCollection(
    Map<String, dynamic> block,
    WebsiteRepeaterCollectionTarget target,
  ) {
    final rawData = block['block_data'];
    if (rawData is! Map) return null;
    var owner = rawData.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    for (final ancestor in target.ancestors) {
      final collection = _readRepeaterCollection(
        owner,
        ancestor.collectionKeys,
      );
      if (collection == null ||
          !_validRepeaterCollection(
            collection,
            identityKey: ancestor.itemIdentityKey,
          )) {
        return null;
      }
      final index = _resolveRepeaterItemIndex(
        collection,
        ancestor.item,
        identityKey: ancestor.itemIdentityKey,
      );
      if (index == null) return null;
      final rawItem = collection[index];
      if (rawItem is! Map) return null;
      owner = rawItem.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    final collection = _readRepeaterCollection(owner, target.collectionKeys);
    if (collection == null ||
        !_validRepeaterCollection(
          collection,
          identityKey: target.itemIdentityKey,
        )) {
      return null;
    }
    return collection;
  }

  List<dynamic>? _readRepeaterCollection(
    Map<String, dynamic> owner,
    List<String> collectionKeys,
  ) {
    for (final key in collectionKeys) {
      if (!owner.containsKey(key)) continue;
      final value = owner[key];
      return value is List ? value : null;
    }
    return null;
  }

  bool _validRepeaterCollection(
    List<dynamic> collection, {
    required String identityKey,
  }) {
    final identities = <Object>{};
    for (final rawItem in collection) {
      if (rawItem is! Map) return false;
      final identity = rawItem[identityKey];
      if (identity == null || identity == '') continue;
      if (!_validRepeaterIdentity(identity) || !identities.add(identity)) {
        return false;
      }
    }
    return true;
  }

  bool _validRepeaterIdentity(Object? value) {
    return value is String && value.isNotEmpty || value is num || value is bool;
  }

  int? _resolveRepeaterItemIndex(
    List<dynamic> collection,
    WebsiteRepeaterItemRef reference, {
    required String identityKey,
  }) {
    if (reference.fallbackIndex < 0) return null;
    if (reference.hasIdentity) {
      if (reference.identityKey != identityKey ||
          !_validRepeaterIdentity(reference.identityValue)) {
        return null;
      }
      final matches = <int>[];
      for (var index = 0; index < collection.length; index++) {
        final rawItem = collection[index];
        if (rawItem is Map && rawItem[identityKey] == reference.identityValue) {
          matches.add(index);
        }
      }
      return matches.length == 1 ? matches.single : null;
    }

    if (reference.fallbackIndex >= collection.length) return null;
    final rawItem = collection[reference.fallbackIndex];
    if (rawItem is! Map) return null;
    // Once an item owns a persisted identity the caller must name it. An
    // index-only reference is reserved for genuinely identity-less legacy
    // items and cannot opt out of the stronger address.
    if (_validRepeaterIdentity(rawItem[identityKey])) return null;
    return reference.fallbackIndex;
  }

  _AppliedWebsiteRepeaterMutation? _applyRepeaterMutationAtOwner(
    Map<String, dynamic> owner, {
    required WebsiteRepeaterCollectionTarget target,
    required int ancestorIndex,
    required WebsiteRepeaterCommand command,
  }) {
    if (ancestorIndex >= target.ancestors.length) {
      final source = _readRepeaterCollection(owner, target.collectionKeys);
      if (source == null ||
          !_validRepeaterCollection(
            source,
            identityKey: target.itemIdentityKey,
          )) {
        return null;
      }
      final applied = _applyRepeaterCommand(
        source,
        target: target,
        command: command,
      );
      if (applied == null || !applied.outcome.result.changed) return applied;
      final nextOwner = Map<String, dynamic>.from(owner);
      final nextCollection =
          _readRepeaterCollection(applied.owner, target.collectionKeys);
      if (nextCollection == null) return null;
      for (final key in target.collectionKeys) {
        nextOwner[key] = _deepCopyValue(nextCollection);
      }
      return _AppliedWebsiteRepeaterMutation(
        owner: nextOwner,
        outcome: applied.outcome,
      );
    }

    final ancestor = target.ancestors[ancestorIndex];
    final source = _readRepeaterCollection(owner, ancestor.collectionKeys);
    if (source == null ||
        !_validRepeaterCollection(
          source,
          identityKey: ancestor.itemIdentityKey,
        )) {
      return null;
    }
    final itemIndex = _resolveRepeaterItemIndex(
      source,
      ancestor.item,
      identityKey: ancestor.itemIdentityKey,
    );
    if (itemIndex == null) return null;
    final rawItem = source[itemIndex];
    if (rawItem is! Map) return null;
    final item = _deepCopyMap(
      rawItem.map((key, value) => MapEntry(key.toString(), value)),
    );
    final nested = _applyRepeaterMutationAtOwner(
      item,
      target: target,
      ancestorIndex: ancestorIndex + 1,
      command: command,
    );
    if (nested == null || !nested.outcome.result.changed) {
      return nested == null
          ? null
          : _AppliedWebsiteRepeaterMutation(
              owner: owner,
              outcome: nested.outcome,
            );
    }

    final nextCollection = List<dynamic>.from(
      _deepCopyValue(source) as List,
    );
    nextCollection[itemIndex] = nested.owner;
    final nextOwner = Map<String, dynamic>.from(owner);
    for (final key in ancestor.collectionKeys) {
      nextOwner[key] = _deepCopyValue(nextCollection);
    }
    return _AppliedWebsiteRepeaterMutation(
      owner: nextOwner,
      outcome: nested.outcome,
    );
  }

  _AppliedWebsiteRepeaterMutation? _applyRepeaterCommand(
    List<dynamic> source, {
    required WebsiteRepeaterCollectionTarget target,
    required WebsiteRepeaterCommand command,
  }) {
    final next = List<dynamic>.from(_deepCopyValue(source) as List);

    WebsiteRepeaterItemRef refAt(int index) {
      return target.itemRef(
        Map<String, dynamic>.from(next[index] as Map),
        index,
      );
    }

    _AppliedWebsiteRepeaterMutation result(
      WebsiteRepeaterMutationOutcome outcome,
    ) {
      final owner = <String, dynamic>{
        for (final key in target.collectionKeys) key: _deepCopyValue(next),
      };
      return _AppliedWebsiteRepeaterMutation(owner: owner, outcome: outcome);
    }

    switch (command) {
      case WebsiteRepeaterAddItem(seed: final frozenSeed):
        if (target.maxItems != null && next.length >= target.maxItems!) {
          return null;
        }
        final seed = Map<String, dynamic>.from(
          _deepCopyValue(frozenSeed) as Map,
        );
        next.add(seed);
        if (!_validRepeaterCollection(
          next,
          identityKey: target.itemIdentityKey,
        )) {
          return null;
        }
        final index = next.length - 1;
        return result(
          WebsiteRepeaterMutationOutcome.committed(
            selectionIndex: index,
            selectionItem: refAt(index),
          ),
        );

      case WebsiteRepeaterDuplicateItem(source: final sourceRef):
        if (target.maxItems != null && next.length >= target.maxItems!) {
          return null;
        }
        final sourceIndex = _resolveRepeaterItemIndex(
          next,
          sourceRef,
          identityKey: target.itemIdentityKey,
        );
        if (sourceIndex == null) return null;
        final rawSource = next[sourceIndex];
        if (rawSource is! Map) return null;
        final copy = _deepCopyMap(
          rawSource.map((key, value) => MapEntry(key.toString(), value)),
        )..remove(target.itemIdentityKey);
        final insertIndex = sourceIndex + 1;
        next.insert(insertIndex, copy);
        return result(
          WebsiteRepeaterMutationOutcome.committed(
            selectionIndex: insertIndex,
            selectionItem: refAt(insertIndex),
          ),
        );

      case WebsiteRepeaterDeleteItem(target: final itemRef):
        if (target.minItems != null && next.length <= target.minItems!) {
          return null;
        }
        final itemIndex = _resolveRepeaterItemIndex(
          next,
          itemRef,
          identityKey: target.itemIdentityKey,
        );
        if (itemIndex == null) return null;
        next.removeAt(itemIndex);
        final selectionIndex =
            next.isEmpty ? 0 : itemIndex.clamp(0, next.length - 1).toInt();
        return result(
          WebsiteRepeaterMutationOutcome.committed(
            selectionIndex: selectionIndex,
            selectionItem: next.isEmpty ? null : refAt(selectionIndex),
          ),
        );

      case WebsiteRepeaterMoveItem(
          source: final sourceRef,
          anchor: final anchorRef,
          placement: final placement,
        ):
        final sourceIndex = _resolveRepeaterItemIndex(
          next,
          sourceRef,
          identityKey: target.itemIdentityKey,
        );
        final anchorIndex = _resolveRepeaterItemIndex(
          next,
          anchorRef,
          identityKey: target.itemIdentityKey,
        );
        if (sourceIndex == null || anchorIndex == null) return null;
        if (sourceIndex == anchorIndex) {
          return result(
            WebsiteRepeaterMutationOutcome.unchanged(
              selectionIndex: sourceIndex,
              selectionItem: refAt(sourceIndex),
            ),
          );
        }
        final moved = next.removeAt(sourceIndex);
        final adjustedAnchor =
            sourceIndex < anchorIndex ? anchorIndex - 1 : anchorIndex;
        final insertIndex = placement == WebsiteRepeaterMovePlacement.before
            ? adjustedAnchor
            : adjustedAnchor + 1;
        next.insert(insertIndex, moved);
        if (_deepEquals(next, source)) {
          return result(
            WebsiteRepeaterMutationOutcome.unchanged(
              selectionIndex: sourceIndex,
              selectionItem: refAt(sourceIndex),
            ),
          );
        }
        return result(
          WebsiteRepeaterMutationOutcome.committed(
            selectionIndex: insertIndex,
            selectionItem: refAt(insertIndex),
          ),
        );

      case WebsiteRepeaterPatchItem(
          target: final itemRef,
          updates: final frozenUpdates,
        ):
        if (frozenUpdates.isEmpty) return null;
        final itemIndex = _resolveRepeaterItemIndex(
          next,
          itemRef,
          identityKey: target.itemIdentityKey,
        );
        if (itemIndex == null) return null;
        final rawItem = next[itemIndex];
        if (rawItem is! Map) return null;
        final currentItem = _deepCopyMap(
          rawItem.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (frozenUpdates.containsKey(target.itemIdentityKey) &&
            !_deepEquals(
              frozenUpdates[target.itemIdentityKey],
              currentItem[target.itemIdentityKey],
            )) {
          return null;
        }
        final nextItem = Map<String, dynamic>.from(currentItem);
        for (final entry in frozenUpdates.entries) {
          nextItem[entry.key] = _deepCopyValue(entry.value);
        }
        if (_deepEquals(currentItem, nextItem)) {
          return result(
            WebsiteRepeaterMutationOutcome.unchanged(
              selectionIndex: itemIndex,
              selectionItem: refAt(itemIndex),
            ),
          );
        }
        next[itemIndex] = nextItem;
        if (!_validRepeaterCollection(
          next,
          identityKey: target.itemIdentityKey,
        )) {
          return null;
        }
        return result(
          WebsiteRepeaterMutationOutcome.committed(
            selectionIndex: itemIndex,
            selectionItem: target.itemRef(nextItem, itemIndex),
          ),
        );
    }
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
  bool _transformBlockRepeaterItemData(
    String blockId, {
    required List<String> collectionKeys,
    required int itemIndex,
    required Map<String, dynamic> Function(Map<String, dynamic> item) transform,
    required String operation,
    String? identityKey,
    Object? identityValue,
    bool saveHistory = true,
  }) {
    if (collectionKeys.isEmpty) return false;

    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint('⚠️ [EditProvider] $operation: block $blockId not found');
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
        '⚠️ [EditProvider] $operation: '
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
        '⚠️ [EditProvider] $operation: '
        'item $resolvedIndex is outside collection bounds ${next.length}',
      );
      return false;
    }
    final rawItem = next[resolvedIndex];
    if (rawItem is! Map) {
      debugPrint(
        '⚠️ [EditProvider] $operation: item $resolvedIndex is not an object',
      );
      return false;
    }

    final currentItem = Map<String, dynamic>.from(rawItem);
    final nextItem = transform(currentItem);
    if (_deepEquals(currentItem, nextItem)) {
      debugPrint(
        'ℹ️ [EditProvider] $operation: blockId=$blockId, '
        'item=$resolvedIndex ignored (no persisted change)',
      );
      return false;
    }
    next[resolvedIndex] = nextItem;
    for (final key in collectionKeys) {
      blockData[key] = _deepCopyValue(next);
    }
    final nextBlock = sanitizeWebsiteBlockForPersistence({
      ...block,
      'block_data': blockData,
    });
    if (_deepEquals(nextBlock, block)) return false;

    _pageDraft.blocks[blockIndex] = nextBlock;
    _reconcileTransientCanvasSelections();
    _pageDraft.hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    } else {
      _markPageDocumentMutation();
    }
    debugPrint(
      '✅ [EditProvider] $operation: blockId=$blockId, '
      'collections=${collectionKeys.join(", ")}, item=$resolvedIndex',
    );
    notifyListeners();
    return true;
  }

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
    return _transformBlockRepeaterItemData(
      blockId,
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
      identityKey: identityKey,
      identityValue: identityValue,
      saveHistory: saveHistory,
      operation: 'updateBlockRepeaterItemMultiple',
      transform: (item) {
        final next = Map<String, dynamic>.from(item);
        for (final entry in updates.entries) {
          next[entry.key] = _deepCopyValue(entry.value);
        }
        return next;
      },
    );
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
  ///
  /// This is the "Agregar capa" entry point of the editor panel, and it is a
  /// structural command like every other one: it resolves the addressed
  /// document, mints an id that collides with none of its identities and
  /// inserts through [insertCanvasLayer]. It never rebuilds `elements` or
  /// `slides`, because rebuilding a whole list overwrites the responsive
  /// overrides that live inside the layers it replaces.
  ///
  /// [slideIndex] addresses one exact slide. A surface that already knows which
  /// slide it is editing passes it instead of letting the command re-derive the
  /// selection, so an inspector mounted on slide 2 can never insert into
  /// whatever slide the shared selection happens to point at.
  bool addCanvasElementToCanvasBlock(
    String canvasBlockId,
    String elementType, {
    int? slideIndex,
  }) {
    final blockIndex =
        _pageDraft.blocks.indexWhere((b) => b['id'] == canvasBlockId);
    if (blockIndex == -1) return false;
    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();

    int? targetSlide;
    int? slideCount;
    if (blockType == WebsiteBlockType.carousel.name) {
      final data = block['block_data'];
      final slides = data is Map ? data['slides'] : null;
      if (slides is! List || slides.isEmpty) return false;
      slideCount = slides.length;
      targetSlide =
          slideIndex ?? carouselSlideSelection(canvasBlockId, slides.length);
    } else if (blockType != WebsiteBlockType.canvas.name) {
      return false;
    } else if (slideIndex != null) {
      // A standalone Canvas block owns no slides; an explicit index addresses
      // nothing and must not silently fall back to the block document.
      return false;
    }

    // The document decides which identities are taken; the target validation
    // inside it is the same one every Canvas command uses.
    final document = canvasDocument(canvasBlockId, slideIndex: targetSlide);
    if (document == null) return false;

    final id = WebsiteCanvasResponsiveDocument.nextLayerId(
      document,
      seed: 'el_${DateTime.now().microsecondsSinceEpoch}',
    );
    final elements = document[WebsiteCanvasResponsivePolicy.elementsKey];
    final index = elements is List ? elements.length : 0;

    final inserted = insertCanvasLayer(
      canvasBlockId,
      createCanvasElement(id: id, type: elementType),
      slideIndex: targetSlide,
      index: index,
    );
    // Selection follows only a command that landed.
    if (!inserted) return false;

    selectCanvasElement(
      canvasBlockId,
      id,
      slideIndex: targetSlide,
      slideCount: slideCount,
    );
    return true;
  }

  // ------------------------------------------------- Canvas atomic commands
  //
  // The single write path for a Canvas document. Every command is one
  // transaction: the owner produces the next document purely, the draft
  // records one change, listeners are notified once and history gets one
  // entry. `slideIndex == null` addresses a standalone Canvas block, whose
  // document is `block_data`; any other value addresses the Canvas of that
  // carousel slide, whose document is the slide map itself. Both run the same
  // owner operation, so the resulting Canvas documents are identical.

  /// Whether this command really addresses a Canvas document.
  ///
  /// A block is a Canvas because its registered type says so, and a slide is a
  /// Canvas because it is genuinely composed — never because its JSON happens
  /// to carry an `elements` or `slides` key. Without this gate an accidental
  /// payload on an unrelated block would become writable through the Canvas
  /// policy, which is exactly the drift the block registry exists to prevent.
  bool _canvasCommandTargetIsValid(
    String blockId,
    int? slideIndex,
    String operation,
  ) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint('⚠️ [EditProvider] $operation: block $blockId not found');
      return false;
    }
    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();

    if (slideIndex == null) {
      if (blockType != WebsiteBlockType.canvas.name) {
        debugPrint(
          '⚠️ [EditProvider] $operation: block $blockId is "$blockType"; '
          'only a Canvas block owns a Canvas document',
        );
        return false;
      }
      return true;
    }

    if (blockType != WebsiteBlockType.carousel.name) {
      debugPrint(
        '⚠️ [EditProvider] $operation: block $blockId is "$blockType"; '
        'a slide index only addresses a carousel',
      );
      return false;
    }
    final blockData = block['block_data'];
    final slides = blockData is Map ? blockData['slides'] : null;
    if (slides is! List || slideIndex < 0 || slideIndex >= slides.length) {
      debugPrint(
        '⚠️ [EditProvider] $operation: slide $slideIndex is outside '
        'block $blockId',
      );
      return false;
    }
    final slide = slides[slideIndex];
    if (slide is! Map) {
      debugPrint(
        '⚠️ [EditProvider] $operation: slide $slideIndex of $blockId '
        'is not an object',
      );
      return false;
    }
    final elements = slide['elements'];
    final composed = slide['useComposition'] == true ||
        (elements is List && elements.isNotEmpty);
    if (!composed) {
      debugPrint(
        '⚠️ [EditProvider] $operation: slide $slideIndex of $blockId '
        'is not a composed Canvas',
      );
      return false;
    }
    return true;
  }

  /// Runs [operation] against the Canvas document this command addresses.
  ///
  /// The target is validated before anything is transformed, and a contract
  /// violation the owner refuses — an unusable, unknown or duplicated layer
  /// identity, or a base write of the z-order — fails closed too: the draft is
  /// not touched, no history entry is created, no listener is notified and the
  /// command reports `false` instead of tearing down the editor mid-gesture.
  bool _runCanvasCommand(
    String blockId,
    int? slideIndex,
    String operation,
    Map<String, dynamic> Function(Map<String, dynamic> document) transform,
  ) {
    if (!_canvasCommandTargetIsValid(blockId, slideIndex, operation)) {
      return false;
    }

    Map<String, dynamic>? failure;
    Map<String, dynamic> guarded(Map<String, dynamic> document) {
      try {
        return transform(document);
      } on StateError catch (error) {
        debugPrint('⚠️ [EditProvider] $operation: ${error.message}');
        failure = document;
        return document;
      }
    }

    final changed = slideIndex == null
        ? _transformBlockData(blockId, guarded)
        : _transformBlockRepeaterItemData(
            blockId,
            collectionKeys: const <String>['slides'],
            itemIndex: slideIndex,
            operation: operation,
            transform: guarded,
          );
    return failure == null && changed;
  }

  /// Writes several root properties of a Canvas document at once.
  bool setCanvasRootProperties(
    String blockId,
    Map<String, Object?> values, {
    int? slideIndex,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    if (values.isEmpty) return false;
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'setCanvasRootProperties',
      (document) => WebsiteCanvasResponsiveDocument.setRootProperties(
        data: document,
        values: values,
        scope: scope,
        viewport: viewport,
      ),
    );
  }

  /// Resets several root viewport overrides of a Canvas document at once.
  bool clearCanvasRootOverrides(
    String blockId,
    Iterable<String> keys, {
    int? slideIndex,
    required WebsiteViewport viewport,
  }) {
    final ordered = keys.toList(growable: false);
    if (ordered.isEmpty) return false;
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'clearCanvasRootOverrides',
      (document) => WebsiteCanvasResponsiveDocument.clearRootOverrides(
        data: document,
        keys: ordered,
        viewport: viewport,
      ),
    );
  }

  /// Writes several properties of ONE layer, addressed by its id.
  bool setCanvasLayerProperties(
    String blockId,
    String layerId,
    Map<String, Object?> values, {
    int? slideIndex,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    if (values.isEmpty) return false;
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'setCanvasLayerProperties',
      (document) => WebsiteCanvasResponsiveDocument.setLayerProperties(
        data: document,
        layerId: layerId,
        values: values,
        scope: scope,
        viewport: viewport,
      ),
    );
  }

  /// Resets several viewport overrides of ONE layer, addressed by its id.
  bool clearCanvasLayerOverrides(
    String blockId,
    String layerId,
    Iterable<String> keys, {
    int? slideIndex,
    required WebsiteViewport viewport,
  }) {
    final ordered = keys.toList(growable: false);
    if (ordered.isEmpty) return false;
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'clearCanvasLayerOverrides',
      (document) => WebsiteCanvasResponsiveDocument.clearLayerOverrides(
        data: document,
        layerId: layerId,
        keys: ordered,
        viewport: viewport,
      ),
    );
  }

  /// Moves ONE layer in the z-order.
  bool reorderCanvasLayer(
    String blockId,
    String layerId,
    int targetIndex, {
    int? slideIndex,
    required WebsiteWriteScope scope,
    required WebsiteViewport viewport,
  }) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'reorderCanvasLayer',
      (document) => WebsiteCanvasResponsiveDocument.reorderLayer(
        data: document,
        layerId: layerId,
        targetIndex: targetIndex,
        scope: scope,
        viewport: viewport,
      ),
    );
  }

  /// Per-field write attribution for the Canvas inspector.
  ///
  /// Transient like the selection: switching a field to "Personalizar" is an
  /// authoring intention, not a document change, so it never dirties the draft
  /// or creates history. The key is per block + slide + root/layer + property
  /// so promoting one field never promotes the next write of another.
  final Map<String, WebsiteWriteScope> _canvasFieldScopes =
      <String, WebsiteWriteScope>{};

  /// The viewport belongs to the identity: promoting a field on the phone must
  /// not promote the same field on the tablet.
  String canvasFieldScopeKey({
    required String blockId,
    int? slideIndex,
    String? layerId,
    required String propertyKey,
    required WebsiteViewport viewport,
  }) {
    return '$blockId|${viewport.name}|${slideIndex ?? 'block'}'
        '|${layerId ?? 'root'}|$propertyKey';
  }

  /// Effective attribution for one Canvas field.
  ///
  /// The editor-level [writeScope] is the default; a field that the user
  /// promoted overrides that default for itself only. Same contract as
  /// [fieldWriteScope], so the two inspectors cannot drift apart.
  WebsiteWriteScope canvasFieldScope(
    String scopeKey, {
    required WebsiteResponsivePropertyPolicy policy,
    WebsiteViewport? viewport,
  }) {
    final targetViewport = viewport ?? previewViewport;
    if (!policy.supportsViewportOverride ||
        targetViewport == WebsiteViewport.desktop) {
      return WebsiteWriteScope.shared;
    }
    return _canvasFieldScopes[scopeKey] ?? _writeScope;
  }

  /// Changes only the transient attribution of one Canvas field. Never
  /// history, dirty state or serialized data.
  void setCanvasFieldScope(
    String scopeKey,
    WebsiteWriteScope scope, {
    required WebsiteResponsivePropertyPolicy policy,
    WebsiteViewport? viewport,
  }) {
    final targetViewport = viewport ?? previewViewport;
    final next = !policy.supportsViewportOverride ||
            targetViewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : scope;
    // The entry is kept even when it equals the current default: an explicit
    // "shared" has to survive the editor default being switched to viewport.
    if (_canvasFieldScopes[scopeKey] == next) return;
    _invalidateInlineManipulation();
    _canvasFieldScopes[scopeKey] = next;
    notifyListeners();
  }

  /// The Canvas document a command addresses, or null when the target is not
  /// one. Read-only: it exists so a caller can mint a collision-safe id
  /// against the identities that document currently carries.
  Map<String, dynamic>? canvasDocument(String blockId, {int? slideIndex}) {
    if (!_canvasCommandTargetIsValid(blockId, slideIndex, 'canvasDocument')) {
      return null;
    }
    final block = _pageDraft.blocks.firstWhere((b) => b['id'] == blockId);
    final blockData =
        Map<String, dynamic>.from(block['block_data'] ?? const {});
    if (slideIndex == null) return _deepUnmodifiableMap(blockData);
    final slides = blockData['slides'] as List;
    final slide = Map<String, dynamic>.from(slides[slideIndex] as Map);
    return _deepUnmodifiableMap(
      WebsiteCanvasResponsiveDocument.carouselAuthoringDocument(
        slide: slide,
        // A binding exists only in Edit, so the provider side of the
        // transaction compares the same transient projection as the renderer.
        showGrid: true,
      ),
    );
  }

  /// Adds one canonical layer. Structure is shared across viewports.
  bool insertCanvasLayer(
    String blockId,
    Map<String, dynamic> layer, {
    int? slideIndex,
    int index = 1 << 30,
  }) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'insertCanvasLayer',
      (document) => WebsiteCanvasResponsiveDocument.insertLayer(
        data: document,
        layer: layer,
        index: index,
      ),
    );
  }

  /// Removes one identity and every responsive branch it owned.
  bool removeCanvasLayer(
    String blockId,
    String layerId, {
    int? slideIndex,
  }) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'removeCanvasLayer',
      (document) => WebsiteCanvasResponsiveDocument.removeLayer(
        data: document,
        layerId: layerId,
      ),
    );
  }

  /// Deep-copies one layer, overrides included, under a new identity.
  bool duplicateCanvasLayer(
    String blockId,
    String layerId,
    String newLayerId, {
    int? slideIndex,
  }) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'duplicateCanvasLayer',
      (document) => WebsiteCanvasResponsiveDocument.duplicateLayer(
        data: document,
        layerId: layerId,
        newLayerId: newLayerId,
      ),
    );
  }

  // ------------------------------------------------ Canvas legacy migration
  //
  // Reading never migrates. Every transition is an explicit operation with one
  // history entry, and none of them saves: the draft is what changes, and the
  // owner decides when a draft becomes a published page.

  /// The read-only verdict for the Canvas this command addresses.
  ///
  /// Pure: it inspects, it never normalises, dirties or notifies. Null when the
  /// target is not a Canvas document at all.
  WebsiteCanvasMigrationStatus? canvasMigrationStatus(
    String blockId, {
    int? slideIndex,
  }) {
    final document = canvasDocument(blockId, slideIndex: slideIndex);
    if (document == null) return null;
    return WebsiteCanvasMigration.inspect(document);
  }

  /// Merges the legacy twins of a document that needs NO judgement call.
  ///
  /// Fails closed on anything else. A partial migration is a real capability of
  /// the pure owner, but persisting one would stamp provenance — and therefore
  /// silence a later `analyze` — on a document whose ambiguous layers still
  /// carry their legacy flags. The operator resolves those deliberately with
  /// [migrateCanvasDocumentKeepingLayers].
  bool migrateCanvasDocument(String blockId, {int? slideIndex}) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'migrateCanvasDocument',
      (document) {
        final result = WebsiteCanvasMigration.migrate(document);
        if (result.issues.isNotEmpty) {
          throw StateError(
            'this Canvas needs a decision first: '
            '${result.issues.map((issue) => issue.code.name).join(", ")}',
          );
        }
        if (WebsiteCanvasMigration.carriesLegacyLayerFlags(result.document)) {
          throw StateError(
            'the migrated document still carries legacy visibility flags',
          );
        }
        return result.document;
      },
    );
  }

  /// The deliberate resolution of an AMBIGUOUS document: merge what is safe and
  /// keep every ambiguous layer as its own canonical identity.
  ///
  /// Nothing is chosen for the operator — no winning copy, destination, type or
  /// order — and no legacy flag survives, so the canonical marker this stamps
  /// is true. Refuses a conflicting identity, where addressing and rollback
  /// cannot be guaranteed.
  bool migrateCanvasDocumentKeepingLayers(String blockId, {int? slideIndex}) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'migrateCanvasDocumentKeepingLayers',
      (document) {
        final result = WebsiteCanvasMigration.migrateKeepDistinct(document);
        if (!result.changed) {
          throw StateError(
            'this Canvas cannot be migrated from here: '
            '${result.issues.map((issue) => issue.code.name).join(", ")}',
          );
        }
        if (WebsiteCanvasMigration.carriesLegacyLayerFlags(result.document)) {
          throw StateError(
            'the migrated document still carries legacy visibility flags',
          );
        }
        return result.document;
      },
    );
  }

  /// Restores the exact document a migration came from.
  ///
  /// Requires provenance: without it there is nothing to restore, and inventing
  /// a legacy shape would be a second migration in the opposite direction.
  bool restoreCanvasLegacyDocument(String blockId, {int? slideIndex}) {
    return _runCanvasCommand(
      blockId,
      slideIndex,
      'restoreCanvasLegacyDocument',
      (document) {
        if (WebsiteCanvasMigration.inspect(document).state !=
            WebsiteCanvasMigrationState.migrated) {
          throw StateError('this Canvas has no migration to undo');
        }
        return WebsiteCanvasMigration.expandToLegacy(document);
      },
    );
  }

  /// Turns a Carousel slide into a CANONICAL composed Canvas, in one operation.
  ///
  /// "Diseño avanzado por capas" used to inject a whole `elements` list holding
  /// a `_desktop`/`_mobile` twin per semantic element, each one arbitrated by
  /// the contradictory `hideOnMobile`/`showOnMobile` pair. That is exactly the
  /// model 7A replaced, and generating more of it would mean authoring new
  /// documents that immediately need a migration.
  ///
  /// So the slide starts life canonical: one identity per semantic element —
  /// title, subtitle, call to action — carrying the desktop values as its
  /// shared base and the phone values as a typed `responsive.mobile` override.
  /// No value is invented; the two geometries are the ones the twin generator
  /// already used, now attributed to one identity instead of two.
  ///
  /// It fails closed on a slide that already has layers: overwriting an
  /// authored composition is a destructive rewrite, not an initialisation.
  bool initializeCanvasComposition(
    String blockId, {
    required int slideIndex,
  }) {
    final blockIndex = _pageDraft.blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint(
        '⚠️ [EditProvider] initializeCanvasComposition: '
        'block $blockId not found',
      );
      return false;
    }
    final block = _pageDraft.blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    if (blockType != WebsiteBlockType.carousel.name) {
      debugPrint(
        '⚠️ [EditProvider] initializeCanvasComposition: block $blockId is '
        '"$blockType"; only a carousel slide is composed into a Canvas',
      );
      return false;
    }
    final blockData = block['block_data'];
    final slides = blockData is Map ? blockData['slides'] : null;
    if (slides is! List || slideIndex < 0 || slideIndex >= slides.length) {
      debugPrint(
        '⚠️ [EditProvider] initializeCanvasComposition: slide $slideIndex is '
        'outside block $blockId',
      );
      return false;
    }
    final slide = slides[slideIndex];
    if (slide is! Map) return false;
    final existing = slide[WebsiteCanvasResponsivePolicy.elementsKey];
    if (existing is List && existing.isNotEmpty) {
      debugPrint(
        'ℹ️ [EditProvider] initializeCanvasComposition: slide $slideIndex of '
        '$blockId already owns layers',
      );
      return false;
    }

    return _transformBlockRepeaterItemData(
      blockId,
      collectionKeys: const <String>['slides'],
      itemIndex: slideIndex,
      operation: 'initializeCanvasComposition',
      transform: _composedCanvasSlide,
    );
  }

  /// The canonical composed document for [slide]. Pure.
  static Map<String, dynamic> _composedCanvasSlide(Map<String, dynamic> slide) {
    final title = (slide['title'] ?? 'Título del banner').toString();
    final subtitle = (slide['subtitle'] ?? '').toString();
    final action = WebsiteActionValue.resolvePrimary(
          slide,
          labelKeys: const ['ctaText', 'buttonText'],
          hrefKeys: const ['ctaLink', 'buttonLink'],
          defaultLabel: 'Ver más',
          defaultHref: '/productos',
          defaultVariant: WebsiteActionVariant.outline,
        ) ??
        const WebsiteActionValue(
          label: 'Ver más',
          href: '/productos',
          variant: WebsiteActionVariant.outline,
        );

    Map<String, dynamic> textLayer({
      required String id,
      required String text,
      required double x,
      required double y,
      required double w,
      required double h,
      required double fontSize,
      String fontRole = 'heading',
      String fontWeight = 'w700',
    }) {
      return <String, dynamic>{
        ...createCanvasElement(id: id, type: 'text', x: x, y: y),
        'w': w,
        'h': h,
        'text': text,
        'fontSize': fontSize,
        'fontWeight': fontWeight,
        'fontRole': fontRole,
        'color': '#FFFFFF',
        'align': 'left',
        'lineHeight': 1.05,
        'letterSpacing': fontRole == 'heading' ? 1.0 : 0.0,
      };
    }

    const titleId = 'title';
    const subtitleId = 'subtitle';
    const ctaId = 'cta';

    final layers = <Map<String, dynamic>>[
      textLayer(
        id: titleId,
        text: title,
        x: 120,
        y: 190,
        w: 620,
        h: 130,
        fontSize: 58,
      ),
      if (subtitle.isNotEmpty)
        textLayer(
          id: subtitleId,
          text: subtitle,
          x: 120,
          y: 330,
          w: 560,
          h: 80,
          fontSize: 22,
          fontRole: 'body',
          fontWeight: 'w400',
        ),
      <String, dynamic>{
        ...createCanvasElement(id: ctaId, type: 'button', x: 120, y: 430),
        'w': 220.0,
        'h': 56.0,
        'label': action.label,
        'link': action.href,
        'style': action.variant.storageValue,
        'inheritTheme': true,
        'actions': WebsiteActionValue.mergePrimary(null, action),
      },
    ];

    var document = <String, dynamic>{
      ...slide,
      'useComposition': true,
      'designWidth': 1200.0,
      'constrainElementsToSafeArea': true,
      WebsiteCanvasResponsivePolicy.elementsKey: layers,
    };

    // The phone geometry is an EXCEPTION of the same identity, written through
    // the owner so it lands where the projection reads it.
    document = WebsiteCanvasResponsiveDocument.setRootProperties(
      data: document,
      values: const <String, Object?>{'designWidth': 390.0},
      scope: WebsiteWriteScope.viewport,
      viewport: WebsiteViewport.mobile,
    );
    const mobileGeometry = <String, Map<String, Object?>>{
      titleId: <String, Object?>{
        'x': 28.0,
        'y': 160.0,
        'w': 334.0,
        'h': 150.0,
        'fontSize': 42.0,
      },
      subtitleId: <String, Object?>{
        'x': 28.0,
        'y': 320.0,
        'w': 334.0,
        'h': 90.0,
        'fontSize': 18.0,
      },
      ctaId: <String, Object?>{'x': 28.0, 'y': 440.0},
    };
    for (final entry in mobileGeometry.entries) {
      if (!layers.any((layer) => layer['id'] == entry.key)) continue;
      document = WebsiteCanvasResponsiveDocument.setLayerProperties(
        data: document,
        layerId: entry.key,
        values: entry.value,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
    }

    return WebsiteCanvasResponsiveDocument.markCanonical(document);
  }

  /// Save current state to history
  void _saveToHistory() {
    _pageDraft.blocks = _deepCopyBlocks(_pageDraft.blocks);
    _markPageDocumentMutation();
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

    _refreshPageDirtyState();

    debugPrint('💾 [EditProvider] Saved to history: '
        'index=${_pageDraft.historyIndex}, '
        'total=${_pageDraft.history.length}, '
        'canUndo=$canUndo, canRedo=$canRedo');
  }

  /// Undo last change
  void undo() {
    finalizeActiveContinuousFieldEdit();
    if (!canUndo) return;

    _pageDraft.historyIndex--;
    _pageDraft.blocks =
        _deepCopyBlocks(_pageDraft.history[_pageDraft.historyIndex]);
    _markPageDocumentMutation();
    _reconcileTransientCanvasSelections();
    _refreshPageDirtyState();
    // Reverting a move is itself a move: the operator has to see the restored
    // order, not infer it. `_reconcileTransientCanvasSelections` already
    // dropped a selection the step deleted, so this asks only for a block the
    // restored document still contains.
    _requestSelectedBlockRevealIfPresent();
    debugPrint(
      '⏪ [EditProvider] Undo: index=${_pageDraft.historyIndex}',
    );
    notifyListeners();
  }

  /// Redo last undone change
  void redo() {
    finalizeActiveContinuousFieldEdit();
    if (!canRedo) return;

    _pageDraft.historyIndex++;
    _pageDraft.blocks =
        _deepCopyBlocks(_pageDraft.history[_pageDraft.historyIndex]);
    _markPageDocumentMutation();
    _reconcileTransientCanvasSelections();
    _refreshPageDirtyState();
    _requestSelectedBlockRevealIfPresent();
    debugPrint(
      '⏩ [EditProvider] Redo: index=${_pageDraft.historyIndex}',
    );
    notifyListeners();
  }

  void _refreshPageDirtyState() {
    if (_pageDraft.history.isEmpty) {
      _pageDraft.hasUnsavedChanges = _pageDraft.blocks.isNotEmpty;
      return;
    }
    _pageDraft.hasUnsavedChanges =
        !_deepEquals(_pageDraft.blocks, _pageDraft.history.first);
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
    // The operation succeeded; the operator must be able to see it. On the
    // contextual host the dock is the only other channel and it keeps naming
    // the same block, so without this a move reads as "nothing happened".
    _requestBlockReveal(blockId);
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
    _requestBlockReveal(blockId);
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
    final movedId = item['id']?.toString();
    if (movedId != null && movedId.isNotEmpty) _requestBlockReveal(movedId);
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
    // t11b: after inserting, "el lienzo lo deja visible". Inserting displaces
    // the page exactly like a move does, and the new block can land off-screen
    // — so it asks for the same reveal, through the same owner, instead of the
    // insertion path growing a scrolling rule of its own.
    final insertedId = newBlock['id']?.toString();
    if (insertedId != null && insertedId.isNotEmpty) {
      _requestBlockReveal(insertedId);
    }
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
  int headerEpoch = 0;
  bool hasHeaderChanges = false;
  Map<String, String> pendingHeaderSettings = {};

  int siteSettingsEpoch = 0;
  bool hasSiteSettingsChanges = false;
  Map<String, String> pendingSiteSettings = {};

  int footerEpoch = 0;
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

  int themeEpoch = 0;
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
